local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.UI = ns.UI or {}

local Theme = ns.UI.Theme
local Widgets = {}
ns.UI.Widgets = Widgets

Widgets.renderGeneration = 1

function Widgets.BumpGeneration()
  Widgets.renderGeneration = (Widgets.renderGeneration or 1) + 1
  return Widgets.renderGeneration
end

-- Safe low-level widget helpers so reduced Lua 5.1 mocks never fail on optional methods.
function Widgets.SafeSetSize(w, width, height)
  if type(w) ~= "table" then
    return
  end
  if type(w.SetSize) == "function" then
    pcall(w.SetSize, w, width, height)
  else
    if width and type(w.SetWidth) == "function" then
      pcall(w.SetWidth, w, width)
    end
    if height and type(w.SetHeight) == "function" then
      pcall(w.SetHeight, w, height)
    end
  end
end

function Widgets.SafeSetWidth(w, width)
  if type(w) ~= "table" or not width then
    return
  end
  if type(w.SetWidth) == "function" then
    pcall(w.SetWidth, w, width)
  elseif type(w.SetSize) == "function" then
    local h = (type(w.GetHeight) == "function" and tonumber(w:GetHeight())) or 24
    pcall(w.SetSize, w, width, h)
  end
end

function Widgets.SafeSetHeight(w, height)
  if type(w) ~= "table" or not height then
    return
  end
  if type(w.SetHeight) == "function" then
    pcall(w.SetHeight, w, height)
  elseif type(w.SetSize) == "function" then
    local width = (type(w.GetWidth) == "function" and tonumber(w:GetWidth())) or 100
    pcall(w.SetSize, w, width, height)
  end
end

function Widgets.SafeClearPoints(w)
  if type(w) == "table" and type(w.ClearAllPoints) == "function" then
    pcall(w.ClearAllPoints, w)
  end
end

function Widgets.SafeSetPoint(w, point, relTo, relPoint, x, y)
  if type(w) ~= "table" or type(w.SetPoint) ~= "function" then
    return
  end
  if relTo ~= nil then
    pcall(w.SetPoint, w, point, relTo, relPoint, x or 0, y or 0)
  else
    pcall(w.SetPoint, w, point)
  end
end

function Widgets.SafeSetAllPoints(w, relTo)
  if type(w) ~= "table" then
    return
  end
  if type(w.SetAllPoints) == "function" then
    pcall(w.SetAllPoints, w, relTo)
  elseif type(w.SetPoint) == "function" and relTo then
    pcall(w.SetPoint, w, "TOPLEFT", relTo, "TOPLEFT", 0, 0)
    pcall(w.SetPoint, w, "BOTTOMRIGHT", relTo, "BOTTOMRIGHT", 0, 0)
  end
end

function Widgets.SafeSetSolidColor(tex, tokenOrRGBA, overrideAlpha)
  if type(tex) ~= "table" then
    return
  end
  local r, g, b, a = Theme.UnpackRGBA(tokenOrRGBA, overrideAlpha)
  if type(tex.SetColorTexture) == "function" then
    pcall(tex.SetColorTexture, tex, r, g, b, a)
  elseif type(tex.SetTexture) == "function" then
    pcall(tex.SetTexture, tex, r, g, b, a)
  end
end

function Widgets.SafeCreateTexture(frame, layer, subLevel)
  if type(frame) ~= "table" or type(frame.CreateTexture) ~= "function" then
    return nil
  end
  local ok, tex = pcall(frame.CreateTexture, frame, nil, layer or "ARTWORK", nil, subLevel)
  if not ok then
    ok, tex = pcall(frame.CreateTexture, frame, nil, layer or "ARTWORK")
  end
  return ok and tex or nil
end

function Widgets.SafeCreateFontString(frame, role, colorToken, layer)
  if type(frame) ~= "table" or type(frame.CreateFontString) ~= "function" then
    return nil
  end
  local spec = Theme.FONT_ROLES[role or "body"] or Theme.FONT_ROLES.body
  local ok, fs = pcall(frame.CreateFontString, frame, nil, layer or "OVERLAY", spec.baseGlobal)
  if not ok or not fs then
    ok, fs = pcall(frame.CreateFontString, frame)
  end
  if ok and fs then
    Theme.ApplyFont(fs, role or "body", colorToken or "text.primary")
    return fs
  end
  return nil
end

function Widgets.SafeShow(w, visible)
  if type(w) ~= "table" then
    return
  end
  if visible == false then
    if type(w.Hide) == "function" then
      pcall(w.Hide, w)
    end
  else
    if type(w.Show) == "function" then
      pcall(w.Show, w)
    end
  end
end

-- Atlas cell registry (4x4 grids of 64x64 cells with 6px UV inset to prevent edge bleed)
Widgets.GLYPHS = {
  close = { atlas = "uiControls", row = 0, col = 0, grid = 4, fallback = "×" },
  chevron_right = { atlas = "uiControls", row = 0, col = 1, grid = 4, fallback = "›" },
  chevron_down = { atlas = "uiControls", row = 0, col = 2, grid = 4, fallback = "⌄" },
  chevron_up = { atlas = "uiControls", row = 0, col = 3, grid = 4, fallback = "⌃" },
  pause = { atlas = "uiControls", row = 1, col = 0, grid = 4, fallback = "||" },
  play = { atlas = "uiControls", row = 1, col = 1, grid = 4, fallback = "▶" },
  lock = { atlas = "uiControls", row = 1, col = 2, grid = 4, fallback = "L" },
  unlock = { atlas = "uiControls", row = 1, col = 3, grid = 4, fallback = "U" },
  more = { atlas = "uiControls", row = 2, col = 0, grid = 4, fallback = "•••" },
  plus = { atlas = "uiControls", row = 2, col = 1, grid = 4, fallback = "+" },
  minus = { atlas = "uiControls", row = 2, col = 2, grid = 4, fallback = "−" },
  check = { atlas = "uiControls", row = 2, col = 3, grid = 4, fallback = "✓" },
  warning = { atlas = "uiControls", row = 3, col = 0, grid = 4, fallback = "!" },
  search = { atlas = "uiControls", row = 3, col = 1, grid = 4, fallback = "?" },
  unpin = { atlas = "uiControls", row = 3, col = 2, grid = 4, fallback = "×" },
  bookmark = { atlas = "uiControls", row = 3, col = 3, grid = 4, fallback = "★" },

  available = { atlas = "questGlyphs", row = 0, col = 0, grid = 4, fallback = "!" },
  turnin = { atlas = "questGlyphs", row = 0, col = 1, grid = 4, fallback = "?" },
  kill = { atlas = "questGlyphs", row = 0, col = 2, grid = 4, fallback = "¤" },
  loot = { atlas = "questGlyphs", row = 0, col = 3, grid = 4, fallback = "[]" },
  talk = { atlas = "questGlyphs", row = 1, col = 0, grid = 4, fallback = "…" },
  travel = { atlas = "questGlyphs", row = 1, col = 1, grid = 4, fallback = "»" },
  elite = { atlas = "questGlyphs", row = 1, col = 2, grid = 4, fallback = "♦" },
  focus = { atlas = "questGlyphs", row = 1, col = 3, grid = 4, fallback = "◎" },
  bank = { atlas = "questGlyphs", row = 2, col = 0, grid = 4, fallback = "B" },
  settings = { atlas = "questGlyphs", row = 2, col = 1, grid = 4, fallback = "*" },
  compact = { atlas = "questGlyphs", row = 2, col = 2, grid = 4, fallback = "[]" },
  info = { atlas = "questGlyphs", row = 2, col = 3, grid = 4, fallback = "i" },
}

-- Applies a single atlas cell to `tex` or cleanly hides `tex` and shows `fallbackFontString`
-- so an entire atlas grid is NEVER displayed if SetTexCoord or texture loading is unavailable.
function Widgets.ApplyGlyph(tex, fallbackFontString, glyphKey, colorToken)
  local def = Widgets.GLYPHS[glyphKey]
  if not def then
    Widgets.SafeShow(tex, false)
    if fallbackFontString and type(fallbackFontString.SetText) == "function" then
      fallbackFontString:SetText("")
      Widgets.SafeShow(fallbackFontString, false)
    end
    return false
  end

  local r, g, b, a = Theme.UnpackRGBA(colorToken or "text.primary")
  local texPath = Theme.TEXTURE_PATHS[def.atlas]
  local canUseAtlas = type(tex) == "table"
    and type(tex.SetTexture) == "function"
    and type(tex.SetTexCoord) == "function"
    and type(texPath) == "string"

  if canUseAtlas then
    pcall(tex.SetTexture, tex, texPath)
    local loadedOk = true
    if type(tex.GetTexture) == "function" then
      local okG, got = pcall(tex.GetTexture, tex)
      if okG and got == nil then
        loadedOk = false
      end
    end
    if loadedOk then
      local inset = 4.0 / 256.0
      local u1 = (def.col / def.grid) + inset
      local u2 = ((def.col + 1) / def.grid) - inset
      local v1 = (def.row / def.grid) + inset
      local v2 = ((def.row + 1) / def.grid) - inset
      pcall(tex.SetTexCoord, tex, u1, u2, v1, v2)
      if type(tex.SetVertexColor) == "function" then
        pcall(tex.SetVertexColor, tex, r, g, b, a)
      end
      Widgets.SafeShow(tex, true)
      if fallbackFontString then
        Widgets.SafeShow(fallbackFontString, false)
      end
      return true
    end
  end

  Widgets.SafeShow(tex, false)
  if fallbackFontString then
    if type(fallbackFontString.SetText) == "function" then
      fallbackFontString:SetText(def.fallback or "")
    end
    if type(fallbackFontString.SetTextColor) == "function" then
      pcall(fallbackFontString.SetTextColor, fallbackFontString, r, g, b, a)
    end
    Widgets.SafeShow(fallbackFontString, true)
  end
  return false
