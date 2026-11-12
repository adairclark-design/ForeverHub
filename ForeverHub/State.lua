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

  State.EnsureNavigationOwnerInitialized()
  State.EnsureRouteProgressInitialized()
  State.EnsureMountTrackerInitialized(isAddonLoad)
  State.EnsureGoldFarmProgressInitialized(isAddonLoad)
  State.EnsureArrowSettingsInitialized()
  State.EnsureWorldMapPinSettingsInitialized()
  State.EnsureWorkspaceUIStateInitialized(isAddonLoad)
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
-- v0.4.0 Riverglades Route State & Mount Tracker (Per-Character)
-- Migrates strictly by stable string actionIDs — never array indexes!
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
  if ctx ~= "riverglades" and ctx ~= "gold_farm" then
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
  charDB.navigationOwner = {
    ownerContext = handle and ctx or nil,
    provider = handle and "native_waypoint" or "none",
    handle = handle,
    pendingRelease = (raw.pendingRelease == true) and (handle ~= nil),
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

  local hudWidth = tonumber(s.hudWidth) or 340
  if hudWidth ~= hudWidth or hudWidth < 280 then
    hudWidth = 280
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
    schemaVersion = 2,
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
  if type(charDB.arrowSettings) ~= "table" or charDB.arrowSettings.schemaVersion ~= 2 then
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
  crates = true,
  riverglades = true,
  gold = true,
}

function State.MigrateWorkspaceUIState(rawUI, settingsRef)
  local u = type(rawUI) == "table" and rawUI or {}
  local prevSchema = tonumber(u.schemaVersion) or 0
  local activeTab = VALID_WORKSPACE_TABS[u.activeTab] and u.activeTab or "riverglades"
  if prevSchema < 2 then
    activeTab = "riverglades"
  end

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

  local rawRG = type(u.rivergladesView) == "table" and u.rivergladesView or {}
  local expandedByActionID = {}
  if type(rawRG.expandedByActionID) == "table" then
    for k, v in pairs(rawRG.expandedByActionID) do
      if type(k) == "string" and k ~= "" and type(v) == "boolean" then
        expandedByActionID[k] = v
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

  return {
    schemaVersion = 2,
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
    rivergladesView = {
      selectedHubID = type(rawRG.selectedHubID) == "string" and rawRG.selectedHubID or nil,
      expandedByActionID = expandedByActionID,
      unresolvedExpanded = (rawRG.unresolvedExpanded == true),
      lastExportedAt = tonumber(rawRG.lastExportedAt) or nil,
      scrollOffset = math.max(0, tonumber(rawRG.scrollOffset) or 0),
    },
    goldView = {
      expandedByFarmID = expandedByFarmID,
      scrollOffset = math.max(0, tonumber(rawGold.scrollOffset) or 0),
    },
  }
end

function State.EnsureWorkspaceUIStateInitialized(isAddonLoad)
  local db = _G.ForeverHubDB
  if type(db) ~= "table" then
    return nil
  end
  db.uiWorkspace = State.MigrateWorkspaceUIState(db.uiWorkspace, db.settings)
  if isAddonLoad then
    db.uiWorkspace.activeTab = "riverglades"
  end
  return db.uiWorkspace
end

function State.GetWorkspaceUIState()
  local db = State.GetDB()
  if type(db.uiWorkspace) ~= "table" or db.uiWorkspace.schemaVersion ~= 2 then
    db.uiWorkspace = State.MigrateWorkspaceUIState(db.uiWorkspace, db.settings)
  end
  return db.uiWorkspace
end

function State.GetCompiledRivergladesRoute()
  return ns.RivergladesData and ns.RivergladesData.route or nil
end

