local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.UI = ns.UI or {}

local Widgets = ns.UI.Widgets

local TradeSkillAdvisor = {
  frame = nil,
  active = false,
  pendingCombatShow = false,
  pendingCombatHide = false,
  lastEvaluation = nil,
}
ns.UI.TradeSkillAdvisor = TradeSkillAdvisor

local PANEL_WIDTH = 316
local PANEL_PADDING = 12
local MAX_SCAN_ROWS = 300
local MAX_REAGENTS_PER_RECIPE = 16

local KNOWN_COOLDOWN_BY_SPELL = {
  [17187] = "alchemy_transmute_arcanite",
  [18560] = "tailoring_mooncloth",
  [19566] = "lw_salt_shaker",
}

local ENGLISH_SKILL_HEADER_TO_ID = {
  ["alchemy"] = 171,
  ["blacksmithing"] = 164,
  ["cooking"] = 185,
  ["enchanting"] = 333,
  ["engineering"] = 202,
  ["first aid"] = 129,
  ["leatherworking"] = 165,
  ["mining"] = 186,
  ["smelting"] = 186,
  ["tailoring"] = 197,
}

local function isPositiveInt(v)
  return type(v) == "number" and v == v and v >= 1 and v < 9007199254740992 and math.floor(v) == v
end

local function isNonNegInt(v)
  return type(v) == "number" and v == v and v >= 0 and v < 9007199254740992 and math.floor(v) == v
end

local function isCombatLocked()
  if ns.Compat and type(ns.Compat.IsInCombat) == "function" then
    return ns.Compat.IsInCombat() == true
  end
  if type(_G.InCombatLockdown) == "function" then
    local ok, locked = pcall(_G.InCombatLockdown)
    return ok and locked == true
  end
  return false
end

local function resolveVerifiedSkillLineID(explicitSkillLineID, headerName)
  local exp = tonumber(explicitSkillLineID)
  if isPositiveInt(exp) then
    return exp
  end
  if type(headerName) ~= "string" or headerName == "" then
    return nil
  end
  local norm = string.lower(string.gsub(headerName, "^%s*(.-)%s*$", "%1"))
  local locale = (ns.Compat and ns.Compat.GetClientLocale and ns.Compat.GetClientLocale()) or "enUS"
  if locale == "enUS" or locale == "enGB" then
    if ENGLISH_SKILL_HEADER_TO_ID[norm] then
      return ENGLISH_SKILL_HEADER_TO_ID[norm]
    end
  end
  if type(_G.PROFESSIONS_FIRST_AID) == "string" and string.lower(_G.PROFESSIONS_FIRST_AID) == norm then
    return 129
  elseif type(_G.PROFESSIONS_COOKING) == "string" and string.lower(_G.PROFESSIONS_COOKING) == norm then
    return 185
  end
  return nil
end

local function anchorToTradeSkillFrame(f)
  if not f or isCombatLocked() then
    return
  end
  if f.ClearAllPoints then
    f:ClearAllPoints()
  end
  local anchorTarget = (_G.CraftFrame and type(_G.CraftFrame.IsShown) == "function" and _G.CraftFrame:IsShown() and _G.CraftFrame)
    or _G.TradeSkillFrame
    or _G.CraftFrame
  local uiParent = _G.UIParent
  if anchorTarget and type(anchorTarget.SetPoint) == "function" then
    local fitsRight = true
    if uiParent and type(uiParent.GetWidth) == "function" and type(anchorTarget.GetRight) == "function" then
      local okW, screenW = pcall(uiParent.GetWidth, uiParent)
      local okR, rightX = pcall(anchorTarget.GetRight, anchorTarget)
      if okW and okR and type(screenW) == "number" and type(rightX) == "number" and screenW > 0 then
        fitsRight = (rightX + PANEL_WIDTH + 16) <= screenW
      end
    end
    if fitsRight then
      f:SetPoint("TOPLEFT", anchorTarget, "TOPRIGHT", 8, -14)
      f.appliedAnchorMode = "tradeskill_right"
    else
      f:SetPoint("TOPLEFT", anchorTarget, "BOTTOMLEFT", 0, -6)
      f.appliedAnchorMode = "tradeskill_below_fallback"
    end
  else
    f:SetPoint("CENTER", uiParent, "CENTER", 240, 40)
    f.appliedAnchorMode = "center_fallback"
  end
end

