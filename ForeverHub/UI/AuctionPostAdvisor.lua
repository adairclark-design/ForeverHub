local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.UI = ns.UI or {}

local Widgets = ns.UI.Widgets

local AuctionPostAdvisor = {
  frame = nil,
  active = false,
  expandedDurations = false,
  pendingCombatShow = false,
  pendingCombatHide = false,
  controller = nil,
  manualScenario = {
    stackSize = 1,
    numStacks = 1,
    startingBidPerLotCopper = 0,
    buyoutPerLotCopper = 0,
    durationIndex = 2,
  },
  lastEvaluation = nil,
}
ns.UI.AuctionPostAdvisor = AuctionPostAdvisor

local PANEL_WIDTH = 328
local PANEL_PADDING = 10

local function isPositiveInt(v)
  return type(v) == "number" and v == v and v >= 1 and v < 9007199254740992 and math.floor(v) == v
end

local function isNonNegInt(v)
  return type(v) == "number" and v == v and v >= 0 and v < 9007199254740992 and math.floor(v) == v
end

local function isCombatLocked()
  if ns.Compat and type(ns.Compat.IsInCombat) == "function" then
    return ns.Compat.IsInCombat() == true
  end
  if type(_G.InCombatLockdown) == "function" then
    local ok, locked = pcall(_G.InCombatLockdown)
    return ok and locked == true
  end
  return false
end

local function fmtMoney(copper)
  if not isNonNegInt(copper) then
    return "Unknown"
  end
  if ns.Compat and type(ns.Compat.FormatCopper) == "function" then
    return ns.Compat.FormatCopper(copper)
  end
  return tostring(copper) .. "c"
end

function AuctionPostAdvisor.EnsureController()
  if not AuctionPostAdvisor.controller and ns.Domain and ns.Domain.AuctionPostMath then
    AuctionPostAdvisor.controller = ns.Domain.AuctionPostMath.CreateSessionController()
  end
  return AuctionPostAdvisor.controller
end

