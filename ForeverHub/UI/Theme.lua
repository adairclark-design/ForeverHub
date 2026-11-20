local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.UI = ns.UI or {}

local Theme = {}
ns.UI.Theme = Theme

-- All dimensions are logical UI units at addon scale 1.0 (Astra v0.8.0 Section 3).
Theme.SPACING = {
  xs = 4,
  sm = 8,
  md = 12,
  lg = 16,
  xl = 24,
}

Theme.METRICS = {
  workspaceDefaultWidth = 960,
  workspaceDefaultHeight = 640,
  workspaceMinWidth = 760,
  workspaceMinHeight = 520,
  compactThresholdWidth = 900,
  workspacePadding = 16,
  cardPadding = 12,
  controlHeight = 28,
  quantityEditorHeight = 24,
  minHitSize = 24,
  badgeMinHeight = 18,
  badgePadX = 6,
  tabBarHeight = 36,
  tabHeight = 32,
  titleBarHeight = 44,
  summaryHeight = 60,
  filterBarHeight = 40,
  actionBarHeight = 32,
  scrollbarTrackWidth = 10,
  scrollbarLaneWidth = 16,
  scrollbarThumbMinHeight = 24,
  crateHeaderHeight = 56,
  tableHeaderHeight = 24,
  ingredientRowMinHeight = 40,
  optionFooterHeight = 32,
  hudDefaultWidth = 240,
  hudMinWidth = 200,
  hudMaxWidth = 440,
  hudDefaultHeight = 48,
  hudPadding = 8,
  hudArrowLaneWidth = 36,
  hudArrowLaneHeight = 36,
}

-- Sanctuary Opaque-Readable Palette (foreverhub.cc obsidian/gold/crystal/arcane tokens)
Theme.PALETTE_ID = "foreverhub-sanctuary-v1"

Theme.COLORS = {
  surface = {
    window = { 0.035, 0.055, 0.082, 0.98, hex = "090E15" },
    card = { 0.051, 0.075, 0.102, 1.00, hex = "0D131A" },
    elevated = { 0.063, 0.090, 0.125, 1.00, hex = "101720" },
    hover = { 0.086, 0.125, 0.173, 1.00, hex = "16202C" },
    selected = { 0.098, 0.153, 0.212, 1.00, hex = "192736" },
    reserved = { 0.071, 0.137, 0.169, 1.00, hex = "12232B" },
  },
  border = {
    default = { 0.227, 0.286, 0.361, 1.00, hex = "3A495C" },
    subtle = { 0.122, 0.165, 0.220, 1.00, hex = "1F2A38" },
    gold = { 0.843, 0.737, 0.518, 1.00, hex = "D7BC84" },
  },
  text = {
    primary = { 0.957, 0.937, 0.902, 1.00, hex = "F4EFE6" },
    secondary = { 0.776, 0.816, 0.863, 1.00, hex = "C6D0DC" },
    muted = { 0.557, 0.612, 0.682, 1.00, hex = "8E9CAE" },
    onAccent = { 0.035, 0.055, 0.082, 1.00, hex = "090E15" },
  },
  accent = {
    gold = { 0.953, 0.824, 0.549, 1.00, hex = "F3D28C" },
    goldMuted = { 0.843, 0.737, 0.518, 1.00, hex = "D7BC84" },
    goldHover = { 0.980, 0.878, 0.651, 1.00, hex = "FAE0A6" },
    crystal = { 0.361, 0.882, 1.000, 1.00, hex = "5CE1FF" },
    arcane = { 0.400, 0.322, 0.557, 1.00, hex = "66528E" },
  },
  status = {
    ready = { 0.494, 0.827, 0.635, 1.00, hex = "7ED3A2" },
    reserved = { 0.361, 0.882, 1.000, 1.00, hex = "5CE1FF" },
    bank = { 0.486, 0.796, 0.796, 1.00, hex = "7CCBCB" },
    buy = { 0.953, 0.824, 0.549, 1.00, hex = "F3D28C" },
    warning = { 0.949, 0.769, 0.376, 1.00, hex = "F2C460" },
    danger = { 0.914, 0.541, 0.502, 1.00, hex = "E98A80" },
    research = { 0.616, 0.525, 0.800, 1.00, hex = "9D86CC" },
  },
}

