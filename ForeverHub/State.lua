local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
local State = ns.State or {}
ns.State = State

State.bankOpen = false
State.sessionBankObserved = false
State.sessionBankSnapshot = nil
State.lastSuggestionSnapshot = nil
State.pendingSuggestionPreview = nil
State.lastManualCompletionSeq = 0
State.listeners = {}

State.inventoryRevision = 1
State.reservationRevision = 1
State.priceRevision = 1

local DEFAULT_STALE_DAYS = 2

function State.BumpInventoryRevision()
  State.inventoryRevision = (State.inventoryRevision or 1) + 1
  State.NotifyChanged()
end

function State.BumpReservationRevision()
  State.reservationRevision = (State.reservationRevision or 1) + 1
  State.pendingSuggestionPreview = nil
  if ns.Providers and ns.Providers.Inventory and ns.Providers.Inventory.OnReservationRevisionChanged then
    pcall(ns.Providers.Inventory.OnReservationRevisionChanged, State.reservationRevision)
  end
  State.NotifyChanged()
end

function State.BumpPriceRevision()
  State.priceRevision = (State.priceRevision or 1) + 1
  State.NotifyChanged()
end

function State.GetRevisions()
  return State.inventoryRevision or 1, State.reservationRevision or 1, State.priceRevision or 1
end

function State.SetSessionBankObserved(snapshot)
  if type(snapshot) == "table" and snapshot.available == true and snapshot.complete == true then
    State.sessionBankObserved = true
    State.sessionBankSnapshot = snapshot
  else
    State.sessionBankObserved = false
    State.sessionBankSnapshot = nil
  end
end

function State.HasSessionBankObservation()
  return State.sessionBankObserved == true
    and type(State.sessionBankSnapshot) == "table"
    and State.sessionBankSnapshot.available == true
    and State.sessionBankSnapshot.complete == true
end

function State.Init(isAddonLoad)
  if isAddonLoad then
    State.sessionBankObserved = false
    State.sessionBankSnapshot = nil
  end

  if type(_G.ForeverHubDB) ~= "table" then
    _G.ForeverHubDB = {}
  end
  local db = _G.ForeverHubDB
  db.schemaVersion = 2
  db.characters = db.characters or {}
  db.discoveredQuestIds = type(db.discoveredQuestIds) == "table" and db.discoveredQuestIds or {}
  db.discoveredQuestTitlesById = type(db.discoveredQuestTitlesById) == "table" and db.discoveredQuestTitlesById or {}
  db.fieldCaptures = type(db.fieldCaptures) == "table" and db.fieldCaptures or {}
  db.macroSync = type(db.macroSync) == "table" and db.macroSync or {}
  for normTitle, rawQid in pairs(db.discoveredQuestIds) do
    local nQid = tonumber(rawQid)
    if type(normTitle) == "string" and normTitle ~= "" and nQid and nQid > 0 then
      db.discoveredQuestTitlesById[nQid] = normTitle
    end
  end
  db.settings = db.settings or {
    staleAgeDays = DEFAULT_STALE_DAYS,
    showOnlyOwnedCrates = true,
    includeAltStock = false,
    acquisitionMode = "after_bank",
  }
  if db.settings.includeAltStock == nil then
    db.settings.includeAltStock = false
  end
  if db.settings.acquisitionMode ~= "bags_only" then
    db.settings.acquisitionMode = "after_bank"
  end

  if type(_G.ForeverHubCharDB) ~= "table" then
    _G.ForeverHubCharDB = {}
  end
  local charDB = _G.ForeverHubCharDB
  charDB.schemaVersion = 2
  -- Never persist sessionBankObserved in SavedVariables (runtime-only authority!)
  charDB.sessionBankObserved = nil

  local _, _, ownerKey = ns.Compat.GetCharacterKey()
  charDB.ownerKey = ownerKey
  charDB.nextPriority = charDB.nextPriority or 1
  charDB.reservations = charDB.reservations or {}
  charDB.macroSync = type(charDB.macroSync) == "table" and charDB.macroSync or {}
  charDB.diagnosticTrace = charDB.diagnosticTrace or {
    enabled = true,
    maxEntries = 250,
    nextSeq = 1,
    entries = {},
  }
  charDB.bankSnapshot = charDB.bankSnapshot or {
    available = false,
    complete = false,
    observedAt = nil,
    source = "none",
    tabIDs = {},
    counts = {},
  }

  -- Migrate any legacy v1 account-wide reservations once into the first loaded character
  if type(db.reservations) == "table" and not db.migratedV1Reservations then
    for k, legacyRes in pairs(db.reservations) do
      if type(legacyRes) == "table" and not charDB.reservations[k] then
        local gKey = legacyRes.goalKey or State.BuildGoalKey(legacyRes.kind or "crate", legacyRes.targetItemID)
        if not charDB.reservations[gKey] then
          legacyRes.ownerKey = ownerKey
          legacyRes.goalKey = gKey
          legacyRes.quantity = math.max(1, math.floor(tonumber(legacyRes.quantity) or 1))
          legacyRes.priority = tonumber(legacyRes.priority) or charDB.nextPriority
          charDB.nextPriority = math.max(charDB.nextPriority, legacyRes.priority + 1)
          charDB.reservations[gKey] = legacyRes
        end
      end
    end
    db.migratedV1Reservations = ownerKey
    db.reservations = nil
  end

  -- Mirror current character's plan under account table keyed by ownerKey
  db.characters[ownerKey] = {
    ownerKey = ownerKey,
    reservations = charDB.reservations,
    updatedAt = time and time() or 0,
  }

  -- Retire legacy Riverglades routeProgress from SavedVariables
  charDB.routeProgress = nil

  State.EnsureNavigationOwnerInitialized()
  State.EnsureMountTrackerInitialized(isAddonLoad)
  State.EnsureGoldFarmProgressInitialized(isAddonLoad)
  State.EnsureArrowSettingsInitialized()
  State.EnsureWorldMapPinSettingsInitialized()
  State.EnsureMinimapSettingsInitialized()
  State.EnsureWorkspaceUIStateInitialized(isAddonLoad)
  if ns.Domain and ns.Domain.MarketAccounting and type(ns.Domain.MarketAccounting.EnsureMarketExportInitialized) == "function" then
    ns.Domain.MarketAccounting.EnsureMarketExportInitialized()
  end
end

function State.GetDB()
  if type(_G.ForeverHubDB) ~= "table" or _G.ForeverHubDB.schemaVersion ~= 2 then
    State.Init()
  end
  return _G.ForeverHubDB
end

function State.GetCharDB()
  if type(_G.ForeverHubCharDB) ~= "table" or _G.ForeverHubCharDB.schemaVersion ~= 2 then
    State.Init()
  end
  return _G.ForeverHubCharDB
end

function State.GetDiagnosticTrace()
  local charDB = State.GetCharDB()
  charDB.diagnosticTrace = charDB.diagnosticTrace or {
    enabled = true,
    maxEntries = 250,
    nextSeq = 1,
    entries = {},
  }
  return charDB.diagnosticTrace
end

function State.GetStaleAgeDays()
  local db = State.GetDB()
  return (db.settings and db.settings.staleAgeDays) or DEFAULT_STALE_DAYS
end

function State.GetIncludeAltStock()
  local db = State.GetDB()
  return (db.settings and db.settings.includeAltStock == true) or false
end

function State.SetIncludeAltStock(enabled)
  local db = State.GetDB()
  db.settings.includeAltStock = (enabled == true)
  State.BumpInventoryRevision()
end

function State.GetAcquisitionMode()
  local db = State.GetDB()
  local m = db.settings and db.settings.acquisitionMode
  if m == "bags_only" then
    return "bags_only"
  end
  return "after_bank"
end

function State.SetAcquisitionMode(mode)
  local db = State.GetDB()
  if mode == "bags_only" then
    db.settings.acquisitionMode = "bags_only"
  else
    db.settings.acquisitionMode = "after_bank"
  end
  State.BumpReservationRevision()
end

function State.BuildGoalKey(kind, targetItemID)
  return string.format("%s:%d", tostring(kind or "crate"), tonumber(targetItemID) or 0)
end

function State.BuildGoalID(kind, targetItemID, optionIndex)
  return string.format("%s:%d:%d", tostring(kind or "crate"), tonumber(targetItemID) or 0, tonumber(optionIndex) or 1)
end

function State.GetReservations()
  local charDB = State.GetCharDB()
  return charDB.reservations or {}
end

function State.GetOrderedReservations()
  local list = {}
  for _, res in pairs(State.GetReservations()) do
    if type(res) == "table" and (res.goalKey or res.goalID) then
      table.insert(list, res)
    end
  end
  table.sort(list, function(a, b)
    local pa = tonumber(a.priority) or 999999
    local pb = tonumber(b.priority) or 999999
    if pa ~= pb then
      return pa < pb
    end
    return tostring(a.goalKey or a.goalID) < tostring(b.goalKey or b.goalID)
  end)
  return list
end

