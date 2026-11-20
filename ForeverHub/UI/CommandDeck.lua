local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.UI = ns.UI or {}

local Theme = ns.UI.Theme
local Widgets = ns.UI.Widgets
local Presenter = ns.UI.CommandDeckPresenter

local CommandDeck = {
  frame = nil,
  host = nil,
  northStarStrip = nil,
  summaryStrip = nil,
  kpis = {},
  viewport = nil,
  cardPool = {},
  lastLayoutReport = nil,
  lastActionNotice = nil,
}
ns.UI.CommandDeck = CommandDeck

local DISCOVERY_LIST_NAME = "ForeverHub Vendor Discovery"

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

local function ensureAdvisorViewState()
  local uiState = (ns.State and ns.State.GetWorkspaceUIState and ns.State.GetWorkspaceUIState()) or {}
  if type(uiState.advisorView) ~= "table" then
    uiState.advisorView = {
      scrollOffset = 0,
      crowdedUntilByFarmID = {},
    }
  end
  if type(uiState.advisorView.crowdedUntilByFarmID) ~= "table" then
    uiState.advisorView.crowdedUntilByFarmID = {}
  end
  return uiState, uiState.advisorView
end

function CommandDeck.Dispatch(actionType, payload)
  payload = type(payload) == "table" and payload or {}
  local inCombat = (ns.Compat and ns.Compat.IsInCombat and ns.Compat.IsInCombat()) or false
  if inCombat then
    CommandDeck.lastActionNotice = "Action blocked during combat."
    if ns.Compat and ns.Compat.Print then
      ns.Compat.Print("Advisor actions are paused during combat.")
    end
    return false, "in_combat_lockdown"
  end

  local _, advView = ensureAdvisorViewState()

  if actionType == "CREATE_DISCOVERY_LIST" then
    if not (ns.Providers and ns.Providers.Auctionator and ns.Providers.Auctionator.CreateShoppingListDetailed) then
      return false, "auctionator_unavailable"
    end
    local ok, countOrErr, listName, details = ns.Providers.Auctionator.CreateShoppingListDetailed(
      DISCOVERY_LIST_NAME,
      {
        {
          itemID = payload.itemID,
          name = payload.name,
          isExact = true,
          maxPrice = payload.maxPrice,
        },
      },
      {
        userInitiated = true,
        passiveRefresh = false,
      }
    )
    if ok then
      CommandDeck.lastActionNotice = string.format(
        "Created discovery list '%s' (%d term%s). Verify exact stack buyout before buying!",
        tostring(listName),
        tonumber(countOrErr) or 1,
        (tonumber(countOrErr) == 1) and "" or "s"
      )
      if ns.Compat and ns.Compat.Print then
        ns.Compat.Print(CommandDeck.lastActionNotice)
      end
      CommandDeck.RefreshIfShown()
      return true, details
    else
      CommandDeck.lastActionNotice = "Discovery list pending or unavailable: " .. tostring(countOrErr)
      if ns.Compat and ns.Compat.Print then
        ns.Compat.Print(CommandDeck.lastActionNotice)
      end
      CommandDeck.RefreshIfShown()
      return false, countOrErr, details
    end
  elseif actionType == "CREATE_SUMMARY_DISCOVERY_LIST" then
    if not (ns.Providers and ns.Providers.Auctionator and ns.Providers.Auctionator.CreateShoppingListDetailed) then
      return false, "auctionator_unavailable"
    end
    local entries = {}
    for _, cand in ipairs(payload.candidates or {}) do
      table.insert(entries, {
        itemID = cand.itemID,
        name = cand.localizedLabelPending and nil or cand.displayName,
        isExact = true,
        maxPrice = cand.maxPriceDiscoveryCeilingCopper,
      })
    end
    local ok, countOrErr, listName, details = ns.Providers.Auctionator.CreateShoppingListDetailed(
      DISCOVERY_LIST_NAME,
      entries,
      {
        userInitiated = true,
        passiveRefresh = false,
      }
    )
    if ok then
      CommandDeck.lastActionNotice = string.format(
        "Created discovery list '%s' (%d created, %d pending). Scan exact stacks before buying.",
        tostring(listName),
        tonumber(details and #details.created) or tonumber(countOrErr) or 0,
        tonumber(details and #details.pending) or 0
      )
      if ns.Compat and ns.Compat.Print then
        ns.Compat.Print(CommandDeck.lastActionNotice)
      end
    end
    CommandDeck.RefreshIfShown()
    return ok == true, details or countOrErr
  elseif actionType == "START_FARM_ROUTE" then
    local fid = tostring(payload.farmID or "")
    if fid == "" then
      return false, "missing_farm_id"
    end
    if ns.Events and ns.Events.HandleGoldSubcommand then
      ns.Events.HandleGoldSubcommand("start " .. fid)
    end
    CommandDeck.RefreshIfShown()
    return true
  elseif actionType == "MARK_ROUTE_CROWDED" then
    local fid = tostring(payload.farmID or "")
    if fid == "" then
      return false, "missing_farm_id"
    end
    local srv = ns.Compat and ns.Compat.GetServerTimeSafe and ns.Compat.GetServerTimeSafe() or nil
    local nowSec = (type(srv) == "table" and tonumber(srv.epochSec) or tonumber(srv))
      or (ns.Compat and ns.Compat.NowSeconds and math.floor(ns.Compat.NowSeconds()))
      or 0
    local cd = math.max(60, math.floor(tonumber(payload.cooldownSeconds) or 1800))
    advView.crowdedUntilByFarmID[fid] = nowSec + cd
    -- If this route was currently active, pause it cleanly so we don't keep pointing into an occupied camp:
    local gProg = ns.State and ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress() or nil
    if gProg and gProg.selectedFarmID == fid and gProg.mode ~= "paused" and ns.Events and ns.Events.HandleGoldSubcommand then
      ns.Events.HandleGoldSubcommand("stop")
    end
    if ns.Compat and ns.Compat.Print then
      ns.Compat.Print(string.format("Marked '%s' as crowded for 30m — showing next supported option.", fid))
    end
    CommandDeck.RefreshIfShown()
    return true
  elseif actionType == "CLEAR_CROWDED_ROUTES" then
    advView.crowdedUntilByFarmID = {}
    if ns.Compat and ns.Compat.Print then
      ns.Compat.Print("Cleared crowded-route filters.")
    end
    CommandDeck.RefreshIfShown()
    return true
  elseif actionType == "RETRY_ITEM_CACHE" then
    for _, id in ipairs(payload.itemIDs or {}) do
      if ns.Compat and type(ns.Compat.RequestLoadItemData) == "function" then
        ns.Compat.RequestLoadItemData(id)
      end
    end
    if ns.Domain and ns.Domain.VendorArbitrage and ns.Domain.VendorArbitrage.InvalidateCache then
      ns.Domain.VendorArbitrage.InvalidateCache()
    end
    CommandDeck.RefreshIfShown()
    return true
  elseif actionType == "OPEN_TAB" then
    local targetTab = tostring(payload.tabKey or "gold")
    if ns.UI and ns.UI.Workspace and ns.UI.Workspace.SetActiveTab then
      ns.UI.Workspace.SetActiveTab(targetTab)
      return true
    end
    return false, "workspace_unavailable"
  end

  return false, "unknown_action"
end

local function createActionCard(parent)
  local card = Widgets.CreatePanel(parent, "surface.card", "border.subtle")
  if not card then
    return nil
  end
  card.leftAccent = Widgets.SafeCreateTexture(card, "BORDER", 2)
  if card.leftAccent then
    Widgets.SafeSetPoint(card.leftAccent, "TOPLEFT", card, "TOPLEFT", 0, 0)
    Widgets.SafeSetPoint(card.leftAccent, "BOTTOMLEFT", card, "BOTTOMLEFT", 0, 0)
    Widgets.SafeSetWidth(card.leftAccent, 3)
  end

  card.icon = Widgets.CreateItemIcon(card, 34)
  if card.icon then
    Widgets.SafeSetPoint(card.icon, "TOPLEFT", card, "TOPLEFT", 12, -12)
  end

  card.badge = Widgets.CreateBadge(card)
  card.titleText = Widgets.SafeCreateFontString(card, "sectionTitle", "text.primary")
  card.reasonText = Widgets.SafeCreateFontString(card, "body", "text.secondary")
  card.costText = Widgets.SafeCreateFontString(card, "dense", "accent.gold")
  card.evidenceText = Widgets.SafeCreateFontString(card, "dense", "text.muted")
  card.prereqText = Widgets.SafeCreateFontString(card, "dense", "text.muted")

  for _, fs in ipairs({ card.titleText, card.reasonText, card.costText, card.evidenceText, card.prereqText }) do
    if fs then
      if type(fs.SetJustifyH) == "function" then pcall(fs.SetJustifyH, fs, "LEFT") end
      if type(fs.SetWordWrap) == "function" then pcall(fs.SetWordWrap, fs, true) end
    end
  end

  card.primaryBtn = Widgets.CreatePrimaryButton(card, 168, "Action", 26)
  card.secondaryBtn = Widgets.CreateGhostButton(card, 118, "Too crowded", 26)
  return card
end

function CommandDeck.EnsureHost()
  if CommandDeck.host then
    return CommandDeck.host
  end
  if not (ns.UI and ns.UI.Workspace and ns.UI.Workspace.EnsureCreated) then
    return nil
  end
  local wf = ns.UI.Workspace.EnsureCreated()
  local tabParent = wf and wf.tabHosts and wf.tabHosts.advisor
  if not tabParent then
    return nil
  end

  local host = Widgets.CreatePanel(tabParent, "surface.window", nil)
  if not host then
    return nil
  end
  host.__parentRef = tabParent
  CommandDeck.host = host
  CommandDeck.frame = tabParent

  if ns.UI.Workspace.RegisterTabRenderer then
    ns.UI.Workspace.RegisterTabRenderer("advisor", {
      Refresh = function(_, contentWidth, contentHeight, isCompact)
        CommandDeck.RenderInHost(contentWidth, contentHeight, isCompact)
      end,
    })
  end

  local nsStrip = Widgets.CreatePanel(host, "surface.elevated", "border.subtle")
  if nsStrip then
    nsStrip.label = Widgets.SafeCreateFontString(nsStrip, "dense", "text.secondary")
    if nsStrip.label then
      Widgets.SafeSetPoint(nsStrip.label, "LEFT", nsStrip, "LEFT", 12, 0)
      Widgets.SafeSetPoint(nsStrip.label, "RIGHT", nsStrip, "RIGHT", -12, 0)
      if type(nsStrip.label.SetJustifyH) == "function" then pcall(nsStrip.label.SetJustifyH, nsStrip.label, "LEFT") end
    end
  end
  CommandDeck.northStarStrip = nsStrip

  local summary = Widgets.CreatePanel(host, "surface.card", "border.subtle")
  CommandDeck.summaryStrip = summary
  CommandDeck.kpis = {}
  for i = 1, 4 do
    CommandDeck.kpis[i] = Widgets.CreateKPI(summary, 170)
  end

  CommandDeck.viewport = Widgets.CreateScrollViewport(host, function(offset)
    local _, advView = ensureAdvisorViewState()
    advView.scrollOffset = offset
  end)

  return host
end

function CommandDeck.RenderInHost(viewportWidth, viewportHeight, isCompact, snapshotOverride)
  local host = CommandDeck.EnsureHost()
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

  local uiState, advView = ensureAdvisorViewState()
  local snap = Presenter.CaptureSnapshot(snapshotOverride)
  local vm = Presenter.Build(snap, uiState)

  if ns.UI.Workspace and ns.UI.Workspace.SetTabBadge then
    local badgeTxt, badgeTok = Presenter.ComputeTabBadge(snap, uiState)
    ns.UI.Workspace.SetTabBadge("advisor", badgeTxt, badgeTok)
  end

  -- 1. North Star Principle Strip (28h)
  local nsH = 28
  if CommandDeck.northStarStrip then
    Widgets.SafeClearPoints(CommandDeck.northStarStrip)
    Widgets.SafeSetPoint(CommandDeck.northStarStrip, "TOPLEFT", host, "TOPLEFT", 0, 0)
    Widgets.SafeSetSize(CommandDeck.northStarStrip, vw, nsH)
    if CommandDeck.northStarStrip.label then
      Theme.ApplyFont(CommandDeck.northStarStrip.label, "dense", "accent.gold")
      CommandDeck.northStarStrip.label:SetText(vm.northStarSubtitle)
    end
  end

  -- 2. 4-KPI Character & Reserve Strip (60h)
  local summaryH = Theme.METRICS.summaryHeight
  Widgets.SafeClearPoints(CommandDeck.summaryStrip)
  Widgets.SafeSetPoint(CommandDeck.summaryStrip, "TOPLEFT", host, "TOPLEFT", 0, -(nsH + 6))
  Widgets.SafeSetSize(CommandDeck.summaryStrip, vw, summaryH)
  local kpiW = math.floor((vw - 24) / 4)
  for i = 1, 4 do
    local kw = CommandDeck.kpis[i]
    local kd = vm.kpis[i]
    if kw and kd then
      Widgets.SafeClearPoints(kw)
      Widgets.SafeSetPoint(kw, "TOPLEFT", CommandDeck.summaryStrip, "TOPLEFT", 12 + (i - 1) * kpiW, -6)
      Widgets.SafeSetSize(kw, kpiW - 6, 48)
      kw:SetKPI(kd.value, kd.label, kd.sub, kd.token)
    end
  end

  -- 3. Vertical Full-Width Variable-Size Card Stack (`0..N` profit cards; never 3 horizontal columns)
  local bodyTop = nsH + 6 + summaryH + 8
  local vpH = math.max(160, vh - bodyTop)
  local rowWidth = vw - Theme.METRICS.scrollbarLaneWidth
  local content = CommandDeck.viewport.content

  Widgets.SafeClearPoints(CommandDeck.viewport)
  Widgets.SafeSetPoint(CommandDeck.viewport, "TOPLEFT", host, "TOPLEFT", 0, -bodyTop)

  resetPool(CommandDeck.cardPool)

  local y = 0
  local cardReports = {}

  for _, cvm in ipairs(vm.cards or {}) do
    local card = acquirePoolItem(CommandDeck.cardPool, function()
      return createActionCard(content)
    end)
    if card then
      local accentTok = cvm.isPrimary and "accent.gold" or (cvm.badgeToken or "border.subtle")
      if card.leftAccent then
        Widgets.SafeSetSolidColor(card.leftAccent, accentTok, cvm.isPrimary and 1.0 or 0.65)
      end
      Widgets.SetSurfaceBorder(card, cvm.isPrimary and "accent.gold" or "border.subtle", cvm.isPrimary and 0.72 or 1.0)

      local hasIcon = (cvm.itemID ~= nil)
      if card.icon then
        if hasIcon then
          card.icon:SetItem(cvm.itemID, cvm.title, generation)
          Widgets.SafeShow(card.icon, true)
        else
          Widgets.SafeShow(card.icon, false)
        end
      end

      local leftInset = hasIcon and 56 or 16
      local rightControlReserve = (not compact and (cvm.primaryAction or cvm.secondaryAction)) and 188 or 16
      local textW = math.max(240, rowWidth - leftInset - rightControlReserve)

      local curY = 10
      if card.badge then
        local bw = card.badge:Configure(cvm.badgeText or "Supported action", cvm.badgeToken or "status.reserved", nil, cvm.isPrimary == true)
        Widgets.SafeClearPoints(card.badge)
        Widgets.SafeSetPoint(card.badge, "TOPLEFT", card, "TOPLEFT", leftInset, -curY)
        Widgets.SafeShow(card.badge, true)
        curY = curY + 22
        local _ = bw
      end

      if card.titleText then
        Widgets.SafeClearPoints(card.titleText)
        Widgets.SafeSetPoint(card.titleText, "TOPLEFT", card, "TOPLEFT", leftInset, -curY)
        Theme.ApplyFont(card.titleText, "sectionTitle", cvm.isPrimary and "accent.gold" or "text.primary")
      end
      local titleH = Theme.MeasureWrappedHeight(card.titleText, cvm.title or "", textW, "sectionTitle", 20, 0)
      curY = curY + titleH + 3

      if card.reasonText then
        Widgets.SafeClearPoints(card.reasonText)
        Widgets.SafeSetPoint(card.reasonText, "TOPLEFT", card, "TOPLEFT", leftInset, -curY)
        Theme.ApplyFont(card.reasonText, "body", "text.secondary")
      end
      local reasonH = Theme.MeasureWrappedHeight(card.reasonText, cvm.reasonText or "", textW, "body", 18, 0)
      curY = curY + reasonH + 4

      if card.costText then
        Widgets.SafeClearPoints(card.costText)
        Widgets.SafeSetPoint(card.costText, "TOPLEFT", card, "TOPLEFT", leftInset, -curY)
        Theme.ApplyFont(card.costText, "dense", "accent.gold")
      end
      local costH = Theme.MeasureWrappedHeight(card.costText, cvm.costAndTimeText or "", textW, "dense", 16, 0)
      curY = curY + costH + 2

      if card.evidenceText then
        Widgets.SafeClearPoints(card.evidenceText)
        Widgets.SafeSetPoint(card.evidenceText, "TOPLEFT", card, "TOPLEFT", leftInset, -curY)
        Theme.ApplyFont(card.evidenceText, "dense", "text.muted")
      end
      local evH = Theme.MeasureWrappedHeight(card.evidenceText, cvm.evidenceText or "", textW, "dense", 16, 0)
      curY = curY + evH + 2

      if cvm.prereqText and cvm.prereqText ~= "" then
        if card.prereqText then
          Widgets.SafeClearPoints(card.prereqText)
          Widgets.SafeSetPoint(card.prereqText, "TOPLEFT", card, "TOPLEFT", leftInset, -curY)
          Theme.ApplyFont(card.prereqText, "dense", "text.muted")
          Widgets.SafeShow(card.prereqText, true)
        end
        local preH = Theme.MeasureWrappedHeight(card.prereqText, cvm.prereqText, textW, "dense", 16, 0)
        curY = curY + preH + 4
      elseif card.prereqText then
        Widgets.SafeShow(card.prereqText, false)
      end

      -- Action Buttons (Right-aligned in wide mode; stacked cleanly at bottom of card in compact mode):
      if card.primaryBtn then
        if cvm.primaryAction then
          card.primaryBtn:SetLabel(cvm.primaryAction.label)
          local act = cvm.primaryAction
          card.primaryBtn:SetOnClick(function()
            CommandDeck.Dispatch(act.actionType, act.payload)
          end)
          Widgets.SafeClearPoints(card.primaryBtn)
          if compact then
            Widgets.SafeSetPoint(card.primaryBtn, "TOPLEFT", card, "TOPLEFT", leftInset, -(curY + 4))
          else
            Widgets.SafeSetPoint(card.primaryBtn, "TOPRIGHT", card, "TOPRIGHT", -12, -14)
          end
          Widgets.SafeShow(card.primaryBtn, true)
        else
          Widgets.SafeShow(card.primaryBtn, false)
        end
      end

      if card.secondaryBtn then
        if cvm.secondaryAction then
          card.secondaryBtn:SetLabel(cvm.secondaryAction.label)
          local sAct = cvm.secondaryAction
          card.secondaryBtn:SetOnClick(function()
            CommandDeck.Dispatch(sAct.actionType, sAct.payload)
          end)
          Widgets.SafeClearPoints(card.secondaryBtn)
          if compact then
            if cvm.primaryAction then
              Widgets.SafeSetPoint(card.secondaryBtn, "LEFT", card.primaryBtn, "RIGHT", 8, 0)
            else
              Widgets.SafeSetPoint(card.secondaryBtn, "TOPLEFT", card, "TOPLEFT", leftInset, -(curY + 4))
            end
          else
            Widgets.SafeSetPoint(card.secondaryBtn, "TOPRIGHT", card, "TOPRIGHT", -12, -46)
          end
          Widgets.SafeShow(card.secondaryBtn, true)
        else
          Widgets.SafeShow(card.secondaryBtn, false)
        end
      end

      if compact and (cvm.primaryAction or cvm.secondaryAction) then
        curY = curY + 36
      end

      local cardH = math.max(92, curY + 10)
      Widgets.SafeClearPoints(card)
      Widgets.SafeSetPoint(card, "TOPLEFT", content, "TOPLEFT", 0, -y)
      Widgets.SafeSetSize(card, rowWidth, cardH)
      Widgets.SafeShow(card, true)

      table.insert(cardReports, {
        cardID = cvm.cardID,
        kind = cvm.kind,
        badgeText = cvm.badgeText,
        badgeToken = cvm.badgeToken,
        width = rowWidth,
        height = cardH,
        y = y,
        isPrimary = (cvm.isPrimary == true),
      })
      y = y + cardH + 8
    end
  end

  CommandDeck.viewport:SetDimensions(vw, vpH, math.max(vpH, y + 12))
  CommandDeck.viewport:SetScrollOffset(advView.scrollOffset or 0, true)

  local report = {
    isCompact = compact,
    viewportWidth = vw,
    viewportHeight = vh,
    rowWidth = rowWidth,
    cardCount = #cardReports,
    supportedActionCount = vm.supportedActionCount,
    cards = cardReports,
    contentHeight = y,
  }
  CommandDeck.lastLayoutReport = report
  return report
end

function CommandDeck.Refresh()
  CommandDeck.EnsureHost()
  if ns.UI.Workspace and ns.UI.Workspace.IsShown and ns.UI.Workspace.IsShown() then
    local st = ns.State.GetWorkspaceUIState()
    if st.activeTab == "advisor" then
      ns.UI.Workspace.Refresh()
    end
  end
  return true
end

function CommandDeck.RefreshIfShown()
  return CommandDeck.Refresh()
end

function CommandDeck.Toggle()
  CommandDeck.EnsureHost()
  if ns.UI.Workspace and ns.UI.Workspace.Toggle then
    ns.UI.Workspace.Toggle("advisor")
    return true
  end
  return false
end

if ns.UI.Workspace and ns.UI.Workspace.RegisterTabRenderer then
  ns.UI.Workspace.RegisterTabRenderer("advisor", {
    Refresh = function(_, contentWidth, contentHeight, isCompact)
      CommandDeck.RenderInHost(contentWidth, contentHeight, isCompact)
    end,
  })
end

return CommandDeck
