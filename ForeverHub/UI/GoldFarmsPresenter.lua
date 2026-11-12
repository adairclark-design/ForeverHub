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

-- Strictly read-only snapshot capture: NEVER mutates progress, waypoints, or session telemetry.
function GoldFarmsPresenter.CaptureSnapshot(override)
  if type(override) == "table" then
    return override
  end
  local catalog = ns.State and ns.State.GetCompiledGoldFarms and ns.State.GetCompiledGoldFarms() or { farms = {} }
  local progress = ns.State and ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress() or { mode = "paused" }
  local mt = ns.State and ns.State.GetMountTracker and ns.State.GetMountTracker() or {}
  local sessSnap = ns.State and ns.State.GetGoldFarmSessionSnapshot and ns.State.GetGoldFarmSessionSnapshot() or {}

  local activeEval = (ns.Domain and ns.Domain.GoldFarms and ns.Domain.GoldFarms.Evaluate)
      and ns.Domain.GoldFarms.Evaluate(catalog, progress)
    or nil
  local activeFarm = (activeEval and activeEval.farm) or (catalog.farms and catalog.farms[1]) or nil
  local gphReport = (ns.Domain and ns.Domain.GoldFarms and ns.Domain.GoldFarms.EvaluateGPHAndMountETA)
      and ns.Domain.GoldFarms.EvaluateGPHAndMountETA(activeFarm, sessSnap, mt)
    or {}

  local warningsByFarmID = {}
  if ns.Domain and ns.Domain.GoldFarms and ns.Domain.GoldFarms.GetReservationWarningsForFarm then
    for _, f in ipairs(catalog.farms or {}) do
      warningsByFarmID[f.farmID] = ns.Domain.GoldFarms.GetReservationWarningsForFarm(f)
    end
  end

  local navStatus = ns.UI and ns.UI.Navigation and ns.UI.Navigation.lastStatus or nil
  local navContext = ns.UI and ns.UI.Navigation and ns.UI.Navigation.activeContext or nil

  return {
    catalog = catalog,
    progress = {
      mode = progress.mode or "paused",
      selectedFarmID = progress.selectedFarmID,
      currentStepID = progress.currentStepID,
      manualPinnedStepID = progress.manualPinnedStepID,
    },
    mountTracker = mt,
    sessionSnap = sessSnap,
    activeEval = activeEval,
    gphReport = gphReport,
    warningsByFarmID = warningsByFarmID,
    navLabel = (navContext == "gold_farm" and navStatus and navStatus.navigationLabel) or nil,
  }
end

function GoldFarmsPresenter.Build(snapshot, uiState)
  snapshot = type(snapshot) == "table" and snapshot or GoldFarmsPresenter.CaptureSnapshot()
  local goldView = (type(uiState) == "table" and type(uiState.goldView) == "table") and uiState.goldView or {}
  local expandedByFarmID = type(goldView.expandedByFarmID) == "table" and goldView.expandedByFarmID or {}

  local catalog = snapshot.catalog or { farms = {} }
  local prog = snapshot.progress or { mode = "paused" }
  local mt = snapshot.mountTracker or {}
  local sess = snapshot.sessionSnap or {}
  local rep = snapshot.gphReport or {}
  local activeEval = snapshot.activeEval

  -- Determine single highlighted/selected farm so ONLY ONE row ever gets the gold primary `Navigate` button!
  local focusedFarmID = nil
  if prog.mode ~= "paused" and prog.selectedFarmID then
    focusedFarmID = prog.selectedFarmID
  elseif type(goldView.focusedFarmID) == "string" and goldView.focusedFarmID ~= "" then
    focusedFarmID = goldView.focusedFarmID
  elseif prog.selectedFarmID then
    focusedFarmID = prog.selectedFarmID
  elseif catalog.farms and catalog.farms[1] then
    focusedFarmID = catalog.farms[1].farmID
  end

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

  local kpis = {
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

  -- 2. Purse Progress Bar model (6-unit bar + explicit text labels)
  local targetC = math.max(1, tonumber(rep.targetCopper) or 900000)
  local reserveC = math.max(0, tonumber(rep.reserveCopper) or 0)
  local spendableC = (sess.moneyAvailable and type(sess.currentCopper) == "number")
      and math.max(0, math.floor(sess.currentCopper) - reserveC)
    or 0
  local frac = sess.moneyAvailable and math.max(0, math.min(1.0, spendableC / targetC)) or 0
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

  local progressSummaryLeft = sess.moneyAvailable
    and string.format(
      "Spendable toward mount: %s / %s (%d%%)",
      Theme.FormatMoney(spendableC, { plainText = true }),
      Theme.FormatMoney(targetC, { plainText = true }),
      pct
    )
    or "Spendable toward mount: Purse unavailable"

  -- 3. Farm Cards
  local farmsVM = {}
  for idx, farm in ipairs(catalog.farms or {}) do
    local fid = tostring(farm.farmID)
    local isActiveNav = (prog.mode ~= "paused" and prog.selectedFarmID == fid)
    local isFocused = (fid == focusedFarmID)
    local isExpanded = (expandedByFarmID[fid] == true) or isActiveNav
    local gphMeta = farm.gphMeta or {}
    local warnings = (snapshot.warningsByFarmID and snapshot.warningsByFarmID[fid]) or {}

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
      table.insert(hops, {
        index = sIdx,
        stepID = st.stepID,
        kind = st.kind,
        title = tostring(st.title or st.stepID) .. coordLabel,
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

    table.insert(farmsVM, {
      index = idx,
      farmID = fid,
      candidateOrder = tonumber(farm.candidateOrder or farm.rank) or idx,
      title = tostring(farm.title or fid),
      zoneAndLevel = string.format("%s · Lv %s", tostring(farm.zoneName or ""), tostring(farm.recommendedLevelRange or "40")),
      iconItemID = iconItemID,
      metaLine1 = summarizeTargetsLine(farm),
      metaLine2 = string.format(
        "%s · Community est. %d–%dg/hr (unverified)",
        tostring(farm.mageSafety or "Mage Candidate"),
        tonumber(gphMeta.lowGold) or 0,
        tonumber(gphMeta.highGold) or 0
      ),
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
    kpis = kpis,
    progressFraction = frac,
    progressLeftText = progressSummaryLeft,
    progressRightText = silkNote or (quoteConfirmed and "Trainer quote confirmed" or "Confirm quote at riding trainer"),
    quoteConfirmed = quoteConfirmed,
    targetCopper = targetC,
    reserveCopper = reserveC,
    isAnyGoldNavActive = isAnyGoldNavActive,
    activeNavLabel = snapshot.navLabel or (isAnyGoldNavActive and "Active" or "Idle"),
    farms = farmsVM,
    quarantinedCount = (catalog.quarantinedFarms and #catalog.quarantinedFarms) or 0,
    tabBadge = (rep.fundingStatus == "funded" and "Funded")
      or (isAnyGoldNavActive and "Active" or ""),
  }
end

return GoldFarmsPresenter
