local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.UI = ns.UI or {}

local Theme = ns.UI.Theme
local Widgets = ns.UI.Widgets
local Presenter = ns.UI.RivergladesPresenter

local RivergladesUI = {
  host = nil,
  summaryStrip = nil,
  kpis = {},
  controlsBar = nil,
  hubSidebar = nil,
  hubCompactBar = nil,
  detailViewport = nil,
  currentCard = nil,
  hubRowPool = {},
  sectionHeaderPool = {},
  questRowPool = {},
  unresolvedRowPool = {},
  decisionRowPool = {},
  badgePool = {},
  lastLayoutReport = nil,
}
ns.UI.Riverglades = RivergladesUI

local HUB_SIDEBAR_WIDTH = 200
local COLUMN_GAP = 12
local HUB_ROW_MIN_HEIGHT = 44
local QUEST_ROW_MIN_HEIGHT = 56

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
  local used = pool.__used or 0
  for i = 1, #pool do
    if i <= used or pool[i] then
      Widgets.SafeShow(pool[i], false)
    end
  end
  pool.__used = 0
end

local function syncLiveNavigationAndMap()
  local prog = ns.State and ns.State.GetRouteProgress and ns.State.GetRouteProgress() or nil
  local nav = ns.UI and ns.UI.Navigation or nil
  if prog and prog.mode ~= "paused" and ns.Domain and ns.Domain.RouteProgress then
    local ev = ns.Domain.RouteProgress.Reconcile()
    if nav and nav.SyncFromEvaluation then
      nav.SyncFromEvaluation(ev, prog)
    end
  elseif prog and nav and nav.SyncFromEvaluation and nav.activeContext == "riverglades" then
    local ev = ns.Domain and ns.Domain.RouteProgress and ns.Domain.RouteProgress.Evaluate() or nil
    if ev then
      nav.SyncFromEvaluation(ev, prog)
    end
  end
  if ns.UI and ns.UI.WorldMapPins and ns.UI.WorldMapPins.RefreshIfVisible then
    ns.UI.WorldMapPins.RefreshIfVisible()
  end
end

function RivergladesUI.Dispatch(actionType, payload)
  payload = type(payload) == "table" and payload or {}
  local uiState = ns.State.GetWorkspaceUIState()
  local rgView = uiState.rivergladesView
  local prog = ns.State.GetRouteProgress()
  local RouteProgress = ns.Domain and ns.Domain.RouteProgress

  if actionType == "SELECT_HUB" then
    rgView.selectedHubID = tostring(payload.hubID or "all")
    rgView.scrollOffset = 0
    if RivergladesUI.detailViewport then
      RivergladesUI.detailViewport:SetScrollOffset(0, true)
    end
    RivergladesUI.Refresh()
    return true
  elseif actionType == "TOGGLE_START_PAUSE" then
    if not RouteProgress then
      return false
    end
    if prog.mode == "standalone" then
      local _, ev = RouteProgress.Pause()
      if ns.UI.Navigation and ns.UI.Navigation.SyncFromEvaluation then
        ns.UI.Navigation.SyncFromEvaluation(ev, prog)
      end
    else
      local ok, ev = RouteProgress.Start()
      if ok and ns.UI.Navigation and ns.UI.Navigation.SyncFromEvaluation then
        ns.UI.Navigation.SyncFromEvaluation(ev, prog)
      end
    end
    if ns.UI.WorldMapPins and ns.UI.WorldMapPins.RefreshIfVisible then
      ns.UI.WorldMapPins.RefreshIfVisible()
    end
    RivergladesUI.Refresh()
    return true
  elseif actionType == "SKIP_CURRENT" then
    if RouteProgress and RouteProgress.SkipCurrent then
      local ok, ev = RouteProgress.SkipCurrent()
      if ok and ns.UI.Navigation and ns.UI.Navigation.SyncFromEvaluation then
        ns.UI.Navigation.SyncFromEvaluation(ev, prog)
      end
      if ns.UI.WorldMapPins and ns.UI.WorldMapPins.RefreshIfVisible then
        ns.UI.WorldMapPins.RefreshIfVisible()
      end
    end
    RivergladesUI.Refresh()
    return true
  elseif actionType == "FOCUS_ACTION" then
    local aid = payload.actionID
    if type(aid) == "string" and aid ~= "" then
      prog.pinnedActionID = aid
      prog.pinnedSubLocationID = nil
      local rxpSel = ns.Bridges and ns.Bridges.RXPBridge and ns.Bridges.RXPBridge.IsRivergladesGuideSelected
          and ns.Bridges.RXPBridge.IsRivergladesGuideSelected()
        or false
      if rxpSel then
        prog.mode = "rxp"
        local ev = RouteProgress and RouteProgress.Evaluate() or nil
        if ev and ns.UI.Navigation and ns.UI.Navigation.SyncFromEvaluation then
          ns.UI.Navigation.SyncFromEvaluation(ev, prog)
        end
      else
        if prog.mode == "paused" and RouteProgress and RouteProgress.Start then
          local ok, ev = RouteProgress.Start()
          prog.pinnedActionID = aid
          ev = RouteProgress.Reconcile() or ev
          if ok and ns.UI.Navigation and ns.UI.Navigation.SyncFromEvaluation then
            ns.UI.Navigation.SyncFromEvaluation(ev, prog)
          end
        else
          syncLiveNavigationAndMap()
        end
      end
      if ns.UI.WorldMapPins and ns.UI.WorldMapPins.RefreshIfVisible then
        ns.UI.WorldMapPins.RefreshIfVisible()
      end
    end
    RivergladesUI.Refresh()
    return true
  elseif actionType == "UNPIN_ACTION" then
    prog.pinnedActionID = nil
    prog.pinnedSubLocationID = nil
    syncLiveNavigationAndMap()
    RivergladesUI.Refresh()
    return true
  elseif actionType == "TOGGLE_ACTION_EXPANDED" then
    local aid = tostring(payload.actionID or "")
    if aid ~= "" then
      rgView.expandedByActionID[aid] = not (rgView.expandedByActionID[aid] == true)
      RivergladesUI.Refresh()
    end
    return true
  elseif actionType == "TOGGLE_SKIP_ACTION" then
    local aid = tostring(payload.actionID or "")
    if aid ~= "" then
      prog.explicitlySkippedActions = prog.explicitlySkippedActions or {}
      if prog.explicitlySkippedActions[aid] then
        prog.explicitlySkippedActions[aid] = nil
      else
        prog.explicitlySkippedActions[aid] = {
          skippedAt = (type(time) == "function" and time()) or 0,
          reason = "workspace_skip",
        }
        if prog.pinnedActionID == aid then
          prog.pinnedActionID = nil
          prog.pinnedSubLocationID = nil
        end
      end
      syncLiveNavigationAndMap()
      RivergladesUI.Refresh()
    end
    return true
  elseif actionType == "CONFIRM_COMPLETED" then
    if payload.questKey and ns.State.ConfirmUnresolvedQuestCompleted then
      rgView.unresolvedCollapsedByUser = false
      ns.State.ConfirmUnresolvedQuestCompleted(payload.questKey, prog)
      syncLiveNavigationAndMap()
      RivergladesUI.Refresh()
      return true
    end
    return false
  elseif actionType == "CONFIRM_INCOMPLETE" then
    if payload.questKey and ns.State.ConfirmUnresolvedQuestIncomplete then
      rgView.unresolvedCollapsedByUser = false
      ns.State.ConfirmUnresolvedQuestIncomplete(payload.questKey, prog)
      syncLiveNavigationAndMap()
      RivergladesUI.Refresh()
      return true
    end
    return false
  elseif actionType == "UNDO_HISTORY_DECISION" or actionType == "LEAVE_UNRESOLVED" then
    if ns.State.UndoUnresolvedQuestDecision then
      rgView.unresolvedCollapsedByUser = false
      ns.State.UndoUnresolvedQuestDecision(payload.questKey, prog)
      syncLiveNavigationAndMap()
      RivergladesUI.Refresh()
      return true
    end
    return false
  elseif actionType == "TOGGLE_UNRESOLVED_SECTION" then
    local curSnap = Presenter.CaptureSnapshot()
    local curVM = Presenter.Build(curSnap, uiState)
    local nextOpen = not (curVM.unresolvedExpanded == true)
    rgView.unresolvedExpanded = nextOpen
    rgView.unresolvedCollapsedByUser = not nextOpen
    RivergladesUI.Refresh()
    return true
  elseif actionType == "TOGGLE_BLOCKED_SECTION" then
    rgView.blockedExpanded = not (rgView.blockedExpanded == true)
    RivergladesUI.Refresh()
    return true
  elseif actionType == "TOGGLE_ELITES" then
    prog.includeEliteBounties = (payload.checked == true)
    syncLiveNavigationAndMap()
    RivergladesUI.Refresh()
    return true
  elseif actionType == "TOGGLE_GROUP" then
    prog.includeGroupBranch = (payload.checked == true)
    syncLiveNavigationAndMap()
    RivergladesUI.Refresh()
    return true
  elseif actionType == "EXPORT_RXP" then
    if ns.Bridges and ns.Bridges.RXPBridge and ns.Bridges.RXPBridge.RegisterRivergladesGuide then
      local ok, statusOrErr = ns.Bridges.RXPBridge.RegisterRivergladesGuide(true)
      if ok then
        rgView.lastExportedAt = (type(time) == "function" and time()) or 1
        if ns.Compat and ns.Compat.Print then
          ns.Compat.Print("Exported static Riverglades itinerary snapshot to RestedXP Guides ('ForeverHub Routes').")
        end
      elseif ns.Compat and ns.Compat.Print then
        ns.Compat.Print("Riverglades RXP export unavailable: " .. tostring(statusOrErr or "RXPGuides not loaded"))
      end
    end
    RivergladesUI.Refresh()
    return true
  end
  return false
