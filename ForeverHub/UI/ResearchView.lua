local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.UI = ns.UI or {}

local Theme = ns.UI.Theme
local Widgets = ns.UI.Widgets

local ResearchView = {
  frame = nil,
  host = nil,
  disclaimerBanner = nil,
  filterBar = nil,
  filterBtns = {},
  viewport = nil,
  cardPool = {},
  lastLayoutReport = nil,
  lastActionNotice = nil,
}
ns.UI.ResearchView = ResearchView

ResearchView.RESEARCH_BANNER_TEXT =
  "RESEARCH_ONLY — Conversion & supply-glut diagnostics. Never an automated buy instruction or promised return."
ResearchView.DISCOVERY_LIST_NAME = "ForeverHub Research Discovery"

local FILTER_MODES = {
  { key = "all", label = "All Research" },
  { key = "conversions", label = "Conversions (Rung 2)" },
  { key = "watchlist", label = "Supply-Glut (Rung 3)" },
  { key = "playbook", label = "Playbook Catalog" },
  { key = "crate_substitutes", label = "Waylaid Crates" },
  { key = "forever_conversions", label = "Forever Alchemy" },
  { key = "de_scenarios", label = "DE Scenarios" },
  { key = "gathering", label = "Gathering & Slot" },
  { key = "portfolio_triage", label = "Portfolio Triage" },
}

local function acquirePoolItem(pool, createFn)
  local idx = (pool.__used or 0) + 1
  pool.__used = idx
  local item = pool[idx]
  if not item then
    item = createFn(idx)
    pool[idx] = item
  end
  return item
end

local function resetPool(pool)
  for i = 1, #pool do
    if pool[i] then
      Widgets.SafeShow(pool[i], false)
    end
  end
  pool.__used = 0
end

local function ensureResearchState()
  local uiState = (ns.State and ns.State.GetWorkspaceUIState and ns.State.GetWorkspaceUIState()) or {}
  if type(uiState.researchView) ~= "table" then
    uiState.researchView = {
      filterMode = "all",
      scrollOffset = 0,
    }
  end
  return uiState, uiState.researchView
end

local function formatMoneySafe(copper)
  if type(copper) ~= "number" then
    return "Unavailable"
  end
  if Theme and type(Theme.FormatMoney) == "function" then
    return Theme.FormatMoney(copper, { plain = true })
  end
  return tostring(math.floor(copper)) .. "c"
end

local function collectObservedSummaryPrices(overrides)
  if type(overrides) == "table" and type(overrides.observedPricesByItemID) == "table" then
    return overrides.observedPricesByItemID
  end
  local prices = {}
  local sibling = _G.ForeverHub_MarketData
  if type(sibling) == "table" and type(sibling.items) == "table" then
    for ikey, rec in pairs(sibling.items) do
      if type(ikey) == "string" and type(rec) == "table" then
        local idStr = string.match(ikey, "^i1:base:(%d+)$")
          or string.match(ikey, "^i1:recipe:(%d+)$")
          or string.match(ikey, "^i1:item:(%d+)$")
        local id = idStr and tonumber(idStr) or nil
        local up = tonumber(rec.unitPriceCopper)
        if id and up and up > 0 and rec.tradeSafe ~= false then
          prices[id] = math.floor(up)
        end
      end
    end
  end
  return prices
end

function ResearchView.ComputeTabBadge()
  return "RESEARCH", "status.research"
end

function ResearchView.EvaluateGatheringYieldScenario(spec)
  spec = type(spec) == "table" and spec or {}
  local baseNodesPerHour = math.max(0, tonumber(spec.baseSkinsPerHour or spec.baseNodesPerHour) or 0)
  local vendorUnitCopper = math.max(0, math.floor(tonumber(spec.vendorValuePerSkinCopper) or 0))
  local ahNetUnitCopper = math.max(0, math.floor(tonumber(spec.ahNetValuePerSkinCopper) or 0))
  local usesBountifulHarvest = (spec.usesBountifulHarvest == true)
  local catchUpMin = math.max(0, math.floor(tonumber(spec.catchUpMinCostCopper) or 0))
  local catchUpMax = math.max(catchUpMin, math.floor(tonumber(spec.catchUpMaxCostCopper) or catchUpMin))

  local baseVendorGph = math.floor((baseNodesPerHour * vendorUnitCopper) + 0.5)
  local baseAhNetGph = math.floor((baseNodesPerHour * ahNetUnitCopper) + 0.5)

  return {
    baseSkinsPerHour = baseNodesPerHour,
    vendorGph100Copper = baseVendorGph,
    vendorGph105Copper = math.floor((baseVendorGph * 1.05) + 0.5),
    vendorGph110Copper = math.floor((baseVendorGph * 1.10) + 0.5),
    ahNetGph100Copper = baseAhNetGph,
    ahNetGph105Copper = math.floor((baseAhNetGph * 1.05) + 0.5),
    ahNetGph110Copper = math.floor((baseAhNetGph * 1.10) + 0.5),
    catchUpMinCostCopper = catchUpMin,
    catchUpMaxCostCopper = catchUpMax,
    usesBountifulHarvest = usesBountifulHarvest,
    bountifulHarvestMechanic = "SCARCE_MATERIAL_DISCOVERY_5_RANK_LEGACY",
    bountifulHarvestClaimID = "legacy_node_5_bountiful_harvest",
    ordinaryGatherMultiplierQuarantined = true,
    legacyPointsCommitted = usesBountifulHarvest and 5 or 0,
    maxActiveLegacyPoints = 16,
  }
end

