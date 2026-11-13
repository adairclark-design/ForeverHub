local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
local Events = {}
ns.Events = Events

function Events.RunSelfTestCommand()
  if not (ns.Domain and ns.Domain.SelfTest and ns.Domain.SelfTest.RunAll) then
    ns.Compat.Print("SelfTest module not loaded.")
    return
  end
  local report = ns.Domain.SelfTest.RunAll()
  ns.Compat.Print(
    string.format(
      "=== ForeverHub Acceptance Self-Tests (%d/%d PASSED) ===",
      report.passed,
      report.total
    )
  )
  for _, r in ipairs(report.results or {}) do
    if r.passed then
      ns.Compat.Print(string.format("  |cff00ff00[PASS]|r %s", r.name))
    else
      ns.Compat.Print(string.format("  |cffff4444[FAIL]|r %s — %s", r.name, tostring(r.error)))
    end
  end

  if ns.Domain.SelfTest.RunRivergladesSuite then
    local rgReport = ns.Domain.SelfTest.RunRivergladesSuite()
    ns.Compat.Print(
      string.format(
        "=== ForeverHub v%s Riverglades & Advisor Self-Tests (%d/%d PASSED) ===",
        tostring(ns.version or "0.7.1"),
        rgReport.passed,
        rgReport.total
      )
    )
    for _, r in ipairs(rgReport.results or {}) do
      if r.passed then
        ns.Compat.Print(string.format("  |cff00ff00[PASS]|r %s", r.name))
      else
        ns.Compat.Print(string.format("  |cffff4444[FAIL]|r %s — %s", r.name, tostring(r.error)))
      end
    end
  end

  if ns.Domain.SelfTest.RunGoldFarmsSuite then
    local gfReport = ns.Domain.SelfTest.RunGoldFarmsSuite()
    ns.Compat.Print(
      string.format(
        "=== ForeverHub v0.5.0 Raw Gold Farms Self-Tests (%d/%d PASSED) ===",
        gfReport.passed,
        gfReport.total
      )
    )
    for _, r in ipairs(gfReport.results or {}) do
      if r.passed then
        ns.Compat.Print(string.format("  |cff00ff00[PASS]|r %s", r.name))
      else
        ns.Compat.Print(string.format("  |cffff4444[FAIL]|r %s — %s", r.name, tostring(r.error)))
      end
    end
  end

  if ns.Domain.SelfTest.RunWorkspaceUISuite then
    local uiReport = ns.Domain.SelfTest.RunWorkspaceUISuite()
    ns.Compat.Print(
      string.format(
        "=== ForeverHub v%s Workspace UI Self-Tests (%d/%d PASSED) ===",
        tostring(ns.version or "0.8.0"),
        uiReport.passed,
        uiReport.total
      )
    )
    for _, r in ipairs(uiReport.results or {}) do
      if r.passed then
        ns.Compat.Print(string.format("  |cff00ff00[PASS]|r %s", r.name))
      else
        ns.Compat.Print(string.format("  |cffff4444[FAIL]|r %s — %s", r.name, tostring(r.error)))
      end
    end
  end
end

function Events.RunDoctor()
  local meta = (ns.Data and ns.Data.meta) or {}
  local version, build, _, tocVersion = "unknown", "unknown", "unknown", "unknown"
  if GetBuildInfo then
    local v, b, d, t = GetBuildInfo()
    version = tostring(v or "unknown")
    build = tostring(b or "unknown")
    tocVersion = tostring(t or "unknown")
  end

  local curName, curRealm = ns.Compat.GetCharacterKey()
  local hasAuctionator = ns.Providers.Auctionator and ns.Providers.Auctionator.IsAvailable() or false
  local invBackend = ns.Providers.Syndicator and ns.Providers.Syndicator.GetActiveBackendName() or "None"

  local snap, bankMeta = {}, nil
  if ns.Providers.Inventory and ns.Providers.Inventory.GetAggregatedSnapshot then
    snap, bankMeta = ns.Providers.Inventory.GetAggregatedSnapshot(true)
  end
  local bankAttr = ns.Providers.Inventory and ns.Providers.Inventory.GetBankAttributionMeta and ns.Providers.Inventory.GetBankAttributionMeta()
    or { label = "Bank: Unvisited" }

  local ownedCratesTotal = 0
  local ownedCrateTypes = 0
  local altSoulboundCratesTotal = 0
  for itemID, _ in pairs((ns.Data and ns.Data.cratesByItemID) or {}) do
    local c = snap[itemID]
    local charTot = c and (c.bagCount + c.bankCount) or 0
    local altTot = c and ((c.altEligibleCount or 0) + (c.altUnknownCount or 0) + (c.altIneligibleCount or 0)) or 0
    if charTot > 0 then
      ownedCratesTotal = ownedCratesTotal + charTot
      ownedCrateTypes = ownedCrateTypes + 1
    end
    altSoulboundCratesTotal = altSoulboundCratesTotal + altTot
  end

  local ownedSealedCratesTotal = 0
  for itemID, _ in pairs((ns.Data and ns.Data.sealedCratesByItemID) or {}) do
    local c = snap[itemID]
    ownedSealedCratesTotal = ownedSealedCratesTotal + (c and (c.bagCount + c.bankCount) or 0)
  end

  local ownedWritsTotal = 0
  for itemID, _ in pairs((ns.Data and ns.Data.writsByItemID) or {}) do
    local c = snap[itemID]
    local charTot = c and (c.bagCount + c.bankCount) or 0
    if charTot > 0 then
      ownedWritsTotal = ownedWritsTotal + charTot
    end
  end

  local activeRes = ns.State.GetOrderedReservations()
  local selfTestSummary = "N/A"
  if ns.Domain and ns.Domain.SelfTest then
    if ns.Domain.SelfTest.GetDoctorSuiteSummary then
      selfTestSummary = ns.Domain.SelfTest.GetDoctorSuiteSummary("core")
    elseif ns.Domain.SelfTest.RunAll then
      local st = ns.Domain.SelfTest.RunAll()
      selfTestSummary = string.format("%d/%d PASSED", st.passed, st.total)
    end
  end

  local rgSelfTestSuffix = ""
  if ns.Domain and ns.Domain.SelfTest and ns.Domain.SelfTest.RunRivergladesSuite then
    local rgSum = ns.Domain.SelfTest.GetDoctorSuiteSummary
      and ns.Domain.SelfTest.GetDoctorSuiteSummary("riverglades")
      or nil
    if rgSum then
      rgSelfTestSuffix = " | RG-v0.4.0: " .. rgSum
    end
  end
  if ns.Domain and ns.Domain.SelfTest and ns.Domain.SelfTest.RunGoldFarmsSuite then
    local gfSum = ns.Domain.SelfTest.GetDoctorSuiteSummary
      and ns.Domain.SelfTest.GetDoctorSuiteSummary("gold_farms")
      or nil
    if gfSum then
      rgSelfTestSuffix = rgSelfTestSuffix .. " | GF-v0.5.0: " .. gfSum
    end
  end
  if ns.Domain and ns.Domain.SelfTest and ns.Domain.SelfTest.RunWorkspaceUISuite then
    local uiSum = ns.Domain.SelfTest.GetDoctorSuiteSummary
      and ns.Domain.SelfTest.GetDoctorSuiteSummary("workspace_ui")
      or nil
    if uiSum then
      rgSelfTestSuffix = rgSelfTestSuffix .. " | UI-v0.8.0: " .. uiSum
    end
  end

  ns.Compat.Print(string.format("=== ForeverHub Doctor (v%s) ===", tostring(ns.version or "0.5.2")))
  ns.Compat.Print(
    string.format(
      "Client: %s (Build %s, Interface %s) | Expected Interface: %s",
      version,
      build,
      tocVersion,
      tostring(meta.verifiedRuntimeInterface or 16001)
    )
  )
  ns.Compat.Print(
    string.format(
      "Policy: %s | Corpus: %s | SHA-256: %s",
      tostring(meta.policyVersion or "v2.2"),
      tostring(meta.corpusRevisionID or "unknown"),
      string.sub(tostring(meta.compiledContentSha256 or "unknown"), 1, 16)
    )
  )
  ns.Compat.Print(
    string.format(
      "Dataset: %d Crates | %d Sealed Crates | %d Materials | %d Forever Writs | %d Unique Books (%d Locations)",
      tonumber(meta.crateCount) or 0,
      tonumber(meta.sealedCrateCount) or 0,
      tonumber(meta.materialCount) or 0,
      tonumber(meta.writCount) or 0,
      tonumber(meta.verifiedBookIdentityCount) or 0,
      tonumber(meta.totalBookLocationCount) or 0
    )
  )
  ns.Compat.Print(
    string.format(
      "Providers: Auctionator=%s | AccountInventory=%s | %s (complete=%s)",
      hasAuctionator and "OK" or "Missing",
      invBackend,
      tostring(bankAttr.label or "Bank: Unvisited"),
      tostring(bankMeta and bankMeta.complete or false)
    )
  )
  ns.Compat.Print(
    string.format(
      "Character %s-%s: %d Unopened Crate(s) across %d type(s) | %d Sealed Crate(s) | %d Writ(s) | %d Active Goal(s) | SelfTests: %s%s",
      curName,
      curRealm,
      ownedCratesTotal,
      ownedCrateTypes,
      ownedSealedCratesTotal,
      ownedWritsTotal,
      #activeRes,
      selfTestSummary,
      rgSelfTestSuffix
    )
  )
  local navLatch = ns.UI and ns.UI.Navigation and ns.UI.Navigation.lastUpdateError
  if navLatch and navLatch.error then
    local firstLine = string.match(tostring(navLatch.error), "^([^\r\n]+)") or tostring(navLatch.error)
    ns.Compat.Print(string.format("|cffff8800Runtime Latch (Navigation:%s):|r %s", tostring(navLatch.loop or "?"), firstLine))
  end
  local mapLatch = ns.UI and ns.UI.WorldMapPins and ns.UI.WorldMapPins.updaterLatchedError
  if mapLatch then
    local firstLine = string.match(tostring(mapLatch), "^([^\r\n]+)") or tostring(mapLatch)
    ns.Compat.Print(string.format("|cffff8800Runtime Latch (WorldMapPins):|r %s", firstLine))
  end
end

Events.reconcilePending = false
Events.objectiveVerifySeq = 0

function Events.FlushRouteReconcileNow()
  Events.reconcilePending = false
  if not (ns.Domain and ns.Domain.RouteProgress) then
    return nil
  end
  if ns.Compat and ns.Compat.InvalidateQuestStateCaches then
    ns.Compat.InvalidateQuestStateCaches()
  end
  local progress = ns.State.GetRouteProgress()
  local eval = ns.Domain.RouteProgress.Reconcile(nil, progress)
  if progress and progress.mode ~= "paused" and ns.UI and ns.UI.Navigation then
    pcall(ns.UI.Navigation.SyncFromEvaluation, eval, progress)
  end
  if ns.UI and ns.UI.WorldMapPins and ns.UI.WorldMapPins.RequestRefresh then
    pcall(ns.UI.WorldMapPins.RequestRefresh)
  end
  if ns.UI and ns.UI.Workspace and ns.UI.Workspace.RefreshIfShown then
    pcall(ns.UI.Workspace.RefreshIfShown)
  end
  return eval
end

function Events.ScheduleRouteReconcile()
  if Events.reconcilePending then
    return
  end
  if C_Timer and type(C_Timer.After) == "function" then
    Events.reconcilePending = true
    local ok = pcall(C_Timer.After, 0.12, function()
      Events.FlushRouteReconcileNow()
    end)
    if not ok then
      Events.FlushRouteReconcileNow()
    end
  else
    Events.FlushRouteReconcileNow()
  end
end

function Events.ScheduleObjectiveVerificationReconciles()
  Events.ScheduleRouteReconcile()
  if not (C_Timer and type(C_Timer.After) == "function") then
    return
  end
  local progress = ns.State and ns.State.GetRouteProgress and ns.State.GetRouteProgress()
  if not progress or progress.mode == "paused" then
    return
  end
  Events.objectiveVerifySeq = (Events.objectiveVerifySeq or 0) + 1
  local seq = Events.objectiveVerifySeq
  for _, delaySec in ipairs({ 0.60, 1.40 }) do
    pcall(C_Timer.After, delaySec, function()
      if seq ~= Events.objectiveVerifySeq then
        return
      end
      local curProg = ns.State and ns.State.GetRouteProgress and ns.State.GetRouteProgress()
      if curProg and curProg.mode ~= "paused" then
        Events.CaptureQuestFieldTelemetry("objective_scan")
        Events.FlushRouteReconcileNow()
      end
    end)
  end
end

function Events.ScheduleVerificationReconciles()
  Events.ScheduleRouteReconcile()
  if not (C_Timer and type(C_Timer.After) == "function") then
    return
  end
  local progress = ns.State and ns.State.GetRouteProgress and ns.State.GetRouteProgress()
  if not progress or progress.mode == "paused" then
    return
  end
  for _, delaySec in ipairs({ 0.85, 2.20 }) do
    pcall(C_Timer.After, delaySec, function()
      local curProg = ns.State and ns.State.GetRouteProgress and ns.State.GetRouteProgress()
      if curProg and curProg.mode ~= "paused" then
        Events.FlushRouteReconcileNow()
      end
    end)
  end
end

local function formatRouteStepSummary(act)
  if not act then
    return "None (all eligible steps completed or skipped)"
  end
  local dest = act.destination
  local npcName = act.npcName
  if ns.Domain and ns.Domain.RoutePlanner and ns.Domain.RoutePlanner.ResolveActiveActionTarget then
    local rd, rn = ns.Domain.RoutePlanner.ResolveActiveActionTarget(act, ns.State and ns.State.GetRouteProgress and ns.State.GetRouteProgress() or nil)
    if type(rd) == "table" then
      dest = rd
    end
    if type(rn) == "string" and rn ~= "" then
      npcName = rn
    end
  end
  if dest then
    local xPct, yPct = ns.Domain.RoutePlanner.NormalizedToPercent(dest.x01, dest.y01)
    local npcSuffix = (type(npcName) == "string" and npcName ~= "") and (" — " .. npcName) or ""
    return string.format("[%s] %s @ (%.1f, %.1f)%s", tostring(act.actionID), tostring(act.title), xPct or 0, yPct or 0, npcSuffix)
  end
  return string.format("[%s] %s (Manual pin)", tostring(act.actionID), tostring(act.title))
