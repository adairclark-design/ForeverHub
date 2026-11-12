local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.UI = ns.UI or {}

local Theme = ns.UI.Theme
local Widgets = ns.UI.Widgets

local RewardAdvisor = {}
ns.UI.RewardAdvisor = RewardAdvisor

RewardAdvisor.frame = nil
RewardAdvisor.active = false
RewardAdvisor.currentGeneration = 0
RewardAdvisor.activeQuestID = nil
RewardAdvisor.pendingItemsByGeneration = {}
RewardAdvisor.lastEvaluation = nil
RewardAdvisor.staleCallbacksDiscarded = 0

local ADVISOR_WIDTH = 320
local ADVISOR_PADDING = 12 -- 24 vertical total, 296 inner usable width (28 + 8 + 160 + 8 + 92 = 296)
local HEADING_HEIGHT = 22
local SECTION_GAP = 8
local ICON_COL_WIDTH = 28
local COL_GAP = 8
local NAME_COL_WIDTH = 160
local VALUE_COL_WIDTH = 92
local MIN_ROW_HEIGHT = 40

local function resolveItemVisualMeta(choice)
  local tex = choice and choice.texture or nil
  local qual = choice and tonumber(choice.quality) or nil
  local ref = (choice and (choice.itemLink or choice.itemID)) or nil
  if ref and type(_G.GetItemInfo) == "function" then
    local ok, _, _, itemQuality, _, _, _, _, _, _, itemTexture = pcall(_G.GetItemInfo, ref)
    if ok then
      if qual == nil and type(itemQuality) == "number" then
        qual = itemQuality
      end
      if tex == nil and itemTexture ~= nil then
        tex = itemTexture
      end
    end
  end
  if tex == nil and choice and choice.itemID and type(_G.GetItemIcon) == "function" then
    local okI, iconTex = pcall(_G.GetItemIcon, choice.itemID)
    if okI and iconTex then
      tex = iconTex
    end
  end
  return tex, qual
end

local function anchorAdvisorSiblingToQuestFrame(f)
  if not f then
    return
  end
  if f.ClearAllPoints then
    f:ClearAllPoints()
  end
  local qf = _G.QuestFrame
  if not qf then
    f:SetPoint("CENTER", _G.UIParent, "CENTER", 260, 40)
    f.appliedAnchorMode = "center_fallback"
    return
  end

  local screenW = (_G.UIParent and type(_G.UIParent.GetWidth) == "function" and tonumber(_G.UIParent:GetWidth())) or nil
  local qfRight = (type(qf.GetRight) == "function" and tonumber(qf:GetRight())) or nil
  local qfLeft = (type(qf.GetLeft) == "function" and tonumber(qf:GetLeft())) or nil

  if screenW and qfRight and (qfRight + 8 + ADVISOR_WIDTH > screenW - 16) then
    if qfLeft and (qfLeft - 8 - ADVISOR_WIDTH >= 16) then
      f:SetPoint("TOPRIGHT", qf, "TOPLEFT", -8, -16)
      f.appliedAnchorMode = "left"
      return
    end
    f:SetPoint("TOPLEFT", qf, "BOTTOMLEFT", 0, -8)
    f.appliedAnchorMode = "bottom"
    return
  end

  f:SetPoint("TOPLEFT", qf, "TOPRIGHT", 8, -16)
  f.appliedAnchorMode = "right"
end