function ResearchView.BuildFilteredDiscoveryTerms(overrides)
  overrides = type(overrides) == "table" and overrides or {}
  local vm = ResearchView.BuildViewModel(overrides)
  local VA = ns.Domain and ns.Domain.VendorArbitrage
  local seen = {}
  local terms = {}
  local excludedCount = 0

  for _, card in ipairs(vm.cards or {}) do
    local dAct = card.discoveryAction
    local itemID = tonumber((dAct and dAct.itemID) or card.itemID)
    local itemKey = tostring(card.itemKey or "")
    local isUnknownVar = (string.sub(itemKey, 1, 11) == "i1:unk_var:")
    local isBlockedWrit = (itemID and VA and VA.IsBlockedUnverifiedWrit and VA.IsBlockedUnverifiedWrit(itemID) == true) or false
    local isQuarantined = (itemID and VA and VA.GetQuarantinedItem and VA.GetQuarantinedItem(itemID) ~= nil) or false

    if itemID and itemID > 0 and not isUnknownVar and not isBlockedWrit and not isQuarantined then
      if not seen[itemID] then
        seen[itemID] = true
        table.insert(terms, {
          itemID = itemID,
          name = nil, -- Locale-safe: resolved strictly from live client item cache
          quantity = dAct and tonumber(dAct.quantity) or nil,
          maxPrice = dAct and tonumber(dAct.maxPrice) or nil,
          isExact = true,
        })
      end
    elseif card.itemID ~= nil or isUnknownVar or isBlockedWrit or isQuarantined then
      excludedCount = excludedCount + 1
    end
  end

  return {
    filterMode = vm.filterMode,
    listLabel = "Discovery list",
    terms = terms,
    excludedCount = excludedCount,
  }
end

function ResearchView.ExportActiveFilterDiscoveryList(overrides)
  overrides = type(overrides) == "table" and overrides or {}
  local inCombat = (ns.Compat and ns.Compat.IsInCombat and ns.Compat.IsInCombat()) or false
  if inCombat then
    return false, "in_combat_lockdown"
  end
  if not (ns.Providers and ns.Providers.Auctionator and ns.Providers.Auctionator.CreateShoppingListDetailed) then
    return false, "auctionator_unavailable"
  end
  local built = ResearchView.BuildFilteredDiscoveryTerms(overrides)
  if #built.terms == 0 then
    return false, "no_eligible_discovery_terms"
  end
  local listName = overrides.listName or ResearchView.DISCOVERY_LIST_NAME
  local ok, countOrErr, resolvedListName, details = ns.Providers.Auctionator.CreateShoppingListDetailed(
    listName,
    built.terms,
    {
      userInitiated = true,
      passiveRefresh = false,
    }
  )
  return ok == true, {
    status = ok and "EXPORTED" or tostring(countOrErr),
    listLabel = "Discovery list",
    listName = resolvedListName or listName,
    filterMode = built.filterMode,
    terms = built.terms,
    excludedCount = built.excludedCount,
    details = details,
  }
end

function ResearchView.ExportConversionDiscoveryList(recipe, opts)
  opts = type(opts) == "table" and opts or {}
  local inCombat = (ns.Compat and ns.Compat.IsInCombat and ns.Compat.IsInCombat()) or false
  if inCombat then
    return false, "in_combat_lockdown"
  end
  if not (ns.Providers and ns.Providers.Auctionator and ns.Providers.Auctionator.IsAvailable and ns.Providers.Auctionator.IsAvailable()) then
    return false, "auctionator_unavailable"
  end
  if not (ns.Domain and ns.Domain.ConversionSpreads and type(ns.Domain.ConversionSpreads.BuildConversionDiscoveryEntries) == "function") then
    return false, "conversion_discovery_unavailable"
  end

  local built = ns.Domain.ConversionSpreads.BuildConversionDiscoveryEntries(recipe, opts)
  if not built or built.ok ~= true or type(built.entries) ~= "table" or #built.entries == 0 then
    return false, (built and built.status) or "no_deficit_entries"
  end

  local shoppingTerms = {}
  for _, entry in ipairs(built.entries) do
    table.insert(shoppingTerms, {
      itemID = entry.itemID,
      name = entry.name,
      quantity = entry.shoppingQuantity,
      maxPrice = entry.maxUnitPriceCopper,
      isExact = true,
    })
  end

  if type(ns.Providers.Auctionator.CreateShoppingListDetailed) == "function" then
    local ok, countOrErr, listName, details = ns.Providers.Auctionator.CreateShoppingListDetailed(
      opts.listName or ResearchView.DISCOVERY_LIST_NAME,
      shoppingTerms,
      {
        userInitiated = true,
        passiveRefresh = false,
      }
    )
    return ok == true, {
      status = ok and "EXPORTED" or tostring(countOrErr),
      listName = listName,
      entries = built.entries,
      simultaneousIndependentCeilings = false,
      ceilingConditionNote = built.ceilingConditionNote,
      details = details,
    }
  end
  return false, "create_shopping_list_missing"
end

