local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.UI = ns.UI or {}

local Theme = ns.UI.Theme

local CommandDeckPresenter = {}
ns.UI.CommandDeckPresenter = CommandDeckPresenter

CommandDeckPresenter.NORTH_STAR_SUBTITLE =
  "Best supported action available for this character, with costs and limitations visible."

local CROWDED_COOLDOWN_SECONDS = 1800 -- 30 minutes session suppression when user clicks "Too crowded"

local function formatMoneyPlainOrRich(copper, opts)
  if Theme and type(Theme.FormatMoney) == "function" then
    return Theme.FormatMoney(copper, opts)
  end
  if type(copper) ~= "number" then
    return "Unpriced"
  end
  return tostring(math.floor(copper)) .. "c"
end

local function normalizeFaction(fac)
  local s = string.upper(tostring(fac or ""))
  if s == "ALLIANCE" or s == "A" then
    return "Alliance"
  elseif s == "HORDE" or s == "H" then
    return "Horde"
  end
  return "Neutral"
end

function CommandDeckPresenter.CaptureSnapshot(overrides)
  overrides = type(overrides) == "table" and overrides or {}

  local nowSec = tonumber(overrides.nowSeconds)
  if not nowSec then
    local srv = ns.Compat and ns.Compat.GetServerTimeSafe and ns.Compat.GetServerTimeSafe() or nil
    nowSec = (type(srv) == "table" and tonumber(srv.epochSec) or tonumber(srv))
      or (ns.Compat and ns.Compat.NowSeconds and math.floor(ns.Compat.NowSeconds()))
      or 0
  end

  local level = tonumber(overrides.level)
    or (ns.Compat and ns.Compat.GetPlayerLevel and ns.Compat.GetPlayerLevel())
    or 1
  level = math.max(1, math.floor(level))

  local faction = overrides.faction
    or (ns.Compat and ns.Compat.GetPlayerFactionString and ns.Compat.GetPlayerFactionString())
    or "Alliance"
  faction = normalizeFaction(faction)

  local classInfo = (ns.Compat and ns.Compat.GetPlayerClassAndRace and ns.Compat.GetPlayerClassAndRace()) or {}
  local classToken = tostring(overrides.classToken or classInfo.classToken or "UNKNOWN")
  local classLabel = tostring(overrides.classLabel or classInfo.className or classToken)

  local inCombat = (overrides.inCombat ~= nil) and (overrides.inCombat == true)
    or (ns.Compat and ns.Compat.IsInCombat and ns.Compat.IsInCombat())
    or false

  local clientLocale = tostring(
    overrides.clientLocale
      or (ns.Compat and ns.Compat.GetClientLocale and ns.Compat.GetClientLocale())
      or "enUS"
  )

  local hasAuctionator = (overrides.hasAuctionator ~= nil) and (overrides.hasAuctionator == true)
    or (ns.Providers and ns.Providers.Auctionator and ns.Providers.Auctionator.IsAvailable and ns.Providers.Auctionator.IsAvailable())
    or false

  -- Learned professions snapshot (explicitly provided or discovered from State):
  local profSnap = nil
  if type(overrides.professionSnapshot) == "table" then
    profSnap = overrides.professionSnapshot
  elseif ns.State and type(ns.State.GetProfessionSnapshot) == "function" then
    profSnap = ns.State.GetProfessionSnapshot()
  end

  local snapshotStatus = tostring(
    overrides.professionSnapshotStatus
      or (type(profSnap) == "table" and profSnap.status)
      or ((type(overrides.learnedSkills) == "table") and "COMPLETE" or "PENDING")
  )

  local learnedSkills = overrides.learnedSkills
  if type(learnedSkills) ~= "table" then
    if type(profSnap) == "table" and snapshotStatus == "COMPLETE" and type(profSnap.baseRanks) == "table" then
      learnedSkills = profSnap.baseRanks
    elseif ns.State and type(ns.State.learnedProfessionSkills) == "table" and snapshotStatus == "COMPLETE" then
      learnedSkills = ns.State.learnedProfessionSkills
    end
  end

  local deckEvalOpts = {
    nowSeconds = nowSec,
    level = level,
    faction = faction,
    inCombat = inCombat,
    clientLocale = clientLocale,
    liquidCopper = overrides.liquidCopper,
    hasBasicMount = overrides.hasBasicMount,
    trainerQuoteCopper = overrides.trainerQuoteCopper,
    explicitUserReserveCopper = overrides.explicitUserReserveCopper,
    freeBagSlots = overrides.freeBagSlots,
    learnedSkills = learnedSkills,
    inventorySnapshot = overrides.inventorySnapshot
      or (ns.Providers and ns.Providers.Inventory and ns.Providers.Inventory.GetAggregatedSnapshot and ns.Providers.Inventory.GetAggregatedSnapshot())
      or {},
    orderedReservations = overrides.orderedReservations
      or (ns.State and ns.State.GetOrderedReservations and ns.State.GetOrderedReservations())
      or {},
    observedLotsByItemID = overrides.observedLotsByItemID,
    liveSellPriceLookup = overrides.liveSellPriceLookup,
    allowStaticWhenClientUnavailable = overrides.allowStaticWhenClientUnavailable,
    atAuctionHub = overrides.atAuctionHub,
  }

  local rung1Deck = nil
  if ns.Domain and ns.Domain.VendorArbitrage and type(ns.Domain.VendorArbitrage.EvaluateCharacterRung1Deck) == "function" then
    rung1Deck = ns.Domain.VendorArbitrage.EvaluateCharacterRung1Deck(deckEvalOpts)
  end

  local reserveSnap = (rung1Deck and rung1Deck.reserveSnapshot)
    or (ns.Domain and ns.Domain.Reserves and ns.Domain.Reserves.EvaluateCharacterReserves and ns.Domain.Reserves.EvaluateCharacterReserves(deckEvalOpts))
    or { status = "unavailable", investableCopper = 0, protectedCopperNow = 0 }

  -- Gather compiled GoldFarms catalog & filter strictly by faction + level bracket:
  local goldCatalog = overrides.goldCatalog
    or (ns.State and ns.State.GetCompiledGoldFarms and ns.State.GetCompiledGoldFarms())
    or ns.GoldFarmsData
  local catalogFaction = "Alliance"
  if goldCatalog and goldCatalog.meta and type(goldCatalog.meta.faction) == "string" then
    catalogFaction = normalizeFaction(goldCatalog.meta.faction)
  elseif goldCatalog and goldCatalog.meta and string.find(string.lower(tostring(goldCatalog.meta.catalogID or "")), "horde", 1, true) then
    catalogFaction = "Horde"
  end

  local eligibleFarms = {}
  local sourceVerifiedRoutes = {}
  local wrongFactionSkippedCount = 0
  local levelBracketSkippedCount = 0
  if goldCatalog and type(goldCatalog.farms) == "table" then
    for _, farm in ipairs(goldCatalog.farms) do
      if type(farm) == "table" and type(farm.farmID) == "string" then
        local farmFac = normalizeFaction(farm.faction or catalogFaction)
        local minLvl = tonumber(farm.minCharacterLevel or farm.recommendedMinLevel) or 38
        local maxLvl = tonumber(farm.maxCharacterLevel or farm.recommendedMaxLevel) or 60
        if farmFac ~= "Neutral" and farmFac ~= faction then
          wrongFactionSkippedCount = wrongFactionSkippedCount + 1
        elseif level < minLvl or level > maxLvl then
          levelBracketSkippedCount = levelBracketSkippedCount + 1
        else
          table.insert(eligibleFarms, farm)
        end
      end
    end
  end
  if goldCatalog and type(goldCatalog.expandedRoutes) == "table" then
    for _, er in ipairs(goldCatalog.expandedRoutes) do
      if type(er) == "table" and type(er.farmID) == "string" then
        local erFac = normalizeFaction(er.faction)
        local minLvl = tonumber(er.minCharacterLevel or er.recommendedMinLevel) or 25
        local maxLvl = tonumber(er.maxCharacterLevel or er.recommendedMaxLevel) or 60
        local pubState = type(er.certification) == "table" and tostring(er.certification.publicationState or "") or ""
        if (erFac == "Neutral" or erFac == faction) and level >= minLvl and level <= maxLvl and pubState == "source_verified" then
          table.insert(sourceVerifiedRoutes, er)
        end
      end
    end
  end

  local activeGoldProg = overrides.goldFarmProgress
    or (ns.State and ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress())
    or {}

  local reconciledProfit = overrides.reconciledVendorProfit
    or (ns.State and ns.State.lastReconciledVendorProfit)
    or nil

  local merchantOutcome = overrides.merchantOutcome
  if type(merchantOutcome) ~= "table" and ns.Domain and ns.Domain.TransactionJournal and ns.Domain.TransactionJournal.EnsureInitialized then
    local tj = ns.Domain.TransactionJournal.EnsureInitialized()
    merchantOutcome = tj and tj.lastMerchantOutcome or nil
  end

  local altCooldownRecords = overrides.altCooldownRecords
    or (ns.State and ns.State.GetAccountCooldownRecords and ns.State.GetAccountCooldownRecords())
    or {}

  local professionPlan = nil
  if ns.Domain and ns.Domain.ProfessionAdvisor and type(ns.Domain.ProfessionAdvisor.EvaluateCharacterPlan) == "function" then
    professionPlan = ns.Domain.ProfessionAdvisor.EvaluateCharacterPlan({
      snapshotStatus = snapshotStatus,
      level = level,
      hasBasicMount = (reserveSnap and reserveSnap.hasBasicMount == true) or (overrides.hasBasicMount == true),
      learnedSkills = learnedSkills or {},
      altCooldownRecords = altCooldownRecords,
      nowSeconds = nowSec,
    })
  end

  local portfolioTriage = overrides.portfolioTriage
  if type(portfolioTriage) ~= "table"
    and ns.Providers and ns.Providers.BlackthornesBridge
    and ns.Domain and ns.Domain.PortfolioTriage
    and (type(overrides.blackthornesDB) == "table" or type(_G.BlackthornesTSDB) == "table")
  then
    local btSnap = ns.Providers.BlackthornesBridge.BuildUnifiedPortfolioSnapshot({
      blackthornesDB = overrides.blackthornesDB,
      characterGUID = overrides.characterGUID,
      realmName = overrides.realmName,
      faction = faction,
      nowEpoch = nowSec,
      liveBags = overrides.liveBags,
      liveBankSnapshot = overrides.liveBankSnapshot,
      externalBankSnapshot = overrides.externalBankSnapshot,
      cachedBankSnapshot = overrides.cachedBankSnapshot,
      sessionBankObserved = overrides.sessionBankObserved,
    })
    if type(btSnap) == "table" then
      portfolioTriage = ns.Domain.PortfolioTriage.EvaluateCharacterPortfolioTriage({
        nowEpoch = nowSec,
        characterGUID = btSnap.character and btSnap.character.guid,
        investableCopper = tonumber(reserveSnap and reserveSnap.investableCopper) or 0,
        outstandingCommitmentsCopper = tonumber(overrides.outstandingCommitmentsCopper) or 0,
        spendableByItemID = btSnap.spendableByItemID,
        matchedCostBasisByItemID = btSnap.matchedCostBasisByItemID,
        activeAuctionUnitsByItemID = btSnap.activeAuctionUnitsByItemID,
        expiredAuctionListings = btSnap.expiredAuctionListings,
        mailInTransitByItemID = btSnap.mailInTransitByItemID,
        currentTailoringSkill = (type(learnedSkills) == "table" and tonumber(learnedSkills.TAILORING)) or 175,
        firstEligibleMoonclothCastEpoch = overrides.firstEligibleMoonclothCastEpoch,
        firstMoonclothSaleVerified = overrides.firstMoonclothSaleVerified,
      })
    end
  end

  local raidReadiness = nil
  if ns.Domain and ns.Domain.RaidReadinessCoach and type(ns.Domain.RaidReadinessCoach.Evaluate) == "function" then
    raidReadiness = ns.Domain.RaidReadinessCoach.Evaluate({
      tailoringSkill = (type(learnedSkills) == "table" and tonumber(learnedSkills.TAILORING)) or 214,
    })
  end

  return {
    nowSeconds = nowSec,
    level = level,
    faction = faction,
    classToken = classToken,
    classLabel = classLabel,
    inCombat = inCombat,
    clientLocale = clientLocale,
    hasAuctionator = hasAuctionator,
    reserveSnapshot = reserveSnap,
    rung1Deck = rung1Deck or {
      directSpreadActions = {},
      craftActions = {},
      discoveryCandidates = {},
      pendingItemCacheIDs = {},
      quarantinedItems = {},
    },
    eligibleFarms = eligibleFarms,
    sourceVerifiedRoutes = sourceVerifiedRoutes,
    wrongFactionSkippedCount = wrongFactionSkippedCount,
    levelBracketSkippedCount = levelBracketSkippedCount,
    activeGoldFarmID = (activeGoldProg.mode ~= "paused") and activeGoldProg.selectedFarmID or nil,
    reconciledProfit = reconciledProfit,
    merchantOutcome = merchantOutcome,
    professionSnapshotStatus = snapshotStatus,
    professionPlan = professionPlan,
    portfolioTriage = portfolioTriage,
    raidReadiness = raidReadiness,
  }
