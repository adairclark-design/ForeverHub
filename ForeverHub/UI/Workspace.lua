local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.UI = ns.UI or {}

local Theme = ns.UI.Theme
local Widgets = ns.UI.Widgets

local Workspace = {}
ns.UI.Workspace = Workspace

Workspace.frame = nil
Workspace.tabRenderers = {}
Workspace.TEXT_SCALE_STEPS = { 0.90, 1.00, 1.15, 1.25 }

function Workspace.IsShown()
  if Workspace.frame and type(Workspace.frame.IsShown) == "function" then
    local ok, shown = pcall(Workspace.frame.IsShown, Workspace.frame)
    return ok and shown == true or false
  end
  return false
end

function Workspace.RegisterTabRenderer(tabKey, rendererTable)
  if type(tabKey) == "string" and type(rendererTable) == "table" then
    Workspace.tabRenderers[tabKey] = rendererTable
  end
end

function Workspace.SetTabBadge(tabKey, badgeStr, statusToken)
  if Workspace.frame and Workspace.frame.tabBar and type(Workspace.frame.tabBar.SetTabCountBadge) == "function" then
    Workspace.frame.tabBar:SetTabCountBadge(tabKey, badgeStr or "", statusToken)
  end
end

local function ensureTabRendererInitialized(tabKey)
  if Workspace.tabRenderers[tabKey] then
    return Workspace.tabRenderers[tabKey]
  end
  if tabKey == "crates" and ns.UI and ns.UI.Crates and type(ns.UI.Crates.EnsureInitialized) == "function" then
    ns.UI.Crates.EnsureInitialized()
  elseif tabKey == "riverglades" and ns.UI and ns.UI.Riverglades and type(ns.UI.Riverglades.EnsureHost) == "function" then
    ns.UI.Riverglades.EnsureHost()
  elseif tabKey == "gold" and ns.UI and ns.UI.GoldFarms and type(ns.UI.GoldFarms.EnsureHost) == "function" then
    ns.UI.GoldFarms.EnsureHost()
  end
  return Workspace.tabRenderers[tabKey]
end

function Workspace.GetDimensions()
  local uiState = (ns.State and ns.State.GetWorkspaceUIState and ns.State.GetWorkspaceUIState()) or {}
  local w = tonumber(uiState.width) or Theme.METRICS.workspaceDefaultWidth
  local h = tonumber(uiState.height) or Theme.METRICS.workspaceDefaultHeight
  if Workspace.frame and type(Workspace.frame.GetWidth) == "function" then
    local okW, liveW = pcall(Workspace.frame.GetWidth, Workspace.frame)
    if okW and type(liveW) == "number" and liveW >= Theme.METRICS.workspaceMinWidth then
      w = math.floor(liveW + 0.5)
    end
  end
  if Workspace.frame and type(Workspace.frame.GetHeight) == "function" then
    local okH, liveH = pcall(Workspace.frame.GetHeight, Workspace.frame)
    if okH and type(liveH) == "number" and liveH >= Theme.METRICS.workspaceMinHeight then
      h = math.floor(liveH + 0.5)
    end
  end
  return math.max(Theme.METRICS.workspaceMinWidth, w), math.max(Theme.METRICS.workspaceMinHeight, h)
end

function Workspace.IsCompactLayout(explicitWidth)
  local uiState = (ns.State and ns.State.GetWorkspaceUIState and ns.State.GetWorkspaceUIState()) or {}
  if type(uiState.compactOverride) == "boolean" then
    return uiState.compactOverride
  end
  local w = tonumber(explicitWidth)
  if not w then
    w = Workspace.GetDimensions()
  end
  return w < Theme.METRICS.compactThresholdWidth
end

local function clampDimensionsToScreen(w, h)
  local maxW, maxH = 1600, 1200
  if type(_G.UIParent) == "table" then
    if type(_G.UIParent.GetWidth) == "function" then
      local okW, pw = pcall(_G.UIParent.GetWidth, _G.UIParent)
      if okW and type(pw) == "number" and pw > 800 then
        maxW = math.max(Theme.METRICS.workspaceMinWidth, math.floor(pw - 32))
      end
    end
    if type(_G.UIParent.GetHeight) == "function" then
      local okH, ph = pcall(_G.UIParent.GetHeight, _G.UIParent)
      if okH and type(ph) == "number" and ph > 560 then
        maxH = math.max(Theme.METRICS.workspaceMinHeight, math.floor(ph - 32))
      end
    end
  end
  local cw = math.max(Theme.METRICS.workspaceMinWidth, math.min(maxW, math.floor((tonumber(w) or 960) + 0.5)))
  local ch = math.max(Theme.METRICS.workspaceMinHeight, math.min(maxH, math.floor((tonumber(h) or 640) + 0.5)))
  return cw, ch
