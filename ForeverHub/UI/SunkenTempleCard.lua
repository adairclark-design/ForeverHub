local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.UI = ns.UI or {}

local Theme = ns.UI.Theme
local Widgets = ns.UI.Widgets

local SunkenTempleCard = {
  frame = nil,
  timerTicker = nil,
  lastViewModel = nil,
}
ns.UI.SunkenTempleCard = SunkenTempleCard

local CARD_WIDTH = 356
local CARD_HEIGHT = 122

local function formatElapsedClock(totalSeconds)
  local s = math.max(0, math.floor((tonumber(totalSeconds) or 0) + 0.5))
  local mins = math.floor(s / 60)
  local rem = s % 60
  return string.format("%02d:%02d", mins, rem)
end

local function stopTimerTicker()
  if SunkenTempleCard.timerTicker and type(SunkenTempleCard.timerTicker.Cancel) == "function" then
    pcall(SunkenTempleCard.timerTicker.Cancel, SunkenTempleCard.timerTicker)
  end
  SunkenTempleCard.timerTicker = nil
end

local function ensureTimerTicker(shouldRun)
  if not shouldRun then
    stopTimerTicker()
    return
  end
  if SunkenTempleCard.timerTicker then
    return
  end
  if _G.C_Timer and type(_G.C_Timer.NewTicker) == "function" then
    local ok, handle = pcall(_G.C_Timer.NewTicker, 0.50, function()
      local coach = ns.Domain and ns.Domain.SunkenTempleCoach
      if not coach or coach.state.sessionState ~= "ACTIVE" then
        stopTimerTicker()
        return
      end
      local f = SunkenTempleCard.frame
      if f and f.timerText and type(f.timerText.SetText) == "function" then
        local vm = coach.GetViewModel()
        f.timerText:SetText(formatElapsedClock(vm.elapsedSec))
      end
    end)
    if ok and handle then
      SunkenTempleCard.timerTicker = handle
    end
  end
end

local function setButtonEnabledSafe(btn, enabled)
  if not btn then
    return
  end
  local on = (enabled == true)
  btn.__disabled = not on
  if Widgets and type(Widgets.SetButtonEnabled) == "function" then
    pcall(Widgets.SetButtonEnabled, btn, on)
  else
    if type(btn.SetEnabled) == "function" then
      pcall(btn.SetEnabled, btn, on)
    end
    if type(btn.SetAlpha) == "function" then
      pcall(btn.SetAlpha, btn, on and 1.0 or 0.45)
    end
  end
end

