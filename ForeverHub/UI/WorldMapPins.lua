local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.UI = ns.UI or {}

local WorldMapPins = {}
ns.UI.WorldMapPins = WorldMapPins

WorldMapPins.pinPool = {}
WorldMapPins.activePinCount = 0
WorldMapPins.lastClusters = {}
WorldMapPins.lastEntries = {}
WorldMapPins.lastSummaryCounts = { objectives = 0, turnins = 0, available = 0, total = 0 }
WorldMapPins.filterBar = nil
WorldMapPins.updaterFrame = nil
WorldMapPins.hookedMapFrame = nil
WorldMapPins.dirty = true
WorldMapPins.lastLayoutKey = nil
WorldMapPins.hoveredPin = nil
WorldMapPins.clusterCycleIndex = {}

local RIVERGLADES_MAP_ID = 2548
-- Clustering distance in zoomed WorldMap canvas UI units (`canvasWidth * canvasScale`).
local DEFAULT_CLUSTER_RADIUS_UI_UNITS = 22
local PIN_FRAME_LEVEL_OFFSET = 2550
local PIN_TARGET_LEVEL_OFFSET = 2620

local atlasSupportCache = {}

local function hasAtlasCompat(atlasName)
  if type(atlasName) ~= "string" or atlasName == "" then
    return false
  end
  if atlasSupportCache[atlasName] ~= nil then
    return atlasSupportCache[atlasName]
  end
  local ok = false
  if C_Texture and type(C_Texture.GetAtlasInfo) == "function" then
    local callOk, info = pcall(C_Texture.GetAtlasInfo, atlasName)
    ok = (callOk and type(info) == "table")
  end
  atlasSupportCache[atlasName] = ok
  return ok
end

local function applyAtlasOrTexture(tex, atlasCandidates, fallbackPath, cropInset)
  if not tex then
    return false
  end
  if type(atlasCandidates) == "table" and type(tex.SetAtlas) == "function" then
    for _, cand in ipairs(atlasCandidates) do
      if hasAtlasCompat(cand) then
        local ok = pcall(tex.SetAtlas, tex, cand, false)
        if ok then
          if type(tex.SetTexCoord) == "function" then
            tex:SetTexCoord(0, 1, 0, 1)
          end
          tex:Show()
          return true, cand
        end
      end
    end
  end
  if type(fallbackPath) == "string" and fallbackPath ~= "" and type(tex.SetTexture) == "function" then
    tex:SetTexture(fallbackPath)
    if type(tex.SetTexCoord) == "function" then
      local c = tonumber(cropInset) or 0
      tex:SetTexCoord(c, 1 - c, c, 1 - c)
    end
    tex:Show()
    return true, fallbackPath
  end
  if type(tex.Hide) == "function" then
    tex:Hide()
  end
  return false, nil
end

local function lookupQuestMeta(route, act)
  if type(route) ~= "table" or type(act) ~= "table" then
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

local function classifyObjectiveStyle(act, qMeta, spotLabel)
  if act.isEliteBounty == true or (qMeta and (qMeta.isEliteBounty == true or qMeta.isElite == true)) then
    return "elite"
  end
  if act.isSupplyObjective == true or (qMeta and qMeta.supplyItemID ~= nil) then
    return "supply"
  end
  local combined = string.lower(
    tostring(spotLabel or "") .. " " .. tostring(act.title or "") .. " " .. tostring(act.note or "")
  )
  if string.find(combined, "slay", 1, true)
    or string.find(combined, "slain", 1, true)
    or string.find(combined, "kill", 1, true)
    or string.find(combined, "hunt", 1, true)
    or string.find(combined, "defeat", 1, true)
    or string.find(combined, "clear ", 1, true)
    or string.find(combined, "cull ", 1, true)
  then
    return "slay"
  end
  return "loot"
end

local function isFiniteNum(v)
  if ns.Compat and type(ns.Compat.IsFiniteNumber) == "function" then
    return ns.Compat.IsFiniteNumber(v)
  end
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function isValidMapRect(minX, maxX, minY, maxY)
  if not (isFiniteNum(minX) and isFiniteNum(maxX) and isFiniteNum(minY) and isFiniteNum(maxY)) then
    return false
  end
  return maxX > minX and maxY > minY
end

-- Projects `(sourceMapID, x01, y01)` onto `targetMapID` when viewing a parent continent or stitched map.
function WorldMapPins.ProjectCoordinates(sourceMapID, targetMapID, x01, y01)
  local srcID = tonumber(sourceMapID)
  local dstID = tonumber(targetMapID)
  local px = tonumber(x01)
  local py = tonumber(y01)
  if not srcID or not dstID or not isFiniteNum(px) or not isFiniteNum(py) then
    return nil, nil
  end
  if px < 0 or px > 1 or py < 0 or py > 1 then
    return nil, nil
  end
  if srcID == dstID then
    return px, py
  end
  if not (C_Map and type(C_Map.GetMapRectOnMap) == "function") then
    return nil, nil
  end

  local curMap = srcID
  local curX, curY = px, py
  local visited = {}
  for _ = 1, 4 do
    if curMap == dstID then
      if isFiniteNum(curX) and isFiniteNum(curY) and curX >= 0 and curX <= 1 and curY >= 0 and curY <= 1 then
        return curX, curY
      end
      return nil, nil
    end
    if visited[curMap] then
      return nil, nil
    end
    visited[curMap] = true

    local okDirect, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, curMap, dstID)
    if okDirect and isValidMapRect(minX, maxX, minY, maxY) then
      local outX = minX + curX * (maxX - minX)
      local outY = minY + curY * (maxY - minY)
      if isFiniteNum(outX) and isFiniteNum(outY) and outX >= 0 and outX <= 1 and outY >= 0 and outY <= 1 then
        return outX, outY
      end
      return nil, nil
    end

    if type(C_Map.GetMapInfo) ~= "function" then
      return nil, nil
    end
    local okInfo, info = pcall(C_Map.GetMapInfo, curMap)
    local parentID = okInfo and type(info) == "table" and tonumber(info.parentMapID) or nil
    if not parentID or parentID <= 0 then
      return nil, nil
    end
    local okStep, pMinX, pMaxX, pMinY, pMaxY = pcall(C_Map.GetMapRectOnMap, curMap, parentID)
    if not (okStep and isValidMapRect(pMinX, pMaxX, pMinY, pMaxY)) then
      return nil, nil
    end
    curX = pMinX + curX * (pMaxX - pMinX)
    curY = pMinY + curY * (pMaxY - pMinY)
    curMap = parentID
  end
  return nil, nil
end

