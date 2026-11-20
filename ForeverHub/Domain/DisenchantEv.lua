local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.Domain = ns.Domain or {}

local DisenchantEv = {}
ns.Domain.DisenchantEv = DisenchantEv

DisenchantEv.STATUS_PROTECTED_ITEM = "PROTECTED_ITEM"
DisenchantEv.STATUS_UNKNOWN_DE_TABLE = "UNKNOWN_DE_TABLE"
DisenchantEv.STATUS_UNVERIFIED_ELIGIBILITY = "UNVERIFIED_ELIGIBILITY"
DisenchantEv.STATUS_INCOMPLETE_PRICES = "INCOMPLETE_PRICES"
DisenchantEv.STATUS_QUOTED_EV_LIQUIDATION_UNKNOWN = "QUOTED_EV_LIQUIDATION_UNKNOWN"
DisenchantEv.STATUS_VENDOR_FAVORED = "VENDOR_FAVORED"
DisenchantEv.STATUS_DE_FAVORED = "DE_FAVORED"
DisenchantEv.STATUS_SALVAGER_DEPENDENT_UNVERIFIED = "SALVAGER_DEPENDENT_UNVERIFIED"

-- Strictly the three Astra-approved Salvager scenarios (NO 1.08x midpoint):
DisenchantEv.SCENARIO_MULTIPLIERS = {
  { key = "base_1_00x", multiplier = 1.00, label = "Base DE (1.00x)" },
  { key = "salvager_1_05x", multiplier = 1.05, label = "Salvager +5% (1.05x — 1x Camp)" },
  { key = "salvager_1_10x", multiplier = 1.10, label = "Salvager +10% (1.10x — 2x Camp)" },
}

-- Verified Classic/Forever Disenchant Outcome Distributions
-- Keyed by explicit table key or resolved from (quality, slotFamily, itemLevel) ONLY when
-- disenchantEligibilityVerified == true and itemLevel (never requiredLevel) is supplied.
DisenchantEv.VERIFIED_DE_TABLES = {
  uncommon_armor_ilvl_46_50 = {
    tableKey = "uncommon_armor_ilvl_46_50",
    quality = 2,
    slotFamily = "ARMOR",
    minItemLevel = 46,
    maxItemLevel = 50,
    outcomes = {
      { itemID = 11174, name = "Lesser Nether Essence", probability = 0.20, minQty = 1, maxQty = 2 },
      { itemID = 11176, name = "Dream Dust", probability = 0.75, minQty = 2, maxQty = 5 },
      { itemID = 11178, name = "Large Radiant Shard", probability = 0.05, minQty = 1, maxQty = 1 },
    },
  },
  uncommon_weapon_ilvl_46_50 = {
    tableKey = "uncommon_weapon_ilvl_46_50",
    quality = 2,
    slotFamily = "WEAPON",
    minItemLevel = 46,
    maxItemLevel = 50,
    outcomes = {
      { itemID = 11174, name = "Lesser Nether Essence", probability = 0.75, minQty = 1, maxQty = 2 },
      { itemID = 11176, name = "Dream Dust", probability = 0.20, minQty = 2, maxQty = 5 },
      { itemID = 11178, name = "Large Radiant Shard", probability = 0.05, minQty = 1, maxQty = 1 },
    },
  },
  uncommon_armor_ilvl_51_55 = {
    tableKey = "uncommon_armor_ilvl_51_55",
    quality = 2,
    slotFamily = "ARMOR",
    minItemLevel = 51,
    maxItemLevel = 55,
    outcomes = {
      { itemID = 16202, name = "Lesser Eternal Essence", probability = 0.20, minQty = 1, maxQty = 2 },
      { itemID = 16204, name = "Illusion Dust", probability = 0.75, minQty = 1, maxQty = 2 },
      { itemID = 14343, name = "Small Brilliant Shard", probability = 0.05, minQty = 1, maxQty = 1 },
    },
  },
  uncommon_weapon_ilvl_51_55 = {
    tableKey = "uncommon_weapon_ilvl_51_55",
    quality = 2,
    slotFamily = "WEAPON",
    minItemLevel = 51,
    maxItemLevel = 55,
    outcomes = {
      { itemID = 16202, name = "Lesser Eternal Essence", probability = 0.75, minQty = 1, maxQty = 2 },
      { itemID = 16204, name = "Illusion Dust", probability = 0.20, minQty = 1, maxQty = 2 },
      { itemID = 14343, name = "Small Brilliant Shard", probability = 0.05, minQty = 1, maxQty = 1 },
    },
  },
  uncommon_armor_ilvl_56_60 = {
    tableKey = "uncommon_armor_ilvl_56_60",
    quality = 2,
    slotFamily = "ARMOR",
    minItemLevel = 56,
    maxItemLevel = 60,
    outcomes = {
      { itemID = 16202, name = "Lesser Eternal Essence", probability = 0.20, minQty = 2, maxQty = 3 },
      { itemID = 16204, name = "Illusion Dust", probability = 0.75, minQty = 2, maxQty = 5 },
      { itemID = 14344, name = "Large Brilliant Shard", probability = 0.05, minQty = 1, maxQty = 1 },
    },
  },
  uncommon_weapon_ilvl_56_60 = {
    tableKey = "uncommon_weapon_ilvl_56_60",
    quality = 2,
    slotFamily = "WEAPON",
    minItemLevel = 56,
    maxItemLevel = 60,
    outcomes = {
      { itemID = 16202, name = "Lesser Eternal Essence", probability = 0.75, minQty = 2, maxQty = 3 },
      { itemID = 16204, name = "Illusion Dust", probability = 0.20, minQty = 2, maxQty = 5 },
      { itemID = 14344, name = "Large Brilliant Shard", probability = 0.05, minQty = 1, maxQty = 1 },
    },
  },
  rare_equip_ilvl_51_55 = {
    tableKey = "rare_equip_ilvl_51_55",
    quality = 3,
    slotFamily = "ANY",
    minItemLevel = 51,
    maxItemLevel = 55,
    outcomes = {
      { itemID = 14343, name = "Small Brilliant Shard", probability = 1.00, minQty = 1, maxQty = 1 },
    },
  },
  rare_equip_ilvl_56_65 = {
    tableKey = "rare_equip_ilvl_56_65",
    quality = 3,
    slotFamily = "ANY",
    minItemLevel = 56,
    maxItemLevel = 65,
    outcomes = {
      { itemID = 14344, name = "Large Brilliant Shard", probability = 1.00, minQty = 1, maxQty = 1 },
    },
  },
}

