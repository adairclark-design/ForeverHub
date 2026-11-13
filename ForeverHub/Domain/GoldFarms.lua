local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.Domain = ns.Domain or {}

local GoldFarms = {}
ns.Domain.GoldFarms = GoldFarms

local MIN_GPH_SAMPLE_SECONDS = 180 -- 3 minutes minimum before extrapolating hourly cash-flow rate

local VALID_STEP_KINDS = {
  travel = true,
  boat_crossing = true,
  vendor = true,
  grind = true,
}

local MATERIAL_NAMES_FALLBACK = {
  [4234] = "Heavy Leather",
  [4304] = "Thick Leather",
  [4306] = "Silk Cloth",
  [4338] = "Mageweave Cloth",
}

local function nowTimestamp()
  if type(time) == "function" then
    return time()
  end
  return 0
end

local function isFinite(v)
  if ns.Compat and ns.Compat.IsFiniteNumber then
    return ns.Compat.IsFiniteNumber(v)
  end
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function GoldFarms.NormalizedToPercent(x01, y01)
  if not isFinite(x01) or not isFinite(y01) then
    return nil, nil
  end
  if x01 <= 0 or x01 >= 1 or y01 <= 0 or y01 >= 1 then
    return nil, nil
  end
  return math.floor(x01 * 10000 + 0.5) / 100, math.floor(y01 * 10000 + 0.5) / 100
end

function GoldFarms.ValidateStepDestination(step, catalog)
  catalog = catalog or (ns.State and ns.State.GetCompiledGoldFarms and ns.State.GetCompiledGoldFarms())
  if type(step) ~= "table" or step.reviewStatus ~= "verified" then
    return false, "unverified_step"
  end
  if not VALID_STEP_KINDS[tostring(step.kind or "")] then
    return false, "invalid_step_kind"
  end
  local dest = step.destination
  if type(dest) ~= "table" then
    return false, "missing_destination"
  end
  if dest.coordinateSpace ~= "uiMap01" then
    return false, "invalid_coordinate_space"
  end
  local mapID = tonumber(dest.uiMapID)
  if not isFinite(mapID) or mapID <= 0 or math.floor(mapID) ~= mapID then
    return false, "invalid_ui_map_id"
  end
  if catalog and type(catalog.reviewedMapsByUiMapID) == "table" and not catalog.reviewedMapsByUiMapID[mapID] then
    return false, "unreviewed_ui_map_id"
  end
  local x01 = tonumber(dest.x01)
  local y01 = tonumber(dest.y01)
  if not isFinite(x01) or not isFinite(y01) or x01 <= 0 or x01 >= 1 or y01 <= 0 or y01 >= 1 then
    return false, "coordinates_out_of_bounds"
  end
  if step.kind == "boat_crossing" then
    local targetMapID = tonumber(step.targetUiMapID)
    if not isFinite(targetMapID) or targetMapID <= 0 or math.floor(targetMapID) ~= targetMapID then
      return false, "missing_boat_target_map"
    end
    if catalog and type(catalog.reviewedMapsByUiMapID) == "table" and not catalog.reviewedMapsByUiMapID[targetMapID] then
      return false, "unreviewed_boat_target_map"
    end
  end
  return true, nil
end

