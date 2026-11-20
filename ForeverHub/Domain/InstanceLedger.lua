local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.Domain = ns.Domain or {}

local InstanceLedger = {}
ns.Domain.InstanceLedger = InstanceLedger

InstanceLedger.SCHEMA = "foreverhub-instance-ledger-v1"
InstanceLedger.MAX_RUNS = 32
InstanceLedger.MAX_SERIALIZED_BYTES = 24576 -- 24 KiB hard cap
InstanceLedger.LOCKOUT_CAPACITY_LABEL = "Observed admissions; remaining capacity unknown"

local MAX_SAFE_INT = 9007199254740991

local function isPositiveInt(v)
  return type(v) == "number" and v == v and v >= 1 and v <= MAX_SAFE_INT and math.floor(v) == v
end

local function isNonNegInt(v)
  return type(v) == "number" and v == v and v >= 0 and v <= MAX_SAFE_INT and math.floor(v) == v
end

local function isSignedSafeInt(v)
  return type(v) == "number" and v == v and v >= -MAX_SAFE_INT and v <= MAX_SAFE_INT and math.floor(v) == v
end

local function resolveServerEpoch(explicitEpoch)
  if isPositiveInt(explicitEpoch) then
    return explicitEpoch
  end
  if ns.Compat and type(ns.Compat.GetDualClockNow) == "function" then
    local c = ns.Compat.GetDualClockNow()
    if type(c) == "table" and isPositiveInt(tonumber(c.serverEpoch)) then
      return math.floor(tonumber(c.serverEpoch))
    end
  end
  if type(_G.GetServerTime) == "function" then
    local ok, t = pcall(_G.GetServerTime)
    if ok and isPositiveInt(tonumber(t)) then
      return math.floor(tonumber(t))
    end
  end
  return 0
end

local function estimateRunBytes(run)
  local base = 240 + string.len(tostring(run.instanceName or "")) + string.len(tostring(run.characterKey or ""))
  for k, _ in pairs(run.unsoldLootByItemKey or {}) do
    base = base + 64 + string.len(tostring(k))
  end
  return base
end

function InstanceLedger.EnsureInitialized()
  local host = nil
  if ns.State and type(ns.State.GetDB) == "function" then
    local ok, db = pcall(ns.State.GetDB)
    if ok and type(db) == "table" then
      host = db
    end
  end
  if not host then
    InstanceLedger.__ephemeralHost = InstanceLedger.__ephemeralHost or {}
    host = InstanceLedger.__ephemeralHost
  end

  if type(host.instanceLedger) ~= "table" or host.instanceLedger.schema ~= InstanceLedger.SCHEMA then
    host.instanceLedger = {
      schema = InstanceLedger.SCHEMA,
      nextRunSeq = 1,
      lockoutState = "UNKNOWN_HISTORY",
      claimsExactAccountLockoutCapacity = false,
      lockoutCapacityLabel = InstanceLedger.LOCKOUT_CAPACITY_LABEL,
      observedSessionAdmissions = 0,
      lastCharacterKey = nil,
      preEntryHasUnrepairedDamage = nil,
      interveningOutsideCombatSinceExit = false,
      activeRunID = nil,
      runs = {},
      estimatedBytes = 128,
    }
  end

  local store = host.instanceLedger
  store.runs = type(store.runs) == "table" and store.runs or {}
  store.claimsExactAccountLockoutCapacity = false
  store.lockoutCapacityLabel = InstanceLedger.LOCKOUT_CAPACITY_LABEL
  return store
end

local function trimLedgerBounds(store)
  while #store.runs > InstanceLedger.MAX_RUNS do
    local removed = table.remove(store.runs, 1)
    if removed and store.activeRunID == removed.runID then
      store.activeRunID = nil
    end
  end
  while true do
    local totalBytes = 128
    for _, r in ipairs(store.runs) do
      totalBytes = totalBytes + estimateRunBytes(r)
    end
    store.estimatedBytes = totalBytes
    if totalBytes <= InstanceLedger.MAX_SERIALIZED_BYTES or #store.runs <= 1 then
      break
    end
    local removed = table.remove(store.runs, 1)
    if removed and store.activeRunID == removed.runID then
      store.activeRunID = nil
    end
  end
