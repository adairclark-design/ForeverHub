local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.UI = ns.UI or {}

local Widgets = ns.UI.Widgets

local MailAdvisor = {
  frame = nil,
  active = false,
  pendingCombatShow = false,
  pendingCombatHide = false,
  lastEvaluation = nil,
}
ns.UI.MailAdvisor = MailAdvisor

local BANNER_WIDTH = 324
local BANNER_PADDING = 10

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

local function anchorToMailFrame(f)
  if not f or isCombatLocked() then
    return
  end
  if f.ClearAllPoints then
    f:ClearAllPoints()
  end
  local mf = _G.MailFrame
  local uiParent = _G.UIParent
  if mf and type(mf.SetPoint) == "function" then
    local fitsRight = true
    if uiParent and type(uiParent.GetWidth) == "function" and type(mf.GetRight) == "function" then
      local okW, screenW = pcall(uiParent.GetWidth, uiParent)
      local okR, rightX = pcall(mf.GetRight, mf)
      if okW and okR and type(screenW) == "number" and type(rightX) == "number" and screenW > 0 then
        fitsRight = (rightX + BANNER_WIDTH + 16) <= screenW
      end
    end
    if fitsRight then
      f:SetPoint("TOPLEFT", mf, "TOPRIGHT", 8, -14)
      f.appliedAnchorMode = "mail_right"
    else
      f:SetPoint("TOPLEFT", mf, "BOTTOMLEFT", 0, -6)
      f.appliedAnchorMode = "mail_below_fallback"
    end
  else
    f:SetPoint("CENTER", uiParent, "CENTER", 250, 40)
    f.appliedAnchorMode = "center_fallback"
  end
end

function MailAdvisor.EnsureFrame()
  if MailAdvisor.frame then
    return MailAdvisor.frame
  end
  if type(CreateFrame) ~= "function" or isCombatLocked() then
    return nil
  end
  -- Strictly parented to `_G.UIParent` (never `MailFrame` / `OpenMailFrame` / `SendMailFrame`):
  local parent = _G.UIParent
  local f = (Widgets and Widgets.CreatePanel and Widgets.CreatePanel(parent, "surface.window", "border.gold"))
    or CreateFrame("Frame", nil, parent)
  if not f then
    return nil
  end
  f.parentedToUIParent = (parent == _G.UIParent)
  if f.SetSize then
    f:SetSize(BANNER_WIDTH, 134)
  end
  if f.SetFrameStrata then
    pcall(f.SetFrameStrata, f, "HIGH")
  end

  f.title = Widgets and Widgets.SafeCreateFontString and Widgets.SafeCreateFontString(f, "sectionTitle", "accent.gold") or nil
  f.codLine = Widgets and Widgets.SafeCreateFontString and Widgets.SafeCreateFontString(f, "body", "status.warning") or nil
  f.sendLine = Widgets and Widgets.SafeCreateFontString and Widgets.SafeCreateFontString(f, "dense", "text.secondary") or nil
  f.noteLine = Widgets and Widgets.SafeCreateFontString and Widgets.SafeCreateFontString(f, "dense", "text.muted") or nil

  local innerW = BANNER_WIDTH - (BANNER_PADDING * 2)
  local y = -BANNER_PADDING
  for _, fs in ipairs({ f.title, f.codLine, f.sendLine, f.noteLine }) do
    if fs then
      if fs.ClearAllPoints then fs:ClearAllPoints() end
      if fs.SetPoint then fs:SetPoint("TOPLEFT", f, "TOPLEFT", BANNER_PADDING, y) end
      if fs.SetWidth then pcall(fs.SetWidth, fs, innerW) end
      if fs.SetJustifyH then pcall(fs.SetJustifyH, fs, "LEFT") end
      if fs.SetWordWrap then pcall(fs.SetWordWrap, fs, true) end
      y = y - 28
    end
  end
  if f.Hide then
    f:Hide()
  end
  MailAdvisor.frame = f
  return f
end

