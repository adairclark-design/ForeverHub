local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.UI = ns.UI or {}

local Theme = ns.UI.Theme
local Widgets = ns.UI.Widgets

local Navigation = {}
ns.UI.Navigation = Navigation

Navigation.frame = nil
Navigation.controllerFrame = nil
Navigation.arrowFrame = nil
Navigation.activeTarget = nil
Navigation.arrowTarget = nil
Navigation._scratchVec = {}
Navigation.travelTicker = nil
Navigation.travelTickerGeneration = 0
Navigation.travelTickerBoundGeneration = nil
Navigation.travelTickerBoundContext = nil
Navigation.suppressHUDCreation = false
Navigation.activeContext = "riverglades"
Navigation.hydratedFromSaved = false
Navigation.pendingDeferredSync = false
Navigation.watchedQuestRef = nil
Navigation.watchedQuestActionID = nil
Navigation.watchedQuestFingerprint = nil
Navigation.questWatchdogAccum = 0
Navigation.questWatchdogActive = false

-- Single shared runtime navigation owner across Riverglades and Gold Farms (Astra P0-1).
Navigation.owner = {
  ownerContext = nil,      -- "riverglades" | "gold_farm" | nil
  generation = 0,          -- monotonic integer incremented on Start/Pause/Stop/context switch
  provider = "none",       -- "none" | "tomtom" | "native_waypoint"
  handle = nil,            -- { uid = ... } or { uiMapID = ..., x01 = ..., y01 = ... }
  pendingRelease = false,  -- true while cleanup is deferred or unconfirmed
  pendingDestination = nil, -- { context = ..., generation = ..., destination = ..., title = ... }
}

Navigation.lastStatus = {
  activeProvider = "none",
  navigationLabel = "Paused",
  hasDirectionalArrow = false,
  deferred = false,
}

local COORD_MATCH_EPSILON = 0.0015
local CUSTOM_UNVERIFIED_ARROW_MAPS = {
  [2548] = true, -- Riverglades custom map: TomTom UID does not prove HBD directional arrow works
}

local function coordsMatch(aMap, aX, aY, bMap, bX, bY)
  if tonumber(aMap) ~= tonumber(bMap) then
    return false
  end
  local ax, ay = tonumber(aX), tonumber(aY)
  local bx, by = tonumber(bX), tonumber(bY)
  if not ax or not ay or not bx or not by then
    return false
  end
  return math.abs(ax - bx) <= COORD_MATCH_EPSILON and math.abs(ay - by) <= COORD_MATCH_EPSILON
end

local function updateDeferredMirror()
  local owner = Navigation.owner
  Navigation.pendingDeferredSync = (owner.pendingRelease == true) or (owner.pendingDestination ~= nil)
end

local function syncProgressMirrorsAndPersist()
  local owner = Navigation.owner
  updateDeferredMirror()
  if ns.State and ns.State.SavePersistedNavigationOwner then
    ns.State.SavePersistedNavigationOwner(owner)
  end
  local rgProg = ns.State and ns.State.GetRouteProgress and ns.State.GetRouteProgress()
  local gfProg = ns.State and ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress()
  local nativeToken = nil
  if owner.provider == "native_waypoint" and type(owner.handle) == "table" then
    nativeToken = {
      provider = "native",
      uiMapID = owner.handle.uiMapID,
      x01 = owner.handle.x01,
      y01 = owner.handle.y01,
    }
  end
  if rgProg then
    rgProg.ownedWaypoint = (owner.ownerContext == "riverglades") and nativeToken or nil
  end
  if gfProg then
    gfProg.ownedWaypoint = (owner.ownerContext == "gold_farm") and nativeToken or nil
  end
end

function Navigation.HydrateOwnerFromSavedStateIfUnset()
  if Navigation.hydratedFromSaved then
    return
  end
  Navigation.hydratedFromSaved = true
  if Navigation.owner.provider ~= "none" or Navigation.owner.handle ~= nil then
    return
  end
  if ns.State and ns.State.GetPersistedNavigationOwner then
    local saved = ns.State.GetPersistedNavigationOwner()
    if type(saved) == "table" then
      local restoredAny = false
      if saved.provider == "native_waypoint" and type(saved.handle) == "table" then
        Navigation.owner.ownerContext = saved.ownerContext
        Navigation.owner.provider = "native_waypoint"
        Navigation.owner.handle = {
          uiMapID = saved.handle.uiMapID,
          x01 = saved.handle.x01,
          y01 = saved.handle.y01,
        }
        Navigation.owner.pendingRelease = (saved.pendingRelease == true)
        restoredAny = true
      end
      if type(saved.pendingDestination) == "table" and type(saved.pendingDestination.destination) == "table" then
        local pd = saved.pendingDestination
        Navigation.owner.pendingDestination = {
          context = pd.context,
          generation = Navigation.owner.generation,
          destination = pd.destination,
          title = pd.title,
        }
        restoredAny = true
      end
      if restoredAny then
        updateDeferredMirror()
        return
      end
    end
  end
  -- Backwards-compatible fallback if a test or old session seeded `progress.ownedWaypoint` directly
  local rgProg = ns.State and ns.State.GetRouteProgress and ns.State.GetRouteProgress()
  if rgProg and type(rgProg.ownedWaypoint) == "table" and rgProg.ownedWaypoint.provider == "native" then
    Navigation.owner.ownerContext = "riverglades"
    Navigation.owner.provider = "native_waypoint"
    Navigation.owner.handle = {
      uiMapID = rgProg.ownedWaypoint.uiMapID,
      x01 = rgProg.ownedWaypoint.x01,
      y01 = rgProg.ownedWaypoint.y01,
    }
    return
  end
  local gfProg = ns.State and ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress()
  if gfProg and type(gfProg.ownedWaypoint) == "table" and gfProg.ownedWaypoint.provider == "native" then
    Navigation.owner.ownerContext = "gold_farm"
    Navigation.owner.provider = "native_waypoint"
    Navigation.owner.handle = {
      uiMapID = gfProg.ownedWaypoint.uiMapID,
      x01 = gfProg.ownedWaypoint.x01,
      y01 = gfProg.ownedWaypoint.y01,
    }
  end
end

function Navigation.BumpGeneration()
  Navigation.owner.generation = (Navigation.owner.generation or 0) + 1
  return Navigation.owner.generation
end

function Navigation.IsGenerationCurrent(expectedGeneration)
  if expectedGeneration == nil then
    return true
  end
  return tonumber(expectedGeneration) == tonumber(Navigation.owner.generation)
end

function Navigation.GetOwnerStateSnapshot()
  local o = Navigation.owner
  return {
    ownerContext = o.ownerContext,
    generation = o.generation,
    provider = o.provider,
    hasHandle = (o.handle ~= nil),
    handle = o.handle,
    pendingRelease = (o.pendingRelease == true),
    hasPendingDestination = (o.pendingDestination ~= nil),
    pendingDestination = o.pendingDestination,
  }
end

function Navigation.StopTravelTicker()
  Navigation.travelTickerGeneration = (Navigation.travelTickerGeneration or 0) + 1
  Navigation.travelTickerBoundGeneration = nil
  Navigation.travelTickerBoundContext = nil
  if Navigation.travelTicker and type(Navigation.travelTicker.Cancel) == "function" then
    pcall(Navigation.travelTicker.Cancel, Navigation.travelTicker)
  end
  Navigation.travelTicker = nil
end

function Navigation.EnsureTravelTicker(shouldRun, context)
  if not shouldRun then
    Navigation.StopTravelTicker()
    return
  end
  local boundCtx = context or Navigation.activeContext
  if Navigation.travelTicker and Navigation.travelTickerBoundContext == boundCtx then
    -- Refresh bound generation across consecutive hop transitions so active polling never self-cancels!
    Navigation.travelTickerBoundGeneration = Navigation.owner.generation
    return
  end
  if Navigation.travelTicker then
    Navigation.StopTravelTicker()
  end
  Navigation.travelTickerGeneration = (Navigation.travelTickerGeneration or 0) + 1
  local tickerSeq = Navigation.travelTickerGeneration
  Navigation.travelTickerBoundGeneration = Navigation.owner.generation
  Navigation.travelTickerBoundContext = boundCtx

  if C_Timer and type(C_Timer.NewTicker) == "function" then
    local ok, ticker = pcall(C_Timer.NewTicker, 0.75, function()
      if tickerSeq ~= Navigation.travelTickerGeneration
        or Navigation.travelTickerBoundContext ~= boundCtx
        or not Navigation.IsGenerationCurrent(Navigation.travelTickerBoundGeneration)
      then
        Navigation.StopTravelTicker()
        return
      end
      if Navigation.activeContext ~= boundCtx then
        Navigation.StopTravelTicker()
        return
      end

      if Navigation.pendingDeferredSync and not ns.Compat.IsInCombat() then
        Navigation.FlushDeferredIfReady()
        if not Navigation.pendingDeferredSync or not Navigation.travelTicker then
          return
        end
      end

      if boundCtx == "gold_farm" then
        local gProg = ns.State and ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress()
        if not gProg or gProg.mode ~= "standalone" then
          Navigation.StopTravelTicker()
          return
        end
        local prevStepID = gProg.currentStepID
        local gEval = ns.Domain.GoldFarms.ReconcileActive(nil, gProg)
        if gEval and gEval.activeStep and gEval.activeStep.stepID ~= prevStepID then
          Navigation.SyncFromGoldFarmEvaluation(gEval, gProg)
          if ns.UI and ns.UI.GoldFarms and ns.UI.GoldFarms.RefreshIfShown then
            ns.UI.GoldFarms.RefreshIfShown()
          end
        elseif not (gEval and gEval.activeStep and (gEval.activeStep.kind == "travel" or gEval.activeStep.kind == "boat_crossing")) then
          Navigation.StopTravelTicker()
        end
        return
      end

      local prog = ns.State and ns.State.GetRouteProgress and ns.State.GetRouteProgress()
      if not prog or prog.mode ~= "standalone" then
        Navigation.StopTravelTicker()
        return
      end
      local prevActionID = prog.currentActionID
      local eval = ns.Domain.RouteProgress.Reconcile()
      if eval and eval.currentActionID ~= prevActionID then
        Navigation.SyncFromEvaluation(eval)
      elseif not (eval and eval.nextAction and eval.nextAction.kind == "travel") then
        Navigation.StopTravelTicker()
      end
    end)
    if ok and ticker then
      Navigation.travelTicker = ticker
    end
  end
end

