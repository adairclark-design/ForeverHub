local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.Domain = ns.Domain or {}

local RewardValue = {}
ns.Domain.RewardValue = RewardValue

local SILK_CLOTH_ITEM_ID = 4306
local SILK_PER_HEAVY_BANDAGE = 2
local HEAVY_SILK_BANDAGE_VENDOR_COPPER = 400 -- 4s per Heavy Silk Bandage (2s per Silk; 20 Silk -> 10 bandages = 40s)

-- Pure First Aid Silk Cloth conversion calculator (Astra Economic Fix & Gate 8).
-- 20 unreserved Silk Cloth -> 10 Heavy Silk Bandages -> 40s (4000c) vendor value.
-- Reserved Silk Cloth is strictly excluded.
function RewardValue.EvaluateSilkBandageConversion(silkMaterialStatus)
  if type(silkMaterialStatus) ~= "table" then
    return nil
  end
  local charOwned = math.max(0, math.floor(tonumber(silkMaterialStatus.charOwned) or 0))
  local reservedTotal = math.max(0, math.floor(tonumber(silkMaterialStatus.reservedTotal) or 0))
  local freeBags = tonumber(silkMaterialStatus.freeBags)
  local freeBank = tonumber(silkMaterialStatus.freeBank)
  local unreservedTotal
  if freeBags ~= nil or freeBank ~= nil then
    unreservedTotal = math.max(0, math.floor((tonumber(freeBags) or 0) + (tonumber(freeBank) or 0)))
  else
    unreservedTotal = math.max(0, charOwned - reservedTotal)
  end
  local unreservedBags = math.max(0, math.floor(tonumber(freeBags) or math.min(unreservedTotal, charOwned)))
  local bandagesFromUnreserved = math.floor(unreservedTotal / SILK_PER_HEAVY_BANDAGE)
  local silkUsed = bandagesFromUnreserved * SILK_PER_HEAVY_BANDAGE
  local leftoverUnreservedSilk = unreservedTotal - silkUsed
  local vendorCopperFromBandages = bandagesFromUnreserved * HEAVY_SILK_BANDAGE_VENDOR_COPPER

  return {
    itemID = SILK_CLOTH_ITEM_ID,
    charOwned = charOwned,
    reservedTotal = reservedTotal,
    unreservedBags = unreservedBags,
    unreservedSilk = unreservedTotal,
    unreservedTotal = unreservedTotal,
    silkPerBandage = SILK_PER_HEAVY_BANDAGE,
    unitBandageVendorCopper = HEAVY_SILK_BANDAGE_VENDOR_COPPER,
    bandagesCraftable = bandagesFromUnreserved,
    silkConsumed = silkUsed,
    silkConvertible = silkUsed,
    leftoverUnreservedSilk = leftoverUnreservedSilk,
    vendorCopper = vendorCopperFromBandages,
    realizableVendorCopper = vendorCopperFromBandages,
  }
end