-- Pure data collector: builds all currently relevant quest markers for `targetMapID`.
-- Never emits completed quests, ineligible steps, locked follow-ups, or intro travel checks.
function WorldMapPins.CollectPinEntries(targetMapID, route, progress, settings, ctx, playerPos)
  local dstMapID = tonumber(targetMapID)
  local emptySummary = { objectives = 0, turnins = 0, available = 0, total = 0 }
  if not dstMapID then
    return {}, emptySummary
  end

  local RoutePlanner = ns.Domain and ns.Domain.RoutePlanner
  if not RoutePlanner then
    return {}, emptySummary
  end

  route = route or (ns.State and ns.State.GetCompiledRivergladesRoute and ns.State.GetCompiledRivergladesRoute())
  progress = progress or (ns.State and ns.State.GetRouteProgress and ns.State.GetRouteProgress())
  settings = settings or (ns.State and ns.State.GetWorldMapPinSettings and ns.State.GetWorldMapPinSettings()) or {
    enabled = true,
    showObjectives = true,
    showTurnIns = true,
    showAvailable = true,
  }
  if type(route) ~= "table" then
    return {}, emptySummary
  end

  ctx = ctx or RoutePlanner.BuildDefaultContext()
  playerPos = playerPos or (ns.Compat and ns.Compat.GetPlayerPosition01 and ns.Compat.GetPlayerPosition01()) or nil
  local eval = RoutePlanner.EvaluateRoute(route, progress, ctx, playerPos)
  if not eval or not eval.valid then
    return {}, emptySummary
  end

  local activeActionID = nil
  local activeSubID = nil
  if progress and progress.mode == "standalone" and eval.nextAction then
    activeActionID = eval.nextAction.actionID
    if RoutePlanner.ResolveActiveActionTarget then
      local _, _, sub = RoutePlanner.ResolveActiveActionTarget(eval.nextAction, progress, ctx, playerPos)
      activeSubID = sub and sub.subID or activeActionID
    else
      activeSubID = activeActionID
    end
  end

  local entries = {}
  local seenKeys = {}
  local rawCounts = {
    objectives = 0,
    turnins = 0,
    available = 0,
    total = 0,
    unresolvedTitlePickups = tonumber(eval.counts and eval.counts.blockedUnresolvedHistory) or 0,
  }

  for _, ev in ipairs(eval.evaluations or {}) do
    local act = ev.action
    local kind = act and act.kind
    if act and (kind == "turnin" or kind == "objective" or kind == "accept") then
      local include = false
      local isQuestLogFull = false
      local isSkipped = false

      if ev.state == "available" then
        include = true
      elseif kind == "accept" and ev.state == "blocked_quest_log_full" then
        include = true
        isQuestLogFull = true
      elseif (kind == "objective" or kind == "turnin") and ev.state == "skipped" then
        -- Still show active incomplete Quest Log objectives / ready turn-ins on the map even if skipped in HUD!
        local eligOk = RoutePlanner.EvaluateEligibility(act, progress, ctx, route) == true
        local reqOk = RoutePlanner.EvaluatePredicate(act.requires, progress, ctx, route) == true
        if eligOk and reqOk then
          include = true
          isSkipped = true
        end
      end

      if include then
        local qMeta = lookupQuestMeta(route, act)
        local questIdentity = tostring(act.questKey or act.questID or act.actionID)
        local questTitle = (qMeta and (qMeta.name or qMeta.title)) or act.title or questIdentity
        local questLevel = qMeta and tonumber(qMeta.questLevel) or nil
        local isElite = (act.isEliteBounty == true)
          or (qMeta and (qMeta.isEliteBounty == true or qMeta.isElite == true))
          or false
        local qref = (type(act.questKey) == "string" and act.questKey ~= "" and act.questKey) or act.questID

        local bankHint = nil
        if qMeta and qMeta.supplyItemID and ns.State and ns.State.GetBankItemCount then
          local bankQty = ns.State.GetBankItemCount(qMeta.supplyItemID)
          if bankQty and bankQty > 0 then
            bankHint = string.format("(%d in bank!)", bankQty)
          end
        end

        local overallProgressText = nil
        if kind == "objective" and qref and ctx and type(ctx.getQuestObjectives) == "function" then
          local objRes = ctx.getQuestObjectives(qref)
          if type(objRes) == "table" and objRes.status == "ok" and type(objRes.summaryText) == "string" and objRes.summaryText ~= "" then
            overallProgressText = objRes.summaryText
          end
        end

        local spots = nil
        if kind == "objective" and type(act.subLocations) == "table" and #act.subLocations > 0 and RoutePlanner.ResolveActiveSubLocations then
          spots = RoutePlanner.ResolveActiveSubLocations(act, ctx)
        elseif type(act.destination) == "table" then
          local resolvedDest, resolvedName = act.destination, act.npcName
          if (kind == "turnin" or kind == "objective") and RoutePlanner.ResolveActiveActionTarget then
            local rd, rn = RoutePlanner.ResolveActiveActionTarget(act, progress, ctx, nil, route)
            if type(rd) == "table" then
              resolvedDest = rd
            end
            if type(rn) == "string" and rn ~= "" then
              resolvedName = rn
            end
          end
          spots = {
            {
              subID = act.actionID,
              label = act.title,
              targetName = resolvedName,
              destination = resolvedDest,
              isPrimary = true,
            },
          }
        end

        for _, spot in ipairs(spots or {}) do
          local sdest = spot.destination
          if type(sdest) == "table" then
            local projX, projY = WorldMapPins.ProjectCoordinates(sdest.uiMapID, dstMapID, sdest.x01, sdest.y01)
            if projX and projY then
              local subKey = tostring(spot.subID or act.actionID)
              local dedupeKey = kind .. "|" .. questIdentity .. "|" .. subKey
              if not seenKeys[dedupeKey] then
                seenKeys[dedupeKey] = true

                if kind == "objective" then
                  rawCounts.objectives = rawCounts.objectives + 1
                elseif kind == "turnin" then
                  rawCounts.turnins = rawCounts.turnins + 1
                elseif kind == "accept" then
                  rawCounts.available = rawCounts.available + 1
                end
                rawCounts.total = rawCounts.total + 1

                local passFilter = (settings.enabled ~= false) and (
                  (kind == "objective" and settings.showObjectives ~= false)
                  or (kind == "turnin" and settings.showTurnIns ~= false)
                  or (kind == "accept" and settings.showAvailable ~= false)
                )

                if passFilter then
                  local isCurrentTarget = (activeActionID ~= nil and act.actionID == activeActionID)
                    and (activeSubID == nil or activeSubID == subKey or spot.isPrimary == true)
                  local isPinned = (progress ~= nil and progress.pinnedActionID == act.actionID)
                    and (progress.pinnedSubLocationID == nil or progress.pinnedSubLocationID == subKey)

                  local basePriority = (kind == "turnin" and 30) or (kind == "objective" and 20) or 10
                  if isCurrentTarget then
                    basePriority = 45
                  elseif isPinned then
                    basePriority = basePriority + 5
                  end

                  local progLine = spot.progressText or overallProgressText
                  if bankHint then
                    progLine = progLine and (progLine .. " " .. bankHint) or bankHint
                  end

                  table.insert(entries, {
                    actionID = act.actionID,
                    subID = (not spot.isPrimary) and spot.subID or nil,
                    kind = kind,
                    questIdentity = questIdentity,
                    questID = act.questID,
                    questKey = act.questKey,
                    questTitle = questTitle,
                    questLevel = questLevel,
                    actionTitle = act.title,
                    spotLabel = (not spot.isPrimary) and spot.label or nil,
                    targetName = spot.targetName or act.npcName,
                    progressText = progLine,
                    note = act.note,
                    isElite = isElite,
                    isSupply = (act.isSupplyObjective == true),
                    objectiveStyle = (kind == "objective") and classifyObjectiveStyle(act, qMeta, spot.label) or nil,
                    questLogFull = isQuestLogFull,
                    isSkipped = isSkipped,
                    isCurrentTarget = isCurrentTarget,
                    isPinned = isPinned,
                    reviewStatus = act.reviewStatus,
                    coordConfidence = sdest.coordConfidence or "artifact_verified",
                    sourceMapID = tonumber(sdest.uiMapID),
                    sourceX01 = tonumber(sdest.x01),
                    sourceY01 = tonumber(sdest.y01),
                    x01 = projX,
                    y01 = projY,
                    priority = basePriority,
                    orderIndex = tonumber(ev.orderIndex) or 9999,
                  })
                end
              end
            end
          end
        end
      end
    end
  end

  return entries, rawCounts
end