function SunkenTempleCard.EnsureCreated()
  if SunkenTempleCard.frame then
    return SunkenTempleCard.frame
  end
  if not Widgets or type(Widgets.CreatePanel) ~= "function" then
    return nil
  end
  local parent = _G.UIParent
  local card = Widgets.CreatePanel(parent, "surface.elevated", "border.default")
  if not card then
    return nil
  end

  Widgets.SafeSetSize(card, CARD_WIDTH, CARD_HEIGHT)
  Widgets.SafeSetPoint(card, "TOP", parent, "TOP", 0, -96)
  if type(card.SetFrameStrata) == "function" then
    pcall(card.SetFrameStrata, card, "MEDIUM")
  end
  if type(card.SetClampedToScreen) == "function" then
    pcall(card.SetClampedToScreen, card, true)
  end
  if type(card.SetMovable) == "function" then
    pcall(card.SetMovable, card, true)
  end
  if type(card.EnableMouse) == "function" then
    pcall(card.EnableMouse, card, true)
  end
  if type(card.RegisterForDrag) == "function" then
    pcall(card.RegisterForDrag, card, "LeftButton")
  end
  if type(card.SetScript) == "function" then
    pcall(card.SetScript, card, "OnDragStart", function(self)
      if type(self.StartMoving) == "function" then
        pcall(self.StartMoving, self)
      end
    end)
    pcall(card.SetScript, card, "OnDragStop", function(self)
      if type(self.StopMovingOrSizing) == "function" then
        pcall(self.StopMovingOrSizing, self)
      end
    end)
  end

  -- Action icon box (uses indexed QuestGlyphs/UIControls atlas ONLY — NEVER a directional compass chevron, ST-02!)
  local iconBox = Widgets.CreatePanel(card, "surface.inset", "border.subtle")
  if iconBox then
    Widgets.SafeSetSize(iconBox, 28, 28)
    Widgets.SafeSetPoint(iconBox, "TOPLEFT", card, "TOPLEFT", 10, -10)
    card.glyphTex = Widgets.SafeCreateTexture(iconBox, "ARTWORK", 2)
    if card.glyphTex then
      Widgets.SafeSetSize(card.glyphTex, 18, 18)
      Widgets.SafeSetPoint(card.glyphTex, "CENTER", iconBox, "CENTER", 0, 0)
    end
    card.glyphFallback = Widgets.SafeCreateFontString(iconBox, "body", "accent.gold")
    if card.glyphFallback then
      Widgets.SafeSetPoint(card.glyphFallback, "CENTER", iconBox, "CENTER", 0, 0)
    end
    card.iconBox = iconBox
  end

  card.headerText = Widgets.SafeCreateFontString(card, "sectionTitle", "accent.gold")
  if card.headerText then
    Widgets.SafeSetPoint(card.headerText, "TOPLEFT", card, "TOPLEFT", 46, -9)
    if type(card.headerText.SetJustifyH) == "function" then
      pcall(card.headerText.SetJustifyH, card.headerText, "LEFT")
    end
  end

  card.timerText = Widgets.SafeCreateFontString(card, "body", "text.secondary")
  if card.timerText then
    Widgets.SafeSetPoint(card.timerText, "TOPRIGHT", card, "TOPRIGHT", -34, -10)
    if type(card.timerText.SetJustifyH) == "function" then
      pcall(card.timerText.SetJustifyH, card.timerText, "RIGHT")
    end
  end

  local closeBtn = Widgets.CreateIconButton(card, "close", "Hide Maneuver Card", { "Re-open with '/fh st show' or in Dungeons tab." }, 22, 11)
  if closeBtn then
    Widgets.SafeSetPoint(closeBtn, "TOPRIGHT", card, "TOPRIGHT", -8, -8)
    closeBtn:SetOnClick(function()
      if ns.Domain and ns.Domain.SunkenTempleCoach then
        ns.Domain.SunkenTempleCoach.SetHudCardHidden(true)
      end
    end)
    card.closeBtn = closeBtn
  end

  card.landmarkText = Widgets.SafeCreateFontString(card, "body", "text.primary")
  if card.landmarkText then
    Widgets.SafeSetPoint(card.landmarkText, "TOPLEFT", card, "TOPLEFT", 46, -28)
    Widgets.SafeSetPoint(card.landmarkText, "TOPRIGHT", card, "TOPRIGHT", -10, -28)
    if type(card.landmarkText.SetJustifyH) == "function" then
      pcall(card.landmarkText.SetJustifyH, card.landmarkText, "LEFT")
    end
    if type(card.landmarkText.SetWordWrap) == "function" then
      pcall(card.landmarkText.SetWordWrap, card.landmarkText, false)
    end
  end

  card.instructionText = Widgets.SafeCreateFontString(card, "dense", "text.secondary")
  if card.instructionText then
    Widgets.SafeSetPoint(card.instructionText, "TOPLEFT", card, "TOPLEFT", 10, -48)
    Widgets.SafeSetPoint(card.instructionText, "TOPRIGHT", card, "TOPRIGHT", -10, -48)
    if type(card.instructionText.SetJustifyH) == "function" then
      pcall(card.instructionText.SetJustifyH, card.instructionText, "LEFT")
    end
    if type(card.instructionText.SetWordWrap) == "function" then
      pcall(card.instructionText.SetWordWrap, card.instructionText, true)
    end
  end

  -- Deterministic manual controls row (standard unprotected buttons -> work cleanly in combat, ST-05)
  card.primaryActionBtn = Widgets.CreatePrimaryButton(card, 96, "Start", 22)
  if card.primaryActionBtn then
    Widgets.SafeSetPoint(card.primaryActionBtn, "BOTTOMLEFT", card, "BOTTOMLEFT", 10, 8)
  end

  card.prevBtn = Widgets.CreateGhostButton(card, 50, "Prev", 22)
  if card.prevBtn then
    Widgets.SafeSetPoint(card.prevBtn, "LEFT", card.primaryActionBtn, "RIGHT", 4, 0)
    card.prevBtn:SetOnClick(function()
      if card.prevBtn.__disabled then return end
      if ns.Domain and ns.Domain.SunkenTempleCoach then
        ns.Domain.SunkenTempleCoach.PrevPhase()
      end
    end)
  end

  card.nextBtn = Widgets.CreateSecondaryButton(card, 54, "Next", 22)
  if card.nextBtn then
    Widgets.SafeSetPoint(card.nextBtn, "LEFT", card.prevBtn, "RIGHT", 4, 0)
    card.nextBtn:SetOnClick(function()
      if card.nextBtn.__disabled then return end
      if ns.Domain and ns.Domain.SunkenTempleCoach then
        ns.Domain.SunkenTempleCoach.NextPhase()
      end
    end)
  end

  card.abortBtn = Widgets.CreateGhostButton(card, 54, "Abort", 22)
  if card.abortBtn then
    Widgets.SafeSetPoint(card.abortBtn, "LEFT", card.nextBtn, "RIGHT", 4, 0)
    card.abortBtn:SetOnClick(function()
      if card.abortBtn.__disabled then return end
      if ns.Domain and ns.Domain.SunkenTempleCoach then
        ns.Domain.SunkenTempleCoach.AbortAttempt("card_abort")
      end
    end)
  end

  card.probeBtn = Widgets.CreateGhostButton(card, 60, "Probe", 22)
  if card.probeBtn then
    Widgets.SafeSetPoint(card.probeBtn, "BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, 8)
    card.probeBtn:SetOnClick(function()
      if ns.Events and type(ns.Events.HandleSunkenTempleSubcommand) == "function" then
        ns.Events.HandleSunkenTempleSubcommand("probe")
      elseif ns.Domain and ns.Domain.SunkenTempleCoach then
        ns.Domain.SunkenTempleCoach.RunOptInProbe()
      end
    end)
  end

  Widgets.SafeShow(card, false)
  SunkenTempleCard.frame = card
  return card
end

function SunkenTempleCard.Refresh(explicitStepOverride)
  local coach = ns.Domain and ns.Domain.SunkenTempleCoach
  if not coach or type(coach.GetViewModel) ~= "function" then
    stopTimerTicker()
    if SunkenTempleCard.frame then
      Widgets.SafeShow(SunkenTempleCard.frame, false)
    end
    return nil
  end

  local vm = coach.GetViewModel(nil, explicitStepOverride)
  SunkenTempleCard.lastViewModel = vm

  if not vm.cardVisible and explicitStepOverride == nil then
    stopTimerTicker()
    if SunkenTempleCard.frame then
      Widgets.SafeShow(SunkenTempleCard.frame, false)
    end
    return vm
  end

  local card = SunkenTempleCard.EnsureCreated()
  if not card then
    return vm
  end

  local glyphTone = (vm.sessionState == "RECOVERY") and "status.warning"
    or ((vm.sessionState == "ACTIVE") and "status.ready" or "accent.gold")
  Widgets.ApplyGlyph(card.glyphTex, card.glyphFallback, vm.cardGlyph or "info", glyphTone)

  if card.headerText and type(card.headerText.SetText) == "function" then
    card.headerText:SetText(tostring(vm.cardTitle or "Sunken Temple Coach"))
  end
  if card.timerText and type(card.timerText.SetText) == "function" then
    card.timerText:SetText(vm.sessionState == "ACTIVE" and formatElapsedClock(vm.elapsedSec) or "")
  end
  if card.landmarkText and type(card.landmarkText.SetText) == "function" then
    card.landmarkText:SetText(tostring(vm.landmarkLine or ""))
  end
  if card.instructionText and type(card.instructionText.SetText) == "function" then
    card.instructionText:SetText(tostring(vm.instructionLine or ""))
  end

  if card.primaryActionBtn then
    if vm.sessionState == "RECOVERY" then
      if type(card.primaryActionBtn.SetLabel) == "function" then
        card.primaryActionBtn:SetLabel("Rearm Coach")
      elseif type(card.primaryActionBtn.SetText) == "function" then
        card.primaryActionBtn:SetText("Rearm Coach")
      end
      setButtonEnabledSafe(card.primaryActionBtn, vm.canRearm)
      card.primaryActionBtn:SetOnClick(function()
        if card.primaryActionBtn.__disabled then return end
        coach.RearmCoach()
      end)
    elseif vm.sessionState == "ACTIVE" then
      if type(card.primaryActionBtn.SetLabel) == "function" then
        card.primaryActionBtn:SetLabel("Finish")
      elseif type(card.primaryActionBtn.SetText) == "function" then
        card.primaryActionBtn:SetText("Finish")
      end
      setButtonEnabledSafe(card.primaryActionBtn, vm.canFinish)
      card.primaryActionBtn:SetOnClick(function()
        if card.primaryActionBtn.__disabled then return end
        coach.FinishAttempt()
      end)
    else
      if type(card.primaryActionBtn.SetLabel) == "function" then
        card.primaryActionBtn:SetLabel("Start")
      elseif type(card.primaryActionBtn.SetText) == "function" then
        card.primaryActionBtn:SetText("Start")
      end
      setButtonEnabledSafe(card.primaryActionBtn, vm.canStart)
      card.primaryActionBtn:SetOnClick(function()
        if card.primaryActionBtn.__disabled then return end
        coach.StartAttempt()
      end)
    end
  end

  setButtonEnabledSafe(card.prevBtn, vm.canPrev)
  setButtonEnabledSafe(card.nextBtn, vm.canNext)
  setButtonEnabledSafe(card.abortBtn, vm.canAbort)

  ensureTimerTicker(vm.sessionState == "ACTIVE" and vm.cardVisible)
  Widgets.SafeShow(card, vm.cardVisible or (explicitStepOverride ~= nil))
  return vm
end

return SunkenTempleCard
