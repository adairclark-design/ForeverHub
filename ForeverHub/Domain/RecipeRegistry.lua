local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.Domain = ns.Domain or {}

local RecipeRegistry = {}
ns.Domain.RecipeRegistry = RecipeRegistry

RecipeRegistry.PROVENANCE_STATIC_VERIFIED = "STATIC_VERIFIED"
RecipeRegistry.PROVENANCE_LIVE_HARVESTED = "LIVE_HARVESTED"
RecipeRegistry.PROVENANCE_CANDIDATE_NAME_ONLY = "CANDIDATE_NAME_ONLY"

-- Astra P1 Identifier Separation Table:
-- Keep recipeItemID (pattern/scroll item), spellID (crafting spell), and outputItemID (crafted item)
-- strictly separated. Never confuse Spell 18401 (Bolt of Runecloth) with Pattern: Mooncloth (Item 14526),
-- and never confuse Pattern: White Bandit Mask (Item 10301) with Item 10316.
RecipeRegistry.CANONICAL_PATTERNS = {
  tailor_mooncloth = {
    recipeKey = "tailor_mooncloth",
    name = "Pattern: Mooncloth",
    professionKey = "TAILORING",
    minSkill = 250,
    recipeItemID = 14526,
    spellID = 18560,
    outputItemID = 14342,
    stockBehaviorInForever = "UNVERIFIED_CHECK_MERCHANT_STOCK",
    classicVendorNote = "Sold by Qia in Everlook; Classic reference distinguishes Mooncloth stock from limited-stock patterns, but Forever acquisition behavior must be verified in-client.",
  },
  tailor_bolt_of_runecloth = {
    recipeKey = "tailor_bolt_of_runecloth",
    name = "Bolt of Runecloth",
    professionKey = "TAILORING",
    minSkill = 250,
    recipeItemID = nil, -- Trainer-taught spell
    spellID = 18401,
    outputItemID = 14048,
  },
  tailor_white_bandit_mask = {
    recipeKey = "tailor_white_bandit_mask",
    name = "Pattern: White Bandit Mask",
    professionKey = "TAILORING",
    minSkill = 215,
    recipeItemID = 10301,
    spellID = 12046,
    outputItemID = 10047,
    classicSkillColors = { orange = 215, yellow = 220, green = 225, gray = 230 },
    foreverSkillColorsVerified = false,
  },
  alchemy_transmute_elemental_fire = {
    recipeKey = "alchemy_transmute_elemental_fire",
    name = "Recipe: Transmute Elemental Fire",
    professionKey = "ALCHEMY",
    minSkill = 300,
    recipeItemID = 20761,
    outputItemID = 7068,
    outputQuantity = 3,
    classicPhaseGate = "PHASE_5_THORIUM_BROTHERHOOD_FRIENDLY",
    foreverPhaseAvailability = "UNVERIFIED_PHASE_GATED",
  },
}

function RecipeRegistry.ValidateSeparatedIdentifiers(record)
  if type(record) ~= "table" then
    return false, "invalid_record"
  end
  local rItem = tonumber(record.recipeItemID)
  local sID = tonumber(record.spellID)
  local outItem = tonumber(record.outputItemID)
  if rItem and outItem and rItem == outItem then
    return false, "recipe_item_id_collides_with_output_item_id"
  end
  if rItem == 18401 then
    return false, "spell_18401_bolt_of_runecloth_misused_as_recipe_item_id"
  end
  if rItem == 10316 and outItem == 10047 then
    return false, "wrong_pattern_id_10316_for_white_bandit_mask_expected_10301"
  end
  if outItem == 14342 and sID == 18401 then
    return false, "spell_18401_is_bolt_of_runecloth_not_mooncloth"
  end
  return true, nil
end

RecipeRegistry.__stateByBuild = {}

local function isPositiveInt(v)
  return type(v) == "number" and v == v and v >= 1 and v < 9007199254740992 and math.floor(v) == v
end

local function normalizeName(name)
  if type(name) ~= "string" then
    return ""
  end
  local trimmed = name:gsub("^%s+", ""):gsub("%s+$", "")
  return string.lower(trimmed)
end

function RecipeRegistry.ResolveBuildVersion(opts)
  if type(opts) == "table" and type(opts.buildVersion) == "string" and opts.buildVersion ~= "" then
    return opts.buildVersion
  end
  if type(_G.GetBuildInfo) == "function" then
    local ok, ver, buildNum = pcall(_G.GetBuildInfo)
    if ok and type(ver) == "string" and ver ~= "" then
      if buildNum and tostring(buildNum) ~= "" then
        return tostring(ver) .. "." .. tostring(buildNum)
      end
      return tostring(ver)
    end
  end
  return "forever_default_build"