end

-- Creates a crisp 1-unit bordered surface without relying on BackdropTemplate or Retail NineSlice.
function Widgets.ApplySurface(frame, surfaceToken, borderToken, borderAlpha)
  if type(frame) ~= "table" then
    return frame
  end
  if not frame.__fhBg then
    frame.__fhBg = Widgets.SafeCreateTexture(frame, "BACKGROUND", 0)
    if frame.__fhBg then
      Widgets.SafeSetAllPoints(frame.__fhBg, frame)
    end
  end
  Widgets.SafeSetSolidColor(frame.__fhBg, surfaceToken or "surface.card")

  if borderToken then
    if not frame.__fhBorders then
      local top = Widgets.SafeCreateTexture(frame, "BORDER", 1)
      local bottom = Widgets.SafeCreateTexture(frame, "BORDER", 1)
      local left = Widgets.SafeCreateTexture(frame, "BORDER", 1)
      local right = Widgets.SafeCreateTexture(frame, "BORDER", 1)
      if top then
        Widgets.SafeSetPoint(top, "TOPLEFT", frame, "TOPLEFT", 0, 0)
        Widgets.SafeSetPoint(top, "TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        Widgets.SafeSetHeight(top, 1)
      end
      if bottom then
        Widgets.SafeSetPoint(bottom, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        Widgets.SafeSetPoint(bottom, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        Widgets.SafeSetHeight(bottom, 1)
      end
      if left then
        Widgets.SafeSetPoint(left, "TOPLEFT", frame, "TOPLEFT", 0, -1)
        Widgets.SafeSetPoint(left, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 1)
        Widgets.SafeSetWidth(left, 1)
      end
      if right then
        Widgets.SafeSetPoint(right, "TOPRIGHT", frame, "TOPRIGHT", 0, -1)
        Widgets.SafeSetPoint(right, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 1)
        Widgets.SafeSetWidth(right, 1)
      end
      frame.__fhBorders = { top = top, bottom = bottom, left = left, right = right }
    end
    for _, edge in pairs(frame.__fhBorders) do
      Widgets.SafeSetSolidColor(edge, borderToken, borderAlpha)
      Widgets.SafeShow(edge, true)
    end
  elseif frame.__fhBorders then
    for _, edge in pairs(frame.__fhBorders) do
      Widgets.SafeShow(edge, false)
    end
  end
  return frame
end

function Widgets.SetSurfaceBorder(frame, borderToken, borderAlpha)
  if type(frame) ~= "table" or not frame.__fhBorders then
    return
  end
  for _, edge in pairs(frame.__fhBorders) do
    Widgets.SafeSetSolidColor(edge, borderToken, borderAlpha)
    Widgets.SafeShow(edge, borderToken ~= nil)
  end
end

function Widgets.CreatePanel(parent, surfaceToken, borderToken, name)
  if type(_G.CreateFrame) ~= "function" then
    return nil
  end
  local ok, f = pcall(_G.CreateFrame, "Frame", name, parent)
  if not ok or not f then
    return nil
  end
  if f.__parent == nil then
    f.__parent = parent
  end
  Widgets.ApplySurface(f, surfaceToken or "surface.card", borderToken or "border.subtle")
  return f
end

local function hideOwnedTooltip(owner)
  local tip = _G.GameTooltip
  if type(tip) == "table" then
    local isOwned = true
    if type(tip.IsOwned) == "function" then
      local ok, res = pcall(tip.IsOwned, tip, owner)
      isOwned = ok and (res == true)
    end
    if isOwned and type(tip.Hide) == "function" then
      pcall(tip.Hide, tip)
    end
  end
end

function Widgets.BindTooltip(widget, titleText, bodyLines)
  if type(widget) ~= "table" then
    return
  end
  widget.__tooltipTitle = titleText
  widget.__tooltipLines = bodyLines
  if type(widget.SetScript) ~= "function" then
    return
  end
  if not widget.__tooltipHooked then
    widget.__tooltipHooked = true
    local prevEnter = widget.__onHoverVisualEnter
    local prevLeave = widget.__onHoverVisualLeave
    widget:SetScript("OnEnter", function(self)
      if prevEnter then prevEnter(self) end
      if self.__onHoverVisualEnter then self.__onHoverVisualEnter(self) end
      if not self.__tooltipTitle and not self.__tooltipItemID then
        return
      end
      local tip = _G.GameTooltip
      if type(tip) ~= "table" then
        return
      end
      if type(tip.SetOwner) == "function" then
        pcall(tip.SetOwner, tip, self, "ANCHOR_RIGHT")
      end
      if self.__tooltipItemID then
        if type(tip.SetItemByID) == "function" then
          pcall(tip.SetItemByID, tip, self.__tooltipItemID)
        elseif type(tip.SetHyperlink) == "function" then
          pcall(tip.SetHyperlink, tip, "item:" .. tostring(self.__tooltipItemID))
        elseif type(tip.SetText) == "function" and self.__tooltipTitle then
          pcall(tip.SetText, tip, tostring(self.__tooltipTitle), 0.93, 0.91, 0.86)
        end
        if type(self.__tooltipLines) == "table" and type(tip.AddLine) == "function" then
          for _, ln in ipairs(self.__tooltipLines) do
            pcall(tip.AddLine, tip, tostring(ln), 0.74, 0.77, 0.80, true)
          end
        end
      else
        if type(tip.ClearLines) == "function" then
          pcall(tip.ClearLines, tip)
        end
        if type(tip.SetText) == "function" then
          pcall(tip.SetText, tip, tostring(self.__tooltipTitle), 0.93, 0.91, 0.86)
        elseif type(tip.AddLine) == "function" then
          pcall(tip.AddLine, tip, tostring(self.__tooltipTitle), 0.93, 0.91, 0.86)
        end
        if type(self.__tooltipLines) == "table" and type(tip.AddLine) == "function" then
          for _, ln in ipairs(self.__tooltipLines) do
            if type(ln) == "table" and ln.left and ln.right and type(tip.AddDoubleLine) == "function" then
              pcall(tip.AddDoubleLine, tip, tostring(ln.left), tostring(ln.right), 0.74, 0.77, 0.80, 0.93, 0.91, 0.86)
            else
              local s = type(ln) == "table" and (tostring(ln.left or "") .. " " .. tostring(ln.right or "")) or tostring(ln)
              pcall(tip.AddLine, tip, s, 0.74, 0.77, 0.80, true)
            end
          end
        end
      end
      if type(tip.Show) == "function" then
        pcall(tip.Show, tip)
      end
    end)
    widget:SetScript("OnLeave", function(self)
      if prevLeave then prevLeave(self) end
      if self.__onHoverVisualLeave then self.__onHoverVisualLeave(self) end
      hideOwnedTooltip(self)
    end)
  end
end

-- Resets pooled widgets strictly before reuse (Astra v0.8.0 Section 3 invariant).
function Widgets.ResetPooledWidget(w)
  if type(w) ~= "table" then
    return
  end
  hideOwnedTooltip(w)
  w.__tooltipTitle = nil
  w.__tooltipLines = nil
  w.__tooltipItemID = nil
  w.__boundItemID = nil
  w.__boundGeneration = nil
  w.__isHovered = false
  w.__isSelected = false
  w.__onClick = nil
  if type(w.SetScript) == "function" and w.__supportsOnClick then
    pcall(w.SetScript, w, "OnClick", nil)
  end
  if type(w.SetButtonEnabled) == "function" then
    w:SetButtonEnabled(true)
  elseif type(w.Enable) == "function" then
    pcall(w.Enable, w)
  end
  Widgets.SafeShow(w, false)
end

-- Button Builder (`primary`, `secondary`, `ghost`)
local function createStyledButton(parent, styleKind, width, text, height)
  if type(_G.CreateFrame) ~= "function" then
    return nil
  end
  local ok, btn = pcall(_G.CreateFrame, "Button", nil, parent)
  if not ok or not btn then
    return nil
  end
  if btn.__parent == nil then
    btn.__parent = parent
  end
  btn.__supportsOnClick = true
  btn.__styleKind = styleKind
  btn.__enabled = true
  btn.__isHovered = false

  local h = tonumber(height) or Theme.METRICS.controlHeight
  Widgets.SafeSetSize(btn, tonumber(width) or 96, h)
  if type(btn.EnableMouse) == "function" then
    pcall(btn.EnableMouse, btn, true)
  end
  if type(btn.RegisterForClicks) == "function" then
    pcall(btn.RegisterForClicks, btn, "LeftButtonUp")
  end

  if styleKind == "primary" then
    Widgets.ApplySurface(btn, "accent.gold", "accent.goldHover", 0.9)
  elseif styleKind == "secondary" then
    Widgets.ApplySurface(btn, "surface.elevated", "border.subtle", 1.0)
  else
    Widgets.ApplySurface(btn, "surface.card", nil)
    Widgets.SafeSetSolidColor(btn.__fhBg, "surface.hover", 0.0)
  end

  local label = Widgets.SafeCreateFontString(
    btn,
    styleKind == "ghost" and "dense" or "body",
    styleKind == "primary" and "text.onAccent" or "text.primary"
  )
  if label then
    Widgets.SafeSetPoint(label, "LEFT", btn, "LEFT", 8, 0)
    Widgets.SafeSetPoint(label, "RIGHT", btn, "RIGHT", -8, 0)
    if type(label.SetJustifyH) == "function" then
      pcall(label.SetJustifyH, label, "CENTER")
    end
    if type(label.SetWordWrap) == "function" then
      pcall(label.SetWordWrap, label, false)
    end
    if type(label.SetText) == "function" then
      label:SetText(tostring(text or ""))
    end
  end
  btn.label = label

  function btn:RefreshVisualState()
    Theme.ApplyFont(
      self.label,
      self.__styleKind == "ghost" and "dense" or "body",
      self.__styleKind == "primary" and "text.onAccent" or "text.primary"
    )
    if not self.__enabled then
      if self.__styleKind == "primary" then
        Widgets.SafeSetSolidColor(self.__fhBg, "surface.elevated", 0.75)
        Widgets.SetSurfaceBorder(self, "border.subtle", 0.6)
        if self.label and self.label.SetTextColor then
          local r, g, b = Theme.UnpackRGBA("text.muted")
          pcall(self.label.SetTextColor, self.label, r, g, b, 0.8)
        end
      elseif self.__styleKind == "secondary" then
        Widgets.SafeSetSolidColor(self.__fhBg, "surface.card", 0.6)
        Widgets.SetSurfaceBorder(self, "border.subtle", 0.5)
        if self.label and self.label.SetTextColor then
          local r, g, b = Theme.UnpackRGBA("text.muted")
          pcall(self.label.SetTextColor, self.label, r, g, b, 0.7)
        end
      else
        Widgets.SafeSetSolidColor(self.__fhBg, "surface.hover", 0.0)
        if self.label and self.label.SetTextColor then
          local r, g, b = Theme.UnpackRGBA("text.muted")
          pcall(self.label.SetTextColor, self.label, r, g, b, 0.55)
        end
      end
      return
    end

    if self.__styleKind == "primary" then
      Widgets.SafeSetSolidColor(self.__fhBg, self.__isHovered and "accent.goldHover" or "accent.gold", 1.0)
      Widgets.SetSurfaceBorder(self, "accent.goldHover", 0.95)
      if self.label and self.label.SetTextColor then
        local r, g, b = Theme.UnpackRGBA("text.onAccent")
        pcall(self.label.SetTextColor, self.label, r, g, b, 1.0)
      end
    elseif self.__styleKind == "secondary" then
      Widgets.SafeSetSolidColor(self.__fhBg, self.__isHovered and "surface.hover" or "surface.elevated", 1.0)
      Widgets.SetSurfaceBorder(self, self.__isHovered and "border.default" or "border.subtle", 1.0)
      if self.label and self.label.SetTextColor then
        local r, g, b = Theme.UnpackRGBA("text.primary")
        pcall(self.label.SetTextColor, self.label, r, g, b, 1.0)
      end
    else
      local showFill = self.__isHovered or self.__isSelected
      Widgets.SafeSetSolidColor(
        self.__fhBg,
        self.__isSelected and "surface.selected" or "surface.hover",
        showFill and 1.0 or 0.0
      )
      if self.label and self.label.SetTextColor then
        local tok = (self.__isHovered or self.__isSelected) and "text.primary" or "text.secondary"
        local r, g, b = Theme.UnpackRGBA(tok)
        pcall(self.label.SetTextColor, self.label, r, g, b, 1.0)
      end
    end
  end

  function btn:SetLabel(str)
    self.__text = tostring(str or "")
    if self.label and type(self.label.SetText) == "function" then
      self.label:SetText(self.__text)
    end
  end

  function btn:GetLabel()
    if self.label and type(self.label.GetText) == "function" then
      return self.label:GetText()
    end
    return self.__text or ""
  end

  function btn:SetButtonEnabled(flag)
    self.__enabled = (flag ~= false)
    if self.__enabled then
      if type(self.Enable) == "function" then pcall(self.Enable, self) end
    else
      if type(self.Disable) == "function" then pcall(self.Disable, self) end
    end
    self:RefreshVisualState()
  end

  function btn:SetOnClick(fn)
    self.__onClick = fn
    if type(self.SetScript) == "function" then
      self:SetScript("OnClick", function(s, mouseBtn)
        if not s.__enabled then
          return
        end
        if type(s.__onClick) == "function" then
          s.__onClick(s, mouseBtn)
        end
      end)
    end
  end

  btn.__onHoverVisualEnter = function(s)
    s.__isHovered = true
    s:RefreshVisualState()
  end
  btn.__onHoverVisualLeave = function(s)
    s.__isHovered = false
    s:RefreshVisualState()
  end
  Widgets.BindTooltip(btn, nil, nil)
  btn:RefreshVisualState()
  return btn
end

function Widgets.CreatePrimaryButton(parent, width, text, height)
  return createStyledButton(parent, "primary", width, text, height)
end

function Widgets.CreateSecondaryButton(parent, width, text, height)
  return createStyledButton(parent, "secondary", width, text, height)
end

function Widgets.CreateGhostButton(parent, width, text, height)
  return createStyledButton(parent, "ghost", width, text, height)
end

-- Icon button (>= 24x24 hit area, 14-16 glyph, mandatory action tooltip)
function Widgets.CreateIconButton(parent, glyphKey, tooltipTitle, tooltipLines, hitSize, glyphSize)
  if type(_G.CreateFrame) ~= "function" then
    return nil
  end
  local ok, btn = pcall(_G.CreateFrame, "Button", nil, parent)
  if not ok or not btn then
    return nil
  end
  if btn.__parent == nil then
    btn.__parent = parent
  end
  if btn.__parent == nil then
    btn.__parent = parent
  end
  btn.__supportsOnClick = true
  btn.__enabled = true
  btn.__isHovered = false
  btn.__glyphKey = glyphKey
  btn.__colorToken = "text.secondary"

  local sz = math.max(Theme.METRICS.minHitSize, tonumber(hitSize) or 26)
  local gsz = tonumber(glyphSize) or 15
  Widgets.SafeSetSize(btn, sz, sz)
  if type(btn.EnableMouse) == "function" then
    pcall(btn.EnableMouse, btn, true)
  end
  if type(btn.RegisterForClicks) == "function" then
    pcall(btn.RegisterForClicks, btn, "LeftButtonUp")
  end

  Widgets.ApplySurface(btn, "surface.hover", nil)
  Widgets.SafeSetSolidColor(btn.__fhBg, "surface.hover", 0.0)

  btn.icon = Widgets.SafeCreateTexture(btn, "ARTWORK", 1)
  if btn.icon then
    Widgets.SafeSetSize(btn.icon, gsz, gsz)
    Widgets.SafeSetPoint(btn.icon, "CENTER", btn, "CENTER", 0, 0)
  end
  btn.fallbackText = Widgets.SafeCreateFontString(btn, "dense", "text.secondary")
  if btn.fallbackText then
    Widgets.SafeSetPoint(btn.fallbackText, "CENTER", btn, "CENTER", 0, 0)
  end

  function btn:RefreshVisualState()
    local activeFill = (self.__isHovered or self.__isSelected) and self.__enabled
    Widgets.SafeSetSolidColor(
      self.__fhBg,
      self.__isSelected and "surface.selected" or "surface.hover",
      activeFill and 1.0 or 0.0
    )
    local tok = not self.__enabled and "text.muted"
      or (self.__isSelected and "accent.gold")
      or (self.__isHovered and "text.primary")
      or (self.__colorToken or "text.secondary")
    Widgets.ApplyGlyph(self.icon, self.fallbackText, self.__glyphKey, tok)
  end

  function btn:SetGlyph(newKey, colorToken)
    self.__glyphKey = newKey
    if colorToken then
      self.__colorToken = colorToken
    end
    self:RefreshVisualState()
  end

  function btn:SetButtonEnabled(flag)
    self.__enabled = (flag ~= false)
    self:RefreshVisualState()
  end

  function btn:SetOnClick(fn)
    self.__onClick = fn
    if type(self.SetScript) == "function" then
      self:SetScript("OnClick", function(s, mb)
        if s.__enabled and type(s.__onClick) == "function" then
          s.__onClick(s, mb)
        end
      end)
    end
  end

  btn.__onHoverVisualEnter = function(s)
    s.__isHovered = true
    s:RefreshVisualState()
  end
  btn.__onHoverVisualLeave = function(s)
    s.__isHovered = false
    s:RefreshVisualState()
  end
  Widgets.BindTooltip(btn, tooltipTitle or tostring(glyphKey), tooltipLines)
  btn:RefreshVisualState()
  return btn
end

-- Semantic Badge (18 min height, 6 horizontal padding, ~0.12 alpha semantic fill + glyph + text)
function Widgets.CreateBadge(parent)
  local f = Widgets.CreatePanel(parent, "surface.elevated", "border.subtle")
  if not f then
    return nil
  end
  Widgets.SafeSetSize(f, 80, Theme.METRICS.badgeMinHeight)

  f.icon = Widgets.SafeCreateTexture(f, "ARTWORK", 1)
  if f.icon then
    Widgets.SafeSetSize(f.icon, 12, 12)
    Widgets.SafeSetPoint(f.icon, "LEFT", f, "LEFT", Theme.METRICS.badgePadX, 0)
  end
  f.iconFallback = Widgets.SafeCreateFontString(f, "dense", "text.primary")
  if f.iconFallback then
    Widgets.SafeSetPoint(f.iconFallback, "LEFT", f, "LEFT", Theme.METRICS.badgePadX, 0)
  end

  f.label = Widgets.SafeCreateFontString(f, "dense", "text.primary")
  if f.label then
    if type(f.label.SetWordWrap) == "function" then
      pcall(f.label.SetWordWrap, f.label, false)
    end
  end

  function f:Configure(text, statusToken, glyphKey, outlineGold, tooltipTitle, tooltipLines)
    local tok = statusToken or "text.secondary"
    local bgR, bgG, bgB, bgA = Theme.GetBadgeBgRGBA(tok, 0.12)
    if self.__fhBg then
      if type(self.__fhBg.SetColorTexture) == "function" then
        pcall(self.__fhBg.SetColorTexture, self.__fhBg, bgR, bgG, bgB, bgA)
      elseif type(self.__fhBg.SetTexture) == "function" then
        pcall(self.__fhBg.SetTexture, self.__fhBg, bgR, bgG, bgB, bgA)
      end
    end
    Widgets.SetSurfaceBorder(self, outlineGold and "accent.gold" or tok, outlineGold and 0.85 or 0.42)

    local hasGlyph = (type(glyphKey) == "string" and glyphKey ~= "")
    if hasGlyph then
      Widgets.ApplyGlyph(self.icon, self.iconFallback, glyphKey, outlineGold and "accent.gold" or tok)
    else
      Widgets.SafeShow(self.icon, false)
      Widgets.SafeShow(self.iconFallback, false)
    end

    local leftPad = Theme.METRICS.badgePadX + (hasGlyph and 15 or 0)
    if self.label then
      Widgets.SafeClearPoints(self.label)
      Widgets.SafeSetPoint(self.label, "LEFT", self, "LEFT", leftPad, 0)
      Theme.ApplyFont(self.label, "dense", outlineGold and "accent.gold" or tok)
      if type(self.label.SetText) == "function" then
        self.label:SetText(tostring(text or ""))
      end
    end

    local textW = nil
    if self.label and type(self.label.GetStringWidth) == "function" then
      local okW, w = pcall(self.label.GetStringWidth, self.label)
      if okW and type(w) == "number" and w > 0 then
        textW = math.ceil(w)
      end
    end
    if not textW then
      local m = Theme.GetRoleMetrics("dense")
      textW = math.ceil(string.len(Theme.StripColorCodes(text or "")) * m.avgCharWidth)
    end
    local totalW = math.max(36, leftPad + textW + Theme.METRICS.badgePadX)
    local totalH = math.max(Theme.METRICS.badgeMinHeight, Theme.GetRoleMetrics("dense").lineHeight + 2)
    Widgets.SafeSetSize(self, totalW, totalH)

    if tooltipTitle then
      if type(self.EnableMouse) == "function" then
        pcall(self.EnableMouse, self, true)
      end
      Widgets.BindTooltip(self, tooltipTitle, tooltipLines)
    else
      self.__tooltipTitle = nil
      self.__tooltipLines = nil
      if type(self.EnableMouse) == "function" then
        pcall(self.EnableMouse, self, false)
      end
    end
    Widgets.SafeShow(self, true)
    return totalW, totalH
  end

  return f
end

-- KPI Metric Display (20-size value, 12-size label, no heavy decorative box)
function Widgets.CreateKPI(parent, width)
  if type(_G.CreateFrame) ~= "function" then
    return nil
  end
  local ok, f = pcall(_G.CreateFrame, "Frame", nil, parent)
  if not ok or not f then
    return nil
  end
  Widgets.SafeSetSize(f, tonumber(width) or 180, 48)

  f.valueText = Widgets.SafeCreateFontString(f, "kpiValue", "text.primary")
  if f.valueText then
    Widgets.SafeSetPoint(f.valueText, "TOPLEFT", f, "TOPLEFT", 0, 0)
    if type(f.valueText.SetJustifyH) == "function" then
      pcall(f.valueText.SetJustifyH, f.valueText, "LEFT")
    end
  end

  f.labelText = Widgets.SafeCreateFontString(f, "dense", "text.secondary")
  if f.labelText then
    Widgets.SafeSetPoint(f.labelText, "TOPLEFT", f, "TOPLEFT", 0, -24)
    if type(f.labelText.SetJustifyH) == "function" then
      pcall(f.labelText.SetJustifyH, f.labelText, "LEFT")
    end
  end

  f.subText = Widgets.SafeCreateFontString(f, "dense", "text.muted")
  if f.subText then
    Widgets.SafeSetPoint(f.subText, "TOPLEFT", f, "TOPLEFT", 0, -39)
    if type(f.subText.SetJustifyH) == "function" then
      pcall(f.subText.SetJustifyH, f.subText, "LEFT")
    end
  end

  function f:SetKPI(valueStr, labelStr, subStr, valueColorToken, tooltipTitle, tooltipLines)
    if self.valueText then
      Theme.ApplyFont(self.valueText, "kpiValue", valueColorToken or "text.primary")
      if type(self.valueText.SetText) == "function" then
        self.valueText:SetText(tostring(valueStr or "0"))
      end
    end
    if self.labelText then
      Theme.ApplyFont(self.labelText, "dense", "text.secondary")
      if type(self.labelText.SetText) == "function" then
        self.labelText:SetText(tostring(labelStr or ""))
      end
    end
    if self.subText then
      Theme.ApplyFont(self.subText, "dense", "text.muted")
      if subStr and subStr ~= "" then
        if type(self.subText.SetText) == "function" then
          self.subText:SetText(tostring(subStr))
        end
        Widgets.SafeShow(self.subText, true)
      else
        if type(self.subText.SetText) == "function" then
          self.subText:SetText("")
        end
        Widgets.SafeShow(self.subText, false)
      end
    end
    if tooltipTitle then
      if type(self.EnableMouse) == "function" then
        pcall(self.EnableMouse, self, true)
      end
      Widgets.BindTooltip(self, tooltipTitle, tooltipLines)
    end
  end

  return f
end

-- Draft-Only Quantity Editor: `− [number] +` (24 high) + optional `1 / 5 / All(N)` draft presets.
-- NEVER invokes domain reservation directly; strictly emits draft quantity changes!
function Widgets.CreateQuantityEditor(parent)
  if type(_G.CreateFrame) ~= "function" then
    return nil
  end
  local ok, f = pcall(_G.CreateFrame, "Frame", nil, parent)
  if not ok or not f then
    return nil
  end
  Widgets.SafeSetSize(f, 224, Theme.METRICS.quantityEditorHeight)
  f.__qty = 1
  f.__maxAll = 0
  f.__onDraftChange = nil

  f.minusBtn = Widgets.CreateIconButton(f, "minus", "Decrease draft quantity", { "Adjusts draft only. Click Reserve / Update plan to apply." }, 24, 12)
  if f.minusBtn then
    Widgets.SafeSetPoint(f.minusBtn, "LEFT", f, "LEFT", 0, 0)
    Widgets.ApplySurface(f.minusBtn, "surface.elevated", "border.subtle")
  end

  f.numBox = Widgets.CreatePanel(f, "surface.window", "border.subtle")
  if f.numBox then
    Widgets.SafeSetSize(f.numBox, 38, 24)
    Widgets.SafeSetPoint(f.numBox, "LEFT", f, "LEFT", 26, 0)
    f.numLabel = Widgets.SafeCreateFontString(f.numBox, "body", "text.primary")
    if f.numLabel then
      Widgets.SafeSetPoint(f.numLabel, "CENTER", f.numBox, "CENTER", 0, 0)
    end
  end

  f.plusBtn = Widgets.CreateIconButton(f, "plus", "Increase draft quantity", { "Adjusts draft only. Click Reserve / Update plan to apply." }, 24, 12)
  if f.plusBtn then
    Widgets.SafeSetPoint(f.plusBtn, "LEFT", f, "LEFT", 66, 0)
    Widgets.ApplySurface(f.plusBtn, "surface.elevated", "border.subtle")
  end

  f.preset1 = Widgets.CreateGhostButton(f, 26, "1", 24)
  if f.preset1 then
    Widgets.SafeSetPoint(f.preset1, "LEFT", f, "LEFT", 94, 0)
  end
  f.preset5 = Widgets.CreateGhostButton(f, 26, "5", 24)
  if f.preset5 then
    Widgets.SafeSetPoint(f.preset5, "LEFT", f, "LEFT", 122, 0)
  end
  f.presetAll = Widgets.CreateGhostButton(f, 72, "All", 24)
  if f.presetAll then
    Widgets.SafeSetPoint(f.presetAll, "LEFT", f, "LEFT", 150, 0)
  end

  local function emitQty(self, targetQty)
    local clamped = math.max(1, math.min(999, math.floor(tonumber(targetQty) or 1)))
    self.__qty = clamped
    self:RefreshVisualState()
    if type(self.__onDraftChange) == "function" then
      self.__onDraftChange(clamped)
    end
  end

  if f.minusBtn then
    f.minusBtn:SetOnClick(function()
      emitQty(f, (f.__qty or 1) - 1)
    end)
  end
  if f.plusBtn then
    f.plusBtn:SetOnClick(function()
      emitQty(f, (f.__qty or 1) + 1)
    end)
  end
  if f.preset1 then
    f.preset1:SetOnClick(function()
      emitQty(f, 1)
    end)
  end
  if f.preset5 then
    f.preset5:SetOnClick(function()
      emitQty(f, 5)
    end)
  end
  if f.presetAll then
    f.presetAll:SetOnClick(function()
      if (f.__maxAll or 0) > 0 then
        emitQty(f, f.__maxAll)
      end
    end)
  end

  function f:RefreshVisualState()
    if self.numLabel and type(self.numLabel.SetText) == "function" then
      Theme.ApplyFont(self.numLabel, "body", "text.primary")
      self.numLabel:SetText(tostring(self.__qty or 1))
    end
    if self.minusBtn then
      self.minusBtn:SetButtonEnabled((self.__qty or 1) > 1)
    end
    if self.preset1 then
      self.preset1.__isSelected = (self.__qty == 1)
      self.preset1:RefreshVisualState()
    end
    if self.preset5 then
      self.preset5.__isSelected = (self.__qty == 5)
      self.preset5:RefreshVisualState()
    end
    if self.presetAll then
      local allN = math.max(0, math.floor(tonumber(self.__maxAll) or 0))
      if allN > 0 then
        self.presetAll:SetLabel(string.format("All (%d)", allN))
        self.presetAll:SetButtonEnabled(true)
        self.presetAll.__isSelected = (self.__qty == allN)
        Widgets.BindTooltip(
          self.presetAll,
          string.format("Draft all %d owned crate(s)/writ(s)", allN),
          { "Sets draft quantity to your character's owned count. Click Reserve / Update plan to commit." }
        )
      else
        self.presetAll:SetLabel("All (0)")
        self.presetAll.__isSelected = false
        self.presetAll:SetButtonEnabled(false)
        Widgets.BindTooltip(self.presetAll, "None owned on this character", { "You currently have 0 of this target in bags and bank." })
      end
      self.presetAll:RefreshVisualState()
    end
  end

  function f:Configure(currentDraftQty, ownedCount, onDraftChange)
    self.__qty = math.max(1, math.floor(tonumber(currentDraftQty) or 1))
    self.__maxAll = math.max(0, math.floor(tonumber(ownedCount) or 0))
    self.__onDraftChange = onDraftChange
    self:RefreshVisualState()
  end

  f:RefreshVisualState()
  return f
end

-- Segmented Filter (28 high; persistent selected fill + gold underline + text change, not color alone)
function Widgets.CreateSegmentedFilter(parent, options, onSelect)
  local f = Widgets.CreatePanel(parent, "surface.card", "border.subtle")
  if not f then
    return nil
  end
  f.__buttons = {}
  f.__onSelect = onSelect
  f.__selectedKey = nil

  local x = 2
  for idx, opt in ipairs(options or {}) do
    local w = tonumber(opt.width) or 116
    local okB, b = pcall(_G.CreateFrame, "Button", nil, f)
    if okB and b then
      Widgets.SafeSetSize(b, w, Theme.METRICS.controlHeight - 4)
      Widgets.SafeSetPoint(b, "LEFT", f, "LEFT", x, 0)
      if type(b.EnableMouse) == "function" then pcall(b.EnableMouse, b, true) end
      if type(b.RegisterForClicks) == "function" then pcall(b.RegisterForClicks, b, "LeftButtonUp") end

      b.bg = Widgets.SafeCreateTexture(b, "BACKGROUND", 1)
      if b.bg then Widgets.SafeSetAllPoints(b.bg, b) end

      b.underline = Widgets.SafeCreateTexture(b, "OVERLAY", 2)
      if b.underline then
        Widgets.SafeSetPoint(b.underline, "BOTTOMLEFT", b, "BOTTOMLEFT", 4, 0)
        Widgets.SafeSetPoint(b.underline, "BOTTOMRIGHT", b, "BOTTOMRIGHT", -4, 0)
        Widgets.SafeSetHeight(b.underline, 2)
        Widgets.SafeSetSolidColor(b.underline, "accent.gold", 1.0)
      end

      b.label = Widgets.SafeCreateFontString(b, "dense", "text.secondary")
      if b.label then
        Widgets.SafeSetPoint(b.label, "CENTER", b, "CENTER", 0, 1)
      end

      b.__key = opt.key
      b.__baseText = opt.label
      b.__isHovered = false
      if opt.tooltipTitle then
        Widgets.BindTooltip(b, opt.tooltipTitle, opt.tooltipLines)
      else
        Widgets.BindTooltip(b, nil, nil)
      end

      b.__onHoverVisualEnter = function(s)
        s.__isHovered = true
        f:RefreshVisualState()
      end
      b.__onHoverVisualLeave = function(s)
        s.__isHovered = false
        f:RefreshVisualState()
      end
      if type(b.SetScript) == "function" then
        b:SetScript("OnClick", function()
          f.__selectedKey = opt.key
          f:RefreshVisualState()
          if type(f.__onSelect) == "function" then
            f.__onSelect(opt.key)
          end
        end)
      end

      f.__buttons[idx] = b
      x = x + w + 2
    end
  end

  Widgets.SafeSetSize(f, x, Theme.METRICS.controlHeight)

  function f:RefreshVisualState()
    for _, b in ipairs(self.__buttons) do
      local sel = (b.__key == self.__selectedKey)
      if b.bg then
        if sel then
          Widgets.SafeSetSolidColor(b.bg, "surface.selected", 1.0)
        elseif b.__isHovered then
          Widgets.SafeSetSolidColor(b.bg, "surface.hover", 0.85)
        else
          Widgets.SafeSetSolidColor(b.bg, "surface.card", 0.0)
        end
      end
      Widgets.SafeShow(b.underline, sel)
      if b.label then
        Theme.ApplyFont(b.label, "dense", sel and "text.primary" or "text.secondary")
        if type(b.label.SetText) == "function" then
          b.label:SetText(sel and ("• " .. tostring(b.__baseText)) or tostring(b.__baseText))
        end
      end
    end
  end

  function f:SetSelected(key)
    self.__selectedKey = key
    self:RefreshVisualState()
  end

  f:RefreshVisualState()
  return f
end

-- Checkbox (16 glyph in 24-high labeled hit area; explicit on/off state)
function Widgets.CreateCheckbox(parent, labelText, tooltipTitle, tooltipLines, onChange)
  if type(_G.CreateFrame) ~= "function" then
    return nil
  end
  local ok, btn = pcall(_G.CreateFrame, "Button", nil, parent)
  if not ok or not btn then
    return nil
  end
  btn.__checked = false
  btn.__isHovered = false
  btn.__onChange = onChange

  if type(btn.EnableMouse) == "function" then pcall(btn.EnableMouse, btn, true) end
  if type(btn.RegisterForClicks) == "function" then pcall(btn.RegisterForClicks, btn, "LeftButtonUp") end

  btn.box = Widgets.CreatePanel(btn, "surface.window", "border.default")
  if btn.box then
    Widgets.SafeSetSize(btn.box, 16, 16)
    Widgets.SafeSetPoint(btn.box, "LEFT", btn, "LEFT", 2, 0)
    btn.checkIcon = Widgets.SafeCreateTexture(btn.box, "OVERLAY", 2)
    if btn.checkIcon then
      Widgets.SafeSetSize(btn.checkIcon, 12, 12)
      Widgets.SafeSetPoint(btn.checkIcon, "CENTER", btn.box, "CENTER", 0, 0)
    end
    btn.checkFallback = Widgets.SafeCreateFontString(btn.box, "dense", "accent.gold")
    if btn.checkFallback then
      Widgets.SafeSetPoint(btn.checkFallback, "CENTER", btn.box, "CENTER", 0, 0)
    end
  end

  btn.label = Widgets.SafeCreateFontString(btn, "dense", "text.secondary")
  if btn.label then
    Widgets.SafeSetPoint(btn.label, "LEFT", btn, "LEFT", 24, 0)
    if type(btn.label.SetJustifyH) == "function" then pcall(btn.label.SetJustifyH, btn.label, "LEFT") end
    if type(btn.label.SetText) == "function" then btn.label:SetText(tostring(labelText or "")) end
  end

  local m = Theme.GetRoleMetrics("dense")
  local estW = 28 + math.ceil(string.len(tostring(labelText or "")) * m.avgCharWidth)
  Widgets.SafeSetSize(btn, math.max(72, estW), 24)

  function btn:RefreshVisualState()
    if self.box then
      Widgets.SafeSetSolidColor(self.box.__fhBg, self.__checked and "surface.selected" or "surface.window", 1.0)
      Widgets.SetSurfaceBorder(self.box, self.__checked and "accent.gold" or (self.__isHovered and "text.secondary" or "border.default"), 1.0)
      if self.__checked then
        Widgets.ApplyGlyph(self.checkIcon, self.checkFallback, "check", "accent.gold")
      else
        Widgets.SafeShow(self.checkIcon, false)
        Widgets.SafeShow(self.checkFallback, false)
      end
    end
    if self.label then
      Theme.ApplyFont(self.label, "dense", self.__checked and "text.primary" or "text.secondary")
    end
  end

  function btn:SetChecked(flag)
    self.__checked = (flag == true)
    self:RefreshVisualState()
  end

  btn.__onHoverVisualEnter = function(s)
    s.__isHovered = true
    s:RefreshVisualState()
  end
  btn.__onHoverVisualLeave = function(s)
    s.__isHovered = false
    s:RefreshVisualState()
  end
  Widgets.BindTooltip(btn, tooltipTitle, tooltipLines)

  if type(btn.SetScript) == "function" then
    btn:SetScript("OnClick", function(s)
      s.__checked = not s.__checked
      s:RefreshVisualState()
      if type(s.__onChange) == "function" then
        s.__onChange(s.__checked)
      end
    end)
  end

  btn:RefreshVisualState()
  return btn
end

-- Tab Bar (32-high tabs inside 36-high bar; supports featured leading glyph + semantic pill badge)
function Widgets.CreateTabBar(parent, tabs, onSelectTab)
  local bar = Widgets.CreatePanel(parent, "surface.card", nil)
  if not bar then
    return nil
  end
  Widgets.SafeSetHeight(bar, Theme.METRICS.tabBarHeight)

  bar.bottomDivider = Widgets.SafeCreateTexture(bar, "BORDER", 1)
  if bar.bottomDivider then
    Widgets.SafeSetPoint(bar.bottomDivider, "BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    Widgets.SafeSetPoint(bar.bottomDivider, "BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    Widgets.SafeSetHeight(bar.bottomDivider, 1)
    Widgets.SafeSetSolidColor(bar.bottomDivider, "border.subtle", 1.0)
  end

  local function measureFontStringWidth(fs, text, role)
    if fs and type(fs.GetStringWidth) == "function" then
      local okW, w = pcall(fs.GetStringWidth, fs)
      if okW and type(w) == "number" and w > 0 then
        return math.ceil(w)
      end
    end
    local m = Theme.GetRoleMetrics(role or "body")
    return math.ceil(string.len(Theme.StripColorCodes(text or "")) * m.avgCharWidth)
  end

  bar.__tabs = {}
  bar.__selectedKey = nil
  bar.__onSelectTab = onSelectTab

  local x = Theme.METRICS.workspacePadding
  for idx, t in ipairs(tabs or {}) do
    local w = tonumber(t.width) or 150
    local okB, b = pcall(_G.CreateFrame, "Button", nil, bar)
    if okB and b then
      Widgets.SafeSetSize(b, w, Theme.METRICS.tabHeight)
      Widgets.SafeSetPoint(b, "BOTTOMLEFT", bar, "BOTTOMLEFT", x, 0)
      if type(b.EnableMouse) == "function" then pcall(b.EnableMouse, b, true) end
      if type(b.RegisterForClicks) == "function" then pcall(b.RegisterForClicks, b, "LeftButtonUp") end

      b.bg = Widgets.SafeCreateTexture(b, "BACKGROUND", 1)
      if b.bg then Widgets.SafeSetAllPoints(b.bg, b) end

      if t.featured == true then
        b.featTop = Widgets.SafeCreateTexture(b, "BORDER", 2)
        b.featLeft = Widgets.SafeCreateTexture(b, "BORDER", 2)
        b.featRight = Widgets.SafeCreateTexture(b, "BORDER", 2)
        if b.featTop then
          Widgets.SafeSetPoint(b.featTop, "TOPLEFT", b, "TOPLEFT", 0, 0)
          Widgets.SafeSetPoint(b.featTop, "TOPRIGHT", b, "TOPRIGHT", 0, 0)
          Widgets.SafeSetHeight(b.featTop, 1)
        end
        if b.featLeft then
          Widgets.SafeSetPoint(b.featLeft, "TOPLEFT", b, "TOPLEFT", 0, 0)
          Widgets.SafeSetPoint(b.featLeft, "BOTTOMLEFT", b, "BOTTOMLEFT", 0, 1)
          Widgets.SafeSetWidth(b.featLeft, 1)
        end
        if b.featRight then
          Widgets.SafeSetPoint(b.featRight, "TOPRIGHT", b, "TOPRIGHT", 0, 0)
          Widgets.SafeSetPoint(b.featRight, "BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 1)
          Widgets.SafeSetWidth(b.featRight, 1)
        end
      end

      b.underline = Widgets.SafeCreateTexture(b, "OVERLAY", 3)
      if b.underline then
        Widgets.SafeSetPoint(b.underline, "BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
        Widgets.SafeSetPoint(b.underline, "BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
        Widgets.SafeSetHeight(b.underline, t.featured == true and 3 or 2)
        Widgets.SafeSetSolidColor(b.underline, "accent.gold", 1.0)
      end

      if type(t.iconGlyph) == "string" and t.iconGlyph ~= "" then
        b.icon = Widgets.SafeCreateTexture(b, "ARTWORK", 2)
        if b.icon then
          Widgets.SafeSetSize(b.icon, 14, 14)
        end
        b.iconFallback = Widgets.SafeCreateFontString(b, "dense", t.iconToken or "accent.gold")
      end

      b.label = Widgets.SafeCreateFontString(b, "sectionTitle", "text.secondary")
      if b.label and type(b.label.SetWordWrap) == "function" then
        pcall(b.label.SetWordWrap, b.label, false)
      end

      b.pill = Widgets.CreatePanel(b, "surface.elevated", "border.subtle")
      if b.pill then
        b.pill.label = Widgets.SafeCreateFontString(b.pill, "dense", "text.primary")
        if b.pill.label then
          Widgets.SafeSetPoint(b.pill.label, "CENTER", b.pill, "CENTER", 0, 0)
          if type(b.pill.label.SetWordWrap) == "function" then
            pcall(b.pill.label.SetWordWrap, b.pill.label, false)
          end
        end
        Widgets.SafeShow(b.pill, false)
      end

      b.__key = t.key
      b.__title = t.label
      b.__baseWidth = w
      b.__featured = (t.featured == true)
      b.__iconGlyph = t.iconGlyph
      b.__iconToken = t.iconToken or "accent.gold"
      b.__badgeText = ""
      b.__badgeToken = nil
      b.__badgeSuffix = ""
      b.__isHovered = false

      b.__onHoverVisualEnter = function(s)
        s.__isHovered = true
        bar:RefreshVisualState()
      end
      b.__onHoverVisualLeave = function(s)
        s.__isHovered = false
        bar:RefreshVisualState()
      end
      Widgets.BindTooltip(b, t.tooltipTitle, t.tooltipLines)

      if type(b.SetScript) == "function" then
        b:SetScript("OnClick", function()
          if bar.__selectedKey ~= t.key then
            bar.__selectedKey = t.key
            bar:RefreshVisualState()
            if type(bar.__onSelectTab) == "function" then
              bar.__onSelectTab(t.key)
            end
          end
        end)
      end

      bar.__tabs[idx] = b
      x = x + w + 8
    end
  end

  function bar:SetTabCountBadge(tabKey, badgeStr, statusToken)
    local clean = (type(badgeStr) == "string") and badgeStr or ""
    for _, b in ipairs(self.__tabs) do
      if b.__key == tabKey then
        b.__badgeText = clean
        b.__badgeToken = statusToken
        b.__badgeSuffix = (clean ~= "") and ("  " .. clean) or ""
      end
    end
    self:RefreshVisualState()
  end

  function bar:RefreshVisualState()
    local cursorTabX = Theme.METRICS.workspacePadding
    for _, b in ipairs(self.__tabs) do
      local sel = (b.__key == self.__selectedKey)
      local feat = (b.__featured == true)

      if b.bg then
        if sel then
          Widgets.SafeSetSolidColor(b.bg, feat and "surface.selected" or "surface.elevated", 0.94)
        elseif b.__isHovered then
          Widgets.SafeSetSolidColor(b.bg, "surface.hover", 0.72)
        elseif feat then
          local fr, fg, fb, fa = Theme.GetBadgeBgRGBA("accent.gold", 0.09)
          if type(b.bg.SetColorTexture) == "function" then
            pcall(b.bg.SetColorTexture, b.bg, fr, fg, fb, fa)
          elseif type(b.bg.SetTexture) == "function" then
            pcall(b.bg.SetTexture, b.bg, fr, fg, fb, fa)
          end
        else
          Widgets.SafeSetSolidColor(b.bg, "surface.card", 0.0)
        end
      end

      if feat then
        local capAlpha = sel and 0.55 or (b.__isHovered and 0.48 or 0.36)
        if b.featTop then Widgets.SafeSetSolidColor(b.featTop, "accent.gold", capAlpha) end
        if b.featLeft then Widgets.SafeSetSolidColor(b.featLeft, "accent.gold", capAlpha) end
        if b.featRight then Widgets.SafeSetSolidColor(b.featRight, "accent.gold", capAlpha) end
      end

      Widgets.SafeShow(b.underline, sel)

      local hasIcon = (type(b.__iconGlyph) == "string" and b.__iconGlyph ~= "")
      if hasIcon then
        local iconColor = sel and "accent.goldHover" or (b.__iconToken or "accent.gold")
        Widgets.ApplyGlyph(b.icon, b.iconFallback, b.__iconGlyph, iconColor)
      end

      local labelRole = (sel or feat) and "sectionTitle" or "body"
      local labelColor = sel and "text.primary"
        or (feat and "text.primary")
        or (b.__isHovered and "text.primary" or "text.secondary")
      local labelW = 0
      if b.label then
        Theme.ApplyFont(b.label, labelRole, labelColor)
        if type(b.label.SetText) == "function" then
          b.label:SetText(tostring(b.__title or ""))
        end
        labelW = measureFontStringWidth(b.label, b.__title, labelRole)
      end

      local badgeText = tostring(b.__badgeText or "")
      local hasBadge = (badgeText ~= "" and b.pill ~= nil)
      local pillW, pillH = 0, 0
      if hasBadge and b.pill then
        local pillTok = b.__badgeToken or (feat and "status.ready" or "status.reserved")
        local pR, pG, pB, pA = Theme.GetBadgeBgRGBA(pillTok, sel and 0.18 or 0.14)
        if b.pill.__fhBg then
          if type(b.pill.__fhBg.SetColorTexture) == "function" then
            pcall(b.pill.__fhBg.SetColorTexture, b.pill.__fhBg, pR, pG, pB, pA)
          elseif type(b.pill.__fhBg.SetTexture) == "function" then
            pcall(b.pill.__fhBg.SetTexture, b.pill.__fhBg, pR, pG, pB, pA)
          end
        end
        Widgets.SetSurfaceBorder(b.pill, pillTok, sel and 0.65 or 0.48)
        if b.pill.label then
          Theme.ApplyFont(b.pill.label, "dense", pillTok)
          if type(b.pill.label.SetText) == "function" then
            b.pill.label:SetText(badgeText)
          end
        end
        local badgeTextW = measureFontStringWidth(b.pill.label, badgeText, "dense")
        pillW = math.max(26, badgeTextW + (Theme.METRICS.badgePadX * 2))
        pillH = math.max(Theme.METRICS.badgeMinHeight, Theme.GetRoleMetrics("dense").lineHeight + 2)
        Widgets.SafeSetSize(b.pill, pillW, pillH)
        Widgets.SafeShow(b.pill, true)
      elseif b.pill then
        Widgets.SafeShow(b.pill, false)
      end

      local iconBlockW = hasIcon and 20 or 0
      local badgeBlockW = hasBadge and (8 + pillW) or 0
      local contentW = iconBlockW + labelW + badgeBlockW
      local effectiveW = math.max(b.__baseWidth or 150, contentW + 24)
      b.__measuredWidth = effectiveW

      Widgets.SafeSetSize(b, effectiveW, Theme.METRICS.tabHeight)
      Widgets.SafeClearPoints(b)
      Widgets.SafeSetPoint(b, "BOTTOMLEFT", bar, "BOTTOMLEFT", cursorTabX, 0)

      local innerX = math.max(12, math.floor((effectiveW - contentW) / 2 + 0.5))
      if hasIcon then
        if b.icon then
          Widgets.SafeClearPoints(b.icon)
          Widgets.SafeSetPoint(b.icon, "LEFT", b, "LEFT", innerX, 1)
        end
        if b.iconFallback then
          Widgets.SafeClearPoints(b.iconFallback)
          Widgets.SafeSetPoint(b.iconFallback, "LEFT", b, "LEFT", innerX, 1)
        end
        innerX = innerX + 20
      end
      if b.label then
        Widgets.SafeClearPoints(b.label)
        Widgets.SafeSetPoint(b.label, "LEFT", b, "LEFT", innerX, 1)
        innerX = innerX + labelW
      end
      if hasBadge and b.pill then
        Widgets.SafeClearPoints(b.pill)
        Widgets.SafeSetPoint(b.pill, "LEFT", b, "LEFT", innerX + 8, 1)
      end

      cursorTabX = cursorTabX + effectiveW + 8
    end
  end

  function bar:SetSelected(key)
    self.__selectedKey = key
    self:RefreshVisualState()
  end

  bar:RefreshVisualState()
  return bar
end

-- Search Box (EditBox with search glyph, placeholder, Escape clear, and safe fallback if EditBox absent)
function Widgets.CreateSearchBox(parent, width, height, placeholder, onTextChanged)
  local wrap = Widgets.CreatePanel(parent, "surface.window", "border.subtle")
  if not wrap then
    return nil
  end
  local w = tonumber(width) or 210
  local h = tonumber(height) or Theme.METRICS.controlHeight
  Widgets.SafeSetSize(wrap, w, h)
  wrap.__query = ""
  wrap.__onTextChanged = onTextChanged

  wrap.icon = Widgets.SafeCreateTexture(wrap, "ARTWORK", 1)
  if wrap.icon then
    Widgets.SafeSetSize(wrap.icon, 13, 13)
    Widgets.SafeSetPoint(wrap.icon, "LEFT", wrap, "LEFT", 8, 0)
  end
  wrap.iconFallback = Widgets.SafeCreateFontString(wrap, "dense", "text.muted")
  if wrap.iconFallback then
    Widgets.SafeSetPoint(wrap.iconFallback, "LEFT", wrap, "LEFT", 8, 0)
  end
  Widgets.ApplyGlyph(wrap.icon, wrap.iconFallback, "search", "text.muted")

  wrap.placeholder = Widgets.SafeCreateFontString(wrap, "dense", "text.muted")
  if wrap.placeholder then
    Widgets.SafeSetPoint(wrap.placeholder, "LEFT", wrap, "LEFT", 26, 0)
    if type(wrap.placeholder.SetText) == "function" then
      wrap.placeholder:SetText(tostring(placeholder or "Search…"))
    end
  end

  wrap.clearBtn = Widgets.CreateIconButton(wrap, "close", "Clear search", nil, 24, 11)
  if wrap.clearBtn then
    Widgets.SafeSetPoint(wrap.clearBtn, "RIGHT", wrap, "RIGHT", -2, 0)
    Widgets.SafeShow(wrap.clearBtn, false)
  end

  local okEB, eb = pcall(_G.CreateFrame, "EditBox", nil, wrap)
  if okEB and eb and type(eb.SetAutoFocus) == "function" then
    eb:SetAutoFocus(false)
    Widgets.SafeSetPoint(eb, "TOPLEFT", wrap, "TOPLEFT", 26, -2)
    Widgets.SafeSetPoint(eb, "BOTTOMRIGHT", wrap, "BOTTOMRIGHT", -26, 2)
    Theme.ApplyFont(eb, "body", "text.primary")
    if type(eb.SetTextInsets) == "function" then
      pcall(eb.SetTextInsets, eb, 0, 0, 0, 0)
    end
    eb:SetScript("OnEscapePressed", function(s)
      if s.ClearFocus then s:ClearFocus() end
    end)
    eb:SetScript("OnEnterPressed", function(s)
      if s.ClearFocus then s:ClearFocus() end
    end)
    eb:SetScript("OnEditFocusGained", function()
      Widgets.SetSurfaceBorder(wrap, "accent.gold", 0.85)
      if wrap.placeholder then Widgets.SafeShow(wrap.placeholder, false) end
    end)
    eb:SetScript("OnEditFocusLost", function(s)
      Widgets.SetSurfaceBorder(wrap, "border.subtle", 1.0)
      local cur = (type(s.GetText) == "function" and s:GetText()) or ""
      if wrap.placeholder then Widgets.SafeShow(wrap.placeholder, cur == "") end
    end)
    eb:SetScript("OnTextChanged", function(s, userInput)
      local cur = (type(s.GetText) == "function" and s:GetText()) or ""
      wrap.__query = cur
      if wrap.placeholder then
        local hasFocus = (type(s.HasFocus) == "function" and s:HasFocus()) or false
        Widgets.SafeShow(wrap.placeholder, cur == "" and not hasFocus)
      end
      if wrap.clearBtn then
        Widgets.SafeShow(wrap.clearBtn, cur ~= "")
      end
      if userInput and type(wrap.__onTextChanged) == "function" then
        wrap.__onTextChanged(cur)
      end
    end)
    wrap.editBox = eb
  end

  if wrap.clearBtn then
    wrap.clearBtn:SetOnClick(function()
      wrap:SetQuery("", true)
    end)
  end

  function wrap:SetQuery(q, notify)
    local clean = tostring(q or "")
    self.__query = clean
    if self.editBox and type(self.editBox.SetText) == "function" then
      pcall(self.editBox.SetText, self.editBox, clean)
    end
    if self.placeholder then
      Widgets.SafeShow(self.placeholder, clean == "")
    end
    if self.clearBtn then
      Widgets.SafeShow(self.clearBtn, clean ~= "")
    end
    if notify and type(self.__onTextChanged) == "function" then
      self.__onTextChanged(clean)
    end
  end

  function wrap:GetQuery()
    return self.__query or ""
  end

  return wrap
end

-- Item Icon Cell (live item icon or neutral placeholder + subtle quality rim + item tooltip + generation guard)
function Widgets.CreateItemIcon(parent, size)
  local sz = tonumber(size) or 28
  local f = Widgets.CreatePanel(parent, "surface.window", "border.default")
  if not f then
    return nil
  end
  Widgets.SafeSetSize(f, sz, sz)
  if type(f.EnableMouse) == "function" then
    pcall(f.EnableMouse, f, true)
  end

  f.tex = Widgets.SafeCreateTexture(f, "ARTWORK", 1)
  if f.tex then
    Widgets.SafeSetPoint(f.tex, "TOPLEFT", f, "TOPLEFT", 2, -2)
    Widgets.SafeSetPoint(f.tex, "BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    if type(f.tex.SetTexCoord) == "function" then
      pcall(f.tex.SetTexCoord, f.tex, 0.07, 0.93, 0.07, 0.93)
    end
  end

  f.placeholderTex = Widgets.SafeCreateTexture(f, "ARTWORK", 2)
  if f.placeholderTex then
    Widgets.SafeSetSize(f.placeholderTex, math.max(12, math.floor(sz * 0.56)), math.max(12, math.floor(sz * 0.56)))
    Widgets.SafeSetPoint(f.placeholderTex, "CENTER", f, "CENTER", 0, 0)
  end
  f.placeholderText = Widgets.SafeCreateFontString(f, "dense", "text.muted")
  if f.placeholderText then
    Widgets.SafeSetPoint(f.placeholderText, "CENTER", f, "CENTER", 0, 0)
  end

  Widgets.BindTooltip(f, nil, nil)

  function f:SetItem(itemID, fallbackName, generation)
    local id = tonumber(itemID)
    self.__boundItemID = id
    self.__boundGeneration = generation or Widgets.renderGeneration
    self.__tooltipItemID = id
    self.__tooltipTitle = fallbackName

    local info = (ns.Compat and ns.Compat.GetItemVisualInfo and ns.Compat.GetItemVisualInfo(id))
      or { hasIcon = false, quality = nil }

    local qr, qg, qb, qa = Theme.GetItemQualityBorderRGBA(info.quality)
    if self.__fhBorders then
      for _, edge in pairs(self.__fhBorders) do
        Widgets.SafeSetSolidColor(edge, { qr, qg, qb, qa })
      end
    end

    if info.hasIcon and self.tex and type(self.tex.SetTexture) == "function" then
      pcall(self.tex.SetTexture, self.tex, info.icon)
      if type(self.tex.SetTexCoord) == "function" then
        pcall(self.tex.SetTexCoord, self.tex, 0.07, 0.93, 0.07, 0.93)
      end
      if type(self.tex.SetVertexColor) == "function" then
        pcall(self.tex.SetVertexColor, self.tex, 1, 1, 1, 1)
      end
      Widgets.SafeShow(self.tex, true)
      Widgets.SafeShow(self.placeholderTex, false)
      Widgets.SafeShow(self.placeholderText, false)
    else
      Widgets.SafeShow(self.tex, false)
      Widgets.ApplyGlyph(self.placeholderTex, self.placeholderText, "loot", "text.muted")
      if id and ns.Compat and ns.Compat.RequestItemVisualLoad then
        ns.Compat.RequestItemVisualLoad(id)
      end
    end
  end

  return f
end

-- Inline Notice Banner (semantic icon + measured wrapped text + optional single action + optional dismiss)
function Widgets.CreateInlineNotice(parent)
  local f = Widgets.CreatePanel(parent, "surface.elevated", "border.default")
  if not f then
    return nil
  end

  f.icon = Widgets.SafeCreateTexture(f, "ARTWORK", 1)
  if f.icon then
    Widgets.SafeSetSize(f.icon, 16, 16)
    Widgets.SafeSetPoint(f.icon, "TOPLEFT", f, "TOPLEFT", 12, -11)
  end
  f.iconFallback = Widgets.SafeCreateFontString(f, "body", "status.warning")
  if f.iconFallback then
    Widgets.SafeSetPoint(f.iconFallback, "TOPLEFT", f, "TOPLEFT", 12, -10)
  end

  f.text = Widgets.SafeCreateFontString(f, "body", "text.primary")
  if f.text then
    if type(f.text.SetJustifyH) == "function" then pcall(f.text.SetJustifyH, f.text, "LEFT") end
    if type(f.text.SetWordWrap) == "function" then pcall(f.text.SetWordWrap, f.text, true) end
  end

  f.actionBtn = Widgets.CreatePrimaryButton(f, 112, "Apply", 24)
  f.secondaryBtn = Widgets.CreateGhostButton(f, 72, "Dismiss", 24)

  function f:Configure(totalWidth, opts)
    opts = type(opts) == "table" and opts or {}
    local statusTok = opts.statusToken or "status.warning"
    Widgets.SetSurfaceBorder(self, statusTok, 0.65)
    Widgets.ApplyGlyph(self.icon, self.iconFallback, opts.glyph or "info", statusTok)

    local hasPrimary = (type(opts.actionLabel) == "string" and opts.actionLabel ~= "" and type(opts.onAction) == "function")
    local hasSecondary = (type(opts.secondaryLabel) == "string" and opts.secondaryLabel ~= "" and type(opts.onSecondary) == "function")

    local rightReserve = 12
    if hasSecondary then rightReserve = rightReserve + 76 end
    if hasPrimary then rightReserve = rightReserve + 118 end

    local w = math.max(240, tonumber(totalWidth) or 800)
    local textW = math.max(120, w - 36 - rightReserve)

    if self.text then
      Widgets.SafeClearPoints(self.text)
      Widgets.SafeSetPoint(self.text, "TOPLEFT", self, "TOPLEFT", 34, -10)
      Theme.ApplyFont(self.text, "body", "text.primary")
    end
    local h = Theme.MeasureWrappedHeight(self.text, opts.message or "", textW, "body", 38, 20)
    Widgets.SafeSetSize(self, w, h)

    if self.secondaryBtn then
      if hasSecondary then
        self.secondaryBtn:SetLabel(opts.secondaryLabel)
        self.secondaryBtn:SetOnClick(opts.onSecondary)
        Widgets.SafeClearPoints(self.secondaryBtn)
        Widgets.SafeSetPoint(self.secondaryBtn, "RIGHT", self, "RIGHT", -10, 0)
        Widgets.SafeShow(self.secondaryBtn, true)
      else
        Widgets.SafeShow(self.secondaryBtn, false)
      end
    end

    if self.actionBtn then
      if hasPrimary then
        self.actionBtn:SetLabel(opts.actionLabel)
        self.actionBtn:SetOnClick(opts.onAction)
        Widgets.SafeClearPoints(self.actionBtn)
        Widgets.SafeSetPoint(self.actionBtn, "RIGHT", self, "RIGHT", hasSecondary and -88 or -10, 0)
        Widgets.SafeShow(self.actionBtn, true)
      else
        Widgets.SafeShow(self.actionBtn, false)
      end
    end

    Widgets.SafeShow(self, true)
    return h
  end

  return f
end

-- Custom Scroll Viewport (10-wide track inside 16/18-wide lane, >=24-high thumb, scroll-anchor preservation)
function Widgets.CreateScrollViewport(parent, onScrollOffsetChanged)
  if type(_G.CreateFrame) ~= "function" then
    return nil
  end
  local okWrap, wrap = pcall(_G.CreateFrame, "Frame", nil, parent)
  if not okWrap or not wrap then
    return nil
  end
  if type(wrap.SetClipsChildren) == "function" then
    pcall(wrap.SetClipsChildren, wrap, true)
  end

  local okSF, sf = pcall(_G.CreateFrame, "ScrollFrame", nil, wrap)
  if not okSF or not sf then
    sf = wrap
  end
  if sf ~= wrap then
    Widgets.SafeSetPoint(sf, "TOPLEFT", wrap, "TOPLEFT", 0, 0)
    Widgets.SafeSetPoint(sf, "BOTTOMRIGHT", wrap, "BOTTOMRIGHT", -Theme.METRICS.scrollbarLaneWidth, 0)
  end
  if type(sf.EnableMouseWheel) == "function" then
    pcall(sf.EnableMouseWheel, sf, true)
  end

  local okChild, content = pcall(_G.CreateFrame, "Frame", nil, sf)
  if okChild and content then
    Widgets.SafeSetSize(content, 800, 400)
    if type(sf.SetScrollChild) == "function" then
      pcall(sf.SetScrollChild, sf, content)
    end
  end

  local lane = Widgets.CreatePanel(wrap, "surface.window", nil)
  if lane then
    Widgets.SafeSetPoint(lane, "TOPRIGHT", wrap, "TOPRIGHT", 0, 0)
    Widgets.SafeSetPoint(lane, "BOTTOMRIGHT", wrap, "BOTTOMRIGHT", 0, 0)
    Widgets.SafeSetWidth(lane, Theme.METRICS.scrollbarLaneWidth)
    if type(lane.EnableMouse) == "function" then pcall(lane.EnableMouse, lane, true) end
  end

  local track = lane and Widgets.CreatePanel(lane, "surface.card", "border.subtle") or nil
  if track then
    Widgets.SafeSetPoint(track, "TOP", lane, "TOP", 0, -2)
    Widgets.SafeSetPoint(track, "BOTTOM", lane, "BOTTOM", 0, 2)
    Widgets.SafeSetWidth(track, Theme.METRICS.scrollbarTrackWidth)
  end

  local thumb = track and Widgets.CreatePanel(track, "border.default", nil) or nil
  if thumb then
    Widgets.SafeSetWidth(thumb, Theme.METRICS.scrollbarTrackWidth - 2)
  end

  wrap.scrollFrame = sf
  wrap.content = content
  wrap.lane = lane
  wrap.track = track
  wrap.thumb = thumb
  wrap.__offset = 0
  wrap.__viewportHeight = 396
  wrap.__contentHeight = 396
  wrap.__onScrollChanged = onScrollOffsetChanged

  function wrap:UpdateScrollbarThumb()
    local maxScroll = math.max(0, (self.__contentHeight or 0) - (self.__viewportHeight or 1))
    if not self.lane or not self.thumb then
      return
    end
    if maxScroll <= 0.5 then
      Widgets.SafeShow(self.thumb, false)
      return
    end
    Widgets.SafeShow(self.thumb, true)
    local trackH = math.max(40, (self.__viewportHeight or 396) - 4)
    local ratio = math.min(1.0, (self.__viewportHeight or 396) / math.max(1, self.__contentHeight or 396))
    local thumbH = math.max(Theme.METRICS.scrollbarThumbMinHeight, math.floor(trackH * ratio + 0.5))
    local travel = math.max(0, trackH - thumbH)
    local frac = math.max(0, math.min(1.0, (self.__offset or 0) / maxScroll))
    local topY = -math.floor(travel * frac + 0.5)
    Widgets.SafeClearPoints(self.thumb)
    Widgets.SafeSetPoint(self.thumb, "TOP", self.track, "TOP", 0, topY)
    Widgets.SafeSetHeight(self.thumb, thumbH)
  end

  function wrap:SetScrollOffset(newOffset, suppressCallback)
    local maxScroll = math.max(0, (self.__contentHeight or 0) - (self.__viewportHeight or 1))
    local clamped = math.max(0, math.min(maxScroll, tonumber(newOffset) or 0))
    self.__offset = clamped
    if self.scrollFrame and type(self.scrollFrame.SetVerticalScroll) == "function" then
      pcall(self.scrollFrame.SetVerticalScroll, self.scrollFrame, clamped)
    end
    self:UpdateScrollbarThumb()
    if not suppressCallback and type(self.__onScrollChanged) == "function" then
      self.__onScrollChanged(clamped)
    end
  end

  function wrap:GetScrollOffset()
    return self.__offset or 0
  end

  function wrap:SetDimensions(viewportWidth, viewportHeight, contentHeight)
    local vw = math.max(200, tonumber(viewportWidth) or 928)
    local vh = math.max(120, tonumber(viewportHeight) or 396)
    local ch = math.max(vh, tonumber(contentHeight) or vh)
    self.__viewportHeight = vh
    self.__contentHeight = ch
    local contentW = math.max(180, vw - Theme.METRICS.scrollbarLaneWidth)
    Widgets.SafeSetSize(self, vw, vh)
    if self.content then
      Widgets.SafeSetSize(self.content, contentW, ch)
    end
    self:SetScrollOffset(self.__offset or 0, true)
    return contentW
  end

  if sf and type(sf.SetScript) == "function" then
    sf:SetScript("OnMouseWheel", function(_, delta)
      local step = 48
      local nextOff = (wrap.__offset or 0) - ((tonumber(delta) or 0) * step)
      wrap:SetScrollOffset(nextOff, false)
    end)
  end

  if lane and type(lane.SetScript) == "function" then
    lane:SetScript("OnMouseDown", function(_, button)
      if button ~= "LeftButton" then
        return
      end
      if type(_G.GetCursorPosition) == "function" and type(lane.GetTop) == "function" and type(lane.GetEffectiveScale) == "function" then
        local okC, _, cursorY = pcall(_G.GetCursorPosition)
        local okT, top = pcall(lane.GetTop, lane)
        local okS, scale = pcall(lane.GetEffectiveScale, lane)
        if okC and okT and okS and top and scale and scale > 0 then
          local relY = top - (cursorY / scale)
          local frac = math.max(0, math.min(1.0, relY / math.max(1, wrap.__viewportHeight or 396)))
          local maxScroll = math.max(0, (wrap.__contentHeight or 0) - (wrap.__viewportHeight or 1))
          wrap:SetScrollOffset(frac * maxScroll, false)
        end
      end
    end)
  end

  return wrap
end
