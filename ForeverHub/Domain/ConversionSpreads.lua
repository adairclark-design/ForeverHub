local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.Domain = ns.Domain or {}

local ConversionSpreads = {}
ns.Domain.ConversionSpreads = ConversionSpreads

ConversionSpreads.MIN_VERIFIED_SALE_SAMPLE_COUNT = 5
ConversionSpreads.DEFAULT_MAX_SALE_EVIDENCE_AGE_SECONDS = 7 * 86400

ConversionSpreads.CURATED_RECIPES = {
  {
    recipeID = "conv_bolt_of_silk_cloth",
    displayName = "Bolt of Silk Cloth",
    professionKey = "TAILORING",
    minSkill = 125,
    outputItemID = 4305,
    outputQuantity = 1,
    outputVendorUnitCopper = 600,
    outputMaxStack = 20,
    castSeconds = 3,
    quantityVerified = true,
    supportsAuctionableVellums = false,
    inputs = {
      { itemID = 4306, quantityPerCraft = 4, sourceKind = "ah_ladder" },
    },
  },
  {
    recipeID = "conv_bolt_of_mageweave",
    displayName = "Bolt of Mageweave",
    professionKey = "TAILORING",
    minSkill = 205,
    outputItemID = 4339,
    outputQuantity = 1,
    outputVendorUnitCopper = 1000,
    outputMaxStack = 20,
    castSeconds = 3,
    quantityVerified = true,
    supportsAuctionableVellums = false,
    inputs = {
      { itemID = 4338, quantityPerCraft = 5, sourceKind = "ah_ladder" },
    },
  },
  {
    recipeID = "conv_bolt_of_runecloth",
    displayName = "Bolt of Runecloth",
    professionKey = "TAILORING",
    minSkill = 250,
    outputItemID = 14048,
    outputQuantity = 1,
    outputVendorUnitCopper = 2000,
    outputMaxStack = 20,
    castSeconds = 3,
    quantityVerified = true,
    supportsAuctionableVellums = false,
    inputs = {
      { itemID = 14047, quantityPerCraft = 5, sourceKind = "ah_ladder" },
    },
  },
  {
    recipeID = "conv_dense_grinding_stone",
    displayName = "Dense Grinding Stone",
    professionKey = "BLACKSMITHING",
    minSkill = 250,
    outputItemID = 12644,
    outputQuantity = 1,
    outputVendorUnitCopper = 1000,
    outputMaxStack = 20,
    castSeconds = 4,
    quantityVerified = true,
    supportsAuctionableVellums = false,
    inputs = {
      { itemID = 12365, quantityPerCraft = 4, sourceKind = "ah_ladder" },
    },
  },
  {
    recipeID = "conv_blackmouth_oil",
    displayName = "Blackmouth Oil",
    professionKey = "ALCHEMY",
    minSkill = 80,
    outputItemID = 6370,
    outputQuantity = 1,
    outputVendorUnitCopper = 25,
    outputMaxStack = 20,
    castSeconds = 3,
    quantityVerified = true,
    supportsAuctionableVellums = false,
    inputs = {
      { itemID = 6358, quantityPerCraft = 2, sourceKind = "ah_ladder" },
      { itemID = 3371, quantityPerCraft = 1, sourceKind = "verified_merchant_bundle", merchantBundleCopper = 20, merchantBundleSize = 5 },
    },
  },
  {
    recipeID = "conv_free_action_potion",
    displayName = "Free Action Potion",
    professionKey = "ALCHEMY",
    minSkill = 150,
    outputItemID = 5634,
    outputQuantity = 1,
    outputVendorUnitCopper = 150,
    outputMaxStack = 5,
    castSeconds = 3,
    quantityVerified = true,
    supportsAuctionableVellums = false,
    inputs = {
      { itemID = 6370, quantityPerCraft = 2, sourceKind = "ah_ladder" },
      { itemID = 3820, quantityPerCraft = 1, sourceKind = "ah_ladder" },
      { itemID = 3372, quantityPerCraft = 1, sourceKind = "verified_merchant_bundle", merchantBundleCopper = 100, merchantBundleSize = 5 },
    },
  },
  {
    recipeID = "conv_gnpp",
    displayName = "Greater Nature Protection Potion",
    professionKey = "ALCHEMY",
    minSkill = 190,
    outputItemID = 13458,
    outputQuantity = 1,
    outputVendorUnitCopper = 250,
    outputMaxStack = 5,
    castSeconds = 3,
    quantityVerified = true,
    supportsAuctionableVellums = false,
    inputs = {
      { itemID = 7067, quantityPerCraft = 1, sourceKind = "ah_ladder" },
      { itemID = 13463, quantityPerCraft = 1, sourceKind = "ah_ladder" },
      { itemID = 8925, quantityPerCraft = 1, sourceKind = "verified_merchant_bundle", merchantBundleCopper = 2500, merchantBundleSize = 5 },
    },
  },
  {
    recipeID = "conv_greater_magic_wand",
    displayName = "Greater Magic Wand",
    professionKey = "ENCHANTING",
    minSkill = 70,
    outputItemID = 11288,
    outputQuantity = 1,
    outputVendorUnitCopper = 1,
    outputMaxStack = 1,
    castSeconds = 5,
    quantityVerified = true,
    supportsAuctionableVellums = false,
    inputs = {
      { itemID = 10939, quantityPerCraft = 1, sourceKind = "ah_ladder" },
      { itemID = 4470, quantityPerCraft = 1, sourceKind = "verified_merchant_bundle", merchantBundleCopper = 38, merchantBundleSize = 1 },
    },
  },
}

