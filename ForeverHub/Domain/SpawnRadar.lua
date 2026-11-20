local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.Domain = ns.Domain or {}

local Compat = ns.Compat

local SpawnRadar = {}
ns.Domain.SpawnRadar = SpawnRadar

-- Heuristic revisit estimates & attribution thresholds (never presented as server respawn truth)
SpawnRadar.KILL_REVISIT_ESTIMATE_SECONDS = 180.0
SpawnRadar.MANUAL_SKIP_REVISIT_SECONDS = 120.0
SpawnRadar.RESPAWN_COOLDOWN_SECONDS = SpawnRadar.KILL_REVISIT_ESTIMATE_SECONDS
SpawnRadar.EMPTY_NODE_SKIP_COOLDOWN_SECONDS = SpawnRadar.MANUAL_SKIP_REVISIT_SECONDS

SpawnRadar.MAX_PULL_ATTRIBUTION_YARDS = 42.0
SpawnRadar.AMBIGUITY_MARGIN_YARDS = 8.0
SpawnRadar.SWITCH_HYSTERESIS_YARDS = 12.0
SpawnRadar.DEDUP_KILL_GUID_WINDOW_SECONDS = 15.0
SpawnRadar.MAX_PULL_STALENESS_SECONDS = 45.0
SpawnRadar.DEFAULT_MACRO_NAME = "FH_Target"
SpawnRadar.MAX_MACRO_BYTES = 255
SpawnRadar.MAX_GLOBAL_MACROS = 120
SpawnRadar.MAX_CHARACTER_MACROS = 18

SpawnRadar.VALID_TERRAIN_ACCESS = {
  walked_verified = true,
  surface_candidate = true,
  unclassified_cave_risk = true,
  excluded_hazard = true,
}

SpawnRadar.VALID_MACRO_SYNC_STATUSES = {
  ["Synced"] = true,
  ["Pending combat"] = true,
  ["Unavailable"] = true,
  ["User modified"] = true,
  ["Missing — click to create"] = true,
  ["Blocked — localized macro exceeds 255 bytes"] = true,
  ["Inactive"] = true,
}

SpawnRadar.macroSyncState = {
  generation = 0,
  pendingCombatGeneration = nil,
  inMutationGuard = false,
  lastStatus = "Inactive",
  lastReason = "no_active_grind",
  lastDesiredSignature = nil,
  lastSyncedBody = nil,
  lastSyncedGeneration = 0,
}

SpawnRadar.state = {
  worldSessionEpoch = 1,
  observationsByLocationID = {}, -- [locationID] = { state = "estimated_recent_kill"|"manually_skipped", expiresAtMono = number, epoch = number }
  recentProcessedKillGUIDs = {}, -- [guid] = observedAtMono
  lastPullObservation = nil,     -- { guid, npcID, npcName, uiMapID, playerX01, playerY01, observedAtMono, epoch }
  lockedStepKey = nil,
  lockedNodeIndex = nil,
  lockedLocationID = nil,
  lastSummary = nil,
}

local function getMonotonicSeconds(overrideNow)
  if type(overrideNow) == "number" and Compat.IsFiniteNumber(overrideNow) then
    return overrideNow
  end
  if ns.State and type(ns.State.overrideMonotonicTime) == "number" then
    return ns.State.overrideMonotonicTime
  end
  if Compat and type(Compat.GetMonotonicSeconds) == "function" then
    local v = Compat.GetMonotonicSeconds()
    if type(v) == "number" and Compat.IsFiniteNumber(v) then
      return v
    end
  end
  if type(_G.GetTime) == "function" then
    local ok, t = pcall(_G.GetTime)
    if ok and type(t) == "number" and Compat.IsFiniteNumber(t) then
      return t
    end
  end
  return 0
end

local function makeStepKey(step)
  if type(step) ~= "table" then
    return "unknown_step"
  end
  return tostring(step.stepID or step.title or "step")
end

local function hasControlCharacters(s)
  if type(s) ~= "string" then
    return true
  end
  return string.find(s, "[%z\1-\31\127]") ~= nil
end

function SpawnRadar.GetLocationID(step, node, fallbackIndex)
  if type(node) == "table" and type(node.locationID) == "string" and node.locationID ~= "" then
    return node.locationID
  end
  local uiMapID = tonumber(step and step.destination and step.destination.uiMapID) or 0
  local npcID = tonumber((node and node.npcID) or (step and step.npcID)) or 0
  local nx = tonumber(node and node.x01) or 0
  local ny = tonumber(node and node.y01) or 0
  if uiMapID > 0 and npcID > 0 and nx > 0 and ny > 0 then
    return string.format(
      "loc:%d:%d:%04d:%04d",
      uiMapID,
      npcID,
      math.floor(nx * 10000 + 0.5),
      math.floor(ny * 10000 + 0.5)
    )
  end
  return string.format("%s#%d", makeStepKey(step), tonumber(fallbackIndex) or 0)
end

function SpawnRadar.ResetSessionState()
  SpawnRadar.state.worldSessionEpoch = 1
  SpawnRadar.state.observationsByLocationID = {}
  SpawnRadar.state.recentProcessedKillGUIDs = {}
  SpawnRadar.state.lastPullObservation = nil
  SpawnRadar.state.lockedStepKey = nil
  SpawnRadar.state.lockedNodeIndex = nil
  SpawnRadar.state.lockedLocationID = nil
  SpawnRadar.state.lastSummary = nil
end

function SpawnRadar.BumpWorldSessionEpoch(reason)
  SpawnRadar.state.worldSessionEpoch = (tonumber(SpawnRadar.state.worldSessionEpoch) or 1) + 1
  SpawnRadar.state.observationsByLocationID = {}
  SpawnRadar.state.recentProcessedKillGUIDs = {}
  SpawnRadar.state.lastPullObservation = nil
  SpawnRadar.state.lockedNodeIndex = nil
  SpawnRadar.state.lockedLocationID = nil
  SpawnRadar.state.lastSummary = nil
  return SpawnRadar.state.worldSessionEpoch, reason
end

function SpawnRadar.ResetCooldowns(reason)
  return SpawnRadar.BumpWorldSessionEpoch(reason or "reset_cooldowns")
end

local function resolveProgress(progress)
  if type(progress) == "table" then
    return progress
  end
  if ns.State and ns.State.GetGoldFarmProgress then
    return ns.State.GetGoldFarmProgress()
  end
  return nil
end

-- Shared fail-closed terrainAccess admission (Astra KI-ARCANE-002 P0-5 & P0-6):
-- - Only `"walked_verified"` and `"surface_candidate"` enter auto-radar by default.
-- - `"unclassified_cave_risk"` enters ONLY on explicit `progress.includeUnwalkedCaveNodes == true`.
-- - `"excluded_hazard"` (elite proximity, blocked approach, crypt/cellar hazard) NEVER enters, even with cave opt-in.
-- - Any unrecognized non-nil `terrainAccess` value fails closed!
function SpawnRadar.IsNodeTerrainAdmitted(step, node, progress)
  progress = resolveProgress(progress)
  local allowCaveRisk = (type(progress) == "table" and progress.includeUnwalkedCaveNodes == true)

  if type(step) == "table" and step.terrainAccess ~= nil then
    if type(step.terrainAccess) ~= "string" or not SpawnRadar.VALID_TERRAIN_ACCESS[step.terrainAccess] then
      return false, "unknown_terrain_access"
    end
    if step.terrainAccess == "excluded_hazard" then
      return false, "excluded_hazard"
    end
  end

  if type(node) == "table" and node.terrainAccess ~= nil then
    if type(node.terrainAccess) ~= "string" or not SpawnRadar.VALID_TERRAIN_ACCESS[node.terrainAccess] then
      return false, "unknown_terrain_access"
    end
    if node.terrainAccess == "excluded_hazard" then
      return false, "excluded_hazard"
    end
  end

  if type(step) == "table" and step.excludeFromAutoRadarUntilWalked == true and not allowCaveRisk then
    return false, "excluded_cave_risk"
  end

  local terrain = (type(node) == "table" and node.terrainAccess)
    or (type(step) == "table" and step.terrainAccess)
    or "surface_candidate"

  if not SpawnRadar.VALID_TERRAIN_ACCESS[terrain] then
    return false, "unknown_terrain_access"
  end
  if terrain == "excluded_hazard" then
    return false, "excluded_hazard"
  end
  if terrain == "unclassified_cave_risk" then
    if allowCaveRisk then
      return true, "unclassified_cave_risk"
    end
    return false, "excluded_cave_risk"
  end
  return true, terrain