end

function Events.RunRivergladesDoctor()
  local rgMeta = (ns.RivergladesData and ns.RivergladesData.meta) or {}
  local route = ns.State.GetCompiledRivergladesRoute()
  local progress = ns.State.GetRouteProgress()
  local eval = (ns.Domain.RouteProgress.Evaluate and ns.Domain.RouteProgress.Evaluate(route, progress))
    or ns.Domain.RouteProgress.Reconcile(route, progress)

  local mapValid = ns.Compat.ValidateUiMap(2548)
  local canWp = ns.Compat.CanSetNativeWaypoint(2548)
  local rxpAvail = ns.Bridges.RXPBridge and ns.Bridges.RXPBridge.IsAvailable() or false
  local rxpSel = ns.Bridges.RXPBridge and ns.Bridges.RXPBridge.IsRivergladesGuideSelected() or false
  local ttAvail = (type(_G.TomTom) == "table" and type(_G.TomTom.AddWaypoint) == "function")
  local qAudit = ns.Providers.Questie and ns.Providers.Questie.AuditManifestAgainstLiveQuestie(route)
    or { available = false, status = { reason = "unavailable" }, mismatches = {} }

  local rgTestSummary = "N/A"
  if ns.Domain.SelfTest and ns.Domain.SelfTest.GetDoctorSuiteSummary then
    rgTestSummary = ns.Domain.SelfTest.GetDoctorSuiteSummary("riverglades")
  end

  ns.Compat.Print(string.format("=== ForeverHub Riverglades Doctor (v%s) ===", tostring(ns.version or "0.7.1")))
  ns.Compat.Print(
    string.format(
      "Route: %s (dataset=%s, rev=%s, faction=%s) | Content SHA: %s | Manifest SHA: %s",
      tostring(route and route.routeID or "missing"),
      tostring(rgMeta.datasetVersion or route and route.datasetVersion or "?"),
      tostring(rgMeta.datasetRevision or route and route.revision or "?"),
      tostring(route and route.faction or "?"),
      string.sub(tostring(rgMeta.compiledContentSha256 or "unknown"), 1, 16),
      string.sub(tostring(rgMeta.sourceManifestHash or "unknown"), 1, 16)
    )
  )
  ns.Compat.Print(
    string.format(
      "Map 2548: valid=%s (%s) | CanSetUserWaypoint=%s (%s) | TomTom=%s | RXP=%s (selected=%s) | FieldCaptures=%d",
      tostring(mapValid.value),
      tostring(mapValid.status),
      tostring(canWp.value),
      tostring(canWp.status),
      ttAvail and "OK" or "Missing",
      rxpAvail and "OK" or "Missing",
      tostring(rxpSel),
      #(ns.State.GetFieldCaptures and ns.State.GetFieldCaptures() or {})
    )
  )
  if qAudit.available then
    ns.Compat.Print(
      string.format(
        "Questie Adapter: READY (Questie=%s, QuestieDB=%s) | Manifest NPCs=%d/%d | Quests in DB=%d/%d | Mismatches=%d",
        tostring(qAudit.status.questieVersion or "unknown"),
        tostring(qAudit.status.questieDBVersion or "unknown"),
        qAudit.npcMatched or 0,
        qAudit.npcTotal or 0,
        qAudit.questPresent or 0,
        qAudit.questTotal or 0,
        #(qAudit.mismatches or {})
      )
    )
    for _, m in ipairs(qAudit.mismatches or {}) do
      ns.Compat.Print("  |cffffcc00[Mismatch]|r " .. tostring(m))
    end
  else
    ns.Compat.Print(
      string.format(
        "Questie Adapter: Not Active (%s) — using pinned offline dataset.",
        tostring(qAudit.status and qAudit.status.reason or "not_loaded")
      )
    )
  end
  local counts = (eval and eval.counts) or {}
  local navStatus = ns.UI.Navigation and ns.UI.Navigation.lastStatus or {}
  local arrowSnap = ns.UI.Navigation and ns.UI.Navigation.GetLiveArrowSnapshot and ns.UI.Navigation.GetLiveArrowSnapshot() or nil
  ns.Compat.Print(
    string.format(
      "Progress: mode=%s | nav=%s | arrow=%s%s | %d/%d completed, %d skipped, %d available, %d unresolved-title, %d quarantined | RG SelfTests: %s",
      tostring(progress and progress.mode or "paused"),
      tostring(navStatus.activeProvider or "none"),
      tostring(arrowSnap and arrowSnap.status or "idle"),
      (arrowSnap and type(arrowSnap.yards) == "number") and string.format("(%.0fyd)", arrowSnap.yards) or "",
      counts.completed or 0,
      counts.total or 0,
      counts.skipped or 0,
      counts.available or 0,
      counts.blockedUnresolvedHistory or 0,
      tonumber(rgMeta.quarantinedActionCount) or 0,
      rgTestSummary
    )
  )
  if ns.UI and ns.UI.WorldMapPins and ns.UI.WorldMapPins.CollectPinEntries then
    local pinSettings = ns.State.GetWorldMapPinSettings()
    local entries2548, raw2548 = ns.UI.WorldMapPins.CollectPinEntries(2548, route, progress, pinSettings)
    local snap = ns.UI.WorldMapPins.GetLiveSnapshot and ns.UI.WorldMapPins.GetLiveSnapshot() or {}
    ns.Compat.Print(
      string.format(
        "World Map Pins: %s (Obj=%s, TurnIn=%s, Avail=%s) | Map 2548 pins=%d (obj=%d, turnin=%d, avail=%d) | Active canvas clusters=%d",
        pinSettings.enabled ~= false and "ON" or "OFF",
        pinSettings.showObjectives ~= false and "ON" or "OFF",
        pinSettings.showTurnIns ~= false and "ON" or "OFF",
        pinSettings.showAvailable ~= false and "ON" or "OFF",
        #(entries2548 or {}),
        raw2548 and raw2548.objectives or 0,
        raw2548 and raw2548.turnins or 0,
        raw2548 and raw2548.available or 0,
        snap.activePinCount or 0
      )
    )
  end
  local driftList = {}
  if ns.Compat and type(ns.Compat.liveQuestTargetDrifts) == "table" then
    for _, ov in pairs(ns.Compat.liveQuestTargetDrifts) do
      if type(ov) == "table" and type(ov.destination) == "table" then
        table.insert(driftList, ov)
      end
    end
    table.sort(driftList, function(a, b)
      return tostring(a.actionID) < tostring(b.actionID)
    end)
  end
  ns.Compat.Print(
    string.format(
      "Live Self-Healing: %d quest target override(s) active",
      #driftList
    )
  )
  for _, ov in ipairs(driftList) do
    local hx, hy = ns.Domain.RoutePlanner.NormalizedToPercent(ov.destination.x01, ov.destination.y01)
    ns.Compat.Print(
      string.format(
        "  |cff5cc98a[Healed]|r [%s] q=%s via %s (~%d yds): %s -> %s @ (%.1f, %.1f)",
        tostring(ov.actionID),
        tostring(ov.questID),
        tostring(ov.source),
        tonumber(ov.deltaYards) or 0,
        tostring(ov.staticNpcName or "?"),
        tostring(ov.targetName or "?"),
        hx or 0,
        hy or 0
      )
    )
  end
  ns.Compat.Print("Current Step: " .. formatRouteStepSummary(eval and eval.nextAction))
end

local function refreshWorldMapPinsIfLoaded()
  if ns.UI and ns.UI.WorldMapPins and ns.UI.WorldMapPins.RequestRefresh then
    ns.UI.WorldMapPins.RequestRefresh()
  end
end

local function printWorldMapPinsStatus(prefix)
  local pinSettings = ns.State.GetWorldMapPinSettings()
  local progress = ns.State.GetRouteProgress()
  local entries2548, raw2548 = {}, {}
  if ns.UI and ns.UI.WorldMapPins and ns.UI.WorldMapPins.CollectPinEntries then
    entries2548, raw2548 = ns.UI.WorldMapPins.CollectPinEntries(2548, nil, progress, pinSettings)
  end
  ns.Compat.Print(
    string.format(
      "%sWorld Map Pins: %s | Obj=%s (%d) | TurnIn=%s (%d) | Avail!=%s (%d) | Elites=%s | Visible on Riverglades=%d",
      prefix and (prefix .. " — ") or "",
      pinSettings.enabled ~= false and "ON" or "OFF",
      pinSettings.showObjectives ~= false and "ON" or "OFF",
      raw2548 and raw2548.objectives or 0,
      pinSettings.showTurnIns ~= false and "ON" or "OFF",
      raw2548 and raw2548.turnins or 0,
      pinSettings.showAvailable ~= false and "ON" or "OFF",
      raw2548 and raw2548.available or 0,
      progress.includeEliteBounties and "ON" or "OFF",
      #(entries2548 or {})
    )
  )
end

local resyncActiveNavigationContext

