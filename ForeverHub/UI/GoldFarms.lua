local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.UI = ns.UI or {}

local Theme = ns.UI.Theme
local Widgets = ns.UI.Widgets
local Presenter = ns.UI.GoldFarmsPresenter

local GoldFarmsUI = {
  frame = nil,
  host = nil,
  summaryStrip = nil,
  kpis = {},
  mountBar = nil,
  viewport = nil,
  cardPool = {},
  badgePool = {},
  lastLayoutReport = nil,
}
ns.UI.GoldFarms = GoldFarmsUI

local FARM_COLLAPSED_MIN_HEIGHT = 82

local function acquirePoolItem(pool, createFn)
  local idx = (pool.__used or 0) + 1
  pool.__used = idx
  local item = pool[idx]
  if not item then
    item = createFn(idx)
    pool[idx] = item
  end
  return item
end

local function resetPool(pool)
  for i = 1, #pool do
    if pool[i] then
      Widgets.SafeShow(pool[i], false)
    end
  end
  pool.__used = 0
end

function GoldFarmsUI.Dispatch(actionType, payload)
  payload = type(payload) == "table" and payload or {}
  local uiState = ns.State.GetWorkspaceUIState()
  local goldView = uiState.goldView

  if actionType == "SELECT_FARM" then
    local fid = tostring(payload.farmID or "")
    if fid ~= "" then
      goldView.focusedFarmID = fid
      GoldFarmsUI.Refresh()
    end
    return true
  elseif actionType == "TOGGLE_EXPAND" then
    local fid = tostring(payload.farmID or "")
    if fid ~= "" then
      goldView.expandedByFarmID[fid] = not (goldView.expandedByFarmID[fid] == true)
      GoldFarmsUI.Refresh()
    end
    return true
  elseif actionType == "START_NAVIGATION" then
    local fid = tostring(payload.farmID or "")
    if fid ~= "" then
      goldView.focusedFarmID = fid
      if ns.Events and ns.Events.HandleGoldSubcommand then
        ns.Events.HandleGoldSubcommand("start " .. fid)
      end
      GoldFarmsUI.Refresh()
      return true
    end
    return false
  elseif actionType == "STOP_NAVIGATION" then
    if ns.Events and ns.Events.HandleGoldSubcommand then
      ns.Events.HandleGoldSubcommand("stop")
    end
    GoldFarmsUI.Refresh()
    return true
  elseif actionType == "NEXT_HOP" then
    if ns.Events and ns.Events.HandleGoldSubcommand then
      ns.Events.HandleGoldSubcommand("next")
    end
    GoldFarmsUI.Refresh()
    return true
  elseif actionType == "PREV_HOP" then
    if ns.Events and ns.Events.HandleGoldSubcommand then
      ns.Events.HandleGoldSubcommand("prev")
    end
    GoldFarmsUI.Refresh()
    return true
  elseif actionType == "REENTER_ROUTE" then
    if ns.Events and ns.Events.HandleGoldSubcommand then
      ns.Events.HandleGoldSubcommand("reenter")
    end
    GoldFarmsUI.Refresh()
    return true
  elseif actionType == "RESET_METER" then
    if ns.Events and ns.Events.HandleGoldSubcommand then
      ns.Events.HandleGoldSubcommand("reset")
    end
    GoldFarmsUI.Refresh()
    return true
  elseif actionType == "EXPORT_RXP" then
    local fid = payload.farmID
    if ns.Events and ns.Events.HandleGoldSubcommand then
      if fid and fid ~= "" then
        ns.Events.HandleGoldSubcommand("export rxp " .. tostring(fid))
      else
        ns.Events.HandleGoldSubcommand("export rxp")
      end
    end
    GoldFarmsUI.Refresh()
    return true
  elseif actionType == "SET_QUOTE_HONORED" then
    if ns.Events and ns.Events.HandleMountCommand then
      ns.Events.HandleMountCommand("honored")
    end
    GoldFarmsUI.Refresh()
    return true
  elseif actionType == "SET_QUOTE_BASE" then
    if ns.Events and ns.Events.HandleMountCommand then
      ns.Events.HandleMountCommand("base")
    end
    GoldFarmsUI.Refresh()
    return true
  elseif actionType == "SET_RESERVE_GOLD" then
    local g = math.max(0, math.floor(tonumber(payload.gold) or 0))
    if ns.Events and ns.Events.HandleMountCommand then
      ns.Events.HandleMountCommand("reserve " .. tostring(g))
    end
    GoldFarmsUI.Refresh()
    return true
  end
  return false
