local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
local Compat = ns.Compat or {}
ns.Compat = Compat

function Compat.GetContainerNumSlots(bagID)
  if C_Container and C_Container.GetContainerNumSlots then
    return C_Container.GetContainerNumSlots(bagID) or 0
  elseif GetContainerNumSlots then
    return GetContainerNumSlots(bagID) or 0
  end
  return 0
end

function Compat.GetContainerItemInfo(bagID, slotID)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(bagID, slotID)
    if not info then
      return nil
    end
    local itemID = info.itemID
    if not itemID and type(info.hyperlink) == "string" then
      itemID = tonumber(string.match(info.hyperlink, "item:(%d+)"))
    end
    return {
      itemID = itemID,
      stackCount = info.stackCount or 1,
      hyperlink = info.hyperlink,
      iconFileID = info.iconFileID,
      -- Preserve nil when binding state is unknown; never coerce nil to false
      isBound = info.isBound,
      hasItem = true,
    }
  elseif GetContainerItemInfo then
    local icon, itemCount, _, _, _, _, itemLink, _, _, itemID, isBound = GetContainerItemInfo(bagID, slotID)
    if not icon and not itemLink and not itemID then
      return nil
    end
    if not itemID and itemLink then
      itemID = tonumber(string.match(itemLink, "item:(%d+)"))
    end
    return {
      itemID = itemID,
      stackCount = itemCount or 1,
      hyperlink = itemLink,
      iconFileID = icon,
      -- Preserve nil when binding state is unknown; never coerce nil to false
      isBound = isBound,
      hasItem = true,
    }
  end
  return nil
end

-- Capability-detected bank container enumeration (matches BagBrother caching.lua:246 & Forever BankDocumentation)
function Compat.CanViewCharacterBank()
  if not (ns.State and ns.State.bankOpen) then
    return false
  end
  if C_Bank and type(C_Bank.CanViewBank) == "function" then
    local ok, canView = pcall(C_Bank.CanViewBank, 0)
    if ok then
      return canView == true
    end
    return false
  end
  return true
end

function Compat.GetPurchasedBankTabIDs()
  if C_Bank and type(C_Bank.FetchPurchasedBankTabData) == "function" then
    local hasNumAPI = type(C_Bank.FetchNumPurchasedBankTabs) == "function"
    local okNum, expectedNum = false, nil
    if hasNumAPI then
      okNum, expectedNum = pcall(C_Bank.FetchNumPurchasedBankTabs, 0)
      if not okNum or type(expectedNum) ~= "number" or expectedNum < 0 then
        return {
          mode = "bank_tabs",
          available = false,
          complete = false,
          confirmedZeroTabs = false,
          tabIDs = {},
          reason = "num_tabs_unavailable",
        }
      end
    end

    local ok, tabs = pcall(C_Bank.FetchPurchasedBankTabData, 0)
    -- When modern bank-tab capability is present, API failure MUST return unavailable/incomplete
    -- and MUST NOT fall back to legacy -1, 5..11 container indices.
    if not ok or type(tabs) ~= "table" then
      return {
        mode = "bank_tabs",
        available = false,
        complete = false,
        confirmedZeroTabs = false,
        tabIDs = {},
        reason = "fetch_tabs_failed",
      }
    end

    local ids = {}
    for _, tab in ipairs(tabs) do
      if type(tab) == "table" and tonumber(tab.ID) then
        table.insert(ids, tonumber(tab.ID))
      else
        return {
          mode = "bank_tabs",
          available = false,
          complete = false,
          confirmedZeroTabs = false,
          tabIDs = {},
          reason = "malformed_tab_entry",
        }
      end
    end

    if expectedNum ~= nil and #ids ~= expectedNum then
      return {
        mode = "bank_tabs",
        available = false,
        complete = false,
        confirmedZeroTabs = false,
        tabIDs = ids,
        reason = "tab_count_mismatch",
      }
    end

    if #ids == 0 then
      -- Distinguish confirmed 0 purchased tabs from an unconfirmed empty table
      if hasNumAPI and expectedNum == 0 then
        return {
          mode = "bank_tabs",
          available = true,
          complete = true,
          confirmedZeroTabs = true,
          tabIDs = {},
        }
      elseif not hasNumAPI then
        return {
          mode = "bank_tabs",
          available = false,
          complete = false,
          confirmedZeroTabs = false,
          tabIDs = {},
          reason = "unconfirmed_zero_tabs",
        }
      end
    end

    return {
      mode = "bank_tabs",
      available = true,
      complete = true,
      confirmedZeroTabs = false,
      tabIDs = ids,
    }
  end

  -- Separate legacy fallback ONLY when C_Bank.FetchPurchasedBankTabData capability is absent
  local legacyIDs = { -1 }
  local firstBank = (tonumber(_G.NUM_BAG_SLOTS) or 4) + 1
  local lastBank = firstBank + (tonumber(_G.NUM_BANKBAGSLOTS) or 7) - 1
  for bagID = firstBank, lastBank do
    table.insert(legacyIDs, bagID)
  end
  return {
    mode = "legacy_bank",
    available = true,
    complete = true,
    confirmedZeroTabs = false,
    tabIDs = legacyIDs,
  }
end

function Compat.ExtractItemID(itemLinkOrString)
  if itemLinkOrString == nil or Compat.IsSecretOrRestrictedValue(itemLinkOrString) then
    return nil
  end
  if type(itemLinkOrString) == "number" then
    if itemLinkOrString ~= itemLinkOrString or itemLinkOrString <= 0 or itemLinkOrString >= math.huge then
      return nil
    end
    return math.floor(itemLinkOrString)
  end
  if type(itemLinkOrString) ~= "string" then
    return nil
  end
  local id = string.match(itemLinkOrString, "item:(%d+)")
  if id then
    local n = tonumber(id)
    return (n and n > 0) and math.floor(n) or nil
  end
  local bare = string.match(itemLinkOrString, "^(%d+):") or string.match(itemLinkOrString, "^(%d+)$")
  if bare then
    local n = tonumber(bare)
    return (n and n > 0) and math.floor(n) or nil
  end
  return nil
end

function Compat.ResolveItemName(itemID, fallbackName)
  itemID = tonumber(itemID)
  if not itemID then
    return fallbackName
  end
  if C_Item and type(C_Item.GetItemNameByID) == "function" then
    local ok, name = pcall(C_Item.GetItemNameByID, itemID)
    if ok and type(name) == "string" and name ~= "" then
      return name
    end
  end
  if type(GetItemInfo) == "function" then
    local ok, name = pcall(GetItemInfo, itemID)
    if ok and type(name) == "string" and name ~= "" then
      return name
    end
  end
  local data = ns.Data
  if data then
    if data.materialToCrates and data.materialToCrates[itemID] and data.materialToCrates[itemID].name then
      return data.materialToCrates[itemID].name
    end
    if data.cratesByItemID and data.cratesByItemID[itemID] and data.cratesByItemID[itemID].name then
      return data.cratesByItemID[itemID].name
    end
    if data.writsByItemID and data.writsByItemID[itemID] and data.writsByItemID[itemID].name then
      return data.writsByItemID[itemID].name
    end
    if data.sealedCratesByItemID and data.sealedCratesByItemID[itemID] and data.sealedCratesByItemID[itemID].name then
      return data.sealedCratesByItemID[itemID].name
    end
    if data.shippingLabelsByItemID and data.shippingLabelsByItemID[itemID] and data.shippingLabelsByItemID[itemID].name then
      return data.shippingLabelsByItemID[itemID].name
    end
    if data.sealedWritsByItemID and data.sealedWritsByItemID[itemID] and data.sealedWritsByItemID[itemID].name then
      return data.sealedWritsByItemID[itemID].name
    end
  end
  if type(fallbackName) == "string" and fallbackName ~= "" and not string.match(fallbackName, "^Item %d+$") then
    return fallbackName
  end
  return nil
end

function Compat.GetClientLocale()
  if ns.State and type(ns.State.overrideClientLocale) == "string" and ns.State.overrideClientLocale ~= "" then
    return ns.State.overrideClientLocale
  end
  local getLoc = _G.GetLocale
  if type(getLoc) == "function" then
    local ok, loc = pcall(getLoc)
    if ok and not Compat.IsSecretOrRestrictedValue(loc) and type(loc) == "string" and loc ~= "" then
      return loc
    end
  end
  return nil
end

-- Resolves an item name safe for exact client-locale Auction House searches (`isExact = true`).
-- Never substitutes English static catalog names on non-English clients (`deDE`, `esMX`, `frFR`, etc.):
-- when the live client item cache is cold, requests async load via `C_Item.RequestLoadItemDataByID`
-- and returns `(nil, "pending_item_cache")` so callers mark the entry `pending` instead of emitting
-- a wrong-language search.
function Compat.ResolveClientLocalizedItemName(itemID, fallbackName, entryOpts)
  itemID = tonumber(itemID)
  local cItem = _G.C_Item
  local getItemInfoFn = _G.GetItemInfo
  local hasLiveItemAPI = (
    (not Compat.IsSecretOrRestrictedValue(cItem))
    and type(cItem) == "table"
    and type(cItem.GetItemNameByID) == "function"
  ) or (type(getItemInfoFn) == "function")

  if itemID and itemID > 0 then
    if (not Compat.IsSecretOrRestrictedValue(cItem)) and type(cItem) == "table" and type(cItem.GetItemNameByID) == "function" then
      local ok, name = pcall(cItem.GetItemNameByID, itemID)
      if ok and not Compat.IsSecretOrRestrictedValue(name) and type(name) == "string" and name ~= "" then
        return name, "resolved_live"
      end
    end
    if type(getItemInfoFn) == "function" then
      local ok, name = pcall(getItemInfoFn, itemID)
      if ok and not Compat.IsSecretOrRestrictedValue(name) and type(name) == "string" and name ~= "" then
        return name, "resolved_live"
      end
    end
  end

  if hasLiveItemAPI then
    if itemID and itemID > 0 and (not Compat.IsSecretOrRestrictedValue(cItem)) and type(cItem) == "table" and type(cItem.RequestLoadItemDataByID) == "function" then
      pcall(cItem.RequestLoadItemDataByID, itemID)
    end
    local locale = Compat.GetClientLocale()
    local isEnglishLocale = (locale == nil or locale == "enUS" or locale == "enGB")
    if entryOpts and entryOpts.requireLiveCache == true then
      return nil, "pending_item_cache"
    end
    if not isEnglishLocale then
      if entryOpts and entryOpts.nameLocale == locale and type(fallbackName) == "string" and fallbackName ~= "" and not string.match(fallbackName, "^Item %d+$") then
        return fallbackName, "resolved_explicit_locale"
      end
      return nil, "pending_item_cache"
    end
    local enName = Compat.ResolveItemName(itemID, fallbackName)
    if enName and enName ~= "" then
      return enName, "resolved_english_fallback"
    end
    if itemID and itemID > 0 then
      return nil, "pending_item_cache"
    end
    return nil, "unresolved_item_name"
  end

  local resolved = Compat.ResolveItemName(itemID, fallbackName)
  if resolved and resolved ~= "" then
    return resolved, "resolved_headless_fallback"
  end
  return nil, "unresolved_item_name"
end

function Compat.GetPlayerLevel()
  if ns.State and type(ns.State.overridePlayerLevel) == "number" then
    return math.max(1, math.floor(ns.State.overridePlayerLevel))
  end
  if type(UnitLevel) == "function" then
    local ok, lvl = pcall(UnitLevel, "player")
    if ok and type(lvl) == "number" and lvl > 0 then
      return math.floor(lvl)
    end
  end
  return 60
end

function Compat.IsOnQuest(questID)
  questID = tonumber(questID)
  if not questID then
    return false
  end
  if ns.State and type(ns.State.overrideActiveQuests) == "table" then
    return ns.State.overrideActiveQuests[questID] == true
  end
  if C_QuestLog and type(C_QuestLog.IsOnQuest) == "function" then
    local ok, onQuest = pcall(C_QuestLog.IsOnQuest, questID)
    if ok then
      return onQuest == true
    end
  end
  if type(GetNumQuestLogEntries) == "function" and type(GetQuestLogTitle) == "function" then
    local numEntries = GetNumQuestLogEntries() or 0
    for i = 1, numEntries do
      local _, _, _, isHeader, _, _, _, qID = GetQuestLogTitle(i)
      if not isHeader and tonumber(qID) == questID then
        return true
      end
    end
  end
  return false
end

function Compat.IsInCombat()
  if ns.State and ns.State.overrideInCombat ~= nil then
    return ns.State.overrideInCombat == true
  end
  if type(InCombatLockdown) == "function" then
    return InCombatLockdown() == true
  end
  return false
end

function Compat.HasCursorItem()
  if ns.State and ns.State.overrideHasCursorItem ~= nil then
    return ns.State.overrideHasCursorItem == true
  end
  if type(CursorHasItem) == "function" then
    return CursorHasItem() == true
  end
  return false
end

function Compat.IsContainerItemLocked(bagID, slotID)
  if ns.State and type(ns.State.overrideLockedSlots) == "table" then
    local key = string.format("%d:%d", tonumber(bagID) or 0, tonumber(slotID) or 0)
    if ns.State.overrideLockedSlots[key] ~= nil then
      return ns.State.overrideLockedSlots[key] == true
    end
  end
  if C_Container and type(C_Container.GetContainerItemInfo) == "function" then
    local info = C_Container.GetContainerItemInfo(bagID, slotID)
    if info and info.isLocked ~= nil then
      return info.isLocked == true
    end
  elseif type(GetContainerItemInfo) == "function" then
    local _, _, locked = GetContainerItemInfo(bagID, slotID)
    return locked == true or locked == 1
  end
  return false
end

function Compat.GetItemMaxStack(itemID)
  itemID = tonumber(itemID)
  if not itemID then
    return 1
  end
  if ns.State and type(ns.State.overrideMaxStackByItemID) == "table" and ns.State.overrideMaxStackByItemID[itemID] then
    return math.max(1, math.floor(tonumber(ns.State.overrideMaxStackByItemID[itemID]) or 1))
  end
  if C_Item and type(C_Item.GetItemMaxStackSizeByID) == "function" then
    local ok, maxStack = pcall(C_Item.GetItemMaxStackSizeByID, itemID)
    if ok and type(maxStack) == "number" and maxStack > 0 then
      return math.floor(maxStack)
    end
  end
  if type(GetItemInfo) == "function" then
    local ok, _, _, _, _, _, _, _, itemStackCount = pcall(GetItemInfo, itemID)
    if ok and type(itemStackCount) == "number" and itemStackCount > 0 then
      return math.floor(itemStackCount)
    end
  end
  local data = ns.Data
  if data then
    if (data.cratesByItemID and data.cratesByItemID[itemID]) or (data.writsByItemID and data.writsByItemID[itemID]) then
      return 20
    end
    if data.materialTransferPolicyByItemID and data.materialTransferPolicyByItemID[itemID] == "never_binds_trade_good" then
      return 200
    end
  end
  return 20
end

function Compat.UseContainerItem(bagID, slotID)
  if ns.State and type(ns.State.overrideUseContainerItem) == "function" then
    return ns.State.overrideUseContainerItem(bagID, slotID)
  end
  if C_Container and type(C_Container.UseContainerItem) == "function" then
    C_Container.UseContainerItem(bagID, slotID)
    return true
  elseif type(UseContainerItem) == "function" then
    UseContainerItem(bagID, slotID)
    return true
  end
  return false
end

