local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.UI = ns.UI or {}

local Theme = ns.UI.Theme
local Widgets = ns.UI.Widgets

local MinimapButton = ns.UI.MinimapButton or {}
ns.UI.MinimapButton = MinimapButton

MinimapButton.button = MinimapButton.button or nil
MinimapButton.welcomeToast = MinimapButton.welcomeToast or nil

local DEFAULT_ANGLE_DEG = 220

local function getMinimapRadius(minimap)
  local w = (type(minimap) == "table" and type(minimap.GetWidth) == "function" and tonumber(minimap:GetWidth())) or 0
  if not w or w <= 20 then
    w = 140
  end
  return (w * 0.5) + 6
end

function MinimapButton.UpdatePosition()
  local btn = MinimapButton.button
  local minimap = _G.Minimap
  if not btn or type(minimap) ~= "table" then
    return
  end
  local mm = (ns.State and ns.State.GetMinimapSettings and ns.State.GetMinimapSettings()) or { angleDeg = DEFAULT_ANGLE_DEG }
  local deg = tonumber(mm.angleDeg) or DEFAULT_ANGLE_DEG
  local rad = math.rad(deg)
  local radius = getMinimapRadius(minimap)
  local ox = math.cos(rad) * radius
  local oy = math.sin(rad) * radius
  Widgets.SafeClearPoints(btn)
  Widgets.SafeSetPoint(btn, "CENTER", minimap, "CENTER", ox, oy)
end

local function updateAngleFromCursor(minimap)
  local getCursor = _G.GetCursorPosition
  if type(getCursor) ~= "function" or type(minimap) ~= "table" or type(minimap.GetCenter) ~= "function" then
    return
  end
  local okCur, cx, cy = pcall(getCursor)
  local okCtr, mx, my = pcall(minimap.GetCenter, minimap)
  if not okCur or not okCtr or type(cx) ~= "number" or type(cy) ~= "number" or type(mx) ~= "number" or type(my) ~= "number" then
    return
  end
  local scale = (type(minimap.GetEffectiveScale) == "function" and tonumber(minimap:GetEffectiveScale())) or 1
  if scale <= 0 then
    scale = 1
  end
  local dx = (cx / scale) - mx
  local dy = (cy / scale) - my
  local deg = math.deg(math.atan2(dy, dx))
  if deg < 0 then
    deg = deg + 360
  end
  if ns.State and type(ns.State.SetMinimapAngle) == "function" then
    ns.State.SetMinimapAngle(deg)
  end
  MinimapButton.UpdatePosition()
end

local function showMinimapTooltip(ownerFrame, anchorMode)
  local tip = _G.GameTooltip
  if type(tip) ~= "table" then
    return
  end
  if type(tip.SetOwner) == "function" then
    pcall(tip.SetOwner, tip, ownerFrame, anchorMode or "ANCHOR_LEFT")
  end
  if type(tip.ClearLines) == "function" then
    pcall(tip.ClearLines, tip)
  end
  local title = string.format("ForeverHub v%s", tostring(ns.version or "0.8.6"))
  if type(tip.SetText) == "function" then
    pcall(tip.SetText, tip, title, 0.91, 0.79, 0.50)
  elseif type(tip.AddLine) == "function" then
    pcall(tip.AddLine, tip, title, 0.91, 0.79, 0.50)
  end
  if type(tip.AddLine) == "function" then
    pcall(tip.AddLine, tip, "Left-Click: Open / Close ForeverHub", 0.93, 0.91, 0.86, true)
    pcall(tip.AddLine, tip, "Right-Click: Open Crates & Writs", 0.74, 0.77, 0.80, true)
    pcall(tip.AddLine, tip, "Drag: Move around Minimap", 0.74, 0.77, 0.80, true)
    pcall(tip.AddLine, tip, "Shift + Right-Click: Hide (/fh minimap to restore)", 0.57, 0.62, 0.66, true)
  end
  if type(tip.Show) == "function" then
    pcall(tip.Show, tip)
  end
end

local function hideMinimapTooltip(ownerFrame)
  local tip = _G.GameTooltip
  if type(tip) ~= "table" then
    return
  end
  local owned = true
  if ownerFrame and type(tip.IsOwned) == "function" then
    local ok, res = pcall(tip.IsOwned, tip, ownerFrame)
    owned = ok and (res == true)
  end
  if owned and type(tip.Hide) == "function" then
    pcall(tip.Hide, tip)
  end
end

function MinimapButton.DismissWelcomeToast()
  if MinimapButton.welcomeToast then
    Widgets.SafeShow(MinimapButton.welcomeToast, false)
  end
end

