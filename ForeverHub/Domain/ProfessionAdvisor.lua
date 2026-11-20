local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.Domain = ns.Domain or {}

local ProfessionAdvisor = {}
ns.Domain.ProfessionAdvisor = ProfessionAdvisor

ProfessionAdvisor.SCHEMA = "foreverhub-profession-advisor-v1"
ProfessionAdvisor.MAX_PRIMARY_PROFESSIONS = 2
ProfessionAdvisor.ALLOW_AUTOMATED_UNLEARN = false

local PRIMARY_PROFESSIONS = {
  ALCHEMY = {
    key = "ALCHEMY",
    label = "Alchemy",
    role = "production",
    gatheringDependency = "HERBALISM",
    hasCooldown = true,
    starterOutlayNote = "Requires herbs or AH capital; pair with Herbalism while leveling.",
  },
  BLACKSMITHING = {
    key = "BLACKSMITHING",
    label = "Blacksmithing",
    role = "production",
    gatheringDependency = "MINING",
    hasCooldown = false,
    starterOutlayNote = "High ore/stone sink while leveling; keep only if already invested or funded.",
  },
  ENCHANTING = {
    key = "ENCHANTING",
    label = "Enchanting",
    role = "hybrid_item_and_service",
    gatheringDependency = nil,
    hasCooldown = false,
    supportsAuctionableVellums = false,
    starterOutlayNote = "Wands/oils are physical items; gear enchants require live trade-window customers (no AH vellums assumed).",
  },
  ENGINEERING = {
    key = "ENGINEERING",
    label = "Engineering",
    role = "utility_production",
    gatheringDependency = "MINING",
    hasCooldown = false,
    starterOutlayNote = "Primarily combat/utility sink; select targeted ammo/parts only with verified spreads.",
  },
  HERBALISM = {
    key = "HERBALISM",
    label = "Herbalism",
    role = "gathering",
    gatheringDependency = nil,
    hasCooldown = false,
    starterOutlayNote = "Zero reagent sink; gathers open-world herbs along quest and grind routes.",
  },
  LEATHERWORKING = {
    key = "LEATHERWORKING",
    label = "Leatherworking",
    role = "production",
    gatheringDependency = "SKINNING",
    hasCooldown = true,
    starterOutlayNote = "Converts unreserved leather into vendor/AH armor kits and Salt Shaker cooldowns at 250+.",
  },
  MINING = {
    key = "MINING",
    label = "Mining",
    role = "gathering",
    gatheringDependency = nil,
    hasCooldown = false,
    starterOutlayNote = "Zero reagent sink; gathers ore, stone, and Arcane Crystals at 275+.",
  },
  SKINNING = {
    key = "SKINNING",
    label = "Skinning",
    role = "gathering",
    gatheringDependency = nil,
    hasCooldown = false,
    starterOutlayNote = "Lowest-friction mount-funding gatherer; adds vendor/AH leather floor to beast grind loops (requires Skinning Knife).",
  },
  TAILORING = {
    key = "TAILORING",
    label = "Tailoring",
    role = "production",
    gatheringDependency = nil,
    hasCooldown = true,
    starterOutlayNote = "Uses humanoid cloth drops without a gathering slot; unlocks Mooncloth cooldown at 250.",
  },
}

local SECONDARY_SKILLS = {
  FIRST_AID = {
    key = "FIRST_AID",
    label = "First Aid",
    consumesPrimarySlot = false,
    note = "Secondary skill (does NOT use a primary profession slot). Converts unreserved cloth into bandages for combat uptime or verified vendor uplift.",
  },
  COOKING = {
    key = "COOKING",
    label = "Cooking",
    consumesPrimarySlot = false,
    note = "Secondary skill (does NOT use a primary profession slot). Converts beast meat & fish drops into stamina/spirit food or vendor value.",
  },
  FISHING = {
    key = "FISHING",
    label = "Fishing",
    consumesPrimarySlot = false,
    note = "Secondary skill (does NOT use a primary profession slot). Zero-combat raw fish & wreckage gathering.",
  },
}

local ENCHANTING_CATALOG = {
  {
    entryID = "ench_lesser_magic_wand",
    name = "Lesser Magic Wand",
    minRank = 10,
    outputMode = "physical_item",
    outputItemID = 11287,
    auctionableItem = true,
    executionNote = "Physical wand item: vendor price resolved via VendorArbitrage / ForeverHub_EconomyData (110c in Forever).",
  },
  {
    entryID = "ench_greater_magic_wand",
    name = "Greater Magic Wand",
    minRank = 70,
    outputMode = "physical_item",
    outputItemID = 11288,
    auctionableItem = true,
    executionNote = "Physical wand item: nerfed to 1c vendor price in WoW: Forever (Bluepost #5); AH sale only.",
  },
  {
    entryID = "ench_lesser_mystic_wand",
    name = "Lesser Mystic Wand",
    minRank = 155,
    outputMode = "physical_item",
    outputItemID = 11289,
    auctionableItem = true,
    executionNote = "Physical wand item: nerfed to 1c vendor price in WoW: Forever (Bluepost #5); AH sale only.",
  },
  {
    entryID = "ench_greater_mystic_wand",
    name = "Greater Mystic Wand",
    minRank = 175,
    outputMode = "physical_item",
    outputItemID = 11290,
    auctionableItem = true,
    executionNote = "Physical wand item: nerfed to 1c vendor price in WoW: Forever (Bluepost #5); AH sale only.",
  },
  {
    entryID = "ench_minor_wizard_oil",
    name = "Minor Wizard Oil",
    minRank = 45,
    outputMode = "physical_item",
    outputItemID = 20744,
    isWizardOil = true,
    auctionableItem = true,
    executionNote = "Physical caster oil: nerfed to 1s (100c) vendor sell value in WoW: Forever (Bluepost #4).",
  },
  {
    entryID = "ench_service_bracer_stamina",
    name = "Enchant Bracer - Greater Stamina",
    minRank = 245,
    outputMode = "trade_window_customer_service",
    outputItemID = nil,
    auctionableItem = false,
    executionNote = "Trade-window service (requires live buyer & 'Will Not Be Traded' slot; no AH vellum assumed).",
  },
  {
    entryID = "ench_service_weapon_crusader",
    name = "Enchant Weapon - Crusader",
    minRank = 300,
    outputMode = "trade_window_customer_service",
    outputItemID = nil,
    auctionableItem = false,
    executionNote = "Trade-window service (requires live buyer & 'Will Not Be Traded' slot; no AH vellum assumed).",
  },
}

local COOLDOWN_DEFINITIONS = {
  tailoring_mooncloth = {
    cooldownID = "tailoring_mooncloth",
    professionKey = "TAILORING",
    minRank = 250,
    label = "Mooncloth",
    durationSeconds = 96 * 3600,
    locationRequirement = "Moonwell",
  },
  alchemy_transmute_arcanite = {
    cooldownID = "alchemy_transmute_arcanite",
    sharedCooldownGroup = "alchemy_shared_transmute",
    sharedVariants = { "Transmute: Arcanite", "Transmute: Legionite", "Elemental Transmutes" },
    professionKey = "ALCHEMY",
    minRank = 275,
    label = "Transmute: Arcanite",
    durationSeconds = 47 * 3600,
    staticDurationSeconds = 48 * 3600,
    locationRequirement = "Philosopher's Stone in bags",
  },
  lw_salt_shaker = {
    cooldownID = "lw_salt_shaker",
    professionKey = "LEATHERWORKING",
    minRank = 250,
    label = "Salt Shaker (Refined Deepsea Salt)",
    durationSeconds = 72 * 3600,
    locationRequirement = "Salt Shaker in bags",
  },
}

