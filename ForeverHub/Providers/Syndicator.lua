local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.Providers = ns.Providers or {}
local SyndicatorProvider = {}
ns.Providers.Syndicator = SyndicatorProvider

-- Parses a BagBrother slot entry string such as "248684;5", "248704", or "9821::::::::32:1482:::1:12719::::::"
-- Returns itemID, quantity, hasInstanceModifiers
function SyndicatorProvider.ParseBrotherSlot(rawEntry)
  if type(rawEntry) ~= "string" then
    return nil, 0, false
  end
  local linkPart, countPart = string.match(rawEntry, "^([^;]+);(%d+)$")
  if not linkPart then
    linkPart = rawEntry
  end
  local itemID = tonumber(string.match(linkPart, "^(%d+):")) or tonumber(string.match(linkPart, "^(%d+)$"))
  if not itemID or itemID <= 0 then
    return nil, 0, false
  end
  local qty = tonumber(countPart) or 1
  if qty <= 0 then
    qty = 1
  end
  -- In BagBrother (caching.lua:295), simple unbound stackable items serialize as bare ID ("2592;20"),
  -- whereas items with instance/enchant/suffix state serialize with ':' payload segments.
  local hasInstanceModifiers = string.find(linkPart, ":", 1, true) ~= nil
  return itemID, qty, hasInstanceModifiers
end

function SyndicatorProvider.HasSyndicator()
  return type(_G.Syndicator) == "table" and type(_G.Syndicator.API) == "table"
end

function SyndicatorProvider.HasBagBrother()
  return type(_G.BrotherBags) == "table"
end

function SyndicatorProvider.GetActiveBackendName()
  if SyndicatorProvider.HasSyndicator() then
    return "Syndicator"
  elseif SyndicatorProvider.HasBagBrother() then
    return "BagBrother"
  end
  return "None"
end

local function isBankContainer(bagKey, bagSlots)
  if type(bagSlots) == "table" and bagSlots.bankType ~= nil then
    -- bankType == 0 is character bank tab in Forever 1.60.1 (bankType == 2 is account bank)
    return bagSlots.bankType == 0
  end
  local k = tonumber(bagKey)
  if not k then
    return false
  end
  return k == -1 or (k >= 6 and k <= 12)
end

local function isPlayerBagContainer(bagKey, bagSlots)
  if type(bagSlots) == "table" and bagSlots.bankType ~= nil then
    return false
  end
  local k = tonumber(bagKey)
  if not k then
    return false
  end
  return k >= 0 and k <= 5
end

-- Classifies transfer eligibility for an item held on an alt character into one of 3 states:
-- "eligible" | "ineligible" | "unknown"
-- Note: BagBrother's ParseItem (caching.lua:277) does NOT store explicit binding state (`explicitIsBound == nil`).
-- Therefore, without explicit `isBound == false`, ONLY items whose compiled `transferPolicy` is
-- `"never_binds_trade_good"` (the 96 verified non-equippable stackable raw trade goods) can be classified
-- `"eligible"` on a confirmed same-realm, same-faction alt. Equippable/instance-bindable writ target items
-- (`transferPolicy == "equippable_or_instance_bindable"`) are classified `"unknown"` unless `explicitIsBound == false`.
function SyndicatorProvider.ClassifyAltTransferEligibility(itemID, curCharFaction, altFaction, hasInstanceModifiers, explicitIsBound)
  local data = ns.Data or {}
  -- 1. Waylaid Crates are strictly Soulbound -> always "ineligible" from alts
  if data.cratesByItemID and data.cratesByItemID[itemID] then
    return "ineligible"
  end
  -- 2. Explicit soulbound flag from provider -> "ineligible"
  if explicitIsBound == true then
    return "ineligible"
  end
  -- 3. Confirmed opposite faction -> "ineligible"
  if curCharFaction ~= nil and altFaction ~= nil and curCharFaction ~= altFaction then
    return "ineligible"
  end
  -- 4. Missing faction metadata on either character -> "unknown" (never default to eligible!)
  if curCharFaction == nil or altFaction == nil then
    return "unknown"
  end
  -- 5. Craftsman's Writs or items with equipment instance modifiers -> "unknown"
  if data.writsByItemID and data.writsByItemID[itemID] then
    return "unknown"
  end
  if hasInstanceModifiers then
    return "unknown"
  end
  -- 6. Check compiled transferPolicy (never conflate `isCrateMaterial` alone with binding policy)
  local matRec = data.materialToCrates and data.materialToCrates[itemID]
  if matRec then
    if matRec.transferPolicy == "soulbound" then
      return "ineligible"
    elseif matRec.transferPolicy == "never_binds_trade_good" then
      return "eligible"
    elseif matRec.transferPolicy == "equippable_or_instance_bindable" then
      if explicitIsBound == false then
        return "eligible"
      end
      return "unknown"
    end
  end
  return "unknown"
