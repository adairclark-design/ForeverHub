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
        tostring(ns.version or "0.9.0"),
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
  if ns.Domain.SelfTest.RunPhase0MarketSuite then
    local mkReport = ns.Domain.SelfTest.RunPhase0MarketSuite()
    ns.Compat.Print(
      string.format(
        "=== ForeverHub v%s Phase 0 Market Self-Tests (%d/%d PASSED) ===",
        tostring(ns.version or "0.9.0"),
        mkReport.passed,
        mkReport.total
      )
    )
    for _, r in ipairs(mkReport.results or {}) do
      if r.passed then
        ns.Compat.Print(string.format("  |cff00ff00[PASS]|r %s", r.name))
      else
        ns.Compat.Print(string.format("  |cffff4444[FAIL]|r %s — %s", r.name, tostring(r.error)))
      end
    end
  end
  if ns.Domain.SelfTest.RunSpawnRadarSuite then
    local srReport = ns.Domain.SelfTest.RunSpawnRadarSuite()
    ns.Compat.Print(
      string.format(
        "=== ForeverHub v%s Arcane Grind & Spawn Radar Self-Tests (%d/%d PASSED) ===",
        tostring(ns.version or "0.9.0"),
        srReport.passed,
        srReport.total
      )
    )
    for _, r in ipairs(srReport.results or {}) do
      if r.passed then
        ns.Compat.Print(string.format("  |cff00ff00[PASS]|r %s", r.name))
      else
        ns.Compat.Print(string.format("  |cffff4444[FAIL]|r %s — %s", r.name, tostring(r.error)))
      end
    end
  end
  if ns.Domain.SelfTest.RunSunkenTempleCoachSuite then
    local stReport = ns.Domain.SelfTest.RunSunkenTempleCoachSuite()
    ns.Compat.Print(
      string.format(
        "=== ForeverHub v%s Sunken Temple Coach RC1 Self-Tests (%d/%d PASSED) ===",
        tostring(ns.version or "0.9.0"),
        stReport.passed,
        stReport.total
      )
    )
    for _, r in ipairs(stReport.results or {}) do
      if r.passed then
        ns.Compat.Print(string.format("  |cff00ff00[PASS]|r %s", r.name))
      else
        ns.Compat.Print(string.format("  |cffff4444[FAIL]|r %s — %s", r.name, tostring(r.error)))
      end
    end
  end
end

function Events.FormatMarketDataDoctorSummary(explicitNowEpochSec, expectedMarketKey)
  local ma = ns.Domain and ns.Domain.MarketAccounting
  if not ma or type(ma.GetSiblingMarketDataStatus) ~= "function" then
    return "MarketData: Unavailable"
  end
  local st = ma.GetSiblingMarketDataStatus(explicitNowEpochSec, expectedMarketKey)
  if not st or st.status == "missing" then
    return "MarketData: Missing (ForeverHub_MarketData not loaded)"
  elseif st.status == "active" then
    local obsAge = st.newestObservationAgeSec ~= nil and (tostring(st.newestObservationAgeSec) .. "s") or "unknown"
    local pubAge = st.publishedAgeSec ~= nil and (tostring(st.publishedAgeSec) .. "s") or "unknown"
    local expStr = st.expiresInSec ~= nil and (tostring(st.expiresInSec) .. "s") or tostring(st.validUntilEpoch or "?")
    return string.format(
      "MarketData: Active | Revision=%s | Market=%s | ObservedAge=%s | PublishedAge=%s | ExpiresIn=%s | Items=%d | Basis=%s",
      tostring(st.contentRevision or "?"),
      tostring(st.marketKey or "?"),
      obsAge,
      pubAge,
      expStr,
      tonumber(st.itemCount) or 0,
      tostring(st.basis or "USER_REPORTED")
    )
  elseif st.status == "expired" then
    return string.format(
      "MarketData: Expired | Revision=%s | Market=%s | ValidUntil=%s",
      tostring(st.contentRevision or "?"),
      tostring(st.marketKey or "?"),
      tostring(st.validUntilEpoch or "?")
    )
  elseif st.status == "wrong_market" then
    return string.format(
      "MarketData: WrongMarket | Loaded=%s | Expected=%s",
      tostring(st.marketKey or "?"),
      tostring(st.expectedMarketKey or "?")
    )
  end
  return string.format("MarketData: InvalidSchema (%s)", tostring(st.reason or "unknown"))
end

function Events.RunProbeCommand(subArg)
  local trimmedSubArg = string.lower(string.gsub(tostring(subArg or ""), "^%s*(.-)%s*$", "%1"))
  local firstProbeWord, probeTail = string.match(trimmedSubArg, "^(%S+)%s*(.-)$")
  if firstProbeWord == "st" or firstProbeWord == "sunkentemple" then
    return Events.HandleSunkenTempleSubcommand("probe " .. tostring(probeTail or ""))
  end
  if not (ns.Compat and type(ns.Compat.ProbeEconomyRuntimeCapabilities) == "function") then
    ns.Compat.Print("Economy runtime capability probe is unavailable.")
    return nil
  end
  local cap = ns.Compat.ProbeEconomyRuntimeCapabilities()
  if ns.Domain and ns.Domain.MarketAccounting and ns.Domain.MarketAccounting.EnsureMarketExportInitialized then
    local me = ns.Domain.MarketAccounting.EnsureMarketExportInitialized()
    me.capabilityMatrix = cap
  end
  local cli = cap.client or {}
  local auc = cap.auctions or {}
  local prof = cap.professions or {}
  local mail = cap.mail or {}
  local loot = cap.loot or {}
  ns.Compat.Print(
    string.format(
      "=== ForeverHub Economy Runtime Probe (%s Build %s, Interface %s) ===",
      tostring(cli.version or "unknown"),
      tostring(cli.build or "unknown"),
      tostring(cli.tocVersion or 0)
    )
  )
  ns.Compat.Print(
    string.format(
      "  Client Guards: issecretvalue=%s | NativeCBOR=%s",
      tostring(cli.hasSecretValueGuard == true),
      tostring(cli.hasNativeCBOR == true)
    )
  )
  ns.Compat.Print(
    string.format(
      "  Auctions: family=%s | legacyQuery=%s | legacyDeposit=%s | modernNS=%s",
      tostring(auc.detectedFamily or "unavailable"),
      tostring(auc.hasLegacyQuery == true),
      tostring(auc.hasLegacyDepositCalc == true),
      tostring(auc.hasModernNamespace == true)
    )
  )
  ns.Compat.Print(
    string.format(
      "  Professions: family=%s | TradeSkill=%s | Craft=%s | ModernTS=%s",
      tostring(prof.detectedFamily or "unavailable"),
      tostring(prof.hasClassicTradeSkill == true),
      tostring(prof.hasClassicCraft == true),
      tostring(prof.hasModernTradeSkillUI == true)
    )
  )
  ns.Compat.Print(
    string.format(
      "  Mail & Loot: inboxHeader=%s | inboxInvoice=%s | lootSlots=%s | lootLinks=%s",
      tostring(mail.hasInboxHeader == true),
      tostring(mail.hasInboxInvoice == true),
      tostring(loot.hasLootSlotInfo == true),
      tostring(loot.hasLootSlotLink == true)
    )
  )
  local merch = cap.merchant or {}
  local itemInsp = cap.itemInspection or {}
  ns.Compat.Print(
    string.format(
      "  Merchant & ItemCache: locale=%s | merchantAPI=%s | costInfo=%s | requestLoad=%s | tooltipInfo=%s",
      tostring(cli.clientLocale or "unknown"),
      tostring(merch.hasMerchantAPI == true),
      tostring(merch.hasMerchantCostInfo == true),
      tostring(itemInsp.hasRequestLoadItemDataByID == true),
      tostring(itemInsp.hasCTooltipInfo == true)
    )
  )
  if ns.Compat and type(ns.Compat.CaptureRedactedContractFixture) == "function" then
    local fix = ns.Compat.CaptureRedactedContractFixture()
    cap.redactedContractFixture = fix
    local ahP = fix.ahPostProbe or {}
    local mailP = fix.mailPostageAndCodProbe or {}
    ns.Compat.Print(
      string.format(
        "  Contract Fixture (7A.1): schema=%s | piiRedacted=%s | ahRows=%d | profStatus=%s | mailItems=%d",
        tostring(fix.schema or "unknown"),
        tostring(fix.piiRedacted == true),
        tonumber(fix.auctionPage and fix.auctionPage.inspectedCount) or 0,
        tostring(fix.professionSnapshot and fix.professionSnapshot.status or "PENDING"),
        tonumber(fix.mailInbox and fix.mailInbox.numItems) or 0
      )
    )
    ns.Compat.Print(
      string.format(
        "  7A.1 Sell & Mail Probes: ahOpen=%s | slotted=%s | venue=%s | sendMailPrice=%s | codSampled=%d",
        tostring(ns.State and ns.State.ahOpen == true),
        tostring(ahP.slottedSellItem and ahP.slottedSellItem.slotted == true),
        tostring(ahP.auctioneerNpc and ahP.auctioneerNpc.status or "UNKNOWN"),
        tostring(mailP.sendMailPriceCopper or "nil"),
        tonumber(mailP.inboxSummary and mailP.inboxSummary.codRowCount) or 0
      )
    )
  end
  return cap
end

function Events.HandleDiscoverySubcommand(rest)
  if not (ns.State and ns.State.EnsureDiscoveryCollectorInitialized) then
    ns.Compat.Print("Discovery collector is unavailable.")
    return
  end
  local sub = string.lower(string.gsub(tostring(rest or ""), "^%s*(.-)%s*$", "%1"))
  if sub == "on" or sub == "enable" then
    ns.State.SetDiscoveryOptIn(true)
    ns.Compat.Print("ForeverHub Discovery Collector: OPTED IN (candidate-only; never auto-promotes executable or compiler truth).")
    return
  elseif sub == "off" or sub == "disable" then
    ns.State.SetDiscoveryOptIn(false)
    ns.Compat.Print("ForeverHub Discovery Collector: OPTED OUT (default).")
    return
  end
  local dc = ns.State.EnsureDiscoveryCollectorInitialized()
  local st = dc.stats or {}
  ns.Compat.Print(
    string.format(
      "Discovery Collector: %s | offers=%d/%d | recipes=%d/%d | bytes=%d/%d | droppedCap=%d | droppedBytes=%d",
      dc.optInEnabled and "OPTED_IN" or "OPTED_OUT",
      #(dc.merchantOffers or {}),
      tonumber(ns.State.DISCOVERY_MAX_OFFERS) or 64,
      #(dc.recipes or {}),
      tonumber(ns.State.DISCOVERY_MAX_RECIPES) or 64,
      tonumber(dc.estimatedBytes) or 0,
      tonumber(ns.State.DISCOVERY_MAX_SERIALIZED_BYTES) or 65536,
      tonumber(st.droppedByCapCount) or 0,
      tonumber(st.droppedByByteBudgetCount) or 0
    )
  )
  ns.Compat.Print("Usage: /fh discovery [status | on | off]")
end

Events.deckRefreshPending = false

function Events.ScheduleCoalescedDeckRefresh()
  if Events.deckRefreshPending then
    return
  end
  local function flushDeck()
    Events.deckRefreshPending = false
    if ns.UI and ns.UI.CommandDeck and ns.UI.CommandDeck.RefreshIfShown then
      pcall(ns.UI.CommandDeck.RefreshIfShown)
    end
  end
  if C_Timer and type(C_Timer.After) == "function" then
    Events.deckRefreshPending = true
    local ok = pcall(C_Timer.After, 0.15, flushDeck)
    if not ok then
      flushDeck()
    end
  else
    flushDeck()
  end
end