end

local function ensureBuildBucket(buildVersion)
  local bKey = tostring(buildVersion or RecipeRegistry.ResolveBuildVersion(nil))
  local bucket = RecipeRegistry.__stateByBuild[bKey]
  if not bucket then
    bucket = {
      buildVersion = bKey,
      itemsByID = {},        -- Strict itemID namespace ONLY
      currenciesByID = {},   -- Strict currencyID namespace ONLY
      recipeItemsByID = {},  -- Strict recipe scroll/formula itemID namespace ONLY
      spellsByID = {},       -- Strict craft/enchant spellID namespace ONLY
      recipesByKey = {},
      candidatesByNormalizedName = {},
    }
    RecipeRegistry.__stateByBuild[bKey] = bucket
  end
  return bucket
end

function RecipeRegistry.ResetForTesting()
  RecipeRegistry.__stateByBuild = {}
end

function RecipeRegistry.ParseHyperlinkNamespace(link)
  if type(link) ~= "string" or link == "" then
    return nil
  end
  local itemMatch = link:match("Hitem:(%d+)")
  if itemMatch then
    local id = tonumber(itemMatch)
    if isPositiveInt(id) then
      local bracketName = link:match("%[(.-)%]")
      return {
        namespace = "itemID",
        id = id,
        name = bracketName,
        rawLink = link,
      }
    end
  end
  local spellMatch = link:match("Hspell:(%d+)") or link:match("Henchant:(%d+)")
  if spellMatch then
    local id = tonumber(spellMatch)
    if isPositiveInt(id) then
      local bracketName = link:match("%[(.-)%]")
      return {
        namespace = "spellID",
        id = id,
        name = bracketName,
        rawLink = link,
      }
    end
  end
  local currencyMatch = link:match("Hcurrency:(%d+)")
  if currencyMatch then
    local id = tonumber(currencyMatch)
    if isPositiveInt(id) then
      local bracketName = link:match("%[(.-)%]")
      return {
        namespace = "currencyID",
        id = id,
        name = bracketName,
        rawLink = link,
      }
    end
  end
  return nil
end

function RecipeRegistry.RecordEntity(entry, opts)
  if type(entry) ~= "table" then
    return nil, "invalid_entry"
  end
  local bucket = ensureBuildBucket(RecipeRegistry.ResolveBuildVersion(opts))
  local nsType = tostring(entry.namespace or "")
  local id = tonumber(entry.id)
  local provenance = tostring(entry.provenance or RecipeRegistry.PROVENANCE_LIVE_HARVESTED)
  local name = type(entry.name) == "string" and entry.name or nil

  if nsType == "itemID" and isPositiveInt(id) then
    local rec = {
      namespace = "itemID",
      itemID = id,
      name = name,
      provenance = provenance,
      identityVerified = (provenance == RecipeRegistry.PROVENANCE_STATIC_VERIFIED or provenance == RecipeRegistry.PROVENANCE_LIVE_HARVESTED),
      buildVersion = bucket.buildVersion,
      sourceSurface = entry.sourceSurface,
    }
    bucket.itemsByID[id] = rec
    if name and name ~= "" then
      bucket.candidatesByNormalizedName[normalizeName(name)] = {
        name = name,
        itemID = id,
        namespace = "itemID",
        provenance = provenance,
        identityVerified = rec.identityVerified,
        buildVersion = bucket.buildVersion,
      }
    end
    return rec, nil
  elseif nsType == "currencyID" and isPositiveInt(id) then
    local rec = {
      namespace = "currencyID",
      currencyID = id,
      name = name,
      provenance = provenance,
      identityVerified = (provenance == RecipeRegistry.PROVENANCE_STATIC_VERIFIED or provenance == RecipeRegistry.PROVENANCE_LIVE_HARVESTED),
      buildVersion = bucket.buildVersion,
      sourceSurface = entry.sourceSurface,
    }
    bucket.currenciesByID[id] = rec
    return rec, nil
  elseif nsType == "recipeItemID" and isPositiveInt(id) then
    local rec = {
      namespace = "recipeItemID",
      recipeItemID = id,
      teachesSpellID = isPositiveInt(tonumber(entry.teachesSpellID)) and tonumber(entry.teachesSpellID) or nil,
      outputItemID = isPositiveInt(tonumber(entry.outputItemID)) and tonumber(entry.outputItemID) or nil,
      name = name,
      bindType = entry.bindType or "UNKNOWN",
      acquisitionSource = entry.acquisitionSource or "UNKNOWN",
      provenance = provenance,
      identityVerified = (provenance == RecipeRegistry.PROVENANCE_STATIC_VERIFIED or provenance == RecipeRegistry.PROVENANCE_LIVE_HARVESTED),
      buildVersion = bucket.buildVersion,
    }
    bucket.recipeItemsByID[id] = rec
    return rec, nil
  elseif nsType == "spellID" and isPositiveInt(id) then
    local rec = {
      namespace = "spellID",
      spellID = id,
      outputItemID = isPositiveInt(tonumber(entry.outputItemID)) and tonumber(entry.outputItemID) or nil,
      name = name,
      provenance = provenance,
      identityVerified = (provenance == RecipeRegistry.PROVENANCE_STATIC_VERIFIED or provenance == RecipeRegistry.PROVENANCE_LIVE_HARVESTED),
      buildVersion = bucket.buildVersion,
    }
    bucket.spellsByID[id] = rec
    return rec, nil
  end
  return nil, "unsupported_namespace_or_id"
