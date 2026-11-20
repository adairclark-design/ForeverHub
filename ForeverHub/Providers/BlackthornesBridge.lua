local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.Providers = ns.Providers or {}

local BlackthornesBridge = {}
ns.Providers.BlackthornesBridge = BlackthornesBridge

BlackthornesBridge.SCHEMA_VERSION = 1
BlackthornesBridge.DEFAULT_FULL_SWEEP_EPOCH = 1795027794
BlackthornesBridge.AH_PAID_RETENTION_SECONDS = 7 * 86400

local function isPositiveInt(v)
  return type(v) == "number" and v == v and v >= 1 and v < 9007199254740992 and math.floor(v) == v
end

local function isNonNegInt(v)
  return type(v) == "number" and v == v and v >= 0 and v < 9007199254740992 and math.floor(v) == v
end

local function shallowCopyNumberMap(src, maxEntries)
  local out = {}
  if type(src) ~= "table" then
    return out
  end
  local limit = tonumber(maxEntries) or 2000
  local count = 0
  for k, v in pairs(src) do
    local id = tonumber(k)
    local qty = tonumber(v)
    if isPositiveInt(id) and isPositiveInt(qty) then
      out[id] = math.floor(qty)
      count = count + 1
      if count >= limit then
        break
      end
    end
  end
  return out
end