local function normalizeProfKey(raw)
  if type(raw) ~= "string" then
    return nil
  end
  local s = string.upper(string.gsub(raw, "^%s*(.-)%s*$", "%1"))
  s = string.gsub(s, "[%s%-]+", "_")
  return s
end

function ProfessionAdvisor.ClassifySkillKind(skillKey)
  local k = normalizeProfKey(skillKey)
  if not k then
    return "unknown", nil
  end
  if PRIMARY_PROFESSIONS[k] then
    return "primary", PRIMARY_PROFESSIONS[k]
  end
  if SECONDARY_SKILLS[k] then
    return "secondary", SECONDARY_SKILLS[k]
  end
  return "unknown", nil
end

function ProfessionAdvisor.RequestUnlearn(_skillKey)
  return false, "profession_unlearn_forbidden_manual_only"
end

function ProfessionAdvisor.PartitionEnchantingCatalog(rank, opts)
  opts = type(opts) == "table" and opts or {}
  local curRank = math.max(0, math.floor(tonumber(rank) or 0))
  local vellumsVerified = (opts.supportsAuctionableVellums == true)
  local includeWizardOils = (opts.includeWizardOils == true)

  local physicalItems = {}
  local customerServices = {}

  for _, entry in ipairs(ENCHANTING_CATALOG) do
    local skipEntry = (entry.isWizardOil == true and not includeWizardOils)
    if not skipEntry and (curRank >= entry.minRank or opts.includeUnlearnedRanks == true) then
      local resolvedVendorCopper = nil
      local vendorPriceStatus = nil
      local quarantineReason = nil

      if entry.outputItemID and ns.Domain and ns.Domain.VendorArbitrage and type(ns.Domain.VendorArbitrage.ResolveVerifiedVendorSellPrice) == "function" then
        local vRes = ns.Domain.VendorArbitrage.ResolveVerifiedVendorSellPrice(entry.outputItemID, {
          allowStaticWhenClientUnavailable = (opts.allowStaticWhenClientUnavailable ~= false),
          liveSellPriceLookup = opts.liveSellPriceLookup,
        })
        if vRes then
          vendorPriceStatus = vRes.status
          if vRes.status == "ok" and type(vRes.unitSellPrice) == "number" then
            resolvedVendorCopper = vRes.unitSellPrice
          elseif vRes.status == "quarantined_sell_price_mismatch" then
            quarantineReason = vRes.quarantineReason
          end
        end
      end

      local copyEntry = {
        entryID = entry.entryID,
        name = entry.name,
        minRank = entry.minRank,
        learnedEligible = (curRank >= entry.minRank),
        outputMode = entry.outputMode,
        outputItemID = entry.outputItemID,
        auctionableItem = entry.auctionableItem,
        supportsAuctionableVellums = vellumsVerified,
        vendorSellCopper = resolvedVendorCopper,
        vendorPriceStatus = vendorPriceStatus,
        quarantineReason = quarantineReason,
        executionNote = entry.executionNote,
      }
      if entry.outputMode == "physical_item" then
        table.insert(physicalItems, copyEntry)
      else
        copyEntry.ahListingBlockedReason = vellumsVerified and nil or "no_auctionable_vellum_in_classic_forever"
        table.insert(customerServices, copyEntry)
      end
    end
  end

  return {
    supportsAuctionableVellums = vellumsVerified,
    physicalItems = physicalItems,
    customerServices = customerServices,
  }
end

function ProfessionAdvisor.EvaluateMultiAltCooldowns(altRecords, nowSeconds)
  local nowSec = math.max(0, math.floor(tonumber(nowSeconds) or 0))
  local results = {}

  for _, alt in ipairs(type(altRecords) == "table" and altRecords or {}) do
    local charKey = tostring(alt.characterKey or alt.name or "UnknownAlt")
    local isCurrent = (alt.isCurrentCharacter == true)
    local observedNow = (alt.observedNow == true)
    local lastObs = tonumber(alt.lastObservedAt)
    local skills = type(alt.learnedSkills) == "table" and alt.learnedSkills or {}
    local cdMap = type(alt.cooldownReadyAtByID) == "table" and alt.cooldownReadyAtByID or {}

    for cdID, def in pairs(COOLDOWN_DEFINITIONS) do
      local profRank = tonumber(skills[def.professionKey]) or 0
      if profRank >= def.minRank then
        local readyAt = tonumber(cdMap[cdID] or cdMap[string.upper(cdID)])
        local confidenceMode
        local state
        local remainingSeconds = nil
        local stalenessSeconds = nil
        local statusLabel

        if isCurrent and observedNow and readyAt ~= nil then
          confidenceMode = "live_verified"
          stalenessSeconds = 0
          remainingSeconds = math.max(0, math.floor(readyAt - nowSec))
          state = (remainingSeconds == 0) and "READY" or "ON_COOLDOWN"
          statusLabel = (remainingSeconds == 0)
              and string.format("%s: Ready now (live verified)", def.label)
            or string.format("%s: %dh %dm left (live verified)", def.label, math.floor(remainingSeconds / 3600), math.floor((remainingSeconds % 3600) / 60))
        elseif lastObs ~= nil and readyAt ~= nil then
          confidenceMode = "estimated_from_last_observation"
          stalenessSeconds = math.max(0, math.floor(nowSec - lastObs))
          remainingSeconds = math.max(0, math.floor(readyAt - nowSec))
          state = (remainingSeconds == 0) and "ESTIMATED_READY" or "ESTIMATED_ON_COOLDOWN"
          local staleHours = math.floor(stalenessSeconds / 3600)
          statusLabel = (remainingSeconds == 0)
              and string.format("%s: Expected ready — last observed %dh ago", def.label, staleHours)
            or string.format("%s: ~%dh left — last observed %dh ago", def.label, math.ceil(remainingSeconds / 3600), staleHours)
        else
          confidenceMode = "unknown_never_observed"
          state = "UNKNOWN_UNOBSERVED"
          statusLabel = string.format("%s: Unknown — log onto %s to observe cooldown timer", def.label, charKey)
        end

        table.insert(results, {
          characterKey = charKey,
          cooldownID = cdID,
          professionKey = def.professionKey,
          label = def.label,
          locationRequirement = def.locationRequirement,
          state = state,
          confidenceMode = confidenceMode,
          lastObservedAt = lastObs,
          stalenessSeconds = stalenessSeconds,
          readyAtEpoch = readyAt,
          remainingSeconds = remainingSeconds,
          statusLabel = statusLabel,
        })
      end
    end
  end

  table.sort(results, function(a, b)
    if a.characterKey ~= b.characterKey then
      return a.characterKey < b.characterKey
    end
    return a.cooldownID < b.cooldownID
  end)

  return results
end

