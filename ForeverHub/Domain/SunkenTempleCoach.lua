local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.Domain = ns.Domain or {}

local SunkenTempleCoach = {}
ns.Domain.SunkenTempleCoach = SunkenTempleCoach

SunkenTempleCoach.SCHEMA = "foreverhub-st-coach-rc1"
SunkenTempleCoach.MAX_RING_EVENTS = 64
SunkenTempleCoach.MAX_PROBE_RUNS = 8
SunkenTempleCoach.BLIZZARD_GAP_HEURISTIC_SECONDS = 10.0

local TRACKED_SPELL_KEYS = {
  "blizzard",
  "ice_barrier",
  "ice_block",
  "cold_snap",
  "frost_nova",
  "cone_of_cold",
  "dampen_magic",
  "frost_ward",
  "blink",
}

local function getMonotonicNow(explicitNow)
  if type(explicitNow) == "number" and explicitNow == explicitNow and explicitNow ~= math.huge and explicitNow ~= -math.huge then
    return explicitNow
  end
  if ns.State and type(ns.State.overrideMonotonicTime) == "number" then
    return ns.State.overrideMonotonicTime
  end
  if ns.Compat and type(ns.Compat.NowSeconds) == "function" then
    local v = ns.Compat.NowSeconds()
    if type(v) == "number" and v == v then
      return v
    end
  end
  return 0
end

local function newCoverageBucket()
  return {
    readable = 0,
    missing = 0,
    restricted = 0,
    errored = 0,
    unknown = 0,
  }
end

local function recordCoverageStatus(bucket, status)
  if type(bucket) ~= "table" then
    return
  end
  local k = tostring(status or "unknown")
  if bucket[k] ~= nil then
    bucket[k] = bucket[k] + 1
  else
    bucket.unknown = (bucket.unknown or 0) + 1
  end
end

local function formatCoverageSummary(name, bucket)
  if type(bucket) ~= "table" then
    return name .. ": unprobed"
  end
  return string.format(
    "%s(readable=%d, missing=%d, restricted=%d, errored=%d, unknown=%d)",
    tostring(name),
    bucket.readable or 0,
    bucket.missing or 0,
    bucket.restricted or 0,
    bucket.errored or 0,
    bucket.unknown or 0
  )
end

local function createFreshState()
  return {
    sessionState = "INACTIVE", -- "INACTIVE" | "READY" | "ACTIVE" | "RECOVERY"
    phaseIndex = 0,
    verifiedSunkenTemple = false,
    instanceClassification = "uninitialized",
    localizedNameHintMatched = false,
    hasObservedOutsideBeforeEntry = false,
    wasInsideVerifiedST = false,
    lastOutsideWasCorpse = false,
    requiresRearm = false,
    recoveryReason = nil,
    observedActiveRunID = nil,
    enteredCurrentCopyCount = 0,
    nextAttemptSeq = 1,
    currentAttempt = nil,
    lastAutopsy = nil,
    hudCardHidden = false,
    liveConfirmedPhases = {},
  }
end

local function createFreshProbeStore()
  return {
    registrations = {},
    observedEventSamples = {},
    runs = {},
    lastSnapshot = nil,
  }
end

-- Ephemeral in-memory state ONLY (ST-09: adds ZERO bytes to ForeverHubDB / ForeverHubCharDB).
SunkenTempleCoach.state = SunkenTempleCoach.state or createFreshState()
SunkenTempleCoach.probeStore = SunkenTempleCoach.probeStore or createFreshProbeStore()
SunkenTempleCoach.eventFrame = nil

local function getPhases()
  local data = ns.SunkenTempleData
  return (data and type(data.PHASES) == "table") and data.PHASES or {}
end

function SunkenTempleCoach.GetPhaseDefinition(phaseIndex)
  local phases = getPhases()
  local idx = tonumber(phaseIndex) or 0
  return phases[idx], #phases
end

local function notifyUIRefresh()
  if ns.UI and ns.UI.SunkenTempleCard and type(ns.UI.SunkenTempleCard.Refresh) == "function" then
    pcall(ns.UI.SunkenTempleCard.Refresh)
  end
  if ns.UI and ns.UI.GoldFarms and type(ns.UI.GoldFarms.RefreshIfShown) == "function" then
    pcall(ns.UI.GoldFarms.RefreshIfShown)
  end
end

local function newAttemptRecord(attemptID, nowMono, firstPhase)
  local spellStats = {}
  for _, sk in ipairs(TRACKED_SPELL_KEYS) do
    spellStats[sk] = {
      count = 0,
      firstOffsetSec = nil,
      lastOffsetSec = nil,
      maxGapSec = nil,
    }
  end
  local rec = {
    attemptID = attemptID,
    startedAtMono = nowMono,
    endedAtMono = nil,
    durationSec = 0,
    closed = false,
    closeCount = 0,
    outcome = "IN_PROGRESS",
    outcomeReason = nil,
    terminalPhaseIndex = 1,
    terminalPhaseID = firstPhase and firstPhase.phaseID or "APPROACH_SANCTUARY",
    terminalPhaseTitle = firstPhase and firstPhase.title or "1. Approach Sanctuary",
    -- Preserved independently of the 64-event ring so noisy pulls never erase terminal/checkpoint truth (ST-09):
    phaseConfirmations = {
      [1] = {
        phaseIndex = 1,
        phaseID = firstPhase and firstPhase.phaseID or "APPROACH_SANCTUARY",
        title = firstPhase and firstPhase.title or "1. Approach Sanctuary",
        confirmedAtOffsetSec = 0.0,
        source = "player_manual",
      },
    },
    manualPrevCorrections = 0,
    combatEnterCount = 0,
    combatExitCount = 0,
    yellObservedCount = 0,
    positiveDragonSightings = {},
    positiveDragonSightingCount = 0,
    spellStats = spellStats,
    coverage = {
      spellcasts = newCoverageBucket(),
      auras = newCoverageBucket(),
      health = newCoverageBucket(),
      subzone = newCoverageBucket(),
      yells = newCoverageBucket(),
      targetSightings = newCoverageBucket(),
    },
    maxRingCapacity = SunkenTempleCoach.MAX_RING_EVENTS,
    ring = {},
    ringWriteCursor = 1,
    totalObservedEvents = 0,
    overflowed = false,
    droppedRingEvents = 0,
  }
  return rec
end

