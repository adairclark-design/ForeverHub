local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.UI = ns.UI or {}

local Theme = ns.UI.Theme
local Widgets = ns.UI.Widgets
local Presenter = ns.UI.GoldFarmsPresenter

local GoldFarmsUI = {
  frame = nil,
  host = nil,
  summaryStrip = nil,
  kpis = {},
  trackBar = nil,
  mountBar = nil,
  subFilterBar = nil,
  activeRouteBanner = nil,
  viewport = nil,
  cardPool = {},
  badgePool = {},
  lastLayoutReport = nil,
}
ns.UI.GoldFarms = GoldFarmsUI

local FARM_COLLAPSED_MIN_HEIGHT = 82

local CARD_BUTTON_KEYS = {
  "primaryNavBtn",
  "selectBtn",
  "nextHopBtn",
  "stopNavBtn",
  "expandBtn",
  "prevHopBtn",
  "reenterBtn",
  "exportBtn",
}

local SUBFILTER_OPTIONS = {
  { key = "my_level", label = "My Level", width = 68, tip = "Eligible Subcamps at Your Level (Ideal & +1/+2 Preview)" },
  { key = "all_shortlist", label = "All (19)", width = 62, tip = "Unverified Candidate Shortlist — all 19 Lv 46–60 source-verified routes" },
  { key = "46_50", label = "46–50", width = 50, tip = "Lv 46–50 Subcamp Candidates" },
  { key = "48_51", label = "48–51", width = 50, tip = "Lv 48–51 Subcamp Candidates" },
  { key = "51_54", label = "51–54", width = 50, tip = "Lv 51–54 Subcamp Candidates" },
  { key = "54_57", label = "54–57", width = 50, tip = "Lv 54–57 Subcamp Candidates" },
  { key = "57_60", label = "57–60", width = 50, tip = "Lv 57–60 Subcamp Candidates" },
  { key = "experimental", label = "+Experimental", width = 94, tip = "Opt-In Experimental / Conditional Candidates (excluded from auto My Level)" },
}

local function clearCardCallbacks(card)
  if type(card) ~= "table" then
    return
  end
  for _, k in ipairs(CARD_BUTTON_KEYS) do
    local btn = card[k]
    if btn and type(btn.SetOnClick) == "function" then
      btn:SetOnClick(nil)
    end
  end
end

local function acquirePoolItem(pool, createFn)
  local idx = (pool.__used or 0) + 1
  pool.__used = idx
  local item = pool[idx]
  if not item then
    item = createFn(idx)
    pool[idx] = item
  end
  return item
end

local function resetPool(pool, mode)
  for i = 1, #pool do
    local item = pool[i]
    if item then
      if mode == "cards" then
        clearCardCallbacks(item)
        Widgets.SafeShow(item, false)
      elseif mode == "badges" and Widgets.ResetPooledWidget then
        Widgets.ResetPooledWidget(item)
      else
        Widgets.SafeShow(item, false)
      end
    end
  end
  pool.__used = 0
end

function GoldFarmsUI.Dispatch(actionType, payload)
  payload = type(payload) == "table" and payload or {}
  local uiState = ns.State.GetWorkspaceUIState()
  local goldView = uiState.goldView

  if actionType == "SELECT_FARM" then
    local fid = tostring(payload.farmID or "")
    if fid ~= "" then
      goldView.focusedFarmID = fid
      if ns.UI.WorldMapPins and ns.UI.WorldMapPins.Refresh then
        pcall(ns.UI.WorldMapPins.Refresh)
      end
      GoldFarmsUI.Refresh()
    end
    return true
  elseif actionType == "SET_SUBVIEW" then
    goldView.subView = (payload.subView == "dungeons") and "dungeons" or "routes"
    goldView.scrollOffset = 0
    GoldFarmsUI.Refresh()
    return true
  elseif actionType == "SET_SUBFILTER" then
    local sf = tostring(payload.subFilter or "my_level")
    local valid = {
      my_level = true,
      all_shortlist = true,
      ["46_50"] = true,
      ["48_51"] = true,
      ["51_54"] = true,
      ["54_57"] = true,
      ["57_60"] = true,
      experimental = true,
    }
    if valid[sf] then
      -- Visibility-only filter change: NEVER stops or mutates active navigation or session meters (Astra P2-1)!
      goldView.subFilter = sf
      goldView.scrollOffset = 0
      local catalog = ns.State.GetCompiledGoldFarms and ns.State.GetCompiledGoldFarms()
      local gProg = ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress()
      local filterRes = (ns.Domain.GoldFarms and ns.Domain.GoldFarms.FilterArcaneFarms)
        and ns.Domain.GoldFarms.FilterArcaneFarms(catalog, sf, nil, gProg)
        or nil
      if type(payload.focusFarmID) == "string" and payload.focusFarmID ~= "" then
        goldView.focusedFarmID = payload.focusFarmID
      elseif filterRes and filterRes.farms and filterRes.farms[1] then
        local found = false
        for _, f in ipairs(filterRes.farms) do
          if f.farmID == goldView.focusedFarmID then
            found = true
            break
          end
        end
        if not found then
          goldView.focusedFarmID = filterRes.farms[1].farmID
        end
      end
      if ns.UI.WorldMapPins and ns.UI.WorldMapPins.Refresh then
        pcall(ns.UI.WorldMapPins.Refresh)
      end
      GoldFarmsUI.Refresh()
      return true
    end
    return false
  elseif actionType == "SET_TRACK" then
    local trk = tostring(payload.track or "")
    if trk == "arcane_lvl47_st" or trk == "lvl40_mount" or trk == "auto" then
      goldView.selectedTrack = trk
      goldView.scrollOffset = 0
      local catalog = ns.State.GetCompiledGoldFarms and ns.State.GetCompiledGoldFarms()
      local eff = ns.Domain.GoldFarms and ns.Domain.GoldFarms.GetEffectiveTrack and ns.Domain.GoldFarms.GetEffectiveTrack(uiState) or trk
      local list
      if eff == "arcane_lvl47_st" and ns.Domain.GoldFarms and ns.Domain.GoldFarms.FilterArcaneFarms then
        local gProg = ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress()
        local fRes = ns.Domain.GoldFarms.FilterArcaneFarms(catalog, goldView.subFilter, nil, gProg)
        list = (fRes and fRes.farms) or {}
      else
        list = ns.Domain.GoldFarms and ns.Domain.GoldFarms.GetFarmsForTrack and ns.Domain.GoldFarms.GetFarmsForTrack(eff, catalog) or {}
      end
      if list[1] then
        goldView.focusedFarmID = list[1].farmID
      end
      if ns.UI.WorldMapPins and ns.UI.WorldMapPins.Refresh then
        pcall(ns.UI.WorldMapPins.Refresh)
      end
      GoldFarmsUI.Refresh()
      return true
    end
    return false
  elseif actionType == "CYCLE_RADAR_MODE" then
    local gProg = ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress()
    if gProg then
      local cur = gProg.spawnRadarMode or "auto"
      local nxt = (cur == "auto" and "on") or (cur == "on" and "off") or "auto"
      gProg.spawnRadarMode = nxt
      if gProg.mode ~= "paused" and ns.UI.Navigation and ns.UI.Navigation.SyncFromGoldFarmEvaluation then
        ns.UI.Navigation.SyncFromGoldFarmEvaluation(nil, gProg)
      elseif ns.UI.Navigation and ns.UI.Navigation.TickSpawnRadar then
        ns.UI.Navigation.TickSpawnRadar(0, true)
      end
      if ns.UI.WorldMapPins and ns.UI.WorldMapPins.RequestRefresh then
        ns.UI.WorldMapPins.RequestRefresh()
      end
      GoldFarmsUI.Refresh()
      return true
    end
    return false
  elseif actionType == "CYCLE_SPAWN_PIN_MODE" then
    local gProg = ns.State.GetGoldFarmProgress and ns.State.GetGoldFarmProgress()
    if gProg then
      local cur = gProg.spawnPinMode or "active"
      local nxt = (cur == "active" and "all") or (cur == "all" and "off") or "active"
      gProg.spawnPinMode = nxt
      if ns.UI.WorldMapPins and ns.UI.WorldMapPins.RequestRefresh then
        ns.UI.WorldMapPins.RequestRefresh()
      end
      GoldFarmsUI.Refresh()
      return true
    end
    return false
  elseif actionType == "SKIP_SPAWN" then
    if ns.Events and ns.Events.HandleGoldSubcommand then
      ns.Events.HandleGoldSubcommand("skip")
    end
    GoldFarmsUI.Refresh()
    return true
  elseif actionType == "CREATE_TARGET_MACRO" then
    if ns.Events and ns.Events.HandleGoldSubcommand then
      ns.Events.HandleGoldSubcommand("macro " .. tostring(payload.farmID or goldView.focusedFarmID or ""))
    end
    GoldFarmsUI.Refresh()
    return true
  elseif actionType == "TOGGLE_EXPAND" then
    local fid = tostring(payload.farmID or "")
    if fid ~= "" then
      goldView.focusedFarmID = fid
      goldView.expandedByFarmID[fid] = not (goldView.expandedByFarmID[fid] == true)
      if ns.UI.WorldMapPins and ns.UI.WorldMapPins.Refresh then
        pcall(ns.UI.WorldMapPins.Refresh)
      end
      GoldFarmsUI.Refresh()
    end
    return true
  elseif actionType == "START_NAVIGATION" then
    local fid = tostring(payload.farmID or "")
    if fid ~= "" then
      goldView.focusedFarmID = fid
      if ns.Events and ns.Events.HandleGoldSubcommand then
        ns.Events.HandleGoldSubcommand("start " .. fid)
      end
      GoldFarmsUI.Refresh()
      return true
    end
    return false
  elseif actionType == "STOP_NAVIGATION" then
    if ns.Events and ns.Events.HandleGoldSubcommand then
      ns.Events.HandleGoldSubcommand("stop")
    end
    GoldFarmsUI.Refresh()
    return true
  elseif actionType == "NEXT_HOP" then
    if ns.Events and ns.Events.HandleGoldSubcommand then
      ns.Events.HandleGoldSubcommand("next")
    end
    GoldFarmsUI.Refresh()
    return true
  elseif actionType == "PREV_HOP" then
    if ns.Events and ns.Events.HandleGoldSubcommand then
      ns.Events.HandleGoldSubcommand("prev")
    end
    GoldFarmsUI.Refresh()
    return true
  elseif actionType == "REENTER_ROUTE" then
    if ns.Events and ns.Events.HandleGoldSubcommand then
      ns.Events.HandleGoldSubcommand("reenter")
    end
    GoldFarmsUI.Refresh()
    return true
  elseif actionType == "RESET_METER" then
    if ns.Events and ns.Events.HandleGoldSubcommand then
      ns.Events.HandleGoldSubcommand("reset")
    end
    GoldFarmsUI.Refresh()
    return true
  elseif actionType == "EXPORT_RXP" then
    local fid = payload.farmID
    if ns.Events and ns.Events.HandleGoldSubcommand then
      if fid and fid ~= "" then
        ns.Events.HandleGoldSubcommand("export rxp " .. tostring(fid))
      else
        local eff = ns.Domain.GoldFarms and ns.Domain.GoldFarms.GetEffectiveTrack and ns.Domain.GoldFarms.GetEffectiveTrack(uiState) or "lvl40_mount"
        if eff == "arcane_lvl47_st" then
          ns.Events.HandleGoldSubcommand("export rxp arcane")
        else
          ns.Events.HandleGoldSubcommand("export rxp")
        end
      end
    end
    GoldFarmsUI.Refresh()
    return true
  elseif actionType == "SET_QUOTE_HONORED" then
    if ns.Events and ns.Events.HandleMountCommand then
      ns.Events.HandleMountCommand("honored")
    end
    GoldFarmsUI.Refresh()
    return true
  elseif actionType == "SET_QUOTE_BASE" then
    if ns.Events and ns.Events.HandleMountCommand then
      ns.Events.HandleMountCommand("base")
    end
    GoldFarmsUI.Refresh()
    return true
  elseif actionType == "SET_RESERVE_GOLD" then
    local g = math.max(0, math.floor(tonumber(payload.gold) or 0))
    if ns.Events and ns.Events.HandleMountCommand then
      ns.Events.HandleMountCommand("reserve " .. tostring(g))
    end
    GoldFarmsUI.Refresh()
    return true
  end
  return false