-- Confirmed release of ForeverHub-owned waypoint resource (Astra P0-1 & Gate 2).
-- NEVER drops ownership token on failed ClearNativeWaypoint(), combat lockdown, or restricted/unavailable reads.
-- Drops token ONLY on confirmed post-clear absence OR confirmed user replacement (leaving user's pin untouched).
function Navigation.TryReleaseOwnedResource(legacyProgressHint)
  Navigation.HydrateOwnerFromSavedStateIfUnset()
  local owner = Navigation.owner

  -- Adopt legacy `progress.ownedWaypoint` if a caller seeded it directly on a progress table
  if owner.provider == "none" and type(legacyProgressHint) == "table" and type(legacyProgressHint.ownedWaypoint) == "table" then
    local ow = legacyProgressHint.ownedWaypoint
    if ow.provider == "native" and ow.uiMapID and ow.x01 and ow.y01 then
      owner.provider = "native_waypoint"
      owner.handle = { uiMapID = ow.uiMapID, x01 = ow.x01, y01 = ow.y01 }
    end
  end

  if owner.provider == "none" or owner.handle == nil then
    owner.provider = "none"
    owner.handle = nil
    owner.pendingRelease = false
    owner.ownerContext = nil
    syncProgressMirrorsAndPersist()
    return true, "already_clean"
  end

  if ns.Compat.IsInCombat() then
    owner.pendingRelease = true
    syncProgressMirrorsAndPersist()
    return false, "deferred_in_combat"
  end

  if owner.provider == "tomtom" then
    if type(_G.TomTom) ~= "table" or type(_G.TomTom.RemoveWaypoint) ~= "function" then
      -- TomTom removal API missing/unavailable: retain ownership token rather than falsely reporting removal!
      owner.pendingRelease = true
      syncProgressMirrorsAndPersist()
      return false, "tomtom_remove_unavailable"
    end
    local ok = pcall(_G.TomTom.RemoveWaypoint, _G.TomTom, owner.handle.uid)
    if not ok then
      owner.pendingRelease = true
      syncProgressMirrorsAndPersist()
      return false, "tomtom_remove_failed"
    end
    owner.provider = "none"
    owner.handle = nil
    owner.pendingRelease = false
    owner.ownerContext = nil
    syncProgressMirrorsAndPersist()
    return true, "confirmed_tomtom_removed"
  end

  if owner.provider == "native_waypoint" then
    local live = ns.Compat.GetNativeWaypoint()
    if live.status ~= "ok" then
      -- Restricted or unavailable read: MUST retain ownership token!
      owner.pendingRelease = true
      syncProgressMirrorsAndPersist()
      return false, "native_read_" .. tostring(live.status)
    end

    if live.hasWaypoint == false then
      owner.provider = "none"
      owner.handle = nil
      owner.pendingRelease = false
      owner.ownerContext = nil
      syncProgressMirrorsAndPersist()
      return true, "confirmed_already_absent"
    end

    if not coordsMatch(live.uiMapID, live.x01, live.y01, owner.handle.uiMapID, owner.handle.x01, owner.handle.y01) then
      -- User replaced ForeverHub's pin: drop our token WITHOUT clearing the user's waypoint!
      owner.provider = "none"
      owner.handle = nil
      owner.pendingRelease = false
      owner.ownerContext = nil
      syncProgressMirrorsAndPersist()
      return true, "confirmed_user_replacement"
    end

    local clearRes = ns.Compat.ClearNativeWaypoint()
    if type(clearRes) ~= "table" or clearRes.status ~= "ok" then
      owner.pendingRelease = true
      syncProgressMirrorsAndPersist()
      return false, (type(clearRes) == "table" and clearRes.reason) or "clear_native_failed"
    end

    local post = ns.Compat.GetNativeWaypoint()
    if post.status == "ok" and post.hasWaypoint == false then
      owner.provider = "none"
      owner.handle = nil
      owner.pendingRelease = false
      owner.ownerContext = nil
      syncProgressMirrorsAndPersist()
      return true, "confirmed_cleared"
    end

    -- Post-clear verification did not confirm removal: retain token!
    owner.pendingRelease = true
    syncProgressMirrorsAndPersist()
    return false, "post_clear_unconfirmed"
  end

  owner.provider = "none"
  owner.handle = nil
  owner.pendingRelease = false
  owner.ownerContext = nil
  syncProgressMirrorsAndPersist()
  return true, "unknown_provider_reset"
end

-- Backwards-compatible wrapper that returns `(released, reason)` and NEVER drops token on failure.
function Navigation.CleanupOwnedWaypoint(progress)
  Navigation.BumpGeneration()
  Navigation.owner.pendingDestination = nil
  updateDeferredMirror()
  local ok, reason = Navigation.TryReleaseOwnedResource(progress)
  updateDeferredMirror()
  if ok and type(progress) == "table" then
    progress.ownedWaypoint = nil
  end
  return ok, reason
end

function Navigation.RequestContextSwitch(targetContext)
  Navigation.HydrateOwnerFromSavedStateIfUnset()
  local gen = Navigation.BumpGeneration()
  Navigation.StopTravelTicker()
  Navigation.ClearArrowTarget()
  Navigation.activeContext = targetContext
  Navigation.owner.pendingDestination = nil
  if Navigation.owner.provider ~= "none" and Navigation.owner.ownerContext ~= targetContext then
    Navigation.owner.pendingRelease = true
    Navigation.TryReleaseOwnedResource()
  end
  updateDeferredMirror()
  return gen
end

local function tryAcquireDestinationForContext(context, dest, titleText)
  Navigation.HydrateOwnerFromSavedStateIfUnset()
  local owner = Navigation.owner

  -- Release-before-acquire across contexts OR when a prior release is still pending
  if owner.pendingRelease or (owner.provider ~= "none" and owner.ownerContext ~= context) then
    local released, relReason = Navigation.TryReleaseOwnedResource()
    if not released then
      return false, "none", relReason or "previous_owner_release_pending"
    end
  end

  -- 1. Try TomTom when verified available
  if type(_G.TomTom) == "table"
    and type(_G.TomTom.AddWaypoint) == "function"
    and type(_G.TomTom.RemoveWaypoint) == "function"
  then
    local mapCheck = ns.Compat.ValidateUiMap(dest.uiMapID)
    if not (mapCheck.status == "ok" and mapCheck.value == false) then
      -- Release any prior ForeverHub resource for this same context before setting new TomTom pin
      if owner.provider ~= "none" then
        local relSame, relSameReason = Navigation.TryReleaseOwnedResource()
        if not relSame then
          return false, "none", relSameReason
        end
      end
      local ok, uid = pcall(_G.TomTom.AddWaypoint, _G.TomTom, dest.uiMapID, dest.x01, dest.y01, {
        title = titleText or "ForeverHub",
        from = "ForeverHub",
        persistent = false,
        minimap = true,
        world = true,
        crazy = true,
      })
      if ok and uid ~= nil and uid ~= false then
        owner.ownerContext = context
        owner.provider = "tomtom"
        owner.handle = { uid = uid, uiMapID = dest.uiMapID, x01 = dest.x01, y01 = dest.y01 }
        owner.pendingRelease = false
        syncProgressMirrorsAndPersist()
        return true, "tomtom", nil
      end
    end
  end

  -- 2. If switching from TomTom to native within same context, release TomTom first
  if owner.provider == "tomtom" then
    local relTT, relTTReason = Navigation.TryReleaseOwnedResource()
    if not relTT then
      return false, "none", relTTReason
    end
  end

  -- 3. Try Blizzard native user waypoint (never overwriting a user-owned pin)
  local canSet = ns.Compat.CanSetNativeWaypoint(dest.uiMapID)
  if canSet.status ~= "ok" or canSet.value ~= true then
    if owner.provider == "native_waypoint" then
      Navigation.TryReleaseOwnedResource()
    end
    return false, "text_manual", canSet.reason or "native_waypoint_unsupported"
  end

  local live = ns.Compat.GetNativeWaypoint()
  if live.status ~= "ok" then
    return false, "text_manual", "native_waypoint_state_" .. tostring(live.status)
  end

  if live.hasWaypoint == true then
    local isOurs = (owner.provider == "native_waypoint")
      and (owner.ownerContext == context)
      and type(owner.handle) == "table"
      and coordsMatch(live.uiMapID, live.x01, live.y01, owner.handle.uiMapID, owner.handle.x01, owner.handle.y01)
    if not isOurs then
      -- User replaced pin (or created their own pin): drop our stale native token if we had one, preserve user's pin!
      if owner.provider == "native_waypoint" then
        owner.provider = "none"
        owner.handle = nil
        owner.pendingRelease = false
        owner.ownerContext = nil
        syncProgressMirrorsAndPersist()
      end
      return false, "text_manual", "preserving_user_waypoint"
    end
  end

  local setRes = ns.Compat.SetNativeWaypoint(dest.uiMapID, dest.x01, dest.y01)
  if setRes.status ~= "ok" then
    return false, "text_manual", setRes.reason or "set_native_failed"
  end

  owner.ownerContext = context
  owner.provider = "native_waypoint"
  owner.handle = {
    uiMapID = dest.uiMapID,
    x01 = dest.x01,
    y01 = dest.y01,
  }
  owner.pendingRelease = false
  syncProgressMirrorsAndPersist()
  return true, "native_waypoint", nil
end

local function shouldQueuePendingDestination(okAcq, reason)
  if okAcq then
    return false
  end
  if Navigation.owner.pendingRelease == true then
    return true
  end
  if reason == "native_waypoint_state_restricted"
    or reason == "native_waypoint_state_unavailable"
    or reason == "set_native_failed"
    or reason == "deferred_in_combat"
  then
    return true
  end
  return false
end

local CUSTOM_ARROW_TEXTURE = "Interface\\AddOns\\ForeverHub\\Textures\\NavigationArrow"
local CLASSIC_ARROW_TEXTURE = "Interface\\MINIMAP\\MinimapArrow"
local ARROW_UPDATE_INTERVAL = 0.033
local ARROW_ROTATION_DEADBAND = math.pi / 90 -- ~2 degrees
local CONTROLLER_POLL_INTERVAL = 0.25 -- 4 Hz independent measurement & RXP handoff controller
local ANCHOR_RETRY_INTERVAL = 1.00 -- bounded retry for incomplete map/world transforms
local QUEST_TRUTH_WATCHDOG_INTERVAL = 1.00 -- 1 Hz active-step & Quest Log truth watchdog
local CAMP_ENTER_RADIUS_YARDS = 35
local CAMP_EXIT_RADIUS_YARDS = 42

local function formatYardsCompact(yards, isCrossZone, includeCrossZoneWord)
  local n = math.max(0, math.floor((tonumber(yards) or 0) + 0.5))
  local prefix = isCrossZone and "~" or ""
  local suffix = (isCrossZone and includeCrossZoneWord) and " yds (straight-line)" or " yds"
  if n >= 1000 then
    local thousands = math.floor(n / 1000)
    local rem = n % 1000
    return string.format("%s%d,%03d%s", prefix, thousands, rem, suffix), n
  end
  return string.format("%s%d%s", prefix, n, suffix), n
end

local function truncateArrowCaption(text, maxChars)
  if ns.Compat and ns.Compat.UTF8Truncate then
    return ns.Compat.UTF8Truncate(text, maxChars or 34)
  end
  local s = tostring(text or "")
  maxChars = maxChars or 34
  if #s <= maxChars then
    return s
  end
  return string.sub(s, 1, maxChars - 1) .. "…"
end

local function resolveActiveArrowTexturePath(settings)
  local style = settings and settings.style or "auto"
  if style == "classic" then
    return CLASSIC_ARROW_TEXTURE, "classic"
  elseif style == "custom" then
    return CUSTOM_ARROW_TEXTURE, "custom"
  end
  if ns.Compat and ns.Compat.HasStartupArrowAsset and ns.Compat.HasStartupArrowAsset() then
    return CUSTOM_ARROW_TEXTURE, "custom"
  end
  -- Hot-reloaded before a full client restart indexed `Textures/NavigationArrow.tga`:
  -- use Blizzard's built-in upward MinimapArrow so `/reload` renders a crisp arrow immediately!
  return CLASSIC_ARROW_TEXTURE, "classic_hotreload_fallback"
end

local function isGrindCampStepKind(kind)
  return kind == "grind" or kind == "grind_camp"
end

local function formatGoldFarmHudStepSuffix(step)
  if not step then
    return ""
  end
  if isGrindCampStepKind(step.kind) then
    return " — Camp Anchor"
  elseif step.kind == "vendor" then
    return " — Vendor & Repair"
  elseif step.kind == "boat_crossing" then
    return " — Boat Pier"
  end
  return ""
end

local function formatHudDistanceSegment(target, vec)
  if not target or not vec then
    return nil
  end
  if type(vec.yards) == "number" and vec.yards >= 0 then
    local fmtStr = formatYardsCompact(vec.yards, vec.isCrossZone == true, true)
    if isGrindCampStepKind(target.stepKind) and target.inCampState then
      return " • In Camp (" .. fmtStr .. ")"
    end
    return " • " .. fmtStr
  elseif vec.status == "different_instance" then
    return " • Different instance/continent"
  end
  return nil
end

local layoutHUDFrame
local updateArrowVisualFromVector
local refreshCapabilityStatusInPlace
local updateTargetHysteresis

local function applyArrowTextureToWidget(widget, settings)
  if not widget or not widget.arrowTex then
    return nil
  end
  local texPath, texMode = resolveActiveArrowTexturePath(settings)
  if widget.appliedTexturePath ~= texPath then
    if widget.arrowTex.SetTexture then
      pcall(widget.arrowTex.SetTexture, widget.arrowTex, texPath)
      if texPath == CUSTOM_ARROW_TEXTURE and type(widget.arrowTex.GetTexture) == "function" and widget.arrowTex:GetTexture() == nil then
        pcall(widget.arrowTex.SetTexture, widget.arrowTex, CLASSIC_ARROW_TEXTURE)
        texPath = CLASSIC_ARROW_TEXTURE
        texMode = "classic_load_fallback"
      end
    end
    widget.appliedTexturePath = texPath
    widget.appliedTextureMode = texMode
  end
  return texMode
end

local function computeOptionalHudFooterStatus(status)
  if type(status) ~= "table" then
    return nil, nil
  end
  if status.activeProvider == "rxp" then
    return "RXP controls navigation", "status.reserved"
  elseif status.deferred == true then
    return "Waypoint deferred", "status.warning"
  elseif status.vectorStatus == "facing_unavailable" then
    return "Manual direction", "status.warning"
  elseif status.arrowDelegated == true then
    return "TomTom arrow delegated", "text.muted"
  elseif status.activeProvider == "text_manual" and status.hasDirectionalArrow ~= true then
    return "Manual direction", "text.muted"
  end
  return nil, nil
end

local function refreshHUDSubtextFromTarget(target, vec)
  local f = Navigation.frame
  if not f or not f.subText or not target or not target.hudCoordPrefix then
    return
  end
  if f.IsShown and not f:IsShown() then
    return
  end
  local distPart = formatHudDistanceSegment(target, vec) or ""
  local fullLine = target.hudCoordPrefix .. distPart .. (target.hudSuffix or "")
  if target.lastHudSubtext ~= fullLine then
    target.lastHudSubtext = fullLine
    f.subText:SetText(fullLine)
    layoutHUDFrame(f, Navigation.lastStatus)
  end
end

Navigation.updateCircuitLatches = Navigation.updateCircuitLatches or {}
Navigation.lastUpdateError = Navigation.lastUpdateError or nil

function Navigation.ResetUpdateCircuitLatches()
  Navigation.updateCircuitLatches = {}
end

local function runGuardedNavUpdate(loopKey, self, elapsed, bodyFn)
  if Navigation.updateCircuitLatches[loopKey] ~= nil then
    if self and type(self.Hide) == "function" then
      pcall(self.Hide, self)
    end
    return
  end
  local ok, traceOrErr = xpcall(
    function()
      bodyFn(self, elapsed)
    end,
    function(err)
      local base = tostring(err)
      if type(_G.debugstack) == "function" then
        local okStack, st = pcall(_G.debugstack, 2, 6, 0)
        if okStack and type(st) == "string" and st ~= "" then
          return base .. "\n" .. st
        end
      end
      return base
    end
  )
  if not ok then
    local record = {
      loop = loopKey,
      error = tostring(traceOrErr),
      timestamp = (type(GetTime) == "function" and GetTime()) or 0,
    }
    Navigation.updateCircuitLatches[loopKey] = record
    Navigation.lastUpdateError = record
    if self and type(self.Hide) == "function" then
      pcall(self.Hide, self)
    end
    if ns.Compat and type(ns.Compat.Print) == "function" then
      local firstLine = string.match(record.error, "^([^\r\n]+)") or record.error
      ns.Compat.Print(
        string.format(
          "|cffff8800[Navigation]|r Suspended '%s' updater after error (run '/fh doctor' for trace): %s",
          tostring(loopKey),
          tostring(firstLine)
        )
      )
    end
  end
end

local function onDockedLaneUpdateBody(self, elapsed)
  local dt = tonumber(elapsed) or 0
  self.elapsedAccum = (self.elapsedAccum or 0) + dt
  if self.elapsedAccum < ARROW_UPDATE_INTERVAL then
    return
  end
  self.elapsedAccum = 0

  local target = Navigation.activeTarget
  if not target or not target.anchor or not target.dockedRendererEnabled then
    if self.Hide then
      self:Hide()
    end
    return
  end

  local vec = ns.Compat.ComputeNavigationVector(target.anchor, Navigation._scratchVec)
  target.lastVecStatus = vec and vec.status or "unavailable"
  updateTargetHysteresis(target, vec)
  updateArrowVisualFromVector(self, target, vec, false, true)
  refreshCapabilityStatusInPlace(target, vec)
end

local function onDockedLaneUpdate(self, elapsed)
  runGuardedNavUpdate("docked", self, elapsed, onDockedLaneUpdateBody)
end

layoutHUDFrame = function(f, status)
  if not f then
    return
  end
  local settings = (ns.State and ns.State.GetArrowSettings and ns.State.GetArrowSettings()) or {}
  local hudW = math.max(
    Theme and Theme.METRICS.hudMinWidth or 280,
    math.min(Theme and Theme.METRICS.hudMaxWidth or 440, math.floor((tonumber(settings.hudWidth) or 340) + 0.5))
  )

  local target = Navigation.activeTarget
  local hasDockedLane = (target ~= nil and target.dockedRendererEnabled == true)
  if f.dockedArrowLane then
    if hasDockedLane then
      applyArrowTextureToWidget(f.dockedArrowLane, settings)
      if f.dockedArrowLane.Show then
        f.dockedArrowLane:Show()
      end
    elseif f.dockedArrowLane.Hide then
      f.dockedArrowLane:Hide()
    end
  end

  local pad = Theme and Theme.METRICS.hudPadding or 12
  local headerH = Theme and Theme.METRICS.hudHeaderHeight or 28
  local bodyLeft = hasDockedLane and (pad + (Theme and Theme.METRICS.hudArrowLaneWidth or 52) + 8) or pad
  local bodyTextWidth = math.max(140, hudW - bodyLeft - pad)

  if f.stepText then
    if f.stepText.ClearAllPoints then f.stepText:ClearAllPoints() end
    f.stepText:SetPoint("TOPLEFT", f, "TOPLEFT", bodyLeft, -(headerH + pad))
    if f.stepText.SetWidth then pcall(f.stepText.SetWidth, f.stepText, bodyTextWidth) end
  end

  local stepStr = (f.stepText and type(f.stepText.GetText) == "function" and f.stepText:GetText()) or ""
  local subStr = (f.subText and type(f.subText.GetText) == "function" and f.subText:GetText()) or ""
  local titleH = Theme and Theme.MeasureWrappedHeight
    and Theme.MeasureWrappedHeight(f.stepText, stepStr, bodyTextWidth, "trackerAction", 20)
    or 20
  local detailH = Theme and Theme.MeasureWrappedHeight
    and Theme.MeasureWrappedHeight(f.subText, subStr, bodyTextWidth, "dense", 16)
    or 16

  if f.subText then
    if f.subText.ClearAllPoints then f.subText:ClearAllPoints() end
    f.subText:SetPoint("TOPLEFT", f, "TOPLEFT", bodyLeft, -(headerH + pad + titleH + 4))
    if f.subText.SetWidth then pcall(f.subText.SetWidth, f.subText, bodyTextWidth) end
  end

  local minBodyH = hasDockedLane and 60 or 42
  local bodyHeight = math.max(minBodyH, titleH + 4 + detailH)

  local footerMsg, footerTone = computeOptionalHudFooterStatus(status)
  local optionalStatusHeight = 0
  if f.statusBar and f.statusText then
    if footerMsg and footerMsg ~= "" then
      optionalStatusHeight = 20
      if Theme and Theme.ApplyFont then
        Theme.ApplyFont(f.statusText, "dense", footerTone or "text.muted")
      end
      f.statusText:SetText(footerMsg)
      if f.statusBar.Show then f.statusBar:Show() end
    else
      f.statusText:SetText("")
      if f.statusBar.Hide then f.statusBar:Hide() end
    end
  end

  if f.dockToggleBtn and f.dockToggleBtn.SetLabel then
    f.dockToggleBtn:SetLabel(settings.dockedInHud ~= false and "Undock floating arrow" or "Dock arrow in HUD")
  end
  if f.lockToggleBtn and f.lockToggleBtn.SetLabel then
    f.lockToggleBtn:SetLabel(settings.hudLocked and "Unlock tracker" or "Lock tracker")
  end

  local hudH = headerH + pad + bodyHeight + pad + optionalStatusHeight
  f:SetSize(hudW, hudH)
  f.__width = hudW
  f.__height = hudH
end

local function createHudMenuRowButton(parent, yOffset, labelText, onClick)
  if Widgets and Widgets.CreateGhostButton then
    local b = Widgets.CreateGhostButton(parent, 164, labelText, 24)
    if b then
      Widgets.SafeSetPoint(b, "TOPLEFT", parent, "TOPLEFT", 6, yOffset)
      if type(b.SetOnClick) == "function" then
        b:SetOnClick(onClick)
      end
      return b
    end
  end
  local okB, b = pcall(CreateFrame, "Button", nil, parent)
  if not okB or not b then
    return nil
  end
  b:SetSize(164, 24)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, yOffset)
  if b.SetText then b:SetText(labelText) end
  b.SetLabel = function(self, txt)
    if self.SetText then self:SetText(txt) end
  end
  if b.SetScript then
    b:SetScript("OnClick", onClick)
  end
  return b