end

local function findRunByID(store, runID)
  if not runID then
    return nil
  end
  for _, r in ipairs(store.runs) do
    if r.runID == runID then
      return r
    end
  end
  return nil
end

local function recomputeRunDerivedTotals(run)
  local unsoldSum = 0
  local unsoldComplete = true
  for _, lot in pairs(run.unsoldLootByItemKey or {}) do
    local q = tonumber(lot.quantity) or 0
    if q > 0 then
      if lot.vendorKnown == true and isNonNegInt(tonumber(lot.unitVendorCopper)) then
        unsoldSum = unsoldSum + (q * math.floor(tonumber(lot.unitVendorCopper)))
      else
        unsoldComplete = false
      end
    end
  end
  run.unsoldLootVendorComplete = unsoldComplete
  run.unsoldLootVendorCopper = unsoldComplete and unsoldSum or nil

  -- Astra P0-6 Non-Double-Counting Invariant:
  -- Unsold loot vendor value + realized loot sale proceeds + reconciled coin NEVER double-counts sold loot!
  if unsoldComplete then
    run.grossAttributableValueCopper = (run.reconciledCoinCopper or 0)
      + (run.realizedLootProceedsCopper or 0)
      + unsoldSum
    run.netAfterAttributedRepairsCopper = run.grossAttributableValueCopper - (run.attributableRepairCopper or 0)
  else
    run.grossAttributableValueCopper = nil
    run.netAfterAttributedRepairsCopper = nil
  end
end

-- ============================================================================
-- 1. Environment Classifier (`party | raid | pvp | arena | transport | none`)
-- ============================================================================

function InstanceLedger.ClassifyEnvironment(ctx)
  ctx = type(ctx) == "table" and ctx or {}
  if ctx.isOnTransport == true then
    return {
      category = "transport",
      isDungeonOrRaid = false,
      instanceType = "transport",
    }
  end

  local inInst = ctx.inInstance
  local instType = ctx.instanceType
  local instName = ctx.instanceName
  local instMapID = tonumber(ctx.instanceMapID)

  local isSecret = ns.Compat and ns.Compat.IsSecretOrRestrictedValue
  if inInst == nil and type(_G.IsInInstance) == "function" then
    local okI, bIn, iType = pcall(_G.IsInInstance)
    if okI and not (isSecret and isSecret(bIn)) then
      inInst = (bIn == true or bIn == 1)
      if not (isSecret and isSecret(iType)) and type(iType) == "string" then
        instType = instType or iType
      end
    end
  end
  if (instName == nil or instMapID == nil) and type(_G.GetInstanceInfo) == "function" then
    local okG, r1_name, r2_iType, _r3_diffID, _r4_diffName, _r5_maxPlayers, _r6_dynDiff, _r7_isDyn, r8_instanceID, r9_instanceGroupSize =
      pcall(_G.GetInstanceInfo)
    if okG then
      if instName == nil and not (isSecret and isSecret(r1_name)) and type(r1_name) == "string" then
        instName = r1_name
      end
      if instType == nil and not (isSecret and isSecret(r2_iType)) and type(r2_iType) == "string" then
        instType = r2_iType
      end
      if instMapID == nil and not (isSecret and isSecret(r8_instanceID)) and type(r8_instanceID) == "number" then
        instMapID = tonumber(r8_instanceID)
      end
      -- Preserve distinct return #9 (`instanceGroupSize`) for diagnostic inspection only (never substituted for `instanceID`!):
      ctx._observedGroupSizeReturn9 = (not (isSecret and isSecret(r9_instanceGroupSize)) and type(r9_instanceGroupSize) == "number")
        and r9_instanceGroupSize
        or nil
    end
  end

  local safeInstType = (not (isSecret and isSecret(instType)) and type(instType) == "string") and instType or "none"
  local normType = string.lower(safeInstType)
  if not inInst or normType == "none" or normType == "" then
    return {
      category = "none",
      isDungeonOrRaid = false,
      instanceType = "none",
    }
  end
  if normType == "pvp" or normType == "arena" or normType == "scenario" then
    return {
      category = normType,
      isDungeonOrRaid = false,
      instanceType = normType,
      instanceName = instName,
      instanceMapID = instMapID,
    }
  end
  if normType == "party" or normType == "raid" then
    local hasIdentity = isPositiveInt(instMapID) or (type(instName) == "string" and instName ~= "")
    return {
      category = normType,
      isDungeonOrRaid = true,
      hasIdentity = hasIdentity,
      instanceType = normType,
      instanceName = (type(instName) == "string" and instName ~= "") and instName or nil,
      instanceMapID = isPositiveInt(instMapID) and instMapID or nil,
      identityKey = isPositiveInt(instMapID) and ("map:" .. tostring(instMapID)) or ("name:" .. tostring(instName or "unknown")),
    }
  end
  return {
    category = "unknown",
    isDungeonOrRaid = false,
    instanceType = normType,
  }