-- Stage 7C Factual Inbox COD & Outgoing SendMail Postage Evaluator:
-- Never hardcodes `30c` postage, never accuses senders of being "scammers", and requires complete fields!
function MailAdvisor.EvaluateMailState(overrides)
  overrides = type(overrides) == "table" and overrides or {}

  local codItems = {}
  local pendingCodRows = 0
  local totalCodCopper = 0

  local rawInbox = overrides.inboxRows
  if type(rawInbox) ~= "table" and type(_G.GetInboxNumItems) == "function" and type(_G.GetInboxHeaderInfo) == "function" then
    rawInbox = {}
    local okN, nItems = pcall(_G.GetInboxNumItems)
    local n = (okN and isNonNegInt(tonumber(nItems))) and math.min(100, math.floor(tonumber(nItems))) or 0
    local getItem = _G.GetInboxItem
    for idx = 1, n do
      local okH, _, _, sender, subject, _, codAmt, _, hasItem = pcall(_G.GetInboxHeaderInfo, idx)
      if not okH or (sender == nil and subject == nil) then
        table.insert(rawInbox, { mailIndex = idx, headerLoaded = false })
      else
        local attName, attCount = nil, nil
        if (hasItem == true or (tonumber(hasItem) or 0) > 0) and type(getItem) == "function" then
          local okA, iName, _, aCnt = pcall(getItem, idx, 1)
          if okA then
            attName = iName
            attCount = tonumber(aCnt)
          end
        end
        table.insert(rawInbox, {
          mailIndex = idx,
          headerLoaded = true,
          sender = sender,
          subject = subject,
          codAmountCopper = codAmt,
          hasItem = hasItem,
          attachmentName = attName,
          attachmentQuantity = attCount,
        })
      end
    end
  end

  for _, r in ipairs(rawInbox or {}) do
    if type(r) == "table" then
      local cod = tonumber(r.codAmountCopper or r.rawCODAmount)
      if r.headerLoaded == false then
        pendingCodRows = pendingCodRows + 1
      elseif isPositiveInt(cod) then
        local attQty = tonumber(r.attachmentQuantity)
        local attName = r.attachmentName
        local senderStr = (type(r.sender) == "string" and r.sender ~= "") and r.sender or nil
        local complete = isPositiveInt(attQty) and (type(attName) == "string" and attName ~= "") and (senderStr ~= nil)
        if not complete then
          pendingCodRows = pendingCodRows + 1
        end
        totalCodCopper = totalCodCopper + cod
        table.insert(codItems, {
          mailIndex = r.mailIndex,
          codAmountCopper = cod,
          attachmentName = complete and attName or nil,
          attachmentQuantity = complete and attQty or nil,
          sender = senderStr,
          fieldsComplete = complete,
        })
      end
    end
  end

  -- Outgoing SendMail factual summary (`GetSendMailPrice()` only — NEVER hardcoded `"30c"`!):
  local outgoing = nil
  local rawOut = overrides.outgoingDraft
  if type(rawOut) ~= "table" and _G.SendMailFrame and type(_G.SendMailFrame.IsShown) == "function" then
    local okS, shown = pcall(_G.SendMailFrame.IsShown, _G.SendMailFrame)
    if okS and shown == true then
      local recip = (_G.SendMailNameEditBox and type(_G.SendMailNameEditBox.GetText) == "function")
          and select(2, pcall(_G.SendMailNameEditBox.GetText, _G.SendMailNameEditBox))
        or nil
      local maxSlots = tonumber(_G.ATTACHMENTS_MAX_SEND) or 12
      local attCount = 0
      if type(_G.GetSendMailItem) == "function" then
        for sIdx = 1, math.min(16, maxSlots) do
          local okSI, itemName = pcall(_G.GetSendMailItem, sIdx)
          if okSI and type(itemName) == "string" and itemName ~= "" then
            attCount = attCount + 1
          end
        end
      end
      local postage = nil
      if type(_G.GetSendMailPrice) == "function" then
        local okP, pVal = pcall(_G.GetSendMailPrice)
        if okP and isNonNegInt(tonumber(pVal)) then
          postage = math.floor(tonumber(pVal))
        end
      end
      rawOut = {
        recipient = recip,
        attachmentSlotCount = attCount,
        verifiedPostageCopper = postage,
      }
    end
  end

  if type(rawOut) == "table" then
    local postageKnown = isNonNegInt(tonumber(rawOut.verifiedPostageCopper))
    outgoing = {
      recipientPresent = (type(rawOut.recipient) == "string" and rawOut.recipient ~= ""),
      recipient = (type(rawOut.recipient) == "string" and rawOut.recipient ~= "") and rawOut.recipient or nil,
      attachmentSlotCount = isNonNegInt(tonumber(rawOut.attachmentSlotCount)) and math.floor(tonumber(rawOut.attachmentSlotCount)) or 0,
      postageKnown = postageKnown,
      verifiedPostageCopper = postageKnown and math.floor(tonumber(rawOut.verifiedPostageCopper)) or nil,
      hardcodedPostageUsed = false,
    }
  end

  local out = {
    codMailCount = #codItems,
    totalCodCopper = totalCodCopper,
    pendingCodRows = pendingCodRows,
    codItems = codItems,
    outgoing = outgoing,
    labelsUnknownSendersScammers = false,
    hardcodes30cPostage = false,
    automatesMailActions = false,
  }
  MailAdvisor.lastEvaluation = out
  return out