-- Read-only inspection of Auctionator Selling tab OR Blizzard Legacy Auctions Sell tab.
-- NEVER writes to Blizzard MoneyInputFrames, NEVER calls StartAuction/PostItem!
function AuctionPostAdvisor.ReadLivePostingFormState(overrides)
  overrides = type(overrides) == "table" and overrides or {}
  if type(overrides.mockFormState) == "table" then
    return overrides.mockFormState
  end

  local getSellInfo = _G.GetAuctionSellItemInfo
  if type(getSellInfo) ~= "function" then
    return { synchronized = false, reason = "sell_item_api_unavailable" }
  end

  local okS, sName, _, sCount, _, _, sVendorTotal, _, _, _, sItemID = pcall(getSellInfo)
  if not okS or sName == nil then
    return { synchronized = false, slotted = false, reason = "no_slotted_sell_item" }
  end

  local itemID = tonumber(sItemID)
  local slottedCount = isPositiveInt(tonumber(sCount)) and math.floor(tonumber(sCount)) or 1
  local unitVendor = nil
  local vendorComplete = false
  if isPositiveInt(itemID) and type(_G.GetItemInfo) == "function" then
    local okI, _, itemLink, _, _, _, _, _, _, _, _, sellPrice, _, _, bindType = pcall(_G.GetItemInfo, itemID)
    if okI and isNonNegInt(tonumber(sellPrice)) then
      unitVendor = math.floor(tonumber(sellPrice))
      vendorComplete = true
      local itemKey = string.format("i1:base:%d", itemID)
      if ns.Domain and ns.Domain.MarketIdentity and type(ns.Domain.MarketIdentity.ClassifyItemIdentity) == "function" and type(itemLink) == "string" then
        local okK, kRes = pcall(ns.Domain.MarketIdentity.ClassifyItemIdentity, { itemID = itemID, itemLink = itemLink })
        if okK and type(kRes) == "table" and type(kRes.itemKey) == "string" then
          itemKey = kRes.itemKey
        end
      end

      -- Path 1: Read-only Auctionator v346 Selling Frame scalar controls (when shown):
      local atr = _G.AuctionatorSellingFrame
      if atr and type(atr) == "table" and type(atr.IsShown) == "function" then
        local okVis, atrShown = pcall(atr.IsShown, atr)
        if okVis and atrShown == true and type(atr.SaleItemFrame) == "table" then
          local sif = atr.SaleItemFrame
          local boStack = nil
          if type(sif.StackPrice) == "table" and type(sif.StackPrice.GetAmount) == "function" then
            local okP, amt = pcall(sif.StackPrice.GetAmount, sif.StackPrice)
            if okP and isNonNegInt(tonumber(amt)) then
              boStack = math.floor(tonumber(amt))
            end
          end
          local stackSize = slottedCount
          local numStacks = 1
          if type(sif.Quantity) == "table" and type(sif.Quantity.GetNumber) == "function" then
            local okQ, qv = pcall(sif.Quantity.GetNumber, sif.Quantity)
            if okQ and isPositiveInt(tonumber(qv)) then
              stackSize = math.floor(tonumber(qv))
            end
          end
          if type(sif.Stacks) == "table" and type(sif.Stacks.NumStacks) == "table" and type(sif.Stacks.NumStacks.GetNumber) == "function" then
            local okN, nv = pcall(sif.Stacks.NumStacks.GetNumber, sif.Stacks.NumStacks)
            if okN and isPositiveInt(tonumber(nv)) then
              numStacks = math.floor(tonumber(nv))
            end
          end
          local durIdx = 2
          if type(sif.Duration) == "table" and type(sif.Duration.GetValue) == "function" then
            local okD, dv = pcall(sif.Duration.GetValue, sif.Duration)
            if okD then
              -- Auctionator internal radio values `12/24/48` or `1/2/3` map cleanly to `1/2/3`:
              if dv == 1 or dv == 12 then durIdx = 1
              elseif dv == 2 or dv == 24 then durIdx = 2
              elseif dv == 3 or dv == 48 then durIdx = 3
              end
            end
          end
          if boStack ~= nil and boStack > 0 then
            return {
              synchronized = true,
              synchronizedSource = "auctionator_selling_readonly",
              slotted = true,
              itemID = itemID,
              itemKey = itemKey,
              bindType = tonumber(bindType),
              stackSize = stackSize,
              numStacks = numStacks,
              startingBidPerLotCopper = boStack,
              buyoutPerLotCopper = boStack,
              durationIndex = durIdx,
              unitVendorCopper = unitVendor,
              vendorMetadataComplete = vendorComplete,
            }
          end
        end
      end

      -- Path 2: Read-only Blizzard Legacy Auctions Frame (`MoneyInputFrame_GetCopper` read-only):
      if type(_G.MoneyInputFrame_GetCopper) == "function" and _G.StartPrice and _G.BuyoutPrice then
        local okB, startBid = pcall(_G.MoneyInputFrame_GetCopper, _G.StartPrice)
        local okBO, buyout = pcall(_G.MoneyInputFrame_GetCopper, _G.BuyoutPrice)
        if okB and okBO and isNonNegInt(tonumber(startBid)) and isNonNegInt(tonumber(buyout)) and (tonumber(startBid) > 0 or tonumber(buyout) > 0) then
          local stackSize = slottedCount
          local numStacks = 1
          if _G.AuctionsStackSizeEntry and type(_G.AuctionsStackSizeEntry.GetNumber) == "function" then
            local okSS, ss = pcall(_G.AuctionsStackSizeEntry.GetNumber, _G.AuctionsStackSizeEntry)
            if okSS and isPositiveInt(tonumber(ss)) then
              stackSize = math.floor(tonumber(ss))
            end
          end
          if _G.AuctionsNumStacksEntry and type(_G.AuctionsNumStacksEntry.GetNumber) == "function" then
            local okNS, nst = pcall(_G.AuctionsNumStacksEntry.GetNumber, _G.AuctionsNumStacksEntry)
            if okNS and isPositiveInt(tonumber(nst)) then
              numStacks = math.floor(tonumber(nst))
            end
          end
          local durIdx = tonumber(_G.AuctionFrameAuctions and _G.AuctionFrameAuctions.duration) or 2
          if durIdx ~= 1 and durIdx ~= 2 and durIdx ~= 3 then
            durIdx = 2
          end
          return {
            synchronized = true,
            synchronizedSource = "blizzard_legacy_auctions_readonly",
            slotted = true,
            itemID = itemID,
            itemKey = itemKey,
            bindType = tonumber(bindType),
            stackSize = stackSize,
            numStacks = numStacks,
            startingBidPerLotCopper = math.floor(tonumber(startBid)),
            buyoutPerLotCopper = math.floor(tonumber(buyout)),
            durationIndex = durIdx,
            unitVendorCopper = unitVendor,
            vendorMetadataComplete = vendorComplete,
          }
        end
      end

      -- Slotted item exists, but native price form controls are unavailable/unprobed -> explicit scenario mode!
      return {
        synchronized = false,
        synchronizedSource = "manual_scenario",
        slotted = true,
        itemID = itemID,
        itemKey = itemKey,
        bindType = tonumber(bindType),
        stackSize = AuctionPostAdvisor.manualScenario.stackSize or slottedCount,
        numStacks = AuctionPostAdvisor.manualScenario.numStacks or 1,
        startingBidPerLotCopper = AuctionPostAdvisor.manualScenario.startingBidPerLotCopper or 0,
        buyoutPerLotCopper = AuctionPostAdvisor.manualScenario.buyoutPerLotCopper or 0,
        durationIndex = AuctionPostAdvisor.manualScenario.durationIndex or 2,
        unitVendorCopper = unitVendor,
        vendorMetadataComplete = vendorComplete,
        reason = "native_price_controls_unverified_fallback_to_scenario",
      }
    end
  elseif isNonNegInt(tonumber(sVendorTotal)) and slottedCount > 0 and (tonumber(sVendorTotal) % slottedCount == 0) then
    unitVendor = math.floor(tonumber(sVendorTotal) / slottedCount)
    vendorComplete = true
  end

  return {
    synchronized = false,
    synchronizedSource = "manual_scenario",
    slotted = true,
    itemID = itemID,
    itemKey = isPositiveInt(itemID) and string.format("i1:base:%d", itemID) or nil,
    stackSize = slottedCount,
    numStacks = 1,
    startingBidPerLotCopper = AuctionPostAdvisor.manualScenario.startingBidPerLotCopper or 0,
    buyoutPerLotCopper = AuctionPostAdvisor.manualScenario.buyoutPerLotCopper or 0,
    durationIndex = AuctionPostAdvisor.manualScenario.durationIndex or 2,
    unitVendorCopper = unitVendor,
    vendorMetadataComplete = vendorComplete,
    reason = "item_metadata_pending_or_manual_scenario",
  }