function State.GetReservedOptionForTarget(kind, targetItemID)
  local goalKey = State.BuildGoalKey(kind, targetItemID)
  local reservations = State.GetReservations()
  if reservations[goalKey] then
    return reservations[goalKey]
  end
  -- Backwards-compatible fallback if keyed by goalID
  local prefix = goalKey .. ":"
  for k, res in pairs(reservations) do
    if string.sub(k, 1, #prefix) == prefix then
      return res
    end
  end
  return nil
end

function State.IsOptionReserved(kind, targetItemID, optionIndex)
  local existing = State.GetReservedOptionForTarget(kind, targetItemID)
  if existing and tonumber(existing.optionIndex) == tonumber(optionIndex) then
    return true, existing.goalKey, existing
  end
  return false, State.BuildGoalKey(kind, targetItemID), nil
end

local function scaleMaterials(unitMaterials, quantity)
  local scaled = {}
  local q = math.max(1, math.floor(tonumber(quantity) or 1))
  for _, m in ipairs(unitMaterials or {}) do
    local uQty = math.max(1, math.floor(tonumber(m.quantity) or 1))
    table.insert(scaled, {
      itemID = m.itemID,
      name = m.name,
      unitQuantity = uQty,
      quantity = uQty * q,
    })
  end
  return scaled
end

-- Creates or updates a character-owned reservation.
-- Preserves existing priority when changing optionIndex or quantity on an already-reserved crate/writ.
function State.ReserveGoal(kind, targetItemID, optionIndex, explicitQuantity)
  local charDB = State.GetCharDB()
  targetItemID = tonumber(targetItemID)
  optionIndex = tonumber(optionIndex) or 1
  if not targetItemID then
    return false, "Invalid item ID."
  end

  local parsedExplicitQty = nil
  if explicitQuantity ~= nil then
    local qNum = tonumber(explicitQuantity)
    if not qNum or qNum <= 0 or math.floor(qNum) ~= qNum then
      return false, "Invalid quantity: must be a positive integer >= 1."
    end
    parsedExplicitQty = math.floor(qNum)
  end

  local targetName = nil
  local unitMaterials = {}

  if kind == "writ" then
    local writ = ns.Data and ns.Data.writsByItemID and ns.Data.writsByItemID[targetItemID]
    if not writ then
      return false, "Unknown Craftsman's Writ item ID: " .. tostring(targetItemID)
    end
    targetName = writ.name
    optionIndex = 1
    table.insert(unitMaterials, {
      itemID = writ.targetItemID,
      name = writ.targetItemName,
      quantity = writ.quantity or 1,
    })
  else
    kind = "crate"
    local crate = ns.Data and ns.Data.cratesByItemID and ns.Data.cratesByItemID[targetItemID]
    if not crate then
      return false, "Unknown Waylaid Crate item ID: " .. tostring(targetItemID)
    end
    local alt = nil
    for _, candidate in ipairs(crate.alternatives or {}) do
      if candidate.optionIndex == optionIndex then
        alt = candidate
        break
      end
    end
    if not alt then
      return false, string.format("Waylaid Crate %s has no option #%d.", crate.name, optionIndex)
    end
    targetName = crate.name
    for _, mat in ipairs(alt.materials or {}) do
      table.insert(unitMaterials, {
        itemID = mat.itemID,
        name = mat.name,
        quantity = mat.quantity,
      })
    end
  end

  local goalKey = State.BuildGoalKey(kind, targetItemID)
  local existing = State.GetReservedOptionForTarget(kind, targetItemID)

  -- Preserve priority when updating option or quantity; only allocate a new priority for a new goalKey
  local priority
  local quantity
  if existing then
    priority = tonumber(existing.priority) or 1
    if parsedExplicitQty ~= nil then
      quantity = parsedExplicitQty
    else
      quantity = math.max(1, math.floor(tonumber(existing.quantity) or 1))
    end
    -- Clean up any legacy goalID key if present
    if existing.goalID and charDB.reservations[existing.goalID] and existing.goalID ~= goalKey then
      charDB.reservations[existing.goalID] = nil
    end
  else
    priority = charDB.nextPriority or 1
    charDB.nextPriority = priority + 1
    quantity = parsedExplicitQty or 1
  end

  local _, _, ownerKey = ns.Compat.GetCharacterKey()
  local goalID = State.BuildGoalID(kind, targetItemID, optionIndex)

  charDB.reservations[goalKey] = {
    ownerKey = ownerKey,
    goalKey = goalKey,
    goalID = goalID,
    kind = kind,
    targetItemID = targetItemID,
    targetName = targetName,
    optionIndex = optionIndex,
    quantity = quantity,
    priority = priority,
    unitMaterials = unitMaterials,
    materials = scaleMaterials(unitMaterials, quantity),
    updatedAt = time and time() or 0,
  }

  local db = State.GetDB()
  db.characters[ownerKey] = {
    ownerKey = ownerKey,
    reservations = charDB.reservations,
    updatedAt = time and time() or 0,
  }

  State.NormalizePriorities()
  State.BumpReservationRevision()
  return true, charDB.reservations[goalKey]
end

-- Normalizes active reservation priorities to contiguous 1..K and sets charDB.nextPriority = K + 1.
function State.NormalizePriorities()
  local charDB = State.GetCharDB()
  local ordered = State.GetOrderedReservations()
  for idx, res in ipairs(ordered) do
    res.priority = idx
  end
  charDB.nextPriority = #ordered + 1
  return ordered
end

-- Moves a reserved goal's priority up (`delta = -1`) or down (`delta = +1`), normalizing 1..K
-- and bumping reservationRevision once.
function State.MoveReservationPriority(goalKeyOrID, delta)
  delta = tonumber(delta) or 0
  if delta == 0 then
    return false, "Priority delta must be non-zero (-1 for up, +1 for down)."
  end
  local ordered = State.NormalizePriorities()
  if #ordered <= 1 then
    return false, "Need at least 2 active reservations to reorder priority."
  end

  local asNum = tonumber(goalKeyOrID)
  local targetIdx = nil
  for idx, res in ipairs(ordered) do
    if res.goalKey == goalKeyOrID or res.goalID == goalKeyOrID or (asNum and res.targetItemID == asNum) then
      targetIdx = idx
      break
    end
  end
  if not targetIdx then
    return false, "Reservation not found."
  end

  local swapIdx = targetIdx + (delta < 0 and -1 or 1)
  if swapIdx < 1 or swapIdx > #ordered then
    return false, "Reservation is already at the boundary priority."
  end

  ordered[targetIdx], ordered[swapIdx] = ordered[swapIdx], ordered[targetIdx]
  local charDB = State.GetCharDB()
  for idx, res in ipairs(ordered) do
    res.priority = idx
  end
  charDB.nextPriority = #ordered + 1

  State.BumpReservationRevision()
  return true, swapIdx, ordered[swapIdx]
end

function State.SetGoalQuantity(kind, targetItemID, newQuantity)
  local existing = State.GetReservedOptionForTarget(kind, targetItemID)
  if not existing then
    return false, "Goal is not currently reserved."
  end
  local q = math.floor(tonumber(newQuantity) or 0)
  if q <= 0 then
    State.UnreserveGoal(existing.goalKey)
    return true, nil
  end
  return State.ReserveGoal(kind, targetItemID, existing.optionIndex, q)
end

-- Explicitly completes `completedCount` (default 1) turn-ins for a reserved crate/writ,
-- decrementing its remaining reserved quantity (preserving priority) or removing it when 0 remain.
function State.CompleteGoalTurnIn(kind, targetItemID, completedCount)
  local existing = State.GetReservedOptionForTarget(kind, targetItemID)
  if not existing then
    return false, "Goal is not reserved."
  end
  local dec = math.max(1, math.floor(tonumber(completedCount) or 1))
  local remaining = (tonumber(existing.quantity) or 1) - dec
  State.lastManualCompletionSeq = (State.lastManualCompletionSeq or 0) + 1
  if ns.Domain and ns.Domain.Diagnostics and ns.Domain.Diagnostics.RecordManualCompletion then
    pcall(ns.Domain.Diagnostics.RecordManualCompletion, kind, targetItemID, dec, remaining)
  end
  if remaining <= 0 then
    State.UnreserveGoal(existing.goalKey)
    return true, 0
  end
  local ok, updated = State.ReserveGoal(kind, targetItemID, existing.optionIndex, remaining)
  return ok, updated and updated.quantity or remaining
end

-- Explicitly reduces a reservation's planned quantity to observed character ownership.
-- Refuses when ownership is uncertain or when sealed crates / active writ quests make unopened count invalid.
function State.ReduceGoalToObservedOwnership(kind, targetItemID, observedOwnedCount, canReduce, blockReason)
  if canReduce == false then
    return false, tostring(blockReason or "Cannot reduce plan while ownership or active quest state is uncertain.")
  end
  local existing = State.GetReservedOptionForTarget(kind, targetItemID)
  if not existing then
    return false, "Goal is not reserved."
  end
  local obs = math.max(0, math.floor(tonumber(observedOwnedCount) or 0))
  if obs <= 0 then
    State.UnreserveGoal(existing.goalKey)
    return true, 0
  end
  if obs >= (tonumber(existing.quantity) or 1) then
    return false, "Planned quantity is already <= observed ownership."
  end
  local ok, updated = State.ReserveGoal(kind, targetItemID, existing.optionIndex, obs)
  return ok, updated and updated.quantity or obs
end

local function cloneReservationsTable(resMap)
  local copy = {}
  for k, v in pairs(resMap or {}) do
    if type(v) == "table" then
      local rCopy = {}
      for rk, rv in pairs(v) do
        if type(rv) == "table" then
          local listCopy = {}
          for i, item in ipairs(rv) do
            if type(item) == "table" then
              local mCopy = {}
              for mk, mv in pairs(item) do
                mCopy[mk] = mv
              end
              listCopy[i] = mCopy
            else
              listCopy[i] = item
            end
          end
          rCopy[rk] = listCopy
        else
          rCopy[rk] = rv
        end
      end
      copy[k] = rCopy
    end
  end
  return copy
end

-- Atomically applies a batch of suggested ready-turn-in reservations, saving an Undo snapshot first.
function State.ApplySuggestedReservations(suggestedList)
  if type(suggestedList) ~= "table" or #suggestedList == 0 then
    return false, "No suggested ready turn-ins to apply."
  end
  local charDB = State.GetCharDB()
  State.lastSuggestionSnapshot = cloneReservationsTable(charDB.reservations)

  local _, _, ownerKey = ns.Compat.GetCharacterKey()
  local appliedCount = 0
  for _, s in ipairs(suggestedList) do
    local kind = tostring(s.kind or "crate")
    local targetItemID = tonumber(s.targetItemID)
    local optIdx = tonumber(s.optionIndex) or 1
    local qty = math.max(1, math.floor(tonumber(s.quantity) or 1))
    local gKey = s.goalKey or State.BuildGoalKey(kind, targetItemID)
    if targetItemID and not charDB.reservations[gKey] then
      local uMats = s.unitMaterials or {}
      charDB.reservations[gKey] = {
        ownerKey = ownerKey,
        goalKey = gKey,
        goalID = State.BuildGoalID(kind, targetItemID, optIdx),
        kind = kind,
        targetItemID = targetItemID,
        targetName = tostring(s.targetName or gKey),
        optionIndex = optIdx,
        quantity = qty,
        priority = tonumber(s.priority) or (charDB.nextPriority or 1),
        unitMaterials = uMats,
        materials = scaleMaterials(uMats, qty),
        updatedAt = time and time() or 0,
      }
      appliedCount = appliedCount + 1
    end
  end

  if appliedCount == 0 then
    State.lastSuggestionSnapshot = nil
    return false, "All suggested targets were already reserved."
  end

  local db = State.GetDB()
  db.characters[ownerKey] = {
    ownerKey = ownerKey,
    reservations = charDB.reservations,
    updatedAt = time and time() or 0,
  }

  State.NormalizePriorities()
  State.BumpReservationRevision()
  return true, appliedCount
end

function State.HasSuggestionUndo()
  return type(State.lastSuggestionSnapshot) == "table"
end

function State.CanUndoLastSuggestion()
  return type(State.lastSuggestionSnapshot) == "table"
end

function State.UndoLastSuggestion()
  if type(State.lastSuggestionSnapshot) ~= "table" then
    return false, "No recent suggestion to undo."
  end
  local charDB = State.GetCharDB()
  charDB.reservations = cloneReservationsTable(State.lastSuggestionSnapshot)
  State.lastSuggestionSnapshot = nil

  local _, _, ownerKey = ns.Compat.GetCharacterKey()
  local db = State.GetDB()
  db.characters[ownerKey] = {
    ownerKey = ownerKey,
    reservations = charDB.reservations,
    updatedAt = time and time() or 0,
  }

  State.NormalizePriorities()
  State.BumpReservationRevision()
  return true
end

function State.ClearAllReservationsWithUndo()
  local charDB = State.GetCharDB()
  local ordered = State.GetOrderedReservations()
  if #ordered == 0 then
    return false, "No active reservations to clear."
  end
  State.lastSuggestionSnapshot = cloneReservationsTable(charDB.reservations)
  State.lastUndoReason = "clear_all"
  charDB.reservations = {}
  charDB.nextPriority = 1
  local _, _, ownerKey = ns.Compat.GetCharacterKey()
  local db = State.GetDB()
  if db.characters and db.characters[ownerKey] then
    db.characters[ownerKey].reservations = charDB.reservations
  end
  State.BumpReservationRevision()
  return true, #ordered
end

function State.UnreserveGoal(goalKeyOrID)
  local charDB = State.GetCharDB()
  if goalKeyOrID == "all" then
    charDB.reservations = {}
    charDB.nextPriority = 1
    local _, _, ownerKey = ns.Compat.GetCharacterKey()
    local db = State.GetDB()
    if db.characters and db.characters[ownerKey] then
      db.characters[ownerKey].reservations = charDB.reservations
    end
    State.BumpReservationRevision()
    return true
  end

  if charDB.reservations[goalKeyOrID] then
    charDB.reservations[goalKeyOrID] = nil
    State.NormalizePriorities()
    State.BumpReservationRevision()
    return true
  end

  -- Also match by goalID or bare itemID
  local asNum = tonumber(goalKeyOrID)
  for k, res in pairs(charDB.reservations) do
    if res.goalID == goalKeyOrID or res.goalKey == goalKeyOrID or (asNum and res.targetItemID == asNum) then
      charDB.reservations[k] = nil
      State.NormalizePriorities()
      State.BumpReservationRevision()
      return true
    end
  end
  return false
end

function State.ToggleGoalReservation(kind, targetItemID, optionIndex, defaultQuantity)
  local isReserved, goalKey = State.IsOptionReserved(kind, targetItemID, optionIndex)
  if isReserved then
    State.UnreserveGoal(goalKey)
    return false, goalKey
  else
    local ok, resOrErr = State.ReserveGoal(kind, targetItemID, optionIndex, defaultQuantity)
    return ok, resOrErr
  end
end

function State.RegisterListener(fn)
  if type(fn) == "function" then
    table.insert(State.listeners, fn)
  end
end

function State.NotifyChanged()
  for _, fn in ipairs(State.listeners) do
    pcall(fn)
  end
end

-- ============================================================================
-- Mount Tracker & Persisted Single-Owner Navigation State (Per-Character)
-- ============================================================================

State.sessionStartMoneyCopper = nil
State.sessionStartTimestamp = nil

-- Forever discounted riding model: 90g (900,000c) includes riding training AND first basic racial mount.
-- Kept as an unconfirmed_default until observed/confirmed by the user via `/fh mount quote <gold>` or `/fh mount honored`.
local DEFAULT_MOUNT_QUOTE_COPPER = 900000

function State.EnsureNavigationOwnerInitialized()
  local charDB = _G.ForeverHubCharDB
  if type(charDB) ~= "table" then
    return nil
  end
  local raw = type(charDB.navigationOwner) == "table" and charDB.navigationOwner or {}
  local ctx = raw.ownerContext
  local retiredRivergladesOwner = (ctx == "riverglades")
  if ctx ~= "gold_farm" and not retiredRivergladesOwner then
    ctx = nil
  end
  local handle = nil
  if type(raw.handle) == "table" and raw.provider == "native_waypoint" then
    local uid = tonumber(raw.handle.uiMapID)
    local hx = tonumber(raw.handle.x01)
    local hy = tonumber(raw.handle.y01)
    if uid and hx and hy and hx > 0 and hx < 1 and hy > 0 and hy < 1 then
      handle = {
        provider = "native_waypoint",
        uiMapID = uid,
        x01 = hx,
        y01 = hy,
      }
    end
  end
  if retiredRivergladesOwner then
    ctx = handle and "gold_farm" or nil
  end
  charDB.navigationOwner = {
    ownerContext = handle and ctx or nil,
    provider = handle and "native_waypoint" or "none",
    handle = handle,
    pendingRelease = ((raw.pendingRelease == true) or retiredRivergladesOwner) and (handle ~= nil),
  }
  return charDB.navigationOwner
end

function State.GetPersistedNavigationOwner()
  local charDB = State.GetCharDB()
  if type(charDB.navigationOwner) ~= "table" then
    State.EnsureNavigationOwnerInitialized()
  end
  return charDB.navigationOwner
end

function State.SavePersistedNavigationOwner(owner)
  local charDB = State.GetCharDB()
  if type(owner) ~= "table" then
    charDB.navigationOwner = {
      ownerContext = nil,
      provider = "none",
      handle = nil,
      pendingRelease = false,
      pendingDestination = nil,
    }
    return
  end
  local persistedHandle = nil
  if owner.provider == "native_waypoint" and type(owner.handle) == "table" then
    persistedHandle = {
      provider = "native_waypoint",
      uiMapID = tonumber(owner.handle.uiMapID),
      x01 = tonumber(owner.handle.x01),
      y01 = tonumber(owner.handle.y01),
    }
  end
  local persistedPendingDest = nil
  if type(owner.pendingDestination) == "table" and type(owner.pendingDestination.destination) == "table" then
    local pd = owner.pendingDestination
    local d = pd.destination
    persistedPendingDest = {
      context = pd.context,
      destination = {
        uiMapID = tonumber(d.uiMapID),
        x01 = tonumber(d.x01),
        y01 = tonumber(d.y01),
        zoneName = d.zoneName,
        coordinateSpace = d.coordinateSpace or "uiMap01",
      },
      title = pd.title,
    }
  end
  charDB.navigationOwner = {
    ownerContext = persistedHandle and owner.ownerContext or nil,
    provider = persistedHandle and "native_waypoint" or "none",
    handle = persistedHandle,
    pendingRelease = (owner.pendingRelease == true) and (persistedHandle ~= nil),
    pendingDestination = persistedPendingDest,
  }
end

local VALID_ARROW_POINTS = {
  CENTER = true,
  TOP = true,
  BOTTOM = true,
  LEFT = true,
  RIGHT = true,
  TOPLEFT = true,
  TOPRIGHT = true,
  BOTTOMLEFT = true,
  BOTTOMRIGHT = true,
}

local VALID_ARROW_RENDERERS = {
  auto = true,
  foreverhub = true,
  tomtom = true,
  off = true,
}

function State.MigrateArrowSettings(raw)
  local s = type(raw) == "table" and raw or {}
  local scale = tonumber(s.scale) or 1.0
  if scale < 0.6 then
    scale = 0.6
  elseif scale > 2.0 then
    scale = 2.0
  end
  local style = s.style
  if style ~= "custom" and style ~= "classic" then
    style = "auto"
  end

  local renderer = s.renderer
  if not VALID_ARROW_RENDERERS[renderer] then
    if s.enabled == false then
      renderer = "off"
    elseif s.showWhenTomTomActive == true then
      renderer = "foreverhub"
    else
      renderer = "auto"
    end
  end

  local pt = VALID_ARROW_POINTS[s.point] and s.point or "CENTER"
  local relPt = VALID_ARROW_POINTS[s.relativePoint] and s.relativePoint or "CENTER"
  local ox = tonumber(s.offsetX)
  local oy = tonumber(s.offsetY)
  if ox == nil or ox ~= ox then
    ox = 0
  end
  if oy == nil or oy ~= oy then
    oy = 135
  end

  local normX = tonumber(s.normX)
  local normY = tonumber(s.normY)
  if normX ~= nil and (normX ~= normX or normX < -0.5 or normX > 0.5) then
    normX = nil
  end
  if normY ~= nil and (normY ~= normY or normY < -0.5 or normY > 0.5) then
    normY = nil
  end

  local prevSchema = tonumber(s.schemaVersion) or 0
  local rawHudWidth = tonumber(s.hudWidth)
  local hudWidth = rawHudWidth or 240
  if prevSchema < 3 and rawHudWidth == 340 then
    hudWidth = 240
  end
  if hudWidth ~= hudWidth or hudWidth < 200 then
    hudWidth = 200
  elseif hudWidth > 440 then
    hudWidth = 440
  end
  local hudPt = VALID_ARROW_POINTS[s.hudPoint] and s.hudPoint or "TOP"
  local hudRelPt = VALID_ARROW_POINTS[s.hudRelativePoint] and s.hudRelativePoint or "TOP"
  local hudOx = tonumber(s.hudOffsetX)
  local hudOy = tonumber(s.hudOffsetY)
  if hudOx == nil or hudOx ~= hudOx then
    hudOx = 0
  end
  if hudOy == nil or hudOy ~= hudOy then
    hudOy = -112
  end

  return {
    schemaVersion = 3,
    renderer = renderer,
    enabled = (renderer ~= "off"),
    locked = (s.locked == true),
    scale = scale,
    style = style,
    dockedInHud = (s.dockedInHud ~= false),
    hudWidth = math.floor(hudWidth + 0.5),
    hudLocked = (s.hudLocked == true),
    hudHidden = (s.hudHidden == true),
    hudPoint = hudPt,
    hudRelativePoint = hudRelPt,
    hudOffsetX = hudOx,
    hudOffsetY = hudOy,
    showWhenTomTomActive = (renderer == "foreverhub"),
    point = pt,
    relativePoint = relPt,
    offsetX = ox,
    offsetY = oy,
    normX = normX,
    normY = normY,
  }
end

function State.EnsureArrowSettingsInitialized()
  local charDB = _G.ForeverHubCharDB
  if type(charDB) ~= "table" then
    return nil
  end
  charDB.arrowSettings = State.MigrateArrowSettings(charDB.arrowSettings)
  return charDB.arrowSettings
end

function State.GetArrowSettings()
  local charDB = State.GetCharDB()
  if type(charDB.arrowSettings) ~= "table" or charDB.arrowSettings.schemaVersion ~= 3 then
    charDB.arrowSettings = State.MigrateArrowSettings(charDB.arrowSettings)
  end
  return charDB.arrowSettings
end

function State.ResetArrowSettingsPosition()
  local settings = State.GetArrowSettings()
  settings.point = "CENTER"
  settings.relativePoint = "CENTER"
  settings.offsetX = 0
  settings.offsetY = 135
  settings.normX = nil
  settings.normY = nil
  settings.scale = 1.0
  return settings
end

local VALID_PILL_CORNERS = {
  BOTTOMLEFT = true,
  BOTTOMRIGHT = true,
  TOPLEFT = true,
  TOPRIGHT = true,
}

function State.MigrateWorldMapPinSettings(rawSettings)
  local s = type(rawSettings) == "table" and rawSettings or {}
  local corner = VALID_PILL_CORNERS[s.pillCorner] and s.pillCorner or "BOTTOMLEFT"
  return {
    schemaVersion = 1,
    enabled = (s.enabled ~= false),
    showObjectives = (s.showObjectives ~= false),
    showTurnIns = (s.showTurnIns ~= false),
    showAvailable = (s.showAvailable ~= false),
    pillCorner = corner,
    filtersCollapsed = (s.filtersCollapsed == true),
  }
end

function State.EnsureWorldMapPinSettingsInitialized()
  local charDB = _G.ForeverHubCharDB
  if type(charDB) ~= "table" then
    return nil
  end
  charDB.worldMapPinSettings = State.MigrateWorldMapPinSettings(charDB.worldMapPinSettings)
  return charDB.worldMapPinSettings
end

function State.GetWorldMapPinSettings()
  local charDB = State.GetCharDB()
  if type(charDB.worldMapPinSettings) ~= "table" or charDB.worldMapPinSettings.schemaVersion ~= 1 then
    charDB.worldMapPinSettings = State.MigrateWorldMapPinSettings(charDB.worldMapPinSettings)
  end
  return charDB.worldMapPinSettings
end

function State.ResetWorldMapPinSettings()
  local charDB = State.GetCharDB()
  charDB.worldMapPinSettings = State.MigrateWorldMapPinSettings(nil)
  return charDB.worldMapPinSettings
end

local VALID_WORKSPACE_TABS = {
  gold = true,
  crates = true,
  advisor = true,
  research = true,
}

function State.MigrateWorkspaceUIState(rawUI, settingsRef)
  local u = type(rawUI) == "table" and rawUI or {}
  local activeTab = VALID_WORKSPACE_TABS[u.activeTab] and u.activeTab or "gold"

  local width = tonumber(u.width) or 960
  if width ~= width or width < 760 then
    width = 760
  elseif width > 1600 then
    width = 1600
  end

  local height = tonumber(u.height) or 640
  if height ~= height or height < 520 then
    height = 520
  elseif height > 1200 then
    height = 1200
  end

  local textScale = tonumber(u.textScale) or 1.0
  if textScale ~= textScale or textScale < 0.85 then
    textScale = 0.85
  elseif textScale > 1.35 then
    textScale = 1.35
  end

  local pt = VALID_ARROW_POINTS[u.point] and u.point or "CENTER"
  local relPt = VALID_ARROW_POINTS[u.relativePoint] and u.relativePoint or "CENTER"
  local ox = tonumber(u.offsetX)
  local oy = tonumber(u.offsetY)
  if ox == nil or ox ~= ox then
    ox = 0
  end
  if oy == nil or oy ~= oy then
    oy = 0
  end

  local compactOverride = nil
  if type(u.compactOverride) == "boolean" then
    compactOverride = u.compactOverride
  end

  local rawCrates = type(u.cratesView) == "table" and u.cratesView or {}
  local defaultOnlyOwned = true
  if type(settingsRef) == "table" and type(settingsRef.showOnlyOwnedCrates) == "boolean" then
    defaultOnlyOwned = settingsRef.showOnlyOwnedCrates
  end
  local scope = rawCrates.scope
  if scope ~= "owned_planned" and scope ~= "all" then
    scope = defaultOnlyOwned and "owned_planned" or "all"
  end

  local expandedByKey = {}
  if type(rawCrates.expandedByKey) == "table" then
    for k, v in pairs(rawCrates.expandedByKey) do
      if type(k) == "string" and k ~= "" and type(v) == "boolean" then
        expandedByKey[k] = v
      end
    end
  end

  local rawGold = type(u.goldView) == "table" and u.goldView or {}
  local expandedByFarmID = {}
  if type(rawGold.expandedByFarmID) == "table" then
    for k, v in pairs(rawGold.expandedByFarmID) do
      if (type(k) == "string" or type(k) == "number") and type(v) == "boolean" then
        expandedByFarmID[tostring(k)] = v
      end
    end
  end
  local selectedTrack = "auto"
  if rawGold.selectedTrack == "arcane_lvl47_st" or rawGold.selectedTrack == "lvl40_mount" or rawGold.selectedTrack == "auto" then
    selectedTrack = rawGold.selectedTrack
  end
  local validSubFilters = {
    my_level = true,
    all_shortlist = true,
    ["46_50"] = true,
    ["48_51"] = true,
    ["51_54"] = true,
    ["54_57"] = true,
    ["57_60"] = true,
    experimental = true,
  }
  local subFilter = validSubFilters[rawGold.subFilter] and rawGold.subFilter or "my_level"
  local focusedFarmID = (type(rawGold.focusedFarmID) == "string" and rawGold.focusedFarmID ~= "") and rawGold.focusedFarmID or nil

  return {
    schemaVersion = 3,
    activeTab = activeTab,
    width = math.floor(width + 0.5),
    height = math.floor(height + 0.5),
    textScale = textScale,
    compactOverride = compactOverride,
    point = pt,
    relativePoint = relPt,
    offsetX = ox,
    offsetY = oy,
    cratesView = {
      searchQuery = type(rawCrates.searchQuery) == "string" and rawCrates.searchQuery or "",
      scope = scope,
      readyOnly = (rawCrates.readyOnly == true),
      expandedByKey = expandedByKey,
      scrollOffset = math.max(0, tonumber(rawCrates.scrollOffset) or 0),
    },
    goldView = {
      subView = (rawGold.subView == "dungeons") and "dungeons" or "routes",
      selectedTrack = selectedTrack,
      subFilter = subFilter,
      focusedFarmID = focusedFarmID,
      expandedByFarmID = expandedByFarmID,
      scrollOffset = math.max(0, tonumber(rawGold.scrollOffset) or 0),
    },
    advisorView = {
      scrollOffset = math.max(0, tonumber(type(u.advisorView) == "table" and u.advisorView.scrollOffset) or 0),
      crowdedUntilByFarmID = (function()
        local out = {}
        if type(u.advisorView) == "table" and type(u.advisorView.crowdedUntilByFarmID) == "table" then
          for k, v in pairs(u.advisorView.crowdedUntilByFarmID) do
            if type(k) == "string" and k ~= "" and type(v) == "number" and v > 0 then
              out[k] = math.floor(v)
            end
          end
        end
        return out
      end)(),
    },
  }
end

function State.EnsureWorkspaceUIStateInitialized(_isAddonLoad)
  local db = _G.ForeverHubDB
  if type(db) ~= "table" then
    return nil
  end
  db.uiWorkspace = State.MigrateWorkspaceUIState(db.uiWorkspace, db.settings)
  return db.uiWorkspace
end

function State.GetWorkspaceUIState()
  local db = State.GetDB()
  if type(db.uiWorkspace) ~= "table" or db.uiWorkspace.schemaVersion ~= 3 then
    db.uiWorkspace = State.MigrateWorkspaceUIState(db.uiWorkspace, db.settings)
  end
  return db.uiWorkspace
end

function State.EnsureMinimapSettingsInitialized()
  local db = _G.ForeverHubDB
  if type(db) ~= "table" then
    return nil
  end
  db.settings = type(db.settings) == "table" and db.settings or {}
  local raw = type(db.settings.minimapButton) == "table" and db.settings.minimapButton or {}
  local deg = tonumber(raw.angleDeg) or 220
  deg = deg % 360
  if deg < 0 then
    deg = deg + 360
  end
  db.settings.minimapButton = {
    hidden = (raw.hidden == true),
    angleDeg = math.floor(deg * 10 + 0.5) / 10,
  }
  if type(db.onboardingSeen) ~= "boolean" then
    db.onboardingSeen = false
  end
  return db.settings.minimapButton
end

function State.GetMinimapSettings()
  local db = State.GetDB()
  if type(db.settings) ~= "table" or type(db.settings.minimapButton) ~= "table" then
    State.EnsureMinimapSettingsInitialized()
  end
  return db.settings.minimapButton
end

function State.SetMinimapHidden(hidden)
  local mm = State.GetMinimapSettings()
  mm.hidden = (hidden == true)
  return mm
end

function State.SetMinimapAngle(angleDeg)
  local mm = State.GetMinimapSettings()
  local deg = (tonumber(angleDeg) or 220) % 360
  if deg < 0 then
    deg = deg + 360
  end
  mm.angleDeg = math.floor(deg * 10 + 0.5) / 10
  return mm
end

function State.HasSeenOnboarding()
  local db = State.GetDB()
  return db.onboardingSeen == true
end

function State.MarkOnboardingSeen(seen)
  local db = State.GetDB()
  db.onboardingSeen = (seen ~= false)
end

function State.GetDiscoveredQuestId(normTitle)
  if type(normTitle) ~= "string" or normTitle == "" then
    return nil
  end
  local db = _G.ForeverHubDB
  if type(db) == "table" and type(db.discoveredQuestIds) == "table" then
    local qid = tonumber(db.discoveredQuestIds[normTitle])
    if qid and qid > 0 then
      return qid
    end
  end
  return nil
end

function State.GetDiscoveredQuestTitle(questID)
  local qid = tonumber(questID)
  if not qid or qid <= 0 then
    return nil
  end
  local db = _G.ForeverHubDB
  if type(db) ~= "table" then
    return nil
  end
  if type(db.discoveredQuestTitlesById) == "table" then
    local t = db.discoveredQuestTitlesById[qid]
    if type(t) == "string" and t ~= "" then
      if type(db.discoveredQuestIds) ~= "table" or tonumber(db.discoveredQuestIds[t]) == qid then
        return t
      end
    end
  end
  if type(db.discoveredQuestIds) == "table" then
    for k, v in pairs(db.discoveredQuestIds) do
      if type(k) == "string" and k ~= "" and tonumber(v) == qid then
        db.discoveredQuestTitlesById = type(db.discoveredQuestTitlesById) == "table" and db.discoveredQuestTitlesById or {}
        db.discoveredQuestTitlesById[qid] = k
        return k
      end
    end
  end
  return nil
end

function State.RecordDiscoveredQuestId(normTitle, questID)
  local qid = tonumber(questID)
  if type(normTitle) ~= "string" or normTitle == "" or not qid or qid <= 0 then
    return false
  end
  if type(_G.ForeverHubDB) ~= "table" then
    _G.ForeverHubDB = {}
  end
  _G.ForeverHubDB.discoveredQuestIds = type(_G.ForeverHubDB.discoveredQuestIds) == "table" and _G.ForeverHubDB.discoveredQuestIds or {}
  _G.ForeverHubDB.discoveredQuestTitlesById = type(_G.ForeverHubDB.discoveredQuestTitlesById) == "table"
      and _G.ForeverHubDB.discoveredQuestTitlesById
    or {}
  _G.ForeverHubDB.discoveredQuestIds[normTitle] = qid
  _G.ForeverHubDB.discoveredQuestTitlesById[qid] = normTitle
  return true
end

function State.RecordCompletedQuestId(_questID)
  return false
end

function State.RecordObservedQuestGiver(questID, giverInfo, progressOverride)
  local qid = tonumber(questID)
  if not qid or qid <= 0 or type(giverInfo) ~= "table" or type(progressOverride) ~= "table" then
    return false
  end
  progressOverride.observedQuestGivers = type(progressOverride.observedQuestGivers) == "table" and progressOverride.observedQuestGivers or {}
  progressOverride.observedQuestGivers[qid] = {
    npcID = tonumber(giverInfo.npcID),
    npcName = type(giverInfo.npcName) == "string" and giverInfo.npcName ~= "" and giverInfo.npcName or nil,
    uiMapID = tonumber(giverInfo.uiMapID),
    x01 = tonumber(giverInfo.x01),
    y01 = tonumber(giverInfo.y01),
  }
  return true
end

function State.GetObservedQuestGiver(questID, progressOverride)
  local qid = tonumber(questID)
  if not qid or qid <= 0 or type(progressOverride) ~= "table" then
    return nil
  end
  if type(progressOverride.observedQuestGivers) == "table" and type(progressOverride.observedQuestGivers[qid]) == "table" then
    return progressOverride.observedQuestGivers[qid]
  end
  return nil
end

function State.RecordObservedQuestObjectiveText(questID, objText, progressOverride)
  local qid = tonumber(questID)
  if not qid or qid <= 0 or type(objText) ~= "string" or objText == "" or type(progressOverride) ~= "table" then
    return false
  end
  progressOverride.observedQuestObjectivesText = type(progressOverride.observedQuestObjectivesText) == "table"
      and progressOverride.observedQuestObjectivesText
    or {}
  progressOverride.observedQuestObjectivesText[qid] = objText
  return true
end

function State.GetObservedQuestObjectiveText(questID, progressOverride)
  local qid = tonumber(questID)
  if not qid or qid <= 0 or type(progressOverride) ~= "table" then
    return nil
  end
  if type(progressOverride.observedQuestObjectivesText) == "table" and type(progressOverride.observedQuestObjectivesText[qid]) == "string" then
    return progressOverride.observedQuestObjectivesText[qid]
  end
  return nil
end

function State.IsObservedCompletedQuestId(_questID)
  return false
end

function State.IsObservedCompletedQuestTitle(_normTitle)
  return false
end

function State.RecordCompletedQuestTitle(_normTitle)
  return false
end

function State.ClearUnresolvedQuestConfirmation(_questKeyOrTitle, _targetProg)
  return false
end

function State.GetBankItemCount(itemID)
  local id = tonumber(itemID)
  if not id or id <= 0 then
    return 0
  end
  if State.HasSessionBankObservation() and type(State.sessionBankSnapshot.counts) == "table" then
    return tonumber(State.sessionBankSnapshot.counts[id]) or 0
  end
  local charDB = _G.ForeverHubCharDB
  if type(charDB) == "table" and type(charDB.bankSnapshot) == "table" and charDB.bankSnapshot.available == true and type(charDB.bankSnapshot.counts) == "table" then
    return tonumber(charDB.bankSnapshot.counts[id]) or 0
  end
  if ns.Providers and ns.Providers.Inventory and type(ns.Providers.Inventory.GetItemCounts) == "function" then
    local counts = ns.Providers.Inventory.GetItemCounts(id)
    if type(counts) == "table" and tonumber(counts.bankCount) and tonumber(counts.bankCount) > 0 then
      return tonumber(counts.bankCount)
    end
  end
  if C_Item and type(C_Item.GetItemCount) == "function" then
    local okAll, withBank = pcall(C_Item.GetItemCount, id, true)
    local okBag, bagsOnly = pcall(C_Item.GetItemCount, id, false)
    if okAll and okBag and type(withBank) == "number" and type(bagsOnly) == "number" and withBank > bagsOnly then
      return withBank - bagsOnly
    end
  elseif type(GetItemCount) == "function" then
    local okAll, withBank = pcall(GetItemCount, id, true)
    local okBag, bagsOnly = pcall(GetItemCount, id, false)
    if okAll and okBag and type(withBank) == "number" and type(bagsOnly) == "number" and withBank > bagsOnly then
      return withBank - bagsOnly
    end
  end
  return 0
end

function State.MigrateMountTracker(rawMt)
  local mt = type(rawMt) == "table" and rawMt or {}
  local quoteSource = type(mt.quoteSource) == "string" and mt.quoteSource or "default_90g_unconfirmed"
  local quote = tonumber(mt.trainerQuoteCopper)
  -- Strip removed unverified 95g Friendly preset if present from an older session
  if quoteSource == "user_friendly_95g" then
    quote = DEFAULT_MOUNT_QUOTE_COPPER
    quoteSource = "default_90g_unconfirmed"
  end
  if not quote or quote <= 0 then
    quote = DEFAULT_MOUNT_QUOTE_COPPER
  end

  local quoteStatus = mt.quoteStatus
  if quoteStatus ~= "user_confirmed" and quoteStatus ~= "unconfirmed_default" then
    if quoteSource == "user_custom_quote" or quoteSource == "user_confirmed_honored_90g" or quoteSource == "base_100g" then
      quoteStatus = "user_confirmed"
    else
      quoteStatus = "unconfirmed_default"
    end
  end

  local reserve = tonumber(mt.cashReserveCopper)
  if not reserve or reserve < 0 then
    reserve = 0
  end
  local reserveExplicitlySet = (mt.reserveExplicitlySet == true) or (reserve > 0)

  local cr = (ns.Compat and ns.Compat.GetPlayerClassAndRace and ns.Compat.GetPlayerClassAndRace()) or {}
  local playerRaceToken = type(mt.playerRaceToken) == "string" and mt.playerRaceToken or cr.raceToken or "UNKNOWN"
  local trainerFaction = type(mt.trainerFaction) == "string" and mt.trainerFaction or "HomeRacialFaction"

  return {
    mountStateVersion = 2,
    standingLabel = type(mt.standingLabel) == "string" and mt.standingLabel ~= "Friendly" and mt.standingLabel or "Honored (Default)",
    trainerQuoteCopper = math.floor(quote),
    quoteSource = quoteSource,
    quoteStatus = quoteStatus,
    cashReserveCopper = math.floor(reserve),
    reserveExplicitlySet = reserveExplicitlySet,
    playerRaceToken = playerRaceToken,
    trainerFaction = trainerFaction,
  }
end

function State.EnsureMountTrackerInitialized(resetSessionBaseline)
  local charDB = _G.ForeverHubCharDB
  if type(charDB) ~= "table" then
    return nil
  end
  charDB.mountTracker = State.MigrateMountTracker(charDB.mountTracker)
  if resetSessionBaseline then
    State.sessionStartMoneyCopper = nil
    State.sessionStartTimestamp = nil
  end
  return charDB.mountTracker
end

function State.GetMountTracker()
  local charDB = State.GetCharDB()
  if type(charDB.mountTracker) ~= "table" or charDB.mountTracker.mountStateVersion ~= 2 then
    State.EnsureMountTrackerInitialized(false)
  end
  return charDB.mountTracker
end

function State.CaptureSessionMoneyBaselineIfUnset()
  if State.sessionStartMoneyCopper == nil and ns.Compat and ns.Compat.GetPlayerMoneyCopper then
    local moneyRes = ns.Compat.GetPlayerMoneyCopper()
    if moneyRes.status == "ok" and type(moneyRes.copper) == "number" then
      State.sessionStartMoneyCopper = moneyRes.copper
      State.sessionStartTimestamp = (type(time) == "function" and time()) or 0
    end
  end
end

-- ============================================================================
-- v0.5.0 Raw Gold Farm State & Net Purse Change / Active Hr Telemetry
-- Migrates strictly by stable string farmIDs and stepIDs — never array indexes!
-- Separate persistence policies for route progress vs cash-flow telemetry (Astra P1-9).
-- ============================================================================

State.goldFarmSession = {
  sessionID = nil,
  active = false,
  pausedByReload = false,
  pausedForWindow = nil,
  wasActiveBeforeWindow = false,
  activeWindows = {},
  farmID = nil,
  phase = "camp", -- "camp" | "travel_service" | "rxp_untracked"
  segmentStartedAt = nil,
  segmentStartCopper = nil,
  campSeconds = 0,
  travelAndServiceSeconds = 0,
  rxpUntrackedSeconds = 0,
  accumulatedSeconds = 0,
  accumulatedCopper = 0,
  accumulatedXP = 0,
  killsObserved = 0,
  lastPlayerXP = nil,
  lastPlayerMaxXP = nil,
  lastPlayerLevel = nil,
  contaminated = false,
  contaminationReason = nil,
  cleanIntervalConfirmed = true,
}

local function normalizeTelemetryPhase(phaseOrKind)
  if phaseOrKind == "rxp_untracked" or phaseOrKind == "rxp" then
    return "rxp_untracked"
  end
  if phaseOrKind == "travel_service"
    or phaseOrKind == "travel"
    or phaseOrKind == "boat_crossing"
    or phaseOrKind == "vendor"
  then
    return "travel_service"
  end
  if phaseOrKind == "camp" or phaseOrKind == "grind" then
    return "camp"
  end
  return nil
end

local sessionSeq = 0
local function newTelemetrySessionID(nowSec)
  sessionSeq = sessionSeq + 1
  return string.format("gf-%d-%d", tonumber(nowSec) or 0, sessionSeq)
end

function State.GetCompiledGoldFarms()
  return ns.GoldFarmsData or nil
end

function State.MigrateGoldFarmProgress(rawProgress, catalog)
  local catalogID = (catalog and catalog.meta and catalog.meta.catalogID)
    or "foreverhub_alliance_lvl40_mage_raw_gold_v1"
  local revision = tonumber(catalog and catalog.meta and catalog.meta.revision) or 2

  local validFarms = {}
  local validStepsByFarm = {}
  local function registerRouteList(list)
    if type(list) ~= "table" then
      return
    end
    for _, farm in ipairs(list) do
      if type(farm) == "table" and type(farm.farmID) == "string" then
        validFarms[farm.farmID] = farm
        local stepSet = {}
        for _, st in ipairs(farm.travelSteps or {}) do
          if type(st) == "table" and type(st.stepID) == "string" then
            stepSet[st.stepID] = true
          end
        end
        validStepsByFarm[farm.farmID] = stepSet
      end
    end
  end
  if catalog then
    registerRouteList(catalog.farms)
    registerRouteList(catalog.arcaneGrindFarms)
    registerRouteList(catalog.expandedRoutes)
  end

  local p = type(rawProgress) == "table" and rawProgress or {}
  local selFarmID = type(p.selectedFarmID) == "string" and p.selectedFarmID or nil
  if next(validFarms) ~= nil and selFarmID and not validFarms[selFarmID] then
    selFarmID = nil
  end

  local curStepID = type(p.currentStepID) == "string" and p.currentStepID or nil
  if selFarmID and validStepsByFarm[selFarmID] and curStepID and not validStepsByFarm[selFarmID][curStepID] then
    curStepID = nil
  elseif not selFarmID then
    curStepID = nil
  end

  local pinnedStepID = type(p.manualPinnedStepID) == "string" and p.manualPinnedStepID or nil
  if selFarmID and validStepsByFarm[selFarmID] and pinnedStepID and not validStepsByFarm[selFarmID][pinnedStepID] then
    pinnedStepID = nil
  elseif not selFarmID then
    pinnedStepID = nil
  end

  local completedSteps = {}
  local archivedCompletedSteps = type(p.archivedCompletedSteps) == "table" and p.archivedCompletedSteps or {}
  if type(p.completedTravelSteps) == "table" then
    for sid, entry in pairs(p.completedTravelSteps) do
      if type(sid) == "string" and entry then
        -- Never persist `already_in_farm_zone` as permanent completion across trips!
        local entryReason = type(entry) == "table" and entry.reason or nil
        if entryReason ~= "already_in_farm_zone" then
          if not selFarmID or not validStepsByFarm[selFarmID] or validStepsByFarm[selFarmID][sid] then
            completedSteps[sid] = type(entry) == "table" and entry or { completedAt = 0, reason = "migrated" }
          else
            archivedCompletedSteps[sid] = entry
          end
        end
      end
    end
  end

  local tripStartMapID = tonumber(p.tripStartPlayerUiMapID)
  if not tripStartMapID or tripStartMapID ~= tripStartMapID or tripStartMapID <= 0 or not selFarmID then
    tripStartMapID = nil
  else
    tripStartMapID = math.floor(tripStartMapID)
  end

  local mode = p.mode
  if mode ~= "standalone" and mode ~= "rxp" then
    mode = "paused"
  end
  if not selFarmID then
    mode = "paused"
  end

  local spawnRadarMode = "auto"
  if p.spawnRadarMode == "on" or p.spawnRadarMode == "off" or p.spawnRadarMode == "auto" then
    spawnRadarMode = p.spawnRadarMode
  end

  local spawnPinMode = "active"
  if p.spawnPinMode == "active" or p.spawnPinMode == "all" or p.spawnPinMode == "off" then
    spawnPinMode = p.spawnPinMode
  end

  return {
    goldStateVersion = 2,
    catalogID = catalogID,
    revision = revision,
    mode = mode,
    selectedFarmID = selFarmID,
    currentStepID = curStepID,
    manualPinnedStepID = pinnedStepID,
    tripStartPlayerUiMapID = tripStartMapID,
    completedTravelSteps = completedSteps,
    archivedCompletedSteps = archivedCompletedSteps,
    ownedWaypoint = type(p.ownedWaypoint) == "table" and p.ownedWaypoint or nil,
    spawnRadarMode = spawnRadarMode,
    spawnPinMode = spawnPinMode,
    includeUnwalkedCaveNodes = (p.includeUnwalkedCaveNodes == true),
  }
end

local resolveNowAndMoney
local accrueOpenSegment
local captureXPBaseline

local function resolveSessionMonoAndWall(explicitMono, explicitWall)
  local wallNow = tonumber(explicitWall)
  if not wallNow then
    wallNow = (type(time) == "function" and time()) or 0
  end
  local monoNow = tonumber(explicitMono)
  if not monoNow then
    if type(State.overrideMonotonicTime) == "number" then
      monoNow = State.overrideMonotonicTime
    elseif ns.Compat and type(ns.Compat.GetMonotonicSeconds) == "function" then
      monoNow = tonumber(ns.Compat.GetMonotonicSeconds())
    elseif type(_G.GetTime) == "function" then
      local ok, v = pcall(_G.GetTime)
      if ok and type(v) == "number" then
        monoNow = v
      end
    end
  end
  if not monoNow then
    monoNow = wallNow
  end
  return monoNow, wallNow
end

local function isWithinReconcileWindow(entry, monoNow, wallNow, maxSec)
  if type(entry) ~= "table" then
    return false
  end
  local dm = math.abs(monoNow - (tonumber(entry.atMono) or monoNow))
  local dw = math.abs(wallNow - (tonumber(entry.atWall) or wallNow))
  return dm <= maxSec and dw <= math.max(maxSec, 3)
end

local function refreshXPContaminationFlags(sess)
  if not sess then
    return
  end
  local unattrib = math.max(0, math.floor(tonumber(sess.unattributedXP) or 0))
  local unresolved = (sess.xpRolloverUnresolved == true) or (sess.terminalSnapshotUnresolved == true)
  local gap = (sess.xpBaselineGap == true)
  sess.xpContaminated = unresolved or (unattrib > 0) or gap
  if sess.xpContaminated then
    if sess.terminalSnapshotUnresolved == true then
      sess.xpContaminationReason = sess.xpContaminationReason or "terminal_xp_probe_unavailable"
    elseif unresolved then
      sess.xpContaminationReason = sess.xpContaminationReason or "rollover_unresolved"
    elseif gap then
      sess.xpContaminationReason = sess.xpContaminationReason or "xp_baseline_gap"
    else
      sess.xpContaminationReason = "unattributed_xp"
    end
  else
    sess.xpContaminationReason = nil
  end
end

local function computeSessionLiveElapsedSeconds(sess, explicitNow)
  if not sess then
    return 0
  end
  local nowSec = tonumber(explicitNow) or ((type(time) == "function" and time()) or 0)
  local campSec = tonumber(sess.campSeconds) or 0
  local travelSec = tonumber(sess.travelAndServiceSeconds) or 0
  local rxpSec = tonumber(sess.rxpUntrackedSeconds) or 0
  if sess.active and type(sess.segmentStartedAt) == "number" then
    local dt = math.max(0, math.floor(nowSec - sess.segmentStartedAt))
    if sess.phase == "rxp_untracked" then
      rxpSec = rxpSec + dt
    elseif sess.phase == "travel_service" then
      travelSec = travelSec + dt
    else
      campSec = campSec + dt
    end
  end
  return math.max(0, campSec + travelSec + rxpSec)
end

local function freezeSessionAtLevelCap(sess, explicitNow)
  if not sess then
    return
  end
  if sess.levelCapReached ~= true then
    sess.levelCapReached = true
    if sess.xpElapsedAtCap == nil then
      sess.xpElapsedAtCap = computeSessionLiveElapsedSeconds(sess, explicitNow)
    end
  end
  sess.pendingRollover = nil
  sess.pendingQuestXP = 0
end

local function updateSessionRestedTracking(sess, onGain)
  if not sess or not (ns.Compat and type(ns.Compat.GetPlayerRestedXPState) == "function") then
    return
  end
  local restRes = ns.Compat.GetPlayerRestedXPState()
  if type(restRes) ~= "table" or restRes.status ~= "ok" then
    return
  end
  local curRested = (restRes.isRested == true)
  if sess.initialRestedState == nil then
    sess.initialRestedState = curRested
  elseif sess.lastRestedState ~= nil and curRested ~= sess.lastRestedState then
    sess.restedRegimeChanged = true
    if onGain and sess.lastRestedState == true then
      sess.restedIncluded = true
    end
  end
  if onGain and curRested then
    sess.restedIncluded = true
  end
  sess.lastRestedState = curRested
end

captureXPBaseline = function(sess)
  if not sess then
    return
  end
  sess.pendingRollover = nil
  if ns.Compat and type(ns.Compat.GetPlayerXPState) == "function" then
    local xpRes = ns.Compat.GetPlayerXPState()
    if xpRes and xpRes.status == "ok" then
      sess.lastPlayerXP = xpRes.currentXP
      sess.lastPlayerMaxXP = xpRes.maxXP
      sess.lastPlayerLevel = xpRes.level
    elseif xpRes and xpRes.status == "capped" then
      sess.lastPlayerXP = xpRes.currentXP or 0
      sess.lastPlayerMaxXP = xpRes.maxXP or 0
      sess.lastPlayerLevel = xpRes.level
      sess.levelCapFinalDeltaCredited = true
      if sess.xpElapsedAtCap == nil then
        sess.xpElapsedAtCap = math.max(0, math.floor(tonumber(sess.accumulatedSeconds) or 0))
      end
      freezeSessionAtLevelCap(sess, nil)
    elseif xpRes and xpRes.status == "transitional_cap_zero" then
      sess.lastPlayerXP = 0
      sess.lastPlayerMaxXP = 0
      sess.lastPlayerLevel = xpRes.level
    else
      sess.lastPlayerXP = nil
      sess.lastPlayerMaxXP = nil
      sess.lastPlayerLevel = nil
    end
  else
    sess.lastPlayerXP = nil
    sess.lastPlayerMaxXP = nil
    sess.lastPlayerLevel = nil
  end
  updateSessionRestedTracking(sess, false)
end

function State.CheckpointGoldFarmTelemetry(explicitNow, explicitCopper, flushActive)
  local charDB = _G.ForeverHubCharDB
  if type(charDB) ~= "table" then
    return nil
  end
  local sess = State.goldFarmSession or {}
  if sess.active and (flushActive == true or explicitNow ~= nil or explicitCopper ~= nil) and resolveNowAndMoney and accrueOpenSegment then
    local nowSec, copper = resolveNowAndMoney(explicitNow, explicitCopper)
    accrueOpenSegment(sess, nowSec, copper)
  end
  local totalXP = math.max(0, math.floor(tonumber(sess.totalSessionXP or sess.accumulatedXP) or 0))
  local xpElapsedCap = (sess.xpElapsedAtCap ~= nil) and math.max(0, math.floor(tonumber(sess.xpElapsedAtCap) or 0)) or nil
  charDB.goldFarmTelemetry = {
    telemetryVersion = 3,
    sessionID = sess.sessionID,
    farmID = sess.farmID,
    phase = sess.phase,
    campSeconds = math.max(0, math.floor(tonumber(sess.campSeconds) or 0)),
    travelAndServiceSeconds = math.max(0, math.floor(tonumber(sess.travelAndServiceSeconds) or 0)),
    rxpUntrackedSeconds = math.max(0, math.floor(tonumber(sess.rxpUntrackedSeconds) or 0)),
    accumulatedSeconds = math.max(0, math.floor(tonumber(sess.accumulatedSeconds) or 0)),
    accumulatedCopper = math.floor(tonumber(sess.accumulatedCopper) or 0),
    accumulatedXP = totalXP,
    totalSessionXP = totalXP,
    attributableGrindXP = math.max(0, math.floor(tonumber(sess.attributableGrindXP) or 0)),
    questRewardXP = math.max(0, math.floor(tonumber(sess.questRewardXP) or 0)),
    unattributedXP = math.max(0, math.floor(tonumber(sess.unattributedXP) or 0)),
    killsObserved = math.max(0, math.floor(tonumber(sess.killsObserved) or 0)),
    levelCapReached = (sess.levelCapReached == true),
    levelCapFinalDeltaCredited = (sess.levelCapFinalDeltaCredited == true),
    xpElapsedAtCap = xpElapsedCap,
    terminalSnapshotUnresolved = (sess.terminalSnapshotUnresolved == true),
    xpContaminated = (sess.xpContaminated == true),
    xpContaminationReason = sess.xpContaminationReason,
    xpRolloverUnresolved = (sess.xpRolloverUnresolved == true),
    restedIncluded = (sess.restedIncluded == true),
    restedRegimeChanged = (sess.restedRegimeChanged == true),
    contaminated = (sess.contaminated == true),
    contaminationReason = sess.contaminationReason,
    cleanIntervalConfirmed = (sess.cleanIntervalConfirmed ~= false) and (sess.contaminated ~= true),
  }
  return charDB.goldFarmTelemetry
end

function State.LoadPersistedGoldFarmTelemetry()
  local charDB = _G.ForeverHubCharDB
  local raw = (type(charDB) == "table" and type(charDB.goldFarmTelemetry) == "table") and charDB.goldFarmTelemetry or {}
  local campSec = math.max(0, math.floor(tonumber(raw.campSeconds) or 0))
  local travelSec = math.max(0, math.floor(tonumber(raw.travelAndServiceSeconds) or 0))
  local rxpSec = math.max(0, math.floor(tonumber(raw.rxpUntrackedSeconds) or 0))
  local accSec = math.max(0, math.floor(tonumber(raw.accumulatedSeconds) or (campSec + travelSec + rxpSec)))
  if campSec + travelSec + rxpSec ~= accSec then
    campSec = math.max(0, accSec - travelSec - rxpSec)
  end
  local contaminated = (raw.contaminated == true)
  local totalXP = math.max(0, math.floor(tonumber(raw.totalSessionXP or raw.accumulatedXP) or 0))
  local attribXP = math.max(0, math.floor(tonumber(raw.attributableGrindXP) or 0))
  local questXP = math.max(0, math.floor(tonumber(raw.questRewardXP) or 0))
  local unattribXP = math.max(0, math.floor(tonumber(raw.unattributedXP) or math.max(0, totalXP - attribXP - questXP)))
  local hasPriorTotals = (accSec > 0) or ((tonumber(raw.accumulatedCopper) or 0) ~= 0) or (totalXP > 0) or (raw.farmID ~= nil)
  local restoredPhase = normalizeTelemetryPhase(raw.phase) or "camp"
  local xpElapsedCap = (raw.xpElapsedAtCap ~= nil) and math.max(0, math.floor(tonumber(raw.xpElapsedAtCap) or 0)) or nil

  -- Astra P1-9: After reload/login, ALWAYS resume telemetry PAUSED with nil clock/money/XP baseline
  -- so offline time or unexplained reload money/XP changes are NEVER counted!
  State.goldFarmSession = {
    sessionID = type(raw.sessionID) == "string" and raw.sessionID or newTelemetrySessionID(0),
    active = false,
    pausedByReload = hasPriorTotals,
    pausedForWindow = nil,
    wasActiveBeforeWindow = false,
    activeWindows = {},
    farmID = type(raw.farmID) == "string" and raw.farmID or nil,
    phase = restoredPhase,
    segmentStartedAt = nil,
    segmentStartCopper = nil,
    campSeconds = campSec,
    travelAndServiceSeconds = travelSec,
    rxpUntrackedSeconds = rxpSec,
    accumulatedSeconds = accSec,
    accumulatedCopper = math.floor(tonumber(raw.accumulatedCopper) or 0),
    accumulatedXP = totalXP,
    totalSessionXP = totalXP,
    attributableGrindXP = attribXP,
    questRewardXP = questXP,
    unattributedXP = unattribXP,
    killsObserved = math.max(0, math.floor(tonumber(raw.killsObserved) or 0)),
    lastPlayerXP = nil,
    lastPlayerMaxXP = nil,
    lastPlayerLevel = nil,
    pendingRollover = nil,
    pendingQuestXP = 0,
    pendingCampKillCredits = {},
    recentCampKills = {},
    recentUnattributedDeltas = {},
    initialRestedState = nil,
    lastRestedState = nil,
    restedIncluded = (raw.restedIncluded == true),
    restedRegimeChanged = (raw.restedRegimeChanged == true),
    levelCapReached = (raw.levelCapReached == true),
    levelCapFinalDeltaCredited = (raw.levelCapFinalDeltaCredited == true),
    xpElapsedAtCap = xpElapsedCap,
    terminalSnapshotUnresolved = (raw.terminalSnapshotUnresolved == true),
    xpBaselineGap = false,
    xpRolloverUnresolved = (raw.xpRolloverUnresolved == true),
    xpContaminated = (raw.xpContaminated == true) or (raw.xpRolloverUnresolved == true) or (raw.terminalSnapshotUnresolved == true) or (unattribXP > 0),
    xpContaminationReason = raw.xpContaminationReason,
    contaminated = contaminated,
    contaminationReason = raw.contaminationReason,
    cleanIntervalConfirmed = (raw.cleanIntervalConfirmed ~= false) and not contaminated,
  }
  refreshXPContaminationFlags(State.goldFarmSession)
  State.CheckpointGoldFarmTelemetry()
  return State.goldFarmSession
end

function State.EnsureGoldFarmProgressInitialized(isReloadOrAddonLoad)
  local charDB = _G.ForeverHubCharDB
  if type(charDB) ~= "table" then
    return nil
  end
  charDB.goldFarmProgress = State.MigrateGoldFarmProgress(charDB.goldFarmProgress, State.GetCompiledGoldFarms())
  if isReloadOrAddonLoad then
    State.LoadPersistedGoldFarmTelemetry()
  end
  return charDB.goldFarmProgress
end

function State.GetGoldFarmProgress()
  local charDB = State.GetCharDB()
  if type(charDB.goldFarmProgress) ~= "table" or charDB.goldFarmProgress.goldStateVersion ~= 2 then
    charDB.goldFarmProgress = State.MigrateGoldFarmProgress(charDB.goldFarmProgress, State.GetCompiledGoldFarms())
  end
  return charDB.goldFarmProgress
end

resolveNowAndMoney = function(explicitNow, explicitCopper)
  local nowSec = tonumber(explicitNow)
  if not nowSec then
    nowSec = (type(time) == "function" and time()) or 0
  end
  local copper = nil
  if explicitCopper ~= nil then
    if explicitCopper == "unavailable" or explicitCopper == "unknown" then
      copper = nil
    else
      copper = tonumber(explicitCopper)
    end
  elseif ns.Compat and ns.Compat.GetPlayerMoneyCopper then
    local mr = ns.Compat.GetPlayerMoneyCopper()
    if mr.status == "ok" and type(mr.copper) == "number" then
      copper = mr.copper
    end
  end
  return nowSec, copper
end

accrueOpenSegment = function(sess, nowSec, copper)
  if not sess or not sess.active then
    return
  end
  if type(sess.segmentStartedAt) == "number" then
    local dt = math.max(0, math.floor(nowSec - sess.segmentStartedAt))
    if sess.phase == "rxp_untracked" then
      sess.rxpUntrackedSeconds = (sess.rxpUntrackedSeconds or 0) + dt
    elseif sess.phase == "travel_service" then
      sess.travelAndServiceSeconds = (sess.travelAndServiceSeconds or 0) + dt
    else
      sess.campSeconds = (sess.campSeconds or 0) + dt
    end
    sess.accumulatedSeconds = (sess.campSeconds or 0) + (sess.travelAndServiceSeconds or 0) + (sess.rxpUntrackedSeconds or 0)
    sess.segmentStartedAt = nowSec
  end
  if type(sess.segmentStartCopper) == "number" and type(copper) == "number" then
    sess.accumulatedCopper = (sess.accumulatedCopper or 0) + (copper - sess.segmentStartCopper)
    sess.segmentStartCopper = copper
  elseif sess.segmentStartCopper == nil and type(copper) == "number" then
    -- Money was previously unavailable; do not attribute unknown prior delta — mark interval unclean!
    sess.segmentStartCopper = copper
    sess.contaminated = true
    sess.contaminationReason = sess.contaminationReason or "money_previously_unavailable"
    sess.cleanIntervalConfirmed = false
  elseif type(sess.segmentStartCopper) == "number" and copper == nil then
    -- Money became unavailable mid-segment: cannot verify delta across gap
    sess.segmentStartCopper = nil
    sess.contaminated = true
    sess.contaminationReason = sess.contaminationReason or "money_unavailable_gap"
    sess.cleanIntervalConfirmed = false
  end
end

function State.SetGoldFarmActivityPhase(stepKind, explicitNow, explicitCopper)
  local sess = State.goldFarmSession
  if not sess then
    return
  end
  local targetPhase = normalizeTelemetryPhase(stepKind) or "travel_service"
  if sess.phase == targetPhase then
    return
  end
  if sess.active then
    local nowSec, copper = resolveNowAndMoney(explicitNow, explicitCopper)
    accrueOpenSegment(sess, nowSec, copper)
  end
  sess.phase = targetPhase
  State.CheckpointGoldFarmTelemetry()
end

function State.PauseGoldFarmSession(explicitNow, explicitCopper)
  local sess = State.goldFarmSession
  if not sess then
    return sess
  end
  sess.wasActiveBeforeWindow = false
  if not sess.active then
    State.CheckpointGoldFarmTelemetry()
    return sess
  end
  local nowSec, copper = resolveNowAndMoney(explicitNow, explicitCopper)
  accrueOpenSegment(sess, nowSec, copper)
  sess.active = false
  sess.pausedByReload = false
  sess.segmentStartedAt = nil
  sess.segmentStartCopper = nil
  sess.lastPlayerXP = nil
  sess.lastPlayerMaxXP = nil
  sess.lastPlayerLevel = nil
  sess.pendingRollover = nil
  State.CheckpointGoldFarmTelemetry()
  return sess
end

function State.StartOrResumeGoldFarmSession(farmID, explicitNow, explicitCopper, initialPhase)
  -- Defensive normalization if a caller ever passes a phase label in arg 2
  if initialPhase == nil and type(explicitNow) == "string" and normalizeTelemetryPhase(explicitNow) ~= nil then
    initialPhase = explicitNow
    explicitNow = nil
  end
  local nowSec, copper = resolveNowAndMoney(explicitNow, explicitCopper)
  local sess = State.goldFarmSession
  if sess.active and sess.farmID ~= farmID then
    State.PauseGoldFarmSession(nowSec, copper)
  end
  if sess.farmID ~= farmID then
    sess.sessionID = newTelemetrySessionID(nowSec)
    sess.farmID = farmID
    sess.campSeconds = 0
    sess.travelAndServiceSeconds = 0
    sess.rxpUntrackedSeconds = 0
    sess.accumulatedSeconds = 0
    sess.accumulatedCopper = 0
    sess.accumulatedXP = 0
    sess.totalSessionXP = 0
    sess.attributableGrindXP = 0
    sess.questRewardXP = 0
    sess.unattributedXP = 0
    sess.killsObserved = 0
    sess.lastPlayerXP = nil
    sess.lastPlayerMaxXP = nil
    sess.lastPlayerLevel = nil
    sess.pendingRollover = nil
    sess.pendingQuestXP = 0
    sess.pendingCampKillCredits = {}
    sess.recentCampKills = {}
    sess.recentUnattributedDeltas = {}
    sess.initialRestedState = nil
    sess.lastRestedState = nil
    sess.restedIncluded = false
    sess.restedRegimeChanged = false
    sess.levelCapReached = false
    sess.levelCapFinalDeltaCredited = false
    sess.xpElapsedAtCap = nil
    sess.terminalSnapshotUnresolved = false
    sess.xpBaselineGap = false
    sess.xpRolloverUnresolved = false
    sess.xpContaminated = false
    sess.xpContaminationReason = nil
    sess.contaminated = false
    sess.contaminationReason = nil
    sess.cleanIntervalConfirmed = (copper ~= nil)
  end
  local normPhase = normalizeTelemetryPhase(initialPhase)
  if normPhase ~= nil then
    if sess.active and sess.phase ~= normPhase then
      accrueOpenSegment(sess, nowSec, copper)
    end
    sess.phase = normPhase
  elseif normalizeTelemetryPhase(sess.phase) == nil then
    sess.phase = "camp"
  end
  sess.pausedByReload = false
  if next(sess.activeWindows or {}) ~= nil then
    sess.active = false
    sess.wasActiveBeforeWindow = true
    sess.segmentStartedAt = nil
    sess.segmentStartCopper = nil
    sess.lastPlayerXP = nil
    sess.lastPlayerMaxXP = nil
    sess.lastPlayerLevel = nil
    sess.pendingRollover = nil
  elseif not sess.active then
    sess.active = true
    sess.segmentStartedAt = nowSec
    sess.segmentStartCopper = copper
    captureXPBaseline(sess)
    if copper == nil then
      sess.contaminated = true
      sess.contaminationReason = sess.contaminationReason or "money_unavailable_at_start"
      sess.cleanIntervalConfirmed = false
    end
  end
  State.CheckpointGoldFarmTelemetry()
  return sess
end

function State.ResetGoldFarmSession(farmID, keepActive, explicitNow, explicitCopper, initialPhase)
  local nowSec, copper = resolveNowAndMoney(explicitNow, explicitCopper)
  local hasOpenWindow = next((State.goldFarmSession and State.goldFarmSession.activeWindows) or {}) ~= nil
  local clean = (copper ~= nil) and not hasOpenWindow
  local normPhase = normalizeTelemetryPhase(initialPhase)
    or normalizeTelemetryPhase(State.goldFarmSession and State.goldFarmSession.phase)
    or "camp"
  local isStarted = (keepActive == true) and not hasOpenWindow
  State.goldFarmSession = {
    sessionID = newTelemetrySessionID(nowSec),
    active = isStarted,
    pausedByReload = false,
    pausedForWindow = hasOpenWindow and State.goldFarmSession.pausedForWindow or nil,
    wasActiveBeforeWindow = (keepActive == true) and hasOpenWindow,
    activeWindows = (State.goldFarmSession and State.goldFarmSession.activeWindows) or {},
    farmID = farmID,
    phase = normPhase,
    segmentStartedAt = isStarted and nowSec or nil,
    segmentStartCopper = isStarted and copper or nil,
    campSeconds = 0,
    travelAndServiceSeconds = 0,
    rxpUntrackedSeconds = 0,
    accumulatedSeconds = 0,
    accumulatedCopper = 0,
    accumulatedXP = 0,
    totalSessionXP = 0,
    attributableGrindXP = 0,
    questRewardXP = 0,
    unattributedXP = 0,
    killsObserved = 0,
    lastPlayerXP = nil,
    lastPlayerMaxXP = nil,
    lastPlayerLevel = nil,
    pendingRollover = nil,
    pendingQuestXP = 0,
    pendingCampKillCredits = {},
    recentCampKills = {},
    recentUnattributedDeltas = {},
    initialRestedState = nil,
    lastRestedState = nil,
    restedIncluded = false,
    restedRegimeChanged = false,
    levelCapReached = false,
    levelCapFinalDeltaCredited = false,
    xpElapsedAtCap = nil,
    terminalSnapshotUnresolved = false,
    xpBaselineGap = false,
    xpRolloverUnresolved = false,
    xpContaminated = false,
    xpContaminationReason = nil,
    contaminated = not clean,
    contaminationReason = hasOpenWindow and State.goldFarmSession.pausedForWindow or (copper == nil and "money_unavailable_at_reset" or nil),
    cleanIntervalConfirmed = clean,
  }
  if isStarted then
    captureXPBaseline(State.goldFarmSession)
  end
  State.CheckpointGoldFarmTelemetry()
  return State.goldFarmSession
end

function State.RecordGoldFarmVerifiedCampKill(killInfo)
  local sess = State.goldFarmSession
  if not sess or not sess.active then
    return { recorded = false, reason = "session_inactive" }
  end
  killInfo = type(killInfo) == "table" and killInfo or {}
  local monoNow, wallNow = resolveSessionMonoAndWall(killInfo.nowMono, killInfo.nowWall)
  local guid = (type(killInfo.guid) == "string" and killInfo.guid ~= "") and killInfo.guid or nil
  local npcName = (type(killInfo.npcName) == "string" and killInfo.npcName ~= "") and killInfo.npcName or nil
  local expectedXP = tonumber(killInfo.expectedXP)
  if expectedXP and expectedXP > 0 then
    expectedXP = math.floor(expectedXP)
  else
    expectedXP = nil
  end

  sess.recentCampKills = sess.recentCampKills or {}
  sess.pendingCampKillCredits = sess.pendingCampKillCredits or {}
  sess.recentUnattributedDeltas = sess.recentUnattributedDeltas or {}

  -- Prune expired recentCampKills (> 15s) and deduplicate UNIT_DIED + CHAT_MSG_COMBAT_XP_GAIN
  local freshKills = {}
  local mergedExisting = nil
  for _, rec in ipairs(sess.recentCampKills) do
    if isWithinReconcileWindow(rec, monoNow, wallNow, 15.0) then
      table.insert(freshKills, rec)
      if not mergedExisting then
        if guid and rec.guid and guid == rec.guid then
          mergedExisting = rec
        elseif not guid and npcName and rec.npcName == npcName and not rec.chatMerged and isWithinReconcileWindow(rec, monoNow, wallNow, 2.0) then
          mergedExisting = rec
        elseif guid and not rec.guid and npcName and rec.npcName == npcName and isWithinReconcileWindow(rec, monoNow, wallNow, 2.0) then
          rec.guid = guid
          mergedExisting = rec
        end
      end
    end
  end
  sess.recentCampKills = freshKills

  if mergedExisting then
    if expectedXP and not mergedExisting.chatMerged then
      mergedExisting.chatMerged = true
      if mergedExisting.creditRef and mergedExisting.creditRef.expectedXP == nil then
        mergedExisting.creditRef.expectedXP = expectedXP
      end
    end
    State.CheckpointGoldFarmTelemetry()
    return { recorded = false, deduplicated = true, killsObserved = sess.killsObserved }
  end

  sess.killsObserved = (tonumber(sess.killsObserved) or 0) + 1

  -- If PLAYER_XP_UPDATE fired moments BEFORE this kill notification (< 2.0s), reclassify that delta immediately!
  local reclassified = 0
  local maxClaim = expectedXP or 1500
  for i = #sess.recentUnattributedDeltas, 1, -1 do
    local uEntry = sess.recentUnattributedDeltas[i]
    if isWithinReconcileWindow(uEntry, monoNow, wallNow, 2.0) and (tonumber(uEntry.remaining) or 0) > 0 then
      local avail = math.floor(tonumber(uEntry.remaining) or 0)
      if expectedXP == nil and avail > maxClaim then
        -- Do not misclassify a large quest turn-in delta as a chat-less UNIT_DIED mob kill
      else
        local take = expectedXP and math.min(avail, expectedXP) or avail
        uEntry.remaining = avail - take
        sess.unattributedXP = math.max(0, (tonumber(sess.unattributedXP) or 0) - take)
        sess.attributableGrindXP = (tonumber(sess.attributableGrindXP) or 0) + take
        reclassified = take
        break
      end
    end
  end

  local creditObj = nil
  if sess.levelCapReached ~= true and (reclassified == 0 or (expectedXP and reclassified < expectedXP)) then
    creditObj = {
      guid = guid,
      npcName = npcName,
      expectedXP = expectedXP and (expectedXP - reclassified) or nil,
      atMono = monoNow,
      atWall = wallNow,
    }
    table.insert(sess.pendingCampKillCredits, creditObj)
  end

  table.insert(sess.recentCampKills, {
    guid = guid,
    npcName = npcName,
    chatMerged = (expectedXP ~= nil),
    creditRef = creditObj,
    atMono = monoNow,
    atWall = wallNow,
  })

  refreshXPContaminationFlags(sess)
  State.CheckpointGoldFarmTelemetry()
  return {
    recorded = true,
    killsObserved = sess.killsObserved,
    reclassifiedXP = reclassified,
  }
end

function State.RecordGoldFarmQuestTurnInXP(questID, xpReward, explicitMono, explicitWall)
  local sess = State.goldFarmSession
  if not sess or not sess.active then
    return { recorded = false, reason = "session_inactive" }
  end
  local qXP = tonumber(xpReward)
  if not qXP or qXP <= 0 then
    return { recorded = false, reason = "zero_or_missing_quest_xp", questID = questID }
  end
  qXP = math.floor(qXP)
  local monoNow, wallNow = resolveSessionMonoAndWall(explicitMono, explicitWall)
  sess.recentUnattributedDeltas = sess.recentUnattributedDeltas or {}

  -- Reconcile regardless of whether PLAYER_XP_UPDATE arrived before or after QUEST_TURNED_IN!
  local remainingToMatch = qXP
  for i = #sess.recentUnattributedDeltas, 1, -1 do
    if remainingToMatch <= 0 then
      break
    end
    local uEntry = sess.recentUnattributedDeltas[i]
    if isWithinReconcileWindow(uEntry, monoNow, wallNow, 2.5) and (tonumber(uEntry.remaining) or 0) > 0 then
      local take = math.min(remainingToMatch, math.floor(tonumber(uEntry.remaining) or 0))
      uEntry.remaining = uEntry.remaining - take
      remainingToMatch = remainingToMatch - take
      sess.unattributedXP = math.max(0, (tonumber(sess.unattributedXP) or 0) - take)
      sess.questRewardXP = (tonumber(sess.questRewardXP) or 0) + take
    end
  end

  if remainingToMatch > 0 and sess.levelCapReached ~= true then
    sess.pendingQuestXP = (tonumber(sess.pendingQuestXP) or 0) + remainingToMatch
  end

  refreshXPContaminationFlags(sess)
  State.CheckpointGoldFarmTelemetry()
  return {
    recorded = true,
    questID = questID,
    questXP = qXP,
    reclassifiedXP = qXP - remainingToMatch,
    pendingQuestXP = sess.pendingQuestXP,
  }
end

function State.ReconcileGoldFarmXPSnapshot(opts)
  opts = type(opts) == "table" and opts or {}
  local sess = State.goldFarmSession
  if not sess or not sess.active then
    return { ok = false, reason = "session_inactive", delta = 0 }
  end

  local monoNow, wallNow = resolveSessionMonoAndWall(opts.nowMono, opts.nowWall)
  sess.pendingCampKillCredits = sess.pendingCampKillCredits or {}
  sess.recentUnattributedDeltas = sess.recentUnattributedDeltas or {}

  if opts.trigger == "UPDATE_EXHAUSTION" then
    updateSessionRestedTracking(sess, false)
    State.CheckpointGoldFarmTelemetry()
    return { ok = true, reason = "exhaustion_updated", delta = 0 }
  end

  if not (ns.Compat and type(ns.Compat.GetPlayerXPState) == "function") then
    return { ok = false, reason = "compat_unavailable", delta = 0 }
  end

  local maxCapLevel = (ns.Compat and tonumber(ns.Compat.MAX_PLAYER_LEVEL)) or 60
  local hintLevel = tonumber(opts.newLevel)
  local xpRes = ns.Compat.GetPlayerXPState()
  local validProbe = (
    type(xpRes) == "table"
    and (xpRes.status == "ok" or xpRes.status == "capped" or xpRes.status == "transitional_cap_zero")
  )
  if not validProbe then
    local isTerminalContext = (hintLevel and hintLevel >= maxCapLevel)
      or (sess.lastPlayerLevel ~= nil and sess.lastPlayerLevel >= (maxCapLevel - 1))
      or (type(sess.pendingRollover) == "table" and (tonumber(sess.pendingRollover.targetLevel) or 0) >= maxCapLevel)
      or (sess.levelCapReached == true)
    if isTerminalContext then
      -- Astra P1-1: On an unknown/corrupt terminal probe, mark terminalSnapshotUnresolved WITHOUT wiping last valid snapshot!
      sess.terminalSnapshotUnresolved = true
      if sess.levelCapReached ~= true then
        sess.xpRolloverUnresolved = true
      end
      sess.xpContaminationReason = sess.xpContaminationReason or "terminal_xp_probe_unavailable"
      refreshXPContaminationFlags(sess)
      State.CheckpointGoldFarmTelemetry()
      return {
        ok = false,
        reason = "terminal_xp_probe_unavailable",
        delta = 0,
        terminalSnapshotUnresolved = true,
      }
    end
    if sess.lastPlayerXP ~= nil then
      sess.lastPlayerXP = nil
      sess.lastPlayerMaxXP = nil
      sess.lastPlayerLevel = nil
      sess.pendingRollover = nil
      sess.xpBaselineGap = true
      sess.xpContaminationReason = sess.xpContaminationReason or "xp_state_unavailable"
      refreshXPContaminationFlags(sess)
      State.CheckpointGoldFarmTelemetry()
    end
    return { ok = false, reason = "xp_state_unavailable", delta = 0 }
  end

  local effectiveLevel = xpRes.level
  if hintLevel and hintLevel > effectiveLevel then
    effectiveLevel = math.floor(hintLevel)
  end

  if sess.lastPlayerXP == nil or sess.lastPlayerLevel == nil or sess.lastPlayerMaxXP == nil then
    sess.lastPlayerXP = xpRes.currentXP or 0
    sess.lastPlayerMaxXP = xpRes.maxXP or 0
    sess.lastPlayerLevel = effectiveLevel
    sess.pendingRollover = nil
    if effectiveLevel >= maxCapLevel or xpRes.status == "capped" then
      sess.levelCapFinalDeltaCredited = true
      freezeSessionAtLevelCap(sess, wallNow)
    elseif (tonumber(sess.totalSessionXP) or 0) > 0 or (tonumber(sess.accumulatedSeconds) or 0) > 0 then
      sess.xpBaselineGap = true
      sess.xpContaminationReason = sess.xpContaminationReason or "xp_baseline_reacquired"
      refreshXPContaminationFlags(sess)
    end
    updateSessionRestedTracking(sess, false)
    State.CheckpointGoldFarmTelemetry()
    return {
      ok = true,
      reason = "baseline_initialized",
      status = (sess.levelCapReached == true) and "at_level_cap" or "baseline_initialized",
      delta = 0,
    }
  end

  -- Already at cap: absorb repeated PLAYER_XP_UPDATE / PLAYER_LEVEL_UP events with zero XP delta and zero contamination
  if sess.levelCapReached == true and effectiveLevel >= maxCapLevel then
    sess.lastPlayerLevel = effectiveLevel
    sess.lastPlayerXP = xpRes.currentXP or 0
    sess.lastPlayerMaxXP = xpRes.maxXP or 0
    freezeSessionAtLevelCap(sess, wallNow)
    updateSessionRestedTracking(sess, false)
    refreshXPContaminationFlags(sess)
    State.CheckpointGoldFarmTelemetry()
    return {
      ok = true,
      status = "at_level_cap",
      delta = 0,
      totalSessionXP = sess.totalSessionXP,
      attributableGrindXP = sess.attributableGrindXP,
      questRewardXP = sess.questRewardXP,
      unattributedXP = sess.unattributedXP,
      levelCapReached = true,
      xpElapsedAtCap = sess.xpElapsedAtCap,
      xpContaminated = sess.xpContaminated,
      xpRolloverUnresolved = sess.xpRolloverUnresolved,
    }
  end

  local delta = 0
  local transitionStatus = "steady"
  local pendingQuestBeforeCap = math.max(0, math.floor(tonumber(sess.pendingQuestXP) or 0))

  if type(sess.pendingRollover) == "table" then
    local pr = sess.pendingRollover
    if effectiveLevel > (pr.fromLevel + 1) then
      sess.pendingRollover = nil
      sess.xpRolloverUnresolved = true
      sess.xpContaminationReason = "multi_level_rollover_unresolved"
      sess.lastPlayerLevel = effectiveLevel
      sess.lastPlayerXP = xpRes.currentXP
      sess.lastPlayerMaxXP = xpRes.maxXP
      if effectiveLevel >= maxCapLevel then
        sess.levelCapFinalDeltaCredited = true
        freezeSessionAtLevelCap(sess, wallNow)
      end
      transitionStatus = "multi_level_unresolved"
    elseif effectiveLevel < pr.fromLevel then
      sess.pendingRollover = nil
      sess.xpRolloverUnresolved = true
      sess.xpContaminationReason = "incoherent_level_decrease"
      sess.lastPlayerLevel = effectiveLevel
      sess.lastPlayerXP = xpRes.currentXP
      sess.lastPlayerMaxXP = xpRes.maxXP
      transitionStatus = "incoherent_level_decrease"
    elseif effectiveLevel >= maxCapLevel and pr.fromLevel == (maxCapLevel - 1) then
      -- Terminal 59 -> 60 resolution after staged wrap: credit (fromMaxXP - fromXP) once, never post-cap overflow!
      if sess.levelCapFinalDeltaCredited ~= true
        and pr.fromMaxXP > 0
        and pr.fromXP >= 0
        and pr.fromXP <= pr.fromMaxXP
        and (pr.fromXP > 0 or pr.fromMaxXP <= 50000 or (tonumber(sess.pendingQuestXP) or 0) > 0)
      then
        delta = math.max(0, pr.fromMaxXP - pr.fromXP)
        sess.levelCapFinalDeltaCredited = true
        transitionStatus = "level_cap_reached"
      elseif sess.levelCapFinalDeltaCredited ~= true then
        sess.xpRolloverUnresolved = true
        sess.xpContaminationReason = "implausible_cap_jump"
        transitionStatus = "implausible_cap_jump"
      else
        transitionStatus = "at_level_cap"
      end
      sess.lastPlayerLevel = effectiveLevel
      sess.lastPlayerXP = xpRes.currentXP or 0
      sess.lastPlayerMaxXP = xpRes.maxXP or 0
      freezeSessionAtLevelCap(sess, wallNow)
    elseif effectiveLevel == pr.targetLevel then
      local postWrapXP = nil
      if xpRes.currentXP < pr.fromXP then
        postWrapXP = xpRes.currentXP
      elseif pr.wrappedXP ~= nil and xpRes.currentXP == pr.wrappedXP then
        postWrapXP = pr.wrappedXP
      end
      if postWrapXP ~= nil and postWrapXP >= 0 and postWrapXP < pr.fromMaxXP and ((pr.fromMaxXP - pr.fromXP) + postWrapXP) < pr.fromMaxXP then
        delta = math.max(0, (pr.fromMaxXP - pr.fromXP) + postWrapXP)
        sess.pendingRollover = nil
        sess.lastPlayerLevel = effectiveLevel
        sess.lastPlayerXP = postWrapXP
        sess.lastPlayerMaxXP = xpRes.maxXP
        transitionStatus = "rollover_resolved"
      else
        transitionStatus = "rollover_pending_wrap"
      end
    else
      -- effectiveLevel == pr.fromLevel while waiting for PLAYER_LEVEL_UP
      if pr.wrappedXP ~= nil and xpRes.currentXP > pr.wrappedXP and opts.trigger == "PLAYER_XP_UPDATE" then
        sess.pendingRollover = nil
        sess.xpRolloverUnresolved = true
        sess.xpContaminationReason = "incoherent_xp_decrease"
        sess.lastPlayerLevel = effectiveLevel
        sess.lastPlayerXP = xpRes.currentXP
        sess.lastPlayerMaxXP = xpRes.maxXP
        transitionStatus = "incoherent_xp_decrease"
      else
        transitionStatus = "rollover_pending_level"
      end
    end
  else
    local prevLvl = sess.lastPlayerLevel
    local prevXP = sess.lastPlayerXP
    local prevMax = sess.lastPlayerMaxXP

    if effectiveLevel >= maxCapLevel and prevLvl == (maxCapLevel - 1) then
      -- Terminal 59 -> 60 transition (single-step OR PLAYER_LEVEL_UP(60) arriving before PLAYER_XP_UPDATE):
      -- Remainder to cap is strictly (prevMax - prevXP); never infer post-cap overflow XP!
      if sess.levelCapFinalDeltaCredited ~= true
        and prevMax > 0
        and prevXP >= 0
        and prevXP <= prevMax
        and (prevXP > 0 or prevMax <= 50000 or (tonumber(sess.pendingQuestXP) or 0) > 0)
      then
        delta = math.max(0, prevMax - prevXP)
        sess.levelCapFinalDeltaCredited = true
        transitionStatus = "level_cap_reached"
      elseif sess.levelCapFinalDeltaCredited ~= true then
        sess.xpRolloverUnresolved = true
        sess.xpContaminationReason = "implausible_cap_jump"
        transitionStatus = "implausible_cap_jump"
      else
        transitionStatus = "at_level_cap"
      end
      sess.lastPlayerLevel = effectiveLevel
      sess.lastPlayerXP = xpRes.currentXP or 0
      sess.lastPlayerMaxXP = xpRes.maxXP or 0
      freezeSessionAtLevelCap(sess, wallNow)
    elseif effectiveLevel == prevLvl then
      if xpRes.status == "transitional_cap_zero" then
        -- PLAYER_XP_UPDATE zeroed UnitXP/UnitXPMax at Lv 59 moments before UnitLevel updated to 60
        sess.pendingRollover = {
          fromLevel = prevLvl,
          fromXP = prevXP,
          fromMaxXP = prevMax,
          targetLevel = prevLvl + 1,
          wrappedXP = 0,
        }
        transitionStatus = "rollover_staged_pre_level"
      elseif xpRes.currentXP >= prevXP then
        delta = xpRes.currentXP - prevXP
        sess.lastPlayerXP = xpRes.currentXP
        sess.lastPlayerMaxXP = xpRes.maxXP
        transitionStatus = delta > 0 and "same_level_gain" or "no_change"
      else
        -- UnitXP wrapped before UnitLevel reported the new level; stage pending rollover!
        sess.pendingRollover = {
          fromLevel = prevLvl,
          fromXP = prevXP,
          fromMaxXP = prevMax,
          targetLevel = prevLvl + 1,
          wrappedXP = xpRes.currentXP,
        }
        transitionStatus = "rollover_staged_pre_level"
      end
    elseif effectiveLevel == (prevLvl + 1) then
      if prevXP > 0 and xpRes.currentXP < prevXP and xpRes.currentXP < prevMax and ((prevMax - prevXP) + xpRes.currentXP) < prevMax then
        delta = math.max(0, (prevMax - prevXP) + xpRes.currentXP)
        sess.lastPlayerLevel = effectiveLevel
        sess.lastPlayerXP = xpRes.currentXP
        sess.lastPlayerMaxXP = xpRes.maxXP
        transitionStatus = "rollover_single_step"
      else
        -- Mixed transitional snapshot (e.g. Lv 48 reported while UnitXP still reads 129900): stage and wait!
        sess.pendingRollover = {
          fromLevel = prevLvl,
          fromXP = prevXP,
          fromMaxXP = prevMax,
          targetLevel = effectiveLevel,
          wrappedXP = nil,
        }
        transitionStatus = "rollover_staged_pre_wrap"
      end
    else
      -- Multi-level jump (e.g. 47 -> 49 or 58 -> 60) or level decrease: never guess intervening XP requirements!
      sess.xpRolloverUnresolved = true
      sess.xpContaminationReason = (effectiveLevel > prevLvl + 1) and "multi_level_rollover_unresolved" or "incoherent_level_decrease"
      sess.lastPlayerLevel = effectiveLevel
      sess.lastPlayerXP = xpRes.currentXP
      sess.lastPlayerMaxXP = xpRes.maxXP
      if effectiveLevel >= maxCapLevel then
        sess.levelCapFinalDeltaCredited = true
        freezeSessionAtLevelCap(sess, wallNow)
      end
      transitionStatus = "multi_level_unresolved"
    end
  end

  -- Note: freezeSessionAtLevelCap clears pendingQuestXP, so restore pendingQuestBeforeCap temporarily if delta > 0
  if delta > 0 and pendingQuestBeforeCap > 0 and (tonumber(sess.pendingQuestXP) or 0) == 0 then
    sess.pendingQuestXP = pendingQuestBeforeCap
  end

  if delta > 0 then
    local wasRestedBefore = (sess.lastRestedState == true)
    updateSessionRestedTracking(sess, true)
    if wasRestedBefore then
      sess.restedIncluded = true
    end

    sess.totalSessionXP = (tonumber(sess.totalSessionXP) or 0) + delta
    sess.accumulatedXP = sess.totalSessionXP

    local remDelta = delta

    -- 1) Consume pending quest turn-in XP first
    local pendingQ = math.max(0, math.floor(tonumber(sess.pendingQuestXP) or 0))
    if pendingQ > 0 and remDelta > 0 then
      local qTake = math.min(remDelta, pendingQ)
      sess.pendingQuestXP = pendingQ - qTake
      sess.questRewardXP = (tonumber(sess.questRewardXP) or 0) + qTake
      remDelta = remDelta - qTake
    end
    if sess.levelCapReached == true then
      sess.pendingQuestXP = 0
    end

    -- 2) Prune expired kill credits and consume fresh verified camp kill credits
    local keptCredits = {}
    for _, cr in ipairs(sess.pendingCampKillCredits) do
      if isWithinReconcileWindow(cr, monoNow, wallNow, 5.0) then
        if remDelta > 0 then
          local maxSingle = cr.expectedXP or 1500
          if cr.expectedXP == nil and remDelta > maxSingle then
            table.insert(keptCredits, cr)
          else
            local kTake = cr.expectedXP and math.min(remDelta, cr.expectedXP) or remDelta
            sess.attributableGrindXP = (tonumber(sess.attributableGrindXP) or 0) + kTake
            remDelta = remDelta - kTake
          end
        else
          table.insert(keptCredits, cr)
        end
      end
    end
    sess.pendingCampKillCredits = keptCredits

    -- 3) Any remaining XP delta enters unattributedXP (and can be reclassified within ~2s if event order was inverted)
    if remDelta > 0 then
      sess.unattributedXP = (tonumber(sess.unattributedXP) or 0) + remDelta
      table.insert(sess.recentUnattributedDeltas, {
        remaining = remDelta,
        atMono = monoNow,
        atWall = wallNow,
      })
      while #sess.recentUnattributedDeltas > 12 do
        table.remove(sess.recentUnattributedDeltas, 1)
      end
    end
  else
    updateSessionRestedTracking(sess, false)
  end

  refreshXPContaminationFlags(sess)
  State.CheckpointGoldFarmTelemetry()
  return {
    ok = true,
    status = transitionStatus,
    delta = delta,
    totalSessionXP = sess.totalSessionXP,
    attributableGrindXP = sess.attributableGrindXP,
    questRewardXP = sess.questRewardXP,
    unattributedXP = sess.unattributedXP,
    levelCapReached = (sess.levelCapReached == true),
    xpElapsedAtCap = sess.xpElapsedAtCap,
    terminalSnapshotUnresolved = (sess.terminalSnapshotUnresolved == true),
    xpContaminated = sess.xpContaminated,
    xpRolloverUnresolved = sess.xpRolloverUnresolved,
  }
