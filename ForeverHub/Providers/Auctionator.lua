local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.Providers = ns.Providers or {}
local AuctionatorProvider = {}
ns.Providers.Auctionator = AuctionatorProvider

local CALLER_ID = "ForeverHub"
local MAX_SAFE_COPPER = 1125899906842623 -- 2^50 - 1
local PURCHASE_SAFEGUARD_WARNING =
  "Auctionator maxPrice filters by minimum group buyout; verify each individual stack's buyout before purchasing."

AuctionatorProvider.__registered = false
AuctionatorProvider.__lastShoppingListReport = nil

local function isPositiveIntegerCopper(val)
  return type(val) == "number"
    and val == val
    and val ~= math.huge
    and val ~= -math.huge
    and val >= 1
    and val <= MAX_SAFE_COPPER
    and math.floor(val) == val
end

local function makeEmptyReport(errMsg)
  return {
    ok = false,
    error = errMsg,
    listName = nil,
    createdCount = 0,
    searchTerms = {},
    created = {},
    pending = {},
    excluded = {},
    isComplete = false,
    hasPriceCeilings = false,
    discoveryOnly = true,
    purchaseSafeguardWarning = PURCHASE_SAFEGUARD_WARNING,
  }
end

local function resolveSearchItemName(entry)
  local compat = ns.Compat
  if compat and type(compat.ResolveClientLocalizedItemName) == "function" then
    return compat.ResolveClientLocalizedItemName(entry.itemID, entry.name, entry)
  end
  -- Minimal test-runtime fallback when only `Compat.ResolveItemName` is stubbed:
  local getLoc = _G.GetLocale
  local locale = nil
  if type(getLoc) == "function" then
    local okL, loc = pcall(getLoc)
    if okL and type(loc) == "string" and loc ~= "" then
      locale = loc
    end
  end
  local cItem = _G.C_Item
  local getInfo = _G.GetItemInfo
  local itemID = tonumber(entry.itemID)
  local hasLiveAPI = (type(cItem) == "table" and type(cItem.GetItemNameByID) == "function") or type(getInfo) == "function"
  if hasLiveAPI and itemID and itemID > 0 then
    if type(cItem) == "table" and type(cItem.GetItemNameByID) == "function" then
      local okN, nm = pcall(cItem.GetItemNameByID, itemID)
      if okN and type(nm) == "string" and nm ~= "" then
        return nm, "resolved_live"
      end
    end
    if type(getInfo) == "function" then
      local okI, nm = pcall(getInfo, itemID)
      if okI and type(nm) == "string" and nm ~= "" then
        return nm, "resolved_live"
      end
    end
    if type(cItem) == "table" and type(cItem.RequestLoadItemDataByID) == "function" then
      pcall(cItem.RequestLoadItemDataByID, itemID)
    end
    if locale and locale ~= "enUS" and locale ~= "enGB" then
      if entry.nameLocale == locale and type(entry.name) == "string" and entry.name ~= "" then
        return entry.name, "resolved_explicit_locale"
      end
      return nil, "pending_item_cache"
    end
  end
  local fallback = compat and compat.ResolveItemName and compat.ResolveItemName(entry.itemID, entry.name) or nil
  if type(fallback) == "string" and fallback ~= "" then
    return fallback, "resolved_fallback"
  end
  return nil, "unresolved_item_name"
end

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

function AuctionatorProvider.GetLastShoppingListReport()
  return AuctionatorProvider.__lastShoppingListReport
end