end

local function createFarmCard(parent)
  local card = Widgets.CreatePanel(parent, "surface.card", "border.subtle")
  if not card then
    return nil
  end

  card.icon = Widgets.CreateItemIcon(card, 32)
  if card.icon then
    Widgets.SafeSetPoint(card.icon, "TOPLEFT", card, "TOPLEFT", 12, -14)
  end

  card.titleText = Widgets.SafeCreateFontString(card, "sectionTitle", "text.primary")
  if card.titleText and type(card.titleText.SetJustifyH) == "function" then
    pcall(card.titleText.SetJustifyH, card.titleText, "LEFT")
  end

  card.meta1Text = Widgets.SafeCreateFontString(card, "body", "text.secondary")
  if card.meta1Text and type(card.meta1Text.SetJustifyH) == "function" then
    pcall(card.meta1Text.SetJustifyH, card.meta1Text, "LEFT")
  end

  card.meta2Text = Widgets.SafeCreateFontString(card, "dense", "text.muted")
  if card.meta2Text and type(card.meta2Text.SetJustifyH) == "function" then
    pcall(card.meta2Text.SetJustifyH, card.meta2Text, "LEFT")
  end

  -- Mutually exclusive primary gold `Navigate` vs neutral secondary `Select`
  card.primaryNavBtn = Widgets.CreatePrimaryButton(card, 96, "Navigate", 28)
  card.selectBtn = Widgets.CreateSecondaryButton(card, 82, "Select", 28)
  card.nextHopBtn = Widgets.CreateSecondaryButton(card, 86, "Next hop", 28)
  card.stopNavBtn = Widgets.CreateGhostButton(card, 112, "Stop navigation", 28)
  card.expandBtn = Widgets.CreateIconButton(card, "chevron_right", "Route & Mage details", { "Show travel hops, Mage pull notes, and RXP export." }, 28, 14)

  card.detailBox = Widgets.CreatePanel(card, "surface.elevated", "border.subtle")
  if card.detailBox then
    card.detailText = Widgets.SafeCreateFontString(card.detailBox, "dense", "text.secondary")
    if card.detailText and type(card.detailText.SetJustifyH) == "function" then
      pcall(card.detailText.SetJustifyH, card.detailText, "LEFT")
    end
    card.prevHopBtn = Widgets.CreateGhostButton(card.detailBox, 78, "Prev hop", 24)
    card.reenterBtn = Widgets.CreateGhostButton(card.detailBox, 108, "Re-route entry", 24)
    card.exportBtn = Widgets.CreateSecondaryButton(card.detailBox, 116, "Export to RXP", 24)
  end

  return card
end