function GoldFarms.ResolveFarm(query, catalog)
  catalog = catalog or (ns.State and ns.State.GetCompiledGoldFarms and ns.State.GetCompiledGoldFarms())
  if type(catalog) ~= "table" or type(catalog.farms) ~= "table" or #catalog.farms == 0 then
    return nil, "Gold farms catalog is not loaded."
  end

  if query == nil or query == "" then
    return catalog.farms[1], nil
  end

  local asNum = tonumber(query)
  if isFinite(asNum) then
    local ordInt = math.floor(asNum)
    for _, f in ipairs(catalog.farms) do
      if tonumber(f.candidateOrder or f.rank) == ordInt then
        return f, nil
      end
    end
    if catalog.farms[ordInt] then
      return catalog.farms[ordInt], nil
    end
  end

  local qStr = string.lower(string.gsub(tostring(query), "^%s*(.-)%s*$", "%1"))
  if catalog.farmsByID and catalog.farmsByID[qStr] then
    return catalog.farmsByID[qStr], nil
  end

  for _, f in ipairs(catalog.farms) do
    if string.lower(tostring(f.farmID or "")) == qStr then
      return f, nil
    end
  end

  for _, f in ipairs(catalog.farms) do
    local hay = string.lower(
      string.format(
        "%s %s %s %s",
        tostring(f.farmID or ""),
        tostring(f.shortLabel or ""),
        tostring(f.zoneName or ""),
        tostring(f.title or "")
      )
    )
    if string.find(hay, qStr, 1, true) then
      return f, nil
    end
  end

  return nil,
    "Unknown gold farm '" .. tostring(query) .. "'. Use '/fh gold list' to see Candidate 1-" .. tostring(#catalog.farms) .. "."
end

-- World-yard arrival & non-proximity service/boat completion (Astra P1-6 & Gate 5):
-- - `grind` camps are STICKY and never auto-complete.
-- - `vendor` stops NEVER auto-complete on proximity; they complete on `MERCHANT_CLOSED` near the NPC or manual `Next`.
-- - `boat_crossing` NEVER completes on origin pier proximity; it completes ONLY when `playerPos.uiMapID == step.targetUiMapID` (or manual `Next`).
-- - `travel` hops require world-yard distance (`Compat.GetWorldDistanceYards`) <= `arrivalRadiusYards`; if map world dimensions are unavailable, manual completion is retained.
function GoldFarms.CheckHopArrival(step, playerPos, catalog)
  if type(step) ~= "table" then
    return false, "invalid_step"
  end
  if step.kind == "grind" then
    return false, "sticky_camp"
  end
  if step.kind == "vendor" then
    return false, "service_step_requires_merchant_or_manual"
  end

  local okDest, destErr = GoldFarms.ValidateStepDestination(step, catalog)
  if not okDest then
    return false, destErr
  end
  if type(playerPos) ~= "table" or playerPos.status ~= "ok" then
    return false, "player_position_unavailable"
  end

  local playerMapID = tonumber(playerPos.uiMapID)
  local px = tonumber(playerPos.x01)
  local py = tonumber(playerPos.y01)
  if not isFinite(playerMapID) or not isFinite(px) or not isFinite(py) then
    return false, "invalid_player_position"
  end

  if step.kind == "boat_crossing" then
    local targetMapID = tonumber(step.targetUiMapID)
    if playerMapID == targetMapID then
      return true, "boat_destination_map_reached"
    end
    return false, "awaiting_boat_arrival_map"
  end

  if step.kind ~= "travel" then
    return false, "unsupported_auto_arrival_kind"
  end

  local dest = step.destination
  local destMapID = tonumber(dest.uiMapID)
  if playerMapID ~= destMapID then
    return false, "different_ui_map"
  end

  if not (ns.Compat and ns.Compat.GetWorldDistanceYards) then
    return false, "missing_world_transform"
  end
  local dist = ns.Compat.GetWorldDistanceYards(destMapID, px, py, tonumber(dest.x01), tonumber(dest.y01))
  if type(dist) ~= "table" or dist.status ~= "ok" or not isFinite(dist.yards) then
    return false, (type(dist) == "table" and dist.reason) or "missing_world_transform"
  end

  local radiusYards = tonumber(step.arrivalRadiusYards) or 30
  if dist.yards <= radiusYards then
    return true, "within_world_yards"
  end
  return false, "outside_arrival_radius"
end

local function findStepIndex(steps, stepID)
  if not stepID then
    return nil
  end
  for i, s in ipairs(steps or {}) do
    if s.stepID == stepID then
      return i
    end
  end
  return nil
end

local function findFirstStepIndexForMap(steps, uiMapID, catalog)
  local m = tonumber(uiMapID)
  if not isFinite(m) then
    return nil
  end
  for i, s in ipairs(steps or {}) do
    if GoldFarms.ValidateStepDestination(s, catalog) then
      local destMapID = s.destination and tonumber(s.destination.uiMapID)
      if destMapID == m then
        return i
      end
    end
  end
  return nil
end

local function isStepEffectivelyCompleted(step, stepIndex, completedMap, manualPinnedStepID, entryStartIdx)
  if type(step) ~= "table" or step.kind == "grind" then
    return false
  end
  if manualPinnedStepID ~= nil and step.stepID == manualPinnedStepID then
    return false
  end
  if completedMap and completedMap[step.stepID] then
    return true
  end
  if (tonumber(stepIndex) or 1) < (tonumber(entryStartIdx) or 1) then
    return true
  end
  return false
end

local function selectDefaultActiveStep(farm, completedMap, manualPinnedStepID, entryStartIdx, catalog)
  local steps = farm.travelSteps or {}
  for i, s in ipairs(steps) do
    if GoldFarms.ValidateStepDestination(s, catalog) then
      if not isStepEffectivelyCompleted(s, i, completedMap, manualPinnedStepID, entryStartIdx) then
        return s, i
      end
    end
  end
  return steps[#steps], #steps
end

-- Strictly READ-ONLY evaluation (Astra P1-9 & Gate 6).
-- Never mutates `progress` (`currentStepID`, `completedTravelSteps`, `manualPinnedStepID`, `tripStartPlayerUiMapID`) or telemetry!
function GoldFarms.Evaluate(catalog, progress, playerPos)
  catalog = catalog or (ns.State and ns.State.GetCompiledGoldFarms and ns.State.GetCompiledGoldFarms())
  progress = progress or (ns.State and ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress())
  if not catalog or not progress then
    return { valid = false, reason = "missing_catalog_or_progress" }
  end

  local farm = nil
  if progress.selectedFarmID then
    farm = (catalog.farmsByID and catalog.farmsByID[progress.selectedFarmID]) or nil
  end
  if not farm then
    return {
      valid = true,
      mode = progress.mode or "paused",
      farm = nil,
      activeStep = nil,
      stepIndex = 0,
      totalSteps = 0,
      inFarmZone = false,
    }
  end

  local steps = farm.travelSteps or {}
  local completedMap = progress.completedTravelSteps or {}
  local pinnedID = progress.manualPinnedStepID

  local pos = playerPos
  if pos == nil and progress.mode == "standalone" and ns.Compat and ns.Compat.GetPlayerPosition01 then
    pos = ns.Compat.GetPlayerPosition01()
  end

  local liveMapID = (type(pos) == "table" and pos.status == "ok" and isFinite(tonumber(pos.uiMapID)))
    and tonumber(pos.uiMapID)
    or nil
  local effectiveMapID = liveMapID or tonumber(progress.tripStartPlayerUiMapID)
  local inFarmZone = (liveMapID ~= nil and liveMapID == tonumber(farm.uiMapID))
  local farmStartIdx = findFirstStepIndexForMap(steps, farm.uiMapID, catalog) or 1
  local entryStartIdx = findFirstStepIndexForMap(steps, effectiveMapID, catalog) or 1

  local activeIdx = nil
  local activeStep = nil

  -- 1. Explicit `Prev` manual pin takes highest precedence until cleared by arrival, `Next`, `Re-route`, or `Start`.
  if pinnedID then
    local pIdx = findStepIndex(steps, pinnedID)
    if pIdx and GoldFarms.ValidateStepDestination(steps[pIdx], catalog) then
      activeIdx = pIdx
      activeStep = steps[pIdx]
    end
  end

  -- 2. Otherwise inspect `progress.currentStepID` without mutating it.
  if not activeStep and progress.currentStepID then
    local cIdx = findStepIndex(steps, progress.currentStepID)
    local cand = cIdx and steps[cIdx] or nil
    if cand and GoldFarms.ValidateStepDestination(cand, catalog) then
      local candMapID = cand.destination and tonumber(cand.destination.uiMapID)
      local candMapFirstIdx = findFirstStepIndexForMap(steps, candMapID, catalog) or 1
      -- If live position moved backward out of a later route map (e.g. hearthed from Swamp/Deadwind/Badlands to Stormwind/Duskwood),
      -- dynamically recompute entry from `entryStartIdx` without mutating `progress`!
      if liveMapID ~= nil and entryStartIdx < candMapFirstIdx then
        local tripCompleted = {}
        for k, v in pairs(completedMap) do
          tripCompleted[k] = v
        end
        for i = entryStartIdx, farmStartIdx - 1 do
          if steps[i] then
            tripCompleted[steps[i].stepID] = nil
          end
        end
        activeStep, activeIdx = selectDefaultActiveStep(farm, tripCompleted, pinnedID, entryStartIdx, catalog)
      elseif not isStepEffectivelyCompleted(cand, cIdx, completedMap, pinnedID, entryStartIdx) then
        activeStep = cand
        activeIdx = cIdx
      end
    end
  end

  if not activeStep then
    activeStep, activeIdx = selectDefaultActiveStep(farm, completedMap, pinnedID, entryStartIdx, catalog)
  end

  return {
    valid = true,
    mode = progress.mode or "paused",
    farm = farm,
    activeStep = activeStep,
    stepIndex = activeIdx or 0,
    totalSteps = #steps,
    inFarmZone = inFarmZone,
    entryStartIndex = entryStartIdx,
  }
end

-- Active mutating reconciliation ONLY when standalone Gold Farm navigation is active.
function GoldFarms.ReconcileActive(catalog, progress, playerPos)
  catalog = catalog or (ns.State and ns.State.GetCompiledGoldFarms and ns.State.GetCompiledGoldFarms())
  progress = progress or (ns.State and ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress())
  if not catalog or not progress then
    return { valid = false, reason = "missing_catalog_or_progress" }
  end

  if progress.mode ~= "standalone" then
    return GoldFarms.Evaluate(catalog, progress, playerPos)
  end
  if ns.UI and ns.UI.Navigation and ns.UI.Navigation.activeContext == "riverglades" then
    return GoldFarms.Evaluate(catalog, progress, playerPos)
  end

  local farm = progress.selectedFarmID and catalog.farmsByID and catalog.farmsByID[progress.selectedFarmID] or nil
  if not farm then
    return GoldFarms.Evaluate(catalog, progress, playerPos)
  end

  local steps = farm.travelSteps or {}
  progress.completedTravelSteps = progress.completedTravelSteps or {}

  local pos = playerPos
  if pos == nil and ns.Compat and ns.Compat.GetPlayerPosition01 then
    pos = ns.Compat.GetPlayerPosition01()
  end

  local liveMapID = (type(pos) == "table" and pos.status == "ok" and isFinite(tonumber(pos.uiMapID)))
    and tonumber(pos.uiMapID)
    or nil
  local inFarmZone = (liveMapID ~= nil and liveMapID == tonumber(farm.uiMapID))
  local farmStartIdx = findFirstStepIndexForMap(steps, farm.uiMapID, catalog) or 1
  local entryStartIdx = findFirstStepIndexForMap(steps, liveMapID or progress.tripStartPlayerUiMapID, catalog) or 1

  -- Trip-scoped entry sync: if the player moved backward from a later route map (e.g. hearthed out of Swamp/Deadwind/Badlands)
  -- without manually pinning a step, reopen pre-farm transit steps from `entryStartIdx` and update `tripStartPlayerUiMapID`.
  if liveMapID ~= nil and not progress.manualPinnedStepID then
    if progress.tripStartPlayerUiMapID == nil then
      progress.tripStartPlayerUiMapID = liveMapID
    end
    local curIdx = findStepIndex(steps, progress.currentStepID)
    local curStep = curIdx and steps[curIdx] or nil
    local curMapFirstIdx = (curStep and curStep.destination and findFirstStepIndexForMap(steps, curStep.destination.uiMapID, catalog)) or 1
    if entryStartIdx < curMapFirstIdx then
      for i = entryStartIdx, farmStartIdx - 1 do
        if steps[i] then
          progress.completedTravelSteps[steps[i].stepID] = nil
        end
      end
      progress.tripStartPlayerUiMapID = liveMapID
      progress.currentStepID = nil
    else
      local savedEntryIdx = findFirstStepIndexForMap(steps, progress.tripStartPlayerUiMapID, catalog) or 1
      if entryStartIdx > savedEntryIdx then
        progress.tripStartPlayerUiMapID = liveMapID
      end
    end
  end

  local eval = GoldFarms.Evaluate(catalog, progress, pos)
  local activeStep = eval.activeStep
  local activeIdx = eval.stepIndex

  if activeStep and GoldFarms.CheckHopArrival(activeStep, pos, catalog) then
    progress.manualPinnedStepID = nil
    progress.completedTravelSteps[activeStep.stepID] = {
      completedAt = nowTimestamp(),
      reason = (activeStep.kind == "boat_crossing") and "boat_crossing_arrival" or "hop_arrival",
      uiMapID = pos.uiMapID,
      x01 = pos.x01,
      y01 = pos.y01,
    }
    if activeIdx and steps[activeIdx + 1] then
      activeIdx = activeIdx + 1
      activeStep = steps[activeIdx]
    else
      activeStep, activeIdx = selectDefaultActiveStep(farm, progress.completedTravelSteps, nil, entryStartIdx, catalog)
    end
  end

  progress.currentStepID = activeStep and activeStep.stepID or nil
  if ns.State and ns.State.SetGoldFarmActivityPhase and activeStep then
    ns.State.SetGoldFarmActivityPhase(activeStep.kind)
  end

  return {
    valid = true,
    mode = progress.mode,
    farm = farm,
    activeStep = activeStep,
    stepIndex = activeIdx or 0,
    totalSteps = #steps,
    inFarmZone = inFarmZone,
    entryStartIndex = entryStartIdx,
  }
end

function GoldFarms.Reconcile(catalog, progress, playerPos)
  progress = progress or (ns.State and ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress())
  if progress and progress.mode == "standalone" then
    return GoldFarms.ReconcileActive(catalog, progress, playerPos)
  end
  return GoldFarms.Evaluate(catalog, progress, playerPos)
end

-- Completes the active `vendor` service step ONLY when `MERCHANT_CLOSED` fires near the vendor NPC (Astra P1-6 & Gate 5).
function GoldFarms.CompleteVendorStepIfNear(catalog, progress, playerPos)
  catalog = catalog or (ns.State and ns.State.GetCompiledGoldFarms and ns.State.GetCompiledGoldFarms())
  progress = progress or (ns.State and ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress())
  if not catalog or not progress or progress.mode ~= "standalone" then
    return false, "not_active_standalone"
  end

  local pos = playerPos
  if pos == nil and ns.Compat and ns.Compat.GetPlayerPosition01 then
    pos = ns.Compat.GetPlayerPosition01()
  end

  local eval = GoldFarms.Evaluate(catalog, progress, pos)
  local step = eval and eval.activeStep
  if not step or step.kind ~= "vendor" then
    return false, "not_on_vendor_step"
  end
  if type(pos) ~= "table" or pos.status ~= "ok" then
    return false, "player_position_unavailable"
  end
  local dest = step.destination
  if tonumber(pos.uiMapID) ~= tonumber(dest.uiMapID) then
    return false, "different_ui_map"
  end
  if not (ns.Compat and ns.Compat.GetWorldDistanceYards) then
    return false, "missing_world_transform"
  end
  local dist = ns.Compat.GetWorldDistanceYards(dest.uiMapID, tonumber(pos.x01), tonumber(pos.y01), tonumber(dest.x01), tonumber(dest.y01))
  if type(dist) ~= "table" or dist.status ~= "ok" or not isFinite(dist.yards) then
    return false, "missing_world_transform"
  end
  local radiusYards = tonumber(step.arrivalRadiusYards) or 25
  if dist.yards > radiusYards then
    return false, "outside_vendor_radius"
  end

  progress.completedTravelSteps = progress.completedTravelSteps or {}
  progress.manualPinnedStepID = nil
  progress.completedTravelSteps[step.stepID] = {
    completedAt = nowTimestamp(),
    reason = "merchant_closed",
    uiMapID = pos.uiMapID,
    x01 = pos.x01,
    y01 = pos.y01,
  }

  local steps = (eval.farm and eval.farm.travelSteps) or {}
  local nextIdx = (eval.stepIndex or 1) + 1
  if steps[nextIdx] then
    progress.currentStepID = steps[nextIdx].stepID
  end

  local afterEval = GoldFarms.ReconcileActive(catalog, progress, pos)
  return true, afterEval
end

local function pauseRivergladesForMutualExclusion()
  if ns.State and ns.State.GetRouteProgress then
    local rgProg = ns.State.GetRouteProgress()
    if rgProg then
      if rgProg.mode ~= "paused" then
        if ns.Domain and ns.Domain.RouteProgress and ns.Domain.RouteProgress.Pause then
          ns.Domain.RouteProgress.Pause(nil, rgProg)
        else
          rgProg.mode = "paused"
        end
        if ns.UI and ns.UI.Navigation and ns.UI.Navigation.HideRivergladesHUD then
          ns.UI.Navigation.HideRivergladesHUD()
        end
      end
      rgProg.pausedHudRetained = false
    end
  end
  if ns.UI and ns.UI.Navigation and ns.UI.Navigation.RequestContextSwitch then
    ns.UI.Navigation.RequestContextSwitch("gold_farm")
  end
end

function GoldFarms.Start(farmQuery, catalog, progress, playerPos)
  catalog = catalog or (ns.State and ns.State.GetCompiledGoldFarms and ns.State.GetCompiledGoldFarms())
  progress = progress or (ns.State and ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress())
  if not catalog or not progress then
    return false, "Gold farms data or state unavailable."
  end

  local effectiveQuery = farmQuery
  if (effectiveQuery == nil or effectiveQuery == "") and progress.selectedFarmID then
    effectiveQuery = progress.selectedFarmID
  end

  local farm, resolveErr = GoldFarms.ResolveFarm(effectiveQuery, catalog)
  if not farm then
    return false, resolveErr
  end

  pauseRivergladesForMutualExclusion()
  progress.pausedHudRetained = false

  local pos = playerPos
  if pos == nil and ns.Compat and ns.Compat.GetPlayerPosition01 then
    pos = ns.Compat.GetPlayerPosition01()
  end
  local liveMapID = (type(pos) == "table" and pos.status == "ok" and isFinite(tonumber(pos.uiMapID)))
    and math.floor(tonumber(pos.uiMapID))
    or nil

  if progress.selectedFarmID ~= farm.farmID then
    progress.selectedFarmID = farm.farmID
    progress.currentStepID = nil
    progress.manualPinnedStepID = nil
    progress.tripStartPlayerUiMapID = liveMapID
    progress.completedTravelSteps = {}
  else
    progress.manualPinnedStepID = nil
    if liveMapID ~= nil then
      local steps = farm.travelSteps or {}
      local farmStartIdx = findFirstStepIndexForMap(steps, farm.uiMapID, catalog) or 1
      local newEntryIdx = findFirstStepIndexForMap(steps, liveMapID, catalog) or 1
      local curIdx = findStepIndex(steps, progress.currentStepID)
      local curStep = curIdx and steps[curIdx] or nil
      local curMapFirstIdx = (curStep and curStep.destination and findFirstStepIndexForMap(steps, curStep.destination.uiMapID, catalog)) or 1
      if newEntryIdx < curMapFirstIdx then
        progress.completedTravelSteps = progress.completedTravelSteps or {}
        for i = newEntryIdx, farmStartIdx - 1 do
          if steps[i] then
            progress.completedTravelSteps[steps[i].stepID] = nil
          end
        end
        progress.currentStepID = nil
      end
      progress.tripStartPlayerUiMapID = liveMapID
    end
  end

  if ns.Bridges and ns.Bridges.RXPBridge and ns.Bridges.RXPBridge.IsGoldFarmGuideSelected
    and ns.Bridges.RXPBridge.IsGoldFarmGuideSelected(farm.farmID, catalog)
  then
    progress.mode = "rxp"
  else
    progress.mode = "standalone"
  end

  local eval
  if progress.mode == "standalone" then
    eval = GoldFarms.ReconcileActive(catalog, progress, pos)
  else
    eval = GoldFarms.Evaluate(catalog, progress, pos)
    progress.currentStepID = eval.activeStep and eval.activeStep.stepID or nil
  end

  if ns.State and ns.State.StartOrResumeGoldFarmSession then
    local initialPhase
    if progress.mode == "rxp" then
      initialPhase = "rxp_untracked"
    elseif eval and eval.activeStep and eval.activeStep.kind == "grind" then
      initialPhase = "camp"
    else
      initialPhase = "travel_service"
    end
    ns.State.StartOrResumeGoldFarmSession(farm.farmID, nil, nil, initialPhase)
  end

  return true, eval
end

function GoldFarms.RestartEntryFromCurrentZone(catalog, progress, playerPos)
  catalog = catalog or (ns.State and ns.State.GetCompiledGoldFarms and ns.State.GetCompiledGoldFarms())
  progress = progress or (ns.State and ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress())
  if not catalog or not progress or not progress.selectedFarmID then
    return false, "No gold farm selected. Use '/fh gold start <1-5>' first."
  end
  local farm = catalog.farmsByID and catalog.farmsByID[progress.selectedFarmID] or nil
  if not farm then
    return false, "Selected gold farm not found."
  end

  local pos = playerPos
  if pos == nil and ns.Compat and ns.Compat.GetPlayerPosition01 then
    pos = ns.Compat.GetPlayerPosition01()
  end
  local liveMapID = (type(pos) == "table" and pos.status == "ok" and isFinite(tonumber(pos.uiMapID)))
    and math.floor(tonumber(pos.uiMapID))
    or nil

  local steps = farm.travelSteps or {}
  local farmStartIdx = findFirstStepIndexForMap(steps, farm.uiMapID, catalog) or 1
  progress.completedTravelSteps = progress.completedTravelSteps or {}
  for i = 1, farmStartIdx - 1 do
    if steps[i] then
      progress.completedTravelSteps[steps[i].stepID] = nil
    end
  end
  progress.manualPinnedStepID = nil
  progress.currentStepID = nil
  progress.tripStartPlayerUiMapID = liveMapID

  local eval
  if progress.mode == "standalone" then
    eval = GoldFarms.ReconcileActive(catalog, progress, pos)
  else
    eval = GoldFarms.Evaluate(catalog, progress, pos)
    progress.currentStepID = eval.activeStep and eval.activeStep.stepID or nil
    if progress.mode == "rxp" and ns.State and ns.State.SetGoldFarmActivityPhase then
      ns.State.SetGoldFarmActivityPhase("rxp_untracked")
    end
  end
  return true, eval
end

function GoldFarms.Pause(catalog, progress)
  progress = progress or (ns.State and ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress())
  if not progress then
    return false, "Gold farm progress unavailable."
  end
  progress.mode = "paused"
  progress.pausedHudRetained = (progress.selectedFarmID ~= nil)
  if ns.State and ns.State.PauseGoldFarmSession then
    ns.State.PauseGoldFarmSession(nil, nil)
  end
  local eval = GoldFarms.Evaluate(catalog, progress, { status = "unavailable" })
  return true, eval
end

function GoldFarms.Stop(resetHops, catalog, progress)
  progress = progress or (ns.State and ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress())
  if not progress then
    return false, "Gold farm progress unavailable."
  end
  progress.mode = "paused"
  progress.pausedHudRetained = false
  if ns.State and ns.State.PauseGoldFarmSession then
    ns.State.PauseGoldFarmSession(nil, nil)
  end
  if resetHops then
    progress.currentStepID = nil
    progress.manualPinnedStepID = nil
    progress.tripStartPlayerUiMapID = nil
    progress.completedTravelSteps = {}
    if ns.State and ns.State.ResetGoldFarmSession then
      ns.State.ResetGoldFarmSession(progress.selectedFarmID, false)
    end
  end
  local eval = GoldFarms.Evaluate(catalog, progress, { status = "unavailable" })
  return true, eval
end

function GoldFarms.NextHop(catalog, progress)
  catalog = catalog or (ns.State and ns.State.GetCompiledGoldFarms and ns.State.GetCompiledGoldFarms())
  progress = progress or (ns.State and ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress())
  if not catalog or not progress or not progress.selectedFarmID then
    return false, "No gold farm selected. Use '/fh gold start 1' first."
  end

  local evalBefore = GoldFarms.Evaluate(catalog, progress)
  local farm = evalBefore.farm
  if not farm then
    return false, "Selected gold farm not found."
  end
  local steps = farm.travelSteps or {}
  local curIdx = evalBefore.stepIndex or 1
  local curStep = steps[curIdx]

  progress.completedTravelSteps = progress.completedTravelSteps or {}
  progress.manualPinnedStepID = nil
  if curStep and curStep.kind ~= "grind" then
    progress.completedTravelSteps[curStep.stepID] = {
      completedAt = nowTimestamp(),
      reason = "manual_next",
    }
  end

  local nextIdx = curIdx + 1
  if nextIdx > #steps then
    -- Cycle back to the first sticky grind camp so the user can toggle Camp A <-> Camp B seamlessly
    nextIdx = 1
    for i, s in ipairs(steps) do
      if s.kind == "grind" then
        nextIdx = i
        break
      end
    end
  end

  local nextStep = steps[nextIdx]
  progress.currentStepID = nextStep and nextStep.stepID or nil
  if ns.State and ns.State.SetGoldFarmActivityPhase and nextStep then
    ns.State.SetGoldFarmActivityPhase(nextStep.kind)
  end

  local evalAfter = GoldFarms.Evaluate(catalog, progress, { status = "unavailable" })
  return true, evalAfter
end

function GoldFarms.PrevHop(catalog, progress)
  catalog = catalog or (ns.State and ns.State.GetCompiledGoldFarms and ns.State.GetCompiledGoldFarms())
  progress = progress or (ns.State and ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress())
  if not catalog or not progress or not progress.selectedFarmID then
    return false, "No gold farm selected. Use '/fh gold start 1' first."
  end

  local evalBefore = GoldFarms.Evaluate(catalog, progress)
  local farm = evalBefore.farm
  if not farm then
    return false, "Selected gold farm not found."
  end
  local steps = farm.travelSteps or {}
  local curIdx = evalBefore.stepIndex or 1
  if curIdx <= 1 then
    return false, "Already at Hop #1 (" .. tostring(steps[1] and steps[1].title or "") .. ")."
  end

  local prevIdx = curIdx - 1
  local prevStep = steps[prevIdx]
  progress.completedTravelSteps = progress.completedTravelSteps or {}
  if prevStep then
    progress.completedTravelSteps[prevStep.stepID] = nil
    progress.currentStepID = prevStep.stepID
    progress.manualPinnedStepID = prevStep.stepID
    if ns.State and ns.State.SetGoldFarmActivityPhase then
      ns.State.SetGoldFarmActivityPhase(prevStep.kind)
    end
  end

  local evalAfter = GoldFarms.Evaluate(catalog, progress, { status = "unavailable" })
  return true, evalAfter
end

function GoldFarms.GetReservationWarningsForFarm(farm, inventorySnapshot, orderedReservations)
  if type(farm) ~= "table" or type(farm.watchedMaterialItemIDs) ~= "table" then
    return {}
  end
  if not (ns.Domain and ns.Domain.Reservations and ns.Domain.Reservations.GetMaterialStatus) then
    return {}
  end

  local warnings = {}
  for _, itemID in ipairs(farm.watchedMaterialItemIDs) do
    local st = ns.Domain.Reservations.GetMaterialStatus(itemID, inventorySnapshot, orderedReservations)
    if st and (tonumber(st.reservedTotal) or 0) > 0 then
      local matEntry = ns.Data and ns.Data.materialsByItemID and ns.Data.materialsByItemID[itemID]
      local matName = (matEntry and matEntry.name) or MATERIAL_NAMES_FALLBACK[itemID] or ("Item #" .. tostring(itemID))
      table.insert(warnings, {
        itemID = itemID,
        name = matName,
        reservedTotal = st.reservedTotal,
        charOwned = st.charOwned or 0,
        unreservedTotal = st.unreservedTotal or 0,
        message = string.format(
          "Reservation Guard: %s has %d reserved (%d unreserved) — only vendor/bandage UNRESERVED surplus!",
          matName,
          st.reservedTotal,
          st.unreservedTotal or 0
        ),
      })
    end
  end
  return warnings
end

-- Honest Cash-Flow Telemetry & Conditional Mount ETA (Astra P0-4, Economic Fixes, Gates 7 & 8):
-- - Metric is labeled "Net Purse Change / Active Hr" (never "Raw GPH").
-- - Negative cash flow (e.g. repairs/flights) stays signed negative — NEVER clamped to 0g/hr!
-- - Unknown money or invalid target NEVER claims "Mount Funded!".
-- - ETA is suppressed whenever contaminated, < 180s sample, <= 0 rate, or fundingStatus ~= "shortfall".
-- - Unrealized Silk bandage value (`20 Silk -> 10 bandages = 40s`) is reported separately, never added to purse delta.
function GoldFarms.EvaluateGPHAndMountETA(farm, sessionSnap, mountTracker, silkStatus)
  local gphMeta = (type(farm) == "table" and type(farm.gphMeta) == "table") and farm.gphMeta or {}
  local lowG = tonumber(gphMeta.lowGold) or 0
  local highG = tonumber(gphMeta.highGold) or 0
  local communityLabel = string.format("%d-%dg/hr (Community Est. — Unverified)", lowG, highG)

  sessionSnap = sessionSnap or (ns.State and ns.State.GetGoldFarmSessionSnapshot and ns.State.GetGoldFarmSessionSnapshot()) or {}
  mountTracker = mountTracker or (ns.State and ns.State.GetMountTracker and ns.State.GetMountTracker()) or {}

  local rawTarget = tonumber(mountTracker.trainerQuoteCopper)
  local targetValid = isFinite(rawTarget) and rawTarget > 0
  local targetCopper = targetValid and math.floor(rawTarget) or 900000
  local reserveCopper = math.max(0, math.floor(tonumber(mountTracker.cashReserveCopper) or 0))
  local quoteStatus = tostring(mountTracker.quoteStatus or "unconfirmed_default")
  local zeroReserveWarning = (reserveCopper == 0)

  local moneyAvailable = (sessionSnap.moneyAvailable == true) and isFinite(tonumber(sessionSnap.currentCopper))
  local curCopper = moneyAvailable and math.floor(tonumber(sessionSnap.currentCopper)) or nil

  local fundingStatus = "unknown"
  local shortfallCopper = nil
  local spendableCopper = nil
  if moneyAvailable and targetValid then
    spendableCopper = math.max(0, curCopper - reserveCopper)
    shortfallCopper = math.max(0, targetCopper - spendableCopper)
    if shortfallCopper == 0 then
      fundingStatus = "funded"
    else
      fundingStatus = "shortfall"
    end
  end

  if silkStatus == nil and ns.Domain and ns.Domain.Reservations and ns.Domain.Reservations.GetMaterialStatus then
    silkStatus = ns.Domain.Reservations.GetMaterialStatus(4306)
  end
  local unrealizedSilkBandages = nil
  if ns.Domain and ns.Domain.RewardValue and ns.Domain.RewardValue.EvaluateSilkBandageConversion then
    unrealizedSilkBandages = ns.Domain.RewardValue.EvaluateSilkBandageConversion(silkStatus)
  end

  local elapsed = math.max(0, math.floor(tonumber(sessionSnap.elapsedSeconds) or 0))
  local campSeconds = math.max(0, math.floor(tonumber(sessionSnap.campSeconds) or 0))
  local travelAndServiceSeconds = math.max(0, math.floor(tonumber(sessionSnap.travelAndServiceSeconds) or 0))
  local rxpUntrackedSeconds = math.max(0, math.floor(tonumber(sessionSnap.rxpUntrackedSeconds) or 0))
  local phaseTimingAvailable = (sessionSnap.phaseTimingAvailable ~= false)
  local deltaCopper = math.floor(tonumber(sessionSnap.netCopperDelta) or 0)
  local isPaused = not (sessionSnap.active == true)
  local contaminated = (sessionSnap.contaminated == true)
  local cleanInterval = (sessionSnap.cleanIntervalConfirmed ~= false) and not contaminated

  local measuredCopperPerHour = nil
  local etaMinutesMeasured = nil
  local etaSuppressionReason = nil
  local liveStatus = "idle"
  local liveLabel = "Paused / Not started (click Navigate or /fh gold start)"

  local pausePrefix = ""
  if isPaused and elapsed > 0 then
    if sessionSnap.pausedForWindow then
      pausePrefix = "[PAUSED: non-farm window] "
    elseif sessionSnap.pausedByReload then
      pausePrefix = "[PAUSED after /reload] "
    else
      pausePrefix = "[PAUSED] "
    end
  end

  if elapsed > 0 or sessionSnap.active then
    if not moneyAvailable then
      liveStatus = "purse_unknown"
      etaSuppressionReason = "purse_unknown"
      liveLabel = string.format(
        "%sPurse Unknown (%ds active — live money unavailable)",
        pausePrefix,
        elapsed
      )
    elseif elapsed < MIN_GPH_SAMPLE_SECONDS then
      liveStatus = isPaused and "paused_warming_up" or "warming_up"
      etaSuppressionReason = "insufficient_sample_seconds"
      liveLabel = string.format(
        "%sWarming up (%ds/%ds min sample, Net %s)",
        pausePrefix,
        elapsed,
        MIN_GPH_SAMPLE_SECONDS,
        ns.Compat.FormatSignedCopper(deltaCopper)
      )
    else
      if deltaCopper >= 0 then
        measuredCopperPerHour = math.floor((deltaCopper * 3600) / elapsed + 0.5)
      else
        measuredCopperPerHour = -math.floor((math.abs(deltaCopper) * 3600) / elapsed + 0.5)
      end

      local rateStr = ns.Compat.FormatSignedCopper(measuredCopperPerHour) .. "/hr net purse change"
      local sampleMins = math.floor(elapsed / 60)

      if measuredCopperPerHour < 0 then
        liveStatus = "measured_negative"
        etaSuppressionReason = "negative_net_cash_flow"
        liveLabel = string.format(
          "%s%s (%dm active — repairs/flights exceed vendor sales so far)",
          pausePrefix,
          rateStr,
          sampleMins
        )
      elseif measuredCopperPerHour == 0 then
        liveStatus = "measured_zero"
        etaSuppressionReason = "zero_net_cash_flow"
        liveLabel = string.format(
          "%s0c/hr net purse change (%dm active — vendor grey trash to realize coin)",
          pausePrefix,
          sampleMins
        )
      else
        liveStatus = isPaused and "measured_paused" or "measured_positive"
        if not cleanInterval then
          etaSuppressionReason = "session_contaminated"
          liveLabel = string.format(
            "%s%s (%dm active — ETA suppressed: mail/AH/trade/trainer in session; /fh gold reset for clean interval)",
            pausePrefix,
            rateStr,
            sampleMins
          )
        elseif fundingStatus == "unknown" then
          etaSuppressionReason = "funding_state_unknown"
          liveLabel = string.format(
            "%s%s (%dm active — purse/quote unavailable for mount ETA)",
            pausePrefix,
            rateStr,
            sampleMins
          )
        elseif fundingStatus == "funded" then
          etaSuppressionReason = "already_funded"
          liveLabel = string.format(
            "%s%s (%dm active — Mount Target Reached [%s])",
            pausePrefix,
            rateStr,
            sampleMins,
            quoteStatus == "user_confirmed" and "Confirmed Quote" or "Unconfirmed 90g Default"
          )
        else
          etaMinutesMeasured = math.ceil((shortfallCopper * 60) / measuredCopperPerHour)
          liveLabel = string.format(
            "%s%s (%dm active, ~%dm to %s mount target at current clean session rate)",
            pausePrefix,
            rateStr,
            sampleMins,
            etaMinutesMeasured,
            quoteStatus == "user_confirmed" and "confirmed" or "unconfirmed 90g"
          )
        end
      end
    end
  end

  return {
    metricName = "Net Purse Change / Active Hr",
    communityLowGold = lowG,
    communityHighGold = highG,
    communityConfidence = tostring(gphMeta.confidence or "community_estimate_unverified"),
    communityLabel = communityLabel,
    payoutBasis = tostring(gphMeta.payoutBasis or ""),
    liveStatus = liveStatus,
    liveLabel = liveLabel,
    isPaused = isPaused,
    pausedByReload = (sessionSnap.pausedByReload == true),
    pausedForWindow = (sessionSnap.pausedForWindow == true),
    contaminated = contaminated,
    contaminationReasons = sessionSnap.contaminationReasons or {},
    cleanIntervalConfirmed = cleanInterval,
    elapsedSeconds = elapsed,
    campSeconds = campSeconds,
    travelAndServiceSeconds = travelAndServiceSeconds,
    rxpUntrackedSeconds = rxpUntrackedSeconds,
    phaseTimingAvailable = phaseTimingAvailable,
    netCopperDelta = deltaCopper,
    measuredCopperPerHour = measuredCopperPerHour,
    etaMinutesMeasured = etaMinutesMeasured,
    etaSuppressionReason = etaSuppressionReason,
    fundingStatus = fundingStatus,
    shortfallCopper = shortfallCopper,
    spendableCopper = spendableCopper,
    targetCopper = targetCopper,
    reserveCopper = reserveCopper,
    quoteStatus = quoteStatus,
    zeroReserveWarning = zeroReserveWarning,
    unrealizedSilkBandages = unrealizedSilkBandages,
  }
end