function State.MigrateRouteProgress(rawProgress, compiledRoute)
  local routeID = (compiledRoute and compiledRoute.routeID) or "foreverhub_rg_alliance_farholde_sunnyglade_v1"
  local revision = tonumber(compiledRoute and compiledRoute.revision) or 1

  local validActionIDs = {}
  if compiledRoute and type(compiledRoute.actions) == "table" then
    for _, act in ipairs(compiledRoute.actions) do
      if type(act) == "table" and type(act.actionID) == "string" then
        validActionIDs[act.actionID] = true
      end
    end
  end

  local p = type(rawProgress) == "table" and rawProgress or {}
  -- Never accept numeric array indexes as currentActionID
  local curActionID = type(p.currentActionID) == "string" and p.currentActionID or nil
  if next(validActionIDs) ~= nil and curActionID and not validActionIDs[curActionID] then
    curActionID = nil
  end

  local skipped = {}
  local archivedSkipped = type(p.archivedSkippedActions) == "table" and p.archivedSkippedActions or {}
  if type(p.explicitlySkippedActions) == "table" then
    for aid, entry in pairs(p.explicitlySkippedActions) do
      if type(aid) == "string" and entry then
        if next(validActionIDs) == nil or validActionIDs[aid] then
          skipped[aid] = type(entry) == "table" and entry or { skippedAt = 0, reason = "migrated" }
        else
          archivedSkipped[aid] = entry
        end
      end
    end
  end

  local evidence = {}
  local archivedEvidence = type(p.archivedCompletionEvidence) == "table" and p.archivedCompletionEvidence or {}
  if type(p.observedCompletionEvidence) == "table" then
    for aid, entry in pairs(p.observedCompletionEvidence) do
      if type(aid) == "string" and entry then
        if next(validActionIDs) == nil or validActionIDs[aid] then
          evidence[aid] = type(entry) == "table" and entry or { observedAt = 0, source = "migrated" }
        else
          archivedEvidence[aid] = entry
        end
      end
    end
  end

  local pinnedActionID = type(p.pinnedActionID) == "string" and p.pinnedActionID or nil
  if next(validActionIDs) ~= nil and pinnedActionID and not validActionIDs[pinnedActionID] then
    pinnedActionID = nil
  end
  local pinnedSubLocationID = (pinnedActionID ~= nil and type(p.pinnedSubLocationID) == "string" and p.pinnedSubLocationID ~= "")
      and p.pinnedSubLocationID
    or nil
  local currentSubLocationID = (curActionID ~= nil and type(p.currentSubLocationID) == "string" and p.currentSubLocationID ~= "")
      and p.currentSubLocationID
    or nil

  local completedTitles = {}
  if type(p.observedCompletedQuestTitles) == "table" then
    for k, v in pairs(p.observedCompletedQuestTitles) do
      if type(k) == "string" and v == true then
        completedTitles[k] = true
      end
    end
  end

  local completedIds = {}
  if type(p.observedCompletedQuestIds) == "table" then
    for k, v in pairs(p.observedCompletedQuestIds) do
      local n = tonumber(k)
      if n and n > 0 and v == true then
        completedIds[n] = true
      end
    end
  end

  local confirmedIncomplete = {}
  if type(p.confirmedIncompleteQuestKeys) == "table" then
    for k, v in pairs(p.confirmedIncompleteQuestKeys) do
      if type(k) == "string" and k ~= "" and v == true then
        confirmedIncomplete[k] = true
      end
    end
  end

  local userConfirmedCompleted = {}
  if type(p.userConfirmedCompletedQuestTitles) == "table" then
    for k, v in pairs(p.userConfirmedCompletedQuestTitles) do
      if type(k) == "string" and k ~= "" and v == true then
        userConfirmedCompleted[k] = true
      end
    end
  end

  local observedGivers = {}
  if type(p.observedQuestGivers) == "table" then
    for k, v in pairs(p.observedQuestGivers) do
      local n = tonumber(k)
      if n and n > 0 and type(v) == "table" then
        observedGivers[n] = {
          npcID = tonumber(v.npcID),
          npcName = type(v.npcName) == "string" and v.npcName ~= "" and v.npcName or nil,
          uiMapID = tonumber(v.uiMapID),
          x01 = tonumber(v.x01),
          y01 = tonumber(v.y01),
        }
      end
    end
  end

  local observedObjTexts = {}
  if type(p.observedQuestObjectivesText) == "table" then
    for k, v in pairs(p.observedQuestObjectivesText) do
      local n = tonumber(k)
      if n and n > 0 and type(v) == "string" and v ~= "" then
        observedObjTexts[n] = v
      end
    end
  end

  local mode = p.mode
  if mode ~= "standalone" and mode ~= "rxp" then
    mode = "paused"
  end

  return {
    routeStateVersion = 3,
    routeID = routeID,
    revision = revision,
    mode = mode,
    includeGroupBranch = (p.includeGroupBranch ~= false),
    includeEliteBounties = (p.includeEliteBounties == true),
    currentActionID = curActionID,
    currentSubLocationID = currentSubLocationID,
    pinnedActionID = pinnedActionID,
    pinnedSubLocationID = pinnedSubLocationID,
    explicitlySkippedActions = skipped,
    observedCompletionEvidence = evidence,
    observedCompletedQuestTitles = completedTitles,
    observedCompletedQuestIds = completedIds,
    userConfirmedCompletedQuestTitles = userConfirmedCompleted,
    confirmedIncompleteQuestKeys = confirmedIncomplete,
    observedQuestGivers = observedGivers,
    observedQuestObjectivesText = observedObjTexts,
    archivedSkippedActions = archivedSkipped,
    archivedCompletionEvidence = archivedEvidence,
    ownedWaypoint = type(p.ownedWaypoint) == "table" and p.ownedWaypoint or nil,
  }