end

-- ============================================================================
-- 2. Lockout & Run Observation State Machine (`P0-5`, `P0-6`)
-- ============================================================================

local function flushActiveTimerSegment(run, nowEpoch)
  if not run or not run.activeSegmentStartedAt or not isPositiveInt(nowEpoch) then
    return
  end
  local delta = math.max(0, nowEpoch - run.activeSegmentStartedAt)
  -- Cap single uncheckpointed clock jump at 4h so offline/sleep gaps never fabricate active hours:
  delta = math.min(delta, 14400)
  run.activeInstanceSeconds = (run.activeInstanceSeconds or 0) + delta
  run.activeSegmentStartedAt = nowEpoch
  if isPositiveInt(run.startedAtEpoch) then
    run.fullTripSeconds = math.max(run.activeInstanceSeconds, math.min(86400, math.max(0, nowEpoch - run.startedAtEpoch)))
  end
end

function InstanceLedger.RecordDurabilityBaseline(hasUnrepairedDamage)
  local store = InstanceLedger.EnsureInitialized()
  if type(hasUnrepairedDamage) == "boolean" then
    store.preEntryHasUnrepairedDamage = hasUnrepairedDamage
  end
  return store.preEntryHasUnrepairedDamage
end

function InstanceLedger.RecordOutsideCombatActivity()
  local store = InstanceLedger.EnsureInitialized()
  if store.lockoutState ~= "INSIDE_OBSERVED_RUN" then
    store.interveningOutsideCombatSinceExit = true
  else
    local active = findRunByID(store, store.activeRunID)
    if active then
      active.hadRunActivity = true
    end
  end
end

function InstanceLedger.ObserveResetSignal(signalKind)
  local store = InstanceLedger.EnsureInitialized()
  local kind = tostring(signalKind or "self_call")
  -- Reset attempts ALONE NEVER increment `observedSessionAdmissions` (`P0-5`)!
  if kind == "system_confirm" then
    store.lockoutState = "RESET_CONFIRMED_WHERE_SUPPORTED"
    local active = findRunByID(store, store.activeRunID)
    if active then
      active.closedByReset = true
    end
    store.activeRunID = nil
    if ns.Domain and ns.Domain.SunkenTempleCoach and type(ns.Domain.SunkenTempleCoach.ObserveConfirmedReset) == "function" then
      pcall(ns.Domain.SunkenTempleCoach.ObserveConfirmedReset)
    end
  elseif kind == "party_leader_ambiguous" then
    store.lockoutState = "RESET_ATTEMPT_OBSERVED"
    store.pendingAmbiguousReset = true
  else
    store.lockoutState = "RESET_ATTEMPT_OBSERVED"
    store.pendingResetAttempt = true
  end
  return store.lockoutState
end

function InstanceLedger.ObserveAdmissionDenied(reason)
  local store = InstanceLedger.EnsureInitialized()
  store.lockoutState = "ADMISSION_DENIED"
  store.lastDeniedReason = tostring(reason or "instance_admission_denied")
  return store.lockoutState
end