-- Encodes discovery-only Auctionator search terms WITHOUT creating or modifying any shopping list.
-- Enforces:
--   1. Public `Auctionator.API.v1.ConvertToSearchString` required; never guesses semicolon field order.
--   2. Optional `maxPrice` / `maxUnitPriceCopper` forwarded ONLY when a finite positive integer `> 0`;
--      explicit `<= 0` or non-finite ceilings are excluded (never emitted as `0` "no limit" or uncapped).
--   3. Cold-cache unresolved localized names become `pending` (`"pending_item_cache"`), never English fallbacks on non-English clients.
--   4. Non-exact affix/variant entries are excluded unless `allowBaseNameDiscovery == true`.
function AuctionatorProvider.PreviewShoppingListTerms(entries, opts)
  local _ = opts
  if not AuctionatorProvider.IsAvailable() then
    return makeEmptyReport("Auctionator is not loaded.")
  end
  local api = _G.Auctionator.API.v1
  if type(api.ConvertToSearchString) ~= "function" then
    return makeEmptyReport(
      "Auctionator search conversion API unavailable. Update Auctionator before creating a shopping list."
    )
  end

  local report = makeEmptyReport(nil)
  for idx, entry in ipairs(entries or {}) do
    if type(entry) == "table" then
      local rawQty = entry.deficitQty
      if rawQty == nil then
        rawQty = entry.buyQty
      end
      if rawQty == nil then
        rawQty = entry.quantity
      end
      local qtyNum = tonumber(rawQty) or 0
      local qty = (qtyNum == qtyNum and qtyNum ~= math.huge and qtyNum ~= -math.huge) and math.floor(qtyNum) or 0
      if qty > 0 then
        local rawMax = entry.maxUnitPriceCopper
        if rawMax == nil then
          rawMax = entry.maxPrice
        end
        local validMaxCopper = nil
        local ceilingInvalid = false
        if rawMax ~= nil then
          if isPositiveIntegerCopper(rawMax) then
            validMaxCopper = rawMax
          else
            ceilingInvalid = true
          end
        end

        if ceilingInvalid then
          table.insert(report.excluded, {
            index = idx,
            itemID = tonumber(entry.itemID),
            quantity = qty,
            reason = "invalid_non_positive_max_price",
          })
        elseif entry.classification ~= nil
          and entry.classification ~= "EXACT_BASE_ITEM"
          and entry.allowBaseNameDiscovery ~= true
        then
          table.insert(report.excluded, {
            index = idx,
            itemID = tonumber(entry.itemID),
            quantity = qty,
            reason = "non_exact_item_variant",
          })
        else
          local resolvedName, nameStatus = resolveSearchItemName(entry)
          if nameStatus == "pending_item_cache" then
            table.insert(report.pending, {
              index = idx,
              itemID = tonumber(entry.itemID),
              quantity = qty,
              reason = "pending_item_cache",
            })
          elseif not resolvedName or resolvedName == "" then
            table.insert(report.excluded, {
              index = idx,
              itemID = tonumber(entry.itemID),
              quantity = qty,
              reason = "unresolved_item_name",
            })
          else
            local searchSpec = {
              searchString = resolvedName,
              isExact = true,
              quantity = qty,
            }
            if validMaxCopper then
              searchSpec.maxPrice = validMaxCopper
              report.hasPriceCeilings = true
            end
            local okConv, term = pcall(api.ConvertToSearchString, CALLER_ID, searchSpec)
            if not okConv or type(term) ~= "string" or term == "" then
              -- Never guess Auctionator's version-dependent serialized field order.
              -- Abort before creating/replacing a list rather than broadening a failed term.
              report.error = "Auctionator could not encode a shopping search. No shopping list was changed."
              report.searchTerms = {}
              report.created = {}
              report.createdCount = 0
              report.isComplete = false
              return report
            end
            table.insert(report.searchTerms, term)
            table.insert(report.created, {
              index = idx,
              itemID = tonumber(entry.itemID),
              searchString = resolvedName,
              quantity = qty,
              maxUnitPriceCopper = validMaxCopper,
              encodedTerm = term,
              resolutionStatus = nameStatus,
            })
          end
        end
      end
    end
  end

  report.createdCount = #report.searchTerms
  report.isComplete = (report.createdCount > 0) and (#report.pending == 0) and (#report.excluded == 0)
  if report.createdCount == 0 then
    if #report.pending > 0 and #report.excluded == 0 then
      report.error = "Could not resolve localized item names yet (waiting for game client item cache; retry in a moment)."
    elseif #report.excluded > 0 or #report.pending > 0 then
      local hasUnresolvedOnly = (#report.pending == 0)
      for _, ex in ipairs(report.excluded) do
        if ex.reason ~= "unresolved_item_name" then
          hasUnresolvedOnly = false
          break
        end
      end
      if hasUnresolvedOnly then
        report.error = "Could not resolve localized item names for missing materials."
      else
        report.error = "No valid shopping searches could be built (check price ceilings or pending item cache)."
      end
    else
      report.error = "No missing materials to shop for."
    end
    report.ok = false
    return report
  end

  report.ok = true
  return report
end

function AuctionatorProvider.CreateShoppingListDetailed(listName, entries, opts)
  if opts and (opts.passiveRefresh == true or opts.userInitiated == false) then
    local blocked = makeEmptyReport("Shopping lists can only be created from an explicit user click.")
    AuctionatorProvider.__lastShoppingListReport = blocked
    return blocked
  end
  if not AuctionatorProvider.IsAvailable() then
    local missing = makeEmptyReport("Auctionator is not loaded.")
    AuctionatorProvider.__lastShoppingListReport = missing
    return missing
  end
  local api = _G.Auctionator.API.v1
  if type(api.CreateShoppingList) ~= "function" then
    local noCreate = makeEmptyReport("Auctionator CreateShoppingList API unavailable.")
    AuctionatorProvider.__lastShoppingListReport = noCreate
    return noCreate
  end

  local report = AuctionatorProvider.PreviewShoppingListTerms(entries, opts)
  if not report.ok then
    AuctionatorProvider.__lastShoppingListReport = report
    return report
  end

  if opts and opts.requireComplete == true and not report.isComplete then
    report.ok = false
    report.error = string.format(
      "Shopping list incomplete (%d pending item cache, %d excluded). No shopping list was changed.",
      #report.pending,
      #report.excluded
    )
    AuctionatorProvider.__lastShoppingListReport = report
    return report
  end

  local finalListName = listName or AuctionatorProvider.GetDefaultShoppingListName()
  local okCall, callErr = pcall(api.CreateShoppingList, CALLER_ID, finalListName, report.searchTerms)
  if not okCall then
    report.ok = false
    report.error = tostring(callErr)
    AuctionatorProvider.__lastShoppingListReport = report
    return report
  end

  report.ok = true
  report.listName = finalListName
  AuctionatorProvider.__lastShoppingListReport = report
  return report
end

function AuctionatorProvider.CreateShoppingList(listName, entries, opts)
  local report = AuctionatorProvider.CreateShoppingListDetailed(listName, entries, opts)
  if not report.ok then
    if opts and opts.returnDetails == true then
      return false, report.error, nil, report
    end
    return false, report.error
  end
  if opts and opts.returnDetails == true then
    return true, report.createdCount, report.listName, report
  end
  return true, report.createdCount, report.listName
end

-- ============================================================================
-- Stage 6A.3 Passive Legacy AH Page Capture State Machine (`Astra P0.3` + `P1.A`)
-- States:
--   CLOSED -> OPEN | CAPABILITIES_PENDING -> OBSERVING_PAGE -> PAGE_CAPTURED ->
--   OBSERVATION_PUBLISHED -> INVALIDATED | CLOSED
-- Invariants:
--   1. Never calls `QueryAuctionItems` or `PlaceAuctionBid` (100% passive read-only).
--   2. Enforces `MAX_PASSIVE_PAGE_ROWS = 100` per-event budget so `getAll` scans never hitch FPS.
--   3. Separates `MULTI_PAGE_QUERY` (known queryKey + pageIndex) from `PAGE_OBSERVATION_ONLY`
--      (unknown query/page context); page 1 never overwrites page 2+ of the same query, and a
--      `PAGE_OBSERVATION_ONLY` slice never clobbers a fuller multi-page ladder in the same session.
--   4. Never retains ephemeral `"list"` row indices; stamps `OWNERSHIP_UNRESOLVED` when `owner == nil`
--      and excludes confirmed self-listings (`owner == playerName`).
--   5. Enforces 4-state `P0.3` lifecycle:
--      `RETAINED_OBSERVATION` -> `RECENT_DISCOVERY_CANDIDATE` -> `CURRENT_NATIVE_LISTING_RECHECK` -> `COMPLETED_PURCHASE`
-- ============================================================================

AuctionatorProvider.MAX_PASSIVE_PAGE_ROWS = 100
AuctionatorProvider.OBSERVATION_STAGES = {
  RETAINED_OBSERVATION = "RETAINED_OBSERVATION",
  RECENT_DISCOVERY_CANDIDATE = "RECENT_DISCOVERY_CANDIDATE",
  CURRENT_NATIVE_LISTING_RECHECK = "CURRENT_NATIVE_LISTING_RECHECK",
  COMPLETED_PURCHASE = "COMPLETED_PURCHASE",
}

AuctionatorProvider.__passiveCapture = {
  state = "CLOSED",
  sessionGenerationID = 0,
  venueKey = nil,
  activeQuery = nil,
  pagesByQueryAndItem = {},
  pageOnlyByItem = {},
  queryHookInstalled = false,
}

function AuctionatorProvider.GetPassiveCaptureState()
  return AuctionatorProvider.__passiveCapture
end

function AuctionatorProvider.GetObservedSessionLotsForItem(itemID)
  local id = tonumber(itemID)
  if not id or id <= 0 then
    return {}
  end
  local map = ns.State and ns.State.sessionObservedAuctionLotsByItemID
  if type(map) ~= "table" then
    return {}
  end
  return map[math.floor(id)] or {}
end

function AuctionatorProvider.RecordPassiveQueryContext(searchName, minLevel, maxLevel, pageIndex, quality, getAll, exactMatch)
  local pc = AuctionatorProvider.__passiveCapture
  if not pc or pc.state == "CLOSED" then
    return
  end
  local pIdx = tonumber(pageIndex)
  if pIdx == nil or pIdx < 0 or math.floor(pIdx) ~= pIdx then
    pc.activeQuery = nil
    return
  end
  local qKey = string.format(
    "q:%s:%s:%s:%s:%s",
    string.lower(tostring(searchName or "")),
    tostring(tonumber(minLevel) or ""),
    tostring(tonumber(maxLevel) or ""),
    tostring(tonumber(quality) or ""),
    exactMatch == true and "1" or "0"
  )
  pc.activeQuery = {
    queryKey = qKey,
    pageIndex = math.floor(pIdx),
    isFullScan = (getAll == true),
    recordedAtGeneration = pc.sessionGenerationID,
  }
end

function AuctionatorProvider.EnsurePassiveQueryHookInstalled()
  local pc = AuctionatorProvider.__passiveCapture
  if pc.queryHookInstalled then
    return true
  end
  if type(_G.hooksecurefunc) == "function" and type(_G.QueryAuctionItems) == "function" then
    local ok = pcall(_G.hooksecurefunc, "QueryAuctionItems", function(name, minLevel, maxLevel, page, _, quality, getAll, exactMatch)
      AuctionatorProvider.RecordPassiveQueryContext(name, minLevel, maxLevel, page, quality, getAll, exactMatch)
    end)
    if ok then
      pc.queryHookInstalled = true
      return true
    end
  end
  return false
end

function AuctionatorProvider.OnAuctionHouseShow(opts)
  opts = type(opts) == "table" and opts or {}
  local pc = AuctionatorProvider.__passiveCapture
  pc.sessionGenerationID = (pc.sessionGenerationID or 0) + 1
  pc.activeQuery = nil
  pc.pagesByQueryAndItem = {}
  pc.pageOnlyByItem = {}
  pc.venueKey = tostring(opts.venueKey or "active_ah_session")

  AuctionatorProvider.EnsurePassiveQueryHookInstalled()
  local hasLegacyListAPI = (type(_G.GetNumAuctionItems) == "function") and (type(_G.GetAuctionItemInfo) == "function")
  pc.state = hasLegacyListAPI and "OPEN" or "CAPABILITIES_PENDING"
  return pc
end

function AuctionatorProvider.InvalidatePassiveSession(reason)
  local pc = AuctionatorProvider.__passiveCapture
  pc.sessionGenerationID = (pc.sessionGenerationID or 0) + 1
  pc.activeQuery = nil
  pc.state = "INVALIDATED"
  pc.invalidationReason = tostring(reason or "session_invalidated")
  -- Mark any retained session lots as non-live `RETAINED_OBSERVATION`:
  if ns.State and type(ns.State.sessionObservedAuctionLotsByItemID) == "table" then
    for _, lots in pairs(ns.State.sessionObservedAuctionLotsByItemID) do
      for _, lot in ipairs(lots) do
        lot.liveWindowCertified = false
        lot.observationStage = AuctionatorProvider.OBSERVATION_STAGES.RETAINED_OBSERVATION
      end
    end
  end
  return pc
end

function AuctionatorProvider.OnAuctionHouseClosed()
  local pc = AuctionatorProvider.InvalidatePassiveSession("auction_house_closed")
  pc.state = "CLOSED"
  return pc
end

local function rebuildPublishedSessionLots(pc)
  local mergedByItemID = {}
  local hasMultiPageItem = {}

  -- 1. Assemble multi-page query ladders (non-destructive across page indices 0, 1, 2...):
  for _, itemMap in pairs(pc.pagesByQueryAndItem or {}) do
    for itemID, pagesTbl in pairs(itemMap) do
      local pageNums = {}
      for pIdx in pairs(pagesTbl) do
        table.insert(pageNums, pIdx)
      end
      table.sort(pageNums)
      local combined = mergedByItemID[itemID] or {}
      for _, pIdx in ipairs(pageNums) do
        for _, lot in ipairs(pagesTbl[pIdx] or {}) do
          table.insert(combined, lot)
        end
      end
      if #combined > 0 then
        mergedByItemID[itemID] = combined
        if #pageNums > 1 then
          hasMultiPageItem[itemID] = true
        end
      end
    end
  end

  -- 2. Include `PAGE_OBSERVATION_ONLY` slices ONLY when they do NOT clobber a multi-page ladder:
  for itemID, pageLots in pairs(pc.pageOnlyByItem or {}) do
    if not hasMultiPageItem[itemID] then
      local existing = mergedByItemID[itemID]
      if not existing or #pageLots >= #existing then
        mergedByItemID[itemID] = pageLots
      end
    end
  end

  if ns.State then
    ns.State.sessionObservedAuctionLotsByItemID = mergedByItemID
  end
  if ns.Domain and ns.Domain.VendorArbitrage and type(ns.Domain.VendorArbitrage.BumpCaptureRevision) == "function" then
    ns.Domain.VendorArbitrage.BumpCaptureRevision()
  end
  return mergedByItemID
end

function AuctionatorProvider.CapturePassiveLegacyAuctionPage(opts)
  if type(opts) == "number" then
    opts = { nowEpoch = opts }
  else
    opts = type(opts) == "table" and opts or {}
  end
  local pc = AuctionatorProvider.__passiveCapture
  if not pc or pc.state == "CLOSED" or pc.state == "INVALIDATED" then
    return { captured = false, state = pc and pc.state or "CLOSED", reason = "ah_session_not_open" }
  end
  if ns.Compat and ns.Compat.IsInCombat and ns.Compat.IsInCombat() then
    return { captured = false, state = pc.state, reason = "in_combat_lockdown" }
  end
  if type(_G.GetNumAuctionItems) ~= "function" or type(_G.GetAuctionItemInfo) ~= "function" then
    pc.state = "CAPABILITIES_PENDING"
    return { captured = false, state = pc.state, reason = "legacy_ah_api_unavailable" }
  end

  local expectedGen = pc.sessionGenerationID
  pc.state = "OBSERVING_PAGE"

  local okCnt, batchCount, totalCount = pcall(_G.GetNumAuctionItems, "list")
  if not okCnt or type(batchCount) ~= "number" or batchCount < 0 then
    pc.state = "OPEN"
    return { captured = false, state = pc.state, reason = "batch_count_unavailable" }
  end

  local bc = math.floor(batchCount)
  local maxRows = tonumber(opts.maxRowsPerCapture) or AuctionatorProvider.MAX_PASSIVE_PAGE_ROWS
  local inspectCount = math.min(bc, math.max(1, math.floor(maxRows)))
  local truncatedByBudget = (bc > inspectCount)

  local clocks = (ns.Compat and ns.Compat.GetDualClockNow and ns.Compat.GetDualClockNow()) or {}
  local nowEpoch = tonumber(opts.nowEpoch) or tonumber(clocks.serverEpoch) or 1
  local playerName = (ns.Compat and ns.Compat.GetCharacterKey and select(1, ns.Compat.GetCharacterKey())) or nil

  local activeQ = pc.activeQuery
  if opts.explicitQueryKey ~= nil and opts.explicitPageIndex ~= nil then
    activeQ = {
      queryKey = tostring(opts.explicitQueryKey),
      pageIndex = math.floor(tonumber(opts.explicitPageIndex) or 0),
      isFullScan = (opts.isFullScan == true),
      recordedAtGeneration = expectedGen,
    }
  end

  local isAttributedQueryPage = (
    type(activeQ) == "table"
    and activeQ.recordedAtGeneration == expectedGen
    and activeQ.isFullScan ~= true
    and not truncatedByBudget
  )
  local captureScope = isAttributedQueryPage and "MULTI_PAGE_QUERY" or "PAGE_OBSERVATION_ONLY"
  local numTotal = tonumber(totalCount)
  local completeness = (truncatedByBudget or not isAttributedQueryPage or (numTotal and numTotal > bc))
      and "PAGE_OBSERVATION_ONLY"
    or "MULTI_PAGE_QUERY"

  local lotsByItemOnPage = {}
  local capturedLotCount = 0
  local discoveryLotCount = 0
  local unresolvedOwnerCount = 0
  local skippedSelfListingCount = 0
  local skippedBidOnlyCount = 0

  for idx = 1, inspectCount do
    -- Exact `1.60.1.70938` tuple: 3=count, 8=minBid, 10=buyoutPrice, 11=bidAmount, 14=owner, 16=saleStatus, 17=itemId
    local okRow, _, _, count, _, _, _, _, minBid, _, buyoutPrice, bidAmount, _, _, owner, _, saleStatus, rawItemID =
      pcall(_G.GetAuctionItemInfo, "list", idx)
    if okRow and tonumber(saleStatus) ~= 1 then
      local itemLink = nil
      if type(_G.GetAuctionItemLink) == "function" then
        local okL, lnk = pcall(_G.GetAuctionItemLink, "list", idx)
        if okL and type(lnk) == "string" and lnk ~= "" then
          itemLink = lnk
        end
      end

      local itemID = tonumber(rawItemID)
      if (not itemID or itemID <= 0) and itemLink and ns.Compat and ns.Compat.ExtractItemID then
        itemID = ns.Compat.ExtractItemID(itemLink)
      end

      local stackSize = tonumber(count)
      local buyout = tonumber(buyoutPrice)

      if itemID and itemID > 0 and stackSize and stackSize >= 1 then
        local ownerKnown = (type(owner) == "string" and owner ~= "")
        local isSelf = (ownerKnown and playerName ~= nil and owner == playerName)
        if isSelf then
          skippedSelfListingCount = skippedSelfListingCount + 1
        else
          if not ownerKnown then
            unresolvedOwnerCount = unresolvedOwnerCount + 1
          end
          local hasBuyout = (buyout and buyout > 0)
          if not hasBuyout then
            skippedBidOnlyCount = skippedBidOnlyCount + 1
          elseif ownerKnown then
            discoveryLotCount = discoveryLotCount + 1
          end
          -- Never store ephemeral `"list"` index! Hyperlink never certifies unobserved durability/charges.
          local lotRecord = {
            itemID = math.floor(itemID),
            itemLink = itemLink,
            stackSize = math.floor(stackSize),
            buyoutCopper = hasBuyout and math.floor(buyout) or 0,
            minBidCopper = tonumber(minBid) and math.floor(tonumber(minBid)) or 0,
            bidAmountCopper = tonumber(bidAmount) and math.floor(tonumber(bidAmount)) or 0,
            observedAt = math.floor(nowEpoch),
            sessionGenerationID = expectedGen,
            captureScope = captureScope,
            observationStage = AuctionatorProvider.OBSERVATION_STAGES.RETAINED_OBSERVATION,
            liveWindowCertified = true,
            durabilityCertified = false,
            chargesCertified = false,
            ownershipStatus = ownerKnown and "FOREIGN_LISTING" or "OWNERSHIP_UNRESOLVED",
          }
          lotsByItemOnPage[lotRecord.itemID] = lotsByItemOnPage[lotRecord.itemID] or {}
          table.insert(lotsByItemOnPage[lotRecord.itemID], lotRecord)
          capturedLotCount = capturedLotCount + 1
        end
      end
    end
  end

  -- Guard against mid-capture invalidation:
  if pc.sessionGenerationID ~= expectedGen or pc.state == "CLOSED" or pc.state == "INVALIDATED" then
    return { captured = false, state = pc.state, reason = "invalidated_during_capture" }
  end

  pc.state = "PAGE_CAPTURED"
  if isAttributedQueryPage and activeQ then
    local qKey = activeQ.queryKey
    local pIdx = activeQ.pageIndex
    pc.pagesByQueryAndItem[qKey] = pc.pagesByQueryAndItem[qKey] or {}
    for itemID, itemLots in pairs(lotsByItemOnPage) do
      pc.pagesByQueryAndItem[qKey][itemID] = pc.pagesByQueryAndItem[qKey][itemID] or {}
      pc.pagesByQueryAndItem[qKey][itemID][pIdx] = itemLots
    end
  else
    for itemID, itemLots in pairs(lotsByItemOnPage) do
      pc.pageOnlyByItem[itemID] = itemLots
    end
  end

  rebuildPublishedSessionLots(pc)
  pc.state = "OBSERVATION_PUBLISHED"

  return {
    captured = true,
    state = pc.state,
    captureScope = captureScope,
    completeness = completeness,
    batchCount = bc,
    totalCount = numTotal,
    inspectedRowCount = inspectCount,
    truncatedByFrameBudget = truncatedByBudget,
    capturedLotCount = capturedLotCount,
    discoveryLotCount = discoveryLotCount,
    unresolvedOwnerCount = unresolvedOwnerCount,
    skippedSelfListingCount = skippedSelfListingCount,
    skippedBidOnlyCount = skippedBidOnlyCount,
  }
end

-- Stage `P0.3` Tier 3 (`CURRENT_NATIVE_LISTING_RECHECK`):
-- Verifies a native AH listing row immediately before user confirmation without relying on stale indices.
function AuctionatorProvider.VerifyNativeListingForRecheck(expectedLot, nativeRow)
  if type(expectedLot) ~= "table" or type(nativeRow) ~= "table" then
    return { verified = false, stage = AuctionatorProvider.OBSERVATION_STAGES.CURRENT_NATIVE_LISTING_RECHECK, reason = "missing_listing_data" }
  end
  if tonumber(expectedLot.itemID) ~= tonumber(nativeRow.itemID) then
    return { verified = false, stage = AuctionatorProvider.OBSERVATION_STAGES.CURRENT_NATIVE_LISTING_RECHECK, reason = "item_id_mismatch" }
  end
  if tonumber(expectedLot.stackSize) ~= tonumber(nativeRow.stackSize) then
    return { verified = false, stage = AuctionatorProvider.OBSERVATION_STAGES.CURRENT_NATIVE_LISTING_RECHECK, reason = "stack_size_changed" }
  end
  local expBuyout = tonumber(expectedLot.buyoutCopper)
  local curBuyout = tonumber(nativeRow.buyoutCopper)
  if not expBuyout or not curBuyout or curBuyout <= 0 or curBuyout > expBuyout then
    return { verified = false, stage = AuctionatorProvider.OBSERVATION_STAGES.CURRENT_NATIVE_LISTING_RECHECK, reason = "buyout_missing_or_increased" }
  end
  if nativeRow.isDamaged == true or nativeRow.hasDepletedCharges == true then
    return { verified = false, stage = AuctionatorProvider.OBSERVATION_STAGES.CURRENT_NATIVE_LISTING_RECHECK, reason = "damaged_or_depleted_instance_state" }
  end
  if nativeRow.isSelfListing == true then
    return { verified = false, stage = AuctionatorProvider.OBSERVATION_STAGES.CURRENT_NATIVE_LISTING_RECHECK, reason = "self_listing_cannot_flip" }
  end
  return {
    verified = true,
    stage = AuctionatorProvider.OBSERVATION_STAGES.CURRENT_NATIVE_LISTING_RECHECK,
    verifiedBuyoutCopper = curBuyout,
    stackSize = tonumber(nativeRow.stackSize),
  }
end

return AuctionatorProvider