-- Pure quantity-aware quest reward vendor-value comparison (Astra P1-H).
-- Compares `stackQuantity * unitSellPrice`.
-- Never selects by armor/weapon type, never treats missing/loading prices as 0c,
-- and explicitly labels partial pricing as "Highest value among priced rewards".
function RewardValue.EvaluateRewardChoices(choicesSnapshot, priceLookupFn)
  if type(choicesSnapshot) ~= "table" or choicesSnapshot.status ~= "ok" then
    return {
      status = "unavailable",
      headlineLabel = "Quest reward choices unavailable",
      choices = {},
      bestChoices = {},
      pendingItemIDs = {},
      pricedCount = 0,
      unresolvedCount = 0,
    }
  end

  local rawChoices = choicesSnapshot.choices or {}
  if #rawChoices <= 1 then
    return {
      status = "no_choice",
      headlineLabel = (#rawChoices == 1) and "Single reward (no vendor comparison needed)" or "No selectable item rewards",
      questID = choicesSnapshot.questID,
      questTitle = choicesSnapshot.questTitle,
      choices = {},
      bestChoices = {},
      pendingItemIDs = {},
      pricedCount = 0,
      unresolvedCount = 0,
    }
  end

  priceLookupFn = priceLookupFn or function(itemIDOrLink)
    return ns.Compat.GetItemSellPriceResult(itemIDOrLink)
  end

  local evaluated = {}
  local pendingItemIDs = {}
  local pendingSeen = {}
  local pricedCount = 0
  local unresolvedCount = 0
  local maxVendorCopper = nil

  for idx, c in ipairs(rawChoices) do
    local choiceIndex = tonumber(c.choiceIndex) or idx
    local qty = math.max(1, math.floor(tonumber(c.quantity) or 1))
    local itemID = tonumber(c.itemID) or (ns.Compat and ns.Compat.ExtractItemID(c.itemLink))
    local pRes = priceLookupFn(c.itemLink or itemID)

    local unitSellPrice = nil
    local totalVendorCopper = nil
    local priceState = (type(pRes) == "table" and pRes.status) or "unknown"
    local resolvedName = c.name or (type(pRes) == "table" and pRes.itemName) or (itemID and ("Item #" .. tostring(itemID))) or ("Choice #" .. tostring(choiceIndex))

    if priceState == "ok" and type(pRes.unitSellPrice) == "number" then
      unitSellPrice = math.max(0, math.floor(pRes.unitSellPrice))
      totalVendorCopper = qty * unitSellPrice
      pricedCount = pricedCount + 1
      if maxVendorCopper == nil or totalVendorCopper > maxVendorCopper then
        maxVendorCopper = totalVendorCopper
      end
    else
      unresolvedCount = unresolvedCount + 1
      if priceState == "loading" and itemID and not pendingSeen[itemID] then
        pendingSeen[itemID] = true
        table.insert(pendingItemIDs, itemID)
      end
    end

    table.insert(evaluated, {
      choiceIndex = choiceIndex,
      itemID = itemID,
      itemLink = c.itemLink,
      name = resolvedName,
      quantity = qty,
      priceState = priceState,
      unitSellPrice = unitSellPrice,
      totalVendorCopper = totalVendorCopper,
      isBestVendor = false,
    })
  end

  table.sort(evaluated, function(a, b)
    return a.choiceIndex < b.choiceIndex
  end)

  local bestChoices = {}
  if maxVendorCopper ~= nil and maxVendorCopper > 0 then
    for _, row in ipairs(evaluated) do
      if row.totalVendorCopper == maxVendorCopper then
        row.isBestVendor = true
        table.insert(bestChoices, row)
      end
    end
  elseif maxVendorCopper == 0 and unresolvedCount == 0 then
    -- All rewards confirmed 0c vendor value (unsellable quest items)
    bestChoices = {}
  end

  local isTie = (#bestChoices > 1)
  local status, headlineLabel
  if pricedCount == 0 then
    status = (#pendingItemIDs > 0) and "loading" or "unpriced"
    headlineLabel = (#pendingItemIDs > 0) and "Loading reward vendor prices..." or "Vendor prices unavailable"
  elseif unresolvedCount > 0 then
    status = "partial"
    headlineLabel = "Highest value among priced rewards"
  elseif maxVendorCopper == 0 then
    status = "complete_zero"
    headlineLabel = "All rewards have 0c vendor sell price"
  else
    status = "complete"
    headlineLabel = isTie and "Tied highest vendor value" or "Highest vendor value"
  end

  return {
    status = status,
    headlineLabel = headlineLabel,
    questID = choicesSnapshot.questID,
    questTitle = choicesSnapshot.questTitle,
    choices = evaluated,
    bestChoices = bestChoices,
    bestVendorCopper = maxVendorCopper,
    isTie = isTie,
    pendingItemIDs = pendingItemIDs,
    pricedCount = pricedCount,
    unresolvedCount = unresolvedCount,
  }
end

-- Pure mount shortfall & session coin delta calculator for `/fh mount` (Astra P1-10 & Gate 8).
-- 90g (900,000c) is Forever's discounted riding model with the first basic racial mount included
-- (kept as `unconfirmed_default` until user-confirmed; never "72g + 18g").
function RewardValue.EvaluateMountShortfall(moneyResult, mountTracker, silkMaterialStatus, sessionStartCopper)
  local mt = type(mountTracker) == "table" and mountTracker or {}
  local targetCopper = math.max(0, math.floor(tonumber(mt.trainerQuoteCopper) or 900000))
  local reserveCopper = math.max(0, math.floor(tonumber(mt.cashReserveCopper) or 0))
  local requiredTotalCopper = targetCopper + reserveCopper
  local quoteStatus = (mt.quoteStatus == "user_confirmed") and "user_confirmed" or "unconfirmed_default"
  local reserveExplicitlySet = (mt.reserveExplicitlySet == true) or (reserveCopper > 0)
  local zeroReserveWarning = (reserveCopper == 0)

  if type(moneyResult) ~= "table" or moneyResult.status ~= "ok" or type(moneyResult.copper) ~= "number" then
    return {
      status = "unavailable",
      targetCopper = targetCopper,
      reserveCopper = reserveCopper,
      requiredTotalCopper = requiredTotalCopper,
      standingLabel = mt.standingLabel or "Honored (Default)",
      quoteSource = mt.quoteSource or "default_90g_unconfirmed",
      quoteStatus = quoteStatus,
      reserveExplicitlySet = reserveExplicitlySet,
      zeroReserveWarning = zeroReserveWarning,
      playerRaceToken = mt.playerRaceToken or "UNKNOWN",
      trainerFaction = mt.trainerFaction or "HomeRacialFaction",
    }
  end

  local currentCopper = math.max(0, math.floor(moneyResult.copper))
  local spendableCopper = math.max(0, currentCopper - reserveCopper)
  local shortfallCopper = math.max(0, targetCopper - spendableCopper)
  local surplusCopper = math.max(0, spendableCopper - targetCopper)

  local sessionDeltaCopper = nil
  if type(sessionStartCopper) == "number" then
    sessionDeltaCopper = currentCopper - math.floor(sessionStartCopper)
  end

  local silkSummary = RewardValue.EvaluateSilkBandageConversion(silkMaterialStatus)

  return {
    status = "ok",
    currentCopper = currentCopper,
    spendableCopper = spendableCopper,
    targetCopper = targetCopper,
    reserveCopper = reserveCopper,
    requiredTotalCopper = requiredTotalCopper,
    shortfallCopper = shortfallCopper,
    surplusCopper = surplusCopper,
    canAffordNow = (shortfallCopper == 0),
    standingLabel = mt.standingLabel or "Honored (Default)",
    quoteSource = mt.quoteSource or "default_90g_unconfirmed",
    quoteStatus = quoteStatus,
    reserveExplicitlySet = reserveExplicitlySet,
    zeroReserveWarning = zeroReserveWarning,
    playerRaceToken = mt.playerRaceToken or "UNKNOWN",
    trainerFaction = mt.trainerFaction or "HomeRacialFaction",
    sessionDeltaCopper = sessionDeltaCopper,
    silkStatus = silkSummary,
  }
end
