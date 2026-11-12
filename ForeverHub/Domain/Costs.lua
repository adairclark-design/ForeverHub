local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.Domain = ns.Domain or {}
local Costs = {}
ns.Domain.Costs = Costs

Costs.__cacheKey = nil
Costs.__cacheMap = {}

local function getPriceInfo(itemID, explicitPriceMap)
  local staleDays = (ns.State and ns.State.GetStaleAgeDays and ns.State.GetStaleAgeDays()) or 2
  if type(explicitPriceMap) == "table" then
    local p = explicitPriceMap[itemID]
    if type(p) == "number" then
      -- Zero or negative copper price is never accepted as a valid price
      if p > 0 then
        return {
          unitPrice = math.floor(p + 0.5),
          ageDays = nil,
          freshness = "unknown_age",
          isStale = false,
          isUnknownAge = true,
        }
      end
      return { unitPrice = nil, ageDays = nil, freshness = "missing", isStale = false, isUnknownAge = false }
    elseif type(p) == "table" then
      local up = tonumber(p.unitPrice)
      if up and up > 0 then
        local ageDays = (p.ageDays ~= nil) and tonumber(p.ageDays) or nil
        if ageDays ~= nil and ageDays < 0 then
          ageDays = nil
        end
        local isStale = (p.isStale == true) or (ageDays ~= nil and ageDays > staleDays) or false
        local isUnknownAge = (ageDays == nil and not isStale)
        local freshness = isStale and "stale" or (isUnknownAge and "unknown_age" or "fresh")
        return {
          unitPrice = math.floor(up + 0.5),
          ageDays = ageDays,
          freshness = freshness,
          isStale = isStale,
          isUnknownAge = isUnknownAge,
        }
      end
      return { unitPrice = nil, ageDays = nil, freshness = "missing", isStale = false, isUnknownAge = false }
    end
    return { unitPrice = nil, ageDays = nil, freshness = "missing", isStale = false, isUnknownAge = false }
  end

  if ns.Providers.Auctionator and ns.Providers.Auctionator.GetItemPriceInfo then
    return ns.Providers.Auctionator.GetItemPriceInfo(itemID)
  end
  return { unitPrice = nil, ageDays = nil, freshness = "missing", isStale = false, isUnknownAge = false }
end