function Events.HandleRivergladesSubcommand(subRaw)
  local cleaned = string.gsub(tostring(subRaw or ""), "^%s*(.-)%s*$", "%1")
  local sub, argRaw = string.match(cleaned, "^(%S*)%s*(.-)$")
  sub = string.lower(sub or "")
  argRaw = string.gsub(tostring(argRaw or ""), "^%s*(.-)%s*$", "%1")
  local arg = string.lower(argRaw)

  local function refreshRivergladesUIIfShown()
    if ns.UI and ns.UI.Riverglades and ns.UI.Riverglades.RefreshIfShown then
      ns.UI.Riverglades.RefreshIfShown()
    elseif ns.UI and ns.UI.Workspace and ns.UI.Workspace.RefreshIfShown then
      ns.UI.Workspace.RefreshIfShown()
    end
  end

  if sub == "ui" then
    if ns.UI and ns.UI.Riverglades and ns.UI.Riverglades.Toggle then
      ns.UI.Riverglades.Toggle()
    end
    return
  elseif sub == "hud" then
    local arrowSettings = ns.State.GetArrowSettings()
    local hudSub, hudVal = string.match(arg, "^(%S*)%s*(.-)$")
    hudSub = string.lower(hudSub or "")
    if hudSub == "hide" or hudSub == "off" then
      arrowSettings.hudHidden = true
      resyncActiveNavigationContext()
      ns.Compat.Print("Hid ForeverHub Tracker HUD (active navigation remains running; '/fh rg hud show' to restore).")
    elseif hudSub == "show" or hudSub == "on" then
      arrowSettings.hudHidden = false
      resyncActiveNavigationContext()
      ns.Compat.Print("Restored ForeverHub Tracker HUD.")
    elseif hudSub == "lock" then
      arrowSettings.hudLocked = true
      resyncActiveNavigationContext()
      ns.Compat.Print("Locked ForeverHub Tracker HUD position.")
    elseif hudSub == "unlock" then
      arrowSettings.hudLocked = false
      resyncActiveNavigationContext()
      ns.Compat.Print("Unlocked ForeverHub Tracker HUD (left-drag tracker to reposition).")
    elseif hudSub == "width" then
      local wNum = tonumber(hudVal)
      if not wNum or wNum < 200 or wNum > 440 then
        ns.Compat.Print("Usage: /fh rg hud width <200-440>")
        return
      end
      arrowSettings.hudWidth = math.floor(wNum + 0.5)
      resyncActiveNavigationContext()
      ns.Compat.Print(string.format("Set ForeverHub Tracker HUD width to %d.", arrowSettings.hudWidth))
    else
      arrowSettings.hudHidden = not (arrowSettings.hudHidden == true)
      resyncActiveNavigationContext()
      ns.Compat.Print("ForeverHub Tracker HUD: " .. (arrowSettings.hudHidden and "Hidden" or "Visible"))
    end
    return
  elseif sub == "" or sub == "status" then
    if sub == "" and ns.UI and ns.UI.Riverglades and ns.UI.Riverglades.Toggle then
      ns.UI.Riverglades.Toggle()
    end
    local progress = ns.State.GetRouteProgress()
    local eval = (ns.Domain.RouteProgress.Evaluate and ns.Domain.RouteProgress.Evaluate(nil, progress))
      or ns.Domain.RouteProgress.Reconcile(nil, progress)
    local counts = eval.counts or {}
    local navLabel = (ns.UI.Navigation and ns.UI.Navigation.lastStatus and ns.UI.Navigation.lastStatus.navigationLabel) or "Paused"
    local unresSuffix = (counts.blockedUnresolvedHistory and counts.blockedUnresolvedHistory > 0)
        and string.format(", %d unresolved-title", counts.blockedUnresolvedHistory)
      or ""
    ns.Compat.Print(
      string.format(
        "Riverglades Route (%s | Nav: %s | %d/%d done, %d skipped%s): %s",
        tostring(progress.mode),
        tostring(navLabel),
        counts.completed or 0,
        counts.total or 0,
        counts.skipped or 0,
        unresSuffix,
        formatRouteStepSummary(eval.nextAction)
      )
    )
    if counts.blockedUnresolvedHistory and counts.blockedUnresolvedHistory > 0 then
      ns.Compat.Print("Note: Unconfirmed pre-install custom title pickups are held back for safety ('/fh rg unresolved' or '/fh rg confirm all').")
    end
    if progress.mode == "paused" then
      ns.Compat.Print("Use '/fh rg start' to begin standalone navigation, or '/fh rg export rxp' to export to RXPGuides.")
    end
    return
  elseif sub == "start" then
    local ok, evalOrErr = ns.Domain.RouteProgress.Start()
    if not ok then
      ns.Compat.Print("Riverglades start failed: " .. tostring(evalOrErr))
      return
    end
    local arrowSettings = ns.State.GetArrowSettings()
    arrowSettings.hudHidden = false
    local navSt = ns.UI.Navigation.SyncFromEvaluation(evalOrErr)
    refreshWorldMapPinsIfLoaded()
    refreshRivergladesUIIfShown()
    ns.Compat.Print(
      string.format(
        "Started Riverglades route (Nav: %s) -> %s",
        tostring(navSt.navigationLabel),
        formatRouteStepSummary(evalOrErr.nextAction)
      )
    )
    return
  elseif sub == "pause" then
    local _, eval = ns.Domain.RouteProgress.Pause()
    ns.UI.Navigation.SyncFromEvaluation(eval)
    refreshWorldMapPinsIfLoaded()
    refreshRivergladesUIIfShown()
    ns.Compat.Print("Paused Riverglades route (owned waypoint cleared; progress preserved).")
    return
  elseif sub == "stop" then
    local resetSkips = (arg == "reset")
    local _, eval = ns.Domain.RouteProgress.Stop(nil, nil, nil, resetSkips)
    ns.UI.Navigation.SyncFromEvaluation(eval)
    refreshWorldMapPinsIfLoaded()
    refreshRivergladesUIIfShown()
    ns.Compat.Print(
      resetSkips and "Stopped Riverglades route and cleared manual skips."
        or "Stopped Riverglades route (use '/fh rg stop reset' to also clear manual skips)."
    )
    return
  elseif sub == "next" or sub == "skip" then
    local ok, resOrErr = ns.Domain.RouteProgress.SkipCurrentAction()
    if not ok then
      ns.Compat.Print("Riverglades next: " .. tostring(resOrErr))
      return
    end
    local progress = ns.State.GetRouteProgress()
    if progress.mode ~= "paused" then
      ns.UI.Navigation.SyncFromEvaluation(resOrErr.evaluation, progress)
    end
    refreshWorldMapPinsIfLoaded()
    refreshRivergladesUIIfShown()
    ns.Compat.Print(
      string.format(
        "Skipped step [%s]: %s (recorded explicit skip; quest NOT marked complete). Next -> %s",
        tostring(resOrErr.skippedActionID),
        tostring(resOrErr.skippedAction and resOrErr.skippedAction.title or ""),
        formatRouteStepSummary(resOrErr.nextAction)
      )
    )
    return
  elseif sub == "prev" or sub == "back" then
    local ok, resOrErr = ns.Domain.RouteProgress.StepPreviousAction()
    if not ok then
      ns.Compat.Print("Riverglades prev: " .. tostring(resOrErr))
      return
    end
    local progress = ns.State.GetRouteProgress()
    if progress.mode ~= "paused" then
      ns.UI.Navigation.SyncFromEvaluation(resOrErr.evaluation, progress)
    end
    refreshWorldMapPinsIfLoaded()
    refreshRivergladesUIIfShown()
    ns.Compat.Print("Stepped back to -> " .. formatRouteStepSummary(resOrErr.nextAction))
    return
  elseif sub == "group" then
    local progress = ns.State.GetRouteProgress()
    if arg == "off" or arg == "solo" then
      progress.includeGroupBranch = false
    elseif arg == "on" then
      progress.includeGroupBranch = true
    else
      progress.includeGroupBranch = not progress.includeGroupBranch
    end
    local eval = Events.FlushRouteReconcileNow()
    ns.Compat.Print(
      string.format(
        "Optional Krol'dok group dungeon branch: %s. Current -> %s",
        progress.includeGroupBranch and "ENABLED" or "DISABLED (strict solo)",
        formatRouteStepSummary(eval and eval.nextAction)
      )
    )
    return
  elseif sub == "elites" or sub == "elite" then
    local progress = ns.State.GetRouteProgress()
    if arg == "off" or arg == "solo" then
      progress.includeEliteBounties = false
    elseif arg == "on" then
      progress.includeEliteBounties = true
    else
      progress.includeEliteBounties = not progress.includeEliteBounties
    end
    local eval = Events.FlushRouteReconcileNow()
    ns.Compat.Print(
      string.format(
        "Optional [42+] Elite bounties (Ghostmaw, Old Rot-Chum, Blademaster Kaijo): %s. Current -> %s",
        progress.includeEliteBounties and "ENABLED" or "DISABLED (solo-safe; ready turn-ins still shown)",
        formatRouteStepSummary(eval and eval.nextAction)
      )
    )
    return
  elseif sub == "pins" or sub == "map" then
    local pinSettings = ns.State.GetWorldMapPinSettings()
    if arg == "" or arg == "status" then
      printWorldMapPinsStatus(nil)
    elseif arg == "on" then
      pinSettings.enabled = true
      refreshWorldMapPinsIfLoaded()
      printWorldMapPinsStatus("Enabled")
    elseif arg == "off" then
      pinSettings.enabled = false
      refreshWorldMapPinsIfLoaded()
      printWorldMapPinsStatus("Disabled")
    elseif arg == "available" or arg == "avail" then
      pinSettings.showAvailable = not (pinSettings.showAvailable ~= false)
      refreshWorldMapPinsIfLoaded()
      printWorldMapPinsStatus("Toggled Available (!)")
    elseif arg == "objectives" or arg == "obj" then
      pinSettings.showObjectives = not (pinSettings.showObjectives ~= false)
      refreshWorldMapPinsIfLoaded()
      printWorldMapPinsStatus("Toggled Objectives")
    elseif arg == "turnins" or arg == "turnin" then
      pinSettings.showTurnIns = not (pinSettings.showTurnIns ~= false)
      refreshWorldMapPinsIfLoaded()
      printWorldMapPinsStatus("Toggled Turn-Ins (?)")
    elseif arg == "reset" then
      ns.State.ResetWorldMapPinSettings()
      local progress = ns.State.GetRouteProgress()
      if ns.Domain.RouteProgress.ClearPinnedFocus then
        ns.Domain.RouteProgress.ClearPinnedFocus(nil, progress)
      end
      if progress.mode ~= "paused" and ns.UI and ns.UI.Navigation then
        local eval = ns.Domain.RouteProgress.Reconcile(nil, progress)
        ns.UI.Navigation.SyncFromEvaluation(eval, progress)
      end
      refreshWorldMapPinsIfLoaded()
      printWorldMapPinsStatus("Reset filters & cleared pinned focus")
    else
      ns.Compat.Print("Usage: /fh rg pins [status|on|off|available|objectives|turnins|reset]")
    end
    return
  elseif sub == "unresolved" then
    local route = ns.State.GetCompiledRivergladesRoute()
    local progress = ns.State.GetRouteProgress()
    local eval = ns.Domain.RouteProgress.Evaluate(route, progress)
    local list = ns.Domain.RoutePlanner.ListUnresolvedTitlePickups(eval, route)
    if #list == 0 then
      ns.Compat.Print("No unresolved pre-install custom title quests are currently blocking Riverglades pickups.")
      return
    end
    ns.Compat.Print(
      string.format(
        "=== Unresolved Custom Title Quests (%d) — pre-install completion cannot be queried without a numeric ID ===",
        #list
      )
    )
    for _, item in ipairs(list) do
      local xPct, yPct = 0, 0
      if item.destination then
        xPct, yPct = ns.Domain.RoutePlanner.NormalizedToPercent(item.destination.x01, item.destination.y01)
      end
      ns.Compat.Print(
        string.format(
          "  • %s (%s @ %.1f, %.1f) -> '/fh rg confirm %s'",
          tostring(item.questTitle),
          tostring(item.npcName or "Quest Giver"),
          xPct or 0,
          yPct or 0,
          tostring(string.gsub(tostring(item.questKey or ""), "^title:", ""))
        )
      )
    end
    ns.Compat.Print("If you have NOT completed these pre-install, run '/fh rg confirm <title>' or '/fh rg confirm all' to unlock pickup pins & routing.")
    return
  elseif sub == "confirm" then
    local route = ns.State.GetCompiledRivergladesRoute()
    local progress = ns.State.GetRouteProgress()
    if arg == "" then
      ns.Compat.Print("Usage: /fh rg confirm <quest title> | /fh rg confirm all (run '/fh rg unresolved' to inspect)")
      return
    end
    local confirmedTitles = {}
    local byTitleKey = (route and route.questsByTitleKey) or {}
    if arg == "all" then
      for qKey, qMeta in pairs(byTitleKey) do
        local compRes = ns.Compat.IsQuestCompletedResult(qKey)
        if type(compRes) == "table" and compRes.reason == "title_history_unresolved" then
          ns.State.ConfirmUnresolvedQuestIncomplete(qKey, progress)
          table.insert(confirmedTitles, tostring((qMeta and (qMeta.name or qMeta.title)) or qKey))
        end
      end
    else
      local needle = ns.Compat.NormalizeQuestTitle(arg) or arg
      for qKey, qMeta in pairs(byTitleKey) do
        local qTitle = tostring((qMeta and (qMeta.name or qMeta.title)) or qKey)
        local normQ = ns.Compat.NormalizeQuestTitle(qKey) or string.lower(qTitle)
        if qKey == arg or normQ == needle or string.find(normQ, needle, 1, true) then
          ns.State.ConfirmUnresolvedQuestIncomplete(qKey, progress)
          table.insert(confirmedTitles, qTitle)
        end
      end
    end
    if #confirmedTitles == 0 then
      ns.Compat.Print("No unresolved custom title quest matched '" .. tostring(arg) .. "'. Run '/fh rg unresolved' to list candidates.")
      return
    end
    table.sort(confirmedTitles)
    local eval = Events.FlushRouteReconcileNow()
    ns.Compat.Print(
      string.format(
        "Confirmed incomplete (%d): %s. Current -> %s",
        #confirmedTitles,
        table.concat(confirmedTitles, ", "),
        formatRouteStepSummary(eval and eval.nextAction)
      )
    )
    return
  elseif sub == "export" then
    if arg == "" or arg == "rxp" then
      local ok, status = ns.Bridges.RXPBridge.RegisterRivergladesGuide(true)
      if ok and status == "selected" then
        Events.FlushRouteReconcileNow()
      end
    else
      ns.Compat.Print("Usage: /fh rg export rxp")
    end
    return
  elseif sub == "mark" or sub == "capture" then
    local okCap, recOrErr = Events.CaptureQuestFieldTelemetry("manual_mark", nil, argRaw)
    if not okCap then
      ns.Compat.Print("Field capture failed (" .. tostring(recOrErr) .. ") — ensure player map coordinates are available.")
      return
    end
    local allCaps = ns.State.GetFieldCaptures and ns.State.GetFieldCaptures() or {}
    local qDesc = recOrErr.questTitle
      or (recOrErr.questID and ("Quest #" .. tostring(recOrErr.questID)))
      or "Unselected Quest"
    local noteSuffix = recOrErr.note and (" [" .. tostring(recOrErr.note) .. "]") or ""
    ns.Compat.Print(
      string.format(
        "Recorded field capture #%d [manual_mark] for %s at uiMapID=%d (%.2f, %.2f)%s -> ForeverHubDB.fieldCaptures.",
        #allCaps,
        tostring(qDesc),
        tonumber(recOrErr.uiMapID) or 0,
        (tonumber(recOrErr.x01) or 0) * 100.0,
        (tonumber(recOrErr.y01) or 0) * 100.0,
        noteSuffix
      )
    )
    return
  elseif sub == "doctor" then
    Events.RunRivergladesDoctor()
    return
  else
    ns.Compat.Print("Riverglades commands: /fh rg | /fh rg start | /fh rg pause | /fh rg next | /fh rg prev | /fh rg stop [reset] | /fh rg mark [note] | /fh rg unresolved | /fh rg confirm <quest|all> | /fh rg pins [on|off|available|reset] | /fh rg elites [on|off] | /fh rg group [on|off] | /fh rg export rxp | /fh rg doctor")
  end
end