end

local function createFarmCard(parent)
  local card = Widgets.CreatePanel(parent, "surface.card", "border.subtle")
  if not card then
    return nil
  end

  card.icon = Widgets.CreateItemIcon(card, 32)
  if card.icon then
    Widgets.SafeSetPoint(card.icon, "TOPLEFT", card, "TOPLEFT", 12, -14)
  end

  card.titleText = Widgets.SafeCreateFontString(card, "sectionTitle", "text.primary")
  if card.titleText and type(card.titleText.SetJustifyH) == "function" then
    pcall(card.titleText.SetJustifyH, card.titleText, "LEFT")
  end

  card.meta1Text = Widgets.SafeCreateFontString(card, "body", "text.secondary")
  if card.meta1Text and type(card.meta1Text.SetJustifyH) == "function" then
    pcall(card.meta1Text.SetJustifyH, card.meta1Text, "LEFT")
  end

  card.meta2Text = Widgets.SafeCreateFontString(card, "dense", "text.muted")
  if card.meta2Text and type(card.meta2Text.SetJustifyH) == "function" then
    pcall(card.meta2Text.SetJustifyH, card.meta2Text, "LEFT")
  end

  -- Mutually exclusive primary gold `Navigate` vs neutral secondary `Select`
  card.primaryNavBtn = Widgets.CreatePrimaryButton(card, 96, "Navigate", 28)
  card.selectBtn = Widgets.CreateSecondaryButton(card, 82, "Select", 28)
  card.nextHopBtn = Widgets.CreateSecondaryButton(card, 86, "Next hop", 28)
  card.stopNavBtn = Widgets.CreateGhostButton(card, 112, "Stop navigation", 28)
  card.expandBtn = Widgets.CreateIconButton(card, "chevron_right", "Route & Mage details", { "Show travel hops, Mage pull notes, and RXP export." }, 28, 14)

  card.detailBox = Widgets.CreatePanel(card, "surface.elevated", "border.subtle")
  if card.detailBox then
    card.detailText = Widgets.SafeCreateFontString(card.detailBox, "dense", "text.secondary")
    if card.detailText and type(card.detailText.SetJustifyH) == "function" then
      pcall(card.detailText.SetJustifyH, card.detailText, "LEFT")
    end
    card.prevHopBtn = Widgets.CreateGhostButton(card.detailBox, 78, "Prev hop", 24)
    card.reenterBtn = Widgets.CreateGhostButton(card.detailBox, 108, "Re-route entry", 24)
    card.exportBtn = Widgets.CreateSecondaryButton(card.detailBox, 116, "Export to RXP", 24)
  end

  return card
end