-- WoW: Forever Custom & Modified Alchemy/Mining Conversion & Raid Consumable Recipes
-- Reconciled against `knowledge/wow_forever/compiled_sources/prof_alchemy.json` and client build 1.60.1.70862 (`ForeverRecipes.lua`) (Astra P0/P1):
ConversionSpreads.FOREVER_RECIPES = {
  {
    recipeID = "forever_major_spellblasting_potion",
    spellID = 1251734,
    displayName = "Major Spellblasting Potion",
    professionKey = "ALCHEMY",
    minSkill = 285,
    outputItemID = 250937,
    outputQuantity = 1,
    outputVendorUnitCopper = 250,
    outputMaxStack = 5,
    castSeconds = 3,
    quantityVerified = true,
    isForeverCustomRecipe = true,
    verifiedClientBuild = "1.60.1.70862",
    effectSummary = "+47 spell damage for 30 sec",
    consumableCategory = "30s_raid_throughput_potion",
    acquisitionSource = "Vendor (180 Merchant's Favor)",
    corpusClaimID = "prof_alchemy_recipe_10_major_spellblasting_poti",
    supportsAuctionableVellums = false,
    inputs = {
      { itemID = 13463, name = "Dreamfoil", quantityPerCraft = 2, sourceKind = "ah_ladder" },
      { itemID = 13465, name = "Mountain Silversage", quantityPerCraft = 1, sourceKind = "ah_ladder" },
      { itemID = 18256, name = "Imbued Vial", quantityPerCraft = 1, sourceKind = "verified_merchant_bundle", merchantBundleCopper = 15000, merchantBundleSize = 5 },
    },
  },
  {
    recipeID = "forever_major_frenzy_potion",
    spellID = 1251740,
    displayName = "Major Frenzy Potion",
    professionKey = "ALCHEMY",
    minSkill = 290,
    outputItemID = 250943,
    outputQuantity = 1,
    outputVendorUnitCopper = 250,
    outputMaxStack = 5,
    castSeconds = 3,
    quantityVerified = true,
    isForeverCustomRecipe = true,
    verifiedClientBuild = "1.60.1.70862",
    effectSummary = "+80 attack power for 30 sec",
    consumableCategory = "30s_raid_throughput_potion",
    acquisitionSource = "Vendor (240 Merchant's Favor)",
    corpusClaimID = "prof_alchemy_recipe_7_major_frenzy_potion",
    supportsAuctionableVellums = false,
    inputs = {
      { itemID = 13466, name = "Plaguebloom", quantityPerCraft = 3, sourceKind = "ah_ladder" },
      { itemID = 8839, name = "Blindweed", quantityPerCraft = 2, sourceKind = "ah_ladder" },
      { itemID = 18256, name = "Imbued Vial", quantityPerCraft = 1, sourceKind = "verified_merchant_bundle", merchantBundleCopper = 15000, merchantBundleSize = 5 },
    },
  },
  {
    recipeID = "forever_major_menders_potion",
    spellID = 1251747,
    displayName = "Major Mender's Potion",
    professionKey = "ALCHEMY",
    minSkill = 280,
    outputItemID = 250949,
    outputQuantity = 1,
    clientExtractOutputQuantity = 1,
    publishedWebSpellOutputQuantity = 2,
    outputYieldConflict = true,
    outputYieldVerificationNote = "Local extract returns 1 item per cast while published craft spell page shows 2; verify actual output in profession window before pricing conversion.",
    outputVendorUnitCopper = 250,
    outputMaxStack = 5,
    castSeconds = 3,
    quantityVerified = true,
    isForeverCustomRecipe = true,
    verifiedClientBuild = "1.60.1.70862",
    effectSummary = "+88 spell healing for 30 sec",
    consumableCategory = "30s_raid_throughput_potion",
    acquisitionSource = "Vendor (180 Merchant's Favor)",
    corpusClaimID = "prof_alchemy_recipe_12_major_mender_s_potion",
    supportsAuctionableVellums = false,
    inputs = {
      { itemID = 13463, name = "Dreamfoil", quantityPerCraft = 3, sourceKind = "ah_ladder" },
      { itemID = 8838, name = "Sungrass", quantityPerCraft = 1, sourceKind = "ah_ladder" },
      { itemID = 18256, name = "Imbued Vial", quantityPerCraft = 1, sourceKind = "verified_merchant_bundle", merchantBundleCopper = 15000, merchantBundleSize = 5 },
    },
  },
  {
    recipeID = "forever_elixir_of_the_owl",
    spellID = 1250786,
    displayName = "Elixir of the Owl",
    professionKey = "ALCHEMY",
    minSkill = 280,
    outputItemID = 250337,
    outputQuantity = 1,
    outputVendorUnitCopper = 250,
    outputMaxStack = 5,
    castSeconds = 3,
    quantityVerified = true,
    isForeverCustomRecipe = true,
    verifiedClientBuild = "1.60.1.70862",
    effectSummary = "+25 Intellect and +2% spell crit for 30 min",
    consumableCategory = "raid_elixir",
    acquisitionSource = "Vendor (180 Merchant's Favor)",
    corpusClaimID = "prof_alchemy_recipe_11_elixir_of_the_owl",
    supportsAuctionableVellums = false,
    inputs = {
      { itemID = 13463, name = "Dreamfoil", quantityPerCraft = 4, sourceKind = "ah_ladder" },
      { itemID = 13465, name = "Mountain Silversage", quantityPerCraft = 2, sourceKind = "ah_ladder" },
      { itemID = 18256, name = "Imbued Vial", quantityPerCraft = 1, sourceKind = "verified_merchant_bundle", merchantBundleCopper = 15000, merchantBundleSize = 5 },
    },
  },
  {
    recipeID = "forever_elixir_of_the_grizzly",
    spellID = 1250800,
    displayName = "Elixir of the Grizzly",
    professionKey = "ALCHEMY",
    minSkill = 300,
    outputItemID = 250351,
    outputQuantity = 1,
    clientExtractOutputQuantity = 1,
    publishedWebSpellOutputQuantity = 2,
    outputYieldConflict = true,
    outputYieldVerificationNote = "Local extract returns 1 item per cast while published craft spell page shows 2; verify actual output in profession window before pricing conversion.",
    outputVendorUnitCopper = 250,
    outputMaxStack = 5,
    castSeconds = 3,
    quantityVerified = true,
    isForeverCustomRecipe = true,
    verifiedClientBuild = "1.60.1.70862",
    effectSummary = "+25 Strength and +2% crit for 30 min",
    consumableCategory = "raid_elixir",
    acquisitionSource = "Vendor (240 Merchant's Favor)",
    corpusClaimID = "prof_alchemy_recipe_1_elixir_of_the_grizzly",
    supportsAuctionableVellums = false,
    inputs = {
      { itemID = 8846, name = "Gromsblood", quantityPerCraft = 3, sourceKind = "ah_ladder" },
      { itemID = 8839, name = "Blindweed", quantityPerCraft = 1, sourceKind = "ah_ladder" },
      { itemID = 8925, name = "Crystal Vial", quantityPerCraft = 1, sourceKind = "verified_merchant_bundle", merchantBundleCopper = 2500, merchantBundleSize = 5 },
    },
  },
  {
    recipeID = "forever_elixir_of_sages",
    spellID = 1250787,
    displayName = "Elixir of Sages",
    professionKey = "ALCHEMY",
    minSkill = 275,
    outputItemID = 250338,
    outputQuantity = 1,
    outputVendorUnitCopper = 150,
    outputMaxStack = 5,
    castSeconds = 3,
    quantityVerified = true,
    isForeverCustomRecipe = true,
    verifiedClientBuild = "1.60.1.70862",
    effectSummary = "+25 Spirit and +2% crit for 30 min",
    consumableCategory = "raid_elixir",
    acquisitionSource = "Vendor (180 Merchant's Favor)",
    corpusClaimID = "prof_alchemy_recipe_16_elixir_of_sages",
    supportsAuctionableVellums = false,
    inputs = {
      { itemID = 13463, name = "Dreamfoil", quantityPerCraft = 4, sourceKind = "ah_ladder" },
      { itemID = 13464, name = "Golden Sansam", quantityPerCraft = 2, sourceKind = "ah_ladder" },
      { itemID = 18256, name = "Imbued Vial", quantityPerCraft = 1, sourceKind = "verified_merchant_bundle", merchantBundleCopper = 15000, merchantBundleSize = 5 },
    },
  },
  {
    recipeID = "forever_ghost_dye",
    spellID = 11473,
    displayName = "Ghost Dye",
    professionKey = "ALCHEMY",
    minSkill = 245,
    outputItemID = 9210,
    outputQuantity = 1,
    outputVendorUnitCopper = 150,
    outputMaxStack = 20,
    castSeconds = 3,
    quantityVerified = true,
    isForeverCustomRecipe = false,
    consumableCategory = "tailoring_reagent",
    supportsAuctionableVellums = false,
    inputs = {
      { itemID = 8845, name = "Ghost Mushroom", quantityPerCraft = 2, sourceKind = "ah_ladder" },
      { itemID = 4342, name = "Purple Dye", quantityPerCraft = 1, sourceKind = "verified_merchant_bundle", merchantBundleCopper = 2500, merchantBundleSize = 1 },
      { itemID = 8925, name = "Crystal Vial", quantityPerCraft = 1, sourceKind = "verified_merchant_bundle", merchantBundleCopper = 2500, merchantBundleSize = 5 },
    },
  },
  {
    recipeID = "forever_smelt_azerothium",
    spellID = 1249637,
    displayName = "Smelt Azerothium",
    professionKey = "MINING",
    minSkill = 275,
    outputItemID = 249726,
    outputQuantity = 1,
    outputVendorUnitCopper = 0,
    outputMaxStack = 20,
    castSeconds = 3,
    quantityVerified = true,
    isForeverCustomRecipe = true,
    verifiedClientBuild = "1.60.1.70862",
    consumableCategory = "scarce_tier3_smelt",
    acquisitionSource = "Mining Trainer (275)",
    supportsAuctionableVellums = false,
    inputs = {
      { itemID = 249426, name = "Pitchblende", quantityPerCraft = 2, sourceKind = "ah_ladder" },
      { itemID = 3857, name = "Coal", quantityPerCraft = 1, sourceKind = "ah_ladder" },
    },
  },
}