end

function State.RecordGoldFarmXPGain(explicitXPDelta, isKill)
  local sess = State.goldFarmSession
  if not sess or not sess.active then
    return false, 0
  end
  if isKill == true then
    State.RecordGoldFarmVerifiedCampKill({ expectedXP = tonumber(explicitXPDelta) })
  end
  if type(explicitXPDelta) == "number" and explicitXPDelta > 0 then
    local d = math.floor(explicitXPDelta)
    updateSessionRestedTracking(sess, true)
    sess.totalSessionXP = (tonumber(sess.totalSessionXP) or 0) + d
    sess.accumulatedXP = sess.totalSessionXP
    if isKill == true then
      -- Consume the credit just added above so explicit synthetic calls don't leave a dangling credit
      sess.pendingCampKillCredits = {}
      sess.attributableGrindXP = (tonumber(sess.attributableGrindXP) or 0) + d
    else
      sess.unattributedXP = (tonumber(sess.unattributedXP) or 0) + d
    end
    captureXPBaseline(sess)
    refreshXPContaminationFlags(sess)
    State.CheckpointGoldFarmTelemetry()
    return true, d
  end
  local rec = State.ReconcileGoldFarmXPSnapshot({ trigger = "RecordGoldFarmXPGain" })
  return rec.ok == true, tonumber(rec.delta) or 0
