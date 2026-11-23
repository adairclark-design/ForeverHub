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

-- ============================================================================
-- RaidReadinessCoach (v0.9.0 — Astra P0/P1 Audited Cross-PC Route & Gear Coach)
-- ============================================================================

local RaidReadinessCoach = {}
ns.Domain.RaidReadinessCoach = RaidReadinessCoach
PortfolioTriage.RaidReadinessCoach = RaidReadinessCoach

RaidReadinessCoach.SCHEMA_VERSION = "foreverhub-raid-readiness-v0.9.0"
RaidReadinessCoach.RETRY_DELAYS_SECONDS = { 0.25, 0.50, 1.00, 2.00 }
RaidReadinessCoach.worldGeneration = 0
RaidReadinessCoach.coalescedPending = false
RaidReadinessCoach.lastEvaluation = nil

-- Astra P1 Verified Item & Spell Constants on Build 70862:
RaidReadinessCoach.VERIFIED_ITEMS = {
  SPIRE_OF_HAKKAR = { itemID = 10844, name = "Spire of Hakkar", spellPower = 62, note = "62 SP + life-steal proc on build 70862; keep until live tooltip comparison shows a gain." },
  INVENTORS_FOCAL_SWORD = { itemID = 17719, name = "Inventor's Focal Sword", combinedWithAquementasSP = 81 },
  SPIRIT_OF_AQUEMENTAS = { itemID = 11904, name = "Spirit of Aquementas", combinedWithGizlockSP = 81 },
  TRINDLEHAVEN_STAFF = { itemID = 13161, name = "Trindlehaven Staff", spellPower = 70, mp5 = 6, wrongItemIDNote = "13261 is Globe of D'sak" },
  SPELLWEAVERS_TURBAN = { itemID = 22267, name = "Spellweaver's Turban" },
  SKYSHROUD_LEGGINGS = { itemID = 13170, name = "Skyshroud Leggings", spellPower = 30 },
  EYE_OF_THE_BEAST = { itemID = 13968, name = "Eye of the Beast", passiveSpellCritPct = 1, onUseSpellHitPct = 7 },
  SONGSTONE_OF_IRONFORGE = { itemID = 12543, name = "Songstone of Ironforge", spellPower = 18 },
  BRIARWOOD_REED = { itemID = 12930, name = "Briarwood Reed", spellPower = 29 },
  DRAKEFIRE_AMULET = { itemID = 16309, name = "Drakefire Amulet", fireResist = 15, stamina = 10 },
  NETHER_FORCE_WAND = { itemID = 11263, name = "Nether Force Wand", arcaneSpellPower = 9, note = "Already has +9 Arcane SP on build 70862; Arcane Wrath can be a sidegrade." },
  THEKAS_LAST_BREATH = { itemID = 274641, name = "Theka's Last Breath", mp5 = 6 },
  LICHBANE = { itemID = 275347, name = "Lichbane" },
  ELUNARIAN_CUFFS = { itemID = 14457, name = "Elunarian Cuffs" },
  COUNCILLORS_TUNIC = { itemID = 10104, name = "Councillor's Tunic" },
  JASPER_LINK = { itemID = 11978, name = "Jasper Link" },
  SCEPTER_OF_CELEBRAS = { itemID = 17191, name = "Scepter of Celebras" },
  PATTERN_MOONCLOTH = { itemID = 14526, name = "Pattern: Mooncloth", requiredSkill = 230 },
  ROBE_OF_THE_ARCHMAGE = { itemID = 14152, spellID = 18457, name = "Robe of the Archmage", requiredSkill = 295 },
}

RaidReadinessCoach.OPTIONAL_STEP_IDS = {
  CORE_1A_IF_BANK_AND_AH = true,
  CORE_7A_LBRS_COMMAND = true,
  LINKEN_GIZLOCK_OPTIONAL = true,
}

local LBRS_SUBZONE_HINTS = {
  ["hordemar city"] = true,
  ["tazz'alaor"] = true,
  ["skitterweb tunnels"] = true,
  ["halycon's lair"] = true,
  ["chamber of battle"] = true,
  ["lower blackrock spire"] = true,
}

local UBRS_SUBZONE_HINTS = {
  ["dragonspire hall"] = true,
  ["hall of blackhand"] = true,
  ["the rookery"] = true,
  ["blackrock stadium"] = true,
  ["the furnace"] = true,
  ["upper blackrock spire"] = true,
}

function RaidReadinessCoach.ResolveBlackrockSpireWing(subzoneText, activeStepID)
  local norm = type(subzoneText) == "string" and string.lower(string.gsub(subzoneText, "^%s*(.-)%s*$", "%1")) or ""
  if LBRS_SUBZONE_HINTS[norm] then
    return "LBRS", "subzone_verified"
  end
  if UBRS_SUBZONE_HINTS[norm] then
    return "UBRS", "subzone_verified"
  end
  if activeStepID == "CORE_7A_LBRS_COMMAND" then
    return "UNCERTAIN", "Use right balcony drop for LBRS (Omokk / Zigris / Wyrmthalak)"
  elseif activeStepID == "CORE_7B_UBRS_DRAKKISATH" or activeStepID == "CORE_7B_DRAKKISATH_MISSING_BLOOD_RECOVERY" then
    return "UNCERTAIN", "Use left ramp up through Seal of Ascension door for UBRS (Jed / Drakkisath)"
  end
  return "UNCERTAIN", "Blackrock Spire Entrance • Left ramp up = UBRS (Seal door) | Right balcony drop = LBRS"
end

local function ensureCharRaidReadinessStore()
  if ns.State and type(ns.State.GetCharDB) == "function" then
    local ok, charDB = pcall(ns.State.GetCharDB)
    if ok and type(charDB) == "table" then
      if type(charDB.raidReadiness) ~= "table" then
        charDB.raidReadiness = {
          activeTrack = "core_attune", -- "core_attune" | "linken_solo"
          coachEnabled = false,
          skippedStepIDs = {},
        }
      end
      if type(charDB.raidReadiness.skippedStepIDs) ~= "table" then
        charDB.raidReadiness.skippedStepIDs = {}
      end
      return charDB.raidReadiness
    end
  end
  RaidReadinessCoach._ephemeralStore = RaidReadinessCoach._ephemeralStore or {
    activeTrack = "core_attune",
    coachEnabled = false,
    skippedStepIDs = {},
  }
  return RaidReadinessCoach._ephemeralStore
end

function RaidReadinessCoach.GetPersistedConfig()
  return ensureCharRaidReadinessStore()
end

-- Astra P0: Keep skips reversible, per-character, and strictly limited to optional work.
-- A skip NEVER grants quest credit or satisfies a mandatory prerequisite.
function RaidReadinessCoach.SetStepSkipped(stepID, skipped)
  local id = tostring(stepID or "")
  if not RaidReadinessCoach.OPTIONAL_STEP_IDS[id] then
    return false, "mandatory_step_cannot_be_skipped"
  end
  local store = ensureCharRaidReadinessStore()
  if skipped == true then
    store.skippedStepIDs[id] = true
  else
    store.skippedStepIDs[id] = nil
  end
  return true, (skipped == true) and "skipped" or "unskipped"
end

function RaidReadinessCoach.ClearAllSkips()
  local store = ensureCharRaidReadinessStore()
  store.skippedStepIDs = {}
  return true
end

function RaidReadinessCoach.SetActiveTrack(trackKey)
  local store = ensureCharRaidReadinessStore()
  if trackKey == "linken_solo" then
    store.activeTrack = "linken_solo"
  else
    store.activeTrack = "core_attune"
  end
  return store.activeTrack
end

local ALL_TRACKED_QUEST_IDS = {
  -- Princess chain & prereqs:
  3702, 3701, 4341, 4342, 4361, 4362, 4363,
  -- Onyxia chain (including both 6403 and 99435 Masquerade variants):
  4182, 4183, 4184, 4185, 4186, 4223, 4224, 4241, 4242, 4264, 4282, 4322, 6402, 6403, 99435, 6501, 6502,
  -- UBRS Eye of the Beast chain:
  5089, 5102,
  -- Optional BRD Shadowforge Key & Build-deferred MC Attunement:
  3801, 3802, 7848,
  -- Full Linken chain (including 4041 Videre repeatable, 4084 Silver Heart, 4005 Aquementas):
  3844, 3845, 3908, 3909, 4041, 3912, 3913, 3914, 3941, 3942, 4084, 4005, 3961, 3962,
}

local function isActiveOrDone(st)
  return st == "active" or st == "ready_to_turn_in" or st == "turned_in"
end

local function isReadyOrDone(st)
  return st == "ready_to_turn_in" or st == "turned_in"
end

