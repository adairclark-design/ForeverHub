local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.Providers = ns.Providers or {}
local Inventory = {}
ns.Providers.Inventory = Inventory

local BACKPACK_BAG = 0
local NUM_PLAYER_BAGS = 5 -- Includes Reagent Bag slot 5 in WoW: Forever 1.60.1

Inventory.__cachedRevision = nil
Inventory.__cachedSnapshot = nil
Inventory.__cachedBankMetadata = nil

function Inventory.InvalidateCache()
  Inventory.__cachedRevision = nil
  Inventory.__cachedSnapshot = nil
end

function Inventory.ScanLiveBags()
  local counts = {}
  local maxBag = tonumber(_G.NUM_TOTAL_EQUIPPED_BAG_SLOTS) or NUM_PLAYER_BAGS
  for bagID = BACKPACK_BAG, maxBag do
    local numSlots = ns.Compat.GetContainerNumSlots(bagID)
    for slotID = 1, numSlots do
      local info = ns.Compat.GetContainerItemInfo(bagID, slotID)
      if info and info.itemID then
        counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1)
      end
    end
  end
  return counts
end

-- Scans the active character's bank ONLY when bank is viewable (`Compat.CanViewCharacterBank()`),
-- using capability-detected purchased bank tab enumeration (`C_Bank.FetchPurchasedBankTabData(0)`).
-- Publishes `ForeverHubCharDB.bankSnapshot` and runtime `State.sessionBankObserved` atomically ONLY when complete
-- and all occupied slots have resolved item IDs.
function Inventory.ScanLiveBankIfOpen()
  if not ns.Compat.CanViewCharacterBank() then
    return nil
  end

  local bankInfo = ns.Compat.GetPurchasedBankTabIDs()
  if not bankInfo or bankInfo.available ~= true or bankInfo.complete ~= true then
    return nil
  end

  local tabIDs = bankInfo.tabIDs or {}
  local mode = bankInfo.mode

  local counts = {}
  local readableTabs = 0

  if mode == "bank_tabs" then
    if #tabIDs == 0 then
      if bankInfo.confirmedZeroTabs ~= true then
        return nil
      end
    else
      for _, bagID in ipairs(tabIDs) do
        local numSlots = ns.Compat.GetContainerNumSlots(bagID)
        if not numSlots or numSlots <= 0 then
          return nil
        end
        readableTabs = readableTabs + 1
        for slotID = 1, numSlots do
          local info = ns.Compat.GetContainerItemInfo(bagID, slotID)
          if info then
            -- If a slot is occupied (`hasItem`) but itemID has not finished loading yet, abort incomplete scan
            if info.hasItem and not info.itemID then
              return nil
            end
            if info.itemID then
              counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1)
            end
          end
        end
      end
      if readableTabs < #tabIDs then
        return nil
      end
    end
  else
    -- Legacy fallback mode (only used when C_Bank.FetchPurchasedBankTabData capability is absent)
    local mainBankSlots = ns.Compat.GetContainerNumSlots(-1)
    if not mainBankSlots or mainBankSlots <= 0 then
      return nil
    end
    for _, bagID in ipairs(tabIDs) do
      local numSlots = ns.Compat.GetContainerNumSlots(bagID)
      if numSlots and numSlots > 0 then
        readableTabs = readableTabs + 1
        for slotID = 1, numSlots do
          local info = ns.Compat.GetContainerItemInfo(bagID, slotID)
          if info then
            if info.hasItem and not info.itemID then
              return nil
            end
            if info.itemID then
              counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1)
            end
          end
        end
      end
    end
  end

  local now = (time and time()) or 0
  local liveSnapshot = {
    available = true,
    complete = true,
    observedAt = now,
    source = "live_bank",
    mode = mode,
    tabIDs = tabIDs,
    counts = counts,
  }

  local charDB = ns.State.GetCharDB()
  charDB.bankSnapshot = {
    available = true,
    complete = true,
    observedAt = now,
    source = "persisted_fallback",
    mode = mode,
    tabIDs = tabIDs,
    counts = counts,
  }
  -- Keep session authority strictly in runtime state, never in ForeverHubCharDB
  charDB.sessionBankObserved = nil
  if ns.State and ns.State.SetSessionBankObserved then
    ns.State.SetSessionBankObserved({
      available = true,
      complete = true,
      observedAt = now,
      source = "session_live_bank",
      mode = mode,
      tabIDs = tabIDs,
      counts = counts,
    })
  end

  return liveSnapshot