function Events.HandleMarketSubcommand(rest)
  local ma = ns.Domain and ns.Domain.MarketAccounting
  if not ma then
    ns.Compat.Print("MarketAccounting module is unavailable.")
    return
  end
  local trimmed = string.gsub(tostring(rest or ""), "^%s*(.-)%s*$", "%1")
  local sub, tail = string.match(trimmed, "^(%S+)%s*(.-)$")
  sub = string.lower(sub or "status")
  if sub == "" or sub == "status" then
    ns.Compat.Print(Events.FormatMarketDataDoctorSummary())
    local me = ma.EnsureMarketExportInitialized()
    ns.Compat.Print(
      string.format(
        "MarketExport Queue: seq=%d | observations=%d | depositQuotes=%d | mailOutcomes=%d",
        tonumber(me.installationSeq) or 0,
        #(me.observations or {}),
        #(me.depositQuotes or {}),
        #(me.mailOutcomes or {})
      )
    )
    return
  elseif sub == "export" then
    local idStr, poolStr = string.match(tail or "", "^(%d+)%s*(%S*)$")
    local itemID = tonumber(idStr)
    if not itemID then
      ns.Compat.Print("Usage: /fh market export <itemID> [alliance|horde|neutral]")
      return
    end
    local pool = (poolStr and poolStr ~= "") and poolStr or nil
    local obs, err = ma.ExportProviderMaterialSlice(itemID, pool)
    if not obs then
      ns.Compat.Print("Market slice export failed: " .. tostring(err))
      return
    end
    ns.Compat.Print(
      string.format(
        "Exported %s (%s) @ %dc | market=%s | observedAt=%s | coarseAgeDays=%s (run /reload to flush SavedVariables)",
        tostring(obs.observationId),
        tostring(obs.itemKey),
        tonumber(obs.unitPriceCopper) or 0,
        tostring(obs.marketKey),
        tostring(obs.observedAt),
        tostring(obs.ageDaysCoarse)
      )
    )
    return
  end
  ns.Compat.Print("Usage: /fh market [status | export <itemID> [pool]]")
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
  if ns.Domain and ns.Domain.SelfTest and ns.Domain.SelfTest.RunPhase0MarketSuite then
    local mkSum = ns.Domain.SelfTest.GetDoctorSuiteSummary
      and ns.Domain.SelfTest.GetDoctorSuiteSummary("phase0_market")
      or nil
    if mkSum then
      rgSelfTestSuffix = rgSelfTestSuffix .. " | MK-v0.9.0: " .. mkSum
    end
  end
  if ns.Domain and ns.Domain.SelfTest and ns.Domain.SelfTest.RunSpawnRadarSuite then
    local srSum = ns.Domain.SelfTest.GetDoctorSuiteSummary
      and ns.Domain.SelfTest.GetDoctorSuiteSummary("spawn_radar")
      or nil
    if srSum then
      rgSelfTestSuffix = rgSelfTestSuffix .. " | SR-v0.9.1: " .. srSum
    end
  end
  if ns.Domain and ns.Domain.SelfTest and ns.Domain.SelfTest.RunSunkenTempleCoachSuite then
    local stSum = ns.Domain.SelfTest.GetDoctorSuiteSummary
      and ns.Domain.SelfTest.GetDoctorSuiteSummary("sunken_temple_rc1")
      or nil
    if stSum then
      rgSelfTestSuffix = rgSelfTestSuffix .. " | ST-RC1: " .. stSum
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
  ns.Compat.Print(Events.FormatMarketDataDoctorSummary())
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
  if ns.UI and ns.UI.WorldMapPins and ns.UI.WorldMapPins.RequestRefresh then
    pcall(ns.UI.WorldMapPins.RequestRefresh)
  end
  if ns.UI and ns.UI.Workspace and ns.UI.Workspace.RefreshIfShown then
    pcall(ns.UI.Workspace.RefreshIfShown)
  end
  return nil
end

function Events.ScheduleRouteReconcile()
  Events.FlushRouteReconcileNow()
end

function Events.ScheduleObjectiveVerificationReconciles()
  return
end

function Events.ScheduleVerificationReconciles()
  return
end

local function refreshWorldMapPinsIfLoaded()
  if ns.UI and ns.UI.WorldMapPins and ns.UI.WorldMapPins.RequestRefresh then
    ns.UI.WorldMapPins.RequestRefresh()
  end
end

local resyncActiveNavigationContext

function Events.HandleRivergladesSubcommand(_subRaw)
  ns.Compat.Print("The Riverglades quest helper has been retired (RestedXP now includes Riverglades natively). Use /fh gold or /fh crates.")
end

local function printSunkenTempleAutopsy(aut)
  if not aut then
    ns.Compat.Print("Sunken Temple Pull Autopsy: No closed attempt recorded in this session yet.")
    return
  end
  ns.Compat.Print(
    string.format(
      "=== ST Pull Autopsy (Attempt #%d · Outcome: %s · %.1fs · Phase: %s · Events: %d%s) ===",
      tonumber(aut.attemptID) or 1,
      tostring(aut.outcome or "?"),
      tonumber(aut.durationSec) or 0,
      tostring(aut.terminalPhaseTitle or "?"),
      tonumber(aut.totalObservedEvents) or 0,
      aut.overflowed and " [64-event ring rotated; header preserved]" or ""
    )
  )
  for _, c in ipairs(aut.confirmed or {}) do
    ns.Compat.Print(string.format("  |cff00ff88[CONFIRMED]|r %s (%s)", tostring(c.summary), tostring(c.evidence)))
  end
  for _, h in ipairs(aut.likelyHeuristics or {}) do
    ns.Compat.Print(
      string.format(
        "  |cffffcc00[LIKELY_HEURISTIC]|r %s | Missing link: %s",
        tostring(h.summary),
        tostring(h.missingLink or "unverified")
      )
    )
  end
  for _, u in ipairs(aut.unobservable or {}) do
    ns.Compat.Print(string.format("  |cff88aacc[UNOBSERVABLE_IN_16001]|r %s", tostring(u.summary)))
  end
end

function Events.HandleSunkenTempleSubcommand(restRaw)
  local coach = ns.Domain and ns.Domain.SunkenTempleCoach
  if not coach then
    ns.Compat.Print("SunkenTempleCoach module is not loaded.")
    return nil
  end
  local cleaned = string.gsub(tostring(restRaw or ""), "^%s*(.-)%s*$", "%1")
  local sub, tail = string.match(cleaned, "^(%S*)%s*(.-)$")
  sub = string.lower(sub or "")

  if sub == "probe" then
    local snap = coach.RunOptInProbe(tail)
    local cli = snap.client or {}
    local inst = snap.instance or {}
    local sig = snap.signals or {}
    ns.Compat.Print(
      string.format(
        "=== ForeverHub ST Live Capability Probe [%s] (Read-Only · ProvesRouteReadiness=false) ===",
        tostring(snap.contextLabel or "probe")
      )
    )
    ns.Compat.Print(
      string.format(
        "  Client: %s Build %s (Interface %s, locale=%s[%s], issecretvalue=%s, inCombat=%s)",
        tostring(cli.version),
        tostring(cli.build),
        tostring(cli.interfaceVersion),
        tostring(cli.locale or "nil"),
        tostring(cli.localeStatus),
        tostring(cli.hasSecretValueDetector == true),
        tostring(cli.inCombatLockdown == true)
      )
    )
    ns.Compat.Print(
      string.format(
        "  Instance Gate: %s (verifiedST=%s) | inInstance=%s(%s) | types=%s/%s | r8_instanceID=%s(%s) | r9_groupSize=%s(%s) | name=%s",
        tostring(inst.classification),
        tostring(inst.verifiedSunkenTemple == true),
        tostring(inst.inInstance),
        tostring(inst.inInstanceStatus),
        tostring(inst.isInTypeStatus),
        tostring(inst.infoTypeStatus),
        tostring(inst.return8_instanceID_value or "nil"),
        tostring(inst.return8_instanceID_status),
        tostring(inst.return9_groupSize_value or "nil"),
        tostring(inst.return9_groupSize_status),
        tostring(inst.nameStatus)
      )
    )
    ns.Compat.Print(
      string.format(
        "  Signals: Spellcast=%s(reg=%s) | C_UnitAuras(spell=%s, idx=%s) | UnitBuff=%s | Health=%s/%s | SubZone=%s/%s | Yell=%s | Emote=%s | Target(guid=%s, name=%s) | Plates(list=%s, tok=%s, guid=%s) | CLEU=%s",
        tostring(sig.unitSpellcastSucceeded and sig.unitSpellcastSucceeded.status),
        tostring(sig.unitSpellcastSucceeded and sig.unitSpellcastSucceeded.registration),
        tostring(sig.cUnitAuras and sig.cUnitAuras.bySpellIDStatus),
        tostring(sig.cUnitAuras and sig.cUnitAuras.byIndexStatus),
        tostring(sig.legacyUnitBuff and sig.legacyUnitBuff.nameStatus),
        tostring(sig.unitHealth and sig.unitHealth.healthStatus),
        tostring(sig.unitHealth and sig.unitHealth.maxHealthStatus),
        tostring(sig.subZone and sig.subZone.subZoneStatus),
        tostring(sig.subZone and sig.subZone.minimapZoneStatus),
        tostring(sig.monsterYell and sig.monsterYell.status),
        tostring(sig.monsterEmote and sig.monsterEmote.status),
        tostring(sig.target and sig.target.guidStatus),
        tostring(sig.target and sig.target.nameStatus),
        tostring(sig.namePlates and sig.namePlates.listStatus),
        tostring(sig.namePlates and sig.namePlates.firstTokenStatus),
        tostring(sig.namePlates and sig.namePlates.firstGuidStatus),
        tostring(sig.cleuPolicy)
      )
    )
    return snap
  elseif sub == "start" then
    local ok, res = coach.StartAttempt()
    if ok then
      ns.Compat.Print("Sunken Temple Coach: Started Attempt #" .. tostring(res.attemptID) .. " at Phase 1/6 (Entrance Run to Reset Ledge #1).")
    else
      ns.Compat.Print("Sunken Temple Coach cannot start: " .. tostring(res))
    end
    return ok
  elseif sub == "confirm" then
    local ok, res = coach.ConfirmPhaseLiveWalk(tail)
    if ok then
      if res == "cleared" then
        ns.Compat.Print("Sunken Temple Coach: Cleared in-session live-walk confirmations (returned to Broog video-candidate gate).")
      elseif res == "all" then
        ns.Compat.Print("Sunken Temple Coach: Confirmed all 6 phases live on this character for the current session.")
      else
        ns.Compat.Print("Sunken Temple Coach: Confirmed Phase " .. tostring(res) .. "/6 live on this character for the current session.")
      end
    else
      ns.Compat.Print("Usage: /fh st confirm [1-6 | all | reset] (" .. tostring(res) .. ")")
    end
    return ok
  elseif sub == "rearm" then
    local ok, res = coach.RearmCoach()
    if ok then
      ns.Compat.Print("Sunken Temple Coach: Rearmed to READY.")
    else
      ns.Compat.Print("Sunken Temple Coach cannot rearm: " .. tostring(res))
    end
    return ok
  elseif sub == "next" then
    local ok, res = coach.NextPhase()
    if ok then
      local pDef = coach.GetPhaseDefinition(res)
      ns.Compat.Print("Sunken Temple Coach -> " .. tostring(pDef and pDef.title or res))
    else
      ns.Compat.Print("Sunken Temple Coach Next unavailable: " .. tostring(res))
    end
    return ok
  elseif sub == "prev" or sub == "back" then
    local ok, res = coach.PrevPhase()
    if ok then
      local pDef = coach.GetPhaseDefinition(res)
      ns.Compat.Print("Sunken Temple Coach <- " .. tostring(pDef and pDef.title or res))
    else
      ns.Compat.Print("Sunken Temple Coach Prev unavailable: " .. tostring(res))
    end
    return ok
  elseif sub == "finish" or sub == "complete" then
    local ok, aut = coach.FinishAttempt()
    if ok then
      printSunkenTempleAutopsy(aut)
    else
      ns.Compat.Print("Sunken Temple Coach Finish unavailable: " .. tostring(aut))
    end
    return ok
  elseif sub == "abort" then
    local ok, aut = coach.AbortAttempt(tail)
    if ok then
      printSunkenTempleAutopsy(aut)
    else
      ns.Compat.Print("Sunken Temple Coach Abort unavailable: " .. tostring(aut))
    end
    return ok
  elseif sub == "reset" then
    local _, newState = coach.ResetCoachProgress()
    ns.Compat.Print("Sunken Temple Coach progress reset (coach state -> " .. tostring(newState) .. "; InstanceLedger untouched).")
    return true
  elseif sub == "autopsy" then
    printSunkenTempleAutopsy(coach.state.lastAutopsy)
    return coach.state.lastAutopsy
  elseif sub == "show" then
    coach.SetHudCardHidden(false)
    ns.Compat.Print("Sunken Temple Maneuver Card enabled (shows automatically inside verified Sunken Temple).")
    return true
  elseif sub == "hide" then
    coach.SetHudCardHidden(true)
    ns.Compat.Print("Sunken Temple Maneuver Card hidden.")
    return true
  elseif sub == "card" then
    local nextHidden = not (coach.state and coach.state.hudCardHidden == true)
    coach.SetHudCardHidden(nextHidden)
    ns.Compat.Print(nextHidden and "Sunken Temple Maneuver Card hidden." or "Sunken Temple Maneuver Card enabled.")
    return true
  elseif sub == "ui" then
    if ns.UI and ns.UI.Workspace and ns.UI.GoldFarms then
      ns.UI.GoldFarms.EnsureHost()
      ns.UI.Workspace.Toggle("gold")
      ns.UI.GoldFarms.Dispatch("SET_SUBVIEW", { subView = "dungeons" })
    end
    return true
  elseif sub == "" or sub == "status" then
    local vm = coach.GetViewModel()
    ns.Compat.Print(
      string.format(
        "=== ForeverHub Sunken Temple Coach (RC1) | State: %s | Gate: %s | Phase: %d/%d ===",
        tostring(vm.sessionState),
        tostring(vm.instanceClassification),
        tonumber(vm.phaseIndex) or 0,
        tonumber(vm.totalPhases) or 6
      )
    )
    ns.Compat.Print("  " .. tostring(vm.landmarkLine))
    ns.Compat.Print("  " .. tostring(vm.instructionLine))
    ns.Compat.Print("  Commands: /fh st [status | ui | card | probe [ctx] | start | confirm [1-6|all|reset] | rearm | next | prev | finish | abort | reset | autopsy | show | hide]")
    return vm
  end

  ns.Compat.Print("Usage: /fh st [status | ui | card | probe [ctx] | start | confirm [1-6|all|reset] | rearm | next | prev | finish | abort | reset | autopsy | show | hide]")
  return false
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

  if type(catalog.arcaneGrindFarms) == "table" and #catalog.arcaneGrindFarms > 0 then
    ns.Compat.Print("=== ForeverHub Level 46-60 Arcane ST Mage Grind Candidates (Source-Verified Coords; Unverified Performance) ===")
    for _, farm in ipairs(catalog.arcaneGrindFarms) do
      local gphMeta = farm.gphMeta or {}
      local xpMeta = farm.xpMeta or {}
      local spawnTotal = 0
      for _, st in ipairs(farm.travelSteps or {}) do
        if st.kind == "grind" and type(st.spawnNodes) == "table" then
          spawnTotal = spawnTotal + #st.spawnNodes
        end
      end
      local purseDesc
      if gphMeta.vendorFloorStatus == "unmeasured_until_sampled" and gphMeta.lowGold == nil then
        purseDesc = "Purse floor: Unmeasured until sampled in-client"
      else
        purseDesc = string.format(
          "Est. vendor liq.: %d-%dg/hr (unverified) | Predicted total: %d-%dg/hr (unverified)",
          tonumber(gphMeta.lowGold) or 0,
          tonumber(gphMeta.highGold) or 0,
          tonumber(gphMeta.predictedTotalLowGold or gphMeta.lowGold) or 0,
          tonumber(gphMeta.predictedTotalHighGold or gphMeta.highGold) or 0
        )
      end
      ns.Compat.Print(
        string.format(
          "Candidate %d [%s] %s (Lv %s) — ~%d-%d XP/mob (~%dk-%dk XP/hr @ 90 kills/hr scenario) | %s (%d recorded spawn pts)",
          tonumber(farm.candidateOrder or farm.rank) or 0,
          tostring(farm.farmID),
          tostring(farm.title),
          tostring(farm.recommendedLevelRange or "46-60"),
          tonumber(xpMeta.xpPerMobLow) or 0,
          tonumber(xpMeta.xpPerMobHigh) or 0,
          math.floor(((tonumber(xpMeta.xpPerHourLow) or 0) + 500) / 1000),
          math.floor(((tonumber(xpMeta.xpPerHourHigh) or 0) + 500) / 1000),
          purseDesc,
          spawnTotal
        )
      )
      ns.Compat.Print("  How to Get There: " .. tostring(farm.howToGetThereSummary or ""))
      local warnings = ns.Domain.GoldFarms.GetReservationWarningsForFarm(farm)
      for _, w in ipairs(warnings) do
        ns.Compat.Print("  |cffffaa00" .. tostring(w.message) .. "|r")
      end
    end
  end

  if type(catalog.quarantinedFarms) == "table" and #catalog.quarantinedFarms > 0 then
    ns.Compat.Print("--- Quarantined / Excluded Trap Farms (Do NOT Solo Grind) ---")
    for _, qf in ipairs(catalog.quarantinedFarms) do
      ns.Compat.Print(string.format("  [SKIP] %s — %s", tostring(qf.title), tostring(qf.reason)))
    end
  end
  ns.Compat.Print("Start navigation + Net Purse Change / Active Hr meter with '/fh gold start <id>', '/fh gold arcane <id>', or '/fh gold' to open window.")