end

function State.OnNonFarmMoneyWindowOpened(windowKey, explicitNow, explicitCopper)
  local sess = State.goldFarmSession
  if not sess then
    return
  end
  sess.activeWindows = sess.activeWindows or {}
  local nowSec, copper = resolveNowAndMoney(explicitNow, explicitCopper)
  if sess.active then
    accrueOpenSegment(sess, nowSec, copper)
    sess.active = false
    sess.wasActiveBeforeWindow = true
    sess.segmentStartedAt = nil
    sess.segmentStartCopper = nil
  end
  sess.activeWindows[windowKey] = true
  sess.pausedForWindow = windowKey
  if sess.farmID ~= nil and (sess.wasActiveBeforeWindow or (sess.accumulatedSeconds or 0) > 0) then
    sess.contaminated = true
    sess.contaminationReason = windowKey
    sess.cleanIntervalConfirmed = false
  end
  State.CheckpointGoldFarmTelemetry()
end

function State.OnNonFarmMoneyWindowClosed(windowKey, explicitNow, explicitCopper)
  local sess = State.goldFarmSession
  if not sess then
    return
  end
  sess.activeWindows = sess.activeWindows or {}
  sess.activeWindows[windowKey] = nil
  if next(sess.activeWindows) ~= nil then
    for k in pairs(sess.activeWindows) do
      sess.pausedForWindow = k
      break
    end
    return
  end
  sess.pausedForWindow = nil
  local nowSec, copper = resolveNowAndMoney(explicitNow, explicitCopper)
  local gProg = State.GetGoldFarmProgress()
  if sess.wasActiveBeforeWindow and gProg and gProg.mode ~= "paused" then
    sess.wasActiveBeforeWindow = false
    sess.active = true
    sess.segmentStartedAt = nowSec
    sess.segmentStartCopper = copper
    captureXPBaseline(sess)
  else
    sess.wasActiveBeforeWindow = false
  end
  State.CheckpointGoldFarmTelemetry()