function GoldFarmsUI.EnsureHost()
  local wsFrame = ns.UI.Workspace and ns.UI.Workspace.EnsureCreated and ns.UI.Workspace.EnsureCreated() or nil
  local tabParent = (wsFrame and wsFrame.tabHosts and wsFrame.tabHosts.gold) or _G.UIParent
  if GoldFarmsUI.host and GoldFarmsUI.host.__parentRef == tabParent then
    return GoldFarmsUI.host
  end

  local host = Widgets.CreatePanel(tabParent, "surface.window", nil)
  if not host then
    return nil
  end
  host.__parentRef = tabParent
  GoldFarmsUI.host = host
  GoldFarmsUI.frame = tabParent
  _G.ForeverHubGoldFarmsFrame = tabParent

  if ns.UI.Workspace and ns.UI.Workspace.RegisterTabRenderer then
    ns.UI.Workspace.RegisterTabRenderer("gold", {
      Refresh = function(_, contentWidth, contentHeight, isCompact)
        GoldFarmsUI.RenderInHost(contentWidth, contentHeight, isCompact)
      end,
    })
  end

  -- 1. Top 5-KPI Summary Strip (60h)
  local summary = Widgets.CreatePanel(host, "surface.card", "border.subtle")
  GoldFarmsUI.summaryStrip = summary
  GoldFarmsUI.kpis = {}
  for i = 1, 5 do
    GoldFarmsUI.kpis[i] = Widgets.CreateKPI(summary, 160)
  end

  -- 2. Purse Progress Bar (`6` high) + Quote/Reserve & Telemetry Controls (58h)
  local mbar = Widgets.CreatePanel(host, "surface.card", "border.subtle")
  GoldFarmsUI.mountBar = mbar
  if mbar then
    mbar.leftLabel = Widgets.SafeCreateFontString(mbar, "dense", "text.primary")
    if mbar.leftLabel then
      Widgets.SafeSetPoint(mbar.leftLabel, "TOPLEFT", mbar, "TOPLEFT", 12, -7)
      if type(mbar.leftLabel.SetJustifyH) == "function" then pcall(mbar.leftLabel.SetJustifyH, mbar.leftLabel, "LEFT") end
    end

    mbar.rightLabel = Widgets.SafeCreateFontString(mbar, "dense", "text.muted")
    if mbar.rightLabel then
      Widgets.SafeSetPoint(mbar.rightLabel, "TOPRIGHT", mbar, "TOPRIGHT", -12, -7)
      if type(mbar.rightLabel.SetJustifyH) == "function" then pcall(mbar.rightLabel.SetJustifyH, mbar.rightLabel, "RIGHT") end
    end

    mbar.track = Widgets.CreatePanel(mbar, "surface.window", "border.subtle")
    if mbar.track then
      Widgets.SafeSetHeight(mbar.track, 6)
      mbar.fill = Widgets.SafeCreateTexture(mbar.track, "ARTWORK", 2)
      if mbar.fill then
        Widgets.SafeSetPoint(mbar.fill, "TOPLEFT", mbar.track, "TOPLEFT", 1, -1)
        Widgets.SafeSetHeight(mbar.fill, 4)
        Widgets.SafeSetSolidColor(mbar.fill, "accent.gold", 1.0)
      end
    end

    mbar.quote90Btn = Widgets.CreateGhostButton(mbar, 96, "Confirm 90g", 22)
    if mbar.quote90Btn then
      mbar.quote90Btn:SetOnClick(function()
        GoldFarmsUI.Dispatch("SET_QUOTE_HONORED")
      end)
      Widgets.BindTooltip(mbar.quote90Btn, "Confirm 90g Honored Quote", { "Marks the 90g Honored trainer quote as confirmed." })
    end

    mbar.quote100Btn = Widgets.CreateGhostButton(mbar, 78, "100g Base", 22)
    if mbar.quote100Btn then
      mbar.quote100Btn:SetOnClick(function()
        GoldFarmsUI.Dispatch("SET_QUOTE_BASE")
      end)
      Widgets.BindTooltip(mbar.quote100Btn, "Set 100g Unimputed Base Quote", { "Sets target to 100g (0% faction discount)." })
    end

    mbar.res0Btn = Widgets.CreateGhostButton(mbar, 58, "Buf 0g", 22)
    if mbar.res0Btn then
      mbar.res0Btn:SetOnClick(function() GoldFarmsUI.Dispatch("SET_RESERVE_GOLD", { gold = 0 }) end)
    end
    mbar.res5Btn = Widgets.CreateGhostButton(mbar, 58, "Buf 5g", 22)
    if mbar.res5Btn then
      mbar.res5Btn:SetOnClick(function() GoldFarmsUI.Dispatch("SET_RESERVE_GOLD", { gold = 5 }) end)
    end
    mbar.res10Btn = Widgets.CreateGhostButton(mbar, 64, "Buf 10g", 22)
    if mbar.res10Btn then
      mbar.res10Btn:SetOnClick(function() GoldFarmsUI.Dispatch("SET_RESERVE_GOLD", { gold = 10 }) end)
    end

    -- Session telemetry controls strictly separate from route navigation
    mbar.resetMeterBtn = Widgets.CreateSecondaryButton(mbar, 96, "Reset meter", 22)
    if mbar.resetMeterBtn then
      mbar.resetMeterBtn:SetOnClick(function()
        GoldFarmsUI.Dispatch("RESET_METER")
      end)
      Widgets.BindTooltip(
        mbar.resetMeterBtn,
        "Reset Session Cash-Flow Meter",
        { "Starts a clean observed purse interval without stopping route navigation." }
      )
    end

    mbar.exportAllBtn = Widgets.CreateGhostButton(mbar, 108, "Export all RXP", 22)
    if mbar.exportAllBtn then
      mbar.exportAllBtn:SetOnClick(function()
        GoldFarmsUI.Dispatch("EXPORT_RXP")
      end)
      Widgets.BindTooltip(
        mbar.exportAllBtn,
        "Export All 5 Candidates to RestedXP",
        { "Registers all 5 verified Level 40 Mage gold farm guides under '+ForeverHub Gold Farms'." }
      )
    end
  end

  -- 3. Scroll Viewport for Farm Cards
  GoldFarmsUI.viewport = Widgets.CreateScrollViewport(host, function(offset)
    local st = ns.State.GetWorkspaceUIState()
    st.goldView.scrollOffset = offset
  end)

  return host
