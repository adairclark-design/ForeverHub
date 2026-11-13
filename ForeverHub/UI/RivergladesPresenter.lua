local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.UI = ns.UI or {}

local Theme = ns.UI.Theme
local RivergladesPresenter = {}
ns.UI.RivergladesPresenter = RivergladesPresenter

RivergladesPresenter.HUB_DEFINITIONS = {
  { id = "all", name = "All Riverglades", shortName = "All" },
  { id = "farholde", name = "Farholde Keep", shortName = "Farholde" },
  { id = "sunnyglade", name = "Sunnyglade & Grange", shortName = "Sunnyglade" },
  { id = "powderfuse", name = "Powderfuse Port", shortName = "Powderfuse" },
  { id = "interior", name = "Rog'mar & Bolder'ok", shortName = "Interior" },
  { id = "kroldok", name = "Krol'dok & Cross-Zone", shortName = "Krol'dok" },
}

function RivergladesPresenter.ClassifyActionHub(action)
  if type(action) ~= "table" then
    return "interior"
  end
  local aid = tostring(action.actionID or "")
  if action.isGroupBranch == true or action.isZoneExit == true or string.find(aid, "^rg_kd_") or string.find(aid, "^rg_exit_") then
    return "kroldok"
  end
  if string.find(aid, "^rg_pf_") then
    return "powderfuse"
  end
  if string.find(aid, "^rg_a_") then
    return "farholde"
  end
  if string.find(aid, "^rg_b_") or string.find(aid, "^rg_sg_") or string.find(aid, "^rg_wg_") then
    return "sunnyglade"
  end
  if string.find(aid, "^rg_hb_") or string.find(aid, "^rg_tw_") then
    return "interior"
  end

  local dest = action.destination
  if type(dest) == "table" and tonumber(dest.uiMapID) == 2548 then
    local x = tonumber(dest.x01) or 0.5
    local y = tonumber(dest.y01) or 0.5
    if x >= 0.70 and y >= 0.42 and y <= 0.64 then
      return "powderfuse"
    elseif x >= 0.54 and y >= 0.72 then
      return "farholde"
    elseif x <= 0.54 and y >= 0.55 then
      return "sunnyglade"
    end
  elseif type(dest) == "table" and tonumber(dest.uiMapID) and tonumber(dest.uiMapID) ~= 2548 then
    return "kroldok"
  end
  return "interior"
end

local function formatCoordText(dest)
  if type(dest) ~= "table" then
    return "Manual step"
  end
  local x = tonumber(dest.x01)
  local y = tonumber(dest.y01)
  local mapID = tonumber(dest.uiMapID)
  local zonePrefix = ""
  if mapID and mapID ~= 2548 then
    if mapID == 1444 then
      zonePrefix = "Feralas "
    else
      zonePrefix = string.format("Map %d ", mapID)
    end
  end
  if x and y and x > 0 and x < 1 and y > 0 and y < 1 then
    return string.format("%s%.1f, %.1f", zonePrefix, x * 100.0, y * 100.0)
  end
  return zonePrefix ~= "" and zonePrefix or "Riverglades"
end

local function lookupQuestMeta(route, action)
  if type(route) ~= "table" or type(action) ~= "table" then
    return nil
  end
  if action.questID and type(route.questsByID) == "table" and route.questsByID[action.questID] then
    return route.questsByID[action.questID]
  end
  if type(action.questKey) == "string" and type(route.questsByTitleKey) == "table" and route.questsByTitleKey[action.questKey] then
    return route.questsByTitleKey[action.questKey]
  end
  return nil
end

local function summarizePrerequisites(node, route)
  if type(node) ~= "table" or node.op == "true" then
    return "None"
  end
  local parts = {}
  local function walk(n)
    if type(n) ~= "table" then
      return
    end
    if n.op == "quest_completed" or n.op == "quest_active" or n.op == "quest_started_or_completed" then
      local qref = n.questKey or n.questID
      local qm = nil
      if type(qref) == "number" and route and route.questsByID then
        qm = route.questsByID[qref]
      elseif type(qref) == "string" and route and route.questsByTitleKey then
        qm = route.questsByTitleKey[qref]
      end
      local qName = (qm and (qm.name or qm.title)) or tostring(qref or "Quest")
      local verb = n.op == "quest_active" and "Active: " or "Requires: "
      table.insert(parts, verb .. qName)
    elseif type(n.children) == "table" then
      for _, ch in ipairs(n.children) do
        walk(ch)
      end
    elseif type(n.child) == "table" then
      walk(n.child)
    end
  end
  walk(node)
  if #parts == 0 then
    return "Conditional chain state"
  end
  return table.concat(parts, " · ")
