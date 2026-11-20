local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.Domain = ns.Domain or {}

local ProtectionPolicy = {}
ns.Domain.ProtectionPolicy = ProtectionPolicy

ProtectionPolicy.SCHEMA = "foreverhub-protection-policy-v1"
ProtectionPolicy.NEVER_DESTROY_NOTICE =
  "ForeverHub never recommends destroying items by vendor value (0c items include enchanting mats, keys, tools, and custom tokens)."

-- Known classic / Forever profession tools, hearthstones, and permanent utility items that must NEVER be treated as junk:
local PROTECTED_UTILITY_ITEM_IDS = {
  [6948] = true,  -- Hearthstone
  [2901] = true,  -- Mining Pick
  [7005] = true,  -- Skinning Knife
  [5956] = true,  -- Blacksmith Hammer
  [6219] = true,  -- Arclight Spanner
  [5060] = true,  -- Thieves' Tools
  [6218] = true,  -- Runed Copper Rod
  [6339] = true,  -- Runed Silver Rod
  [11130] = true, -- Runed Golden Rod
  [11145] = true, -- Runed Truesilver Rod
  [16207] = true, -- Runed Arcanite Rod
  [9149] = true,  -- Philosopher's Stone
  [15846] = true, -- Salt Shaker
  [6256] = true,  -- Fishing Pole
  [6365] = true,  -- Strong Fishing Pole
  [6367] = true,  -- Big Iron Fishing Pole
  [4470] = true,  -- Simple Wood
  [4471] = true,  -- Flint and Tinder
}

local function isPositiveInt(v)
  return type(v) == "number" and v == v and v >= 1 and v < 9007199254740992 and math.floor(v) == v
end

local function isNonNegInt(v)
  return type(v) == "number" and v == v and v >= 0 and v < 9007199254740992 and math.floor(v) == v
end

local function isCatalogProtectedSupplyItem(itemID)
  local data = ns.Data
  if type(data) ~= "table" then
    return false
  end
  if (data.cratesByItemID and data.cratesByItemID[itemID])
    or (data.sealedCratesByItemID and data.sealedCratesByItemID[itemID])
    or (data.shippingLabelsByItemID and data.shippingLabelsByItemID[itemID])
    or (data.writsByItemID and data.writsByItemID[itemID])
    or (data.sealedWritsByItemID and data.sealedWritsByItemID[itemID])
  then
    return true
  end
  return false
end

local function normalizeBindingStatus(itemCtx)
  local raw = itemCtx.bindingStatus
  if type(raw) == "string" and raw ~= "" then
    local up = string.upper(raw)
    if up == "NONE" or up == "BOE" or up == "BOP" or up == "BOU" or up == "QUEST" or up == "ACCOUNT" or up == "UNKNOWN" then
      return up
    end
  end
  local bt = itemCtx.bindType
  if bt == 0 then
    return "NONE"
  elseif bt == 1 then
    return "BOP"
  elseif bt == 2 then
    return "BOE"
  elseif bt == 3 then
    return "BOU"
  elseif bt == 4 then
    return "QUEST"
  end
  return "UNKNOWN"
end

-- ============================================================================
-- Shared Item Protection Policy (`MUST_ADD_NOW` + Astra `P0.6`)
-- Unknown metadata, 0c items, locked/refundable slots, quest/key/tool/container/gear,
-- and active reservations ALWAYS default to `protected = true`.
-- ============================================================================

