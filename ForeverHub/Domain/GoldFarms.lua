local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.Domain = ns.Domain or {}

local GoldFarms = {}
ns.Domain.GoldFarms = GoldFarms

local MIN_GPH_SAMPLE_SECONDS = 180 -- 3 minutes minimum before extrapolating hourly cash-flow rate

local VALID_STEP_KINDS = {
  travel = true,
  boat_crossing = true,
  boat_disembark = true,
  vendor = true,
  grind = true,
}

function GoldFarms.GetPublicationState(farm)
  if type(farm) == "table" and type(farm.certification) == "table" and type(farm.certification.publicationState) == "string" then
    return farm.certification.publicationState
  end
  return "traversal_verified"
end

function GoldFarms.GetPrimaryActionLabel(farm)
  if type(farm) == "table" and farm.track == "arcane_lvl47_st" then
    return "Start route"
  end
  local pub = GoldFarms.GetPublicationState(farm)
  if pub == "source_verified" then
    return "Show direction"
  end
  local steps = type(farm) == "table" and farm.travelSteps or nil
  if type(steps) == "table" and #steps <= 1 then
    return "Show direction"
  end
  return "Start route"
end

local function lookupRouteByID(catalog, farmID)
  if type(catalog) ~= "table" or not farmID then
    return nil
  end
  if type(catalog.farmsByID) == "table" and catalog.farmsByID[farmID] then
    return catalog.farmsByID[farmID]
  end
  if type(catalog.arcaneGrindFarmsByID) == "table" and catalog.arcaneGrindFarmsByID[farmID] then
    return catalog.arcaneGrindFarmsByID[farmID]
  end
  if type(catalog.experimentalArcaneFarmsByID) == "table" and catalog.experimentalArcaneFarmsByID[farmID] then
    return catalog.experimentalArcaneFarmsByID[farmID]
  end
  if type(catalog.expandedRoutesByID) == "table" and catalog.expandedRoutesByID[farmID] then
    return catalog.expandedRoutesByID[farmID]
  end
  return nil
end