ConversionSpreads.SHARED_TRANSMUTE_RECIPES = {
  {
    recipeID = "transmute_arcanite",
    spellID = 17187,
    displayName = "Transmute: Arcanite",
    professionKey = "ALCHEMY",
    minSkill = 275,
    sharedCooldownGroup = "alchemy_shared_transmute",
    staticCooldownHours = 47,
    formulaResolved = true,
    outputItemID = 12360,
    outputQuantity = 1,
    outputVendorUnitCopper = 5000,
    inputs = {
      { itemID = 12363, name = "Arcane Crystal", quantityPerCraft = 1 },
      { itemID = 12359, name = "Thorium Bar", quantityPerCraft = 1 },
    },
  },
  {
    recipeID = "transmute_legionite",
    spellID = 1317279,
    displayName = "Transmute: Legionite",
    professionKey = "ALCHEMY",
    minSkill = 275,
    sharedCooldownGroup = "alchemy_shared_transmute",
    staticCooldownHours = 47,
    isForeverCustomRecipe = true,
    formulaResolved = true,
    verifiedClientBuild = "1.60.1.70862",
    acquisitionSource = "Recipe: Transmute Legionite — Source not known yet",
    corpusClaimID = "prof_alchemy_recipe_20_legionite_bar_transmute_",
    corpusFormulaText = "1x Heavy Thorium Bar + 1x Fel Crystal",
    outputItemID = 251290,
    outputQuantity = 1,
    outputVendorUnitCopper = 5000,
    inputs = {
      { itemID = 251291, name = "Heavy Thorium Bar", quantityPerCraft = 1 },
      { itemID = 248819, name = "Fel Crystal", quantityPerCraft = 1 },
    },
  },
  {
    recipeID = "transmute_fire_to_earth",
    spellID = 17560,
    displayName = "Transmute: Fire to Earth",
    professionKey = "ALCHEMY",
    minSkill = 275,
    sharedCooldownGroup = "alchemy_shared_transmute",
    staticCooldownHours = 24,
    formulaResolved = true,
    outputItemID = 7076,
    outputQuantity = 1,
    outputVendorUnitCopper = 400,
    inputs = {
      { itemID = 7078, name = "Essence of Fire", quantityPerCraft = 1 },
    },
  },
  {
    recipeID = "transmute_earth_to_water",
    spellID = 17561,
    displayName = "Transmute: Earth to Water",
    professionKey = "ALCHEMY",
    minSkill = 275,
    sharedCooldownGroup = "alchemy_shared_transmute",
    staticCooldownHours = 24,
    formulaResolved = true,
    outputItemID = 7080,
    outputQuantity = 1,
    outputVendorUnitCopper = 400,
    inputs = {
      { itemID = 7076, name = "Essence of Earth", quantityPerCraft = 1 },
    },
  },
  {
    recipeID = "transmute_undeath_to_water",
    spellID = 17563,
    displayName = "Transmute: Undeath to Water",
    professionKey = "ALCHEMY",
    minSkill = 275,
    sharedCooldownGroup = "alchemy_shared_transmute",
    staticCooldownHours = 24,
    formulaResolved = true,
    outputItemID = 7080,
    outputQuantity = 1,
    outputVendorUnitCopper = 400,
    inputs = {
      { itemID = 12808, name = "Essence of Undeath", quantityPerCraft = 1 },
    },
  },
}

ConversionSpreads.RECIPES_BY_ID = {}
for _, r in ipairs(ConversionSpreads.CURATED_RECIPES) do
  ConversionSpreads.RECIPES_BY_ID[r.recipeID] = r
end
ConversionSpreads.FOREVER_RECIPES_BY_ID = {}
for _, r in ipairs(ConversionSpreads.FOREVER_RECIPES) do
  ConversionSpreads.FOREVER_RECIPES_BY_ID[r.recipeID] = r
end

local function isBlockedWritItem(itemID, explicitBlockedSet)
  if type(explicitBlockedSet) == "table" and explicitBlockedSet[itemID] == true then
    return true
  end
  if ns.Domain and ns.Domain.VendorArbitrage and type(ns.Domain.VendorArbitrage.IsBlockedUnverifiedWrit) == "function" then
    return ns.Domain.VendorArbitrage.IsBlockedUnverifiedWrit(itemID) == true
  end
  return false
end

