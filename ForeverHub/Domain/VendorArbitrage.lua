local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.Domain = ns.Domain or {}

local VendorArbitrage = {}
ns.Domain.VendorArbitrage = VendorArbitrage

VendorArbitrage.PRE_EXECUTION_LABEL = "Vendor spread — verify purchase"
VendorArbitrage.POST_RECONCILIATION_LABEL = "Realized vendor profit"
VendorArbitrage.DISCOVERY_ONLY_LABEL = "Discovery candidate — scan exact stacks at AH"

VendorArbitrage.DEFAULT_MAX_LOT_AGE_SECONDS = 900 -- 15 minutes for executable lot observations
VendorArbitrage.__captureRevision = 1
VendorArbitrage.__quarantinedByItemID = {}
VendorArbitrage.__coalescedCacheKey = nil
VendorArbitrage.__coalescedSnapshot = nil

local FLAG_VENDORABLE = 1
local FLAG_UNIQUE = 2
local FLAG_CONJURED = 4
local FLAG_INSTANCE_SENSITIVE = 8
local FLAG_UNVERIFIED_WRIT = 16

local function hasBit(mask, bitVal)
  local m = math.max(0, math.floor(tonumber(mask) or 0))
  return (math.floor(m / bitVal) % 2) == 1
end

local function isPositiveInt(v)
  return type(v) == "number" and v == v and v >= 1 and v < 9007199254740992 and math.floor(v) == v
end

local function isNonNegInt(v)
  return type(v) == "number" and v == v and v >= 0 and v < 9007199254740992 and math.floor(v) == v
end

local function nowEpochSeconds(opts)
  if type(opts) == "table" and isPositiveInt(opts.nowSeconds) then
    return opts.nowSeconds
  end
  if ns.Compat and type(ns.Compat.GetServerTimeSafe) == "function" then
    local srv = ns.Compat.GetServerTimeSafe()
    local ep = type(srv) == "table" and tonumber(srv.epochSec) or tonumber(srv)
    if isPositiveInt(ep) then
      return ep
    end
  end
  if ns.Compat and type(ns.Compat.NowSeconds) == "function" then
    local t = ns.Compat.NowSeconds()
    if type(t) == "number" and t >= 1 then
      return math.floor(t)
    end
  end
  return 0
end

function VendorArbitrage.BumpCaptureRevision()
  VendorArbitrage.__captureRevision = (VendorArbitrage.__captureRevision or 1) + 1
  VendorArbitrage.__coalescedCacheKey = nil
  VendorArbitrage.__coalescedSnapshot = nil
end

function VendorArbitrage.InvalidateCache()
  VendorArbitrage.__coalescedCacheKey = nil
  VendorArbitrage.__coalescedSnapshot = nil
end

function VendorArbitrage.IsBlockedUnverifiedWrit(itemID)
  local id = tonumber(itemID)
  if not isPositiveInt(id) then
    return false
  end
  local econ = ns.EconomyData
  if econ and type(econ.blockedWritByItemID) == "table" and econ.blockedWritByItemID[id] == true then
    return true
  end
  if ns.Data then
    if type(ns.Data.writsByItemID) == "table" and ns.Data.writsByItemID[id] ~= nil then
      local w = ns.Data.writsByItemID[id]
      if type(w) ~= "table" or w.quantityVerified ~= true then
        return true
      end
    end
    if type(ns.Data.sealedWritsByItemID) == "table" and ns.Data.sealedWritsByItemID[id] ~= nil then
      return true
    end
  end
  return false
end

function VendorArbitrage.QuarantineItem(itemID, staticSellPrice, liveSellPrice, reason)
  local id = tonumber(itemID)
  if not isPositiveInt(id) then
    return
  end
  VendorArbitrage.__quarantinedByItemID[id] = {
    itemID = id,
    staticSellPrice = staticSellPrice,
    liveSellPrice = liveSellPrice,
    reason = tostring(reason or "live_sell_price_mismatch"),
    quarantinedAt = nowEpochSeconds(nil),
  }
  VendorArbitrage.InvalidateCache()
end

function VendorArbitrage.GetQuarantinedItem(itemID)
  local id = tonumber(itemID)
  if not isPositiveInt(id) then
    return nil
  end
  return VendorArbitrage.__quarantinedByItemID[id]
end

function VendorArbitrage.ListQuarantinedItems()
  local out = {}
  for id, q in pairs(VendorArbitrage.__quarantinedByItemID or {}) do
    if type(q) == "table" then
      table.insert(out, {
        itemID = q.itemID or id,
        staticSellPrice = q.staticSellPrice,
        liveSellPrice = q.liveSellPrice,
        reason = q.reason or "live_sell_price_mismatch",
        quarantinedAt = q.quarantinedAt,
      })
    end
  end
  table.sort(out, function(a, b)
    return (tonumber(a.itemID) or 0) < (tonumber(b.itemID) or 0)
  end)
  return out
end

function VendorArbitrage.ClearQuarantineForTesting()
  VendorArbitrage.__quarantinedByItemID = {}
  VendorArbitrage.InvalidateCache()
end

function VendorArbitrage.CountFreePlayerBagSlots(opts)
  if type(opts) == "table" and isNonNegInt(opts.freeBagSlots) then
    return opts.freeBagSlots
  end
  if not (ns.Compat and type(ns.Compat.GetContainerNumSlots) == "function" and type(ns.Compat.GetContainerItemInfo) == "function") then
    return 16
  end
  local freeCount = 0
  local observedAnyBag = false
  for bagID = 0, 4 do
    local numSlots = tonumber(ns.Compat.GetContainerNumSlots(bagID)) or 0
    if numSlots > 0 then
      observedAnyBag = true
      for slot = 1, numSlots do
        local info = ns.Compat.GetContainerItemInfo(bagID, slot)
        if not info or (info.itemID == nil and info.hyperlink == nil and info.iconFileID == nil) then
          freeCount = freeCount + 1
        end
      end
    end
  end
  if not observedAnyBag then
    return 16
  end
  return freeCount
end

function VendorArbitrage.GetStaticDisputeInfo(itemID)
  local id = tonumber(itemID)
  if not isPositiveInt(id) then
    return nil
  end
  local econ = ns.EconomyData
  if econ and type(econ.staticDisputedSellPrices) == "table" then
    return econ.staticDisputedSellPrices[id]
  end
  return nil
end