local function ensureWorkspaceReady()
  if ns.UI and ns.UI.Crates and type(ns.UI.Crates.EnsureInitialized) == "function" then
    ns.UI.Crates.EnsureInitialized()
  end
end

local function handleLauncherClick(mouseBtn)
  MinimapButton.DismissWelcomeToast()
  if mouseBtn == "RightButton" then
    local shiftDown = type(_G.IsShiftKeyDown) == "function" and _G.IsShiftKeyDown()
    if shiftDown then
      MinimapButton.SetHidden(true)
      if ns.Compat and type(ns.Compat.Print) == "function" then
        ns.Compat.Print("Minimap button hidden. Type /fh minimap to restore it anytime.")
      end
      return
    end
    ensureWorkspaceReady()
    if ns.UI and ns.UI.Workspace and type(ns.UI.Workspace.Toggle) == "function" then
      ns.UI.Workspace.Toggle("crates")
    end
    return
  end
  ensureWorkspaceReady()
  if ns.UI and ns.UI.Workspace and type(ns.UI.Workspace.Toggle) == "function" then
    ns.UI.Workspace.Toggle()
  end
end

function MinimapButton.EnsureCreated()
  if MinimapButton.button then
    return MinimapButton.button
  end
  local minimap = _G.Minimap
  if type(minimap) ~= "table" or type(_G.CreateFrame) ~= "function" then
    return nil
  end

  local ok, btn = pcall(_G.CreateFrame, "Button", "ForeverHubMinimapButton", minimap)
  if not ok or not btn then
    return nil
  end
  MinimapButton.button = btn

  Widgets.SafeSetSize(btn, 32, 32)
  if type(btn.SetFrameStrata) == "function" then
    pcall(btn.SetFrameStrata, btn, "MEDIUM")
  end
  if type(btn.SetFrameLevel) == "function" then
    local baseLvl = (type(minimap.GetFrameLevel) == "function" and tonumber(minimap:GetFrameLevel())) or 2
    pcall(btn.SetFrameLevel, btn, baseLvl + 6)
  end
  if type(btn.EnableMouse) == "function" then
    pcall(btn.EnableMouse, btn, true)
  end
  if type(btn.SetMovable) == "function" then
    pcall(btn.SetMovable, btn, true)
  end
  if type(btn.RegisterForClicks) == "function" then
    pcall(btn.RegisterForClicks, btn, "LeftButtonUp", "RightButtonUp")
  end
  if type(btn.RegisterForDrag) == "function" then
    pcall(btn.RegisterForDrag, btn, "LeftButton")
  end

  -- Sanctuary circular dark core + gold ring + compass pointer
  local coreBg = Widgets.SafeCreateTexture(btn, "BACKGROUND", 0)
  if coreBg then
    Widgets.SafeSetSize(coreBg, 20, 20)
    Widgets.SafeSetPoint(coreBg, "CENTER", btn, "CENTER", 0, 0)
    Widgets.SafeSetSolidColor(coreBg, "surface.window", 0.96)
  end
  btn.coreBg = coreBg

  local hoverGlow = Widgets.SafeCreateTexture(btn, "BORDER", 0)
  if hoverGlow then
    Widgets.SafeSetSize(hoverGlow, 34, 34)
    Widgets.SafeSetPoint(hoverGlow, "CENTER", btn, "CENTER", 0, 0)
    if type(hoverGlow.SetTexture) == "function" then
      pcall(hoverGlow.SetTexture, hoverGlow, Theme.TEXTURE_PATHS.pinGlow)
    end
    if type(hoverGlow.SetVertexColor) == "function" then
      local r, g, b = Theme.UnpackRGBA("accent.goldHover")
      pcall(hoverGlow.SetVertexColor, hoverGlow, r, g, b, 0.42)
    end
    Widgets.SafeShow(hoverGlow, false)
  end
  btn.hoverGlow = hoverGlow

  local ringTex = Widgets.SafeCreateTexture(btn, "OVERLAY", 1)
  if ringTex then
    Widgets.SafeSetSize(ringTex, 30, 30)
    Widgets.SafeSetPoint(ringTex, "CENTER", btn, "CENTER", 0, 0)
    if type(ringTex.SetTexture) == "function" then
      pcall(ringTex.SetTexture, ringTex, Theme.TEXTURE_PATHS.pinRing)
    end
    if type(ringTex.SetVertexColor) == "function" then
      local r, g, b = Theme.UnpackRGBA("accent.gold")
      pcall(ringTex.SetVertexColor, ringTex, r, g, b, 1.0)
    end
  end
  btn.ringTex = ringTex

  local iconTex = Widgets.SafeCreateTexture(btn, "ARTWORK", 2)
  local iconLoaded = false
  if iconTex then
    Widgets.SafeSetSize(iconTex, 16, 16)
    Widgets.SafeSetPoint(iconTex, "CENTER", btn, "CENTER", 0, 0)
    if type(iconTex.SetTexture) == "function" then
      local okTex = pcall(iconTex.SetTexture, iconTex, Theme.TEXTURE_PATHS.navigationArrow)
      iconLoaded = okTex and true or false
    end
    if type(iconTex.SetRotation) == "function" then
      pcall(iconTex.SetRotation, iconTex, -0.52)
    end
    if type(iconTex.SetVertexColor) == "function" then
      local r, g, b = Theme.UnpackRGBA("accent.goldHover")
      pcall(iconTex.SetVertexColor, iconTex, r, g, b, 1.0)
    end
  end
  btn.iconTex = iconTex

  if not iconLoaded then
    local fbText = Widgets.SafeCreateFontString(btn, "dense", "accent.goldHover")
    if fbText and type(fbText.SetText) == "function" then
      Widgets.SafeSetPoint(fbText, "CENTER", btn, "CENTER", 0, 0)
      fbText:SetText("FH")
    end
    btn.fallbackText = fbText
  end

  if type(btn.SetScript) == "function" then
    btn:SetScript("OnEnter", function(self)
      if self.hoverGlow then
        Widgets.SafeShow(self.hoverGlow, true)
      end
      if self.ringTex and type(self.ringTex.SetVertexColor) == "function" then
        local r, g, b = Theme.UnpackRGBA("accent.goldHover")
        pcall(self.ringTex.SetVertexColor, self.ringTex, r, g, b, 1.0)
      end
      showMinimapTooltip(self, "ANCHOR_LEFT")
    end)

    btn:SetScript("OnLeave", function(self)
      if self.hoverGlow then
        Widgets.SafeShow(self.hoverGlow, false)
      end
      if self.ringTex and type(self.ringTex.SetVertexColor) == "function" then
        local r, g, b = Theme.UnpackRGBA("accent.gold")
        pcall(self.ringTex.SetVertexColor, self.ringTex, r, g, b, 1.0)
      end
      hideMinimapTooltip(self)
    end)

    btn:SetScript("OnDragStart", function(self)
      self.__dragging = true
      hideMinimapTooltip(self)
      self:SetScript("OnUpdate", function()
        updateAngleFromCursor(_G.Minimap)
      end)
    end)

    btn:SetScript("OnDragStop", function(self)
      self.__dragging = false
      self:SetScript("OnUpdate", nil)
      updateAngleFromCursor(_G.Minimap)
    end)

    btn:SetScript("OnClick", function(self, mouseBtn)
      if self.__dragging then
        return
      end
      handleLauncherClick(mouseBtn)
    end)
  end

  MinimapButton.UpdatePosition()
  MinimapButton.RefreshVisibility()
  return btn