function Events.HandleMountCommand(restRaw)
  ns.State.CaptureSessionMoneyBaselineIfUnset()
  local mt = ns.State.GetMountTracker()
  local cleaned = string.gsub(tostring(restRaw or ""), "^%s*(.-)%s*$", "%1")
  local sub, valStr = string.match(cleaned, "^(%S*)%s*(.-)$")
  sub = string.lower(sub or "")

  if sub == "honored" then
    mt.standingLabel = "Honored"
    mt.trainerQuoteCopper = 900000
    mt.quoteSource = "user_honored_90g"
    mt.quoteStatus = "user_confirmed"
    ns.Compat.Print("Confirmed Apprentice Riding target at 90g (Honored discount; includes 1st basic racial mount in Forever).")
  elseif sub == "unverified" or sub == "full" then
    mt.standingLabel = "Neutral/Base"
    mt.trainerQuoteCopper = 1000000
    mt.quoteSource = "base_100g"
    mt.quoteStatus = "user_confirmed"
    ns.Compat.Print("Confirmed Apprentice Riding target at 100g (undiscounted baseline; includes 1st basic racial mount).")
  elseif sub == "quote" then
    local goldNum = tonumber(valStr)
    if not goldNum or not ns.Compat.IsFiniteNumber(goldNum) or goldNum <= 0 then
      ns.Compat.Print("Usage: /fh mount quote <gold> (e.g. '/fh mount quote 90')")
      return
    end
    mt.standingLabel = "Custom Quote"
    mt.trainerQuoteCopper = math.floor(goldNum * 10000 + 0.5)
    mt.quoteSource = "user_custom_quote"
    mt.quoteStatus = "user_confirmed"
    ns.Compat.Print("Confirmed riding trainer quote target at " .. ns.Compat.FormatCopper(mt.trainerQuoteCopper) .. ".")
  elseif sub == "reserve" then
    local goldNum = tonumber(valStr)
    if not goldNum or not ns.Compat.IsFiniteNumber(goldNum) or goldNum < 0 then
      ns.Compat.Print("Usage: /fh mount reserve <gold> (e.g. '/fh mount reserve 5' to keep 5g buffer)")
      return
    end
    mt.cashReserveCopper = math.floor(goldNum * 10000 + 0.5)
    mt.reserveExplicitlySet = true
    ns.Compat.Print("Updated repair/flight/AH cash reserve buffer to " .. ns.Compat.FormatCopper(mt.cashReserveCopper) .. ".")
  elseif sub ~= "" and sub ~= "status" then
    ns.Compat.Print(
      "Mount commands: /fh mount | /fh mount honored (90g) | /fh mount full (100g) | /fh mount quote <gold> | /fh mount reserve <gold> (Note: 90g in Forever is discounted riding with 1st basic racial mount included; confirm your live trainer quote)."
    )
    return
  end

  local moneyRes = ns.Compat.GetPlayerMoneyCopper()
  local silkStatus = nil
  if ns.Domain and ns.Domain.Reservations and ns.Domain.Reservations.GetMaterialStatus then
    silkStatus = ns.Domain.Reservations.GetMaterialStatus(4306)
  end

  local report = ns.Domain.RewardValue.EvaluateMountShortfall(
    moneyRes,
    mt,
    silkStatus,
    ns.State.sessionStartMoneyCopper
  )

  if report.status ~= "ok" then
    ns.Compat.Print("Mount Tracker: Player money is currently unavailable (funding state unknown).")
    return
  end

  local deltaStr = ns.Compat.FormatSignedCopper(report.sessionDeltaCopper or 0)
  local quoteStateStr = (report.quoteStatus == "user_confirmed")
    and "Confirmed Quote"
    or "Unconfirmed 90g Default (1st basic mount incl.)"

  ns.Compat.Print(
    string.format(
      "=== ForeverHub Mount Tracker (%s [%s]: %s | Reserve Buffer: %s | Race: %s -> %s) ===",
      tostring(report.standingLabel),
      quoteStateStr,
      ns.Compat.FormatCopper(report.targetCopper),
      ns.Compat.FormatCopper(report.reserveCopper),
      tostring(mt.playerRaceToken or "Alliance"),
      tostring(mt.trainerFaction or "Home Faction Trainer")
    )
  )
  if report.quoteStatus ~= "user_confirmed" then
    ns.Compat.Print(
      "  |cffffcc00[Quote Unconfirmed]|r 90g is Forever's discounted Apprentice Riding default (includes your 1st basic racial mount). Verify at your riding trainer and confirm via '/fh mount quote <gold>' or '/fh mount honored'."
    )
  end
  if report.zeroReserveWarning then
    ns.Compat.Print(
      "  |cffffaa00[0c Reserve Warning]|r Reserve buffer is 0c — spending 100% of purse leaves nothing for repairs, flight paths, or AH deposits. Consider '/fh mount reserve 2'."
    )
  end

  if report.canAffordNow then
    ns.Compat.Print(
      string.format(
        "Measured Purse: %s (Spendable: %s) -> |cff00ff00TARGET REACHED|r (+%s above %s target) | Session Net: %s",
        ns.Compat.FormatCopper(report.currentCopper),
        ns.Compat.FormatCopper(report.spendableCopper),
        ns.Compat.FormatCopper(report.surplusCopper),
        quoteStateStr,
        deltaStr
      )
    )
  else
    ns.Compat.Print(
      string.format(
        "Measured Purse: %s (Spendable: %s) -> Shortfall: %s | Session Net: %s",
        ns.Compat.FormatCopper(report.currentCopper),
        ns.Compat.FormatCopper(report.spendableCopper),
        ns.Compat.FormatCopper(report.shortfallCopper),
        deltaStr
      )
    )
  end

  if report.silkStatus and (report.silkStatus.charOwned or 0) > 0 then
    local sb = report.silkBandageConversion or ns.Domain.RewardValue.EvaluateSilkBandageConversion(report.silkStatus)
    ns.Compat.Print(
      string.format(
        "Silk Cloth [4306] Check: %d owned (%d reserved for Crates/Writs, %d unreserved) -> Unrealized First Aid value: %d Heavy Silk Bandage(s) = %s (2s/Silk; 20 Silk = 40s; reserved Silk excluded).",
        report.silkStatus.charOwned or 0,
        report.silkStatus.reservedTotal or 0,
        report.silkStatus.unreservedTotal or 0,
        sb and sb.bandagesCraftable or 0,
        ns.Compat.FormatCopper(sb and sb.vendorCopper or 0)
      )
    )
  end
end

local function formatGoldHopSummary(eval)
  if not eval or not eval.activeStep then
    return "None"
  end
  local st = eval.activeStep
  if st.destination then
    local xPct, yPct = ns.Domain.GoldFarms.NormalizedToPercent(st.destination.x01, st.destination.y01)
    return string.format(
      "[Hop %d/%d] %s @ %s (%.1f, %.1f)",
      tonumber(eval.stepIndex) or 1,
      tonumber(eval.totalSteps) or 1,
      tostring(st.title),
      tostring(st.destination.zoneName or ""),
      xPct or 0,
      yPct or 0
    )
  end
  return string.format("[Hop %d/%d] %s", tonumber(eval.stepIndex) or 1, tonumber(eval.totalSteps) or 1, tostring(st.title))
end

local REVIEWED_DOCTOR_MAPS = { 2548, 1418, 1435, 1445, 1417, 1432, 1431, 1430, 1437, 1433 }

local function formatAddonProbe(addonNameStr)
  local info = ns.Compat.GetLoadedAddonInfo and ns.Compat.GetLoadedAddonInfo(addonNameStr) or { loaded = false, version = "missing" }
  if info.loaded then
    return string.format("%s=Loaded(%s)", addonNameStr, tostring(info.version or "unknown"))
  end
  return string.format("%s=NotLoaded", addonNameStr)
end

function Events.RunGoldFarmsDoctor()
  local catalog = ns.State.GetCompiledGoldFarms() or {}
  local meta = catalog.meta or {}
  local progress = ns.State.GetGoldFarmProgress()
  -- Strictly read-only evaluation (Astra P1-9 & Gate 6)
  local eval = ns.Domain.GoldFarms.Evaluate(catalog, progress)
  local sessSnap = ns.State.GetGoldFarmSessionSnapshot()
  local gphReport = ns.Domain.GoldFarms.EvaluateGPHAndMountETA(eval and eval.farm, sessSnap, ns.State.GetMountTracker())

  local gfTestSummary = "N/A"
  if ns.Domain.SelfTest and ns.Domain.SelfTest.GetDoctorSuiteSummary then
    gfTestSummary = ns.Domain.SelfTest.GetDoctorSuiteSummary("gold_farms")
  end

  local depSummary = table.concat({
    formatAddonProbe("RXPGuides"),
    formatAddonProbe("TomTom"),
    formatAddonProbe("Questie"),
    formatAddonProbe("QuestieDB"),
  }, " | ")

  local worldOkCount = 0
  local wpOkCount = 0
  local mapParts = {}
  for _, mID in ipairs(REVIEWED_DOCTOR_MAPS) do
    local ws = ns.Compat.GetMapWorldSizeYards and ns.Compat.GetMapWorldSizeYards(mID) or { status = "unavailable" }
    local cw = ns.Compat.CanSetNativeWaypoint and ns.Compat.CanSetNativeWaypoint(mID) or { status = "unavailable", value = false }
    local hasWorld = (ws.status == "ok")
    local hasWp = (cw.status == "ok" and cw.value == true)
    if hasWorld then
      worldOkCount = worldOkCount + 1
    end
    if hasWp then
      wpOkCount = wpOkCount + 1
    end
    table.insert(mapParts, string.format("%d(size=%s,wp=%s)", mID, hasWorld and "OK" or "No", hasWp and "OK" or "No"))
  end

  local navStatus = ns.UI.Navigation and ns.UI.Navigation.lastStatus or {}
  local ownerSnap = ns.UI.Navigation and ns.UI.Navigation.GetOwnerStateSnapshot and ns.UI.Navigation.GetOwnerStateSnapshot() or {}

  ns.Compat.Print(string.format("=== ForeverHub Gold Farms Doctor (v%s) ===", tostring(ns.version or "0.5.1")))
  ns.Compat.Print(
    string.format(
      "Catalog: %s (rev %s, %s %s Lv %s) | Content SHA: %s | Manifest SHA: %s",
      tostring(meta.catalogID or "missing"),
      tostring(meta.revision or "?"),
      tostring(meta.faction or "Alliance"),
      tostring(meta.targetClass or "MAGE"),
      tostring(meta.targetLevel or 40),
      string.sub(tostring(meta.compiledContentSha256 or "unknown"), 1, 16),
      string.sub(tostring(meta.sourceManifestHash or "unknown"), 1, 16)
    )
  )
  ns.Compat.Print(
    string.format(
      "Candidates: %d | Quarantined Traps: %d | Verified NPCs: %d | GF SelfTests: %s",
      tonumber(meta.verifiedFarmCount) or 0,
      tonumber(meta.quarantinedFarmCount) or 0,
      tonumber(meta.verifiedNpcCount) or 0,
      gfTestSummary
    )
  )
  ns.Compat.Print("Dependencies: " .. depSummary)
  ns.Compat.Print(
    string.format(
      "Map Capabilities (%d/%d world-yard transforms, %d/%d native waypoints): %s",
      worldOkCount,
      #REVIEWED_DOCTOR_MAPS,
      wpOkCount,
      #REVIEWED_DOCTOR_MAPS,
      table.concat(mapParts, ", ")
    )
  )
  ns.Compat.Print(
    string.format(
      "Nav Owner: ctx=%s | provider=%s | gen=%s | pendingRelease=%s | activeNav=%s",
      tostring(ownerSnap.ownerContext or "none"),
      tostring(ownerSnap.provider or "none"),
      tostring(ownerSnap.generation or 0),
      tostring(ownerSnap.pendingRelease or false),
      tostring(navStatus.activeProvider or "none")
    )
  )
  local phaseDetail
  if (progress and progress.mode == "rxp") or not gphReport.phaseTimingAvailable then
    phaseDetail = string.format(
      "phaseTiming=Unavailable(RXP, rxp=%ds, camp=%ds, transit/service=%ds)",
      gphReport.rxpUntrackedSeconds or 0,
      gphReport.campSeconds or 0,
      gphReport.travelAndServiceSeconds or 0
    )
  else
    phaseDetail = string.format(
      "camp=%ds, transit/service=%ds",
      gphReport.campSeconds or 0,
      gphReport.travelAndServiceSeconds or 0
    )
  end
  ns.Compat.Print(
    string.format(
      "State: mode=%s | selected=%s | pinned=%s | Net Purse Change / Active Hr: %s (%s, contaminated=%s)",
      tostring(progress and progress.mode or "paused"),
      tostring(progress and progress.selectedFarmID or "none"),
      tostring(progress and progress.manualPinnedStepID or "none"),
      tostring(gphReport.liveLabel),
      phaseDetail,
      tostring(gphReport.contaminated or false)
    )
  )
  if eval and eval.farm then
    ns.Compat.Print("Current Hop: " .. formatGoldHopSummary(eval))
  end
end

function Events.PrintGoldFarmsList()
  local catalog = ns.State.GetCompiledGoldFarms()
  if not catalog or type(catalog.farms) ~= "table" then
    ns.Compat.Print("Gold farms catalog is not loaded.")
    return
  end

  ns.Compat.Print("=== ForeverHub Verified Alliance Level 40 Mage Gold Farm Candidates ===")
  for _, farm in ipairs(catalog.farms) do
    local gphMeta = farm.gphMeta or {}
    local targetNames = {}
    for _, t in ipairs(farm.targets or {}) do
      local xPct, yPct = ns.Domain.GoldFarms.NormalizedToPercent(t.x01, t.y01)
      table.insert(
        targetNames,
        string.format("%s (Lv %d-%d @ %.1f, %.1f)", tostring(t.name), t.minLevel or 40, t.maxLevel or 40, xPct or 0, yPct or 0)
      )
    end
    ns.Compat.Print(
      string.format(
        "Candidate %d [%s] %s (Lv %s) — Community Est.: %d-%dg/hr (Unverified Ref; not a measured ranking)",
        tonumber(farm.candidateOrder or farm.rank) or 0,
        tostring(farm.farmID),
        tostring(farm.title),
        tostring(farm.recommendedLevelRange or "40"),
        tonumber(gphMeta.lowGold) or 0,
        tonumber(gphMeta.highGold) or 0
      )
    )
    ns.Compat.Print("  How to Get There: " .. tostring(farm.howToGetThereSummary or ""))
    ns.Compat.Print("  What to Kill: " .. table.concat(targetNames, "; "))
    local warnings = ns.Domain.GoldFarms.GetReservationWarningsForFarm(farm)
    for _, w in ipairs(warnings) do
      ns.Compat.Print("  |cffffaa00" .. tostring(w.message) .. "|r")
    end
  end

  if type(catalog.quarantinedFarms) == "table" and #catalog.quarantinedFarms > 0 then
    ns.Compat.Print("--- Quarantined 2019 Classic Trap Farms (Do NOT Run at Lv 40 in Forever) ---")
    for _, qf in ipairs(catalog.quarantinedFarms) do
      ns.Compat.Print(string.format("  [SKIP] %s — %s", tostring(qf.title), tostring(qf.reason)))
    end
  end
  ns.Compat.Print("Start navigation + Net Purse Change / Active Hr meter with '/fh gold start <1-5>', or '/fh gold' to open window.")
end

