local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.Domain = ns.Domain or {}

local MarketIdentity = {}
ns.Domain.MarketIdentity = MarketIdentity

MarketIdentity.SCHEMA_VERSION = 1

local VALID_AUCTION_POOLS = {
  alliance = true,
  horde = true,
  neutral = true,
  cross_faction_verified = true,
  unknown_pool = true,
}

local VALID_REGIONS = {
  us = true,
  eu = true,
  kr = true,
  tw = true,
  cn = true,
  unknown = true,
}

local NON_VARIANT_EQUIP_LOCS = {
  [""] = true,
  INVTYPE_NON_EQUIP = true,
  INVTYPE_NON_EQUIP_IGNORE = true,
  INVTYPE_BAG = true,
  INVTYPE_QUIVER = true,
  INVTYPE_AMMO = true,
}

local function isSecret(v)
  if ns.Compat and type(ns.Compat.IsSecretOrRestrictedValue) == "function" then
    return ns.Compat.IsSecretOrRestrictedValue(v) == true
  end
  local checkFn = _G.issecretvalue
  if type(checkFn) == "function" then
    local ok, res = pcall(checkFn, v)
    if ok and res == true then
      return true
    end
  end
  return false
end

local function isSafePositiveInt(v)
  if isSecret(v) or type(v) ~= "number" then
    return false
  end
  if v ~= v or v == math.huge or v == -math.huge then
    return false
  end
  return v >= 1 and v <= 2147483647 and math.floor(v) == v
end

local function isSafeSignedInt(v)
  if isSecret(v) or type(v) ~= "number" then
    return false
  end
  if v ~= v or v == math.huge or v == -math.huge then
    return false
  end
  return v >= -2147483648 and v <= 2147483647 and math.floor(v) == v
end

function MarketIdentity.SlugifyToken(raw)
  if isSecret(raw) or type(raw) ~= "string" then
    return nil
  end
  local lowered = string.lower(raw)
  local cleaned = string.gsub(lowered, "[^a-z0-9_-]+", "-")
  cleaned = string.gsub(cleaned, "^-+(.+)$", "%1")
  cleaned = string.gsub(cleaned, "^(.-)-+$", "%1")
  cleaned = string.gsub(cleaned, "-+", "-")
  if cleaned == "" or cleaned == "-" then
    return nil
  end
  return cleaned
end

function MarketIdentity.DetectClientRegion()
  local getRegName = _G.GetCurrentRegionName
  if type(getRegName) == "function" then
    local ok, reg = pcall(getRegName)
    if ok and not isSecret(reg) and type(reg) == "string" then
      local slug = MarketIdentity.SlugifyToken(reg)
      if slug and VALID_REGIONS[slug] then
        return slug
      end
    end
  end
  local getCVar = _G.GetCVar
  if type(getCVar) == "function" then
    local ok, portal = pcall(getCVar, "portal")
    if ok and not isSecret(portal) and type(portal) == "string" then
      local slug = MarketIdentity.SlugifyToken(portal)
      if slug and VALID_REGIONS[slug] then
        return slug
      end
    end
  end
  return "unknown"
end