end

function SpawnRadar.GetStepNodes(step, progress)
  if type(step) ~= "table" or step.kind ~= "grind" then
    return {}
  end
  progress = resolveProgress(progress)
  local nodes = step.spawnNodes
  if type(nodes) ~= "table" or #nodes < 2 then
    return {}
  end
  local filtered = {}
  for i = 1, #nodes do
    local n = nodes[i]
    if type(n) == "table" then
      local admitted = SpawnRadar.IsNodeTerrainAdmitted(step, n, progress)
      if admitted then
        table.insert(filtered, n)
      end
    end
  end
  if #filtered < 2 then
    return {}
  end
  return filtered
end

function SpawnRadar.IsStepEligible(step, progress)
  return #SpawnRadar.GetStepNodes(step, progress) >= 2
end

function SpawnRadar.IsEnabledForFarm(farm, progress)
  if type(farm) ~= "table" then
    return false
  end
  progress = resolveProgress(progress)
  local mode = (type(progress) == "table" and progress.spawnRadarMode) or "auto"
  if mode == "off" then
    return false
  end
  local hasAnyEligibleStep = false
  for _, st in ipairs(farm.travelSteps or {}) do
    if SpawnRadar.IsStepEligible(st, progress) then
      hasAnyEligibleStep = true
      break
    end
  end
  if not hasAnyEligibleStep then
    return false
  end
  if mode == "on" then
    return true
  end
  return farm.track == "arcane_lvl47_st"
end

function SpawnRadar.GetEffectiveMode(farm, progress)
  progress = resolveProgress(progress)
  local rawMode = (type(progress) == "table" and progress.spawnRadarMode) or "auto"
  if rawMode ~= "on" and rawMode ~= "off" and rawMode ~= "auto" then
    rawMode = "auto"
  end
  return rawMode, SpawnRadar.IsEnabledForFarm(farm, progress)
end

function SpawnRadar.IsActiveForStep(farm, step, progress)
  progress = resolveProgress(progress)
  if type(progress) ~= "table" or progress.mode ~= "standalone" then
    return false
  end
  if not SpawnRadar.IsEnabledForFarm(farm, progress) then
    return false
  end
  return SpawnRadar.IsStepEligible(step, progress)
end

function SpawnRadar.IsActiveForFarm(farm, progress)
  progress = resolveProgress(progress)
  if type(progress) ~= "table" or progress.mode ~= "standalone" then
    return false
  end
  if not SpawnRadar.IsEnabledForFarm(farm, progress) then
    return false
  end
  if type(farm) == "table" and type(progress.currentStepID) == "string" then
    for _, st in ipairs(farm.travelSteps or {}) do
      if st.stepID == progress.currentStepID and st.kind == "grind" then
        return SpawnRadar.IsStepEligible(st, progress)
      end
    end
  end
  return true
end

function SpawnRadar.GetNodeObservationState(step, nodeOrIndex, nowMono, progress)
  nowMono = getMonotonicSeconds(nowMono)
  local node = nil
  local idx = 1
  if type(nodeOrIndex) == "table" then
    node = nodeOrIndex
    idx = tonumber(node.nodeIndex) or 1
  else
    idx = tonumber(nodeOrIndex) or 1
    local rawNodes = type(step) == "table" and step.spawnNodes or nil
    node = type(rawNodes) == "table" and rawNodes[idx] or nil
  end
  if type(node) ~= "table" then
    return "unobserved", 0, nil
  end
  progress = resolveProgress(progress)
  local admitted, rejectReason = SpawnRadar.IsNodeTerrainAdmitted(step, node, progress)
  if not admitted then
    return rejectReason or "excluded_cave_risk", 0, nil
  end

  local locID = SpawnRadar.GetLocationID(step, node, idx)
  local obs = SpawnRadar.state.observationsByLocationID[locID]
  if type(obs) ~= "table" then
    return "unobserved", 0, nil
  end
  if obs.epoch ~= SpawnRadar.state.worldSessionEpoch then
    SpawnRadar.state.observationsByLocationID[locID] = nil
    return "unobserved", 0, nil
  end
  local exp = tonumber(obs.expiresAtMono)
  if not exp or nowMono >= exp then
    SpawnRadar.state.observationsByLocationID[locID] = nil
    return "unobserved", 0, nil
  end
  return tostring(obs.state or "estimated_recent_kill"), (exp - nowMono), obs
end

function SpawnRadar.IsNodeCoolingDown(step, nodeIndex, nowMono, progress)
  local stName, remSec = SpawnRadar.GetNodeObservationState(step, nodeIndex, nowMono, progress)
  if stName == "estimated_recent_kill" or stName == "manually_skipped" then
    return true, remSec, stName
  end
  return false, 0, stName
end

function SpawnRadar.ResolveLocalizedNpcName(npcID, fallbackEnglishName)
  local cleanID = tonumber(npcID)
  local locale = (Compat and type(Compat.GetClientLocale) == "function" and Compat.GetClientLocale()) or "enUS"
  if cleanID and cleanID > 0 then
    if ns.State and type(ns.State.overrideLocalizedNpcNames) == "table" then
      local byLoc = ns.State.overrideLocalizedNpcNames[locale]
      if type(byLoc) == "table" and type(byLoc[cleanID]) == "string" and byLoc[cleanID] ~= "" then
        return byLoc[cleanID]
      end
    end
    if locale ~= "enUS" and locale ~= "enGB" then
      local qdb = _G.QuestieDB
      if type(qdb) == "table" and type(qdb.QueryNPCSingle) == "function" then
        local okQ, locName = pcall(qdb.QueryNPCSingle, cleanID, "name")
        if okQ
          and not (Compat and Compat.IsSecretOrRestrictedValue and Compat.IsSecretOrRestrictedValue(locName))
          and type(locName) == "string"
          and locName ~= ""
        then
          return locName
        end
      end
    end
  end
  return fallbackEnglishName
end

function SpawnRadar.GetTargetMatchSets(farm, step, progress)
  progress = resolveProgress(progress)
  local npcIDSet = {}
  local npcNameSet = {}
  local orderedNames = {}

  local function addNpc(nid, rawName)
    local cleanID = tonumber(nid)
    if cleanID and cleanID > 0 then
      npcIDSet[cleanID] = true
    end
    local nm = SpawnRadar.ResolveLocalizedNpcName(cleanID, rawName)
    if type(rawName) == "string" and rawName ~= "" then
      npcNameSet[rawName] = true
    end
    if type(nm) == "string" and nm ~= "" then
      if not npcNameSet[nm] then
        npcNameSet[nm] = true
      end
      local alreadyOrdered = false
      for _, ex in ipairs(orderedNames) do
        if ex == nm then
          alreadyOrdered = true
          break
        end
      end
      if not alreadyOrdered then
        table.insert(orderedNames, nm)
      end
    end
  end

  -- CRITICAL (P0-1 & KI-ARCANE-002 P1-7): When a grind step defines explicit `spawnNodes`,
  -- derive target species STRICTLY from admitted nodes on `step` (honoring `step.macroTargetOrder`
  -- safe-pull priority across both species names and npcIDs) so excluded cave/hazard species NEVER leak into FH_Target!
  if type(step) == "table" and type(step.spawnNodes) == "table" and #step.spawnNodes > 0 then
    local effectiveProg = progress
    if step.excludeFromAutoRadarUntilWalked == true then
      effectiveProg = { includeUnwalkedCaveNodes = true }
    end
    local admittedNodes = {}
    for i = 1, #step.spawnNodes do
      local n = step.spawnNodes[i]
      if type(n) == "table" and SpawnRadar.IsNodeTerrainAdmitted(step, n, effectiveProg) then
        table.insert(admittedNodes, n)
      end
    end
    if #admittedNodes == 0 then
      return npcIDSet, npcNameSet, orderedNames
    end
    local admittedNameByID = {}
    local admittedIDByName = {}
    for _, node in ipairs(admittedNodes) do
      local nid = tonumber(node.npcID or step.npcID)
      local nm = node.npcName or step.npcName
      if nid and nid > 0 and type(nm) == "string" and nm ~= "" then
        if admittedNameByID[nid] == nil then
          admittedNameByID[nid] = nm
        end
        if admittedIDByName[nm] == nil then
          admittedIDByName[nm] = nid
        end
      end
    end
    if type(step.macroTargetOrder) == "table" then
      for _, prioEntry in ipairs(step.macroTargetOrder) do
        if type(prioEntry) == "string" and admittedIDByName[prioEntry] ~= nil then
          addNpc(admittedIDByName[prioEntry], prioEntry)
        else
          local pid = tonumber(prioEntry)
          if pid and admittedNameByID[pid] ~= nil then
            addNpc(pid, admittedNameByID[pid])
          end
        end
      end
    end
    for _, node in ipairs(admittedNodes) do
      addNpc(node.npcID or step.npcID, node.npcName or step.npcName)
    end
    return npcIDSet, npcNameSet, orderedNames
  end

  if type(step) == "table" then
    addNpc(step.npcID, step.npcName)
  end
  local stepMapID = tonumber(step and step.destination and step.destination.uiMapID) or nil
  if type(farm) == "table" and type(farm.targets) == "table" then
    for _, t in ipairs(farm.targets) do
      if not stepMapID or tonumber(t.uiMapID) == stepMapID then
        addNpc(t.npcID, t.name)
      end
    end
  end

  return npcIDSet, npcNameSet, orderedNames
