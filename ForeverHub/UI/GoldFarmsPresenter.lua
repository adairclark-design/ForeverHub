local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.UI = ns.UI or {}

local Theme = ns.UI.Theme
local GoldFarmsPresenter = {}
ns.UI.GoldFarmsPresenter = GoldFarmsPresenter

local FARM_ICON_FALLBACKS = {
  badlands_elementals_coyotes = 7912, -- Solid Stone / Elemental drop
  dustwallow_muckshells_crocs = 4304, -- Thick Leather
  swamp_jaguars_snappers = 4234, -- Heavy Leather
  arathi_exiles_circles = 4306, -- Silk Cloth
  rg_brineshell_twilight = 4338, -- Mageweave Cloth
  arcane_hinterlands_owlbeasts = 4589, -- Long Elegant Feather
  arcane_azshara_hippogryphs = 4304, -- Thick Leather
  arcane_felwood_deadwood = 4338, -- Mageweave Cloth
  arcane_searing_gorge_elementals = 7068, -- Elemental Fire
  arcane_tanaris_dunemaul = 4338, -- Mageweave Cloth
  arcane_hinterlands_snapjaws = 8150, -- Deeprock Salt / Turtle scale
  arcane_azshara_thunderheads = 4304, -- Thick Leather
  arcane_felwood_jadefire_south = 14047, -- Runecloth
  arcane_wpl_sorrow_hill = 14047, -- Runecloth
  arcane_azshara_legashi_classic = 14047, -- Runecloth
  arcane_azshara_blood_elves_classic = 14047, -- Runecloth
  arcane_felwood_jadefire_north = 14047, -- Runecloth
  arcane_ungoro_fire_plume = 7068, -- Elemental Fire
  arcane_wpl_northridge_lumber = 14047, -- Runecloth
  arcane_winterspring_keltheril = 14047, -- Runecloth
  arcane_silithus_crystal_vale = 7067, -- Elemental Earth
  arcane_winterspring_owlbeasts = 8170, -- Rugged Leather
  arcane_winterspring_winterfall_east = 14047, -- Runecloth
  arcane_silithus_twilight = 14047, -- Runecloth
}

local function formatDurationMinutes(mins)
  local m = math.max(1, math.floor(tonumber(mins) or 0))
  if m >= 60 then
    local h = math.floor(m / 60)
    local rem = m % 60
    if rem == 0 then
      return string.format("%dh", h)
    end
    return string.format("%dh %dm", h, rem)
  end
  return string.format("%dm", m)
end

local function formatSecondsCompact(sec)
  local s = math.max(0, math.floor(tonumber(sec) or 0))
  if s >= 3600 then
    return string.format("%dh %dm", math.floor(s / 3600), math.floor((s % 3600) / 60))
  elseif s >= 60 then
    return string.format("%dm %ds", math.floor(s / 60), s % 60)
  end
  return string.format("%ds", s)
end