end

function CommandDeckPresenter.Build(snapshot, uiState)
  local snap = type(snapshot) == "table" and snapshot or CommandDeckPresenter.CaptureSnapshot(nil)
  uiState = type(uiState) == "table" and uiState or {}
  local deckView = type(uiState.advisorView) == "table" and uiState.advisorView or {}
  local crowdedMap = type(deckView.crowdedUntilByFarmID) == "table" and deckView.crowdedUntilByFarmID or {}
  local nowSec = tonumber(snap.nowSeconds) or 0

  local res = snap.reserveSnapshot or {}
  local kpis = {
    {
      label = "Character",
      value = string.format("Lv %d %s", tonumber(snap.level) or 1, tostring(snap.classLabel or "Adventurer")),
      sub = string.format("%s · %s", tostring(snap.faction or "Alliance"), tostring(snap.clientLocale or "enUS")),
      token = "text.primary",
    },
    {
      label = "Liquid Purse",
      value = (res.status == "ok") and formatMoneyPlainOrRich(res.liquidCopper, { plainText = true }) or "Unavailable",
      sub = snap.hasAuctionator and "Auctionator: Ready" or "Standalone (No Auctionator)",
      token = "accent.gold",
    },
    {
      label = "Protected Reserves",
      value = (res.status == "ok") and formatMoneyPlainOrRich(res.protectedCopperNow or 0, { plainText = true }) or "—",
      sub = (not res.hasBasicMount and (tonumber(res.mountReserveTargetCopper) or 0) > 0)
          and string.format("Mount shortfall: %s", formatMoneyPlainOrRich(res.mountShortfallCopper or 0, { plainText = true }))
        or "Training + repair/flight float",
      token = "status.reserved",
    },
    {
      label = "Investable Now",
      value = (res.status == "ok") and formatMoneyPlainOrRich(res.investableCopper or 0, { plainText = true }) or "0c",
      sub = (tonumber(res.investableCopper) or 0) > 0
          and "Available above reserves"
        or "Outlay gated to protect reserves",
      token = ((tonumber(res.investableCopper) or 0) > 0) and "accent.gold" or "text.muted",
    },
  }

  local cards = {}
  local actionableProfitOrRouteCount = 0

  -- 1. Combat Lockdown Banner Card (Persona 3 — Lv 60 mid-combat):
  if snap.inCombat == true then
    table.insert(cards, {
      cardID = "status:combat_lockdown",
      kind = "combat_guard",
      isPrimary = true,
      title = "In combat — advisor actions paused",
      badgeText = "Combat lockdown",
      badgeToken = "status.warning",
      reasonText = "Auction House discovery lists, batch crafting, and route changes are disabled during combat so gameplay frames remain safe.",
      costAndTimeText = "Cost: 0c · Resume immediately once out of combat",
      evidenceText = "Active HUD directional guidance stays passive until combat ends.",
      prereqText = "Exit combat to unlock supported actions.",
      primaryAction = nil,
      secondaryAction = nil,
    })
    return {
      northStarSubtitle = CommandDeckPresenter.NORTH_STAR_SUBTITLE,
      kpis = kpis,
      cards = cards,
      supportedActionCount = 0,
      inCombat = true,
    }
  end

  -- 2. Reconciled Realized Vendor Profit Card (Post-Execution ONLY):
  if type(snap.reconciledProfit) == "table" and snap.reconciledProfit.status == "REALIZED_RECONCILED" then
    local rp = snap.reconciledProfit
    table.insert(cards, {
      cardID = "reconciled:vendor_profit",
      kind = "reconciled_profit",
      isPrimary = false,
      title = "Last verified vendor cycle",
      badgeText = "Realized vendor profit",
      badgeToken = "status.ready",
      reasonText = string.format(
        "Reconciled actual vendor receipts (%s) minus actual buyout & incremental costs (%s).",
        formatMoneyPlainOrRich(rp.actualVendorGrossCopper or 0, { plainText = true }),
        formatMoneyPlainOrRich((rp.actualBuyoutPaidCopper or 0) + (rp.actualIncrementalCostCopper or 0), { plainText = true })
      ),
      costAndTimeText = string.format("Realized net: %s", formatMoneyPlainOrRich(rp.realizedProfitCopper or 0, { plainText = true })),
      evidenceText = "Post-transaction receipt reconciliation complete.",
      prereqText = "",
      primaryAction = nil,
    })
  end

  -- 3. Cold-Cache Localized Item Resolution Notice (Persona 4 — deDE/esMX cold cache):
  local pendingIDs = (snap.rung1Deck and snap.rung1Deck.pendingItemCacheIDs) or {}
  if #pendingIDs > 0 then
    table.insert(cards, {
      cardID = "status:pending_item_cache",
      kind = "pending_cache",
      isPrimary = false,
      title = string.format("Loading localized item data (%d pending)", #pendingIDs),
      badgeText = "Awaiting item cache",
      badgeToken = "status.warning",
      reasonText = string.format(
        "Requested client metadata for %d item(s) on locale %s. English catalog names are never substituted into exact searches.",
        #pendingIDs,
        tostring(snap.clientLocale or "enUS")
      ),
      costAndTimeText = "Cost: 0c · Resolves automatically on GET_ITEM_INFO_RECEIVED",
      evidenceText = "Fail-closed locale & live SellPrice verification active.",
      prereqText = "Click Retry once the client finishes caching item names.",
      primaryAction = {
        label = "Retry Item Cache",
        actionType = "RETRY_ITEM_CACHE",
        payload = { itemIDs = pendingIDs },
      },
    })
  end

  -- 4. Quarantined SellPrice Mismatch Notice (if live client disagreed with static data):
  local quarantined = (snap.rung1Deck and snap.rung1Deck.quarantinedItems) or {}
  if #quarantined > 0 then
    local q0 = quarantined[1]
    table.insert(cards, {
      cardID = "status:quarantined_items",
      kind = "quarantine_notice",
      isPrimary = false,
      title = string.format("Quarantined %d item(s) on live SellPrice mismatch", #quarantined),
      badgeText = "Quarantined — live mismatch",
      badgeToken = "status.danger",
      reasonText = string.format(
        "Item #%s reported live SellPrice %s vs static %s; excluded automatically from vendor spread recommendations.",
        tostring(q0.itemID or "?"),
        formatMoneyPlainOrRich(q0.liveSellPrice, { plainText = true }),
        formatMoneyPlainOrRich(q0.staticSellPrice, { plainText = true })
      ),
      costAndTimeText = "Excluded from execution to prevent loss.",
      evidenceText = "Live client GetItemInfo authority enforced.",
      prereqText = "",
      primaryAction = nil,
    })
  end

  -- 5. Rung-1a Direct AH-to-Vendor Conditional Spreads:
  for idx, act in ipairs((snap.rung1Deck and snap.rung1Deck.directSpreadActions) or {}) do
    if idx <= 3 then
      actionableProfitOrRouteCount = actionableProfitOrRouteCount + 1
      table.insert(cards, {
        cardID = string.format("rung1a:%d", act.itemID),
        kind = "rung1a_vendor_spread",
        isPrimary = (actionableProfitOrRouteCount == 1),
        itemID = act.itemID,
        title = string.format("%s (%dx across %d stack%s)", tostring(act.displayName), act.totalUnits, act.stackCount, act.stackCount == 1 and "" or "s"),
        badgeText = "Vendor spread — verify purchase",
        badgeToken = "status.buy",
        reasonText = string.format(
          "Observed whole-stack buyouts total %s vs %s NPC vendor value (expected spread: %s, ~%s/hr).",
          formatMoneyPlainOrRich(act.totalBuyoutCopper, { plainText = true }),
          formatMoneyPlainOrRich(act.totalVendorGrossCopper, { plainText = true }),
          formatMoneyPlainOrRich(act.netVendorProfitCopper, { plainText = true }),
          formatMoneyPlainOrRich(act.gphCopper, { plainText = true })
        ),
        costAndTimeText = string.format(
          "Outlay: %s (within %s investable) · Est. cycle: ~%ds",
          formatMoneyPlainOrRich(act.totalOutlayCopper, { plainText = true }),
          formatMoneyPlainOrRich((res.investableCopper or 0), { plainText = true }),
          tonumber(act.timing and act.timing.totalSeconds) or 60
        ),
        evidenceText = string.format(
          "Lot age: %ds · Live vendor value: %s/ea · Skipped %d bid-only listing(s)",
          tonumber(act.maxLotAgeSeconds) or 0,
          formatMoneyPlainOrRich(act.unitSellPrice, { plainText = true }),
          tonumber(act.skippedBidOnlyCount) or 0
        ),
        prereqText = string.format(
          "Requires %d free bag slot(s). %s",
          act.stackCount,
          tostring(act.discoveryWarning or "")
        ),
        primaryAction = snap.hasAuctionator and {
          label = "Create Discovery List",
          actionType = "CREATE_DISCOVERY_LIST",
          payload = {
            itemID = act.itemID,
            name = act.localizedLabelPending and nil or act.displayName,
            maxPrice = act.maxDiscoveryUnitCeilingCopper,
          },
        } or nil,
      })
    end
  end

  -- 6. Rung-1b Craft-to-Vendor Batch Actions (Bag Conversions + Whole-Input Batches):
  for idx, cAct in ipairs((snap.rung1Deck and snap.rung1Deck.craftActions) or {}) do
    if idx <= 2 then
      actionableProfitOrRouteCount = actionableProfitOrRouteCount + 1
      local leftoverParts = {}
      for _, lf in ipairs(cAct.leftoverInputs or {}) do
        table.insert(leftoverParts, string.format("%dx Item #%d", lf.quantity, lf.itemID))
      end
      local leftoverSuffix = (#leftoverParts > 0)
          and (" · Leftover inputs (excluded from cash profit): " .. table.concat(leftoverParts, ", "))
        or ""

      table.insert(cards, {
        cardID = "rung1b:" .. tostring(cAct.recipeID),
        kind = "rung1b_craft_vendor",
        isPrimary = (actionableProfitOrRouteCount == 1),
        itemID = cAct.outputItemID,
        title = string.format("Craft %dx %s -> Vendor", cAct.craftCount, tostring(cAct.outputDisplayName)),
        badgeText = (cAct.totalCashOutlayCopper == 0)
            and "Bag craft-to-vendor uplift"
          or "Vendor spread — verify purchase",
        badgeToken = (cAct.totalCashOutlayCopper == 0) and "accent.gold" or "status.buy",
        reasonText = string.format(
          "Cash profit: %s · Owned input alt-use cost: %s · Net economic gain: %s (~%s/hr)%s",
          formatMoneyPlainOrRich(cAct.cashProfitCopper, { plainText = true }),
          formatMoneyPlainOrRich(cAct.ownedInputsOpportunityCostCopper, { plainText = true }),
          formatMoneyPlainOrRich(cAct.economicSurplusCopper, { plainText = true }),
          formatMoneyPlainOrRich(cAct.gphCopper, { plainText = true }),
          leftoverSuffix
        ),
        costAndTimeText = string.format(
          "Cash outlay: %s · Est. craft & sell time: ~%ds",
          formatMoneyPlainOrRich(cAct.totalCashOutlayCopper, { plainText = true }),
          tonumber(cAct.totalSeconds) or 30
        ),
        evidenceText = string.format(
          "Verified output quantity (%dx) · Live output vendor value: %s/ea · Unreserved stock only",
          cAct.outputsSoldUnits,
          formatMoneyPlainOrRich(cAct.unitOutputVendorCopper, { plainText = true })
        ),
        prereqText = string.format("Profession: %s · Free bag slots available: %d", tostring(cAct.professionKey), tonumber(cAct.freeBagSlots) or 1),
        primaryAction = (cAct.totalCashOutlayCopper > 0 and snap.hasAuctionator) and {
          label = "Create Discovery List",
          actionType = "CREATE_CRAFT_DISCOVERY_LIST",
          payload = { recipeID = cAct.recipeID },
        } or {
          label = "View Crates & Reservations",
          actionType = "OPEN_TAB",
          payload = { tabKey = "crates" },
        },
      })
    end
  end

  -- 7. Supported Open-World Route / Raw Gold Farm Cards (Faction + Level + Crowded-Aware):
  local crowdedSkipped = {}
  local addedFarms = 0
  for _, farm in ipairs(snap.eligibleFarms or {}) do
    local fid = tostring(farm.farmID)
    local crowdedUntil = tonumber(crowdedMap[fid]) or 0
    if crowdedUntil > nowSec then
      table.insert(crowdedSkipped, {
        farmID = fid,
        title = tostring(farm.title or farm.shortLabel or fid),
        remainingMinutes = math.max(1, math.ceil((crowdedUntil - nowSec) / 60)),
      })
    elseif addedFarms < 2 then
      addedFarms = addedFarms + 1
      actionableProfitOrRouteCount = actionableProfitOrRouteCount + 1
      local stepCount = type(farm.travelSteps) == "table" and #farm.travelSteps or 0
      local ctaLabel = (stepCount > 1) and "Start route" or "Show direction"
      local isActive = (snap.activeGoldFarmID == fid)
      table.insert(cards, {
        cardID = "route:" .. fid,
        kind = "supported_route",
        isPrimary = (actionableProfitOrRouteCount == 1),
        farmID = fid,
        title = tostring(farm.title or farm.shortLabel or fid),
        badgeText = isActive and "Active route" or "Verified route",
        badgeToken = isActive and "accent.gold" or "status.reserved",
        reasonText = string.format(
          "%s (%s) — %s",
          tostring(farm.zoneName or "Open World"),
          tostring(snap.faction),
          tostring(farm.mobSummary or farm.summary or "Verified grind & vendor loop")
        ),
        costAndTimeText = "Outlay: 0c · Tracked via Net Purse Change / Active Hr (min 3m clean sample)",
        evidenceText = string.format(
          "Source & service flags verified (%d route hops) · Yard arrival only on known map transforms",
          stepCount
        ),
        prereqText = string.format("Faction: %s · Recommended level: %d+", tostring(snap.faction), tonumber(farm.minCharacterLevel) or 40),
        primaryAction = {
          label = isActive and "Open Route Controls" or ctaLabel,
          actionType = isActive and "OPEN_TAB" or "START_FARM_ROUTE",
          payload = { farmID = fid, tabKey = "gold" },
        },
        secondaryAction = {
          label = "Too crowded",
          actionType = "MARK_ROUTE_CROWDED",
          payload = { farmID = fid, cooldownSeconds = CROWDED_COOLDOWN_SECONDS },
        },
      })
    end
  end

  -- 8. Discovery-Only Auctionator Summary Candidates (when investableCopper > 0 and 0 observed lot flips):
  local discList = (snap.rung1Deck and snap.rung1Deck.discoveryCandidates) or {}
  if #discList > 0 and (tonumber(res.investableCopper) or 0) > 0 then
    local topD = discList[1]
    table.insert(cards, {
      cardID = string.format("discovery:%d", topD.itemID),
      kind = "discovery_only",
      isPrimary = (actionableProfitOrRouteCount == 0),
      itemID = topD.itemID,
      title = string.format("%s (+%d more summary candidate%s)", tostring(topD.displayName), math.max(0, #discList - 1), (#discList - 1) == 1 and "" or "s"),
      badgeText = "Discovery candidate — scan exact stacks at AH",
      badgeToken = "status.reserved",
      reasonText = string.format(
        "Summary unit price (%s) is below vendor value (%s), but Auctionator summaries do not prove stack size or remaining buyout depth.",
        formatMoneyPlainOrRich(topD.summaryUnitBuyoutCopper, { plainText = true }),
        formatMoneyPlainOrRich(topD.unitSellPrice, { plainText = true })
      ),
      costAndTimeText = "Outlay: 0c to scan · Revalidate exact stack buyout before purchasing",
      evidenceText = "Summary-only observation (never promoted to executable profit without lot scan).",
      prereqText = "Open the Auction House and click Create Discovery List to inspect live stacks.",
      primaryAction = snap.hasAuctionator and {
        label = "Create Discovery List",
        actionType = "CREATE_SUMMARY_DISCOVERY_LIST",
        payload = { candidates = discList },
      } or nil,
    })
  end

  -- 9. Crowded-Route Recovery Card (Persona 5 — when all eligible farms were marked "Too crowded"):
  if #crowdedSkipped > 0 and addedFarms == 0 then
    local cNames = {}
    for _, c in ipairs(crowdedSkipped) do
      table.insert(cNames, string.format("%s (%dm left)", c.title, c.remainingMinutes))
    end
    table.insert(cards, {
      cardID = "status:all_routes_crowded",
      kind = "crowded_fallback",
      isPrimary = (actionableProfitOrRouteCount == 0),
      title = "Local grind spot marked crowded — fallback options",
      badgeText = "Crowded camp fallback",
      badgeToken = "status.warning",
      reasonText = "Suppressed crowded spot(s) for this session: " .. table.concat(cNames, ", ")
        .. ". No additional traversal-verified grind loop matches this exact level/faction bracket yet.",
      costAndTimeText = "Cost: 0c · Convert unreserved bag cloth, pick an alternate grind subcamp, or clear crowded filter",
      evidenceText = "Never routes you into unverified caves or opposing-faction camps.",
      prereqText = "Click Clear Crowded Filter anytime to re-enable suppressed spots.",
      primaryAction = {
        label = "Open Gold & Farms",
        actionType = "OPEN_TAB",
        payload = { tabKey = "gold" },
      },
      secondaryAction = {
        label = "Clear Crowded Filter",
        actionType = "CLEAR_CROWDED_ROUTES",
        payload = {},
      },
    })
  end

  -- 10. Honest Prerequisite & Coverage Empty-State Card (Personas 1 & 2 when 0 profit/route cards qualify):
  if actionableProfitOrRouteCount == 0 and #crowdedSkipped == 0 then
    local emptyTitle = "No verified immediate profit flip or grind loop for this state"
    local emptyReason = ""
    local emptyPrereq = ""
    local primaryAct = {
      label = "Open Gold & Farms",
      actionType = "OPEN_TAB",
      payload = { tabKey = "gold" },
    }

    if (tonumber(res.liquidCopper) or 0) == 0 and not snap.hasAuctionator then
      emptyTitle = "Starter character mode — 0c purse & standalone setup"
      emptyReason =
        "You have 0c liquid copper and Auctionator is not installed, so Auction House purchases are unavailable. Quest normally, loot & vendor gray items, and ForeverHub will automatically highlight the highest-vendor quest reward on multi-choice turn-ins."
      emptyPrereq =
        "Optional: install Auctionator later for AH discovery lists. ForeverHub works standalone for quest rewards, crates, and routes."
    elseif res.summaryReason == "protected_for_mount_shortfall" then
      emptyTitle = string.format(
        "Mount savings protected (%s shortfall to Lv 40 riding)",
        formatMoneyPlainOrRich(res.mountShortfallCopper or 0, { plainText = true })
      )
      emptyReason = string.format(
        "Your %s purse is reserved toward your %s riding target plus training/repair float, so risky capital outlays are blocked.",
        formatMoneyPlainOrRich(res.liquidCopper or 0, { plainText = true }),
        formatMoneyPlainOrRich(res.mountTargetCopper or 900000, { plainText = true })
      )
      if snap.wrongFactionSkippedCount > 0 and #(snap.eligibleFarms or {}) == 0 then
        emptyReason = emptyReason
          .. string.format(
            " (%d Alliance-only farm route(s) excluded for %s; no unverified cross-faction camps shown.)",
            snap.wrongFactionSkippedCount,
            tostring(snap.faction)
          )
      end
      emptyPrereq =
        "Supported zero-outlay options now: quest turn-in vendor selection, unreserved First Aid cloth->bandage conversion, or Mount Tracker in Gold & Mount."
      primaryAct = {
        label = "Open Mount & Gold Tracker",
        actionType = "OPEN_TAB",
        payload = { tabKey = "gold" },
      }
    else
      emptyReason =
        "No live positive vendor spread lots or traversal-verified grind loops matched your current faction, level bracket, and unreserved inventory."
      emptyPrereq =
        "Scan an item page at the Auction House, gather unreserved cloth for First Aid conversion, or continue your quest route."
    end

    table.insert(cards, {
      cardID = "empty:honest_coverage",
      kind = "honest_coverage_state",
      isPrimary = true,
      title = emptyTitle,
      badgeText = "Honest coverage & prerequisites",
      badgeToken = "status.reserved",
      reasonText = emptyReason,
      costAndTimeText = "Outlay required: 0c · Reserves preserved",
      evidenceText = "142 unverified-quantity Craftsman's Writs remain excluded from profit ranking.",
      prereqText = emptyPrereq,
      primaryAction = primaryAct,
    })
  end

  -- 11. Supplemental Merchant Session Reconciliation Card (`P0.4`: `PROCEEDS_RECONCILED` vs `AMBIGUOUS`):
  local mo = snap.merchantOutcome
  if type(mo) == "table" then
    if mo.status == "PROCEEDS_RECONCILED" and (tonumber(mo.vendorProceedsCopper) or 0) > 0 then
      table.insert(cards, {
        cardID = "reconciled:merchant_proceeds",
        kind = "reconciled_proceeds",
        isPrimary = false,
        title = "Last merchant visit — Vendor proceeds",
        badgeText = "Vendor proceeds",
        badgeToken = "status.reserved",
        reasonText = string.format(
          "Gross vendor sales: %s (Personal repairs: %s · Purchases: %s). Realized profit is not claimed because item acquisition cost basis was unrecorded.",
          formatMoneyPlainOrRich(mo.vendorProceedsCopper or 0, { plainText = true }),
          formatMoneyPlainOrRich(mo.playerRepairCopper or 0, { plainText = true }),
          formatMoneyPlainOrRich((mo.purchasesCopper or 0) + (mo.buybacksCopper or 0), { plainText = true })
        ),
        costAndTimeText = string.format("Net purse change: %s", formatMoneyPlainOrRich(mo.netPurseDeltaCopper or 0, { plainText = true })),
        evidenceText = "Distinguishes gross vendor proceeds from verified-cost-basis profit (P0.4).",
        prereqText = "",
        primaryAction = nil,
      })
    elseif mo.status == "AMBIGUOUS" then
      table.insert(cards, {
        cardID = "reconciled:merchant_ambiguous",
        kind = "merchant_ambiguous",
        isPrimary = false,
        title = "Last merchant visit — Ambiguous attribution",
        badgeText = "Merchant session ambiguous",
        badgeToken = "status.warning",
        reasonText = string.format(
          "Session involved mixed or unattributable cash/slot changes (%s); ForeverHub withheld realized-profit attribution.",
          tostring(mo.reason or "unattributable_delta")
        ),
        costAndTimeText = "Profit claimed: None (attribution withheld)",
        evidenceText = "Fail-closed transaction reconciliation active.",
        prereqText = "",
        primaryAction = nil,
      })
    end
  end

  -- 12. Profession Plan or Explicit Unknown/Partial Profession State (`Stage 6A.3` / `P1.B`):
  local profPlan = snap.professionPlan
  if type(profPlan) == "table" then
    if profPlan.status == "incomplete_profession_snapshot" then
      table.insert(cards, {
        cardID = "profession:incomplete",
        kind = "profession_unknown_state",
        isPrimary = false,
        title = string.format("Profession guidance awaiting complete skill snapshot (%s)", tostring(profPlan.snapshotStatus or "PENDING")),
        badgeText = "Profession state pending",
        badgeToken = "status.warning",
        reasonText = tostring(profPlan.unknownStateNote or "Open your Skills pane so ForeverHub can inspect numeric skillLine IDs before advising on open primary slots."),
        costAndTimeText = "Cost: 0c · Zero automated unlearning",
        evidenceText = "Locale-safe numeric skillLine capture prevents false open-slot assumptions.",
        prereqText = "",
        primaryAction = nil,
      })
    elseif profPlan.status == "ok" and type(profPlan.prioritizedActions) == "table" and #profPlan.prioritizedActions > 0 then
      local topProf = profPlan.prioritizedActions[1]
      table.insert(cards, {
        cardID = "profession:plan",
        kind = "profession_plan",
        isPrimary = false,
        title = tostring(topProf.title or "Supported profession priority"),
        badgeText = string.format("Profession plan (%d/%d primary free)", tonumber(profPlan.openPrimarySlots) or 0, tonumber(profPlan.primarySlotCap) or 2),
        badgeToken = "status.reserved",
        reasonText = tostring(topProf.detail or ""),
        costAndTimeText = "Zero automated unlearning · Secondary First Aid never uses a primary slot",
        evidenceText = "Evaluated from complete base-rank profession snapshot.",
        prereqText = "",
        primaryAction = nil,
      })
    end

    -- 13. Account Cooldown Summary (`Stage 6B.1` / `P1.E`):
    local cdList = type(profPlan.altCooldowns) == "table" and profPlan.altCooldowns or {}
    if #cdList > 0 then
      local summaryLines = {}
      for idx, cd in ipairs(cdList) do
        if idx <= 3 then
          table.insert(summaryLines, string.format("[%s] %s", tostring(cd.characterKey or "Character"), tostring(cd.statusLabel or cd.state)))
        end
      end
      table.insert(cards, {
        cardID = "cooldown:summary",
        kind = "cooldown_summary",
        isPrimary = false,
        title = string.format("Tracked profession cooldowns (%d)", #cdList),
        badgeText = "Account cooldowns",
        badgeToken = "status.reserved",
        reasonText = table.concat(summaryLines, " · "),
        costAndTimeText = "Dual-clock UTC server-epoch persistence across reloads",
        evidenceText = "Offline alt cooldowns report expected readiness from last observation.",
        prereqText = "",
        primaryAction = nil,
      })
    end
  end

  -- 14. Source-Verified Expanded Route Reference Cards (`Stage 6A.4` — Horde `25-60` transparency):
  local addedSourceRoutes = 0
  for _, sRoute in ipairs(snap.sourceVerifiedRoutes or {}) do
    if addedSourceRoutes < 2 then
      addedSourceRoutes = addedSourceRoutes + 1
      local sFid = tostring(sRoute.farmID)
      table.insert(cards, {
        cardID = "route_source_verified:" .. sFid,
        kind = "source_verified_route_notice",
        isPrimary = false,
        farmID = sFid,
        title = tostring(sRoute.title or sRoute.shortLabel or sFid),
        badgeText = "Source-verified — awaiting field walk",
        badgeToken = "status.reserved",
        reasonText = string.format(
          "%s (%s, Lv %d–%d) — %s",
          tostring(sRoute.zoneName or "Open World"),
          tostring(snap.faction),
          tonumber(sRoute.minCharacterLevel) or 25,
          tonumber(sRoute.maxCharacterLevel) or 60,
          tostring(sRoute.mobSummary or "Source coordinates & vendor/repair services verified; awaiting recorded in-game field traversal receipt.")
        ),
        costAndTimeText = "Not counted as traversal-verified route until in-game field walk completes",
        evidenceText = "Compiler Gate 6 blocks geometry-only promotion to traversal_verified.",
        prereqText = "",
        primaryAction = nil,
      })
    end
  end

  -- 15. Optional Portfolio & Profession Triage Briefing (Astra P1/P2: placed after combat, cold-cache, quarantine, and Rung 1a/1b gates):
  local pt = snap.portfolioTriage
  if type(pt) == "table" then
    local ot = pt.tailoringOpeningTranche
    if type(ot) == "table" then
      table.insert(cards, {
        cardID = "portfolio:opening_tailoring_tranche",
        kind = "portfolio_tailoring_tranche",
        isPrimary = false,
        title = string.format("Tailoring %d->%d Opening Tranche: %dx Black Mageweave Leggings", ot.currentSkill or 175, ot.openingTargetSkill or 185, ot.openingOrangeCrafts or 10),
        badgeText = "Priced opening tranche",
        badgeToken = "status.reserved",
        reasonText = string.format(
          "Uses 20 of %d banked Bolt of Mageweave (spell 3865 = 5 cloth/bolt). Upfront thread cash: %s -> Vendor proceeds: %s (Net cash inflow: +%s; Owned-bolt economic cost: ~%s/craft).",
          (ot.bankedInventorySummary and ot.bankedInventorySummary.initialBolts) or 55,
          formatMoneyPlainOrRich(ot.upfrontCashOutlayCopper or 15000, { plainText = true }),
          formatMoneyPlainOrRich(ot.verifiedVendorProceedsCopper or 48320, { plainText = true }),
          formatMoneyPlainOrRich(ot.netCashInflowCopper or 33320, { plainText = true }),
          formatMoneyPlainOrRich(ot.economicCostPerCraftCopper or 1941, { plainText = true })
        ),
        costAndTimeText = "Owned Pattern: Mooncloth (14526) = 0c purchase outlay (50s saved vendor value) · Refresh skill colors at 185",
        evidenceText = "Forever table: Bolt of Runecloth at 205, Runecloth Belt at 210 (yellow 225), Mooncloth at 230 (confirm at trainer & tooltip).",
        prereqText = "Keep Skinning 300, Tailoring, and First Aid.",
        primaryAction = nil,
      })
    end

    table.insert(cards, {
      cardID = "portfolio:stage1_probe",
      kind = "portfolio_stage1_probe",
      isPrimary = false,
      title = string.format("Stage 1 Consumable Probe (Cap: %s)", formatMoneyPlainOrRich(pt.stage1BudgetCapCopper or 126750, { plainText = true })),
      badgeText = "Research & discovery test lot",
      badgeToken = "status.reserved",
      reasonText = "Test <=30 Dreamfoil (<=14s 50c), <=30 Mountain Silversage (<=12s 75c), <=15 Plaguebloom (<=30s) after a fresh AH scan and stack-boundary check.",
      costAndTimeText = "Stage 2 locked until dated own-sale mailLedger invoices confirm net profit after failed deposits (heardSales ignored).",
      evidenceText = "6 banked Felcloth covers 3 Mooncloth casts (t, t+4d, t+8d) before Dec 9, 2026 (1796832000 assumed 16:00 UTC cutoff).",
      prereqText = "",
      primaryAction = snap.hasAuctionator and {
        label = "Open Research View",
        actionType = "OPEN_TAB",
        payload = { tabKey = "research" },
      } or nil,
    })
  end

  return {
    northStarSubtitle = CommandDeckPresenter.NORTH_STAR_SUBTITLE,
    kpis = kpis,
    cards = cards,
    supportedActionCount = actionableProfitOrRouteCount,
    crowdedSuppressedCount = #crowdedSkipped,
    inCombat = false,
  }
end

function CommandDeckPresenter.ComputeTabBadge(snapshot, uiState)
  local vm = CommandDeckPresenter.Build(snapshot, uiState)
  if vm.inCombat then
    return "Combat", "status.warning"
  end
  if (vm.supportedActionCount or 0) > 0 then
    return string.format("%d ready", vm.supportedActionCount), "accent.gold"
  end
  return "Guide", "status.reserved"
end

return CommandDeckPresenter
