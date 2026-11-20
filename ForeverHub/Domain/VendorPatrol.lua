local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.Domain = ns.Domain or {}

local VendorPatrol = {}
ns.Domain.VendorPatrol = VendorPatrol

VendorPatrol.SCHEMA = "foreverhub-vendor-patrol-v1"
VendorPatrol.MAX_ENTRIES = 64
VendorPatrol.MAX_SERIALIZED_BYTES = 16384 -- 16 KiB hard cap
VendorPatrol.OBSERVATION_LABEL = "Observed vendor memory (stock and price at last visit; no restock prediction)"

local MAX_SAFE_INT = 9007199254740991

local function isPositiveInt(v)
  return type(v) == "number" and v == v and v >= 1 and v <= MAX_SAFE_INT and math.floor(v) == v
end

local function isNonNegInt(v)
  return type(v) == "number" and v == v and v >= 0 and v <= MAX_SAFE_INT and math.floor(v) == v
end

local function resolveServerEpoch(explicitEpoch)
  if isPositiveInt(explicitEpoch) then
    return explicitEpoch
  end
  if ns.Compat and type(ns.Compat.GetDualClockNow) == "function" then
    local c = ns.Compat.GetDualClockNow()
    if type(c) == "table" and isPositiveInt(tonumber(c.serverEpoch)) then
      return math.floor(tonumber(c.serverEpoch))
    end
  end
  if type(_G.GetServerTime) == "function" then
    local ok, t = pcall(_G.GetServerTime)
    if ok and isPositiveInt(tonumber(t)) then
      return math.floor(tonumber(t))
    end
  end
  return 0
end

local function estimateEntryBytes(entry)
  return 164
    + string.len(tostring(entry.observationKey or ""))
    + string.len(tostring(entry.itemKey or ""))
    + string.len(tostring(entry.itemName or ""))
    + string.len(tostring(entry.standingOrDiscountContext or ""))
end

function VendorPatrol.EnsureInitialized()
  local host = nil
  if ns.State and type(ns.State.GetDB) == "function" then
    local ok, db = pcall(ns.State.GetDB)
    if ok and type(db) == "table" then
      host = db
    end
  end
  if not host then
    VendorPatrol.__ephemeralHost = VendorPatrol.__ephemeralHost or {}
    host = VendorPatrol.__ephemeralHost
  end

  if type(host.vendorPatrol) ~= "table" or host.vendorPatrol.schema ~= VendorPatrol.SCHEMA then
    host.vendorPatrol = {
      schema = VendorPatrol.SCHEMA,
      entries = {},
      estimatedBytes = 96,
      droppedByCapCount = 0,
      droppedByByteBudgetCount = 0,
    }
  end
  local store = host.vendorPatrol
  store.entries = type(store.entries) == "table" and store.entries or {}
  return store
end

local function enforceBounds(store)
  while #store.entries > VendorPatrol.MAX_ENTRIES do
    table.remove(store.entries, 1)
    store.droppedByCapCount = (store.droppedByCapCount or 0) + 1
  end
  while true do
    local bytes = 96
    for _, e in ipairs(store.entries) do
      bytes = bytes + estimateEntryBytes(e)
    end
    store.estimatedBytes = bytes
    if bytes <= VendorPatrol.MAX_SERIALIZED_BYTES or #store.entries == 0 then
      break
    end
    table.remove(store.entries, 1)
    store.droppedByByteBudgetCount = (store.droppedByByteBudgetCount or 0) + 1
  end
end