end

-- Captures a strictly non-mutating snapshot (`RouteProgress.Evaluate` ONLY; never Start or Reconcile).
function RivergladesPresenter.CaptureSnapshot(override)
  if type(override) == "table" then
    return override
  end
  local route = ns.State and ns.State.GetCompiledRivergladesRoute and ns.State.GetCompiledRivergladesRoute() or nil
  local progress = ns.State and ns.State.GetRouteProgress and ns.State.GetRouteProgress() or {}
  local ctx = ns.Domain and ns.Domain.RoutePlanner and ns.Domain.RoutePlanner.BuildDefaultContext and ns.Domain.RoutePlanner.BuildDefaultContext() or nil
  local playerPos = ns.Compat and ns.Compat.GetPlayerPosition01 and ns.Compat.GetPlayerPosition01() or nil
  local eval = (ns.Domain and ns.Domain.RouteProgress and ns.Domain.RouteProgress.Evaluate)
      and ns.Domain.RouteProgress.Evaluate(route, progress, ctx, playerPos)
    or { valid = false, evaluations = {}, counts = {} }

  local navOwner = ns.UI and ns.UI.Navigation and ns.UI.Navigation.owner or nil
  local navStatus = ns.UI and ns.UI.Navigation and ns.UI.Navigation.lastStatus or nil
  local rxpSelected = ns.Bridges and ns.Bridges.RXPBridge and ns.Bridges.RXPBridge.IsRivergladesGuideSelected
      and ns.Bridges.RXPBridge.IsRivergladesGuideSelected()
    or false

  -- Collect live objective text for active quests
  local objectiveSummaryByActionID = {}
  if ctx and type(ctx.getQuestObjectives) == "function" and type(eval.evaluations) == "table" then
    for _, row in ipairs(eval.evaluations) do
      local act = row.action
      if act and (act.kind == "objective" or act.kind == "turnin") and row.state == "available" then
        local qref = act.questKey or act.questID
        if qref then
          local objRes = ctx.getQuestObjectives(qref)
          if type(objRes) == "table" and objRes.status == "ok" and type(objRes.objectives) == "table" and #objRes.objectives > 0 then
            local lines = {}
            for _, o in ipairs(objRes.objectives) do
              if type(o.text) == "string" and o.text ~= "" then
                table.insert(lines, o.text)
              end
            end
            if #lines > 0 then
              objectiveSummaryByActionID[act.actionID] = table.concat(lines, " · ")
            end
          end
        end
      end
    end
  end

  -- Check user-confirmed history decisions so they remain inspectable and undoable
  local userDecisions = {}
  if type(route) == "table" and type(route.questsByTitleKey) == "table" and ns.State and ns.State.GetUnresolvedQuestUserDecision then
    for qKey, qMeta in pairs(route.questsByTitleKey) do
      local dec = ns.State.GetUnresolvedQuestUserDecision(qKey, progress)
      if dec then
        table.insert(userDecisions, {
          questKey = qKey,
          questTitle = (type(qMeta) == "table" and (qMeta.name or qMeta.title)) or qKey,
          decision = dec,
        })
      end
    end
    table.sort(userDecisions, function(a, b)
      return tostring(a.questTitle) < tostring(b.questTitle)
    end)
  end

  return {
    route = route,
    progress = {
      mode = progress.mode or "paused",
      includeEliteBounties = (progress.includeEliteBounties == true),
      includeGroupBranch = (progress.includeGroupBranch ~= false),
      currentActionID = progress.currentActionID,
      pinnedActionID = progress.pinnedActionID,
      pinnedSubLocationID = progress.pinnedSubLocationID,
      explicitlySkippedActions = progress.explicitlySkippedActions or {},
    },
    eval = eval,
    objectiveSummaryByActionID = objectiveSummaryByActionID,
    userDecisions = userDecisions,
    navOwnerContext = navOwner and navOwner.ownerContext or nil,
    navProvider = (navStatus and navStatus.activeProvider) or (navOwner and navOwner.provider) or "none",
    navLabel = (navStatus and navStatus.navigationLabel) or nil,
    rxpSelected = rxpSelected,
    hasLastUndo = (ns.State and ns.State.lastQuestHistoryUndo ~= nil) or false,
  }