function Events.HandleGoldSubcommand(subRaw)
  ns.State.CaptureSessionMoneyBaselineIfUnset()
  local cleaned = string.gsub(tostring(subRaw or ""), "^%s*(.-)%s*$", "%1")
  local sub, arg = string.match(cleaned, "^(%S*)%s*(.-)$")
  sub = string.lower(sub or "")
  arg = string.gsub(tostring(arg or ""), "^%s*(.-)%s*$", "%1")

  if sub == "" then
    local toggled = false
    if ns.UI and ns.UI.GoldFarms and ns.UI.GoldFarms.Toggle then
      toggled = ns.UI.GoldFarms.Toggle()
    end
    local progress = ns.State.GetGoldFarmProgress()
    local eval = ns.Domain.GoldFarms.Evaluate(nil, progress)
    local sessSnap = ns.State.GetGoldFarmSessionSnapshot()
    local gphReport = ns.Domain.GoldFarms.EvaluateGPHAndMountETA(eval and eval.farm, sessSnap, ns.State.GetMountTracker())
    if progress.mode == "paused" then
      if not toggled then
        Events.PrintGoldFarmsList()
      else
        ns.Compat.Print("Opened ForeverHub Gold Farms advisor. Click 'Navigate (Arrow / Pin)' or run '/fh gold start 1'.")
      end
    else
      local navLabel = (ns.UI.Navigation and ns.UI.Navigation.lastStatus and ns.UI.Navigation.lastStatus.navigationLabel) or "Active"
      ns.Compat.Print(
        string.format(
          "Gold Farm (%s | Nav: %s): %s -> %s | Net Purse Change / Active Hr: %s",
          tostring(progress.mode),
          tostring(navLabel),
          tostring(eval.farm and eval.farm.title or progress.selectedFarmID),
          formatGoldHopSummary(eval),
          tostring(gphReport.liveLabel)
        )
      )
    end
    return
  elseif sub == "status" then
    local progress = ns.State.GetGoldFarmProgress()
    -- Strictly read-only status inspection (Astra P1-9 & Gate 6)
    local eval = ns.Domain.GoldFarms.Evaluate(nil, progress)
    local sessSnap = ns.State.GetGoldFarmSessionSnapshot()
    local gphReport = ns.Domain.GoldFarms.EvaluateGPHAndMountETA(eval and eval.farm, sessSnap, ns.State.GetMountTracker())
    local navLabel = (progress.mode ~= "paused"
      and ns.UI.Navigation
      and ns.UI.Navigation.activeContext == "gold_farm"
      and ns.UI.Navigation.lastStatus
      and ns.UI.Navigation.lastStatus.navigationLabel) or "Paused"
    if eval and eval.farm then
      ns.Compat.Print(
        string.format(
          "Gold Farm [Candidate %d %s] (%s | Nav: %s) | %s | Ref: %s | Net Purse Change / Active Hr: %s",
          tonumber(eval.farm.candidateOrder or eval.farm.rank) or 1,
          tostring(eval.farm.shortLabel or eval.farm.farmID),
          tostring(progress.mode),
          tostring(navLabel),
          formatGoldHopSummary(eval),
          tostring(gphReport.communityLabel),
          tostring(gphReport.liveLabel)
        )
      )
    else
      ns.Compat.Print("Gold Farm: Paused (no farm selected). Use '/fh gold list' or '/fh gold start 1'.")
    end
    return
  elseif sub == "list" then
    Events.PrintGoldFarmsList()
    return
  elseif sub == "start" then
    local ok, evalOrErr = ns.Domain.GoldFarms.Start(arg)
    if not ok then
      ns.Compat.Print("Gold farm start failed: " .. tostring(evalOrErr))
      return
    end
    local arrowSettings = ns.State.GetArrowSettings()
    arrowSettings.hudHidden = false
    local navSt = ns.UI.Navigation.SyncFromGoldFarmEvaluation(evalOrErr)
    local farm = evalOrErr.farm
    local gphMeta = farm and farm.gphMeta or {}
    ns.Compat.Print(
      string.format(
        "Started Gold Farm Candidate %d: %s (Nav: %s | Community Est.: %d-%dg/hr Unverified Ref)",
        tonumber(farm and (farm.candidateOrder or farm.rank)) or 1,
        tostring(farm and farm.title or ""),
        tostring(navSt.navigationLabel),
        tonumber(gphMeta.lowGold) or 0,
        tonumber(gphMeta.highGold) or 0
      )
    )
    ns.Compat.Print("  Current Hop -> " .. formatGoldHopSummary(evalOrErr))
    local warnings = ns.Domain.GoldFarms.GetReservationWarningsForFarm(farm)
    for _, w in ipairs(warnings) do
      ns.Compat.Print("  |cffffaa00" .. tostring(w.message) .. "|r")
    end
    if ns.UI and ns.UI.GoldFarms and ns.UI.GoldFarms.RefreshIfShown then
      ns.UI.GoldFarms.RefreshIfShown()
    end
    return
  elseif sub == "next" or sub == "hop" then
    local ok, evalOrErr = ns.Domain.GoldFarms.NextHop()
    if not ok then
      ns.Compat.Print("Gold farm next: " .. tostring(evalOrErr))
      return
    end
    local progress = ns.State.GetGoldFarmProgress()
    if progress.mode ~= "paused" then
      ns.UI.Navigation.SyncFromGoldFarmEvaluation(evalOrErr, progress)
    end
    ns.Compat.Print("Gold Farm Next Hop -> " .. formatGoldHopSummary(evalOrErr))
    if ns.UI and ns.UI.GoldFarms and ns.UI.GoldFarms.RefreshIfShown then
      ns.UI.GoldFarms.RefreshIfShown()
    end
    return
  elseif sub == "prev" or sub == "back" then
    local ok, evalOrErr = ns.Domain.GoldFarms.PrevHop()
    if not ok then
      ns.Compat.Print("Gold farm prev: " .. tostring(evalOrErr))
      return
    end
    local progress = ns.State.GetGoldFarmProgress()
    if progress.mode ~= "paused" then
      ns.UI.Navigation.SyncFromGoldFarmEvaluation(evalOrErr, progress)
    end
    ns.Compat.Print("Gold Farm Stepped Back -> " .. formatGoldHopSummary(evalOrErr))
    if ns.UI and ns.UI.GoldFarms and ns.UI.GoldFarms.RefreshIfShown then
      ns.UI.GoldFarms.RefreshIfShown()
    end
    return
  elseif sub == "pause" then
    local _, eval = ns.Domain.GoldFarms.Pause()
    ns.UI.Navigation.SyncFromGoldFarmEvaluation(eval)
    ns.Compat.Print("Paused Gold Farm navigation & Net Purse Change / Active Hr timer.")
    if ns.UI and ns.UI.GoldFarms and ns.UI.GoldFarms.RefreshIfShown then
      ns.UI.GoldFarms.RefreshIfShown()
    end
    return
  elseif sub == "stop" then
    local resetAll = (string.lower(arg) == "reset")
    local _, eval = ns.Domain.GoldFarms.Stop(resetAll)
    ns.UI.Navigation.SyncFromGoldFarmEvaluation(eval)
    ns.Compat.Print(
      resetAll and "Stopped Gold Farm navigation and reset travel hops + Net Purse Change / Active Hr meter."
        or "Stopped Gold Farm navigation (use '/fh gold reset' to zero the session cash-flow meter)."
    )
    if ns.UI and ns.UI.GoldFarms and ns.UI.GoldFarms.RefreshIfShown then
      ns.UI.GoldFarms.RefreshIfShown()
    end
    return
  elseif sub == "reenter" or sub == "reroute" then
    local ok, evalOrErr = ns.Domain.GoldFarms.RestartEntryFromCurrentZone()
    if not ok then
      ns.Compat.Print("Gold farm re-route: " .. tostring(evalOrErr))
      return
    end
    local progress = ns.State.GetGoldFarmProgress()
    if progress and progress.mode ~= "paused" then
      ns.UI.Navigation.SyncFromGoldFarmEvaluation(evalOrErr, progress)
    end
    ns.Compat.Print("Recomputed Gold Farm entry from current zone -> " .. formatGoldHopSummary(evalOrErr))
    if ns.UI and ns.UI.GoldFarms and ns.UI.GoldFarms.RefreshIfShown then
      ns.UI.GoldFarms.RefreshIfShown()
    end
    return
  elseif sub == "reset" then
    local progress = ns.State.GetGoldFarmProgress()
    local keepActive = (progress and progress.mode ~= "paused")
    local resetPhase = nil
    if progress and progress.mode == "rxp" then
      resetPhase = "rxp_untracked"
    elseif progress and progress.selectedFarmID then
      local curEval = ns.Domain.GoldFarms.Evaluate(nil, progress)
      resetPhase = (curEval and curEval.activeStep and curEval.activeStep.kind == "grind") and "camp" or "travel_service"
    end
    ns.State.ResetGoldFarmSession(progress and progress.selectedFarmID, keepActive, nil, nil, resetPhase)
    ns.Compat.Print("Reset Net Purse Change / Active Hr meter baseline to current purse (clean interval started).")
    if ns.UI and ns.UI.GoldFarms and ns.UI.GoldFarms.RefreshIfShown then
      ns.UI.GoldFarms.RefreshIfShown()
    end
    return
  elseif sub == "export" then
    local rxpSub, farmArg = string.match(arg, "^(%S*)%s*(.-)$")
    rxpSub = string.lower(rxpSub or "")
    farmArg = string.gsub(tostring(farmArg or ""), "^%s*(.-)%s*$", "%1")
    if rxpSub == "" or rxpSub == "rxp" then
      if farmArg ~= "" and string.lower(farmArg) ~= "all" then
        local ok, status = ns.Bridges.RXPBridge.RegisterGoldFarmGuide(farmArg, true)
        if ok and status == "selected" then
          local progress = ns.State.GetGoldFarmProgress()
          if progress.mode ~= "paused" then
            ns.UI.Navigation.SyncFromGoldFarmEvaluation(nil, progress)
          end
        end
      else
        ns.Bridges.RXPBridge.RegisterAllGoldFarmGuides(true)
      end
    else
      ns.Compat.Print("Usage: /fh gold export rxp [1-5 | farmID | all]")
    end
    return
  elseif sub == "doctor" then
    Events.RunGoldFarmsDoctor()
    return
  else
    -- Convenience: allow `/fh gold 1` or `/fh gold badlands` directly!
    local directFarm = ns.Domain.GoldFarms.ResolveFarm(cleaned)
    if directFarm then
      Events.HandleGoldSubcommand("start " .. directFarm.farmID)
      return
    end
    ns.Compat.Print("Gold Farm commands: /fh gold | /fh gold list | /fh gold start <1-5|zone> | /fh gold reenter | /fh gold next | /fh gold prev | /fh gold pause | /fh gold stop [reset] | /fh gold reset | /fh gold export rxp [farm] | /fh gold doctor")
  end
end

resyncActiveNavigationContext = function()
  if not (ns.UI and ns.UI.Navigation) then
    return
  end
  ns.UI.Navigation.RefreshArrowSettings()
  local ctx = ns.UI.Navigation.activeContext
  if ctx == "gold_farm" then
    local gProg = ns.State.GetGoldFarmProgress()
    if gProg and gProg.mode ~= "paused" then
      ns.UI.Navigation.SyncFromGoldFarmEvaluation(nil, gProg)
    end
  else
    local rProg = ns.State.GetRouteProgress()
    if rProg and rProg.mode ~= "paused" then
      ns.UI.Navigation.SyncFromEvaluation(nil, rProg)
    end
  end
end

function Events.HandleArrowCommand(subRaw)
  local cleaned = string.gsub(tostring(subRaw or ""), "^%s*(.-)%s*$", "%1")
  local sub, arg = string.match(cleaned, "^(%S*)%s*(.-)$")
  sub = string.lower(sub or "")
  arg = string.lower(string.gsub(tostring(arg or ""), "^%s*(.-)%s*$", "%1"))

  local settings = ns.State.GetArrowSettings()
  if sub == "" or sub == "status" then
    local snap = ns.UI.Navigation and ns.UI.Navigation.GetLiveArrowSnapshot and ns.UI.Navigation.GetLiveArrowSnapshot() or {}
    local distInfo = (type(snap.yards) == "number") and string.format(" | Distance: %.0f yds", snap.yards) or ""
    ns.Compat.Print(
      string.format(
        "ForeverHub Arrow: %s | Mode: %s | Renderer: %s | Lock: %s | Scale: %.2fx | Style: %s (%s) | Live: %s%s",
        settings.enabled and "Enabled" or "Hidden",
        settings.dockedInHud ~= false and "Docked in HUD" or "Floating",
        tostring(settings.renderer or "auto"),
        settings.locked and "Locked" or "Movable (left-drag)",
        tonumber(settings.scale) or 1.0,
        tostring(settings.style or "auto"),
        tostring(snap.resolvedTextureMode or "auto"),
        tostring(snap.status or "idle"),
        distInfo
      )
    )
    ns.Compat.Print("Usage: /fh arrow [on|off|toggle|dock|undock|renderer <auto|foreverhub|tomtom|off>|lock|unlock|scale <0.6-2.0>|style <auto|custom|classic>|always|reset]")
    return
  elseif sub == "dock" then
    settings.dockedInHud = true
    resyncActiveNavigationContext()
    ns.Compat.Print("Docked ForeverHub directional arrow inside the Tracker HUD (floating arrow hidden while HUD is shown).")
    return
  elseif sub == "undock" or sub == "float" then
    settings.dockedInHud = false
    resyncActiveNavigationContext()
    ns.Compat.Print("Undocked ForeverHub directional arrow to a floating widget.")
    return
  elseif sub == "on" or sub == "show" or sub == "enable" then
    settings.enabled = true
    if settings.renderer == "off" then
      settings.renderer = settings.showWhenTomTomActive and "foreverhub" or "auto"
    end
    resyncActiveNavigationContext()
    ns.Compat.Print("ForeverHub directional arrow enabled (renderer: " .. tostring(settings.renderer or "auto") .. ").")
    return
  elseif sub == "off" or sub == "hide" or sub == "disable" then
    settings.enabled = false
    settings.renderer = "off"
    resyncActiveNavigationContext()
    ns.Compat.Print("ForeverHub floating arrow hidden; HUD distance tracking remains active (use '/fh arrow on' to re-enable).")
    return
  elseif sub == "toggle" then
    settings.enabled = not settings.enabled
    if not settings.enabled then
      settings.renderer = "off"
    elseif settings.renderer == "off" then
      settings.renderer = settings.showWhenTomTomActive and "foreverhub" or "auto"
    end
    resyncActiveNavigationContext()
    ns.Compat.Print("ForeverHub directional arrow: " .. (settings.enabled and "Enabled" or "Hidden"))
    return
  elseif sub == "renderer" then
    if arg ~= "auto" and arg ~= "foreverhub" and arg ~= "tomtom" and arg ~= "off" then
      ns.Compat.Print("Usage: /fh arrow renderer <auto|foreverhub|tomtom|off>")
      return
    end
    settings.renderer = arg
    settings.enabled = (arg ~= "off")
    settings.showWhenTomTomActive = (arg == "foreverhub")
    resyncActiveNavigationContext()
    ns.Compat.Print("Set ForeverHub arrow renderer mode to: " .. arg)
    return
  elseif sub == "lock" then
    settings.locked = true
    if ns.UI and ns.UI.Navigation and ns.UI.Navigation.RefreshArrowSettings then
      ns.UI.Navigation.RefreshArrowSettings()
    end
    ns.Compat.Print("Locked ForeverHub arrow position — arrow is now click-through (use '/fh arrow unlock' to drag).")
    return
  elseif sub == "unlock" then
    settings.locked = false
    if ns.UI and ns.UI.Navigation and ns.UI.Navigation.RefreshArrowSettings then
      ns.UI.Navigation.RefreshArrowSettings()
    end
    ns.Compat.Print("Unlocked ForeverHub arrow — left-drag the arrow to position it anywhere on screen.")
    return
  elseif sub == "reset" then
    ns.State.ResetArrowSettingsPosition()
    resyncActiveNavigationContext()
    ns.Compat.Print("Reset ForeverHub arrow position above center screen (scale 1.0x).")
    return
  elseif sub == "scale" then
    local val = tonumber(arg)
    if not val or val < 0.6 or val > 2.0 then
      ns.Compat.Print("Usage: /fh arrow scale <0.6 - 2.0> (e.g. '/fh arrow scale 1.2')")
      return
    end
    settings.scale = math.floor(val * 100 + 0.5) / 100
    resyncActiveNavigationContext()
    ns.Compat.Print(string.format("Set ForeverHub arrow scale to %.2fx.", settings.scale))
    return
  elseif sub == "style" then
    if arg ~= "auto" and arg ~= "custom" and arg ~= "classic" then
      ns.Compat.Print("Usage: /fh arrow style <auto|custom|classic>")
      return
    end
    settings.style = arg
    if ns.UI and ns.UI.Navigation and ns.UI.Navigation.arrowFrame then
      ns.UI.Navigation.arrowFrame.appliedTexturePath = nil
    end
    resyncActiveNavigationContext()
    ns.Compat.Print("Set ForeverHub arrow style to: " .. arg)
    return
  elseif sub == "always" or sub == "tomtom" then
    settings.showWhenTomTomActive = not settings.showWhenTomTomActive
    settings.enabled = true
    settings.renderer = settings.showWhenTomTomActive and "foreverhub" or "auto"
    resyncActiveNavigationContext()
    ns.Compat.Print("Show ForeverHub arrow alongside TomTom on classic maps: " .. tostring(settings.showWhenTomTomActive))
    return
  else
    ns.Compat.Print("Usage: /fh arrow [on|off|toggle|renderer <auto|foreverhub|tomtom|off>|lock|unlock|scale <0.6-2.0>|style <auto|custom|classic>|always|reset]")
  end