end

local function computeNodeDistanceYards(uiMapID, ax01, ay01, bx01, by01)
  if not (Compat and type(Compat.GetWorldDistanceYards) == "function") then
    return nil, false
  end
  local d = Compat.GetWorldDistanceYards(uiMapID, ax01, ay01, bx01, by01)
  if type(d) == "table" and d.status == "ok" and type(d.yards) == "number" and Compat.IsFiniteNumber(d.yards) then
    return d.yards, true
  end
  -- CRITICAL (P1-6): Fail closed when world dimensions are unavailable; NEVER fabricate 3200x2133 yards!
  return nil, false
end

local function resolveCurrentPlayerMapPos(playerPos)
  if type(playerPos) == "table" and playerPos.status == "ok" then
    return playerPos
  end
  if Compat and type(Compat.GetPlayerPosition01) == "function" then
    return Compat.GetPlayerPosition01()
  end
  if Compat and type(Compat.GetPlayerMapPosition) == "function" then
    return Compat.GetPlayerMapPosition()
  end
  return nil
end

function SpawnRadar.RecordPullObservation(farm, step, unitObs, playerPos, nowMono)
  nowMono = getMonotonicSeconds(nowMono)
  local npcIDSet, npcNameSet = SpawnRadar.GetTargetMatchSets(farm, step)

  if unitObs == nil and Compat and type(Compat.ObserveUnitForTargetSet) == "function" then
    local probed = Compat.ObserveUnitForTargetSet("target", npcIDSet, npcNameSet)
    if type(probed) == "table" and probed.status == "matched_live_hostile" then
      unitObs = probed
    end
  end

  if type(unitObs) ~= "table" then
    return false, "no_unit_observation"
  end

  local guid = (not Compat.IsSecretOrRestrictedValue(unitObs.guid) and type(unitObs.guid) == "string" and unitObs.guid ~= "")
    and unitObs.guid or nil
  local npcID = tonumber(not Compat.IsSecretOrRestrictedValue(unitObs.npcID) and unitObs.npcID or nil)
  if not npcID and guid and Compat.ExtractCreatureNpcIDFromGUID then
    npcID = Compat.ExtractCreatureNpcIDFromGUID(guid)
  end
  local npcName = (not Compat.IsSecretOrRestrictedValue(unitObs.name or unitObs.npcName) and type(unitObs.name or unitObs.npcName) == "string")
    and (unitObs.name or unitObs.npcName) or nil

  local matchesCamp = (npcID ~= nil and npcIDSet[npcID] == true)
    or (npcName ~= nil and npcNameSet[npcName] == true)
  if not matchesCamp then
    return false, "target_not_in_camp_pool"
  end

  playerPos = resolveCurrentPlayerMapPos(playerPos)
  local pMap = (type(playerPos) == "table" and playerPos.status == "ok") and tonumber(playerPos.uiMapID) or nil
  local px = (type(playerPos) == "table" and playerPos.status == "ok") and tonumber(playerPos.x01) or nil
  local py = (type(playerPos) == "table" and playerPos.status == "ok") and tonumber(playerPos.y01) or nil

  SpawnRadar.state.lastPullObservation = {
    guid = guid,
    npcID = npcID,
    npcName = npcName,
    uiMapID = pMap,
    playerX01 = px,
    playerY01 = py,
    observedAtMono = nowMono,
    epoch = SpawnRadar.state.worldSessionEpoch,
  }
  return true, SpawnRadar.state.lastPullObservation
end

local function pruneOldProcessedGUIDs(nowMono)
  local tbl = SpawnRadar.state.recentProcessedKillGUIDs
  for g, ts in pairs(tbl) do
    if (nowMono - (tonumber(ts) or 0)) > SpawnRadar.DEDUP_KILL_GUID_WINDOW_SECONDS then
      tbl[g] = nil
    end
  end
end