end

local function glyphForAction(act)
  if type(act) ~= "table" then
    return "info", "text.secondary"
  end
  if act.kind == "turnin" then
    return "turnin", "status.ready"
  elseif act.kind == "accept" then
    return "available", "accent.gold"
  elseif act.kind == "travel" then
    return "travel", "text.primary"
  elseif act.isSupplyObjective == true then
    return "bank", "status.bank"
  elseif act.isEliteBounty == true then
    return "elite", "status.warning"
  end
  return "kill", "text.primary"
end

function RivergladesPresenter.Build(snapshot, uiState)
  snapshot = type(snapshot) == "table" and snapshot or RivergladesPresenter.CaptureSnapshot()
  local rgView = (type(uiState) == "table" and type(uiState.rivergladesView) == "table") and uiState.rivergladesView or {}
  local expandedByActionID = type(rgView.expandedByActionID) == "table" and rgView.expandedByActionID or {}
  local selectedHubID = rgView.selectedHubID or "all"

  local validHub = false
  for _, h in ipairs(RivergladesPresenter.HUB_DEFINITIONS) do
    if h.id == selectedHubID then
      validHub = true
      break
    end
  end
  if not validHub then
    selectedHubID = "all"
  end

  local route = snapshot.route or {}
  local eval = snapshot.eval or {}
  local prog = snapshot.progress or {}
  local objMap = snapshot.objectiveSummaryByActionID or {}

  local hubStats = {}
  for _, h in ipairs(RivergladesPresenter.HUB_DEFINITIONS) do
    hubStats[h.id] = {
      id = h.id,
      name = h.name,
      shortName = h.shortName,
      readyCount = 0,
      activeCount = 0,
      availableCount = 0,
      unresolvedCount = 0,
    }
  end

  local readyTurnIns = {}
  local activeObjectives = {}
  local availablePickups = {}
  local unresolvedItems = {}
  local blockedOrSkipped = {}

  local totalReady = 0
  local totalActiveObj = 0
  local totalAvailablePickups = 0
  local totalUnresolved = 0

  for _, row in ipairs(eval.evaluations or {}) do
    local act = row.action
    if type(act) == "table" then
      local hubID = RivergladesPresenter.ClassifyActionHub(act)
      local stHub = hubStats[hubID] or hubStats.interior
      local stAll = hubStats.all
      local qMeta = lookupQuestMeta(route, act)

      if row.state == "available" then
        if act.kind == "turnin" then
          totalReady = totalReady + 1
          stHub.readyCount = stHub.readyCount + 1
          stAll.readyCount = stAll.readyCount + 1
        elseif act.kind == "accept" then
          totalAvailablePickups = totalAvailablePickups + 1
          stHub.availableCount = stHub.availableCount + 1
          stAll.availableCount = stAll.availableCount + 1
        else
          totalActiveObj = totalActiveObj + 1
          stHub.activeCount = stHub.activeCount + 1
          stAll.activeCount = stAll.activeCount + 1
        end
      elseif row.state == "blocked_unresolved_history" and act.kind == "accept" then
        totalUnresolved = totalUnresolved + 1
        stHub.unresolvedCount = stHub.unresolvedCount + 1
        stAll.unresolvedCount = stAll.unresolvedCount + 1
      end

      if selectedHubID == "all" or selectedHubID == hubID then
        local glyphKey, glyphColor = glyphForAction(act)
        local resolvedDest, resolvedName = act.destination, act.npcName
        if row.state == "available"
          and (act.kind == "turnin" or act.kind == "objective")
          and ns.Domain
          and ns.Domain.RoutePlanner
          and ns.Domain.RoutePlanner.ResolveActiveActionTarget
        then
          local rd, rn = ns.Domain.RoutePlanner.ResolveActiveActionTarget(act, prog, nil, nil, route, { recordDrift = false })
          if type(rd) == "table" then
            resolvedDest = rd
          end
          if type(rn) == "string" and rn ~= "" then
            resolvedName = rn
          end
        end
        local coordStr = formatCoordText(resolvedDest)
        local npcPart = (type(resolvedName) == "string" and resolvedName ~= "") and resolvedName or nil
        local liveObj = objMap[act.actionID]
        local subParts = {}
        if npcPart then table.insert(subParts, npcPart) end
        if coordStr and coordStr ~= "" then table.insert(subParts, coordStr) end
        if liveObj and liveObj ~= "" then table.insert(subParts, liveObj) end
        if #subParts == 0 and type(act.note) == "string" and act.note ~= "" then
          table.insert(subParts, act.note)
        end

        local destConf = resolvedDest and resolvedDest.coordConfidence or (qMeta and qMeta.reviewStatus) or act.reviewStatus or "verified"
        local isEstimated = (destConf == "estimated" or act.reviewStatus == "estimated")
        local isPinned = (prog.pinnedActionID ~= nil and prog.pinnedActionID == act.actionID)
        local isSkipped = (prog.explicitlySkippedActions and prog.explicitlySkippedActions[act.actionID] ~= nil) or (row.state == "skipped")

        local subLocLines = {}
        if type(act.subLocations) == "table" and #act.subLocations > 0 then
          for _, sl in ipairs(act.subLocations) do
            table.insert(subLocLines, string.format("%s (%s)", tostring(sl.label or sl.subID), formatCoordText(sl.destination)))
          end
        end

        local userDec = nil
        if act.questKey and ns.State and ns.State.GetUnresolvedQuestUserDecision then
          userDec = ns.State.GetUnresolvedQuestUserDecision(act.questKey)
        end

        local itemVM = {
          actionID = act.actionID,
          questID = act.questID,
          questKey = act.questKey,
          kind = act.kind,
          state = row.state,
          reason = row.reason,
          hubID = hubID,
          title = tostring(act.title or (qMeta and qMeta.name) or act.actionID),
          questLevel = qMeta and tonumber(qMeta.level) or (act.eligibility and tonumber(act.eligibility.minLevel)) or nil,
          subtitle = table.concat(subParts, " · "),
          note = tostring(act.note or ""),
          glyphKey = glyphKey,
          glyphColor = glyphColor,
          isElite = (act.isEliteBounty == true),
          isGroup = (act.isGroupBranch == true),
          isEstimated = isEstimated,
          isPinned = isPinned,
          isSkipped = isSkipped,
          userDecision = userDec,
          isExpanded = (expandedByActionID[act.actionID] == true),
          prereqText = summarizePrerequisites(act.requires, route),
          subLocationSummary = (#subLocLines > 0) and table.concat(subLocLines, " | ") or nil,
          provenanceLabel = isEstimated and "Estimated coordinates (community/patrol)" or "Artifact-verified coordinates",
        }

        if row.state == "available" then
          if act.kind == "turnin" then
            table.insert(readyTurnIns, itemVM)
          elseif act.kind == "accept" then
            table.insert(availablePickups, itemVM)
          else
            table.insert(activeObjectives, itemVM)
          end
        elseif row.state == "blocked_unresolved_history" and act.kind == "accept" then
          table.insert(unresolvedItems, itemVM)
        elseif row.state == "skipped" or row.state == "blocked_prerequisite" or row.state == "blocked_quest_log_full" then
          table.insert(blockedOrSkipped, itemVM)
        end
      end
    end
  end

  if type(route.quarantinedActions) == "table" and ns.Compat then
    for _, qAct in ipairs(route.quarantinedActions) do
      local qid = tonumber(qAct.questID)
      if qid and qid > 0 then
        local onRes = ns.Compat.IsOnQuestResult and ns.Compat.IsOnQuestResult(qid) or nil
        if type(onRes) == "table" and onRes.status == "ok" and onRes.value == true then
          local objsDone = false
          local objRes = ns.Compat.GetQuestObjectivesResult and ns.Compat.GetQuestObjectivesResult(qid) or nil
          if type(objRes) == "table" and objRes.status == "ok" and objRes.allFinished == true then
            objsDone = true
          end
          if not objsDone then
            table.insert(blockedOrSkipped, {
              actionID = qAct.actionID,
              questID = qid,
              kind = "manual",
              state = "quarantined_unverified",
              title = tostring(qAct.title or ("Quest #" .. tostring(qid))),
              subLine = tostring(qAct.reason or "Objective spawn coordinates unpinned — excluded from arrow"),
              badgeText = "Location unverified",
              badgeToken = "status.warning",
              hubID = selectedHubID,
              isSkipped = false,
            })
          end
        end
      end
    end
  end

  -- Hub row view-models
  local hubsVM = {}
  for _, h in ipairs(RivergladesPresenter.HUB_DEFINITIONS) do
    local st = hubStats[h.id]
    local parts = {}
    if st.readyCount > 0 then
      table.insert(parts, string.format("%d ready", st.readyCount))
    end
    local activeCombined = st.activeCount + st.availableCount
    if activeCombined > 0 then
      table.insert(parts, string.format("%d active", activeCombined))
    end
    if st.unresolvedCount > 0 then
      table.insert(parts, string.format("%d needs history", st.unresolvedCount))
    end
    local summaryLine = (#parts > 0) and table.concat(parts, " · ") or "No pending steps"
    table.insert(hubsVM, {
      id = h.id,
      name = h.name,
      shortName = h.shortName,
      summary = summaryLine,
      isSelected = (h.id == selectedHubID),
      hasReady = (st.readyCount > 0),
      hasUnresolved = (st.unresolvedCount > 0),
    })
  end

  -- Navigation owner KPI & Current Action Card
  local navModeValue = "Paused"
  local navModeSub = "Click Start route to navigate"
  local navModeToken = "text.secondary"
  if snapshot.rxpSelected or prog.mode == "rxp" then
    navModeValue = "RXP Guide"
    navModeSub = "RXP controls active arrow"
    navModeToken = "status.reserved"
  elseif prog.mode == "standalone" then
    navModeValue = "Active"
    navModeSub = snapshot.navLabel or "ForeverHub Arrow + Map Pin"
    navModeToken = "accent.gold"
  elseif snapshot.navOwnerContext == "gold_farm" then
    navModeValue = "Gold Farm"
    navModeSub = "Gold route currently owns arrow"
    navModeToken = "status.buy"
  end

  local userConfirmedCount = #(snapshot.userDecisions or {})
  local nextAct = eval.nextAction
  local plan = type(eval.plan) == "table" and eval.plan or nil

  local readySubText = "None ready yet"
  if totalReady > 0 then
    if nextAct and nextAct.kind == "turnin" then
      readySubText = "Turn in now at hub"
    elseif plan and plan.hubReturnPlanned == true then
      readySubText = "Batched for hub return"
    else
      readySubText = "Ready turn-ins deferred while you finish nearby quests"
    end
  end

  local kpis = {
    {
      value = tostring(totalReady),
      label = "Ready turn-ins",
      sub = readySubText,
      token = totalReady > 0 and "status.ready" or "text.primary",
      tooltipTitle = "Ready Turn-Ins",
      tooltipLines = {
        "Active Riverglades quests whose objectives are 100% complete in your Quest Log.",
        "Travel-aware routing defers distant leaf returns to reduce backtracking; click any turn-in row to focus it immediately.",
      },
    },
    {
      value = tostring(totalActiveObj),
      label = "Active steps",
      sub = string.format("%d available pickup(s)", totalAvailablePickups),
      token = "text.primary",
      tooltipTitle = "Active Objectives & Pickups",
      tooltipLines = {
        "Field objectives and travel steps currently ready to execute.",
        "Skipped and unresolved quests are never folded into a fake completion fraction.",
      },
    },
    {
      value = tostring(totalUnresolved),
      label = "Unresolved history",
      sub = userConfirmedCount > 0 and string.format("%d user confirmed", userConfirmedCount) or "Pre-install title quests",
      token = totalUnresolved > 0 and "status.warning" or "text.primary",
      tooltipTitle = "Unresolved Pre-Install Quest History",
      tooltipLines = {
        "Title-only quests without a server completion ID cannot be verified automatically before first observation.",
        "ForeverHub holds automatic routing on them until you confirm whether you completed them.",
      },
    },
    {
      value = navModeValue,
      label = "Navigation owner",
      sub = navModeSub,
      token = navModeToken,
      tooltipTitle = "Navigation Ownership",
      tooltipLines = {
        "Only one route (Riverglades, Gold Farm, or RXP Guide) owns waypoints and the directional arrow at a time.",
      },
    },
  }

  local currentActionVM
  if nextAct then
    local nextDest, nextNpcName = nextAct.destination, nextAct.npcName
    if ns.Domain and ns.Domain.RoutePlanner and ns.Domain.RoutePlanner.ResolveActiveActionTarget then
      local rd, rn = ns.Domain.RoutePlanner.ResolveActiveActionTarget(nextAct, prog, nil, nil, route, { recordDrift = false })
      if type(rd) == "table" then
        nextDest = rd
      end
      if type(rn) == "string" and rn ~= "" then
        nextNpcName = rn
      end
    end
    local nextCoord = formatCoordText(nextDest)
    local nextObj = objMap[nextAct.actionID]
    local detailParts = {}
    if nextNpcName and nextNpcName ~= "" then
      table.insert(detailParts, nextNpcName)
    end
    if nextCoord and nextCoord ~= "" then
      table.insert(detailParts, nextCoord)
    end
    if nextObj and nextObj ~= "" then
      table.insert(detailParts, nextObj)
    elseif nextAct.note and nextAct.note ~= "" then
      table.insert(detailParts, nextAct.note)
    end

    local reasonCode = plan and plan.selectionReason or nil
    local reasonLabel = plan and plan.selectionReasonLabel or nil
    local anchorLabel = plan and plan.anchorLabel or nil
    if plan and plan.insertedGroupID and anchorLabel and anchorLabel ~= "" then
      table.insert(detailParts, "Planned anchor: " .. tostring(anchorLabel))
    elseif anchorLabel and anchorLabel ~= "" and anchorLabel ~= nextNpcName and plan and plan.zoneStatus == "in_zone" then
      table.insert(detailParts, "Anchor: " .. tostring(anchorLabel))
    end

    local cardTitle = tostring(nextAct.title or nextAct.actionID)
    local cardDetail = table.concat(detailParts, " · ")
    if plan and plan.zoneStatus == "off_zone" then
      cardTitle = "Travel to Riverglades to begin"
      cardDetail = "Entry step: " .. tostring(nextAct.title or nextAct.actionID) .. (cardDetail ~= "" and (" · " .. cardDetail) or "")
    end

    local headingText = "CURRENT ROUTE STEP"
    if type(reasonLabel) == "string" and reasonLabel ~= "" then
      headingText = "CURRENT ROUTE STEP · " .. reasonLabel
    end

    currentActionVM = {
      hasAction = true,
      actionID = nextAct.actionID,
      title = cardTitle,
      detail = cardDetail,
      headingText = headingText,
      reasonCode = reasonCode,
      reasonLabel = reasonLabel,
      anchorLabel = anchorLabel,
      zoneStatus = plan and plan.zoneStatus or "in_zone",
      providerText = navModeSub,
      isRunning = (prog.mode == "standalone"),
      isRxp = (snapshot.rxpSelected or prog.mode == "rxp"),
      isPinned = (prog.pinnedActionID ~= nil and prog.pinnedActionID == nextAct.actionID),
      primaryButtonLabel = (prog.mode == "standalone") and "Pause route" or "Start route",
    }
  else
    local emptyMsg = totalUnresolved > 0
      and "Remaining title pickups need pre-install history confirmation below before automatic routing."
      or "All currently eligible Riverglades steps are complete."
    currentActionVM = {
      hasAction = false,
      title = totalUnresolved > 0 and "Waiting on unresolved quest history" or "Riverglades route caught up",
      detail = emptyMsg,
      headingText = "CURRENT ROUTE STEP",
      reasonCode = "idle",
      reasonLabel = "Route caught up",
      anchorLabel = nil,
      zoneStatus = "idle",
      providerText = navModeSub,
      isRunning = (prog.mode == "standalone"),
      isRxp = (snapshot.rxpSelected or prog.mode == "rxp"),
      isPinned = false,
      primaryButtonLabel = (prog.mode == "standalone") and "Pause route" or "Start route",
    }
  end

  local lastExportText = "Static snapshot for RestedXP (does not auto-branch dynamically)"
  if tonumber(rgView.lastExportedAt) and tonumber(rgView.lastExportedAt) > 0 then
    if type(_G.date) == "function" then
      local okD, formatted = pcall(_G.date, "%H:%M:%S", tonumber(rgView.lastExportedAt))
      if okD and type(formatted) == "string" then
        lastExportText = "Exported snapshot at " .. formatted .. " · Static RXP itinerary"
      end
    else
      lastExportText = "Snapshot exported · Static RXP itinerary"
    end
  end

  local userDecisions = snapshot.userDecisions or {}
  local defaultUnresolvedOpen = (#unresolvedItems > 0) or (#userDecisions > 0)
  local unresolvedExpanded
  if rgView.unresolvedCollapsedByUser == true then
    unresolvedExpanded = false
  else
    unresolvedExpanded = (rgView.unresolvedExpanded == true) or defaultUnresolvedOpen
  end

  return {
    selectedHubID = selectedHubID,
    kpis = kpis,
    hubs = hubsVM,
    currentAction = currentActionVM,
    readyTurnIns = readyTurnIns,
    activeObjectives = activeObjectives,
    availablePickups = availablePickups,
    unresolvedItems = unresolvedItems,
    userDecisions = userDecisions,
    blockedOrSkipped = blockedOrSkipped,
    includeEliteBounties = prog.includeEliteBounties,
    includeGroupBranch = prog.includeGroupBranch,
    unresolvedExpanded = unresolvedExpanded,
    blockedExpanded = (rgView.blockedExpanded == true),
    exportNote = lastExportText,
    tabBadge = RivergladesPresenter.FormatTabBadgeFromCounts(
      prog.mode == "standalone",
      totalReady,
      totalUnresolved,
      totalAvailablePickups + totalActiveObj
    ),
    tabBadgeToken = select(
      2,
      RivergladesPresenter.FormatTabBadgeFromCounts(
        prog.mode == "standalone",
        totalReady,
        totalUnresolved,
        totalAvailablePickups + totalActiveObj
      )
    ),
  }
end

function RivergladesPresenter.FormatTabBadgeFromCounts(isLiveRoute, totalReady, totalUnresolved, totalAvailableSteps)
  local ready = tonumber(totalReady) or 0
  local unresolved = tonumber(totalUnresolved) or 0
  local avail = tonumber(totalAvailableSteps) or 0
  if isLiveRoute == true then
    if ready > 0 then
      return string.format("LIVE · %d ready", ready), "status.ready"
    end
    return "LIVE", "accent.gold"
  end
  if ready > 0 then
    return string.format("%d ready", ready), "status.ready"
  elseif unresolved > 0 then
    return string.format("%d?", unresolved), "status.warning"
  elseif avail > 0 then
    return "Route", "accent.gold"
  end
  return "", nil
end

-- Strictly non-mutating tab badge summary (`RouteProgress.Evaluate` ONLY; never starts or reconciles).
function RivergladesPresenter.ComputeTabBadge(snapshotOverride)
  local route, progress, eval
  if type(snapshotOverride) == "table" then
    route = snapshotOverride.route
    progress = snapshotOverride.progress or {}
    eval = snapshotOverride.eval or {}
  else
    route = ns.State and ns.State.GetCompiledRivergladesRoute and ns.State.GetCompiledRivergladesRoute() or nil
    progress = ns.State and ns.State.GetRouteProgress and ns.State.GetRouteProgress() or {}
    local ctx = ns.Domain and ns.Domain.RoutePlanner and ns.Domain.RoutePlanner.BuildDefaultContext and ns.Domain.RoutePlanner.BuildDefaultContext() or nil
    local playerPos = ns.Compat and ns.Compat.GetPlayerPosition01 and ns.Compat.GetPlayerPosition01() or nil
    eval = (ns.Domain and ns.Domain.RouteProgress and ns.Domain.RouteProgress.Evaluate)
        and ns.Domain.RouteProgress.Evaluate(route, progress, ctx, playerPos)
      or { valid = false, evaluations = {} }
  end

  local totalReady = 0
  local totalUnresolved = 0
  local totalAvailableSteps = 0
  for _, row in ipairs(eval.evaluations or {}) do
    local act = row.action
    if type(act) == "table" then
      if row.state == "available" then
        if act.kind == "turnin" then
          totalReady = totalReady + 1
        else
          totalAvailableSteps = totalAvailableSteps + 1
        end
      elseif row.state == "blocked_unresolved_history" and act.kind == "accept" then
        totalUnresolved = totalUnresolved + 1
      end
    end
  end

  return RivergladesPresenter.FormatTabBadgeFromCounts(
    progress.mode == "standalone",
    totalReady,
    totalUnresolved,
    totalAvailableSteps
  )
end

return RivergladesPresenter
