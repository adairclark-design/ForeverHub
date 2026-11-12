local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.Domain = ns.Domain or {}
local Diagnostics = {}
ns.Domain.Diagnostics = Diagnostics

Diagnostics.MAX_TRACE_ENTRIES = 250
Diagnostics.__lastBagCounts = nil
Diagnostics.__lastBankCounts = nil

local function getInteractionContext(explicitContext)
  if type(explicitContext) == "table" then
    return {
      bankOpen = explicitContext.bankOpen == true,
      mailOpen = explicitContext.mailOpen == true,
      ahOpen = explicitContext.ahOpen == true,
      merchantOpen = explicitContext.merchantOpen == true,
      tradeOpen = explicitContext.tradeOpen == true,
      gossipOpen = explicitContext.gossipOpen == true,
    }
  end
  local st = ns.State or {}
  return {
    bankOpen = st.bankOpen == true,
    mailOpen = st.mailOpen == true,
    ahOpen = st.ahOpen == true,
    merchantOpen = st.merchantOpen == true,
    tradeOpen = st.tradeOpen == true,
    gossipOpen = st.gossipOpen == true,
  }
end

local function isRelevantItemID(itemID)
  itemID = tonumber(itemID)
  if not itemID then
    return false
  end
  local data = ns.Data or {}
  if data.cratesByItemID and data.cratesByItemID[itemID] then
    return true
  end
  if data.sealedCratesByItemID and data.sealedCratesByItemID[itemID] then
    return true
  end
  if data.writsByItemID and data.writsByItemID[itemID] then
    return true
  end
  if data.sealedWritsByItemID and data.sealedWritsByItemID[itemID] then
    return true
  end
  if data.shippingLabelsByItemID and data.shippingLabelsByItemID[itemID] then
    return true
  end
  if data.materialToCrates and data.materialToCrates[itemID] then
    return true
  end
  return false
end

