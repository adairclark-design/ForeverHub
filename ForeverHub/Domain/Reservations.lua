local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.Domain = ns.Domain or {}
local Reservations = {}
ns.Domain.Reservations = Reservations

Reservations.__cachedKey = nil
Reservations.__cachedLedger = nil

local function getCounts(inventorySnapshot, itemID)
  local c = inventorySnapshot and inventorySnapshot[itemID]
  if not c then
    return 0, 0, 0, 0, 0
  end
  if type(c) == "number" then
    return math.max(0, math.floor(c)), 0, 0, 0, 0
  end
  local bag = math.max(0, math.floor(tonumber(c.bagCount) or 0))
  local bank = math.max(0, math.floor(tonumber(c.bankCount) or 0))
  local altElig = math.max(0, math.floor(tonumber(c.altEligibleCount or c.altCount) or 0))
  local altUnk = math.max(0, math.floor(tonumber(c.altUnknownCount) or 0))
  local altInelig = math.max(0, math.floor(tonumber(c.altIneligibleCount) or 0))
  return bag, bank, altElig, altUnk, altInelig
end

local function isHigherPriority(resA, cutoffPriority, cutoffGoalKey)
  local pA = tonumber(resA.priority) or 999999
  if pA ~= cutoffPriority then
    return pA < cutoffPriority
  end
  return tostring(resA.goalKey or resA.goalID) < tostring(cutoffGoalKey)
end

local function isPositiveInt(v)
  return type(v) == "number" and v == v and v >= 1 and v < 9007199254740992 and math.floor(v) == v
end