local MATERIAL_NAMES_FALLBACK = {
  [4234] = "Heavy Leather",
  [4304] = "Thick Leather",
  [4306] = "Silk Cloth",
  [4338] = "Mageweave Cloth",
  [7068] = "Elemental Fire",
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

local function isKnownReviewedMap(catalog, mapID)
  if type(catalog) ~= "table" then
    return true
  end
  if type(catalog.reviewedMapsByUiMapID) == "table" and catalog.reviewedMapsByUiMapID[mapID] then
    return true
  end
  if type(catalog.arcaneGrindMapsByUiMapID) == "table" and catalog.arcaneGrindMapsByUiMapID[mapID] then
    return true
  end
  if type(catalog.reviewedMapsByUiMapID) == "table" then
    return false
  end
  return true
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
  if not isKnownReviewedMap(catalog, mapID) then
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
    if not isKnownReviewedMap(catalog, targetMapID) then
      return false, "unreviewed_boat_target_map"
    end
  end
  return true, nil
end

function GoldFarms.GetTrackSupportedLevelRange(catalog)
  catalog = catalog or (ns.State and ns.State.GetCompiledGoldFarms and ns.State.GetCompiledGoldFarms())
  if type(catalog) == "table" and type(catalog.meta) == "table" and type(catalog.meta.arcaneTrackSupportedLevelRange) == "table" then
    local r = catalog.meta.arcaneTrackSupportedLevelRange
    local lo = tonumber(r.min)
    local hi = tonumber(r.max)
    if lo and hi and lo <= hi then
      return math.floor(lo), math.floor(hi)
    end
  end
  local minBracket = nil
  local maxBracket = nil
  if type(catalog) == "table" and type(catalog.arcaneGrindFarms) == "table" then
    for _, f in ipairs(catalog.arcaneGrindFarms) do
      local fMin = tonumber(f and f.minCharacterLevel)
      local fMax = tonumber(f and f.maxCharacterLevel)
      if fMin and (minBracket == nil or fMin < minBracket) then
        minBracket = fMin
      end
      if fMax and (maxBracket == nil or fMax > maxBracket) then
        maxBracket = fMax
      end
    end
  end
  return minBracket or 46, maxBracket or 60
end

function GoldFarms.GetEffectiveTrack(uiState, catalog, explicitLevel)
  uiState = uiState or (ns.State and ns.State.GetWorkspaceUIState and ns.State.GetWorkspaceUIState())
  local goldView = (type(uiState) == "table" and type(uiState.goldView) == "table") and uiState.goldView or {}
  local sel = goldView.selectedTrack or "auto"
  if sel == "arcane_lvl47_st" then
    return "arcane_lvl47_st"
  elseif sel == "lvl40_mount" then
    return "lvl40_mount"
  end

  local minBracket, maxBracket = GoldFarms.GetTrackSupportedLevelRange(catalog)
  local lvl = tonumber(explicitLevel) or tonumber(ns.Compat and ns.Compat.GetPlayerLevel and ns.Compat.GetPlayerLevel()) or 40
  if lvl >= minBracket and lvl <= maxBracket then
    return "arcane_lvl47_st"
  end
  return "lvl40_mount"
end

GoldFarms.DEFAULT_SCENARIO_KILLS_PER_HOUR = 90

GoldFarms.SUBFILTER_BRACKETS = {
  ["46_50"] = { min = 46, max = 50, label = "Lv 46–50" },
  ["48_51"] = { min = 48, max = 51, label = "Lv 48–51" },
  ["51_54"] = { min = 51, max = 54, label = "Lv 51–54" },
  ["54_57"] = { min = 54, max = 57, label = "Lv 54–57" },
  ["57_60"] = { min = 57, max = 60, label = "Lv 57–60" },
}

function GoldFarms.GetClassicZeroDifference(playerLevel)
  local clvl = math.max(1, math.min(60, math.floor(tonumber(playerLevel) or 1)))
  if clvl <= 7 then
    return 5
  elseif clvl <= 9 then
    return 6
  elseif clvl <= 11 then
    return 7
  elseif clvl <= 15 then
    return 8
  elseif clvl <= 19 then
    return 9
  elseif clvl <= 29 then
    return 11
  elseif clvl <= 39 then
    return 12
  elseif clvl <= 44 then
    return 13
  elseif clvl <= 49 then
    return 14
  elseif clvl <= 54 then
    return 15
  elseif clvl <= 59 then
    return 16
  end
  return 17
end

function GoldFarms.GetClassicGrayLevel(playerLevel)
  local clvl = math.max(1, math.min(60, math.floor(tonumber(playerLevel) or 1)))
  if clvl <= 5 then
    return 0
  elseif clvl <= 39 then
    return clvl - math.floor(clvl / 10) - 5
  elseif clvl <= 59 then
    return clvl - math.floor(clvl / 5) - 1
  end
  return 51
end

function GoldFarms.ComputeClassicSoloMobXP(playerLevel, mobLevel)
  local maxCap = (ns.Compat and tonumber(ns.Compat.MAX_PLAYER_LEVEL)) or 60
  local clvl = math.max(1, math.floor(tonumber(playerLevel) or 1))
  local mlvl = math.max(1, math.floor(tonumber(mobLevel) or clvl))
  if clvl >= maxCap then
    return 0
  end
  if mlvl <= GoldFarms.GetClassicGrayLevel(clvl) then
    return 0
  end
  local baseXP = (clvl * 5) + 45
  if mlvl > clvl then
    local diff = math.min(4, mlvl - clvl)
    return math.floor(baseXP * (1 + (0.05 * diff)) + 0.5)
  elseif mlvl == clvl then
    return baseXP
  end
  local zd = GoldFarms.GetClassicZeroDifference(clvl)
  local diff = clvl - mlvl
  if diff >= zd then
    return 0
  end
  return math.floor(baseXP * (1 - (diff / zd)) + 0.5)
end

function GoldFarms.EvaluateStepEligibility(farm, step, playerLevel, progress)
  local clvl = math.max(1, math.floor(tonumber(playerLevel) or tonumber(ns.Compat and ns.Compat.GetPlayerLevel and ns.Compat.GetPlayerLevel()) or 48))
  local maxCap = (ns.Compat and tonumber(ns.Compat.MAX_PLAYER_LEVEL)) or 60
  local SR = ns.Domain and ns.Domain.SpawnRadar
  local admittedNodes = (SR and SR.GetStepNodes and SR.GetStepNodes(step, progress)) or (type(step) == "table" and step.spawnNodes) or {}

  local mobMin = nil
  local mobMax = nil
  for _, n in ipairs(admittedNodes) do
    local nLo = tonumber(n.minLevel or n.level)
    local nHi = tonumber(n.maxLevel or n.level or nLo)
    if nLo and (mobMin == nil or nLo < mobMin) then
      mobMin = math.floor(nLo)
    end
    if nHi and (mobMax == nil or nHi > mobMax) then
      mobMax = math.floor(nHi)
    end
  end
  if mobMin == nil then
    mobMin = tonumber(step and step.mobLevelMin) or tonumber(farm and farm.minMobLevel) or tonumber(farm and farm.minCharacterLevel) or 46
  end
  if mobMax == nil then
    mobMax = tonumber(step and step.mobLevelMax) or tonumber(farm and farm.maxMobLevel) or tonumber(farm and farm.maxCharacterLevel) or mobMin
  end
  mobMin = math.floor(mobMin)
  mobMax = math.max(mobMin, math.floor(mobMax))

  local grayLvl = GoldFarms.GetClassicGrayLevel(clvl)
  local code = "ideal"
  local badgeLabel = "Ideal"
  local hasPlusThreeCliff = false

  if clvl >= maxCap then
    if mobMax <= grayLvl then
      code = "gray"
      badgeLabel = "Gray (0 XP)"
    elseif mobMax >= 55 then
      code = "ideal"
      badgeLabel = "Ideal (Lv 60 Purse)"
    else
      code = "green"
      badgeLabel = "Low-Lvl Purse"
    end
  elseif mobMax <= grayLvl then
    code = "gray"
    badgeLabel = "Gray (0 XP)"
  elseif mobMin >= (clvl + 10) or mobMax >= (clvl + 10) then
    code = "skull"
    badgeLabel = "Skull (+10+)"
    hasPlusThreeCliff = true
  elseif mobMax >= (clvl + 3) then
    code = "high_resist"
    hasPlusThreeCliff = true
    badgeLabel = (mobMin <= clvl + 2)
      and string.format("High Resist (+%d Mixed)", mobMax - clvl)
      or string.format("High Resist (+%d)", mobMax - clvl)
  elseif mobMax >= (clvl + 1) then
    code = "preview_orange"
    badgeLabel = string.format("Preview (+%d)", mobMax - clvl)
  elseif mobMax <= (clvl - 5) then
    code = "green"
    badgeLabel = "Green XP"
  else
    code = "ideal"
    badgeLabel = "Ideal"
  end

  local xpSum = 0
  local xpCnt = 0
  local xpLow = nil
  local xpHigh = nil
  for ml = mobMin, mobMax do
    local x = GoldFarms.ComputeClassicSoloMobXP(clvl, ml)
    xpSum = xpSum + x
    xpCnt = xpCnt + 1
    if xpLow == nil or x < xpLow then
      xpLow = x
    end
    if xpHigh == nil or x > xpHigh then
      xpHigh = x
    end
  end
  local xpAvg = (xpCnt > 0) and (xpSum / xpCnt) or 0
  local scenarioKPH = GoldFarms.DEFAULT_SCENARIO_KILLS_PER_HOUR
  local scenarioXPH = (clvl >= maxCap) and 0 or math.floor((scenarioKPH * xpAvg) + 0.5)

  return {
    stepID = step and step.stepID or nil,
    stepTitle = step and step.title or nil,
    admittedNodeCount = #admittedNodes,
    mobLevelMin = mobMin,
    mobLevelMax = mobMax,
    code = code,
    badgeLabel = badgeLabel,
    hasPlusThreeCliff = hasPlusThreeCliff,
    xpPerMobLow = xpLow or 0,
    xpPerMobHigh = xpHigh or 0,
    xpPerMobAvg = math.floor(xpAvg + 0.5),
    scenarioKillsPerHour = scenarioKPH,
    scenarioXpPerHour = scenarioXPH,
  }
end

local ELIGIBILITY_RANK = {
  ideal = 1,
  preview_orange = 2,
  green = 3,
  high_resist = 4,
  gray = 5,
  skull = 6,
}

function GoldFarms.EvaluateFarmSubcampEligibility(farm, playerLevel, progress)
  local clvl = math.max(1, math.floor(tonumber(playerLevel) or tonumber(ns.Compat and ns.Compat.GetPlayerLevel and ns.Compat.GetPlayerLevel()) or 48))
  local subcamps = {}
  local best = nil
  local worstCliff = nil

  for _, st in ipairs((type(farm) == "table" and farm.travelSteps) or {}) do
    if st.kind == "grind" then
      local ev = GoldFarms.EvaluateStepEligibility(farm, st, clvl, progress)
      if ev.admittedNodeCount > 0 or #(st.spawnNodes or {}) == 0 then
        table.insert(subcamps, ev)
        if not best or (ELIGIBILITY_RANK[ev.code] or 99) < (ELIGIBILITY_RANK[best.code] or 99)
          or ((ELIGIBILITY_RANK[ev.code] == ELIGIBILITY_RANK[best.code]) and (ev.scenarioXpPerHour > best.scenarioXpPerHour))
        then
          best = ev
        end
        if ev.hasPlusThreeCliff then
          worstCliff = ev
        end
      end
    end
  end

  if not best then
    best = GoldFarms.EvaluateStepEligibility(farm, nil, clvl, progress)
    table.insert(subcamps, best)
  end

  local isExperimental = (type(farm) == "table" and farm.publicationTier == "experimental_candidate")
  return {
    playerLevel = clvl,
    isExperimental = isExperimental,
    publicationTier = (type(farm) == "table" and farm.publicationTier) or "primary_source_verified",
    bestSubcamp = best,
    subcamps = subcamps,
    hasIdealSubcamp = (best.code == "ideal"),
    hasPreviewSubcamp = (best.code == "preview_orange"),
    hasEligibleMyLevelSubcamp = (best.code == "ideal" or best.code == "preview_orange"),
    hasAnyCliffSubcamp = (worstCliff ~= nil),
    badgeLabel = best.badgeLabel,
    code = best.code,
    scenarioKillsPerHour = best.scenarioKillsPerHour,
    scenarioXpPerHour = best.scenarioXpPerHour,
    xpPerMobLow = best.xpPerMobLow,
    xpPerMobHigh = best.xpPerMobHigh,
  }
end

function GoldFarms.FilterArcaneFarms(catalog, subFilter, playerLevel, progress)
  catalog = catalog or (ns.State and ns.State.GetCompiledGoldFarms and ns.State.GetCompiledGoldFarms()) or {}
  local primaryList = type(catalog.arcaneGrindFarms) == "table" and catalog.arcaneGrindFarms or {}
  local expList = type(catalog.experimentalArcaneFarms) == "table" and catalog.experimentalArcaneFarms or {}
  local clvl = math.max(1, math.floor(tonumber(playerLevel) or tonumber(ns.Compat and ns.Compat.GetPlayerLevel and ns.Compat.GetPlayerLevel()) or 48))
  local sf = tostring(subFilter or "my_level")
  local seenIDs = {}
  local out = {}
  local evalByFarmID = {}
  local fallbackBelowBracket = false
  local headerTitle = "My Level Eligible Subcamps"

  if sf == "experimental" then
    headerTitle = "Experimental / Conditional Candidates (Opt-In Browse Only)"
    for _, f in ipairs(expList) do
      if f and f.farmID and not seenIDs[f.farmID] then
        seenIDs[f.farmID] = true
        evalByFarmID[f.farmID] = GoldFarms.EvaluateFarmSubcampEligibility(f, clvl, progress)
        table.insert(out, f)
      end
    end
  elseif sf == "all_shortlist" then
    headerTitle = "Unverified Candidate Shortlist (Lv 46–60 Source-Verified)"
    for _, f in ipairs(primaryList) do
      if f and f.farmID and f.publicationTier ~= "experimental_candidate" and not seenIDs[f.farmID] then
        seenIDs[f.farmID] = true
        evalByFarmID[f.farmID] = GoldFarms.EvaluateFarmSubcampEligibility(f, clvl, progress)
        table.insert(out, f)
      end
    end
  elseif GoldFarms.SUBFILTER_BRACKETS[sf] ~= nil then
    local br = GoldFarms.SUBFILTER_BRACKETS[sf]
    headerTitle = string.format("%s Subcamp Candidates (Source-Verified)", br.label)
    for _, f in ipairs(primaryList) do
      if f and f.farmID and f.publicationTier ~= "experimental_candidate" and not seenIDs[f.farmID] then
        local fMin = tonumber(f.minCharacterLevel) or 46
        local fMax = tonumber(f.maxCharacterLevel) or 60
        if fMin <= br.max and fMax >= br.min then
          seenIDs[f.farmID] = true
          evalByFarmID[f.farmID] = GoldFarms.EvaluateFarmSubcampEligibility(f, clvl, progress)
          table.insert(out, f)
        end
      end
    end
  else
    sf = "my_level"
    headerTitle = (clvl >= 60)
      and "Level 60 Endgame Purse Subcamps (Source-Verified)"
      or string.format("Lv %d Eligible Subcamps (Ideal & +1/+2 Preview)", clvl)
    local scored = {}
    for idx, f in ipairs(primaryList) do
      if f and f.farmID and f.publicationTier ~= "experimental_candidate" and not seenIDs[f.farmID] then
        local ev = GoldFarms.EvaluateFarmSubcampEligibility(f, clvl, progress)
        evalByFarmID[f.farmID] = ev
        if ev.hasEligibleMyLevelSubcamp then
          seenIDs[f.farmID] = true
          table.insert(scored, { farm = f, eval = ev, ord = idx })
        end
      end
    end
    table.sort(scored, function(a, b)
      local ra = ELIGIBILITY_RANK[a.eval.code] or 99
      local rb = ELIGIBILITY_RANK[b.eval.code] or 99
      if ra ~= rb then
        return ra < rb
      end
      if clvl >= 60 then
        local ma = a.eval.bestSubcamp and a.eval.bestSubcamp.mobLevelMax or 0
        local mb = b.eval.bestSubcamp and b.eval.bestSubcamp.mobLevelMax or 0
        if ma ~= mb then
          return ma > mb
        end
      elseif math.abs((a.eval.scenarioXpPerHour or 0) - (b.eval.scenarioXpPerHour or 0)) > 1500 then
        return a.eval.scenarioXpPerHour > b.eval.scenarioXpPerHour
      end
      return a.ord < b.ord
    end)
    for _, item in ipairs(scored) do
      table.insert(out, item.farm)
    end
    if #out == 0 and #primaryList > 0 then
      fallbackBelowBracket = true
      headerTitle = string.format("Lv %d Outside 46–60 Window — Entry Lv 46–50 Subcamps", clvl)
      for _, f in ipairs(primaryList) do
        local fMin = tonumber(f.minCharacterLevel) or 46
        if f and f.farmID and f.publicationTier ~= "experimental_candidate" and fMin <= 48 and not seenIDs[f.farmID] then
          seenIDs[f.farmID] = true
          evalByFarmID[f.farmID] = evalByFarmID[f.farmID] or GoldFarms.EvaluateFarmSubcampEligibility(f, clvl, progress)
          table.insert(out, f)
        end
      end
    end
  end

  local gProg = progress or (ns.State and ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress())
  local activeFarm = nil
  local activeFarmHidden = false
  if gProg and gProg.mode ~= "paused" and gProg.selectedFarmID then
    activeFarm = lookupRouteByID(catalog, gProg.selectedFarmID)
    if activeFarm and activeFarm.track == "arcane_lvl47_st" and not seenIDs[activeFarm.farmID] then
      activeFarmHidden = true
    end
  end

  return {
    subFilter = sf,
    playerLevel = clvl,
    headerTitle = headerTitle,
    farms = out,
    evalByFarmID = evalByFarmID,
    fallbackBelowBracket = fallbackBelowBracket,
    activeFarm = activeFarm,
    activeFarmHidden = activeFarmHidden,
  }
end

function GoldFarms.GetFarmsForTrack(trackKey, catalog)
  catalog = catalog or (ns.State and ns.State.GetCompiledGoldFarms and ns.State.GetCompiledGoldFarms())
  if type(catalog) ~= "table" then
    return {}
  end
  if trackKey == "arcane_lvl47_st" and type(catalog.arcaneGrindFarms) == "table" and #catalog.arcaneGrindFarms > 0 then
    return catalog.arcaneGrindFarms
  end
  return catalog.farms or {}
end

function GoldFarms.LookupFarmByID(farmID, catalog)
  catalog = catalog or (ns.State and ns.State.GetCompiledGoldFarms and ns.State.GetCompiledGoldFarms())
  return lookupRouteByID(catalog, farmID)
end

function GoldFarms.ResolveFarm(query, catalog, preferredTrack)
  catalog = catalog or (ns.State and ns.State.GetCompiledGoldFarms and ns.State.GetCompiledGoldFarms())
  if type(catalog) ~= "table" or type(catalog.farms) ~= "table" or #catalog.farms == 0 then
    return nil, "Gold farms catalog is not loaded."
  end

  local primaryFarms = catalog.farms
  if preferredTrack == "arcane_lvl47_st" and type(catalog.arcaneGrindFarms) == "table" and #catalog.arcaneGrindFarms > 0 then
    primaryFarms = catalog.arcaneGrindFarms
  end

  if query == nil or query == "" then
    return primaryFarms[1], nil
  end

  local asNum = tonumber(query)
  if isFinite(asNum) then
    local ordInt = math.floor(asNum)
    for _, f in ipairs(primaryFarms) do
      if tonumber(f.candidateOrder or f.rank) == ordInt then
        return f, nil
      end
    end
    if primaryFarms[ordInt] then
      return primaryFarms[ordInt], nil
    end
  end

  local qStr = string.lower(string.gsub(tostring(query), "^%s*(.-)%s*$", "%1"))

  local arcaneIdx = string.match(qStr, "^arcane[:%-_]?%s*(%d+)$") or string.match(qStr, "^a(%d+)$")
  if arcaneIdx and type(catalog.arcaneGrindFarms) == "table" then
    local ord = tonumber(arcaneIdx)
    for _, f in ipairs(catalog.arcaneGrindFarms) do
      if tonumber(f.candidateOrder or f.rank) == ord then
        return f, nil
      end
    end
    if catalog.arcaneGrindFarms[ord] then
      return catalog.arcaneGrindFarms[ord], nil
    end
  end

  local mountIdx = string.match(qStr, "^mount[:%-_]?%s*(%d+)$") or string.match(qStr, "^m(%d+)$")
  if mountIdx then
    local ord = tonumber(mountIdx)
    for _, f in ipairs(catalog.farms) do
      if tonumber(f.candidateOrder or f.rank) == ord then
        return f, nil
      end
    end
    if catalog.farms[ord] then
      return catalog.farms[ord], nil
    end
  end

  if catalog.farmsByID and catalog.farmsByID[qStr] then
    return catalog.farmsByID[qStr], nil
  end
  if catalog.arcaneGrindFarmsByID and catalog.arcaneGrindFarmsByID[qStr] then
    return catalog.arcaneGrindFarmsByID[qStr], nil
  end
  if catalog.experimentalArcaneFarmsByID and catalog.experimentalArcaneFarmsByID[qStr] then
    return catalog.experimentalArcaneFarmsByID[qStr], nil
  end
  if catalog.expandedRoutesByID and catalog.expandedRoutesByID[qStr] then
    return catalog.expandedRoutesByID[qStr], nil
  end

  local searchLists = (preferredTrack == "arcane_lvl47_st")
    and { catalog.arcaneGrindFarms or {}, catalog.experimentalArcaneFarms or {}, catalog.farms, catalog.expandedRoutes or {} }
    or { catalog.farms, catalog.arcaneGrindFarms or {}, catalog.experimentalArcaneFarms or {}, catalog.expandedRoutes or {} }

  for _, list in ipairs(searchLists) do
    for _, f in ipairs(list) do
      if string.lower(tostring(f.farmID or "")) == qStr then
        return f, nil
      end
    end
  end

  for _, list in ipairs(searchLists) do
    for _, f in ipairs(list) do
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
  end

  return nil,
    "Unknown gold farm '" .. tostring(query) .. "'. Use '/fh gold list' to see available routes."
end

-- World-yard arrival & non-proximity service/boat completion (Astra P1-6 & Gate 5):
-- - `grind` camps are STICKY and never auto-complete.
-- - `vendor` stops NEVER auto-complete on proximity; they complete on `MERCHANT_CLOSED` near the NPC or manual `Next`.
-- - `boat_crossing` NEVER completes on origin pier proximity; it completes ONLY when `playerPos.uiMapID == step.targetUiMapID` (or manual `Next`).
-- - `travel` hops require world-yard distance (`Compat.GetWorldDistanceYards`) <= `arrivalRadiusYards`; if map world dimensions are unavailable, manual completion is retained.
function GoldFarms.CheckHopArrival(step, playerPos, catalog, farm)
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

  if type(step.prerequisiteGate) == "table" and step.prerequisiteGate.gateKind == "conditionally_blocked_crossing" then
    local gateDestMapID = tonumber(step.prerequisiteGate.destinationUiMapID)
    if gateDestMapID and playerMapID == gateDestMapID then
      return true, "prerequisite_crossing_destination_reached"
    end
    return false, "prerequisite_gate_requires_crossing_or_manual"
  end

  if step.kind ~= "travel" and step.kind ~= "boat_disembark" then
    return false, "unsupported_auto_arrival_kind"
  end

  if GoldFarms.GetPublicationState(farm) == "source_verified" and not (type(farm) == "table" and farm.track == "arcane_lvl47_st") then
    return false, "traversal_unverified_manual_only"
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
    if step.kind == "boat_disembark" then
      return true, "boat_disembark_world_yards"
    end
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
    farm = lookupRouteByID(catalog, progress.selectedFarmID)
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

  local farm = progress.selectedFarmID and lookupRouteByID(catalog, progress.selectedFarmID) or nil
  if not farm then
    return GoldFarms.Evaluate(catalog, progress, playerPos)
  end

  local prevStepID = progress.currentStepID
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

  if activeStep and GoldFarms.CheckHopArrival(activeStep, pos, catalog, farm) then
    progress.manualPinnedStepID = nil
    progress.completedTravelSteps[activeStep.stepID] = {
      completedAt = nowTimestamp(),
      reason = (activeStep.kind == "boat_crossing") and "boat_crossing_arrival"
        or ((activeStep.kind == "boat_disembark") and "boat_disembark_arrival" or "hop_arrival"),
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
  if progress.currentStepID ~= prevStepID and ns.Domain and ns.Domain.SpawnRadar and ns.Domain.SpawnRadar.SyncExistingOwnedTargetMacro then
    ns.Domain.SpawnRadar.SyncExistingOwnedTargetMacro("GoldFarms.ReconcileActive")
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

local function ensureGoldFarmNavigationContext()
  if ns.UI and ns.UI.Navigation and ns.UI.Navigation.RequestContextSwitch then
    ns.UI.Navigation.RequestContextSwitch("gold_farm")
  end
end

function GoldFarms.Start(farmQuery, catalog, progress, playerPos, preferredTrack)
  catalog = catalog or (ns.State and ns.State.GetCompiledGoldFarms and ns.State.GetCompiledGoldFarms())
  progress = progress or (ns.State and ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress())
  if not catalog or not progress then
    return false, "Gold farms data or state unavailable."
  end

  local effectiveQuery = farmQuery
  if (effectiveQuery == nil or effectiveQuery == "") and progress.selectedFarmID then
    effectiveQuery = progress.selectedFarmID
  end

  local farm, resolveErr = GoldFarms.ResolveFarm(effectiveQuery, catalog, preferredTrack)
  if not farm then
    return false, resolveErr
  end

  ensureGoldFarmNavigationContext()
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
    if ns.Domain and ns.Domain.SpawnRadar and ns.Domain.SpawnRadar.ResetCooldowns then
      ns.Domain.SpawnRadar.ResetCooldowns(farm.farmID)
    end
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

  -- Smart in-camp start for Level 46-50 Arcane ST grinds (Astra P1-7):
  -- - Only matches surface-eligible grind steps (never `excludeFromAutoRadarUntilWalked` / `unclassified_cave_risk` unless explicitly opted in).
  -- - Requires calibrated world-yard distances (`status == "ok"`).
  -- - Bypasses ONLY preceding `travel` instructions (`reason = "bypassed_travel_started_in_camp"`); NEVER marks `vendor` steps completed or implies repairs occurred!
  if farm.track == "arcane_lvl47_st"
    and liveMapID ~= nil
    and liveMapID == tonumber(farm.uiMapID)
    and type(pos) == "table"
    and pos.status == "ok"
    and ns.Compat
    and ns.Compat.GetWorldDistanceYards
  then
    local allowCaveRisk = (progress.includeUnwalkedCaveNodes == true)
    local steps = farm.travelSteps or {}
    local curIdx = findStepIndex(steps, progress.currentStepID)
    local curStep = curIdx and steps[curIdx] or nil
    if not curStep or curStep.kind ~= "grind" then
      local matchedGrindIdx = nil
      local bestNodeYards = nil
      local SR = ns.Domain and ns.Domain.SpawnRadar
      for sIdx, st in ipairs(steps) do
        local stepHazardExcluded = (st.terrainAccess == "excluded_hazard")
        local stepCaveExcluded = ((st.excludeFromAutoRadarUntilWalked == true) or (st.terrainAccess == "unclassified_cave_risk")) and not allowCaveRisk
        if st.kind == "grind" and not stepHazardExcluded and not stepCaveExcluded and st.destination and tonumber(st.destination.uiMapID) == liveMapID then
          local dAnchor = ns.Compat.GetWorldDistanceYards(liveMapID, pos.x01, pos.y01, st.destination.x01, st.destination.y01)
          local campHit = (dAnchor and dAnchor.status == "ok" and type(dAnchor.yards) == "number" and dAnchor.yards <= 160.0)
          local minNodeYards = (campHit and dAnchor.yards) or nil
          for _, sn in ipairs(st.spawnNodes or {}) do
            local admitted = false
            if SR and SR.IsNodeTerrainAdmitted then
              admitted = SR.IsNodeTerrainAdmitted(st, sn, progress)
            else
              local terrain = sn.terrainAccess or st.terrainAccess or "surface_candidate"
              admitted = (terrain == "walked_verified" or terrain == "surface_candidate" or (terrain == "unclassified_cave_risk" and allowCaveRisk))
            end
            if admitted then
              local dn = ns.Compat.GetWorldDistanceYards(liveMapID, pos.x01, pos.y01, sn.x01, sn.y01)
              if dn and dn.status == "ok" and type(dn.yards) == "number" and dn.yards <= 65.0 then
                campHit = true
                if minNodeYards == nil or dn.yards < minNodeYards then
                  minNodeYards = dn.yards
                end
              end
            end
          end
          if campHit and (bestNodeYards == nil or (minNodeYards or 160) < bestNodeYards) then
            matchedGrindIdx = sIdx
            bestNodeYards = minNodeYards or 160
          end
        end
      end
      if matchedGrindIdx and steps[matchedGrindIdx] then
        progress.completedTravelSteps = progress.completedTravelSteps or {}
        for i = 1, matchedGrindIdx - 1 do
          if steps[i] and steps[i].kind == "travel" then
            progress.completedTravelSteps[steps[i].stepID] = {
              completedAt = nowTimestamp(),
              reason = "bypassed_travel_started_in_camp",
              uiMapID = liveMapID,
              x01 = pos.x01,
              x01_bypass = true,
              y01 = pos.y01,
            }
          end
        end
        progress.currentStepID = steps[matchedGrindIdx].stepID
      end
    end
  end

  if ns.State and ns.State.GetWorkspaceUIState then
    local uiState = ns.State.GetWorkspaceUIState()
    if type(uiState) == "table" and type(uiState.goldView) == "table" then
      uiState.goldView.focusedFarmID = farm.farmID
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

  if ns.Domain and ns.Domain.SpawnRadar and ns.Domain.SpawnRadar.SyncExistingOwnedTargetMacro then
    ns.Domain.SpawnRadar.SyncExistingOwnedTargetMacro("GoldFarms.Start")
  end

  return true, eval
end

function GoldFarms.RestartEntryFromCurrentZone(catalog, progress, playerPos)
  catalog = catalog or (ns.State and ns.State.GetCompiledGoldFarms and ns.State.GetCompiledGoldFarms())
  progress = progress or (ns.State and ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress())
  if not catalog or not progress or not progress.selectedFarmID then
    return false, "No gold farm selected. Use '/fh gold start <1-5>' first."
  end
  local farm = lookupRouteByID(catalog, progress.selectedFarmID)
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
  if ns.Domain and ns.Domain.SpawnRadar and ns.Domain.SpawnRadar.SyncExistingOwnedTargetMacro then
    ns.Domain.SpawnRadar.SyncExistingOwnedTargetMacro("GoldFarms.RestartEntryFromCurrentZone")
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
  if ns.Domain and ns.Domain.SpawnRadar and ns.Domain.SpawnRadar.SyncExistingOwnedTargetMacro then
    ns.Domain.SpawnRadar.SyncExistingOwnedTargetMacro("GoldFarms.Pause")
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
    if ns.Domain and ns.Domain.SpawnRadar and ns.Domain.SpawnRadar.ResetCooldowns then
      ns.Domain.SpawnRadar.ResetCooldowns(progress.selectedFarmID)
    end
  end
  if ns.Domain and ns.Domain.SpawnRadar and ns.Domain.SpawnRadar.SyncExistingOwnedTargetMacro then
    ns.Domain.SpawnRadar.SyncExistingOwnedTargetMacro("GoldFarms.Stop")
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
  if ns.Domain and ns.Domain.SpawnRadar and ns.Domain.SpawnRadar.SyncExistingOwnedTargetMacro then
    ns.Domain.SpawnRadar.SyncExistingOwnedTargetMacro("GoldFarms.NextHop")
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
  if ns.Domain and ns.Domain.SpawnRadar and ns.Domain.SpawnRadar.SyncExistingOwnedTargetMacro then
    ns.Domain.SpawnRadar.SyncExistingOwnedTargetMacro("GoldFarms.PrevHop")
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
  local vendorFloorStatus = tostring(gphMeta.vendorFloorStatus or "")
  local rawLowG = tonumber(gphMeta.lowGold)
  local rawHighG = tonumber(gphMeta.highGold)
  local lowG = rawLowG or 0
  local highG = rawHighG or 0
  local communityLabel
  if vendorFloorStatus == "unmeasured_until_sampled" and rawLowG == nil then
    communityLabel = "Unmeasured until sampled in-client (Net Purse / Active Hr)"
  else
    communityLabel = string.format("%d-%dg/hr (Community Est. — Unverified)", lowG, highG)
  end

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

  local elapsed = math.max(0, math.floor(tonumber(sessionSnap.elapsedSeconds or sessionSnap.accumulatedSeconds) or 0))
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
    predictedTotalLowGold = tonumber(gphMeta.predictedTotalLowGold),
    predictedTotalHighGold = tonumber(gphMeta.predictedTotalHighGold),
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

function GoldFarms.EvaluateSessionXP(farm, sessionSnap, xpState)
  local xpMeta = (type(farm) == "table" and type(farm.xpMeta) == "table") and farm.xpMeta or nil
  local estPerMobLow = xpMeta and tonumber(xpMeta.xpPerMobLow) or nil
  local estPerMobHigh = xpMeta and tonumber(xpMeta.xpPerMobHigh) or nil
  local estPerHourLow = xpMeta and tonumber(xpMeta.xpPerHourLow) or nil
  local estPerHourHigh = xpMeta and tonumber(xpMeta.xpPerHourHigh) or nil
  local estLabel = nil
  if estPerMobLow and estPerMobHigh and estPerHourLow and estPerHourHigh then
    estLabel = string.format(
      "~%d-%d XP/mob (~%dk-%dk XP/hr unverified est.)",
      math.floor(estPerMobLow),
      math.floor(estPerMobHigh),
      math.floor(estPerHourLow / 1000 + 0.5),
      math.floor(estPerHourHigh / 1000 + 0.5)
    )
  end

  sessionSnap = sessionSnap or (ns.State and ns.State.GetGoldFarmSessionSnapshot and ns.State.GetGoldFarmSessionSnapshot()) or {}
  xpState = xpState or (ns.Compat and ns.Compat.GetPlayerXPState and ns.Compat.GetPlayerXPState()) or { status = "unavailable" }

  local elapsed = math.max(0, math.floor(tonumber(sessionSnap.elapsedSeconds or sessionSnap.accumulatedSeconds) or 0))
  local totalSessionXP = math.max(0, math.floor(tonumber(sessionSnap.totalSessionXP or sessionSnap.accumulatedXP) or 0))
  local killsObserved = math.max(0, math.floor(tonumber(sessionSnap.killsObserved) or 0))
  local questRewardXP = math.max(0, math.floor(tonumber(sessionSnap.questRewardXP) or 0))
  local unattributedXP = 0
  local attributableGrindXP = 0
  if sessionSnap.attributableGrindXP ~= nil then
    attributableGrindXP = math.max(0, math.floor(tonumber(sessionSnap.attributableGrindXP) or 0))
    unattributedXP = math.max(0, math.floor(tonumber(sessionSnap.unattributedXP) or math.max(0, totalSessionXP - attributableGrindXP - questRewardXP)))
  elseif killsObserved > 0 and sessionSnap.xpContaminated ~= true then
    attributableGrindXP = math.max(0, totalSessionXP - questRewardXP)
  else
    unattributedXP = math.max(0, totalSessionXP - questRewardXP)
  end

  local maxCapLevel = (ns.Compat and tonumber(ns.Compat.MAX_PLAYER_LEVEL)) or 60
  local curLvl = (type(xpState) == "table" and tonumber(xpState.level)) or 47
  local isCappedNow = (sessionSnap.levelCapReached == true)
    or (type(xpState) == "table" and xpState.status == "capped")
    or (curLvl >= maxCapLevel)
  local terminalUnresolved = (sessionSnap.terminalSnapshotUnresolved == true)
  local xpElapsedAtCap = (sessionSnap.xpElapsedAtCap ~= nil)
    and math.max(0, math.floor(tonumber(sessionSnap.xpElapsedAtCap) or 0))
    or nil
  local xpRolloverUnresolved = (sessionSnap.xpRolloverUnresolved == true) or terminalUnresolved
  local xpContaminated = (sessionSnap.xpContaminated == true) or xpRolloverUnresolved or (unattributedXP > 0)
  local xpContaminationReason = sessionSnap.xpContaminationReason
    or (terminalUnresolved and "terminal_xp_probe_unavailable")
    or (xpRolloverUnresolved and "rollover_unresolved")
    or ((unattributedXP > 0) and "unattributed_xp")
    or nil
  local restedIncluded = (sessionSnap.restedIncluded == true)
  local restedRegimeChanged = (sessionSnap.restedRegimeChanged == true)
  local isPaused = not (sessionSnap.active == true)

  local liveStatus = "idle"
  local liveLabel = isCappedNow
    and string.format("Level %d Cap Reached — XP meter retired (see Net Purse Change / Active Hr)", curLvl)
    or "Idle — start farm to measure live grind XP/hr"
  local measuredGrindXpPerHour = nil
  local measuredTotalXpPerHour = nil
  local etaNextLevelMinutes = nil
  local etaSuppressionReason = isCappedNow and "level_cap_reached" or nil

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

  local restedSuffix = restedRegimeChanged and " [rested changed]" or (restedIncluded and " [incl. rested]" or "")

  if isCappedNow then
    if terminalUnresolved then
      liveStatus = "xp_rollover_unresolved"
      etaSuppressionReason = "terminal_xp_probe_unavailable"
      liveLabel = string.format(
        "%sTerminal Lv %d XP snapshot unresolved (%d kills — last valid total preserved)",
        pausePrefix,
        curLvl,
        killsObserved
      )
    elseif xpRolloverUnresolved then
      liveStatus = "xp_rollover_unresolved"
      etaSuppressionReason = "xp_rollover_unresolved"
      liveLabel = string.format(
        "%sXP rollover unresolved before Lv %d cap (%d kills)",
        pausePrefix,
        curLvl,
        killsObserved
      )
    else
      etaSuppressionReason = "level_cap_reached"
      local xpDenom = xpElapsedAtCap
      if xpDenom ~= nil and xpDenom >= MIN_GPH_SAMPLE_SECONDS and attributableGrindXP > 0 then
        measuredGrindXpPerHour = math.floor((attributableGrindXP * 3600) / xpDenom + 0.5)
        measuredTotalXpPerHour = math.floor((totalSessionXP * 3600) / xpDenom + 0.5)
        liveStatus = isPaused and "measured_paused_at_cap" or "level_capped_with_history"
        liveLabel = string.format(
          "%s%d grind XP/hr%s (pre-cap %dm frozen, +%d grind XP • Level %d Cap Reached)",
          pausePrefix,
          measuredGrindXpPerHour,
          restedSuffix,
          math.floor(xpDenom / 60),
          attributableGrindXP,
          curLvl
        )
      elseif attributableGrindXP > 0 then
        liveStatus = "level_capped"
        liveLabel = string.format(
          "%sLevel %d Cap Reached (+%d final grind XP, %d kills — see Net Purse Change / Active Hr)",
          pausePrefix,
          curLvl,
          attributableGrindXP,
          killsObserved
        )
      else
        liveStatus = "level_capped"
        liveLabel = string.format(
          "%sLevel %d Cap Reached — XP meter retired (%d kills; see Net Purse Change / Active Hr)",
          pausePrefix,
          curLvl,
          killsObserved
        )
      end
    end
  elseif elapsed > 0 or sessionSnap.active then
    if elapsed < MIN_GPH_SAMPLE_SECONDS then
      liveStatus = isPaused and "paused_warming_up" or "warming_up"
      etaSuppressionReason = "insufficient_sample_seconds"
      liveLabel = string.format(
        "%sWarming up (%ds/%ds min sample, +%d grind XP, %d kills)",
        pausePrefix,
        elapsed,
        MIN_GPH_SAMPLE_SECONDS,
        attributableGrindXP,
        killsObserved
      )
    else
      measuredGrindXpPerHour = math.floor((attributableGrindXP * 3600) / elapsed + 0.5)
      measuredTotalXpPerHour = math.floor((totalSessionXP * 3600) / elapsed + 0.5)
      local sampleMins = math.floor(elapsed / 60)
      local remXP = (type(xpState) == "table" and xpState.status == "ok") and tonumber(xpState.remainingXP) or nil

      if xpRolloverUnresolved then
        measuredGrindXpPerHour = nil
        measuredTotalXpPerHour = nil
        liveStatus = "xp_rollover_unresolved"
        etaSuppressionReason = "xp_rollover_unresolved"
        liveLabel = string.format(
          "%sXP rollover unresolved%s (%dm active — multi-level jump; /fh gold reset for clean interval)",
          pausePrefix,
          restedSuffix,
          sampleMins
        )
      elseif measuredGrindXpPerHour <= 0 then
        etaSuppressionReason = "zero_attributable_grind_xp"
        if totalSessionXP > 0 then
          liveStatus = "non_grind_xp_only"
          liveLabel = string.format(
            "%s0 grind XP/hr (%dm active, +%d non-grind XP excluded; ETA suppressed)",
            pausePrefix,
            sampleMins,
            totalSessionXP
          )
        else
          liveStatus = "measured_zero"
          liveLabel = string.format(
            "%s0 grind XP/hr (%dm active — defeat camp mobs to measure live grind rate)",
            pausePrefix,
            sampleMins
          )
        end
      else
        liveStatus = isPaused and "measured_paused" or "measured_positive"
        if xpContaminated then
          etaSuppressionReason = xpContaminationReason or "xp_contaminated"
        elseif restedRegimeChanged then
          etaSuppressionReason = "rested_regime_changed"
        elseif not remXP or remXP <= 0 then
          etaSuppressionReason = "xp_state_unavailable"
        end

        if etaSuppressionReason ~= nil then
          liveLabel = string.format(
            "%s%d grind XP/hr%s (%dm active, %d kills — ETA suppressed: %s)",
            pausePrefix,
            measuredGrindXpPerHour,
            restedSuffix,
            sampleMins,
            killsObserved,
            tostring(etaSuppressionReason)
          )
        else
          etaNextLevelMinutes = math.ceil((remXP * 60) / measuredGrindXpPerHour)
          liveLabel = string.format(
            "%s%d grind XP/hr%s (%dm active, %d kills • ~%dm to Lv %d)",
            pausePrefix,
            measuredGrindXpPerHour,
            restedSuffix,
            sampleMins,
            killsObserved,
            etaNextLevelMinutes,
            curLvl + 1
          )
        end
      end
    end
  end

  return {
    estPerMobLow = estPerMobLow,
    estPerMobHigh = estPerMobHigh,
    estPerHourLow = estPerHourLow,
    estPerHourHigh = estPerHourHigh,
    estLabel = estLabel,
    xpBasis = xpMeta and tostring(xpMeta.basis or "") or "",
    elapsedSeconds = elapsed,
    xpElapsedAtCap = xpElapsedAtCap,
    levelCapReached = isCappedNow,
    terminalSnapshotUnresolved = terminalUnresolved,
    accumulatedXP = totalSessionXP,
    totalSessionXP = totalSessionXP,
    attributableGrindXP = attributableGrindXP,
    questRewardXP = questRewardXP,
    unattributedXP = unattributedXP,
    killsObserved = killsObserved,
    xpContaminated = xpContaminated,
    xpContaminationReason = xpContaminationReason,
    xpRolloverUnresolved = xpRolloverUnresolved,
    restedIncluded = restedIncluded,
    restedRegimeChanged = restedRegimeChanged,
    liveStatus = liveStatus,
    liveLabel = liveLabel,
    isPaused = isPaused,
    measuredGrindXpPerHour = measuredGrindXpPerHour,
    measuredTotalXpPerHour = measuredTotalXpPerHour,
    measuredXpPerHour = measuredGrindXpPerHour,
    etaNextLevelMinutes = etaNextLevelMinutes,
    etaSuppressionReason = etaSuppressionReason,
    xpState = xpState,
  }
end

function GoldFarms.ListRoutesForProfile(opts, catalog)
  opts = type(opts) == "table" and opts or {}
  catalog = catalog or (ns.State and ns.State.GetCompiledGoldFarms and ns.State.GetCompiledGoldFarms()) or ns.GoldFarmsData
  if type(catalog) ~= "table" then
    return {
      verifiedRoutes = {},
      sourceVerifiedCandidates = {},
      coverageMatrix = nil,
    }
  end

  local faction = tostring(opts.faction or "Alliance")
  if faction == "A" then
    faction = "Alliance"
  elseif faction == "H" then
    faction = "Horde"
  end
  local level = math.max(1, math.floor(tonumber(opts.level) or 40))
  local requiredCap = opts.requiredCapabilityTag and tostring(opts.requiredCapabilityTag) or nil

  local verifiedRoutes = {}
  local sourceVerifiedCandidates = {}

  local function matchesRoute(route)
    if type(route) ~= "table" or route.reviewStatus ~= "verified" then
      return false
    end
    local rFac = tostring(route.faction or (catalog.meta and catalog.meta.faction) or "Alliance")
    if rFac ~= faction then
      return false
    end
    local minLvl = tonumber(route.minCharacterLevel) or 39
    local maxLvl = tonumber(route.maxCharacterLevel) or 42
    if level < minLvl or level > maxLvl then
      return false
    end
    if requiredCap and type(route.capabilityTags) == "table" then
      local hasCap = false
      for _, t in ipairs(route.capabilityTags) do
        if t == requiredCap then
          hasCap = true
          break
        end
      end
      if not hasCap then
        return false
      end
    end
    return true
  end

  for _, f in ipairs(catalog.farms or {}) do
    if matchesRoute(f) then
      local pub = GoldFarms.GetPublicationState(f)
      if pub == "traversal_verified" or pub == "economically_measured" then
        table.insert(verifiedRoutes, f)
      else
        table.insert(sourceVerifiedCandidates, f)
      end
    end
  end

  for _, r in ipairs(catalog.expandedRoutes or {}) do
    if matchesRoute(r) then
      local pub = GoldFarms.GetPublicationState(r)
      if pub == "traversal_verified" or pub == "economically_measured" then
        table.insert(verifiedRoutes, r)
      else
        table.insert(sourceVerifiedCandidates, r)
      end
    end
  end

  return {
    verifiedRoutes = verifiedRoutes,
    sourceVerifiedCandidates = sourceVerifiedCandidates,
    coverageMatrix = catalog.coverageMatrix,
  }
end