end

local function anchorPanelScreenSafe(f)
  if not f or isCombatLocked() then
    return
  end
  if f.userMoved == true then
    return
  end
  if f.ClearAllPoints then
    f:ClearAllPoints()
  end
  local ahFrame = _G.AuctionFrame
  local uiParent = _G.UIParent
  if ahFrame and type(ahFrame.SetPoint) == "function" then
    local fitsRight = true
    if uiParent and type(uiParent.GetWidth) == "function" and type(ahFrame.GetRight) == "function" then
      local okW, screenW = pcall(uiParent.GetWidth, uiParent)
      local okR, rightX = pcall(ahFrame.GetRight, ahFrame)
      if okW and okR and type(screenW) == "number" and type(rightX) == "number" and screenW > 0 then
        fitsRight = (rightX + PANEL_WIDTH + 16) <= screenW
      end
    end
    if fitsRight then
      f:SetPoint("TOPLEFT", ahFrame, "TOPRIGHT", 8, -12)
      f.appliedAnchorMode = "auction_right"
    else
      f:SetPoint("TOPLEFT", ahFrame, "BOTTOMLEFT", 0, -6)
      f.appliedAnchorMode = "auction_below_fallback"
    end
  else
    f:SetPoint("CENTER", uiParent, "CENTER", 250, 40)
    f.appliedAnchorMode = "center_fallback"
  end