end

function MinimapButton.RefreshVisibility()
  local btn = MinimapButton.button or MinimapButton.EnsureCreated()
  if not btn then
    return
  end
  local mm = (ns.State and ns.State.GetMinimapSettings and ns.State.GetMinimapSettings()) or { hidden = false }
  Widgets.SafeShow(btn, mm.hidden ~= true)
  if mm.hidden ~= true then
    MinimapButton.UpdatePosition()
  end
end

function MinimapButton.SetHidden(hidden)
  if ns.State and type(ns.State.SetMinimapHidden) == "function" then
    ns.State.SetMinimapHidden(hidden == true)
  end
  MinimapButton.RefreshVisibility()
end

function MinimapButton.ResetPosition()
  if ns.State and type(ns.State.SetMinimapAngle) == "function" then
    ns.State.SetMinimapAngle(DEFAULT_ANGLE_DEG)
  end
  if ns.State and type(ns.State.SetMinimapHidden) == "function" then
    ns.State.SetMinimapHidden(false)
  end
  MinimapButton.RefreshVisibility()
end

function MinimapButton.EnsureWelcomeToastCreated()
  if MinimapButton.welcomeToast then
    return MinimapButton.welcomeToast
  end
  if type(_G.CreateFrame) ~= "function" then
    return nil
  end
  local toast = Widgets.CreatePanel(_G.UIParent, "surface.window", "accent.gold", "ForeverHubWelcomeToast")
  if not toast then
    return nil
  end
  MinimapButton.welcomeToast = toast

  Widgets.SafeSetSize(toast, 344, 78)
  Widgets.SafeSetPoint(toast, "TOPRIGHT", _G.UIParent, "TOPRIGHT", -212, -26)
  if type(toast.SetFrameStrata) == "function" then
    pcall(toast.SetFrameStrata, toast, "DIALOG")
  end
  if type(toast.SetClampedToScreen) == "function" then
    pcall(toast.SetClampedToScreen, toast, true)
  end
  if type(toast.EnableMouse) == "function" then
    pcall(toast.EnableMouse, toast, true)
  end
  if type(toast.SetMovable) == "function" then
    pcall(toast.SetMovable, toast, true)
  end
  if type(toast.RegisterForDrag) == "function" then
    pcall(toast.RegisterForDrag, toast, "LeftButton")
  end
  if type(toast.SetScript) == "function" then
    toast:SetScript("OnDragStart", function(self)
      if type(self.StartMoving) == "function" then
        pcall(self.StartMoving, self)
      end
    end)
    toast:SetScript("OnDragStop", function(self)
      if type(self.StopMovingOrSizing) == "function" then
        pcall(self.StopMovingOrSizing, self)
      end
    end)
  end

  local titleText = Widgets.SafeCreateFontString(toast, "sectionTitle", "accent.goldHover")
  if titleText then
    Widgets.SafeSetPoint(titleText, "TOPLEFT", toast, "TOPLEFT", 12, -10)
    if type(titleText.SetText) == "function" then
      titleText:SetText(string.format("ForeverHub v%s Ready", tostring(ns.version or "0.8.6")))
    end
  end
  toast.titleText = titleText

  local subText = Widgets.SafeCreateFontString(toast, "dense", "text.secondary")
  if subText then
    Widgets.SafeSetPoint(subText, "TOPLEFT", toast, "TOPLEFT", 12, -31)
    Widgets.SafeSetWidth(subText, 198)
    if type(subText.SetJustifyH) == "function" then
      pcall(subText.SetJustifyH, subText, "LEFT")
    end
    if type(subText.SetWordWrap) == "function" then
      pcall(subText.SetWordWrap, subText, true)
    end
    if type(subText.SetText) == "function" then
      subText:SetText("Click the gold Minimap compass or type /fh anytime.")
    end
  end
  toast.subText = subText

  local openBtn = Widgets.CreatePrimaryButton(toast, 104, "Open /fh", 26)
  if openBtn then
    Widgets.SafeSetPoint(openBtn, "BOTTOMRIGHT", toast, "BOTTOMRIGHT", -12, 12)
    openBtn:SetOnClick(function()
      MinimapButton.DismissWelcomeToast()
      ensureWorkspaceReady()
      if ns.UI and ns.UI.Workspace and type(ns.UI.Workspace.Show) == "function" then
        ns.UI.Workspace.Show()
      end
    end)
  end
  toast.openBtn = openBtn

  local closeBtn = Widgets.CreateIconButton(
    toast,
    "close",
    "Dismiss",
    { "ForeverHub stays on your Minimap and via /fh." },
    22,
    12
  )
  if closeBtn then
    Widgets.SafeSetPoint(closeBtn, "TOPRIGHT", toast, "TOPRIGHT", -6, -6)
    closeBtn:SetOnClick(function()
      MinimapButton.DismissWelcomeToast()
    end)
  end
  toast.closeBtn = closeBtn

  Widgets.SafeShow(toast, false)
  return toast