local function createRewardRow(parent)
  local row = (Widgets and Widgets.CreatePanel and Widgets.CreatePanel(parent, "surface.card", "border.subtle"))
    or CreateFrame("Frame", nil, parent)
  if not row then
    return nil
  end
  row:SetSize(ADVISOR_WIDTH - (ADVISOR_PADDING * 2), MIN_ROW_HEIGHT)

  local accentBar = (Widgets and Widgets.SafeCreateTexture and Widgets.SafeCreateTexture(row, "ARTWORK", 2))
    or (row.CreateTexture and row:CreateTexture(nil, "ARTWORK"))
  if accentBar then
    accentBar:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
    accentBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 1, 1)
    if accentBar.SetSize then accentBar:SetSize(3, MIN_ROW_HEIGHT - 2) end
    if Widgets and Widgets.SafeSetSolidColor then
      Widgets.SafeSetSolidColor(accentBar, "accent.gold", 1.0)
    elseif accentBar.SetColorTexture then
      accentBar:SetColorTexture(0.84, 0.69, 0.42, 1.0)
    end
    if accentBar.Hide then accentBar:Hide() end
  end
  row.accentBar = accentBar

  local iconBox = (Widgets and Widgets.CreateItemIcon and Widgets.CreateItemIcon(row, ICON_COL_WIDTH)) or nil
  if iconBox then
    Widgets.SafeSetPoint(iconBox, "TOPLEFT", row, "TOPLEFT", 0, -6)
  end
  row.iconBox = iconBox

  local nameX = ICON_COL_WIDTH + COL_GAP
  local nameText = (Widgets and Widgets.SafeCreateFontString and Widgets.SafeCreateFontString(row, "body", "text.primary"))
    or row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  if nameText then
    nameText:SetPoint("TOPLEFT", row, "TOPLEFT", nameX, -6)
    if nameText.SetWidth then pcall(nameText.SetWidth, nameText, NAME_COL_WIDTH) end
    if nameText.SetJustifyH then nameText:SetJustifyH("LEFT") end
    if nameText.SetWordWrap then nameText:SetWordWrap(true) end
    nameText:SetText("")
  end
  row.nameText = nameText

  local badgeText = (Widgets and Widgets.SafeCreateFontString and Widgets.SafeCreateFontString(row, "dense", "accent.gold"))
    or row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  if badgeText then
    badgeText:SetPoint("TOPLEFT", row, "TOPLEFT", nameX, -24)
    if badgeText.SetWidth then pcall(badgeText.SetWidth, badgeText, NAME_COL_WIDTH) end
    if badgeText.SetJustifyH then badgeText:SetJustifyH("LEFT") end
    if badgeText.SetWordWrap then badgeText:SetWordWrap(false) end
    badgeText:SetText("")
    if badgeText.Hide then badgeText:Hide() end
  end
  row.badgeText = badgeText

  local valueText = (Widgets and Widgets.SafeCreateFontString and Widgets.SafeCreateFontString(row, "body", "text.primary"))
    or row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  if valueText then
    valueText:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -8)
    if valueText.SetWidth then pcall(valueText.SetWidth, valueText, VALUE_COL_WIDTH) end
    if valueText.SetJustifyH then valueText:SetJustifyH("RIGHT") end
    if valueText.SetWordWrap then valueText:SetWordWrap(false) end
    valueText:SetText("")
  end
  row.valueText = valueText

  return row
end