function InstanceLedger.ObserveTransition(ctx)
  ctx = type(ctx) == "table" and ctx or {}
  local store = InstanceLedger.EnsureInitialized()
  local nowEpoch = resolveServerEpoch(ctx.nowEpoch)
  local charKey = tostring(ctx.characterKey or (ns.Compat and ns.Compat.GetPlayerKey and ns.Compat.GetPlayerKey()) or "CurrentCharacter")

  -- Character switch / observation gap resets certainty to `UNKNOWN_HISTORY`:
  if store.lastCharacterKey ~= nil and store.lastCharacterKey ~= charKey then
    local prevRun = findRunByID(store, store.activeRunID)
    if prevRun and prevRun.activeSegmentStartedAt then
      flushActiveTimerSegment(prevRun, nowEpoch)
      prevRun.activeSegmentStartedAt = nil
    end
    store.activeRunID = nil
    store.lockoutState = "UNKNOWN_HISTORY"
    store.pendingAmbiguousReset = true
  end
  store.lastCharacterKey = charKey

  if type(ctx.hasUnrepairedDamageBeforeEntry) == "boolean" and store.lockoutState ~= "INSIDE_OBSERVED_RUN" then
    store.preEntryHasUnrepairedDamage = ctx.hasUnrepairedDamageBeforeEntry
  end

  local env = InstanceLedger.ClassifyEnvironment(ctx)
  local activeRun = findRunByID(store, store.activeRunID)

  -- Case 1: Outside dungeon/raid (`none`, `pvp`, `arena`, `transport`):
  if not env.isDungeonOrRaid then
    if activeRun then
      if activeRun.activeSegmentStartedAt then
        flushActiveTimerSegment(activeRun, nowEpoch)
        activeRun.activeSegmentStartedAt = nil
      end
      if isPositiveInt(nowEpoch) and isPositiveInt(activeRun.startedAtEpoch) then
        activeRun.fullTripSeconds = math.max(activeRun.activeInstanceSeconds or 0, math.min(86400, math.max(0, nowEpoch - activeRun.startedAtEpoch)))
      end
      activeRun.isInsideNow = false
      activeRun.lastOutsideReason = (ctx.isGhostOrCorpseRun == true) and "corpse_run" or env.category
      if store.lockoutState ~= "RESET_ATTEMPT_OBSERVED" and store.lockoutState ~= "RESET_CONFIRMED_WHERE_SUPPORTED" and store.lockoutState ~= "ADMISSION_DENIED" then
        store.lockoutState = "OUTSIDE_WITH_REENTRY_CANDIDATE"
      end
    else
      if store.lockoutState == "UNKNOWN_HISTORY" then
        store.lockoutState = "OUTSIDE"
      end
    end
    return {
      lockoutState = store.lockoutState,
      lockoutCapacityLabel = store.lockoutCapacityLabel,
      claimsExactAccountLockoutCapacity = false,
      environmentCategory = env.category,
      activeRunID = store.activeRunID,
    }
  end

  -- Case 2: Inside a `party` or `raid` instance, but identity is missing/pending:
  if not env.hasIdentity then
    store.lockoutState = "ENTRY_IDENTITY_UNKNOWN"
    return {
      lockoutState = store.lockoutState,
      lockoutCapacityLabel = store.lockoutCapacityLabel,
      claimsExactAccountLockoutCapacity = false,
      environmentCategory = env.category,
      activeRunID = store.activeRunID,
    }
  end

  -- Case 3: Duplicate zone/floor transition inside the SAME active run (`coalesced`!):
  if activeRun
    and activeRun.identityKey == env.identityKey
    and activeRun.closedByReset ~= true
    and store.lockoutState ~= "RESET_CONFIRMED_WHERE_SUPPORTED"
    and store.pendingResetAttempt ~= true
  then
    if activeRun.isInsideNow == true then
      -- Internal floor change or burst `ZONE_CHANGED_NEW_AREA` / `PLAYER_ENTERING_WORLD`: coalesce!
      flushActiveTimerSegment(activeRun, nowEpoch)
    else
      -- Re-entering the SAME copy after corpse run / brief portal-out without reset: resume WITHOUT incrementing admissions!
      activeRun.isInsideNow = true
      activeRun.activeSegmentStartedAt = isPositiveInt(nowEpoch) and nowEpoch or nil
      activeRun.reentryCount = (activeRun.reentryCount or 0) + 1
      if store.pendingAmbiguousReset then
        activeRun.copyIdentityCertainty = "UNCERTAIN_PARTY_OR_RELOG"
      end
    end
    store.lockoutState = "INSIDE_OBSERVED_RUN"
    return {
      lockoutState = store.lockoutState,
      lockoutCapacityLabel = store.lockoutCapacityLabel,
      claimsExactAccountLockoutCapacity = false,
      environmentCategory = env.category,
      activeRunID = activeRun.runID,
      resumedExistingRun = true,
    }
  end

  -- Case 4: New observed dungeon/raid run admission!
  if activeRun and activeRun.activeSegmentStartedAt then
    flushActiveTimerSegment(activeRun, nowEpoch)
    activeRun.activeSegmentStartedAt = nil
    activeRun.isInsideNow = false
  end

  local certainty = "OBSERVED_ENTRY"
  if store.lockoutState == "RESET_CONFIRMED_WHERE_SUPPORTED" then
    certainty = "CONFIRMED_POST_RESET"
  elseif store.pendingAmbiguousReset or store.pendingResetAttempt then
    certainty = "UNCERTAIN_POST_RESET_OR_GAP"
  end
  store.pendingResetAttempt = false
  store.pendingAmbiguousReset = false
  store.interveningOutsideCombatSinceExit = false

  local runID = "run_" .. tostring(store.nextRunSeq or 1)
  store.nextRunSeq = (store.nextRunSeq or 1) + 1
  store.observedSessionAdmissions = (store.observedSessionAdmissions or 0) + 1

  local newRun = {
    runID = runID,
    characterKey = charKey,
    instanceType = env.instanceType,
    instanceName = env.instanceName or ("Instance #" .. tostring(env.instanceMapID or 0)),
    instanceMapID = env.instanceMapID,
    identityKey = env.identityKey,
    copyIdentityCertainty = certainty,
    startedAtEpoch = nowEpoch,
    activeSegmentStartedAt = isPositiveInt(nowEpoch) and nowEpoch or nil,
    activeInstanceSeconds = 0,
    fullTripSeconds = 0,
    isInsideNow = true,
    reentryCount = 0,
    hadPreRunUnrepairedDamage = (store.preEntryHasUnrepairedDamage ~= false), -- fail-closed if baseline wasn't observed clean (`false`)!
    hadRunActivity = true,
    reconciledCoinCopper = 0,
    unsoldLootByItemKey = {},
    unsoldLootVendorCopper = 0,
    unsoldLootVendorComplete = true,
    realizedLootProceedsCopper = 0,
    attributableRepairCopper = 0,
    unattributedRepairCopper = 0,
    guildRepairExcludedCopper = 0,
    unexplainedPurseDeltaCopper = 0,
    grossAttributableValueCopper = 0,
    netAfterAttributedRepairsCopper = 0,
  }
  table.insert(store.runs, newRun)
  store.activeRunID = runID
  store.lockoutState = "INSIDE_OBSERVED_RUN"
  trimLedgerBounds(store)

  return {
    lockoutState = store.lockoutState,
    lockoutCapacityLabel = store.lockoutCapacityLabel,
    claimsExactAccountLockoutCapacity = false,
    environmentCategory = env.category,
    activeRunID = runID,
    resumedExistingRun = false,
  }