function ResearchView.BuildViewModel(overrides)
  overrides = type(overrides) == "table" and overrides or {}
  local _, rState = ensureResearchState()
  local filterMode = tostring(overrides.filterMode or rState.filterMode or "all")
  local hasAuctionator = (overrides.hasAuctionator ~= nil) and (overrides.hasAuctionator == true)
    or (ns.Providers and ns.Providers.Auctionator and ns.Providers.Auctionator.IsAvailable and ns.Providers.Auctionator.IsAvailable())
    or false

  local pricesByID = collectObservedSummaryPrices(overrides)
  local cards = {}

  if (filterMode == "all" or filterMode == "conversions")
    and ns.Domain and ns.Domain.ConversionSpreads
    and type(ns.Domain.ConversionSpreads.EvaluateAllCuratedConversions) == "function"
  then
    local convs = ns.Domain.ConversionSpreads.EvaluateAllCuratedConversions({
      summaryUnitPricesByItemID = pricesByID,
      laddersByItemID = overrides.laddersByItemID,
      outputPricesByItemID = overrides.outputPricesByItemID or pricesByID,
      feeRule = overrides.feeRule,
      currentBuild = overrides.currentBuild,
      saleThroughByRecipeID = overrides.saleThroughByRecipeID,
      nowEpoch = overrides.nowEpoch,
    })
    for _, c in ipairs(convs) do
      local netStr = c.netSpreadCopper and formatMoneySafe(c.netSpreadCopper) or "Pending verified fee rule / prices"
      local badgeTok = (c.status == "POSITIVE_CONVERSION_SPREAD" and c.saleThroughVerified == true)
        and "accent.crystal"
        or "status.warning"
      table.insert(cards, {
        cardID = "rung2:" .. tostring(c.recipeID),
        rung = "RUNG_2_CONVERSION",
        mode = "CONVERSION_DIAGNOSTIC",
        allowBuyCta = false,
        itemID = c.outputItemID,
        badgeText = "RUNG 2 · " .. tostring(c.status),
        badgeToken = badgeTok,
        title = string.format("%s (%s %d)", tostring(c.displayName), tostring(c.professionKey or ""), tonumber(c.minSkill) or 1),
        summaryText = string.format("Net conversion spread: %s  ·  %s", netStr, tostring(c.turnaroundLabel or "Liquidation time: UNKNOWN")),
        fallbackText = string.format("Liquidation horizon: %s (never promised without measured sale-through)", tostring(c.liquidationTime or "UNKNOWN")),
        caveatText = (c.supportsAuctionableVellums == false and c.professionKey == "ENCHANTING")
          and "Physical crafted item only — trade-window enchanting services cannot be posted via vellums."
          or "Verify whole-stack input depth and exact AH listing deposit before crafting.",
        discoveryAction = hasAuctionator and {
          label = "Create Discovery List",
          itemID = c.outputItemID,
          displayName = c.displayName,
        } or nil,
      })
    end
  end

  if (filterMode == "all" or filterMode == "watchlist" or filterMode == "playbook")
    and ns.Domain and ns.Domain.SupplyGlutResearch
    and type(ns.Domain.SupplyGlutResearch.EvaluateCuratedWatchlist) == "function"
  then
    local glutList = ns.Domain.SupplyGlutResearch.EvaluateCuratedWatchlist({
      observedPricesByItemID = pricesByID,
      historyByItemID = overrides.historyByItemID,
      includeFullPlaybook = (filterMode == "playbook"),
      playbookCategory = overrides.playbookCategory,
      learnedProfessions = overrides.learnedProfessions,
      learnedRecipes = overrides.learnedRecipes,
      ownedTools = overrides.ownedTools,
      stationAvailable = overrides.stationAvailable,
      blockDisputedStaticWithoutLive = overrides.blockDisputedStaticWithoutLive,
      liveSellPriceLookup = overrides.liveSellPriceLookup,
    })
    for _, g in ipairs(glutList) do
      local badgeTok = (g.classification == "STRUCTURAL_OVERSUPPLY_RISK") and "status.warning" or "status.research"
      local askStr = g.observedUnitAskCopper and formatMoneySafe(g.observedUnitAskCopper) or "Unobserved"
      local fbLossStr = "No verified immediate fallback"
      if g.lossUnderStatedFallbackCopper ~= nil then
        local pctStr = (type(g.lossUnderStatedFallbackPct) == "number")
          and string.format(" (%.1f%%)", g.lossUnderStatedFallbackPct)
          or ""
        fbLossStr = formatMoneySafe(g.lossUnderStatedFallbackCopper) .. pctStr
      end
      local directStr = (g.directVendorFallbackCopper ~= nil)
        and formatMoneySafe(g.directVendorFallbackCopper)
        or "Unverified"
      local slotStr = string.format(
        "Slots: %d (stack %d) · Cap/slot: %s",
        tonumber(g.slotsRequired) or 1,
        tonumber(g.verifiedStackSize) or 20,
        g.capitalPerSlotCopper and formatMoneySafe(g.capitalPerSlotCopper) or "N/A"
      )
      table.insert(cards, {
        cardID = "rung3:" .. tostring(g.candidateID),
        itemKey = g.itemKey,
        rung = "RUNG_3_SUPPLY_GLUT_RESEARCH",
        mode = "RESEARCH_ONLY",
        activityClass = g.activityClass,
        fallbackType = g.fallbackType,
        classification = g.classification,
        allowBuyCta = false,
        itemID = g.itemID,
        badgeText = string.format("RESEARCH_ONLY · %s · %s", tostring(g.classification), tostring(g.fallbackType or "UNVERIFIED")),
        badgeToken = badgeTok,
        title = tostring(g.displayName),
        summaryText = tostring(g.hypothesisSummary or ""),
        fallbackText = string.format(
          "Observed ask: %s · %s (%s): %s · Direct vendor: %s · %s",
          askStr,
          tostring(g.fallbackLabel or "Loss under stated fallback"),
          tostring(g.fallbackType or "UNVERIFIED"),
          fbLossStr,
          directStr,
          slotStr
        ),
        caveatText = string.format("Bull-trap risk: %s", tostring(g.principalFailureMode or "")),
        discoveryAction = hasAuctionator and {
          label = "Create Discovery List",
          itemID = g.itemID,
          displayName = g.displayName,
        } or nil,
      })
    end
  end

  if filterMode == "crate_substitutes"
    and ns.Domain and ns.Domain.SupplyGlutResearch
    and type(ns.Domain.SupplyGlutResearch.EvaluateCrateSubstituteSpreads) == "function"
  then
    local crates = ns.Domain.SupplyGlutResearch.EvaluateCrateSubstituteSpreads({
      observedPricesByItemID = pricesByID,
      laddersByItemID = overrides.laddersByItemID,
      ownedByItemID = overrides.ownedByItemID,
      reservedByItemID = overrides.reservedByItemID,
      learnedProfessions = overrides.learnedProfessions,
      learnedRecipes = overrides.learnedRecipes,
      tierFilter = overrides.crateTierFilter,
      marketIdentity = overrides.marketIdentity,
      snapshotAgeSeconds = overrides.snapshotAgeSeconds,
    })
    for _, c in ipairs(crates) do
      local cheapest = c.cheapestKnownOption
      local cheapestStr = cheapest
        and string.format("%s (%s)", tostring(cheapest.label), formatMoneySafe(cheapest.effectiveTotalCostCopper))
        or "No priced options"
      local globalStr = c.verifiedGlobalCheapestOption
        and "Verified global cheapest (full depth)"
        or "Known minimum only (partial/summary)"
      local spreadStr = c.runnerUpSpreadCopper
        and string.format("Buyer substitution diff: %s", formatMoneySafe(c.runnerUpSpreadCopper))
        or "Substitution diff: UNKNOWN (<2 priced options)"
      table.insert(cards, {
        cardID = "crate_sub:" .. tostring(c.crateItemID),
        rung = "CRATE_SUBSTITUTE_DIAGNOSTIC",
        mode = "RESEARCH_ONLY",
        allowBuyCta = false,
        itemID = cheapest and cheapest.itemID or nil,
        badgeText = string.format("WAYLAID CRATE (%s) · %s", tostring(c.tier or "?"), tostring(c.outcome)),
        badgeToken = (c.outcome == "COMPLETE_COVERAGE") and "accent.crystal" or "status.research",
        title = string.format("%s (Lv%d · %s)", tostring(c.name or c.shortName), tonumber(c.requiredLevel) or 10, tostring(c.rewardCurrency or "Merchant's Favor")),
        summaryText = string.format("Cheapest known option: %s · %s", cheapestStr, globalStr),
        fallbackText = string.format("%s · Priced %d/%d options (0 rep after intro Shipping Label)", spreadStr, c.pricedOptionCount or 0, c.totalOptionCount or 0),
        caveatText = c.namespaceClarificationNote
          or "Soulbound crate: substitution spread measures buyer alternative cost, not guaranteed flipper profit.",
        discoveryAction = (hasAuctionator and cheapest and cheapest.itemID) and {
          label = "Create Discovery List",
          itemID = cheapest.itemID,
          quantity = cheapest.netPurchaseQuantity,
          displayName = cheapest.itemName,
        } or nil,
      })
    end
  end

  if filterMode == "forever_conversions"
    and ns.Domain and ns.Domain.ConversionSpreads
  then
    for _, recipe in ipairs(ns.Domain.ConversionSpreads.FOREVER_RECIPES or {}) do
      local marginRes = ns.Domain.ConversionSpreads.EvaluateConditionalRecipeMargin(recipe, {
        pricesByItemID = pricesByID,
        pricesByRecipeID = overrides.pricesByRecipeID,
        ownedByItemID = overrides.ownedByItemID,
        reservedByItemID = overrides.reservedByItemID,
        unlockCostCopper = overrides.unlockCostByRecipeID and overrides.unlockCostByRecipeID[recipe.recipeID],
      })
      local marginStr = (marginRes and marginRes.marginPerCraftCopper)
        and formatMoneySafe(marginRes.marginPerCraftCopper)
        or "Awaiting live output/herb prices"
      local breakEvenStr = (marginRes and marginRes.unlockBreakEvenCrafts and marginRes.unlockBreakEvenCrafts < math.huge)
        and string.format("Unlock break-even: %d crafts", marginRes.unlockBreakEvenCrafts)
        or "Unlock break-even: N/A"
      table.insert(cards, {
        cardID = "forever_conv:" .. tostring(recipe.recipeID),
        rung = "RUNG_2_FOREVER_CONVERSION",
        mode = "CONVERSION_DIAGNOSTIC",
        allowBuyCta = false,
        itemID = recipe.outputItemID,
        badgeText = "FOREVER ALCHEMY · " .. tostring(marginRes and marginRes.status or "UNPRICED"),
        badgeToken = "status.research",
        title = string.format("%s (%s %d)", tostring(recipe.displayName), tostring(recipe.professionKey), tonumber(recipe.minSkill) or 1),
        summaryText = string.format("Conditional margin/craft: %s  ·  %s", marginStr, breakEvenStr),
        fallbackText = "Input ceilings C_{k,max} are conditional on all other inputs fixed (never independent).",
        caveatText = "Verify recipe bind state & AH sale-through cohort before committing gold.",
      })
    end
  end

  if filterMode == "de_scenarios"
    and ns.Domain and ns.Domain.DisenchantEv
  then
    local sampleItems = overrides.disenchantCandidates or {
      {
        itemID = 11288,
        name = "Greater Magic Wand (Forever 1c Vendor)",
        quality = 2,
        itemLevel = 18,
        slotFamily = "WEAPON",
        isWand = true,
        disenchantEligibilityVerified = false,
      },
      {
        itemID = nil,
        name = "Lv 52-55 Uncommon Armor Sample (iLvl 53)",
        quality = 2,
        itemLevel = 53,
        slotFamily = "ARMOR",
        vendorSellCopper = 14500,
        disenchantEligibilityVerified = true,
      },
    }
    for idx, spec in ipairs(sampleItems) do
      local deRes = ns.Domain.DisenchantEv.EvaluateItemDisenchant(spec, {
        materialPricesByItemID = pricesByID,
        liquidationVerified = overrides.liquidationVerified,
        salvagerLiveVerified = overrides.salvagerLiveVerified,
      })
      local summaryLine
      if deRes.eligible then
        summaryLine = string.format(
          "Vendor: %s  ·  1.00x: %s  ·  1.05x: %s  ·  1.10x: %s",
          formatMoneySafe(deRes.vendorSellCopper),
          formatMoneySafe(deRes.baseExpectedNetCopper),
          formatMoneySafe(deRes.salvager105ExpectedNetCopper),
          formatMoneySafe(deRes.salvager110ExpectedNetCopper)
        )
      else
        summaryLine = string.format("Blocked (%s): %s", tostring(deRes.status), tostring(deRes.reason))
      end
      table.insert(cards, {
        cardID = "de_scenario:" .. tostring(idx),
        rung = "DISENCHANT_SCENARIO_EVAL",
        mode = "RESEARCH_ONLY",
        allowBuyCta = false,
        itemID = spec.itemID,
        badgeText = "DE SCENARIO · " .. tostring(deRes.status),
        badgeToken = "status.research",
        title = tostring(spec.name or ("Item #" .. tostring(spec.itemID or idx))),
        summaryText = summaryLine,
        fallbackText = string.format("Conservative Floor: %s (enchanting mats have 0c vendor floor)", formatMoneySafe(deRes.conservativeFloorCopper or 0)),
        caveatText = tostring(deRes.recommendation or "Never destroy unverified Forever items or raid epics without a verified DE table."),
      })
    end
  end

  if filterMode == "gathering" then
    local gEval = ResearchView.EvaluateGatheringYieldScenario(overrides.gatheringScenario or {
      baseSkinsPerHour = 120,
      vendorValuePerSkinCopper = 500,
      ahNetValuePerSkinCopper = 680,
      usesBountifulHarvest = true,
      campDuplicatesActive = 1,
      catchUpMinCostCopper = 150000,
      catchUpMaxCostCopper = 350000,
    })
    table.insert(cards, {
      cardID = "gathering:skinning_48_60",
      rung = "GATHERING_SCENARIO_EVAL",
      mode = "RESEARCH_ONLY",
      allowBuyCta = false,
      badgeText = "GATHERING · SKINNING 48-60",
      badgeToken = "status.research",
      title = "Skinning (48-60) Yield & Catch-Up Bounds",
      summaryText = string.format(
        "Vendor GPH (1.00x / 1.05x / 1.10x): %s / %s / %s",
        formatMoneySafe(gEval.vendorGph100Copper),
        formatMoneySafe(gEval.vendorGph105Copper),
        formatMoneySafe(gEval.vendorGph110Copper)
      ),
      fallbackText = string.format(
        "1-240 Catch-up cost range: %s - %s  ·  Legacy cost: %d/%d active points",
        formatMoneySafe(gEval.catchUpMinCostCopper),
        formatMoneySafe(gEval.catchUpMaxCostCopper),
        gEval.legacyPointsCommitted,
        gEval.maxActiveLegacyPoints
      ),
      caveatText = "Beast-skinning loops compete directly with humanoid Tailoring cloth routes.",
    })
  end

  if filterMode == "portfolio_triage"
    and ns.Domain and ns.Domain.PortfolioTriage
    and type(ns.Domain.PortfolioTriage.EvaluateCharacterPortfolioTriage) == "function"
  then
    local pt = ns.Domain.PortfolioTriage.EvaluateCharacterPortfolioTriage(overrides.portfolioTriageOpts or overrides)
    local ot = pt and pt.tailoringOpeningTranche
    if ot then
      table.insert(cards, {
        cardID = "triage:tailoring_175_185",
        rung = "PORTFOLIO_TRIAGE_DIAGNOSTIC",
        mode = "RESEARCH_ONLY",
        allowBuyCta = false,
        itemID = 9999,
        badgeText = "RESEARCH_ONLY · TAILORING 175-185 TRANCHE",
        badgeToken = "status.research",
        title = "Tailoring 175->185: 10x Black Mageweave Leggings (Spell 12049)",
        summaryText = string.format(
          "Upfront thread cash: %s · Vendor proceeds: %s · Net cash inflow: +%s · Economic cost: ~%s/craft",
          formatMoneySafe(ot.upfrontCashOutlayCopper),
          formatMoneySafe(ot.verifiedVendorProceedsCopper),
          formatMoneySafe(ot.netCashInflowCopper),
          formatMoneySafe(ot.economicCostPerCraftCopper)
        ),
        fallbackText = "Loss under stated fallback: 0c (immediate 48s 32c NPC vendor proceeds exceed 15s thread outlay)",
        caveatText = "Spell 3865 uses 5x Mageweave Cloth per bolt; refresh skill colors at 185 and verify Mooncloth rank (230 vs 250) on tooltip.",
      })
    end
    for _, probe in ipairs((pt and pt.stage1ProbeSpecs) or {}) do
      table.insert(cards, {
        cardID = "triage:stage1:" .. tostring(probe.itemID),
        rung = "PORTFOLIO_TRIAGE_DIAGNOSTIC",
        mode = "RESEARCH_ONLY",
        allowBuyCta = false,
        itemID = probe.itemID,
        badgeText = "RESEARCH_ONLY · STAGE 1 CONSUMABLE PROBE",
        badgeToken = "status.research",
        title = string.format("%s (<=%du @ <=%s)", tostring(probe.name), probe.maxUnits, formatMoneySafe(probe.maxUnitPriceCopper)),
        summaryText = string.format("Ceiling outlay: %s (Stage 1 total cap: %s)", formatMoneySafe(probe.ceilingCopper), formatMoneySafe(pt.stage1BudgetCapCopper)),
        fallbackText = "Loss under stated fallback: requires fresh AH scan and stack-boundary verification before purchase",
        caveatText = "Stage 2 scaling locked until dated mailLedger own-sale invoices confirm net profit after failed deposits.",
        discoveryAction = hasAuctionator and {
          label = "Create Discovery List",
          itemID = probe.itemID,
          quantity = probe.maxUnits,
          maxPrice = probe.maxUnitPriceCopper,
          displayName = probe.name,
        } or nil,
      })
    end
  end

  return {
    filterMode = filterMode,
    bannerText = ResearchView.RESEARCH_BANNER_TEXT,
    hasAuctionator = hasAuctionator,
    cards = cards,
  }