end

local function saveFrameAnchor(f)
  if not f or not (ns.State and ns.State.GetWorkspaceUIState) then
    return
  end
  local uiState = ns.State.GetWorkspaceUIState()
  if type(f.GetPoint) == "function" then
    local ok, pt, _, relPt, ox, oy = pcall(f.GetPoint, f, 1)
    if ok and type(pt) == "string" then
      uiState.point = pt
      uiState.relativePoint = type(relPt) == "string" and relPt or pt
      uiState.offsetX = math.floor((tonumber(ox) or 0) + 0.5)
      uiState.offsetY = math.floor((tonumber(oy) or 0) + 0.5)
    end
  end
end

-- ============================================================================
-- About / Diagnostics Drawer (replaces noisy provenance footer in gameplay view)
-- ============================================================================

local function createDiagnosticsDrawer(parent)
  local drawer = Widgets.CreatePanel(parent, "surface.elevated", "border.default")
  if not drawer then
    return nil
  end
  local UPDATE_PORTAL_URL = "https://foreverhub.cc/addon"
  Widgets.SafeSetSize(drawer, 456, 336)
  Widgets.SafeSetPoint(drawer, "TOPRIGHT", parent, "TOPRIGHT", -16, -46)
  if type(drawer.SetFrameLevel) == "function" and type(parent.GetFrameLevel) == "function" then
    pcall(drawer.SetFrameLevel, drawer, (parent:GetFrameLevel() or 10) + 30)
  end
  if type(drawer.EnableMouse) == "function" then
    pcall(drawer.EnableMouse, drawer, true)
  end

  local hdr = Widgets.SafeCreateFontString(drawer, "sectionTitle", "accent.gold")
  if hdr then
    Widgets.SafeSetPoint(hdr, "TOPLEFT", drawer, "TOPLEFT", 14, -12)
    if type(hdr.SetText) == "function" then
      hdr:SetText("About, Changelog & Updates")
    end
  end

  local closeBtn = Widgets.CreateIconButton(drawer, "close", "Close diagnostics", nil, 24, 12)
  if closeBtn then
    Widgets.SafeSetPoint(closeBtn, "TOPRIGHT", drawer, "TOPRIGHT", -8, -8)
    closeBtn:SetOnClick(function()
      Widgets.SafeShow(drawer, false)
    end)
  end

  local body = Widgets.SafeCreateFontString(drawer, "dense", "text.secondary")
  if body then
    Widgets.SafeSetPoint(body, "TOPLEFT", drawer, "TOPLEFT", 14, -38)
    Widgets.SafeSetPoint(body, "TOPRIGHT", drawer, "TOPRIGHT", -14, -38)
    if type(body.SetJustifyH) == "function" then pcall(body.SetJustifyH, body, "LEFT") end
    if type(body.SetWordWrap) == "function" then pcall(body.SetWordWrap, body, true) end
  end
  drawer.body = body

  local urlLabel = Widgets.SafeCreateFontString(drawer, "dense", "accent.gold")
  if urlLabel then
    Widgets.SafeSetPoint(urlLabel, "BOTTOMLEFT", drawer, "BOTTOMLEFT", 14, 74)
    if type(urlLabel.SetText) == "function" then
      urlLabel:SetText("Check website for updates (offline addon — copy URL):")
    end
  end
  drawer.urlLabel = urlLabel

  local okBox, urlBox = pcall(_G.CreateFrame, "EditBox", nil, drawer)
  if okBox and urlBox then
    Widgets.SafeSetSize(urlBox, 428, 24)
    Widgets.SafeSetPoint(urlBox, "BOTTOMLEFT", drawer, "BOTTOMLEFT", 14, 46)
    Widgets.ApplySurface(urlBox, "surface.inset", "border.subtle", 1.0)
    if type(urlBox.SetAutoFocus) == "function" then pcall(urlBox.SetAutoFocus, urlBox, false) end
    if _G.GameFontHighlightSmall and type(urlBox.SetFontObject) == "function" then
      pcall(urlBox.SetFontObject, urlBox, _G.GameFontHighlightSmall)
    end
    if type(urlBox.SetTextInsets) == "function" then pcall(urlBox.SetTextInsets, urlBox, 8, 8, 2, 2) end
    if type(urlBox.SetText) == "function" then pcall(urlBox.SetText, urlBox, UPDATE_PORTAL_URL) end
    if type(urlBox.SetScript) == "function" then
      urlBox:SetScript("OnEscapePressed", function(eb)
        if type(eb.ClearFocus) == "function" then pcall(eb.ClearFocus, eb) end
      end)
      urlBox:SetScript("OnEditFocusGained", function(eb)
        if type(eb.SetText) == "function" then pcall(eb.SetText, eb, UPDATE_PORTAL_URL) end
        if type(eb.HighlightText) == "function" then pcall(eb.HighlightText, eb) end
      end)
      urlBox:SetScript("OnTextChanged", function(eb, userInput)
        if userInput and type(eb.SetText) == "function" then
          pcall(eb.SetText, eb, UPDATE_PORTAL_URL)
          if type(eb.HighlightText) == "function" then pcall(eb.HighlightText, eb) end
        end
      end)
    end
    drawer.updateUrlBox = urlBox
  end

  local doctorBtn = Widgets.CreateSecondaryButton(drawer, 108, "Print Doctor", 26)
  if doctorBtn then
    Widgets.SafeSetPoint(doctorBtn, "BOTTOMLEFT", drawer, "BOTTOMLEFT", 14, 12)
    doctorBtn:SetOnClick(function()
      if ns.Events and ns.Events.RunDoctor then
        ns.Events.RunDoctor()
      end
    end)
  end

  local selfTestBtn = Widgets.CreateGhostButton(drawer, 118, "Run Self-Tests", 26)
  if selfTestBtn then
    Widgets.SafeSetPoint(selfTestBtn, "LEFT", doctorBtn, "RIGHT", 6, 0)
    selfTestBtn:SetOnClick(function()
      if ns.Events and ns.Events.RunSelfTestCommand then
        ns.Events.RunSelfTestCommand()
      end
    end)
  end

  local updateCheckBtn = Widgets.CreateSecondaryButton(drawer, 190, "Check website for updates", 26)
  if updateCheckBtn then
    Widgets.SafeSetPoint(updateCheckBtn, "LEFT", selfTestBtn, "RIGHT", 6, 0)
    updateCheckBtn:SetOnClick(function()
      if drawer.updateUrlBox then
        if type(drawer.updateUrlBox.SetText) == "function" then
          pcall(drawer.updateUrlBox.SetText, drawer.updateUrlBox, UPDATE_PORTAL_URL)
        end
        if type(drawer.updateUrlBox.SetFocus) == "function" then
          pcall(drawer.updateUrlBox.SetFocus, drawer.updateUrlBox)
        end
        if type(drawer.updateUrlBox.HighlightText) == "function" then
          pcall(drawer.updateUrlBox.HighlightText, drawer.updateUrlBox)
        end
      end
      if ns.Compat and type(ns.Compat.Print) == "function" then
        ns.Compat.Print(string.format("Installed: v%s — Check website for updates: %s", tostring(ns.version or "0.8.8"), UPDATE_PORTAL_URL))
      end
    end)
    drawer.updateCheckBtn = updateCheckBtn
  end

  function drawer:RefreshDiagnostics()
    if not self.body or type(self.body.SetText) ~= "function" then
      return
    end
    Theme.ApplyFont(self.body, "dense", "text.secondary")
    local meta = (ns.Data and ns.Data.meta) or {}
    local rgMeta = (ns.RivergladesData and ns.RivergladesData.meta) or {}
    local buildVer, buildNum, _, tocNum = "1.60.1", "70862", "", "16001"
    if type(_G.GetBuildInfo) == "function" then
      local v, b, _, t = _G.GetBuildInfo()
      buildVer = tostring(v or buildVer)
      buildNum = tostring(b or buildNum)
      tocNum = tostring(t or tocNum)
    end
    local hasAuc = (ns.Providers and ns.Providers.Auctionator and ns.Providers.Auctionator.IsAvailable and ns.Providers.Auctionator.IsAvailable()) or false
    local invName = (ns.Providers and ns.Providers.Syndicator and ns.Providers.Syndicator.GetActiveBackendName and ns.Providers.Syndicator.GetActiveBackendName()) or "None"
    local curVer = tostring(ns.version or "0.8.8")
    local lines = {
      string.format("Installed: v%s  ·  Client %s (Build %s, TOC %s)", curVer, buildVer, buildNum, tocNum),
      string.format("Crates: %s (%s) · Riverglades Rev %s (%s)", tostring(meta.corpusRevisionID or "unknown"), string.sub(tostring(meta.compiledContentSha256 or "unknown"), 1, 8), tostring(rgMeta.datasetRevision or "?"), string.sub(tostring(rgMeta.compiledContentSha256 or "unknown"), 1, 8)),
      string.format("Providers: Auctionator=%s · AccountInv=%s", hasAuc and "OK" or "Missing", tostring(invName)),
      "",
      string.format("Changelog (v%s):", curVer),
      "• Compact 240x48 Tracker HUD (Arrow, Quest Name, Distance/Status, ...)",
      "• Mapped all 124 playable Riverglades & Krol'dok quests (330 steps)",
      "• Fixed Snargl's Snout & accepted Elite quest pins on World Map",
      "• Added Search Area badges + live auto-snap for unpinned spawns",
    }
    self.body:SetText(table.concat(lines, "\n"))
    if self.updateUrlBox and type(self.updateUrlBox.SetText) == "function" then
      pcall(self.updateUrlBox.SetText, self.updateUrlBox, UPDATE_PORTAL_URL)
    end
  end

  Widgets.SafeShow(drawer, false)
  return drawer