function GoldFarmsUI.EnsureHost()
  local wsFrame = ns.UI.Workspace and ns.UI.Workspace.EnsureCreated and ns.UI.Workspace.EnsureCreated() or nil
  local tabParent = (wsFrame and wsFrame.tabHosts and wsFrame.tabHosts.gold) or _G.UIParent
  if GoldFarmsUI.host and GoldFarmsUI.host.__parentRef == tabParent then
    return GoldFarmsUI.host
  end

  local host = Widgets.CreatePanel(tabParent, "surface.window", nil)
  if not host then
    return nil
  end
  host.__parentRef = tabParent
  GoldFarmsUI.host = host
  GoldFarmsUI.frame = tabParent
  _G.ForeverHubGoldFarmsFrame = tabParent

  if ns.UI.Workspace and ns.UI.Workspace.RegisterTabRenderer then
    ns.UI.Workspace.RegisterTabRenderer("gold", {
      Refresh = function(_, contentWidth, contentHeight, isCompact)
        GoldFarmsUI.RenderInHost(contentWidth, contentHeight, isCompact)
      end,
    })
  end

  -- 1. Top 5-KPI Summary Strip (60h)
  local summary = Widgets.CreatePanel(host, "surface.card", "border.subtle")
  GoldFarmsUI.summaryStrip = summary
  GoldFarmsUI.kpis = {}
  for i = 1, 5 do
    GoldFarmsUI.kpis[i] = Widgets.CreateKPI(summary, 160)
  end

  -- 1b. Track Switcher & Spawn Radar Strip (32h)
  local tbar = Widgets.CreatePanel(host, "surface.card", "border.subtle")
  GoldFarmsUI.trackBar = tbar
  if tbar then
    tbar.trackLabel = Widgets.SafeCreateFontString(tbar, "dense", "text.muted")
    if tbar.trackLabel then
      tbar.trackLabel:SetText("Track:")
      Widgets.SafeSetPoint(tbar.trackLabel, "LEFT", tbar, "LEFT", 12, 0)
    end

    tbar.trackArcaneBtn = Widgets.CreateGhostButton(tbar, 140, "Lv 46–60 Arcane ST", 22)
    if tbar.trackArcaneBtn then
      tbar.trackArcaneBtn:SetOnClick(function()
        GoldFarmsUI.Dispatch("SET_SUBVIEW", { subView = "routes" })
        GoldFarmsUI.Dispatch("SET_TRACK", { track = "arcane_lvl47_st" })
      end)
      Widgets.BindTooltip(
        tbar.trackArcaneBtn,
        "Level 46–60 Arcane Single-Target Grind Track",
        {
          "19 source-verified XP + Purse subcamp routes (plus 7 opt-in experimental candidates) for Arcane Single-Target Mage in WoW: Forever.",
          "Subcamp-level filtering, QuestieDB Candidate-Spawn Radar arrow, scope-aware FH_Target sync & reconciled grind XP/hr.",
        }
      )
    end

    tbar.trackMountBtn = Widgets.CreateGhostButton(tbar, 114, "Lv 39–42 Mount", 22)
    if tbar.trackMountBtn then
      tbar.trackMountBtn:SetOnClick(function()
        GoldFarmsUI.Dispatch("SET_SUBVIEW", { subView = "routes" })
        GoldFarmsUI.Dispatch("SET_TRACK", { track = "lvl40_mount" })
      end)
      Widgets.BindTooltip(
        tbar.trackMountBtn,
        "Level 39–42 Mount Funding Track",
        { "5 Alliance Apprentice Riding + Mount cash-flow candidates." }
      )
    end

    tbar.subRoutesBtn = Widgets.CreateGhostButton(tbar, 58, "Routes", 22)
    if tbar.subRoutesBtn then
      tbar.subRoutesBtn:SetOnClick(function()
        GoldFarmsUI.Dispatch("SET_SUBVIEW", { subView = "routes" })
      end)
      Widgets.BindTooltip(
        tbar.subRoutesBtn,
        "Open-World Gold Routes",
        { "Verified open-world gold farm routes & QuestieDB Spawn Radar." }
      )
    end

    tbar.subDungeonsBtn = Widgets.CreateGhostButton(tbar, 72, "Dungeons", 22)
    if tbar.subDungeonsBtn then
      tbar.subDungeonsBtn:SetOnClick(function()
        GoldFarmsUI.Dispatch("SET_SUBVIEW", { subView = "dungeons" })
      end)
      Widgets.BindTooltip(
        tbar.subDungeonsBtn,
        "Dungeon Session Ledger (Observed Only)",
        {
          "Reconciled instance session coin, unsold/realized loot, and durability-baseline repairs.",
          "Observed admissions; remaining account lockout capacity is unknown.",
        }
      )
    end

    tbar.targetMacroBtn = Widgets.CreateSecondaryButton(tbar, 104, "Target Macro", 22)
    if tbar.targetMacroBtn then
      tbar.targetMacroBtn:SetOnClick(function()
        GoldFarmsUI.Dispatch("CREATE_TARGET_MACRO")
      end)
      Widgets.BindTooltip(
        tbar.targetMacroBtn,
        "Create / Update 'FH_Target' Macro",
        {
          "Creates or updates out-of-combat macro 'FH_Target' with '/stopmacro [harm,nodead]' target preservation and '/targetexact'.",
          "Drag 'FH_Target' from /macro onto a keybind to acquire camp species without overwriting a live pull.",
        }
      )
    end

    tbar.radarModeBtn = Widgets.CreateGhostButton(tbar, 126, "Radar: Auto (ON)", 22)
    if tbar.radarModeBtn then
      tbar.radarModeBtn:SetOnClick(function()
        GoldFarmsUI.Dispatch("CYCLE_RADAR_MODE")
      end)
      Widgets.BindTooltip(
        tbar.radarModeBtn,
        "Toggle Candidate-Spawn Radar",
        {
          "Cycles Spawn Radar mode: Auto -> ON -> OFF.",
          "Points the ForeverHub arrow to the nearest recorded spawn point (verified kills ~180s revisit est.; manual skip ~120s).",
        }
      )
    end
  end

  -- 2. Purse / XP Progress Bar (`6` high) + Quote/Reserve & Telemetry Controls (60h)
  local mbar = Widgets.CreatePanel(host, "surface.card", "border.subtle")
  GoldFarmsUI.mountBar = mbar
  if mbar then
    mbar.leftLabel = Widgets.SafeCreateFontString(mbar, "dense", "text.primary")
    if mbar.leftLabel then
      Widgets.SafeSetPoint(mbar.leftLabel, "TOPLEFT", mbar, "TOPLEFT", 12, -7)
      if type(mbar.leftLabel.SetJustifyH) == "function" then pcall(mbar.leftLabel.SetJustifyH, mbar.leftLabel, "LEFT") end
    end

    mbar.rightLabel = Widgets.SafeCreateFontString(mbar, "dense", "text.muted")
    if mbar.rightLabel then
      Widgets.SafeSetPoint(mbar.rightLabel, "TOPRIGHT", mbar, "TOPRIGHT", -12, -7)
      if type(mbar.rightLabel.SetJustifyH) == "function" then pcall(mbar.rightLabel.SetJustifyH, mbar.rightLabel, "RIGHT") end
    end

    mbar.arcaneTipLabel = Widgets.SafeCreateFontString(mbar, "dense", "text.secondary")
    if mbar.arcaneTipLabel then
      Widgets.SafeSetPoint(mbar.arcaneTipLabel, "BOTTOMLEFT", mbar, "BOTTOMLEFT", 12, 8)
      if type(mbar.arcaneTipLabel.SetJustifyH) == "function" then pcall(mbar.arcaneTipLabel.SetJustifyH, mbar.arcaneTipLabel, "LEFT") end
    end

    mbar.track = Widgets.CreatePanel(mbar, "surface.window", "border.subtle")
    if mbar.track then
      Widgets.SafeSetHeight(mbar.track, 6)
      mbar.fill = Widgets.SafeCreateTexture(mbar.track, "ARTWORK", 2)
      if mbar.fill then
        Widgets.SafeSetPoint(mbar.fill, "TOPLEFT", mbar.track, "TOPLEFT", 1, -1)
        Widgets.SafeSetHeight(mbar.fill, 4)
        Widgets.SafeSetSolidColor(mbar.fill, "accent.gold", 1.0)
      end
    end

    mbar.quote90Btn = Widgets.CreateGhostButton(mbar, 96, "Confirm 90g", 22)
    if mbar.quote90Btn then
      mbar.quote90Btn:SetOnClick(function()
        GoldFarmsUI.Dispatch("SET_QUOTE_HONORED")
      end)
      Widgets.BindTooltip(mbar.quote90Btn, "Confirm 90g Honored Quote", { "Marks the 90g Honored trainer quote as confirmed." })
    end

    mbar.quote100Btn = Widgets.CreateGhostButton(mbar, 78, "100g Base", 22)
    if mbar.quote100Btn then
      mbar.quote100Btn:SetOnClick(function()
        GoldFarmsUI.Dispatch("SET_QUOTE_BASE")
      end)
      Widgets.BindTooltip(mbar.quote100Btn, "Set 100g Unimputed Base Quote", { "Sets target to 100g (0% faction discount)." })
    end

    mbar.res0Btn = Widgets.CreateGhostButton(mbar, 58, "Buf 0g", 22)
    if mbar.res0Btn then
      mbar.res0Btn:SetOnClick(function() GoldFarmsUI.Dispatch("SET_RESERVE_GOLD", { gold = 0 }) end)
    end
    mbar.res5Btn = Widgets.CreateGhostButton(mbar, 58, "Buf 5g", 22)
    if mbar.res5Btn then
      mbar.res5Btn:SetOnClick(function() GoldFarmsUI.Dispatch("SET_RESERVE_GOLD", { gold = 5 }) end)
    end
    mbar.res10Btn = Widgets.CreateGhostButton(mbar, 64, "Buf 10g", 22)
    if mbar.res10Btn then
      mbar.res10Btn:SetOnClick(function() GoldFarmsUI.Dispatch("SET_RESERVE_GOLD", { gold = 10 }) end)
    end

    mbar.pinModeBtn = Widgets.CreateGhostButton(mbar, 94, "Pins: Active", 22)
    if mbar.pinModeBtn then
      mbar.pinModeBtn:SetOnClick(function()
        GoldFarmsUI.Dispatch("CYCLE_SPAWN_PIN_MODE")
      end)
      Widgets.BindTooltip(
        mbar.pinModeBtn,
        "Toggle World Map Spawn Pins",
        {
          "Cycles spawn-point dots on the World Map: Active subcamp -> All subcamps -> OFF.",
          "Vendor & travel service markers remain readable above ordinary dots.",
        }
      )
    end

    mbar.skipSpawnBtn = Widgets.CreateGhostButton(mbar, 84, "Skip Spot", 22)
    if mbar.skipSpawnBtn then
      mbar.skipSpawnBtn:SetOnClick(function()
        GoldFarmsUI.Dispatch("SKIP_SPAWN")
      end)
      Widgets.BindTooltip(
        mbar.skipSpawnBtn,
        "Skip Current Spawn Point (~120s)",
        {
          "Manually suppresses the currently locked spawn coordinate for ~120s if empty or contested (/fh gold skip).",
          "ForeverHub never auto-suppresses unobserved points just because nameplates are off.",
        }
      )
    end

    -- Session telemetry controls strictly separate from route navigation
    mbar.resetMeterBtn = Widgets.CreateSecondaryButton(mbar, 96, "Reset meter", 22)
    if mbar.resetMeterBtn then
      mbar.resetMeterBtn:SetOnClick(function()
        GoldFarmsUI.Dispatch("RESET_METER")
      end)
      Widgets.BindTooltip(
        mbar.resetMeterBtn,
        "Reset Session Cash-Flow Meter",
        { "Starts a clean observed purse interval without stopping route navigation." }
      )
    end

    mbar.exportAllBtn = Widgets.CreateGhostButton(mbar, 108, "Export all RXP", 22)
    if mbar.exportAllBtn then
      mbar.exportAllBtn:SetOnClick(function()
        GoldFarmsUI.Dispatch("EXPORT_RXP")
      end)
      Widgets.BindTooltip(
        mbar.exportAllBtn,
        "Export Track Candidates to RestedXP",
        { "Registers verified track guides under '+ForeverHub Gold Farms' without changing your active RXP guide." }
      )
    end
  end

  -- 2b. Arcane Subcamp Filter Strip (28h, visible on Arcane Routes view)
  local sfbar = Widgets.CreatePanel(host, "surface.card", "border.subtle")
  GoldFarmsUI.subFilterBar = sfbar
  if sfbar then
    sfbar.pills = {}
    for idx, opt in ipairs(SUBFILTER_OPTIONS) do
      local pBtn = Widgets.CreateGhostButton(sfbar, opt.width, opt.label, 22)
      if pBtn then
        local targetKey = opt.key
        pBtn.__subFilterKey = targetKey
        pBtn:SetOnClick(function()
          GoldFarmsUI.Dispatch("SET_SUBFILTER", { subFilter = targetKey })
        end)
        Widgets.BindTooltip(pBtn, opt.label, { opt.tip, "Visibility-only filter: never interrupts active navigation or session meters." })
        sfbar.pills[idx] = pBtn
      end
    end
    sfbar.headerLabel = Widgets.SafeCreateFontString(sfbar, "dense", "text.muted")
    if sfbar.headerLabel and type(sfbar.headerLabel.SetJustifyH) == "function" then
      pcall(sfbar.headerLabel.SetJustifyH, sfbar.headerLabel, "RIGHT")
    end
    Widgets.SafeShow(sfbar, false)
  end

  -- 2c. Persistent Active Route Summary Strip when active route is hidden by sub-filter (Astra P2-1, 30h)
  local abanner = Widgets.CreatePanel(host, "surface.selected", "accent.gold")
  GoldFarmsUI.activeRouteBanner = abanner
  if abanner then
    abanner.text = Widgets.SafeCreateFontString(abanner, "dense", "text.primary")
    if abanner.text and type(abanner.text.SetJustifyH) == "function" then
      pcall(abanner.text.SetJustifyH, abanner.text, "LEFT")
    end
    abanner.showBtn = Widgets.CreateSecondaryButton(abanner, 92, "Show active", 22)
    abanner.stopBtn = Widgets.CreateGhostButton(abanner, 64, "Stop", 22)
    if abanner.stopBtn then
      abanner.stopBtn:SetOnClick(function()
        GoldFarmsUI.Dispatch("STOP_NAVIGATION")
      end)
    end
    Widgets.SafeShow(abanner, false)
  end

  -- 3. Scroll Viewport for Farm Cards
  GoldFarmsUI.viewport = Widgets.CreateScrollViewport(host, function(offset)
    local st = ns.State.GetWorkspaceUIState()
    st.goldView.scrollOffset = offset
  end)

  return host