end

function ResearchView.Dispatch(actionType, payload)
  payload = type(payload) == "table" and payload or {}
  local inCombat = (ns.Compat and ns.Compat.IsInCombat and ns.Compat.IsInCombat()) or false
  if inCombat then
    ResearchView.lastActionNotice = "Action blocked during combat."
    return false, "in_combat_lockdown"
  end

  local _, rState = ensureResearchState()
  if actionType == "SET_FILTER" then
    rState.filterMode = tostring(payload.filterMode or "all")
    rState.scrollOffset = 0
    ResearchView.RefreshIfShown()
    return true
  elseif actionType == "CREATE_RESEARCH_DISCOVERY_LIST" then
    if not (ns.Providers and ns.Providers.Auctionator and ns.Providers.Auctionator.CreateShoppingListDetailed) then
      return false, "auctionator_unavailable"
    end
    local ok, countOrErr, listName, details = ns.Providers.Auctionator.CreateShoppingListDetailed(
      ResearchView.DISCOVERY_LIST_NAME,
      {
        {
          itemID = payload.itemID,
          name = nil, -- Locale-safe: resolve strictly from client GetItemInfo cache
          isExact = true,
        },
      },
      {
        userInitiated = true,
        passiveRefresh = false,
      }
    )
    if ok then
      ResearchView.lastActionNotice = string.format(
        "Created research discovery list '%s' (%d term). Discovery aid only — never an automated buy signal.",
        tostring(listName),
        tonumber(countOrErr) or 1
      )
    else
      ResearchView.lastActionNotice = "Discovery list pending item cache or unavailable: " .. tostring(countOrErr)
    end
    ResearchView.RefreshIfShown()
    return ok == true, details or countOrErr
  end
  return false, "unknown_action"