end

function AuctionPostAdvisor.EnsureFrame()
  if AuctionPostAdvisor.frame then
    return AuctionPostAdvisor.frame
  end
  if type(CreateFrame) ~= "function" or isCombatLocked() then
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
    f:SetSize(PANEL_WIDTH, 182)
  end
  if f.SetFrameStrata then
    pcall(f.SetFrameStrata, f, "HIGH")
  end
  if f.SetMovable then
    pcall(f.SetMovable, f, true)
  end

  f.title = Widgets and Widgets.SafeCreateFontString and Widgets.SafeCreateFontString(f, "sectionTitle", "accent.gold") or nil
  f.modeLine = Widgets and Widgets.SafeCreateFontString and Widgets.SafeCreateFontString(f, "dense", "text.muted") or nil
  f.unitStackLine = Widgets and Widgets.SafeCreateFontString and Widgets.SafeCreateFontString(f, "body", "text.primary") or nil
  f.keepVsVendorLine = Widgets and Widgets.SafeCreateFontString and Widgets.SafeCreateFontString(f, "dense", "text.secondary") or nil
  f.warningLine = Widgets and Widgets.SafeCreateFontString and Widgets.SafeCreateFontString(f, "dense", "status.warning") or nil
  f.durationLine = Widgets and Widgets.SafeCreateFontString and Widgets.SafeCreateFontString(f, "dense", "text.muted") or nil

  local innerW = PANEL_WIDTH - (PANEL_PADDING * 2)
  local y = -PANEL_PADDING
  for _, fs in ipairs({ f.title, f.modeLine, f.unitStackLine, f.keepVsVendorLine, f.warningLine, f.durationLine }) do
    if fs then
      if fs.ClearAllPoints then fs:ClearAllPoints() end
      if fs.SetPoint then fs:SetPoint("TOPLEFT", f, "TOPLEFT", PANEL_PADDING, y) end
      if fs.SetWidth then pcall(fs.SetWidth, fs, innerW) end
      if fs.SetJustifyH then pcall(fs.SetJustifyH, fs, "LEFT") end
      if fs.SetWordWrap then pcall(fs.SetWordWrap, fs, true) end
      y = y - 26
    end
  end

  if f.Hide then
    f:Hide()
  end
  AuctionPostAdvisor.frame = f
  return f
end