end

local function ensureHUDFrame()
  if Navigation.suppressHUDCreation then
    return nil
  end
  if Navigation.frame then
    return Navigation.frame
  end
  if type(CreateFrame) ~= "function" then
    return nil
  end

  local settings = (ns.State and ns.State.GetArrowSettings and ns.State.GetArrowSettings()) or {}
  local initW = math.max(280, math.min(440, math.floor((tonumber(settings.hudWidth) or 340) + 0.5)))

  local ok, f = pcall(
    CreateFrame,
    "Frame",
    "ForeverHubRivergladesHUD",
    UIParent,
    BackdropTemplateMixin and "BackdropTemplate" or nil
  )
  if not ok or not f then
    ok, f = pcall(CreateFrame, "Frame", "ForeverHubRivergladesHUD", UIParent)
  end
  if not ok or not f then
    return nil
  end

  f:SetSize(initW, 112)
  f.__width = initW
  f.__height = 112
  f:SetPoint(
    settings.hudPoint or "TOP",
    UIParent,
    settings.hudRelativePoint or "TOP",
    tonumber(settings.hudOffsetX) or 0,
    tonumber(settings.hudOffsetY) or -110
  )
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  if f.SetClampedToScreen then
    f:SetClampedToScreen(true)
  end
  if f.SetFrameStrata then
    pcall(f.SetFrameStrata, f, "MEDIUM")
  end

  if Widgets and Widgets.ApplySurface then
    Widgets.ApplySurface(f, "surface.window", "border.default", 0.94)
  elseif f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8x8",
      edgeFile = "Interface\\Buttons\\WHITE8x8",
      tile = false,
      edgeSize = 1,
      insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    if f.SetBackdropColor then
      f:SetBackdropColor(0.063, 0.075, 0.094, 0.88)
    end
    if f.SetBackdropBorderColor then
      f:SetBackdropBorderColor(0.227, 0.259, 0.314, 0.90)
    end
  end

  local function startHudDrag()
    local curSettings = ns.State and ns.State.GetArrowSettings and ns.State.GetArrowSettings()
    if curSettings and curSettings.hudLocked then
      return
    end
    if f.StartMoving then
      f:StartMoving()
    end
  end

  local function stopHudDrag()
    if f.StopMovingOrSizing then
      f:StopMovingOrSizing()
    end
    local curSettings = ns.State and ns.State.GetArrowSettings and ns.State.GetArrowSettings()
    if curSettings and type(f.GetPoint) == "function" then
      local okP, pt, _, relPt, ox, oy = pcall(f.GetPoint, f, 1)
      if okP and type(pt) == "string" then
        curSettings.hudPoint = pt
        curSettings.hudRelativePoint = type(relPt) == "string" and relPt or pt
        curSettings.hudOffsetX = math.floor((tonumber(ox) or 0) + 0.5)
        curSettings.hudOffsetY = math.floor((tonumber(oy) or -110) + 0.5)
      end
    end
  end

  f:SetScript("OnDragStart", startHudDrag)
  f:SetScript("OnDragStop", stopHudDrag)

  -- 1) 28-unit Header Bar (`[Riverglades / Gold Farm]` + `[Pause]` + `[⋯]`)
  local headerBar = (Widgets and Widgets.CreatePanel and Widgets.CreatePanel(f, "surface.card", nil)) or nil
  if headerBar then
    Widgets.SafeSetPoint(headerBar, "TOPLEFT", f, "TOPLEFT", 1, -1)
    Widgets.SafeSetPoint(headerBar, "TOPRIGHT", f, "TOPRIGHT", -1, -1)
    Widgets.SafeSetHeight(headerBar, 27)
    if type(headerBar.EnableMouse) == "function" then pcall(headerBar.EnableMouse, headerBar, true) end
    if type(headerBar.RegisterForDrag) == "function" then pcall(headerBar.RegisterForDrag, headerBar, "LeftButton") end
    if type(headerBar.SetScript) == "function" then
      headerBar:SetScript("OnDragStart", startHudDrag)
      headerBar:SetScript("OnDragStop", stopHudDrag)
    end
    local hdrDiv = Widgets.SafeCreateTexture(headerBar, "BORDER", 2)
    if hdrDiv then
      Widgets.SafeSetPoint(hdrDiv, "BOTTOMLEFT", headerBar, "BOTTOMLEFT", 0, 0)
      Widgets.SafeSetPoint(hdrDiv, "BOTTOMRIGHT", headerBar, "BOTTOMRIGHT", 0, 0)
      Widgets.SafeSetHeight(hdrDiv, 1)
      Widgets.SafeSetSolidColor(hdrDiv, "border.subtle", 0.90)
    end
    local hdrAccent = Widgets.SafeCreateTexture(headerBar, "ARTWORK", 2)
    if hdrAccent then
      Widgets.SafeSetPoint(hdrAccent, "LEFT", headerBar, "LEFT", 10, 0)
      Widgets.SafeSetSize(hdrAccent, 3, 14)
      Widgets.SafeSetSolidColor(hdrAccent, "accent.gold", 1.0)
    end
  end
  f.headerBar = headerBar

  local moreBtn = (Widgets and Widgets.CreateIconButton)
    and Widgets.CreateIconButton(headerBar or f, "more", "Tracker options", { "Skip, step back, dock/undock arrow, hide tracker, or stop navigation." }, 24, 13)
    or CreateFrame("Button", nil, headerBar or f)
  if moreBtn then
    moreBtn:SetSize(24, 24)
    moreBtn:SetPoint("RIGHT", headerBar or f, "RIGHT", -6, 0)
  end
  f.moreBtn = moreBtn

  local pauseBtn = (Widgets and Widgets.CreateIconButton)
    and Widgets.CreateIconButton(headerBar or f, "pause", "Pause navigation", { "Pauses active navigation and releases owned map pin." }, 24, 13)
    or CreateFrame("Button", nil, headerBar or f)
  if pauseBtn then
    pauseBtn:SetSize(24, 24)
    pauseBtn:SetPoint("RIGHT", moreBtn or headerBar or f, moreBtn and "LEFT" or "RIGHT", moreBtn and -4 or -34, 0)
    local onPauseClick = function()
      if Navigation.activeContext == "gold_farm" and ns.Events and ns.Events.HandleGoldSubcommand then
        ns.Events.HandleGoldSubcommand("pause")
      elseif ns.Events and ns.Events.HandleRivergladesSubcommand then
        ns.Events.HandleRivergladesSubcommand("pause")
      end
    end
    if type(pauseBtn.SetOnClick) == "function" then
      pauseBtn:SetOnClick(onPauseClick)
    elseif pauseBtn.SetScript then
      pauseBtn:SetScript("OnClick", onPauseClick)
    end
  end
  f.pauseBtn = pauseBtn

  local header = (Widgets and Widgets.SafeCreateFontString and Widgets.SafeCreateFontString(headerBar or f, "body", "text.primary"))
    or f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  if header then
    header:SetPoint("LEFT", headerBar or f, "LEFT", 18, 0)
    header:SetPoint("RIGHT", pauseBtn or headerBar or f, pauseBtn and "LEFT" or "RIGHT", -6, 0)
    if header.SetJustifyH then header:SetJustifyH("LEFT") end
    if header.SetWordWrap then header:SetWordWrap(false) end
    header:SetText("Riverglades")
  end
  f.headerText = header

  -- 2) Docked 52-wide Arrow Lane (`38x38` NavigationArrow.tga + compact distance label beneath)
  local okLane, dockedLane = pcall(CreateFrame, "Frame", nil, f)
  if okLane and dockedLane and type(dockedLane.CreateTexture) == "function" then
    dockedLane:SetSize(52, 60)
    dockedLane:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -40)
    if dockedLane.EnableMouse then pcall(dockedLane.EnableMouse, dockedLane, false) end

    local dArrowTex = dockedLane:CreateTexture(nil, "ARTWORK")
    dArrowTex:SetSize(38, 38)
    dArrowTex:SetPoint("TOP", dockedLane, "TOP", 0, -1)
    dockedLane.arrowTex = dArrowTex

    local dNonDir = dockedLane:CreateTexture(nil, "ARTWORK")
    dNonDir:SetSize(12, 12)
    dNonDir:SetPoint("CENTER", dockedLane, "TOP", 0, -20)
    if dNonDir.Hide then dNonDir:Hide() end
    dockedLane.nonDirMarker = dNonDir

    local dDist = (Widgets and Widgets.SafeCreateFontString and Widgets.SafeCreateFontString(dockedLane, "dense", "text.secondary"))
      or dockedLane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if dDist then
      dDist:SetPoint("TOP", dockedLane, "TOP", 0, -42)
      if dDist.SetWidth then pcall(dDist.SetWidth, dDist, 56) end
      if dDist.SetJustifyH then dDist:SetJustifyH("CENTER") end
      if dDist.SetWordWrap then dDist:SetWordWrap(false) end
      dDist:SetText("")
    end
    dockedLane.distanceText = dDist

    if dockedLane.SetScript then
      dockedLane:SetScript("OnUpdate", onDockedLaneUpdate)
    end
    if dockedLane.Hide then dockedLane:Hide() end
  end
  f.dockedArrowLane = dockedLane

  -- 3) Wrapped Body Title & Detail Lines
  local stepLine = (Widgets and Widgets.SafeCreateFontString and Widgets.SafeCreateFontString(f, "trackerAction", "text.primary"))
    or f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  if stepLine then
    stepLine:SetPoint("TOPLEFT", f, "TOPLEFT", 72, -40)
    if stepLine.SetJustifyH then stepLine:SetJustifyH("LEFT") end
    if stepLine.SetWordWrap then stepLine:SetWordWrap(true) end
    stepLine:SetText("")
  end
  f.stepText = stepLine

  local subLine = (Widgets and Widgets.SafeCreateFontString and Widgets.SafeCreateFontString(f, "dense", "text.secondary"))
    or f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  if subLine then
    subLine:SetPoint("TOPLEFT", f, "TOPLEFT", 72, -62)
    if subLine.SetJustifyH then subLine:SetJustifyH("LEFT") end
    if subLine.SetWordWrap then subLine:SetWordWrap(true) end
    subLine:SetText("")
  end
  f.subText = subLine

  -- 4) Optional Compact Footer Status Strip (`20` high; hidden unless status needs explanation)
  local statusBar = (Widgets and Widgets.CreatePanel and Widgets.CreatePanel(f, "surface.elevated", nil))
    or CreateFrame("Frame", nil, f)
  if statusBar then
    statusBar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
    statusBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    statusBar:SetSize(initW - 2, 19)
    local stText = (Widgets and Widgets.SafeCreateFontString and Widgets.SafeCreateFontString(statusBar, "dense", "text.muted"))
      or statusBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if stText then
      stText:SetPoint("LEFT", statusBar, "LEFT", 12, 0)
      stText:SetPoint("RIGHT", statusBar, "RIGHT", -12, 0)
      if stText.SetJustifyH then stText:SetJustifyH("LEFT") end
      if stText.SetWordWrap then stText:SetWordWrap(false) end
      stText:SetText("")
    end
    f.statusText = stText
    if statusBar.Hide then statusBar:Hide() end
  end
  f.statusBar = statusBar

  -- 5) Overflow Menu (`[⋯]`: Skip/Next, Prev, Dock/Undock, Lock/Unlock, Open Workspace, Hide Tracker, Stop)
  local overflowMenu = (Widgets and Widgets.CreatePanel and Widgets.CreatePanel(f, "surface.elevated", "border.default"))
    or CreateFrame("Frame", nil, f)
  if overflowMenu then
    overflowMenu:SetSize(176, 188)
    overflowMenu:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -30)
    if type(overflowMenu.SetFrameLevel) == "function" and type(f.GetFrameLevel) == "function" then
      pcall(overflowMenu.SetFrameLevel, overflowMenu, (f:GetFrameLevel() or 10) + 25)
    end
    if type(overflowMenu.EnableMouse) == "function" then
      pcall(overflowMenu.EnableMouse, overflowMenu, true)
    end

    local function closeMenu()
      if overflowMenu.Hide then overflowMenu:Hide() end
    end

    f.nextBtn = createHudMenuRowButton(overflowMenu, -6, "Skip objective", function()
      closeMenu()
      if Navigation.activeContext == "gold_farm" and ns.Events and ns.Events.HandleGoldSubcommand then
        ns.Events.HandleGoldSubcommand("next")
      elseif ns.Events and ns.Events.HandleRivergladesSubcommand then
        ns.Events.HandleRivergladesSubcommand("next")
      end
    end)

    f.prevBtn = createHudMenuRowButton(overflowMenu, -32, "Previous step", function()
      closeMenu()
      if Navigation.activeContext == "gold_farm" and ns.Events and ns.Events.HandleGoldSubcommand then
        ns.Events.HandleGoldSubcommand("prev")
      elseif ns.Events and ns.Events.HandleRivergladesSubcommand then
        ns.Events.HandleRivergladesSubcommand("prev")
      end
    end)

    f.dockToggleBtn = createHudMenuRowButton(overflowMenu, -58, "Undock floating arrow", function()
      closeMenu()
      local cur = ns.State and ns.State.GetArrowSettings and ns.State.GetArrowSettings()
      if cur then
        cur.dockedInHud = not (cur.dockedInHud ~= false)
        Navigation.RefreshArrowSettings()
      end
    end)

    f.lockToggleBtn = createHudMenuRowButton(overflowMenu, -84, "Unlock tracker", function()
      closeMenu()
      local cur = ns.State and ns.State.GetArrowSettings and ns.State.GetArrowSettings()
      if cur then
        cur.hudLocked = not (cur.hudLocked == true)
        layoutHUDFrame(f, Navigation.lastStatus)
      end
    end)

    f.openWorkspaceBtn = createHudMenuRowButton(overflowMenu, -110, "Open Workspace", function()
      closeMenu()
      if ns.UI and ns.UI.Workspace and ns.UI.Workspace.Show then
        ns.UI.Workspace.Show(Navigation.activeContext == "gold_farm" and "gold" or "riverglades")
      end
    end)

    f.hideTrackerBtn = createHudMenuRowButton(overflowMenu, -136, "Hide tracker", function()
      closeMenu()
      local cur = ns.State and ns.State.GetArrowSettings and ns.State.GetArrowSettings()
      if cur then
        cur.hudHidden = true
      end
      f:Hide()
      Navigation.RefreshArrowSettings()
    end)

    f.closeBtn = createHudMenuRowButton(overflowMenu, -162, "Stop navigation", function()
      closeMenu()
      if Navigation.activeContext == "gold_farm" and ns.Events and ns.Events.HandleGoldSubcommand then
        ns.Events.HandleGoldSubcommand("stop")
      elseif ns.Events and ns.Events.HandleRivergladesSubcommand then
        ns.Events.HandleRivergladesSubcommand("stop")
      end
    end)

    if overflowMenu.Hide then overflowMenu:Hide() end
  end
  f.overflowMenu = overflowMenu

  if moreBtn and overflowMenu then
    local onMoreClick = function()
      local shown = (type(overflowMenu.IsShown) == "function" and overflowMenu:IsShown()) or false
      if shown then
        overflowMenu:Hide()
      else
        layoutHUDFrame(f, Navigation.lastStatus)
        overflowMenu:Show()
      end
    end
    if type(moreBtn.SetOnClick) == "function" then
      moreBtn:SetOnClick(onMoreClick)
    elseif moreBtn.SetScript then
      moreBtn:SetScript("OnClick", onMoreClick)
    end
  end

  f:Hide()
  Navigation.frame = f
  return f