local function boundedCopyLadder(rawLadder, maxEntries)
  local out = {}
  if type(rawLadder) ~= "table" then
    return out
  end
  local limit = math.min(#rawLadder, tonumber(maxEntries) or 40)
  for i = 1, limit do
    out[i] = rawLadder[i]
  end
  return out
end

-- Resolves character record strictly on GUID + exact realm + exact faction (Astra P0/Blindspot:
-- first name + realm is ambiguous in Forever; never join on name + realm alone).
function BlackthornesBridge.ResolveCharacterRecord(opts)
  opts = type(opts) == "table" and opts or {}
  local db = opts.blackthornesDB or _G.BlackthornesTSDB
  if type(db) ~= "table" or type(db.characters) ~= "table" then
    return nil, "blackthornes_db_unavailable"
  end

  local guid = opts.characterGUID
  if type(guid) ~= "string" or guid == "" then
    if type(_G.UnitGUID) == "function" then
      local okG, liveG = pcall(_G.UnitGUID, "player")
      if okG and type(liveG) == "string" and liveG ~= "" then
        guid = liveG
      end
    end
  end
  if type(guid) ~= "string" or guid == "" then
    return nil, "missing_character_guid"
  end

  local realm = opts.realmName
  if type(realm) ~= "string" or realm == "" then
    if type(_G.GetRealmName) == "function" then
      local okR, liveR = pcall(_G.GetRealmName)
      if okR and type(liveR) == "string" and liveR ~= "" then
        realm = liveR
      end
    end
  end

  local faction = opts.faction
  if type(faction) ~= "string" or faction == "" then
    if ns.Compat and type(ns.Compat.GetPlayerFactionString) == "function" then
      faction = ns.Compat.GetPlayerFactionString()
    elseif type(_G.UnitFactionGroup) == "function" then
      local okF, liveF = pcall(_G.UnitFactionGroup, "player")
      if okF and type(liveF) == "string" then
        faction = liveF
      end
    end
  end

  if type(realm) ~= "string" or realm == "" or type(faction) ~= "string" or faction == "" then
    return nil, "missing_realm_or_faction_identity"
  end

  local charRec = db.characters[guid]
  if type(charRec) ~= "table" then
    return nil, "character_guid_not_found"
  end
  if tostring(charRec.guid or guid) ~= guid then
    return nil, "character_guid_mismatch"
  end
  if tostring(charRec.realm or "") ~= realm then
    return nil, "character_realm_mismatch"
  end
  if tostring(charRec.faction or "") ~= faction then
    return nil, "character_faction_mismatch"
  end

  return {
    guid = guid,
    name = tostring(charRec.name or ""),
    realm = realm,
    faction = faction,
    realmFactionKey = string.format("%s-%s", realm, faction),
    seenAt = tonumber(charRec.seenAt),
    level = tonumber(charRec.level),
    goldCopper = tonumber(charRec.gold),
    record = charRec,
  }
end

-- Reads per-item price & ladder snapshot from BlackthornesTSDB.prices[realmFactionKey]
-- (never uses BlackthornesTS_API.GetPrice as a fresh local scan because PublicAPI can return fallback values).
function BlackthornesBridge.GetItemMarketSnapshot(itemID, opts)
  opts = type(opts) == "table" and opts or {}
  local id = tonumber(itemID)
  if not isPositiveInt(id) then
    return nil, "invalid_item_id"
  end
  local db = opts.blackthornesDB or _G.BlackthornesTSDB
  local realmFactionKey = opts.realmFactionKey
  if type(realmFactionKey) ~= "string" or realmFactionKey == "" then
    local charInfo = BlackthornesBridge.ResolveCharacterRecord(opts)
    realmFactionKey = charInfo and charInfo.realmFactionKey or nil
  end
  if type(realmFactionKey) ~= "string" or realmFactionKey == "" then
    return nil, "missing_market_identity"
  end

  local pricesRoot = (type(db) == "table" and type(db.prices) == "table") and db.prices[realmFactionKey] or nil
  if type(pricesRoot) ~= "table" then
    return nil, "realm_prices_unavailable"
  end

  local itemsTbl = type(pricesRoot.items) == "table" and pricesRoot.items or pricesRoot
  local rec = type(itemsTbl) == "table" and itemsTbl[id] or nil
  if type(rec) ~= "table" then
    return nil, "item_price_not_found"
  end

  local nowEpoch = tonumber(opts.nowEpoch) or 0
  local lastFullScanAt = tonumber(pricesRoot.lastFullScanAt or pricesRoot.scanAt or opts.lastFullScanAt) or BlackthornesBridge.DEFAULT_FULL_SWEEP_EPOCH
  local ladderAt = tonumber(rec.ladderAt or rec.at or opts.ladderAt) or lastFullScanAt
  local rawLadder = boundedCopyLadder(rec.ladder, 40)

  local sgr = ns.Domain and ns.Domain.SupplyGlutResearch
  local ladderEval = nil
  if sgr and type(sgr.EvaluateSavedLadderSnapshot) == "function" then
    ladderEval = sgr.EvaluateSavedLadderSnapshot({
      itemID = id,
      marketIdentity = realmFactionKey,
      requireMarketIdentity = true,
      ladder = rawLadder,
      rowPriceFixed = (rec.rowPriceFixed == true),
      commodityPartialFillVerified = (opts.commodityPartialFillVerified == true),
      ladderAt = ladderAt,
      lastFullScanAt = lastFullScanAt,
      nowEpoch = nowEpoch,
      maxFreshAgeSeconds = opts.maxFreshAgeSeconds,
      maxClockSkewSeconds = opts.maxClockSkewSeconds,
      maxUnitPriceCopper = opts.maxUnitPriceCopper,
      targetUnits = opts.targetUnits,
      totalListedUnits = tonumber(rec.quantity) or 0,
      verifiedVendorUnitCopper = opts.verifiedVendorUnitCopper,
      unitDepositCopper = opts.unitDepositCopper,
      expectedFailedExpirations = opts.expectedFailedExpirations,
    })
  end

  return {
    itemID = id,
    marketIdentity = realmFactionKey,
    marketCopper = tonumber(rec.market),
    ownMinCopper = tonumber(rec.ownMin),
    rowPriceFixed = (rec.rowPriceFixed == true),
    ladderAt = ladderAt,
    lastFullScanAt = lastFullScanAt,
    ladder = rawLadder,
    ladderEvaluation = ladderEval,
  }
end

-- Resolves character holdings with strict anti-double-counting and bank snapshot precedence (Astra Blindspot):
-- 1. Live bags taken ONCE (`opts.liveBags` or `Providers.Inventory.ScanLiveBags()`). Never merged with `charRec.inventory`.
-- 2. Bank snapshot resolved via `Providers.Inventory.ResolveCurrentBankSnapshot` first (preserving valid empty banks!).
--    `charRec.bank` is used ONLY as a labeled fallback (`source = "blackthornes_saved_bank"`) when no complete
--    live/session/external/persisted bank snapshot exists AND `charRec.bankAt` is valid (`<= nowEpoch`) and not partial.
-- 3. Active posted auctions and mail in transit stay strictly outside `spendableHoldings`.
-- 4. Expired auction listings (`ends <= nowEpoch`) are excluded from active sale tests and flagged for reconciliation.
function BlackthornesBridge.BuildUnifiedPortfolioSnapshot(opts)
  opts = type(opts) == "table" and opts or {}
  local nowEpoch = tonumber(opts.nowEpoch) or 0
  local charInfo, errChar = BlackthornesBridge.ResolveCharacterRecord(opts)
  if not charInfo then
    return nil, errChar
  end
  local charRec = charInfo.record
  local db = opts.blackthornesDB or _G.BlackthornesTSDB

  -- 1. Live bags (taken once):
  local liveBags = type(opts.liveBags) == "table"
    and shallowCopyNumberMap(opts.liveBags)
    or ((ns.Providers and ns.Providers.Inventory and type(ns.Providers.Inventory.ScanLiveBags) == "function")
      and shallowCopyNumberMap(ns.Providers.Inventory.ScanLiveBags())
      or {})

  -- 2. Bank precedence (preserve valid empty bank snapshots; never overwrite with stale Blackthornes bank):
  local chosenBank = nil
  if ns.Providers and ns.Providers.Inventory and type(ns.Providers.Inventory.ResolveCurrentBankSnapshot) == "function" then
    chosenBank = ns.Providers.Inventory.ResolveCurrentBankSnapshot(
      opts.liveBankSnapshot,
      opts.externalBankSnapshot,
      opts.cachedBankSnapshot,
      opts.sessionBankObserved == true
    )
  end

  local bankCounts = {}
  local bankSource = "none"
  local bankObservedAt = nil
  local bankAvailable = false
  local bankComplete = false

  if type(chosenBank) == "table" and chosenBank.available == true and chosenBank.complete == true then
    bankCounts = shallowCopyNumberMap(chosenBank.counts)
    bankSource = tostring(chosenBank.source or "live_bank")
    bankObservedAt = tonumber(chosenBank.observedAt)
    bankAvailable = true
    bankComplete = true
  else
    -- Labeled fallback to BlackthornesTSDB.characters[guid].bank ONLY when complete and timestamp-valid:
    local btBankAt = tonumber(charRec.bankAt)
    local btBankPartial = (charRec.bankPartial == true) or (charRec.bankComplete == false)
    if type(charRec.bank) == "table" and isPositiveInt(btBankAt) and (nowEpoch <= 0 or btBankAt <= nowEpoch) and not btBankPartial then
      bankCounts = shallowCopyNumberMap(charRec.bank)
      bankSource = "blackthornes_saved_bank"
      bankObservedAt = btBankAt
      bankAvailable = true
      bankComplete = true
    elseif btBankPartial then
      bankSource = "rejected_partial_blackthornes_bank"
    elseif isPositiveInt(btBankAt) and nowEpoch > 0 and btBankAt > nowEpoch then
      bankSource = "rejected_future_blackthornes_bank_timestamp"
    end
  end

  -- Combine spendable holdings (liveBags + chosenBank ONLY; never auctions or incoming mail):
  local spendableByItemID = {}
  for id, q in pairs(liveBags) do
    spendableByItemID[id] = {
      itemID = id,
      bagCount = q,
      bankCount = 0,
      spendableCount = q,
    }
  end
  for id, q in pairs(bankCounts) do
    local entry = spendableByItemID[id]
    if not entry then
      entry = { itemID = id, bagCount = 0, bankCount = 0, spendableCount = 0 }
      spendableByItemID[id] = entry
    end
    entry.bankCount = q
    entry.spendableCount = entry.bagCount + q
  end

  -- 3. Active vs Expired Posted Auctions (strictly outside spendableHoldings):
  local activeAuctionListings = {}
  local activeAuctionUnitsByItemID = {}
  local expiredAuctionListings = {}
  local postedRealm = (type(db) == "table" and type(db.postedAuctions) == "table") and db.postedAuctions[charInfo.realmFactionKey] or nil
  local postedChar = (type(postedRealm) == "table" and type(postedRealm.byCharacter) == "table") and postedRealm.byCharacter[charInfo.guid] or nil
  local postedUpdatedAt = type(postedChar) == "table" and tonumber(postedChar.updatedAt) or nil

  if type(postedChar) == "table" and type(postedChar.listings) == "table" then
    for _, lst in ipairs(postedChar.listings) do
      if type(lst) == "table" then
        local id = tonumber(lst.itemID)
        local qty = tonumber(lst.quantity)
        local unitPrice = tonumber(lst.unit)
        local endsAt = tonumber(lst.ends)
        if isPositiveInt(id) and isPositiveInt(qty) then
          local rec = {
            itemID = id,
            quantity = math.floor(qty),
            unitPriceCopper = unitPrice and math.floor(unitPrice) or nil,
            endsAt = endsAt,
            updatedAt = postedUpdatedAt,
          }
          if isPositiveInt(endsAt) and nowEpoch > 0 and endsAt <= nowEpoch then
            rec.status = "EXPIRED_RECONCILE_REQUIRED"
            table.insert(expiredAuctionListings, rec)
          else
            rec.status = "ACTIVE_POSTED_LISTING"
            table.insert(activeAuctionListings, rec)
            activeAuctionUnitsByItemID[id] = (activeAuctionUnitsByItemID[id] or 0) + math.floor(qty)
          end
        end
      end
    end
  end

  -- 4. Mail in transit (strictly outside spendableHoldings):
  local mailInTransitByItemID = {}
  if type(charRec.mail) == "table" then
    for k, v in pairs(charRec.mail) do
      local id = tonumber(k)
      local qty = tonumber(v)
      if isPositiveInt(id) and isPositiveInt(qty) then
        mailInTransitByItemID[id] = (mailInTransitByItemID[id] or 0) + math.floor(qty)
      elseif type(v) == "table" and isPositiveInt(tonumber(v.itemID)) and isPositiveInt(tonumber(v.quantity or v.count)) then
        local mID = math.floor(tonumber(v.itemID))
        local mQ = math.floor(tonumber(v.quantity or v.count))
        mailInTransitByItemID[mID] = (mailInTransitByItemID[mID] or 0) + mQ
      end
    end
  end

  -- 5. Seven-day purchase history (`ahPaid`):
  local matchedCostBasisByItemID = {}
  if type(charRec.ahPaid) == "table" then
    for _, p in ipairs(charRec.ahPaid) do
      if type(p) == "table" then
        local id = tonumber(p.itemID)
        local qty = tonumber(p.quantity)
        local paid = tonumber(p.paid)
        local at = tonumber(p.at)
        if isPositiveInt(id) and isPositiveInt(qty) and isPositiveInt(paid) and isPositiveInt(at) then
          if nowEpoch <= 0 or (at <= nowEpoch and (nowEpoch - at) <= BlackthornesBridge.AH_PAID_RETENTION_SECONDS) then
            local b = matchedCostBasisByItemID[id]
            if not b then
              b = { itemID = id, totalQuantity = 0, totalPaidCopper = 0, latestAt = at }
              matchedCostBasisByItemID[id] = b
            end
            b.totalQuantity = b.totalQuantity + math.floor(qty)
            b.totalPaidCopper = b.totalPaidCopper + math.floor(paid)
            if at > b.latestAt then
              b.latestAt = at
            end
          end
        end
      end
    end
  end
  for _, b in pairs(matchedCostBasisByItemID) do
    b.averageUnitPaidCopper = math.floor((b.totalPaidCopper / math.max(1, b.totalQuantity)) + 0.5)
  end

  -- 6. Validated Learned Recipes (checks cachedAt <= nowEpoch, skillUp.skill == currentSkill, learned profession):
  local learnedProfBySkillLineID = {}
  if type(charRec.professions) == "table" then
    for _, p in ipairs(charRec.professions) do
      if type(p) == "table" and isPositiveInt(tonumber(p.skillLineID)) then
        learnedProfBySkillLineID[math.floor(tonumber(p.skillLineID))] = {
          skillLineID = math.floor(tonumber(p.skillLineID)),
          name = tostring(p.name or ""),
          learned = (p.learned == true),
          skillLevel = math.floor(tonumber(p.skillLevel) or 0),
          maxSkillLevel = math.floor(tonumber(p.maxSkillLevel) or 0),
        }
      end
    end
  end

  local validRecipesBySpellID = {}
  local rejectedRecipesBySpellID = {}
  if type(charRec.recipes) == "table" then
    for k, r in pairs(charRec.recipes) do
      local spellID = tonumber((type(r) == "table" and r.recipeID) or k)
      if isPositiveInt(spellID) and type(r) == "table" then
        local slID = tonumber(r.skillLineID)
        local cachedAt = tonumber(r.cachedAt)
        local su = type(r.skillUp) == "table" and r.skillUp or {}
        local suSkill = tonumber(su.skill)
        local prof = slID and learnedProfBySkillLineID[slID] or nil

        local rejectReason = nil
        if not prof or prof.learned ~= true then
          rejectReason = "profession_not_learned"
        elseif not isPositiveInt(cachedAt) or (nowEpoch > 0 and cachedAt > nowEpoch) then
          rejectReason = "invalid_or_future_cached_at"
        elseif suSkill ~= nil and math.floor(suSkill) ~= prof.skillLevel then
          rejectReason = "stale_skill_up_rank_mismatch"
        end

        if rejectReason then
          rejectedRecipesBySpellID[spellID] = {
            spellID = spellID,
            name = tostring(r.name or ""),
            reason = rejectReason,
            cachedSkill = suSkill,
            currentSkill = prof and prof.skillLevel or nil,
          }
        else
          validRecipesBySpellID[spellID] = {
            spellID = spellID,
            name = tostring(r.name or ""),
            skillLineID = slID,
            outputItemID = tonumber(r.outputItemID),
            cachedAt = cachedAt,
            tier = tostring(su.tier or "unknown"),
            skillAtCapture = suSkill or (prof and prof.skillLevel),
          }
        end
      end
    end
  end

  return {
    character = charInfo,
    nowEpoch = nowEpoch,
    bankMetadata = {
      available = bankAvailable,
      complete = bankComplete,
      source = bankSource,
      observedAt = bankObservedAt,
    },
    spendableByItemID = spendableByItemID,
    activeAuctionListings = activeAuctionListings,
    activeAuctionUnitsByItemID = activeAuctionUnitsByItemID,
    expiredAuctionListings = expiredAuctionListings,
    mailInTransitByItemID = mailInTransitByItemID,
    matchedCostBasisByItemID = matchedCostBasisByItemID,
    learnedProfBySkillLineID = learnedProfBySkillLineID,
    validRecipesBySpellID = validRecipesBySpellID,
    rejectedRecipesBySpellID = rejectedRecipesBySpellID,
  }
end

return BlackthornesBridge