function SpawnRadar.RecordVerifiedKillObservation(farm, step, killEvent, playerPos, nowMono, progress)
  progress = resolveProgress(progress)
  local nodes = SpawnRadar.GetStepNodes(step, progress)
  if #nodes < 2 then
    return { suppressed = 0, reason = "ineligible_step" }
  end
  if type(killEvent) ~= "table" then
    return { suppressed = 0, reason = "missing_kill_identity" }
  end

  local destMap = tonumber(step.destination and step.destination.uiMapID)
  if not destMap then
    return { suppressed = 0, reason = "missing_step_map" }
  end

  nowMono = getMonotonicSeconds(nowMono)
  pruneOldProcessedGUIDs(nowMono)

  local guid = (not Compat.IsSecretOrRestrictedValue(killEvent.guid) and type(killEvent.guid) == "string" and killEvent.guid ~= "")
    and killEvent.guid or nil
  local killNpcID = tonumber(not Compat.IsSecretOrRestrictedValue(killEvent.npcID) and killEvent.npcID or nil)
  if not killNpcID and guid and Compat.ExtractCreatureNpcIDFromGUID then
    killNpcID = Compat.ExtractCreatureNpcIDFromGUID(guid)
  end
  local killName = (not Compat.IsSecretOrRestrictedValue(killEvent.npcName or killEvent.name) and type(killEvent.npcName or killEvent.name) == "string")
    and (killEvent.npcName or killEvent.name) or nil

  if guid and SpawnRadar.state.recentProcessedKillGUIDs[guid] ~= nil then
    return { suppressed = 0, reason = "duplicate_kill_guid", deduplicated = true, guid = guid }
  end

  local npcIDSet, npcNameSet = SpawnRadar.GetTargetMatchSets(farm, step)
  local pull = SpawnRadar.state.lastPullObservation
  local matchedPull = false
  if type(pull) == "table"
    and pull.epoch == SpawnRadar.state.worldSessionEpoch
    and (nowMono - (tonumber(pull.observedAtMono) or 0)) <= SpawnRadar.MAX_PULL_STALENESS_SECONDS
  then
    if guid and pull.guid and guid == pull.guid then
      matchedPull = true
      killNpcID = killNpcID or pull.npcID
      killName = killName or pull.npcName
    elseif not guid and not killNpcID and killName and pull.npcName == killName then
      matchedPull = true
      killNpcID = pull.npcID
    end
  end

  local matchesCamp = (killNpcID ~= nil and npcIDSet[killNpcID] == true)
    or (killName ~= nil and npcNameSet[killName] == true)
  if not matchesCamp then
    return { suppressed = 0, reason = "identity_not_camp_target" }
  end

  if guid then
    SpawnRadar.state.recentProcessedKillGUIDs[guid] = nowMono
  end

  playerPos = resolveCurrentPlayerMapPos(playerPos)
  local refX, refY = nil, nil
  if matchedPull and tonumber(pull.uiMapID) == destMap and pull.playerX01 and pull.playerY01 then
    refX, refY = pull.playerX01, pull.playerY01
  elseif type(playerPos) == "table" and playerPos.status == "ok" and tonumber(playerPos.uiMapID) == destMap then
    refX, refY = tonumber(playerPos.x01), tonumber(playerPos.y01)
  end

  if matchedPull then
    SpawnRadar.state.lastPullObservation = nil
  end

  if not refX or not refY then
    return { suppressed = 0, reason = "off_map_or_unavailable" }
  end

  local bestNode = nil
  local bestLocID = nil
  local bestDist = nil
  local secondDist = nil

  for i, node in ipairs(nodes) do
    local nodeMatchesIdentity = false
    if killNpcID ~= nil then
      nodeMatchesIdentity = (tonumber(node.npcID or step.npcID) == killNpcID)
    elseif killName ~= nil then
      nodeMatchesIdentity = (tostring(node.npcName or step.npcName or "") == killName)
    end
    if nodeMatchesIdentity then
      local obsState = SpawnRadar.GetNodeObservationState(step, node, nowMono, progress)
      if obsState == "unobserved" then
        local yd, distOk = computeNodeDistanceYards(destMap, refX, refY, node.x01, node.y01)
        if not distOk then
          return { suppressed = 0, reason = "distance_unavailable" }
        end
        if yd <= SpawnRadar.MAX_PULL_ATTRIBUTION_YARDS then
          if bestDist == nil or yd < bestDist then
            secondDist = bestDist
            bestDist = yd
            bestNode = node
            bestLocID = SpawnRadar.GetLocationID(step, node, tonumber(node.nodeIndex) or i)
          elseif secondDist == nil or yd < secondDist then
            secondDist = yd
          end
        end
      end
    end
  end

  -- CRITICAL (P1-2 & P1-3): Never bulk-suppress multiple nodes, never suppress ambiguous pairs,
  -- and NEVER fall back to lockedNodeIndex when pull/kill position cannot disambiguate!
  if not bestLocID or not bestNode then
    return { suppressed = 0, reason = "no_candidate_within_pull_range" }
  end
  if secondDist ~= nil and (secondDist - bestDist) < SpawnRadar.AMBIGUITY_MARGIN_YARDS then
    return {
      suppressed = 0,
      reason = "ambiguous_candidate_locations",
      bestDistYards = bestDist,
      secondDistYards = secondDist,
    }
  end

  SpawnRadar.state.observationsByLocationID[bestLocID] = {
    state = "estimated_recent_kill",
    expiresAtMono = nowMono + SpawnRadar.KILL_REVISIT_ESTIMATE_SECONDS,
    epoch = SpawnRadar.state.worldSessionEpoch,
  }
  if SpawnRadar.state.lockedLocationID == bestLocID then
    SpawnRadar.state.lockedLocationID = nil
    SpawnRadar.state.lockedNodeIndex = nil
  end

  return {
    suppressed = 1,
    reason = "single_unambiguous_kill",
    locationID = bestLocID,
    nodeIndex = tonumber(bestNode.nodeIndex) or nil,
    distanceYards = bestDist,
  }
end

function SpawnRadar.RecordKillEvent(farm, step, playerPos, nowMono, killEvent, progress)
  return SpawnRadar.RecordVerifiedKillObservation(farm, step, killEvent, playerPos, nowMono, progress)
end

function SpawnRadar.SkipCurrentLocation(farm, step, nowMono, progress)
  progress = resolveProgress(progress)
  local nodes = SpawnRadar.GetStepNodes(step, progress)
  if #nodes < 2 then
    return { ok = false, reason = "ineligible_step" }
  end
  nowMono = getMonotonicSeconds(nowMono)

  local targetNode = nil
  local targetLocID = SpawnRadar.state.lockedLocationID
  if targetLocID then
    for _, n in ipairs(nodes) do
      if SpawnRadar.GetLocationID(step, n, n.nodeIndex) == targetLocID then
        targetNode = n
        break
      end
    end
  end
  if not targetNode then
    local summary = SpawnRadar.EvaluateNearestNode(farm, step, nil, 0, nowMono, progress)
    if summary and summary.active and summary.locationID then
      targetLocID = summary.locationID
      for _, n in ipairs(nodes) do
        if SpawnRadar.GetLocationID(step, n, n.nodeIndex) == targetLocID then
          targetNode = n
          break
        end
      end
    end
  end
  if not targetLocID or not targetNode then
    return { ok = false, reason = "no_active_location" }
  end

  SpawnRadar.state.observationsByLocationID[targetLocID] = {
    state = "manually_skipped",
    expiresAtMono = nowMono + SpawnRadar.MANUAL_SKIP_REVISIT_SECONDS,
    epoch = SpawnRadar.state.worldSessionEpoch,
  }
  if SpawnRadar.state.lockedLocationID == targetLocID then
    SpawnRadar.state.lockedLocationID = nil
    SpawnRadar.state.lockedNodeIndex = nil
  end
  return {
    ok = true,
    locationID = targetLocID,
    nodeIndex = tonumber(targetNode.nodeIndex) or 1,
    npcName = targetNode.npcName or step.npcName,
    revisitSeconds = SpawnRadar.MANUAL_SKIP_REVISIT_SECONDS,
  }
end

