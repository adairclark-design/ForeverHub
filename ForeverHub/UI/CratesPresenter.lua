local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.UI = ns.UI or {}

local Theme = ns.UI.Theme
local CratesPresenter = {}
ns.UI.CratesPresenter = CratesPresenter

local function shallowCopyReservation(res)
  if type(res) ~= "table" then
    return nil
  end
  local out = {}
  for k, v in pairs(res) do
    if type(v) == "table" then
      local list = {}
      for i, item in ipairs(v) do
        if type(item) == "table" then
          local mc = {}
          for mk, mv in pairs(item) do
            mc[mk] = mv
          end
          list[i] = mc
        else
          list[i] = item
        end
      end
      out[k] = list
    else
      out[k] = v
    end
  end
  return out
end

local function cloneInventorySnapshot(rawSnap)
  local snap = {}
  for itemID, entry in pairs(rawSnap or {}) do
    local id = tonumber(itemID)
    if id then
      if type(entry) == "table" then
        snap[id] = {
          bagCount = tonumber(entry.bagCount) or 0,
          bankCount = tonumber(entry.bankCount) or 0,
          altCount = tonumber(entry.altCount) or 0,
          altEligibleCount = tonumber(entry.altEligibleCount or entry.altCount) or 0,
          altUnknownCount = tonumber(entry.altUnknownCount) or 0,
          altIneligibleCount = tonumber(entry.altIneligibleCount) or 0,
        }
      elseif type(entry) == "number" then
        snap[id] = {
          bagCount = entry,
          bankCount = 0,
          altCount = 0,
          altEligibleCount = 0,
          altUnknownCount = 0,
          altIneligibleCount = 0,
        }
      end
    end
  end
  return snap
end

-- Captures all live/cached domain inputs up front so `CratesPresenter.Build(...)` is 100% pure.
function CratesPresenter.CaptureSnapshot(opts)
  opts = type(opts) == "table" and opts or {}

  local rawSnap = opts.inventorySnapshot
    or (ns.Providers and ns.Providers.Inventory and ns.Providers.Inventory.GetAggregatedSnapshot and ns.Providers.Inventory.GetAggregatedSnapshot())
    or {}
  local invSnap = cloneInventorySnapshot(rawSnap)

  local bankMeta = opts.bankMeta
    or (ns.Providers and ns.Providers.Inventory and ns.Providers.Inventory.GetBankAttributionMeta and ns.Providers.Inventory.GetBankAttributionMeta())
    or { authority = "none", label = "Bank: Unvisited", complete = false }

  local rawRes = opts.orderedReservations
    or (ns.State and ns.State.GetOrderedReservations and ns.State.GetOrderedReservations())
    or {}
  local orderedRes = {}
  for i, r in ipairs(rawRes) do
    orderedRes[i] = shallowCopyReservation(r)
  end

  local includeAltStock = opts.includeAltStock
  if includeAltStock == nil then
    includeAltStock = (ns.State and ns.State.GetIncludeAltStock and ns.State.GetIncludeAltStock()) or false
  end

  local acquisitionMode = opts.acquisitionMode
  if acquisitionMode == nil then
    acquisitionMode = (ns.State and ns.State.GetAcquisitionMode and ns.State.GetAcquisitionMode()) or "after_bank"
  end
  if acquisitionMode ~= "bags_only" then
    acquisitionMode = "after_bank"
  end

  local data = ns.Data or {}
  local cratesByID = opts.cratesByItemID or data.cratesByItemID or {}
  local writsByID = opts.writsByItemID or data.writsByItemID or {}
  local sealedByID = opts.sealedCratesByItemID or data.sealedCratesByItemID or {}

  -- Capture price info map once up front so `Build` never queries mutable provider state.
  local priceMap = {}
  if type(opts.priceMap) == "table" then
    for k, v in pairs(opts.priceMap) do
      priceMap[tonumber(k) or k] = v
    end
  elseif ns.Providers and ns.Providers.Auctionator and type(ns.Providers.Auctionator.GetItemPriceInfo) == "function" then
    local seenMat = {}
    for _, crate in pairs(cratesByID) do
      for _, alt in ipairs((type(crate) == "table" and crate.alternatives) or {}) do
        for _, mat in ipairs(alt.materials or {}) do
          local mID = tonumber(mat.itemID)
          if mID and not seenMat[mID] then
            seenMat[mID] = true
            priceMap[mID] = ns.Providers.Auctionator.GetItemPriceInfo(mID)
          end
        end
      end
    end
    for _, writ in pairs(writsByID) do
      local mID = tonumber(type(writ) == "table" and writ.targetItemID)
      if mID and not seenMat[mID] then
        seenMat[mID] = true
        priceMap[mID] = ns.Providers.Auctionator.GetItemPriceInfo(mID)
      end
    end
  end

  local rawColState = opts.bankCollectionState
    or (ns.Providers and ns.Providers.Inventory and ns.Providers.Inventory.GetBankCollectionState and ns.Providers.Inventory.GetBankCollectionState())
    or nil
  local colState = nil
  if type(rawColState) == "table" then
    colState = {
      active = (rawColState.active == true),
      lastMessage = rawColState.lastMessage,
    }
  end

  return {
    inventorySnapshot = invSnap,
    bankMeta = {
      authority = bankMeta.authority or "none",
      label = bankMeta.label or "Bank: Unvisited",
      complete = (bankMeta.complete == true),
    },
    orderedReservations = orderedRes,
    includeAltStock = (includeAltStock == true),
    acquisitionMode = acquisitionMode,
    cratesByItemID = cratesByID,
    writsByItemID = writsByID,
    sealedCratesByItemID = sealedByID,
    dataMeta = data.meta or {},
    priceMap = priceMap,
    bankOpen = (opts.bankOpen ~= nil) and (opts.bankOpen == true) or ((ns.State and ns.State.bankOpen) == true),
    bankCollectionState = colState,
    canUndoLastAction = (opts.canUndoLastAction ~= nil)
      and (opts.canUndoLastAction == true)
      or ((ns.State and ns.State.CanUndoLastSuggestion and ns.State.CanUndoLastSuggestion()) == true),
    lastUndoReason = opts.lastUndoReason or (ns.State and ns.State.lastUndoReason) or "suggest_ready",
    pendingSuggestionPreview = opts.pendingSuggestionPreview,
  }