end

-- ============================================================================
-- 3. Non-Double-Counting Run Coin, Loot, Sale Realization & Repair Attribution (`P0-6`)
-- ============================================================================

function InstanceLedger.RecordPurseDelta(deltaCopper, ctx)
  ctx = type(ctx) == "table" and ctx or {}
  local store = InstanceLedger.EnsureInitialized()
  local run = findRunByID(store, ctx.runID or store.activeRunID)
  if not run or not isSignedSafeInt(tonumber(deltaCopper)) then
    return false, "no_active_run_or_invalid_delta"
  end
  local delta = math.floor(tonumber(deltaCopper))
  if delta == 0 then
    return true, run
  end

  local nonRunWindowOpen = (ctx.nonRunWindowOpen == true)
    or (ns.State and (ns.State.mailOpen == true or ns.State.ahOpen == true or ns.State.merchantOpen == true or ns.State.tradeOpen == true or ns.State.trainerOpen == true))

  if run.isInsideNow == true and not nonRunWindowOpen and delta > 0 then
    run.reconciledCoinCopper = (run.reconciledCoinCopper or 0) + delta
  else
    run.unexplainedPurseDeltaCopper = (run.unexplainedPurseDeltaCopper or 0) + delta
  end
  recomputeRunDerivedTotals(run)
  return true, run
