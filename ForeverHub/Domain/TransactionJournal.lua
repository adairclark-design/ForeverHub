local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.Domain = ns.Domain or {}

local TransactionJournal = {}
ns.Domain.TransactionJournal = TransactionJournal

TransactionJournal.SCHEMA = "foreverhub-transaction-journal-v1"
TransactionJournal.MAX_JOURNAL_ENTRIES = 200
TransactionJournal.MAX_COST_BASIS_LOTS = 128

TransactionJournal.__merchantSession = {
  state = "IDLE",
  sessionID = 0,
}
TransactionJournal.__mailSession = {
  state = "CLOSED",
  sessionID = 0,
}

local function isPositiveInt(v)
  return type(v) == "number" and v == v and v >= 1 and v < 9007199254740992 and math.floor(v) == v
end

local function isNonNegInt(v)
  return type(v) == "number" and v == v and v >= 0 and v < 9007199254740992 and math.floor(v) == v
end

local function isSignedSafeInt(v)
  return type(v) == "number" and v == v and v > -9007199254740992 and v < 9007199254740992 and math.floor(v) == v
end

local function resolveNowEpoch(explicitEpoch)
  if isPositiveInt(explicitEpoch) then
    return explicitEpoch
  end
  if ns.Compat and type(ns.Compat.GetServerTimeSafe) == "function" then
    local srv = ns.Compat.GetServerTimeSafe()
    local ep = type(srv) == "table" and tonumber(srv.epochSec) or tonumber(srv)
    if isPositiveInt(ep) then
      return ep
    end
  end
  if type(_G.GetServerTime) == "function" then
    local ok, t = pcall(_G.GetServerTime)
    if ok and isPositiveInt(t) then
      return t
    end
  end
  if type(_G.time) == "function" then
    local ok, t = pcall(_G.time)
    if ok and isPositiveInt(t) then
      return t
    end
  end
  return 0
end

function TransactionJournal.EnsureInitialized()
  local store = nil
  if ns.State and type(ns.State.GetCharDB) == "function" then
    local ok, charDB = pcall(ns.State.GetCharDB)
    if ok and type(charDB) == "table" then
      store = charDB
    end
  end
  if not store then
    TransactionJournal.__ephemeralStore = TransactionJournal.__ephemeralStore or {}
    store = TransactionJournal.__ephemeralStore
  end

  if type(store.transactionJournal) ~= "table" or store.transactionJournal.schema ~= TransactionJournal.SCHEMA then
    store.transactionJournal = {
      schema = TransactionJournal.SCHEMA,
      nextSeq = 1,
      entries = {},
      costBasisLots = {},
      compatibleCommissionRules = {
        floor = true,
        half_up = true,
      },
      lastMerchantOutcome = nil,
      lastMailOutcome = nil,
    }
  end
  local tj = store.transactionJournal
  tj.entries = type(tj.entries) == "table" and tj.entries or {}
  tj.costBasisLots = type(tj.costBasisLots) == "table" and tj.costBasisLots or {}
  if type(tj.compatibleCommissionRules) ~= "table" then
    tj.compatibleCommissionRules = { floor = true, half_up = true }
  end
  return tj
end

local function appendJournalEntry(entry)
  local tj = TransactionJournal.EnsureInitialized()
  entry.seq = tj.nextSeq or 1
  tj.nextSeq = entry.seq + 1
  table.insert(tj.entries, entry)
  while #tj.entries > TransactionJournal.MAX_JOURNAL_ENTRIES do
    table.remove(tj.entries, 1)
  end
  return entry
end

-- ============================================================================
-- Verified Lot Cost-Basis Tracker (`MUST_ADD_NOW` + Astra `P0.4`)
-- Never fabricates realized profit when cost basis is unrecorded or ambiguous!
-- ============================================================================

function TransactionJournal.RecordVerifiedAcquisition(acq)
  if type(acq) ~= "table" then
    return false, "invalid_acquisition"
  end
  local itemKey = tostring(acq.itemKey or "")
  local qty = tonumber(acq.quantity)
  local paid = tonumber(acq.totalPaidCopper)
  if itemKey == "" or string.find(itemKey, "^i1:unk_var:") or not isPositiveInt(qty) or not isNonNegInt(paid) then
    return false, "invalid_acquisition_fields"
  end

  local tj = TransactionJournal.EnsureInitialized()
  local lot = {
    lotID = "cb_" .. tostring(tj.nextSeq or 1),
    itemKey = itemKey,
    itemID = tonumber(acq.itemID),
    remainingQuantity = qty,
    initialQuantity = qty,
    totalPaidCopper = paid,
    remainingCostCopper = paid,
    source = tostring(acq.source or "verified_purchase"),
    observedAtEpoch = resolveNowEpoch(acq.observedAtEpoch),
  }
  table.insert(tj.costBasisLots, lot)
  while #tj.costBasisLots > TransactionJournal.MAX_COST_BASIS_LOTS do
    table.remove(tj.costBasisLots, 1)
  end

  appendJournalEntry({
    kind = "ACQUISITION_RECORDED",
    itemKey = itemKey,
    itemID = lot.itemID,
    quantity = qty,
    totalPaidCopper = paid,
    source = lot.source,
    observedAtEpoch = lot.observedAtEpoch,
  })
  return true, lot