end

local function createResearchCard(parent)
  local card = Widgets.CreatePanel(parent, "surface.card", "border.subtle")
  if not card then
    return nil
  end
  card.leftAccent = Widgets.SafeCreateTexture(card, "BORDER", 2)
  if card.leftAccent then
    Widgets.SafeSetPoint(card.leftAccent, "TOPLEFT", card, "TOPLEFT", 0, 0)
    Widgets.SafeSetPoint(card.leftAccent, "BOTTOMLEFT", card, "BOTTOMLEFT", 0, 0)
    Widgets.SafeSetWidth(card.leftAccent, 3)
  end

  card.icon = Widgets.CreateItemIcon(card, 32)
  if card.icon then
    Widgets.SafeSetPoint(card.icon, "TOPLEFT", card, "TOPLEFT", 12, -12)
  end

  card.badge = Widgets.CreateBadge(card)
  card.titleText = Widgets.SafeCreateFontString(card, "sectionTitle", "text.primary")
  card.summaryText = Widgets.SafeCreateFontString(card, "body", "text.secondary")
  card.fallbackText = Widgets.SafeCreateFontString(card, "dense", "accent.goldMuted")
  card.caveatText = Widgets.SafeCreateFontString(card, "dense", "text.muted")

  for _, fs in ipairs({ card.titleText, card.summaryText, card.fallbackText, card.caveatText }) do
    if fs then
      if type(fs.SetJustifyH) == "function" then pcall(fs.SetJustifyH, fs, "LEFT") end
      if type(fs.SetWordWrap) == "function" then pcall(fs.SetWordWrap, fs, true) end
    end
  end

  -- Strictly Ghost button ("Create Discovery List"), NEVER a primary green/gold "Buy" CTA!
  card.discoveryBtn = Widgets.CreateGhostButton(card, 156, "Create Discovery List", 26)
  return card