function Compat.IsFiniteNumber(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- Pure integer copper formatting (1g = 10000c, 1s = 100c)
function Compat.FormatCopper(copper)
  if not Compat.IsFiniteNumber(copper) then
    return "unknown"
  end
  local c = math.floor(copper + 0.5)
  if c < 0 then
    c = 0
  end
  local gold = math.floor(c / 10000)
  local silver = math.floor((c % 10000) / 100)
  local remCopper = c % 100

  local parts = {}
  if gold > 0 then
    table.insert(parts, string.format("|cffffd700%dg|r", gold))
  end
  if silver > 0 or (gold > 0 and remCopper > 0) then
    table.insert(parts, string.format("|cffc7c7cf%ds|r", silver))
  end
  if remCopper > 0 or #parts == 0 then
    table.insert(parts, string.format("|cffeda55f%dc|r", remCopper))
  end
  return table.concat(parts, " ")
end

function Compat.FormatSignedCopper(copper, includePlus)
  if not Compat.IsFiniteNumber(copper) then
    return "unknown"
  end
  local rounded = math.floor(math.abs(copper) + 0.5)
  if copper < 0 and rounded > 0 then
    return "|cffff6666-|r" .. Compat.FormatCopper(rounded)
  elseif includePlus and rounded > 0 then
    return "+" .. Compat.FormatCopper(rounded)
  end
  return Compat.FormatCopper(rounded)
end

function Compat.GetCharacterKey()
  local name = (ns.State and ns.State.overrideCharName) or (UnitName and UnitName("player")) or "Unknown"
  local realm = (ns.State and ns.State.overrideRealmName) or (GetRealmName and GetRealmName()) or "forever"
  return name, realm, string.format("%s-%s", name, realm)
end

function Compat.GetCurrentFaction()
  if ns.State and ns.State.overrideFaction ~= nil then
    return ns.State.overrideFaction
  end
  if type(UnitFactionGroup) == "function" then
    local f = UnitFactionGroup("player")
    if f == "Alliance" then
      return true
    elseif f == "Horde" then
      return false
    end
  end
  return nil
end

function Compat.Print(msg)
  local prefix = "|cff00ccff[ForeverHub]|r "
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage(prefix .. tostring(msg))
  else
    print(prefix .. tostring(msg))
  end
end

-- ============================================================================
-- v0.4.0 Typed Capability Results (Astra P0-G / P1-G / P1-H)
-- Never translate API failure, secret values, or uncached items into false, 0,
-- or (0, 0) coordinates.
-- ============================================================================

function Compat.IsSecretOrRestrictedValue(v)
  if type(_G.issecretvalue) == "function" then
    local ok, isSecret = pcall(_G.issecretvalue, v)
    if ok and isSecret == true then
      return true
    end
  end
  return false
end

function Compat.GetPlayerFactionString()
  if ns.State and type(ns.State.overrideFactionString) == "string" then
    return ns.State.overrideFactionString
  end
  local b = Compat.GetCurrentFaction()
  if b == true then
    return "Alliance"
  elseif b == false then
    return "Horde"
  end
  if type(UnitFactionGroup) == "function" then
    local ok, f = pcall(UnitFactionGroup, "player")
    if ok and type(f) == "string" and not Compat.IsSecretOrRestrictedValue(f) and f ~= "" then
      return f
    end
  end
  return nil
end

function Compat.GetPlayerClassAndRace()
  local classToken = ns.State and ns.State.overridePlayerClass or nil
  local raceToken = ns.State and ns.State.overridePlayerRace or nil
  if not classToken and type(UnitClass) == "function" then
    local ok, _, engClass = pcall(UnitClass, "player")
    if ok and type(engClass) == "string" and not Compat.IsSecretOrRestrictedValue(engClass) then
      classToken = engClass
    end
  end
  if not raceToken and type(UnitRace) == "function" then
    local ok, _, engRace = pcall(UnitRace, "player")
    if ok and type(engRace) == "string" and not Compat.IsSecretOrRestrictedValue(engRace) then
      raceToken = engRace
    end
  end
  return {
    classToken = classToken,
    raceToken = raceToken,
  }
end

Compat.recentQuestAcceptedByID = Compat.recentQuestAcceptedByID or {}
Compat.recentQuestAcceptedByTitle = Compat.recentQuestAcceptedByTitle or {}
Compat.recentQuestTurnedInByID = Compat.recentQuestTurnedInByID or {}
Compat.recentQuestTurnedInByTitle = Compat.recentQuestTurnedInByTitle or {}
Compat.observedLogTitlesByID = Compat.observedLogTitlesByID or {}
Compat.questObjectiveTextByID = Compat.questObjectiveTextByID or {}
Compat.liveMapQuestsCache = Compat.liveMapQuestsCache or {}
Compat.liveQuestTargetDrifts = Compat.liveQuestTargetDrifts or {}
Compat.lastDialogQuest = Compat.lastDialogQuest or { questID = nil, rawTitle = nil, normTitle = nil, capturedAt = 0 }
Compat.bulkCompletedCache = Compat.bulkCompletedCache or { expiresAt = 0, map = nil }
Compat.liveQuestLogCache = Compat.liveQuestLogCache or { expiresAt = 0, data = nil }

local RECENT_ACCEPT_TTL_SECONDS = 3.5
local RECENT_TURNIN_TTL_SECONDS = 8.0
local BULK_COMPLETED_TTL_SECONDS = 2.0
local LIVE_QUESTLOG_CACHE_TTL_SECONDS = 0.25
local LIVE_MAP_QUESTS_CACHE_TTL_SECONDS = 1.50

function Compat.NowSeconds()
  if type(GetTime) == "function" then
    local ok, t = pcall(GetTime)
    if ok and type(t) == "number" then
      return t
    end
  end
  if os and type(os.clock) == "function" then
    return os.clock()
  end
  if type(time) == "function" then
    return time()
  end
  return 0
end

function Compat.NormalizeQuestTitle(rawTitle)
  if type(rawTitle) ~= "string" or Compat.IsSecretOrRestrictedValue(rawTitle) then
    return nil
  end
  local s = rawTitle
  if string.sub(string.lower(s), 1, 6) == "title:" then
    s = string.sub(s, 7)
  end
  s = string.gsub(s, "|c%x%x%x%x%x%x%x%x", "")
  s = string.gsub(s, "|r", "")
  s = string.gsub(s, "^%s*%[%d+%+?%a*%]%s*", "")
  s = string.gsub(s, "%s*%([Ee]lite%)%s*$", "")
  s = string.gsub(s, "%s*%([Dd]ungeon%)%s*$", "")
  s = string.gsub(s, "%s*%([Gg]roup%)%s*$", "")
  s = string.gsub(s, "%s+", " ")
  s = string.gsub(s, "^%s+", "")
  s = string.gsub(s, "%s+$", "")
  if s == "" then
    return nil
  end
  return string.lower(s)
end

function Compat.InvalidateQuestStateCaches()
  Compat.bulkCompletedCache = { expiresAt = 0, map = nil }
  Compat.liveQuestLogCache = { expiresAt = 0, data = nil }
  Compat.liveMapQuestsCache = {}
end

function Compat.LookupRouteQuestMeta(_questRef)
  return nil
end

local function parseNpcIdFromGuid(guid)
  if type(guid) ~= "string" or Compat.IsSecretOrRestrictedValue(guid) or guid == "" then
    return nil
  end
  local idStr = string.match(guid, "^%a+%-0%-%d+%-%d+%-%d+%-(%d+)%-")
    or string.match(guid, "%-(%d+)%-%x+$")
  local nid = tonumber(idStr)
  if nid and nid > 0 then
    return nid
  end
  return nil
end

function Compat.CaptureQuestDialogIdentity(dialogKind)
  local qid = nil
  local rawTitle = nil
  local npcID = nil
  local npcName = nil
  local objectiveText = nil
  if type(GetQuestID) == "function" then
    local ok, id = pcall(GetQuestID)
    if ok and not Compat.IsSecretOrRestrictedValue(id) then
      id = tonumber(id)
      if id and id > 0 then
        qid = id
      end
    end
  end
  if type(GetTitleText) == "function" then
    local ok, t = pcall(GetTitleText)
    if ok and type(t) == "string" and not Compat.IsSecretOrRestrictedValue(t) and t ~= "" then
      rawTitle = t
    end
  end
  if type(_G.UnitGUID) == "function" then
    local okG, guid = pcall(_G.UnitGUID, "npc")
    if okG then
      npcID = parseNpcIdFromGuid(guid)
    end
  end
  if type(UnitName) == "function" then
    local okU, uName = pcall(UnitName, "npc")
    if okU and type(uName) == "string" and not Compat.IsSecretOrRestrictedValue(uName) and uName ~= "" then
      npcName = uName
    end
  end
  if type(_G.GetObjectiveText) == "function" then
    local okO, oTxt = pcall(_G.GetObjectiveText)
    if okO and type(oTxt) == "string" and not Compat.IsSecretOrRestrictedValue(oTxt) and oTxt ~= "" then
      objectiveText = oTxt
    end
  end
  local posStatus, posMapID, posX, posY = Compat.GetPlayerPosition01Raw()
  local normTitle = Compat.NormalizeQuestTitle(rawTitle)
  Compat.lastDialogQuest = {
    dialogKind = dialogKind,
    questID = qid,
    rawTitle = rawTitle,
    normTitle = normTitle,
    npcID = npcID,
    npcName = npcName,
    objectiveText = objectiveText,
    uiMapID = (posStatus == "ok") and posMapID or nil,
    x01 = (posStatus == "ok") and posX or nil,
    y01 = (posStatus == "ok") and posY or nil,
    capturedAt = Compat.NowSeconds(),
  }
  if qid then
    if normTitle then
      Compat.observedLogTitlesByID[qid] = normTitle
      if ns.State and type(ns.State.RecordDiscoveredQuestId) == "function" then
        ns.State.RecordDiscoveredQuestId(normTitle, qid)
      end
    end
    if objectiveText then
      Compat.questObjectiveTextByID[qid] = objectiveText
      if ns.State and type(ns.State.RecordObservedQuestObjectiveText) == "function" then
        ns.State.RecordObservedQuestObjectiveText(qid, objectiveText)
      end
    end
    if dialogKind == "QUEST_DETAIL" and (npcID or npcName) then
      if ns.State and type(ns.State.RecordObservedQuestGiver) == "function" then
        ns.State.RecordObservedQuestGiver(qid, Compat.lastDialogQuest)
      end
    end
  end
  return Compat.lastDialogQuest
end

function Compat.ScanLiveQuestLog(allowCollapsedExpand)
  local now = Compat.NowSeconds()
  if
    not allowCollapsedExpand
    and Compat.liveQuestLogCache
    and Compat.liveQuestLogCache.data
    and now < (Compat.liveQuestLogCache.expiresAt or 0)
  then
    return Compat.liveQuestLogCache.data
  end

  local result = {
    available = false,
    byID = {},
    byTitle = {},
    numQuests = 0,
    visibleQuestCount = 0,
    hasCollapsedHeaders = false,
    enumerationComplete = false,
  }

  local canUseModern = C_QuestLog
    and type(C_QuestLog.GetNumQuestLogEntries) == "function"
    and type(C_QuestLog.GetInfo) == "function"
  local canUseClassic = type(GetNumQuestLogEntries) == "function" and type(GetQuestLogTitle) == "function"

  if not canUseModern and not canUseClassic then
    return result
  end

  local canSafelyExpand = false
  if allowCollapsedExpand == true and not Compat.IsInCombat() then
    local qfShown = (_G.QuestLogFrame and type(_G.QuestLogFrame.IsShown) == "function" and _G.QuestLogFrame:IsShown()) or false
    local wmShown = (_G.WorldMapFrame and type(_G.WorldMapFrame.IsShown) == "function" and _G.WorldMapFrame:IsShown()) or false
    if not qfShown and not wmShown then
      canSafelyExpand = true
    end
  end

  local collapsedHeaderTitles = {}
  if canSafelyExpand and type(ExpandQuestHeader) == "function" and type(CollapseQuestHeader) == "function" then
    local okN, numEntries = pcall(canUseModern and C_QuestLog.GetNumQuestLogEntries or GetNumQuestLogEntries)
    if okN and type(numEntries) == "number" and numEntries > 0 then
      for i = numEntries, 1, -1 do
        local hTitle, isHeader, isCollapsed = nil, false, false
        if canUseModern then
          local okI, info = pcall(C_QuestLog.GetInfo, i)
          if okI and type(info) == "table" then
            hTitle = info.title
            isHeader = (info.isHeader == true)
            isCollapsed = (info.isCollapsed == true)
          end
        else
          local okR, t, _, _, hdr, col = pcall(GetQuestLogTitle, i)
          if okR then
            hTitle = t
            isHeader = (hdr == true or hdr == 1)
            isCollapsed = (col == true or col == 1)
          end
        end
        if isHeader and isCollapsed and type(hTitle) == "string" then
          collapsedHeaderTitles[hTitle] = true
          pcall(ExpandQuestHeader, i)
        end
      end
    end
  end

  local totalEntriesRead = 0
  local nonNilEntryCount = 0
  local visibleQuestCount = 0
  local digestParts = {}

  if canUseModern then
    local okN, numEntries, nQuests = pcall(C_QuestLog.GetNumQuestLogEntries)
    if okN and type(numEntries) == "number" then
      result.available = true
      result.numQuests = tonumber(nQuests) or 0
      totalEntriesRead = numEntries
      for i = 1, numEntries do
        local okI, info = pcall(C_QuestLog.GetInfo, i)
        if okI and type(info) == "table" then
          nonNilEntryCount = nonNilEntryCount + 1
          if info.isHeader == true then
            if info.isCollapsed == true then
              result.hasCollapsedHeaders = true
            end
          elseif not info.isHidden then
            visibleQuestCount = visibleQuestCount + 1
            local qid = tonumber(info.questID)
            if qid and qid <= 0 then
              qid = nil
            end
            local rawTitle = type(info.title) == "string" and not Compat.IsSecretOrRestrictedValue(info.title) and info.title or nil
            local normTitle = Compat.NormalizeQuestTitle(rawTitle)
            local row = {
              logIndex = i,
              questID = qid,
              title = rawTitle,
              normTitle = normTitle,
              isComplete = (info.isComplete == true or info.isComplete == 1),
            }
            digestParts[#digestParts + 1] = string.format("%s:%s:%s", tostring(qid or 0), tostring(normTitle or ""), row.isComplete and "1" or "0")
            if qid and qid > 0 then
              result.byID[qid] = row
            end
            if normTitle then
              result.byTitle[normTitle] = row
              if qid and qid > 0 then
                Compat.observedLogTitlesByID[qid] = normTitle
                if ns.State and type(ns.State.RecordDiscoveredQuestId) == "function" then
                  ns.State.RecordDiscoveredQuestId(normTitle, qid)
                end
              end
            end
          end
        end
      end
    end
  elseif canUseClassic then
    local okN, numEntries, nQuests = pcall(GetNumQuestLogEntries)
    if okN and type(numEntries) == "number" then
      result.available = true
      result.numQuests = tonumber(nQuests) or 0
      totalEntriesRead = numEntries
      for i = 1, numEntries do
        local okR, rawTitle, _, _, isHeader, isCollapsed, isComplete, _, qID = pcall(GetQuestLogTitle, i)
        if okR and rawTitle ~= nil then
          nonNilEntryCount = nonNilEntryCount + 1
          if isHeader == true or isHeader == 1 then
            if isCollapsed == true or isCollapsed == 1 then
              result.hasCollapsedHeaders = true
            end
          else
            visibleQuestCount = visibleQuestCount + 1
            local qid = tonumber(qID)
            if qid and qid <= 0 then
              qid = nil
            end
            local cleanTitle = type(rawTitle) == "string" and not Compat.IsSecretOrRestrictedValue(rawTitle) and rawTitle or nil
            local normTitle = Compat.NormalizeQuestTitle(cleanTitle)
            local row = {
              logIndex = i,
              questID = qid,
              title = cleanTitle,
              normTitle = normTitle,
              isComplete = (isComplete == true or isComplete == 1),
            }
            digestParts[#digestParts + 1] = string.format("%s:%s:%s", tostring(qid or 0), tostring(normTitle or ""), row.isComplete and "1" or "0")
            if qid and qid > 0 then
              result.byID[qid] = row
            end
            if normTitle then
              result.byTitle[normTitle] = row
              if qid and qid > 0 then
                Compat.observedLogTitlesByID[qid] = normTitle
                if ns.State and type(ns.State.RecordDiscoveredQuestId) == "function" then
                  ns.State.RecordDiscoveredQuestId(normTitle, qid)
                end
              end
            end
          end
        end
      end
    end
  end

  result.visibleQuestCount = visibleQuestCount
  result.digest = result.available
    and string.format("%d:%d:%s:%s", result.numQuests, visibleQuestCount, result.hasCollapsedHeaders and "1" or "0", table.concat(digestParts, ","))
    or "unavail"
  if result.available then
    local hiddenQuestGap = (nonNilEntryCount == totalEntriesRead)
      and (result.numQuests > 0)
      and (visibleQuestCount < result.numQuests)
    result.enumerationComplete = (not result.hasCollapsedHeaders) and (not hiddenQuestGap)
  end

  local didTemporaryExpand = next(collapsedHeaderTitles) ~= nil
  if didTemporaryExpand and type(CollapseQuestHeader) == "function" then
    local okN2, numEntries2 = pcall(canUseModern and C_QuestLog.GetNumQuestLogEntries or GetNumQuestLogEntries)
    if okN2 and type(numEntries2) == "number" then
      for i = numEntries2, 1, -1 do
        local hTitle, isHeader = nil, false
        if canUseModern then
          local okI, info = pcall(C_QuestLog.GetInfo, i)
          if okI and type(info) == "table" then
            hTitle = info.title
            isHeader = (info.isHeader == true)
          end
        else
          local okR, t, _, _, hdr = pcall(GetQuestLogTitle, i)
          if okR then
            hTitle = t
            isHeader = (hdr == true or hdr == 1)
          end
        end
        if isHeader and type(hTitle) == "string" and collapsedHeaderTitles[hTitle] then
          pcall(CollapseQuestHeader, i)
        end
      end
    end
    -- Never leave pre-collapse expanded logIndex values on returned rows or in liveQuestLogCache
    for _, row in pairs(result.byID) do
      row.logIndex = nil
    end
    for _, row in pairs(result.byTitle) do
      row.logIndex = nil
    end
    return result
  end

  Compat.liveQuestLogCache = {
    expiresAt = now + LIVE_QUESTLOG_CACHE_TTL_SECONDS,
    data = result,
  }
  return result
end

function Compat.ResolveFreshQuestLogIndex(questID, normTitle)
  local qid = tonumber(questID)
  if qid and qid <= 0 then
    qid = nil
  end
  local canUseModern = C_QuestLog
    and type(C_QuestLog.GetNumQuestLogEntries) == "function"
    and type(C_QuestLog.GetInfo) == "function"
  local canUseClassic = type(GetNumQuestLogEntries) == "function" and type(GetQuestLogTitle) == "function"

  if canUseModern then
    local okN, numEntries = pcall(C_QuestLog.GetNumQuestLogEntries)
    if okN and type(numEntries) == "number" then
      for i = 1, numEntries do
        local okI, info = pcall(C_QuestLog.GetInfo, i)
        if okI and type(info) == "table" and not info.isHeader and not info.isHidden then
          local rowQid = tonumber(info.questID)
          if rowQid and rowQid <= 0 then
            rowQid = nil
          end
          local rawTitle = type(info.title) == "string" and not Compat.IsSecretOrRestrictedValue(info.title) and info.title or nil
          local rowNorm = Compat.NormalizeQuestTitle(rawTitle)
          local isComp = (info.isComplete == true or info.isComplete == 1)
          if qid and rowQid == qid then
            return i, isComp
          end
          if normTitle and rowNorm == normTitle and (not qid or not rowQid or rowQid == qid) then
            return i, isComp
          end
        end
      end
    end
  elseif canUseClassic then
    local okN, numEntries = pcall(GetNumQuestLogEntries)
    if okN and type(numEntries) == "number" then
      for i = 1, numEntries do
        local okR, rawTitle, _, _, isHeader, _, isComplete, _, qID = pcall(GetQuestLogTitle, i)
        if okR and not (isHeader == true or isHeader == 1) then
          local rowQid = tonumber(qID)
          if rowQid and rowQid <= 0 then
            rowQid = nil
          end
          local cleanTitle = type(rawTitle) == "string" and not Compat.IsSecretOrRestrictedValue(rawTitle) and rawTitle or nil
          local rowNorm = Compat.NormalizeQuestTitle(cleanTitle)
          local isComp = (isComplete == true or isComplete == 1)
          if qid and rowQid == qid then
            return i, isComp
          end
          if normTitle and rowNorm == normTitle and (not qid or not rowQid or rowQid == qid) then
            return i, isComp
          end
        end
      end
    end
  end
  return nil, false
end

function Compat.GetSelectedQuestInfo()
  if ns.State and type(ns.State.overrideSelectedQuest) == "table" then
    local ov = ns.State.overrideSelectedQuest
    local qid = tonumber(ov.questID)
    if qid and qid <= 0 then
      qid = nil
    end
    local rawTitle = type(ov.title) == "string" and ov.title or nil
    if not rawTitle and qid then
      local meta = Compat.LookupRouteQuestMeta(qid)
      rawTitle = meta and meta.name or nil
    end
    local normTitle = Compat.NormalizeQuestTitle(rawTitle)
    if not qid and not normTitle then
      return { available = false }
    end
    return {
      available = true,
      questID = qid,
      title = rawTitle,
      normTitle = normTitle,
      level = tonumber(ov.level),
      source = "override",
    }
  end

  local qid = nil
  local rawTitle = nil
  local qLevel = nil
  local source = nil

  if type(_G.QuestMapFrame_GetDetailQuestID) == "function" then
    local ok, id = pcall(_G.QuestMapFrame_GetDetailQuestID)
    if ok and not Compat.IsSecretOrRestrictedValue(id) and (tonumber(id) or 0) > 0 then
      qid = tonumber(id)
      source = "quest_map_detail_fn"
    end
  end

  if not qid and type(_G.QuestMapFrame) == "table" and type(_G.QuestMapFrame.DetailsFrame) == "table" then
    local df = _G.QuestMapFrame.DetailsFrame
    local shown = (type(df.IsShown) ~= "function") or df:IsShown()
    if shown and not Compat.IsSecretOrRestrictedValue(df.questID) and (tonumber(df.questID) or 0) > 0 then
      qid = tonumber(df.questID)
      source = "quest_map_details_frame"
    end
  end

  if not qid and type(_G.WorldMapFrame) == "table" then
    local wf = _G.WorldMapFrame
    if type(wf.DetailsFrame) == "table" then
      local df = wf.DetailsFrame
      local shown = (type(df.IsShown) ~= "function") or df:IsShown()
      if shown and not Compat.IsSecretOrRestrictedValue(df.questID) and (tonumber(df.questID) or 0) > 0 then
        qid = tonumber(df.questID)
        source = "world_map_details_frame"
      end
    end
    if not qid and type(wf.questLog) == "table" then
      local ql = wf.questLog
      if type(ql.DetailsFrame) == "table" then
        local df = ql.DetailsFrame
        local shown = (type(df.IsShown) ~= "function") or df:IsShown()
        if shown and not Compat.IsSecretOrRestrictedValue(df.questID) and (tonumber(df.questID) or 0) > 0 then
          qid = tonumber(df.questID)
          source = "world_map_questlog_details"
        end
      end
      if not qid and not Compat.IsSecretOrRestrictedValue(ql.selectedQuestID) and (tonumber(ql.selectedQuestID) or 0) > 0 then
        qid = tonumber(ql.selectedQuestID)
        source = "world_map_questlog_selected"
      end
    end
  end

  if not qid and C_QuestLog and type(C_QuestLog.GetSelectedQuest) == "function" then
    local ok, id = pcall(C_QuestLog.GetSelectedQuest)
    if ok and not Compat.IsSecretOrRestrictedValue(id) and (tonumber(id) or 0) > 0 then
      qid = tonumber(id)
      source = "c_questlog_selected"
    end
  end

  if not qid and type(_G.GetQuestLogSelection) == "function" and type(_G.GetQuestLogTitle) == "function" then
    local okSel, selIdx = pcall(_G.GetQuestLogSelection)
    if okSel and type(selIdx) == "number" and selIdx > 0 and not Compat.IsSecretOrRestrictedValue(selIdx) then
      local okRow, t, lvl, _, isHeader, _, _, _, rowQid = pcall(_G.GetQuestLogTitle, selIdx)
      if okRow and not (isHeader == true or isHeader == 1) then
        if type(t) == "string" and not Compat.IsSecretOrRestrictedValue(t) and t ~= "" then
          rawTitle = t
        end
        if type(lvl) == "number" and not Compat.IsSecretOrRestrictedValue(lvl) and lvl > 0 then
          qLevel = lvl
        end
        if not Compat.IsSecretOrRestrictedValue(rowQid) and (tonumber(rowQid) or 0) > 0 then
          qid = tonumber(rowQid)
        end
        source = "classic_questlog_selection"
      end
    end
  end

  if qid and not rawTitle then
    if C_QuestLog and type(C_QuestLog.GetTitleForQuestID) == "function" then
      local okT, t = pcall(C_QuestLog.GetTitleForQuestID, qid)
      if okT and type(t) == "string" and not Compat.IsSecretOrRestrictedValue(t) and t ~= "" then
        rawTitle = t
      end
    end
    if not rawTitle then
      local scan = Compat.ScanLiveQuestLog(false)
      local liveRow = scan.available and scan.byID and scan.byID[qid] or nil
      if liveRow then
        rawTitle = liveRow.title or liveRow.normTitle
        qLevel = qLevel or tonumber(liveRow.level)
      end
    end
    if not rawTitle then
      local meta = Compat.LookupRouteQuestMeta(qid)
      if meta then
        rawTitle = meta.name
        qLevel = qLevel or tonumber(meta.questLevel)
      end
    end
  end

  local normTitle = Compat.NormalizeQuestTitle(rawTitle)
  if not qid and not normTitle then
    return { available = false }
  end
  return {
    available = true,
    questID = qid,
    title = rawTitle,
    normTitle = normTitle,
    level = qLevel,
    source = source or "live",
  }
end

function Compat.ResolveQuestIdentity(questRef)
  local qid = tonumber(questRef)
  if qid and qid <= 0 then
    qid = nil
  end
  local meta = Compat.LookupRouteQuestMeta(questRef)
  if not qid and meta and tonumber(meta.questID) and tonumber(meta.questID) > 0 then
    qid = tonumber(meta.questID)
  end
  local identityConfidence = qid and "catalog_id" or "title_only_unresolved"
  local normTitle = nil
  if meta and type(meta.name) == "string" then
    normTitle = Compat.NormalizeQuestTitle(meta.name)
  elseif type(questRef) == "string" then
    normTitle = Compat.NormalizeQuestTitle(questRef)
  elseif qid then
    normTitle = Compat.observedLogTitlesByID[qid]
      or (ns.State and type(ns.State.GetDiscoveredQuestTitle) == "function" and ns.State.GetDiscoveredQuestTitle(qid))
      or nil
  end

  if not qid and normTitle then
    if ns.State and type(ns.State.GetDiscoveredQuestId) == "function" then
      qid = ns.State.GetDiscoveredQuestId(normTitle)
      if qid then
        identityConfidence = "discovered_id"
      end
    end
    if not qid then
      local scan = Compat.ScanLiveQuestLog(false)
      local liveRow = scan.available and scan.byTitle[normTitle] or nil
      if liveRow then
        if (tonumber(liveRow.questID) or 0) > 0 then
          qid = tonumber(liveRow.questID)
          identityConfidence = "live_log_id"
        else
          identityConfidence = "title_only_active"
        end
      end
      if not qid and meta and tonumber(meta.knownQuestID) and tonumber(meta.knownQuestID) > 0 then
        local kQid = tonumber(meta.knownQuestID)
        local now = Compat.NowSeconds()
        local hasExplicitOverride = (
          ns.State
          and (
            (type(ns.State.overrideActiveQuests) == "table" and ns.State.overrideActiveQuests[kQid] ~= nil)
            or (type(ns.State.overrideCompletedQuests) == "table" and ns.State.overrideCompletedQuests[kQid] ~= nil)
          )
        )
        local observedOrCached = (
          (ns.State and type(ns.State.IsObservedCompletedQuestId) == "function" and ns.State.IsObservedCompletedQuestId(kQid))
          or ((Compat.recentQuestAcceptedByID[kQid] or 0) > now)
          or ((Compat.recentQuestTurnedInByID[kQid] or 0) > now)
          or (scan and scan.available and scan.byID and scan.byID[kQid] ~= nil)
        )
        local liveActiveOrCompleted = false
        if not hasExplicitOverride and not observedOrCached then
          if not (ns.State and type(ns.State.overrideActiveQuests) == "table")
            and C_QuestLog and type(C_QuestLog.IsOnQuest) == "function"
          then
            local okOn, onVal = pcall(C_QuestLog.IsOnQuest, kQid)
            if okOn and not Compat.IsSecretOrRestrictedValue(onVal) and onVal == true then
              liveActiveOrCompleted = true
            end
          end
          if not liveActiveOrCompleted
            and not (ns.State and type(ns.State.overrideCompletedQuests) == "table")
            and C_QuestLog and type(C_QuestLog.IsQuestFlaggedCompleted) == "function"
          then
            local okDone, doneVal = pcall(C_QuestLog.IsQuestFlaggedCompleted, kQid)
            if okDone and not Compat.IsSecretOrRestrictedValue(doneVal) and doneVal == true then
              liveActiveOrCompleted = true
            end
          end
        end
        if hasExplicitOverride or observedOrCached or liveActiveOrCompleted then
          qid = kQid
          identityConfidence = "live_log_id"
        end
      end
    end
  end
  return qid, normTitle, meta, identityConfidence
end

local function resolveKnownTitleForQuestID(qid)
  if not qid or qid <= 0 then
    return nil
  end
  if Compat.liveQuestLogCache and Compat.liveQuestLogCache.data and Compat.liveQuestLogCache.data.byID[qid] then
    local t = Compat.liveQuestLogCache.data.byID[qid].normTitle
    if type(t) == "string" and t ~= "" then
      return t
    end
  end
  if type(Compat.observedLogTitlesByID[qid]) == "string" and Compat.observedLogTitlesByID[qid] ~= "" then
    return Compat.observedLogTitlesByID[qid]
  end
  if ns.State and type(ns.State.GetDiscoveredQuestTitle) == "function" then
    local dt = ns.State.GetDiscoveredQuestTitle(qid)
    if type(dt) == "string" and dt ~= "" then
      return dt
    end
  end
  local meta = Compat.LookupRouteQuestMeta(qid)
  if meta and type(meta.name) == "string" then
    return Compat.NormalizeQuestTitle(meta.name)
  end
  return nil
end

local function isDialogTitleCompatibleWithQuestID(dialogNormTitle, qid)
  if type(dialogNormTitle) ~= "string" or dialogNormTitle == "" then
    return false
  end
  if not qid or qid <= 0 then
    return true
  end
  local knownForID = resolveKnownTitleForQuestID(qid)
  if knownForID and knownForID ~= dialogNormTitle then
    return false
  end
  if ns.State and type(ns.State.GetDiscoveredQuestId) == "function" then
    local existingDiscovered = ns.State.GetDiscoveredQuestId(dialogNormTitle)
    if existingDiscovered and existingDiscovered ~= qid then
      return false
    end
  end
  return true
end

function Compat.RecordRecentQuestAccepted(questID, rawTitle)
  local now = Compat.NowSeconds()
  local qid = tonumber(questID)
  if qid and qid <= 0 then
    qid = nil
  end
  local normTitle = Compat.NormalizeQuestTitle(rawTitle)
  if not normTitle and qid then
    normTitle = resolveKnownTitleForQuestID(qid)
  end
  if not normTitle and Compat.lastDialogQuest and (now - (Compat.lastDialogQuest.capturedAt or 0)) <= 6.0 then
    local dQid = Compat.lastDialogQuest.questID
    local dNorm = Compat.lastDialogQuest.normTitle
    if (not qid or not dQid or dQid == qid) and isDialogTitleCompatibleWithQuestID(dNorm, qid or dQid) then
      normTitle = dNorm
      qid = qid or dQid
    end
  end
  if qid and qid > 0 then
    Compat.recentQuestAcceptedByID[qid] = now + RECENT_ACCEPT_TTL_SECONDS
    Compat.recentQuestTurnedInByID[qid] = nil
    if normTitle then
      Compat.observedLogTitlesByID[qid] = normTitle
      if ns.State and type(ns.State.RecordDiscoveredQuestId) == "function" then
        ns.State.RecordDiscoveredQuestId(normTitle, qid)
      end
    end
    if Compat.lastDialogQuest and (now - (Compat.lastDialogQuest.capturedAt or 0)) <= 6.0 then
      local dQid = Compat.lastDialogQuest.questID
      local dKind = Compat.lastDialogQuest.dialogKind
      if (not dQid or dQid == qid) and (dKind == nil or dKind == "QUEST_DETAIL") then
        if type(Compat.lastDialogQuest.objectiveText) == "string" and Compat.lastDialogQuest.objectiveText ~= "" then
          Compat.questObjectiveTextByID[qid] = Compat.lastDialogQuest.objectiveText
          if ns.State and type(ns.State.RecordObservedQuestObjectiveText) == "function" then
            ns.State.RecordObservedQuestObjectiveText(qid, Compat.lastDialogQuest.objectiveText)
          end
        end
        if Compat.lastDialogQuest.npcID or Compat.lastDialogQuest.npcName then
          if ns.State and type(ns.State.RecordObservedQuestGiver) == "function" then
            ns.State.RecordObservedQuestGiver(qid, Compat.lastDialogQuest)
          end
        end
      end
    end
  end
  if normTitle then
    Compat.recentQuestAcceptedByTitle[normTitle] = now + RECENT_ACCEPT_TTL_SECONDS
    Compat.recentQuestTurnedInByTitle[normTitle] = nil
    if ns.State and type(ns.State.ClearUnresolvedQuestConfirmation) == "function" then
      ns.State.ClearUnresolvedQuestConfirmation(normTitle)
    end
  end
  Compat.InvalidateQuestStateCaches()
end

function Compat.RecordRecentQuestTurnedIn(questID, rawTitle)
  local now = Compat.NowSeconds()
  local qid = tonumber(questID)
  if qid and qid <= 0 then
    qid = nil
  end
  local normTitle = Compat.NormalizeQuestTitle(rawTitle)
  if not normTitle and qid then
    normTitle = resolveKnownTitleForQuestID(qid)
  end
  if not normTitle and Compat.lastDialogQuest and (now - (Compat.lastDialogQuest.capturedAt or 0)) <= 6.0 then
    local dQid = Compat.lastDialogQuest.questID
    local dNorm = Compat.lastDialogQuest.normTitle
    if (not qid or not dQid or dQid == qid) and isDialogTitleCompatibleWithQuestID(dNorm, qid or dQid) then
      normTitle = dNorm
      qid = qid or dQid
    end
  end
  if qid and qid > 0 then
    Compat.recentQuestTurnedInByID[qid] = now + RECENT_TURNIN_TTL_SECONDS
    Compat.recentQuestAcceptedByID[qid] = nil
    if ns.State and type(ns.State.RecordCompletedQuestId) == "function" then
      ns.State.RecordCompletedQuestId(qid)
    end
    if normTitle then
      Compat.observedLogTitlesByID[qid] = normTitle
      if ns.State and type(ns.State.RecordDiscoveredQuestId) == "function" then
        ns.State.RecordDiscoveredQuestId(normTitle, qid)
      end
    end
  end
  if normTitle then
    Compat.recentQuestTurnedInByTitle[normTitle] = now + RECENT_TURNIN_TTL_SECONDS
    Compat.recentQuestAcceptedByTitle[normTitle] = nil
    if ns.State and type(ns.State.RecordCompletedQuestTitle) == "function" then
      ns.State.RecordCompletedQuestTitle(normTitle)
    end
  end
  Compat.InvalidateQuestStateCaches()
end

local function escapeLuaPatternLiteral(str)
  return (string.gsub(str, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

local function isServerQuestFlaggedCompletedRaw(questID)
  local qid = tonumber(questID)
  if not qid or qid <= 0 then
    return false
  end
  if ns.State and type(ns.State.overrideCompletedQuests) == "table" then
    return ns.State.overrideCompletedQuests[qid] == true
  end
  if C_QuestLog and type(C_QuestLog.IsQuestFlaggedCompleted) == "function" then
    local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, qid)
    if ok and not Compat.IsSecretOrRestrictedValue(done) and done == true then
      return true
    end
  end
  if type(IsQuestFlaggedCompleted) == "function" then
    local ok, done = pcall(IsQuestFlaggedCompleted, qid)
    if ok and not Compat.IsSecretOrRestrictedValue(done) and (done == true or done == 1) then
      return true
    end
  end
  if Compat.CheckBulkQuestCompleted(qid) then
    return true
  end
  return false
end

function Compat.RecordRecentQuestRemoved(questID)
  local qid = tonumber(questID)
  if qid and qid <= 0 then
    qid = nil
  end
  local normTitle = qid and resolveKnownTitleForQuestID(qid) or nil
  if qid then
    Compat.recentQuestAcceptedByID[qid] = nil
  end
  if normTitle then
    Compat.recentQuestAcceptedByTitle[normTitle] = nil
  end
  Compat.InvalidateQuestStateCaches()
  if qid and isServerQuestFlaggedCompletedRaw(qid) then
    Compat.RecordRecentQuestTurnedIn(qid, normTitle)
    return true, normTitle
  end
  return false, normTitle
end

function Compat.ParseSystemQuestCompletedMessage(rawMsg)
  if type(rawMsg) ~= "string" or rawMsg == "" or Compat.IsSecretOrRestrictedValue(rawMsg) then
    return nil
  end
  local pattern = "^(.+) completed%.$"
  local fmt = _G.ERR_QUEST_COMPLETE_S
  if type(fmt) == "string" and fmt ~= "" and not Compat.IsSecretOrRestrictedValue(fmt) and string.find(fmt, "%s", 1, true) then
    local pre, post = string.match(fmt, "^(.-)%%s(.-)$")
    if pre ~= nil and post ~= nil then
      pattern = "^" .. escapeLuaPatternLiteral(pre) .. "(.+)" .. escapeLuaPatternLiteral(post) .. "$"
    end
  end
  local capturedTitle = string.match(rawMsg, pattern)
  if type(capturedTitle) ~= "string" or capturedTitle == "" then
    return nil
  end
  local normTitle = Compat.NormalizeQuestTitle(capturedTitle)
  if not normTitle then
    return nil
  end

  local isKnownOrTracked = (Compat.LookupRouteQuestMeta(normTitle) ~= nil)
    or ((Compat.recentQuestAcceptedByTitle[normTitle] or 0) > 0)
    or (Compat.lastDialogQuest and Compat.lastDialogQuest.normTitle == normTitle)
    or (ns.State and type(ns.State.GetDiscoveredQuestId) == "function" and ns.State.GetDiscoveredQuestId(normTitle) ~= nil)

  local matchedObservedQid = nil
  for obsId, obsNorm in pairs(Compat.observedLogTitlesByID) do
    if obsNorm == normTitle and tonumber(obsId) and tonumber(obsId) > 0 then
      isKnownOrTracked = true
      matchedObservedQid = tonumber(obsId)
      break
    end
  end

  if not isKnownOrTracked then
    local cachedScan = Compat.liveQuestLogCache and Compat.liveQuestLogCache.data or nil
    if cachedScan and cachedScan.byTitle and cachedScan.byTitle[normTitle] ~= nil then
      isKnownOrTracked = true
      local rowQid = tonumber(cachedScan.byTitle[normTitle].questID)
      if rowQid and rowQid > 0 then
        matchedObservedQid = rowQid
      end
    end
  end

  if not isKnownOrTracked then
    return nil
  end

  local resolvedQid = Compat.ResolveQuestIdentity(normTitle)
  if not resolvedQid and matchedObservedQid then
    resolvedQid = matchedObservedQid
  end
  return resolvedQid, capturedTitle, normTitle
end

function Compat.CheckBulkQuestCompleted(questID)
  local qid = tonumber(questID)
  if not qid then
    return false
  end
  local now = Compat.NowSeconds()
  if not Compat.bulkCompletedCache.map or now >= (Compat.bulkCompletedCache.expiresAt or 0) then
    local map = nil
    if C_QuestLog and type(C_QuestLog.GetAllCompletedQuestIDs) == "function" then
      local ok, list = pcall(C_QuestLog.GetAllCompletedQuestIDs)
      if ok and type(list) == "table" and not Compat.IsSecretOrRestrictedValue(list) then
        map = {}
        for _, id in ipairs(list) do
          local n = tonumber(id)
          if n then
            map[n] = true
          end
        end
      end
    elseif type(GetQuestsCompleted) == "function" then
      local ok, tbl = pcall(GetQuestsCompleted)
      if ok and type(tbl) == "table" and not Compat.IsSecretOrRestrictedValue(tbl) then
        map = tbl
      end
    end
    Compat.bulkCompletedCache = {
      expiresAt = now + BULK_COMPLETED_TTL_SECONDS,
      map = map,
    }
  end
  if type(Compat.bulkCompletedCache.map) == "table" and Compat.bulkCompletedCache.map[qid] == true then
    return true
  end
  return false
end

function Compat.IsQuestCompletedResult(questRef)
  if questRef == nil then
    return { status = "unknown", value = nil, reason = "invalid_quest_id" }
  end
  local questID, normTitle, _, identityConfidence = Compat.ResolveQuestIdentity(questRef)
  if not questID and not normTitle then
    return { status = "unknown", value = nil, reason = "invalid_quest_id" }
  end

  if ns.State and type(ns.State.overrideCompletedQuests) == "table" then
    local ov = ns.State.overrideCompletedQuests[questRef]
    if ov == nil and questID then
      ov = ns.State.overrideCompletedQuests[questID]
    end
    if ov == nil and normTitle then
      ov = ns.State.overrideCompletedQuests["title:" .. normTitle]
    end
    if ov == "unknown" or ov == "unavailable" or ov == "restricted" then
      return { status = ov, value = nil, reason = "override_" .. ov, identityConfidence = identityConfidence }
    elseif type(ov) == "boolean" then
      return { status = "ok", value = ov, identityConfidence = identityConfidence }
    else
      return { status = "ok", value = false, identityConfidence = identityConfidence }
    end
  end

  local now = Compat.NowSeconds()
  if questID and (Compat.recentQuestTurnedInByID[questID] or 0) > now then
    return { status = "ok", value = true, source = "recent_turnin_cache", identityConfidence = identityConfidence }
  end
  if normTitle and (Compat.recentQuestTurnedInByTitle[normTitle] or 0) > now then
    return { status = "ok", value = true, source = "recent_turnin_title_cache", identityConfidence = identityConfidence }
  end
  if questID and ns.State and type(ns.State.IsObservedCompletedQuestId) == "function" and ns.State.IsObservedCompletedQuestId(questID) then
    return { status = "ok", value = true, source = "observed_id_history", identityConfidence = identityConfidence }
  end

  if not questID then
    local onRes = Compat.IsOnQuestResult(questRef)
    if onRes.status == "ok" and onRes.value == true then
      return {
        status = "ok",
        value = false,
        reason = "active_in_quest_log",
        identityConfidence = "title_only_active",
      }
    end
    if onRes.status == "restricted" then
      return {
        status = "restricted",
        value = nil,
        reason = onRes.reason or "secret_value",
        identityConfidence = "title_only_unresolved",
      }
    end
    if not ((C_QuestLog and type(C_QuestLog.IsQuestFlaggedCompleted) == "function") or type(IsQuestFlaggedCompleted) == "function") then
      return {
        status = "unavailable",
        value = nil,
        reason = "missing_quest_completion_api",
        identityConfidence = "title_only_unresolved",
      }
    end
    local userConfirmed = (
      ns.State
      and type(ns.State.IsUnresolvedQuestConfirmedIncomplete) == "function"
      and ns.State.IsUnresolvedQuestConfirmedIncomplete(normTitle, type(questRef) == "string" and questRef or nil)
    ) or false
    return {
      status = "unknown",
      value = nil,
      reason = "title_history_unresolved",
      identityConfidence = "title_only_unresolved",
      userConfirmedIncomplete = userConfirmed,
    }
  end

  if C_QuestLog and type(C_QuestLog.IsQuestFlaggedCompleted) == "function" then
    local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, questID)
    if not ok then
      return { status = "unavailable", value = nil, reason = "api_error", identityConfidence = identityConfidence }
    end
    if Compat.IsSecretOrRestrictedValue(done) then
      return { status = "restricted", value = nil, reason = "secret_value", identityConfidence = identityConfidence }
    end
    if type(done) == "boolean" then
      if done == true or Compat.CheckBulkQuestCompleted(questID) then
        return { status = "ok", value = true, identityConfidence = identityConfidence }
      end
      return { status = "ok", value = false, identityConfidence = identityConfidence }
    end
    return { status = "unknown", value = nil, reason = "unexpected_return_type", identityConfidence = identityConfidence }
  end
  if type(IsQuestFlaggedCompleted) == "function" then
    local ok, done = pcall(IsQuestFlaggedCompleted, questID)
    if ok and not Compat.IsSecretOrRestrictedValue(done) then
      if done == true or done == 1 or Compat.CheckBulkQuestCompleted(questID) then
        return { status = "ok", value = true, identityConfidence = identityConfidence }
      end
      return { status = "ok", value = false, identityConfidence = identityConfidence }
    end
    return { status = "unavailable", value = nil, reason = "legacy_api_error", identityConfidence = identityConfidence }
  end
  return { status = "unavailable", value = nil, reason = "missing_quest_completion_api", identityConfidence = identityConfidence }
end

function Compat.IsOnQuestResult(questRef)
  if questRef == nil then
    return { status = "unknown", value = nil, reason = "invalid_quest_id" }
  end
  local questID, normTitle, _, identityConfidence = Compat.ResolveQuestIdentity(questRef)
  if not questID and not normTitle then
    return { status = "unknown", value = nil, reason = "invalid_quest_id" }
  end

  if ns.State and type(ns.State.overrideActiveQuests) == "table" then
    local ov = ns.State.overrideActiveQuests[questRef]
    if ov == nil and questID then
      ov = ns.State.overrideActiveQuests[questID]
    end
    if ov == nil and normTitle then
      ov = ns.State.overrideActiveQuests["title:" .. normTitle]
    end
    if ov == "unknown" or ov == "unavailable" or ov == "restricted" then
      return { status = ov, value = nil, reason = "override_" .. ov, identityConfidence = identityConfidence }
    end
    return { status = "ok", value = (ov == true), identityConfidence = identityConfidence, observationCompleteness = "complete" }
  end

  local now = Compat.NowSeconds()
  if questID and (Compat.recentQuestTurnedInByID[questID] or 0) > now then
    return { status = "ok", value = false, source = "recent_turnin_cache", identityConfidence = identityConfidence, observationCompleteness = "complete" }
  end
  if normTitle and (Compat.recentQuestTurnedInByTitle[normTitle] or 0) > now then
    return { status = "ok", value = false, source = "recent_turnin_title_cache", identityConfidence = identityConfidence, observationCompleteness = "complete" }
  end
  if questID and (Compat.recentQuestAcceptedByID[questID] or 0) > now then
    return { status = "ok", value = true, source = "recent_accept_cache", identityConfidence = identityConfidence, observationCompleteness = "complete" }
  end
  if normTitle and (Compat.recentQuestAcceptedByTitle[normTitle] or 0) > now then
    return { status = "ok", value = true, source = "recent_accept_title_cache", identityConfidence = identityConfidence, observationCompleteness = "complete" }
  end

  local scan = Compat.ScanLiveQuestLog(false)
  local scanCompleteness = "unavailable"
  if scan.available then
    scanCompleteness = scan.enumerationComplete and "complete" or "incomplete_collapsed_headers"
    if questID and scan.byID[questID] ~= nil then
      return { status = "ok", value = true, identityConfidence = identityConfidence, observationCompleteness = scanCompleteness }
    end
    if normTitle and scan.byTitle[normTitle] ~= nil then
      return { status = "ok", value = true, identityConfidence = identityConfidence, observationCompleteness = scanCompleteness }
    end
  end

  if questID and C_QuestLog and type(C_QuestLog.IsOnQuest) == "function" then
    local ok, onQ = pcall(C_QuestLog.IsOnQuest, questID)
    if not ok then
      return { status = "unavailable", value = nil, reason = "api_error", identityConfidence = identityConfidence, observationCompleteness = scanCompleteness }
    end
    if Compat.IsSecretOrRestrictedValue(onQ) then
      return { status = "restricted", value = nil, reason = "secret_value", identityConfidence = identityConfidence, observationCompleteness = "restricted" }
    end
    if type(onQ) == "boolean" then
      return { status = "ok", value = onQ, identityConfidence = identityConfidence, observationCompleteness = "complete" }
    end
    return { status = "unknown", value = nil, reason = "unexpected_return_type", identityConfidence = identityConfidence, observationCompleteness = scanCompleteness }
  end

  if scan.available then
    if not scan.enumerationComplete then
      return {
        status = "unknown",
        value = nil,
        reason = "collapsed_quest_headers",
        identityConfidence = identityConfidence,
        observationCompleteness = "incomplete_collapsed_headers",
      }
    end
    return {
      status = "ok",
      value = false,
      identityConfidence = identityConfidence,
      observationCompleteness = "complete",
    }
  end
  return {
    status = "unavailable",
    value = nil,
    reason = "missing_quest_log_api",
    identityConfidence = identityConfidence,
    observationCompleteness = "unavailable",
  }
end

local function buildObjectivesSummaryText(parsed, allDone)
  if allDone then
    return "Ready to turn in"
  end
  if type(parsed) ~= "table" or #parsed == 0 then
    return nil
  end
  local parts = {}
  for _, row in ipairs(parsed) do
    if row.finished ~= true then
      local txt = type(row.text) == "string" and row.text or ""
      txt = string.gsub(txt, "^%s*%-+%s*", "")
      txt = string.gsub(txt, "^%s+", "")
      txt = string.gsub(txt, "%s+$", "")
      if txt == "" and row.numFulfilled ~= nil and row.numRequired ~= nil then
        txt = string.format("%d/%d", row.numFulfilled, row.numRequired)
      end
      if txt ~= "" then
        table.insert(parts, txt)
      end
      if #parts >= 2 then
        break
      end
    end
  end
  if #parts == 0 then
    return nil
  end
  return table.concat(parts, " • ")
end

local function sumObjectiveProgressScore(rows)
  local finishedCount = 0
  local fulfilledSum = 0
  for _, r in ipairs(rows or {}) do
    if type(r) == "table" then
      if r.finished == true then
        finishedCount = finishedCount + 1
      end
      fulfilledSum = fulfilledSum + (tonumber(r.numFulfilled) or 0)
    end
  end
  return finishedCount, fulfilledSum
end

local function readClassicLeaderboardObjectives(questID, normTitle, isZeroObjectiveQuest, identityConfidence)
  if type(GetNumQuestLeaderBoards) ~= "function" or type(GetQuestLogLeaderBoard) ~= "function" then
    return nil
  end
  local freshIndex, freshComplete = Compat.ResolveFreshQuestLogIndex(questID, normTitle)
  if not freshIndex then
    return nil
  end
  if freshComplete == true then
    return {
      status = "ok",
      allFinished = true,
      objectives = {},
      summaryText = "Ready to turn in",
      provider = "classic_leaderboards",
      identityConfidence = identityConfidence,
    }
  end
  local okLB, numLB = pcall(GetNumQuestLeaderBoards, freshIndex)
  if okLB and Compat.IsSecretOrRestrictedValue(numLB) then
    return { status = "restricted", allFinished = nil, objectives = {}, reason = "secret_value", identityConfidence = identityConfidence }
  end
  if okLB and type(numLB) == "number" then
    if numLB == 0 then
      return {
        status = "ok",
        allFinished = (isZeroObjectiveQuest == true),
        objectives = {},
        summaryText = isZeroObjectiveQuest and "Ready to turn in" or nil,
        provider = "classic_leaderboards",
        identityConfidence = identityConfidence,
      }
    end
    local parsed = {}
    local allDone = true
    for j = 1, numLB do
      local okItem, desc, _, finished = pcall(GetQuestLogLeaderBoard, j, freshIndex)
      if okItem and Compat.IsSecretOrRestrictedValue(finished) then
        return { status = "restricted", allFinished = nil, objectives = {}, reason = "restricted_objective_row", identityConfidence = identityConfidence }
      end
      local fin = (okItem and (finished == true or finished == 1)) or false
      if not fin then
        allDone = false
      end
      local cleanDesc = (type(desc) == "string" and not Compat.IsSecretOrRestrictedValue(desc)) and desc or ""
      local nf, nr = nil, nil
      if cleanDesc ~= "" then
        local a, b = string.match(cleanDesc, "(%d+)%s*/%s*(%d+)")
        nf = tonumber(a)
        nr = tonumber(b)
      end
      table.insert(parsed, {
        index = j,
        text = cleanDesc,
        finished = fin,
        numFulfilled = nf,
        numRequired = nr,
      })
    end
    return {
      status = "ok",
      allFinished = allDone,
      objectives = parsed,
      summaryText = buildObjectivesSummaryText(parsed, allDone),
      provider = "classic_leaderboards",
      identityConfidence = identityConfidence,
    }
  end
  return nil
end

function Compat.GetQuestObjectivesResult(questRef, opts)
  if questRef == nil then
    return { status = "unknown", allFinished = nil, objectives = {}, reason = "invalid_quest_id" }
  end
  local questID, normTitle, meta, identityConfidence = Compat.ResolveQuestIdentity(questRef)
  if not questID and not normTitle then
    return { status = "unknown", allFinished = nil, objectives = {}, reason = "invalid_quest_id" }
  end
  local isZeroObjectiveQuest = (type(opts) == "table" and opts.zeroObjectives == true)
    or (type(meta) == "table" and meta.zeroObjectives == true)

  if ns.State and type(ns.State.overrideQuestObjectives) == "table" then
    local ov = ns.State.overrideQuestObjectives[questRef]
    if ov == nil and questID then
      ov = ns.State.overrideQuestObjectives[questID]
    end
    if ov == nil and normTitle then
      ov = ns.State.overrideQuestObjectives["title:" .. normTitle]
    end
    if type(ov) == "string" then
      return { status = ov, allFinished = nil, objectives = {}, reason = "override_" .. ov }
    elseif type(ov) == "boolean" then
      return { status = "ok", allFinished = ov, objectives = {}, summaryText = ov and "Ready to turn in" or nil }
    elseif type(ov) == "table" then
      if ov.status then
        return ov
      end
      local allDone = (#ov > 0)
      for _, row in ipairs(ov) do
        if not (type(row) == "table" and row.finished == true) then
          allDone = false
          break
        end
      end
      return { status = "ok", allFinished = allDone, objectives = ov, summaryText = buildObjectivesSummaryText(ov, allDone) }
    end
  end

  if questID and C_QuestLog and type(C_QuestLog.IsComplete) == "function" then
    local okComp, isComp = pcall(C_QuestLog.IsComplete, questID)
    if okComp and Compat.IsSecretOrRestrictedValue(isComp) then
      return { status = "restricted", allFinished = nil, objectives = {}, reason = "secret_value" }
    end
    if okComp and isComp == true then
      return { status = "ok", allFinished = true, objectives = {}, summaryText = "Ready to turn in", provider = "modern_c_questlog" }
    end
  end

  local scan = Compat.ScanLiveQuestLog(false)
  if scan.available then
    local logRow = (questID and scan.byID[questID]) or (normTitle and scan.byTitle[normTitle]) or nil
    if logRow and logRow.isComplete == true then
      return { status = "ok", allFinished = true, objectives = {}, summaryText = "Ready to turn in", provider = "quest_log_header_flag" }
    end
  end

  -- Provider 1: Modern C_QuestLog.GetQuestObjectives (retains catalog questID; falls through to Classic leaderboards on error/nil/empty, NEVER bypassing restricted values!)
  local modernFallbackReason = nil
  if questID and C_QuestLog and type(C_QuestLog.GetQuestObjectives) == "function" then
    local ok, objs = pcall(C_QuestLog.GetQuestObjectives, questID)
    if not ok then
      modernFallbackReason = "api_error"
    elseif Compat.IsSecretOrRestrictedValue(objs) then
      return { status = "restricted", allFinished = nil, objectives = {}, reason = "secret_value", identityConfidence = identityConfidence }
    elseif type(objs) ~= "table" then
      modernFallbackReason = "nil_objectives"
    elseif #objs == 0 then
      modernFallbackReason = "empty_objectives"
    else
      local parsed = {}
      local allDone = true
      for idx, row in ipairs(objs) do
        if type(row) ~= "table" or Compat.IsSecretOrRestrictedValue(row.finished) then
          return { status = "restricted", allFinished = nil, objectives = {}, reason = "restricted_objective_row", identityConfidence = identityConfidence }
        end
        local fin = (row.finished == true)
        if not fin then
          allDone = false
        end
        table.insert(parsed, {
          index = idx,
          text = type(row.text) == "string" and not Compat.IsSecretOrRestrictedValue(row.text) and row.text or "",
          finished = fin,
          numFulfilled = tonumber(row.numFulfilled),
          numRequired = tonumber(row.numRequired),
        })
      end
      -- Cross-check against Classic Quest Log Leaderboards when modern GetQuestObjectives lags on WoW: Forever (stale 0/1 while leaderboard is already finished/ahead)
      if not allDone then
        local classicCheck = readClassicLeaderboardObjectives(questID, normTitle, isZeroObjectiveQuest, identityConfidence)
        if classicCheck then
          if classicCheck.status == "restricted" then
            return classicCheck
          elseif classicCheck.status == "ok" then
            if classicCheck.allFinished == true then
              return classicCheck
            end
            local modFin, modFul = sumObjectiveProgressScore(parsed)
            local clsFin, clsFul = sumObjectiveProgressScore(classicCheck.objectives)
            if clsFin > modFin or (clsFin == modFin and clsFul > modFul) then
              return classicCheck
            end
          end
        end
      end
      return {
        status = "ok",
        allFinished = allDone,
        objectives = parsed,
        summaryText = buildObjectivesSummaryText(parsed, allDone),
        provider = "modern_c_questlog",
        identityConfidence = identityConfidence,
      }
    end
  end

  -- Provider 2: Classic Quest Log Leaderboards using a freshly verified live logIndex (even when live row had questID=0)
  local classicRes = readClassicLeaderboardObjectives(questID, normTitle, isZeroObjectiveQuest, identityConfidence)
  if classicRes then
    return classicRes
  end

  if modernFallbackReason == "empty_objectives" then
    local onRes = Compat.IsOnQuestResult(questRef)
    if onRes.status == "ok" and onRes.value == true then
      if isZeroObjectiveQuest then
        return { status = "ok", allFinished = true, objectives = {}, summaryText = "Ready to turn in", identityConfidence = identityConfidence }
      end
      return { status = "ok", allFinished = false, objectives = {}, identityConfidence = identityConfidence }
    end
    return { status = "unknown", allFinished = nil, objectives = {}, reason = "empty_objectives", identityConfidence = identityConfidence }
  elseif modernFallbackReason == "api_error" then
    return { status = "unavailable", allFinished = nil, objectives = {}, reason = "api_error", identityConfidence = identityConfidence }
  elseif modernFallbackReason == "nil_objectives" then
    return { status = "unknown", allFinished = nil, objectives = {}, reason = "nil_objectives", identityConfidence = identityConfidence }
  end

  if not questID then
    local onRes = Compat.IsOnQuestResult(questRef)
    if onRes.status == "ok" and onRes.value == true and isZeroObjectiveQuest then
      return { status = "ok", allFinished = true, objectives = {}, summaryText = "Ready to turn in", identityConfidence = identityConfidence }
    end
    if onRes.status ~= "ok" then
      return { status = onRes.status, allFinished = nil, objectives = {}, reason = onRes.reason, identityConfidence = identityConfidence }
    end
    return { status = "ok", allFinished = false, objectives = {}, reason = "title_quest_not_active", identityConfidence = identityConfidence }
  end
  return { status = "unavailable", allFinished = nil, objectives = {}, reason = "missing_objectives_api", identityConfidence = identityConfidence }
end

function Compat.GetQuestEvidenceResult(questRef, opts)
  opts = type(opts) == "table" and opts or {}
  local questID, normTitle, meta, identityConfidence = Compat.ResolveQuestIdentity(questRef)
  local questKey = (meta and meta.questKey) or (normTitle and ("title:" .. normTitle)) or nil
  local activeRes = Compat.IsOnQuestResult(questRef)
  local completedRes = Compat.IsQuestCompletedResult(questRef)
  local objectivesRes = nil
  if opts.includeObjectives then
    objectivesRes = Compat.GetQuestObjectivesResult(questRef, opts)
  end
  local userConfirmed = (
    ns.State
    and type(ns.State.IsUnresolvedQuestConfirmedIncomplete) == "function"
    and ns.State.IsUnresolvedQuestConfirmedIncomplete(normTitle, questKey, opts.progress)
  ) or false
  local observationCompleteness = activeRes.observationCompleteness or "complete"
  if activeRes.status == "restricted" or completedRes.status == "restricted" or (objectivesRes and objectivesRes.status == "restricted") then
    observationCompleteness = "restricted"
  end
  return {
    questRef = questRef,
    questID = questID,
    normTitle = normTitle,
    questKey = questKey,
    identityConfidence = completedRes.identityConfidence or identityConfidence,
    observationCompleteness = observationCompleteness,
    active = activeRes,
    completed = completedRes,
    objectives = objectivesRes,
    userConfirmedIncomplete = userConfirmed,
    provenance = {
      reviewStatus = meta and meta.reviewStatus or nil,
      prereqConfidence = meta and meta.prereqConfidence or nil,
    },
  }
end

function Compat.GetActiveStepTruthFingerprint(questRef, forceFresh)
  if forceFresh == true then
    Compat.bulkCompletedCache = { expiresAt = 0, map = nil }
    Compat.liveQuestLogCache = { expiresAt = 0, data = nil }
  end
  local scan = Compat.ScanLiveQuestLog(false)
  local logDigest = (scan and scan.digest) or "unavail"
  if questRef == nil then
    return "idle|" .. tostring(logDigest)
  end
  local onRes = Compat.IsOnQuestResult(questRef)
  local compRes = Compat.IsQuestCompletedResult(questRef)
  local objRes = nil
  if onRes.status == "ok" and onRes.value == true and compRes.value ~= true then
    objRes = Compat.GetQuestObjectivesResult(questRef)
  end
  return string.format(
    "%s:%s|%s:%s|%s:%s:%s|%s",
    tostring(onRes.status),
    tostring(onRes.value),
    tostring(compRes.status),
    tostring(compRes.value),
    tostring(objRes and objRes.status or "-"),
    tostring(objRes and objRes.allFinished or "-"),
    tostring(objRes and objRes.summaryText or ""),
    tostring(logDigest)
  )
end

function Compat.IsQuestLogFullResult()
  if ns.State and ns.State.overrideQuestLogFull ~= nil then
    if type(ns.State.overrideQuestLogFull) == "boolean" then
      return { status = "ok", value = ns.State.overrideQuestLogFull }
    end
    return { status = "unknown", value = nil }
  end
  local numQuests = nil
  local maxQuests = 40
  local hasExplicitApiMax = false
  if C_QuestLog and type(C_QuestLog.GetNumQuestLogEntries) == "function" then
    local ok, _, nQuests = pcall(C_QuestLog.GetNumQuestLogEntries)
    if ok and type(nQuests) == "number" then
      numQuests = nQuests
    end
    if type(C_QuestLog.GetMaxNumQuestsCanAccept) == "function" then
      local okM, maxQ = pcall(C_QuestLog.GetMaxNumQuestsCanAccept)
      if okM and type(maxQ) == "number" and maxQ > 0 then
        maxQuests = maxQ
        hasExplicitApiMax = true
      end
    end
  elseif type(GetNumQuestLogEntries) == "function" then
    local ok, _, nQuests = pcall(GetNumQuestLogEntries)
    if ok and type(nQuests) == "number" then
      numQuests = nQuests
    end
  end
  local tocVersion = nil
  if type(GetBuildInfo) == "function" then
    local okB, _, _, _, t = pcall(GetBuildInfo)
    if okB then
      tocVersion = tonumber(t)
    end
  end
  if tocVersion == 16001 and maxQuests < 40 then
    -- WoW: Forever raises the active Quest Log cap to 40 quests
    maxQuests = 40
  elseif not hasExplicitApiMax then
    maxQuests = math.max(maxQuests, tonumber(_G.MAX_QUESTLOG_QUESTS) or 0, tonumber(_G.MAX_QUESTS) or 0)
  end
  if type(numQuests) == "number" then
    if numQuests > maxQuests then
      maxQuests = numQuests
    end
    return { status = "ok", value = (numQuests >= maxQuests), count = numQuests, max = maxQuests }
  end
  return { status = "unknown", value = nil }
end

function Compat.GetQuestLogCapacityResult()
  if ns.State and ns.State.overrideQuestLogCapacity ~= nil then
    local ov = ns.State.overrideQuestLogCapacity
    if type(ov) == "table" then
      if ov.status ~= "ok" then
        return { status = "unknown", isFull = nil, count = nil, max = nil, freeSlots = nil }
      end
      local c = tonumber(ov.count)
      local m = tonumber(ov.max)
      if c and m and m > 0 then
        local effMax = math.max(c, m)
        return {
          status = "ok",
          isFull = (c >= effMax),
          count = c,
          max = effMax,
          freeSlots = math.max(0, effMax - c),
        }
      end
      if type(ov.isFull) == "boolean" then
        return {
          status = "ok",
          isFull = ov.isFull,
          count = nil,
          max = nil,
          freeSlots = ov.isFull and 0 or nil,
        }
      end
    elseif type(ov) == "boolean" then
      return {
        status = "ok",
        isFull = ov,
        count = nil,
        max = nil,
        freeSlots = ov and 0 or nil,
      }
    end
    return { status = "unknown", isFull = nil, count = nil, max = nil, freeSlots = nil }
  end

  local raw = Compat.IsQuestLogFullResult()
  if type(raw) ~= "table" or raw.status ~= "ok" then
    return { status = "unknown", isFull = nil, count = nil, max = nil, freeSlots = nil }
  end
  local c = tonumber(raw.count)
  local m = tonumber(raw.max)
  if c and m and m > 0 then
    local effMax = math.max(c, m)
    return {
      status = "ok",
      isFull = (c >= effMax),
      count = c,
      max = effMax,
      freeSlots = math.max(0, effMax - c),
    }
  end
  if type(raw.value) == "boolean" then
    return {
      status = "ok",
      isFull = raw.value,
      count = nil,
      max = nil,
      freeSlots = raw.value and 0 or nil,
    }
  end
  return { status = "unknown", isFull = nil, count = nil, max = nil, freeSlots = nil }
end

function Compat.ValidateUiMap(uiMapID)
  uiMapID = tonumber(uiMapID)
  if not uiMapID then
    return { status = "unknown", value = false, reason = "invalid_uimap_id" }
  end
  if ns.State and type(ns.State.overrideValidUiMaps) == "table" then
    local ov = ns.State.overrideValidUiMaps[uiMapID]
    if ov == "unavailable" or ov == "unknown" then
      return { status = ov, value = nil, reason = "override_" .. ov }
    end
    return { status = "ok", value = (ov == true) }
  end
  if C_Map and type(C_Map.GetMapInfo) == "function" then
    local ok, info = pcall(C_Map.GetMapInfo, uiMapID)
    if not ok then
      return { status = "unavailable", value = nil, reason = "get_map_info_failed" }
    end
    if Compat.IsSecretOrRestrictedValue(info) then
      return { status = "restricted", value = nil, reason = "secret_map_info" }
    end
    if type(info) == "table" and tonumber(info.mapID) == uiMapID then
      return { status = "ok", value = true, mapInfo = info }
    end
    return { status = "ok", value = false, reason = "map_not_found" }
  end
  return { status = "unavailable", value = nil, reason = "missing_c_map" }
end

function Compat.GetPlayerUiMapIDRaw()
  if ns.State and type(ns.State.overridePlayerPosition) == "table" then
    local pos = ns.State.overridePlayerPosition
    if pos.status and pos.status ~= "ok" then
      return false, nil
    end
    local m = tonumber(pos.uiMapID)
    if Compat.IsFiniteNumber(m) and m > 0 then
      return true, m
    end
    return false, nil
  end
  if C_Map and type(C_Map.GetBestMapForUnit) == "function" then
    local okMap, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if okMap and not Compat.IsSecretOrRestrictedValue(mapID) then
      mapID = tonumber(mapID)
      if Compat.IsFiniteNumber(mapID) and mapID > 0 then
        return true, mapID
      end
    end
  end
  return false, nil
end

-- Zero-allocation raw position helper returning `(status, uiMapID, x01, y01, reason)` on the Lua stack.
function Compat.GetPlayerPosition01Raw()
  if ns.State and type(ns.State.overridePlayerPosition) == "table" then
    local pos = ns.State.overridePlayerPosition
    if pos.status and pos.status ~= "ok" then
      return tostring(pos.status), nil, nil, nil, pos.reason or "override_not_ok"
    end
    local x = tonumber(pos.x01)
    local y = tonumber(pos.y01)
    local m = tonumber(pos.uiMapID)
    if not Compat.IsFiniteNumber(m) or not Compat.IsFiniteNumber(x) or not Compat.IsFiniteNumber(y)
      or (x == 0 and y == 0) or x < 0 or x > 1 or y < 0 or y > 1
    then
      return "unavailable", nil, nil, nil, "invalid_or_zero_override_coords"
    end
    return "ok", m, x, y, nil
  end
  if not (C_Map and type(C_Map.GetBestMapForUnit) == "function" and type(C_Map.GetPlayerMapPosition) == "function") then
    return "unavailable", nil, nil, nil, "missing_map_position_api"
  end
  local okMap, mapID = pcall(C_Map.GetBestMapForUnit, "player")
  if not okMap or Compat.IsSecretOrRestrictedValue(mapID) or not Compat.IsFiniteNumber(mapID) or mapID <= 0 then
    return "unavailable", nil, nil, nil, "player_map_unavailable"
  end
  local okPos, posObj = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
  if not okPos or not posObj or Compat.IsSecretOrRestrictedValue(posObj) or type(posObj.GetXY) ~= "function" then
    return "unavailable", nil, nil, nil, "player_position_nil_or_restricted"
  end
  local okXY, x, y = pcall(posObj.GetXY, posObj)
  if not okXY or Compat.IsSecretOrRestrictedValue(x) or Compat.IsSecretOrRestrictedValue(y) then
    return "restricted", nil, nil, nil, "secret_xy"
  end
  x = tonumber(x)
  y = tonumber(y)
  -- Never treat (0, 0), NaN, or out-of-bounds sentinel as a valid coordinate!
  if not Compat.IsFiniteNumber(x) or not Compat.IsFiniteNumber(y)
    or (x <= 0 and y <= 0) or x < 0 or x > 1 or y < 0 or y > 1
  then
    return "unavailable", nil, nil, nil, "zero_or_out_of_bounds_xy"
  end
  return "ok", mapID, x, y, nil
end

function Compat.GetPlayerPosition01()
  if ns.State and type(ns.State.overridePlayerPosition) == "table" then
    local pos = ns.State.overridePlayerPosition
    if pos.status and pos.status ~= "ok" then
      return pos
    end
  end
  local status, mapID, x, y, reason = Compat.GetPlayerPosition01Raw()
  if status == "ok" then
    return { status = "ok", uiMapID = mapID, x01 = x, y01 = y }
  end
  return { status = status, reason = reason }
end

Compat.GetPlayerMapPosition = Compat.GetPlayerPosition01

Compat._mapWorldSizeCache = Compat._mapWorldSizeCache or {}

function Compat.InvalidateMapWorldSizeCache(uiMapID)
  if uiMapID ~= nil then
    Compat._mapWorldSizeCache[tonumber(uiMapID) or uiMapID] = nil
  else
    Compat._mapWorldSizeCache = {}
  end
end

function Compat.GetMapWorldSizeYards(uiMapID)
  uiMapID = tonumber(uiMapID)
  if not Compat.IsFiniteNumber(uiMapID) or uiMapID <= 0 then
    return { status = "unavailable", reason = "invalid_uimap_id" }
  end
  if ns.State and type(ns.State.overrideMapWorldSizes) == "table" then
    local ov = ns.State.overrideMapWorldSizes[uiMapID]
    if ov == nil and ns.State.overrideMapWorldSizes["*"] ~= nil then
      ov = ns.State.overrideMapWorldSizes["*"]
    end
    if ov == nil or ov == false or ov == "unavailable" or ov == "unknown" then
      return { status = "unavailable", reason = "missing_world_transform" }
    elseif type(ov) == "table" then
      local w = tonumber(ov.width or ov.widthYards or ov[1])
      local h = tonumber(ov.height or ov.heightYards or ov[2])
      if Compat.IsFiniteNumber(w) and Compat.IsFiniteNumber(h) and w > 0 and h > 0 then
        return { status = "ok", widthYards = w, heightYards = h, source = "override" }
      end
      return { status = "unavailable", reason = "invalid_override_world_size" }
    end
    return { status = "unavailable", reason = "invalid_override_world_size" }
  end
  local curFnSize = C_Map and C_Map.GetMapWorldSize or nil
  local curFnPos = C_Map and C_Map.GetWorldPosFromMapPos or nil
  local cached = Compat._mapWorldSizeCache[uiMapID]
  if type(cached) == "table"
    and cached.status == "ok"
    and cached._fnSize == curFnSize
    and cached._fnPos == curFnPos
  then
    return cached
  end
  if type(curFnSize) == "function" then
    local okSz, w, h = pcall(curFnSize, uiMapID)
    if okSz and not Compat.IsSecretOrRestrictedValue(w) and not Compat.IsSecretOrRestrictedValue(h) then
      w = tonumber(w)
      h = tonumber(h)
      if Compat.IsFiniteNumber(w) and Compat.IsFiniteNumber(h) and w > 0 and h > 0 then
        local res = {
          status = "ok",
          widthYards = w,
          heightYards = h,
          source = "GetMapWorldSize",
          _fnSize = curFnSize,
          _fnPos = curFnPos,
        }
        Compat._mapWorldSizeCache[uiMapID] = res
        return res
      end
    end
  end
  if type(curFnPos) == "function" then
    local makeVec = type(_G.CreateVector2D) == "function" and _G.CreateVector2D
      or function(vx, vy)
        return { x = vx, y = vy, GetXY = function(self) return self.x, self.y end }
      end
    local ok0, inst0, wp0 = pcall(C_Map.GetWorldPosFromMapPos, uiMapID, makeVec(0, 0))
    local ok1, inst1, wp1 = pcall(C_Map.GetWorldPosFromMapPos, uiMapID, makeVec(1, 1))
    if ok0 and ok1 and wp0 and wp1 and inst0 ~= nil and inst0 == inst1 then
      local x0 = type(wp0.GetXY) == "function" and select(1, wp0:GetXY()) or wp0.x
      local y0 = type(wp0.GetXY) == "function" and select(2, wp0:GetXY()) or wp0.y
      local x1 = type(wp1.GetXY) == "function" and select(1, wp1:GetXY()) or wp1.x
      local y1 = type(wp1.GetXY) == "function" and select(2, wp1:GetXY()) or wp1.y
      x0, y0, x1, y1 = tonumber(x0), tonumber(y0), tonumber(x1), tonumber(y1)
      if Compat.IsFiniteNumber(x0) and Compat.IsFiniteNumber(y0)
        and Compat.IsFiniteNumber(x1) and Compat.IsFiniteNumber(y1)
      then
        -- In WoW world space, map X corresponds to -worldY (west->east) and map Y corresponds to -worldX (north->south),
        -- or vice versa depending on client axis helper; check axis-aligned spans robustly:
        local spanA = math.abs(x1 - x0)
        local spanB = math.abs(y1 - y0)
        local okX, _, wpX = pcall(C_Map.GetWorldPosFromMapPos, uiMapID, makeVec(1, 0))
        local okY, _, wpY = pcall(C_Map.GetWorldPosFromMapPos, uiMapID, makeVec(0, 1))
        if okX and okY and wpX and wpY then
          local xx = tonumber(type(wpX.GetXY) == "function" and select(1, wpX:GetXY()) or wpX.x)
          local xy = tonumber(type(wpX.GetXY) == "function" and select(2, wpX:GetXY()) or wpX.y)
          local yx = tonumber(type(wpY.GetXY) == "function" and select(1, wpY:GetXY()) or wpY.x)
          local yy = tonumber(type(wpY.GetXY) == "function" and select(2, wpY:GetXY()) or wpY.y)
          if Compat.IsFiniteNumber(xx) and Compat.IsFiniteNumber(xy)
            and Compat.IsFiniteNumber(yx) and Compat.IsFiniteNumber(yy)
          then
            local wYards = math.sqrt(((xx - x0) * (xx - x0)) + ((xy - y0) * (xy - y0)))
            local hYards = math.sqrt(((yx - x0) * (yx - x0)) + ((yy - y0) * (yy - y0)))
            if wYards > 0 and hYards > 0 then
              local res = {
                status = "ok",
                widthYards = wYards,
                heightYards = hYards,
                source = "GetWorldPosFromMapPos",
                _fnSize = curFnSize,
                _fnPos = curFnPos,
              }
              Compat._mapWorldSizeCache[uiMapID] = res
              return res
            end
          end
        elseif spanA > 0 and spanB > 0 then
          local res = { status = "ok", widthYards = spanB, heightYards = spanA, source = "GetWorldPosFromMapPos" }
          Compat._mapWorldSizeCache[uiMapID] = res
          return res
        end
      end
    end
  end
  return { status = "unavailable", reason = "missing_world_transform" }
end

function Compat.GetWorldDistanceYards(uiMapID, ax01, ay01, bx01, by01)
  uiMapID = tonumber(uiMapID)
  ax01, ay01 = tonumber(ax01), tonumber(ay01)
  bx01, by01 = tonumber(bx01), tonumber(by01)
  if not Compat.IsFiniteNumber(uiMapID)
    or not Compat.IsFiniteNumber(ax01) or not Compat.IsFiniteNumber(ay01)
    or not Compat.IsFiniteNumber(bx01) or not Compat.IsFiniteNumber(by01)
    or ax01 < 0 or ax01 > 1 or ay01 < 0 or ay01 > 1
    or bx01 < 0 or bx01 > 1 or by01 < 0 or by01 > 1
  then
    return { status = "unavailable", yards = nil, reason = "invalid_coords" }
  end
  local sz = Compat.GetMapWorldSizeYards(uiMapID)
  if sz.status ~= "ok" or not Compat.IsFiniteNumber(sz.widthYards) or not Compat.IsFiniteNumber(sz.heightYards) then
    return { status = "unavailable", yards = nil, reason = sz.reason or "missing_world_transform" }
  end
  local dxYards = (ax01 - bx01) * sz.widthYards
  local dyYards = (ay01 - by01) * sz.heightYards
  local yards = math.sqrt((dxYards * dxYards) + (dyYards * dyYards))
  return {
    status = "ok",
    yards = yards,
    widthYards = sz.widthYards,
    heightYards = sz.heightYards,
    source = sz.source,
  }
end

function Compat.GetLoadedAddonInfo(addonFolderName)
  local loaded = false
  local version = nil
  if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
    local ok, res = pcall(C_AddOns.IsAddOnLoaded, addonFolderName)
    if ok and res == true then
      loaded = true
    end
  elseif type(IsAddOnLoaded) == "function" then
    local ok, res = pcall(IsAddOnLoaded, addonFolderName)
    if ok and (res == true or res == 1) then
      loaded = true
    end
  end
  if C_AddOns and type(C_AddOns.GetAddOnMetadata) == "function" then
    local okV, v = pcall(C_AddOns.GetAddOnMetadata, addonFolderName, "Version")
    if okV and type(v) == "string" and v ~= "" then
      version = v
    end
  elseif type(GetAddOnMetadata) == "function" then
    local okV, v = pcall(GetAddOnMetadata, addonFolderName, "Version")
    if okV and type(v) == "string" and v ~= "" then
      version = v
    end
  end
  if not loaded then
    if addonFolderName == "RXPGuides" and type(_G.RXPGuides) == "table" then
      loaded = true
      version = version or tostring(_G.RXPGuides.version or _G.RXPGuides.release or "loaded")
    elseif addonFolderName == "TomTom" and type(_G.TomTom) == "table" then
      loaded = true
      version = version or tostring(_G.TomTom.version or "loaded")
    elseif addonFolderName == "Questie" and type(_G.Questie) == "table" then
      loaded = true
      version = version or "loaded"
    elseif addonFolderName == "QuestieDB" and type(_G.QuestieDB) == "table" then
      loaded = true
      version = version or "loaded"
    end
  end
  return {
    loaded = loaded,
    version = loaded and (version or "unknown") or "not_loaded",
  }
end

function Compat.CanSetNativeWaypoint(uiMapID)
  uiMapID = tonumber(uiMapID)
  if not Compat.IsFiniteNumber(uiMapID) then
    return { status = "ok", value = false, reason = "invalid_uimap_id" }
  end
  if ns.State and type(ns.State.overrideNativeWaypointState) == "table" then
    local st = ns.State.overrideNativeWaypointState
    if st.supported == false then
      return { status = "ok", value = false, reason = "override_unsupported" }
    elseif st.supported == "unavailable" then
      return { status = "unavailable", value = nil, reason = "override_unavailable" }
    end
    local allowedMaps = st.allowedMaps
    if type(allowedMaps) == "table" then
      return { status = "ok", value = (allowedMaps[uiMapID] == true) }
    end
    return { status = "ok", value = true }
  end
  if not (C_Map and type(C_Map.CanSetUserWaypointOnMap) == "function" and type(C_Map.SetUserWaypoint) == "function" and _G.UiMapPoint and type(_G.UiMapPoint.CreateFromCoordinates) == "function") then
    return { status = "unavailable", value = false, reason = "missing_native_waypoint_api" }
  end
  local ok, canSet = pcall(C_Map.CanSetUserWaypointOnMap, uiMapID)
  if not ok or Compat.IsSecretOrRestrictedValue(canSet) then
    return { status = "unavailable", value = nil, reason = "can_set_waypoint_failed" }
  end
  return { status = "ok", value = (canSet == true) }
end

function Compat.GetNativeWaypoint()
  if ns.State and type(ns.State.overrideNativeWaypointState) == "table" then
    local st = ns.State.overrideNativeWaypointState
    if st.readStatus == "restricted" then
      return { status = "restricted", hasWaypoint = true, reason = "override_restricted" }
    elseif st.readStatus == "unavailable" then
      return { status = "unavailable", hasWaypoint = nil, reason = "override_unavailable" }
    end
    local cur = st.current
    if type(cur) == "table"
      and Compat.IsFiniteNumber(tonumber(cur.uiMapID))
      and Compat.IsFiniteNumber(tonumber(cur.x01))
      and Compat.IsFiniteNumber(tonumber(cur.y01))
    then
      return {
        status = "ok",
        hasWaypoint = true,
        uiMapID = tonumber(cur.uiMapID),
        x01 = tonumber(cur.x01),
        y01 = tonumber(cur.y01),
      }
    end
    return { status = "ok", hasWaypoint = false }
  end
  if not (C_Map and type(C_Map.GetUserWaypoint) == "function") then
    return { status = "unavailable", hasWaypoint = nil }
  end
  local ok, point = pcall(C_Map.GetUserWaypoint)
  if not ok then
    return { status = "unavailable", hasWaypoint = nil }
  end
  if not point then
    return { status = "ok", hasWaypoint = false }
  end
  if Compat.IsSecretOrRestrictedValue(point) or type(point) ~= "table" then
    return { status = "restricted", hasWaypoint = true }
  end
  local uiMapID = tonumber(point.uiMapID)
  local x01, y01 = nil, nil
  if type(point.position) == "table" then
    if type(point.position.GetXY) == "function" then
      local okXY, px, py = pcall(point.position.GetXY, point.position)
      if okXY then
        x01, y01 = tonumber(px), tonumber(py)
      end
    else
      x01 = tonumber(point.position.x)
      y01 = tonumber(point.position.y)
    end
  end
  if not Compat.IsFiniteNumber(uiMapID) or not Compat.IsFiniteNumber(x01) or not Compat.IsFiniteNumber(y01) then
    return { status = "restricted", hasWaypoint = true, reason = "unreadable_waypoint_coords" }
  end
  return {
    status = "ok",
    hasWaypoint = true,
    uiMapID = uiMapID,
    x01 = x01,
    y01 = y01,
  }
end

function Compat.SetNativeWaypoint(uiMapID, x01, y01)
  uiMapID = tonumber(uiMapID)
  x01 = tonumber(x01)
  y01 = tonumber(y01)
  if not Compat.IsFiniteNumber(uiMapID) or not Compat.IsFiniteNumber(x01) or not Compat.IsFiniteNumber(y01)
    or x01 <= 0 or x01 >= 1 or y01 <= 0 or y01 >= 1
  then
    return { status = "unavailable", reason = "invalid_waypoint_coords" }
  end
  if Compat.IsInCombat() then
    return { status = "unavailable", reason = "in_combat_lockdown" }
  end
  local canRes = Compat.CanSetNativeWaypoint(uiMapID)
  if canRes.status ~= "ok" or canRes.value ~= true then
    return { status = "unavailable", reason = canRes.reason or "map_waypoint_unsupported" }
  end
  if ns.State and type(ns.State.overrideNativeWaypointState) == "table" then
    local st = ns.State.overrideNativeWaypointState
    if st.setMustFail == true then
      return { status = "unavailable", reason = "override_set_failed" }
    end
    st.current = {
      uiMapID = uiMapID,
      x01 = x01,
      y01 = y01,
    }
    st.superTracked = true
    return { status = "ok", uiMapID = uiMapID, x01 = x01, y01 = y01 }
  end
  local okPt, pt = pcall(_G.UiMapPoint.CreateFromCoordinates, uiMapID, x01, y01)
  if not okPt or not pt then
    return { status = "unavailable", reason = "create_uimap_point_failed" }
  end
  local okSet = pcall(C_Map.SetUserWaypoint, pt)
  if not okSet then
    return { status = "unavailable", reason = "set_user_waypoint_failed" }
  end
  if C_SuperTrack and type(C_SuperTrack.SetSuperTrackedUserWaypoint) == "function" then
    pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
  end
  return { status = "ok", uiMapID = uiMapID, x01 = x01, y01 = y01 }
end

function Compat.ClearNativeWaypoint()
  if Compat.IsInCombat() then
    return { status = "unavailable", reason = "in_combat_lockdown" }
  end
  if ns.State and type(ns.State.overrideNativeWaypointState) == "table" then
    local st = ns.State.overrideNativeWaypointState
    if st.clearMustFail == true then
      return { status = "unavailable", reason = "override_clear_failed" }
    end
    st.current = nil
    st.superTracked = false
    return { status = "ok" }
  end
  if not (C_Map and type(C_Map.ClearUserWaypoint) == "function") then
    return { status = "unavailable", reason = "missing_clear_waypoint_api" }
  end
  local ok = pcall(C_Map.ClearUserWaypoint)
  if not ok then
    return { status = "unavailable", reason = "clear_waypoint_failed" }
  end
  return { status = "ok" }
end

function Compat.RequestLoadItemData(itemID)
  itemID = tonumber(itemID)
  if not itemID or itemID <= 0 then
    return false
  end
  if ns.State and type(ns.State.requestedItemLoads) == "table" then
    ns.State.requestedItemLoads[itemID] = (ns.State.requestedItemLoads[itemID] or 0) + 1
  end
  if C_Item and type(C_Item.RequestLoadItemDataByID) == "function" then
    local ok = pcall(C_Item.RequestLoadItemDataByID, itemID)
    return ok == true
  end
  return false
end

function Compat.GetItemSellPriceResult(itemIDOrLink)
  local itemID = Compat.ExtractItemID(itemIDOrLink)
  if not itemID then
    return { status = "unknown", unitSellPrice = nil, reason = "missing_item_id" }
  end
  if ns.State and type(ns.State.overrideItemSellPrices) == "table" then
    local ov = ns.State.overrideItemSellPrices[itemID]
    if ov == "loading" then
      return { status = "loading", itemID = itemID, unitSellPrice = nil }
    elseif ov == "unknown" or ov == "unavailable" then
      return { status = ov, itemID = itemID, unitSellPrice = nil }
    elseif type(ov) == "number" then
      return { status = "ok", itemID = itemID, unitSellPrice = math.max(0, math.floor(ov)) }
    elseif type(ov) == "table" then
      return ov
    end
  end
  local getInfoFn = (C_Item and type(C_Item.GetItemInfo) == "function" and C_Item.GetItemInfo)
    or (type(GetItemInfo) == "function" and GetItemInfo)
    or nil
  if not getInfoFn then
    return { status = "unavailable", itemID = itemID, unitSellPrice = nil, reason = "missing_get_item_info" }
  end
  local ok, itemName, itemLink, _, _, _, _, _, _, _, _, sellPrice = pcall(getInfoFn, itemIDOrLink or itemID)
  if not ok then
    return { status = "unavailable", itemID = itemID, unitSellPrice = nil, reason = "get_item_info_error" }
  end
  if Compat.IsSecretOrRestrictedValue(itemName) or Compat.IsSecretOrRestrictedValue(sellPrice) then
    return { status = "restricted", itemID = itemID, unitSellPrice = nil, reason = "secret_item_info" }
  end
  -- When itemName is nil, the client has not cached item info yet: never treat as 0c!
  if itemName == nil then
    return { status = "loading", itemID = itemID, unitSellPrice = nil, reason = "item_not_cached" }
  end
  if type(sellPrice) ~= "number" then
    return { status = "unknown", itemID = itemID, itemName = itemName, itemLink = itemLink, unitSellPrice = nil, reason = "sell_price_nil" }
  end
  return {
    status = "ok",
    itemID = itemID,
    itemName = itemName,
    itemLink = itemLink,
    unitSellPrice = math.max(0, math.floor(sellPrice)),
  }
end

function Compat.GetQuestRewardChoicesSnapshot()
  if ns.State and type(ns.State.overrideQuestRewardChoices) == "table" then
    return ns.State.overrideQuestRewardChoices
  end
  if type(GetNumQuestChoices) ~= "function" or type(GetQuestItemInfo) ~= "function" then
    return { status = "unavailable", choices = {} }
  end
  local okNum, numChoices = pcall(GetNumQuestChoices)
  if not okNum or Compat.IsSecretOrRestrictedValue(numChoices) or type(numChoices) ~= "number" then
    return { status = "unavailable", choices = {} }
  end
  local questID = nil
  if type(GetQuestID) == "function" then
    local okQ, qid = pcall(GetQuestID)
    if okQ and not Compat.IsSecretOrRestrictedValue(qid) and type(qid) == "number" and qid > 0 then
      questID = qid
    end
  end
  local questTitle = nil
  if type(GetTitleText) == "function" then
    local okT, title = pcall(GetTitleText)
    if okT and not Compat.IsSecretOrRestrictedValue(title) and type(title) == "string" then
      questTitle = title
    end
  end
  local choices = {}
  for idx = 1, numChoices do
    local okInfo, name, texture, numItems, quality, isUsable = pcall(GetQuestItemInfo, "choice", idx)
    local link = nil
    if type(GetQuestItemLink) == "function" then
      local okLink, l = pcall(GetQuestItemLink, "choice", idx)
      if okLink and not Compat.IsSecretOrRestrictedValue(l) and type(l) == "string" then
        link = l
      end
    end
    local itemID = Compat.ExtractItemID(link)
    local qty = (okInfo and not Compat.IsSecretOrRestrictedValue(numItems) and tonumber(numItems)) or 1
    qty = math.max(1, math.floor(qty))
    table.insert(choices, {
      choiceIndex = idx,
      itemID = itemID,
      itemLink = link,
      name = (okInfo and not Compat.IsSecretOrRestrictedValue(name) and type(name) == "string" and name ~= "") and name or nil,
      texture = okInfo and texture or nil,
      quantity = qty,
      quality = okInfo and tonumber(quality) or nil,
      isUsable = okInfo and isUsable or nil,
    })
  end
  return {
    status = "ok",
    questID = questID,
    questTitle = questTitle,
    choices = choices,
  }
end

function Compat.GetPlayerMoneyCopper()
  if ns.State and ns.State.overridePlayerMoneyCopper ~= nil then
    if type(ns.State.overridePlayerMoneyCopper) == "number" then
      return { status = "ok", copper = math.max(0, math.floor(ns.State.overridePlayerMoneyCopper)) }
    end
    return { status = tostring(ns.State.overridePlayerMoneyCopper), copper = nil }
  end
  if type(GetMoney) == "function" then
    local ok, money = pcall(GetMoney)
    if ok and not Compat.IsSecretOrRestrictedValue(money) and type(money) == "number" then
      return { status = "ok", copper = math.max(0, math.floor(money)) }
    end
    return { status = "unavailable", copper = nil, reason = "get_money_failed" }
  end
  return { status = "unavailable", copper = nil, reason = "missing_get_money" }
end

function Compat.GetPlayerLevel()
  if ns.State and type(ns.State.overridePlayerLevel) == "number" then
    return math.max(1, math.floor(ns.State.overridePlayerLevel))
  end
  if type(UnitLevel) == "function" then
    local ok, lvl = pcall(UnitLevel, "player")
    if ok and not Compat.IsSecretOrRestrictedValue(lvl) and type(lvl) == "number" and Compat.IsFiniteNumber(lvl) and lvl > 0 then
      return math.floor(lvl)
    end
  end
  local ident = type(Compat.GetPlayerIdentity) == "function" and Compat.GetPlayerIdentity() or nil
  if type(ident) == "table" and type(ident.level) == "number" and ident.level > 0 then
    return math.floor(ident.level)
  end
  return 1
end

Compat.MAX_PLAYER_LEVEL = 60

local function normalizePlayerXPProbe(effLvl, rawCurXP, rawMaxXP)
  if Compat.IsSecretOrRestrictedValue(effLvl)
    or Compat.IsSecretOrRestrictedValue(rawCurXP)
    or Compat.IsSecretOrRestrictedValue(rawMaxXP)
  then
    return { status = "unavailable", level = 1, reason = "xp_query_secret" }
  end
  local lvl = tonumber(effLvl)
  if not Compat.IsFiniteNumber(lvl) or lvl < 1 then
    lvl = 1
  else
    lvl = math.floor(lvl)
  end
  local curXP = tonumber(rawCurXP)
  local maxXP = tonumber(rawMaxXP)
  if not Compat.IsFiniteNumber(curXP) or not Compat.IsFiniteNumber(maxXP) or curXP < 0 or maxXP < 0 then
    return { status = "unavailable", level = lvl, reason = "xp_query_invalid" }
  end
  curXP = math.floor(curXP)
  maxXP = math.floor(maxXP)

  if lvl >= Compat.MAX_PLAYER_LEVEL then
    return {
      status = "capped",
      isCapped = true,
      currentXP = curXP,
      maxXP = maxXP,
      remainingXP = 0,
      fraction = 1.0,
      pct = 100.0,
      level = lvl,
    }
  end

  if maxXP == 0 then
    if lvl == (Compat.MAX_PLAYER_LEVEL - 1) and curXP == 0 then
      return {
        status = "transitional_cap_zero",
        isCapped = false,
        currentXP = 0,
        maxXP = 0,
        remainingXP = 0,
        fraction = 1.0,
        pct = 100.0,
        level = lvl,
      }
    end
    return { status = "unavailable", level = lvl, reason = "xp_query_zero_max_subcap" }
  end

  local frac = math.max(0.0, math.min(1.0, curXP / maxXP))
  return {
    status = "ok",
    isCapped = false,
    currentXP = curXP,
    maxXP = maxXP,
    remainingXP = math.max(0, maxXP - curXP),
    fraction = frac,
    pct = frac * 100.0,
    level = lvl,
  }
end

function Compat.GetPlayerXPState()
  local lvl = Compat.GetPlayerLevel()
  if ns.State and ns.State.overridePlayerXPState ~= nil then
    local ov = ns.State.overridePlayerXPState
    if type(ov) == "table" then
      local effLvl = tonumber(ov.level) or lvl
      if ov.status and ov.status ~= "ok" and ov.status ~= "capped" and ov.status ~= "transitional_cap_zero" then
        return {
          status = tostring(ov.status),
          level = math.max(1, math.floor(effLvl)),
          reason = ov.reason or "override_not_ok",
        }
      end
      local rawCur = (ov.currentXP ~= nil) and ov.currentXP or 0
      local rawMax = ov.maxXP
      if rawMax == nil then
        rawMax = (effLvl >= Compat.MAX_PLAYER_LEVEL) and 0 or 100000
      end
      return normalizePlayerXPProbe(effLvl, rawCur, rawMax)
    end
    return { status = tostring(ov), level = lvl }
  end
  if type(_G.UnitXP) == "function" and type(_G.UnitXPMax) == "function" then
    local okCur, curXP = pcall(_G.UnitXP, "player")
    local okMax, maxXP = pcall(_G.UnitXPMax, "player")
    if okCur and okMax then
      return normalizePlayerXPProbe(lvl, curXP, maxXP)
    end
    return { status = "unavailable", level = lvl, reason = "xp_query_invalid" }
  end
  return { status = "unavailable", level = lvl, reason = "missing_unit_xp_api" }
end

function Compat.GetCombatLockdownState()
  if ns.State and type(ns.State.overrideCombatLockdownState) == "table" then
    local ov = ns.State.overrideCombatLockdownState
    return {
      ok = (ov.ok == true),
      locked = (ov.locked ~= false),
      reason = ov.reason,
    }
  end
  if ns.State and type(ns.State.overrideInCombat) == "boolean" then
    return {
      ok = true,
      locked = (ns.State.overrideInCombat == true),
      reason = ns.State.overrideInCombat and "combat_lockdown" or nil,
    }
  end
  if type(_G.InCombatLockdown) ~= "function" then
    return { ok = false, locked = true, reason = "lockdown_probe_missing" }
  end
  local okCall, res = pcall(_G.InCombatLockdown)
  if not okCall or Compat.IsSecretOrRestrictedValue(res) or type(res) ~= "boolean" then
    return { ok = false, locked = true, reason = "lockdown_probe_unavailable" }
  end
  return {
    ok = true,
    locked = (res == true),
    reason = res and "combat_lockdown" or nil,
  }
end

function Compat.GetPlayerRestedXPState()
  if ns.State and ns.State.overrideRestedXP ~= nil then
    local ov = ns.State.overrideRestedXP
    if type(ov) == "table" then
      if ov.status and ov.status ~= "ok" then
        return { status = tostring(ov.status), reason = ov.reason or "override_not_ok" }
      end
      local exh = math.max(0, math.floor(tonumber(ov.exhaustionXP) or 0))
      return {
        status = "ok",
        exhaustionXP = exh,
        isRested = (ov.isRested ~= nil) and (ov.isRested == true) or (exh > 0),
      }
    elseif type(ov) == "number" and Compat.IsFiniteNumber(ov) then
      local exh = math.max(0, math.floor(ov))
      return {
        status = "ok",
        exhaustionXP = exh,
        isRested = (exh > 0),
      }
    end
    return { status = "unavailable", reason = "invalid_rested_override" }
  end
  if type(_G.GetXPExhaustion) ~= "function" then
    return { status = "unavailable", reason = "missing_get_xp_exhaustion" }
  end
  local okCall, exh = pcall(_G.GetXPExhaustion)
  if not okCall or Compat.IsSecretOrRestrictedValue(exh) then
    return { status = "unavailable", reason = "exhaustion_query_failed" }
  end
  if exh == nil then
    return { status = "ok", exhaustionXP = 0, isRested = false }
  end
  if type(exh) == "number" and Compat.IsFiniteNumber(exh) then
    local cleanExh = math.max(0, math.floor(exh))
    return { status = "ok", exhaustionXP = cleanExh, isRested = (cleanExh > 0) }
  end
  return { status = "unavailable", reason = "exhaustion_query_invalid" }
end

local function extractCreatureNpcIDFromGUID(guid)
  if Compat.IsSecretOrRestrictedValue(guid) or type(guid) ~= "string" then
    return nil
  end
  local nid = string.match(guid, "^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    or string.match(guid, "^Vehicle%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
  if nid then
    return tonumber(nid)
  end
  return nil
end

Compat.ExtractCreatureNpcIDFromGUID = extractCreatureNpcIDFromGUID

function Compat.ObserveUnitForTargetSet(unitToken, npcIDSet, npcNameSet)
  if Compat.IsSecretOrRestrictedValue(unitToken) or type(unitToken) ~= "string" or unitToken == "" then
    return { status = "observation_unavailable", matched = false, reason = "invalid_unit_token" }
  end
  npcIDSet = (not Compat.IsSecretOrRestrictedValue(npcIDSet) and type(npcIDSet) == "table") and npcIDSet or {}
  npcNameSet = (not Compat.IsSecretOrRestrictedValue(npcNameSet) and type(npcNameSet) == "table") and npcNameSet or {}

  if type(_G.UnitExists) ~= "function"
    or type(_G.UnitIsDeadOrGhost) ~= "function"
    or type(_G.UnitCanAttack) ~= "function"
  then
    return { status = "observation_unavailable", matched = false, reason = "missing_unit_probe_api" }
  end

  local okEx, exists = pcall(_G.UnitExists, unitToken)
  if not okEx or Compat.IsSecretOrRestrictedValue(exists) or type(exists) ~= "boolean" then
    return { status = "observation_unavailable", matched = false, reason = "unit_exists_unavailable" }
  end
  if exists == false then
    return { status = "not_matched", matched = false, reason = "unit_absent" }
  end

  local okDead, isDead = pcall(_G.UnitIsDeadOrGhost, unitToken)
  if not okDead or Compat.IsSecretOrRestrictedValue(isDead) or type(isDead) ~= "boolean" then
    return { status = "observation_unavailable", matched = false, reason = "unit_dead_probe_unavailable" }
  end
  if isDead == true then
    return { status = "not_matched", matched = false, reason = "unit_dead" }
  end

  local okAtk, canAtk = pcall(_G.UnitCanAttack, "player", unitToken)
  if not okAtk or Compat.IsSecretOrRestrictedValue(canAtk) or type(canAtk) ~= "boolean" then
    return { status = "observation_unavailable", matched = false, reason = "unit_hostility_probe_unavailable" }
  end
  if canAtk == false then
    return { status = "not_matched", matched = false, reason = "unit_not_attackable" }
  end

  local readableIdentity = false
  local matched = false
  local cleanGuid, cleanNpcID, cleanName = nil, nil, nil
  local sawIdentityError = false

  if type(_G.UnitGUID) == "function" then
    local okGuid, guid = pcall(_G.UnitGUID, unitToken)
    if not okGuid or Compat.IsSecretOrRestrictedValue(guid) then
      sawIdentityError = true
    elseif type(guid) == "string" and guid ~= "" then
      readableIdentity = true
      cleanGuid = guid
      cleanNpcID = extractCreatureNpcIDFromGUID(guid)
      if cleanNpcID and npcIDSet[cleanNpcID] == true then
        matched = true
      end
    end
  end

  if type(_G.UnitName) == "function" then
    local okNm, nm = pcall(_G.UnitName, unitToken)
    if not okNm or Compat.IsSecretOrRestrictedValue(nm) then
      sawIdentityError = true
    elseif type(nm) == "string" and nm ~= "" then
      readableIdentity = true
      cleanName = nm
      if npcNameSet[nm] == true or npcNameSet[string.lower(nm)] == true then
        matched = true
      end
    end
  end

  if not readableIdentity then
    return {
      status = "observation_unavailable",
      matched = false,
      reason = sawIdentityError and "unit_identity_restricted" or "unit_identity_unavailable",
    }
  end

  if matched then
    return {
      status = "matched_live_hostile",
      matched = true,
      unitToken = unitToken,
      guid = cleanGuid,
      npcID = cleanNpcID,
      name = cleanName,
    }
  end

  return {
    status = "not_matched",
    matched = false,
    reason = "identity_mismatch",
    unitToken = unitToken,
    guid = cleanGuid,
    npcID = cleanNpcID,
    name = cleanName,
  }
end

function Compat.ObserveMatchingHostileTargetOrNameplate(npcIDSet, npcNameSet)
  if ns.State and ns.State.overrideHasMatchingHostileTarget ~= nil then
    if ns.State.overrideHasMatchingHostileTarget == true then
      return { status = "matched_live_hostile", matched = true, source = "override" }
    elseif ns.State.overrideHasMatchingHostileTarget == false then
      return { status = "not_matched", matched = false, source = "override" }
    end
    return { status = "observation_unavailable", matched = false, source = "override" }
  end

  local sawUnavailable = false
  for _, tok in ipairs({ "target", "mouseover" }) do
    local obs = Compat.ObserveUnitForTargetSet(tok, npcIDSet, npcNameSet)
    if obs.status == "matched_live_hostile" then
      return obs
    elseif obs.status == "observation_unavailable" then
      sawUnavailable = true
    end
  end

  if _G.C_NamePlate and type(_G.C_NamePlate.GetNamePlates) == "function" then
    local okPlates, plates = pcall(_G.C_NamePlate.GetNamePlates)
    if not okPlates or Compat.IsSecretOrRestrictedValue(plates) or type(plates) ~= "table" then
      sawUnavailable = true
    else
      local okLen, plateCount = pcall(function() return #plates end)
      if not okLen or Compat.IsSecretOrRestrictedValue(plateCount) or type(plateCount) ~= "number" then
        sawUnavailable = true
      else
        local maxScan = math.min(plateCount, 40)
        for i = 1, maxScan do
          local okEntry, plate = pcall(function() return plates[i] end)
          if not okEntry or Compat.IsSecretOrRestrictedValue(plate) or type(plate) ~= "table" then
            sawUnavailable = true
          else
            local token = nil
            local okTok1, rawTok1 = pcall(function() return plate.namePlateUnitToken end)
            if not okTok1 or Compat.IsSecretOrRestrictedValue(rawTok1) then
              sawUnavailable = true
            elseif type(rawTok1) == "string" and rawTok1 ~= "" then
              token = rawTok1
            end

            if token == nil then
              local okUF, uf = pcall(function() return plate.UnitFrame end)
              if not okUF or Compat.IsSecretOrRestrictedValue(uf) then
                sawUnavailable = true
              elseif type(uf) == "table" then
                local okTok2, rawTok2 = pcall(function() return uf.unit end)
                if not okTok2 or Compat.IsSecretOrRestrictedValue(rawTok2) then
                  sawUnavailable = true
                elseif type(rawTok2) == "string" and rawTok2 ~= "" then
                  token = rawTok2
                end
              end
            end

            if token ~= nil then
              local obs = Compat.ObserveUnitForTargetSet(token, npcIDSet, npcNameSet)
              if obs.status == "matched_live_hostile" then
                return obs
              elseif obs.status == "observation_unavailable" then
                sawUnavailable = true
              end
            end
          end
        end
      end
    end
  end

  if sawUnavailable then
    return { status = "observation_unavailable", matched = false, reason = "partial_or_restricted_probe" }
  end
  return { status = "not_matched", matched = false, reason = "none_observed" }
end

function Compat.HasMatchingHostileTargetOrNameplate(npcIDSet, npcNameSet)
  local obs = Compat.ObserveMatchingHostileTargetOrNameplate(npcIDSet, npcNameSet)
  return type(obs) == "table" and obs.status == "matched_live_hostile"
end

local TWO_PI = math.pi * 2

local function atan2Radians(y, x)
  if type(math.atan2) == "function" then
    return math.atan2(y, x)
  end
  if x > 0 then
    return math.atan(y / x)
  elseif x < 0 and y >= 0 then
    return math.atan(y / x) + math.pi
  elseif x < 0 and y < 0 then
    return math.atan(y / x) - math.pi
  elseif x == 0 and y > 0 then
    return math.pi / 2
  elseif x == 0 and y < 0 then
    return -math.pi / 2
  end
  return 0
end

-- UTF-8 boundary-safe truncation (never splits multi-byte codepoints like `—`, `•`, or localized names).
function Compat.UTF8Truncate(text, maxCodepoints)
  local s = tostring(text or "")
  maxCodepoints = math.max(2, tonumber(maxCodepoints) or 34)
  local byteLen = #s
  if byteLen <= maxCodepoints then
    return s
  end
  local i = 1
  local count = 0
  local cutPos = nil
  while i <= byteLen do
    count = count + 1
    if count == maxCodepoints then
      cutPos = i - 1
    end
    local b = string.byte(s, i)
    if b < 0x80 then
      i = i + 1
    elseif b >= 0xC0 and b < 0xE0 then
      i = i + 2
    elseif b >= 0xE0 and b < 0xF0 then
      i = i + 3
    elseif b >= 0xF0 then
      i = i + 4
    else
      i = i + 1
    end
  end
  if count <= maxCodepoints then
    return s
  end
  return string.sub(s, 1, cutPos or (maxCodepoints - 1)) .. "…"
end

function Compat.HasStartupArrowAsset()
  if ns.State and ns.State.overrideStartupArrowAsset ~= nil then
    return ns.State.overrideStartupArrowAsset == true
  end
  local addonNameKey = (ns and ns.name) or "ForeverHub"
  if C_AddOns and type(C_AddOns.GetAddOnMetadata) == "function" then
    local ok, val = pcall(C_AddOns.GetAddOnMetadata, addonNameKey, "X-ForeverHub-Assets")
    if ok and type(val) == "string" then
      return val == "arrow-v1"
    end
  elseif type(GetAddOnMetadata) == "function" then
    local ok, val = pcall(GetAddOnMetadata, addonNameKey, "X-ForeverHub-Assets")
    if ok and type(val) == "string" then
      return val == "arrow-v1"
    end
  end
  return false
end

function Compat.GetPlayerFacingRadiansRaw()
  if ns.State and ns.State.overridePlayerFacing ~= nil then
    local ov = ns.State.overridePlayerFacing
    if type(ov) == "number" and Compat.IsFiniteNumber(ov) then
      return true, ((ov % TWO_PI) + TWO_PI) % TWO_PI, nil
    end
    return false, nil, tostring(ov)
  end
  if type(GetPlayerFacing) ~= "function" then
    return false, nil, "missing_get_player_facing"
  end
  local ok, facing = pcall(GetPlayerFacing)
  if not ok or facing == nil or Compat.IsSecretOrRestrictedValue(facing) then
    return false, nil, "facing_restricted_or_nil"
  end
  facing = tonumber(facing)
  if not Compat.IsFiniteNumber(facing) then
    return false, nil, "facing_non_finite"
  end
  return true, ((facing % TWO_PI) + TWO_PI) % TWO_PI, nil
end

function Compat.GetPlayerFacingRadians()
  local ok, rad, reason = Compat.GetPlayerFacingRadiansRaw()
  if ok then
    return { status = "ok", radians = rad }
  end
  return { status = "unavailable", radians = nil, reason = reason or "unavailable" }
end

-- Returns `(ok, northYards, westYards, instanceID)` with zero table allocations for OnUpdate hot paths.
-- In WoW 1.60.1, `UnitPosition("player")` returns `(posNorth, posWest, posZ, instanceID)`, matching
-- `C_Map.GetWorldPosFromMapPos` (`worldPos:GetXY() -> north, west`).
function Compat.GetPlayerWorldPositionRaw()
  if ns.State and ns.State.overridePlayerWorldPosition ~= nil then
    local ov = ns.State.overridePlayerWorldPosition
    if type(ov) == "table" then
      local n = tonumber(ov.north or ov.y or ov[1])
      local w = tonumber(ov.west or ov.x or ov[2])
      local inst = tonumber(ov.instanceID or ov.instance or ov[3])
      if Compat.IsFiniteNumber(n) and Compat.IsFiniteNumber(w) and Compat.IsFiniteNumber(inst) then
        return true, n, w, inst
      end
    end
    return false, nil, nil, nil
  end
  if type(UnitPosition) ~= "function" then
    return false, nil, nil, nil
  end
  local ok, north, west, _z, instanceID = pcall(UnitPosition, "player")
  if not ok or north == nil or west == nil then
    return false, nil, nil, tonumber(instanceID)
  end
  if Compat.IsSecretOrRestrictedValue(north)
    or Compat.IsSecretOrRestrictedValue(west)
    or Compat.IsSecretOrRestrictedValue(instanceID)
  then
    return false, nil, nil, nil
  end
  north = tonumber(north)
  west = tonumber(west)
  instanceID = tonumber(instanceID)
  if not Compat.IsFiniteNumber(north) or not Compat.IsFiniteNumber(west) or not Compat.IsFiniteNumber(instanceID) then
    return false, nil, nil, nil
  end
  return true, north, west, instanceID
end

-- Resolves and caches destination world coordinates & map world size ONCE per step change (zero OnUpdate churn).
function Compat.ResolveTargetWorldAnchor(uiMapID, x01, y01, arrivalRadiusYards)
  uiMapID = tonumber(uiMapID)
  x01 = tonumber(x01)
  y01 = tonumber(y01)
  if not Compat.IsFiniteNumber(uiMapID) or uiMapID <= 0
    or not Compat.IsFiniteNumber(x01) or not Compat.IsFiniteNumber(y01)
    or x01 <= 0 or x01 >= 1 or y01 <= 0 or y01 >= 1
  then
    return nil
  end

  local anchor = {
    uiMapID = uiMapID,
    x01 = x01,
    y01 = y01,
    arrivalRadiusYards = math.max(5, tonumber(arrivalRadiusYards) or 15),
    hasWorldCoords = false,
    continentInstanceID = nil,
    targetNorth = nil,
    targetWest = nil,
    hasZoneSize = false,
    widthYards = nil,
    heightYards = nil,
  }

  if ns.State and type(ns.State.overrideTargetWorldPositions) == "table" then
    local key = string.format("%d:%.4f:%.4f", uiMapID, x01, y01)
    local ov = ns.State.overrideTargetWorldPositions[key] or ns.State.overrideTargetWorldPositions[uiMapID]
    if type(ov) == "table" then
      local tn = tonumber(ov.north)
      local tw = tonumber(ov.west)
      local inst = tonumber(ov.instanceID)
      if Compat.IsFiniteNumber(tn) and Compat.IsFiniteNumber(tw) and Compat.IsFiniteNumber(inst) then
        anchor.hasWorldCoords = true
        anchor.continentInstanceID = inst
        anchor.targetNorth = tn
        anchor.targetWest = tw
      end
    end
  elseif C_Map and type(C_Map.GetWorldPosFromMapPos) == "function" then
    local makeVec = type(_G.CreateVector2D) == "function" and _G.CreateVector2D
      or function(vx, vy)
        return { x = vx, y = vy, GetXY = function(self) return self.x, self.y end }
      end
    local okW, instID, wp = pcall(C_Map.GetWorldPosFromMapPos, uiMapID, makeVec(x01, y01))
    if okW and wp and instID ~= nil and not Compat.IsSecretOrRestrictedValue(instID) and not Compat.IsSecretOrRestrictedValue(wp) then
      local tn = type(wp.GetXY) == "function" and select(1, wp:GetXY()) or wp.x
      local tw = type(wp.GetXY) == "function" and select(2, wp:GetXY()) or wp.y
      tn = tonumber(tn)
      tw = tonumber(tw)
      instID = tonumber(instID)
      if Compat.IsFiniteNumber(tn) and Compat.IsFiniteNumber(tw) and Compat.IsFiniteNumber(instID) then
        anchor.hasWorldCoords = true
        anchor.continentInstanceID = instID
        anchor.targetNorth = tn
        anchor.targetWest = tw
      end
    end
  end

  local sz = Compat.GetMapWorldSizeYards(uiMapID)
  if sz.status == "ok" and Compat.IsFiniteNumber(sz.widthYards) and Compat.IsFiniteNumber(sz.heightYards) then
    anchor.hasZoneSize = true
    anchor.widthYards = sz.widthYards
    anchor.heightYards = sz.heightYards
  end

  anchor.isUsable = (anchor.hasWorldCoords or anchor.hasZoneSize)
  anchor.isComplete = (anchor.hasWorldCoords and anchor.hasZoneSize)
  return anchor
end

function Compat.ComputeArrowAlignmentColor(absTurnRadians, isArrived)
  if isArrived then
    return 0.20, 1.00, 0.76
  end
  local t = math.max(0, math.min(1, (tonumber(absTurnRadians) or 0) / math.pi))
  if t <= 0.5 then
    local u = t * 2.0
    -- Crisp Emerald Green (0.15, 0.96, 0.42) -> Warm Gold (1.00, 0.80, 0.16)
    return 0.15 + (1.00 - 0.15) * u, 0.96 + (0.80 - 0.96) * u, 0.42 + (0.16 - 0.42) * u
  else
    local u = (t - 0.5) * 2.0
    -- Warm Gold (1.00, 0.80, 0.16) -> Coral Red (0.98, 0.28, 0.28)
    return 1.00 + (0.98 - 1.00) * u, 0.80 + (0.28 - 0.80) * u, 0.16 + (0.28 - 0.16) * u
  end
end

-- Computes live distance in yards, world bearing, relative arrow rotation (`Texture:SetRotation` CCW radians),
-- and alignment tint into `out` (allocates zero tables on BOTH `world_coords` and `same_map_size` paths when `out` is supplied).
function Compat.ComputeNavigationVector(anchor, out)
  out = out or {}
  out.status = "unavailable"
  out.reason = nil
  out.yards = nil
  out.worldBearingRadians = nil
  out.playerFacingRadians = nil
  out.rotationRadians = nil
  out.signedTurnRadians = nil
  out.absTurnRadians = nil
  out.isArrived = false
  out.nearZeroDistance = false
  out.isCrossZone = false
  out.playerUiMapID = nil
  out.vectorSource = nil
  out.colorR, out.colorG, out.colorB = 1, 1, 1

  if type(anchor) ~= "table" then
    out.reason = "missing_anchor"
    return out
  end
  if not anchor.hasWorldCoords and not anchor.hasZoneSize then
    out.status = "missing_transform"
    out.reason = "target_transform_unavailable"
    return out
  end

  local dNorth, dWest = nil, nil
  local okWorld, pNorth, pWest, pInst = Compat.GetPlayerWorldPositionRaw()
  if okWorld and anchor.hasWorldCoords and pInst == anchor.continentInstanceID then
    dNorth = anchor.targetNorth - pNorth
    dWest = anchor.targetWest - pWest
    out.vectorSource = "world_coords"
    local okMap, curMapID = Compat.GetPlayerUiMapIDRaw()
    if okMap then
      out.playerUiMapID = curMapID
      out.isCrossZone = (curMapID ~= anchor.uiMapID)
    end
  end

  if dNorth == nil then
    local posStatus, pMapID, px01, py01, posReason = Compat.GetPlayerPosition01Raw()
    if posStatus == "ok" then
      out.playerUiMapID = pMapID
      if pMapID == anchor.uiMapID then
        if anchor.hasZoneSize then
          -- Map X increases West->East (-West); Map Y increases North->South (-North)
          dNorth = (py01 - anchor.y01) * anchor.heightYards
          dWest = (px01 - anchor.x01) * anchor.widthYards
          out.vectorSource = "same_map_size"
          out.isCrossZone = false
        else
          out.status = "missing_transform"
          out.reason = "zone_world_size_unavailable"
          return out
        end
      elseif okWorld and anchor.hasWorldCoords and pInst ~= nil and pInst ~= anchor.continentInstanceID then
        out.status = "different_instance"
        out.reason = "different_instance_or_continent"
        return out
      else
        out.status = "different_zone"
        out.reason = "cross_zone_without_world_pos"
        return out
      end
    elseif okWorld and anchor.hasWorldCoords and pInst ~= nil and pInst ~= anchor.continentInstanceID then
      out.status = "different_instance"
      out.reason = "different_instance_or_continent"
      return out
    else
      out.status = "unavailable"
      out.reason = posReason or "player_position_unavailable"
      return out
    end
  end

  local yards = math.sqrt((dNorth * dNorth) + (dWest * dWest))
  out.yards = yards
  out.isArrived = (yards <= (anchor.arrivalRadiusYards or 15))
  out.nearZeroDistance = (yards < 2.0)

  local okFace, facingRad, faceReason = Compat.GetPlayerFacingRadiansRaw()
  if not okFace then
    out.status = "facing_unavailable"
    out.reason = faceReason or "facing_unavailable"
    return out
  end

  -- World bearing counter-clockwise from North (`0` = North, `pi/2` = West, `pi` = South, `3*pi/2` = East)
  local rawBearing = out.nearZeroDistance and facingRad or atan2Radians(dWest, dNorth)
  local bearing = ((rawBearing % TWO_PI) + TWO_PI) % TWO_PI
  local rotation = ((bearing - facingRad) % TWO_PI + TWO_PI) % TWO_PI
  local signedTurn = ((rotation + math.pi) % TWO_PI) - math.pi
  local absTurn = math.abs(signedTurn)

  out.status = "ok"
  out.worldBearingRadians = bearing
  out.playerFacingRadians = facingRad
  out.rotationRadians = rotation
  out.signedTurnRadians = signedTurn
  out.absTurnRadians = absTurn
  out.colorR, out.colorG, out.colorB = Compat.ComputeArrowAlignmentColor(absTurn, out.isArrived)
  return out
end

-- Capability-safe item visual adapter (Astra v0.8.0):
-- Resolves live item icon, quality, and localized name without assuming Retail-only C_Item APIs.
-- Missing or uncached item data returns `hasIcon = false` so callers render a neutral placeholder.
function Compat.GetItemVisualInfo(itemID)
  local id = tonumber(itemID)
  if not id or id <= 0 then
    return { itemID = nil, icon = nil, quality = nil, name = nil, hasIcon = false, cached = false }
  end

  local icon, quality, name = nil, nil, nil

  if type(_G.C_Item) == "table" and type(_G.C_Item.GetItemInfo) == "function" then
    local ok, n, _, q, _, _, _, _, _, _, tex = pcall(_G.C_Item.GetItemInfo, id)
    if ok then
      if type(n) == "string" and n ~= "" and not Compat.IsSecretOrRestrictedValue(n) then
        name = n
      end
      if type(q) == "number" and not Compat.IsSecretOrRestrictedValue(q) then
        quality = q
      end
      if (type(tex) == "number" or (type(tex) == "string" and tex ~= "")) and not Compat.IsSecretOrRestrictedValue(tex) then
        icon = tex
      end
    end
  end

  if (name == nil or icon == nil) and type(_G.GetItemInfo) == "function" then
    local ok, n, _, q, _, _, _, _, _, _, tex = pcall(_G.GetItemInfo, id)
    if ok then
      if name == nil and type(n) == "string" and n ~= "" and not Compat.IsSecretOrRestrictedValue(n) then
        name = n
      end
      if quality == nil and type(q) == "number" and not Compat.IsSecretOrRestrictedValue(q) then
        quality = q
      end
      if icon == nil and (type(tex) == "number" or (type(tex) == "string" and tex ~= "")) and not Compat.IsSecretOrRestrictedValue(tex) then
        icon = tex
      end
    end
  end

  if icon == nil and type(_G.C_Item) == "table" and type(_G.C_Item.GetItemIconByID) == "function" then
    local ok, tex = pcall(_G.C_Item.GetItemIconByID, id)
    if ok and (type(tex) == "number" or (type(tex) == "string" and tex ~= "")) and not Compat.IsSecretOrRestrictedValue(tex) then
      icon = tex
    end
  end

  if icon == nil and type(_G.GetItemIcon) == "function" then
    local ok, tex = pcall(_G.GetItemIcon, id)
    if ok and (type(tex) == "number" or (type(tex) == "string" and tex ~= "")) and not Compat.IsSecretOrRestrictedValue(tex) then
      icon = tex
    end
  end

  if icon == nil and type(_G.C_Item) == "table" and type(_G.C_Item.GetItemInfoInstant) == "function" then
    local ok, _, _, _, _, tex = pcall(_G.C_Item.GetItemInfoInstant, id)
    if ok and (type(tex) == "number" or (type(tex) == "string" and tex ~= "")) and not Compat.IsSecretOrRestrictedValue(tex) then
      icon = tex
    end
  end

  if icon == nil and type(_G.GetItemInfoInstant) == "function" then
    local ok, _, _, _, _, tex = pcall(_G.GetItemInfoInstant, id)
    if ok and (type(tex) == "number" or (type(tex) == "string" and tex ~= "")) and not Compat.IsSecretOrRestrictedValue(tex) then
      icon = tex
    end
  end

  return {
    itemID = id,
    icon = icon,
    quality = quality,
    name = name,
    hasIcon = (icon ~= nil),
    cached = (name ~= nil),
  }
end

function Compat.RequestItemVisualLoad(itemID)
  local id = tonumber(itemID)
  if not id or id <= 0 then
    return false
  end
  return Compat.RequestLoadItemData(id)
end

-- ============================================================================
-- v0.8.4 Live Client Quest-Target Self-Healing (Defense-in-Depth Layer 2)
-- Cross-checks single-spot turn-in and objective steps against live client
-- map POIs (`C_QuestLog.GetQuestsOnMap`), Quest Log objective recipient text,
-- and observed quest-giver identity so unannounced server hotfixes self-heal.
-- ============================================================================

local QUEST_TEXT_RANK_PREFIX_WORDS = {
  abbot = true,
  barracks = true,
  brother = true,
  captain = true,
  cavalry = true,
  chief = true,
  commander = true,
  corporal = true,
  doctor = true,
  foreman = true,
  guard = true,
  innkeeper = true,
  knight = true,
  lady = true,
  lieutenant = true,
  lord = true,
  marshal = true,
  master = true,
  professor = true,
  scout = true,
  sergeant = true,
  sister = true,
  watcher = true,
  wharfmaster = true,
}

local QUEST_TEXT_PRIORITY_CUES = {
  " return to ",
  " speak to ",
  " speak with ",
  " talk to ",
  " talk with ",
  " report to ",
}

local QUEST_TEXT_GENERAL_CUES = {
  " for ",
  " to ",
  " with ",
}

function Compat.GetLiveMapQuestsByID(uiMapID)
  uiMapID = tonumber(uiMapID)
  if not Compat.IsFiniteNumber(uiMapID) or uiMapID <= 0 then
    return {}
  end

  if ns.State and type(ns.State.overrideMapQuestsByUiMapID) == "table" then
    local rawOv = ns.State.overrideMapQuestsByUiMapID[uiMapID]
    local out = {}
    if type(rawOv) == "table" then
      for k, row in pairs(rawOv) do
        if type(row) == "table" then
          local qid = tonumber(row.questID or k)
          local x = tonumber(row.x01 or row.x)
          local y = tonumber(row.y01 or row.y)
          if qid and qid > 0 and Compat.IsFiniteNumber(x) and Compat.IsFiniteNumber(y) and x > 0 and x < 1 and y > 0 and y < 1 then
            out[qid] = { questID = qid, x01 = x, y01 = y }
          end
        end
      end
    end
    return out
  end

  local now = Compat.NowSeconds()
  local cached = Compat.liveMapQuestsCache[uiMapID]
  if cached and now < (cached.expiresAt or 0) and type(cached.byID) == "table" then
    return cached.byID
  end

  local byID = {}
  if C_QuestLog and type(C_QuestLog.GetQuestsOnMap) == "function" then
    local ok, list = pcall(C_QuestLog.GetQuestsOnMap, uiMapID)
    if ok and type(list) == "table" and not Compat.IsSecretOrRestrictedValue(list) then
      for _, row in ipairs(list) do
        if type(row) == "table" and not Compat.IsSecretOrRestrictedValue(row) then
          local rawQid = row.questID
          local rawX = row.x ~= nil and row.x or row.x01
          local rawY = row.y ~= nil and row.y or row.y01
          if not Compat.IsSecretOrRestrictedValue(rawQid)
            and not Compat.IsSecretOrRestrictedValue(rawX)
            and not Compat.IsSecretOrRestrictedValue(rawY)
          then
            local qid = tonumber(rawQid)
            local x = tonumber(rawX)
            local y = tonumber(rawY)
            if qid and qid > 0 and Compat.IsFiniteNumber(x) and Compat.IsFiniteNumber(y) and x > 0 and x < 1 and y > 0 and y < 1 then
              byID[qid] = { questID = qid, x01 = x, y01 = y }
            end
          end
        end
      end
    end
  end

  Compat.liveMapQuestsCache[uiMapID] = {
    expiresAt = now + LIVE_MAP_QUESTS_CACHE_TTL_SECONDS,
    byID = byID,
  }
  return byID
end

function Compat.MatchNpcFromQuestText(rawText, route)
  if type(rawText) ~= "string" or rawText == "" or Compat.IsSecretOrRestrictedValue(rawText) then
    return nil
  end
  if type(route) ~= "table" or type(route.npcDirectoryByNormName) ~= "table" or type(route.npcDirectoryByID) ~= "table" then
    return nil
  end

  local byNorm = route.npcDirectoryByNormName
  local byID = route.npcDirectoryByID
  local cleaned = string.lower(rawText)
  cleaned = string.gsub(cleaned, "[^%w'%-%s]", " ")
  cleaned = string.gsub(cleaned, "%s+", " ")
  cleaned = " " .. cleaned .. " "

  local function matchAfterCue(cue)
    local searchFrom = 1
    while true do
      local sPos, ePos = string.find(cleaned, cue, searchFrom, true)
      if not sPos then
        return nil
      end
      searchFrom = sPos + 1
      local tail = string.sub(cleaned, ePos + 1)
      local tokens = {}
      for rawTok in string.gmatch(tail, "[%w'%-]+") do
        local tok = string.gsub(string.gsub(rawTok, "^['%-]+", ""), "['%-]+$", "")
        if tok ~= "" then
          table.insert(tokens, tok)
          if #tokens >= 6 then
            break
          end
        end
      end
      if #tokens > 0 then
        local maxStart = 1
        while maxStart < #tokens and maxStart <= 3 and QUEST_TEXT_RANK_PREFIX_WORDS[tokens[maxStart]] do
          maxStart = maxStart + 1
        end
        for startIdx = 1, maxStart do
          local maxLen = math.min(4, #tokens - startIdx + 1)
          for wLen = maxLen, 1, -1 do
            local cand = table.concat(tokens, " ", startIdx, startIdx + wLen - 1)
            if wLen > 1 or #cand >= 5 then
              local npcID = byNorm[cand]
              if npcID and type(byID[npcID]) == "table" then
                return byID[npcID]
              end
            end
          end
        end
      end
    end
  end

  for _, cue in ipairs(QUEST_TEXT_PRIORITY_CUES) do
    local hit = matchAfterCue(cue)
    if hit then
      return hit
    end
  end
  for _, cue in ipairs(QUEST_TEXT_GENERAL_CUES) do
    local hit = matchAfterCue(cue)
    if hit then
      return hit
    end
  end
  return nil
end

function Compat.ReadSafeQuestLogObjectiveText(questID, normTitle, progress)
  local qid = tonumber(questID)
  if qid and qid <= 0 then
    qid = nil
  end

  if ns.State and type(ns.State.overrideQuestObjectiveTexts) == "table" then
    local ov = (qid and ns.State.overrideQuestObjectiveTexts[qid])
      or (normTitle and ns.State.overrideQuestObjectiveTexts["title:" .. normTitle])
      or nil
    if type(ov) == "string" and ov ~= "" then
      return ov
    end
  end

  if qid and type(Compat.questObjectiveTextByID[qid]) == "string" and Compat.questObjectiveTextByID[qid] ~= "" then
    return Compat.questObjectiveTextByID[qid]
  end

  if qid and ns.State and type(ns.State.GetObservedQuestObjectiveText) == "function" then
    local persisted = ns.State.GetObservedQuestObjectiveText(qid, progress)
    if type(persisted) == "string" and persisted ~= "" then
      Compat.questObjectiveTextByID[qid] = persisted
      return persisted
    end
  end

  if Compat.IsInCombat() then
    return nil
  end
  if _G.QuestLogFrame and type(_G.QuestLogFrame.IsShown) == "function" and _G.QuestLogFrame:IsShown() then
    return nil
  end
  if _G.WorldMapFrame and type(_G.WorldMapFrame.IsShown) == "function" and _G.WorldMapFrame:IsShown() then
    return nil
  end
  if type(_G.GetQuestLogQuestText) ~= "function" then
    return nil
  end

  local logIndex = Compat.ResolveFreshQuestLogIndex(qid, normTitle)
  if not logIndex then
    return nil
  end

  local prevSel = nil
  if type(_G.GetQuestLogSelection) == "function" then
    local okSel, curSel = pcall(_G.GetQuestLogSelection)
    if okSel and type(curSel) == "number" and not Compat.IsSecretOrRestrictedValue(curSel) then
      prevSel = curSel
    end
  end

  if type(_G.SelectQuestLogEntry) == "function" then
    pcall(_G.SelectQuestLogEntry, logIndex)
  end
  local okTxt, _, questObjectives = pcall(_G.GetQuestLogQuestText, logIndex)
  if prevSel and prevSel > 0 and prevSel ~= logIndex and type(_G.SelectQuestLogEntry) == "function" then
    pcall(_G.SelectQuestLogEntry, prevSel)
  end

  if okTxt and type(questObjectives) == "string" and questObjectives ~= "" and not Compat.IsSecretOrRestrictedValue(questObjectives) then
    if qid then
      Compat.questObjectiveTextByID[qid] = questObjectives
      if ns.State and type(ns.State.RecordObservedQuestObjectiveText) == "function" then
        ns.State.RecordObservedQuestObjectiveText(qid, questObjectives, progress)
      end
    end
    return questObjectives
  end
  return nil
end

local function estimateHeuristicDistanceYards(uiMapID, ax01, ay01, bx01, by01)
  local dRes = Compat.GetWorldDistanceYards(uiMapID, ax01, ay01, bx01, by01)
  if type(dRes) == "table" and dRes.status == "ok" and Compat.IsFiniteNumber(dRes.yards) then
    return dRes.yards
  end
  local dx = (tonumber(ax01) - tonumber(bx01)) * 3600.0
  local dy = (tonumber(ay01) - tonumber(by01)) * 2400.0
  return math.sqrt(dx * dx + dy * dy)
end

local function isQuestObjectiveTargetNpc(route, questID, npcID)
  if type(route) ~= "table" or type(route.actions) ~= "table" or not questID or not npcID then
    return false
  end
  for _, act in ipairs(route.actions) do
    if type(act) == "table" and act.kind == "objective" and tonumber(act.questID) == questID then
      if tonumber(act.npcID) == npcID then
        return true
      end
      if type(act.subLocations) == "table" then
        for _, sl in ipairs(act.subLocations) do
          if type(sl) == "table" and tonumber(sl.targetNpcID) == npcID then
            return true
          end
        end
      end
    end
  end
  return false
end

local function findNearestDirectoryNpc(route, uiMapID, x01, y01, maxNormRadius)
  if type(route) ~= "table" or type(route.npcDirectoryByID) ~= "table" then
    return nil
  end
  local bestNpc = nil
  local bestSq = (maxNormRadius or 0.008) * (maxNormRadius or 0.008)
  for _, entry in pairs(route.npcDirectoryByID) do
    if type(entry) == "table" and tonumber(entry.uiMapID) == uiMapID then
      local ex = tonumber(entry.x01)
      local ey = tonumber(entry.y01)
      if ex and ey then
        local dx = ex - x01
        local dy = ey - y01
        local sq = dx * dx + dy * dy
        if sq <= bestSq then
          bestSq = sq
          bestNpc = entry
        end
      end
    end
  end
  return bestNpc
end

function Compat.ResolveLiveQuestTargetOverride(action, route, progress, ctx, opts)
  local recordDrift = not (type(opts) == "table" and opts.recordDrift == false)
  if type(action) ~= "table" then
    return nil
  end
  if action.kind ~= "turnin" and action.kind ~= "objective" then
    return nil
  end
  if type(action.subLocations) == "table" and #action.subLocations > 0 then
    return nil
  end
  local sDest = action.destination
  if type(sDest) ~= "table" then
    return nil
  end

  if type(route) ~= "table" then
    return nil
  end

  local qRef = action.questID or action.questKey
  if qRef == nil then
    return nil
  end
  local qid, normTitle, qMeta = Compat.ResolveQuestIdentity(qRef)
  if not qid or qid <= 0 then
    return nil
  end
  qMeta = qMeta or (type(route.questsByID) == "table" and route.questsByID[qid]) or nil

  local onRes = (ctx and type(ctx.isOnQuest) == "function") and ctx.isOnQuest(qRef) or Compat.IsOnQuestResult(qRef)
  if type(onRes) ~= "table" or onRes.status ~= "ok" or onRes.value ~= true then
    if recordDrift then
      Compat.liveQuestTargetDrifts[action.actionID] = nil
    end
    return nil
  end

  local objsComplete = false
  if qMeta and qMeta.zeroObjectives == true then
    objsComplete = true
  else
    local objRes = (ctx and type(ctx.getQuestObjectives) == "function")
        and ctx.getQuestObjectives(qRef)
      or Compat.GetQuestObjectivesResult(qRef)
    if type(objRes) == "table" and objRes.status == "ok" and objRes.allFinished == true then
      objsComplete = true
    end
  end

  local staticMapID = tonumber(sDest.uiMapID)
  local staticX = tonumber(sDest.x01)
  local staticY = tonumber(sDest.y01)
  local staticNpcID = tonumber(action.npcID)
  if not staticMapID or not staticX or not staticY then
    return nil
  end

  local candMapID, candAreaID, candX, candY, candName, candNpcID, candSource = nil, nil, nil, nil, nil, nil, nil
  local hasExplicitNpcIdentity = false
  local minDriftYards = 25.0

  if action.kind == "turnin" then
    local objText = Compat.ReadSafeQuestLogObjectiveText(qid, normTitle, progress)
    local textNpc = objText and Compat.MatchNpcFromQuestText(objText, route) or nil
    if textNpc and isQuestObjectiveTargetNpc(route, qid, tonumber(textNpc.npcID)) then
      if not (qMeta and tonumber(qMeta.turninNpcID) == tonumber(textNpc.npcID)) then
        textNpc = nil
      end
    end

    local giverNpc = nil
    if ns.State and type(ns.State.GetObservedQuestGiver) == "function" then
      local obsGiver = ns.State.GetObservedQuestGiver(qid, progress)
      if type(obsGiver) == "table" and qMeta and qMeta.giverNpcID ~= nil and qMeta.giverNpcID == qMeta.turninNpcID then
        local gID = tonumber(obsGiver.npcID)
        if gID and type(route.npcDirectoryByID) == "table" and type(route.npcDirectoryByID[gID]) == "table" then
          giverNpc = route.npcDirectoryByID[gID]
        elseif obsGiver.uiMapID and obsGiver.x01 and obsGiver.y01 then
          giverNpc = {
            npcID = gID,
            name = obsGiver.npcName,
            uiMapID = tonumber(obsGiver.uiMapID),
            areaID = sDest.areaID,
            x01 = tonumber(obsGiver.x01),
            y01 = tonumber(obsGiver.y01),
          }
        end
      end
    end

    local poi = nil
    if objsComplete then
      local mapPois = Compat.GetLiveMapQuestsByID(staticMapID)
      poi = mapPois and mapPois[qid] or nil
    end

    if poi then
      local poiDist = estimateHeuristicDistanceYards(staticMapID, staticX, staticY, poi.x01, poi.y01)
      if poiDist >= 25.0 then
        candMapID = staticMapID
        candX = poi.x01
        candY = poi.y01
        candSource = "live_map_poi"
        local named = textNpc or giverNpc or findNearestDirectoryNpc(route, staticMapID, poi.x01, poi.y01, 0.008)
        if named and tonumber(named.uiMapID) == staticMapID then
          candName = named.name
          candNpcID = tonumber(named.npcID)
          candAreaID = tonumber(named.areaID) or sDest.areaID
        else
          candName = "Quest Turn-in (Live Map POI)"
          candAreaID = sDest.areaID
        end
      end
    end

    if not candX then
      local chosen = textNpc or giverNpc
      if chosen and tonumber(chosen.uiMapID) and tonumber(chosen.x01) and tonumber(chosen.y01) then
        candMapID = tonumber(chosen.uiMapID)
        candAreaID = tonumber(chosen.areaID) or sDest.areaID
        candX = tonumber(chosen.x01)
        candY = tonumber(chosen.y01)
        candName = chosen.name
        candNpcID = tonumber(chosen.npcID)
        candSource = (chosen == textNpc) and "quest_text_npc" or "observed_quest_giver"
        hasExplicitNpcIdentity = (candNpcID ~= nil)
      end
    end
  elseif action.kind == "objective" and not objsComplete then
    minDriftYards = 80.0
    local mapPois = Compat.GetLiveMapQuestsByID(staticMapID)
    local poi = mapPois and mapPois[qid] or nil
    if poi then
      candMapID = staticMapID
      candAreaID = sDest.areaID
      candX = poi.x01
      candY = poi.y01
      candName = action.npcName
      candNpcID = staticNpcID
      candSource = "live_map_poi"
    end
  end

  if not candMapID or not candX or not candY or candX <= 0 or candX >= 1 or candY <= 0 or candY >= 1 then
    if recordDrift then
      Compat.liveQuestTargetDrifts[action.actionID] = nil
    end
    return nil
  end

  local crossZone = (candMapID ~= staticMapID)
  local distYards = crossZone and 9999.0 or estimateHeuristicDistanceYards(staticMapID, staticX, staticY, candX, candY)
  local npcChanged = hasExplicitNpcIdentity and staticNpcID ~= nil and candNpcID ~= staticNpcID

  if not crossZone and not npcChanged and distYards < minDriftYards then
    if recordDrift then
      Compat.liveQuestTargetDrifts[action.actionID] = nil
    end
    return nil
  end

  local override = {
    actionID = action.actionID,
    questID = qid,
    kind = action.kind,
    source = candSource,
    deltaYards = math.floor(distYards + 0.5),
    staticNpcID = staticNpcID,
    staticNpcName = action.npcName,
    staticX01 = staticX,
    staticY01 = staticY,
    npcID = candNpcID,
    targetName = candName or action.npcName,
    destination = {
      uiMapID = candMapID,
      areaID = candAreaID or sDest.areaID,
      x01 = candX,
      y01 = candY,
      coordinateSpace = "uiMap01",
      coordConfidence = "live_client_healed",
    },
  }
  if recordDrift then
    Compat.liveQuestTargetDrifts[action.actionID] = override
  end
  return override
end

-- ============================================================================
-- Phase 0 Economy Runtime Capability Probes (`contracts/market-projection-v1.md`)
-- Read-only capability & safe return-shape inspection; NEVER invokes protected
-- purchase, post, craft, or mail-extraction operations.
-- ============================================================================

function Compat.GetServerTimeSafe()
  local getSrv = _G.GetServerTime
  if type(getSrv) == "function" then
    local ok, val = pcall(getSrv)
    if ok and not Compat.IsSecretOrRestrictedValue(val) and Compat.IsFiniteNumber(val) and val > 0 then
      return {
        epochSec = math.floor(val),
        authority = "server_time",
      }
    end
  end
  if type(time) == "function" then
    local okT, localT = pcall(time)
    if okT and not Compat.IsSecretOrRestrictedValue(localT) and Compat.IsFiniteNumber(localT) and localT > 0 then
      return {
        epochSec = math.floor(localT),
        authority = "local_clock",
      }
    end
  end
  return {
    epochSec = nil,
    authority = "unavailable",
  }
end

local function hasFunctionAt(tbl, key)
  if Compat.IsSecretOrRestrictedValue(tbl) or type(tbl) ~= "table" then
    return false
  end
  local v = tbl[key]
  if Compat.IsSecretOrRestrictedValue(v) then
    return false
  end
  return type(v) == "function"
end

function Compat.ProbeEconomyRuntimeCapabilities()
  local version, build, tocVersion = "unknown", "unknown", 0
  if type(_G.GetBuildInfo) == "function" then
    local okB, v, b, _, t = pcall(_G.GetBuildInfo)
    if okB then
      if not Compat.IsSecretOrRestrictedValue(v) and type(v) == "string" then
        version = v
      end
      if not Compat.IsSecretOrRestrictedValue(b) and type(b) == "string" then
        build = b
      end
      if not Compat.IsSecretOrRestrictedValue(t) and Compat.IsFiniteNumber(t) then
        tocVersion = math.floor(t)
      end
    end
  end

  local cAH = _G.C_AuctionHouse
  local hasModernAH = (not Compat.IsSecretOrRestrictedValue(cAH))
    and type(cAH) == "table"
    and (hasFunctionAt(cAH, "SendBrowseQuery") or hasFunctionAt(cAH, "SendSearchQuery"))
  local hasLegacyAH = hasFunctionAt(_G, "QueryAuctionItems") and hasFunctionAt(_G, "GetAuctionItemInfo")
  local ahFamily = "unavailable"
  if hasModernAH and hasLegacyAH then
    ahFamily = "hybrid_both"
  elseif hasModernAH then
    ahFamily = "modern_c_auctionhouse"
  elseif hasLegacyAH then
    ahFamily = "legacy_ah"
  end

  local liveAuctionWindowShape = nil
  local inCombat = Compat.IsInCombat()
  if not inCombat and ns.State and ns.State.ahOpen == true then
    if hasLegacyAH and hasFunctionAt(_G, "GetNumAuctionItems") then
      local okCount, batchCount, totalCount = pcall(_G.GetNumAuctionItems, "list")
      if okCount
        and not Compat.IsSecretOrRestrictedValue(batchCount)
        and not Compat.IsSecretOrRestrictedValue(totalCount)
        and Compat.IsFiniteNumber(batchCount)
      then
        local bc = math.floor(batchCount)
        local buyoutPositiveCount = 0
        local bidOnlyZeroBuyoutCount = 0
        if bc > 0 and hasFunctionAt(_G, "GetAuctionItemInfo") then
          local inspectLimit = math.min(bc, 50)
          for idx = 1, inspectLimit do
            local okRow, _, _, count, _, _, _, _, _, _, buyoutPrice = pcall(_G.GetAuctionItemInfo, "list", idx)
            if okRow and not Compat.IsSecretOrRestrictedValue(count) and not Compat.IsSecretOrRestrictedValue(buyoutPrice) then
              local bPrice = tonumber(buyoutPrice) or 0
              if bPrice > 0 then
                buyoutPositiveCount = buyoutPositiveCount + 1
              else
                bidOnlyZeroBuyoutCount = bidOnlyZeroBuyoutCount + 1
              end
            end
          end
        end
        liveAuctionWindowShape = {
          mode = "legacy_list",
          batchCount = bc,
          totalCount = Compat.IsFiniteNumber(totalCount) and math.floor(totalCount) or nil,
          buyoutPositiveSampleCount = buyoutPositiveCount,
          bidOnlyZeroBuyoutSampleCount = bidOnlyZeroBuyoutCount,
        }
      end
    end
  end

  local hasMerchantAPI = hasFunctionAt(_G, "GetMerchantNumItems") and hasFunctionAt(_G, "GetMerchantItemInfo")
  local hasMerchantItemLink = hasFunctionAt(_G, "GetMerchantItemLink")
  local hasMerchantCostInfo = hasFunctionAt(_G, "GetMerchantItemCostInfo")
  local hasCanMerchantRepair = hasFunctionAt(_G, "CanMerchantRepair")
  local liveMerchantSummary = nil
  if not inCombat and ns.State and ns.State.merchantOpen == true and hasMerchantAPI then
    local okM, mCount = pcall(_G.GetMerchantNumItems)
    if okM and not Compat.IsSecretOrRestrictedValue(mCount) and Compat.IsFiniteNumber(mCount) then
      local mc = math.max(0, math.floor(mCount))
      local unlimitedCount = 0
      local limitedStockCount = 0
      local altCurrencyCount = 0
      for idx = 1, math.min(mc, 80) do
        local okInfo, _, _, price, quantity, numAvailable, _, extendedCost = pcall(_G.GetMerchantItemInfo, idx)
        if okInfo and not Compat.IsSecretOrRestrictedValue(price) and not Compat.IsSecretOrRestrictedValue(numAvailable) then
          if tonumber(numAvailable) == -1 then
            unlimitedCount = unlimitedCount + 1
          elseif Compat.IsFiniteNumber(numAvailable) and numAvailable >= 0 then
            limitedStockCount = limitedStockCount + 1
          end
          if not Compat.IsSecretOrRestrictedValue(extendedCost) and extendedCost == true then
            altCurrencyCount = altCurrencyCount + 1
          end
          local _ = quantity
        end
      end
      liveMerchantSummary = {
        offerCount = mc,
        unlimitedOfferSampleCount = unlimitedCount,
        limitedStockSampleCount = limitedStockCount,
        extendedCostSampleCount = altCurrencyCount,
      }
    end
  end

  local cItem = _G.C_Item
  local cTip = _G.C_TooltipInfo
  local cCont = _G.C_Container
  local hasCItem = (not Compat.IsSecretOrRestrictedValue(cItem)) and type(cItem) == "table"
  local hasCTooltipInfo = (not Compat.IsSecretOrRestrictedValue(cTip))
    and type(cTip) == "table"
    and hasFunctionAt(cTip, "GetBagItem")
  local hasContainerDurability = (
    (not Compat.IsSecretOrRestrictedValue(cCont))
    and type(cCont) == "table"
    and hasFunctionAt(cCont, "GetContainerItemDurability")
  ) or hasFunctionAt(_G, "GetContainerItemDurability")

  local cTS = _G.C_TradeSkillUI
  local hasModernTS = (not Compat.IsSecretOrRestrictedValue(cTS))
    and type(cTS) == "table"
    and hasFunctionAt(cTS, "GetAllRecipeIDs")
  local hasClassicTS = hasFunctionAt(_G, "GetNumTradeSkills") and hasFunctionAt(_G, "GetTradeSkillInfo")
  local hasClassicCraft = hasFunctionAt(_G, "GetNumCrafts") and hasFunctionAt(_G, "GetCraftInfo")
  local profFamily = "unavailable"
  if hasModernTS and (hasClassicTS or hasClassicCraft) then
    profFamily = "hybrid"
  elseif hasModernTS then
    profFamily = "modern_c_tradeskillui"
  elseif hasClassicTS and hasClassicCraft then
    profFamily = "classic_tradeskill_and_craft"
  elseif hasClassicTS then
    profFamily = "classic_tradeskill_only"
  end

  local hasMailHeader = hasFunctionAt(_G, "GetInboxNumItems") and hasFunctionAt(_G, "GetInboxHeaderInfo")
  local hasMailInvoice = hasFunctionAt(_G, "GetInboxInvoiceInfo")
  local liveInboxSummary = nil
  if not inCombat and ns.State and ns.State.mailOpen == true and hasMailHeader then
    local okNum, numItems, totalItems = pcall(_G.GetInboxNumItems)
    if okNum
      and not Compat.IsSecretOrRestrictedValue(numItems)
      and Compat.IsFiniteNumber(numItems)
    then
      liveInboxSummary = {
        numItems = math.floor(numItems),
        totalItems = (not Compat.IsSecretOrRestrictedValue(totalItems) and Compat.IsFiniteNumber(totalItems))
          and math.floor(totalItems)
          or nil,
      }
    end
  end

  local hasLootSlots = hasFunctionAt(_G, "GetNumLootItems") and hasFunctionAt(_G, "GetLootSlotInfo")
  local cEnc = _G.C_EncodingUtil
  local hasNativeCBOR = (not Compat.IsSecretOrRestrictedValue(cEnc))
    and type(cEnc) == "table"
    and hasFunctionAt(cEnc, "SerializeCBOR")
    and hasFunctionAt(cEnc, "DeserializeCBOR")

  return {
    client = {
      version = version,
      build = build,
      tocVersion = tocVersion,
      clientLocale = Compat.GetClientLocale() or "unknown",
      hasSecretValueGuard = hasFunctionAt(_G, "issecretvalue"),
      hasNativeCBOR = hasNativeCBOR,
    },
    auctions = {
      detectedFamily = ahFamily,
      hasLegacyQuery = hasLegacyAH,
      hasLegacyDepositCalc = hasFunctionAt(_G, "CalculateAuctionDeposit") or hasFunctionAt(_G, "GetAuctionDeposit"),
      hasModernNamespace = hasModernAH,
      hasModernCommodityDeposit = hasModernAH and hasFunctionAt(cAH, "CalculateCommodityDeposit") or false,
      hasModernItemDeposit = hasModernAH and hasFunctionAt(cAH, "CalculateItemDeposit") or false,
      liveWindowObservation = liveAuctionWindowShape,
    },
    merchant = {
      hasMerchantAPI = hasMerchantAPI,
      hasMerchantItemLink = hasMerchantItemLink,
      hasMerchantCostInfo = hasMerchantCostInfo,
      hasCanMerchantRepair = hasCanMerchantRepair,
      liveWindowObservation = liveMerchantSummary,
    },
    itemInspection = {
      hasGetItemInfo = hasFunctionAt(_G, "GetItemInfo"),
      hasCItem = hasCItem,
      hasRequestLoadItemDataByID = hasCItem and hasFunctionAt(cItem, "RequestLoadItemDataByID") or false,
      hasCTooltipInfo = hasCTooltipInfo,
      hasContainerDurability = hasContainerDurability,
    },
    professions = {
      detectedFamily = profFamily,
      hasClassicTradeSkill = hasClassicTS,
      hasClassicCraft = hasClassicCraft,
      hasModernTradeSkillUI = hasModernTS,
    },
    mail = {
      hasInboxHeader = hasMailHeader,
      hasInboxInvoice = hasMailInvoice,
      liveWindowObservation = liveInboxSummary,
    },
    loot = {
      hasLootSlotInfo = hasLootSlots,
      hasLootSlotLink = hasFunctionAt(_G, "GetLootSlotLink"),
    },
  }
end

-- ============================================================================
-- Stage 6A.2 / 6A.3 / 6B.1 Runtime Adapters (`1.60.1.70938` Safe):
--   1. Locale-Safe Profession Snapshot (`P1.B` — numeric skillLine IDs -> spell IDs -> locale-aware fallback)
--   2. Dual-Clock Cooldown Capture (`P1.E` — monotonic GetTime() + UTC GetServerTime() in one capture)
--   3. Detailed Bag Slot Snapshot (with `bagFamily` for `P0.6` safe consolidation)
--   4. Redacted Runtime Contract Fixture Capture (`6A.2` `/fh probe` extension)
-- ============================================================================

local SKILL_LINE_ID_TO_KEY = {
  [171] = "ALCHEMY",
  [164] = "BLACKSMITHING",
  [333] = "ENCHANTING",
  [202] = "ENGINEERING",
  [182] = "HERBALISM",
  [165] = "LEATHERWORKING",
  [186] = "MINING",
  [393] = "SKINNING",
  [197] = "TAILORING",
  [129] = "FIRST_AID",
  [185] = "COOKING",
  [356] = "FISHING",
}

local ENGLISH_SKILL_NAME_TO_KEY = {
  ["alchemy"] = "ALCHEMY",
  ["blacksmithing"] = "BLACKSMITHING",
  ["enchanting"] = "ENCHANTING",
  ["engineering"] = "ENGINEERING",
  ["herbalism"] = "HERBALISM",
  ["herb gathering"] = "HERBALISM",
  ["leatherworking"] = "LEATHERWORKING",
  ["mining"] = "MINING",
  ["skinning"] = "SKINNING",
  ["tailoring"] = "TAILORING",
  ["first aid"] = "FIRST_AID",
  ["cooking"] = "COOKING",
  ["fishing"] = "FISHING",
}

local PROFESSION_KNOWN_SPELL_IDS = {
  ALCHEMY = { 2259, 3101, 3464, 11611 },
  BLACKSMITHING = { 2018, 3100, 3538, 9785 },
  ENCHANTING = { 7411, 7412, 7413, 13920 },
  ENGINEERING = { 4036, 4037, 4038, 12656 },
  HERBALISM = { 2366, 2368, 3570, 11993, 2383 },
  LEATHERWORKING = { 2108, 3104, 3811, 10662 },
  MINING = { 2575, 2576, 3564, 10248, 2580, 2656 },
  SKINNING = { 8613, 8617, 8618, 10768 },
  TAILORING = { 3908, 3909, 3910, 12180 },
  FIRST_AID = { 3273, 3274, 7924, 10846 },
  COOKING = { 2550, 3102, 3413, 18260, 818 },
  FISHING = { 7620, 7731, 7732, 18248 },
}

function Compat.GetDualClockNow()
  local serverEpoch = nil
  if ns.State and type(ns.State.overrideServerTimeEpoch) == "number" then
    serverEpoch = math.floor(ns.State.overrideServerTimeEpoch)
  elseif type(_G.GetServerTime) == "function" then
    local okS, s = pcall(_G.GetServerTime)
    if okS and not Compat.IsSecretOrRestrictedValue(s) and Compat.IsFiniteNumber(s) and s > 0 then
      serverEpoch = math.floor(s)
    end
  elseif type(_G.time) == "function" then
    local okT, t = pcall(_G.time)
    if okT and not Compat.IsSecretOrRestrictedValue(t) and Compat.IsFiniteNumber(t) and t > 0 then
      serverEpoch = math.floor(t)
    end
  end

  local monotonicSec = nil
  if ns.State and type(ns.State.overrideMonotonicTime) == "number" then
    monotonicSec = ns.State.overrideMonotonicTime
  elseif type(_G.GetTime) == "function" then
    local okM, m = pcall(_G.GetTime)
    if okM and not Compat.IsSecretOrRestrictedValue(m) and Compat.IsFiniteNumber(m) and m >= 0 then
      monotonicSec = m
    end
  end

  return {
    serverEpoch = serverEpoch,
    monotonicSec = monotonicSec,
  }
end

function Compat.IsTradeSkillViewLinked()
  if ns.State and ns.State.overrideTradeSkillLinked ~= nil then
    return ns.State.overrideTradeSkillLinked == true
  end
  if type(_G.IsTradeSkillLinked) == "function" then
    local okL, linked = pcall(_G.IsTradeSkillLinked)
    if okL and not Compat.IsSecretOrRestrictedValue(linked) and linked == true then
      return true
    end
  end
  local cTS = _G.C_TradeSkillUI
  if not Compat.IsSecretOrRestrictedValue(cTS) and type(cTS) == "table" then
    if type(cTS.IsTradeSkillLinked) == "function" then
      local okM, isL = pcall(cTS.IsTradeSkillLinked)
      if okM and isL == true then
        return true
      end
    end
    if type(cTS.IsTradeSkillGuild) == "function" then
      local okG, isG = pcall(cTS.IsTradeSkillGuild)
      if okG and isG == true then
        return true
      end
    end
  end
  return false
end

function Compat.CaptureProfessionSnapshot()
  local clocks = Compat.GetDualClockNow()
  local nowEpoch = clocks.serverEpoch or 0

  -- Never overwrite character profession state from a chat-linked / guild trade-skill inspection!
  if Compat.IsTradeSkillViewLinked() then
    return {
      snapshotStatus = "LINKED_VIEW_IGNORED",
      isLinkedView = true,
      learnedSkills = {},
      baseRanks = {},
      effectiveModifiers = {},
      maxRanks = {},
      observedAt = nowEpoch,
    }
  end

  local baseRanks = {}
  local modifiers = {}
  local maxRanks = {}

  -- Path 1: Modern/Hybrid `GetProfessions` + `GetProfessionInfo` numeric `skillLine` IDs (100% locale-invariant!)
  if type(_G.GetProfessions) == "function" and type(_G.GetProfessionInfo) == "function" then
    local okP, p1, p2, arch, fish, cook, firstAid = pcall(_G.GetProfessions)
    if okP then
      local indices = { p1, p2, arch, fish, cook, firstAid }
      local anyNumericFailed = false
      for _, idx in ipairs(indices) do
        if type(idx) == "number" and idx > 0 then
          local okInfo, _, _, rank, maxRank, _, _, skillLine, mod = pcall(_G.GetProfessionInfo, idx)
          if okInfo and type(skillLine) == "number" then
            local key = SKILL_LINE_ID_TO_KEY[math.floor(skillLine)]
            if key and Compat.IsFiniteNumber(rank) then
              baseRanks[key] = math.max(0, math.floor(rank))
              modifiers[key] = Compat.IsFiniteNumber(mod) and math.floor(mod) or 0
              maxRanks[key] = Compat.IsFiniteNumber(maxRank) and math.max(0, math.floor(maxRank)) or 300
            end
          else
            anyNumericFailed = true
          end
        end
      end
      return {
        snapshotStatus = anyNumericFailed and "PARTIAL" or "COMPLETE",
        source = "get_professions_numeric_skillline",
        isLinkedView = false,
        learnedSkills = baseRanks,
        baseRanks = baseRanks,
        effectiveModifiers = modifiers,
        maxRanks = maxRanks,
        observedAt = nowEpoch,
      }
    end
  end

  -- Path 2: Classic `GetNumSkillLines` + `GetSkillLineInfo` with locale safety + spellbook cross-check:
  if type(_G.GetNumSkillLines) == "function" and type(_G.GetSkillLineInfo) == "function" then
    local okN, numLines = pcall(_G.GetNumSkillLines)
    if not okN or not Compat.IsFiniteNumber(numLines) or numLines <= 0 then
      return {
        snapshotStatus = "PENDING",
        source = "skill_lines_empty_before_init",
        isLinkedView = false,
        learnedSkills = {},
        baseRanks = {},
        effectiveModifiers = {},
        maxRanks = {},
        observedAt = nowEpoch,
      }
    end

    local locale = Compat.GetClientLocale() or "enUS"
    local isEnglish = (locale == "enUS" or locale == "enGB")

    -- Build localized client global name map where available (`PROFESSIONS_FIRST_AID`, `PROFESSIONS_COOKING`, `PROFESSIONS_FISHING`)
    local localizedNameMap = {}
    if isEnglish then
      for k, v in pairs(ENGLISH_SKILL_NAME_TO_KEY) do
        localizedNameMap[k] = v
      end
    end
    local globalPairs = {
      { _G.PROFESSIONS_FIRST_AID, "FIRST_AID" },
      { _G.PROFESSIONS_COOKING, "COOKING" },
      { _G.PROFESSIONS_FISHING, "FISHING" },
    }
    for _, gp in ipairs(globalPairs) do
      if type(gp[1]) == "string" and gp[1] ~= "" then
        localizedNameMap[string.lower(gp[1])] = gp[2]
      end
    end

    local totalNonHeaderLines = 0
    local hadUnmappedOnNonEnglish = false

    for i = 1, math.floor(numLines) do
      local okL, skillName, isHeader, _, skillRank, numTempPoints, skillModifier, skillMaxRank = pcall(_G.GetSkillLineInfo, i)
      if okL and not isHeader and type(skillName) == "string" and skillName ~= "" then
        totalNonHeaderLines = totalNonHeaderLines + 1
        local norm = string.lower(string.gsub(skillName, "^%s*(.-)%s*$", "%1"))
        local mappedKey = localizedNameMap[norm]
        if mappedKey and Compat.IsFiniteNumber(skillRank) then
          baseRanks[mappedKey] = math.max(0, math.floor(skillRank))
          local effMod = Compat.IsFiniteNumber(skillModifier) and math.floor(skillModifier)
            or (Compat.IsFiniteNumber(numTempPoints) and math.floor(numTempPoints) or 0)
          modifiers[mappedKey] = effMod
          maxRanks[mappedKey] = Compat.IsFiniteNumber(skillMaxRank) and math.max(0, math.floor(skillMaxRank)) or 300
        elseif not isEnglish and Compat.IsFiniteNumber(skillMaxRank) and (skillMaxRank == 75 or skillMaxRank == 150 or skillMaxRank == 225 or skillMaxRank == 300) then
          hadUnmappedOnNonEnglish = true
        end
      end
    end

    -- Supplemental locale-invariant spellbook detection (`IsSpellKnown` / `IsPlayerSpell`):
    local checkSpellFn = (type(_G.IsSpellKnown) == "function" and _G.IsSpellKnown)
      or (type(_G.IsPlayerSpell) == "function" and _G.IsPlayerSpell)
      or nil
    if checkSpellFn then
      for profKey, spellList in pairs(PROFESSION_KNOWN_SPELL_IDS) do
        if baseRanks[profKey] == nil then
          for _, spID in ipairs(spellList) do
            local okSp, known = pcall(checkSpellFn, spID)
            if okSp and known == true then
              -- Known via spellbook, exact rank unknown on non-English skill line -> mark PARTIAL (rank >= 1)
              baseRanks[profKey] = 1
              modifiers[profKey] = 0
              maxRanks[profKey] = 75
              hadUnmappedOnNonEnglish = true
              break
            end
          end
        end
      end
    end

    if totalNonHeaderLines == 0 then
      return {
        snapshotStatus = "PENDING",
        source = "skill_lines_headers_collapsed_or_pending",
        isLinkedView = false,
        learnedSkills = {},
        baseRanks = {},
        effectiveModifiers = {},
        maxRanks = {},
        observedAt = nowEpoch,
      }
    end

    return {
      snapshotStatus = (not isEnglish and hadUnmappedOnNonEnglish) and "PARTIAL" or "COMPLETE",
      source = "classic_skill_lines",
      isLinkedView = false,
      learnedSkills = baseRanks,
      baseRanks = baseRanks,
      effectiveModifiers = modifiers,
      maxRanks = maxRanks,
      observedAt = nowEpoch,
    }
  end

  return {
    snapshotStatus = "PENDING",
    source = "no_profession_api_available",
    isLinkedView = false,
    learnedSkills = {},
    baseRanks = {},
    effectiveModifiers = {},
    maxRanks = {},
    observedAt = nowEpoch,
  }
end

-- Dual-clock item & recipe cooldown converter (`P1.E`):
-- Converts monotonic `(startTime, duration, enable)` or recipe `remainingSeconds` into UTC server epoch.
-- `nil` NEVER becomes ready!
function Compat.NormalizeItemCooldownToServerEpoch(startTime, duration, enable, clocks)
  clocks = type(clocks) == "table" and clocks or Compat.GetDualClockNow()
  local serverNow = clocks.serverEpoch
  local monoNow = clocks.monotonicSec

  if not Compat.IsFiniteNumber(serverNow) or serverNow <= 0 or not Compat.IsFiniteNumber(monoNow) then
    return { status = "CLOCK_UNAVAILABLE", readyAtServerEpoch = nil }
  end
  if startTime == nil or duration == nil or enable == nil then
    return { status = "UNKNOWN", readyAtServerEpoch = nil, reason = "nil_cooldown_tuple" }
  end
  if enable == 0 or enable == false then
    return { status = "PAUSED_OR_INACTIVE", readyAtServerEpoch = nil }
  end
  if not Compat.IsFiniteNumber(startTime) or not Compat.IsFiniteNumber(duration) or startTime < 0 or duration < 0 then
    return { status = "UNKNOWN", readyAtServerEpoch = nil, reason = "non_finite_cooldown_tuple" }
  end
  if startTime == 0 and duration == 0 then
    return {
      status = "READY_OBSERVED",
      remainingSeconds = 0,
      readyAtServerEpoch = serverNow,
      observedAtServerEpoch = serverNow,
    }
  end
  local rem = math.max(0, (startTime + duration) - monoNow)
  local remCeil = math.ceil(rem)
  return {
    status = (remCeil == 0) and "READY_OBSERVED" or "ON_COOLDOWN_OBSERVED",
    remainingSeconds = remCeil,
    readyAtServerEpoch = serverNow + remCeil,
    observedAtServerEpoch = serverNow,
  }
end

function Compat.NormalizeRecipeCooldownToServerEpoch(rawRemainingSeconds, rowVerified, isLinkedView, clocks, cooldownApiObserved)
  if isLinkedView == true then
    return { status = "LINKED_VIEW_IGNORED", readyAtServerEpoch = nil }
  end
  if rowVerified ~= true then
    return { status = "UNKNOWN", readyAtServerEpoch = nil, reason = "recipe_row_unverified" }
  end
  if cooldownApiObserved == false then
    return { status = "UNKNOWN", readyAtServerEpoch = nil, reason = "cooldown_api_unavailable" }
  end
  clocks = type(clocks) == "table" and clocks or Compat.GetDualClockNow()
  local serverNow = clocks.serverEpoch
  if not Compat.IsFiniteNumber(serverNow) or serverNow <= 0 then
    return { status = "CLOCK_UNAVAILABLE", readyAtServerEpoch = nil }
  end
  -- Astra P0-8: NEVER normalize `nil` cooldown returns to `0` (`READY_OBSERVED`)!
  if rawRemainingSeconds == nil then
    return { status = "UNKNOWN", readyAtServerEpoch = nil, reason = "nil_cooldown_value" }
  end
  if rawRemainingSeconds == 0 then
    return {
      status = "READY_OBSERVED",
      remainingSeconds = 0,
      readyAtServerEpoch = serverNow,
      observedAtServerEpoch = serverNow,
    }
  end
  if not Compat.IsFiniteNumber(rawRemainingSeconds) or rawRemainingSeconds < 0 then
    return { status = "UNKNOWN", readyAtServerEpoch = nil, reason = "invalid_remaining_seconds" }
  end
  local remCeil = math.ceil(rawRemainingSeconds)
  return {
    status = "ON_COOLDOWN_OBSERVED",
    remainingSeconds = remCeil,
    readyAtServerEpoch = serverNow + remCeil,
    observedAtServerEpoch = serverNow,
  }
end

-- Detailed bag slot snapshot with `bagFamily` for `P0.6` safe consolidation & `P1.C` merchant reconciliation:
function Compat.SnapshotDetailedPlayerBagSlots()
  local out = {}
  local cCont = _G.C_Container
  local getNumFreeModern = (not Compat.IsSecretOrRestrictedValue(cCont)) and type(cCont) == "table" and cCont.GetContainerNumFreeSlots or nil
  local getNumFreeLegacy = _G.GetContainerNumFreeSlots
  local getItemInfoFn = _G.GetItemInfo

  for bagID = 0, 4 do
    local numSlots = Compat.GetContainerNumSlots(bagID)
    if numSlots > 0 then
      local bagFamily = 0
      if type(getNumFreeModern) == "function" then
        local okF, _, fam = pcall(getNumFreeModern, bagID)
        if okF and Compat.IsFiniteNumber(fam) then
          bagFamily = math.max(0, math.floor(fam))
        end
      elseif type(getNumFreeLegacy) == "function" then
        local okF, _, fam = pcall(getNumFreeLegacy, bagID)
        if okF and Compat.IsFiniteNumber(fam) then
          bagFamily = math.max(0, math.floor(fam))
        end
      end

      for slotID = 1, numSlots do
        local info = Compat.GetContainerItemInfo(bagID, slotID)
        if info and info.hasItem and tonumber(info.itemID) then
          local itemID = tonumber(info.itemID)
          local locked = Compat.IsContainerItemLocked(bagID, slotID)
          local quality, maxStack, equipLoc, sellPrice, classID, subClassID, bindType = nil, nil, nil, nil, nil, nil, nil
          local metaComplete = false

          if type(getItemInfoFn) == "function" then
            local okI, _, _, q, _, _, _, _, stCount, eqLoc, _, sp, cID, scID, bType = pcall(getItemInfoFn, info.hyperlink or itemID)
            if okI and q ~= nil and sp ~= nil then
              quality = tonumber(q)
              maxStack = tonumber(stCount)
              equipLoc = type(eqLoc) == "string" and eqLoc or ""
              sellPrice = tonumber(sp)
              classID = tonumber(cID)
              subClassID = tonumber(scID)
              bindType = tonumber(bType)
              metaComplete = true
            end
          end

          local canonicalKey = nil
          if ns.Domain and ns.Domain.MarketIdentity and type(ns.Domain.MarketIdentity.ClassifyItemIdentity) == "function" then
            local okK, kRes = pcall(ns.Domain.MarketIdentity.ClassifyItemIdentity, {
              itemID = itemID,
              itemLink = info.hyperlink,
              clientClassInfo = classID and { classID = classID, equipLoc = equipLoc } or nil,
            })
            if okK and type(kRes) == "table" then
              canonicalKey = kRes.itemKey
            end
          end

          table.insert(out, {
            bagID = bagID,
            slotID = slotID,
            bagFamily = bagFamily,
            hasItem = true,
            itemID = itemID,
            itemKey = canonicalKey,
            hyperlink = info.hyperlink,
            stackCount = info.stackCount or 1,
            maxStack = maxStack or Compat.GetItemMaxStack(itemID),
            isLocked = locked,
            isBound = info.isBound,
            quality = quality,
            unitSellPrice = sellPrice,
            classID = classID,
            subClassID = subClassID,
            equipLoc = equipLoc,
            bindType = bindType,
            metadataComplete = metaComplete,
          })
        end
      end
    end
  end
  return out
end

-- Stage 6A.2 Redacted Runtime Contract Fixture Capture (`/fh probe` extension):
-- Strips all player/guild/mail-sender PII while capturing exact `1.60.1.70938` return shapes.
function Compat.CaptureRedactedContractFixture()
  local baseProbe = Compat.ProbeEconomyRuntimeCapabilities and Compat.ProbeEconomyRuntimeCapabilities() or {}
  local profSnap = Compat.CaptureProfessionSnapshot()
  local clocks = Compat.GetDualClockNow()

  local ahRedactedSample = nil
  if not Compat.IsInCombat() and ns.State and ns.State.ahOpen == true and type(_G.GetNumAuctionItems) == "function" and type(_G.GetAuctionItemInfo) == "function" then
    local okCnt, batchCount, totalCount = pcall(_G.GetNumAuctionItems, "list")
    if okCnt and Compat.IsFiniteNumber(batchCount) then
      local bc = math.max(0, math.floor(batchCount))
      local ownerPresentCount = 0
      local ownerNilCount = 0
      local sampleRows = {}
      for idx = 1, math.min(bc, 5) do
        local okRow, _, _, count, quality, _, _, _, minBid, _, buyoutPrice, bidAmount, _, _, owner, _, saleStatus, itemId =
          pcall(_G.GetAuctionItemInfo, "list", idx)
        if okRow then
          local resolvedID = tonumber(itemId)
          if (not resolvedID or resolvedID <= 0) and type(_G.GetAuctionItemLink) == "function" then
            local okLink, link = pcall(_G.GetAuctionItemLink, "list", idx)
            if okLink and type(link) == "string" then
              resolvedID = Compat.ExtractItemID(link)
            end
          end
          local hasOwner = (type(owner) == "string" and owner ~= "")
          if hasOwner then
            ownerPresentCount = ownerPresentCount + 1
          else
            ownerNilCount = ownerNilCount + 1
          end
          table.insert(sampleRows, {
            index = idx,
            itemID = resolvedID,
            count = tonumber(count),
            quality = tonumber(quality),
            minBid = tonumber(minBid),
            buyoutPrice = tonumber(buyoutPrice),
            bidAmount = tonumber(bidAmount),
            ownerPopulated = hasOwner, -- PII redacted to boolean!
            saleStatus = tonumber(saleStatus),
          })
        end
      end
      ahRedactedSample = {
        batchCount = bc,
        totalCount = Compat.IsFiniteNumber(totalCount) and math.floor(totalCount) or nil,
        ownerPresentSampleCount = ownerPresentCount,
        ownerNilSampleCount = ownerNilCount,
        rows = sampleRows,
      }
    end
  end

  local mailRedactedInvoices = nil
  if not Compat.IsInCombat() and ns.State and ns.State.mailOpen == true and type(_G.GetInboxNumItems) == "function" and type(_G.GetInboxInvoiceInfo) == "function" then
    local okM, numItems = pcall(_G.GetInboxNumItems)
    if okM and Compat.IsFiniteNumber(numItems) then
      mailRedactedInvoices = {}
      for idx = 1, math.min(math.floor(numItems), 10) do
        local okInv, invType, _, playerName, bid, buyout, deposit, consignment = pcall(_G.GetInboxInvoiceInfo, idx)
        if okInv and type(invType) == "string" and invType ~= "" then
          table.insert(mailRedactedInvoices, {
            mailIndex = idx,
            invoiceType = invType,
            counterpartyPresent = (type(playerName) == "string" and playerName ~= ""), -- PII redacted!
            bid = tonumber(bid),
            buyout = tonumber(buyout),
            deposit = tonumber(deposit),
            consignment = tonumber(consignment),
          })
        end
      end
    end
  end

    return {
      schema = "foreverhub-redacted-runtime-fixture-v1",
      piiRedacted = true,
      capturedAtServerEpoch = clocks.serverEpoch,
      monotonicClockAvailable = (clocks.monotonicSec ~= nil),
      capabilities = baseProbe,
      professionSnapshot = {
        snapshotStatus = profSnap.snapshotStatus,
        status = profSnap.snapshotStatus,
        source = profSnap.source,
        isLinkedView = profSnap.isLinkedView,
        learnedCount = 0,
      },
      auctionPage = ahRedactedSample and {
        inspectedCount = #(ahRedactedSample.rows or {}),
        totalCount = ahRedactedSample.totalCount,
      } or nil,
      mailInbox = mailRedactedInvoices and {
        numItems = #mailRedactedInvoices,
      } or nil,
      redactedAuctionSample = ahRedactedSample,
      redactedMailInvoices = mailRedactedInvoices,
      ahPostProbe = Compat.CaptureRedactedAhPostProbe(),
      mailPostageAndCodProbe = Compat.CaptureRedactedMailPostageAndCodProbe(),
    }
  end

function Compat.ParseCreatureGUIDSafe(rawGuid)
  if Compat.IsSecretOrRestrictedValue(rawGuid) or type(rawGuid) ~= "string" or rawGuid == "" then
    return { status = "UNKNOWN_NPC", npcType = nil, npcID = nil }
  end
  local unitType, npcIDStr = string.match(rawGuid, "^(Creature)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-[%x]+$")
  if not unitType then
    unitType, npcIDStr = string.match(rawGuid, "^(Vehicle)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-[%x]+$")
  end
  local npcID = tonumber(npcIDStr)
  if unitType and Compat.IsFiniteNumber(npcID) and npcID >= 1 and math.floor(npcID) == npcID then
    return {
      status = "VERIFIED_NPC_GUID",
      npcType = string.lower(unitType),
      npcID = npcID,
    }
  end
  return { status = "UNKNOWN_NPC", npcType = nil, npcID = nil }
end

-- Stage 7A.1 Redacted AH Post & Deposit Runtime Probe (`GetAuctionDeposit` + `Auctionator` Selling controls):
function Compat.CaptureRedactedAhPostProbe()
  local hasGetAuctionDeposit = (type(_G.GetAuctionDeposit) == "function")
  local hasCalculateAuctionDeposit = (type(_G.CalculateAuctionDeposit) == "function")
  local hasGetAuctionSellItemInfo = (type(_G.GetAuctionSellItemInfo) == "function")
  local atrSell = _G.AuctionatorSellingFrame
  local hasAtrSellingFrame = (not Compat.IsSecretOrRestrictedValue(atrSell)) and (atrSell ~= nil)
  local hasAtrStackPrice = false
  if hasAtrSellingFrame and type(atrSell) == "table" and type(atrSell.SaleItemFrame) == "table" then
    local sif = atrSell.SaleItemFrame
    hasAtrStackPrice = (type(sif.StackPrice) == "table" and type(sif.StackPrice.GetAmount) == "function")
      or (type(sif.Price) == "table" and type(sif.Price.GetAmount) == "function")
  end

  local npcGuidInfo = { status = "UNKNOWN_NPC", npcType = nil, npcID = nil }
  if not Compat.IsInCombat() and type(_G.UnitGUID) == "function" then
    local okG, rawG = pcall(_G.UnitGUID, "npc")
    if (not okG or not rawG) then
      okG, rawG = pcall(_G.UnitGUID, "target")
    end
    if okG and rawG then
      npcGuidInfo = Compat.ParseCreatureGUIDSafe(rawG)
    end
  end

  local slottedSellItem = nil
  local durationQuotes = nil
  if not Compat.IsInCombat() and ns.State and ns.State.ahOpen == true and hasGetAuctionSellItemInfo then
    local okS, sName, _, sCount, sQuality, _, sVendorPrice, sPricePerUnit, sStackCount, sTotalCount, sItemID =
      pcall(_G.GetAuctionSellItemInfo)
    if okS and sName ~= nil then
      slottedSellItem = {
        slotted = true,
        count = Compat.IsFiniteNumber(sCount) and math.floor(sCount) or nil,
        quality = Compat.IsFiniteNumber(sQuality) and math.floor(sQuality) or nil,
        vendorPriceCopper = Compat.IsFiniteNumber(sVendorPrice) and math.floor(sVendorPrice) or nil,
        pricePerUnitCopper = Compat.IsFiniteNumber(sPricePerUnit) and math.floor(sPricePerUnit) or nil,
        stackCount = Compat.IsFiniteNumber(sStackCount) and math.floor(sStackCount) or nil,
        totalCount = Compat.IsFiniteNumber(sTotalCount) and math.floor(sTotalCount) or nil,
        itemID = Compat.IsFiniteNumber(sItemID) and math.floor(sItemID) or nil,
      }
      if hasGetAuctionDeposit then
        durationQuotes = {}
        local probeStack = math.max(1, tonumber(slottedSellItem.count) or 1)
        for durIdx = 1, 3 do
          local okD1, qSingle = pcall(_G.GetAuctionDeposit, durIdx, 100, 200, probeStack, 1)
          local okD2, qBatch2 = pcall(_G.GetAuctionDeposit, durIdx, 100, 200, probeStack, 2)
          durationQuotes[durIdx] = {
            durationIndex = durIdx,
            foreverDisplayHours = (durIdx == 1 and 2) or (durIdx == 2 and 8) or 24,
            singleStackCallOk = okD1,
            singleStackDepositCopper = (okD1 and Compat.IsFiniteNumber(qSingle)) and math.floor(qSingle) or nil,
            twoStackCallOk = okD2,
            twoStackDepositCopper = (okD2 and Compat.IsFiniteNumber(qBatch2)) and math.floor(qBatch2) or nil,
          }
        end
      end
    else
      slottedSellItem = { slotted = false }
    end
  end

  return {
    piiRedacted = true,
    hasGetAuctionDeposit = hasGetAuctionDeposit,
    hasCalculateAuctionDeposit = hasCalculateAuctionDeposit,
    hasGetAuctionSellItemInfo = hasGetAuctionSellItemInfo,
    hasAuctionatorSellingFrame = hasAtrSellingFrame,
    hasAuctionatorStackPriceReader = hasAtrStackPrice,
    auctioneerNpc = npcGuidInfo,
    slottedSellItem = slottedSellItem,
    durationDepositProbe = durationQuotes,
  }
end

-- Stage 7A.1 Redacted Mail Postage & COD Runtime Probe:
function Compat.CaptureRedactedMailPostageAndCodProbe()
  local hasGetSendMailPrice = (type(_G.GetSendMailPrice) == "function")
  local hasGetInboxHeaderInfo = (type(_G.GetInboxHeaderInfo) == "function")
  local hasGetInboxItem = (type(_G.GetInboxItem) == "function")
  local sendMailPriceCopper = nil
  if not Compat.IsInCombat() and ns.State and ns.State.mailOpen == true and hasGetSendMailPrice then
    local okP, pVal = pcall(_G.GetSendMailPrice)
    if okP and Compat.IsFiniteNumber(pVal) and pVal >= 0 then
      sendMailPriceCopper = math.floor(pVal)
    end
  end

  local inboxSummary = nil
  if not Compat.IsInCombat() and ns.State and ns.State.mailOpen == true and type(_G.GetInboxNumItems) == "function" and hasGetInboxHeaderInfo then
    local okN, numItems = pcall(_G.GetInboxNumItems)
    if okN and Compat.IsFiniteNumber(numItems) then
      local n = math.min(100, math.max(0, math.floor(numItems)))
      local codCount = 0
      local attachmentRowCount = 0
      local incompleteCount = 0
      for idx = 1, n do
        local okH, _, _, sender, subject, money, codAmount, _, hasItem = pcall(_G.GetInboxHeaderInfo, idx)
        if not okH or (sender == nil and subject == nil) then
          incompleteCount = incompleteCount + 1
        else
          if Compat.IsFiniteNumber(codAmount) and codAmount > 0 then
            codCount = codCount + 1
          end
          if (Compat.IsFiniteNumber(hasItem) and hasItem > 0) or hasItem == true then
            attachmentRowCount = attachmentRowCount + 1
          end
        end
      end
      inboxSummary = {
        inspectedCount = n,
        codRowCount = codCount,
        attachmentRowCount = attachmentRowCount,
        incompleteHeaderCount = incompleteCount,
      }
    end
  end

  return {
    piiRedacted = true,
    hasGetSendMailPrice = hasGetSendMailPrice,
    hasGetInboxHeaderInfo = hasGetInboxHeaderInfo,
    hasGetInboxItem = hasGetInboxItem,
    sendMailPriceCopper = sendMailPriceCopper,
    inboxSummary = inboxSummary,
  }
end

-- ============================================================================
-- KI-ST-001 Strict Secret-Safe Classifier & Instance Identity Probe (ST-01, ST-04)
-- Classifies each input as `"readable" | "missing" | "restricted" | "errored" | "unknown"`
-- BEFORE comparing, formatting, indexing, arithmetic, or storing it.
-- - Unavailable `_G.issecretvalue` on a `secretCapable` path returns `"unknown"`.
-- - Throwing `_G.issecretvalue` returns `"errored"`.
-- - Preserves legitimate `false` and `0` ONLY after validation.
-- - Never retains raw secret/hostile payloads on non-readable results.
-- ============================================================================

function Compat.ClassifySecretSafeValue(rawVal, opts)
  opts = type(opts) == "table" and opts or nil
  local secretCapable = (opts == nil) or (opts.secretCapable ~= false)

  local okLookup, detFn = pcall(function()
    return _G.issecretvalue
  end)
  if not okLookup then
    return { status = "errored", reason = "secret_detector_lookup_threw", value = nil }
  end

  local hasDetector = (type(detFn) == "function")
  if secretCapable and not hasDetector then
    return { status = "unknown", reason = "secret_detector_unavailable", value = nil }
  end

  local rawEq = _G.rawequal
  if hasDetector then
    local okDet, isSec = pcall(detFn, rawVal)
    if not okDet then
      return { status = "errored", reason = "secret_detector_threw", value = nil }
    end
    if rawEq(isSec, true) then
      return { status = "restricted", reason = "secret_value", value = nil }
    end
    if not rawEq(isSec, false) then
      return { status = "unknown", reason = "secret_detector_non_boolean", value = nil }
    end
  end

  if rawEq(rawVal, nil) then
    return { status = "missing", reason = "nil_value", value = nil }
  end

  local valType = type(rawVal)
  local expectedType = opts and opts.expectedType or nil
  if expectedType ~= nil and valType ~= expectedType then
    return { status = "errored", reason = "unexpected_type_" .. tostring(valType), value = nil }
  end

  if valType == "boolean" then
    if rawEq(rawVal, true) then
      return { status = "readable", value = true, valueType = "boolean" }
    elseif rawEq(rawVal, false) then
      return { status = "readable", value = false, valueType = "boolean" }
    end
    return { status = "errored", reason = "invalid_boolean", value = nil }
  elseif valType == "number" then
    local okNum, cleanNum = pcall(function()
      if rawVal ~= rawVal or rawVal == math.huge or rawVal == -math.huge then
        error("non_finite")
      end
      return rawVal + 0
    end)
    if not okNum or type(cleanNum) ~= "number" then
      return { status = "errored", reason = "non_finite_or_hostile_number", value = nil }
    end
    return { status = "readable", value = cleanNum, valueType = "number" }
  elseif valType == "string" then
    local okStr, isEmpty = pcall(function()
      return rawVal == ""
    end)
    if not okStr or type(isEmpty) ~= "boolean" then
      return { status = "errored", reason = "hostile_string", value = nil }
    end
    if isEmpty and not (opts and opts.allowEmptyString == true) then
      return { status = "missing", reason = "empty_string", value = nil }
    end
    return { status = "readable", value = rawVal, valueType = "string" }
  elseif valType == "table" then
    return { status = "readable", value = rawVal, valueType = "table" }
  end

  return { status = "errored", reason = "unsupported_type_" .. tostring(valType), value = nil }
end

function Compat.CallAndClassifySecretSafe(getterFn, opts)
  if type(getterFn) ~= "function" then
    return { status = "missing", reason = "missing_api", value = nil }
  end
  local okCall, rawVal = pcall(getterFn)
  if not okCall then
    return { status = "errored", reason = "api_call_threw", value = nil }
  end
  return Compat.ClassifySecretSafeValue(rawVal, opts)
end

function Compat.ClassifySecretSafeField(tbl, fieldKey, opts)
  local tblCheck = Compat.ClassifySecretSafeValue(tbl, {
    secretCapable = (type(opts) == "table") and (opts.secretCapable ~= false) or true,
    expectedType = "table",
  })
  if tblCheck.status ~= "readable" then
    return { status = tblCheck.status, reason = tblCheck.reason or "parent_table_unreadable", value = nil }
  end
  local okField, rawField = pcall(function()
    return tbl[fieldKey]
  end)
  if not okField then
    return { status = "errored", reason = "field_index_threw", value = nil }
  end
  return Compat.ClassifySecretSafeValue(rawField, opts)
end

-- Probes both return #8 (`instanceID`) and return #9 (`instanceGroupSize`) of `GetInstanceInfo()`
-- alongside `IsInInstance()` and validates exact Sunken Temple identity (`instanceType == "party"` and `instanceID == 109`).
-- Localized instance names NEVER arm Sunken Temple without verified numeric `instanceID == 109` (ST-01).
function Compat.ProbeSunkenTempleInstanceIdentity(explicitOverride)
  local stData = ns.SunkenTempleData
  local targetInstanceID = (stData and tonumber(stData.SUNKEN_TEMPLE_INSTANCE_ID)) or 109
  local nameHints = (stData and stData.LOCALIZED_NAME_HINTS) or {
    ["the temple of atal'hakkar"] = true,
    ["temple of atal'hakkar"] = true,
    ["sunken temple"] = true,
  }

  local bInRaw, isInTypeRaw = nil, nil
  local hasIsInAPI = false
  local isInCallOk = false
  if type(explicitOverride) == "table" and explicitOverride.useExplicit == true then
    hasIsInAPI = true
    isInCallOk = true
    bInRaw = explicitOverride.inInstance
    isInTypeRaw = explicitOverride.isInInstanceType
  elseif type(_G.IsInInstance) == "function" then
    hasIsInAPI = true
    local okI, r1, r2 = pcall(_G.IsInInstance)
    isInCallOk = okI
    if okI then
      bInRaw, isInTypeRaw = r1, r2
    end
  end

  local hasGetInfoAPI = false
  local getInfoCallOk = false
  local gName, gType, gMaxPlayers, gReturn8, gReturn9 = nil, nil, nil, nil, nil
  if type(explicitOverride) == "table" and explicitOverride.useExplicit == true then
    hasGetInfoAPI = true
    getInfoCallOk = true
    gName = explicitOverride.name
    gType = explicitOverride.infoInstanceType
    gMaxPlayers = explicitOverride.maxPlayers
    gReturn8 = explicitOverride.return8_instanceID
    gReturn9 = explicitOverride.return9_instanceGroupSize
  elseif type(_G.GetInstanceInfo) == "function" then
    hasGetInfoAPI = true
    local okG, r1, r2, _r3, _r4, r5, _r6, _r7, r8, r9 = pcall(_G.GetInstanceInfo)
    getInfoCallOk = okG
    if okG then
      gName, gType, gMaxPlayers, gReturn8, gReturn9 = r1, r2, r5, r8, r9
    end
  end

  local nonSecretMetaOptsBool = { secretCapable = false }
  local nonSecretMetaOptsStr = { secretCapable = false, expectedType = "string" }
  local nonSecretMetaOptsNum = { secretCapable = false, expectedType = "number" }

  local inInstStatus = "missing"
  local inInstBool = nil
  if not hasIsInAPI then
    inInstStatus = "missing"
  elseif not isInCallOk then
    inInstStatus = "errored"
  else
    local c = Compat.ClassifySecretSafeValue(bInRaw, nonSecretMetaOptsBool)
    inInstStatus = c.status
    if c.status == "readable" then
      if c.valueType == "boolean" then
        inInstBool = c.value
      elseif c.valueType == "number" then
        inInstBool = (c.value == 1)
      else
        inInstStatus = "errored"
      end
    end
  end

  local isInTypeRes = (not hasIsInAPI and { status = "missing" })
    or (not isInCallOk and { status = "errored" })
    or Compat.ClassifySecretSafeValue(isInTypeRaw, nonSecretMetaOptsStr)

  local nameRes = (not hasGetInfoAPI and { status = "missing" })
    or (not getInfoCallOk and { status = "errored" })
    or Compat.ClassifySecretSafeValue(gName, nonSecretMetaOptsStr)

  local infoTypeRes = (not hasGetInfoAPI and { status = "missing" })
    or (not getInfoCallOk and { status = "errored" })
    or Compat.ClassifySecretSafeValue(gType, nonSecretMetaOptsStr)

  local maxPlayersRes = (not hasGetInfoAPI and { status = "missing" })
    or (not getInfoCallOk and { status = "errored" })
    or Compat.ClassifySecretSafeValue(gMaxPlayers, nonSecretMetaOptsNum)

  local return8Res = (not hasGetInfoAPI and { status = "missing" })
    or (not getInfoCallOk and { status = "errored" })
    or Compat.ClassifySecretSafeValue(gReturn8, nonSecretMetaOptsNum)

  local return9Res = (not hasGetInfoAPI and { status = "missing" })
    or (not getInfoCallOk and { status = "errored" })
    or Compat.ClassifySecretSafeValue(gReturn9, nonSecretMetaOptsNum)

  local localizedNameHintMatched = false
  if nameRes.status == "readable" and type(nameRes.value) == "string" then
    local lowName = string.lower(nameRes.value)
    if nameHints[lowName] == true then
      localizedNameHintMatched = true
    end
  end

  -- Determine instance presence & type strictly fail-closed:
  if inInstStatus ~= "readable" then
    return {
      verifiedSunkenTemple = false,
      classification = "ambiguous_instance_state",
      inInstanceStatus = inInstStatus,
      inInstance = nil,
      isInTypeStatus = isInTypeRes.status,
      infoTypeStatus = infoTypeRes.status,
      nameStatus = nameRes.status,
      return8Status = return8Res.status,
      return8Value = return8Res.status == "readable" and return8Res.value or nil,
      return9Status = return9Res.status,
      return9Value = return9Res.status == "readable" and return9Res.value or nil,
      maxPlayersStatus = maxPlayersRes.status,
      localizedNameHintMatched = localizedNameHintMatched,
    }
  end

  if inInstBool == false then
    return {
      verifiedSunkenTemple = false,
      classification = "outside_instance",
      inInstanceStatus = "readable",
      inInstance = false,
      isInTypeStatus = isInTypeRes.status,
      infoTypeStatus = infoTypeRes.status,
      nameStatus = nameRes.status,
      return8Status = return8Res.status,
      return8Value = return8Res.status == "readable" and return8Res.value or nil,
      return9Status = return9Res.status,
      return9Value = return9Res.status == "readable" and return9Res.value or nil,
      maxPlayersStatus = maxPlayersRes.status,
      localizedNameHintMatched = localizedNameHintMatched,
    }
  end

  local tA = (isInTypeRes.status == "readable") and string.lower(isInTypeRes.value) or nil
  local tB = (infoTypeRes.status == "readable") and string.lower(infoTypeRes.value) or nil
  if tA ~= nil and tB ~= nil and tA ~= tB then
    return {
      verifiedSunkenTemple = false,
      classification = "instance_type_conflict",
      inInstanceStatus = "readable",
      inInstance = true,
      instanceType = nil,
      isInTypeStatus = isInTypeRes.status,
      infoTypeStatus = infoTypeRes.status,
      nameStatus = nameRes.status,
      return8Status = return8Res.status,
      return8Value = return8Res.status == "readable" and return8Res.value or nil,
      return9Status = return9Res.status,
      return9Value = return9Res.status == "readable" and return9Res.value or nil,
      maxPlayersStatus = maxPlayersRes.status,
      localizedNameHintMatched = localizedNameHintMatched,
    }
  end

  local effType = tB or tA
  if effType == nil then
    return {
      verifiedSunkenTemple = false,
      classification = "ambiguous_instance_type",
      inInstanceStatus = "readable",
      inInstance = true,
      instanceType = nil,
      isInTypeStatus = isInTypeRes.status,
      infoTypeStatus = infoTypeRes.status,
      nameStatus = nameRes.status,
      return8Status = return8Res.status,
      return8Value = return8Res.status == "readable" and return8Res.value or nil,
      return9Status = return9Res.status,
      return9Value = return9Res.status == "readable" and return9Res.value or nil,
      maxPlayersStatus = maxPlayersRes.status,
      localizedNameHintMatched = localizedNameHintMatched,
    }
  end

  if effType ~= "party" then
    return {
      verifiedSunkenTemple = false,
      classification = "instance_type_mismatch",
      inInstanceStatus = "readable",
      inInstance = true,
      instanceType = effType,
      isInTypeStatus = isInTypeRes.status,
      infoTypeStatus = infoTypeRes.status,
      nameStatus = nameRes.status,
      return8Status = return8Res.status,
      return8Value = return8Res.status == "readable" and return8Res.value or nil,
      return9Status = return9Res.status,
      return9Value = return9Res.status == "readable" and return9Res.value or nil,
      maxPlayersStatus = maxPlayersRes.status,
      localizedNameHintMatched = localizedNameHintMatched,
    }
  end

  -- Require return #8 (`instanceID`) to be a readable positive integer (never trust return #9 or name alone!).
  if return8Res.status ~= "readable"
    or type(return8Res.value) ~= "number"
    or math.floor(return8Res.value) ~= return8Res.value
    or return8Res.value <= 0
  then
    return {
      verifiedSunkenTemple = false,
      classification = "ambiguous_unresolved_identity",
      inInstanceStatus = "readable",
      inInstance = true,
      instanceType = effType,
      isInTypeStatus = isInTypeRes.status,
      infoTypeStatus = infoTypeRes.status,
      nameStatus = nameRes.status,
      return8Status = return8Res.status,
      return8Value = nil,
      return9Status = return9Res.status,
      return9Value = return9Res.status == "readable" and return9Res.value or nil,
      maxPlayersStatus = maxPlayersRes.status,
      localizedNameHintMatched = localizedNameHintMatched,
    }
  end

  local instID = math.floor(return8Res.value)
  if instID ~= targetInstanceID then
    return {
      verifiedSunkenTemple = false,
      classification = "other_instance",
      inInstanceStatus = "readable",
      inInstance = true,
      instanceType = effType,
      instanceID = instID,
      isInTypeStatus = isInTypeRes.status,
      infoTypeStatus = infoTypeRes.status,
      nameStatus = nameRes.status,
      return8Status = "readable",
      return8Value = instID,
      return9Status = return9Res.status,
      return9Value = return9Res.status == "readable" and return9Res.value or nil,
      maxPlayersStatus = maxPlayersRes.status,
      localizedNameHintMatched = localizedNameHintMatched,
    }
  end

  return {
    verifiedSunkenTemple = true,
    classification = "verified_sunken_temple",
    inInstanceStatus = "readable",
    inInstance = true,
    instanceType = effType,
    instanceID = instID,
    instanceName = (nameRes.status == "readable") and nameRes.value or nil,
    isInTypeStatus = isInTypeRes.status,
    infoTypeStatus = infoTypeRes.status,
    nameStatus = nameRes.status,
    return8Status = "readable",
    return8Value = instID,
    return9Status = return9Res.status,
    return9Value = return9Res.status == "readable" and return9Res.value or nil,
    maxPlayersStatus = maxPlayersRes.status,
    localizedNameHintMatched = localizedNameHintMatched,
  }
end

-- ============================================================================
-- Interface 16001 Restricted CallbackEvent Registration Guard
-- In WoW: Forever (12.0-derived runtime), calling `Frame:RegisterEvent` on a
-- `HasRestrictions = true, CallbackEvent = true` event (e.g. `COMBAT_LOG_EVENT_UNFILTERED`)
-- fires C++ `ADDON_ACTION_FORBIDDEN` EVEN INSIDE `pcall(...)` and taints
-- `Enum.ForbiddenAspect.EventRegistrations` on the frame!
-- Always pre-screen via denylist + `C_EventUtils` BEFORE calling `RegisterEvent`.
-- ============================================================================

Compat.FORBIDDEN_CALLBACK_EVENTS = {
  ["COMBAT_LOG_EVENT_UNFILTERED"] = true,
  ["COMBAT_LOG_EVENT"] = true,
  ["ENCOUNTER_STATE_CHANGED"] = true,
}

local function isFrameObject(f)
  local t = type(f)
  return t == "table" or t == "userdata"
end

function Compat.IsFrameEventRegistrable(eventName)
  if type(eventName) ~= "string" or eventName == "" then
    return false, "invalid_event_name"
  end
  if Compat.FORBIDDEN_CALLBACK_EVENTS[eventName] == true then
    return false, "restricted_callback_event"
  end
  if type(_G.C_EventUtils) == "table" then
    if type(_G.C_EventUtils.IsCallbackEvent) == "function" then
      local okCb, isCb = pcall(_G.C_EventUtils.IsCallbackEvent, eventName)
      if okCb and isCb == true then
        return false, "callback_event_restricted"
      end
    end
    if type(_G.C_EventUtils.IsEventValid) == "function" then
      local okValid, isValid = pcall(_G.C_EventUtils.IsEventValid, eventName)
      if okValid and isValid == false then
        return false, "invalid_event_for_client"
      end
    end
  end
  return true, "ok"
end

function Compat.SafeRegisterFrameEvent(frame, eventName)
  if not isFrameObject(frame) then
    return false, "missing_event_frame"
  end
  local canReg, reason = Compat.IsFrameEventRegistrable(eventName)
  if not canReg then
    return false, reason
  end
  local okLookup, regFn = pcall(function()
    return frame.RegisterEvent
  end)
  if not okLookup or type(regFn) ~= "function" then
    return false, "missing_register_method"
  end
  local okReg, resReg = pcall(regFn, frame, eventName)
  if not okReg or resReg == false then
    return false, "registration_rejected"
  end
  return true, "registered"
end

function Compat.SafeRegisterFrameUnitEvent(frame, eventName, unitToken)
  if not isFrameObject(frame) then
    return false, "missing_event_frame"
  end
  local canReg, reason = Compat.IsFrameEventRegistrable(eventName)
  if not canReg then
    return false, reason
  end
  local okLookupU, unitRegFn = pcall(function()
    return frame.RegisterUnitEvent
  end)
  if okLookupU and type(unitRegFn) == "function" then
    local okRU, resRU = pcall(unitRegFn, frame, eventName, unitToken)
    if okRU and resRU ~= false then
      return true, "registered_unit_" .. tostring(unitToken)
    end
    return false, "registration_rejected"
  end
  local okReg, regReason = Compat.SafeRegisterFrameEvent(frame, eventName)
  if okReg then
    return true, "registered_global"
  end
  return false, regReason
end