end

local function buildBestCriterionLabel(bestOpt, eval)
  if not bestOpt then
    return nil, nil
  end
  if bestOpt.canFillFromBagsNow then
    return "Best · Ready in bags", {
      "Requires 0 purchases; all required materials are unreserved in your bags.",
    }
  end
  if eval.acquisitionMode ~= "bags_only" and bestOpt.canFillWithTransfer then
    return "Best · 0c buy w/ bank", {
      "Requires 0 purchases after retrieving stored materials.",
    }
  end
  if eval.coverageStatus == "partial" then
    return "Best · Lowest known buy cost", {
      "Lowest estimated purchase cost among priced alternatives.",
      "One or more sibling alternatives currently have no cached Auctionator price.",
    }
  end
  return "Best · Lowest buy cost", {
    "Lowest estimated Auctionator purchase cost across all alternatives.",
  }
end

local function formatCompactOptionSummary(opt, acquisitionMode)
  if not opt then
    return "No option data"
  end
  local matParts = {}
  for _, m in ipairs(opt.materials or {}) do
    table.insert(matParts, string.format("%d× %s", tonumber(m.requiredQty) or 1, tostring(m.name or ("Item " .. tostring(m.itemID)))))
  end
  local matsText = table.concat(matParts, " + ")

  local statusParts = {}
  local buyUnits = (acquisitionMode == "bags_only")
    and (tonumber(opt.totalBagDeficitUnits) or 0)
    or (tonumber(opt.totalTransferDeficitUnits) or 0)
  local retrUnits = (acquisitionMode == "bags_only") and 0 or (tonumber(opt.totalRetrieveUnits) or 0)
  local estCopper = (acquisitionMode == "bags_only") and opt.bagDeficitEstimate or opt.transferDeficitEstimate
  local estKnown = (acquisitionMode == "bags_only") and opt.isBagDeficitKnown or opt.isTransferDeficitKnown

  if buyUnits == 0 and retrUnits == 0 then
    table.insert(statusParts, Theme.Colorize("status.ready", "In bags"))
  else
    if retrUnits > 0 then
      table.insert(statusParts, Theme.Colorize("status.bank", string.format("Retrieve %d", retrUnits)))
    end
    if buyUnits > 0 then
      local costStr = estKnown
        and Theme.FormatMoney(estCopper, { estimated = (estCopper and estCopper > 0) })
        or Theme.Colorize("text.muted", "Unpriced")
      table.insert(statusParts, Theme.Colorize("status.buy", string.format("Buy %d", buyUnits)) .. " (" .. costStr .. ")")
    end
  end

  if #statusParts > 0 then
    return matsText .. "  ·  " .. table.concat(statusParts, " · ")
  end
  return matsText
end

local function matchesSearchQuery(record, evalOptions, needle)
  if not needle or needle == "" then
    return true, false
  end
  if string.find(string.lower(tostring(record.name or "")), needle, 1, true) then
    return true, false
  end
  if record.profession and string.find(string.lower(tostring(record.profession)), needle, 1, true) then
    return true, false
  end
  if record.tier and string.find(string.lower(tostring(record.tier)), needle, 1, true) then
    return true, false
  end
  for _, opt in ipairs(evalOptions or {}) do
    for _, m in ipairs(opt.materials or {}) do
      if string.find(string.lower(tostring(m.name or "")), needle, 1, true) then
        return true, true
      end
    end
  end
  return false, false
