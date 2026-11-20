local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.Domain = ns.Domain or {}
local SelfTest = {}
ns.Domain.SelfTest = SelfTest

SelfTest._running = {
  core = false,
  gold_farms = false,
  workspace_ui = false,
  phase0_market = false,
  spawn_radar = false,
  sunken_temple_rc1 = false,
}
SelfTest.cachedReports = {
  core = nil,
  gold_farms = nil,
  workspace_ui = nil,
  phase0_market = nil,
  spawn_radar = nil,
  sunken_temple_rc1 = nil,
}
SelfTest.suiteRunCounts = {
  core = 0,
  gold_farms = 0,
  workspace_ui = 0,
  phase0_market = 0,
  spawn_radar = 0,
  sunken_temple_rc1 = 0,
}

local function deepCopyTable(val)
  if type(val) ~= "table" then
    return val
  end
  local copy = {}
  for k, v in pairs(val) do
    copy[deepCopyTable(k)] = deepCopyTable(v)
  end
  return copy
end

local function copyOwnerPreservingOpaqueHandle(owner)
  if type(owner) ~= "table" then
    return owner
  end
  local copy = {
    ownerContext = owner.ownerContext,
    generation = owner.generation,
    provider = owner.provider,
    pendingRelease = owner.pendingRelease,
    pendingDestination = deepCopyTable(owner.pendingDestination),
    handle = nil,
  }
  if type(owner.handle) == "table" then
    local h = {}
    for k, v in pairs(owner.handle) do
      if k == "uid" then
        -- CRITICAL (Astra P1): Preserve external opaque provider handle (e.g. TomTom table UID) by reference!
        h.uid = v
      else
        h[deepCopyTable(k)] = deepCopyTable(v)
      end
    end
    copy.handle = h
  else
    copy.handle = owner.handle
  end
  return copy
end

local function snapshotAndIsolateNavigation(charDB)
  local nav = ns.UI and ns.UI.Navigation or nil
  local wmp = ns.UI and ns.UI.WorldMapPins or nil
  local gfProg = ns.State and ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress() or nil
  local snap = {
    savedCTimer = _G.C_Timer,
    savedWorldMapFrame = _G.WorldMapFrame,
    savedGlobalHUD = _G.ForeverHubRivergladesHUD,
    savedGlobalArrow = _G.ForeverHubNavigationArrow,
    savedGlobalController = _G.ForeverHubNavigationController,
    savedDBNavOwner = charDB and deepCopyTable(charDB.navigationOwner) or nil,
    savedDBArrowSettings = charDB and deepCopyTable(charDB.arrowSettings) or nil,
    savedDBWorldMapPinSettings = charDB and deepCopyTable(charDB.worldMapPinSettings) or nil,
    savedGfOwnedWp = gfProg and deepCopyTable(gfProg.ownedWaypoint) or nil,
    savedEventsReconcilePending = ns.Events and ns.Events.reconcilePending or false,
    savedOverrideFacing = ns.State and ns.State.overridePlayerFacing or nil,
    savedOverrideWorldPos = ns.State and ns.State.overridePlayerWorldPosition or nil,
    savedOverrideTargetWorldPos = ns.State and ns.State.overrideTargetWorldPositions or nil,
  }
  _G.WorldMapFrame = nil
  if wmp then
    snap.hasWmp = true
    snap.wmpDirty = wmp.dirty
    snap.wmpLastLayoutKey = wmp.lastLayoutKey
    snap.wmpLastEntries = wmp.lastEntries
    snap.wmpLastClusters = wmp.lastClusters
    snap.wmpLastSummaryCounts = wmp.lastSummaryCounts
    snap.wmpActivePinCount = wmp.activePinCount
    snap.wmpClusterCycleIndex = deepCopyTable(wmp.clusterCycleIndex)
    snap.wmpHookedMapFrame = wmp.hookedMapFrame
    snap.wmpFilterBar = wmp.filterBar
    snap.wmpPinPool = wmp.pinPool
    wmp.hookedMapFrame = nil
    wmp.filterBar = nil
    wmp.pinPool = {}
  end
  if nav then
    snap.hasNav = true
    snap.travelTicker = nav.travelTicker
    snap.travelTickerGeneration = nav.travelTickerGeneration
    snap.travelTickerBoundGeneration = nav.travelTickerBoundGeneration
    snap.travelTickerBoundContext = nav.travelTickerBoundContext
    snap.frame = nav.frame
    snap.controllerFrame = nav.controllerFrame
    snap.arrowFrame = nav.arrowFrame
    snap.activeTarget = nav.activeTarget
    snap.arrowTarget = nav.arrowTarget
    snap.suppressHUDCreation = nav.suppressHUDCreation
    snap.owner = copyOwnerPreservingOpaqueHandle(nav.owner)
    snap.activeContext = nav.activeContext
    snap.hydratedFromSaved = nav.hydratedFromSaved
    snap.lastStatus = deepCopyTable(nav.lastStatus)
    snap.pendingDeferredSync = nav.pendingDeferredSync
    snap.watchedQuestRef = nav.watchedQuestRef
    snap.watchedQuestActionID = nav.watchedQuestActionID
    snap.watchedQuestFingerprint = nav.watchedQuestFingerprint
    snap.questWatchdogAccum = nav.questWatchdogAccum
    snap.questWatchdogActive = nav.questWatchdogActive

    -- Detach live ticker, live HUD, live controller, live arrow, AND live owner WITHOUT cancelling the live C_Timer handle or touching live waypoints!
    nav.travelTicker = nil
    nav.travelTickerBoundGeneration = nil
    nav.travelTickerBoundContext = nil
    nav.frame = nil
    nav.controllerFrame = nil
    nav.arrowFrame = nil
    nav.activeTarget = nil
    nav.arrowTarget = nil
    nav.suppressHUDCreation = true
    nav.hydratedFromSaved = true
    nav.pendingDeferredSync = false
    nav.watchedQuestRef = nil
    nav.watchedQuestActionID = nil
    nav.watchedQuestFingerprint = nil
    nav.questWatchdogAccum = 0
    nav.questWatchdogActive = false
    nav.owner = {
      ownerContext = nil,
      generation = 0,
      provider = "none",
      handle = nil,
      pendingRelease = false,
      pendingDestination = nil,
    }
    if charDB then
      charDB.navigationOwner = nil
    end
  end
  return snap
end

local function restoreNavigationSnapshot(snap, charDB)
  _G.C_Timer = snap.savedCTimer
  _G.WorldMapFrame = snap.savedWorldMapFrame
  if snap.savedGlobalHUD ~= nil then
    _G.ForeverHubRivergladesHUD = snap.savedGlobalHUD
  end
  if snap.savedGlobalArrow ~= nil then
    _G.ForeverHubNavigationArrow = snap.savedGlobalArrow
  end
  if snap.savedGlobalController ~= nil then
    _G.ForeverHubNavigationController = snap.savedGlobalController
  end
  if ns.State then
    ns.State.overridePlayerFacing = snap.savedOverrideFacing
    ns.State.overridePlayerWorldPosition = snap.savedOverrideWorldPos
    ns.State.overrideTargetWorldPositions = snap.savedOverrideTargetWorldPos
  end
  local wmp = ns.UI and ns.UI.WorldMapPins or nil
  if wmp and snap.hasWmp then
    wmp.dirty = snap.wmpDirty
    wmp.lastLayoutKey = snap.wmpLastLayoutKey
    wmp.lastEntries = snap.wmpLastEntries
    wmp.lastClusters = snap.wmpLastClusters
    wmp.lastSummaryCounts = snap.wmpLastSummaryCounts
    wmp.activePinCount = snap.wmpActivePinCount
    wmp.clusterCycleIndex = snap.wmpClusterCycleIndex
    wmp.hookedMapFrame = snap.wmpHookedMapFrame
    wmp.filterBar = snap.wmpFilterBar
    wmp.pinPool = snap.wmpPinPool
  end
  local nav = ns.UI and ns.UI.Navigation or nil
  if nav and snap.hasNav then
    -- Cancel ONLY tickers created inside the self-test sandbox; never cancel the pre-existing live ticker!
    nav.StopTravelTicker()
    nav.travelTicker = snap.travelTicker
    nav.travelTickerGeneration = snap.travelTickerGeneration
    nav.travelTickerBoundGeneration = snap.travelTickerBoundGeneration
    nav.travelTickerBoundContext = snap.travelTickerBoundContext
    nav.frame = snap.frame
    nav.controllerFrame = snap.controllerFrame
    nav.arrowFrame = snap.arrowFrame
    nav.activeTarget = snap.activeTarget
    nav.arrowTarget = snap.arrowTarget
    nav.suppressHUDCreation = snap.suppressHUDCreation
    nav.owner = snap.owner
    nav.activeContext = snap.activeContext
    nav.hydratedFromSaved = snap.hydratedFromSaved
    nav.lastStatus = snap.lastStatus
    nav.pendingDeferredSync = snap.pendingDeferredSync
    nav.watchedQuestRef = snap.watchedQuestRef
    nav.watchedQuestActionID = snap.watchedQuestActionID
    nav.watchedQuestFingerprint = snap.watchedQuestFingerprint
    nav.questWatchdogAccum = snap.questWatchdogAccum
    nav.questWatchdogActive = snap.questWatchdogActive
  end
  if charDB then
    charDB.navigationOwner = snap.savedDBNavOwner
    charDB.arrowSettings = snap.savedDBArrowSettings
    charDB.worldMapPinSettings = snap.savedDBWorldMapPinSettings
  end
  local gfProg = ns.State and ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress() or nil
  if gfProg then
    gfProg.ownedWaypoint = snap.savedGfOwnedWp
  end
  if ns.Events then
    ns.Events.reconcilePending = snap.savedEventsReconcilePending
  end
end

function SelfTest.GetDoctorSuiteSummary(suiteKey)
  if SelfTest._running[suiteKey] then
    return "IN-SUITE"
  end
  local rep = SelfTest.cachedReports[suiteKey]
  if not rep then
    if suiteKey == "core" and SelfTest.RunAll then
      rep = SelfTest.RunAll()
    elseif suiteKey == "gold_farms" and SelfTest.RunGoldFarmsSuite then
      rep = SelfTest.RunGoldFarmsSuite()
    elseif suiteKey == "workspace_ui" and SelfTest.RunWorkspaceUISuite then
      rep = SelfTest.RunWorkspaceUISuite()
    elseif suiteKey == "phase0_market" and SelfTest.RunPhase0MarketSuite then
      rep = SelfTest.RunPhase0MarketSuite()
    elseif suiteKey == "spawn_radar" and SelfTest.RunSpawnRadarSuite then
      rep = SelfTest.RunSpawnRadarSuite()
    elseif suiteKey == "sunken_temple_rc1" and SelfTest.RunSunkenTempleCoachSuite then
      rep = SelfTest.RunSunkenTempleCoachSuite()
    end
  end
  if not rep then
    return "N/A"
  end
  return string.format("%d/%d %s", rep.passed or 0, rep.total or 0, (rep.failed == 0) and "PASSED" or "FAILED")
end

local function assertTrue(cond, msg)
  if not cond then
    error(msg or "Assertion failed", 2)
  end
end