end

function State.MarkGoldFarmTelemetryContaminated(reason)
  local sess = State.goldFarmSession
  if not sess then
    return
  end
  sess.contaminated = true
  sess.contaminationReason = tostring(reason or "external_cashflow")
  sess.cleanIntervalConfirmed = false
  State.CheckpointGoldFarmTelemetry()
end

function State.GetGoldFarmSessionSnapshot(explicitNow, explicitCopper)
  local sess = State.goldFarmSession or {}
  local nowSec, copper = resolveNowAndMoney(explicitNow, explicitCopper)
  local campSec = tonumber(sess.campSeconds) or 0
  local travelSec = tonumber(sess.travelAndServiceSeconds) or 0
  local rxpSec = tonumber(sess.rxpUntrackedSeconds) or 0
  local totalCopper = tonumber(sess.accumulatedCopper) or 0
  local moneyAvailable = (type(copper) == "number")
  local contaminated = (sess.contaminated == true)
  local contaminationReason = sess.contaminationReason

  if sess.active then
    if type(sess.segmentStartedAt) == "number" then
      local dt = math.max(0, math.floor(nowSec - sess.segmentStartedAt))
      if sess.phase == "rxp_untracked" then
        rxpSec = rxpSec + dt
      elseif sess.phase == "travel_service" then
        travelSec = travelSec + dt
      else
        campSec = campSec + dt
      end
    end
    if type(sess.segmentStartCopper) == "number" and moneyAvailable then
      totalCopper = totalCopper + (copper - sess.segmentStartCopper)
    elseif sess.segmentStartCopper == nil and moneyAvailable then
      contaminated = true
      contaminationReason = contaminationReason or "money_previously_unavailable"
    elseif type(sess.segmentStartCopper) == "number" and not moneyAvailable then
      contaminated = true
      contaminationReason = contaminationReason or "money_unavailable"
    end
  end

  local totalSec = campSec + travelSec + rxpSec
  local phaseTimingAvailable = (sess.phase ~= "rxp_untracked") and (rxpSec == 0)
  local totalXP = math.max(0, math.floor(tonumber(sess.totalSessionXP or sess.accumulatedXP) or 0))

  return {
    sessionID = sess.sessionID,
    active = sess.active == true,
    pausedByReload = sess.pausedByReload == true,
    pausedForWindow = sess.pausedForWindow,
    farmID = sess.farmID,
    phase = sess.phase or "camp",
    campSeconds = campSec,
    travelAndServiceSeconds = travelSec,
    rxpUntrackedSeconds = rxpSec,
    phaseTimingAvailable = phaseTimingAvailable,
    elapsedSeconds = totalSec,
    netCopperDelta = totalCopper,
    accumulatedXP = totalXP,
    totalSessionXP = totalXP,
    attributableGrindXP = math.max(0, math.floor(tonumber(sess.attributableGrindXP) or 0)),
    questRewardXP = math.max(0, math.floor(tonumber(sess.questRewardXP) or 0)),
    unattributedXP = math.max(0, math.floor(tonumber(sess.unattributedXP) or 0)),
    killsObserved = math.max(0, math.floor(tonumber(sess.killsObserved) or 0)),
    levelCapReached = (sess.levelCapReached == true),
    levelCapFinalDeltaCredited = (sess.levelCapFinalDeltaCredited == true),
    xpElapsedAtCap = (sess.xpElapsedAtCap ~= nil) and math.max(0, math.floor(tonumber(sess.xpElapsedAtCap) or 0)) or nil,
    terminalSnapshotUnresolved = (sess.terminalSnapshotUnresolved == true),
    xpContaminated = (sess.xpContaminated == true),
    xpContaminationReason = sess.xpContaminationReason,
    xpRolloverUnresolved = (sess.xpRolloverUnresolved == true),
    restedIncluded = (sess.restedIncluded == true),
    restedRegimeChanged = (sess.restedRegimeChanged == true),
    currentCopper = copper,
    moneyAvailable = moneyAvailable,
    contaminated = contaminated,
    contaminationReason = contaminationReason,
    cleanIntervalConfirmed = (sess.cleanIntervalConfirmed ~= false) and not contaminated,
  }