end

function MailAdvisor.Render(evalResult)
  local eval = evalResult or MailAdvisor.EvaluateMailState()
  if not eval then
    return nil
  end
  if isCombatLocked() then
    MailAdvisor.pendingCombatShow = true
    return eval
  end
  local f = MailAdvisor.EnsureFrame()
  if not f then
    return eval
  end
  anchorToMailFrame(f)

  if f.title and f.title.SetText then
    f.title:SetText("ForeverHub Mail Check")
  end
  if f.codLine and f.codLine.SetText then
    if eval.codMailCount > 0 then
      local first = eval.codItems[1]
      if first and first.fieldsComplete then
        f.codLine:SetText(
          string.format(
            "COD mail (%d): %s due for %d× %s from %s",
            eval.codMailCount,
            fmtMoney(first.codAmountCopper),
            first.attachmentQuantity,
            tostring(first.attachmentName),
            tostring(first.sender)
          )
        )
      else
        f.codLine:SetText(
          string.format("COD mail (%d): %s total COD · attachment metadata loading", eval.codMailCount, fmtMoney(eval.totalCodCopper))
        )
      end
    else
      f.codLine:SetText("Inbox COD check: 0 Cash-on-Delivery mails detected")
    end
  end

  if f.sendLine and f.sendLine.SetText then
    if eval.outgoing then
      local postTxt = eval.outgoing.postageKnown and fmtMoney(eval.outgoing.verifiedPostageCopper) or "Postage unverified"
      f.sendLine:SetText(
        string.format(
          "Send draft: %d attachment(s) · Recipient: %s · Postage: %s",
          eval.outgoing.attachmentSlotCount or 0,
          eval.outgoing.recipient or "Unset",
          postTxt
        )
      )
    else
      f.sendLine:SetText("Send tab: Open Send Mail to inspect recipient, attachments & client postage")
    end
  end

  if f.noteLine and f.noteLine.SetText then
    f.noteLine:SetText("Read-only visibility · Clicking a COD attachment pays the stated COD amount")
  end

  if f.Show then
    f:Show()
  end
  return eval
end

function MailAdvisor.OnMailShow()
  MailAdvisor.active = true
  MailAdvisor.pendingCombatHide = false
  return MailAdvisor.Render()
end

function MailAdvisor.OnMailUpdated()
  if MailAdvisor.active then
    return MailAdvisor.Render()
  end
  return nil
end

function MailAdvisor.OnMailClosed()
  MailAdvisor.active = false
  MailAdvisor.pendingCombatShow = false
  if isCombatLocked() then
    MailAdvisor.pendingCombatHide = true
    return
  end
  if MailAdvisor.frame and MailAdvisor.frame.Hide then
    MailAdvisor.frame:Hide()
  end
end

function MailAdvisor.FlushDeferredIfReady()
  if isCombatLocked() then
    return
  end
  if MailAdvisor.pendingCombatHide then
    MailAdvisor.pendingCombatHide = false
    MailAdvisor.pendingCombatShow = false
    if MailAdvisor.frame and MailAdvisor.frame.Hide then
      MailAdvisor.frame:Hide()
    end
  elseif MailAdvisor.pendingCombatShow and MailAdvisor.active then
    MailAdvisor.pendingCombatShow = false
    MailAdvisor.Render(MailAdvisor.lastEvaluation)
  end
end

return MailAdvisor