local function applyDownstreamQuestInference(qStates)
  -- Helper: if any quest in `laterList` is active/ready/turned_in, all quests in `earlierList` are inferred "turned_in"
  local function inferChain(orderedIDs)
    local highestActiveOrDoneIdx = 0
    for idx, qid in ipairs(orderedIDs) do
      local entry = qStates[qid]
      if entry and isActiveOrDone(entry.state) then
        highestActiveOrDoneIdx = idx
      end
    end
    if highestActiveOrDoneIdx > 1 then
      for idx = 1, highestActiveOrDoneIdx - 1 do
        local qid = orderedIDs[idx]
        local entry = qStates[qid]
        if not entry or entry.state ~= "turned_in" then
          qStates[qid] = {
            questID = qid,
            state = "turned_in",
            fulfilledCount = 1,
            requiredCount = 1,
            objectives = {},
            provenance = "downstream_evidence",
          }
        end
      end
    end
  end

  inferChain({ 3702, 3701, 4341, 4342, 4361, 4362, 4363 })
  inferChain({ 4182, 4183, 4184, 4185, 4186, 4223, 4224, 4241, 4242, 4264, 4282, 4322, 6402 })
  inferChain({ 5089, 5102 })
  inferChain({ 3844, 3845, 3908, 3909, 3912, 3913, 3914, 3941, 3942, 4084, 4005, 3961, 3962 })

  -- Masquerade dual-ID handling (6403 or 99435) -> 6501 -> 6502
  local q6502 = qStates[6502] and qStates[6502].state or "absent"
  local q6501 = qStates[6501] and qStates[6501].state or "absent"
  if isActiveOrDone(q6502) and q6501 ~= "turned_in" then
    qStates[6501] = { questID = 6501, state = "turned_in", fulfilledCount = 1, requiredCount = 1, provenance = "downstream_evidence" }
    q6501 = "turned_in"
  end
  if isActiveOrDone(q6501) then
    for _, preId in ipairs({ 4182, 4183, 4184, 4185, 4186, 4223, 4224, 4241, 4242, 4264, 4282, 4322, 6402 }) do
      if not qStates[preId] or qStates[preId].state ~= "turned_in" then
        qStates[preId] = { questID = preId, state = "turned_in", fulfilledCount = 1, requiredCount = 1, provenance = "downstream_evidence" }
      end
    end
    if (not qStates[6403] or qStates[6403].state ~= "turned_in") and (not qStates[99435] or qStates[99435].state ~= "turned_in") then
      qStates[6403] = { questID = 6403, state = "turned_in", fulfilledCount = 1, requiredCount = 1, provenance = "downstream_evidence" }
    end
  end
  local q6403 = qStates[6403] and qStates[6403].state or "absent"
  local q99435 = qStates[99435] and qStates[99435].state or "absent"
  if isActiveOrDone(q6403) or isActiveOrDone(q99435) then
    for _, preId in ipairs({ 4182, 4183, 4184, 4185, 4186, 4223, 4224, 4241, 4242, 4264, 4282, 4322, 6402 }) do
      if not qStates[preId] or qStates[preId].state ~= "turned_in" then
        qStates[preId] = { questID = preId, state = "turned_in", fulfilledCount = 1, requiredCount = 1, provenance = "downstream_evidence" }
      end
    end
  end
end