end

local function syncArrowMouseInteractivity(af)
  if not af or type(af.EnableMouse) ~= "function" then
    return
  end
  local settings = ns.State and ns.State.GetArrowSettings and ns.State.GetArrowSettings() or nil
  local isShown = (type(af.IsShown) ~= "function") or (af:IsShown() == true)
  local hasVisibleContent = (af.visibleAlpha or 0) > 0
  local isLocked = (settings and settings.locked == true) or false
  -- Locked or invisible arrows are 100% click-through so they never intercept camera turns or world clicks!
  local interactive = isShown and hasVisibleContent and (not isLocked)
  if af.mouseEnabledState ~= interactive then
    af.mouseEnabledState = interactive
    af:EnableMouse(interactive)
  end
end

local function computeClampedParentCenterOffsets(settings)
  local scale = (settings and tonumber(settings.scale)) or 1.0
  local parentW = (UIParent and type(UIParent.GetWidth) == "function") and tonumber(UIParent:GetWidth()) or nil
  local parentH = (UIParent and type(UIParent.GetHeight) == "function") and tonumber(UIParent:GetHeight()) or nil
  local ox = (settings and tonumber(settings.offsetX)) or 0
  local oy = (settings and tonumber(settings.offsetY)) or 135

  if settings and type(settings.normX) == "number" and type(settings.normY) == "number"
    and parentW and parentW > 0 and parentH and parentH > 0
  then
    ox = settings.normX * parentW
    oy = settings.normY * parentH
  end

  if parentW and parentW > 80 and parentH and parentH > 80 then
    local halfW = math.max(0, (parentW * 0.5) - math.ceil(28 * scale))
    local halfH = math.max(0, (parentH * 0.5) - math.ceil(36 * scale))
    ox = math.max(-halfW, math.min(halfW, ox))
    oy = math.max(-halfH, math.min(halfH, oy))
  end

  return math.floor(ox + 0.5), math.floor(oy + 0.5), scale
end

local function applyArrowSettingsToFrame(af)
  if not af then
    return
  end
  local settings = ns.State and ns.State.GetArrowSettings and ns.State.GetArrowSettings() or nil
  local ox, oy, scale = computeClampedParentCenterOffsets(settings)

  -- Outer positioning container (`af`) ALWAYS stays at scale 1.0 in UIParent coordinate space;
  -- scale is applied strictly to the inner `visualRoot` child so drag/anchor math never drifts!
  if af.SetScale then
    af:SetScale(1.0)
  end
  if af.visualRoot and af.visualRoot ~= af and af.visualRoot.SetScale then
    af.visualRoot:SetScale(scale)
  end

  local pt = (settings and settings.normX == nil and settings.point) or "CENTER"
  local relPt = (settings and settings.normX == nil and settings.relativePoint) or "CENTER"
  if af.ClearAllPoints then
    af:ClearAllPoints()
  end
  af:SetPoint(pt, UIParent, relPt, ox, oy)

  applyArrowTextureToWidget(af, settings)
  syncArrowMouseInteractivity(af)
end

updateTargetHysteresis = function(target, vec)
  if not target or not vec or type(vec.yards) ~= "number" then
    if target then
      target.isArrivedState = false
      target.inCampState = false
    end
    return
  end
  local y = vec.yards
  local enterRad = target.arrivalRadiusYards or 15
  local exitRad = enterRad + math.max(4, enterRad * 0.25)
  if target.isArrivedState then
    if y > exitRad then
      target.isArrivedState = false
    end
  else
    if y <= enterRad then
      target.isArrivedState = true
    end
  end

  if isGrindCampStepKind(target.stepKind) then
    if target.inCampState then
      if y > CAMP_EXIT_RADIUS_YARDS then
        target.inCampState = false
      end
    else
      if y <= CAMP_ENTER_RADIUS_YARDS then
        target.inCampState = true
      end
    end
  else
    target.inCampState = false
  end
end

local function setArrowSubwidgetsMode(af, showChevron, showNonDirMarker, nonDirR, nonDirG, nonDirB)
  if af.arrowTex then
    if showChevron then
      if af.arrowTex.Show then af.arrowTex:Show() end
    else
      if af.arrowTex.Hide then af.arrowTex:Hide() end
    end
  end
  if af.nonDirMarker then
    if showNonDirMarker then
      if af.nonDirMarker.SetColorTexture then
        af.nonDirMarker:SetColorTexture(nonDirR or 0.89, nonDirG or 0.66, nonDirB or 0.23, 0.90)
      elseif af.nonDirMarker.SetVertexColor then
        af.nonDirMarker:SetVertexColor(nonDirR or 0.89, nonDirG or 0.66, nonDirB or 0.23, 0.90)
      end
      if af.nonDirMarker.Show then af.nonDirMarker:Show() end
    else
      if af.nonDirMarker.Hide then af.nonDirMarker:Hide() end
    end
  end
end

updateArrowVisualFromVector = function(af, target, vec, force, isCompactDocked)
  if not af or not target then
    return
  end
  if not vec
    or vec.status == "unavailable"
    or vec.status == "missing_transform"
    or vec.status == "different_zone"
  then
    if af.lastPresentationState ~= "hidden" or af.visibleAlpha ~= 0 or force then
      af.lastPresentationState = "hidden"
      af.visibleAlpha = 0
      setArrowSubwidgetsMode(af, false, false)
      if isCompactDocked then
        if af.distanceText then af.distanceText:SetText("—") end
        if af.SetAlpha then af:SetAlpha(0.35) end
      else
        if af.SetAlpha then af:SetAlpha(0) end
        syncArrowMouseInteractivity(af)
      end
    end
    return
  end

  if vec.status == "different_instance" then
    if af.lastPresentationState ~= "different_instance" or af.visibleAlpha ~= 1 or force then
      af.lastPresentationState = "different_instance"
      af.visibleAlpha = 1
      setArrowSubwidgetsMode(af, false, true, 0.42, 0.65, 0.85)
      if af.SetAlpha then
        af:SetAlpha(1)
      end
      local instLabel = isCompactDocked and "Cross-cont" or "|cff6ca6d9Different instance/continent|r"
      af.lastDistanceLabel = instLabel
      if af.distanceText then
        af.distanceText:SetText(instLabel)
      end
      if not isCompactDocked then
        syncArrowMouseInteractivity(af)
      end
    end
    return
  end

  local distStr, intYards = formatYardsCompact(vec.yards or 0, vec.isCrossZone == true, false)

  -- Honest non-directional presentation when `GetPlayerFacing()` is nil/restricted:
  -- Hides directional chevron completely so it NEVER implies "head straight ahead / due North"!
  if vec.status == "facing_unavailable" then
    if af.lastPresentationState ~= "facing_unavailable" or af.lastDisplayedYards ~= intYards or af.visibleAlpha ~= 1 or force then
      af.lastPresentationState = "facing_unavailable"
      af.lastDisplayedYards = intYards
      af.visibleAlpha = 1
      setArrowSubwidgetsMode(af, false, true, 0.89, 0.66, 0.23)
      if af.SetAlpha then
        af:SetAlpha(1)
      end
      local noFaceStr = isCompactDocked and distStr or ("|cffe2a93bFacing unavailable • " .. distStr .. "|r")
      af.lastDistanceLabel = noFaceStr
      if af.distanceText then
        af.distanceText:SetText(noFaceStr)
      end
      if not isCompactDocked then
        syncArrowMouseInteractivity(af)
      end
    end
    return
  end

  -- Full directional vector (`vec.status == "ok"`)
  local inCamp = (isGrindCampStepKind(target.stepKind) and target.inCampState == true)
  local arrivedFlag = (not inCamp) and (target.isArrivedState == true)
  local presState = inCamp and "ok_in_camp" or (arrivedFlag and "ok_arrived" or "ok_travel")
  local desiredAlpha = inCamp and (isCompactDocked and 0.60 or 0.45) or 1.0

  if af.lastPresentationState ~= presState or af.visibleAlpha ~= desiredAlpha or force then
    setArrowSubwidgetsMode(af, true, false)
    af.visibleAlpha = desiredAlpha
    if af.SetAlpha then
      af:SetAlpha(desiredAlpha)
    end
    if not isCompactDocked then
      syncArrowMouseInteractivity(af)
    end
  end

  -- Freeze rotation at near-zero distance (< 2 yds) where bearing is mathematically undefined
  if not vec.nearZeroDistance then
    local rot = vec.rotationRadians or 0
    local prevRot = af.lastRotation
    local rotDelta = prevRot and math.abs((((rot - prevRot) + math.pi) % (math.pi * 2)) - math.pi) or 999
    if force or af.lastPresentationState ~= presState or rotDelta >= ARROW_ROTATION_DEADBAND then
      af.lastRotation = rot
      if af.arrowTex and af.arrowTex.SetRotation then
        af.arrowTex:SetRotation(rot)
      end
    end
  elseif af.lastRotation == nil then
    af.lastRotation = 0
    if af.arrowTex and af.arrowTex.SetRotation then
      af.arrowTex:SetRotation(0)
    end
  end

  local r, g, b = vec.colorR or 1, vec.colorG or 1, vec.colorB or 1
  if inCamp or arrivedFlag then
    r, g, b = 0.36, 0.79, 0.54
  end
  local colorBucket = (inCamp and -2) or (arrivedFlag and -1) or math.floor(((vec.absTurnRadians or 0) / math.pi) * 24 + 0.5)
  if force or af.lastPresentationState ~= presState or af.lastColorKey ~= colorBucket then
    af.lastColorKey = colorBucket
    if af.arrowTex and af.arrowTex.SetVertexColor then
      af.arrowTex:SetVertexColor(r, g, b, 1.0)
    end
  end

  if force or af.lastPresentationState ~= presState or af.lastDisplayedYards ~= intYards then
    af.lastPresentationState = presState
    af.lastDisplayedYards = intYards
    if af.distanceText then
      if inCamp then
        local campStr = isCompactDocked and "|cff5cc98aIn Camp|r" or ("|cff5cc98aIn Camp • " .. distStr .. "|r")
        af.lastDistanceLabel = campStr
        af.distanceText:SetText(campStr)
      elseif arrivedFlag then
        local arrStr = isCompactDocked and "|cff5cc98aArrived|r" or ("|cff5cc98aArrived • " .. distStr .. "|r")
        af.lastDistanceLabel = arrStr
        af.distanceText:SetText(arrStr)
      else
        af.lastDistanceLabel = distStr
        af.distanceText:SetText(distStr)
      end
    end
  end
end

local function isTomTomArrowConfirmedActive()
  local tt = _G.TomTom
  if type(tt) ~= "table" then
    return false
  end
  local ca = _G.TomTomCrazyArrow or tt.crazyArrow
  if type(ca) ~= "table" or type(ca.IsShown) ~= "function" then
    return false
  end
  local okS, shown = pcall(ca.IsShown, ca)
  if not okS or shown ~= true then
    return false
  end
  if type(tt.IsCrazyArrowEmpty) == "function" then
    local okE, isEmpty = pcall(tt.IsCrazyArrowEmpty, tt)
    if okE and isEmpty == true then
      return false
    end
  end
  return true
end

local function buildProviderStatus(provider, dest, fallbackReason, builtinArrowActive, vecStatus)
  local facingMissingSuffix = (vecStatus == "facing_unavailable") and " (Facing Unavailable)" or ""
  if provider == "tomtom" then
    local isCustomMap = dest and CUSTOM_UNVERIFIED_ARROW_MAPS[tonumber(dest.uiMapID) or 0] == true
    if isCustomMap then
      local label = builtinArrowActive and "FH Arrow + TomTom Pin"
        or ("TomTom Pin (Custom Map Arrow Unverified)" .. facingMissingSuffix)
      return {
        activeProvider = "tomtom",
        navigationLabel = label,
        hasDirectionalArrow = (builtinArrowActive == true),
        hasBuiltinArrow = (builtinArrowActive == true),
        arrowDelegated = false,
        vectorStatus = vecStatus,
        deferred = false,
      }
    end
    if builtinArrowActive then
      return {
        activeProvider = "tomtom",
        navigationLabel = "FH Arrow + TomTom Waypoint",
        hasDirectionalArrow = true,
        hasBuiltinArrow = true,
        arrowDelegated = false,
        vectorStatus = vecStatus,
        deferred = false,
      }
    end
    local ttConfirmed = isTomTomArrowConfirmedActive()
    return {
      activeProvider = "tomtom",
      navigationLabel = ttConfirmed and "TomTom Waypoint + Arrow" or "TomTom waypoint; arrow delegated",
      hasDirectionalArrow = ttConfirmed,
      hasBuiltinArrow = false,
      arrowDelegated = true,
      vectorStatus = vecStatus,
      deferred = false,
    }
  elseif provider == "native_waypoint" then
    return {
      activeProvider = "native_waypoint",
      navigationLabel = builtinArrowActive and "Arrow + Pin" or ("Map Pin" .. facingMissingSuffix),
      hasDirectionalArrow = (builtinArrowActive == true),
      hasBuiltinArrow = (builtinArrowActive == true),
      arrowDelegated = false,
      vectorStatus = vecStatus,
      deferred = false,
    }
  elseif provider == "deferred" then
    return {
      activeProvider = "deferred",
      navigationLabel = builtinArrowActive and "Arrow (Pin Deferred)" or ("Deferred (In Combat)" .. facingMissingSuffix),
      hasDirectionalArrow = (builtinArrowActive == true),
      hasBuiltinArrow = (builtinArrowActive == true),
      arrowDelegated = false,
      vectorStatus = vecStatus,
      deferred = true,
    }
  end
  local fallbackLabel = builtinArrowActive and "FH Arrow" or ("Text Destination / Manual" .. facingMissingSuffix)
  if fallbackReason == "preserving_user_waypoint" then
    fallbackLabel = builtinArrowActive and "Arrow (User Pin Kept)" or ("Text Only (User Pin Preserved)" .. facingMissingSuffix)
  elseif fallbackReason and string.find(tostring(fallbackReason), "clear", 1, true) then
    fallbackLabel = builtinArrowActive and "Arrow (Pin Cleanup Pending)" or "Text Only (Prior Pin Cleanup Unconfirmed)"
  elseif fallbackReason and string.find(tostring(fallbackReason), "native_read_", 1, true) then
    fallbackLabel = builtinArrowActive and "Arrow (Pin Restricted)" or "Text Only (Waypoint State Restricted)"
  end
  return {
    activeProvider = "text_manual",
    navigationLabel = fallbackLabel,
    fallbackReason = fallbackReason,
    hasDirectionalArrow = (builtinArrowActive == true),
    hasBuiltinArrow = (builtinArrowActive == true),
    arrowDelegated = false,
    vectorStatus = vecStatus,
    deferred = false,
  }