function VendorPatrol.RecordMerchantOfferObservation(obs)
  if type(obs) ~= "table" then
    return false, "invalid_observation"
  end

  local itemID = tonumber(obs.itemID)
  local bundleQty = tonumber(obs.bundleQuantity)
  local observedPrice = tonumber(obs.observedClientPriceCopper or obs.bundlePriceCopper)
  if not isPositiveInt(itemID) or not isPositiveInt(bundleQty) or not isPositiveInt(observedPrice) then
    return false, "invalid_item_bundle_or_price"
  end
  if obs.extendedCost == true then
    return false, "extended_cost_excluded"
  end

  local itemKey = tostring(obs.itemKey or string.format("i1:base:%d", itemID))
  if string.find(itemKey, "^i1:unk_var:") or string.find(itemKey, "^i1:service:") then
    return false, "non_canonical_item_key"
  end

  -- Strict GUID validation (`UNKNOWN_NPC` fallback when GUID is missing, player, or malformed):
  local npcIdentityStatus = "UNKNOWN_NPC"
  local npcType = nil
  local npcID = nil
  if isPositiveInt(tonumber(obs.verifiedNpcID)) then
    npcIdentityStatus = "VERIFIED_NPC_GUID"
    npcType = tostring(obs.npcType or "creature")
    npcID = math.floor(tonumber(obs.verifiedNpcID))
  elseif type(obs.rawNpcGuid) == "string" and ns.Compat and type(ns.Compat.ParseCreatureGUIDSafe) == "function" then
    local parsed = ns.Compat.ParseCreatureGUIDSafe(obs.rawNpcGuid)
    if parsed and parsed.status == "VERIFIED_NPC_GUID" then
      npcIdentityStatus = "VERIFIED_NPC_GUID"
      npcType = parsed.npcType
      npcID = parsed.npcID
    end
  end

  local uiMapID = isPositiveInt(tonumber(obs.uiMapID)) and math.floor(tonumber(obs.uiMapID)) or nil
  local stockMode = (obs.stockMode == "LIMITED" or obs.stockMode == "UNLIMITED") and obs.stockMode or "UNKNOWN"
  local stockObserved = (stockMode == "LIMITED" and isNonNegInt(tonumber(obs.stockObserved or obs.stockQuantity)))
      and math.floor(tonumber(obs.stockObserved or obs.stockQuantity))
    or nil
  local nowEpoch = resolveServerEpoch(obs.observedAtServerEpoch)

  local obsKey = string.format(
    "%s:%s|map:%s|%s",
    npcIdentityStatus,
    tostring(npcID or "unknown"),
    tostring(uiMapID or 0),
    itemKey
  )

  local store = VendorPatrol.EnsureInitialized()
  -- Replace existing observation for the exact same `(npc, map, itemKey)` so latest visit wins cleanly:
  for idx = #store.entries, 1, -1 do
    if store.entries[idx].observationKey == obsKey then
      table.remove(store.entries, idx)
    end
  end

  local record = {
    observationKey = obsKey,
    npcIdentityStatus = npcIdentityStatus,
    npcType = npcType,
    npcID = npcID,
    uiMapID = uiMapID,
    itemID = itemID,
    itemKey = itemKey,
    itemName = type(obs.itemName) == "string" and string.sub(obs.itemName, 1, 64) or nil,
    bundleQuantity = bundleQty,
    observedClientPriceCopper = observedPrice, -- Stored verbatim; NEVER re-applies assumed discounts!
    effectiveUnitCostCeilCopper = math.ceil(observedPrice / bundleQty),
    reappliesAssumedDiscount = false,
    stockMode = stockMode,
    stockObserved = stockObserved,
    predictsRestockTimer = false,
    restockCountdownSeconds = nil, -- Permanently prohibited (`7B.2`)!
    standingOrDiscountContext = tostring(obs.standingOrDiscountContext or "client_reported_verbatim"),
    metadataComplete = (obs.metadataComplete == true),
    observedAtServerEpoch = nowEpoch,
  }

  table.insert(store.entries, record)
  enforceBounds(store)
  return true, record
end

function VendorPatrol.GetNearbyObservations(uiMapID, nowEpoch)
  local store = VendorPatrol.EnsureInitialized()
  local mapNum = tonumber(uiMapID)
  local ep = resolveServerEpoch(nowEpoch)
  local matches = {}
  for i = #store.entries, 1, -1 do
    local e = store.entries[i]
    if mapNum == nil or e.uiMapID == mapNum then
      local ageSec = (isPositiveInt(ep) and isPositiveInt(e.observedAtServerEpoch) and ep >= e.observedAtServerEpoch)
          and (ep - e.observedAtServerEpoch)
        or nil
      table.insert(matches, {
        entry = e,
        ageSeconds = ageSec,
        basisLabel = VendorPatrol.OBSERVATION_LABEL,
      })
    end
  end
  return matches
end

return VendorPatrol