end

-- Records positive net loot additions only (bag slot moves/stack splits have `netDelta == 0` and are ignored!).
function InstanceLedger.RecordAttributableLoot(lootItem, ctx)
  ctx = type(ctx) == "table" and ctx or {}
  local store = InstanceLedger.EnsureInitialized()
  local run = findRunByID(store, ctx.runID or store.activeRunID)
  if not run or type(lootItem) ~= "table" then
    return false, "no_active_run_or_invalid_loot"
  end

  local nonRunWindowOpen = (ctx.nonRunWindowOpen == true)
    or (ns.State and (ns.State.mailOpen == true or ns.State.ahOpen == true or ns.State.merchantOpen == true or ns.State.tradeOpen == true))
  if run.isInsideNow ~= true or nonRunWindowOpen then
    return false, "loot_outside_clean_instance_window"
  end

  local netDeltaQty = tonumber(lootItem.netBagDeltaQuantity or lootItem.quantity)
  if not isPositiveInt(netDeltaQty) then
    return false, "zero_or_negative_net_bag_delta_ignored"
  end

  local itemID = tonumber(lootItem.itemID)
  local itemKey = tostring(lootItem.itemKey or (isPositiveInt(itemID) and string.format("i1:base:%d", itemID) or ""))
  if itemKey == "" or string.find(itemKey, "^i1:unk_var:") then
    return false, "ambiguous_item_key"
  end

  local vendorKnown = (lootItem.vendorKnown == true) and isNonNegInt(tonumber(lootItem.unitVendorCopper))
  local unitVendor = vendorKnown and math.floor(tonumber(lootItem.unitVendorCopper)) or nil

  local bucket = run.unsoldLootByItemKey[itemKey]
  if not bucket then
    bucket = {
      itemID = itemID,
      itemKey = itemKey,
      quantity = 0,
      vendorKnown = vendorKnown,
      unitVendorCopper = unitVendor,
    }
    run.unsoldLootByItemKey[itemKey] = bucket
  else
    if not vendorKnown then
      bucket.vendorKnown = false
      bucket.unitVendorCopper = nil
    end
  end
  bucket.quantity = bucket.quantity + netDeltaQty
  recomputeRunDerivedTotals(run)
  trimLedgerBounds(store)
  return true, run
end