local function appendRingAnnotation(attempt, nowMono, kind, summaryText, phaseIdx)
  if type(attempt) ~= "table" or attempt.closed == true then
    return false
  end
  local offset = math.max(0, (tonumber(nowMono) or 0) - (tonumber(attempt.startedAtMono) or 0))
  attempt.totalObservedEvents = (attempt.totalObservedEvents or 0) + 1
  local entry = {
    seq = attempt.totalObservedEvents,
    offsetSec = math.floor(offset * 10 + 0.5) / 10,
    phaseIndex = tonumber(phaseIdx) or attempt.terminalPhaseIndex or 1,
    kind = tostring(kind or "note"),
    summary = tostring(summaryText or ""),
  }
  local cap = SunkenTempleCoach.MAX_RING_EVENTS
  if #attempt.ring < cap then
    table.insert(attempt.ring, entry)
    attempt.ringWriteCursor = (#attempt.ring % cap) + 1
  else
    attempt.overflowed = true
    attempt.droppedRingEvents = (attempt.droppedRingEvents or 0) + 1
    local idx = attempt.ringWriteCursor or 1
    attempt.ring[idx] = entry
    attempt.ringWriteCursor = (idx % cap) + 1
  end
  return true
end

local function extractOrderedRingEntries(attempt)
  if type(attempt) ~= "table" or type(attempt.ring) ~= "table" then
    return {}
  end
  local n = #attempt.ring
  if n == 0 then
    return {}
  end
  if not attempt.overflowed then
    local copy = {}
    for i = 1, n do
      copy[i] = attempt.ring[i]
    end
    return copy
  end
  local out = {}
  local startIdx = attempt.ringWriteCursor or 1
  for offset = 0, n - 1 do
    local idx = ((startIdx - 1 + offset) % n) + 1
    table.insert(out, attempt.ring[idx])
  end
  return out
end

-- Builds epistemically honest 3-tier Pull Autopsy (`CONFIRMED` / `LIKELY_HEURISTIC` / `UNOBSERVABLE_IN_16001`, ST-06 & ST-09).
function SunkenTempleCoach.BuildAutopsy(attempt)
  if type(attempt) ~= "table" then
    return nil
  end
  local confirmed = {}
  local likelyHeuristics = {}
  local unobservable = {}
  local allClaims = {}

  local function pushClaim(tier, code, summary, evidence, coverage, missingLink)
    local rec = {
      tier = tier,
      code = code,
      summary = summary,
      evidence = evidence,
      coverage = coverage,
      missingLink = missingLink,
    }
    table.insert(allClaims, rec)
    if tier == "CONFIRMED" then
      table.insert(confirmed, rec)
    elseif tier == "LIKELY_HEURISTIC" then
      table.insert(likelyHeuristics, rec)
    else
      table.insert(unobservable, rec)
    end
  end

  local dur = math.max(0, tonumber(attempt.durationSec) or 0)
  local phaseLabel = tostring(attempt.terminalPhaseTitle or attempt.terminalPhaseID or "Unknown Phase")

  -- 1. CONFIRMED terminal outcome & manual checkpoint confirmations (attributed to player):
  if attempt.outcome == "DIED" then
    pushClaim(
      "CONFIRMED",
      "outcome_player_dead",
      string.format("You died during %s at +%.1fs.", phaseLabel, dur),
      "Observed PLAYER_DEAD event while attempt was active.",
      "PLAYER_DEAD delivery confirmed (100% terminal state certainty)."
    )
  elseif attempt.outcome == "PLAYER_REPORTED_COMPLETE" then
    pushClaim(
      "CONFIRMED",
      "outcome_player_complete",
      string.format("Player reported attempt complete at +%.1fs (final phase: %s).", dur, phaseLabel),
      "Player invoked manual Finish control.",
      "Player-attributed completion; kill counts and loot completeness are not independently asserted."
    )
  elseif attempt.outcome == "ABORTED" then
    pushClaim(
      "CONFIRMED",
      "outcome_aborted",
      string.format("Attempt closed as aborted during %s at +%.1fs (%s).", phaseLabel, dur, tostring(attempt.outcomeReason or "player_manual")),
      "Player manual Abort or portal exit prior to completion.",
      "Player/session transition observed directly."
    )
  end

  local cpParts = {}
  for idx = 1, 6 do
    local cp = attempt.phaseConfirmations and attempt.phaseConfirmations[idx]
    if cp then
      table.insert(cpParts, string.format("P%d@+%.1fs", idx, tonumber(cp.confirmedAtOffsetSec) or 0))
    end
  end
  if #cpParts > 0 then
    pushClaim(
      "CONFIRMED",
      "player_checkpoint_confirmations",
      string.format(
        "Player-confirmed checkpoints: %s (manual Prev corrections: %d).",
        table.concat(cpParts, ", "),
        tonumber(attempt.manualPrevCorrections) or 0
      ),
      "Manual player phase controls (Start/Next/Prev).",
      "Player-reported checkpoint timestamps; does not independently verify character coordinates."
    )
  end

  local spellCovStr = formatCoverageSummary("spellcasts", attempt.coverage and attempt.coverage.spellcasts)
  for _, sk in ipairs({ "ice_block", "cold_snap", "ice_barrier", "blizzard", "frost_nova" }) do
    local st = attempt.spellStats and attempt.spellStats[sk]
    if st and (st.count or 0) > 0 then
      pushClaim(
        "CONFIRMED",
        "observed_cast_" .. sk,
        string.format(
          "Observed %d player '%s' cast(s) (first @ +%.1fs, last @ +%.1fs).",
          st.count,
          sk,
          tonumber(st.firstOffsetSec) or 0,
          tonumber(st.lastOffsetSec) or 0
        ),
        "Readable UNIT_SPELLCAST_SUCCEEDED('player') event(s).",
        spellCovStr
      )
    end
  end

  if (attempt.positiveDragonSightingCount or 0) > 0 then
    local sightedList = {}
    for nm, firstT in pairs(attempt.positiveDragonSightings or {}) do
      table.insert(sightedList, string.format("%s (@+%.1fs)", tostring(nm), tonumber(firstT) or 0))
    end
    table.sort(sightedList)
    pushClaim(
      "CONFIRMED",
      "positive_unit_sightings",
      "Observed named unit sighting(s): " .. table.concat(sightedList, ", ") .. ".",
      "Readable target/nameplate unit identity sample.",
      formatCoverageSummary("targetSightings", attempt.coverage and attempt.coverage.targetSightings)
        .. " — sighting establishes presence at sample time ONLY, never failed reset."
    )
  end

  if attempt.overflowed then
    pushClaim(
      "CONFIRMED",
      "timeline_ring_overflow",
      string.format(
        "High-event pull: %d observations recorded; oldest %d detail ring entries rotated out (64-event cap preserved terminal header & checkpoints).",
        tonumber(attempt.totalObservedEvents) or 0,
        tonumber(attempt.droppedRingEvents) or 0
      ),
      "Bounded 64-slot ring buffer counter.",
      "Attempt start, terminal outcome, spell counters, and phase confirmations were retained outside the ring."
    )
  end

  -- 2. LIKELY_HEURISTIC: Requires POSITIVE readable observations + explicit missing-link disclosure (ST-06):
  local blizStats = attempt.spellStats and attempt.spellStats.blizzard
  if blizStats and (blizStats.count or 0) >= 2 and (tonumber(blizStats.maxGapSec) or 0) >= SunkenTempleCoach.BLIZZARD_GAP_HEURISTIC_SECONDS then
    pushClaim(
      "LIKELY_HEURISTIC",
      "blizzard_cast_gap",
      string.format(
        "Observed %.1fs maximum gap between readable player Blizzard casts (potential slow drop window).",
        tonumber(blizStats.maxGapSec) or 0
      ),
      string.format("%d readable UNIT_SPELLCAST_SUCCEEDED('player') Blizzard events.", blizStats.count),
      spellCovStr,
      "Establishes a cast-initiation gap only; cannot confirm channel completion, Blizzard ticks, targets hit, or whether enemies spent that interval unslowed."
    )
  end

  local spCov = attempt.coverage and attempt.coverage.spellcasts or {}
  local ibStats = attempt.spellStats and attempt.spellStats.ice_block
  if attempt.outcome == "DIED"
    and (spCov.readable or 0) > 0
    and (spCov.restricted or 0) == 0
    and (spCov.unknown or 0) == 0
    and (not ibStats or (ibStats.count or 0) == 0)
  then
    pushClaim(
      "LIKELY_HEURISTIC",
      "died_without_observed_ice_block",
      "Player died with zero Ice Block casts observed across an unrestricted player spellcast stream.",
      "PLAYER_DEAD + >0 readable player spellcasts with 0 restricted/unknown spellcast samples and 0 Ice Block casts.",
      spellCovStr,
      "Cannot establish whether Ice Block was on cooldown, Hypothermia was active, or fatal damage occurred during a stun/global."
    )
  end

  -- 3. UNOBSERVABLE_IN_16001: Explicit coverage & engine non-observability disclosures (ST-06):
  pushClaim(
    "UNOBSERVABLE_IN_16001",
    "dragon_leash_and_reset_unobservable",
    "Boss-dragon patrol direction, leash state, and reset completion cannot be established by ForeverHub.",
    "C++ #noinstance position lockout + target/nameplate non-exhaustiveness in Interface 16001.",
    formatCoverageSummary("targetSightings", attempt.coverage and attempt.coverage.targetSightings)
      .. " — neither sighting nor absence of Dreamscythe, Weaver, Morphaz, or Hazzas proves reset or failure."
  )

  pushClaim(
    "UNOBSERVABLE_IN_16001",
    "rp_and_eranikus_attackability_unobservable",
    "Shade of Eranikus wakeup/attackability and RP completion cannot be proven from chat or combat-end state.",
    string.format("Monster yell samples observed: %d.", tonumber(attempt.yellObservedCount) or 0),
    formatCoverageSummary("yells", attempt.coverage and attempt.coverage.yells)
      .. " — silence never proves failed RP, and a matched yell never proves attackability."
  )

  pushClaim(
    "UNOBSERVABLE_IN_16001",
    "fatal_hit_knockback_and_shield_absorb_unobservable",
    "Exact incoming damage source, knockback cause, remaining Ice Barrier absorb, and enemy kill count are unobservable.",
    "COMBAT_LOG_EVENT_UNFILTERED is excluded from required inputs; aura buffs do not expose remaining shield absorb.",
    formatCoverageSummary("auras", attempt.coverage and attempt.coverage.auras)
      .. " · " .. formatCoverageSummary("health", attempt.coverage and attempt.coverage.health)
  )

  return {
    schema = "foreverhub-st-autopsy-rc1",
    attemptID = attempt.attemptID,
    outcome = attempt.outcome,
    outcomeReason = attempt.outcomeReason,
    durationSec = dur,
    terminalPhaseIndex = attempt.terminalPhaseIndex,
    terminalPhaseID = attempt.terminalPhaseID,
    terminalPhaseTitle = attempt.terminalPhaseTitle,
    overflowed = (attempt.overflowed == true),
    totalObservedEvents = attempt.totalObservedEvents or 0,
    droppedRingEvents = attempt.droppedRingEvents or 0,
    retainedRingEntries = extractOrderedRingEntries(attempt),
    confirmed = confirmed,
    likelyHeuristics = likelyHeuristics,
    unobservable = unobservable,
    claims = allClaims,
  }
end

local function closeActiveAttemptOnce(outcome, reasonTag, explicitNow)
  local st = SunkenTempleCoach.state
  local attempt = st.currentAttempt
  if not attempt or attempt.closed == true then
    return false, "no_open_attempt"
  end
  local nowMono = getMonotonicNow(explicitNow)
  attempt.closed = true
  attempt.closeCount = (attempt.closeCount or 0) + 1
  attempt.endedAtMono = nowMono
  attempt.durationSec = math.max(0, math.floor(((nowMono - (attempt.startedAtMono or nowMono)) * 10) + 0.5) / 10)
  attempt.outcome = tostring(outcome or "ABORTED")
  attempt.outcomeReason = reasonTag and tostring(reasonTag) or nil

  local pDef = SunkenTempleCoach.GetPhaseDefinition(st.phaseIndex)
  attempt.terminalPhaseIndex = tonumber(st.phaseIndex) or attempt.terminalPhaseIndex or 1
  attempt.terminalPhaseID = (pDef and pDef.phaseID) or attempt.terminalPhaseID
  attempt.terminalPhaseTitle = (pDef and pDef.title) or attempt.terminalPhaseTitle

  st.lastAutopsy = SunkenTempleCoach.BuildAutopsy(attempt)
  return true, st.lastAutopsy
end

-- ============================================================================
-- 1. Environment & Instance Identity Gate (`P0-2`, `ST-01`, `ST-03`, `ST-07`)
-- ============================================================================

function SunkenTempleCoach.ObserveEnvironmentTransition(ctx)
  ctx = type(ctx) == "table" and ctx or {}
  local st = SunkenTempleCoach.state
  local probe = (ns.Compat and ns.Compat.ProbeSunkenTempleInstanceIdentity)
    and ns.Compat.ProbeSunkenTempleInstanceIdentity(ctx.identityOverride)
    or { verifiedSunkenTemple = false, classification = "compat_unavailable", inInstance = false }

  st.instanceClassification = probe.classification
  st.localizedNameHintMatched = (probe.localizedNameHintMatched == true)

  local ledgerRunID = ctx.ledgerActiveRunID
  if ledgerRunID == nil and ns.Domain and ns.Domain.InstanceLedger and type(ns.Domain.InstanceLedger.GetSummarySnapshot) == "function" then
    local lSnap = ns.Domain.InstanceLedger.GetSummarySnapshot()
    ledgerRunID = lSnap and lSnap.activeRunID or nil
  end

  local isCorpse = (ctx.isCorpseOrGhost == true)
    or (ns.UI and ns.UI.Navigation and ns.UI.Navigation.IsPlayerCorpseOrGhost and ns.UI.Navigation.IsPlayerCorpseOrGhost())
    or false

  -- Case A: Verified inside Sunken Temple (`instanceType == "party"` and `return8 == 109`):
  if probe.verifiedSunkenTemple == true then
    if ns.UI and ns.UI.Navigation and type(ns.UI.Navigation.OnInstancePortalEntry) == "function" then
      ns.UI.Navigation.OnInstancePortalEntry()
    end
    st.verifiedSunkenTemple = true

    -- Internal floor/subzone transition inside the SAME active run (`ST-07` coalescing!):
    if st.wasInsideVerifiedST == true then
      local runChangedWhileInside = (ledgerRunID ~= nil and st.observedActiveRunID ~= nil and ledgerRunID ~= st.observedActiveRunID)
      if not runChangedWhileInside then
        SunkenTempleCoach.AnnotateSubZoneSample(ctx.nowMono)
        notifyUIRefresh()
        return st.sessionState, "coalesced_in_instance"
      end
      -- Copy identity changed across a reset: never carry an active phase into another copy!
      if st.sessionState == "ACTIVE" then
        closeActiveAttemptOnce("ABORTED", "instance_copy_changed", ctx.nowMono)
      end
      st.currentAttempt = nil
      st.phaseIndex = 0
      st.observedActiveRunID = ledgerRunID
      st.enteredCurrentCopyCount = 1
      st.requiresRearm = true
      st.recoveryReason = "copy_changed_requires_rearm"
      st.sessionState = "RECOVERY"
      notifyUIRefresh()
      return st.sessionState, "copy_changed_recovery"
    end

    -- Fresh transition into Sunken Temple (`wasInsideVerifiedST == false` -> `true`):
    st.wasInsideVerifiedST = true
    local sameCopyReentry = (ctx.resumedExistingRun == true)
      or (ledgerRunID ~= nil and st.observedActiveRunID ~= nil and ledgerRunID == st.observedActiveRunID)
      or (ledgerRunID == nil and st.enteredCurrentCopyCount >= 1 and st.pendingConfirmedReset ~= true)

    st.pendingConfirmedReset = false
    if ledgerRunID ~= nil and ledgerRunID ~= st.observedActiveRunID then
      st.observedActiveRunID = ledgerRunID
      st.enteredCurrentCopyCount = 1
    else
      st.enteredCurrentCopyCount = (st.enteredCurrentCopyCount or 0) + 1
    end

    -- Gate ST-07: Mid-pull `/reload` (booting already inside ST without prior outside observation),
    -- corpse/ghost re-entry, or same-copy re-entry MUST enter `RECOVERY` and require explicit `RearmCoach()`.
    if st.hasObservedOutsideBeforeEntry ~= true then
      st.phaseIndex = 0
      st.requiresRearm = true
      st.recoveryReason = "reload_or_login_inside_instance"
      st.sessionState = "RECOVERY"
      notifyUIRefresh()
      return st.sessionState, st.recoveryReason
    end

    if isCorpse or st.lastOutsideWasCorpse == true or st.requiresRearm == true or sameCopyReentry then
      st.phaseIndex = 0
      st.requiresRearm = true
      st.recoveryReason = (isCorpse or st.lastOutsideWasCorpse) and "corpse_reentry" or "same_copy_reentry"
      st.sessionState = "RECOVERY"
      notifyUIRefresh()
      return st.sessionState, st.recoveryReason
    end

    -- Clean, verified entry into a fresh Sunken Temple copy from outside!
    st.phaseIndex = 0
    st.requiresRearm = false
    st.recoveryReason = nil
    st.sessionState = "READY"
    notifyUIRefresh()
    return st.sessionState, "verified_fresh_entry"
  end

  -- Case B: Not inside verified Sunken Temple (outside, other dungeon, raid, or ambiguous identity):
  local wasInside = (st.wasInsideVerifiedST == true)
  st.verifiedSunkenTemple = false
  st.wasInsideVerifiedST = false

  if probe.inInstance == false then
    st.hasObservedOutsideBeforeEntry = true
    if isCorpse then
      st.lastOutsideWasCorpse = true
      st.requiresRearm = true
    else
      st.lastOutsideWasCorpse = false
    end
    if wasInside then
      if st.sessionState == "ACTIVE" and st.currentAttempt and not st.currentAttempt.closed then
        closeActiveAttemptOnce("ABORTED", isCorpse and "ghost_release_outside" or "exited_instance_portal", ctx.nowMono)
      end
      if ns.UI and ns.UI.Navigation and type(ns.UI.Navigation.OnInstancePortalExit) == "function" then
        ns.UI.Navigation.OnInstancePortalExit(ctx.expectedGeneration, isCorpse)
      end
    end
  else
    -- Inside another dungeon, raid, or ambiguous/unresolved instance: suppress outdoor arrow if party/raid, keep coach INACTIVE!
    if probe.inInstance == true and (probe.instanceType == "party" or probe.instanceType == "raid") then
      if ns.UI and ns.UI.Navigation and type(ns.UI.Navigation.OnInstancePortalEntry) == "function" then
        ns.UI.Navigation.OnInstancePortalEntry()
      end
    end
    if st.sessionState == "ACTIVE" and st.currentAttempt and not st.currentAttempt.closed then
      closeActiveAttemptOnce("ABORTED", "left_verified_sunken_temple", ctx.nowMono)
    end
  end

  st.phaseIndex = 0
  st.sessionState = "INACTIVE"
  notifyUIRefresh()
  return st.sessionState, probe.classification
end

function SunkenTempleCoach.ObserveConfirmedReset()
  local st = SunkenTempleCoach.state
  st.pendingConfirmedReset = true
  st.observedActiveRunID = nil
  st.enteredCurrentCopyCount = 0
  if not st.wasInsideVerifiedST then
    st.requiresRearm = false
    st.lastOutsideWasCorpse = false
    st.recoveryReason = nil
  end
end

-- ============================================================================
-- 2. Deterministic Manual Controls (100% Combat-Safe, `ST-05` & `ST-07`)
-- ============================================================================

function SunkenTempleCoach.RearmCoach()
  local st = SunkenTempleCoach.state
  if st.verifiedSunkenTemple ~= true then
    return false, "not_in_verified_sunken_temple"
  end
  local isCorpse = ns.UI and ns.UI.Navigation and ns.UI.Navigation.IsPlayerCorpseOrGhost and ns.UI.Navigation.IsPlayerCorpseOrGhost() or false
  if isCorpse then
    return false, "cannot_rearm_while_dead_or_ghost"
  end
  if st.sessionState ~= "RECOVERY" and st.sessionState ~= "READY" then
    return false, "coach_not_in_recovery"
  end
  st.requiresRearm = false
  st.lastOutsideWasCorpse = false
  st.recoveryReason = nil
  st.phaseIndex = 0
  st.sessionState = "READY"
  notifyUIRefresh()
  return true, "READY"
end

function SunkenTempleCoach.StartAttempt(explicitNow)
  local st = SunkenTempleCoach.state
  if st.verifiedSunkenTemple ~= true then
    return false, "not_in_verified_sunken_temple"
  end
  if st.sessionState == "RECOVERY" or st.requiresRearm == true then
    return false, "recovery_requires_rearm"
  end
  if st.sessionState ~= "READY" then
    return false, "coach_not_ready"
  end
  local isCorpse = ns.UI and ns.UI.Navigation and ns.UI.Navigation.IsPlayerCorpseOrGhost and ns.UI.Navigation.IsPlayerCorpseOrGhost() or false
  if isCorpse then
    st.sessionState = "RECOVERY"
    st.requiresRearm = true
    st.recoveryReason = "dead_or_ghost"
    notifyUIRefresh()
    return false, "cannot_start_while_dead_or_ghost"
  end

  local nowMono = getMonotonicNow(explicitNow)
  local attemptID = st.nextAttemptSeq or 1
  st.nextAttemptSeq = attemptID + 1
  local firstPhase = SunkenTempleCoach.GetPhaseDefinition(1)
  st.phaseIndex = 1
  st.sessionState = "ACTIVE"
  st.currentAttempt = newAttemptRecord(attemptID, nowMono, firstPhase)
  appendRingAnnotation(st.currentAttempt, nowMono, "attempt_started", "Player started attempt in Phase 1 (Approach Sanctuary)", 1)
  SunkenTempleCoach.AnnotateSubZoneSample(nowMono)
  SunkenTempleCoach.AnnotatePlayerAuraSample(nowMono)
  notifyUIRefresh()
  return true, st.currentAttempt
end

function SunkenTempleCoach.NextPhase(explicitNow)
  local st = SunkenTempleCoach.state
  if st.sessionState ~= "ACTIVE" or not st.currentAttempt or st.currentAttempt.closed then
    return false, "no_active_attempt"
  end
  local _, totalPhases = SunkenTempleCoach.GetPhaseDefinition(1)
  if st.phaseIndex >= totalPhases then
    return false, "already_at_final_phase"
  end
  local nowMono = getMonotonicNow(explicitNow)
  local nextIdx = st.phaseIndex + 1
  local pDef = SunkenTempleCoach.GetPhaseDefinition(nextIdx)
  st.phaseIndex = nextIdx
  st.currentAttempt.terminalPhaseIndex = nextIdx
  st.currentAttempt.terminalPhaseID = pDef and pDef.phaseID or tostring(nextIdx)
  st.currentAttempt.terminalPhaseTitle = pDef and pDef.title or tostring(nextIdx)

  local offset = math.max(0, math.floor(((nowMono - (st.currentAttempt.startedAtMono or nowMono)) * 10) + 0.5) / 10)
  st.currentAttempt.phaseConfirmations[nextIdx] = {
    phaseIndex = nextIdx,
    phaseID = st.currentAttempt.terminalPhaseID,
    title = st.currentAttempt.terminalPhaseTitle,
    confirmedAtOffsetSec = offset,
    source = "player_manual",
  }
  appendRingAnnotation(
    st.currentAttempt,
    nowMono,
    "manual_phase_next",
    string.format("Player confirmed %s", tostring(st.currentAttempt.terminalPhaseTitle)),
    nextIdx
  )
  notifyUIRefresh()
  return true, nextIdx
end

function SunkenTempleCoach.PrevPhase(explicitNow)
  local st = SunkenTempleCoach.state
  if st.sessionState ~= "ACTIVE" or not st.currentAttempt or st.currentAttempt.closed then
    return false, "no_active_attempt"
  end
  if st.phaseIndex <= 1 then
    return false, "already_at_first_phase"
  end
  local nowMono = getMonotonicNow(explicitNow)
  local prevIdx = st.phaseIndex - 1
  local pDef = SunkenTempleCoach.GetPhaseDefinition(prevIdx)
  st.phaseIndex = prevIdx
  st.currentAttempt.terminalPhaseIndex = prevIdx
  st.currentAttempt.terminalPhaseID = pDef and pDef.phaseID or tostring(prevIdx)
  st.currentAttempt.terminalPhaseTitle = pDef and pDef.title or tostring(prevIdx)
  st.currentAttempt.manualPrevCorrections = (st.currentAttempt.manualPrevCorrections or 0) + 1
  appendRingAnnotation(
    st.currentAttempt,
    nowMono,
    "manual_phase_prev",
    string.format("Player stepped back to %s", tostring(st.currentAttempt.terminalPhaseTitle)),
    prevIdx
  )
  notifyUIRefresh()
  return true, prevIdx
end

function SunkenTempleCoach.FinishAttempt(explicitNow)
  local st = SunkenTempleCoach.state
  if st.sessionState ~= "ACTIVE" or not st.currentAttempt or st.currentAttempt.closed then
    return false, "no_active_attempt"
  end
  local nowMono = getMonotonicNow(explicitNow)
  appendRingAnnotation(st.currentAttempt, nowMono, "manual_finish", "Player reported attempt complete", st.phaseIndex)
  local ok, autopsy = closeActiveAttemptOnce("PLAYER_REPORTED_COMPLETE", "player_reported_complete", nowMono)
  st.phaseIndex = 0
  st.sessionState = st.verifiedSunkenTemple and "READY" or "INACTIVE"
  notifyUIRefresh()
  return ok, autopsy
end

function SunkenTempleCoach.AbortAttempt(reasonNote, explicitNow)
  local st = SunkenTempleCoach.state
  if st.sessionState ~= "ACTIVE" or not st.currentAttempt or st.currentAttempt.closed then
    return false, "no_active_attempt"
  end
  local nowMono = getMonotonicNow(explicitNow)
  local tag = (type(reasonNote) == "string" and reasonNote ~= "") and reasonNote or "player_manual_abort"
  appendRingAnnotation(st.currentAttempt, nowMono, "manual_abort", "Player aborted attempt (" .. tag .. ")", st.phaseIndex)
  local ok, autopsy = closeActiveAttemptOnce("ABORTED", tag, nowMono)
  st.phaseIndex = 0
  st.sessionState = st.verifiedSunkenTemple and "READY" or "INACTIVE"
  notifyUIRefresh()
  return ok, autopsy
end

-- `/fh st reset`: resets ONLY the coach's own progress/timeline (never touches InstanceLedger or Navigation.owner, ST-07).
function SunkenTempleCoach.ResetCoachProgress()
  local st = SunkenTempleCoach.state
  st.currentAttempt = nil
  st.lastAutopsy = nil
  st.phaseIndex = 0
  if st.verifiedSunkenTemple == true then
    local isCorpse = ns.UI and ns.UI.Navigation and ns.UI.Navigation.IsPlayerCorpseOrGhost and ns.UI.Navigation.IsPlayerCorpseOrGhost() or false
    if isCorpse or st.requiresRearm == true then
      st.sessionState = "RECOVERY"
    else
      st.sessionState = "READY"
    end
  else
    st.sessionState = "INACTIVE"
  end
  notifyUIRefresh()
  return true, st.sessionState
end

-- ============================================================================
-- 3. Non-Advancing Live Signal Annotations (`P1`, `ST-04`, `ST-05`, `ST-06`)
-- ============================================================================

local function resolveSpellKeyFromID(spellID)
  local data = ns.SunkenTempleData
  local idMap = data and data.SPELL_KEY_BY_ID or {}
  local nameMap = data and data.SPELL_KEY_BY_EN_NAME_LOWER or {}

  -- Try live spell name when readable in enUS/enGB so shared IDs resolve accurately:
  if ns.Compat and ns.Compat.CallAndClassifySecretSafe then
    if type(_G.C_Spell) == "table" and type(_G.C_Spell.GetSpellName) == "function" then
      local nmRes = ns.Compat.CallAndClassifySecretSafe(function()
        return _G.C_Spell.GetSpellName(spellID)
      end, { secretCapable = true, expectedType = "string" })
      if nmRes.status == "readable" then
        local mapped = nameMap[string.lower(nmRes.value)]
        if mapped then
          return mapped
        end
      end
    elseif type(_G.GetSpellInfo) == "function" then
      local nmRes = ns.Compat.CallAndClassifySecretSafe(function()
        return (select(1, _G.GetSpellInfo(spellID)))
      end, { secretCapable = true, expectedType = "string" })
      if nmRes.status == "readable" then
        local mapped = nameMap[string.lower(nmRes.value)]
        if mapped then
          return mapped
        end
      end
    end
  end
  return idMap[spellID]
end

function SunkenTempleCoach.OnCombatStart(explicitNow)
  local st = SunkenTempleCoach.state
  local attempt = st.currentAttempt
  if st.sessionState ~= "ACTIVE" or not attempt or attempt.closed then
    return false
  end
  attempt.combatEnterCount = (attempt.combatEnterCount or 0) + 1
  appendRingAnnotation(attempt, getMonotonicNow(explicitNow), "combat_start", "Entered combat", st.phaseIndex)
  return true
end

-- Gate ST-06: Combat end with zero recorded kills leaves the attempt OPEN (never fails, never claims reset!).
function SunkenTempleCoach.OnCombatEnd(explicitNow)
  local st = SunkenTempleCoach.state
  local attempt = st.currentAttempt
  if st.sessionState ~= "ACTIVE" or not attempt or attempt.closed then
    return false
  end
  attempt.combatExitCount = (attempt.combatExitCount or 0) + 1
  appendRingAnnotation(attempt, getMonotonicNow(explicitNow), "combat_end", "Left combat (outcome remains open)", st.phaseIndex)
  return true
end

-- Gate ST-06 & ST-07: `PLAYER_DEAD` closes an open active attempt EXACTLY ONCE and transitions to `RECOVERY`.
function SunkenTempleCoach.OnPlayerDead(explicitNow)
  local st = SunkenTempleCoach.state
  st.requiresRearm = true
  st.recoveryReason = "player_died"
  if st.sessionState ~= "ACTIVE" or not st.currentAttempt or st.currentAttempt.closed then
    if st.verifiedSunkenTemple then
      st.sessionState = "RECOVERY"
      st.phaseIndex = 0
      notifyUIRefresh()
    end
    return false, "no_open_active_attempt"
  end
  local nowMono = getMonotonicNow(explicitNow)
  appendRingAnnotation(st.currentAttempt, nowMono, "player_dead", "PLAYER_DEAD observed", st.phaseIndex)
  local ok, autopsy = closeActiveAttemptOnce("DIED", "player_dead", nowMono)
  st.phaseIndex = 0
  st.sessionState = st.verifiedSunkenTemple and "RECOVERY" or "INACTIVE"
  notifyUIRefresh()
  return ok, autopsy
end

function SunkenTempleCoach.OnUnitSpellcastSucceeded(rawUnit, rawCastGUID, rawSpellID, explicitNow)
  local classify = ns.Compat and ns.Compat.ClassifySecretSafeValue
  if not classify then
    return false, "classifier_unavailable"
  end
  local unitRes = classify(rawUnit, { secretCapable = true, expectedType = "string" })
  local guidRes = classify(rawCastGUID, { secretCapable = true })
  local spellRes = classify(rawSpellID, { secretCapable = true, expectedType = "number" })

  SunkenTempleCoach.probeStore.observedEventSamples.unitSpellcastSucceeded = {
    unitStatus = unitRes.status,
    castGUIDStatus = guidRes.status,
    spellIDStatus = spellRes.status,
  }

  local st = SunkenTempleCoach.state
  local attempt = st.currentAttempt
  if st.sessionState ~= "ACTIVE" or not attempt or attempt.closed then
    return false, "inactive"
  end

  if unitRes.status ~= "readable" then
    recordCoverageStatus(attempt.coverage.spellcasts, unitRes.status)
    return false, unitRes.status
  end
  if unitRes.value ~= "player" then
    return false, "non_player_unit"
  end
  recordCoverageStatus(attempt.coverage.spellcasts, spellRes.status)
  if spellRes.status ~= "readable" then
    return false, spellRes.status
  end

  local nowMono = getMonotonicNow(explicitNow)
  local spellID = math.floor(spellRes.value)
  local spellKey = resolveSpellKeyFromID(spellID)
  local offset = math.max(0, (nowMono - (attempt.startedAtMono or nowMono)))

  if spellKey and attempt.spellStats[spellKey] then
    local sp = attempt.spellStats[spellKey]
    if sp.count > 0 and sp.lastOffsetSec ~= nil then
      local gap = math.max(0, offset - sp.lastOffsetSec)
      if sp.maxGapSec == nil or gap > sp.maxGapSec then
        sp.maxGapSec = math.floor(gap * 10 + 0.5) / 10
      end
    end
    sp.count = sp.count + 1
    if sp.firstOffsetSec == nil then
      sp.firstOffsetSec = math.floor(offset * 10 + 0.5) / 10
    end
    sp.lastOffsetSec = math.floor(offset * 10 + 0.5) / 10
  end

  appendRingAnnotation(
    attempt,
    nowMono,
    "player_cast",
    string.format("Player cast observed: %s (spellID=%d)", tostring(spellKey or "spell"), spellID),
    st.phaseIndex
  )
  return true, spellKey or spellID
end

function SunkenTempleCoach.OnMonsterChatEvent(eventKind, rawText, rawSender, explicitNow)
  local classify = ns.Compat and ns.Compat.ClassifySecretSafeValue
  if not classify then
    return false
  end
  local textRes = classify(rawText, { secretCapable = true, expectedType = "string" })
  local senderRes = classify(rawSender, { secretCapable = true, expectedType = "string" })

  SunkenTempleCoach.probeStore.observedEventSamples[eventKind == "EMOTE" and "monsterEmote" or "monsterYell"] = {
    textStatus = textRes.status,
    senderStatus = senderRes.status,
  }

  local st = SunkenTempleCoach.state
  local attempt = st.currentAttempt
  if st.sessionState ~= "ACTIVE" or not attempt or attempt.closed then
    return false
  end

  local combinedStatus = (textRes.status == "readable") and "readable" or textRes.status
  recordCoverageStatus(attempt.coverage.yells, combinedStatus)
  if textRes.status == "readable" then
    attempt.yellObservedCount = (attempt.yellObservedCount or 0) + 1
    local senderLabel = (senderRes.status == "readable") and "readable_sender" or senderRes.status
    appendRingAnnotation(
      attempt,
      getMonotonicNow(explicitNow),
      eventKind == "EMOTE" and "monster_emote" or "monster_yell",
      string.format("Monster %s observed (sender=%s)", string.lower(tostring(eventKind or "yell")), senderLabel),
      st.phaseIndex
    )
    return true
  end
  return false
end

function SunkenTempleCoach.AnnotateSubZoneSample(explicitNow)
  local callSafe = ns.Compat and ns.Compat.CallAndClassifySecretSafe
  if not callSafe then
    return nil
  end
  local subRes = callSafe(_G.GetSubZoneText, { secretCapable = true, expectedType = "string" })
  local st = SunkenTempleCoach.state
  local attempt = st.currentAttempt
  if st.sessionState == "ACTIVE" and attempt and not attempt.closed then
    recordCoverageStatus(attempt.coverage.subzone, subRes.status)
    if subRes.status == "readable" and attempt.lastSubZoneText ~= subRes.value then
      attempt.lastSubZoneText = subRes.value
      appendRingAnnotation(attempt, getMonotonicNow(explicitNow), "subzone_context", "Subzone label observed", st.phaseIndex)
    end
  end
  return subRes
end

function SunkenTempleCoach.AnnotatePlayerAuraSample(explicitNow)
  local callSafe = ns.Compat and ns.Compat.CallAndClassifySecretSafe
  local fieldSafe = ns.Compat and ns.Compat.ClassifySecretSafeField
  if not callSafe or not fieldSafe then
    return nil
  end
  local st = SunkenTempleCoach.state
  local attempt = st.currentAttempt
  if st.sessionState ~= "ACTIVE" or not attempt or attempt.closed then
    return nil
  end
  if type(_G.C_UnitAuras) == "table" and type(_G.C_UnitAuras.GetPlayerAuraBySpellID) == "function" then
    local auraRes = callSafe(function()
      return _G.C_UnitAuras.GetPlayerAuraBySpellID(11426)
    end, { secretCapable = true })
    if auraRes.status == "readable" and auraRes.valueType == "table" then
      local spRes = fieldSafe(auraRes.value, "spellId", { secretCapable = true, expectedType = "number" })
      recordCoverageStatus(attempt.coverage.auras, spRes.status)
      if spRes.status == "readable" then
        appendRingAnnotation(attempt, getMonotonicNow(explicitNow), "aura_sample", "Ice Barrier aura present at sample", st.phaseIndex)
      end
    else
      recordCoverageStatus(attempt.coverage.auras, auraRes.status)
    end
    return auraRes
  end
  recordCoverageStatus(attempt.coverage.auras, "missing")
  return nil
end

function SunkenTempleCoach.OnTargetChangedSample(explicitNow)
  local callSafe = ns.Compat and ns.Compat.CallAndClassifySecretSafe
  if not callSafe then
    return false
  end
  local st = SunkenTempleCoach.state
  local attempt = st.currentAttempt
  if st.sessionState ~= "ACTIVE" or not attempt or attempt.closed then
    return false
  end
  if type(_G.UnitExists) ~= "function" then
    recordCoverageStatus(attempt.coverage.targetSightings, "missing")
    return false
  end
  local exRes = callSafe(function()
    return _G.UnitExists("target")
  end, { secretCapable = true, expectedType = "boolean" })
  if exRes.status ~= "readable" then
    recordCoverageStatus(attempt.coverage.targetSightings, exRes.status)
    return false
  end
  if exRes.value == false then
    return false
  end

  local guidRes = callSafe(function()
    return type(_G.UnitGUID) == "function" and _G.UnitGUID("target") or nil
  end, { secretCapable = true, expectedType = "string" })
  local nameRes = callSafe(function()
    return type(_G.UnitName) == "function" and _G.UnitName("target") or nil
  end, { secretCapable = true, expectedType = "string" })

  local bestStatus = (guidRes.status == "readable" or nameRes.status == "readable") and "readable" or guidRes.status
  recordCoverageStatus(attempt.coverage.targetSightings, bestStatus)

  local matchedDragon = nil
  local data = ns.SunkenTempleData
  if guidRes.status == "readable" and ns.Compat and ns.Compat.ExtractCreatureNpcIDFromGUID then
    local npcID = ns.Compat.ExtractCreatureNpcIDFromGUID(guidRes.value)
    if npcID and data and data.KNOWN_NPCS_BY_ID and data.KNOWN_NPCS_BY_ID[npcID] then
      matchedDragon = data.KNOWN_NPCS_BY_ID[npcID]
    end
  end
  if not matchedDragon and nameRes.status == "readable" and data and data.KNOWN_DRAGON_NAMES_LOWER then
    matchedDragon = data.KNOWN_DRAGON_NAMES_LOWER[string.lower(nameRes.value)]
  end

  if matchedDragon then
    local nowMono = getMonotonicNow(explicitNow)
    local offset = math.max(0, math.floor(((nowMono - (attempt.startedAtMono or nowMono)) * 10) + 0.5) / 10)
    if attempt.positiveDragonSightings[matchedDragon] == nil then
      attempt.positiveDragonSightings[matchedDragon] = offset
      attempt.positiveDragonSightingCount = (attempt.positiveDragonSightingCount or 0) + 1
    end
    appendRingAnnotation(attempt, nowMono, "unit_sighting", "Positive target sighting: " .. matchedDragon, st.phaseIndex)
    return true, matchedDragon
  end
  return false
end

-- ============================================================================
-- 4. Opt-In Read-Only Live Capability Probe (`/fh st probe`, `ST-04`, `ST-08`, `ST-10`)
-- ============================================================================

function SunkenTempleCoach.AttachEventRegistrations(targetFrame)
  local regs = SunkenTempleCoach.probeStore.registrations
  local tfType = type(targetFrame)
  if tfType ~= "table" and tfType ~= "userdata" then
    regs.frame = "missing_event_frame"
    regs.UNIT_SPELLCAST_SUCCEEDED = "registration_rejected"
    regs.CHAT_MSG_MONSTER_YELL = "registration_rejected"
    regs.CHAT_MSG_MONSTER_EMOTE = "registration_rejected"
    return false
  end
  regs.frame = "attached"

  local Compat = ns.Compat
  -- Prefer unit-filtered registration for `UNIT_SPELLCAST_SUCCEEDED` ("player") where available,
  -- pre-screened via `Compat.SafeRegisterFrameUnitEvent` so restricted CallbackEvents can NEVER fire ADDON_ACTION_FORBIDDEN:
  if Compat and type(Compat.SafeRegisterFrameUnitEvent) == "function" then
    local okUnit, unitReason = Compat.SafeRegisterFrameUnitEvent(targetFrame, "UNIT_SPELLCAST_SUCCEEDED", "player")
    regs.UNIT_SPELLCAST_SUCCEEDED = okUnit and tostring(unitReason) or "registration_rejected"
  elseif type(targetFrame.RegisterUnitEvent) == "function" then
    local okRU, resRU = pcall(targetFrame.RegisterUnitEvent, targetFrame, "UNIT_SPELLCAST_SUCCEEDED", "player")
    regs.UNIT_SPELLCAST_SUCCEEDED = (okRU and resRU ~= false) and "registered_unit_player" or "registration_rejected"
  elseif type(targetFrame.RegisterEvent) == "function" then
    local okRE, resRE = pcall(targetFrame.RegisterEvent, targetFrame, "UNIT_SPELLCAST_SUCCEEDED")
    regs.UNIT_SPELLCAST_SUCCEEDED = (okRE and resRE ~= false) and "registered_global" or "registration_rejected"
  else
    regs.UNIT_SPELLCAST_SUCCEEDED = "registration_rejected"
  end

  for _, evName in ipairs({
    "CHAT_MSG_MONSTER_YELL",
    "CHAT_MSG_MONSTER_EMOTE",
    "PLAYER_DEAD",
    "PLAYER_ALIVE",
    "PLAYER_UNGHOST",
    "ZONE_CHANGED",
    "ZONE_CHANGED_INDOORS",
  }) do
    if Compat and type(Compat.SafeRegisterFrameEvent) == "function" then
      local okEv = Compat.SafeRegisterFrameEvent(targetFrame, evName)
      regs[evName] = okEv and "registered" or "registration_rejected"
    elseif type(targetFrame.RegisterEvent) == "function" then
      local okEv, resEv = pcall(targetFrame.RegisterEvent, targetFrame, evName)
      regs[evName] = (okEv and resEv ~= false) and "registered" or "registration_rejected"
    else
      regs[evName] = "registration_rejected"
    end
  end

  SunkenTempleCoach.eventFrame = targetFrame
  return true
end

function SunkenTempleCoach.EnsureEventFrame()
  if SunkenTempleCoach.eventFrame then
    return SunkenTempleCoach.eventFrame
  end
  return nil
end

local function summarizeEventRegistrationAndSample(regStatus, sampleTable, primaryFieldKey)
  if regStatus == "registration_rejected" or regStatus == "missing_create_frame" or regStatus == "create_frame_failed" then
    return "registration_rejected"
  end
  if type(sampleTable) ~= "table" then
    return "registered_no_sample"
  end
  return tostring(sampleTable[primaryFieldKey] or "registered_no_sample")
end

-- Strictly opt-in, read-only probe (`ST-08` zero macro/waypoint/target/frame mutations; `ST-04` zero raw payload retention).
function SunkenTempleCoach.RunOptInProbe(userContextLabel)
  SunkenTempleCoach.EnsureEventFrame()
  local Compat = ns.Compat
  local callSafe = Compat.CallAndClassifySecretSafe
  local fieldSafe = Compat.ClassifySecretSafeField
  local classify = Compat.ClassifySecretSafeValue

  local ver, build, tocVer = "unknown", "unknown", 0
  if type(_G.GetBuildInfo) == "function" then
    local okB, r1, r2, _r3, r4 = pcall(_G.GetBuildInfo)
    if okB then
      local c1 = classify(r1, { secretCapable = false, expectedType = "string" })
      local c2 = classify(r2, { secretCapable = false, expectedType = "string" })
      local c4 = classify(r4, { secretCapable = false, expectedType = "number" })
      ver = c1.status == "readable" and c1.value or c1.status
      build = c2.status == "readable" and c2.value or c2.status
      tocVer = c4.status == "readable" and math.floor(c4.value) or 0
    end
  end

  local locRes = callSafe(_G.GetLocale, { secretCapable = false, expectedType = "string" })
  local lockdownState = Compat.GetCombatLockdownState and Compat.GetCombatLockdownState() or { ok = false, locked = true }
  local instProbe = Compat.ProbeSunkenTempleInstanceIdentity()

  local autoContext = "outside"
  if instProbe.inInstance == true then
    autoContext = (lockdownState.locked == true) and "inside_combat" or "inside_out_of_combat"
  end
  local cleanLabel = (type(userContextLabel) == "string" and userContextLabel ~= "")
    and string.gsub(string.sub(userContextLabel, 1, 24), "[^%w_%-]", "")
    or autoContext

  -- 1. C_UnitAuras & legacy UnitBuff probed separately:
  local cAuraSpellStatus = "missing"
  local cAuraIndexStatus = "missing"
  local cAuraFields = nil
  if type(_G.C_UnitAuras) == "table" then
    if type(_G.C_UnitAuras.GetPlayerAuraBySpellID) == "function" then
      local spAura = callSafe(function()
        return _G.C_UnitAuras.GetPlayerAuraBySpellID(11426)
      end, { secretCapable = true })
      cAuraSpellStatus = spAura.status
    end
    if type(_G.C_UnitAuras.GetBuffDataByIndex) == "function" then
      local idxAura = callSafe(function()
        return _G.C_UnitAuras.GetBuffDataByIndex("player", 1)
      end, { secretCapable = true })
      cAuraIndexStatus = idxAura.status
      if idxAura.status == "readable" and idxAura.valueType == "table" then
        cAuraFields = {
          name = fieldSafe(idxAura.value, "name", { secretCapable = true, expectedType = "string" }).status,
          spellId = fieldSafe(idxAura.value, "spellId", { secretCapable = true, expectedType = "number" }).status,
          expirationTime = fieldSafe(idxAura.value, "expirationTime", { secretCapable = true, expectedType = "number" }).status,
        }
      end
    end
  end

  local unitBuffStatus = "missing"
  local unitBuffSpellIdStatus = "missing"
  if type(_G.UnitBuff) == "function" then
    local okUB, ubName, _ubIcon, _ubCount, _ubDebuffType, _ubDur, _ubExp, _ubSource, _ubSteal, _ubNameplate, ubSpellId =
      pcall(_G.UnitBuff, "player", 1)
    if not okUB then
      unitBuffStatus = "errored"
      unitBuffSpellIdStatus = "errored"
    else
      unitBuffStatus = classify(ubName, { secretCapable = true, expectedType = "string" }).status
      unitBuffSpellIdStatus = classify(ubSpellId, { secretCapable = true, expectedType = "number" }).status
    end
  end

  -- 2. UnitHealth & UnitHealthMax guarded independently before any arithmetic:
  local hpRes = callSafe(function()
    return type(_G.UnitHealth) == "function" and _G.UnitHealth("player") or nil
  end, { secretCapable = true, expectedType = "number" })
  local hpMaxRes = callSafe(function()
    return type(_G.UnitHealthMax) == "function" and _G.UnitHealthMax("player") or nil
  end, { secretCapable = true, expectedType = "number" })

  -- 3. GetSubZoneText & GetMinimapZoneText:
  local subZoneRes = callSafe(_G.GetSubZoneText, { secretCapable = true, expectedType = "string" })
  local minimapZoneRes = callSafe(_G.GetMinimapZoneText, { secretCapable = true, expectedType = "string" })

  -- 4. Current target (read-only, zero targeting calls):
  local targetExistsRes = callSafe(function()
    return type(_G.UnitExists) == "function" and _G.UnitExists("target") or nil
  end, { secretCapable = true, expectedType = "boolean" })
  local targetGuidStatus = "missing"
  local targetNameStatus = "missing"
  if targetExistsRes.status == "readable" and targetExistsRes.value == true then
    targetGuidStatus = callSafe(function()
      return type(_G.UnitGUID) == "function" and _G.UnitGUID("target") or nil
    end, { secretCapable = true, expectedType = "string" }).status
    targetNameStatus = callSafe(function()
      return type(_G.UnitName) == "function" and _G.UnitName("target") or nil
    end, { secretCapable = true, expectedType = "string" }).status
  elseif targetExistsRes.status ~= "readable" then
    targetGuidStatus = targetExistsRes.status
    targetNameStatus = targetExistsRes.status
  else
    targetGuidStatus = "no_target_selected"
    targetNameStatus = "no_target_selected"
  end

  -- 5. C_NamePlate.GetNamePlates (read-only enumeration + nested token & identity field check):
  local platesListStatus = "missing"
  local firstPlateTokenStatus = "missing"
  local firstPlateGuidStatus = "missing"
  local firstPlateNameStatus = "missing"
  if type(_G.C_NamePlate) == "table" and type(_G.C_NamePlate.GetNamePlates) == "function" then
    local plRes = callSafe(_G.C_NamePlate.GetNamePlates, { secretCapable = true, expectedType = "table" })
    platesListStatus = plRes.status
    if plRes.status == "readable" then
      local okLen, cnt = pcall(function()
        return #plRes.value
      end)
      if not okLen then
        platesListStatus = "errored"
      elseif type(cnt) == "number" and cnt >= 1 then
        local p1Res = fieldSafe(plRes.value, 1, { secretCapable = true, expectedType = "table" })
        if p1Res.status == "readable" then
          local tokRes = fieldSafe(p1Res.value, "namePlateUnitToken", { secretCapable = true, expectedType = "string" })
          firstPlateTokenStatus = tokRes.status
          if tokRes.status == "readable" then
            firstPlateGuidStatus = callSafe(function()
              return type(_G.UnitGUID) == "function" and _G.UnitGUID(tokRes.value) or nil
            end, { secretCapable = true, expectedType = "string" }).status
            firstPlateNameStatus = callSafe(function()
              return type(_G.UnitName) == "function" and _G.UnitName(tokRes.value) or nil
            end, { secretCapable = true, expectedType = "string" }).status
          else
            firstPlateGuidStatus = tokRes.status
            firstPlateNameStatus = tokRes.status
          end
        else
          firstPlateTokenStatus = p1Res.status
        end
      else
        firstPlateTokenStatus = "zero_visible_plates"
        firstPlateGuidStatus = "zero_visible_plates"
        firstPlateNameStatus = "zero_visible_plates"
      end
    end
  end

  local regs = SunkenTempleCoach.probeStore.registrations
  local samples = SunkenTempleCoach.probeStore.observedEventSamples
  local okDetLookup, detFn = pcall(function()
    return _G.issecretvalue
  end)
  local hasSecretDetector = okDetLookup and (type(detFn) == "function") or false

  local snapshot = {
    schema = "foreverhub-st-probe-rc1",
    provesRouteReadiness = false, -- ST-10: probe results NEVER prove route readiness!
    contextLabel = cleanLabel,
    autoContext = autoContext,
    client = {
      version = ver,
      build = build,
      interfaceVersion = tocVer,
      localeStatus = locRes.status,
      locale = locRes.status == "readable" and locRes.value or nil,
      hasSecretValueDetector = hasSecretDetector,
      lockdownProbeOk = (lockdownState.ok == true),
      inCombatLockdown = (lockdownState.locked == true),
    },
    instance = {
      classification = instProbe.classification,
      verifiedSunkenTemple = (instProbe.verifiedSunkenTemple == true),
      inInstanceStatus = instProbe.inInstanceStatus,
      inInstance = instProbe.inInstance,
      isInTypeStatus = instProbe.isInTypeStatus,
      infoTypeStatus = instProbe.infoTypeStatus,
      nameStatus = instProbe.nameStatus,
      return8_instanceID_status = instProbe.return8Status,
      return8_instanceID_value = instProbe.return8Value,
      return9_groupSize_status = instProbe.return9Status,
      return9_groupSize_value = instProbe.return9Value,
    },
    signals = {
      unitSpellcastSucceeded = {
        registration = regs.UNIT_SPELLCAST_SUCCEEDED or "unregistered",
        status = summarizeEventRegistrationAndSample(
          regs.UNIT_SPELLCAST_SUCCEEDED,
          samples.unitSpellcastSucceeded,
          "spellIDStatus"
        ),
        sampleFields = samples.unitSpellcastSucceeded,
      },
      cUnitAuras = {
        bySpellIDStatus = cAuraSpellStatus,
        byIndexStatus = cAuraIndexStatus,
        byIndexFields = cAuraFields,
      },
      legacyUnitBuff = {
        nameStatus = unitBuffStatus,
        spellIdStatus = unitBuffSpellIdStatus,
      },
      unitHealth = {
        healthStatus = hpRes.status,
        maxHealthStatus = hpMaxRes.status,
      },
      subZone = {
        subZoneStatus = subZoneRes.status,
        minimapZoneStatus = minimapZoneRes.status,
      },
      monsterYell = {
        registration = regs.CHAT_MSG_MONSTER_YELL or "unregistered",
        status = summarizeEventRegistrationAndSample(regs.CHAT_MSG_MONSTER_YELL, samples.monsterYell, "textStatus"),
      },
      monsterEmote = {
        registration = regs.CHAT_MSG_MONSTER_EMOTE or "unregistered",
        status = summarizeEventRegistrationAndSample(regs.CHAT_MSG_MONSTER_EMOTE, samples.monsterEmote, "textStatus"),
      },
      target = {
        existsStatus = targetExistsRes.status,
        guidStatus = targetGuidStatus,
        nameStatus = targetNameStatus,
      },
      namePlates = {
        listStatus = platesListStatus,
        firstTokenStatus = firstPlateTokenStatus,
        firstGuidStatus = firstPlateGuidStatus,
        firstNameStatus = firstPlateNameStatus,
      },
      cleuPolicy = "excluded_not_registered_by_coach",
    },
  }

  local runs = SunkenTempleCoach.probeStore.runs
  if #runs >= SunkenTempleCoach.MAX_PROBE_RUNS then
    table.remove(runs, 1)
  end
  table.insert(runs, snapshot)
  SunkenTempleCoach.probeStore.lastSnapshot = snapshot
  notifyUIRefresh()
  return snapshot
end

-- ============================================================================
-- 5. View-Model Builder for Compact Maneuver Card & Dungeons Panel (`ST-02`, `ST-10`)
-- ============================================================================

local function buildEffectiveStepForSession(rawStep, st)
  if type(rawStep) ~= "table" then
    return nil
  end
  local idx = tonumber(rawStep.index)
  local confirmedMap = st and st.liveConfirmedPhases
  if not idx or type(confirmedMap) ~= "table" or confirmedMap[idx] ~= true then
    return rawStep
  end
  local copy = {}
  for k, v in pairs(rawStep) do
    copy[k] = v
  end
  copy.verificationState = "live_confirmed"
  if type(rawStep.provenance) == "table" then
    local pCopy = {}
    for pk, pv in pairs(rawStep.provenance) do
      pCopy[pk] = pv
    end
    pCopy.liveConfirmedOnPlayerCharacter = true
    copy.provenance = pCopy
  end
  return copy
end

function SunkenTempleCoach.ConfirmPhaseLiveWalk(targetArg)
  local st = SunkenTempleCoach.state
  st.liveConfirmedPhases = type(st.liveConfirmedPhases) == "table" and st.liveConfirmedPhases or {}
  local _, totalPhases = SunkenTempleCoach.GetPhaseDefinition(1)
  local raw = string.lower(string.gsub(tostring(targetArg or ""), "^%s*(.-)%s*$", "%1"))

  if raw == "reset" or raw == "clear" or raw == "off" then
    st.liveConfirmedPhases = {}
    notifyUIRefresh()
    return true, "cleared"
  elseif raw == "all" then
    for i = 1, totalPhases do
      st.liveConfirmedPhases[i] = true
    end
    notifyUIRefresh()
    return true, "all"
  end

  local targetIdx = tonumber(raw)
  if targetIdx == nil then
    targetIdx = (st.sessionState == "ACTIVE" and st.phaseIndex >= 1) and st.phaseIndex or nil
  end
  if not targetIdx or targetIdx < 1 or targetIdx > totalPhases or math.floor(targetIdx) ~= targetIdx then
    return false, "specify_phase_1_to_" .. tostring(totalPhases) .. "_or_all"
  end
  st.liveConfirmedPhases[targetIdx] = true
  notifyUIRefresh()
  return true, targetIdx
end

function SunkenTempleCoach.GetViewModel(explicitNow, explicitStepOverride)
  local st = SunkenTempleCoach.state
  local nowMono = getMonotonicNow(explicitNow)
  local locale = (ns.Compat and ns.Compat.GetClientLocale and ns.Compat.GetClientLocale()) or nil
  local _, totalPhases = SunkenTempleCoach.GetPhaseDefinition(1)
  local refVideo = ns.SunkenTempleData and ns.SunkenTempleData.REFERENCE_VIDEO or nil

  local rawStep = explicitStepOverride or SunkenTempleCoach.GetPhaseDefinition(st.phaseIndex)
  local step = (explicitStepOverride ~= nil) and explicitStepOverride or buildEffectiveStepForSession(rawStep, st)
  local readinessOk, readinessDataOrReason = false, "no_active_step"
  if step and ns.SunkenTempleData and type(ns.SunkenTempleData.ValidateStepDataReadiness) == "function" then
    readinessOk, readinessDataOrReason = ns.SunkenTempleData.ValidateStepDataReadiness(step, locale)
  end

  local elapsedSec = 0
  if st.sessionState == "ACTIVE" and st.currentAttempt and not st.currentAttempt.closed then
    elapsedSec = math.max(0, math.floor((nowMono - (st.currentAttempt.startedAtMono or nowMono)) + 0.5))
  end

  local cardTitle = "Sunken Temple Coach"
  local cardGlyph = "info"
  local landmarkLine = ""
  local instructionLine = ""
  local readinessBadge = nil

  if st.sessionState == "INACTIVE" then
    landmarkLine = st.localizedNameHintMatched
      and "Unresolved instance identity — numeric Sunken Temple ID (109) unconfirmed; coach idle."
      or "Idle outside verified Sunken Temple (arms automatically on verified ID 109 party entry)."
    instructionLine = refVideo and refVideo.allianceApproach
      or "Run '/fh st probe' to record capability statuses, or enter Sunken Temple to arm."
  elseif st.sessionState == "RECOVERY" then
    cardGlyph = "warning"
    cardTitle = "Sunken Temple Coach · RECOVERY"
    landmarkLine = string.format("Recovery latched (%s) — automatic start blocked.", tostring(st.recoveryReason or "reentry_or_reload"))
    instructionLine = "Confirm your character position and click Rearm Coach when ready to start a new attempt."
  elseif st.sessionState == "READY" then
    cardGlyph = "play"
    cardTitle = "Sunken Temple Coach · READY"
    landmarkLine = "Verified Sunken Temple (ID 109) · Broog Reference + Lv54 Gnome Coach Ready"
    instructionLine = refVideo and ("Prep: " .. tostring(refVideo.prepChecklist))
      or "Click Start Attempt to open a 6-phase manual timeline, or run '/fh st probe' first."
  elseif st.sessionState == "ACTIVE" and step then
    cardGlyph = step.glyph or "travel"
    cardTitle = string.format("ST Coach · Phase %d/%d", tonumber(st.phaseIndex) or 1, totalPhases)
    if readinessOk and type(readinessDataOrReason) == "table" then
      readinessBadge = "Verified Landmark Cue"
      landmarkLine = string.format(
        "%s — Landmark: %s",
        tostring(step.shortTitle or step.title),
        tostring(readinessDataOrReason.approachLandmark)
      )
      local jumpNote = ""
      if readinessDataOrReason.jumpTakeoff and readinessDataOrReason.jumpLanding then
        jumpNote = string.format(
          " [Jump: %s -> %s]",
          tostring(readinessDataOrReason.jumpTakeoff),
          tostring(readinessDataOrReason.jumpLanding)
        )
      end
      instructionLine = string.format(
        "Ref Pose: %s -> %s%s (Cue: %s)",
        tostring(readinessDataOrReason.referencePose),
        tostring(readinessDataOrReason.actionableInstruction),
        jumpNote,
        tostring(readinessDataOrReason.visibleSuccessCue)
      )
    else
      readinessBadge = "Route Cue Gated (" .. tostring(readinessDataOrReason) .. ")"
      landmarkLine = tostring(step.title or step.phaseID)
      local basePrompt = tostring(
        step.checkpointPrompt
          or "Actionable RP/reset/jump cue gated (ST-10): awaiting verified video provenance & live reproduction."
      )
      if type(step.gnomeLv54Note) == "string" and step.gnomeLv54Note ~= "" then
        instructionLine = basePrompt .. " | " .. step.gnomeLv54Note .. " (Use '/fh st confirm' after live walk check.)"
      else
        instructionLine = basePrompt
      end
    end
  end

  local confirmedCount = 0
  if type(st.liveConfirmedPhases) == "table" then
    for i = 1, totalPhases do
      if st.liveConfirmedPhases[i] == true then
        confirmedCount = confirmedCount + 1
      end
    end
  end

  return {
    sessionState = st.sessionState,
    verifiedSunkenTemple = (st.verifiedSunkenTemple == true),
    instanceClassification = st.instanceClassification,
    phaseIndex = st.phaseIndex,
    totalPhases = totalPhases,
    elapsedSec = elapsedSec,
    cardVisible = (st.verifiedSunkenTemple == true) and (st.hudCardHidden ~= true) and (st.sessionState ~= "INACTIVE"),
    hudCardHidden = (st.hudCardHidden == true),
    cardGlyph = cardGlyph,
    cardTitle = cardTitle,
    landmarkLine = landmarkLine,
    instructionLine = instructionLine,
    dataReadinessOk = readinessOk,
    dataReadinessReason = (not readinessOk) and tostring(readinessDataOrReason) or nil,
    readinessBadge = readinessBadge,
    confirmedPhaseCount = confirmedCount,
    referenceVideo = refVideo,
    canRearm = (st.sessionState == "RECOVERY" and st.verifiedSunkenTemple == true),
    canStart = (st.sessionState == "READY" and st.verifiedSunkenTemple == true),
    canPrev = (st.sessionState == "ACTIVE" and st.phaseIndex > 1),
    canNext = (st.sessionState == "ACTIVE" and st.phaseIndex < totalPhases),
    canFinish = (st.sessionState == "ACTIVE"),
    canAbort = (st.sessionState == "ACTIVE"),
    lastAutopsy = st.lastAutopsy,
    lastProbe = SunkenTempleCoach.probeStore.lastSnapshot,
    probeRunCount = #(SunkenTempleCoach.probeStore.runs or {}),
  }
end

function SunkenTempleCoach.SetHudCardHidden(hidden)
  SunkenTempleCoach.state.hudCardHidden = (hidden == true)
  notifyUIRefresh()
end

return SunkenTempleCoach