end

State.MAX_FIELD_CAPTURES = 500

function State.GetFieldCaptures()
  if type(_G.ForeverHubDB) ~= "table" then
    _G.ForeverHubDB = {}
  end
  if type(_G.ForeverHubDB.fieldCaptures) ~= "table" then
    _G.ForeverHubDB.fieldCaptures = {}
  end
  return _G.ForeverHubDB.fieldCaptures
end

function State.RecordFieldCapture(entry)
  if type(entry) ~= "table" then
    return false, "invalid_entry"
  end
  local mapID = tonumber(entry.uiMapID)
  local x = tonumber(entry.x01)
  local y = tonumber(entry.y01)
  if not mapID or mapID <= 0 or not x or not y or x <= 0 or x >= 1 or y <= 0 or y >= 1 then
    return false, "invalid_coordinates"
  end
  local rx = math.floor(x * 10000 + 0.5) / 10000
  local ry = math.floor(y * 10000 + 0.5) / 10000
  local list = State.GetFieldCaptures()
  while #list >= State.MAX_FIELD_CAPTURES do
    table.remove(list, 1)
  end
  local nowSec = 0
  if ns.Compat and type(ns.Compat.NowSeconds) == "function" then
    nowSec = math.floor(tonumber(ns.Compat.NowSeconds()) or 0)
  end
  local rec = {
    kind = tostring(entry.kind or "event"),
    questID = tonumber(entry.questID),
    questTitle = type(entry.questTitle) == "string" and entry.questTitle ~= "" and entry.questTitle or nil,
    objectiveIndex = tonumber(entry.objectiveIndex),
    objectiveText = type(entry.objectiveText) == "string" and entry.objectiveText ~= "" and entry.objectiveText or nil,
    note = type(entry.note) == "string" and entry.note ~= "" and entry.note or nil,
    npcID = tonumber(entry.npcID),
    npcName = type(entry.npcName) == "string" and entry.npcName ~= "" and entry.npcName or nil,
    uiMapID = mapID,
    x01 = rx,
    y01 = ry,
    recordedAt = nowSec,
  }
  table.insert(list, rec)
  return true, rec
end

-- ============================================================================
-- Stage 6A.3 / 6B.1 / 6C State Stores:
--   1. User-Protected Item IDs (`P0.6`)
--   2. Locale-Safe Profession Snapshot Store (`P1.B`)
--   3. Dual-Clock Account Cooldown Persistence (`P1.E` — "Expected ready — last observed ...")
--   4. Bounded Opt-In Candidate-Only Discovery Ring (`Stage 6C`)
-- ============================================================================

State.DISCOVERY_MAX_OFFERS = 64
State.DISCOVERY_MAX_RECIPES = 64
State.DISCOVERY_MAX_STRING_BYTES = 128
State.DISCOVERY_MAX_REAGENTS = 12
State.DISCOVERY_MAX_SERIALIZED_BYTES = 65536
State.DISCOVERY_EXPIRY_SECONDS = 7 * 86400

function State.IsUserProtectedItem(itemID)
  local id = tonumber(itemID)
  if not id or id <= 0 then
    return false
  end
  local db = State.GetDB()
  return type(db.protectedItemIDs) == "table" and db.protectedItemIDs[math.floor(id)] == true
end

function State.SetUserProtectedItem(itemID, isProtected)
  local id = tonumber(itemID)
  if not id or id <= 0 then
    return false
  end
  local db = State.GetDB()
  db.protectedItemIDs = type(db.protectedItemIDs) == "table" and db.protectedItemIDs or {}
  if isProtected == true then
    db.protectedItemIDs[math.floor(id)] = true
  else
    db.protectedItemIDs[math.floor(id)] = nil
  end
  State.BumpInventoryRevision()
  return true
end

function State.UpdateProfessionSnapshot(snap)
  if type(snap) ~= "table" then
    return
  end
  if snap.isLinkedView == true or snap.snapshotStatus == "LINKED_VIEW_IGNORED" then
    -- Linked/guild views NEVER overwrite the character's learned profession state!
    return
  end
  State.professionSnapshot = snap
  if snap.snapshotStatus == "COMPLETE" and type(snap.learnedSkills) == "table" then
    State.learnedProfessionSkills = snap.learnedSkills
    local db = State.GetDB()
    local _, _, ownerKey = ns.Compat.GetCharacterKey()
    db.characterProfessions = type(db.characterProfessions) == "table" and db.characterProfessions or {}
    db.characterProfessions[ownerKey] = {
      ownerKey = ownerKey,
      learnedSkills = snap.learnedSkills,
      baseRanks = snap.baseRanks,
      effectiveModifiers = snap.effectiveModifiers,
      maxRanks = snap.maxRanks,
      observedAt = tonumber(snap.observedAt) or 0,
    }
  else
    State.learnedProfessionSkills = nil
  end
end

function State.GetProfessionSnapshot()
  if type(State.professionSnapshot) == "table" then
    return State.professionSnapshot
  end
  if ns.Compat and type(ns.Compat.CaptureProfessionSnapshot) == "function" then
    local captured = ns.Compat.CaptureProfessionSnapshot()
    State.UpdateProfessionSnapshot(captured)
    return State.professionSnapshot or captured
  end
  return {
    snapshotStatus = "PENDING",
    learnedSkills = {},
    baseRanks = {},
    effectiveModifiers = {},
    maxRanks = {},
    observedAt = 0,
  }
end

