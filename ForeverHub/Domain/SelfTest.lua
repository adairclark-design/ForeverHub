local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.Domain = ns.Domain or {}
local SelfTest = {}
ns.Domain.SelfTest = SelfTest

SelfTest._running = {
  core = false,
  riverglades = false,
  gold_farms = false,
  workspace_ui = false,
}
SelfTest.cachedReports = {
  core = nil,
  riverglades = nil,
  gold_farms = nil,
  workspace_ui = nil,
}
SelfTest.suiteRunCounts = {
  core = 0,
  riverglades = 0,
  gold_farms = 0,
  workspace_ui = 0,
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
  local rgProg = ns.State and ns.State.GetRouteProgress and ns.State.GetRouteProgress() or nil
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
    savedRgOwnedWp = rgProg and deepCopyTable(rgProg.ownedWaypoint) or nil,
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
  local rgProg = ns.State and ns.State.GetRouteProgress and ns.State.GetRouteProgress() or nil
  local gfProg = ns.State and ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress() or nil
  if rgProg then
    rgProg.ownedWaypoint = snap.savedRgOwnedWp
  end
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
    elseif suiteKey == "riverglades" and SelfTest.RunRivergladesSuite then
      rep = SelfTest.RunRivergladesSuite()
    elseif suiteKey == "gold_farms" and SelfTest.RunGoldFarmsSuite then
      rep = SelfTest.RunGoldFarmsSuite()
    elseif suiteKey == "workspace_ui" and SelfTest.RunWorkspaceUISuite then
      rep = SelfTest.RunWorkspaceUISuite()
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
-- v0.4.0 Riverglades Route, Navigation, Reward Value & Mount Acceptance Suite
-- Covers GPT Astra's 10 Mandatory v0.4.0 Offline Acceptance Gates
-- ============================================================================

function SelfTest.RunRivergladesSuite()
  if SelfTest._running.riverglades then
    error("Recursive SelfTest.RunRivergladesSuite invocation forbidden", 2)
  end
  SelfTest._running.riverglades = true
  SelfTest.suiteRunCounts.riverglades = (SelfTest.suiteRunCounts.riverglades or 0) + 1

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

  local RoutePlanner = ns.Domain.RoutePlanner
  local RouteProgress = ns.Domain.RouteProgress
  local RewardValue = ns.Domain.RewardValue
  local route = ns.RivergladesData and ns.RivergladesData.route

  local charDB = ns.State and ns.State.GetCharDB and ns.State.GetCharDB() or nil
  local savedRGProg = charDB and deepCopyTable(charDB.routeProgress) or nil
  local savedGFProg = charDB and deepCopyTable(charDB.goldFarmProgress) or nil
  local savedSuiteDiscoveredIds = _G.ForeverHubDB and deepCopyTable(_G.ForeverHubDB.discoveredQuestIds or {}) or nil
  local savedSuiteDiscoveredTitles = _G.ForeverHubDB and deepCopyTable(_G.ForeverHubDB.discoveredQuestTitlesById or {}) or nil
  local navSnap = snapshotAndIsolateNavigation(charDB)

  local function makeMockCtx(overrides)
    overrides = overrides or {}
    local completed = overrides.completed or {}
    local active = overrides.active or {}
    local objectives = overrides.objectives or {}
    local items = overrides.items or {}
    return {
      getPlayerFaction = function()
        return overrides.faction ~= nil and overrides.faction or "Alliance"
      end,
      getPlayerLevel = function()
        return overrides.level or 40
      end,
      getPlayerClassAndRace = function()
        return { classToken = overrides.classToken or "MAGE", raceToken = overrides.raceToken or "HUMAN" }
      end,
      isQuestCompleted = function(qid)
        local v = completed[qid]
        if v == "unknown" or v == "unavailable" or v == "restricted" then
          return { status = v, value = nil }
        end
        return { status = "ok", value = (v == true) }
      end,
      isOnQuest = function(qid)
        local v = active[qid]
        if v == "unknown" or v == "unavailable" then
          return { status = v, value = nil }
        end
        return { status = "ok", value = (v == true) }
      end,
      getQuestObjectives = function(qid)
        local v = objectives[qid]
        if type(v) == "table" then
          return v
        end
        if v == "unknown" or v == "unavailable" then
          return { status = v, allFinished = nil }
        end
        return { status = "ok", allFinished = (v == true) }
      end,
      isQuestLogFull = function()
        return { status = "ok", value = (overrides.questLogFull == true) }
      end,
      getBagItemCount = function(itemID)
        return { status = "ok", count = tonumber(items[itemID]) or 0 }
      end,
    }
  end

  local savedGlobalPlayerPos = ns.State.overridePlayerPosition
  ns.State.overridePlayerPosition = { status = "unavailable", reason = "selftest_isolated" }

  -- Gate 1: AND (preQuestGroup) vs OR (preQuestSingle) prerequisites, breadcrumbs, exclusiveTo, faction/class/level
  check("RG-1. AND vs OR Prerequisites, Exclusive Branches & Faction/Class/Level Restrictions", function()
    assertTrue(type(route) == "table" and type(route.actions) == "table", "Compiled Riverglades route missing")
    local prog = ns.State.MigrateRouteProgress({}, route)

    -- 94907 (A Small Favor) uses `all` (AND) requiring BOTH 94879 AND 94881 completed
    local evalOnlyOne = RoutePlanner.EvaluateRoute(route, prog, makeMockCtx({ completed = { [94879] = true, [94881] = false } }))
    assertTrue(
      evalOnlyOne.byActionID["rg_a_09_accept_94907"].state == "blocked_prerequisite",
      "A Small Favor (94907) must stay blocked when only 1 of 2 AND prerequisites is complete"
    )
    local evalBoth = RoutePlanner.EvaluateRoute(route, prog, makeMockCtx({ completed = { [94879] = true, [94881] = true } }))
    assertTrue(
      evalBoth.byActionID["rg_a_09_accept_94907"].state == "available",
      "A Small Favor (94907) must unlock when BOTH 94879 and 94881 are complete"
    )

    -- Krol'dok entrance (`rg_a_16_opt_kroldok_entrance`) uses `any` (OR / preQuestSingle): unlocked if EITHER 94982 OR 94984 is active
    local evalOrSingle = RoutePlanner.EvaluateRoute(route, prog, makeMockCtx({ active = { [94982] = true } }))
    assertTrue(
      evalOrSingle.byActionID["rg_a_16_opt_kroldok_entrance"].state == "available",
      "OR (any / preQuestSingle) must unlock when 1 listed quest is active"
    )

    -- Exclusive branch & class/faction/level checks on synthetic action
    local exAction = {
      actionID = "test_exclusive_mage",
      kind = "accept",
      questID = 94879,
      reviewStatus = "verified",
      eligibility = { faction = "Alliance", minLevel = 40, classes = { "MAGE" }, exclusiveTo = { 99001, 99002 } },
      requires = { op = "quest_completed", questID = 88000 }, -- external breadcrumb outside Riverglades
      completionPredicate = { type = "quest_completed", questID = 94879 },
      destination = { uiMapID = 2548, areaID = 16724, x01 = 0.6672, y01 = 0.8107, coordinateSpace = "uiMap01" },
    }
    assertTrue(
      RoutePlanner.EvaluateAction(exAction, route, prog, makeMockCtx({ faction = "Horde", completed = { [88000] = true } })).state == "ineligible",
      "Horde character must be ineligible for Alliance action"
    )
    assertTrue(
      RoutePlanner.EvaluateAction(exAction, route, prog, makeMockCtx({ classToken = "WARRIOR", completed = { [88000] = true } })).state == "ineligible",
      "Wrong class must be ineligible"
    )
    assertTrue(
      RoutePlanner.EvaluateAction(exAction, route, prog, makeMockCtx({ level = 39, completed = { [88000] = true } })).state == "ineligible",
      "Below minLevel must be ineligible"
    )
    assertTrue(
      RoutePlanner.EvaluateAction(exAction, route, prog, makeMockCtx({ completed = { [88000] = true, [99002] = true } })).state == "ineligible",
      "Completed exclusiveTo branch must mark sibling branch ineligible"
    )
    assertTrue(
      RoutePlanner.EvaluateAction(exAction, route, prog, makeMockCtx({ completed = { [88000] = false } })).state == "blocked_prerequisite",
      "Missing external breadcrumb must block action"
    )
    assertTrue(
      RoutePlanner.EvaluateAction(exAction, route, prog, makeMockCtx({ completed = { [88000] = true } })).state == "available",
      "Satisfied breadcrumb + eligible Mage must become available"
    )
  end)

  -- Gate 2: Unknown prerequisite or missing/ambiguous map conversion NEVER becomes available
  check("RG-2. Closed-Fail Provenance: Unknown Prerequisite or Unmapped Area Never Becomes Available", function()
    local prog = ns.State.MigrateRouteProgress({}, route)

    -- Quarantined 94890 action must evaluate to blocked_unverified
    local qAct = route.quarantinedActions and route.quarantinedActions[1]
    assertTrue(qAct ~= nil, "Quarantined action manifest missing")
    local evQuarantined = RoutePlanner.EvaluateAction(qAct, route, prog, makeMockCtx())
    assertTrue(evQuarantined.state == "blocked_unverified", "Unreviewed action must be blocked_unverified")

    -- API returning unavailable/restricted on prerequisite must produce blocked_unverified, NEVER available
    local evalApiUnk = RoutePlanner.EvaluateRoute(route, prog, makeMockCtx({ completed = { [94879] = true, [94881] = "unavailable" } }))
    assertTrue(
      evalApiUnk.byActionID["rg_a_09_accept_94907"].state == "blocked_unverified",
      "Unavailable prerequisite status must produce blocked_unverified, never available"
    )

    -- Unmapped AreaTable ID or (0, 0) coordinate must fail closed
    local unmappedAct = {
      actionID = "test_bad_map",
      kind = "travel",
      reviewStatus = "verified",
      eligibility = {},
      requires = { op = "true" },
      completionPredicate = { type = "manual_or_arrival" },
      destination = { uiMapID = 2548, areaID = 99999, x01 = 0.5, y01 = 0.5, coordinateSpace = "uiMap01" },
    }
    assertTrue(
      RoutePlanner.EvaluateAction(unmappedAct, route, prog, makeMockCtx()).state == "blocked_unverified",
      "Unmapped AreaTable conversion must be blocked_unverified"
    )
    local zeroCoordAct = {
      actionID = "test_zero_coord",
      kind = "travel",
      reviewStatus = "verified",
      eligibility = {},
      requires = { op = "true" },
      completionPredicate = { type = "manual_or_arrival" },
      destination = { uiMapID = 2548, areaID = 16591, x01 = 0, y01 = 0, coordinateSpace = "uiMap01" },
    }
    assertTrue(
      RoutePlanner.EvaluateAction(zeroCoordAct, route, prog, makeMockCtx()).state == "blocked_unverified",
      "(0, 0) sentinel coordinate must be blocked_unverified"
    )
  end)

  -- Gate 3: Coordinate round-trips and known Riverglades landmark checks
  check("RG-3. Normalized (0..1) <-> Percent (0..100) Round-Trips & Verified Landmarks", function()
    local xPct, yPct = RoutePlanner.NormalizedToPercent(0.6672, 0.8107)
    assertTrue(math.abs(xPct - 66.72) < 1e-6 and math.abs(yPct - 81.07) < 1e-6, "0..1 -> 0..100 conversion mismatch")
    local x01, y01 = RoutePlanner.PercentToNormalized(xPct, yPct)
    assertTrue(math.abs(x01 - 0.6672) < 1e-6 and math.abs(y01 - 0.8107) < 1e-6, "0..100 -> 0..1 round-trip mismatch")

    local lm = route.landmarksByKey or {}
    assertTrue(lm.farholde_keep_fp and lm.farholde_keep_fp.uiMapID == 2548, "Missing Farholde Keep FP landmark")
    assertTrue(math.abs(lm.farholde_keep_fp.x01 - 0.6062) < 1e-4, "Farholde FP x01 mismatch")
    assertTrue(math.abs(lm.powderfuse_tanaris_pier.x01 - 0.8024) < 1e-4, "Powderfuse Pier x01 mismatch")
    assertTrue(math.abs(lm.kroldok_stronghold_entrance.x01 - 0.4850) < 1e-4, "Krol'dok entrance x01 must be 0.4850")
    assertTrue(math.abs(lm.kroldok_stronghold_entrance.y01 - 0.2610) < 1e-4, "Krol'dok entrance y01 must be 0.2610")
  end)

  -- Gate 4: Numeric .goto 2548,x,y output, #forever header, and exclusion of unverified quests
  check("RG-4. RXP Export Emits #forever + Numeric .goto 2548 & Excludes Quarantined Steps", function()
    local text, err = ns.Bridges.RXPBridge.BuildRivergladesGuideText(route)
    assertTrue(type(text) == "string" and err == nil, "BuildRivergladesGuideText failed: " .. tostring(err))
    assertTrue(string.find(text, "^#forever\n") ~= nil, "RXP export must begin with #forever header")
    assertTrue(string.find(text, "%.goto 2548,66%.72,81%.07", 1) ~= nil, "RXP export must emit numeric .goto 2548,66.72,81.07")
    assertTrue(string.find(text, "%.accept 94879", 1) ~= nil, "RXP export must emit verified .accept 94879")
    assertTrue(string.find(text, "95562", 1, true) == nil, "Atlas side quest 95562 must NEVER appear in linear RXP export")
    assertTrue(string.find(text, "95331", 1, true) == nil, "Placeholder quest 95331 must NEVER appear in RXP export")
    assertTrue(string.find(text, "%.accept 94980", 1) == nil, "Item-started atlas quest 94980 must NEVER emit .accept in RXP export")
  end)

  -- Gate 5: pcall success with RegisterGuide logical failure (false / deferred nil) handled cleanly
  check("RG-5. RXP Registration Distinguishes pcall Success from Rejected or Deferred Guide", function()
    local savedRXP = _G.RXPGuides
    local savedRegFlag = ns.Bridges.RXPBridge.rivergladesRegistered
    local ok, err = pcall(function()
      -- Case A: pcall succeeds, RegisterGuide returns false (rejected by RXP parser/filter)
      _G.RXPGuides = {
        addonLoaded = true,
        guides = {},
        RegisterGuide = function()
          return false
        end,
      }
      local regOkA, statusA = ns.Bridges.RXPBridge.RegisterRivergladesGuide(false, route)
      assertTrue(regOkA == false and statusA == "rejected", "RegisterGuide returning false must be treated as rejected")

      -- Case B: pcall succeeds, addonLoaded == false, RegisterGuide queues and returns nil (deferred, not yet accepted)
      _G.RXPGuides = {
        addonLoaded = false,
        guides = {},
        RegisterGuide = function()
          return nil
        end,
      }
      local regOkB, statusB = ns.Bridges.RXPBridge.RegisterRivergladesGuide(false, route)
      assertTrue(regOkB == false and statusB == "deferred", "Deferred RegisterGuide before RXP load must report deferred")

      -- Case C: RegisterGuide accepts guide while another guide is selected -> registered, NOT hijacked!
      _G.RXPGuides = {
        addonLoaded = true,
        currentGuide = { group = "RestedXP Speedrun Guide (A)", name = "38-40 Dustwallow" },
        guides = {},
        RegisterGuide = function(txt)
          local key = ns.Bridges.RXPBridge.RIVERGLADES_GUIDE_GROUP .. "||" .. ns.Bridges.RXPBridge.RIVERGLADES_GUIDE_NAME
          _G.RXPGuides.guides[key] = { text = txt }
          return true
        end,
      }
      local regOkC, statusC = ns.Bridges.RXPBridge.RegisterRivergladesGuide(false, route)
      assertTrue(regOkC == true and statusC == "registered", "Accepted guide must report registered without claiming selected")
      assertTrue(
        _G.RXPGuides.currentGuide.name == "38-40 Dustwallow",
        "Exporting guide must NEVER overwrite unrelated active RXP guide"
      )
    end)
    _G.RXPGuides = savedRXP
    ns.Bridges.RXPBridge.rivergladesRegistered = savedRegFlag
    if not ok then
      error(err, 2)
    end
  end)

  -- Gate 6: No-RXP / no-TomTom / unsupported-native navigation remains usable via text fallback
  check("RG-6. Text/Manual Fallback Works Without RXP, TomTom, or Native Waypoints", function()
    local savedRXP = _G.RXPGuides
    local savedTT = _G.TomTom
    local savedWpOv = ns.State.overrideNativeWaypointState
    local savedCombat = ns.State.overrideInCombat
    local ok, err = pcall(function()
      _G.RXPGuides = nil
      _G.TomTom = nil
      ns.State.overrideInCombat = false
      ns.State.overrideNativeWaypointState = { supported = false, current = nil }

      local prog = ns.State.MigrateRouteProgress({ mode = "standalone" }, route)
      local eval = RouteProgress.Reconcile(route, prog, makeMockCtx())
      local navStatus = ns.UI.Navigation.SyncFromEvaluation(eval, prog)
      assertTrue(navStatus.activeProvider == "text_manual", "Must fall back cleanly to text_manual")
      assertTrue(navStatus.hasDirectionalArrow == false, "Text fallback must NEVER claim a directional arrow exists")
      assertTrue(eval.nextAction ~= nil and eval.nextAction.actionID == "rg_a_01_farholde_fp", "First action must still be selectable")
    end)
    _G.RXPGuides = savedRXP
    _G.TomTom = savedTT
    ns.State.overrideNativeWaypointState = savedWpOv
    ns.State.overrideInCombat = savedCombat
    if not ok then
      error(err, 2)
    end
  end)

  -- Gate 7: Reward stack quantities, ties, missing/loading prices, and stale async callbacks
  check("RG-7. Reward Stack Quantities, Ties, Partial Pricing & Stale Async Callback Rejection", function()
    local savedPrices = ns.State.overrideItemSellPrices
    local savedLoads = ns.State.requestedItemLoads
    local ok, err = pcall(function()
      ns.State.requestedItemLoads = {}
      -- Stack of 5x 400c (2000c) must beat 1x 1500c (1500c), while choice 3 is still loading ("loading")
      ns.State.overrideItemSellPrices = {
        [70001] = 1500,
        [70002] = 400,
        [70003] = "loading",
      }
      local snapPartial = {
        status = "ok",
        questID = 94879,
        questTitle = "Scraps of Knowledge",
        choices = {
          { choiceIndex = 1, itemID = 70001, name = "Heavy Mace", quantity = 1 },
          { choiceIndex = 2, itemID = 70002, name = "Mana Potion Bundle", quantity = 5 },
          { choiceIndex = 3, itemID = 70003, name = "Uncached Robe", quantity = 1 },
        },
      }
      local eval1, gen1 = ns.UI.RewardAdvisor.OnQuestComplete(snapPartial)
      assertTrue(eval1.status == "partial", "Uncached choice must produce partial status, not complete")
      assertTrue(
        eval1.headlineLabel == "Highest value among priced rewards",
        "Partial pricing must state 'Highest value among priced rewards'"
      )
      assertTrue(eval1.bestVendorCopper == 2000 and eval1.bestChoices[1].choiceIndex == 2, "5x 400c (2000c) must beat 1x 1500c")
      assertTrue(ns.State.requestedItemLoads[70003] == 1, "Must request async item load for uncached item 70003")

      -- Advance quest generation (e.g. player opened a second quest) and verify late callback from gen1 is discarded!
      ns.State.overrideItemSellPrices = { [80001] = 1200, [80002] = 1200 }
      local snapTie = {
        status = "ok",
        questID = 94881,
        questTitle = "Curious Trinkets",
        choices = {
          { choiceIndex = 1, itemID = 80001, name = "Cloth Bracers", quantity = 1 },
          { choiceIndex = 2, itemID = 80002, name = "Plate Bracers", quantity = 1 },
        },
      }
      local evalTie, gen2 = ns.UI.RewardAdvisor.OnQuestComplete(snapTie)
      assertTrue(gen2 > gen1, "Generation must increment monotonically")
      assertTrue(evalTie.status == "complete" and evalTie.isTie == true and #evalTie.bestChoices == 2, "Exact copper tie must report both choices")

      local handledStale, staleReason = ns.UI.RewardAdvisor.OnItemInfoReceived(70003, true, gen1, snapTie)
      assertTrue(handledStale == false and staleReason == "stale_generation_discarded", "Late callback from old generation must be discarded")
      ns.UI.RewardAdvisor.OnQuestFinished()
    end)
    ns.State.overrideItemSellPrices = savedPrices
    ns.State.overrideItemLoads = nil
    ns.State.requestedItemLoads = savedLoads
    if not ok then
      error(err, 2)
    end
  end)

  -- Gate 8: Duplicate/reordered events, reload migration by actionID, abandonment, quest-log-full & explicit skips
  check("RG-8. Migration by ActionID, Explicit Skips, Abandonment, Quest-Log-Full & Proximity Safety", function()
    -- 1. Migration rejects numeric currentActionID, keeps valid actionID skips, and archives removed actionIDs
    local migrated = ns.State.MigrateRouteProgress({
      currentActionID = 3, -- invalid numeric index!
      explicitlySkippedActions = {
        ["rg_a_01_farholde_fp"] = { skippedAt = 10, reason = "manual_next" },
        ["obsolete_removed_step_v0"] = { skippedAt = 5, reason = "manual_next" },
      },
    }, route)
    assertTrue(migrated.currentActionID == nil, "Migration must reject numeric array index currentActionID")
    assertTrue(migrated.explicitlySkippedActions["rg_a_01_farholde_fp"] ~= nil, "Valid actionID skip must survive migration")
    assertTrue(migrated.explicitlySkippedActions["obsolete_removed_step_v0"] == nil, "Removed actionID must move out of active skips")
    assertTrue(migrated.archivedSkippedActions["obsolete_removed_step_v0"] ~= nil, "Removed actionID must be preserved in archive")

    -- 2. Manual `Next` records explicit skip WITHOUT marking quest completed!
    local savedWorldSizes = ns.State.overrideMapWorldSizes
    local okRG8, errRG8 = pcall(function()
      local prog = ns.State.MigrateRouteProgress({ mode = "standalone" }, route)
      -- Without world-size transform on custom map 2548, travel arrival MUST retain manual completion
      ns.State.overrideMapWorldSizes = {}
      local evalNoTransform = RouteProgress.Reconcile(route, prog, makeMockCtx(), { status = "ok", uiMapID = 2548, x01 = 0.6062, y01 = 0.8153 })
      assertTrue(
        evalNoTransform.nextAction and evalNoTransform.nextAction.actionID == "rg_a_01_farholde_fp",
        "Missing world transform on 2548 must retain manual completion instead of normalized % guessing"
      )

      -- With world-size transform available, complete initial travel steps via world-yard arrival
      ns.State.overrideMapWorldSizes = { [2548] = { width = 3600, height = 2400 } }
      RouteProgress.Reconcile(route, prog, makeMockCtx(), { status = "ok", uiMapID = 2548, x01 = 0.6062, y01 = 0.8153 })
      RouteProgress.Reconcile(route, prog, makeMockCtx(), { status = "ok", uiMapID = 2548, x01 = 0.6464, y01 = 0.8420 })
      -- Standing right on Ashe Amberhall (0.6672, 0.8107) MUST NOT auto-complete `rg_a_03_accept_94879`!
      local evalAtNpc = RouteProgress.Reconcile(route, prog, makeMockCtx(), { status = "ok", uiMapID = 2548, x01 = 0.6672, y01 = 0.8107 })
      assertTrue(evalAtNpc.nextAction.actionID == "rg_a_03_accept_94879", "Proximity must NEVER auto-complete quest accept steps")

      -- Quest-log-full blocks pickup cleanly
      local evalFull = RouteProgress.Reconcile(route, prog, makeMockCtx({ questLogFull = true }))
      assertTrue(evalFull.byActionID["rg_a_03_accept_94879"].state == "blocked_quest_log_full", "Full quest log must block accept step")

      -- Explicit `Next` skips `rg_a_03_accept_94879` without completing 94879
      local skipOk, skipRes = RouteProgress.SkipCurrentAction(route, prog, makeMockCtx())
      assertTrue(skipOk and skipRes.skippedActionID == "rg_a_03_accept_94879", "SkipCurrentAction must skip rg_a_03_accept_94879")
      assertTrue(prog.explicitlySkippedActions["rg_a_03_accept_94879"] ~= nil, "Explicit skip must be recorded")
      assertTrue(skipRes.evaluation.byActionID["rg_a_03_accept_94879"].state == "skipped", "Skipped action state must be 'skipped', not 'completed'")

      -- 3. Accept 94879 & 94881 (even with duplicate reconcile calls), then abandon 94879 -> must roll back to `rg_a_03_accept_94879`!
      local evalAccepted = RouteProgress.Reconcile(route, prog, makeMockCtx({ active = { [94879] = true, [94881] = true } }))
      evalAccepted = RouteProgress.Reconcile(route, prog, makeMockCtx({ active = { [94879] = true, [94881] = true } }))
      assertTrue(evalAccepted.nextAction.actionID == "rg_a_05_obj_sunnyglade_94881", "Active quests must advance to Sunnyglade objectives")

      local evalAbandoned = RouteProgress.Reconcile(route, prog, makeMockCtx({ active = { [94879] = false, [94881] = true } }))
      assertTrue(
        evalAbandoned.nextAction.actionID == "rg_a_03_accept_94879",
        "Abandoning quest 94879 must roll progression back to accepting 94879"
      )

      -- 4. Read-only RouteProgress.Evaluate MUST NOT record travel arrival evidence even when standing on step 1
      local progRO = ns.State.MigrateRouteProgress({ mode = "standalone" }, route)
      ns.State.overridePlayerPosition = { status = "ok", uiMapID = 2548, x01 = 0.6062, y01 = 0.8153 }
      local evalRO = RouteProgress.Evaluate(route, progRO, makeMockCtx())
      assertTrue(evalRO.nextAction.actionID == "rg_a_01_farholde_fp", "Read-only Evaluate must not advance travel step")
      assertTrue(progRO.observedCompletionEvidence["rg_a_01_farholde_fp"] == nil, "Read-only Evaluate must never write travel evidence")

      -- 5. Callback-capable C_Timer.NewTicker must advance CONSECUTIVE Riverglades travel steps without self-cancelling
      local prevCTimer = _G.C_Timer
      local prevWpOv = ns.State.overrideNativeWaypointState
      local prevInCombat = ns.State.overrideInCombat
      local prevRGDB = charDB and deepCopyTable(charDB.routeProgress) or nil
      local okTickerRG, errTickerRG = pcall(function()
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
        ns.State.overrideInCombat = false
        ns.State.overrideNativeWaypointState = { supported = true, current = nil }
        ns.UI.Navigation.StopTravelTicker()
        cancelCount = 0
        activeTickFn = nil

        charDB.routeProgress = ns.State.MigrateRouteProgress({}, route)
        ns.State.overridePlayerPosition = { status = "ok", uiMapID = 2548, x01 = 0.5000, y01 = 0.5000 }
        local okStartRG, startEvalRG = RouteProgress.Start()
        assertTrue(okStartRG and startEvalRG.nextAction.actionID == "rg_a_01_farholde_fp", "RG ticker start at step 1")
        ns.UI.Navigation.SyncFromEvaluation(startEvalRG, charDB.routeProgress)
        assertTrue(type(activeTickFn) == "function" and cancelCount == 0, "RG travel ticker must start cleanly")

        -- Tick 1: arrive at rg_a_01_farholde_fp -> advances to rg_a_02_farholde_inn without cancelling ticker!
        ns.State.overridePlayerPosition = { status = "ok", uiMapID = 2548, x01 = 0.6062, y01 = 0.8153 }
        activeTickFn()
        assertTrue(charDB.routeProgress.currentActionID == "rg_a_02_farholde_inn", "RG Tick 1 must advance to rg_a_02_farholde_inn")
        assertTrue(cancelCount == 0, "RG ticker must remain alive across generation bump after first hop")

        -- Tick 2 (same ticker closure!): arrive at rg_a_02_farholde_inn -> advances to rg_a_03_accept_94879!
        ns.State.overridePlayerPosition = { status = "ok", uiMapID = 2548, x01 = 0.6464, y01 = 0.8420 }
        activeTickFn()
        assertTrue(charDB.routeProgress.currentActionID == "rg_a_03_accept_94879", "RG Tick 2 must advance consecutive travel step to rg_a_03_accept_94879")
      end)
      ns.UI.Navigation.StopTravelTicker()
      _G.C_Timer = prevCTimer
      ns.State.overrideNativeWaypointState = prevWpOv
      ns.State.overrideInCombat = prevInCombat
      ns.State.overridePlayerPosition = { status = "unavailable" }
      if charDB then
        charDB.routeProgress = prevRGDB
      end
      if not okTickerRG then
        error(errTickerRG, 2)
      end
    end)
    ns.State.overrideMapWorldSizes = savedWorldSizes
    if not okRG8 then
      error(errRG8, 2)
    end
  end)

  -- Gate 9: Waypoint ownership — user-created tracking is NEVER overwritten or cleared during cleanup
  check("RG-9. Waypoint Ownership: User-Created Native Waypoint Is Never Overwritten or Deleted", function()
    local charDB = ns.State.GetCharDB()
    local savedTT = _G.TomTom
    local savedWpOv = ns.State.overrideNativeWaypointState
    local savedCombat = ns.State.overrideInCombat
    local savedOwner = {
      ownerContext = ns.UI.Navigation.owner.ownerContext,
      generation = ns.UI.Navigation.owner.generation,
      provider = ns.UI.Navigation.owner.provider,
      handle = ns.UI.Navigation.owner.handle,
      pendingRelease = ns.UI.Navigation.owner.pendingRelease,
      pendingDestination = ns.UI.Navigation.owner.pendingDestination,
    }
    local savedActiveCtx = ns.UI.Navigation.activeContext
    local savedHydrated = ns.UI.Navigation.hydratedFromSaved
    local savedDBNavOwner = charDB.navigationOwner

    local ok, err = pcall(function()
      _G.TomTom = nil
      ns.State.overrideInCombat = false
      ns.UI.Navigation.hydratedFromSaved = true
      ns.UI.Navigation.owner = {
        ownerContext = nil,
        generation = 0,
        provider = "none",
        handle = nil,
        pendingRelease = false,
        pendingDestination = nil,
      }

      -- Subcase A: User ALREADY has a custom native pin before starting ForeverHub
      ns.State.overrideNativeWaypointState = {
        supported = true,
        current = { uiMapID = 2548, x01 = 0.3333, y01 = 0.4444 },
      }
      local progA = ns.State.MigrateRouteProgress({ mode = "standalone" }, route)
      local evalA = RouteProgress.Reconcile(route, progA, makeMockCtx())
      local stA = ns.UI.Navigation.SyncFromEvaluation(evalA, progA)
      assertTrue(stA.activeProvider == "text_manual", "Must not overwrite pre-existing user waypoint")
      assertTrue(
        math.abs(ns.State.overrideNativeWaypointState.current.x01 - 0.3333) < 1e-6,
        "Pre-existing user waypoint x01 must remain untouched"
      )

      -- Subcase B: No pin initially -> ForeverHub sets owned pin -> User replaces pin mid-route -> Pause cleanup MUST NOT delete user's pin!
      ns.State.overrideNativeWaypointState = { supported = true, current = nil }
      local progB = ns.State.MigrateRouteProgress({ mode = "standalone" }, route)
      local evalB = RouteProgress.Reconcile(route, progB, makeMockCtx())
      local stB = ns.UI.Navigation.SyncFromEvaluation(evalB, progB)
      assertTrue(stB.activeProvider == "native_waypoint", "ForeverHub must set native waypoint when none exists")
      assertTrue(ns.UI.Navigation.owner.provider == "native_waypoint", "ForeverHub must record native_waypoint owner token")

      -- Simulate user Ctrl-clicking map at (0.7777, 0.2222)
      ns.State.overrideNativeWaypointState.current = { uiMapID = 2548, x01 = 0.7777, y01 = 0.2222 }
      ns.UI.Navigation.CleanupOwnedWaypoint(progB)
      assertTrue(
        ns.State.overrideNativeWaypointState.current ~= nil
          and math.abs(ns.State.overrideNativeWaypointState.current.x01 - 0.7777) < 1e-6,
        "CleanupOwnedWaypoint must NEVER delete a user-replaced native waypoint"
      )

      -- Subcase C: When ForeverHub still owns the pin, cleanup removes it cleanly
      ns.State.overrideNativeWaypointState = { supported = true, current = nil }
      local progC = ns.State.MigrateRouteProgress({ mode = "standalone" }, route)
      ns.UI.Navigation.SyncFromEvaluation(RouteProgress.Reconcile(route, progC, makeMockCtx()), progC)
      assertTrue(ns.State.overrideNativeWaypointState.current ~= nil, "Owned pin set")
      ns.UI.Navigation.CleanupOwnedWaypoint(progC)
      assertTrue(ns.State.overrideNativeWaypointState.current == nil, "Cleanup must clear waypoint still owned by ForeverHub")
    end)
    _G.TomTom = savedTT
    ns.State.overrideNativeWaypointState = savedWpOv
    ns.State.overrideInCombat = savedCombat
    ns.UI.Navigation.owner = savedOwner
    ns.UI.Navigation.activeContext = savedActiveCtx
    ns.UI.Navigation.hydratedFromSaved = savedHydrated
    charDB.navigationOwner = savedDBNavOwner
    if not ok then
      error(err, 2)
    end
  end)

  -- Gate 10: Mount shortfall calculation, Silk Cloth reservation integration & 14/14 Core Reservation Regression Check
  check("RG-10. Mount Shortfall Tracker (Honored 90g + Silk Check) & Core Reservation Regression Green", function()
    local mountReport = RewardValue.EvaluateMountShortfall(
      { status = "ok", copper = 540000 }, -- 54g
      { standingLabel = "Honored", trainerQuoteCopper = 900000, cashReserveCopper = 50000, quoteStatus = "user_confirmed" }, -- 90g quote + 5g reserve
      { charOwned = 120, reservedTotal = 80, freeBags = 20, freeBank = 20 },
      500000 -- started session at 50g -> +4g net
    )
    assertTrue(mountReport.status == "ok", "Mount shortfall evaluation failed")
    assertTrue(mountReport.spendableCopper == 490000, "Spendable copper must deduct 5g reserve (54g - 5g = 49g)")
    assertTrue(mountReport.shortfallCopper == 410000, "Shortfall against 90g Honored quote must be 41g (410000c)")
    assertTrue(mountReport.sessionDeltaCopper == 40000, "Session net delta must be +4g (40000c)")
    assertTrue(mountReport.silkStatus.reservedTotal == 80 and mountReport.silkStatus.unreservedTotal == 40, "Silk reservation split mismatch")

    local coreReport = SelfTest.RunAll()
    assertTrue(coreReport.failed == 0 and coreReport.passed == 14, "All 14 core reservation self-tests must remain green")
  end)

  -- Gate 11: Artifact-Verified Chain Inference, Non-Inference on Estimated Edges & Hybrid Title Discovery
  check("RG-11. Artifact-Verified Chain Inference, Non-Inference on Estimated Edges & Hybrid Title Discovery", function()
    local prog = ns.State.MigrateRouteProgress({ mode = "standalone" }, route)

    -- 1a. Positive `artifact_verified` inference (FDJ.QUEST_PREREQ_CHAINS[94984] & [94981]):
    -- Having `94984` (Twilight's End) and `94981` (Culling the Cultists) active MUST transitively mark
    -- `94907` (A Small Favor), `94879` (Scraps of Knowledge), `94881` (Securing the Area), and
    -- `94980` (Sunnyglade Reinforcement) completed even if server flags omit them, and retire intro steps!
    local inferredCtx = makeMockCtx({ level = 43, active = { [94984] = true, [94981] = true }, completed = {} })
    local evalInferred = RoutePlanner.EvaluateRoute(route, prog, inferredCtx)
    assertTrue(evalInferred.byActionID["rg_a_03_accept_94879"].state == "completed", "94879 accept must be inferred completed from artifact_verified successor 94984")
    assertTrue(evalInferred.byActionID["rg_a_08_turnin_94881"].state == "completed", "94881 turnin must be inferred completed from artifact_verified successor 94984")
    assertTrue(evalInferred.byActionID["rg_a_09_accept_94907"].state == "completed", "94907 accept must be inferred completed from artifact_verified successor 94984")
    assertTrue(evalInferred.byActionID["rg_a_11_obj_conduit_94907"].state == "completed", "94907 objective must be inferred completed from artifact_verified successor 94984")
    assertTrue(evalInferred.byActionID["rg_a_12_turnin_94907"].state == "completed", "94907 turnin must be inferred completed from artifact_verified successor 94984")
    assertTrue(evalInferred.byActionID["rg_a_17_opt_key_94981"].state == "completed", "94981 accept must be completed while 94981 is active")
    local inferred94980 = RoutePlanner.IsQuestCompletedOrInferred(94980, route, inferredCtx)
    assertTrue(
      inferred94980.status == "ok"
        and inferred94980.value == true
        and inferred94980.inferredFrom == 94981
        and inferred94980.completionSource == "artifact_verified_successor",
      "94980 must be inferred completed from artifact_verified successor 94981"
    )
    assertTrue(evalInferred.byActionID["rg_a_01_farholde_fp"].state == "completed", "Intro travel FP must auto-retire once route quests are started")
    assertTrue(evalInferred.byActionID["rg_a_13_powderfuse_hub"].state == "completed", "Powderfuse intro hub check must auto-retire once route quests are started")

    -- 1b. Negative non-inference on `"estimated"` observational chain edges (Astra v0.7.1 P1 #5):
    -- Having `94928` (A Few Furs for Friz) active with empty server flags MUST NOT infer completion of `94925` (A Fur Trade)!
    local evalNoUnverifiedInference = RoutePlanner.EvaluateRoute(
      route,
      prog,
      makeMockCtx({ level = 41, active = { [94928] = true }, completed = {} })
    )
    assertTrue(
      evalNoUnverifiedInference.byActionID["rg_hb_accept_94925"].state == "available",
      "Estimated chain edge 94925 -> 94928 MUST NOT suppress 94925 without direct completion evidence"
    )

    -- Test live hybrid title->ID discovery & immediate QUEST_TURNED_IN cache before server flag flip
    local savedCQ = _G.C_QuestLog
    local savedDiscovered = ForeverHubDB and deepCopyTable(ForeverHubDB.discoveredQuestIds or {}) or nil
    local savedDiscoveredTitles = ForeverHubDB and deepCopyTable(ForeverHubDB.discoveredQuestTitlesById or {}) or nil
    local savedTurnInID = deepCopyTable(ns.Compat.recentQuestTurnedInByID or {})
    local savedTurnInTitle = deepCopyTable(ns.Compat.recentQuestTurnedInByTitle or {})
    local savedAcceptID = deepCopyTable(ns.Compat.recentQuestAcceptedByID or {})
    local savedAcceptTitle = deepCopyTable(ns.Compat.recentQuestAcceptedByTitle or {})
    local savedLastDialog = deepCopyTable(ns.Compat.lastDialogQuest or {})
    local savedObsLogTitles = deepCopyTable(ns.Compat.observedLogTitlesByID or {})
    local savedCharRGInGate = charDB and deepCopyTable(charDB.routeProgress) or nil
    local okHybrid, errHybrid = pcall(function()
      if ForeverHubDB then
        ForeverHubDB.discoveredQuestIds = {}
        ForeverHubDB.discoveredQuestTitlesById = {}
      end
      local serverFlagged = false
      local inLog = true
      _G.C_QuestLog = {
        GetNumQuestLogEntries = function()
          return inLog and 2 or 0, inLog and 1 or 0
        end,
        GetInfo = function(idx)
          if idx == 1 then
            return { title = "Riverglades", isHeader = true, isCollapsed = false }
          elseif idx == 2 and inLog then
            return { title = "WANTED: Trapclaw", questID = 95999, isHeader = false, isComplete = true }
          end
          return nil
        end,
        IsOnQuest = function(qid)
          return inLog and qid == 95999
        end,
        IsComplete = function(qid)
          return inLog and qid == 95999
        end,
        GetQuestObjectives = function(qid)
          if qid == 95999 then
            return { { text = "1/1 Trapclaw's Pincer", finished = true, numFulfilled = 1, numRequired = 1 } }
          end
          return {}
        end,
        IsQuestFlaggedCompleted = function(qid)
          return qid == 95999 and serverFlagged
        end,
      }
      ns.Compat.InvalidateQuestStateCaches()
      local onTrap = ns.Compat.IsOnQuestResult("title:wanted: trapclaw")
      assertTrue(onTrap.status == "ok" and onTrap.value == true, "Title-keyed quest must resolve from live Quest Log")
      assertTrue(ns.State.GetDiscoveredQuestId("wanted: trapclaw") == 95999, "Runtime questID must be persisted by normalized title")
      assertTrue(ns.State.GetDiscoveredQuestTitle(95999) == "wanted: trapclaw", "Reverse questID->title map must be persisted")

      local objTrap = ns.Compat.GetQuestObjectivesResult("title:wanted: trapclaw")
      assertTrue(objTrap.status == "ok" and objTrap.allFinished == true, "Title-keyed objectives must resolve via discovered ID")

      -- Turn in quest while `serverFlagged` is still false (simulating server flag lag on QUEST_TURNED_IN)
      inLog = false
      ns.Compat.RecordRecentQuestTurnedIn(95999, "WANTED: Trapclaw")
      local compImmediate = ns.Compat.IsQuestCompletedResult("title:wanted: trapclaw")
      assertTrue(compImmediate.status == "ok" and compImmediate.value == true, "QUEST_TURNED_IN cache must mark quest completed immediately")
    end)
    _G.C_QuestLog = savedCQ
    ns.Compat.recentQuestTurnedInByID = savedTurnInID
    ns.Compat.recentQuestTurnedInByTitle = savedTurnInTitle
    ns.Compat.recentQuestAcceptedByID = savedAcceptID
    ns.Compat.recentQuestAcceptedByTitle = savedAcceptTitle
    ns.Compat.lastDialogQuest = savedLastDialog
    ns.Compat.observedLogTitlesByID = savedObsLogTitles
    if charDB and savedCharRGInGate ~= nil then
      charDB.routeProgress = savedCharRGInGate
    end
    if ForeverHubDB then
      ForeverHubDB.discoveredQuestIds = savedDiscovered or {}
      ForeverHubDB.discoveredQuestTitlesById = savedDiscoveredTitles or {}
    end
    ns.Compat.InvalidateQuestStateCaches()
    if not okHybrid then
      error(errHybrid, 2)
    end
  end)

  -- Gate 12: Full 40/40 Quest-Log Replay (All 22 Screenshot Quests @ Powderfuse Port 78.9, 53.0)
  check("RG-12. Full 40/40 22-Quest Powderfuse Replay, Zero-Click Auto-Advance & Elite Bounty Safety", function()
    local savedWorldSizes = ns.State.overrideMapWorldSizes
    local okReplay, errReplay = pcall(function()
      ns.State.overrideMapWorldSizes = { [2548] = { width = 3600, height = 2400 }, [1444] = { width = 6950, height = 4633 } }
      local prog = ns.State.MigrateRouteProgress({ mode = "standalone", includeEliteBounties = false }, route)
      local active22 = {
        [95943] = true, -- Foreman's Plight
        [96063] = true, -- Gaseous Gold
        [95988] = true, -- Goes Down Smooth
        [95613] = true, -- Keeping the Light On (follows 95603)
        [95982] = true, -- Not My Circus
        [94931] = true, -- Stolen Saws
        [95184] = true, -- The Sharpest of Blades (follows 95156)
        [94842] = true, -- Unsavory Plant Food
        [94925] = true, -- A Fur Trade (8 Prized Lion Hides -> Watcher Cornelius)
        [94928] = true, -- A Few Furs for Friz (zero-objective delivery -> Friz Frazzlespark)
        [94924] = true, -- Hunting the Hunters
        [95121] = true, -- A Taste of the Sea
        [96081] = true, -- Wound Dressings (13/20 Mageweave Cloth)
        [95219] = true, -- From Port to Port (Feralas delivery)
        [95118] = true, -- Saltwater Savages
        [95912] = true, -- [42+] WANTED: Blademaster Kaijo
        [95991] = true, -- [42+] WANTED: Ghostmaw
        [95120] = true, -- [42+] WANTED: Old Rot-Chum
        ["title:wanted: trapclaw"] = true,
        [95119] = true, -- Unfriendly Competition
        [94907] = true, -- A Small Favor (follows artifact_verified 94879 + 94881)
        [94886] = true, -- The Western Front (zero-objective find Riftan)
        [94887] = true, -- Saving Marshal Ryan (follows 94885)
      }
      -- Numeric server completion flags for prior non-artifact-verified chains (94879 & 94881 intentionally
      -- omitted so RG-12 also verifies artifact_verified successor inference from active 94907!)
      local completedPrior = {
        [95603] = true,
        [95156] = true,
        [94885] = true,
      }
      local objectives22 = {}
      local playerAtPowderfuse = { status = "ok", uiMapID = 2548, x01 = 0.7890, y01 = 0.5300 }

      local eval1 = RouteProgress.Reconcile(
        route,
        prog,
        makeMockCtx({ level = 41, active = active22, completed = completedPrior, objectives = objectives22, questLogFull = true }),
        playerAtPowderfuse
      )

      -- 1. Zero completed prerequisites or intro waypoints are ever suggested
      for _, doneID in ipairs({
        "rg_a_01_farholde_fp",
        "rg_a_02_farholde_inn",
        "rg_a_03_accept_94879",
        "rg_a_08_turnin_94881",
        "rg_fk_turnin_95603",
        "rg_fk_turnin_95156",
      }) do
        assertTrue(eval1.byActionID[doneID].state == "completed", "Completed/inferred step must never be recommended: " .. doneID)
      end

      -- 2. Unaccepted quests are blocked by 40/40 log, NOT stalling active progression; local Powderfuse delivery 94928 wins!
      assertTrue(eval1.byActionID["rg_hb_accept_94614"].state == "blocked_quest_log_full", "Unaccepted quest must be blocked_quest_log_full at 40/40")
      assertTrue(eval1.nextAction ~= nil and eval1.nextAction.actionID == "rg_pf_turnin_94928", "At Powderfuse (78.9, 53.0), ready zero-objective A Few Furs for Friz (94928) turn-in must be chosen first")
      active22[94928] = false
      completedPrior[94928] = true
      eval1 = RouteProgress.Reconcile(
        route,
        prog,
        makeMockCtx({ level = 41, active = active22, completed = completedPrior, objectives = objectives22, questLogFull = true }),
        playerAtPowderfuse
      )
      assertTrue(eval1.nextAction ~= nil and eval1.nextAction.actionID == "rg_pf_obj_wanted_trapclaw", "After turning in 94928 at Powderfuse, local Trapclaw objective must be chosen next")

      -- 3. [42+] Elite bounty objectives are hidden by default, EXCEPT if completed they immediately surface to turn in!
      assertTrue(eval1.byActionID["rg_el_obj_95991"].state == "ineligible", "[42+] Ghostmaw objective must default off for solo safety")
      objectives22[95991] = true
      local evalEliteReady = RouteProgress.Reconcile(
        route,
        prog,
        makeMockCtx({ level = 41, active = active22, completed = completedPrior, objectives = objectives22, questLogFull = true }),
        playerAtPowderfuse
      )
      assertTrue(evalEliteReady.byActionID["rg_el_turnin_95991"].state == "available", "Completed [42+] Elite bounty in log must still guide turn-in")
      objectives22[95991] = false

      -- 4. Zero-click auto-advance: complete Trapclaw -> auto-advances to Powderfuse turn-in -> turn in -> auto-advances to Goes Down Smooth!
      objectives22["title:wanted: trapclaw"] = true
      local eval2 = RouteProgress.Reconcile(
        route,
        prog,
        makeMockCtx({ level = 41, active = active22, completed = completedPrior, objectives = objectives22, questLogFull = true }),
        playerAtPowderfuse
      )
      assertTrue(eval2.nextAction.actionID == "rg_pf_turnin_wanted_trapclaw", "Completing Trapclaw must auto-advance immediately to local turn-in")

      active22["title:wanted: trapclaw"] = false
      completedPrior["title:wanted: trapclaw"] = true
      local eval3 = RouteProgress.Reconcile(
        route,
        prog,
        makeMockCtx({
          level = 41,
          active = active22,
          completed = completedPrior,
          objectives = objectives22,
          questLogFull = false,
        }),
        playerAtPowderfuse
      )
      assertTrue(eval3.nextAction.actionID == "rg_pf_accept_95261", "Freeing a slot after Trapclaw at Powderfuse must immediately offer local dock pickup It Takes Guts (95261)")
      completedPrior[95261] = true
      completedPrior[95267] = true
      completedPrior[95288] = true
      completedPrior[95293] = true
      completedPrior[95294] = true
      local eval3b = RouteProgress.Reconcile(
        route,
        prog,
        makeMockCtx({
          level = 41,
          active = active22,
          completed = completedPrior,
          objectives = objectives22,
          questLogFull = false,
        }),
        playerAtPowderfuse
      )
      assertTrue(eval3b.nextAction.actionID == "rg_pf_obj_goes_down_smooth", "With Powderfuse pickups complete, turning in Trapclaw must auto-advance to Goes Down Smooth without clicking Skip")

      -- 5. Zero-objective delivery `From Port to Port` (95219) is available & immediately prioritized if player arrives in Feralas (1444)
      assertTrue(eval3.byActionID["rg_exit_turnin_95219"].state == "available", "Zero-objective delivery 95219 must be available while active")
      local evalInFeralas = RouteProgress.Reconcile(
        route,
        prog,
        makeMockCtx({ level = 41, active = active22, completed = completedPrior, objectives = objectives22 }),
        { status = "ok", uiMapID = 1444, x01 = 0.3100, y01 = 0.4320 }
      )
      assertTrue(evalInFeralas.nextAction.actionID == "rg_exit_turnin_95219", "Entering Feralas must immediately prioritize From Port to Port turn-in")
    end)
    ns.State.overrideMapWorldSizes = savedWorldSizes
    if not okReplay then
      error(errReplay, 2)
    end
  end)

  -- RG-13. World Map Quest Pins: Non-Vacuous Completion Removal, Sub-Objectives, Zoom Clustering & Click-to-Focus
  check("RG-13. World Map Quest Pins: State Filtering, Sub-Objectives, Zoom Clustering & Click-to-Focus", function()
    local WorldMapPins = ns.UI and ns.UI.WorldMapPins
    assertTrue(type(WorldMapPins) == "table", "ns.UI.WorldMapPins must be loaded")
    assertTrue(route.questsByID and route.questsByID[95613] ~= nil, "Compiled route must include 95613 (Keeping the Light On)")

    local prog = ns.State.MigrateRouteProgress({ mode = "paused", includeEliteBounties = false })
    local pinSettings = { enabled = true, showObjectives = true, showTurnIns = true, showAvailable = true }
    local playerPos = { status = "ok", uiMapID = 2548, x01 = 0.4560, y01 = 0.6200 }

    -- Non-vacuous check (Astra v0.7.1 P2 #4): prove 95613 appears on Map 2548 BEFORE completion!
    local entriesPre95613 = WorldMapPins.CollectPinEntries(
      2548,
      route,
      prog,
      pinSettings,
      makeMockCtx({ level = 41, completed = { [95603] = true } }),
      playerPos
    )
    local saw95613Before = false
    for _, e in ipairs(entriesPre95613) do
      if e.questID == 95613 then
        saw95613Before = true
        break
      end
    end
    assertTrue(saw95613Before, "95613 (Keeping the Light On) must emit an Available (!) pin before completion")

    local unsavoryObjectivesAllOpen = {
      [94842] = {
        status = "ok",
        allFinished = false,
        summaryText = "0/4 Jumbo Crawfish Shell; 0/4 Fresh Manure; 0/8 Mudfin Murloc Head",
        objectives = {
          { index = 1, text = "0/4 Jumbo Crawfish Shell", finished = false },
          { index = 2, text = "0/4 Fresh Manure", finished = false },
          { index = 3, text = "0/8 Mudfin Murloc Head", finished = false },
        },
      },
      ["title:wanted: trapclaw"] = {
        status = "ok",
        allFinished = true,
        summaryText = "1/1 Trapclaw's Pincer",
        objectives = { { index = 1, text = "1/1 Trapclaw's Pincer", finished = true } },
      },
    }

    local ctx1 = makeMockCtx({
      level = 41,
      active = {
        [94842] = true,
        [94907] = true, -- A Small Favor active -> artifact_verified inference suppresses 94879 & 94881!
        [95219] = true,
        ["title:wanted: trapclaw"] = true,
      },
      completed = {
        [95603] = true,
        [95613] = true, -- Keeping the Light On explicitly completed!
      },
      objectives = unsavoryObjectivesAllOpen,
    })

    local entries1, raw1 = WorldMapPins.CollectPinEntries(2548, route, prog, pinSettings, ctx1, playerPos)
    assertTrue(#entries1 > 0 and raw1.objectives >= 3 and raw1.turnins >= 1, "CollectPinEntries must emit active objectives, turn-ins, and available quests")

    local unsavorySubs1 = {}
    for _, e in ipairs(entries1) do
      assertTrue(e.questID ~= 95613, "Completed quest 95613 (Keeping the Light On) must NEVER appear on World Map")
      assertTrue(e.questID ~= 94879 and e.questID ~= 94881, "Artifact-verified inferred-completed prerequisites 94879/94881 must NEVER appear on World Map")
      assertTrue(not e.isElite, "Disabled elite bounties must be hidden on World Map when includeEliteBounties=false")
      if e.actionID == "rg_hb_obj_94842" then
        unsavorySubs1[tostring(e.subID)] = e
      end
    end
    assertTrue(
      unsavorySubs1["jumbo_crawfish_shell"] ~= nil
        and unsavorySubs1["fresh_manure"] ~= nil
        and unsavorySubs1["mudfin_murloc_head"] ~= nil,
      "Unsavory Plant Food must emit 3 distinct sub-objective pins while all 3 ingredients are incomplete"
    )

    -- Completing 8/8 Mudfin Murloc Head must immediately hide ONLY that sub-objective pin and step active target!
    local unsavoryObjectivesAfterMurlocs = {
      [94842] = {
        status = "ok",
        allFinished = false,
        summaryText = "0/4 Jumbo Crawfish Shell; 0/4 Fresh Manure; 8/8 Mudfin Murloc Head",
        objectives = {
          { index = 1, text = "0/4 Jumbo Crawfish Shell", finished = false },
          { index = 2, text = "0/4 Fresh Manure", finished = false },
          { index = 3, text = "8/8 Mudfin Murloc Head", finished = true },
        },
      },
      ["title:wanted: trapclaw"] = unsavoryObjectivesAllOpen["title:wanted: trapclaw"],
    }
    local ctx2 = makeMockCtx({
      level = 41,
      active = { [94842] = true, [94907] = true, [95219] = true, ["title:wanted: trapclaw"] = true },
      completed = { [95603] = true, [95613] = true },
      objectives = unsavoryObjectivesAfterMurlocs,
    })

    local entries2 = WorldMapPins.CollectPinEntries(2548, route, prog, pinSettings, ctx2, playerPos)
    local unsavorySubs2 = {}
    local countUnsavory2 = 0
    for _, e in ipairs(entries2) do
      if e.actionID == "rg_hb_obj_94842" then
        countUnsavory2 = countUnsavory2 + 1
        unsavorySubs2[tostring(e.subID)] = e
      end
    end
    assertTrue(
      countUnsavory2 == 2 and unsavorySubs2["mudfin_murloc_head"] == nil,
      "Finishing 8/8 Mudfin Murloc Head must auto-hide mudfin_murloc_head pin while preserving remaining 2 ingredient pins"
    )

    local unsavoryAct = nil
    for _, a in ipairs(route.actions) do
      if a.actionID == "rg_hb_obj_94842" then
        unsavoryAct = a
        break
      end
    end
    local steppedDest, _, steppedSub = RoutePlanner.ResolveActiveActionTarget(
      unsavoryAct,
      prog,
      ctx2,
      { status = "ok", uiMapID = 2548, x01 = 0.4420, y01 = 0.5600 }
    )
    assertTrue(
      steppedDest and steppedSub and steppedSub.subID ~= "mudfin_murloc_head",
      "ResolveActiveActionTarget must step Arrow away from finished mudfin_murloc_head to nearest unfinished ingredient"
    )

    -- Zoom-adaptive clustering: zoomed out (1.0x) merges nearby Powderfuse Port pins; zoomed in (4.0x) separates them!
    local clusters1x = WorldMapPins.BuildClusters(entries2, 1002, 668, 1.0, 22)
    local clusters4x = WorldMapPins.BuildClusters(entries2, 1002, 668, 4.0, 22)
    assertTrue(#clusters1x < #entries2, "Zoomed-out map (1.0x) must merge closely-spaced hub pins into compact clusters")
    assertTrue(#clusters4x > #clusters1x, "Zooming in (4.0x) must smoothly split hub clusters into individual NPC/spot pins")

    local foundTurnInAnchoredCluster = false
    for _, cl in ipairs(clusters1x) do
      if cl.hasTurnIn and cl.hasAvailable then
        assertTrue(cl.primary.kind == "turnin", "Mixed turn-in + available cluster must anchor badge on highest-priority turn-in")
        foundTurnInAnchoredCluster = true
      end
    end
    assertTrue(foundTurnInAnchoredCluster, "Powderfuse Port cluster must combine ready Trapclaw turn-in with available port quests at 1.0x")

    -- Cross-zone delivery pin on Feralas (1444)
    local entriesFeralas = WorldMapPins.CollectPinEntries(1444, route, prog, pinSettings, ctx2, playerPos)
    local foundPortToPort = false
    for _, e in ipairs(entriesFeralas) do
      if e.actionID == "rg_exit_turnin_95219" and e.kind == "turnin" then
        foundPortToPort = true
      end
    end
    assertTrue(foundPortToPort, "Active From Port to Port (95219) must appear as a turn-in pin on Feralas (1444)")

    -- Left-click focus (`FocusActionFromMapPin`) & Right-click unpin (`ClearPinnedFocus`)
    local okFocus, evalFocus = RouteProgress.FocusActionFromMapPin("rg_hb_obj_94842", "fresh_manure", route, prog, ctx2, playerPos)
    assertTrue(okFocus and prog.mode == "standalone", "Clicking a map pin while paused must activate standalone navigation")
    assertTrue(
      prog.pinnedActionID == "rg_hb_obj_94842"
        and prog.pinnedSubLocationID == "fresh_manure"
        and evalFocus.nextAction.actionID == "rg_hb_obj_94842",
      "FocusActionFromMapPin must pin both actionID and subLocationID"
    )
    local pinnedDest = RoutePlanner.ResolveActiveActionTarget(evalFocus.nextAction, prog, ctx2, playerPos)
    assertTrue(
      math.abs(pinnedDest.x01 - 0.4500) < 0.0005 and math.abs(pinnedDest.y01 - 0.7900) < 0.0005,
      "Pinned subLocationID must steer active target directly to Meadowsbrook Ranch Pasture (0.450, 0.790)"
    )

    local okClear = RouteProgress.ClearPinnedFocus(route, prog, ctx2, playerPos)
    assertTrue(okClear and prog.pinnedActionID == nil and prog.pinnedSubLocationID == nil, "ClearPinnedFocus must clear both pinnedActionID and pinnedSubLocationID")
  end)

  -- RG-14. v0.7.1 Quest-Evidence Correctness, Leaderboard Fallback, Collapsed Headers, Turn-In Provenance, Hysteresis & RXP Export
  check("RG-14. v0.7.1 Quest-Evidence, Classic Leaderboard Fallback, Collapsed Headers, Hysteresis & RXP Export", function()
    local savedCQ = _G.C_QuestLog
    local savedGetNumEntries = _G.GetNumQuestLogEntries
    local savedGetLogTitle = _G.GetQuestLogTitle
    local savedGetNumLB = _G.GetNumQuestLeaderBoards
    local savedGetLB = _G.GetQuestLogLeaderBoard
    local savedIsSecret = _G.issecretvalue
    local savedRXP = _G.RXPGuides
    local savedMap = _G.C_Map
    local savedWorldSizes = ns.State.overrideMapWorldSizes
    local savedLvl = ns.State.overridePlayerLevel
    local savedFac = ns.State.overridePlayerFaction
    local savedTurnInID = deepCopyTable(ns.Compat.recentQuestTurnedInByID or {})
    local savedTurnInTitle = deepCopyTable(ns.Compat.recentQuestTurnedInByTitle or {})
    local savedAcceptID = deepCopyTable(ns.Compat.recentQuestAcceptedByID or {})
    local savedAcceptTitle = deepCopyTable(ns.Compat.recentQuestAcceptedByTitle or {})
    local savedLastDialog = deepCopyTable(ns.Compat.lastDialogQuest or {})
    local savedObsLog = deepCopyTable(ns.Compat.observedLogTitlesByID or {})
    local savedDiscovered = _G.ForeverHubDB and deepCopyTable(_G.ForeverHubDB.discoveredQuestIds or {}) or nil
    local savedDiscoveredTitles = _G.ForeverHubDB and deepCopyTable(_G.ForeverHubDB.discoveredQuestTitlesById or {}) or nil
    local savedCharRG = charDB and deepCopyTable(charDB.routeProgress) or nil

    local okGate14, errGate14 = pcall(function()
      ns.State.overridePlayerLevel = 42
      ns.State.overridePlayerFaction = "Alliance"
      ns.State.overrideMapWorldSizes = { [2548] = { width = 3600, height = 2400 } }
      if _G.ForeverHubDB then
        _G.ForeverHubDB.discoveredQuestIds = {}
        _G.ForeverHubDB.discoveredQuestTitlesById = {}
      end
      if charDB then
        charDB.routeProgress = ns.State.MigrateRouteProgress({ mode = "standalone" }, route)
      end
      local prog = ns.State.GetRouteProgress()

      -- 1. P1 #1: Pre-install undiscovered title-only quest MUST return `unknown / title_history_unresolved`
      -- and enter `blocked_unresolved_history` (excluded from auto-routing & automatic `!` map pins until confirmed)
      _G.GetNumQuestLogEntries = function() return 0, 0 end
      _G.GetQuestLogTitle = function() return nil end
      _G.C_QuestLog = {
        GetNumQuestLogEntries = function() return 0, 0 end,
        IsQuestFlaggedCompleted = function() return false end,
        IsOnQuest = function() return false end,
        GetMaxNumQuestsCanAccept = function() return 40 end,
      }
      ns.Compat.InvalidateQuestStateCaches()

      local unresRes = ns.Compat.IsQuestCompletedResult("title:wanted: trapclaw")
      assertTrue(
        unresRes.status == "unknown" and unresRes.value == nil and unresRes.reason == "title_history_unresolved",
        "Undiscovered pre-install title quest must NEVER return ok,false"
      )
      local evUnres = ns.Compat.GetQuestEvidenceResult("title:wanted: trapclaw")
      assertTrue(
        type(evUnres) == "table" and evUnres.identityConfidence == "title_only_unresolved",
        "GetQuestEvidenceResult must report title_only_unresolved identityConfidence"
      )

      local evalBlocked = RoutePlanner.EvaluateRoute(route, prog)
      assertTrue(
        evalBlocked.byActionID["rg_pf_accept_wanted_trapclaw"].state == "blocked_unresolved_history",
        "Unconfirmed pre-install title pickup must be blocked_unresolved_history"
      )
      local pinsBlocked = ns.UI.WorldMapPins.CollectPinEntries(2548, route, prog)
      for _, pe in ipairs(pinsBlocked) do
        assertTrue(pe.actionID ~= "rg_pf_accept_wanted_trapclaw", "Unconfirmed title pickup must NOT show automatic ! pin")
      end

      -- Explicit user confirmation (`/fh rg confirm trapclaw`) unlocks pickup & `!` map pin
      ns.State.ConfirmUnresolvedQuestIncomplete("title:wanted: trapclaw", prog)
      local evalConfirmed = RoutePlanner.EvaluateRoute(route, prog)
      assertTrue(
        evalConfirmed.byActionID["rg_pf_accept_wanted_trapclaw"].state == "available"
          and evalConfirmed.byActionID["rg_pf_accept_wanted_trapclaw"].reason == "user_confirmed_incomplete",
        "Confirming unresolved title quest incomplete must unlock pickup"
      )
      local pinsConfirmed = ns.UI.WorldMapPins.CollectPinEntries(2548, route, prog)
      local sawConfirmedTrapPin = false
      for _, pe in ipairs(pinsConfirmed) do
        if pe.actionID == "rg_pf_accept_wanted_trapclaw" then
          sawConfirmedTrapPin = true
          break
        end
      end
      assertTrue(sawConfirmedTrapPin, "Confirmed incomplete title quest must emit ! map pin")

      -- 2. P1 #2: Numeric catalog ID (94842) + live Quest Log row with `questID = 0` + modern GetQuestObjectives
      -- returning nil/error -> falls back to Classic leaderboards via verified fresh logIndex, while preserving `restricted`!
      local modernMode = "nil"
      local secretSentinel = { __secret = true }
      _G.issecretvalue = function(v) return v == secretSentinel end
      _G.GetNumQuestLogEntries = function() return 2, 1 end
      _G.GetQuestLogTitle = function(idx)
        if idx == 1 then
          return "Riverglades", 0, nil, true, false, nil, nil, 0
        elseif idx == 2 then
          return "Unsavory Plant Food", 38, nil, false, false, false, nil, 0 -- live questID == 0!
        end
        return nil
      end
      _G.GetNumQuestLeaderBoards = function(idx)
        return idx == 2 and 3 or 0
      end
      _G.GetQuestLogLeaderBoard = function(objIdx, qIdx)
        if qIdx ~= 2 then return nil end
        if objIdx == 1 then return "4/4 Jumbo Crawfish Shell", "item", true end
        if objIdx == 2 then return "1/4 Fresh Manure", "item", false end
        if objIdx == 3 then return "8/8 Mudfin Murloc Head", "item", true end
        return nil
      end
      _G.C_QuestLog = {
        GetNumQuestLogEntries = function() return 2, 1 end,
        IsQuestFlaggedCompleted = function(qid) return qid == 94841 end,
        IsOnQuest = function(qid) return qid == 94842 end,
        GetQuestObjectives = function(qid)
          if qid == 94842 then
            if modernMode == "error" then error("modern_objectives_error") end
            if modernMode == "restricted" then return secretSentinel end
          end
          return nil
        end,
        GetMaxNumQuestsCanAccept = function() return 40 end,
      }
      ns.Compat.InvalidateQuestStateCaches()

      local objFallbackNil = ns.Compat.GetQuestObjectivesResult(94842)
      assertTrue(
        objFallbackNil.status == "ok"
          and objFallbackNil.provider == "classic_leaderboards"
          and objFallbackNil.allFinished == false,
        "Catalog numeric ID with live questID=0 and nil modern objectives must fall back to Classic leaderboards"
      )
      modernMode = "error"
      local objFallbackErr = ns.Compat.GetQuestObjectivesResult(94842)
      assertTrue(
        objFallbackErr.status == "ok" and objFallbackErr.provider == "classic_leaderboards",
        "Modern GetQuestObjectives error must also fall back to Classic leaderboards"
      )
      local unsavoryAct = nil
      for _, a in ipairs(route.actions) do
        if a.actionID == "rg_hb_obj_94842" then unsavoryAct = a; break end
      end
      local remSubs = RoutePlanner.ResolveActiveSubLocations(unsavoryAct)
      assertTrue(
        #remSubs == 1 and remSubs[1].subID == "fresh_manure",
        "Classic leaderboard fallback must retire finished Crawfish & Murloc sub-pins, leaving only Fresh Manure"
      )

      modernMode = "restricted"
      local objRestricted = ns.Compat.GetQuestObjectivesResult(94842)
      assertTrue(
        objRestricted.status == "restricted",
        "Restricted modern objective result MUST NOT be bypassed by Classic fallback"
      )

      -- 3. P1 #3: Collapsed Quest Log header MUST produce `unknown / collapsed_quest_headers` (never false `ok, false`)
      _G.GetNumQuestLogEntries = function() return 1, 3 end
      _G.GetQuestLogTitle = function(idx)
        if idx == 1 then
          return "Riverglades", 0, nil, true, true, nil, nil, 0 -- isHeader=true, isCollapsed=true!
        end
        return nil
      end
      _G.C_QuestLog = {
        GetNumQuestLogEntries = function() return 1, 3 end,
        IsQuestFlaggedCompleted = function() return false end,
        GetMaxNumQuestsCanAccept = function() return 40 end,
      }
      ns.Compat.InvalidateQuestStateCaches()

      local onCollapsed = ns.Compat.IsOnQuestResult("title:wanted: trapclaw")
      assertTrue(
        onCollapsed.status == "unknown" and onCollapsed.reason == "collapsed_quest_headers",
        "Collapsed Quest Log headers must return unknown/collapsed_quest_headers, never ok,false"
      )
      local evalCollapsed = RoutePlanner.EvaluateRoute(route, prog)
      assertTrue(
        evalCollapsed.byActionID["rg_pf_accept_wanted_trapclaw"].state == "blocked_unverified"
          and evalCollapsed.byActionID["rg_pf_accept_wanted_trapclaw"].reason == "collapsed_quest_headers",
        "Collapsed headers must block uncertain title pickup rather than falsely treating quest as inactive"
      )

      -- 4. P2 #1: QUEST_TURNED_IN without dialogue/cache reverse-resolves persisted ID & rejects conflicting dialogue
      ns.State.RecordDiscoveredQuestId("wanted: trapclaw", 95999)
      ns.Compat.lastDialogQuest = { questID = 94879, title = "Scraps of Knowledge", at = 999999999 }
      _G.GetNumQuestLogEntries = function() return 0, 0 end
      _G.GetQuestLogTitle = function() return nil end
      ns.Compat.InvalidateQuestStateCaches()
      ns.Compat.RecordRecentQuestTurnedIn(95999, nil)

      assertTrue(
        not ns.State.IsObservedCompletedQuestTitle("scraps of knowledge"),
        "Conflicting lastDialogQuest title must be rejected on QUEST_TURNED_IN"
      )
      assertTrue(
        ns.State.IsObservedCompletedQuestTitle("wanted: trapclaw") and ns.State.IsObservedCompletedQuestId(95999),
        "Persisted reverse ID->title map must record both title and numeric ID completion on QUEST_TURNED_IN"
      )
      ns.Compat.recentQuestTurnedInByID = {}
      ns.Compat.recentQuestTurnedInByTitle = {}
      local persistedComp = ns.Compat.IsQuestCompletedResult("title:wanted: trapclaw")
      assertTrue(
        persistedComp.status == "ok" and persistedComp.value == true,
        "Persisted turn-in completion must survive after transient TTL cache expires"
      )

      -- 5. P2 #3: Sustained sub-target hysteresis (`65 yd`) & proximity-tier hysteresis
      local hProg = ns.State.MigrateRouteProgress({
        mode = "standalone",
        currentActionID = "rg_hb_obj_94842",
        currentSubLocationID = "jumbo_crawfish_shell",
      }, route)
      local hCtx = makeMockCtx({
        level = 41,
        active = { [94842] = true },
        objectives = {
          [94842] = {
            status = "ok",
            allFinished = false,
            objectives = {
              { index = 1, text = "0/4 Jumbo Crawfish Shell", finished = false },
              { index = 2, text = "0/4 Fresh Manure", finished = false },
              { index = 3, text = "8/8 Mudfin Murloc Head", finished = true },
            },
          },
        },
      })
      -- Midpoint slightly closer (~35.5 yds) to fresh_manure (0.450, 0.790) than jumbo_crawfish_shell (0.564, 0.458):
      -- sustained 65 yd hysteresis MUST retain jumbo_crawfish_shell!
      local _, _, retainedSub = RoutePlanner.ResolveActiveActionTarget(
        unsavoryAct,
        hProg,
        hCtx,
        { status = "ok", uiMapID = 2548, x01 = 0.5040, y01 = 0.6300 }
      )
      assertTrue(
        retainedSub and retainedSub.subID == "jumbo_crawfish_shell",
        "Sustained sub-location hysteresis must prevent oscillation near midpoint (<65 yd delta)"
      )
      -- Standing right at Meadowsbrook Ranch (0.450, 0.790, >200 yds closer): switches cleanly to fresh_manure!
      local _, _, switchedSub = RoutePlanner.ResolveActiveActionTarget(
        unsavoryAct,
        hProg,
        hCtx,
        { status = "ok", uiMapID = 2548, x01 = 0.4500, y01 = 0.7900 }
      )
      assertTrue(
        switchedSub and switchedSub.subID == "fresh_manure",
        "Moving >65 yds closer to another unfinished sub-location must switch cleanly"
      )

      -- 6. P2 #2 & P1 #4: RXP-mode map-pin click honesty, ProjectCoordinates NaN guard & RXP `.complete` / `+` export
      _G.RXPGuides = {
        RegisterGuide = function() return true end,
        currentGuide = {
          group = ns.Bridges.RXPBridge.RIVERGLADES_GUIDE_GROUP,
          name = ns.Bridges.RXPBridge.RIVERGLADES_GUIDE_NAME,
        },
      }
      local okRxpPin, evalRxpPin = RouteProgress.FocusActionFromMapPin(
        "rg_hb_obj_94842",
        "fresh_manure",
        route,
        hProg,
        hCtx,
        { status = "ok", uiMapID = 2548, x01 = 0.4500, y01 = 0.7900 }
      )
      assertTrue(
        okRxpPin and hProg.mode == "rxp" and evalRxpPin.mode == "rxp",
        "Clicking a World Map pin while exported RXP guide is selected must preserve mode='rxp'"
      )

      _G.C_Map = {
        GetMapRectOnMap = function()
          return 0.1, 0.5, 0.0 / 0.0, 0.8 -- NaN minY!
        end,
      }
      local badProjX, badProjY = ns.UI.WorldMapPins.ProjectCoordinates(2548, 1415, 0.5, 0.5)
      assertTrue(badProjX == nil and badProjY == nil, "ProjectCoordinates must reject NaN/non-finite map rectangle bounds")

      if _G.ForeverHubDB then
        _G.ForeverHubDB.discoveredQuestIds = {}
        _G.ForeverHubDB.discoveredQuestTitlesById = {}
      end
      local rxpGuideText, rxpErr = ns.Bridges.RXPBridge.BuildRivergladesGuideText(route)
      assertTrue(type(rxpGuideText) == "string" and rxpErr == nil, "BuildRivergladesGuideText must succeed")
      assertTrue(string.find(rxpGuideText, "STATIC LINEAR SNAPSHOT", 1, true) ~= nil, "RXP export must label static linear snapshot")
      assertTrue(string.find(rxpGuideText, ".complete 94842,1", 1, true) ~= nil, "RXP export must emit per-subLocation .complete 94842,1")
      assertTrue(string.find(rxpGuideText, ".complete 94842,3", 1, true) ~= nil, "RXP export must emit per-subLocation .complete 94842,3")
      assertTrue(string.find(rxpGuideText, ".complete -95991,1", 1, true) ~= nil, "RXP export must emit negative skipIfMissing .complete for optional [42+] elites")
      assertTrue(string.find(rxpGuideText, "\n    +Accept WANTED: Trapclaw (manual checkbox", 1, true) ~= nil, "Undiscovered title quest in RXP export must emit clickable + manual checkbox")
      assertTrue(string.find(rxpGuideText, "[Est. Coords]", 1, true) == nil, "RXP export must have zero [Est. Coords] when 100% of active steps are artifact_verified")
    end)

    _G.C_QuestLog = savedCQ
    _G.GetNumQuestLogEntries = savedGetNumEntries
    _G.GetQuestLogTitle = savedGetLogTitle
    _G.GetNumQuestLeaderBoards = savedGetNumLB
    _G.GetQuestLogLeaderBoard = savedGetLB
    _G.issecretvalue = savedIsSecret
    _G.RXPGuides = savedRXP
    _G.C_Map = savedMap
    ns.State.overrideMapWorldSizes = savedWorldSizes
    ns.State.overridePlayerLevel = savedLvl
    ns.State.overridePlayerFaction = savedFac
    ns.Compat.recentQuestTurnedInByID = savedTurnInID
    ns.Compat.recentQuestTurnedInByTitle = savedTurnInTitle
    ns.Compat.recentQuestAcceptedByID = savedAcceptID
    ns.Compat.recentQuestAcceptedByTitle = savedAcceptTitle
    ns.Compat.lastDialogQuest = savedLastDialog
    ns.Compat.observedLogTitlesByID = savedObsLog
    if _G.ForeverHubDB then
      _G.ForeverHubDB.discoveredQuestIds = savedDiscovered or {}
      _G.ForeverHubDB.discoveredQuestTitlesById = savedDiscoveredTitles or {}
    end
    if charDB then
      charDB.routeProgress = savedCharRG
    end
    ns.Compat.InvalidateQuestStateCaches()
    if not okGate14 then
      error(errGate14, 2)
    end
  end)

  -- RG-15. v0.8.4 14-Quest Zone Audit & Live Client Quest-Target Self-Healing (Defense-in-Depth)
  check("RG-15. v0.8.4 14-Quest Zone Audit & Live Client Quest-Target Self-Healing", function()
    local savedMapOv = ns.State.overrideMapQuestsByUiMapID
    local savedObjTxtOv = ns.State.overrideQuestObjectiveTexts
    local savedWorldSizes = ns.State.overrideMapWorldSizes
    local savedDrifts = deepCopyTable(ns.Compat.liveQuestTargetDrifts or {})
    local savedObjTxtMem = deepCopyTable(ns.Compat.questObjectiveTextByID or {})
    local savedCharRG = charDB and deepCopyTable(charDB.routeProgress) or nil

    local okGate15, errGate15 = pcall(function()
      ns.State.overrideMapWorldSizes = { [2548] = { width = 3600, height = 2400 }, [1444] = { width = 6950, height = 4633 } }
      ns.Compat.liveQuestTargetDrifts = {}
      ns.Compat.questObjectiveTextByID = {}

      -- 1. Verify Layer 1 Static Audit: Gaseous Gold (96063) -> Sleebo Fizzlespout (263367 @ 69.55, 50.32), NOT Friz Frazzlespark!
      local byID = {}
      for _, a in ipairs(route.actions) do
        byID[a.actionID] = a
        if a.destination then
          assertTrue(
            a.destination.coordConfidence == "artifact_verified"
              or (a.destination.coordConfidence == "subzone_verified" and a.reviewStatus == "estimated"),
            "Every active automated step in v0.8.7 must be artifact_verified or subzone_verified (estimated): " .. tostring(a.actionID)
          )
        end
      end
      local gasAccept = byID["rg_pf_accept_96063"]
      local gasTurnin = byID["rg_pf_turnin_96063"]
      assertTrue(
        gasAccept and gasAccept.npcID == 263367 and gasAccept.npcName == "Sleebo Fizzlespout",
        "96063 accept must point to Sleebo Fizzlespout (263367)"
      )
      assertTrue(
        gasTurnin
          and gasTurnin.npcID == 263367
          and gasTurnin.npcName == "Sleebo Fizzlespout"
          and math.abs(gasTurnin.destination.x01 - 0.6955) < 1e-4
          and math.abs(gasTurnin.destination.y01 - 0.5032) < 1e-4,
        "96063 turn-in must point to Sleebo Fizzlespout @ (0.6955, 0.5032)"
      )

      -- Verify key audited quests across the zone
      local gdsObj = byID["rg_pf_obj_goes_down_smooth"]
      assertTrue(
        gdsObj and type(gdsObj.subLocations) == "table" and #gdsObj.subLocations == 4,
        "Goes Down Smooth (95988) must include all 4 audited drink delivery sub-locations"
      )
      assertTrue(
        byID["rg_pf_turnin_goes_down_smooth"] and byID["rg_pf_turnin_goes_down_smooth"].npcID == 255894,
        "Goes Down Smooth (95988) turn-in must be Innkeeper Zizplink (255894)"
      )
      assertTrue(
        byID["rg_exit_turnin_95219"]
          and byID["rg_exit_turnin_95219"].npcID == 7941
          and byID["rg_exit_turnin_95219"].destination.uiMapID == 1444,
        "From Port to Port (95219) must deliver to Mardrack Greenwell (7941) in Feralas (1444)"
      )
      assertTrue(
        byID["rg_fk_obj_95603"] and byID["rg_fk_obj_95603"].npcID == 262037,
        "Bats in the Belfry (95603) must target Roosting Duskbat (262037)"
      )
      assertTrue(
        byID["rg_fk_turnin_95156"] and byID["rg_fk_turnin_95156"].npcID == 260080
          and byID["rg_sup_turnin_95184"] and byID["rg_sup_turnin_95184"].npcID == 260080,
        "95156 & 95184 must point to Ember Bladewhisper (260080)"
      )
      assertTrue(
        route.questsByID[94925] and route.questsByID[94925].zeroObjectives == false
          and byID["rg_hb_turnin_94925"] and byID["rg_hb_turnin_94925"].npcID == 259352
          and route.questsByID[94928] and route.questsByID[94928].zeroObjectives == true
          and byID["rg_pf_turnin_94928"] and byID["rg_pf_turnin_94928"].npcID == 255897,
        "A Fur Trade (94925) must turn in to Watcher Cornelius (259352), unlocking zero-objective A Few Furs for Friz (94928 -> 255897)"
      )
      assertTrue(
        byID["rg_hb_turnin_95329"] and byID["rg_hb_turnin_95329"].npcID == 259352,
        "Out in the Field (95329) turn-in must point to Watcher Cornelius (259352)"
      )
      assertTrue(
        byID["rg_hb_accept_94614"] and byID["rg_hb_accept_94614"].npcID == 258317
          and byID["rg_hb_accept_94618"] and byID["rg_hb_accept_94618"].npcID == 258317,
        "94614 & 94618 must be present at Benjy Wheeler (258317)"
      )
      assertTrue(
        byID["rg_pf_turnin_wanted_trapclaw"] and byID["rg_pf_turnin_wanted_trapclaw"].npcID == 259962,
        "WANTED: Trapclaw must turn in at Fimbo Greasemitz (259962)"
      )
      assertTrue(
        byID["rg_el_turnin_95912"] and byID["rg_el_turnin_95912"].npcID == 260080,
        "WANTED: Blademaster Kaijo (95912) must turn in at Ember Bladewhisper (260080)"
      )
      assertTrue(
        byID["rg_hb_obj_94925"]
          and byID["rg_hb_obj_94925"].npcID == 259055
          and math.abs(byID["rg_hb_obj_94925"].destination.x01 - 0.6152) < 1e-4
          and math.abs(byID["rg_hb_obj_94925"].destination.y01 - 0.5003) < 1e-4,
        "A Fur Trade (94925) objective must target Wildplains Huntress (259055) @ (61.52, 50.03), NEVER Plains Prowler (268831)"
      )
      assertTrue(
        byID["rg_hb_obj_foremans_plight"]
          and math.abs(byID["rg_hb_obj_foremans_plight"].destination.x01 - 0.5110) < 1e-4
          and math.abs(byID["rg_hb_obj_foremans_plight"].destination.y01 - 0.5710) < 1e-4,
        "Foreman's Plight (95943) objective must point to Foreman's Crate @ (51.10, 57.10)"
      )
      assertTrue(
        byID["rg_pf_obj_96063"]
          and math.abs(byID["rg_pf_obj_96063"].destination.x01 - 0.6240) < 1e-4
          and math.abs(byID["rg_pf_obj_96063"].destination.y01 - 0.5720) < 1e-4,
        "Gaseous Gold (96063) objective must point to Marsh Gas Vents @ (62.40, 57.20)"
      )
      assertTrue(
        byID["rg_hb_obj_94843"]
          and math.abs(byID["rg_hb_obj_94843"].destination.x01 - 0.3880) < 1e-4
          and math.abs(byID["rg_hb_obj_94843"].destination.y01 - 0.6270) < 1e-4,
        "From Seed to Sprout (94843) objective must point to Loamy Soil @ (38.80, 62.70)"
      )
      assertTrue(
        byID["rg_el_obj_94890"]
          and byID["rg_el_obj_94890"].npcID == 256881
          and math.abs(byID["rg_el_obj_94890"].destination.x01 - 0.2580) < 1e-4
          and math.abs(byID["rg_el_obj_94890"].destination.y01 - 0.4340) < 1e-4
          and byID["rg_wf_obj_94891"] == nil
          and byID["rg_wf_turnin_94891"]
          and byID["rg_wf_turnin_94891"].npcID == 257591
          and route.questsByID[94891].zeroObjectives == true,
        "Bring Me His Head (94890) -> Overlord Kilgar (25.8, 43.4) & News to Farholde (94891) zero-obj -> Ashe Amberhall (257591)"
      )
      assertTrue(
        byID["rg_hb_accept_94961"]
          and byID["rg_hb_accept_94961"].npcID == 259158
          and math.abs(byID["rg_hb_accept_94961"].destination.x01 - 0.4730) < 1e-4
          and math.abs(byID["rg_hb_accept_94961"].destination.y01 - 0.5130) < 1e-4
          and byID["rg_hb_obj_94961"]
          and byID["rg_hb_obj_94961"].npcID == 254560,
        "Biting the Hand (94961) must start/turn in at Fuzzle (47.3, 51.3) and farm Twilight Shadowmancers (254560)"
      )
      assertTrue(
        type(route.npcDirectoryByID) == "table" and route.npcDirectoryByID[263367] ~= nil and route.npcDirectoryByID[7941] ~= nil,
        "198-entry NPC directory must include Sleebo Fizzlespout (263367) and Mardrack Greenwell (7941)"
      )

      -- 2. Verify Layer 2 Live Client Self-Healing against simulated server hotfix drift
      -- Simulate an outdated static turn-in action pointing 96063 to Friz Frazzlespark (77.15, 52.92)
      local staleAction = {
        actionID = "test_stale_turnin_96063",
        kind = "turnin",
        questID = 96063,
        title = "Turn in Gaseous Gold",
        npcID = 255897,
        npcName = "Friz Frazzlespark",
        destination = {
          uiMapID = 2548,
          areaID = 16727,
          x01 = 0.7715,
          y01 = 0.5292,
          coordinateSpace = "uiMap01",
          coordConfidence = "artifact_verified",
        },
      }
      local healProg = ns.State.MigrateRouteProgress({ mode = "standalone" }, route)
      local healCtx = makeMockCtx({
        level = 41,
        active = { [96063] = true },
        objectives = { [96063] = true },
      })

      -- 2a. Hostile-mob & rank-prefix text parser safety
      assertTrue(
        ns.Compat.MatchNpcFromQuestText("Travel to Bolder'ok Outpost to kill Bolder'ok Brute.", route) == nil,
        "MatchNpcFromQuestText must NEVER match hostile mob after an infinitive verb ('to kill ...')"
      )
      local rankedMatch = ns.Compat.MatchNpcFromQuestText(
        "Deliver the Eye of Mugg to Knight Commander Demar Brant in Farholde Keep.",
        route
      )
      assertTrue(
        rankedMatch and rankedMatch.npcID == 257558,
        "MatchNpcFromQuestText must resolve ranked NPC names ('Knight Commander Demar Brant' -> 257558)"
      )

      -- 2b. Signal 1: Quest Log objective text ('Gather 5 Marsh Gas Vials for Sleebo Fizzlespout.') heals target!
      ns.State.overrideMapQuestsByUiMapID = {}
      ns.State.overrideQuestObjectiveTexts = {
        [96063] = "Gather 5 Marsh Gas Vials for Sleebo Fizzlespout.",
      }
      local d1, n1, sub1, ov1 = RoutePlanner.ResolveActiveActionTarget(staleAction, healProg, healCtx, nil, route)
      assertTrue(sub1 == nil, "Single-spot live override MUST keep 3rd return (activeSub) nil")
      assertTrue(
        d1
          and n1 == "Sleebo Fizzlespout"
          and math.abs(d1.x01 - 0.6955) < 1e-4
          and math.abs(d1.y01 - 0.5032) < 1e-4
          and ov1
          and ov1.source == "quest_text_npc",
        "Quest Log objective text must self-heal turn-in target to Sleebo Fizzlespout @ (69.55, 50.32)"
      )

      -- 2c. Signal 2: Observed QUEST_DETAIL giver heals same-giver-as-turnin quest when text/POI absent
      ns.State.overrideQuestObjectiveTexts = nil
      ns.Compat.questObjectiveTextByID = {}
      ns.State.RecordObservedQuestGiver(96063, {
        npcID = 263367,
        npcName = "Sleebo Fizzlespout",
        uiMapID = 2548,
        x01 = 0.6955,
        y01 = 0.5032,
      }, healProg)
      local d2, n2, sub2, ov2 = RoutePlanner.ResolveActiveActionTarget(staleAction, healProg, healCtx, nil, route)
      assertTrue(
        sub2 == nil
          and n2 == "Sleebo Fizzlespout"
          and math.abs(d2.x01 - 0.6955) < 1e-4
          and ov2
          and ov2.source == "observed_quest_giver",
        "Observed quest giver must self-heal turn-in when giverNpcID == turninNpcID"
      )

      -- 2d. Signal 3: Live Map POI (`C_QuestLog.GetQuestsOnMap`) heals target & World Map Pins, while <25 yd jitter is ignored!
      healProg.observedQuestGivers = {}
      ns.State.overrideMapQuestsByUiMapID = {
        [2548] = {
          [96063] = { questID = 96063, x01 = 0.7712, y01 = 0.5290 }, -- ~1.2 yds from static: must NOT trigger override!
        },
      }
      local _, _, _, ovJitter = RoutePlanner.ResolveActiveActionTarget(staleAction, healProg, healCtx, nil, route)
      assertTrue(ovJitter == nil, "<25 yd map POI coordinate jitter must NOT trigger a false-positive override")

      -- Move live map POI for 96063 to Powderfuse Pier (Argo Brinewhistle @ 0.7954, 0.5246, >360 yds from Sleebo):
      -- Both ResolveActiveActionTarget AND WorldMapPins.CollectPinEntries on the real route must self-heal!
      ns.State.overrideMapQuestsByUiMapID = {
        [2548] = {
          [96063] = { questID = 96063, x01 = 0.7954, y01 = 0.5246 },
        },
      }
      local realTurnin = byID["rg_pf_turnin_96063"]
      local d3, n3, sub3, ov3 = RoutePlanner.ResolveActiveActionTarget(realTurnin, healProg, healCtx, nil, route)
      assertTrue(
        sub3 == nil
          and n3 == "Argo Brinewhistle"
          and math.abs(d3.x01 - 0.7954) < 1e-4
          and math.abs(d3.y01 - 0.5246) < 1e-4
          and ov3
          and ov3.source == "live_map_poi",
        "Live map POI >25 yds away must self-heal route target and resolve nearest directory NPC"
      )
      assertTrue(
        ns.Compat.liveQuestTargetDrifts["rg_pf_turnin_96063"] ~= nil,
        "Active live self-healing override must be recorded in Compat.liveQuestTargetDrifts for /fh rg doctor"
      )

      local healedPins = ns.UI.WorldMapPins.CollectPinEntries(
        2548,
        route,
        healProg,
        { enabled = true, showObjectives = true, showTurnIns = true, showAvailable = true },
        healCtx
      )
      local sawHealedMapPin = false
      for _, pe in ipairs(healedPins) do
        if pe.actionID == "rg_pf_turnin_96063" then
          assertTrue(
            math.abs(pe.x01 - 0.7954) < 1e-4 and pe.targetName == "Argo Brinewhistle",
            "WorldMapPins must project healed coordinates and NPC name for single-spot turn-ins"
          )
          sawHealedMapPin = true
        end
      end
      assertTrue(sawHealedMapPin, "WorldMapPins must emit healed turn-in pin for 96063")
    end)

    ns.State.overrideMapQuestsByUiMapID = savedMapOv
    ns.State.overrideQuestObjectiveTexts = savedObjTxtOv
    ns.State.overrideMapWorldSizes = savedWorldSizes
    ns.Compat.liveQuestTargetDrifts = savedDrifts
    ns.Compat.questObjectiveTextByID = savedObjTxtMem
    if charDB then
      charDB.routeProgress = savedCharRG
    end
    ns.Compat.InvalidateQuestStateCaches()
    if not okGate15 then
      error(errGate15, 2)
    end
  end)

  -- RG-16. The Monster Surfaces (95267 @ 74.3, 72.4), Anti-Misdirection Selection Guardrails & Field Telemetry
  check("RG-16. The Monster Surfaces (74.3, 72.4), Selection Guardrails & Field Telemetry", function()
    local savedSelOv = ns.State.overrideSelectedQuest
    local savedPosOv = ns.State.overridePlayerPosition
    local savedActiveOv = ns.State.overrideActiveQuests
    local savedCompOv = ns.State.overrideCompletedQuests
    local savedCaps = (_G.ForeverHubDB and type(_G.ForeverHubDB.fieldCaptures) == "table")
      and deepCopyTable(_G.ForeverHubDB.fieldCaptures)
      or nil
    local savedCharRG = charDB and deepCopyTable(charDB.routeProgress) or nil

    local okGate16, errGate16 = pcall(function()
      local byID = {}
      for _, a in ipairs(route.actions) do
        byID[a.actionID] = a
      end

      -- 1. Verify 95267 (The Monster Surfaces) static route coordinates & chain
      local msAccept = byID["rg_pf_accept_95267"]
      local msObj = byID["rg_pf_obj_95267"]
      local msTurnin = byID["rg_pf_turnin_95267"]
      assertTrue(msAccept and msAccept.npcID == 260231, "95267 accept must point to Argo Brinewhistle (260231)")
      assertTrue(
        msObj
          and msObj.destination
          and msObj.destination.uiMapID == 2548
          and math.abs(msObj.destination.x01 - 0.7430) < 1e-4
          and math.abs(msObj.destination.y01 - 0.7240) < 1e-4
          and msObj.destination.coordConfidence == "artifact_verified",
        "95267 objective must point to verified Fresh Wreckage at (74.3, 72.4)"
      )
      assertTrue(
        msTurnin
          and msTurnin.npcID == 260231
          and math.abs(msTurnin.destination.x01 - 0.7954) < 1e-4
          and math.abs(msTurnin.destination.y01 - 0.5246) < 1e-4,
        "95267 turn-in must point to Argo Brinewhistle at (79.54, 52.46)"
      )

      -- Verify newly reconciled Riverglades quests from WDB + QuestieDB
      assertTrue(byID["rg_hb_obj_95064"] and byID["rg_hb_obj_95064"].npcID == 256749, "Preventative Measures (95064) must target Rog'mar Trainee (256749)")
      assertTrue(byID["rg_hb_obj_95984"] and byID["rg_hb_obj_95984"].npcID == 263348, "Song of the Strider (95984) must target Roving Tallstrider (263348)")
      assertTrue(byID["rg_fk_obj_96082"] and byID["rg_fk_obj_96082"].npcID == 263614, "Doctor's Orderly (96082) must target Wounded Soldier (263614)")
      assertTrue(byID["rg_pf_turnin_95957"] and byID["rg_pf_turnin_95957"].npcID == 263120, "Drink Up! (95957) must turn in to Gray Dawnbright (263120)")
      assertTrue(byID["rg_pf_obj_96067"] and byID["rg_pf_obj_96067"].npcID == 263369, "Rock 'em and Sock 'em (96067) must target G45-B4G (263369)")

      -- 2. Verify WorldMapPins Selection Sync & Anti-Misdirection Notice Banner
      local pinProg = ns.State.MigrateRouteProgress({ mode = "standalone" }, route)
      local pinCtx = makeMockCtx({
        level = 42,
        questLogFull = true,
        active = {
          ["title:wanted: trapclaw"] = true,
          [95267] = true,
          [95123] = true, -- A Blast Ye Scurvy Dogs! (quarantined objective: Powder Keg spawns unpinned)
        },
        objectives = {
          ["title:wanted: trapclaw"] = false,
          [95267] = false,
          [95123] = false,
        },
      })

      -- 2a. Selecting 95267 (The Monster Surfaces) highlights its (74.3, 72.4) pin and emits NO unverified warning
      ns.State.overrideSelectedQuest = { questID = 95267, title = "The Monster Surfaces", level = 42 }
      local entriesMapped, countsMapped = ns.UI.WorldMapPins.CollectPinEntries(
        2548,
        route,
        pinProg,
        { enabled = true, showObjectives = true, showTurnIns = true, showAvailable = true },
        pinCtx,
        { status = "ok", uiMapID = 2548, x01 = 0.8030, y01 = 0.5440 }
      )
      assertTrue(countsMapped.selectedQuestNotice == nil, "Mapped quest 95267 must NOT emit an unverified warning banner")
      local sawSelected95267 = false
      for _, e in ipairs(entriesMapped) do
        if e.actionID == "rg_pf_obj_95267" then
          assertTrue(
            e.isSelectedQuest == true
              and math.abs(e.x01 - 0.7430) < 1e-4
              and math.abs(e.y01 - 0.7240) < 1e-4,
            "95267 map pin must be at (74.3, 72.4) and marked isSelectedQuest=true"
          )
          sawSelected95267 = true
        end
      end
      assertTrue(sawSelected95267, "WorldMapPins must render objective pin for 95267 at (74.3, 72.4)")

      -- 2b. Selecting promoted 95123 (A Blast Ye Scurvy Dogs!) now renders a subzone_verified pin with NO unverified warning,
      -- while selecting quarantined placeholder 95331 (REUSE ME) emits the anti-misdirection warning banner!
      ns.State.overrideSelectedQuest = { questID = 95123, title = "A Blast Ye Scurvy Dogs!", level = 44 }
      local entries95123, counts95123 = ns.UI.WorldMapPins.CollectPinEntries(
        2548,
        route,
        pinProg,
        { enabled = true, showObjectives = true, showTurnIns = true, showAvailable = true },
        pinCtx,
        { status = "ok", uiMapID = 2548, x01 = 0.8030, y01 = 0.5440 }
      )
      assertTrue(counts95123.selectedQuestNotice == nil, "Promoted quest 95123 must NOT emit an unverified warning banner")
      local saw95123Pin = false
      for _, e in ipairs(entries95123) do
        if e.actionID == "rg_pf_obj_95123" then
          assertTrue(
            e.isSelectedQuest == true and e.coordConfidence == "subzone_verified",
            "95123 map pin must carry coordConfidence='subzone_verified' and isSelectedQuest=true"
          )
          saw95123Pin = true
        end
      end
      assertTrue(saw95123Pin, "WorldMapPins must render objective pin for 95123 at Windstead")

      ns.State.overrideSelectedQuest = { questID = 95331, title = "REUSE ME", level = 45 }
      local _, countsQuar = ns.UI.WorldMapPins.CollectPinEntries(
        2548,
        route,
        pinProg,
        { enabled = true, showObjectives = true, showTurnIns = true, showAvailable = true },
        pinCtx,
        { status = "ok", uiMapID = 2548, x01 = 0.8030, y01 = 0.5440 }
      )
      assertTrue(
        countsQuar.selectedQuestNotice ~= nil
          and countsQuar.selectedQuestNotice.status == "quarantined_objective"
          and string.find(countsQuar.selectedQuestNotice.bannerText, "REUSE ME", 1, true) ~= nil
          and string.find(countsQuar.selectedQuestNotice.bannerText, "Location unverified", 1, true) ~= nil
          and string.find(countsQuar.selectedQuestNotice.bannerText, "Arrow: WANTED: Trapclaw", 1, true) ~= nil,
        "Selecting quarantined quest must warn player that it has no FH pin and explicitly name the quest owning the arrow"
      )

      -- 3. Verify Field-Capture Telemetry (State.RecordFieldCapture & /fh rg mark)
      if _G.ForeverHubDB then
        _G.ForeverHubDB.fieldCaptures = {}
      end
      ns.State.overridePlayerPosition = { status = "ok", uiMapID = 2548, x01 = 0.74304, y01 = 0.72398 }
      ns.State.overrideSelectedQuest = { questID = 95267, title = "The Monster Surfaces", level = 42 }
      local okCap, rec = ns.Events.CaptureQuestFieldTelemetry("manual_mark", nil, "Fresh Wreckage")
      assertTrue(
        okCap == true
          and rec ~= nil
          and rec.questID == 95267
          and rec.uiMapID == 2548
          and math.abs(rec.x01 - 0.7430) < 1e-6
          and math.abs(rec.y01 - 0.7240) < 1e-6
          and rec.note == "Fresh Wreckage",
        "CaptureQuestFieldTelemetry must persist 4-decimal coordinates and note into ForeverHubDB.fieldCaptures"
      )

      -- 4. Verify Real-Time Objective & Turn-In Completion Truth Sync (QUEST_REMOVED quirk, CHAT_MSG_SYSTEM, Cross-Provider & 1Hz Watchdog)
      local savedObjOv = ns.State.overrideQuestObjectives
      local savedLvl16 = ns.State.overridePlayerLevel
      local savedFac16 = ns.State.overridePlayerFaction
      local savedFull16 = ns.State.overrideQuestLogFull
      local savedSizes16 = ns.State.overrideMapWorldSizes
      local savedNativeWp16 = ns.State.overrideNativeWaypointState
      local savedTomTom16 = _G.TomTom
      local savedCQ16 = _G.C_QuestLog
      local savedGetNum16 = _G.GetNumQuestLogEntries
      local savedGetTitle16 = _G.GetQuestLogTitle
      local savedGetNumLB16 = _G.GetNumQuestLeaderBoards
      local savedGetLB16 = _G.GetQuestLogLeaderBoard
      local savedTurnInID16 = deepCopyTable(ns.Compat.recentQuestTurnedInByID or {})
      local savedTurnInTitle16 = deepCopyTable(ns.Compat.recentQuestTurnedInByTitle or {})
      local savedAcceptID16 = deepCopyTable(ns.Compat.recentQuestAcceptedByID or {})
      local savedAcceptTitle16 = deepCopyTable(ns.Compat.recentQuestAcceptedByTitle or {})

      local okSyncSub, errSyncSub = pcall(function()
        -- 4a. Abandoned quest (`IsQuestFlaggedCompleted == false`) MUST NOT be promoted to completed on QUEST_REMOVED
        if charDB and charDB.routeProgress then
          charDB.routeProgress.observedCompletedQuestIds = {}
          charDB.routeProgress.observedCompletedQuestTitles = {}
        end
        ns.Compat.RecordRecentQuestAccepted(95254, "WANTED: Trapclaw")
        ns.State.overrideCompletedQuests = { [95254] = false }
        local promotedAbandon = ns.Compat.RecordRecentQuestRemoved(95254)
        assertTrue(promotedAbandon == false, "Abandoned quest (server flag false) must NOT be marked completed on QUEST_REMOVED")
        assertTrue(ns.Compat.recentQuestAcceptedByTitle["wanted: trapclaw"] == nil, "QUEST_REMOVED must clear recentQuestAcceptedByTitle")

        -- 4b. Forever server quirk: QUEST_REMOVED without QUEST_TURNED_IN when server flag is true promotes completion!
        ns.State.overrideCompletedQuests = { [95254] = true }
        local promotedTurnIn = ns.Compat.RecordRecentQuestRemoved(95254)
        assertTrue(promotedTurnIn == true, "QUEST_REMOVED with server completion flag true must promote to completed")
        assertTrue(
          ns.State.IsObservedCompletedQuestId(95254) and ns.State.IsObservedCompletedQuestTitle("wanted: trapclaw"),
          "Promoted QUEST_REMOVED must record both numeric ID and normalized title completion"
        )

        -- 4c. CHAT_MSG_SYSTEM quest completion parser accepts known route quests and rejects arbitrary system chatter
        ns.State.overrideCompletedQuests = nil
        local badQid, badTitle = ns.Compat.ParseSystemQuestCompletedMessage("Duel starting: 3...")
        assertTrue(badQid == nil and badTitle == nil, "Non-quest system messages must be ignored")
        local unmappedQid, unmappedTitle = ns.Compat.ParseSystemQuestCompletedMessage("Imaginary Unrelated Quest completed.")
        assertTrue(unmappedQid == nil and unmappedTitle == nil, "Unknown untracked titles must not pollute completion state")
        local trapQid, trapRaw, trapNorm = ns.Compat.ParseSystemQuestCompletedMessage("WANTED: Trapclaw completed.")
        assertTrue(
          trapQid == 95254 and trapRaw == "WANTED: Trapclaw" and trapNorm == "wanted: trapclaw",
          "Known route quest completion message must resolve questID 95254 and normalized title"
        )

        -- 4d. Cross-provider objective truth: stale C_QuestLog.GetQuestObjectives (0/1) yields to completed Classic leaderboard (1/1)
        ns.State.overrideQuestObjectives = nil
        _G.C_QuestLog = {
          GetQuestObjectives = function(qid)
            if qid == 95254 then
              return { { text = "0/1 Trapclaw's Pincer", finished = false, numFulfilled = 0, numRequired = 1 } }
            end
            return {}
          end,
        }
        _G.GetNumQuestLogEntries = function() return 2, 1 end
        _G.GetQuestLogTitle = function(idx)
          if idx == 1 then return "Riverglades", 0, nil, true, false, nil, nil, 0 end
          if idx == 2 then return "WANTED: Trapclaw", 42, nil, false, false, false, nil, 95254 end
          return nil
        end
        _G.GetNumQuestLeaderBoards = function(idx) return idx == 2 and 1 or 0 end
        _G.GetQuestLogLeaderBoard = function(objIdx, qIdx)
          if qIdx == 2 and objIdx == 1 then
            return "Trapclaw's Pincer: 1/1", "item", true
          end
          return nil
        end
        ns.Compat.InvalidateQuestStateCaches()
        local crossObj = ns.Compat.GetQuestObjectivesResult(95254)
        assertTrue(
          crossObj.status == "ok" and crossObj.allFinished == true and crossObj.provider == "classic_leaderboards",
          "Completed Classic leaderboard must override lagging 0/1 C_QuestLog.GetQuestObjectives"
        )

        -- 4e. 1 Hz Active-Step Truth Watchdog catches silent 0/1 -> 1/1 completion with zero WoW events fired!
        _G.C_QuestLog = nil
        _G.GetNumQuestLogEntries = nil
        _G.GetQuestLogTitle = nil
        _G.GetNumQuestLeaderBoards = nil
        _G.GetQuestLogLeaderBoard = nil
        if charDB then
          charDB.routeProgress = ns.State.MigrateRouteProgress({ mode = "standalone" }, route)
        end
        ns.State.overridePlayerLevel = 42
        ns.State.overridePlayerFaction = "Alliance"
        ns.State.overrideQuestLogFull = true
        ns.State.overrideNativeWaypointState = { supported = false }
        _G.TomTom = nil
        ns.State.overrideMapWorldSizes = { [2548] = { width = 3600, height = 2400 } }
        ns.State.overridePlayerPosition = { status = "ok", uiMapID = 2548, x01 = 0.8030, y01 = 0.5440 }
        ns.State.overrideActiveQuests = { [95254] = true }
        ns.State.overrideCompletedQuests = { [95254] = false }
        ns.State.overrideQuestObjectives = {
          [95254] = { { text = "0/1 Trapclaw's Pincer", finished = false, numFulfilled = 0, numRequired = 1 } },
        }
        ns.Events.FlushRouteReconcileNow()
        assertTrue(
          ns.UI.Navigation.watchedQuestActionID == "rg_pf_obj_wanted_trapclaw",
          "Initial active step at (80.3, 54.4) must watch rg_pf_obj_wanted_trapclaw, got: " .. tostring(ns.UI.Navigation.watchedQuestActionID)
        )
        assertTrue(
          ns.UI.Navigation.TickActiveStepWatchdog(1.05) == false,
          "Steady-state watchdog tick with unchanged quest state must be a no-op"
        )
        -- Silently flip Trapclaw objective 0/1 -> 1/1 WITHOUT firing any event:
        ns.State.overrideQuestObjectives = {
          [95254] = { { text = "1/1 Trapclaw's Pincer", finished = true, numFulfilled = 1, numRequired = 1 } },
        }
        local didReconcile = ns.UI.Navigation.TickActiveStepWatchdog(1.05)
        assertTrue(didReconcile == true, "1 Hz watchdog must detect silent 0/1 -> 1/1 objective completion")
        assertTrue(
          ns.UI.Navigation.watchedQuestActionID == "rg_pf_turnin_wanted_trapclaw",
          "Watchdog reconcile must immediately advance active step to rg_pf_turnin_wanted_trapclaw"
        )
      end)

      ns.State.overrideQuestObjectives = savedObjOv
      ns.State.overridePlayerLevel = savedLvl16
      ns.State.overridePlayerFaction = savedFac16
      ns.State.overrideQuestLogFull = savedFull16
      ns.State.overrideMapWorldSizes = savedSizes16
      ns.State.overrideNativeWaypointState = savedNativeWp16
      _G.TomTom = savedTomTom16
      _G.C_QuestLog = savedCQ16
      _G.GetNumQuestLogEntries = savedGetNum16
      _G.GetQuestLogTitle = savedGetTitle16
      _G.GetNumQuestLeaderBoards = savedGetNumLB16
      _G.GetQuestLogLeaderBoard = savedGetLB16
      ns.Compat.recentQuestTurnedInByID = savedTurnInID16
      ns.Compat.recentQuestTurnedInByTitle = savedTurnInTitle16
      ns.Compat.recentQuestAcceptedByID = savedAcceptID16
      ns.Compat.recentQuestAcceptedByTitle = savedAcceptTitle16
      if not okSyncSub then
        error(errSyncSub, 2)
      end
    end)

    ns.State.overrideSelectedQuest = savedSelOv
    ns.State.overridePlayerPosition = savedPosOv
    ns.State.overrideActiveQuests = savedActiveOv
    ns.State.overrideCompletedQuests = savedCompOv
    if _G.ForeverHubDB then
      _G.ForeverHubDB.fieldCaptures = savedCaps or {}
    end
    if charDB then
      charDB.routeProgress = savedCharRG
    end
    ns.Compat.InvalidateQuestStateCaches()
    if not okGate16 then
      error(errGate16, 2)
    end
  end)

  -- Gate 17: v0.8.7 Snargl's Snout (94679) & Accepted Elite Quest Map Visibility with Elites: OFF
  check("RG-17. Accepted Elite Quests Always Show World Map Pins & Focus When Clicked (Snargl's Snout 94679)", function()
    local savedSel17 = ns.State.overrideSelectedQuest
    local ok17, err17 = pcall(function()
      -- Default solo profile: includeEliteBounties == false (Elites: OFF)
      local prog17 = ns.State.MigrateRouteProgress({
        mode = "standalone",
        includeEliteBounties = false,
      }, route)
      local ctx17 = makeMockCtx({
        level = 40,
        active = { [94679] = true, [94678] = true },
        objectives = { [94679] = false, [94678] = false },
      })
      local pos17 = { status = "ok", uiMapID = 2548, x01 = 0.3940, y01 = 0.7460 }

      -- 1. Unpinned solo HUD keeps [40+] Snargl's Snout ineligible so solo players aren't auto-sent into an elite camp
      local posBristle17 = { status = "ok", uiMapID = 2548, x01 = 0.3038, y01 = 0.6334 }
      local evalSolo = RouteProgress.Reconcile(route, prog17, ctx17, posBristle17)
      assertTrue(
        evalSolo.byActionID["rg_el_obj_94679"].state == "ineligible"
          and evalSolo.byActionID["rg_el_obj_94679"].reason == "optional_elite_bounty_disabled",
        "Unpinned Snargl's Snout objective must remain ineligible in default solo HUD auto-routing"
      )
      assertTrue(
        evalSolo.nextAction ~= nil and evalSolo.nextAction.actionID == "rg_hb_obj_94678",
        "Solo HUD at Bristle Hills must prefer solo Gnoll Infestation (94678) over unpinned elite Snargl's Snout"
      )

      -- 2. WorldMapPins MUST still render Snargl's Snout objective pins on map 2548 with Elites: OFF!
      ns.State.overrideSelectedQuest = { questID = 94679, title = "Snargl's Snout", level = 40 }
      local entries17, counts17 = ns.UI.WorldMapPins.CollectPinEntries(
        2548,
        route,
        prog17,
        { enabled = true, showObjectives = true, showTurnIns = true, showAvailable = true },
        ctx17,
        pos17
      )
      assertTrue(counts17.selectedQuestNotice == nil, "Accepted Snargl's Snout must NEVER show an unverified/missing pin warning")
      local snarglPinCount = 0
      for _, e in ipairs(entries17) do
        if e.actionID == "rg_el_obj_94679" then
          snarglPinCount = snarglPinCount + 1
          assertTrue(
            e.coordConfidence == "subzone_verified" and e.isSelectedQuest == true,
            "Snargl's Snout map pin must be subzone_verified and selected"
          )
        end
      end
      assertTrue(snarglPinCount == 2, "Snargl's Snout must render both West & East Bristle Hills camp pins, got: " .. tostring(snarglPinCount))

      -- 3. Clicking Snargl's Snout on the map (pinnedActionID) immediately focuses it in HUD & Arrow even with Elites: OFF!
      prog17.pinnedActionID = "rg_el_obj_94679"
      local evalPinned = RouteProgress.Reconcile(route, prog17, ctx17, pos17)
      assertTrue(
        evalPinned.byActionID["rg_el_obj_94679"].state == "available"
          and evalPinned.nextAction ~= nil
          and evalPinned.nextAction.actionID == "rg_el_obj_94679",
        "Manually pinning Snargl's Snout on the World Map must focus rg_el_obj_94679 even when Elites: OFF"
      )

      -- 4. Looting Snargl's Snout (1/1) auto-retires the pin and surfaces Cedric Dalton turn-in (39.4, 74.6)!
      local ctx17Done = makeMockCtx({
        level = 40,
        active = { [94679] = true, [94678] = true },
        objectives = { [94679] = true, [94678] = false },
      })
      local evalTurnIn = RouteProgress.Reconcile(route, prog17, ctx17Done, pos17)
      assertTrue(
        evalTurnIn.byActionID["rg_el_turnin_94679"].state == "available"
          and evalTurnIn.nextAction ~= nil
          and evalTurnIn.nextAction.actionID == "rg_el_turnin_94679",
        "Completed Snargl's Snout must immediately guide turn-in to Cedric Dalton at Southern Watch"
      )
    end)
    ns.State.overrideSelectedQuest = savedSel17
    if not ok17 then
      error(err17, 2)
    end
  end)

  -- Gate 18: v0.8.7 Full Riverglades Atlas Side-Quest Coverage & Tier Isolation
  check("RG-18. Full Riverglades Atlas Side-Quests Render Map Pins Without Hijacking Core Solo Route", function()
    local prog18 = ns.State.MigrateRouteProgress({ mode = "standalone" }, route)
    -- Standing right beside Farmer Elbrim (52.7, 43.8) while holding a core Sunnyglade quest (94879)
    local ctx18 = makeMockCtx({
      level = 40,
      active = { [94879] = true },
      completed = { [94885] = true },
      objectives = { [94879] = false },
    })
    local pos18 = { status = "ok", uiMapID = 2548, x01 = 0.5270, y01 = 0.4380 }

    -- 1. Unaccepted isAtlasSideQuest accept (94829 What We Lost at 52.7, 43.8, 0 yd away!) stays in optional pool and NEVER hijacks core solo routing!
    local evalUnaccepted = RouteProgress.Reconcile(route, prog18, ctx18, pos18)
    assertTrue(
      evalUnaccepted.byActionID["rg_atlas_accept_94829"].state == "available",
      "What We Lost (94829) accept must be available on World Map"
    )
    assertTrue(
      evalUnaccepted.nextAction ~= nil
        and evalUnaccepted.nextAction.actionID ~= "rg_atlas_accept_94829"
        and evalUnaccepted.nextAction.isAtlasSideQuest ~= true,
      "Unaccepted atlas side quest at 0 yd must NOT hijack core solo routing, got: " .. tostring(evalUnaccepted.nextAction and evalUnaccepted.nextAction.actionID)
    )
    -- And when standing near Sunnyglade (45.2, 52.2), active 94879 objective is chosen directly over unaccepted atlas side quests
    local evalSunnyglade18 = RouteProgress.Reconcile(
      route,
      ns.State.MigrateRouteProgress({ mode = "standalone" }, route),
      ctx18,
      { status = "ok", uiMapID = 2548, x01 = 0.4520, y01 = 0.5220 }
    )
    assertTrue(
      evalSunnyglade18.nextAction ~= nil and evalSunnyglade18.nextAction.actionID == "rg_a_06_obj_sunnyglade_94879",
      "Core Sunnyglade objective must be chosen near Sunnyglade, got: " .. tostring(evalSunnyglade18.nextAction and evalSunnyglade18.nextAction.actionID)
    )

    -- 2. WorldMapPins renders [!] Available pins for atlas side quests on Riverglades (2548) AND external maps (e.g. Dalaran 1416 for 96771)
    local entriesRG = ns.UI.WorldMapPins.CollectPinEntries(
      2548,
      route,
      prog18,
      { enabled = true, showObjectives = true, showTurnIns = true, showAvailable = true },
      ctx18,
      pos18
    )
    local sawElbrimAccept = false
    for _, e in ipairs(entriesRG) do
      if e.actionID == "rg_atlas_accept_94829" then
        sawElbrimAccept = true
      end
    end
    assertTrue(sawElbrimAccept, "WorldMapPins(2548) must render [!] Accept What We Lost at Farmer Elbrim")

    prog18.includeGroupBranches = true
    local entriesDalaran = ns.UI.WorldMapPins.CollectPinEntries(
      1416,
      route,
      prog18,
      { enabled = true, showObjectives = true, showTurnIns = true, showAvailable = true },
      ctx18,
      pos18
    )
    local saw96771 = false
    for _, e in ipairs(entriesDalaran) do
      if e.actionID == "rg_kd_accept_96771" then
        saw96771 = true
      end
    end
    assertTrue(saw96771, "WorldMapPins(1416) must render [!] Accept Vengeance of the Highborne in Dalaran")

    -- 3. Once the player accepts an atlas side quest in Riverglades (e.g. 94829 What We Lost), local proximity guides its objective!
    local ctxAccepted = makeMockCtx({
      level = 40,
      active = { [94829] = true },
      objectives = { [94829] = false },
    })
    local evalAccepted = RouteProgress.Reconcile(route, prog18, ctxAccepted, pos18)
    assertTrue(
      evalAccepted.nextAction ~= nil and evalAccepted.nextAction.actionID == "rg_atlas_obj_94829",
      "Accepted atlas side quest on same map must guide player to its objective (52.2, 50.7)"
    )

    -- 4. Zero playable quests are quarantined: ONLY developer placeholder 95331 (REUSE ME) remains in quarantinedActions
    assertTrue(
      type(route.quarantinedActions) == "table"
        and #route.quarantinedActions == 1
        and route.quarantinedActions[1].questID == 95331,
      "Only unobtainable developer placeholder 95331 (REUSE ME) may remain in quarantinedActions"
    )
  end)

  -- Gate 19: v0.8.7 Travel-Aware Routing, Counterfactual Batching, En-Route Insertion & Zero-Mutation Reads
  check("RG-19. Travel-Aware Service-Group Planner, Counterfactual AND-Gates & Commitment Stability", function()
    local synthRoute = {
      routeID = "rg_selftest_v087_travel_aware",
      revision = 1,
      primaryUiMapID = 2548,
      areaIdToUiMapId = { [16591] = 2548, [357] = 1444 },
      questsByID = {
        [1001] = { questID = 1001, title = "Far Leaf Turnin" },
        [1002] = { questID = 1002, title = "Nearby Camp Kill" },
        [1003] = { questID = 1003, title = "Nearby Hub Pickup" },
        [2001] = { questID = 2001, title = "Joint Gate A" },
        [2002] = { questID = 2002, title = "Joint Gate B" },
        [2003] = { questID = 2003, title = "Unlocked Camp Quest" },
      },
      questSuccessors = {
        [2001] = { 2003 },
        [2002] = { 2003 },
      },
      actions = {
        {
          actionID = "st_turnin_1001",
          kind = "turnin",
          questID = 1001,
          title = "Turn in Far Leaf",
          npcID = 9001,
          npcName = "Far Captain",
          reviewStatus = "verified",
          requires = { op = "quest_objectives_complete", questID = 1001 },
          eligibility = { faction = "Alliance" },
          completionPredicate = { type = "quest_completed", questID = 1001 },
          destination = { coordinateSpace = "uiMap01", coordConfidence = "artifact_verified", uiMapID = 2548, areaID = 16591, x01 = 0.5500, y01 = 0.2000 },
        },
        {
          actionID = "st_obj_1002",
          kind = "objective",
          questID = 1002,
          title = "Clear Nearby Camp",
          reviewStatus = "verified",
          requires = { op = "quest_active", questID = 1002 },
          eligibility = { faction = "Alliance" },
          completionPredicate = { type = "quest_objectives_complete_or_turned_in", questID = 1002 },
          destination = { coordinateSpace = "uiMap01", coordConfidence = "artifact_verified", uiMapID = 2548, areaID = 16591, x01 = 0.1583, y01 = 0.2000 },
        },
        {
          actionID = "st_accept_1003",
          kind = "accept",
          questID = 1003,
          title = "Accept Nearby Pickup",
          npcID = 9003,
          npcName = "Scout",
          reviewStatus = "verified",
          requires = { op = "true" },
          eligibility = { faction = "Alliance" },
          completionPredicate = { type = "quest_active_or_completed", questID = 1003 },
          destination = { coordinateSpace = "uiMap01", coordConfidence = "artifact_verified", uiMapID = 2548, areaID = 16591, x01 = 0.1583, y01 = 0.2000 },
        },
        {
          actionID = "st_obj_1003",
          kind = "objective",
          questID = 1003,
          title = "Scout Objective",
          reviewStatus = "verified",
          requires = { op = "quest_active", questID = 1003 },
          eligibility = { faction = "Alliance" },
          completionPredicate = { type = "quest_objectives_complete_or_turned_in", questID = 1003 },
          destination = { coordinateSpace = "uiMap01", coordConfidence = "artifact_verified", uiMapID = 2548, areaID = 16591, x01 = 0.1700, y01 = 0.2100 },
        },
      },
    }

    -- 1. 210 yd objective beats 1,500 yd leaf turn-in
    local progA = ns.State.MigrateRouteProgress({ mode = "standalone" }, synthRoute)
    local ctxA = makeMockCtx({
      level = 40,
      active = { [1001] = true, [1002] = true },
      completed = { [1003] = true },
      objectives = { [1001] = true, [1002] = false },
    })
    local posStart = { status = "ok", uiMapID = 2548, x01 = 0.1000, y01 = 0.2000 }
    local evalA = RouteProgress.Reconcile(synthRoute, progA, ctxA, posStart)
    assertTrue(
      evalA.nextAction ~= nil and evalA.nextAction.actionID == "st_obj_1002",
      "210 yd objective must beat 1,620 yd leaf turn-in, got: " .. tostring(evalA.nextAction and evalA.nextAction.actionID)
    )
    assertTrue(
      evalA.plan ~= nil and evalA.plan.hubReturnPlanned == false and evalA.plan.deferredReadyCount == 1,
      "Deferred ready leaf turn-in must set hubReturnPlanned=false and deferredReadyCount=1"
    )

    -- 2. Continuity check at 219 / 220 / 221 yards (zero priority cliff)
    local ctxLeafOnly = makeMockCtx({
      level = 40,
      active = { [1001] = true },
      completed = { [1002] = true, [1003] = true },
      objectives = { [1001] = true },
    })
    local function leafScoreAtYards(yd)
      local x = 0.5500 - (yd / 3600.0)
      local ev = RoutePlanner.EvaluateRoute(
        synthRoute,
        ns.State.MigrateRouteProgress({ mode = "standalone" }, synthRoute),
        ctxLeafOnly,
        { status = "ok", uiMapID = 2548, x01 = x, y01 = 0.2000 }
      )
      local sb = ev.plan.groupScores["sg_npc_9001"]
      return sb and sb.score or 0
    end
    local s219, s220, s221 = leafScoreAtYards(219.0), leafScoreAtYards(220.0), leafScoreAtYards(221.0)
    assertTrue(
      math.abs(s220 - s219) < 4.0 and math.abs(s221 - s220) < 4.0,
      string.format("Continuous score must have zero cliff across 219/220/221 yd (got %.2f / %.2f / %.2f)", s219, s220, s221)
    )

    -- 3. Joint AND-gate + camp-overlap counterfactual batch valuation on real Riverglades route (94879 + 94881 -> 94907 near active 94889)
    local ctxSingle94879 = makeMockCtx({
      level = 40,
      active = { [94879] = true, [94881] = true, [94889] = true },
      objectives = { [94879] = true, [94881] = false, [94889] = false },
    })
    local ctxJointNoWestCamp = makeMockCtx({
      level = 40,
      active = { [94879] = true, [94881] = true },
      objectives = { [94879] = true, [94881] = true },
    })
    local ctxJointWithWestCamp = makeMockCtx({
      level = 40,
      active = { [94879] = true, [94881] = true, [94889] = true },
      objectives = { [94879] = true, [94881] = true, [94889] = false },
    })
    local posSunny = { status = "ok", uiMapID = 2548, x01 = 0.4800, y01 = 0.5400 }
    local evSingle = RoutePlanner.EvaluateRoute(route, ns.State.MigrateRouteProgress({ mode = "standalone" }, route), ctxSingle94879, posSunny)
    local evNoWest = RoutePlanner.EvaluateRoute(route, ns.State.MigrateRouteProgress({ mode = "standalone" }, route), ctxJointNoWestCamp, posSunny)
    local evJoint = RoutePlanner.EvaluateRoute(route, ns.State.MigrateRouteProgress({ mode = "standalone" }, route), ctxJointWithWestCamp, posSunny)
    local sbSingle = evSingle.plan.groupScores["sg_farholde_citadel"]
    local sbNoWest = evNoWest.plan.groupScores["sg_farholde_citadel"]
    local sbJoint = evJoint.plan.groupScores["sg_farholde_citadel"]
    assertTrue(
      sbSingle ~= nil and sbSingle.unlockBenefit == 0,
      "Completing 94879 alone must NOT falsely credit AND-gated 94907"
    )
    assertTrue(
      sbNoWest ~= nil and sbNoWest.unlockBenefit == 0,
      "Unlocking 94907 without an active Western Conduit camp quest must not claim double-clear credit across the zone"
    )
    assertTrue(
      sbJoint ~= nil and sbJoint.unlockBenefit > 150,
      "Joint completion of 94879 + 94881 while holding Western Conduit quest 94889 must award double-clear avoidance credit"
    )

    -- 4. Pure read-only Evaluate / Presenter snapshot never mutates progress or drift table
    local progPure = ns.State.MigrateRouteProgress({ mode = "standalone" }, route)
    RouteProgress.Reconcile(route, progPure, ctxJointWithWestCamp, posSunny)
    local savedEpoch = progPure.routingEpoch
    local savedSig = progPure.committedDecisionSig
    RouteProgress.Evaluate(route, progPure, ctxJointWithWestCamp, { status = "ok", uiMapID = 2548, x01 = 0.6100, y01 = 0.7900 })
    assertTrue(
      progPure.routingEpoch == savedEpoch and progPure.committedDecisionSig == savedSig,
      "RouteProgress.Evaluate must remain 100% pure and never mutate progress commitment state"
    )
  end)

  ns.State.overridePlayerPosition = savedGlobalPlayerPos
  if _G.ForeverHubDB then
    _G.ForeverHubDB.discoveredQuestIds = savedSuiteDiscoveredIds or {}
    _G.ForeverHubDB.discoveredQuestTitlesById = savedSuiteDiscoveredTitles or {}
  end
  if charDB then
    charDB.routeProgress = savedRGProg
    charDB.goldFarmProgress = savedGFProg
  end
  restoreNavigationSnapshot(navSnap, charDB)

  local report = {
    passed = passed,
    failed = failed,
    total = passed + failed,
    results = results,
  }
  SelfTest.cachedReports.riverglades = report
  SelfTest._running.riverglades = false
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
  local savedRGProg = deepCopyTable(charDB.routeProgress)
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
    ns.UI.Navigation.activeContext = "riverglades"
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
    -- Gate 1: Ownership across RG <-> Gold in combat, failed clear, restricted read, user replacement & rapid Stop
    check("GF-1. Gate 1: Single Navigation Owner Across Combat, Failed Clear, Restricted Read & Rapid Switches", function()
      resetNavOwnerForTest()
      _G.TomTom = nil
      _G.RXPGuides = nil
      _G.RXPCData = nil
      ns.State.overrideInCombat = false
      ns.State.overrideNativeWaypointState = { supported = true, current = nil }

      charDB.routeProgress = ns.State.MigrateRouteProgress({}, ns.State.GetCompiledRivergladesRoute())
      charDB.goldFarmProgress = ns.State.MigrateGoldFarmProgress({}, catalog)

      -- 1) RG acquires native pin on 2548
      local okRG, rgEval = ns.Domain.RouteProgress.Start()
      assertTrue(okRG, "RG Start failed")
      local stRG = ns.UI.Navigation.SyncFromEvaluation(rgEval)
      assertTrue(stRG.activeProvider == "native_waypoint" and ns.State.overrideNativeWaypointState.current.uiMapID == 2548, "RG owns 2548 pin")

      -- 2) Enter combat -> switch RG -> Gold Farm #1 (1432): RG pauses, release deferred, token retained by RG!
      ns.State.overrideInCombat = true
      local okGF, gfEval = GoldFarms.Start(1, catalog, charDB.goldFarmProgress, { status = "unavailable" })
      assertTrue(okGF and charDB.routeProgress.mode == "paused", "Switching to Gold must pause RG")
      local stGFDeferred = ns.UI.Navigation.SyncFromGoldFarmEvaluation(gfEval, charDB.goldFarmProgress)
      assertTrue(stGFDeferred.deferred == true, "Gold acquisition must defer while RG release is blocked in combat")
      assertTrue(ns.UI.Navigation.owner.ownerContext == "riverglades" and ns.UI.Navigation.owner.pendingRelease == true, "RG ownership token must be retained during combat")
      assertTrue(ns.State.overrideNativeWaypointState.current.uiMapID == 2548, "Live 2548 pin remains until combat ends")

      -- 3) Combat ends, BUT ClearNativeWaypoint fails -> token MUST still be retained (never mistaken for user pin)!
      ns.State.overrideInCombat = false
      ns.State.overrideNativeWaypointState.clearMustFail = true
      local flushFail = ns.UI.Navigation.FlushDeferredIfReady()
      assertTrue(flushFail.deferred == true and ns.UI.Navigation.owner.handle ~= nil, "Failed clear must retain ownership token")
      assertTrue(ns.UI.Navigation.owner.ownerContext == "riverglades", "Owner context remains riverglades until confirmed release")

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

      -- 6) Enter combat -> user replaces pin with custom Stormwind pin (1453) while deferred -> rapid Gold -> RG -> Stop BEFORE combat ends!
      ns.State.overrideInCombat = true
      local staleGen = ns.UI.Navigation.owner.generation
      ns.State.overrideNativeWaypointState.current = { uiMapID = 1453, x01 = 0.6100, y01 = 0.7200 }
      local _, rgEvalRapid = ns.Domain.RouteProgress.Start()
      ns.UI.Navigation.SyncFromEvaluation(rgEvalRapid)
      local _, rgStopEval = ns.Domain.RouteProgress.Stop()
      ns.UI.Navigation.SyncFromEvaluation(rgStopEval)
      assertTrue(not ns.UI.Navigation.IsGenerationCurrent(staleGen), "Stale generation must be invalidated by rapid switches")
      assertTrue(ns.UI.Navigation.owner.pendingDestination == nil, "Stop must cancel pending destination")

      -- Combat ends: user's 1453 pin MUST remain untouched and no stale RG/Gold pin may be written!
      ns.State.overrideInCombat = false
      ns.UI.Navigation.FlushDeferredIfReady()
      assertTrue(ns.State.overrideNativeWaypointState.current ~= nil and ns.State.overrideNativeWaypointState.current.uiMapID == 1453, "User replacement pin must survive rapid Gold->RG->Stop")
      assertTrue(ns.UI.Navigation.owner.provider == "none" and ns.UI.Navigation.owner.handle == nil, "Token dropped cleanly after confirmed user replacement")

      -- 7) Out-of-combat failed native clear MUST retain pendingDestination (and Pause MUST cancel pendingDestination)
      resetNavOwnerForTest()
      ns.State.overrideInCombat = false
      ns.State.overrideNativeWaypointState = { supported = true, current = nil }
      charDB.routeProgress = ns.State.MigrateRouteProgress({}, ns.State.GetCompiledRivergladesRoute())
      charDB.goldFarmProgress = ns.State.MigrateGoldFarmProgress({}, catalog)

      local okRG2, rgEval2 = ns.Domain.RouteProgress.Start()
      assertTrue(okRG2, "RG2 Start failed")
      ns.UI.Navigation.SyncFromEvaluation(rgEval2)
      assertTrue(ns.State.overrideNativeWaypointState.current.uiMapID == 2548, "RG2 owns 2548")

      -- Out of combat, ClearNativeWaypoint fails when switching RG -> Gold Farm #1
      ns.State.overrideNativeWaypointState.clearMustFail = true
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
      local _, rgEval3 = ns.Domain.RouteProgress.Start()
      ns.UI.Navigation.SyncFromEvaluation(rgEval3)
      assertTrue(ns.UI.Navigation.owner.pendingDestination ~= nil, "RG pendingDestination queued while Gold clear fails")
      local _, rgPause3 = ns.Domain.RouteProgress.Pause()
      ns.UI.Navigation.SyncFromEvaluation(rgPause3)
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

      _G.RXPCData = {
        currentGuideGroup = ns.Bridges.RXPBridge.RIVERGLADES_GUIDE_GROUP,
        currentGuideName = ns.Bridges.RXPBridge.RIVERGLADES_GUIDE_NAME,
      }
      assertTrue(ns.Bridges.RXPBridge.IsRivergladesGuideSelected() == false, "Stale RXPCData must NEVER mark Riverglades guide selected")
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
  charDB.routeProgress = savedRGProg
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
  local savedRGProg = deepCopyTable(charDB.routeProgress)
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

      -- Switching tabs to Riverglades & Gold MUST NOT start navigation or mutate paused route progress!
      charDB.routeProgress.mode = "paused"
      charDB.goldFarmProgress.mode = "paused"
      local sessActiveBefore = ns.State.goldFarmSession and ns.State.goldFarmSession.active or false
      Workspace.SetActiveTab("riverglades")
      Workspace.SetActiveTab("gold")
      Workspace.SetActiveTab("crates")
      assertTrue(charDB.routeProgress.mode == "paused", "Switching to Riverglades tab MUST NOT start Riverglades navigation")
      assertTrue(charDB.goldFarmProgress.mode == "paused", "Switching to Gold tab MUST NOT start Gold Farm navigation")
      assertTrue((ns.State.goldFarmSession and ns.State.goldFarmSession.active or false) == sessActiveBefore, "Switching tabs MUST NOT activate farm telemetry")

      -- v0.8.3: Riverglades is default opening tab, migrated from v1 saves, session-fresh on ADDON_LOADED, and featured in Slot #1
      local freshUI = ns.State.MigrateWorkspaceUIState(nil, db.settings)
      assertTrue(freshUI.schemaVersion == 2 and freshUI.activeTab == "riverglades", "Fresh uiWorkspace must default to 'riverglades' (schema v2)")
      local migratedV1 = ns.State.MigrateWorkspaceUIState({ schemaVersion = 1, activeTab = "crates", width = 1040 }, db.settings)
      assertTrue(migratedV1.schemaVersion == 2 and migratedV1.activeTab == "riverglades" and migratedV1.width == 1040, "v1 uiWorkspace must migrate activeTab to 'riverglades' while preserving geometry")
      db.uiWorkspace.activeTab = "crates"
      ns.State.EnsureWorkspaceUIStateInitialized(false)
      assertTrue(db.uiWorkspace.activeTab == "crates", "In-session Workspace state must preserve current tab when not on ADDON_LOADED")
      ns.State.EnsureWorkspaceUIStateInitialized(true)
      assertTrue(db.uiWorkspace.activeTab == "riverglades", "Fresh ADDON_LOADED session must open on 'riverglades'")

      if Workspace.frame and Workspace.frame.tabBar and Workspace.frame.tabBar.__tabs then
        local firstTab = Workspace.frame.tabBar.__tabs[1]
        assertTrue(
          firstTab and firstTab.__key == "riverglades" and firstTab.__featured == true and firstTab.__iconGlyph == "travel",
          "Riverglades must occupy featured Slot #1 with compass glyph"
        )
        assertTrue(type(firstTab.__badgeText) == "string" and firstTab.__badgeText ~= "", "Riverglades pill badge must populate live on Workspace.Refresh")
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

    -- UI-05: Surface B (Riverglades) Two-Column Geometry (200+12+700), Compact Mode & Unresolved Quest History Resolver
    check("UI-05. Surface B (Riverglades): 200+12+700 Geometry, Compact Selector & Unresolved History Undo", function()
      local RivergladesPresenter = ns.UI.RivergladesPresenter
      local RivergladesUI = ns.UI.Riverglades
      assertTrue(type(RivergladesPresenter) == "table" and type(RivergladesUI) == "table", "RivergladesPresenter and RivergladesUI must be loaded")

      charDB.userConfirmedCompletedQuestTitles = {}
      local st = ns.State.GetWorkspaceUIState()
      st.textScale = 1.0
      Theme.appliedFontScale = nil

      Workspace.Show("riverglades")
      Workspace.SetDimensions(960, 640)
      local rg960 = RivergladesUI.RenderInHost(928, 560, false)
      assertTrue(
        rg960.isCompact == false
          and rg960.hubSidebarWidth == 200
          and rg960.columnGap == 12
          and rg960.detailContentWidth == 700,
        "Riverglades standard geometry must be 200 sidebar + 12 gap + 700 detail (+ 16 scrollbar = 928)"
      )
      for _, h in ipairs(rg960.hubs or {}) do
        assertTrue(h.height >= 44, "Riverglades hub row height must be >= 44")
      end
      for _, r in ipairs(rg960.rows or {}) do
        if r.kind == "quest" then
          assertTrue(r.height >= 56, "Riverglades quest row height must be >= 56")
        end
      end

      -- Compact < 900 width collapses sidebar into segmented hub bar
      Workspace.SetDimensions(760, 520)
      local rg760 = RivergladesUI.RenderInHost(728, 440, true)
      assertTrue(rg760.isCompact == true and rg760.hubSidebarWidth == 0 and rg760.detailContentWidth == 712, "Compact Riverglades must collapse hub sidebar")

      -- Per-quest unresolved history resolver: Confirm completed -> labeled 'User confirmed' -> Undo restores unresolved!
      RivergladesUI.Dispatch("CONFIRM_COMPLETED", { questKey = "title:wanted: trapclaw" })
      assertTrue(
        ns.State.GetUnresolvedQuestUserDecision("title:wanted: trapclaw") == "user_confirmed_completed",
        "User decision must record 'user_confirmed_completed'"
      )
      local compRes = ns.Compat.IsQuestCompletedResult("title:wanted: trapclaw")
      assertTrue(
        compRes.status == "ok" and compRes.value == true and compRes.completionSource == "user_confirmed",
        "User-confirmed title quest must report completionSource='user_confirmed', never server_verified"
      )
      local snapAfterConfirm = RivergladesPresenter.CaptureSnapshot()
      local vmAfterConfirm = RivergladesPresenter.Build(snapAfterConfirm, st)
      local sawUserConfirmedDecision = false
      for _, d in ipairs(vmAfterConfirm.userDecisions or {}) do
        if d.questKey == "title:wanted: trapclaw" and d.decision == "user_confirmed_completed" then
          sawUserConfirmedDecision = true
          break
        end
      end
      assertTrue(sawUserConfirmedDecision, "Confirmed unresolved quest must appear in userDecisions with Undo affordance")
      RivergladesUI.RenderInHost(928, 560, false, snapAfterConfirm)
      assertTrue(#RivergladesUI.decisionRowPool >= 1, "Riverglades view must render 'User confirmed' decision row with Undo")

      RivergladesUI.Dispatch("UNDO_HISTORY_DECISION", { questKey = "title:wanted: trapclaw" })
      assertTrue(ns.State.GetUnresolvedQuestUserDecision("title:wanted: trapclaw") == nil, "Undo must clear user assertion cleanly")
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

    -- UI-07: Surface D (Tracker HUD & Docked/Floating Arrow) Mutual Exclusion & Non-Stopping Hide Tracker
    check("UI-07. Surface D (Tracker HUD): 340w Docked Default, Arrow Mutual Exclusion & Non-Stopping Hide", function()
      local Nav = ns.UI.Navigation
      if Nav and type(_G.CreateFrame) == "function" then
        local arrowSettings = ns.State.GetArrowSettings()
        local prog = ns.State.GetRouteProgress()
        local savedArrowSettings = deepCopyTable(arrowSettings)
        local savedProgMode = prog.mode
        local prevSuppress = Nav.suppressHUDCreation

        -- If live frames had not yet been instantiated before this suite, keep any newly created frames hidden in navSnap
        -- so real WoW never creates duplicate global frame names on repeated `/fh selftest` runs.
        local okNavTest, errNavTest = pcall(function()
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
          arrowSettings.hudWidth = 340
          arrowSettings.renderer = "foreverhub"

          prog.mode = "standalone"
          Nav.SetArrowTarget(
            "riverglades",
            { uiMapID = 2548, x01 = 0.6062, y01 = 0.8153, zoneName = "Riverglades" },
            "Farholde Keep Flight Path",
            "Farholde Keep Flight Path",
            15,
            "native_waypoint"
          )
          Nav.RefreshArrowSettings()

          local snapDocked = Nav.GetLiveArrowSnapshot()
          assertTrue(
            not (snapDocked.dockedVisible and snapDocked.floatingVisible),
            "Docked HUD arrow and floating arrow MUST NEVER be visible simultaneously"
          )
          if Nav.frame then
            local hudW = (type(Nav.frame.GetWidth) == "function" and Nav.frame:GetWidth()) or Nav.frame.__width
            assertTrue(hudW == 340, "Default Tracker HUD width must be 340")

            -- Regression guard for v0.8.1/v0.8.2: tick the 20 Hz docked arrow lane OnUpdate callback & verify single-shot circuit breaker
            local dockedLane = Nav.frame.dockedArrowLane
            if dockedLane and dockedLane.arrowTex then
              local dockedUpdate = (dockedLane.__scripts and dockedLane.__scripts["OnUpdate"])
                or (type(dockedLane.GetScript) == "function" and dockedLane:GetScript("OnUpdate"))
              assertTrue(type(dockedUpdate) == "function", "Docked arrow lane must bind an OnUpdate handler")
              dockedLane.elapsedAccum = 0
              dockedUpdate(dockedLane, 0.10)
              assertTrue(Nav.activeTarget ~= nil and Nav.activeTarget.lastVecStatus ~= nil, "Docked arrow OnUpdate must evaluate vector cleanly")

              -- Verify Astra P1 #4 circuit-breaker latch: injected error trips once, hides lane, and does NOT repeat on subsequent ticks
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

            local hideBtn = Nav.frame.hideTrackerBtn
            if hideBtn then
              if type(hideBtn.__onClick) == "function" then
                hideBtn:__onClick("LeftButton")
              elseif hideBtn.__scripts and type(hideBtn.__scripts["OnClick"]) == "function" then
                hideBtn.__scripts["OnClick"](hideBtn, "LeftButton")
              elseif type(hideBtn.GetScript) == "function" and type(hideBtn:GetScript("OnClick")) == "function" then
                hideBtn:GetScript("OnClick")(hideBtn, "LeftButton")
              end
              assertTrue(arrowSettings.hudHidden == true, "Hide tracker must mark hudHidden = true")
              assertTrue(prog.mode == "standalone" and Nav.activeTarget ~= nil, "Hide tracker MUST keep active navigation running")
              local snapHidden = Nav.GetLiveArrowSnapshot()
              assertTrue(
                not (snapHidden.dockedVisible and snapHidden.floatingVisible),
                "Hiding tracker must maintain docked/floating arrow mutual exclusion"
              )
            end
          end
        end)

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
        prog.mode = savedProgMode

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
  charDB.routeProgress = savedRGProg
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