function ConversionSpreads.ResolveTurnaroundHorizon(saleThroughEvidence, opts)
  opts = type(opts) == "table" and opts or {}
  local nowEpoch = tonumber(opts.nowEpoch) or 0
  local minSamples = tonumber(opts.minSaleSampleCount) or ConversionSpreads.MIN_VERIFIED_SALE_SAMPLE_COUNT
  local maxAge = tonumber(opts.maxEvidenceAgeSeconds) or ConversionSpreads.DEFAULT_MAX_SALE_EVIDENCE_AGE_SECONDS

  if type(saleThroughEvidence) ~= "table" then
    return {
      saleThroughVerified = false,
      liquidationTime = "UNKNOWN",
      censoringStatus = "UNMEASURED",
      turnaroundLabel = "Liquidation time: UNKNOWN (unmeasured sale-through)",
      medianHoursToSell = nil,
      observedSaleCount = 0,
      reason = "missing_sale_through_evidence",
    }
  end

  local verified = saleThroughEvidence.saleThroughVerified == true
  local count = tonumber(saleThroughEvidence.observedSaleCount) or 0
  local medianHrs = tonumber(saleThroughEvidence.medianHoursToSell)
  local obsAt = tonumber(saleThroughEvidence.observedAtEpoch)

  if not verified
    or math.floor(count) ~= count
    or count < minSamples
    or not medianHrs
    or medianHrs ~= medianHrs
    or medianHrs == math.huge
    or medianHrs <= 0
    or not obsAt
    or obsAt <= 0
    or (nowEpoch > 0 and (nowEpoch - obsAt) > maxAge)
    or (nowEpoch > 0 and obsAt > (nowEpoch + 300))
  then
    return {
      saleThroughVerified = false,
      liquidationTime = "UNKNOWN",
      censoringStatus = "UNMEASURED",
      turnaroundLabel = "Liquidation time: UNKNOWN (unmeasured sale-through)",
      medianHoursToSell = nil,
      observedSaleCount = math.max(0, math.floor(count)),
      reason = "insufficient_or_stale_sale_through_sample",
    }
  end

  local med = math.floor(medianHrs * 100 + 0.5) / 100
  local soldN = math.floor(count)

  -- Astra Round-4 P0.7 & Profession Audit P0.2:
  -- 1. Recorded sales alone omit unsold/cancelled listings (right-censoring).
  -- 2. Cohort median order-statistic identifiability requires strictly >50% of the cohort to sell
  --    (`soldN >= math.floor(totalCohort / 2) + 1`).
  -- 3. When per-listing sale times (`saleTimesHours` or `cohortListings`) are supplied, verify that
  --    at least 50% of the ENTIRE cohort sold at or before `medianHoursToSell` (rejecting sold-only
  --    medians such as 5 sales at 1, 2, 3, 4, 100h + 5 unsold claiming a 3h median).
  local cohortComplete = (saleThroughEvidence.cohortComplete == true)
  local unsoldCount = tonumber(saleThroughEvidence.unsoldOrCancelledCount)
  local totalCohort = tonumber(saleThroughEvidence.totalCohortListings)

  local parsedSaleTimes = nil
  if type(saleThroughEvidence.cohortListings) == "table" and #saleThroughEvidence.cohortListings > 0 then
    parsedSaleTimes = {}
    local listingSoldCount = 0
    local listingUnsoldCount = 0
    for _, row in ipairs(saleThroughEvidence.cohortListings) do
      if type(row) == "table" and row.relistedFromId == nil then
        local listedAt = tonumber(row.listedAtEpoch)
        local soldAt = tonumber(row.soldAtEpoch)
        if listedAt and soldAt and soldAt > listedAt and row.cancelled ~= true then
          listingSoldCount = listingSoldCount + 1
          table.insert(parsedSaleTimes, (soldAt - listedAt) / 3600.0)
        else
          listingUnsoldCount = listingUnsoldCount + 1
        end
      end
    end
    soldN = listingSoldCount
    unsoldCount = listingUnsoldCount
    totalCohort = listingSoldCount + listingUnsoldCount
    cohortComplete = true
  elseif type(saleThroughEvidence.saleTimesHours) == "table" then
    parsedSaleTimes = {}
    for _, t in ipairs(saleThroughEvidence.saleTimesHours) do
      local numT = tonumber(t)
      if numT and numT > 0 then
        table.insert(parsedSaleTimes, numT)
      end
    end
  end

  local minRequiredCohortSales = (totalCohort and totalCohort >= 1) and (math.floor(totalCohort / 2) + 1) or 0
  local validCohort = cohortComplete
    and unsoldCount ~= nil
    and unsoldCount >= 0
    and math.floor(unsoldCount) == unsoldCount
    and totalCohort ~= nil
    and math.floor(totalCohort) == totalCohort
    and totalCohort == (soldN + unsoldCount)
    and totalCohort >= minSamples
    and soldN >= minRequiredCohortSales

  if not validCohort then
    return {
      saleThroughVerified = false,
      liquidationTime = "UNKNOWN",
      censoringStatus = "RECORDED_SALES_ONLY_CENSORED",
      turnaroundLabel = "Observed time among recorded sales; unsold inventory excluded.",
      medianHoursToSell = med,
      observedSaleCount = soldN,
      fractionSoldByHorizon = (totalCohort and totalCohort > 0) and (math.floor((soldN / totalCohort) * 10000 + 0.5) / 10000) or nil,
      reason = "unsold_inventory_excluded_censored_sample",
    }
  end

  local soldByHorizonCount = soldN
  if type(parsedSaleTimes) == "table" then
    if #parsedSaleTimes ~= soldN then
      return {
        saleThroughVerified = false,
        liquidationTime = "UNKNOWN",
        censoringStatus = "SOLD_ONLY_MEDIAN_MISLEADING",
        turnaroundLabel = "Cohort sale-time list does not match observed sale count.",
        medianHoursToSell = med,
        observedSaleCount = soldN,
        unsoldOrCancelledCount = unsoldCount,
        totalCohortListings = totalCohort,
        fractionSoldByHorizon = nil,
        reason = "sale_times_count_mismatch",
      }
    end
    soldByHorizonCount = 0
    for _, t in ipairs(parsedSaleTimes) do
      if t <= (medianHrs + 1e-9) then
        soldByHorizonCount = soldByHorizonCount + 1
      end
    end
    if (soldByHorizonCount * 2) < totalCohort then
      return {
        saleThroughVerified = false,
        liquidationTime = "UNKNOWN",
        censoringStatus = "SOLD_ONLY_MEDIAN_MISLEADING",
        turnaroundLabel = "Sold-only median rejected: fewer than 50% of the cohort sold by claimed horizon.",
        medianHoursToSell = med,
        observedSaleCount = soldN,
        unsoldOrCancelledCount = unsoldCount,
        totalCohortListings = totalCohort,
        fractionSoldByHorizon = math.floor((soldByHorizonCount / totalCohort) * 10000 + 0.5) / 10000,
        reason = "fewer_than_half_of_cohort_sold_by_claimed_median",
      }
    end
  end

  local fractionSoldByHorizon = math.floor((soldByHorizonCount / totalCohort) * 10000 + 0.5) / 10000
  local bucket
  local label
  if medianHrs <= 24.0 then
    bucket = "<24h_cohort_observed"
    label = string.format(
      "Cohort median sale-through: %.1fh (%d/%d sold, %d unsold/cancelled, not guaranteed)",
      medianHrs,
      soldN,
      totalCohort,
      unsoldCount
    )
  elseif medianHrs <= 48.0 then
    bucket = "24_48h_cohort_observed"
    label = string.format(
      "Cohort median sale-through: %.1fh (%d/%d sold, %d unsold/cancelled, not guaranteed)",
      medianHrs,
      soldN,
      totalCohort,
      unsoldCount
    )
  else
    bucket = ">48h_cohort_observed"
    label = string.format(
      "Cohort median sale-through: %.1fh (%d/%d sold, %d unsold/cancelled, slow turnover)",
      medianHrs,
      soldN,
      totalCohort,
      unsoldCount
    )
  end

  return {
    saleThroughVerified = true,
    liquidationTime = bucket,
    censoringStatus = "COHORT_COMPLETE",
    turnaroundLabel = label,
    medianHoursToSell = med,
    observedSaleCount = soldN,
    unsoldOrCancelledCount = unsoldCount,
    totalCohortListings = totalCohort,
    fractionSoldByHorizon = fractionSoldByHorizon,
    reason = nil,
  }
end

local function quoteFeeRuleDeposit(feeRule, vendorUnitCopper, stackSize, numStacks, durationHours, currentBuild)
  local MA = ns.Domain and ns.Domain.MarketAccounting
  if not MA or type(feeRule) ~= "table" then
    return nil, "missing_fee_rule"
  end
  if feeRule.verificationStatus ~= "VERIFIED" then
    return nil, "unverified_fee_rule"
  end
  if type(currentBuild) == "string" and currentBuild ~= "" and feeRule.observedBuild ~= currentBuild then
    return nil, "stale_build_fee_rule"
  end
  local schedule = feeRule.durationSchedule
  local rateBps = type(schedule) == "table" and (tonumber(schedule[durationHours]) or tonumber(schedule[tostring(durationHours)])) or nil
  local minDep = tonumber(feeRule.minDepositCopper)
  local rMode = feeRule.roundingMode or "half_up"
  local sem = feeRule.stackSemantics or "per_stack_with_min_floor"
  if not rateBps or not minDep or minDep < 1 then
    return nil, "incomplete_fee_rule"
  end

  local stackVendor, errSV = MA.SafeMulNonNegativeCopper(vendorUnitCopper, stackSize)
  if not stackVendor then
    return nil, errSV
  end
  local perStack
  if sem == "per_stack_with_min_floor" then
    local raw, errR = MA.ScaleCopperByBps(stackVendor, rateBps, rMode)
    if not raw then
      return nil, errR
    end
    perStack = math.max(minDep, raw)
  elseif sem == "per_unit_floor_then_stack" then
    local perUnit, errU = MA.ScaleCopperByBps(vendorUnitCopper, rateBps, rMode)
    if not perUnit then
      return nil, errU
    end
    local mulU, errMU = MA.SafeMulNonNegativeCopper(perUnit, stackSize)
    if not mulU then
      return nil, errMU
    end
    perStack = math.max(minDep, mulU)
  else
    return nil, "unsupported_stack_semantics"
  end
  return MA.SafeMulNonNegativeCopper(perStack, numStacks)