end

function GoldFarmsUI.RenderInHost(viewportWidth, viewportHeight, isCompact, snapshotOverride)
  local host = GoldFarmsUI.EnsureHost()
  if not host then
    return nil
  end

  local generation = Widgets.BumpGeneration()
  local pad = Theme.METRICS.workspacePadding
  local vw = math.max(700, tonumber(viewportWidth) or 928)
  local vh = math.max(360, (tonumber(viewportHeight) or 560) - 16)
  local compact = (isCompact == true)
  Widgets.SafeClearPoints(host)
  Widgets.SafeSetSize(host, vw, vh)
  Widgets.SafeSetPoint(host, "TOPLEFT", host.__parentRef, "TOPLEFT", pad, -8)
  Widgets.SafeShow(host, true)

  local uiState = ns.State.GetWorkspaceUIState()
  local snap = Presenter.CaptureSnapshot(snapshotOverride)
  local vm = Presenter.Build(snap, uiState)
  GoldFarmsUI.lastViewModel = vm

  if ns.UI.Workspace and ns.UI.Workspace.SetTabBadge then
    ns.UI.Workspace.SetTabBadge("gold", vm.tabBadge)
  end

  -- 1. Layout 5 KPIs
  local summaryH = Theme.METRICS.summaryHeight
  Widgets.SafeClearPoints(GoldFarmsUI.summaryStrip)
  Widgets.SafeSetPoint(GoldFarmsUI.summaryStrip, "TOPLEFT", host, "TOPLEFT", 0, 0)
  Widgets.SafeSetSize(GoldFarmsUI.summaryStrip, vw, summaryH)
  local kpiW = math.floor((vw - 24) / 5)
  for i = 1, 5 do
    local kw = GoldFarmsUI.kpis[i]
    local kd = vm.kpis[i]
    if kw and kd then
      Widgets.SafeClearPoints(kw)
      Widgets.SafeSetPoint(kw, "TOPLEFT", GoldFarmsUI.summaryStrip, "TOPLEFT", 12 + (i - 1) * kpiW, -6)
      Widgets.SafeSetSize(kw, kpiW - 6, 48)
      kw:SetKPI(kd.value, kd.label, kd.sub, kd.token, kd.tooltipTitle, kd.tooltipLines)
    end
  end

  local activeSubView = (uiState.goldView and uiState.goldView.subView == "dungeons") and "dungeons" or "routes"

  -- 1b. Layout Track Switcher & Spawn Radar Strip
  local tbarH = 32
  local tbar = GoldFarmsUI.trackBar
  if tbar then
    Widgets.SafeClearPoints(tbar)
    Widgets.SafeSetPoint(tbar, "TOPLEFT", host, "TOPLEFT", 0, -(summaryH + 6))
    Widgets.SafeSetSize(tbar, vw, tbarH)

    if tbar.trackLabel then
      Theme.ApplyFont(tbar.trackLabel, "dense", "text.muted")
      Widgets.SafeClearPoints(tbar.trackLabel)
      Widgets.SafeSetPoint(tbar.trackLabel, "LEFT", tbar, "LEFT", 12, 0)
    end
    if tbar.trackArcaneBtn then
      tbar.trackArcaneBtn.__isSelected = (activeSubView == "routes" and vm.effectiveTrack == "arcane_lvl47_st")
      tbar.trackArcaneBtn:RefreshVisualState()
      Widgets.SafeClearPoints(tbar.trackArcaneBtn)
      Widgets.SafeSetPoint(tbar.trackArcaneBtn, "LEFT", tbar, "LEFT", 52, 0)
    end
    if tbar.trackMountBtn then
      tbar.trackMountBtn.__isSelected = (activeSubView == "routes" and vm.effectiveTrack == "lvl40_mount")
      tbar.trackMountBtn:RefreshVisualState()
      Widgets.SafeClearPoints(tbar.trackMountBtn)
      Widgets.SafeSetPoint(tbar.trackMountBtn, "LEFT", tbar.trackArcaneBtn, "RIGHT", 4, 0)
    end
    if tbar.subRoutesBtn then
      tbar.subRoutesBtn.__isSelected = (activeSubView == "routes")
      tbar.subRoutesBtn:RefreshVisualState()
      Widgets.SafeClearPoints(tbar.subRoutesBtn)
      Widgets.SafeSetPoint(tbar.subRoutesBtn, "LEFT", tbar.trackMountBtn, "RIGHT", 8, 0)
    end
    if tbar.subDungeonsBtn then
      tbar.subDungeonsBtn.__isSelected = (activeSubView == "dungeons")
      tbar.subDungeonsBtn:RefreshVisualState()
      Widgets.SafeClearPoints(tbar.subDungeonsBtn)
      Widgets.SafeSetPoint(tbar.subDungeonsBtn, "LEFT", tbar.subRoutesBtn, "RIGHT", 4, 0)
    end
    if tbar.targetMacroBtn then
      Widgets.SafeClearPoints(tbar.targetMacroBtn)
      Widgets.SafeSetPoint(tbar.targetMacroBtn, "RIGHT", tbar, "RIGHT", -10, 0)
    end
    if tbar.radarModeBtn then
      if tbar.radarModeBtn.SetLabel then
        tbar.radarModeBtn:SetLabel(vm.radarPillLabel or "Radar: Auto")
      end
      tbar.radarModeBtn.__isSelected = (vm.spawnRadarEffectiveOn == true)
      tbar.radarModeBtn:RefreshVisualState()
      Widgets.SafeClearPoints(tbar.radarModeBtn)
      Widgets.SafeSetPoint(tbar.radarModeBtn, "RIGHT", tbar.targetMacroBtn, "LEFT", -6, 0)
    end
  end

  -- 2. Layout 6-unit Progress Bar + Controls Strip
  local mbarH = 60
  local mbar = GoldFarmsUI.mountBar
  Widgets.SafeClearPoints(mbar)
  Widgets.SafeSetPoint(mbar, "TOPLEFT", host, "TOPLEFT", 0, -(summaryH + 6 + tbarH + 6))
  Widgets.SafeSetSize(mbar, vw, mbarH)

  if mbar.leftLabel then
    Theme.ApplyFont(mbar.leftLabel, "dense", "text.primary")
    mbar.leftLabel:SetText(vm.progressLeftText)
  end
  if mbar.rightLabel then
    Theme.ApplyFont(mbar.rightLabel, "dense", "text.muted")
    mbar.rightLabel:SetText(compact and "" or vm.progressRightText)
  end
  if mbar.track then
    local trackW = vw - 24
    Widgets.SafeClearPoints(mbar.track)
    Widgets.SafeSetPoint(mbar.track, "TOPLEFT", mbar, "TOPLEFT", 12, -24)
    Widgets.SafeSetSize(mbar.track, trackW, 6)
    if mbar.fill then
      local fillW = math.floor((trackW - 2) * (vm.progressFraction or 0) + 0.5)
      if fillW <= 0 then
        Widgets.SafeShow(mbar.fill, false)
      else
        Widgets.SafeSetWidth(mbar.fill, fillW)
        Widgets.SafeSetSolidColor(mbar.fill, (vm.progressFraction >= 1.0) and "status.ready" or "accent.gold", 1.0)
        Widgets.SafeShow(mbar.fill, true)
      end
    end
  end

  local showMountButtons = not vm.isArcaneTrack
  if mbar.pinModeBtn then
    if mbar.pinModeBtn.SetLabel then
      mbar.pinModeBtn:SetLabel(vm.pinPillLabel or "Pins: Active")
    end
    mbar.pinModeBtn.__isSelected = (vm.spawnPinMode ~= "off")
    mbar.pinModeBtn:RefreshVisualState()
    Widgets.SafeClearPoints(mbar.pinModeBtn)
    Widgets.SafeSetPoint(mbar.pinModeBtn, "BOTTOMLEFT", mbar, "BOTTOMLEFT", 10, 5)
    Widgets.SafeShow(mbar.pinModeBtn, vm.isArcaneTrack)
  end
  if mbar.skipSpawnBtn then
    Widgets.SafeClearPoints(mbar.skipSpawnBtn)
    Widgets.SafeSetPoint(mbar.skipSpawnBtn, "LEFT", mbar.pinModeBtn, "RIGHT", 6, 0)
    Widgets.SafeShow(mbar.skipSpawnBtn, vm.isArcaneTrack and vm.isAnyGoldNavActive)
  end
  if mbar.arcaneTipLabel then
    Theme.ApplyFont(mbar.arcaneTipLabel, "dense", "text.secondary")
    Widgets.SafeClearPoints(mbar.arcaneTipLabel)
    local anchorBtn = (vm.isAnyGoldNavActive and mbar.skipSpawnBtn) or mbar.pinModeBtn
    if anchorBtn then
      Widgets.SafeSetPoint(mbar.arcaneTipLabel, "LEFT", anchorBtn, "RIGHT", 10, 0)
    else
      Widgets.SafeSetPoint(mbar.arcaneTipLabel, "BOTTOMLEFT", mbar, "BOTTOMLEFT", 12, 8)
    end
    mbar.arcaneTipLabel:SetText("Verified kills ~180s revisit · Manual skip ~120s")
    Widgets.SafeShow(mbar.arcaneTipLabel, vm.isArcaneTrack and (not compact) and vw >= 820)
  end

  if mbar.quote90Btn then
    mbar.quote90Btn.__isSelected = (vm.quoteConfirmed and vm.targetCopper == 900000)
    mbar.quote90Btn:RefreshVisualState()
    Widgets.SafeClearPoints(mbar.quote90Btn)
    Widgets.SafeSetPoint(mbar.quote90Btn, "BOTTOMLEFT", mbar, "BOTTOMLEFT", 10, 5)
    Widgets.SafeShow(mbar.quote90Btn, showMountButtons)
  end
  if mbar.quote100Btn then
    mbar.quote100Btn.__isSelected = (vm.targetCopper == 1000000)
    mbar.quote100Btn:RefreshVisualState()
    Widgets.SafeClearPoints(mbar.quote100Btn)
    Widgets.SafeSetPoint(mbar.quote100Btn, "LEFT", mbar.quote90Btn, "RIGHT", 4, 0)
    Widgets.SafeShow(mbar.quote100Btn, showMountButtons)
  end
  if mbar.res0Btn then
    mbar.res0Btn.__isSelected = (vm.reserveCopper == 0)
    mbar.res0Btn:RefreshVisualState()
    Widgets.SafeClearPoints(mbar.res0Btn)
    Widgets.SafeSetPoint(mbar.res0Btn, "LEFT", mbar.quote100Btn, "RIGHT", 10, 0)
    Widgets.SafeShow(mbar.res0Btn, showMountButtons)
  end
  if mbar.res5Btn then
    mbar.res5Btn.__isSelected = (vm.reserveCopper == 50000)
    mbar.res5Btn:RefreshVisualState()
    Widgets.SafeClearPoints(mbar.res5Btn)
    Widgets.SafeSetPoint(mbar.res5Btn, "LEFT", mbar.res0Btn, "RIGHT", 4, 0)
    Widgets.SafeShow(mbar.res5Btn, showMountButtons)
  end
  if mbar.res10Btn then
    mbar.res10Btn.__isSelected = (vm.reserveCopper == 100000)
    mbar.res10Btn:RefreshVisualState()
    Widgets.SafeClearPoints(mbar.res10Btn)
    Widgets.SafeSetPoint(mbar.res10Btn, "LEFT", mbar.res5Btn, "RIGHT", 4, 0)
    Widgets.SafeShow(mbar.res10Btn, showMountButtons)
  end
  if mbar.resetMeterBtn then
    Widgets.SafeClearPoints(mbar.resetMeterBtn)
    Widgets.SafeSetPoint(mbar.resetMeterBtn, "BOTTOMRIGHT", mbar, "BOTTOMRIGHT", -10, 5)
  end
  if mbar.exportAllBtn then
    Widgets.SafeClearPoints(mbar.exportAllBtn)
    Widgets.SafeSetPoint(mbar.exportAllBtn, "RIGHT", mbar.resetMeterBtn, "LEFT", -6, 0)
    if vm.isArcaneTrack then
      Widgets.BindTooltip(
        mbar.exportAllBtn,
        string.format("Export All %d Arcane Candidates to RestedXP", tonumber(vm.allArcaneCount) or 19),
        { "Registers all verified Level 46–60 Arcane ST Mage guides under '+ForeverHub Gold Farms' without changing your active RXP guide." }
      )
    else
      Widgets.BindTooltip(
        mbar.exportAllBtn,
        "Export All 5 Candidates to RestedXP",
        { "Registers all 5 verified Level 40 Mage gold farm guides under '+ForeverHub Gold Farms'." }
      )
    end
  end

  local curTop = summaryH + 6 + tbarH + 6 + mbarH + 6

  -- 2b. Layout Arcane Subcamp Filter Strip (visibility-only)
  local showSubFilterBar = (vm.isArcaneTrack == true) and (activeSubView == "routes")
  local sfbar = GoldFarmsUI.subFilterBar
  if sfbar then
    if showSubFilterBar then
      local sfH = 28
      Widgets.SafeClearPoints(sfbar)
      Widgets.SafeSetPoint(sfbar, "TOPLEFT", host, "TOPLEFT", 0, -curTop)
      Widgets.SafeSetSize(sfbar, vw, sfH)
      local px = 8
      for idx, pBtn in ipairs(sfbar.pills or {}) do
        local opt = SUBFILTER_OPTIONS[idx]
        if pBtn and opt then
          if opt.key == "all_shortlist" and pBtn.SetLabel then
            pBtn:SetLabel(string.format("All (%d)", tonumber(vm.allArcaneCount) or 19))
          end
          pBtn.__isSelected = (vm.subFilter == opt.key)
          pBtn:RefreshVisualState()
          Widgets.SafeClearPoints(pBtn)
          Widgets.SafeSetPoint(pBtn, "LEFT", sfbar, "LEFT", px, 0)
          px = px + (tonumber(opt.width) or 56) + 3
        end
      end
      if sfbar.headerLabel then
        Theme.ApplyFont(sfbar.headerLabel, "dense", "text.muted")
        Widgets.SafeClearPoints(sfbar.headerLabel)
        Widgets.SafeSetPoint(sfbar.headerLabel, "RIGHT", sfbar, "RIGHT", -10, 0)
        sfbar.headerLabel:SetText(compact and "" or tostring(vm.subFilterHeader or ""))
        Widgets.SafeShow(sfbar.headerLabel, (not compact) and vw >= 840)
      end
      Widgets.SafeShow(sfbar, true)
      curTop = curTop + sfH + 6
    else
      Widgets.SafeShow(sfbar, false)
    end
  end

  -- 2c. Layout Persistent Active Route Summary Strip when hidden by filter (Astra P2-1)
  local hiddenSummary = (showSubFilterBar and vm.hiddenActiveRouteSummary) or nil
  local abanner = GoldFarmsUI.activeRouteBanner
  if abanner then
    if hiddenSummary then
      local abH = 30
      Widgets.SafeClearPoints(abanner)
      Widgets.SafeSetPoint(abanner, "TOPLEFT", host, "TOPLEFT", 0, -curTop)
      Widgets.SafeSetSize(abanner, vw, abH)
      if abanner.stopBtn then
        Widgets.SafeClearPoints(abanner.stopBtn)
        Widgets.SafeSetPoint(abanner.stopBtn, "RIGHT", abanner, "RIGHT", -8, 0)
        Widgets.SafeShow(abanner.stopBtn, true)
      end
      if abanner.showBtn then
        local targetFilter = hiddenSummary.isExperimental and "experimental" or "all_shortlist"
        local targetFID = hiddenSummary.farmID
        abanner.showBtn:SetOnClick(function()
          GoldFarmsUI.Dispatch("SET_SUBFILTER", { subFilter = targetFilter, focusFarmID = targetFID })
        end)
        Widgets.SafeClearPoints(abanner.showBtn)
        Widgets.SafeSetPoint(abanner.showBtn, "RIGHT", abanner.stopBtn, "LEFT", -6, 0)
        Widgets.SafeShow(abanner.showBtn, true)
      end
      if abanner.text then
        Theme.ApplyFont(abanner.text, "dense", "accent.gold")
        Widgets.SafeClearPoints(abanner.text)
        Widgets.SafeSetPoint(abanner.text, "LEFT", abanner, "LEFT", 12, 0)
        abanner.text:SetText(
          string.format("▶ Active route (hidden by filter): %s · %s", tostring(hiddenSummary.title), tostring(hiddenSummary.stepSummary))
        )
      end
      Widgets.SafeShow(abanner, true)
      curTop = curTop + abH + 6
    else
      if abanner.showBtn then
        abanner.showBtn:SetOnClick(nil)
      end
      Widgets.SafeShow(abanner, false)
    end
  end

  -- 3. Layout Collapsible Farm Rows
  local bodyTop = curTop + 2
  local vpH = math.max(140, vh - bodyTop)
  local rowWidth = vw - Theme.METRICS.scrollbarLaneWidth
  local content = GoldFarmsUI.viewport.content

  Widgets.SafeClearPoints(GoldFarmsUI.viewport)
  Widgets.SafeSetPoint(GoldFarmsUI.viewport, "TOPLEFT", host, "TOPLEFT", 0, -bodyTop)

  resetPool(GoldFarmsUI.cardPool, "cards")
  resetPool(GoldFarmsUI.badgePool, "badges")

  local y = 0
  local cardReports = {}
  local primaryGoldButtonCount = 0
  local dungeonSummary = nil

  if activeSubView == "dungeons" then
    local stCoach = ns.Domain and ns.Domain.SunkenTempleCoach
    if stCoach and type(stCoach.GetViewModel) == "function" then
      local stVm = stCoach.GetViewModel()
      if not GoldFarmsUI.stCoachPanel then
        local sp = Widgets.CreatePanel(content, "surface.card", "border.default")
        if sp then
          sp.headerText = Widgets.SafeCreateFontString(sp, "sectionTitle", "accent.gold")
          sp.statusText = Widgets.SafeCreateFontString(sp, "body", "text.primary")
          sp.bodyText = Widgets.SafeCreateFontString(sp, "dense", "text.secondary")
          for _, fs in ipairs({ sp.headerText, sp.statusText, sp.bodyText }) do
            if fs and type(fs.SetJustifyH) == "function" then
              pcall(fs.SetJustifyH, fs, "LEFT")
            end
          end

          sp.primaryBtn = Widgets.CreatePrimaryButton(sp, 98, "Start", 22)
          sp.prevBtn = Widgets.CreateGhostButton(sp, 50, "Prev", 22)
          sp.nextBtn = Widgets.CreateSecondaryButton(sp, 54, "Next", 22)
          sp.abortBtn = Widgets.CreateGhostButton(sp, 56, "Abort", 22)
          sp.probeBtn = Widgets.CreateSecondaryButton(sp, 118, "Run /fh st probe", 22)
          sp.cardToggleBtn = Widgets.CreateGhostButton(sp, 102, "Hide HUD Card", 22)
        end
        GoldFarmsUI.stCoachPanel = sp
      end

      local sp = GoldFarmsUI.stCoachPanel
      if sp then
        local innerW = math.max(200, rowWidth - 28)
        local stHeader = string.format(
          "Sunken Temple Solo Coach (RC1)  ·  State: %s",
          tostring(stVm.sessionState or "INACTIVE")
        )
        local stStatus = string.format(
          "Instance Gate: %s  ·  %s",
          tostring(stVm.instanceClassification or "outside"),
          tostring(stVm.landmarkLine or "")
        )

        local stLines = {
          "• " .. tostring(stVm.instructionLine or ""),
        }
        if stVm.referenceVideo then
          table.insert(
            stLines,
            string.format(
              "• Reference: %s — %s (%s -> Target: %s · Live-confirmed phases this session: %d/%d via '/fh st confirm')",
              tostring(stVm.referenceVideo.creator or "Broog"),
              tostring(stVm.referenceVideo.sourceUrl or ""),
              tostring(stVm.referenceVideo.recordedCharacter or "Orc Mage"),
              tostring(stVm.referenceVideo.targetCharacter or "Alliance Gnome Frost Mage Lv54"),
              tonumber(stVm.confirmedPhaseCount) or 0,
              tonumber(stVm.totalPhases) or 6
            )
          )
        end

        if stVm.lastProbe then
          local lp = stVm.lastProbe
          local lpInst = lp.instance or {}
          local lpSig = lp.signals or {}
          table.insert(
            stLines,
            string.format(
              "• Latest /fh st probe [%s]: Build %s (Interface %s, issecretvalue=%s, lockdown=%s) · r8_instanceID=%s(%s) vs r9_groupSize=%s(%s) · cast=%s · aura=%s · hp=%s/%s · subzone=%s · yell=%s · target=%s (probe never unlocks ST-10 route cues)",
              tostring(lp.contextLabel or "?"),
              tostring(lp.client and lp.client.build or "?"),
              tostring(lp.client and lp.client.interfaceVersion or "?"),
              tostring(lp.client and lp.client.hasSecretValueDetector == true),
              tostring(lp.client and lp.client.inCombatLockdown == true),
              tostring(lpInst.return8_instanceID_value or "nil"),
              tostring(lpInst.return8_instanceID_status or "?"),
              tostring(lpInst.return9_groupSize_value or "nil"),
              tostring(lpInst.return9_groupSize_status or "?"),
              tostring(lpSig.unitSpellcastSucceeded and lpSig.unitSpellcastSucceeded.status or "?"),
              tostring(lpSig.cUnitAuras and lpSig.cUnitAuras.bySpellIDStatus or "?"),
              tostring(lpSig.unitHealth and lpSig.unitHealth.healthStatus or "?"),
              tostring(lpSig.unitHealth and lpSig.unitHealth.maxHealthStatus or "?"),
              tostring(lpSig.subZone and lpSig.subZone.subZoneStatus or "?"),
              tostring(lpSig.monsterYell and lpSig.monsterYell.status or "?"),
              tostring(lpSig.target and lpSig.target.guidStatus or "?")
            )
          )
        else
          table.insert(stLines, "• Live Probe: Not run yet this session (opt-in via 'Run /fh st probe' or '/fh st probe' outside, inside OOC, and during trash combat).")
        end

        local aut = stVm.lastAutopsy
        if aut then
          table.insert(
            stLines,
            string.format(
              "=== Last Pull Autopsy (Attempt #%d · Outcome: %s · %.1fs · Phase: %s · Events: %d%s) ===",
              tonumber(aut.attemptID) or 1,
              tostring(aut.outcome or "?"),
              tonumber(aut.durationSec) or 0,
              tostring(aut.terminalPhaseTitle or "?"),
              tonumber(aut.totalObservedEvents) or 0,
              aut.overflowed and " [64-event ring rotated; header preserved]" or ""
            )
          )
          for _, c in ipairs(aut.confirmed or {}) do
            table.insert(stLines, string.format("  [CONFIRMED] %s (Evidence: %s)", tostring(c.summary), tostring(c.evidence)))
          end
          for _, h in ipairs(aut.likelyHeuristics or {}) do
            table.insert(
              stLines,
              string.format(
                "  [LIKELY_HEURISTIC] %s (Missing link: %s)",
                tostring(h.summary),
                tostring(h.missingLink or "unverified")
              )
            )
          end
          for _, u in ipairs(aut.unobservable or {}) do
            table.insert(stLines, string.format("  [UNOBSERVABLE_IN_16001] %s", tostring(u.summary)))
          end
        else
          table.insert(stLines, "• Pull Autopsy: No closed attempt in this session yet (ephemeral in-memory; 0 SavedVariables bytes).")
        end

        local stBodyJoined = table.concat(stLines, "\n")
        if sp.headerText then
          Widgets.SafeClearPoints(sp.headerText)
          Widgets.SafeSetPoint(sp.headerText, "TOPLEFT", sp, "TOPLEFT", 14, -12)
          Theme.ApplyFont(sp.headerText, "sectionTitle", "accent.gold")
        end
        local shH = Theme.MeasureWrappedHeight(sp.headerText, stHeader, innerW, "sectionTitle", 20, 0)

        if sp.statusText then
          Widgets.SafeClearPoints(sp.statusText)
          Widgets.SafeSetPoint(sp.statusText, "TOPLEFT", sp, "TOPLEFT", 14, -(12 + shH + 4))
          Theme.ApplyFont(sp.statusText, "body", "text.primary")
        end
        local ssH = Theme.MeasureWrappedHeight(sp.statusText, stStatus, innerW, "body", 18, 0)

        local btnRowTop = 12 + shH + 4 + ssH + 6
        local function setSpBtn(btn, en)
          if not btn then return end
          btn.__disabled = not en
          if Widgets.SetButtonEnabled then
            pcall(Widgets.SetButtonEnabled, btn, en)
          end
        end
        if sp.primaryBtn then
          Widgets.SafeClearPoints(sp.primaryBtn)
          Widgets.SafeSetPoint(sp.primaryBtn, "TOPLEFT", sp, "TOPLEFT", 14, -btnRowTop)
          if stVm.sessionState == "RECOVERY" then
            if sp.primaryBtn.SetLabel then sp.primaryBtn:SetLabel("Rearm Coach") end
            setSpBtn(sp.primaryBtn, stVm.canRearm)
            sp.primaryBtn:SetOnClick(function()
              if sp.primaryBtn.__disabled then return end
              stCoach.RearmCoach()
            end)
          elseif stVm.sessionState == "ACTIVE" then
            if sp.primaryBtn.SetLabel then sp.primaryBtn:SetLabel("Finish") end
            setSpBtn(sp.primaryBtn, stVm.canFinish)
            sp.primaryBtn:SetOnClick(function()
              if sp.primaryBtn.__disabled then return end
              stCoach.FinishAttempt()
            end)
          else
            if sp.primaryBtn.SetLabel then sp.primaryBtn:SetLabel("Start") end
            setSpBtn(sp.primaryBtn, stVm.canStart)
            sp.primaryBtn:SetOnClick(function()
              if sp.primaryBtn.__disabled then return end
              stCoach.StartAttempt()
            end)
          end
        end
        if sp.prevBtn and sp.primaryBtn then
          Widgets.SafeClearPoints(sp.prevBtn)
          Widgets.SafeSetPoint(sp.prevBtn, "LEFT", sp.primaryBtn, "RIGHT", 6, 0)
          setSpBtn(sp.prevBtn, stVm.canPrev)
          sp.prevBtn:SetOnClick(function()
            if sp.prevBtn.__disabled then return end
            stCoach.PrevPhase()
          end)
        end
        if sp.nextBtn and sp.prevBtn then
          Widgets.SafeClearPoints(sp.nextBtn)
          Widgets.SafeSetPoint(sp.nextBtn, "LEFT", sp.prevBtn, "RIGHT", 6, 0)
          setSpBtn(sp.nextBtn, stVm.canNext)
          sp.nextBtn:SetOnClick(function()
            if sp.nextBtn.__disabled then return end
            stCoach.NextPhase()
          end)
        end
        if sp.abortBtn and sp.nextBtn then
          Widgets.SafeClearPoints(sp.abortBtn)
          Widgets.SafeSetPoint(sp.abortBtn, "LEFT", sp.nextBtn, "RIGHT", 6, 0)
          setSpBtn(sp.abortBtn, stVm.canAbort)
          sp.abortBtn:SetOnClick(function()
            if sp.abortBtn.__disabled then return end
            stCoach.AbortAttempt("dungeons_panel_abort")
          end)
        end
        if sp.probeBtn and sp.abortBtn then
          Widgets.SafeClearPoints(sp.probeBtn)
          Widgets.SafeSetPoint(sp.probeBtn, "LEFT", sp.abortBtn, "RIGHT", 10, 0)
          setSpBtn(sp.probeBtn, true)
          sp.probeBtn:SetOnClick(function()
            if ns.Events and ns.Events.HandleSunkenTempleSubcommand then
              ns.Events.HandleSunkenTempleSubcommand("probe")
            else
              stCoach.RunOptInProbe()
            end
          end)
        end
        if sp.cardToggleBtn and sp.probeBtn then
          Widgets.SafeClearPoints(sp.cardToggleBtn)
          Widgets.SafeSetPoint(sp.cardToggleBtn, "LEFT", sp.probeBtn, "RIGHT", 6, 0)
          if sp.cardToggleBtn.SetLabel then
            sp.cardToggleBtn:SetLabel(stVm.hudCardHidden and "Show HUD Card" or "Hide HUD Card")
          end
          setSpBtn(sp.cardToggleBtn, true)
          sp.cardToggleBtn:SetOnClick(function()
            stCoach.SetHudCardHidden(not stVm.hudCardHidden)
          end)
        end

        local bodyTop = btnRowTop + 28
        if sp.bodyText then
          Widgets.SafeClearPoints(sp.bodyText)
          Widgets.SafeSetPoint(sp.bodyText, "TOPLEFT", sp, "TOPLEFT", 14, -bodyTop)
          Theme.ApplyFont(sp.bodyText, "dense", "text.secondary")
        end
        local sbH = Theme.MeasureWrappedHeight(sp.bodyText, stBodyJoined, innerW, "dense", 48, 0)
        local spH = math.max(150, bodyTop + sbH + 14)
        Widgets.SafeClearPoints(sp)
        Widgets.SafeSetPoint(sp, "TOPLEFT", content, "TOPLEFT", 0, -y)
        Widgets.SafeSetSize(sp, rowWidth, spH)
        Widgets.SafeShow(sp, true)
        y = y + spH + 8
      end
    end

    local il = ns.Domain and ns.Domain.InstanceLedger
    dungeonSummary = (il and type(il.GetSummarySnapshot) == "function") and il.GetSummarySnapshot() or {
      lockoutState = "UNKNOWN_HISTORY",
      lockoutCapacityLabel = "Observed admissions; remaining capacity unknown",
      claimsExactAccountLockoutCapacity = false,
      observedSessionAdmissions = 0,
      runCount = 0,
      runs = {},
    }
    if not GoldFarmsUI.dungeonPanel then
      local dp = Widgets.CreatePanel(content, "surface.card", "border.subtle")
      if dp then
        dp.headerText = Widgets.SafeCreateFontString(dp, "sectionTitle", "accent.gold")
        dp.statusText = Widgets.SafeCreateFontString(dp, "body", "text.primary")
        dp.bodyText = Widgets.SafeCreateFontString(dp, "dense", "text.secondary")
        for _, fs in ipairs({ dp.headerText, dp.statusText, dp.bodyText }) do
          if fs and type(fs.SetJustifyH) == "function" then
            pcall(fs.SetJustifyH, fs, "LEFT")
          end
        end
      end
      GoldFarmsUI.dungeonPanel = dp
    end
    local dp = GoldFarmsUI.dungeonPanel
    if dp then
      local innerW = math.max(200, rowWidth - 28)
      local fmtC = (ns.Compat and ns.Compat.FormatCopper) or tostring
      local headerStr = "Dungeon Session Ledger  ·  " .. tostring(dungeonSummary.lockoutCapacityLabel or "Observed admissions; remaining capacity unknown")
      local statusStr = string.format(
        "State: %s  ·  Observed session admissions: %d  ·  Recorded runs: %d (never claims exact 5/hr account capacity)",
        tostring(dungeonSummary.lockoutState or "UNKNOWN_HISTORY"),
        tonumber(dungeonSummary.observedSessionAdmissions) or 0,
        tonumber(dungeonSummary.runCount) or 0
      )
      local runLines = {}
      local runs = dungeonSummary.runs or {}
      if #runs == 0 then
        table.insert(runLines, "No dungeon or raid runs observed yet in this ledger.")
        table.insert(runLines, "Reconciles looted coin, unsold attributable loot vendor value (transitions cleanly to realized proceeds on sale), durability-baseline repairs, and active inside vs. full-trip duration.")
      else
        for idx = #runs, math.max(1, #runs - 7), -1 do
          local r = runs[idx]
          table.insert(
            runLines,
            string.format(
              "• [%s] %s (%s) — Active: %ds / Trip: %ds · Coin: %s · Unsold Loot: %s · Realized Sales: %s · Attrib Repairs: %s (Unattrib: %s) · Net: %s",
              tostring(r.runID or idx),
              tostring(r.instanceName or "Instance"),
              tostring(r.copyIdentityCertainty or "OBSERVED_ENTRY"),
              tonumber(r.activeInstanceSeconds) or 0,
              tonumber(r.fullTripSeconds) or 0,
              fmtC(r.reconciledCoinCopper or 0),
              r.unsoldLootVendorComplete == false and "Pending item metadata" or fmtC(r.unsoldLootVendorCopper or 0),
              fmtC(r.realizedLootProceedsCopper or 0),
              fmtC(r.attributableRepairCopper or 0),
              fmtC(r.unattributedRepairCopper or 0),
              fmtC(r.netAfterAttributedRepairsCopper or 0)
            )
          )
        end
      end
      local bodyJoined = table.concat(runLines, "\n")
      if dp.headerText then
        Widgets.SafeClearPoints(dp.headerText)
        Widgets.SafeSetPoint(dp.headerText, "TOPLEFT", dp, "TOPLEFT", 14, -12)
        Theme.ApplyFont(dp.headerText, "sectionTitle", "accent.gold")
      end
      local hH = Theme.MeasureWrappedHeight(dp.headerText, headerStr, innerW, "sectionTitle", 20, 0)
      if dp.statusText then
        Widgets.SafeClearPoints(dp.statusText)
        Widgets.SafeSetPoint(dp.statusText, "TOPLEFT", dp, "TOPLEFT", 14, -(12 + hH + 4))
        Theme.ApplyFont(dp.statusText, "body", "text.primary")
      end
      local sH = Theme.MeasureWrappedHeight(dp.statusText, statusStr, innerW, "body", 18, 0)
      if dp.bodyText then
        Widgets.SafeClearPoints(dp.bodyText)
        Widgets.SafeSetPoint(dp.bodyText, "TOPLEFT", dp, "TOPLEFT", 14, -(12 + hH + 4 + sH + 6))
        Theme.ApplyFont(dp.bodyText, "dense", "text.secondary")
      end
      local bH = Theme.MeasureWrappedHeight(dp.bodyText, bodyJoined, innerW, "dense", 36, 0)
      local dpH = math.max(120, 12 + hH + 4 + sH + 6 + bH + 14)
      Widgets.SafeClearPoints(dp)
      Widgets.SafeSetPoint(dp, "TOPLEFT", content, "TOPLEFT", 0, -y)
      Widgets.SafeSetSize(dp, rowWidth, dpH)
      Widgets.SafeShow(dp, true)
      y = y + dpH + 8
    end
  else
    if GoldFarmsUI.stCoachPanel then
      Widgets.SafeShow(GoldFarmsUI.stCoachPanel, false)
    end
    if GoldFarmsUI.dungeonPanel then
      Widgets.SafeShow(GoldFarmsUI.dungeonPanel, false)
    end
    for _, fvm in ipairs(vm.farms) do
    local card = acquirePoolItem(GoldFarmsUI.cardPool, function()
      return createFarmCard(content)
    end)
    if card then
      -- Clear all pooled button callbacks first so reused cards NEVER retain stale closures (Astra P2-2)
      clearCardCallbacks(card)

      if card.icon then
        card.icon:SetItem(fvm.iconItemID, fvm.title, generation)
      end

      local rightControlsReserve = fvm.isActiveNav and 254 or 148
      local textW = math.max(200, rowWidth - 56 - rightControlsReserve)

      local fullHeading = string.format("%s  ·  %s", fvm.title, fvm.zoneAndLevel)
      if card.titleText then
        Widgets.SafeClearPoints(card.titleText)
        Widgets.SafeSetPoint(card.titleText, "TOPLEFT", card, "TOPLEFT", 54, -10)
        Theme.ApplyFont(card.titleText, "sectionTitle", fvm.isActiveNav and "accent.gold" or "text.primary")
      end
      local tH = Theme.MeasureWrappedHeight(card.titleText, fullHeading, textW, "sectionTitle", 20, 0)

      if card.meta1Text then
        Widgets.SafeClearPoints(card.meta1Text)
        Widgets.SafeSetPoint(card.meta1Text, "TOPLEFT", card, "TOPLEFT", 54, -(10 + tH + 2))
        Theme.ApplyFont(card.meta1Text, "body", "text.secondary")
      end
      local m1H = Theme.MeasureWrappedHeight(card.meta1Text, fvm.metaLine1, textW, "body", 18, 0)

      if card.meta2Text then
        Widgets.SafeClearPoints(card.meta2Text)
        Widgets.SafeSetPoint(card.meta2Text, "TOPLEFT", card, "TOPLEFT", 54, -(10 + tH + 2 + m1H + 2))
        Theme.ApplyFont(card.meta2Text, "dense", "text.muted")
      end
      local m2H = Theme.MeasureWrappedHeight(card.meta2Text, fvm.metaLine2, textW, "dense", 16, 0)

      -- Optional status badges (Active hop / Subcamp eligibility / Experimental / Reservation warning)
      local badgeY = 10 + tH + 2 + m1H + 2 + m2H + 4
      local badgeX = 54
      local hasBadges = false
      local function addCardBadge(txt, tok, glyph, goldOutline)
        local b = acquirePoolItem(GoldFarmsUI.badgePool, function()
          return Widgets.CreateBadge(content)
        end)
        if b then
          if type(b.SetParent) == "function" then pcall(b.SetParent, b, card) end
          local bw = b:Configure(txt, tok, glyph, goldOutline)
          Widgets.SafeClearPoints(b)
          Widgets.SafeSetPoint(b, "TOPLEFT", card, "TOPLEFT", badgeX, -badgeY)
          badgeX = badgeX + bw + 6
          hasBadges = true
        end
      end

      if fvm.isActiveNav and fvm.activeStepSummary then
        addCardBadge("Active · " .. fvm.activeStepSummary, "status.ready", "play", true)
      elseif fvm.isFocused then
        addCardBadge("Selected candidate", "accent.gold", nil, false)
      end
      if fvm.eligibilityBadge and fvm.eligibilityBadge ~= "" then
        local elTok = "text.muted"
        if fvm.eligibilityCode == "ideal" then
          elTok = "status.ready"
        elseif fvm.eligibilityCode == "preview_orange" then
          elTok = "accent.gold"
        elseif fvm.eligibilityCode == "high_resist" or fvm.eligibilityCode == "skull" then
          elTok = "status.danger"
        end
        addCardBadge(fvm.eligibilityBadge, elTok, nil, false)
      end
      if fvm.isExperimental then
        addCardBadge("Experimental (Opt-In)", "status.warning", "warning", false)
      end
      if fvm.hasReservationConflict then
        addCardBadge("Reserved mat guard", "status.warning", "warning", false)
      end

      local collapsedH = math.max(FARM_COLLAPSED_MIN_HEIGHT, 10 + tH + 2 + m1H + 2 + m2H + (hasBadges and 24 or 0) + 10)

      Widgets.SafeSetSolidColor(card.__fhBg, fvm.isActiveNav and "surface.selected" or "surface.card", 1.0)
      Widgets.SetSurfaceBorder(
        card,
        fvm.isActiveNav and "accent.gold" or (fvm.isFocused and "border.default" or "border.subtle"),
        fvm.isActiveNav and 0.90 or 1.0
      )

      -- Right-side action hierarchy:
      -- - Active farm: `Next hop` + `Stop navigation` + chevron
      -- - Selected (non-active) farm: ONLY gold primary `Navigate` + chevron
      -- - All other farms: neutral secondary `Select` + chevron
      local fid = fvm.farmID
      if card.expandBtn then
        card.expandBtn:SetGlyph(fvm.isExpanded and "chevron_down" or "chevron_right", "text.secondary")
        Widgets.SafeClearPoints(card.expandBtn)
        Widgets.SafeSetPoint(card.expandBtn, "TOPRIGHT", card, "TOPRIGHT", -10, -16)
        card.expandBtn:SetOnClick(function()
          GoldFarmsUI.Dispatch("TOGGLE_EXPAND", { farmID = fid })
        end)
        Widgets.SafeShow(card.expandBtn, true)
      end

      if fvm.isActiveNav then
        Widgets.SafeShow(card.primaryNavBtn, false)
        Widgets.SafeShow(card.selectBtn, false)
        if card.stopNavBtn then
          Widgets.SafeClearPoints(card.stopNavBtn)
          Widgets.SafeSetPoint(card.stopNavBtn, "RIGHT", card.expandBtn, "LEFT", -6, 0)
          card.stopNavBtn:SetOnClick(function()
            GoldFarmsUI.Dispatch("STOP_NAVIGATION")
          end)
          Widgets.SafeShow(card.stopNavBtn, true)
        end
        if card.nextHopBtn then
          Widgets.SafeClearPoints(card.nextHopBtn)
          Widgets.SafeSetPoint(card.nextHopBtn, "RIGHT", card.stopNavBtn, "LEFT", -6, 0)
          card.nextHopBtn:SetOnClick(function()
            GoldFarmsUI.Dispatch("NEXT_HOP")
          end)
          Widgets.SafeShow(card.nextHopBtn, true)
        end
      elseif fvm.isFocused then
        Widgets.SafeShow(card.selectBtn, false)
        Widgets.SafeShow(card.nextHopBtn, false)
        Widgets.SafeShow(card.stopNavBtn, false)
        if card.primaryNavBtn then
          card.primaryNavBtn:SetLabel("Navigate")
          Widgets.SafeClearPoints(card.primaryNavBtn)
          Widgets.SafeSetPoint(card.primaryNavBtn, "RIGHT", card.expandBtn, "LEFT", -6, 0)
          card.primaryNavBtn:SetOnClick(function()
            GoldFarmsUI.Dispatch("START_NAVIGATION", { farmID = fid })
          end)
          Widgets.SafeShow(card.primaryNavBtn, true)
          primaryGoldButtonCount = primaryGoldButtonCount + 1
        end
      else
        Widgets.SafeShow(card.primaryNavBtn, false)
        Widgets.SafeShow(card.nextHopBtn, false)
        Widgets.SafeShow(card.stopNavBtn, false)
        if card.selectBtn then
          Widgets.SafeClearPoints(card.selectBtn)
          Widgets.SafeSetPoint(card.selectBtn, "RIGHT", card.expandBtn, "LEFT", -6, 0)
          card.selectBtn:SetOnClick(function()
            GoldFarmsUI.Dispatch("SELECT_FARM", { farmID = fid })
          end)
          Widgets.SafeShow(card.selectBtn, true)
        end
      end

      -- Expanded Details Drawer
      local totalCardH = collapsedH
      if fvm.isExpanded and card.detailBox then
        local hopLines = {}
        for _, h in ipairs(fvm.hops) do
          local prefix = h.isCurrent and "▶ " or "  • "
          table.insert(hopLines, string.format("%sHop %d: %s", prefix, h.index, h.title))
        end
        local detailParts = {
          "Entry & Hops:\n" .. table.concat(hopLines, "\n"),
          "Mage Notes: " .. fvm.magePullNotes,
          "Payout Basis: " .. fvm.payoutBasis,
        }
        if fvm.lootBucketsNote and fvm.lootBucketsNote ~= "" then
          table.insert(detailParts, fvm.lootBucketsNote)
        end
        if fvm.xpBasis and fvm.xpBasis ~= "" then
          table.insert(detailParts, "XP Basis: " .. fvm.xpBasis)
        end
        if (tonumber(fvm.spawnNodeCount) or 0) > 0 then
          table.insert(
            detailParts,
            string.format(
              "Spawn Radar: %d QuestieDB spawn coordinates recorded (verified camp kills ~180s revisit est.; manual skip ~120s).",
              tonumber(fvm.spawnNodeCount) or 0
            )
          )
        end
        for _, w in ipairs(fvm.warnings or {}) do
          table.insert(detailParts, Theme.Colorize("status.warning", w.message))
        end
        local detailJoined = table.concat(detailParts, "\n")
        local innerW = math.max(180, rowWidth - 44)
        if card.detailText then
          Widgets.SafeClearPoints(card.detailText)
          Widgets.SafeSetPoint(card.detailText, "TOPLEFT", card.detailBox, "TOPLEFT", 12, -10)
          Theme.ApplyFont(card.detailText, "dense", "text.secondary")
        end
        local dTextH = Theme.MeasureWrappedHeight(card.detailText, detailJoined, innerW, "dense", 48, 0)
        local dBoxH = dTextH + 44

        Widgets.SafeClearPoints(card.detailBox)
        Widgets.SafeSetPoint(card.detailBox, "TOPLEFT", card, "TOPLEFT", 10, -collapsedH)
        Widgets.SafeSetSize(card.detailBox, rowWidth - 20, dBoxH)

        if card.exportBtn then
          Widgets.SafeClearPoints(card.exportBtn)
          Widgets.SafeSetPoint(card.exportBtn, "BOTTOMRIGHT", card.detailBox, "BOTTOMRIGHT", -10, 8)
          card.exportBtn:SetOnClick(function()
            GoldFarmsUI.Dispatch("EXPORT_RXP", { farmID = fid })
          end)
          Widgets.SafeShow(card.exportBtn, true)
        end
        if card.prevHopBtn then
          Widgets.SafeClearPoints(card.prevHopBtn)
          Widgets.SafeSetPoint(card.prevHopBtn, "BOTTOMLEFT", card.detailBox, "BOTTOMLEFT", 10, 8)
          card.prevHopBtn:SetOnClick(function()
            GoldFarmsUI.Dispatch("PREV_HOP")
          end)
          Widgets.SafeShow(card.prevHopBtn, fvm.isActiveNav)
        end
        if card.reenterBtn then
          Widgets.SafeClearPoints(card.reenterBtn)
          Widgets.SafeSetPoint(card.reenterBtn, "LEFT", card.prevHopBtn, "RIGHT", 6, 0)
          card.reenterBtn:SetOnClick(function()
            GoldFarmsUI.Dispatch("REENTER_ROUTE")
          end)
          Widgets.SafeShow(card.reenterBtn, fvm.isActiveNav)
        end

        Widgets.SafeShow(card.detailBox, true)
        totalCardH = collapsedH + dBoxH + 10
      elseif card.detailBox then
        Widgets.SafeShow(card.detailBox, false)
      end

      Widgets.SafeClearPoints(card)
      Widgets.SafeSetPoint(card, "TOPLEFT", content, "TOPLEFT", 0, -y)
      Widgets.SafeSetSize(card, rowWidth, totalCardH)
      Widgets.SafeShow(card, true)

      table.insert(cardReports, {
        farmID = fid,
        collapsedHeight = collapsedH,
        height = totalCardH,
        width = rowWidth,
        isActiveNav = fvm.isActiveNav,
        isFocused = fvm.isFocused,
        hasNextHopVisible = fvm.isActiveNav,
      })
      y = y + totalCardH + 8
    end
    end
  end

  local totalContentH = math.max(vpH, y + 12)
  local maxScroll = math.max(0, totalContentH - vpH)
  local clampedScroll = math.max(0, math.min(maxScroll, tonumber(uiState.goldView.scrollOffset) or 0))
  uiState.goldView.scrollOffset = clampedScroll
  GoldFarmsUI.viewport:SetDimensions(vw, vpH, totalContentH)
  GoldFarmsUI.viewport:SetScrollOffset(clampedScroll, true)

  local report = {
    isCompact = compact,
    subView = activeSubView,
    subFilter = vm.subFilter,
    viewportWidth = vw,
    viewportHeight = vh,
    rowWidth = rowWidth,
    primaryGoldButtonCount = primaryGoldButtonCount,
    cards = cardReports,
    dungeonSummary = dungeonSummary,
    contentHeight = y,
    maxScrollOffset = maxScroll,
    clampedScrollOffset = clampedScroll,
  }
  GoldFarmsUI.lastLayoutReport = report
  return report