end

local function resolveActiveGoldFarmStep()
  local gProg = ns.State and ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress()
  local GF = ns.Domain and ns.Domain.GoldFarms
  if not gProg or not GF or not gProg.selectedFarmID then
    return nil, nil, gProg
  end
  local eval = GF.Evaluate(nil, gProg)
  return eval and eval.farm or nil, eval and eval.activeStep or nil, gProg
end

local function isFarmTargetIdentity(farm, step, npcID, npcName, gProg)
  local SR = ns.Domain and ns.Domain.SpawnRadar
  if SR and SR.GetTargetMatchSets and (farm or step) then
    local idSet, nameSet = SR.GetTargetMatchSets(farm, step, gProg)
    if (npcID and idSet[npcID] == true) or (npcName and nameSet[npcName] == true) then
      return true
    end
  end
  if type(farm) == "table" and type(farm.targets) == "table" and step == nil then
    for _, t in ipairs(farm.targets) do
      if (npcID and tonumber(t.npcID) == npcID) or (npcName and tostring(t.name or "") == npcName) then
        return true
      end
    end
  end
  return false
end

function Events.OnGoldFarmTargetOrCombatPull()
  local SR = ns.Domain and ns.Domain.SpawnRadar
  if not SR or not SR.RecordPullObservation then
    return
  end
  local farm, step, gProg = resolveActiveGoldFarmStep()
  if farm and step and gProg and gProg.mode == "standalone" and SR.IsActiveForStep(farm, step, gProg) then
    SR.RecordPullObservation(farm, step, nil, nil, nil)
  end
end

function Events.OnGoldFarmUnitDied(destGUID, destName)
  if ns.Compat and ns.Compat.IsSecretOrRestrictedValue then
    if ns.Compat.IsSecretOrRestrictedValue(destGUID) then
      destGUID = nil
    end
    if ns.Compat.IsSecretOrRestrictedValue(destName) then
      destName = nil
    end
  end
  local cleanGUID = (type(destGUID) == "string" and destGUID ~= "") and destGUID or nil
  local cleanName = (type(destName) == "string" and destName ~= "") and destName or nil
  if not cleanGUID and not cleanName then
    return
  end

  local npcID = (cleanGUID and ns.Compat and ns.Compat.ExtractCreatureNpcIDFromGUID)
    and ns.Compat.ExtractCreatureNpcIDFromGUID(cleanGUID)
    or nil
  local farm, step, gProg = resolveActiveGoldFarmStep()
  if not farm or not isFarmTargetIdentity(farm, step, npcID, cleanName, gProg) then
    return
  end

  if ns.State and ns.State.RecordGoldFarmVerifiedCampKill then
    ns.State.RecordGoldFarmVerifiedCampKill({
      guid = cleanGUID,
      npcID = npcID,
      npcName = cleanName,
    })
  end

  local SR = ns.Domain and ns.Domain.SpawnRadar
  if SR and gProg and gProg.mode == "standalone" and step and step.kind == "grind" and SR.IsActiveForStep(farm, step, gProg) then
    local killRes = SR.RecordVerifiedKillObservation(
      farm,
      step,
      { guid = cleanGUID, npcID = npcID, npcName = cleanName },
      nil,
      nil,
      gProg
    )
    if killRes and (tonumber(killRes.suppressed) or 0) > 0 then
      if ns.UI and ns.UI.Navigation and ns.UI.Navigation.TickSpawnRadar then
        ns.UI.Navigation.TickSpawnRadar(0, true)
      end
      if ns.UI and ns.UI.WorldMapPins and ns.UI.WorldMapPins.RequestRefresh then
        ns.UI.WorldMapPins.RequestRefresh()
      end
    end
  end

  if ns.UI and ns.UI.GoldFarms and ns.UI.GoldFarms.RefreshIfShown then
    ns.UI.GoldFarms.RefreshIfShown()
  end
end