end

function RecipeRegistry.HarvestFromHyperlink(link, sourceSurface, opts)
  local parsed = RecipeRegistry.ParseHyperlinkNamespace(link)
  if not parsed then
    return nil, "unparseable_link"
  end
  local isRecipeScroll = (type(opts) == "table" and opts.isRecipeScroll == true)
  local targetNamespace = (isRecipeScroll and parsed.namespace == "itemID") and "recipeItemID" or parsed.namespace
  return RecipeRegistry.RecordEntity({
    namespace = targetNamespace,
    id = parsed.id,
    name = parsed.name,
    provenance = RecipeRegistry.PROVENANCE_LIVE_HARVESTED,
    sourceSurface = sourceSurface or "hyperlink_harvest",
  }, opts)
end

function RecipeRegistry.HarvestFromTradeSkillEntry(tradeSkillRow, opts)
  if type(tradeSkillRow) ~= "table" then
    return nil, "invalid_tradeskill_row"
  end
  local bucket = ensureBuildBucket(RecipeRegistry.ResolveBuildVersion(opts))
  local recipeKey = tostring(tradeSkillRow.recipeID or tradeSkillRow.recipeName or "")
  if recipeKey == "" then
    return nil, "missing_recipe_key"
  end

  local outputItemID = nil
  if type(tradeSkillRow.outputItemLink) == "string" then
    local parsedOut = RecipeRegistry.ParseHyperlinkNamespace(tradeSkillRow.outputItemLink)
    if parsedOut and parsedOut.namespace == "itemID" then
      outputItemID = parsedOut.id
      RecipeRegistry.RecordEntity({
        namespace = "itemID",
        id = parsedOut.id,
        name = parsedOut.name or tradeSkillRow.outputName or tradeSkillRow.recipeName,
        provenance = RecipeRegistry.PROVENANCE_LIVE_HARVESTED,
        sourceSurface = "tradeskill_output_link",
      }, opts)
    end
  elseif isPositiveInt(tonumber(tradeSkillRow.outputItemID)) then
    outputItemID = tonumber(tradeSkillRow.outputItemID)
    RecipeRegistry.RecordEntity({
      namespace = "itemID",
      id = outputItemID,
      name = tradeSkillRow.outputName or tradeSkillRow.recipeName,
      provenance = tradeSkillRow.provenance or RecipeRegistry.PROVENANCE_LIVE_HARVESTED,
      sourceSurface = "tradeskill_output_id",
    }, opts)
  end

  local spellID = nil
  if type(tradeSkillRow.recipeSpellLink) == "string" then
    local parsedSpell = RecipeRegistry.ParseHyperlinkNamespace(tradeSkillRow.recipeSpellLink)
    if parsedSpell and parsedSpell.namespace == "spellID" then
      spellID = parsedSpell.id
      RecipeRegistry.RecordEntity({
        namespace = "spellID",
        id = spellID,
        outputItemID = outputItemID,
        name = parsedSpell.name or tradeSkillRow.recipeName,
        provenance = RecipeRegistry.PROVENANCE_LIVE_HARVESTED,
        sourceSurface = "tradeskill_spell_link",
      }, opts)
    end
  elseif isPositiveInt(tonumber(tradeSkillRow.spellID)) then
    spellID = tonumber(tradeSkillRow.spellID)
    RecipeRegistry.RecordEntity({
      namespace = "spellID",
      id = spellID,
      outputItemID = outputItemID,
      name = tradeSkillRow.recipeName,
      provenance = tradeSkillRow.provenance or RecipeRegistry.PROVENANCE_LIVE_HARVESTED,
      sourceSurface = "tradeskill_spell_id",
    }, opts)
  end

  local harvestedReagents = {}
  for _, rg in ipairs(tradeSkillRow.reagents or {}) do
    if type(rg) == "table" then
      local rID = tonumber(rg.itemID)
      local rName = rg.name
      if type(rg.itemLink) == "string" then
        local parsedRg = RecipeRegistry.ParseHyperlinkNamespace(rg.itemLink)
        if parsedRg and parsedRg.namespace == "itemID" then
          rID = parsedRg.id
          rName = parsedRg.name or rName
        end
      end
      if isPositiveInt(rID) then
        RecipeRegistry.RecordEntity({
          namespace = "itemID",
          id = rID,
          name = rName,
          provenance = RecipeRegistry.PROVENANCE_LIVE_HARVESTED,
          sourceSurface = "tradeskill_reagent",
        }, opts)
      end
      table.insert(harvestedReagents, {
        itemID = isPositiveInt(rID) and rID or nil,
        name = rName,
        quantity = math.max(1, math.floor(tonumber(rg.quantity) or 1)),
        identityVerified = isPositiveInt(rID),
      })
    end
  end

  local recipeRecord = {
    recipeKey = recipeKey,
    recipeName = tradeSkillRow.recipeName,
    professionKey = tradeSkillRow.professionKey,
    outputItemID = outputItemID,
    spellID = spellID,
    recipeItemID = isPositiveInt(tonumber(tradeSkillRow.recipeItemID)) and tonumber(tradeSkillRow.recipeItemID) or nil,
    reagents = harvestedReagents,
    provenance = (outputItemID ~= nil or spellID ~= nil)
      and (tradeSkillRow.provenance or RecipeRegistry.PROVENANCE_LIVE_HARVESTED)
      or RecipeRegistry.PROVENANCE_CANDIDATE_NAME_ONLY,
    identityVerified = (outputItemID ~= nil or spellID ~= nil),
    buildVersion = bucket.buildVersion,
  }
  bucket.recipesByKey[recipeKey] = recipeRecord
  if type(tradeSkillRow.recipeName) == "string" and tradeSkillRow.recipeName ~= "" and not recipeRecord.identityVerified then
    bucket.candidatesByNormalizedName[normalizeName(tradeSkillRow.recipeName)] = {
      name = tradeSkillRow.recipeName,
      recipeKey = recipeKey,
      namespace = "candidate_name_only",
      provenance = RecipeRegistry.PROVENANCE_CANDIDATE_NAME_ONLY,
      identityVerified = false,
      buildVersion = bucket.buildVersion,
    }
  end
  return recipeRecord, nil