local function appendTraceEntry(entry)
  local trace = ns.State and ns.State.GetDiagnosticTrace and ns.State.GetDiagnosticTrace()
  if not trace then
    return nil
  end
  trace.entries = trace.entries or {}
  local invRev, resRev = 1, 1
  if ns.State and ns.State.GetRevisions then
    invRev, resRev = ns.State.GetRevisions()
  end
  entry.seq = (#trace.entries) + 1
  entry.timestamp = entry.timestamp or ((type(time) == "function" and time()) or 0)
  entry.inventoryRevision = entry.inventoryRevision or invRev
  entry.reservationRevision = entry.reservationRevision or resRev
  entry.context = entry.context or getInteractionContext()

  table.insert(trace.entries, entry)
  while #trace.entries > Diagnostics.MAX_TRACE_ENTRIES do
    table.remove(trace.entries, 1)
  end
  return entry
end

function Diagnostics.IsEnabled()
  local trace = ns.State and ns.State.GetDiagnosticTrace and ns.State.GetDiagnosticTrace()
  if trace and trace.enabled ~= nil then
    return trace.enabled == true
  end
  return true
end

function Diagnostics.SetEnabled(enabled)
  local trace = ns.State and ns.State.GetDiagnosticTrace and ns.State.GetDiagnosticTrace()
  if trace then
    trace.enabled = (enabled == true)
  end
end

function Diagnostics.ClearTrace()
  local trace = ns.State and ns.State.GetDiagnosticTrace and ns.State.GetDiagnosticTrace()
  if trace then
    trace.entries = {}
    trace.transactions = {}
  end
  Diagnostics.__lastBagCounts = nil
  Diagnostics.__lastBankCounts = nil
end

function Diagnostics.RecordQuestEvent(eventName, questID, extraInfo, explicitContext)
  if not Diagnostics.IsEnabled() then
    return nil
  end
  questID = tonumber(questID)
  return appendTraceEntry({
    kind = "QUEST_EVENT",
    event = tostring(eventName),
    questID = questID,
    extra = extraInfo,
    context = getInteractionContext(explicitContext),
  })
end

function Diagnostics.RecordManualCompletion(kind, targetItemID, completedTurnIns, remainingTurnIns, explicitContext)
  if not Diagnostics.IsEnabled() then
    return nil
  end
  return appendTraceEntry({
    kind = "MANUAL_COMPLETE",
    event = "USER_COMPLETE_TURNIN",
    goalKind = tostring(kind or "crate"),
    targetItemID = tonumber(targetItemID),
    completedTurnIns = tonumber(completedTurnIns) or 1,
    remainingTurnIns = tonumber(remainingTurnIns) or 0,
    context = getInteractionContext(explicitContext),
  })
end

function Diagnostics.RecordInventoryObservation(sourceEvent, bagCounts, bankCounts, explicitContext)
  if not Diagnostics.IsEnabled() then
    return nil
  end
  bagCounts = bagCounts or {}
  bankCounts = bankCounts or {}

  if Diagnostics.__lastBagCounts == nil then
    Diagnostics.__lastBagCounts = {}
    Diagnostics.__lastBankCounts = {}
    for id, count in pairs(bagCounts) do
      if isRelevantItemID(id) then
        Diagnostics.__lastBagCounts[tonumber(id)] = tonumber(count) or 0
      end
    end
    for id, count in pairs(bankCounts) do
      if isRelevantItemID(id) then
        Diagnostics.__lastBankCounts[tonumber(id)] = tonumber(count) or 0
      end
    end
    return nil
  end

  local seenIDs = {}
  for id, _ in pairs(Diagnostics.__lastBagCounts) do
    seenIDs[tonumber(id)] = true
  end
  for id, _ in pairs(Diagnostics.__lastBankCounts) do
    seenIDs[tonumber(id)] = true
  end
  for id, _ in pairs(bagCounts) do
    if isRelevantItemID(id) then
      seenIDs[tonumber(id)] = true
    end
  end
  for id, _ in pairs(bankCounts) do
    if isRelevantItemID(id) then
      seenIDs[tonumber(id)] = true
    end
  end

  local deltas = {}
  local hasDelta = false
  for id, _ in pairs(seenIDs) do
    local oldBag = Diagnostics.__lastBagCounts[id] or 0
    local newBag = tonumber(bagCounts[id]) or 0
    local oldBank = Diagnostics.__lastBankCounts[id] or 0
    local newBank = tonumber(bankCounts[id]) or 0
    local bagDelta = newBag - oldBag
    local bankDelta = newBank - oldBank

    if bagDelta ~= 0 or bankDelta ~= 0 then
      hasDelta = true
      deltas[id] = {
        itemID = id,
        bagBefore = oldBag,
        bagAfter = newBag,
        bagDelta = bagDelta,
        bankBefore = oldBank,
        bankAfter = newBank,
        bankDelta = bankDelta,
        charDelta = bagDelta + bankDelta,
      }
    end
    Diagnostics.__lastBagCounts[id] = newBag
    Diagnostics.__lastBankCounts[id] = newBank
  end

  if not hasDelta then
    return nil
  end

  return appendTraceEntry({
    kind = "INVENTORY_DELTA",
    event = tostring(sourceEvent or "BAG_UPDATE_DELAYED"),
    deltas = deltas,
    context = getInteractionContext(explicitContext),
  })
end

-- Pure transaction state machine & replay verifier.
-- Evaluates a sequence of recorded trace entries against initial reservations and classifies
-- transitions (`Planned -> Filled`, `Filled -> Delivered`, `Planned -> QuestActive -> Delivered`,
-- `BankMove -> Ignored`, `ManualCompletion -> Idempotent`, `Ambiguous -> Review`)
-- under normal, reversed, delayed, and duplicate event delivery orderings.
function Diagnostics.ReplayTransactions(traceEntries, initialReservations)
  traceEntries = traceEntries or ((ns.State and ns.State.GetDiagnosticTrace and ns.State.GetDiagnosticTrace().entries) or {})
  initialReservations = initialReservations or ((ns.State and ns.State.GetOrderedReservations and ns.State.GetOrderedReservations()) or {})

  local data = ns.Data or {}
  local cratesByID = data.cratesByItemID or {}
  local sealedCratesByID = data.sealedCratesByItemID or {}
  local writsByID = data.writsByItemID or {}
  local deliveryQuestSet = {}
  for _, qID in ipairs(data.sealedCrateDeliveryQuestIDs or { 91899, 91900, 91901, 91904, 91905 }) do
    deliveryQuestSet[tonumber(qID)] = true
  end

  local writByQuestID = {}
  for wID, wRec in pairs(writsByID) do
    if wRec.startQuestID then
      writByQuestID[tonumber(wRec.startQuestID)] = wRec
    end
  end

  -- Clone reservations into mutable simulation state
  local goalStateByKey = {}
  local orderedKeys = {}
  for _, r in ipairs(initialReservations) do
    if type(r) == "table" then
      local kind = r.kind or "crate"
      local targetID = tonumber(r.targetItemID) or 0
      local gKey = r.goalKey or string.format("%s:%d", kind, targetID)
      local uMats = {}
      if r.unitMaterials and #r.unitMaterials > 0 then
        for _, m in ipairs(r.unitMaterials) do
          table.insert(uMats, {
            itemID = tonumber(m.itemID),
            quantity = math.max(1, math.floor(tonumber(m.quantity) or 1)),
          })
        end
      elseif r.materials then
        local q = math.max(1, math.floor(tonumber(r.quantity) or 1))
        for _, m in ipairs(r.materials) do
          local mq = math.max(1, math.floor(tonumber(m.quantity) or 1))
          table.insert(uMats, {
            itemID = tonumber(m.itemID),
            quantity = math.max(1, math.floor(tonumber(m.unitQuantity) or math.floor(mq / q))),
          })
        end
      end

      goalStateByKey[gKey] = {
        goalKey = gKey,
        kind = kind,
        targetItemID = targetID,
        targetName = r.targetName or gKey,
        optionIndex = tonumber(r.optionIndex) or 1,
        plannedCount = math.max(0, math.floor(tonumber(r.quantity) or 1)),
        filledCount = 0,
        questActiveCount = 0,
        deliveredCount = 0,
        manualCompletedCredit = 0,
        unitMaterials = uMats,
      }
      table.insert(orderedKeys, gKey)
    end
  end

  local transactions = {}
  local pendingCrateDeliveryQuests = 0
  local pendingSealedCrateDecrements = {}
  local pendingWritTurnInQuests = {}
  local pendingWritBagDecrements = {}
  local seenEventKeys = {}

  local function recordTx(tx)
    tx.index = #transactions + 1
    table.insert(transactions, tx)
  end

  local function tryReconcileSealedCrateDelivery(seq, timestamp)
    while pendingCrateDeliveryQuests > 0 and #pendingSealedCrateDecrements > 0 do
      pendingCrateDeliveryQuests = pendingCrateDeliveryQuests - 1
      local sealedStep = table.remove(pendingSealedCrateDecrements, 1)

      -- Match against a goal in `filledCount > 0`
      local matchedGoals = {}
      for _, gKey in ipairs(orderedKeys) do
        local gs = goalStateByKey[gKey]
        if gs.kind == "crate" and gs.filledCount > 0 then
          table.insert(matchedGoals, gs)
        end
      end

      if #matchedGoals == 1 then
        local gs = matchedGoals[1]
        gs.filledCount = gs.filledCount - 1
        gs.deliveredCount = gs.deliveredCount + 1
        recordTx({
          seq = seq,
          timestamp = timestamp,
          classification = "Delivered",
          transition = "Filled -> Delivered",
          goalKey = gs.goalKey,
          sealedItemID = sealedStep.sealedItemID,
          questID = sealedStep.questID,
        })
      elseif #matchedGoals > 1 then
        recordTx({
          seq = seq,
          timestamp = timestamp,
          classification = "Ambiguous",
          transition = "Ambiguous -> Review",
          reason = "multiple_filled_crate_goals_match_delivery",
          sealedItemID = sealedStep.sealedItemID,
        })
      else
        recordTx({
          seq = seq,
          timestamp = timestamp,
          classification = "DeliveredUnplanned",
          transition = "Filled -> Delivered",
          sealedItemID = sealedStep.sealedItemID,
        })
      end
    end
  end

  local function tryReconcileWritDelivery(writID, seq, timestamp)
    local wRec = writsByID[writID]
    if not wRec then
      return
    end
    local qID = tonumber(wRec.startQuestID)
    if qID and pendingWritTurnInQuests[qID] and pendingWritBagDecrements[writID] then
      pendingWritTurnInQuests[qID] = nil
      pendingWritBagDecrements[writID] = nil
      local gKey = string.format("writ:%d", writID)
      local gs = goalStateByKey[gKey]
      if gs then
        if gs.manualCompletedCredit > 0 then
          gs.manualCompletedCredit = gs.manualCompletedCredit - 1
          recordTx({
            seq = seq,
            timestamp = timestamp,
            classification = "ManualCompletionDeduped",
            transition = "ManualCompletion -> Idempotent",
            goalKey = gKey,
            questID = qID,
          })
          return
        end
        if gs.questActiveCount > 0 then
          gs.questActiveCount = gs.questActiveCount - 1
        end
        if gs.plannedCount > 0 then
          gs.plannedCount = gs.plannedCount - 1
        end
        gs.deliveredCount = gs.deliveredCount + 1
        recordTx({
          seq = seq,
          timestamp = timestamp,
          classification = "Delivered",
          transition = "QuestActive -> Delivered",
          goalKey = gKey,
          questID = qID,
          writItemID = writID,
        })
      end
    end
  end

  for idx, entry in ipairs(traceEntries) do
    local seq = entry.seq or idx
    local ts = entry.timestamp or idx
    local ctx = entry.context or {}

    if entry.kind == "MANUAL_COMPLETE" then
      local gKey = string.format("%s:%d", tostring(entry.goalKind or "crate"), tonumber(entry.targetItemID) or 0)
      local gs = goalStateByKey[gKey]
      local count = math.max(1, math.floor(tonumber(entry.completedTurnIns) or 1))
      if gs then
        gs.plannedCount = math.max(0, gs.plannedCount - count)
        gs.manualCompletedCredit = gs.manualCompletedCredit + count
      end
      recordTx({
        seq = seq,
        timestamp = ts,
        classification = "ManualCompletion",
        transition = "ManualCompletion -> Idempotent",
        goalKey = gKey,
        completedTurnIns = count,
      })
    elseif entry.kind == "QUEST_EVENT" then
      local ev = tostring(entry.event or "")
      local qID = tonumber(entry.questID)
      -- Deduplicate identical duplicate quest events at the same revision/timestamp
      local dedupKey = string.format("%s:%s:%s", ev, tostring(qID or 0), tostring(entry.DedupeToken or entry.inventoryRevision or seq))
      if ev == "QUEST_TURNED_IN" and qID then
        local TurnInKey = string.format("TURNIN:%d:%s", qID, tostring(entry.turnInInstanceID or "1"))
        if not seenEventKeys[TurnInKey] then
          seenEventKeys[TurnInKey] = true
          if deliveryQuestSet[qID] then
            pendingCrateDeliveryQuests = pendingCrateDeliveryQuests + 1
            tryReconcileSealedCrateDelivery(seq, ts)
          elseif writByQuestID[qID] then
            local wRec = writByQuestID[qID]
            pendingWritTurnInQuests[qID] = true
            tryReconcileWritDelivery(tonumber(wRec.writItemID), seq, ts)
          end
        else
          recordTx({
            seq = seq,
            timestamp = ts,
            classification = "DuplicateIgnored",
            transition = "Duplicate -> Ignored",
            questID = qID,
          })
        end
      elseif ev == "QUEST_ACCEPTED" and qID and writByQuestID[qID] then
        local wRec = writByQuestID[qID]
        local gKey = string.format("writ:%d", tonumber(wRec.writItemID) or 0)
        local gs = goalStateByKey[gKey]
        if gs and gs.plannedCount > gs.questActiveCount then
          gs.questActiveCount = gs.questActiveCount + 1
          recordTx({
            seq = seq,
            timestamp = ts,
            classification = "QuestActive",
            transition = "Planned -> QuestActive",
            goalKey = gKey,
            questID = qID,
          })
        end
      end
    elseif entry.kind == "INVENTORY_DELTA" then
      local deltas = entry.deltas or {}

      -- 1. Check if this delta is purely a bank <-> bag move (`charDelta == 0` for all changed items)
      local allZeroCharDelta = true
      local anyChanged = false
      for _, d in pairs(deltas) do
        anyChanged = true
        if (tonumber(d.charDelta) or (tonumber(d.bagDelta or 0) + tonumber(d.bankDelta or 0))) ~= 0 then
          allZeroCharDelta = false
          break
        end
      end

      if anyChanged and allZeroCharDelta then
        recordTx({
          seq = seq,
          timestamp = ts,
          classification = "BankMove",
          transition = "BankMove -> Ignored",
        })
      else
        -- 2. Check for unsafe interaction contexts (Mail, AH, Merchant, Trade)
        local unsafeSource = (ctx.mailOpen or ctx.ahOpen or ctx.merchantOpen or ctx.tradeOpen)

        -- 3. Check for unopened Waylaid Crate -> Sealed Crate fill transition
        local decreasedCrates = {}
        local increasedSealed = {}
        for itemID, d in pairs(deltas) do
          local id = tonumber(itemID)
          local charDelta = tonumber(d.charDelta) or (tonumber(d.bagDelta or 0) + tonumber(d.bankDelta or 0))
          if cratesByID[id] and charDelta < 0 then
            table.insert(decreasedCrates, { itemID = id, count = -charDelta })
          elseif sealedCratesByID[id] and charDelta > 0 then
            table.insert(increasedSealed, { itemID = id, count = charDelta })
          elseif sealedCratesByID[id] and charDelta < 0 then
            for _ = 1, (-charDelta) do
              table.insert(pendingSealedCrateDecrements, { sealedItemID = id, seq = seq })
            end
          elseif writsByID[id] and charDelta < 0 then
            local wRec = writsByID[id]
            local tID = tonumber(wRec.targetItemID)
            local tDelta = tID and deltas[tID] and (tonumber(deltas[tID].charDelta) or tonumber(deltas[tID].bagDelta) or 0) or 0
            local reqQty = math.max(1, math.floor(tonumber(wRec.quantity) or 1))
            if tDelta <= -reqQty then
              pendingWritBagDecrements[id] = true
              tryReconcileWritDelivery(id, seq, ts)
            end
          end
        end

        if #decreasedCrates > 0 and #increasedSealed > 0 then
          if unsafeSource then
            recordTx({
              seq = seq,
              timestamp = ts,
              classification = "Ambiguous",
              transition = "Ambiguous -> Review",
              reason = "unsafe_interaction_context_during_crate_change",
            })
          elseif #decreasedCrates == 1 and decreasedCrates[1].count == 1 then
            local cID = decreasedCrates[1].itemID
            local gKey = string.format("crate:%d", cID)
            local gs = goalStateByKey[gKey]
            local cRec = cratesByID[cID]

            -- Check how many options of cRec match the consumed materials in `deltas`
            local matchingOptions = {}
            for _, alt in ipairs((cRec and cRec.alternatives) or {}) do
              local allMatsMatch = true
              for _, m in ipairs(alt.materials or {}) do
                local mID = tonumber(m.itemID)
                local req = math.max(1, math.floor(tonumber(m.quantity) or 1))
                local dMat = deltas[mID]
                local mCharDelta = dMat and (tonumber(dMat.charDelta) or tonumber(dMat.bagDelta) or 0) or 0
                if mCharDelta > -req then
                  allMatsMatch = false
                  break
                end
              end
              if allMatsMatch then
                table.insert(matchingOptions, tonumber(alt.optionIndex) or 1)
              end
            end

            if #matchingOptions == 1 then
              if gs then
                if gs.manualCompletedCredit > 0 then
                  gs.manualCompletedCredit = gs.manualCompletedCredit - 1
                  recordTx({
                    seq = seq,
                    timestamp = ts,
                    classification = "ManualCompletionDeduped",
                    transition = "ManualCompletion -> Idempotent",
                    goalKey = gKey,
                    optionIndex = matchingOptions[1],
                  })
                elseif gs.plannedCount > 0 then
                  gs.plannedCount = gs.plannedCount - 1
                  gs.filledCount = gs.filledCount + 1
                  recordTx({
                    seq = seq,
                    timestamp = ts,
                    classification = "Filled",
                    transition = "Planned -> Filled",
                    goalKey = gKey,
                    crateItemID = cID,
                    sealedItemID = increasedSealed[1].itemID,
                    optionIndex = matchingOptions[1],
                  })
                end
              else
                recordTx({
                  seq = seq,
                  timestamp = ts,
                  classification = "FilledUnplanned",
                  transition = "Unplanned -> Filled",
                  crateItemID = cID,
                  sealedItemID = increasedSealed[1].itemID,
                  optionIndex = matchingOptions[1],
                })
              end
            else
              recordTx({
                seq = seq,
                timestamp = ts,
                classification = "Ambiguous",
                transition = "Ambiguous -> Review",
                goalKey = gKey,
                reason = (#matchingOptions == 0) and "no_matching_material_bundle" or "multiple_matching_material_bundles",
              })
            end
          else
            recordTx({
              seq = seq,
              timestamp = ts,
              classification = "Ambiguous",
              transition = "Ambiguous -> Review",
              reason = "multiple_crates_changed_simultaneously",
            })
          end
        end

        if #pendingSealedCrateDecrements > 0 and pendingCrateDeliveryQuests > 0 then
          tryReconcileSealedCrateDelivery(seq, ts)
        end
      end
    end
  end

  return {
    transactions = transactions,
    goalStateByKey = goalStateByKey,
    pendingCrateDeliveryQuests = pendingCrateDeliveryQuests,
    pendingSealedCrateDecrements = #pendingSealedCrateDecrements,
  }
end

function Diagnostics.GetSummary()
  local trace = ns.State and ns.State.GetDiagnosticTrace and ns.State.GetDiagnosticTrace()
  local entries = (trace and trace.entries) or {}
  local replay = Diagnostics.ReplayTransactions(entries)
  return {
    enabled = Diagnostics.IsEnabled(),
    autoMutateReservations = false,
    entryCount = #entries,
    transactionCount = #(replay.transactions or {}),
    transactions = replay.transactions or {},
    entries = entries,
  }
end