end

function State.EnsureRouteProgressInitialized()
  local charDB = _G.ForeverHubCharDB
  if type(charDB) ~= "table" then
    return nil
  end
  charDB.routeProgress = State.MigrateRouteProgress(charDB.routeProgress, State.GetCompiledRivergladesRoute())
  return charDB.routeProgress
end

function State.GetRouteProgress()
  local charDB = State.GetCharDB()
  local compiled = State.GetCompiledRivergladesRoute()
  local expectedRev = tonumber(compiled and compiled.revision) or 1
  if
    type(charDB.routeProgress) ~= "table"
    or charDB.routeProgress.routeStateVersion ~= 3
    or charDB.routeProgress.revision ~= expectedRev
  then
    charDB.routeProgress = State.MigrateRouteProgress(charDB.routeProgress, compiled)
  end
  return charDB.routeProgress
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

function State.RecordCompletedQuestId(questID)
  local qid = tonumber(questID)
  if not qid or qid <= 0 or type(_G.ForeverHubCharDB) ~= "table" then
    return false
  end
  local prog = State.GetRouteProgress()
  if type(prog) == "table" then
    prog.observedCompletedQuestIds = type(prog.observedCompletedQuestIds) == "table" and prog.observedCompletedQuestIds or {}
    prog.observedCompletedQuestIds[qid] = true
    return true
  end
  return false
end