-- Groups nearby pins in zoomed canvas UI-unit space (`canvasWidth * canvasScale`, `canvasHeight * canvasScale`)
-- so dense hubs stay readable when zoomed out and smoothly separate into individual pins on zoom-in.
function WorldMapPins.BuildClusters(entries, canvasWidth, canvasHeight, canvasScale, radiusUiUnits)
  if type(entries) ~= "table" or #entries == 0 then
    return {}
  end

  local sorted = {}
  for i, e in ipairs(entries) do
    sorted[i] = e
  end
  table.sort(sorted, function(a, b)
    if a.priority ~= b.priority then
      return a.priority > b.priority
    end
    return (a.orderIndex or 9999) < (b.orderIndex or 9999)
  end)

  local effW = math.max(1, (tonumber(canvasWidth) or 1002) * math.max(0.1, tonumber(canvasScale) or 1.0))
  local effH = math.max(1, (tonumber(canvasHeight) or 668) * math.max(0.1, tonumber(canvasScale) or 1.0))
  local limit = tonumber(radiusUiUnits) or DEFAULT_CLUSTER_RADIUS_UI_UNITS
  local limitSq = limit * limit

  local clusters = {}
  for _, entry in ipairs(sorted) do
    local matchedCluster = nil
    local bestDistSq = limitSq
    for _, cl in ipairs(clusters) do
      local dx = (entry.x01 - cl.x01) * effW
      local dy = (entry.y01 - cl.y01) * effH
      local dSq = dx * dx + dy * dy
      if dSq <= bestDistSq then
        matchedCluster = cl
        bestDistSq = dSq
      end
    end

    if matchedCluster then
      table.insert(matchedCluster.entries, entry)
      matchedCluster.count = #matchedCluster.entries
      if entry.isCurrentTarget then
        matchedCluster.hasCurrentTarget = true
      end
      if entry.kind == "turnin" then
        matchedCluster.hasTurnIn = true
      elseif entry.kind == "objective" then
        matchedCluster.hasObjective = true
      elseif entry.kind == "accept" then
        matchedCluster.hasAvailable = true
      end
      if entry.isElite then
        matchedCluster.hasElite = true
      end
    else
      local key = string.format("%.3f|%.3f", entry.x01, entry.y01)
      table.insert(clusters, {
        clusterKey = key,
        x01 = entry.x01,
        y01 = entry.y01,
        primary = entry,
        entries = { entry },
        count = 1,
        hasCurrentTarget = (entry.isCurrentTarget == true),
        hasTurnIn = (entry.kind == "turnin"),
        hasObjective = (entry.kind == "objective"),
        hasAvailable = (entry.kind == "accept"),
        hasElite = (entry.isElite == true),
      })
    end
  end

  return clusters
end

local function getWorldMapFrame()
  return _G.WorldMapFrame
end

local function getWorldMapCanvas(mapFrame)
  if type(mapFrame) ~= "table" then
    return nil
  end
  if type(mapFrame.GetCanvas) == "function" then
    local ok, canvas = pcall(mapFrame.GetCanvas, mapFrame)
    if ok and type(canvas) == "table" then
      return canvas
    end
  end
  local sc = mapFrame.ScrollContainer
  if type(sc) == "table" then
    return sc.Child or sc
  end
  return nil
end

local function getViewedMapID(mapFrame)
  if type(mapFrame) ~= "table" or type(mapFrame.GetMapID) ~= "function" then
    return nil
  end
  local ok, mapID = pcall(mapFrame.GetMapID, mapFrame)
  if ok and type(mapID) == "number" and mapID > 0 then
    return mapID
  end
  return nil
end

local function formatEntryLevelPrefix(entry)
  if not entry.questLevel then
    return ""
  end
  if entry.isElite then
    return string.format("[%d+] ", entry.questLevel)
  end
  return string.format("[%d] ", entry.questLevel)
end

local function safeTipAddDoubleLine(tip, leftText, rightText, lr, lg, lb, rr, rg, rb)
  if type(tip.AddDoubleLine) == "function" then
    tip:AddDoubleLine(leftText, rightText, lr, lg, lb, rr, rg, rb)
  elseif type(tip.AddLine) == "function" then
    tip:AddLine(tostring(leftText or "") .. "  " .. tostring(rightText or ""), lr or 1, lg or 1, lb or 1, true)
  end
end

local function formatKindTag(entry)
  local Theme = ns.UI and ns.UI.Theme
  local function col(tok, txt)
    if Theme and Theme.Colorize then
      return Theme.Colorize(tok, txt)
    end
    return txt
  end
  if entry.kind == "turnin" then
    return col("status.ready", "Turn-in (?)")
  elseif entry.kind == "objective" then
    if entry.isElite then
      return col("status.warning", "Elite Objective")
    elseif entry.isSupply then
      return col("status.bank", "Supply Objective")
    end
    return col("text.secondary", "Objective")
  else
    if entry.questLogFull then
      return col("status.warning", "Available (!) · Log 40/40")
    end
    return col("accent.gold", "Available (!)")
  end
end

local function showPinTooltip(pin)
  local cluster = pin and pin.cluster
  if not cluster or type(_G.GameTooltip) ~= "table" then
    return
  end
  local Theme = ns.UI and ns.UI.Theme
  local function unpackCol(tok, dr, dg, db)
    if Theme and Theme.UnpackRGBA then
      local r, g, b = Theme.UnpackRGBA(tok)
      return r, g, b
    end
    return dr, dg, db
  end
  local function col(tok, txt)
    if Theme and Theme.Colorize then
      return Theme.Colorize(tok, txt)
    end
    return txt
  end

  local tip = _G.GameTooltip
  if type(tip.SetOwner) == "function" then
    tip:SetOwner(pin, "ANCHOR_RIGHT")
  end
  if type(tip.ClearLines) == "function" then
    tip:ClearLines()
  end

  local goldR, goldG, goldB = unpackCol("accent.gold", 0.85, 0.71, 0.42)
  local priR, priG, priB = unpackCol("text.primary", 0.93, 0.91, 0.86)
  local secR, secG, secB = unpackCol("text.secondary", 0.74, 0.77, 0.80)
  local mutR, mutG, mutB = unpackCol("text.muted", 0.57, 0.62, 0.66)
  local rdyR, rdyG, rdyB = unpackCol("status.ready", 0.49, 0.83, 0.64)
  local wrnR, wrnG, wrnB = unpackCol("status.warning", 0.95, 0.77, 0.38)

  local primary = cluster.primary
  local xPct, yPct = ns.Domain.RoutePlanner.NormalizedToPercent(primary.sourceX01, primary.sourceY01)

  if cluster.count == 1 then
    local titleStr = formatEntryLevelPrefix(primary) .. tostring(primary.questTitle)
    if type(tip.SetText) == "function" then
      tip:SetText(titleStr, goldR, goldG, goldB)
    elseif type(tip.AddLine) == "function" then
      tip:AddLine(titleStr, goldR, goldG, goldB)
    end
    local statusLine = formatKindTag(primary)
    if primary.isCurrentTarget then
      statusLine = statusLine .. "  " .. col("accent.gold", "· Current target")
    elseif primary.isPinned then
      statusLine = statusLine .. "  " .. col("status.reserved", "· Pinned")
    elseif primary.isSkipped then
      statusLine = statusLine .. "  " .. col("text.muted", "· Skipped in tracker")
    end
    local coordText = string.format(
      "(%.1f, %.1f)%s",
      xPct or 0,
      yPct or 0,
      (primary.coordConfidence == "estimated") and " · Est." or ""
    )
    safeTipAddDoubleLine(tip, statusLine, coordText, secR, secG, secB, mutR, mutG, mutB)

    if type(tip.AddLine) == "function" then
      if primary.spotLabel and primary.spotLabel ~= primary.questTitle then
        tip:AddLine(tostring(primary.spotLabel), priR, priG, priB)
      elseif primary.targetName and primary.targetName ~= "" then
        tip:AddLine(tostring(primary.targetName), secR, secG, secB)
      end
      if primary.progressText and primary.progressText ~= "" then
        tip:AddLine(tostring(primary.progressText), rdyR, rdyG, rdyB, true)
      end
    end
  else
    local header = string.format(
      "ForeverHub · %d Quests Here (%.1f, %.1f)",
      cluster.count,
      xPct or 0,
      yPct or 0
    )
    if type(tip.SetText) == "function" then
      tip:SetText(header, goldR, goldG, goldB)
    elseif type(tip.AddLine) == "function" then
      tip:AddLine(header, goldR, goldG, goldB)
    end
    if type(tip.AddLine) == "function" then
      for idx, e in ipairs(cluster.entries) do
        if idx <= 10 then
          local bullet = e.isCurrentTarget and col("accent.gold", "› ") or "· "
          local leftPart = string.format(
            "%s%s%s",
            bullet,
            formatEntryLevelPrefix(e),
            tostring(e.questTitle)
          )
          safeTipAddDoubleLine(tip, leftPart, formatKindTag(e), priR, priG, priB, secR, secG, secB)
          local detailParts = {}
          if e.spotLabel and e.spotLabel ~= e.questTitle then
            table.insert(detailParts, tostring(e.spotLabel))
          elseif e.targetName and e.targetName ~= "" then
            table.insert(detailParts, tostring(e.targetName))
          end
          if e.progressText and e.progressText ~= "" then
            table.insert(detailParts, tostring(e.progressText))
          end
          if e.coordConfidence == "estimated" then
            table.insert(detailParts, "Est. coords")
          end
          if #detailParts > 0 then
            tip:AddLine("   " .. table.concat(detailParts, " · "), secR, secG, secB, true)
          end
        end
      end
      if cluster.count > 10 then
        tip:AddLine(string.format("   +%d more (zoom in to separate)", cluster.count - 10), mutR, mutG, mutB)
      end
    end
  end

  if type(tip.AddLine) == "function" then
    local prog = ns.State and ns.State.GetRouteProgress and ns.State.GetRouteProgress()
    local rxpOwnsNav = (prog and prog.mode == "rxp")
      or (
        ns.Bridges
        and ns.Bridges.RXPBridge
        and ns.Bridges.RXPBridge.IsRivergladesGuideSelected
        and ns.Bridges.RXPBridge.IsRivergladesGuideSelected()
      )
    tip:AddLine(" ", 1, 1, 1)
    if rxpOwnsNav then
      tip:AddLine("Left-Click: Save ForeverHub focus (RXP controls active arrow)", wrnR, wrnG, wrnB)
    elseif cluster.count > 1 then
      tip:AddLine("Left-Click: Focus or cycle quests here", mutR, mutG, mutB)
    else
      tip:AddLine("Left-Click: Navigate here", mutR, mutG, mutB)
    end
    if prog and prog.pinnedActionID then
      tip:AddLine("Right-Click: Clear manual pin", mutR, mutG, mutB)
    end
  end

  if type(tip.Show) == "function" then
    tip:Show()
  end