function ProfessionAdvisor.CompareProfessionSwitch(opts)
  opts = type(opts) == "table" and opts or {}
  local curKey = normalizeProfKey(opts.currentProfession)
  local nextKey = normalizeProfKey(opts.proposedProfession)
  local curKind, curMeta = ProfessionAdvisor.ClassifySkillKind(curKey)
  local nextKind, nextMeta = ProfessionAdvisor.ClassifySkillKind(nextKey)

  if curKind == "secondary" or nextKind == "secondary" then
    return {
      status = "invalid_secondary_switch",
      reason = "Secondary skills (First Aid, Cooking, Fishing) never occupy primary slots and never need to be unlearned.",
      allowAutomatedUnlearn = false,
    }
  end
  if curKind ~= "primary" or nextKind ~= "primary" then
    return {
      status = "invalid_profession_key",
      reason = "Both currentProfession and proposedProfession must be valid primary professions.",
      allowAutomatedUnlearn = false,
    }
  end

  local curRank = math.max(0, math.floor(tonumber(opts.currentRank) or 0))
  local rareRecipes = {}
  for _, r in ipairs(type(opts.knownRareRecipes) == "table" and opts.knownRareRecipes or {}) do
    table.insert(rareRecipes, tostring(r))
  end

  local lostCooldowns = {}
  for cdID, def in pairs(COOLDOWN_DEFINITIONS) do
    if def.professionKey == curKey and curRank >= def.minRank then
      table.insert(lostCooldowns, cdID)
    end
  end
  table.sort(lostCooldowns)

  local retrainOutlay = tonumber(opts.estimatedRetrainingOutlayCopper)
  local retrainTimeCost = math.max(0, math.floor(tonumber(opts.retrainingTimeOpportunityCostCopper) or 0))
  local candidateDailyNet = tonumber(opts.candidateDailyNetCopper or opts.verifiedDailyNetGainCopper)
  local currentDailyNet = math.max(0, math.floor(tonumber(opts.currentProfessionDailyNetCopper) or 0))
  local lostCooldownDailyNet = math.max(0, math.floor(tonumber(opts.lostCooldownDailyValueCopper) or 0))

  -- Astra P1.4: Payback denominator MUST be incremental net gain versus keeping the current profession:
  local incrementalDailyNetGain = nil
  local baselineComparisonMode = "missing_daily_net"
  if candidateDailyNet ~= nil then
    if opts.currentProfessionDailyNetCopper ~= nil or opts.lostCooldownDailyValueCopper ~= nil then
      incrementalDailyNetGain = candidateDailyNet - currentDailyNet - lostCooldownDailyNet
      baselineComparisonMode = "candidate_minus_current_baseline"
    else
      incrementalDailyNetGain = candidateDailyNet
      baselineComparisonMode = "explicit_incremental_input"
    end
  end

  local totalSwitchCostCopper = (retrainOutlay ~= nil and retrainOutlay >= 0) and (retrainOutlay + retrainTimeCost) or nil
  local paybackDays = nil
  local paybackHorizonLabel = "UNKNOWN — requires verified output sale-through & retraining cost"

  if totalSwitchCostCopper ~= nil and incrementalDailyNetGain ~= nil then
    if incrementalDailyNetGain <= 0 then
      paybackDays = nil
      paybackHorizonLabel = "NEVER — candidate profession does not beat keeping current profession"
    elseif totalSwitchCostCopper == 0 then
      paybackDays = 0
      paybackHorizonLabel = "Immediate (0c switch cost with positive incremental daily net gain)"
    else
      paybackDays = math.ceil(totalSwitchCostCopper / incrementalDailyNetGain)
      paybackHorizonLabel = string.format("~%d day(s) at incremental daily net gain vs keeping %s", paybackDays, curMeta.label)
    end
  end

  local highLossRisk = (curRank >= 150) or (#rareRecipes > 0) or (#lostCooldowns > 0)

  return {
    status = "ok",
    allowAutomatedUnlearn = false,
    manualActionWarning = "ForeverHub never unlearns professions automatically. Unlearning permanently destroys skill ranks and learned recipes.",
    currentProfession = curKey,
    currentLabel = curMeta.label,
    currentRank = curRank,
    proposedProfession = nextKey,
    proposedLabel = nextMeta.label,
    sunkSkillRanksLost = curRank,
    lostRareRecipes = rareRecipes,
    lostActiveCooldowns = lostCooldowns,
    estimatedRetrainingOutlayCopper = retrainOutlay,
    retrainingTimeOpportunityCostCopper = retrainTimeCost,
    totalSwitchCostCopper = totalSwitchCostCopper,
    candidateDailyNetCopper = candidateDailyNet,
    currentProfessionDailyNetCopper = currentDailyNet,
    lostCooldownDailyValueCopper = lostCooldownDailyNet,
    incrementalDailyNetGainCopper = incrementalDailyNetGain,
    baselineComparisonMode = baselineComparisonMode,
    retrainingCostStatus = (retrainOutlay ~= nil) and "supplied" or "unpriced_without_market_depth",
    paybackDays = paybackDays,
    paybackHorizonLabel = paybackHorizonLabel,
    recommendation = highLossRisk and "HOLD_EXISTING_PROFESSION_REVIEW_LOSSES" or "MANUAL_SWITCH_LOW_SUNK_COST",
  }
end

function ProfessionAdvisor.EvaluateCharacterPlan(opts)
  opts = type(opts) == "table" and opts or {}
  local snapStatus = tostring(opts.snapshotStatus or "COMPLETE")
  if snapStatus ~= "COMPLETE" then
    return {
      status = "incomplete_profession_snapshot",
      snapshotStatus = snapStatus,
      allowAutomatedUnlearn = false,
      unknownStateNote = "Profession snapshot is "
        .. snapStatus
        .. " — open your Skills pane or wait for client metadata. ForeverHub never assumes open primary slots while profession data is incomplete.",
      prioritizedActions = {},
      altCooldowns = ProfessionAdvisor.EvaluateMultiAltCooldowns(opts.altCooldownRecords, opts.nowSeconds),
    }
  end

  local level = math.max(1, math.floor(tonumber(opts.level) or 1))
  local hasBasicMount = (opts.hasBasicMount == true)
  local rawSkills = type(opts.learnedSkills) == "table" and opts.learnedSkills or {}

  local learnedPrimary = {}
  local learnedSecondary = {}

  for rawKey, rankVal in pairs(rawSkills) do
    local rank = math.floor(tonumber(rankVal) or 0)
    if rank > 0 then
      local kind, meta = ProfessionAdvisor.ClassifySkillKind(rawKey)
      if kind == "primary" then
        table.insert(learnedPrimary, {
          key = meta.key,
          label = meta.label,
          rank = rank,
          role = meta.role,
          supportsAuctionableVellums = meta.supportsAuctionableVellums,
        })
      elseif kind == "secondary" then
        table.insert(learnedSecondary, {
          key = meta.key,
          label = meta.label,
          rank = rank,
          consumesPrimarySlot = false,
        })
      end
    end
  end

  table.sort(learnedPrimary, function(a, b)
    return a.key < b.key
  end)
  table.sort(learnedSecondary, function(a, b)
    return a.key < b.key
  end)

  if #learnedPrimary > ProfessionAdvisor.MAX_PRIMARY_PROFESSIONS then
    return {
      status = "invalid_primary_slot_count",
      reason = string.format(
        "Snapshot reported %d primary professions (maximum allowed is %d).",
        #learnedPrimary,
        ProfessionAdvisor.MAX_PRIMARY_PROFESSIONS
      ),
      primarySlotCap = ProfessionAdvisor.MAX_PRIMARY_PROFESSIONS,
      learnedPrimary = learnedPrimary,
      learnedSecondary = learnedSecondary,
      prioritizedActions = {},
    }
  end

  local openPrimarySlots = ProfessionAdvisor.MAX_PRIMARY_PROFESSIONS - #learnedPrimary
  local prioritizedActions = {}
  local enchantingBreakdown = nil

  -- Priority Tier 1: Existing learned primary professions & secondary skills FIRST (0-switch, low commitment):
  for _, p in ipairs(learnedPrimary) do
    if p.key == "ENCHANTING" then
      enchantingBreakdown = ProfessionAdvisor.PartitionEnchantingCatalog(p.rank, {
        supportsAuctionableVellums = false,
      })
      table.insert(prioritizedActions, {
        priorityTier = 1,
        commitmentLevel = "existing_skill",
        skillKind = "primary",
        professionKey = p.key,
        title = string.format("Use existing Enchanting (Rank %d) — physical wands/oils first", p.rank),
        detail = string.format(
          "%d physical wand/oil recipe(s) eligible for item accounting; %d trade-window enchant(s) kept separate (no AH vellum assumed).",
          #enchantingBreakdown.physicalItems,
          #enchantingBreakdown.customerServices
        ),
      })
    else
      local meta = PRIMARY_PROFESSIONS[p.key]
      table.insert(prioritizedActions, {
        priorityTier = 1,
        commitmentLevel = "existing_skill",
        skillKind = "primary",
        professionKey = p.key,
        title = string.format("Continue existing %s (Rank %d)", p.label, p.rank),
        detail = meta and meta.starterOutlayNote or "Prioritize learned recipes & unreserved materials before spending capital.",
      })
    end
  end

  for _, s in ipairs(learnedSecondary) do
    local smeta = SECONDARY_SKILLS[s.key]
    table.insert(prioritizedActions, {
      priorityTier = 1,
      commitmentLevel = "existing_secondary_skill",
      skillKind = "secondary",
      professionKey = s.key,
      title = string.format("Use Secondary %s (Rank %d — 0 primary slots used)", s.label, s.rank),
      detail = smeta and smeta.note or "",
    })
  end

  -- Priority Tier 2: Recommend missing Secondary First Aid (never consumes a primary slot):
  local knowsFirstAid = false
  for _, s in ipairs(learnedSecondary) do
    if s.key == "FIRST_AID" then
      knowsFirstAid = true
      break
    end
  end
  if not knowsFirstAid then
    table.insert(prioritizedActions, {
      priorityTier = 2,
      commitmentLevel = "low_commitment_secondary",
      skillKind = "secondary",
      professionKey = "FIRST_AID",
      title = "Learn Secondary Skill: First Aid (keeps both primary slots free)",
      detail = SECONDARY_SKILLS.FIRST_AID.note,
    })
  end

  -- Priority Tier 3: Only when primary slots are actually open, suggest zero-reagent-sink gathering:
  if openPrimarySlots > 0 then
    local learnedSet = {}
    for _, p in ipairs(learnedPrimary) do
      learnedSet[p.key] = true
    end
    local gatherCandidates = (not hasBasicMount and level < 40)
        and { "SKINNING", "HERBALISM", "MINING" }
      or { "HERBALISM", "MINING", "SKINNING" }

    local suggestedCount = 0
    for _, gKey in ipairs(gatherCandidates) do
      if not learnedSet[gKey] and suggestedCount < openPrimarySlots then
        suggestedCount = suggestedCount + 1
        local gMeta = PRIMARY_PROFESSIONS[gKey]
        table.insert(prioritizedActions, {
          priorityTier = 3,
          commitmentLevel = "fill_open_primary_slot",
          skillKind = "primary",
          professionKey = gKey,
          title = string.format("Optional Open Primary Slot (%d/%d free): %s", openPrimarySlots, ProfessionAdvisor.MAX_PRIMARY_PROFESSIONS, gMeta.label),
          detail = gMeta.starterOutlayNote,
        })
      end
    end
  end

  local altCooldowns = ProfessionAdvisor.EvaluateMultiAltCooldowns(opts.altCooldownRecords, opts.nowSeconds)

  return {
    status = "ok",
    schema = ProfessionAdvisor.SCHEMA,
    allowAutomatedUnlearn = false,
    primarySlotCap = ProfessionAdvisor.MAX_PRIMARY_PROFESSIONS,
    openPrimarySlots = openPrimarySlots,
    learnedPrimary = learnedPrimary,
    learnedSecondary = learnedSecondary,
    prioritizedActions = prioritizedActions,
    enchantingBreakdown = enchantingBreakdown,
    altCooldowns = altCooldowns,
  }
end

-- ============================================================================
-- Astra P1.4: Full Path Valuation V_path & Conditional 4-Way Second-Slot Rule
--   V_path = realized_net_receipts + conservative_ending_inventory_value
--            - training_and_acquisition_costs - time_opportunity_cost
-- ============================================================================

function ProfessionAdvisor.EvaluatePathComparison(pathSpec, opts)
  opts = type(opts) == "table" and opts or {}
  if type(pathSpec) ~= "table" then
    return nil, "invalid_path_spec"
  end

  local realizedNetReceipts = math.floor(tonumber(pathSpec.realizedNetReceiptsCopper) or 0)
  local conservativeEndingInv = math.max(0, math.floor(tonumber(pathSpec.conservativeEndingInventoryCopper) or 0))
  local trainingAndAcquisitionCost = math.max(0, math.floor(tonumber(pathSpec.trainingAndAcquisitionCostCopper) or 0))
  local timeOpportunityCost = math.max(0, math.floor(tonumber(pathSpec.timeOpportunityCostCopper) or 0))

  -- Catch-up range for late gathering start (e.g., Skinning 1->240 at Level 48):
  local catchUpMin = math.max(0, math.floor(tonumber(pathSpec.catchUpMinCostCopper) or 0))
  local catchUpMax = math.max(catchUpMin, math.floor(tonumber(pathSpec.catchUpMaxCostCopper) or catchUpMin))
  local routeCompetitionPenalty = math.max(0, math.floor(tonumber(pathSpec.routeCompetitionPenaltyCopper) or 0))
  local campOutlay = (pathSpec.campAccessMode == "owned_crafted_camp_outlay")
      and math.max(0, math.floor(tonumber(pathSpec.campCraftOutlayCopper) or 0))
    or 0

  local totalDeductionsMin = trainingAndAcquisitionCost + timeOpportunityCost + catchUpMin + routeCompetitionPenalty + campOutlay
  local totalDeductionsMax = trainingAndAcquisitionCost + timeOpportunityCost + catchUpMax + routeCompetitionPenalty + campOutlay

  local vPathConservativeCopper = realizedNetReceipts + conservativeEndingInv - totalDeductionsMax
  local vPathOptimisticCopper = realizedNetReceipts + conservativeEndingInv - totalDeductionsMin

  local usesBountifulHarvest = (pathSpec.usesBountifulHarvest == true)

  return {
    pathID = tostring(pathSpec.pathID or "unnamed_path"),
    label = tostring(pathSpec.label or pathSpec.pathID or "Unnamed Path"),
    realizedNetReceiptsCopper = realizedNetReceipts,
    conservativeEndingInventoryCopper = conservativeEndingInv,
    trainingAndAcquisitionCostCopper = trainingAndAcquisitionCost,
    timeOpportunityCostCopper = timeOpportunityCost,
    catchUpCostRangeCopper = { minCopper = catchUpMin, maxCopper = catchUpMax },
    routeCompetitionPenaltyCopper = routeCompetitionPenalty,
    campAccessMode = pathSpec.campAccessMode or "none_or_shared_party_camp",
    campCraftOutlayCopper = campOutlay,
    usesBountifulHarvest = usesBountifulHarvest,
    bountifulHarvestMechanic = "SCARCE_MATERIAL_DISCOVERY_5_RANK_LEGACY",
    bountifulHarvestClaimID = "legacy_node_5_bountiful_harvest",
    ordinaryGatherMultiplierQuarantined = true,
    legacyPointsCommitted = usesBountifulHarvest and 5 or 0,
    maxActiveLegacyPoints = 16,
    legacyOpportunityNote = usesBountifulHarvest
      and "Commits 5/16 active Legacy points to Bountiful Harvest (5/5 Professions Legacy Tree entry perk: +20% to +100% Scarce material discovery; Survival ordinary-node double-yield claim quarantined)."
      or "0/16 active Legacy points required.",
    vPathConservativeCopper = vPathConservativeCopper,
    vPathOptimisticCopper = vPathOptimisticCopper,
  }
end

-- ============================================================================
-- Astra P0 & P1: Tailoring 175 -> 250 Progression Cost, Forever Skill Profile,
-- Opening Tranche Dual Cash/Opportunity Accounting & 2026 Mooncloth Schedule
-- ============================================================================

-- Blizzard confirmed December 9, 2026 raid unlock anchor (2026-12-09T16:00:00Z -> 1796832000).
-- Until an exact unlock hour is verified, label the 16:00 UTC reset cutoff assumption explicitly.
ProfessionAdvisor.DEC9_2026_RAID_UNLOCK_EPOCH = 1796832000
ProfessionAdvisor.DEC9_2026_CUTOFF_ASSUMPTION_NOTE =
  "Blizzard confirms December 9, 2026 raid unlock date; 16:00 UTC reset hour is an assumed cutoff until exact unlock hour is verified."
ProfessionAdvisor.MOONCLOTH_COOLDOWN_SECONDS = 96 * 3600

ProfessionAdvisor.CLASSIC_TAILORING_CANDIDATE_STEPS_175_250 = {
  {
    stepID = "tailor_175_185_bolt_of_mageweave",
    rangeStart = 175,
    rangeEnd = 185,
    recipeName = "Bolt of Mageweave",
    spellID = 3865,
    outputItemID = 4339,
    recipeSource = "TRAINER",
    classicGraySkill = 205,
    note = "Classic Bolt of Silk Cloth (4305) grays at 175; Bolt of Mageweave (spell 3865 -> item 4339, 5x Mageweave Cloth) is the Classic baseline.",
  },
  {
    stepID = "tailor_185_215_crimson_silk",
    rangeStart = 185,
    rangeEnd = 215,
    recipeName = "Crimson Silk Vest / Crimson Silk Pantaloons",
    recipeSource = "TRAINER",
    note = "Bolt of Mageweave grays at 205 in Classic; Crimson Silk crafts bridge 185-215.",
  },
  {
    stepID = "tailor_215_220_black_mageweave_vest_or_leggings",
    rangeStart = 215,
    rangeEnd = 220,
    recipeName = "Black Mageweave Vest / Black Mageweave Leggings",
    recipeSource = "TRAINER",
    note = "Trainer-only candidate path (Pattern: White Bandit Mask is item 10301 and grays at 230 in Classic).",
  },
  {
    stepID = "tailor_220_230_black_mageweave_gloves",
    rangeStart = 220,
    rangeEnd = 230,
    recipeName = "Black Mageweave Gloves",
    recipeSource = "TRAINER",
    note = "Trainer-only candidate path for 220-230.",
  },
  {
    stepID = "tailor_230_250_black_mageweave_headband",
    rangeStart = 230,
    rangeEnd = 250,
    recipeName = "Black Mageweave Headband",
    recipeSource = "TRAINER",
    note = "Trainer-only candidate path for 230-250; Forever skill-color thresholds must be verified in-client.",
  },
}

-- Installed WoW: Forever skill table profile (`Blackthornes_TS/Data/LearnSpots.lua:591, 891, 938`):
-- Separate from `CLASSIC_TAILORING_CANDIDATE_STEPS_175_250` per Astra P1:
ProfessionAdvisor.FOREVER_TAILORING_SKILL_PROFILE_175_250 = {
  {
    stepID = "forever_bolt_of_mageweave",
    recipeName = "Bolt of Mageweave",
    spellID = 3865,
    outputItemID = 4339,
    clothPerBolt = 5,
    trivialAt175 = true,
    note = "Spell 3865 -> item 4339 uses 5x Mageweave Cloth (4338) and is trivial at 175 (spell 3844 is Heavy Woolen Cloak).",
  },
  {
    stepID = "forever_175_185_black_mageweave_leggings_or_vest",
    recipeName = "Black Mageweave Leggings / Black Mageweave Vest",
    leggingsSpellID = 12049,
    leggingsOutputItemID = 9999,
    leggingsVendorUnitCopper = 4832,
    vestSpellID = 12048,
    vestOutputItemID = 9998,
    vestVendorUnitCopper = 4815,
    learnSkill = 170,
    yellowSkill = 185,
    graySkill = 215,
    boltsPerCraft = 2,
    silkenThreadPerCraft = 3,
    note = "Both learned and orange at 175; turn yellow at 185 and gray at 215 in LearnSpots.lua:591. Craft 10 Leggings from 175->185 while orange, then refresh skill colors.",
  },
  {
    stepID = "forever_185_200_gloves_and_headband_comparison",
    recipeName = "Black Mageweave Gloves / Black Mageweave Headband",
    glovesSpellID = 12053,
    glovesThresholds = { 180, 195, 225 },
    headbandSpellID = 12062,
    headbandThresholds = { 185, 200, 230 },
    artisanTrainer = "Timothy Worthington (Theramore Isle)",
    note = "From 185, refresh skill colors and compare Leggings with Black Mageweave Gloves (12053), then Headband (12062) as it becomes available; check Artisan training once eligible.",
  },
  {
    stepID = "forever_205_bolt_of_runecloth",
    recipeName = "Bolt of Runecloth",
    spellID = 18401,
    outputItemID = 14048,
    clothPerBolt = 5,
    learnSkill = 205,
    yellowSkill = 210,
    graySkill = 215,
    note = "Installed Forever table gives Bolt of Runecloth at 205 (turns yellow at 210, gray at 215 in LearnSpots.lua:891). At 205, bolt the Runecloth intended for progression.",
  },
  {
    stepID = "forever_210_250_runecloth_belt_and_mooncloth",
    recipeName = "Runecloth Belt / Mooncloth",
    beltSpellID = 18402,
    beltOutputItemID = 14136,
    beltThresholds = { 210, 225, 255 },
    beltBoltsPerCraft = 3,
    moonclothSpellID = 18560,
    moonclothPatternItemID = 14526,
    moonclothOutputItemID = 14342,
    moonclothForeverThresholds = { 230, 270, 300 },
    moonclothClassicMinSkill = 250,
    note = "At 210, craft Runecloth Belts (3 bolts + 1 Rune Thread) and reprice when belts turn yellow at 225. Confirm Mooncloth rank (230 in Forever table vs 250 Classic) at trainer and on pattern tooltip.",
  },
}

function ProfessionAdvisor.EvaluateMoonclothCastSchedule(opts)
  opts = type(opts) == "table" and opts or {}
  local cutoffEpoch = tonumber(opts.raidCutoffEpoch) or ProfessionAdvisor.DEC9_2026_RAID_UNLOCK_EPOCH
  local cooldownSec = tonumber(opts.cooldownSeconds) or ProfessionAdvisor.MOONCLOTH_COOLDOWN_SECONDS
  local firstEligibleEpoch = tonumber(opts.firstEligibleCastEpoch)
  local ownedFelcloth = math.max(0, math.floor(tonumber(opts.ownedFelclothCount) or 0))
  local firstSaleVerified = (opts.firstMoonclothSaleVerified == true)

  if not firstEligibleEpoch or firstEligibleEpoch <= 0 then
    return {
      status = "AWAITING_FIRST_ELIGIBLE_CAST_TIME",
      raidCutoffEpoch = cutoffEpoch,
      cutoffAssumptionNote = ProfessionAdvisor.DEC9_2026_CUTOFF_ASSUMPTION_NOTE,
      ownedFelclothCount = ownedFelcloth,
      ownedCastsCovered = math.floor(ownedFelcloth / 2),
      maxPreCutoffCasts = nil,
      additionalFelclothJustifiedCount = 0,
    }
  end

  local castEpochs = {}
  local t = firstEligibleEpoch
  while t < cutoffEpoch do
    table.insert(castEpochs, t)
    t = t + cooldownSec
  end

  local maxCasts = #castEpochs
  local ownedCastsCovered = math.floor(ownedFelcloth / 2)
  local totalFelclothForMaxCasts = maxCasts * 2
  local deficitForMaxCasts = math.max(0, totalFelclothForMaxCasts - ownedFelcloth)
  local additionalJustified = (firstSaleVerified and maxCasts > ownedCastsCovered) and deficitForMaxCasts or 0

  return {
    status = "OK",
    raidCutoffEpoch = cutoffEpoch,
    cutoffAssumptionNote = ProfessionAdvisor.DEC9_2026_CUTOFF_ASSUMPTION_NOTE,
    firstEligibleCastEpoch = firstEligibleEpoch,
    cooldownSeconds = cooldownSec,
    castEpochs = castEpochs,
    maxPreCutoffCasts = maxCasts,
    ownedFelclothCount = ownedFelcloth,
    ownedCastsCovered = ownedCastsCovered,
    totalFelclothForMaxCasts = totalFelclothForMaxCasts,
    deficitFelclothForMaxCasts = deficitForMaxCasts,
    firstMoonclothSaleVerified = firstSaleVerified,
    additionalFelclothJustifiedCount = additionalJustified,
    scheduleNote = string.format(
      "%dx owned Felcloth covers %d cast(s) at t, t+4d, t+8d; %dx additional Felcloth justified only if %d casts fit before Dec 9, 2026 cutoff and demand is verified.",
      ownedFelcloth,
      ownedCastsCovered,
      deficitForMaxCasts,
      maxCasts
    ),
  }
end

function ProfessionAdvisor.EvaluateForeverTailoringOpeningTranche(opts)
  opts = type(opts) == "table" and opts or {}
  local currentSkill = math.floor(tonumber(opts.currentSkill) or 175)
  local orangeCutoffSkill = math.floor(tonumber(opts.orangeCutoffSkill) or 185)
  local orangeCrafts = math.max(0, math.min(tonumber(opts.openingCrafts) or (orangeCutoffSkill - currentSkill), orangeCutoffSkill - currentSkill))

  local ownedBolts = math.max(0, math.floor(tonumber(opts.ownedBoltOfMageweaveCount) or 55))
  local ownedMageweaveCloth = math.max(0, math.floor(tonumber(opts.ownedMageweaveClothCount) or 54))
  local ownedRunecloth = math.max(0, math.floor(tonumber(opts.ownedRuneclothCount) or 106))
  local ownedFelcloth = math.max(0, math.floor(tonumber(opts.ownedFelclothCount) or 6))
  local ownsMoonclothPattern = (opts.ownsMoonclothPattern ~= false)

  local clothPerBolt = 5 -- Spell 3865 -> item 4339 uses 5x Mageweave Cloth
  local maxBoltsFromOwnedCloth = math.floor(ownedMageweaveCloth / clothPerBolt)
  local maxTotalMageweaveBolts = ownedBolts + maxBoltsFromOwnedCloth
  local maxTotalLeggingsFromBank = math.floor(maxTotalMageweaveBolts / 2)

  -- Turning only 45 cloth into 9 bolts supplies 64 bolts (32 Leggings crafts) and leaves 9 cloth:
  local boltsNeededForMaxEvenLeggings = maxTotalLeggingsFromBank * 2
  local additionalBoltsNeededFor32 = math.max(0, boltsNeededForMaxEvenLeggings - ownedBolts)
  local clothConsumedForEvenLeggings = additionalBoltsNeededFor32 * clothPerBolt
  local leftoverClothAfterEvenLeggings = ownedMageweaveCloth - clothConsumedForEvenLeggings

  -- Opening tranche: 10 orange crafts (175 -> 185) of Black Mageweave Leggings (12049 -> 9999):
  local boltsPerCraft = 2
  local threadPerCraft = 3
  local threadUnitBuyCopper = tonumber(opts.silkenThreadUnitBuyCopper) or 500
  local leggingsVendorUnitCopper = tonumber(opts.leggingsVendorUnitCopper) or 4832
  local boltSavedAskCopper = tonumber(opts.boltOfMageweaveAskCopper) or 2775
  local clothSavedAskCopper = tonumber(opts.mageweaveClothAskCopper) or 340
  local clothVendorUnitCopper = tonumber(opts.mageweaveClothVendorCopper) or 250
  local boltVendorUnitCopper = tonumber(opts.boltOfMageweaveVendorCopper) or 1000
  local ahCutRate = tonumber(opts.ahCutRate) or 0.05

  local boltsUsedOpening = orangeCrafts * boltsPerCraft
  local ownedBoltsUsedOpening = math.min(ownedBolts, boltsUsedOpening)
  local extraBoltsFromClothOpening = math.max(0, boltsUsedOpening - ownedBoltsUsedOpening)
  local clothConsumedOpening = extraBoltsFromClothOpening * clothPerBolt

  local threadCostPerCraftCopper = threadPerCraft * threadUnitBuyCopper
  local upfrontCashOutlayCopper = orangeCrafts * threadCostPerCraftCopper
  local verifiedVendorProceedsCopper = orangeCrafts * leggingsVendorUnitCopper
  local netCashInflowCopper = verifiedVendorProceedsCopper - upfrontCashOutlayCopper

  -- Best attainable alternative for owned Bolt of Mageweave and raw Mageweave Cloth:
  local boltNetAhUnitCopper = math.floor((boltSavedAskCopper * (1.0 - ahCutRate)) + 0.5)
  local boltAlternativeUnitCopper = math.max(boltVendorUnitCopper, boltNetAhUnitCopper)
  local clothNetAhUnitCopper = math.floor((clothSavedAskCopper * (1.0 - ahCutRate)) + 0.5)
  local rawClothAlternativeUnitCopper = math.max(clothVendorUnitCopper, clothNetAhUnitCopper)

  -- Exact per-craft economic cost when 2 owned bolts could clear at saved ask with 5% cut:
  -- 2 * 2775 * 0.95 = 5272.5c (+ 1500c thread - 4832c vendor = 1940.5c -> rounds half-up to 1941c/craft):
  local twoBoltsNetAhExact = (boltsPerCraft * boltSavedAskCopper) * (1.0 - ahCutRate)
  local ownedBoltOpportunityPerCraftCopper = math.floor(math.max(boltsPerCraft * boltVendorUnitCopper, twoBoltsNetAhExact) + 0.5)
  local economicCostPerCraftCopper = ownedBoltOpportunityPerCraftCopper + threadCostPerCraftCopper - leggingsVendorUnitCopper
  local totalOpeningEconomicCostCopper = math.floor((orangeCrafts * ( math.max(boltsPerCraft * boltVendorUnitCopper, twoBoltsNetAhExact) + threadCostPerCraftCopper - leggingsVendorUnitCopper )) + 0.5)

  -- Runecloth progression math (205 Bolt of Runecloth, 210 Runecloth Belt):
  local runeclothBoltsFromBank = math.floor(ownedRunecloth / 5)
  local leftoverRuneclothAfterBolting = ownedRunecloth - (runeclothBoltsFromBank * 5)
  local runeclothBeltsFromBank = math.floor(runeclothBoltsFromBank / 3)
  local leftoverRuneclothBoltsAfterBelts = runeclothBoltsFromBank - (runeclothBeltsFromBank * 3)
  local minRuneclothForAllBelt210To250 = 40 * 3 * 5 -- 40 belts * 3 bolts * 5 cloth = 600 Runecloth minimum

  local patternPurchaseOutlayCopper = ownsMoonclothPattern and 0 or (tonumber(opts.patternAskCopper) or 0)
  local patternSavedVendorValueCopper = ownsMoonclothPattern and 5000 or 0

  return {
    status = "PRICED_OPENING_TRANCHE_CONDITIONAL_CONTINUATION",
    boltOfMageweaveSpellID = 3865,
    heavyWoolenCloakSpellID = 3844,
    blackMageweaveLeggingsSpellID = 12049,
    blackMageweaveLeggingsItemID = 9999,
    blackMageweaveVestSpellID = 12048,
    blackMageweaveVestItemID = 9998,
    clothPerMageweaveBolt = clothPerBolt,
    currentSkill = currentSkill,
    openingTargetSkill = currentSkill + orangeCrafts,
    openingOrangeCrafts = orangeCrafts,
    upfrontCashOutlayCopper = upfrontCashOutlayCopper,
    verifiedVendorProceedsCopper = verifiedVendorProceedsCopper,
    netCashInflowCopper = netCashInflowCopper,
    ownedBoltOpportunityPerCraftCopper = ownedBoltOpportunityPerCraftCopper,
    economicCostPerCraftCopper = economicCostPerCraftCopper,
    totalOpeningEconomicCostCopper = totalOpeningEconomicCostCopper,
    boltAlternativeUnitCopper = boltAlternativeUnitCopper,
    rawClothAlternativeUnitCopper = rawClothAlternativeUnitCopper,
    patternPurchaseOutlayCopper = patternPurchaseOutlayCopper,
    patternSavedVendorValueCopper = patternSavedVendorValueCopper,
    bankedInventorySummary = {
      initialBolts = ownedBolts,
      initialMageweaveCloth = ownedMageweaveCloth,
      maxBoltsFromCloth = maxBoltsFromOwnedCloth,
      maxTotalBolts = maxTotalMageweaveBolts,
      maxTotalLeggingsCrafts = maxTotalLeggingsFromBank,
      clothNeededForEven32Crafts = clothConsumedForEvenLeggings,
      boltsCreatedForEven32Crafts = additionalBoltsNeededFor32,
      leftoverClothAfterEven32Crafts = leftoverClothAfterEvenLeggings,
    },
    remainingInventoryAfterOpening10 = {
      remainingBoltOfMageweave = ownedBolts - ownedBoltsUsedOpening,
      remainingMageweaveCloth = ownedMageweaveCloth - clothConsumedOpening,
      remainingRunecloth = ownedRunecloth,
      remainingFelcloth = ownedFelcloth,
      ownsMoonclothPattern = ownsMoonclothPattern,
    },
    runeclothProgressionSummary = {
      bankedRunecloth = ownedRunecloth,
      boltsAt205 = runeclothBoltsFromBank,
      leftoverRunecloth = leftoverRuneclothAfterBolting,
      beltsAt210 = runeclothBeltsFromBank,
      leftoverBoltsAfterBelts = leftoverRuneclothBoltsAfterBelts,
      minRuneclothForAllBelt210To250 = minRuneclothForAllBelt210To250,
    },
    foreverSkillProfile = ProfessionAdvisor.FOREVER_TAILORING_SKILL_PROFILE_175_250,
  }
end

function ProfessionAdvisor.EvaluateTailoringProgressionCost(opts)
  opts = type(opts) == "table" and opts or {}
  local steps = type(opts.recipeSteps) == "table" and opts.recipeSteps or {}
  local trainingCopper = tonumber(opts.trainingCostCopper)
  local patternsCopper = tonumber(opts.patternAcquisitionCostCopper) or 0
  local travelCopper = tonumber(opts.travelCostCopper) or 0
  local foreverThresholdsVerified = (opts.foreverSkillThresholdsVerified == true)
  local openingTranche = ProfessionAdvisor.EvaluateForeverTailoringOpeningTranche(opts)

  if #steps == 0 or trainingCopper == nil or not foreverThresholdsVerified then
    return {
      status = "UNPRICED_WITHOUT_VERIFIED_THRESHOLDS_AND_DEPTH",
      reason = "Exact Forever net leveling cost requires verified Forever skill-color thresholds, recipe quantities, output vendor sell prices, material depth, and expected crafts N_r.",
      candidateSteps = ProfessionAdvisor.CLASSIC_TAILORING_CANDIDATE_STEPS_175_250,
      foreverSkillProfile = ProfessionAdvisor.FOREVER_TAILORING_SKILL_PROFILE_175_250,
      openingTranche = openingTranche,
      moonclothPatternItemID = 14526,
      boltOfMageweaveSpellID = 3865,
      boltOfRuneclothSpellID = 18401,
      whiteBanditMaskPatternItemID = 10301,
    }
  end

  local totalStepCostCopper = 0
  local totalCashOutlayCopper = 0
  local totalVendorProceedsCopper = 0
  local totalOwnedOpportunityCostCopper = 0
  local stepBreakdowns = {}
  for idx, st in ipairs(steps) do
    local expectedCrafts = tonumber(st.expectedCrafts)
    local materialCost = tonumber(st.materialCostPerCraftCopper)
    local verifiedVendorProceeds = tonumber(st.verifiedVendorProceedsPerCraftCopper)
    if not expectedCrafts or expectedCrafts <= 0 or not materialCost or materialCost < 0 or not verifiedVendorProceeds or verifiedVendorProceeds < 0 then
      return {
        status = "INCOMPLETE_STEP_INPUTS",
        failedStepIndex = idx,
        reason = "Each step requires positive expectedCrafts N_r, materialCostPerCraftCopper, and verifiedVendorProceedsPerCraftCopper.",
      }
    end
    local cashOutlayPerCraft = tonumber(st.cashOutlayPerCraftCopper) or materialCost
    local ownedOppPerCraft = tonumber(st.ownedMaterialOpportunityCostPerCraftCopper) or math.max(0, materialCost - cashOutlayPerCraft)
    local netPerCraft = materialCost - verifiedVendorProceeds
    local stepTotal = math.floor((expectedCrafts * netPerCraft) + 0.5)
    local stepCashOutlay = math.floor((expectedCrafts * cashOutlayPerCraft) + 0.5)
    local stepProceeds = math.floor((expectedCrafts * verifiedVendorProceeds) + 0.5)
    local stepOwnedOpp = math.floor((expectedCrafts * ownedOppPerCraft) + 0.5)

    totalStepCostCopper = totalStepCostCopper + stepTotal
    totalCashOutlayCopper = totalCashOutlayCopper + stepCashOutlay
    totalVendorProceedsCopper = totalVendorProceedsCopper + stepProceeds
    totalOwnedOpportunityCostCopper = totalOwnedOpportunityCostCopper + stepOwnedOpp

    table.insert(stepBreakdowns, {
      stepIndex = idx,
      recipeName = st.recipeName or ("Step " .. tostring(idx)),
      expectedCrafts = expectedCrafts,
      materialCostPerCraftCopper = materialCost,
      cashOutlayPerCraftCopper = cashOutlayPerCraft,
      ownedMaterialOpportunityCostPerCraftCopper = ownedOppPerCraft,
      verifiedVendorProceedsPerCraftCopper = verifiedVendorProceeds,
      netCostPerCraftCopper = netPerCraft,
      stepTotalNetCopper = stepTotal,
      stepCashOutlayCopper = stepCashOutlay,
      stepVendorProceedsCopper = stepProceeds,
      stepOwnedOpportunityCostCopper = stepOwnedOpp,
    })
  end

  local totalUnlockCostCopper = totalStepCostCopper + math.floor(trainingCopper) + math.floor(patternsCopper) + math.floor(travelCopper)

  -- Evaluate Mooncloth payback inequality if Mooncloth & Felcloth prices are supplied:
  local moonclothNetProceeds = tonumber(opts.netMoonclothProceedsCopper)
  local felclothUnitPrice = tonumber(opts.felclothUnitPriceCopper)
  local opsPerCast = math.max(0, math.floor(tonumber(opts.operatingCostPerCastCopper) or 0))
  local eligiblePreRaidCasts = math.max(0, math.floor(tonumber(opts.eligiblePreRaidCasts) or 6))

  local paybackStatus = "MOONCLOTH_PRICE_UNSUPPLIED"
  local paybackSatisfied = nil
  local cumulativePreRaidNetCopper = nil
  if moonclothNetProceeds and felclothUnitPrice and moonclothNetProceeds > 0 and felclothUnitPrice > 0 then
    local perCastNet = moonclothNetProceeds - (2 * felclothUnitPrice) - opsPerCast
    cumulativePreRaidNetCopper = eligiblePreRaidCasts * perCastNet
    paybackSatisfied = (totalUnlockCostCopper <= cumulativePreRaidNetCopper)
    paybackStatus = paybackSatisfied and "PAYBACK_SATISFIED_IN_WINDOW" or "PAYBACK_EXCEEDS_PRE_RAID_WINDOW"
  end

  return {
    status = "OK",
    totalLevelingAndUnlockCostCopper = totalUnlockCostCopper,
    stepNetCostCopper = totalStepCostCopper,
    cashOutlayCopper = totalCashOutlayCopper + math.floor(trainingCopper) + math.floor(patternsCopper) + math.floor(travelCopper),
    vendorProceedsCopper = totalVendorProceedsCopper,
    ownedMaterialOpportunityCostCopper = totalOwnedOpportunityCostCopper,
    remainingInventory = openingTranche.remainingInventoryAfterOpening10,
    openingTranche = openingTranche,
    foreverSkillProfile = ProfessionAdvisor.FOREVER_TAILORING_SKILL_PROFILE_175_250,
    trainingCostCopper = math.floor(trainingCopper),
    patternAcquisitionCostCopper = math.floor(patternsCopper),
    travelCostCopper = math.floor(travelCopper),
    steps = stepBreakdowns,
    eligiblePreRaidCasts = eligiblePreRaidCasts,
    preRaidCastsNote = "Count casts from the first eligible time after training, pattern access, Moonwell access, and any remaining cooldown before December 9, 2026 (1796832000 assumed 16:00 UTC cutoff).",
    cumulativePreRaidNetCopper = cumulativePreRaidNetCopper,
    paybackSatisfiedInPreRaidWindow = paybackSatisfied,
    paybackStatus = paybackStatus,
    moonclothPatternItemID = 14526,
    boltOfMageweaveSpellID = 3865,
    boltOfRuneclothSpellID = 18401,
    whiteBanditMaskPatternItemID = 10301,
  }
end

function ProfessionAdvisor.EvaluateSecondSlotDecisionRule(evidence)
  evidence = type(evidence) == "table" and evidence or {}

  -- Pre-commitment checklist (Astra 1-Page Decision Record):
  local checklist = {
    character_level_and_tailoring_rank_recorded = (tonumber(evidence.characterLevel) ~= nil and tonumber(evidence.tailoringRank) ~= nil),
    liquid_gold_and_mount_target_recorded = (tonumber(evidence.liquidCopper) ~= nil and tonumber(evidence.mountTargetCopper) ~= nil),
    leveling_route_mix_beast_vs_humanoid_recorded = (type(evidence.routeMix) == "string" and evidence.routeMix ~= ""),
    herb_and_potion_ah_scan_completed = (evidence.herbAndPotionScanCompleted == true),
    enchanting_mat_vs_vendor_de_sample_completed = (evidence.deVsVendorSampleCompleted == true),
    bank_alt_disenchant_feasibility_checked = (evidence.bankAltChecked == true),
  }

  local skinningCatchUpHours = tonumber(evidence.skinningCatchUpHours)
  local beastRouteShare = tonumber(evidence.beastRouteShare) or 0
  local skinningExpectedNetCopper = tonumber(evidence.skinningExpectedNet48To60Copper)
  local skinningSwitchCostCopper = tonumber(evidence.skinningSwitchAndCatchUpCostCopper)

  local deBeatsVendorOnSample = (evidence.deBeatsVendorOnSample == true)
  local enchantingLiquidationVerified = (evidence.enchantingLiquidationVerified == true)
  local canUseLevel5DisenchantAlt = (evidence.canUseLevel5DisenchantAlt == true)
  local mainNeedsBoPDisenchantOrRaidEnchants = (evidence.mainNeedsBoPDisenchantOrRaidEnchants == true)

  local alchemyMarginsPositiveNetOfFees = (evidence.alchemyMarginsPositiveNetOfFees == true)
  local alchemySaleThroughVerified = (evidence.alchemySaleThroughVerified == true)
  local alchemyUnlockBreakEvenAcceptable = (evidence.alchemyUnlockBreakEvenAcceptable == true)

  local decisionCode
  local headline
  local rationale

  if skinningCatchUpHours ~= nil
    and skinningCatchUpHours <= 2.5
    and beastRouteShare >= 0.40
    and skinningExpectedNetCopper ~= nil
    and skinningSwitchCostCopper ~= nil
    and skinningExpectedNetCopper > skinningSwitchCostCopper
  then
    decisionCode = "SKINNING_TEMPORARY"
    headline = "Take Skinning temporarily (48-60) only under verified beast-route & catch-up bounds"
    rationale = string.format(
      "Beast route share (%.0f%%) and low 1-240 catch-up time (%.1fh) yield positive net receipts (%dc > %dc catch-up/switch cost).",
      beastRouteShare * 100,
      skinningCatchUpHours,
      skinningExpectedNetCopper,
      skinningSwitchCostCopper
    )
  elseif deBeatsVendorOnSample
    and enchantingLiquidationVerified
    and (mainNeedsBoPDisenchantOrRaidEnchants or not canUseLevel5DisenchantAlt)
  then
    decisionCode = "ENCHANTING_NOW"
    headline = "Take Enchanting now (verified DE > vendor spread & main-character BoP/enchant utility)"
    rationale = "Base (1.00x) DE EV beats vendor cash with verified AH sale-through, and main-character BoP disenchanting is required."
  elseif alchemyMarginsPositiveNetOfFees
    and alchemySaleThroughVerified
    and alchemyUnlockBreakEvenAcceptable
  then
    decisionCode = "ALCHEMY_NOW"
    headline = "Take Alchemy now (verified AH-herb conversion margin & shared transmute slot)"
    rationale = "Forever potion/elixir margins are positive net of AH fees/relists with verified cohort sale-through and acceptable recipe unlock break-even."
  else
    decisionCode = "PRESERVE_SLOT_COLLECT_EVIDENCE"
    headline = "Preserve open second slot (or use a Lv 5 bank alt for BoE DE) while collecting live AH/route evidence"
    rationale = "No candidate profession has yet cleared its verified catch-up, sale-through, or DE-vs-vendor threshold; avoid irreversible sunk training costs."
  end

  return {
    decisionCode = decisionCode,
    headline = headline,
    rationale = rationale,
    unconditionalDefaultRejected = true,
    preCommitmentChecklist = checklist,
  }
end

return ProfessionAdvisor