end

local function createHubRow(parent)
  local ok, btn = pcall(_G.CreateFrame, "Button", nil, parent)
  if not ok or not btn then
    return nil
  end
  if type(btn.EnableMouse) == "function" then pcall(btn.EnableMouse, btn, true) end
  if type(btn.RegisterForClicks) == "function" then pcall(btn.RegisterForClicks, btn, "LeftButtonUp") end
  Widgets.ApplySurface(btn, "surface.card", "border.subtle")

  btn.accentBar = Widgets.SafeCreateTexture(btn, "OVERLAY", 2)
  if btn.accentBar then
    Widgets.SafeSetPoint(btn.accentBar, "TOPLEFT", btn, "TOPLEFT", 0, -1)
    Widgets.SafeSetPoint(btn.accentBar, "BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 1)
    Widgets.SafeSetWidth(btn.accentBar, 3)
    Widgets.SafeSetSolidColor(btn.accentBar, "accent.gold", 1.0)
  end

  btn.nameText = Widgets.SafeCreateFontString(btn, "body", "text.primary")
  if btn.nameText then
    Widgets.SafeSetPoint(btn.nameText, "TOPLEFT", btn, "TOPLEFT", 10, -7)
    if type(btn.nameText.SetJustifyH) == "function" then pcall(btn.nameText.SetJustifyH, btn.nameText, "LEFT") end
  end

  btn.summaryText = Widgets.SafeCreateFontString(btn, "dense", "text.secondary")
  if btn.summaryText then
    Widgets.SafeSetPoint(btn.summaryText, "TOPLEFT", btn, "TOPLEFT", 10, -25)
    if type(btn.summaryText.SetJustifyH) == "function" then pcall(btn.summaryText.SetJustifyH, btn.summaryText, "LEFT") end
  end

  return btn
end

local function createSectionHeader(parent)
  local f = Widgets.CreatePanel(parent, "surface.window", nil)
  if not f then
    return nil
  end
  Widgets.SafeSetHeight(f, 26)
  f.title = Widgets.SafeCreateFontString(f, "sectionTitle", "text.primary")
  if f.title then
    Widgets.SafeSetPoint(f.title, "LEFT", f, "LEFT", 2, 0)
    if type(f.title.SetJustifyH) == "function" then pcall(f.title.SetJustifyH, f.title, "LEFT") end
  end
  f.toggleBtn = Widgets.CreateGhostButton(f, 92, "Expand", 24)
  if f.toggleBtn then
    Widgets.SafeSetPoint(f.toggleBtn, "RIGHT", f, "RIGHT", 0, 0)
  end
  return f
end

local function createQuestRow(parent)
  local card = Widgets.CreatePanel(parent, "surface.card", "border.subtle")
  if not card then
    return nil
  end
  card.glyphTex = Widgets.SafeCreateTexture(card, "ARTWORK", 1)
  if card.glyphTex then
    Widgets.SafeSetSize(card.glyphTex, 18, 18)
    Widgets.SafeSetPoint(card.glyphTex, "TOPLEFT", card, "TOPLEFT", 12, -12)
  end
  card.glyphFallback = Widgets.SafeCreateFontString(card, "sectionTitle", "accent.gold")
  if card.glyphFallback then
    Widgets.SafeSetPoint(card.glyphFallback, "TOPLEFT", card, "TOPLEFT", 14, -10)
  end

  card.titleText = Widgets.SafeCreateFontString(card, "body", "text.primary")
  if card.titleText then
    if type(card.titleText.SetJustifyH) == "function" then pcall(card.titleText.SetJustifyH, card.titleText, "LEFT") end
  end

  card.subText = Widgets.SafeCreateFontString(card, "dense", "text.secondary")
  if card.subText then
    if type(card.subText.SetJustifyH) == "function" then pcall(card.subText.SetJustifyH, card.subText, "LEFT") end
  end

  card.focusBtn = Widgets.CreateSecondaryButton(card, 72, "Focus", 24)
  card.expandBtn = Widgets.CreateIconButton(card, "chevron_right", "Quest details", { "Inspect prerequisites, objective spots, and provenance." }, 24, 13)

  card.detailBox = Widgets.CreatePanel(card, "surface.elevated", "border.subtle")
  if card.detailBox then
    card.detailText = Widgets.SafeCreateFontString(card.detailBox, "dense", "text.secondary")
    if card.detailText and type(card.detailText.SetJustifyH) == "function" then
      pcall(card.detailText.SetJustifyH, card.detailText, "LEFT")
    end
    card.skipBtn = Widgets.CreateGhostButton(card.detailBox, 92, "Skip step", 24)
  end

  return card
end

local function createUnresolvedRow(parent)
  local card = Widgets.CreatePanel(parent, "surface.card", "status.warning")
  if not card then
    return nil
  end
  Widgets.SetSurfaceBorder(card, "status.warning", 0.55)

  card.warnTex = Widgets.SafeCreateTexture(card, "ARTWORK", 1)
  if card.warnTex then
    Widgets.SafeSetSize(card.warnTex, 16, 16)
    Widgets.SafeSetPoint(card.warnTex, "TOPLEFT", card, "TOPLEFT", 12, -12)
  end
  card.warnFallback = Widgets.SafeCreateFontString(card, "body", "status.warning")
  if card.warnFallback then
    Widgets.SafeSetPoint(card.warnFallback, "TOPLEFT", card, "TOPLEFT", 14, -10)
  end
  Widgets.ApplyGlyph(card.warnTex, card.warnFallback, "warning", "status.warning")

  card.titleText = Widgets.SafeCreateFontString(card, "body", "text.primary")
  if card.titleText and type(card.titleText.SetJustifyH) == "function" then
    pcall(card.titleText.SetJustifyH, card.titleText, "LEFT")
  end
  card.promptText = Widgets.SafeCreateFontString(card, "dense", "text.secondary")
  if card.promptText and type(card.promptText.SetJustifyH) == "function" then
    pcall(card.promptText.SetJustifyH, card.promptText, "LEFT")
  end

  card.completedBtn = Widgets.CreateSecondaryButton(card, 126, "I completed this", 24)
  card.incompleteBtn = Widgets.CreateSecondaryButton(card, 112, "Not completed", 24)
  card.leaveBtn = Widgets.CreateGhostButton(card, 120, "Leave unresolved", 24)
  return card
end

local function createDecisionRow(parent)
  local row = Widgets.CreatePanel(parent, "surface.elevated", "border.subtle")
  if not row then
    return nil
  end
  Widgets.SafeSetHeight(row, 36)
  row.titleText = Widgets.SafeCreateFontString(row, "dense", "text.primary")
  if row.titleText then
    Widgets.SafeSetPoint(row.titleText, "LEFT", row, "LEFT", 10, 0)
    if type(row.titleText.SetJustifyH) == "function" then pcall(row.titleText.SetJustifyH, row.titleText, "LEFT") end
  end
  row.badge = Widgets.CreateBadge(row)
  row.undoBtn = Widgets.CreateGhostButton(row, 60, "Undo", 24)
  if row.undoBtn then
    Widgets.SafeSetPoint(row.undoBtn, "RIGHT", row, "RIGHT", -8, 0)
  end
  return row
end

function RivergladesUI.EnsureHost()
  local wsFrame = ns.UI.Workspace and ns.UI.Workspace.EnsureCreated and ns.UI.Workspace.EnsureCreated() or nil
  local tabParent = (wsFrame and wsFrame.tabHosts and wsFrame.tabHosts.riverglades) or _G.UIParent
  if RivergladesUI.host and RivergladesUI.host.__parentRef == tabParent then
    return RivergladesUI.host
  end

  local host = Widgets.CreatePanel(tabParent, "surface.window", nil)
  if not host then
    return nil
  end
  host.__parentRef = tabParent
  RivergladesUI.host = host

  if ns.UI.Workspace and ns.UI.Workspace.RegisterTabRenderer then
    ns.UI.Workspace.RegisterTabRenderer("riverglades", {
      Refresh = function(_, contentWidth, contentHeight, isCompact)
        RivergladesUI.RenderInHost(contentWidth, contentHeight, isCompact)
      end,
    })
  end

  -- 1. Top 4-KPI Summary Strip (60 high)
  local summary = Widgets.CreatePanel(host, "surface.card", "border.subtle")
  RivergladesUI.summaryStrip = summary
  RivergladesUI.kpis = {}
  for i = 1, 4 do
    RivergladesUI.kpis[i] = Widgets.CreateKPI(summary, 180)
  end

  -- 2. Toggles & Static Export Bar (36 high)
  local cbar = Widgets.CreatePanel(host, "surface.card", "border.subtle")
  RivergladesUI.controlsBar = cbar
  cbar.elitesCheck = Widgets.CreateCheckbox(
    cbar,
    "Include elite bounties",
    "Elite WANTED Bounties",
    { "Includes [42+] WANTED: Blademaster Kaijo, Ghostmaw, and Old Rot-Chum in active routing and map pins." },
    function(checked)
      RivergladesUI.Dispatch("TOGGLE_ELITES", { checked = checked })
    end
  )
  cbar.groupCheck = Widgets.CreateCheckbox(
    cbar,
    "Include group branch",
    "Krol'dok Stronghold Group Quests",
    { "Includes the optional Krol'dok Stronghold group quest chain after solo zone objectives." },
    function(checked)
      RivergladesUI.Dispatch("TOGGLE_GROUP", { checked = checked })
    end
  )
  cbar.exportNote = Widgets.SafeCreateFontString(cbar, "dense", "text.muted")
  if cbar.exportNote and type(cbar.exportNote.SetJustifyH) == "function" then
    pcall(cbar.exportNote.SetJustifyH, cbar.exportNote, "RIGHT")
  end
  cbar.exportBtn = Widgets.CreateSecondaryButton(cbar, 158, "Export static itinerary", 26)
  if cbar.exportBtn then
    cbar.exportBtn:SetOnClick(function()
      RivergladesUI.Dispatch("EXPORT_RXP")
    end)
    Widgets.BindTooltip(
      cbar.exportBtn,
      "Export Static Itinerary to RestedXP",
      {
        "Generates a point-in-time guide snapshot under 'ForeverHub Routes'.",
        "Limitation: RXP guides are static text and do not dynamically re-score hub proximity or unresolved title history mid-run.",
      }
    )
  end

  -- 3. Left Hub Sidebar (Standard >=900 width: 200 wide)
  RivergladesUI.hubSidebar = Widgets.CreatePanel(host, "surface.window", nil)

  -- 4. Compact Hub Selector Strip (<900 width)
  local segOpts = {}
  for _, h in ipairs(Presenter.HUB_DEFINITIONS) do
    table.insert(segOpts, {
      key = h.id,
      label = h.shortName,
      width = 112,
      tooltipTitle = h.name,
      tooltipLines = { "Filter Riverglades steps to " .. h.name .. "." },
    })
  end
  RivergladesUI.hubCompactBar = Widgets.CreateSegmentedFilter(host, segOpts, function(hubKey)
    RivergladesUI.Dispatch("SELECT_HUB", { hubID = hubKey })
  end)

  -- 5. Right / Main Detail Scroll Viewport
  RivergladesUI.detailViewport = Widgets.CreateScrollViewport(host, function(offset)
    local st = ns.State.GetWorkspaceUIState()
    st.rivergladesView.scrollOffset = offset
  end)

  -- Current Action Card inside Detail Content
  local content = RivergladesUI.detailViewport and RivergladesUI.detailViewport.content or host
  local cur = Widgets.CreatePanel(content, "surface.elevated", "accent.gold")
  if cur then
    Widgets.SetSurfaceBorder(cur, "accent.gold", 0.70)
    cur.heading = Widgets.SafeCreateFontString(cur, "dense", "accent.gold")
    if cur.heading then
      Widgets.SafeSetPoint(cur.heading, "TOPLEFT", cur, "TOPLEFT", 12, -10)
      cur.heading:SetText("CURRENT ROUTE STEP")
    end
    cur.providerText = Widgets.SafeCreateFontString(cur, "dense", "text.muted")
    if cur.providerText then
      Widgets.SafeSetPoint(cur.providerText, "TOPRIGHT", cur, "TOPRIGHT", -12, -10)
    end
    cur.titleText = Widgets.SafeCreateFontString(cur, "sectionTitle", "text.primary")
    if cur.titleText and type(cur.titleText.SetJustifyH) == "function" then
      pcall(cur.titleText.SetJustifyH, cur.titleText, "LEFT")
    end
    cur.detailText = Widgets.SafeCreateFontString(cur, "body", "text.secondary")
    if cur.detailText and type(cur.detailText.SetJustifyH) == "function" then
      pcall(cur.detailText.SetJustifyH, cur.detailText, "LEFT")
    end
    cur.primaryBtn = Widgets.CreatePrimaryButton(cur, 112, "Start route", 28)
    if cur.primaryBtn then
      cur.primaryBtn:SetOnClick(function()
        RivergladesUI.Dispatch("TOGGLE_START_PAUSE")
      end)
    end
    cur.skipBtn = Widgets.CreateSecondaryButton(cur, 92, "Skip step", 28)
    if cur.skipBtn then
      cur.skipBtn:SetOnClick(function()
        RivergladesUI.Dispatch("SKIP_CURRENT")
      end)
    end
    cur.unpinBtn = Widgets.CreateGhostButton(cur, 76, "Unpin", 28)
    if cur.unpinBtn then
      cur.unpinBtn:SetOnClick(function()
        RivergladesUI.Dispatch("UNPIN_ACTION")
      end)
    end
  end
  RivergladesUI.currentCard = cur

  return host
end

function RivergladesUI.RenderInHost(viewportWidth, viewportHeight, isCompact, snapshotOverride)
  local host = RivergladesUI.EnsureHost()
  if not host then
    return nil
  end

  Widgets.BumpGeneration()
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
    ns.UI.Workspace.SetTabBadge("riverglades", vm.tabBadge, vm.tabBadgeToken)
  end

  -- 1. Layout Summary Strip (60h)
  local summaryH = Theme.METRICS.summaryHeight
  Widgets.SafeClearPoints(RivergladesUI.summaryStrip)
  Widgets.SafeSetPoint(RivergladesUI.summaryStrip, "TOPLEFT", host, "TOPLEFT", 0, 0)
  Widgets.SafeSetSize(RivergladesUI.summaryStrip, vw, summaryH)
  local kpiColW = math.floor((vw - 24) / 4)
  for i = 1, 4 do
    local kpiW = RivergladesUI.kpis[i]
    local kpiData = vm.kpis[i]
    if kpiW and kpiData then
      Widgets.SafeClearPoints(kpiW)
      Widgets.SafeSetPoint(kpiW, "TOPLEFT", RivergladesUI.summaryStrip, "TOPLEFT", 12 + (i - 1) * kpiColW, -6)
      Widgets.SafeSetSize(kpiW, kpiColW - 8, 48)
      kpiW:SetKPI(kpiData.value, kpiData.label, kpiData.sub, kpiData.token, kpiData.tooltipTitle, kpiData.tooltipLines)
    end
  end

  -- 2. Layout Controls & Export Bar (36h)
  local controlsH = 36
  local controlsTopY = -(summaryH + 8)
  local cbar = RivergladesUI.controlsBar
  Widgets.SafeClearPoints(cbar)
  Widgets.SafeSetPoint(cbar, "TOPLEFT", host, "TOPLEFT", 0, controlsTopY)
  Widgets.SafeSetSize(cbar, vw, controlsH)

  if cbar.elitesCheck then
    cbar.elitesCheck:SetChecked(vm.includeEliteBounties)
    Widgets.SafeClearPoints(cbar.elitesCheck)
    Widgets.SafeSetPoint(cbar.elitesCheck, "LEFT", cbar, "LEFT", 10, 0)
  end
  if cbar.groupCheck then
    cbar.groupCheck:SetChecked(vm.includeGroupBranch)
    Widgets.SafeClearPoints(cbar.groupCheck)
    Widgets.SafeSetPoint(cbar.groupCheck, "LEFT", cbar, "LEFT", 184, 0)
  end
  if cbar.exportBtn then
    Widgets.SafeClearPoints(cbar.exportBtn)
    Widgets.SafeSetPoint(cbar.exportBtn, "RIGHT", cbar, "RIGHT", -8, 0)
  end
  if cbar.exportNote then
    Widgets.SafeClearPoints(cbar.exportNote)
    Widgets.SafeSetPoint(cbar.exportNote, "RIGHT", cbar.exportBtn, "LEFT", -10, 0)
    Theme.ApplyFont(cbar.exportNote, "dense", "text.muted")
    cbar.exportNote:SetText(compact and "Static RXP snapshot" or vm.exportNote)
  end

  -- 3. Hub Sidebar vs Compact Hub Selector
  local bodyTopOffset = summaryH + 8 + controlsH + 8
  local detailViewportX = 0
  local detailViewportW = vw
  local hubReports = {}

  resetPool(RivergladesUI.hubRowPool)
  resetPool(RivergladesUI.sectionHeaderPool)
  resetPool(RivergladesUI.questRowPool)
  resetPool(RivergladesUI.unresolvedRowPool)
  resetPool(RivergladesUI.decisionRowPool)
  resetPool(RivergladesUI.badgePool)

  if compact then
    Widgets.SafeShow(RivergladesUI.hubSidebar, false)
    if RivergladesUI.hubCompactBar then
      Widgets.SafeClearPoints(RivergladesUI.hubCompactBar)
      Widgets.SafeSetPoint(RivergladesUI.hubCompactBar, "TOPLEFT", host, "TOPLEFT", 0, -bodyTopOffset)
      RivergladesUI.hubCompactBar:SetSelected(vm.selectedHubID)
      Widgets.SafeShow(RivergladesUI.hubCompactBar, true)
      bodyTopOffset = bodyTopOffset + Theme.METRICS.controlHeight + 8
    end
  else
    Widgets.SafeShow(RivergladesUI.hubCompactBar, false)
    Widgets.SafeClearPoints(RivergladesUI.hubSidebar)
    Widgets.SafeSetPoint(RivergladesUI.hubSidebar, "TOPLEFT", host, "TOPLEFT", 0, -bodyTopOffset)
    local bodyH = math.max(180, vh - bodyTopOffset)
    Widgets.SafeSetSize(RivergladesUI.hubSidebar, HUB_SIDEBAR_WIDTH, bodyH)
    Widgets.SafeShow(RivergladesUI.hubSidebar, true)

    local hy = 0
    for _, hvm in ipairs(vm.hubs) do
      local hRow = acquirePoolItem(RivergladesUI.hubRowPool, function()
        return createHubRow(RivergladesUI.hubSidebar)
      end)
      if hRow then
        local sumH = Theme.MeasureWrappedHeight(hRow.summaryText, hvm.summary, HUB_SIDEBAR_WIDTH - 20, "dense", 16, 0)
        local rowH = math.max(HUB_ROW_MIN_HEIGHT, 26 + sumH + 6)
        Widgets.SafeClearPoints(hRow)
        Widgets.SafeSetPoint(hRow, "TOPLEFT", RivergladesUI.hubSidebar, "TOPLEFT", 0, -hy)
        Widgets.SafeSetSize(hRow, HUB_SIDEBAR_WIDTH, rowH)

        Widgets.SafeSetSolidColor(hRow.__fhBg, hvm.isSelected and "surface.selected" or "surface.card", 1.0)
        Widgets.SetSurfaceBorder(hRow, hvm.isSelected and "accent.gold" or "border.subtle", hvm.isSelected and 0.80 or 1.0)
        Widgets.SafeShow(hRow.accentBar, hvm.isSelected)

        if hRow.nameText then
          Theme.ApplyFont(hRow.nameText, "body", hvm.isSelected and "accent.gold" or "text.primary")
          hRow.nameText:SetText(hvm.name)
        end
        if hRow.summaryText then
          local sumTok = hvm.hasReady and "status.ready" or (hvm.hasUnresolved and "status.warning" or "text.secondary")
          Theme.ApplyFont(hRow.summaryText, "dense", sumTok)
          hRow.summaryText:SetText(hvm.summary)
        end

        local targetHubID = hvm.id
        hRow:SetScript("OnClick", function()
          RivergladesUI.Dispatch("SELECT_HUB", { hubID = targetHubID })
        end)
        Widgets.SafeShow(hRow, true)
        table.insert(hubReports, { id = hvm.id, height = rowH, width = HUB_SIDEBAR_WIDTH })
        hy = hy + rowH + 6
      end
    end

    detailViewportX = HUB_SIDEBAR_WIDTH + COLUMN_GAP
    detailViewportW = vw - detailViewportX
  end

  -- 4. Detail Scroll Content (700 standard width = 928 - 200 - 12 - 16 scrollbar lane!)
  local detailViewportH = math.max(160, vh - bodyTopOffset)
  local content = RivergladesUI.detailViewport.content
  local detailContentW = math.max(240, detailViewportW - Theme.METRICS.scrollbarLaneWidth)

  Widgets.SafeClearPoints(RivergladesUI.detailViewport)
  Widgets.SafeSetPoint(RivergladesUI.detailViewport, "TOPLEFT", host, "TOPLEFT", detailViewportX, -bodyTopOffset)

  local y = 0
  local rowReports = {}

  -- (A) Current Action Card
  local cur = RivergladesUI.currentCard
  if cur then
    if cur.heading then
      cur.heading:SetText(vm.currentAction.headingText or "CURRENT ROUTE STEP")
    end
    local rightActionsW = 124 + (vm.currentAction.hasAction and 98 or 0) + (vm.currentAction.isPinned and 82 or 0)
    local curTextW = math.max(180, detailContentW - 24 - rightActionsW)
    if cur.titleText then
      Widgets.SafeClearPoints(cur.titleText)
      Widgets.SafeSetPoint(cur.titleText, "TOPLEFT", cur, "TOPLEFT", 12, -28)
      Theme.ApplyFont(cur.titleText, "sectionTitle", "text.primary")
    end
    local titleH = Theme.MeasureWrappedHeight(cur.titleText, vm.currentAction.title, curTextW, "sectionTitle", 20, 0)

    if cur.detailText then
      Widgets.SafeClearPoints(cur.detailText)
      Widgets.SafeSetPoint(cur.detailText, "TOPLEFT", cur, "TOPLEFT", 12, -(28 + titleH + 4))
      Theme.ApplyFont(cur.detailText, "body", "text.secondary")
    end
    local detH = Theme.MeasureWrappedHeight(cur.detailText, vm.currentAction.detail, curTextW, "body", 18, 0)
    if cur.providerText then
      Theme.ApplyFont(cur.providerText, "dense", "text.muted")
      cur.providerText:SetText(vm.currentAction.providerText or "")
    end

    local curCardH = math.max(76, 28 + titleH + 4 + detH + 12)
    Widgets.SafeClearPoints(cur)
    Widgets.SafeSetPoint(cur, "TOPLEFT", content, "TOPLEFT", 0, -y)
    Widgets.SafeSetSize(cur, detailContentW, curCardH)

    if cur.primaryBtn then
      cur.primaryBtn:SetLabel(vm.currentAction.primaryButtonLabel)
      Widgets.SafeClearPoints(cur.primaryBtn)
      Widgets.SafeSetPoint(cur.primaryBtn, "BOTTOMRIGHT", cur, "BOTTOMRIGHT", -12, 12)
      Widgets.SafeShow(cur.primaryBtn, true)
    end
    if cur.skipBtn then
      Widgets.SafeClearPoints(cur.skipBtn)
      Widgets.SafeSetPoint(cur.skipBtn, "RIGHT", cur.primaryBtn, "LEFT", -6, 0)
      Widgets.SafeShow(cur.skipBtn, vm.currentAction.hasAction)
    end
    if cur.unpinBtn then
      Widgets.SafeClearPoints(cur.unpinBtn)
      Widgets.SafeSetPoint(cur.unpinBtn, "RIGHT", vm.currentAction.hasAction and cur.skipBtn or cur.primaryBtn, "LEFT", -6, 0)
      Widgets.SafeShow(cur.unpinBtn, vm.currentAction.isPinned)
    end
    Widgets.SafeShow(cur, true)
    y = y + curCardH + 12
  end

  local function renderQuestSection(sectionTitle, items, emptyBehavior)
    if #items == 0 and emptyBehavior == "hide" then
      return
    end
    local hdr = acquirePoolItem(RivergladesUI.sectionHeaderPool, function()
      return createSectionHeader(content)
    end)
    if hdr then
      Widgets.SafeClearPoints(hdr)
      Widgets.SafeSetPoint(hdr, "TOPLEFT", content, "TOPLEFT", 0, -y)
      Widgets.SafeSetSize(hdr, detailContentW, 24)
      if hdr.title then
        Theme.ApplyFont(hdr.title, "sectionTitle", "text.primary")
        hdr.title:SetText(string.format("%s (%d)", sectionTitle, #items))
      end
      Widgets.SafeShow(hdr.toggleBtn, false)
      Widgets.SafeShow(hdr, true)
      y = y + 28
    end

    for _, qvm in ipairs(items) do
      local qRow = acquirePoolItem(RivergladesUI.questRowPool, function()
        return createQuestRow(content)
      end)
      if qRow then
        Widgets.ApplyGlyph(qRow.glyphTex, qRow.glyphFallback, qvm.glyphKey, qvm.glyphColor)
        Widgets.SetSurfaceBorder(qRow, qvm.isPinned and "accent.gold" or "border.subtle", qvm.isPinned and 0.85 or 1.0)
        Widgets.SafeSetSolidColor(qRow.__fhBg, qvm.isPinned and "surface.selected" or "surface.card", 1.0)

        local rightControlsReserve = 118
        local textW = math.max(180, detailContentW - 40 - rightControlsReserve)

        local levelPrefix = qvm.questLevel and string.format("[%d%s] ", qvm.questLevel, qvm.isElite and "+" or "") or ""
        local fullTitle = levelPrefix .. qvm.title

        if qRow.titleText then
          Widgets.SafeClearPoints(qRow.titleText)
          Widgets.SafeSetPoint(qRow.titleText, "TOPLEFT", qRow, "TOPLEFT", 38, -10)
          Theme.ApplyFont(qRow.titleText, "body", "text.primary")
        end
        local tH = Theme.MeasureWrappedHeight(qRow.titleText, fullTitle, textW, "body", 18, 0)

        if qRow.subText then
          Widgets.SafeClearPoints(qRow.subText)
          Widgets.SafeSetPoint(qRow.subText, "TOPLEFT", qRow, "TOPLEFT", 38, -(10 + tH + 3))
          Theme.ApplyFont(qRow.subText, "dense", "text.secondary")
        end
        local sH = Theme.MeasureWrappedHeight(qRow.subText, qvm.subtitle, textW, "dense", 16, 0)

        -- Optional inline badges row (Pinned / Elite / Group / Estimated / User decision)
        local badgeY = 10 + tH + 3 + sH + 4
        local badgeX = 38
        local anyBadge = false
        local function addRowBadge(txt, tok, glyph, goldOutline, tipTitle, tipLines)
          local b = acquirePoolItem(RivergladesUI.badgePool, function()
            return Widgets.CreateBadge(content)
          end)
          if b then
            if type(b.SetParent) == "function" then pcall(b.SetParent, b, qRow) end
            local bw = b:Configure(txt, tok, glyph, goldOutline, tipTitle, tipLines)
            Widgets.SafeClearPoints(b)
            Widgets.SafeSetPoint(b, "TOPLEFT", qRow, "TOPLEFT", badgeX, -badgeY)
            badgeX = badgeX + bw + 6
            anyBadge = true
          end
        end

        if qvm.isPinned then
          addRowBadge("Focused", "accent.gold", "focus", true, "Manual Focus Active", { "Arrow and World Map highlight are pinned to this step." })
        end
        if qvm.isElite then
          addRowBadge("Elite", "status.warning", "elite", false)
        end
        if qvm.isGroup then
          addRowBadge("Group", "status.reserved", nil, false)
        end
        if qvm.isEstimated then
          addRowBadge("Estimated coords", "text.muted", "info", false, "Estimated Coordinates", { "Patrol or community spawn center without a pinned DB digest." })
        end
        if qvm.userDecision == "user_confirmed_incomplete" then
          addRowBadge("User marked incomplete", "status.reserved", "check", false, "User History Assertion", { "You marked this pre-install title quest as not yet completed." })
        end
        if qvm.isSkipped then
          addRowBadge("Skipped", "status.warning", nil, false)
        end

        local headerBlockH = math.max(QUEST_ROW_MIN_HEIGHT, 10 + tH + 3 + sH + (anyBadge and 24 or 0) + 10)

        -- Controls on right of row header
        local aid = qvm.actionID
        if qRow.expandBtn then
          qRow.expandBtn:SetGlyph(qvm.isExpanded and "chevron_down" or "chevron_right", "text.secondary")
          Widgets.SafeClearPoints(qRow.expandBtn)
          Widgets.SafeSetPoint(qRow.expandBtn, "TOPRIGHT", qRow, "TOPRIGHT", -10, -14)
          qRow.expandBtn:SetOnClick(function()
            RivergladesUI.Dispatch("TOGGLE_ACTION_EXPANDED", { actionID = aid })
          end)
          Widgets.SafeShow(qRow.expandBtn, true)
        end

        if qRow.focusBtn then
          Widgets.SafeClearPoints(qRow.focusBtn)
          Widgets.SafeSetPoint(qRow.focusBtn, "RIGHT", qRow.expandBtn, "LEFT", -6, 0)
          if qvm.isPinned then
            qRow.focusBtn:SetLabel("Unpin")
            qRow.focusBtn:SetOnClick(function()
              RivergladesUI.Dispatch("UNPIN_ACTION")
            end)
          else
            qRow.focusBtn:SetLabel("Focus")
            qRow.focusBtn:SetOnClick(function()
              RivergladesUI.Dispatch("FOCUS_ACTION", { actionID = aid })
            end)
          end
          Widgets.SafeShow(qRow.focusBtn, qvm.state == "available")
        end

        local totalRowH = headerBlockH
        if qvm.isExpanded and qRow.detailBox then
          local detailLines = {
            "Prerequisites: " .. tostring(qvm.prereqText or "None"),
            "Provenance: " .. tostring(qvm.provenanceLabel or "Verified"),
          }
          if qvm.subLocationSummary then
            table.insert(detailLines, "Sub-locations: " .. qvm.subLocationSummary)
          end
          if qvm.note ~= "" then
            table.insert(detailLines, "Notes: " .. qvm.note)
          end
          local detailJoined = table.concat(detailLines, "\n")
          local innerW = math.max(160, detailContentW - 24 - 116)
          if qRow.detailText then
            Widgets.SafeClearPoints(qRow.detailText)
            Widgets.SafeSetPoint(qRow.detailText, "TOPLEFT", qRow.detailBox, "TOPLEFT", 10, -8)
            Theme.ApplyFont(qRow.detailText, "dense", "text.secondary")
          end
          local dTextH = Theme.MeasureWrappedHeight(qRow.detailText, detailJoined, innerW, "dense", 32, 0)
          local dBoxH = math.max(44, dTextH + 16)
          Widgets.SafeClearPoints(qRow.detailBox)
          Widgets.SafeSetPoint(qRow.detailBox, "TOPLEFT", qRow, "TOPLEFT", 10, -headerBlockH)
          Widgets.SafeSetSize(qRow.detailBox, detailContentW - 20, dBoxH)

          if qRow.skipBtn then
            qRow.skipBtn:SetLabel(qvm.isSkipped and "Unskip step" or "Skip step")
            Widgets.SafeClearPoints(qRow.skipBtn)
            Widgets.SafeSetPoint(qRow.skipBtn, "BOTTOMRIGHT", qRow.detailBox, "BOTTOMRIGHT", -8, 8)
            qRow.skipBtn:SetOnClick(function()
              RivergladesUI.Dispatch("TOGGLE_SKIP_ACTION", { actionID = aid })
            end)
            Widgets.SafeShow(qRow.skipBtn, true)
          end
          Widgets.SafeShow(qRow.detailBox, true)
          totalRowH = headerBlockH + dBoxH + 8
        elseif qRow.detailBox then
          Widgets.SafeShow(qRow.detailBox, false)
        end

        Widgets.SafeClearPoints(qRow)
        Widgets.SafeSetPoint(qRow, "TOPLEFT", content, "TOPLEFT", 0, -y)
        Widgets.SafeSetSize(qRow, detailContentW, totalRowH)
        Widgets.SafeShow(qRow, true)

        table.insert(rowReports, {
          actionID = qvm.actionID,
          height = totalRowH,
          headerHeight = headerBlockH,
          width = detailContentW,
          textWidth = textW,
        })
        y = y + totalRowH + 8
      end
    end
    y = y + 4
  end

  -- Sections (2), (3), (4) in Astra's exact order
  renderQuestSection("Ready Turn-Ins", vm.readyTurnIns, "hide")
  renderQuestSection("Active Steps & Objectives", vm.activeObjectives, "hide")
  renderQuestSection("Available Quests", vm.availablePickups, "hide")

  -- Section (5): Unresolved Pre-Install History & User-Confirmed Assertions
  local unresolvedTotal = #vm.unresolvedItems + #vm.userDecisions
  if unresolvedTotal > 0 then
    local uHdr = acquirePoolItem(RivergladesUI.sectionHeaderPool, function()
      return createSectionHeader(content)
    end)
    if uHdr then
      Widgets.SafeClearPoints(uHdr)
      Widgets.SafeSetPoint(uHdr, "TOPLEFT", content, "TOPLEFT", 0, -y)
      Widgets.SafeSetSize(uHdr, detailContentW, 26)
      if uHdr.title then
        Theme.ApplyFont(uHdr.title, "sectionTitle", (#vm.unresolvedItems > 0) and "status.warning" or "text.secondary")
        uHdr.title:SetText(string.format("Pre-Install Quest History (%d unresolved · %d user confirmed)", #vm.unresolvedItems, #vm.userDecisions))
      end
      if uHdr.toggleBtn then
        uHdr.toggleBtn:SetLabel(vm.unresolvedExpanded and "Collapse" or "Review")
        uHdr.toggleBtn:SetOnClick(function()
          RivergladesUI.Dispatch("TOGGLE_UNRESOLVED_SECTION")
        end)
        Widgets.SafeShow(uHdr.toggleBtn, true)
      end
      Widgets.SafeShow(uHdr, true)
      y = y + 30
    end

    if vm.unresolvedExpanded then
      for _, uvm in ipairs(vm.unresolvedItems) do
        local uCard = acquirePoolItem(RivergladesUI.unresolvedRowPool, function()
          return createUnresolvedRow(content)
        end)
        if uCard then
          local textW = math.max(200, detailContentW - 48)
          if uCard.titleText then
            Widgets.SafeClearPoints(uCard.titleText)
            Widgets.SafeSetPoint(uCard.titleText, "TOPLEFT", uCard, "TOPLEFT", 36, -10)
            Theme.ApplyFont(uCard.titleText, "body", "text.primary")
          end
          local tH = Theme.MeasureWrappedHeight(uCard.titleText, uvm.title .. " · " .. uvm.subtitle, textW, "body", 18, 0)

          local promptStr = "ForeverHub cannot determine whether you completed this before installation."
          if uCard.promptText then
            Widgets.SafeClearPoints(uCard.promptText)
            Widgets.SafeSetPoint(uCard.promptText, "TOPLEFT", uCard, "TOPLEFT", 36, -(10 + tH + 3))
            Theme.ApplyFont(uCard.promptText, "dense", "text.secondary")
          end
          local pH = Theme.MeasureWrappedHeight(uCard.promptText, promptStr, textW, "dense", 16, 0)

          local btnY = -(10 + tH + 3 + pH + 8)
          local qKey = uvm.questKey
          if uCard.completedBtn then
            Widgets.SafeClearPoints(uCard.completedBtn)
            Widgets.SafeSetPoint(uCard.completedBtn, "TOPLEFT", uCard, "TOPLEFT", 36, btnY)
            uCard.completedBtn:SetOnClick(function()
              RivergladesUI.Dispatch("CONFIRM_COMPLETED", { questKey = qKey })
            end)
            Widgets.BindTooltip(
              uCard.completedBtn,
              "Mark Completed (User Confirmed)",
              { "Records a user assertion ('User confirmed', not API verified) so ForeverHub skips this pickup. Undoable anytime." }
            )
            Widgets.SafeShow(uCard.completedBtn, true)
          end
          if uCard.incompleteBtn then
            Widgets.SafeClearPoints(uCard.incompleteBtn)
            Widgets.SafeSetPoint(uCard.incompleteBtn, "LEFT", uCard.completedBtn, "RIGHT", 8, 0)
            uCard.incompleteBtn:SetOnClick(function()
              RivergladesUI.Dispatch("CONFIRM_INCOMPLETE", { questKey = qKey })
            end)
            Widgets.BindTooltip(
              uCard.incompleteBtn,
              "Mark Not Completed",
              { "Unlocks automatic routing to pick up this quest. Undoable anytime." }
            )
            Widgets.SafeShow(uCard.incompleteBtn, true)
          end
          if uCard.leaveBtn then
            Widgets.SafeClearPoints(uCard.leaveBtn)
            Widgets.SafeSetPoint(uCard.leaveBtn, "LEFT", uCard.incompleteBtn, "RIGHT", 8, 0)
            uCard.leaveBtn:SetOnClick(function()
              RivergladesUI.Dispatch("LEAVE_UNRESOLVED", { questKey = qKey })
            end)
            Widgets.SafeShow(uCard.leaveBtn, true)
          end

          local uCardH = math.max(82, 10 + tH + 3 + pH + 8 + 24 + 10)
          Widgets.SafeClearPoints(uCard)
          Widgets.SafeSetPoint(uCard, "TOPLEFT", content, "TOPLEFT", 0, -y)
          Widgets.SafeSetSize(uCard, detailContentW, uCardH)
          Widgets.SafeShow(uCard, true)
          y = y + uCardH + 8
        end
      end

      -- Render User-Confirmed History Assertions with explicit "User confirmed" badge & Undo!
      for _, dec in ipairs(vm.userDecisions) do
        local dRow = acquirePoolItem(RivergladesUI.decisionRowPool, function()
          return createDecisionRow(content)
        end)
        if dRow then
          Widgets.SafeClearPoints(dRow)
          Widgets.SafeSetPoint(dRow, "TOPLEFT", content, "TOPLEFT", 0, -y)
          Widgets.SafeSetSize(dRow, detailContentW, 36)

          if dRow.titleText then
            Theme.ApplyFont(dRow.titleText, "dense", "text.primary")
            dRow.titleText:SetText(tostring(dec.questTitle))
          end
          if dRow.badge then
            local badgeLabel = (dec.decision == "user_confirmed_completed")
              and "User confirmed · Completed"
              or "User confirmed · Not completed"
            local tok = (dec.decision == "user_confirmed_completed") and "status.reserved" or "status.buy"
            dRow.badge:Configure(
              badgeLabel,
              tok,
              "check",
              false,
              "User-Confirmed Pre-Install History",
              { "Asserted manually by player — distinct from live server quest API verification. Click Undo to restore unresolved state." }
            )
            Widgets.SafeClearPoints(dRow.badge)
            Widgets.SafeSetPoint(dRow.badge, "RIGHT", dRow.undoBtn, "LEFT", -8, 0)
          end
          if dRow.undoBtn then
            local qKey = dec.questKey
            dRow.undoBtn:SetOnClick(function()
              RivergladesUI.Dispatch("UNDO_HISTORY_DECISION", { questKey = qKey })
            end)
            Widgets.SafeShow(dRow.undoBtn, true)
          end
          Widgets.SafeShow(dRow, true)
          y = y + 40
        end
      end
    end
  end

  -- Collapsed Blocked / Skipped Section
  if #vm.blockedOrSkipped > 0 then
    local bHdr = acquirePoolItem(RivergladesUI.sectionHeaderPool, function()
      return createSectionHeader(content)
    end)
    if bHdr then
      Widgets.SafeClearPoints(bHdr)
      Widgets.SafeSetPoint(bHdr, "TOPLEFT", content, "TOPLEFT", 0, -y)
      Widgets.SafeSetSize(bHdr, detailContentW, 26)
      if bHdr.title then
        Theme.ApplyFont(bHdr.title, "sectionTitle", "text.muted")
        bHdr.title:SetText(string.format("Locked Chain & Skipped Steps (%d)", #vm.blockedOrSkipped))
      end
      if bHdr.toggleBtn then
        bHdr.toggleBtn:SetLabel(vm.blockedExpanded and "Collapse" or "Inspect")
        bHdr.toggleBtn:SetOnClick(function()
          RivergladesUI.Dispatch("TOGGLE_BLOCKED_SECTION")
        end)
        Widgets.SafeShow(bHdr.toggleBtn, true)
      end
      Widgets.SafeShow(bHdr, true)
      y = y + 30
    end
    if vm.blockedExpanded then
      renderQuestSection("Locked / Skipped", vm.blockedOrSkipped, "hide")
    end
  end

  RivergladesUI.detailViewport:SetDimensions(detailViewportW, detailViewportH, math.max(detailViewportH, y + 12))
  RivergladesUI.detailViewport:SetScrollOffset(uiState.rivergladesView.scrollOffset or 0, true)

  local report = {
    isCompact = compact,
    viewportWidth = vw,
    viewportHeight = vh,
    hubSidebarWidth = compact and 0 or HUB_SIDEBAR_WIDTH,
    columnGap = compact and 0 or COLUMN_GAP,
    detailContentWidth = detailContentW,
    hubs = hubReports,
    rows = rowReports,
    contentHeight = y,
  }
  RivergladesUI.lastLayoutReport = report
  return report
end

function RivergladesUI.Refresh()
  RivergladesUI.EnsureHost()
  if ns.UI.Workspace and ns.UI.Workspace.IsShown and ns.UI.Workspace.IsShown() then
    local st = ns.State.GetWorkspaceUIState()
    if st.activeTab == "riverglades" then
      ns.UI.Workspace.Refresh()
    end
  end
end

function RivergladesUI.RefreshIfShown()
  RivergladesUI.Refresh()
end

function RivergladesUI.Toggle()
  RivergladesUI.EnsureHost()
  if ns.UI.Workspace and ns.UI.Workspace.Toggle then
    ns.UI.Workspace.Toggle("riverglades")
  end
end

if ns.UI.Workspace and ns.UI.Workspace.RegisterTabRenderer then
  ns.UI.Workspace.RegisterTabRenderer("riverglades", {
    Refresh = function(_, contentWidth, contentHeight, isCompact)
      RivergladesUI.RenderInHost(contentWidth, contentHeight, isCompact)
    end,
  })
end

return RivergladesUI