function Costs.EvaluateTargetOptions(
  kind,
  targetRecord,
  explicitPriceMap,
  explicitInventorySnapshot,
  explicitOrderedReservations,
  explicitCandidateQuantity,
  explicitIncludeAlt,
  explicitAcquisitionMode
)
  if type(targetRecord) ~= "table" then
    return nil
  end
  kind = kind or (targetRecord.writItemID and "writ" or "crate")
  local targetItemID = tonumber(targetRecord.itemID or targetRecord.writItemID)
  local goalKey = string.format("%s:%d", kind, targetItemID or 0)

  if explicitCandidateQuantity ~= nil then
    local qNum = tonumber(explicitCandidateQuantity)
    if not qNum or qNum <= 0 or math.floor(qNum) ~= qNum then
      error("Invalid candidate quantity: must be a positive integer >= 1", 2)
    end
  end

  local acquisitionMode = explicitAcquisitionMode
  if acquisitionMode == nil then
    acquisitionMode = (ns.State and ns.State.GetAcquisitionMode and ns.State.GetAcquisitionMode()) or "after_bank"
  end
  if acquisitionMode ~= "bags_only" then
    acquisitionMode = "after_bank"
  end

  local useCache = (
    explicitPriceMap == nil
    and explicitInventorySnapshot == nil
    and explicitOrderedReservations == nil
    and explicitCandidateQuantity == nil
    and explicitIncludeAlt == nil
    and explicitAcquisitionMode == nil
  )

  local includeAltStock = explicitIncludeAlt
  if includeAltStock == nil then
    includeAltStock = (ns.State and ns.State.GetIncludeAltStock and ns.State.GetIncludeAltStock()) or false
  end

  if useCache and ns.State and ns.State.GetRevisions then
    local invRev, resRev, priceRev = ns.State.GetRevisions()
    local revKey = string.format(
      "%d:%d:%d:%s:%s",
      invRev,
      resRev,
      priceRev,
      includeAltStock and "1" or "0",
      acquisitionMode
    )
    if Costs.__cacheKey ~= revKey then
      Costs.__cacheKey = revKey
      Costs.__cacheMap = {}
    end
    if Costs.__cacheMap[goalKey] then
      return Costs.__cacheMap[goalKey]
    end
  end

  local inventorySnapshot = explicitInventorySnapshot
    or (ns.Providers.Inventory and ns.Providers.Inventory.GetAggregatedSnapshot and ns.Providers.Inventory.GetAggregatedSnapshot())
    or {}
  local orderedReservations = explicitOrderedReservations
    or (ns.State and ns.State.GetOrderedReservations and ns.State.GetOrderedReservations())
    or {}

  -- Find existing reservation for `goalKey` if present
  local existingGoal = nil
  for _, r in ipairs(orderedReservations) do
    local rKey = r.goalKey or string.format("%s:%d", tostring(r.kind or "crate"), tonumber(r.targetItemID) or 0)
    if rKey == goalKey then
      existingGoal = r
      break
    end
  end

  local effectiveQty
  if explicitCandidateQuantity ~= nil then
    effectiveQty = math.floor(tonumber(explicitCandidateQuantity))
  else
    effectiveQty = math.max(1, math.floor(tonumber(existingGoal and existingGoal.quantity) or 1))
  end

  -- Build ledger of strictly higher-priority reservations ONCE for this target evaluation
  local priorLedger = ns.Domain.Reservations.BuildAllocationLedger(
    inventorySnapshot,
    orderedReservations,
    goalKey,
    includeAltStock
  )

  -- Current-character crate ownership strictly excludes soulbound alt crates
  local targetInv = inventorySnapshot[targetItemID] or {}
  local bagOwnedTarget = math.max(0, math.floor(tonumber(targetInv.bagCount) or 0))
  local bankOwnedTarget = math.max(0, math.floor(tonumber(targetInv.bankCount) or 0))
  local charOwnedCrates = bagOwnedTarget + bankOwnedTarget
  local altSoulboundCrates = math.max(0, math.floor(tonumber(targetInv.altEligibleCount or targetInv.altCount) or 0))
    + math.max(0, math.floor(tonumber(targetInv.altUnknownCount) or 0))
    + math.max(0, math.floor(tonumber(targetInv.altIneligibleCount) or 0))

  local rawOptions = {}
  if kind == "writ" then
    table.insert(rawOptions, {
      optionIndex = 1,
      label = string.format("%s x%d", tostring(targetRecord.targetItemName or "Target"), tonumber(targetRecord.quantity) or 1),
      materials = {
        {
          itemID = targetRecord.targetItemID,
          name = targetRecord.targetItemName,
          quantity = targetRecord.quantity or 1,
        },
      },
    })
  else
    rawOptions = targetRecord.alternatives or {}
  end

  local evaluatedOptions = {}
  local fullyPricedReplacementCount = 0
  local knownBagDeficitCount = 0
  local knownTransferDeficitCount = 0
  local knownActiveDeficitCount = 0

  for _, alt in ipairs(rawOptions) do
    local optIndex = tonumber(alt.optionIndex) or 1
    local goalID = string.format("%s:%d:%d", kind, targetItemID or 0, optIndex)
    local isReserved = (existingGoal ~= nil and tonumber(existingGoal.optionIndex) == optIndex)

    local matDetails = {}
    local replacementComplete = true
    local bagDeficitComplete = true
    local transferDeficitComplete = true

    local replacementSum = 0
    local bagDeficitSum = 0
    local transferDeficitSum = 0

    local anyStale = false
    local anyUnknownAge = false
    local maxAgeDays = nil

    local totalBagDeficitUnits = 0
    local totalBankDeficitUnits = 0
    local totalTransferDeficitUnits = 0
    local totalRetrieveBankUnits = 0
    local totalRetrieveAltUnits = 0

    local conflictUnitsTotal = 0
    local conflictGoalsByKey = {}
    local conflictGoalList = {}
    local conflictGoalKeys = {}

    for _, mat in ipairs(alt.materials or {}) do
      local mID = tonumber(mat.itemID)
      local unitReqQty = math.max(1, math.floor(tonumber(mat.quantity) or 1))
      local reqQty = unitReqQty * effectiveQty

      local itemState = priorLedger.byItem[mID]
      local bagCount, bankCount, altEligCount, altUnkCount, freeBags, freeBank, freeAlt, freeTransfer, reservedHigher, higherGoals
      if itemState then
        bagCount = itemState.bagCount
        bankCount = itemState.bankCount
        altEligCount = itemState.altEligibleCount
        altUnkCount = itemState.altUnknownCount
        freeBags = itemState.freeBags
        freeBank = itemState.freeBank
        freeAlt = itemState.freeAltEligible
        freeTransfer = itemState.freeTransfer
        reservedHigher = itemState.reservedTotal
        higherGoals = itemState.goals or {}
      else
        local invE = inventorySnapshot[mID] or {}
        bagCount = math.max(0, math.floor(tonumber(invE.bagCount) or 0))
        bankCount = math.max(0, math.floor(tonumber(invE.bankCount) or 0))
        altEligCount = math.max(0, math.floor(tonumber(invE.altEligibleCount or invE.altCount) or 0))
        altUnkCount = math.max(0, math.floor(tonumber(invE.altUnknownCount) or 0))
        freeBags = bagCount
        freeBank = bankCount
        freeAlt = includeAltStock and altEligCount or 0
        freeTransfer = freeBank + freeAlt
        reservedHigher = 0
        higherGoals = {}
      end

      local totalUsableOwned = bagCount + bankCount + (includeAltStock and altEligCount or 0)
      local bagDeficitUnits = math.max(0, reqQty - freeBags)
      local bankDeficitUnits = math.max(0, reqQty - (freeBags + freeBank))
      local transferDeficitUnits = math.max(0, reqQty - (freeBags + freeTransfer))

      local retrieveBankUnits = math.min(bagDeficitUnits, freeBank)
      local retrieveAltUnits = includeAltStock and math.min(math.max(0, bagDeficitUnits - freeBank), freeAlt) or 0

      totalBagDeficitUnits = totalBagDeficitUnits + bagDeficitUnits
      totalBankDeficitUnits = totalBankDeficitUnits + bankDeficitUnits
      totalTransferDeficitUnits = totalTransferDeficitUnits + transferDeficitUnits
      totalRetrieveBankUnits = totalRetrieveBankUnits + retrieveBankUnits
      totalRetrieveAltUnits = totalRetrieveAltUnits + retrieveAltUnits

      -- Partial or full conflict detection against higher-priority goals
      local physicallyCoverable = math.min(reqQty, totalUsableOwned)
      local unreservedCoverable = math.min(reqQty, freeBags + freeTransfer)
      local matConflictUnits = math.max(0, physicallyCoverable - unreservedCoverable)
      if matConflictUnits > 0 then
        conflictUnitsTotal = conflictUnitsTotal + matConflictUnits
        for _, hg in ipairs(higherGoals) do
          local hKey = hg.goalKey or hg.goalID
          if not conflictGoalsByKey[hKey] then
            conflictGoalsByKey[hKey] = true
            table.insert(conflictGoalList, hg)
            table.insert(conflictGoalKeys, hKey)
          end
        end
      end

      local pInfo = getPriceInfo(mID, explicitPriceMap)
      local unitPrice = pInfo and pInfo.unitPrice or nil
      local isStale = (pInfo and pInfo.isStale) or false
      local isUnknownAge = (pInfo and pInfo.isUnknownAge) or false
      local freshness = (pInfo and pInfo.freshness) or "missing"

      local matReplacement = nil
      local matBagDeficit = nil
      local matTransferDeficit = nil

      if type(unitPrice) == "number" and unitPrice > 0 then
        if isStale then
          anyStale = true
        end
        if isUnknownAge then
          anyUnknownAge = true
        end
        if pInfo.ageDays ~= nil then
          maxAgeDays = math.max(maxAgeDays or 0, pInfo.ageDays)
        end
        matReplacement = reqQty * unitPrice
        matBagDeficit = bagDeficitUnits * unitPrice
        matTransferDeficit = transferDeficitUnits * unitPrice

        replacementSum = replacementSum + matReplacement
        bagDeficitSum = bagDeficitSum + matBagDeficit
        transferDeficitSum = transferDeficitSum + matTransferDeficit
      else
        -- Missing price: replacement value is unknown, BUT if deficit is 0, purchase deficit is known 0 copper!
        replacementComplete = false
        if bagDeficitUnits == 0 then
          matBagDeficit = 0
        else
          bagDeficitComplete = false
        end
        if transferDeficitUnits == 0 then
          matTransferDeficit = 0
        else
          transferDeficitComplete = false
        end
      end

      table.insert(matDetails, {
        itemID = mID,
        name = mat.name,
        unitRequired = unitReqQty,
        requiredQty = reqQty,
        required = reqQty,
        bagCount = bagCount,
        bankCount = bankCount,
        altEligibleCount = altEligCount,
        altUnknownCount = altUnkCount,
        reservedHigherPriority = reservedHigher,
        freeBags = freeBags,
        freeBank = freeBank,
        freeTransfer = freeTransfer,
        retrieveBankUnits = retrieveBankUnits,
        retrieveAltUnits = retrieveAltUnits,
        bagDeficitUnits = bagDeficitUnits,
        bankDeficitUnits = bankDeficitUnits,
        transferDeficitUnits = transferDeficitUnits,
        conflictUnits = matConflictUnits,
        unitPrice = unitPrice,
        unitPriceCopper = unitPrice,
        ageDays = pInfo and pInfo.ageDays or nil,
        priceAgeDays = pInfo and pInfo.ageDays or nil,
        priceFreshness = freshness,
        isStale = isStale,
        isUnknownAge = isUnknownAge,
        replacementCopper = matReplacement,
        bagDeficitCopper = matBagDeficit,
        transferDeficitCopper = matTransferDeficit,
      })
    end

    if replacementComplete then
      fullyPricedReplacementCount = fullyPricedReplacementCount + 1
    end
    if bagDeficitComplete then
      knownBagDeficitCount = knownBagDeficitCount + 1
    end
    if transferDeficitComplete then
      knownTransferDeficitCount = knownTransferDeficitCount + 1
    end

    local isActiveDeficitKnown = (acquisitionMode == "bags_only") and bagDeficitComplete or transferDeficitComplete
    if isActiveDeficitKnown then
      knownActiveDeficitCount = knownActiveDeficitCount + 1
    end

    local coverage
    if replacementComplete then
      if anyStale then
        coverage = "stale"
      elseif anyUnknownAge then
        coverage = "unknown_age"
      else
        coverage = "complete"
      end
    elseif bagDeficitComplete or transferDeficitComplete then
      coverage = "deficit_known_only"
    else
      coverage = "unpriced"
    end

    local conflictWarning = nil
    if conflictUnitsTotal > 0 then
      if #conflictGoalList == 1 then
        local cg = conflictGoalList[1]
        local cgKind = (cg.kind == "writ") and "writ" or "crate"
        conflictWarning = string.format(
          "This option consumes materials reserved for your selected %s (%s).",
          cgKind,
          cg.targetName
        )
      else
        conflictWarning = "This option consumes materials reserved for your selected goals."
      end
    end

    local displacement = ns.Domain.Reservations.ComputeDownstreamDisplacement(
      inventorySnapshot,
      orderedReservations,
      goalKey,
      optIndex,
      effectiveQty,
      alt.materials or {},
      includeAltStock
    )

    local repEst = replacementComplete and replacementSum or nil
    local bagDefEst = bagDeficitComplete and bagDeficitSum or nil
    local transDefEst = transferDeficitComplete and transferDeficitSum or nil
    local activeDefEst = (acquisitionMode == "bags_only") and bagDefEst or transDefEst

    table.insert(evaluatedOptions, {
      goalKey = goalKey,
      goalID = goalID,
      optionIndex = optIndex,
      quantity = effectiveQty,
      label = alt.label or string.format("Option #%d", optIndex),
      isReserved = isReserved,
      coverage = coverage,
      isPriced = replacementComplete,
      isFullyPriced = replacementComplete,
      isBagDeficitKnown = bagDeficitComplete,
      isTransferDeficitKnown = transferDeficitComplete,
      isActiveDeficitKnown = isActiveDeficitKnown,
      replacementEstimate = repEst,
      bagDeficitEstimate = bagDefEst,
      transferDeficitEstimate = transDefEst,
      activeDeficitEstimate = activeDefEst,
      replacementEstimateCopper = repEst,
      bagDeficitEstimateCopper = bagDefEst,
      transferDeficitEstimateCopper = transDefEst,
      activeDeficitEstimateCopper = activeDefEst,
      maxPriceAgeDays = maxAgeDays,
      isStalePrice = anyStale,
      isUnknownPriceAge = anyUnknownAge,
      totalBagDeficitUnits = totalBagDeficitUnits,
      totalBankDeficitUnits = totalBankDeficitUnits,
      totalTransferDeficitUnits = totalTransferDeficitUnits,
      totalRetrieveBankUnits = totalRetrieveBankUnits,
      totalRetrieveAltUnits = totalRetrieveAltUnits,
      totalRetrieveUnits = totalRetrieveBankUnits + totalRetrieveAltUnits,
      canFillFromBagsNow = (totalBagDeficitUnits == 0),
      canFillFromUnreservedBags = (totalBagDeficitUnits == 0),
      canFillWithTransfer = (totalTransferDeficitUnits == 0),
      canFillFromUnreservedTransfer = (totalTransferDeficitUnits == 0),
      consumesReservedStock = (conflictUnitsTotal > 0),
      reservedConflictUnits = conflictUnitsTotal,
      reservationConflicts = conflictGoalKeys,
      conflictWarning = conflictWarning,
      displacesLowerPriorityStock = displacement.displacesLowerPriorityStock,
      displacedLowerPriorityUnits = displacement.displacedLowerPriorityUnits,
      displacedGoalKeys = displacement.displacedGoalKeys,
      displacedGoals = displacement.displacedGoals,
      displacementWarning = displacement.displacementWarning,
      materials = matDetails,
    })
  end

  -- Transitive strict weak ordering comparator (matches Python _rank_key):
  -- Prioritizes known deficit -> contention avoidance -> displacement avoidance -> active deficit copper -> retrieve units.
  local rankedOptions = {}
  for _, opt in ipairs(evaluatedOptions) do
    table.insert(rankedOptions, opt)
  end

  table.sort(rankedOptions, function(a, b)
    if a.isActiveDeficitKnown ~= b.isActiveDeficitKnown then
      return a.isActiveDeficitKnown
    end
    if a.consumesReservedStock ~= b.consumesReservedStock then
      return not a.consumesReservedStock
    end
    if a.displacesLowerPriorityStock ~= b.displacesLowerPriorityStock then
      return not a.displacesLowerPriorityStock
    end
    if a.isActiveDeficitKnown and a.activeDeficitEstimate ~= b.activeDeficitEstimate then
      return a.activeDeficitEstimate < b.activeDeficitEstimate
    end
    if a.totalRetrieveUnits ~= b.totalRetrieveUnits then
      return a.totalRetrieveUnits < b.totalRetrieveUnits
    end
    if a.isBagDeficitKnown ~= b.isBagDeficitKnown then
      return a.isBagDeficitKnown
    end
    if a.isBagDeficitKnown and a.bagDeficitEstimate ~= b.bagDeficitEstimate then
      return a.bagDeficitEstimate < b.bagDeficitEstimate
    end
    if a.isTransferDeficitKnown ~= b.isTransferDeficitKnown then
      return a.isTransferDeficitKnown
    end
    if a.isTransferDeficitKnown and a.transferDeficitEstimate ~= b.transferDeficitEstimate then
      return a.transferDeficitEstimate < b.transferDeficitEstimate
    end
    if a.isPriced ~= b.isPriced then
      return a.isPriced
    end
    if a.isPriced and a.replacementEstimate ~= b.replacementEstimate then
      return a.replacementEstimate < b.replacementEstimate
    end
    return a.optionIndex < b.optionIndex
  end)

  local cheapestReplacementIndices = {}
  local cheapestDeficitIndices = {}
  local cheapestTransferDeficitIndices = {}
  local minReplacement = nil
  local minBagDeficit = nil
  local minTransferDeficit = nil

  for _, opt in ipairs(evaluatedOptions) do
    if opt.replacementEstimate ~= nil then
      if minReplacement == nil or opt.replacementEstimate < minReplacement then
        minReplacement = opt.replacementEstimate
      end
    end
    if opt.bagDeficitEstimate ~= nil then
      if minBagDeficit == nil or opt.bagDeficitEstimate < minBagDeficit then
        minBagDeficit = opt.bagDeficitEstimate
      end
    end
    if opt.transferDeficitEstimate ~= nil then
      if minTransferDeficit == nil or opt.transferDeficitEstimate < minTransferDeficit then
        minTransferDeficit = opt.transferDeficitEstimate
      end
    end
  end

  for _, opt in ipairs(evaluatedOptions) do
    if minReplacement ~= nil and opt.replacementEstimate == minReplacement then
      table.insert(cheapestReplacementIndices, opt.optionIndex)
    end
    if minBagDeficit ~= nil and opt.bagDeficitEstimate == minBagDeficit then
      table.insert(cheapestDeficitIndices, opt.optionIndex)
    end
    if minTransferDeficit ~= nil and opt.transferDeficitEstimate == minTransferDeficit then
      table.insert(cheapestTransferDeficitIndices, opt.optionIndex)
    end
  end

  local bestOption = nil
  if
    knownActiveDeficitCount > 0
    or knownBagDeficitCount > 0
    or knownTransferDeficitCount > 0
    or fullyPricedReplacementCount > 0
  then
    bestOption = rankedOptions[1]
  end

  local totalOpts = #evaluatedOptions
  local coverageStatus
  local recommendationScopeLabel
  if fullyPricedReplacementCount == 0 and knownBagDeficitCount == 0 and knownTransferDeficitCount == 0 then
    coverageStatus = "unpriced"
    recommendationScopeLabel = "price data unavailable"
  elseif bestOption and bestOption.coverage == "deficit_known_only" then
    coverageStatus = "partial"
    recommendationScopeLabel = "lowest known purchase estimate"
  elseif fullyPricedReplacementCount < totalOpts then
    coverageStatus = "partial"
    recommendationScopeLabel = "lowest estimated cost among priced options"
  else
    coverageStatus = "complete"
    recommendationScopeLabel = "lowest estimated cost"
  end

  local result = {
    kind = kind,
    targetItemID = targetItemID,
    crateItemID = targetItemID,
    name = targetRecord.name,
    crateName = targetRecord.name,
    goalKey = goalKey,
    acquisitionMode = acquisitionMode,
    plannedTurnIns = effectiveQty,
    charOwnedCrates = charOwnedCrates,
    altSoulboundCrates = altSoulboundCrates,
    limitationNotice = (kind == "writ")
      and (targetRecord.limitationNotice or "Finished item reserved; crafting reagents are not protected.")
      or nil,
    options = evaluatedOptions,
    rankedOptions = rankedOptions,
    bestOption = bestOption,
    coverageStatus = coverageStatus,
    recommendationScopeLabel = recommendationScopeLabel,
    pricedOptionCount = fullyPricedReplacementCount,
    knownBagDeficitOptionCount = knownBagDeficitCount,
    knownTransferDeficitOptionCount = knownTransferDeficitCount,
    knownActiveDeficitOptionCount = knownActiveDeficitCount,
    totalOptionCount = totalOpts,
    minReplacementCopper = minReplacement,
    minBagDeficitCopper = minBagDeficit,
    minTransferDeficitCopper = minTransferDeficit,
    cheapestReplacementOptionIndices = cheapestReplacementIndices,
    cheapestDeficitOptionIndices = cheapestDeficitIndices,
    cheapestTransferDeficitOptionIndices = cheapestTransferDeficitIndices,
  }

  if useCache then
    Costs.__cacheMap[goalKey] = result
  end
  return result