end

function WorldMapPins.HandleClusterClick(cluster, mouseButton)
  if type(cluster) ~= "table" or type(cluster.entries) ~= "table" or #cluster.entries == 0 then
    return false
  end

  if mouseButton == "RightButton" then
    local prog = ns.State and ns.State.GetRouteProgress and ns.State.GetRouteProgress()
    if prog and prog.pinnedActionID and ns.Domain and ns.Domain.RouteProgress then
      local ok, eval = ns.Domain.RouteProgress.ClearPinnedFocus(nil, prog)
      if ok and prog.mode ~= "paused" and ns.UI and ns.UI.Navigation then
        ns.UI.Navigation.SyncFromEvaluation(eval, prog)
      end
      ns.Compat.Print("Cleared manual map focus — resumed automatic Riverglades routing.")
      WorldMapPins.RefreshNow()
      return true
    end
    return false
  end

  local idx = 1
  if #cluster.entries > 1 then
    local prevIdx = tonumber(WorldMapPins.clusterCycleIndex[cluster.clusterKey]) or 0
    idx = (prevIdx % #cluster.entries) + 1
    WorldMapPins.clusterCycleIndex[cluster.clusterKey] = idx
  end
  local chosen = cluster.entries[idx] or cluster.primary
  if not chosen then
    return false
  end

  if chosen.kind == "accept" and chosen.questLogFull then
    ns.Compat.Print(
      string.format(
        "Quest Log is full (40/40) — turn in a completed quest before accepting '%s'.",
        tostring(chosen.questTitle)
      )
    )
    return false
  end

  if ns.Domain and ns.Domain.RouteProgress and ns.Domain.RouteProgress.FocusActionFromMapPin then
    local ok, evalOrErr = ns.Domain.RouteProgress.FocusActionFromMapPin(chosen.actionID, chosen.subID)
    if ok then
      local prog = ns.State.GetRouteProgress()
      local navSt = nil
      if ns.UI and ns.UI.Navigation then
        navSt = ns.UI.Navigation.SyncFromEvaluation(evalOrErr, prog)
      end
      local xPct, yPct = ns.Domain.RoutePlanner.NormalizedToPercent(chosen.sourceX01, chosen.sourceY01)
      local subSuffix = chosen.spotLabel and (" [" .. tostring(chosen.spotLabel) .. "]") or ""
      local rxpActive = (prog and prog.mode == "rxp")
        or (navSt and navSt.activeProvider == "rxp")
        or (
          ns.Bridges
          and ns.Bridges.RXPBridge
          and ns.Bridges.RXPBridge.IsRivergladesGuideSelected
          and ns.Bridges.RXPBridge.IsRivergladesGuideSelected()
        )
      if rxpActive then
        ns.Compat.Print(
          string.format(
            "Saved ForeverHub map focus -> %s%s (%.1f, %.1f). RXPGuides currently owns the active arrow; deselect the RXP guide or run '/fh rg start' to use ForeverHub's arrow.",
            tostring(chosen.questTitle),
            subSuffix,
            xPct or 0,
            yPct or 0
          )
        )
      else
        ns.Compat.Print(
          string.format(
            "Focused ForeverHub Arrow -> %s%s (%.1f, %.1f). Right-click pin or click [Unpin ×] on map to unpin.",
            tostring(chosen.questTitle),
            subSuffix,
            xPct or 0,
            yPct or 0
          )
        )
      end
      WorldMapPins.RefreshNow()
      if WorldMapPins.hoveredPin and WorldMapPins.hoveredPin.cluster then
        showPinTooltip(WorldMapPins.hoveredPin)
      end
      return true
    end
  end
  return false
end

local PILL_CORNERS = { "BOTTOMLEFT", "TOPLEFT", "TOPRIGHT", "BOTTOMRIGHT" }
local PILL_CORNER_LABELS = {
  BOTTOMLEFT = "⌞",
  TOPLEFT = "⌜",
  TOPRIGHT = "⌝",
  BOTTOMRIGHT = "⌟",
}

local function nextPillCorner(cur)
  for idx, c in ipairs(PILL_CORNERS) do
    if c == cur then
      return PILL_CORNERS[(idx % #PILL_CORNERS) + 1]
    end
  end
  return "TOPLEFT"
end

local function stylePinVisuals(pin, cluster, canvasScale)
  local Theme = ns.UI and ns.UI.Theme
  local Widgets = ns.UI and ns.UI.Widgets
  local primary = cluster.primary
  local invScale = 1.0 / math.max(0.15, tonumber(canvasScale) or 1.0)

  -- Hit target >= 24 screen-space units; 28 when focused/active target (never call pin:SetScale).
  local baseSize = cluster.hasCurrentTarget and 28 or 24
  local visualDiscSize = cluster.hasCurrentTarget and 26 or (primary.kind == "turnin" and 24 or 22)

  local btnSize = baseSize * invScale
  local ringSize = visualDiscSize * invScale
  local innerBgSize = (visualDiscSize * 0.80) * invScale
  local iconSize = (visualDiscSize * 0.62) * invScale
  local glowSize = (baseSize * 1.55) * invScale

  pin:SetSize(btnSize, btnSize)
  pin.__lastBaseSize = baseSize

  if pin.shadow then
    pin.shadow:SetSize(ringSize * 1.10, ringSize * 1.10)
  end

  if pin.discBg then
    pin.discBg:SetSize(innerBgSize, innerBgSize)
    if Theme and Theme.UnpackRGBA and type(pin.discBg.SetVertexColor) == "function" then
      local r, g, b = Theme.UnpackRGBA(cluster.hasCurrentTarget and "surface.selected" or "surface.window")
      pin.discBg:SetVertexColor(r, g, b, 0.94)
    end
  end

  local ringToken = "border.default"
  local glyphKey = "loot"
  local glyphToken = "text.primary"

  if primary.kind == "turnin" then
    glyphKey = "turnin"
    glyphToken = "accent.gold"
    ringToken = "status.ready"
  elseif primary.kind == "accept" then
    glyphKey = "available"
    if primary.questLogFull then
      glyphToken = "status.warning"
      ringToken = "border.default"
    else
      glyphToken = "accent.gold"
      ringToken = "accent.gold"
    end
  else
    local style = primary.objectiveStyle or "loot"
    if style == "elite" then
      glyphKey = "elite"
      glyphToken = "status.warning"
      ringToken = "status.warning"
    elseif style == "slay" then
      glyphKey = "kill"
      glyphToken = "text.primary"
      ringToken = "border.default"
    elseif style == "supply" then
      glyphKey = "bank"
      glyphToken = "status.bank"
      ringToken = "status.bank"
    else
      glyphKey = "loot"
      glyphToken = "text.primary"
      ringToken = "border.default"
    end
  end

  if cluster.hasCurrentTarget then
    ringToken = "accent.gold"
  elseif primary.isPinned then
    ringToken = "status.reserved"
  end

  local pinRingPath = (Theme and Theme.TEXTURE_PATHS and Theme.TEXTURE_PATHS.pinRing)
    or "Interface\\AddOns\\ForeverHub\\Textures\\PinRing.tga"
  local pinGlowPath = (Theme and Theme.TEXTURE_PATHS and Theme.TEXTURE_PATHS.pinGlow)
    or "Interface\\AddOns\\ForeverHub\\Textures\\PinGlow.tga"

  if pin.ring then
    if type(pin.ring.SetTexture) == "function" then
      pin.ring:SetTexture(pinRingPath)
      if type(pin.ring.SetTexCoord) == "function" then
        pin.ring:SetTexCoord(0, 1, 0, 1)
      end
      pin.ring:Show()
    end
    pin.ring:SetSize(ringSize, ringSize)
    if type(pin.ring.SetVertexColor) == "function" then
      if Theme and Theme.UnpackRGBA then
        local r, g, b = Theme.UnpackRGBA(ringToken)
        local alpha = (primary.kind == "accept" and primary.questLogFull) and 0.72 or 0.98
        pin.ring:SetVertexColor(r, g, b, alpha)
      else
        pin.ring:SetVertexColor(0.85, 0.71, 0.42, 0.98)
      end
    end
  end

  if pin.highlight then
    if type(pin.highlight.SetTexture) == "function" then
      pin.highlight:SetTexture(pinGlowPath)
    end
    pin.highlight:SetSize(ringSize * 1.25, ringSize * 1.25)
  end

  if pin.outerGlow then
    if cluster.hasCurrentTarget then
      if type(pin.outerGlow.SetTexture) == "function" then
        pin.outerGlow:SetTexture(pinGlowPath)
        if type(pin.outerGlow.SetTexCoord) == "function" then
          pin.outerGlow:SetTexCoord(0, 1, 0, 1)
        end
      end
      pin.outerGlow:SetSize(glowSize, glowSize)
      if type(pin.outerGlow.SetVertexColor) == "function" then
        if Theme and Theme.UnpackRGBA then
          local r, g, b = Theme.UnpackRGBA("accent.gold")
          pin.outerGlow:SetVertexColor(r, g, b, 0.52)
        else
          pin.outerGlow:SetVertexColor(0.85, 0.71, 0.42, 0.52)
        end
      end
      pin.outerGlow:Show()
    else
      pin.outerGlow:Hide()
    end
  end

  pin.__glyphKey = glyphKey
  pin.__glyphToken = glyphToken
  if Widgets and type(Widgets.ApplyGlyph) == "function" then
    Widgets.ApplyGlyph(pin.icon, pin.iconFallbackText, glyphKey, glyphToken)
    if pin.icon then
      pin.icon:SetSize(iconSize, iconSize)
    end
    if pin.iconFallbackText and type(pin.iconFallbackText.SetScale) == "function" then
      pin.iconFallbackText:SetScale(invScale)
    end
  elseif pin.icon then
    applyAtlasOrTexture(pin.icon, nil, pinRingPath, 0)
    pin.icon:SetSize(iconSize, iconSize)
  end

  if pin.badgeBg and pin.badgeText then
    if cluster.count > 1 then
      local badgeSz = 13 * invScale
      pin.badgeBg:SetSize(badgeSz, badgeSz)
      if type(pin.badgeBg.ClearAllPoints) == "function" then
        pin.badgeBg:ClearAllPoints()
      end
      pin.badgeBg:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", 2 * invScale, -2 * invScale)
      pin.badgeBg:Show()

      pin.badgeText:SetText(tostring(cluster.count))
      if type(pin.badgeText.SetScale) == "function" then
        pin.badgeText:SetScale(invScale)
      end
      if type(pin.badgeText.ClearAllPoints) == "function" then
        pin.badgeText:ClearAllPoints()
      end
      pin.badgeText:SetPoint("CENTER", pin.badgeBg, "CENTER", 0, 0)
      if type(pin.badgeText.Show) == "function" then
        pin.badgeText:Show()
      end
    else
      pin.badgeBg:Hide()
      if type(pin.badgeText.Hide) == "function" then
        pin.badgeText:Hide()
      end
    end
  end
end

local function createPinButton(canvas)
  if type(CreateFrame) ~= "function" or not canvas then
    return nil
  end
  local Theme = ns.UI and ns.UI.Theme
  local pin = CreateFrame("Button", nil, canvas)
  if not pin then
    return nil
  end
  if type(pin.RegisterForClicks) == "function" then
    pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  end
  if type(pin.EnableMouse) == "function" then
    pin:EnableMouse(true)
  end

  local pinGlowPath = (Theme and Theme.TEXTURE_PATHS and Theme.TEXTURE_PATHS.pinGlow)
    or "Interface\\AddOns\\ForeverHub\\Textures\\PinGlow.tga"

  if type(pin.CreateTexture) == "function" then
    pin.outerGlow = pin:CreateTexture(nil, "BACKGROUND", nil, -2)
    if pin.outerGlow then
      pin.outerGlow:SetPoint("CENTER")
      if type(pin.outerGlow.SetBlendMode) == "function" then
        pin.outerGlow:SetBlendMode("ADD")
      end
      pin.outerGlow:Hide()
    end

    pin.shadow = pin:CreateTexture(nil, "BACKGROUND", nil, -1)
    if pin.shadow then
      pin.shadow:SetTexture(pinGlowPath)
      if type(pin.shadow.SetVertexColor) == "function" then
        pin.shadow:SetVertexColor(0, 0, 0, 0.58)
      end
      pin.shadow:SetPoint("CENTER")
    end

    pin.discBg = pin:CreateTexture(nil, "BACKGROUND", nil, 0)
    if pin.discBg then
      pin.discBg:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
      if type(pin.discBg.SetVertexColor) == "function" then
        pin.discBg:SetVertexColor(0.06, 0.08, 0.09, 0.94)
      end
      pin.discBg:SetPoint("CENTER")
    end

    pin.ring = pin:CreateTexture(nil, "ARTWORK", nil, 1)
    if pin.ring then
      pin.ring:SetPoint("CENTER")
    end

    pin.icon = pin:CreateTexture(nil, "ARTWORK", nil, 2)
    if pin.icon then
      pin.icon:SetPoint("CENTER")
    end

    pin.highlight = pin:CreateTexture(nil, "HIGHLIGHT")
    if pin.highlight then
      pin.highlight:SetTexture(pinGlowPath)
      if type(pin.highlight.SetBlendMode) == "function" then
        pin.highlight:SetBlendMode("ADD")
      end
      if type(pin.highlight.SetVertexColor) == "function" then
        pin.highlight:SetVertexColor(0.91, 0.79, 0.50, 0.35)
      end
      pin.highlight:SetPoint("CENTER")
    end

    pin.badgeBg = pin:CreateTexture(nil, "OVERLAY", nil, 3)
    if pin.badgeBg then
      pin.badgeBg:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
      if type(pin.badgeBg.SetVertexColor) == "function" then
        if Theme and Theme.UnpackRGBA then
          local r, g, b = Theme.UnpackRGBA("surface.elevated")
          pin.badgeBg:SetVertexColor(r, g, b, 0.96)
        else
          pin.badgeBg:SetVertexColor(0.12, 0.14, 0.17, 0.96)
        end
      end
      pin.badgeBg:Hide()
    end
  end

  if type(pin.CreateFontString) == "function" then
    pin.iconFallbackText = pin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if pin.iconFallbackText then
      pin.iconFallbackText:SetPoint("CENTER", pin, "CENTER", 0, 0)
      if Theme and Theme.ApplyFont then
        Theme.ApplyFont(pin.iconFallbackText, "dense", "text.primary")
      end
      if type(pin.iconFallbackText.Hide) == "function" then
        pin.iconFallbackText:Hide()
      end
    end

    pin.badgeText = pin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if pin.badgeText then
      if Theme and Theme.ApplyFont then
        Theme.ApplyFont(pin.badgeText, "dense", "text.primary")
      elseif type(pin.badgeText.SetTextColor) == "function" then
        pin.badgeText:SetTextColor(0.93, 0.91, 0.86, 1.0)
      end
      if type(pin.badgeText.Hide) == "function" then
        pin.badgeText:Hide()
      end
    end
  end

  if type(pin.SetScript) == "function" then
    pin:SetScript("OnEnter", function(self)
      WorldMapPins.hoveredPin = self
      showPinTooltip(self)
    end)
    pin:SetScript("OnLeave", function(self)
      if WorldMapPins.hoveredPin == self then
        WorldMapPins.hoveredPin = nil
      end
      if _G.GameTooltip and type(_G.GameTooltip.Hide) == "function" then
        _G.GameTooltip:Hide()
      end
    end)
    pin:SetScript("OnHide", function(self)
      if WorldMapPins.hoveredPin == self then
        WorldMapPins.hoveredPin = nil
        if _G.GameTooltip and type(_G.GameTooltip.Hide) == "function" then
          _G.GameTooltip:Hide()
        end
      end
    end)
    pin:SetScript("OnClick", function(self, button)
      if self.cluster then
        WorldMapPins.HandleClusterClick(self.cluster, button)
      end
    end)
  end

  return pin
end

local function createPillButton(parent, width, onClick, allowRightClick)
  local Theme = ns.UI and ns.UI.Theme
  local btn = CreateFrame("Button", nil, parent)
  btn:SetSize(width, 22)
  if type(btn.RegisterForClicks) == "function" then
    if allowRightClick then
      btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    else
      btn:RegisterForClicks("LeftButtonUp")
    end
  end
  if type(btn.CreateTexture) == "function" then
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    if btn.bg then
      btn.bg:SetAllPoints(btn)
      if type(btn.bg.SetColorTexture) == "function" then
        btn.bg:SetColorTexture(0.12, 0.14, 0.17, 0.92)
      end
    end
  end
  if type(btn.CreateFontString) == "function" then
    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if btn.label then
      btn.label:SetPoint("CENTER", btn, "CENTER", 0, 0)
      if Theme and Theme.ApplyFont then
        Theme.ApplyFont(btn.label, "dense", "text.secondary")
      end
    end
  end
  if type(btn.SetScript) == "function" then
    btn:SetScript("OnClick", onClick)
  end
  return btn
end

local function applyFilterBarCornerAnchor(bar, corner)
  if not bar or not bar.host then
    return
  end
  local c = tostring(corner or "BOTTOMLEFT")
  if type(bar.ClearAllPoints) == "function" then
    bar:ClearAllPoints()
  end
  if c == "TOPLEFT" then
    bar:SetPoint("TOPLEFT", bar.host, "TOPLEFT", 10, -10)
  elseif c == "TOPRIGHT" then
    bar:SetPoint("TOPRIGHT", bar.host, "TOPRIGHT", -10, -10)
  elseif c == "BOTTOMRIGHT" then
    bar:SetPoint("BOTTOMRIGHT", bar.host, "BOTTOMRIGHT", -10, 10)
  else
    bar:SetPoint("BOTTOMLEFT", bar.host, "BOTTOMLEFT", 10, 10)
  end
  bar.__appliedCorner = c
end

local function ensureFilterBar(mapFrame)
  if WorldMapPins.filterBar then
    return WorldMapPins.filterBar
  end
  if type(CreateFrame) ~= "function" or type(mapFrame) ~= "table" then
    return nil
  end
  local Widgets = ns.UI and ns.UI.Widgets
  local host = mapFrame.ScrollContainer or mapFrame
  local bar = CreateFrame("Frame", nil, host)
  if not bar then
    return nil
  end
  bar.host = host
  bar:SetSize(534, 28)
  applyFilterBarCornerAnchor(bar, "BOTTOMLEFT")
  if type(bar.SetFrameStrata) == "function" then
    bar:SetFrameStrata("HIGH")
  end
  if type(bar.SetFrameLevel) == "function" and type(host.GetFrameLevel) == "function" then
    bar:SetFrameLevel((host:GetFrameLevel() or 10) + 80)
  end
  if type(bar.EnableMouse) == "function" then
    bar:EnableMouse(true)
  end

  if Widgets and type(Widgets.ApplySurface) == "function" then
    Widgets.ApplySurface(bar, "surface.window", "border.default", 0.95)
    bar.bg = bar.__fhBg
  elseif type(bar.CreateTexture) == "function" then
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    if bar.bg then
      bar.bg:SetAllPoints(bar)
      if type(bar.bg.SetColorTexture) == "function" then
        bar.bg:SetColorTexture(0.06, 0.08, 0.09, 0.96)
      end
    end
  end

  bar.masterBtn = createPillButton(bar, 88, function(_, mouseButton)
    local s = ns.State.GetWorldMapPinSettings()
    if mouseButton == "RightButton" then
      s.pillCorner = nextPillCorner(s.pillCorner)
      applyFilterBarCornerAnchor(bar, s.pillCorner)
    else
      s.enabled = not s.enabled
    end
    WorldMapPins.lastLayoutKey = nil
    WorldMapPins.RefreshNow()
  end, true)

  bar.collapseBtn = createPillButton(bar, 78, function()
    local s = ns.State.GetWorldMapPinSettings()
    if bar.__isAutoNarrow then
      bar.__forceExpandedNarrow = not bar.__forceExpandedNarrow
    else
      s.filtersCollapsed = not s.filtersCollapsed
    end
    WorldMapPins.lastLayoutKey = nil
    WorldMapPins.RefreshNow()
  end)

  bar.objBtn = createPillButton(bar, 96, function()
    local s = ns.State.GetWorldMapPinSettings()
    s.showObjectives = not s.showObjectives
    WorldMapPins.lastLayoutKey = nil
    WorldMapPins.RefreshNow()
  end)

  bar.turnInBtn = createPillButton(bar, 92, function()
    local s = ns.State.GetWorldMapPinSettings()
    s.showTurnIns = not s.showTurnIns
    WorldMapPins.lastLayoutKey = nil
    WorldMapPins.RefreshNow()
  end)

  bar.availBtn = createPillButton(bar, 94, function()
    local s = ns.State.GetWorldMapPinSettings()
    s.showAvailable = not s.showAvailable
    WorldMapPins.lastLayoutKey = nil
    WorldMapPins.RefreshNow()
  end)

  bar.eliteBtn = createPillButton(bar, 80, function()
    local prog = ns.State.GetRouteProgress()
    prog.includeEliteBounties = not prog.includeEliteBounties
    if ns.Events and ns.Events.FlushRouteReconcileNow then
      ns.Events.FlushRouteReconcileNow()
    end
    WorldMapPins.lastLayoutKey = nil
    WorldMapPins.RefreshNow()
  end)

  bar.unpinBtn = createPillButton(bar, 66, function()
    WorldMapPins.HandleClusterClick({ entries = { true } }, "RightButton")
  end)

  bar.cornerBtn = createPillButton(bar, 24, function()
    local s = ns.State.GetWorldMapPinSettings()
    s.pillCorner = nextPillCorner(s.pillCorner)
    applyFilterBarCornerAnchor(bar, s.pillCorner)
    WorldMapPins.RefreshNow()
  end)

  WorldMapPins.filterBar = bar
  return bar
end

local function updateFilterBarPresentation(mapFrame, mapID, rawCounts)
  local bar = ensureFilterBar(mapFrame)
  if not bar then
    return
  end
  if tonumber(mapID) ~= RIVERGLADES_MAP_ID then
    bar:Hide()
    return
  end

  local Theme = ns.UI and ns.UI.Theme
  local s = ns.State.GetWorldMapPinSettings()
  local prog = ns.State.GetRouteProgress()
  local counts = rawCounts or { objectives = 0, turnins = 0, available = 0 }

  local corner = s.pillCorner or "BOTTOMLEFT"
  if bar.__appliedCorner ~= corner then
    applyFilterBarCornerAnchor(bar, corner)
  end

  local function setPillState(btn, text, active, accentMode)
    if not btn or not btn.label then
      return
    end
    btn.label:SetText(text)
    if type(btn.label.SetTextColor) == "function" then
      if Theme and Theme.UnpackRGBA then
        local tok = "text.muted"
        if accentMode == "gold" and active then
          tok = "accent.gold"
        elseif accentMode == "warning" and active then
          tok = "status.warning"
        elseif active then
          tok = "text.primary"
        end
        local r, g, b = Theme.UnpackRGBA(tok)
        btn.label:SetTextColor(r, g, b, 1.0)
      else
        if active then
          btn.label:SetTextColor(0.93, 0.91, 0.86, 1.0)
        else
          btn.label:SetTextColor(0.57, 0.62, 0.66, 1.0)
        end
      end
    end
    if btn.bg and type(btn.bg.SetColorTexture) == "function" then
      if Theme and Theme.UnpackRGBA then
        local bgTok = active and (accentMode == "gold" and "surface.selected" or "surface.elevated") or "surface.card"
        local r, g, b = Theme.UnpackRGBA(bgTok)
        btn.bg:SetColorTexture(r, g, b, active and 0.96 or 0.78)
      else
        if active then
          btn.bg:SetColorTexture(0.16, 0.21, 0.25, 0.96)
        else
          btn.bg:SetColorTexture(0.09, 0.11, 0.13, 0.78)
        end
      end
    end
  end

  local hostW = (bar.host and type(bar.host.GetWidth) == "function" and tonumber(bar.host:GetWidth())) or 0
  if hostW <= 1 then
    local cv = getWorldMapCanvas(mapFrame)
    hostW = (cv and type(cv.GetWidth) == "function" and tonumber(cv:GetWidth())) or 1002
  end
  bar.__isAutoNarrow = (hostW > 1 and hostW < 680)
  local collapsed = (s.filtersCollapsed == true) or (bar.__isAutoNarrow and not bar.__forceExpandedNarrow)

  setPillState(bar.masterBtn, s.enabled and "FH Pins: ON" or "FH Pins: OFF", s.enabled == true, "gold")
  setPillState(bar.objBtn, string.format("Objectives (%d)", counts.objectives or 0), s.enabled and s.showObjectives)
  setPillState(bar.turnInBtn, string.format("Turn-ins (%d)", counts.turnins or 0), s.enabled and s.showTurnIns)
  setPillState(bar.availBtn, string.format("Available (%d)", counts.available or 0), s.enabled and s.showAvailable)
  setPillState(bar.eliteBtn, prog.includeEliteBounties and "Elites: ON" or "Elites: OFF", prog.includeEliteBounties == true)
  setPillState(bar.collapseBtn, collapsed and "Filters ▾" or "Filters ▴", not collapsed)
  setPillState(bar.cornerBtn, PILL_CORNER_LABELS[corner] or "⌞", false)

  local xCursor = 4
  local function placeBtn(btn, w)
    if type(btn.ClearAllPoints) == "function" then
      btn:ClearAllPoints()
    end
    btn:SetSize(w, 22)
    btn:SetPoint("LEFT", bar, "LEFT", xCursor, 0)
    btn:Show()
    xCursor = xCursor + w + 4
  end

  placeBtn(bar.masterBtn, 88)
  if collapsed then
    placeBtn(bar.collapseBtn, 78)
    bar.objBtn:Hide()
    bar.turnInBtn:Hide()
    bar.availBtn:Hide()
    bar.eliteBtn:Hide()
  else
    if bar.__isAutoNarrow or s.filtersCollapsed == true then
      placeBtn(bar.collapseBtn, 78)
    else
      bar.collapseBtn:Hide()
    end
    placeBtn(bar.objBtn, 98)
    placeBtn(bar.turnInBtn, 92)
    placeBtn(bar.availBtn, 94)
    placeBtn(bar.eliteBtn, 80)
  end

  if prog and prog.pinnedActionID then
    setPillState(bar.unpinBtn, "Unpin ×", true, "warning")
    placeBtn(bar.unpinBtn, 66)
  else
    bar.unpinBtn:Hide()
  end

  placeBtn(bar.cornerBtn, 24)
  bar:SetSize(xCursor, 28)
  bar:Show()
end

function WorldMapPins.HideAllPins()
  for i = 1, #WorldMapPins.pinPool do
    local pin = WorldMapPins.pinPool[i]
    if pin then
      pin.cluster = nil
      pin:Hide()
    end
  end
  WorldMapPins.activePinCount = 0
  if WorldMapPins.filterBar then
    WorldMapPins.filterBar:Hide()
  end
end

function WorldMapPins.RequestRefresh()
  WorldMapPins.dirty = true
  WorldMapPins.lastLayoutKey = nil
  local mapFrame = getWorldMapFrame()
  if mapFrame and type(mapFrame.IsShown) == "function" and mapFrame:IsShown() then
    WorldMapPins.RefreshNow()
  end
end

function WorldMapPins.RefreshNow()
  WorldMapPins.EnsureHooksInstalled()
  local mapFrame = getWorldMapFrame()
  if not mapFrame or (type(mapFrame.IsShown) == "function" and not mapFrame:IsShown()) then
    WorldMapPins.HideAllPins()
    return 0
  end

  local mapID = getViewedMapID(mapFrame)
  local canvas = getWorldMapCanvas(mapFrame)
  if not mapID or not canvas then
    WorldMapPins.HideAllPins()
    return 0
  end

  local width = (type(canvas.GetWidth) == "function" and canvas:GetWidth()) or 0
  local height = (type(canvas.GetHeight) == "function" and canvas:GetHeight()) or 0
  local scale = (type(canvas.GetScale) == "function" and canvas:GetScale()) or 1.0
  if width <= 1 or height <= 1 or scale <= 0 then
    return 0
  end

  local settings = ns.State.GetWorldMapPinSettings()
  local progress = ns.State.GetRouteProgress()
  local entries, rawCounts = WorldMapPins.CollectPinEntries(mapID, nil, progress, settings)
  WorldMapPins.lastEntries = entries
  WorldMapPins.lastSummaryCounts = rawCounts
  WorldMapPins.dirty = false

  updateFilterBarPresentation(mapFrame, mapID, rawCounts)

  if not settings.enabled or #entries == 0 then
    for i = 1, #WorldMapPins.pinPool do
      local pin = WorldMapPins.pinPool[i]
      if pin then
        pin.cluster = nil
        pin:Hide()
      end
    end
    WorldMapPins.lastClusters = {}
    WorldMapPins.activePinCount = 0
    return 0
  end

  local clusters = WorldMapPins.BuildClusters(entries, width, height, scale, DEFAULT_CLUSTER_RADIUS_UI_UNITS)
  WorldMapPins.lastClusters = clusters

  local baseCanvasLevel = (type(canvas.GetFrameLevel) == "function" and canvas:GetFrameLevel()) or 10
  for idx, cluster in ipairs(clusters) do
    local pin = WorldMapPins.pinPool[idx]
    if not pin then
      pin = createPinButton(canvas)
      WorldMapPins.pinPool[idx] = pin
    end
    if pin then
      if type(pin.GetParent) == "function" and pin:GetParent() ~= canvas and type(pin.SetParent) == "function" then
        pin:SetParent(canvas)
      end
      pin.cluster = cluster
      local lvl = baseCanvasLevel + (cluster.hasCurrentTarget and PIN_TARGET_LEVEL_OFFSET or PIN_FRAME_LEVEL_OFFSET)
      if type(pin.SetFrameLevel) == "function" then
        pin:SetFrameLevel(lvl)
      end
      stylePinVisuals(pin, cluster, scale)
      pin:ClearAllPoints()
      pin:SetPoint("CENTER", canvas, "TOPLEFT", width * cluster.x01, -height * cluster.y01)
      pin:Show()
    end
  end

  for idx = #clusters + 1, #WorldMapPins.pinPool do
    local pin = WorldMapPins.pinPool[idx]
    if pin then
      pin.cluster = nil
      pin:Hide()
    end
  end

  WorldMapPins.activePinCount = #clusters
  return #clusters
end

WorldMapPins.updaterLatchedError = WorldMapPins.updaterLatchedError or nil

function WorldMapPins.ResetUpdaterLatch()
  WorldMapPins.updaterLatchedError = nil
  if WorldMapPins.updaterFrame and type(WorldMapPins.updaterFrame.Show) == "function" then
    local mf = WorldMapPins.hookedMapFrame
    if mf and type(mf.IsShown) == "function" and mf:IsShown() then
      pcall(WorldMapPins.updaterFrame.Show, WorldMapPins.updaterFrame)
    end
  end
end

function WorldMapPins.EnsureHooksInstalled()
  local mapFrame = getWorldMapFrame()
  if type(mapFrame) ~= "table" or WorldMapPins.hookedMapFrame == mapFrame then
    return
  end
  WorldMapPins.hookedMapFrame = mapFrame

  if type(mapFrame.HookScript) == "function" then
    pcall(mapFrame.HookScript, mapFrame, "OnShow", function()
      WorldMapPins.ResetUpdaterLatch()
      WorldMapPins.dirty = true
      WorldMapPins.lastLayoutKey = nil
      WorldMapPins.RefreshNow()
    end)
    pcall(mapFrame.HookScript, mapFrame, "OnHide", function()
      WorldMapPins.HideAllPins()
    end)
  end

  if type(hooksecurefunc) == "function" then
    if type(mapFrame.OnMapChanged) == "function" then
      pcall(hooksecurefunc, mapFrame, "OnMapChanged", function()
        WorldMapPins.dirty = true
        WorldMapPins.lastLayoutKey = nil
        WorldMapPins.RefreshNow()
      end)
    end
    if type(mapFrame.OnCanvasScaleChanged) == "function" then
      pcall(hooksecurefunc, mapFrame, "OnCanvasScaleChanged", function()
        WorldMapPins.RefreshNow()
      end)
    end
  end

  if type(CreateFrame) == "function" then
    local updater = CreateFrame("Frame", nil, mapFrame)
    if updater and type(updater.SetScript) == "function" then
      local elapsedAcc = 0
      local lastObsMap = nil
      local lastObsScale = nil
      local lastObsW = nil
      updater:SetScript("OnUpdate", function(self, elapsed)
        if WorldMapPins.updaterLatchedError ~= nil then
          if self and type(self.Hide) == "function" then
            pcall(self.Hide, self)
          end
          return
        end
        elapsedAcc = elapsedAcc + (tonumber(elapsed) or 0)
        if elapsedAcc < 0.15 then
          return
        end
        elapsedAcc = 0
        local okTick, tickErr = xpcall(
          function()
            local mID = getViewedMapID(mapFrame)
            local canvas = getWorldMapCanvas(mapFrame)
            local sc = canvas and type(canvas.GetScale) == "function" and canvas:GetScale() or nil
            local cw = canvas and type(canvas.GetWidth) == "function" and canvas:GetWidth() or nil
            if WorldMapPins.dirty
              or mID ~= lastObsMap
              or (sc and lastObsScale and math.abs(sc - lastObsScale) > 0.001)
              or (cw and cw ~= lastObsW)
            then
              lastObsMap = mID
              lastObsScale = sc
              lastObsW = cw
              WorldMapPins.RefreshNow()
            end
          end,
          function(err)
            local base = tostring(err)
            if type(_G.debugstack) == "function" then
              local okSt, st = pcall(_G.debugstack, 2, 6, 0)
              if okSt and type(st) == "string" and st ~= "" then
                return base .. "\n" .. st
              end
            end
            return base
          end
        )
        if not okTick then
          WorldMapPins.updaterLatchedError = tostring(tickErr)
          if self and type(self.Hide) == "function" then
            pcall(self.Hide, self)
          end
          if ns.Compat and type(ns.Compat.Print) == "function" then
            local firstLine = string.match(WorldMapPins.updaterLatchedError, "^([^\r\n]+)") or WorldMapPins.updaterLatchedError
            ns.Compat.Print("|cffff8800[WorldMapPins]|r Suspended map zoom watcher after error (reopen map to retry): " .. tostring(firstLine))
          end
        end
      end)
      WorldMapPins.updaterFrame = updater
    end
  end
end

function WorldMapPins.GetLiveSnapshot()
  local s = ns.State and ns.State.GetWorldMapPinSettings and ns.State.GetWorldMapPinSettings() or {}
  local mapFrame = getWorldMapFrame()
  local shown = mapFrame and type(mapFrame.IsShown) == "function" and mapFrame:IsShown() or false
  local bar = WorldMapPins.filterBar
  local barShown = bar and type(bar.IsShown) == "function" and bar:IsShown() or false
  local barH = bar and type(bar.GetHeight) == "function" and bar:GetHeight() or nil
  return {
    enabled = s.enabled ~= false,
    showObjectives = s.showObjectives ~= false,
    showTurnIns = s.showTurnIns ~= false,
    showAvailable = s.showAvailable ~= false,
    pillCorner = s.pillCorner or "BOTTOMLEFT",
    filtersCollapsed = s.filtersCollapsed == true,
    filterBarShown = barShown,
    filterBarHeight = barH,
    mapShown = shown,
    viewedMapID = shown and getViewedMapID(mapFrame) or nil,
    activePinCount = WorldMapPins.activePinCount or 0,
    entryCount = #(WorldMapPins.lastEntries or {}),
    summaryCounts = WorldMapPins.lastSummaryCounts,
  }
end