local function ensureAdvisorFrame()
  if RewardAdvisor.frame then
    return RewardAdvisor.frame
  end
  if type(CreateFrame) ~= "function" then
    return nil
  end

  -- Strictly parented to UIParent as an addon-owned sibling frame (zero taint/overlay on Blizzard buttons!)
  local ok, f = pcall(
    CreateFrame,
    "Frame",
    "ForeverHubRewardAdvisorFrame",
    _G.UIParent,
    BackdropTemplateMixin and "BackdropTemplate" or nil
  )
  if not ok or not f then
    ok, f = pcall(CreateFrame, "Frame", "ForeverHubRewardAdvisorFrame", _G.UIParent)
  end
  if not ok or not f then
    return nil
  end

  f:SetSize(ADVISOR_WIDTH, 148)
  f.__width = ADVISOR_WIDTH
  f.__height = 148
  if f.SetClampedToScreen then
    f:SetClampedToScreen(true)
  end
  if f.SetFrameStrata then
    pcall(f.SetFrameStrata, f, "HIGH")
  end

  if Widgets and Widgets.ApplySurface then
    Widgets.ApplySurface(f, "surface.window", "border.default", 0.96)
  elseif f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8x8",
      edgeFile = "Interface\\Buttons\\WHITE8x8",
      tile = false,
      edgeSize = 1,
      insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    if f.SetBackdropColor then
      f:SetBackdropColor(0.078, 0.090, 0.114, 0.96)
    end
    if f.SetBackdropBorderColor then
      f:SetBackdropBorderColor(0.227, 0.259, 0.314, 1.0)
    end
  end

  anchorAdvisorSiblingToQuestFrame(f)

  local title = (Widgets and Widgets.SafeCreateFontString and Widgets.SafeCreateFontString(f, "sectionTitle", "text.primary"))
    or f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  if title then
    title:SetPoint("TOPLEFT", f, "TOPLEFT", ADVISOR_PADDING, -ADVISOR_PADDING)
    if title.SetJustifyH then title:SetJustifyH("LEFT") end
    title:SetText("Quest Reward Vendor Value")
  end
  f.titleText = title

  local summary = (Widgets and Widgets.SafeCreateFontString and Widgets.SafeCreateFontString(f, "dense", "text.muted"))
    or f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  if summary then
    summary:SetPoint("TOPRIGHT", f, "TOPRIGHT", -ADVISOR_PADDING, -(ADVISOR_PADDING + 3))
    if summary.SetJustifyH then summary:SetJustifyH("RIGHT") end
    summary:SetText("")
  end
  f.summaryText = summary

  local footer = (Widgets and Widgets.SafeCreateFontString and Widgets.SafeCreateFontString(f, "dense", "text.muted"))
    or f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  if footer then
    footer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", ADVISOR_PADDING, ADVISOR_PADDING)
    footer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -ADVISOR_PADDING, ADVISOR_PADDING)
    if footer.SetWidth then pcall(footer.SetWidth, footer, ADVISOR_WIDTH - (ADVISOR_PADDING * 2)) end
    if footer.SetJustifyH then footer:SetJustifyH("LEFT") end
    if footer.SetWordWrap then footer:SetWordWrap(true) end
    footer:SetText("Vendor value only. Choose upgrades first.")
  end
  f.footerText = footer
  -- Backwards-compatible summary mirror if inspected directly
  f.bodyText = footer

  f.rowPool = {}
  f.activeRowHeights = {}

  f:Hide()
  RewardAdvisor.frame = f
  return f
end