function SpawnRadar.EvaluateNearestNode(farm, step, playerPos, dtSec, nowMono, progress)
  progress = resolveProgress(progress)
  local nodes = SpawnRadar.GetStepNodes(step, progress)
  if #nodes < 2 then
    local excludedReason = (type(step) == "table" and step.excludeFromAutoRadarUntilWalked == true)
      and "excluded_unwalked_cave_risk"
      or "ineligible_step"
    return { active = false, status = excludedReason, reason = excludedReason }
  end

  local destMap = tonumber(step.destination and step.destination.uiMapID)
  local zoneName = tostring((step.destination and step.destination.zoneName) or (farm and farm.zoneName) or "")
  if not destMap then
    return { active = false, status = "missing_step_map", reason = "missing_step_map" }
  end

  nowMono = getMonotonicSeconds(nowMono)
  playerPos = resolveCurrentPlayerMapPos(playerPos)

  local stepKey = makeStepKey(step)
  if SpawnRadar.state.lockedStepKey ~= stepKey then
    SpawnRadar.state.lockedStepKey = stepKey
    SpawnRadar.state.lockedNodeIndex = nil
    SpawnRadar.state.lockedLocationID = nil
  end

  local totalNodes = #nodes
  local unobservedCount = 0
  local suppressedCount = 0
  local soonestNode = nil
  local soonestLocID = nil
  local soonestRemSec = nil

  local sameZone = type(playerPos) == "table"
    and playerPos.status == "ok"
    and tonumber(playerPos.uiMapID) == destMap
    and type(playerPos.x01) == "number"
    and type(playerPos.y01) == "number"

  if sameZone then
    -- Opportunistically refresh live target pull observation while in camp (never suppresses nodes!)
    SpawnRadar.RecordPullObservation(farm, step, nil, playerPos, nowMono)
  end

  local nearestNode = nil
  local nearestLocID = nil
  local nearestYards = nil
  local lockedNode = nil
  local lockedYards = nil

  for i, node in ipairs(nodes) do
    local locID = SpawnRadar.GetLocationID(step, node, tonumber(node.nodeIndex) or i)
    local obsState, remSec = SpawnRadar.GetNodeObservationState(step, node, nowMono, progress)
    if obsState == "unobserved" then
      unobservedCount = unobservedCount + 1
      if sameZone then
        local yd, distOk = computeNodeDistanceYards(destMap, playerPos.x01, playerPos.y01, node.x01, node.y01)
        if not distOk then
          local unavailSummary = {
            active = true,
            status = "distance_unavailable",
            zoneStatus = "in_zone",
            distanceAvailable = false,
            uiMapID = destMap,
            node = node,
            nodeIndex = tonumber(node.nodeIndex) or i,
            locationID = locID,
            npcID = tonumber(node.npcID or step.npcID) or nil,
            npcName = tostring(node.npcName or step.npcName or "Target"),
            x01 = node.x01,
            y01 = node.y01,
            distanceYards = nil,
            allCoolingDown = false,
            allSuppressed = false,
            readyInSec = 0,
            readyInSeconds = 0,
            nextRevisitInSec = 0,
            readyCount = unobservedCount,
            unobservedCount = unobservedCount,
            coolingCount = suppressedCount,
            suppressedCount = suppressedCount,
            totalCount = totalNodes,
            targetDestination = step.destination,
          }
          SpawnRadar.state.lastSummary = unavailSummary
          return unavailSummary
        end
        if nearestYards == nil or yd < nearestYards then
          nearestYards = yd
          nearestNode = node
          nearestLocID = locID
        end
        if locID == SpawnRadar.state.lockedLocationID then
          lockedNode = node
          lockedYards = yd
        end
      else
        if nearestNode == nil then
          nearestNode = node
          nearestLocID = locID
        end
      end
    else
      suppressedCount = suppressedCount + 1
      if soonestRemSec == nil or remSec < soonestRemSec then
        soonestRemSec = remSec
        soonestNode = node
        soonestLocID = locID
      end
    end
  end

  local chosenNode = nil
  local chosenLocID = nil
  local chosenYards = nil
  local allSuppressed = false
  local nextRevisitInSec = 0

  local inCombat = (ns.Compat and ns.Compat.IsInCombat and ns.Compat.IsInCombat()) == true

  if nearestNode and nearestLocID then
    if sameZone and lockedNode and lockedYards ~= nil and nearestYards ~= nil and SpawnRadar.state.lockedLocationID ~= nearestLocID then
      if inCombat or (lockedYards - nearestYards) < SpawnRadar.SWITCH_HYSTERESIS_YARDS then
        chosenNode = lockedNode
        chosenLocID = SpawnRadar.state.lockedLocationID
        chosenYards = lockedYards
      else
        chosenNode = nearestNode
        chosenLocID = nearestLocID
        chosenYards = nearestYards
      end
    else
      chosenNode = nearestNode
      chosenLocID = nearestLocID
      chosenYards = nearestYards
    end
    SpawnRadar.state.lockedLocationID = chosenLocID
    SpawnRadar.state.lockedNodeIndex = tonumber(chosenNode.nodeIndex) or 1
  else
    allSuppressed = true
    chosenNode = soonestNode or nodes[1]
    chosenLocID = soonestLocID or SpawnRadar.GetLocationID(step, chosenNode, 1)
    nextRevisitInSec = math.max(1, math.ceil(soonestRemSec or 1))
    if sameZone and chosenNode then
      local yd, distOk = computeNodeDistanceYards(destMap, playerPos.x01, playerPos.y01, chosenNode.x01, chosenNode.y01)
      if distOk then
        chosenYards = yd
      end
    end
    SpawnRadar.state.lockedLocationID = chosenLocID
    SpawnRadar.state.lockedNodeIndex = tonumber(chosenNode and chosenNode.nodeIndex) or 1
  end

  local chosenIdx = tonumber(chosenNode.nodeIndex) or 1
  local npcName = tostring(chosenNode.npcName or step.npcName or "Target")

  local summary = {
    active = true,
    status = "ok",
    zoneStatus = sameZone and "in_zone" or "off_zone",
    distanceAvailable = sameZone,
    uiMapID = destMap,
    node = chosenNode,
    nodeIndex = chosenIdx,
    locationID = chosenLocID,
    npcID = tonumber(chosenNode.npcID or step.npcID) or nil,
    npcName = npcName,
    x01 = chosenNode.x01,
    y01 = chosenNode.y01,
    distanceYards = chosenYards,
    allCoolingDown = allSuppressed,
    allSuppressed = allSuppressed,
    readyInSec = nextRevisitInSec,
    readyInSeconds = nextRevisitInSec,
    nextRevisitInSec = nextRevisitInSec,
    readyCount = unobservedCount,
    unobservedCount = unobservedCount,
    coolingCount = suppressedCount,
    suppressedCount = suppressedCount,
    totalCount = totalNodes,
    targetDestination = {
      uiMapID = destMap,
      zoneName = zoneName,
      x01 = chosenNode.x01,
      y01 = chosenNode.y01,
      coordinateSpace = "uiMap01",
    },
  }
  SpawnRadar.state.lastSummary = summary
  return summary
end

function SpawnRadar.GetNodeStatesForStep(farm, step, nowMono, progress)
  progress = resolveProgress(progress)
  nowMono = getMonotonicSeconds(nowMono)
  local nodes = SpawnRadar.GetStepNodes(step, progress)
  local out = {}
  for i, node in ipairs(nodes) do
    local nodeIdx = tonumber(node.nodeIndex) or i
    local locID = SpawnRadar.GetLocationID(step, node, nodeIdx)
    local obsState, remSec = SpawnRadar.GetNodeObservationState(step, node, nowMono, progress)
    local isCooling = (obsState == "estimated_recent_kill" or obsState == "manually_skipped")
    local isLocked = (SpawnRadar.state.lockedLocationID ~= nil and SpawnRadar.state.lockedLocationID == locID)
    table.insert(out, {
      nodeIndex = nodeIdx,
      locationID = locID,
      npcID = tonumber(node.npcID or step.npcID) or nil,
      npcName = tostring(node.npcName or step.npcName or "Mob"),
      x01 = node.x01,
      y01 = node.y01,
      terrainAccess = tostring(node.terrainAccess or "surface_candidate"),
      status = isCooling and "cooldown" or "unobserved",
      observationState = obsState,
      isCoolingDown = isCooling,
      remainingSeconds = isCooling and math.max(1, math.ceil(remSec or 1)) or 0,
      isLockedTarget = isLocked,
    })
  end
  return out
end

function SpawnRadar.BuildTargetMacroBody(farm, step, progress)
  local _, _, orderedNames = SpawnRadar.GetTargetMatchSets(farm, step, progress)
  if #orderedNames == 0 then
    return nil, {
      ok = false,
      reason = "empty_targets",
      byteLength = 0,
      speciesCount = 0,
    }
  end

  local lines = {}
  for _, nm in ipairs(orderedNames) do
    if hasControlCharacters(nm) then
      return nil, {
        ok = false,
        reason = "control_char_in_name",
        invalidName = nm,
        byteLength = 0,
        speciesCount = #orderedNames,
      }
    end
    table.insert(lines, "/stopmacro [harm,nodead]")
    table.insert(lines, "/cleartarget")
    table.insert(lines, "/targetexact " .. nm)
  end
  table.insert(lines, "/cleartarget [noharm][dead]")

  local body = table.concat(lines, "\n")
  local byteLen = #body
  if byteLen > SpawnRadar.MAX_MACRO_BYTES then
    return nil, {
      ok = false,
      reason = "macro_overflow",
      byteLength = byteLen,
      maxBytes = SpawnRadar.MAX_MACRO_BYTES,
      speciesCount = #orderedNames,
    }
  end

  return body, {
    ok = true,
    byteLength = byteLen,
    speciesCount = #orderedNames,
    speciesNames = orderedNames,
  }
end

local function getMacroSyncScopeStore(scope, createIfMissing)
  local rootDB = (scope == "character") and _G.ForeverHubCharDB or _G.ForeverHubDB
  if type(rootDB) ~= "table" then
    if not createIfMissing then
      return nil
    end
    if scope == "character" then
      _G.ForeverHubCharDB = {}
      rootDB = _G.ForeverHubCharDB
    else
      _G.ForeverHubDB = {}
      rootDB = _G.ForeverHubDB
    end
  end
  if type(rootDB.macroSync) ~= "table" then
    if not createIfMissing then
      return nil
    end
    rootDB.macroSync = {}
  end
  return rootDB.macroSync
end