end

function RecipeRegistry.LookupByNamespace(namespace, id, opts)
  local numID = tonumber(id)
  if not isPositiveInt(numID) then
    return nil
  end
  local bucket = ensureBuildBucket(RecipeRegistry.ResolveBuildVersion(opts))
  if namespace == "itemID" then
    return bucket.itemsByID[numID]
  elseif namespace == "currencyID" then
    return bucket.currenciesByID[numID]
  elseif namespace == "recipeItemID" then
    return bucket.recipeItemsByID[numID]
  elseif namespace == "spellID" then
    return bucket.spellsByID[numID]
  end
  return nil
end

-- Exact-name fallback search: returns explicit candidate status and NEVER claims verified itemID
-- unless backed by a verified static or live-harvested record in the same buildVersion.
function RecipeRegistry.ResolveCandidateByExactName(name, opts)
  local norm = normalizeName(name)
  if norm == "" then
    return {
      status = "INVALID_QUERY",
      identityVerified = false,
      provenance = RecipeRegistry.PROVENANCE_CANDIDATE_NAME_ONLY,
    }
  end
  local bucket = ensureBuildBucket(RecipeRegistry.ResolveBuildVersion(opts))
  local existing = bucket.candidatesByNormalizedName[norm]
  if existing and existing.identityVerified == true and isPositiveInt(existing.itemID) then
    return {
      status = "VERIFIED_IN_BUILD",
      name = existing.name,
      itemID = existing.itemID,
      namespace = "itemID",
      identityVerified = true,
      provenance = existing.provenance,
      buildVersion = bucket.buildVersion,
    }
  end
  return {
    status = "CANDIDATE_UNVERIFIED_ID",
    name = name,
    itemID = nil,
    namespace = "candidate_name_only",
    identityVerified = false,
    provenance = RecipeRegistry.PROVENANCE_CANDIDATE_NAME_ONLY,
    buildVersion = bucket.buildVersion,
    reason = "exact_name_only_awaiting_live_item_link",
  }
end

return RecipeRegistry