end

local function refreshHUDHeaderInPlace(target, status)
  local f = Navigation.frame
  if not f or (f.IsShown and not f:IsShown()) or not target then
    return
  end
  if f.headerText and target.hudCleanHeader then
    f.headerText:SetText(target.hudCleanHeader)
  end
  layoutHUDFrame(f, status)
end

refreshCapabilityStatusInPlace = function(target, vec)
  if not target then
    return
  end
  local vecStatus = vec and vec.status or "unavailable"
  local floatingShown = (target.floatingRendererEnabled == true)
    and (Navigation.arrowFrame ~= nil)
    and (type(Navigation.arrowFrame.IsShown) ~= "function" or Navigation.arrowFrame:IsShown() == true)
  local dockedShown = (target.dockedRendererEnabled == true)
    and (Navigation.frame ~= nil and Navigation.frame.dockedArrowLane ~= nil)
  local builtinActive = (floatingShown or dockedShown) and (vecStatus == "ok")
  local ttConfirmed = (target.provider == "tomtom") and isTomTomArrowConfirmedActive() or false
  local capKey = string.format("%s|%s|%s|%s", tostring(target.provider), tostring(builtinActive), tostring(vecStatus), tostring(ttConfirmed))
  if target.lastCapabilityKey == capKey then
    return
  end
  target.lastCapabilityKey = capKey
  local newStatus = buildProviderStatus(target.provider, target, target.fallbackReason, builtinActive, vecStatus)
  if target.queuedDeferred or target.provider == "deferred" then
    newStatus.deferred = true
  end
  Navigation.lastStatus = newStatus
  refreshHUDHeaderInPlace(target, newStatus)
end

local function onArrowFrameUpdateBody(self, elapsed)
  local dt = tonumber(elapsed) or 0
  self.elapsedAccum = (self.elapsedAccum or 0) + dt
  if self.elapsedAccum < ARROW_UPDATE_INTERVAL then
    return
  end
  self.elapsedAccum = 0

  local target = Navigation.activeTarget
  if not target or not target.anchor or not target.floatingRendererEnabled then
    self:Hide()
    return
  end

  local vec = ns.Compat.ComputeNavigationVector(target.anchor, Navigation._scratchVec)
  target.lastVecStatus = vec and vec.status or "unavailable"
  updateTargetHysteresis(target, vec)
  updateArrowVisualFromVector(self, target, vec, false, false)
  refreshCapabilityStatusInPlace(target, vec)
end

local function onArrowFrameUpdate(self, elapsed)
  runGuardedNavUpdate("floating", self, elapsed, onArrowFrameUpdateBody)
end

local function hasActiveProviderOrRxpMonitorableSession()
  if Navigation.activeTarget ~= nil then
    return true
  end
  local gProg = ns.State and ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress()
  if gProg and gProg.mode ~= "paused" then
    return true
  end
  local rProg = ns.State and ns.State.GetRouteProgress and ns.State.GetRouteProgress()
  if rProg and rProg.mode ~= "paused" then
    return true
  end
  return false
end

function Navigation.TickActiveStepWatchdog(stepDt)
  if Navigation.activeContext == "gold_farm" or not Navigation.questWatchdogActive then
    return false
  end
  local rProg = ns.State and ns.State.GetRouteProgress and ns.State.GetRouteProgress()
  if not rProg or rProg.mode ~= "standalone" then
    return false
  end
  if not (ns.Compat and ns.Compat.GetActiveStepTruthFingerprint) then
    return false
  end
  Navigation.questWatchdogAccum = (Navigation.questWatchdogAccum or 0) + (tonumber(stepDt) or 0)
  if Navigation.questWatchdogAccum < QUEST_TRUTH_WATCHDOG_INTERVAL then
    return false
  end
  Navigation.questWatchdogAccum = 0
  local freshFp = ns.Compat.GetActiveStepTruthFingerprint(Navigation.watchedQuestRef, true)
  if freshFp ~= Navigation.watchedQuestFingerprint then
    Navigation.watchedQuestFingerprint = freshFp
    if ns.Events and ns.Events.CaptureQuestFieldTelemetry then
      pcall(ns.Events.CaptureQuestFieldTelemetry, "objective_scan")
    end
    if ns.Events and ns.Events.FlushRouteReconcileNow then
      ns.Events.FlushRouteReconcileNow()
    else
      Navigation.SyncFromEvaluation(nil, rProg)
    end
    return true
  end
  return false
end

local function syncRivergladesQuestWatchBaseline(act, activeStandalone)
  if not activeStandalone then
    Navigation.questWatchdogActive = false
    Navigation.watchedQuestRef = nil
    Navigation.watchedQuestActionID = nil
    Navigation.watchedQuestFingerprint = nil
    Navigation.questWatchdogAccum = 0
    return
  end
  local qref = nil
  local actionID = nil
  if type(act) == "table" then
    qref = (type(act.questKey) == "string" and act.questKey ~= "" and act.questKey) or act.questID
    actionID = act.actionID
  end
  Navigation.questWatchdogActive = true
  Navigation.watchedQuestRef = qref
  Navigation.watchedQuestActionID = actionID
  Navigation.questWatchdogAccum = 0
  if ns.Compat and ns.Compat.GetActiveStepTruthFingerprint then
    Navigation.watchedQuestFingerprint = ns.Compat.GetActiveStepTruthFingerprint(qref, false)
  else
    Navigation.watchedQuestFingerprint = nil
  end
end

local function onControllerFrameUpdateBody(self, elapsed)
  local dt = tonumber(elapsed) or 0
  self.elapsedAccum = (self.elapsedAccum or 0) + dt
  if self.elapsedAccum < CONTROLLER_POLL_INTERVAL then
    return
  end
  local stepDt = self.elapsedAccum
  self.elapsedAccum = 0

  -- 1) Live RXP selection transition check (covers stationary sticky camps & vendors without travelTicker!)
  if Navigation.activeContext == "gold_farm" then
    local gProg = ns.State and ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress()
    if gProg and gProg.mode ~= "paused" and gProg.selectedFarmID
      and ns.Bridges and ns.Bridges.RXPBridge and ns.Bridges.RXPBridge.IsGoldFarmGuideSelected
    then
      local rxpNow = (ns.Bridges.RXPBridge.IsGoldFarmGuideSelected(gProg.selectedFarmID) == true)
      if (gProg.mode == "rxp") ~= rxpNow then
        Navigation.SyncFromGoldFarmEvaluation(nil, gProg)
        return
      end
    end
  else
    local rProg = ns.State and ns.State.GetRouteProgress and ns.State.GetRouteProgress()
    if rProg and rProg.mode ~= "paused"
      and ns.Bridges and ns.Bridges.RXPBridge and ns.Bridges.RXPBridge.IsRivergladesGuideSelected
    then
      local rxpNow = (ns.Bridges.RXPBridge.IsRivergladesGuideSelected() == true)
      if (rProg.mode == "rxp") ~= rxpNow then
        Navigation.SyncFromEvaluation(nil, rProg)
        return
      end
    end
    -- 1b) 1 Hz Active-Step & Quest Log Truth Watchdog: guarantees real-time advancement even if WoW: Forever drops or delays quest events
    if Navigation.TickActiveStepWatchdog(stepDt) then
      return
    end
  end

  local target = Navigation.activeTarget
  if not target then
    if not hasActiveProviderOrRxpMonitorableSession() then
      self:Hide()
    end
    return
  end

  -- 2) Independent 4 Hz HUD yard measurement + bounded retry for failed/incomplete transforms (`P1 #2`)
  local vec = ns.Compat.ComputeNavigationVector(target.anchor, Navigation._scratchVec)
  local distanceResolved = (vec and (vec.status == "ok" or vec.status == "facing_unavailable")) or false
  local needsTransformRetry = (not target.anchor)
    or (not target.anchor.isUsable)
    or (not target.anchor.isComplete and not distanceResolved)
  if needsTransformRetry
    and (target.anchorRetryCount or 0) < 6
    and ns.Compat and ns.Compat.ResolveTargetWorldAnchor
  then
    target.anchorRetryAccum = (target.anchorRetryAccum or 0) + stepDt
    if target.anchorRetryAccum >= ANCHOR_RETRY_INTERVAL then
      target.anchorRetryAccum = 0
      target.anchorRetryCount = (target.anchorRetryCount or 0) + 1
      local refreshed = ns.Compat.ResolveTargetWorldAnchor(target.uiMapID, target.x01, target.y01, target.arrivalRadiusYards)
      if refreshed and (refreshed.isUsable or not target.anchor) then
        target.anchor = refreshed
        vec = ns.Compat.ComputeNavigationVector(target.anchor, Navigation._scratchVec)
      end
    end
  end

  target.lastVecStatus = vec and vec.status or "unavailable"
  updateTargetHysteresis(target, vec)
  refreshHUDSubtextFromTarget(target, vec)
  refreshCapabilityStatusInPlace(target, vec)
  if target.dockedRendererEnabled and Navigation.frame and Navigation.frame.dockedArrowLane then
    updateArrowVisualFromVector(Navigation.frame.dockedArrowLane, target, vec, false, true)
  end
  if target.floatingRendererEnabled and Navigation.arrowFrame and Navigation.arrowFrame:IsShown() then
    updateArrowVisualFromVector(Navigation.arrowFrame, target, vec, false, false)
  end
end

local function onControllerFrameUpdate(self, elapsed)
  runGuardedNavUpdate("controller", self, elapsed, onControllerFrameUpdateBody)
end

local function ensureControllerFrame()
  if Navigation.suppressHUDCreation then
    return nil
  end
  if Navigation.controllerFrame then
    return Navigation.controllerFrame
  end
  if type(CreateFrame) ~= "function" then
    return nil
  end
  local ok, cf = pcall(CreateFrame, "Frame", "ForeverHubNavigationController", UIParent)
  if not ok or not cf then
    return nil
  end
  cf.elapsedAccum = 0
  cf:SetScript("OnUpdate", onControllerFrameUpdate)
  cf:Hide()
  Navigation.controllerFrame = cf
  return cf
end

local function syncControllerActivity()
  local cf = Navigation.controllerFrame
  if hasActiveProviderOrRxpMonitorableSession() then
    cf = cf or ensureControllerFrame()
    if cf then
      cf.elapsedAccum = 0
      cf:Show()
    end
  elseif cf then
    cf:Hide()
  end
end

local function ensureArrowFrame()
  if Navigation.suppressHUDCreation then
    return nil
  end
  if Navigation.arrowFrame then
    return Navigation.arrowFrame
  end
  if type(CreateFrame) ~= "function" then
    return nil
  end

  local ok, af = pcall(CreateFrame, "Frame", "ForeverHubNavigationArrow", UIParent)
  if not ok or not af or type(af.CreateTexture) ~= "function" then
    if af and af.Hide then
      af:Hide()
    end
    return nil
  end

  af:SetSize(46, 46)
  af:SetMovable(true)
  af:EnableMouse(false)
  af.mouseEnabledState = false
  af:RegisterForDrag("LeftButton")
  if af.SetClampedToScreen then
    af:SetClampedToScreen(true)
  end
  if af.SetFrameStrata then
    af:SetFrameStrata("HIGH")
  end

  local okChild, visualRoot = pcall(CreateFrame, "Frame", nil, af)
  if okChild and visualRoot and type(visualRoot.CreateTexture) == "function" then
    visualRoot:SetSize(46, 46)
    visualRoot:SetPoint("CENTER", af, "CENTER", 0, 0)
    if visualRoot.EnableMouse then
      visualRoot:EnableMouse(false)
    end
  else
    visualRoot = af
  end
  af.visualRoot = visualRoot
  af.GetVisualScale = function(self)
    if self.visualRoot and self.visualRoot.GetScale then
      return self.visualRoot:GetScale()
    end
    return self.GetScale and self:GetScale() or 1.0
  end

  local arrowTex = visualRoot:CreateTexture(nil, "ARTWORK")
  arrowTex:SetSize(42, 42)
  arrowTex:SetPoint("TOP", visualRoot, "TOP", 0, -2)
  af.arrowTex = arrowTex

  local nonDirMarker = visualRoot:CreateTexture(nil, "ARTWORK")
  nonDirMarker:SetSize(14, 14)
  nonDirMarker:SetPoint("CENTER", visualRoot, "TOP", 0, -23)
  if nonDirMarker.Hide then
    nonDirMarker:Hide()
  end
  af.nonDirMarker = nonDirMarker

  local distText = visualRoot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  distText:SetPoint("TOP", visualRoot, "TOP", 0, -47)
  distText:SetJustifyH("CENTER")
  if distText.GetFont and distText.SetFont then
    local fontPath, fontSize = distText:GetFont()
    if fontPath then
      pcall(distText.SetFont, distText, fontPath, math.max(12, tonumber(fontSize) or 12), "OUTLINE")
    end
  end
  if distText.SetTextColor then
    distText:SetTextColor(1.0, 0.96, 0.84, 1.0)
  end
  distText:SetText("")
  af.distanceText = distText

  local captionText = visualRoot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  captionText:SetPoint("TOP", distText, "BOTTOM", 0, -2)
  captionText:SetJustifyH("CENTER")
  if captionText.GetFont and captionText.SetFont then
    local fontPath, fontSize = captionText:GetFont()
    if fontPath then
      pcall(captionText.SetFont, captionText, fontPath, math.max(10, tonumber(fontSize) or 10), "OUTLINE")
    end
  end
  if captionText.SetTextColor then
    captionText:SetTextColor(0.82, 0.90, 0.98, 0.95)
  end
  captionText:SetText("")
  af.captionText = captionText

  af:SetScript("OnDragStart", function(self)
    local settings = ns.State and ns.State.GetArrowSettings and ns.State.GetArrowSettings()
    if settings and settings.locked then
      return
    end
    if self.StartMoving then
      self.isMoving = true
      self:StartMoving()
    end
  end)

  af:SetScript("OnDragStop", function(self)
    if self.isMoving and self.StopMovingOrSizing then
      self:StopMovingOrSizing()
      self.isMoving = false
    end
    local settings = ns.State and ns.State.GetArrowSettings and ns.State.GetArrowSettings()
    if not settings then
      return
    end
    local savedViaCenter = false
    if type(self.GetCenter) == "function"
      and UIParent
      and type(UIParent.GetCenter) == "function"
      and type(UIParent.GetWidth) == "function"
      and type(UIParent.GetHeight) == "function"
    then
      local cx, cy = self:GetCenter()
      local px, py = UIParent:GetCenter()
      local pw, ph = UIParent:GetWidth(), UIParent:GetHeight()
      if cx and cy and px and py and pw and pw > 0 and ph and ph > 0 then
        local rawOx = cx - px
        local rawOy = cy - py
        settings.normX = math.max(-0.5, math.min(0.5, rawOx / pw))
        settings.normY = math.max(-0.5, math.min(0.5, rawOy / ph))
        local clampedOx, clampedOy = computeClampedParentCenterOffsets(settings)
        settings.point = "CENTER"
        settings.relativePoint = "CENTER"
        settings.offsetX = clampedOx
        settings.offsetY = clampedOy
        settings.normX = clampedOx / pw
        settings.normY = clampedOy / ph
        savedViaCenter = true
      end
    end
    if not savedViaCenter and self.GetPoint then
      local pt, _, relPt, ox, oy = self:GetPoint(1)
      if pt and relPt and type(ox) == "number" and type(oy) == "number" then
        settings.point = pt
        settings.relativePoint = relPt
        settings.offsetX = math.floor(ox + 0.5)
        settings.offsetY = math.floor(oy + 0.5)
        settings.normX = nil
        settings.normY = nil
      end
    end
    applyArrowSettingsToFrame(self)
  end)

  af:SetScript("OnHide", function(self)
    if self.isMoving and self.StopMovingOrSizing then
      self:StopMovingOrSizing()
      self.isMoving = false
    end
    self.mouseEnabledState = false
    if self.EnableMouse then
      self:EnableMouse(false)
    end
  end)

  af:SetScript("OnEnter", function(self)
    if not _G.GameTooltip or (_G.GameTooltip.IsForbidden and _G.GameTooltip:IsForbidden()) then
      return
    end
    local t = Navigation.activeTarget
    if not t then
      return
    end
    _G.GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -28)
    _G.GameTooltip:ClearLines()
    _G.GameTooltip:AddLine("ForeverHub Navigation Arrow", 0.22, 0.74, 0.97)
    if t.title and t.title ~= "" then
      _G.GameTooltip:AddLine(tostring(t.title), 1, 1, 1, true)
    end
    if t.coordSummary and t.coordSummary ~= "" then
      _G.GameTooltip:AddLine(tostring(t.coordSummary), 0.95, 0.82, 0.35)
    end
    if isGrindCampStepKind(t.stepKind) then
      _G.GameTooltip:AddLine("Standalone mode points to Camp Anchor (auto-dims inside camp).", 0.65, 0.92, 0.75, true)
    end
    local settings = ns.State and ns.State.GetArrowSettings and ns.State.GetArrowSettings()
    local dragHint = (settings and settings.locked) and "Locked (/fh arrow unlock to move)" or "Left-drag to move • /fh arrow lock"
    _G.GameTooltip:AddLine(dragHint, 0.65, 0.72, 0.82)
    _G.GameTooltip:Show()
  end)

  af:SetScript("OnLeave", function()
    if _G.GameTooltip and (not _G.GameTooltip.IsForbidden or not _G.GameTooltip:IsForbidden()) then
      _G.GameTooltip:Hide()
    end
  end)

  af:SetScript("OnUpdate", onArrowFrameUpdate)
  applyArrowSettingsToFrame(af)
  af:Hide()
  Navigation.arrowFrame = af
  return af
