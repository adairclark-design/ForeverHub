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
-- v0.4.0 Riverglades Explicit RXP Guide Export & Verification (Astra P1-E)
-- ============================================================================

RXPBridge.RIVERGLADES_GUIDE_GROUP = "ForeverHub Routes"
RXPBridge.RIVERGLADES_GUIDE_NAME = "Riverglades: Farholde & Sunnyglade (Alliance)"
RXPBridge.rivergladesRegistered = false

function RXPBridge.BuildRivergladesGuideText(route)
  route = route or (ns.State and ns.State.GetCompiledRivergladesRoute())
  if type(route) ~= "table" or type(route.actions) ~= "table" then
    return nil, "missing_riverglades_route"
  end

  local RoutePlanner = ns.Domain and ns.Domain.RoutePlanner
  if not RoutePlanner then
    return nil, "missing_route_planner"
  end

  local function sanitizeRxpText(s)
    local txt = tostring(s or "")
    txt = string.gsub(txt, "%-%-", "—")
    txt = string.gsub(txt, ">>", "->")
    return txt
  end

  local function lookupRouteQuestMeta(act)
    if type(act) ~= "table" then
      return nil
    end
    if type(act.questID) == "number" and type(route.questsByID) == "table" then
      return route.questsByID[act.questID]
    end
    if type(act.questKey) == "string" and type(route.questsByTitleKey) == "table" then
      return route.questsByTitleKey[act.questKey]
    end
    return nil
  end

  local lines = {
    "#forever",
    "#disabledungeons",
    string.format("#version %d", tonumber(route.datasetRevision or route.revision) or 3),
    string.format("#group %s", RXPBridge.RIVERGLADES_GUIDE_GROUP),
    string.format("#name %s", RXPBridge.RIVERGLADES_GUIDE_NAME),
    string.format("#displayname %s", "Riverglades: Multi-Hub Alliance (Static Linear Snapshot)"),
    "",
    "step",
    "    >>ForeverHub Riverglades [STATIC LINEAR SNAPSHOT] — Dynamic hub/proximity routing, 40/40 Quest Log draining, and sub-objective pin retirement require ForeverHub Standalone ('/fh rg start'). Unverified steps are excluded by policy.",
  }

  local emittedSteps = 0
  for _, act in ipairs(route.actions) do
    local usable = RoutePlanner.IsUsableReviewStatus
      and RoutePlanner.IsUsableReviewStatus(act and act.reviewStatus)
      or (type(act) == "table" and act.reviewStatus == "verified")
    if type(act) == "table" and usable and act.isAtlasSideQuest ~= true then
      local destOk = RoutePlanner.ValidateActionDestination(act, route)
      if destOk then
        local isOptional = (act.isGroupBranch == true) or (act.isEliteBounty == true)
        local qMeta = lookupRouteQuestMeta(act)
        local resolvedQID = tonumber(act.questID)
        if not resolvedQID and type(act.questKey) == "string" and ns.Compat and ns.Compat.ResolveQuestIdentity then
          resolvedQID = tonumber((ns.Compat.ResolveQuestIdentity(act.questKey)))
        end
        local signedCompleteQID = resolvedQID and (isOptional and -math.abs(resolvedQID) or math.abs(resolvedQID)) or nil
        local objCount = math.max(0, tonumber(qMeta and qMeta.objectiveCount) or 1)
        if qMeta and qMeta.zeroObjectives == true then
          objCount = 0
        end

        local titleLine = sanitizeRxpText(act.title or act.actionID)
        local noteClean = (act.note and act.note ~= "") and sanitizeRxpText(act.note) or nil
        local fullLine = noteClean and string.format("%s — %s", titleLine, noteClean) or titleLine

        if act.kind == "objective" and type(act.subLocations) == "table" and #act.subLocations > 0 then
          local groups = {}
          local groupByKey = {}
          for sIdx, sl in ipairs(act.subLocations) do
            if type(sl) == "table" and type(sl.destination) == "table" then
              local ois = {}
              if type(sl.objectiveIndexes) == "table" and #sl.objectiveIndexes > 0 then
                for _, oi in ipairs(sl.objectiveIndexes) do
                  local n = tonumber(oi)
                  if n and n >= 1 then
                    table.insert(ois, math.floor(n))
                  end
                end
                table.sort(ois)
              end
              local gKey = (#ois > 0) and ("obj:" .. table.concat(ois, ",")) or ("spot:" .. tostring(sIdx))
              local grp = groupByKey[gKey]
              if not grp then
                grp = { key = gKey, objIndexes = ois, spots = {} }
                groupByKey[gKey] = grp
                table.insert(groups, grp)
              end
              table.insert(grp.spots, sl)
            end
          end

          for _, grp in ipairs(groups) do
            table.insert(lines, "step")
            if isOptional then
              table.insert(lines, "    #optional")
            end

            local spotLabels = {}
            local targetsSeen = {}
            local mobLines = {}
            local hasEstCoord = false
            for _, sl in ipairs(grp.spots) do
              local sdest = sl.destination
              if sdest.coordConfidence == "estimated" then
                hasEstCoord = true
              end
              local sxPct, syPct = RoutePlanner.NormalizedToPercent(sdest.x01, sdest.y01)
              if sxPct and syPct then
                local mapID = tonumber(sdest.uiMapID) or 2548
                if #grp.spots > 1 then
                  table.insert(lines, string.format("    .goto %d,%.2f,%.2f,40,0", mapID, sxPct, syPct))
                else
                  table.insert(lines, string.format("    .goto %d,%.2f,%.2f", mapID, sxPct, syPct))
                end
              end
              if sl.label and sl.label ~= "" then
                table.insert(spotLabels, sanitizeRxpText(sl.label))
              end
              local tName = sl.targetName and sanitizeRxpText(sl.targetName) or nil
              local tID = tonumber(sl.targetNpcID)
              if tName and tName ~= "" then
                local mSpec = tID and string.format("%s::%d", tName, tID) or tName
                if not targetsSeen[mSpec] then
                  targetsSeen[mSpec] = true
                  table.insert(mobLines, mSpec)
                end
              end
            end

            local subSummary = (#spotLabels > 0) and table.concat(spotLabels, " / ") or titleLine
            local estTag = hasEstCoord and " [Est. Coords]" or ""
            table.insert(lines, string.format("    >>%s — %s%s", titleLine, subSummary, estTag))

            for _, mSpec in ipairs(mobLines) do
              table.insert(lines, string.format("    .mob %s", mSpec))
            end

            if signedCompleteQID and #grp.objIndexes > 0 and objCount > 0 then
              for _, oi in ipairs(grp.objIndexes) do
                table.insert(lines, string.format("    .complete %d,%d --%s", signedCompleteQID, oi, subSummary))
              end
            elseif signedCompleteQID and objCount > 0 then
              for oi = 1, objCount do
                table.insert(lines, string.format("    .complete %d,%d --%s", signedCompleteQID, oi, subSummary))
              end
            else
              table.insert(
                lines,
                string.format("    +%s (manual checkbox — custom quest ID not yet discovered)", subSummary)
              )
            end
            emittedSteps = emittedSteps + 1
          end
        else
          table.insert(lines, "step")
          if isOptional then
            table.insert(lines, "    #optional")
          end

          local estTag = (act.destination and act.destination.coordConfidence == "estimated") and " [Est. Coords]" or ""
          if act.destination then
            local xPct, yPct = RoutePlanner.NormalizedToPercent(act.destination.x01, act.destination.y01)
            if xPct and yPct then
              local mapID = tonumber(act.destination.uiMapID) or 2548
              if act.kind == "travel" then
                local rad = math.max(10, math.floor(tonumber(act.arrivalRadiusYards) or 25))
                table.insert(lines, string.format("    .goto %d,%.2f,%.2f,%d >>%s%s", mapID, xPct, yPct, rad, fullLine, estTag))
              else
                table.insert(lines, string.format("    .goto %d,%.2f,%.2f", mapID, xPct, yPct))
                table.insert(lines, string.format("    >>%s%s", fullLine, estTag))
              end
            end
          else
            table.insert(lines, string.format("    >>%s%s", fullLine, estTag))
          end

          if act.npcName and act.npcID then
            local directive = (act.kind == "objective") and ".mob" or ".target"
            table.insert(lines, string.format("    %s %s::%d", directive, sanitizeRxpText(act.npcName), tonumber(act.npcID)))
          elseif act.npcName and act.npcName ~= "" and act.kind == "objective" then
            table.insert(lines, string.format("    .mob %s", sanitizeRxpText(act.npcName)))
          end

          if act.kind == "accept" then
            if resolvedQID then
              table.insert(lines, string.format("    .accept %d >>%s", resolvedQID, titleLine))
            else
              table.insert(
                lines,
                string.format(
                  "    +%s (manual checkbox — custom quest ID not yet discovered; tick to skip if completed pre-install)",
                  titleLine
                )
              )
            end
          elseif act.kind == "objective" then
            if signedCompleteQID and objCount > 0 then
              for oi = 1, objCount do
                table.insert(lines, string.format("    .complete %d,%d --%s", signedCompleteQID, oi, titleLine))
              end
            else
              table.insert(
                lines,
                string.format("    +%s (manual checkbox — complete objective in Quest Log)", titleLine)
              )
            end
          elseif act.kind == "turnin" then
            if resolvedQID then
              table.insert(lines, string.format("    .turnin %d >>%s", resolvedQID, titleLine))
            else
              table.insert(
                lines,
                string.format("    +%s (manual checkbox — turn in quest)", titleLine)
              )
            end
          end

          emittedSteps = emittedSteps + 1
        end
      end
    end
  end

  if emittedSteps == 0 then
    return nil, "no_verified_steps_to_export"
  end

  return table.concat(lines, "\n"), nil
end

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

-- Checks ONLY live `_G.RXPGuides.currentGuide` — never stale `_G.RXPCData` (Astra P2 & Gate 9).
function RXPBridge.IsRivergladesGuideSelected()
  local rxp = _G.RXPGuides
  if type(rxp) == "table" and type(rxp.currentGuide) == "table" then
    if rxp.currentGuide.group == RXPBridge.RIVERGLADES_GUIDE_GROUP
      and rxp.currentGuide.name == RXPBridge.RIVERGLADES_GUIDE_NAME
    then
      return true
    end
  end
  return false
end

-- Registers the reviewed Riverglades guide in RXPGuides WITHOUT auto-selecting or hijacking
-- an unrelated active RXP guide, and verifies registration outcome beyond `pcall`!
function RXPBridge.RegisterRivergladesGuide(verbose, route)
  if not RXPBridge.IsAvailable() then
    if verbose then
      ns.Compat.Print("RXPGuides is not loaded; continuing with ForeverHub standalone navigation.")
    end
    return false, "unavailable", "RXPGuides unavailable"
  end

  local guideText, buildErr = RXPBridge.BuildRivergladesGuideText(route)
  if not guideText then
    if verbose then
      ns.Compat.Print("Cannot export Riverglades RXP guide: " .. tostring(buildErr))
    end
    return false, "build_failed", tostring(buildErr)
  end

  local rxp = _G.RXPGuides
  local ok, regResult = pcall(rxp.RegisterGuide, guideText)
  if not ok then
    RXPBridge.rivergladesRegistered = false
    if verbose then
      ns.Compat.Print("RXPGuides threw an error during registration: " .. tostring(regResult))
    end
    return false, "error", tostring(regResult)
  end

  -- Astra P1-E: `pcall succeeded ~= guide accepted`!
  -- In RXP GuideLoader.lua:531, `RegisterGuide` returns `false` on parse/compatibility rejection
  -- without raising a Lua error, or `nil` when deferred before RXP addonLoaded.
  if regResult == false then
    RXPBridge.rivergladesRegistered = false
    if verbose then
      ns.Compat.Print("RXPGuides rejected the Riverglades guide (RegisterGuide returned false).")
    end
    return false, "rejected", "register_guide_returned_false"
  end

  local foundInGuides = RXPBridge.IsGuideRegisteredInRXP(
    RXPBridge.RIVERGLADES_GUIDE_GROUP,
    RXPBridge.RIVERGLADES_GUIDE_NAME
  )

  if rxp.addonLoaded == false and regResult == nil and not foundInGuides then
    RXPBridge.rivergladesRegistered = false
    if verbose then
      ns.Compat.Print("RXPGuides has not finished loading yet; guide registration was deferred (not yet active).")
    end
    return false, "deferred", "rxp_not_loaded_deferred"
  end

  if regResult ~= true and not foundInGuides then
    RXPBridge.rivergladesRegistered = false
    if verbose then
      ns.Compat.Print("RXPGuides did not confirm acceptance of the Riverglades guide.")
    end
    return false, "rejected", "guide_not_accepted"
  end

  RXPBridge.rivergladesRegistered = true
  local isSelected = RXPBridge.IsRivergladesGuideSelected()
  if verbose then
    if isSelected then
      ns.Compat.Print(
        string.format(
          "Registered & detected active selection: '%s' -> '%s' [Static Linear Snapshot — RXP owns step progression; use '/fh rg start' after deselecting in RXP for live dynamic hub/40-slot routing].",
          RXPBridge.RIVERGLADES_GUIDE_GROUP,
          RXPBridge.RIVERGLADES_GUIDE_NAME
        )
      )
    else
      ns.Compat.Print(
        string.format(
          "Exported static linear snapshot '%s' under '%s' in RXPGuides (current RXP guide left unchanged; ForeverHub Standalone '/fh rg start' remains recommended for dynamic proximity & 40/40 log routing).",
          RXPBridge.RIVERGLADES_GUIDE_NAME,
          RXPBridge.RIVERGLADES_GUIDE_GROUP
        )
      )
    end
  end
  return true, isSelected and "selected" or "registered", guideText
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
  local rev = math.max(2, tonumber(catalog and catalog.meta and catalog.meta.revision) or 2)

  local lines = {
    "#forever",
    string.format("#version %d", rev),
    string.format("#group %s", RXPBridge.GOLD_FARMS_GUIDE_GROUP),
    string.format("#name %s", guideName),
    string.format("#displayname %s", displayName),
    "",
    "step",
    string.format(
      "    >>%s (%s, Lv %s) — Community Est.: %d-%dg/hr (Unverified Reference; measure character cash flow via Net Purse Change / Active Hr in /fh gold).",
      tostring(farm.title),
      tostring(farm.zoneName),
      tostring(farm.recommendedLevelRange or "40"),
      tonumber(gphMeta.lowGold) or 0,
      tonumber(gphMeta.highGold) or 0
    ),
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
  if farmID and catalog and catalog.farmsByID and catalog.farmsByID[farmID] then
    expectedName = RXPBridge.BuildGoldFarmGuideName(catalog.farmsByID[farmID])
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

function RXPBridge.RegisterAllGoldFarmGuides(verbose, catalog)
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

  local exported = 0
  local lastErr = nil
  for _, farm in ipairs(catalog.farms) do
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
        "Exported %d/%d verified Level 40 Mage Gold Farm Candidate guides under '%s' in RXPGuides (your active RXP guide was NOT changed).",
        exported,
        #catalog.farms,
        RXPBridge.GOLD_FARMS_GUIDE_GROUP
      )
    )
  end
  return true, "registered", exported
end