-- Subtle item-quality border palette for icon frames ONLY (never carries readiness/recommendation meaning)
local QUALITY_BORDER_RGB = {
  [0] = { 0.45, 0.47, 0.50 }, -- Poor
  [1] = { 0.36, 0.40, 0.45 }, -- Common (restrained slate)
  [2] = { 0.24, 0.62, 0.32 }, -- Uncommon
  [3] = { 0.22, 0.48, 0.86 }, -- Rare
  [4] = { 0.58, 0.30, 0.82 }, -- Epic
  [5] = { 0.88, 0.52, 0.16 }, -- Legendary
}

Theme.FONT_ROLES = {
  windowTitle = { size = 18, lineHeight = 22, baseGlobal = "GameFontNormalLarge", avgCharWidth = 8.8 },
  sectionTitle = { size = 15, lineHeight = 20, baseGlobal = "GameFontNormal", avgCharWidth = 7.4 },
  body = { size = 13, lineHeight = 18, baseGlobal = "GameFontHighlight", avgCharWidth = 6.5 },
  dense = { size = 12, lineHeight = 16, baseGlobal = "GameFontHighlightSmall", avgCharWidth = 5.9 },
  kpiValue = { size = 20, lineHeight = 24, baseGlobal = "GameFontNormalLarge", avgCharWidth = 9.8 },
  trackerAction = { size = 15, lineHeight = 20, baseGlobal = "GameFontHighlight", avgCharWidth = 7.3 },
}

Theme.TEXTURE_PATHS = {
  uiControls = "Interface\\AddOns\\ForeverHub\\Textures\\UIControls.tga",
  questGlyphs = "Interface\\AddOns\\ForeverHub\\Textures\\QuestGlyphs.tga",
  pinRing = "Interface\\AddOns\\ForeverHub\\Textures\\PinRing.tga",
  pinGlow = "Interface\\AddOns\\ForeverHub\\Textures\\PinGlow.tga",
  coinGlyphs = "Interface\\AddOns\\ForeverHub\\Textures\\CoinGlyphs.tga",
  sanctuaryChrome = "Interface\\AddOns\\ForeverHub\\Textures\\SanctuaryChrome.tga",
  navigationArrow = "Interface\\AddOns\\ForeverHub\\Textures\\NavigationArrow.tga",
}

Theme.fontObjects = {}
Theme.appliedFontScale = nil
Theme.customMeasureFn = nil
Theme.coinIconsVerified = nil
Theme.sanctuaryChromeVerified = nil

function Theme.ResolveToken(tokenOrTable)
  if type(tokenOrTable) == "table" and type(tokenOrTable[1]) == "number" then
    return tokenOrTable
  end
  if type(tokenOrTable) == "string" then
    local group, key = string.match(tokenOrTable, "^([^%.]+)%.([^%.]+)$")
    if group and key and Theme.COLORS[group] and Theme.COLORS[group][key] then
      return Theme.COLORS[group][key]
    end
  end
  return Theme.COLORS.text.primary
end

function Theme.UnpackRGBA(tokenOrTable, overrideAlpha)
  local c = Theme.ResolveToken(tokenOrTable)
  return c[1], c[2], c[3], (overrideAlpha ~= nil and overrideAlpha or c[4] or 1.0)
end

function Theme.GetBadgeBgRGBA(statusToken, alpha)
  local c = Theme.ResolveToken(statusToken)
  return c[1], c[2], c[3], tonumber(alpha) or 0.12
end

function Theme.Colorize(tokenOrTable, text)
  local c = Theme.ResolveToken(tokenOrTable)
  local hex = c.hex or "EEE8DA"
  return "|cff" .. hex .. tostring(text or "") .. "|r"