-- Cross-checks static `ForeverHub_EconomyData` against live `Compat.GetItemSellPriceResult`.
-- Quarantines immediately if live client reports a different `unitSellPrice`.
function VendorArbitrage.ResolveVerifiedVendorSellPrice(itemID, opts)
  opts = type(opts) == "table" and opts or {}
  local id = tonumber(itemID)
  if not isPositiveInt(id) then
    return { status = "invalid_item_id", unitSellPrice = nil }
  end
  if VendorArbitrage.IsBlockedUnverifiedWrit(id) then
    return { status = "blocked_unverified_writ", itemID = id, quantityStatus = "UNKNOWN", unitSellPrice = nil }
  end

  local existingQ = VendorArbitrage.__quarantinedByItemID[id]
  if existingQ then
    return {
      status = "quarantined_sell_price_mismatch",
      itemID = id,
      unitSellPrice = nil,
      quarantine = existingQ,
      quarantineReason = existingQ.reason or "live_sell_price_mismatch",
    }
  end

  local econ = ns.EconomyData
  local staticTuple = (econ and type(econ.items) == "table") and econ.items[id] or nil
  local staticSellPrice = staticTuple and tonumber(staticTuple[1]) or nil
  local staticMaxStack = staticTuple and tonumber(staticTuple[2]) or nil
  local staticFlags = staticTuple and tonumber(staticTuple[3]) or 0

  if hasBit(staticFlags, FLAG_CONJURED) then
    return { status = "conjured_unsellable", itemID = id, unitSellPrice = nil, flags = staticFlags }
  end
  if hasBit(staticFlags, FLAG_UNVERIFIED_WRIT) then
    return { status = "blocked_unverified_writ", itemID = id, quantityStatus = "UNKNOWN", unitSellPrice = nil }
  end

  local liveRes = nil
  if type(opts.liveSellPriceLookup) == "function" then
    liveRes = opts.liveSellPriceLookup(id)
  elseif ns.Compat and type(ns.Compat.GetItemSellPriceResult) == "function" then
    liveRes = ns.Compat.GetItemSellPriceResult(id)
  end

  local liveStatus = type(liveRes) == "table" and liveRes.status or "unavailable"
  if liveStatus == "ok" and type(liveRes.unitSellPrice) == "number" then
    local livePrice = math.max(0, math.floor(liveRes.unitSellPrice))
    if staticSellPrice ~= nil and livePrice ~= staticSellPrice then
      VendorArbitrage.QuarantineItem(id, staticSellPrice, livePrice, "live_sell_price_mismatch")
      local qEntry = VendorArbitrage.__quarantinedByItemID[id]
      return {
        status = "quarantined_sell_price_mismatch",
        itemID = id,
        unitSellPrice = nil,
        quarantine = qEntry,
        quarantineReason = qEntry and qEntry.reason or "live_sell_price_mismatch",
      }
    end
    if livePrice <= 0 then
      return { status = "zero_vendor_sell_price", itemID = id, unitSellPrice = 0, flags = staticFlags }
    end
    return {
      status = "ok",
      itemID = id,
      unitSellPrice = livePrice,
      maxStack = staticMaxStack or 20,
      flags = staticFlags,
      verifiedBy = "live_client",
      itemName = liveRes.itemName,
    }
  elseif liveStatus == "loading" then
    if ns.Compat and type(ns.Compat.RequestLoadItemData) == "function" then
      ns.Compat.RequestLoadItemData(id)
    end
    return {
      status = "pending_item_cache",
      itemID = id,
      unitSellPrice = nil,
      flags = staticFlags,
    }
  elseif liveStatus == "unavailable" and opts.allowStaticWhenClientUnavailable == true and staticSellPrice ~= nil then
    local staticDispute = VendorArbitrage.GetStaticDisputeInfo(id)
    if staticDispute and opts.blockDisputedStaticWithoutLive == true then
      return {
        status = "static_conflict_requires_live",
        itemID = id,
        unitSellPrice = nil,
        staticDispute = staticDispute,
        flags = staticFlags,
      }
    end
    if staticSellPrice <= 0 then
      return { status = "zero_vendor_sell_price", itemID = id, unitSellPrice = 0, flags = staticFlags }
    end
    return {
      status = "ok",
      itemID = id,
      unitSellPrice = math.floor(staticSellPrice),
      maxStack = staticMaxStack or 20,
      flags = staticFlags,
      verifiedBy = "static_headless_fallback",
      staticDispute = staticDispute,
    }
  end

  return {
    status = "vendor_price_unverified",
    itemID = id,
    unitSellPrice = nil,
    liveStatus = liveStatus,
    flags = staticFlags,
  }
end

local function resolveLocalizedDisplayLabel(itemID, liveItemName, opts)
  local econ = ns.EconomyData
  local enFallback = (econ and type(econ.englishItemNames) == "table") and econ.englishItemNames[itemID] or nil
  if type(liveItemName) == "string" and liveItemName ~= "" then
    return liveItemName, false
  end
  if ns.Compat and type(ns.Compat.ResolveClientLocalizedItemName) == "function" then
    local resolved, err = ns.Compat.ResolveClientLocalizedItemName(itemID, enFallback, opts)
    if type(resolved) == "string" and resolved ~= "" then
      return resolved, false
    end
    if err == "pending_item_cache" then
      return string.format("Item #%d", itemID), true
    end
  end
  return enFallback or string.format("Item #%d", itemID), false
end

-- ============================================================================
-- Rung 1a: Direct AH-to-Vendor Conditional Spread Calculator (9-Point Gate)
--   Pi_vendor = sum_{l in L*} V_actual(l) - sum_{l in L*} B_l - C_incremental
--   GPH = 3600 * Pi_vendor / (T_search + T_buy + T_retrieve + T_travel + T_sell)
-- ============================================================================