end

function Navigation.ClearArrowTarget()
  Navigation.ResetUpdateCircuitLatches()
  Navigation.activeTarget = nil
  Navigation.arrowTarget = nil
  if Navigation.arrowFrame then
    Navigation.arrowFrame:Hide()
  end
  if Navigation.frame and Navigation.frame.dockedArrowLane and Navigation.frame.dockedArrowLane.Hide then
    Navigation.frame.dockedArrowLane:Hide()
  end
  syncControllerActivity()
end

function Navigation.InvalidateTargetAnchor()
  local t = Navigation.activeTarget
  if not t then
    return
  end
  if ns.Compat and ns.Compat.ResolveTargetWorldAnchor then
    t.anchor = ns.Compat.ResolveTargetWorldAnchor(t.uiMapID, t.x01, t.y01, t.arrivalRadiusYards)
    t.anchorRetryAccum = 0
    t.anchorRetryCount = 0
  else
    t.anchor = nil
  end
end

local function shouldUseBuiltinArrowForProvider(provider, dest)
  if not dest then
    return false
  end
  if provider == "rxp" or provider == "none" then
    return false
  end
  local settings = ns.State and ns.State.GetArrowSettings and ns.State.GetArrowSettings()
  local renderer = settings and settings.renderer or "auto"
  if (settings and settings.enabled == false) or renderer == "off" or renderer == "tomtom" then
    return false
  end
  if renderer == "foreverhub" or (settings and settings.showWhenTomTomActive == true) then
    return true
  end
  if provider == "tomtom" then
    local isCustomMap = CUSTOM_UNVERIFIED_ARROW_MAPS[tonumber(dest.uiMapID) or 0] == true
    if not isCustomMap then
      return false
    end
  end
  return true
end

local function resolveArrowRenderers(builtinDesired)
  if not builtinDesired then
    return false, false
  end
  local settings = ns.State and ns.State.GetArrowSettings and ns.State.GetArrowSettings() or {}
  local wantDocked = (settings.dockedInHud ~= false)
    and (settings.hudHidden ~= true)
    and (not Navigation.suppressHUDCreation)
  if wantDocked then
    return true, false
  end
  return false, true
end