local function renderEvaluation(eval)
  local f = ensureAdvisorFrame()
  if not f then
    return
  end

  if not eval or eval.status == "unavailable" or eval.status == "no_choice" then
    f:Hide()
    return
  end

  anchorAdvisorSiblingToQuestFrame(f)

  local usableW = ADVISOR_WIDTH - (ADVISOR_PADDING * 2)
  local statusPill = ""
  local statusTone = "text.muted"
  if eval.status == "partial" then
    statusPill = "PROVISIONAL"
    statusTone = "status.warning"
  elseif eval.status == "loading" then
    statusPill = "LOADING"
    statusTone = "text.muted"
  elseif eval.isTie then
    statusPill = "TIE"
    statusTone = "accent.gold"
  end

  if f.summaryText then
    if Theme and Theme.ApplyFont then
      Theme.ApplyFont(f.summaryText, "dense", statusTone)
    end
    f.summaryText:SetText(statusPill ~= "" and statusPill or "")
  end

  local choices = eval.choices or {}
  local curY = -(ADVISOR_PADDING + HEADING_HEIGHT + SECTION_GAP)
  local sumRowHeights = 0
  f.activeRowHeights = {}

  for idx, c in ipairs(choices) do
    local row = f.rowPool[idx]
    if not row then
      row = createRewardRow(f)
      f.rowPool[idx] = row
    end
    if row then
      local qtySuffix = (c.quantity and c.quantity > 1) and string.format(" ×%d", c.quantity) or ""
      local displayName = tostring(c.name or ("Reward #" .. tostring(c.choiceIndex or idx))) .. qtySuffix

      local badgeLabel = nil
      local badgeTone = "accent.gold"
      if c.isBestVendor then
        if eval.status == "partial" then
          badgeLabel = "PROVISIONAL BEST"
          badgeTone = "status.warning"
        elseif eval.isTie then
          badgeLabel = "TIED BEST"
          badgeTone = "accent.gold"
        else
          badgeLabel = "BEST VENDOR"
          badgeTone = "accent.gold"
        end
      end

      local valueStr
      local valueTone = "text.primary"
      if c.priceState == "ok" and type(c.totalVendorCopper) == "number" then
        if c.totalVendorCopper > 0 then
          valueStr = (Theme and Theme.FormatMoney and Theme.FormatMoney(c.totalVendorCopper))
            or ns.Compat.FormatCopper(c.totalVendorCopper)
          valueTone = c.isBestVendor and "accent.gold" or "text.primary"
        else
          valueStr = "No vendor price"
          valueTone = "text.muted"
        end
      elseif c.priceState == "loading" then
        valueStr = "Loading…"
        valueTone = "text.muted"
      else
        valueStr = "Unpriced"
        valueTone = "text.muted"
      end

      if Widgets and Widgets.ApplySurface then
        if c.isBestVendor then
          Widgets.ApplySurface(row, "surface.selected", eval.status == "partial" and "status.warning" or "accent.gold", 0.98)
        else
          Widgets.ApplySurface(row, "surface.card", "border.subtle", 0.92)
        end
      end
      if row.accentBar then
        if c.isBestVendor then
          if Widgets and Widgets.SafeSetSolidColor then
            Widgets.SafeSetSolidColor(row.accentBar, eval.status == "partial" and "status.warning" or "accent.gold", 1.0)
          end
          if row.accentBar.Show then row.accentBar:Show() end
        elseif row.accentBar.Hide then
          row.accentBar:Hide()
        end
      end

      if row.iconBox and type(row.iconBox.SetItem) == "function" then
        local tex, qual = resolveItemVisualMeta(c)
        row.iconBox:SetItem(tex, qual, c.quantity)
      end

      if row.nameText then
        if Theme and Theme.ApplyFont then
          Theme.ApplyFont(row.nameText, "body", "text.primary")
        end
        row.nameText:SetText(displayName)
      end

      local nameH = (Theme and Theme.MeasureWrappedHeight and Theme.MeasureWrappedHeight(row.nameText, displayName, NAME_COL_WIDTH, "body", 18)) or 18
      local badgeH = 0
      if row.badgeText then
        if badgeLabel then
          badgeH = 14
          if Theme and Theme.ApplyFont then
            Theme.ApplyFont(row.badgeText, "dense", badgeTone)
          end
          if row.badgeText.ClearAllPoints then row.badgeText:ClearAllPoints() end
          row.badgeText:SetPoint("TOPLEFT", row, "TOPLEFT", ICON_COL_WIDTH + COL_GAP, -(6 + nameH + 2))
          row.badgeText:SetText(badgeLabel)
          if row.badgeText.Show then row.badgeText:Show() end
        else
          row.badgeText:SetText("")
          if row.badgeText.Hide then row.badgeText:Hide() end
        end
      end

      if row.valueText then
        if Theme and Theme.ApplyFont then
          Theme.ApplyFont(row.valueText, "body", valueTone)
        end
        row.valueText:SetText(valueStr)
      end

      local innerH = nameH + (badgeH > 0 and (2 + badgeH) or 0) + 12
      local rowH = math.max(MIN_ROW_HEIGHT, innerH)
      row:SetSize(usableW, rowH)
      row.__width = usableW
      row.__height = rowH
      if row.ClearAllPoints then row:ClearAllPoints() end
      row:SetPoint("TOPLEFT", f, "TOPLEFT", ADVISOR_PADDING, curY)
      if row.Show then row:Show() end

      table.insert(f.activeRowHeights, rowH)
      sumRowHeights = sumRowHeights + rowH
      curY = curY - rowH
    end
  end

  for i = #choices + 1, #f.rowPool do
    if f.rowPool[i] and f.rowPool[i].Hide then
      f.rowPool[i]:Hide()
    end
  end

  local footerMsg = (eval.status == "partial")
    and "Provisional while uncached rewards load. Vendor value only. Choose upgrades first."
    or "Vendor value only. Choose upgrades first."
  if f.footerText then
    if Theme and Theme.ApplyFont then
      Theme.ApplyFont(f.footerText, "dense", eval.status == "partial" and "status.warning" or "text.muted")
    end
    f.footerText:SetText(footerMsg)
  end
  local footerHeight = (Theme and Theme.MeasureWrappedHeight and Theme.MeasureWrappedHeight(f.footerText, footerMsg, usableW, "dense", 16)) or 16

  -- Exact Surface E formula: 24 + 22 + 8 + sum(rewardRowHeights) + 8 + footerHeight
  local totalHeight = (ADVISOR_PADDING * 2) + HEADING_HEIGHT + SECTION_GAP + sumRowHeights + SECTION_GAP + footerHeight
  f:SetSize(ADVISOR_WIDTH, totalHeight)
  f.__width = ADVISOR_WIDTH
  f.__height = totalHeight
  f.measuredFooterHeight = footerHeight
  f.measuredRowsHeight = sumRowHeights
  f:Show()