end

-- Enforces exact 4-step bank snapshot precedence:
-- 1. Complete live observation (`live_bank`)
-- 2. Latest complete observation made during this runtime session (`session_live_bank`)
-- 3. Valid external snapshot on a new session (`bagbrother` / `syndicator`)
-- 4. Persisted ForeverHub snapshot as a labeled fallback (`persisted_fallback`)
-- Never treats an empty bank (`counts = {}`) as unavailable, and never invents timestamps for external data.
function Inventory.ResolveCurrentBankSnapshot(liveBankSnap, externalBankSnap, cachedBankSnap, sessionBankObserved)
  -- 1. Complete live observation while bank is open
  if type(liveBankSnap) == "table" and liveBankSnap.available == true and liveBankSnap.complete == true then
    return liveBankSnap
  end

  -- 2. Latest complete observation made during this runtime session
  if sessionBankObserved == true and type(cachedBankSnap) == "table" and cachedBankSnap.available == true and cachedBankSnap.complete == true then
    return {
      available = true,
      complete = true,
      observedAt = cachedBankSnap.observedAt,
      source = (cachedBankSnap.source == "live_bank" or cachedBankSnap.source == "session_live_bank")
        and "session_live_bank"
        or cachedBankSnap.source,
      mode = cachedBankSnap.mode,
      tabIDs = cachedBankSnap.tabIDs or {},
      counts = cachedBankSnap.counts or {},
    }
  end

  -- 3. Valid external snapshot on a new session (BagBrother / Syndicator)
  if type(externalBankSnap) == "table" and externalBankSnap.available == true and externalBankSnap.complete == true then
    return externalBankSnap
  end

  -- 4. Persisted ForeverHub snapshot as a labeled fallback
  if type(cachedBankSnap) == "table" and cachedBankSnap.available == true and cachedBankSnap.complete == true then
    return {
      available = true,
      complete = true,
      observedAt = cachedBankSnap.observedAt,
      source = "persisted_fallback",
      mode = cachedBankSnap.mode,
      tabIDs = cachedBankSnap.tabIDs or {},
      counts = cachedBankSnap.counts or {},
    }
  end

  return {
    available = false,
    complete = false,
    observedAt = nil,
    source = "none",
    tabIDs = {},
    counts = {},
  }
end

-- Returns cached aggregated snapshot keyed by `ns.State.inventoryRevision`.
-- Never double-counts live bags or current-character bank, and never resurrects cached holdings over a valid empty bank.
function Inventory.GetAggregatedSnapshot(forceRefresh)
  local invRev = (ns.State and ns.State.inventoryRevision) or 1
  if not forceRefresh and Inventory.__cachedSnapshot and Inventory.__cachedRevision == invRev then
    return Inventory.__cachedSnapshot, Inventory.__cachedBankMetadata
  end

  local liveBags = Inventory.ScanLiveBags()
  local liveBankSnap = Inventory.ScanLiveBankIfOpen()
  local charDB = ns.State.GetCharDB()
  local sessionBankObserved = (ns.State and ns.State.sessionBankObserved == true) or false
  local cachedBankSnap = (sessionBankObserved and ns.State and ns.State.sessionBankSnapshot)
    or (charDB and charDB.bankSnapshot)
    or nil

  local external = {}
  if ns.Providers.Syndicator and ns.Providers.Syndicator.GetAccountSnapshot then
    external = ns.Providers.Syndicator.GetAccountSnapshot() or {}
  end

  local chosenBankSnap = Inventory.ResolveCurrentBankSnapshot(
    liveBankSnap,
    external.currentCharBankSnapshot,
    cachedBankSnap,
    sessionBankObserved
  )

  local snapshot = {}
  local function ensure(itemID)
    local entry = snapshot[itemID]
    if not entry then
      entry = {
        itemID = itemID,
        bagCount = 0,
        bankCount = 0,
        charOwned = 0,
        altEligibleCount = 0,
        altUnknownCount = 0,
        altIneligibleCount = 0,
        altCount = 0,
        sources = {},
      }
      snapshot[itemID] = entry
    end
    return entry
  end

  for itemID, qty in pairs(liveBags) do
    if qty > 0 then
      local e = ensure(itemID)
      e.bagCount = qty
      e.charOwned = e.bagCount + e.bankCount
      table.insert(e.sources, {
        character = "Current",
        location = "bags",
        quantity = qty,
        transferState = "eligible",
        transferEligible = true,
      })
    end
  end

  if chosenBankSnap and chosenBankSnap.available and chosenBankSnap.complete then
    for itemID, qty in pairs(chosenBankSnap.counts or {}) do
      if qty > 0 then
        local e = ensure(itemID)
        e.bankCount = qty
        e.charOwned = e.bagCount + e.bankCount
        table.insert(e.sources, {
          character = "Current",
          location = "bank",
          quantity = qty,
          transferState = "eligible",
          transferEligible = true,
        })
      end
    end
  end

  for itemID, qty in pairs(external.altEligibleTotals or {}) do
    if qty > 0 then
      local e = ensure(itemID)
      e.altEligibleCount = qty
      e.altCount = e.altEligibleCount
    end
  end

  for itemID, qty in pairs(external.altUnknownTotals or {}) do
    if qty > 0 then
      local e = ensure(itemID)
      e.altUnknownCount = qty
    end
  end

  for itemID, qty in pairs(external.altIneligibleTotals or {}) do
    if qty > 0 then
      local e = ensure(itemID)
      e.altIneligibleCount = qty
    end
  end

  for itemID, srcList in pairs(external.altSources or {}) do
    local e = ensure(itemID)
    for _, src in ipairs(srcList) do
      table.insert(e.sources, src)
    end
  end

  Inventory.__cachedRevision = invRev
  Inventory.__cachedSnapshot = snapshot
  Inventory.__cachedBankMetadata = chosenBankSnap
  return snapshot, chosenBankSnap
