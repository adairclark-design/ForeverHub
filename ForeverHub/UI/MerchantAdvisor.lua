local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.UI = ns.UI or {}

local Theme = ns.UI.Theme
local Widgets = ns.UI.Widgets

local MerchantAdvisor = {
  frame = nil,
  active = false,
  lastEvaluation = nil,
}
ns.UI.MerchantAdvisor = MerchantAdvisor

local PANEL_WIDTH = 312
local PANEL_PADDING = 12

local function extractNpcIdFromGuid(guid)
  if type(guid) ~= "string" then
    return nil, nil
  end
  local unitType, _, _, _, _, npcIdStr = string.match(guid, "^([A-Za-z]+)%-(%d+)%-(%d+)%-(%d+)%-(%d+)%-(%d+)%-")
  local npcID = tonumber(npcIdStr)
  if npcID and npcID > 0 then
    return npcID, string.lower(tostring(unitType or "creature"))
  end
  return nil, nil
end

local function formatCopper(copper)
  if ns.Compat and type(ns.Compat.FormatCopper) == "function" then
    return ns.Compat.FormatCopper(copper)
  end
  return tostring(math.floor(tonumber(copper) or 0)) .. "c"
end

local function resolveObservedAhAskCopper(itemID)
  local auc = ns.Providers and ns.Providers.Auctionator
  if auc and type(auc.GetObservedSessionLotsForItem) == "function" then
    local lots = auc.GetObservedSessionLotsForItem(itemID)
    if type(lots) == "table" and #lots > 0 then
      local best = nil
      for _, lot in ipairs(lots) do
        local ss = tonumber(lot.stackSize) or 0
        local bo = tonumber(lot.buyoutCopper) or 0
        if ss >= 1 and bo > 0 then
          local unitAsk = math.floor(bo / ss)
          if unitAsk > 0 and (best == nil or unitAsk < best) then
            best = unitAsk
          end
        end
      end
      if best then
        return best, "session_lot"
      end
    end
  end
  if auc and type(auc.GetItemPriceInfo) == "function" then
    local pInfo = auc.GetItemPriceInfo(itemID)
    if type(pInfo) == "table" and type(pInfo.unitPrice) == "number" and pInfo.unitPrice > 0 and not pInfo.isStale then
      return math.floor(pInfo.unitPrice), "cached_summary"
    end
  end
  return nil, nil
end

local function anchorToMerchantFrame(f)
  if not f then
    return
  end
  if f.ClearAllPoints then
    f:ClearAllPoints()
  end
  local mf = _G.MerchantFrame
  if mf and type(mf.SetPoint) == "function" then
    f:SetPoint("TOPLEFT", mf, "TOPRIGHT", 8, -14)
    f.appliedAnchorMode = "merchant_right"
  else
    f:SetPoint("CENTER", _G.UIParent, "CENTER", 280, 40)
    f.appliedAnchorMode = "center_fallback"
  end
end

function MerchantAdvisor.EnsureFrame()
  if MerchantAdvisor.frame then
    return MerchantAdvisor.frame
  end
  if type(CreateFrame) ~= "function" then
    return nil
  end
  if type(InCombatLockdown) == "function" and InCombatLockdown() == true then
    MerchantAdvisor.pendingCombatShow = true
    return nil
  end
  -- Astra Section 5 Taint Guardrail: Strictly parented to `_G.UIParent`!
  local parent = _G.UIParent
  local f = (Widgets and Widgets.CreatePanel and Widgets.CreatePanel(parent, "surface.window", "border.gold"))
    or CreateFrame("Frame", nil, parent)
  if not f then
    return nil
  end
  f.parentedToUIParent = (parent == _G.UIParent)
  if f.SetSize then
    f:SetSize(PANEL_WIDTH, 186)
  end
  if f.SetFrameStrata then
    pcall(f.SetFrameStrata, f, "HIGH")
  end

  f.title = Widgets and Widgets.SafeCreateFontString and Widgets.SafeCreateFontString(f, "sectionTitle", "accent.gold") or nil
  f.junkLine = Widgets and Widgets.SafeCreateFontString and Widgets.SafeCreateFontString(f, "body", "text.primary") or nil
  f.spaceLine = Widgets and Widgets.SafeCreateFontString and Widgets.SafeCreateFontString(f, "dense", "text.secondary") or nil
  f.offerLine = Widgets and Widgets.SafeCreateFontString and Widgets.SafeCreateFontString(f, "dense", "accent.crystal") or nil
  f.guardLine = Widgets and Widgets.SafeCreateFontString and Widgets.SafeCreateFontString(f, "dense", "text.muted") or nil

  local innerW = PANEL_WIDTH - (PANEL_PADDING * 2)
  local y = -PANEL_PADDING
  for _, fs in ipairs({ f.title, f.junkLine, f.spaceLine, f.offerLine, f.guardLine }) do
    if fs then
      if fs.ClearAllPoints then fs:ClearAllPoints() end
      if fs.SetPoint then fs:SetPoint("TOPLEFT", f, "TOPLEFT", PANEL_PADDING, y) end
      if fs.SetWidth then pcall(fs.SetWidth, fs, innerW) end
      if fs.SetJustifyH then pcall(fs.SetJustifyH, fs, "LEFT") end
      if fs.SetWordWrap then pcall(fs.SetWordWrap, fs, true) end
      y = y - 30
    end
  end
  if f.Hide then
    f:Hide()
  end
  MerchantAdvisor.frame = f
  return f