end

function TransactionJournal.ConsumeCostBasisForSale(itemKey, quantitySold, opts)
  opts = type(opts) == "table" and opts or {}
  local key = tostring(itemKey or "")
  local qtyNeeded = tonumber(quantitySold)
  if key == "" or not isPositiveInt(qtyNeeded) then
    return {
      costBasisKnown = false,
      totalCostBasisCopper = nil,
      reason = "invalid_sale_key_or_quantity",
    }
  end

  local tj = TransactionJournal.EnsureInitialized()
  local availableUnits = 0
  for _, lot in ipairs(tj.costBasisLots) do
    if lot.itemKey == key and isPositiveInt(lot.remainingQuantity) then
      availableUnits = availableUnits + lot.remainingQuantity
    end
  end

  if availableUnits < qtyNeeded then
    return {
      costBasisKnown = false,
      totalCostBasisCopper = nil,
      availableRecordedUnits = availableUnits,
      reason = (availableUnits == 0) and "no_recorded_cost_basis" or "partial_cost_basis_only",
    }
  end

  local remainingToMatch = qtyNeeded
  local totalCostCopper = 0
  local dryRun = (opts.dryRun == true)

  for _, lot in ipairs(tj.costBasisLots) do
    if remainingToMatch <= 0 then
      break
    end
    if lot.itemKey == key and isPositiveInt(lot.remainingQuantity) then
      local take = math.min(remainingToMatch, lot.remainingQuantity)
      local allocatedCost
      if take == lot.remainingQuantity then
        allocatedCost = lot.remainingCostCopper
      else
        -- Exact integer pro-rata floor allocation; remainder stays on remaining units so copper always sums!
        allocatedCost = math.floor((lot.remainingCostCopper * take) / lot.remainingQuantity)
      end
      totalCostCopper = totalCostCopper + allocatedCost
      remainingToMatch = remainingToMatch - take
      if not dryRun then
        lot.remainingQuantity = lot.remainingQuantity - take
        lot.remainingCostCopper = math.max(0, lot.remainingCostCopper - allocatedCost)
      end
    end
  end

  if not dryRun then
    local kept = {}
    for _, lot in ipairs(tj.costBasisLots) do
      if isPositiveInt(lot.remainingQuantity) then
        table.insert(kept, lot)
      end
    end
    tj.costBasisLots = kept
  end

  return {
    costBasisKnown = true,
    totalCostBasisCopper = totalCostCopper,
    matchedQuantity = qtyNeeded,
  }
end

-- ============================================================================
-- Acquisition-Cost Comparator & Pre-/Post-Action Revalidator (`MUST_ADD_NOW`)
-- ============================================================================