local function getMacroOwnershipRecord(macroName, scope)
  local store = getMacroSyncScopeStore(scope, false)
  local rec = store and store[macroName] or nil
  if type(rec) ~= "table" then
    return nil
  end
  if rec.scope ~= scope then
    return nil
  end
  return rec
end

local function saveMacroOwnershipRecord(macroName, scope, slotIndex, writtenBody, locale, autoSyncOptIn)
  local store = getMacroSyncScopeStore(scope, true)
  if not store then
    return nil
  end
  local nowWall = (type(time) == "function" and time()) or 0
  store[macroName] = {
    autoSyncOptIn = (autoSyncOptIn ~= false),
    scope = scope,
    slotIndex = slotIndex,
    lastWrittenBody = writtenBody,
    locale = locale or "enUS",
    userModifiedDetected = false,
    updatedAt = nowWall,
  }
  return store[macroName]
end

local function scanMacroSlotsByName(macroName)
  local getInfo = _G.GetMacroInfo
  local getIdx = _G.GetMacroIndexByName
  local getNum = _G.GetNumMacros
  if type(getInfo) ~= "function" and type(getIdx) ~= "function" then
    return { ok = false, reason = "macro_api_unavailable" }
  end
  if type(getInfo) ~= "function" then
    return { ok = false, reason = "macro_api_unavailable" }
  end

  local matches = {}
  local seenSlots = {}
  local acctCount = nil
  local charCount = nil

  local function inspectSlot(slotIdx)
    if seenSlots[slotIdx] then
      return true, nil
    end
    local okInfo, mName, _, mBody = pcall(getInfo, slotIdx)
    if not okInfo then
      return false, "macro_inspection_unavailable"
    end
    if Compat.IsSecretOrRestrictedValue(mName) or Compat.IsSecretOrRestrictedValue(mBody) then
      return false, "macro_inspection_unavailable"
    end
    if mName == macroName then
      if type(mBody) ~= "string" then
        return false, "macro_inspection_unavailable"
      end
      seenSlots[slotIdx] = true
      table.insert(matches, {
        slotIndex = slotIdx,
        scope = (slotIdx <= SpawnRadar.MAX_GLOBAL_MACROS) and "global" or "character",
        name = mName,
        body = mBody,
      })
    end
    return true, nil
  end

  if type(getNum) == "function" then
    local okNum, rawGlobal, rawChar = pcall(getNum)
    if not okNum
      or Compat.IsSecretOrRestrictedValue(rawGlobal)
      or Compat.IsSecretOrRestrictedValue(rawChar)
      or type(rawGlobal) ~= "number"
    then
      return { ok = false, reason = "macro_count_unavailable" }
    end
    acctCount = math.min(SpawnRadar.MAX_GLOBAL_MACROS, math.max(0, math.floor(rawGlobal)))
    charCount = math.min(SpawnRadar.MAX_CHARACTER_MACROS, math.max(0, math.floor(tonumber(rawChar) or 0)))

    for slot = 1, acctCount do
      local okSlot, errSlot = inspectSlot(slot)
      if not okSlot then
        return { ok = false, reason = errSlot }
      end
    end
    for slot = SpawnRadar.MAX_GLOBAL_MACROS + 1, SpawnRadar.MAX_GLOBAL_MACROS + charCount do
      local okSlot, errSlot = inspectSlot(slot)
      if not okSlot then
        return { ok = false, reason = errSlot }
      end
    end
  end

  if type(getIdx) == "function" then
    local okIdx, existingIdx = pcall(getIdx, macroName)
    if not okIdx or Compat.IsSecretOrRestrictedValue(existingIdx) then
      return { ok = false, reason = "macro_lookup_failed" }
    end
    local parsedIdx = tonumber(existingIdx) or 0
    if parsedIdx > 0 and not seenSlots[parsedIdx] then
      local okSlot, errSlot = inspectSlot(parsedIdx)
      if not okSlot then
        return { ok = false, reason = errSlot }
      end
    end
  elseif type(getNum) ~= "function" then
    return { ok = false, reason = "macro_api_unavailable" }
  end

  if #matches > 1 then
    return {
      ok = false,
      reason = "duplicate_macro_scope_conflict",
      matches = matches,
    }
  end

  return {
    ok = true,
    match = matches[1] or nil,
    acctCount = acctCount,
    charCount = charCount,
  }
end

local function computeLiveDesiredMacroIntent()
  local gProg = ns.State and ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress() or nil
  if type(gProg) ~= "table" or gProg.mode == "paused" or not gProg.selectedFarmID then
    return { active = false, reason = "no_active_grind" }
  end
  local GF = ns.Domain and ns.Domain.GoldFarms
  if not GF or type(GF.Evaluate) ~= "function" then
    return { active = false, reason = "gold_farms_unavailable" }
  end
  local eval = GF.Evaluate(nil, gProg)
  local farm = eval and eval.farm or nil
  if type(farm) ~= "table" then
    return { active = false, reason = "farm_not_found" }
  end
  local grindStep = nil
  if eval.activeStep and eval.activeStep.kind == "grind" and SpawnRadar.IsStepEligible(eval.activeStep, gProg) then
    grindStep = eval.activeStep
  else
    for _, st in ipairs(farm.travelSteps or {}) do
      if st.kind == "grind" and SpawnRadar.IsStepEligible(st, gProg) then
        grindStep = st
        break
      end
    end
  end
  if not grindStep then
    return { active = false, reason = "no_eligible_grind_step" }
  end

  local curLocale = (Compat and type(Compat.GetClientLocale) == "function" and Compat.GetClientLocale()) or "enUS"
  local body, meta = SpawnRadar.BuildTargetMacroBody(farm, grindStep, gProg)
  local sig = string.format(
    "%s|%s|%s|%s",
    tostring(farm.farmID),
    tostring(grindStep.stepID),
    tostring(curLocale),
    tostring(body or (meta and meta.reason) or "invalid")
  )
  local ms = SpawnRadar.macroSyncState
  if ms.lastDesiredSignature ~= sig then
    ms.generation = (tonumber(ms.generation) or 0) + 1
    ms.lastDesiredSignature = sig
  end
  return {
    active = true,
    generation = ms.generation,
    farm = farm,
    step = grindStep,
    progress = gProg,
    locale = curLocale,
    body = body,
    meta = meta,
    signature = sig,
  }
end

local function setMacroStatus(statusLabel, reason)
  if not SpawnRadar.VALID_MACRO_SYNC_STATUSES[statusLabel] then
    statusLabel = "Unavailable"
  end
  SpawnRadar.macroSyncState.lastStatus = statusLabel
  SpawnRadar.macroSyncState.lastReason = reason
  return statusLabel
end

-- Strictly read-only status inspection (safe for UI render & UPDATE_MACROS; NEVER mutates macros!)
function SpawnRadar.InspectMacroSyncStatus()
  if SpawnRadar.macroSyncState.inMutationGuard then
    return SpawnRadar.macroSyncState.lastStatus, SpawnRadar.macroSyncState.lastReason
  end
  local intent = computeLiveDesiredMacroIntent()
  if not intent.active then
    SpawnRadar.macroSyncState.pendingCombatGeneration = nil
    return setMacroStatus("Inactive", intent.reason or "no_active_grind"), intent.reason
  end

  local macroName = SpawnRadar.DEFAULT_MACRO_NAME
  local scan = scanMacroSlotsByName(macroName)
  if not scan.ok then
    return setMacroStatus("Unavailable", scan.reason), scan.reason
  end
  local m = scan.match
  if not m then
    return setMacroStatus("Missing — click to create", "macro_missing"), "macro_missing"
  end

  local rec = getMacroOwnershipRecord(macroName, m.scope)
  if not rec or type(rec.lastWrittenBody) ~= "string" then
    return setMacroStatus("Unavailable", "macro_name_collision"), "macro_name_collision"
  end
  if m.body ~= rec.lastWrittenBody then
    rec.userModifiedDetected = true
    return setMacroStatus("User modified", "user_modified"), "user_modified"
  end
  if rec.autoSyncOptIn ~= true then
    return setMacroStatus("Unavailable", "autosync_disabled"), "autosync_disabled"
  end
  if not intent.meta or intent.meta.ok ~= true then
    if intent.meta and intent.meta.reason == "macro_overflow" then
      return setMacroStatus("Blocked — localized macro exceeds 255 bytes", "macro_overflow"), "macro_overflow"
    end
    return setMacroStatus("Unavailable", (intent.meta and intent.meta.reason) or "invalid_macro_body"),
      (intent.meta and intent.meta.reason) or "invalid_macro_body"
  end
  if m.body == intent.body then
    return setMacroStatus("Synced", "already_synced"), "already_synced"
  end

  local lock = (Compat and type(Compat.GetCombatLockdownState) == "function")
    and Compat.GetCombatLockdownState()
    or { ok = false, locked = true, reason = "lockdown_probe_missing" }
  if not lock.ok then
    return setMacroStatus("Unavailable", lock.reason or "lockdown_probe_unavailable"), lock.reason
  end
  if lock.locked == true or SpawnRadar.macroSyncState.pendingCombatGeneration ~= nil then
    return setMacroStatus("Pending combat", "combat_lockdown"), "combat_lockdown"
  end
  return setMacroStatus("Unavailable", "unsynced"), "unsynced"