function Events.OnGoldFarmCombatOrLootEvent(event, arg1)
  if event ~= "CHAT_MSG_COMBAT_XP_GAIN" then
    -- CRITICAL (Astra P1-1): LOOT_OPENED is NEVER an independent kill or radar suppression trigger!
    return
  end
  if ns.Compat and ns.Compat.IsSecretOrRestrictedValue and ns.Compat.IsSecretOrRestrictedValue(arg1) then
    return
  end
  if type(arg1) ~= "string" or arg1 == "" then
    return
  end

  local mobName, xpStr = string.match(arg1, "^(.-)%s+dies,%s+you%s+gain%s+(%d+)%s+experience")
  if type(mobName) ~= "string" or mobName == "" then
    return
  end
  local parsedXP = tonumber(xpStr)
  local farm, step, gProg = resolveActiveGoldFarmStep()
  local matchesFarmTarget = farm and isFarmTargetIdentity(farm, step, nil, mobName, gProg) or false

  if matchesFarmTarget then
    local xpStateOk = false
    if ns.Compat and type(ns.Compat.GetPlayerXPState) == "function" then
      local xpSt = ns.Compat.GetPlayerXPState()
      xpStateOk = (xpSt and (xpSt.status == "ok" or xpSt.status == "capped" or xpSt.status == "transitional_cap_zero"))
    end
    if xpStateOk and ns.State and ns.State.RecordGoldFarmVerifiedCampKill then
      ns.State.RecordGoldFarmVerifiedCampKill({
        npcName = mobName,
        expectedXP = parsedXP,
      })
    elseif (not xpStateOk) and ns.State and ns.State.RecordGoldFarmXPGain then
      ns.State.RecordGoldFarmXPGain(parsedXP, true)
    end
  end

  local SR = ns.Domain and ns.Domain.SpawnRadar
  if SR and farm and step and gProg and gProg.mode == "standalone" and step.kind == "grind" and SR.IsActiveForStep(farm, step, gProg) then
    local killRes = SR.RecordVerifiedKillObservation(
      farm,
      step,
      { npcName = mobName },
      nil,
      nil,
      gProg
    )
    if killRes and (tonumber(killRes.suppressed) or 0) > 0 then
      if ns.UI and ns.UI.Navigation and ns.UI.Navigation.TickSpawnRadar then
        ns.UI.Navigation.TickSpawnRadar(0, true)
      end
      if ns.UI and ns.UI.WorldMapPins and ns.UI.WorldMapPins.RequestRefresh then
        ns.UI.WorldMapPins.RequestRefresh()
      end
    end
  end

  if ns.UI and ns.UI.GoldFarms and ns.UI.GoldFarms.RefreshIfShown then
    ns.UI.GoldFarms.RefreshIfShown()
  end
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
        ns.Compat.Print("Opened ForeverHub Gold Farms advisor. Click 'Navigate (Arrow / Pin)' or run '/fh gold start 1' / '/fh gold arcane 1'.")
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
    local xpState = (ns.Compat and ns.Compat.GetPlayerXPState and ns.Compat.GetPlayerXPState()) or nil
    local xpReport = ns.Domain.GoldFarms.EvaluateSessionXP and ns.Domain.GoldFarms.EvaluateSessionXP(eval and eval.farm, sessSnap, xpState) or nil
    local navLabel = (progress.mode ~= "paused"
      and ns.UI.Navigation
      and ns.UI.Navigation.activeContext == "gold_farm"
      and ns.UI.Navigation.lastStatus
      and ns.UI.Navigation.lastStatus.navigationLabel) or "Paused"
    if eval and eval.farm then
      local xpSuffix = ""
      if eval.farm.track == "arcane_lvl47_st" and xpReport then
        xpSuffix = " | Session XP/hr: " .. tostring(xpReport.liveLabel)
      end
      ns.Compat.Print(
        string.format(
          "Gold Farm [Candidate %d %s] (%s | Nav: %s) | %s | Ref: %s | Net Purse Change / Active Hr: %s%s",
          tonumber(eval.farm.candidateOrder or eval.farm.rank) or 1,
          tostring(eval.farm.shortLabel or eval.farm.farmID),
          tostring(progress.mode),
          tostring(navLabel),
          formatGoldHopSummary(eval),
          tostring(gphReport.communityLabel),
          tostring(gphReport.liveLabel),
          xpSuffix
        )
      )
    else
      ns.Compat.Print("Gold Farm: Paused (no farm selected). Use '/fh gold list', '/fh gold start 1', or '/fh gold arcane 1'.")
    end
    return
  elseif sub == "list" then
    Events.PrintGoldFarmsList()
    return
  elseif sub == "arcane" then
    local uiState = ns.State.GetWorkspaceUIState and ns.State.GetWorkspaceUIState()
    if uiState and uiState.goldView then
      uiState.goldView.selectedTrack = "arcane_lvl47_st"
    end
    local q = (arg ~= "") and arg or "arcane:1"
    if tonumber(q) then
      q = "arcane:" .. tostring(tonumber(q))
    end
    local ok, evalOrErr = ns.Domain.GoldFarms.Start(q, nil, nil, nil, "arcane_lvl47_st")
    if not ok then
      ns.Compat.Print("Arcane grind start failed: " .. tostring(evalOrErr))
      return
    end
    if uiState and uiState.goldView and evalOrErr.farm then
      uiState.goldView.focusedFarmID = evalOrErr.farm.farmID
    end
    local arrowSettings = ns.State.GetArrowSettings()
    arrowSettings.hudHidden = false
    local navSt = ns.UI.Navigation.SyncFromGoldFarmEvaluation(evalOrErr)
    local farm = evalOrErr.farm
    local gphMeta = farm and farm.gphMeta or {}
    local xpMeta = farm and farm.xpMeta or {}
    local purseShort = (gphMeta.vendorFloorStatus == "unmeasured_until_sampled" and gphMeta.lowGold == nil)
      and "Purse: Unmeasured until sampled"
      or string.format(
        "Predicted total: %d-%dg/hr unverified",
        tonumber(gphMeta.predictedTotalLowGold or gphMeta.lowGold) or 0,
        tonumber(gphMeta.predictedTotalHighGold or gphMeta.highGold) or 0
      )
    ns.Compat.Print(
      string.format(
        "Started Lv 46-60 Arcane ST Grind Candidate %d: %s (Nav: %s | ~%d-%d XP/mob est. | %s)",
        tonumber(farm and (farm.candidateOrder or farm.rank)) or 1,
        tostring(farm and farm.title or ""),
        tostring(navSt.navigationLabel),
        tonumber(xpMeta.xpPerMobLow) or 0,
        tonumber(xpMeta.xpPerMobHigh) or 0,
        purseShort
      )
    )
    ns.Compat.Print("  Current Hop -> " .. formatGoldHopSummary(evalOrErr))
    local warnings = ns.Domain.GoldFarms.GetReservationWarningsForFarm(farm)
    for _, w in ipairs(warnings) do
      ns.Compat.Print("  |cffffaa00" .. tostring(w.message) .. "|r")
    end
    if ns.UI and ns.UI.WorldMapPins and ns.UI.WorldMapPins.RequestRefresh then
      ns.UI.WorldMapPins.RequestRefresh()
    end
    if ns.UI and ns.UI.GoldFarms and ns.UI.GoldFarms.RefreshIfShown then
      ns.UI.GoldFarms.RefreshIfShown()
    end
    return
  elseif sub == "track" then
    local uiState = ns.State.GetWorkspaceUIState and ns.State.GetWorkspaceUIState()
    local a = string.lower(arg or "")
    local targetTrack = nil
    if a == "arcane" or a == "47" or a == "st" or a == "arcane_lvl47_st" then
      targetTrack = "arcane_lvl47_st"
    elseif a == "mount" or a == "40" or a == "lvl40_mount" then
      targetTrack = "lvl40_mount"
    elseif a == "auto" or a == "" then
      targetTrack = "auto"
    end
    if not targetTrack then
      ns.Compat.Print("Usage: /fh gold track <arcane | mount | auto>")
      return
    end
    if uiState and uiState.goldView then
      uiState.goldView.selectedTrack = targetTrack
      local eff = ns.Domain.GoldFarms.GetEffectiveTrack(uiState)
      local list = ns.Domain.GoldFarms.GetFarmsForTrack(eff)
      if list and list[1] then
        uiState.goldView.focusedFarmID = list[1].farmID
      end
    end
    local effNow = ns.Domain.GoldFarms.GetEffectiveTrack(uiState)
    ns.Compat.Print(string.format("Gold Farms track set to '%s' (active view: %s).", targetTrack, effNow))
    if ns.UI and ns.UI.WorldMapPins and ns.UI.WorldMapPins.RequestRefresh then
      ns.UI.WorldMapPins.RequestRefresh()
    end
    if ns.UI and ns.UI.GoldFarms and ns.UI.GoldFarms.RefreshIfShown then
      ns.UI.GoldFarms.RefreshIfShown()
    end
    return
  elseif sub == "radar" then
    local gProg = ns.State.GetGoldFarmProgress()
    local SR = ns.Domain and ns.Domain.SpawnRadar
    local a = string.lower(arg or "")
    if a == "on" or a == "off" or a == "auto" then
      gProg.spawnRadarMode = a
      if ns.UI and ns.UI.Navigation and ns.UI.Navigation.SyncFromGoldFarmEvaluation then
        ns.UI.Navigation.SyncFromGoldFarmEvaluation(nil, gProg)
      end
      if ns.UI and ns.UI.WorldMapPins and ns.UI.WorldMapPins.RequestRefresh then
        ns.UI.WorldMapPins.RequestRefresh()
      end
      if ns.UI and ns.UI.GoldFarms and ns.UI.GoldFarms.RefreshIfShown then
        ns.UI.GoldFarms.RefreshIfShown()
      end
      ns.Compat.Print("Spawn Radar mode set to: " .. string.upper(a))
      return
    elseif a == "reset" then
      if SR and SR.BumpWorldSessionEpoch then
        SR.BumpWorldSessionEpoch("manual_reset")
      end
      if ns.UI and ns.UI.Navigation and ns.UI.Navigation.TickSpawnRadar then
        ns.UI.Navigation.TickSpawnRadar(0, true)
      end
      if ns.UI and ns.UI.WorldMapPins and ns.UI.WorldMapPins.RequestRefresh then
        ns.UI.WorldMapPins.RequestRefresh()
      end
      if ns.UI and ns.UI.GoldFarms and ns.UI.GoldFarms.RefreshIfShown then
        ns.UI.GoldFarms.RefreshIfShown()
      end
      ns.Compat.Print("Spawn Radar revisit observations cleared (all candidate points reset to unvisited).")
      return
    else
      local eval = ns.Domain.GoldFarms.Evaluate(nil, gProg)
      local rawM, isAct = "auto", false
      if SR and SR.GetEffectiveMode then
        rawM, isAct = SR.GetEffectiveMode(eval and eval.farm, gProg)
      end
      local sum = SR and SR.state and SR.state.lastSummary
      local nodeDesc = (sum and sum.npcName and string.format("%s (%d/%d active pool)", tostring(sum.npcName), tonumber(sum.unobservedCount or sum.readyCount) or 0, tonumber(sum.totalCount) or 0))
        or "Idle"
      ns.Compat.Print(string.format("Spawn Radar: mode=%s (active=%s) | Target=%s", string.upper(tostring(rawM)), tostring(isAct), nodeDesc))
      return
    end
  elseif sub == "skip" then
    local SR = ns.Domain and ns.Domain.SpawnRadar
    local farm, step, gProg = resolveActiveGoldFarmStep()
    if not SR or not farm or not step or step.kind ~= "grind" then
      ns.Compat.Print("No active grind subcamp to skip a spawn point on. Start an Arcane ST grind first.")
      return
    end
    local skipRes = SR.SkipCurrentLocation(farm, step, nil, gProg)
    if skipRes and skipRes.ok then
      if ns.UI and ns.UI.Navigation and ns.UI.Navigation.TickSpawnRadar then
        ns.UI.Navigation.TickSpawnRadar(0, true)
      end
      if ns.UI and ns.UI.WorldMapPins and ns.UI.WorldMapPins.RequestRefresh then
        ns.UI.WorldMapPins.RequestRefresh()
      end
      if ns.UI and ns.UI.GoldFarms and ns.UI.GoldFarms.RefreshIfShown then
        ns.UI.GoldFarms.RefreshIfShown()
      end
      ns.Compat.Print(
        string.format(
          "Skipped spawn point #%d (%s) for ~%ds revisit estimate.",
          tonumber(skipRes.nodeIndex) or 1,
          tostring(skipRes.npcName or "Target"),
          tonumber(skipRes.revisitSeconds) or 120
        )
      )
    else
      ns.Compat.Print("Could not skip current spawn point (" .. tostring(skipRes and skipRes.reason or "unavailable") .. ").")
    end
    return
  elseif sub == "pins" then
    local gProg = ns.State.GetGoldFarmProgress()
    local a = string.lower(arg or "")
    if a == "" then
      local cur = tostring(gProg.spawnPinMode or "active")
      if cur == "active" then
        a = "all"
      elseif cur == "all" then
        a = "off"
      else
        a = "active"
      end
    end
    if a ~= "active" and a ~= "all" and a ~= "off" then
      ns.Compat.Print("Usage: /fh gold pins <active | all | off>")
      return
    end
    gProg.spawnPinMode = a
    if ns.UI and ns.UI.WorldMapPins and ns.UI.WorldMapPins.RequestRefresh then
      ns.UI.WorldMapPins.RequestRefresh()
    end
    if ns.UI and ns.UI.GoldFarms and ns.UI.GoldFarms.RefreshIfShown then
      ns.UI.GoldFarms.RefreshIfShown()
    end
    ns.Compat.Print("Gold Farm spawn pins mode set to: " .. string.upper(a))
    return
  elseif sub == "macro" then
    local SR = ns.Domain and ns.Domain.SpawnRadar
    if not SR then
      ns.Compat.Print("SpawnRadar module unavailable.")
      return
    end
    local allowAdopt = false
    local perChar = false
    local farmQueryParts = {}
    for tok in string.gmatch(tostring(arg or ""), "%S+") do
      local lowTok = string.lower(tok)
      if lowTok == "adopt" or lowTok == "force" then
        allowAdopt = true
      elseif lowTok == "char" or lowTok == "character" then
        perChar = true
      else
        table.insert(farmQueryParts, tok)
      end
    end
    local farmQuery = table.concat(farmQueryParts, " ")
    local uiState = ns.State.GetWorkspaceUIState and ns.State.GetWorkspaceUIState()
    local gProg = ns.State.GetGoldFarmProgress()
    local farm = nil
    if farmQuery ~= "" then
      local pref = (uiState and uiState.goldView and uiState.goldView.selectedTrack == "arcane_lvl47_st") and "arcane_lvl47_st" or nil
      farm = ns.Domain.GoldFarms.ResolveFarm(farmQuery, nil, pref)
    end
    if not farm and gProg and gProg.selectedFarmID then
      farm = ns.Domain.GoldFarms.LookupFarmByID(gProg.selectedFarmID)
    end
    if not farm and uiState and uiState.goldView and uiState.goldView.focusedFarmID then
      farm = ns.Domain.GoldFarms.LookupFarmByID(uiState.goldView.focusedFarmID)
    end
    if not farm then
      farm = ns.Domain.GoldFarms.LookupFarmByID("arcane_hinterlands_owlbeasts") or ns.Domain.GoldFarms.ResolveFarm("1")
    end
    if not farm then
      ns.Compat.Print("Could not resolve a Gold Farm for target macro.")
      return
    end
    local grindStep = nil
    local eval = ns.Domain.GoldFarms.Evaluate(nil, gProg)
    if eval and eval.farm and eval.farm.farmID == farm.farmID and eval.activeStep and eval.activeStep.kind == "grind" then
      grindStep = eval.activeStep
    else
      for _, st in ipairs(farm.travelSteps or {}) do
        if st.kind == "grind" then
          grindStep = st
          break
        end
      end
    end
    local res = SR.CreateOrAdoptTargetMacro(farm, grindStep, {
      allowAdoptModified = allowAdopt,
      perCharacter = perChar,
    })
    if ns.UI and ns.UI.GoldFarms and ns.UI.GoldFarms.RefreshIfShown then
      ns.UI.GoldFarms.RefreshIfShown()
    end
    if res and res.ok then
      ns.Compat.Print(
        string.format(
          "Target macro '%s' %s (%dB, %s scope) for %s! Auto-sync enabled for owned unmodified body.",
          tostring(res.macroName),
          tostring(res.action),
          tonumber(res.byteLength) or 0,
          tostring(res.scope or "global"),
          tostring((grindStep and grindStep.title) or farm.title)
        )
      )
    elseif res and (res.reason == "combat_lockdown" or res.reason == "in_combat_lockdown" or res.reason == "lockdown_probe_unavailable") then
      ns.Compat.Print("Cannot create/edit macro '" .. tostring(res.macroName or "FH_Target") .. "' (" .. tostring(res.status or res.reason) .. "). Retry out of combat.")
    elseif res and res.reason == "duplicate_macro_scope_conflict" then
      ns.Compat.Print("Macro '" .. tostring(res.macroName or "FH_Target") .. "' exists in both General and Character slots — delete one copy so ownership is unambiguous.")
    elseif res and res.reason == "user_modified_requires_adopt" then
      ns.Compat.Print("Macro '" .. tostring(res.macroName or "FH_Target") .. "' was modified outside ForeverHub (status: User modified). Run '/fh gold macro adopt' to re-adopt auto-sync.")
    elseif res and res.reason == "macro_name_collision" then
      ns.Compat.Print("Existing macro '" .. tostring(res.macroName or "FH_Target") .. "' was not created by ForeverHub; refusing to overwrite user macro (use '/fh gold macro adopt' only if you intend ForeverHub to own it).")
    elseif res and res.reason == "macro_slots_full" then
      ns.Compat.Print("Macro slots are full in the requested scope; free a macro slot before creating '" .. tostring(res.macroName or "FH_Target") .. "'.")
    elseif res and res.reason == "macro_overflow" then
      ns.Compat.Print("Blocked — localized macro exceeds 255 bytes (" .. tostring(res.byteLength) .. "B); refusing partial macro generation.")
    else
      ns.Compat.Print(
        string.format(
          "Target macro (%s / %s) for %s:\n%s",
          tostring(res and res.status or "Unavailable"),
          tostring(res and res.reason or "unavailable"),
          tostring(farm.title),
          tostring(res and res.body or "")
        )
      )
    end
    return
  elseif sub == "start" then
    local uiState = ns.State.GetWorkspaceUIState and ns.State.GetWorkspaceUIState()
    local prefTrack = (uiState and uiState.goldView and uiState.goldView.selectedTrack == "arcane_lvl47_st") and "arcane_lvl47_st" or nil
    local ok, evalOrErr = ns.Domain.GoldFarms.Start(arg, nil, nil, nil, prefTrack)
    if not ok then
      ns.Compat.Print("Gold farm start failed: " .. tostring(evalOrErr))
      return
    end
    if uiState and uiState.goldView and evalOrErr.farm then
      uiState.goldView.focusedFarmID = evalOrErr.farm.farmID
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
    if ns.UI and ns.UI.WorldMapPins and ns.UI.WorldMapPins.RequestRefresh then
      ns.UI.WorldMapPins.RequestRefresh()
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
    if ns.UI and ns.UI.WorldMapPins and ns.UI.WorldMapPins.RequestRefresh then
      ns.UI.WorldMapPins.RequestRefresh()
    end
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
    if ns.UI and ns.UI.WorldMapPins and ns.UI.WorldMapPins.RequestRefresh then
      ns.UI.WorldMapPins.RequestRefresh()
    end
    if ns.UI and ns.UI.GoldFarms and ns.UI.GoldFarms.RefreshIfShown then
      ns.UI.GoldFarms.RefreshIfShown()
    end
    return
  elseif sub == "pause" then
    local _, eval = ns.Domain.GoldFarms.Pause()
    ns.UI.Navigation.SyncFromGoldFarmEvaluation(eval)
    ns.Compat.Print("Paused Gold Farm navigation & Net Purse Change / Active Hr timer.")
    if ns.UI and ns.UI.WorldMapPins and ns.UI.WorldMapPins.RequestRefresh then
      ns.UI.WorldMapPins.RequestRefresh()
    end
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
    if ns.UI and ns.UI.WorldMapPins and ns.UI.WorldMapPins.RequestRefresh then
      ns.UI.WorldMapPins.RequestRefresh()
    end
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
    if ns.UI and ns.UI.WorldMapPins and ns.UI.WorldMapPins.RequestRefresh then
      ns.UI.WorldMapPins.RequestRefresh()
    end
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
      local lowArg = string.lower(farmArg)
      if lowArg == "arcane" then
        ns.Bridges.RXPBridge.RegisterAllGoldFarmGuides(true, nil, "arcane_lvl47_st")
      elseif farmArg ~= "" and lowArg ~= "all" then
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
      ns.Compat.Print("Usage: /fh gold export rxp [1-5 | arcane | farmID | all]")
    end
    return
  elseif sub == "doctor" then
    Events.RunGoldFarmsDoctor()
    return
  else
    -- Convenience: allow `/fh gold 1`, `/fh gold hinterlands`, or `/fh gold badlands` directly!
    local uiState = ns.State.GetWorkspaceUIState and ns.State.GetWorkspaceUIState()
    local prefTrack = (uiState and uiState.goldView and uiState.goldView.selectedTrack == "arcane_lvl47_st") and "arcane_lvl47_st" or nil
    local directFarm = ns.Domain.GoldFarms.ResolveFarm(cleaned, nil, prefTrack)
    if directFarm then
      Events.HandleGoldSubcommand("start " .. directFarm.farmID)
      return
    end
    ns.Compat.Print("Gold Farm commands: /fh gold | /fh gold list | /fh gold start <1-19|zone> | /fh gold arcane <1-19> | /fh gold track <arcane|mount|auto> | /fh gold radar <auto|on|off|reset> | /fh gold skip | /fh gold pins <active|all|off> | /fh gold macro [adopt|char|<farm>] | /fh gold reenter | /fh gold next | /fh gold prev | /fh gold pause | /fh gold stop [reset] | /fh gold reset | /fh gold export rxp [farm|arcane] | /fh gold doctor")
  end
