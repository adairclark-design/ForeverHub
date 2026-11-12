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
  -- EXCEPT ready-to-turn-in Elite bounties are always surfaced so completed kills are cashed in!).
  if action.isEliteBounty == true and not (progress and progress.includeEliteBounties == true) then
    if action.kind == "turnin" then
      local reqReady = RoutePlanner.EvaluatePredicate(action.requires, progress, ctx, route, memo)
      if reqReady ~= true then
        return false, "optional_elite_bounty_disabled"
      end
    else
      return false, "optional_elite_bounty_disabled"
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

local function estimateDestYardsForScoring(dest, playerPos)
  if type(dest) ~= "table" or type(playerPos) ~= "table" or playerPos.status ~= "ok" then
    return 999999
  end
  if tonumber(dest.uiMapID) ~= tonumber(playerPos.uiMapID) then
    return 500000
  end
  if ns.Compat and ns.Compat.GetWorldDistanceYards then
    local distRes = ns.Compat.GetWorldDistanceYards(
      dest.uiMapID,
      playerPos.x01,
      playerPos.y01,
      dest.x01,
      dest.y01
    )
    if type(distRes) == "table" and distRes.status == "ok" and type(distRes.yards) == "number" then
      return distRes.yards
    end
  end
  local dx = ((tonumber(dest.x01) or 0) - (tonumber(playerPos.x01) or 0)) * 3600.0
  local dy = ((tonumber(dest.y01) or 0) - (tonumber(playerPos.y01) or 0)) * 2400.0
  return math.sqrt(dx * dx + dy * dy)
end

local function estimateActionYardsForScoring(act, playerPos)
  return estimateDestYardsForScoring(act and act.destination, playerPos)
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
function RoutePlanner.ResolveActiveActionTarget(action, progress, ctx, playerPos, route)
  if type(action) ~= "table" then
    return nil, nil, nil, nil
  end
  if type(action.subLocations) ~= "table" or #action.subLocations == 0 then
    if (action.kind == "turnin" or action.kind == "objective")
      and ns.Compat
      and type(ns.Compat.ResolveLiveQuestTargetOverride) == "function"
    then
      local liveOverride = ns.Compat.ResolveLiveQuestTargetOverride(action, route, progress, ctx)
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
    bestYards = estimateDestYardsForScoring(bestSub.destination, playerPos)
    for i = 2, #activeSubs do
      local cand = activeSubs[i]
      local y = estimateDestYardsForScoring(cand.destination, playerPos)
      if y < bestYards - 0.5 then
        bestSub = cand
        bestYards = y
      end
    end

    if progress and progress.currentActionID == action.actionID and type(progress.currentSubLocationID) == "string" then
      for _, sl in ipairs(activeSubs) do
        if sl.subID == progress.currentSubLocationID then
          if sl ~= bestSub then
            local curYards = estimateDestYardsForScoring(sl.destination, playerPos)
            if not (bestYards < curYards - SUBLOCATION_SWITCH_HYSTERESIS_YARDS) then
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

-- Selects the next eligible action using Hub-Aware Proximity & Quest-Drain Priority when
-- live player coordinates are available, scoring resolved unfinished destinations and applying
-- proximity-tier boundary hysteresis (Astra v0.7.1 P2 #3).
function RoutePlanner.SelectBestNextAction(availableEvaluations, route, progress, playerPos, anyQuestStarted, ctx)
  if type(availableEvaluations) ~= "table" or #availableEvaluations == 0 then
    return nil
  end

  local pinnedID = progress and progress.pinnedActionID or nil
  if type(pinnedID) == "string" and pinnedID ~= "" then
    for _, ev in ipairs(availableEvaluations) do
      if ev.action and ev.action.actionID == pinnedID then
        return ev.action
      end
    end
  end

  if type(playerPos) ~= "table" or playerPos.status ~= "ok" then
    return availableEvaluations[1].action
  end

  local currentID = progress and progress.currentActionID or nil
  local bestAction = nil
  local bestTier = math.huge
  local bestSortDist = math.huge
  local bestOrderIdx = math.huge

  for _, ev in ipairs(availableEvaluations) do
    local act = ev.action
    local scoreDest = act and act.destination or nil
    if act and ((type(act.subLocations) == "table" and #act.subLocations > 0) or act.kind == "turnin" or act.kind == "objective") then
      local resolvedDest = RoutePlanner.ResolveActiveActionTarget(act, progress, ctx, playerPos, route)
      if type(resolvedDest) == "table" then
        scoreDest = resolvedDest
      end
    end
    local yards = estimateDestYardsForScoring(scoreDest, playerPos)
    local destMapID = scoreDest and tonumber(scoreDest.uiMapID) or nil
    local sameMap = (destMapID ~= nil and destMapID == tonumber(playerPos.uiMapID))
    local isCurrent = (currentID ~= nil and act.actionID == currentID)

    local turninRadius = isCurrent and 260 or 220
    local acceptRadius = isCurrent and 220 or 180
    local objRadius = isCurrent and 235 or 180

    local tier = 5
    local sortDist = yards

    if act.retireWhenAnyQuestStarted == true and not anyQuestStarted then
      tier = 0
      sortDist = 0
    elseif act.isGroupBranch == true then
      tier = (act.kind == "turnin") and 8.0 or 8.5
      sortDist = yards
    elseif act.isZoneExit == true and not sameMap then
      tier = 7
      sortDist = 0
    elseif act.isSupplyObjective == true then
      tier = 6
      sortDist = 0
    elseif act.kind == "turnin" and sameMap and yards <= turninRadius then
      tier = 1
      sortDist = isCurrent and -1 or 0
    elseif act.kind == "accept" and sameMap and yards <= acceptRadius then
      tier = 2.0
      sortDist = isCurrent and -1 or 0
    elseif (act.kind == "objective" or act.kind == "travel") and sameMap and yards <= objRadius then
      tier = 2.5
      sortDist = isCurrent and -1 or 0
    elseif act.kind == "turnin" then
      tier = 3
      sortDist = yards
    elseif act.kind == "objective" or act.kind == "travel" or act.kind == "manual" then
      tier = 4
      sortDist = math.max(0, yards - (isCurrent and 200 or 0))
    else
      tier = 5
      sortDist = yards
    end

    local ord = tonumber(ev.orderIndex) or 999999
    if (tier < bestTier)
      or (tier == bestTier and sortDist < bestSortDist - 0.5)
      or (tier == bestTier and math.abs(sortDist - bestSortDist) <= 0.5 and ord < bestOrderIdx)
    then
      bestAction = act
      bestTier = tier
      bestSortDist = sortDist
      bestOrderIdx = ord
    end
  end

  return bestAction or availableEvaluations[1].action
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

-- Evaluates the entire route and deterministically chooses the next eligible action.
function RoutePlanner.EvaluateRoute(route, progress, ctx, playerPos)
  ctx = ctx or RoutePlanner.BuildDefaultContext()
  if type(route) ~= "table" or type(route.actions) ~= "table" then
    return {
      valid = false,
      evaluations = {},
      byActionID = {},
      availableActions = {},
      nextAction = nil,
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

  local nextAction = RoutePlanner.SelectBestNextAction(
    availableEvaluations,
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
    blockedNotice = blockedNoticeAction,
    counts = counts,
  }
end