end

function Theme.GetItemQualityBorderRGBA(quality)
  local q = tonumber(quality)
  local rgb = (q and QUALITY_BORDER_RGB[q]) or nil
  if not rgb then
    local subtle = Theme.COLORS.border.default
    return subtle[1], subtle[2], subtle[3], 0.90
  end
  return rgb[1], rgb[2], rgb[3], 0.90
end

function Theme.GetTextScale()
  if ns.State and type(ns.State.GetWorkspaceUIState) == "function" then
    local ok, uiState = pcall(ns.State.GetWorkspaceUIState)
    if ok and type(uiState) == "table" and type(uiState.textScale) == "number" then
      return math.max(0.85, math.min(1.35, uiState.textScale))
    end
  end
  return 1.0
end

function Theme.GetRoleMetrics(role)
  local spec = Theme.FONT_ROLES[role] or Theme.FONT_ROLES.body
  local scale = Theme.GetTextScale()
  return {
    size = math.max(10, math.floor(spec.size * scale + 0.5)),
    lineHeight = math.max(14, math.ceil(spec.lineHeight * scale)),
    avgCharWidth = spec.avgCharWidth * scale,
    baseGlobal = spec.baseGlobal,
  }
end

-- Creates and updates addon-owned FontObjects without mutating shared Blizzard globals.
function Theme.EnsureFontObjects()
  local scale = Theme.GetTextScale()
  if Theme.appliedFontScale == scale and next(Theme.fontObjects) ~= nil then
    return
  end
  Theme.appliedFontScale = scale

  if type(_G.CreateFont) ~= "function" then
    return
  end

  for role, spec in pairs(Theme.FONT_ROLES) do
    local fontObj = Theme.fontObjects[role]
    if not fontObj then
      local ok, created = pcall(_G.CreateFont, "ForeverHubFont_" .. role)
      if ok and created then
        fontObj = created
        Theme.fontObjects[role] = fontObj
      end
    end
    if fontObj then
      local baseObj = _G[spec.baseGlobal] or _G.GameFontHighlight or _G.GameFontNormal
      if baseObj and type(fontObj.CopyFontObject) == "function" and not fontObj.__copiedBase then
        pcall(fontObj.CopyFontObject, fontObj, baseObj)
        fontObj.__copiedBase = true
      end
      local fontPath, _, fontFlags = nil, nil, ""
      if baseObj and type(baseObj.GetFont) == "function" then
        local okF, fp, _, ff = pcall(baseObj.GetFont, baseObj)
        if okF and type(fp) == "string" and fp ~= "" then
          fontPath = fp
          fontFlags = ff or ""
        end
      end
      local targetSize = math.max(10, math.floor(spec.size * scale + 0.5))
      if fontPath and type(fontObj.SetFont) == "function" then
        pcall(fontObj.SetFont, fontObj, fontPath, targetSize, fontFlags)
      end
      if type(fontObj.SetShadowOffset) == "function" then
        pcall(fontObj.SetShadowOffset, fontObj, 1, -1)
      end
      if type(fontObj.SetShadowColor) == "function" then
        pcall(fontObj.SetShadowColor, fontObj, 0, 0, 0, 0.75)
      end
    end
  end
end

function Theme.ApplyFont(fontString, role, colorToken)
  if type(fontString) ~= "table" then
    return
  end
  Theme.EnsureFontObjects()
  local fontObj = Theme.fontObjects[role or "body"]
  if fontObj and type(fontString.SetFontObject) == "function" then
    pcall(fontString.SetFontObject, fontString, fontObj)
  elseif type(fontString.SetFontObject) == "function" then
    local spec = Theme.FONT_ROLES[role or "body"] or Theme.FONT_ROLES.body
    local fallbackBase = _G[spec.baseGlobal]
    if fallbackBase then
      pcall(fontString.SetFontObject, fontString, fallbackBase)
    end
  end
  if colorToken and type(fontString.SetTextColor) == "function" then
    local r, g, b, a = Theme.UnpackRGBA(colorToken)
    pcall(fontString.SetTextColor, fontString, r, g, b, a)
  end