-- Stage 7B.1 (`P0-8`): Incomplete or linked `craft` reservations fail closed and NEVER allocate or shop!
local function isExecutableCraftReservation(res)
  if type(res) ~= "table" then
    return false
  end
  if res.kind ~= "craft" then
    return true
  end
  if res.scanComplete ~= true or res.learnedRecipeVerified ~= true then
    return false
  end
  if not isPositiveInt(tonumber(res.skillLineID)) or not isPositiveInt(tonumber(res.spellID or res.spellOrRecipeID)) then
    return false
  end
  local mats = (type(res.unitMaterials) == "table" and #res.unitMaterials > 0 and res.unitMaterials)
    or (type(res.materials) == "table" and #res.materials > 0 and res.materials)
    or nil
  if not mats then
    return false
  end
  for _, m in ipairs(mats) do
    if type(m) ~= "table" or not isPositiveInt(tonumber(m.itemID)) or not isPositiveInt(tonumber(m.quantity or m.unitQuantity)) then
      return false
    end
  end
  return true
end

-- Computes deterministic priority-ordered reservation ledger.
-- If `upToPriorityGoalKey` (e.g. "crate:248684") is provided:
--   * If `upToPriorityGoalKey` is already reserved at priority P, ONLY goals strictly higher priority than (P, goalKey)
--     allocate before it. Lower-priority goals (> P) and `upToPriorityGoalKey` itself do NOT allocate before it.
--   * If `upToPriorityGoalKey` is not reserved, all existing reservations allocate before it.
-- This guarantees that evaluating an existing goal (or switching its option/quantity) preserves its priority.
function Reservations.BuildAllocationLedger(inventorySnapshot, orderedReservations, upToPriorityGoalKey, explicitIncludeAlt)
  local useCache = (inventorySnapshot == nil and orderedReservations == nil and upToPriorityGoalKey == nil and explicitIncludeAlt == nil)
  local includeAltStock = explicitIncludeAlt
  if includeAltStock == nil then
    includeAltStock = (ns.State and ns.State.GetIncludeAltStock and ns.State.GetIncludeAltStock()) or false
  end

  if useCache then
    local invRev, resRev = 1, 1
    if ns.State and ns.State.GetRevisions then
      invRev, resRev = ns.State.GetRevisions()
    end
    local cacheKey = string.format("%d:%d:%s", invRev, resRev, includeAltStock and "1" or "0")
    if Reservations.__cachedLedger and Reservations.__cachedKey == cacheKey then
      return Reservations.__cachedLedger
    end
    inventorySnapshot = (ns.Providers.Inventory and ns.Providers.Inventory.GetAggregatedSnapshot()) or {}
    orderedReservations = (ns.State and ns.State.GetOrderedReservations()) or {}
    local built = Reservations.BuildAllocationLedger(inventorySnapshot, orderedReservations, nil, includeAltStock)
    Reservations.__cachedKey = cacheKey
    Reservations.__cachedLedger = built
    return built
  end

  inventorySnapshot = inventorySnapshot or (ns.Providers.Inventory and ns.Providers.Inventory.GetAggregatedSnapshot()) or {}
  orderedReservations = orderedReservations or (ns.State and ns.State.GetOrderedReservations()) or {}

  local cutoffPriority = nil
  local cutoffGoalKey = nil
  if upToPriorityGoalKey ~= nil then
    for _, res in ipairs(orderedReservations) do
      local gKey = res.goalKey or string.format("%s:%d", tostring(res.kind or "crate"), tonumber(res.targetItemID) or 0)
      if gKey == upToPriorityGoalKey then
        cutoffPriority = tonumber(res.priority) or 999999
        cutoffGoalKey = gKey
        break
      end
    end
  end

  local byItem = {}
  local function ensureItem(itemID)
    local entry = byItem[itemID]
    if not entry then
      local bag, bank, altElig, altUnk, altInelig = getCounts(inventorySnapshot, itemID)
      local charOwned = bag + bank
      local usableAlt = includeAltStock and altElig or 0
      entry = {
        itemID = itemID,
        bagCount = bag,
        bankCount = bank,
        charOwned = charOwned,
        altEligibleCount = altElig,
        altUnknownCount = altUnk,
        altIneligibleCount = altInelig,
        totalOwned = charOwned + usableAlt,
        freeBags = bag,
        freeBank = bank,
        freeAltEligible = usableAlt,
        freeTransfer = bank + usableAlt,
        reservedTotal = 0,
        reservedAllocatedBags = 0,
        reservedAllocatedBank = 0,
        reservedAllocatedAlt = 0,
        reservedAllocatedTransfer = 0,
        reservedShortfall = 0,
        goals = {},
      }
      byItem[itemID] = entry
    end
    return entry
  end

  for _, res in ipairs(orderedReservations) do
    if type(res) == "table" then
      local gKey = res.goalKey or string.format("%s:%d", tostring(res.kind or "crate"), tonumber(res.targetItemID) or 0)
      local shouldInclude = isExecutableCraftReservation(res)
      if shouldInclude and upToPriorityGoalKey ~= nil then
        if gKey == upToPriorityGoalKey then
          shouldInclude = false
        elseif cutoffPriority ~= nil and not isHigherPriority(res, cutoffPriority, cutoffGoalKey) then
          shouldInclude = false
        end
      end

      if shouldInclude then
        local goalQty = math.max(1, math.floor(tonumber(res.quantity) or 1))
        local matList = res.materials or {}
        if res.unitMaterials and #res.unitMaterials > 0 then
          matList = {}
          for _, um in ipairs(res.unitMaterials) do
            local uq = math.max(1, math.floor(tonumber(um.quantity) or 1))
            table.insert(matList, {
              itemID = um.itemID,
              name = um.name,
              unitQuantity = uq,
              quantity = uq * goalQty,
            })
          end
        end

        for _, mat in ipairs(matList) do
          local itemID = tonumber(mat.itemID)
          local reqQty = math.max(0, math.floor(tonumber(mat.quantity) or 0))
          if itemID and reqQty > 0 then
            local e = ensureItem(itemID)
            local allocBags = math.min(reqQty, e.freeBags)
            local rem1 = reqQty - allocBags
            local allocBank = math.min(rem1, e.freeBank)
            local rem2 = rem1 - allocBank
            local allocAlt = includeAltStock and math.min(rem2, e.freeAltEligible) or 0
            local shortfall = rem2 - allocAlt

            e.freeBags = e.freeBags - allocBags
            e.freeBank = e.freeBank - allocBank
            e.freeAltEligible = e.freeAltEligible - allocAlt
            e.freeTransfer = e.freeBank + e.freeAltEligible

            e.reservedTotal = e.reservedTotal + reqQty
            e.reservedAllocatedBags = e.reservedAllocatedBags + allocBags
            e.reservedAllocatedBank = e.reservedAllocatedBank + allocBank
            e.reservedAllocatedAlt = e.reservedAllocatedAlt + allocAlt
            e.reservedAllocatedTransfer = e.reservedAllocatedBank + e.reservedAllocatedAlt
            e.reservedShortfall = e.reservedShortfall + shortfall

            table.insert(e.goals, {
              goalKey = gKey,
              goalID = res.goalID or string.format("%s:%d", gKey, tonumber(res.optionIndex) or 1),
              kind = res.kind or "crate",
              targetItemID = res.targetItemID,
              targetName = res.targetName or tostring(gKey),
              optionIndex = res.optionIndex or 1,
              quantity = goalQty,
              priority = res.priority or 1,
              requiredQty = reqQty,
              allocatedBags = allocBags,
              allocatedBank = allocBank,
              allocatedAlt = allocAlt,
              allocatedTransfer = allocBank + allocAlt,
              allocatedQty = allocBags + allocBank + allocAlt,
              shortfallQty = shortfall,
            })
          end
        end
      end
    end
  end

  return {
    byItem = byItem,
    inventorySnapshot = inventorySnapshot,
    includeAltStock = includeAltStock,
  }
end

-- Computes how replacing `goalKey` at its existing priority with `candidateOptionIndex` and
-- `candidateQuantity` affects lower-priority reservations in the full allocation ledger.
-- Kept strictly separate from higher-priority `consumesReservedStock` conflicts.
function Reservations.ComputeDownstreamDisplacement(
  inventorySnapshot,
  orderedReservations,
  goalKey,
  candidateOptionIndex,
  candidateQuantity,
  candidateUnitMaterials,
  explicitIncludeAlt
)
  local includeAltStock = explicitIncludeAlt
  if includeAltStock == nil then
    includeAltStock = (ns.State and ns.State.GetIncludeAltStock and ns.State.GetIncludeAltStock()) or false
  end

  orderedReservations = orderedReservations or (ns.State and ns.State.GetOrderedReservations and ns.State.GetOrderedReservations()) or {}
  local existing = nil
  for _, r in ipairs(orderedReservations) do
    local rKey = r.goalKey or string.format("%s:%d", tostring(r.kind or "crate"), tonumber(r.targetItemID) or 0)
    if rKey == goalKey then
      existing = r
      break
    end
  end

  if not existing or #orderedReservations <= 1 then
    return {
      displacesLowerPriorityStock = false,
      displacedLowerPriorityUnits = 0,
      displacedGoalKeys = {},
      displacedGoals = {},
      displacementWarning = nil,
    }
  end

  local beforeLedger = Reservations.BuildAllocationLedger(inventorySnapshot, orderedReservations, nil, includeAltStock)

  local candidateList = {}
  local q = math.max(1, math.floor(tonumber(candidateQuantity) or 1))
  for _, r in ipairs(orderedReservations) do
    local rKey = r.goalKey or string.format("%s:%d", tostring(r.kind or "crate"), tonumber(r.targetItemID) or 0)
    if rKey == goalKey then
      local uMats = {}
      for _, m in ipairs(candidateUnitMaterials or {}) do
        table.insert(uMats, {
          itemID = tonumber(m.itemID),
          name = m.name,
          quantity = math.max(1, math.floor(tonumber(m.quantity) or 1)),
        })
      end
      table.insert(candidateList, {
        ownerKey = r.ownerKey,
        goalKey = goalKey,
        goalID = string.format("%s:%d", goalKey, tonumber(candidateOptionIndex) or 1),
        kind = r.kind or "crate",
        targetItemID = r.targetItemID,
        targetName = r.targetName or goalKey,
        optionIndex = tonumber(candidateOptionIndex) or 1,
        quantity = q,
        priority = r.priority or 1,
        unitMaterials = uMats,
      })
    else
      table.insert(candidateList, r)
    end
  end

  local afterLedger = Reservations.BuildAllocationLedger(inventorySnapshot, candidateList, nil, includeAltStock)

  local beforeByGoalItem = {}
  for itemID, entry in pairs(beforeLedger.byItem or {}) do
    for _, g in ipairs(entry.goals or {}) do
      if g.goalKey ~= goalKey then
        beforeByGoalItem[string.format("%s|%d", tostring(g.goalKey), tonumber(itemID) or 0)] = g
      end
    end
  end

  local displacedGoals = {}
  local displacedGoalKeys = {}
  local seenDisplacedKey = {}
  local totalDisplacedUnits = 0

  local sortedItemIDs = {}
  for itemID, _ in pairs(afterLedger.byItem or {}) do
    table.insert(sortedItemIDs, itemID)
  end
  table.sort(sortedItemIDs)

  for _, itemID in ipairs(sortedItemIDs) do
    local entry = afterLedger.byItem[itemID]
    for _, gAfter in ipairs(entry.goals or {}) do
      local gKey = tostring(gAfter.goalKey)
      if gKey ~= goalKey then
        local gBefore = beforeByGoalItem[string.format("%s|%d", gKey, tonumber(itemID) or 0)]
        local beforeAlloc = gBefore and (tonumber(gBefore.allocatedQty) or 0) or (tonumber(gAfter.requiredQty) or 0)
        local afterAlloc = tonumber(gAfter.allocatedQty) or 0
        local beforeShort = gBefore and (tonumber(gBefore.shortfallQty) or 0) or 0
        local afterShort = tonumber(gAfter.shortfallQty) or 0
        local displacedUnits = math.max(0, beforeAlloc - afterAlloc, afterShort - beforeShort)
        if displacedUnits > 0 then
          totalDisplacedUnits = totalDisplacedUnits + displacedUnits
          if not seenDisplacedKey[gKey] then
            seenDisplacedKey[gKey] = true
            table.insert(displacedGoalKeys, gKey)
          end
          table.insert(displacedGoals, {
            goalKey = gKey,
            targetName = tostring(gAfter.targetName or gKey),
            priority = tonumber(gAfter.priority) or 1,
            itemID = itemID,
            displacedUnits = displacedUnits,
            shortfallIncrease = math.max(0, afterShort - beforeShort),
          })
        end
      end
    end
  end

  local warning = nil
  if totalDisplacedUnits > 0 then
    if #displacedGoals == 1 then
      local dg = displacedGoals[1]
      warning = string.format(
        "This change displaces %d reserved stock from lower-priority goal (%s).",
        dg.displacedUnits,
        dg.targetName
      )
    else
      warning = string.format(
        "This change displaces %d reserved stock across %d lower-priority goals.",
        totalDisplacedUnits,
        #displacedGoalKeys
      )
    end
  end

  return {
    displacesLowerPriorityStock = (totalDisplacedUnits > 0),
    displacedLowerPriorityUnits = totalDisplacedUnits,
    displacedGoalKeys = displacedGoalKeys,
    displacedGoals = displacedGoals,
    displacementWarning = warning,
  }
end

function Reservations.GetMaterialStatus(itemID, inventorySnapshot, orderedReservations, upToPriorityGoalKey, explicitIncludeAlt)
  itemID = tonumber(itemID)
  local ledger = Reservations.BuildAllocationLedger(inventorySnapshot, orderedReservations, upToPriorityGoalKey, explicitIncludeAlt)
  local entry = ledger.byItem[itemID]
  if not entry then
    local bag, bank, altElig, altUnk, altInelig = getCounts(ledger.inventorySnapshot, itemID)
    local charOwned = bag + bank
    local usableAlt = ledger.includeAltStock and altElig or 0
    entry = {
      itemID = itemID,
      bagCount = bag,
      bankCount = bank,
      charOwned = charOwned,
      altEligibleCount = altElig,
      altUnknownCount = altUnk,
      altIneligibleCount = altInelig,
      totalOwned = charOwned + usableAlt,
      freeBags = bag,
      freeBank = bank,
      freeAltEligible = usableAlt,
      freeTransfer = bank + usableAlt,
      reservedTotal = 0,
      reservedAllocatedBags = 0,
      reservedAllocatedBank = 0,
      reservedAllocatedAlt = 0,
      reservedAllocatedTransfer = 0,
      reservedShortfall = 0,
      goals = {},
    }
  end

  local unreservedTotal = entry.freeBags + entry.freeTransfer
  local reservedAllocated = entry.reservedAllocatedBags + entry.reservedAllocatedTransfer
  local retrieveQty = entry.reservedAllocatedTransfer
  local buyAfterBankQty = entry.reservedShortfall
  local buyBagsOnlyQty = math.max(0, entry.reservedTotal - entry.bagCount)

  local summaryText
  if entry.reservedTotal > 0 then
    local goalDesc
    if #entry.goals == 1 then
      local g = entry.goals[1]
      local turnInTag = (g.quantity and g.quantity > 1) and string.format(" x%d", g.quantity) or ""
      goalDesc = string.format("your selected %s (%s%s)", g.kind == "writ" and "writ" or "crate", g.targetName, turnInTag)
    else
      goalDesc = string.format("%d selected goals", #entry.goals)
    end

    if entry.reservedShortfall > 0 then
      summaryText = string.format(
        "You have %d (%d bags, %d bank). Reserve %d for %s (Retrieve %d, Buy %d). %d remain unreserved.",
        entry.totalOwned,
        entry.bagCount,
        entry.bankCount,
        entry.reservedTotal,
        goalDesc,
        retrieveQty,
        buyAfterBankQty,
        unreservedTotal
      )
    else
      summaryText = string.format(
        "You have %d. Reserve %d for %s. %d remain unreserved.",
        entry.totalOwned,
        entry.reservedTotal,
        goalDesc,
        unreservedTotal
      )
    end
  else
    summaryText = string.format(
      "You have %d (%d bags, %d bank). %d remain unreserved.",
      entry.totalOwned,
      entry.bagCount,
      entry.bankCount,
      unreservedTotal
    )
  end

  local altBoundaryNote = nil
  if ledger.includeAltStock and entry.altEligibleCount > 0 then
    altBoundaryNote = "Alt stock is uncommitted estimated supply (not reconciled against that alt's own reservations)."
  end

  return {
    itemID = itemID,
    bagCount = entry.bagCount,
    bankCount = entry.bankCount,
    charOwned = entry.charOwned,
    altEligibleCount = entry.altEligibleCount,
    altUnknownCount = entry.altUnknownCount,
    altIneligibleCount = entry.altIneligibleCount,
    totalOwned = entry.totalOwned,
    freeBags = entry.freeBags,
    freeBank = entry.freeBank,
    freeAltEligible = entry.freeAltEligible,
    freeTransfer = entry.freeTransfer,
    unreservedBags = entry.freeBags,
    unreservedTotal = unreservedTotal,
    reservedTotal = entry.reservedTotal,
    reservedAllocated = reservedAllocated,
    reservedShortfall = entry.reservedShortfall,
    reservedQty = entry.reservedTotal,
    retrieveQty = retrieveQty,
    buyAfterBankQty = buyAfterBankQty,
    buyBagsOnlyQty = buyBagsOnlyQty,
    goals = entry.goals,
    summaryText = summaryText,
    altBoundaryNote = altBoundaryNote,
  }
end

-- Builds the acquisition plan across all active reservations with explicit `reserved`, `retrieve`, and `buy` quantities.
-- `mode`: "after_bank" (default: subtracts bags + verified bank + optional eligible alt stock)
--         or "bags_only" ("Buy without collecting stored materials": subtracts current bags only)
function Reservations.BuildShoppingPlan(mode, inventorySnapshot, orderedReservations, explicitIncludeAlt)
  mode = mode or "after_bank"
  local ledger = Reservations.BuildAllocationLedger(inventorySnapshot, orderedReservations, nil, explicitIncludeAlt)
  local items = {}

  for itemID, entry in pairs(ledger.byItem or {}) do
    if entry.reservedTotal > 0 then
      local name = ns.Compat.ResolveItemName(itemID)
      local retrieveQty = (mode == "bags_only") and 0 or entry.reservedAllocatedTransfer
      local buyQty = (mode == "bags_only")
        and math.max(0, entry.reservedTotal - entry.bagCount)
        or entry.reservedShortfall

      table.insert(items, {
        itemID = itemID,
        name = name,
        reservedQty = entry.reservedTotal,
        bagOwned = entry.bagCount,
        bankOwned = entry.bankCount,
        altEligibleOwned = entry.altEligibleCount,
        retrieveQty = retrieveQty,
        buyQty = buyQty,
        deficitQty = buyQty,
      })
    end
  end

  table.sort(items, function(a, b)
    return a.itemID < b.itemID
  end)

  return {
    mode = mode,
    items = items,
  }
end

-- Computes the Ready-in-Bags / Ready-with-Bank summary from the shared priority ledger,
-- requiring BOTH target crate/writ possession and material allocation.
-- Also computes safe eligibility for "Reduce plan to observed ownership".
function Reservations.BuildReadySummary(inventorySnapshot, orderedReservations, explicitIncludeAlt, explicitBankMeta)
  local ledger = Reservations.BuildAllocationLedger(inventorySnapshot, orderedReservations, nil, explicitIncludeAlt)
  inventorySnapshot = ledger.inventorySnapshot
  orderedReservations = orderedReservations or (ns.State and ns.State.GetOrderedReservations and ns.State.GetOrderedReservations()) or {}

  local bankMeta = explicitBankMeta
  if not bankMeta and ns.Providers and ns.Providers.Inventory and ns.Providers.Inventory.GetBankAttributionMeta then
    bankMeta = ns.Providers.Inventory.GetBankAttributionMeta()
  end
  local bankAuthority = bankMeta and bankMeta.authority or "none"
  local bankOwnershipCertain = (bankAuthority == "live" or bankAuthority == "session" or bankAuthority == "external_cache" or bankAuthority == "fh_cache")
  if explicitBankMeta == nil and inventorySnapshot ~= nil and (not ns.Providers or not ns.Providers.Inventory) then
    -- In unit test environments with explicit snapshots, treat bank counts in the snapshot as observed unless overridden
    bankOwnershipCertain = true
  end

  local data = ns.Data or {}
  local sealedCratesByID = data.sealedCratesByItemID or {}
  local writsByID = data.writsByItemID or {}

  local sealedCratesInBags = 0
  local sealedCratesInBank = 0
  for sID, _ in pairs(sealedCratesByID) do
    local b, bk = getCounts(inventorySnapshot, tonumber(sID))
    sealedCratesInBags = sealedCratesInBags + b
    sealedCratesInBank = sealedCratesInBank + bk
  end
  local sealedCratesTotal = sealedCratesInBags + sealedCratesInBank

  local goalAllocByKey = {}
  for itemID, entry in pairs(ledger.byItem or {}) do
    for _, g in ipairs(entry.goals or {}) do
      local gKey = tostring(g.goalKey)
      goalAllocByKey[gKey] = goalAllocByKey[gKey] or {}
      goalAllocByKey[gKey][tonumber(itemID)] = g
    end
  end

  local goals = {}
  local totalPlannedTurnIns = 0
  local totalReadyInBagsNow = 0
  local totalReadyAfterBank = 0
  local totalExcessPlannedTurnIns = 0
  local activeWritQuestsCount = 0

  for _, res in ipairs(orderedReservations) do
    if type(res) == "table" then
      local kind = res.kind or "crate"
      local targetID = tonumber(res.targetItemID) or 0
      local gKey = res.goalKey or string.format("%s:%d", kind, targetID)
      local plannedQty = math.max(1, math.floor(tonumber(res.quantity) or 1))
      local bagTarget, bankTarget = getCounts(inventorySnapshot, targetID)
      local charOwnedTarget = bagTarget + bankTarget

      local writQuestActive = false
      if kind == "writ" then
        local wRec = writsByID[targetID]
        if wRec and wRec.startQuestID and ns.Compat and ns.Compat.IsOnQuest then
          writQuestActive = ns.Compat.IsOnQuest(wRec.startQuestID)
          if writQuestActive then
            activeWritQuestsCount = activeWritQuestsCount + 1
          end
        end
      end

      local uMats = res.unitMaterials or {}
      if #uMats == 0 and res.materials then
        for _, m in ipairs(res.materials) do
          local mq = math.max(1, math.floor(tonumber(m.quantity) or 1))
          table.insert(uMats, {
            itemID = m.itemID,
            name = m.name,
            quantity = math.max(1, math.floor(tonumber(m.unitQuantity) or math.floor(mq / plannedQty))),
          })
        end
      end

      local matReadyBags = plannedQty
      local matReadyBank = plannedQty
      local matReadyTransfer = plannedQty
      local gAllocs = goalAllocByKey[gKey] or {}

      for _, um in ipairs(uMats) do
        local mID = tonumber(um.itemID)
        local unitReq = math.max(1, math.floor(tonumber(um.quantity) or 1))
        local ga = mID and gAllocs[mID] or nil
        local aBags = ga and (tonumber(ga.allocatedBags) or 0) or 0
        local aBank = ga and (tonumber(ga.allocatedBank) or 0) or 0
        local aTotal = ga and (tonumber(ga.allocatedQty) or 0) or 0

        matReadyBags = math.min(matReadyBags, math.floor(aBags / unitReq))
        matReadyBank = math.min(matReadyBank, math.floor((aBags + aBank) / unitReq))
        matReadyTransfer = math.min(matReadyTransfer, math.floor(aTotal / unitReq))
      end

      local readyInBagsNow = 0
      local readyAfterBank = 0
      local excessOverOwned = 0
      local canReduceToOwned = false
      local reduceBlockReason = nil
      local craftBlockedReason = nil

      if kind == "craft" then
        -- Stage 7B.1 (`P0-8`): Craft readiness NEVER requires possession of `targetItemID` (`outputItemID`)!
        -- Depends strictly on complete own-character recipe, allocated consumed reagents, required tool/station, and cooldown.
        if not isExecutableCraftReservation(res) then
          craftBlockedReason = "incomplete_or_unverified_recipe"
        elseif res.requiredToolsPresent == false or res.requiredStationPresent == false then
          craftBlockedReason = "missing_required_tool_or_station"
        elseif res.cooldownStatus == "ON_COOLDOWN_OBSERVED" then
          craftBlockedReason = "recipe_on_cooldown"
        else
          readyInBagsNow = math.min(plannedQty, matReadyBags)
          readyAfterBank = math.min(plannedQty, matReadyBank)
        end
      else
        -- Ready turn-ins in bags require BOTH possession of the crate/writ in bags AND allocated materials in bags
        readyInBagsNow = math.min(plannedQty, bagTarget, matReadyBags)
        readyAfterBank = math.min(plannedQty, charOwnedTarget, matReadyBank)
        excessOverOwned = math.max(0, plannedQty - charOwnedTarget)

        if excessOverOwned > 0 then
          if not bankOwnershipCertain then
            reduceBlockReason = "Bank ownership is unverified; visit your bank before reducing plans."
          elseif kind == "crate" and sealedCratesTotal > 0 then
            reduceBlockReason = string.format(
              "You have %d Sealed Crate(s) awaiting delivery; deliver them before reducing crate plans.",
              sealedCratesTotal
            )
          elseif kind == "writ" and writQuestActive then
            reduceBlockReason = "This writ quest is currently active in your quest log."
          else
            canReduceToOwned = true
          end
        end
      end

      totalPlannedTurnIns = totalPlannedTurnIns + plannedQty
      totalReadyInBagsNow = totalReadyInBagsNow + readyInBagsNow
      totalReadyAfterBank = totalReadyAfterBank + readyAfterBank
      totalExcessPlannedTurnIns = totalExcessPlannedTurnIns + excessOverOwned

      table.insert(goals, {
        goalKey = gKey,
        kind = kind,
        skillLineID = (kind == "craft") and tonumber(res.skillLineID) or nil,
        spellID = (kind == "craft") and tonumber(res.spellID) or nil,
        targetItemID = targetID,
        targetName = res.targetName or gKey,
        priority = tonumber(res.priority) or 1,
        optionIndex = tonumber(res.optionIndex) or 1,
        plannedQty = plannedQty,
        bagOwnedTarget = bagTarget,
        bankOwnedTarget = bankTarget,
        charOwnedTarget = charOwnedTarget,
        writQuestActive = writQuestActive,
        matReadyBags = matReadyBags,
        matReadyBank = matReadyBank,
        matReadyTransfer = matReadyTransfer,
        readyInBagsNow = readyInBagsNow,
        readyAfterBank = readyAfterBank,
        excessOverOwned = excessOverOwned,
        canReduceToOwned = canReduceToOwned,
        reduceBlockReason = reduceBlockReason,
        craftBlockedReason = craftBlockedReason,
      })
    end
  end

  return {
    goals = goals,
    totalGoals = #goals,
    totalPlannedTurnIns = totalPlannedTurnIns,
    totalReadyInBagsNow = totalReadyInBagsNow,
    totalReadyAfterBank = totalReadyAfterBank,
    totalExcessPlannedTurnIns = totalExcessPlannedTurnIns,
    sealedCratesInBags = sealedCratesInBags,
    sealedCratesInBank = sealedCratesInBank,
    sealedCratesTotal = sealedCratesTotal,
    activeWritQuestsCount = activeWritQuestsCount,
    bankOwnershipCertain = bankOwnershipCertain,
  }
end

-- Builds the character-bank withdrawal plan across active reservations.
-- Strictly withdraws ONLY current-character bank allocations (`allocatedBank`), never `allocatedAlt`,
-- and includes planned target crates/writs currently stored in the character's bank.
function Reservations.BuildBankCollectionPlan(inventorySnapshot, orderedReservations, explicitIncludeAlt)
  local ledger = Reservations.BuildAllocationLedger(inventorySnapshot, orderedReservations, nil, explicitIncludeAlt)
  inventorySnapshot = ledger.inventorySnapshot
  orderedReservations = orderedReservations or (ns.State and ns.State.GetOrderedReservations and ns.State.GetOrderedReservations()) or {}

  local targetItems = {}
  local seenTarget = {}
  local totalTargetUnits = 0

  for _, res in ipairs(orderedReservations) do
    if type(res) == "table" and res.kind ~= "craft" then
      local targetID = tonumber(res.targetItemID)
      local plannedQty = math.max(1, math.floor(tonumber(res.quantity) or 1))
      if targetID and not seenTarget[targetID] then
        seenTarget[targetID] = true
        local bagOwned, bankOwned = getCounts(inventorySnapshot, targetID)
        local neededInBags = math.max(0, plannedQty - bagOwned)
        local pullFromBank = math.min(neededInBags, bankOwned)
        if pullFromBank > 0 then
          totalTargetUnits = totalTargetUnits + pullFromBank
          table.insert(targetItems, {
            itemID = targetID,
            name = res.targetName or ns.Compat.ResolveItemName(targetID) or string.format("Item %d", targetID),
            kind = res.kind or "crate",
            plannedQty = plannedQty,
            bagOwned = bagOwned,
            bankOwned = bankOwned,
            pullQty = pullFromBank,
          })
        end
      end
    end
  end

  local materials = {}
  local totalMaterialUnits = 0
  local totalAltAllocatedUnits = 0

  local sortedItemIDs = {}
  for itemID, _ in pairs(ledger.byItem or {}) do
    table.insert(sortedItemIDs, itemID)
  end
  table.sort(sortedItemIDs)

  for _, itemID in ipairs(sortedItemIDs) do
    local entry = ledger.byItem[itemID]
    if entry and entry.reservedTotal > 0 then
      local pullBankQty = math.max(0, math.floor(tonumber(entry.reservedAllocatedBank) or 0))
      local altAllocQty = math.max(0, math.floor(tonumber(entry.reservedAllocatedAlt) or 0))
      totalAltAllocatedUnits = totalAltAllocatedUnits + altAllocQty
      if pullBankQty > 0 then
        totalMaterialUnits = totalMaterialUnits + pullBankQty
        table.insert(materials, {
          itemID = itemID,
          name = ns.Compat.ResolveItemName(itemID) or string.format("Item %d", itemID),
          reservedTotal = entry.reservedTotal,
          bagOwned = entry.bagCount,
          bankOwned = entry.bankCount,
          pullQty = pullBankQty,
          altAllocatedQty = altAllocQty,
        })
      end
    end
  end

  return {
    targetItems = targetItems,
    materials = materials,
    totalTargetUnits = totalTargetUnits,
    totalMaterialUnits = totalMaterialUnits,
    totalPullUnits = totalTargetUnits + totalMaterialUnits,
    totalAltAllocatedUnits = totalAltAllocatedUnits,
  }
end
