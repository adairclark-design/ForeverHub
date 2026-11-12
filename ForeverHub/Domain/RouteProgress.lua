local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.Domain = ns.Domain or {}

local RouteProgress = {}
ns.Domain.RouteProgress = RouteProgress

local function nowTimestamp()
  if type(time) == "function" then
    return time()
  end
  return 0
end

-- Checks whether player arrival satisfies an active `travel` action ONLY, using world-yard distance.
-- If world-space map dimensions are unavailable, retains manual completion (Astra P1-6).
-- Arrival NEVER marks `accept`, `objective`, or `turnin` actions complete (Astra P2).
function RouteProgress.CheckTravelArrival(action, playerPos)
  if type(action) ~= "table" or action.kind ~= "travel" then
    return false, "not_travel"
  end
  local dest = action.destination
  if type(dest) ~= "table" or dest.coordinateSpace ~= "uiMap01" then
    return false, "invalid_destination"
  end
  if type(playerPos) ~= "table" or playerPos.status ~= "ok" then
    return false, "player_position_unavailable"
  end
  if tonumber(playerPos.uiMapID) ~= tonumber(dest.uiMapID) then
    return false, "different_map"
  end
  if not (ns.Compat and ns.Compat.GetWorldDistanceYards) then
    return false, "missing_world_transform"
  end
  local distRes = ns.Compat.GetWorldDistanceYards(
    dest.uiMapID,
    playerPos.x01,
    playerPos.y01,
    dest.x01,
    dest.y01
  )
  if distRes.status ~= "ok" or type(distRes.yards) ~= "number" then
    return false, distRes.reason or "missing_world_transform"
  end
  local radiusYards = tonumber(action.arrivalRadiusYards or dest.arrivalRadiusYards) or 35
  return distRes.yards <= radiusYards, "ok"
end

-- Pure read-only evaluation for `/fh rg status` and `/fh rg doctor` (never mutates `progress`).
function RouteProgress.Evaluate(route, progress, ctx, playerPos)
  route = route or (ns.State and ns.State.GetCompiledRivergladesRoute())
  progress = progress or (ns.State and ns.State.GetRouteProgress())
  if not route or not progress then
    return { valid = false, reason = "missing_route_or_progress" }
  end
  local RoutePlanner = ns.Domain.RoutePlanner
  ctx = ctx or RoutePlanner.BuildDefaultContext()
  local pos = playerPos or (ns.Compat and ns.Compat.GetPlayerPosition01 and ns.Compat.GetPlayerPosition01()) or nil
  local eval = RoutePlanner.EvaluateRoute(route, progress, ctx, pos)
  eval.mode = progress.mode
  eval.currentActionID = eval.nextAction and eval.nextAction.actionID or nil
  return eval
end