-- Separate explicit table registry for verified WoW: Forever raid epics (e.g., Malleable Essence of Nature).
-- Never inferred from generic Classic epic iLvl brackets unless explicitly supplied and verified.
DisenchantEv.VERIFIED_RAID_EPIC_TABLES = {
  forever_molten_core_nature_epic_verified = {
    tableKey = "forever_molten_core_nature_epic_verified",
    quality = 4,
    isRaidEpic = true,
    note = "Verified WoW: Forever raid epic DE table (Malleable Essence of Nature + Nexus Crystal distribution)",
    outcomes = {
      { itemID = 20725, name = "Nexus Crystal", probability = 1.00, minQty = 1, maxQty = 1 },
      { itemKey = "forever:malleable_essence_of_nature", name = "Malleable Essence of Nature", probability = 1.00, minQty = 1, maxQty = 1 },
    },
  },
}

DisenchantEv.__observedLog = {}

local function isPositiveInt(v)
  return type(v) == "number" and v == v and v >= 1 and v < 9007199254740992 and math.floor(v) == v
end

local function isNonNegInt(v)
  return type(v) == "number" and v == v and v >= 0 and v < 9007199254740992 and math.floor(v) == v
end

function DisenchantEv.ResetObservationsForTesting()
  DisenchantEv.__observedLog = {}
end

function DisenchantEv.RecordObservedDisenchant(obs)
  if type(obs) ~= "table" then
    return nil, "invalid_observation"
  end
  local buildVer = tostring(obs.buildVersion or (ns.Domain.RecipeRegistry and ns.Domain.RecipeRegistry.ResolveBuildVersion(obs)) or "forever_default_build")
  local itemCat = tostring(obs.itemCategory or "unknown_category")
  local campCond = tostring(obs.campCondition or "no_camp")
  local key = buildVer .. "|" .. itemCat .. "|" .. campCond
  local bucket = DisenchantEv.__observedLog[key]
  if not bucket then
    bucket = {
      buildVersion = buildVer,
      itemCategory = itemCat,
      campCondition = campCond,
      sampleCount = 0,
      duplicateProcCount = 0,
      samples = {},
      autoPromotedToRule = false, -- Never auto-promote empirical observations to universal rules
    }
    DisenchantEv.__observedLog[key] = bucket
  end
  bucket.sampleCount = bucket.sampleCount + 1
  if obs.duplicateProcObserved == true then
    bucket.duplicateProcCount = bucket.duplicateProcCount + 1
  end
  table.insert(bucket.samples, {
    sourceItemID = tonumber(obs.sourceItemID),
    outputItemID = tonumber(obs.outputItemID),
    outputQuantity = tonumber(obs.outputQuantity) or 1,
    duplicateProcObserved = (obs.duplicateProcObserved == true),
  })
  return bucket, nil