end

function ConversionSpreads.EvaluateConversionSpread(recipe, opts)
  opts = type(opts) == "table" and opts or {}
  local MA = ns.Domain and ns.Domain.MarketAccounting
  if not MA or type(recipe) ~= "table" then
    return nil, "invalid_recipe_or_accounting"
  end

  local craftCount = tonumber(opts.craftCount) or 1
  local outputLotSize = tonumber(opts.outputLotSize) or 1
  local expectedRelists = tonumber(opts.expectedFailedRelists) or 0
  local durationHours = tonumber(opts.durationHours) or 24
  local currentBuild = tostring(opts.currentBuild or "1.60.1.70938")
  local nowEpoch = tonumber(opts.nowEpoch) or 1763120000

  if not MA.IsSafeIntegerCopper(craftCount) or craftCount <= 0 or craftCount > 500 then
    return nil, "invalid_craft_count"
  end
  if not MA.IsSafeIntegerCopper(outputLotSize) or outputLotSize <= 0 or outputLotSize > (tonumber(recipe.outputMaxStack) or 20) then
    return nil, "invalid_output_lot_size"
  end
  if not MA.CheckNonNegativeCopper(expectedRelists) or expectedRelists > 100 then
    return nil, "invalid_expected_failed_relists"
  end

  local writCheck = MA.EvaluateWritEconomicEligibility({
    quantityVerified = recipe.quantityVerified,
    quantity = recipe.outputQuantity,
  })
  if not writCheck or writCheck.eligible ~= true or isBlockedWritItem(recipe.outputItemID, opts.blockedWritByItemID) then
    return {
      recipeID = recipe.recipeID,
      displayName = recipe.displayName,
      rung = "RUNG_2_CONVERSION",
      status = "BLOCKED_UNVERIFIED_WRIT",
      quantityStatus = "UNKNOWN",
      liquidationTime = "UNKNOWN",
      saleThroughVerified = false,
      activeGphCopper = nil,
    }
  end

  for _, inp in ipairs(recipe.inputs or {}) do
    if isBlockedWritItem(inp.itemID, opts.blockedWritByItemID) then
      return {
        recipeID = recipe.recipeID,
        displayName = recipe.displayName,
        rung = "RUNG_2_CONVERSION",
        status = "BLOCKED_UNVERIFIED_WRIT",
        quantityStatus = "UNKNOWN",
        liquidationTime = "UNKNOWN",
        saleThroughVerified = false,
        activeGphCopper = nil,
      }
    end
  end

  local turnaround = ConversionSpreads.ResolveTurnaroundHorizon(opts.saleThroughEvidence, { nowEpoch = nowEpoch })
  local ladders = type(opts.laddersByItemID) == "table" and opts.laddersByItemID or {}
  local summaries = type(opts.summaryUnitPricesByItemID) == "table" and opts.summaryUnitPricesByItemID or {}

  local totalInputOutlayCopper = 0
  local leftoverInputs = {}
  local discoveryOnly = false

  for _, inp in ipairs(recipe.inputs or {}) do
    local reqQty = MA.SafeMulNonNegativeCopper(inp.quantityPerCraft, craftCount)
    if inp.sourceKind == "verified_merchant_bundle" then
      local bCopper = tonumber(inp.merchantBundleCopper)
      local bSize = tonumber(inp.merchantBundleSize)
      if not bCopper or not bSize or bSize < 1 then
        return {
          recipeID = recipe.recipeID,
          displayName = recipe.displayName,
          rung = "RUNG_2_CONVERSION",
          status = "UNVERIFIED_MERCHANT_BUNDLE",
          liquidationTime = turnaround.liquidationTime,
          saleThroughVerified = turnaround.saleThroughVerified,
          activeGphCopper = nil,
        }
      end
      local bundlesNeeded = math.floor((reqQty + bSize - 1) / bSize)
      local bCost = MA.SafeMulNonNegativeCopper(bundlesNeeded, bCopper)
      totalInputOutlayCopper = totalInputOutlayCopper + bCost
      local excess = (bundlesNeeded * bSize) - reqQty
      if excess > 0 then
        table.insert(leftoverInputs, { itemID = inp.itemID, excessUnits = excess })
      end
    else
      local rungList = ladders[inp.itemID]
      if type(rungList) == "table" and #rungList > 0 then
        local walk = MA.WalkAskLadderEntryCost(rungList, reqQty, false, nil)
        if not walk or walk.sufficientDepth ~= true or not walk.entryCostCopper then
          return {
            recipeID = recipe.recipeID,
            displayName = recipe.displayName,
            rung = "RUNG_2_CONVERSION",
            status = "INSUFFICIENT_INPUT_DEPTH",
            missingItemID = inp.itemID,
            liquidationTime = turnaround.liquidationTime,
            saleThroughVerified = turnaround.saleThroughVerified,
            activeGphCopper = nil,
          }
        end
        totalInputOutlayCopper = totalInputOutlayCopper + walk.entryCostCopper
        if (tonumber(walk.excessUnits) or 0) > 0 then
          table.insert(leftoverInputs, { itemID = inp.itemID, excessUnits = walk.excessUnits })
        end
      elseif MA.IsSafeIntegerCopper(summaries[inp.itemID]) and summaries[inp.itemID] > 0 then
        discoveryOnly = true
        totalInputOutlayCopper = totalInputOutlayCopper + MA.SafeMulNonNegativeCopper(summaries[inp.itemID], reqQty)
      else
        return {
          recipeID = recipe.recipeID,
          displayName = recipe.displayName,
          rung = "RUNG_2_CONVERSION",
          status = "MISSING_INPUT_OBSERVATION",
          missingItemID = inp.itemID,
          liquidationTime = turnaround.liquidationTime,
          saleThroughVerified = turnaround.saleThroughVerified,
          activeGphCopper = nil,
        }
      end
    end
  end

  local totalOutputUnits = MA.SafeMulNonNegativeCopper(recipe.outputQuantity, craftCount)
  if (totalOutputUnits % outputLotSize) ~= 0 then
    return {
      recipeID = recipe.recipeID,
      displayName = recipe.displayName,
      rung = "RUNG_2_CONVERSION",
      status = "LOT_SIZE_DOES_NOT_DIVIDE_OUTPUT",
      liquidationTime = turnaround.liquidationTime,
      saleThroughVerified = turnaround.saleThroughVerified,
      activeGphCopper = nil,
    }
  end

  local outUnitPrice = opts.outputLotUnitPriceCopper
  if not MA.IsSafeIntegerCopper(outUnitPrice) or outUnitPrice <= 0 then
    return {
      recipeID = recipe.recipeID,
      displayName = recipe.displayName,
      rung = "RUNG_2_CONVERSION",
      status = "MISSING_OUTPUT_PRICE",
      liquidationTime = turnaround.liquidationTime,
      saleThroughVerified = turnaround.saleThroughVerified,
      activeGphCopper = nil,
    }
  end

  local numLots = math.floor(totalOutputUnits / outputLotSize)
  local lotGrossCopper = MA.SafeMulNonNegativeCopper(outUnitPrice, outputLotSize)
  local grossSaleCopper = MA.SafeMulNonNegativeCopper(lotGrossCopper, numLots)

  local feeRule = opts.feeRule
  local feeStatus = "UNVERIFIED"
  if type(feeRule) == "table" then
    feeStatus = tostring(feeRule.verificationStatus or "UNVERIFIED")
    if (feeStatus == "VERIFIED" or feeStatus == "PARTIALLY_VERIFIED") and feeRule.observedBuild ~= currentBuild then
      feeStatus = "STALE_BUILD"
    end
  end

  if type(feeRule) ~= "table" or feeStatus ~= "VERIFIED" then
    return {
      recipeID = recipe.recipeID,
      displayName = recipe.displayName,
      professionKey = recipe.professionKey,
      rung = "RUNG_2_CONVERSION",
      status = "FEE_RULE_UNVERIFIED",
      feeRuleStatus = feeStatus,
      inputOutlayCopper = totalInputOutlayCopper,
      grossSaleCopper = grossSaleCopper,
      liquidationTime = turnaround.liquidationTime,
      turnaroundLabel = turnaround.turnaroundLabel,
      saleThroughVerified = turnaround.saleThroughVerified,
      leftoverInputs = leftoverInputs,
      activeGphCopper = nil,
    }
  end

  -- Resolve verified output vendor price via VendorArbitrage (Astra P0.1: single source of truth + quarantine preservation):
  local resolvedVendorUnitCopper = tonumber(recipe.outputVendorUnitCopper) or 0
  if recipe.outputItemID and ns.Domain and ns.Domain.VendorArbitrage and type(ns.Domain.VendorArbitrage.ResolveVerifiedVendorSellPrice) == "function" then
    local vRes = ns.Domain.VendorArbitrage.ResolveVerifiedVendorSellPrice(recipe.outputItemID, {
      allowStaticWhenClientUnavailable = (opts.allowStaticWhenClientUnavailable ~= false),
      liveSellPriceLookup = opts.liveSellPriceLookup,
    })
    if vRes and vRes.status == "quarantined_sell_price_mismatch" then
      return {
        recipeID = recipe.recipeID,
        displayName = recipe.displayName,
        professionKey = recipe.professionKey,
        rung = "RUNG_2_CONVERSION",
        status = "QUARANTINED_VENDOR_PRICE_MISMATCH",
        quarantine = vRes.quarantine,
        quarantineReason = vRes.quarantineReason,
        liquidationTime = turnaround.liquidationTime,
        saleThroughVerified = turnaround.saleThroughVerified,
        activeGphCopper = nil,
      }
    elseif vRes and vRes.status == "pending_item_cache" then
      return {
        recipeID = recipe.recipeID,
        displayName = recipe.displayName,
        professionKey = recipe.professionKey,
        rung = "RUNG_2_CONVERSION",
        status = "PENDING_ITEM_CACHE",
        liquidationTime = turnaround.liquidationTime,
        saleThroughVerified = turnaround.saleThroughVerified,
        activeGphCopper = nil,
      }
    elseif vRes and vRes.status == "ok" and tonumber(vRes.unitSellPrice) then
      resolvedVendorUnitCopper = tonumber(vRes.unitSellPrice)
    end
  end

  local singleDepositCopper = quoteFeeRuleDeposit(
    feeRule,
    resolvedVendorUnitCopper,
    outputLotSize,
    numLots,
    durationHours,
    currentBuild
  )
  if not singleDepositCopper then
    return {
      recipeID = recipe.recipeID,
      displayName = recipe.displayName,
      rung = "RUNG_2_CONVERSION",
      status = "FEE_RULE_UNVERIFIED",
      liquidationTime = turnaround.liquidationTime,
      saleThroughVerified = turnaround.saleThroughVerified,
      activeGphCopper = nil,
    }
  end

  local commissionCopper = MA.ComputeLotBatchCommissionCopper(
    lotGrossCopper,
    numLots,
    tonumber(feeRule.commissionBps) or 500,
    feeRule.roundingMode or "half_up"
  )
  local relistLossCopper = MA.SafeMulNonNegativeCopper(singleDepositCopper, expectedRelists)
  local netProceedsAfterComm = grossSaleCopper - commissionCopper
  local netSpreadZeroRelist = netProceedsAfterComm - totalInputOutlayCopper
  local netSpreadCopper = netSpreadZeroRelist - relistLossCopper

  local execStatus
  if discoveryOnly then
    execStatus = "DISCOVERY_ONLY_SUMMARY_INPUTS"
  elseif netSpreadCopper > 0 then
    execStatus = "POSITIVE_CONVERSION_SPREAD"
  else
    execStatus = "NON_POSITIVE_SPREAD"
  end

  return {
    recipeID = recipe.recipeID,
    displayName = recipe.displayName,
    professionKey = recipe.professionKey,
    minSkill = recipe.minSkill,
    outputItemID = recipe.outputItemID,
    totalOutputUnits = totalOutputUnits,
    numLots = numLots,
    outputLotSize = outputLotSize,
    supportsAuctionableVellums = recipe.supportsAuctionableVellums,
    rung = "RUNG_2_CONVERSION",
    status = execStatus,
    feeRuleStatus = feeStatus,
    inputOutlayCopper = totalInputOutlayCopper,
    grossSaleCopper = grossSaleCopper,
    singleListingDepositCopper = singleDepositCopper,
    commissionCopper = commissionCopper,
    relistDepositLossCopper = relistLossCopper,
    netSpreadZeroRelistCopper = netSpreadZeroRelist,
    netSpreadCopper = netSpreadCopper,
    leftoverInputs = leftoverInputs,
    saleThroughVerified = turnaround.saleThroughVerified,
    liquidationTime = turnaround.liquidationTime,
    censoringStatus = turnaround.censoringStatus,
    turnaroundLabel = turnaround.turnaroundLabel,
    observedSaleCount = turnaround.observedSaleCount,
    medianHoursToSell = turnaround.medianHoursToSell,
    activeGphCopper = nil,
  }