function State.RecordObservedQuestGiver(questID, giverInfo, progressOverride)
  local qid = tonumber(questID)
  if not qid or qid <= 0 or type(giverInfo) ~= "table" then
    return false
  end
  local prog = type(progressOverride) == "table" and progressOverride
    or (type(_G.ForeverHubCharDB) == "table" and State.GetRouteProgress())
    or nil
  if type(prog) ~= "table" then
    return false
  end
  prog.observedQuestGivers = type(prog.observedQuestGivers) == "table" and prog.observedQuestGivers or {}
  prog.observedQuestGivers[qid] = {
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
  if not qid or qid <= 0 then
    return nil
  end
  local rp = type(progressOverride) == "table" and progressOverride
    or (_G.ForeverHubCharDB and _G.ForeverHubCharDB.routeProgress)
  if type(rp) == "table" and type(rp.observedQuestGivers) == "table" then
    local g = rp.observedQuestGivers[qid]
    if type(g) == "table" then
      return g
    end
  end
  return nil
end

function State.RecordObservedQuestObjectiveText(questID, objText, progressOverride)
  local qid = tonumber(questID)
  if not qid or qid <= 0 or type(objText) ~= "string" or objText == "" then
    return false
  end
  local prog = type(progressOverride) == "table" and progressOverride
    or (type(_G.ForeverHubCharDB) == "table" and State.GetRouteProgress())
    or nil
  if type(prog) ~= "table" then
    return false
  end
  prog.observedQuestObjectivesText = type(prog.observedQuestObjectivesText) == "table" and prog.observedQuestObjectivesText or {}
  prog.observedQuestObjectivesText[qid] = objText
  return true
end

function State.GetObservedQuestObjectiveText(questID, progressOverride)
  local qid = tonumber(questID)
  if not qid or qid <= 0 then
    return nil
  end
  local rp = type(progressOverride) == "table" and progressOverride
    or (_G.ForeverHubCharDB and _G.ForeverHubCharDB.routeProgress)
  if type(rp) == "table" and type(rp.observedQuestObjectivesText) == "table" then
    local txt = rp.observedQuestObjectivesText[qid]
    if type(txt) == "string" and txt ~= "" then
      return txt
    end
  end
  return nil
end

function State.IsObservedCompletedQuestId(questID)
  local qid = tonumber(questID)
  if not qid or qid <= 0 or type(_G.ForeverHubCharDB) ~= "table" then
    return false
  end
  local rp = _G.ForeverHubCharDB.routeProgress
  if type(rp) == "table" and type(rp.observedCompletedQuestIds) == "table" and rp.observedCompletedQuestIds[qid] == true then
    return true
  end
  return false
end

function State.IsObservedCompletedQuestTitle(normTitle)
  if type(normTitle) ~= "string" or normTitle == "" or type(_G.ForeverHubCharDB) ~= "table" then
    return false
  end
  local rp = _G.ForeverHubCharDB.routeProgress
  if type(rp) == "table" and type(rp.observedCompletedQuestTitles) == "table" and rp.observedCompletedQuestTitles[normTitle] == true then
    return true
  end
  return false
end

function State.RecordCompletedQuestTitle(normTitle)
  if type(normTitle) ~= "string" or normTitle == "" then
    return false
  end
  local charDB = _G.ForeverHubCharDB
  if type(charDB) ~= "table" then
    return false
  end
  local prog = State.GetRouteProgress()
  if type(prog) == "table" then
    prog.observedCompletedQuestTitles = type(prog.observedCompletedQuestTitles) == "table" and prog.observedCompletedQuestTitles or {}
    prog.observedCompletedQuestTitles[normTitle] = true
    if type(prog.userConfirmedCompletedQuestTitles) == "table" then
      prog.userConfirmedCompletedQuestTitles[normTitle] = nil
      prog.userConfirmedCompletedQuestTitles["title:" .. normTitle] = nil
    end
    State.ClearUnresolvedQuestConfirmation(normTitle, prog)
    return true
  end
  return false
end

-- Records explicit user assertion ("I completed this") distinctly from live API/event verification ("User confirmed").
function State.ConfirmUnresolvedQuestCompleted(questKeyOrTitle, targetProg)
  if type(questKeyOrTitle) ~= "string" or questKeyOrTitle == "" then
    return false
  end
  local rawClean = string.gsub(questKeyOrTitle, "^title:", "")
  local norm = (ns.Compat and ns.Compat.NormalizeQuestTitle and ns.Compat.NormalizeQuestTitle(rawClean)) or string.lower(rawClean)
  if not norm or norm == "" then
    return false
  end
  local prog = targetProg or State.GetRouteProgress()
  if type(prog) ~= "table" then
    return false
  end
  prog.userConfirmedCompletedQuestTitles = type(prog.userConfirmedCompletedQuestTitles) == "table"
      and prog.userConfirmedCompletedQuestTitles
    or {}
  prog.userConfirmedCompletedQuestTitles[norm] = true
  if type(prog.confirmedIncompleteQuestKeys) == "table" then
    prog.confirmedIncompleteQuestKeys[norm] = nil
    prog.confirmedIncompleteQuestKeys["title:" .. norm] = nil
    prog.confirmedIncompleteQuestKeys[questKeyOrTitle] = nil
  end
  State.lastQuestHistoryUndo = {
    normTitle = norm,
    questKey = "title:" .. norm,
    decision = "completed",
  }
  if ns.Compat and type(ns.Compat.InvalidateQuestStateCaches) == "function" then
    ns.Compat.InvalidateQuestStateCaches()
  end
  return true
end

function State.ConfirmUnresolvedQuestIncomplete(questKeyOrTitle, targetProg)
  if type(questKeyOrTitle) ~= "string" or questKeyOrTitle == "" then
    return false
  end
  local rawClean = string.gsub(questKeyOrTitle, "^title:", "")
  local norm = (ns.Compat and ns.Compat.NormalizeQuestTitle and ns.Compat.NormalizeQuestTitle(rawClean)) or string.lower(rawClean)
  if not norm or norm == "" then
    return false
  end
  local prog = targetProg or State.GetRouteProgress()
  if type(prog) ~= "table" then
    return false
  end
  prog.confirmedIncompleteQuestKeys = type(prog.confirmedIncompleteQuestKeys) == "table" and prog.confirmedIncompleteQuestKeys or {}
  prog.confirmedIncompleteQuestKeys[norm] = true
  prog.confirmedIncompleteQuestKeys["title:" .. norm] = true
  if type(prog.userConfirmedCompletedQuestTitles) == "table" then
    prog.userConfirmedCompletedQuestTitles[norm] = nil
    prog.userConfirmedCompletedQuestTitles["title:" .. norm] = nil
  end
  State.lastQuestHistoryUndo = {
    normTitle = norm,
    questKey = "title:" .. norm,
    decision = "incomplete",
  }
  if ns.Compat and type(ns.Compat.InvalidateQuestStateCaches) == "function" then
    ns.Compat.InvalidateQuestStateCaches()
  end
  return true
end

function State.UndoUnresolvedQuestDecision(questKeyOrTitle, targetProg)
  if type(questKeyOrTitle) ~= "string" or questKeyOrTitle == "" then
    if type(State.lastQuestHistoryUndo) == "table" and type(State.lastQuestHistoryUndo.normTitle) == "string" then
      questKeyOrTitle = State.lastQuestHistoryUndo.normTitle
    else
      return false
    end
  end
  local rawClean = string.gsub(questKeyOrTitle, "^title:", "")
  local norm = (ns.Compat and ns.Compat.NormalizeQuestTitle and ns.Compat.NormalizeQuestTitle(rawClean)) or string.lower(rawClean)
  local prog = targetProg or State.GetRouteProgress()
  if type(prog) ~= "table" then
    return false
  end
  if type(prog.userConfirmedCompletedQuestTitles) == "table" then
    if norm then
      prog.userConfirmedCompletedQuestTitles[norm] = nil
      prog.userConfirmedCompletedQuestTitles["title:" .. norm] = nil
    end
    prog.userConfirmedCompletedQuestTitles[questKeyOrTitle] = nil
  end
  if type(prog.confirmedIncompleteQuestKeys) == "table" then
    if norm then
      prog.confirmedIncompleteQuestKeys[norm] = nil
      prog.confirmedIncompleteQuestKeys["title:" .. norm] = nil
    end
    prog.confirmedIncompleteQuestKeys[questKeyOrTitle] = nil
  end
  if State.lastQuestHistoryUndo and State.lastQuestHistoryUndo.normTitle == norm then
    State.lastQuestHistoryUndo = nil
  end
  if ns.Compat and type(ns.Compat.InvalidateQuestStateCaches) == "function" then
    ns.Compat.InvalidateQuestStateCaches()
  end
  return true
end

function State.GetUnresolvedQuestUserDecision(questKeyOrTitle, targetProg)
  if type(questKeyOrTitle) ~= "string" or questKeyOrTitle == "" then
    return nil
  end
  local rawClean = string.gsub(questKeyOrTitle, "^title:", "")
  local norm = (ns.Compat and ns.Compat.NormalizeQuestTitle and ns.Compat.NormalizeQuestTitle(rawClean)) or string.lower(rawClean)
  local prog = targetProg or (type(_G.ForeverHubCharDB) == "table" and _G.ForeverHubCharDB.routeProgress) or nil
  if type(prog) ~= "table" then
    return nil
  end
  if type(prog.userConfirmedCompletedQuestTitles) == "table" and norm and prog.userConfirmedCompletedQuestTitles[norm] == true then
    return "user_confirmed_completed"
  end
  if type(prog.confirmedIncompleteQuestKeys) == "table" and norm then
    if prog.confirmedIncompleteQuestKeys[norm] == true or prog.confirmedIncompleteQuestKeys["title:" .. norm] == true then
      return "user_confirmed_incomplete"
    end
  end
  return nil
end

function State.ClearUnresolvedQuestConfirmation(questKeyOrTitle, targetProg)
  if type(questKeyOrTitle) ~= "string" or questKeyOrTitle == "" then
    return false
  end
  local rawClean = string.gsub(questKeyOrTitle, "^title:", "")
  local norm = ns.Compat and ns.Compat.NormalizeQuestTitle and ns.Compat.NormalizeQuestTitle(rawClean) or nil
  local prog = targetProg or (type(_G.ForeverHubCharDB) == "table" and _G.ForeverHubCharDB.routeProgress) or nil
  if type(prog) ~= "table" then
    return false
  end
  if type(prog.confirmedIncompleteQuestKeys) == "table" then
    if norm then
      prog.confirmedIncompleteQuestKeys[norm] = nil
      prog.confirmedIncompleteQuestKeys["title:" .. norm] = nil
    end
    prog.confirmedIncompleteQuestKeys[questKeyOrTitle] = nil
  end
  return true
end

function State.IsUnresolvedQuestConfirmedIncomplete(normTitle, questKey, targetProg)
  local prog = targetProg or (type(_G.ForeverHubCharDB) == "table" and _G.ForeverHubCharDB.routeProgress) or nil
  if type(prog) ~= "table" or type(prog.confirmedIncompleteQuestKeys) ~= "table" then
    return false
  end
  if type(normTitle) == "string" and normTitle ~= "" then
    if prog.confirmedIncompleteQuestKeys[normTitle] == true or prog.confirmedIncompleteQuestKeys["title:" .. normTitle] == true then
      return true
    end
  end
  if type(questKey) == "string" and questKey ~= "" and prog.confirmedIncompleteQuestKeys[questKey] == true then
    return true
  end
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
  if catalog and type(catalog.farms) == "table" then
    for _, farm in ipairs(catalog.farms) do
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
  }
