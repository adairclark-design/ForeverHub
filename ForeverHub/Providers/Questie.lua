local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.Providers = ns.Providers or {}

local QuestieProvider = {}
ns.Providers.Questie = QuestieProvider

local function isAddonLoadedCompat(name)
  if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
    local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, name)
    if ok then
      return loaded == true
    end
  end
  if type(IsAddOnLoaded) == "function" then
    local ok, loaded = pcall(IsAddOnLoaded, name)
    if ok then
      return loaded == true or loaded == 1
    end
  end
  return false
end

local function getAddonVersionCompat(name)
  if C_AddOns and type(C_AddOns.GetAddOnMetadata) == "function" then
    local ok, ver = pcall(C_AddOns.GetAddOnMetadata, name, "Version")
    if ok and type(ver) == "string" and ver ~= "" then
      return ver
    end
  end
  if type(GetAddOnMetadata) == "function" then
    local ok, ver = pcall(GetAddOnMetadata, name, "Version")
    if ok and type(ver) == "string" and ver ~= "" then
      return ver
    end
  end
  return "unknown"
end

-- Versioned readiness inspection (Astra P1-F).
-- Importing QuestieLoader:ImportModule("QuestieDB") alone does not guarantee consumer caches are ready.
function QuestieProvider.GetStatus()
  if ns.State and type(ns.State.overrideQuestieProviderStatus) == "table" then
    return ns.State.overrideQuestieProviderStatus
  end

  local questieLoaded = isAddonLoadedCompat("Questie")
  local questieDBLoaded = isAddonLoadedCompat("QuestieDB")
  local questieVersion = questieLoaded and getAddonVersionCompat("Questie") or nil
  local questieDBVersion = questieDBLoaded and getAddonVersionCompat("QuestieDB") or nil

  local loader = _G.QuestieLoader
  if type(loader) ~= "table" or type(loader.ImportModule) ~= "function" then
    return {
      questieLoaded = questieLoaded,
      questieDBLoaded = questieDBLoaded,
      questieVersion = questieVersion,
      questieDBVersion = questieDBVersion,
      ready = false,
      reason = questieLoaded and "questie_loader_unavailable" or "questie_not_loaded",
    }
  end

  local okMod, qdb = pcall(loader.ImportModule, loader, "QuestieDB")
  if not okMod or type(qdb) ~= "table" then
    return {
      questieLoaded = questieLoaded,
      questieDBLoaded = questieDBLoaded,
      questieVersion = questieVersion,
      questieDBVersion = questieDBVersion,
      ready = false,
      reason = "questiedb_module_unavailable",
    }
  end

  local hasQueryFns = type(qdb.QueryQuestSingle) == "function" and type(qdb.QueryNPCSingle) == "function"
  local hasKeyTables = type(qdb.questKeys) == "table" and type(qdb.npcKeys) == "table"
  -- Questie populates QuestPointers / NPCPointers after async initialization completes
  local pointersInitialized = (type(qdb.QuestPointers) == "table" or type(qdb._npcAdapterQueryOrder) == "table")

  return {
    questieLoaded = questieLoaded,
    questieDBLoaded = questieDBLoaded,
    questieVersion = questieVersion,
    questieDBVersion = questieDBVersion,
    ready = (hasQueryFns and hasKeyTables and pointersInitialized) == true,
    reason = (hasQueryFns and hasKeyTables and pointersInitialized) and "ready" or "initializing_or_partial",
    _module = qdb,
  }
end

-- Diagnostic-only manifest reconciliation when an explicit route table is passed.
-- Queries ONLY compiled manifest IDs (bounded, non-enumerating) and NEVER mutates compiled route data!
function QuestieProvider.AuditManifestAgainstLiveQuestie(route)
  local st = QuestieProvider.GetStatus()
  if not st.ready or not st._module or type(route) ~= "table" then
    return {
      available = false,
      status = st,
      npcMatched = 0,
      npcTotal = 0,
      questPresent = 0,
      questTotal = 0,
      mismatches = {},
    }
  end

  local qdb = st._module
  local mismatches = {}
  local npcTotal, npcMatched = 0, 0
  for npcID, npcMeta in pairs(route.npcsByID or {}) do
    npcTotal = npcTotal + 1
    local okName, liveName = pcall(qdb.QueryNPCSingle, npcID, "name")
    if okName and type(liveName) == "string" and liveName ~= "" then
      npcMatched = npcMatched + 1
      if npcMeta.name and liveName ~= npcMeta.name then
        table.insert(mismatches, string.format("NPC %d name drift: route='%s' vs live='%s'", npcID, tostring(npcMeta.name), liveName))
      end
    else
      table.insert(mismatches, string.format("NPC %d (%s) missing in live QuestieDB", npcID, tostring(npcMeta.name or "?")))
    end
  end

  local questTotal, questPresent = 0, 0
  for questID, qMeta in pairs(route.questsByID or {}) do
    questTotal = questTotal + 1
    local okQ, liveQName = pcall(qdb.QueryQuestSingle, questID, "name")
    if okQ and type(liveQName) == "string" and liveQName ~= "" then
      questPresent = questPresent + 1
    end
  end

  return {
    available = true,
    status = st,
    npcMatched = npcMatched,
    npcTotal = npcTotal,
    questPresent = questPresent,
    questTotal = questTotal,
    mismatches = mismatches,
  }
end