end

function Theme.StripColorCodes(raw)
  if type(raw) ~= "string" then
    return tostring(raw or "")
  end
  local s = string.gsub(raw, "|c%x%x%x%x%x%x%x%x", "")
  s = string.gsub(s, "|r", "")
  s = string.gsub(s, "|T[^|]+|t", "@@")
  return s
end

-- Deterministic fallback measurement when live WoW GetStringHeight is unavailable (e.g. headless Lua 5.1).
function Theme.EstimateWrappedHeight(text, width, role, minHeight, verticalPadding)
  local m = Theme.GetRoleMetrics(role or "body")
  local padY = tonumber(verticalPadding) or 0
  local minH = tonumber(minHeight) or m.lineHeight
  local effWidth = math.max(24, tonumber(width) or 200)
  local clean = Theme.StripColorCodes(text or "")
  if clean == "" then
    return math.max(minH, m.lineHeight + padY)
  end

  local charsPerLine = math.max(4, math.floor(effWidth / math.max(4.0, m.avgCharWidth)))
  local totalLines = 0
  local startIdx = 1
  local len = string.len(clean)
  while startIdx <= len do
    local nl = string.find(clean, "\n", startIdx, true)
    local segLen
    if nl then
      segLen = nl - startIdx
      startIdx = nl + 1
    else
      segLen = len - startIdx + 1
      startIdx = len + 1
    end
    local segLines = math.max(1, math.ceil(math.max(1, segLen) / charsPerLine))
    totalLines = totalLines + segLines
  end
  if totalLines < 1 then
    totalLines = 1
  end
  return math.max(minH, (totalLines * m.lineHeight) + padY)
end

-- Sets final width before measuring; uses live GetStringHeight when available or deterministic fallback.
function Theme.MeasureWrappedHeight(fontString, text, width, role, minHeight, verticalPadding)
  local padY = tonumber(verticalPadding) or 0
  local m = Theme.GetRoleMetrics(role or "body")
  local minH = tonumber(minHeight) or m.lineHeight
  local effWidth = math.max(24, tonumber(width) or 200)

  if fontString then
    if type(fontString.SetWordWrap) == "function" then
      pcall(fontString.SetWordWrap, fontString, true)
    end
    if type(fontString.SetWidth) == "function" then
      pcall(fontString.SetWidth, fontString, effWidth)
    end
    if text ~= nil and type(fontString.SetText) == "function" then
      pcall(fontString.SetText, fontString, tostring(text))
    end
  end

  if type(Theme.customMeasureFn) == "function" then
    local h = Theme.customMeasureFn(text, effWidth, role, m)
    if type(h) == "number" and h > 0 then
      return math.max(minH, math.ceil(h) + padY)
    end
  end

  if fontString and type(fontString.GetStringHeight) == "function" then
    local ok, rawH = pcall(fontString.GetStringHeight, fontString)
    if ok and type(rawH) == "number" and rawH > 0 then
      return math.max(minH, math.ceil(rawH) + padY)
    end
  end

  return Theme.EstimateWrappedHeight(
    text ~= nil and text or (fontString and fontString.GetText and fontString:GetText()) or "",
    effWidth,
    role,
    minH,
    padY
  )
end