local function summarizeTargetsLine(farm)
  local names = {}
  local drops = {}
  for _, t in ipairs(farm.targets or {}) do
    if t.name and t.name ~= "" then
      table.insert(names, tostring(t.name))
    end
    if t.drops and t.drops ~= "" and #drops < 2 then
      table.insert(drops, tostring(t.drops))
    end
  end
  local left = (#names > 0) and table.concat(names, ", ") or "Verified grind targets"
  if #drops > 0 then
    return left .. " · " .. drops[1]
  end
  return left
end

local function countFarmSpawnNodes(farm)
  local total = 0
  for _, st in ipairs((type(farm) == "table" and farm.travelSteps) or {}) do
    if st.kind == "grind" and type(st.spawnNodes) == "table" then
      total = total + #st.spawnNodes
    end
  end
  return total
end

local function findFarmInList(list, farmID)
  if not farmID or type(list) ~= "table" then
    return nil
  end
  for _, f in ipairs(list) do
    if f.farmID == farmID then
      return f
    end
  end
  return nil
end

-- Strictly read-only snapshot capture: NEVER mutates progress, waypoints, or session telemetry.
function GoldFarmsPresenter.CaptureSnapshot(override)
  if type(override) == "table" then
    return override
  end
  local catalog = ns.State and ns.State.GetCompiledGoldFarms and ns.State.GetCompiledGoldFarms() or { farms = {} }
  local progress = ns.State and ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress() or { mode = "paused" }
  local mt = ns.State and ns.State.GetMountTracker and ns.State.GetMountTracker() or {}
  local sessSnap = ns.State and ns.State.GetGoldFarmSessionSnapshot and ns.State.GetGoldFarmSessionSnapshot() or {}
  local xpState = (ns.Compat and ns.Compat.GetPlayerXPState and ns.Compat.GetPlayerXPState()) or { status = "unavailable" }

  local activeEval = (ns.Domain and ns.Domain.GoldFarms and ns.Domain.GoldFarms.Evaluate)
      and ns.Domain.GoldFarms.Evaluate(catalog, progress)
    or nil
  local activeFarm = (activeEval and activeEval.farm) or (catalog.farms and catalog.farms[1]) or nil
  local gphReport = (ns.Domain and ns.Domain.GoldFarms and ns.Domain.GoldFarms.EvaluateGPHAndMountETA)
      and ns.Domain.GoldFarms.EvaluateGPHAndMountETA(activeFarm, sessSnap, mt)
    or {}
  local xpReport = (ns.Domain and ns.Domain.GoldFarms and ns.Domain.GoldFarms.EvaluateSessionXP)
      and ns.Domain.GoldFarms.EvaluateSessionXP(activeFarm, sessSnap, xpState)
    or {}

  local warningsByFarmID = {}
  if ns.Domain and ns.Domain.GoldFarms and ns.Domain.GoldFarms.GetReservationWarningsForFarm then
    for _, f in ipairs(catalog.farms or {}) do
      warningsByFarmID[f.farmID] = ns.Domain.GoldFarms.GetReservationWarningsForFarm(f)
    end
    for _, f in ipairs(catalog.arcaneGrindFarms or {}) do
      warningsByFarmID[f.farmID] = ns.Domain.GoldFarms.GetReservationWarningsForFarm(f)
    end
    for _, f in ipairs(catalog.experimentalArcaneFarms or {}) do
      warningsByFarmID[f.farmID] = ns.Domain.GoldFarms.GetReservationWarningsForFarm(f)
    end
  end

  local macroSyncStatus = (ns.Domain and ns.Domain.SpawnRadar and ns.Domain.SpawnRadar.GetMacroSyncStatus)
      and ns.Domain.SpawnRadar.GetMacroSyncStatus()
    or { status = "Inactive", reason = "unavailable" }

  local navStatus = ns.UI and ns.UI.Navigation and ns.UI.Navigation.lastStatus or nil
  local navContext = ns.UI and ns.UI.Navigation and ns.UI.Navigation.activeContext or nil

  return {
    catalog = catalog,
    progress = {
      mode = progress.mode or "paused",
      selectedFarmID = progress.selectedFarmID,
      currentStepID = progress.currentStepID,
      manualPinnedStepID = progress.manualPinnedStepID,
      spawnRadarMode = progress.spawnRadarMode or "auto",
      spawnPinMode = progress.spawnPinMode or "active",
      includeUnwalkedCaveNodes = (progress.includeUnwalkedCaveNodes == true),
    },
    mountTracker = mt,
    sessionSnap = sessSnap,
    xpState = xpState,
    activeEval = activeEval,
    gphReport = gphReport,
    xpReport = xpReport,
    warningsByFarmID = warningsByFarmID,
    macroSyncStatus = macroSyncStatus,
    navLabel = (navContext == "gold_farm" and navStatus and navStatus.navigationLabel) or nil,
  }
end

function GoldFarmsPresenter.Build(snapshot, uiState)
  snapshot = type(snapshot) == "table" and snapshot or GoldFarmsPresenter.CaptureSnapshot()
  local uiRef = type(uiState) == "table" and uiState or (ns.State and ns.State.GetWorkspaceUIState and ns.State.GetWorkspaceUIState()) or {}
  local goldView = (type(uiRef.goldView) == "table") and uiRef.goldView or {}
  local expandedByFarmID = type(goldView.expandedByFarmID) == "table" and goldView.expandedByFarmID or {}

  local catalog = snapshot.catalog or { farms = {} }
  local prog = snapshot.progress or { mode = "paused" }
  local mt = snapshot.mountTracker or {}
  local sess = snapshot.sessionSnap or {}
  local rep = snapshot.gphReport or {}
  local xpRep = snapshot.xpReport or {}
  local xpState = snapshot.xpState or { status = "unavailable" }
  local activeEval = snapshot.activeEval
  local macroSyncStatus = snapshot.macroSyncStatus
    or ((ns.Domain and ns.Domain.SpawnRadar and ns.Domain.SpawnRadar.GetMacroSyncStatus) and ns.Domain.SpawnRadar.GetMacroSyncStatus())
    or { status = "Inactive" }

  local curLvl = tonumber(xpState.level) or (ns.Compat and ns.Compat.GetPlayerLevel and ns.Compat.GetPlayerLevel()) or 48
  local maxCapLevel = (ns.Compat and tonumber(ns.Compat.MAX_PLAYER_LEVEL)) or 60
  local isLevelCapped = (xpState.status == "capped") or (xpRep.levelCapReached == true) or (curLvl >= maxCapLevel)

  local selectedTrack = goldView.selectedTrack or "auto"
  local effectiveTrack = "lvl40_mount"
  if selectedTrack == "arcane_lvl47_st" then
    effectiveTrack = "arcane_lvl47_st"
  elseif selectedTrack == "lvl40_mount" then
    effectiveTrack = "lvl40_mount"
  elseif ns.Domain and ns.Domain.GoldFarms and ns.Domain.GoldFarms.GetEffectiveTrack then
    effectiveTrack = ns.Domain.GoldFarms.GetEffectiveTrack(uiRef, catalog, curLvl)
  else
    if type(curLvl) == "number" and curLvl >= 46 and curLvl <= 60 and type(catalog.arcaneGrindFarms) == "table" and #catalog.arcaneGrindFarms > 0 then
      effectiveTrack = "arcane_lvl47_st"
    end
  end

  local isArcaneTrack = (effectiveTrack == "arcane_lvl47_st")
    and type(catalog.arcaneGrindFarms) == "table"
    and #catalog.arcaneGrindFarms > 0

  local subFilter = goldView.subFilter or "my_level"
  local filterRes = nil
  local trackFarms = catalog.farms or {}
  local hiddenActiveRouteSummary = nil
  if isArcaneTrack then
    if ns.Domain and ns.Domain.GoldFarms and ns.Domain.GoldFarms.FilterArcaneFarms then
      filterRes = ns.Domain.GoldFarms.FilterArcaneFarms(catalog, subFilter, curLvl, prog)
      subFilter = filterRes.subFilter or subFilter
      trackFarms = filterRes.farms or catalog.arcaneGrindFarms
      if filterRes.activeFarmHidden and filterRes.activeFarm then
        local actStepText = "Active navigation"
        if activeEval and activeEval.activeStep then
          actStepText = string.format(
            "Hop %d/%d · %s",
            tonumber(activeEval.stepIndex) or 1,
            tonumber(activeEval.totalSteps) or 1,
            tostring(activeEval.activeStep.title or "")
          )
        end
        hiddenActiveRouteSummary = {
          farmID = filterRes.activeFarm.farmID,
          title = tostring(filterRes.activeFarm.title or filterRes.activeFarm.farmID),
          stepSummary = actStepText,
          isExperimental = (filterRes.activeFarm.publicationTier == "experimental_candidate"),
        }
      end
    else
      trackFarms = catalog.arcaneGrindFarms
    end
  end

  -- Determine single highlighted/selected farm within the displayed track so ONLY ONE row gets primary gold `Navigate`!
  local focusedFarmID = nil
  if prog.mode ~= "paused" and prog.selectedFarmID and findFarmInList(trackFarms, prog.selectedFarmID) then
    focusedFarmID = prog.selectedFarmID
  elseif type(goldView.focusedFarmID) == "string" and goldView.focusedFarmID ~= "" and findFarmInList(trackFarms, goldView.focusedFarmID) then
    focusedFarmID = goldView.focusedFarmID
  elseif prog.selectedFarmID and findFarmInList(trackFarms, prog.selectedFarmID) then
    focusedFarmID = prog.selectedFarmID
  elseif trackFarms[1] then
    focusedFarmID = trackFarms[1].farmID
  end

  local refFarm = (activeEval and activeEval.farm)
    or findFarmInList(trackFarms, focusedFarmID)
    or trackFarms[1]
    or (isArcaneTrack and catalog.arcaneGrindFarms[1])
  local rawRadarMode = (prog.spawnRadarMode == "on" or prog.spawnRadarMode == "off") and prog.spawnRadarMode or "auto"
  local radarEffectiveOn = false
  if ns.Domain and ns.Domain.SpawnRadar and ns.Domain.SpawnRadar.GetEffectiveMode then
    local _, effOn = ns.Domain.SpawnRadar.GetEffectiveMode(refFarm, prog)
    radarEffectiveOn = effOn
  else
    radarEffectiveOn = (rawRadarMode == "on") or (rawRadarMode == "auto" and isArcaneTrack)
  end
  local radarPillLabel = (rawRadarMode == "on" and "Radar: ON")
    or (rawRadarMode == "off" and "Radar: OFF")
    or (radarEffectiveOn and "Radar: Auto (ON)" or "Radar: Auto (OFF)")
  local rawPinMode = (prog.spawnPinMode == "all" or prog.spawnPinMode == "off") and prog.spawnPinMode or "active"
  local pinPillLabel = (rawPinMode == "all" and "Pins: All")
    or (rawPinMode == "off" and "Pins: OFF")
    or "Pins: Active"

  -- 1. Build 5 Honest Summary KPIs
  local purseVal = sess.moneyAvailable and Theme.FormatMoney(sess.currentCopper, { plainText = true }) or "Purse unknown"
  local reserveSub = rep.zeroReserveWarning
    and "0c reserve (click 5g/10g)"
    or ("Reserve buffer: " .. Theme.FormatMoney(rep.reserveCopper or 0, { plainText = true }))

  local targetVal = Theme.FormatMoney(rep.targetCopper or 900000, { plainText = true })
  local quoteConfirmed = (rep.quoteStatus == "user_confirmed")
  local targetSub = quoteConfirmed and "Confirmed quote" or "Unconfirmed 90g default"

  local remVal = "Unknown"
  local remSub = "Needs live purse"
  local remTok = "text.secondary"
  if rep.fundingStatus == "funded" then
    remVal = "Funded"
    remSub = "Target + reserve met"
    remTok = "status.ready"
  elseif rep.fundingStatus == "shortfall" then
    remVal = Theme.FormatMoney(rep.shortfallCopper or 0, { plainText = true })
    remSub = "After reserve buffer"
    remTok = "status.buy"
  end

  local rateVal = "No sample"
  local rateSub = "Start farm to measure"
  local rateTok = "text.secondary"
  local elapsed = tonumber(sess.elapsedSeconds) or 0
  if rep.liveStatus == "purse_unknown" then
    rateVal = "Purse unknown"
    rateSub = formatSecondsCompact(elapsed) .. " active"
    rateTok = "status.warning"
  elseif rep.liveStatus == "warming_up" or rep.liveStatus == "paused_warming_up" then
    rateVal = "Collecting"
    rateSub = string.format("%ds / 180s min sample", elapsed)
    rateTok = "text.secondary"
  elseif type(rep.measuredCopperPerHour) == "number" then
    local absC = math.abs(rep.measuredCopperPerHour)
    local sign = rep.measuredCopperPerHour > 0 and "+" or (rep.measuredCopperPerHour < 0 and "-" or "")
    rateVal = sign .. Theme.FormatMoney(absC, { plainText = true }) .. "/hr"
    rateSub = formatSecondsCompact(elapsed) .. (sess.active and " active" or " (paused)")
    rateTok = rep.measuredCopperPerHour > 0 and "status.ready" or (rep.measuredCopperPerHour < 0 and "status.danger" or "text.secondary")
  end

  -- KPI 5: Mount ETA — STRICTLY honest; NEVER fabricates an ETA from community estimates!
  local etaVal = "Collecting session data"
  local etaSub = "Requires >= 3m clean sample"
  local etaTok = "text.muted"
  if type(rep.etaMinutesMeasured) == "number" and rep.etaMinutesMeasured > 0 then
    etaVal = formatDurationMinutes(rep.etaMinutesMeasured)
    etaSub = "At observed session rate"
    etaTok = "accent.gold"
  elseif rep.fundingStatus == "funded" then
    etaVal = "Target reached"
    etaSub = "Mount + riding funded"
    etaTok = "status.ready"
  elseif rep.etaSuppressionReason == "session_contaminated" then
    etaVal = "Suppressed"
    etaSub = "Mail/AH/trade in session"
    etaTok = "status.warning"
  elseif rep.etaSuppressionReason == "negative_net_cash_flow" then
    etaVal = "Suppressed"
    etaSub = "Negative net purse rate"
    etaTok = "status.warning"
  elseif rep.etaSuppressionReason == "zero_net_cash_flow" then
    etaVal = "Suppressed"
    etaSub = "0c net purse change"
    etaTok = "text.muted"
  elseif rep.etaSuppressionReason == "purse_unknown" or rep.fundingStatus == "unknown" then
    etaVal = "Unavailable"
    etaSub = "Live purse unknown"
    etaTok = "text.muted"
  end

  local kpis
  local frac = 0
  local progressSummaryLeft = ""
  local progressSummaryRight = ""
  local targetC = math.max(1, tonumber(rep.targetCopper) or 900000)
  local reserveC = math.max(0, tonumber(rep.reserveCopper) or 0)

  if isArcaneTrack then
    local refSpawnTotal = countFarmSpawnNodes(refFarm)
    local radarSub = string.format("%d recorded pts", refSpawnTotal)
    local ls = ns.Domain and ns.Domain.SpawnRadar and ns.Domain.SpawnRadar.state and ns.Domain.SpawnRadar.state.lastSummary
    if prog.mode ~= "paused" and ls and tonumber(ls.totalCount) and tonumber(ls.totalCount) > 0 then
      radarSub = string.format("%d/%d active pool", tonumber(ls.unobservedCount or ls.readyCount) or 0, tonumber(ls.totalCount) or 0)
    end
    local grindRate = tonumber(xpRep.measuredGrindXpPerHour or xpRep.measuredXpPerHour)
    local macroStateText = tostring(macroSyncStatus.status or "Inactive")

    if isLevelCapped then
      -- Level 60 Endgame Purse Pivot (Astra P1-1 / P1-2):
      -- Retires Next-Level XP ETA cleanly, never divides by zero, never prompts to defeat mobs for XP,
      -- and elevates Net Purse Change / Active Hour + configurable goal budget (never hardcoding an unverified epic mount price).
      local capSub = "XP meter retired at cap"
      if xpRep.xpRolloverUnresolved then
        capSub = "Terminal cap snapshot unresolved"
      elseif type(grindRate) == "number" and grindRate > 0 then
        capSub = string.format("Pre-cap: %d XP/hr frozen", grindRate)
      elseif (tonumber(xpRep.attributableGrindXP) or 0) > 0 then
        capSub = string.format("+%d final grind XP", tonumber(xpRep.attributableGrindXP) or 0)
      end

      local spendableC = (sess.moneyAvailable and type(sess.currentCopper) == "number")
          and math.max(0, math.floor(sess.currentCopper) - reserveC)
        or 0
      frac = sess.moneyAvailable and math.max(0, math.min(1.0, spendableC / targetC)) or 1.0
      local pctCap = math.floor(frac * 100 + 0.5)

      kpis = {
        {
          value = rateVal,
          label = "Net Purse / Active Hr",
          sub = rateSub,
          token = rateTok,
          tooltipTitle = "Primary Lv 60 KPI — Net Purse Change / Active Hour",
          tooltipLines = {
            "At Level 60 cap, primary route evaluation pivots to observed realized coin delta across active camp + travel/vendor time.",
            "Negative rates (repairs/flights) are shown honestly and never clamped to 0.",
          },
        },
        {
          value = purseVal,
          label = "Current purse",
          sub = (remVal ~= "Unknown") and ("Goal rem: " .. remVal) or reserveSub,
          token = sess.moneyAvailable and "text.primary" or "status.warning",
          tooltipTitle = "Current Purse & Configurable Savings Goal",
          tooltipLines = {
            "Tracks spendable funds against your configurable savings target and cash reserve buffer (/fh mount).",
            "ForeverHub never hardcodes an unverified Forever epic mount total.",
          },
        },
        {
          value = string.format("Lv %d (Cap)", curLvl),
          label = "Level & XP",
          sub = capSub,
          token = xpRep.xpRolloverUnresolved and "status.warning" or "status.ready",
          tooltipTitle = "Level Cap Reached",
          tooltipLines = {
            "WoW: Forever character level cap (60) reached.",
            "Pre-cap session grind XP/hr is frozen at the cap ding so post-cap farming time never dilutes historical XP rates.",
          },
        },
        {
          value = "Cap reached",
          label = "Next level ETA",
          sub = "0 XP needed at Lv 60",
          token = "status.ready",
          tooltipTitle = "Next Level ETA Retired at Cap",
          tooltipLines = {
            "Suppressed cleanly at Level 60 (etaSuppressionReason = level_cap_reached).",
          },
        },
        {
          value = radarEffectiveOn and "Active" or "Off",
          label = "Spawn radar",
          sub = radarSub,
          token = radarEffectiveOn and "status.ready" or "text.muted",
          tooltipTitle = "Candidate-Spawn Radar (Source-Verified Coordinates)",
          tooltipLines = {
            "Points the directional arrow to the nearest recorded QuestieDB spawn coordinate.",
            "Suppresses verified camp kills (~180s revisit est.) and manual skips (/fh gold skip, ~120s).",
          },
        },
      }

      progressSummaryLeft = sess.moneyAvailable
        and string.format(
          "Lv %d Cap · Net Purse Focus — Spendable: %s / %s goal (%d%%)",
          curLvl,
          Theme.FormatMoney(spendableC, { plainText = true }),
          Theme.FormatMoney(targetC, { plainText = true }),
          pctCap
        )
        or string.format("Lv %d Cap Reached — Primary metric: Net Purse Change / Active Hour", curLvl)
      progressSummaryRight = "FH_Target: " .. macroStateText
    else
      local xpPct = (xpState.status == "ok" and type(xpState.fraction) == "number")
        and math.floor(xpState.fraction * 100 + 0.5)
        or 0
      local lvlVal = (xpState.status == "ok") and string.format("Lv %d (%d%%)", curLvl, xpPct) or string.format("Lv %d", curLvl)
      local lvlSub = (xpState.status == "ok") and string.format("%d XP remaining", tonumber(xpState.remainingXP) or 0) or "Live XP bar unavailable"

      local xpRateVal = "No sample"
      local xpRateSub = "Start grind to measure"
      local xpRateTok = "text.secondary"
      if xpRep.xpRolloverUnresolved then
        xpRateVal = "Unresolved"
        xpRateSub = "Multi-level jump; reset meter"
        xpRateTok = "status.warning"
      elseif xpRep.liveStatus == "warming_up" or xpRep.liveStatus == "paused_warming_up" then
        xpRateVal = "Collecting"
        xpRateSub = string.format(
          "%ds / 180s (+%d grind XP)",
          tonumber(xpRep.elapsedSeconds) or 0,
          tonumber(xpRep.attributableGrindXP or xpRep.accumulatedXP) or 0
        )
        xpRateTok = "text.secondary"
      elseif type(grindRate) == "number" and grindRate > 0 then
        xpRateVal = string.format("%d/hr", grindRate)
        xpRateSub = string.format(
          "%d kills · %s%s",
          tonumber(xpRep.killsObserved) or 0,
          formatSecondsCompact(xpRep.elapsedSeconds or 0),
          xpRep.xpContaminated and " · +non-grind" or ""
        )
        xpRateTok = xpRep.xpContaminated and "status.warning" or "status.ready"
      elseif xpRep.liveStatus == "measured_zero" or xpRep.liveStatus == "non_grind_xp_only" then
        xpRateVal = "0 XP/hr"
        xpRateSub = xpRep.xpContaminated
          and string.format("0 grind (+%d non-grind XP)", tonumber(xpRep.totalSessionXP) or 0)
          or (formatSecondsCompact(xpRep.elapsedSeconds or 0) .. " active")
        xpRateTok = xpRep.xpContaminated and "status.warning" or "text.muted"
      end

      local lvlEtaVal = "Collecting data"
      local lvlEtaSub = "Requires >= 3m clean grind"
      local lvlEtaTok = "text.muted"
      if type(xpRep.etaNextLevelMinutes) == "number" and xpRep.etaNextLevelMinutes > 0 then
        lvlEtaVal = formatDurationMinutes(xpRep.etaNextLevelMinutes)
        lvlEtaSub = string.format("To Lv %d (observed)", curLvl + 1)
        lvlEtaTok = "accent.gold"
      elseif xpRep.etaSuppressionReason == "xp_session_contaminated" then
        lvlEtaVal = "Suppressed"
        lvlEtaSub = "Non-grind XP in session"
        lvlEtaTok = "status.warning"
      elseif xpRep.etaSuppressionReason == "xp_rollover_unresolved" or xpRep.etaSuppressionReason == "terminal_xp_probe_unavailable" then
        lvlEtaVal = "Suppressed"
        lvlEtaSub = "Level rollover unresolved"
        lvlEtaTok = "status.warning"
      elseif xpRep.etaSuppressionReason == "rested_regime_changed" then
        lvlEtaVal = "Suppressed"
        lvlEtaSub = "Rested bonus changed"
        lvlEtaTok = "status.warning"
      elseif xpRep.etaSuppressionReason == "zero_grind_xp" or xpRep.etaSuppressionReason == "zero_attributable_grind_xp" then
        lvlEtaVal = "Suppressed"
        lvlEtaSub = "0 attributable grind XP"
        lvlEtaTok = "text.muted"
      end

      kpis = {
        {
          value = lvlVal,
          label = "Level & XP",
          sub = lvlSub,
          token = "text.primary",
          tooltipTitle = "Character Level & XP Progress",
          tooltipLines = { "Arcane Single-Target Mage candidate catalog (Lv 46–60) in WoW: Forever." },
        },
        {
          value = xpRateVal,
          label = "Grind XP / hr",
          sub = xpRateSub,
          token = xpRateTok,
          tooltipTitle = "Observed Attributable Grind XP / Active Hour",
          tooltipLines = {
            "Computed strictly from reconciled camp-target kills across >= 3m active session time.",
            "Quest turn-ins and unattributed XP are tracked separately and never inflate grind XP/hr.",
          },
        },
        {
          value = lvlEtaVal,
          label = "Next level ETA",
          sub = lvlEtaSub,
          token = lvlEtaTok,
          tooltipTitle = "Time to Next Level",
          tooltipLines = {
            "Projected strictly from clean observed grind XP/hr (>= 180s).",
            "Suppressed automatically if quest/unattributed XP or rested-bonus changes occur.",
          },
        },
        {
          value = rateVal,
          label = "Observed gold / hr",
          sub = rateSub,
          token = rateTok,
          tooltipTitle = "Observed Net Purse Change / Active Hour",
          tooltipLines = {
            "Measures realized coin delta across active camp + travel/vendor time.",
            "Negative rates (repairs/flights) are shown honestly and never clamped to 0.",
          },
        },
        {
          value = radarEffectiveOn and "Active" or "Off",
          label = "Spawn radar",
          sub = radarSub,
          token = radarEffectiveOn and "status.ready" or "text.muted",
          tooltipTitle = "Candidate-Spawn Radar (Source-Verified Coordinates)",
          tooltipLines = {
            "Points the directional arrow to the nearest recorded QuestieDB spawn coordinate.",
            "Suppresses verified camp kills (~180s revisit est.) and manual skips (/fh gold skip, ~120s).",
          },
        },
      }

      frac = (xpState.status == "ok" and type(xpState.fraction) == "number")
        and math.max(0, math.min(1.0, xpState.fraction))
        or 0
      progressSummaryLeft = (xpState.status == "ok")
        and string.format(
          "Level %d XP: %d / %d (%d%%) — %d XP to Level %d",
          curLvl,
          tonumber(xpState.currentXP) or 0,
          tonumber(xpState.maxXP) or 1,
          xpPct,
          tonumber(xpState.remainingXP) or 0,
          curLvl + 1
        )
        or "Arcane Single-Target Mage Grind Track (Lv 46–60)"
      progressSummaryRight = "Basic Campfire (+4% Spirit) · FH_Target: " .. macroStateText
    end
  else
    kpis = {
      {
        value = purseVal,
        label = "Current purse",
        sub = reserveSub,
        token = sess.moneyAvailable and "text.primary" or "status.warning",
        tooltipTitle = "Current Character Purse",
        tooltipLines = { "Spendable mount funds subtract your configured cash reserve buffer for repairs, reagents, and flights." },
      },
      {
        value = targetVal,
        label = "Mount target",
        sub = targetSub,
        token = quoteConfirmed and "text.primary" or "status.warning",
        tooltipTitle = "Mount & Riding Target",
        tooltipLines = {
          "Level 40 Apprentice Riding includes your 1st racial basic mount.",
          "Confirm 90g (Honored) or 100g (Base) once verified at your racial riding trainer.",
        },
      },
      {
        value = remVal,
        label = "Remaining",
        sub = remSub,
        token = remTok,
        tooltipTitle = "Remaining Gold Needed",
        tooltipLines = { "Exact shortfall after keeping your cash reserve buffer intact." },
      },
      {
        value = rateVal,
        label = "Observed / hr",
        sub = rateSub,
        token = rateTok,
        tooltipTitle = "Observed Net Purse Change / Active Hour",
        tooltipLines = {
          "Measures realized coin delta across active camp + travel/vendor time.",
          "Negative rates (repairs/flights) are shown honestly and never clamped to 0.",
        },
      },
      {
        value = etaVal,
        label = "Mount ETA",
        sub = etaSub,
        token = etaTok,
        tooltipTitle = "Observed Mount ETA",
        tooltipLines = {
          "Computed strictly from clean observed session earnings (>= 3m sample).",
          "ForeverHub never fabricates an ETA from unverified community estimates.",
        },
      },
    }

    local spendableC = (sess.moneyAvailable and type(sess.currentCopper) == "number")
        and math.max(0, math.floor(sess.currentCopper) - reserveC)
      or 0
    frac = sess.moneyAvailable and math.max(0, math.min(1.0, spendableC / targetC)) or 0
    local pct = math.floor(frac * 100 + 0.5)

    local silkInfo = rep.unrealizedSilkBandages
    local silkNote = nil
    if type(silkInfo) == "table" and (tonumber(silkInfo.bandagesCraftable) or 0) > 0 then
      silkNote = string.format(
        "Unrealized unreserved Silk: %dx -> %d Heavy Silk Bandages (%s vendor)",
        tonumber(silkInfo.unreservedSilk or silkInfo.silkConvertible) or 0,
        tonumber(silkInfo.bandagesCraftable) or 0,
        Theme.FormatMoney(tonumber(silkInfo.vendorCopper) or 0, { plainText = true })
      )
    end

    progressSummaryLeft = sess.moneyAvailable
      and string.format(
        "Spendable toward mount: %s / %s (%d%%)",
        Theme.FormatMoney(spendableC, { plainText = true }),
        Theme.FormatMoney(targetC, { plainText = true }),
        pct
      )
      or "Spendable toward mount: Purse unavailable"
    progressSummaryRight = silkNote or (quoteConfirmed and "Trainer quote confirmed" or "Confirm quote at riding trainer")
  end

  -- 3. Farm Cards
  local farmsVM = {}
  for idx, farm in ipairs(trackFarms) do
    local fid = tostring(farm.farmID)
    local isActiveNav = (prog.mode ~= "paused" and prog.selectedFarmID == fid)
    local isFocused = (fid == focusedFarmID)
    local isExpanded = (expandedByFarmID[fid] == true) or isActiveNav
    local gphMeta = farm.gphMeta or {}
    local xpMeta = farm.xpMeta or nil
    local warnings = (snapshot.warningsByFarmID and snapshot.warningsByFarmID[fid]) or {}
    local spawnNodeCount = countFarmSpawnNodes(farm)

    local subEval = (filterRes and filterRes.evalByFarmID and filterRes.evalByFarmID[fid])
      or ((isArcaneTrack and ns.Domain and ns.Domain.GoldFarms and ns.Domain.GoldFarms.EvaluateFarmSubcampEligibility)
        and ns.Domain.GoldFarms.EvaluateFarmSubcampEligibility(farm, curLvl, prog)
        or nil)

    local iconItemID = (type(farm.watchedMaterialItemIDs) == "table" and tonumber(farm.watchedMaterialItemIDs[1]))
      or FARM_ICON_FALLBACKS[fid]
      or 4306

    local hops = {}
    local activeStepIdx = (isActiveNav and activeEval and tonumber(activeEval.stepIndex)) or nil
    for sIdx, st in ipairs(farm.travelSteps or {}) do
      local xPct, yPct = nil, nil
      if ns.Domain and ns.Domain.GoldFarms and ns.Domain.GoldFarms.NormalizedToPercent and st.destination then
        xPct, yPct = ns.Domain.GoldFarms.NormalizedToPercent(st.destination.x01, st.destination.y01)
      end
      local coordLabel = (xPct and yPct) and string.format(" (%.1f, %.1f)", xPct, yPct) or ""
      local nodeTag = ""
      if st.kind == "grind" and type(st.spawnNodes) == "table" and #st.spawnNodes > 0 then
        local admitted = (ns.Domain and ns.Domain.SpawnRadar and ns.Domain.SpawnRadar.GetStepNodes)
          and ns.Domain.SpawnRadar.GetStepNodes(st, prog)
          or st.spawnNodes
        local stepBadge = ""
        if isArcaneTrack and ns.Domain and ns.Domain.GoldFarms and ns.Domain.GoldFarms.EvaluateStepEligibility then
          local sev = ns.Domain.GoldFarms.EvaluateStepEligibility(farm, st, curLvl, prog)
          if sev and sev.badgeLabel then
            stepBadge = string.format(" · %s (Lv %d–%d)", tostring(sev.badgeLabel), sev.mobLevelMin, sev.mobLevelMax)
          end
        end
        if st.excludeFromAutoRadarUntilWalked == true and not prog.includeUnwalkedCaveNodes then
          nodeTag = string.format(" [%d recorded pts; cave risk excluded%s]", #st.spawnNodes, stepBadge)
        elseif #admitted < #st.spawnNodes then
          nodeTag = string.format(" [%d/%d surface pts; hazard/cave excluded%s]", #admitted, #st.spawnNodes, stepBadge)
        else
          nodeTag = string.format(" [%d recorded pts%s]", #st.spawnNodes, stepBadge)
        end
      end
      table.insert(hops, {
        index = sIdx,
        stepID = st.stepID,
        kind = st.kind,
        title = tostring(st.title or st.stepID) .. coordLabel .. nodeTag,
        isCurrent = (activeStepIdx == sIdx),
      })
    end

    local activeStepSummary = nil
    if isActiveNav and activeEval and activeEval.activeStep then
      activeStepSummary = string.format(
        "Hop %d/%d · %s",
        tonumber(activeEval.stepIndex) or 1,
        tonumber(activeEval.totalSteps) or #hops,
        tostring(activeEval.activeStep.title or "")
      )
    end

    local goldText
    if gphMeta.vendorFloorStatus == "unmeasured_until_sampled" then
      goldText = "Vendor liq.: UNKNOWN pre-sample"
    else
      goldText = string.format(
        "Est. vendor liq.: %d–%dg/hr · Pred. value: %d–%dg/hr (unverified)",
        tonumber(gphMeta.lowGold) or 0,
        tonumber(gphMeta.highGold) or 0,
        tonumber(gphMeta.predictedTotalLowGold or gphMeta.lowGold) or 0,
        tonumber(gphMeta.predictedTotalHighGold or gphMeta.highGold) or 0
      )
    end

    local metaLine2
    if isArcaneTrack and subEval then
      local xpPart
      if isLevelCapped then
        xpPart = "Lv 60 Cap (0 XP; purse focus)"
      else
        xpPart = string.format(
          "Cond. XP (@%d kills/hr scenario): ~%d–%d/mob (~%.1fk/hr est.)",
          tonumber(subEval.scenarioKillsPerHour) or 90,
          tonumber(subEval.xpPerMobLow) or 0,
          tonumber(subEval.xpPerMobHigh) or 0,
          (tonumber(subEval.scenarioXpPerHour) or 0) / 1000.0
        )
      end
      metaLine2 = string.format("%s · %s · %d recorded pts", xpPart, goldText, spawnNodeCount)
    elseif xpMeta then
      metaLine2 = string.format(
        "Est. XP: ~%d–%d/mob (~%dk–%dk/hr unverified) · %s · %d recorded pts",
        tonumber(xpMeta.xpPerMobLow) or 0,
        tonumber(xpMeta.xpPerMobHigh) or 0,
        math.floor((tonumber(xpMeta.xpPerHourLow) or 0) / 1000 + 0.5),
        math.floor((tonumber(xpMeta.xpPerHourHigh) or 0) / 1000 + 0.5),
        goldText,
        spawnNodeCount
      )
    else
      metaLine2 = string.format(
        "%s · Community est. %d–%dg/hr (unverified)",
        tostring(farm.mageSafety or "Mage Candidate"),
        tonumber(gphMeta.lowGold) or 0,
        tonumber(gphMeta.highGold) or 0
      )
    end

    local lootBucketsNote = nil
    if type(farm.lootBuckets) == "table" and type(farm.lootBuckets.personalSustainItemIDs) == "table" and #farm.lootBuckets.personalSustainItemIDs > 0 then
      local hasDemonicRune = false
      for _, id in ipairs(farm.lootBuckets.personalSustainItemIDs) do
        if tonumber(id) == 12662 then
          hasDemonicRune = true
          break
        end
      end
      if hasDemonicRune then
        lootBucketsNote = "BoP Sustain (NOT Gold): Demonic Rune [12662] is personal mana sustain only and is never priced as saleable gold."
      end
    end

    table.insert(farmsVM, {
      index = idx,
      farmID = fid,
      track = farm.track or "lvl40_mount",
      publicationTier = tostring(farm.publicationTier or "primary_source_verified"),
      isExperimental = (farm.publicationTier == "experimental_candidate"),
      candidateOrder = tonumber(farm.candidateOrder or farm.rank) or idx,
      title = tostring(farm.title or fid),
      zoneAndLevel = string.format("%s · Lv %s", tostring(farm.zoneName or ""), tostring(farm.recommendedLevelRange or "40")),
      iconItemID = iconItemID,
      metaLine1 = summarizeTargetsLine(farm),
      metaLine2 = metaLine2,
      spawnNodeCount = spawnNodeCount,
      eligibilityCode = subEval and subEval.code or nil,
      eligibilityBadge = subEval and subEval.badgeLabel or nil,
      hasAnyCliffSubcamp = (subEval and subEval.hasAnyCliffSubcamp == true) or false,
      lootBucketsNote = lootBucketsNote,
      xpBasis = xpMeta and tostring(xpMeta.basis or "") or nil,
      isActiveNav = isActiveNav,
      isFocused = isFocused,
      isExpanded = isExpanded,
      activeStepSummary = activeStepSummary,
      hasReservationConflict = (#warnings > 0),
      warnings = warnings,
      howToGetThere = tostring(farm.howToGetThereSummary or ""),
      magePullNotes = tostring(farm.magePullNotes or ""),
      payoutBasis = tostring(gphMeta.payoutBasis or ""),
      hops = hops,
    })
  end

  local isAnyGoldNavActive = (prog.mode ~= "paused")
  return {
    effectiveTrack = effectiveTrack,
    isArcaneTrack = isArcaneTrack,
    isLevelCapped = isLevelCapped,
    subFilter = subFilter,
    subFilterHeader = (filterRes and filterRes.headerTitle) or "Lv 46–60 Source-Verified Subcamps",
    allArcaneCount = #(catalog.arcaneGrindFarms or {}),
    experimentalCount = #(catalog.experimentalArcaneFarms or {}),
    hiddenActiveRouteSummary = hiddenActiveRouteSummary,
    macroSyncStatus = macroSyncStatus,
    focusedFarmID = focusedFarmID,
    spawnRadarMode = rawRadarMode,
    spawnRadarEffectiveOn = radarEffectiveOn,
    radarPillLabel = radarPillLabel,
    spawnPinMode = rawPinMode,
    pinPillLabel = pinPillLabel,
    kpis = kpis,
    progressFraction = frac,
    progressLeftText = progressSummaryLeft,
    progressRightText = progressSummaryRight,
    quoteConfirmed = quoteConfirmed,
    targetCopper = targetC,
    reserveCopper = reserveC,
    isAnyGoldNavActive = isAnyGoldNavActive,
    activeNavLabel = snapshot.navLabel or (isAnyGoldNavActive and "Active" or "Idle"),
    farms = farmsVM,
    cards = farmsVM,
    gphReport = rep,
    xpReport = xpRep,
    xpState = xpState,
    quarantinedCount = (catalog.quarantinedFarms and #catalog.quarantinedFarms) or 0,
    arcaneQuarantinedCount = (catalog.arcaneQuarantinedFarms and #catalog.arcaneQuarantinedFarms) or 0,
    tabBadge = isAnyGoldNavActive and "Active"
      or ((not isArcaneTrack and rep.fundingStatus == "funded") and "Funded" or ""),
  }
end

return GoldFarmsPresenter