end

function ConversionSpreads.EvaluateAllCuratedConversions(opts)
  local results = {}
  for _, recipe in ipairs(ConversionSpreads.CURATED_RECIPES) do
    local perRecipeOpts = {}
    if type(opts) == "table" then
      for k, v in pairs(opts) do
        perRecipeOpts[k] = v
      end
      if type(opts.outputPricesByItemID) == "table" and perRecipeOpts.outputLotUnitPriceCopper == nil then
        perRecipeOpts.outputLotUnitPriceCopper = opts.outputPricesByItemID[recipe.outputItemID]
      end
      if type(opts.saleThroughByRecipeID) == "table" and perRecipeOpts.saleThroughEvidence == nil then
        perRecipeOpts.saleThroughEvidence = opts.saleThroughByRecipeID[recipe.recipeID]
      end
    end
    local eval = ConversionSpreads.EvaluateConversionSpread(recipe, perRecipeOpts)
    if eval then
      table.insert(results, eval)
    end
  end
  return results
end

-- ============================================================================
-- Astra P1.2: Conditional Per-Craft Margin, Conditional Single-Input Ceilings,
-- Separate Unlock Break-Even, Shared Transmute Selection & Discovery Export
--   m = q * P * (1 - f) - sum_i(a_i * C_i) - L - w * t
--   C_{k,max} = (q * P * (1 - f) - sum_{i ~= k}(a_i * C_i) - L - w * t) / a_k
-- ============================================================================