end

-- Triggered on QUEST_COMPLETE.
-- Captures a new monotonic generation, requests uncached item data, and renders addon-owned advice
-- without touching Blizzard reward buttons or auto-selecting rewards (Astra P1-H).
function RewardAdvisor.OnQuestComplete(explicitSnapshot)
  RewardAdvisor.currentGeneration = (RewardAdvisor.currentGeneration or 0) + 1
  local gen = RewardAdvisor.currentGeneration
  RewardAdvisor.active = true

  local snap = explicitSnapshot or ns.Compat.GetQuestRewardChoicesSnapshot()
  RewardAdvisor.activeQuestID = snap and snap.questID or nil

  local eval = ns.Domain.RewardValue.EvaluateRewardChoices(snap)
  RewardAdvisor.lastEvaluation = eval

  local pendingMap = {}
  for _, itemID in ipairs(eval.pendingItemIDs or {}) do
    pendingMap[itemID] = true
    ns.Compat.RequestLoadItemData(itemID)
  end
  RewardAdvisor.pendingItemsByGeneration[gen] = pendingMap

  renderEvaluation(eval)
  return eval, gen
end

-- Handles asynchronous GET_ITEM_INFO_RECEIVED callbacks.
-- Discards late callbacks if the quest window closed, generation advanced, or questID changed!
function RewardAdvisor.OnItemInfoReceived(itemID, success, callbackGeneration, explicitSnapshot)
  itemID = tonumber(itemID)
  if not RewardAdvisor.active then
    RewardAdvisor.staleCallbacksDiscarded = (RewardAdvisor.staleCallbacksDiscarded or 0) + 1
    return false, "inactive_discarded"
  end

  if callbackGeneration ~= nil and callbackGeneration ~= RewardAdvisor.currentGeneration then
    RewardAdvisor.staleCallbacksDiscarded = (RewardAdvisor.staleCallbacksDiscarded or 0) + 1
    return false, "stale_generation_discarded"
  end

  local snap = explicitSnapshot or ns.Compat.GetQuestRewardChoicesSnapshot()
  if RewardAdvisor.activeQuestID ~= nil and snap and snap.questID ~= nil and snap.questID ~= RewardAdvisor.activeQuestID then
    RewardAdvisor.staleCallbacksDiscarded = (RewardAdvisor.staleCallbacksDiscarded or 0) + 1
    return false, "quest_changed_discarded"
  end

  local curPending = RewardAdvisor.pendingItemsByGeneration[RewardAdvisor.currentGeneration]
  if itemID and type(curPending) == "table" and next(curPending) ~= nil and not curPending[itemID] then
    return false, "unrelated_item_ignored"
  end

  if itemID and type(curPending) == "table" then
    curPending[itemID] = nil
  end

  local eval = ns.Domain.RewardValue.EvaluateRewardChoices(snap)
  RewardAdvisor.lastEvaluation = eval
  renderEvaluation(eval)
  return true, eval
end

function RewardAdvisor.OnQuestFinished()
  RewardAdvisor.active = false
  RewardAdvisor.activeQuestID = nil
  RewardAdvisor.currentGeneration = (RewardAdvisor.currentGeneration or 0) + 1
  if RewardAdvisor.frame then
    RewardAdvisor.frame:Hide()
  end
end