-- Verifies once whether custom CoinGlyphs.tga loads cleanly in the current client UI.
function Theme.CanUseCoinIcons()
  if Theme.coinIconsVerified ~= nil then
    return Theme.coinIconsVerified
  end
  if type(_G.UIParent) ~= "table" or type(_G.UIParent.CreateTexture) ~= "function" then
    Theme.coinIconsVerified = false
    return false
  end
  local ok, probe = pcall(_G.UIParent.CreateTexture, _G.UIParent, nil, "BACKGROUND")
  if not ok or type(probe) ~= "table" or type(probe.SetTexture) ~= "function" or type(probe.GetTexture) ~= "function" or type(probe.SetTexCoord) ~= "function" then
    if probe and type(probe.Hide) == "function" then
      pcall(probe.Hide, probe)
    end
    Theme.coinIconsVerified = false
    return false
  end
  pcall(probe.SetTexture, probe, Theme.TEXTURE_PATHS.coinGlyphs)
  local loaded = nil
  local okGet, texVal = pcall(probe.GetTexture, probe)
  if okGet then
    loaded = texVal
  end
  if type(probe.Hide) == "function" then
    pcall(probe.Hide, probe)
  end
  Theme.coinIconsVerified = (loaded ~= nil)
  return Theme.coinIconsVerified
end

local function buildCoinMarkup(col, row, fallbackSuffix)
  if not Theme.CanUseCoinIcons() then
    return fallbackSuffix
  end
  local px1 = col * 64 + 6
  local px2 = (col + 1) * 64 - 6
  local py1 = row * 64 + 6
  local py2 = (row + 1) * 64 - 6
  return string.format(
    "|T%s:12:12:0:0:128:128:%d:%d:%d:%d|t",
    Theme.TEXTURE_PATHS.coinGlyphs,
    px1,
    px2,
    py1,
    py2
  )
end

-- Truthful money formatting (Astra v0.8.0 Section 3):
-- * nil copper -> muted "—" (compact numeric cell) or "Unpriced" (details); NEVER "unk" or "0c".
-- * 0 copper -> "0c" ONLY when copper == 0 is a known zero.
-- * estimated == true -> prefixes "~" for positive/estimated amounts.
function Theme.FormatMoney(copper, opts)
  opts = type(opts) == "table" and opts or {}
  if type(copper) ~= "number" or copper ~= copper then
    local label = opts.compactMissing and "—" or "Unpriced"
    return opts.plainText and label or Theme.Colorize("text.muted", label)
  end

  local n = math.floor(copper + 0.5)
  local neg = ""
  if n < 0 then
    neg = "-"
    n = math.abs(n)
  end

  if n == 0 then
    local cGlyph = opts.plainText and "c" or buildCoinMarkup(0, 1, Theme.Colorize("text.muted", "c"))
    local zeroStr = "0" .. cGlyph
    if opts.colorToken and not opts.plainText then
      return Theme.Colorize(opts.colorToken, "0") .. cGlyph
    end
    return zeroStr
  end

  local g = math.floor(n / 10000)
  local s = math.floor((n % 10000) / 100)
  local c = n % 100

  local gGlyph = opts.plainText and "g" or buildCoinMarkup(0, 0, Theme.Colorize("accent.gold", "g"))
  local sGlyph = opts.plainText and "s" or buildCoinMarkup(1, 0, Theme.Colorize("text.secondary", "s"))
  local cGlyph = opts.plainText and "c" or buildCoinMarkup(0, 1, Theme.Colorize("status.buy", "c"))

  local parts = {}
  if g > 0 then
    table.insert(parts, string.format("%d%s", g, gGlyph))
    if s > 0 or c > 0 then
      table.insert(parts, string.format("%02d%s", s, sGlyph))
    end
    if c > 0 and not opts.omitCopperOverGold then
      table.insert(parts, string.format("%02d%s", c, cGlyph))
    end
  elseif s > 0 then
    table.insert(parts, string.format("%d%s", s, sGlyph))
    if c > 0 then
      table.insert(parts, string.format("%02d%s", c, cGlyph))
    end
  else
    table.insert(parts, string.format("%d%s", c, cGlyph))
  end

  local prefix = (opts.estimated == true) and "~" or ""
  local body = prefix .. neg .. table.concat(parts, " ")
  if opts.colorToken and not opts.plainText then
    return Theme.Colorize(opts.colorToken, prefix .. neg) .. table.concat(parts, " ")
  end
  return body
end