end

function GoldFarmsUI.RenderInHost(viewportWidth, viewportHeight, isCompact, snapshotOverride)
  local host = GoldFarmsUI.EnsureHost()
  if not host then
    return nil
  end

  local generation = Widgets.BumpGeneration()
  local pad = Theme.METRICS.workspacePadding
  local vw = math.max(700, tonumber(viewportWidth) or 928)
  local vh = math.max(360, (tonumber(viewportHeight) or 560) - 16)
  local compact = (isCompact == true)
  Widgets.SafeClearPoints(host)
  Widgets.SafeSetSize(host, vw, vh)
  Widgets.SafeSetPoint(host, "TOPLEFT", host.__parentRef, "TOPLEFT", pad, -8)
  Widgets.SafeShow(host, true)

  local uiState = ns.State.GetWorkspaceUIState()
  local snap = Presenter.CaptureSnapshot(snapshotOverride)
  local vm = Presenter.Build(snap, uiState)

  if ns.UI.Workspace and ns.UI.Workspace.SetTabBadge then
    ns.UI.Workspace.SetTabBadge("gold", vm.tabBadge)
  end

  -- 1. Layout 5 KPIs
  local summaryH = Theme.METRICS.summaryHeight
  Widgets.SafeClearPoints(GoldFarmsUI.summaryStrip)
  Widgets.SafeSetPoint(GoldFarmsUI.summaryStrip, "TOPLEFT", host, "TOPLEFT", 0, 0)
  Widgets.SafeSetSize(GoldFarmsUI.summaryStrip, vw, summaryH)
  local kpiW = math.floor((vw - 24) / 5)
  for i = 1, 5 do
    local kw = GoldFarmsUI.kpis[i]
    local kd = vm.kpis[i]
    if kw and kd then
      Widgets.SafeClearPoints(kw)
      Widgets.SafeSetPoint(kw, "TOPLEFT", GoldFarmsUI.summaryStrip, "TOPLEFT", 12 + (i - 1) * kpiW, -6)
      Widgets.SafeSetSize(kw, kpiW - 6, 48)
      kw:SetKPI(kd.value, kd.label, kd.sub, kd.token, kd.tooltipTitle, kd.tooltipLines)
    end
  end

  -- 2. Layout 6-unit Progress Bar + Controls Strip
  local mbarH = 60
  local mbar = GoldFarmsUI.mountBar
  Widgets.SafeClearPoints(mbar)
  Widgets.SafeSetPoint(mbar, "TOPLEFT", host, "TOPLEFT", 0, -(summaryH + 8))
  Widgets.SafeSetSize(mbar, vw, mbarH)

  if mbar.leftLabel then
    Theme.ApplyFont(mbar.leftLabel, "dense", "text.primary")
    mbar.leftLabel:SetText(vm.progressLeftText)
  end
  if mbar.rightLabel then
    Theme.ApplyFont(mbar.rightLabel, "dense", "text.muted")
    mbar.rightLabel:SetText(compact and "" or vm.progressRightText)
  end
  if mbar.track then
    local trackW = vw - 24
    Widgets.SafeClearPoints(mbar.track)
    Widgets.SafeSetPoint(mbar.track, "TOPLEFT", mbar, "TOPLEFT", 12, -24)
    Widgets.SafeSetSize(mbar.track, trackW, 6)
    if mbar.fill then
      local fillW = math.floor((trackW - 2) * (vm.progressFraction or 0) + 0.5)
      if fillW <= 0 then
        Widgets.SafeShow(mbar.fill, false)
      else
        Widgets.SafeSetWidth(mbar.fill, fillW)
        Widgets.SafeSetSolidColor(mbar.fill, (vm.progressFraction >= 1.0) and "status.ready" or "accent.gold", 1.0)
        Widgets.SafeShow(mbar.fill, true)
      end
    end
  end

  if mbar.quote90Btn then
    mbar.quote90Btn.__isSelected = (vm.quoteConfirmed and vm.targetCopper == 900000)
    mbar.quote90Btn:RefreshVisualState()
    Widgets.SafeClearPoints(mbar.quote90Btn)
    Widgets.SafeSetPoint(mbar.quote90Btn, "BOTTOMLEFT", mbar, "BOTTOMLEFT", 10, 5)
  end
  if mbar.quote100Btn then
    mbar.quote100Btn.__isSelected = (vm.targetCopper == 1000000)
    mbar.quote100Btn:RefreshVisualState()
    Widgets.SafeClearPoints(mbar.quote100Btn)
    Widgets.SafeSetPoint(mbar.quote100Btn, "LEFT", mbar.quote90Btn, "RIGHT", 4, 0)
  end
  if mbar.res0Btn then
    mbar.res0Btn.__isSelected = (vm.reserveCopper == 0)
    mbar.res0Btn:RefreshVisualState()
    Widgets.SafeClearPoints(mbar.res0Btn)
    Widgets.SafeSetPoint(mbar.res0Btn, "LEFT", mbar.quote100Btn, "RIGHT", 10, 0)
  end
  if mbar.res5Btn then
    mbar.res5Btn.__isSelected = (vm.reserveCopper == 50000)
    mbar.res5Btn:RefreshVisualState()
    Widgets.SafeClearPoints(mbar.res5Btn)
    Widgets.SafeSetPoint(mbar.res5Btn, "LEFT", mbar.res0Btn, "RIGHT", 4, 0)
  end
  if mbar.res10Btn then
    mbar.res10Btn.__isSelected = (vm.reserveCopper == 100000)
    mbar.res10Btn:RefreshVisualState()
    Widgets.SafeClearPoints(mbar.res10Btn)
    Widgets.SafeSetPoint(mbar.res10Btn, "LEFT", mbar.res5Btn, "RIGHT", 4, 0)
  end
  if mbar.resetMeterBtn then
    Widgets.SafeClearPoints(mbar.resetMeterBtn)
    Widgets.SafeSetPoint(mbar.resetMeterBtn, "BOTTOMRIGHT", mbar, "BOTTOMRIGHT", -10, 5)
  end
  if mbar.exportAllBtn then
    Widgets.SafeClearPoints(mbar.exportAllBtn)
    Widgets.SafeSetPoint(mbar.exportAllBtn, "RIGHT", mbar.resetMeterBtn, "LEFT", -6, 0)
  end

  -- 3. Layout 5 Collapsible Farm Rows
  local bodyTop = summaryH + 8 + mbarH + 8
  local vpH = math.max(160, vh - bodyTop)
  local rowWidth = vw - Theme.METRICS.scrollbarLaneWidth
  local content = GoldFarmsUI.viewport.content

  Widgets.SafeClearPoints(GoldFarmsUI.viewport)
  Widgets.SafeSetPoint(GoldFarmsUI.viewport, "TOPLEFT", host, "TOPLEFT", 0, -bodyTop)

  resetPool(GoldFarmsUI.cardPool)
  resetPool(GoldFarmsUI.badgePool)

  local y = 0
  local cardReports = {}
  local primaryGoldButtonCount = 0

  for _, fvm in ipairs(vm.farms) do
    local card = acquirePoolItem(GoldFarmsUI.cardPool, function()
      return createFarmCard(content)
    end)
    if card then
      if card.icon then
        card.icon:SetItem(fvm.iconItemID, fvm.title, generation)
      end

      local rightControlsReserve = fvm.isActiveNav and 254 or 148
      local textW = math.max(200, rowWidth - 56 - rightControlsReserve)

      local fullHeading = string.format("%s  ·  %s", fvm.title, fvm.zoneAndLevel)
      if card.titleText then
        Widgets.SafeClearPoints(card.titleText)
        Widgets.SafeSetPoint(card.titleText, "TOPLEFT", card, "TOPLEFT", 54, -10)
        Theme.ApplyFont(card.titleText, "sectionTitle", fvm.isActiveNav and "accent.gold" or "text.primary")
      end
      local tH = Theme.MeasureWrappedHeight(card.titleText, fullHeading, textW, "sectionTitle", 20, 0)

      if card.meta1Text then
        Widgets.SafeClearPoints(card.meta1Text)
        Widgets.SafeSetPoint(card.meta1Text, "TOPLEFT", card, "TOPLEFT", 54, -(10 + tH + 2))
        Theme.ApplyFont(card.meta1Text, "body", "text.secondary")
      end
      local m1H = Theme.MeasureWrappedHeight(card.meta1Text, fvm.metaLine1, textW, "body", 18, 0)

      if card.meta2Text then
        Widgets.SafeClearPoints(card.meta2Text)
        Widgets.SafeSetPoint(card.meta2Text, "TOPLEFT", card, "TOPLEFT", 54, -(10 + tH + 2 + m1H + 2))
        Theme.ApplyFont(card.meta2Text, "dense", "text.muted")
      end
      local m2H = Theme.MeasureWrappedHeight(card.meta2Text, fvm.metaLine2, textW, "dense", 16, 0)

      -- Optional status badges (Active hop / Reservation warning)
      local badgeY = 10 + tH + 2 + m1H + 2 + m2H + 4
      local badgeX = 54
      local hasBadges = false
      local function addCardBadge(txt, tok, glyph, goldOutline)
        local b = acquirePoolItem(GoldFarmsUI.badgePool, function()
          return Widgets.CreateBadge(content)
        end)
        if b then
          if type(b.SetParent) == "function" then pcall(b.SetParent, b, card) end
          local bw = b:Configure(txt, tok, glyph, goldOutline)
          Widgets.SafeClearPoints(b)
          Widgets.SafeSetPoint(b, "TOPLEFT", card, "TOPLEFT", badgeX, -badgeY)
          badgeX = badgeX + bw + 6
          hasBadges = true
        end
      end

      if fvm.isActiveNav and fvm.activeStepSummary then
        addCardBadge("Active · " .. fvm.activeStepSummary, "status.ready", "play", true)
      elseif fvm.isFocused then
        addCardBadge("Selected candidate", "accent.gold", nil, false)
      end
      if fvm.hasReservationConflict then
        addCardBadge("Reserved mat guard", "status.warning", "warning", false)
      end

      local collapsedH = math.max(FARM_COLLAPSED_MIN_HEIGHT, 10 + tH + 2 + m1H + 2 + m2H + (hasBadges and 24 or 0) + 10)

      Widgets.SafeSetSolidColor(card.__fhBg, fvm.isActiveNav and "surface.selected" or "surface.card", 1.0)
      Widgets.SetSurfaceBorder(
        card,
        fvm.isActiveNav and "accent.gold" or (fvm.isFocused and "border.default" or "border.subtle"),
        fvm.isActiveNav and 0.90 or 1.0
      )

      -- Right-side action hierarchy:
      -- - Active farm: `Next hop` + `Stop navigation` + chevron
      -- - Selected (non-active) farm: ONLY gold primary `Navigate` + chevron
      -- - All other farms: neutral secondary `Select` + chevron
      local fid = fvm.farmID
      if card.expandBtn then
        card.expandBtn:SetGlyph(fvm.isExpanded and "chevron_down" or "chevron_right", "text.secondary")
        Widgets.SafeClearPoints(card.expandBtn)
        Widgets.SafeSetPoint(card.expandBtn, "TOPRIGHT", card, "TOPRIGHT", -10, -16)
        card.expandBtn:SetOnClick(function()
          GoldFarmsUI.Dispatch("TOGGLE_EXPAND", { farmID = fid })
        end)
        Widgets.SafeShow(card.expandBtn, true)
      end

      if fvm.isActiveNav then
        Widgets.SafeShow(card.primaryNavBtn, false)
        Widgets.SafeShow(card.selectBtn, false)
        if card.stopNavBtn then
          Widgets.SafeClearPoints(card.stopNavBtn)
          Widgets.SafeSetPoint(card.stopNavBtn, "RIGHT", card.expandBtn, "LEFT", -6, 0)
          card.stopNavBtn:SetOnClick(function()
            GoldFarmsUI.Dispatch("STOP_NAVIGATION")
          end)
          Widgets.SafeShow(card.stopNavBtn, true)
        end
        if card.nextHopBtn then
          Widgets.SafeClearPoints(card.nextHopBtn)
          Widgets.SafeSetPoint(card.nextHopBtn, "RIGHT", card.stopNavBtn, "LEFT", -6, 0)
          card.nextHopBtn:SetOnClick(function()
            GoldFarmsUI.Dispatch("NEXT_HOP")
          end)
          Widgets.SafeShow(card.nextHopBtn, true)
        end
      elseif fvm.isFocused then
        Widgets.SafeShow(card.selectBtn, false)
        Widgets.SafeShow(card.nextHopBtn, false)
        Widgets.SafeShow(card.stopNavBtn, false)
        if card.primaryNavBtn then
          card.primaryNavBtn:SetLabel("Navigate")
          Widgets.SafeClearPoints(card.primaryNavBtn)
          Widgets.SafeSetPoint(card.primaryNavBtn, "RIGHT", card.expandBtn, "LEFT", -6, 0)
          card.primaryNavBtn:SetOnClick(function()
            GoldFarmsUI.Dispatch("START_NAVIGATION", { farmID = fid })
          end)
          Widgets.SafeShow(card.primaryNavBtn, true)
          primaryGoldButtonCount = primaryGoldButtonCount + 1
        end
      else
        Widgets.SafeShow(card.primaryNavBtn, false)
        Widgets.SafeShow(card.nextHopBtn, false)
        Widgets.SafeShow(card.stopNavBtn, false)
        if card.selectBtn then
          Widgets.SafeClearPoints(card.selectBtn)
          Widgets.SafeSetPoint(card.selectBtn, "RIGHT", card.expandBtn, "LEFT", -6, 0)
          card.selectBtn:SetOnClick(function()
            GoldFarmsUI.Dispatch("SELECT_FARM", { farmID = fid })
          end)
          Widgets.SafeShow(card.selectBtn, true)
        end
      end

      -- Expanded Details Drawer
      local totalCardH = collapsedH
      if fvm.isExpanded and card.detailBox then
        local hopLines = {}
        for _, h in ipairs(fvm.hops) do
          local prefix = h.isCurrent and "▶ " or "  • "
          table.insert(hopLines, string.format("%sHop %d: %s", prefix, h.index, h.title))
        end
        local detailParts = {
          "Entry & Hops:\n" .. table.concat(hopLines, "\n"),
          "Mage Notes: " .. fvm.magePullNotes,
          "Payout Basis: " .. fvm.payoutBasis,
        }
        for _, w in ipairs(fvm.warnings or {}) do
          table.insert(detailParts, Theme.Colorize("status.warning", w.message))
        end
        local detailJoined = table.concat(detailParts, "\n")
        local innerW = math.max(180, rowWidth - 44)
        if card.detailText then
          Widgets.SafeClearPoints(card.detailText)
          Widgets.SafeSetPoint(card.detailText, "TOPLEFT", card.detailBox, "TOPLEFT", 12, -10)
          Theme.ApplyFont(card.detailText, "dense", "text.secondary")
        end
        local dTextH = Theme.MeasureWrappedHeight(card.detailText, detailJoined, innerW, "dense", 48, 0)
        local dBoxH = dTextH + 44

        Widgets.SafeClearPoints(card.detailBox)
        Widgets.SafeSetPoint(card.detailBox, "TOPLEFT", card, "TOPLEFT", 10, -collapsedH)
        Widgets.SafeSetSize(card.detailBox, rowWidth - 20, dBoxH)

        if card.exportBtn then
          Widgets.SafeClearPoints(card.exportBtn)
          Widgets.SafeSetPoint(card.exportBtn, "BOTTOMRIGHT", card.detailBox, "BOTTOMRIGHT", -10, 8)
          card.exportBtn:SetOnClick(function()
            GoldFarmsUI.Dispatch("EXPORT_RXP", { farmID = fid })
          end)
          Widgets.SafeShow(card.exportBtn, true)
        end
        if card.prevHopBtn then
          Widgets.SafeClearPoints(card.prevHopBtn)
          Widgets.SafeSetPoint(card.prevHopBtn, "BOTTOMLEFT", card.detailBox, "BOTTOMLEFT", 10, 8)
          card.prevHopBtn:SetOnClick(function()
            GoldFarmsUI.Dispatch("PREV_HOP")
          end)
          Widgets.SafeShow(card.prevHopBtn, fvm.isActiveNav)
        end
        if card.reenterBtn then
          Widgets.SafeClearPoints(card.reenterBtn)
          Widgets.SafeSetPoint(card.reenterBtn, "LEFT", card.prevHopBtn, "RIGHT", 6, 0)
          card.reenterBtn:SetOnClick(function()
            GoldFarmsUI.Dispatch("REENTER_ROUTE")
          end)
          Widgets.SafeShow(card.reenterBtn, fvm.isActiveNav)
        end

        Widgets.SafeShow(card.detailBox, true)
        totalCardH = collapsedH + dBoxH + 10
      elseif card.detailBox then
        Widgets.SafeShow(card.detailBox, false)
      end

      Widgets.SafeClearPoints(card)
      Widgets.SafeSetPoint(card, "TOPLEFT", content, "TOPLEFT", 0, -y)
      Widgets.SafeSetSize(card, rowWidth, totalCardH)
      Widgets.SafeShow(card, true)

      table.insert(cardReports, {
        farmID = fid,
        collapsedHeight = collapsedH,
        height = totalCardH,
        width = rowWidth,
        isActiveNav = fvm.isActiveNav,
        isFocused = fvm.isFocused,
        hasNextHopVisible = fvm.isActiveNav,
      })
      y = y + totalCardH + 8
    end
  end

  GoldFarmsUI.viewport:SetDimensions(vw, vpH, math.max(vpH, y + 12))
  GoldFarmsUI.viewport:SetScrollOffset(uiState.goldView.scrollOffset or 0, true)

  local report = {
    isCompact = compact,
    viewportWidth = vw,
    viewportHeight = vh,
    rowWidth = rowWidth,
    primaryGoldButtonCount = primaryGoldButtonCount,
    cards = cardReports,
    contentHeight = y,
  }
  GoldFarmsUI.lastLayoutReport = report
  return report
end

function GoldFarmsUI.Refresh()
  GoldFarmsUI.EnsureHost()
  if ns.UI.Workspace and ns.UI.Workspace.IsShown and ns.UI.Workspace.IsShown() then
    local st = ns.State.GetWorkspaceUIState()
    if st.activeTab == "gold" then
      ns.UI.Workspace.Refresh()
    end
  end
  return true
end

function GoldFarmsUI.RefreshIfShown()
  GoldFarmsUI.Refresh()
end

function GoldFarmsUI.Toggle()
  GoldFarmsUI.EnsureHost()
  if ns.UI.Workspace and ns.UI.Workspace.Toggle then
    ns.UI.Workspace.Toggle("gold")
    return true
  end
  return false
end

if ns.UI.Workspace and ns.UI.Workspace.RegisterTabRenderer then
  ns.UI.Workspace.RegisterTabRenderer("gold", {
    Refresh = function(_, contentWidth, contentHeight, isCompact)
      GoldFarmsUI.RenderInHost(contentWidth, contentHeight, isCompact)
    end,
  })
end

return GoldFarmsUI