end

resyncActiveNavigationContext = function()
  if not (ns.UI and ns.UI.Navigation) then
    return
  end
  ns.UI.Navigation.RefreshArrowSettings()
  local gProg = ns.State.GetGoldFarmProgress()
  if gProg and gProg.mode ~= "paused" then
    ns.UI.Navigation.SyncFromGoldFarmEvaluation(nil, gProg)
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

  if cmd == "" or cmd == "crates" or cmd == "ui" or cmd == "advisor" or cmd == "deck" then
    local tabArg = string.lower(string.gsub(tostring(rest or ""), "^%s*(.-)%s*$", "%1"))
    if (cmd == "advisor" or cmd == "deck" or (cmd == "ui" and (tabArg == "advisor" or tabArg == "deck"))) and ns.UI and ns.UI.Workspace then
      if ns.UI.CommandDeck and ns.UI.CommandDeck.EnsureHost then
        ns.UI.CommandDeck.EnsureHost()
      end
      ns.UI.Workspace.Toggle("advisor")
    elseif cmd == "ui" and (tabArg == "gold" or tabArg == "mount" or tabArg == "farms") and ns.UI and ns.UI.Workspace then
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
  elseif cmd == "st" or cmd == "sunkentemple" then
    Events.HandleSunkenTempleSubcommand(rest)
    return
  elseif cmd == "gold" or cmd == "farm" or cmd == "farms" then
    Events.HandleGoldSubcommand(rest)
    return
  elseif cmd == "probe" then
    Events.RunProbeCommand(rest)
    return
  elseif cmd == "discovery" then
    Events.HandleDiscoverySubcommand(rest)
    return
  elseif cmd == "market" or cmd == "mk" then
    Events.HandleMarketSubcommand(rest)
    return
  elseif cmd == "research" then
    if ns.UI and ns.UI.ResearchView and ns.UI.ResearchView.Toggle then
      ns.UI.ResearchView.Toggle()
    elseif ns.UI and ns.UI.Workspace and ns.UI.Workspace.Toggle then
      ns.UI.Workspace.Toggle("research")
    end
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
  elseif cmd == "raidready" or cmd == "rr" or cmd == "attune" then
    local RRC = ns.Domain and ns.Domain.RaidReadinessCoach
    local Nav = ns.UI and ns.UI.Navigation
    if not RRC then
      ns.Compat.Print("RaidReadinessCoach unavailable.")
      return
    end
    local sub, arg2 = string.match(rest or "", "^(%S+)%s*(.-)$")
    sub = string.lower(sub or "start")
    arg2 = string.gsub(arg2 or "", "^%s*(.-)%s*$", "%1")
    if sub == "stop" or sub == "off" then
      if Nav and Nav.StopRaidReadinessCoach then
        Nav.StopRaidReadinessCoach()
      end
      ns.Compat.Print("Raid-Ready & Attunement Arrow stopped.")
    elseif sub == "linken" then
      if Nav and Nav.StartRaidReadinessCoach then
        Nav.StartRaidReadinessCoach("linken_solo")
      end
      local ev = RRC.Evaluate()
      ns.Compat.Print("Raid-Ready Arrow (Linken Track): " .. tostring(ev.activeStep and ev.activeStep.shortTitle or ""))
    elseif sub == "core" or sub == "start" or sub == "on" then
      if Nav and Nav.StartRaidReadinessCoach then
        Nav.StartRaidReadinessCoach("core_attune")
      end
      local ev = RRC.Evaluate()
      ns.Compat.Print("Raid-Ready Arrow (Core Onyxia/Princess Spine): " .. tostring(ev.activeStep and ev.activeStep.shortTitle or ""))
    elseif sub == "skip" and arg2 ~= "" then
      local ok, reason = RRC.SetStepSkipped(arg2, true)
      if ok then
        local ev = RRC.RequestCoalescedRefresh(false)
        ns.Compat.Print("Skipped optional step " .. arg2 .. " -> Next: " .. tostring(ev.activeStep and ev.activeStep.shortTitle or ""))
      else
        ns.Compat.Print("Cannot skip step " .. arg2 .. ": " .. tostring(reason))
      end
    elseif sub == "unskip" and arg2 ~= "" then
      local ok, reason = RRC.SetStepSkipped(arg2, false)
      if ok then
        local ev = RRC.RequestCoalescedRefresh(false)
        ns.Compat.Print("Unskipped step " .. arg2 .. " -> Next: " .. tostring(ev.activeStep and ev.activeStep.shortTitle or ""))
      else
        ns.Compat.Print("Cannot unskip step " .. arg2 .. ": " .. tostring(reason))
      end
    elseif sub == "reset" then
      RRC.ClearAllSkips()
      local ev = RRC.RequestCoalescedRefresh(false)
      ns.Compat.Print("Cleared optional skips -> Next: " .. tostring(ev.activeStep and ev.activeStep.shortTitle or ""))
    else
      local ev = RRC.Evaluate()
      ns.Compat.Print(string.format(
        "Raid-Ready Status: %s | Next (%s): %s | %s",
        tostring(ev.onyxiaStatusLabel),
        tostring(ev.activeTrack),
        tostring(ev.activeStep and ev.activeStep.shortTitle or ""),
        tostring(ev.professionStatus and ev.professionStatus.summaryText or "")
      ))
    end
    return
  else
    ns.Compat.Print("Commands: /fh | /fh raidready [start|stop|core|linken|skip <id>|unskip <id>|reset|status] | /fh minimap [show|hide|reset] | /fh arrow [...] | /fh gold [...] | /fh mount | /fh doctor | /fh selftest")
  end