end

local function recordInventoryTraceIfEnabled(sourceEvent)
  if not (ns.Domain and ns.Domain.Diagnostics and ns.Domain.Diagnostics.RecordInventoryObservation) then
    return
  end
  local snap = ns.Providers.Inventory and ns.Providers.Inventory.GetAggregatedSnapshot and ns.Providers.Inventory.GetAggregatedSnapshot() or {}
  local bagCounts = {}
  local bankCounts = {}
  for itemID, entry in pairs(snap) do
    bagCounts[itemID] = entry.bagCount or 0
    bankCounts[itemID] = entry.bankCount or 0
  end
  ns.Domain.Diagnostics.RecordInventoryObservation(sourceEvent, bagCounts, bankCounts)
end

Events.lastObjectiveProgressByQuest = Events.lastObjectiveProgressByQuest or {}
Events.objectiveBaselineSeeded = Events.objectiveBaselineSeeded or false

local function collectCandidateActiveQuestRefs()
  local refs = {}
  local seen = {}
  local function addRef(qRef, title)
    local key = tostring(qRef)
    if qRef ~= nil and not seen[key] then
      seen[key] = true
      table.insert(refs, { questRef = qRef, title = title })
    end
  end
  if ns.Compat and ns.Compat.ScanLiveQuestLog then
    local scan = ns.Compat.ScanLiveQuestLog(false)
    if scan and scan.available and type(scan.byID) == "table" then
      for qid, row in pairs(scan.byID) do
        addRef(tonumber(qid) or qid, row and row.title or nil)
      end
    end
  end
  local route = ns.State and ns.State.GetCompiledRivergladesRoute and ns.State.GetCompiledRivergladesRoute() or nil
  if type(route) == "table" and ns.Compat and ns.Compat.IsOnQuestResult then
    for qid, meta in pairs(route.questsByID or {}) do
      local nQid = tonumber(qid)
      if nQid and not seen[tostring(nQid)] then
        local onRes = ns.Compat.IsOnQuestResult(nQid)
        if type(onRes) == "table" and onRes.status == "ok" and onRes.value == true then
          addRef(nQid, meta and meta.name or nil)
        end
      end
    end
    for qKey, meta in pairs(route.questsByTitleKey or {}) do
      local kQid = meta and tonumber(meta.knownQuestID) or nil
      local effRef = kQid or qKey
      if not seen[tostring(effRef)] then
        local onRes = ns.Compat.IsOnQuestResult(qKey)
        if type(onRes) == "table" and onRes.status == "ok" and onRes.value == true then
          addRef(effRef, meta and meta.name or nil)
        end
      end
    end
  end
  return refs
end

local function snapshotObjectiveState(objRes)
  local snap = {
    allFinished = false,
  }
  if type(objRes) == "table" and objRes.status == "ok" then
    snap.allFinished = (objRes.allFinished == true)
    if type(objRes.objectives) == "table" then
      for idx, row in ipairs(objRes.objectives) do
        snap[idx] = {
          fulfilled = tonumber(row.numFulfilled) or ((row.finished == true) and 1 or 0),
          finished = (row.finished == true),
          text = row.text,
        }
      end
    end
  end
  return snap
end

function Events.SeedObjectiveTelemetryBaseline()
  Events.lastObjectiveProgressByQuest = {}
  if not ns.Compat or not ns.Compat.GetQuestObjectivesResult then
    Events.objectiveBaselineSeeded = true
    return
  end
  for _, item in ipairs(collectCandidateActiveQuestRefs()) do
    local objRes = ns.Compat.GetQuestObjectivesResult(item.questRef)
    Events.lastObjectiveProgressByQuest[tostring(item.questRef)] = snapshotObjectiveState(objRes)
  end
  Events.objectiveBaselineSeeded = true
end

function Events.CaptureQuestFieldTelemetry(kind, explicitQuestID, noteText)
  if not ns.State or type(ns.State.RecordFieldCapture) ~= "function" or not ns.Compat then
    return false, "telemetry_unavailable"
  end
  local posStatus, mapID, x01, y01, posReason = ns.Compat.GetPlayerPosition01Raw()
  if posStatus ~= "ok" or not mapID or not x01 or not y01 then
    return false, posReason or "position_unavailable"
  end

  local dialog = ns.Compat.lastDialogQuest
  local now = ns.Compat.NowSeconds and ns.Compat.NowSeconds() or 0
  local freshDialog = (type(dialog) == "table" and (now - (tonumber(dialog.capturedAt) or 0)) <= 8.0) and dialog or nil

  if kind == "manual_mark" then
    local sel = ns.Compat.GetSelectedQuestInfo and ns.Compat.GetSelectedQuestInfo() or { available = false }
    local qid = sel.available and tonumber(sel.questID) or tonumber(explicitQuestID)
    local qTitle = sel.available and sel.title or nil
    if not qid and not qTitle then
      local progress = ns.State.GetRouteProgress and ns.State.GetRouteProgress() or nil
      if progress and progress.mode == "standalone" and ns.Domain and ns.Domain.RouteProgress and ns.Domain.RouteProgress.Evaluate then
        local eval = ns.Domain.RouteProgress.Evaluate(nil, progress)
        local act = eval and eval.nextAction or nil
        if act then
          local meta = ns.Compat.LookupRouteQuestMeta and ns.Compat.LookupRouteQuestMeta(act.questKey or act.questID) or nil
          qid = tonumber(act.questID) or (meta and tonumber(meta.knownQuestID)) or nil
          qTitle = (meta and meta.name) or act.title
        end
      end
    end
    if qid and not qTitle and ns.Compat.LookupRouteQuestMeta then
      local meta = ns.Compat.LookupRouteQuestMeta(qid)
      qTitle = meta and meta.name or nil
    end
    return ns.State.RecordFieldCapture({
      kind = "manual_mark",
      questID = qid,
      questTitle = qTitle,
      note = noteText,
      uiMapID = mapID,
      x01 = x01,
      y01 = y01,
    })
  elseif kind == "quest_accepted" or kind == "quest_turned_in" then
    local qid = tonumber(explicitQuestID) or (freshDialog and tonumber(freshDialog.questID)) or nil
    local meta = qid and ns.Compat.LookupRouteQuestMeta and ns.Compat.LookupRouteQuestMeta(qid) or nil
    local qTitle = (meta and meta.name)
      or (freshDialog and freshDialog.rawTitle)
      or nil
    if qid and kind == "quest_accepted" then
      Events.lastObjectiveProgressByQuest[tostring(qid)] = {}
      Events.objectiveBaselineSeeded = true
    elseif qid and kind == "quest_turned_in" then
      Events.lastObjectiveProgressByQuest[tostring(qid)] = nil
    end
    return ns.State.RecordFieldCapture({
      kind = kind,
      questID = qid,
      questTitle = qTitle,
      npcID = freshDialog and tonumber(freshDialog.npcID) or nil,
      npcName = freshDialog and freshDialog.npcName or nil,
      uiMapID = mapID,
      x01 = x01,
      y01 = y01,
    })
  elseif kind == "objective_scan" then
    if not Events.objectiveBaselineSeeded then
      Events.SeedObjectiveTelemetryBaseline()
      return false, "seeded_baseline"
    end
    local recordedCount = 0
    local lastRec = nil
    for _, item in ipairs(collectCandidateActiveQuestRefs()) do
      local qKey = tostring(item.questRef)
      local qid = tonumber(item.questRef)
      local meta = ns.Compat.LookupRouteQuestMeta and ns.Compat.LookupRouteQuestMeta(item.questRef) or nil
      local qTitle = item.title or (meta and meta.name) or nil
      local objRes = ns.Compat.GetQuestObjectivesResult and ns.Compat.GetQuestObjectivesResult(item.questRef) or nil
      local curSnap = snapshotObjectiveState(objRes)
      local prevSnap = Events.lastObjectiveProgressByQuest[qKey]
      if prevSnap ~= nil then
        local questRecordedThisTick = false
        for idx, curRow in ipairs(curSnap) do
          local prevRow = prevSnap[idx]
          local prevFulfilled = prevRow and prevRow.fulfilled or 0
          local prevFinished = prevRow and prevRow.finished or false
          if curRow.fulfilled > prevFulfilled or (curRow.finished and not prevFinished) then
            local ok, rec = ns.State.RecordFieldCapture({
              kind = "objective_progress",
              questID = qid,
              questTitle = qTitle,
              objectiveIndex = idx,
              objectiveText = curRow.text,
              uiMapID = mapID,
              x01 = x01,
              y01 = y01,
            })
            if ok then
              recordedCount = recordedCount + 1
              lastRec = rec
              questRecordedThisTick = true
            end
          end
        end
        if not questRecordedThisTick and curSnap.allFinished == true and prevSnap.allFinished ~= true then
          local fallbackIdx = 1
          local fallbackText = "Ready to turn in"
          for idx, prevRow in ipairs(prevSnap) do
            if prevRow and not prevRow.finished then
              fallbackIdx = idx
              fallbackText = prevRow.text or fallbackText
              break
            end
          end
          local ok, rec = ns.State.RecordFieldCapture({
            kind = "objective_progress",
            questID = qid,
            questTitle = qTitle,
            objectiveIndex = fallbackIdx,
            objectiveText = fallbackText,
            uiMapID = mapID,
            x01 = x01,
            y01 = y01,
          })
          if ok then
            recordedCount = recordedCount + 1
            lastRec = rec
          end
        end
      end
      Events.lastObjectiveProgressByQuest[qKey] = curSnap
    end
    return (recordedCount > 0), lastRec
  end
  return false, "unsupported_kind"
end

