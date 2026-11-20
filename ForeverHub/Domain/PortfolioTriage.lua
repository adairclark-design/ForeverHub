local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.Domain = ns.Domain or {}

local PortfolioTriage = {}
ns.Domain.PortfolioTriage = PortfolioTriage

PortfolioTriage.SCHEMA_VERSION = 1
PortfolioTriage.STAGE1_MAX_CEILING_COPPER = 126750 -- 12g 67s 50c (30 Dreamfoil @ 14s50c + 30 Silversage @ 12s75c + 15 Plaguebloom @ 30s)
PortfolioTriage.DEC9_2026_RAID_UNLOCK_EPOCH = 1796832000 -- 2026-12-09T16:00:00Z

PortfolioTriage.PROTECTED_ITEM_IDS = {
  [6893] = "Workshop Key",
  [6948] = "Hearthstone",
  [7005] = "Skinning Knife",
  [7146] = "The Scarlet Key",
  [8705] = "OOX-22/FE Distress Beacon",
  [9240] = "Mallet of Zul'Farrak",
  [10022] = "Proof of Deed",
  [11122] = "Carrot on a Stick",
  [11445] = "Flute of the Ancients",
  [11955] = "Bag of Empty Ooze Containers",
  [12891] = "Jaron's Pick",
  [15788] = "Everlook Report",
  [15790] = "Studies in Spirit Speaking",
  [17191] = "Scepter of Celebras",
  [19141] = "Luffa",
  [211527] = "Cozy Sleeping Bag",
  [257808] = "Parcel of Mail",
  [262802] = "Moonveil Moss",
  [263028] = "Enchanted Harpy Amulet",
  [267089] = "Krol'dok Compound Key",
  [271879] = "Eye of Endless Influence",
  [272925] = "Ketharas' Note",
  [273799] = "Thomas's Ring",
  [274795] = "Embroidered Scabbard",
  [277507] = "Dalaran Sewer Key",
}

PortfolioTriage.MANUAL_REVIEW_GEAR_IDS = {
  [10104] = "Councillor's Tunic",
  [11978] = "Jasper Link",
  [13093] = "Blush Ember Ring",
  [14457] = "Elunarian Cuffs",
  [20641] = "Southsea Mojo Boots",
  [274641] = "Theka's Last Breath",
  [275347] = "Lichbane",
}

PortfolioTriage.LOCKBOX_ITEM_IDS = {
  [4636] = "Strong Iron Lockbox",
  [4637] = "Steel Lockbox",
  [4638] = "Reinforced Steel Lockbox",
  [5758] = "Mithril Lockbox",
  [5759] = "Thorium Lockbox",
}