-- Builds canonical `m1:<product>:<ruleset>:<region>:<realm_scope>:<auction_pool_id>`.
-- Layer identifiers are strictly excluded from `marketKey` (tracked only as route-contention metadata).
function MarketIdentity.BuildMarketKey(opts)
  if isSecret(opts) or type(opts) ~= "table" then
    return nil, "invalid_options"
  end

  local product = MarketIdentity.SlugifyToken(opts.product or "wowf")
  local ruleset = MarketIdentity.SlugifyToken(opts.ruleset or "wow_forever")
  if not product or not ruleset then
    return nil, "invalid_product_or_ruleset"
  end

  local region = MarketIdentity.SlugifyToken(opts.region or "unknown") or "unknown"
  if not VALID_REGIONS[region] then
    region = "unknown"
  end

  local realmSlug = nil
  local realmPrefix = "r"
  if opts.connectedRealmVerified == true and not isSecret(opts.connectedRealmRoot) then
    realmSlug = MarketIdentity.SlugifyToken(opts.connectedRealmRoot)
    if realmSlug then
      realmPrefix = "cr"
    end
  end
  if not realmSlug then
    realmSlug = MarketIdentity.SlugifyToken(opts.realmName)
    realmPrefix = "r"
  end
  if not realmSlug then
    return nil, "missing_realm_identity"
  end

  local pool = MarketIdentity.SlugifyToken(opts.auctionPoolID or "unknown_pool") or "unknown_pool"
  if not VALID_AUCTION_POOLS[pool] then
    return nil, "invalid_auction_pool_id"
  end

  local key = string.format("m1:%s:%s:%s:%s:%s:%s", product, ruleset, region, realmPrefix, realmSlug, pool)
  return key, nil
end

function MarketIdentity.ResolveCurrentClientMarketKey(explicitAuctionPoolID)
  local realmName = nil
  local getRealm = _G.GetRealmName
  if type(getRealm) == "function" then
    local ok, r = pcall(getRealm)
    if ok and not isSecret(r) and type(r) == "string" and r ~= "" then
      realmName = r
    end
  end
  if not realmName then
    return nil, "realm_unavailable"
  end

  local pool = nil
  if not isSecret(explicitAuctionPoolID) and type(explicitAuctionPoolID) == "string" then
    pool = MarketIdentity.SlugifyToken(explicitAuctionPoolID)
  end
  if not pool then
    local fac = ns.Compat and ns.Compat.GetPlayerFactionString and ns.Compat.GetPlayerFactionString() or nil
    if not isSecret(fac) and type(fac) == "string" then
      local fl = string.lower(fac)
      if fl == "alliance" or fl == "horde" then
        pool = fl
      end
    end
  end
  pool = pool or "unknown_pool"

  return MarketIdentity.BuildMarketKey({
    product = "wowf",
    ruleset = "wow_forever",
    region = MarketIdentity.DetectClientRegion(),
    realmName = realmName,
    auctionPoolID = pool,
  })
end

-- Parses WoW `item:` hyperlink payload while stripping viewer-specific fields (`linkLevel`,
-- `uniqueID` instance GUIDs, `specID`, creator context) and guarding against secret values first.
function MarketIdentity.ParseItemHyperlink(rawLink)
  if isSecret(rawLink) or type(rawLink) ~= "string" or rawLink == "" then
    return nil, "missing_or_restricted_link"
  end

  local itemPayload = string.match(rawLink, "|Hitem:([%d:%-]+)|h")
  if not itemPayload then
    itemPayload = string.match(rawLink, "^item:([%d:%-]+)$")
  end
  if not itemPayload then
    return nil, "not_an_item_hyperlink"
  end

  local fields = {}
  local count = 0
  for token in string.gmatch(itemPayload .. ":", "([^:]*):") do
    count = count + 1
    if count > 24 then
      break
    end
    fields[count] = token
  end

  local itemID = tonumber(fields[1])
  if not isSafePositiveInt(itemID) then
    return nil, "invalid_item_id"
  end

  local permEnchantID = tonumber(fields[2] or "") or 0
  if not isSafeSignedInt(permEnchantID) or permEnchantID < 0 then
    permEnchantID = 0
  end

  local suffixID = tonumber(fields[7] or "") or 0
  if not isSafeSignedInt(suffixID) then
    suffixID = 0
  end

  -- Only negative suffixIDs in Classic/Forever use a stat-scaling factor in field 8 (low 16 bits);
  -- for suffixID >= 0, field 8 is an instance-unique GUID and MUST be stripped to avoid splitting markets.
  local suffixFactor = 0
  if suffixID < 0 then
    local rawUnique = tonumber(fields[8] or "") or 0
    if isSafeSignedInt(rawUnique) and rawUnique ~= 0 then
      suffixFactor = math.abs(rawUnique) % 65536
    end
  end

  return {
    itemID = itemID,
    permEnchantID = permEnchantID,
    suffixID = suffixID,
    suffixFactor = suffixFactor,
    sanitizedEvidenceLink = string.format("item:%d:%d:0:0:0:0:%d:%d", itemID, permEnchantID, suffixID, suffixFactor),
  }, nil