-- Transitions sold run loot OUT of `unsoldLootByItemKey` and INTO `realizedLootProceedsCopper` (`P0-6` zero double-counting!):
function InstanceLedger.ReconcileLootRealization(itemKey, quantitySold, netProceedsCopper, ctx)
  ctx = type(ctx) == "table" and ctx or {}
  local store = InstanceLedger.EnsureInitialized()
  local key = tostring(itemKey or "")
  local qty = tonumber(quantitySold)
  local proceeds = tonumber(netProceedsCopper)
  if key == "" or not isPositiveInt(qty) or not isNonNegInt(proceeds) then
    return false, "invalid_realization_inputs"
  end

  local run = findRunByID(store, ctx.runID or store.activeRunID)
  if not run then
    -- Match most recent run holding unsold units of `itemKey` if `runID` omitted:
    for i = #store.runs, 1, -1 do
      local candidate = store.runs[i]
      local b = candidate.unsoldLootByItemKey and candidate.unsoldLootByItemKey[key]
      if b and (tonumber(b.quantity) or 0) > 0 then
        run = candidate
        break
      end
    end
  end
  if not run or not run.unsoldLootByItemKey or not run.unsoldLootByItemKey[key] then
    return false, "no_attributable_unsold_run_loot"
  end

  local bucket = run.unsoldLootByItemKey[key]
  local matchedQty = math.min(qty, tonumber(bucket.quantity) or 0)
  if matchedQty <= 0 then
    return false, "zero_unsold_units_remaining"
  end

  local allocatedProceeds = (matchedQty == qty)
      and proceeds
    or math.floor((proceeds * matchedQty) / qty)

  bucket.quantity = bucket.quantity - matchedQty
  if bucket.quantity <= 0 then
    run.unsoldLootByItemKey[key] = nil
  end
  run.realizedLootProceedsCopper = (run.realizedLootProceedsCopper or 0) + allocatedProceeds
  recomputeRunDerivedTotals(run)
  return true, {
    runID = run.runID,
    matchedQuantity = matchedQty,
    allocatedProceedsCopper = allocatedProceeds,
    remainingUnsoldVendorCopper = run.unsoldLootVendorCopper,
    realizedLootProceedsCopper = run.realizedLootProceedsCopper,
    grossAttributableValueCopper = run.grossAttributableValueCopper,
  }
end

-- Durability-baseline repair attribution (`P0-6`):
function InstanceLedger.RecordRepairExpense(repairCopper, usedGuildBank, ctx)
  ctx = type(ctx) == "table" and ctx or {}
  local store = InstanceLedger.EnsureInitialized()
  local amt = tonumber(repairCopper)
  if not isPositiveInt(amt) then
    return false, "invalid_repair_copper"
  end

  local run = findRunByID(store, ctx.runID or store.activeRunID)
  if not run and #store.runs > 0 then
    run = store.runs[#store.runs]
  end
  if not run then
    return false, "no_recorded_run"
  end

  if usedGuildBank == true then
    run.guildRepairExcludedCopper = (run.guildRepairExcludedCopper or 0) + amt
    return true, { attribution = "GUILD_BANK_EXCLUDED", runID = run.runID }
  end

  local cleanPreBaseline = (run.hadPreRunUnrepairedDamage == false)
  local noOutsideCombat = (store.interveningOutsideCombatSinceExit ~= true) and (ctx.hadInterveningOutsideCombat ~= true)

  if cleanPreBaseline and noOutsideCombat and run.hadRunActivity == true then
    run.attributableRepairCopper = (run.attributableRepairCopper or 0) + amt
    -- Once repaired cleanly, reset baseline to clean (`false`) for next run!
    store.preEntryHasUnrepairedDamage = false
    recomputeRunDerivedTotals(run)
    return true, { attribution = "ATTRIBUTED_CLEAN_BASELINE", runID = run.runID, attributableRepairCopper = run.attributableRepairCopper }
  end

  run.unattributedRepairCopper = (run.unattributedRepairCopper or 0) + amt
  store.preEntryHasUnrepairedDamage = false
  recomputeRunDerivedTotals(run)
  return true, {
    attribution = "UNATTRIBUTED_MIXED_DURABILITY_BASELINE",
    runID = run.runID,
    unattributedRepairCopper = run.unattributedRepairCopper,
  }
end

function InstanceLedger.GetSummarySnapshot(nowEpoch)
  local store = InstanceLedger.EnsureInitialized()
  local ep = resolveServerEpoch(nowEpoch)
  local active = findRunByID(store, store.activeRunID)
  if active and active.isInsideNow and active.activeSegmentStartedAt and isPositiveInt(ep) then
    flushActiveTimerSegment(active, ep)
  end
  return {
    lockoutState = store.lockoutState,
    lockoutCapacityLabel = InstanceLedger.LOCKOUT_CAPACITY_LABEL,
    claimsExactAccountLockoutCapacity = false,
    observedSessionAdmissions = store.observedSessionAdmissions or 0,
    activeRunID = store.activeRunID,
    runCount = #store.runs,
    estimatedBytes = store.estimatedBytes or 128,
    runs = store.runs,
  }
end

return InstanceLedger