end

local TIER_ORDER = {
  Apprentice = 1,
  Journeyman = 2,
  Expert = 3,
  Artisan = 4,
  Master = 5,
  ["Craftsman's Writ"] = 6,
}

-- Scarcity-aware incremental planner for owned crates/writs that can be filled with 0 purchases.
-- Preserves all manual reservations, checks requiredLevel, excludes unverified writs by default,
-- and assigns scarce/inflexible requirements before flexible multi-option goals.
function Costs.SuggestReadyTurnIns(
  explicitInventorySnapshot,
  explicitOrderedReservations,
  explicitPriceMap,
  explicitPlayerLevel,
  explicitIncludeAlt,
  explicitAcquisitionMode,
  explicitIncludeUnverifiedWrits,
  explicitCandidateTargets
)
  local inventorySnapshot = explicitInventorySnapshot
    or (ns.Providers.Inventory and ns.Providers.Inventory.GetAggregatedSnapshot and ns.Providers.Inventory.GetAggregatedSnapshot())
    or {}
  local existingReservations = explicitOrderedReservations
    or (ns.State and ns.State.GetOrderedReservations and ns.State.GetOrderedReservations())
    or {}
  local playerLevel = tonumber(explicitPlayerLevel)
    or (ns.Compat and ns.Compat.GetPlayerLevel and ns.Compat.GetPlayerLevel())
    or 60
  local includeAltStock = explicitIncludeAlt
  if includeAltStock == nil then
    includeAltStock = (ns.State and ns.State.GetIncludeAltStock and ns.State.GetIncludeAltStock()) or false
  end
  local acquisitionMode = explicitAcquisitionMode
  if acquisitionMode == nil then
    acquisitionMode = (ns.State and ns.State.GetAcquisitionMode and ns.State.GetAcquisitionMode()) or "after_bank"
  end
  if acquisitionMode ~= "bags_only" then
    acquisitionMode = "after_bank"
  end
  local includeUnverifiedWrits = (explicitIncludeUnverifiedWrits == true)

  local simulatedReservations = {}
  local preservedGoalKeys = {}
  local existingGoalKeySet = {}
  local maxPriority = 0

  for _, r in ipairs(existingReservations) do
    if type(r) == "table" then
      local gKey = r.goalKey or string.format("%s:%d", tostring(r.kind or "crate"), tonumber(r.targetItemID) or 0)
      existingGoalKeySet[gKey] = true
      table.insert(preservedGoalKeys, gKey)
      local p = tonumber(r.priority) or 1
      if p > maxPriority then
        maxPriority = p
      end
      local copy = {}
      for k, v in pairs(r) do
        copy[k] = v
      end
      table.insert(simulatedReservations, copy)
    end
  end

  local nextPriority = maxPriority + 1

  -- Gather candidate targets
  local rawCandidates = {}
  if type(explicitCandidateTargets) == "table" then
    rawCandidates = explicitCandidateTargets
  else
    local data = ns.Data or {}
    local crateIDs = {}
    for id, _ in pairs(data.cratesByItemID or {}) do
      table.insert(crateIDs, tonumber(id))
    end
    table.sort(crateIDs)
    for _, id in ipairs(crateIDs) do
      table.insert(rawCandidates, data.cratesByItemID[id])
    end

    local writIDs = {}
    for id, _ in pairs(data.writsByItemID or {}) do
      table.insert(writIDs, tonumber(id))
    end
    table.sort(writIDs)
    for _, id in ipairs(writIDs) do
      table.insert(rawCandidates, data.writsByItemID[id])
    end
  end

  local eligibleTargets = {}
  local remainingOwnedByKey = {}
  local chosenOptionByKey = {}

  for _, t in ipairs(rawCandidates) do
    if type(t) == "table" then
      local kind = t.writItemID and "writ" or (t.kind or "crate")
      local targetID = tonumber(t.itemID or t.writItemID) or 0
      local gKey = string.format("%s:%d", kind, targetID)
      if not existingGoalKeySet[gKey] then
        local reqLevel = tonumber(t.requiredLevel) or 1
        local qtyVerified = (t.quantityVerified ~= false)
        if reqLevel <= playerLevel and (kind ~= "writ" or includeUnverifiedWrits or qtyVerified) then
          local invEntry = inventorySnapshot[targetID] or {}
          local bagOwned = math.max(0, math.floor(tonumber(invEntry.bagCount) or 0))
          local bankOwned = math.max(0, math.floor(tonumber(invEntry.bankCount) or 0))
          local charOwned = bagOwned + bankOwned
          if charOwned > 0 then
            table.insert(eligibleTargets, t)
            remainingOwnedByKey[gKey] = charOwned
          end
        end
      end
    end
  end

  -- Incremental 1-turn-in step loop
  while true do
    local ledger = ns.Domain.Reservations.BuildAllocationLedger(
      inventorySnapshot,
      simulatedReservations,
      nil,
      includeAltStock
    )

    local function getFreeCount(mID)
      local e = ledger.byItem[mID]
      if e then
        if acquisitionMode == "bags_only" then
          return e.freeBags
        end
        return e.freeBags + e.freeTransfer
      end
      local invE = inventorySnapshot[mID] or {}
      local b = math.max(0, math.floor(tonumber(invE.bagCount) or 0))
      local bk = math.max(0, math.floor(tonumber(invE.bankCount) or 0))
      local alt = includeAltStock and math.max(0, math.floor(tonumber(invE.altEligibleCount or invE.altCount) or 0)) or 0
      if acquisitionMode == "bags_only" then
        return b
      end
      return b + bk + alt
    end

    local viableByGoal = {}
    local matDemandGoalCount = {}

    for _, t in ipairs(eligibleTargets) do
      local kind = t.writItemID and "writ" or (t.kind or "crate")
      local targetID = tonumber(t.itemID or t.writItemID) or 0
      local gKey = string.format("%s:%d", kind, targetID)
      if (remainingOwnedByKey[gKey] or 0) > 0 then
        local evalRes = Costs.EvaluateTargetOptions(
          kind,
          t,
          explicitPriceMap,
          inventorySnapshot,
          simulatedReservations,
          1,
          includeAltStock,
          acquisitionMode
        )
        local lockedOptIdx = chosenOptionByKey[gKey]
        local viableOpts = {}
        local seenGoalMat = {}

        for _, opt in ipairs((evalRes and evalRes.options) or {}) do
          if lockedOptIdx == nil or opt.optionIndex == lockedOptIdx then
            local canFill = (acquisitionMode == "bags_only") and opt.canFillFromBagsNow or opt.canFillWithTransfer
            if canFill and not opt.consumesReservedStock then
              table.insert(viableOpts, opt)
              for _, m in ipairs(opt.materials or {}) do
                local mID = tonumber(m.itemID)
                if mID and not seenGoalMat[mID] then
                  seenGoalMat[mID] = true
                  matDemandGoalCount[mID] = (matDemandGoalCount[mID] or 0) + 1
                end
              end
            end
          end
        end

        if #viableOpts > 0 then
          viableByGoal[gKey] = {
            target = t,
            viableOpts = viableOpts,
          }
        end
      end
    end

    local bestStep = nil

    for gKey, info in pairs(viableByGoal) do
      local t = info.target
      local viableOpts = info.viableOpts
      local numViable = #viableOpts
      local tierRank = TIER_ORDER[tostring(t.tier or "")] or 99
      local targetID = tonumber(t.itemID or t.writItemID) or 0

      for _, opt in ipairs(viableOpts) do
        local competingOtherGoals = 0
        local inflexibleOthersBlocked = 0

        for _, m in ipairs(opt.materials or {}) do
          local mID = tonumber(m.itemID)
          local req = math.max(1, math.floor(tonumber(m.unitRequired or m.requiredQty) or 1))
          competingOtherGoals = competingOtherGoals + math.max(0, (matDemandGoalCount[mID] or 1) - 1)
          local freeAfter = getFreeCount(mID) - req

          for otherKey, otherInfo in pairs(viableByGoal) do
            if otherKey ~= gKey and #otherInfo.viableOpts == 1 then
              local otherOpt = otherInfo.viableOpts[1]
              for _, om in ipairs(otherOpt.materials or {}) do
                if tonumber(om.itemID) == mID then
                  local oReq = math.max(1, math.floor(tonumber(om.unitRequired or om.requiredQty) or 1))
                  if freeAfter < oReq then
                    inflexibleOthersBlocked = inflexibleOthersBlocked + 1
                  end
                end
              end
            end
          end
        end

        local retrieveUnits = tonumber(opt.totalRetrieveUnits) or 0
        local isPriced = (opt.isPriced == true)
        local repCost = tonumber(opt.replacementEstimate) or 0
        local optIdx = tonumber(opt.optionIndex) or 1

        local candidateStep = {
          gKey = gKey,
          target = t,
          opt = opt,
          inflexibleOthersBlocked = inflexibleOthersBlocked,
          numViable = numViable,
          competingOtherGoals = competingOtherGoals,
          retrieveUnits = retrieveUnits,
          isPriced = isPriced,
          repCost = repCost,
          tierRank = tierRank,
          targetID = targetID,
          optIdx = optIdx,
        }

        local isBetter = false
        if not bestStep then
          isBetter = true
        elseif candidateStep.inflexibleOthersBlocked ~= bestStep.inflexibleOthersBlocked then
          isBetter = candidateStep.inflexibleOthersBlocked < bestStep.inflexibleOthersBlocked
        elseif candidateStep.numViable ~= bestStep.numViable then
          isBetter = candidateStep.numViable < bestStep.numViable
        elseif candidateStep.competingOtherGoals ~= bestStep.competingOtherGoals then
          isBetter = candidateStep.competingOtherGoals < bestStep.competingOtherGoals
        elseif candidateStep.retrieveUnits ~= bestStep.retrieveUnits then
          isBetter = candidateStep.retrieveUnits < bestStep.retrieveUnits
        elseif candidateStep.isPriced ~= bestStep.isPriced then
          isBetter = candidateStep.isPriced
        elseif candidateStep.isPriced and candidateStep.repCost ~= bestStep.repCost then
          isBetter = candidateStep.repCost < bestStep.repCost
        elseif candidateStep.tierRank ~= bestStep.tierRank then
          isBetter = candidateStep.tierRank < bestStep.tierRank
        elseif candidateStep.targetID ~= bestStep.targetID then
          isBetter = candidateStep.targetID < bestStep.targetID
        else
          isBetter = candidateStep.optIdx < bestStep.optIdx
        end

        if isBetter then
          bestStep = candidateStep
        end
      end
    end

    if not bestStep then
      break
    end

    local winKey = bestStep.gKey
    local winTarget = bestStep.target
    local winOpt = bestStep.opt
    local winKind = winTarget.writItemID and "writ" or (winTarget.kind or "crate")
    local winTargetID = tonumber(winTarget.itemID or winTarget.writItemID) or 0
    local winOptIdx = tonumber(winOpt.optionIndex) or 1

    remainingOwnedByKey[winKey] = (remainingOwnedByKey[winKey] or 1) - 1
    chosenOptionByKey[winKey] = winOptIdx

    local existingSim = nil
    for _, r in ipairs(simulatedReservations) do
      if r.goalKey == winKey then
        existingSim = r
        break
      end
    end

    if existingSim then
      existingSim.quantity = (tonumber(existingSim.quantity) or 1) + 1
      for _, m in ipairs(existingSim.materials or {}) do
        local uq = math.max(1, math.floor(tonumber(m.unitQuantity) or 1))
        m.quantity = uq * existingSim.quantity
      end
    else
      local unitMats = {}
      local scaledMats = {}
      for _, m in ipairs(winOpt.materials or {}) do
        local uq = math.max(1, math.floor(tonumber(m.unitRequired or m.requiredQty) or 1))
        table.insert(unitMats, {
          itemID = tonumber(m.itemID),
          name = m.name,
          quantity = uq,
        })
        table.insert(scaledMats, {
          itemID = tonumber(m.itemID),
          name = m.name,
          unitQuantity = uq,
          quantity = uq,
        })
      end
      table.insert(simulatedReservations, {
        goalKey = winKey,
        goalID = string.format("%s:%d", winKey, winOptIdx),
        kind = winKind,
        targetItemID = winTargetID,
        targetName = winTarget.name or winKey,
        optionIndex = winOptIdx,
        quantity = 1,
        priority = nextPriority,
        unitMaterials = unitMats,
        materials = scaledMats,
        suggested = true,
      })
      nextPriority = nextPriority + 1
    end
  end

  local finalLedger = ns.Domain.Reservations.BuildAllocationLedger(
    inventorySnapshot,
    simulatedReservations,
    nil,
    includeAltStock
  )

  local suggestedNew = {}
  local addedTurnInsCount = 0
  for _, r in ipairs(simulatedReservations) do
    if r.suggested then
      table.insert(suggestedNew, r)
      addedTurnInsCount = addedTurnInsCount + (tonumber(r.quantity) or 1)
    end
  end

  local totalRetrieveBankUnits = 0
  local totalRetrieveAltUnits = 0
  local unreservedRemainingByItem = {}

  for itemID, entry in pairs(finalLedger.byItem or {}) do
    totalRetrieveBankUnits = totalRetrieveBankUnits + (tonumber(entry.reservedAllocatedBank) or 0)
    totalRetrieveAltUnits = totalRetrieveAltUnits + (tonumber(entry.reservedAllocatedAlt) or 0)
    unreservedRemainingByItem[itemID] = (tonumber(entry.freeBags) or 0) + (tonumber(entry.freeTransfer) or 0)
  end

  return {
    suggestedReservations = suggestedNew,
    allSimulatedReservations = simulatedReservations,
    addedGoalCount = #suggestedNew,
    addedTurnInsCount = addedTurnInsCount,
    preservedGoalKeys = preservedGoalKeys,
    totalRetrieveBankUnits = totalRetrieveBankUnits,
    totalRetrieveAltUnits = totalRetrieveAltUnits,
    unreservedRemainingByItem = unreservedRemainingByItem,
  }
end