function ConversionSpreads.EvaluateConditionalRecipeMargin(recipe, opts)
  opts = type(opts) == "table" and opts or {}
  if type(recipe) ~= "table" then
    return nil, "invalid_recipe"
  end

  local q = math.max(1, math.floor(tonumber(recipe.outputQuantity) or 1))
  local outPrice = tonumber(opts.outputUnitPriceCopper)
  if not outPrice and type(opts.pricesByItemID) == "table" and recipe.outputItemID then
    outPrice = tonumber(opts.pricesByItemID[recipe.outputItemID])
  end
  if not outPrice and type(opts.pricesByRecipeID) == "table" and recipe.recipeID then
    outPrice = tonumber(opts.pricesByRecipeID[recipe.recipeID])
  end
  if not outPrice or outPrice <= 0 then
    return {
      recipeID = recipe.recipeID,
      displayName = recipe.displayName,
      professionKey = recipe.professionKey,
      status = "MISSING_OUTPUT_PRICE",
      simultaneousIndependentCeilings = false,
    }
  end

  local feeRate = tonumber(opts.ahCutRate)
  if feeRate == nil then
    feeRate = (opts.selfUseValuation == true) and 0.0 or 0.05
  end
  local listingLossCopper = math.max(0, math.floor(tonumber(opts.expectedListingLossPerCraftCopper) or 0))
  local castSeconds = math.max(0, tonumber(recipe.castSeconds) or 3)
  local timeWageCopperPerHour = math.max(0, tonumber(opts.opportunityWageCopperPerHour) or 0)
  local timeCostCopper = math.floor(((timeWageCopperPerHour * castSeconds) / 3600.0) + 0.5)

  local grossNetOfFeeCopper = math.floor((q * outPrice * (1.0 - feeRate)) + 0.5)
  local pricesByItemID = type(opts.pricesByItemID) == "table" and opts.pricesByItemID or {}
  local ownedByItemID = type(opts.ownedByItemID) == "table" and opts.ownedByItemID or {}
  local reservedByItemID = type(opts.reservedByItemID) == "table" and opts.reservedByItemID or {}

  local inputTerms = {}
  local totalInputCostCopper = 0

  for idx, inp in ipairs(recipe.inputs or {}) do
    local a_i = math.max(1, math.floor(tonumber(inp.quantityPerCraft) or 1))
    local unitCostCopper = nil
    if inp.sourceKind == "verified_merchant_bundle" then
      local bCopper = tonumber(inp.merchantBundleCopper)
      local bSize = math.max(1, math.floor(tonumber(inp.merchantBundleSize) or 1))
      if bCopper and bCopper > 0 then
        unitCostCopper = math.ceil(bCopper / bSize)
      end
    else
      unitCostCopper = tonumber(pricesByItemID[inp.itemID])
    end

    if not unitCostCopper or unitCostCopper <= 0 then
      return {
        recipeID = recipe.recipeID,
        displayName = recipe.displayName,
        professionKey = recipe.professionKey,
        status = "MISSING_INPUT_PRICE",
        missingItemID = inp.itemID,
        missingInputName = inp.name,
        simultaneousIndependentCeilings = false,
      }
    end

    local ownedTotal = math.max(0, math.floor(tonumber(ownedByItemID[inp.itemID]) or 0))
    local reservedTotal = math.max(0, math.floor(tonumber(reservedByItemID[inp.itemID]) or 0))
    local unreservedOwned = math.max(0, ownedTotal - reservedTotal)
    local termCost = a_i * unitCostCopper
    totalInputCostCopper = totalInputCostCopper + termCost

    table.insert(inputTerms, {
      inputIndex = idx,
      itemID = inp.itemID,
      name = inp.name,
      quantityPerCraft = a_i,
      sourceKind = inp.sourceKind or "ah_ladder",
      statedUnitCostCopper = unitCostCopper,
      termCostCopper = termCost,
      ownedCount = ownedTotal,
      reservedCount = reservedTotal,
      unreservedOwnedCount = unreservedOwned,
    })
  end

  local marginPerCraftCopper = grossNetOfFeeCopper - totalInputCostCopper - listingLossCopper - timeCostCopper

  -- Compute conditional single-input ceiling C_{k,max} for each input holding all other inputs i ~= k fixed:
  local conditionalCeilings = {}
  local conditionalCeilingsByItemID = {}
  for _, kTerm in ipairs(inputTerms) do
    local otherInputsCost = totalInputCostCopper - kTerm.termCostCopper
    local numerator = grossNetOfFeeCopper - otherInputsCost - listingLossCopper - timeCostCopper
    local cMax = math.floor(numerator / kTerm.quantityPerCraft)
    local row = {
      itemID = kTerm.itemID,
      name = kTerm.name,
      quantityPerCraft = kTerm.quantityPerCraft,
      statedUnitCostCopper = kTerm.statedUnitCostCopper,
      conditionalMaxUnitPriceCopper = cMax,
      otherInputsFixedCostCopper = otherInputsCost,
      isConditionalOnOtherInputs = true,
    }
    table.insert(conditionalCeilings, row)
    if kTerm.itemID then
      conditionalCeilingsByItemID[kTerm.itemID] = row
    end
  end

  -- Separate unlock break-even calculator (never folded into per-craft margin m):
  local unlockCostCopper = math.max(0, math.floor(tonumber(opts.unlockCostCopper or recipe.unlockCostCopper) or 0))
  local unlockBreakEvenCrafts = nil
  if unlockCostCopper > 0 then
    if marginPerCraftCopper > 0 then
      unlockBreakEvenCrafts = math.ceil(unlockCostCopper / marginPerCraftCopper)
    else
      unlockBreakEvenCrafts = math.huge
    end
  end

  local publishedWebYieldMarginCopper = nil
  if recipe.outputYieldConflict == true and tonumber(recipe.publishedWebSpellOutputQuantity) and tonumber(recipe.publishedWebSpellOutputQuantity) > q then
    local webQ = math.floor(tonumber(recipe.publishedWebSpellOutputQuantity))
    local webGrossNet = math.floor((webQ * outPrice * (1.0 - feeRate)) + 0.5)
    publishedWebYieldMarginCopper = webGrossNet - totalInputCostCopper - listingLossCopper - timeCostCopper
  end

  return {
    recipeID = recipe.recipeID,
    spellID = recipe.spellID,
    outputItemID = recipe.outputItemID,
    displayName = recipe.displayName,
    professionKey = recipe.professionKey,
    status = (marginPerCraftCopper > 0) and "POSITIVE_CONDITIONAL_MARGIN" or "NON_POSITIVE_CONDITIONAL_MARGIN",
    outputQuantity = q,
    outputYieldConflict = (recipe.outputYieldConflict == true),
    clientExtractOutputQuantity = recipe.clientExtractOutputQuantity,
    publishedWebSpellOutputQuantity = recipe.publishedWebSpellOutputQuantity,
    outputYieldVerificationNote = recipe.outputYieldVerificationNote,
    publishedWebYieldMarginPerCraftCopper = publishedWebYieldMarginCopper,
    outputUnitPriceCopper = outPrice,
    grossNetOfFeeCopper = grossNetOfFeeCopper,
    totalInputCostCopper = totalInputCostCopper,
    listingLossCopper = listingLossCopper,
    timeOpportunityCostCopper = timeCostCopper,
    marginPerCraftCopper = marginPerCraftCopper,
    simultaneousIndependentCeilings = false,
    ceilingConditionNote = "Each input ceiling C_{k,max} is conditional on all other inputs i ~= k being acquired at their stated prices C_i; ceilings cannot be spent simultaneously.",
    conditionalCeilings = conditionalCeilings,
    conditionalCeilingsByItemID = conditionalCeilingsByItemID,
    inputs = inputTerms,
    unlockCostCopper = unlockCostCopper,
    unlockBreakEvenCrafts = unlockBreakEvenCrafts,
  }