end

function SpawnRadar.GetMacroSyncStatus()
  local status, reason = SpawnRadar.InspectMacroSyncStatus()
  return {
    status = status,
    reason = reason,
    generation = SpawnRadar.macroSyncState.generation,
    pendingCombat = (SpawnRadar.macroSyncState.pendingCombatGeneration ~= nil),
    macroName = SpawnRadar.DEFAULT_MACRO_NAME,
  }
end

-- Explicit user-initiated macro creation / update / adoption ONLY (Astra KI-ARCANE-002 P0-1, P0-2, P0-4):
-- NEVER called automatically during route navigation, event reconciliation, or UI rendering.
function SpawnRadar.CreateOrAdoptTargetMacro(farm, step, opts)
  opts = type(opts) == "table" and opts or {}
  local preferredScope = (opts.scope == "character") and "character" or "global"
  local forceAdopt = (opts.forceAdopt == true)
  local macroName = SpawnRadar.DEFAULT_MACRO_NAME

  local lock = (Compat and type(Compat.GetCombatLockdownState) == "function")
    and Compat.GetCombatLockdownState()
    or { ok = false, locked = true, reason = "lockdown_probe_missing" }

  local body, meta = SpawnRadar.BuildTargetMacroBody(farm, step, opts.progress)
  if lock.ok ~= true or lock.locked ~= false then
    local lReason = (lock.ok ~= true) and (lock.reason or "lockdown_probe_unavailable") or "combat_lockdown"
    setMacroStatus((lock.ok == true and lock.locked == true) and "Pending combat" or "Unavailable", lReason)
    return {
      ok = false,
      reason = lReason,
      status = SpawnRadar.macroSyncState.lastStatus,
      body = body,
    }
  end
  if not meta or meta.ok ~= true or type(body) ~= "string" then
    local bReason = (meta and meta.reason) or "invalid_macro_body"
    setMacroStatus(bReason == "macro_overflow" and "Blocked — localized macro exceeds 255 bytes" or "Unavailable", bReason)
    return {
      ok = false,
      reason = bReason,
      status = SpawnRadar.macroSyncState.lastStatus,
      byteLength = meta and meta.byteLength or nil,
    }
  end

  local getIdx = _G.GetMacroIndexByName
  local getInfo = _G.GetMacroInfo
  local createMacro = _G.CreateMacro
  local editMacro = _G.EditMacro
  if type(getInfo) ~= "function"
    or type(createMacro) ~= "function"
    or type(editMacro) ~= "function"
    or (type(getIdx) ~= "function" and type(_G.GetNumMacros) ~= "function")
  then
    setMacroStatus("Unavailable", "macro_api_unavailable")
    return {
      ok = false,
      reason = "macro_api_unavailable",
      status = "Unavailable",
      macroName = macroName,
      body = body,
    }
  end

  local scan = scanMacroSlotsByName(macroName)
  if not scan.ok then
    setMacroStatus("Unavailable", scan.reason)
    return {
      ok = false,
      reason = scan.reason,
      status = "Unavailable",
      macroName = macroName,
      body = body,
    }
  end

  local curLocale = (Compat and type(Compat.GetClientLocale) == "function" and Compat.GetClientLocale()) or "enUS"
  local action = nil
  local targetIdx = 0
  local targetScope = preferredScope

  if scan.match ~= nil then
    local m = scan.match
    targetScope = m.scope
    local rec = getMacroOwnershipRecord(macroName, m.scope)
    local provenOwned = (rec ~= nil and type(rec.lastWrittenBody) == "string" and m.body == rec.lastWrittenBody)
    if not provenOwned and not forceAdopt then
      if rec ~= nil and type(rec.lastWrittenBody) == "string" and m.body ~= rec.lastWrittenBody then
        rec.userModifiedDetected = true
        setMacroStatus("User modified", "user_modified")
        return {
          ok = false,
          reason = "user_modified",
          status = "User modified",
          macroName = macroName,
        }
      end
      setMacroStatus("Unavailable", "macro_name_collision")
      return {
        ok = false,
        reason = "macro_name_collision",
        status = "Unavailable",
        macroName = macroName,
      }
    end

    SpawnRadar.macroSyncState.inMutationGuard = true
    local okEdit, editedIdx = pcall(editMacro, m.slotIndex, macroName, "INV_Misc_QuestionMark", body)
    SpawnRadar.macroSyncState.inMutationGuard = false
    if not okEdit then
      setMacroStatus("Unavailable", "edit_macro_failed")
      return {
        ok = false,
        reason = "edit_macro_failed",
        status = "Unavailable",
        macroName = macroName,
        body = body,
      }
    end
    targetIdx = tonumber(editedIdx) or m.slotIndex
    action = forceAdopt and not provenOwned and "adopted" or "updated"
  else
    if type(_G.GetNumMacros) ~= "function" then
      setMacroStatus("Unavailable", "macro_count_unavailable")
      return {
        ok = false,
        reason = "macro_count_unavailable",
        status = "Unavailable",
        macroName = macroName,
        body = body,
      }
    end
    local acctCount = scan.acctCount
    local charCount = scan.charCount
    if acctCount == nil then
      local okNum, gCount, cCount = pcall(_G.GetNumMacros)
      if not okNum
        or Compat.IsSecretOrRestrictedValue(gCount)
        or Compat.IsSecretOrRestrictedValue(cCount)
        or type(gCount) ~= "number"
      then
        setMacroStatus("Unavailable", "macro_count_unavailable")
        return {
          ok = false,
          reason = "macro_count_unavailable",
          status = "Unavailable",
          macroName = macroName,
          body = body,
        }
      end
      acctCount = math.floor(gCount)
      charCount = math.floor(tonumber(cCount) or 0)
    end
    if preferredScope == "character" then
      if charCount >= SpawnRadar.MAX_CHARACTER_MACROS then
        setMacroStatus("Unavailable", "macro_slots_full")
        return {
          ok = false,
          reason = "macro_slots_full",
          status = "Unavailable",
          macroName = macroName,
          body = body,
        }
      end
    else
      if acctCount >= SpawnRadar.MAX_GLOBAL_MACROS then
        setMacroStatus("Unavailable", "macro_slots_full")
        return {
          ok = false,
          reason = "macro_slots_full",
          status = "Unavailable",
          macroName = macroName,
          body = body,
        }
      end
    end

    local perCharArg = (preferredScope == "character") and 1 or nil
    SpawnRadar.macroSyncState.inMutationGuard = true
    local okCreate, newIdx = pcall(createMacro, macroName, "INV_Misc_QuestionMark", body, perCharArg)
    SpawnRadar.macroSyncState.inMutationGuard = false
    if not okCreate or not newIdx then
      setMacroStatus("Unavailable", "create_macro_failed")
      return {
        ok = false,
        reason = "create_macro_failed",
        status = "Unavailable",
        macroName = macroName,
        body = body,
      }
    end
    targetIdx = tonumber(newIdx) or 0
    action = "created"
  end

  local verifyIdx = targetIdx
  if (not verifyIdx or verifyIdx <= 0) and type(getIdx) == "function" then
    local okReIdx, reIdx = pcall(getIdx, macroName)
    local parsedIdx = (okReIdx and not Compat.IsSecretOrRestrictedValue(reIdx)) and tonumber(reIdx) or nil
    if parsedIdx and parsedIdx > 0 then
      verifyIdx = parsedIdx
    end
  end
  if not verifyIdx or verifyIdx <= 0 then
    setMacroStatus("Unavailable", "macro_readback_missing")
    return {
      ok = false,
      reason = "macro_readback_missing",
      status = "Unavailable",
      macroName = macroName,
      body = body,
    }
  end

  local okVerify, rbName, _, rbBody = pcall(getInfo, verifyIdx)
  if not okVerify
    or Compat.IsSecretOrRestrictedValue(rbName)
    or Compat.IsSecretOrRestrictedValue(rbBody)
    or rbName ~= macroName
    or rbBody ~= body
  then
    setMacroStatus("Unavailable", "macro_readback_mismatch")
    return {
      ok = false,
      reason = "macro_readback_mismatch",
      status = "Unavailable",
      macroName = macroName,
      body = body,
    }
  end

  local actualScope = (verifyIdx <= SpawnRadar.MAX_GLOBAL_MACROS) and "global" or "character"
  saveMacroOwnershipRecord(macroName, actualScope, verifyIdx, body, curLocale, true)
  SpawnRadar.macroSyncState.pendingCombatGeneration = nil
  SpawnRadar.macroSyncState.lastSyncedBody = body
  setMacroStatus("Synced", action)

  return {
    ok = true,
    action = action,
    scope = actualScope,
    status = "Synced",
    macroIndex = verifyIdx,
    macroName = macroName,
    byteLength = #body,
    body = body,
  }