end

function DisenchantEv.ResolveVerifiedTable(itemSpec)
  if type(itemSpec) ~= "table" then
    return nil, "invalid_item_spec"
  end

  if type(itemSpec.customVerifiedOutcomes) == "table" and #itemSpec.customVerifiedOutcomes > 0 then
    return {
      tableKey = tostring(itemSpec.verifiedDisenchantTableKey or "custom_verified_table"),
      outcomes = itemSpec.customVerifiedOutcomes,
    }, nil
  end

  local quality = tonumber(itemSpec.quality)
  if quality == 4 or itemSpec.isRaidEpic == true then
    local raidKey = tostring(itemSpec.verifiedRaidEpicTableKey or "")
    local raidTbl = DisenchantEv.VERIFIED_RAID_EPIC_TABLES[raidKey]
    if raidTbl and itemSpec.raidEpicTableVerified == true then
      return raidTbl, nil
    end
    return nil, "unverified_forever_raid_epic_table"
  end

  if type(itemSpec.verifiedDisenchantTableKey) == "string" then
    local direct = DisenchantEv.VERIFIED_DE_TABLES[itemSpec.verifiedDisenchantTableKey]
    if direct then
      return direct, nil
    end
  end

  -- Strictly require itemLevel (never substitute requiredLevel!)
  local itemLevel = tonumber(itemSpec.itemLevel)
  if not isPositiveInt(itemLevel) then
    return nil, "missing_item_level_never_use_required_level"
  end

  local slotFamily = tostring(itemSpec.slotFamily or ""):upper()
  if quality == 2 and (slotFamily ~= "ARMOR" and slotFamily ~= "WEAPON") then
    return nil, "unsupported_or_ambiguous_slot_family"
  end

  for _, tbl in pairs(DisenchantEv.VERIFIED_DE_TABLES) do
    if tbl.quality == quality and itemLevel >= tbl.minItemLevel and itemLevel <= tbl.maxItemLevel then
      if tbl.slotFamily == "ANY" or tbl.slotFamily == slotFamily then
        return tbl, nil
      end
    end
  end

  return nil, "no_verified_de_table_for_bracket"
end