end

function ConversionSpreads.EvaluateSharedTransmuteGroup(opts)
  opts = type(opts) == "table" and opts or {}
  local candidates = type(opts.transmuteRecipes) == "table" and opts.transmuteRecipes or ConversionSpreads.SHARED_TRANSMUTE_RECIPES
  local liveObservedHours = tonumber(opts.liveObservedCooldownHours)
  local observedBuild = opts.observedBuild
  local pricesByItemID = type(opts.pricesByItemID) == "table" and opts.pricesByItemID or {}
  local evaluated = {}
  local unresolvedTransmutes = {}
  local bestCandidate = nil

  for _, recipe in ipairs(candidates) do
    local isResolved = (recipe.formulaResolved ~= false)
    local conflictStatus = recipe.conflictStatus
    if isResolved and recipe.verifiedClientBuild then
      if observedBuild and tostring(observedBuild) ~= tostring(recipe.verifiedClientBuild) then
        isResolved = false
        conflictStatus = "UNRESOLVED_BUILD_PROVENANCE"
      elseif recipe.isForeverCustomRecipe == true then
        for _, inp in ipairs(recipe.inputs or {}) do
          if not tonumber(pricesByItemID[inp.itemID]) or tonumber(pricesByItemID[inp.itemID]) <= 0 then
            isResolved = false
            conflictStatus = "UNRESOLVED_BUILD_SCOPED_REAGENT_PRICES"
            break
          end
        end
      end
    end

    local marginRes = isResolved and ConversionSpreads.EvaluateConditionalRecipeMargin(recipe, opts) or {
      recipeID = recipe.recipeID,
      spellID = recipe.spellID,
      outputItemID = recipe.outputItemID,
      displayName = recipe.displayName,
      professionKey = recipe.professionKey,
      status = conflictStatus or "UNRESOLVED_CORPUS_FORMULA",
      verifiedClientBuild = recipe.verifiedClientBuild,
      corpusClaimID = recipe.corpusClaimID,
      corpusFormulaText = recipe.corpusFormulaText,
      simultaneousIndependentCeilings = false,
    }
    local staticHrs = tonumber(recipe.staticCooldownHours) or 47
    local effectiveHours = (liveObservedHours and liveObservedHours > 0) and liveObservedHours or staticHrs
    local cooldownReconciliationStatus = "STATIC_DEFAULT"
    if liveObservedHours and liveObservedHours > 0 then
      if math.abs(liveObservedHours - staticHrs) > 0.05 then
        cooldownReconciliationStatus = "RECONCILED_TO_LIVE_COOLDOWN"
      else
        cooldownReconciliationStatus = "LIVE_MATCHES_STATIC"
      end
    end

    local marginCopper = (marginRes and tonumber(marginRes.marginPerCraftCopper)) or nil
    local annualizedDailyCopper = nil
    if marginCopper then
      annualizedDailyCopper = math.floor(((marginCopper * 24.0) / effectiveHours) + 0.5)
    end

    local entry = {
      recipeID = recipe.recipeID,
      spellID = recipe.spellID,
      outputItemID = recipe.outputItemID,
      displayName = recipe.displayName,
      sharedCooldownGroup = recipe.sharedCooldownGroup or "alchemy_shared_transmute",
      formulaResolved = isResolved,
      verifiedClientBuild = recipe.verifiedClientBuild,
      conflictStatus = conflictStatus,
      corpusClaimID = recipe.corpusClaimID,
      corpusFormulaText = recipe.corpusFormulaText,
      staticCooldownHours = staticHrs,
      effectiveCooldownHours = effectiveHours,
      cooldownReconciliationStatus = cooldownReconciliationStatus,
      marginPerCastCopper = marginCopper,
      equivalentDailyNetCopper = annualizedDailyCopper,
      evaluation = marginRes,
    }
    table.insert(evaluated, entry)
    if not isResolved then
      table.insert(unresolvedTransmutes, entry)
    end

    if isResolved and marginCopper and marginCopper > 0 then
      if not bestCandidate or (annualizedDailyCopper or 0) > (bestCandidate.equivalentDailyNetCopper or 0) then
        bestCandidate = entry
      end
    end
  end

  return {
    sharedCooldownGroup = "alchemy_shared_transmute",
    mutuallyExclusive = true,
    summedCooldownsAllowed = false,
    selectedTransmute = bestCandidate,
    selectedDailyNetCopper = bestCandidate and bestCandidate.equivalentDailyNetCopper or 0,
    unresolvedTransmutes = unresolvedTransmutes,
    candidates = evaluated,
  }
end

function ConversionSpreads.BuildConversionDiscoveryEntries(recipe, opts)
  opts = type(opts) == "table" and opts or {}
  local targetCrafts = math.max(1, math.floor(tonumber(opts.targetCrafts) or 1))
  local marginEval = ConversionSpreads.EvaluateConditionalRecipeMargin(recipe, opts)
  if not marginEval or not marginEval.inputs then
    return {
      ok = false,
      status = marginEval and marginEval.status or "INVALID_RECIPE",
      entries = {},
    }
  end

  local entries = {}
  for _, inp in ipairs(marginEval.inputs) do
    if inp.sourceKind ~= "verified_merchant_bundle" then
      local grossRequired = inp.quantityPerCraft * targetCrafts
      local deficitNetOfReserved = math.max(0, grossRequired - inp.unreservedOwnedCount)
      local ceilRow = marginEval.conditionalCeilingsByItemID and marginEval.conditionalCeilingsByItemID[inp.itemID]
      local conditionalMaxCopper = ceilRow and ceilRow.conditionalMaxUnitPriceCopper or inp.statedUnitCostCopper
      if deficitNetOfReserved > 0 and conditionalMaxCopper and conditionalMaxCopper > 0 then
        table.insert(entries, {
          itemID = inp.itemID,
          name = inp.name or (ns.EconomyData and ns.EconomyData.englishItemNames and ns.EconomyData.englishItemNames[inp.itemID]) or ("Item #" .. tostring(inp.itemID)),
          grossRequiredQuantity = grossRequired,
          ownedQuantity = inp.ownedCount,
          reservedProtectedQuantity = inp.reservedCount,
          unreservedAvailableQuantity = inp.unreservedOwnedCount,
          shoppingQuantity = deficitNetOfReserved,
          maxUnitPriceCopper = conditionalMaxCopper,
          isConditionalSingleInputCeiling = true,
        })
      end
    end
  end

  return {
    ok = true,
    recipeID = recipe.recipeID,
    displayName = recipe.displayName,
    targetCrafts = targetCrafts,
    simultaneousIndependentCeilings = false,
    ceilingConditionNote = marginEval.ceilingConditionNote,
    entries = entries,
  }
end

return ConversionSpreads