function State.RecordObservedCooldown(cooldownID, normalizedObs, explicitCharKey)
  if type(cooldownID) ~= "string" or cooldownID == "" or type(normalizedObs) ~= "table" then
    return false, "invalid_cooldown_observation"
  end
  cooldownID = string.lower(cooldownID)
  if normalizedObs.status ~= "READY_OBSERVED" and normalizedObs.status ~= "ON_COOLDOWN_OBSERVED" then
    return false, normalizedObs.status or "unobserved_cooldown"
  end
  local readyAt = tonumber(normalizedObs.readyAtServerEpoch)
  local obsAt = tonumber(normalizedObs.observedAtServerEpoch)
  if not readyAt or readyAt <= 0 or not obsAt or obsAt <= 0 then
    return false, "missing_server_epoch"
  end

  local _, _, curOwnerKey = ns.Compat.GetCharacterKey()
  local ownerKey = (type(explicitCharKey) == "string" and explicitCharKey ~= "") and explicitCharKey or curOwnerKey
  local db = State.GetDB()
  db.accountCooldowns = type(db.accountCooldowns) == "table" and db.accountCooldowns or {}
  local charSlot = type(db.accountCooldowns[ownerKey]) == "table" and db.accountCooldowns[ownerKey] or {
    characterKey = ownerKey,
    cooldownReadyAtByID = {},
    observedAtByID = {},
    lastObservedAt = 0,
  }
  charSlot.cooldownReadyAtByID = type(charSlot.cooldownReadyAtByID) == "table" and charSlot.cooldownReadyAtByID or {}
  charSlot.observedAtByID = type(charSlot.observedAtByID) == "table" and charSlot.observedAtByID or {}

  -- Conflict-safe monotonic timestamp merge: never overwrite a newer observation with an older timestamp!
  local prevObs = tonumber(charSlot.observedAtByID[cooldownID]) or 0
  if obsAt >= prevObs then
    charSlot.cooldownReadyAtByID[cooldownID] = math.floor(readyAt)
    charSlot.observedAtByID[cooldownID] = math.floor(obsAt)
    charSlot.lastObservedAt = math.max(tonumber(charSlot.lastObservedAt) or 0, math.floor(obsAt))
  end
  db.accountCooldowns[ownerKey] = charSlot

  State.sessionObservedCooldowns = State.sessionObservedCooldowns or {}
  if ownerKey == curOwnerKey then
    State.sessionObservedCooldowns[cooldownID] = true
  end
  return true, charSlot
end

function State.GetAccountCooldownRecords()
  local db = State.GetDB()
  local _, _, curOwnerKey = ns.Compat.GetCharacterKey()
  local out = {}
  local cdMap = type(db.accountCooldowns) == "table" and db.accountCooldowns or {}
  local profMap = type(db.characterProfessions) == "table" and db.characterProfessions or {}

  local seenChars = {}
  for ownerKey in pairs(cdMap) do
    seenChars[ownerKey] = true
  end
  for ownerKey in pairs(profMap) do
    seenChars[ownerKey] = true
  end

  for ownerKey in pairs(seenChars) do
    local cEntry = cdMap[ownerKey] or {}
    local pEntry = profMap[ownerKey] or {}
    local isCurrent = (ownerKey == curOwnerKey)
    local hasSessionObs = false
    if isCurrent and type(State.sessionObservedCooldowns) == "table" and next(State.sessionObservedCooldowns) ~= nil then
      hasSessionObs = true
    end
    table.insert(out, {
      characterKey = ownerKey,
      isCurrentCharacter = isCurrent,
      observedNow = isCurrent and hasSessionObs,
      lastObservedAt = tonumber(cEntry.lastObservedAt) or tonumber(pEntry.observedAt),
      learnedSkills = isCurrent and State.learnedProfessionSkills or pEntry.learnedSkills or {},
      cooldownReadyAtByID = cEntry.cooldownReadyAtByID or {},
    })
  end

  table.sort(out, function(a, b)
    return tostring(a.characterKey) < tostring(b.characterKey)
  end)
  return out
end