function SelfTest.RunAll()
  if SelfTest._running.core then
    error("Recursive SelfTest.RunAll invocation forbidden", 2)
  end
  SelfTest._running.core = true
  SelfTest.suiteRunCounts.core = (SelfTest.suiteRunCounts.core or 0) + 1
  local results = {}
  local passed = 0
  local failed = 0

  local function check(name, fn)
    local ok, err = pcall(fn)
    if ok then
      passed = passed + 1
      table.insert(results, { name = name, passed = true })
    else
      failed = failed + 1
      table.insert(results, { name = name, passed = false, error = tostring(err) })
    end
  end

  local crate248684 = ns.Data and ns.Data.cratesByItemID and ns.Data.cratesByItemID[248684]

  -- Scenario 1: One versus forty Apprentice Textiles turn-ins produces 40 versus 1,600 Linen demand,
  -- omitted candidateQuantity preserves 40x on an existing reservation, and invalid quantities (<= 0) are rejected.
  check("1. N-Turn-In Demand Scaling (1x vs 40x), Omitted Quantity Preservation & Invalid Quantity Rejection", function()
    assertTrue(crate248684 ~= nil, "Missing crate 248684 in ForeverHub_Data")
    local eval1 = ns.Domain.Costs.EvaluateTargetOptions("crate", crate248684, {}, {}, {}, 1, false)
    local eval40 = ns.Domain.Costs.EvaluateTargetOptions("crate", crate248684, {}, {}, {}, 40, false)
    assertTrue(eval1.options[1].materials[1].requiredQty == 40, "Expected 40 Linen for 1 turn-in")
    assertTrue(eval40.options[1].materials[1].requiredQty == 1600, "Expected 1600 Linen for 40 turn-ins")

    -- Omitted candidateQuantity (nil) on an existing 40x reservation must evaluate at 40x, never 1x
    local ordered40 = {
      {
        goalKey = "crate:248684",
        goalID = "crate:248684:1",
        kind = "crate",
        targetItemID = 248684,
        targetName = crate248684.name,
        optionIndex = 1,
        quantity = 40,
        priority = 1,
        unitMaterials = { { itemID = 2589, name = "Linen Cloth", quantity = 40 } },
      },
    }
    local evalOmitted = ns.Domain.Costs.EvaluateTargetOptions("crate", crate248684, {}, {}, ordered40, nil, false)
    assertTrue(evalOmitted.plannedTurnIns == 40, "Omitted candidateQuantity must preserve existing 40x quantity")
    assertTrue(evalOmitted.options[1].materials[1].requiredQty == 1600, "Omitted candidateQuantity must require 1600 Linen")

    -- Invalid candidateQuantity (0 or negative) must fail closed
    local okZero = pcall(ns.Domain.Costs.EvaluateTargetOptions, "crate", crate248684, {}, {}, {}, 0, false)
    assertTrue(not okZero, "candidateQuantity = 0 must be rejected")
  end)

  -- Scenario 2: Priority preservation across competing goals AND downstream displacement preview
  check("2. Priority Preservation & Downstream Displacement Preview on Option Switch", function()
    local inv = {
      [2589] = { bagCount = 40, bankCount = 0, altEligibleCount = 0 },
      [2318] = { bagCount = 20, bankCount = 0, altEligibleCount = 0 },
    }
    local goalA = {
      goalKey = "crate:248684",
      goalID = "crate:248684:1",
      kind = "crate",
      targetItemID = 248684,
      targetName = "Waylaid Crate: Apprentice Textiles",
      optionIndex = 1,
      quantity = 1,
      priority = 1,
      unitMaterials = { { itemID = 2589, name = "Linen Cloth", quantity = 40 } },
    }
    local goalB = {
      goalKey = "crate:999999",
      goalID = "crate:999999:1",
      kind = "crate",
      targetItemID = 999999,
      targetName = "Competing Linen Goal B",
      optionIndex = 1,
      quantity = 1,
      priority = 2,
      unitMaterials = { { itemID = 2589, name = "Linen Cloth", quantity = 40 } },
    }
    local goalCLeather = {
      goalKey = "crate:888888",
      goalID = "crate:888888:1",
      kind = "crate",
      targetItemID = 888888,
      targetName = "Competing Leather Goal C",
      optionIndex = 1,
      quantity = 1,
      priority = 3,
      unitMaterials = { { itemID = 2318, name = "Light Leather", quantity = 20 } },
    }
    local ordered = { goalA, goalB, goalCLeather }
    local prices = {
      [2589] = { unitPrice = 20, ageDays = 1 },
      [2318] = { unitPrice = 35, ageDays = 1 },
    }

    -- Evaluate Goal A (priority 1): must get all 40 Linen without lower-priority Goal B stealing it
    local evalA = ns.Domain.Costs.EvaluateTargetOptions("crate", crate248684, prices, inv, ordered, 1, false)
    local optA1 = evalA.options[1]
    assertTrue(optA1.totalBagDeficitUnits == 0, "Priority 1 Goal A must have 0 deficit")
    assertTrue(optA1.consumesReservedStock == false, "Priority 1 Goal A must not conflict with Priority 2 Goal B")
    assertTrue(optA1.displacesLowerPriorityStock == false, "Keeping Option 1 on Goal A must not newly displace stock")

    -- Option 2 on Goal A (Light Leather x20) evaluated at Priority 1:
    -- Must have 0 higher-priority conflict (`consumesReservedStock == false`),
    -- AND must preview displacing 20 Light Leather from lower-priority Goal C (`displacesLowerPriorityStock == true`)!
    local optA2 = evalA.options[2]
    assertTrue(optA2.totalBagDeficitUnits == 0, "Alternative Option 2 on Goal A must have 0 deficit at Priority 1")
    assertTrue(optA2.consumesReservedStock == false, "Alternative Option 2 must not report higher-priority conflict")
    assertTrue(optA2.displacesLowerPriorityStock == true, "Switching Goal A to Light Leather must preview displacing Goal C")
    assertTrue(optA2.displacedLowerPriorityUnits == 20, "Displaced Light Leather units must be 20")
    assertTrue(optA2.displacedGoalKeys[1] == "crate:888888", "Displaced goalKey must be crate:888888")

    -- Evaluate Goal B (priority 2): must see 0 free Linen and report conflict with Priority 1 Goal A
    local fakeCrateB = {
      itemID = 999999,
      name = "Competing Linen Goal B",
      alternatives = {
        { optionIndex = 1, label = "Linen Cloth x40", materials = { { itemID = 2589, name = "Linen Cloth", quantity = 40 } } },
      },
    }
    local evalB = ns.Domain.Costs.EvaluateTargetOptions("crate", fakeCrateB, prices, inv, ordered, 1, false)
    local optB1 = evalB.options[1]
    assertTrue(optB1.totalBagDeficitUnits == 40, "Priority 2 Goal B must see 40 deficit")
    assertTrue(optB1.consumesReservedStock == true, "Priority 2 Goal B must report consuming stock reserved by Goal A")
    assertTrue(optB1.reservedConflictUnits == 40, "Priority 2 Goal B conflict units must be 40")
  end)

  -- Scenario 3: Five bag Wool plus 68 bank Wool equals 73, including after bank close/reopen
  check("3. Econa Wool Cloth (5 Bags + 68 Bank = 73) Across Bank Open/Close", function()
    local liveBankSnap = {
      available = true,
      complete = true,
      observedAt = 1000,
      source = "live_bank",
      tabIDs = { 6, 7 },
      counts = { [2592] = 68 },
    }
    local chosenWhileOpen = ns.Providers.Inventory.ResolveCurrentBankSnapshot(liveBankSnap, nil, nil, true)
    assertTrue(chosenWhileOpen.counts[2592] == 68, "Bank open must report 68 Wool Cloth")
    assertTrue(chosenWhileOpen.source == "live_bank", "Live bank source must be live_bank")

    local chosenAfterClose = ns.Providers.Inventory.ResolveCurrentBankSnapshot(nil, nil, liveBankSnap, true)
    assertTrue(chosenAfterClose.counts[2592] == 68, "After bank close, cached session snapshot must report 68 Wool Cloth")
    assertTrue(chosenAfterClose.source == "session_live_bank", "Session bank source must be session_live_bank")

    local inv = {
      [2592] = { bagCount = 5, bankCount = chosenAfterClose.counts[2592], altEligibleCount = 0 },
    }
    local status = ns.Domain.Reservations.GetMaterialStatus(2592, inv, {}, nil, false)
    assertTrue(status.charOwned == 73, "5 bag Wool + 68 bank Wool must equal 73 charOwned")
  end)

  -- Scenario 4: Session reload precedence & valid empty bank never resurrecting stale cached holdings
  check("4. Session Reload Precedence & Valid Empty Bank Never Resurrects Stale Cache", function()
    local oldNonEmptyCache = {
      available = true,
      complete = true,
      observedAt = 500,
      source = "persisted_fallback",
      counts = { [2592] = 68 },
    }
    local validEmptyExternal = {
      available = true,
      complete = true,
      observedAt = nil,
      source = "bagbrother",
      counts = {},
    }
    -- On a new session (`sessionBankObserved == false`), external BagBrother snapshot takes precedence over yesterday's cache
    local resolved = ns.Providers.Inventory.ResolveCurrentBankSnapshot(nil, validEmptyExternal, oldNonEmptyCache, false)
    assertTrue(resolved.available == true and resolved.complete == true, "Empty bank must remain available and complete")
    assertTrue(resolved.source == "bagbrother", "New session must prefer valid external snapshot over persisted fallback")
    assertTrue((resolved.counts[2592] or 0) == 0, "Empty bank must report 0 Wool Cloth, not resurrect 68")

    -- When external snapshot is unavailable on a new session, fallback is labeled persisted_fallback
    local fallback = ns.Providers.Inventory.ResolveCurrentBankSnapshot(nil, nil, oldNonEmptyCache, false)
    assertTrue(fallback.source == "persisted_fallback", "Fallback must be labeled persisted_fallback")
  end)

  -- Scenario 5: Transfer Policy & Binding State (Soulbound alt crate = ineligible; Writ equippable = unknown; Trade good = eligible)
  check("5. Transfer Eligibility Policy (Soulbound Crate vs Equippable Writ Target vs Trade Good)", function()
    local eligCrate = ns.Providers.Syndicator.ClassifyAltTransferEligibility(248684, true, true, false, nil)
    assertTrue(eligCrate == "ineligible", "Waylaid Crate 248684 on alt must be classified ineligible")

    -- Trade good (Linen Cloth 2589) has transferPolicy == "never_binds_trade_good" -> eligible on same-faction alt
    local eligTradeGood = ns.Providers.Syndicator.ClassifyAltTransferEligibility(2589, true, true, false, nil)
    assertTrue(eligTradeGood == "eligible", "Linen Cloth 2589 on same-faction alt must be classified eligible")

    -- Equippable writ target item (Colorful Kilt 10008) has transferPolicy == "equippable_or_instance_bindable":
    -- Without explicit `isBound == false`, it MUST be classified "unknown" on alts!
    local eligWritTargetUnk = ns.Providers.Syndicator.ClassifyAltTransferEligibility(10008, true, true, false, nil)
    assertTrue(eligWritTargetUnk == "unknown", "Equippable writ target 10008 without explicit binding state must be unknown")

    local eligWritTargetUnbound = ns.Providers.Syndicator.ClassifyAltTransferEligibility(10008, true, true, false, false)
    assertTrue(eligWritTargetUnbound == "eligible", "Equippable writ target 10008 with explicit isBound=false may be eligible")

    local inv = {
      [248684] = { bagCount = 0, bankCount = 40, altEligibleCount = 0, altIneligibleCount = 10 },
    }
    local eval = ns.Domain.Costs.EvaluateTargetOptions("crate", crate248684, {}, inv, {}, 1, true)
    assertTrue(eval.charOwnedCrates == 40, "Current-character crate count must be 40 (excluding 10 alt crates)")
    assertTrue(eval.altSoulboundCrates == 10, "Alt soulbound crates must be tracked separately as 10")
  end)

  -- Scenario 6: Missing prices preserve known zero purchase deficits (including bank-held stock) & metric-specific label
  check("6. Missing Prices Preserve Known Zero Purchase Deficits (Bags & Bank) & Metric Label", function()
    -- Case A: 40 Linen in bags, no AH price
    local invBags = {
      [2589] = { bagCount = 40, bankCount = 0, altEligibleCount = 0 },
    }
    local evalBags = ns.Domain.Costs.EvaluateTargetOptions("crate", crate248684, {}, invBags, {}, 1, false, "after_bank")
    local opt1 = evalBags.options[1]
    assertTrue(opt1.isBagDeficitKnown == true and opt1.bagDeficitEstimate == 0, "Bag deficit must be known 0c")
    assertTrue(opt1.isTransferDeficitKnown == true and opt1.transferDeficitEstimate == 0, "Transfer deficit must be known 0c")
    assertTrue(opt1.isPriced == false and opt1.replacementEstimate == nil, "Replacement value must remain nil")
    assertTrue(
      evalBags.recommendationScopeLabel == "lowest known purchase estimate",
      "Metric label must be 'lowest known purchase estimate' when winner is deficit_known_only"
    )

    -- Case B: 0 Linen in bags, 40 Linen in bank, no AH price, Option 2 priced at 700c
    local invBank = {
      [2589] = { bagCount = 0, bankCount = 40, altEligibleCount = 0 },
    }
    local evalBank = ns.Domain.Costs.EvaluateTargetOptions(
      "crate",
      crate248684,
      { [2318] = { unitPrice = 35, ageDays = 1 } },
      invBank,
      {},
      1,
      false,
      "after_bank"
    )
    assertTrue(
      evalBank.bestOption.optionIndex == 1,
      "In after_bank mode, Option 1 with 40 Linen in bank (0c after-bank deficit) must beat Option 2 requiring 700c purchase"
    )
    assertTrue(evalBank.bestOption.activeDeficitEstimate == 0, "After-bank active deficit estimate must be 0c")
  end)

  -- Scenario 7: Comparator transitivity when mixing known and unknown replacement estimates at equal purchase deficits
  check("7. Comparator Strict Weak Ordering Transitivity (Known vs Unknown Replacement Estimates)", function()
    local fakeCrate3 = {
      itemID = 777777,
      name = "Comparator Transitivity Crate",
      alternatives = {
        { optionIndex = 1, label = "Opt A (20c)", materials = { { itemID = 2589, name = "Linen Cloth", quantity = 10 } } },
        { optionIndex = 2, label = "Opt B (nil)", materials = { { itemID = 2318, name = "Light Leather", quantity = 10 } } },
        { optionIndex = 3, label = "Opt C (10c)", materials = { { itemID = 2840, name = "Copper Bar", quantity = 10 } } },
      },
    }
    -- All 3 options have 0 deficit (owned in bags), so activeDeficit == bagDeficit == transferDeficit == 0
    local inv = {
      [2589] = { bagCount = 10, bankCount = 0 },
      [2318] = { bagCount = 10, bankCount = 0 },
      [2840] = { bagCount = 10, bankCount = 0 },
    }
    local prices = {
      [2589] = { unitPrice = 2, ageDays = 1 }, -- 20c replacement
      -- 2318 unpriced (nil replacement)
      [2840] = { unitPrice = 1, ageDays = 1 }, -- 10c replacement
    }
    local eval = ns.Domain.Costs.EvaluateTargetOptions("crate", fakeCrate3, prices, inv, {}, 1, false, "after_bank")
    assertTrue(eval.rankedOptions[1].optionIndex == 3, "Rank 1 must be Option 3 (10c replacement)")
    assertTrue(eval.rankedOptions[2].optionIndex == 1, "Rank 2 must be Option 1 (20c replacement)")
    assertTrue(eval.rankedOptions[3].optionIndex == 2, "Rank 3 must be Option 2 (unpriced replacement)")
  end)

  -- Scenario 8: Completing turn-ins releases exact reserved quantity and restores character DB state cleanly
  check("8. Completing Turn-Ins Decrements & Releases Exact Reserved Quantity (Full State Isolation)", function()
    local charDB = ns.State.GetCharDB()
    local db = ns.State.GetDB()
    local _, _, ownerKey = ns.Compat.GetCharacterKey()

    local savedRes = charDB.reservations
    local savedNextP = charDB.nextPriority
    local savedCharRecord = db.characters and db.characters[ownerKey]
    local savedSessionFlag = ns.State.sessionBankObserved
    local savedSessionSnap = ns.State.sessionBankSnapshot

    charDB.reservations = {}
    charDB.nextPriority = 1

    local ok, err = pcall(function()
      -- Reject invalid 0 quantity on ReserveGoal
      local okInvalid = ns.State.ReserveGoal("crate", 248684, 1, 0)
      assertTrue(not okInvalid, "ReserveGoal must reject quantity 0")

      local okRes, res40 = ns.State.ReserveGoal("crate", 248684, 1, 40)
      assertTrue(okRes and res40.quantity == 40 and res40.priority == 1, "Initial 40x reservation failed")

      local invBefore = { [2589] = { bagCount = 500, bankCount = 1100 } }
      local st40 = ns.Domain.Reservations.GetMaterialStatus(2589, invBefore, ns.State.GetOrderedReservations(), nil, false)
      assertTrue(st40.reservedTotal == 1600, "40 turn-ins must reserve 1,600 Linen")

      -- Order A: Turn-in completion before inventory consumption update
      local okComp1, remAfter1 = ns.State.CompleteGoalTurnIn("crate", 248684, 1)
      assertTrue(okComp1 and remAfter1 == 39, "Completing 1 turn-in must leave 39 turn-ins")
      local currentRes = ns.State.GetReservedOptionForTarget("crate", 248684)
      assertTrue(currentRes.priority == 1, "Completing 1 turn-in must preserve priority 1")

      local st39BeforeBagUpdate = ns.Domain.Reservations.GetMaterialStatus(2589, invBefore, ns.State.GetOrderedReservations(), nil, false)
      assertTrue(st39BeforeBagUpdate.reservedTotal == 1560, "39 remaining turn-ins must reserve 1,560 Linen")
      assertTrue(st39BeforeBagUpdate.unreservedTotal == 40, "40 Linen released before bag consumption")

      -- Inventory consumption arrives (40 Linen consumed from bags: 500 -> 460)
      local invAfter1 = { [2589] = { bagCount = 460, bankCount = 1100 } }
      local st39AfterBagUpdate = ns.Domain.Reservations.GetMaterialStatus(2589, invAfter1, ns.State.GetOrderedReservations(), nil, false)
      assertTrue(st39AfterBagUpdate.reservedTotal == 1560 and st39AfterBagUpdate.unreservedTotal == 0, "After bag update, 1,560 owned matches 1,560 reserved")

      -- Order B: Inventory consumption arrives BEFORE turn-in completion (460 -> 420)
      local invAfter2 = { [2589] = { bagCount = 420, bankCount = 1100 } }
      local okComp2, remAfter2 = ns.State.CompleteGoalTurnIn("crate", 248684, 1)
      assertTrue(okComp2 and remAfter2 == 38, "Completing 2nd turn-in must leave 38 turn-ins")
      local st38 = ns.Domain.Reservations.GetMaterialStatus(2589, invAfter2, ns.State.GetOrderedReservations(), nil, false)
      assertTrue(st38.reservedTotal == 1520 and st38.unreservedTotal == 0, "After both events in reverse order, 1,520 owned matches 1,520 reserved")

      local okCompAll, remAfterAll = ns.State.CompleteGoalTurnIn("crate", 248684, 38)
      assertTrue(okCompAll and remAfterAll == 0, "Completing remaining 38 turn-ins must clear the reservation")
      assertTrue(ns.State.GetReservedOptionForTarget("crate", 248684) == nil, "Reservation must be removed at 0")
    end)

    charDB.reservations = savedRes
    charDB.nextPriority = savedNextP
    if db.characters then
      db.characters[ownerKey] = savedCharRecord
    end
    ns.State.sessionBankObserved = savedSessionFlag
    ns.State.sessionBankSnapshot = savedSessionSnap
    ns.State.BumpReservationRevision()
    if not ok then
      error(err, 2)
    end
  end)

  -- Scenario 9: Capability-detected bank enumeration failure returns unavailable/incomplete rather than legacy fallback
  check("9. Capability-Detected Bank Enumeration Failure Never Falls Back to Legacy Containers", function()
    local savedCBank = _G.C_Bank
    local ok, err = pcall(function()
      -- Simulate modern C_Bank capability where FetchPurchasedBankTabData throws or returns nil
      _G.C_Bank = {
        FetchNumPurchasedBankTabs = function()
          return 2
        end,
        FetchPurchasedBankTabData = function()
          return nil
        end,
      }
      local infoFail = ns.Compat.GetPurchasedBankTabIDs()
      assertTrue(infoFail.mode == "bank_tabs", "Modern C_Bank capability must stay in bank_tabs mode")
      assertTrue(infoFail.available == false and infoFail.complete == false, "Failed tab fetch must report incomplete/unavailable")

      -- Simulate mismatch: 2 purchased tabs expected, but empty table returned
      _G.C_Bank = {
        FetchNumPurchasedBankTabs = function()
          return 2
        end,
        FetchPurchasedBankTabData = function()
          return {}
        end,
      }
      local infoMismatch = ns.Compat.GetPurchasedBankTabIDs()
      assertTrue(infoMismatch.available == false and infoMismatch.complete == false, "Tab count mismatch must report incomplete")

      -- Simulate confirmed 0 purchased tabs
      _G.C_Bank = {
        FetchNumPurchasedBankTabs = function()
          return 0
        end,
        FetchPurchasedBankTabData = function()
          return {}
        end,
      }
      local infoZero = ns.Compat.GetPurchasedBankTabIDs()
      assertTrue(infoZero.available == true and infoZero.complete == true and infoZero.confirmedZeroTabs == true, "Confirmed 0 tabs must be complete")
    end)
    _G.C_Bank = savedCBank
    if not ok then
      error(err, 2)
    end
  end)

  -- Scenario 10: Ranking Comparator Contention/Displacement Avoidance & Retrieve-Units Tie-Breaking
  check("10. Comparator Prioritizes Zero Contention, Zero Displacement, & Bags-Ready Over Bank Retrieval", function()
    local inv = {
      [2589] = { bagCount = 40, bankCount = 0 },
      [2318] = { bagCount = 0, bankCount = 20 },
    }
    -- Lower-priority Goal C reserves 40 Linen Cloth (2589)
    local ordered = {
      {
        goalKey = "crate:248684",
        goalID = "crate:248684:2",
        kind = "crate",
        targetItemID = 248684,
        targetName = "Waylaid Crate: Apprentice Textiles",
        optionIndex = 2,
        quantity = 1,
        priority = 1,
        unitMaterials = { { itemID = 2318, name = "Light Leather", quantity = 20 } },
      },
      {
        goalKey = "crate:999999",
        goalID = "crate:999999:1",
        kind = "crate",
        targetItemID = 999999,
        targetName = "Lower Priority Linen Goal",
        optionIndex = 1,
        quantity = 1,
        priority = 2,
        unitMaterials = { { itemID = 2589, name = "Linen Cloth", quantity = 40 } },
      },
    }
    -- Evaluating Goal A (priority 1):
    -- Option 1 (Linen x40) has 0c deficit in bags, but displaces lower-priority Goal C (`displacesLowerPriorityStock = true`).
    -- Option 2 (Light Leather x20) has 0c deficit in bank and does NOT displace Goal C (`displacesLowerPriorityStock = false`).
    -- Therefore Option 2 must rank ahead of Option 1!
    local eval = ns.Domain.Costs.EvaluateTargetOptions("crate", crate248684, {}, inv, ordered, 1, false, "after_bank")
    assertTrue(eval.bestOption.optionIndex == 2, "Non-displacing Option 2 must rank ahead of displacing Option 1")
  end)

  -- Scenario 11: Scarcity-Aware "Suggest Ready Turn-Ins" (Astra's 10 X / 10 Y Counterexample + Manual Preservation)
  check("11. Scarcity-Aware SuggestReadyTurnIns Solves 10 X / 10 Y Counterexample & Preserves Manual Goals", function()
    -- Goal A (flexible): accepts 10 X (2589) OR 10 Y (2318)
    -- Goal B (inflexible): accepts ONLY 10 X (2589)
    -- Inventory has 10 X and 10 Y, with 0 AH prices.
    -- Scarcity-aware planner MUST assign 10 X to Goal B and 10 Y to Goal A so BOTH turn-ins are suggested!
    local targetA = {
      kind = "crate",
      itemID = 900001,
      name = "Flexible Crate A",
      tier = "Apprentice",
      requiredLevel = 1,
      alternatives = {
        { optionIndex = 1, label = "10 X", materials = { { itemID = 2589, name = "Mat X", quantity = 10 } } },
        { optionIndex = 2, label = "10 Y", materials = { { itemID = 2318, name = "Mat Y", quantity = 10 } } },
      },
    }
    local targetB = {
      kind = "crate",
      itemID = 900002,
      name = "Inflexible Crate B",
      tier = "Apprentice",
      requiredLevel = 1,
      alternatives = {
        { optionIndex = 1, label = "10 X", materials = { { itemID = 2589, name = "Mat X", quantity = 10 } } },
      },
    }
    local inv = {
      [900001] = { bagCount = 1, bankCount = 0 },
      [900002] = { bagCount = 1, bankCount = 0 },
      [2589] = { bagCount = 10, bankCount = 0 },
      [2318] = { bagCount = 10, bankCount = 0 },
    }
    local suggestion = ns.Domain.Costs.SuggestReadyTurnIns(
      inv,
      {},
      {},
      60,
      false,
      "after_bank",
      false,
      { targetA, targetB }
    )
    assertTrue(suggestion.addedGoalCount == 2, "Must suggest both Goal A and Goal B (2 goals)")
    assertTrue(suggestion.addedTurnInsCount == 2, "Must suggest 2 total turn-ins")

    local byKey = {}
    for _, sr in ipairs(suggestion.suggestedReservations) do
      byKey[sr.goalKey] = sr
    end
    assertTrue(byKey["crate:900002"].optionIndex == 1, "Inflexible Goal B must receive Option 1 (10 X)")
    assertTrue(byKey["crate:900001"].optionIndex == 2, "Flexible Goal A must receive Option 2 (10 Y)")
  end)

  -- Scenario 12: Priority Reordering (1..K Normalization) & Ready Summary / Reduce-to-Owned Safety Gates
  check("12. Priority Reordering (1..K Normalization), Ready Summary & Reduce-to-Owned Safety Gates", function()
    local charDB = ns.State.GetCharDB()
    local savedRes = charDB.reservations
    local savedNextP = charDB.nextPriority
    charDB.reservations = {}
    charDB.nextPriority = 1

    local ok, err = pcall(function()
      ns.State.ReserveGoal("crate", 248684, 1, 2) -- Prio 1: Apprentice Textiles x2 (needs 80 Linen)
      ns.State.ReserveGoal("crate", 248682, 1, 1) -- Prio 2: Apprentice Leatherwork x1
      local before = ns.State.GetOrderedReservations()
      assertTrue(#before == 2 and before[1].targetItemID == 248684 and before[2].targetItemID == 248682, "Initial order mismatch")

      -- Move 248682 up (-1) to Priority 1
      local okMove, newPrio = ns.State.MoveReservationPriority(248682, -1)
      assertTrue(okMove and newPrio == 1, "Moving 248682 up must place it at Priority 1")
      local after = ns.State.GetOrderedReservations()
      assertTrue(after[1].targetItemID == 248682 and after[1].priority == 1, "248682 must now be Priority 1")
      assertTrue(after[2].targetItemID == 248684 and after[2].priority == 2, "248684 must now be Priority 2")
      assertTrue(charDB.nextPriority == 3, "nextPriority must normalize to K + 1 (3)")

      -- Ready Summary: 1 crate of 248684 in bags, 0 in bank (planned = 2), 80 Linen in bags, plus 1 Sealed Crate (248765) in bags
      local invWithSealed = {
        [248684] = { bagCount = 1, bankCount = 0 },
        [2589] = { bagCount = 80, bankCount = 0 },
        [248765] = { bagCount = 1, bankCount = 0 },
      }
      local ready = ns.Domain.Reservations.BuildReadySummary(
        invWithSealed,
        ns.State.GetOrderedReservations(),
        false,
        { authority = "live" }
      )
      local rgTextiles = nil
      for _, rg in ipairs(ready.goals) do
        if rg.targetItemID == 248684 then
          rgTextiles = rg
        end
      end
      assertTrue(rgTextiles ~= nil, "Missing 248684 in ReadySummary")
      -- Ready in bags requires BOTH crate possession in bags (1) AND materials in bags (2) -> min(2, 1, 2) = 1
      assertTrue(rgTextiles.readyInBagsNow == 1, "Ready in bags must be 1 (gated by 1 unopened crate in bags)")
      -- Because 1 Sealed Crate (248765) is in bags, Reduce-to-Owned MUST be blocked!
      assertTrue(rgTextiles.canReduceToOwned == false, "Reduce-to-Owned must be blocked when Sealed Crates exist")

      -- Without Sealed Crates, Reduce-to-Owned is allowed and reduces plannedQty from 2 -> 1
      local invNoSealed = {
        [248684] = { bagCount = 1, bankCount = 0 },
        [2589] = { bagCount = 80, bankCount = 0 },
      }
      local readyClean = ns.Domain.Reservations.BuildReadySummary(
        invNoSealed,
        ns.State.GetOrderedReservations(),
        false,
        { authority = "live" }
      )
      local rgClean = nil
      for _, rg in ipairs(readyClean.goals) do
        if rg.targetItemID == 248684 then
          rgClean = rg
        end
      end
      assertTrue(rgClean.canReduceToOwned == true, "Reduce-to-Owned must be enabled when bank is live and no Sealed Crates exist")
      local okRed, newCount = ns.State.ReduceGoalToObservedOwnership("crate", 248684, 1, rgClean.canReduceToOwned, rgClean.reduceBlockReason)
      assertTrue(okRed and newCount == 1, "ReduceGoalToObservedOwnership must reduce quantity to 1")
    end)

    charDB.reservations = savedRes
    charDB.nextPriority = savedNextP
    ns.State.BumpReservationRevision()
    if not ok then
      error(err, 2)
    end
  end)

  -- Scenario 13: Bank Collection Plan Strictly Separates allocatedBank from allocatedAlt & Includes Banked Crates
  check("13. Bank Collection Plan Withdraws Only Character Bank (Never Alt Stock) & Includes Banked Crates", function()
    local inv = {
      [248684] = { bagCount = 0, bankCount = 2, altIneligibleCount = 5 },
      [2589] = { bagCount = 10, bankCount = 30, altEligibleCount = 40 },
    }
    local ordered = {
      {
        goalKey = "crate:248684",
        goalID = "crate:248684:1",
        kind = "crate",
        targetItemID = 248684,
        targetName = "Waylaid Crate: Apprentice Textiles",
        optionIndex = 1,
        quantity = 2,
        priority = 1,
        unitMaterials = { { itemID = 2589, name = "Linen Cloth", quantity = 40 } },
      },
    }
    -- Total required Linen = 80: 10 in bags, 30 in character bank, 40 on alt.
    -- Bank collection plan MUST pull 2 crates (248684) and ONLY 30 Linen from character bank (never 70!).
    local colPlan = ns.Domain.Reservations.BuildBankCollectionPlan(inv, ordered, true)
    assertTrue(colPlan.totalTargetUnits == 2, "Must pull 2 planned crates from character bank")
    assertTrue(colPlan.totalMaterialUnits == 30, "Must pull strictly 30 Linen from character bank (excluding 40 on alts)")
    assertTrue(colPlan.totalAltAllocatedUnits == 40, "Must track 40 alt-allocated Linen separately")
  end)

  -- Scenario 14: Transaction Lifecycle Replay (Normal, Reversed, Duplicate, BankMove, & Manual Completion Coexistence)
  check("14. Lifecycle State Machine Replays Normal, Reversed, Duplicate, BankMove & Manual Completion Cleanly", function()
    local initialRes = {
      {
        goalKey = "crate:248684",
        goalID = "crate:248684:1",
        kind = "crate",
        targetItemID = 248684,
        targetName = "Waylaid Crate: Apprentice Textiles",
        optionIndex = 1,
        quantity = 2,
        priority = 1,
        unitMaterials = { { itemID = 2589, name = "Linen Cloth", quantity = 40 } },
      },
    }

    -- Trace sequence testing:
    -- 1. Bank move (40 Linen moved from bank to bags -> charDelta = 0) -> BankMove -> Ignored
    -- 2. Fill crate 1 (248684 -1, 2589 -40, Sealed Crate 248765 +1) -> Planned -> Filled
    -- 3. Reversed delivery order for crate 1: QUEST_TURNED_IN (91899) arrives BEFORE BAG_UPDATE_DELAYED (248765 -1), plus duplicate QUEST_TURNED_IN
    -- 4. Manual completion for crate 2 (`MANUAL_COMPLETE`) followed by fill event -> ManualCompletionDeduped (no double-decrement!)
    local trace = {
      {
        seq = 1,
        kind = "INVENTORY_DELTA",
        event = "BAG_UPDATE_DELAYED",
        deltas = {
          [2589] = { itemID = 2589, bagDelta = 40, bankDelta = -40, charDelta = 0 },
        },
        context = { bankOpen = true },
      },
      {
        seq = 2,
        kind = "INVENTORY_DELTA",
        event = "BAG_UPDATE_DELAYED",
        deltas = {
          [248684] = { itemID = 248684, bagDelta = -1, bankDelta = 0, charDelta = -1 },
          [2589] = { itemID = 2589, bagDelta = -40, bankDelta = 0, charDelta = -40 },
          [248765] = { itemID = 248765, bagDelta = 1, bankDelta = 0, charDelta = 1 },
        },
        context = {},
      },
      {
        seq = 3,
        kind = "QUEST_EVENT",
        event = "QUEST_TURNED_IN",
        questID = 91899,
        turnInInstanceID = "tx1",
        context = { gossipOpen = true },
      },
      {
        seq = 4,
        kind = "QUEST_EVENT",
        event = "QUEST_TURNED_IN",
        questID = 91899,
        turnInInstanceID = "tx1", -- duplicate event
        context = { gossipOpen = true },
      },
      {
        seq = 5,
        kind = "INVENTORY_DELTA",
        event = "BAG_UPDATE_DELAYED",
        deltas = {
          [248765] = { itemID = 248765, bagDelta = -1, bankDelta = 0, charDelta = -1 },
        },
        context = { gossipOpen = true },
      },
      {
        seq = 6,
        kind = "MANUAL_COMPLETE",
        event = "USER_COMPLETE_TURNIN",
        goalKind = "crate",
        targetItemID = 248684,
        completedTurnIns = 1,
        context = {},
      },
      {
        seq = 7,
        kind = "INVENTORY_DELTA",
        event = "BAG_UPDATE_DELAYED",
        deltas = {
          [248684] = { itemID = 248684, bagDelta = -1, bankDelta = 0, charDelta = -1 },
          [2589] = { itemID = 2589, bagDelta = -40, bankDelta = 0, charDelta = -40 },
          [248765] = { itemID = 248765, bagDelta = 1, bankDelta = 0, charDelta = 1 },
        },
        context = {},
      },
    }

    local replay = ns.Domain.Diagnostics.ReplayTransactions(trace, initialRes)
    local txs = replay.transactions
    assertTrue(txs[1].classification == "BankMove", "Step 1 must classify as BankMove")
    assertTrue(txs[2].classification == "Filled" and txs[2].transition == "Planned -> Filled", "Step 2 must classify as Planned -> Filled")
    assertTrue(txs[3].classification == "DuplicateIgnored", "Duplicate QUEST_TURNED_IN must be ignored")
    assertTrue(txs[4].classification == "Delivered" and txs[4].transition == "Filled -> Delivered", "Reversed quest/bag delivery must reconcile to Filled -> Delivered")
    assertTrue(txs[5].classification == "ManualCompletion", "Step 6 must record ManualCompletion")
    assertTrue(txs[6].classification == "ManualCompletionDeduped", "Step 7 must deduplicate against manual completion without double-decrementing")
    local gs = replay.goalStateByKey["crate:248684"]
    assertTrue(gs.plannedCount == 0, "Final plannedCount must be 0 (not negative, not double-decremented)")
  end)

  local report = {
    passed = passed,
    failed = failed,
    total = passed + failed,
    results = results,
  }
  SelfTest.cachedReports.core = report
  SelfTest._running.core = false
  return report
end

-- ============================================================================
-- v0.5.0 Gold Farms & Single-Owner Navigation Acceptance Gates (GF-1 .. GF-10)
-- Maps 1-to-1 to Astra's 10 Mandatory Offline Acceptance Gates with deliberate failure cases.
-- ============================================================================
function SelfTest.RunGoldFarmsSuite()
  if SelfTest._running.gold_farms then
    error("Recursive SelfTest.RunGoldFarmsSuite invocation forbidden", 2)
  end
  SelfTest._running.gold_farms = true
  SelfTest.suiteRunCounts.gold_farms = (SelfTest.suiteRunCounts.gold_farms or 0) + 1

  local results = {}
  local passed = 0
  local failed = 0

  local function check(name, fn)
    local ok, err = pcall(fn)
    if ok then
      passed = passed + 1
      table.insert(results, { name = name, passed = true })
    else
      failed = failed + 1
      table.insert(results, { name = name, passed = false, error = tostring(err) })
    end
  end

  local catalog = ns.State.GetCompiledGoldFarms()
  local GoldFarms = ns.Domain.GoldFarms
  local RewardValue = ns.Domain.RewardValue

  local charDB = ns.State.GetCharDB()
  local savedGFProg = deepCopyTable(charDB.goldFarmProgress)
  local savedGFTelem = deepCopyTable(charDB.goldFarmTelemetry)
  local savedMountTracker = deepCopyTable(charDB.mountTracker)
  local savedGFSess = deepCopyTable(ns.State.goldFarmSession)
  local savedPlayerPos = ns.State.overridePlayerPosition
  local savedPlayerMoney = ns.State.overridePlayerMoney
  local savedWpOv = ns.State.overrideNativeWaypointState
  local savedWorldSizes = ns.State.overrideMapWorldSizes
  local savedCombat = ns.State.overrideInCombat
  local savedTT = _G.TomTom
  local savedRXP = _G.RXPGuides
  local savedRXPC = _G.RXPCData
  local navSnap = snapshotAndIsolateNavigation(charDB)

  local function resetNavOwnerForTest()
    ns.UI.Navigation.StopTravelTicker()
    ns.UI.Navigation.hydratedFromSaved = true
    ns.UI.Navigation.activeContext = "gold_farm"
    ns.UI.Navigation.owner = {
      ownerContext = nil,
      generation = 0,
      provider = "none",
      handle = nil,
      pendingRelease = false,
      pendingDestination = nil,
    }
    charDB.navigationOwner = nil
  end

  ns.State.overridePlayerPosition = { status = "unavailable" }
  ns.State.overrideMapWorldSizes = {
    [2548] = { width = 3600, height = 2400 },
    [1418] = { width = 2487, height = 1658 },
    [1435] = { width = 2293, height = 1529 },
    [1445] = { width = 5250, height = 3500 },
    [1417] = { width = 3600, height = 2400 },
    [1432] = { width = 2758, height = 1839 },
    [1431] = { width = 2700, height = 1800 },
    [1430] = { width = 2500, height = 1667 },
    [1437] = { width = 4135, height = 2757 },
    [1433] = { width = 2170, height = 1447 },
  }

  local suiteOk, suiteErr = pcall(function()
    -- Gate 1: Single Navigation Owner across legacy SavedVariables sanitization, combat deferral, failed clear, restricted read & rapid Stop
    check("GF-1. Gate 1: Single Navigation Owner Across Combat, Failed Clear, Restricted Read & Rapid Switches", function()
      resetNavOwnerForTest()
      _G.TomTom = nil
      _G.RXPGuides = nil
      _G.RXPCData = nil
      ns.State.overrideInCombat = false
      ns.State.overrideNativeWaypointState = {
        supported = true,
        current = { uiMapID = 2548, x01 = 0.6062, y01 = 0.8153 },
      }
      charDB.goldFarmProgress = ns.State.MigrateGoldFarmProgress({}, catalog)

      -- 1) Legacy Riverglades SavedVariables ownership token is sanitized into pendingRelease under gold_farm
      charDB.navigationOwner = {
        ownerContext = "riverglades",
        generation = 1,
        provider = "native_waypoint",
        handle = { uiMapID = 2548, x01 = 0.6062, y01 = 0.8153 },
        pendingRelease = false,
      }
      local migratedOwner = ns.State.EnsureNavigationOwnerInitialized(true)
      assertTrue(
        migratedOwner.ownerContext == "gold_farm"
          and migratedOwner.pendingRelease == true
          and migratedOwner.handle ~= nil,
        "Legacy Riverglades navigationOwner must convert to pendingRelease under gold_farm"
      )
      ns.UI.Navigation.hydratedFromSaved = false
      ns.UI.Navigation.HydrateOwnerFromSavedStateIfUnset()

      -- 2) Enter combat -> start Gold Farm #1 (1432): release of 2548 pin is deferred, token retained!
      ns.State.overrideInCombat = true
      local okGF, gfEval = GoldFarms.Start(1, catalog, charDB.goldFarmProgress, { status = "unavailable" })
      assertTrue(okGF, "Gold Farm #1 Start must succeed")
      local stGFDeferred = ns.UI.Navigation.SyncFromGoldFarmEvaluation(gfEval, charDB.goldFarmProgress)
      assertTrue(stGFDeferred.deferred == true, "Gold acquisition must defer while prior release is blocked in combat")
      assertTrue(ns.UI.Navigation.owner.pendingRelease == true and ns.UI.Navigation.owner.handle ~= nil, "Ownership token must be retained during combat")
      assertTrue(ns.State.overrideNativeWaypointState.current.uiMapID == 2548, "Live 2548 pin remains until combat ends")

      -- 3) Combat ends, BUT ClearNativeWaypoint fails -> token MUST still be retained (never mistaken for user pin)!
      ns.State.overrideInCombat = false
      ns.State.overrideNativeWaypointState.clearMustFail = true
      local flushFail = ns.UI.Navigation.FlushDeferredIfReady()
      assertTrue(flushFail.deferred == true and ns.UI.Navigation.owner.handle ~= nil, "Failed clear must retain ownership token")

      -- 4) Clear works, BUT GetNativeWaypoint read is restricted -> token MUST still be retained!
      ns.State.overrideNativeWaypointState.clearMustFail = false
      ns.State.overrideNativeWaypointState.readStatus = "restricted"
      local flushRestricted = ns.UI.Navigation.FlushDeferredIfReady()
      assertTrue(flushRestricted.deferred == true and ns.UI.Navigation.owner.handle ~= nil, "Restricted read must retain ownership token")

      -- 5) Restore normal read -> confirms release of 2548 AND acquires 1432 for Gold Farm!
      ns.State.overrideNativeWaypointState.readStatus = "ok"
      local flushOk = ns.UI.Navigation.FlushDeferredIfReady()
      assertTrue(flushOk.activeProvider == "native_waypoint" and not flushOk.deferred, "Gold must acquire native waypoint once clear is confirmed")
      assertTrue(ns.UI.Navigation.owner.ownerContext == "gold_farm" and ns.State.overrideNativeWaypointState.current.uiMapID == 1432, "Gold now owns 1432 pin")

      -- 6) Enter combat -> user replaces pin with custom Stormwind pin (1453) while deferred -> rapid Gold #2 (2548) -> Stop BEFORE combat ends!
      ns.State.overrideInCombat = true
      local staleGen = ns.UI.Navigation.owner.generation
      ns.State.overrideNativeWaypointState.current = { uiMapID = 1453, x01 = 0.6100, y01 = 0.7200 }
      local _, gfEvalRapid = GoldFarms.Start("rg_brineshell_twilight", catalog, charDB.goldFarmProgress, { status = "unavailable" })
      ns.UI.Navigation.SyncFromGoldFarmEvaluation(gfEvalRapid, charDB.goldFarmProgress)
      local _, gfStopEval = GoldFarms.Stop(charDB.goldFarmProgress)
      ns.UI.Navigation.SyncFromGoldFarmEvaluation(gfStopEval, charDB.goldFarmProgress)
      assertTrue(not ns.UI.Navigation.IsGenerationCurrent(staleGen), "Stale generation must be invalidated by rapid switches")
      assertTrue(ns.UI.Navigation.owner.pendingDestination == nil, "Stop must cancel pending destination")

      -- Combat ends: user's 1453 pin MUST remain untouched and no stale Gold pin may be written!
      ns.State.overrideInCombat = false
      ns.UI.Navigation.FlushDeferredIfReady()
      assertTrue(ns.State.overrideNativeWaypointState.current ~= nil and ns.State.overrideNativeWaypointState.current.uiMapID == 1453, "User replacement pin must survive rapid switch->Stop")
      assertTrue(ns.UI.Navigation.owner.provider == "none" and ns.UI.Navigation.owner.handle == nil, "Token dropped cleanly after confirmed user replacement")

      -- 7) Out-of-combat failed native clear MUST retain pendingDestination (and Pause MUST cancel pendingDestination)
      resetNavOwnerForTest()
      ns.State.overrideInCombat = false
      ns.State.overrideNativeWaypointState = { supported = true, current = nil }
      charDB.goldFarmProgress = ns.State.MigrateGoldFarmProgress({}, catalog)

      local okGF4, gfEval4 = GoldFarms.Start("rg_brineshell_twilight", catalog, charDB.goldFarmProgress, { status = "unavailable" })
      assertTrue(okGF4, "GF rg_brineshell_twilight Start failed")
      ns.UI.Navigation.SyncFromGoldFarmEvaluation(gfEval4, charDB.goldFarmProgress)
      assertTrue(ns.State.overrideNativeWaypointState.current.uiMapID == 2548, "rg_brineshell_twilight owns 2548")

      -- Out of combat, Stop with ClearNativeWaypoint failing leaves pendingRelease = true; starting GF #1 queues pendingDestination!
      ns.State.overrideNativeWaypointState.clearMustFail = true
      local _, gfStopBefore1 = GoldFarms.Stop(charDB.goldFarmProgress)
      ns.UI.Navigation.SyncFromGoldFarmEvaluation(gfStopBefore1, charDB.goldFarmProgress)
      local okGF2, gfEval2 = GoldFarms.Start(1, catalog, charDB.goldFarmProgress, { status = "unavailable" })
      assertTrue(okGF2, "GF2 Start failed")
      local stOutOfCombatFail = ns.UI.Navigation.SyncFromGoldFarmEvaluation(gfEval2, charDB.goldFarmProgress)
      assertTrue(stOutOfCombatFail.deferred == true, "Out-of-combat failed clear must defer destination acquisition")
      assertTrue(
        ns.UI.Navigation.owner.pendingRelease == true
          and ns.UI.Navigation.owner.pendingDestination ~= nil
          and ns.UI.Navigation.owner.pendingDestination.context == "gold_farm"
          and ns.UI.Navigation.owner.pendingDestination.destination ~= nil
          and ns.UI.Navigation.owner.pendingDestination.destination.uiMapID == 1432,
        "Out-of-combat failed clear must retain incoming Gold Farm pendingDestination"
      )
      assertTrue(
        charDB.navigationOwner
          and charDB.navigationOwner.pendingDestination
          and charDB.navigationOwner.pendingDestination.destination
          and charDB.navigationOwner.pendingDestination.destination.uiMapID == 1432,
        "Persisted navigationOwner must also save pendingDestination"
      )

      -- Once ClearNativeWaypoint succeeds, FlushDeferredIfReady MUST acquire Gold Farm's 1432 destination!
      ns.State.overrideNativeWaypointState.clearMustFail = false
      local flushOutOk = ns.UI.Navigation.FlushDeferredIfReady()
      assertTrue(flushOutOk.activeProvider == "native_waypoint" and not flushOutOk.deferred, "Deferred Gold destination must acquire after clear succeeds")
      assertTrue(
        ns.UI.Navigation.owner.ownerContext == "gold_farm"
          and ns.UI.Navigation.owner.provider == "native_waypoint"
          and ns.State.overrideNativeWaypointState.current.uiMapID == 1432,
        "Gold must own 1432 pin after out-of-combat failed clear recovers"
      )

      -- Explicit Pause while release is blocked out of combat MUST cancel pendingDestination
      ns.State.overrideNativeWaypointState.clearMustFail = true
      local _, gfStop3 = GoldFarms.Stop(charDB.goldFarmProgress)
      ns.UI.Navigation.SyncFromGoldFarmEvaluation(gfStop3, charDB.goldFarmProgress)
      local _, gfEval3 = GoldFarms.Start("rg_brineshell_twilight", catalog, charDB.goldFarmProgress, { status = "unavailable" })
      ns.UI.Navigation.SyncFromGoldFarmEvaluation(gfEval3, charDB.goldFarmProgress)
      assertTrue(ns.UI.Navigation.owner.pendingDestination ~= nil, "rg_brineshell_twilight pendingDestination queued while prior clear fails")
      local _, gfPause3 = GoldFarms.Pause(charDB.goldFarmProgress)
      ns.UI.Navigation.SyncFromGoldFarmEvaluation(gfPause3, charDB.goldFarmProgress)
      assertTrue(ns.UI.Navigation.owner.pendingDestination == nil, "Explicit Pause must cancel pendingDestination")
      ns.State.overrideNativeWaypointState.clearMustFail = false
      ns.UI.Navigation.FlushDeferredIfReady()
      assertTrue(ns.UI.Navigation.owner.provider == "none" and ns.State.overrideNativeWaypointState.current == nil, "After Pause + clear recovery, no stale destination may acquire")

      -- 8) Callback-capable C_Timer.NewTicker MUST advance consecutive Gold Farm travel hops without self-cancelling
      local prevCTimerGF = _G.C_Timer
      local okTickerGF, errTickerGF = pcall(function()
        local activeTickFn = nil
        local cancelCount = 0
        _G.C_Timer = {
          NewTicker = function(_, cb)
            activeTickFn = cb
            return {
              Cancel = function()
                cancelCount = cancelCount + 1
              end,
            }
          end,
          After = function(_, cb)
            if type(cb) == "function" then
              cb()
            end
          end,
        }
        resetNavOwnerForTest()
        cancelCount = 0
        activeTickFn = nil
        ns.State.overrideInCombat = false
        ns.State.overrideNativeWaypointState = { supported = true, current = nil }
        charDB.goldFarmProgress = ns.State.MigrateGoldFarmProgress({}, catalog)

        ns.State.overridePlayerPosition = { status = "ok", uiMapID = 1453, x01 = 0.6200, y01 = 0.7100 }
        local okStartTick, evStartTick = GoldFarms.Start(1, catalog, charDB.goldFarmProgress, ns.State.overridePlayerPosition)
        assertTrue(okStartTick and evStartTick.activeStep.stepID == "badlands_hop_1_thelsamar_fp", "Ticker test starts at Badlands Hop 1")
        ns.UI.Navigation.SyncFromGoldFarmEvaluation(evStartTick, charDB.goldFarmProgress)
        assertTrue(type(activeTickFn) == "function" and cancelCount == 0, "Gold travel ticker started cleanly")

        -- Tick 1: arrive at Hop 1 (1432, 0.3394, 0.5095) -> advances to Hop 2 without cancelling ticker!
        ns.State.overridePlayerPosition = { status = "ok", uiMapID = 1432, x01 = 0.3394, y01 = 0.5095 }
        activeTickFn()
        assertTrue(charDB.goldFarmProgress.currentStepID == "badlands_hop_2_south_pass", "GF Tick 1 must advance to badlands_hop_2_south_pass")
        assertTrue(cancelCount == 0, "GF travel ticker must NOT self-cancel after first generation bump")

        -- Tick 2 (same ticker closure!): arrive at Hop 2 (1432, 0.4690, 0.7700) -> advances to Hop 3 Jazzrik vendor!
        ns.State.overridePlayerPosition = { status = "ok", uiMapID = 1432, x01 = 0.4690, y01 = 0.7700 }
        activeTickFn()
        assertTrue(charDB.goldFarmProgress.currentStepID == "badlands_hop_3_jazzrik_vendor", "GF Tick 2 must advance consecutive travel hop to badlands_hop_3_jazzrik_vendor")
        assertTrue(ns.State.overrideNativeWaypointState.current.uiMapID == 1418, "GF Tick 2 must update native waypoint to Badlands 1418")
      end)
      ns.UI.Navigation.StopTravelTicker()
      _G.C_Timer = prevCTimerGF
      ns.State.overridePlayerPosition = { status = "unavailable" }
      if not okTickerGF then
        error(errTickerGF, 2)
      end
    end)

    -- Gate 2: Confirmed cleanup acknowledgment & Custom-map 2548 TomTom arrow honesty
    check("GF-2. Gate 2: Cleanup Acknowledgment Verification & Custom-Map 2548 Arrow Honesty", function()
      resetNavOwnerForTest()
      _G.TomTom = nil
      ns.State.overrideInCombat = false
      ns.State.overrideNativeWaypointState = { supported = true, current = nil }

      local prog = ns.State.MigrateGoldFarmProgress({ mode = "standalone", selectedFarmID = "arathi_exiles_circles" }, catalog)
      local ev = GoldFarms.ReconcileActive(catalog, prog, { status = "unavailable" })
      local st = ns.UI.Navigation.SyncFromGoldFarmEvaluation(ev, prog)
      assertTrue(st.activeProvider == "native_waypoint", "Set native pin on Arathi 1417")

      -- Simulate clearMustFail -> CleanupOwnedWaypoint returns false and keeps handle
      ns.State.overrideNativeWaypointState.clearMustFail = true
      local rel1, reason1 = ns.UI.Navigation.CleanupOwnedWaypoint(prog)
      assertTrue(rel1 == false and ns.UI.Navigation.owner.handle ~= nil, "Failed clear must return false and keep handle: " .. tostring(reason1))

      -- Simulate unavailable read -> still returns false and keeps handle
      ns.State.overrideNativeWaypointState.clearMustFail = false
      ns.State.overrideNativeWaypointState.readStatus = "unavailable"
      local rel2 = ns.UI.Navigation.CleanupOwnedWaypoint(prog)
      assertTrue(rel2 == false and ns.UI.Navigation.owner.handle ~= nil, "Unavailable read must keep handle")

      -- Restore read -> clears and verifies post-clear absence
      ns.State.overrideNativeWaypointState.readStatus = "ok"
      local rel3, reason3 = ns.UI.Navigation.CleanupOwnedWaypoint(prog)
      assertTrue(rel3 == true and reason3 == "confirmed_cleared" and ns.UI.Navigation.owner.handle == nil, "Token dropped only on confirmed_cleared")

      -- TomTom arrow honesty (Astra P2 #2):
      -- Bare TomTom without confirmed CrazyArrow reports delegated status (`hasDirectionalArrow = false`),
      -- confirmed visible `TomTom.crazyArrow` on Classic map 1417 reports `hasDirectionalArrow = true`,
      -- and custom map 2548 never claims a verified TomTom arrow!
      _G.TomTom = {
        AddWaypoint = function(_, m, x, y)
          return { m = m, x = x, y = y }
        end,
        RemoveWaypoint = function() end,
      }
      local stClassicDelegated = ns.UI.Navigation.SyncFromGoldFarmEvaluation(ev, prog)
      assertTrue(
        stClassicDelegated.activeProvider == "tomtom"
          and stClassicDelegated.hasDirectionalArrow == false
          and stClassicDelegated.arrowDelegated == true
          and stClassicDelegated.navigationLabel == "TomTom waypoint; arrow delegated",
        "Bare TomTom without confirmed CrazyArrow must report 'TomTom waypoint; arrow delegated' (hasDirectionalArrow=false)"
      )

      _G.TomTom.crazyArrow = { IsShown = function() return true end }
      local stClassicConfirmed = ns.UI.Navigation.SyncFromGoldFarmEvaluation(ev, prog)
      assertTrue(
        stClassicConfirmed.activeProvider == "tomtom"
          and stClassicConfirmed.hasDirectionalArrow == true
          and stClassicConfirmed.navigationLabel == "TomTom Waypoint + Arrow",
        "Confirmed visible TomTom CrazyArrow on Classic map 1417 must report 'TomTom Waypoint + Arrow'"
      )

      local progRG = ns.State.MigrateGoldFarmProgress({ mode = "standalone", selectedFarmID = "rg_brineshell_twilight" }, catalog)
      local evRG = GoldFarms.ReconcileActive(catalog, progRG, { status = "unavailable" })
      local stCustom = ns.UI.Navigation.SyncFromGoldFarmEvaluation(evRG, progRG)
      assertTrue(stCustom.activeProvider == "tomtom" and stCustom.hasDirectionalArrow == false, "Custom map 2548 TomTom must NOT claim verified directional arrow")
      ns.UI.Navigation.CleanupOwnedWaypoint(progRG)
    end)

    -- Gate 3: NPC Service & Faction Flag Validation (Jannos 1471, Jazzrik 9179, Gretchen 257087, no Hammon 2810)
    check("GF-3. Gate 3: NPC Service & Faction Flags (Jannos 1471 Repair, Jazzrik 9179, Gretchen 257087 Unknown)", function()
      local npcs = catalog.npcsByID or {}
      assertTrue(npcs[2810] == nil, "Hammon Karwn [2810] (flags=6, no repair) must NOT be in verified repair catalog")

      local jannos = npcs[1471]
      assertTrue(jannos ~= nil and jannos.name == "Jannos Ironwill", "Jannos Ironwill [1471] must be present")
      assertTrue(
        jannos.serviceRole == "vendor_repair" and jannos.serviceStatus == "verified_flags" and jannos.npcFlags == 16388,
        "Jannos must have verified_flags vendor_repair bitmask 16388"
      )

      local jazzrik = npcs[9179]
      assertTrue(
        jazzrik ~= nil and jazzrik.serviceRole == "vendor_repair" and jazzrik.serviceStatus == "verified_flags" and jazzrik.friendlyToFaction == "AH",
        "Jazzrik [9179] verified AH vendor_repair"
      )

      local gretchen = npcs[257087]
      assertTrue(
        gretchen ~= nil and gretchen.serviceStatus == "unknown" and gretchen.serviceEvidence == "subname_only_flags_missing",
        "Gretchen Mayberry [257087] missing npcFlags must remain serviceStatus='unknown'"
      )

      -- Every repair-claiming vendor step across all 5 farms must point to an NPC with verified_flags vendor_repair
      for _, farm in ipairs(catalog.farms) do
        for _, st in ipairs(farm.travelSteps or {}) do
          if st.kind == "vendor" and st.requiresRepair then
            local rec = npcs[tonumber(st.npcID)]
            assertTrue(
              rec ~= nil and rec.serviceRole == "vendor_repair" and rec.serviceStatus == "verified_flags",
              "Unverified repair NPC on " .. tostring(st.stepID)
            )
          end
        end
      end
    end)

    -- Gate 4: Closed-fail destination & NaN/Inf/pier/crossing provenance guards
    check("GF-4. Gate 4: Closed-Fail Validation Rejects NaN, Inf, Out-of-Bounds & Unreviewed Maps", function()
      local nanVal = 0 / 0
      local nx, ny = GoldFarms.NormalizedToPercent(nanVal, 0.5)
      assertTrue(nx == nil and ny == nil, "NormalizedToPercent must reject NaN")
      local ix, iy = GoldFarms.NormalizedToPercent(math.huge, 0.5)
      assertTrue(ix == nil and iy == nil, "NormalizedToPercent must reject +Inf")

      assertTrue(
        not GoldFarms.ValidateStepDestination({
          kind = "travel",
          reviewStatus = "verified",
          destination = { uiMapID = 1418, x01 = nanVal, y01 = 0.5, coordinateSpace = "uiMap01" },
        }, catalog),
        "ValidateStepDestination must reject NaN x01"
      )
      assertTrue(
        not GoldFarms.ValidateStepDestination({
          kind = "travel",
          reviewStatus = "verified",
          destination = { uiMapID = 1418, x01 = 0, y01 = 0, coordinateSpace = "uiMap01" },
        }, catalog),
        "ValidateStepDestination must reject (0,0)"
      )
      assertTrue(
        not GoldFarms.ValidateStepDestination({
          kind = "boat_crossing",
          reviewStatus = "verified",
          targetUiMapID = 99999,
          destination = { uiMapID = 1437, x01 = 0.0508, y01 = 0.6341, coordinateSpace = "uiMap01" },
        }, catalog),
        "ValidateStepDestination must reject boat_crossing with unreviewed targetUiMapID"
      )
      assertTrue(
        catalog.piersByKey and catalog.piersByKey.menethil_theramore_pier and catalog.piersByKey.menethil_theramore_pier.destUiMapID == 1445,
        "Menethil pier record must bind (0.0508, 0.6341) to Theramore destUiMapID 1445"
      )
    end)

    -- Gate 5: World-yard arrival across map sizes, missing transforms, vendor MERCHANT_CLOSED & Menethil pier guard
    check("GF-5. Gate 5: World-Yard Arrival, Missing Transform Fallback, Vendor Merchant Event & Boat Pier Guard", function()
      local testHop = {
        stepID = "test_world_yard_hop",
        kind = "travel",
        reviewStatus = "verified",
        arrivalRadiusYards = 30,
        destination = { uiMapID = 1418, x01 = 0.5000, y01 = 0.5000, coordinateSpace = "uiMap01" },
      }

      -- 0.01 delta on 2000yd map = 20yd (<=30yd -> arrives!)
      ns.State.overrideMapWorldSizes[1418] = { width = 2000, height = 2000 }
      assertTrue(
        GoldFarms.CheckHopArrival(testHop, { status = "ok", uiMapID = 1418, x01 = 0.5100, y01 = 0.5000 }, catalog) == true,
        "20 yards on 2000yd map must arrive within 30yd radius"
      )

      -- Exact same 0.01 delta on 5000yd map = 50yd (>30yd -> must NOT arrive!)
      ns.State.overrideMapWorldSizes[1418] = { width = 5000, height = 5000 }
      assertTrue(
        GoldFarms.CheckHopArrival(testHop, { status = "ok", uiMapID = 1418, x01 = 0.5100, y01 = 0.5000 }, catalog) == false,
        "50 yards on 5000yd map must NOT arrive within 30yd radius"
      )

      -- Same coordinates on wrong uiMapID -> false
      ns.State.overrideMapWorldSizes[1418] = { width = 2000, height = 2000 }
      assertTrue(
        GoldFarms.CheckHopArrival(testHop, { status = "ok", uiMapID = 1432, x01 = 0.5000, y01 = 0.5000 }, catalog) == false,
        "Same x01/y01 on wrong uiMapID must NOT arrive"
      )

      -- Missing world transform -> false ("missing_world_transform"), retaining manual completion
      ns.State.overrideMapWorldSizes[1418] = nil
      local okMissing, whyMissing = GoldFarms.CheckHopArrival(testHop, { status = "ok", uiMapID = 1418, x01 = 0.5000, y01 = 0.5000 }, catalog)
      assertTrue(okMissing == false and whyMissing == "missing_world_transform", "Missing world transform must retain manual completion")
      ns.State.overrideMapWorldSizes[1418] = { width = 2487, height = 1658 }

      -- Vendor step: standing right on Jazzrik (1418, 0.4247, 0.5250) MUST NOT auto-complete via ReconcileActive;
      -- closing merchant (`CompleteVendorStepIfNear`) DOES complete it!
      local progBadlands = ns.State.MigrateGoldFarmProgress({
        mode = "standalone",
        selectedFarmID = "badlands_elementals_coyotes",
      }, catalog)
      ns.UI.Navigation.activeContext = "gold_farm"
      local evAtJazzrik = GoldFarms.ReconcileActive(catalog, progBadlands, { status = "ok", uiMapID = 1418, x01 = 0.4247, y01 = 0.5250 })
      assertTrue(evAtJazzrik.activeStep.stepID == "badlands_hop_3_jazzrik_vendor", "Vendor step must NOT auto-complete on proximity alone")

      local doneVendor, evAfterMerchant = GoldFarms.CompleteVendorStepIfNear(
        catalog,
        progBadlands,
        { status = "ok", uiMapID = 1418, x01 = 0.4247, y01 = 0.5250 }
      )
      assertTrue(doneVendor and evAfterMerchant.activeStep.stepID == "badlands_hop_4_lesser_elementals", "MERCHANT_CLOSED near Jazzrik must advance to Camp A")

      -- Boat crossing: standing on Menethil pier (1437, 0.0508, 0.6341) completes Hop 1 (pier approach) ONLY,
      -- and MUST NOT complete Hop 2 (`boat_crossing`) until reaching Dustwallow (1445)!
      local progDust = ns.State.MigrateGoldFarmProgress({
        mode = "standalone",
        selectedFarmID = "dustwallow_muckshells_crocs",
      }, catalog)
      local evOnPier1 = GoldFarms.ReconcileActive(catalog, progDust, { status = "ok", uiMapID = 1437, x01 = 0.0508, y01 = 0.6341 })
      assertTrue(evOnPier1.activeStep.stepID == "dustwallow_hop_2_boat_to_theramore", "Reaching pier advances Hop 1 -> Hop 2 boat_crossing")
      local evStillOnPier = GoldFarms.ReconcileActive(catalog, progDust, { status = "ok", uiMapID = 1437, x01 = 0.0508, y01 = 0.6341 })
      assertTrue(evStillOnPier.activeStep.stepID == "dustwallow_hop_2_boat_to_theramore", "Standing on Menethil pier must NEVER complete boat_crossing")

      local evLandedTheramore = GoldFarms.ReconcileActive(catalog, progDust, { status = "ok", uiMapID = 1445, x01 = 0.7151, y01 = 0.5634 })
      assertTrue(evLandedTheramore.activeStep.stepID == "dustwallow_hop_3_theramore_vendor", "Landing on map 1445 completes boat_crossing -> Piter Verance")
    end)

    -- Gate 6: Progress persistence — Prev pin survives /reload, leaving farm zone recomputes entry & read-only status
    check("GF-6. Gate 6: Prev Pin Survives /reload, Leaving Zone Recomputes Entry & Paused Status Is Read-Only", function()
      ns.UI.Navigation.activeContext = "gold_farm"
      local prog = ns.State.MigrateGoldFarmProgress({
        mode = "standalone",
        selectedFarmID = "badlands_elementals_coyotes",
      }, catalog)

      -- Start in Badlands (1418): skips cross-zone entry dynamically WITHOUT writing `already_in_farm_zone`
      local evInZone = GoldFarms.ReconcileActive(catalog, prog, { status = "ok", uiMapID = 1418, x01 = 0.50, y01 = 0.15 })
      assertTrue(evInZone.activeStep.stepID == "badlands_hop_3_jazzrik_vendor", "In-zone start selects Hop 3")
      assertTrue(prog.completedTravelSteps["badlands_hop_1_thelsamar_fp"] == nil, "Must NOT persist already_in_farm_zone in completedTravelSteps")

      -- User steps back via PrevHop -> pins `badlands_hop_2_south_pass`
      local okPrev, evPrev = GoldFarms.PrevHop(catalog, prog)
      assertTrue(okPrev and evPrev.activeStep.stepID == "badlands_hop_2_south_pass", "PrevHop selects Hop 2")
      assertTrue(prog.manualPinnedStepID == "badlands_hop_2_south_pass", "PrevHop records manualPinnedStepID")

      -- Simulate `/reload` migration: `manualPinnedStepID` MUST survive and stay selected even in Badlands (1418)!
      local reloadedProg = ns.State.MigrateGoldFarmProgress(prog, catalog)
      assertTrue(reloadedProg.manualPinnedStepID == "badlands_hop_2_south_pass", "manualPinnedStepID must survive /reload")
      local evAfterReload = GoldFarms.Evaluate(catalog, reloadedProg, { status = "ok", uiMapID = 1418, x01 = 0.50, y01 = 0.15 })
      assertTrue(evAfterReload.activeStep.stepID == "badlands_hop_2_south_pass", "Pinned step stays active after /reload")

      -- Advance to Camp A inside Badlands (with Hops 1 & 2 marked complete from earlier transit), then hearth out to Stormwind (1453)!
      reloadedProg.manualPinnedStepID = nil
      reloadedProg.completedTravelSteps["badlands_hop_1_thelsamar_fp"] = { completedAt = 1, reason = "hop_arrival" }
      reloadedProg.completedTravelSteps["badlands_hop_2_south_pass"] = { completedAt = 2, reason = "hop_arrival" }
      reloadedProg.completedTravelSteps["badlands_hop_3_jazzrik_vendor"] = { completedAt = 3, reason = "merchant_closed" }
      reloadedProg.currentStepID = "badlands_hop_4_lesser_elementals"
      local evLeftZone = GoldFarms.ReconcileActive(catalog, reloadedProg, { status = "ok", uiMapID = 1453, x01 = 0.50, y01 = 0.50 })
      assertTrue(evLeftZone.activeStep.stepID == "badlands_hop_1_thelsamar_fp", "Leaving farm zone must recompute entry routing from Hop 1")

      -- Paused / inactive status inspection MUST NOT advance or mutate state even when standing on Hop 1!
      reloadedProg.mode = "paused"
      ns.State.overridePlayerPosition = { status = "ok", uiMapID = 1432, x01 = 0.3394, y01 = 0.5095 }
      local evPaused = GoldFarms.Reconcile(catalog, reloadedProg)
      assertTrue(evPaused.activeStep.stepID == "badlands_hop_1_thelsamar_fp", "Paused reconcile must be read-only")
      assertTrue(reloadedProg.completedTravelSteps["badlands_hop_1_thelsamar_fp"] == nil, "Paused reconcile must NEVER complete travel hops")
      ns.State.overridePlayerPosition = { status = "unavailable" }

      -- Candidate 3 (`swamp_jaguars_snappers`) multi-map transit routing:
      -- 1) Starting in Deadwind Pass (1430) MUST select Hop 4 (`swamp_hop_4_deadwind_pass`), NOT Darkshire FP (1431)!
      local progDeadwind = ns.State.MigrateGoldFarmProgress({
        mode = "standalone",
        selectedFarmID = "swamp_jaguars_snappers",
      }, catalog)
      local evDeadwind = GoldFarms.ReconcileActive(catalog, progDeadwind, { status = "ok", uiMapID = 1430, x01 = 0.35, y01 = 0.50 })
      assertTrue(
        evDeadwind.activeStep and evDeadwind.activeStep.stepID == "swamp_hop_4_deadwind_pass",
        "Starting Swamp farm in Deadwind Pass (1430) must select swamp_hop_4_deadwind_pass, got " .. tostring(evDeadwind.activeStep and evDeadwind.activeStep.stepID)
      )

      -- 2) Starting in Swamp of Sorrows (1435) MUST skip Duskwood vendor (`swamp_hop_2_darkshire_vendor`) and select `swamp_hop_5_west_jaguars`!
      local progSwamp = ns.State.MigrateGoldFarmProgress({
        mode = "standalone",
        selectedFarmID = "swamp_jaguars_snappers",
      }, catalog)
      local evSwamp = GoldFarms.ReconcileActive(catalog, progSwamp, { status = "ok", uiMapID = 1435, x01 = 0.15, y01 = 0.50 })
      assertTrue(
        evSwamp.activeStep and evSwamp.activeStep.stepID == "swamp_hop_5_west_jaguars",
        "Starting Swamp farm in Swamp of Sorrows (1435) must select swamp_hop_5_west_jaguars, got " .. tostring(evSwamp.activeStep and evSwamp.activeStep.stepID)
      )
      assertTrue(progSwamp.tripStartPlayerUiMapID == 1435, "tripStartPlayerUiMapID must record 1435")

      -- 3) `/reload` preserves `tripStartPlayerUiMapID == 1435`
      local reloadedSwamp = ns.State.MigrateGoldFarmProgress(progSwamp, catalog)
      assertTrue(reloadedSwamp.tripStartPlayerUiMapID == 1435, "tripStartPlayerUiMapID must survive /reload migration")
      local evSwampReloaded = GoldFarms.Evaluate(catalog, reloadedSwamp, { status = "ok", uiMapID = 1435, x01 = 0.15, y01 = 0.50 })
      assertTrue(evSwampReloaded.activeStep.stepID == "swamp_hop_5_west_jaguars", "Swamp entry stays on Hop 5 across /reload")

      -- 4) Hearthing backward to Stormwind (1453) reopens full entry routing at `swamp_hop_1_darkshire_fp`
      local evSwampHearthed = GoldFarms.ReconcileActive(catalog, reloadedSwamp, { status = "ok", uiMapID = 1453, x01 = 0.62, y01 = 0.71 })
      assertTrue(evSwampHearthed.activeStep.stepID == "swamp_hop_1_darkshire_fp", "Hearthing to Stormwind must reopen Swamp Hop 1")

      -- 5) Explicit RestartEntryFromCurrentZone in Deadwind Pass (1430) resets completed transit hops and selects Hop 4
      reloadedSwamp.completedTravelSteps["swamp_hop_1_darkshire_fp"] = { completedAt = 1, reason = "hop_arrival" }
      local okReenter, evReenter = GoldFarms.RestartEntryFromCurrentZone(
        catalog,
        reloadedSwamp,
        { status = "ok", uiMapID = 1430, x01 = 0.35, y01 = 0.50 }
      )
      assertTrue(okReenter and evReenter.activeStep.stepID == "swamp_hop_4_deadwind_pass", "RestartEntryFromCurrentZone on 1430 must select Hop 4")
    end)

    -- Gate 7: Honest cash-flow telemetry — negative rate preserved, unknown money, contamination suppression & /reload pause
    check("GF-7. Gate 7: Signed Negative Cash Flow, Unknown Money Guard, Contamination & Paused /reload", function()
      local farm = catalog.farmsByID["badlands_elementals_coyotes"]
      local mt = { standingLabel = "Honored", trainerQuoteCopper = 900000, cashReserveCopper = 20000, quoteStatus = "user_confirmed" }

      -- 1) Negative cash flow (-15000c over 900s = -6g/hr) MUST stay signed negative, NEVER clamped to 0g/hr!
      local neg = GoldFarms.EvaluateGPHAndMountETA(farm, {
        active = true,
        elapsedSeconds = 900,
        netCopperDelta = -15000,
        currentCopper = 500000,
        moneyAvailable = true,
        cleanIntervalConfirmed = true,
      }, mt)
      assertTrue(neg.liveStatus == "measured_negative" and neg.measuredCopperPerHour == -60000, "Negative rate must stay signed -60000c/hr")
      assertTrue(neg.etaMinutesMeasured == nil, "Negative rate must suppress ETA")
      local strippedNegLabel = string.gsub(string.gsub(tostring(neg.liveLabel or ""), "|c%x%x%x%x%x%x%x%x", ""), "|r", "")
      assertTrue(string.find(strippedNegLabel, "^%-6g", 1) ~= nil, "Negative label must begin with signed -6g, never 0g/hr")

      -- 2) Unknown money (`moneyAvailable = false`) MUST report "Purse Unknown" with nil rate (never "6g/hr" or "Mount Funded!")
      local unk = GoldFarms.EvaluateGPHAndMountETA(farm, {
        active = true,
        elapsedSeconds = 600,
        netCopperDelta = 10000,
        currentCopper = nil,
        moneyAvailable = false,
        cleanIntervalConfirmed = true,
      }, mt)
      assertTrue(
        unk.liveStatus == "purse_unknown" and unk.measuredCopperPerHour == nil,
        "Unknown money at 600s/10000c must set liveStatus='purse_unknown' and nil measuredCopperPerHour"
      )
      assertTrue(unk.fundingStatus == "unknown" and unk.etaMinutesMeasured == nil, "Unknown money must set fundingStatus='unknown' and nil ETA")
      assertTrue(string.find(unk.liveLabel, "Purse Unknown", 1, true) ~= nil, "Unknown money must display 'Purse Unknown'")
      assertTrue(string.find(unk.liveLabel, "6g/hr", 1, true) == nil, "Unknown money must NEVER display 6g/hr")
      assertTrue(string.find(unk.liveLabel, "Reached", 1, true) == nil and string.find(unk.liveLabel, "Funded", 1, true) == nil, "Unknown money must NEVER say Funded/Reached")

      -- 2b) GoldFarms.Start on a travel hop MUST set session phase='travel_service' (not 'camp'), and RXP mode MUST set 'rxp_untracked'
      local progPhase = ns.State.MigrateGoldFarmProgress({}, catalog)
      _G.RXPGuides = nil
      _G.RXPCData = nil
      local okStartPhase = GoldFarms.Start(1, catalog, progPhase, { status = "ok", uiMapID = 1453, x01 = 0.62, y01 = 0.71 })
      assertTrue(okStartPhase and ns.State.goldFarmSession.phase == "travel_service", "Starting on Hop 1 travel step must set phase='travel_service'")
      local okPausePhase = GoldFarms.Pause(catalog, progPhase)
      assertTrue(okPausePhase and ns.State.goldFarmSession.active == false, "GoldFarms.Pause must cleanly pause telemetry session")

      _G.RXPGuides = {
        addonLoaded = true,
        currentGuide = { group = "+ForeverHub Gold Farms", name = "Badlands — Elementals and Coyotes" },
      }
      GoldFarms.Start(1, catalog, progPhase, { status = "ok", uiMapID = 1453, x01 = 0.62, y01 = 0.71 })
      assertTrue(ns.State.goldFarmSession.phase == "rxp_untracked", "Active RXP guide must mark telemetry phase='rxp_untracked'")
      local snapRxp = ns.State.GetGoldFarmSessionSnapshot()
      assertTrue(snapRxp.phaseTimingAvailable == false, "RXP mode must report phaseTimingAvailable=false")
      _G.RXPGuides = nil

      -- 3) Mail / AH / Trade / Trainer contamination pauses interval, excludes window gold, and suppresses ETA!
      ns.State.GetGoldFarmProgress().mode = "standalone"
      ns.State.ResetGoldFarmSession("badlands_elementals_coyotes", false, 1000, 500000, "camp")
      ns.State.StartOrResumeGoldFarmSession("badlands_elementals_coyotes", 1000, 500000, "camp")
      ns.State.OnNonFarmMoneyWindowOpened("mail", 1600, 520000) -- +2g farmed in 600s before opening mail
      -- Player collects +50g from mailbox while mail is open (52g -> 102g) over 60s
      ns.State.OnNonFarmMoneyWindowClosed("mail", 1660, 1020000)
      local snapContam = ns.State.GetGoldFarmSessionSnapshot(1960, 1030000) -- +1g farmed in 300s after closing mail
      assertTrue(snapContam.elapsedSeconds == 900, "60s mail window must be excluded from active elapsedSeconds (600+300=900)")
      assertTrue(snapContam.netCopperDelta == 30000, "50g mailbox payout must be excluded from farm netCopperDelta (+2g + +1g = +3g)")
      assertTrue(snapContam.contaminated == true and snapContam.cleanIntervalConfirmed == false, "Session must be marked contaminated")
      local repContam = GoldFarms.EvaluateGPHAndMountETA(farm, snapContam, mt)
      assertTrue(repContam.etaMinutesMeasured == nil and repContam.etaSuppressionReason == "session_contaminated", "Contaminated session must suppress mount ETA")

      -- 4) `/reload` simulation: CheckpointGoldFarmTelemetry -> LoadPersistedGoldFarmTelemetry resumes PAUSED with 0 offline drift!
      ns.State.ResetGoldFarmSession("badlands_elementals_coyotes", false, 2000, 400000, "camp")
      ns.State.StartOrResumeGoldFarmSession("badlands_elementals_coyotes", 2000, 400000, "camp")
      ns.State.SetGoldFarmActivityPhase("travel", 2300, 405000) -- 300s camp
      ns.State.CheckpointGoldFarmTelemetry(2420, 415000) -- +120s travel/service, +1g50s total
      ns.State.LoadPersistedGoldFarmTelemetry() -- simulate reload 2 hours later at t=9620 with 350000c
      local snapReload = ns.State.GetGoldFarmSessionSnapshot(9620, 350000)
      assertTrue(snapReload.active == false and snapReload.pausedByReload == true, "Reload must always resume telemetry in PAUSED state")
      assertTrue(snapReload.elapsedSeconds == 420 and snapReload.campSeconds == 300 and snapReload.travelAndServiceSeconds == 120, "Camp vs travel seconds preserved across reload without offline time")
      assertTrue(snapReload.netCopperDelta == 15000, "Offline gold changes must not alter paused reload delta")
    end)

    -- Gate 8: Accounting — 20 Silk = 40s, reserved Silk excluded, unrealized Silk separate, 90g includes 1st racial mount
    check("GF-8. Gate 8: Silk Bandage Math (20 Silk = 40s), Reserved Exclusion & 90g Riding Model", function()
      -- 50 owned, 30 reserved -> 20 unreserved Silk -> 10 Heavy Silk Bandages @ 4s = 40s (4000c), NOT 80s!
      local conv20 = RewardValue.EvaluateSilkBandageConversion({ charOwned = 50, reservedTotal = 30, unreservedTotal = 20 })
      assertTrue(conv20.unreservedSilk == 20 and conv20.bandagesCraftable == 10 and conv20.vendorCopper == 4000, "20 Silk must equal 10 bandages / 40s (4000c)")

      -- 40 unreserved Silk -> 20 Heavy Silk Bandages = 80s (8000c)
      local conv40 = RewardValue.EvaluateSilkBandageConversion({ charOwned = 40, reservedTotal = 0, unreservedTotal = 40 })
      assertTrue(conv40.bandagesCraftable == 20 and conv40.vendorCopper == 8000, "40 Silk must equal 20 bandages / 80s (8000c)")

      -- All Silk reserved -> 0 convertible
      local convRes = RewardValue.EvaluateSilkBandageConversion({ charOwned = 60, reservedTotal = 60, unreservedTotal = 0 })
      assertTrue(convRes.bandagesCraftable == 0 and convRes.vendorCopper == 0, "Reserved Silk must NEVER be counted as convertible")

      -- Unrealized Silk value must stay strictly separate from purse delta
      local farm = catalog.farmsByID["rg_brineshell_twilight"]
      local gph = GoldFarms.EvaluateGPHAndMountETA(
        farm,
        { active = true, elapsedSeconds = 600, netCopperDelta = 10000, currentCopper = 500000, moneyAvailable = true, cleanIntervalConfirmed = true },
        { trainerQuoteCopper = 900000, cashReserveCopper = 0, quoteStatus = "unconfirmed_default" },
        { charOwned = 50, reservedTotal = 30, unreservedTotal = 20 }
      )
      assertTrue(gph.netCopperDelta == 10000 and gph.unrealizedSilkBandages.vendorCopper == 4000, "Unrealized Silk must never inflate realized purse delta")

      -- Mount tracker defaults & migration: 90g unconfirmed_default, legacy 95g Friendly migrated out, zero reserve warning active
      local defMt = ns.State.MigrateMountTracker({})
      assertTrue(defMt.trainerQuoteCopper == 900000 and defMt.quoteStatus == "unconfirmed_default", "90g default must be unconfirmed_default")
      local migFriendly = ns.State.MigrateMountTracker({ standingLabel = "Friendly", trainerQuoteCopper = 950000, quoteSource = "user_friendly_95g" })
      assertTrue(migFriendly.trainerQuoteCopper == 900000 and migFriendly.quoteStatus == "unconfirmed_default", "Unverified 95g Friendly preset must migrate to 90g unconfirmed_default")
      assertTrue(gph.zeroReserveWarning == true, "0c reserve must trigger zeroReserveWarning")
    end)

    -- Gate 9: RXP export progression rules, RegisterGuide() == false rejection & stale RXPCData ignored
    check("GF-9. Gate 9: RXP Export Progression Syntax, Post-pcall Rejection & Live currentGuide Only", function()
      local badlands = catalog.farmsByID["badlands_elementals_coyotes"]
      assertTrue(ns.Bridges.RXPBridge.BuildGoldFarmGuideName(badlands) == "Badlands — Elementals and Coyotes", "Guide #name must not contain rank prefix")

      local txtB, errB = ns.Bridges.RXPBridge.BuildGoldFarmGuideText(badlands, catalog)
      assertTrue(txtB ~= nil and errB == nil, "BuildGoldFarmGuideText failed: " .. tostring(errB))
      assertTrue(string.find(txtB, "#version 2", 1, true) ~= nil, "Must emit #version 2")
      assertTrue(string.find(txtB, "#name Badlands — Elementals and Coyotes", 1, true) ~= nil, "Stable #name missing")
      assertTrue(string.find(txtB, ".goto 1432,33.94,50.95,30 >>", 1, true) ~= nil, "Travel hop must emit .goto with explicit radius")
      assertTrue(string.find(txtB, "+Hop 3: Neutral Vendor & Repair Anchor — Jazzrik", 1, true) ~= nil, "Vendor hop must emit manual '+' objective")
      assertTrue(string.find(txtB, ".loop 25,1418,18.81,42.99", 1, true) ~= nil, "Multi-point camp must emit .loop 25,1418,...")
      assertTrue(string.find(txtB, "#loop", 1, true) == nil, "Single-point camps must NOT emit bogus #loop tag")

      -- Dustwallow boat crossing must target destination pier on 1445 (71.51, 56.34), NOT Menethil origin pier!
      local dust = catalog.farmsByID["dustwallow_muckshells_crocs"]
      local txtD = ns.Bridges.RXPBridge.BuildGoldFarmGuideText(dust, catalog)
      assertTrue(string.find(txtD, ".goto 1445,71.51,56.34,35 >>Hop 2: Board Boat", 1, true) ~= nil, "Boat crossing in RXP must target Theramore arrival pier on 1445")

      -- RegisterGuide returning false without error -> rejected
      _G.RXPGuides = {
        addonLoaded = true,
        guides = {},
        RegisterGuide = function()
          return false
        end,
      }
      local okRej, stRej = ns.Bridges.RXPBridge.RegisterGoldFarmGuide(1, false, catalog)
      assertTrue(not okRej and stRej == "rejected", "RegisterGuide()==false must be rejected")

      -- Stale RXPCData MUST be ignored when live RXPGuides.currentGuide differs or is nil!
      _G.RXPCData = {
        currentGuideGroup = "+ForeverHub Gold Farms",
        currentGuideName = "Badlands — Elementals and Coyotes",
      }
      _G.RXPGuides = {
        addonLoaded = true,
        currentGuide = { group = "RestedXP Alliance", name = "40-41 Badlands" },
      }
      assertTrue(ns.Bridges.RXPBridge.IsGoldFarmGuideSelected("badlands_elementals_coyotes", catalog) == false, "Stale RXPCData must NEVER mark Gold Farm guide selected")
    end)

    -- Gate 10: Doctor diagnostics (read-only, non-recursive, addon versions + map capability matrix) & copy hygiene
    check("GF-10. Gate 10: Read-Only Non-Recursive Doctor Capability Matrix & Zero Legacy Economic Errors", function()
      local captured = {}
      local origPrint = ns.Compat.Print
      local countBeforeDoc = SelfTest.suiteRunCounts.gold_farms
      local okDoc, errDoc = pcall(function()
        ns.Compat.Print = function(msg)
          table.insert(captured, tostring(msg or ""))
        end
        charDB.goldFarmProgress = ns.State.MigrateGoldFarmProgress({
          mode = "paused",
          selectedFarmID = "badlands_elementals_coyotes",
        }, catalog)
        ns.State.overridePlayerPosition = { status = "ok", uiMapID = 1432, x01 = 0.3394, y01 = 0.5095 }
        ns.Events.RunGoldFarmsDoctor()
      end)
      ns.Compat.Print = origPrint
      ns.State.overridePlayerPosition = { status = "unavailable" }
      if not okDoc then
        error(errDoc, 2)
      end

      assertTrue(
        SelfTest.suiteRunCounts.gold_farms == countBeforeDoc,
        "RunGoldFarmsDoctor must NEVER recursively re-enter RunGoldFarmsSuite"
      )
      local joined = table.concat(captured, "\n")
      assertTrue(string.find(joined, "Dependencies:", 1, true) ~= nil, "Doctor must report dependency addon states")
      assertTrue(string.find(joined, "Map Capabilities", 1, true) ~= nil, "Doctor must report map world-size & waypoint capabilities")
      assertTrue(string.find(joined, "Net Purse Change / Active Hr:", 1, true) ~= nil, "Doctor must report Net Purse Change / Active Hr")
      assertTrue(charDB.goldFarmProgress.completedTravelSteps["badlands_hop_1_thelsamar_fp"] == nil, "Doctor must NEVER mutate paused progress")

      -- Copy hygiene: zero occurrences of "72g" or "Raw GPH" in compiled farm strings
      for _, farm in ipairs(catalog.farms) do
        local blob = string.format(
          "%s %s %s %s",
          tostring(farm.howToGetThereSummary or ""),
          tostring(farm.magePullNotes or ""),
          tostring(farm.mageSafety or ""),
          tostring(farm.gphMeta and farm.gphMeta.payoutBasis or "")
        )
        assertTrue(string.find(blob, "72g", 1, true) == nil, "Forbidden 72g+18g text in " .. tostring(farm.farmID))
        assertTrue(string.find(blob, "Raw GPH", 1, true) == nil, "Forbidden 'Raw GPH' label in " .. tostring(farm.farmID))
      end
    end)
  end)

  restoreNavigationSnapshot(navSnap, charDB)
  charDB.goldFarmProgress = savedGFProg
  charDB.goldFarmTelemetry = savedGFTelem
  charDB.mountTracker = savedMountTracker
  ns.State.goldFarmSession = savedGFSess
  ns.State.overridePlayerPosition = savedPlayerPos
  ns.State.overridePlayerMoney = savedPlayerMoney
  ns.State.overrideNativeWaypointState = savedWpOv
  ns.State.overrideMapWorldSizes = savedWorldSizes
  ns.State.overrideInCombat = savedCombat
  _G.TomTom = savedTT
  _G.RXPGuides = savedRXP
  _G.RXPCData = savedRXPC

  local report = {
    passed = passed,
    failed = failed,
    total = passed + failed,
    results = results,
  }
  if suiteOk then
    SelfTest.cachedReports.gold_farms = report
  end
  SelfTest._running.gold_farms = false

  if not suiteOk then
    error(suiteErr, 2)
  end

  return report