function TradeSkillAdvisor.EnsureFrame()
  if TradeSkillAdvisor.frame then
    return TradeSkillAdvisor.frame
  end
  if type(CreateFrame) ~= "function" or isCombatLocked() then
    return nil
  end
  -- Astra Section 5 Taint Guardrail: ALWAYS parent addon sibling panels to `_G.UIParent`, NEVER Blizzard frames!
  local parent = _G.UIParent
  local f = (Widgets and Widgets.CreatePanel and Widgets.CreatePanel(parent, "surface.window", "border.gold"))
    or CreateFrame("Frame", nil, parent)
  if not f then
    return nil
  end
  f.parentedToUIParent = (parent == _G.UIParent)
  if f.SetSize then
    f:SetSize(PANEL_WIDTH, 154)
  end
  if f.SetFrameStrata then
    pcall(f.SetFrameStrata, f, "HIGH")
  end

  f.title = Widgets and Widgets.SafeCreateFontString and Widgets.SafeCreateFontString(f, "sectionTitle", "accent.gold") or nil
  f.viewLine = Widgets and Widgets.SafeCreateFontString and Widgets.SafeCreateFontString(f, "body", "text.primary") or nil
  f.cooldownLine = Widgets and Widgets.SafeCreateFontString and Widgets.SafeCreateFontString(f, "dense", "text.secondary") or nil
  f.noteLine = Widgets and Widgets.SafeCreateFontString and Widgets.SafeCreateFontString(f, "dense", "text.muted") or nil

  local innerW = PANEL_WIDTH - (PANEL_PADDING * 2)
  local y = -PANEL_PADDING
  for _, fs in ipairs({ f.title, f.viewLine, f.cooldownLine, f.noteLine }) do
    if fs then
      if fs.ClearAllPoints then fs:ClearAllPoints() end
      if fs.SetPoint then fs:SetPoint("TOPLEFT", f, "TOPLEFT", PANEL_PADDING, y) end
      if fs.SetWidth then pcall(fs.SetWidth, fs, innerW) end
      if fs.SetJustifyH then pcall(fs.SetJustifyH, fs, "LEFT") end
      if fs.SetWordWrap then pcall(fs.SetWordWrap, fs, true) end
      y = y - 28
    end
  end
  if f.Hide then
    f:Hide()
  end
  TradeSkillAdvisor.frame = f
  return f
end

local function extractSpellIDFromRecipeLink(link)
  if type(link) ~= "string" then
    return nil
  end
  local idStr = string.match(link, "enchant:(%d+)") or string.match(link, "spell:(%d+)")
  local n = tonumber(idStr)
  return isPositiveInt(n) and n or nil
end

local function parseToolOrFocusPairs(...)
  local n = select("#", ...)
  local tools = {}
  local allPresent = true
  for i = 1, n, 2 do
    local tName = select(i, ...)
    local tHas = select(i + 1, ...)
    if type(tName) == "string" and tName ~= "" then
      local present = (tHas ~= nil and tHas ~= false and tHas ~= 0)
      if not present then
        allPresent = false
      end
      table.insert(tools, {
        name = tName,
        present = present,
      })
    end
  end
  return tools, allPresent
end

local function classifyReagentItemKey(rItemID, rLink)
  if ns.Domain and ns.Domain.MarketIdentity and type(ns.Domain.MarketIdentity.ClassifyItemIdentity) == "function" and type(rLink) == "string" and rLink ~= "" then
    local okId, idRes = pcall(ns.Domain.MarketIdentity.ClassifyItemIdentity, {
      itemID = rItemID,
      itemLink = rLink,
      verifiedBaseSet = { [rItemID] = true },
    })
    if okId and type(idRes) == "table" and type(idRes.itemKey) == "string" then
      if idRes.tradeSafe == false or string.find(idRes.itemKey, "^i1:unk_var:") or string.find(idRes.itemKey, "^i1:service:") then
        return nil
      end
      return idRes.itemKey
    end
  end
  return string.format("i1:base:%d", rItemID)
end