end

function MarketIdentity.IsCatalogVerifiedFungibleBaseItem(itemID, explicitBaseSet)
  if not isSafePositiveInt(itemID) then
    return false
  end
  if type(explicitBaseSet) == "table" and explicitBaseSet[itemID] == true then
    return true
  end
  local data = ns.Data or {}
  if data.cratesByItemID and data.cratesByItemID[itemID] then
    return true
  end
  if data.sealedCratesByItemID and data.sealedCratesByItemID[itemID] then
    return true
  end
  if data.materialToCrates and data.materialToCrates[itemID] then
    return true
  end
  if data.materialsByItemID and data.materialsByItemID[itemID] then
    return true
  end
  local gf = ns.GoldFarmsData or {}
  if gf.materialsByItemID and gf.materialsByItemID[itemID] then
    return true
  end
  local econ = ns.EconomyData or {}
  if type(econ.items) == "table" and type(econ.items[itemID]) == "table" then
    local flags = tonumber(econ.items[itemID][3]) or 0
    if (math.floor(flags / 8) % 2) == 0 and (math.floor(flags / 16) % 2) == 0 then
      return true
    end
  end
  return false
end

function MarketIdentity.IsCatalogRecipeOrWritItem(itemID)
  if not isSafePositiveInt(itemID) then
    return false
  end
  local data = ns.Data or {}
  if data.writsByItemID and data.writsByItemID[itemID] then
    return true
  end
  return false
end

local function inspectClientItemClass(itemID)
  local getInstant = _G.GetItemInfoInstant
  if type(getInstant) ~= "function" then
    return nil
  end
  local ok, retID, _, _, itemEquipLoc, _, classID, subClassID = pcall(getInstant, itemID)
  if not ok or isSecret(retID) or isSecret(itemEquipLoc) or isSecret(classID) then
    return nil
  end
  if type(classID) ~= "number" then
    return nil
  end
  return {
    equipLoc = type(itemEquipLoc) == "string" and itemEquipLoc or "",
    classID = classID,
    subClassID = type(subClassID) == "number" and subClassID or 0,
  }
end

