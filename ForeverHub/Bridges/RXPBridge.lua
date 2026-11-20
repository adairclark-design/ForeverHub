local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
local RXPBridge = {}
ns.Bridges.RXPBridge = RXPBridge

RXPBridge.registered = false

function RXPBridge.IsAvailable()
  return type(_G.RXPGuides) == "table" and type(_G.RXPGuides.RegisterGuide) == "function"
end

function RXPBridge.BuildDetourGuideText()
  local books = (ns.Data and ns.Data.booksByIdentity) or {}
  local sortedKeys = {}
  for k, b in pairs(books) do
    if type(b) == "table" and b.statusInForever == "verified_location" and type(b.locations) == "table" and #b.locations > 0 then
      table.insert(sortedKeys, k)
    end
  end
  table.sort(sortedKeys)

  local lines = {
    "#classic",
    "#version 1",
    "#group ForeverHub Detours",
    "#name ForeverHub Verified Library Books (36 Unique Books / 37 Locations)",
    "step",
    "    .note Verified WoW: Forever Library Books. Unfound Feralas book is excluded. Rumi of Gnomeregan appears in both Loch Modan and Westfall (can only be collected/turned in once).",
  }

  for _, key in ipairs(sortedKeys) do
    local book = books[key]
    local multiLocNote = (#book.locations > 1) and " (Duplicate copy — collect once only)" or ""
    for _, loc in ipairs(book.locations) do
      table.insert(lines, "step")
      table.insert(
        lines,
        string.format(
          "    #sticky\n    .goto %s,%.1f,%.1f\n    .note %s%s — %s",
          loc.zone,
          tonumber(loc.x) or 50.0,
          tonumber(loc.y) or 50.0,
          book.title,
          multiLocNote,
          loc.note or ""
        )
      )
    end
  end

  return table.concat(lines, "\n")
end

-- User-triggered only; never overwrites or auto-selects the active RXP leveling guide.
function RXPBridge.RegisterBookDetours(verbose)
  if not RXPBridge.IsAvailable() then
    if verbose then
      ns.Compat.Print("RXPGuides is not loaded or RegisterGuide is unavailable.")
    end
    return false, "RXPGuides unavailable"
  end

  if RXPBridge.registered then
    if verbose then
      ns.Compat.Print("ForeverHub Library Book Detours are already registered under 'ForeverHub Detours' in RXPGuides.")
    end
    return true, "already_registered"
  end

  local guideText = RXPBridge.BuildDetourGuideText()
  local ok, err = pcall(_G.RXPGuides.RegisterGuide, guideText)
  if not ok then
    if verbose then
      ns.Compat.Print("Could not register RXP detour guide: " .. tostring(err))
    end
    return false, tostring(err)
  end

  RXPBridge.registered = true
  if verbose then
    ns.Compat.Print(
      "Registered 'ForeverHub Verified Library Books' under group 'ForeverHub Detours' in RXPGuides (active leveling guide left unchanged)."
    )
  end
  return true, "registered"
end

-- ============================================================================
-- RXP Guide Lookup Helper
-- ============================================================================

function RXPBridge.IsGuideRegisteredInRXP(groupName, guideName)
  local rxp = _G.RXPGuides
  if type(rxp) ~= "table" then
    return false
  end
  if type(rxp.GetGuideTable) == "function" then
    local ok, g = pcall(rxp.GetGuideTable, groupName, guideName)
    if ok and type(g) == "table" then
      return true
    end
  end
  if type(rxp.guides) == "table" then
    local key = string.format("%s||%s", tostring(groupName), tostring(guideName))
    if type(rxp.guides[key]) == "table" then
      return true
    end
    for _, g in pairs(rxp.guides) do
      if type(g) == "table" and g.group == groupName and g.name == guideName then
        return true
      end
    end
  end
  return false
end

-- ============================================================================
-- v0.5.0 Raw Gold Farms Explicit RXP Guide Export (+ForeverHub Gold Farms)
-- Remediated per Astra P0-5 & Gate 9:
--   * Stable `#name` without rank prefixes (e.g. `Badlands — Elementals and Coyotes`), `#version 2`
--   * `travel` hops use `.goto <map>,<x>,<y>,<radius>` so RXP advances on arrival
--   * `boat_crossing` hops target the destination dock on `targetUiMapID` (never completing on origin pier)
--   * `vendor` stops use a manual `+` checkbox objective + bare `.goto` (`textOnly = true`, never proximity-completed)
--   * `grind` camps use `.loop 25,<map>,...` ONLY when >=2 verified spawn points exist, else sticky single-point `.goto` (no `#loop`)
-- ============================================================================

RXPBridge.GOLD_FARMS_GUIDE_GROUP = "+ForeverHub Gold Farms"
RXPBridge.goldFarmsRegisteredByID = {}

function RXPBridge.BuildGoldFarmGuideName(farm)
  if type(farm) ~= "table" then
    return nil
  end
  if type(farm.rxpGuideName) == "string" and farm.rxpGuideName ~= "" then
    return farm.rxpGuideName
  end
  return tostring(farm.title or farm.farmID)
end

function RXPBridge.BuildGoldFarmDisplayName(farm)
  if type(farm) ~= "table" then
    return nil
  end
  local ord = tonumber(farm.candidateOrder or farm.rank) or 1
  return string.format("Candidate %d: %s", ord, RXPBridge.BuildGoldFarmGuideName(farm))
end

function RXPBridge.BuildGoldFarmGuideText(farm, catalog)
  catalog = catalog or (ns.State and ns.State.GetCompiledGoldFarms and ns.State.GetCompiledGoldFarms())
  if type(farm) ~= "table" or farm.reviewStatus ~= "verified" then
    return nil, "unverified_or_missing_farm"
  end
  local GoldFarms = ns.Domain and ns.Domain.GoldFarms
  if not GoldFarms then
    return nil, "missing_gold_farms_domain"
  end

  local guideName = RXPBridge.BuildGoldFarmGuideName(farm)
  local displayName = RXPBridge.BuildGoldFarmDisplayName(farm)
  local gphMeta = farm.gphMeta or {}
  local rxpDslVersion = 2

  local rateSummaryLine
  if gphMeta.vendorFloorStatus == "unmeasured_until_sampled" then
    rateSummaryLine = string.format(
      "    >>%s (%s, Lv %s) — Vendor liq.: UNKNOWN pre-sample (Source-Verified Candidate; measure character cash flow via Net Purse Change / Active Hr in /fh gold).",
      tostring(farm.title),
      tostring(farm.zoneName),
      tostring(farm.recommendedLevelRange or "48-60")
    )
  else
    rateSummaryLine = string.format(
      "    >>%s (%s, Lv %s) — Community Est.: %d-%dg/hr (Unverified Reference; measure character cash flow via Net Purse Change / Active Hr in /fh gold).",
      tostring(farm.title),
      tostring(farm.zoneName),
      tostring(farm.recommendedLevelRange or "40"),
      tonumber(gphMeta.lowGold) or 0,
      tonumber(gphMeta.highGold) or 0
    )
  end

  local lines = {
    "#forever",
    string.format("#version %d", rxpDslVersion),
    string.format("#group %s", RXPBridge.GOLD_FARMS_GUIDE_GROUP),
    string.format("#name %s", guideName),
    string.format("#displayname %s", displayName),
    "",
    "step",
    rateSummaryLine,
    string.format("    >>Mage Notes: %s", tostring(farm.magePullNotes or "")),
  }

  local emittedSteps = 0
  for _, st in ipairs(farm.travelSteps or {}) do
    if type(st) == "table" and st.reviewStatus == "verified" then
      local destOk = GoldFarms.ValidateStepDestination(st, catalog)
      if destOk then
        local mapID = tonumber(st.destination.uiMapID)
        local xPct, yPct = GoldFarms.NormalizedToPercent(st.destination.x01, st.destination.y01)
        local noteSuffix = (st.note and st.note ~= "") and (" — " .. tostring(st.note)) or ""
        local stepSummary = string.format("%s%s", tostring(st.title or st.stepID), noteSuffix)

        if st.kind == "boat_crossing" then
          local arrivalPier = st.arrivalLandmarkKey
            and catalog
            and type(catalog.piersByKey) == "table"
            and catalog.piersByKey[st.arrivalLandmarkKey]
            or nil
          local targetMapID = tonumber(st.targetUiMapID)
          local arrX, arrY = nil, nil
          if arrivalPier and tonumber(arrivalPier.uiMapID) == targetMapID then
            arrX, arrY = GoldFarms.NormalizedToPercent(arrivalPier.x01, arrivalPier.y01)
          end
          if targetMapID and arrX and arrY then
            table.insert(lines, "step")
            table.insert(lines, string.format("    .goto %d,%.2f,%.2f,35 >>%s", targetMapID, arrX, arrY, stepSummary))
            emittedSteps = emittedSteps + 1
          end
        elseif xPct and yPct then
          if st.kind == "travel" then
            local rad = math.max(10, math.floor(tonumber(st.arrivalRadiusYards) or 25))
            table.insert(lines, "step")
            table.insert(lines, string.format("    .goto %d,%.2f,%.2f,%d >>%s", mapID, xPct, yPct, rad, stepSummary))
            if st.npcName and st.npcID then
              table.insert(lines, string.format("    .target %s::%d", tostring(st.npcName), tonumber(st.npcID)))
            end
            emittedSteps = emittedSteps + 1
          elseif st.kind == "vendor" then
            table.insert(lines, "step")
            table.insert(lines, string.format("    +%s", stepSummary))
            table.insert(lines, string.format("    .goto %d,%.2f,%.2f", mapID, xPct, yPct))
            if st.npcName and st.npcID then
              table.insert(lines, string.format("    .target %s::%d", tostring(st.npcName), tonumber(st.npcID)))
            end
            emittedSteps = emittedSteps + 1
          elseif st.kind == "grind" then
            table.insert(lines, "step")
            table.insert(lines, string.format("    >>%s", stepSummary))
            local loopCoords = {}
            if type(st.loopPoints) == "table" and #st.loopPoints >= 2 then
              local allValid = true
              for _, pt in ipairs(st.loopPoints) do
                local lx, ly = GoldFarms.NormalizedToPercent(pt and pt.x01, pt and pt.y01)
                if not lx or not ly then
                  allValid = false
                  break
                end
                table.insert(loopCoords, string.format("%.2f,%.2f", lx, ly))
              end
              if not allValid then
                loopCoords = {}
              end
            end
            if #loopCoords >= 2 then
              table.insert(lines, string.format("    .loop 25,%d,%s", mapID, table.concat(loopCoords, ",")))
            else
              table.insert(lines, string.format("    .goto %d,%.2f,%.2f", mapID, xPct, yPct))
            end
            if st.npcName and st.npcID then
              table.insert(lines, string.format("    .target %s::%d", tostring(st.npcName), tonumber(st.npcID)))
            end
            emittedSteps = emittedSteps + 1
          end
        end
      end
    end
  end

  if emittedSteps == 0 then
    return nil, "no_verified_farm_steps"
  end

  return table.concat(lines, "\n"), nil
end

-- Checks ONLY live `_G.RXPGuides.currentGuide` — never stale `_G.RXPCData` (Astra P2 & Gate 9).
function RXPBridge.IsGoldFarmGuideSelected(farmID, catalog)
  catalog = catalog or (ns.State and ns.State.GetCompiledGoldFarms and ns.State.GetCompiledGoldFarms())
  local expectedName = nil
  if farmID and catalog then
    local farmObj = (catalog.farmsByID and catalog.farmsByID[farmID])
      or (catalog.arcaneGrindFarmsByID and catalog.arcaneGrindFarmsByID[farmID])
      or (catalog.experimentalArcaneFarmsByID and catalog.experimentalArcaneFarmsByID[farmID])
      or (catalog.expandedRoutesByID and catalog.expandedRoutesByID[farmID])
    if farmObj then
      expectedName = RXPBridge.BuildGoldFarmGuideName(farmObj)
    end
  end

  local rxp = _G.RXPGuides
  if type(rxp) == "table" and type(rxp.currentGuide) == "table" then
    if rxp.currentGuide.group == RXPBridge.GOLD_FARMS_GUIDE_GROUP then
      if expectedName == nil or rxp.currentGuide.name == expectedName then
        return true
      end
    end
  end

  return false
end

function RXPBridge.RegisterGoldFarmGuide(farmQuery, verbose, catalog)
  if not RXPBridge.IsAvailable() then
    if verbose then
      ns.Compat.Print("RXPGuides is not loaded; continuing with ForeverHub standalone navigation.")
    end
    return false, "unavailable", "RXPGuides unavailable"
  end

  catalog = catalog or (ns.State and ns.State.GetCompiledGoldFarms and ns.State.GetCompiledGoldFarms())
  local farm, resolveErr = ns.Domain.GoldFarms.ResolveFarm(farmQuery, catalog)
  if not farm then
    if verbose then
      ns.Compat.Print(tostring(resolveErr))
    end
    return false, "unknown_farm", tostring(resolveErr)
  end

  local guideText, buildErr = RXPBridge.BuildGoldFarmGuideText(farm, catalog)
  if not guideText then
    if verbose then
      ns.Compat.Print("Cannot export gold farm RXP guide: " .. tostring(buildErr))
    end
    return false, "build_failed", tostring(buildErr)
  end

  local guideName = RXPBridge.BuildGoldFarmGuideName(farm)
  local rxp = _G.RXPGuides
  local ok, regResult = pcall(rxp.RegisterGuide, guideText)
  if not ok then
    RXPBridge.goldFarmsRegisteredByID[farm.farmID] = false
    if verbose then
      ns.Compat.Print("RXPGuides threw an error registering gold farm guide: " .. tostring(regResult))
    end
    return false, "error", tostring(regResult)
  end

  if regResult == false then
    RXPBridge.goldFarmsRegisteredByID[farm.farmID] = false
    if verbose then
      ns.Compat.Print("RXPGuides rejected the gold farm guide (RegisterGuide returned false).")
    end
    return false, "rejected", "register_guide_returned_false"
  end

  local foundInGuides = RXPBridge.IsGuideRegisteredInRXP(RXPBridge.GOLD_FARMS_GUIDE_GROUP, guideName)
  if rxp.addonLoaded == false and regResult == nil and not foundInGuides then
    RXPBridge.goldFarmsRegisteredByID[farm.farmID] = false
    if verbose then
      ns.Compat.Print("RXPGuides has not finished loading yet; gold farm registration was deferred.")
    end
    return false, "deferred", "rxp_not_loaded_deferred"
  end

  if regResult ~= true and not foundInGuides then
    RXPBridge.goldFarmsRegisteredByID[farm.farmID] = false
    if verbose then
      ns.Compat.Print("RXPGuides did not confirm acceptance of the gold farm guide.")
    end
    return false, "rejected", "guide_not_accepted"
  end

  RXPBridge.goldFarmsRegisteredByID[farm.farmID] = true
  local isSelected = RXPBridge.IsGoldFarmGuideSelected(farm.farmID, catalog)
  if verbose then
    if isSelected then
      ns.Compat.Print(
        string.format("Registered & detected active RXP selection: '%s' -> '%s'.", RXPBridge.GOLD_FARMS_GUIDE_GROUP, guideName)
      )
    else
      ns.Compat.Print(
        string.format(
          "Exported '%s' under farming group '%s' in RXPGuides (current RXP guide left unchanged).",
          guideName,
          RXPBridge.GOLD_FARMS_GUIDE_GROUP
        )
      )
    end
  end
  return true, isSelected and "selected" or "registered", guideText
end

function RXPBridge.RegisterAllGoldFarmGuides(verbose, catalog, trackKey)
  catalog = catalog or (ns.State and ns.State.GetCompiledGoldFarms and ns.State.GetCompiledGoldFarms())
  if type(catalog) ~= "table" or type(catalog.farms) ~= "table" then
    return false, "missing_catalog", 0
  end
  if not RXPBridge.IsAvailable() then
    if verbose then
      ns.Compat.Print("RXPGuides is not loaded; continuing with ForeverHub standalone navigation.")
    end
    return false, "unavailable", 0
  end

  local targetList = (trackKey == "arcane_lvl47_st" and type(catalog.arcaneGrindFarms) == "table" and #catalog.arcaneGrindFarms > 0)
    and catalog.arcaneGrindFarms
    or catalog.farms
  local trackDesc = (trackKey == "arcane_lvl47_st")
    and "Level 46-60 Arcane ST Mage Candidate"
    or "Level 40 Mage Gold Farm Candidate"

  local exported = 0
  local lastErr = nil
  for _, farm in ipairs(targetList) do
    local ok, status, detail = RXPBridge.RegisterGoldFarmGuide(farm.farmID, false, catalog)
    if ok then
      exported = exported + 1
    else
      lastErr = status or detail
    end
  end

  if exported == 0 then
    if verbose then
      ns.Compat.Print("Could not export gold farm guides to RXPGuides (" .. tostring(lastErr or "rejected") .. ").")
    end
    return false, tostring(lastErr or "rejected"), 0
  end

  if verbose then
    ns.Compat.Print(
      string.format(
        "Exported %d/%d verified %s guides under '%s' in RXPGuides (your active RXP guide was NOT changed).",
        exported,
        #targetList,
        trackDesc,
        RXPBridge.GOLD_FARMS_GUIDE_GROUP
      )
    )
  end
  return true, "registered", exported
end