end

function Inventory.GetBankAttributionMeta()
  local _, meta = Inventory.GetAggregatedSnapshot()
  meta = meta or Inventory.__cachedBankMetadata or { available = false, source = "none" }
  local src = tostring(meta.source or "none")
  if src == "live_bank" then
    return {
      authority = "live",
      source = src,
      isCached = false,
      label = "Bank: Live",
    }
  elseif src == "session_live_bank" then
    return {
      authority = "session",
      source = src,
      isCached = true,
      label = "Bank: Observed this session",
    }
  elseif src == "bagbrother" or src == "syndicator" then
    return {
      authority = "external_cache",
      source = src,
      isCached = true,
      label = string.format("Bank: Cached (%s, unverified tab count)", src),
    }
  elseif src == "persisted_fallback" then
    return {
      authority = "fh_cache",
      source = src,
      isCached = true,
      label = "Bank: Cached (ForeverHub fallback)",
    }
  end
  return {
    authority = "none",
    source = "none",
    isCached = false,
    label = "Bank: Unvisited",
  }
end

function Inventory.GetItemCounts(itemID, optionalSnapshot)
  itemID = tonumber(itemID)
  if not itemID then
    return {
      bagCount = 0,
      bankCount = 0,
      charOwned = 0,
      altEligibleCount = 0,
      altUnknownCount = 0,
      altIneligibleCount = 0,
      altCount = 0,
      sources = {},
    }
  end
  local snap = optionalSnapshot or Inventory.GetAggregatedSnapshot()
  return snap[itemID] or {
    itemID = itemID,
    bagCount = 0,
    bankCount = 0,
    charOwned = 0,
    altEligibleCount = 0,
    altUnknownCount = 0,
    altIneligibleCount = 0,
    altCount = 0,
    sources = {},
  }
end

-- ============================================================================
-- Acknowledged Single-Step Bank Collection State Machine
-- Validate -> Issue one move -> Observe result -> Recompute -> Continue
-- ============================================================================

Inventory.COLLECTION_STEP_TIMEOUT_SECONDS = 3
Inventory.__collectionState = {
  active = false,
  status = "idle",
  reason = nil,
  startedReservationRevision = nil,
  pendingMove = nil,
  completedMoves = {},
  excessNotes = {},
  lastMessage = nil,
}

function Inventory.GetBankCollectionState()
  return Inventory.__collectionState
end