local function handleSlashCommand(msg)
  local raw = string.gsub(tostring(msg or ""), "^%s*(.-)%s*$", "%1")
  local cmd, rest = string.match(raw, "^(%S+)%s*(.-)$")
  cmd = string.lower(cmd or "")

  if cmd == "" or cmd == "crates" or cmd == "ui" then
    local tabArg = string.lower(string.gsub(tostring(rest or ""), "^%s*(.-)%s*$", "%1"))
    if cmd == "ui" and (tabArg == "rg" or tabArg == "riverglades") and ns.UI and ns.UI.Workspace then
      if ns.UI.Crates and ns.UI.Crates.EnsureInitialized then
        ns.UI.Crates.EnsureInitialized()
      end
      ns.UI.Workspace.Toggle("riverglades")
    elseif cmd == "ui" and (tabArg == "gold" or tabArg == "mount") and ns.UI and ns.UI.Workspace then
      if ns.UI.Crates and ns.UI.Crates.EnsureInitialized then
        ns.UI.Crates.EnsureInitialized()
      end
      ns.UI.Workspace.Toggle("gold")
    elseif cmd == "" and ns.UI and ns.UI.Workspace then
      if ns.UI.Crates and ns.UI.Crates.EnsureInitialized then
        ns.UI.Crates.EnsureInitialized()
      end
      ns.UI.Workspace.Toggle(nil)
    elseif ns.UI and ns.UI.Crates then
      ns.UI.Crates.Toggle()
    end
    return
  elseif cmd == "doctor" or cmd == "status" then
    Events.RunDoctor()
    return
  elseif cmd == "selftest" or cmd == "test" then
    Events.RunSelfTestCommand()
    return
  elseif cmd == "suggest" then
    local sub = string.lower(string.gsub(tostring(rest or ""), "^%s*(.-)%s*$", "%1"))
    if sub == "apply" then
      if ns.UI and ns.UI.Crates then
        if not ns.UI.Crates.pendingSuggestionPreview then
          ns.UI.Crates.pendingSuggestionPreview = ns.Domain.Costs.SuggestReadyTurnIns()
        end
        ns.UI.Crates.ApplyPendingSuggestion()
      end
    elseif sub == "undo" then
      local ok, err = ns.State.UndoLastSuggestion()
      if ok then
        ns.Compat.Print("Reverted last 'Suggest Ready' batch.")
        if ns.UI and ns.UI.Crates then
          ns.UI.Crates.RefreshIfShown()
        end
      else
        ns.Compat.Print("Undo unavailable: " .. tostring(err))
      end
    else
      if ns.UI and ns.UI.Crates then
        ns.UI.Crates.PreviewSuggestReady()
      end
    end
    return
  elseif cmd == "priority" or cmd == "prio" then
    local idStr, dirStr = string.match(rest or "", "^(%S+)%s*(%S*)$")
    if not idStr or idStr == "" then
      ns.Compat.Print("Usage: /fh priority <crateOrWritItemID> <up|down>")
      return
    end
    local delta = (string.lower(dirStr or "up") == "down") and 1 or -1
    local ok, newPrioOrErr = ns.State.MoveReservationPriority(idStr, delta)
    if ok then
      ns.Compat.Print(string.format("Moved reservation %s to Priority #%s.", tostring(idStr), tostring(newPrioOrErr)))
      if ns.UI and ns.UI.Crates then
        ns.UI.Crates.RefreshIfShown()
      end
    else
      ns.Compat.Print("Priority move failed: " .. tostring(newPrioOrErr))
    end
    return
  elseif cmd == "collect" or cmd == "withdraw" then
    local sub = string.lower(string.gsub(tostring(rest or ""), "^%s*(.-)%s*$", "%1"))
    if sub == "stop" or sub == "cancel" then
      ns.Providers.Inventory.CancelBankCollection("user_cancelled", "Bank collection stopped by user.")
    else
      ns.Providers.Inventory.StartBankCollection()
    end
    if ns.UI and ns.UI.Crates then
      ns.UI.Crates.RefreshIfShown()
    end
    return
  elseif cmd == "trace" then
    local sub = string.lower(string.gsub(tostring(rest or ""), "^%s*(.-)%s*$", "%1"))
    if sub == "clear" then
      ns.Domain.Diagnostics.ClearTrace()
      ns.Compat.Print("Cleared diagnostic lifecycle trace.")
      return
    end
    local summary = ns.Domain.Diagnostics.GetSummary()
    ns.Compat.Print(
      string.format(
        "=== ForeverHub Lifecycle Trace (Diagnostic-Only, AutoMutate=%s) | %d Entries | %d Classified Transactions ===",
        tostring(summary.autoMutateReservations),
        summary.entryCount or 0,
        summary.transactionCount or 0
      )
    )
    local txs = summary.transactions or {}
    local startIdx = math.max(1, #txs - 9)
    for i = startIdx, #txs do
      local tx = txs[i]
      ns.Compat.Print(
        string.format(
          "  #%d [seq=%s] %s (%s) goal=%s quest=%s",
          i,
          tostring(tx.seq or "?"),
          tostring(tx.classification),
          tostring(tx.transition),
          tostring(tx.goalKey or "-"),
          tostring(tx.questID or "-")
        )
      )
    end
    return
  elseif cmd == "reserve" then
    local idStr, optStr, qtyStr = string.match(rest or "", "^(%d+)%s*(%d*)%s*(%S*)$")
    local itemID = tonumber(idStr)
    local optIdx = tonumber(optStr) or 1
    if not itemID then
      ns.Compat.Print("Usage: /fh reserve <crateOrWritItemID> [optionIndex] [quantity|all]")
      return
    end
    local kind = (ns.Data and ns.Data.writsByItemID and ns.Data.writsByItemID[itemID]) and "writ" or "crate"
    local qty = nil
    if qtyStr and qtyStr ~= "" then
      if string.lower(qtyStr) == "all" then
        local counts = ns.Providers.Inventory.GetItemCounts(itemID)
        local charOwned = (counts.bagCount or 0) + (counts.bankCount or 0)
        if charOwned <= 0 then
          ns.Compat.Print(
            string.format("Cannot reserve 'all': you currently own 0 of item %d in bags/bank.", itemID)
          )
          return
        end
        qty = charOwned
      else
        qty = tonumber(qtyStr)
        if not qty or qty <= 0 or math.floor(qty) ~= qty then
          ns.Compat.Print("Invalid quantity: must be a positive integer >= 1 (or 'all').")
          return
        end
      end
    end
    local ok, resOrErr = ns.State.ReserveGoal(kind, itemID, optIdx, qty)
    if ok then
      ns.Compat.Print(
        string.format(
          "Reserved %dx %s (Option #%d, Priority #%d) -> %s",
          resOrErr.quantity or 1,
          resOrErr.targetName,
          resOrErr.optionIndex,
          resOrErr.priority or 1,
          resOrErr.goalKey
        )
      )
      if ns.UI and ns.UI.Crates then
        ns.UI.Crates.RefreshIfShown()
      end
    else
      ns.Compat.Print("Reserve failed: " .. tostring(resOrErr))
    end
    return
  elseif cmd == "complete" or cmd == "done" then
    local idStr, countStr = string.match(rest or "", "^(%d+)%s*(%d*)$")
    local itemID = tonumber(idStr)
    local count = tonumber(countStr) or 1
    if not itemID then
      ns.Compat.Print("Usage: /fh complete <crateOrWritItemID> [completedCount]")
      return
    end
    local kind = (ns.Data and ns.Data.writsByItemID and ns.Data.writsByItemID[itemID]) and "writ" or "crate"
    local ok, remOrErr = ns.State.CompleteGoalTurnIn(kind, itemID, count)
    if ok then
      if ns.Domain and ns.Domain.Diagnostics and ns.Domain.Diagnostics.RecordManualCompletion then
        ns.Domain.Diagnostics.RecordManualCompletion(kind, itemID, count, remOrErr)
      end
      if remOrErr > 0 then
        ns.Compat.Print(string.format("Completed %d turn-in(s) for item %d. Remaining reserved turn-ins: %d.", count, itemID, remOrErr))
      else
        ns.Compat.Print(string.format("Completed final turn-in for item %d. Reservation cleared.", itemID))
      end
      if ns.UI and ns.UI.Crates then
        ns.UI.Crates.RefreshIfShown()
      end
    else
      ns.Compat.Print("Complete failed: " .. tostring(remOrErr))
    end
    return
  elseif cmd == "shop" then
    local modeArg = string.lower(rest or "")
    local mode = (modeArg == "bags" or modeArg == "bagsonly") and "bags_only" or "after_bank"
    if ns.UI and ns.UI.Crates then
      ns.UI.Crates.ExportShoppingList(mode)
    end
    return
  elseif cmd == "unreserve" or cmd == "clear" then
    local target = (rest and rest ~= "") and rest or "all"
    local ok = ns.State.UnreserveGoal(target)
    if ok then
      ns.Compat.Print("Cleared reservation(s): " .. tostring(target))
      if ns.UI and ns.UI.Crates then
        ns.UI.Crates.RefreshIfShown()
      end
    else
      ns.Compat.Print("No matching reservation found for: " .. tostring(target))
    end
    return
  elseif cmd == "rxp" or cmd == "books" then
    if ns.Bridges and ns.Bridges.RXPBridge then
      ns.Bridges.RXPBridge.RegisterBookDetours(true)
    end
    return
  elseif cmd == "rg" or cmd == "riverglades" then
    Events.HandleRivergladesSubcommand(rest)
    return
  elseif cmd == "gold" or cmd == "farm" or cmd == "farms" then
    Events.HandleGoldSubcommand(rest)
    return
  elseif cmd == "mount" then
    Events.HandleMountCommand(rest)
    return
  elseif cmd == "arrow" then
    Events.HandleArrowCommand(rest)
    return
  elseif cmd == "minimap" or cmd == "mm" then
    local sub = string.lower(string.gsub(tostring(rest or ""), "^%s*(.-)%s*$", "%1"))
    local mmUI = ns.UI and ns.UI.MinimapButton
    if sub == "reset" then
      if mmUI and mmUI.ResetPosition then
        mmUI.ResetPosition()
      end
      ns.Compat.Print("Minimap button restored to default position.")
    elseif sub == "hide" or sub == "off" then
      if mmUI and mmUI.SetHidden then
        mmUI.SetHidden(true)
      elseif ns.State and ns.State.SetMinimapHidden then
        ns.State.SetMinimapHidden(true)
      end
      ns.Compat.Print("Minimap button hidden. Type /fh minimap to show it again.")
    elseif sub == "show" or sub == "on" then
      if mmUI and mmUI.SetHidden then
        mmUI.SetHidden(false)
      elseif ns.State and ns.State.SetMinimapHidden then
        ns.State.SetMinimapHidden(false)
      end
      ns.Compat.Print("Minimap button shown.")
    else
      local cur = (ns.State and ns.State.GetMinimapSettings and ns.State.GetMinimapSettings()) or { hidden = false }
      local nextHidden = not (cur.hidden == true)
      if mmUI and mmUI.SetHidden then
        mmUI.SetHidden(nextHidden)
      elseif ns.State and ns.State.SetMinimapHidden then
        ns.State.SetMinimapHidden(nextHidden)
      end
      ns.Compat.Print(nextHidden and "Minimap button hidden. Type /fh minimap to show it again." or "Minimap button shown.")
    end
    return
  else
    ns.Compat.Print("Commands: /fh | /fh minimap [show|hide|reset] | /fh arrow [on|off|lock|unlock|scale <0.6-2.0>|style <auto|custom|classic>|reset] | /fh gold [...] | /fh rg [...] | /fh mount | /fh doctor | /fh selftest")
  end
end

local eventFrame = CreateFrame and CreateFrame("Frame")
if eventFrame then
  eventFrame:RegisterEvent("ADDON_LOADED")
  eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
  eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
  eventFrame:RegisterEvent("BANKFRAME_OPENED")
  eventFrame:RegisterEvent("BANKFRAME_CLOSED")
  eventFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
  for _, optEvent in ipairs({
    "BANK_TABS_CHANGED",
    "PLAYERBANKSLOTS_CHANGED",
    "QUEST_ACCEPTED",
    "QUEST_TURNED_IN",
    "QUEST_REMOVED",
    "QUEST_LOG_UPDATE",
    "QUEST_WATCH_UPDATE",
    "UNIT_QUEST_LOG_CHANGED",
    "CRITERIA_UPDATE",
    "CHAT_MSG_SYSTEM",
    "QUEST_AUTOCOMPLETE",
    "QUEST_PROGRESS",
    "QUEST_COMPLETE",
    "QUEST_FINISHED",
    "QUEST_DETAIL",
    "GET_ITEM_INFO_RECEIVED",
    "PLAYER_MONEY",
    "MAIL_SHOW",
    "MAIL_CLOSED",
    "AUCTION_HOUSE_SHOW",
    "AUCTION_HOUSE_CLOSED",
    "MERCHANT_SHOW",
    "MERCHANT_CLOSED",
    "TRADE_SHOW",
    "TRADE_CLOSED",
    "TRAINER_SHOW",
    "TRAINER_CLOSED",
    "GOSSIP_SHOW",
    "GOSSIP_CLOSED",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "ZONE_CHANGED_NEW_AREA",
    "DISPLAY_SIZE_CHANGED",
    "UI_SCALE_CHANGED",
    "PLAYER_LOGOUT",
  }) do
    pcall(function()
      eventFrame:RegisterEvent(optEvent)
    end)
  end

  eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "ADDON_LOADED" and arg1 == ns.name then
      ns.State.Init(true)
      if ns.UI and ns.UI.Tooltips then
        ns.UI.Tooltips.Init()
      end
      if ns.UI and ns.UI.WorldMapPins then
        ns.UI.WorldMapPins.EnsureHooksInstalled()
        ns.UI.WorldMapPins.RequestRefresh()
      end
      if ns.UI and ns.UI.MinimapButton and ns.UI.MinimapButton.EnsureCreated then
        ns.UI.MinimapButton.EnsureCreated()
      end
    elseif event == "PLAYER_ENTERING_WORLD" then
      if ns.UI and ns.UI.MinimapButton then
        if ns.UI.MinimapButton.RefreshVisibility then
          ns.UI.MinimapButton.RefreshVisibility()
        end
        if ns.UI.MinimapButton.ShowWelcomeToastIfNeeded then
          ns.UI.MinimapButton.ShowWelcomeToastIfNeeded()
        end
      end
      ns.State.CaptureSessionMoneyBaselineIfUnset()
      if ns.Providers and ns.Providers.Auctionator then
        ns.Providers.Auctionator.RegisterDBUpdateCallback(function()
          if ns.UI and ns.UI.Crates then
            ns.UI.Crates.RefreshIfShown()
          end
        end)
      end
      ns.State.BumpInventoryRevision()
      recordInventoryTraceIfEnabled("PLAYER_ENTERING_WORLD")
      if ns.UI and ns.UI.Navigation and ns.UI.Navigation.InvalidateTargetAnchor then
        ns.UI.Navigation.InvalidateTargetAnchor()
      end
      if ns.UI and ns.UI.WorldMapPins then
        ns.UI.WorldMapPins.EnsureHooksInstalled()
      end
      if ns.Compat and ns.Compat.ScanLiveQuestLog then
        ns.Compat.ScanLiveQuestLog(true)
      end
      Events.SeedObjectiveTelemetryBaseline()
      Events.ScheduleRouteReconcile()
      local gProg = ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress()
      -- Astra P1-9 & Gate 7: Telemetry ALWAYS stays paused after `/reload` until user explicitly runs `/fh gold start`.
      if gProg and gProg.mode ~= "paused" and ns.UI and ns.UI.Navigation then
        local gEval = ns.Domain.GoldFarms.Reconcile(nil, gProg)
        ns.UI.Navigation.SyncFromGoldFarmEvaluation(gEval, gProg)
      end
    elseif event == "PLAYER_LOGOUT" then
      if ns.State and ns.State.CheckpointGoldFarmTelemetry then
        ns.State.CheckpointGoldFarmTelemetry(nil, nil, true)
      end
    elseif event == "MODIFIER_STATE_CHANGED" then
      if (arg1 == "LSHIFT" or arg1 == "RSHIFT") and ns.UI and ns.UI.Tooltips and ns.UI.Tooltips.RefreshActiveTooltips then
        ns.UI.Tooltips.RefreshActiveTooltips()
      end
    elseif event == "MAIL_SHOW" then
      ns.State.mailOpen = true
      if ns.State.OnNonFarmMoneyWindowOpened then
        ns.State.OnNonFarmMoneyWindowOpened("mail")
      end
    elseif event == "MAIL_CLOSED" then
      ns.State.mailOpen = false
      if ns.State.OnNonFarmMoneyWindowClosed then
        ns.State.OnNonFarmMoneyWindowClosed("mail")
      end
    elseif event == "AUCTION_HOUSE_SHOW" then
      ns.State.ahOpen = true
      if ns.State.OnNonFarmMoneyWindowOpened then
        ns.State.OnNonFarmMoneyWindowOpened("auction_house")
      end
    elseif event == "AUCTION_HOUSE_CLOSED" then
      ns.State.ahOpen = false
      if ns.State.OnNonFarmMoneyWindowClosed then
        ns.State.OnNonFarmMoneyWindowClosed("auction_house")
      end
    elseif event == "MERCHANT_SHOW" then
      ns.State.merchantOpen = true
    elseif event == "MERCHANT_CLOSED" then
      ns.State.merchantOpen = false
      if ns.Domain and ns.Domain.GoldFarms and ns.Domain.GoldFarms.CompleteVendorStepIfNear then
        local gProg = ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress()
        local completedVendor, afterEval = ns.Domain.GoldFarms.CompleteVendorStepIfNear(nil, gProg)
        if completedVendor and afterEval and ns.UI and ns.UI.Navigation and ns.UI.Navigation.SyncFromGoldFarmEvaluation then
          ns.UI.Navigation.SyncFromGoldFarmEvaluation(afterEval, gProg)
          if ns.UI.GoldFarms and ns.UI.GoldFarms.RefreshIfShown then
            ns.UI.GoldFarms.RefreshIfShown()
          end
        end
      end
    elseif event == "TRADE_SHOW" then
      ns.State.tradeOpen = true
      if ns.State.OnNonFarmMoneyWindowOpened then
        ns.State.OnNonFarmMoneyWindowOpened("trade")
      end
    elseif event == "TRADE_CLOSED" then
      ns.State.tradeOpen = false
      if ns.State.OnNonFarmMoneyWindowClosed then
        ns.State.OnNonFarmMoneyWindowClosed("trade")
      end
    elseif event == "TRAINER_SHOW" then
      ns.State.trainerOpen = true
      if ns.State.OnNonFarmMoneyWindowOpened then
        ns.State.OnNonFarmMoneyWindowOpened("trainer")
      end
    elseif event == "TRAINER_CLOSED" then
      ns.State.trainerOpen = false
      if ns.State.OnNonFarmMoneyWindowClosed then
        ns.State.OnNonFarmMoneyWindowClosed("trainer")
      end
    elseif event == "GOSSIP_SHOW" then
      ns.State.gossipOpen = true
    elseif event == "GOSSIP_CLOSED" then
      ns.State.gossipOpen = false
    elseif event == "PLAYER_REGEN_DISABLED" then
      if ns.Providers and ns.Providers.Inventory and ns.Providers.Inventory.CancelBankCollection then
        ns.Providers.Inventory.CancelBankCollection("combat", "Bank collection stopped because you entered combat.")
      end
    elseif event == "PLAYER_REGEN_ENABLED" then
      if ns.UI and ns.UI.Navigation and ns.UI.Navigation.FlushDeferredIfReady then
        ns.UI.Navigation.FlushDeferredIfReady()
      end
      local rProg = ns.State and ns.State.GetRouteProgress and ns.State.GetRouteProgress()
      if rProg and rProg.mode ~= "paused" then
        Events.ScheduleObjectiveVerificationReconciles()
      end
    elseif event == "ZONE_CHANGED_NEW_AREA" then
      if ns.UI and ns.UI.Navigation and ns.UI.Navigation.InvalidateTargetAnchor then
        ns.UI.Navigation.InvalidateTargetAnchor()
      end
      if ns.UI and ns.UI.Navigation and ns.UI.Navigation.pendingDeferredSync and ns.UI.Navigation.FlushDeferredIfReady then
        ns.UI.Navigation.FlushDeferredIfReady()
      end
      Events.ScheduleRouteReconcile()
      local gProg = ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress()
      if gProg and gProg.mode ~= "paused" and ns.UI and ns.UI.Navigation and ns.UI.Navigation.SyncFromGoldFarmEvaluation then
        local gEval = ns.Domain.GoldFarms.ReconcileActive(nil, gProg)
        ns.UI.Navigation.SyncFromGoldFarmEvaluation(gEval, gProg)
      end
    elseif event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
      if ns.UI and ns.UI.Navigation and ns.UI.Navigation.RefreshArrowSettings then
        ns.UI.Navigation.RefreshArrowSettings()
      end
      if ns.UI and ns.UI.Workspace and ns.UI.Workspace.RefreshIfShown then
        ns.UI.Workspace.RefreshIfShown()
      end
    elseif event == "QUEST_COMPLETE" then
      if ns.Compat and ns.Compat.CaptureQuestDialogIdentity then
        ns.Compat.CaptureQuestDialogIdentity("QUEST_COMPLETE")
      end
      if ns.UI and ns.UI.RewardAdvisor then
        ns.UI.RewardAdvisor.OnQuestComplete()
      end
    elseif event == "QUEST_PROGRESS" then
      if ns.Compat and ns.Compat.CaptureQuestDialogIdentity then
        ns.Compat.CaptureQuestDialogIdentity("QUEST_PROGRESS")
      end
    elseif event == "QUEST_DETAIL" then
      if ns.Compat and ns.Compat.CaptureQuestDialogIdentity then
        ns.Compat.CaptureQuestDialogIdentity("QUEST_DETAIL")
      end
      if ns.UI and ns.UI.RewardAdvisor then
        ns.UI.RewardAdvisor.OnQuestFinished()
      end
    elseif event == "QUEST_FINISHED" then
      if ns.UI and ns.UI.RewardAdvisor then
        ns.UI.RewardAdvisor.OnQuestFinished()
      end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
      if ns.UI and ns.UI.RewardAdvisor then
        ns.UI.RewardAdvisor.OnItemInfoReceived(arg1, arg2)
      end
      if ns.UI and ns.UI.Crates and ns.UI.Crates.OnItemInfoReceived then
        ns.UI.Crates.OnItemInfoReceived(arg1, arg2)
      end
    elseif event == "PLAYER_MONEY" then
      ns.State.CaptureSessionMoneyBaselineIfUnset()
      if ns.UI and ns.UI.GoldFarms and ns.UI.GoldFarms.RefreshIfShown then
        ns.UI.GoldFarms.RefreshIfShown()
      end
      if ns.UI and ns.UI.Workspace and ns.UI.Workspace.RefreshIfShown then
        ns.UI.Workspace.RefreshIfShown()
      end
    elseif event == "QUEST_LOG_UPDATE" or event == "QUEST_WATCH_UPDATE" or event == "QUEST_AUTOCOMPLETE" then
      if ns.Compat and ns.Compat.InvalidateQuestStateCaches then
        ns.Compat.InvalidateQuestStateCaches()
      end
      if event == "QUEST_LOG_UPDATE" or event == "QUEST_WATCH_UPDATE" then
        Events.CaptureQuestFieldTelemetry("objective_scan")
      end
      Events.ScheduleObjectiveVerificationReconciles()
    elseif event == "UNIT_QUEST_LOG_CHANGED" then
      if arg1 == nil or arg1 == "player" then
        if ns.Compat and ns.Compat.InvalidateQuestStateCaches then
          ns.Compat.InvalidateQuestStateCaches()
        end
        Events.CaptureQuestFieldTelemetry("objective_scan")
        Events.ScheduleObjectiveVerificationReconciles()
      end
    elseif event == "CRITERIA_UPDATE" then
      local rProg = ns.State and ns.State.GetRouteProgress and ns.State.GetRouteProgress()
      if rProg and rProg.mode ~= "paused" then
        if ns.Compat and ns.Compat.InvalidateQuestStateCaches then
          ns.Compat.InvalidateQuestStateCaches()
        end
        Events.CaptureQuestFieldTelemetry("objective_scan")
        Events.ScheduleObjectiveVerificationReconciles()
      end
    elseif event == "CHAT_MSG_SYSTEM" then
      if ns.Compat and ns.Compat.ParseSystemQuestCompletedMessage then
        local sysQid, sysRawTitle, sysNormTitle = ns.Compat.ParseSystemQuestCompletedMessage(arg1)
        if sysQid or sysNormTitle then
          if ns.Compat.RecordRecentQuestTurnedIn then
            ns.Compat.RecordRecentQuestTurnedIn(sysQid, sysRawTitle)
          end
          Events.CaptureQuestFieldTelemetry("quest_turned_in", sysQid)
          if ns.Domain and ns.Domain.Diagnostics and ns.Domain.Diagnostics.RecordQuestEvent then
            ns.Domain.Diagnostics.RecordQuestEvent("CHAT_MSG_SYSTEM_QUEST_COMPLETE", sysQid)
          end
          if ns.UI and ns.UI.Crates then
            ns.UI.Crates.RefreshIfShown()
          end
          Events.ScheduleVerificationReconciles()
        end
      end
    elseif event == "QUEST_ACCEPTED" then
      local qID = tonumber(arg2) or tonumber(arg1)
      if ns.Compat and ns.Compat.RecordRecentQuestAccepted then
        ns.Compat.RecordRecentQuestAccepted(qID, nil)
      end
      Events.CaptureQuestFieldTelemetry("quest_accepted", qID)
      if ns.Domain and ns.Domain.Diagnostics and ns.Domain.Diagnostics.RecordQuestEvent then
        ns.Domain.Diagnostics.RecordQuestEvent(event, qID)
      end
      if ns.UI and ns.UI.Crates then
        ns.UI.Crates.RefreshIfShown()
      end
      Events.ScheduleVerificationReconciles()
    elseif event == "QUEST_TURNED_IN" then
      local qID = tonumber(arg1)
      if ns.Compat and ns.Compat.RecordRecentQuestTurnedIn then
        ns.Compat.RecordRecentQuestTurnedIn(qID, nil)
      end
      Events.CaptureQuestFieldTelemetry("quest_turned_in", qID)
      if ns.Domain and ns.Domain.Diagnostics and ns.Domain.Diagnostics.RecordQuestEvent then
        ns.Domain.Diagnostics.RecordQuestEvent(event, qID)
      end
      if ns.UI and ns.UI.Crates then
        ns.UI.Crates.RefreshIfShown()
      end
      Events.ScheduleVerificationReconciles()
    elseif event == "QUEST_REMOVED" then
      local qID = tonumber(arg1)
      local promoted = false
      if ns.Compat and ns.Compat.RecordRecentQuestRemoved then
        promoted = (ns.Compat.RecordRecentQuestRemoved(qID) == true)
      end
      if promoted then
        Events.CaptureQuestFieldTelemetry("quest_turned_in", qID)
      elseif qID and qID > 0 and C_Timer and type(C_Timer.After) == "function" then
        pcall(C_Timer.After, 1.00, function()
          if ns.Compat and ns.Compat.RecordRecentQuestRemoved and ns.Compat.RecordRecentQuestRemoved(qID) == true then
            Events.CaptureQuestFieldTelemetry("quest_turned_in", qID)
            local curProg = ns.State and ns.State.GetRouteProgress and ns.State.GetRouteProgress()
            if curProg and curProg.mode ~= "paused" then
              Events.FlushRouteReconcileNow()
            end
          end
        end)
      end
      if ns.Domain and ns.Domain.Diagnostics and ns.Domain.Diagnostics.RecordQuestEvent then
        ns.Domain.Diagnostics.RecordQuestEvent(event, qID)
      end
      if ns.UI and ns.UI.Crates then
        ns.UI.Crates.RefreshIfShown()
      end
      Events.ScheduleVerificationReconciles()
    elseif event == "BANKFRAME_OPENED" or event == "BANK_TABS_CHANGED" then
      if event == "BANKFRAME_OPENED" then
        ns.State.bankOpen = true
      end
      if ns.Providers and ns.Providers.Inventory then
        ns.Providers.Inventory.ScanLiveBankIfOpen()
      end
      ns.State.BumpInventoryRevision()
      recordInventoryTraceIfEnabled(event)
      if ns.UI and ns.UI.Workspace and ns.UI.Workspace.RefreshIfShown then
        ns.UI.Workspace.RefreshIfShown()
      elseif ns.UI and ns.UI.Crates then
        ns.UI.Crates.RefreshIfShown()
      end
    elseif event == "BANKFRAME_CLOSED" then
      if ns.Providers and ns.Providers.Inventory then
        if ns.Providers.Inventory.CancelBankCollection then
          ns.Providers.Inventory.CancelBankCollection("bank_closed", "Bank collection stopped because the bank was closed.")
        end
        ns.Providers.Inventory.ScanLiveBankIfOpen()
      end
      ns.State.bankOpen = false
      ns.State.BumpInventoryRevision()
      recordInventoryTraceIfEnabled(event)
      if ns.UI and ns.UI.Workspace and ns.UI.Workspace.RefreshIfShown then
        ns.UI.Workspace.RefreshIfShown()
      elseif ns.UI and ns.UI.Crates then
        ns.UI.Crates.RefreshIfShown()
      end
      Events.ScheduleRouteReconcile()
    elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYERBANKSLOTS_CHANGED" then
      if ns.State.bankOpen and ns.Providers and ns.Providers.Inventory then
        ns.Providers.Inventory.ScanLiveBankIfOpen()
      end
      ns.State.BumpInventoryRevision()
      recordInventoryTraceIfEnabled(event)
      if ns.Providers and ns.Providers.Inventory and ns.Providers.Inventory.OnInventoryChangedForCollection then
        ns.Providers.Inventory.OnInventoryChangedForCollection()
      end
      if ns.UI and ns.UI.Workspace and ns.UI.Workspace.RefreshIfShown then
        ns.UI.Workspace.RefreshIfShown()
      elseif ns.UI and ns.UI.Crates then
        ns.UI.Crates.RefreshIfShown()
      end
      local rProg = ns.State and ns.State.GetRouteProgress and ns.State.GetRouteProgress()
      if rProg and rProg.mode ~= "paused" then
        Events.ScheduleObjectiveVerificationReconciles()
      end
    end
  end)
end

SLASH_FOREVERHUB1 = "/foreverhub"
SLASH_FOREVERHUB2 = "/fh"
SlashCmdList = SlashCmdList or {}
SlashCmdList["FOREVERHUB"] = handleSlashCommand