end

-- ============================================================================
-- Main Workspace Frame (`ForeverHubWorkspaceFrame`)
-- ============================================================================

function Workspace.EnsureCreated()
  if Workspace.frame then
    return Workspace.frame
  end
  if type(_G.CreateFrame) ~= "function" then
    return nil
  end

  local uiState = (ns.State and ns.State.GetWorkspaceUIState and ns.State.GetWorkspaceUIState()) or {}
  local initW, initH = clampDimensionsToScreen(
    uiState.width or Theme.METRICS.workspaceDefaultWidth,
    uiState.height or Theme.METRICS.workspaceDefaultHeight
  )

  local ok, f = pcall(_G.CreateFrame, "Frame", "ForeverHubWorkspaceFrame", _G.UIParent)
  if not ok or not f then
    return nil
  end
  Workspace.frame = f
  if not _G.ForeverHubCratesFrame then
    _G.ForeverHubCratesFrame = f
  end

  Widgets.SafeSetSize(f, initW, initH)
  Widgets.SafeClearPoints(f)
  Widgets.SafeSetPoint(
    f,
    uiState.point or "CENTER",
    _G.UIParent,
    uiState.relativePoint or "CENTER",
    tonumber(uiState.offsetX) or 0,
    tonumber(uiState.offsetY) or 0
  )
  Widgets.ApplySurface(f, "surface.window", "border.default", 1.0)

  if type(f.SetFrameStrata) == "function" then
    pcall(f.SetFrameStrata, f, "HIGH")
  end
  if type(f.SetToplevel) == "function" then
    pcall(f.SetToplevel, f, true)
  end
  if type(f.SetClampedToScreen) == "function" then
    pcall(f.SetClampedToScreen, f, true)
  end
  if type(f.SetMovable) == "function" then
    pcall(f.SetMovable, f, true)
  end
  if type(f.SetResizable) == "function" then
    pcall(f.SetResizable, f, true)
  end
  if type(f.SetResizeBounds) == "function" then
    pcall(f.SetResizeBounds, f, Theme.METRICS.workspaceMinWidth, Theme.METRICS.workspaceMinHeight, 1600, 1200)
  elseif type(f.SetMinResize) == "function" then
    pcall(f.SetMinResize, f, Theme.METRICS.workspaceMinWidth, Theme.METRICS.workspaceMinHeight)
  end
  if type(f.EnableMouse) == "function" then
    pcall(f.EnableMouse, f, true)
  end

  if type(_G.UISpecialFrames) == "table" then
    local found = false
    for _, n in ipairs(_G.UISpecialFrames) do
      if n == "ForeverHubWorkspaceFrame" then
        found = true
        break
      end
    end
    if not found then
      table.insert(_G.UISpecialFrames, "ForeverHubWorkspaceFrame")
    end
  end

  -- 1. Title Bar (Y = 0, H = 44)
  local titleBar = Widgets.CreatePanel(f, "surface.card", nil)
  if titleBar then
    Widgets.SafeSetPoint(titleBar, "TOPLEFT", f, "TOPLEFT", 1, -1)
    Widgets.SafeSetPoint(titleBar, "TOPRIGHT", f, "TOPRIGHT", -1, -1)
    Widgets.SafeSetHeight(titleBar, Theme.METRICS.titleBarHeight)
    if type(titleBar.EnableMouse) == "function" then pcall(titleBar.EnableMouse, titleBar, true) end
    if type(titleBar.RegisterForDrag) == "function" then pcall(titleBar.RegisterForDrag, titleBar, "LeftButton") end
    if type(titleBar.SetScript) == "function" then
      titleBar:SetScript("OnDragStart", function()
        if f.StartMoving then pcall(f.StartMoving, f) end
      end)
      titleBar:SetScript("OnDragStop", function()
        if f.StopMovingOrSizing then pcall(f.StopMovingOrSizing, f) end
        saveFrameAnchor(f)
      end)
    end
  end
  f.titleBar = titleBar

  local brandAccent = titleBar and Widgets.SafeCreateTexture(titleBar, "ARTWORK", 2) or nil
  if brandAccent then
    Widgets.SafeSetPoint(brandAccent, "LEFT", titleBar, "LEFT", Theme.METRICS.workspacePadding, 0)
    Widgets.SafeSetSize(brandAccent, 3, 20)
    Widgets.SafeSetSolidColor(brandAccent, "accent.gold", 1.0)
  end

  local titleText = Widgets.SafeCreateFontString(titleBar or f, "windowTitle", "text.primary")
  if titleText then
    Widgets.SafeSetPoint(titleText, "LEFT", titleBar or f, "LEFT", Theme.METRICS.workspacePadding + 10, 0)
    if type(titleText.SetText) == "function" then
      titleText:SetText("ForeverHub")
    end
  end
  f.titleText = titleText

  local subtitleText = Widgets.SafeCreateFontString(titleBar or f, "dense", "text.muted")
  if subtitleText then
    Widgets.SafeSetPoint(subtitleText, "LEFT", titleText or titleBar or f, "RIGHT", 10, -1)
    if type(subtitleText.SetText) == "function" then
      subtitleText:SetText(string.format("Planning & Route Workspace  ·  Installed: v%s", tostring(ns.version or "0.8.8")))
    end
  end
  f.subtitleText = subtitleText

  -- Header Right Controls: Close, About/Diagnostics, Compact Mode, Text Scale
  local closeBtn = Widgets.CreateIconButton(titleBar or f, "close", "Close ForeverHub", { "Press Escape or /fh to toggle." }, 28, 14)
  if closeBtn then
    Widgets.SafeSetPoint(closeBtn, "RIGHT", titleBar or f, "RIGHT", -12, 0)
  end
  if closeBtn then
    closeBtn:SetOnClick(function()
      Workspace.Hide()
    end)
  end
  f.closeBtn = closeBtn

  local infoBtn = Widgets.CreateIconButton(
    titleBar or f,
    "info",
    "About, Changelog & Updates",
    { "Inspect installed version, local changelog, update URL, and diagnostics." },
    28,
    15
  )
  if infoBtn then
    Widgets.SafeSetPoint(infoBtn, "RIGHT", closeBtn, "LEFT", -6, 0)
  end
  f.infoBtn = infoBtn

  local compactBtn = Widgets.CreateGhostButton(titleBar or f, 78, "Layout: Auto", 24)
  if compactBtn then
    Widgets.SafeSetPoint(compactBtn, "RIGHT", infoBtn, "LEFT", -6, 0)
    Widgets.BindTooltip(
      compactBtn,
      "Responsive Density",
      { "Switches between Auto (<900px compact), Compact, and Standard column layouts." }
    )
    compactBtn:SetOnClick(function()
      local st = ns.State.GetWorkspaceUIState()
      if st.compactOverride == nil then
        st.compactOverride = true
      elseif st.compactOverride == true then
        st.compactOverride = false
      else
        st.compactOverride = nil
      end
      Workspace.Refresh()
    end)
  end
  f.compactBtn = compactBtn

  local scaleBtn = Widgets.CreateGhostButton(titleBar or f, 84, "Aa 100%", 24)
  if scaleBtn then
    Widgets.SafeSetPoint(scaleBtn, "RIGHT", compactBtn, "LEFT", -6, 0)
    Widgets.BindTooltip(
      scaleBtn,
      "Text Scale",
      { "Cycles ForeverHub typography scale (90% / 100% / 115% / 125%) without altering Blizzard UI fonts." }
    )
    scaleBtn:SetOnClick(function()
      local st = ns.State.GetWorkspaceUIState()
      local cur = tonumber(st.textScale) or 1.0
      local nextScale = 1.0
      for i, s in ipairs(Workspace.TEXT_SCALE_STEPS) do
        if math.abs(cur - s) < 0.03 then
          nextScale = Workspace.TEXT_SCALE_STEPS[(i % #Workspace.TEXT_SCALE_STEPS) + 1]
          break
        end
      end
      st.textScale = nextScale
      Theme.appliedFontScale = nil
      Theme.EnsureFontObjects()
      Workspace.Refresh()
    end)
  end
  f.scaleBtn = scaleBtn

  -- 2. Tab Bar (Y = -44, H = 36) — Riverglades featured in primary Slot #1
  local tabBar = Widgets.CreateTabBar(f, {
    {
      key = "riverglades",
      label = "Riverglades",
      width = 188,
      featured = true,
      iconGlyph = "travel",
      iconToken = "accent.gold",
      tooltipTitle = "Riverglades Route (Primary Hub)",
      tooltipLines = {
        "Inspect live Riverglades quest route progress, turn-ins, and map pin filters.",
        "Opening this tab inspects your route safely without auto-starting navigation.",
      },
    },
    {
      key = "crates",
      label = "Crates & Writs",
      width = 164,
      tooltipTitle = "Crates & Writs Planner",
      tooltipLines = { "Reservation-aware Waylaid Crate & Writ planning, bank withdrawal, and Auctionator shopping." },
    },
    {
      key = "gold",
      label = "Gold & Mount",
      width = 152,
      tooltipTitle = "Gold Farms & Mount Target",
      tooltipLines = { "Inspect Level 40 riding target shortfall and verified gold farm candidates." },
    },
  }, function(selectedKey)
    Workspace.SetActiveTab(selectedKey)
  end)
  if tabBar then
    Widgets.SafeSetPoint(tabBar, "TOPLEFT", f, "TOPLEFT", 1, -Theme.METRICS.titleBarHeight)
    Widgets.SafeSetPoint(tabBar, "TOPRIGHT", f, "TOPRIGHT", -1, -Theme.METRICS.titleBarHeight)
  end
  f.tabBar = tabBar

  -- 3. Tab Content Host Containers (Y = -80 .. Bottom)
  f.tabHosts = {}
  for _, tabKey in ipairs({ "riverglades", "crates", "gold" }) do
    local okH, host = pcall(_G.CreateFrame, "Frame", nil, f)
    if okH and host then
      Widgets.SafeSetPoint(host, "TOPLEFT", f, "TOPLEFT", 0, -(Theme.METRICS.titleBarHeight + Theme.METRICS.tabBarHeight))
      Widgets.SafeSetPoint(host, "BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
      Widgets.SafeShow(host, false)
      f.tabHosts[tabKey] = host
    end
  end

  -- 4. Diagnostics Drawer
  f.diagnosticsDrawer = createDiagnosticsDrawer(f)
  if infoBtn and f.diagnosticsDrawer then
    infoBtn:SetOnClick(function()
      local shown = (type(f.diagnosticsDrawer.IsShown) == "function" and f.diagnosticsDrawer:IsShown()) or false
      if not shown then
        f.diagnosticsDrawer:RefreshDiagnostics()
      end
      Widgets.SafeShow(f.diagnosticsDrawer, not shown)
    end)
  end

  -- 5. Bottom-Right Resize Grip
  local okGrip, grip = pcall(_G.CreateFrame, "Button", nil, f)
  if okGrip and grip then
    Widgets.SafeSetSize(grip, 16, 16)
    Widgets.SafeSetPoint(grip, "BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    if type(grip.EnableMouse) == "function" then pcall(grip.EnableMouse, grip, true) end
    local gripTex = Widgets.SafeCreateTexture(grip, "OVERLAY", 2)
    if gripTex then
      Widgets.SafeSetSize(gripTex, 12, 12)
      Widgets.SafeSetPoint(gripTex, "BOTTOMRIGHT", grip, "BOTTOMRIGHT", -1, 1)
    end
    local gripFb = Widgets.SafeCreateFontString(grip, "dense", "text.muted")
    if gripFb then
      Widgets.SafeSetPoint(gripFb, "CENTER", grip, "CENTER", 0, 0)
    end
    Widgets.ApplyGlyph(gripTex, gripFb, "chevron_down", "text.muted")
    Widgets.BindTooltip(grip, "Resize Workspace", { "Drag to resize (min 760×520; compact layout below 900 width)." })
    if type(grip.SetScript) == "function" then
      grip:SetScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" and type(f.StartSizing) == "function" then
          pcall(f.StartSizing, f, "BOTTOMRIGHT")
        end
      end)
      grip:SetScript("OnMouseUp", function()
        if type(f.StopMovingOrSizing) == "function" then
          pcall(f.StopMovingOrSizing, f)
        end
        local w, h = Workspace.GetDimensions()
        local cw, ch = clampDimensionsToScreen(w, h)
        local st = ns.State.GetWorkspaceUIState()
        st.width = cw
        st.height = ch
        Widgets.SafeSetSize(f, cw, ch)
        saveFrameAnchor(f)
        Workspace.Refresh()
      end)
    end
    f.resizeGrip = grip
  end

  if type(f.SetScript) == "function" then
    f:SetScript("OnSizeChanged", function(_, newW, newH)
      if type(newW) == "number" and type(newH) == "number" and newW >= Theme.METRICS.workspaceMinWidth then
        local st = ns.State and ns.State.GetWorkspaceUIState and ns.State.GetWorkspaceUIState()
        if st then
          st.width = math.floor(newW + 0.5)
          st.height = math.floor(math.max(Theme.METRICS.workspaceMinHeight, newH) + 0.5)
        end
        if type(f.IsShown) == "function" and f:IsShown() then
          Workspace.Refresh()
        end
      end
    end)
  end

  Widgets.SafeShow(f, false)
  return f
end

function Workspace.SetDimensions(width, height)
  local f = Workspace.EnsureCreated()
  local cw, ch = clampDimensionsToScreen(width, height)
  local st = ns.State and ns.State.GetWorkspaceUIState and ns.State.GetWorkspaceUIState()
  if st then
    st.width = cw
    st.height = ch
  end
  if f then
    Widgets.SafeSetSize(f, cw, ch)
  end
  Workspace.RefreshIfShown()
  return cw, ch
end

function Workspace.SetActiveTab(tabKey)
  if tabKey ~= "crates" and tabKey ~= "riverglades" and tabKey ~= "gold" then
    tabKey = "riverglades"
  end
  local st = ns.State and ns.State.GetWorkspaceUIState and ns.State.GetWorkspaceUIState()
  if st then
    st.activeTab = tabKey
  end
  local f = Workspace.EnsureCreated()
  if not f then
    return
  end
  if f.tabBar then
    f.tabBar:SetSelected(tabKey)
  end
  for k, host in pairs(f.tabHosts or {}) do
    Widgets.SafeShow(host, k == tabKey)
  end
  if type(f.IsShown) == "function" and f:IsShown() then
    Workspace.Refresh()
  end
end

function Workspace.Refresh()
  local f = Workspace.EnsureCreated()
  if not f or (type(f.IsShown) == "function" and not f:IsShown()) then
    return
  end

  Theme.EnsureFontObjects()
  local st = (ns.State and ns.State.GetWorkspaceUIState and ns.State.GetWorkspaceUIState()) or { activeTab = "riverglades", textScale = 1.0 }
  local activeTab = st.activeTab or "riverglades"

  if f.titleText then
    Theme.ApplyFont(f.titleText, "windowTitle", "text.primary")
  end
  if f.subtitleText then
    Theme.ApplyFont(f.subtitleText, "dense", "text.muted")
    if type(f.subtitleText.SetText) == "function" then
      f.subtitleText:SetText(string.format("Planning & Route Workspace  ·  Installed: v%s", tostring(ns.version or "0.8.8")))
    end
  end

  if f.scaleBtn then
    local pct = math.floor(((tonumber(st.textScale) or 1.0) * 100) + 0.5)
    f.scaleBtn:SetLabel(string.format("Aa %d%%", pct))
  end

  if f.compactBtn then
    local modeLabel = (st.compactOverride == true and "Compact")
      or (st.compactOverride == false and "Standard")
      or "Auto"
    f.compactBtn:SetLabel(modeLabel)
    f.compactBtn.__isSelected = (st.compactOverride ~= nil)
    f.compactBtn:RefreshVisualState()
  end

  -- Update tab count/status badges cleanly without mutating domain state
  if f.tabBar then
    if ns.UI and ns.UI.RivergladesPresenter and type(ns.UI.RivergladesPresenter.ComputeTabBadge) == "function" then
      local rgBadge, rgToken = ns.UI.RivergladesPresenter.ComputeTabBadge()
      f.tabBar:SetTabCountBadge("riverglades", rgBadge, rgToken)
    end
    local resCount = #(ns.State and ns.State.GetOrderedReservations and ns.State.GetOrderedReservations() or {})
    f.tabBar:SetTabCountBadge("crates", resCount > 0 and string.format("%d planned", resCount) or "", "status.reserved")
    f.tabBar:SetSelected(activeTab)
  end

  for k, host in pairs(f.tabHosts or {}) do
    Widgets.SafeShow(host, k == activeTab)
  end

  local w, h = Workspace.GetDimensions()
  local contentW = w - (Theme.METRICS.workspacePadding * 2)
  local contentH = h - (Theme.METRICS.titleBarHeight + Theme.METRICS.tabBarHeight)

  local renderer = ensureTabRendererInitialized(activeTab)
  if renderer and type(renderer.Refresh) == "function" then
    renderer:Refresh(contentW, contentH, Workspace.IsCompactLayout(w))
  end

  if f.diagnosticsDrawer and type(f.diagnosticsDrawer.IsShown) == "function" and f.diagnosticsDrawer:IsShown() then
    f.diagnosticsDrawer:RefreshDiagnostics()
  end
end

function Workspace.RefreshIfShown()
  if Workspace.frame and type(Workspace.frame.IsShown) == "function" and Workspace.frame:IsShown() then
    Workspace.Refresh()
  end
end

function Workspace.Show(tabKey)
  if ns.UI and ns.UI.MinimapButton and type(ns.UI.MinimapButton.DismissWelcomeToast) == "function" then
    ns.UI.MinimapButton.DismissWelcomeToast()
  end
  local f = Workspace.EnsureCreated()
  if not f then
    return
  end
  if tabKey then
    local st = ns.State and ns.State.GetWorkspaceUIState and ns.State.GetWorkspaceUIState()
    if st then
      st.activeTab = tabKey
    end
  end
  Widgets.SafeShow(f, true)
  Workspace.Refresh()
end

function Workspace.Hide()
  if Workspace.frame then
    for _, host in pairs(Workspace.frame.tabHosts or {}) do
      Widgets.SafeShow(host, false)
    end
    if Workspace.frame.diagnosticsDrawer then
      Widgets.SafeShow(Workspace.frame.diagnosticsDrawer, false)
    end
    Widgets.SafeShow(Workspace.frame, false)
  end
end

function Workspace.Toggle(tabKey)
  local f = Workspace.EnsureCreated()
  if not f then
    return
  end
  local isShown = (type(f.IsShown) == "function" and f:IsShown()) or false
  if isShown then
    if tabKey then
      local st = ns.State and ns.State.GetWorkspaceUIState and ns.State.GetWorkspaceUIState()
      if st and st.activeTab ~= tabKey then
        Workspace.SetActiveTab(tabKey)
        return
      end
    end
    Workspace.Hide()
  else
    Workspace.Show(tabKey)
  end
end

return Workspace