end

local resolveNowAndMoney
local accrueOpenSegment

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
  charDB.goldFarmTelemetry = {
    telemetryVersion = 2,
    sessionID = sess.sessionID,
    farmID = sess.farmID,
    phase = sess.phase,
    campSeconds = math.max(0, math.floor(tonumber(sess.campSeconds) or 0)),
    travelAndServiceSeconds = math.max(0, math.floor(tonumber(sess.travelAndServiceSeconds) or 0)),
    rxpUntrackedSeconds = math.max(0, math.floor(tonumber(sess.rxpUntrackedSeconds) or 0)),
    accumulatedSeconds = math.max(0, math.floor(tonumber(sess.accumulatedSeconds) or 0)),
    accumulatedCopper = math.floor(tonumber(sess.accumulatedCopper) or 0),
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
  local hasPriorTotals = (accSec > 0) or ((tonumber(raw.accumulatedCopper) or 0) ~= 0) or (raw.farmID ~= nil)
  local restoredPhase = normalizeTelemetryPhase(raw.phase) or "camp"

  -- Astra P1-9: After reload/login, ALWAYS resume telemetry PAUSED with nil clock/money baseline
  -- so offline time or unexplained reload money changes are NEVER counted!
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
    contaminated = contaminated,
    contaminationReason = raw.contaminationReason,
    cleanIntervalConfirmed = (raw.cleanIntervalConfirmed ~= false) and not contaminated,
  }
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
  elseif not sess.active then
    sess.active = true
    sess.segmentStartedAt = nowSec
    sess.segmentStartCopper = copper
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
  State.goldFarmSession = {
    sessionID = newTelemetrySessionID(nowSec),
    active = (keepActive == true) and not hasOpenWindow,
    pausedByReload = false,
    pausedForWindow = hasOpenWindow and State.goldFarmSession.pausedForWindow or nil,
    wasActiveBeforeWindow = (keepActive == true) and hasOpenWindow,
    activeWindows = (State.goldFarmSession and State.goldFarmSession.activeWindows) or {},
    farmID = farmID,
    phase = normPhase,
    segmentStartedAt = (keepActive == true and not hasOpenWindow) and nowSec or nil,
    segmentStartCopper = (keepActive == true and not hasOpenWindow) and copper or nil,
    campSeconds = 0,
    travelAndServiceSeconds = 0,
    rxpUntrackedSeconds = 0,
    accumulatedSeconds = 0,
    accumulatedCopper = 0,
    contaminated = not clean,
    contaminationReason = hasOpenWindow and State.goldFarmSession.pausedForWindow or (copper == nil and "money_unavailable_at_reset" or nil),
    cleanIntervalConfirmed = clean,
  }
  State.CheckpointGoldFarmTelemetry()
  return State.goldFarmSession
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