function DisenchantEv.EvaluateItemDisenchant(itemSpec, opts)
  opts = type(opts) == "table" and opts or {}
  if type(itemSpec) ~= "table" then
    return {
      eligible = false,
      status = DisenchantEv.STATUS_UNVERIFIED_ELIGIBILITY,
      reason = "invalid_item_spec",
    }
  end

  -- 1. Protection Gate (never recommend destroying protected items):
  if itemSpec.isEquipped == true
    or itemSpec.isReserved == true
    or itemSpec.isUpgradeCandidate == true
    or itemSpec.isQuestItem == true
    or itemSpec.isConjured == true
    or itemSpec.isUnique == true
  then
    return {
      eligible = false,
      status = DisenchantEv.STATUS_PROTECTED_ITEM,
      reason = "item_is_protected_from_destruction",
      itemID = tonumber(itemSpec.itemID),
    }
  end

  -- 2. Disenchant Eligibility Verification Gate:
  if itemSpec.isWand == true or itemSpec.isCustomForeverItem == true or itemSpec.isOffhandSpecial == true then
    if itemSpec.explicitForeverDeVerified ~= true then
      return {
        eligible = false,
        status = DisenchantEv.STATUS_UNVERIFIED_ELIGIBILITY,
        reason = "forever_custom_or_wand_de_eligibility_unverified",
        itemID = tonumber(itemSpec.itemID),
      }
    end
  end

  if itemSpec.disenchantEligibilityVerified ~= true then
    return {
      eligible = false,
      status = DisenchantEv.STATUS_UNVERIFIED_ELIGIBILITY,
      reason = "disenchant_eligibility_not_verified",
      itemID = tonumber(itemSpec.itemID),
    }
  end

  -- 3. Resolve Verified DE Table (strict itemLevel, separate raid epic handling):
  local deTable, tblErr = DisenchantEv.ResolveVerifiedTable(itemSpec)
  if not deTable then
    return {
      eligible = false,
      status = DisenchantEv.STATUS_UNKNOWN_DE_TABLE,
      reason = tblErr or "unknown_disenchant_table",
      itemID = tonumber(itemSpec.itemID),
      itemLevel = tonumber(itemSpec.itemLevel),
      requiredLevel = tonumber(itemSpec.requiredLevel),
    }
  end

  -- 4. Resolve Vendor Sell Price (via VendorArbitrage or explicit verified vendorSellCopper):
  local vendorSellCopper = tonumber(itemSpec.vendorSellCopper)
  if vendorSellCopper == nil and isPositiveInt(tonumber(itemSpec.itemID)) then
    if ns.Domain and ns.Domain.VendorArbitrage and type(ns.Domain.VendorArbitrage.ResolveVerifiedVendorSellPrice) == "function" then
      local vRes = ns.Domain.VendorArbitrage.ResolveVerifiedVendorSellPrice(tonumber(itemSpec.itemID), {
        allowStaticWhenClientUnavailable = (opts.allowStaticWhenClientUnavailable ~= false),
        liveSellPriceLookup = opts.liveSellPriceLookup,
      })
      if vRes and vRes.status == "quarantined_sell_price_mismatch" then
        return {
          eligible = false,
          status = DisenchantEv.STATUS_INCOMPLETE_PRICES,
          reason = "quarantined_vendor_sell_price_mismatch",
          quarantineReason = vRes.quarantineReason,
          itemID = tonumber(itemSpec.itemID),
        }
      elseif vRes and vRes.status == "ok" and isNonNegInt(vRes.unitSellPrice) then
        vendorSellCopper = vRes.unitSellPrice
      elseif vRes and vRes.status == "zero_vendor_sell_price" then
        vendorSellCopper = 0
      end
    end
  end

  if not isNonNegInt(vendorSellCopper) then
    return {
      eligible = false,
      status = DisenchantEv.STATUS_INCOMPLETE_PRICES,
      reason = "missing_verified_vendor_sell_price",
      itemID = tonumber(itemSpec.itemID),
    }
  end

  -- 5. Resolve Market Prices for All Possible DE Outcomes:
  local pricesByItemID = type(opts.materialPricesByItemID) == "table" and opts.materialPricesByItemID or {}
  local pricesByItemKey = type(opts.materialPricesByItemKey) == "table" and opts.materialPricesByItemKey or {}
  local ahCutRate = (opts.valuationMode == "self_use") and 0.0 or (tonumber(opts.ahCutRate) or 0.05)

  local baseExpectedNetCopper = 0
  local conservativeFloorCopper = nil
  local outcomeBreakdown = {}

  for _, outRow in ipairs(deTable.outcomes or {}) do
    local prob = tonumber(outRow.probability) or 0
    local minQty = math.max(1, math.floor(tonumber(outRow.minQty) or 1))
    local maxQty = math.max(minQty, math.floor(tonumber(outRow.maxQty) or minQty))
    local expectedQty = (minQty + maxQty) / 2.0

    local unitMarketCopper = nil
    if isPositiveInt(tonumber(outRow.itemID)) then
      unitMarketCopper = tonumber(pricesByItemID[tonumber(outRow.itemID)])
    end
    if unitMarketCopper == nil and type(outRow.itemKey) == "string" then
      unitMarketCopper = tonumber(pricesByItemKey[outRow.itemKey])
    end

    if not isPositiveInt(unitMarketCopper) then
      return {
        eligible = false,
        status = DisenchantEv.STATUS_INCOMPLETE_PRICES,
        reason = "missing_disenchant_material_price",
        missingMaterialItemID = outRow.itemID,
        missingMaterialName = outRow.name,
        tableKey = deTable.tableKey,
      }
    end

    local netUnitAfterFee = unitMarketCopper * (1.0 - ahCutRate)
    local expectedOutcomeCopper = prob * expectedQty * netUnitAfterFee
    local minOutcomeCopper = minQty * netUnitAfterFee

    baseExpectedNetCopper = baseExpectedNetCopper + expectedOutcomeCopper
    if prob > 0 and (conservativeFloorCopper == nil or minOutcomeCopper < conservativeFloorCopper) then
      conservativeFloorCopper = math.floor(minOutcomeCopper)
    end

    table.insert(outcomeBreakdown, {
      itemID = outRow.itemID,
      itemKey = outRow.itemKey,
      name = outRow.name,
      probability = prob,
      minQty = minQty,
      maxQty = maxQty,
      expectedQty = expectedQty,
      unitMarketCopper = unitMarketCopper,
      expectedContributionCopper = math.floor(expectedOutcomeCopper + 0.5),
      floorOutcomeCopper = math.floor(minOutcomeCopper),
    })
  end

  conservativeFloorCopper = conservativeFloorCopper or 0

  -- 6. Build the 3 Explicit Scenarios (1.00x, 1.05x, 1.10x):
  local scenarios = {}
  local scenariosByKey = {}
  for _, sc in ipairs(DisenchantEv.SCENARIO_MULTIPLIERS) do
    local expectedCopper = math.floor((baseExpectedNetCopper * sc.multiplier) + 0.5)
    local deltaVsVendor = expectedCopper - vendorSellCopper
    local row = {
      scenarioKey = sc.key,
      multiplier = sc.multiplier,
      label = sc.label,
      expectedNetCopper = expectedCopper,
      conservativeFloorCopper = conservativeFloorCopper,
      vendorSellCopper = vendorSellCopper,
      deltaVsVendorCopper = deltaVsVendor,
      beatsVendor = (expectedCopper > vendorSellCopper),
    }
    table.insert(scenarios, row)
    scenariosByKey[sc.key] = row
  end

  local baseBeatsVendor = scenariosByKey.base_1_00x.beatsVendor
  local salvager105BeatsVendor = scenariosByKey.salvager_1_05x.beatsVendor
  local salvager110BeatsVendor = scenariosByKey.salvager_1_10x.beatsVendor
  local liquidationVerified = (opts.liquidationVerified == true)
  local salvagerLiveVerified = (opts.salvagerLiveVerified == true)

  local finalStatus
  local recommendation
  if not baseBeatsVendor and not salvager105BeatsVendor and not salvager110BeatsVendor then
    finalStatus = DisenchantEv.STATUS_VENDOR_FAVORED
    recommendation = "Vendor immediately — vendor cash exceeds DE EV even under 1.10x Salvager camp."
  elseif not baseBeatsVendor and (salvager105BeatsVendor or salvager110BeatsVendor) and not salvagerLiveVerified then
    finalStatus = DisenchantEv.STATUS_SALVAGER_DEPENDENT_UNVERIFIED
    recommendation = "Do NOT destroy yet — Base (1.00x) loses to vendor; only profitable if Salvager camp bonus is live-verified."
  elseif not liquidationVerified then
    finalStatus = DisenchantEv.STATUS_QUOTED_EV_LIQUIDATION_UNKNOWN
    recommendation = "Quoted DE EV exceeds vendor, but AH sale-through is unverified (0c vendor floor on enchanting mats)."
  else
    finalStatus = DisenchantEv.STATUS_DE_FAVORED
    recommendation = "Disenchant favored — Base (1.00x) EV beats vendor and material liquidation is verified."
  end

  return {
    eligible = true,
    status = finalStatus,
    recommendation = recommendation,
    itemID = tonumber(itemSpec.itemID),
    itemLevel = tonumber(itemSpec.itemLevel),
    tableKey = deTable.tableKey,
    vendorSellCopper = vendorSellCopper,
    conservativeFloorCopper = conservativeFloorCopper,
    baseExpectedNetCopper = scenariosByKey.base_1_00x.expectedNetCopper,
    salvager105ExpectedNetCopper = scenariosByKey.salvager_1_05x.expectedNetCopper,
    salvager110ExpectedNetCopper = scenariosByKey.salvager_1_10x.expectedNetCopper,
    scenarios = scenarios,
    scenariosByKey = scenariosByKey,
    outcomes = outcomeBreakdown,
    liquidationVerified = liquidationVerified,
    salvagerLiveVerified = salvagerLiveVerified,
  }
end

return DisenchantEv