end

-- Scans BrotherBags or Syndicator without double-counting current character's live bags.
-- Distinguishes a valid empty current-character bank (`available = true, complete = true, counts = {}`)
-- from an unobserved bank (`available = false, complete = false`).
function SyndicatorProvider.GetAccountSnapshot(overrideCurrentName, overrideCurrentRealm)
  local curName, curRealm = ns.Compat.GetCharacterKey()
  curName = overrideCurrentName or curName
  curRealm = overrideCurrentRealm or curRealm

  local result = {
    backend = SyndicatorProvider.GetActiveBackendName(),
    currentCharBankSnapshot = {
      available = false,
      complete = false,
      observedAt = nil,
      source = "none",
      tabIDs = {},
      counts = {},
    },
    altEligibleTotals = {},
    altUnknownTotals = {},
    altIneligibleTotals = {},
    altSources = {},
  }

  -- 1. BagBrother (_G.BrotherBags) path
  if type(_G.BrotherBags) == "table" then
    local realmTable = _G.BrotherBags[curRealm]
    if type(realmTable) ~= "table" then
      for rKey, rTbl in pairs(_G.BrotherBags) do
        if type(rKey) == "string" and type(rTbl) == "table" and string.lower(rKey) == string.lower(curRealm) then
          realmTable = rTbl
          break
        end
      end
    end

    if type(realmTable) == "table" then
      local curCharFaction = ns.Compat.GetCurrentFaction()
      if curCharFaction == nil and type(realmTable[curName]) == "table" then
        curCharFaction = realmTable[curName].faction
      end

      for charName, charData in pairs(realmTable) do
        if type(charData) == "table" then
          local isCurrentChar = (charName == curName)
          local altFaction = charData.faction

          local observedBankTabCount = 0
          local validBankTabCount = 0
          local observedBankTabSet = {}

          for bagKey, bagSlots in pairs(charData) do
            if type(bagSlots) == "table" then
              local inBank = isBankContainer(bagKey, bagSlots)
              local inBags = isPlayerBagContainer(bagKey, bagSlots)
              if inBank or inBags then
                if isCurrentChar and inBank then
                  observedBankTabCount = observedBankTabCount + 1
                  local tabID = tonumber(bagSlots.ID or bagKey)
                  local tabSize = tonumber(bagSlots.size)
                  -- Require positive size and valid tab ID before considering the tab complete
                  if tabID ~= nil and ((tabSize ~= nil and tabSize > 0) or (tabSize == nil and type(bagSlots.items) == "table")) then
                    validBankTabCount = validBankTabCount + 1
                    observedBankTabSet[tabID] = true
                    table.insert(result.currentCharBankSnapshot.tabIDs, tabID)
                  end
                end

                local slotTable = (type(bagSlots.items) == "table") and bagSlots.items or bagSlots
                local perBagItems = {}
                for slotKey, rawSlot in pairs(slotTable) do
                  if type(slotKey) == "number" and type(rawSlot) == "string" then
                    local itemID, qty, hasMods = SyndicatorProvider.ParseBrotherSlot(rawSlot)
                    if itemID and qty > 0 then
                      local entry = perBagItems[itemID]
                      if not entry then
                        entry = { qty = 0, hasMods = false }
                        perBagItems[itemID] = entry
                      end
                      entry.qty = entry.qty + qty
                      if hasMods then
                        entry.hasMods = true
                      end
                    end
                  end
                end

                for itemID, info in pairs(perBagItems) do
                  local qty = info.qty
                  if isCurrentChar then
                    -- Only record bank for current character; live bags come from Providers.Inventory.ScanLiveBags()
                    if inBank then
                      local cMap = result.currentCharBankSnapshot.counts
                      cMap[itemID] = (cMap[itemID] or 0) + qty
                    end
                  else
                    local eligState = SyndicatorProvider.ClassifyAltTransferEligibility(
                      itemID,
                      curCharFaction,
                      altFaction,
                      info.hasMods
                    )
                    if eligState == "eligible" then
                      result.altEligibleTotals[itemID] = (result.altEligibleTotals[itemID] or 0) + qty
                    elseif eligState == "ineligible" then
                      result.altIneligibleTotals[itemID] = (result.altIneligibleTotals[itemID] or 0) + qty
                    else
                      result.altUnknownTotals[itemID] = (result.altUnknownTotals[itemID] or 0) + qty
                    end

                    result.altSources[itemID] = result.altSources[itemID] or {}
                    table.insert(result.altSources[itemID], {
                      character = charName,
                      realm = curRealm,
                      location = inBank and "bank" or "bags",
                      quantity = qty,
                      transferState = eligState,
                      transferEligible = (eligState == "eligible"),
                    })
                  end
                end
              end
            end
          end

          if isCurrentChar and observedBankTabCount > 0 and validBankTabCount == observedBankTabCount then
            table.sort(result.currentCharBankSnapshot.tabIDs)
            -- Verify contiguous purchased character bank tab IDs (6 .. 6 + N - 1) or legacy main bank (-1)
            local contiguous = true
            if not observedBankTabSet[-1] then
              for expectedTabID = 6, 6 + validBankTabCount - 1 do
                if not observedBankTabSet[expectedTabID] then
                  contiguous = false
                  break
                end
              end
            end
            if contiguous then
              result.currentCharBankSnapshot.available = true
              result.currentCharBankSnapshot.complete = true
              result.currentCharBankSnapshot.observedAt = nil
              result.currentCharBankSnapshot.source = "bagbrother"
            end
          end
        end
      end
    end
    return result
  end

  -- 2. Syndicator (_G.Syndicator.API) path if installed
  if SyndicatorProvider.HasSyndicator() then
    local api = _G.Syndicator.API
    if type(api.GetAllCharacters) == "function" and type(api.GetCharacter) == "function" then
      local okChars, allChars = pcall(api.GetAllCharacters)
      if okChars and type(allChars) == "table" then
        local curFull = string.format("%s-%s", curName, curRealm)
        local curCharFaction = ns.Compat.GetCurrentFaction()
        for _, fullKey in ipairs(allChars) do
          local okChar, cData = pcall(api.GetCharacter, fullKey)
          if okChar and type(cData) == "table" then
            local cName = (cData.details and cData.details.character) or fullKey
            local cRealm = (cData.details and cData.details.realm) or curRealm
            local altFaction = nil
            if cData.details and cData.details.faction then
              if cData.details.faction == "Alliance" or cData.details.faction == true then
                altFaction = true
              elseif cData.details.faction == "Horde" or cData.details.faction == false then
                altFaction = false
              end
            end
            if string.lower(tostring(cRealm)) == string.lower(tostring(curRealm)) then
              local isCurrentChar = (cName == curName) or (fullKey == curFull)
              if isCurrentChar and type(cData.bank) == "table" and #cData.bank > 0 then
                result.currentCharBankSnapshot.available = true
                result.currentCharBankSnapshot.complete = true
                result.currentCharBankSnapshot.source = "syndicator"
              end

              local function countContainerGroup(groupContainers, locLabel)
                if type(groupContainers) ~= "table" then
                  return
                end
                local tally = {}
                for _, bag in ipairs(groupContainers) do
                  if type(bag) == "table" then
                    for _, slot in ipairs(bag) do
                      if type(slot) == "table" and slot.itemID and (slot.itemCount or 0) > 0 then
                        local e = tally[slot.itemID]
                        if not e then
                          e = { qty = 0, anyBound = false, allKnownUnbound = true }
                          tally[slot.itemID] = e
                        end
                        e.qty = e.qty + slot.itemCount
                        if slot.isBound == true then
                          e.anyBound = true
                          e.allKnownUnbound = false
                        elseif slot.isBound == nil then
                          e.allKnownUnbound = false
                        end
                      end
                    end
                  end
                end
                for itemID, info in pairs(tally) do
                  if isCurrentChar then
                    if locLabel == "bank" then
                      local cMap = result.currentCharBankSnapshot.counts
                      cMap[itemID] = (cMap[itemID] or 0) + info.qty
                    end
                  else
                    local explicitBound = nil
                    if info.anyBound then
                      explicitBound = true
                    elseif info.allKnownUnbound then
                      explicitBound = false
                    end
                    local eligState = SyndicatorProvider.ClassifyAltTransferEligibility(
                      itemID,
                      curCharFaction,
                      altFaction,
                      false,
                      explicitBound
                    )
                    if eligState == "eligible" then
                      result.altEligibleTotals[itemID] = (result.altEligibleTotals[itemID] or 0) + info.qty
                    elseif eligState == "ineligible" then
                      result.altIneligibleTotals[itemID] = (result.altIneligibleTotals[itemID] or 0) + info.qty
                    else
                      result.altUnknownTotals[itemID] = (result.altUnknownTotals[itemID] or 0) + info.qty
                    end
                    result.altSources[itemID] = result.altSources[itemID] or {}
                    table.insert(result.altSources[itemID], {
                      character = cName,
                      realm = cRealm,
                      location = locLabel,
                      quantity = info.qty,
                      transferState = eligState,
                      transferEligible = (eligState == "eligible"),
                    })
                  end
                end
              end
              countContainerGroup(cData.bags, "bags")
              countContainerGroup(cData.bank, "bank")
            end
          end
        end
      end
    end
  end

  return result
end