local function srgbChannelToLinear(ch)
  local c = math.max(0.0, math.min(1.0, tonumber(ch) or 0.0))
  if c <= 0.04045 then
    return c / 12.92
  end
  return ((c + 0.055) / 1.055) ^ 2.4
end

function Theme.ComputeContrastRatio(tokenA, tokenB)
  local a = Theme.ResolveToken(tokenA)
  local b = Theme.ResolveToken(tokenB)
  local lumA = 0.2126 * srgbChannelToLinear(a[1]) + 0.7152 * srgbChannelToLinear(a[2]) + 0.0722 * srgbChannelToLinear(a[3])
  local lumB = 0.2126 * srgbChannelToLinear(b[1]) + 0.7152 * srgbChannelToLinear(b[2]) + 0.0722 * srgbChannelToLinear(b[3])
  local lighter = math.max(lumA, lumB)
  local darker = math.min(lumA, lumB)
  return (lighter + 0.05) / (darker + 0.05)
end

function Theme.CanUseSanctuaryChrome()
  if Theme.sanctuaryChromeVerified ~= nil then
    return Theme.sanctuaryChromeVerified
  end
  if type(_G.UIParent) ~= "table" or type(_G.UIParent.CreateTexture) ~= "function" then
    Theme.sanctuaryChromeVerified = false
    return false
  end
  local ok, probe = pcall(_G.UIParent.CreateTexture, _G.UIParent, nil, "BACKGROUND")
  if not ok or type(probe) ~= "table" or type(probe.SetTexture) ~= "function" or type(probe.GetTexture) ~= "function" or type(probe.SetTexCoord) ~= "function" then
    if probe and type(probe.Hide) == "function" then
      pcall(probe.Hide, probe)
    end
    Theme.sanctuaryChromeVerified = false
    return false
  end
  pcall(probe.SetTexture, probe, Theme.TEXTURE_PATHS.sanctuaryChrome)
  local loaded = nil
  local okGet, texVal = pcall(probe.GetTexture, probe)
  if okGet then
    loaded = texVal
  end
  if type(probe.Hide) == "function" then
    pcall(probe.Hide, probe)
  end
  Theme.sanctuaryChromeVerified = (loaded ~= nil)
  return Theme.sanctuaryChromeVerified
end

function Theme.ApplySanctuaryChromeCell(tex, col, row, fallbackToken, alpha)
  if type(tex) ~= "table" then
    return false, "invalid_texture"
  end
  local r, g, b, a = Theme.UnpackRGBA(fallbackToken or "border.gold", alpha)
  if Theme.CanUseSanctuaryChrome() and type(tex.SetTexture) == "function" and type(tex.SetTexCoord) == "function" then
    pcall(tex.SetTexture, tex, Theme.TEXTURE_PATHS.sanctuaryChrome)
    -- Half-texel inset inside the 8px extruded gutter on the 256x256 (4x4 of 64x64) atlas:
    local u1 = (col * 64 + 8.5) / 256.0
    local u2 = ((col + 1) * 64 - 8.5) / 256.0
    local v1 = (row * 64 + 8.5) / 256.0
    local v2 = ((row + 1) * 64 - 8.5) / 256.0
    pcall(tex.SetTexCoord, tex, u1, u2, v1, v2)
    if type(tex.SetVertexColor) == "function" then
      pcall(tex.SetVertexColor, tex, 1, 1, 1, a)
    end
    return true, "atlas_loaded"
  end
  if type(tex.SetColorTexture) == "function" then
    pcall(tex.SetColorTexture, tex, r, g, b, a)
  elseif type(tex.SetTexture) == "function" then
    pcall(tex.SetTexture, tex, r, g, b, a)
  end
  return true, "solid_rgba_fallback"
end