function RaidReadinessCoach.BuildSnapshot(opts)
  opts = type(opts) == "table" and opts or {}
  local store = ensureCharRaidReadinessStore()
  local skipped = type(opts.skippedStepIDs) == "table" and opts.skippedStepIDs or store.skippedStepIDs or {}
  local activeTrack = opts.activeTrack or store.activeTrack or "core_attune"

  -- 1. Resolve 5-state quest table
  local qStates = {}
  local unknownQuestIDs = {}
  for _, qid in ipairs(ALL_TRACKED_QUEST_IDS) do
    local reqObj = (qid == 3701) and 12 or nil
    local res = (ns.Compat and type(ns.Compat.GetCrossPCQuestStateResult) == "function")
      and ns.Compat.GetCrossPCQuestStateResult(qid, {
        questStatesByID = opts.questStatesByID,
        requiredObjectiveCount = reqObj,
      })
      or { questID = qid, state = "unknown", fulfilledCount = 0, requiredCount = reqObj or 0 }
    qStates[qid] = res
  end

  -- Apply downstream evidence before checking if any active blocking quest is still "unknown"
  applyDownstreamQuestInference(qStates)

  for _, qid in ipairs({ 3702, 3701, 4182, 4241, 4242, 4322, 4341, 4361, 4362, 4363, 6402, 6501, 6502, 3912, 3962 }) do
    if qStates[qid] and qStates[qid].state == "unknown" then
      table.insert(unknownQuestIDs, qid)
    end
  end

  -- 2. Bag & Bank counts + Bank Readability
  local bagCounts = type(opts.bagCountsByID) == "table" and opts.bagCountsByID or {}
  local bankCounts = type(opts.bankCountsByID) == "table" and opts.bankCountsByID or {}
  local bankReadable = (opts.bankReadable == true)
    or (ns.State and type(ns.State.HasSessionBankObservation) == "function" and ns.State.HasSessionBankObservation())
    or (ns.State and ns.State.bankOpen == true)
    or false

  local function getBagCount(itemID)
    if bagCounts[itemID] ~= nil then
      return math.max(0, math.floor(tonumber(bagCounts[itemID]) or 0))
    end
    if type(_G.GetItemCount) == "function" then
      local ok, c = pcall(_G.GetItemCount, itemID, false)
      if ok and type(c) == "number" then
        return math.max(0, math.floor(c))
      end
    end
    return 0
  end

  local function getBankCount(itemID)
    if bankCounts[itemID] ~= nil then
      return math.max(0, math.floor(tonumber(bankCounts[itemID]) or 0))
    end
    if type(_G.GetItemCount) == "function" then
      local okT, tot = pcall(_G.GetItemCount, itemID, true)
      local b = getBagCount(itemID)
      if okT and type(tot) == "number" and tot > b then
        bankReadable = true
        return math.max(0, math.floor(tot - b))
      end
    end
    return 0
  end

  -- 3. Equipped slots & pending item metadata distinction
  local equippedBySlot = type(opts.equippedBySlot) == "table" and opts.equippedBySlot or {}
  local equippedLinksBySlot = type(opts.equippedLinksBySlot) == "table" and opts.equippedLinksBySlot or {}
  local pendingMetadataSlots = {}
  for slot = 1, 18 do
    if equippedBySlot[slot] == nil and type(_G.GetInventoryItemID) == "function" then
      local ok, iid = pcall(_G.GetInventoryItemID, "player", slot)
      if ok and type(iid) == "number" and iid > 0 then
        equippedBySlot[slot] = iid
        if type(_G.GetInventoryItemLink) == "function" then
          local okL, lnk = pcall(_G.GetInventoryItemLink, "player", slot)
          if okL and type(lnk) == "string" then
            equippedLinksBySlot[slot] = lnk
          else
            table.insert(pendingMetadataSlots, slot)
          end
        end
      end
    end
  end

  -- 4. Location, Instance, Ghost & Teleport state
  local isDeadOrGhost = (opts.isDeadOrGhost == true)
  if opts.isDeadOrGhost == nil and type(_G.UnitIsDeadOrGhost) == "function" then
    local okD, d = pcall(_G.UnitIsDeadOrGhost, "player")
    if okD and (d == true or d == 1) then
      isDeadOrGhost = true
    end
  end

  local inInstance = (opts.inInstance == true)
  local instanceName = opts.instanceName or ""
  local subzoneText = opts.subzoneText or ""
  if opts.inInstance == nil and type(_G.IsInInstance) == "function" then
    local okI, isIn, iType = pcall(_G.IsInInstance)
    if okI and (isIn == true or isIn == 1) and (iType == "party" or iType == "raid") then
      inInstance = true
    end
  end
  if subzoneText == "" and type(_G.GetSubZoneText) == "function" then
    local okS, sz = pcall(_G.GetSubZoneText)
    if okS and type(sz) == "string" then
      subzoneText = sz
    end
  end

  -- 5. Tailoring skill & Mooncloth / Archmage tracking (Astra P1: Mooncloth = 230, Robe of the Archmage = 295)
  local tailoringSkill = tonumber(opts.tailoringSkill) or 214
  local tailoringCap = tonumber(opts.tailoringCap) or 225
  local runeOfTeleportCount = getBagCount(17031)

  return {
    activeTrack = activeTrack,
    skippedStepIDs = skipped,
    questStates = qStates,
    unknownQuestIDs = unknownQuestIDs,
    hydrationPending = (#unknownQuestIDs > 0) or (#pendingMetadataSlots > 0) or (opts.hydrationPending == true),
    pendingMetadataSlots = pendingMetadataSlots,
    bankReadable = bankReadable,
    getBagCount = getBagCount,
    getBankCount = getBankCount,
    equippedBySlot = equippedBySlot,
    equippedLinksBySlot = equippedLinksBySlot,
    isDeadOrGhost = isDeadOrGhost,
    inInstance = inInstance,
    instanceName = instanceName,
    subzoneText = subzoneText,
    tailoringSkill = tailoringSkill,
    tailoringCap = tailoringCap,
    runeOfTeleportCount = runeOfTeleportCount,
  }
end

function RaidReadinessCoach.Evaluate(opts)
  local snap = RaidReadinessCoach.BuildSnapshot(opts)
  local q = snap.questStates
  local getBag = snap.getBagCount
  local getBank = snap.getBankCount
  local eq = snap.equippedBySlot
  local skipped = snap.skippedStepIDs

  local function qState(qid)
    return (q[qid] and q[qid].state) or "unknown"
  end

  -- A. Evaluate Onyxia Attunement & Amulet Carrier Status (Astra P0/P2)
  local q6502 = qState(6502)
  local amuletInBags = getBag(16309) > 0
  local amuletEquipped = (eq[2] == 16309)
  local amuletInBank = getBank(16309) > 0
  local amuletCarried = amuletInBags or amuletEquipped
  local onyxiaStatusLabel = "Onyxia attunement in progress"
  local onyxiaAttunedAndCarried = false
  if q6502 == "turned_in" then
    if amuletCarried then
      onyxiaStatusLabel = "Onyxia attuned · amulet carried"
      onyxiaAttunedAndCarried = true
    elseif amuletInBank then
      onyxiaStatusLabel = "Onyxia attuned · amulet in BANK (withdraw required!)"
    elseif snap.bankReadable then
      onyxiaStatusLabel = "Onyxia attuned · amulet MISSING (recover from Haleh!)"
    else
      onyxiaStatusLabel = "Onyxia attuned · amulet not in bags (check Bank)"
    end
  end

  -- B. Evaluate Linken `3962` vs `Spirit of Aquementas (11904)` Ownership Separately (Astra P0)
  local q3962 = qState(3962)
  local aquementasInBagsOrEquipped = (getBag(11904) > 0) or (eq[17] == 11904)
  local aquementasInBank = getBank(11904) > 0
  local aquementasStatus = "in_progress"
  if aquementasInBagsOrEquipped then
    aquementasStatus = (eq[17] == 11904) and "equipped" or "in_bags"
  elseif aquementasInBank then
    aquementasStatus = "in_bank_withdraw_needed"
  elseif q3962 == "turned_in" then
    aquementasStatus = snap.bankReadable and "completed_other_reward_chosen_or_missing" or "completed_check_bank"
  end

  -- C. Evaluate Profession Readiness (Astra P1: Mooncloth at 230, Robe of the Archmage at 295)
  local pointsToMooncloth = math.max(0, 230 - snap.tailoringSkill)
  local needsArtisanCapRaise = (snap.tailoringCap < 300)
  local felclothTotal = getBag(14256) + getBank(14256)
  local patternMoonclothOwned = (getBag(14526) + getBank(14526)) > 0
  local professionStatus = {
    tailoringSkill = snap.tailoringSkill,
    tailoringCap = snap.tailoringCap,
    moonclothUnlockSkill = 230,
    pointsToMooncloth = pointsToMooncloth,
    needsArtisanCapRaise = needsArtisanCapRaise,
    patternMoonclothOwned = patternMoonclothOwned,
    felclothAvailable = felclothTotal,
    moonclothReadyToCraft = (snap.tailoringSkill >= 230 and getBag(14256) >= 2),
    archmageUnlockSkill = 295,
    pointsToArchmage = math.max(0, 295 - snap.tailoringSkill),
    summaryText = string.format(
      "Tailoring %d/%d (%d pts to Mooncloth @ 230%s; Archmage @ 295 fits separate project)",
      snap.tailoringSkill,
      snap.tailoringCap,
      pointsToMooncloth,
      needsArtisanCapRaise and ", train Artisan 225->300 first" or ""
    ),
  }

  -- D. Evaluate Gear Scorecard (Astra P1 corrections: Spire = 62 SP, Focal+Aquementas = 81 SP, Trindlehaven 13161 = 70 SP + 6 MP5, Wand 11263 = +9 Arcane SP, Turban = 22267, Skyshroud = 30 SP, Eye = 1% crit + 7% hit use)
  local gearScorecard = {
    weapon = {
      equippedMH = eq[16],
      equippedOH = eq[17],
      hasSpireOfHakkar = (eq[16] == 10844),
      hasTrindlehaven = (eq[16] == 13161 or getBag(13161) > 0),
      hasFocalPlusAquementas = ((eq[16] == 17719 or getBag(17719) > 0) and (aquementasInBagsOrEquipped or aquementasInBank)),
      guidance = "Keep Spire of Hakkar (10844: 62 SP + life-steal proc) until live tooltip shows a gain (Gizlock 17719 + Aquementas 11904 = 81 combined SP; LBRS Trindlehaven Staff 13161 = 70 SP + 6 MP5).",
    },
    wrist = {
      equipped = eq[9],
      bankedElunarian = (getBag(14457) + getBank(14457)) > 0,
      isLv34Oilrag = (eq[9] == 9448),
      guidance = "Compare banked Elunarian Cuffs (14457) suffix/enchant against Spidertank Oilrag (9448), price AH wrists, and roll on Lord Incendius Flameweave Cuffs (11766) in BRD.",
    },
    wand = {
      equipped = eq[18],
      isNetherForce = (eq[18] == 11263),
      guidance = "Nether Force Wand (11263) already grants +9 Arcane SP on build 70862; Arcane Wrath can be a sidegrade—compare actual realm listings and live tooltips before buying.",
    },
    legs = {
      equipped = eq[7],
      isLv41Slacks = (eq[7] == 279878),
      hasSkyshroud = (eq[7] == 13170 or getBag(13170) > 0),
      guidance = "Price AH legs against Apprentice Sorcerer's Slacks (279878) and target LBRS Highlord Omokk for Skyshroud Leggings (13170, 30 SP).",
    },
    chest = {
      equipped = eq[5],
      bankedCouncillors = (getBag(10104) + getBank(10104)) > 0,
      guidance = "Compare banked Councillor's Tunic (10104:8489) against Acumen Robes (17775); treat Robe of the Archmage (18457, Tailoring 295) as a separate pattern & materials project.",
    },
    rings = {
      equipped1 = eq[11],
      equipped2 = eq[12],
      bankedJasperLink = (getBag(11978) + getBank(11978)) > 0,
      hasSongstone = (eq[11] == 12543 or eq[12] == 12543 or getBag(12543) > 0 or getBank(12543) > 0),
      guidance = "Compare banked Jasper Link (11978) against Woodseed Hoop (17768) / Purified Ring (270081) and choose Songstone of Ironforge (12543) from 4363.",
    },
    trinkets = {
      equipped1 = eq[13],
      equipped2 = eq[14],
      hasThekasAvailable = (eq[13] == 274641 or eq[14] == 274641 or getBag(274641) > 0 or getBank(274641) > 0),
      hasEyeOfTheBeast = (eq[13] == 13968 or eq[14] == 13968 or getBag(13968) > 0 or getBank(13968) > 0),
      guidance = "Theka's Last Breath (274641, +6 MP5) is immediately available over Chained Essence of Eranikus (10455); choose Eye of the Beast (13968, 1% passive spell crit + 7% spell-hit use) from 5102.",
    },
  }

  local travelNote = (snap.runeOfTeleportCount > 0)
    and "Keep Gadgetzan hearth; use Teleport: Ironforge (3562) / Teleport: Stormwind (3561)."
    or "Keep Gadgetzan hearth; restock Rune of Teleportation (17031) for Ironforge/Stormwind teleports."

  local function makeStep(spec)
    spec.travelSuggestion = spec.travelSuggestion or travelNote
    if snap.inInstance and spec.navigationMode == "OUTDOOR_ARROW" then
      -- Astra P0: Never render an outdoor directional arrow while inside an instance!
      spec.effectiveNavigationMode = "INSTANCE_OBJECTIVE"
    else
      spec.effectiveNavigationMode = spec.navigationMode
    end
    return spec
  end

  -- ==========================================================================
  -- E. Resolve Next Action on Parallel Track ("linken_solo")
  -- ==========================================================================
  local function resolveLinkenAction()
    local q3912 = qState(3912)
    local q3913 = qState(3913)
    local q3914 = qState(3914)
    local q3941 = qState(3941)
    local q3942 = qState(3942)
    local q4084 = qState(4084)
    local q4005 = qState(4005)
    local q3961 = qState(3961)

    if q3912 == "absent" then
      return makeStep({
        stepID = "LINKEN_1_WS_DONOVA_3912",
        track = "linken_solo",
        shortTitle = "L1: Accept Meet at the Grave (Donova, WS)",
        navigationMode = "OUTDOOR_ARROW",
        destination = { uiMapID = 1452, x01 = 0.312, y01 = 0.452, zoneName = "Winterspring" },
        arrivalRadiusYards = 20,
        npcName = "Donova Snowden",
        questID = 3912,
        detailText = "Donova consumed 1 Videre Elixir on 3909 turn-in. Accept 3912 Meet at the Grave (supplies Tempered Sword), then recheck bags/bank for Videre Elixir (11243).",
      })
    end

    if q3912 == "active" or q3912 == "ready_to_turn_in" then
      -- Astra P0: While already a ghost on this leg, show Gaeriyan and suppress the elixir shopping prompt!
      if snap.isDeadOrGhost then
        return makeStep({
          stepID = "LINKEN_2C_GHOST_GAERIYAN_3912",
          track = "linken_solo",
          shortTitle = "L2: Speak to Gaeriyan as Ghost (Tanaris)",
          navigationMode = "OUTDOOR_ARROW",
          destination = { uiMapID = 1446, x01 = 0.540, y01 = 0.232, zoneName = "Tanaris" },
          arrivalRadiusYards = 18,
          npcName = "Gaeriyan",
          questID = 3912,
          elixirShoppingSuppressed = true,
          detailText = "Already in ghost form: speak directly to Gaeriyan (54.0, 23.2) to turn in 3912 and accept 3913 A Grave Situation.",
        })
      end
      if getBag(11243) == 0 then
        if getBank(11243) > 0 then
          return makeStep({
            stepID = "LINKEN_2A_WITHDRAW_VIDERE_BANK",
            track = "linken_solo",
            shortTitle = "L2: Withdraw Videre Elixir (11243) from Bank",
            navigationMode = "OUTDOOR_ARROW",
            destination = { uiMapID = 1452, x01 = 0.614, y01 = 0.370, zoneName = "Winterspring" },
            arrivalRadiusYards = 20,
            questID = 3912,
            detailText = "Videre Elixir (11243) is in your Bank. Withdraw it before hearthing to Gadgetzan.",
          })
        end
        if getBag(11242) == 0 then
          if getBag(11141) == 0 then
            return makeStep({
              stepID = "LINKEN_2B_FERALAS_GREGAN_BAIT",
              track = "linken_solo",
              shortTitle = "L2: Get Bait (11141) from Gregan (Feralas)",
              navigationMode = "OUTDOOR_ARROW",
              destination = { uiMapID = 1444, x01 = 0.451, y01 = 0.256, zoneName = "Feralas" },
              arrivalRadiusYards = 20,
              npcName = "Gregan Brewspewer",
              questID = 4041,
              detailText = "Buy/take Bait (11141) from Gregan Brewspewer (45.1, 25.6), then use it by Miblon Snarltooth at Ravenwind (44.6, 10.6) to loot Evoroot (11242).",
            })
          end
          return makeStep({
            stepID = "LINKEN_2B_FERALAS_MIBLON_EVOROOT",
            track = "linken_solo",
            shortTitle = "L2: Use Bait on Miblon -> Loot Evoroot (Feralas)",
            navigationMode = "OUTDOOR_ARROW",
            destination = { uiMapID = 1444, x01 = 0.446, y01 = 0.106, zoneName = "Feralas" },
            arrivalRadiusYards = 18,
            npcName = "Miblon Snarltooth",
            questID = 4041,
            detailText = "Place Bait (11141) beside Miblon Snarltooth (44.6, 10.6), step through the wall gap to loot Evoroot (11242), and return to Gregan (45.1, 25.6).",
          })
        end
        return makeStep({
          stepID = "LINKEN_2B_FERALAS_GREGAN_4041",
          track = "linken_solo",
          shortTitle = "L2: Trade Evoroot to Gregan for 3x Videre (4041)",
          navigationMode = "OUTDOOR_ARROW",
          destination = { uiMapID = 1444, x01 = 0.451, y01 = 0.256, zoneName = "Feralas" },
          arrivalRadiusYards = 20,
          npcName = "Gregan Brewspewer",
          questID = 4041,
          detailText = "Turn in Evoroot (11242) via repeatable 4041 The Videre Elixir (yields 3 vials of 11243), then hearth to Gadgetzan.",
        })
      end
      return makeStep({
        stepID = "LINKEN_2C_GADGETZAN_GY_DRINK",
        track = "linken_solo",
        shortTitle = "L2: Drink Videre at Gadgetzan GY (53.9, 29.0)",
        navigationMode = "OUTDOOR_ARROW",
        destination = { uiMapID = 1446, x01 = 0.539, y01 = 0.290, zoneName = "Tanaris" },
        arrivalRadiusYards = 22,
        questID = 3912,
        detailText = "Hearth to Gadgetzan, walk to the graveyard (53.9, 29.0), drink Videre Elixir (11243), release spirit, and walk north to Gaeriyan (54.0, 23.2).",
      })
    end

    if q3913 ~= "turned_in" then
      return makeStep({
        stepID = "LINKEN_3_GRAVESTONE_3913",
        track = "linken_solo",
        shortTitle = "L3: Resurrect & Click Conspicuous Gravestone",
        navigationMode = "OUTDOOR_ARROW",
        destination = { uiMapID = 1446, x01 = 0.539, y01 = 0.290, zoneName = "Tanaris" },
        arrivalRadiusYards = 18,
        npcName = "Conspicuous Gravestone",
        questID = 3913,
        detailText = "Resurrect at Gadgetzan Graveyard (53.9, 29.0), turn in 3913 A Grave Situation at the Conspicuous Gravestone, and accept 3914 Linken's Sword.",
      })
    end

    if q3914 ~= "turned_in" or q3941 ~= "turned_in" then
      local atCollie = (q3914 == "turned_in")
      return makeStep({
        stepID = "LINKEN_4_UNGORO_LINKEN_COLLIE",
        track = "linken_solo",
        shortTitle = atCollie and "L4: Speak to J.D. Collie (Un'Goro Cave)" or "L4: Turn in 3914 to Linken (Un'Goro)",
        navigationMode = "OUTDOOR_ARROW",
        destination = atCollie
          and { uiMapID = 1449, x01 = 0.418, y01 = 0.026, zoneName = "Un'Goro Crater" }
          or { uiMapID = 1449, x01 = 0.446, y01 = 0.082, zoneName = "Un'Goro Crater" },
        arrivalRadiusYards = 20,
        npcName = atCollie and "J.D. Collie" or "Linken",
        questID = atCollie and 3941 or 3914,
        detailText = "Turn in 3914 Linken's Sword at Linken (44.6, 8.2) -> accept 3941 -> speak to J.D. Collie inside Marshal's Refuge crystal cave (41.8, 2.6) and accept 3942 Linken's Memory.",
      })
    end

    if q3942 ~= "turned_in" then
      return makeStep({
        stepID = "LINKEN_5_FELWOOD_ERIDAN_3942",
        track = "linken_solo",
        shortTitle = "L5: Turn in 3942 to Eridan Bluewind (Felwood)",
        navigationMode = "OUTDOOR_ARROW",
        destination = { uiMapID = 1448, x01 = 0.513, y01 = 0.816, zoneName = "Felwood" },
        arrivalRadiusYards = 22,
        npcName = "Eridan Bluewind",
        questID = 3942,
        detailText = "Turn in 3942 Linken's Memory to Eridan Bluewind at Emerald Sanctuary, Felwood (51.3, 81.6) and accept 4084 Silver Heart.",
      })
    end

    if q4084 ~= "turned_in" then
      local claws = getBag(11172)
      local heart = getBag(11173)
      local ready4084 = (q4084 == "ready_to_turn_in") or (claws >= 11 and heart >= 1)
      return makeStep({
        stepID = "LINKEN_6_FELWOOD_SILVER_HEART_4084",
        track = "linken_solo",
        shortTitle = ready4084 and "L6: Turn in 4084 Silver Heart to Eridan" or string.format("L6: Farm Claws (%d/11) & Heart (%d/1) (Felwood)", math.min(11, claws), math.min(1, heart)),
        navigationMode = "OUTDOOR_ARROW",
        destination = ready4084
          and { uiMapID = 1448, x01 = 0.513, y01 = 0.816, zoneName = "Felwood" }
          or { uiMapID = 1448, x01 = 0.495, y01 = 0.295, zoneName = "Felwood" },
        arrivalRadiusYards = 25,
        npcName = ready4084 and "Eridan Bluewind" or "Irontree Elementals & Felwood Beasts",
        questID = 4084,
        detailText = "For 4084 Silver Heart: loot 11 Silvery Claws (11172) from Felwood bears/wolves and 1 Irontree Heart (11173) from Irontree Woods elementals, then return to Eridan Bluewind (51.3, 81.6) and accept 4005 Aquementas.",
      })
    end

    if q4005 ~= "turned_in" then
      local hasTotem = (getBag(11522) >= 1) or (q4005 == "ready_to_turn_in")
      return makeStep({
        stepID = "LINKEN_7_TANARIS_AQUEMENTAS_4005",
        track = "linken_solo",
        shortTitle = hasTotem and "L7: Turn in 4005 Aquementas to J.D. Collie" or "L7: Summon Aquementas at Lost Rigger Cove",
        navigationMode = "OUTDOOR_ARROW",
        destination = hasTotem
          and { uiMapID = 1449, x01 = 0.418, y01 = 0.026, zoneName = "Un'Goro Crater" }
          or { uiMapID = 1446, x01 = 0.702, y01 = 0.499, zoneName = "Tanaris" },
        arrivalRadiusYards = 22,
        npcName = hasTotem and "J.D. Collie" or "Aquementas Stone Circle",
        questID = 4005,
        detailText = "Open Eridan's Supplies (11617) for Book of Aquor (11169). Stand inside the stone circle at Lost Rigger Cove, Tanaris (70.2, 49.9), read Book of Aquor, and stay inside the circle until your items become Silver Totem of Aquementas (11522). Then turn in 4005 to J.D. Collie (Un'Goro 41.8, 2.6).",
      })
    end

    if q3961 ~= "turned_in" then
      return makeStep({
        stepID = "LINKEN_8_UNGORO_3961",
        track = "linken_solo",
        shortTitle = "L8: Turn in 3961 Linken's Adventure to Linken",
        navigationMode = "OUTDOOR_ARROW",
        destination = { uiMapID = 1449, x01 = 0.446, y01 = 0.082, zoneName = "Un'Goro Crater" },
        arrivalRadiusYards = 20,
        npcName = "Linken",
        questID = 3961,
        detailText = "Take 3961 Linken's Adventure from J.D. Collie (41.8, 2.6) to Linken (44.6, 8.2) and accept 3962 It's Dangerous to Go Alone.",
      })
    end

    if q3962 ~= "turned_in" then
      local hasFlame = (getBag(11179) >= 1) or (q3962 == "ready_to_turn_in")
      return makeStep({
        stepID = "LINKEN_9_BLAZERUNNER_3962",
        track = "linken_solo",
        shortTitle = hasFlame and "L9: Turn in 3962 -> Choose Spirit of Aquementas" or "L9: Kill Blazerunner & Loot Golden Flame",
        navigationMode = "OUTDOOR_ARROW",
        destination = hasFlame
          and { uiMapID = 1449, x01 = 0.446, y01 = 0.082, zoneName = "Un'Goro Crater" }
          or { uiMapID = 1449, x01 = 0.494, y01 = 0.493, zoneName = "Un'Goro Crater" },
        arrivalRadiusYards = 22,
        npcName = hasFlame and "Linken" or "Blazerunner",
        questID = 3962,
        detailText = "Bring Silver Totem of Aquementas (11522) to Fire Plume Ridge peak (49.4, 49.3), use the totem to strip Blazerunner's aura, defeat him, loot Golden Flame (11179) from the chest behind him, and return to Linken (44.6, 8.2). IMPORTANT: Choose Spirit of Aquementas (11904)!",
      })
    end

    if aquementasInBank and not aquementasInBagsOrEquipped then
      return makeStep({
        stepID = "LINKEN_9B_WITHDRAW_AQUEMENTAS_BANK",
        track = "linken_solo",
        shortTitle = "L9b: Withdraw Spirit of Aquementas (11904) from Bank",
        navigationMode = "OUTDOOR_ARROW",
        destination = { uiMapID = 1455, x01 = 0.356, y01 = 0.606, zoneName = "Ironforge" },
        arrivalRadiusYards = 20,
        detailText = "3962 is completed and Spirit of Aquementas (11904) is in your Bank. Withdraw it to pair with a 1H caster weapon.",
      })
    end

    if not skipped["LINKEN_GIZLOCK_OPTIONAL"] and eq[16] ~= 17719 and getBag(17719) == 0 and getBank(17719) == 0 then
      return makeStep({
        stepID = "LINKEN_GIZLOCK_OPTIONAL",
        track = "linken_solo",
        optional = true,
        shortTitle = "L10 (Opt): Solo Maraudon Gizlock for Focal Sword",
        navigationMode = snap.inInstance and "INSTANCE_OBJECTIVE" or "OUTDOOR_ARROW",
        destination = { uiMapID = 1443, x01 = 0.360, y01 = 0.640, zoneName = "Desolace" },
        arrivalRadiusYards = 25,
        npcName = "Tinkerer Gizlock",
        detailText = "Optional: Enter Maraudon exterior in Desolace (36.0, 64.0), use Scepter of Celebras (17191) to portal to Earth Song Falls (Inner Maraudon), and solo Tinkerer Gizlock for Inventor's Focal Sword (17719; 81 combined SP with Aquementas vs 62 SP on Spire of Hakkar).",
      })
    end

    return makeStep({
      stepID = "LINKEN_COMPLETE",
      track = "linken_solo",
      isComplete = true,
      shortTitle = "Linken Track Complete",
      navigationMode = "INSTANCE_OBJECTIVE",
      detailText = (aquementasStatus == "completed_other_reward_chosen_or_missing")
        and "Linken chain (3962) is complete, but Spirit of Aquementas (11904) was not found in bags or bank."
        or "Linken chain complete and Spirit of Aquementas (11904) verified!",
    })
  end

  -- ==========================================================================
  -- F. Resolve Next Action on Primary Core Spine ("core_attune")
  -- ==========================================================================
  local function resolveCoreAction()
    local q3701 = qState(3701)
    local q4182 = qState(4182)
    local q4183 = qState(4183)
    local q4184 = qState(4184)
    local q4185 = qState(4185)
    local q4186 = qState(4186)
    local q4223 = qState(4223)
    local q4224 = qState(4224)
    local q4241 = qState(4241)
    local q4242 = qState(4242)
    local q4264 = qState(4264)
    local q4282 = qState(4282)
    local q4322 = qState(4322)
    local q4341 = qState(4341)
    local q4342 = qState(4342)
    local q4361 = qState(4361)
    local q4362 = qState(4362)
    local q4363 = qState(4363)
    local q6402 = qState(6402)
    local q6403 = qState(6403)
    local q99435 = qState(99435)
    local q6501 = qState(6501)
    local q5089 = qState(5089)
    local q5102 = qState(5102)

    -- 1. Optional Ironforge Bank & AH Comparison (`CORE_1A_IF_BANK_AND_AH`)
    local hasUncheckedBankUpgrades = (getBank(14457) > 0 or getBank(10104) > 0 or getBank(11978) > 0 or getBank(274641) > 0)
    if not skipped["CORE_1A_IF_BANK_AND_AH"] and hasUncheckedBankUpgrades and q3701 == "absent" then
      return makeStep({
        stepID = "CORE_1A_IF_BANK_AND_AH",
        track = "core_attune",
        optional = true,
        shortTitle = "P1.1 (Opt): Review Bank Upgrades & AH (IF)",
        navigationMode = "OUTDOOR_ARROW",
        destination = { uiMapID = 1455, x01 = 0.356, y01 = 0.606, zoneName = "Ironforge" },
        arrivalRadiusYards = 22,
        detailText = "Compare banked Elunarian Cuffs (14457), Councillor's Tunic (10104:8489), Jasper Link (11978), and Theka's Last Breath (274641, +6 MP5) against equipped links, and price AH legs/wrists/wands (Nether Force Wand 11263 already has +9 Arcane SP).",
      })
    end

    -- 2. Mandatory Ironforge Prerequisite: Accept `3701` from Royal Historian Archesonus before leaving for Burning Steppes
    if q3701 == "absent" then
      return makeStep({
        stepID = "CORE_1B_IF_ARCHESONUS_3701",
        track = "core_attune",
        shortTitle = "P1.2: Accept Ruins of Thaurissan (3701, IF)",
        navigationMode = "OUTDOOR_ARROW",
        destination = { uiMapID = 1455, x01 = 0.384, y01 = 0.554, zoneName = "Ironforge" },
        arrivalRadiusYards = 18,
        npcName = "Royal Historian Archesonus",
        questID = 3701,
        detailText = "Accept 3701 The Smoldering Ruins of Thaurissan from Royal Historian Archesonus (38.4, 55.4) in Ironforge before flying to Burning Steppes (required prerequisite for King Magni's 4341 Kharan Mighthammer).",
      })
    end

    -- 3. Burning Steppes Field Leg: `4182 Dragonkin Menace` + 12 Thaurissan Relics (`3701` -> "ready_to_turn_in")
    -- Astra P0: Advance the Burning Steppes field leg as soon as the 12 relics are collected (`3701` is "ready_to_turn_in" or "turned_in") AND `4182` is turned in!
    if q4182 ~= "turned_in" or not isReadyOrDone(q3701) then
      if q4182 == "absent" then
        return makeStep({
          stepID = "CORE_2A_BS_ACCEPT_4182",
          track = "core_attune",
          shortTitle = "P2.1: Accept Dragonkin Menace (Helendis, BS)",
          navigationMode = "OUTDOOR_ARROW",
          destination = { uiMapID = 1428, x01 = 0.854, y01 = 0.688, zoneName = "Burning Steppes" },
          arrivalRadiusYards = 20,
          npcName = "Helendis Riverhorn",
          questID = 4182,
          detailText = "Accept 4182 Dragonkin Menace from Helendis Riverhorn at Morgan's Vigil (85.4, 68.8).",
        })
      end
      if q4182 == "ready_to_turn_in" then
        return makeStep({
          stepID = "CORE_2B_BS_TURNIN_4182",
          track = "core_attune",
          shortTitle = "P2.1: Turn in Dragonkin Menace (Helendis, BS)",
          navigationMode = "OUTDOOR_ARROW",
          destination = { uiMapID = 1428, x01 = 0.854, y01 = 0.688, zoneName = "Burning Steppes" },
          arrivalRadiusYards = 20,
          npcName = "Helendis Riverhorn",
          questID = 4182,
          detailText = "Turn in 4182 Dragonkin Menace to Helendis Riverhorn (85.4, 68.8) and accept 4183 The True Masters.",
        })
      end
      if q4182 == "active" then
        return makeStep({
          stepID = "CORE_2A_BS_SLAY_DRAGONKIN",
          track = "core_attune",
          shortTitle = "P2.1: Slay Dragonkin for 4182 (Burning Steppes)",
          navigationMode = "OUTDOOR_ARROW",
          destination = { uiMapID = 1428, x01 = 0.890, y01 = 0.560, zoneName = "Burning Steppes" },
          arrivalRadiusYards = 30,
          questID = 4182,
          detailText = "Slay 15 Black Broodlings, 10 Black Dragonspawn, 4 Black Wyrmkin, and 1 Black Drake (skin for Black Dragonscale & Pristine Scale), then turn in 4182 to Helendis Riverhorn (85.4, 68.8).",
        })
      end
      -- `4182` is turned in, now finish collecting 12 Thaurissan Relics for `3701` (`q3701 == "active"`)
      local relicCount = (q[3701] and tonumber(q[3701].fulfilledCount)) or 0
      return makeStep({
        stepID = "CORE_2C_BS_COLLECT_12_RELICS",
        track = "core_attune",
        shortTitle = string.format("P2.2: Collect Thaurissan Relics (%d/12, BS)", math.min(12, relicCount)),
        navigationMode = "OUTDOOR_ARROW",
        destination = { uiMapID = 1428, x01 = 0.650, y01 = 0.400, zoneName = "Burning Steppes" },
        arrivalRadiusYards = 28,
        questID = 3701,
        detailText = "Click 12 Thaurissan Relics in the Ruins of Thaurissan (65.0, 40.0). Once 12/12 are collected (3701 ready to turn in), advance immediately without waiting for Ironforge turn-in.",
      })
    end

    -- 4. Courier Hop: Helendis -> Solomon (24.8, 44.2) -> Bolvar (80.0, 38.6) -> Prestor -> Bolvar -> Solomon -> Maxwell -> Ragged John -> Maxwell (`4241`)
    if q4183 ~= "turned_in" then
      local needPickup = (q4183 == "absent")
      return makeStep({
        stepID = "CORE_3A_LAKESHIRE_4183",
        track = "core_attune",
        shortTitle = needPickup and "P2.3: Accept 4183 from Helendis (BS)" or "P2.3: Deliver 4183 to Solomon (Redridge)",
        navigationMode = "OUTDOOR_ARROW",
        destination = needPickup
          and { uiMapID = 1428, x01 = 0.854, y01 = 0.688, zoneName = "Burning Steppes" }
          or { uiMapID = 1433, x01 = 0.248, y01 = 0.442, zoneName = "Redridge Mountains" },
        arrivalRadiusYards = 18,
        npcName = needPickup and "Helendis Riverhorn" or "Magistrate Solomon",
        questID = 4183,
        detailText = "Deliver 4183 The True Masters to Magistrate Solomon in Lakeshire Town Hall (24.8, 44.2) and accept 4184.",
      })
    end

    if q4184 ~= "turned_in" or q4185 ~= "turned_in" then
      return makeStep({
        stepID = "CORE_3B_SW_BOLVAR_4184_4185",
        track = "core_attune",
        shortTitle = "P2.4: Bolvar & Lady Prestor (SW Keep 80.0, 38.6)",
        navigationMode = "OUTDOOR_ARROW",
        destination = { uiMapID = 1453, x01 = 0.800, y01 = 0.386, zoneName = "Stormwind City" },
        arrivalRadiusYards = 18,
        npcName = "Highlord Bolvar Fordragon",
        questID = (q4184 ~= "turned_in") and 4184 or 4185,
        detailText = "Use Teleport: Stormwind (3561) if reagents available. Turn in 4184 to Highlord Bolvar Fordragon (80.0, 38.6), accept 4185, speak to Lady Katrana Prestor beside him, turn in 4185 to Bolvar, and accept 4186.",
      })
    end

    if q4186 ~= "turned_in" then
      return makeStep({
        stepID = "CORE_3C_LAKESHIRE_4186",
        track = "core_attune",
        shortTitle = "P2.5: Return Decree (4186) to Solomon (Redridge)",
        navigationMode = "OUTDOOR_ARROW",
        destination = { uiMapID = 1433, x01 = 0.248, y01 = 0.442, zoneName = "Redridge Mountains" },
        arrivalRadiusYards = 18,
        npcName = "Magistrate Solomon",
        questID = 4186,
        detailText = "Turn in 4186 to Magistrate Solomon in Lakeshire (24.8, 44.2) and accept 4223.",
      })
    end

    if q4223 ~= "turned_in" or q4224 ~= "turned_in" or q4241 == "absent" then
      local atJohn = (q4223 == "turned_in" and q4224 == "active")
      return makeStep({
        stepID = "CORE_3D_BS_MAXWELL_AND_JOHN",
        track = "core_attune",
        shortTitle = atJohn and "P2.6: Speak to Ragged John (BS 65.0, 23.8)" or "P2.6: Marshal Maxwell at Morgan's Vigil",
        navigationMode = "OUTDOOR_ARROW",
        destination = atJohn
          and { uiMapID = 1428, x01 = 0.650, y01 = 0.238, zoneName = "Burning Steppes" }
          or { uiMapID = 1428, x01 = 0.846, y01 = 0.688, zoneName = "Burning Steppes" },
        arrivalRadiusYards = 20,
        npcName = atJohn and "Ragged John" or "Marshal Maxwell",
        questID = (q4223 ~= "turned_in") and 4223 or ((q4224 ~= "turned_in") and 4224 or 4241),
        detailText = "Turn in 4223 to Marshal Maxwell (84.6, 68.8) -> accept 4224 -> listen to Ragged John (65.0, 23.8) -> return to Marshal Maxwell (84.6, 68.8) and accept 4241 Marshal Windsor.",
      })
    end

    -- 5. Mandatory Ironforge Relic Turn-In (`3701`) & `4341 Kharan Mighthammer` Pickup Before BRD
    if q3701 ~= "turned_in" or q4341 == "absent" then
      local atArchesonus = (q3701 ~= "turned_in")
      return makeStep({
        stepID = "CORE_3E_IF_ARCHESONUS_AND_MAGNI",
        track = "core_attune",
        shortTitle = atArchesonus and "P2.7: Turn in 3701 Relics to Archesonus (IF)" or "P2.7: Accept 4341 Kharan from King Magni (IF)",
        navigationMode = "OUTDOOR_ARROW",
        destination = atArchesonus
          and { uiMapID = 1455, x01 = 0.384, y01 = 0.554, zoneName = "Ironforge" }
          or { uiMapID = 1455, x01 = 0.394, y01 = 0.558, zoneName = "Ironforge" },
        arrivalRadiusYards = 18,
        npcName = atArchesonus and "Royal Historian Archesonus" or "King Magni Bronzebeard",
        questID = atArchesonus and 3701 or 4341,
        detailText = "Use Teleport: Ironforge (3562). Turn 3701 in to Royal Historian Archesonus (38.4, 55.4), then accept 4341 Kharan Mighthammer from King Magni Bronzebeard (39.4, 55.8) before entering BRD.",
      })
    end

    -- 6. Short BRD Detention Party Hop (`4241 -> 4242` & `4341 -> 4342 -> 4361`)
    if (q4241 ~= "turned_in" and not isActiveOrDone(q4242)) or (q4341 ~= "turned_in" and not isActiveOrDone(q4361)) then
      return makeStep({
        stepID = "CORE_4A_BRD_DETENTION_HOP",
        track = "core_attune",
        shortTitle = "P3.1: BRD Detention Hop (Windsor & Kharan)",
        navigationMode = snap.inInstance and "INSTANCE_OBJECTIVE" or "OUTDOOR_ARROW",
        destination = { uiMapID = 1428, x01 = 0.290, y01 = 0.375, zoneName = "Burning Steppes" },
        arrivalRadiusYards = 25,
        npcName = "Marshal Windsor & Kharan Mighthammer",
        questID = 4241,
        mcAttuneNote = "7848 Attunement to the Core is non-blocking (deferred on build 70862 unless active); Shadowforge Key (3801/3802) is optional convenience.",
        detailText = "Enter BRD Detention Block with a small party. Get Prison Cell Key from High Interrogator Gerstahn (rolls: Kentic Amice 11624) or confirm cell access. Speak to Marshal Windsor (4241 -> accept 4242 Abandoned Hope) and Kharan Mighthammer (4341 -> 4342 -> accept 4361 The Bearer of Bad News).",
      })
    end

    -- 7. Turn in `4242 Abandoned Hope` (Morgan's Vigil) & `4361 The Bearer of Bad News` -> Accept `4362` (Ironforge)
    if q4242 ~= "turned_in" then
      return makeStep({
        stepID = "CORE_4B_BS_TURNIN_4242",
        track = "core_attune",
        shortTitle = "P3.2: Turn in 4242 Abandoned Hope (Maxwell, BS)",
        navigationMode = "OUTDOOR_ARROW",
        destination = { uiMapID = 1428, x01 = 0.846, y01 = 0.688, zoneName = "Burning Steppes" },
        arrivalRadiusYards = 20,
        npcName = "Marshal Maxwell",
        questID = 4242,
        detailText = "Turn in 4242 Abandoned Hope to Marshal Maxwell at Morgan's Vigil (84.6, 68.8). Turning in 4242 unlocks A Crumpled Up Note (11446) drops!",
      })
    end

    if q4361 ~= "turned_in" or q4362 == "absent" then
      return makeStep({
        stepID = "CORE_4C_IF_TURNIN_4361_ACCEPT_4362",
        track = "core_attune",
        shortTitle = "P3.3: Turn in 4361 & Accept 4362 (King Magni, IF)",
        navigationMode = "OUTDOOR_ARROW",
        destination = { uiMapID = 1455, x01 = 0.394, y01 = 0.558, zoneName = "Ironforge" },
        arrivalRadiusYards = 18,
        npcName = "King Magni Bronzebeard",
        questID = (q4361 ~= "turned_in") and 4361 or 4362,
        detailText = "Use Teleport: Ironforge (3562). Turn in 4361 The Bearer of Bad News to King Magni Bronzebeard (39.4, 55.8) and accept 4362 The Fate of the Kingdom.",
      })
    end

    -- 8. Crumpled Note (`11446` -> `4264` -> `4282`) + ONE Full BRD Clear (`4282` + `4322 Jail Break!` + `4362 Emperor`)
    if q4264 == "absent" and q4282 == "absent" and q4322 == "absent" then
      if getBag(11446) == 0 then
        return makeStep({
          stepID = "CORE_5A_FARM_CRUMPLED_NOTE",
          track = "core_attune",
          shortTitle = "P4.1: Loot A Crumpled Up Note (11446, BRM/BRD)",
          navigationMode = snap.inInstance and "INSTANCE_OBJECTIVE" or "OUTDOOR_ARROW",
          destination = { uiMapID = 1428, x01 = 0.290, y01 = 0.375, zoneName = "Burning Steppes" },
          arrivalRadiusYards = 25,
          questID = 4264,
          detailText = "4242 is turned in. Farm A Crumpled Up Note (11446) from eligible Quarry Slaves outside BRD while assembling your full-clear group (or from Dark Iron dwarves inside BRD), then right-click 11446 to start 4264.",
        })
      end
      return makeStep({
        stepID = "CORE_5B_USE_NOTE_AND_ACCEPT_4282",
        track = "core_attune",
        shortTitle = "P4.1: Use Note (11446) -> Accept 4282 from Windsor",
        navigationMode = snap.inInstance and "INSTANCE_OBJECTIVE" or "OUTDOOR_ARROW",
        destination = { uiMapID = 1428, x01 = 0.290, y01 = 0.375, zoneName = "Burning Steppes" },
        arrivalRadiusYards = 25,
        npcName = "Marshal Windsor",
        questID = 4264,
        detailText = "Right-click A Crumpled Up Note (11446) in your bags to accept 4264, turn it in to Marshal Windsor inside BRD Detention Block, and accept 4282 A Shred of Hope BEFORE killing General Angerforge and Golem Lord Argelmach!",
      })
    end

    if not isReadyOrDone(q4322) or (not isReadyOrDone(q4362) and not isActiveOrDone(q4363)) then
      return makeStep({
        stepID = "CORE_5C_BRD_FULL_CLEAR_ESCORT_EMPEROR",
        track = "core_attune",
        shortTitle = "P4.2: BRD Full Clear: 4282, Jail Break! & Emperor",
        navigationMode = "INSTANCE_OBJECTIVE",
        destination = { uiMapID = 1428, x01 = 0.290, y01 = 0.375, zoneName = "Burning Steppes" },
        arrivalRadiusYards = 25,
        questID = (not isReadyOrDone(q4322)) and 4322 or 4362,
        detailText = "1) With 4282 active, kill General Angerforge & Golem Lord Argelmach (Omnicast Boots 11822) and turn in 4282 to Windsor. 2) Clear escort path, start 4322 Jail Break!, and confirm escort completion credit before leaving! 3) Continue to Emperor Dagran Thaurissan (passing Stilgiss Boreal Mantle 11782 & Incendius Flameweave Cuffs 11766) with 4362 active, keep Princess Moira alive, turn in 4362 to Moira, and accept 4363.",
      })
    end

    if q4363 ~= "turned_in" then
      return makeStep({
        stepID = "CORE_5D_IF_TURNIN_4363_SONGSTONE",
        track = "core_attune",
        shortTitle = "P4.3: Turn in 4363 -> Choose Songstone (Magni, IF)",
        navigationMode = "OUTDOOR_ARROW",
        destination = { uiMapID = 1455, x01 = 0.394, y01 = 0.558, zoneName = "Ironforge" },
        arrivalRadiusYards = 18,
        npcName = "King Magni Bronzebeard",
        questID = 4363,
        detailText = "Turn in 4363 The Princess's Surprise to King Magni Bronzebeard (39.4, 55.8) in Ironforge and choose Songstone of Ironforge (12543, +18 SP Ring)!",
      })
    end

    if q4322 ~= "turned_in" or q6402 == "absent" then
      return makeStep({
        stepID = "CORE_5E_BS_TURNIN_4322_ACCEPT_6402",
        track = "core_attune",
        shortTitle = "P4.4: Turn in Jail Break! (4322) to Maxwell (BS)",
        navigationMode = "OUTDOOR_ARROW",
        destination = { uiMapID = 1428, x01 = 0.846, y01 = 0.688, zoneName = "Burning Steppes" },
        arrivalRadiusYards = 20,
        npcName = "Marshal Maxwell",
        questID = 4322,
        detailText = "Turn in 4322 Jail Break! to Marshal Maxwell at Morgan's Vigil (84.6, 68.8) and accept 6402 Stormwind Rendezvous.",
      })
    end

    -- 9. Stormwind Masquerade (`6402` -> `6403` OR `99435` -> `6501 The Dragon's Eye`)
    local masqueradeDone = (q6403 == "turned_in") or (q99435 == "turned_in") or isActiveOrDone(q6501)
    if not masqueradeDone or q6501 == "absent" then
      local atKeep = (q6403 == "ready_to_turn_in" or q99435 == "ready_to_turn_in" or q6403 == "turned_in" or q99435 == "turned_in")
      return makeStep({
        stepID = "CORE_6A_SW_MASQUERADE_6402_6403_99435",
        track = "core_attune",
        shortTitle = atKeep and "P5.1: Turn in Masquerade & Accept 6501 (Bolvar, SW)" or "P5.1: Stormwind Gates (Rowe/Windsor: 6402 -> 6403/99435)",
        navigationMode = "OUTDOOR_ARROW",
        destination = atKeep
          and { uiMapID = 1453, x01 = 0.800, y01 = 0.386, zoneName = "Stormwind City" }
          or { uiMapID = 1453, x01 = 0.640, y01 = 0.740, zoneName = "Stormwind City" },
        arrivalRadiusYards = 22,
        npcName = atKeep and "Highlord Bolvar Fordragon" or "Squire Rowe / Reginald Windsor",
        questID = atKeep and 6501 or ((isActiveOrDone(q99435) and 99435) or (isActiveOrDone(q6403) and 6403) or 6402),
        acceptedMasqueradeVariantIDs = { 6403, 99435 },
        detailText = "Use Teleport: Stormwind (3561). Meet Squire Rowe / Reginald Windsor at the Stormwind City Gates (supports both Forever variant 99435 and Classic 6403), escort Windsor to Highlord Bolvar Fordragon in Stormwind Keep (80.0, 38.6), turn in Masquerade, and accept 6501 The Dragon's Eye.",
      })
    end

    -- 10. Winterspring Mazthoril Cave -> Rune (`52.8, 55.8`) -> Haleh (`54.5, 51.3`) to accept `6502 Drakefire Amulet`
    if q6501 ~= "turned_in" or q6502 == "absent" then
      return makeStep({
        stepID = "CORE_6B_WS_MAZTHORIL_HALEH_6501",
        track = "core_attune",
        shortTitle = "P5.2: Mazthoril Rune (52.8, 55.8) -> Haleh (54.5, 51.3)",
        navigationMode = "OUTDOOR_ARROW",
        destination = { uiMapID = 1452, x01 = 0.528, y01 = 0.558, zoneName = "Winterspring" },
        secondaryDestination = { uiMapID = 1452, x01 = 0.545, y01 = 0.513, zoneName = "Winterspring" },
        arrivalRadiusYards = 18,
        npcName = "Matron Protectorate Haleh",
        questID = 6501,
        detailText = "Enter Mazthoril cave in Winterspring, step onto the blue teleport rune inside the cave (52.8, 55.8) to reach Matron Protectorate Haleh above (54.5, 51.3), turn in 6501 The Dragon's Eye, and accept 6502 Drakefire Amulet. Reserve return visit to Haleh until after Drakkisath!",
      })
    end

    -- 11. Optional LBRS Pre-Step (`12780 General Drakkisath's Command` -> `5089` -> `5102`) so `Eye of the Beast` completes on the same UBRS Drakkisath kill
    if not skipped["CORE_7A_LBRS_COMMAND"] and not isActiveOrDone(q5102) then
      if q5089 == "active" or q5089 == "ready_to_turn_in" then
        return makeStep({
          stepID = "CORE_7A_BS_TURNIN_5089_ACCEPT_5102",
          track = "core_attune",
          optional = true,
          shortTitle = "P5.3: Turn in 5089 -> Accept 5102 Demise (Maxwell, BS)",
          navigationMode = "OUTDOOR_ARROW",
          destination = { uiMapID = 1428, x01 = 0.846, y01 = 0.688, zoneName = "Burning Steppes" },
          arrivalRadiusYards = 20,
          npcName = "Marshal Maxwell",
          questID = 5089,
          detailText = "Turn in 5089 General Drakkisath's Command to Marshal Maxwell (84.6, 68.8) and accept 5102 General Drakkisath's Demise before entering UBRS.",
        })
      end
      if getBag(12780) > 0 then
        return makeStep({
          stepID = "CORE_7A_USE_COMMAND_12780",
          track = "core_attune",
          optional = true,
          shortTitle = "P5.3: Right-Click Drakkisath's Command (12780) -> Maxwell",
          navigationMode = snap.inInstance and "INSTANCE_OBJECTIVE" or "OUTDOOR_ARROW",
          destination = { uiMapID = 1428, x01 = 0.846, y01 = 0.688, zoneName = "Burning Steppes" },
          arrivalRadiusYards = 20,
          npcName = "Marshal Maxwell",
          questID = 5089,
          detailText = "Right-click General Drakkisath's Command (12780) in your bags to accept 5089, then turn it in to Marshal Maxwell (84.6, 68.8) for 5102 General Drakkisath's Demise.",
        })
      end
      local wing, wingHint = RaidReadinessCoach.ResolveBlackrockSpireWing(snap.subzoneText, "CORE_7A_LBRS_COMMAND")
      return makeStep({
        stepID = "CORE_7A_LBRS_COMMAND",
        track = "core_attune",
        optional = true,
        shortTitle = "P5.3 (Opt): LBRS Wyrmthalak for Command (12780)",
        navigationMode = snap.inInstance and "INSTANCE_OBJECTIVE" or "OUTDOOR_ARROW",
        destination = { uiMapID = 1428, x01 = 0.290, y01 = 0.375, zoneName = "Burning Steppes" },
        arrivalRadiusYards = 25,
        brsWing = wing,
        brsWingHint = wingHint,
        npcName = "Overlord Wyrmthalak",
        questID = 5089,
        detailText = "Run LBRS before UBRS if you want Eye of the Beast (13968) from the same Drakkisath kill: roll on Highlord Omokk Skyshroud Leggings (13170, 30 SP), Quartermaster Zigris Hands of Power (13253), and Overlord Wyrmthalak Trindlehaven Staff (13161, 70 SP + 6 MP5) + loot General Drakkisath's Command (12780).",
      })
    end

    -- 12. Planned UBRS Kill (`6502` + `5102`) & Post-Drakkisath Dual Verification (Astra P0)
    local hasBlood = (getBag(16663) > 0) or isReadyOrDone(q6502)
    local drakkKilledFor5102 = isReadyOrDone(q5102)
    if q6502 ~= "turned_in" and not hasBlood then
      local wing, wingHint = RaidReadinessCoach.ResolveBlackrockSpireWing(snap.subzoneText, "CORE_7B_UBRS_DRAKKISATH")
      if drakkKilledFor5102 then
        -- Astra P0: Killed Drakkisath for 5102 without looting Blood of the Black Dragon Champion (16663) for 6502!
        return makeStep({
          stepID = "CORE_7B_DRAKKISATH_MISSING_BLOOD_RECOVERY",
          track = "core_attune",
          isRecoveryStep = true,
          shortTitle = "P5.4 RECOVERY: Loot Blood (16663) from Drakkisath!",
          navigationMode = "INSTANCE_OBJECTIVE",
          destination = { uiMapID = 1428, x01 = 0.290, y01 = 0.375, zoneName = "Burning Steppes" },
          brsWing = wing,
          brsWingHint = wingHint,
          npcName = "General Drakkisath",
          questID = 6502,
          detailText = "WARNING: 5102 General Drakkisath's Demise shows kill credit, but Blood of the Black Dragon Champion (16663) is NOT in your bags for 6502 Drakefire Amulet! Loot Drakkisath's corpse immediately (or re-kill Drakkisath with 6502 active) before traveling to Winterspring!",
        })
      end
      return makeStep({
        stepID = "CORE_7B_UBRS_DRAKKISATH",
        track = "core_attune",
        shortTitle = "P5.4: UBRS Drakkisath (Blood 16663 + 5102 Kill)",
        navigationMode = snap.inInstance and "INSTANCE_OBJECTIVE" or "OUTDOOR_ARROW",
        destination = { uiMapID = 1428, x01 = 0.290, y01 = 0.375, zoneName = "Burning Steppes" },
        arrivalRadiusYards = 25,
        brsWing = wing,
        brsWingHint = wingHint,
        npcName = "General Drakkisath",
        questID = 6502,
        detailText = "Enter UBRS with 6502 active (and 5102 active for Eye of the Beast) + a Seal of Ascension holder. Fish for Jed Runewatcher (Briarwood Reed 12930, 29 SP), kill General Drakkisath (roll on Spellweaver's Turban 22267), and verify BOTH 5102 kill credit AND Blood of the Black Dragon Champion (16663) in your bags!",
      })
    end

    -- 13. Turn in `5102 General Drakkisath's Demise` -> Choose `Eye of the Beast (13968)`
    if q5102 == "ready_to_turn_in" then
      return makeStep({
        stepID = "CORE_7C_BS_TURNIN_5102_EYE_OF_THE_BEAST",
        track = "core_attune",
        shortTitle = "P5.5: Turn in 5102 -> Choose Eye of the Beast (BS)",
        navigationMode = "OUTDOOR_ARROW",
        destination = { uiMapID = 1428, x01 = 0.846, y01 = 0.688, zoneName = "Burning Steppes" },
        arrivalRadiusYards = 20,
        npcName = "Marshal Maxwell",
        questID = 5102,
        detailText = "Turn in 5102 General Drakkisath's Demise to Marshal Maxwell at Morgan's Vigil (84.6, 68.8) and choose Eye of the Beast (13968, 1% passive Spell Crit + 7% Spell Hit on-use)!",
      })
    end

    -- 14. Turn in `6502 Drakefire Amulet` to Haleh in Winterspring (`52.8, 55.8` rune -> `54.5, 51.3` Haleh)
    if q6502 ~= "turned_in" then
      return makeStep({
        stepID = "CORE_7D_WS_TURNIN_6502_DRAKEFIRE",
        track = "core_attune",
        shortTitle = "P5.6: Turn in 6502 to Haleh -> Drakefire Amulet",
        navigationMode = "OUTDOOR_ARROW",
        destination = { uiMapID = 1452, x01 = 0.528, y01 = 0.558, zoneName = "Winterspring" },
        secondaryDestination = { uiMapID = 1452, x01 = 0.545, y01 = 0.513, zoneName = "Winterspring" },
        arrivalRadiusYards = 18,
        npcName = "Matron Protectorate Haleh",
        questID = 6502,
        detailText = "Enter Mazthoril cave in Winterspring, step onto the teleport rune (52.8, 55.8), and turn in 6502 to Matron Protectorate Haleh (54.5, 51.3) to receive Drakefire Amulet (16309).",
      })
    end

    -- 15. Post-`6502` Amulet Carrier Audit (Astra P0: separate 6502 completion from carrying 16309!)
    if not amuletCarried then
      if amuletInBank then
        return makeStep({
          stepID = "CORE_7E_WITHDRAW_BANKED_AMULET",
          track = "core_attune",
          isRecoveryStep = true,
          shortTitle = "P5.7 RECOVERY: Withdraw Drakefire Amulet from Bank!",
          navigationMode = "OUTDOOR_ARROW",
          destination = { uiMapID = 1452, x01 = 0.614, y01 = 0.370, zoneName = "Winterspring" },
          arrivalRadiusYards = 20,
          detailText = "6502 Drakefire Amulet is turned in, but Drakefire Amulet (16309) is in your BANK! Every raider must carry 16309 in their bags (or equip it) to enter Onyxia's Lair.",
        })
      elseif snap.bankReadable then
        return makeStep({
          stepID = "CORE_7F_RECOVER_MISSING_AMULET",
          track = "core_attune",
          isRecoveryStep = true,
          shortTitle = "P5.7 RECOVERY: Reclaim Drakefire Amulet from Haleh!",
          navigationMode = "OUTDOOR_ARROW",
          destination = { uiMapID = 1452, x01 = 0.528, y01 = 0.558, zoneName = "Winterspring" },
          secondaryDestination = { uiMapID = 1452, x01 = 0.545, y01 = 0.513, zoneName = "Winterspring" },
          arrivalRadiusYards = 18,
          npcName = "Matron Protectorate Haleh",
          detailText = "6502 is turned in, but Drakefire Amulet (16309) is missing from both your bags and bank. Speak to Matron Protectorate Haleh at Mazthoril (54.5, 51.3) to restore your amulet.",
        })
      else
        return makeStep({
          stepID = "CORE_7E_VERIFY_BANK_FOR_AMULET",
          track = "core_attune",
          isRecoveryStep = true,
          shortTitle = "P5.7 RECOVERY: Open Bank to Withdraw Drakefire Amulet",
          navigationMode = "OUTDOOR_ARROW",
          destination = { uiMapID = 1455, x01 = 0.356, y01 = 0.606, zoneName = "Ironforge" },
          arrivalRadiusYards = 20,
          detailText = "6502 is turned in, but Drakefire Amulet (16309) is not in your bags and your Bank has not been opened this session. Open your Bank and move 16309 into your bags.",
        })
      end
    end

    return makeStep({
      stepID = "CORE_COMPLETE_ATTUNED_AND_CARRIED",
      track = "core_attune",
      isComplete = true,
      shortTitle = "Onyxia attuned · amulet carried",
      navigationMode = "INSTANCE_OBJECTIVE",
      detailText = "Onyxia attuned · amulet carried (Drakefire Amulet 16309 verified in bags/equipped) & Princess chain complete!",
    })
  end

  local coreStep = resolveCoreAction()
  local linkenStep = resolveLinkenAction()
  local activeStep = (snap.activeTrack == "linken_solo") and linkenStep or coreStep

  local result = {
    schemaVersion = RaidReadinessCoach.SCHEMA_VERSION,
    activeTrack = snap.activeTrack,
    hydrationPending = snap.hydrationPending,
    unknownQuestIDs = snap.unknownQuestIDs,
    pendingMetadataSlots = snap.pendingMetadataSlots,
    bankReadable = snap.bankReadable,
    onyxiaAttunedAndCarried = onyxiaAttunedAndCarried,
    onyxiaStatusLabel = onyxiaStatusLabel,
    aquementasStatus = aquementasStatus,
    mcAttunementStatus = (qState(7848) == "turned_in") and "attuned" or "deferred_non_blocking_build_70862",
    activeStep = activeStep,
    coreNextStep = coreStep,
    linkenNextStep = linkenStep,
    professionStatus = professionStatus,
    gearScorecard = gearScorecard,
    travelNote = travelNote,
  }
  RaidReadinessCoach.lastEvaluation = result
  return result
end

-- World-generation-scoped hydration retry scheduler (`0.25, 0.5, 1, 2` seconds) & burst coalescer (Astra P0)
function RaidReadinessCoach.RequestCoalescedRefresh(isWorldTransition)
  if isWorldTransition then
    RaidReadinessCoach.worldGeneration = (RaidReadinessCoach.worldGeneration or 0) + 1
  end
  local gen = RaidReadinessCoach.worldGeneration
  local eval = RaidReadinessCoach.Evaluate()
  if ns.UI and ns.UI.Navigation and type(ns.UI.Navigation.SyncFromRaidReadinessCoach) == "function" then
    local store = ensureCharRaidReadinessStore()
    if store.coachEnabled == true then
      pcall(ns.UI.Navigation.SyncFromRaidReadinessCoach, eval)
    end
  end

  if eval.hydrationPending and isWorldTransition and _G.C_Timer and type(_G.C_Timer.After) == "function" then
    for _, delaySec in ipairs(RaidReadinessCoach.RETRY_DELAYS_SECONDS) do
      pcall(_G.C_Timer.After, delaySec, function()
        if RaidReadinessCoach.worldGeneration ~= gen then
          return
        end
        local reEval = RaidReadinessCoach.Evaluate()
        if ns.UI and ns.UI.Navigation and type(ns.UI.Navigation.SyncFromRaidReadinessCoach) == "function" then
          local st = ensureCharRaidReadinessStore()
          if st.coachEnabled == true then
            pcall(ns.UI.Navigation.SyncFromRaidReadinessCoach, reEval)
          end
        end
      end)
    end
  end
  return eval
end

return PortfolioTriage