function ProtectionPolicy.EvaluateItemProtection(itemCtx, opts)
  opts = type(opts) == "table" and opts or {}
  if type(itemCtx) ~= "table" then
    return {
      protected = true,
      knownOrdinaryVendorJunk = false,
      status = "UNKNOWN_METADATA",
      reason = "invalid_item_context",
    }
  end

  local itemID = tonumber(itemCtx.itemID)
  if not isPositiveInt(itemID) then
    return {
      protected = true,
      knownOrdinaryVendorJunk = false,
      status = "UNKNOWN_METADATA",
      reason = "invalid_or_missing_item_id",
    }
  end

  if itemCtx.isLocked == true or itemCtx.isPending == true then
    return {
      protected = true,
      knownOrdinaryVendorJunk = false,
      status = "LOCKED_OR_PENDING",
      reason = "locked_or_pending_slot",
      itemID = itemID,
    }
  end

  if itemCtx.userProtected == true
    or (ns.State and type(ns.State.IsUserProtectedItem) == "function" and ns.State.IsUserProtectedItem(itemID) == true)
  then
    return {
      protected = true,
      knownOrdinaryVendorJunk = false,
      status = "USER_PROTECTED",
      reason = "user_protected_item",
      itemID = itemID,
    }
  end

  if PROTECTED_UTILITY_ITEM_IDS[itemID] == true or itemCtx.isToolOrTotemOrSymbol == true then
    return {
      protected = true,
      knownOrdinaryVendorJunk = false,
      status = "PROTECTED_UTILITY",
      reason = "tool_reagent_or_class_resource",
      itemID = itemID,
    }
  end

  if isCatalogProtectedSupplyItem(itemID)
    or (ns.Domain.VendorArbitrage and ns.Domain.VendorArbitrage.IsBlockedUnverifiedWrit and ns.Domain.VendorArbitrage.IsBlockedUnverifiedWrit(itemID))
  then
    return {
      protected = true,
      knownOrdinaryVendorJunk = false,
      status = "PROTECTED_SUPPLY_OR_WRIT",
      reason = "waylaid_crate_or_writ_protected",
      itemID = itemID,
    }
  end

  local isReserved = (itemCtx.isReserved == true) or ((tonumber(itemCtx.reservedQuantity) or 0) > 0)
  if not isReserved and opts.checkLiveReservations ~= false and ns.Domain.Reservations and type(ns.Domain.Reservations.GetMaterialStatus) == "function" then
    local okR, matStat = pcall(ns.Domain.Reservations.GetMaterialStatus, itemID)
    if okR and type(matStat) == "table" and (tonumber(matStat.reservedTotal) or 0) > 0 then
      isReserved = true
    end
  end
  if isReserved then
    return {
      protected = true,
      knownOrdinaryVendorJunk = false,
      status = "PROTECTED_RESERVED",
      reason = "active_reservation_protected",
      itemID = itemID,
    }
  end

  if itemCtx.isRefundable == true or itemCtx.hasActiveTradeTimer == true then
    return {
      protected = true,
      knownOrdinaryVendorJunk = false,
      status = "PROTECTED_REFUNDABLE",
      reason = "refundable_or_tradeable_timer",
      itemID = itemID,
    }
  end

  if itemCtx.isEquipmentSetMember == true then
    return {
      protected = true,
      knownOrdinaryVendorJunk = false,
      status = "PROTECTED_EQUIPMENT_SET",
      reason = "equipment_set_member",
      itemID = itemID,
    }
  end

  local metadataComplete = (itemCtx.metadataComplete == true)
  local quality = itemCtx.quality
  local unitSellPrice = itemCtx.unitSellPrice
  local bindingStatus = normalizeBindingStatus(itemCtx)

  if not metadataComplete or not isNonNegInt(quality) or not isNonNegInt(unitSellPrice) then
    return {
      protected = true,
      knownOrdinaryVendorJunk = false,
      status = "PENDING_METADATA",
      reason = "incomplete_item_metadata",
      itemID = itemID,
    }
  end

  local classID = tonumber(itemCtx.classID)
  local equipLoc = tostring(itemCtx.equipLoc or "")

  if itemCtx.isQuestItem == true or bindingStatus == "QUEST" or bindingStatus == "ACCOUNT" or classID == 12 or classID == 13 then
    return {
      protected = true,
      knownOrdinaryVendorJunk = false,
      status = "PROTECTED_QUEST_OR_KEY",
      reason = "quest_attunement_account_or_key",
      itemID = itemID,
    }
  end

  if classID == 1 or classID == 11 then
    return {
      protected = true,
      knownOrdinaryVendorJunk = false,
      status = "PROTECTED_CONTAINER",
      reason = "container_or_quiver",
      itemID = itemID,
    }
  end

  if classID == 5 then
    return {
      protected = true,
      knownOrdinaryVendorJunk = false,
      status = "PROTECTED_REAGENT",
      reason = "class_reagent_or_symbol",
      itemID = itemID,
    }
  end

  -- Astra P0.6: 0c vendor price items (enchanting mats, custom Forever tokens, keys) are ALWAYS protected!
  if unitSellPrice <= 0 then
    return {
      protected = true,
      knownOrdinaryVendorJunk = false,
      status = "PROTECTED_ZERO_SELL_PRICE",
      reason = "zero_vendor_value_protected",
      itemID = itemID,
    }
  end

  if quality >= 1 and (classID == 2 or classID == 4 or (equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP")) then
    return {
      protected = true,
      knownOrdinaryVendorJunk = false,
      status = "PROTECTED_EQUIPMENT",
      reason = "equippable_gear_or_trinket",
      itemID = itemID,
    }
  end

  -- Positively identified unbound, unlocked, unreserved `quality == 0` vendorable junk (`sellPrice > 0`):
  local explicitlyUnbound = (itemCtx.isBound == false)
    and (bindingStatus == "NONE" or bindingStatus == "BOE")

  if quality == 0 and unitSellPrice > 0 and explicitlyUnbound then
    return {
      protected = false,
      knownOrdinaryVendorJunk = true,
      status = "KNOWN_ORDINARY_VENDOR_JUNK",
      reason = "unbound_gray_positive_vendor_value",
      itemID = itemID,
      unitSellPrice = unitSellPrice,
    }
  end

  return {
    protected = true,
    knownOrdinaryVendorJunk = false,
    status = "PROTECTED_NON_JUNK",
    reason = (quality == 0) and "bound_or_unresolved_binding_gray" or "non_gray_item_protected",
    itemID = itemID,
  }
end

-- ============================================================================
-- Positive Merchant Resale Tradability Predicate (`Astra P0.1`)
-- NEVER uses `bindType ~= 1`! Uncached/nil metadata resolves strictly to `PENDING_METADATA`.
-- Requires:
--   metadata_complete AND binding_class_supported AND item_transferability_verified
--   AND merchant_offer_current AND cost_fully_resolved
-- ============================================================================

function ProtectionPolicy.EvaluatePositiveMerchantResaleTradability(offerCtx)
  if type(offerCtx) ~= "table" then
    return {
      eligible = false,
      status = "INVALID_OFFER",
      reason = "invalid_offer_context",
    }
  end

  local itemID = tonumber(offerCtx.itemID)
  if not isPositiveInt(itemID) then
    return {
      eligible = false,
      status = "INVALID_OFFER",
      reason = "invalid_item_id",
    }
  end

  if ns.Domain.VendorArbitrage and ns.Domain.VendorArbitrage.IsBlockedUnverifiedWrit and ns.Domain.VendorArbitrage.IsBlockedUnverifiedWrit(itemID) then
    return {
      eligible = false,
      status = "BLOCKED_WRIT",
      reason = "blocked_unverified_writ",
      itemID = itemID,
    }
  end

  -- 1. metadata_complete (uncached nil bindType MUST fail closed to PENDING_METADATA!)
  local bindType = offerCtx.bindType
  local bindingStatus = normalizeBindingStatus(offerCtx)
  if offerCtx.metadataComplete ~= true or (bindType == nil and bindingStatus == "UNKNOWN") then
    return {
      eligible = false,
      status = "PENDING_METADATA",
      reason = "item_metadata_or_binding_uncached",
      itemID = itemID,
    }
  end

  -- 2. binding_class_supported (ONLY positively established NONE (0) or BOE (2), non-unique, non-account, non-quest, non-conjured)
  local bindingSupported = ((bindType == 0 or bindType == 2) or (bindType == nil and (bindingStatus == "NONE" or bindingStatus == "BOE")))
    and bindType ~= 1
    and bindType ~= 3
    and bindType ~= 4
    and bindingStatus ~= "BOP"
    and bindingStatus ~= "BOU"
    and bindingStatus ~= "QUEST"
    and bindingStatus ~= "ACCOUNT"
    and offerCtx.isAccountBound ~= true
    and offerCtx.isQuestItem ~= true
    and offerCtx.isConjured ~= true
    and ((tonumber(offerCtx.maxUniqueCount) or 0) == 0)

  if not bindingSupported then
    return {
      eligible = false,
      status = "NON_TRADABLE_BINDING_OR_RESTRICTION",
      reason = "binding_or_uniqueness_blocks_resale",
      itemID = itemID,
      bindingStatus = bindingStatus,
    }
  end

  -- 3. item_transferability_verified (canonical MarketIdentity tradeSafe + no faction/instance/reputation transfer lock)
  if offerCtx.transferabilityVerified ~= true or offerCtx.reputationOrStandingLocked == true then
    return {
      eligible = false,
      status = "UNVERIFIED_TRANSFERABILITY",
      reason = "transferability_not_positively_verified",
      itemID = itemID,
    }
  end

  local canonicalKey = offerCtx.itemKey
  if type(canonicalKey) ~= "string" and ns.Domain.MarketIdentity and type(ns.Domain.MarketIdentity.ClassifyItemIdentity) == "function" then
    local okId, idRes = pcall(ns.Domain.MarketIdentity.ClassifyItemIdentity, {
      itemID = itemID,
      itemLink = offerCtx.itemLink,
      isVariantCapable = (offerCtx.isVariantCapable == true),
    })
    if okId and type(idRes) == "table" and idRes.tradeSafe == true then
      canonicalKey = idRes.itemKey
    end
  end
  if type(canonicalKey) ~= "string" or string.find(canonicalKey, "^i1:unk_var:") or string.find(canonicalKey, "^i1:service:") then
    return {
      eligible = false,
      status = "AMBIGUOUS_CANONICAL_IDENTITY",
      reason = "canonical_item_key_not_trade_safe",
      itemID = itemID,
    }
  end

  -- 4. merchant_offer_current & purchaseEligible
  local stockMode = tostring(offerCtx.stockMode or "UNKNOWN")
  local stockQty = tonumber(offerCtx.stockQuantity)
  local hasStock = (stockMode == "UNLIMITED") or (stockMode == "LIMITED" and isPositiveInt(stockQty))
  if offerCtx.merchantOfferCurrent ~= true or offerCtx.purchaseEligible ~= true or not hasStock then
    return {
      eligible = false,
      status = "OFFER_UNAVAILABLE_OR_INELIGIBLE",
      reason = "merchant_offer_stale_depleted_or_ineligible",
      itemID = itemID,
    }
  end

  -- 5. cost_fully_resolved (explicit extendedCost == false, positive integer bundle price & bundle quantity)
  local bundlePrice = tonumber(offerCtx.bundlePriceCopper)
  local bundleQty = tonumber(offerCtx.bundleQuantity)
  if offerCtx.extendedCost ~= false or not isPositiveInt(bundlePrice) or not isPositiveInt(bundleQty) then
    return {
      eligible = false,
      status = "EXTENDED_OR_UNRESOLVED_COST",
      reason = "extended_currency_or_unresolved_bundle_cost",
      itemID = itemID,
    }
  end

  return {
    eligible = true,
    status = "POSITIVE_TRADABILITY_VERIFIED",
    itemID = itemID,
    itemKey = canonicalKey,
    bindingStatus = (bindType == 2 or bindingStatus == "BOE") and "BOE" or "NONE",
    bundlePriceCopper = bundlePrice,
    bundleQuantity = bundleQty,
    effectiveUnitCostCeilCopper = math.ceil(bundlePrice / bundleQty),
    stockMode = stockMode,
    stockQuantity = stockQty,
  }
end

-- ============================================================================
-- Safe Inventory Space Recovery (`Astra P0.6` — Zero Item-Destruction Rankings)
-- Computes:
--   1. Exact known unbound `quality == 0` (`sellPrice > 0`) vendorable junk tally
--   2. Partial-stack consolidation slots within compatible `bagFamily` containers
--   3. Safe bank / mail storage alternatives for unreserved trade goods
-- ============================================================================

function ProtectionPolicy.EvaluateSafeInventoryRecovery(bagSlots, opts)
  opts = type(opts) == "table" and opts or {}
  local slots = type(bagSlots) == "table" and bagSlots or {}

  local junkSlotCount = 0
  local junkItemCount = 0
  local junkTotalCopper = 0
  local junkEntries = {}
  local protectedSlotCount = 0
  local pendingMetadataCount = 0

  -- Group unlocked partial stacks by `(bagFamily, itemKeyOrID)` so specialized bags never cross-merge!
  local partialGroups = {}
  local bankableTradeGoodSlots = 0

  for _, slot in ipairs(slots) do
    if type(slot) == "table" and slot.hasItem ~= false and isPositiveInt(tonumber(slot.itemID)) then
      local prot = ProtectionPolicy.EvaluateItemProtection(slot, opts)
      local stackCount = math.max(1, math.floor(tonumber(slot.stackCount) or 1))
      local maxStack = math.max(1, math.floor(tonumber(slot.maxStack) or 1))
      local bagFamily = math.max(0, math.floor(tonumber(slot.bagFamily) or 0))
      local mergeIdentity = tostring(slot.itemKey or ("id:" .. tostring(slot.itemID)))

      if prot.status == "PENDING_METADATA" then
        pendingMetadataCount = pendingMetadataCount + 1
        protectedSlotCount = protectedSlotCount + 1
      elseif prot.knownOrdinaryVendorJunk == true then
        junkSlotCount = junkSlotCount + 1
        junkItemCount = junkItemCount + stackCount
        local slotCopper = stackCount * (tonumber(prot.unitSellPrice) or 0)
        junkTotalCopper = junkTotalCopper + slotCopper
        table.insert(junkEntries, {
          bagID = slot.bagID,
          slotID = slot.slotID,
          itemID = slot.itemID,
          stackCount = stackCount,
          slotVendorCopper = slotCopper,
        })
      else
        protectedSlotCount = protectedSlotCount + 1
        if slot.isLocked ~= true
          and slot.isBound == false
          and prot.status ~= "PROTECTED_RESERVED"
          and tonumber(slot.classID) == 7
        then
          bankableTradeGoodSlots = bankableTradeGoodSlots + 1
        end
      end

      if slot.isLocked ~= true and maxStack > 1 and stackCount < maxStack then
        local gKey = string.format("fam:%d|%s", bagFamily, mergeIdentity)
        local grp = partialGroups[gKey]
        if not grp then
          grp = {
            bagFamily = bagFamily,
            itemID = tonumber(slot.itemID),
            itemKey = mergeIdentity,
            maxStack = maxStack,
            partialSlotCount = 0,
            totalUnits = 0,
          }
          partialGroups[gKey] = grp
        end
        grp.partialSlotCount = grp.partialSlotCount + 1
        grp.totalUnits = grp.totalUnits + stackCount
      end
    end
  end

  local consolidations = {}
  local totalConsolidationSlotsSaved = 0
  for _, grp in pairs(partialGroups) do
    if grp.partialSlotCount >= 2 then
      local minSlotsNeeded = math.ceil(grp.totalUnits / grp.maxStack)
      local saved = math.max(0, grp.partialSlotCount - minSlotsNeeded)
      if saved > 0 then
        totalConsolidationSlotsSaved = totalConsolidationSlotsSaved + saved
        table.insert(consolidations, {
          itemID = grp.itemID,
          itemKey = grp.itemKey,
          bagFamily = grp.bagFamily,
          currentSlots = grp.partialSlotCount,
          consolidatedSlots = minSlotsNeeded,
          slotsRecovered = saved,
        })
      end
    end
  end

  table.sort(consolidations, function(a, b)
    if a.slotsRecovered ~= b.slotsRecovered then
      return a.slotsRecovered > b.slotsRecovered
    end
    return (a.itemID or 0) < (b.itemID or 0)
  end)

  return {
    neverDestroyNotice = ProtectionPolicy.NEVER_DESTROY_NOTICE,
    recommendsDestroyingItems = false,
    knownVendorJunk = {
      slotCount = junkSlotCount,
      totalUnits = junkItemCount,
      totalVendorCopper = junkTotalCopper,
      entries = junkEntries,
    },
    stackConsolidation = {
      totalSlotsRecoverable = totalConsolidationSlotsSaved,
      groups = consolidations,
    },
    safeStorageAlternatives = {
      unreservedTradeGoodSlotsForBankOrAlt = bankableTradeGoodSlots,
    },
    protectedSlotCount = protectedSlotCount,
    pendingMetadataSlotCount = pendingMetadataCount,
  }
end

-- ============================================================================
-- Stage 7C Deferred Capability Gates (`Astra P0-5`, `P0-7`, Section 4)
-- Explicitly suppresses actionable Classic-reference DE advice, exact 5/hr account
-- lockout countdowns, openable-container EV, and spirit-rez optimization until
-- empirical Forever build evidence is recorded and audited.
-- ============================================================================

ProtectionPolicy.DEFERRED_STAGE7_CAPABILITIES = {
  DISENCHANT_RECOMMENDATION = {
    status = "DEFER_UNTIL_IN_GAME_PROBE",
    reason = "unverified_forever_disenchant_model_and_item_id_cutoff_rejected",
    label = "Disenchant EV deferred — Classic yield tables & itemID <= 24283 cutoffs are not verified for Forever.",
  },
  EXACT_ACCOUNT_LOCKOUT_COUNTDOWN = {
    status = "DEFER_UNTIL_IN_GAME_PROBE",
    reason = "forever_account_vs_character_lockout_window_and_copy_id_unverified",
    label = "Observed admissions; remaining capacity unknown.",
  },
  CONTAINER_OPENABLE_EV = {
    status = "DEFER_UNTIL_IN_GAME_PROBE",
    reason = "forever_container_drop_tables_unverified",
    label = "Container EV deferred — Forever loot tables unverified.",
  },
  SPIRIT_REZ_OPTIMIZER = {
    status = "DEFER_UNTIL_IN_GAME_PROBE",
    reason = "sickness_durability_and_graveyard_time_tradeoff_unverified",
    label = "Spirit resurrection optimization disabled.",
  },
}

function ProtectionPolicy.EvaluateDeferredCapabilityGate(capabilityKey, evidence)
  local key = tostring(capabilityKey or "")
  local spec = ProtectionPolicy.DEFERRED_STAGE7_CAPABILITIES[key]
  if not spec then
    return {
      actionable = false,
      status = "UNKNOWN_CAPABILITY",
      reason = "unregistered_capability_key",
      capabilityKey = key,
    }
  end
  -- Reject `itemID <= 24283` or missing-"cannot disenchant" heuristics unconditionally (`P0-7`):
  if key == "DISENCHANT_RECOMMENDATION" and type(evidence) == "table" then
    if evidence.usedItemIdCutoffHeuristic == true or evidence.usedMissingCannotDisenchantText == true then
      return {
        actionable = false,
        status = "PERMANENTLY_REJECTED_HEURISTIC",
        reason = "item_id_cutoff_or_negative_tooltip_absence_forbidden",
        label = spec.label,
        capabilityKey = key,
      }
    end
  end
  return {
    actionable = false,
    status = spec.status,
    reason = spec.reason,
    label = spec.label,
    capabilityKey = key,
  }
end

return ProtectionPolicy