local function normalizeValidatedRecipeEntry(rawEntry, isLinked, fallbackSkillLineID)
  if type(rawEntry) ~= "table" then
    return nil
  end
  local skillLineID = resolveVerifiedSkillLineID(rawEntry.skillLineID or fallbackSkillLineID, rawEntry.skillHeaderName)
  -- Astra P0-8: NEVER fall back to `outputItemID` as `spellID`, and NEVER default `skillLineID` to `1`!
  local spellID = isPositiveInt(tonumber(rawEntry.spellID)) and tonumber(rawEntry.spellID) or nil
  local outItemID = isPositiveInt(tonumber(rawEntry.outputItemID)) and tonumber(rawEntry.outputItemID) or nil
  local recipeName = (type(rawEntry.name) == "string" and rawEntry.name ~= "") and rawEntry.name or nil

  local rawReagents = rawEntry.reagents
  local reagents = {}
  local reagentsTruncated = (rawEntry.reagentsTruncated == true)
  local reagentsEnumerated = (rawEntry.reagentsEnumerated ~= false) and (type(rawReagents) == "table")
  local reagentsComplete = reagentsEnumerated and (not reagentsTruncated)

  if type(rawReagents) == "table" then
    if #rawReagents > MAX_REAGENTS_PER_RECIPE then
      reagentsTruncated = true
      reagentsComplete = false
    end
    for rIdx = 1, math.min(#rawReagents, MAX_REAGENTS_PER_RECIPE) do
      local r = rawReagents[rIdx]
      local rItemID = type(r) == "table" and tonumber(r.itemID) or nil
      local rQty = type(r) == "table" and tonumber(r.quantity) or nil
      local rKey = type(r) == "table" and r.itemKey or nil
      if type(rKey) ~= "string" and isPositiveInt(rItemID) then
        rKey = classifyReagentItemKey(rItemID, type(r) == "table" and r.itemLink or nil)
      end
      local rMetaOk = type(r) == "table" and (r.metadataComplete ~= false)
      if type(rKey) == "string" and (string.find(rKey, "^i1:unk_var:") or string.find(rKey, "^i1:service:")) then
        rMetaOk = false
      end
      -- Astra P0-8: NEVER default `nil` or non-positive reagent quantity to `1`!
      if isPositiveInt(rItemID) and isPositiveInt(rQty) and type(rKey) == "string" and rKey ~= "" and rMetaOk then
        table.insert(reagents, {
          itemID = rItemID,
          itemKey = rKey,
          quantity = rQty,
          name = type(r.name) == "string" and r.name or nil,
          metadataComplete = true,
        })
      else
        reagentsComplete = false
      end
    end
  else
    reagentsComplete = false
  end

  if rawEntry.reagentsComplete == false or rawEntry.metadataComplete == false then
    reagentsComplete = false
  end

  local minMade = tonumber(rawEntry.minMade)
  local maxMade = tonumber(rawEntry.maxMade)
  local madeValid = true
  if minMade == nil then
    minMade = 1
  elseif not isPositiveInt(minMade) then
    madeValid = false
    minMade = 1
  end
  if maxMade == nil then
    maxMade = minMade
  elseif not isPositiveInt(maxMade) or maxMade < minMade then
    madeValid = false
    maxMade = minMade
  end

  -- Astra P0-8: NEVER coerce `nil` cooldown returns to `0` (`READY_OBSERVED`)!
  local rawCd = rawEntry.remainingCooldownSec
  local cdApiObserved = (rawEntry.cooldownApiObserved ~= false) and (rawCd ~= nil)
  local cooldownStatus = "UNKNOWN"
  if isLinked then
    cooldownStatus = "LINKED_VIEW_IGNORED"
  elseif cdApiObserved and type(rawCd) == "number" and rawCd == rawCd then
    if rawCd == 0 then
      cooldownStatus = "READY_OBSERVED"
    elseif rawCd > 0 then
      cooldownStatus = "ON_COOLDOWN_OBSERVED"
    end
  elseif type(rawEntry.cooldownStatus) == "string" and rawEntry.cooldownStatus ~= "" then
    cooldownStatus = rawEntry.cooldownStatus
  end

  local requiredTools = type(rawEntry.requiredTools) == "table" and rawEntry.requiredTools or {}
  local requiredToolsPresent = rawEntry.requiredToolsPresent
  if requiredToolsPresent == nil then
    requiredToolsPresent = true
    for _, t in ipairs(requiredTools) do
      if type(t) == "table" and t.present == false then
        requiredToolsPresent = false
        break
      end
    end
  end
  local requiredStationPresent = (rawEntry.requiredStationPresent ~= false)

  local recipeIdentityComplete = isPositiveInt(skillLineID) and isPositiveInt(spellID)
  local metadataComplete = (recipeName ~= nil) and reagentsComplete and madeValid
  local scanComplete = (not isLinked)
    and recipeIdentityComplete
    and metadataComplete
    and (#reagents > 0)
    and (not reagentsTruncated)

  return {
    index = rawEntry.index,
    scannerKind = rawEntry.scannerKind or "tradeskill",
    name = recipeName,
    skillLineID = skillLineID,
    spellID = spellID,
    outputItemID = outItemID,
    cooldownID = rawEntry.cooldownID,
    remainingCooldownSec = (type(rawCd) == "number" and rawCd == rawCd and rawCd >= 0) and rawCd or nil,
    cooldownApiObserved = cdApiObserved,
    cooldownStatus = cooldownStatus,
    minMade = minMade,
    maxMade = maxMade,
    reagents = reagents,
    reagentsComplete = reagentsComplete,
    reagentsTruncated = reagentsTruncated,
    requiredTools = requiredTools,
    requiredToolsPresent = requiredToolsPresent,
    requiredStationPresent = requiredStationPresent,
    stationOrToolReq = rawEntry.stationOrToolReq,
    recipeIdentityComplete = recipeIdentityComplete,
    metadataComplete = metadataComplete,
    scanComplete = scanComplete,
    learnedRecipeVerified = (not isLinked) and (rawEntry.learnedRecipeVerified ~= false) and recipeIdentityComplete,
  }
end

local function scanLiveTradeSkillsOrCrafts(scannerKind, explicitSkillLineID)
  local rawList = {}
  local listTruncated = false

  if scannerKind == "craft" then
    local getNum = _G.GetNumCrafts
    local getInfo = _G.GetCraftInfo
    local getItemLink = _G.GetCraftItemLink
    local getRecipeLink = _G.GetCraftRecipeLink
    local getNumReagents = _G.GetCraftNumReagents
    local getReagentLink = _G.GetCraftReagentItemLink
    local getReagentInfo = _G.GetCraftReagentInfo
    local getFocus = _G.GetCraftSpellFocus
    local getLine = _G.GetCraftDisplaySkillLine

    local headerName = (type(getLine) == "function") and select(2, pcall(getLine)) or nil
    local resolvedLineID = resolveVerifiedSkillLineID(explicitSkillLineID, headerName)

    if type(getNum) == "function" and type(getInfo) == "function" then
      local okN, total = pcall(getNum)
      local totalInt = (okN and type(total) == "number" and total == total) and math.max(0, math.floor(total)) or 0
      if totalInt > MAX_SCAN_ROWS then
        listTruncated = true
      end
      local maxRows = math.min(MAX_SCAN_ROWS, totalInt)
      for idx = 1, maxRows do
        local okI, craftName, _, craftType = pcall(getInfo, idx)
        if okI and craftType ~= "header" and craftType ~= "subheader" then
          local outLink = type(getItemLink) == "function" and select(2, pcall(getItemLink, idx)) or nil
          local recLink = type(getRecipeLink) == "function" and select(2, pcall(getRecipeLink, idx)) or nil
          local outItemID = (type(outLink) == "string" and ns.Compat and ns.Compat.ExtractItemID and ns.Compat.ExtractItemID(outLink)) or nil
          local spellID = extractSpellIDFromRecipeLink(recLink)
          if not spellID and isPositiveInt(tonumber(outLink and string.match(tostring(outLink), "enchant:(%d+)"))) then
            spellID = tonumber(string.match(tostring(outLink), "enchant:(%d+)"))
          end

          local reqTools, toolsPresent = {}, true
          if type(getFocus) == "function" then
            local okF, f1, f2, f3, f4, f5, f6 = pcall(getFocus, idx)
            if okF then
              reqTools, toolsPresent = parseToolOrFocusPairs(f1, f2, f3, f4, f5, f6)
            else
              toolsPresent = false
            end
          end

          local reagents = {}
          local reagentsEnumerated = false
          local reagentsTruncated = false
          local reagentsComplete = false
          if type(getNumReagents) == "function" and type(getReagentInfo) == "function" then
            local okR, rCount = pcall(getNumReagents, idx)
            if okR and isNonNegInt(rCount) then
              reagentsEnumerated = true
              reagentsComplete = (rCount > 0)
              if rCount > MAX_REAGENTS_PER_RECIPE then
                reagentsTruncated = true
                reagentsComplete = false
              end
              for rIdx = 1, math.min(rCount, MAX_REAGENTS_PER_RECIPE) do
                local rLink = type(getReagentLink) == "function" and select(2, pcall(getReagentLink, idx, rIdx)) or nil
                local rItemID = (type(rLink) == "string" and ns.Compat and ns.Compat.ExtractItemID and ns.Compat.ExtractItemID(rLink)) or nil
                local okRI, rName, _, rQty = pcall(getReagentInfo, idx, rIdx)
                local rKey = isPositiveInt(rItemID) and classifyReagentItemKey(rItemID, rLink) or nil
                if okRI and type(rName) == "string" and rName ~= "" and isPositiveInt(rItemID) and isPositiveInt(rQty) and type(rKey) == "string" then
                  table.insert(reagents, {
                    itemID = rItemID,
                    itemKey = rKey,
                    quantity = rQty,
                    name = rName,
                    metadataComplete = true,
                  })
                else
                  reagentsComplete = false
                end
              end
            end
          end

          table.insert(rawList, {
            index = idx,
            scannerKind = "craft",
            name = craftName,
            skillLineID = resolvedLineID,
            spellID = spellID,
            outputItemID = outItemID,
            remainingCooldownSec = nil,
            cooldownApiObserved = false,
            cooldownStatus = "NO_CRAFT_COOLDOWN_API",
            minMade = 1,
            maxMade = 1,
            reagents = reagents,
            reagentsEnumerated = reagentsEnumerated,
            reagentsTruncated = reagentsTruncated,
            reagentsComplete = reagentsComplete,
            requiredTools = reqTools,
            requiredToolsPresent = toolsPresent,
          })
        end
      end
    end
    return rawList, listTruncated
  end

  -- Standard `TradeSkill` scanner (`Alchemy`, `Blacksmithing`, `Cooking`, `Engineering`, `First Aid`, `LW`, `Mining`, `Tailoring`):
  local getNum = _G.GetNumTradeSkills
  local getInfo = _G.GetTradeSkillInfo
  local getItemLink = _G.GetTradeSkillItemLink
  local getRecipeLink = _G.GetTradeSkillRecipeLink
  local getCooldown = _G.GetTradeSkillCooldown
  local getNumMade = _G.GetTradeSkillNumMade
  local getNumReagents = _G.GetTradeSkillNumReagents
  local getReagentLink = _G.GetTradeSkillReagentItemLink
  local getReagentInfo = _G.GetTradeSkillReagentInfo
  local getTools = _G.GetTradeSkillTools
  local getLine = _G.GetTradeSkillLine

  local headerName = (type(getLine) == "function") and select(2, pcall(getLine)) or nil
  local resolvedLineID = resolveVerifiedSkillLineID(explicitSkillLineID, headerName)

  if type(getNum) == "function" and type(getInfo) == "function" then
    local okN, total = pcall(getNum)
    local totalInt = (okN and type(total) == "number" and total == total) and math.max(0, math.floor(total)) or 0
    if totalInt > MAX_SCAN_ROWS then
      listTruncated = true
    end
    local maxRows = math.min(MAX_SCAN_ROWS, totalInt)
    for idx = 1, maxRows do
      local okI, skillName, skillType = pcall(getInfo, idx)
      if okI and skillType ~= "header" and skillType ~= "subheader" then
        local outLink = type(getItemLink) == "function" and select(2, pcall(getItemLink, idx)) or nil
        local recLink = type(getRecipeLink) == "function" and select(2, pcall(getRecipeLink, idx)) or nil

        local cdObserved = false
        local remSec = nil
        if type(getCooldown) == "function" then
          local okCD, cdVal = pcall(getCooldown, idx)
          if okCD then
            cdObserved = true
            remSec = cdVal -- Keep raw `nil` as `nil` (NEVER default `nil` to `0`!)
          end
        end

        local minMade, maxMade = nil, nil
        if type(getNumMade) == "function" then
          local okM, mn, mx = pcall(getNumMade, idx)
          if okM and isPositiveInt(mn) then
            minMade = mn
            maxMade = isPositiveInt(mx) and math.max(mn, mx) or mn
          end
        else
          minMade, maxMade = 1, 1
        end

        local reqTools, toolsPresent = {}, true
        if type(getTools) == "function" then
          local okT, t1, t2, t3, t4, t5, t6 = pcall(getTools, idx)
          if okT then
            reqTools, toolsPresent = parseToolOrFocusPairs(t1, t2, t3, t4, t5, t6)
          else
            toolsPresent = false
          end
        end

        local outItemID = (type(outLink) == "string" and ns.Compat and ns.Compat.ExtractItemID and ns.Compat.ExtractItemID(outLink)) or nil
        local spellID = extractSpellIDFromRecipeLink(recLink)

        local reagents = {}
        local reagentsEnumerated = false
        local reagentsTruncated = false
        local reagentsComplete = false
        if type(getNumReagents) == "function" and type(getReagentInfo) == "function" then
          local okR, rCount = pcall(getNumReagents, idx)
          if okR and isNonNegInt(rCount) then
            reagentsEnumerated = true
            reagentsComplete = (rCount > 0)
            if rCount > MAX_REAGENTS_PER_RECIPE then
              reagentsTruncated = true
              reagentsComplete = false
            end
            for rIdx = 1, math.min(rCount, MAX_REAGENTS_PER_RECIPE) do
              local rLink = type(getReagentLink) == "function" and select(2, pcall(getReagentLink, idx, rIdx)) or nil
              local rItemID = (type(rLink) == "string" and ns.Compat and ns.Compat.ExtractItemID and ns.Compat.ExtractItemID(rLink)) or nil
              local okRI, rName, _, rQty = pcall(getReagentInfo, idx, rIdx)
              local rKey = isPositiveInt(rItemID) and classifyReagentItemKey(rItemID, rLink) or nil
              if okRI and type(rName) == "string" and rName ~= "" and isPositiveInt(rItemID) and isPositiveInt(rQty) and type(rKey) == "string" then
                table.insert(reagents, {
                  itemID = rItemID,
                  itemKey = rKey,
                  quantity = rQty,
                  name = rName,
                  metadataComplete = true,
                })
              else
                reagentsComplete = false
              end
            end
          end
        end

        table.insert(rawList, {
          index = idx,
          scannerKind = "tradeskill",
          name = skillName,
          skillLineID = resolvedLineID,
          spellID = spellID,
          outputItemID = outItemID,
          remainingCooldownSec = remSec,
          cooldownApiObserved = cdObserved,
          minMade = minMade,
          maxMade = maxMade,
          reagents = reagents,
          reagentsEnumerated = reagentsEnumerated,
          reagentsTruncated = reagentsTruncated,
          reagentsComplete = reagentsComplete,
          requiredTools = reqTools,
          requiredToolsPresent = toolsPresent,
          metadataComplete = (minMade ~= nil) and reagentsComplete,
        })
      end
    end
  end

  return rawList, listTruncated
end

function TradeSkillAdvisor.ScanAndEvaluate(overrides)
  overrides = type(overrides) == "table" and overrides or {}
  local isLinked = (overrides.isLinked == true)
    or (ns.Compat and type(ns.Compat.IsTradeSkillViewLinked) == "function" and ns.Compat.IsTradeSkillViewLinked() == true)

  local scannerKind = overrides.scannerKind
  if scannerKind ~= "craft" and scannerKind ~= "tradeskill" then
    if _G.CraftFrame and type(_G.CraftFrame.IsShown) == "function" and _G.CraftFrame:IsShown() then
      scannerKind = "craft"
    else
      scannerKind = "tradeskill"
    end
  end

  local rawEntries = overrides.recipeEntries
  local listTruncated = false
  if type(rawEntries) ~= "table" then
    rawEntries, listTruncated = scanLiveTradeSkillsOrCrafts(scannerKind, overrides.skillLineID)
  end

  local validatedEntries = {}
  local completeRecipeCount = 0
  local incompleteRecipeCount = 0
  local observedCooldownCount = 0
  local discoveryRecordedCount = 0
  local optInDiscovery = ns.State and type(ns.State.IsDiscoveryOptInEnabled) == "function" and ns.State.IsDiscoveryOptInEnabled()

  for _, rawEntry in ipairs(rawEntries) do
    local entry = normalizeValidatedRecipeEntry(rawEntry, isLinked, overrides.skillLineID)
    if entry then
      table.insert(validatedEntries, entry)
      if entry.scanComplete then
        completeRecipeCount = completeRecipeCount + 1
      else
        incompleteRecipeCount = incompleteRecipeCount + 1
      end

      if ns.Domain and ns.Domain.RecipeRegistry and type(ns.Domain.RecipeRegistry.HarvestFromTradeSkillEntry) == "function" then
        ns.Domain.RecipeRegistry.HarvestFromTradeSkillEntry({
          recipeID = entry.spellID and ("spell:" .. tostring(entry.spellID)) or entry.name,
          recipeName = entry.name,
          outputItemID = entry.outputItemID,
          spellID = entry.spellID,
          reagents = entry.reagents,
        }, { buildVersion = overrides.buildVersion })
      end

      local cdID = entry.cooldownID or (entry.spellID and KNOWN_COOLDOWN_BY_SPELL[entry.spellID])
      if not isLinked
        and cdID
        and entry.cooldownApiObserved == true
        and entry.remainingCooldownSec ~= nil
        and ns.Compat
        and type(ns.Compat.NormalizeRecipeCooldownToServerEpoch) == "function"
      then
        local norm = ns.Compat.NormalizeRecipeCooldownToServerEpoch(
          entry.remainingCooldownSec,
          entry.recipeIdentityComplete == true,
          isLinked,
          nil,
          entry.cooldownApiObserved
        )
        if norm and (norm.status == "READY_OBSERVED" or norm.status == "ON_COOLDOWN_OBSERVED") and ns.State and type(ns.State.RecordObservedCooldown) == "function" then
          local okCD = ns.State.RecordObservedCooldown(cdID, norm)
          if okCD then
            observedCooldownCount = observedCooldownCount + 1
          end
        end
      end

      -- Astra P0-8: Discovery candidates require verified `skillLineID` AND `spellID` (NEVER `1` default or `outputItemID` fallback!)
      if optInDiscovery
        and entry.reagentsComplete == true
        and #(entry.reagents or {}) > 0
        and isPositiveInt(entry.skillLineID)
        and isPositiveInt(entry.spellID)
      then
        local outKey = entry.outputItemID and string.format("i1:base:%d", entry.outputItemID)
          or string.format("i1:service:%s:%d", tostring(entry.scannerKind or "tradeskill"), entry.spellID)
        local okRec = ns.State.RecordDiscoveryCandidate("recipe", {
          subjectKey = string.format("recipe:%d:%d", entry.skillLineID, entry.spellID),
          skillLineID = entry.skillLineID,
          spellOrRecipeID = entry.spellID,
          viewContext = isLinked and "linked" or "own",
          learnedOrAccessStatus = isLinked and "linked_inspection" or "learned",
          outputItemKey = outKey,
          minMade = entry.minMade or 1,
          maxMade = entry.maxMade or 1,
          reagents = entry.reagents,
          stationOrToolReq = tostring(entry.stationOrToolReq or (#(entry.requiredTools or {}) > 0 and entry.requiredTools[1].name or "none")),
          metadataComplete = (entry.metadataComplete == true),
        })
        if okRec then
          discoveryRecordedCount = discoveryRecordedCount + 1
        end
      end
    end
  end

  local cdEval = {}
  if ns.Domain and ns.Domain.ProfessionAdvisor and ns.State and ns.State.GetAccountCooldownRecords then
    local clocks = ns.Compat and ns.Compat.GetDualClockNow and ns.Compat.GetDualClockNow() or {}
    cdEval = ns.Domain.ProfessionAdvisor.EvaluateMultiAltCooldowns(
      ns.State.GetAccountCooldownRecords(),
      clocks.serverEpoch or 0
    )
  end

  local out = {
    isLinked = isLinked,
    scannerKind = scannerKind,
    listTruncated = listTruncated,
    scannedRecipeCount = #validatedEntries,
    completeRecipeCount = completeRecipeCount,
    incompleteRecipeCount = incompleteRecipeCount,
    entries = validatedEntries,
    observedCooldownCount = observedCooldownCount,
    discoveryRecordedCount = discoveryRecordedCount,
    accountCooldowns = cdEval,
  }
  TradeSkillAdvisor.lastEvaluation = out
  return out
end

function TradeSkillAdvisor.PinRecipeToReservations(entry, plannedExecutions, ownerKey)
  if type(entry) ~= "table" then
    return false, "invalid_recipe_entry"
  end
  if entry.scanComplete ~= true or entry.learnedRecipeVerified ~= true then
    return false, "incomplete_or_linked_recipe_scan"
  end
  if not isPositiveInt(entry.skillLineID) or not isPositiveInt(entry.spellID) then
    return false, "missing_verified_skill_line_or_spell_id"
  end
  if not (ns.State and type(ns.State.ReserveCraftGoal) == "function") then
    return false, "craft_reservation_store_unavailable"
  end
  local qty = tonumber(plannedExecutions) or 1
  if not isPositiveInt(qty) then
    return false, "invalid_planned_executions"
  end
  return ns.State.ReserveCraftGoal({
    ownerKey = ownerKey,
    viewContext = "own",
    isLinked = false,
    recipeIdentityStatus = "SPELL_VERIFIED",
    skillLineID = entry.skillLineID,
    spellID = entry.spellID,
    spellOrRecipeID = entry.spellID,
    name = entry.name,
    recipeName = entry.name,
    outputItemID = entry.outputItemID,
    minMade = entry.minMade,
    maxMade = entry.maxMade,
    reagents = entry.reagents,
    reagentsComplete = (entry.reagentsComplete == true),
    reagentsTruncated = (entry.reagentsTruncated == true),
    requiredTools = entry.requiredTools,
    requiredToolsPresent = entry.requiredToolsPresent,
    requiredStationPresent = entry.requiredStationPresent,
    cooldownStatus = entry.cooldownStatus,
    scanComplete = true,
    learnedRecipeVerified = true,
  }, qty)
end

function TradeSkillAdvisor.Render(evalResult)
  local eval = evalResult or TradeSkillAdvisor.ScanAndEvaluate()
  if not eval then
    return nil
  end
  if isCombatLocked() then
    TradeSkillAdvisor.pendingCombatShow = true
    return eval
  end
  local f = TradeSkillAdvisor.EnsureFrame()
  if not f then
    return eval
  end
  anchorToTradeSkillFrame(f)

  if f.title and f.title.SetText then
    f.title:SetText("ForeverHub Profession Helper")
  end
  if f.viewLine and f.viewLine.SetText then
    if eval.isLinked then
      f.viewLine:SetText("Linked profession view (read-only; reservations & character timers disabled)")
    elseif (eval.incompleteRecipeCount or 0) > 0 or eval.listTruncated then
      f.viewLine:SetText(
        string.format(
          "Inspected %d recipe(s) (%d complete, %d pending item cache)",
          eval.scannedRecipeCount or 0,
          eval.completeRecipeCount or 0,
          eval.incompleteRecipeCount or 0
        )
      )
    else
      f.viewLine:SetText(
        string.format("Inspected %d complete recipe(s) · Unreserved reagents protected", eval.scannedRecipeCount or 0)
      )
    end
  end
  if f.cooldownLine and f.cooldownLine.SetText then
    if #(eval.accountCooldowns or {}) > 0 then
      local top = eval.accountCooldowns[1]
      f.cooldownLine:SetText(string.format("Cooldowns: %s (%d tracked across account)", tostring(top.statusLabel), #eval.accountCooldowns))
    else
      f.cooldownLine:SetText("Cooldowns: Explicit timer values recorded on own-character scan")
    end
  end
  if f.noteLine and f.noteLine.SetText then
    f.noteLine:SetText("Zero automated crafting · Only complete own-character recipes can reserve materials")
  end

  if f.Show then
    f:Show()
  end
  return eval
end

function TradeSkillAdvisor.FlushDeferredIfReady()
  if isCombatLocked() then
    return
  end
  if TradeSkillAdvisor.pendingCombatHide then
    TradeSkillAdvisor.pendingCombatHide = false
    TradeSkillAdvisor.pendingCombatShow = false
    if TradeSkillAdvisor.frame and TradeSkillAdvisor.frame.Hide then
      TradeSkillAdvisor.frame:Hide()
    end
  elseif TradeSkillAdvisor.pendingCombatShow and TradeSkillAdvisor.active then
    TradeSkillAdvisor.pendingCombatShow = false
    TradeSkillAdvisor.Render(TradeSkillAdvisor.lastEvaluation)
  end
end

function TradeSkillAdvisor.OnTradeSkillShow(scannerKind)
  TradeSkillAdvisor.active = true
  TradeSkillAdvisor.pendingCombatHide = false
  local eval = TradeSkillAdvisor.ScanAndEvaluate({ scannerKind = scannerKind })
  return TradeSkillAdvisor.Render(eval)
end

function TradeSkillAdvisor.OnTradeSkillUpdate(scannerKind)
  if TradeSkillAdvisor.active then
    local eval = TradeSkillAdvisor.ScanAndEvaluate({ scannerKind = scannerKind })
    return TradeSkillAdvisor.Render(eval)
  end
  return nil
end

function TradeSkillAdvisor.OnTradeSkillClosed()
  TradeSkillAdvisor.active = false
  TradeSkillAdvisor.pendingCombatShow = false
  if isCombatLocked() then
    TradeSkillAdvisor.pendingCombatHide = true
    return
  end
  if TradeSkillAdvisor.frame and TradeSkillAdvisor.frame.Hide then
    TradeSkillAdvisor.frame:Hide()
  end
end

return TradeSkillAdvisor