-- Checks item-specific destination bag capacity for transferring `transferCount` of `itemID`.
-- Standard bags `0..4` accept all items; reagent bag `5` is ONLY counted for partial stacks
-- of `itemID` already present in bag `5` (never assumed to accept arbitrary items or crates/writs).
function Inventory.CanFitItemInPlayerBags(itemID, transferCount)
  itemID = tonumber(itemID)
  transferCount = math.max(1, math.floor(tonumber(transferCount) or 1))
  local maxStack = (ns.Compat and ns.Compat.GetItemMaxStack and ns.Compat.GetItemMaxStack(itemID)) or 20

  local freeStandardSlots = 0
  local partialCapacity = 0

  local maxBag = tonumber(_G.NUM_TOTAL_EQUIPPED_BAG_SLOTS) or NUM_PLAYER_BAGS
  for bagID = BACKPACK_BAG, maxBag do
    local isStandardBag = (bagID >= 0 and bagID <= 4)
    local numSlots = ns.Compat.GetContainerNumSlots(bagID)
    for slotID = 1, numSlots do
      local info = ns.Compat.GetContainerItemInfo(bagID, slotID)
      if not info or not info.hasItem then
        if isStandardBag then
          freeStandardSlots = freeStandardSlots + 1
        end
      elseif tonumber(info.itemID) == itemID then
        local curStack = math.max(1, math.floor(tonumber(info.stackCount) or 1))
        if curStack < maxStack then
          partialCapacity = partialCapacity + (maxStack - curStack)
        end
      end
    end
  end

  if freeStandardSlots > 0 then
    return true, freeStandardSlots, partialCapacity
  end
  if partialCapacity >= transferCount then
    return true, 0, partialCapacity
  end
  return false, 0, partialCapacity
end

-- Scans open bank containers for unlocked slots containing `targetItemID` and selects the best stack for `neededQty`:
-- 1. If stacks with `stackCount <= neededQty` exist, prefers the largest stack <= `neededQty` (exact fit first).
-- 2. Otherwise (all stacks > `neededQty`), prefers the SMALLEST stack > `neededQty` to minimize whole-stack excess.
function Inventory.FindBestBankSlotForItem(targetItemID, neededQty)
  targetItemID = tonumber(targetItemID)
  neededQty = math.max(1, math.floor(tonumber(neededQty) or 1))
  if not ns.Compat.CanViewCharacterBank() then
    return nil, "bank_closed"
  end

  local bankInfo = ns.Compat.GetPurchasedBankTabIDs()
  if not bankInfo or bankInfo.available ~= true or bankInfo.complete ~= true then
    return nil, "bank_unavailable"
  end

  local candidates = {}
  local sawLocked = false
  for _, bagID in ipairs(bankInfo.tabIDs or {}) do
    local numSlots = ns.Compat.GetContainerNumSlots(bagID) or 0
    for slotID = 1, numSlots do
      local info = ns.Compat.GetContainerItemInfo(bagID, slotID)
      if info and tonumber(info.itemID) == targetItemID then
        if ns.Compat.IsContainerItemLocked and ns.Compat.IsContainerItemLocked(bagID, slotID) then
          sawLocked = true
        else
          table.insert(candidates, {
            bagID = bagID,
            slotID = slotID,
            itemID = targetItemID,
            stackCount = math.max(1, math.floor(tonumber(info.stackCount) or 1)),
          })
        end
      end
    end
  end

  if #candidates == 0 then
    return nil, sawLocked and "slot_locked" or "not_found"
  end

  table.sort(candidates, function(a, b)
    local aUnder = (a.stackCount <= neededQty)
    local bUnder = (b.stackCount <= neededQty)
    if aUnder ~= bUnder then
      return aUnder
    end
    if aUnder and bUnder then
      if a.stackCount ~= b.stackCount then
        return a.stackCount > b.stackCount
      end
    else
      if a.stackCount ~= b.stackCount then
        return a.stackCount < b.stackCount
      end
    end
    if a.bagID ~= b.bagID then
      return a.bagID < b.bagID
    end
    return a.slotID < b.slotID
  end)

  return candidates[1], nil
end

function Inventory.CancelBankCollection(reason, message)
  local st = Inventory.__collectionState
  if not st then
    return
  end
  local wasActive = st.active
  st.active = false
  st.status = "cancelled"
  st.reason = reason or "user_cancelled"
  st.pendingMove = nil
  st.lastMessage = message or string.format("Bank collection stopped (%s).", tostring(st.reason))
  if wasActive and ns.UI and ns.UI.Crates and ns.UI.Crates.RefreshIfShown then
    ns.UI.Crates.RefreshIfShown()
  end
  return st
end

function Inventory.OnReservationRevisionChanged()
  local st = Inventory.__collectionState
  if st and st.active then
    Inventory.CancelBankCollection(
      "plan_changed",
      "Bank collection cancelled because your reservation plan changed."
    )
  end
end