end

function ResearchView.EnsureHost()
  if ResearchView.host then
    return ResearchView.host
  end
  if not (ns.UI and ns.UI.Workspace and ns.UI.Workspace.EnsureCreated) then
    return nil
  end
  local wf = ns.UI.Workspace.EnsureCreated()
  local tabParent = wf and wf.tabHosts and wf.tabHosts.research
  if not tabParent then
    return nil
  end

  local host = Widgets.CreatePanel(tabParent, "surface.window", nil)
  if not host then
    return nil
  end
  host.__parentRef = tabParent
  ResearchView.host = host
  ResearchView.frame = tabParent

  if ns.UI.Workspace.RegisterTabRenderer then
    ns.UI.Workspace.RegisterTabRenderer("research", {
      Refresh = function(_, contentWidth, contentHeight, isCompact)
        ResearchView.RenderInHost(contentWidth, contentHeight, isCompact)
      end,
    })
  end

  local banner = Widgets.CreatePanel(host, "surface.elevated", "border.subtle")
  if banner then
    banner.label = Widgets.SafeCreateFontString(banner, "dense", "status.research")
    if banner.label then
      Widgets.SafeSetPoint(banner.label, "LEFT", banner, "LEFT", 12, 0)
      Widgets.SafeSetPoint(banner.label, "RIGHT", banner, "RIGHT", -12, 0)
      if type(banner.label.SetJustifyH) == "function" then pcall(banner.label.SetJustifyH, banner.label, "LEFT") end
    end
  end
  ResearchView.disclaimerBanner = banner

  local fBar = Widgets.CreatePanel(host, "surface.card", "border.subtle")
  ResearchView.filterBar = fBar
  ResearchView.filterBtns = {}
  if fBar then
    for idx, fSpec in ipairs(FILTER_MODES) do
      local btn = Widgets.CreateGhostButton(fBar, 156, fSpec.label, 26)
      if btn then
        local keyCopy = fSpec.key
        btn:SetOnClick(function()
          ResearchView.Dispatch("SET_FILTER", { filterMode = keyCopy })
        end)
        ResearchView.filterBtns[idx] = { key = fSpec.key, button = btn }
      end
    end
  end

  ResearchView.viewport = Widgets.CreateScrollViewport(host, function(offset)
    local _, rState = ensureResearchState()
    rState.scrollOffset = offset
  end)

  return host