end

local eventFrame = CreateFrame and CreateFrame("Frame")
if eventFrame then
  local function safeReg(evName)
    if ns.Compat and type(ns.Compat.SafeRegisterFrameEvent) == "function" then
      ns.Compat.SafeRegisterFrameEvent(eventFrame, evName)
    elseif type(eventFrame.RegisterEvent) == "function" then
      pcall(eventFrame.RegisterEvent, eventFrame, evName)
    end
  end

  safeReg("ADDON_LOADED")
  safeReg("PLAYER_ENTERING_WORLD")
  safeReg("BAG_UPDATE_DELAYED")
  safeReg("BANKFRAME_OPENED")
  safeReg("BANKFRAME_CLOSED")
  safeReg("MODIFIER_STATE_CHANGED")
  -- NOTE: `COMBAT_LOG_EVENT_UNFILTERED` is NEVER registered here — in Interface 16001
  -- (`CombatLogDocumentation.lua`: `HasRestrictions = true, CallbackEvent = true`), calling
  -- `Frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")` fires C++ `ADDON_ACTION_FORBIDDEN`
  -- even inside `pcall` and taints `Enum.ForbiddenAspect.EventRegistrations` on `eventFrame`!
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
    "PLAYER_EQUIPMENT_CHANGED",
    "PLAYER_MONEY",
    "MAIL_SHOW",
    "MAIL_INBOX_UPDATE",
    "SEND_MAIL_MONEY_CHANGED",
    "SEND_MAIL_COD_CHANGED",
    "MAIL_CLOSED",
    "AUCTION_HOUSE_SHOW",
    "AUCTION_ITEM_LIST_UPDATE",
    "NEW_AUCTION_UPDATE",
    "AUCTION_MULTISELL_UPDATE",
    "AUCTION_HOUSE_CLOSED",
    "MERCHANT_SHOW",
    "MERCHANT_CLOSED",
    "UPDATE_INVENTORY_DURABILITY",
    "TRADE_SHOW",
    "TRADE_CLOSED",
    "TRAINER_SHOW",
    "TRAINER_CLOSED",
    "SKILL_LINES_CHANGED",
    "TRADE_SKILL_SHOW",
    "TRADE_SKILL_UPDATE",
    "TRADE_SKILL_CLOSE",
    "CRAFT_SHOW",
    "CRAFT_UPDATE",
    "CRAFT_CLOSE",
    "BAG_UPDATE_COOLDOWN",
    "GOSSIP_SHOW",
    "GOSSIP_CLOSED",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "UPDATE_MACROS",
    "PLAYER_TARGET_CHANGED",
    "PLAYER_XP_UPDATE",
    "PLAYER_LEVEL_UP",
    "UPDATE_EXHAUSTION",
    "CHAT_MSG_COMBAT_XP_GAIN",
    "ZONE_CHANGED_NEW_AREA",
    "ZONE_CHANGED",
    "ZONE_CHANGED_INDOORS",
    "MINIMAP_ZONE_CHANGED",
    "PLAYER_DEAD",
    "PLAYER_ALIVE",
    "PLAYER_UNGHOST",
    "DISPLAY_SIZE_CHANGED",
    "UI_SCALE_CHANGED",
    "PLAYER_LOGOUT",
  }) do
    safeReg(optEvent)
  end
  if ns.Domain and ns.Domain.SunkenTempleCoach and type(ns.Domain.SunkenTempleCoach.AttachEventRegistrations) == "function" then
    pcall(ns.Domain.SunkenTempleCoach.AttachEventRegistrations, eventFrame)
  end

  local function isFiniteNonNeg(v)
    return type(v) == "number" and v == v and v >= 0 and v <= 9007199254740991 and math.floor(v) == v
  end

  local function scanLiveMailInboxRows()
    local rows = {}
    local getNum = _G.GetInboxNumItems
    local getHdr = _G.GetInboxHeaderInfo
    local getInv = _G.GetInboxInvoiceInfo
    if type(getNum) ~= "function" or type(getHdr) ~= "function" then
      return rows
    end
    local okN, count = pcall(getNum)
    local n = (okN and type(count) == "number") and math.min(100, math.max(0, math.floor(count))) or 0
    for idx = 1, n do
      local okH, _, _, sender, subject, money, codAmount, _, hasItem = pcall(getHdr, idx)
      if not okH then
        table.insert(rows, { mailIndex = idx, headerLoaded = false })
      else
        local headerLoaded = (sender ~= nil or subject ~= nil)
        local invType, itemName, playerName, bid, buyout, deposit, consignment = nil, nil, nil, nil, nil, nil, nil
        if type(getInv) == "function" then
          local okI, it, iName, py, b, bo, dep, cons = pcall(getInv, idx)
          if okI then
            invType, itemName, playerName, bid, buyout, deposit, consignment = it, iName, py, b, bo, dep, cons
          end
        end
        local isAuctionMail = (invType ~= nil and invType ~= "")
        local invoiceFieldsComplete = true
        if isAuctionMail then
          if invType == "seller" or invType == "seller_temp_invoice" then
            invoiceFieldsComplete = headerLoaded
              and (type(itemName) == "string" and itemName ~= "")
              and isFiniteNonNeg(bid)
              and isFiniteNonNeg(buyout)
              and isFiniteNonNeg(deposit)
              and isFiniteNonNeg(consignment)
              and isFiniteNonNeg(money)
          elseif invType == "buyer" then
            invoiceFieldsComplete = headerLoaded
              and (type(itemName) == "string" and itemName ~= "")
              and isFiniteNonNeg(bid)
              and isFiniteNonNeg(buyout)
          else
            invoiceFieldsComplete = false
          end
        end
        -- Astra `P0-2`: Preserve raw `nil`/missing invoice fields; NEVER coerce `nil` to `0` before completeness verification!
        table.insert(rows, {
          mailIndex = idx,
          headerLoaded = headerLoaded,
          sender = sender,
          subject = subject,
          hasItem = hasItem,
          isAuctionMail = isAuctionMail,
          invoiceLoaded = isAuctionMail,
          fieldsComplete = invoiceFieldsComplete,
          invoiceFieldsComplete = invoiceFieldsComplete,
          invoiceType = invType,
          itemName = itemName,
          counterpartyPresent = (playerName ~= nil and playerName ~= ""),
          rawBid = bid,
          rawBuyout = buyout,
          rawDeposit = deposit,
          rawConsignment = consignment,
          rawMoney = money,
          rawCODAmount = codAmount,
          bid = (invoiceFieldsComplete and isFiniteNonNeg(bid)) and bid or nil,
          buyout = (invoiceFieldsComplete and isFiniteNonNeg(buyout)) and buyout or nil,
          deposit = (invoiceFieldsComplete and isFiniteNonNeg(deposit)) and deposit or nil,
          consignment = (invoiceFieldsComplete and isFiniteNonNeg(consignment)) and consignment or nil,
          money = isFiniteNonNeg(money) and money or nil,
          codAmountCopper = isFiniteNonNeg(codAmount) and codAmount or nil,
        })
      end
    end
    return rows
  end

  local function syncLiveProfessionSnapshot()
    if ns.Compat and type(ns.Compat.CaptureProfessionSnapshot) == "function" and ns.State and type(ns.State.UpdateProfessionSnapshot) == "function" then
      local snap = ns.Compat.CaptureProfessionSnapshot()
      ns.State.UpdateProfessionSnapshot(snap)
    end
  end

  eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3)
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
      syncLiveProfessionSnapshot()
      local instTransPEW = nil
      if ns.Domain and ns.Domain.InstanceLedger and ns.Domain.InstanceLedger.ObserveTransition then
        local okIT, resIT = pcall(ns.Domain.InstanceLedger.ObserveTransition, { trigger = "PLAYER_ENTERING_WORLD" })
        if okIT then
          instTransPEW = resIT
        end
      end
      if ns.Domain and ns.Domain.SunkenTempleCoach then
        if ns.Domain.SunkenTempleCoach.EnsureEventFrame then
          pcall(ns.Domain.SunkenTempleCoach.EnsureEventFrame)
        end
        if ns.Domain.SunkenTempleCoach.ObserveEnvironmentTransition then
          pcall(ns.Domain.SunkenTempleCoach.ObserveEnvironmentTransition, {
            trigger = "PLAYER_ENTERING_WORLD",
            resumedExistingRun = instTransPEW and instTransPEW.resumedExistingRun == true,
            ledgerActiveRunID = instTransPEW and instTransPEW.activeRunID or nil,
          })
        end
      end
      if ns.Providers and ns.Providers.Auctionator then
        if ns.Providers.Auctionator.EnsurePassiveQueryHookInstalled then
          ns.Providers.Auctionator.EnsurePassiveQueryHookInstalled()
        end
        ns.Providers.Auctionator.RegisterDBUpdateCallback(function()
          if ns.UI and ns.UI.Crates then
            ns.UI.Crates.RefreshIfShown()
          end
        end)
      end
      ns.State.BumpInventoryRevision()
      recordInventoryTraceIfEnabled("PLAYER_ENTERING_WORLD")
      if ns.Compat and ns.Compat.InvalidateMapWorldSizeCache then
        ns.Compat.InvalidateMapWorldSizeCache()
      end
      if ns.Domain and ns.Domain.SpawnRadar and ns.Domain.SpawnRadar.BumpWorldSessionEpoch then
        ns.Domain.SpawnRadar.BumpWorldSessionEpoch("PLAYER_ENTERING_WORLD")
      end
      do
        local curPos = ns.Compat and ns.Compat.GetPlayerPosition01 and ns.Compat.GetPlayerPosition01()
        Events._lastObservedPlayerUiMapID = (curPos and curPos.status == "ok") and tonumber(curPos.uiMapID) or nil
      end
      if ns.UI and ns.UI.Navigation and ns.UI.Navigation.InvalidateTargetAnchor then
        ns.UI.Navigation.InvalidateTargetAnchor()
      end
      if ns.UI and ns.UI.WorldMapPins then
        ns.UI.WorldMapPins.EnsureHooksInstalled()
      end
      if ns.Compat and ns.Compat.ScanLiveQuestLog then
        ns.Compat.ScanLiveQuestLog(true)
      end
      if ns.UI and ns.UI.Navigation and ns.UI.Navigation.FlushDeferredIfReady then
        ns.UI.Navigation.FlushDeferredIfReady()
      end
      local gProg = ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress()
      -- Astra P1-9 & Gate 7: Telemetry ALWAYS stays paused after `/reload` until user explicitly runs `/fh gold start`.
      if gProg and gProg.mode ~= "paused" and ns.UI and ns.UI.Navigation then
        local gEval = ns.Domain.GoldFarms.Reconcile(nil, gProg)
        ns.UI.Navigation.SyncFromGoldFarmEvaluation(gEval, gProg)
        if ns.Domain and ns.Domain.SpawnRadar and ns.Domain.SpawnRadar.SyncExistingOwnedTargetMacro then
          ns.Domain.SpawnRadar.SyncExistingOwnedTargetMacro("PLAYER_ENTERING_WORLD")
        end
      end
    elseif event == "PLAYER_LOGOUT" then
      if ns.State and ns.State.CheckpointGoldFarmTelemetry then
        ns.State.CheckpointGoldFarmTelemetry(nil, nil, true)
      end
      if ns.Domain and ns.Domain.MarketAccounting and ns.Domain.MarketAccounting.OnPlayerLogout then
        ns.Domain.MarketAccounting.OnPlayerLogout()
      end
    elseif event == "MODIFIER_STATE_CHANGED" then
      if (arg1 == "LSHIFT" or arg1 == "RSHIFT") and ns.UI and ns.UI.Tooltips and ns.UI.Tooltips.RefreshActiveTooltips then
        ns.UI.Tooltips.RefreshActiveTooltips()
      end
    elseif event == "MAIL_SHOW" then
      ns.State.mailOpen = true
      if ns.State.merchantOpen and ns.Domain and ns.Domain.TransactionJournal and ns.Domain.TransactionJournal.MarkMerchantExternalContamination then
        ns.Domain.TransactionJournal.MarkMerchantExternalContamination("mail_opened_during_merchant")
      end
      local inboxRows = scanLiveMailInboxRows()
      if ns.Domain and ns.Domain.TransactionJournal and ns.Domain.TransactionJournal.CaptureInboxSnapshot then
        local curMoney = (type(GetMoney) == "function") and GetMoney() or nil
        ns.Domain.TransactionJournal.CaptureInboxSnapshot(inboxRows, { moneyCopper = curMoney })
      end
      if ns.Domain and ns.Domain.MarketAccounting and ns.Domain.MarketAccounting.ReconcileInboxInvoiceBatch then
        pcall(ns.Domain.MarketAccounting.ReconcileInboxInvoiceBatch, inboxRows)
      end
      if ns.UI and ns.UI.MailAdvisor and ns.UI.MailAdvisor.OnMailShow then
        ns.UI.MailAdvisor.OnMailShow()
      end
      if ns.State.OnNonFarmMoneyWindowOpened then
        ns.State.OnNonFarmMoneyWindowOpened("mail")
      end
    elseif event == "MAIL_INBOX_UPDATE" then
      if ns.State.mailOpen then
        local inboxRows = scanLiveMailInboxRows()
        if ns.Domain and ns.Domain.TransactionJournal then
          local curMoney = (type(GetMoney) == "function") and GetMoney() or nil
          local prevSession = ns.Domain.TransactionJournal.__mailSession
          if prevSession and prevSession.baselineMoneyCopper and curMoney and curMoney > prevSession.baselineMoneyCopper and ns.Domain.TransactionJournal.ReconcileMailCashCollection then
            ns.Domain.TransactionJournal.ReconcileMailCashCollection(inboxRows, curMoney)
          end
          if ns.Domain.TransactionJournal.CaptureInboxSnapshot then
            ns.Domain.TransactionJournal.CaptureInboxSnapshot(inboxRows, { moneyCopper = curMoney })
          end
        end
        if ns.Domain and ns.Domain.MarketAccounting and ns.Domain.MarketAccounting.ReconcileInboxInvoiceBatch then
          pcall(ns.Domain.MarketAccounting.ReconcileInboxInvoiceBatch, inboxRows)
        end
        if ns.UI and ns.UI.MailAdvisor and ns.UI.MailAdvisor.OnMailUpdated then
          ns.UI.MailAdvisor.OnMailUpdated()
        end
      end
    elseif event == "SEND_MAIL_MONEY_CHANGED" or event == "SEND_MAIL_COD_CHANGED" then
      if ns.State.mailOpen and ns.UI and ns.UI.MailAdvisor and ns.UI.MailAdvisor.OnMailUpdated then
        ns.UI.MailAdvisor.OnMailUpdated()
      end
    elseif event == "MAIL_CLOSED" then
      ns.State.mailOpen = false
      if ns.UI and ns.UI.MailAdvisor and ns.UI.MailAdvisor.OnMailClosed then
        ns.UI.MailAdvisor.OnMailClosed()
      end
      if ns.State.OnNonFarmMoneyWindowClosed then
        ns.State.OnNonFarmMoneyWindowClosed("mail")
      end
    elseif event == "AUCTION_HOUSE_SHOW" then
      ns.State.ahOpen = true
      if ns.State.merchantOpen and ns.Domain and ns.Domain.TransactionJournal and ns.Domain.TransactionJournal.MarkMerchantExternalContamination then
        ns.Domain.TransactionJournal.MarkMerchantExternalContamination("auction_house_opened_during_merchant")
      end
      if ns.Providers and ns.Providers.Auctionator and ns.Providers.Auctionator.OnAuctionHouseShow then
        ns.Providers.Auctionator.OnAuctionHouseShow()
      end
      if ns.UI and ns.UI.AuctionPostAdvisor and ns.UI.AuctionPostAdvisor.OnAuctionHouseShow then
        ns.UI.AuctionPostAdvisor.OnAuctionHouseShow()
      end
      if ns.State.OnNonFarmMoneyWindowOpened then
        ns.State.OnNonFarmMoneyWindowOpened("auction_house")
      end
    elseif event == "AUCTION_ITEM_LIST_UPDATE" then
      if ns.State.ahOpen and ns.Providers and ns.Providers.Auctionator and ns.Providers.Auctionator.CapturePassiveLegacyAuctionPage then
        ns.Providers.Auctionator.CapturePassiveLegacyAuctionPage()
        Events.ScheduleCoalescedDeckRefresh()
      end
    elseif event == "NEW_AUCTION_UPDATE" or event == "AUCTION_MULTISELL_UPDATE" then
      if ns.State.ahOpen and ns.UI and ns.UI.AuctionPostAdvisor and ns.UI.AuctionPostAdvisor.OnAuctionSellSelectionChanged then
        ns.UI.AuctionPostAdvisor.OnAuctionSellSelectionChanged()
      end
    elseif event == "AUCTION_HOUSE_CLOSED" then
      ns.State.ahOpen = false
      if ns.UI and ns.UI.AuctionPostAdvisor and ns.UI.AuctionPostAdvisor.OnAuctionHouseClosed then
        ns.UI.AuctionPostAdvisor.OnAuctionHouseClosed()
      end
      if ns.Providers and ns.Providers.Auctionator and ns.Providers.Auctionator.OnAuctionHouseClosed then
        ns.Providers.Auctionator.OnAuctionHouseClosed()
      end
      if ns.State.OnNonFarmMoneyWindowClosed then
        ns.State.OnNonFarmMoneyWindowClosed("auction_house")
      end
    elseif event == "MERCHANT_SHOW" then
      ns.State.merchantOpen = true
      if ns.Domain and ns.Domain.TransactionJournal and ns.Domain.TransactionJournal.BeginMerchantSession then
        local curMoney = (type(GetMoney) == "function") and GetMoney() or nil
        local bagSlots = (ns.Compat and ns.Compat.SnapshotDetailedPlayerBagSlots and ns.Compat.SnapshotDetailedPlayerBagSlots()) or {}
        ns.Domain.TransactionJournal.BeginMerchantSession({
          moneyCopper = curMoney,
          bagSlots = bagSlots,
        })
      end
      if ns.UI and ns.UI.MerchantAdvisor and ns.UI.MerchantAdvisor.OnMerchantShow then
        ns.UI.MerchantAdvisor.OnMerchantShow()
      end
    elseif event == "MERCHANT_CLOSED" then
      ns.State.merchantOpen = false
      if ns.UI and ns.UI.MerchantAdvisor and ns.UI.MerchantAdvisor.OnMerchantClosed then
        ns.UI.MerchantAdvisor.OnMerchantClosed()
      end
      if ns.Domain and ns.Domain.TransactionJournal and ns.Domain.TransactionJournal.FinalizeMerchantSession then
        local endMoney = (type(GetMoney) == "function") and GetMoney() or nil
        local endSlots = (ns.Compat and ns.Compat.SnapshotDetailedPlayerBagSlots and ns.Compat.SnapshotDetailedPlayerBagSlots()) or {}
        ns.Domain.TransactionJournal.FinalizeMerchantSession({
          moneyCopper = endMoney,
          bagSlots = endSlots,
        })
        Events.ScheduleCoalescedDeckRefresh()
      end
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
      if ns.State.merchantOpen and ns.Domain and ns.Domain.TransactionJournal and ns.Domain.TransactionJournal.MarkMerchantExternalContamination then
        ns.Domain.TransactionJournal.MarkMerchantExternalContamination("trade_opened_during_merchant")
      end
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
      if ns.UI and ns.UI.TrainerAdvisor and ns.UI.TrainerAdvisor.OnTrainerShow then
        ns.UI.TrainerAdvisor.OnTrainerShow()
      end
      if ns.State.OnNonFarmMoneyWindowOpened then
        ns.State.OnNonFarmMoneyWindowOpened("trainer")
      end
    elseif event == "TRAINER_CLOSED" then
      ns.State.trainerOpen = false
      if ns.UI and ns.UI.TrainerAdvisor and ns.UI.TrainerAdvisor.OnTrainerClosed then
        ns.UI.TrainerAdvisor.OnTrainerClosed()
      end
      if ns.State.OnNonFarmMoneyWindowClosed then
        ns.State.OnNonFarmMoneyWindowClosed("trainer")
      end
    elseif event == "SKILL_LINES_CHANGED" then
      syncLiveProfessionSnapshot()
      Events.ScheduleCoalescedDeckRefresh()
    elseif event == "TRADE_SKILL_SHOW" or event == "CRAFT_SHOW" then
      syncLiveProfessionSnapshot()
      if ns.UI and ns.UI.TradeSkillAdvisor and ns.UI.TradeSkillAdvisor.OnTradeSkillShow then
        ns.UI.TradeSkillAdvisor.OnTradeSkillShow(event == "CRAFT_SHOW" and "craft" or "tradeskill")
      end
    elseif event == "TRADE_SKILL_UPDATE" or event == "CRAFT_UPDATE" then
      if ns.UI and ns.UI.TradeSkillAdvisor and ns.UI.TradeSkillAdvisor.OnTradeSkillUpdate then
        ns.UI.TradeSkillAdvisor.OnTradeSkillUpdate(event == "CRAFT_UPDATE" and "craft" or "tradeskill")
      end
    elseif event == "TRADE_SKILL_CLOSE" or event == "CRAFT_CLOSE" then
      if ns.UI and ns.UI.TradeSkillAdvisor and ns.UI.TradeSkillAdvisor.OnTradeSkillClosed then
        ns.UI.TradeSkillAdvisor.OnTradeSkillClosed()
      end
    elseif event == "BAG_UPDATE_COOLDOWN" then
      if ns.Compat and ns.Compat.NormalizeItemCooldownToServerEpoch and ns.State and ns.State.RecordObservedCooldown then
        local getItemCD = (C_Container and type(C_Container.GetContainerItemCooldown) == "function" and C_Container.GetContainerItemCooldown)
          or _G.GetContainerItemCooldown
        if type(getItemCD) == "function" then
          for bagID = 0, 4 do
            local numSlots = ns.Compat.GetContainerNumSlots(bagID)
            for slotID = 1, numSlots do
              local info = ns.Compat.GetContainerItemInfo(bagID, slotID)
              if info and info.hasItem and tonumber(info.itemID) == 15846 then
                local okCD, startT, dur, en = pcall(getItemCD, bagID, slotID)
                if okCD then
                  local norm = ns.Compat.NormalizeItemCooldownToServerEpoch(startT, dur, en)
                  if norm and (norm.status == "READY_OBSERVED" or norm.status == "ON_COOLDOWN_OBSERVED") then
                    ns.State.RecordObservedCooldown("lw_salt_shaker", norm)
                  end
                end
              end
            end
          end
        end
      end
    elseif event == "GOSSIP_SHOW" then
      ns.State.gossipOpen = true
    elseif event == "GOSSIP_CLOSED" then
      ns.State.gossipOpen = false
    elseif event == "PLAYER_REGEN_DISABLED" then
      if ns.Providers and ns.Providers.Inventory and ns.Providers.Inventory.CancelBankCollection then
        ns.Providers.Inventory.CancelBankCollection("combat", "Bank collection stopped because you entered combat.")
      end
      if ns.Domain and ns.Domain.InstanceLedger and ns.Domain.InstanceLedger.RecordOutsideCombatActivity then
        pcall(ns.Domain.InstanceLedger.RecordOutsideCombatActivity)
      end
      if ns.Domain and ns.Domain.SunkenTempleCoach and ns.Domain.SunkenTempleCoach.OnCombatStart then
        pcall(ns.Domain.SunkenTempleCoach.OnCombatStart)
      end
      Events.OnGoldFarmTargetOrCombatPull()
    elseif event == "PLAYER_TARGET_CHANGED" then
      if ns.Domain and ns.Domain.SunkenTempleCoach and ns.Domain.SunkenTempleCoach.OnTargetChangedSample then
        pcall(ns.Domain.SunkenTempleCoach.OnTargetChangedSample)
      end
      Events.OnGoldFarmTargetOrCombatPull()
    elseif event == "PLAYER_REGEN_ENABLED" then
      if ns.Domain and ns.Domain.SunkenTempleCoach and ns.Domain.SunkenTempleCoach.OnCombatEnd then
        pcall(ns.Domain.SunkenTempleCoach.OnCombatEnd)
      end
      if ns.UI and ns.UI.Navigation and ns.UI.Navigation.FlushDeferredIfReady then
        ns.UI.Navigation.FlushDeferredIfReady()
      end
      if ns.Domain and ns.Domain.SpawnRadar and ns.Domain.SpawnRadar.FlushPendingMacroSync then
        local mRes = ns.Domain.SpawnRadar.FlushPendingMacroSync()
        if mRes ~= nil and ns.UI and ns.UI.GoldFarms and ns.UI.GoldFarms.RefreshIfShown then
          ns.UI.GoldFarms.RefreshIfShown()
        end
      end
      for _, advName in ipairs({ "MerchantAdvisor", "TrainerAdvisor", "TradeSkillAdvisor", "AuctionPostAdvisor", "MailAdvisor" }) do
        local adv = ns.UI and ns.UI[advName]
        if adv and type(adv.FlushDeferredIfReady) == "function" then
          pcall(adv.FlushDeferredIfReady)
        end
      end
    elseif event == "UPDATE_MACROS" then
      -- Read-only macro ownership/status inspection on external /macro edits (never calls EditMacro/CreateMacro -> zero loop risk)
      local SR = ns.Domain and ns.Domain.SpawnRadar
      if SR and not (SR.macroSyncState and SR.macroSyncState.inMutationGuard == true) and type(SR.InspectMacroSyncStatus) == "function" then
        SR.InspectMacroSyncStatus()
        if ns.UI and ns.UI.GoldFarms and ns.UI.GoldFarms.RefreshIfShown then
          ns.UI.GoldFarms.RefreshIfShown()
        end
      end
    elseif event == "ZONE_CHANGED_NEW_AREA" then
      local instTransZC = nil
      if ns.Domain and ns.Domain.InstanceLedger and ns.Domain.InstanceLedger.ObserveTransition then
        local okZC, resZC = pcall(ns.Domain.InstanceLedger.ObserveTransition, { trigger = "ZONE_CHANGED_NEW_AREA" })
        if okZC then
          instTransZC = resZC
        end
      end
      if ns.Domain and ns.Domain.SunkenTempleCoach and ns.Domain.SunkenTempleCoach.ObserveEnvironmentTransition then
        pcall(ns.Domain.SunkenTempleCoach.ObserveEnvironmentTransition, {
          trigger = "ZONE_CHANGED_NEW_AREA",
          resumedExistingRun = instTransZC and instTransZC.resumedExistingRun == true,
          ledgerActiveRunID = instTransZC and instTransZC.activeRunID or nil,
        })
      end
      if ns.Compat and ns.Compat.InvalidateMapWorldSizeCache then
        ns.Compat.InvalidateMapWorldSizeCache()
      end
      do
        local curPos = ns.Compat and ns.Compat.GetPlayerPosition01 and ns.Compat.GetPlayerPosition01()
        local curMapID = (curPos and curPos.status == "ok") and tonumber(curPos.uiMapID) or nil
        if curMapID ~= Events._lastObservedPlayerUiMapID then
          Events._lastObservedPlayerUiMapID = curMapID
          if ns.Domain and ns.Domain.SpawnRadar and ns.Domain.SpawnRadar.BumpWorldSessionEpoch then
            ns.Domain.SpawnRadar.BumpWorldSessionEpoch("ZONE_CHANGED_NEW_AREA")
          end
        end
      end
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
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
      if ns.Domain and ns.Domain.SunkenTempleCoach and ns.Domain.SunkenTempleCoach.OnUnitSpellcastSucceeded then
        pcall(ns.Domain.SunkenTempleCoach.OnUnitSpellcastSucceeded, arg1, arg2, arg3)
      end
    elseif event == "CHAT_MSG_MONSTER_YELL" then
      if ns.Domain and ns.Domain.SunkenTempleCoach and ns.Domain.SunkenTempleCoach.OnMonsterChatEvent then
        pcall(ns.Domain.SunkenTempleCoach.OnMonsterChatEvent, "YELL", arg1, arg2)
      end
    elseif event == "CHAT_MSG_MONSTER_EMOTE" then
      if ns.Domain and ns.Domain.SunkenTempleCoach and ns.Domain.SunkenTempleCoach.OnMonsterChatEvent then
        pcall(ns.Domain.SunkenTempleCoach.OnMonsterChatEvent, "EMOTE", arg1, arg2)
      end
    elseif event == "PLAYER_DEAD" then
      if ns.Domain and ns.Domain.SunkenTempleCoach and ns.Domain.SunkenTempleCoach.OnPlayerDead then
        pcall(ns.Domain.SunkenTempleCoach.OnPlayerDead)
      end
    elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
      if ns.Domain and ns.Domain.SunkenTempleCoach and ns.Domain.SunkenTempleCoach.ObserveEnvironmentTransition then
        pcall(ns.Domain.SunkenTempleCoach.ObserveEnvironmentTransition, { trigger = event })
      end
    elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
      if ns.Domain and ns.Domain.SunkenTempleCoach and ns.Domain.SunkenTempleCoach.AnnotateSubZoneSample then
        pcall(ns.Domain.SunkenTempleCoach.AnnotateSubZoneSample)
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
      if ns.UI and ns.UI.Tooltips and ns.UI.Tooltips.BumpVendorMetadataRevision then
        ns.UI.Tooltips.BumpVendorMetadataRevision()
      end
      if ns.UI and ns.UI.MerchantAdvisor and ns.UI.MerchantAdvisor.RefreshIfActive then
        ns.UI.MerchantAdvisor.RefreshIfActive()
      end
      if ns.UI and ns.UI.RewardAdvisor then
        ns.UI.RewardAdvisor.OnItemInfoReceived(arg1, arg2)
      end
      if ns.UI and ns.UI.Crates and ns.UI.Crates.OnItemInfoReceived then
        ns.UI.Crates.OnItemInfoReceived(arg1, arg2)
      end
      if ns.UI and ns.UI.AuctionPostAdvisor and ns.UI.AuctionPostAdvisor.active and ns.UI.AuctionPostAdvisor.OnAuctionSellSelectionChanged then
        ns.UI.AuctionPostAdvisor.OnAuctionSellSelectionChanged()
      end
      Events.ScheduleCoalescedDeckRefresh()
    elseif event == "PLAYER_MONEY" then
      ns.State.CaptureSessionMoneyBaselineIfUnset()
      if ns.UI and ns.UI.GoldFarms and ns.UI.GoldFarms.RefreshIfShown then
        ns.UI.GoldFarms.RefreshIfShown()
      end
      if ns.UI and ns.UI.Workspace and ns.UI.Workspace.RefreshIfShown then
        ns.UI.Workspace.RefreshIfShown()
      end
    elseif event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" or event == "UPDATE_EXHAUSTION" then
      if ns.State and ns.State.ReconcileGoldFarmXPSnapshot then
        local newLvl = nil
        if event == "PLAYER_LEVEL_UP" and not (ns.Compat and ns.Compat.IsSecretOrRestrictedValue and ns.Compat.IsSecretOrRestrictedValue(arg1)) then
          newLvl = tonumber(arg1)
        end
        ns.State.ReconcileGoldFarmXPSnapshot({
          trigger = event,
          newLevel = newLvl,
        })
      end
      if ns.UI and ns.UI.GoldFarms and ns.UI.GoldFarms.RefreshIfShown then
        ns.UI.GoldFarms.RefreshIfShown()
      end
      if ns.UI and ns.UI.Workspace and ns.UI.Workspace.RefreshIfShown then
        ns.UI.Workspace.RefreshIfShown()
      end
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
      Events.OnGoldFarmCombatOrLootEvent(event, arg1)
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
      if ns.Compat and ns.Compat.InvalidateQuestStateCaches then
        ns.Compat.InvalidateQuestStateCaches()
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
      if ns.State and ns.State.RecordGoldFarmQuestTurnInXP then
        local xpRew = nil
        if not (ns.Compat and ns.Compat.IsSecretOrRestrictedValue and ns.Compat.IsSecretOrRestrictedValue(arg2)) then
          xpRew = tonumber(arg2)
        end
        ns.State.RecordGoldFarmQuestTurnInXP(qID, xpRew)
      end
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
      if ns.UI and ns.UI.GoldFarms and ns.UI.GoldFarms.RefreshIfShown then
        ns.UI.GoldFarms.RefreshIfShown()
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
    end

    local RRC = ns.Domain and ns.Domain.RaidReadinessCoach
    if RRC and type(RRC.RequestCoalescedRefresh) == "function" then
      local isWorldTrans = (event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA")
      local isRrcEvent = isWorldTrans
        or event == "ZONE_CHANGED"
        or event == "ZONE_CHANGED_INDOORS"
        or event == "MINIMAP_ZONE_CHANGED"
        or event == "QUEST_LOG_UPDATE"
        or event == "QUEST_ACCEPTED"
        or event == "QUEST_TURNED_IN"
        or event == "QUEST_REMOVED"
        or event == "QUEST_WATCH_UPDATE"
        or event == "UNIT_QUEST_LOG_CHANGED"
        or event == "BAG_UPDATE_DELAYED"
        or event == "BANKFRAME_OPENED"
        or event == "BANKFRAME_CLOSED"
        or event == "PLAYERBANKSLOTS_CHANGED"
        or event == "BANK_TABS_CHANGED"
        or event == "PLAYER_EQUIPMENT_CHANGED"
        or event == "GET_ITEM_INFO_RECEIVED"
        or event == "SKILL_LINES_CHANGED"
        or event == "TRADE_SKILL_UPDATE"
        or event == "CRAFT_UPDATE"
        or event == "PLAYER_DEAD"
        or event == "PLAYER_ALIVE"
        or event == "PLAYER_UNGHOST"
        or event == "PLAYER_REGEN_ENABLED"
      if isRrcEvent then
        pcall(RRC.RequestCoalescedRefresh, isWorldTrans)
      end
    end
  end)
end

SLASH_FOREVERHUB1 = "/foreverhub"
SLASH_FOREVERHUB2 = "/fh"
SlashCmdList = SlashCmdList or {}
SlashCmdList["FOREVERHUB"] = handleSlashCommand
