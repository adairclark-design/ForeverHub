local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.Providers = ns.Providers or {}
local AuctionatorProvider = {}
ns.Providers.Auctionator = AuctionatorProvider

local CALLER_ID = "ForeverHub"
AuctionatorProvider.__registered = false

function AuctionatorProvider.IsAvailable()
  return type(_G.Auctionator) == "table"
    and type(_G.Auctionator.API) == "table"
    and type(_G.Auctionator.API.v1) == "table"
    and type(_G.Auctionator.API.v1.GetAuctionPriceByItemID) == "function"
end

function AuctionatorProvider.RegisterDBUpdateCallback(callback)
  if AuctionatorProvider.__registered then
    return true
  end
  if not AuctionatorProvider.IsAvailable() then
    return false
  end
  local api = _G.Auctionator.API.v1
  if type(api.RegisterForDBUpdate) == "function" then
    local ok = pcall(api.RegisterForDBUpdate, CALLER_ID, function()
      if ns.State and ns.State.BumpPriceRevision then
        ns.State.BumpPriceRevision()
      end
      if type(callback) == "function" then
        callback()
      end
    end)
    if ok then
      AuctionatorProvider.__registered = true
      return true
    end
  end
  return false
end

-- Returns {
--   unitPrice = integerCopperOrNil,
--   ageDays = numberOrNil,
--   freshness = "fresh" | "stale" | "unknown_age" | "missing",
--   isStale = boolean,
--   isUnknownAge = boolean,
--   available = boolean,
-- }
-- Missing or <= 0 prices ALWAYS return unitPrice = nil (never 0).
-- Unknown age (nil from GetAuctionAgeByItemID, including >21d old) sets freshness = "unknown_age", never "fresh".
function AuctionatorProvider.GetItemPriceInfo(itemID)
  itemID = tonumber(itemID)
  if not itemID or itemID <= 0 or not AuctionatorProvider.IsAvailable() then
    return {
      unitPrice = nil,
      ageDays = nil,
      freshness = "missing",
      isStale = false,
      isUnknownAge = false,
      available = false,
    }
  end

  local api = _G.Auctionator.API.v1
  local okPrice, rawPrice = pcall(api.GetAuctionPriceByItemID, CALLER_ID, itemID)
  if not okPrice or type(rawPrice) ~= "number" or rawPrice <= 0 then
    return {
      unitPrice = nil,
      ageDays = nil,
      freshness = "missing",
      isStale = false,
      isUnknownAge = false,
      available = true,
    }
  end

  local unitPrice = math.floor(rawPrice + 0.5)
  local ageDays = nil
  if type(api.GetAuctionAgeByItemID) == "function" then
    local okAge, rawAge = pcall(api.GetAuctionAgeByItemID, CALLER_ID, itemID)
    if okAge and type(rawAge) == "number" and rawAge >= 0 then
      ageDays = math.floor(rawAge)
    end
  end

  local staleThresholdDays = (ns.State and ns.State.GetStaleAgeDays and ns.State.GetStaleAgeDays()) or 2
  local freshness
  local isStale = false
  local isUnknownAge = false

  if ageDays == nil then
    freshness = "unknown_age"
    isUnknownAge = true
  elseif ageDays > staleThresholdDays then
    freshness = "stale"
    isStale = true
  else
    freshness = "fresh"
  end

  return {
    unitPrice = unitPrice,
    ageDays = ageDays,
    freshness = freshness,
    isStale = isStale,
    isUnknownAge = isUnknownAge,
    available = true,
  }
end

function AuctionatorProvider.GetDefaultShoppingListName(modeSuffix)
  local charName = ns.Compat.GetCharacterKey()
  if modeSuffix and modeSuffix ~= "" then
    return string.format("ForeverHub - %s (%s)", charName, modeSuffix)
  end
  return string.format("ForeverHub - %s", charName)
end

function AuctionatorProvider.CreateShoppingList(listName, entries)
  if not AuctionatorProvider.IsAvailable() then
    return false, "Auctionator is not loaded."
  end
  local api = _G.Auctionator.API.v1
  if type(api.CreateShoppingList) ~= "function" then
    return false, "Auctionator CreateShoppingList API unavailable."
  end

  local searchTerms = {}
  local skippedUnresolved = 0

  for _, entry in ipairs(entries or {}) do
    local qty = math.floor(tonumber(entry.deficitQty or entry.buyQty) or 0)
    if qty > 0 then
      local resolvedName = ns.Compat.ResolveItemName(entry.itemID, entry.name)
      if not resolvedName or resolvedName == "" then
        skippedUnresolved = skippedUnresolved + 1
      else
        local termStr = nil
        if type(api.ConvertToSearchString) == "function" then
          local okConv, term = pcall(api.ConvertToSearchString, CALLER_ID, {
            searchString = resolvedName,
            isExact = true,
            quantity = qty,
          })
          if okConv and type(term) == "string" and term ~= "" then
            termStr = term
          end
        end
        if not termStr then
          -- Auctionator advanced search format: "ExactName";category;minLvl;maxLvl;...;quantity (11 semicolons before quantity)
          termStr = string.format("\"%s\";;;;;;;;;;;%d", resolvedName, qty)
        end
        table.insert(searchTerms, termStr)
      end
    end
  end

  if #searchTerms == 0 then
    if skippedUnresolved > 0 then
      return false, "Could not resolve localized item names for missing materials."
    end
    return false, "No missing materials to shop for."
  end

  local finalListName = listName or AuctionatorProvider.GetDefaultShoppingListName()
  local ok, err = pcall(api.CreateShoppingList, CALLER_ID, finalListName, searchTerms)
  if not ok then
    return false, tostring(err)
  end
  return true, #searchTerms, finalListName
end
