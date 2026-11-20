local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.Domain = ns.Domain or {}

local Reserves = {}
ns.Domain.Reserves = Reserves

local DEFAULT_MOUNT_TARGET_COPPER = 900000 -- 90g Forever discounted basic riding + mount default

local function safeFloorNonNeg(v)
  local n = tonumber(v)
  if not n or n ~= n or n == math.huge or n == -math.huge or n < 0 then
    return 0
  end
  return math.floor(n)
end

function Reserves.GetSpellTrainingBufferCopper(level)
  local lvl = math.max(1, safeFloorNonNeg(level))
  if lvl >= 60 then
    return 0
  elseif lvl >= 50 then
    return 150000 -- 15g
  elseif lvl >= 38 then
    return 80000 -- 8g
  elseif lvl >= 26 then
    return 35000 -- 3g 50s
  elseif lvl >= 14 then
    return 10000 -- 1g
  elseif lvl >= 6 then
    return 1500 -- 15s
  end
  return 100 -- 1s starter training buffer
end

function Reserves.GetOperatingFloatCopper(level)
  local lvl = math.max(1, safeFloorNonNeg(level))
  if lvl >= 60 then
    return 50000 -- 5g repair / flight / deposit float
  elseif lvl >= 40 then
    return 20000 -- 2g
  elseif lvl >= 20 then
    return 5000 -- 50s
  elseif lvl >= 10 then
    return 1000 -- 10s
  end
  return 50 -- 50c starter repair/flight float
end

function Reserves.GetMountSavingsWeightBps(level, hasBasicMount)
  if hasBasicMount == true then
    return 0
  end
  local lvl = math.max(1, safeFloorNonNeg(level))
  if lvl >= 36 then
    return 10000 -- 100% protection in Lv 36+ mount window until basic riding is owned
  elseif lvl >= 34 then
    return 6500 -- 65%
  elseif lvl >= 30 then
    return 3500 -- 35%
  elseif lvl >= 25 then
    return 1500 -- 15%
  end
  return 0
end

function Reserves.ResolveHasBasicMount(opts, mountTracker)
  if type(opts) == "table" and type(opts.hasBasicMount) == "boolean" then
    return opts.hasBasicMount
  end
  if type(mountTracker) == "table" and type(mountTracker.hasBasicMount) == "boolean" then
    return mountTracker.hasBasicMount
  end
  -- Characters at level >= 42 without an active unmounted override only skip mount lock when confirmed;
  -- default conservatively to false unless explicitly confirmed or level >= 60 with no mount tracker shortfall.
  if type(_G.IsMounted) == "function" then
    local ok, mounted = pcall(_G.IsMounted)
    if ok and mounted == true then
      if type(mountTracker) == "table" then
        mountTracker.hasBasicMount = true
      end
      return true
    end
  end
  return false
end