end

function GoldFarmsUI.Refresh()
  GoldFarmsUI.EnsureHost()
  if ns.UI.Workspace and ns.UI.Workspace.IsShown and ns.UI.Workspace.IsShown() then
    local st = ns.State.GetWorkspaceUIState()
    if st.activeTab == "gold" then
      ns.UI.Workspace.Refresh()
    end
  end
  return true
end

function GoldFarmsUI.RefreshIfShown()
  GoldFarmsUI.Refresh()
end

function GoldFarmsUI.Show()
  GoldFarmsUI.EnsureHost()
  if ns.UI.Workspace and ns.UI.Workspace.Show then
    ns.UI.Workspace.Show("gold")
    return true
  end
  return false
end

function GoldFarmsUI.Toggle()
  GoldFarmsUI.EnsureHost()
  if ns.UI.Workspace and ns.UI.Workspace.Toggle then
    ns.UI.Workspace.Toggle("gold")
    return true
  end
  return false
end

if ns.UI.Workspace and ns.UI.Workspace.RegisterTabRenderer then
  ns.UI.Workspace.RegisterTabRenderer("gold", {
    Refresh = function(_, contentWidth, contentHeight, isCompact)
      GoldFarmsUI.RenderInHost(contentWidth, contentHeight, isCompact)
    end,
  })
end

return GoldFarmsUI