-- Reconciles persisted progress against compiled route & live client quest/position state.
-- Does NOT mutate or rewrite compiled route tables!
function RouteProgress.Reconcile(route, progress, ctx, playerPos)
  route = route or (ns.State and ns.State.GetCompiledRivergladesRoute())
  progress = progress or (ns.State and ns.State.GetRouteProgress())
  if not route or not progress then
    return { valid = false, reason = "missing_route_or_progress" }
  end

  local RoutePlanner = ns.Domain.RoutePlanner
  ctx = ctx or RoutePlanner.BuildDefaultContext()
  local pos = playerPos or (ns.Compat and ns.Compat.GetPlayerPosition01 and ns.Compat.GetPlayerPosition01()) or nil

  -- First pass evaluation
  local eval = RoutePlanner.EvaluateRoute(route, progress, ctx, pos)

  -- Clear user-pinned action once it completes or is no longer available
  if progress.pinnedActionID then
    local pinEv = eval.byActionID and eval.byActionID[progress.pinnedActionID]
    if not pinEv or pinEv.state ~= "available" then
      progress.pinnedActionID = nil
      progress.pinnedSubLocationID = nil
    elseif progress.pinnedSubLocationID and pinEv.action and type(pinEv.action.subLocations) == "table" then
      local activeSubs = RoutePlanner.ResolveActiveSubLocations(pinEv.action, ctx)
      local stillActive = false
      for _, sl in ipairs(activeSubs) do
        if sl.subID == progress.pinnedSubLocationID then
          stillActive = true
          break
        end
      end
      if not stillActive then
        progress.pinnedSubLocationID = nil
      end
    end
  else
    progress.pinnedSubLocationID = nil
  end

  -- Record observed quest completion evidence on quests confirmed completed by API
  -- (while keeping travel arrival evidence separate so quest abandonment is reversible!)
  for _, row in ipairs(eval.evaluations) do
    local act = row.action
    if row.state == "completed" and act.kind ~= "travel" then
      progress.observedCompletionEvidence[act.actionID] = progress.observedCompletionEvidence[act.actionID]
        or {
          observedAt = nowTimestamp(),
          source = "live_quest_api",
          questID = act.questID,
          questKey = act.questKey,
        }
      if act.questKey and ns.State and ns.State.ClearUnresolvedQuestConfirmation then
        ns.State.ClearUnresolvedQuestConfirmation(act.questKey, progress)
      end
      -- If an action became genuinely completed in-game, clear any stale skip marker on it
      if progress.explicitlySkippedActions[act.actionID] then
        progress.explicitlySkippedActions[act.actionID] = nil
      end
    elseif act.kind ~= "travel" and act.kind ~= "manual" and row.state ~= "completed" then
      -- If a previously accepted quest was abandoned before completion, clear transient pickup evidence
      if progress.observedCompletionEvidence[act.actionID]
        and progress.observedCompletionEvidence[act.actionID].source == "live_quest_api"
      then
        progress.observedCompletionEvidence[act.actionID] = nil
      end
    end
  end

  -- Travel-step arrival check on the currently active travel step ONLY when running standalone
  -- (supports up to 4 stacked travel arrivals in one pass if standing inside multiple radii).
  if progress.mode == "standalone" and pos then
    for _ = 1, 4 do
      if not (eval.nextAction and eval.nextAction.kind == "travel") then
        break
      end
      if not RouteProgress.CheckTravelArrival(eval.nextAction, pos) then
        break
      end
      local arrivedID = eval.nextAction.actionID
      progress.observedCompletionEvidence[arrivedID] = {
        observedAt = nowTimestamp(),
        source = "travel_arrival",
        uiMapID = pos.uiMapID,
        x01 = pos.x01,
        y01 = pos.y01,
      }
      if progress.pinnedActionID == arrivedID then
        progress.pinnedActionID = nil
        progress.pinnedSubLocationID = nil
      end
      eval = RoutePlanner.EvaluateRoute(route, progress, ctx, pos)
    end
  end

  local nextSubID = nil
  if eval.nextAction and type(eval.nextAction.subLocations) == "table" and #eval.nextAction.subLocations > 0 then
    local _, _, activeSub = RoutePlanner.ResolveActiveActionTarget(eval.nextAction, progress, ctx, pos)
    nextSubID = activeSub and activeSub.subID or nil
  end
  progress.currentActionID = eval.nextAction and eval.nextAction.actionID or nil
  progress.currentSubLocationID = nextSubID
  eval.mode = progress.mode
  eval.currentActionID = progress.currentActionID
  eval.currentSubLocationID = progress.currentSubLocationID
  return eval
end

function RouteProgress.Start(route, progress, ctx, playerPos)
  route = route or (ns.State and ns.State.GetCompiledRivergladesRoute())
  progress = progress or (ns.State and ns.State.GetRouteProgress())
  if not route or not progress then
    return false, "Riverglades route data is not loaded."
  end

  -- Mutual exclusion: pause any active Gold Farm route before Riverglades acquires navigation
  if ns.State and ns.State.GetGoldFarmProgress then
    local goldProg = ns.State.GetGoldFarmProgress()
    if goldProg and goldProg.mode ~= "paused" then
      if ns.Domain and ns.Domain.GoldFarms and ns.Domain.GoldFarms.Pause then
        ns.Domain.GoldFarms.Pause(nil, goldProg)
      else
        goldProg.mode = "paused"
      end
    end
  end
  if ns.UI and ns.UI.Navigation and ns.UI.Navigation.RequestContextSwitch then
    ns.UI.Navigation.RequestContextSwitch("riverglades")
  end

  -- Check if user explicitly selected our exported guide in RXPGuides
  if ns.Bridges and ns.Bridges.RXPBridge and ns.Bridges.RXPBridge.IsRivergladesGuideSelected
    and ns.Bridges.RXPBridge.IsRivergladesGuideSelected()
  then
    progress.mode = "rxp"
  else
    progress.mode = "standalone"
  end

  local eval = RouteProgress.Reconcile(route, progress, ctx, playerPos)
  return true, eval
end

function RouteProgress.Pause(route, progress, ctx)
  progress = progress or (ns.State and ns.State.GetRouteProgress())
  if not progress then
    return false, "Route progress unavailable."
  end
  progress.mode = "paused"
  local eval = RouteProgress.Reconcile(route, progress, ctx)
  return true, eval
end

function RouteProgress.Stop(route, progress, ctx, resetSkips)
  progress = progress or (ns.State and ns.State.GetRouteProgress())
  if not progress then
    return false, "Route progress unavailable."
  end
  progress.mode = "paused"
  progress.currentActionID = nil
  progress.currentSubLocationID = nil
  progress.pinnedActionID = nil
  progress.pinnedSubLocationID = nil
  if resetSkips == true then
    progress.explicitlySkippedActions = {}
  end
  local eval = RouteProgress.Reconcile(route, progress, ctx)
  return true, eval
end