function Reserves.EvaluateCharacterReserves(opts)
  opts = type(opts) == "table" and opts or {}

  local level = tonumber(opts.level)
  if not level then
    level = (ns.Compat and ns.Compat.GetPlayerLevel and ns.Compat.GetPlayerLevel()) or 1
  end
  level = math.max(1, safeFloorNonNeg(level))

  local mt = opts.mountTracker
  if type(mt) ~= "table" and ns.State and type(ns.State.GetMountTracker) == "function" then
    mt = ns.State.GetMountTracker()
  end
  mt = type(mt) == "table" and mt or {}

  local hasBasicMount = Reserves.ResolveHasBasicMount(opts, mt)
  local mountTargetCopper = DEFAULT_MOUNT_TARGET_COPPER
  if opts.trainerQuoteCopper ~= nil then
    mountTargetCopper = safeFloorNonNeg(opts.trainerQuoteCopper)
  elseif mt.trainerQuoteCopper ~= nil then
    mountTargetCopper = safeFloorNonNeg(mt.trainerQuoteCopper)
  end

  local explicitUserReserveCopper = 0
  if opts.explicitUserReserveCopper ~= nil then
    explicitUserReserveCopper = safeFloorNonNeg(opts.explicitUserReserveCopper)
  elseif mt.cashReserveCopper ~= nil then
    explicitUserReserveCopper = safeFloorNonNeg(mt.cashReserveCopper)
  end

  local mountWeightBps = Reserves.GetMountSavingsWeightBps(level, hasBasicMount)
  local mountReserveTargetCopper = math.floor((mountTargetCopper * mountWeightBps) / 10000)
  local spellTrainingBufferCopper = opts.spellTrainingBufferCopper ~= nil
      and safeFloorNonNeg(opts.spellTrainingBufferCopper)
    or Reserves.GetSpellTrainingBufferCopper(level)
  local operatingFloatCopper = opts.operatingFloatCopper ~= nil
      and safeFloorNonNeg(opts.operatingFloatCopper)
    or Reserves.GetOperatingFloatCopper(level)

  local totalReserveTargetCopper = mountReserveTargetCopper
    + spellTrainingBufferCopper
    + operatingFloatCopper
    + explicitUserReserveCopper

  local liquidCopper = nil
  local moneyStatus = "unavailable"
  if opts.liquidCopper ~= nil then
    if type(opts.liquidCopper) == "number" and opts.liquidCopper == opts.liquidCopper and opts.liquidCopper >= 0 then
      liquidCopper = math.floor(opts.liquidCopper)
      moneyStatus = "ok"
    else
      moneyStatus = tostring(opts.liquidCopper)
    end
  elseif ns.Compat and type(ns.Compat.GetPlayerMoneyCopper) == "function" then
    local mr = ns.Compat.GetPlayerMoneyCopper()
    if type(mr) == "table" and mr.status == "ok" and type(mr.copper) == "number" then
      liquidCopper = math.max(0, math.floor(mr.copper))
      moneyStatus = "ok"
    elseif type(mr) == "table" and type(mr.status) == "string" then
      moneyStatus = mr.status
    end
  end

  if moneyStatus ~= "ok" or liquidCopper == nil then
    return {
      status = "unavailable",
      moneyStatus = moneyStatus,
      level = level,
      hasBasicMount = hasBasicMount,
      liquidCopper = nil,
      mountTargetCopper = mountTargetCopper,
      mountWeightBps = mountWeightBps,
      mountReserveTargetCopper = mountReserveTargetCopper,
      mountShortfallCopper = hasBasicMount and 0 or mountTargetCopper,
      spellTrainingBufferCopper = spellTrainingBufferCopper,
      operatingFloatCopper = operatingFloatCopper,
      explicitUserReserveCopper = explicitUserReserveCopper,
      totalReserveTargetCopper = totalReserveTargetCopper,
      protectedCopperNow = 0,
      reserveShortfallCopper = totalReserveTargetCopper,
      investableCopper = 0,
      canDeployOutlay = false,
      summaryReason = "player_money_unavailable",
    }
  end

  local mountShortfallCopper = hasBasicMount and 0 or math.max(0, mountTargetCopper - liquidCopper)
  local protectedCopperNow = math.min(liquidCopper, totalReserveTargetCopper)
  local reserveShortfallCopper = math.max(0, totalReserveTargetCopper - liquidCopper)
  local investableCopper = math.max(0, liquidCopper - totalReserveTargetCopper)

  local summaryReason = "investable_surplus_available"
  if liquidCopper == 0 then
    summaryReason = "zero_liquid_copper"
  elseif investableCopper == 0 then
    if not hasBasicMount and mountReserveTargetCopper > 0 and mountShortfallCopper > 0 then
      summaryReason = "protected_for_mount_shortfall"
    elseif spellTrainingBufferCopper > 0 and liquidCopper <= (spellTrainingBufferCopper + operatingFloatCopper) then
      summaryReason = "protected_for_training_and_float"
    else
      summaryReason = "protected_by_reserve_floor"
    end
  end

  return {
    status = "ok",
    moneyStatus = "ok",
    level = level,
    hasBasicMount = hasBasicMount,
    liquidCopper = liquidCopper,
    mountTargetCopper = mountTargetCopper,
    mountWeightBps = mountWeightBps,
    mountReserveTargetCopper = mountReserveTargetCopper,
    mountShortfallCopper = mountShortfallCopper,
    spellTrainingBufferCopper = spellTrainingBufferCopper,
    operatingFloatCopper = operatingFloatCopper,
    explicitUserReserveCopper = explicitUserReserveCopper,
    totalReserveTargetCopper = totalReserveTargetCopper,
    protectedCopperNow = protectedCopperNow,
    reserveShortfallCopper = reserveShortfallCopper,
    investableCopper = investableCopper,
    canDeployOutlay = (investableCopper > 0),
    summaryReason = summaryReason,
  }
end

function Reserves.CanAffordOutlay(outlayCopper, opts)
  local req = tonumber(outlayCopper)
  if not req or req ~= req or req < 0 or math.floor(req) ~= req then
    return false, "invalid_outlay_copper", nil
  end
  local snap = Reserves.EvaluateCharacterReserves(opts)
  if snap.status ~= "ok" then
    return false, snap.summaryReason or "player_money_unavailable", snap
  end
  if req == 0 then
    return true, nil, snap
  end
  if req > snap.investableCopper then
    return false, snap.summaryReason or "exceeds_investable_after_reserves", snap
  end
  return true, nil, snap
end

return Reserves
