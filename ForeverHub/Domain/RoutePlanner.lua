local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.Domain = ns.Domain or {}

local RoutePlanner = {}
ns.Domain.RoutePlanner = RoutePlanner

local SUBLOCATION_SWITCH_HYSTERESIS_YARDS = 65.0

function RoutePlanner.IsUsableReviewStatus(status)
  return status == "verified" or status == "estimated"
end

-- Converts normalized uiMap01 (0..1) coordinates to RXP percentage (0..100) coordinates.
function RoutePlanner.NormalizedToPercent(x01, y01)
  local x = tonumber(x01)
  local y = tonumber(y01)
  if not x or not y or x <= 0 or x >= 1 or y <= 0 or y >= 1 then
    return nil, nil
  end
  return x * 100.0, y * 100.0
end

-- Converts percentage (0..100) coordinates to normalized uiMap01 (0..1) coordinates.
function RoutePlanner.PercentToNormalized(xPct, yPct)
  local x = tonumber(xPct)
  local y = tonumber(yPct)
  if not x or not y or x <= 0 or x >= 100 or y <= 0 or y >= 100 then
    return nil, nil
  end
  return x / 100.0, y / 100.0
end

-- Closed-fail map conversion & coordinate-space validator (Astra P0-D).
function RoutePlanner.ValidateActionDestination(action, route)
  if type(action) ~= "table" then
    return false, "invalid_action"
  end
  local dest = action.destination
  if action.kind == "manual" and dest == nil then
    return true, "manual_no_pin"
  end
  if type(dest) ~= "table" then
    return false, "missing_destination"
  end
  if dest.coordinateSpace ~= "uiMap01" then
    return false, "invalid_coordinate_space"
  end
  local uiMapID = tonumber(dest.uiMapID)
  local areaID = tonumber(dest.areaID)
  local x01 = tonumber(dest.x01)
  local y01 = tonumber(dest.y01)
  if not uiMapID or not areaID or not x01 or not y01 then
    return false, "non_numeric_destination"
  end
  if x01 <= 0 or x01 >= 1 or y01 <= 0 or y01 >= 1 then
    return false, "out_of_bounds_or_zero_coords"
  end
  local areaMap = route and route.areaIdToUiMapId
  if type(areaMap) ~= "table" then
    return false, "missing_reviewed_map_mappings"
  end
  local mappedUiMap = tonumber(areaMap[areaID])
  if not mappedUiMap or mappedUiMap ~= uiMapID then
    return false, "unverified_area_to_uimap_conversion"
  end
  return true, "ok"
end

function RoutePlanner.BuildDefaultContext()
  local Compat = ns.Compat
  return {
    getPlayerFaction = function()
      return Compat.GetPlayerFactionString()
    end,
    getPlayerLevel = function()
      return Compat.GetPlayerLevel()
    end,
    getPlayerClassAndRace = function()
      return Compat.GetPlayerClassAndRace()
    end,
    isQuestCompleted = function(questRef)
      return Compat.IsQuestCompletedResult(questRef)
    end,
    isOnQuest = function(questRef)
      return Compat.IsOnQuestResult(questRef)
    end,
    getQuestObjectives = function(questRef)
      return Compat.GetQuestObjectivesResult(questRef)
    end,
    isQuestLogFull = function()
      return Compat.IsQuestLogFullResult()
    end,
    getQuestLogCapacity = function()
      if Compat.GetQuestLogCapacityResult then
        return Compat.GetQuestLogCapacityResult()
      end
      return Compat.IsQuestLogFullResult()
    end,
    isInCombat = function()
      if Compat.IsInCombat then
        return Compat.IsInCombat()
      end
      return false
    end,
    getQuestEvidence = function(questRef, opts)
      if Compat.GetQuestEvidenceResult then
        return Compat.GetQuestEvidenceResult(questRef, opts)
      end
      return nil
    end,
    getBagItemCount = function(itemID)
      if ns.Providers and ns.Providers.Inventory and ns.Providers.Inventory.GetItemCounts then
        local c = ns.Providers.Inventory.GetItemCounts(itemID)
        return { status = "ok", count = tonumber(c and c.bagCount) or 0 }
      end
      return { status = "unknown", count = nil }
    end,
  }
end

local function getQuestRef(node)
  if type(node) ~= "table" then
    return nil
  end
  if type(node.questKey) == "string" and node.questKey ~= "" then
    return node.questKey
  end
  return node.questID
end

local function lookupQuestMeta(route, questRef)
  if type(route) ~= "table" or questRef == nil then
    return nil
  end
  if type(questRef) == "number" and type(route.questsByID) == "table" then
    return route.questsByID[questRef]
  end
  if type(questRef) == "string" and type(route.questsByTitleKey) == "table" then
    return route.questsByTitleKey[questRef]
  end
  local numID = tonumber(questRef)
  if numID and type(route.questsByID) == "table" then
    return route.questsByID[numID]
  end
  return nil
end