-- Manual `Next`: visibly records an explicit skip on the current action.
-- NEVER marks any quest complete!
function RouteProgress.SkipCurrentAction(route, progress, ctx)
  route = route or (ns.State and ns.State.GetCompiledRivergladesRoute())
  progress = progress or (ns.State and ns.State.GetRouteProgress())
  if not route or not progress then
    return false, "Route progress unavailable."
  end

  local before = RouteProgress.Reconcile(route, progress, ctx)
  local cur = before.nextAction
  if not cur then
    return false, "No active Riverglades step to skip."
  end

  progress.explicitlySkippedActions[cur.actionID] = {
    skippedAt = nowTimestamp(),
    reason = "manual_next",
    title = cur.title,
  }
  progress.currentActionID = nil
  progress.currentSubLocationID = nil
  progress.pinnedActionID = nil
  progress.pinnedSubLocationID = nil

  local after = RouteProgress.Reconcile(route, progress, ctx)
  return true, {
    skippedAction = cur,
    skippedActionID = cur.actionID,
    nextAction = after.nextAction,
    evaluation = after,
  }
end

-- Manual `Prev`: unskips the most recently skipped action or re-opens the preceding travel/manual step.
function RouteProgress.StepPreviousAction(route, progress, ctx)
  route = route or (ns.State and ns.State.GetCompiledRivergladesRoute())
  progress = progress or (ns.State and ns.State.GetRouteProgress())
  if not route or not progress then
    return false, "Route progress unavailable."
  end

  local curEval = RouteProgress.Reconcile(route, progress, ctx)
  local curIdx = #route.actions + 1
  if curEval.nextAction and curEval.byActionID[curEval.nextAction.actionID] then
    curIdx = curEval.byActionID[curEval.nextAction.actionID].orderIndex
  end

  local restoredAction = nil
  for i = curIdx - 1, 1, -1 do
    local act = route.actions[i]
    if progress.explicitlySkippedActions[act.actionID] then
      progress.explicitlySkippedActions[act.actionID] = nil
      progress.currentActionID = act.actionID
      progress.currentSubLocationID = nil
      progress.pinnedActionID = act.actionID
      restoredAction = act
      break
    elseif act.kind == "travel"
      and progress.observedCompletionEvidence[act.actionID]
      and progress.observedCompletionEvidence[act.actionID].source == "travel_arrival"
    then
      progress.observedCompletionEvidence[act.actionID] = nil
      progress.currentActionID = act.actionID
      progress.currentSubLocationID = nil
      progress.pinnedActionID = act.actionID
      restoredAction = act
      break
    end
  end

  if not restoredAction then
    return false, "No prior skipped or travel step to step back to."
  end

  local after = RouteProgress.Reconcile(route, progress, ctx)
  return true, {
    restoredAction = restoredAction,
    nextAction = after.nextAction,
    evaluation = after,
  }
end

-- Focuses a specific action (and optional subLocation) clicked on the World Map.
-- Un-skips if previously skipped, respects RXP ownership if RXP guide is selected (Astra P2 #2),
-- activates standalone navigation if paused, and reconciles.
function RouteProgress.FocusActionFromMapPin(actionID, subLocationID, route, progress, ctx, playerPos)
  route = route or (ns.State and ns.State.GetCompiledRivergladesRoute())
  progress = progress or (ns.State and ns.State.GetRouteProgress())
  if not route or not progress or type(actionID) ~= "string" or actionID == "" then
    return false, "Invalid map pin target."
  end

  if progress.explicitlySkippedActions and progress.explicitlySkippedActions[actionID] then
    progress.explicitlySkippedActions[actionID] = nil
  end
  progress.pinnedActionID = actionID
  progress.pinnedSubLocationID = (type(subLocationID) == "string" and subLocationID ~= "") and subLocationID or nil

  local rxpSelected = ns.Bridges
    and ns.Bridges.RXPBridge
    and ns.Bridges.RXPBridge.IsRivergladesGuideSelected
    and ns.Bridges.RXPBridge.IsRivergladesGuideSelected()
    or false

  if rxpSelected then
    progress.mode = "rxp"
    local eval = RouteProgress.Reconcile(route, progress, ctx, playerPos)
    return true, eval
  end

  if progress.mode == "paused" then
    return RouteProgress.Start(route, progress, ctx, playerPos)
  end

  local eval = RouteProgress.Reconcile(route, progress, ctx, playerPos)
  return true, eval
end

function RouteProgress.ClearPinnedFocus(route, progress, ctx, playerPos)
  route = route or (ns.State and ns.State.GetCompiledRivergladesRoute())
  progress = progress or (ns.State and ns.State.GetRouteProgress())
  if not route or not progress then
    return false, "Route progress unavailable."
  end
  progress.pinnedActionID = nil
  progress.pinnedSubLocationID = nil
  local eval = RouteProgress.Reconcile(route, progress, ctx, playerPos)
  return true, eval
end