end

function MerchantAdvisor.EvaluateCurrentSession(overrides)
  overrides = type(overrides) == "table" and overrides or {}
  local pp = ns.Domain and ns.Domain.ProtectionPolicy
  if not pp then
    return nil
  end

  local bagSlots = overrides.bagSlots
  if type(bagSlots) ~= "table" and ns.Compat and type(ns.Compat.SnapshotDetailedPlayerBagSlots) == "function" then
    bagSlots = ns.Compat.SnapshotDetailedPlayerBagSlots()
  end
  local recovery = pp.EvaluateSafeInventoryRecovery(bagSlots or {}, overrides.protectionOpts)

  local resaleCandidates = {}
  local pendingOfferMetadataIDs = {}
  local rejectedOffersCount = 0
  local discoveryRecordedCount = 0

  local rawOffers = overrides.merchantOffers
  if type(rawOffers) ~= "table" then
    rawOffers = {}
    local getNum = _G.GetMerchantNumItems
    local getInfo = _G.GetMerchantItemInfo
    local getLink = _G.GetMerchantItemLink
    if type(getNum) == "function" and type(getInfo) == "function" then
      local okN, numItems = pcall(getNum)
      local count = (okN and type(numItems) == "number") and math.min(120, math.max(0, math.floor(numItems))) or 0
      for idx = 1, count do
        local okM, mName, _, price, quantity, numAvailable, isPurchasable, isUsable, extendedCost = pcall(getInfo, idx)
        if okM then
          local link = nil
          if type(getLink) == "function" then
            local okL, l = pcall(getLink, idx)
            if okL and type(l) == "string" then
              link = l
            end
          end
          local itemID = link and ns.Compat and ns.Compat.ExtractItemID and ns.Compat.ExtractItemID(link) or nil
          if itemID then
            local metaComplete = false
            local bindType = nil
            local itemName = mName
            if type(GetItemInfo) == "function" then
              local okI, iName, _, _, _, _, _, _, _, _, _, _, _, _, bType = pcall(GetItemInfo, link or itemID)
              if okI and type(iName) == "string" and iName ~= "" and type(bType) == "number" then
                metaComplete = true
                bindType = bType
                itemName = iName
              end
            end
            local stockMode = "UNKNOWN"
            local stockQty = nil
            if type(numAvailable) == "number" then
              if numAvailable == -1 then
                stockMode = "UNLIMITED"
              elseif numAvailable >= 0 then
                stockMode = "LIMITED"
                stockQty = math.floor(numAvailable)
              end
            end
            table.insert(rawOffers, {
              slotIndex = idx,
              itemID = itemID,
              itemLink = link,
              displayName = itemName,
              metadataComplete = metaComplete,
              bindType = bindType,
              transferabilityVerified = metaComplete and (bindType == 0 or bindType == 2),
              merchantOfferCurrent = true,
              purchaseEligible = (isPurchasable ~= false) and (isUsable ~= false or bindType == 0 or bindType == 2),
              stockMode = stockMode,
              stockQuantity = stockQty,
              extendedCost = (extendedCost == true),
              bundlePriceCopper = tonumber(price) or 0,
              bundleQuantity = math.max(1, math.floor(tonumber(quantity) or 1)),
            })
          end
        end
      end
    end
  end

  local npcID, npcType = overrides.npcID, overrides.npcType
  local rawNpcGuid = overrides.npcGUID
  if type(rawNpcGuid) ~= "string" and type(UnitGUID) == "function" then
    local okG, guid = pcall(UnitGUID, "npc")
    if okG and type(guid) == "string" then
      rawNpcGuid = guid
    end
  end
  if not npcID and type(rawNpcGuid) == "string" then
    npcID, npcType = extractNpcIdFromGuid(rawNpcGuid)
  end
  local uiMapID = tonumber(overrides.uiMapID)
  if not uiMapID and C_Map and type(C_Map.GetBestMapForUnit) == "function" then
    local okM, m = pcall(C_Map.GetBestMapForUnit, "player")
    if okM and type(m) == "number" then
      uiMapID = m
    end
  end

  local optInDiscovery = ns.State and type(ns.State.IsDiscoveryOptInEnabled) == "function" and ns.State.IsDiscoveryOptInEnabled()
  local vendorPatrol = ns.Domain and ns.Domain.VendorPatrol
  local patrolRecordedCount = 0

  for _, offer in ipairs(rawOffers) do
    local eval = pp.EvaluatePositiveMerchantResaleTradability(offer)
    if eval.status == "PENDING_METADATA" then
      table.insert(pendingOfferMetadataIDs, offer.itemID)
      if ns.UI and ns.UI.Tooltips and ns.UI.Tooltips.QueueDeferredItemLoad then
        ns.UI.Tooltips.QueueDeferredItemLoad(offer.itemID)
      end
    elseif eval.eligible == true then
      local ahAsk, ahSource = resolveObservedAhAskCopper(eval.itemID)
      if ahAsk and ahAsk > eval.effectiveUnitCostCeilCopper then
        table.insert(resaleCandidates, {
          itemID = eval.itemID,
          itemKey = eval.itemKey,
          displayName = tostring(offer.displayName or ("Item #" .. tostring(eval.itemID))),
          unitCostCeilCopper = eval.effectiveUnitCostCeilCopper,
          bundlePriceCopper = eval.bundlePriceCopper,
          bundleQuantity = eval.bundleQuantity,
          observedAhUnitCopper = ahAsk,
          observedAhSource = ahSource,
          stockMode = eval.stockMode,
          stockQuantity = eval.stockQuantity,
        })
      end
    else
      rejectedOffersCount = rejectedOffersCount + 1
    end

    if vendorPatrol
      and type(vendorPatrol.RecordMerchantOfferObservation) == "function"
      and offer.itemID
      and offer.extendedCost ~= true
      and (tonumber(offer.bundlePriceCopper) or 0) > 0
      and (offer.stockMode == "LIMITED" or eval.eligible == true or overrides.recordAllPatrolOffers == true)
    then
      local okVP = vendorPatrol.RecordMerchantOfferObservation({
        rawNpcGuid = rawNpcGuid,
        verifiedNpcID = overrides.npcID,
        npcType = npcType,
        uiMapID = uiMapID,
        itemID = offer.itemID,
        itemKey = eval.itemKey or string.format("i1:base:%d", offer.itemID),
        itemName = offer.displayName,
        bundleQuantity = offer.bundleQuantity,
        observedClientPriceCopper = offer.bundlePriceCopper,
        stockMode = offer.stockMode,
        stockObserved = offer.stockQuantity,
        extendedCost = offer.extendedCost,
        standingOrDiscountContext = overrides.standingContext or "client_reported_verbatim",
        metadataComplete = (offer.metadataComplete == true),
      })
      if okVP then
        patrolRecordedCount = patrolRecordedCount + 1
      end
    end

    if optInDiscovery and npcID and npcID > 0 and offer.itemID then
      local canonicalKey = eval.itemKey
      if not canonicalKey and ns.Domain and ns.Domain.MarketIdentity and type(ns.Domain.MarketIdentity.ClassifyItemIdentity) == "function" then
        local okK, kRes = pcall(ns.Domain.MarketIdentity.ClassifyItemIdentity, {
          itemID = offer.itemID,
          itemLink = offer.itemLink,
          isVariantCapable = false,
        })
        if okK and type(kRes) == "table" and type(kRes.itemKey) == "string" then
          canonicalKey = kRes.itemKey
        end
      end
      canonicalKey = canonicalKey or string.format("i1:base:%d", offer.itemID)
      local okD = ns.State.RecordDiscoveryCandidate("merchant_offer", {
        subjectKey = string.format("merchant:%s:%d:%s", tostring(npcType or "creature"), npcID, canonicalKey),
        npcType = npcType or "creature",
        npcID = npcID,
        uiMapID = uiMapID or 0,
        itemKey = canonicalKey,
        bundleQuantity = offer.bundleQuantity,
        bundlePriceCopper = offer.bundlePriceCopper,
        stockQuantity = offer.stockQuantity,
        stockMode = offer.stockMode,
        bindingStatus = eval.bindingStatus or (offer.metadataComplete and "NON_TRADABLE" or "UNKNOWN"),
        metadataComplete = (offer.metadataComplete == true),
        extendedCost = (offer.extendedCost == true),
        purchaseEligible = (offer.purchaseEligible == true),
        standingOrDiscountContext = tostring(overrides.standingContext or "live_observed"),
        phaseOrAccessContext = tostring(overrides.phaseContext or "live_observed"),
      })
      if okD then
        discoveryRecordedCount = discoveryRecordedCount + 1
      end
    end
  end

  local result = {
    recovery = recovery,
    resaleCandidates = resaleCandidates,
    pendingOfferMetadataIDs = pendingOfferMetadataIDs,
    rejectedOffersCount = rejectedOffersCount,
    discoveryRecordedCount = discoveryRecordedCount,
    patrolRecordedCount = patrolRecordedCount,
    automatedActionsPerformed = false,
  }
  MerchantAdvisor.lastEvaluation = result
  return result