local function selectNextCollectionRequirement(plan)
  for _, t in ipairs((plan and plan.targetItems) or {}) do
    if (tonumber(t.pullQty) or 0) > 0 then
      return {
        itemID = tonumber(t.itemID),
        name = t.name,
        neededQty = tonumber(t.pullQty),
        bagOwned = tonumber(t.bagOwned) or 0,
        bankOwned = tonumber(t.bankOwned) or 0,
        isTargetItem = true,
      }
    end
  end
  for _, m in ipairs((plan and plan.materials) or {}) do
    if (tonumber(m.pullQty) or 0) > 0 then
      return {
        itemID = tonumber(m.itemID),
        name = m.name,
        neededQty = tonumber(m.pullQty),
        bagOwned = tonumber(m.bagOwned) or 0,
        bankOwned = tonumber(m.bankOwned) or 0,
        isTargetItem = false,
      }
    end
  end
  return nil
end

function Inventory.PreviewBankCollection()
  local snap = Inventory.GetAggregatedSnapshot()
  local plan = ns.Domain.Reservations.BuildBankCollectionPlan(snap)
  local excessPreview = {}

  if ns.Compat.CanViewCharacterBank() then
    local allReqs = {}
    for _, t in ipairs(plan.targetItems or {}) do
      table.insert(allReqs, t)
    end
    for _, m in ipairs(plan.materials or {}) do
      table.insert(allReqs, m)
    end
    for _, req in ipairs(allReqs) do
      local slot = Inventory.FindBestBankSlotForItem(req.itemID, req.pullQty)
      if slot and slot.stackCount > req.pullQty then
        local extra = slot.stackCount - req.pullQty
        table.insert(
          excessPreview,
          string.format(
            "Need %d %s; transferring a stack of %d; %d extra will remain in bags.",
            req.pullQty,
            req.name,
            slot.stackCount,
            extra
          )
        )
      end
    end
  end

  return {
    plan = plan,
    bankOpen = ns.Compat.CanViewCharacterBank(),
    excessPreview = excessPreview,
  }
end