PortfolioTriage.CAPTURE_VERIFIED_AH_CRATE_IDS = {
  [248695] = true, -- Waylaid Crate: Earthly Artisan Herbs (observed on Econa's active AH listings)
  [248699] = true, -- Waylaid Crate: Artisan Curiosities (observed on Econa's active AH listings)
}

PortfolioTriage.STAGE1_PROBE_SPECS = {
  {
    itemID = 13463,
    name = "Dreamfoil",
    maxUnits = 30,
    maxUnitPriceCopper = 1450,
    ceilingCopper = 43500,
  },
  {
    itemID = 13465,
    name = "Mountain Silversage",
    maxUnits = 30,
    maxUnitPriceCopper = 1275,
    ceilingCopper = 38250,
  },
  {
    itemID = 13466,
    name = "Plaguebloom",
    maxUnits = 15,
    maxUnitPriceCopper = 3000,
    ceilingCopper = 45000,
  },
}

local function isPositiveInt(v)
  return type(v) == "number" and v == v and v >= 1 and v < 9007199254740992 and math.floor(v) == v
end

-- Reconciles dated, deduplicated own-sale invoices (`mailLedger` entries with `kind == "sold"`)
-- against test purchases. Rejects `heardSales` notifications (which lack quantity and proceeds).
function PortfolioTriage.ReconcileStage1SaleInvoices(opts)
  opts = type(opts) == "table" and opts or {}
  local guid = tostring(opts.characterGUID or "")
  local purchasesByItemID = type(opts.testPurchasesByItemID) == "table" and opts.testPurchasesByItemID or {}
  local mailEntries = type(opts.mailLedgerEntries) == "table" and opts.mailLedgerEntries or {}
  local heardSales = type(opts.heardSalesEntries) == "table" and opts.heardSalesEntries or {}
  local failedDepositByItemID = type(opts.failedListingDepositCopperByItemID) == "table" and opts.failedListingDepositCopperByItemID or {}

  local seenInvoiceKeys = {}
  local matchedByItemID = {}
  local unmatchedHeardSalesCount = #heardSales

  for _, entry in ipairs(mailEntries) do
    if type(entry) == "table" and tostring(entry.kind or "") == "sold" and tostring(entry.who or "") == guid then
      local id = tonumber(entry.itemID)
      local ts = tonumber(entry.t)
      local gross = tonumber(entry.gross)
      local net = tonumber(entry.net)
      local cut = tonumber(entry.cut) or 0
      local qty = tonumber(entry.quantity or entry.count) or 1
      local purchase = id and purchasesByItemID[id] or nil
      local purchaseAt = type(purchase) == "table" and tonumber(purchase.purchasedAt) or nil
      local unitCost = type(purchase) == "table" and tonumber(purchase.unitCostCopper) or nil

      if isPositiveInt(id) and isPositiveInt(ts) and isPositiveInt(gross) and isPositiveInt(net) and isPositiveInt(qty) then
        if purchaseAt and ts >= purchaseAt and unitCost and unitCost > 0 then
          local dedupKey = string.format("%s:%d:%d:%d:%d", guid, id, ts, gross, net)
          if not seenInvoiceKeys[dedupKey] then
            seenInvoiceKeys[dedupKey] = true
            local rec = matchedByItemID[id]
            if not rec then
              rec = {
                itemID = id,
                soldUnits = 0,
                grossProceedsCopper = 0,
                netProceedsCopper = 0,
                ahCutCopper = 0,
                acquisitionCostCopper = 0,
                invoiceCount = 0,
              }
              matchedByItemID[id] = rec
            end
            rec.soldUnits = rec.soldUnits + math.floor(qty)
            rec.grossProceedsCopper = rec.grossProceedsCopper + math.floor(gross)
            rec.netProceedsCopper = rec.netProceedsCopper + math.floor(net)
            rec.ahCutCopper = rec.ahCutCopper + math.floor(cut)
            rec.acquisitionCostCopper = rec.acquisitionCostCopper + (math.floor(qty) * math.floor(unitCost))
            rec.invoiceCount = rec.invoiceCount + 1
          end
        end
      end
    end
  end

  local verifiedProfitableItems = 0
  for id, rec in pairs(matchedByItemID) do
    local failedDep = math.max(0, math.floor(tonumber(failedDepositByItemID[id]) or 0))
    rec.failedListingDepositCopper = failedDep
    rec.realizedNetProfitCopper = rec.netProceedsCopper - rec.acquisitionCostCopper - failedDep
    rec.stage2UnlockedForItem = (rec.realizedNetProfitCopper > 0)
    if rec.stage2UnlockedForItem then
      verifiedProfitableItems = verifiedProfitableItems + 1
    end
  end

  return {
    stage2Unlocked = (verifiedProfitableItems > 0),
    verifiedProfitableItemCount = verifiedProfitableItems,
    matchedByItemID = matchedByItemID,
    unmatchedHeardSalesIgnoredCount = unmatchedHeardSalesCount,
    heardSalesIgnoredReason = "heardSales notifications lack quantity and net proceeds and never authorize Stage 2 scaling.",
  }
end

function PortfolioTriage.EvaluateCharacterPortfolioTriage(opts)
  opts = type(opts) == "table" and opts or {}
  local PA = ns.Domain and ns.Domain.ProfessionAdvisor
  local SGR = ns.Domain and ns.Domain.SupplyGlutResearch

  local nowEpoch = tonumber(opts.nowEpoch) or 1795152527
  local investableCopper = math.max(0, math.floor(tonumber(opts.investableCopper) or 2201096))
  local outstandingCommitmentsCopper = math.max(0, math.floor(tonumber(opts.outstandingCommitmentsCopper) or 0))
  local availableAfterCommitments = math.max(0, investableCopper - outstandingCommitmentsCopper)
  local stage1BudgetCapCopper = math.min(PortfolioTriage.STAGE1_MAX_CEILING_COPPER, availableAfterCommitments)

  local spendableByItemID = type(opts.spendableByItemID) == "table" and opts.spendableByItemID or {}
  local matchedBasisByItemID = type(opts.matchedCostBasisByItemID) == "table" and opts.matchedCostBasisByItemID or {}
  local activeAuctionsByItemID = type(opts.activeAuctionUnitsByItemID) == "table" and opts.activeAuctionUnitsByItemID or {}
  local expiredAuctionListings = type(opts.expiredAuctionListings) == "table" and opts.expiredAuctionListings or {}
  local mailInTransitByItemID = type(opts.mailInTransitByItemID) == "table" and opts.mailInTransitByItemID or {}

  -- 1. Tailoring 175 -> 185 opening tranche & Mooncloth schedule:
  local boltsOwned = (spendableByItemID[4339] and spendableByItemID[4339].spendableCount) or tonumber(opts.ownedBoltOfMageweaveCount) or 55
  local clothOwned = (spendableByItemID[4338] and spendableByItemID[4338].spendableCount) or tonumber(opts.ownedMageweaveClothCount) or 54
  local runeclothOwned = (spendableByItemID[14047] and spendableByItemID[14047].spendableCount) or tonumber(opts.ownedRuneclothCount) or 106
  local felclothOwned = (spendableByItemID[14256] and spendableByItemID[14256].spendableCount) or tonumber(opts.ownedFelclothCount) or 6
  local patternOwned = ((spendableByItemID[14526] and spendableByItemID[14526].spendableCount or 0) > 0) or (opts.ownsMoonclothPattern ~= false)

  local openingTranche = PA and PA.EvaluateForeverTailoringOpeningTranche and PA.EvaluateForeverTailoringOpeningTranche({
    currentSkill = opts.currentTailoringSkill or 175,
    orangeCutoffSkill = 185,
    ownedBoltOfMageweaveCount = boltsOwned,
    ownedMageweaveClothCount = clothOwned,
    ownedRuneclothCount = runeclothOwned,
    ownedFelclothCount = felclothOwned,
    ownsMoonclothPattern = patternOwned,
  }) or nil

  local moonclothSchedule = PA and PA.EvaluateMoonclothCastSchedule and PA.EvaluateMoonclothCastSchedule({
    raidCutoffEpoch = opts.raidCutoffEpoch or PortfolioTriage.DEC9_2026_RAID_UNLOCK_EPOCH,
    firstEligibleCastEpoch = opts.firstEligibleMoonclothCastEpoch,
    ownedFelclothCount = felclothOwned,
    firstMoonclothSaleVerified = (opts.firstMoonclothSaleVerified == true),
  }) or nil

  -- 2. Specific Banked Holdings Triage (Astra P1 Table):
  local mossCount = (spendableByItemID[1206] and spendableByItemID[1206].spendableCount) or 47
  local mossGrossCopper = (mossCount >= 1) and (850 + math.max(0, mossCount - 1) * 887) or 0
  local mossVendorCopper = mossCount * 400

  local giantCount = (spendableByItemID[6662] and spendableByItemID[6662].spendableCount) or 33
  local giantBasisRec = matchedBasisByItemID[6662]
  local giantUnitBasis = (giantBasisRec and tonumber(giantBasisRec.averageUnitPaidCopper)) or 778
  local giantSavedAskUnit = tonumber(opts.giantGrowthAskCopper) or 778
  local giantGrossCopper = giantCount * giantSavedAskUnit
  local giantNetAfterCutCopper = math.floor((giantGrossCopper * 0.95) + 0.5)
  local giantLotBasisCopper = giantCount * giantUnitBasis
  local giantNetVsBasisCopper = giantNetAfterCutCopper - giantLotBasisCopper

  local swiftCount = (spendableByItemID[2459] and spendableByItemID[2459].spendableCount) or 32
  local swiftSavedAskUnit = tonumber(opts.swiftnessAskCopper) or 1294
  local swiftGrossCopper = swiftCount * swiftSavedAskUnit
  local swiftVendorCopper = swiftCount * 25

  local holdingsTriage = {
    mossAgate = {
      itemID = 1206,
      name = "Moss Agate",
      quantity = mossCount,
      disposition = "RESCAN_AND_TEST_5_TO_10",
      testLotMinUnits = 5,
      testLotMaxUnits = 10,
      impliedGrossLotCopper = mossGrossCopper,
      verifiedVendorLotCopper = mossVendorCopper,
    },
    elixirOfGiantGrowth = {
      itemID = 6662,
      name = "Elixir of Giant Growth",
      quantity = giantCount,
      disposition = "RESERVE_USEFUL_TEST_SURPLUS_LOSS_AFTER_CUT_WARNING",
      matchedUnitBasisCopper = giantUnitBasis,
      savedUnitAskCopper = giantSavedAskUnit,
      impliedGrossLotCopper = giantGrossCopper,
      impliedNetAfterCutCopper = giantNetAfterCutCopper,
      matchedLotBasisCopper = giantLotBasisCopper,
      netAfterCutMinusBasisCopper = giantNetVsBasisCopper,
      lossAfterCutIfBasisApplies = (giantNetVsBasisCopper < 0),
    },
    swiftnessPotion = {
      itemID = 2459,
      name = "Swiftness Potion",
      quantity = swiftCount,
      disposition = "RESERVE_USEFUL_TEST_SURPLUS",
      savedUnitAskCopper = swiftSavedAskUnit,
      impliedGrossLotCopper = swiftGrossCopper,
      verifiedVendorLotCopper = swiftVendorCopper,
    },
  }

  -- 3. Protected items, manual-review gear (with 7-day ahPaid matching), and lockboxes:
  local protectedItems = {}
  for id, label in pairs(PortfolioTriage.PROTECTED_ITEM_IDS) do
    local qty = spendableByItemID[id] and spendableByItemID[id].spendableCount or 0
    if qty > 0 then
      table.insert(protectedItems, {
        itemID = id,
        name = label,
        quantity = qty,
        disposition = "PROTECTED_NEVER_SELL",
      })
    end
  end
  table.sort(protectedItems, function(a, b) return a.itemID < b.itemID end)

  local manualReviewGear = {}
  for id, label in pairs(PortfolioTriage.MANUAL_REVIEW_GEAR_IDS) do
    local qty = (spendableByItemID[id] and spendableByItemID[id].spendableCount) or 1
    local bRec = matchedBasisByItemID[id]
    table.insert(manualReviewGear, {
      itemID = id,
      name = label,
      quantity = qty,
      disposition = "MANUAL_REVIEW_GEAR",
      costBasisStatus = bRec and "MATCHED_7D_AH_PAID" or "UNKNOWN",
      matchedCostBasisCopper = bRec and bRec.averageUnitPaidCopper or nil,
      reviewChecklist = "Verify instance binding, random suffix, equipment upgrade use, and exact comparable listings.",
    })
  end
  table.sort(manualReviewGear, function(a, b) return a.itemID < b.itemID end)

  local lockboxes = {}
  local totalLockboxes = 0
  for id, label in pairs(PortfolioTriage.LOCKBOX_ITEM_IDS) do
    local qty = (spendableByItemID[id] and spendableByItemID[id].spendableCount) or 0
    if qty > 0 then
      totalLockboxes = totalLockboxes + qty
      table.insert(lockboxes, {
        itemID = id,
        name = label,
        quantity = qty,
        disposition = "HOLD_FOR_UNLOCK_ASSESSMENT",
      })
    end
  end
  table.sort(lockboxes, function(a, b) return a.itemID < b.itemID end)

  -- 4. Unfilled Waylaid Crates (separate AH eligibility, alt transfer, filled state, and turn-in economics):
  local crateRecords = {}
  local cratesMap = (ns.Data and ns.Data.cratesByItemID) or {}
  for cid, cMeta in pairs(cratesMap) do
    local numID = tonumber(cid)
    if numID then
      local bankedQty = (spendableByItemID[numID] and spendableByItemID[numID].spendableCount) or 0
      local postedQty = activeAuctionsByItemID[numID] or 0
      if bankedQty > 0 or postedQty > 0 then
        local captureAhProven = (PortfolioTriage.CAPTURE_VERIFIED_AH_CRATE_IDS[numID] == true)
        table.insert(crateRecords, {
          crateItemID = numID,
          name = cMeta.name or ("Waylaid Crate #" .. tostring(numID)),
          tier = cMeta.tier,
          bankedQuantity = bankedQty,
          activePostedQuantity = postedQty,
          ahEligibilityAtCapture = captureAhProven and "PROVEN_BY_ACTIVE_LISTING_AT_CAPTURE" or "UNVERIFIED_BANK_INSTANCE",
          altTransferEligibility = "ineligible", -- Preserves Syndicator.ClassifyAltTransferEligibility contract
          filledState = "UNVERIFY_UNTIL_INSPECTED_IN_CLIENT",
          turnInComparisonRequired = true,
          disposition = "VERIFY_BANK_INSTANCE_AND_COMPARE_RESALE_VS_FILL_AND_REWARD",
        })
      end
    end
  end
  table.sort(crateRecords, function(a, b) return a.crateItemID < b.crateItemID end)

  -- 5. Stage 1 vs Stage 2 Consumable Probe & Invoice Reconciliation:
  local invoiceReport = PortfolioTriage.ReconcileStage1SaleInvoices({
    characterGUID = opts.characterGUID,
    testPurchasesByItemID = opts.testPurchasesByItemID,
    mailLedgerEntries = opts.mailLedgerEntries,
    heardSalesEntries = opts.heardSalesEntries,
    failedListingDepositCopperByItemID = opts.failedListingDepositCopperByItemID,
  })

  return {
    schemaVersion = PortfolioTriage.SCHEMA_VERSION,
    nowEpoch = nowEpoch,
    raidCutoffEpoch = PortfolioTriage.DEC9_2026_RAID_UNLOCK_EPOCH,
    stage1BudgetCapCopper = stage1BudgetCapCopper,
    stage1MaxCeilingCopper = PortfolioTriage.STAGE1_MAX_CEILING_COPPER,
    stage1ProbeSpecs = PortfolioTriage.STAGE1_PROBE_SPECS,
    stage2Reconciliation = invoiceReport,
    tailoringOpeningTranche = openingTranche,
    moonclothSchedule = moonclothSchedule,
    holdingsTriage = holdingsTriage,
    protectedItems = protectedItems,
    manualReviewGear = manualReviewGear,
    lockboxes = lockboxes,
    totalLockboxCount = totalLockboxes,
    crateTriage = crateRecords,
    activeAuctionUnitsByItemID = activeAuctionsByItemID,
    expiredAuctionListings = expiredAuctionListings,
    mailInTransitByItemID = mailInTransitByItemID,
  }
end

return PortfolioTriage