-- Stage 6C Bounded Opt-In Candidate-Only Discovery Collector:
local function estimateDiscoveryRecordBytes(rec)
  if type(rec) ~= "table" then
    return 16
  end
  local total = 64
  for k, v in pairs(rec) do
    total = total + #tostring(k)
    local tv = type(v)
    if tv == "string" then
      total = total + #v + 4
    elseif tv == "number" or tv == "boolean" then
      total = total + 12
    elseif tv == "table" then
      for _, sub in ipairs(v) do
        total = total + 40 + (type(sub) == "table" and sub.itemKey and #tostring(sub.itemKey) or 8)
      end
    end
  end
  return total
end

function State.EnsureDiscoveryCollectorInitialized()
  local db = State.GetDB()
  if type(db.discoveryCollector) ~= "table" or db.discoveryCollector.schemaVersion ~= 1 then
    db.discoveryCollector = {
      schemaVersion = 1,
      optInEnabled = false,
      merchantOffers = {},
      recipes = {},
      estimatedBytes = 0,
      stats = {
        droppedByCapCount = 0,
        droppedByByteBudgetCount = 0,
        expiredPrunedCount = 0,
        deduplicatedUpdateCount = 0,
      },
    }
  end
  local dc = db.discoveryCollector
  dc.merchantOffers = type(dc.merchantOffers) == "table" and dc.merchantOffers or {}
  dc.recipes = type(dc.recipes) == "table" and dc.recipes or {}
  dc.stats = type(dc.stats) == "table" and dc.stats or {
    droppedByCapCount = 0,
    droppedByByteBudgetCount = 0,
    expiredPrunedCount = 0,
    deduplicatedUpdateCount = 0,
  }
  return dc
end

function State.SetDiscoveryOptIn(enabled)
  local dc = State.EnsureDiscoveryCollectorInitialized()
  dc.optInEnabled = (enabled == true)
  return dc.optInEnabled
end

function State.IsDiscoveryOptInEnabled()
  local dc = State.EnsureDiscoveryCollectorInitialized()
  return dc.optInEnabled == true
end

local function clampDiscoveryString(s)
  local clean = tostring(s or "")
  if #clean > State.DISCOVERY_MAX_STRING_BYTES then
    return string.sub(clean, 1, State.DISCOVERY_MAX_STRING_BYTES)
  end
  return clean
end

function State.RecordDiscoveryCandidate(candidateKind, rawRecord, nowEpochOverride)
  local dc = State.EnsureDiscoveryCollectorInitialized()
  if dc.optInEnabled ~= true then
    return false, "discovery_opt_in_disabled"
  end
  if type(rawRecord) ~= "table" then
    return false, "invalid_candidate_record"
  end

  local clocks = ns.Compat and ns.Compat.GetDualClockNow and ns.Compat.GetDualClockNow() or {}
  local nowEpoch = tonumber(nowEpochOverride) or tonumber(clocks.serverEpoch) or 0
  if nowEpoch <= 0 then
    return false, "server_clock_unavailable"
  end

  local targetList
  local maxCap
  local subjectKey = clampDiscoveryString(rawRecord.subjectKey)
  if subjectKey == "" then
    return false, "missing_subject_key"
  end

  local cleanRec = {
    subjectKey = subjectKey,
    observedAtEpoch = math.floor(nowEpoch),
    promotionState = "RAW_USER_REPORTED",
    executableEligible = false,
  }

  if candidateKind == "merchant_offer" then
    targetList = dc.merchantOffers
    maxCap = State.DISCOVERY_MAX_OFFERS
    cleanRec.npcType = clampDiscoveryString(rawRecord.npcType or "creature")
    cleanRec.npcID = math.max(1, math.floor(tonumber(rawRecord.npcID) or 0))
    cleanRec.uiMapID = math.max(0, math.floor(tonumber(rawRecord.uiMapID) or 0))
    cleanRec.itemKey = clampDiscoveryString(rawRecord.itemKey)
    cleanRec.bundleQuantity = math.max(1, math.floor(tonumber(rawRecord.bundleQuantity) or 1))
    cleanRec.bundlePriceCopper = math.max(0, math.floor(tonumber(rawRecord.bundlePriceCopper) or 0))
    cleanRec.stockQuantity = (rawRecord.stockQuantity ~= nil) and math.floor(tonumber(rawRecord.stockQuantity) or 0) or nil
    cleanRec.stockMode = clampDiscoveryString(rawRecord.stockMode or "UNKNOWN")
    cleanRec.bindingStatus = clampDiscoveryString(rawRecord.bindingStatus or "UNKNOWN")
    cleanRec.metadataComplete = (rawRecord.metadataComplete == true)
    cleanRec.extendedCost = (rawRecord.extendedCost == true)
    cleanRec.purchaseEligible = (rawRecord.purchaseEligible == true)
    cleanRec.standingOrDiscountContext = clampDiscoveryString(rawRecord.standingOrDiscountContext or "unknown")
    cleanRec.phaseOrAccessContext = clampDiscoveryString(rawRecord.phaseOrAccessContext or "unknown")
  elseif candidateKind == "recipe" then
    targetList = dc.recipes
    maxCap = State.DISCOVERY_MAX_RECIPES
    local rawReagents = type(rawRecord.reagents) == "table" and rawRecord.reagents or {}
    if #rawReagents == 0 or #rawReagents > State.DISCOVERY_MAX_REAGENTS then
      return false, "invalid_reagent_count"
    end
    local cleanReagents = {}
    for _, rg in ipairs(rawReagents) do
      if type(rg) == "table" and type(rg.itemKey) == "string" then
        table.insert(cleanReagents, {
          itemKey = clampDiscoveryString(rg.itemKey),
          quantity = math.max(1, math.floor(tonumber(rg.quantity) or 1)),
        })
      end
    end
    if #cleanReagents == 0 then
      return false, "empty_clean_reagents"
    end
    cleanRec.skillLineID = math.max(1, math.floor(tonumber(rawRecord.skillLineID) or 0))
    cleanRec.spellOrRecipeID = math.max(1, math.floor(tonumber(rawRecord.spellOrRecipeID) or 0))
    cleanRec.viewContext = clampDiscoveryString(rawRecord.viewContext or "own")
    cleanRec.learnedOrAccessStatus = clampDiscoveryString(rawRecord.learnedOrAccessStatus or "learned")
    cleanRec.outputItemKey = clampDiscoveryString(rawRecord.outputItemKey)
    cleanRec.minMade = math.max(1, math.floor(tonumber(rawRecord.minMade) or 1))
    cleanRec.maxMade = math.max(cleanRec.minMade, math.floor(tonumber(rawRecord.maxMade) or cleanRec.minMade))
    cleanRec.reagents = cleanReagents
    cleanRec.stationOrToolReq = clampDiscoveryString(rawRecord.stationOrToolReq or "none")
    cleanRec.metadataComplete = (rawRecord.metadataComplete == true)
  else
    return false, "unsupported_candidate_kind"
  end

  -- Prune expired entries incrementally (no heavy logout rebuild!):
  local cutoff = nowEpoch - State.DISCOVERY_EXPIRY_SECONDS
  for _, listRef in ipairs({ dc.merchantOffers, dc.recipes }) do
    local idx = 1
    while idx <= #listRef do
      local existing = listRef[idx]
      if type(existing) ~= "table" or (tonumber(existing.observedAtEpoch) or 0) < cutoff then
        table.remove(listRef, idx)
        dc.stats.expiredPrunedCount = (dc.stats.expiredPrunedCount or 0) + 1
      else
        idx = idx + 1
      end
    end
  end

  -- Deduplicate by subjectKey in place:
  for idx, existing in ipairs(targetList) do
    if existing.subjectKey == subjectKey then
      targetList[idx] = cleanRec
      dc.stats.deduplicatedUpdateCount = (dc.stats.deduplicatedUpdateCount or 0) + 1
      return true, cleanRec
    end
  end

  -- Enforce ring cap (`maxCap`):
  while #targetList >= maxCap do
    table.remove(targetList, 1)
    dc.stats.droppedByCapCount = (dc.stats.droppedByCapCount or 0) + 1
  end

  -- Enforce total serialized byte budget (`64 KiB`):
  local totalBytes = estimateDiscoveryRecordBytes(cleanRec)
  for _, o in ipairs(dc.merchantOffers) do
    totalBytes = totalBytes + estimateDiscoveryRecordBytes(o)
  end
  for _, r in ipairs(dc.recipes) do
    totalBytes = totalBytes + estimateDiscoveryRecordBytes(r)
  end
  while totalBytes > State.DISCOVERY_MAX_SERIALIZED_BYTES and (#dc.merchantOffers > 0 or #dc.recipes > 0) do
    if #dc.merchantOffers >= #dc.recipes and #dc.merchantOffers > 0 then
      local dropped = table.remove(dc.merchantOffers, 1)
      totalBytes = totalBytes - estimateDiscoveryRecordBytes(dropped)
    elseif #dc.recipes > 0 then
      local dropped = table.remove(dc.recipes, 1)
      totalBytes = totalBytes - estimateDiscoveryRecordBytes(dropped)
    else
      break
    end
    dc.stats.droppedByByteBudgetCount = (dc.stats.droppedByByteBudgetCount or 0) + 1
  end

  if totalBytes > State.DISCOVERY_MAX_SERIALIZED_BYTES then
    dc.stats.droppedByByteBudgetCount = (dc.stats.droppedByByteBudgetCount or 0) + 1
    return false, "exceeds_discovery_byte_budget"
  end

  table.insert(targetList, cleanRec)
  dc.estimatedBytes = totalBytes
  return true, cleanRec
end

-- ============================================================================
-- Stage 7A / 7B.1 State Stores (Astra Round-5 Remediated):
--   1. Isolated Open-AH Session & Venue Identity (`P0-2`, `P0-3` — `UNKNOWN_AH` never pooled)
--   2. Separated Commission Rule vs. Deposit Schedule Evidence (`P0-2`)
--   3. Full-Identity Deposit Quote Cache & Tested Tooltip Adapter (`P0-3`)
--   4. Strictly Complete Own-Character `craft` Reservation Goals (`P0-8`, `7B.1`)
-- ============================================================================

State.ahSessionSeq = State.ahSessionSeq or 0
State.currentAhSession = State.currentAhSession or nil
State.commissionRuleRevision = State.commissionRuleRevision or 0
State.depositRuleRevision = State.depositRuleRevision or 0
State.openAhDepositQuotesByCompositeKey = State.openAhDepositQuotesByCompositeKey or {}
State.openAhDepositQuoteOrder = State.openAhDepositQuoteOrder or {}
State.MAX_OPEN_AH_DEPOSIT_CACHE = 128

local function resolveCurrentClientBuild(explicitBuild)
  if type(explicitBuild) == "string" and explicitBuild ~= "" then
    return explicitBuild
  end
  if type(_G.GetBuildInfo) == "function" then
    local ok, ver, buildNum = pcall(_G.GetBuildInfo)
    if ok and (type(buildNum) == "string" or type(buildNum) == "number") then
      local bStr = tostring(buildNum)
      if string.find(bStr, "%.") then
        return bStr
      end
      if type(ver) == "string" and ver ~= "" then
        return string.format("%s.%s", ver, bStr)
      end
      return bStr
    end
  end
  return "1.60.1.70938"
end

function State.BeginOpenAhSession(venueInfo)
  venueInfo = type(venueInfo) == "table" and venueInfo or {}
  State.ahSessionSeq = (tonumber(State.ahSessionSeq) or 0) + 1
  local sessionID = State.ahSessionSeq
  local verified = (venueInfo.verified == true or venueInfo.venueVerified == true)
    and type(venueInfo.venueIdentity) == "string"
    and venueInfo.venueIdentity ~= ""
    and venueInfo.venueIdentity ~= "UNKNOWN_AH"

  local venueIdentity = verified and venueInfo.venueIdentity or nil
  -- Astra P0-3: `UNKNOWN_AH` is an absence of identity, NEVER a shared pool across sessions!
  local venueSessionScope = verified and venueIdentity or string.format("UNKNOWN_AH:session:%d", sessionID)

  State.currentAhSession = {
    sessionID = sessionID,
    open = true,
    build = resolveCurrentClientBuild(venueInfo.build or venueInfo.clientBuild),
    venueClassified = verified,
    venueIdentity = venueIdentity,
    venueSessionScope = venueSessionScope,
    venueEvidenceSource = verified and tostring(venueInfo.evidenceSource or "verified_venue") or "unclassified",
    selectionRevision = 1,
  }
  State.ahOpen = true
  return State.currentAhSession
end

function State.UpdateOpenAhVenueIdentity(venueInfo)
  if type(State.currentAhSession) ~= "table" or State.currentAhSession.open ~= true then
    return State.BeginOpenAhSession(venueInfo)
  end
  venueInfo = type(venueInfo) == "table" and venueInfo or {}
  local verified = (venueInfo.verified == true or venueInfo.venueVerified == true)
    and type(venueInfo.venueIdentity) == "string"
    and venueInfo.venueIdentity ~= ""
    and venueInfo.venueIdentity ~= "UNKNOWN_AH"
  local nextScope = verified and venueInfo.venueIdentity or string.format("UNKNOWN_AH:session:%d", State.currentAhSession.sessionID)
  if nextScope ~= State.currentAhSession.venueSessionScope then
    State.currentAhSession.venueClassified = verified
    State.currentAhSession.venueIdentity = verified and venueInfo.venueIdentity or nil
    State.currentAhSession.venueSessionScope = nextScope
    State.currentAhSession.venueEvidenceSource = verified and tostring(venueInfo.evidenceSource or "verified_venue") or "unclassified"
    State.currentAhSession.selectionRevision = (State.currentAhSession.selectionRevision or 1) + 1
  end
  return State.currentAhSession
end

function State.BumpAhSelectionRevision()
  if type(State.currentAhSession) == "table" and State.currentAhSession.open == true then
    State.currentAhSession.selectionRevision = (tonumber(State.currentAhSession.selectionRevision) or 1) + 1
    return State.currentAhSession.selectionRevision
  end
  return 0
end

function State.EndOpenAhSession()
  local ended = State.currentAhSession
  if type(ended) == "table" then
    local closedScope = ended.venueSessionScope
    -- Purge any session-isolated UNKNOWN_AH quotes on close so they never leak!
    if type(closedScope) == "string" and string.sub(closedScope, 1, 11) == "UNKNOWN_AH:" then
      for k, rec in pairs(State.openAhDepositQuotesByCompositeKey or {}) do
        if type(rec) == "table" and rec.venueSessionScope == closedScope then
          State.openAhDepositQuotesByCompositeKey[k] = nil
        end
      end
    end
    ended.open = false
  end
  State.currentAhSession = nil
  State.ahOpen = false
end

function State.EnsureSeparatedMarketRuleStores()
  local db = State.GetDB()
  db.verifiedCommissionRules = type(db.verifiedCommissionRules) == "table" and db.verifiedCommissionRules or {}
  db.verifiedDepositRules = type(db.verifiedDepositRules) == "table" and db.verifiedDepositRules or {}
  return db.verifiedCommissionRules, db.verifiedDepositRules
end

function State.SetVerifiedCommissionRule(venueIdentity, ruleRecord)
  if type(venueIdentity) ~= "string" or venueIdentity == "" or venueIdentity == "UNKNOWN_AH" or string.sub(venueIdentity, 1, 11) == "UNKNOWN_AH:" then
    return false, "unclassified_venue_cannot_own_commission_rule"
  end
  if type(ruleRecord) ~= "table" then
    return false, "invalid_commission_rule_record"
  end
  local cutBps = tonumber(ruleRecord.cutBps)
  local rMode = tostring(ruleRecord.roundingMode or "")
  local obsBuild = tostring(ruleRecord.observedBuild or "")
  if not cutBps or cutBps <= 0 or cutBps > 10000 or math.floor(cutBps) ~= cutBps then
    return false, "invalid_commission_cut_bps"
  end
  if rMode ~= "floor" and rMode ~= "half_up" then
    -- Astra P0-2: `both_agree` or `unknown` never establishes an authoritative rounding rule!
    return false, "unresolved_commission_rounding_mode"
  end
  if obsBuild == "" then
    return false, "missing_observed_build"
  end
  if type(ruleRecord.supportingInvoiceIds) ~= "table" or #ruleRecord.supportingInvoiceIds == 0 then
    return false, "missing_supporting_invoice_provenance"
  end
  if ruleRecord.salePostBuildVerified ~= true then
    return false, "sale_build_provenance_unverified"
  end

  local commMap = State.EnsureSeparatedMarketRuleStores()
  State.commissionRuleRevision = (tonumber(State.commissionRuleRevision) or 0) + 1
  local stored = {
    verified = true,
    venueVerified = true,
    venueKey = venueIdentity,
    venueIdentity = venueIdentity,
    cutBps = cutBps,
    commissionNumerator = cutBps,
    commissionDenominator = 10000,
    roundingMode = rMode,
    clientBuild = obsBuild,
    observedBuild = obsBuild,
    verificationStatus = "VERIFIED",
    salePostBuildVerified = true,
    supportingInvoiceIds = ruleRecord.supportingInvoiceIds,
    revision = State.commissionRuleRevision,
  }
  commMap[venueIdentity] = stored
  return true, stored
end

function State.GetVerifiedCommissionRule(venueIdentity, currentBuildOverride)
  if type(venueIdentity) ~= "string" or venueIdentity == "" or string.sub(venueIdentity, 1, 11) == "UNKNOWN_AH:" then
    return nil, "venue_unclassified"
  end
  local commMap = State.EnsureSeparatedMarketRuleStores()
  local rec = commMap[venueIdentity]
  if type(rec) ~= "table" then
    return nil, "commission_rule_missing"
  end
  local curBuild = resolveCurrentClientBuild(currentBuildOverride)
  if rec.observedBuild ~= curBuild then
    return nil, "stale_build_commission_rule"
  end
  if rec.verificationStatus ~= "VERIFIED" or (rec.roundingMode ~= "floor" and rec.roundingMode ~= "half_up") then
    return nil, "commission_rule_unverified"
  end
  return rec, nil
end

function State.SetVerifiedDepositRule(venueIdentity, depositRecord)
  if type(venueIdentity) ~= "string" or venueIdentity == "" or venueIdentity == "UNKNOWN_AH" or string.sub(venueIdentity, 1, 11) == "UNKNOWN_AH:" then
    return false, "unclassified_venue_cannot_own_deposit_rule"
  end
  if type(depositRecord) ~= "table" then
    return false, "invalid_deposit_rule_record"
  end
  local minDep = tonumber(depositRecord.minDepositCopper)
  local obsBuild = tostring(depositRecord.observedBuild or "")
  if not minDep or minDep < 0 or math.floor(minDep) ~= minDep or obsBuild == "" then
    return false, "invalid_deposit_rule_fields"
  end
  if type(depositRecord.durationSchedule) ~= "table" or type(depositRecord.supportingDepositCaptureIds) ~= "table" or #depositRecord.supportingDepositCaptureIds == 0 then
    return false, "missing_deposit_schedule_or_captures"
  end
  local _, depMap = State.EnsureSeparatedMarketRuleStores()
  State.depositRuleRevision = (tonumber(State.depositRuleRevision) or 0) + 1
  local stored = {
    venueIdentity = venueIdentity,
    minDepositCopper = minDep,
    durationSchedule = depositRecord.durationSchedule,
    batchSemantics = tostring(depositRecord.batchSemantics or "UNKNOWN"),
    observedBuild = obsBuild,
    verificationStatus = "VERIFIED",
    supportingDepositCaptureIds = depositRecord.supportingDepositCaptureIds,
    revision = State.depositRuleRevision,
  }
  depMap[venueIdentity] = stored
  return true, stored
end

function State.GetVerifiedDepositRule(venueIdentity, currentBuildOverride)
  if type(venueIdentity) ~= "string" or venueIdentity == "" or string.sub(venueIdentity, 1, 11) == "UNKNOWN_AH:" then
    return nil, "venue_unclassified"
  end
  local _, depMap = State.EnsureSeparatedMarketRuleStores()
  local rec = depMap[venueIdentity]
  if type(rec) ~= "table" then
    return nil, "deposit_rule_missing"
  end
  local curBuild = resolveCurrentClientBuild(currentBuildOverride)
  if rec.observedBuild ~= curBuild then
    return nil, "stale_build_deposit_rule"
  end
  return rec, nil
end

function State.GetActiveVerifiedCommissionRuleForTooltip(currentBuildOverride)
  if type(State.currentAhSession) == "table" and State.currentAhSession.open == true then
    if State.currentAhSession.venueClassified == true and State.currentAhSession.venueIdentity then
      local rule = State.GetVerifiedCommissionRule(State.currentAhSession.venueIdentity, currentBuildOverride or State.currentAhSession.build)
      return rule
    end
    -- Open unclassified AH session MUST NOT inherit another venue's commission rule!
    return nil
  end
  -- Backward compatibility for direct unit-test injection (`State.activeVerifiedFeeRule`):
  if type(State.activeVerifiedFeeRule) == "table" and (State.activeVerifiedFeeRule.verified == true or State.activeVerifiedFeeRule.verificationStatus == "VERIFIED") then
    local curBuild = resolveCurrentClientBuild(currentBuildOverride)
    local rb = State.activeVerifiedFeeRule.observedBuild or State.activeVerifiedFeeRule.clientBuild
    if rb == nil or rb == curBuild then
      return State.activeVerifiedFeeRule
    end
  end
  return nil
end

function State.BuildDepositQuoteCompositeKey(q)
  if type(q) ~= "table" then
    return nil
  end
  local build = tostring(q.build or "")
  local venueScope = tostring(q.venueSessionScope or "")
  local selRev = tonumber(q.selectionRevision)
  local itemKey = tostring(q.itemKey or "")
  local durIdx = tonumber(q.durationIndex)
  local stackSize = tonumber(q.stackSize)
  local numStacks = tonumber(q.numStacks)
  if build == "" or venueScope == "" or not selRev or selRev < 1 or itemKey == ""
    or not durIdx or (durIdx ~= 1 and durIdx ~= 2 and durIdx ~= 3)
    or not stackSize or stackSize < 1 or math.floor(stackSize) ~= stackSize
    or not numStacks or numStacks < 1 or math.floor(numStacks) ~= numStacks
  then
    return nil
  end
  local bidPart = (q.startingBid ~= nil) and tostring(math.floor(tonumber(q.startingBid) or 0)) or "nil"
  local boPart = (q.buyoutPerStack ~= nil) and tostring(math.floor(tonumber(q.buyoutPerStack) or 0)) or "nil"
  return string.format(
    "%s|%s|%d|%s|%d|%d|%d|%s|%s",
    build,
    venueScope,
    math.floor(selRev),
    itemKey,
    math.floor(durIdx),
    math.floor(stackSize),
    math.floor(numStacks),
    bidPart,
    boPart
  )
end

function State.RecordOpenAhDepositQuote(quote)
  if type(quote) ~= "table" then
    return false, "invalid_deposit_quote"
  end
  local sess = State.currentAhSession
  if type(sess) ~= "table" or sess.open ~= true then
    return false, "auction_house_not_open"
  end
  local selRev = tonumber(quote.selectionRevision)
  if not selRev or math.floor(selRev) ~= sess.selectionRevision then
    -- Astra P0-3: Late or stale callback must NEVER attach to a replacement selection!
    return false, "stale_selection_revision"
  end
  local depCopper = tonumber(quote.quotedDepositCopper)
  if not depCopper or depCopper < 0 or math.floor(depCopper) ~= depCopper then
    return false, "invalid_quoted_deposit_copper"
  end
  if ns.Domain and ns.Domain.MarketIdentity and type(ns.Domain.MarketIdentity.IsCanonicalItemKey) == "function" then
    if not ns.Domain.MarketIdentity.IsCanonicalItemKey(quote.itemKey) then
      return false, "non_canonical_item_key"
    end
  elseif type(quote.itemKey) ~= "string" or quote.itemKey == "" then
    return false, "missing_item_key"
  end

  local normalized = {
    build = sess.build,
    venueClassified = sess.venueClassified,
    venueIdentity = sess.venueIdentity,
    venueSessionScope = sess.venueSessionScope,
    selectionRevision = sess.selectionRevision,
    itemKey = quote.itemKey,
    durationIndex = tonumber(quote.durationIndex),
    durationHoursLabel = (quote.durationIndex == 1 and 2) or (quote.durationIndex == 2 and 8) or (quote.durationIndex == 3 and 24) or nil,
    stackSize = math.floor(tonumber(quote.stackSize) or 0),
    numStacks = math.floor(tonumber(quote.numStacks) or 0),
    startingBid = (quote.startingBid ~= nil) and math.floor(tonumber(quote.startingBid) or 0) or nil,
    buyoutPerStack = (quote.buyoutPerStack ~= nil) and math.floor(tonumber(quote.buyoutPerStack) or 0) or nil,
    quotedDepositCopper = math.floor(depCopper),
    batchSemantics = tostring(quote.batchSemantics or "UNVERIFIED_SEMANTICS"),
    observedAtEpoch = tonumber(quote.observedAtEpoch) or 0,
  }
  local compKey = State.BuildDepositQuoteCompositeKey(normalized)
  if not compKey then
    return false, "incomplete_deposit_quote_identity"
  end

  if State.openAhDepositQuotesByCompositeKey[compKey] == nil then
    table.insert(State.openAhDepositQuoteOrder, compKey)
    while #State.openAhDepositQuoteOrder > State.MAX_OPEN_AH_DEPOSIT_CACHE do
      local oldest = table.remove(State.openAhDepositQuoteOrder, 1)
      if oldest then
        State.openAhDepositQuotesByCompositeKey[oldest] = nil
      end
    end
  end
  State.openAhDepositQuotesByCompositeKey[compKey] = normalized
  return true, normalized, compKey
end

-- Explicit, tested adapter for `Tooltips.lua` (`P0-3`):
-- Maps `quotedDepositCopper` -> `depositCopper` ONLY when exact variant `itemKey`, `stackSize`,
-- `numStacks == 1`, active `selectionRevision`, `venueSessionScope`, and `build` match!
-- Never falls back from variant keys to `i1:base:<itemID>`.
function State.ResolveTooltipOpenAhDepositQuote(params)
  params = type(params) == "table" and params or {}
  local itemKey = params.itemKey
  local reqStack = math.max(1, math.floor(tonumber(params.stackSize) or 1))
  local prefDurationIdx = tonumber(params.durationIndex) or 3

  if type(State.currentAhSession) == "table" and State.currentAhSession.open == true then
    if type(itemKey) ~= "string" or itemKey == "" then
      return nil, "missing_exact_item_key"
    end
    local sess = State.currentAhSession
    local best = nil
    for _, rec in pairs(State.openAhDepositQuotesByCompositeKey or {}) do
      if type(rec) == "table"
        and rec.build == sess.build
        and rec.venueSessionScope == sess.venueSessionScope
        and rec.selectionRevision == sess.selectionRevision
        and rec.itemKey == itemKey
        and rec.stackSize == reqStack
        and rec.numStacks == 1
      then
        if rec.durationIndex == prefDurationIdx then
          best = rec
          break
        elseif best == nil then
          best = rec
        end
      end
    end
    if best then
      return {
        depositCopper = best.quotedDepositCopper,
        quotedDepositCopper = best.quotedDepositCopper,
        durationIndex = best.durationIndex,
        durationHoursLabel = best.durationHoursLabel,
        stackSize = best.stackSize,
        venueSessionScope = best.venueSessionScope,
        selectionRevision = best.selectionRevision,
      }, nil
    end
    return nil, "no_matching_selection_quote"
  end

  -- Backward-compatible path ONLY for explicit Stage 6 test fixtures (`lastOpenAhDepositQuoteByItemKey` when no `currentAhSession` is open):
  if type(State.lastOpenAhDepositQuoteByItemKey) == "table" then
    local depMap = State.lastOpenAhDepositQuoteByItemKey
    local rec = (type(itemKey) == "string" and depMap[itemKey]) or nil
    if rec == nil and params.allowBaseTestFallback == true and tonumber(params.itemID) then
      local baseK = string.format("i1:base:%d", math.floor(tonumber(params.itemID)))
      rec = depMap[baseK] or depMap[tonumber(params.itemID)]
    end
    if type(rec) == "table" then
      local dc = tonumber(rec.depositCopper ~= nil and rec.depositCopper or rec.quotedDepositCopper)
      if dc and dc > 0 then
        return {
          depositCopper = math.floor(dc),
          quotedDepositCopper = math.floor(dc),
          stackSize = reqStack,
          venueKey = rec.venueKey,
        }, nil
      end
    elseif type(rec) == "number" and rec > 0 then
      return { depositCopper = math.floor(rec), quotedDepositCopper = math.floor(rec), stackSize = reqStack }, nil
    end
  end
  return nil, "ah_closed_or_no_quote"
end

function State.BuildCraftGoalKey(ownerKey, skillLineID, spellOrRecipeID)
  return string.format(
    "craft:%s:%d:%d",
    tostring(ownerKey or "unknown"),
    math.floor(tonumber(skillLineID) or 0),
    math.floor(tonumber(spellOrRecipeID) or 0)
  )
end

-- Creates or updates a strictly complete own-character `craft` reservation (`P0-8`, `7B.1`).
-- Fails closed on linked views, missing numeric spell/skillLine IDs, truncated/incomplete reagents,
-- defaulted reagent quantities, or empty consumed reagent lists.
function State.ReserveCraftGoal(craftSpec, explicitExecutions)
  if type(craftSpec) ~= "table" then
    return false, "invalid_craft_spec"
  end
  if craftSpec.isLinked == true or craftSpec.viewContext ~= "own" then
    return false, "linked_or_foreign_tradeskill_rejected"
  end
  if craftSpec.learnedRecipeVerified ~= true then
    return false, "recipe_not_verified_learned"
  end
  if craftSpec.scanComplete ~= true or craftSpec.reagentsComplete ~= true or craftSpec.reagentsTruncated == true then
    return false, "incomplete_or_truncated_recipe_scan"
  end
  local skillLineID = tonumber(craftSpec.skillLineID)
  local spellOrRecipeID = tonumber(craftSpec.spellOrRecipeID or craftSpec.spellID)
  if not skillLineID or skillLineID <= 0 or math.floor(skillLineID) ~= skillLineID then
    return false, "missing_verified_skill_line_id"
  end
  if craftSpec.recipeIdentityStatus ~= "SPELL_VERIFIED" or not spellOrRecipeID or spellOrRecipeID <= 0 or math.floor(spellOrRecipeID) ~= spellOrRecipeID then
    return false, "missing_verified_numeric_spell_id"
  end

  local parsedExec = 1
  local rawExec = explicitExecutions ~= nil and explicitExecutions or craftSpec.quantity
  if rawExec ~= nil then
    local qNum = tonumber(rawExec)
    if not qNum or qNum <= 0 or math.floor(qNum) ~= qNum then
      return false, "invalid_craft_executions"
    end
    parsedExec = math.floor(qNum)
  end

  local rawReagents = type(craftSpec.consumedReagents) == "table" and craftSpec.consumedReagents or craftSpec.reagents
  if type(rawReagents) ~= "table" or #rawReagents == 0 then
    return false, "empty_consumed_reagents"
  end

  local unitMaterials = {}
  for _, rg in ipairs(rawReagents) do
    local rItemID = type(rg) == "table" and tonumber(rg.itemID) or nil
    local rQty = type(rg) == "table" and tonumber(rg.quantity) or nil
    if not rItemID or rItemID <= 0 or math.floor(rItemID) ~= rItemID then
      return false, "missing_reagent_item_id"
    end
    if rg.quantityExplicit ~= false and (not rQty or rQty <= 0 or math.floor(rQty) ~= rQty) then
      return false, "missing_or_invalid_reagent_quantity"
    end
    if rg.quantityDefaulted == true or rg.metadataComplete ~= true then
      return false, "incomplete_reagent_metadata"
    end
    table.insert(unitMaterials, {
      itemID = math.floor(rItemID),
      name = tostring(rg.name or ("Item " .. tostring(rItemID))),
      quantity = math.floor(rQty),
    })
  end

  local _, _, ownerKey = ns.Compat.GetCharacterKey()
  local charDB = State.GetCharDB()
  local goalKey = State.BuildCraftGoalKey(ownerKey, skillLineID, spellOrRecipeID)
  local existing = charDB.reservations[goalKey]

  local priority
  local executions
  if existing then
    priority = tonumber(existing.priority) or 1
    executions = (explicitExecutions ~= nil) and parsedExec or math.max(1, math.floor(tonumber(existing.quantity) or 1))
  else
    priority = charDB.nextPriority or 1
    charDB.nextPriority = priority + 1
    executions = parsedExec
  end

  local minMade = tonumber(craftSpec.minMade)
  local maxMade = tonumber(craftSpec.maxMade)
  local outputRangeComplete = (minMade ~= nil and minMade >= 1 and math.floor(minMade) == minMade)

  charDB.reservations[goalKey] = {
    ownerKey = ownerKey,
    goalKey = goalKey,
    goalID = goalKey .. ":1",
    kind = "craft",
    skillLineID = math.floor(skillLineID),
    spellID = math.floor(spellOrRecipeID),
    spellOrRecipeID = math.floor(spellOrRecipeID),
    targetItemID = tonumber(craftSpec.outputItemID), -- optional reference ONLY; NEVER required for possession!
    outputItemID = tonumber(craftSpec.outputItemID),
    targetName = tostring(craftSpec.name or craftSpec.recipeName or string.format("Recipe #%d", spellOrRecipeID)),
    optionIndex = 1,
    quantity = executions, -- N craft executions!
    minMadePerExecution = outputRangeComplete and math.floor(minMade) or nil,
    maxMadePerExecution = (outputRangeComplete and maxMade and maxMade >= minMade) and math.floor(maxMade) or (outputRangeComplete and math.floor(minMade) or nil),
    requiredTools = type(craftSpec.requiredTools) == "table" and craftSpec.requiredTools or {},
    requiredToolsPresent = (craftSpec.requiredToolsPresent ~= false),
    requiredStation = craftSpec.requiredStation,
    requiredStationPresent = (craftSpec.requiredStationPresent ~= false),
    cooldownID = craftSpec.cooldownID,
    cooldownStatus = tostring(craftSpec.cooldownStatus or "NONE"),
    scanComplete = true,
    reagentsComplete = true,
    learnedRecipeVerified = true,
    viewContext = "own",
    priority = priority,
    unitMaterials = unitMaterials,
    materials = scaleMaterials(unitMaterials, executions),
    updatedAt = time and time() or 0,
  }

  local db = State.GetDB()
  db.characters[ownerKey] = {
    ownerKey = ownerKey,
    reservations = charDB.reservations,
    updatedAt = time and time() or 0,
  }

  State.NormalizePriorities()
  State.BumpReservationRevision()
  return true, charDB.reservations[goalKey]
end