function AuctionPostAdvisor.EvaluateCurrentSelection(overrides)
  overrides = type(overrides) == "table" and overrides or {}
  local apm = ns.Domain and ns.Domain.AuctionPostMath
  if not apm then
    return nil
  end
  local ctrl = AuctionPostAdvisor.EnsureController()
  if ctrl.state == "CLOSED" then
    ctrl:Open(overrides.venueContext or {})
  end

  local form = AuctionPostAdvisor.ReadLivePostingFormState(overrides)
  ctrl:UpdateSelection(form)

  local quotes = overrides.quotesByDuration
  if type(quotes) ~= "table" and ctrl.state == "SNAPSHOT_READY" and form.slotted == true then
    quotes = {}
    for _, durIdx in ipairs({ 1, 2, 3 }) do
      local qRes = apm.QueryLiveDepositForDuration({
        durationIndex = durIdx,
        startingBidPerLotCopper = form.startingBidPerLotCopper,
        buyoutPerLotCopper = form.buyoutPerLotCopper,
        stackSize = form.stackSize,
        numStacks = form.numStacks,
        slottedItemVerified = true,
        verifiedMultiStackSemantics = overrides.verifiedMultiStackSemantics,
      })
      if qRes and qRes.ok then
        quotes[durIdx] = qRes
      end
    end
  end
  if type(quotes) == "table" and next(quotes) ~= nil then
    ctrl:AttachQuotes(quotes)
  end

  local commRule = overrides.commissionRule
  if commRule == nil and ns.State and type(ns.State.GetActiveVerifiedCommissionRuleForTooltip) == "function" then
    commRule = ns.State.GetActiveVerifiedCommissionRuleForTooltip()
  end

  local eval = apm.EvaluatePostingScenario({
    synchronizedToForm = (form.synchronized == true),
    stackSize = form.stackSize,
    numStacks = form.numStacks,
    startingBidPerLotCopper = form.startingBidPerLotCopper,
    buyoutPerLotCopper = form.buyoutPerLotCopper,
    durationIndex = form.durationIndex,
    unitVendorCopper = form.unitVendorCopper,
    vendorMetadataComplete = form.vendorMetadataComplete,
    bindType = form.bindType,
    commissionRule = commRule,
    quotesByDuration = ctrl.quotesByDuration,
    reserveOpts = overrides.reserveOpts,
  })
  eval.lifecycleState = ctrl.state
  eval.selectionRevision = ctrl.selectionRevision
  eval.venue = ctrl.venue
  eval.writesBlizzardMoneyInputs = false
  eval.automatesPosting = false
  AuctionPostAdvisor.lastEvaluation = eval
  return eval
end

function AuctionPostAdvisor.Render(evalResult)
  local eval = evalResult or AuctionPostAdvisor.EvaluateCurrentSelection()
  if not eval then
    return nil
  end
  if isCombatLocked() then
    AuctionPostAdvisor.pendingCombatShow = true
    return eval
  end
  local f = AuctionPostAdvisor.EnsureFrame()
  if not f then
    return eval
  end
  anchorPanelScreenSafe(f)

  if f.title and f.title.SetText then
    f.title:SetText("ForeverHub Sell Check")
  end
  if f.modeLine and f.modeLine.SetText then
    f.modeLine:SetText(tostring(eval.modeBanner or "Scenario calculator — not synchronized to posting form"))
  end

  if eval.status ~= "OK" then
    if f.unitStackLine and f.unitStackLine.SetText then
      f.unitStackLine:SetText("Slot a tradable item or enter scenario quantities to inspect unit/stack/batch math.")
    end
    if f.keepVsVendorLine and f.keepVsVendorLine.SetText then
      f.keepVsVendorLine:SetText("Zero automated posting or undercutting.")
    end
    if f.warningLine and f.warningLine.SetText then
      f.warningLine:SetText("")
    end
    if f.durationLine and f.durationLine.SetText then
      f.durationLine:SetText("")
    end
  else
    local primary = eval.isBidOnly and eval.bidScenario or eval.buyoutScenario
    local modeTag = eval.isBidOnly and "Bid-only" or "Buyout"
    if f.unitStackLine and f.unitStackLine.SetText and primary then
      f.unitStackLine:SetText(
        string.format(
          "%s (%d×%d = %d units): ~%s/ea · %s/stack · %s batch",
          modeTag,
          eval.stackSize,
          eval.numStacks,
          eval.totalUnits,
          fmtMoney(primary.perUnitFloorCopper),
          fmtMoney(primary.perLotGrossCopper),
          fmtMoney(primary.batchGrossCopper)
        )
      )
    end

    if f.keepVsVendorLine and f.keepVsVendorLine.SetText then
      local keepPart = eval.commissionKnown and primary and fmtMoney(primary.batchNetKeepExclDepositRefundCopper) or "Fee unverified"
      local vendPart = eval.vendorKnown and fmtMoney(eval.batchVendorCopper) or "Vendor pending"
      f.keepVsVendorLine:SetText(string.format("If sold keep (excl. deposit refund): %s  ·  Client vendor: %s", keepPart, vendPart))
    end

    local warnParts = {}
    if eval.buyoutLossWarning then
      table.insert(warnParts, "Buyout after commission is BELOW client vendor value!")
    end
    if eval.bidFloorLossWarning then
      table.insert(warnParts, "BID_FLOOR_LOSS: Min bid after commission is BELOW vendor if won without buyout!")
    end
    if eval.suspectedUnitAsStackMistake then
      table.insert(warnParts, "Check stack vs unit price: stack total is below vendor!")
    end
    if eval.depositReserveWarning then
      table.insert(warnParts, "Upfront deposit dips into protected riding/training reserve!")
    end
    if f.warningLine and f.warningLine.SetText then
      f.warningLine:SetText(table.concat(warnParts, " "))
    end

    local durParts = {}
    for _, durIdx in ipairs({ 1, 2, 3 }) do
      local de = eval.durationEvaluations and eval.durationEvaluations[durIdx]
      if de and de.depositKnown then
        local beTxt = (de.breakEvenBuyout and de.breakEvenBuyout.pStarPct)
            and string.format(" (1-try p*=%.1f%%)", de.breakEvenBuyout.pStarPct)
          or ""
        table.insert(durParts, string.format("%dh: %s%s", de.foreverDisplayHours, fmtMoney(de.batchDepositCopper), beTxt))
      end
    end
    if f.durationLine and f.durationLine.SetText then
      if #durParts > 0 then
        f.durationLine:SetText("Deposit lock (lost only if unsold): " .. table.concat(durParts, " · "))
      else
        f.durationLine:SetText("Deposit exposure: awaiting live GetAuctionDeposit quote")
      end
    end
  end

  if f.Show then
    f:Show()
  end
  return eval