end

function SpawnRadar.EnsureTargetMacro(farm, step, opts)
  return SpawnRadar.CreateOrAdoptTargetMacro(farm, step, opts)
end

-- Automatic single-intent synchronizer for already-owned `FH_Target` (Astra KI-ARCANE-002 P0-1..P0-4, P0-7):
-- - NEVER calls `CreateMacro` (even if macro was deleted or missing).
-- - Requires explicit `autoSyncOptIn == true` AND exact `currentBody == lastWrittenBody` in matching scope DB.
-- - Coalesces combat route transitions (`A -> B -> C` writes ONLY `C`; `A -> Stop` writes NOTHING).
-- - Guarded against `UPDATE_MACROS` edit loops and verifies post-write readback parity before reporting `Synced`.
function SpawnRadar.SyncExistingOwnedTargetMacro(triggerReason)
  local ms = SpawnRadar.macroSyncState
  if ms.inMutationGuard then
    return { ok = false, reason = "reentrant_guarded", status = ms.lastStatus }
  end

  local intent = computeLiveDesiredMacroIntent()
  if not intent.active then
    ms.pendingCombatGeneration = nil
    local st = setMacroStatus("Inactive", intent.reason or "no_active_grind")
    return { ok = true, action = "noop_inactive", status = st, reason = intent.reason }
  end

  local macroName = SpawnRadar.DEFAULT_MACRO_NAME
  local scan = scanMacroSlotsByName(macroName)
  if not scan.ok then
    ms.pendingCombatGeneration = nil
    local st = setMacroStatus("Unavailable", scan.reason)
    return { ok = false, status = st, reason = scan.reason }
  end

  local m = scan.match
  if not m then
    ms.pendingCombatGeneration = nil
    local st = setMacroStatus("Missing — click to create", "macro_missing")
    return { ok = false, status = st, reason = "macro_missing" }
  end

  local rec = getMacroOwnershipRecord(macroName, m.scope)
  if not rec or type(rec.lastWrittenBody) ~= "string" then
    ms.pendingCombatGeneration = nil
    local st = setMacroStatus("Unavailable", "macro_name_collision")
    return { ok = false, status = st, reason = "macro_name_collision" }
  end

  if m.body ~= rec.lastWrittenBody then
    rec.userModifiedDetected = true
    ms.pendingCombatGeneration = nil
    local st = setMacroStatus("User modified", "user_modified")
    return { ok = false, status = st, reason = "user_modified" }
  end

  if rec.autoSyncOptIn ~= true then
    ms.pendingCombatGeneration = nil
    local st = setMacroStatus("Unavailable", "autosync_disabled")
    return { ok = false, status = st, reason = "autosync_disabled" }
  end

  if not intent.meta or intent.meta.ok ~= true or type(intent.body) ~= "string" then
    ms.pendingCombatGeneration = nil
    local bReason = (intent.meta and intent.meta.reason) or "invalid_macro_body"
    local st = setMacroStatus(
      bReason == "macro_overflow" and "Blocked — localized macro exceeds 255 bytes" or "Unavailable",
      bReason
    )
    return { ok = false, status = st, reason = bReason, byteLength = intent.meta and intent.meta.byteLength or nil }
  end

  if m.body == intent.body then
    ms.pendingCombatGeneration = nil
    rec.slotIndex = m.slotIndex
    rec.locale = intent.locale
    local st = setMacroStatus("Synced", "already_synced")
    return {
      ok = true,
      action = "noop_already_synced",
      status = st,
      scope = m.scope,
      macroIndex = m.slotIndex,
      byteLength = #intent.body,
      body = intent.body,
    }
  end

  local lock = (Compat and type(Compat.GetCombatLockdownState) == "function")
    and Compat.GetCombatLockdownState()
    or { ok = false, locked = true, reason = "lockdown_probe_missing" }
  if lock.ok ~= true then
    local lReason = lock.reason or "lockdown_probe_unavailable"
    local st = setMacroStatus("Unavailable", lReason)
    return { ok = false, status = st, reason = lReason }
  end
  if lock.locked ~= false then
    ms.pendingCombatGeneration = intent.generation
    local st = setMacroStatus("Pending combat", "combat_lockdown")
    return {
      ok = false,
      status = st,
      reason = "combat_lockdown",
      generation = intent.generation,
      triggerReason = triggerReason,
    }
  end

  local editMacro = _G.EditMacro
  local getInfo = _G.GetMacroInfo
  if type(editMacro) ~= "function" or type(getInfo) ~= "function" then
    local st = setMacroStatus("Unavailable", "macro_api_unavailable")
    return { ok = false, status = st, reason = "macro_api_unavailable" }
  end

  ms.inMutationGuard = true
  local okEdit, editedIdx = pcall(editMacro, m.slotIndex, macroName, "INV_Misc_QuestionMark", intent.body)
  ms.inMutationGuard = false
  ms.pendingCombatGeneration = nil

  if not okEdit then
    local st = setMacroStatus("Unavailable", "edit_macro_failed")
    return { ok = false, status = st, reason = "edit_macro_failed" }
  end

  local verifyIdx = tonumber(editedIdx) or m.slotIndex
  local okVerify, rbName, _, rbBody = pcall(getInfo, verifyIdx)
  if not okVerify
    or Compat.IsSecretOrRestrictedValue(rbName)
    or Compat.IsSecretOrRestrictedValue(rbBody)
    or rbName ~= macroName
    or rbBody ~= intent.body
  then
    local st = setMacroStatus("Unavailable", "macro_readback_mismatch")
    return { ok = false, status = st, reason = "macro_readback_mismatch" }
  end

  saveMacroOwnershipRecord(macroName, m.scope, verifyIdx, intent.body, intent.locale, true)
  ms.lastSyncedBody = intent.body
  ms.lastSyncedGeneration = intent.generation
  local st = setMacroStatus("Synced", "updated")
  return {
    ok = true,
    action = "updated",
    status = st,
    scope = m.scope,
    macroIndex = verifyIdx,
    byteLength = #intent.body,
    body = intent.body,
  }
end

function SpawnRadar.FlushPendingMacroSync()
  if SpawnRadar.macroSyncState.pendingCombatGeneration == nil then
    return nil
  end
  return SpawnRadar.SyncExistingOwnedTargetMacro("PLAYER_REGEN_ENABLED")
end

return SpawnRadar