function VendorArbitrage.EvaluateVendorSpreadLots(itemSpec, observedLots, opts)
  opts = type(opts) == "table" and opts or {}
  itemSpec = type(itemSpec) == "table" and itemSpec or { itemID = tonumber(itemSpec) }

  local checklist = {
    exact_item_identity = false,
    executable_buyout = false,
    observed_quantity = false,
    sufficiently_recent_observation = false,
    verified_vendorability = false,
    supported_instance_state = false,
    current_vendor_value = false,
    feasible_access = false,
    budget_and_inventory_capacity = false,
  }

  -- 1. exact_item_identity
  local itemID = tonumber(itemSpec.itemID)
  if not isPositiveInt(itemID) then
    return { eligible = false, status = "INELIGIBLE", failedGate = "exact_item_identity", reason = "invalid_item_id", checklist = checklist }
  end
  if VendorArbitrage.IsBlockedUnverifiedWrit(itemID) then
    return {
      eligible = false,
      status = "BLOCKED_WRIT",
      failedGate = "exact_item_identity",
      reason = "blocked_unverified_writ",
      quantityStatus = "UNKNOWN",
      checklist = checklist,
    }
  end
  if itemSpec.variantAmbiguous == true then
    return { eligible = false, status = "INELIGIBLE", failedGate = "exact_item_identity", reason = "ambiguous_variant", checklist = checklist }
  end
  local canonicalItemKey = nil
  if ns.Domain and ns.Domain.MarketIdentity and type(ns.Domain.MarketIdentity.ClassifyItemIdentity) == "function" then
    local okKey, idRes = pcall(ns.Domain.MarketIdentity.ClassifyItemIdentity, {
      itemID = itemID,
      itemLink = itemSpec.itemLink,
      charges = itemSpec.charges,
      isVariantCapable = (itemSpec.isVariantCapable == true),
    })
    if okKey and type(idRes) == "table" and type(idRes.itemKey) == "string" then
      if itemSpec.isVariantCapable == true and idRes.tradeSafe ~= true then
        return { eligible = false, status = "INELIGIBLE", failedGate = "exact_item_identity", reason = "ambiguous_variant", checklist = checklist }
      end
      canonicalItemKey = idRes.itemKey
    end
  end
  if not canonicalItemKey then
    return { eligible = false, status = "INELIGIBLE", failedGate = "exact_item_identity", reason = "canonical_key_failed", checklist = checklist }
  end
  checklist.exact_item_identity = true

  -- 7 & 5. current_vendor_value + verified_vendorability (checked early so quarantine/pending short-circuits cleanly)
  local sellRes = VendorArbitrage.ResolveVerifiedVendorSellPrice(itemID, opts)
  if sellRes.status == "pending_item_cache" then
    return {
      eligible = false,
      status = "PENDING_ITEM_CACHE",
      failedGate = "current_vendor_value",
      reason = "pending_item_cache",
      itemID = itemID,
      itemKey = canonicalItemKey,
      checklist = checklist,
    }
  elseif sellRes.status == "quarantined_sell_price_mismatch" then
    return {
      eligible = false,
      status = "QUARANTINED",
      failedGate = "current_vendor_value",
      reason = "live_sell_price_mismatch",
      itemID = itemID,
      itemKey = canonicalItemKey,
      quarantine = sellRes.quarantine,
      checklist = checklist,
    }
  elseif sellRes.status ~= "ok" or not isPositiveInt(sellRes.unitSellPrice) then
    return {
      eligible = false,
      status = "INELIGIBLE",
      failedGate = "verified_vendorability",
      reason = sellRes.status or "non_vendorable",
      itemID = itemID,
      itemKey = canonicalItemKey,
      checklist = checklist,
    }
  end
  local unitSellPrice = sellRes.unitSellPrice
  local staticFlags = tonumber(sellRes.flags) or 0
  checklist.verified_vendorability = true
  checklist.current_vendor_value = true

  -- 6. supported_instance_state (reject conjured, unknown charges, unverified durability/instance risk, Owned Unique)
  if itemSpec.isConjured == true or hasBit(staticFlags, FLAG_CONJURED) then
    return { eligible = false, status = "INELIGIBLE", failedGate = "supported_instance_state", reason = "conjured_item", checklist = checklist }
  end
  if itemSpec.hasUnknownCharges == true then
    return { eligible = false, status = "INELIGIBLE", failedGate = "supported_instance_state", reason = "unknown_charges", checklist = checklist }
  end
  if itemSpec.isDamaged == true then
    -- Zero auto-repair rule: never assume repairing restores profitable vendor spread
    return { eligible = false, status = "INELIGIBLE", failedGate = "supported_instance_state", reason = "damaged_item_no_auto_repair", checklist = checklist }
  end
  if hasBit(staticFlags, FLAG_INSTANCE_SENSITIVE) and itemSpec.instanceStateVerified ~= true then
    return {
      eligible = false,
      status = "INELIGIBLE",
      failedGate = "supported_instance_state",
      reason = "unverified_equipment_instance_state",
      checklist = checklist,
    }
  end
  local isUnique = (itemSpec.isUnique == true) or hasBit(staticFlags, FLAG_UNIQUE)
  local ownedTotal = math.max(0, math.floor(tonumber(itemSpec.ownedCount) or 0))
  if isUnique and ownedTotal >= 1 then
    return { eligible = false, status = "INELIGIBLE", failedGate = "supported_instance_state", reason = "unique_already_owned", checklist = checklist }
  end
  checklist.supported_instance_state = true

  -- 8. feasible_access (combat lockdown, AH + vendor reachability)
  local inCombat = (opts.inCombat ~= nil) and (opts.inCombat == true)
    or (ns.Compat and ns.Compat.IsInCombat and ns.Compat.IsInCombat())
    or false
  if inCombat then
    return { eligible = false, status = "BLOCKED_COMBAT", failedGate = "feasible_access", reason = "in_combat_lockdown", checklist = checklist }
  end
  if opts.auctionHouseAccessible == false or opts.vendorAccessible == false then
    return { eligible = false, status = "INELIGIBLE", failedGate = "feasible_access", reason = "ah_or_vendor_inaccessible", checklist = checklist }
  end
  checklist.feasible_access = true

  -- 2, 3, 4. executable_buyout + observed_quantity + sufficiently_recent_observation
  if type(observedLots) ~= "table" or #observedLots == 0 then
    return { eligible = false, status = "INELIGIBLE", failedGate = "executable_buyout", reason = "no_observed_lots", checklist = checklist }
  end

  local nowSec = nowEpochSeconds(opts)
  local maxAgeSec = isPositiveInt(opts.maxObservationAgeSeconds)
      and opts.maxObservationAgeSeconds
    or VendorArbitrage.DEFAULT_MAX_LOT_AGE_SECONDS

  local anyPositiveBuyout = false
  local anyValidQty = false
  local anyRecent = false
  local candidateLots = {}
  local skippedBidOnlyCount = 0
  local skippedStaleCount = 0

  for idx, rawLot in ipairs(observedLots) do
    if type(rawLot) == "table" then
      local buyout = tonumber(rawLot.buyoutCopper or rawLot.buyoutPrice)
      local stackSize = tonumber(rawLot.stackSize or rawLot.count)
      local obsAt = tonumber(rawLot.observedAt)
      if not isPositiveInt(buyout) then
        skippedBidOnlyCount = skippedBidOnlyCount + 1
      else
        anyPositiveBuyout = true
        if isPositiveInt(stackSize) then
          anyValidQty = true
          local ageSec = (isPositiveInt(obsAt) and nowSec > 0) and (nowSec - obsAt) or nil
          if ageSec ~= nil and ageSec >= 0 and ageSec <= maxAgeSec then
            anyRecent = true
            local lotDamaged = (rawLot.isDamaged == true)
            local lotUnknownCharges = (rawLot.hasUnknownCharges == true)
            if not lotDamaged and not lotUnknownCharges and (not isUnique or stackSize == 1) then
              local lotVendorCopper = stackSize * unitSellPrice
              local lotSpreadCopper = lotVendorCopper - buyout
              if lotSpreadCopper > 0 then
                table.insert(candidateLots, {
                  lotIndex = idx,
                  lotId = rawLot.lotId or tostring(idx),
                  stackSize = stackSize,
                  buyoutCopper = buyout,
                  vendorValueCopper = lotVendorCopper,
                  netLotSpreadCopper = lotSpreadCopper,
                  observedAt = obsAt,
                  ageSeconds = ageSec,
                })
              end
            end
          else
            skippedStaleCount = skippedStaleCount + 1
          end
        end
      end
    end
  end

  if not anyPositiveBuyout then
    return {
      eligible = false,
      status = "INELIGIBLE",
      failedGate = "executable_buyout",
      reason = "bid_only_or_zero_buyout",
      skippedBidOnlyCount = skippedBidOnlyCount,
      checklist = checklist,
    }
  end
  checklist.executable_buyout = true

  if not anyValidQty then
    return { eligible = false, status = "INELIGIBLE", failedGate = "observed_quantity", reason = "missing_observed_quantity", checklist = checklist }
  end
  checklist.observed_quantity = true

  if not anyRecent then
    return {
      eligible = false,
      status = "STALE_OBSERVATION",
      failedGate = "sufficiently_recent_observation",
      reason = "stale_or_unverified_timestamp",
      skippedStaleCount = skippedStaleCount,
      checklist = checklist,
    }
  end
  checklist.sufficiently_recent_observation = true

  if #candidateLots == 0 then
    return {
      eligible = false,
      status = "NO_POSITIVE_SPREAD",
      failedGate = "budget_and_inventory_capacity",
      reason = "no_lots_below_vendor_value",
      unitSellPrice = unitSellPrice,
      checklist = checklist,
    }
  end

  -- 9. budget_and_inventory_capacity (Reserves + Free Bag Slots + Whole-Stack Subset Selection)
  local reserveSnap = (ns.Domain and ns.Domain.Reserves and ns.Domain.Reserves.EvaluateCharacterReserves)
      and ns.Domain.Reserves.EvaluateCharacterReserves(opts)
    or { status = "ok", investableCopper = math.max(0, math.floor(tonumber(opts.investableCopper) or 0)) }
  if opts.investableCopper ~= nil and isNonNegInt(opts.investableCopper) then
    reserveSnap = {
      status = "ok",
      liquidCopper = reserveSnap.liquidCopper or opts.investableCopper,
      investableCopper = opts.investableCopper,
      protectedCopperNow = reserveSnap.protectedCopperNow or 0,
      summaryReason = reserveSnap.summaryReason or "explicit_budget",
    }
  end

  local investableCopper = (reserveSnap.status == "ok") and (reserveSnap.investableCopper or 0) or 0
  local incrementalCostCopper = isNonNegInt(opts.incrementalCostCopper) and opts.incrementalCostCopper or 0
  local freeBagSlots = VendorArbitrage.CountFreePlayerBagSlots(opts)
  local maxStacksAllowed = isUnique and math.min(1, freeBagSlots) or freeBagSlots

  if investableCopper <= incrementalCostCopper or maxStacksAllowed <= 0 then
    return {
      eligible = false,
      status = "BUDGET_OR_BAG_CONSTRAINED",
      failedGate = "budget_and_inventory_capacity",
      reason = (maxStacksAllowed <= 0) and "no_free_bag_slots" or (reserveSnap.summaryReason or "insufficient_investable_copper"),
      reserveSnapshot = reserveSnap,
      freeBagSlots = freeBagSlots,
      checklist = checklist,
    }
  end

  local maxBuyoutBudget = investableCopper - incrementalCostCopper

  -- Sort candidate lots deterministically by highest spread per stack, then lowest buyout, then lotIndex:
  table.sort(candidateLots, function(a, b)
    if a.netLotSpreadCopper ~= b.netLotSpreadCopper then
      return a.netLotSpreadCopper > b.netLotSpreadCopper
    end
    if a.buyoutCopper ~= b.buyoutCopper then
      return a.buyoutCopper < b.buyoutCopper
    end
    return a.lotIndex < b.lotIndex
  end)

  -- Exact branch-and-bound whole-stack subset optimizer (bounded to top 20 lots for O(1) latency):
  local poolSize = math.min(#candidateLots, 20)
  local bestProfit = 0
  local bestOutlay = 0
  local bestIndices = nil

  local suffixMaxGain = {}
  suffixMaxGain[poolSize + 1] = 0
  for i = poolSize, 1, -1 do
    suffixMaxGain[i] = suffixMaxGain[i + 1] + candidateLots[i].netLotSpreadCopper
  end

  local currentPick = {}
  local function search(idx, pickedCount, outlaySoFar, gainSoFar)
    if gainSoFar > bestProfit or (gainSoFar == bestProfit and gainSoFar > 0 and outlaySoFar < bestOutlay) then
      bestProfit = gainSoFar
      bestOutlay = outlaySoFar
      bestIndices = {}
      for k = 1, pickedCount do
        bestIndices[k] = currentPick[k]
      end
    end
    if idx > poolSize or pickedCount >= maxStacksAllowed then
      return
    end
    local remainingSlots = maxStacksAllowed - pickedCount
    -- Upper bound check:
    local optimisticExtra = suffixMaxGain[idx]
    if gainSoFar + optimisticExtra < bestProfit then
      return
    end
    -- Try taking candidateLots[idx]:
    local lot = candidateLots[idx]
    if outlaySoFar + lot.buyoutCopper <= maxBuyoutBudget then
      currentPick[pickedCount + 1] = idx
      search(idx + 1, pickedCount + 1, outlaySoFar + lot.buyoutCopper, gainSoFar + lot.netLotSpreadCopper)
    end
    -- Try skipping candidateLots[idx]:
    if remainingSlots > 0 then
      search(idx + 1, pickedCount, outlaySoFar, gainSoFar)
    end
  end

  search(1, 0, 0, 0)

  local netVendorProfitCopper = bestProfit - incrementalCostCopper
  if not bestIndices or #bestIndices == 0 or netVendorProfitCopper <= 0 then
    return {
      eligible = false,
      status = "BUDGET_OR_BAG_CONSTRAINED",
      failedGate = "budget_and_inventory_capacity",
      reason = "whole_stacks_exceed_investable_budget",
      reserveSnapshot = reserveSnap,
      freeBagSlots = freeBagSlots,
      checklist = checklist,
    }
  end
  checklist.budget_and_inventory_capacity = true

  local selectedLots = {}
  local totalUnits = 0
  local totalVendorGrossCopper = 0
  local totalBuyoutCopper = 0
  local maxLotAgeSeconds = 0
  local maxRecommendedUnitBuyoutCopper = 0

  for _, poolIdx in ipairs(bestIndices) do
    local lot = candidateLots[poolIdx]
    table.insert(selectedLots, lot)
    totalUnits = totalUnits + lot.stackSize
    totalVendorGrossCopper = totalVendorGrossCopper + lot.vendorValueCopper
    totalBuyoutCopper = totalBuyoutCopper + lot.buyoutCopper
    if lot.ageSeconds > maxLotAgeSeconds then
      maxLotAgeSeconds = lot.ageSeconds
    end
    local lotUnitCeil = math.floor(lot.buyoutCopper / lot.stackSize)
    if lotUnitCeil > maxRecommendedUnitBuyoutCopper then
      maxRecommendedUnitBuyoutCopper = lotUnitCeil
    end
  end

  local numStacks = #selectedLots
  local atAuctionHub = (opts.atAuctionHub ~= false)
  local tSearch = isNonNegInt(opts.tSearchSeconds) and opts.tSearchSeconds or 15
  local tBuy = isNonNegInt(opts.tBuySeconds) and opts.tBuySeconds or (4 * numStacks)
  local tRetrieve = isNonNegInt(opts.tRetrieveSeconds) and opts.tRetrieveSeconds or (20 + (2 * numStacks))
  local tTravel = isNonNegInt(opts.tTravelSeconds) and opts.tTravelSeconds or (atAuctionHub and 25 or 180)
  local tSell = isNonNegInt(opts.tSellSeconds) and opts.tSellSeconds or (5 + (2 * numStacks))
  local totalSeconds = math.max(1, tSearch + tBuy + tRetrieve + tTravel + tSell)
  local gphCopper = math.floor((3600 * netVendorProfitCopper) / totalSeconds)

  local displayName, labelPending = resolveLocalizedDisplayLabel(itemID, sellRes.itemName, opts)

  return {
    eligible = true,
    rung = "RUNG_1A_DIRECT_VENDOR",
    status = "ELIGIBLE_VERIFY_PURCHASE",
    headlineLabel = VendorArbitrage.PRE_EXECUTION_LABEL,
    itemID = itemID,
    itemKey = canonicalItemKey,
    displayName = displayName,
    localizedLabelPending = labelPending,
    unitSellPrice = unitSellPrice,
    selectedLots = selectedLots,
    stackCount = numStacks,
    totalUnits = totalUnits,
    totalVendorGrossCopper = totalVendorGrossCopper,
    totalBuyoutCopper = totalBuyoutCopper,
    incrementalCostCopper = incrementalCostCopper,
    totalOutlayCopper = totalBuyoutCopper + incrementalCostCopper,
    netVendorProfitCopper = netVendorProfitCopper,
    maxDiscoveryUnitCeilingCopper = math.max(1, unitSellPrice - 1),
    maxSelectedUnitBuyoutCopper = math.max(1, maxRecommendedUnitBuyoutCopper),
    timing = {
      tSearchSeconds = tSearch,
      tBuySeconds = tBuy,
      tRetrieveSeconds = tRetrieve,
      tTravelSeconds = tTravel,
      tSellSeconds = tSell,
      totalSeconds = totalSeconds,
    },
    gphCopper = gphCopper,
    maxLotAgeSeconds = maxLotAgeSeconds,
    skippedBidOnlyCount = skippedBidOnlyCount,
    reserveSnapshot = reserveSnap,
    freeBagSlots = freeBagSlots,
    discoveryWarning = "Shopping list maxPrice filters by group minimum buyout only — verify exact stack buyout & quantity before clicking Buy.",
    checklist = checklist,
  }
end

-- Never promotes summary-only Auctionator unit prices to executable Rung-1a offers!
function VendorArbitrage.EvaluateAuctionatorDiscoveryCandidate(itemID, priceInfo, opts)
  opts = type(opts) == "table" and opts or {}
  local id = tonumber(itemID)
  if not isPositiveInt(id) or VendorArbitrage.IsBlockedUnverifiedWrit(id) then
    return nil
  end
  if type(priceInfo) ~= "table" or not isPositiveInt(priceInfo.unitPrice) or priceInfo.isStale == true then
    return nil
  end
  local sellRes = VendorArbitrage.ResolveVerifiedVendorSellPrice(id, opts)
  if sellRes.status ~= "ok" or not isPositiveInt(sellRes.unitSellPrice) then
    return nil
  end
  if priceInfo.unitPrice >= sellRes.unitSellPrice then
    return nil
  end
  local displayName, labelPending = resolveLocalizedDisplayLabel(id, sellRes.itemName, opts)
  return {
    eligible = false, -- Strictly NOT an executable offer until exact stacks are scanned!
    rung = "RUNG_1A_DISCOVERY_ONLY",
    status = "DISCOVERY_SCAN_REQUIRED",
    headlineLabel = VendorArbitrage.DISCOVERY_ONLY_LABEL,
    itemID = id,
    displayName = displayName,
    localizedLabelPending = labelPending,
    summaryUnitBuyoutCopper = priceInfo.unitPrice,
    unitSellPrice = sellRes.unitSellPrice,
    potentialUnitSpreadCopper = sellRes.unitSellPrice - priceInfo.unitPrice,
    maxPriceDiscoveryCeilingCopper = math.max(1, sellRes.unitSellPrice - 1),
    ageDays = priceInfo.ageDays,
  }
end

function VendorArbitrage.ReconcileRealizedVendorProfit(input)
  if type(input) ~= "table" then
    return nil, "invalid_reconciliation_input"
  end
  local grossSold = tonumber(input.actualVendorGrossCopper)
  local buyoutPaid = tonumber(input.actualBuyoutPaidCopper)
  local incCost = tonumber(input.actualIncrementalCostCopper or 0)
  if not isNonNegInt(grossSold) or not isNonNegInt(buyoutPaid) or not isNonNegInt(incCost) then
    return nil, "invalid_copper_amounts"
  end
  return {
    status = "REALIZED_RECONCILED",
    headlineLabel = VendorArbitrage.POST_RECONCILIATION_LABEL,
    actualVendorGrossCopper = grossSold,
    actualBuyoutPaidCopper = buyoutPaid,
    actualIncrementalCostCopper = incCost,
    realizedProfitCopper = grossSold - buyoutPaid - incCost,
  }, nil
end

-- ============================================================================
-- Rung 1b: Batch Craft-to-Vendor Cash & Opportunity-Cost Engine
--   Pi_cash = V_{outputs actually sold} - C_{whole input purchases} - C_{training/travel/operations}
--   * Leftover inputs from whole-stack / bundle purchases are separated (NEVER counted in Pi_cash).
--   * Consumed owned bag inputs are valued at best supported alternative use (NEVER 0c free inputs).
--   * Vendor reagents require verified unlimited merchant offers (NEVER raw base BuyPrice).
-- ============================================================================

local function resolveVerifiedMerchantOffer(reagentItemID, opts)
  if type(opts) == "table" and type(opts.merchantOffersByItemID) == "table" and opts.merchantOffersByItemID[reagentItemID] ~= nil then
    local custom = opts.merchantOffersByItemID[reagentItemID]
    if type(custom) == "table" and custom.stockMode == "unlimited_verified" then
      local bTotal = tonumber(custom.bundleTotalCopper or custom[1])
      local bQty = tonumber(custom.bundleQuantity or custom[2] or 1)
      if isPositiveInt(bTotal) and isPositiveInt(bQty) then
        return {
          bundleTotalCopper = bTotal,
          bundleQuantity = bQty,
          stockMode = "unlimited_verified",
          standingDiscountEligible = (custom.standingDiscountEligible == true or custom[4] == true),
        }
      end
    end
    return nil
  end
  local econ = ns.EconomyData
  local tup = (econ and type(econ.merchantOffers) == "table") and econ.merchantOffers[reagentItemID] or nil
  if type(tup) == "table" and tup[3] == "unlimited_verified" and isPositiveInt(tup[1]) and isPositiveInt(tup[2]) then
    local bundleTotal = tup[1]
    local discountBps = (tup[4] == true and isNonNegInt(opts and opts.verifiedFactionDiscountBps))
        and math.min(2000, opts.verifiedFactionDiscountBps)
      or 0
    if discountBps > 0 then
      bundleTotal = math.max(1, math.floor((bundleTotal * (10000 - discountBps)) / 10000))
    end
    return {
      bundleTotalCopper = bundleTotal,
      bundleQuantity = tup[2],
      stockMode = "unlimited_verified",
    }
  end
  return nil
end

function VendorArbitrage.EvaluateCraftToVendorBatch(recipe, opts)
  opts = type(opts) == "table" and opts or {}
  if type(recipe) ~= "table" or type(recipe.recipeID) ~= "string" then
    return { eligible = false, status = "INELIGIBLE", reason = "invalid_recipe" }
  end
  if recipe.quantityVerified ~= true then
    return { eligible = false, status = "INELIGIBLE", reason = "unverified_output_quantity", quantityStatus = "UNKNOWN" }
  end
  local outputItemID = tonumber(recipe.outputItemID)
  local outputQuantity = tonumber(recipe.outputQuantity)
  if not isPositiveInt(outputItemID) or not isPositiveInt(outputQuantity) then
    return { eligible = false, status = "INELIGIBLE", reason = "invalid_output_spec" }
  end
  if VendorArbitrage.IsBlockedUnverifiedWrit(outputItemID) then
    return { eligible = false, status = "BLOCKED_WRIT", reason = "blocked_unverified_writ", quantityStatus = "UNKNOWN" }
  end

  local inCombat = (opts.inCombat ~= nil) and (opts.inCombat == true)
    or (ns.Compat and ns.Compat.IsInCombat and ns.Compat.IsInCombat())
    or false
  if inCombat then
    return { eligible = false, status = "BLOCKED_COMBAT", reason = "in_combat_lockdown" }
  end

  -- Check learned profession skill:
  local profKey = tostring(recipe.professionKey or "")
  local minSkill = math.max(1, math.floor(tonumber(recipe.minSkill) or 1))
  local learnedSkills = type(opts.learnedSkills) == "table" and opts.learnedSkills or nil
  local currentSkill = learnedSkills and tonumber(learnedSkills[profKey]) or nil
  local trainingCostCopper = isNonNegInt(opts.trainingCostCopper) and opts.trainingCostCopper or 0

  if learnedSkills ~= nil then
    if currentSkill == nil or currentSkill < minSkill then
      if not (opts.canTrainNow == true and isPositiveInt(trainingCostCopper)) then
        return {
          eligible = false,
          status = "PREREQUISITE_MISSING",
          reason = (currentSkill == nil) and "profession_not_learned" or "insufficient_skill_rank",
          professionKey = profKey,
          requiredSkill = minSkill,
          currentSkill = currentSkill,
        }
      end
    else
      trainingCostCopper = 0
    end
  else
    -- Without learned skill snapshot, never fabricate crafts requiring learned recipes
    return {
      eligible = false,
      status = "PREREQUISITE_UNVERIFIED",
      reason = "profession_skill_unverified",
      professionKey = profKey,
      requiredSkill = minSkill,
    }
  end

  if recipe.requiresStation ~= nil and opts.nearStations and opts.nearStations[recipe.requiresStation] ~= true then
    return {
      eligible = false,
      status = "PREREQUISITE_MISSING",
      reason = "missing_crafting_station",
      requiresStation = recipe.requiresStation,
    }
  end

  local freeBagSlots = VendorArbitrage.CountFreePlayerBagSlots(opts)
  if freeBagSlots < 1 then
    return {
      eligible = false,
      status = "BUDGET_OR_BAG_CONSTRAINED",
      reason = "no_free_bag_slots_for_crafting",
      freeBagSlots = freeBagSlots,
    }
  end

  -- Verify output vendor sell price against live client:
  local outSell = VendorArbitrage.ResolveVerifiedVendorSellPrice(outputItemID, opts)
  if outSell.status == "pending_item_cache" then
    return { eligible = false, status = "PENDING_ITEM_CACHE", reason = "pending_output_item_cache", itemID = outputItemID }
  elseif outSell.status == "quarantined_sell_price_mismatch" then
    return { eligible = false, status = "QUARANTINED", reason = "output_live_sell_price_mismatch", quarantine = outSell.quarantine }
  elseif outSell.status ~= "ok" or not isPositiveInt(outSell.unitSellPrice) then
    return { eligible = false, status = "INELIGIBLE", reason = outSell.status or "output_non_vendorable" }
  end
  local unitOutputVendorCopper = outSell.unitSellPrice

  -- Build reservation-aware unreserved bag inventory:
  local invSnapshot = opts.inventorySnapshot
  local orderedRes = opts.orderedReservations
  local allocLedger = nil
  if ns.Domain and ns.Domain.Reservations and type(ns.Domain.Reservations.BuildAllocationLedger) == "function" then
    allocLedger = ns.Domain.Reservations.BuildAllocationLedger(invSnapshot, orderedRes, nil, false)
  end

  local reserveSnap = (ns.Domain and ns.Domain.Reserves and ns.Domain.Reserves.EvaluateCharacterReserves)
      and ns.Domain.Reserves.EvaluateCharacterReserves(opts)
    or { status = "ok", investableCopper = math.max(0, math.floor(tonumber(opts.investableCopper) or 0)) }
  if opts.investableCopper ~= nil and isNonNegInt(opts.investableCopper) then
    reserveSnap = {
      status = "ok",
      liquidCopper = reserveSnap.liquidCopper or opts.investableCopper,
      investableCopper = opts.investableCopper,
      summaryReason = "explicit_budget",
    }
  end
  local investableCopper = (reserveSnap.status == "ok") and (reserveSnap.investableCopper or 0) or 0

  local ahLotsByItemID = type(opts.observedLotsByItemID) == "table" and opts.observedLotsByItemID or {}
  local altUseOverrides = type(opts.alternativeUseUnitCopperByItemID) == "table" and opts.alternativeUseUnitCopperByItemID or {}
  local operationsCostCopper = isNonNegInt(opts.operationsCostCopper) and opts.operationsCostCopper or 0

  -- Prepare per-reagent metadata & check unreserved bag stock:
  local reagentSpecs = {}
  local maxBagOnlyCrafts = nil
  for _, rTuple in ipairs(recipe.reagents or {}) do
    local rItemID = tonumber(rTuple[1] or rTuple.itemID)
    local rUnitQty = tonumber(rTuple[2] or rTuple.quantity)
    if not isPositiveInt(rItemID) or not isPositiveInt(rUnitQty) then
      return { eligible = false, status = "INELIGIBLE", reason = "invalid_reagent_tuple" }
    end
    local rSellRes = VendorArbitrage.ResolveVerifiedVendorSellPrice(rItemID, opts)
    if rSellRes.status == "quarantined_sell_price_mismatch" then
      return { eligible = false, status = "QUARANTINED", reason = "reagent_live_sell_price_mismatch", quarantine = rSellRes.quarantine }
    elseif rSellRes.status == "pending_item_cache" then
      return { eligible = false, status = "PENDING_ITEM_CACHE", reason = "pending_reagent_item_cache", itemID = rItemID }
    end
    local rDirectVendor = (rSellRes.status == "ok" and isNonNegInt(rSellRes.unitSellPrice)) and rSellRes.unitSellPrice or 0
    local rAltUseUnit = math.max(rDirectVendor, isNonNegInt(altUseOverrides[rItemID]) and altUseOverrides[rItemID] or 0)

    local unreservedBagUnits = 0
    if allocLedger and allocLedger.byItem and allocLedger.byItem[rItemID] then
      unreservedBagUnits = math.max(0, math.floor(tonumber(allocLedger.byItem[rItemID].freeBags) or 0))
    elseif type(invSnapshot) == "table" and invSnapshot[rItemID] ~= nil then
      local rawC = invSnapshot[rItemID]
      unreservedBagUnits = type(rawC) == "number" and math.max(0, math.floor(rawC))
        or math.max(0, math.floor(tonumber(rawC.bagCount) or 0))
    end

    if recipe.requiresToolItemID ~= nil then
      local toolID = tonumber(recipe.requiresToolItemID)
      local toolOwned = 0
      if type(invSnapshot) == "table" and invSnapshot[toolID] ~= nil then
        local tc = invSnapshot[toolID]
        toolOwned = type(tc) == "number" and tc or (tonumber(tc.bagCount) or 0)
      end
      if toolOwned <= 0 then
        return { eligible = false, status = "PREREQUISITE_MISSING", reason = "missing_required_tool", toolItemID = toolID }
      end
    end

    local craftsFromBag = math.floor(unreservedBagUnits / rUnitQty)
    if maxBagOnlyCrafts == nil or craftsFromBag < maxBagOnlyCrafts then
      maxBagOnlyCrafts = craftsFromBag
    end

    table.insert(reagentSpecs, {
      itemID = rItemID,
      unitQty = rUnitQty,
      unreservedBagUnits = unreservedBagUnits,
      altUseUnitCopper = rAltUseUnit,
      merchantOffer = resolveVerifiedMerchantOffer(rItemID, opts),
      ahLots = ahLotsByItemID[rItemID],
    })
  end

  maxBagOnlyCrafts = maxBagOnlyCrafts or 0
  local maxBatchCrafts = math.max(maxBagOnlyCrafts, math.min(40, tonumber(opts.maxBatchCrafts) or 25))

  -- Evaluate batch candidate counts (bag-only count + 1..maxBatchCrafts):
  local candidateCraftCounts = {}
  local seenN = {}
  if maxBagOnlyCrafts >= 1 then
    seenN[maxBagOnlyCrafts] = true
    table.insert(candidateCraftCounts, maxBagOnlyCrafts)
  end
  for n = 1, maxBatchCrafts do
    if not seenN[n] then
      seenN[n] = true
      table.insert(candidateCraftCounts, n)
    end
  end

  local bestEval = nil
  local firstFailureReason = "no_profitable_batch"

  for _, nCrafts in ipairs(candidateCraftCounts) do
    local totalWholePurchaseCopper = 0
    local totalOwnedOpportunityCopper = 0
    local totalExtraStacksNeeded = 0
    local leftoverInputs = {}
    local batchFeasible = true
    local failWhy = nil

    for _, rs in ipairs(reagentSpecs) do
      local totalReq = nCrafts * rs.unitQty
      local usedFromBags = math.min(totalReq, rs.unreservedBagUnits)
      local deficit = totalReq - usedFromBags
      totalOwnedOpportunityCopper = totalOwnedOpportunityCopper + (usedFromBags * rs.altUseUnitCopper)

      if deficit > 0 then
        if rs.merchantOffer then
          local bQty = rs.merchantOffer.bundleQuantity
          local bCount = math.ceil(deficit / bQty)
          local bCost = bCount * rs.merchantOffer.bundleTotalCopper
          local bUnits = bCount * bQty
          local extra = bUnits - deficit
          totalWholePurchaseCopper = totalWholePurchaseCopper + bCost
          totalExtraStacksNeeded = totalExtraStacksNeeded + 1
          if extra > 0 then
            table.insert(leftoverInputs, { itemID = rs.itemID, quantity = extra, source = "merchant_bundle" })
          end
        elseif type(rs.ahLots) == "table" and #rs.ahLots > 0 and ns.Domain and ns.Domain.MarketAccounting then
          -- Filter to recent positive-buyout lots:
          local nowSec = nowEpochSeconds(opts)
          local maxAgeSec = isPositiveInt(opts.maxObservationAgeSeconds)
              and opts.maxObservationAgeSeconds
            or VendorArbitrage.DEFAULT_MAX_LOT_AGE_SECONDS
          local cleanRungs = {}
          for _, l in ipairs(rs.ahLots) do
            local bo = tonumber(l.buyoutCopper or l.buyoutPrice)
            local cnt = tonumber(l.stackSize or l.count)
            local obsAt = tonumber(l.observedAt)
            if isPositiveInt(bo) and isPositiveInt(cnt) and isPositiveInt(obsAt) and (nowSec - obsAt) >= 0 and (nowSec - obsAt) <= maxAgeSec then
              table.insert(cleanRungs, { stackSize = cnt, stackBuyoutCopper = bo, numStacks = 1 })
            end
          end
          local acq = ns.Domain.MarketAccounting.WalkAskLadderEntryCost(cleanRungs, deficit, false, nil)
          if not acq or acq.status ~= "ok" or not isPositiveInt(acq.entryCostCopper) then
            batchFeasible = false
            failWhy = "insufficient_observed_ah_depth"
            break
          end
          local stacksBought = 0
          for _, f in ipairs(acq.fills or {}) do
            stacksBought = stacksBought + math.max(1, tonumber(f.stacksPurchased) or 1)
          end
          totalWholePurchaseCopper = totalWholePurchaseCopper + acq.entryCostCopper
          totalExtraStacksNeeded = totalExtraStacksNeeded + math.max(1, stacksBought)
          if (tonumber(acq.excessUnits) or 0) > 0 then
            table.insert(leftoverInputs, { itemID = rs.itemID, quantity = acq.excessUnits, source = "ah_whole_stack" })
          end
        else
          batchFeasible = false
          failWhy = "unverified_or_missing_reagent_offer"
          break
        end
      end
    end

    if not batchFeasible then
      firstFailureReason = failWhy or firstFailureReason
    else
      local totalCashOutlay = totalWholePurchaseCopper + trainingCostCopper + operationsCostCopper
      local outputMaxStack = tonumber(outSell.maxStack) or 20
      local outputStacksCreated = math.ceil((nCrafts * outputQuantity) / math.max(1, outputMaxStack))
      local peakSlotsRequired = math.max(1, totalExtraStacksNeeded + math.min(outputStacksCreated, 2))

      if totalCashOutlay > investableCopper then
        firstFailureReason = reserveSnap.summaryReason or "exceeds_investable_after_reserves"
      elseif peakSlotsRequired > freeBagSlots then
        firstFailureReason = "insufficient_free_bag_slots_for_batch"
      else
        local outputsSoldUnits = nCrafts * outputQuantity
        local outputsSoldVendorCopper = outputsSoldUnits * unitOutputVendorCopper
        -- Exact Astra Rung-1b cash equation (leftovers strictly excluded from Pi_cash!):
        local piCashCopper = outputsSoldVendorCopper - totalWholePurchaseCopper - trainingCostCopper - operationsCostCopper
        local economicSurplusCopper = piCashCopper - totalOwnedOpportunityCopper

        if piCashCopper > 0 and economicSurplusCopper > 0 then
          local castTotalSec = nCrafts * math.max(1, math.floor(tonumber(recipe.castSeconds) or 3))
          local purchaseOverheadSec = (totalWholePurchaseCopper > 0) and 45 or 0
          local travelAndSellSec = isNonNegInt(opts.tTravelAndSellSeconds) and opts.tTravelAndSellSeconds or 20
          local totalSec = math.max(1, castTotalSec + purchaseOverheadSec + travelAndSellSec)
          local gphCopper = math.floor((3600 * economicSurplusCopper) / totalSec)

          if not bestEval
            or economicSurplusCopper > bestEval.economicSurplusCopper
            or (economicSurplusCopper == bestEval.economicSurplusCopper and totalCashOutlay < bestEval.totalCashOutlayCopper)
          then
            local outDisplayName, labelPending = resolveLocalizedDisplayLabel(outputItemID, outSell.itemName, opts)
            bestEval = {
              eligible = true,
              rung = "RUNG_1B_CRAFT_TO_VENDOR",
              status = (totalCashOutlay == 0) and "ELIGIBLE_BAG_CONVERSION" or "ELIGIBLE_VERIFY_PURCHASE",
              headlineLabel = (totalCashOutlay == 0)
                  and "Bag craft-to-vendor uplift"
                or VendorArbitrage.PRE_EXECUTION_LABEL,
              recipeID = recipe.recipeID,
              professionKey = profKey,
              isSecondaryProfession = (recipe.isSecondaryProfession == true),
              craftCount = nCrafts,
              outputItemID = outputItemID,
              outputDisplayName = outDisplayName,
              localizedLabelPending = labelPending,
              outputsSoldUnits = outputsSoldUnits,
              unitOutputVendorCopper = unitOutputVendorCopper,
              outputsSoldVendorCopper = outputsSoldVendorCopper,
              wholeInputPurchaseCopper = totalWholePurchaseCopper,
              trainingAndOperationsCopper = trainingCostCopper + operationsCostCopper,
              totalCashOutlayCopper = totalCashOutlay,
              cashProfitCopper = piCashCopper,
              ownedInputsOpportunityCostCopper = totalOwnedOpportunityCopper,
              economicSurplusCopper = economicSurplusCopper,
              leftoverInputs = leftoverInputs,
              totalSeconds = totalSec,
              gphCopper = gphCopper,
              reserveSnapshot = reserveSnap,
              freeBagSlots = freeBagSlots,
            }
          end
        end
      end
    end
  end

  if not bestEval then
    return {
      eligible = false,
      status = "NO_PROFITABLE_BATCH",
      reason = firstFailureReason,
      recipeID = recipe.recipeID,
      reserveSnapshot = reserveSnap,
    }
  end
  return bestEval
end

-- ============================================================================
-- Coalesced Dirty-Flag Character Rung-1 Deck Evaluator
-- Never re-runs bounded-DP on passive UI refreshes when state revisions match.
-- ============================================================================

function VendorArbitrage.ComputeStateRevisionFingerprint(opts)
  opts = type(opts) == "table" and opts or {}
  local invRev, resRev, priceRev = 1, 1, 1
  if ns.State and type(ns.State.GetRevisions) == "function" then
    invRev, resRev, priceRev = ns.State.GetRevisions()
  end
  local mr = ns.Compat and ns.Compat.GetPlayerMoneyCopper and ns.Compat.GetPlayerMoneyCopper() or {}
  local moneyStr = (mr.status == "ok" and type(mr.copper) == "number") and tostring(mr.copper) or tostring(mr.status or "na")
  local lvl = tonumber(opts.level) or (ns.Compat and ns.Compat.GetPlayerLevel and ns.Compat.GetPlayerLevel()) or 1
  local fac = tostring(opts.faction or (ns.Compat and ns.Compat.GetPlayerFactionString and ns.Compat.GetPlayerFactionString()) or "UNKNOWN")
  local combat = ((opts.inCombat ~= nil and opts.inCombat == true) or (ns.Compat and ns.Compat.IsInCombat and ns.Compat.IsInCombat())) and "1" or "0"
  local loc = (ns.Compat and ns.Compat.GetClientLocale and ns.Compat.GetClientLocale()) or "enUS"
  return string.format(
    "%d:%d:%d:%d:%s:%d:%s:%s:%s",
    invRev,
    resRev,
    priceRev,
    VendorArbitrage.__captureRevision or 1,
    moneyStr,
    lvl,
    fac,
    combat,
    loc
  )
end

function VendorArbitrage.EvaluateCharacterRung1Deck(opts)
  local hasExplicitOverrides = (type(opts) == "table" and next(opts) ~= nil)
  if not hasExplicitOverrides then
    local fp = VendorArbitrage.ComputeStateRevisionFingerprint(nil)
    if VendorArbitrage.__coalescedSnapshot and VendorArbitrage.__coalescedCacheKey == fp then
      return VendorArbitrage.__coalescedSnapshot
    end
    local computed = VendorArbitrage.EvaluateCharacterRung1Deck({ __useLiveState = true })
    VendorArbitrage.__coalescedCacheKey = fp
    VendorArbitrage.__coalescedSnapshot = computed
    return computed
  end

  opts = type(opts) == "table" and opts or {}
  local reserveSnap = (ns.Domain and ns.Domain.Reserves and ns.Domain.Reserves.EvaluateCharacterReserves)
      and ns.Domain.Reserves.EvaluateCharacterReserves(opts)
    or { status = "unavailable", investableCopper = 0 }

  local directSpreadActions = {}
  local craftActions = {}
  local discoveryCandidates = {}
  local pendingItemCacheIDs = {}
  local quarantinedItems = {}

  -- 1. Evaluate observed whole-stack AH lots (from opts.observedLotsByItemID or live session captures):
  local lotsByItemID = opts.observedLotsByItemID
  if type(lotsByItemID) ~= "table" and ns.State and type(ns.State.sessionObservedAuctionLotsByItemID) == "table" then
    lotsByItemID = ns.State.sessionObservedAuctionLotsByItemID
  end
  if type(lotsByItemID) == "table" then
    local sortedItemIDs = {}
    for rawID in pairs(lotsByItemID) do
      local id = tonumber(rawID)
      if isPositiveInt(id) then
        table.insert(sortedItemIDs, id)
      end
    end
    table.sort(sortedItemIDs)
    for _, id in ipairs(sortedItemIDs) do
      local res = VendorArbitrage.EvaluateVendorSpreadLots({ itemID = id }, lotsByItemID[id] or lotsByItemID[tostring(id)], opts)
      if res.eligible then
        table.insert(directSpreadActions, res)
      elseif res.status == "PENDING_ITEM_CACHE" then
        table.insert(pendingItemCacheIDs, id)
      elseif res.status == "QUARANTINED" and res.quarantine then
        table.insert(quarantinedItems, res.quarantine)
      end
    end
  end

  -- 2. Evaluate Rung-1b Craft-to-Vendor recipes:
  local recipes = (opts.recipes) or (ns.EconomyData and ns.EconomyData.craftToVendorRecipes) or {}
  for _, rec in ipairs(recipes) do
    local cRes = VendorArbitrage.EvaluateCraftToVendorBatch(rec, opts)
    if cRes.eligible then
      table.insert(craftActions, cRes)
    elseif cRes.status == "PENDING_ITEM_CACHE" and cRes.itemID then
      table.insert(pendingItemCacheIDs, cRes.itemID)
    elseif cRes.status == "QUARANTINED" and cRes.quarantine then
      table.insert(quarantinedItems, cRes.quarantine)
    end
  end

  -- 3. Evaluate Auctionator summary discovery candidates (strictly non-executable discovery aids):
  if ns.Providers and ns.Providers.Auctionator and ns.Providers.Auctionator.IsAvailable and ns.Providers.Auctionator.IsAvailable() then
    local econItems = (ns.EconomyData and ns.EconomyData.items) or {}
    local itemIDs = {}
    for id in pairs(econItems) do
      if isPositiveInt(id) and (not lotsByItemID or not lotsByItemID[id]) then
        table.insert(itemIDs, id)
      end
    end
    table.sort(itemIDs)
    for _, id in ipairs(itemIDs) do
      local pInfo = ns.Providers.Auctionator.GetItemPriceInfo and ns.Providers.Auctionator.GetItemPriceInfo(id) or nil
      local dCand = VendorArbitrage.EvaluateAuctionatorDiscoveryCandidate(id, pInfo, opts)
      if dCand then
        table.insert(discoveryCandidates, dCand)
      end
    end
  end

  table.sort(directSpreadActions, function(a, b)
    if a.gphCopper ~= b.gphCopper then
      return a.gphCopper > b.gphCopper
    end
    return a.netVendorProfitCopper > b.netVendorProfitCopper
  end)

  table.sort(craftActions, function(a, b)
    if a.gphCopper ~= b.gphCopper then
      return a.gphCopper > b.gphCopper
    end
    return a.economicSurplusCopper > b.economicSurplusCopper
  end)

  return {
    reserveSnapshot = reserveSnap,
    directSpreadActions = directSpreadActions,
    craftActions = craftActions,
    discoveryCandidates = discoveryCandidates,
    pendingItemCacheIDs = pendingItemCacheIDs,
    quarantinedItems = quarantinedItems,
  }
end

return VendorArbitrage