function Inventory.StepBankCollection()
  local st = Inventory.__collectionState
  if not st or not st.active then
    return st
  end

  -- 1. Validate environment preconditions
  if not ns.Compat.CanViewCharacterBank() then
    return Inventory.CancelBankCollection("bank_closed", "Bank collection stopped because the bank was closed.")
  end
  if ns.Compat.IsInCombat and ns.Compat.IsInCombat() then
    return Inventory.CancelBankCollection("combat", "Bank collection stopped because you entered combat.")
  end
  if ns.Compat.HasCursorItem and ns.Compat.HasCursorItem() then
    return Inventory.CancelBankCollection("cursor_busy", "Bank collection paused because an item is on the cursor.")
  end

  local _, resRev = 1, 1
  if ns.State and ns.State.GetRevisions then
    _, resRev = ns.State.GetRevisions()
  end
  if st.startedReservationRevision and resRev ~= st.startedReservationRevision then
    return Inventory.CancelBankCollection("plan_changed", "Bank collection stopped because reservations changed.")
  end

  local snap = Inventory.GetAggregatedSnapshot(true)

  -- 2. If a move is currently pending, verify acknowledgment before issuing any new move
  if st.pendingMove then
    local pm = st.pendingMove
    local curCounts = snap[pm.itemID] or {}
    local curBag = tonumber(curCounts.bagCount) or 0
    local curBank = tonumber(curCounts.bankCount) or 0
    local curChar = curBag + curBank

    if curChar < pm.expectedCharOwned then
      return Inventory.CancelBankCollection(
        "unexpected_inventory_change",
        string.format("Bank collection stopped: unexpected inventory change for %s.", tostring(pm.itemName))
      )
    end

    if curBag >= pm.expectedBagCountAfter then
      -- Move acknowledged! Record completion and clear pendingMove before recomputing
      table.insert(st.completedMoves, {
        itemID = pm.itemID,
        itemName = pm.itemName,
        transferred = curBag - pm.bagCountBefore,
        excessQty = pm.excessQty,
      })
      st.pendingMove = nil
    else
      local now = (type(time) == "function" and time()) or 0
      if pm.issuedAt and (now - pm.issuedAt) > Inventory.COLLECTION_STEP_TIMEOUT_SECONDS then
        return Inventory.CancelBankCollection(
          "timeout",
          string.format("Bank collection timed out waiting for %s to move to bags.", tostring(pm.itemName))
        )
      end
      -- Still waiting for client container event acknowledgment
      return st
    end
  end

  -- 3. Recompute remaining bank collection plan from fresh live state
  local plan = ns.Domain.Reservations.BuildBankCollectionPlan(snap)
  local nextReq = selectNextCollectionRequirement(plan)
  if not nextReq then
    st.active = false
    st.status = "completed"
    st.reason = "all_collected"
    local altNote = (plan.totalAltAllocatedUnits and plan.totalAltAllocatedUnits > 0)
      and string.format(" (%d additional reserved units remain on alts.)", plan.totalAltAllocatedUnits)
      or ""
    st.lastMessage = string.format(
      "Bank collection complete (%d stack move(s)).%s",
      #st.completedMoves,
      altNote
    )
    if ns.Compat and ns.Compat.Print then
      ns.Compat.Print(st.lastMessage)
    end
    return st
  end

  -- 4. Find best bank stack for `nextReq`
  local bestSlot, slotErr = Inventory.FindBestBankSlotForItem(nextReq.itemID, nextReq.neededQty)
  if not bestSlot then
    if slotErr == "slot_locked" then
      st.lastMessage = string.format("Waiting for locked bank slot (%s)...", tostring(nextReq.name))
      return st
    end
    return Inventory.CancelBankCollection(
      slotErr or "slot_unavailable",
      string.format("Could not find unlocked bank stack for %s.", tostring(nextReq.name))
    )
  end

  -- 5. Verify item-specific destination bag capacity in player bags 0..4
  local canFit = Inventory.CanFitItemInPlayerBags(nextReq.itemID, bestSlot.stackCount)
  if not canFit then
    return Inventory.CancelBankCollection(
      "bag_full",
      string.format(
        "Destination bags (0..4) cannot fit %s x%d; free a bag slot and try again.",
        tostring(nextReq.name),
        bestSlot.stackCount
      )
    )
  end

  local excessQty = math.max(0, bestSlot.stackCount - nextReq.neededQty)
  if excessQty > 0 then
    local excessMsg = string.format(
      "Need %d %s; transferring a stack of %d; %d extra will remain in bags.",
      nextReq.neededQty,
      nextReq.name,
      bestSlot.stackCount,
      excessQty
    )
    table.insert(st.excessNotes, excessMsg)
    st.lastMessage = excessMsg
    if ns.Compat and ns.Compat.Print then
      ns.Compat.Print(excessMsg)
    end
  else
    st.lastMessage = string.format("Withdrawing %s x%d from bank...", tostring(nextReq.name), bestSlot.stackCount)
  end

  -- 6. Issue exactly ONE container move and wait for observed bag increase
  local now = (type(time) == "function" and time()) or 0
  st.pendingMove = {
    itemID = nextReq.itemID,
    itemName = nextReq.name,
    bagID = bestSlot.bagID,
    slotID = bestSlot.slotID,
    stackCount = bestSlot.stackCount,
    neededQty = nextReq.neededQty,
    excessQty = excessQty,
    bagCountBefore = nextReq.bagOwned,
    expectedBagCountAfter = nextReq.bagOwned + bestSlot.stackCount,
    expectedCharOwned = nextReq.bagOwned + nextReq.bankOwned,
    issuedAt = now,
  }

  local issued = ns.Compat.UseContainerItem(bestSlot.bagID, bestSlot.slotID)
  if not issued then
    st.pendingMove = nil
    return Inventory.CancelBankCollection(
      "move_failed",
      string.format("Failed to issue bank withdrawal for %s.", tostring(nextReq.name))
    )
  end

  return st
end

function Inventory.StartBankCollection()
  if not ns.Compat.CanViewCharacterBank() then
    local msg = "Open your character bank first to collect planned crates and materials."
    if ns.Compat and ns.Compat.Print then
      ns.Compat.Print(msg)
    end
    Inventory.__collectionState = {
      active = false,
      status = "blocked",
      reason = "bank_closed",
      lastMessage = msg,
      completedMoves = {},
      excessNotes = {},
    }
    return Inventory.__collectionState
  end

  local _, resRev = 1, 1
  if ns.State and ns.State.GetRevisions then
    _, resRev = ns.State.GetRevisions()
  end

  Inventory.__collectionState = {
    active = true,
    status = "running",
    reason = nil,
    startedReservationRevision = resRev,
    pendingMove = nil,
    completedMoves = {},
    excessNotes = {},
    lastMessage = "Starting bank collection...",
  }

  return Inventory.StepBankCollection()
end

function Inventory.OnInventoryChangedForCollection()
  local st = Inventory.__collectionState
  if st and st.active then
    return Inventory.StepBankCollection()
  end
  return nil
end