end

-- ============================================================================
-- ForeverHub v0.8.0 Workspace & Crates Vertical Slice Self-Test Suite (Stage 1)
-- ============================================================================

function SelfTest.RunWorkspaceUISuite()
  if SelfTest._running.workspace_ui then
    error("Recursive SelfTest.RunWorkspaceUISuite invocation forbidden", 2)
  end
  SelfTest._running.workspace_ui = true
  SelfTest.suiteRunCounts.workspace_ui = (SelfTest.suiteRunCounts.workspace_ui or 0) + 1

  local results = {}
  local passed = 0
  local failed = 0

  local function check(name, fn)
    local ok, err = pcall(fn)
    if ok then
      passed = passed + 1
      table.insert(results, { name = name, passed = true })
    else
      failed = failed + 1
      table.insert(results, { name = name, passed = false, error = tostring(err) })
    end
  end

  local db = ns.State.GetDB()
  local charDB = ns.State.GetCharDB()
  local navSnap = snapshotAndIsolateNavigation(charDB)
  local savedUIWorkspace = deepCopyTable(db.uiWorkspace)
  local savedSettings = deepCopyTable(db.settings)
  local savedReservations = deepCopyTable(charDB.reservations)
  local savedNextPriority = charDB.nextPriority
  local savedGFProg = deepCopyTable(charDB.goldFarmProgress)
  local savedUserConfirmedTitles = deepCopyTable(charDB.userConfirmedCompletedQuestTitles or {})
  local savedLastUndo = ns.State.lastSuggestionSnapshot
  local savedUndoReason = ns.State.lastUndoReason
  local savedDraft = ns.UI and ns.UI.Crates and deepCopyTable(ns.UI.Crates.draftState) or nil
  local wasShown = (ns.UI and ns.UI.Workspace and ns.UI.Workspace.frame and type(ns.UI.Workspace.frame.IsShown) == "function" and ns.UI.Workspace.frame:IsShown()) or false

  local suiteOk, suiteErr = pcall(function()
    local Theme = ns.UI.Theme
    local Widgets = ns.UI.Widgets
    local Presenter = ns.UI.CratesPresenter
    local Workspace = ns.UI.Workspace
    local CratesUI = ns.UI.Crates

    -- UI-01: Pure Presenter Snapshot Isolation, Bank-Only Ownership Truthfulness & Missing Price Honesty
    check("UI-01. Pure Presenter Snapshot Isolation, Bank-Only Ownership & Truthful Unpriced Money", function()
      assertTrue(type(Presenter) == "table" and type(Presenter.Build) == "function", "CratesPresenter must be loaded")

      -- Find Apprentice Herbs or Apprentice Textiles crate
      local herbsID = nil
      local multiMatID = nil
      for id, crate in pairs((ns.Data and ns.Data.cratesByItemID) or {}) do
        if type(crate.alternatives) == "table" and #crate.alternatives >= 2 then
          if not herbsID then
            herbsID = tonumber(id)
          end
          for _, alt in ipairs(crate.alternatives) do
            if type(alt.materials) == "table" and #alt.materials >= 2 then
              multiMatID = tonumber(id)
              break
            end
          end
        end
      end
      assertTrue(herbsID ~= nil, "Expected multi-option Waylaid Crate in compiled dataset")
      local herbsRec = ns.Data.cratesByItemID[herbsID]
      local opt1MatID = herbsRec.alternatives[1].materials[1].itemID
      local opt2MatID = herbsRec.alternatives[2].materials[1].itemID

      -- Snapshot: 2 crates in BANK ONLY (`bagCount=0, bankCount=2`), Option 1 priced, Option 2 unpriced!
      local snap = Presenter.CaptureSnapshot({
        inventorySnapshot = {
          [herbsID] = { bagCount = 0, bankCount = 2 },
          [opt1MatID] = { bagCount = 0, bankCount = 0 },
          [opt2MatID] = { bagCount = 0, bankCount = 0 },
        },
        bankMeta = { authority = "fh_cache", label = "Bank: Cached", complete = true },
        orderedReservations = {
          {
            goalKey = string.format("crate:%d", herbsID),
            kind = "crate",
            targetItemID = herbsID,
            targetName = herbsRec.name,
            optionIndex = 2,
            quantity = 1,
            priority = 1,
            unitMaterials = herbsRec.alternatives[2].materials,
          },
        },
        priceMap = {
          [opt1MatID] = { unitPrice = 45, ageDays = 0 },
          -- opt2MatID intentionally missing (unpriced)!
        },
        includeAltStock = false,
        acquisitionMode = "after_bank",
      })

      local invRevBefore, resRevBefore, priceRevBefore = ns.State.GetRevisions()
      local snapBefore = deepCopyTable(snap)
      local uiState = {
        cratesView = { searchQuery = "", scope = "owned_planned", readyOnly = false, expandedByKey = {} },
      }
      local vm1 = Presenter.Build(snap, uiState, { byGoalKey = {} })
      local vm2 = Presenter.Build(snap, uiState, { byGoalKey = {} })
      local invRevAfter, resRevAfter, priceRevAfter = ns.State.GetRevisions()

      assertTrue(invRevBefore == invRevAfter and resRevBefore == resRevAfter and priceRevBefore == priceRevAfter, "Pure Presenter.Build must NEVER bump State revisions")
      assertTrue(#snap.orderedReservations == #snapBefore.orderedReservations, "Presenter.Build must NEVER mutate input snapshot")
      assertTrue(#vm1.cards == #vm2.cards and #vm1.cards == 1, "Expected 1 owned/reserved card in viewModel")

      local card = vm1.cards[1]
      -- Bank-only crate MUST NOT be labeled green "Ready in bags"!
      assertTrue(card.bagCount == 0 and card.bankCount == 2, "Card ownership counts mismatch")
      if card.readinessBadge then
        assertTrue(card.readinessBadge.token ~= "status.ready", "Bank-only crate MUST NEVER carry status.ready green badge")
      end

      -- Best option criterion must explicitly state "Best · Lowest known buy cost" when sibling is unpriced
      local opt1VM = card.options[1]
      local opt2VM = card.options[2]
      assertTrue(opt1VM.isBest and opt1VM.bestLabel == "Best · Lowest known buy cost", "Partial price coverage must label 'Best · Lowest known buy cost', got: " .. tostring(opt1VM.bestLabel))
      assertTrue(string.find(opt2VM.estCostFormatted, "Unpriced", 1, true) ~= nil, "Missing price must render 'Unpriced', never 'unk' or '0c'")
      assertTrue(string.find(opt2VM.estCostFormatted, "unk", 1, true) == nil, "Legacy 'unk' string must NEVER appear")

      -- KPI 4 (Estimated purchases) when reserved item is unpriced MUST say "Unpriced" + "1 unpriced item", NEVER "0c"!
      local kpi4 = vm1.kpis[4]
      assertTrue(kpi4.value == "Unpriced", "Unpriced shopping deficit must display 'Unpriced', never '0c': " .. tostring(kpi4.value))
      assertTrue(string.find(kpi4.sub, "1 unpriced", 1, true) ~= nil, "KPI 4 subtitle must report unpriced item count")

      -- Direct Theme.FormatMoney checks
      local missingCompact = Theme.FormatMoney(nil, { compactMissing = true, plainText = true })
      local missingFull = Theme.FormatMoney(nil, { compactMissing = false, plainText = true })
      local zeroKnown = Theme.FormatMoney(0, { plainText = true })
      local estKnown = Theme.FormatMoney(320, { estimated = true, plainText = true })
      assertTrue(missingCompact == "—", "Compact missing price must be em-dash")
      assertTrue(missingFull == "Unpriced", "Full missing price must be 'Unpriced'")
      assertTrue(zeroKnown == "0c", "Known zero copper must be '0c'")
      assertTrue(estKnown == "~3s 20c", "Estimated positive copper must be '~3s 20c', got: " .. tostring(estKnown))
    end)

    -- UI-02: Draft vs Commit Isolation, Undo Clear Plan & Non-Mutating Tab Switching
    check("UI-02. Draft vs Commit Isolation, Clear-Plan Undo & Non-Mutating Tab Switching", function()
      charDB.reservations = {}
      charDB.nextPriority = 1
      ns.State.BumpReservationRevision()
      CratesUI.draftState = { byGoalKey = {} }

      Workspace.Show("crates")
      local _, resRev0 = ns.State.GetRevisions()
      assertTrue(#ns.State.GetOrderedReservations() == 0, "Expected 0 initial reservations")

      -- Drafting option & quantities (1 -> 5 -> 12) MUST NOT touch State reservations!
      CratesUI.Dispatch("SELECT_DRAFT_OPTION", { goalKey = "crate:248684", optionIndex = 2 })
      CratesUI.Dispatch("SET_DRAFT_QUANTITY", { goalKey = "crate:248684", quantity = 5 })
      CratesUI.Dispatch("SET_DRAFT_QUANTITY", { goalKey = "crate:248684", quantity = 12 })
      local _, resRevAfterDraft = ns.State.GetRevisions()
      assertTrue(#ns.State.GetOrderedReservations() == 0 and resRevAfterDraft == resRev0, "Draft edits MUST NEVER call State.ReserveGoal")

      -- Explicit COMMIT_RESERVATION persists once!
      local committed = CratesUI.Dispatch("COMMIT_RESERVATION", {
        kind = "crate",
        itemID = 248684,
        goalKey = "crate:248684",
        optionIndex = 2,
        quantity = 5,
      })
      assertTrue(committed == true, "COMMIT_RESERVATION failed")
      local ordered1 = ns.State.GetOrderedReservations()
      assertTrue(#ordered1 == 1 and ordered1[1].optionIndex == 2 and ordered1[1].quantity == 5, "Committed reservation mismatch")

      -- Request Clear Plan -> Cancel -> Confirm -> Undo restores reservation!
      CratesUI.Dispatch("REQUEST_CLEAR_PLAN")
      assertTrue(#ns.State.GetOrderedReservations() == 1, "REQUEST_CLEAR_PLAN preview must not delete reservations before confirmation")
      CratesUI.Dispatch("CONFIRM_CLEAR_PLAN")
      assertTrue(#ns.State.GetOrderedReservations() == 0, "CONFIRM_CLEAR_PLAN must clear reservations")
      CratesUI.Dispatch("UNDO_LAST_ACTION")
      local orderedRestored = ns.State.GetOrderedReservations()
      assertTrue(#orderedRestored == 1 and orderedRestored[1].quantity == 5, "UNDO_LAST_ACTION must restore cleared plan")

      -- Switching tabs to Gold, Advisor & Crates MUST NOT start navigation or mutate paused farm progress!
      charDB.goldFarmProgress.mode = "paused"
      local sessActiveBefore = ns.State.goldFarmSession and ns.State.goldFarmSession.active or false
      Workspace.SetActiveTab("gold")
      Workspace.SetActiveTab("advisor")
      Workspace.SetActiveTab("crates")
      assertTrue(charDB.goldFarmProgress.mode == "paused", "Switching to Gold tab MUST NOT start Gold Farm navigation")
      assertTrue((ns.State.goldFarmSession and ns.State.goldFarmSession.active or false) == sessActiveBefore, "Switching tabs MUST NOT activate farm telemetry")

      -- Schema v3: Gold & Farms ('gold') is default opening tab, migrates retired 'riverglades' tab -> 'gold', preserves valid tabs across reloads, and occupies featured Slot #1
      local freshUI = ns.State.MigrateWorkspaceUIState(nil, db.settings)
      assertTrue(freshUI.schemaVersion == 3 and freshUI.activeTab == "gold", "Fresh uiWorkspace must default to 'gold' (schema v3)")
      local migratedV2RG = ns.State.MigrateWorkspaceUIState({ schemaVersion = 2, activeTab = "riverglades", width = 1040 }, db.settings)
      assertTrue(migratedV2RG.schemaVersion == 3 and migratedV2RG.activeTab == "gold" and migratedV2RG.width == 1040, "Retired 'riverglades' activeTab must migrate to 'gold' while preserving geometry")
      local migratedCrates = ns.State.MigrateWorkspaceUIState({ schemaVersion = 2, activeTab = "crates", width = 1040 }, db.settings)
      assertTrue(migratedCrates.schemaVersion == 3 and migratedCrates.activeTab == "crates" and migratedCrates.width == 1040, "Valid 'crates' activeTab must be preserved across migration")
      db.uiWorkspace.activeTab = "crates"
      ns.State.EnsureWorkspaceUIStateInitialized(false)
      assertTrue(db.uiWorkspace.activeTab == "crates", "In-session Workspace state must preserve current tab")
      ns.State.EnsureWorkspaceUIStateInitialized(true)
      assertTrue(db.uiWorkspace.activeTab == "crates", "ADDON_LOADED must preserve last valid activeTab ('crates')")

      if Workspace.frame and Workspace.frame.tabBar and Workspace.frame.tabBar.__tabs then
        local firstTab = Workspace.frame.tabBar.__tabs[1]
        assertTrue(
          firstTab and firstTab.__key == "gold" and firstTab.__featured == true and firstTab.__iconGlyph == "travel",
          "Gold & Farms must occupy featured Slot #1 with compass glyph"
        )
        assertTrue(type(firstTab.__badgeText) == "string" and firstTab.__badgeText ~= "", "Gold & Farms pill badge must populate live on Workspace.Refresh")
      end
    end)

    -- UI-03: Layout Measurement & Zero-Overlap Geometry across 960x640, 760x520 Compact, and 1.25x Scale
    check("UI-03. Layout Geometry: Zero Overlap at 960x640, 760x520 Compact & 1.25x Scale (Multi-Material)", function()
      local syntheticCrateID = 999880
      local prevSynthetic = ns.Data and ns.Data.cratesByItemID and ns.Data.cratesByItemID[syntheticCrateID] or nil
      if ns.Data and ns.Data.cratesByItemID then
        ns.Data.cratesByItemID[syntheticCrateID] = {
          kind = "crate",
          itemID = syntheticCrateID,
          name = "Waylaid Crate: Multi-Material Layout Probe",
          tier = "Journeyman",
          requiredLevel = 20,
          alternatives = {
            {
              optionIndex = 1,
              label = "20x Linen Cloth + 10x Light Leather",
              materials = {
                { itemID = 2589, name = "Linen Cloth", quantity = 20 },
                { itemID = 2318, name = "Light Leather", quantity = 10 },
              },
            },
            {
              optionIndex = 2,
              label = "10x Wool Cloth",
              materials = {
                { itemID = 2592, name = "Wool Cloth", quantity = 10 },
              },
            },
          },
        }
      end

      local okGeom, errGeom = pcall(function()
        local st = ns.State.GetWorkspaceUIState()
        st.cratesView.scope = "all"
        st.cratesView.searchQuery = ""
        st.cratesView.readyOnly = false
        st.cratesView.expandedByKey = {
          ["crate:248684"] = true,
          ["crate:248683"] = true,
          ["crate:999880"] = true,
        }

        local function assertDisjointColumns(rep, label)
          assertTrue(type(rep) == "table" and #(rep.cards or {}) >= 10, "Expected >=10 cards in layout report for " .. label)
          local c = rep.columns
          local orderedCols = { c.icon, c.mat, c.bags, c.bank, c.buy, c.cost }
          if c.plan then
            table.insert(orderedCols, c.plan)
          end
          for i = 1, #orderedCols - 1 do
            local leftCol = orderedCols[i]
            local rightCol = orderedCols[i + 1]
            assertTrue(
              (leftCol.x + leftCol.w) <= rightCol.x,
              string.format("%s column overlap between col %d (%d+%d) and col %d (%d)", label, i, leftCol.x, leftCol.w, i + 1, rightCol.x)
            )
          end
          assertTrue(orderedCols[#orderedCols].x + orderedCols[#orderedCols].w <= rep.rowWidth, label .. " rightmost column exceeds rowWidth")

          local sawMultiMaterial = false
          for _, cardRep in ipairs(rep.cards) do
            assertTrue(cardRep.headerHeight >= Theme.METRICS.crateHeaderHeight, label .. " card header below min 56")
            assertTrue(cardRep.headerTextBox.width >= 160, label .. " card header text squeezed below 160")
            if cardRep.isExpanded then
              for _, optRep in ipairs(cardRep.options or {}) do
                local sumIng = 0
                for _, ing in ipairs(optRep.ingredients or {}) do
                  assertTrue(ing.height >= Theme.METRICS.ingredientRowMinHeight, label .. " ingredient row below min 40")
                  sumIng = sumIng + ing.height
                end
                if #(optRep.ingredients or {}) >= 2 then
                  sawMultiMaterial = true
                end
                assertTrue(
                  optRep.height >= (16 + sumIng + Theme.METRICS.optionFooterHeight),
                  string.format("%s option height %d smaller than 16 + %d + 32", label, optRep.height, sumIng)
                )
                if rep.isCompact and optRep.isSelected and optRep.controls.qtyEditor and optRep.controls.primaryBtn then
                  assertTrue(
                    (optRep.controls.qtyEditor.x + optRep.controls.qtyEditor.w) < optRep.controls.primaryBtn.x,
                    label .. " compact QuantityEditor overlaps Primary Button"
                  )
                end
              end
            end
          end
          assertTrue(sawMultiMaterial, label .. " test must exercise multi-material crate option height calculation")
        end

        -- 1) Default 960x640 @ 1.0x text scale (Standard 912 rowWidth)
        st.compactOverride = nil
        st.textScale = 1.0
        Theme.appliedFontScale = nil
        Workspace.Show("crates")
        Workspace.SetDimensions(960, 640)
        local rep960 = CratesUI.RenderInHost(928, 560, false)
        assertTrue(rep960.rowWidth == 912 and rep960.isCompact == false, "960 width must yield 912 standard rowWidth")
        assertTrue(rep960.columns.mat.x == 48 and rep960.columns.mat.w == 248 and rep960.columns.plan.x == 648 and rep960.columns.plan.w == 252, "Exact Astra 912 column coords mismatch")
        assertDisjointColumns(rep960, "Standard-960@1.0x")

        -- 2) Minimum 760x520 @ 1.0x text scale (Dedicated Compact 712 rowWidth)
        Workspace.SetDimensions(760, 520)
        local rep760 = CratesUI.RenderInHost(728, 440, true)
        assertTrue(rep760.rowWidth == 712 and rep760.isCompact == true and rep760.columns.plan == nil, "760 width must activate dedicated Compact layout")
        assertDisjointColumns(rep760, "Compact-760@1.0x")

        -- 3) Minimum 760x520 @ 1.25x text scale
        st.textScale = 1.25
        Theme.appliedFontScale = nil
        local rep760Scale125 = CratesUI.RenderInHost(728, 440, true)
        assertDisjointColumns(rep760Scale125, "Compact-760@1.25x")
        st.textScale = 1.0
        Theme.appliedFontScale = nil
      end)

      if ns.Data and ns.Data.cratesByItemID then
        ns.Data.cratesByItemID[syntheticCrateID] = prevSynthetic
      end
      if not okGeom then
        error(errGeom, 2)
      end
    end)

    -- UI-04: Atlas Capability Fallback & Pool Reuse Stability
    check("UI-04. Atlas Capability Fallback & Pooled Re-Render Hygiene", function()
      local fallbackShown = false
      local fallbackTextVal = nil
      local texHidden = false
      local fakeTexWithoutTexCoord = {
        SetTexture = function() end,
        Hide = function() texHidden = true end,
      }
      local fakeFallbackFS = {
        SetText = function(_, t) fallbackTextVal = t end,
        Show = function() fallbackShown = true end,
      }
      local usedAtlas = Widgets.ApplyGlyph(fakeTexWithoutTexCoord, fakeFallbackFS, "close", "text.primary")
      assertTrue(usedAtlas == false and texHidden == true and fallbackShown == true and fallbackTextVal == "×", "Missing SetTexCoord MUST hide atlas texture and show clean fallback glyph")

      -- Verify repeated renders reuse pools without growing pool sizes unboundedly
      CratesUI.RenderInHost(928, 560, false)
      local cards1 = #CratesUI.cardPool
      local opts1 = #CratesUI.optionPool
      local ings1 = #CratesUI.ingredientRowPool
      local badges1 = #CratesUI.badgePool
      CratesUI.RenderInHost(928, 560, false)
      CratesUI.RenderInHost(928, 560, false)
      assertTrue(
        #CratesUI.cardPool == cards1 and #CratesUI.optionPool == opts1 and #CratesUI.ingredientRowPool == ings1 and #CratesUI.badgePool == badges1,
        "Repeated identical renders must reuse pooled widgets with zero pool growth"
      )
    end)

    -- UI-06: Surface C (Gold & Mount) 5 Honest KPIs, Suppressed Short-Sample ETA & Single Primary Button Invariant
    check("UI-06. Surface C (Gold & Mount): Honest ETA Suppression, >=80h Farm Cards & Single Primary CTA", function()
      local GoldPresenter = ns.UI.GoldFarmsPresenter
      local GoldUI = ns.UI.GoldFarms
      assertTrue(type(GoldPresenter) == "table" and type(GoldUI) == "table", "GoldFarmsPresenter and GoldFarmsUI must be loaded")

      charDB.goldFarmProgress.mode = "paused"
      charDB.goldFarmProgress.selectedFarmID = nil
      local snapShort = GoldPresenter.CaptureSnapshot()
      -- Force a < 3m active session sample to verify honest suppression (never fabricated ETA!)
      snapShort.sessionSnap = {
        active = true,
        farmID = "badlands_elementals_coyotes",
        moneyAvailable = true,
        currentCopper = 500000,
        startCopper = 488000,
        netCopper = 12000,
        elapsedSeconds = 45,
        contaminated = false,
      }
      snapShort.gphReport = ns.Domain.GoldFarms.EvaluateGPHAndMountETA(
        snapShort.catalog.farms[1],
        snapShort.sessionSnap,
        snapShort.mountTracker
      )
      local st = ns.State.GetWorkspaceUIState()
      local vmShort = GoldPresenter.Build(snapShort, st)
      assertTrue(#vmShort.kpis == 5, "Gold & Mount must present 5 KPIs")
      assertTrue(
        vmShort.kpis[4].value == "Collecting" and vmShort.kpis[5].value == "Collecting session data",
        "Short (<3m) session MUST display 'Collecting' / 'Collecting session data', never a fabricated GPH or Mount ETA"
      )

      Workspace.Show("gold")
      Workspace.SetDimensions(960, 640)
      local gfRep = GoldUI.RenderInHost(928, 560, false, snapShort)
      assertTrue(#gfRep.cards == 5, "Expected all 5 verified farm cards")
      assertTrue(gfRep.primaryGoldButtonCount == 1, "Strictly 1 farm card may hold primary gold 'Navigate' CTA while paused")
      for _, cRep in ipairs(gfRep.cards) do
        assertTrue(cRep.collapsedHeight >= 80, "Farm card collapsed height must be >= 80")
        assertTrue(cRep.hasNextHopVisible == false, "Next hop must be hidden when no farm route is actively navigating")
      end
    end)

    -- UI-07: Surface D (Compact Tracker HUD 240x48, Schema v3 Migration, Parent-Chain Visibility & State Transitions)
    check("UI-07. Surface D (Compact Tracker HUD): 240x48 Default, Schema v3 Migration, Parent-Chain Visibility & State Transitions", function()
      local Nav = ns.UI.Navigation
      if Nav and type(_G.CreateFrame) == "function" then
        local arrowSettings = ns.State.GetArrowSettings()
        local gfProg = ns.State.GetGoldFarmProgress()
        local savedArrowSettings = deepCopyTable(arrowSettings)
        local savedGfProg = deepCopyTable(gfProg)
        local prevSuppress = Nav.suppressHUDCreation

        local function getWidgetParent(w)
          if type(w) ~= "table" then
            return nil
          end
          if type(w.GetParent) == "function" then
            return w:GetParent()
          end
          return w.__parent
        end

        local function isEffectivelyVisible(widget)
          local cur = widget
          local depth = 0
          while cur and depth < 12 do
            if type(cur.IsShown) == "function" and cur:IsShown() ~= true then
              return false
            end
            local parent = getWidgetParent(cur)
            if not parent or parent == cur or parent == _G.UIParent then
              break
            end
            cur = parent
            depth = depth + 1
          end
          return widget ~= nil
        end

        local function fireButtonClick(btn)
          if not btn then return end
          if type(btn.__onClick) == "function" then
            btn:__onClick("LeftButton")
          elseif btn.__scripts and type(btn.__scripts["OnClick"]) == "function" then
            btn.__scripts["OnClick"](btn, "LeftButton")
          elseif type(btn.GetScript) == "function" and type(btn:GetScript("OnClick")) == "function" then
            btn:GetScript("OnClick")(btn, "LeftButton")
          end
        end

        -- If live frames had not yet been instantiated before this suite, keep any newly created frames hidden in navSnap
        -- so real WoW never creates duplicate global frame names on repeated `/fh selftest` runs.
        local okNavTest, errNavTest = pcall(function()
          -- 1) Schema v2 -> v3 idempotent migration & custom width [200, 440] checks
          local mockSettings = ns.State.MigrateArrowSettings({ schemaVersion = 2, hudWidth = 340 })
          assertTrue(mockSettings.schemaVersion == 3, "MigrateArrowSettings must upgrade schemaVersion to 3")
          assertTrue(mockSettings.hudWidth == 240, "v2 default hudWidth 340 must migrate to 240")
          -- Idempotency: user explicitly sets 340 on v3 -> must stay 340!
          mockSettings.hudWidth = 340
          mockSettings = ns.State.MigrateArrowSettings(mockSettings)
          assertTrue(mockSettings.hudWidth == 340, "v3 custom hudWidth 340 must not be overwritten on repeat migration")
          -- Clamp range [200, 440]
          mockSettings.hudWidth = 150
          mockSettings = ns.State.MigrateArrowSettings(mockSettings)
          assertTrue(mockSettings.hudWidth == 200, "hudWidth below 200 must clamp to 200")
          mockSettings.hudWidth = 520
          mockSettings = ns.State.MigrateArrowSettings(mockSettings)
          assertTrue(mockSettings.hudWidth == 440, "hudWidth above 440 must clamp to 440")

          -- Only instantiate test HUD/Arrow frames when no live HUD/Arrow existed prior to snapshot isolation,
          -- or in headless unit tests where live frames are pure Lua tables.
          local canInstantiateIsolatedFrames = (navSnap.frame == nil and navSnap.arrowFrame == nil)
            or (navSnap.frame and type(navSnap.frame.__scripts) == "table")
          if not canInstantiateIsolatedFrames then
            return
          end
          Nav.suppressHUDCreation = false

          arrowSettings.enabled = true
          arrowSettings.dockedInHud = true
          arrowSettings.hudHidden = false
          arrowSettings.hudLocked = false
          arrowSettings.hudWidth = 240
          arrowSettings.renderer = "foreverhub"

          local mockFarm = {
            farmID = "rg_brineshell_twilight",
            shortLabel = "Farholde Coast",
            title = "Riverglades: Farholde Coast Clackers & Twilight Raiders",
            zoneName = "Riverglades",
          }
          gfProg.mode = "standalone"
          gfProg.selectedFarmID = "rg_brineshell_twilight"
          gfProg.pausedHudRetained = false
          Nav.SyncFromGoldFarmEvaluation({
            farm = mockFarm,
            stepIndex = 1,
            totalSteps = 4,
            activeStep = {
              stepID = "rg_hop_1_farholde_fp",
              kind = "travel",
              title = "Hop 1: Arrive at Farholde Keep",
              destination = { uiMapID = 2548, x01 = 0.6062, y01 = 0.8153, zoneName = "Riverglades" },
            },
          }, gfProg)
          Nav.RefreshArrowSettings()

          local snapDocked = Nav.GetLiveArrowSnapshot()
          assertTrue(
            not (snapDocked.dockedVisible and snapDocked.floatingVisible),
            "Docked HUD arrow and floating arrow MUST NEVER be visible simultaneously"
          )
          if Nav.frame then
            local hudW = (type(Nav.frame.GetWidth) == "function" and Nav.frame:GetWidth()) or Nav.frame.__width
            local hudH = (type(Nav.frame.GetHeight) == "function" and Nav.frame:GetHeight()) or Nav.frame.__height
            assertTrue(hudW == 240, "Default Compact Tracker HUD width must be 240")
            assertTrue(hudH == 48, "Default Compact Tracker HUD height must be 48 at 1.0 text scale")

            -- Release Blocker #1: Parent-chain effective visibility of `moreBtn` (`...`) when `headerBar` is hidden
            assertTrue(
              Nav.frame.moreBtn ~= nil and getWidgetParent(Nav.frame.moreBtn) == Nav.frame,
              "moreBtn (...) must be parented directly to ForeverHubTrackerHUD, not headerBar"
            )
            assertTrue(
              isEffectivelyVisible(Nav.frame.moreBtn),
              "moreBtn (...) must remain effectively visible through its entire parent chain when headerBar is hidden"
            )
            assertTrue(
              Nav.frame.dockedArrowLane
                and Nav.frame.dockedArrowLane.distanceText
                and (Nav.frame.dockedArrowLane.distanceText:GetText() or "") == "",
              "Docked arrow lane distanceText must be empty so distance is never duplicated or truncated under the arrow"
            )
            assertTrue(
              Nav.frame.stepText:GetText() == "Hop 1: Arrive at Farholde Keep",
              "Line 1 must show clean active step title"
            )

            -- Transition 1: Active -> Paused -> Resumed -> Stopped (Release Blocker #2)
            ns.Domain.GoldFarms.Pause(gfProg)
            assertTrue(gfProg.mode == "paused" and gfProg.pausedHudRetained == true, "Pause must set pausedHudRetained = true")
            Nav.SyncFromGoldFarmEvaluation({ farm = mockFarm, stepIndex = 1, totalSteps = 4 }, gfProg)
            assertTrue(Nav.frame:IsShown() == true, "Paused session must remain visible in HUD so Resume is reachable")
            assertTrue(Nav.frame.subText:GetText() == "Paused", "Paused HUD Line 2 must display 'Paused'")
            ns.Domain.GoldFarms.Start("rg_brineshell_twilight", nil, gfProg, { status = "unavailable" })
            assertTrue(gfProg.mode == "standalone" and gfProg.pausedHudRetained == false, "Resume must clear pausedHudRetained")
            ns.Domain.GoldFarms.Stop(gfProg)
            assertTrue(gfProg.mode == "paused" and gfProg.pausedHudRetained == false, "Stop must set pausedHudRetained = false")
            Nav.SyncFromGoldFarmEvaluation({ farm = mockFarm, stepIndex = 1, totalSteps = 4 }, gfProg)
            assertTrue(Nav.frame:IsShown() == false, "Stopped session must hide the HUD")

            -- Restore active standalone session
            ns.Domain.GoldFarms.Start("rg_brineshell_twilight", nil, gfProg, { status = "unavailable" })

            -- Transition 2: ForeverHub -> RXP -> ForeverHub (with disabled step actions in RXP mode)
            local rxpBridge = ns.Bridges and ns.Bridges.RXPBridge
            local savedIsGfSelected = rxpBridge and rxpBridge.IsGoldFarmGuideSelected
            if rxpBridge then
              rxpBridge.IsGoldFarmGuideSelected = function()
                return true
              end
            end
            Nav.SyncFromGoldFarmEvaluation({ farm = mockFarm, stepIndex = 1, totalSteps = 4 }, gfProg)
            if rxpBridge then
              rxpBridge.IsGoldFarmGuideSelected = savedIsGfSelected
            end
            assertTrue(gfProg.mode == "rxp" and Nav.frame.subText:GetText() == "Controlled by RXP", "RXP mode Line 2 must show 'Controlled by RXP'")
            assertTrue(Nav.frame.nextBtn and Nav.frame.nextBtn.__disabled == true, "Next button must be disabled in RXP mode")
            assertTrue(Nav.frame.prevBtn and Nav.frame.prevBtn.__disabled == true, "Prev button must be disabled in RXP mode")
            assertTrue(Nav.frame.pauseToggleBtn and Nav.frame.pauseToggleBtn.__disabled == true, "Pause button must be disabled in RXP mode")
            gfProg.mode = "standalone"

            -- Transition 3: Context switch / farm switch closes overflowMenu
            if Nav.frame.overflowMenu and Nav.frame.overflowMenu.Show then
              Nav.frame.overflowMenu:Show()
            end
            Nav.RequestContextSwitch("gold_farm")
            gfProg.selectedFarmID = "feralas_nagash"
            Nav.SyncFromGoldFarmEvaluation({
              farm = { farmID = "feralas_nagash", shortLabel = "Feralas", title = "Feralas Naga", zoneName = "Feralas" },
              stepIndex = 1,
              totalSteps = 3,
              activeStep = {
                stepID = "step_1",
                kind = "grind_camp",
                title = "Southern Isle Cave",
                destination = { uiMapID = 1444, x01 = 0.28, y01 = 0.72, zoneName = "Feralas" },
              },
            }, gfProg)
            assertTrue(
              Nav.frame.overflowMenu == nil or Nav.frame.overflowMenu:IsShown() == false,
              "Context switch must close overflowMenu"
            )
            assertTrue(Nav.frame.stepText:GetText() == "Southern Isle Cave", "Gold Farm Line 1 must show step name")

            -- Transition 4: Target A -> Target B at identical distance invalidates composite Line 2 cache key
            local savedCompute = ns.Compat.ComputeNavigationVector
            ns.Compat.ComputeNavigationVector = function()
              return { status = "ok", yards = 125, isCrossZone = false, rotationRadians = 0, absTurnRadians = 0 }
            end
            local okVecTests, errVecTests = pcall(function()
              Nav.SyncFromGoldFarmEvaluation({
                farm = mockFarm,
                stepIndex = 1,
                totalSteps = 4,
                activeStep = {
                  stepID = "target_a",
                  kind = "travel",
                  title = "Target Alpha",
                  destination = { uiMapID = 2548, x01 = 0.20, y01 = 0.20, zoneName = "Riverglades" },
                },
              }, gfProg)
              local keyA = Nav.frame.__lastLine2CompositeKey
              assertTrue(Nav.frame.subText:GetText() == "125 yds", "Docked normal navigation Line 2 must show numeric distance")

              Nav.SyncFromGoldFarmEvaluation({
                farm = mockFarm,
                stepIndex = 2,
                totalSteps = 4,
                activeStep = {
                  stepID = "target_b",
                  kind = "travel",
                  title = "Target Beta",
                  destination = { uiMapID = 2548, x01 = 0.80, y01 = 0.80, zoneName = "Riverglades" },
                },
              }, gfProg)
              local keyB = Nav.frame.__lastLine2CompositeKey
              assertTrue(keyA ~= keyB, "Composite Line 2 cache key must change when switching from Target A to Target B at equal distance")

              -- Transition 5: Docked -> Undocked -> HUD Hidden
              arrowSettings.dockedInHud = false
              Nav.RefreshArrowSettings()
              local snapUndocked = Nav.GetLiveArrowSnapshot()
              assertTrue(
                snapUndocked.floatingVisible == true and snapUndocked.dockedVisible == false,
                "Undocked mode must show floating arrow and hide docked arrow lane"
              )
              assertTrue(
                Nav.frame.subText:GetText() ~= "125 yds",
                "When undocked, floating arrow is the sole distance display; HUD Line 2 must not duplicate numeric distance"
              )
              arrowSettings.dockedInHud = true
              Nav.RefreshArrowSettings()

              -- Transition 6: Valid vector -> Unavailable -> Recovered
              ns.Compat.ComputeNavigationVector = function()
                return { status = "unavailable" }
              end
              Nav.RefreshCompactHUDFromVector(Nav.activeTarget, { status = "unavailable" }, false)
              assertTrue(
                Nav.frame.subText:GetText() == "Position unavailable" or Nav.frame.subText:GetText() == "No position",
                "Unavailable vector must replace distance on Line 2 with Position unavailable / No position"
              )
              ns.Compat.ComputeNavigationVector = function()
                return { status = "ok", yards = 88, isCrossZone = false, rotationRadians = 0, absTurnRadians = 0 }
              end
              Nav.RefreshCompactHUDFromVector(Nav.activeTarget, { status = "ok", yards = 88, isCrossZone = false }, false)
              assertTrue(Nav.frame.subText:GetText() == "88 yds", "Recovered vector must restore numeric distance on Line 2")
            end)
            ns.Compat.ComputeNavigationVector = savedCompute
            if not okVecTests then
              error(errVecTests, 2)
            end

            -- Transition 7: Tick 20 Hz docked arrow lane OnUpdate callback & verify single-shot circuit breaker
            local dockedLane = Nav.frame.dockedArrowLane
            if dockedLane and dockedLane.arrowTex then
              local dockedUpdate = (dockedLane.__scripts and dockedLane.__scripts["OnUpdate"])
                or (type(dockedLane.GetScript) == "function" and dockedLane:GetScript("OnUpdate"))
              assertTrue(type(dockedUpdate) == "function", "Docked arrow lane must bind an OnUpdate handler")
              dockedLane.elapsedAccum = 0
              dockedUpdate(dockedLane, 0.10)
              assertTrue(Nav.activeTarget ~= nil and Nav.activeTarget.lastVecStatus ~= nil, "Docked arrow OnUpdate must evaluate vector cleanly")

              local savedComputeVec = ns.Compat.ComputeNavigationVector
              local savedLastErr = Nav.lastUpdateError
              local faultCalls = 0
              ns.Compat.ComputeNavigationVector = function()
                faultCalls = faultCalls + 1
                error("injected_nav_vector_fault")
              end
              local okLatch, errLatch = pcall(function()
                dockedLane.elapsedAccum = 0
                dockedUpdate(dockedLane, 0.10)
                assertTrue(faultCalls == 1, "Faulting OnUpdate must invoke body once before latching")
                assertTrue(Nav.updateCircuitLatches and Nav.updateCircuitLatches.docked ~= nil, "Circuit breaker must latch 'docked' loop")
                dockedLane.elapsedAccum = 0
                dockedUpdate(dockedLane, 0.10)
                assertTrue(faultCalls == 1, "Latched OnUpdate MUST NOT retry failing body on subsequent ticks")
                Nav.ResetUpdateCircuitLatches()
                assertTrue(Nav.updateCircuitLatches.docked == nil, "ResetUpdateCircuitLatches must clear latched state")
              end)
              ns.Compat.ComputeNavigationVector = savedComputeVec
              Nav.lastUpdateError = savedLastErr
              Nav.ResetUpdateCircuitLatches()
              if dockedLane.Show then
                dockedLane:Show()
              end
              if not okLatch then
                error(errLatch, 2)
              end
            end

            -- Verify locked HUD preserves mouse/overflow click while Hide tracker keeps navigation running
            arrowSettings.hudLocked = true
            fireButtonClick(Nav.frame.moreBtn)
            assertTrue(
              Nav.frame.overflowMenu and Nav.frame.overflowMenu:IsShown() == true,
              "Clicking moreBtn (...) while hudLocked = true must still open overflowMenu"
            )

            local hideBtn = Nav.frame.hideTrackerBtn
            if hideBtn then
              fireButtonClick(hideBtn)
              assertTrue(arrowSettings.hudHidden == true, "Hide tracker must mark hudHidden = true")
              assertTrue(gfProg.mode == "standalone" and Nav.activeTarget ~= nil, "Hide tracker MUST keep active navigation running")
              local snapHidden = Nav.GetLiveArrowSnapshot()
              assertTrue(
                not (snapHidden.dockedVisible and snapHidden.floatingVisible),
                "Hiding tracker must maintain docked/floating arrow mutual exclusion"
              )
            end
          end
        end)

        if Nav.TryReleaseOwnedResource then
          pcall(Nav.TryReleaseOwnedResource)
        end
        Nav.ClearArrowTarget()
        if Nav.frame and Nav.frame.Hide then
          Nav.frame:Hide()
        end
        if Nav.arrowFrame and Nav.arrowFrame.Hide then
          Nav.arrowFrame:Hide()
        end
        if navSnap.frame == nil and Nav.frame ~= nil and type(Nav.frame.__scripts) ~= "table" then
          navSnap.frame = Nav.frame
          navSnap.savedGlobalHUD = Nav.frame
        end
        if navSnap.arrowFrame == nil and Nav.arrowFrame ~= nil and type(Nav.arrowFrame.__scripts) ~= "table" then
          navSnap.arrowFrame = Nav.arrowFrame
          navSnap.savedGlobalArrow = Nav.arrowFrame
        end
        if navSnap.controllerFrame == nil and Nav.controllerFrame ~= nil and type(Nav.controllerFrame.__scripts) ~= "table" then
          navSnap.controllerFrame = Nav.controllerFrame
          navSnap.savedGlobalController = Nav.controllerFrame
        end
        Nav.frame = nil
        Nav.arrowFrame = nil
        Nav.controllerFrame = nil
        Nav.suppressHUDCreation = prevSuppress

        for k in pairs(arrowSettings) do
          arrowSettings[k] = nil
        end
        for k, v in pairs(savedArrowSettings) do
          arrowSettings[k] = v
        end
        for k in pairs(gfProg) do
          gfProg[k] = nil
        end
        for k, v in pairs(savedGfProg) do
          gfProg[k] = v
        end

        if not okNavTest then
          error(errNavTest, 2)
        end
      end
    end)

    -- UI-08: Surface E (RewardAdvisor) Dynamic Measured Height Formula & Zero 'unk' Copy
    check("UI-08. Surface E (RewardAdvisor): Sibling Frame Width 320, Exact Height Formula & Provisional/Tie Badges", function()
      local RA = ns.UI.RewardAdvisor
      if RA and type(_G.CreateFrame) == "function" then
        local savedCItem = _G.C_Item
        local savedRAActive = RA.active
        local savedRAQuestID = RA.activeQuestID
        local savedRAGen = RA.currentGeneration
        local savedRAEval = RA.lastEvaluation
        local savedRAShown = (RA.frame and type(RA.frame.IsShown) == "function" and RA.frame:IsShown()) or false

        local mockRewardItems = {
          [1001] = { name = "Powderfuse Repeater of the Eagle", sellPrice = 8450 },
          [1002] = { name = "Farholde Heavy Greaves of Stamina", sellPrice = 11200 },
          [1003] = { name = "Sunnyglade Mantle", sellPrice = 6300 },
          [1004] = { name = "Rog'mar Signet Ring", sellPrice = 4100 },
          [1005] = { name = "Marshwater Healing Draught", sellPrice = 800 },
          [1006] = { name = "Ceremonial Riverglades Tabard", sellPrice = 0 },
        }
        _G.C_Item = {
          GetItemInfo = function(idOrLink)
            local id = tonumber(tostring(idOrLink):match("(%d+)"))
            local row = mockRewardItems[id]
            if not row then
              if savedCItem and type(savedCItem.GetItemInfo) == "function" then
                return savedCItem.GetItemInfo(idOrLink)
              end
              return nil
            end
            return row.name, string.format("|Hitem:%d|h[%s]|h", id, row.name), 2, 40, 38, "Armor", "Mail", 1, "INVTYPE_FEET", 132541, row.sellPrice
          end,
          RequestLoadItemDataByID = function() end,
        }
        local okRA, errRA = pcall(function()
          local sixRewards = {
            status = "ok",
            questID = 95999,
            numChoices = 6,
            choices = {
              { choiceIndex = 1, itemID = 1001, itemLink = "|Hitem:1001|h[Powderfuse Repeater of the Eagle]|h", name = "Powderfuse Repeater of the Eagle", quantity = 1 },
              { choiceIndex = 2, itemID = 1002, itemLink = "|Hitem:1002|h[Farholde Heavy Greaves of Stamina]|h", name = "Farholde Heavy Greaves of Stamina", quantity = 1 },
              { choiceIndex = 3, itemID = 1003, itemLink = "|Hitem:1003|h[Sunnyglade Mantle]|h", name = "Sunnyglade Mantle", quantity = 1 },
              { choiceIndex = 4, itemID = 1004, itemLink = "|Hitem:1004|h[Rog'mar Signet Ring]|h", name = "Rog'mar Signet Ring", quantity = 1 },
              { choiceIndex = 5, itemID = 1005, itemLink = "|Hitem:1005|h[Marshwater Healing Draught]|h", name = "Marshwater Healing Draught", quantity = 3 },
              { choiceIndex = 6, itemID = 1006, itemLink = "|Hitem:1006|h[Ceremonial Riverglades Tabard]|h", name = "Ceremonial Riverglades Tabard", quantity = 1 },
            },
          }
          local eval = RA.OnQuestComplete(sixRewards)
          assertTrue(eval and eval.status == "complete", "6-reward evaluation must succeed with status='complete'")
          local f = RA.frame
          if f then
            local fw = (type(f.GetWidth) == "function" and f:GetWidth()) or f.__width
            local fh = (type(f.GetHeight) == "function" and f:GetHeight()) or f.__height
            assertTrue(fw == 320, "RewardAdvisor width must be 320")
            local sumRows = 0
            for _, rh in ipairs(f.activeRowHeights or {}) do
              assertTrue(rh >= 40, "Each reward row must be >= 40 high")
              sumRows = sumRows + rh
            end
            local expectedTotal = 24 + 22 + 8 + sumRows + 8 + (f.measuredFooterHeight or 16)
            assertTrue(fh == expectedTotal, string.format("RewardAdvisor height %d != formula %d", tonumber(fh) or -1, expectedTotal))
            assertTrue(f.rowPool[2].badgeText:GetText() == "BEST VENDOR", "Highest vendor reward must carry BEST VENDOR badge")
            assertTrue(f.rowPool[6].valueText:GetText() == "No vendor price", "Zero sellPrice reward must show 'No vendor price'")
          end
          RA.OnQuestFinished()

          -- Also verify stack quantities, ties, partial pricing & stale async callback rejection on RewardAdvisor
          local savedPrices = ns.State.overrideItemSellPrices
          local savedLoads = ns.State.requestedItemLoads
          local okStack, errStack = pcall(function()
            ns.State.requestedItemLoads = {}
            ns.State.overrideItemSellPrices = { [70001] = 1500, [70002] = 400, [70003] = "loading" }
            local snapPartial = {
              status = "ok",
              questID = 94879,
              questTitle = "Plaguelands Supplies",
              choices = {
                { choiceIndex = 1, itemID = 70001, name = "Heavy Mace", quantity = 1 },
                { choiceIndex = 2, itemID = 70002, name = "Mana Potion Bundle", quantity = 5 },
                { choiceIndex = 3, itemID = 70003, name = "Uncached Robe", quantity = 1 },
              },
            }
            local eval1, gen1 = RA.OnQuestComplete(snapPartial)
            assertTrue(eval1.status == "partial", "Uncached choice must produce partial status")
            assertTrue(eval1.bestVendorCopper == 2000 and eval1.bestChoices[1].choiceIndex == 2, "5x 400c (2000c) must beat 1x 1500c")
            assertTrue(ns.State.requestedItemLoads[70003] == 1, "Must request async item load for uncached item 70003")

            ns.State.overrideItemSellPrices = { [80001] = 1200, [80002] = 1200 }
            local snapTie = {
              status = "ok",
              questID = 94881,
              questTitle = "Timbermaw Tribute",
              choices = {
                { choiceIndex = 1, itemID = 80001, name = "Cloth Bracers", quantity = 1 },
                { choiceIndex = 2, itemID = 80002, name = "Plate Bracers", quantity = 1 },
              },
            }
            local evalTie, gen2 = RA.OnQuestComplete(snapTie)
            assertTrue(gen2 > gen1 and evalTie.status == "complete" and evalTie.isTie == true and #evalTie.bestChoices == 2, "Exact copper tie must report both choices")
            local handledStale, staleReason = RA.OnItemInfoReceived(70003, true, gen1, snapTie)
            assertTrue(handledStale == false and staleReason == "stale_generation_discarded", "Late callback from old generation must be discarded")
            RA.OnQuestFinished()
          end)
          ns.State.overrideItemSellPrices = savedPrices
          ns.State.requestedItemLoads = savedLoads
          if not okStack then
            error(errStack, 2)
          end
        end)
        _G.C_Item = savedCItem
        RA.active = savedRAActive
        RA.activeQuestID = savedRAQuestID
        RA.currentGeneration = savedRAGen
        RA.lastEvaluation = savedRAEval
        if RA.frame then
          if savedRAShown then
            RA.frame:Show()
          else
            RA.frame:Hide()
          end
        end
        if not okRA then
          error(errRA, 2)
        end
      end
    end)

    -- UI-09: Surface F (WorldMapPins & Tooltips) Hit Size >= 24, 28h Control Pill & Zero 'unk' Tooltips
    check("UI-09. Surface F (WorldMapPins & Tooltips): Pin Glyph Fallback, 28h Pill & Clean Tooltips", function()
      local WMP = ns.UI.WorldMapPins
      local Tooltips = ns.UI.Tooltips
      assertTrue(type(WMP) == "table" and type(Tooltips) == "table", "WorldMapPins and Tooltips must be loaded")

      -- Verify Tooltips emits 'Unreserved:' and NEVER 'unk' even on unpriced crate options!
      if _G.GameTooltip and type(_G.GameTooltip.ClearLines) == "function" then
        local anyCrateID = nil
        for cid in pairs((ns.Data and ns.Data.cratesByItemID) or {}) do
          anyCrateID = tonumber(cid)
          break
        end
        if anyCrateID then
          _G.GameTooltip.__lines = {}
          _G.GameTooltip.GetItem = function()
            return "Waylaid Crate", string.format("|Hitem:%d::::::::40:::::::|h[Waylaid Crate]|h", anyCrateID)
          end
          _G.GameTooltip.__fhLastRenderKey = nil
          Tooltips.OnTooltipSetItem(_G.GameTooltip)
          local joined = table.concat(_G.GameTooltip.__lines or {}, "\n")
          assertTrue(string.find(joined, "Unreserved:", 1, true) ~= nil, "Item tooltip must preserve 'Unreserved:'")
          assertTrue(string.find(joined, "unk", 1, true) == nil, "Item tooltip MUST NEVER emit 'unk': " .. joined)

          -- Regression guard for v0.8.1/v0.8.2 (Interface 16001): TooltipDataProcessor, post-hook deduplication, Shift context & secret values
          local savedGameTT = _G.GameTooltip
          local savedItemRefTT = _G.ItemRefTooltip
          local savedTDP = _G.TooltipDataProcessor
          local savedEnum = _G.Enum
          local savedHookSecure = _G.hooksecurefunc
          local savedIsSecret = _G.issecretvalue
          local savedHookedFlag = Tooltips._dataProcessorHooked
          local registeredPostCall = nil

          local modernLines = {}
          local bagCalls = {}
          local hyperlinkCalls = {}
          local isForbiddenState = false
          local SECRET_SENTINEL = { __secret = true }

          local modernTT = nil
          local postHooks = {}
          modernTT = {
            __lines = modernLines,
            IsForbidden = function()
              return isForbiddenState
            end,
            IsShown = function()
              return true
            end,
            NumLines = function()
              return #modernLines
            end,
            HasScript = function(_, scriptName)
              return scriptName == "OnHide"
            end,
            HookScript = function(_, scriptName, fn)
              if scriptName ~= "OnHide" then
                error("bad argument #2 to '?' (Usage: local success = self:HookScript(scriptTypeName, script [, bindingType]))")
              end
              assertTrue(type(fn) == "function", "OnHide hook must pass a function")
              return true
            end,
            ClearLines = function(self)
              modernLines = {}
              self.__lines = modernLines
              if postHooks.ClearLines then
                postHooks.ClearLines(self)
              end
            end,
            SetBagItem = function(self, b, s)
              table.insert(bagCalls, { bag = b, slot = s })
              modernLines = { "Native Bag Line" }
              self.__lines = modernLines
              if registeredPostCall then
                registeredPostCall(self, { id = anyCrateID })
              end
              if postHooks.SetBagItem then
                postHooks.SetBagItem(self, b, s)
              end
            end,
            SetHyperlink = function(self, link)
              table.insert(hyperlinkCalls, link)
              modernLines = { "Native Link Line" }
              self.__lines = modernLines
              if registeredPostCall then
                registeredPostCall(self, { id = anyCrateID })
              end
              if postHooks.SetHyperlink then
                postHooks.SetHyperlink(self, link)
              end
            end,
            AddLine = function(_, text)
              table.insert(modernLines, tostring(text or ""))
            end,
            AddDoubleLine = function(_, l, r)
              table.insert(modernLines, tostring(l or "") .. " " .. tostring(r or ""))
            end,
            Show = function() end,
          }
          _G.hooksecurefunc = function(tbl, method, fn)
            if tbl == modernTT then
              postHooks[method] = fn
            end
          end
          _G.issecretvalue = function(v)
            return v == SECRET_SENTINEL
          end
          _G.GameTooltip = modernTT
          _G.ItemRefTooltip = nil
          _G.Enum = { TooltipDataType = { Item = 0 } }
          _G.TooltipDataProcessor = {
            AddTooltipPostCall = function(dataType, cb)
              if dataType == 0 then
                registeredPostCall = cb
              end
            end,
          }
          Tooltips._dataProcessorHooked = false
          local okModern, errModern = pcall(function()
            Tooltips.Init()
            assertTrue(type(registeredPostCall) == "function", "Tooltips.Init must register TooltipDataProcessor on 16001")

            -- 1) Astra P1 #2: SetBagItem fires TooltipDataProcessor inside accessor, then post-hook runs; repeated callback w/ same data MUST NOT duplicate lines!
            local sharedBagData = { id = anyCrateID }
            modernLines = { "Native Bag Line" }
            modernTT.__lines = modernLines
            registeredPostCall(modernTT, sharedBagData)
            if postHooks.SetBagItem then
              postHooks.SetBagItem(modernTT, 0, 1)
            end
            local countAfterFirst = #modernLines
            assertTrue(countAfterFirst > 1, "16001 TooltipDataProcessor must append ForeverHub lines via data.id")
            registeredPostCall(modernTT, sharedBagData)
            assertTrue(#modernLines == countAfterFirst, "Repeated callback after SetBagItem post-hook MUST NOT duplicate lines")

            -- 2) Astra P1 #1: Shift refresh on bag tooltip refreshes bag slot 0:1, NOT SetHyperlink
            bagCalls = {}
            hyperlinkCalls = {}
            Tooltips.RefreshActiveTooltips()
            assertTrue(#bagCalls == 1 and bagCalls[1].bag == 0 and bagCalls[1].slot == 1, "Shift refresh on bag tooltip must call SetBagItem(0, 1)")
            assertTrue(#hyperlinkCalls == 0, "Shift refresh on bag tooltip must not call SetHyperlink")

            -- 3) Astra P1 #1: Subsequent Merchant/Quest tooltip without Hide/Clear MUST clear stale bag context and NOT call SetBagItem or SetHyperlink on Shift!
            modernLines = { "Native Merchant Line" }
            modernTT.__lines = modernLines
            registeredPostCall(modernTT, { id = anyCrateID })
            assertTrue(#modernLines > 1, "Merchant crate tooltip must still append ForeverHub lines")
            bagCalls = {}
            hyperlinkCalls = {}
            Tooltips.RefreshActiveTooltips()
            assertTrue(#bagCalls == 0, "Shift on Merchant/contextual tooltip MUST NOT restore stale bag slot 0:1")
            assertTrue(#hyperlinkCalls == 0, "Shift on Merchant/contextual tooltip MUST NOT clobber tooltip with generic SetHyperlink")

            -- 4) Astra P1 #3: Secret values and forbidden tooltips are rejected safely without mutation or error
            assertTrue(ns.Compat.ExtractItemID(SECRET_SENTINEL) == nil, "ExtractItemID must reject secret values")
            modernLines = { "Base" }
            modernTT.__lines = modernLines
            registeredPostCall(modernTT, { id = SECRET_SENTINEL })
            assertTrue(#modernLines == 1, "Secret data.id must not append lines")
            isForbiddenState = true
            registeredPostCall(modernTT, { id = anyCrateID })
            assertTrue(#modernLines == 1, "Forbidden tooltip must not be mutated")
            isForbiddenState = false
          end)
          _G.GameTooltip = savedGameTT
          _G.ItemRefTooltip = savedItemRefTT
          _G.TooltipDataProcessor = savedTDP
          _G.Enum = savedEnum
          _G.hooksecurefunc = savedHookSecure
          _G.issecretvalue = savedIsSecret
          Tooltips._dataProcessorHooked = savedHookedFlag
          if not okModern then
            error(errModern, 2)
          end
        end
      end
    end)
  end)

  restoreNavigationSnapshot(navSnap, charDB)
  db.uiWorkspace = savedUIWorkspace
  db.settings = savedSettings
  charDB.reservations = savedReservations
  charDB.nextPriority = savedNextPriority
  charDB.goldFarmProgress = savedGFProg
  charDB.userConfirmedCompletedQuestTitles = savedUserConfirmedTitles
  ns.State.lastSuggestionSnapshot = savedLastUndo
  ns.State.lastUndoReason = savedUndoReason
  if ns.UI and ns.UI.Theme then
    ns.UI.Theme.appliedFontScale = nil
  end
  if ns.UI and ns.UI.Crates and savedDraft then
    ns.UI.Crates.draftState = savedDraft
    ns.UI.Crates.pendingClearConfirm = false
    ns.UI.Crates.pendingSuggestionPreview = nil
  end
  if ns.UI and ns.UI.Workspace then
    if wasShown then
      ns.UI.Workspace.Refresh()
    else
      ns.UI.Workspace.Hide()
    end
  end

  local report = {
    passed = passed,
    failed = failed,
    total = passed + failed,
    results = results,
  }
  if suiteOk then
    SelfTest.cachedReports.workspace_ui = report
  end
  SelfTest._running.workspace_ui = false

  if not suiteOk then
    error(suiteErr, 2)
  end

  return report
end

function SelfTest.RunPhase0MarketSuite()
  if SelfTest._running.phase0_market then
    error("Recursive SelfTest.RunPhase0MarketSuite invocation forbidden", 2)
  end
  SelfTest._running.phase0_market = true
  SelfTest.suiteRunCounts.phase0_market = (SelfTest.suiteRunCounts.phase0_market or 0) + 1

  local results = {}
  local passed = 0
  local failed = 0

  local function check(name, fn)
    local ok, err = pcall(fn)
    if ok then
      passed = passed + 1
      table.insert(results, { name = name, passed = true })
    else
      failed = failed + 1
      table.insert(results, { name = name, passed = false, error = tostring(err) })
    end
  end

  local db = _G.ForeverHubDB or {}
  local savedSibling = _G.ForeverHub_MarketData
  local savedExport = deepCopyTable(db.marketExport)
  local savedIsSecret = _G.issecretvalue
  local savedGetRealm = _G.GetRealmName

  local suiteOk, suiteErr = pcall(function()
    local MI = ns.Domain and ns.Domain.MarketIdentity
    local MA = ns.Domain and ns.Domain.MarketAccounting
    assertTrue(type(MI) == "table", "MarketIdentity module must load")
    assertTrue(type(MA) == "table", "MarketAccounting module must load")

    check("Phase0.1: MarketKey isolates realms and auction pools without merging unverified connected realms", function()
      local mkAlliance = MI.BuildMarketKey({
        product = "wowf",
        ruleset = "wow_forever",
        region = "US",
        realmName = "Evergreen",
        connectedRealmRoot = "Cluster-A",
        connectedRealmVerified = false,
        auctionPoolID = "alliance",
        layerID = 4,
      })
      local mkHorde = MI.BuildMarketKey({
        product = "wowf",
        ruleset = "wow_forever",
        region = "US",
        realmName = "Evergreen",
        auctionPoolID = "horde",
      })
      local mkNeutral = MI.BuildMarketKey({
        product = "wowf",
        ruleset = "wow_forever",
        region = "US",
        realmName = "Evergreen",
        auctionPoolID = "neutral",
      })
      local mkConnected = MI.BuildMarketKey({
        product = "wowf",
        ruleset = "wow_forever",
        region = "US",
        realmName = "Evergreen",
        connectedRealmRoot = "Cluster A",
        connectedRealmVerified = true,
        auctionPoolID = "alliance",
      })
      assertTrue(mkAlliance == "m1:wowf:wow_forever:us:r:evergreen:alliance", "Unexpected Alliance marketKey: " .. tostring(mkAlliance))
      assertTrue(mkHorde == "m1:wowf:wow_forever:us:r:evergreen:horde", "Unexpected Horde marketKey")
      assertTrue(mkNeutral == "m1:wowf:wow_forever:us:r:evergreen:neutral", "Unexpected Neutral marketKey")
      assertTrue(mkAlliance ~= mkHorde and mkAlliance ~= mkNeutral, "Faction and neutral pools must remain distinct")
      assertTrue(mkConnected == "m1:wowf:wow_forever:us:cr:cluster-a:alliance", "Verified connected realm uses cr prefix")
    end)

    check("Phase0.2: ItemKey separates fungible base, random-suffix variants, unknown_variant, recipes, and services", function()
      local base = MI.ClassifyItemIdentity({
        itemID = 2770,
        verifiedBaseSet = { [2770] = true },
      })
      assertTrue(base and base.itemKey == "i1:base:2770" and base.tradeSafe == true, "Copper Ore must classify as verified_base_item")

      -- Positive suffix with two different instance GUIDs in field 8 must collapse to same variant key
      local varA = MI.ClassifyItemIdentity({
        itemLink = "|cff1eff00|Hitem:9811:0:0:0:0:0:1204:99887766:25|h[Bandit Jerkin of the Bear]|h|r",
        isVariantCapable = true,
      })
      local varB = MI.ClassifyItemIdentity({
        itemLink = "|cff1eff00|Hitem:9811:0:0:0:0:0:1204:11223344:60|h[Bandit Jerkin of the Bear]|h|r",
        isVariantCapable = true,
      })
      assertTrue(varA and varB and varA.itemKey == varB.itemKey, "Instance uniqueID and linkLevel must be stripped for positive suffix")
      assertTrue(varA.itemKey == "i1:var:9811:s=1204:f=0:e=0:c=0", "Unexpected positive-suffix variant key: " .. tostring(varA.itemKey))

      -- Negative suffix preserves 16-bit scaling factor
      local varNeg = MI.ClassifyItemIdentity({
        itemLink = "item:15212:0:0:0:0:0:-18:65560:60",
        isVariantCapable = true,
      })
      assertTrue(varNeg and varNeg.itemKey == "i1:var:15212:s=-18:f=24:e=0:c=0", "Negative suffix must retain low-16-bit factor")

      -- Variant-capable item observed by itemID ONLY must fail closed as `unknown_variant` (`tradeSafe = false`)
      local unk = MI.ClassifyItemIdentity({
        itemID = 9811,
        isVariantCapable = true,
      })
      assertTrue(unk and unk.classification == "unknown_variant" and unk.itemKey == "i1:unk_var:9811", "Missing link on gear must be unknown_variant")
      assertTrue(unk.tradeSafe == false, "unknown_variant MUST NOT be tradeSafe")

      -- Recipe item vs service
      local rec = MI.ClassifyItemIdentity({ kind = "recipe", itemID = 16221 })
      local svc = MI.ClassifyItemIdentity({ kind = "service", professionSlug = "Enchanting", spellID = 20025 })
      assertTrue(rec and rec.itemKey == "i1:recipe:16221", "Recipe itemKey mismatch")
      assertTrue(svc and svc.itemKey == "i1:service:enchanting:20025", "Service itemKey mismatch")
    end)

    check("Phase0.3: Secret/restricted values are guarded BEFORE comparisons, arithmetic, or indexing", function()
      local SECRET = setmetatable({}, {
        __eq = function()
          error("Forbidden __eq on secret value!")
        end,
        __lt = function()
          error("Forbidden __lt on secret value!")
        end,
        __tostring = function()
          error("Forbidden __tostring on secret value!")
        end,
      })
      _G.issecretvalue = function(v)
        return rawget({ [SECRET] = true }, v) == true
      end
      assertTrue(MI.SlugifyToken(SECRET) == nil, "SlugifyToken must reject secret value safely")
      assertTrue(MI.ParseItemHyperlink(SECRET) == nil, "ParseItemHyperlink must reject secret value safely")
      assertTrue(MI.ClassifyItemIdentity({ itemID = SECRET }) == nil, "ClassifyItemIdentity must reject secret itemID")
      assertTrue(MA.ComputeCommissionCopper(SECRET, 500) == nil, "ComputeCommissionCopper must reject secret copper")
      _G.issecretvalue = savedIsSecret
    end)

    check("Phase0.4: Overflow-safe half-up copper commission and whole-stack ask ladder execution", function()
      assertTrue(MA.ComputeCommissionCopper(9, 500) == 0, "9c * 5% = 0.45c -> 0c")
      assertTrue(MA.ComputeCommissionCopper(10, 500) == 1, "10c * 5% = 0.50c -> 1c half-up")
      assertTrue(MA.ComputeCommissionCopper(10000, 500) == 500, "1g * 5% -> 5s")
      assertTrue(MA.ComputeCommissionCopper(10000, 1500) == 1500, "1g * 15% neutral -> 15s")
      local hugeComm = MA.ComputeCommissionCopper(500000000010, 500)
      assertTrue(hugeComm == 25000000001, "Large copper commission must stay exact without 53-bit overflow")

      local rungs = {
        { stackSize = 20, stackBuyoutCopper = 2000, numStacks = 2 }, -- 100c/u, 2000c per full stack
        { stackSize = 5, stackBuyoutCopper = 700, numStacks = 1 },   -- 140c/u, 700c for 5
      }
      local whole = MA.WalkAskLadderEntryCost(rungs, 5, false)
      assertTrue(whole and whole.sufficientDepth == true, "Depth sufficient")
      -- Buying the 5-stack @ 700c beats over-buying a 20-stack @ 2000c when only 5 units are needed!
      assertTrue(whole.entryCostCopper == 700 and whole.acquiredUnits == 5, "Whole-stack optimizer should pick 700c 5-stack over 2000c 20-stack")

      local partial = MA.WalkAskLadderEntryCost(rungs, 5, true)
      assertTrue(partial and partial.entryCostCopper == 500 and partial.acquiredUnits == 5, "Commodity partial stack buys 5 units @ 100c = 500c")

      local deep = MA.WalkAskLadderEntryCost(rungs, 50, false)
      assertTrue(deep and deep.sufficientDepth == false and deep.status == "insufficient_depth", "Must flag insufficient_depth above 45 units")
    end)

    check("Phase0.5: Liquidation policy R_pi(q,H) and 1-copper sale/expired mail reconciliation", function()
      local liq = MA.EvaluateLiquidationPolicy({
        quantity = 10,
        vendorable = true,
        vendorUnitCopper = 200, -- vendor_now = 2000c
        saleUnitPriceCopper = 500,
        saleProbabilityBps = 8000, -- 80% sell at (5000 - 250 = 4750) -> 3800c + 20% vendor fallback (400c) = 4200c
        cutBps = 500,
        depositPerAttemptCopper = 120,
        expectedFailedAttemptsBps = 2500, -- 0.25 * 120 = 30c
        expectedCancelFeeCopper = 0,
        liquidationOpsCopper = 20,
      })
      assertTrue(liq and liq.status == "ok" and liq.bestPolicy == "ah_horizon", "AH horizon should beat vendor_now")
      assertTrue(liq.totalRealizableCopper == 4150, "Expected 3800 + 400 - 30 - 20 = 4150c, got " .. tostring(liq.totalRealizableCopper))

      local sale, errSale = MA.ReconcileMailOutcome({
        outcomeType = "SALE_INVOICE",
        grossSaleCopper = 10000,
        commissionCopper = 500,
        depositRefundedCopper = 300,
        cashReceivedCopper = 9800,
        entryCostCopper = 7000,
        priorFailedDepositsCopper = 300,
        expectedCutBps = 500,
      })
      assertTrue(sale and errSale == nil, "Sale reconciliation must succeed")
      assertTrue(sale.reconciledExact == true and sale.discrepancyCopper == 0, "Cash received 9800 must match 10000 - 500 + 300")
      assertTrue(sale.principalReturnedCopper == 300, "Deposit refund is returned principal")
      assertTrue(sale.economicProfitCopper == 2200, "Economic profit = (10000 - 500) - 7000 - 300 = 2200c (deposit refund excluded!)")

      local exp = MA.ReconcileMailOutcome({
        outcomeType = "EXPIRED_RETURN",
        depositPostedCopper = 300,
      })
      assertTrue(exp and exp.depositLostCopper == 300 and exp.realizedAttemptFeeDeltaCopper == -300, "Expired listing loses deposit")
    end)

    check("Phase0.6: Four-timestamp preservation and ForeverHub_MarketData sibling status checks", function()
      _G.GetRealmName = function()
        return "Evergreen"
      end
      db.marketExport = nil
      MA.EnsureMarketExportInitialized()
      local obs, errObs = MA.RecordMaterialObservation({
        marketKey = "m1:wowf:wow_forever:us:r:evergreen:alliance",
        itemID = 2770,
        verifiedBaseSet = { [2770] = true },
        observedAt = nil,
        ageDaysCoarse = 1,
        unitPriceCopper = 185,
      })
      assertTrue(obs and errObs == nil, "RecordMaterialObservation must succeed")
      assertTrue(obs.observedAt == nil and obs.ageDaysCoarse == 1, "Unknown scan epoch MUST stay nil, never substituted with current time")

      _G.ForeverHub_MarketData = nil
      local stMissing = MA.GetSiblingMarketDataStatus(1700000500, "m1:wowf:wow_forever:us:r:evergreen:alliance")
      assertTrue(stMissing.status == "missing", "Expected missing when sibling absent")

      _G.ForeverHub_MarketData = {
        schemaVersion = 1,
        artifactType = "market-projection-v1",
        contentRevision = 7,
        marketKey = "m1:wowf:wow_forever:us:r:evergreen:alliance",
        publishedAtEpoch = 1700000100,
        validUntilEpoch = 1700003700,
        evidenceBasis = "OPERATOR_CONTROLLED",
        items = {
          ["i1:base:2770"] = {
            unitPriceCopper = 185,
            observedAtEpoch = 1700000050,
            confidence = "SUMMARY_ONLY",
          },
        },
      }
      local stActive = MA.GetSiblingMarketDataStatus(1700000500, "m1:wowf:wow_forever:us:r:evergreen:alliance")
      assertTrue(stActive.status == "active" and stActive.contentRevision == 7, "Expected active revision 7")
      assertTrue(stActive.newestObservationAgeSec == 450 and stActive.expiresInSec == 3200, "Age and expiry math must match")

      local stExpired = MA.GetSiblingMarketDataStatus(1700003700, "m1:wowf:wow_forever:us:r:evergreen:alliance")
      assertTrue(stExpired.status == "expired", "Expected expired at validUntilEpoch")

      local stWrong = MA.GetSiblingMarketDataStatus(1700000500, "m1:wowf:wow_forever:us:r:evergreen:horde")
      assertTrue(stWrong.status == "wrong_market", "Expected wrong_market across Alliance/Horde boundary")
    end)

    check("Phase0.7: Exact DP stack selection, 53-bit cross-product safety, per-lot fee rounding, zero-vendor ratio & writ quantity gates", function()
      -- 1. Astra reproduced indivisible stack counterexample: 2x6@10c (20c) vs 2x5@9c (18c) for targetQty=10
      local dpRungs = {
        { stackSize = 6, stackBuyoutCopper = 10, numStacks = 2 },
        { stackSize = 5, stackBuyoutCopper = 9, numStacks = 2 },
      }
      local dpRes, dpErr = MA.WalkAskLadderEntryCost(dpRungs, 10, false, { vendorable = true, vendorUnitCopper = 1 })
      assertTrue(dpRes and dpErr == nil, "Bounded DP stack selection must succeed")
      assertTrue(dpRes.selectionMode == "exact_min_outlay_dp", "Expected exact_min_outlay_dp mode")
      assertTrue(dpRes.entryCostCopper == 18 and dpRes.acquiredUnits == 10 and dpRes.excessUnits == 0, "Must select 2x5@9c = 18c instead of greedy 2x6@10c = 20c")
      assertTrue(dpRes.excessVendorSalvageCopper == 0, "0 excess units -> 0 salvage")

      -- 2. Astra reproduced 50-bit * 10,000 cross-product precision (`9,997,000,200,000,009,998` vs `...999`)
      local cmpNearLimit = MA.CompareUnitPricesExact(999900000000001, 9999, 999800000000001, 9998)
      assertTrue(cmpNearLimit == -1, "Exact quotient-remainder comparator must distinguish cross-products differing by 1 above 2^53")

      -- 3. Per-lot vs single-batch commission rounding + half_up vs floor invoice inference
      local comm10LotsHalfUp = MA.ComputeLotBatchCommissionCopper(10, 10, 500, "half_up")
      local comm10LotsFloor = MA.ComputeLotBatchCommissionCopper(10, 10, 500, "floor")
      local commSingleLot = MA.ComputeLotBatchCommissionCopper(100, 1, 500, "half_up")
      assertTrue(comm10LotsHalfUp == 10 and comm10LotsFloor == 0 and commSingleLot == 5, "Per-lot rounding must preserve 10x1c vs 10x0c vs 1x5c")

      local ruleHalfUp = MA.InferInvoiceCommissionRule(10, 1, 500)
      local ruleFloor = MA.InferInvoiceCommissionRule(10, 0, 500)
      assertTrue(ruleHalfUp and ruleHalfUp.status == "half_up", "10c -> 1c at 5% must infer half_up")
      assertTrue(ruleFloor and ruleFloor.status == "floor", "10c -> 0c at 5% must infer floor")

      -- 4. Zero-vendor items return nil vendorFloorRatioBps (never 0 or math.huge)
      local ratioZero, ratioErr = MA.ComputeVendorFloorRatioBps(500, true, 0)
      local ratioNonVend = MA.ComputeVendorFloorRatioBps(500, false, 100)
      local ratioValid = MA.ComputeVendorFloorRatioBps(250, true, 100)
      assertTrue(ratioZero == nil and ratioErr == "vendor_floor_unavailable", "Zero-vendor item must return nil ratio")
      assertTrue(ratioNonVend == nil, "Non-vendorable item must return nil ratio")
      assertTrue(ratioValid == 25000, "250c / 100c = 25000 bps (2.5x)")

      -- 5. Unverified Writ quantities (`quantityVerified = false`) MUST be blocked from economic eligibility
      for _, writ in pairs((ns.Data and ns.Data.writsByItemID) or {}) do
        if writ.quantityVerified ~= true then
          local elig = MA.EvaluateWritEconomicEligibility(writ)
          assertTrue(elig and elig.eligible == false and elig.requiredQuantity == nil and elig.quantityStatus == "UNKNOWN", "Unverified writ must return UNKNOWN/ineligible")
          break
        end
      end
    end)

    check("Phase0.8: Stage 1 FeeRuleRecord build-staleness & native legacy AH buyout > 0 enforcement", function()
      local verifiedFee = {
        ruleId = "fee:m1:wowf:wow_forever:us:r:evergreen:alliance:build-70938",
        marketKey = "m1:wowf:wow_forever:us:r:evergreen:alliance",
        observedBuild = "70938",
        durationSchedule = { [2] = 1500, [8] = 6000, [24] = 18000 },
        minDepositCopper = 100,
        proportionalBasis = "vendor_stack_value",
        stackSemantics = "per_stack_with_min_floor",
        commissionBps = 500,
        roundingMode = "floor",
        supportingCaptureIds = { "dep:1", "mail:2" },
        verificationStatus = "VERIFIED",
      }
      local sameBuild = MA.EvaluateFeeRuleForBuild(verifiedFee, "70938")
      assertTrue(sameBuild and sameBuild.effectiveStatus == "VERIFIED" and sameBuild.microSpreadEligible == true, "Same-build verified FeeRuleRecord must be eligible")

      local depQuote, depErr = MA.QuoteExpectedDepositCopper(verifiedFee, {
        currentBuild = "70938",
        vendorUnitCopper = 0,
        stackSize = 20,
        numStacks = 3,
        durationHours = 24,
      })
      assertTrue(depQuote == 300 and depErr == nil, "3 stacks of zero-vendor item at 100c min floor must quote 300c")

      local staleBuild = MA.EvaluateFeeRuleForBuild(verifiedFee, "71005")
      assertTrue(staleBuild and staleBuild.effectiveStatus == "STALE_BUILD" and staleBuild.microSpreadEligible == false, "New client build without fresh captures MUST downgrade to STALE_BUILD")
      local staleQuote, staleErr = MA.QuoteExpectedDepositCopper(verifiedFee, {
        currentBuild = "71005",
        vendorUnitCopper = 0,
        stackSize = 20,
        numStacks = 1,
        durationHours = 24,
      })
      assertTrue(staleQuote == nil and staleErr == "stale_build_fee_rule", "Stale build FeeRuleRecord must refuse deposit quotes")

      -- Native Legacy AH page capture MUST reject `buyout == 0` bid-only auctions!
      local savedNumFn, savedInfoFn, savedLinkFn = _G.GetNumAuctionItems, _G.GetAuctionItemInfo, _G.GetAuctionItemLink
      _G.GetNumAuctionItems = function(kind)
        if kind == "list" then
          return 4, 4
        end
        return 0, 0
      end
      _G.GetAuctionItemInfo = function(_, idx)
        if idx == 1 then
          -- Bid-only listing (`buyoutPrice = 0`): MUST be skipped!
          return "Copper Ore", 0, 20, 1, false, 1, "", 500, 50, 0, 0, nil, 0, "SellerA", nil, 0, 2770
        elseif idx == 2 then
          -- Valid buyout listing (`20 @ 1800c`):
          return "Copper Ore", 0, 20, 1, false, 1, "", 1500, 50, 1800, 0, nil, 0, "SellerB", nil, 0, 2770
        elseif idx == 3 then
          -- Second valid buyout listing (`5 @ 500c`):
          return "Copper Ore", 0, 5, 1, false, 1, "", 400, 50, 500, 0, nil, 0, "SellerC", nil, 0, 2770
        else
          -- Ambiguous unverified equippable item without hyperlink: MUST be skipped!
          return "Mystery Sword", 0, 1, 2, false, 1, "", 1000, 50, 2000, 0, nil, 0, "SellerD", nil, 0, 999999
        end
      end
      _G.GetAuctionItemLink = function(_, idx)
        if idx == 1 or idx == 2 or idx == 3 then
          return "|cff1eff00|Hitem:2770:0:0:0:0:0:0:0:60|h[Copper Ore]|h|r"
        end
        return nil
      end
      local pageRes, pageErr = MA.InspectLegacyAuctionPageBuyouts({ verifiedBaseSet = { [2770] = true } })
      _G.GetNumAuctionItems, _G.GetAuctionItemInfo, _G.GetAuctionItemLink = savedNumFn, savedInfoFn, savedLinkFn
      assertTrue(pageRes and pageErr == nil, "InspectLegacyAuctionPageBuyouts must succeed")
      assertTrue(pageRes.skippedBidOnlyCount == 1, "Bid-only buyout==0 listing must be skipped into skippedBidOnlyCount")
      assertTrue(pageRes.skippedAmbiguousCount == 1, "Ambiguous linkless listing must be skipped into skippedAmbiguousCount")
      assertTrue(pageRes.eligibleListingCount == 2 and #pageRes.items == 1, "Only the 2 positive-buyout trade-safe listings must qualify")
      assertTrue(pageRes.items[1].minUnitPriceCopper == 90 and #pageRes.items[1].ladderRungs == 2, "Min unit buyout must be 1800/20 = 90c with 2 sorted rungs")
    end)

    check("Phase0.9: Astra Profession & Market Advisor P0-P2 Invariants (Wand/Oil Vendor Authority, Right-Censored Cohort Median, RecipeRegistry, DisenchantEv & 4-Way Decision Rule)", function()
      local PA = ns.Domain and ns.Domain.ProfessionAdvisor
      local CS = ns.Domain and ns.Domain.ConversionSpreads
      local RR = ns.Domain and ns.Domain.RecipeRegistry
      local DE = ns.Domain and ns.Domain.DisenchantEv
      assertTrue(type(PA) == "table" and type(CS) == "table" and type(RR) == "table" and type(DE) == "table", "Profession/Market P0-P2 modules must load")

      -- 1) Wand & Wizard Oil vendor prices resolved from EconomyData via VendorArbitrage:
      local enchCat = PA.PartitionEnchantingCatalog(200, { includeWizardOils = true, allowStaticWhenClientUnavailable = true })
      local byItem = {}
      for _, row in ipairs(enchCat.physicalItems or {}) do
        byItem[row.outputItemID] = row.vendorSellCopper
      end
      assertTrue(byItem[11287] == 110 and byItem[11288] == 1 and byItem[11289] == 1 and byItem[11290] == 1 and byItem[20744] == 100, "Wand/oil vendor prices must match Forever Bluepost #4/#5")

      -- 2) Right-censored sold-only median (5 sales at 1,2,3,4,100h + 5 unsold claiming 3h median) MUST be rejected:
      local badTurn = CS.ResolveTurnaroundHorizon({
        saleThroughVerified = true,
        cohortComplete = true,
        observedSaleCount = 5,
        unsoldOrCancelledCount = 5,
        totalCohortListings = 10,
        saleTimesHours = { 1, 2, 3, 4, 100 },
        medianHoursToSell = 3.0,
        observedAtEpoch = 1700000000,
      }, { nowEpoch = 1700000100 })
      assertTrue(badTurn.saleThroughVerified == false and badTurn.liquidationTime == "UNKNOWN", "Sold-only 3h median with 5 unsold listings must be rejected")

      -- 3) DisenchantEv enforces PROTECTED_ITEM, UNVERIFIED_ELIGIBILITY, UNKNOWN_DE_TABLE, and 1.00x/1.05x/1.10x scenarios:
      local protRes = DE.EvaluateItemDisenchant({ itemID = 1001, isReserved = true })
      assertTrue(protRes.status == "PROTECTED_ITEM", "Reserved item must return PROTECTED_ITEM")
      local deRes = DE.EvaluateItemDisenchant({
        itemID = 4004,
        quality = 2,
        itemLevel = 53,
        slotFamily = "ARMOR",
        vendorSellCopper = 12000,
        disenchantEligibilityVerified = true,
      }, {
        materialPricesByItemID = { [16202] = 18000, [16204] = 8000, [14343] = 25000 },
        liquidationVerified = true,
      })
      assertTrue(deRes.eligible == true and deRes.status == "DE_FAVORED" and #deRes.scenarios == 3, "Verified DE evaluation must produce 3 scenarios (1.00x/1.05x/1.10x)")

      -- 4) Conditional 4-way Decision Rule rejects unconditional defaults:
      local holdRule = PA.EvaluateSecondSlotDecisionRule({})
      assertTrue(holdRule.decisionCode == "PRESERVE_SLOT_COLLECT_EVIDENCE" and holdRule.unconditionalDefaultRejected == true, "Unmeasured state must default to PRESERVE_SLOT_COLLECT_EVIDENCE")
    end)
  end)

  _G.ForeverHub_MarketData = savedSibling
  db.marketExport = savedExport
  _G.issecretvalue = savedIsSecret
  _G.GetRealmName = savedGetRealm

  local report = {
    passed = passed,
    failed = failed,
    total = passed + failed,
    results = results,
  }
  if suiteOk then
    SelfTest.cachedReports.phase0_market = report
  end
  SelfTest._running.phase0_market = false

  if not suiteOk then
    error(suiteErr, 2)
  end

  return report
end

function SelfTest.RunSpawnRadarSuite()
  if SelfTest._running.spawn_radar then
    error("Recursive SelfTest.RunSpawnRadarSuite invocation forbidden", 2)
  end
  SelfTest._running.spawn_radar = true
  SelfTest.suiteRunCounts.spawn_radar = (SelfTest.suiteRunCounts.spawn_radar or 0) + 1

  local results = {}
  local passed = 0
  local failed = 0

  local function check(name, fn)
    local ok, err = pcall(fn)
    if ok then
      passed = passed + 1
      table.insert(results, { name = name, passed = true })
    else
      failed = failed + 1
      table.insert(results, { name = name, passed = false, error = tostring(err) })
    end
  end

  local SR = ns.Domain and ns.Domain.SpawnRadar
  local GF = ns.Domain and ns.Domain.GoldFarms
  local Compat = ns.Compat
  local db = ns.State and ns.State.GetDB and ns.State.GetDB() or _G.ForeverHubDB
  local charDB = ns.State and ns.State.GetCharDB and ns.State.GetCharDB() or _G.ForeverHubCharDB
  local navSnap = snapshotAndIsolateNavigation(charDB)
  local savedSRState = SR and deepCopyTable(SR.state) or nil
  local savedSRMacroSync = SR and deepCopyTable(SR.macroSyncState) or nil
  local savedAcctMacroSync = (type(_G.ForeverHubDB) == "table") and deepCopyTable(_G.ForeverHubDB.macroSync) or nil
  local savedCharMacroSync = (type(_G.ForeverHubCharDB) == "table") and deepCopyTable(_G.ForeverHubCharDB.macroSync) or nil
  local savedGFProg = charDB and deepCopyTable(charDB.goldFarmProgress) or nil
  local savedGFTelem = charDB and deepCopyTable(charDB.goldFarmTelemetry) or nil
  local savedGoldView = (db and db.uiWorkspace) and deepCopyTable(db.uiWorkspace.goldView) or nil
  local savedGFSess = ns.State and deepCopyTable(ns.State.goldFarmSession) or nil
  local savedWorldSizes = ns.State and ns.State.overrideMapWorldSizes or nil
  local savedPlayerPos = ns.State and ns.State.overridePlayerPosition or nil
  local savedCombat = ns.State and ns.State.overrideInCombat or nil
  local savedXPState = ns.State and ns.State.overridePlayerXPState or nil
  local savedRested = ns.State and ns.State.overrideRestedXP or nil
  local savedInCombatFn = _G.InCombatLockdown
  local savedIsSecret = _G.issecretvalue
  local savedGetNumMacros = _G.GetNumMacros
  local savedGetMacroIndexByName = _G.GetMacroIndexByName
  local savedGetMacroInfo = _G.GetMacroInfo
  local savedCreateMacro = _G.CreateMacro
  local savedEditMacro = _G.EditMacro
  local savedUnitExists = _G.UnitExists
  local savedUnitCanAttack = _G.UnitCanAttack
  local savedUnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
  local savedUnitGUID = _G.UnitGUID
  local savedUnitName = _G.UnitName
  local savedUnitLevel = _G.UnitLevel
  local savedUnitXP = _G.UnitXP
  local savedUnitXPMax = _G.UnitXPMax
  local savedCNamePlate = _G.C_NamePlate

  -- Headless Lua macro interpreter verifying exact sequential WoW 1.60.1.70938 macro semantics!
  local function simulateMacroExecution(body, initialTarget, worldUnits)
    local cur = initialTarget
    for rawLine in string.gmatch(tostring(body or ""), "[^\r\n]+") do
      local line = string.gsub(rawLine, "^%s*(.-)%s*$", "%1")
      if line == "/stopmacro [harm,nodead]" then
        if cur and cur.harm == true and cur.dead ~= true then
          break
        end
      elseif line == "/cleartarget" then
        cur = nil
      elseif line == "/cleartarget [noharm][dead]" then
        if cur and (cur.harm ~= true or cur.dead == true) then
          cur = nil
        end
      else
        local exactName = string.match(line, "^/targetexact%s+(.+)$")
        assertTrue(exactName ~= nil, "Unexpected or bracketed macro command: " .. tostring(line))
        assertTrue(string.find(exactName, "[", 1, true) == nil, "/targetexact must NEVER carry bracketed conditionals")
        for _, u in ipairs(worldUnits or {}) do
          if u.name == exactName then
            cur = u
            break
          end
        end
      end
    end
    return cur
  end

  local suiteOk, suiteErr = pcall(function()
    assertTrue(type(SR) == "table", "SpawnRadar module must load")
    assertTrue(type(GF) == "table", "GoldFarms module must load")

    local allArcaneMapSizes = {
      [1422] = { width = 4300, height = 2867 },
      [1423] = { width = 3870, height = 2580 },
      [1425] = { width = 3850, height = 2567 },
      [1427] = { width = 2231, height = 1487 },
      [1440] = { width = 5766, height = 3844 },
      [1446] = { width = 6900, height = 4600 },
      [1447] = { width = 5070, height = 3380 },
      [1448] = { width = 5750, height = 3833 },
      [1449] = { width = 3700, height = 2467 },
      [1451] = { width = 3483, height = 2322 },
      [1452] = { width = 7100, height = 4733 },
      [2482] = { width = 4200, height = 2800 },
    }
    ns.State.overrideMapWorldSizes = deepCopyTable(allArcaneMapSizes)

    local mockFarm = {
      farmID = "selftest_arcane_camp",
      title = "SelfTest Arcane Owlbeast Camp",
      track = "arcane_lvl47_st",
      targets = {
        { npcID = 2929, name = "Savage Owlbeast" },
        { npcID = 2928, name = "Primitive Owlbeast" },
      },
    }
    local mockStep = {
      stepID = "selftest_grind_step",
      kind = "grind",
      destination = { uiMapID = 1425, areaID = 47, x01 = 0.5000, y01 = 0.5000, coordinateSpace = "uiMap01" },
      spawnNodes = {
        { nodeIndex = 1, locationID = "loc:1425:2928:5000:5000", npcID = 2928, npcName = "Primitive Owlbeast", x01 = 0.5000, y01 = 0.5000, terrainAccess = "surface_candidate" },
        { nodeIndex = 2, locationID = "loc:1425:2929:5000:5117", npcID = 2929, npcName = "Savage Owlbeast", x01 = 0.5000, y01 = 0.5117, terrainAccess = "surface_candidate" }, -- ~30.0 yds south
        { nodeIndex = 3, locationID = "loc:1425:2929:5000:5250", npcID = 2929, npcName = "Savage Owlbeast", x01 = 0.5000, y01 = 0.5250, terrainAccess = "surface_candidate" }, -- ~64.2 yds south
      },
    }

    check("Radar.1: Candidate catalog (19 primary + 7 experimental), deduplicated locationIDs, Tanaris cave-risk exclusion & Lv 46-60 auto-track bounds", function()
      local catalog = ns.State.GetCompiledGoldFarms()
      assertTrue(catalog and type(catalog.arcaneGrindFarms) == "table" and #catalog.arcaneGrindFarms == 19, "Must compile 19 primary Arcane ST candidate farms")
      assertTrue(type(catalog.experimentalArcaneFarms) == "table" and #catalog.experimentalArcaneFarms == 7, "Must compile 7 experimental Arcane ST candidate farms")
      local expectedFirstFiveIDs = {
        "arcane_hinterlands_owlbeasts",
        "arcane_azshara_hippogryphs",
        "arcane_tanaris_dunemaul",
        "arcane_felwood_deadwood",
        "arcane_searing_gorge_elementals",
      }
      local expectedFirstFiveNodeCounts = { 52, 43, 36, 22, 28 }
      local firstFiveNodes = 0
      for idx, f in ipairs(catalog.arcaneGrindFarms) do
        assertTrue(tonumber(f.candidateOrder) == idx, "candidateOrder must match index at #" .. tostring(idx))
        if idx <= 5 then
          assertTrue(f.farmID == expectedFirstFiveIDs[idx], "Candidate order mismatch at #" .. tostring(idx) .. ": got " .. tostring(f.farmID))
        end
        local farmNodes = 0
        local farmSeenLocs = {}
        for _, st in ipairs(f.travelSteps or {}) do
          assertTrue(GF.ValidateStepDestination(st, catalog) == true, "Every primary Arcane step destination must validate (" .. tostring(f.farmID) .. ")")
          if st.kind == "grind" and type(st.spawnNodes) == "table" then
            farmNodes = farmNodes + #st.spawnNodes
            for _, sn in ipairs(st.spawnNodes) do
              assertTrue(type(sn.locationID) == "string" and string.sub(sn.locationID, 1, 4) == "loc:", "Every spawnNode must carry deterministic locationID")
              assertTrue(SR.VALID_TERRAIN_ACCESS[sn.terrainAccess] == true, "Every spawnNode must carry valid shared terrainAccess enum")
              assertTrue(farmSeenLocs[sn.locationID] == nil, "Cross-step duplicate locationID in " .. tostring(f.farmID) .. ": " .. tostring(sn.locationID))
              farmSeenLocs[sn.locationID] = true
            end
          end
        end
        assertTrue(farmNodes > 0, "Every primary Arcane farm must have >=1 QuestieDB spawnNode: " .. tostring(f.farmID))
        if idx <= 5 then
          assertTrue(farmNodes == expectedFirstFiveNodeCounts[idx], "Expected " .. tostring(expectedFirstFiveNodeCounts[idx]) .. " nodes for " .. f.farmID .. ", got " .. tostring(farmNodes))
          firstFiveNodes = firstFiveNodes + farmNodes
        end
      end
      assertTrue(firstFiveNodes == 181, "Expected 181 deduplicated QuestieDB spawn coordinates across #1..#5, got " .. tostring(firstFiveNodes))

      for _, ef in ipairs(catalog.experimentalArcaneFarms) do
        assertTrue(ef.publicationTier == "experimental_candidate", "Experimental route must carry publicationTier='experimental_candidate'")
        for _, st in ipairs(ef.travelSteps or {}) do
          assertTrue(GF.ValidateStepDestination(st, catalog) == true, "Every experimental step destination must validate (" .. tostring(ef.farmID) .. ")")
        end
      end

      -- Tanaris Dunemaul Compound (`unclassified_cave_risk`) MUST be excluded from default active pool until opted in!
      local tanaris = catalog.arcaneGrindFarms[3]
      local compoundStep = tanaris.travelSteps[5]
      assertTrue(compoundStep and compoundStep.excludeFromAutoRadarUntilWalked == true, "Dunemaul Compound must be excluded until walked")
      assertTrue(#SR.GetStepNodes(compoundStep, { includeUnwalkedCaveNodes = false }) == 0, "Default pool must exclude unwalked cave-risk step")
      assertTrue(#SR.GetStepNodes(compoundStep, { includeUnwalkedCaveNodes = true }) == 15, "Explicit opt-in includes compound nodes")

      -- Auto-track bounds (`46..60`):
      local autoUI = { goldView = { selectedTrack = "auto" } }
      assertTrue(GF.GetEffectiveTrack(autoUI, catalog, 45) == "lvl40_mount", "Lv 45 must NOT auto-select arcane_lvl47_st")
      assertTrue(GF.GetEffectiveTrack(autoUI, catalog, 46) == "arcane_lvl47_st", "Lv 46 must auto-select arcane_lvl47_st")
      assertTrue(GF.GetEffectiveTrack(autoUI, catalog, 50) == "arcane_lvl47_st", "Lv 50 must auto-select arcane_lvl47_st")
      assertTrue(GF.GetEffectiveTrack(autoUI, catalog, 55) == "arcane_lvl47_st", "Lv 55 must auto-select arcane_lvl47_st")
      assertTrue(GF.GetEffectiveTrack(autoUI, catalog, 60) == "arcane_lvl47_st", "Lv 60 must auto-select arcane_lvl47_st")
      assertTrue(GF.GetEffectiveTrack(autoUI, catalog, 61) == "lvl40_mount", "Lv 61 must NOT auto-select arcane_lvl47_st")
    end)

    check("Radar.2: Gate 1 Macro Behavioral Semantics (live target preserved, first species kept, dead/friendly cleared)", function()
      local catalog = ns.State.GetCompiledGoldFarms()
      for _, f in ipairs(catalog.arcaneGrindFarms or {}) do
        for _, st in ipairs(f.travelSteps or {}) do
          if st.kind == "grind" then
            local body, meta = SR.BuildTargetMacroBody(f, st)
            assertTrue(type(body) == "string" and meta.ok == true and #body <= 255, "Every grind macro must be <= 255 bytes")
            assertTrue(string.find(body, "^/stopmacro %[harm,nodead%]") ~= nil, "Macro must lead with /stopmacro [harm,nodead]")
          end
        end
      end

      local owlBody = SR.BuildTargetMacroBody(mockFarm, mockStep)
      -- 1) Pressing macro mid-pull NEVER replaces existing live hostile target!
      local existingPull = { id = "pull_a", name = "Primitive Owlbeast", harm = true, dead = false }
      local resMidPull = simulateMacroExecution(owlBody, existingPull, {
        { id = "other_savage", name = "Savage Owlbeast", harm = true, dead = false },
      })
      assertTrue(resMidPull == existingPull, "Macro pressed mid-pull MUST preserve existing [harm,nodead] target")

      -- 2) Both Primitive (attempt 1) and Savage (attempt 2) alive in range -> Primitive MUST NOT be overwritten by Savage!
      local livePrimitive = { id = "prim_1", name = "Primitive Owlbeast", harm = true, dead = false }
      local liveSavage = { id = "savage_1", name = "Savage Owlbeast", harm = true, dead = false }
      local resBoth = simulateMacroExecution(owlBody, nil, { livePrimitive, liveSavage })
      assertTrue(resBoth == livePrimitive, "Second species attempt MUST NOT overwrite live first species")

      -- 3) Primitive corpse + live Savage -> corpse cleared by /cleartarget [noharm][dead], falls through to live Savage!
      local deadPrimitive = { id = "prim_dead", name = "Primitive Owlbeast", harm = true, dead = true }
      local resFallthrough = simulateMacroExecution(owlBody, nil, { deadPrimitive, liveSavage })
      assertTrue(resFallthrough == liveSavage, "Dead first species must be cleared and fall through to live second species")

      -- 4) Friendly namesake cleared -> ends with nil target rather than friendly lock!
      local friendlyUnit = { id = "friendly_1", name = "Primitive Owlbeast", harm = false, dead = false }
      local resFriendly = simulateMacroExecution(owlBody, nil, { friendlyUnit })
      assertTrue(resFriendly == nil, "Non-hostile match must be cleared by /cleartarget [noharm][dead]")
    end)

    check("Radar.3: Gate 2 Macro Security (fail-closed lockdown, 120-slot cap, user collision, >255B overflow & readback parity)", function()
      local macroCalls = 0
      _G.CreateMacro = function() macroCalls = macroCalls + 1; return 1 end
      _G.EditMacro = function() macroCalls = macroCalls + 1; return 1 end

      -- Combat lockdown true -> 0 calls
      ns.State.overrideInCombat = nil
      _G.InCombatLockdown = function() return true end
      local rLock = SR.EnsureTargetMacro(mockFarm, mockStep)
      assertTrue(rLock.ok == false and rLock.reason == "combat_lockdown" and macroCalls == 0, "InCombatLockdown()==true must block macro mutation")

      -- Missing / throwing / secret InCombatLockdown -> fail-closed (0 calls!)
      _G.InCombatLockdown = nil
      local rNil = SR.EnsureTargetMacro(mockFarm, mockStep)
      assertTrue(rNil.ok == false and rNil.reason == "lockdown_probe_missing" and macroCalls == 0, "Missing InCombatLockdown must fail closed")

      _G.InCombatLockdown = function() error("probe_boom") end
      local rErr = SR.EnsureTargetMacro(mockFarm, mockStep)
      assertTrue(rErr.ok == false and rErr.reason == "lockdown_probe_unavailable" and macroCalls == 0, "Erroring InCombatLockdown must fail closed")

      local secretBool = {}
      _G.issecretvalue = function(v) return v == secretBool end
      _G.InCombatLockdown = function() return secretBool end
      local rSec = SR.EnsureTargetMacro(mockFarm, mockStep)
      assertTrue(rSec.ok == false and rSec.reason == "lockdown_probe_unavailable" and macroCalls == 0, "Secret InCombatLockdown must fail closed")
      _G.issecretvalue = savedIsSecret
      _G.InCombatLockdown = function() return false end

      -- User-owned 'FH_Target' collision -> never overwrite user's macro!
      _G.GetMacroIndexByName = function(n) return n == "FH_Target" and 7 or 0 end
      _G.GetMacroInfo = function(idx)
        if idx == 7 then return "FH_Target", 134400, "/cast Ice Block" end
        return nil
      end
      local rCol = SR.EnsureTargetMacro(mockFarm, mockStep)
      assertTrue(rCol.ok == false and rCol.reason == "macro_name_collision" and macroCalls == 0, "User macro named FH_Target must NEVER be overwritten")

      -- 120/120 general macro slots full -> fail closed
      _G.GetMacroIndexByName = function() return 0 end
      _G.GetMacroInfo = function() return nil end
      _G.GetNumMacros = function() return 120, 18 end
      local rFull = SR.EnsureTargetMacro(mockFarm, mockStep)
      assertTrue(rFull.ok == false and rFull.reason == "macro_slots_full" and macroCalls == 0, "120/120 general macro slots must fail closed")

      -- >255B overflow -> atomic refusal, 0 CreateMacro calls
      _G.GetNumMacros = function() return 10, 0 end
      local hugeFarm = {
        farmID = "huge",
        targets = {
          { npcID = 1, uiMapID = 1425, name = "Extremely Long Synthetic Creature Name Alpha One" },
          { npcID = 2, uiMapID = 1425, name = "Extremely Long Synthetic Creature Name Beta Two" },
          { npcID = 3, uiMapID = 1425, name = "Extremely Long Synthetic Creature Name Gamma Three" },
          { npcID = 4, uiMapID = 1425, name = "Extremely Long Synthetic Creature Name Delta Four" },
        },
      }
      local hugeStep = {
        stepID = "huge_step",
        kind = "grind",
        destination = { uiMapID = 1425, x01 = 0.5000, y01 = 0.5000, coordinateSpace = "uiMap01" },
      }
      local rOver = SR.EnsureTargetMacro(hugeFarm, hugeStep)
      assertTrue(rOver.ok == false and rOver.reason == "macro_overflow" and macroCalls == 0, ">255B macro must fail closed without partial write")

      -- Post-write readback mismatch -> detected!
      _G.CreateMacro = function() macroCalls = macroCalls + 1; return 11 end
      _G.GetMacroInfo = function(idx)
        if idx == 11 then return "FH_Target", 134400, "corrupted_body" end
        return nil
      end
      local rMismatch = SR.EnsureTargetMacro(mockFarm, mockStep)
      assertTrue(rMismatch.ok == false and rMismatch.reason == "macro_readback_mismatch", "Post-write readback mismatch must be caught")
    end)

    check("Radar.4: Gate 3 Kill Identity, No Bulk Suppression, GUID Dedup, Ambiguity Rejection & Ranged Pull Separation", function()
      SR.ResetCooldowns()
      local posNear1 = { status = "ok", uiMapID = 1425, x01 = 0.5000, y01 = 0.5015 } -- ~3.85 yds from #1, ~26.2 yds from #2
      local s1 = SR.EvaluateNearestNode(mockFarm, mockStep, posNear1, 0.25, 200.0)
      assertTrue(s1.nodeIndex == 1 and s1.unobservedCount == 3, "Initially locked on node #1")

      -- Unrelated add kill (Timber Wolf) -> 0 suppressions!
      local rWolf = SR.RecordVerifiedKillObservation(
        mockFarm,
        mockStep,
        { npcID = 999999, npcName = "Timber Wolf", guid = "Creature-0-0-0-0-999999-0001" },
        posNear1,
        201.0
      )
      assertTrue(rWolf.suppressed == 0 and rWolf.reason == "identity_not_camp_target", "Unrelated creature kill must suppress 0 nodes")

      -- Verified camp kill + duplicate event for same GUID (Kill A -> Loot/XP A) -> suppresses ONLY 1 node once!
      local owlGuidA = "Creature-0-0-0-0-2928-000A"
      local rKillA1 = SR.RecordVerifiedKillObservation(
        mockFarm,
        mockStep,
        { npcID = 2928, npcName = "Primitive Owlbeast", guid = owlGuidA },
        posNear1,
        202.0
      )
      local rKillA2 = SR.RecordVerifiedKillObservation(
        mockFarm,
        mockStep,
        { npcID = 2928, npcName = "Primitive Owlbeast", guid = owlGuidA },
        posNear1,
        202.5
      )
      assertTrue(rKillA1.suppressed == 1 and rKillA1.locationID == "loc:1425:2928:5000:5000", "Kill A must suppress node #1")
      assertTrue(rKillA2.suppressed == 0 and rKillA2.reason == "duplicate_kill_guid", "Duplicate event for same GUID must NOT suppress a second node")

      -- Ranged pull on B (node #3, Savage) while arrow points to node #2 -> killing B when standing near #2 NEVER suppresses #2 if ambiguous, and standing near #3 while arrow locked #1 suppresses #3 (NOT locked #1)!
      SR.ResetCooldowns()
      SR.EvaluateNearestNode(mockFarm, mockStep, posNear1, 0.25, 210.0)
      assertTrue(SR.state.lockedLocationID == "loc:1425:2928:5000:5000", "Arrow locked on node #1 (Primitive)")
      -- Player pulls & kills Savage (#2 at 30 yds from #1, 34 yds from #3 -> wait: move player to y=0.5220 so #3 is 7.7 yds away and #2 is 26.4 yds away, while lockedLocationID is STILL #1!)
      local posNear3 = { status = "ok", uiMapID = 1425, x01 = 0.5000, y01 = 0.5220 }
      local rKillB = SR.RecordVerifiedKillObservation(
        mockFarm,
        mockStep,
        { npcID = 2929, npcName = "Savage Owlbeast", guid = "Creature-0-0-0-0-2929-000B" },
        posNear3,
        211.0
      )
      assertTrue(rKillB.suppressed == 1 and rKillB.locationID == "loc:1425:2929:5000:5250", "Kill on B must associate with B, NEVER with stale arrow lock A")
      local obsA = SR.GetNodeObservationState(mockStep, mockStep.spawnNodes[1], 211.0)
      assertTrue(obsA == "unobserved", "Arrow lock A (#1) must remain unobserved when B (#3) was killed")

      -- Two same-species nodes < 8 yds apart -> ambiguous kill suppresses 0 nodes!
      local tightStep = {
        stepID = "tight_step",
        kind = "grind",
        destination = { uiMapID = 1425, x01 = 0.5000, y01 = 0.5000, coordinateSpace = "uiMap01" },
        spawnNodes = {
          { nodeIndex = 1, locationID = "loc:tight:1", npcID = 2929, npcName = "Savage Owlbeast", x01 = 0.5000, y01 = 0.5000 },
          { nodeIndex = 2, locationID = "loc:tight:2", npcID = 2929, npcName = "Savage Owlbeast", x01 = 0.5000, y01 = 0.5020 }, -- ~5.1 yds apart!
        },
      }
      local rAmb = SR.RecordVerifiedKillObservation(
        mockFarm,
        tightStep,
        { npcID = 2929, npcName = "Savage Owlbeast", guid = "Creature-0-0-0-0-2929-0099" },
        { status = "ok", uiMapID = 1425, x01 = 0.5000, y01 = 0.5005 },
        220.0
      )
      assertTrue(rAmb.suppressed == 0 and rAmb.reason == "ambiguous_candidate_locations", "Ambiguous <8yd pair must suppress 0 nodes (never bulk radial)")
    end)

    check("Radar.5: Gate 4 Headless — Negative-Evidence Non-Suppression, Manual Skip & Secret-Value Fail-Closed Probes", function()
      SR.ResetCooldowns()
      local posAt1 = { status = "ok", uiMapID = 1425, x01 = 0.5000, y01 = 0.5005 }
      -- Dwell at node #1 for 20 seconds with zero target / nameplates off -> MUST NOT auto-suppress!
      for t = 300, 320, 2 do
        local sum = SR.EvaluateNearestNode(mockFarm, mockStep, posAt1, 2.0, t)
        assertTrue(sum.nodeIndex == 1 and sum.suppressedCount == 0, "Missing nameplate/target MUST NEVER become evidence of death")
      end
      -- Explicit manual skip (/fh gold skip) suppresses current node for 120s (`manually_skipped`)
      local sk = SR.SkipCurrentLocation(mockFarm, mockStep, 321.0)
      assertTrue(sk.ok == true and sk.locationID == "loc:1425:2928:5000:5000", "Explicit SkipCurrentLocation must succeed")
      local afterSkip = SR.EvaluateNearestNode(mockFarm, mockStep, posAt1, 0.25, 321.0)
      assertTrue(afterSkip.nodeIndex == 2 and afterSkip.suppressedCount == 1, "Manual skip advances radar to node #2")

      -- Secret / error-injected unit & nameplate probes MUST fail closed (never fail open to true, never crash!)
      local secretToken = {}
      _G.issecretvalue = function(v) return v == secretToken end
      _G.UnitExists = function() return false end
      _G.C_NamePlate = {
        GetNamePlates = function()
          return { { namePlateUnitToken = secretToken } }
        end,
      }
      local obsSecretPlate = Compat.ObserveMatchingHostileTargetOrNameplate({ [2928] = true }, { ["primitive owlbeast"] = true })
      assertTrue(obsSecretPlate.matched == false and obsSecretPlate.status == "observation_unavailable", "Secret nameplate token must fail closed")

      -- Erroring UnitCanAttack / UnitIsDeadOrGhost with matching GUID/name (Astra's exact fail-open reproduction!) -> MUST return matched == false!
      _G.issecretvalue = savedIsSecret
      _G.UnitExists = function(u) return u == "target" end
      _G.UnitCanAttack = function() error("restricted_hostility") end
      _G.UnitIsDeadOrGhost = function() return false end
      _G.UnitGUID = function() return "Creature-0-0-0-0-2928-0001" end
      _G.UnitName = function() return "Primitive Owlbeast" end
      local obsErrAttack = Compat.ObserveMatchingHostileTargetOrNameplate({ [2928] = true }, { ["primitive owlbeast"] = true })
      assertTrue(obsErrAttack.matched == false and obsErrAttack.status == "observation_unavailable", "Failed hostility check MUST NOT fall through to positive GUID/name match")

      _G.UnitCanAttack = function() return true end
      _G.UnitIsDeadOrGhost = function() error("restricted_death") end
      local obsErrDead = Compat.ObserveMatchingHostileTargetOrNameplate({ [2928] = true }, { ["primitive owlbeast"] = true })
      assertTrue(obsErrDead.matched == false and obsErrDead.status == "observation_unavailable", "Failed death check MUST NOT fall through to positive GUID/name match")
    end)

    check("Radar.6: Gate 5 & Gate 6 — Shared locationID Across Steps, World-Epoch Reset & Fail-Closed distance_unavailable", function()
      SR.ResetCooldowns()
      local stepB = {
        stepID = "selftest_grind_step_b",
        kind = "grind",
        destination = { uiMapID = 1425, areaID = 47, x01 = 0.5000, y01 = 0.5000, coordinateSpace = "uiMap01" },
        spawnNodes = {
          { nodeIndex = 1, locationID = "loc:1425:2928:5000:5000", npcID = 2928, npcName = "Primitive Owlbeast", x01 = 0.5000, y01 = 0.5000 },
          { nodeIndex = 2, locationID = "loc:1425:2929:5000:5300", npcID = 2929, npcName = "Savage Owlbeast", x01 = 0.5000, y01 = 0.5300 },
        },
      }
      SR.RecordVerifiedKillObservation(
        mockFarm,
        mockStep,
        { npcID = 2928, npcName = "Primitive Owlbeast", guid = "Creature-0-0-0-0-2928-7777" },
        { status = "ok", uiMapID = 1425, x01 = 0.5000, y01 = 0.5002 },
        400.0
      )
      local stInB, remInB = SR.GetNodeObservationState(stepB, stepB.spawnNodes[1], 410.0)
      assertTrue(stInB == "estimated_recent_kill" and math.abs(remInB - 170.0) < 0.01, "Shared locationID must synchronize suppression across steps")

      SR.BumpWorldSessionEpoch("zone_transition")
      local stAfterEpoch = SR.GetNodeObservationState(stepB, stepB.spawnNodes[1], 411.0)
      assertTrue(stAfterEpoch == "unobserved", "BumpWorldSessionEpoch must invalidate stale world observations")

      -- Gate 6: Missing map calibration -> fail closed (`distance_unavailable`), NEVER fabricate 3200x2133 yards!
      ns.State.overrideMapWorldSizes = { [1425] = "unavailable" }
      local distUnavail = SR.EvaluateNearestNode(mockFarm, mockStep, { status = "ok", uiMapID = 1425, x01 = 0.5000, y01 = 0.5002 }, 0.25, 420.0)
      assertTrue(distUnavail.status == "distance_unavailable" and distUnavail.distanceYards == nil, "Missing calibration must report distance_unavailable with nil yards")
      local killNoCal = SR.RecordVerifiedKillObservation(
        mockFarm,
        mockStep,
        { npcID = 2928, npcName = "Primitive Owlbeast", guid = "Creature-0-0-0-0-2928-8888" },
        { status = "ok", uiMapID = 1425, x01 = 0.5000, y01 = 0.5002 },
        421.0
      )
      assertTrue(killNoCal.suppressed == 0 and killNoCal.reason == "distance_unavailable", "Yard suppression must be disabled when distance calibration is unavailable")

      ns.State.overrideMapWorldSizes = deepCopyTable(allArcaneMapSizes)
    end)

    check("Radar.7: Gate 7 Coalesced XP Rollover (280 vs 130,000), Multi-Level Unresolved & Quest Turn-In Separation", function()
      local catalog = ns.State.GetCompiledGoldFarms()
      local owlFarm = catalog.arcaneGrindFarms[1]

      -- 1) Astra's exact rollover bug reproduction: Lv 47 (129900/130000) -> mixed Lv 48 (129900/134000) -> Lv 48 (180/134000) == 280 XP!
      ns.State.overridePlayerXPState = { status = "ok", level = 47, currentXP = 129900, maxXP = 130000, remainingXP = 100 }
      ns.State.overrideRestedXP = 0
      ns.State.ResetGoldFarmSession("arcane_hinterlands_owlbeasts", true, 1000)
      ns.State.RecordGoldFarmVerifiedCampKill({ npcID = 2928, expectedXP = 280, nowMono = 1010, nowWall = 1010 })
      ns.State.overridePlayerXPState = { status = "ok", level = 48, currentXP = 129900, maxXP = 134000, remainingXP = 4100 }
      ns.State.ReconcileGoldFarmXPSnapshot({ trigger = "PLAYER_LEVEL_UP", newLevel = 48, nowMono = 1010, nowWall = 1010 })
      ns.State.overridePlayerXPState = { status = "ok", level = 48, currentXP = 180, maxXP = 134000, remainingXP = 133820 }
      local finA = ns.State.ReconcileGoldFarmXPSnapshot({ trigger = "PLAYER_XP_UPDATE", nowMono = 1010, nowWall = 1010 })
      assertTrue(finA.delta == 280, "Mixed rollover transition MUST record 280 XP (not 130,000), got " .. tostring(finA.delta))
      local snapA = ns.State.GetGoldFarmSessionSnapshot(1200)
      assertTrue(snapA.totalSessionXP == 280 and snapA.attributableGrindXP == 280 and snapA.xpRolloverUnresolved == false, "Clean rollover must attribute 280 grind XP")

      -- 2) Reverse arrival order: PLAYER_XP_UPDATE (Lv 47 @ 180) BEFORE PLAYER_LEVEL_UP (Lv 48 @ 180) == 280 XP!
      ns.State.overridePlayerXPState = { status = "ok", level = 47, currentXP = 129900, maxXP = 130000, remainingXP = 100 }
      ns.State.ResetGoldFarmSession("arcane_hinterlands_owlbeasts", true, 2000)
      ns.State.RecordGoldFarmVerifiedCampKill({ npcID = 2928, expectedXP = 280, nowMono = 2005, nowWall = 2005 })
      ns.State.overridePlayerXPState = { status = "ok", level = 47, currentXP = 180, maxXP = 130000, remainingXP = 129820 }
      ns.State.ReconcileGoldFarmXPSnapshot({ trigger = "PLAYER_XP_UPDATE", nowMono = 2005, nowWall = 2005 })
      ns.State.overridePlayerXPState = { status = "ok", level = 48, currentXP = 180, maxXP = 134000, remainingXP = 133820 }
      local finB = ns.State.ReconcileGoldFarmXPSnapshot({ trigger = "PLAYER_LEVEL_UP", newLevel = 48, nowMono = 2005, nowWall = 2005 })
      assertTrue(finB.delta == 280, "XP-before-level rollover MUST also record 280 XP, got " .. tostring(finB.delta))

      -- 3) Multi-level jump (Lv 47 -> Lv 49) marks xpRolloverUnresolved = true and suppresses rate/ETA!
      ns.State.overridePlayerXPState = { status = "ok", level = 47, currentXP = 129900, maxXP = 130000, remainingXP = 100 }
      ns.State.ResetGoldFarmSession("arcane_hinterlands_owlbeasts", true, 3000)
      ns.State.overridePlayerXPState = { status = "ok", level = 49, currentXP = 500, maxXP = 138000, remainingXP = 137500 }
      ns.State.ReconcileGoldFarmXPSnapshot({ trigger = "PLAYER_LEVEL_UP", newLevel = 49, nowMono = 3200, nowWall = 3200 })
      local snapMulti = ns.State.GetGoldFarmSessionSnapshot(3200)
      local repMulti = GF.EvaluateSessionXP(owlFarm, snapMulti, { status = "ok", level = 49, currentXP = 500, maxXP = 138000, remainingXP = 137500 })
      assertTrue(snapMulti.xpRolloverUnresolved == true and repMulti.measuredXpPerHour == nil and repMulti.etaNextLevelMinutes == nil, "Multi-level jump must fail closed as unresolved")

      -- 4) Astra's exact contaminated probe: 6,000 quest XP, 0 kills, 180s -> 0 grind XP/hr and suppressed ETA (NEVER 120,000 XP/hr)!
      ns.State.overridePlayerXPState = { status = "ok", level = 47, currentXP = 50000, maxXP = 130000, remainingXP = 80000 }
      ns.State.ResetGoldFarmSession("arcane_hinterlands_owlbeasts", true, 4000)
      ns.State.overridePlayerXPState = { status = "ok", level = 47, currentXP = 56000, maxXP = 130000, remainingXP = 74000 }
      ns.State.ReconcileGoldFarmXPSnapshot({ trigger = "PLAYER_XP_UPDATE", nowMono = 4060, nowWall = 4060 })
      ns.State.RecordGoldFarmQuestTurnInXP(101, 6000, 4060, 4060) -- arrives AFTER PLAYER_XP_UPDATE!
      local snapQuest = ns.State.GetGoldFarmSessionSnapshot(4180) -- 180s!
      local repQuest = GF.EvaluateSessionXP(owlFarm, snapQuest, { status = "ok", level = 47, currentXP = 56000, maxXP = 130000, remainingXP = 74000 })
      assertTrue(snapQuest.totalSessionXP == 6000 and snapQuest.questRewardXP == 6000 and snapQuest.attributableGrindXP == 0, "Retroactive QUEST_TURNED_IN must move 6000 XP out of unattributed into questRewardXP with 0 grind XP")
      assertTrue(repQuest.measuredGrindXpPerHour == 0 and repQuest.etaNextLevelMinutes == nil and repQuest.liveStatus == "non_grind_xp_only", "Contaminated 0-kill session MUST report 0 grind XP/hr and nil ETA")
    end)

    check("Radar.8: Gate 8 XP Boundaries (179s vs 180s), Rested Regime Suppression & Gold Contamination Independence", function()
      local catalog = ns.State.GetCompiledGoldFarms()
      local owlFarm = catalog.arcaneGrindFarms[1]
      local xpState = { status = "ok", level = 47, currentXP = 60000, maxXP = 130000, remainingXP = 70000 }

      local rep179 = GF.EvaluateSessionXP(owlFarm, {
        active = true,
        elapsedSeconds = 179,
        totalSessionXP = 4200,
        attributableGrindXP = 4200,
        killsObserved = 15,
      }, xpState)
      assertTrue(rep179.liveStatus == "warming_up" and rep179.measuredXpPerHour == nil and rep179.etaNextLevelMinutes == nil, "179s sample MUST block rate & ETA")

      local rep180 = GF.EvaluateSessionXP(owlFarm, {
        active = true,
        elapsedSeconds = 180,
        totalSessionXP = 2100,
        attributableGrindXP = 2100,
        killsObserved = 8,
        contaminated = true, -- Gold mail contamination ONLY (`xpContaminated == false`)!
        xpContaminated = false,
      }, xpState)
      assertTrue(rep180.liveStatus == "measured_positive" and rep180.measuredGrindXpPerHour == 42000 and rep180.etaNextLevelMinutes == 100, "180s clean grind XP must compute 42,000 XP/hr & 100m ETA even when gold purse had mail contamination")

      local repRestedFlip = GF.EvaluateSessionXP(owlFarm, {
        active = true,
        elapsedSeconds = 360,
        totalSessionXP = 4200,
        attributableGrindXP = 4200,
        killsObserved = 15,
        restedIncluded = true,
        restedRegimeChanged = true,
      }, xpState)
      assertTrue(repRestedFlip.measuredGrindXpPerHour == 42000 and repRestedFlip.etaNextLevelMinutes == nil and repRestedFlip.etaSuppressionReason == "rested_regime_changed", "Rested bonus exhaustion mid-session must suppress ETA")
    end)

    check("Radar.9: KI-ARCANE-002 Scope-Aware FH_Target Ownership, No-Auto-Create, Combat Coalescing & Exact UTF-8 Byte Counts", function()
      local catalog = ns.State.GetCompiledGoldFarms()

      -- 1) Exact UTF-8 macro byte lengths (Astra P0-7):
      local function syntheticSingleStep(names)
        local f = { farmID = "byte_probe", targets = {} }
        local s = {
          stepID = "byte_step",
          kind = "grind",
          destination = { uiMapID = 1425, x01 = 0.5000, y01 = 0.5000, coordinateSpace = "uiMap01" },
          spawnNodes = {},
        }
        for i, nm in ipairs(names) do
          table.insert(f.targets, { npcID = i, name = nm })
          table.insert(s.spawnNodes, {
            nodeIndex = i,
            locationID = string.format("loc:1425:%d:5000:%04d", i, 5000 + i),
            npcID = i,
            npcName = nm,
            x01 = 0.5000,
            y01 = 0.5000 + (i * 0.0010),
            terrainAccess = "surface_candidate",
          })
        end
        return SR.BuildTargetMacroBody(f, s)
      end

      local bStag, mStag = syntheticSingleStep({ "Thunderhead Stagwing", "Thunderhead Skystormer" })
      assertTrue(mStag.ok and #bStag == 173, "Stagwing+Skystormer must be 173 bytes, got " .. tostring(bStag and #bStag))
      local bSnap, mSnap = syntheticSingleStep({ "Saltwater Snapjaw" })
      assertTrue(mSnap.ok and #bSnap == 96, "Saltwater Snapjaw must be 96 bytes, got " .. tostring(bSnap and #bSnap))
      local bLegClassic, mLegClassic = syntheticSingleStep({ "Legashi Satyr", "Legashi Rogue", "Legashi Hellcaller" })
      assertTrue(mLegClassic.ok and #bLegClassic == 227, "Classic Legashi trio must be 227 bytes, got " .. tostring(bLegClassic and #bLegClassic))
      local bLegCustom, mLegCustom = syntheticSingleStep({ "Legashi Satyr", "Legashi Felsworn", "Legashi Hellcaller" })
      assertTrue(mLegCustom.ok and #bLegCustom == 230, "Custom Legashi trio must be 230 bytes, got " .. tostring(bLegCustom and #bLegCustom))
      local bBloodElf, mBloodElf = syntheticSingleStep({ "Blood Elf Surveyor", "Blood Elf Reclaimer", "Blood Elf Defender" })
      assertTrue(mBloodElf.ok and #bBloodElf == 238, "Azshara Blood Elf trio must be 238 bytes, got " .. tostring(bBloodElf and #bBloodElf))
      local bOwlA, mOwlA = syntheticSingleStep({ "Raging Owlbeast", "Crazed Owlbeast" })
      assertTrue(mOwlA.ok and #bOwlA == 161, "Raging+Crazed Owlbeast must be 161 bytes, got " .. tostring(bOwlA and #bOwlA))
      local bOwlB, mOwlB = syntheticSingleStep({ "Moontouched Owlbeast", "Berserk Owlbeast" })
      assertTrue(mOwlB.ok and #bOwlB == 167, "Moontouched+Berserk Owlbeast must be 167 bytes, got " .. tostring(bOwlB and #bOwlB))

      local b255, m255 = syntheticSingleStep({ string.rep("A", 176) })
      local b256, m256 = syntheticSingleStep({ string.rep("A", 177) })
      assertTrue(m255.ok == true and #b255 == 255, "Exact 255-byte macro must pass")
      assertTrue(b256 == nil and m256.ok == false and m256.reason == "macro_overflow" and m256.byteLength == 256, "256-byte macro must fail closed")

      -- 2) Scope-aware macro slot harness (`1..120` global, `121..138` character):
      _G.ForeverHubDB = _G.ForeverHubDB or {}
      _G.ForeverHubCharDB = _G.ForeverHubCharDB or {}
      _G.ForeverHubDB.macroSync = {}
      _G.ForeverHubCharDB.macroSync = {}
      SR.macroSyncState.pendingCombatGeneration = nil
      SR.macroSyncState.inMutationGuard = false

      local slots = {}
      local createCalls = 0
      local editCalls = 0
      local reentrantInspectTriggeredWrite = false

      _G.GetNumMacros = function()
        local gCount, cCount = 0, 0
        for idx = 1, 120 do if slots[idx] then gCount = idx end end
        for idx = 121, 138 do if slots[idx] then cCount = idx - 120 end end
        return gCount, cCount
      end
      _G.GetMacroInfo = function(idx)
        local s = slots[idx]
        if s then return s.name, s.icon or 134400, s.body end
        return nil
      end
      _G.GetMacroIndexByName = function(nm)
        for idx = 1, 120 do if slots[idx] and slots[idx].name == nm then return idx end end
        for idx = 121, 138 do if slots[idx] and slots[idx].name == nm then return idx end end
        return 0
      end
      _G.CreateMacro = function(nm, icon, body, perChar)
        createCalls = createCalls + 1
        local base = perChar and 121 or 1
        local cap = perChar and 138 or 120
        for idx = base, cap do
          if not slots[idx] then
            slots[idx] = { name = nm, icon = icon, body = body }
            return idx
          end
        end
        return 0
      end
      _G.EditMacro = function(idx, nm, icon, body)
        editCalls = editCalls + 1
        slots[idx] = { name = nm, icon = icon, body = body }
        -- Simulate synchronous UPDATE_MACROS inside EditMacro to prove reentrancy guard!
        local reRes = SR.SyncExistingOwnedTargetMacro("SYNCHRONOUS_UPDATE_MACROS")
        if reRes and reRes.reason ~= "reentrant_guarded" then
          reentrantInspectTriggeredWrite = true
        end
        return idx
      end
      ns.State.overrideInCombat = nil
      _G.InCombatLockdown = function() return false end

      -- A) Starting a grind route with NO existing macro NEVER calls CreateMacro (`Missing — click to create`)!
      local okStart1 = GF.Start("arcane_hinterlands_owlbeasts", catalog, nil, { status = "ok", uiMapID = 1425, x01 = 0.5140, y01 = 0.4560 }, "arcane_lvl47_st")
      assertTrue(okStart1 == true and createCalls == 0 and editCalls == 0, "Route start must NEVER auto-create FH_Target")
      assertTrue(SR.GetMacroSyncStatus().status == "Missing — click to create", "Missing macro must report 'Missing — click to create'")

      -- B) Legacy boolean `ownedMacros.FH_Target = true` + canonical `/stopmacro` prefix WITHOUT `macroSync` record MUST NOT authorize overwrite!
      slots[1] = {
        name = "FH_Target",
        body = "/stopmacro [harm,nodead]\n/cleartarget\n/targetexact Custom User Target\n/cleartarget [noharm][dead]",
      }
      local gProg = ns.State.GetGoldFarmProgress()
      gProg.ownedMacros = { FH_Target = true }
      local rLegacy = SR.SyncExistingOwnedTargetMacro("legacy_probe")
      assertTrue(rLegacy.ok == false and rLegacy.reason == "macro_name_collision" and editCalls == 0 and createCalls == 0, "Legacy boolean + prefix alone must NEVER authorize overwrite")

      -- C) Explicit character-scope creation (`slot 121`), auto-sync on route transition, user edit revocation & explicit adopt:
      slots = {}
      local rCharCreate = SR.CreateOrAdoptTargetMacro(catalog.arcaneGrindFarms[1], catalog.arcaneGrindFarms[1].travelSteps[3], { scope = "character" })
      assertTrue(rCharCreate.ok == true and rCharCreate.scope == "character" and rCharCreate.macroIndex == 121 and createCalls == 1, "Character-scoped CreateOrAdoptTargetMacro must create in slot 121")
      assertTrue(_G.ForeverHubCharDB.macroSync.FH_Target and _G.ForeverHubCharDB.macroSync.FH_Target.lastWrittenBody == slots[121].body, "Character scope DB must record exact body")

      -- Transition to #6 (`arcane_hinterlands_snapjaws`, 96B Saltwater Snapjaw) -> auto-updates owned character macro!
      GF.Start("arcane_hinterlands_snapjaws", catalog, nil, { status = "ok", uiMapID = 1425, x01 = 0.7710, y01 = 0.6120 }, "arcane_lvl47_st")
      assertTrue(createCalls == 1 and editCalls == 1 and #slots[121].body == 96, "Owned macro must auto-sync to 96B Saltwater Snapjaw on route switch")
      assertTrue(reentrantInspectTriggeredWrite == false, "Synchronous UPDATE_MACROS inside EditMacro must hit reentrant_guarded")

      -- User edits macro body -> status becomes `User modified` and subsequent route transitions make 0 writes!
      slots[121].body = slots[121].body .. "\n/run print(1)"
      local stMod = SR.GetMacroSyncStatus()
      assertTrue(stMod.status == "User modified", "Edited body must report 'User modified'")
      GF.Start("arcane_azshara_thunderheads", catalog, nil, { status = "ok", uiMapID = 1447, x01 = 0.5600, y01 = 0.3000 }, "arcane_lvl47_st")
      assertTrue(editCalls == 1, "User-modified macro must NEVER be overwritten on route transition")

      -- Explicit `forceAdopt = true` re-adopts slot 121 and writes 99B Thunderhead Stagwing body!
      local rAdopt = SR.CreateOrAdoptTargetMacro(catalog.arcaneGrindFarms[7], catalog.arcaneGrindFarms[7].travelSteps[3], { forceAdopt = true })
      assertTrue(rAdopt.ok == true and rAdopt.action == "adopted" and editCalls == 2 and #slots[121].body == 99, "Explicit adopt must restore ownership and write 99B Thunderhead Stagwing body")

      -- D) Duplicate global + character `FH_Target` conflict fails closed with 0 writes!
      slots[2] = { name = "FH_Target", body = slots[121].body }
      local rDup = SR.SyncExistingOwnedTargetMacro("dup_scope")
      assertTrue(rDup.ok == false and rDup.reason == "duplicate_macro_scope_conflict" and rDup.status == "Unavailable" and editCalls == 2, "Duplicate global+char FH_Target must fail closed")
      slots[2] = nil

      -- E) Combat single-intent coalescing: `A (#7) -> B (#1) -> C (#6)` in combat flushes ONLY `C (#6)` once!
      _G.InCombatLockdown = function() return true end
      GF.Start("arcane_hinterlands_owlbeasts", catalog, nil, { status = "ok", uiMapID = 1425, x01 = 0.5140, y01 = 0.4560 }, "arcane_lvl47_st")
      GF.Start("arcane_hinterlands_snapjaws", catalog, nil, { status = "ok", uiMapID = 1425, x01 = 0.7710, y01 = 0.6120 }, "arcane_lvl47_st")
      assertTrue(editCalls == 2 and SR.GetMacroSyncStatus().status == "Pending combat", "Combat route transitions must defer without writing")
      _G.InCombatLockdown = function() return false end
      local rFlush = SR.FlushPendingMacroSync()
      assertTrue(rFlush and rFlush.ok == true and editCalls == 3 and #slots[121].body == 96, "Combat flush must write ONLY final target C (96B) in 1 EditMacro call")

      -- Combat `C (#6) -> B (#1) -> Stop` in combat flushes 0 writes after combat!
      _G.InCombatLockdown = function() return true end
      GF.Start("arcane_hinterlands_owlbeasts", catalog, nil, { status = "ok", uiMapID = 1425, x01 = 0.5140, y01 = 0.4560 }, "arcane_lvl47_st")
      GF.Stop(false, catalog)
      _G.InCombatLockdown = function() return false end
      local rStopFlush = SR.FlushPendingMacroSync()
      assertTrue(rStopFlush == nil and editCalls == 3 and createCalls == 1, "Stopping route during combat must cancel pending generation with 0 writes")

      -- UI Presenter/View refresh must perform 0 macro writes!
      if ns.UI and ns.UI.GoldFarmsPresenter then
        local snapUI = ns.UI.GoldFarmsPresenter.CaptureSnapshot()
        ns.UI.GoldFarmsPresenter.Build(snapUI)
      end
      assertTrue(editCalls == 3 and createCalls == 1, "UI snapshot/build must perform 0 macro mutations")
    end)

    check("Radar.10: KI-ARCANE-002 Fail-Closed terrainAccess, Subcamp Macro Parity & Timbermaw Prerequisite Gate", function()
      local catalog = ns.State.GetCompiledGoldFarms()

      -- 1) Unknown / malformed / `excluded_hazard` terrainAccess MUST fail closed even when `includeUnwalkedCaveNodes = true`!
      local optInProg = { includeUnwalkedCaveNodes = true }
      local defProg = { includeUnwalkedCaveNodes = false }
      local normalStep = { stepID = "s_norm", kind = "grind", excludeFromAutoRadarUntilWalked = false }
      assertTrue(SR.IsNodeTerrainAdmitted(normalStep, { terrainAccess = "walked_verified" }, defProg) == true, "walked_verified admitted")
      assertTrue(SR.IsNodeTerrainAdmitted(normalStep, { terrainAccess = "surface_candidate" }, defProg) == true, "surface_candidate admitted")
      assertTrue(SR.IsNodeTerrainAdmitted(normalStep, { terrainAccess = "unclassified_cave_risk" }, defProg) == false, "unclassified_cave_risk excluded by default")
      assertTrue(SR.IsNodeTerrainAdmitted(normalStep, { terrainAccess = "unclassified_cave_risk" }, optInProg) == true, "unclassified_cave_risk admitted on explicit opt-in")
      assertTrue(SR.IsNodeTerrainAdmitted(normalStep, { terrainAccess = "excluded_hazard" }, optInProg) == false, "excluded_hazard MUST remain excluded even with opt-in")
      for _, badVal in ipairs({ "cave_unverified", "outdoor_verified", "", 123, false }) do
        assertTrue(SR.IsNodeTerrainAdmitted(normalStep, { terrainAccess = badVal }, optInProg) == false, "Unknown terrainAccess must fail closed: " .. tostring(badVal))
      end

      -- 2) Subcamp macro parity: excluded_hazard species & farm-level species absent from active subcamp MUST NOT enter macro!
      local parityFarm = {
        farmID = "parity_farm",
        targets = {
          { npcID = 10, name = "Admitted Alpha" },
          { npcID = 20, name = "Excluded Hazard Beta" },
          { npcID = 30, name = "Other Subcamp Gamma" },
        },
      }
      local parityStep = {
        stepID = "parity_step",
        kind = "grind",
        destination = { uiMapID = 1425, x01 = 0.5, y01 = 0.5, coordinateSpace = "uiMap01" },
        spawnNodes = {
          { nodeIndex = 1, locationID = "loc:p:1", npcID = 10, npcName = "Admitted Alpha", x01 = 0.5, y01 = 0.5, terrainAccess = "surface_candidate" },
          { nodeIndex = 2, locationID = "loc:p:2", npcID = 20, npcName = "Excluded Hazard Beta", x01 = 0.5, y01 = 0.51, terrainAccess = "excluded_hazard" },
        },
      }
      local pBody, pMeta = SR.BuildTargetMacroBody(parityFarm, parityStep, optInProg)
      assertTrue(pMeta.ok == true and pMeta.speciesCount == 1, "Subcamp macro must emit ONLY admitted node species")
      assertTrue(string.find(pBody, "Admitted Alpha", 1, true) ~= nil and string.find(pBody, "Beta", 1, true) == nil and string.find(pBody, "Gamma", 1, true) == nil, "Excluded/off-subcamp species must be omitted")

      -- 3) Timbermaw Hold (`conditionally_blocked_crossing`) holds arrival on Felwood side until Winterspring map 1452 reached!
      local wsOwl = GF.LookupFarmByID("arcane_winterspring_owlbeasts", catalog)
      assertTrue(wsOwl ~= nil, "Must find arcane_winterspring_owlbeasts (#16)")
      local timberStep = wsOwl.travelSteps[2]
      assertTrue(timberStep and timberStep.prerequisiteGate and timberStep.prerequisiteGate.gateKind == "conditionally_blocked_crossing", "Hop 2 must carry conditionally_blocked_crossing gate")
      local arrivedAtMouth, reasonMouth = GF.CheckHopArrival(timberStep, { status = "ok", uiMapID = 1448, x01 = 0.6510, y01 = 0.0840 }, catalog, wsOwl)
      assertTrue(arrivedAtMouth == false and reasonMouth == "prerequisite_gate_requires_crossing_or_manual", "Standing at Felwood tunnel mouth must NOT auto-complete gated crossing")
      local arrivedInWS, reasonWS = GF.CheckHopArrival(timberStep, { status = "ok", uiMapID = 1452, x01 = 0.2800, y01 = 0.3450 }, catalog, wsOwl)
      assertTrue(arrivedInWS == true and reasonWS == "prerequisite_crossing_destination_reached", "Reaching Winterspring map 1452 completes gated crossing")
    end)

    check("Radar.11: KI-ARCANE-002 Raw 59->60 Cap XP Adapter (UnitXPMax==0 & >0, Both Orders, Quest Attribution & Purse KPI Pivot)", function()
      local catalog = ns.State.GetCompiledGoldFarms()
      local silFarm = GF.LookupFarmByID("arcane_silithus_twilight", catalog)
      assertTrue(silFarm ~= nil, "Must find #19 arcane_silithus_twilight")

      -- Exercise RAW client probe path (`overridePlayerXPState = nil`) so Compat.GetPlayerXPState is tested end-to-end!
      ns.State.overridePlayerXPState = nil
      ns.State.overrideRestedXP = 0
      local rawLvl, rawXP, rawMax = 59, 209600, 209800
      _G.UnitLevel = function() return rawLvl end
      _G.UnitXP = function() return rawXP end
      _G.UnitXPMax = function() return rawMax end

      -- Case A: `UnitXPMax == 0` at Level 60, level-first (`PLAYER_LEVEL_UP(60)` -> `PLAYER_XP_UPDATE`), verified grind kill:
      local probe59 = Compat.GetPlayerXPState()
      assertTrue(probe59.status == "ok" and probe59.level == 59 and probe59.remainingXP == 200, "Raw Lv 59 probe must read 209600/209800")
      ns.State.ResetGoldFarmSession("arcane_silithus_twilight", true, 5000)
      ns.State.RecordGoldFarmVerifiedCampKill({ npcID = 11880, expectedXP = 320, nowMono = 5240, nowWall = 5240 })
      rawLvl, rawXP, rawMax = 60, 0, 0
      local probe60Zero = Compat.GetPlayerXPState()
      assertTrue(probe60Zero.status == "capped" and probe60Zero.isCapped == true and probe60Zero.maxXP == 0, "Raw Lv 60 0/0 probe MUST return status='capped' without clamping maxXP to 1")

      local capRes1 = ns.State.ReconcileGoldFarmXPSnapshot({ trigger = "PLAYER_LEVEL_UP", newLevel = 60, nowMono = 5240, nowWall = 5240 })
      local capRes2 = ns.State.ReconcileGoldFarmXPSnapshot({ trigger = "PLAYER_XP_UPDATE", nowMono = 5240, nowWall = 5240 })
      assertTrue(capRes1.delta == 200 and (capRes2.delta or 0) == 0, "Terminal 59->60 ding must credit 200 XP exactly once")

      -- Continue farming at cap until t=5600 (600s total, 240s pre-cap): pre-cap rate freezes at 240s (`200 * 3600 / 240 = 3000 XP/hr`)!
      ns.State.ReconcileGoldFarmXPSnapshot({ trigger = "PLAYER_XP_UPDATE", nowMono = 5600, nowWall = 5600 })
      local snapCapA = ns.State.GetGoldFarmSessionSnapshot(5600)
      local repCapA = GF.EvaluateSessionXP(silFarm, snapCapA, Compat.GetPlayerXPState())
      assertTrue(snapCapA.levelCapReached == true and snapCapA.xpElapsedAtCap == 240 and snapCapA.totalSessionXP == 200 and snapCapA.attributableGrindXP == 200, "Cap snapshot must freeze pre-cap XP & elapsed time")
      assertTrue(repCapA.measuredGrindXpPerHour == 3000 and repCapA.etaNextLevelMinutes == nil and repCapA.etaSuppressionReason == "level_cap_reached", "Cap XP report must freeze pre-cap rate and suppress ETA")

      -- Case B: `UnitXPMax > 0` at Level 60 (`0 / 217400`), XP-first transitional (`59, 0/0` -> `60, 0/217400`) via Quest Turn-In:
      rawLvl, rawXP, rawMax = 59, 209300, 209800 -- remaining = 500
      ns.State.ResetGoldFarmSession("arcane_silithus_twilight", true, 6000)
      rawLvl, rawXP, rawMax = 59, 0, 0 -- transitional XP-first frame before UnitLevel flips to 60!
      local transRes = ns.State.ReconcileGoldFarmXPSnapshot({ trigger = "PLAYER_XP_UPDATE", nowMono = 6200, nowWall = 6200 })
      assertTrue((transRes.delta or 0) == 0, "Transitional (59, 0/0) frame must hold without premature reset or negative delta")
      rawLvl, rawXP, rawMax = 60, 0, 217400 -- non-zero maxXP at cap!
      ns.State.RecordGoldFarmQuestTurnInXP(5501, 4500, 6200, 6200)
      local capQuestRes = ns.State.ReconcileGoldFarmXPSnapshot({ trigger = "PLAYER_LEVEL_UP", newLevel = 60, nowMono = 6200, nowWall = 6200 })
      local snapCapB = ns.State.GetGoldFarmSessionSnapshot(6300)
      assertTrue(capQuestRes.delta == 500 and snapCapB.totalSessionXP == 500 and snapCapB.questRewardXP == 500 and snapCapB.attributableGrindXP == 0, "Quest turn-in ding into 60 (0/217400) must attribute 500 to questRewardXP and 0 to grind")

      -- Case C: Level 60 Presenter KPI Pivot (`Net Purse / Active Hr`, `Current purse`, `Level & XP` @ Cap, `Next level ETA` retired):
      if ns.UI and ns.UI.GoldFarmsPresenter then
        local presSnap = ns.UI.GoldFarmsPresenter.CaptureSnapshot()
        local vm60 = ns.UI.GoldFarmsPresenter.Build(presSnap, { goldView = { selectedTrack = "arcane_lvl47_st", subFilter = "my_level" } })
        assertTrue(vm60.isLevelCapped == true, "Presenter VM must detect Level 60 cap")
        assertTrue(vm60.kpis and vm60.kpis[1] and vm60.kpis[1].label == "Net Purse / Active Hr", "KPI #1 must pivot to Net Purse / Active Hr at Level 60")
        assertTrue(vm60.kpis[2] and vm60.kpis[2].label == "Current purse", "KPI #2 must show Current purse at Level 60")
        assertTrue(vm60.kpis[3] and vm60.kpis[3].label == "Level & XP" and vm60.kpis[3].value == "Lv 60 (Cap)", "KPI #3 must show Lv 60 (Cap)")
        assertTrue(vm60.kpis[4] and vm60.kpis[4].label == "Next level ETA" and vm60.kpis[4].value == "Cap reached", "KPI #4 must retire Next level ETA as Cap reached")
      end

      _G.UnitLevel = savedUnitLevel
      _G.UnitXP = savedUnitXP
      _G.UnitXPMax = savedUnitXPMax
    end)

    check("Radar.12: KI-ARCANE-002 Lv 46-60 Ideal Subcamp Coverage, +3 Mixed Badge, Non-Disruptive Sub-Filter & Map Index", function()
      local catalog = ns.State.GetCompiledGoldFarms()

      -- 1) Every integer player level 46..60 MUST have >= 1 outdoor `Ideal` subcamp in `my_level`!
      for lvl = 46, 60 do
        local fRes = GF.FilterArcaneFarms(catalog, "my_level", lvl, { includeUnwalkedCaveNodes = false })
        assertTrue(type(fRes.farms) == "table" and #fRes.farms >= 1, "Level " .. tostring(lvl) .. " must have >=1 eligible subcamp")
        local topEv = fRes.evalByFarmID[fRes.farms[1].farmID]
        assertTrue(topEv and topEv.code == "ideal", "Level " .. tostring(lvl) .. " top subcamp must be Ideal, got " .. tostring(topEv and topEv.code))
      end

      -- Verify `all_shortlist` (19) and `experimental` (7) counts:
      local allRes = GF.FilterArcaneFarms(catalog, "all_shortlist", 52)
      local expRes = GF.FilterArcaneFarms(catalog, "experimental", 52)
      assertTrue(#allRes.farms == 19, "all_shortlist must return all 19 primary farms")
      assertTrue(#expRes.farms == 7, "experimental must return all 7 experimental farms")

      -- 2) Mixed +3 resist warning (`High Resist (+3 Mixed)`) on #19 Casters subcamp (`58-60`) at Level 57:
      local sil19 = GF.LookupFarmByID("arcane_silithus_twilight", catalog)
      local castersStep = sil19.travelSteps[4]
      local ev57 = GF.EvaluateStepEligibility(sil19, castersStep, 57, { includeUnwalkedCaveNodes = false })
      assertTrue(ev57.code == "high_resist" and ev57.badgeLabel == "High Resist (+3 Mixed)", "Lv 57 against 58-60 subcamp must warn High Resist (+3 Mixed)")

      -- 3) Visibility-only sub-filter switching NEVER stops/pauses active route or resets session meters, and surfaces `hiddenActiveRouteSummary`!
      GF.Start("arcane_hinterlands_owlbeasts", catalog, nil, { status = "ok", uiMapID = 1425, x01 = 0.5140, y01 = 0.4560 }, "arcane_lvl47_st")
      local gProg = ns.State.GetGoldFarmProgress()
      assertTrue(gProg.mode == "standalone" and gProg.selectedFarmID == "arcane_hinterlands_owlbeasts", "Active Hinterlands route running")
      if ns.UI and ns.UI.GoldFarms and ns.UI.GoldFarmsPresenter then
        ns.UI.GoldFarms.Dispatch("SET_SUBFILTER", { subFilter = "57_60" })
        assertTrue(gProg.mode == "standalone" and gProg.selectedFarmID == "arcane_hinterlands_owlbeasts", "SET_SUBFILTER must NEVER pause or change active route")
        local snap = ns.UI.GoldFarmsPresenter.CaptureSnapshot()
        local vmHidden = ns.UI.GoldFarmsPresenter.Build(snap, { goldView = { selectedTrack = "arcane_lvl47_st", subFilter = "57_60" } })
        assertTrue(vmHidden.hiddenActiveRouteSummary ~= nil and vmHidden.hiddenActiveRouteSummary.farmID == "arcane_hinterlands_owlbeasts", "Hidden active route must surface persistent banner summary")
        ns.UI.GoldFarms.Dispatch("SET_SUBFILTER", { subFilter = "my_level" })
      end
      GF.Stop(false, catalog)

      -- 4) Pre-indexed WorldMapPins lookup (`O(|map_step_nodes|)`):
      if ns.UI and ns.UI.WorldMapPins and ns.UI.WorldMapPins.EnsureGoldFarmMapIndex then
        local idxA = ns.UI.WorldMapPins.EnsureGoldFarmMapIndex(catalog)
        local idxB = ns.UI.WorldMapPins.EnsureGoldFarmMapIndex(catalog)
        assertTrue(idxA ~= nil and idxA == idxB, "EnsureGoldFarmMapIndex must cache per catalog hash")
        assertTrue(idxA.byMapID[1425] and #idxA.byMapID[1425] >= 2, "Hinterlands map 1425 must index owlbeast & turtle farms")
        assertTrue(idxA.byMapID[1452] and #idxA.byMapID[1452] >= 2, "Winterspring map 1452 must index owlbeast & ghost farms")
        assertTrue(idxA.byMapID[2482] and #idxA.byMapID[2482] >= 1, "Hyjal map 2482 must index experimental farm")
      end
    end)
  end)

  _G.InCombatLockdown = savedInCombatFn
  _G.issecretvalue = savedIsSecret
  _G.GetNumMacros = savedGetNumMacros
  _G.GetMacroIndexByName = savedGetMacroIndexByName
  _G.GetMacroInfo = savedGetMacroInfo
  _G.CreateMacro = savedCreateMacro
  _G.EditMacro = savedEditMacro
  _G.UnitExists = savedUnitExists
  _G.UnitCanAttack = savedUnitCanAttack
  _G.UnitIsDeadOrGhost = savedUnitIsDeadOrGhost
  _G.UnitGUID = savedUnitGUID
  _G.UnitName = savedUnitName
  _G.UnitLevel = savedUnitLevel
  _G.UnitXP = savedUnitXP
  _G.UnitXPMax = savedUnitXPMax
  _G.C_NamePlate = savedCNamePlate

  if SR and savedSRState then
    SR.state = savedSRState
  end
  if SR and savedSRMacroSync then
    SR.macroSyncState = savedSRMacroSync
  end
  if type(_G.ForeverHubDB) == "table" then
    _G.ForeverHubDB.macroSync = savedAcctMacroSync
  end
  if type(_G.ForeverHubCharDB) == "table" then
    _G.ForeverHubCharDB.macroSync = savedCharMacroSync
  end
  if db and db.uiWorkspace and savedGoldView then
    db.uiWorkspace.goldView = savedGoldView
  end
  if charDB then
    charDB.goldFarmProgress = savedGFProg
    charDB.goldFarmTelemetry = savedGFTelem
  end
  if ns.State then
    ns.State.goldFarmSession = savedGFSess
    ns.State.overrideMapWorldSizes = savedWorldSizes
    ns.State.overridePlayerPosition = savedPlayerPos
    ns.State.overrideInCombat = savedCombat
    ns.State.overridePlayerXPState = savedXPState
    ns.State.overrideRestedXP = savedRested
  end
  restoreNavigationSnapshot(navSnap, charDB)

  local report = {
    passed = passed,
    failed = failed,
    total = passed + failed,
    results = results,
  }
  if suiteOk then
    SelfTest.cachedReports.spawn_radar = report
  end
  SelfTest._running.spawn_radar = false

  if not suiteOk then
    error(suiteErr, 2)
  end

  return report
end

-- ============================================================================
-- Sunken Temple Coach RC1 Acceptance Self-Tests (Astra Gates ST-01 .. ST-10)
-- ============================================================================

function SelfTest.RunSunkenTempleCoachSuite()
  if SelfTest._running.sunken_temple_rc1 then
    return SelfTest.cachedReports.sunken_temple_rc1 or { passed = 0, failed = 0, total = 0, results = {} }
  end
  SelfTest._running.sunken_temple_rc1 = true
  SelfTest.suiteRunCounts.sunken_temple_rc1 = (SelfTest.suiteRunCounts.sunken_temple_rc1 or 0) + 1

  local results = {}
  local passed = 0
  local failed = 0
  local function check(name, fn)
    local ok, err = pcall(fn)
    if ok then
      passed = passed + 1
      table.insert(results, { name = name, passed = true })
    else
      failed = failed + 1
      table.insert(results, { name = name, passed = false, error = tostring(err) })
    end
  end

  local db = ns.State and ns.State.GetDB and ns.State.GetDB() or _G.ForeverHubDB
  local charDB = ns.State and ns.State.GetCharDB and ns.State.GetCharDB() or _G.ForeverHubCharDB
  local navSnap = snapshotAndIsolateNavigation(charDB)

  local coach = ns.Domain and ns.Domain.SunkenTempleCoach
  local stData = ns.SunkenTempleData
  local il = ns.Domain and ns.Domain.InstanceLedger
  local nav = ns.UI and ns.UI.Navigation
  local cardUI = ns.UI and ns.UI.SunkenTempleCard

  local savedCoachState = coach and deepCopyTable(coach.state) or nil
  local savedProbeStore = coach and deepCopyTable(coach.probeStore) or nil
  local savedCoachEventFrame = coach and coach.eventFrame or nil
  local savedCardHidden = cardUI and cardUI.frame and cardUI.frame.IsShown and cardUI.frame:IsShown() or false
  local savedInstanceLedger = db and deepCopyTable(db.instanceLedger) or nil
  local savedGFProg = charDB and deepCopyTable(charDB.goldFarmProgress) or nil

  local savedIsSecret = _G.issecretvalue
  local savedInCombat = _G.InCombatLockdown
  local savedIsInInstance = _G.IsInInstance
  local savedGetInstanceInfo = _G.GetInstanceInfo
  local savedGetLocale = _G.GetLocale
  local savedCreateFrame = _G.CreateFrame
  local savedCreateMacro = _G.CreateMacro
  local savedEditMacro = _G.EditMacro
  local savedTargetUnit = _G.TargetUnit
  local savedSetRaidTarget = _G.SetRaidTarget
  local savedUnitExists = _G.UnitExists
  local savedUnitGUID = _G.UnitGUID
  local savedUnitName = _G.UnitName
  local savedUnitHealth = _G.UnitHealth
  local savedUnitHealthMax = _G.UnitHealthMax
  local savedUnitBuff = _G.UnitBuff
  local savedCUnitAuras = _G.C_UnitAuras
  local savedCNamePlate = _G.C_NamePlate
  local savedGetSubZoneText = _G.GetSubZoneText
  local savedGetMinimapZoneText = _G.GetMinimapZoneText

  local savedOverrideCombat = ns.State and ns.State.overrideInCombat or nil
  local savedOverrideDead = ns.State and ns.State.overridePlayerIsDeadOrGhost or nil
  local savedOverrideNativeWp = ns.State and ns.State.overrideNativeWaypointState or nil
  local savedOverrideMono = ns.State and ns.State.overrideMonotonicTime or nil
  local savedOverrideLocale = ns.State and ns.State.overrideClientLocale or nil
  local savedOverridePos = ns.State and ns.State.overridePlayerPosition or nil
  local savedOverrideWorldSizes = ns.State and ns.State.overrideMapWorldSizes or nil

  local function resetCoachClean()
    coach.state = {
      sessionState = "INACTIVE",
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
    }
    coach.probeStore = {
      registrations = {},
      observedEventSamples = {},
      runs = {},
      lastSnapshot = nil,
    }
  end

  local suiteOk, suiteErr = pcall(function()
    assertTrue(coach ~= nil and stData ~= nil, "SunkenTempleCoach and SunkenTempleData must be loaded")

    check("ST-01: Identity — Distinct Return #8 (109) vs Return #9 (5), Type & Ambiguity Gate", function()
      resetCoachClean()
      _G.issecretvalue = function() return false end
      ns.State.overridePlayerIsDeadOrGhost = false

      _G.IsInInstance = function() return false, "none" end
      _G.GetInstanceInfo = function() return "Swamp of Sorrows", "none", 0, "", 0, 0, false, 0, 0 end
      local sOut = coach.ObserveEnvironmentTransition()
      assertTrue(sOut == "INACTIVE" and coach.state.hasObservedOutsideBeforeEntry == true, "Outside sets INACTIVE and records outside baseline")

      _G.IsInInstance = function() return true, "party" end
      _G.GetInstanceInfo = function() return "The Temple of Atal'Hakkar", "party", 1, "Normal", 5, 0, false, 5, 109 end
      local sSwapped, clsSwapped = coach.ObserveEnvironmentTransition()
      assertTrue(sSwapped == "INACTIVE" and clsSwapped == "other_instance", "Swapped r8=5/r9=109 must be rejected as other_instance")

      _G.GetInstanceInfo = function() return "Zul'Farrak", "party", 1, "Normal", 5, 0, false, 209, 5 end
      local sZF = coach.ObserveEnvironmentTransition()
      assertTrue(sZF == "INACTIVE", "Zul'Farrak (209) must keep ST coach INACTIVE")

      _G.IsInInstance = function() return true, "raid" end
      _G.GetInstanceInfo = function() return "The Temple of Atal'Hakkar", "raid", 1, "Raid", 20, 0, false, 109, 20 end
      local sRaid, clsRaid = coach.ObserveEnvironmentTransition()
      assertTrue(sRaid == "INACTIVE" and clsRaid == "instance_type_mismatch", "Raid instanceType must fail ST party gate")

      _G.IsInInstance = function() return true, "party" end
      _G.GetInstanceInfo = function() return "The Temple of Atal'Hakkar", "party", 1, "Normal", 5, 0, false, nil, 5 end
      local sAmbig, clsAmbig = coach.ObserveEnvironmentTransition()
      assertTrue(sAmbig == "INACTIVE" and clsAmbig == "ambiguous_unresolved_identity", "Localized name without numeric r8=109 must stay INACTIVE")
      assertTrue(coach.state.localizedNameHintMatched == true, "Localized name hint recorded for diagnostics only")

      _G.IsInInstance = function() return false, "none" end
      _G.GetInstanceInfo = function() return "Swamp of Sorrows", "none", 0, "", 0, 0, false, 0, 0 end
      coach.ObserveEnvironmentTransition()
      _G.IsInInstance = function() return true, "party" end
      _G.GetInstanceInfo = function() return "The Temple of Atal'Hakkar", "party", 1, "Normal", 5, 0, false, 109, 5 end
      local sST, clsST = coach.ObserveEnvironmentTransition({ ledgerActiveRunID = "run_st01_1", resumedExistingRun = false })
      assertTrue(sST == "READY" and clsST == "verified_fresh_entry", "Verified ST (r8=109, r9=5) must open READY")
    end)

    check("ST-02: Directional Honesty — Hidden Chevrons Indoors & 180-Deg Camera-Invariant Landmark Card", function()
      resetCoachClean()
      local secretCoord = setmetatable({}, {})
      _G.issecretvalue = function(v) return _G.rawequal(v, secretCoord) end
      ns.State.overrideClientLocale = "enUS"

      ns.State.overridePlayerFacing = secretCoord
      ns.State.overridePlayerWorldPosition = nil
      ns.State.overridePlayerPosition = { status = "restricted", reason = "secret_xy" }
      ns.State.overrideMapWorldSizes = { [1435] = { 2293, 1529 } }

      local arrowSettings = ns.State.GetArrowSettings()
      arrowSettings.enabled = true
      arrowSettings.dockedInHud = true
      nav.SetArrowTarget("gold_farm", { uiMapID = 1435, x01 = 0.70, y01 = 0.55, zoneName = "Swamp of Sorrows" }, "ST Portal", "Portal", 20, "native_waypoint")
      local snapDocked = nav.GetLiveArrowSnapshot()
      assertTrue(snapDocked.active == false, "Docked directional arrow must NOT be active with secret coords/facing")
      if nav.frame and nav.frame.dockedArrowLane and nav.frame.dockedArrowLane.arrowTex and nav.frame.dockedArrowLane.arrowTex.IsShown then
        assertTrue(nav.frame.dockedArrowLane.arrowTex:IsShown() == false, "Docked chevron must be hidden")
      end

      arrowSettings.dockedInHud = false
      nav.RefreshArrowSettings()
      local snapFloat = nav.GetLiveArrowSnapshot()
      assertTrue(snapFloat.active == false, "Floating directional arrow must NOT be active with secret coords/facing")
      if nav.arrowFrame and nav.arrowFrame.arrowTex and nav.arrowFrame.arrowTex.IsShown then
        assertTrue(nav.arrowFrame.arrowTex:IsShown() == false, "Floating chevron must be hidden")
      end

      local verifiedStepFixture = {
        index = 1,
        phaseID = "APPROACH_SANCTUARY",
        shortTitle = "Approach Sanctuary",
        title = "1. Approach Sanctuary",
        glyph = "travel",
        actionableKind = "traversal",
        verificationState = "live_confirmed",
        locale = "enUS",
        provenance = {
          sourceUrl = "https://example.invalid/st-verified",
          timestamps = "01:15-01:42",
          recordedBuildOrDate = "1.60.1.70938",
          liveConfirmedOnPlayerCharacter = true,
        },
        geometry = {
          approachLandmark = "Broken Spiral Stairwell Arch",
          referencePose = "Face the central dragon arch from the upper landing",
          actionableInstruction = "take the left archway opening",
          visibleSuccessCue = "Hall of Masks circular balcony in view",
          abortRoute = "Run back down entry ramp to instance portal",
        },
      }

      coach.state.verifiedSunkenTemple = true
      coach.state.sessionState = "ACTIVE"
      coach.state.phaseIndex = 1
      ns.State.overridePlayerFacing = 0.0
      local vmFace0 = cardUI.Refresh(verifiedStepFixture)
      ns.State.overridePlayerFacing = math.pi
      local vmFace180 = cardUI.Refresh(verifiedStepFixture)

      assertTrue(vmFace0.dataReadinessOk == true, "Verified fixture passes readiness")
      assertTrue(vmFace0.landmarkLine == vmFace180.landmarkLine and vmFace0.instructionLine == vmFace180.instructionLine, "180-deg turn must not alter landmark/reference-pose text")
      assertTrue(string.find(vmFace180.instructionLine, "Face the central dragon arch", 1, true) ~= nil, "Reference pose must be explicit")
    end)

    check("ST-03: Ownership — Combat Portal Suppression, Failed Clear Guard, User Pin Survival & Corpse/Stale Exit", function()
      resetCoachClean()
      _G.issecretvalue = function() return false end
      ns.State.overridePlayerIsDeadOrGhost = false
      ns.State.overrideMapWorldSizes = { [1435] = { 2293, 1529 } }
      ns.State.overridePlayerPosition = { status = "ok", uiMapID = 1435, x01 = 0.50, y01 = 0.50 }
      ns.State.overrideNativeWaypointState = {
        supported = true,
        current = nil,
        clearMustFail = false,
      }

      ns.State.overrideInCombat = false
      _G.IsInInstance = function() return false, "none" end
      _G.GetInstanceInfo = function() return "Swamp of Sorrows", "none", 0, "", 0, 0, false, 0, 0 end
      local catalog = ns.State.GetCompiledGoldFarms()
      ns.Domain.GoldFarms.Start("swamp_jaguars_snappers", catalog, nil, ns.State.overridePlayerPosition)
      local gProg = ns.State.GetGoldFarmProgress()
      nav.SyncFromGoldFarmEvaluation(nil, gProg)
      assertTrue(nav.owner.provider == "native_waypoint" and nav.owner.ownerContext == "gold_farm", "Outdoor native waypoint acquired")

      ns.State.overrideInCombat = true
      _G.IsInInstance = function() return true, "party" end
      _G.GetInstanceInfo = function() return "The Temple of Atal'Hakkar", "party", 1, "Normal", 5, 0, false, 109, 5 end
      coach.ObserveEnvironmentTransition({ ledgerActiveRunID = "run_st03_1" })
      assertTrue(nav.activeTarget == nil, "Outdoor arrow target must be suppressed on portal entry")
      assertTrue(nav.owner.pendingRelease == true and nav.owner.provider == "native_waypoint" and nav.owner.handle ~= nil, "Deferred ownership token retained in combat")
      assertTrue(nav.owner.ownerContext ~= "st_coach", "Coach must NEVER take waypoint ownership")

      ns.State.overrideInCombat = false
      ns.State.overrideNativeWaypointState.clearMustFail = true
      _G.IsInInstance = function() return false, "none" end
      _G.GetInstanceInfo = function() return "Swamp of Sorrows", "none", 0, "", 0, 0, false, 0, 0 end
      local okExitFail, reasonExitFail = nav.OnInstancePortalExit(nav.owner.generation, false)
      assertTrue(okExitFail == false and nav.owner.pendingRelease == true, "Clear failure must block reacquisition (" .. tostring(reasonExitFail) .. ")")

      ns.State.overrideNativeWaypointState.clearMustFail = false
      ns.State.overrideNativeWaypointState.current = { uiMapID = 1435, x01 = 0.2121, y01 = 0.3434 }
      local okRelUser, relReasonUser = nav.TryReleaseOwnedResource()
      assertTrue(okRelUser == true and relReasonUser == "confirmed_user_replacement", "User replacement must drop FH token cleanly")
      assertTrue(ns.State.overrideNativeWaypointState.current ~= nil and ns.State.overrideNativeWaypointState.current.x01 == 0.2121, "User's waypoint must survive untouched")

      local staleGen = (nav.owner.generation or 1) - 1
      local okStale, reasonStale = nav.OnInstancePortalExit(staleGen, false)
      assertTrue(okStale == false and reasonStale == "stale_generation_discarded", "Stale generation must be discarded")

      local curGen = nav.owner.generation
      local okCorpse, reasonCorpse = nav.OnInstancePortalExit(curGen, true)
      assertTrue(okCorpse == false and reasonCorpse == "corpse_transition_suppressed", "Corpse exit must not reacquire outdoor route")
      ns.Domain.GoldFarms.Stop(false, catalog)
    end)

    check("ST-04: Secret Handling — Hostile Poison Proxies, Missing/Throwing Detector & Rejected Registration", function()
      resetCoachClean()
      local function makePoisonProxy()
        local p = {}
        local mt = {
          __index = function() error("HOSTILE_INDEX") end,
          __newindex = function() error("HOSTILE_NEWINDEX") end,
          __tostring = function() error("HOSTILE_TOSTRING") end,
          __add = function() error("HOSTILE_ADD") end,
          __sub = function() error("HOSTILE_SUB") end,
          __lt = function() error("HOSTILE_LT") end,
          __le = function() error("HOSTILE_LE") end,
          __eq = function() error("HOSTILE_EQ") end,
        }
        return setmetatable(p, mt)
      end

      local poisonSecret = makePoisonProxy()
      local poisonUnflagged = makePoisonProxy()

      _G.issecretvalue = nil
      local rMissingDet = ns.Compat.ClassifySecretSafeValue(poisonSecret, { secretCapable = true })
      assertTrue(rMissingDet.status == "unknown" and rMissingDet.value == nil, "Missing detector on secret-capable path must return unknown")

      _G.issecretvalue = function() error("DETECTOR_EXPLODED") end
      local rThrowDet = ns.Compat.ClassifySecretSafeValue(poisonSecret, { secretCapable = true })
      assertTrue(rThrowDet.status == "errored" and rThrowDet.value == nil, "Throwing detector must return errored")

      _G.issecretvalue = function(v) return _G.rawequal(v, poisonSecret) end
      local rSec = ns.Compat.ClassifySecretSafeValue(poisonSecret, { secretCapable = true, expectedType = "string" })
      assertTrue(rSec.status == "restricted" and rSec.value == nil, "Secret poison proxy must classify as restricted")

      local rBadType = ns.Compat.ClassifySecretSafeValue(poisonUnflagged, { secretCapable = true, expectedType = "number" })
      assertTrue(rBadType.status == "errored" and rBadType.value == nil, "Hostile type mismatch must return errored")

      local rFalse = ns.Compat.ClassifySecretSafeValue(false, { secretCapable = true, expectedType = "boolean" })
      local rZero = ns.Compat.ClassifySecretSafeValue(0, { secretCapable = true, expectedType = "number" })
      assertTrue(rFalse.status == "readable" and rFalse.value == false, "Legitimate false must be preserved")
      assertTrue(rZero.status == "readable" and rZero.value == 0, "Legitimate 0 must be preserved")

      local rejectedMockFrame = {
        RegisterUnitEvent = function() error("RESTRICTED_UNIT_EVENT") end,
        RegisterEvent = function(_, ev)
          if ev == "CHAT_MSG_MONSTER_YELL" then error("RESTRICTED_YELL") end
          return true
        end,
      }
      coach.AttachEventRegistrations(rejectedMockFrame)
      _G.C_UnitAuras = {
        GetPlayerAuraBySpellID = function() return poisonSecret end,
        GetBuffDataByIndex = function() return { name = poisonSecret, spellId = 11426, expirationTime = poisonSecret } end,
      }
      _G.UnitHealth = function() return poisonSecret end
      _G.UnitHealthMax = function() return 3200 end
      _G.C_NamePlate = {
        GetNamePlates = function() return { { namePlateUnitToken = poisonSecret } } end,
      }
      local snap = coach.RunOptInProbe("trash")
      assertTrue(snap.signals.unitSpellcastSucceeded.status == "registration_rejected", "Rejected unit event registration must be reported")
      assertTrue(snap.signals.monsterYell.status == "registration_rejected", "Rejected yell registration must be reported")
      assertTrue(snap.signals.cUnitAuras.bySpellIDStatus == "restricted", "Secret aura return must be restricted")
      assertTrue(snap.signals.cUnitAuras.byIndexFields.name == "restricted" and snap.signals.cUnitAuras.byIndexFields.spellId == "readable", "Nested aura fields classified per-field")
      assertTrue(snap.signals.unitHealth.healthStatus == "restricted" and snap.signals.unitHealth.maxHealthStatus == "readable", "Health and maxHealth guarded independently")
      assertTrue(snap.signals.namePlates.firstTokenStatus == "restricted", "Secret nameplate nested token classified restricted")
      _G.CreateFrame = savedCreateFrame
      coach.eventFrame = nil
    end)

    check("ST-05: Phase Control — Events Never Auto-Advance; Manual Controls Work Deterministically In Combat", function()
      resetCoachClean()
      _G.issecretvalue = function() return false end
      ns.State.overridePlayerIsDeadOrGhost = false
      ns.State.overrideMonotonicTime = 100.0

      _G.IsInInstance = function() return false, "none" end
      _G.GetInstanceInfo = function() return "Swamp of Sorrows", "none", 0, "", 0, 0, false, 0, 0 end
      coach.ObserveEnvironmentTransition()
      _G.IsInInstance = function() return true, "party" end
      _G.GetInstanceInfo = function() return "The Temple of Atal'Hakkar", "party", 1, "Normal", 5, 0, false, 109, 5 end
      coach.ObserveEnvironmentTransition({ ledgerActiveRunID = "run_st05_1" })

      ns.State.overrideInCombat = true
      _G.InCombatLockdown = function() return true end

      local okStart = coach.StartAttempt(100.0)
      assertTrue(okStart == true and coach.state.phaseIndex == 1, "StartAttempt works in combat at Phase 1")

      coach.OnCombatStart(101.0)
      coach.OnCombatStart(101.0)
      coach.OnMonsterChatEvent("YELL", "The coil of evil...", "Shade of Eranikus", 102.0)
      coach.OnUnitSpellcastSucceeded("player", "Cast-1", 10, 103.0)
      coach.OnUnitSpellcastSucceeded("player", "Cast-2", 11958, 105.0)
      coach.OnUnitSpellcastSucceeded("player", "Cast-1", 10, 104.0)
      coach.OnCombatEnd(106.0)
      assertTrue(coach.state.phaseIndex == 1 and coach.state.sessionState == "ACTIVE", "Live events must NEVER auto-advance phase")

      local okN1, p2 = coach.NextPhase(110.0)
      local okN2, p3 = coach.NextPhase(115.0)
      local okPrev, pBack2 = coach.PrevPhase(118.0)
      assertTrue(okN1 and p2 == 2 and okN2 and p3 == 3 and okPrev and pBack2 == 2, "Manual Next/Prev deterministic in combat")
      assertTrue(coach.state.currentAttempt.manualPrevCorrections == 1, "Prev records manual correction")

      local okFin, aut = coach.FinishAttempt(130.0)
      assertTrue(okFin and aut.outcome == "PLAYER_REPORTED_COMPLETE" and coach.state.sessionState == "READY", "FinishAttempt closes cleanly in combat")
    end)

    check("ST-06: Outcome Integrity — Open Combat End, Sighting Non-Failure, Idempotent PLAYER_DEAD & Evidence Tiers", function()
      resetCoachClean()
      _G.issecretvalue = function() return false end
      ns.State.overridePlayerIsDeadOrGhost = false
      _G.IsInInstance = function() return false, "none" end
      _G.GetInstanceInfo = function() return "Swamp of Sorrows", "none", 0, "", 0, 0, false, 0, 0 end
      coach.ObserveEnvironmentTransition()
      _G.IsInInstance = function() return true, "party" end
      _G.GetInstanceInfo = function() return "The Temple of Atal'Hakkar", "party", 1, "Normal", 5, 0, false, 109, 5 end
      coach.ObserveEnvironmentTransition({ ledgerActiveRunID = "run_st06_1" })

      coach.StartAttempt(200.0)
      coach.NextPhase(205.0)
      coach.NextPhase(210.0)
      coach.NextPhase(215.0)

      _G.UnitExists = function(u) return u == "target" end
      _G.UnitGUID = function(u) return u == "target" and "Creature-0-0-0-0-5719-00000001" or nil end
      _G.UnitName = function(u) return u == "target" and "Morphaz" or nil end
      coach.OnCombatStart(216.0)
      coach.OnTargetChangedSample(218.0)
      coach.OnUnitSpellcastSucceeded("player", "Cast-B1", 10, 220.0)
      coach.OnUnitSpellcastSucceeded("player", "Cast-B2", 10, 233.0)
      coach.OnCombatEnd(235.0)

      assertTrue(coach.state.sessionState == "ACTIVE" and coach.state.currentAttempt.closed == false, "Combat end with 0 kills, visible dragon, and 0 yells MUST keep attempt open")

      coach.NextPhase(240.0)
      local okDead1, aut1 = coach.OnPlayerDead(245.0)
      local okDead2 = coach.OnPlayerDead(246.0)
      assertTrue(okDead1 == true and okDead2 == false, "PLAYER_DEAD must close the attempt EXACTLY ONCE")
      assertTrue(coach.state.currentAttempt.closeCount == 1 and aut1.outcome == "DIED", "Single close with DIED outcome")

      assertTrue(#aut1.claims >= 5, "Autopsy must include confirmed, heuristic, and unobservable claims")
      local sawBlizGap = false
      for _, c in ipairs(aut1.claims) do
        assertTrue(type(c.tier) == "string" and type(c.evidence) == "string" and c.evidence ~= "" and type(c.coverage) == "string" and c.coverage ~= "", "Every claim must specify tier, evidence, and coverage")
        assertTrue(c.code ~= "failed_reset" and c.code ~= "failed_rp", "Must never fabricate failed_reset or failed_rp")
        if c.code == "blizzard_cast_gap" then
          sawBlizGap = true
          assertTrue(c.tier == "LIKELY_HEURISTIC" and type(c.missingLink) == "string" and c.missingLink ~= "", "Heuristic must name missing link")
        end
      end
      assertTrue(sawBlizGap == true, "13s Blizzard gap must surface as LIKELY_HEURISTIC")
    end)

    check("ST-07: Reload & Re-entry — Mid-Pull Reload, Death, Ghost Exit, Same-Copy Re-entry & Floor Coalescing", function()
      resetCoachClean()
      _G.issecretvalue = function() return false end
      ns.State.overridePlayerIsDeadOrGhost = false
      if db then db.instanceLedger = nil end
      il.EnsureInitialized()

      _G.IsInInstance = function() return true, "party" end
      _G.GetInstanceInfo = function() return "The Temple of Atal'Hakkar", "party", 1, "Normal", 5, 0, false, 109, 5 end
      local tr1 = il.ObserveTransition({ nowEpoch = 1000 })
      local sReload = coach.ObserveEnvironmentTransition({ ledgerActiveRunID = tr1.activeRunID, resumedExistingRun = tr1.resumedExistingRun })
      assertTrue(sReload == "RECOVERY", "Mid-instance /reload must enter RECOVERY")
      local okStartBlocked = coach.StartAttempt(300.0)
      assertTrue(okStartBlocked == false, "RECOVERY must block StartAttempt until explicit RearmCoach")

      local okRearm = coach.RearmCoach()
      assertTrue(okRearm == true and coach.state.sessionState == "READY", "Explicit RearmCoach transitions RECOVERY -> READY")
      coach.StartAttempt(305.0)
      coach.NextPhase(310.0)

      local admBefore = il.GetSummarySnapshot().observedSessionAdmissions
      local trFloor = il.ObserveTransition({ nowEpoch = 1015 })
      local sFloor = coach.ObserveEnvironmentTransition({ ledgerActiveRunID = trFloor.activeRunID, resumedExistingRun = trFloor.resumedExistingRun })
      local admAfter = il.GetSummarySnapshot().observedSessionAdmissions
      assertTrue(admAfter == admBefore and sFloor == "ACTIVE" and coach.state.phaseIndex == 2, "Floor bursts must coalesce without bumping admissions or phase")

      coach.OnPlayerDead(320.0)
      assertTrue(coach.state.sessionState == "RECOVERY", "Death enters RECOVERY")
      ns.State.overridePlayerIsDeadOrGhost = true
      _G.IsInInstance = function() return false, "none" end
      _G.GetInstanceInfo = function() return "Swamp of Sorrows", "none", 0, "", 0, 0, false, 0, 0 end
      il.ObserveTransition({ nowEpoch = 1025, isGhostOrCorpseRun = true })
      coach.ObserveEnvironmentTransition({ isCorpseOrGhost = true })
      assertTrue(coach.state.sessionState == "INACTIVE", "Outside as ghost is INACTIVE")

      ns.State.overridePlayerIsDeadOrGhost = false
      _G.IsInInstance = function() return true, "party" end
      _G.GetInstanceInfo = function() return "The Temple of Atal'Hakkar", "party", 1, "Normal", 5, 0, false, 109, 5 end
      local trReenter = il.ObserveTransition({ nowEpoch = 1040 })
      local sReenter = coach.ObserveEnvironmentTransition({ ledgerActiveRunID = trReenter.activeRunID, resumedExistingRun = trReenter.resumedExistingRun })
      assertTrue(trReenter.resumedExistingRun == true and sReenter == "RECOVERY", "Same-copy re-entry must land in RECOVERY")
      assertTrue(coach.StartAttempt(345.0) == false, "Same-copy re-entry requires RearmCoach")

      coach.RearmCoach()
      coach.StartAttempt(350.0)
      coach.NextPhase(352.0)
      _G.IsInInstance = function() return false, "none" end
      _G.GetInstanceInfo = function() return "Swamp of Sorrows", "none", 0, "", 0, 0, false, 0, 0 end
      il.ObserveTransition({ nowEpoch = 1060 })
      coach.ObserveEnvironmentTransition()
      il.ObserveResetSignal("system_confirm")
      _G.IsInInstance = function() return true, "party" end
      _G.GetInstanceInfo = function() return "The Temple of Atal'Hakkar", "party", 1, "Normal", 5, 0, false, 109, 5 end
      local trFresh = il.ObserveTransition({ nowEpoch = 1070 })
      local sFresh = coach.ObserveEnvironmentTransition({ ledgerActiveRunID = trFresh.activeRunID, resumedExistingRun = trFresh.resumedExistingRun })
      assertTrue(sFresh == "READY" and coach.state.phaseIndex == 0, "Fresh post-reset copy must open READY at phase 0")
    end)

    check("ST-08: Macro Isolation — Zero Targeting, Raid-Marking, or Macro Writes Across Coach & Probe", function()
      resetCoachClean()
      _G.issecretvalue = function() return false end
      local forbiddenCalls = 0
      _G.CreateMacro = function() forbiddenCalls = forbiddenCalls + 1 end
      _G.EditMacro = function() forbiddenCalls = forbiddenCalls + 1 end
      _G.TargetUnit = function() forbiddenCalls = forbiddenCalls + 1 end
      _G.SetRaidTarget = function() forbiddenCalls = forbiddenCalls + 1 end

      coach.eventFrame = nil
      coach.EnsureEventFrame()
      coach.RunOptInProbe("outside")
      coach.OnCombatStart(400.0)
      coach.OnCombatEnd(405.0)
      assertTrue(forbiddenCalls == 0, "Coach startup, probe, and combat transitions must produce ZERO macro/target/mark writes")
    end)

    check("ST-09: Bounds & Regressions — 64-Event Ring Overflow Preserves Header & Zero SavedVariables Bytes", function()
      resetCoachClean()
      _G.issecretvalue = function() return false end
      ns.State.overridePlayerIsDeadOrGhost = false

      local function countKeysDeep(t)
        if type(t) ~= "table" then return 1 end
        local n = 0
        for k, v in pairs(t) do
          n = n + 1 + countKeysDeep(k) + countKeysDeep(v)
        end
        return n
      end

      local dbBefore = countKeysDeep(_G.ForeverHubDB)
      local charDbBefore = countKeysDeep(_G.ForeverHubCharDB)

      _G.IsInInstance = function() return false, "none" end
      _G.GetInstanceInfo = function() return "Swamp of Sorrows", "none", 0, "", 0, 0, false, 0, 0 end
      coach.ObserveEnvironmentTransition()
      _G.IsInInstance = function() return true, "party" end
      _G.GetInstanceInfo = function() return "The Temple of Atal'Hakkar", "party", 1, "Normal", 5, 0, false, 109, 5 end
      coach.ObserveEnvironmentTransition({ ledgerActiveRunID = "run_st09_1" })

      coach.StartAttempt(500.0)
      coach.NextPhase(502.0)
      for i = 1, 90 do
        coach.OnUnitSpellcastSucceeded("player", "Cast-" .. tostring(i), 10, 502.0 + i)
      end
      local okAb, aut = coach.AbortAttempt("overflow_test", 600.0)
      assertTrue(okAb == true and aut.overflowed == true, "90+ events must flag overflowed == true")
      assertTrue(#aut.retainedRingEntries == 64 and aut.totalObservedEvents > 64, "Ring buffer must stay capped at 64 entries")
      assertTrue(aut.outcome == "ABORTED" and aut.terminalPhaseIndex == 2, "Terminal outcome & phase header preserved despite ring overflow")
      assertTrue(coach.state.currentAttempt.phaseConfirmations[1] ~= nil and coach.state.currentAttempt.phaseConfirmations[2] ~= nil, "Independent phase confirmations preserved")

      coach.RunOptInProbe("post")
      local dbAfter = countKeysDeep(_G.ForeverHubDB)
      local charDbAfter = countKeysDeep(_G.ForeverHubCharDB)
      assertTrue(dbAfter == dbBefore and charDbAfter == charDbBefore, "ST Coach & Probe must add ZERO SavedVariables entries/bytes")
    end)

    check("ST-10: Data Readiness — Unverified, Missing-Locale, Incomplete-Jump & Probe States Gate Actionable Cues", function()
      resetCoachClean()
      _G.issecretvalue = function() return false end

      for idx = 1, 6 do
        local p = coach.GetPhaseDefinition(idx)
        local okReady, reason = stData.ValidateStepDataReadiness(p, "enUS")
        assertTrue(okReady == false and reason == "unverified_route_entry", "RC1 phase " .. tostring(idx) .. " must gate actionable cues")
      end

      local snap = coach.RunOptInProbe("ooc")
      assertTrue(snap.provesRouteReadiness == false, "Probe snapshot must explicitly report provesRouteReadiness == false")
      local okProbeStep, reasonProbeStep = stData.ValidateStepDataReadiness({
        phaseID = "BOSS_DRAGON_RESET",
        actionableKind = "reset",
        verificationState = "probe_observed",
      }, "enUS")
      assertTrue(okProbeStep == false and reasonProbeStep == "probe_does_not_prove_route_readiness", "probe_observed state must fail ST-10")

      local baseJump = {
        phaseID = "KILL_LEDGE",
        actionableKind = "jump",
        verificationState = "live_confirmed",
        locale = "enUS",
        provenance = {
          sourceUrl = "https://youtube.com/watch?v=example",
          timestamps = "04:10-05:00",
          recordedBuildOrDate = "1.60.1.70938",
          liveConfirmedOnPlayerCharacter = true,
        },
        geometry = {
          approachLandmark = "Upper Tunnel Corner",
          referencePose = "Face north wall torch from tunnel lip",
          actionableInstruction = "jump onto the corner ledge",
          visibleSuccessCue = "Standing above melee pathing line",
          abortRoute = "Ice Block then drop to lower hall",
        },
      }
      local okNoTakeoff, rNoTakeoff = stData.ValidateStepDataReadiness(baseJump, "enUS")
      assertTrue(okNoTakeoff == false and rNoTakeoff == "missing_jump_takeoff_or_landing", "Jump step without takeoff/landing must fail ST-10")

      baseJump.geometry.jumpTakeoff = "Outer stone seam"
      baseJump.geometry.jumpLanding = "Elevated corner molding"
      local okWrongLoc, rWrongLoc = stData.ValidateStepDataReadiness(baseJump, "deDE")
      assertTrue(okWrongLoc == false and rWrongLoc == "missing_localized_geometry", "Mismatched locale without localizedGeometry must fail ST-10")

      baseJump.provenance.liveConfirmedOnPlayerCharacter = false
      local okUnwalked, rUnwalked = stData.ValidateStepDataReadiness(baseJump, "enUS")
      assertTrue(okUnwalked == false and rUnwalked == "missing_live_character_confirmation", "Video-only step without live character confirmation must fail ST-10")

      baseJump.provenance.liveConfirmedOnPlayerCharacter = true
      local okFull = stData.ValidateStepDataReadiness(baseJump, "enUS")
      assertTrue(okFull == true, "Fully provenanced, locale-matched, live-confirmed jump step passes ST-10")
    end)
  end)

  _G.issecretvalue = savedIsSecret
  _G.InCombatLockdown = savedInCombat
  _G.IsInInstance = savedIsInInstance
  _G.GetInstanceInfo = savedGetInstanceInfo
  _G.GetLocale = savedGetLocale
  _G.CreateFrame = savedCreateFrame
  _G.CreateMacro = savedCreateMacro
  _G.EditMacro = savedEditMacro
  _G.TargetUnit = savedTargetUnit
  _G.SetRaidTarget = savedSetRaidTarget
  _G.UnitExists = savedUnitExists
  _G.UnitGUID = savedUnitGUID
  _G.UnitName = savedUnitName
  _G.UnitHealth = savedUnitHealth
  _G.UnitHealthMax = savedUnitHealthMax
  _G.UnitBuff = savedUnitBuff
  _G.C_UnitAuras = savedCUnitAuras
  _G.C_NamePlate = savedCNamePlate
  _G.GetSubZoneText = savedGetSubZoneText
  _G.GetMinimapZoneText = savedGetMinimapZoneText

  if coach then
    coach.state = savedCoachState
    coach.probeStore = savedProbeStore
    coach.eventFrame = savedCoachEventFrame
  end
  if cardUI and cardUI.frame then
    ns.UI.Widgets.SafeShow(cardUI.frame, savedCardHidden)
  end
  if db then
    db.instanceLedger = savedInstanceLedger
  end
  if charDB then
    charDB.goldFarmProgress = savedGFProg
  end
  if ns.State then
    ns.State.overrideInCombat = savedOverrideCombat
    ns.State.overridePlayerIsDeadOrGhost = savedOverrideDead
    ns.State.overrideNativeWaypointState = savedOverrideNativeWp
    ns.State.overrideMonotonicTime = savedOverrideMono
    ns.State.overrideClientLocale = savedOverrideLocale
    ns.State.overridePlayerPosition = savedOverridePos
    ns.State.overrideMapWorldSizes = savedOverrideWorldSizes
  end
  restoreNavigationSnapshot(navSnap, charDB)

  local report = {
    passed = passed,
    failed = failed,
    total = passed + failed,
    results = results,
  }
  if suiteOk then
    SelfTest.cachedReports.sunken_temple_rc1 = report
  end
  SelfTest._running.sunken_temple_rc1 = false

  if not suiteOk then
    error(suiteErr, 2)
  end

  return report
end