end

function AuctionPostAdvisor.OnAuctionHouseShow(venueCtx)
  AuctionPostAdvisor.active = true
  AuctionPostAdvisor.pendingCombatHide = false
  local ctrl = AuctionPostAdvisor.EnsureController()
  if ctrl then
    ctrl:Open(venueCtx or {})
  end
  return AuctionPostAdvisor.Render()
end

function AuctionPostAdvisor.OnAuctionSellSelectionChanged(overrides)
  if not AuctionPostAdvisor.active then
    return nil
  end
  local eval = AuctionPostAdvisor.EvaluateCurrentSelection(overrides)
  return AuctionPostAdvisor.Render(eval)
end

function AuctionPostAdvisor.OnAuctionHouseClosed()
  AuctionPostAdvisor.active = false
  AuctionPostAdvisor.pendingCombatShow = false
  local ctrl = AuctionPostAdvisor.EnsureController()
  if ctrl then
    ctrl:Close()
  end
  if isCombatLocked() then
    AuctionPostAdvisor.pendingCombatHide = true
    return
  end
  if AuctionPostAdvisor.frame and AuctionPostAdvisor.frame.Hide then
    AuctionPostAdvisor.frame:Hide()
  end
end

function AuctionPostAdvisor.FlushDeferredIfReady()
  if isCombatLocked() then
    return
  end
  if AuctionPostAdvisor.pendingCombatHide then
    AuctionPostAdvisor.pendingCombatHide = false
    AuctionPostAdvisor.pendingCombatShow = false
    if AuctionPostAdvisor.frame and AuctionPostAdvisor.frame.Hide then
      AuctionPostAdvisor.frame:Hide()
    end
  elseif AuctionPostAdvisor.pendingCombatShow and AuctionPostAdvisor.active then
    AuctionPostAdvisor.pendingCombatShow = false
    AuctionPostAdvisor.Render(AuctionPostAdvisor.lastEvaluation)
  end
end

return AuctionPostAdvisor