end

function MerchantAdvisor.Render(evalResult)
  local eval = evalResult or MerchantAdvisor.EvaluateCurrentSession()
  if not eval then
    return nil
  end
  local f = MerchantAdvisor.EnsureFrame()
  if not f then
    return eval
  end
  anchorToMerchantFrame(f)

  local junk = eval.recovery and eval.recovery.knownVendorJunk or { slotCount = 0, totalVendorCopper = 0 }
  local cons = eval.recovery and eval.recovery.stackConsolidation or { totalSlotsRecoverable = 0 }
  local altStore = eval.recovery and eval.recovery.safeStorageAlternatives or { unreservedTradeGoodSlotsForBankOrAlt = 0 }

  if f.title and f.title.SetText then
    f.title:SetText("ForeverHub Merchant Guide")
  end
  if f.junkLine and f.junkLine.SetText then
    if (junk.slotCount or 0) > 0 then
      f.junkLine:SetText(
        string.format(
          "Known unbound gray junk: %d slot(s) = %s (manual sell only)",
          junk.slotCount,
          formatCopper(junk.totalVendorCopper or 0)
        )
      )
    else
      f.junkLine:SetText("Known unbound gray junk: 0 slots in bags")
    end
  end
  if f.spaceLine and f.spaceLine.SetText then
    f.spaceLine:SetText(
      string.format(
        "Safe bag recovery: %d slot(s) via same-bag stack merge · %d unreserved trade-good slot(s) bankable",
        cons.totalSlotsRecoverable or 0,
        altStore.unreservedTradeGoodSlotsForBankOrAlt or 0
      )
    )
  end
  if f.offerLine and f.offerLine.SetText then
    if #(eval.resaleCandidates or {}) > 0 then
      local top = eval.resaleCandidates[1]
      f.offerLine:SetText(
        string.format(
          "Tradable offer check: %s (%s/ea vendor cost vs %s observed AH; verify demand before buying)",
          top.displayName,
          formatCopper(top.unitCostCeilCopper),
          formatCopper(top.observedAhUnitCopper)
        )
      )
    elseif #(eval.pendingOfferMetadataIDs or {}) > 0 then
      f.offerLine:SetText(string.format("Offer metadata loading (%d item(s) pending binding check)", #eval.pendingOfferMetadataIDs))
    else
      f.offerLine:SetText("Offers checked: positive tradability enforced (BoP/uncached/token offers excluded)")
    end
  end
  if f.guardLine and f.guardLine.SetText then
    f.guardLine:SetText("0c, bound, quest, tool & reserved items stay protected. Zero item-destruction advice.")
  end

  if f.Show then
    f:Show()
  end
  return eval
end

function MerchantAdvisor.OnMerchantShow()
  MerchantAdvisor.active = true
  return MerchantAdvisor.Render()
end

function MerchantAdvisor.OnMerchantClosed()
  MerchantAdvisor.active = false
  MerchantAdvisor.pendingCombatShow = false
  if type(InCombatLockdown) == "function" and InCombatLockdown() == true then
    MerchantAdvisor.pendingCombatHide = true
    return
  end
  if MerchantAdvisor.frame and MerchantAdvisor.frame.Hide then
    MerchantAdvisor.frame:Hide()
  end
end

function MerchantAdvisor.FlushDeferredIfReady()
  if type(InCombatLockdown) == "function" and InCombatLockdown() == true then
    return
  end
  if MerchantAdvisor.pendingCombatHide then
    MerchantAdvisor.pendingCombatHide = false
    MerchantAdvisor.pendingCombatShow = false
    if MerchantAdvisor.frame and MerchantAdvisor.frame.Hide then
      MerchantAdvisor.frame:Hide()
    end
  elseif MerchantAdvisor.pendingCombatShow and MerchantAdvisor.active then
    MerchantAdvisor.pendingCombatShow = false
    MerchantAdvisor.Render(MerchantAdvisor.lastEvaluation)
  end
end

function MerchantAdvisor.RefreshIfActive()
  if MerchantAdvisor.active then
    return MerchantAdvisor.Render()
  end
  return nil
end

return MerchantAdvisor
