local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.UI = ns.UI or {}

local Widgets = ns.UI.Widgets

local TrainerAdvisor = {
  frame = nil,
  active = false,
  lastEvaluation = nil,
}
ns.UI.TrainerAdvisor = TrainerAdvisor

local BANNER_WIDTH = 312
local BANNER_PADDING = 12

local function formatCopper(copper)
  if ns.Compat and type(ns.Compat.FormatCopper) == "function" then
    return ns.Compat.FormatCopper(copper)
  end
  return tostring(math.floor(tonumber(copper) or 0)) .. "c"
end

local function anchorToTrainerFrame(f)
  if not f then
    return
  end
  if f.ClearAllPoints then
    f:ClearAllPoints()
  end
  local tf = _G.ClassTrainerFrame
  if tf and type(tf.SetPoint) == "function" then
    f:SetPoint("TOPLEFT", tf, "TOPRIGHT", 8, -14)
    f.appliedAnchorMode = "trainer_right"
  else
    f:SetPoint("CENTER", _G.UIParent, "CENTER", 280, 40)
    f.appliedAnchorMode = "center_fallback"
  end
end

function TrainerAdvisor.EnsureFrame()
  if TrainerAdvisor.frame then
    return TrainerAdvisor.frame
  end
  if type(CreateFrame) ~= "function" then
    return nil
  end
  if type(InCombatLockdown) == "function" and InCombatLockdown() == true then
    TrainerAdvisor.pendingCombatShow = true
    return nil
  end
  -- Astra Section 5 Taint Guardrail: Strictly parented to `_G.UIParent`!
  local parent = _G.UIParent
  local f = (Widgets and Widgets.CreatePanel and Widgets.CreatePanel(parent, "surface.window", "border.gold"))
    or CreateFrame("Frame", nil, parent)
  if not f then
    return nil
  end
  f.parentedToUIParent = (parent == _G.UIParent)
  if f.SetSize then
    f:SetSize(BANNER_WIDTH, 118)
  end
  if f.SetFrameStrata then
    pcall(f.SetFrameStrata, f, "HIGH")
  end

  f.title = Widgets and Widgets.SafeCreateFontString and Widgets.SafeCreateFontString(f, "sectionTitle", "accent.gold") or nil
  f.purseLine = Widgets and Widgets.SafeCreateFontString and Widgets.SafeCreateFontString(f, "body", "text.primary") or nil
  f.noteLine = Widgets and Widgets.SafeCreateFontString and Widgets.SafeCreateFontString(f, "dense", "text.muted") or nil

  local innerW = BANNER_WIDTH - (BANNER_PADDING * 2)
  local y = -BANNER_PADDING
  for _, fs in ipairs({ f.title, f.purseLine, f.noteLine }) do
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
  TrainerAdvisor.frame = f
  return f
end

function TrainerAdvisor.EvaluateCurrentImpact(overrides)
  overrides = type(overrides) == "table" and overrides or {}
  local reservesMod = ns.Domain and ns.Domain.Reserves
  if not reservesMod or type(reservesMod.EvaluateCharacterReserves) ~= "function" then
    return nil
  end
  local snap = reservesMod.EvaluateCharacterReserves(overrides)
  local out = {
    status = snap.status,
    liquidCopper = snap.liquidCopper or 0,
    hasBasicMount = (snap.hasBasicMount == true),
    mountTargetCopper = snap.mountReserveTargetCopper or 0,
    mountShortfallCopper = snap.mountShortfallCopper or 0,
    protectedCopperNow = snap.protectedCopperNow or 0,
    investableCopper = snap.investableCopper or 0,
    prescribesRankSkipping = false,
  }
  TrainerAdvisor.lastEvaluation = out
  return out
end

function TrainerAdvisor.Render(evalResult)
  local eval = evalResult or TrainerAdvisor.EvaluateCurrentImpact()
  if not eval then
    return nil
  end
  local f = TrainerAdvisor.EnsureFrame()
  if not f then
    return eval
  end
  anchorToTrainerFrame(f)

  if f.title and f.title.SetText then
    f.title:SetText("ForeverHub Purse & Mount Reserve")
  end
  if f.purseLine and f.purseLine.SetText then
    if not eval.hasBasicMount and (eval.mountTargetCopper or 0) > 0 then
      f.purseLine:SetText(
        string.format(
          "Purse: %s · Lv 40 riding target: %s (shortfall: %s)",
          formatCopper(eval.liquidCopper),
          formatCopper(eval.mountTargetCopper),
          formatCopper(eval.mountShortfallCopper)
        )
      )
    else
      f.purseLine:SetText(
        string.format(
          "Purse: %s · Protected repair/travel float: %s · Available above reserve: %s",
          formatCopper(eval.liquidCopper),
          formatCopper(eval.protectedCopperNow),
          formatCopper(eval.investableCopper)
        )
      )
    end
  end
  if f.noteLine and f.noteLine.SetText then
    f.noteLine:SetText("Factual purse check only — choose whichever class abilities fit your build.")
  end

  if f.Show then
    f:Show()
  end
  return eval
end

function TrainerAdvisor.OnTrainerShow()
  TrainerAdvisor.active = true
  return TrainerAdvisor.Render()
end

function TrainerAdvisor.OnTrainerClosed()
  TrainerAdvisor.active = false
  TrainerAdvisor.pendingCombatShow = false
  if type(InCombatLockdown) == "function" and InCombatLockdown() == true then
    TrainerAdvisor.pendingCombatHide = true
    return
  end
  if TrainerAdvisor.frame and TrainerAdvisor.frame.Hide then
    TrainerAdvisor.frame:Hide()
  end
end

function TrainerAdvisor.FlushDeferredIfReady()
  if type(InCombatLockdown) == "function" and InCombatLockdown() == true then
    return
  end
  if TrainerAdvisor.pendingCombatHide then
    TrainerAdvisor.pendingCombatHide = false
    TrainerAdvisor.pendingCombatShow = false
    if TrainerAdvisor.frame and TrainerAdvisor.frame.Hide then
      TrainerAdvisor.frame:Hide()
    end
  elseif TrainerAdvisor.pendingCombatShow and TrainerAdvisor.active then
    TrainerAdvisor.pendingCombatShow = false
    TrainerAdvisor.Render(TrainerAdvisor.lastEvaluation)
  end
end

return TrainerAdvisor