end

-- Pure Presenter: transforms `(snapshot, uiState, draftState)` into a complete deterministic `viewModel`.
-- NEVER mutates SavedVariables, reservation state, quest discovery, or navigation ownership.
function CratesPresenter.Build(snapshot, uiState, draftState)
  snapshot = type(snapshot) == "table" and snapshot or CratesPresenter.CaptureSnapshot()
  uiState = type(uiState) == "table" and uiState or {}
  local cratesView = type(uiState.cratesView) == "table" and uiState.cratesView or {}
  local draftByKey = (type(draftState) == "table" and type(draftState.byGoalKey) == "table") and draftState.byGoalKey or {}

  local invSnap = snapshot.inventorySnapshot or {}
  local orderedRes = snapshot.orderedReservations or {}
  local includeAlt = (snapshot.includeAltStock == true)
  local acqMode = (snapshot.acquisitionMode == "bags_only") and "bags_only" or "after_bank"
  local priceMap = snapshot.priceMap or {}
  local bankMeta = snapshot.bankMeta or { label = "Bank: Unvisited" }

  local resByGoalKey = {}
  for _, r in ipairs(orderedRes) do
    if type(r) == "table" then
      local gk = r.goalKey or string.format("%s:%d", tostring(r.kind or "crate"), tonumber(r.targetItemID) or 0)
      resByGoalKey[gk] = r
    end
  end

  local shoppingPlan = ns.Domain.Reservations.BuildShoppingPlan(acqMode, invSnap, orderedRes, includeAlt)
  local readySummary = ns.Domain.Reservations.BuildReadySummary(invSnap, orderedRes, includeAlt, bankMeta)
  local bankColPlan = ns.Domain.Reservations.BuildBankCollectionPlan(invSnap, orderedRes, includeAlt)

  local readyByGoalKey = {}
  for _, rg in ipairs(readySummary.goals or {}) do
    readyByGoalKey[rg.goalKey] = rg
  end

  -- Compute Estimated Purchases KPI with strict truthful pricing rules (never 0c for unpriced)
  local buyItemsCount = 0
  local pricedBuyItemsCount = 0
  local unpricedBuyItemsCount = 0
  local pricedBuySubtotalCopper = 0
  local totalBuyUnits = 0
  local totalRetrieveUnits = 0

  for _, pItem in ipairs(shoppingPlan.items or {}) do
    totalRetrieveUnits = totalRetrieveUnits + (tonumber(pItem.retrieveQty) or 0)
    local bQty = tonumber(pItem.buyQty) or 0
    if bQty > 0 then
      buyItemsCount = buyItemsCount + 1
      totalBuyUnits = totalBuyUnits + bQty
      local pInfo = priceMap[tonumber(pItem.itemID)]
      local uPrice = type(pInfo) == "table" and tonumber(pInfo.unitPrice) or tonumber(pInfo)
      if uPrice and uPrice > 0 then
        pricedBuyItemsCount = pricedBuyItemsCount + 1
        pricedBuySubtotalCopper = pricedBuySubtotalCopper + (bQty * math.floor(uPrice + 0.5))
      else
        unpricedBuyItemsCount = unpricedBuyItemsCount + 1
      end
    end
  end

  -- Gather all targets and compute owned readiness counts even when 0 goals are reserved
  local rawQuery = tostring(cratesView.searchQuery or "")
  local trimmedQuery = string.gsub(rawQuery, "^%s*(.-)%s*$", "%1")
  local needle = string.lower(trimmedQuery)
  local scope = (cratesView.scope == "all") and "all" or "owned_planned"
  local readyOnly = (cratesView.readyOnly == true)
  local expandedByKey = type(cratesView.expandedByKey) == "table" and cratesView.expandedByKey or {}

  local allCandidates = {}
  local ownedFillableInBagsTurnIns = 0
  local ownedFillableAfterBankTurnIns = 0
  local totalOwnedTargetsCount = 0

  local function collectRecord(kind, itemID, record)
    local id = tonumber(itemID)
    if not id or type(record) ~= "table" then
      return
    end
    local counts = invSnap[id] or {}
    local bagCount = math.max(0, math.floor(tonumber(counts.bagCount) or 0))
    local bankCount = math.max(0, math.floor(tonumber(counts.bankCount) or 0))
    local charOwned = bagCount + bankCount
    local altCrates = math.max(0, math.floor(tonumber(counts.altEligibleCount or counts.altCount) or 0))
      + math.max(0, math.floor(tonumber(counts.altUnknownCount) or 0))
      + math.max(0, math.floor(tonumber(counts.altIneligibleCount) or 0))

    local goalKey = string.format("%s:%d", kind, id)
    local existingRes = resByGoalKey[goalKey]

    -- Evaluate baseline 1x to check immediate readiness and search matches cleanly
    local baseEval = ns.Domain.Costs.EvaluateTargetOptions(
      kind,
      record,
      priceMap,
      invSnap,
      orderedRes,
      1,
      includeAlt,
      acqMode
    )

    local anyBagsNow = false
    local anyAfterBank = false
    for _, opt in ipairs((baseEval and baseEval.options) or {}) do
      if opt.canFillFromBagsNow and not opt.consumesReservedStock then
        anyBagsNow = true
      end
      if opt.canFillWithTransfer and not opt.consumesReservedStock then
        anyAfterBank = true
      end
    end

    if charOwned > 0 then
      totalOwnedTargetsCount = totalOwnedTargetsCount + 1
      if bagCount > 0 and anyBagsNow then
        ownedFillableInBagsTurnIns = ownedFillableInBagsTurnIns + 1
      end
      if anyAfterBank then
        ownedFillableAfterBankTurnIns = ownedFillableAfterBankTurnIns + 1
      end
    end

    local inScope = false
    if scope == "all" then
      inScope = (kind == "crate") or (charOwned > 0) or (existingRes ~= nil) or (needle ~= "")
    else
      inScope = (charOwned > 0) or (existingRes ~= nil)
    end
    if not inScope then
      return
    end

    local rg = readyByGoalKey[goalKey]
    local isCardReadyForFilter = false
    if existingRes then
      if acqMode == "bags_only" then
        isCardReadyForFilter = ((rg and rg.readyInBagsNow or 0) > 0)
      else
        isCardReadyForFilter = ((rg and rg.readyAfterBank or 0) > 0)
      end
    else
      if acqMode == "bags_only" then
        isCardReadyForFilter = (bagCount > 0 and anyBagsNow)
      else
        isCardReadyForFilter = (charOwned > 0 and anyAfterBank)
      end
    end

    if readyOnly and not isCardReadyForFilter then
      return
    end

    local matchedQuery, matchedMaterial = matchesSearchQuery(record, baseEval and baseEval.options, needle)
    if not matchedQuery then
      return
    end

    table.insert(allCandidates, {
      kind = kind,
      itemID = id,
      goalKey = goalKey,
      record = record,
      bagCount = bagCount,
      bankCount = bankCount,
      charOwned = charOwned,
      altCrates = altCrates,
      existingRes = existingRes,
      baseEval = baseEval,
      readyGoal = rg,
      anyBagsNow = anyBagsNow,
      anyAfterBank = anyAfterBank,
      matchedMaterial = matchedMaterial,
    })
  end

  for itemID, crate in pairs(snapshot.cratesByItemID or {}) do
    collectRecord("crate", itemID, crate)
  end
  for itemID, writ in pairs(snapshot.writsByItemID or {}) do
    collectRecord("writ", itemID, writ)
  end

  table.sort(allCandidates, function(a, b)
    local aRes = (a.existingRes ~= nil)
    local bRes = (b.existingRes ~= nil)
    if aRes ~= bRes then
      return aRes
    end
    if aRes and bRes then
      local pa = tonumber(a.existingRes.priority) or 999
      local pb = tonumber(b.existingRes.priority) or 999
      if pa ~= pb then
        return pa < pb
      end
    end
    local aInBagsReady = (a.bagCount > 0 and a.anyBagsNow)
    local bInBagsReady = (b.bagCount > 0 and b.anyBagsNow)
    if aInBagsReady ~= bInBagsReady then
      return aInBagsReady
    end
    if (a.charOwned > 0) ~= (b.charOwned > 0) then
      return a.charOwned > 0
    end
    if a.kind ~= b.kind then
      return a.kind == "crate"
    end
    return a.itemID < b.itemID
  end)

  -- Build Card ViewModels
  local totalReservedGoals = #orderedRes
  local cards = {}

  for idx, c in ipairs(allCandidates) do
    local draftEntry = draftByKey[c.goalKey]
    local rawOpts = (c.baseEval and c.baseEval.options) or {}
    local validOptSet = {}
    for _, o in ipairs(rawOpts) do
      validOptSet[tonumber(o.optionIndex) or 1] = true
    end

    local defaultOptIdx = (c.existingRes and tonumber(c.existingRes.optionIndex))
      or (c.baseEval and c.baseEval.bestOption and tonumber(c.baseEval.bestOption.optionIndex))
      or 1
    local selectedOptIdx = (draftEntry and validOptSet[tonumber(draftEntry.selectedOptionIndex)])
        and tonumber(draftEntry.selectedOptionIndex)
      or defaultOptIdx
    if not validOptSet[selectedOptIdx] then
      selectedOptIdx = 1
    end

    local defaultDraftQty = (c.existingRes and math.max(1, math.floor(tonumber(c.existingRes.quantity) or 1))) or 1
    local draftQty = (draftEntry and tonumber(draftEntry.draftQuantity))
        and math.max(1, math.min(999, math.floor(tonumber(draftEntry.draftQuantity))))
      or defaultDraftQty

    local evalAtDraft = (draftQty == 1 and c.baseEval)
      or ns.Domain.Costs.EvaluateTargetOptions(
        c.kind,
        c.record,
        priceMap,
        invSnap,
        orderedRes,
        draftQty,
        includeAlt,
        acqMode
      )

    local bestOpt = evalAtDraft and evalAtDraft.bestOption or nil
    local bestLabel, bestTooltip = buildBestCriterionLabel(bestOpt, evalAtDraft)

    local selectedOptEval = nil
    local optionVMs = {}
    for _, opt in ipairs((evalAtDraft and evalAtDraft.options) or {}) do
      local isSelected = (opt.optionIndex == selectedOptIdx)
      if isSelected then
        selectedOptEval = opt
      end
      local isBest = (bestOpt ~= nil and bestOpt.optionIndex == opt.optionIndex)
      local buyEst = (acqMode == "bags_only") and opt.bagDeficitEstimate or opt.transferDeficitEstimate
      local buyKnown = (acqMode == "bags_only") and opt.isBagDeficitKnown or opt.isTransferDeficitKnown
      local buyUnits = (acqMode == "bags_only")
        and (tonumber(opt.totalBagDeficitUnits) or 0)
        or (tonumber(opt.totalTransferDeficitUnits) or 0)

      local estCostFormatted
      if buyKnown then
        estCostFormatted = Theme.FormatMoney(buyEst, {
          estimated = (buyEst ~= nil and buyEst > 0),
          colorToken = (buyEst == 0) and "status.ready" or "text.primary",
        })
      else
        estCostFormatted = Theme.FormatMoney(nil, { compactMissing = false })
      end

      local repFormatted = opt.isPriced
        and Theme.FormatMoney(opt.replacementEstimate, { estimated = true })
        or Theme.Colorize("text.muted", "Unpriced")

      local matRows = {}
      for _, m in ipairs(opt.materials or {}) do
        local mBuyUnits = (acqMode == "bags_only")
          and (tonumber(m.bagDeficitUnits) or 0)
          or (tonumber(m.transferDeficitUnits) or 0)
        local mEstCopper = (acqMode == "bags_only") and m.bagDeficitCopper or m.transferDeficitCopper
        local mCostStr
        if mBuyUnits == 0 then
          mCostStr = Theme.FormatMoney(0, { colorToken = "text.muted" })
        elseif mEstCopper ~= nil then
          mCostStr = Theme.FormatMoney(mEstCopper, { estimated = true })
        else
          mCostStr = Theme.FormatMoney(nil, { compactMissing = true })
        end

        local bankCellStr = tostring(m.freeBank or 0)
        if includeAlt and (tonumber(m.retrieveAltUnits) or 0) > 0 then
          bankCellStr = string.format("%d (+%d alt)", tonumber(m.freeBank) or 0, tonumber(m.retrieveAltUnits) or 0)
        end

        table.insert(matRows, {
          itemID = m.itemID,
          name = m.name or ("Item " .. tostring(m.itemID)),
          requiredQty = tonumber(m.requiredQty) or 1,
          unitRequired = tonumber(m.unitRequired) or 1,
          requirementLabel = string.format("%d× %s", tonumber(m.requiredQty) or 1, tostring(m.name or ("Item " .. tostring(m.itemID)))),
          freeBags = tonumber(m.freeBags) or 0,
          freeBank = tonumber(m.freeBank) or 0,
          bankCellText = bankCellStr,
          buyUnits = mBuyUnits,
          retrieveUnits = (acqMode == "bags_only") and 0 or ((tonumber(m.retrieveBankUnits) or 0) + (tonumber(m.retrieveAltUnits) or 0)),
          estCostText = mCostStr,
          unitPrice = m.unitPrice,
          isStale = (m.isStale == true),
          reservedHigherPriority = tonumber(m.reservedHigherPriority) or 0,
        })
      end

      local isCommittedExact = (c.existingRes ~= nil)
        and (tonumber(c.existingRes.optionIndex) == opt.optionIndex)
        and (tonumber(c.existingRes.quantity) == draftQty)

      local primaryActionLabel
      if not c.existingRes then
        primaryActionLabel = (draftQty > 1) and string.format("Reserve ×%d", draftQty) or "Reserve"
      elseif isCommittedExact then
        primaryActionLabel = string.format("Saved ×%d", draftQty)
      else
        primaryActionLabel = string.format("Update ×%d", draftQty)
      end

      table.insert(optionVMs, {
        optionIndex = opt.optionIndex,
        label = opt.label,
        isSelected = isSelected,
        isReserved = (opt.isReserved == true),
        isBest = isBest,
        bestLabel = isBest and bestLabel or nil,
        bestTooltip = isBest and bestTooltip or nil,
        consumesReservedStock = (opt.consumesReservedStock == true),
        conflictWarning = opt.conflictWarning,
        displacesLowerPriorityStock = (opt.displacesLowerPriorityStock == true),
        displacementWarning = opt.displacementWarning,
        isStalePrice = (opt.isStalePrice == true),
        buyUnits = buyUnits,
        retrieveUnits = (acqMode == "bags_only") and 0 or (tonumber(opt.totalRetrieveUnits) or 0),
        estCostFormatted = estCostFormatted,
        replacementFormatted = repFormatted,
        canFillFromBagsNow = (opt.canFillFromBagsNow == true),
        canFillWithTransfer = (opt.canFillWithTransfer == true),
        materials = matRows,
        draftQuantity = draftQty,
        isCommittedExact = isCommittedExact,
        primaryActionLabel = primaryActionLabel,
        primaryActionEnabled = not isCommittedExact,
      })
    end

    -- Location text (strictly separated from Ready status; bank-only is NEVER green)
    local locationText
    if c.bagCount > 0 and c.bankCount > 0 then
      locationText = string.format("In bags: %d · In bank: %d", c.bagCount, c.bankCount)
    elseif c.bagCount > 0 then
      locationText = string.format("In bags: %d", c.bagCount)
    elseif c.bankCount > 0 then
      locationText = Theme.Colorize("status.bank", string.format("In bank: %d", c.bankCount))
    else
      locationText = Theme.Colorize("text.muted", "0 owned")
    end

    -- Readiness badge (ONLY green when physically in bags AND materials ready in bags)
    local readinessBadge = nil
    local rg = c.readyGoal
    if c.existingRes and rg then
      if (rg.readyInBagsNow or 0) > 0 then
        readinessBadge = {
          text = string.format("Ready in bags ×%d", rg.readyInBagsNow),
          token = "status.ready",
          glyph = "check",
          tooltipTitle = "Ready to fill right now",
          tooltipLines = { "Both the target crate/writ and reserved materials are in your character's bags." },
        }
      elseif (rg.readyAfterBank or 0) > 0 then
        readinessBadge = {
          text = string.format("After bank ×%d", rg.readyAfterBank),
          token = "status.bank",
          glyph = "bank",
          tooltipTitle = "Ready after bank visit",
          tooltipLines = { "Requires retrieving either the crate/writ or stored materials from your character bank." },
        }
      end
    elseif c.bagCount > 0 and selectedOptEval and selectedOptEval.canFillFromBagsNow and not selectedOptEval.consumesReservedStock then
      readinessBadge = {
        text = "Ready in bags",
        token = "status.ready",
        glyph = "check",
        tooltipTitle = "Fillable from bags now",
        tooltipLines = { "Crate/writ is in your bags and selected option requires 0 purchases or bank pulls." },
      }
    elseif c.charOwned > 0 and selectedOptEval and selectedOptEval.canFillWithTransfer and not selectedOptEval.consumesReservedStock then
      readinessBadge = {
        text = "After bank",
        token = "status.bank",
        glyph = "bank",
        tooltipTitle = "Fillable after bank visit",
        tooltipLines = {
          c.bagCount == 0
            and "Crate/writ is currently stored in your bank (not in bags)."
            or "Selected option uses materials stored in your bank.",
        },
      }
    end

    local reservedBadge = nil
    if c.existingRes then
      reservedBadge = {
        text = string.format("Reserved ×%d · #%d", tonumber(c.existingRes.quantity) or 1, tonumber(c.existingRes.priority) or 1),
        token = "status.reserved",
        glyph = "bookmark",
        tooltipTitle = string.format("Priority #%d Reservation", tonumber(c.existingRes.priority) or 1),
        tooltipLines = {
          string.format("Option #%d · %d planned turn-in(s)", tonumber(c.existingRes.optionIndex) or 1, tonumber(c.existingRes.quantity) or 1),
          "Higher-priority goals claim shared materials first.",
        },
      }
    end

    -- Disclosure state: manual override wins; otherwise auto-expand only if <=2 visible cards or material search hit
    local isExpanded
    if type(expandedByKey[c.goalKey]) == "boolean" then
      isExpanded = expandedByKey[c.goalKey]
    else
      isExpanded = (#allCandidates <= 2) or (c.matchedMaterial == true)
    end

    local summaryPrefix = c.existingRes and "Planned: "
      or ((bestOpt and selectedOptEval and bestOpt.optionIndex == selectedOptEval.optionIndex) and "Recommended: " or "Selected: ")
    local collapsedOptionText = summaryPrefix .. formatCompactOptionSummary(selectedOptEval or bestOpt, acqMode)

    local priorityNum = c.existingRes and (tonumber(c.existingRes.priority) or 1) or nil

    table.insert(cards, {
      index = idx,
      kind = c.kind,
      itemID = c.itemID,
      goalKey = c.goalKey,
      name = c.record.name or ("Item " .. tostring(c.itemID)),
      bagCount = c.bagCount,
      bankCount = c.bankCount,
      charOwned = c.charOwned,
      altCrates = c.altCrates,
      locationText = locationText,
      collapsedSummaryText = locationText .. "   ·   " .. collapsedOptionText,
      isExpanded = isExpanded,
      isReserved = (c.existingRes ~= nil),
      reservedPriority = priorityNum,
      reservedQuantity = c.existingRes and (tonumber(c.existingRes.quantity) or 1) or 0,
      reservedOptionIndex = c.existingRes and (tonumber(c.existingRes.optionIndex) or 1) or nil,
      canMovePriorityUp = (priorityNum ~= nil and priorityNum > 1),
      canMovePriorityDown = (priorityNum ~= nil and priorityNum < totalReservedGoals),
      excessOverOwned = rg and (tonumber(rg.excessOverOwned) or 0) or 0,
      canReduceToOwned = rg and (rg.canReduceToOwned == true) or false,
      reduceBlockReason = rg and rg.reduceBlockReason or nil,
      readinessBadge = readinessBadge,
      reservedBadge = reservedBadge,
      limitationNotice = evalAtDraft and evalAtDraft.limitationNotice or nil,
      quantityVerified = (c.record.quantityVerified ~= false),
      selectedOptionIndex = selectedOptIdx,
      draftQuantity = draftQty,
      totalOptionCount = #optionVMs,
      options = optionVMs,
    })
  end

  -- Build 4 KPI ViewModels
  local hasReservations = (#orderedRes > 0)
  local kpi1Val = hasReservations and tostring(readySummary.totalReadyInBagsNow or 0) or tostring(ownedFillableInBagsTurnIns)
  local sealedSuffix = (readySummary.sealedCratesTotal or 0) > 0
    and string.format(" · %d sealed ready", readySummary.sealedCratesTotal)
    or ""
  local kpi1Sub = hasReservations
    and (string.format("of %d planned", readySummary.totalPlannedTurnIns or 0) .. sealedSuffix)
    or ((ownedFillableInBagsTurnIns > 0 and "Owned & fillable now" or "In character bags") .. sealedSuffix)

  local kpi2Val = hasReservations and tostring(readySummary.totalReadyAfterBank or 0) or tostring(ownedFillableAfterBankTurnIns)
  local kpi2Sub = tostring(bankMeta.label or "Bank: Unvisited")

  local kpi3Val = tostring(readySummary.totalPlannedTurnIns or 0)
  local kpi3Sub = hasReservations
    and string.format("%d goal%s reserved", #orderedRes, #orderedRes == 1 and "" or "s")
    or "No active goals"

  local kpi4Val, kpi4Sub, kpi4Token
  if buyItemsCount == 0 then
    kpi4Val = Theme.FormatMoney(0, { plainText = false })
    kpi4Sub = hasReservations
      and (totalRetrieveUnits > 0 and string.format("Retrieve %d from bank", totalRetrieveUnits) or "All mats owned")
      or "Reserve goals to price"
    kpi4Token = hasReservations and "status.ready" or "text.primary"
  elseif pricedBuyItemsCount == 0 then
    kpi4Val = "Unpriced"
    kpi4Sub = string.format("%d unpriced item%s", unpricedBuyItemsCount, unpricedBuyItemsCount == 1 and "" or "s")
    kpi4Token = "status.warning"
  elseif unpricedBuyItemsCount > 0 then
    kpi4Val = Theme.FormatMoney(pricedBuySubtotalCopper, { estimated = true })
    kpi4Sub = string.format("+ %d unpriced", unpricedBuyItemsCount)
    kpi4Token = "status.buy"
  else
    kpi4Val = Theme.FormatMoney(pricedBuySubtotalCopper, { estimated = true })
    kpi4Sub = string.format("%d item%s (%d units)", buyItemsCount, buyItemsCount == 1 and "" or "s", totalBuyUnits)
    kpi4Token = "status.buy"
  end

  local kpis = {
    {
      value = kpi1Val,
      label = "Ready in bags",
      sub = kpi1Sub,
      colorToken = ((tonumber(kpi1Val) or 0) > 0) and "status.ready" or "text.primary",
      tooltipTitle = "Ready in bags right now",
      tooltipLines = {
        "Requires BOTH the unopened Waylaid Crate/Writ AND all required materials in your character's bags.",
        (readySummary.sealedCratesTotal or 0) > 0
          and string.format("You also have %d Sealed Crate(s) ready for delivery.", readySummary.sealedCratesTotal)
          or "Bank-stored crates appear under 'After bank visit', never here.",
      },
    },
    {
      value = kpi2Val,
      label = "After bank visit",
      sub = kpi2Sub,
      colorToken = ((tonumber(kpi2Val) or 0) > (tonumber(kpi1Val) or 0)) and "status.bank" or "text.primary",
      tooltipTitle = "Fillable after visiting your bank",
      tooltipLines = {
        "Includes crates/writs and unreserved materials stored in your character's bank.",
        "Bank source: " .. tostring(bankMeta.label or "Bank: Unvisited"),
      },
    },
    {
      value = kpi3Val,
      label = "Planned",
      sub = kpi3Sub,
      colorToken = hasReservations and "status.reserved" or "text.primary",
      tooltipTitle = "Reserved turn-in plan",
      tooltipLines = {
        "Priority-ordered reservations protect materials in tooltips and build your bank & Auctionator shopping lists.",
      },
    },
    {
      value = kpi4Val,
      label = "Estimated purchases",
      sub = kpi4Sub,
      colorToken = kpi4Token,
      tooltipTitle = "Estimated Auctionator purchases",
      tooltipLines = {
        acqMode == "bags_only"
          and "Mode: Bags only (ignores bank/alt stock when calculating shopping deficits)."
          or "Mode: Use bank stock (subtracts character bags + bank before buying).",
        "Missing Auctionator prices are shown as Unpriced, never 0c.",
      },
    },
  }

  -- Contextual Action Bar state
  local colState = snapshot.bankCollectionState
  local pullTargetUnits = tonumber(bankColPlan.totalTargetUnits) or 0
  local pullMatUnits = tonumber(bankColPlan.totalMaterialUnits) or 0
  local pullTotalUnits = tonumber(bankColPlan.totalPullUnits) or 0

  local collectBtnLabel = "Collect from bank"
  local collectBtnEnabled = true
  local collectTooltipLines = {}
  if colState and colState.active then
    collectBtnLabel = "Stop bank pull"
    table.insert(collectTooltipLines, "Bank withdrawal is currently running. Click to cancel.")
  elseif pullTotalUnits > 0 then
    collectBtnLabel = string.format("Collect bank (%d)", pullTotalUnits)
    table.insert(
      collectTooltipLines,
      string.format("Withdraw %d planned crate(s)/writ(s) and %d reserved material(s).", pullTargetUnits, pullMatUnits)
    )
    if not snapshot.bankOpen then
      table.insert(collectTooltipLines, "Open your bank frame first to withdraw automatically.")
    end
  else
    collectBtnEnabled = hasReservations and snapshot.bankOpen
    table.insert(
      collectTooltipLines,
      hasReservations
        and "0 reserved crates or materials currently need withdrawal from your character bank."
        or "Reserve at least one crate or writ option first."
    )
  end

  return {
    kpis = kpis,
    filters = {
      searchQuery = rawQuery,
      scope = scope,
      readyOnly = readyOnly,
      includeAltStock = includeAlt,
      acquisitionMode = acqMode,
    },
    altStockNotice = includeAlt
      and "Alt stock is planning information only (uncommitted estimate; not immediately retrievable at your character bank)."
      or nil,
    cards = cards,
    totalVisibleCards = #cards,
    totalOwnedTargetsCount = totalOwnedTargetsCount,
    totalReservedGoals = totalReservedGoals,
    totalPlannedTurnIns = readySummary.totalPlannedTurnIns or 0,
    actionBar = {
      collectLabel = collectBtnLabel,
      collectEnabled = (colState and colState.active) or (pullTotalUnits > 0),
      collectActive = (colState and colState.active == true) or false,
      collectStatusMessage = colState and colState.lastMessage or nil,
      collectTooltipLines = collectTooltipLines,
      bankOpen = snapshot.bankOpen,
      acquisitionMode = acqMode,
      exportEnabled = hasReservations,
      exportBuyItemsCount = buyItemsCount,
      canClearAll = hasReservations,
      canUndo = snapshot.canUndoLastAction,
      lastUndoReason = snapshot.lastUndoReason,
    },
    diagnostics = {
      addonVersion = tostring(ns.version or "0.8.0"),
      corpusRevisionID = tostring((snapshot.dataMeta and snapshot.dataMeta.corpusRevisionID) or "unknown"),
      compiledContentSha256 = tostring((snapshot.dataMeta and snapshot.dataMeta.compiledContentSha256) or "unknown"),
      bankAuthorityLabel = tostring(bankMeta.label or "Bank: Unvisited"),
    },
  }
end

return CratesPresenter