-- Operation-specific UI microbenchmark across 760x520 @ 1.25x, missing-texture fallback, combat lockdown, and resize.
function Theme.RunMicrobenchmarkSuite(opts)
  opts = type(opts) == "table" and opts or {}
  local iterations = math.max(1, math.floor(tonumber(opts.iterations) or 25))
  local clockFn = (type(_G.debugprofilestop) == "function" and _G.debugprofilestop) or nil
  local function nowMs()
    if clockFn then
      return tonumber(clockFn()) or 0
    end
    if type(_G.os) == "table" and type(_G.os.clock) == "function" then
      return _G.os.clock() * 1000.0
    end
    return 0
  end

  local memBeforeKB = (type(_G.collectgarbage) == "function" and tonumber(_G.collectgarbage("count"))) or 0
  local startMs = nowMs()

  local savedScale = nil
  if ns.State and type(ns.State.GetWorkspaceUIState) == "function" then
    local okS, st = pcall(ns.State.GetWorkspaceUIState)
    if okS and type(st) == "table" then
      savedScale = st.textScale
      st.textScale = 1.25
    end
  end

  local savedChrome = Theme.sanctuaryChromeVerified
  Theme.sanctuaryChromeVerified = false -- exercise missing-texture solid RGBA fallback path
  local fallbackTexCalls = 0
  local dummyTex = {
    SetColorTexture = function()
      fallbackTexCalls = fallbackTexCalls + 1
    end,
  }

  local layoutHeights = 0
  local combatCardsChecked = 0
  for i = 1, iterations do
    local okT, mode = Theme.ApplySanctuaryChromeCell(dummyTex, 0, 0, "border.gold", 0.9)
    if not okT or mode ~= "solid_rgba_fallback" then
      error("Expected solid_rgba_fallback when texture unavailable")
    end
    -- Resize sweep from 960x640 down to minimum 760x520 @ 1.25x scale:
    local w = (i % 2 == 1) and 760 or 960
    local h = Theme.EstimateWrappedHeight(
      "Vendor spread — verify purchase · Outlay: 12s 50c · Loss under stated fallback: 0c",
      w - 64,
      "body",
      18,
      8
    )
    layoutHeights = layoutHeights + h
    if ns.UI and ns.UI.CommandDeckPresenter and type(ns.UI.CommandDeckPresenter.Build) == "function" then
      local vm = ns.UI.CommandDeckPresenter.Build({
        nowSeconds = 1763100000 + i,
        level = 60,
        faction = "Alliance",
        classLabel = "Mage",
        inCombat = true,
        reserveSnapshot = { status = "ok", liquidCopper = 500000, protectedCopperNow = 100000, investableCopper = 400000 },
      }, {})
      if vm and vm.inCombat == true and #(vm.cards or {}) == 1 then
        combatCardsChecked = combatCardsChecked + 1
      end
    end
  end

  Theme.sanctuaryChromeVerified = savedChrome
  if ns.State and type(ns.State.GetWorkspaceUIState) == "function" then
    local okS, st = pcall(ns.State.GetWorkspaceUIState)
    if okS and type(st) == "table" then
      st.textScale = savedScale
    end
  end

  local elapsedMs = math.max(0, nowMs() - startMs)
  local memAfterKB = (type(_G.collectgarbage) == "function" and tonumber(_G.collectgarbage("count"))) or memBeforeKB

  return {
    paletteID = Theme.PALETTE_ID,
    iterations = iterations,
    elapsedMs = elapsedMs,
    avgMsPerOp = elapsedMs / iterations,
    memDeltaKB = memAfterKB - memBeforeKB,
    fallbackTexCalls = fallbackTexCalls,
    combatCardsChecked = combatCardsChecked,
    contrastPrimaryOnCard = Theme.ComputeContrastRatio("text.primary", "surface.card"),
    contrastGoldOnCard = Theme.ComputeContrastRatio("accent.gold", "surface.card"),
    contrastCrystalOnCard = Theme.ComputeContrastRatio("accent.crystal", "surface.card"),
    contrastResearchOnCard = Theme.ComputeContrastRatio("status.research", "surface.card"),
    layoutChecksum = layoutHeights,
  }
end