-- Canonical item/service key classifier (`contracts/market-identity-v1.md` Section 2).
-- Returns `{ itemKey, classification, itemID, tradeSafe, reason, sanitizedLink }`.
function MarketIdentity.ClassifyItemIdentity(opts)
  if isSecret(opts) or type(opts) ~= "table" then
    return nil, "invalid_options"
  end

  local kind = not isSecret(opts.kind) and tostring(opts.kind or "item") or "item"

  -- 1. Trade-window service (`i1:service:<profession_slug>:<spell_id>`)
  if kind == "service" then
    local profSlug = MarketIdentity.SlugifyToken(opts.professionSlug)
    local spellID = tonumber(not isSecret(opts.spellID) and opts.spellID or nil)
    if not profSlug or not isSafePositiveInt(spellID) then
      return nil, "invalid_service_identity"
    end
    return {
      itemKey = string.format("i1:service:%s:%d", profSlug, spellID),
      classification = "service",
      spellID = spellID,
      tradeSafe = true,
    }, nil
  end

  local parsedLink = nil
  if not isSecret(opts.itemLink) and type(opts.itemLink) == "string" and opts.itemLink ~= "" then
    parsedLink = MarketIdentity.ParseItemHyperlink(opts.itemLink)
  end

  local rawID = not isSecret(opts.itemID) and tonumber(opts.itemID) or nil
  local itemID = (parsedLink and parsedLink.itemID) or rawID
  if not isSafePositiveInt(itemID) then
    return nil, "invalid_item_id"
  end
  if parsedLink and rawID and parsedLink.itemID ~= rawID then
    return nil, "mismatched_item_id_and_hyperlink"
  end

  local charges = 0
  if opts.charges ~= nil then
    if isSecret(opts.charges) then
      return nil, "restricted_charges"
    end
    local cNum = tonumber(opts.charges)
    if not isSafeSignedInt(cNum) or cNum < 0 then
      return nil, "invalid_charges"
    end
    charges = cNum
  end

  local instInfo = opts.clientClassInfo
  if instInfo == nil then
    instInfo = inspectClientItemClass(itemID)
  end

  -- 2. Recipe / Writ item (`i1:recipe:<item_id>`) — strictly distinct from crafted output!
  if kind == "recipe" or MarketIdentity.IsCatalogRecipeOrWritItem(itemID) or (instInfo and instInfo.classID == 9) then
    return {
      itemKey = string.format("i1:recipe:%d", itemID),
      classification = "recipe_item",
      itemID = itemID,
      tradeSafe = true,
      sanitizedLink = parsedLink and parsedLink.sanitizedEvidenceLink or nil,
    }, nil
  end

  -- 3. Explicit variant-capable check (weapons classID=2, armor classID=4, equippable gear, or explicit flag)
  local variantCapable = nil
  if type(opts.isVariantCapable) == "boolean" then
    variantCapable = opts.isVariantCapable
  elseif MarketIdentity.IsCatalogVerifiedFungibleBaseItem(itemID, opts.verifiedBaseSet) and charges == 0 then
    variantCapable = false
  elseif instInfo then
    if instInfo.classID == 2 or instInfo.classID == 4 then
      variantCapable = true
    elseif not NON_VARIANT_EQUIP_LOCS[instInfo.equipLoc or ""] then
      variantCapable = true
    elseif instInfo.classID == 7 or instInfo.classID == 5 or instInfo.classID == 1 then
      -- Trade Goods (7), Reagent (5), Container/Bag (1) with non-gear equipLoc
      variantCapable = (charges > 0)
    elseif instInfo.classID == 0 and charges == 0 then
      variantCapable = false
    end
  end

  if variantCapable == false then
    if parsedLink and (parsedLink.suffixID ~= 0 or parsedLink.permEnchantID ~= 0) then
      variantCapable = true
    else
      return {
        itemKey = string.format("i1:base:%d", itemID),
        classification = "verified_base_item",
        itemID = itemID,
        tradeSafe = true,
        sanitizedLink = parsedLink and parsedLink.sanitizedEvidenceLink or nil,
      }, nil
    end
  end

  -- 4. Variant-capable item WITH full hyperlink observed -> deterministic variant key
  if variantCapable == true and parsedLink then
    local vKey = string.format(
      "i1:var:%d:s=%d:f=%d:e=%d:c=%d",
      itemID,
      parsedLink.suffixID,
      parsedLink.suffixFactor,
      parsedLink.permEnchantID,
      charges
    )
    return {
      itemKey = vKey,
      classification = "variant_item",
      itemID = itemID,
      suffixID = parsedLink.suffixID,
      suffixFactor = parsedLink.suffixFactor,
      permEnchantID = parsedLink.permEnchantID,
      charges = charges,
      tradeSafe = true,
      sanitizedLink = parsedLink.sanitizedEvidenceLink,
    }, nil
  end

  -- 5. Variant-capable or unverified item observed WITHOUT hyperlink (`itemID` only) -> `unknown_variant` (tradeSafe = false!)
  return {
    itemKey = string.format("i1:unk_var:%d", itemID),
    classification = "unknown_variant",
    itemID = itemID,
    tradeSafe = false,
    reason = (variantCapable == true) and "missing_hyperlink_for_variant_item" or "unverified_item_variant_class",
    sanitizedLink = nil,
  }, nil
end