end

function MinimapButton.ShowWelcomeToastIfNeeded()
  if not ns.State or type(ns.State.HasSeenOnboarding) ~= "function" then
    return false
  end
  if ns.State.HasSeenOnboarding() then
    return false
  end
  if type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() then
    return false
  end

  ns.State.MarkOnboardingSeen(true)
  if ns.Compat and type(ns.Compat.Print) == "function" then
    ns.Compat.Print(
      string.format(
        "Welcome to ForeverHub v%s! Click the gold compass button on your Minimap (or type /fh) to open.",
        tostring(ns.version or "0.8.6")
      )
    )
  end

  local toast = MinimapButton.EnsureWelcomeToastCreated()
  if toast then
    if toast.titleText and type(toast.titleText.SetText) == "function" then
      toast.titleText:SetText(string.format("ForeverHub v%s Ready", tostring(ns.version or "0.8.6")))
    end
    Widgets.SafeShow(toast, true)
  end
  return true
end

-- Blizzard Addon Compartment callbacks (WoW 1.60.1 Minimap Addons dropdown).
-- Assigned via `_G.<name>` so zero `OP_SETGLOBAL` instructions are emitted.
_G.ForeverHub_OnAddonCompartmentClick = function(_, buttonName)
  handleLauncherClick(buttonName or "LeftButton")
end

_G.ForeverHub_OnAddonCompartmentEnter = function(_, menuButtonFrame)
  showMinimapTooltip(menuButtonFrame or _G.Minimap, "ANCHOR_LEFT")
end

_G.ForeverHub_OnAddonCompartmentLeave = function(_, menuButtonFrame)
  hideMinimapTooltip(menuButtonFrame)
end

return MinimapButton