end

function ResearchView.RenderInHost(viewportWidth, viewportHeight, isCompact, overrides)
  local host = ResearchView.EnsureHost()
  if not host then
    return nil
  end

  local generation = Widgets.BumpGeneration()
  local pad = Theme.METRICS.workspacePadding
  local vw = math.max(700, tonumber(viewportWidth) or 928)
  local vh = math.max(360, (tonumber(viewportHeight) or 560) - 16)
  local compact = (isCompact == true)

  Widgets.SafeClearPoints(host)
  Widgets.SafeSetSize(host, vw, vh)
  Widgets.SafeSetPoint(host, "TOPLEFT", host.__parentRef, "TOPLEFT", pad, -8)
  Widgets.SafeShow(host, true)

  local _, rState = ensureResearchState()
  local vm = ResearchView.BuildViewModel(overrides)

  local bannerH = 30
  if ResearchView.disclaimerBanner then
    Widgets.SafeClearPoints(ResearchView.disclaimerBanner)
    Widgets.SafeSetPoint(ResearchView.disclaimerBanner, "TOPLEFT", host, "TOPLEFT", 0, 0)
    Widgets.SafeSetSize(ResearchView.disclaimerBanner, vw, bannerH)
    if ResearchView.disclaimerBanner.label then
      Theme.ApplyFont(ResearchView.disclaimerBanner.label, "dense", "status.research")
      ResearchView.disclaimerBanner.label:SetText(vm.bannerText)
    end
  end

  local filterH = 38
  if ResearchView.filterBar then
    Widgets.SafeClearPoints(ResearchView.filterBar)
    Widgets.SafeSetPoint(ResearchView.filterBar, "TOPLEFT", host, "TOPLEFT", 0, -(bannerH + 6))
    Widgets.SafeSetSize(ResearchView.filterBar, vw, filterH)
    local btnW = math.min(180, math.floor((vw - 32) / #FILTER_MODES) - 6)
    for idx, entry in ipairs(ResearchView.filterBtns) do
      local b = entry.button
      if b then
        Widgets.SafeClearPoints(b)
        Widgets.SafeSetSize(b, btnW, 26)
        Widgets.SafeSetPoint(b, "LEFT", ResearchView.filterBar, "LEFT", 12 + (idx - 1) * (btnW + 8), 0)
        b.__isSelected = (entry.key == vm.filterMode)
        if type(b.RefreshVisualState) == "function" then
          b:RefreshVisualState()
        end
      end
    end
  end

  local bodyTop = bannerH + 6 + filterH + 8
  local vpH = math.max(160, vh - bodyTop)
  local rowWidth = vw - Theme.METRICS.scrollbarLaneWidth
  local content = ResearchView.viewport.content

  Widgets.SafeClearPoints(ResearchView.viewport)
  Widgets.SafeSetPoint(ResearchView.viewport, "TOPLEFT", host, "TOPLEFT", 0, -bodyTop)

  resetPool(ResearchView.cardPool)

  local y = 0
  local cardReports = {}

  for _, cvm in ipairs(vm.cards or {}) do
    local card = acquirePoolItem(ResearchView.cardPool, function()
      return createResearchCard(content)
    end)
    if card then
      if card.leftAccent then
        Widgets.SafeSetSolidColor(card.leftAccent, cvm.badgeToken or "status.research", 0.85)
      end
      Widgets.SetSurfaceBorder(card, "border.subtle", 1.0)

      local hasIcon = (cvm.itemID ~= nil)
      if card.icon then
        if hasIcon then
          card.icon:SetItem(cvm.itemID, cvm.title, generation)
          Widgets.SafeShow(card.icon, true)
        else
          Widgets.SafeShow(card.icon, false)
        end
      end

      local leftInset = hasIcon and 54 or 16
      local rightReserve = (not compact and cvm.discoveryAction) and 172 or 16
      local textW = math.max(240, rowWidth - leftInset - rightReserve)

      local curY = 10
      if card.badge then
        card.badge:Configure(cvm.badgeText, cvm.badgeToken or "status.research", nil, false)
        Widgets.SafeClearPoints(card.badge)
        Widgets.SafeSetPoint(card.badge, "TOPLEFT", card, "TOPLEFT", leftInset, -curY)
        Widgets.SafeShow(card.badge, true)
        curY = curY + 22
      end

      if card.titleText then
        Widgets.SafeClearPoints(card.titleText)
        Widgets.SafeSetPoint(card.titleText, "TOPLEFT", card, "TOPLEFT", leftInset, -curY)
        Theme.ApplyFont(card.titleText, "sectionTitle", "text.primary")
      end
      curY = curY + Theme.MeasureWrappedHeight(card.titleText, cvm.title or "", textW, "sectionTitle", 20, 0) + 3

      if card.summaryText then
        Widgets.SafeClearPoints(card.summaryText)
        Widgets.SafeSetPoint(card.summaryText, "TOPLEFT", card, "TOPLEFT", leftInset, -curY)
        Theme.ApplyFont(card.summaryText, "body", "text.secondary")
      end
      curY = curY + Theme.MeasureWrappedHeight(card.summaryText, cvm.summaryText or "", textW, "body", 18, 0) + 3

      if card.fallbackText then
        Widgets.SafeClearPoints(card.fallbackText)
        Widgets.SafeSetPoint(card.fallbackText, "TOPLEFT", card, "TOPLEFT", leftInset, -curY)
        Theme.ApplyFont(card.fallbackText, "dense", "accent.goldMuted")
      end
      curY = curY + Theme.MeasureWrappedHeight(card.fallbackText, cvm.fallbackText or "", textW, "dense", 16, 0) + 2

      if card.caveatText then
        Widgets.SafeClearPoints(card.caveatText)
        Widgets.SafeSetPoint(card.caveatText, "TOPLEFT", card, "TOPLEFT", leftInset, -curY)
        Theme.ApplyFont(card.caveatText, "dense", "text.muted")
      end
      curY = curY + Theme.MeasureWrappedHeight(card.caveatText, cvm.caveatText or "", textW, "dense", 16, 0) + 4

      if card.discoveryBtn then
        if cvm.discoveryAction then
          card.discoveryBtn:SetLabel(cvm.discoveryAction.label)
          local dAct = cvm.discoveryAction
          card.discoveryBtn:SetOnClick(function()
            ResearchView.Dispatch("CREATE_RESEARCH_DISCOVERY_LIST", dAct)
          end)
          Widgets.SafeClearPoints(card.discoveryBtn)
          if compact then
            Widgets.SafeSetPoint(card.discoveryBtn, "TOPLEFT", card, "TOPLEFT", leftInset, -(curY + 2))
            curY = curY + 34
          else
            Widgets.SafeSetPoint(card.discoveryBtn, "TOPRIGHT", card, "TOPRIGHT", -12, -14)
          end
          Widgets.SafeShow(card.discoveryBtn, true)
        else
          Widgets.SafeShow(card.discoveryBtn, false)
        end
      end

      local cardH = math.max(88, curY + 10)
      Widgets.SafeClearPoints(card)
      Widgets.SafeSetPoint(card, "TOPLEFT", content, "TOPLEFT", 0, -y)
      Widgets.SafeSetSize(card, rowWidth, cardH)
      Widgets.SafeShow(card, true)

      table.insert(cardReports, {
        cardID = cvm.cardID,
        rung = cvm.rung,
        mode = cvm.mode,
        allowBuyCta = cvm.allowBuyCta,
        badgeText = cvm.badgeText,
        badgeToken = cvm.badgeToken,
        fallbackText = cvm.fallbackText,
        width = rowWidth,
        height = cardH,
        y = y,
      })
      y = y + cardH + 8
    end
  end

  ResearchView.viewport:SetDimensions(vw, vpH, math.max(vpH, y + 12))
  ResearchView.viewport:SetScrollOffset(rState.scrollOffset or 0, true)

  local report = {
    isCompact = compact,
    viewportWidth = vw,
    viewportHeight = vh,
    rowWidth = rowWidth,
    cardCount = #cardReports,
    cards = cardReports,
    contentHeight = y,
  }
  ResearchView.lastLayoutReport = report
  return report
end

function ResearchView.Refresh()
  ResearchView.EnsureHost()
  if ns.UI.Workspace and ns.UI.Workspace.IsShown and ns.UI.Workspace.IsShown() then
    local st = ns.State.GetWorkspaceUIState()
    if st.activeTab == "research" then
      ns.UI.Workspace.Refresh()
    end
  end
  return true
end

function ResearchView.RefreshIfShown()
  return ResearchView.Refresh()
end

function ResearchView.Toggle()
  ResearchView.EnsureHost()
  if ns.UI.Workspace and ns.UI.Workspace.Toggle then
    ns.UI.Workspace.Toggle("research")
    return true
  end
  return false
end

if ns.UI.Workspace and ns.UI.Workspace.RegisterTabRenderer then
  ns.UI.Workspace.RegisterTabRenderer("research", {
    Refresh = function(_, contentWidth, contentHeight, isCompact)
      ResearchView.RenderInHost(contentWidth, contentHeight, isCompact)
    end,
  })
end

return ResearchView