-- Transitive mandatory chain-successor completion inference (Astra v0.7.1 P1 #5):
-- Permitted ONLY across `prereqConfidence == "artifact_verified"` prerequisite edges.
-- Preserves closed-fail ("unavailable" / "restricted") status from direct checks.
function RoutePlanner.IsQuestCompletedOrInferred(questRef, route, ctx, visited, memo)
  if questRef == nil then
    return { status = "unavailable", reason = "nil_quest_ref" }
  end
  local key = tostring(questRef)
  if memo and memo[key] ~= nil then
    return memo[key]
  end

  local r = ctx.isQuestCompleted(questRef)
  if type(r) ~= "table" then
    return { status = "unavailable", reason = "invalid_completion_result" }
  end
  if r.status ~= "ok" and r.reason ~= "title_history_unresolved" then
    return r
  end
  if r.status == "ok" and r.value == true then
    if memo then
      memo[key] = r
    end
    return r
  end

  local succList = route and type(route.questSuccessors) == "table" and route.questSuccessors[key] or nil
  if type(succList) == "table" and #succList > 0 then
    visited = visited or {}
    if not visited[key] then
      visited[key] = true
      for _, succRef in ipairs(succList) do
        local succMeta = lookupQuestMeta(route, succRef)
        if not succMeta or succMeta.prereqConfidence == "artifact_verified" then
          local onSucc = ctx.isOnQuest(succRef)
          if type(onSucc) == "table" and onSucc.status == "ok" and onSucc.value == true then
            local inferred = {
              status = "ok",
              value = true,
              inferredFrom = succRef,
              completionSource = "artifact_verified_successor",
            }
            if memo then
              memo[key] = inferred
            end
            visited[key] = nil
            return inferred
          end
          if not visited[tostring(succRef)] then
            local compSucc = RoutePlanner.IsQuestCompletedOrInferred(succRef, route, ctx, visited, memo)
            if type(compSucc) == "table" and compSucc.status == "ok" and compSucc.value == true then
              local inferred = {
                status = "ok",
                value = true,
                inferredFrom = compSucc.inferredFrom or succRef,
                completionSource = "artifact_verified_successor",
              }
              if memo then
                memo[key] = inferred
              end
              visited[key] = nil
              return inferred
            end
          end
        end
      end
      visited[key] = nil
    end
  end

  if memo then
    memo[key] = r
  end
  return r
end

function RoutePlanner.HasAnyRouteQuestStarted(route, ctx, memo)
  if type(route) ~= "table" then
    return false
  end
  if type(route.questsByID) == "table" then
    for qID, qMeta in pairs(route.questsByID) do
      if type(qMeta) == "table" and RoutePlanner.IsUsableReviewStatus(qMeta.reviewStatus) then
        local onRes = ctx.isOnQuest(qID)
        if type(onRes) == "table" and onRes.status == "ok" and onRes.value == true then
          return true
        end
        local compRes = RoutePlanner.IsQuestCompletedOrInferred(qID, route, ctx, nil, memo)
        if type(compRes) == "table" and compRes.status == "ok" and compRes.value == true then
          return true
        end
      end
    end
  end
  if type(route.questsByTitleKey) == "table" then
    for qKey, qMeta in pairs(route.questsByTitleKey) do
      if type(qMeta) == "table" and RoutePlanner.IsUsableReviewStatus(qMeta.reviewStatus) then
        local onRes = ctx.isOnQuest(qKey)
        if type(onRes) == "table" and onRes.status == "ok" and onRes.value == true then
          return true
        end
        local compRes = RoutePlanner.IsQuestCompletedOrInferred(qKey, route, ctx, nil, memo)
        if type(compRes) == "table" and compRes.status == "ok" and compRes.value == true then
          return true
        end
      end
    end
  end
  return false
end

-- Three-valued predicate evaluator: returns true, false, or "unknown".
-- Unknown prerequisites MUST NEVER evaluate to true!
function RoutePlanner.EvaluatePredicate(node, progress, ctx, route, memo)
  if node == nil then
    return true
  end
  if type(node) ~= "table" or type(node.op) ~= "string" then
    return "unknown", "malformed_predicate"
  end

  local op = node.op
  if op == "true" then
    return true
  elseif op == "unknown" then
    return "unknown", tostring(node.reason or "unverified_prerequisite")
  elseif op == "all" then
    local children = node.children
    if type(children) ~= "table" or #children == 0 then
      return "unknown", "empty_all_predicate"
    end
    local sawUnknown = false
    local unknownReason = nil
    for _, child in ipairs(children) do
      local res, rsn = RoutePlanner.EvaluatePredicate(child, progress, ctx, route, memo)
      if res == false then
        return false, rsn or "all_child_false"
      elseif res ~= true then
        sawUnknown = true
        unknownReason = unknownReason or rsn
      end
    end
    if sawUnknown then
      return "unknown", unknownReason or "all_child_unknown"
    end
    return true
  elseif op == "any" then
    -- Matches QuestieDB preQuestSingle semantics: satisfied if AT LEAST ONE child is true.
    local children = node.children
    if type(children) ~= "table" or #children == 0 then
      return "unknown", "empty_any_predicate"
    end
    local sawUnknown = false
    local unknownReason = nil
    for _, child in ipairs(children) do
      local res, rsn = RoutePlanner.EvaluatePredicate(child, progress, ctx, route, memo)
      if res == true then
        return true
      elseif res ~= false then
        sawUnknown = true
        unknownReason = unknownReason or rsn
      end
    end
    if sawUnknown then
      return "unknown", unknownReason or "any_child_unknown"
    end
    return false, "none_of_any_satisfied"
  elseif op == "not" then
    local res, rsn = RoutePlanner.EvaluatePredicate(node.child, progress, ctx, route, memo)
    if res == true then
      return false, "negated_true"
    elseif res == false then
      return true
    end
    return "unknown", rsn or "negated_unknown"
  elseif op == "quest_completed" then
    local qref = getQuestRef(node)
    local r = RoutePlanner.IsQuestCompletedOrInferred(qref, route, ctx, nil, memo)
    if type(r) == "table" and r.status == "ok" and type(r.value) == "boolean" then
      return r.value, r.value and nil or ("quest_not_completed:" .. tostring(qref))
    end
    return "unknown", "quest_completed_status_" .. tostring(r and r.status or "nil")
  elseif op == "quest_active" then
    local qref = getQuestRef(node)
    local r = ctx.isOnQuest(qref)
    if type(r) == "table" and r.status == "ok" and type(r.value) == "boolean" then
      return r.value, r.value and nil or ("quest_not_active:" .. tostring(qref))
    end
    return "unknown", "quest_active_status_" .. tostring(r and r.status or "nil")
  elseif op == "quest_active_or_completed" then
    local qref = getQuestRef(node)
    local rAct = ctx.isOnQuest(qref)
    local rComp = RoutePlanner.IsQuestCompletedOrInferred(qref, route, ctx, nil, memo)
    if (type(rAct) == "table" and rAct.status == "ok" and rAct.value == true)
      or (type(rComp) == "table" and rComp.status == "ok" and rComp.value == true)
    then
      return true
    end
    if type(rAct) == "table" and rAct.status == "ok" and rAct.value == false
      and type(rComp) == "table" and rComp.status == "ok" and rComp.value == false
    then
      return false, "quest_neither_active_nor_completed:" .. tostring(qref)
    end
    return "unknown", "quest_state_uncertain:" .. tostring(qref)
  elseif op == "quest_objectives_complete" then
    local qref = getQuestRef(node)
    local rComp = RoutePlanner.IsQuestCompletedOrInferred(qref, route, ctx, nil, memo)
    if type(rComp) == "table" and rComp.status == "ok" and rComp.value == true then
      return true
    end
    local qMeta = lookupQuestMeta(route, qref)
    if qMeta and qMeta.zeroObjectives == true then
      local rOn = ctx.isOnQuest(qref)
      if type(rOn) == "table" and rOn.status == "ok" and rOn.value == true then
        return true
      end
    end
    local rObj = ctx.getQuestObjectives(qref)
    if type(rObj) == "table" and rObj.status == "ok" and type(rObj.allFinished) == "boolean" then
      return rObj.allFinished, rObj.allFinished and nil or ("objectives_incomplete:" .. tostring(qref))
    end
    return "unknown", "objectives_status_" .. tostring(rObj and rObj.status or "nil")
  elseif op == "action_done_or_skipped" then
    local aid = tostring(node.actionID or "")
    local ev = progress and progress.observedCompletionEvidence and progress.observedCompletionEvidence[aid]
    local sk = progress and progress.explicitlySkippedActions and progress.explicitlySkippedActions[aid]
    if ev or sk then
      return true
    end
    return false, "prior_action_pending:" .. aid
  elseif op == "item_owned_or_quest_active" then
    local qref = getQuestRef(node)
    local rAct = qref and ctx.isOnQuest(qref) or { status = "ok", value = false }
    if type(rAct) == "table" and rAct.status == "ok" and rAct.value == true then
      return true
    end
    local rItem = ctx.getBagItemCount(node.itemID)
    if type(rItem) == "table" and rItem.status == "ok" and type(rItem.count) == "number" then
      if rItem.count > 0 then
        return true
      elseif type(rAct) == "table" and rAct.status == "ok" and rAct.value == false then
        return false, "missing_starter_item:" .. tostring(node.itemID)
      end
    end
    return "unknown", "starter_item_state_unknown"
  elseif op == "exclusive_none_completed" then
    local qList = node.questIDs
    if type(qList) ~= "table" then
      return "unknown", "invalid_exclusive_list"
    end
    local sawUnknown = false
    for _, exQID in ipairs(qList) do
      local rAct = ctx.isOnQuest(exQID)
      local rComp = RoutePlanner.IsQuestCompletedOrInferred(exQID, route, ctx, nil, memo)
      if (type(rAct) == "table" and rAct.status == "ok" and rAct.value == true)
        or (type(rComp) == "table" and rComp.status == "ok" and rComp.value == true)
      then
        return false, "exclusive_branch_taken:" .. tostring(exQID)
      end
      if not (type(rAct) == "table" and rAct.status == "ok" and type(rComp) == "table" and rComp.status == "ok") then
        sawUnknown = true
      end
    end
    if sawUnknown then
      return "unknown", "exclusive_branch_unknown"
    end
    return true
  end

  return "unknown", "unsupported_predicate_op:" .. tostring(op)
end

-- Checks faction, race, class, minimum level, optional group-branch, and optional [42+] Elite bounty eligibility.
-- Returns true, false, or "unknown", plus reason string.
function RoutePlanner.EvaluateEligibility(action, progress, ctx, route, memo)
  local elig = type(action.eligibility) == "table" and action.eligibility or {}

  if elig.faction then
    local pFaction = ctx.getPlayerFaction()
    if not pFaction then
      return "unknown", "player_faction_unknown"
    end
    if pFaction ~= elig.faction then
      return false, "wrong_faction:" .. tostring(pFaction)
    end
  end

  if elig.minLevel then
    local pLvl = tonumber(ctx.getPlayerLevel())
    if not pLvl then
      return "unknown", "player_level_unknown"
    end
    if pLvl < tonumber(elig.minLevel) then
      return false, string.format("below_min_level:%d<%d", pLvl, tonumber(elig.minLevel))
    end
  end

  if type(elig.classes) == "table" and #elig.classes > 0 then
    local cr = ctx.getPlayerClassAndRace()
    local pClass = cr and cr.classToken
    if not pClass then
      return "unknown", "player_class_unknown"
    end
    local match = false
    for _, c in ipairs(elig.classes) do
      if c == pClass then
        match = true
        break
      end
    end
    if not match then
      return false, "wrong_class:" .. tostring(pClass)
    end
  end

  if type(elig.races) == "table" and #elig.races > 0 then
    local cr = ctx.getPlayerClassAndRace()
    local pRace = cr and cr.raceToken
    if not pRace then
      return "unknown", "player_race_unknown"
    end
    local match = false
    for _, r in ipairs(elig.races) do
      if r == pRace then
        match = true
        break
      end
    end
    if not match then
      return false, "wrong_race:" .. tostring(pRace)
    end
  end

  if type(elig.exclusiveTo) == "table" and #elig.exclusiveTo > 0 then
    local exRes, exReason = RoutePlanner.EvaluatePredicate(
      { op = "exclusive_none_completed", questIDs = elig.exclusiveTo },
      progress,
      ctx,
      route,
      memo
    )
    if exRes ~= true then
      return exRes, exReason
    end
  end

  -- Optional dungeon/group branch filter: if includeGroupBranch is explicitly false and the player
  -- is not already on the quest, hide optional group actions from solo progression.
  local qref = getQuestRef(action)
  if action.isGroupBranch == true and progress and progress.includeGroupBranch == false then
    if qref then
      local onQ = ctx.isOnQuest(qref)
      if not (type(onQ) == "table" and onQ.status == "ok" and onQ.value == true) then
        return false, "optional_group_branch_disabled"
      end
    else
      return false, "optional_group_branch_disabled"
    end
  end

  -- Optional [42+] Elite bounty filter (default off for solo safety unless `/fh rg elites on`,
  -- EXCEPT manually pinned map targets and ready-to-turn-in Elite bounties are always eligible
  -- in HUD evaluation, while WorldMapPins always renders accepted Elite objectives on the map!).
  if action.isEliteBounty == true and not (progress and progress.includeEliteBounties == true) then
    local isManuallyPinned = (progress and progress.pinnedActionID == action.actionID)
    if not isManuallyPinned then
      if action.kind == "turnin" then
        local reqReady = RoutePlanner.EvaluatePredicate(action.requires, progress, ctx, route, memo)
        if reqReady ~= true then
          return false, "optional_elite_bounty_disabled"
        end
      else
        return false, "optional_elite_bounty_disabled"
      end
    end
  end

  return true
end

-- Evaluates live completion truth for an action.
-- Proximity/arrival NEVER completes accept/objective/turnin quest actions!
function RoutePlanner.EvaluateCompletion(action, progress, ctx, route, anyQuestStarted, memo)
  if action.retireWhenAnyQuestStarted == true and anyQuestStarted == true then
    return true
  end

  local cp = type(action.completionPredicate) == "table" and action.completionPredicate or {}
  local cType = cp.type
  local qref = getQuestRef(cp) or getQuestRef(action)

  if cType == "quest_completed" then
    return RoutePlanner.EvaluatePredicate({ op = "quest_completed", questID = cp.questID or action.questID, questKey = cp.questKey or action.questKey }, progress, ctx, route, memo)
  elseif cType == "quest_active_or_completed" then
    return RoutePlanner.EvaluatePredicate({ op = "quest_active_or_completed", questID = cp.questID or action.questID, questKey = cp.questKey or action.questKey }, progress, ctx, route, memo)
  elseif cType == "quest_objectives_complete_or_turned_in" then
    local rComp = RoutePlanner.IsQuestCompletedOrInferred(qref, route, ctx, nil, memo)
    if type(rComp) == "table" and rComp.status == "ok" and rComp.value == true then
      return true
    end
    -- If player abandoned the quest, objectives are NOT complete!
    local rAct = ctx.isOnQuest(qref)
    if type(rAct) == "table" and rAct.status == "ok" and rAct.value == false then
      return false
    end
    return RoutePlanner.EvaluatePredicate({ op = "quest_objectives_complete", questID = cp.questID or action.questID, questKey = cp.questKey or action.questKey }, progress, ctx, route, memo)
  elseif cType == "manual_or_arrival" then
    if action.kind ~= "travel" and action.kind ~= "manual" then
      return false
    end
    local ev = progress and progress.observedCompletionEvidence and progress.observedCompletionEvidence[action.actionID]
    return ev ~= nil
  elseif cType == "quest_objectives_complete_or_arrival" then
    if qref then
      local objDone = RoutePlanner.EvaluatePredicate({ op = "quest_objectives_complete", questID = cp.questID or action.questID, questKey = cp.questKey or action.questKey }, progress, ctx, route, memo)
      if objDone == true then
        return true
      end
    end
    if action.kind == "travel" then
      local ev = progress and progress.observedCompletionEvidence and progress.observedCompletionEvidence[action.actionID]
      if ev ~= nil then
        return true
      end
    end
    return false
  end

  return false
end

function RoutePlanner.EvaluateAction(action, route, progress, ctx, anyQuestStarted, memo)
  ctx = ctx or RoutePlanner.BuildDefaultContext()

  -- 1. Provenance & map conversion gate (Astra P0-A, P0-B, P0-D; v0.7.1 P1 #5 verified/estimated vs quarantined)
  if type(action) ~= "table" or not RoutePlanner.IsUsableReviewStatus(action.reviewStatus) then
    return {
      actionID = action and action.actionID or "unknown",
      state = "blocked_unverified",
      reason = "unverified_review_status",
    }
  end

  local destValid, destReason = RoutePlanner.ValidateActionDestination(action, route)
  if not destValid then
    return {
      actionID = action.actionID,
      state = "blocked_unverified",
      reason = destReason,
    }
  end

  -- 2. Completion check against live client truth + artifact_verified chain inference
  local compRes = RoutePlanner.EvaluateCompletion(action, progress, ctx, route, anyQuestStarted, memo)
  if compRes == true then
    return {
      actionID = action.actionID,
      state = "completed",
      reason = "completed",
    }
  end

  -- 3. Explicit user skip (`Next` = skip action, NOT complete quest!)
  if progress and progress.explicitlySkippedActions and progress.explicitlySkippedActions[action.actionID] then
    return {
      actionID = action.actionID,
      state = "skipped",
      reason = "explicitly_skipped",
    }
  end

  -- 4. Character eligibility
  local eligRes, eligReason = RoutePlanner.EvaluateEligibility(action, progress, ctx, route, memo)
  if eligRes == false then
    return {
      actionID = action.actionID,
      state = "ineligible",
      reason = eligReason,
    }
  elseif eligRes ~= true then
    return {
      actionID = action.actionID,
      state = "blocked_unverified",
      reason = eligReason or "eligibility_unknown",
    }
  end

  -- 5. Prerequisite predicate tree (AND / OR / NOT / breadcrumbs / exclusives)
  local reqRes, reqReason = RoutePlanner.EvaluatePredicate(action.requires, progress, ctx, route, memo)
  if reqRes == false then
    return {
      actionID = action.actionID,
      state = "blocked_prerequisite",
      reason = reqReason or "prerequisite_unmet",
    }
  elseif reqRes ~= true then
    return {
      actionID = action.actionID,
      state = "blocked_unverified",
      reason = reqReason or "prerequisite_unknown",
    }
  end

  -- 6. Quest-state certainty & pre-install title-history gate on pickup actions (Astra v0.7.1 P1 #1 & P1 #3)
  local readyReason = "ready"
  if action.kind == "accept" then
    local qref = getQuestRef(action)
    if qref ~= nil then
      local rAct = ctx.isOnQuest(qref)
      if type(rAct) ~= "table" or rAct.status ~= "ok" then
        return {
          actionID = action.actionID,
          state = "blocked_unverified",
          reason = (type(rAct) == "table" and rAct.reason) or "quest_active_uncertain",
        }
      end
      local rComp = RoutePlanner.IsQuestCompletedOrInferred(qref, route, ctx, nil, memo)
      if type(rComp) ~= "table" or rComp.status ~= "ok" then
        local cReason = type(rComp) == "table" and rComp.reason or nil
        if cReason == "title_history_unresolved" then
          local normT = (ns.Compat and ns.Compat.NormalizeQuestTitle and ns.Compat.NormalizeQuestTitle(qref)) or nil
          local confirmed = (type(rComp) == "table" and rComp.userConfirmedIncomplete == true)
            or (
              ns.State
              and type(ns.State.IsUnresolvedQuestConfirmedIncomplete) == "function"
              and ns.State.IsUnresolvedQuestConfirmedIncomplete(normT, type(qref) == "string" and qref or nil, progress)
            )
          if not confirmed then
            return {
              actionID = action.actionID,
              state = "blocked_unresolved_history",
              reason = "title_history_unresolved",
            }
          end
          readyReason = "user_confirmed_incomplete"
        else
          return {
            actionID = action.actionID,
            state = "blocked_unverified",
            reason = cReason or "quest_completion_uncertain",
          }
        end
      end
    end

    -- 7. Quest-log-full check on pickup actions
    local fullRes = ctx.isQuestLogFull()
    if type(fullRes) == "table" and fullRes.status == "ok" and fullRes.value == true then
      return {
        actionID = action.actionID,
        state = "blocked_quest_log_full",
        reason = "quest_log_full",
      }
    end
  end

  return {
    actionID = action.actionID,
    state = "available",
    reason = readyReason,
  }
end

-- Pure same-map distance helper in yards; returns nil across maps or when coordinates are invalid.
-- Never returns fabricated sentinel distances (such as 500000) for route scoring (Astra v0.8.7 P0).
local function computeSameMapYards(uiMapID, ax01, ay01, bx01, by01)
  local mID = tonumber(uiMapID)
  local ax = tonumber(ax01)
  local ay = tonumber(ay01)
  local bx = tonumber(bx01)
  local by = tonumber(by01)
  if not mID or not ax or not ay or not bx or not by then
    return nil
  end
  if ns.Compat and ns.Compat.GetWorldDistanceYards then
    local distRes = ns.Compat.GetWorldDistanceYards(mID, ax, ay, bx, by)
    if type(distRes) == "table" and distRes.status == "ok" and type(distRes.yards) == "number" then
      return distRes.yards
    end
  end
  local widthYards = (mID == 1444) and 6950.0 or 3600.0
  local heightYards = (mID == 1444) and 4633.0 or 2400.0
  local dx = (ax - bx) * widthYards
  local dy = (ay - by) * heightYards
  return math.sqrt(dx * dx + dy * dy)
end

local function computeDestDistanceYards(destA, destB)
  if type(destA) ~= "table" or type(destB) ~= "table" then
    return nil
  end
  local mapA = tonumber(destA.uiMapID)
  local mapB = tonumber(destB.uiMapID)
  if not mapA or not mapB or mapA ~= mapB then
    return nil
  end
  return computeSameMapYards(mapA, destA.x01, destA.y01, destB.x01, destB.y01)
end

local function computePlayerToDestYards(playerPos, dest)
  if type(playerPos) ~= "table" or playerPos.status ~= "ok" or type(dest) ~= "table" then
    return nil
  end
  local pMap = tonumber(playerPos.uiMapID)
  local dMap = tonumber(dest.uiMapID)
  if not pMap or not dMap or pMap ~= dMap then
    return nil
  end
  return computeSameMapYards(pMap, playerPos.x01, playerPos.y01, dest.x01, dest.y01)
end

-- Resolves currently unfinished sub-objective locations for an action.
-- When a specific objective line finishes in the live Quest Log (e.g. 8/8 Mudfin Murloc Head),
-- its corresponding subLocation is automatically retired so both World Map pins and the live
-- Directional Arrow focus strictly on the remaining unfinished locations.
function RoutePlanner.ResolveActiveSubLocations(action, ctx)
  if type(action) ~= "table" then
    return {}
  end
  ctx = ctx or RoutePlanner.BuildDefaultContext()
  local subLocs = action.subLocations
  if type(subLocs) ~= "table" or #subLocs == 0 then
    if type(action.destination) == "table" then
      return {
        {
          subID = action.actionID,
          label = action.title,
          targetName = action.npcName,
          destination = action.destination,
          isPrimary = true,
        },
      }
    end
    return {}
  end

  local qref = getQuestRef(action)
  local objRows = nil
  if qref and ctx and type(ctx.getQuestObjectives) == "function" then
    local objRes = ctx.getQuestObjectives(qref)
    if type(objRes) == "table" and objRes.status == "ok" and type(objRes.objectives) == "table" and #objRes.objectives > 0 then
      objRows = objRes.objectives
    end
  end

  local active = {}
  for _, sl in ipairs(subLocs) do
    if type(sl) == "table" and type(sl.destination) == "table" then
      local keep = true
      local progressLines = {}
      if objRows then
        local matchedCount = 0
        local unfinishedCount = 0
        if type(sl.objectiveMatches) == "table" and #sl.objectiveMatches > 0 then
          for _, obj in ipairs(objRows) do
            local txt = type(obj.text) == "string" and obj.text or ""
            local lowTxt = string.lower(txt)
            local hit = false
            for _, needle in ipairs(sl.objectiveMatches) do
              if type(needle) == "string" and needle ~= "" and string.find(lowTxt, string.lower(needle), 1, true) then
                hit = true
                break
              end
            end
            if hit then
              matchedCount = matchedCount + 1
              if obj.finished ~= true then
                unfinishedCount = unfinishedCount + 1
                if txt ~= "" then
                  table.insert(progressLines, txt)
                end
              end
            end
          end
        end
        if matchedCount == 0 and type(sl.objectiveIndexes) == "table" and #sl.objectiveIndexes > 0 then
          local idxSet = {}
          for _, oi in ipairs(sl.objectiveIndexes) do
            local n = tonumber(oi)
            if n and n >= 1 then
              idxSet[n] = true
            end
          end
          for rowPos, obj in ipairs(objRows) do
            local effIdx = tonumber(obj.index) or rowPos
            if idxSet[effIdx] then
              matchedCount = matchedCount + 1
              if obj.finished ~= true then
                unfinishedCount = unfinishedCount + 1
                local txt = type(obj.text) == "string" and obj.text or ""
                if txt ~= "" then
                  table.insert(progressLines, txt)
                end
              end
            end
          end
        end
        if matchedCount > 0 and unfinishedCount == 0 then
          keep = false
        end
      end

      if keep then
        table.insert(active, {
          subID = sl.subID,
          label = sl.label or action.title,
          targetName = sl.targetName or action.npcName,
          targetNpcID = sl.targetNpcID,
          objectiveIndexes = sl.objectiveIndexes,
          destination = sl.destination,
          progressText = (#progressLines > 0) and table.concat(progressLines, "; ") or nil,
        })
      end
    end
  end

  if #active == 0 and type(action.destination) == "table" then
    return {
      {
        subID = action.actionID,
        label = action.title,
        targetName = action.npcName,
        destination = action.destination,
        isPrimary = true,
      },
    }
  end
  return active
end

-- Selects the active destination & target caption for HUD + Directional Arrow,
-- honoring user-clicked `pinnedSubLocationID`, sustained `currentSubLocationID` hysteresis (Astra P2 #3),
-- or the closest unfinished `subLocation`.
function RoutePlanner.ResolveActiveActionTarget(action, progress, ctx, playerPos, route, opts)
  if type(action) ~= "table" then
    return nil, nil, nil, nil
  end
  if type(action.subLocations) ~= "table" or #action.subLocations == 0 then
    if (action.kind == "turnin" or action.kind == "objective")
      and ns.Compat
      and type(ns.Compat.ResolveLiveQuestTargetOverride) == "function"
    then
      local liveOverride = ns.Compat.ResolveLiveQuestTargetOverride(action, route, progress, ctx, opts)
      if type(liveOverride) == "table" and type(liveOverride.destination) == "table" then
        return liveOverride.destination, liveOverride.targetName or action.npcName, nil, liveOverride
      end
    end
    return action.destination, action.npcName, nil, nil
  end
  ctx = ctx or RoutePlanner.BuildDefaultContext()
  playerPos = playerPos or (ns.Compat and ns.Compat.GetPlayerPosition01 and ns.Compat.GetPlayerPosition01()) or nil
  local activeSubs = RoutePlanner.ResolveActiveSubLocations(action, ctx)
  if #activeSubs == 0 then
    return action.destination, action.npcName, nil
  end

  if progress and progress.pinnedActionID == action.actionID and type(progress.pinnedSubLocationID) == "string" then
    for _, sl in ipairs(activeSubs) do
      if sl.subID == progress.pinnedSubLocationID then
        return sl.destination, sl.targetName or action.npcName, sl
      end
    end
  end

  local bestSub = activeSubs[1]
  local bestYards = nil
  if type(playerPos) == "table" and playerPos.status == "ok" and #activeSubs > 1 then
    bestYards = computePlayerToDestYards(playerPos, bestSub.destination)
    for i = 2, #activeSubs do
      local cand = activeSubs[i]
      local y = computePlayerToDestYards(playerPos, cand.destination)
      if y ~= nil and (bestYards == nil or y < bestYards - 0.5) then
        bestSub = cand
        bestYards = y
      end
    end

    if bestYards ~= nil and progress and progress.currentActionID == action.actionID and type(progress.currentSubLocationID) == "string" then
      for _, sl in ipairs(activeSubs) do
        if sl.subID == progress.currentSubLocationID then
          if sl ~= bestSub then
            local curYards = computePlayerToDestYards(playerPos, sl.destination)
            if curYards ~= nil and not (bestYards < curYards - SUBLOCATION_SWITCH_HYSTERESIS_YARDS) then
              bestSub = sl
            end
          end
          break
        end
      end
    end
  end
  return bestSub.destination, bestSub.targetName or action.npcName, bestSub
end

-- ============================================================================
-- Travel-Aware Service-Group Planner, Counterfactual Batch Engine & Commitment
-- (GPT Astra v0.8.7 Specification)
-- ============================================================================

local W_NPC_GROUP = 15.0
local W_OBJECTIVE_GROUP = 20.0
local W_INSERT_STOP = 12.0
local INSERT_MAX_DETOUR_YARDS = 120.0
local MAX_BATCH_BENEFIT_YARDS = 180.0
local MAX_UNLOCK_BENEFIT_YARDS = 240.0
local MAX_CAPACITY_BENEFIT_YARDS = 260.0
local LEAF_DEFERRAL_MAX_YARDS = 300.0
local SIBLING_DEFERRAL_MAX_YARDS = 220.0
local USEFUL_BREADCRUMB_MAX_YARDS = 550.0

local planningMetaCache = setmetatable({}, { __mode = "k" })

local SELECTION_REASON_LABELS = {
  pinned = "Pinned by you",
  onboarding = "Zone entry setup",
  on_route = "On your route",
  frees_slot = "Frees a quest slot",
  unlocks_nearby = "Unlocks nearby objectives",
  hub_batch = "Planned to reduce backtracking",
  nearby_step = "Travel-aware route",
  position_unavailable = "Position unavailable",
  travel_to_zone = "Travel to Riverglades to begin",
  zone_exit = "Cross-zone delivery",
  idle = "Route caught up",
}

local function clamp01(x)
  if x <= 0.0 then
    return 0.0
  elseif x >= 1.0 then
    return 1.0
  end
  return x
end

local function smoothstep01(t)
  local u = clamp01(t)
  return u * u * (3.0 - 2.0 * u)
end

local function canonicalQuestIdentity(route, questRef)
  if questRef == nil then
    return nil, nil
  end
  local qMeta = lookupQuestMeta(route, questRef)
  if type(qMeta) == "table" then
    local qid = tonumber(qMeta.questID) or tonumber(qMeta.knownQuestID)
    if qid and qid > 0 then
      return "id:" .. tostring(qid), qMeta
    end
    if type(qMeta.questKey) == "string" and qMeta.questKey ~= "" then
      return qMeta.questKey, qMeta
    end
  end
  local n = tonumber(questRef)
  if n and n > 0 then
    return "id:" .. tostring(n), qMeta
  end
  return tostring(questRef), qMeta
end

local function normalizeQuestLogCapacity(ctx)
  if ctx and type(ctx.getQuestLogCapacity) == "function" then
    local cap = ctx.getQuestLogCapacity()
    if type(cap) == "table" and cap.status == "ok" then
      local c = tonumber(cap.count)
      local m = tonumber(cap.max)
      if c and m and m > 0 then
        local effMax = math.max(c, m)
        return {
          status = "ok",
          isFull = (c >= effMax),
          count = c,
          max = effMax,
          freeSlots = math.max(0, effMax - c),
        }
      end
      if type(cap.isFull) == "boolean" then
        return {
          status = "ok",
          isFull = cap.isFull,
          count = nil,
          max = nil,
          freeSlots = cap.isFull and 0 or nil,
        }
      end
    end
  end
  if ctx and type(ctx.isQuestLogFull) == "function" then
    local raw = ctx.isQuestLogFull()
    if type(raw) == "table" and raw.status == "ok" then
      local c = tonumber(raw.count)
      local m = tonumber(raw.max)
      if c and m and m > 0 then
        local effMax = math.max(c, m)
        return {
          status = "ok",
          isFull = (c >= effMax),
          count = c,
          max = effMax,
          freeSlots = math.max(0, effMax - c),
        }
      end
      if type(raw.value) == "boolean" then
        return {
          status = "ok",
          isFull = raw.value,
          count = nil,
          max = nil,
          freeSlots = raw.value and 0 or nil,
        }
      end
    end
  end
  return { status = "unknown", isFull = nil, count = nil, max = nil, freeSlots = nil }
end

local function deriveFallbackServiceGroup(act, hubSeeds)
  if type(act.serviceGroupID) == "string" and act.serviceGroupID ~= "" then
    return act.serviceGroupID, (string.sub(act.serviceGroupID, 1, 4) == "obj_") and "objective" or "hub", act.serviceGroupLabel
  end
  local dest = act.destination
  local mapID = dest and tonumber(dest.uiMapID) or 0
  local x = dest and tonumber(dest.x01) or 0
  local y = dest and tonumber(dest.y01) or 0

  local isHubKind = (act.kind == "accept" or act.kind == "turnin" or act.kind == "travel")
  if act.kind == "objective"
    and mapID == 2548
    and (type(act.subLocations) ~= "table" or #act.subLocations == 0)
    and act.isSupplyObjective ~= true
  then
    if x >= 0.651 and x <= 0.675 and y >= 0.785 and y <= 0.840 then
      return "sg_farholde_citadel", "hub", "Farholde Citadel"
    elseif x >= 0.685 and x <= 0.700 and y >= 0.495 and y <= 0.510 then
      return "sg_sleebo_fizzlespout", "hub", "Sleebo Fizzlespout"
    end
  end

  if not isHubKind then
    return "obj_" .. tostring(act.actionID), "objective", tostring(act.npcName or act.title or act.actionID)
  end

  if mapID == 2548 then
    if x >= 0.595 and x <= 0.675 and y >= 0.780 and y <= 0.865 then
      if x < 0.625 then
        return "sg_farholde_chapel", "hub", "Farholde Chapel"
      elseif x < 0.651 then
        return "sg_farholde_square", "hub", "Farholde Square"
      else
        return "sg_farholde_citadel", "hub", "Farholde Citadel"
      end
    elseif x >= 0.745 and x <= 0.805 and y >= 0.515 and y <= 0.555 then
      if x < 0.780 then
        return "sg_powderfuse_west", "hub", "Powderfuse West"
      else
        return "sg_powderfuse_docks", "hub", "Powderfuse Docks"
      end
    elseif x >= 0.685 and x <= 0.702 and y >= 0.495 and y <= 0.512 then
      return "sg_sleebo_fizzlespout", "hub", "Sleebo Fizzlespout"
    end
  elseif mapID == 1444 then
    return "sg_mardrack_greenwell", "hub", "Feathermoon Stronghold"
  end

  if dest then
    for _, seed in ipairs(hubSeeds) do
      if seed.uiMapID == mapID then
        local d = computeSameMapYards(mapID, x, y, seed.x01, seed.y01)
        if d and d <= 40.0 then
          return seed.groupID, "hub", seed.label
        end
      end
    end
    local gid = "sg_npc_" .. tostring(act.npcID or act.actionID)
    for _, seed in ipairs(hubSeeds) do
      if seed.groupID == gid then
        gid = gid .. "_" .. tostring(act.actionID)
        break
      end
    end
    local lbl = tostring(act.npcName or act.title or act.actionID)
    table.insert(hubSeeds, { groupID = gid, label = lbl, uiMapID = mapID, x01 = x, y01 = y })
    return gid, "hub", lbl
  end

  return "obj_" .. tostring(act.actionID), "objective", tostring(act.title or act.actionID)
end

local function collectPredicateQuestDeps(node, route, negDepth, out)
  if type(node) ~= "table" or type(node.op) ~= "string" then
    return
  end
  local op = node.op
  if op == "not" then
    collectPredicateQuestDeps(node.child, route, negDepth + 1, out)
  elseif op == "all" or op == "any" then
    if type(node.children) == "table" then
      for _, ch in ipairs(node.children) do
        collectPredicateQuestDeps(ch, route, negDepth, out)
      end
    end
  elseif op == "exclusive_none_completed" then
    if type(node.questIDs) == "table" then
      for _, exQ in ipairs(node.questIDs) do
        local cKey = canonicalQuestIdentity(route, exQ)
        if cKey then
          out[cKey] = "negative"
        end
      end
    end
  elseif
    op == "quest_completed"
    or op == "quest_active"
    or op == "quest_active_or_completed"
    or op == "quest_objectives_complete"
    or op == "item_owned_or_quest_active"
  then
    local qref = getQuestRef(node)
    local cKey = canonicalQuestIdentity(route, qref)
    if cKey then
      local pol = (negDepth % 2 == 1) and "negative" or "positive"
      if out[cKey] == "negative" then
        pol = "negative"
      end
      out[cKey] = pol
    end
  end
end

function RoutePlanner.EnsurePlanningMetadata(route)
  if type(route) ~= "table" or type(route.actions) ~= "table" then
    return nil
  end
  local cached = planningMetaCache[route]
  if cached and cached.actionCount == #route.actions then
    return cached
  end

  local staticGroupIDByActionID = {}
  local groupDefsByID = {}
  local questActionsByKey = {}
  local dependentsByQuestKey = {}
  local actionByID = {}
  local campClusterByActionID = {}
  local campSeeds = {}
  local hubSeeds = {}

  -- Pre-build predecessor closure over route.questSuccessors so transitive completion inference
  -- (`94879/94881 -> 94907 -> 94984`) is also reflected in reverse dependency lookups.
  local reversePredecessorsByKey = {}
  if type(route.questSuccessors) == "table" then
    for predRaw, succList in pairs(route.questSuccessors) do
      local predKey = canonicalQuestIdentity(route, tonumber(predRaw) or predRaw)
      if predKey and type(succList) == "table" then
        for _, succRef in ipairs(succList) do
          local succKey = canonicalQuestIdentity(route, succRef)
          if succKey then
            reversePredecessorsByKey[succKey] = reversePredecessorsByKey[succKey] or {}
            reversePredecessorsByKey[succKey][predKey] = true
          end
        end
      end
    end
  end

  local compiledGroups = type(route.serviceGroupsByID) == "table" and route.serviceGroupsByID or nil

  for idx, act in ipairs(route.actions) do
    if type(act) == "table" and type(act.actionID) == "string" then
      actionByID[act.actionID] = act
      local sgID, sgKind, sgLabel = deriveFallbackServiceGroup(act, hubSeeds)
      if compiledGroups and type(compiledGroups[sgID]) == "table" then
        sgKind = compiledGroups[sgID].kind or sgKind
        sgLabel = compiledGroups[sgID].label or sgLabel
      end
      staticGroupIDByActionID[act.actionID] = sgID

      local gDef = groupDefsByID[sgID]
      if not gDef then
        gDef = {
          serviceGroupID = sgID,
          kind = sgKind,
          label = sgLabel or sgID,
          uiMapID = act.destination and tonumber(act.destination.uiMapID) or nil,
          minCircuitRank = tonumber(act.circuitRank) or idx,
          sumX = 0.0,
          sumY = 0.0,
          coordCount = 0,
        }
        groupDefsByID[sgID] = gDef
      else
        local rnk = tonumber(act.circuitRank) or idx
        if rnk < gDef.minCircuitRank then
          gDef.minCircuitRank = rnk
        end
      end
      if act.destination and tonumber(act.destination.x01) and tonumber(act.destination.y01) then
        gDef.sumX = gDef.sumX + tonumber(act.destination.x01)
        gDef.sumY = gDef.sumY + tonumber(act.destination.y01)
        gDef.coordCount = gDef.coordCount + 1
      end

      if act.kind == "objective" and act.isSupplyObjective ~= true and type(act.destination) == "table" then
        local mID = tonumber(act.destination.uiMapID)
        local ox = tonumber(act.destination.x01)
        local oy = tonumber(act.destination.y01)
        if mID and ox and oy then
          local assignedCamp = nil
          for _, cSeed in ipairs(campSeeds) do
            if cSeed.uiMapID == mID then
              local cd = computeSameMapYards(mID, ox, oy, cSeed.x01, cSeed.y01)
              if cd and cd <= 85.0 then
                assignedCamp = cSeed.campID
                break
              end
            end
          end
          if not assignedCamp then
            assignedCamp = "camp_" .. act.actionID
            table.insert(campSeeds, { campID = assignedCamp, uiMapID = mID, x01 = ox, y01 = oy })
          end
          campClusterByActionID[act.actionID] = assignedCamp
        end
      end

      local qref = getQuestRef(act)
      local cKey, qMeta = canonicalQuestIdentity(route, qref)
      if cKey then
        local qInfo = questActionsByKey[cKey]
        if not qInfo then
          qInfo = {
            canonKey = cKey,
            questRef = qref,
            zeroObjectives = (qMeta and qMeta.zeroObjectives == true) or false,
            isSupplyQuest = (qMeta and qMeta.supplyItemID ~= nil) or false,
            acceptActions = {},
            objectiveActions = {},
            turninActions = {},
            turninGroupIDs = {},
          }
          questActionsByKey[cKey] = qInfo
        end
        if act.isSupplyObjective == true then
          qInfo.isSupplyQuest = true
        end
        if act.kind == "accept" then
          table.insert(qInfo.acceptActions, act)
        elseif act.kind == "objective" and act.isSupplyObjective ~= true then
          table.insert(qInfo.objectiveActions, act)
        elseif act.kind == "turnin" then
          table.insert(qInfo.turninActions, act)
          qInfo.turninGroupIDs[sgID] = true
        end
      end

      local depSet = {}
      collectPredicateQuestDeps(act.requires, route, 0, depSet)
      if type(act.eligibility) == "table" and type(act.eligibility.exclusiveTo) == "table" then
        for _, exQ in ipairs(act.eligibility.exclusiveTo) do
          local exKey = canonicalQuestIdentity(route, exQ)
          if exKey then
            depSet[exKey] = "negative"
          end
        end
      end

      -- Expand transitive successor dependencies
      local expanded = {}
      local queue = {}
      for dKey, pol in pairs(depSet) do
        expanded[dKey] = pol
        table.insert(queue, dKey)
      end
      local qi = 1
      while qi <= #queue do
        local curKey = queue[qi]
        qi = qi + 1
        local preds = reversePredecessorsByKey[curKey]
        if preds then
          for pKey in pairs(preds) do
            if not expanded[pKey] then
              expanded[pKey] = expanded[curKey]
              table.insert(queue, pKey)
            end
          end
        end
      end

      for dKey, pol in pairs(expanded) do
        dependentsByQuestKey[dKey] = dependentsByQuestKey[dKey] or {}
        table.insert(dependentsByQuestKey[dKey], { action = act, polarity = pol })
      end
    end
  end

  for _, gDef in pairs(groupDefsByID) do
    if gDef.coordCount > 0 then
      gDef.centroidX01 = gDef.sumX / gDef.coordCount
      gDef.centroidY01 = gDef.sumY / gDef.coordCount
    end
  end

  local meta = {
    actionCount = #route.actions,
    actionByID = actionByID,
    staticGroupIDByActionID = staticGroupIDByActionID,
    groupDefsByID = groupDefsByID,
    questActionsByKey = questActionsByKey,
    dependentsByQuestKey = dependentsByQuestKey,
    campClusterByActionID = campClusterByActionID,
  }
  planningMetaCache[route] = meta
  return meta
end

local function isOptionalDeferredCandidate(act, elitesEnabled)
  if act.isSupplyObjective == true then
    return true, "supply"
  end
  if act.isAtlasSideQuest == true and act.kind == "accept" then
    return true, "optional"
  end
  if act.isGroupBranch == true and act.kind ~= "turnin" then
    return true, "optional"
  end
  if act.isEliteBounty == true and not elitesEnabled and act.kind ~= "turnin" then
    return true, "optional"
  end
  return false, "core"
end

local function isUsefulPickupEntry(entry, meta)
  local act = entry.action
  if act.kind ~= "accept" or act.isAtlasSideQuest == true or act.isGroupBranch == true then
    return false
  end
  local qref = getQuestRef(act)
  local cKey = canonicalQuestIdentity(meta.routeRef, qref)
  local qInfo = cKey and meta.questActionsByKey[cKey] or nil
  if not qInfo then
    return true
  end
  if qInfo.isSupplyQuest and #qInfo.objectiveActions == 0 then
    return false
  end
  if qInfo.zeroObjectives == true and #qInfo.objectiveActions == 0 then
    -- Short local/adjacent-hub deliveries count as useful; cross-zone (>550 yd / cross-map) deliveries do not
    if #qInfo.turninActions == 0 then
      return false
    end
    for _, tAct in ipairs(qInfo.turninActions) do
      local d = computeDestDistanceYards(entry.dest, tAct.destination)
      if d ~= nil and d <= USEFUL_BREADCRUMB_MAX_YARDS then
        return true
      end
    end
    return false
  end
  return #qInfo.objectiveActions > 0
end

local function selectBestActionWithinGroup(group, currentID, anyQuestStarted)
  local items = group.entries
  if #items == 0 then
    return nil
  end
  if not anyQuestStarted then
    for _, e in ipairs(items) do
      if e.action.retireWhenAnyQuestStarted == true then
        return e.action
      end
    end
  end

  local bestEntry = nil
  local bestSubRank = math.huge
  local bestDist = math.huge
  local bestCircuitRank = math.huge
  local bestOrder = math.huge

  for _, e in ipairs(items) do
    local act = e.action
    local subRank = 4
    if act.kind == "turnin" then
      subRank = 1
    elseif act.kind == "accept" then
      if act.isGroupBranch == true or act.isAtlasSideQuest == true then
        subRank = 2.5
      else
        subRank = 2
      end
    elseif act.kind == "objective" or act.kind == "travel" then
      subRank = 3
    end

    local effDist = e.playerYards or 0.0
    if currentID ~= nil and act.actionID == currentID then
      effDist = effDist - 6.0
    end
    local cRank = tonumber(act.circuitRank) or tonumber(e.orderIndex) or 999999
    local ord = tonumber(e.orderIndex) or 999999

    if (subRank < bestSubRank)
      or (subRank == bestSubRank and effDist < bestDist - 5.0)
      or (subRank == bestSubRank and math.abs(effDist - bestDist) <= 5.0 and cRank < bestCircuitRank)
      or (subRank == bestSubRank and math.abs(effDist - bestDist) <= 5.0 and cRank == bestCircuitRank and ord < bestOrder)
    then
      bestEntry = e
      bestSubRank = subRank
      bestDist = effDist
      bestCircuitRank = cRank
      bestOrder = ord
    end
  end

  return bestEntry and bestEntry.action or items[1].action
end

local function deterministicFallbackAction(availableEvaluations, progress, decisionSig)
  if #availableEvaluations == 0 then
    return nil
  end
  -- Retain valid currentActionID during position loss ONLY when eligibility/decision signature is unchanged
  local curID = progress and progress.currentActionID or nil
  if type(curID) == "string" and curID ~= ""
    and progress
    and type(progress.committedDecisionSig) == "string"
    and progress.committedDecisionSig == decisionSig
  then
    for _, ev in ipairs(availableEvaluations) do
      if ev.action and ev.action.actionID == curID then
        return ev.action
      end
    end
  end

  local elitesEnabled = (progress and progress.includeEliteBounties == true)
  local bestAct = nil
  local bestBucket = math.huge
  local bestRank = math.huge
  local bestOrd = math.huge
  for _, ev in ipairs(availableEvaluations) do
    local act = ev.action
    if act then
      local bucket = 1
      if act.retireWhenAnyQuestStarted == true then
        bucket = 0
      elseif act.isSupplyObjective == true then
        bucket = 4
      elseif act.isZoneExit == true then
        bucket = 3.5
      else
        local isOpt = isOptionalDeferredCandidate(act, elitesEnabled)
        if isOpt then
          bucket = 3
        elseif act.isAtlasSideQuest == true then
          bucket = 2
        end
      end
      local rnk = tonumber(act.circuitRank) or tonumber(ev.orderIndex) or 999999
      local ord = tonumber(ev.orderIndex) or 999999
      if (bucket < bestBucket)
        or (bucket == bestBucket and rnk < bestRank)
        or (bucket == bestBucket and rnk == bestRank and ord < bestOrd)
      then
        bestAct = act
        bestBucket = bucket
        bestRank = rnk
        bestOrd = ord
      end
    end
  end
  return bestAct or availableEvaluations[1].action
end

local function evaluateCounterfactualHubBatch(group, route, progress, ctx, byActionID, meta, cap, playerPos, coreObjectiveEntries)
  if #group.readyTurninEntries == 0 then
    return 0, 0.0, 0
  end

  local simCompleted = {}
  local simInactive = {}
  local simFreedSlots = 0

  local overlayCtx = {
    getPlayerFaction = ctx.getPlayerFaction,
    getPlayerLevel = ctx.getPlayerLevel,
    getPlayerClassAndRace = ctx.getPlayerClassAndRace,
    getQuestObjectives = ctx.getQuestObjectives,
    getQuestEvidence = ctx.getQuestEvidence,
    getBagItemCount = ctx.getBagItemCount,
    isQuestCompleted = function(questRef)
      local cKey = canonicalQuestIdentity(route, questRef)
      if cKey and simCompleted[cKey] == true then
        return { status = "ok", value = true }
      end
      return ctx.isQuestCompleted(questRef)
    end,
    isOnQuest = function(questRef)
      local cKey = canonicalQuestIdentity(route, questRef)
      if cKey and simInactive[cKey] == true then
        return { status = "ok", value = false }
      end
      return ctx.isOnQuest(questRef)
    end,
    isQuestLogFull = function()
      if simFreedSlots > 0 then
        if cap.freeSlots == nil or (cap.freeSlots + simFreedSlots) > 0 then
          return { status = "ok", value = false }
        end
      end
      return ctx.isQuestLogFull()
    end,
    getQuestLogCapacity = function()
      if cap.status ~= "ok" then
        return { status = "unknown", isFull = nil, count = nil, max = nil, freeSlots = nil }
      end
      local newFree = (cap.freeSlots ~= nil) and (cap.freeSlots + simFreedSlots) or nil
      local newCount = (cap.count ~= nil) and math.max(0, cap.count - simFreedSlots) or nil
      local newFull = (newFree ~= nil) and (newFree <= 0) or ((simFreedSlots > 0) and false or cap.isFull)
      return {
        status = "ok",
        isFull = newFull,
        count = newCount,
        max = cap.max,
        freeSlots = newFree,
      }
    end,
  }

  local seenTurninQuest = {}
  local executedQuestKeys = {}

  for idx, entry in ipairs(group.readyTurninEntries) do
    local tAct = entry.action
    local qref = getQuestRef(tAct)
    local cKey = canonicalQuestIdentity(route, qref)
    if cKey and not seenTurninQuest[cKey] then
      local stillFeasible = true
      if idx > 1 then
        local stepEv = RoutePlanner.EvaluateAction(tAct, route, progress, overlayCtx, true, {})
        stillFeasible = (stepEv and stepEv.state == "available")
      end
      if stillFeasible then
        seenTurninQuest[cKey] = true
        -- Check whether this quest was genuinely active in the live log before marking inactive
        local origOn = ctx.isOnQuest(qref)
        if type(origOn) == "table" and origOn.status == "ok" and origOn.value == true then
          simFreedSlots = simFreedSlots + 1
        end
        simCompleted[cKey] = true
        simInactive[cKey] = true
        table.insert(executedQuestKeys, cKey)
      end
    end
  end

  if #executedQuestKeys == 0 then
    return 0, 0.0, 0
  end

  local candidateActions = {}
  local seenActionID = {}
  for _, cKey in ipairs(executedQuestKeys) do
    local depList = meta.dependentsByQuestKey[cKey]
    if depList then
      for _, dep in ipairs(depList) do
        local u = dep.action
        if u and not seenActionID[u.actionID] then
          seenActionID[u.actionID] = true
          table.insert(candidateActions, u)
        end
      end
    end
  end
  if simFreedSlots > 0 then
    for _, act in ipairs(route.actions) do
      if act and not seenActionID[act.actionID] then
        local origEv = byActionID[act.actionID]
        if origEv and origEv.state == "blocked_quest_log_full" then
          seenActionID[act.actionID] = true
          table.insert(candidateActions, act)
        end
      end
    end
  end

  local batchMemo = {}
  local newlyAvailable = {}
  local newlyDisabledUsefulCount = 0

  for _, u in ipairs(candidateActions) do
    local origEv = byActionID[u.actionID]
    local origState = origEv and origEv.state or "blocked"
    local simEv = RoutePlanner.EvaluateAction(u, route, progress, overlayCtx, true, batchMemo)
    local newState = simEv and simEv.state or "blocked"
    if origState ~= "available" and newState == "available" then
      table.insert(newlyAvailable, u)
    elseif origState == "available" and newState ~= "available" and newState ~= "completed" then
      if not seenTurninQuest[canonicalQuestIdentity(route, getQuestRef(u)) or ""] then
        newlyDisabledUsefulCount = newlyDisabledUsefulCount + 1
      end
    end
  end

  if #newlyAvailable == 0 then
    return #executedQuestKeys, 0.0, simFreedSlots
  end

  local pickupCredits = {}
  local directUnlockCredit = 0.0
  local dPH = group.distanceFromPlayer or 0.0

  for _, u in ipairs(newlyAvailable) do
    if u.isAtlasSideQuest ~= true and u.isGroupBranch ~= true and u.isSupplyObjective ~= true then
      if u.kind == "accept" then
        -- Only credit accepts that are reachable right at this hub (<= 90 yd) or en-route, AND have a verified field objective!
        local dHAccept = computeDestDistanceYards(group.repDest, u.destination)
        if dHAccept ~= nil and dHAccept <= 120.0 then
          local uKey = canonicalQuestIdentity(route, getQuestRef(u))
          local qInfo = uKey and meta.questActionsByKey[uKey] or nil
          if qInfo and not qInfo.zeroObjectives and #qInfo.objectiveActions > 0 then
            local bestPickupVal = 0.0
            for _, objAct in ipairs(qInfo.objectiveActions) do
              local dHObj = computeDestDistanceYards(group.repDest, objAct.destination)
              if dHObj ~= nil then
                local localCredit = 200.0 * (1.0 - smoothstep01((dHObj - 60.0) / 340.0))
                local doubleClearCredit = 0.0
                for _, actObjEntry in ipairs(coreObjectiveEntries) do
                  local dCamp = computeDestDistanceYards(actObjEntry.dest, objAct.destination)
                  if dCamp ~= nil and dCamp <= 380.0 then
                    local dPC = actObjEntry.playerYards or 0.0
                    local dHC = computeDestDistanceYards(group.repDest, actObjEntry.dest) or dHObj
                    local savedTrip = math.max(0.0, dPC + dHC - dPH)
                    local proximityWeight = 1.0 - smoothstep01((dCamp - 80.0) / 300.0)
                    local val = math.min(MAX_UNLOCK_BENEFIT_YARDS, savedTrip * proximityWeight)
                    if val > doubleClearCredit then
                      doubleClearCredit = val
                    end
                  end
                end
                local candidateVal = math.max(localCredit, doubleClearCredit)
                if candidateVal > bestPickupVal then
                  bestPickupVal = candidateVal
                end
              end
            end
            if bestPickupVal > 0.0 then
              table.insert(pickupCredits, bestPickupVal)
            end
          end
        end
      elseif u.kind == "objective" or u.kind == "turnin" then
        local dHU = computeDestDistanceYards(group.repDest, u.destination)
        if dHU ~= nil then
          local c = 160.0 * (1.0 - smoothstep01((dHU - 60.0) / 300.0))
          if c > directUnlockCredit then
            directUnlockCredit = c
          end
        end
      end
    end
  end

  table.sort(pickupCredits, function(a, b)
    return a > b
  end)

  local slotBudget = math.huge
  if cap.freeSlots ~= nil then
    slotBudget = math.max(0, cap.freeSlots + simFreedSlots)
  end

  local sumPickupUnlock = 0.0
  local taken = 0
  for _, val in ipairs(pickupCredits) do
    if taken >= slotBudget then
      break
    end
    sumPickupUnlock = sumPickupUnlock + val
    taken = taken + 1
  end

  local rawUnlock = sumPickupUnlock + directUnlockCredit - (40.0 * newlyDisabledUsefulCount)
  local finalUnlock = math.min(MAX_UNLOCK_BENEFIT_YARDS, math.max(0.0, rawUnlock))
  return #executedQuestKeys, finalUnlock, simFreedSlots
end

function RoutePlanner.PlanNextAction(availableEvaluations, evaluations, byActionID, route, progress, playerPos, anyQuestStarted, ctx)
  local emptyPlan = {
    zoneStatus = "idle",
    anchorGroupID = nil,
    anchorLabel = nil,
    insertedGroupID = nil,
    selectedGroupID = nil,
    selectionReason = "idle",
    selectionReasonLabel = SELECTION_REASON_LABELS.idle,
    hubReturnPlanned = false,
    deferredReadyCount = 0,
    readyCount = 0,
    slotDeficit = 0,
    decisionSig = "idle",
    retainCommitment = false,
    deferDecisionCommit = false,
    groupScores = {},
  }
  if type(availableEvaluations) ~= "table" or #availableEvaluations == 0 then
    return nil, emptyPlan
  end

  ctx = ctx or RoutePlanner.BuildDefaultContext()
  local meta = RoutePlanner.EnsurePlanningMetadata(route)
  if meta then
    meta.routeRef = route
  end
  local cap = normalizeQuestLogCapacity(ctx)
  local elitesEnabled = (progress and progress.includeEliteBounties == true)
  local primaryUiMapID = tonumber(route and route.primaryUiMapID) or 2548

  -- Count distinct ready turn-ins across all available actions
  local readyQuestSeen = {}
  local totalReadyTurnins = 0
  for _, ev in ipairs(availableEvaluations) do
    local act = ev.action
    if act and act.kind == "turnin" then
      local cKey = canonicalQuestIdentity(route, getQuestRef(act)) or act.actionID
      if not readyQuestSeen[cKey] then
        readyQuestSeen[cKey] = true
        totalReadyTurnins = totalReadyTurnins + 1
      end
    end
  end

  -- Resolve live destinations (pure read, never writing Compat.liveQuestTargetDrifts) & build spatial revision
  local resolvedEntries = {}
  local availIds = {}
  local spatialParts = {}

  for _, ev in ipairs(availableEvaluations) do
    local act = ev.action
    table.insert(availIds, act.actionID)
    local dest = act.destination
    local targetName = act.npcName
    local activeSub = nil
    local liveOverride = nil
    local activeSubCount = 1

    if type(act.subLocations) == "table" and #act.subLocations > 0 then
      local subs = RoutePlanner.ResolveActiveSubLocations(act, ctx)
      activeSubCount = #subs
      dest, targetName, activeSub = RoutePlanner.ResolveActiveActionTarget(
        act,
        progress,
        ctx,
        playerPos,
        route,
        { recordDrift = false }
      )
      table.insert(spatialParts, string.format("%s#sub%d", act.actionID, activeSubCount))
    elseif act.kind == "turnin" or act.kind == "objective" then
      dest, targetName, activeSub, liveOverride = RoutePlanner.ResolveActiveActionTarget(
        act,
        progress,
        ctx,
        playerPos,
        route,
        { recordDrift = false }
      )
      if liveOverride and type(dest) == "table" then
        table.insert(
          spatialParts,
          string.format(
            "%s@%.3f,%.3f:%s",
            act.actionID,
            tonumber(dest.x01) or 0,
            tonumber(dest.y01) or 0,
            tostring(dest.uiMapID or 0)
          )
        )
      end
    end

    local dMapID = dest and tonumber(dest.uiMapID) or nil
    local pYards = computePlayerToDestYards(playerPos, dest)

    -- Assign service group (invalidating static assignment if live self-healing moved the target)
    local sgID = (meta and meta.staticGroupIDByActionID[act.actionID]) or ("obj_" .. act.actionID)
    local sgKind = (meta and meta.groupDefsByID[sgID] and meta.groupDefsByID[sgID].kind) or "objective"
    local sgLabel = (meta and meta.groupDefsByID[sgID] and meta.groupDefsByID[sgID].label) or targetName or act.title

    if liveOverride and type(dest) == "table" and meta then
      local matchedHubID = nil
      for candID, gDef in pairs(meta.groupDefsByID) do
        if gDef.kind == "hub" and gDef.uiMapID == dMapID and gDef.centroidX01 and gDef.centroidY01 then
          local hd = computeSameMapYards(dMapID, dest.x01, dest.y01, gDef.centroidX01, gDef.centroidY01)
          if hd and hd <= 55.0 then
            matchedHubID = candID
            sgLabel = gDef.label
            break
          end
        end
      end
      sgID = matchedHubID or ("healed:" .. act.actionID)
      sgKind = (act.kind == "objective") and "objective" or "hub"
      if not matchedHubID then
        sgLabel = targetName or act.title or act.actionID
      end
    end

    table.insert(resolvedEntries, {
      ev = ev,
      action = act,
      orderIndex = ev.orderIndex,
      dest = dest,
      uiMapID = dMapID,
      targetName = targetName,
      activeSub = activeSub,
      activeSubCount = activeSubCount,
      liveOverride = liveOverride,
      playerYards = pYards,
      serviceGroupID = sgID,
      serviceGroupKind = sgKind,
      serviceGroupLabel = sgLabel,
    })
  end

  -- Count blocked_quest_log_full solo demand for capacity pressure
  local blockedFullDemand = 0
  local blockedFullSeen = {}
  if type(evaluations) == "table" then
    for _, ev in ipairs(evaluations) do
      if ev.state == "blocked_quest_log_full" and ev.action and ev.action.kind == "accept" then
        if ev.action.isAtlasSideQuest ~= true and ev.action.isGroupBranch ~= true then
          local cKey = canonicalQuestIdentity(route, getQuestRef(ev.action)) or ev.action.actionID
          if not blockedFullSeen[cKey] then
            blockedFullSeen[cKey] = true
            blockedFullDemand = blockedFullDemand + 1
          end
        end
      end
    end
  end

  local posOk = (type(playerPos) == "table" and playerPos.status == "ok" and tonumber(playerPos.uiMapID) ~= nil)
  local playerMapID = posOk and tonumber(playerPos.uiMapID) or nil
  local mapBucket = posOk and ("map:" .. tostring(playerMapID)) or "pos:unavailable"
  local pinDigest = tostring(progress and progress.pinnedActionID or "") .. ":" .. tostring(progress and progress.pinnedSubLocationID or "")
  local capStateStr = (cap.isFull == true and ("full:" .. tostring(blockedFullDemand)))
    or (cap.freeSlots ~= nil and ("free:" .. tostring(math.min(cap.freeSlots, 6))))
    or "cap:unknown"
  local baseDecisionSig = table.concat({
    mapBucket,
    table.concat(availIds, ","),
    capStateStr,
    table.concat(spatialParts, ";"),
    pinDigest,
  }, "|")

  -- 1. User pin override always retains highest priority while pinned action remains available
  local pinnedID = progress and progress.pinnedActionID or nil
  if type(pinnedID) == "string" and pinnedID ~= "" then
    for _, entry in ipairs(resolvedEntries) do
      if entry.action.actionID == pinnedID then
        local deferredCount = (entry.action.kind == "turnin") and math.max(0, totalReadyTurnins - 1) or totalReadyTurnins
        return entry.action, {
          zoneStatus = posOk and ((playerMapID == primaryUiMapID or playerMapID == 1444) and "in_zone" or "off_zone") or "position_unavailable",
          anchorGroupID = entry.serviceGroupID,
          anchorLabel = entry.serviceGroupLabel,
          insertedGroupID = nil,
          selectedGroupID = entry.serviceGroupID,
          selectionReason = "pinned",
          selectionReasonLabel = SELECTION_REASON_LABELS.pinned,
          hubReturnPlanned = (entry.action.kind == "turnin"),
          deferredReadyCount = deferredCount,
          readyCount = totalReadyTurnins,
          slotDeficit = 0,
          decisionSig = baseDecisionSig,
          retainCommitment = true,
          deferDecisionCommit = false,
          groupScores = {},
        }
      end
    end
  end

  -- 2. Unknown player position: honest deterministic fallback, zero fabricated proximity
  if not posOk then
    local fbAct = deterministicFallbackAction(availableEvaluations, progress, baseDecisionSig)
    local fbGroupID = fbAct and meta and meta.staticGroupIDByActionID[fbAct.actionID] or (fbAct and fbAct.actionID) or nil
    local fbLabel = (fbGroupID and meta and meta.groupDefsByID[fbGroupID] and meta.groupDefsByID[fbGroupID].label)
      or (fbAct and (fbAct.npcName or fbAct.title))
      or nil
    return fbAct, {
      zoneStatus = "position_unavailable",
      anchorGroupID = fbGroupID,
      anchorLabel = fbLabel,
      insertedGroupID = nil,
      selectedGroupID = fbGroupID,
      selectionReason = "position_unavailable",
      selectionReasonLabel = SELECTION_REASON_LABELS.position_unavailable,
      hubReturnPlanned = (fbAct ~= nil and fbAct.kind == "turnin"),
      deferredReadyCount = (fbAct and fbAct.kind == "turnin") and math.max(0, totalReadyTurnins - 1) or totalReadyTurnins,
      readyCount = totalReadyTurnins,
      slotDeficit = 0,
      decisionSig = baseDecisionSig,
      retainCommitment = false,
      deferDecisionCommit = false,
      groupScores = {},
    }
  end

  -- 3. Feralas (1444) explicit zone-exit delivery rule
  if playerMapID == 1444 then
    for _, entry in ipairs(resolvedEntries) do
      if entry.uiMapID == 1444 then
        return entry.action, {
          zoneStatus = "feralas_delivery",
          anchorGroupID = entry.serviceGroupID,
          anchorLabel = entry.serviceGroupLabel,
          insertedGroupID = nil,
          selectedGroupID = entry.serviceGroupID,
          selectionReason = "zone_exit",
          selectionReasonLabel = SELECTION_REASON_LABELS.zone_exit,
          hubReturnPlanned = (entry.action.kind == "turnin"),
          deferredReadyCount = math.max(0, totalReadyTurnins - 1),
          readyCount = totalReadyTurnins,
          slotDeficit = 0,
          decisionSig = baseDecisionSig,
          retainCommitment = false,
          deferDecisionCommit = false,
          groupScores = {},
        }
      end
    end
  end

  -- 4. Unrelated continent / city / dungeon (`uiMapID ~= primaryUiMapID` and no active local step on current map):
  --    Unaccepted external-map side/group quests (`kind == "accept"`) must NEVER hijack `/fh rg start` off-zone!
  --    Show "Travel to Riverglades to begin" without comparing remote actions at 500000 sentinel yards!
  local hasSameMapEntry = false
  if playerMapID == primaryUiMapID then
    for _, entry in ipairs(resolvedEntries) do
      if entry.uiMapID == playerMapID then
        hasSameMapEntry = true
        break
      end
    end
  elseif anyQuestStarted then
    for _, entry in ipairs(resolvedEntries) do
      if entry.uiMapID == playerMapID and entry.action.kind ~= "accept" then
        hasSameMapEntry = true
        break
      end
    end
  end
  if playerMapID ~= primaryUiMapID and not hasSameMapEntry then
    local primaryEvals = {}
    for _, ev in ipairs(availableEvaluations) do
      local d = ev.action and ev.action.destination
      if d and tonumber(d.uiMapID) == primaryUiMapID then
        table.insert(primaryEvals, ev)
      end
    end
    local entryAct = deterministicFallbackAction(
      (#primaryEvals > 0) and primaryEvals or availableEvaluations,
      progress,
      baseDecisionSig
    )
    local entryGroupID = entryAct and meta and meta.staticGroupIDByActionID[entryAct.actionID] or nil
    local entryLabel = (entryGroupID and meta and meta.groupDefsByID[entryGroupID] and meta.groupDefsByID[entryGroupID].label)
      or (entryAct and (entryAct.npcName or entryAct.title))
      or "Riverglades"
    return entryAct, {
      zoneStatus = "off_zone",
      anchorGroupID = entryGroupID,
      anchorLabel = entryLabel,
      insertedGroupID = nil,
      selectedGroupID = entryGroupID,
      selectionReason = "travel_to_zone",
      selectionReasonLabel = SELECTION_REASON_LABELS.travel_to_zone,
      hubReturnPlanned = false,
      deferredReadyCount = totalReadyTurnins,
      readyCount = totalReadyTurnins,
      slotDeficit = 0,
      decisionSig = baseDecisionSig,
      retainCommitment = false,
      deferDecisionCommit = false,
      groupScores = {},
    }
  end

  -- 5. Onboarding intro waypoints (`retireWhenAnyQuestStarted == true`) before any quest has started
  if not anyQuestStarted then
    for _, entry in ipairs(resolvedEntries) do
      if entry.uiMapID == playerMapID and entry.action.retireWhenAnyQuestStarted == true then
        return entry.action, {
          zoneStatus = "in_zone",
          anchorGroupID = entry.serviceGroupID,
          anchorLabel = entry.serviceGroupLabel,
          insertedGroupID = nil,
          selectedGroupID = entry.serviceGroupID,
          selectionReason = "onboarding",
          selectionReasonLabel = SELECTION_REASON_LABELS.onboarding,
          hubReturnPlanned = false,
          deferredReadyCount = totalReadyTurnins,
          readyCount = totalReadyTurnins,
          slotDeficit = 0,
          decisionSig = baseDecisionSig,
          retainCommitment = false,
          deferDecisionCommit = false,
          groupScores = {},
        }
      end
    end
  end

  -- 6. Partition same-map actions into Core -> Optional -> Supply pools; cross-map only if same-map is empty
  local coreSameMap = {}
  local optionalSameMap = {}
  local supplySameMap = {}
  local crossMapEntries = {}
  local coreObjectiveEntries = {}
  local campCounts = {}

  for _, entry in ipairs(resolvedEntries) do
    if entry.uiMapID == playerMapID then
      local isDeferred, bucketName = isOptionalDeferredCandidate(entry.action, elitesEnabled)
      if not isDeferred then
        table.insert(coreSameMap, entry)
        if entry.action.kind == "objective" then
          table.insert(coreObjectiveEntries, entry)
          local campID = meta and meta.campClusterByActionID[entry.action.actionID] or nil
          if campID then
            campCounts[campID] = (campCounts[campID] or 0) + 1
          end
        end
      elseif bucketName == "optional" then
        table.insert(optionalSameMap, entry)
      else
        table.insert(supplySameMap, entry)
      end
    else
      table.insert(crossMapEntries, entry)
    end
  end

  local activePool = coreSameMap
  if #activePool == 0 then
    if #optionalSameMap > 0 then
      activePool = optionalSameMap
    elseif #crossMapEntries > 0 then
      -- Only cross-map actions remain before passive supply objectives (e.g. Feralas delivery 95219)
      local xAct = crossMapEntries[1].action
      return xAct, {
        zoneStatus = "in_zone",
        anchorGroupID = crossMapEntries[1].serviceGroupID,
        anchorLabel = crossMapEntries[1].serviceGroupLabel,
        insertedGroupID = nil,
        selectedGroupID = crossMapEntries[1].serviceGroupID,
        selectionReason = "zone_exit",
        selectionReasonLabel = SELECTION_REASON_LABELS.zone_exit,
        hubReturnPlanned = (xAct.kind == "turnin"),
        deferredReadyCount = math.max(0, totalReadyTurnins - 1),
        readyCount = totalReadyTurnins,
        slotDeficit = 0,
        decisionSig = baseDecisionSig,
        retainCommitment = false,
        deferDecisionCommit = false,
        groupScores = {},
      }
    else
      activePool = supplySameMap
    end
  end

  -- 7. Build candidate service groups from activePool
  local groupsByID = {}
  local groupList = {}
  local hasRemainingCoreWork = false
  local nearbyUsefulPickupDemand = 0
  local seenPickupDemandQuest = {}

  for _, entry in ipairs(activePool) do
    local sgID = entry.serviceGroupID
    local grp = groupsByID[sgID]
    if not grp then
      grp = {
        groupID = sgID,
        kind = entry.serviceGroupKind,
        label = entry.serviceGroupLabel,
        entries = {},
        readyTurninEntries = {},
        usefulPickupEntries = {},
        distinctReadyMap = {},
        distinctReadyCount = 0,
        distinctUsefulPickupMap = {},
        distinctUsefulPickupCount = 0,
        distanceFromPlayer = nil,
        repDest = entry.dest,
        usefulRepDest = nil,
        usefulDistanceFromPlayer = nil,
        minCircuitRank = tonumber(entry.action.circuitRank) or tonumber(entry.orderIndex) or 999999,
        minOrderIndex = tonumber(entry.orderIndex) or 999999,
      }
      groupsByID[sgID] = grp
      table.insert(groupList, grp)
    end

    table.insert(grp.entries, entry)
    local rnk = tonumber(entry.action.circuitRank) or tonumber(entry.orderIndex) or 999999
    if rnk < grp.minCircuitRank then
      grp.minCircuitRank = rnk
    end
    local ord = tonumber(entry.orderIndex) or 999999
    if ord < grp.minOrderIndex then
      grp.minOrderIndex = ord
    end

    local py = entry.playerYards
    if py ~= nil and (grp.distanceFromPlayer == nil or py < grp.distanceFromPlayer) then
      grp.distanceFromPlayer = py
      grp.repDest = entry.dest
    end

    local act = entry.action
    local cKey = canonicalQuestIdentity(route, getQuestRef(act)) or act.actionID
    if act.kind == "turnin" then
      table.insert(grp.readyTurninEntries, entry)
      if not grp.distinctReadyMap[cKey] then
        grp.distinctReadyMap[cKey] = true
        grp.distinctReadyCount = grp.distinctReadyCount + 1
      end
      if py ~= nil and (grp.usefulDistanceFromPlayer == nil or py < grp.usefulDistanceFromPlayer) then
        grp.usefulDistanceFromPlayer = py
        grp.usefulRepDest = entry.dest
      end
    elseif act.kind == "accept" then
      if meta and isUsefulPickupEntry(entry, meta) then
        hasRemainingCoreWork = true
        table.insert(grp.usefulPickupEntries, entry)
        if not grp.distinctUsefulPickupMap[cKey] then
          grp.distinctUsefulPickupMap[cKey] = true
          grp.distinctUsefulPickupCount = grp.distinctUsefulPickupCount + 1
        end
        if py ~= nil and py <= 500.0 and not seenPickupDemandQuest[cKey] then
          seenPickupDemandQuest[cKey] = true
          nearbyUsefulPickupDemand = nearbyUsefulPickupDemand + 1
        end
        if py ~= nil and (grp.usefulDistanceFromPlayer == nil or py < grp.usefulDistanceFromPlayer) then
          grp.usefulDistanceFromPlayer = py
          grp.usefulRepDest = entry.dest
        end
      end
    elseif (act.kind == "objective" or act.kind == "travel") and act.isSupplyObjective ~= true then
      hasRemainingCoreWork = true
    end
  end

  -- Demand-aware quest-log capacity deficit (Astra Rule 6):
  -- At 38/40 with r=0 planned pickups, slotDeficit == 0 -> zero emergency hub return!
  local slotDeficit = 0
  if cap.status == "ok" then
    if cap.isFull == true then
      slotDeficit = math.max(blockedFullDemand, nearbyUsefulPickupDemand)
    elseif type(cap.freeSlots) == "number" then
      slotDeficit = math.max(0, nearbyUsefulPickupDemand - cap.freeSlots)
    end
  end

  local decisionSig = baseDecisionSig .. "|def:" .. tostring(slotDeficit)

  -- 8. Commitment Policy Check (Astra Rule 7):
  --    - With unchanged eligibility, capacity pressure, pin, map, and live spatial revisions (`decisionSig == committedDecisionSig`),
  --      movement alone NEVER replaces a committed target!
  --    - In combat, discretionary switches are deferred while the current action remains valid & available.
  local currentID = progress and progress.currentActionID or nil
  local currentStillAvailable = false
  local currentGroupID = nil
  if type(currentID) == "string" and currentID ~= "" then
    for _, grp in ipairs(groupList) do
      for _, e in ipairs(grp.entries) do
        if e.action.actionID == currentID then
          currentStillAvailable = true
          currentGroupID = grp.groupID
          break
        end
      end
      if currentStillAvailable then
        break
      end
    end
  end

  local inCombat = (ctx and type(ctx.isInCombat) == "function" and ctx.isInCombat() == true)
    or (ns.Compat and ns.Compat.IsInCombat and ns.Compat.IsInCombat() == true)
    or false

  if progress and type(progress.committedDecisionSig) == "string" and progress.committedDecisionSig == decisionSig then
    local commIns = progress.insertedGroupID and groupsByID[progress.insertedGroupID] or nil
    local commAnc = progress.committedAnchorGroupID and groupsByID[progress.committedAnchorGroupID] or nil
    local lockedGrp = commIns or commAnc
    if lockedGrp then
      local chosenAct = selectBestActionWithinGroup(lockedGrp, currentID, anyQuestStarted)
      local effAnc = commAnc or lockedGrp
      local reasonCode = commIns and "on_route" or ((effAnc.distinctReadyCount > 0 and slotDeficit > 0) and "frees_slot" or "nearby_step")
      local defReady = (chosenAct and chosenAct.kind == "turnin")
        and math.max(0, totalReadyTurnins - lockedGrp.distinctReadyCount)
        or totalReadyTurnins
      return chosenAct, {
        zoneStatus = "in_zone",
        anchorGroupID = effAnc.groupID,
        anchorLabel = effAnc.label,
        insertedGroupID = commIns and commIns.groupID or nil,
        selectedGroupID = lockedGrp.groupID,
        selectionReason = reasonCode,
        selectionReasonLabel = SELECTION_REASON_LABELS[reasonCode] or SELECTION_REASON_LABELS.nearby_step,
        hubReturnPlanned = (effAnc.distinctReadyCount > 0) or (commIns ~= nil and commIns.distinctReadyCount > 0),
        deferredReadyCount = defReady,
        readyCount = totalReadyTurnins,
        slotDeficit = slotDeficit,
        decisionSig = decisionSig,
        retainCommitment = true,
        deferDecisionCommit = false,
        groupScores = {},
      }
    end
  end

  if inCombat and currentStillAvailable and currentGroupID and groupsByID[currentGroupID] then
    local combatGrp = groupsByID[currentGroupID]
    local combatAct = selectBestActionWithinGroup(combatGrp, currentID, anyQuestStarted)
    return combatAct, {
      zoneStatus = "in_zone",
      anchorGroupID = progress and progress.committedAnchorGroupID or currentGroupID,
      anchorLabel = combatGrp.label,
      insertedGroupID = progress and progress.insertedGroupID or nil,
      selectedGroupID = currentGroupID,
      selectionReason = "nearby_step",
      selectionReasonLabel = SELECTION_REASON_LABELS.nearby_step,
      hubReturnPlanned = (combatGrp.distinctReadyCount > 0),
      deferredReadyCount = (combatAct and combatAct.kind == "turnin")
        and math.max(0, totalReadyTurnins - combatGrp.distinctReadyCount)
        or totalReadyTurnins,
      readyCount = totalReadyTurnins,
      slotDeficit = slotDeficit,
      decisionSig = decisionSig,
      retainCommitment = true,
      deferDecisionCommit = true,
      groupScores = {},
    }
  end

  -- 9. Continuous Anchor Scoring: S(H) = D(P,H) + L(H) + W(H) + F(H) - B(H) - U(H) - C(H)
  local groupScores = {}
  local bestAnchor = nil
  local prevAnchorID = progress and progress.committedAnchorGroupID or nil
  local wasServicingInsert = (progress and type(progress.insertedGroupID) == "string" and progress.insertedGroupID ~= "")

  for _, grp in ipairs(groupList) do
    local dPH = grp.distanceFromPlayer or 0.0

    -- Internal travel spread L(H)
    local internalSpread = 0.0
    if grp.kind == "hub" and #grp.entries > 1 then
      local maxPair = 0.0
      for i = 1, #grp.entries - 1 do
        for j = i + 1, #grp.entries do
          local pd = computeDestDistanceYards(grp.entries[i].dest, grp.entries[j].dest)
          if pd and pd > maxPair then
            maxPair = pd
          end
        end
      end
      internalSpread = math.min(45.0, 0.25 * maxPair)
    elseif grp.kind == "objective" and #grp.entries == 1 then
      local onlyAct = grp.entries[1].action
      if type(onlyAct.subLocations) == "table" and #onlyAct.subLocations > 1 then
        local activeSubs = RoutePlanner.ResolveActiveSubLocations(onlyAct, ctx)
        if #activeSubs > 1 then
          local maxSubSpan = 0.0
          for i = 1, #activeSubs - 1 do
            for j = i + 1, #activeSubs do
              local sd = computeDestDistanceYards(activeSubs[i].destination, activeSubs[j].destination)
              if sd and sd > maxSubSpan then
                maxSubSpan = sd
              end
            end
          end
          internalSpread = math.min(90.0, 0.15 * maxSubSpan)
        end
      end
    end

    local serviceCost = (grp.kind == "hub") and W_NPC_GROUP or W_OBJECTIVE_GROUP

    -- Counterfactual batch evaluation for hubs with ready turn-ins
    local feasibleBatchCount = 0
    local unlockBenefit = 0.0
    local freedSlots = 0
    if grp.distinctReadyCount > 0 and meta then
      feasibleBatchCount, unlockBenefit, freedSlots = evaluateCounterfactualHubBatch(
        grp,
        route,
        progress,
        ctx,
        byActionID,
        meta,
        cap,
        playerPos,
        coreObjectiveEntries
      )
    end
    grp.feasibleReadyCount = feasibleBatchCount
    grp.unlockBenefit = unlockBenefit
    grp.freedSlots = freedSlots

    -- Cap effective useful pickups at hub by available slots after turning in ready quests
    local nEffUsefulPickups = grp.distinctUsefulPickupCount
    if cap.freeSlots ~= nil then
      nEffUsefulPickups = math.min(nEffUsefulPickups, math.max(0, cap.freeSlots + freedSlots))
    end
    grp.nEffUsefulPickups = nEffUsefulPickups

    -- Bounded batch benefit B(H): only rewards batching 2+ actions on the same stop (never discounts a lone 1-quest stop)
    local batchBenefit = 0.0
    if grp.kind == "hub" then
      local rawHubBatch = 0.0
      if feasibleBatchCount > 0 then
        rawHubBatch = 40.0 * math.max(0, feasibleBatchCount - 1) + 25.0 * nEffUsefulPickups
      else
        rawHubBatch = 25.0 * math.max(0, nEffUsefulPickups - 1)
      end
      batchBenefit = math.min(MAX_BATCH_BENEFIT_YARDS, rawHubBatch)
    else
      local onlyAct = grp.entries[1] and grp.entries[1].action or nil
      local campID = (onlyAct and meta and meta.campClusterByActionID[onlyAct.actionID]) or nil
      local coLocated = campID and math.max(0, (campCounts[campID] or 1) - 1) or 0
      batchBenefit = math.min(MAX_BATCH_BENEFIT_YARDS, 20.0 * coLocated)
    end

    -- Demand-aware capacity benefit C(H)
    local capacityBenefit = 0.0
    if slotDeficit > 0 and freedSlots > 0 then
      local effRel = math.min(freedSlots, slotDeficit)
      capacityBenefit = math.min(
        MAX_CAPACITY_BENEFIT_YARDS,
        160.0 * math.min(1, effRel)
          + 45.0 * math.max(0, effRel - 1)
          + 15.0 * math.max(0, freedSlots - effRel)
      )
    end

    -- Smooth leaf & sibling deferral F(H) (zero when all core work/pickups are exhausted or slotDeficit > 0)
    local deferral = 0.0
    if hasRemainingCoreWork and slotDeficit == 0 and grp.kind == "hub" and feasibleBatchCount > 0 then
      local fLeaf = 0.0
      if nEffUsefulPickups == 0 and unlockBenefit <= 0.0 then
        fLeaf = LEAF_DEFERRAL_MAX_YARDS * smoothstep01((dPH - 80.0) / 320.0)
      end

      local fSib = 0.0
      if meta then
        local minExtraTrip = nil
        for _, objEntry in ipairs(coreObjectiveEntries) do
          local oKey = canonicalQuestIdentity(route, getQuestRef(objEntry.action))
          local qInfo = oKey and meta.questActionsByKey[oKey] or nil
          if qInfo and qInfo.turninGroupIDs[grp.groupID] then
            local dHObj = computeDestDistanceYards(grp.repDest, objEntry.dest)
            local dPObj = objEntry.playerYards
            if dHObj ~= nil and dPObj ~= nil then
              local extraTrip = math.max(0.0, dPH + dHObj - dPObj)
              if minExtraTrip == nil or extraTrip < minExtraTrip then
                minExtraTrip = extraTrip
              end
            end
          end
        end
        if minExtraTrip ~= nil then
          fSib = math.min(SIBLING_DEFERRAL_MAX_YARDS, 0.5 * minExtraTrip)
        end
      end

      deferral = math.max(fLeaf, fSib)
    end

    -- Preserve committed anchor smoothly after completing an en-route insertion
    local anchorContinuityCredit = 0.0
    if wasServicingInsert and prevAnchorID ~= nil and grp.groupID == prevAnchorID then
      anchorContinuityCredit = 30.0
    end

    local totalScore = dPH
      + internalSpread
      + serviceCost
      + deferral
      - batchBenefit
      - unlockBenefit
      - capacityBenefit
      - anchorContinuityCredit

    grp.score = totalScore
    grp.scoreBreakdown = {
      score = totalScore,
      distance = dPH,
      internalSpread = internalSpread,
      serviceCost = serviceCost,
      deferral = deferral,
      batchBenefit = batchBenefit,
      unlockBenefit = unlockBenefit,
      capacityBenefit = capacityBenefit,
    }
    groupScores[grp.groupID] = grp.scoreBreakdown

    if not bestAnchor then
      bestAnchor = grp
    else
      local diff = totalScore - bestAnchor.score
      if (diff < -0.5)
        or (math.abs(diff) <= 0.5 and dPH < (bestAnchor.distanceFromPlayer or 0) - 0.5)
        or (math.abs(diff) <= 0.5 and math.abs(dPH - (bestAnchor.distanceFromPlayer or 0)) <= 0.5 and unlockBenefit > bestAnchor.unlockBenefit + 0.5)
        or (math.abs(diff) <= 0.5 and math.abs(dPH - (bestAnchor.distanceFromPlayer or 0)) <= 0.5 and math.abs(unlockBenefit - bestAnchor.unlockBenefit) <= 0.5 and freedSlots > bestAnchor.freedSlots)
        or (math.abs(diff) <= 0.5 and math.abs(dPH - (bestAnchor.distanceFromPlayer or 0)) <= 0.5 and math.abs(unlockBenefit - bestAnchor.unlockBenefit) <= 0.5 and freedSlots == bestAnchor.freedSlots and grp.minCircuitRank < bestAnchor.minCircuitRank)
        or (math.abs(diff) <= 0.5 and math.abs(dPH - (bestAnchor.distanceFromPlayer or 0)) <= 0.5 and math.abs(unlockBenefit - bestAnchor.unlockBenefit) <= 0.5 and freedSlots == bestAnchor.freedSlots and grp.minCircuitRank == bestAnchor.minCircuitRank and grp.groupID < bestAnchor.groupID)
      then
        bestAnchor = grp
      end
    end
  end

  if not bestAnchor then
    bestAnchor = groupList[1]
  end

  -- 10. Bounded Single En-Route Insertion: Δ(X | P, A) = D(P, X) + D(X, A) - D(P, A) + W(X) <= 120
  local bestInsert = nil
  local bestInsertDetour = math.huge
  local dPA = bestAnchor.distanceFromPlayer or 0.0

  if dPA > 40.0 then
    for _, cand in ipairs(groupList) do
      if cand.groupID ~= bestAnchor.groupID
        and (cand.feasibleReadyCount > 0 or cand.nEffUsefulPickups > 0)
        and cand.usefulRepDest ~= nil
      then
        local dPX = cand.usefulDistanceFromPlayer or cand.distanceFromPlayer
        local dXA = computeDestDistanceYards(cand.usefulRepDest, bestAnchor.repDest)
        if dPX ~= nil and dXA ~= nil and dPX < dPA then
          local detour = dPX + dXA - dPA + W_INSERT_STOP
          if detour <= INSERT_MAX_DETOUR_YARDS then
            local candHasUnlock = (cand.unlockBenefit or 0) > 0
            local bestHasUnlock = bestInsert and ((bestInsert.unlockBenefit or 0) > 0) or false
            if (detour < bestInsertDetour - 0.5)
              or (math.abs(detour - bestInsertDetour) <= 0.5 and candHasUnlock and not bestHasUnlock)
              or (math.abs(detour - bestInsertDetour) <= 0.5 and candHasUnlock == bestHasUnlock and (cand.freedSlots or 0) > (bestInsert and bestInsert.freedSlots or 0))
              or (math.abs(detour - bestInsertDetour) <= 0.5 and candHasUnlock == bestHasUnlock and (cand.freedSlots or 0) == (bestInsert and bestInsert.freedSlots or 0) and cand.minCircuitRank < (bestInsert and bestInsert.minCircuitRank or math.huge))
              or (math.abs(detour - bestInsertDetour) <= 0.5 and candHasUnlock == bestHasUnlock and (cand.freedSlots or 0) == (bestInsert and bestInsert.freedSlots or 0) and cand.minCircuitRank == (bestInsert and bestInsert.minCircuitRank or math.huge) and cand.groupID < (bestInsert and bestInsert.groupID or ""))
            then
              bestInsert = cand
              bestInsertDetour = detour
            end
          end
        end
      end
    end
  end

  local selectedGroup = bestInsert or bestAnchor
  local chosenAction = selectBestActionWithinGroup(selectedGroup, currentID, anyQuestStarted)

  local reasonCode = "nearby_step"
  if bestInsert ~= nil then
    reasonCode = "on_route"
  elseif (selectedGroup.scoreBreakdown and selectedGroup.scoreBreakdown.capacityBenefit or 0) > 0 then
    reasonCode = "frees_slot"
  elseif (selectedGroup.unlockBenefit or 0) >= 25.0 then
    reasonCode = "unlocks_nearby"
  elseif selectedGroup.kind == "hub" and (selectedGroup.feasibleReadyCount or 0) > 0 then
    reasonCode = "hub_batch"
  end

  local hubReturnPlanned = ((bestAnchor.feasibleReadyCount or 0) > 0)
    or (bestInsert ~= nil and (bestInsert.feasibleReadyCount or 0) > 0)
  local deferredReadyCount = (chosenAction and chosenAction.kind == "turnin")
    and math.max(0, totalReadyTurnins - (selectedGroup.distinctReadyCount or 1))
    or totalReadyTurnins

  return chosenAction, {
    zoneStatus = "in_zone",
    anchorGroupID = bestAnchor.groupID,
    anchorLabel = bestAnchor.label,
    insertedGroupID = bestInsert and bestInsert.groupID or nil,
    insertedDetourYards = bestInsert and bestInsertDetour or nil,
    selectedGroupID = selectedGroup.groupID,
    selectionReason = reasonCode,
    selectionReasonLabel = SELECTION_REASON_LABELS[reasonCode] or SELECTION_REASON_LABELS.nearby_step,
    hubReturnPlanned = hubReturnPlanned,
    deferredReadyCount = deferredReadyCount,
    readyCount = totalReadyTurnins,
    slotDeficit = slotDeficit,
    decisionSig = decisionSig,
    retainCommitment = false,
    deferDecisionCommit = false,
    groupScores = groupScores,
  }
end

function RoutePlanner.SelectBestNextAction(availableEvaluations, route, progress, playerPos, anyQuestStarted, ctx, evaluations, byActionID)
  if type(availableEvaluations) ~= "table" or #availableEvaluations == 0 then
    return nil, nil
  end
  if type(byActionID) ~= "table" then
    byActionID = {}
    for _, ev in ipairs(evaluations or availableEvaluations) do
      if ev and ev.action and ev.action.actionID then
        byActionID[ev.action.actionID] = ev
      end
    end
  end
  return RoutePlanner.PlanNextAction(
    availableEvaluations,
    evaluations or availableEvaluations,
    byActionID,
    route,
    progress,
    playerPos,
    anyQuestStarted,
    ctx
  )
end

function RoutePlanner.ListUnresolvedTitlePickups(eval, route)
  local list = {}
  if type(eval) ~= "table" or type(eval.evaluations) ~= "table" then
    return list
  end
  local seen = {}
  for _, row in ipairs(eval.evaluations) do
    local act = row.action
    if row.state == "blocked_unresolved_history" and act and act.kind == "accept" then
      local qKey = tostring(act.questKey or act.actionID)
      if not seen[qKey] then
        seen[qKey] = true
        local qMeta = lookupQuestMeta(route, qKey)
        table.insert(list, {
          actionID = act.actionID,
          questKey = act.questKey,
          questTitle = (qMeta and (qMeta.name or qMeta.title)) or act.title or qKey,
          npcName = act.npcName,
          destination = act.destination,
        })
      end
    end
  end
  return list
end

-- Evaluates the entire route purely (zero state/progress/cache mutation) and returns nextAction + plan.
function RoutePlanner.EvaluateRoute(route, progress, ctx, playerPos)
  ctx = ctx or RoutePlanner.BuildDefaultContext()
  if type(route) ~= "table" or type(route.actions) ~= "table" then
    return {
      valid = false,
      evaluations = {},
      byActionID = {},
      availableActions = {},
      nextAction = nil,
      plan = nil,
      counts = { completed = 0, skipped = 0, available = 0, blocked = 0, ineligible = 0, total = 0 },
    }
  end

  local evaluations = {}
  local byActionID = {}
  local availableActions = {}
  local availableEvaluations = {}
  local counts = {
    completed = 0,
    skipped = 0,
    available = 0,
    blocked = 0,
    blockedUnverified = 0,
    blockedQuestLogFull = 0,
    blockedUnresolvedHistory = 0,
    ineligible = 0,
    total = #route.actions,
  }

  local completionMemo = {}
  local anyQuestStarted = RoutePlanner.HasAnyRouteQuestStarted(route, ctx, completionMemo)

  for idx, act in ipairs(route.actions) do
    local ev = RoutePlanner.EvaluateAction(act, route, progress, ctx, anyQuestStarted, completionMemo)
    ev.orderIndex = idx
    ev.action = act
    table.insert(evaluations, ev)
    byActionID[act.actionID] = ev

    if ev.state == "completed" then
      counts.completed = counts.completed + 1
    elseif ev.state == "skipped" then
      counts.skipped = counts.skipped + 1
    elseif ev.state == "available" then
      counts.available = counts.available + 1
      table.insert(availableActions, act)
      table.insert(availableEvaluations, ev)
    elseif ev.state == "ineligible" then
      counts.ineligible = counts.ineligible + 1
    else
      counts.blocked = counts.blocked + 1
      if ev.state == "blocked_unverified" then
        counts.blockedUnverified = counts.blockedUnverified + 1
      elseif ev.state == "blocked_quest_log_full" then
        counts.blockedQuestLogFull = counts.blockedQuestLogFull + 1
      elseif ev.state == "blocked_unresolved_history" then
        counts.blockedUnresolvedHistory = counts.blockedUnresolvedHistory + 1
      end
    end
  end

  local nextAction, plan = RoutePlanner.PlanNextAction(
    availableEvaluations,
    evaluations,
    byActionID,
    route,
    progress,
    playerPos,
    anyQuestStarted,
    ctx
  )
  local blockedNoticeAction = nil
  if not nextAction then
    for _, ev in ipairs(evaluations) do
      if ev.state == "blocked_quest_log_full" then
        blockedNoticeAction = ev
        break
      end
    end
    if not blockedNoticeAction then
      for _, ev in ipairs(evaluations) do
        if ev.state == "blocked_unresolved_history" then
          blockedNoticeAction = ev
          break
        end
      end
    end
  end

  return {
    valid = true,
    anyQuestStarted = anyQuestStarted,
    evaluations = evaluations,
    byActionID = byActionID,
    availableActions = availableActions,
    nextAction = nextAction,
    plan = plan,
    blockedNotice = blockedNoticeAction,
    counts = counts,
  }
end

function RoutePlanner.InspectQuestCoverage(questID, rawTitle, route, eval, ctx, progress)
  route = route or (ns.State and ns.State.GetCompiledRivergladesRoute and ns.State.GetCompiledRivergladesRoute())
  if type(route) ~= "table" then
    return { status = "unmapped", hasMapPin = false }
  end
  ctx = ctx or RoutePlanner.BuildDefaultContext()
  progress = progress or (ns.State and ns.State.GetRouteProgress and ns.State.GetRouteProgress())

  local qid = tonumber(questID)
  if qid and qid <= 0 then
    qid = nil
  end
  local normTitle = ns.Compat and ns.Compat.NormalizeQuestTitle and ns.Compat.NormalizeQuestTitle(rawTitle) or nil
  local qMeta = nil
  if ns.Compat and ns.Compat.LookupRouteQuestMeta then
    qMeta = ns.Compat.LookupRouteQuestMeta(qid or rawTitle)
  end
  if not qid and qMeta then
    qid = tonumber(qMeta.questID) or tonumber(qMeta.knownQuestID) or nil
  end
  if not normTitle and qMeta and type(qMeta.name) == "string" and ns.Compat and ns.Compat.NormalizeQuestTitle then
    normTitle = ns.Compat.NormalizeQuestTitle(qMeta.name)
  end
  local questKey = (qMeta and qMeta.questKey) or (normTitle and ("title:" .. normTitle)) or nil
  local resolvedTitle = (qMeta and qMeta.name) or rawTitle or (qid and ("Quest #" .. tostring(qid))) or "Selected Quest"
  local questLevel = qMeta and tonumber(qMeta.questLevel) or nil

  local function matchesAction(act)
    if type(act) ~= "table" then
      return false
    end
    if qid and tonumber(act.questID) == qid then
      return true
    end
    if questKey and type(act.questKey) == "string" and act.questKey == questKey then
      return true
    end
    if qMeta and type(qMeta.questKey) == "string" and act.questKey == qMeta.questKey then
      return true
    end
    return false
  end

  local qRef = (qMeta and qMeta.questKey) or qid or questKey
  local isOnQuest = false
  local objsComplete = false
  if qRef ~= nil then
    local onRes = (ctx and type(ctx.isOnQuest) == "function") and ctx.isOnQuest(qRef)
      or (ns.Compat and ns.Compat.IsOnQuestResult and ns.Compat.IsOnQuestResult(qRef))
    if type(onRes) == "table" and onRes.status == "ok" and onRes.value == true then
      isOnQuest = true
    end
    if qMeta and qMeta.zeroObjectives == true then
      objsComplete = true
    else
      local objRes = (ctx and type(ctx.getQuestObjectives) == "function") and ctx.getQuestObjectives(qRef)
        or (ns.Compat and ns.Compat.GetQuestObjectivesResult and ns.Compat.GetQuestObjectivesResult(qRef))
      if type(objRes) == "table" and objRes.status == "ok" and objRes.allFinished == true then
        objsComplete = true
      end
    end
  end

  local matchingActionIDs = {}
  local hasObjectiveStep = false
  local hasTurnInStep = false
  local hasActivePin = false

  for _, act in ipairs(route.actions or {}) do
    if matchesAction(act) then
      table.insert(matchingActionIDs, act.actionID)
      local ev = eval and eval.byActionID and eval.byActionID[act.actionID] or nil
      local evState = ev and ev.state or nil
      if act.kind == "objective" then
        hasObjectiveStep = true
        if evState == "available"
          or evState == "skipped"
          or (evState == "ineligible" and ev and ev.reason == "optional_elite_bounty_disabled" and isOnQuest and not objsComplete)
          or (ev == nil and isOnQuest and not objsComplete)
        then
          hasActivePin = true
        end
      elseif act.kind == "turnin" then
        hasTurnInStep = true
        if evState == "available" or evState == "skipped" or (ev == nil and isOnQuest and objsComplete) then
          hasActivePin = true
        end
      elseif act.kind == "accept" then
        if evState == "available" or evState == "blocked_quest_log_full" then
          hasActivePin = true
        end
      end
    end
  end

  local quarantinedReason = qMeta and qMeta.quarantineReason or nil
  for _, qAct in ipairs(route.quarantinedActions or {}) do
    if matchesAction(qAct) then
      quarantinedReason = quarantinedReason or qAct.reason or qAct.title
      break
    end
  end

  local status = "unmapped"
  if hasActivePin then
    status = "mapped_active"
  elseif quarantinedReason ~= nil or (qMeta ~= nil and isOnQuest and not objsComplete and not hasObjectiveStep) then
    status = "quarantined_objective"
  elseif qMeta ~= nil or #matchingActionIDs > 0 then
    status = (hasTurnInStep and isOnQuest and objsComplete) and "mapped_active" or "mapped_inactive"
  end

  return {
    questID = qid,
    normTitle = normTitle,
    questKey = questKey,
    questTitle = resolvedTitle,
    questLevel = questLevel,
    isElite = (qMeta and (qMeta.isEliteBounty == true or qMeta.isElite == true)) or false,
    isOnQuest = isOnQuest,
    objectivesComplete = objsComplete,
    status = status,
    hasMapPin = hasActivePin,
    quarantinedReason = quarantinedReason,
    matchingActionIDs = matchingActionIDs,
  }
end