function TransactionJournal.CompareAcquisitionSources(itemID, requiredQuantity, opts)
  opts = type(opts) == "table" and opts or {}
  local id = tonumber(itemID)
  local reqQty = tonumber(requiredQuantity)
  if not isPositiveInt(id) or not isPositiveInt(reqQty) then
    return {
      completeness = "UNKNOWN",
      bestCashSource = nil,
      sources = {},
      reason = "invalid_item_or_quantity",
    }
  end

  local sources = {}
  local hasAnyExecutable = false

  -- 1. Unreserved owned stock:
  local unreservedOwned = math.max(0, math.floor(tonumber(opts.unreservedBagUnits) or 0))
  local unitVendorFloor = tonumber(opts.verifiedUnitVendorCopper)
  if unreservedOwned > 0 then
    local covered = math.min(reqQty, unreservedOwned)
    table.insert(sources, {
      sourceKind = "UNRESERVED_OWNED_STOCK",
      coveredUnits = covered,
      cashOutlayCopper = 0,
      opportunityCostCopper = isNonNegInt(unitVendorFloor) and (covered * unitVendorFloor) or nil,
      completeness = (covered >= reqQty) and "COMPLETE" or "PARTIAL",
    })
    if covered >= reqQty then
      hasAnyExecutable = true
    end
  end

  -- 2. Positively verified merchant offer (`P0.1` gated):
  if type(opts.merchantOffer) == "table" and ns.Domain.ProtectionPolicy then
    local trad = ns.Domain.ProtectionPolicy.EvaluatePositiveMerchantResaleTradability(opts.merchantOffer)
    if trad and trad.eligible == true then
      local bundles = math.ceil(reqQty / trad.bundleQuantity)
      local totalCash = bundles * trad.bundlePriceCopper
      local excess = (bundles * trad.bundleQuantity) - reqQty
      table.insert(sources, {
        sourceKind = "VERIFIED_MERCHANT_OFFER",
        coveredUnits = reqQty,
        cashOutlayCopper = totalCash,
        leftoverUnits = excess,
        completeness = "COMPLETE",
      })
      hasAnyExecutable = true
    end
  end

  -- 3. Retained whole-stack AH lots (`P0.3` RETAINED_OBSERVATION):
  if type(opts.observedLots) == "table" and #opts.observedLots > 0 and ns.Domain.MarketAccounting then
    local nowEpoch = resolveNowEpoch(opts.nowEpoch)
    local maxAge = isPositiveInt(opts.maxLotAgeSeconds) and opts.maxLotAgeSeconds or 900
    local rungs = {}
    for _, l in ipairs(opts.observedLots) do
      local bo = tonumber(l.buyoutCopper or l.buyoutPrice)
      local cnt = tonumber(l.stackSize or l.count)
      local obsAt = tonumber(l.observedAt)
      if isPositiveInt(bo) and isPositiveInt(cnt) and isPositiveInt(obsAt) and (nowEpoch - obsAt) >= 0 and (nowEpoch - obsAt) <= maxAge then
        table.insert(rungs, { stackSize = cnt, stackBuyoutCopper = bo, numStacks = 1 })
      end
    end
    if #rungs > 0 then
      local walk = ns.Domain.MarketAccounting.WalkAskLadderEntryCost(rungs, reqQty, false, nil)
      if walk and walk.status == "ok" and isPositiveInt(walk.entryCostCopper) then
        table.insert(sources, {
          sourceKind = "RETAINED_AH_LOT_OBSERVATION",
          observationStage = "RETAINED_OBSERVATION",
          coveredUnits = reqQty,
          cashOutlayCopper = walk.entryCostCopper,
          leftoverUnits = tonumber(walk.excessUnits) or 0,
          completeness = "COMPLETE",
        })
        hasAnyExecutable = true
      end
    end
  end

  local bestCash = nil
  for _, s in ipairs(sources) do
    if s.completeness == "COMPLETE" then
      if not bestCash or s.cashOutlayCopper < bestCash.cashOutlayCopper then
        bestCash = s
      end
    end
  end

  return {
    itemID = id,
    requiredQuantity = reqQty,
    completeness = hasAnyExecutable and "COMPLETE" or ((#sources > 0) and "PARTIAL" or "UNKNOWN"),
    bestCashSource = bestCash,
    sources = sources,
  }
end

function TransactionJournal.RevalidateActionInputs(expected, current)
  expected = type(expected) == "table" and expected or {}
  current = type(current) == "table" and current or {}
  local reasons = {}

  if current.inCombat == true then
    table.insert(reasons, "in_combat_lockdown")
  end
  if isNonNegInt(expected.requiredOutlayCopper) and isNonNegInt(current.investableCopper) then
    if current.investableCopper < expected.requiredOutlayCopper then
      table.insert(reasons, "insufficient_investable_copper_after_reserves")
    end
  end
  if isNonNegInt(expected.requiredBagSlots) and isNonNegInt(current.freeBagSlots) then
    if current.freeBagSlots < expected.requiredBagSlots then
      table.insert(reasons, "insufficient_free_bag_slots")
    end
  end
  if expected.reservationRevision ~= nil and current.reservationRevision ~= nil then
    if expected.reservationRevision ~= current.reservationRevision then
      table.insert(reasons, "reservation_revision_changed")
    end
  end
  if isPositiveInt(expected.observedAtEpoch) and isPositiveInt(current.nowEpoch) then
    local maxAge = isPositiveInt(expected.maxObservationAgeSeconds) and expected.maxObservationAgeSeconds or 900
    if (current.nowEpoch - expected.observedAtEpoch) > maxAge then
      table.insert(reasons, "observation_expired")
    end
  end

  return {
    valid = (#reasons == 0),
    invalidatedReasons = reasons,
  }
end

-- ============================================================================
-- Merchant Reconciliation State Machine (`Astra P0.4` + `P1.C`)
--   IDLE -> BASELINE_PENDING -> TRACKING -> SETTLING -> RECONCILED | AMBIGUOUS | ABORTED
--   Emits `PROCEEDS_RECONCILED | PROFIT_RECONCILED | AMBIGUOUS` (never fabricated profit!).
-- ============================================================================

local function summarizeBagSnapshotForMerchant(bagSlots)
  local byKey = {}
  local anyLocked = false
  local anyIncomplete = false

  for _, s in ipairs(type(bagSlots) == "table" and bagSlots or {}) do
    if type(s) == "table" and s.hasItem ~= false and isPositiveInt(tonumber(s.itemID)) then
      if s.isLocked == true or s.isPending == true then
        anyLocked = true
      end
      local key = tostring(s.itemKey or ("i1:base:" .. tostring(s.itemID)))
      local qty = math.max(1, math.floor(tonumber(s.stackCount) or 1))
      local unitSell = tonumber(s.unitSellPrice)
      if s.metadataComplete == false or not isNonNegInt(unitSell) then
        anyIncomplete = true
      end
      local cur = byKey[key]
      if not cur then
        cur = {
          itemKey = key,
          itemID = tonumber(s.itemID),
          totalQty = 0,
          unitSellPrice = isNonNegInt(unitSell) and unitSell or nil,
        }
        byKey[key] = cur
      end
      cur.totalQty = cur.totalQty + qty
      if cur.unitSellPrice == nil and isNonNegInt(unitSell) then
        cur.unitSellPrice = unitSell
      elseif cur.unitSellPrice ~= nil and isNonNegInt(unitSell) and cur.unitSellPrice ~= unitSell then
        anyIncomplete = true
      end
    end
  end

  return {
    byKey = byKey,
    anyLocked = anyLocked,
    anyIncomplete = anyIncomplete,
  }
end

function TransactionJournal.BeginMerchantSession(baseline)
  baseline = type(baseline) == "table" and baseline or {}
  local nextID = (TransactionJournal.__merchantSession.sessionID or 0) + 1
  local moneyCopper = tonumber(baseline.moneyCopper)
  local bagSum = summarizeBagSnapshotForMerchant(baseline.bagSlots)

  if not isNonNegInt(moneyCopper) then
    TransactionJournal.__merchantSession = {
      sessionID = nextID,
      state = "AMBIGUOUS",
      ambiguityReason = "baseline_money_unavailable",
      startedAtEpoch = resolveNowEpoch(baseline.nowEpoch),
    }
    return TransactionJournal.__merchantSession
  end

  if bagSum.anyLocked then
    TransactionJournal.__merchantSession = {
      sessionID = nextID,
      state = "BASELINE_PENDING",
      ambiguityReason = "baseline_bag_slot_locked",
      baselineMoneyCopper = moneyCopper,
      startedAtEpoch = resolveNowEpoch(baseline.nowEpoch),
    }
    return TransactionJournal.__merchantSession
  end

  TransactionJournal.__merchantSession = {
    sessionID = nextID,
    state = "TRACKING",
    startedAtEpoch = resolveNowEpoch(baseline.nowEpoch),
    baselineMoneyCopper = moneyCopper,
    baselineBags = bagSum,
    playerRepairCopper = 0,
    guildRepairCopper = 0,
    recordedPurchasesCopper = 0,
    recordedBuybacksCopper = 0,
    purchasedUnitsByKey = {},
    buybackUnitsByKey = {},
    externalContaminationReason = nil,
  }
  return TransactionJournal.__merchantSession
end

function TransactionJournal.RecordMerchantRepair(costCopper, usedGuildBank)
  local sess = TransactionJournal.__merchantSession
  if not sess or sess.state ~= "TRACKING" then
    return false
  end
  local cost = tonumber(costCopper)
  if not isNonNegInt(cost) then
    sess.state = "AMBIGUOUS"
    sess.ambiguityReason = "invalid_repair_cost"
    return false
  end
  if usedGuildBank == true then
    sess.guildRepairCopper = (sess.guildRepairCopper or 0) + cost
  else
    sess.playerRepairCopper = (sess.playerRepairCopper or 0) + cost
  end
  return true
end

function TransactionJournal.RecordMerchantPurchaseIntent(itemKey, quantity, costCopper, isBuyback)
  local sess = TransactionJournal.__merchantSession
  if not sess or sess.state ~= "TRACKING" then
    return false
  end
  local key = tostring(itemKey or "")
  local qty = tonumber(quantity)
  local cost = tonumber(costCopper)
  if key == "" or not isPositiveInt(qty) or not isNonNegInt(cost) then
    sess.state = "AMBIGUOUS"
    sess.ambiguityReason = "invalid_purchase_or_buyback_intent"
    return false
  end
  if isBuyback == true then
    sess.recordedBuybacksCopper = (sess.recordedBuybacksCopper or 0) + cost
    sess.buybackUnitsByKey[key] = (sess.buybackUnitsByKey[key] or 0) + qty
  else
    sess.recordedPurchasesCopper = (sess.recordedPurchasesCopper or 0) + cost
    sess.purchasedUnitsByKey[key] = (sess.purchasedUnitsByKey[key] or 0) + qty
  end
  return true
end

function TransactionJournal.MarkMerchantExternalContamination(reason)
  local sess = TransactionJournal.__merchantSession
  if not sess or sess.state == "IDLE" then
    return
  end
  sess.state = "AMBIGUOUS"
  sess.externalContaminationReason = tostring(reason or "external_money_event")
  sess.ambiguityReason = sess.externalContaminationReason
end

function TransactionJournal.FinalizeMerchantSession(endSnapshot)
  endSnapshot = type(endSnapshot) == "table" and endSnapshot or {}
  local sess = TransactionJournal.__merchantSession
  local nowEpoch = resolveNowEpoch(endSnapshot.nowEpoch)
  local tj = TransactionJournal.EnsureInitialized()

  if not sess or sess.state == "IDLE" then
    return { status = "ABORTED", reason = "no_active_merchant_session" }
  end

  local function emitAmbiguous(reason)
    sess.state = "AMBIGUOUS"
    local out = {
      sessionID = sess.sessionID,
      state = "AMBIGUOUS",
      status = "AMBIGUOUS",
      headlineLabel = "Merchant session ambiguous — profit not attributed",
      reason = tostring(reason or sess.ambiguityReason or "unattributable_merchant_delta"),
      observedAtEpoch = nowEpoch,
    }
    tj.lastMerchantOutcome = out
    appendJournalEntry({
      kind = "MERCHANT_SESSION_AMBIGUOUS",
      reason = out.reason,
      observedAtEpoch = nowEpoch,
    })
    sess.state = "IDLE"
    return out
  end

  if sess.state ~= "TRACKING" then
    return emitAmbiguous(sess.ambiguityReason or "session_not_tracking")
  end
  if sess.externalContaminationReason ~= nil then
    return emitAmbiguous(sess.externalContaminationReason)
  end

  sess.state = "SETTLING"
  local endMoney = tonumber(endSnapshot.moneyCopper)
  if not isNonNegInt(endMoney) then
    return emitAmbiguous("end_money_unavailable")
  end

  local endBags = summarizeBagSnapshotForMerchant(endSnapshot.bagSlots)
  if endBags.anyLocked then
    return emitAmbiguous("end_bag_slot_locked_unsettled")
  end

  local allKeys = {}
  local seenKeys = {}
  for k in pairs(sess.baselineBags.byKey) do
    seenKeys[k] = true
    table.insert(allKeys, k)
  end
  for k in pairs(endBags.byKey) do
    if not seenKeys[k] then
      seenKeys[k] = true
      table.insert(allKeys, k)
    end
  end
  table.sort(allKeys)

  local grossSalesCopper = 0
  local soldLines = {}
  local appearedUnexplained = false

  for _, key in ipairs(allKeys) do
    local beforeRec = sess.baselineBags.byKey[key]
    local afterRec = endBags.byKey[key]
    local beforeQty = beforeRec and beforeRec.totalQty or 0
    local afterQty = afterRec and afterRec.totalQty or 0
    local purchasedUnits = (sess.purchasedUnitsByKey[key] or 0) + (sess.buybackUnitsByKey[key] or 0)

    -- Net units sold after accounting for explicit purchases/buybacks of that same itemKey:
    local expectedAfterWithoutSales = beforeQty + purchasedUnits
    if afterQty > expectedAfterWithoutSales then
      appearedUnexplained = true
      break
    elseif afterQty < expectedAfterWithoutSales then
      local soldQty = expectedAfterWithoutSales - afterQty
      -- Mixed buy + sell of the exact same itemKey in one session without exact receipt separation is ambiguous!
      if purchasedUnits > 0 then
        return emitAmbiguous("mixed_same_item_buy_sell_or_buyback")
      end
      local unitSell = (beforeRec and beforeRec.unitSellPrice) or (afterRec and afterRec.unitSellPrice)
      if not isPositiveInt(unitSell) then
        return emitAmbiguous("sold_item_missing_verified_sell_price")
      end
      local lineGross = soldQty * unitSell
      grossSalesCopper = grossSalesCopper + lineGross
      table.insert(soldLines, {
        itemKey = key,
        itemID = beforeRec and beforeRec.itemID or (afterRec and afterRec.itemID),
        quantity = soldQty,
        unitSellPrice = unitSell,
        grossCopper = lineGross,
      })
    end
  end

  if appearedUnexplained then
    return emitAmbiguous("untracked_items_appeared_during_merchant_session")
  end

  local actualDeltaCopper = endMoney - sess.baselineMoneyCopper
  local expectedDeltaCopper = grossSalesCopper
    - (sess.recordedPurchasesCopper or 0)
    - (sess.playerRepairCopper or 0)
    - (sess.recordedBuybacksCopper or 0)

  if actualDeltaCopper ~= expectedDeltaCopper then
    return emitAmbiguous(
      string.format("cash_delta_mismatch_actual_%d_vs_expected_%d", actualDeltaCopper, expectedDeltaCopper)
    )
  end

  -- Determine whether ALL sold lines have complete verified cost basis (`PROFIT_RECONCILED`) or only proceeds (`PROCEEDS_RECONCILED`):
  local allCostBasisKnown = (#soldLines > 0)
  local totalCostBasisCopper = 0
  for _, line in ipairs(soldLines) do
    local dry = TransactionJournal.ConsumeCostBasisForSale(line.itemKey, line.quantity, { dryRun = true })
    if not dry.costBasisKnown then
      allCostBasisKnown = false
      break
    end
    totalCostBasisCopper = totalCostBasisCopper + (dry.totalCostBasisCopper or 0)
  end

  local outcomeStatus = "PROCEEDS_RECONCILED"
  local headlineLabel = "Vendor proceeds"
  local realizedProfitCopper = nil

  if allCostBasisKnown then
    totalCostBasisCopper = 0
    for _, line in ipairs(soldLines) do
      local consumed = TransactionJournal.ConsumeCostBasisForSale(line.itemKey, line.quantity, { dryRun = false })
      totalCostBasisCopper = totalCostBasisCopper + (consumed.totalCostBasisCopper or 0)
    end
    outcomeStatus = "PROFIT_RECONCILED"
    headlineLabel = "Realized vendor profit"
    realizedProfitCopper = grossSalesCopper - totalCostBasisCopper
  end

  local out = {
    sessionID = sess.sessionID,
    state = "RECONCILED",
    status = outcomeStatus,
    headlineLabel = headlineLabel,
    vendorProceedsCopper = grossSalesCopper,
    actualVendorGrossCopper = grossSalesCopper,
    actualBuyoutPaidCopper = allCostBasisKnown and totalCostBasisCopper or nil,
    actualIncrementalCostCopper = 0,
    realizedProfitCopper = realizedProfitCopper,
    playerRepairCopper = sess.playerRepairCopper or 0,
    guildRepairCopper = sess.guildRepairCopper or 0,
    purchasesCopper = sess.recordedPurchasesCopper or 0,
    buybacksCopper = sess.recordedBuybacksCopper or 0,
    netPurseDeltaCopper = actualDeltaCopper,
    soldLines = soldLines,
    observedAtEpoch = nowEpoch,
  }

  tj.lastMerchantOutcome = out
  if ns.State then
    if outcomeStatus == "PROFIT_RECONCILED" then
      ns.State.lastReconciledVendorProfit = {
        status = "REALIZED_RECONCILED",
        actualVendorGrossCopper = grossSalesCopper,
        actualBuyoutPaidCopper = totalCostBasisCopper,
        actualIncrementalCostCopper = 0,
        realizedProfitCopper = realizedProfitCopper,
        observedAtEpoch = nowEpoch,
      }
    end
    ns.State.lastReconciledMerchantSession = out
  end

  appendJournalEntry({
    kind = outcomeStatus,
    vendorProceedsCopper = grossSalesCopper,
    realizedProfitCopper = realizedProfitCopper,
    netPurseDeltaCopper = actualDeltaCopper,
    observedAtEpoch = nowEpoch,
  })
  sess.state = "IDLE"
  return out
end

-- ============================================================================
-- Mail Reconciliation State Machine (`Astra P0.2` + `P1.D`)
--   MAIL_OPEN -> HEADERS_PENDING -> INVOICES_PENDING -> SNAPSHOT_READY ->
--   INVOICE_OBSERVED -> CASH_COLLECTION_RECONCILED
--   - Separates `seller`, `seller_temp_invoice`, and `buyer`
--   - Tracks snapshot multiplicities for identical auctions
--   - Retains `compatibleCommissionRules = { floor = ..., half_up = ... }` narrowed only by discriminating gross sales!
--   - Never treats refunded deposit as a deducted expense (`net = bid + deposit - consignment`)!
-- ============================================================================

local function buildInvoiceMultiplicitySignature(row)
  return string.format(
    "%s|%s|%d|%d|%d|%d|%d",
    tostring(row.invoiceType or "none"),
    tostring(row.itemKey or row.itemName or "?"),
    tonumber(row.bid) or 0,
    tonumber(row.buyout) or 0,
    tonumber(row.deposit) or 0,
    tonumber(row.consignment) or 0,
    tonumber(row.headerMoney) or 0
  )
end

function TransactionJournal.UpdateCommissionRuleCompatibility(bidCopper, consignmentCopper, commissionBps)
  local tj = TransactionJournal.EnsureInitialized()
  local bid = tonumber(bidCopper)
  local cons = tonumber(consignmentCopper)
  local bps = tonumber(commissionBps) or 500
  if not isPositiveInt(bid) or not isNonNegInt(cons) then
    return tj.compatibleCommissionRules
  end

  local floorExpected = math.floor((bid * bps) / 10000)
  local halfUpExpected = math.floor((bid * bps + 5000) / 10000)

  if cons ~= floorExpected then
    tj.compatibleCommissionRules.floor = false
  end
  if cons ~= halfUpExpected then
    tj.compatibleCommissionRules.half_up = false
  end
  return tj.compatibleCommissionRules
end

function TransactionJournal.CaptureInboxSnapshot(inboxRows, opts)
  opts = type(opts) == "table" and opts or {}
  local rows = type(inboxRows) == "table" and inboxRows or {}
  local nowEpoch = resolveNowEpoch(opts.nowEpoch)
  local nextID = (TransactionJournal.__mailSession.sessionID or 0) + 1

  local headersPending = false
  local invoicesPending = false
  local multiplicityBySig = {}
  local sellerReadyInvoices = {}
  local sellerPendingTempInvoices = {}
  local buyerInvoices = {}

  for idx, r in ipairs(rows) do
    if type(r) ~= "table" or r.headerLoaded == false then
      headersPending = true
    else
      local invType = r.invoiceType
      if r.isAuctionMail == true and (invType == nil or invType == "" or r.invoiceFieldsComplete == false) then
        invoicesPending = true
      elseif invType == "seller" or invType == "seller_temp_invoice" or invType == "buyer" then
        if r.invoiceFieldsComplete == false then
          invoicesPending = true
        else
        local bid = tonumber(r.bid) or 0
        local buyout = tonumber(r.buyout) or 0
        local deposit = tonumber(r.deposit) or 0
        local consignment = tonumber(r.consignment) or 0
        local headerMoney = tonumber(r.money) or 0

        local sig = buildInvoiceMultiplicitySignature({
          invoiceType = invType,
          itemKey = r.itemKey,
          itemName = r.itemName,
          bid = bid,
          buyout = buyout,
          deposit = deposit,
          consignment = consignment,
          headerMoney = headerMoney,
        })
        multiplicityBySig[sig] = (multiplicityBySig[sig] or 0) + 1

        local cleanRow = {
          mailIndex = idx,
          signature = sig,
          invoiceType = invType,
          itemKey = (type(r.itemKey) == "string" and not string.find(r.itemKey, "^i1:unk_var:")) and r.itemKey or nil,
          itemName = tostring(r.itemName or ""),
          quantity = math.max(1, math.floor(tonumber(r.quantity) or 1)),
          bid = bid,
          buyout = buyout,
          depositRefundCopper = deposit,
          consignmentCommissionCopper = consignment,
          -- Astra P0.2: Successful sale net proceeds EXCLUDE refunded deposit principal (`proceeds = G - commission`)
          saleProceedsExclDepositRefundCopper = (invType == "seller" or invType == "seller_temp_invoice")
              and math.max(0, bid - consignment)
            or nil,
          expectedHeaderCashCopper = (invType == "seller") and math.max(0, bid + deposit - consignment) or headerMoney,
          headerMoneyCopper = headerMoney,
        }

        if invType == "seller" then
          TransactionJournal.UpdateCommissionRuleCompatibility(bid, consignment, opts.commissionBps or 500)
          table.insert(sellerReadyInvoices, cleanRow)
        elseif invType == "seller_temp_invoice" then
          TransactionJournal.UpdateCommissionRuleCompatibility(bid, consignment, opts.commissionBps or 500)
          table.insert(sellerPendingTempInvoices, cleanRow)
        elseif invType == "buyer" then
          table.insert(buyerInvoices, cleanRow)
        end
        end
      end
    end
  end

  local state = "SNAPSHOT_READY"
  if headersPending then
    state = "HEADERS_PENDING"
  elseif invoicesPending then
    state = "INVOICES_PENDING"
  elseif #sellerReadyInvoices > 0 or #sellerPendingTempInvoices > 0 or #buyerInvoices > 0 then
    state = "INVOICE_OBSERVED"
  end

  local tj = TransactionJournal.EnsureInitialized()
  TransactionJournal.__mailSession = {
    sessionID = nextID,
    state = state,
    observedAtEpoch = nowEpoch,
    baselineMoneyCopper = isNonNegInt(tonumber(opts.moneyCopper)) and tonumber(opts.moneyCopper) or nil,
    multiplicityBySig = multiplicityBySig,
    sellerReadyInvoices = sellerReadyInvoices,
    sellerPendingTempInvoices = sellerPendingTempInvoices,
    buyerInvoices = buyerInvoices,
    compatibleCommissionRules = {
      floor = tj.compatibleCommissionRules.floor == true,
      half_up = tj.compatibleCommissionRules.half_up == true,
    },
  }
  return TransactionJournal.__mailSession
end

function TransactionJournal.ReconcileMailCashCollection(afterInboxRows, afterMoneyCopper, opts)
  opts = type(opts) == "table" and opts or {}
  local before = TransactionJournal.__mailSession
  if not before or (before.state ~= "INVOICE_OBSERVED" and before.state ~= "SNAPSHOT_READY") then
    return {
      status = "MAIL_SNAPSHOT_INCOMPLETE",
      reason = "baseline_inbox_not_ready",
    }
  end
  if not isNonNegInt(before.baselineMoneyCopper) or not isNonNegInt(tonumber(afterMoneyCopper)) then
    return {
      status = "AMBIGUOUS",
      reason = "mail_money_unavailable",
    }
  end

  local afterMult = {}
  for _, r in ipairs(type(afterInboxRows) == "table" and afterInboxRows or {}) do
    if type(r) == "table" and r.headerLoaded ~= false and (r.invoiceType == "seller" or r.invoiceType == "seller_temp_invoice" or r.invoiceType == "buyer") then
      local sig = buildInvoiceMultiplicitySignature({
        invoiceType = r.invoiceType,
        itemKey = r.itemKey,
        itemName = r.itemName,
        bid = tonumber(r.bid) or 0,
        buyout = tonumber(r.buyout) or 0,
        deposit = tonumber(r.deposit) or 0,
        consignment = tonumber(r.consignment) or 0,
        headerMoney = tonumber(r.money) or 0,
      })
      afterMult[sig] = (afterMult[sig] or 0) + 1
    end
  end

  local collectedInvoices = {}
  local expectedCashCollected = 0
  local totalSaleProceedsExclDeposit = 0
  local totalRefundedDeposits = 0
  local identicalMultiplicityAmbiguity = false

  local consumedBySig = {}
  for sig, beforeCnt in pairs(before.multiplicityBySig or {}) do
    local afterCnt = afterMult[sig] or 0
    if afterCnt < beforeCnt then
      consumedBySig[sig] = beforeCnt - afterCnt
      -- Partial collection across >1 identical invoices without unique lot IDs marks per-lot attribution ambiguous while total cash remains exact:
      if beforeCnt > 1 and afterCnt > 0 then
        identicalMultiplicityAmbiguity = true
      end
    end
  end

  local takenSoFar = {}
  for _, inv in ipairs(before.sellerReadyInvoices or {}) do
    local need = consumedBySig[inv.signature] or 0
    local used = takenSoFar[inv.signature] or 0
    if used < need then
      takenSoFar[inv.signature] = used + 1
      expectedCashCollected = expectedCashCollected + inv.headerMoneyCopper
      totalSaleProceedsExclDeposit = totalSaleProceedsExclDeposit + (inv.saleProceedsExclDepositRefundCopper or 0)
      totalRefundedDeposits = totalRefundedDeposits + (inv.depositRefundCopper or 0)
      table.insert(collectedInvoices, inv)
    end
  end

  -- Also record any collected buyer auction deliveries into verified cost-basis lots when itemKey is canonical!
  local buyerLotsRecorded = 0
  for _, bInv in ipairs(before.buyerInvoices or {}) do
    local need = consumedBySig[bInv.signature] or 0
    local used = takenSoFar[bInv.signature] or 0
    if used < need then
      takenSoFar[bInv.signature] = used + 1
      if bInv.itemKey and isPositiveInt(bInv.bid) then
        local okAcq = TransactionJournal.RecordVerifiedAcquisition({
          itemKey = bInv.itemKey,
          quantity = bInv.quantity,
          totalPaidCopper = bInv.bid,
          source = "ah_buyer_invoice",
          observedAtEpoch = resolveNowEpoch(opts.nowEpoch),
        })
        if okAcq then
          buyerLotsRecorded = buyerLotsRecorded + 1
        end
      end
    end
  end

  local actualMoneyDelta = tonumber(afterMoneyCopper) - before.baselineMoneyCopper
  local tj = TransactionJournal.EnsureInitialized()

  if isSignedSafeInt(actualMoneyDelta) and actualMoneyDelta == expectedCashCollected and (#collectedInvoices > 0 or buyerLotsRecorded > 0) then
    before.state = "CASH_COLLECTION_RECONCILED"
    local out = {
      status = "CASH_COLLECTION_RECONCILED",
      collectedSellerInvoiceCount = #collectedInvoices,
      buyerLotsRecordedCount = buyerLotsRecorded,
      cashCollectedCopper = actualMoneyDelta,
      saleProceedsExclDepositRefundCopper = totalSaleProceedsExclDeposit,
      refundedDepositPrincipalCopper = totalRefundedDeposits,
      lotAttributionAmbiguous = identicalMultiplicityAmbiguity,
      compatibleCommissionRules = {
        floor = tj.compatibleCommissionRules.floor == true,
        half_up = tj.compatibleCommissionRules.half_up == true,
      },
      observedAtEpoch = resolveNowEpoch(opts.nowEpoch),
    }
    tj.lastMailOutcome = out
    appendJournalEntry({
      kind = "MAIL_CASH_COLLECTION_RECONCILED",
      cashCollectedCopper = actualMoneyDelta,
      saleProceedsExclDepositRefundCopper = totalSaleProceedsExclDeposit,
      refundedDepositPrincipalCopper = totalRefundedDeposits,
      buyerLotsRecordedCount = buyerLotsRecorded,
      observedAtEpoch = out.observedAtEpoch,
    })
    return out
  end

  return {
    status = "AMBIGUOUS",
    reason = string.format("mail_cash_delta_%d_vs_expected_%d", actualMoneyDelta, expectedCashCollected),
    compatibleCommissionRules = {
      floor = tj.compatibleCommissionRules.floor == true,
      half_up = tj.compatibleCommissionRules.half_up == true,
    },
  }
end

return TransactionJournal