function Navigation.SetArrowTarget(
  context,
  dest,
  titleText,
  captionLabel,
  arrivalRadiusYards,
  provider,
  hudCoordPrefix,
  hudSuffix,
  stepKind,
  fallbackReason,
  queuedDeferred,
  hudHeaderTemplate
)
  if not dest or provider == "rxp" or provider == "none" then
    Navigation.ClearArrowTarget()
    return false, nil
  end

  local prev = Navigation.activeTarget
  local radius = math.max(5, tonumber(arrivalRadiusYards) or 15)
  local sameSpot = prev
    and tonumber(prev.uiMapID) == tonumber(dest.uiMapID)
    and prev.x01 == dest.x01
    and prev.y01 == dest.y01
    and prev.arrivalRadiusYards == radius

  if not sameSpot or (prev and prev.context ~= context) then
    Navigation.ResetUpdateCircuitLatches()
  end

  local anchor = nil
  -- CRITICAL (Astra P1 #2): Never reuse a failed/unusable anchor, or a partial anchor whose vector failed!
  local canReusePrevAnchor = sameSpot
    and prev.anchor
    and (
      prev.anchor.isComplete == true
      or (prev.anchor.isUsable == true and (prev.lastVecStatus == "ok" or prev.lastVecStatus == "facing_unavailable"))
    )
  if canReusePrevAnchor then
    anchor = prev.anchor
  elseif ns.Compat and ns.Compat.ResolveTargetWorldAnchor then
    anchor = ns.Compat.ResolveTargetWorldAnchor(dest.uiMapID, dest.x01, dest.y01, radius)
  end

  if not anchor then
    Navigation.ClearArrowTarget()
    return false, nil
  end

  local xPct = (tonumber(dest.x01) or 0) * 100
  local yPct = (tonumber(dest.y01) or 0) * 100
  local mID = tonumber(dest.uiMapID)
  local zoneName = tostring(
    dest.zoneName
      or (mID == 2548 and "Riverglades")
      or (mID == 1444 and "Feralas")
      or (C_Map and C_Map.GetMapInfo and mID and (C_Map.GetMapInfo(mID) or {}).name)
      or ""
  )
  local coordSummary = zoneName ~= "" and string.format("%s (%.1f, %.1f)", zoneName, xPct, yPct)
    or string.format("(%.1f, %.1f)", xPct, yPct)

  local builtinDesired = shouldUseBuiltinArrowForProvider(provider, dest)
  local dockedEnabled, floatingEnabled = resolveArrowRenderers(builtinDesired)
  local effectiveCaption = captionLabel or titleText or coordSummary
  if isGrindCampStepKind(stepKind) and not string.find(string.lower(tostring(effectiveCaption)), "camp", 1, true) then
    effectiveCaption = tostring(effectiveCaption) .. " (Camp)"
  end

  local target = {
    context = context,
    stepKind = stepKind,
    uiMapID = tonumber(dest.uiMapID),
    x01 = dest.x01,
    y01 = dest.y01,
    arrivalRadiusYards = radius,
    provider = provider,
    fallbackReason = fallbackReason,
    queuedDeferred = (queuedDeferred == true),
    dockedRendererEnabled = dockedEnabled,
    floatingRendererEnabled = floatingEnabled,
    title = tostring(titleText or ""),
    caption = truncateArrowCaption(effectiveCaption, 34),
    coordSummary = coordSummary,
    hudCoordPrefix = hudCoordPrefix,
    hudSuffix = hudSuffix,
    hudHeaderTemplate = hudHeaderTemplate,
    hudCleanHeader = (context == "riverglades") and "Riverglades" or nil,
    isArrivedState = sameSpot and (prev.isArrivedState == true) or false,
    inCampState = sameSpot and (prev.inCampState == true) or false,
    anchorRetryAccum = 0,
    anchorRetryCount = 0,
    anchor = anchor,
  }

  local vec = ns.Compat.ComputeNavigationVector(anchor, Navigation._scratchVec)
  target.lastVecStatus = vec and vec.status or "unavailable"
  updateTargetHysteresis(target, vec)

  Navigation.activeTarget = target
  Navigation.arrowTarget = target

  local settings = ns.State and ns.State.GetArrowSettings and ns.State.GetArrowSettings()
  local arrowFrameReady = false
  if dockedEnabled then
    if Navigation.arrowFrame then
      Navigation.arrowFrame:Hide()
    end
    local hud = ensureHUDFrame()
    if hud and hud.dockedArrowLane then
      arrowFrameReady = true
      applyArrowTextureToWidget(hud.dockedArrowLane, settings)
      hud.dockedArrowLane.elapsedAccum = 0
      if hud.dockedArrowLane.Show then hud.dockedArrowLane:Show() end
      updateArrowVisualFromVector(hud.dockedArrowLane, target, vec, true, true)
    end
  elseif floatingEnabled then
    if Navigation.frame and Navigation.frame.dockedArrowLane and Navigation.frame.dockedArrowLane.Hide then
      Navigation.frame.dockedArrowLane:Hide()
    end
    local af = ensureArrowFrame()
    if af then
      arrowFrameReady = true
      applyArrowSettingsToFrame(af)
      af.captionText:SetText(target.caption)
      af.elapsedAccum = 0
      af:Show()
      updateArrowVisualFromVector(af, target, vec, true, false)
    end
  else
    if Navigation.arrowFrame then
      Navigation.arrowFrame:Hide()
    end
    if Navigation.frame and Navigation.frame.dockedArrowLane and Navigation.frame.dockedArrowLane.Hide then
      Navigation.frame.dockedArrowLane:Hide()
    end
  end

  syncControllerActivity()
  local builtinArrowOk = arrowFrameReady and (vec and vec.status == "ok") or false
  target.lastCapabilityKey = string.format(
    "%s|%s|%s|%s",
    tostring(provider),
    tostring(builtinArrowOk),
    tostring(vec and vec.status or "unavailable"),
    tostring((provider == "tomtom") and isTomTomArrowConfirmedActive() or false)
  )
  return builtinArrowOk, vec
end

function Navigation.RefreshArrowSettings()
  Navigation.ResetUpdateCircuitLatches()
  local settings = ns.State and ns.State.GetArrowSettings and ns.State.GetArrowSettings()
  local target = Navigation.activeTarget
  if target then
    local builtinDesired = shouldUseBuiltinArrowForProvider(target.provider, target)
    local dockedEnabled, floatingEnabled = resolveArrowRenderers(builtinDesired)
    target.dockedRendererEnabled = dockedEnabled
    target.floatingRendererEnabled = floatingEnabled
    local vec = ns.Compat.ComputeNavigationVector(target.anchor, Navigation._scratchVec)
    updateTargetHysteresis(target, vec)
    if dockedEnabled then
      if Navigation.arrowFrame then
        Navigation.arrowFrame:Hide()
      end
      local hud = ensureHUDFrame()
      if hud and hud.dockedArrowLane then
        hud.dockedArrowLane.appliedTexturePath = nil
        applyArrowTextureToWidget(hud.dockedArrowLane, settings)
        if hud.dockedArrowLane.Show then hud.dockedArrowLane:Show() end
        updateArrowVisualFromVector(hud.dockedArrowLane, target, vec, true, true)
      end
    elseif floatingEnabled then
      if Navigation.frame and Navigation.frame.dockedArrowLane and Navigation.frame.dockedArrowLane.Hide then
        Navigation.frame.dockedArrowLane:Hide()
      end
      local af = ensureArrowFrame()
      if af then
        af.appliedTexturePath = nil
        applyArrowSettingsToFrame(af)
        af.captionText:SetText(target.caption or "")
        af:Show()
        updateArrowVisualFromVector(af, target, vec, true, false)
      end
    else
      if Navigation.arrowFrame then
        Navigation.arrowFrame:Hide()
      end
      if Navigation.frame and Navigation.frame.dockedArrowLane and Navigation.frame.dockedArrowLane.Hide then
        Navigation.frame.dockedArrowLane:Hide()
      end
    end

    if Navigation.frame then
      if settings and settings.hudHidden then
        Navigation.frame:Hide()
      elseif hasActiveProviderOrRxpMonitorableSession() then
        layoutHUDFrame(Navigation.frame, Navigation.lastStatus)
        Navigation.frame:Show()
      end
    end

    refreshHUDSubtextFromTarget(target, vec)
    target.lastCapabilityKey = nil
    refreshCapabilityStatusInPlace(target, vec)
    if Navigation.frame then
      layoutHUDFrame(Navigation.frame, Navigation.lastStatus)
    end
    syncControllerActivity()
    return
  end

  if Navigation.frame then
    if settings and settings.hudHidden then
      Navigation.frame:Hide()
    elseif hasActiveProviderOrRxpMonitorableSession() then
      layoutHUDFrame(Navigation.frame, Navigation.lastStatus)
      Navigation.frame:Show()
    end
  end

  if Navigation.arrowFrame then
    applyArrowSettingsToFrame(Navigation.arrowFrame)
    if settings and settings.enabled == false then
      Navigation.arrowFrame:Hide()
    end
  end
  syncControllerActivity()
end

function Navigation.GetLiveArrowSnapshot()
  local settings = ns.State and ns.State.GetArrowSettings and ns.State.GetArrowSettings() or {}
  local target = Navigation.activeTarget
  if not target or not target.anchor then
    return {
      active = false,
      dockedVisible = false,
      floatingVisible = false,
      dockedInHud = (settings.dockedInHud ~= false),
      renderer = settings.renderer or "auto",
      enabled = (settings.enabled ~= false),
      locked = (settings.locked == true),
      scale = settings.scale or 1.0,
      style = settings.style or "auto",
      status = "idle",
    }
  end
  local vec = ns.Compat.ComputeNavigationVector(target.anchor, {})
  local _, resolvedMode = resolveActiveArrowTexturePath(settings)
  local dockedShown = (target.dockedRendererEnabled == true)
    and (Navigation.frame ~= nil and Navigation.frame.dockedArrowLane ~= nil)
    and (type(Navigation.frame.dockedArrowLane.IsShown) ~= "function" or Navigation.frame.dockedArrowLane:IsShown() == true)
  local floatingShown = (target.floatingRendererEnabled == true)
    and (Navigation.arrowFrame == nil or Navigation.arrowFrame:IsShown() == true)

  if dockedShown and Navigation.frame and Navigation.frame.dockedArrowLane and Navigation.frame.dockedArrowLane.appliedTextureMode then
    resolvedMode = Navigation.frame.dockedArrowLane.appliedTextureMode
  elseif floatingShown and Navigation.arrowFrame and Navigation.arrowFrame.appliedTextureMode then
    resolvedMode = Navigation.arrowFrame.appliedTextureMode
  elseif Navigation.arrowFrame and Navigation.arrowFrame.appliedTextureMode then
    resolvedMode = Navigation.arrowFrame.appliedTextureMode
  end

  return {
    active = (dockedShown or floatingShown) and (vec.status == "ok"),
    dockedVisible = dockedShown,
    floatingVisible = floatingShown,
    dockedInHud = (settings.dockedInHud ~= false),
    renderer = settings.renderer or "auto",
    enabled = (settings.enabled ~= false),
    locked = (settings.locked == true),
    scale = settings.scale or 1.0,
    style = settings.style or "auto",
    resolvedTextureMode = resolvedMode,
    status = vec.status,
    reason = vec.reason,
    yards = vec.yards,
    isCrossZone = vec.isCrossZone,
    worldBearingDegrees = vec.worldBearingRadians and math.deg(vec.worldBearingRadians) or nil,
    rotationDegrees = vec.rotationRadians and math.deg(vec.rotationRadians) or nil,
    isArrived = target.isArrivedState,
    inCamp = target.inCampState,
    vectorSource = vec.vectorSource,
    title = target.title,
    coordSummary = target.coordSummary,
  }
end

function Navigation.HideRivergladesHUD()
  if Navigation.frame and Navigation.activeContext == "riverglades" then
    Navigation.frame:Hide()
  end
  if Navigation.activeTarget and Navigation.activeTarget.context == "riverglades" then
    Navigation.ClearArrowTarget()
  end
end

local function formatRivergladesHudParts(act, route, progress, explicitDest, explicitTargetName)
  if type(act) ~= "table" or type(act.destination) ~= "table" then
    return nil, ""
  end
  local dest = explicitDest
  local targetName = explicitTargetName
  if not dest and ns.Domain and ns.Domain.RoutePlanner and ns.Domain.RoutePlanner.ResolveActiveActionTarget then
    progress = progress or (ns.State and ns.State.GetRouteProgress and ns.State.GetRouteProgress())
    dest, targetName = ns.Domain.RoutePlanner.ResolveActiveActionTarget(act, progress)
  end
  dest = dest or act.destination
  targetName = targetName or act.npcName

  local xPct, yPct = ns.Domain.RoutePlanner.NormalizedToPercent(dest.x01, dest.y01)
  local mID = tonumber(dest.uiMapID)
  local zoneLabel = tostring(
    dest.zoneName
      or (mID == 2548 and "Riverglades")
      or (mID == 1444 and "Feralas")
      or (C_Map and C_Map.GetMapInfo and mID and (C_Map.GetMapInfo(mID) or {}).name)
      or "Riverglades"
  )
  local prefix = string.format("%s (%.1f, %.1f)", zoneLabel, xPct or 0, yPct or 0)
  if dest.coordConfidence == "estimated" then
    prefix = prefix .. " [Est.]"
  end

  local suffixParts = {}
  if targetName and targetName ~= "" then
    table.insert(suffixParts, " — " .. tostring(targetName))
  end

  if act.kind == "objective" and ns.Compat and ns.Compat.GetQuestObjectivesResult then
    local qref = (type(act.questKey) == "string" and act.questKey ~= "" and act.questKey) or act.questID
    if qref then
      local objRes = ns.Compat.GetQuestObjectivesResult(qref)
      if type(objRes) == "table" and objRes.status == "ok" and type(objRes.summaryText) == "string" and objRes.summaryText ~= "" then
        table.insert(suffixParts, " [" .. objRes.summaryText .. "]")
      end
      route = route or (ns.State and ns.State.GetCompiledRivergladesRoute and ns.State.GetCompiledRivergladesRoute())
      local qMeta = nil
      if type(route) == "table" then
        if type(qref) == "number" and type(route.questsByID) == "table" then
          qMeta = route.questsByID[qref]
        elseif type(qref) == "string" and type(route.questsByTitleKey) == "table" then
          qMeta = route.questsByTitleKey[qref]
        end
      end
      if qMeta and qMeta.supplyItemID and ns.State and ns.State.GetBankItemCount then
        local bankQty = ns.State.GetBankItemCount(qMeta.supplyItemID)
        if bankQty and bankQty > 0 then
          table.insert(suffixParts, string.format(" (%d in bank!)", bankQty))
        end
      end
    end
  end

  return prefix, table.concat(suffixParts, "")
end

local function notifyWorldMapPinsRefresh()
  if ns.UI and ns.UI.WorldMapPins and type(ns.UI.WorldMapPins.RequestRefresh) == "function" then
    ns.UI.WorldMapPins.RequestRefresh()
  end
end

local function showOrHideHUDRespectingPreference(f, status)
  if not f then
    return
  end
  local settings = ns.State and ns.State.GetArrowSettings and ns.State.GetArrowSettings()
  layoutHUDFrame(f, status)
  if settings and settings.hudHidden == true then
    if f.overflowMenu and f.overflowMenu.Hide then f.overflowMenu:Hide() end
    f:Hide()
  else
    f:Show()
  end
end

local function updateHUDPresentation(eval, status)
  notifyWorldMapPinsRefresh()
  local f = ensureHUDFrame()
  if not f then
    return
  end

  local progress = ns.State and ns.State.GetRouteProgress and ns.State.GetRouteProgress()
  if not progress or progress.mode == "paused" then
    if Navigation.activeContext == "riverglades" then
      if f.overflowMenu and f.overflowMenu.Hide then f.overflowMenu:Hide() end
      f:Hide()
    end
    return
  end

  if f.nextBtn and f.nextBtn.SetLabel then
    f.nextBtn:SetLabel("Skip objective")
  elseif f.nextBtn and f.nextBtn.SetText then
    f.nextBtn:SetText("Skip objective")
  end

  local counts = (eval and eval.counts) or { completed = 0, total = 0, skipped = 0 }
  local act = eval and eval.nextAction
  local cleanHeader = "Riverglades"
  if progress.mode ~= "rxp" and act and (act.questID or act.questKey) and ns.Compat and ns.Compat.LookupRouteQuestMeta then
    local qMeta = ns.Compat.LookupRouteQuestMeta(act.questKey or act.questID)
    local qName = qMeta and qMeta.name or nil
    if type(qName) == "string" and qName ~= "" then
      local lvl = tonumber(qMeta.questLevel)
      local lvlPrefix = ""
      if lvl and lvl > 0 then
        local plus = (act.isEliteBounty == true or qMeta.isEliteBounty == true) and "+" or ""
        lvlPrefix = string.format("[%d%s] ", lvl, plus)
      end
      local fullHdr = "Riverglades · " .. lvlPrefix .. qName
      if ns.Compat.UTF8Truncate then
        cleanHeader = ns.Compat.UTF8Truncate(fullHdr, 44)
      else
        cleanHeader = fullHdr
      end
    end
  end
  if Navigation.activeTarget and Navigation.activeTarget.context == "riverglades" then
    Navigation.activeTarget.hudCleanHeader = cleanHeader
  end
  f.headerText:SetText(cleanHeader)

  if progress.mode == "rxp" then
    f.stepText:SetText("RXPGuides owns active step progression")
    f.subText:SetText("Use RXP window for steps, or /fh rg start after deselecting in RXP.")
    showOrHideHUDRespectingPreference(f, status)
    return
  end

  if not act then
    if eval and eval.blockedNotice and eval.blockedNotice.state == "blocked_quest_log_full" then
      f.stepText:SetText("Quest Log Full — clear a slot to accept next quest")
      f.subText:SetText(tostring(eval.blockedNotice.action and eval.blockedNotice.action.title or ""))
    elseif eval and (
      (eval.blockedNotice and eval.blockedNotice.state == "blocked_unresolved_history")
      or ((counts.blockedUnresolvedHistory or 0) > 0)
    ) then
      f.stepText:SetText(
        string.format(
          "%d custom title quest(s) awaiting pre-install history check",
          tonumber(counts.blockedUnresolvedHistory) or 1
        )
      )
      f.subText:SetText("Open Workspace (/fh rg) or run /fh rg unresolved to review.")
    else
      f.stepText:SetText("Reviewed Riverglades segment complete!")
      f.subText:SetText("All eligible steps completed or skipped (/fh rg stop to close).")
    end
    showOrHideHUDRespectingPreference(f, status)
    return
  end

  local plan = (eval and type(eval.plan) == "table") and eval.plan or nil
  local isOffZone = (plan and plan.zoneStatus == "off_zone")
  local isPosUnavail = (plan and plan.zoneStatus == "position_unavailable")

  if isOffZone then
    f.stepText:SetText("Travel to Riverglades to begin")
  else
    f.stepText:SetText(tostring(act.title or act.actionID))
  end

  if act.destination then
    local prefix, suffix = formatRivergladesHudParts(act)
    local t = Navigation.activeTarget
    if isOffZone then
      local entryText = "Entry: " .. tostring(act.title or act.actionID) .. " · " .. prefix .. suffix
      if t and t.context == "riverglades" then
        t.lastHudSubtext = entryText
      end
      f.subText:SetText(entryText)
    elseif t and t.context == "riverglades" and t.anchor then
      t.hudCoordPrefix = prefix
      t.hudSuffix = suffix
      local vec = ns.Compat.ComputeNavigationVector(t.anchor, Navigation._scratchVec)
      updateTargetHysteresis(t, vec)
      local distPart = formatHudDistanceSegment(t, vec) or ""
      if distPart == "" and isPosUnavail then
        distPart = " • Position unavailable"
      end
      local fullLine = prefix .. distPart .. suffix
      t.lastHudSubtext = fullLine
      f.subText:SetText(fullLine)
    else
      local posNote = isPosUnavail and " • Position unavailable" or ""
      f.subText:SetText(prefix .. posNote .. suffix)
    end
  else
    f.subText:SetText(tostring(act.note or "Manual objective — see quest log / live Questie"))
  end
  showOrHideHUDRespectingPreference(f, status)
end

function Navigation.SyncFromEvaluation(eval, progress, expectedGeneration)
  Navigation.HydrateOwnerFromSavedStateIfUnset()
  if expectedGeneration ~= nil and not Navigation.IsGenerationCurrent(expectedGeneration) then
    return Navigation.lastStatus, "stale_generation_discarded"
  end

  progress = progress or (ns.State and ns.State.GetRouteProgress and ns.State.GetRouteProgress())
  if not progress then
    return Navigation.lastStatus
  end

  -- Ignore syncs from an inactive paused Riverglades context while Gold Farms actively owns navigation
  if progress.mode == "paused" and Navigation.activeContext == "gold_farm" then
    local gfProg = ns.State and ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress()
    if gfProg and gfProg.mode ~= "paused" then
      return Navigation.lastStatus
    end
  end

  if progress.mode ~= "paused" and Navigation.activeContext ~= "riverglades" then
    Navigation.RequestContextSwitch("riverglades")
  elseif progress.mode ~= "paused" then
    Navigation.activeContext = "riverglades"
  end

  eval = eval or ns.Domain.RouteProgress.Reconcile(nil, progress)

  if progress.mode ~= "paused"
    and ns.Bridges
    and ns.Bridges.RXPBridge
    and ns.Bridges.RXPBridge.IsRivergladesGuideSelected()
  then
    progress.mode = "rxp"
  elseif progress.mode == "rxp"
    and ns.Bridges
    and ns.Bridges.RXPBridge
    and not ns.Bridges.RXPBridge.IsRivergladesGuideSelected()
  then
    progress.mode = "standalone"
  end

  local gen = Navigation.BumpGeneration()

  if progress.mode == "paused" then
    syncRivergladesQuestWatchBaseline(nil, false)
    Navigation.StopTravelTicker()
    Navigation.ClearArrowTarget()
    Navigation.owner.pendingDestination = nil
    syncProgressMirrorsAndPersist()
    if Navigation.owner.ownerContext == "riverglades" or Navigation.owner.pendingRelease then
      local relOk, relReason = Navigation.TryReleaseOwnedResource(progress)
      if not relOk then
        Navigation.lastStatus = {
          activeProvider = "none",
          navigationLabel = ns.Compat.IsInCombat() and "Paused (Cleanup Deferred — In Combat)" or "Paused (Cleanup Unconfirmed)",
          cleanupReason = relReason,
          hasDirectionalArrow = false,
          deferred = true,
        }
        updateHUDPresentation(eval, Navigation.lastStatus)
        return Navigation.lastStatus
      end
    end
    Navigation.lastStatus = {
      activeProvider = "none",
      navigationLabel = "Paused",
      hasDirectionalArrow = false,
      deferred = false,
    }
    updateHUDPresentation(eval, Navigation.lastStatus)
    return Navigation.lastStatus
  end

  if progress.mode == "rxp" then
    syncRivergladesQuestWatchBaseline(nil, false)
    Navigation.StopTravelTicker()
    Navigation.ClearArrowTarget()
    Navigation.owner.pendingDestination = nil
    Navigation.TryReleaseOwnedResource(progress)
    syncControllerActivity()
    Navigation.lastStatus = {
      activeProvider = "rxp",
      navigationLabel = "RXP Guide Selected",
      hasDirectionalArrow = false,
      deferred = false,
    }
    updateHUDPresentation(eval, Navigation.lastStatus)
    return Navigation.lastStatus
  end

  local nextAct = eval and eval.nextAction
  syncRivergladesQuestWatchBaseline(nextAct, true)
  if not nextAct or not nextAct.destination then
    Navigation.StopTravelTicker()
    Navigation.ClearArrowTarget()
    Navigation.owner.pendingDestination = nil
    Navigation.TryReleaseOwnedResource(progress)
    syncControllerActivity()
    Navigation.lastStatus = {
      activeProvider = "text_manual",
      navigationLabel = nextAct and "Manual / Text Note" or "Segment Idle",
      hasDirectionalArrow = false,
      deferred = false,
    }
    updateHUDPresentation(eval, Navigation.lastStatus)
    return Navigation.lastStatus
  end

  local activeDest, activeTargetName = nextAct.destination, nextAct.npcName
  if ns.Domain and ns.Domain.RoutePlanner and ns.Domain.RoutePlanner.ResolveActiveActionTarget then
    local resolvedDest, resolvedName = ns.Domain.RoutePlanner.ResolveActiveActionTarget(nextAct, progress)
    if type(resolvedDest) == "table" then
      activeDest = resolvedDest
      activeTargetName = resolvedName or activeTargetName
    end
  end

  local counts = (eval and eval.counts) or { completed = 0, total = 0, skipped = 0 }
  local rgHeaderTpl = string.format(
    "ForeverHub Riverglades [%d/%d done, %d skipped] — Nav: %%s",
    counts.completed or 0,
    counts.total or 0,
    counts.skipped or 0
  )
  local rgHudPrefix, rgHudSuffix = formatRivergladesHudParts(nextAct, nil, progress, activeDest, activeTargetName)
  local rgCaption = activeTargetName or nextAct.title or rgHudPrefix
  local rgArrivalRadius = tonumber(nextAct.arrivalRadiusYards or (activeDest and activeDest.radiusYards)) or 18

  if ns.Compat.IsInCombat() then
    local alreadyOwnsSamePin = (Navigation.owner.ownerContext == "riverglades")
      and (Navigation.owner.provider ~= "none")
      and (not Navigation.owner.pendingRelease)
      and type(Navigation.owner.handle) == "table"
      and coordsMatch(
        Navigation.owner.handle.uiMapID,
        Navigation.owner.handle.x01,
        Navigation.owner.handle.y01,
        activeDest.uiMapID,
        activeDest.x01,
        activeDest.y01
      )
    if alreadyOwnsSamePin then
      local sameArrowOk, sameVec = Navigation.SetArrowTarget(
        "riverglades",
        activeDest,
        nextAct.title,
        rgCaption,
        rgArrivalRadius,
        Navigation.owner.provider,
        rgHudPrefix,
        rgHudSuffix,
        nextAct.kind,
        nil,
        false,
        rgHeaderTpl
      )
      Navigation.lastStatus = buildProviderStatus(
        Navigation.owner.provider,
        activeDest,
        nil,
        sameArrowOk,
        sameVec and sameVec.status or nil
      )
      updateHUDPresentation(eval, Navigation.lastStatus)
      return Navigation.lastStatus
    end

    if Navigation.owner.provider ~= "none" and Navigation.owner.ownerContext ~= "riverglades" then
      Navigation.owner.pendingRelease = true
    end
    Navigation.owner.pendingDestination = {
      context = "riverglades",
      generation = gen,
      destination = activeDest,
      title = nextAct.title,
    }
    syncProgressMirrorsAndPersist()
    local combatArrowOk, combatVec = Navigation.SetArrowTarget(
      "riverglades",
      activeDest,
      nextAct.title,
      rgCaption,
      rgArrivalRadius,
      "deferred",
      rgHudPrefix,
      rgHudSuffix,
      nextAct.kind,
      "deferred_in_combat",
      true,
      rgHeaderTpl
    )
    Navigation.lastStatus = buildProviderStatus(
      "deferred",
      activeDest,
      "deferred_in_combat",
      combatArrowOk,
      combatVec and combatVec.status or nil
    )
    updateHUDPresentation(eval, Navigation.lastStatus)
    return Navigation.lastStatus
  end

  Navigation.owner.pendingDestination = nil
  updateDeferredMirror()

  local okAcq, provider, reason = tryAcquireDestinationForContext("riverglades", activeDest, nextAct.title)
  local queuedDeferred = shouldQueuePendingDestination(okAcq, reason)
  if queuedDeferred then
    Navigation.owner.pendingDestination = {
      context = "riverglades",
      generation = gen,
      destination = activeDest,
      title = nextAct.title,
    }
  end
  syncProgressMirrorsAndPersist()
  Navigation.EnsureTravelTicker((nextAct.kind == "travel") or queuedDeferred, "riverglades")
  local effProvider = okAcq and provider or "text_manual"
  local arrowOk, vec = Navigation.SetArrowTarget(
    "riverglades",
    activeDest,
    nextAct.title,
    rgCaption,
    rgArrivalRadius,
    effProvider,
    rgHudPrefix,
    rgHudSuffix,
    nextAct.kind,
    reason,
    queuedDeferred,
    rgHeaderTpl
  )
  Navigation.lastStatus = buildProviderStatus(effProvider, activeDest, reason, arrowOk, vec and vec.status or nil)
  if queuedDeferred then
    Navigation.lastStatus.deferred = true
  end
  updateHUDPresentation(eval, Navigation.lastStatus)
  return Navigation.lastStatus
end

local function updateGoldFarmHUDPresentation(eval, status)
  local f = ensureHUDFrame()
  if not f then
    return
  end

  local progress = ns.State and ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress()
  if not progress or progress.mode == "paused" or not (eval and eval.farm) then
    if Navigation.activeContext == "gold_farm" then
      if f.overflowMenu and f.overflowMenu.Hide then f.overflowMenu:Hide() end
      f:Hide()
    end
    return
  end

  if f.nextBtn and f.nextBtn.SetLabel then
    f.nextBtn:SetLabel("Next hop")
  elseif f.nextBtn and f.nextBtn.SetText then
    f.nextBtn:SetText("Next hop")
  end

  local farm = eval.farm
  local cleanHeader = string.format(
    "Gold Farm · %s (%d/%d)",
    tostring(farm.shortLabel or farm.zoneName),
    tonumber(eval.stepIndex) or 1,
    tonumber(eval.totalSteps) or 1
  )
  if Navigation.activeTarget and Navigation.activeTarget.context == "gold_farm" then
    Navigation.activeTarget.hudCleanHeader = cleanHeader
  end
  f.headerText:SetText(cleanHeader)

  if progress.mode == "rxp" then
    f.stepText:SetText("RXPGuides owns active gold farm steps")
    f.subText:SetText("Use RXP window, or /fh gold start after deselecting in RXP.")
    showOrHideHUDRespectingPreference(f, status)
    return
  end

  local step = eval.activeStep
  if not step then
    f.stepText:SetText(tostring(farm.title))
    f.subText:SetText("Open Workspace (/fh gold) or run /fh gold stop to close.")
    showOrHideHUDRespectingPreference(f, status)
    return
  end

  f.stepText:SetText(tostring(step.title or step.stepID))
  if step.destination then
    local xPct, yPct = ns.Domain.GoldFarms.NormalizedToPercent(step.destination.x01, step.destination.y01)
    local zoneLabel = tostring(step.destination.zoneName or farm.zoneName or "")
    local prefix = string.format("%s (%.1f, %.1f)", zoneLabel, xPct or 0, yPct or 0)
    local suffix = formatGoldFarmHudStepSuffix(step)
    local t = Navigation.activeTarget
    if t and t.context == "gold_farm" and t.anchor then
      local vec = ns.Compat.ComputeNavigationVector(t.anchor, Navigation._scratchVec)
      updateTargetHysteresis(t, vec)
      local distPart = formatHudDistanceSegment(t, vec) or ""
      local fullLine = prefix .. distPart .. suffix
      t.lastHudSubtext = fullLine
      f.subText:SetText(fullLine)
    else
      f.subText:SetText(prefix .. suffix)
    end
  else
    f.subText:SetText(tostring(step.note or ""))
  end
  showOrHideHUDRespectingPreference(f, status)
end

function Navigation.SyncFromGoldFarmEvaluation(eval, progress, expectedGeneration)
  Navigation.HydrateOwnerFromSavedStateIfUnset()
  if expectedGeneration ~= nil and not Navigation.IsGenerationCurrent(expectedGeneration) then
    return Navigation.lastStatus, "stale_generation_discarded"
  end

  progress = progress or (ns.State and ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress())
  if not progress then
    return Navigation.lastStatus
  end

  if progress.mode == "paused" and Navigation.activeContext == "riverglades" then
    local rgProg = ns.State and ns.State.GetRouteProgress and ns.State.GetRouteProgress()
    if rgProg and rgProg.mode ~= "paused" then
      return Navigation.lastStatus
    end
  end

  if progress.mode ~= "paused" and Navigation.activeContext ~= "gold_farm" then
    syncRivergladesQuestWatchBaseline(nil, false)
    Navigation.RequestContextSwitch("gold_farm")
  elseif progress.mode ~= "paused" then
    syncRivergladesQuestWatchBaseline(nil, false)
    Navigation.activeContext = "gold_farm"
  end

  eval = eval or ns.Domain.GoldFarms.Evaluate(nil, progress)
  local farmID = progress.selectedFarmID

  if progress.mode ~= "paused"
    and farmID
    and ns.Bridges
    and ns.Bridges.RXPBridge
    and ns.Bridges.RXPBridge.IsGoldFarmGuideSelected
    and ns.Bridges.RXPBridge.IsGoldFarmGuideSelected(farmID)
  then
    progress.mode = "rxp"
    if ns.State and ns.State.SetGoldFarmActivityPhase then
      ns.State.SetGoldFarmActivityPhase("rxp_untracked")
    end
  elseif progress.mode == "rxp"
    and ns.Bridges
    and ns.Bridges.RXPBridge
    and ns.Bridges.RXPBridge.IsGoldFarmGuideSelected
    and not ns.Bridges.RXPBridge.IsGoldFarmGuideSelected(farmID)
  then
    progress.mode = "standalone"
    if ns.State and ns.State.SetGoldFarmActivityPhase and eval and eval.activeStep then
      ns.State.SetGoldFarmActivityPhase(eval.activeStep.kind)
    end
  end

  local gen = Navigation.BumpGeneration()

  if progress.mode == "paused" then
    Navigation.StopTravelTicker()
    Navigation.ClearArrowTarget()
    Navigation.owner.pendingDestination = nil
    syncProgressMirrorsAndPersist()
    if Navigation.owner.ownerContext == "gold_farm" or Navigation.owner.pendingRelease then
      local relOk, relReason = Navigation.TryReleaseOwnedResource(progress)
      if not relOk then
        Navigation.lastStatus = {
          activeProvider = "none",
          navigationLabel = ns.Compat.IsInCombat() and "Paused (Cleanup Deferred — In Combat)" or "Paused (Cleanup Unconfirmed)",
          cleanupReason = relReason,
          hasDirectionalArrow = false,
          deferred = true,
        }
        updateGoldFarmHUDPresentation(eval, Navigation.lastStatus)
        return Navigation.lastStatus
      end
    end
    Navigation.lastStatus = {
      activeProvider = "none",
      navigationLabel = "Paused",
      hasDirectionalArrow = false,
      deferred = false,
    }
    updateGoldFarmHUDPresentation(eval, Navigation.lastStatus)
    return Navigation.lastStatus
  end

  if progress.mode == "rxp" then
    Navigation.StopTravelTicker()
    Navigation.ClearArrowTarget()
    Navigation.owner.pendingDestination = nil
    syncProgressMirrorsAndPersist()
    Navigation.TryReleaseOwnedResource(progress)
    syncControllerActivity()
    Navigation.lastStatus = {
      activeProvider = "rxp",
      navigationLabel = "RXP Guide Selected",
      hasDirectionalArrow = false,
      deferred = false,
    }
    updateGoldFarmHUDPresentation(eval, Navigation.lastStatus)
    return Navigation.lastStatus
  end

  local step = eval and eval.activeStep
  if not step or not step.destination then
    Navigation.StopTravelTicker()
    Navigation.ClearArrowTarget()
    Navigation.owner.pendingDestination = nil
    Navigation.TryReleaseOwnedResource(progress)
    syncControllerActivity()
    Navigation.lastStatus = {
      activeProvider = "text_manual",
      navigationLabel = "Manual / Text Note",
      hasDirectionalArrow = false,
      deferred = false,
    }
    updateGoldFarmHUDPresentation(eval, Navigation.lastStatus)
    return Navigation.lastStatus
  end

  local xPctGF, yPctGF = ns.Domain.GoldFarms.NormalizedToPercent(step.destination.x01, step.destination.y01)
  local gfFarm = eval.farm or {}
  local gfZoneLabel = tostring(step.destination.zoneName or gfFarm.zoneName or "")
  local gfHudPrefix = string.format("%s (%.1f, %.1f)", gfZoneLabel, xPctGF or 0, yPctGF or 0)
  local gfHudSuffix = formatGoldFarmHudStepSuffix(step)
  local gfHeaderTpl = string.format(
    "ForeverHub Gold [Candidate %d: %s | Hop %d/%d] — Nav: %%s",
    tonumber(gfFarm.candidateOrder or gfFarm.rank) or 1,
    tostring(gfFarm.shortLabel or gfFarm.zoneName),
    tonumber(eval.stepIndex) or 1,
    tonumber(eval.totalSteps) or 1
  )
  local gfArrivalRadius = tonumber(step.arrivalRadiusYards or (step.destination and step.destination.radiusYards)) or 25
  local ttTitle = string.format("%s — %s", tostring(gfFarm.shortLabel or "Gold Farm"), tostring(step.title or ""))

  if ns.Compat.IsInCombat() then
    if Navigation.owner.provider ~= "none" and Navigation.owner.ownerContext ~= "gold_farm" then
      Navigation.owner.pendingRelease = true
    end
    Navigation.owner.pendingDestination = {
      context = "gold_farm",
      generation = gen,
      destination = step.destination,
      title = ttTitle,
    }
    syncProgressMirrorsAndPersist()
    local combatArrowOk, combatVec = Navigation.SetArrowTarget(
      "gold_farm",
      step.destination,
      ttTitle,
      step.title or gfZoneLabel,
      gfArrivalRadius,
      "deferred",
      gfHudPrefix,
      gfHudSuffix,
      step.kind,
      "deferred_in_combat",
      true,
      gfHeaderTpl
    )
    Navigation.lastStatus = buildProviderStatus(
      "deferred",
      step.destination,
      "deferred_in_combat",
      combatArrowOk,
      combatVec and combatVec.status or nil
    )
    updateGoldFarmHUDPresentation(eval, Navigation.lastStatus)
    return Navigation.lastStatus
  end

  Navigation.owner.pendingDestination = nil
  updateDeferredMirror()

  local okAcq, provider, reason = tryAcquireDestinationForContext("gold_farm", step.destination, ttTitle)
  local queuedDeferred = shouldQueuePendingDestination(okAcq, reason)
  if queuedDeferred then
    Navigation.owner.pendingDestination = {
      context = "gold_farm",
      generation = gen,
      destination = step.destination,
      title = ttTitle,
    }
  end
  syncProgressMirrorsAndPersist()
  Navigation.EnsureTravelTicker(
    (step.kind == "travel" or step.kind == "boat_crossing") or queuedDeferred,
    "gold_farm"
  )
  local effProvider = okAcq and provider or "text_manual"
  local arrowOk, vec = Navigation.SetArrowTarget(
    "gold_farm",
    step.destination,
    ttTitle,
    step.title or gfZoneLabel,
    gfArrivalRadius,
    effProvider,
    gfHudPrefix,
    gfHudSuffix,
    step.kind,
    reason,
    queuedDeferred,
    gfHeaderTpl
  )
  Navigation.lastStatus = buildProviderStatus(effProvider, step.destination, reason, arrowOk, vec and vec.status or nil)
  if queuedDeferred then
    Navigation.lastStatus.deferred = true
  end
  updateGoldFarmHUDPresentation(eval, Navigation.lastStatus)
  return Navigation.lastStatus
end

function Navigation.FlushDeferredIfReady()
  if ns.Compat.IsInCombat() then
    return nil
  end
  Navigation.HydrateOwnerFromSavedStateIfUnset()

  local pending = Navigation.owner.pendingDestination
  local needsRelease = (Navigation.owner.pendingRelease == true)

  if not pending and not needsRelease then
    updateDeferredMirror()
    return nil
  end

  -- First attempt any pending cleanup (e.g. Stop or context switch issued during combat or failed clear)
  if needsRelease then
    local relOk = Navigation.TryReleaseOwnedResource()
    if not relOk then
      updateDeferredMirror()
      return Navigation.lastStatus
    end
  end

  -- Reject stale or cancelled pending destination (e.g. Gold -> Riverglades -> Stop before cleanup succeeded)
  if not pending or not Navigation.IsGenerationCurrent(pending.generation) then
    Navigation.owner.pendingDestination = nil
    syncProgressMirrorsAndPersist()
    return Navigation.lastStatus
  end

  if pending.context == "gold_farm" then
    local gProg = ns.State and ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress()
    if gProg and gProg.mode ~= "paused" then
      local gEval = ns.Domain.GoldFarms.ReconcileActive(nil, gProg)
      return Navigation.SyncFromGoldFarmEvaluation(gEval, gProg)
    end
    Navigation.owner.pendingDestination = nil
    syncProgressMirrorsAndPersist()
    return Navigation.lastStatus
  elseif pending.context == "riverglades" then
    local rProg = ns.State and ns.State.GetRouteProgress and ns.State.GetRouteProgress()
    if rProg and rProg.mode ~= "paused" then
      local eval = ns.Domain.RouteProgress.Reconcile(nil, rProg)
      return Navigation.SyncFromEvaluation(eval, rProg)
    end
    Navigation.owner.pendingDestination = nil
    syncProgressMirrorsAndPersist()
    return Navigation.lastStatus
  end

  Navigation.owner.pendingDestination = nil
  syncProgressMirrorsAndPersist()
  return nil
end
