local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.UI = ns.UI or {}

local Theme = ns.UI.Theme
local Widgets = ns.UI.Widgets
local CratesPresenter = ns.UI.CratesPresenter
local Workspace = ns.UI.Workspace

local CratesUI = {}
ns.UI.Crates = CratesUI

CratesUI.frame = nil
CratesUI.hostView = nil
CratesUI.pendingSuggestionPreview = nil
CratesUI.pendingClearConfirm = false
CratesUI.draftState = { byGoalKey = {} }
CratesUI.lastViewModel = nil
CratesUI.lastLayoutReport = nil

-- Pools for zero-leak re-renders
CratesUI.cardPool = {}
CratesUI.optionPool = {}
CratesUI.ingredientRowPool = {}
CratesUI.badgePool = {}

local function ensureDraftEntry(goalKey)
  CratesUI.draftState.byGoalKey = CratesUI.draftState.byGoalKey or {}
  local entry = CratesUI.draftState.byGoalKey[goalKey]
  if not entry then
    entry = {}
    CratesUI.draftState.byGoalKey[goalKey] = entry
  end
  return entry
end

-- ============================================================================
-- Controller: Explicit User Intent Commands Only
-- Drafting/filtering/expanding NEVER mutates domain reservations!
-- ============================================================================

function CratesUI.Dispatch(command, payload)
  payload = type(payload) == "table" and payload or {}
  local uiState = ns.State and ns.State.GetWorkspaceUIState and ns.State.GetWorkspaceUIState()
  local cratesView = uiState and uiState.cratesView

  if command == "SELECT_DRAFT_OPTION" then
    local gk = tostring(payload.goalKey or "")
    if gk ~= "" then
      local d = ensureDraftEntry(gk)
      d.selectedOptionIndex = tonumber(payload.optionIndex) or 1
      CratesUI.RefreshIfShown()
    end
    return true
  elseif command == "SET_DRAFT_QUANTITY" then
    local gk = tostring(payload.goalKey or "")
    if gk ~= "" then
      local d = ensureDraftEntry(gk)
      d.draftQuantity = math.max(1, math.min(999, math.floor(tonumber(payload.quantity) or 1)))
      CratesUI.RefreshIfShown()
    end
    return true
  elseif command == "COMMIT_RESERVATION" then
    local kind = tostring(payload.kind or "crate")
    local itemID = tonumber(payload.itemID)
    local optIdx = tonumber(payload.optionIndex) or 1
    local qty = math.max(1, math.floor(tonumber(payload.quantity) or 1))
    if not itemID then
      return false
    end
    local ok, resOrErr = ns.State.ReserveGoal(kind, itemID, optIdx, qty)
    if ok and resOrErr then
      local d = ensureDraftEntry(resOrErr.goalKey)
      d.selectedOptionIndex = resOrErr.optionIndex
      d.draftQuantity = resOrErr.quantity
      CratesUI.RefreshIfShown()
      return true
    else
      ns.Compat.Print("Reserve failed: " .. tostring(resOrErr))
      return false
    end
  elseif command == "COMPLETE_TURNIN" then
    local kind = tostring(payload.kind or "crate")
    local itemID = tonumber(payload.itemID)
    local count = math.max(1, math.floor(tonumber(payload.count) or 1))
    if not itemID then
      return false
    end
    local ok, rem = ns.State.CompleteGoalTurnIn(kind, itemID, count)
    if ok then
      local gk = ns.State.BuildGoalKey(kind, itemID)
      if (tonumber(rem) or 0) <= 0 then
        CratesUI.draftState.byGoalKey[gk] = nil
      else
        local d = ensureDraftEntry(gk)
        d.draftQuantity = tonumber(rem)
      end
      CratesUI.RefreshIfShown()
      return true
    end
    return false
  elseif command == "UNRESERVE_GOAL" then
    local gk = tostring(payload.goalKey or "")
    if gk ~= "" then
      ns.State.UnreserveGoal(gk)
      CratesUI.draftState.byGoalKey[gk] = nil
      CratesUI.RefreshIfShown()
      return true
    end
    return false
  elseif command == "MOVE_PRIORITY" then
    local gk = tostring(payload.goalKey or "")
    local delta = tonumber(payload.delta) or 0
    if gk ~= "" and delta ~= 0 then
      ns.State.MoveReservationPriority(gk, delta)
      CratesUI.RefreshIfShown()
      return true
    end
    return false
  elseif command == "REDUCE_TO_OWNED" then
    local ok, remOrErr = ns.State.ReduceGoalToObservedOwnership(
      payload.kind,
      payload.itemID,
      payload.charOwned,
      payload.canReduce,
      payload.blockReason
    )
    if ok then
      local gk = ns.State.BuildGoalKey(payload.kind, payload.itemID)
      if (tonumber(remOrErr) or 0) <= 0 then
        CratesUI.draftState.byGoalKey[gk] = nil
      else
        ensureDraftEntry(gk).draftQuantity = tonumber(remOrErr)
      end
      ns.Compat.Print(
        string.format("Reduced plan for %s to observed ownership (%d).", tostring(payload.name or gk), tonumber(remOrErr) or 0)
      )
      CratesUI.RefreshIfShown()
      return true
    else
      ns.Compat.Print("Cannot reduce plan: " .. tostring(remOrErr))
      return false
    end
  elseif command == "TOGGLE_CARD" then
    if cratesView and type(payload.goalKey) == "string" then
      cratesView.expandedByKey[payload.goalKey] = not (payload.currentExpanded == true)
      CratesUI.RefreshIfShown()
    end
    return true
  elseif command == "SET_ALL_EXPANDED" then
    if cratesView and CratesUI.lastViewModel then
      local targetFlag = (payload.expanded == true)
      for _, card in ipairs(CratesUI.lastViewModel.cards or {}) do
        cratesView.expandedByKey[card.goalKey] = targetFlag
      end
      CratesUI.RefreshIfShown()
    end
    return true
  elseif command == "SET_SEARCH" then
    if cratesView then
      cratesView.searchQuery = tostring(payload.query or "")
      cratesView.scrollOffset = 0
      if CratesUI.hostView and CratesUI.hostView.viewport then
        CratesUI.hostView.viewport:SetScrollOffset(0, true)
      end
      CratesUI.RefreshIfShown()
    end
    return true
  elseif command == "SET_SCOPE" then
    local nextScope = (payload.scope == "all") and "all" or "owned_planned"
    if cratesView then
      cratesView.scope = nextScope
      cratesView.scrollOffset = 0
    end
    local db = ns.State and ns.State.GetDB and ns.State.GetDB()
    if db and db.settings then
      db.settings.showOnlyOwnedCrates = (nextScope == "owned_planned")
    end
    if CratesUI.hostView and CratesUI.hostView.viewport then
      CratesUI.hostView.viewport:SetScrollOffset(0, true)
    end
    CratesUI.RefreshIfShown()
    return true
  elseif command == "SET_READY_ONLY" then
    if cratesView then
      cratesView.readyOnly = (payload.readyOnly == true)
      cratesView.scrollOffset = 0
    end
    if CratesUI.hostView and CratesUI.hostView.viewport then
      CratesUI.hostView.viewport:SetScrollOffset(0, true)
    end
    CratesUI.RefreshIfShown()
    return true
  elseif command == "SET_INCLUDE_ALT" then
    if ns.State and ns.State.SetIncludeAltStock then
      ns.State.SetIncludeAltStock(payload.enabled == true)
    end
    CratesUI.RefreshIfShown()
    return true
  elseif command == "SET_ACQUISITION_MODE" then
    if ns.State and ns.State.SetAcquisitionMode then
      ns.State.SetAcquisitionMode(payload.mode == "bags_only" and "bags_only" or "after_bank")
    end
    CratesUI.RefreshIfShown()
    return true
  elseif command == "REQUEST_CLEAR_PLAN" then
    CratesUI.pendingClearConfirm = true
    CratesUI.RefreshIfShown()
    return true
  elseif command == "CANCEL_CLEAR_PLAN" then
    CratesUI.pendingClearConfirm = false
    CratesUI.RefreshIfShown()
    return true
  elseif command == "CONFIRM_CLEAR_PLAN" then
    CratesUI.pendingClearConfirm = false
    CratesUI.pendingSuggestionPreview = nil
    CratesUI.draftState.byGoalKey = {}
    local ok, clearedOrErr = false, nil
    if ns.State and ns.State.ClearAllReservationsWithUndo then
      ok, clearedOrErr = ns.State.ClearAllReservationsWithUndo()
    else
      ok = ns.State.UnreserveGoal("all")
    end
    if ok then
      ns.Compat.Print(
        string.format("Cleared %s reservation(s). Use [•••] -> Undo to restore if needed.", tostring(clearedOrErr or "all"))
      )
    end
    CratesUI.RefreshIfShown()
    return ok
  elseif command == "UNDO_LAST_ACTION" then
    local ok, err = ns.State.UndoLastSuggestion()
    if ok then
      CratesUI.pendingSuggestionPreview = nil
      CratesUI.pendingClearConfirm = false
      CratesUI.draftState.byGoalKey = {}
      ns.Compat.Print("Reverted last plan batch change.")
      CratesUI.RefreshIfShown()
    else
      ns.Compat.Print("Undo unavailable: " .. tostring(err))
    end
    return ok
  elseif command == "COLLECT_BANK" then
    local colState = ns.Providers.Inventory and ns.Providers.Inventory.GetBankCollectionState and ns.Providers.Inventory.GetBankCollectionState()
    if colState and colState.active then
      ns.Providers.Inventory.CancelBankCollection("user_cancelled", "Bank collection stopped by user.")
    else
      ns.Providers.Inventory.StartBankCollection()
    end
    CratesUI.RefreshIfShown()
    return true
  elseif command == "EXPORT_SHOPPING_LIST" then
    local mode = payload.mode or (ns.State and ns.State.GetAcquisitionMode and ns.State.GetAcquisitionMode()) or "after_bank"
    CratesUI.ExportShoppingList(mode)
    CratesUI.RefreshIfShown()
    return true
  end
  return false
end

-- ============================================================================
-- Backward-Compatible Public Action Methods (`Events.lua` / Slash Commands)
-- ============================================================================

function CratesUI.PreviewSuggestReady()
  local preview = ns.Domain.Costs.SuggestReadyTurnIns()
  CratesUI.pendingSuggestionPreview = preview
  CratesUI.pendingClearConfirm = false
  if not preview or (preview.addedGoalCount or 0) == 0 then
    ns.Compat.Print(
      "Suggest Ready: 0 additional owned crates/writs can be filled with 0 purchases from currently unreserved stock."
    )
  else
    ns.Compat.Print(
      string.format(
        "Suggest Ready Preview: +%d goal(s) (%d turn-in(s)) with 0 purchases (%d manual goal(s) preserved; Retrieve Bank: %d). Click 'Apply (+%d)' to commit.",
        preview.addedGoalCount,
        preview.addedTurnInsCount,
        #(preview.preservedGoalKeys or {}),
        preview.totalRetrieveBankUnits or 0,
        preview.addedTurnInsCount
      )
    )
  end
  CratesUI.RefreshIfShown()
  return preview
end

function CratesUI.ApplyPendingSuggestion()
  local preview = CratesUI.pendingSuggestionPreview
  if not preview or #(preview.suggestedReservations or {}) == 0 then
    CratesUI.pendingSuggestionPreview = nil
    CratesUI.RefreshIfShown()
    return
  end
  ns.State.lastUndoReason = "suggest_ready"
  local ok, count = ns.State.ApplySuggestedReservations(preview.suggestedReservations)
  CratesUI.pendingSuggestionPreview = nil
  if ok then
    ns.Compat.Print(
      string.format("Applied %d suggested ready goal(s). Click 'Undo' to revert if needed.", tonumber(count) or 0)
    )
  end
  CratesUI.RefreshIfShown()
end

function CratesUI.ExportShoppingList(mode)
  mode = mode or "after_bank"
  if ns.State and ns.State.SetAcquisitionMode then
    ns.State.SetAcquisitionMode(mode)
  end
  local ordered = ns.State.GetOrderedReservations()
  if #ordered == 0 then
    ns.Compat.Print("No active reservations. Reserve at least one Crate or Writ option first.")
    return
  end

  local plan = ns.Domain.Reservations.BuildShoppingPlan(mode)
  local toBuy = {}
  local totalRetrieve = 0
  for _, item in ipairs(plan.items or {}) do
    totalRetrieve = totalRetrieve + (item.retrieveQty or 0)
    if (item.buyQty or 0) > 0 then
      table.insert(toBuy, item)
    end
  end

  if #toBuy == 0 then
    if mode == "after_bank" and totalRetrieve > 0 then
      ns.Compat.Print(
        string.format(
          "0 materials need to be bought! Retrieve %d reserved material(s) from your bank/alts (or switch to 'Bags only' to buy without retrieving).",
          totalRetrieve
        )
      )
    else
      ns.Compat.Print("All reserved materials are already in your bags!")
    end
    return
  end

  local suffix = (mode == "bags_only") and "Bags Only" or nil
  local listName = ns.Providers.Auctionator.GetDefaultShoppingListName(suffix)
  local ok, countOrErr, createdName, details = ns.Providers.Auctionator.CreateShoppingList(
    listName,
    toBuy,
    { userInitiated = true, returnDetails = true }
  )
  if ok then
    local pendingCount = details and details.pending and #details.pending or 0
    local excludedCount = details and details.excluded and #details.excluded or 0
    if details and not details.isComplete then
      ns.Compat.Print(
        string.format(
          "Exported %d of %d material(s) to Auctionator discovery list '%s' (%d pending client cache — retry in a moment; %d skipped; Retrieve from bank: %d).",
          countOrErr,
          countOrErr + pendingCount + excludedCount,
          tostring(createdName or listName),
          pendingCount,
          excludedCount,
          totalRetrieve
        )
      )
    else
      ns.Compat.Print(
        string.format(
          "Exported %d material(s) to Auctionator discovery list '%s' (Retrieve from bank: %d; verify stack buyouts before buying).",
          countOrErr,
          tostring(createdName or listName),
          totalRetrieve
        )
      )
    end
  else
    ns.Compat.Print("Could not create Auctionator shopping list: " .. tostring(countOrErr))
  end
end

-- ============================================================================
-- Widget Pool Acquirers (Reset strictly before reuse)
-- ============================================================================

local function resetPoolList(pool, usedCount)
  for i = usedCount + 1, #pool do
    Widgets.ResetPooledWidget(pool[i])
  end
end

local function acquireBadge(pool, idx, parent)
  local b = pool[idx]
  if not b then
    b = Widgets.CreateBadge(parent)
    pool[idx] = b
  end
  if b then
    Widgets.ResetPooledWidget(b)
    if type(b.SetParent) == "function" then
      pcall(b.SetParent, b, parent)
    end
    Widgets.SafeShow(b, true)
  end
  return b
end

local function acquireCardWidget(idx, parent)
  local card = CratesUI.cardPool[idx]
  if not card then
    card = Widgets.CreatePanel(parent, "surface.card", "border.subtle")
    if card then
      -- Header click button
      local okHB, hdrBtn = pcall(_G.CreateFrame, "Button", nil, card)
      if okHB and hdrBtn then
        if type(hdrBtn.EnableMouse) == "function" then pcall(hdrBtn.EnableMouse, hdrBtn, true) end
        if type(hdrBtn.RegisterForClicks) == "function" then pcall(hdrBtn.RegisterForClicks, hdrBtn, "LeftButtonUp") end
        hdrBtn.bg = Widgets.SafeCreateTexture(hdrBtn, "BACKGROUND", 1)
        if hdrBtn.bg then
          Widgets.SafeSetAllPoints(hdrBtn.bg, hdrBtn)
          Widgets.SafeSetSolidColor(hdrBtn.bg, "surface.hover", 0.0)
        end
        hdrBtn:SetScript("OnEnter", function(s)
          if s.bg then Widgets.SafeSetSolidColor(s.bg, "surface.hover", 0.55) end
        end)
        hdrBtn:SetScript("OnLeave", function(s)
          if s.bg then Widgets.SafeSetSolidColor(s.bg, "surface.hover", 0.0) end
        end)
        card.headerBtn = hdrBtn
      end

      local hParent = card.headerBtn or card
      card.chevronTex = Widgets.SafeCreateTexture(hParent, "ARTWORK", 2)
      if card.chevronTex then
        Widgets.SafeSetSize(card.chevronTex, 14, 14)
      end
      card.chevronFallback = Widgets.SafeCreateFontString(hParent, "body", "text.secondary")

      card.itemIcon = Widgets.CreateItemIcon(hParent, 30)
      card.titleText = Widgets.SafeCreateFontString(hParent, "sectionTitle", "text.primary")
      if card.titleText and type(card.titleText.SetJustifyH) == "function" then
        pcall(card.titleText.SetJustifyH, card.titleText, "LEFT")
      end
      card.summaryText = Widgets.SafeCreateFontString(hParent, "dense", "text.secondary")
      if card.summaryText and type(card.summaryText.SetJustifyH) == "function" then
        pcall(card.summaryText.SetJustifyH, card.summaryText, "LEFT")
      end

      -- Header right-hand priority & reduce controls (children of card above headerBtn)
      card.prioUpBtn = Widgets.CreateIconButton(card, "chevron_up", "Increase reservation priority", { "Higher-priority goals claim shared materials first." }, 24, 13)
      card.prioDownBtn = Widgets.CreateIconButton(card, "chevron_down", "Decrease reservation priority", { "Moves this goal lower in material allocation order." }, 24, 13)
      card.reduceBtn = Widgets.CreateGhostButton(card, 72, "Own", 24)
      if card.prioUpBtn and card.headerBtn and type(card.prioUpBtn.SetFrameLevel) == "function" and type(card.headerBtn.GetFrameLevel) == "function" then
        local baseLvl = (card.headerBtn:GetFrameLevel() or 10) + 4
        pcall(card.prioUpBtn.SetFrameLevel, card.prioUpBtn, baseLvl)
        if card.prioDownBtn then pcall(card.prioDownBtn.SetFrameLevel, card.prioDownBtn, baseLvl) end
        if card.reduceBtn then pcall(card.reduceBtn.SetFrameLevel, card.reduceBtn, baseLvl) end
      end

      -- Expanded table header
      card.tableHeader = Widgets.CreatePanel(card, "surface.elevated", nil)
      if card.tableHeader then
        card.thMat = Widgets.SafeCreateFontString(card.tableHeader, "dense", "text.muted")
        card.thBags = Widgets.SafeCreateFontString(card.tableHeader, "dense", "text.muted")
        card.thBank = Widgets.SafeCreateFontString(card.tableHeader, "dense", "text.muted")
        card.thBuy = Widgets.SafeCreateFontString(card.tableHeader, "dense", "text.muted")
        card.thCost = Widgets.SafeCreateFontString(card.tableHeader, "dense", "text.muted")
        card.thPlan = Widgets.SafeCreateFontString(card.tableHeader, "dense", "text.muted")
        if card.thMat and card.thMat.SetJustifyH then pcall(card.thMat.SetJustifyH, card.thMat, "LEFT") end
        if card.thBags and card.thBags.SetJustifyH then pcall(card.thBags.SetJustifyH, card.thBags, "RIGHT") end
        if card.thBank and card.thBank.SetJustifyH then pcall(card.thBank.SetJustifyH, card.thBank, "RIGHT") end
        if card.thBuy and card.thBuy.SetJustifyH then pcall(card.thBuy.SetJustifyH, card.thBuy, "RIGHT") end
        if card.thCost and card.thCost.SetJustifyH then pcall(card.thCost.SetJustifyH, card.thCost, "RIGHT") end
        if card.thPlan and card.thPlan.SetJustifyH then pcall(card.thPlan.SetJustifyH, card.thPlan, "RIGHT") end
      end

      card.writNotice = Widgets.SafeCreateFontString(card, "dense", "status.warning")
      if card.writNotice and type(card.writNotice.SetJustifyH) == "function" then
        pcall(card.writNotice.SetJustifyH, card.writNotice, "LEFT")
      end
    end
    CratesUI.cardPool[idx] = card
  end

  if card then
    if type(card.SetParent) == "function" then
      pcall(card.SetParent, card, parent)
    end
    Widgets.SafeShow(card, true)
  end
  return card
end

local function acquireOptionWidget(idx, parent)
  local optW = CratesUI.optionPool[idx]
  if not optW then
    optW = Widgets.CreatePanel(parent, "surface.card", "border.subtle")
    if optW then
      optW.leftAccent = Widgets.SafeCreateTexture(optW, "OVERLAY", 2)
      if optW.leftAccent then
        Widgets.SafeSetPoint(optW.leftAccent, "TOPLEFT", optW, "TOPLEFT", 0, 0)
        Widgets.SafeSetPoint(optW.leftAccent, "BOTTOMLEFT", optW, "BOTTOMLEFT", 0, 0)
        Widgets.SafeSetWidth(optW.leftAccent, 3)
      end

      optW.qtyEditor = Widgets.CreateQuantityEditor(optW)
      optW.chooseBtn = Widgets.CreateSecondaryButton(optW, 88, "Choose", 26)
      optW.primaryBtn = Widgets.CreatePrimaryButton(optW, 112, "Reserve", 26)
      optW.doneBtn = Widgets.CreateGhostButton(optW, 64, "Done -1", 24)
      optW.removeBtn = Widgets.CreateGhostButton(optW, 64, "Remove", 24)

      optW.footerDivider = Widgets.SafeCreateTexture(optW, "BORDER", 1)
      if optW.footerDivider then
        Widgets.SafeSetHeight(optW.footerDivider, 1)
        Widgets.SafeSetSolidColor(optW.footerDivider, "border.subtle", 0.65)
      end

      optW.footerText = Widgets.SafeCreateFontString(optW, "dense", "text.secondary")
      if optW.footerText and type(optW.footerText.SetJustifyH) == "function" then
        pcall(optW.footerText.SetJustifyH, optW.footerText, "LEFT")
      end
    end
    CratesUI.optionPool[idx] = optW
  end

  if optW then
    if type(optW.SetParent) == "function" then
      pcall(optW.SetParent, optW, parent)
    end
    Widgets.SafeShow(optW, true)
  end
  return optW
end

local function acquireIngredientRowWidget(idx, parent)
  local row = CratesUI.ingredientRowPool[idx]
  if not row then
    local okR, r = pcall(_G.CreateFrame, "Frame", nil, parent)
    if okR and r then
      r.icon = Widgets.CreateItemIcon(r, 28)
      r.matText = Widgets.SafeCreateFontString(r, "body", "text.primary")
      r.bagsText = Widgets.SafeCreateFontString(r, "body", "text.secondary")
      r.bankText = Widgets.SafeCreateFontString(r, "body", "text.secondary")
      r.buyText = Widgets.SafeCreateFontString(r, "body", "text.primary")
      r.costText = Widgets.SafeCreateFontString(r, "body", "text.primary")

      if r.matText and r.matText.SetJustifyH then pcall(r.matText.SetJustifyH, r.matText, "LEFT") end
      if r.bagsText and r.bagsText.SetJustifyH then pcall(r.bagsText.SetJustifyH, r.bagsText, "RIGHT") end
      if r.bankText and r.bankText.SetJustifyH then pcall(r.bankText.SetJustifyH, r.bankText, "RIGHT") end
      if r.buyText and r.buyText.SetJustifyH then pcall(r.buyText.SetJustifyH, r.buyText, "RIGHT") end
      if r.costText and r.costText.SetJustifyH then pcall(r.costText.SetJustifyH, r.costText, "RIGHT") end
      row = r
      CratesUI.ingredientRowPool[idx] = row
    end
  end

  if row then
    if type(row.SetParent) == "function" then
      pcall(row.SetParent, row, parent)
    end
    Widgets.SafeShow(row, true)
  end
  return row
end

-- ============================================================================
-- Column Geometry Solver (Exact Astra Standard `912` + Dedicated Compact `<900`)
-- ============================================================================

function CratesUI.ComputeOptionColumns(rowWidth, isCompact)
  local w = math.max(520, tonumber(rowWidth) or 912)
  if isCompact then
    -- Dedicated Compact Layout (<900 window width; e.g. 760 window -> 712 rowWidth):
    -- Ingredient cells span full width; selection/plan controls occupy dedicated bottom band.
    local costW = 112
    local costX = w - 12 - costW
    local buyW = 64
    local buyX = costX - 8 - buyW
    local bankW = 72
    local bankX = buyX - 8 - bankW
    local bagsW = 64
    local bagsX = bankX - 8 - bagsW
    local iconX = 12
    local iconW = 28
    local matX = 48
    local matW = math.max(140, bagsX - 8 - matX)
    return {
      isCompact = true,
      rowWidth = w,
      icon = { x = iconX, w = iconW },
      mat = { x = matX, w = matW },
      bags = { x = bagsX, w = bagsW },
      bank = { x = bankX, w = bankW },
      buy = { x = buyX, w = buyW },
      cost = { x = costX, w = costW },
      plan = nil,
    }
  end

  -- Standard Layout (>=900 window width; at 960 default, rowWidth == 912 and extraW == 0):
  -- Exact Astra Section 4 column X/W coordinates!
  local extraW = math.max(0, w - 912)
  return {
    isCompact = false,
    rowWidth = w,
    icon = { x = 12, w = 28 },
    mat = { x = 48, w = 248 + extraW },
    bags = { x = 304 + extraW, w = 64 },
    bank = { x = 376 + extraW, w = 72 },
    buy = { x = 456 + extraW, w = 64 },
    cost = { x = 528 + extraW, w = 112 },
    plan = { x = 648 + extraW, w = 252 },
  }
end

-- ============================================================================
-- Host View Construction inside `Workspace` (`tabHosts.crates`)
-- ============================================================================

local function createOverflowMenu(parent)
  local menu = Widgets.CreatePanel(parent, "surface.elevated", "border.default")
  if not menu then
    return nil
  end
  Widgets.SafeSetSize(menu, 214, 108)
  if type(menu.SetFrameLevel) == "function" and type(parent.GetFrameLevel) == "function" then
    pcall(menu.SetFrameLevel, menu, (parent:GetFrameLevel() or 10) + 25)
  end
  if type(menu.EnableMouse) == "function" then pcall(menu.EnableMouse, menu, true) end

  menu.undoBtn = Widgets.CreateGhostButton(menu, 198, "Undo last batch", 28)
  if menu.undoBtn then
    Widgets.SafeSetPoint(menu.undoBtn, "TOPLEFT", menu, "TOPLEFT", 8, -8)
    menu.undoBtn:SetOnClick(function()
      Widgets.SafeShow(menu, false)
      CratesUI.Dispatch("UNDO_LAST_ACTION")
    end)
  end

  menu.collapseBtn = Widgets.CreateGhostButton(menu, 198, "Collapse all cards", 28)
  if menu.collapseBtn then
    Widgets.SafeSetPoint(menu.collapseBtn, "TOPLEFT", menu, "TOPLEFT", 8, -40)
    menu.collapseBtn:SetOnClick(function()
      Widgets.SafeShow(menu, false)
      CratesUI.Dispatch("SET_ALL_EXPANDED", { expanded = false })
    end)
  end

  menu.clearBtn = Widgets.CreateGhostButton(menu, 198, "Clear plan…", 28)
  if menu.clearBtn then
    Widgets.SafeSetPoint(menu.clearBtn, "TOPLEFT", menu, "TOPLEFT", 8, -72)
    menu.clearBtn:SetOnClick(function()
      Widgets.SafeShow(menu, false)
      CratesUI.Dispatch("REQUEST_CLEAR_PLAN")
    end)
  end

  Widgets.SafeShow(menu, false)
  return menu
end

function CratesUI.EnsureInitialized()
  local wsFrame = Workspace.EnsureCreated()
  if not wsFrame then
    return nil
  end
  CratesUI.frame = wsFrame
  if CratesUI.hostView then
    return CratesUI.hostView
  end

  local host = wsFrame.tabHosts and wsFrame.tabHosts.crates
  if not host then
    return nil
  end

  local pad = Theme.METRICS.workspacePadding
  local hv = { host = host }

  -- 1. Summary KPI Strip (Y = 0..60 inside host == Y = 80..140 of window)
  hv.kpiStrip = Widgets.CreatePanel(host, "surface.window", nil)
  if hv.kpiStrip then
    Widgets.SafeSetPoint(hv.kpiStrip, "TOPLEFT", host, "TOPLEFT", pad, 0)
    Widgets.SafeSetPoint(hv.kpiStrip, "TOPRIGHT", host, "TOPRIGHT", -pad, 0)
    Widgets.SafeSetHeight(hv.kpiStrip, Theme.METRICS.summaryHeight)
    local div = Widgets.SafeCreateTexture(hv.kpiStrip, "BORDER", 1)
    if div then
      Widgets.SafeSetPoint(div, "BOTTOMLEFT", hv.kpiStrip, "BOTTOMLEFT", 0, 0)
      Widgets.SafeSetPoint(div, "BOTTOMRIGHT", hv.kpiStrip, "BOTTOMRIGHT", 0, 0)
      Widgets.SafeSetHeight(div, 1)
      Widgets.SafeSetSolidColor(div, "border.subtle", 1.0)
    end
  end

  hv.kpis = {}
  for i = 1, 4 do
    hv.kpis[i] = Widgets.CreateKPI(hv.kpiStrip or host, 210)
  end

  -- 2. Search & Filter Bar (Y = -60..-100 inside host == Y = 140..180 of window)
  hv.filterBar = Widgets.CreatePanel(host, "surface.window", nil)
  if hv.filterBar then
    Widgets.SafeSetPoint(hv.filterBar, "TOPLEFT", host, "TOPLEFT", pad, -Theme.METRICS.summaryHeight)
    Widgets.SafeSetPoint(hv.filterBar, "TOPRIGHT", host, "TOPRIGHT", -pad, -Theme.METRICS.summaryHeight)
    Widgets.SafeSetHeight(hv.filterBar, Theme.METRICS.filterBarHeight)
  end

  local fParent = hv.filterBar or host
  hv.searchBox = Widgets.CreateSearchBox(fParent, 184, 28, "Search crates or mats…", function(q)
    CratesUI.Dispatch("SET_SEARCH", { query = q })
  end)
  if hv.searchBox then
    Widgets.SafeSetPoint(hv.searchBox, "LEFT", fParent, "LEFT", 0, 0)
  end

  hv.scopeSegment = Widgets.CreateSegmentedFilter(fParent, {
    {
      key = "owned_planned",
      label = "Owned & planned",
      width = 122,
      tooltipTitle = "Owned & Planned",
      tooltipLines = { "Shows only Waylaid Crates & Writs you currently own in bags/bank or have reserved." },
    },
    {
      key = "all",
      label = "All",
      width = 64,
      tooltipTitle = "All Compiled Crates",
      tooltipLines = { "Browse all 30 compiled Waylaid Crates even when 0 are currently owned." },
    },
  }, function(selKey)
    CratesUI.Dispatch("SET_SCOPE", { scope = selKey })
  end)
  if hv.scopeSegment then
    Widgets.SafeSetPoint(hv.scopeSegment, "LEFT", fParent, "LEFT", 192, 0)
  end

  hv.readyCheck = Widgets.CreateCheckbox(
    fParent,
    "Ready",
    "Ready Only",
    { "Filter to targets that can be filled with 0 Auction House purchases right now." },
    function(checked)
      CratesUI.Dispatch("SET_READY_ONLY", { readyOnly = checked })
    end
  )
  if hv.readyCheck then
    Widgets.SafeSetPoint(hv.readyCheck, "LEFT", fParent, "LEFT", 394, 0)
  end

  hv.altCheck = Widgets.CreateCheckbox(
    fParent,
    "Include alt stock",
    "Include Alt Material Stock (Planning Only)",
    {
      "Counts uncommitted materials seen on same-realm alts via BagBrother/Syndicator.",
      "Planning estimate only — alt items are NOT immediately retrievable at your character bank.",
    },
    function(checked)
      CratesUI.Dispatch("SET_INCLUDE_ALT", { enabled = checked })
    end
  )
  if hv.altCheck then
    Widgets.SafeSetPoint(hv.altCheck, "LEFT", fParent, "LEFT", 472, 0)
  end

  hv.expandAllBtn = Widgets.CreateGhostButton(fParent, 104, "Expand all", 26)
  if hv.expandAllBtn then
    Widgets.SafeSetPoint(hv.expandAllBtn, "RIGHT", fParent, "RIGHT", 0, 0)
  end

  -- 3. Scroll Viewport (Y = -108 inside host == Y = 188 of window; default H = 396)
  hv.viewport = Widgets.CreateScrollViewport(host, function(newOffset)
    local st = ns.State and ns.State.GetWorkspaceUIState and ns.State.GetWorkspaceUIState()
    if st and st.cratesView then
      st.cratesView.scrollOffset = newOffset
    end
  end)
  if hv.viewport then
    Widgets.SafeSetPoint(hv.viewport, "TOPLEFT", host, "TOPLEFT", pad, -(Theme.METRICS.summaryHeight + Theme.METRICS.filterBarHeight + 8))
  end

  local scrollContent = (hv.viewport and hv.viewport.content) or host
  hv.suggestionNotice = Widgets.CreateInlineNotice(scrollContent)
  hv.clearConfirmNotice = Widgets.CreateInlineNotice(scrollContent)
  hv.altNotice = Widgets.CreateInlineNotice(scrollContent)
  hv.emptyStatePanel = Widgets.CreatePanel(scrollContent, "surface.card", "border.subtle")
  if hv.emptyStatePanel then
    hv.emptyTitle = Widgets.SafeCreateFontString(hv.emptyStatePanel, "sectionTitle", "text.primary")
    hv.emptySub = Widgets.SafeCreateFontString(hv.emptyStatePanel, "body", "text.secondary")
    hv.emptyBtn = Widgets.CreateSecondaryButton(hv.emptyStatePanel, 168, "Browse All Crates", 28)
    if hv.emptyTitle then
      Widgets.SafeSetPoint(hv.emptyTitle, "TOPLEFT", hv.emptyStatePanel, "TOPLEFT", 16, -16)
    end
    if hv.emptySub then
      Widgets.SafeSetPoint(hv.emptySub, "TOPLEFT", hv.emptyStatePanel, "TOPLEFT", 16, -42)
    end
    if hv.emptyBtn then
      Widgets.SafeSetPoint(hv.emptyBtn, "TOPLEFT", hv.emptyStatePanel, "TOPLEFT", 16, -74)
    end
    Widgets.SafeShow(hv.emptyStatePanel, false)
  end

  -- 4. Contextual Bottom Action Bar (BOTTOMLEFT 16, 16; H = 32 -> Y = 592..624 at 640 window height)
  hv.actionBar = Widgets.CreatePanel(host, "surface.window", nil)
  if hv.actionBar then
    Widgets.SafeSetPoint(hv.actionBar, "BOTTOMLEFT", host, "BOTTOMLEFT", pad, pad)
    Widgets.SafeSetPoint(hv.actionBar, "BOTTOMRIGHT", host, "BOTTOMRIGHT", -pad, pad)
    Widgets.SafeSetHeight(hv.actionBar, Theme.METRICS.actionBarHeight)
  end

  local aParent = hv.actionBar or host
  hv.collectBtn = Widgets.CreateSecondaryButton(aParent, 144, "Collect from bank", 28)
  if hv.collectBtn then
    Widgets.SafeSetPoint(hv.collectBtn, "LEFT", aParent, "LEFT", 0, 0)
    hv.collectBtn:SetOnClick(function()
      CratesUI.Dispatch("COLLECT_BANK")
    end)
  end

  hv.reviewReadyBtn = Widgets.CreateSecondaryButton(aParent, 172, "Review ready options", 28)
  if hv.reviewReadyBtn then
    Widgets.SafeSetPoint(hv.reviewReadyBtn, "LEFT", hv.collectBtn, "RIGHT", 8, 0)
    Widgets.BindTooltip(
      hv.reviewReadyBtn,
      "Review Ready Options",
      { "Previews 0-purchase reservations for owned crates/writs without overwriting your manual plan." }
    )
    hv.reviewReadyBtn:SetOnClick(function()
      CratesUI.PreviewSuggestReady()
    end)
  end

  hv.moreBtn = Widgets.CreateIconButton(
    aParent,
    "more",
    "Plan Actions",
    { "Undo batch changes, collapse cards, or clear your reservation plan." },
    28,
    15
  )
  if hv.moreBtn then
    Widgets.SafeSetPoint(hv.moreBtn, "RIGHT", aParent, "RIGHT", 0, 0)
  end

  hv.exportBtn = Widgets.CreatePrimaryButton(aParent, 156, "Export shopping list", 28)
  if hv.exportBtn then
    Widgets.SafeSetPoint(hv.exportBtn, "RIGHT", hv.moreBtn, "LEFT", -8, 0)
    hv.exportBtn:SetOnClick(function()
      CratesUI.Dispatch("EXPORT_SHOPPING_LIST")
    end)
  end

  hv.modeSegment = Widgets.CreateSegmentedFilter(aParent, {
    {
      key = "after_bank",
      label = "Use bank",
      width = 82,
      tooltipTitle = "Use Bank Stock",
      tooltipLines = { "Subtracts materials in your character bags and bank before exporting deficits to Auctionator." },
    },
    {
      key = "bags_only",
      label = "Bags only",
      width = 82,
      tooltipTitle = "Bags Only Mode",
      tooltipLines = { "Buys missing materials based purely on current bags (skips bank/alt retrieval)." },
    },
  }, function(selMode)
    CratesUI.Dispatch("SET_ACQUISITION_MODE", { mode = selMode })
  end)
  if hv.modeSegment then
    Widgets.SafeSetPoint(hv.modeSegment, "RIGHT", hv.exportBtn, "LEFT", -8, 0)
  end

  hv.overflowMenu = createOverflowMenu(host)
  if hv.overflowMenu and hv.moreBtn then
    Widgets.SafeSetPoint(hv.overflowMenu, "BOTTOMRIGHT", hv.moreBtn, "TOPRIGHT", 0, 6)
    hv.moreBtn:SetOnClick(function()
      local shown = (type(hv.overflowMenu.IsShown) == "function" and hv.overflowMenu:IsShown()) or false
      Widgets.SafeShow(hv.overflowMenu, not shown)
    end)
  end

  CratesUI.hostView = hv
  Workspace.RegisterTabRenderer("crates", {
    Refresh = function(_, contentWidth, contentHeight, isCompact)
      CratesUI.RenderInHost(contentWidth, contentHeight, isCompact)
    end,
  })
  return hv
end

-- ============================================================================
-- View Renderer: Measured Heights + Zero-Overlap Layout Report
-- ============================================================================

function CratesUI.RenderViewModel(viewModel, contentWidth, contentHeight, isCompact)
  local hv = CratesUI.EnsureInitialized()
  if not hv or not viewModel then
    return nil
  end

  local generation = Widgets.BumpGeneration()
  local cw = math.max(Theme.METRICS.workspaceMinWidth - 32, tonumber(contentWidth) or 928)
  local ch = math.max(Theme.METRICS.workspaceMinHeight - 80, tonumber(contentHeight) or 560)
  local viewportH = math.max(160, ch - Theme.METRICS.summaryHeight - Theme.METRICS.filterBarHeight - 8 - Theme.METRICS.actionBarHeight - 24)
  local rowWidth = cw - Theme.METRICS.scrollbarLaneWidth
  local cols = CratesUI.ComputeOptionColumns(rowWidth, isCompact == true)

  local layoutReport = {
    windowContentWidth = cw,
    windowContentHeight = ch,
    viewportWidth = cw,
    viewportHeight = viewportH,
    rowWidth = rowWidth,
    isCompact = (cols.isCompact == true),
    textScale = Theme.GetTextScale(),
    columns = cols,
    cards = {},
  }

  -- 1. Render 4 KPIs
  local kpiGap = 12
  local kpiW = math.floor((cw - (kpiGap * 3)) / 4)
  for i = 1, 4 do
    local kw = hv.kpis[i]
    local kd = viewModel.kpis[i]
    if kw and kd then
      Widgets.SafeClearPoints(kw)
      Widgets.SafeSetPoint(kw, "TOPLEFT", hv.kpiStrip, "TOPLEFT", (i - 1) * (kpiW + kpiGap), -4)
      Widgets.SafeSetSize(kw, kpiW, 52)
      kw:SetKPI(kd.value, kd.label, kd.sub, kd.colorToken, kd.tooltipTitle, kd.tooltipLines)
    end
  end

  -- 2. Sync Filter Bar
  if hv.searchBox and hv.searchBox:GetQuery() ~= viewModel.filters.searchQuery then
    hv.searchBox:SetQuery(viewModel.filters.searchQuery, false)
  end
  if hv.scopeSegment then
    hv.scopeSegment:SetSelected(viewModel.filters.scope)
  end
  if hv.readyCheck then
    hv.readyCheck:SetChecked(viewModel.filters.readyOnly == true)
  end
  if hv.altCheck then
    hv.altCheck:SetChecked(viewModel.filters.includeAltStock == true)
  end
  if hv.expandAllBtn then
    local anyCollapsed = false
    for _, c in ipairs(viewModel.cards or {}) do
      if not c.isExpanded then
        anyCollapsed = true
        break
      end
    end
    hv.expandAllBtn:SetLabel(anyCollapsed and "Expand all" or "Collapse all")
    hv.expandAllBtn:SetButtonEnabled(#(viewModel.cards or {}) > 0)
    hv.expandAllBtn:SetOnClick(function()
      CratesUI.Dispatch("SET_ALL_EXPANDED", { expanded = anyCollapsed })
    end)
  end

  -- 3. Sync Contextual Bottom Action Bar
  local ab = viewModel.actionBar
  if hv.collectBtn then
    hv.collectBtn:SetLabel(ab.collectLabel)
    hv.collectBtn:SetButtonEnabled(ab.collectEnabled)
    Widgets.BindTooltip(hv.collectBtn, "Withdraw from Character Bank", ab.collectTooltipLines)
  end
  if hv.modeSegment then
    hv.modeSegment:SetSelected(ab.acquisitionMode)
  end
  if hv.exportBtn then
    local expLbl = (ab.exportBuyItemsCount > 0)
      and string.format("Export list (%d)", ab.exportBuyItemsCount)
      or "Export shopping list"
    hv.exportBtn:SetLabel(expLbl)
    hv.exportBtn:SetButtonEnabled(ab.exportEnabled)
    Widgets.BindTooltip(
      hv.exportBtn,
      "Export Auctionator Shopping List",
      {
        ab.exportEnabled
          and string.format("Exports %d missing material(s) to Auctionator (%s).", ab.exportBuyItemsCount, ab.acquisitionMode == "bags_only" and "Bags only" or "Use bank stock")
          or "Reserve at least one crate or writ option first to build a shopping list.",
      }
    )
  end
  if hv.overflowMenu then
    if hv.overflowMenu.undoBtn then
      hv.overflowMenu.undoBtn:SetButtonEnabled(ab.canUndo == true)
      hv.overflowMenu.undoBtn:SetLabel(ab.lastUndoReason == "clear_all" and "Undo clear plan" or "Undo ready batch")
    end
    if hv.overflowMenu.clearBtn then
      hv.overflowMenu.clearBtn:SetButtonEnabled(ab.canClearAll == true)
    end
  end

  -- 4. Scroll Content Layout (Notices -> Cards / Empty State)
  local scrollContent = (hv.viewport and hv.viewport.content) or hv.host
  local yCursor = 0

  -- 4a. Inline Confirmation Notice for Clear Plan
  if CratesUI.pendingClearConfirm and hv.clearConfirmNotice then
    Widgets.SafeClearPoints(hv.clearConfirmNotice)
    Widgets.SafeSetPoint(hv.clearConfirmNotice, "TOPLEFT", scrollContent, "TOPLEFT", 0, -yCursor)
    local nh = hv.clearConfirmNotice:Configure(rowWidth, {
      statusToken = "status.danger",
      glyph = "warning",
      message = string.format(
        "Clear all %d active reservation goal(s) (%d planned turn-ins)? You can undo immediately from [•••].",
        viewModel.totalReservedGoals or 0,
        viewModel.totalPlannedTurnIns or 0
      ),
      actionLabel = "Clear plan",
      onAction = function()
        CratesUI.Dispatch("CONFIRM_CLEAR_PLAN")
      end,
      secondaryLabel = "Cancel",
      onSecondary = function()
        CratesUI.Dispatch("CANCEL_CLEAR_PLAN")
      end,
    })
    yCursor = yCursor + nh + 8
  elseif hv.clearConfirmNotice then
    Widgets.SafeShow(hv.clearConfirmNotice, false)
  end

  -- 4b. Inline Suggestion Preview Notice (`Review ready options`)
  local preview = CratesUI.pendingSuggestionPreview
  if preview and hv.suggestionNotice then
    Widgets.SafeClearPoints(hv.suggestionNotice)
    Widgets.SafeSetPoint(hv.suggestionNotice, "TOPLEFT", scrollContent, "TOPLEFT", 0, -yCursor)
    if (preview.addedGoalCount or 0) > 0 then
      local names = {}
      for _, sr in ipairs(preview.suggestedReservations or {}) do
        table.insert(names, string.format("%s ×%d", tostring(sr.targetName), tonumber(sr.quantity) or 1))
      end
      local nh = hv.suggestionNotice:Configure(rowWidth, {
        statusToken = "status.ready",
        glyph = "check",
        message = string.format(
          "Ready preview: +%d goal(s) (%d turn-in(s), 0 purchases, %d bank pull): %s",
          preview.addedGoalCount,
          preview.addedTurnInsCount,
          preview.totalRetrieveBankUnits or 0,
          table.concat(names, " · ")
        ),
        actionLabel = string.format("Apply (+%d)", preview.addedTurnInsCount or preview.addedGoalCount),
        onAction = function()
          CratesUI.ApplyPendingSuggestion()
        end,
        secondaryLabel = "Dismiss",
        onSecondary = function()
          CratesUI.pendingSuggestionPreview = nil
          CratesUI.RefreshIfShown()
        end,
      })
      yCursor = yCursor + nh + 8
    else
      local nh = hv.suggestionNotice:Configure(rowWidth, {
        statusToken = "text.secondary",
        glyph = "info",
        message = "0 additional owned crates or writs can be filled with 0 purchases from currently unreserved stock.",
        secondaryLabel = "Dismiss",
        onSecondary = function()
          CratesUI.pendingSuggestionPreview = nil
          CratesUI.RefreshIfShown()
        end,
      })
      yCursor = yCursor + nh + 8
    end
  elseif hv.suggestionNotice then
    Widgets.SafeShow(hv.suggestionNotice, false)
  end

  -- 4c. Alt Stock Planning Notice
  if viewModel.altStockNotice and hv.altNotice then
    Widgets.SafeClearPoints(hv.altNotice)
    Widgets.SafeSetPoint(hv.altNotice, "TOPLEFT", scrollContent, "TOPLEFT", 0, -yCursor)
    local nh = hv.altNotice:Configure(rowWidth, {
      statusToken = "status.bank",
      glyph = "info",
      message = viewModel.altStockNotice,
    })
    yCursor = yCursor + nh + 8
  elseif hv.altNotice then
    Widgets.SafeShow(hv.altNotice, false)
  end

  local usedCards = 0
  local usedOptions = 0
  local usedIngredients = 0
  local usedBadges = 0

  -- 4d. Empty State vs Crate/Writ Cards
  if #(viewModel.cards or {}) == 0 then
    if hv.emptyStatePanel then
      Widgets.SafeClearPoints(hv.emptyStatePanel)
      Widgets.SafeSetPoint(hv.emptyStatePanel, "TOPLEFT", scrollContent, "TOPLEFT", 0, -yCursor)
      Widgets.SafeSetSize(hv.emptyStatePanel, rowWidth, 118)
      if hv.emptyTitle and type(hv.emptyTitle.SetText) == "function" then
        Theme.ApplyFont(hv.emptyTitle, "sectionTitle", "text.primary")
        hv.emptyTitle:SetText(
          viewModel.filters.searchQuery ~= ""
            and "No crates or materials match your search"
            or (viewModel.filters.readyOnly and "No owned crates are ready right now" or "No Waylaid Crates or Writs in bags or bank")
        )
      end
      if hv.emptySub and type(hv.emptySub.SetText) == "function" then
        Theme.ApplyFont(hv.emptySub, "body", "text.secondary")
        hv.emptySub:SetText(
          viewModel.filters.scope == "owned_planned"
            and "Switch the scope filter to 'All' to browse and plan any of the 30 compiled Waylaid Crates."
            or "Try clearing your search query or disabling the 'Ready' filter."
        )
      end
      if hv.emptyBtn then
        if viewModel.filters.scope == "owned_planned" then
          hv.emptyBtn:SetLabel("Show All Crates")
          hv.emptyBtn:SetOnClick(function()
            CratesUI.Dispatch("SET_SCOPE", { scope = "all" })
          end)
        else
          hv.emptyBtn:SetLabel("Reset Filters")
          hv.emptyBtn:SetOnClick(function()
            if hv.searchBox then hv.searchBox:SetQuery("", false) end
            local st = ns.State.GetWorkspaceUIState()
            st.cratesView.searchQuery = ""
            st.cratesView.readyOnly = false
            CratesUI.RefreshIfShown()
          end)
        end
        Widgets.SafeShow(hv.emptyBtn, true)
      end
      Widgets.SafeShow(hv.emptyStatePanel, true)
      yCursor = yCursor + 126
    end
  elseif hv.emptyStatePanel then
    Widgets.SafeShow(hv.emptyStatePanel, false)
  end

  for _, cardVM in ipairs(viewModel.cards or {}) do
    usedCards = usedCards + 1
    local cardW = acquireCardWidget(usedCards, scrollContent)
    if cardW then
      Widgets.SafeClearPoints(cardW)
      Widgets.SafeSetPoint(cardW, "TOPLEFT", scrollContent, "TOPLEFT", 0, -yCursor)
      Widgets.ApplySurface(
        cardW,
        cardVM.isReserved and "surface.reserved" or "surface.card",
        cardVM.isReserved and "status.reserved" or "border.subtle",
        cardVM.isReserved and 0.65 or 1.0
      )

      -- Header Right Controls & Badges (layout right-to-left so header text knows exact available width)
      local rightCursor = 12
      if cardVM.isReserved then
        if cardW.prioDownBtn then
          Widgets.SafeClearPoints(cardW.prioDownBtn)
          Widgets.SafeSetPoint(cardW.prioDownBtn, "TOPRIGHT", cardW, "TOPRIGHT", -rightCursor, -16)
          cardW.prioDownBtn:SetButtonEnabled(cardVM.canMovePriorityDown)
          local capGK = cardVM.goalKey
          cardW.prioDownBtn:SetOnClick(function()
            CratesUI.Dispatch("MOVE_PRIORITY", { goalKey = capGK, delta = 1 })
          end)
          Widgets.SafeShow(cardW.prioDownBtn, true)
          rightCursor = rightCursor + 26
        end
        if cardW.prioUpBtn then
          Widgets.SafeClearPoints(cardW.prioUpBtn)
          Widgets.SafeSetPoint(cardW.prioUpBtn, "TOPRIGHT", cardW, "TOPRIGHT", -rightCursor, -16)
          cardW.prioUpBtn:SetButtonEnabled(cardVM.canMovePriorityUp)
          local capGK = cardVM.goalKey
          cardW.prioUpBtn:SetOnClick(function()
            CratesUI.Dispatch("MOVE_PRIORITY", { goalKey = capGK, delta = -1 })
          end)
          Widgets.SafeShow(cardW.prioUpBtn, true)
          rightCursor = rightCursor + 28
        end
        if cardVM.excessOverOwned > 0 and cardW.reduceBtn then
          Widgets.SafeClearPoints(cardW.reduceBtn)
          Widgets.SafeSetPoint(cardW.reduceBtn, "TOPRIGHT", cardW, "TOPRIGHT", -rightCursor, -16)
          cardW.reduceBtn:SetLabel(string.format("Own (%d)", cardVM.charOwned))
          cardW.reduceBtn:SetButtonEnabled(cardVM.canReduceToOwned)
          Widgets.BindTooltip(
            cardW.reduceBtn,
            "Reduce Plan to Observed Ownership",
            { cardVM.canReduceToOwned and "Reduces reserved turn-ins to match crates/writs owned on this character." or tostring(cardVM.reduceBlockReason or "Ownership uncertain.") }
          )
          local capPayload = {
            kind = cardVM.kind,
            itemID = cardVM.itemID,
            name = cardVM.name,
            charOwned = cardVM.charOwned,
            canReduce = cardVM.canReduceToOwned,
            blockReason = cardVM.reduceBlockReason,
          }
          cardW.reduceBtn:SetOnClick(function()
            CratesUI.Dispatch("REDUCE_TO_OWNED", capPayload)
          end)
          Widgets.SafeShow(cardW.reduceBtn, true)
          rightCursor = rightCursor + 78
        elseif cardW.reduceBtn then
          Widgets.SafeShow(cardW.reduceBtn, false)
        end
      else
        if cardW.prioUpBtn then Widgets.SafeShow(cardW.prioUpBtn, false) end
        if cardW.prioDownBtn then Widgets.SafeShow(cardW.prioDownBtn, false) end
        if cardW.reduceBtn then Widgets.SafeShow(cardW.reduceBtn, false) end
      end

      if cardVM.reservedBadge then
        usedBadges = usedBadges + 1
        local b = acquireBadge(CratesUI.badgePool, usedBadges, cardW)
        if b then
          local bw = b:Configure(
            cardVM.reservedBadge.text,
            cardVM.reservedBadge.token,
            cardVM.reservedBadge.glyph,
            false,
            cardVM.reservedBadge.tooltipTitle,
            cardVM.reservedBadge.tooltipLines
          )
          Widgets.SafeClearPoints(b)
          Widgets.SafeSetPoint(b, "TOPRIGHT", cardW, "TOPRIGHT", -rightCursor, -18)
          rightCursor = rightCursor + bw + 6
        end
      end

      if cardVM.readinessBadge then
        usedBadges = usedBadges + 1
        local b = acquireBadge(CratesUI.badgePool, usedBadges, cardW)
        if b then
          local bw = b:Configure(
            cardVM.readinessBadge.text,
            cardVM.readinessBadge.token,
            cardVM.readinessBadge.glyph,
            false,
            cardVM.readinessBadge.tooltipTitle,
            cardVM.readinessBadge.tooltipLines
          )
          Widgets.SafeClearPoints(b)
          Widgets.SafeSetPoint(b, "TOPRIGHT", cardW, "TOPRIGHT", -rightCursor, -18)
          rightCursor = rightCursor + bw + 6
        end
      end

      -- Measure Header Text before assigning header height (Astra rule: min 56, expands cleanly if wrapped)
      local headerTextLeft = 72
      local headerTextW = math.max(160, rowWidth - headerTextLeft - rightCursor - 8)

      if cardW.titleText then
        Widgets.SafeClearPoints(cardW.titleText)
        Widgets.SafeSetPoint(cardW.titleText, "TOPLEFT", cardW.headerBtn or cardW, "TOPLEFT", headerTextLeft, -10)
        Theme.ApplyFont(cardW.titleText, "sectionTitle", "text.primary")
      end
      local titleH = Theme.MeasureWrappedHeight(cardW.titleText, cardVM.name, headerTextW, "sectionTitle", 20, 0)

      if cardW.summaryText then
        Widgets.SafeClearPoints(cardW.summaryText)
        Widgets.SafeSetPoint(cardW.summaryText, "TOPLEFT", cardW.headerBtn or cardW, "TOPLEFT", headerTextLeft, -(10 + titleH + 2))
        Theme.ApplyFont(cardW.summaryText, "dense", "text.secondary")
      end
      local summaryH = Theme.MeasureWrappedHeight(cardW.summaryText, cardVM.collapsedSummaryText, headerTextW, "dense", 16, 0)
      local headerH = math.max(Theme.METRICS.crateHeaderHeight, 10 + titleH + 2 + summaryH + 10)

      if cardW.headerBtn then
        Widgets.SafeClearPoints(cardW.headerBtn)
        Widgets.SafeSetPoint(cardW.headerBtn, "TOPLEFT", cardW, "TOPLEFT", 1, -1)
        Widgets.SafeSetSize(cardW.headerBtn, rowWidth - 2, headerH - 2)
        local capGK = cardVM.goalKey
        local capExp = cardVM.isExpanded
        cardW.headerBtn:SetScript("OnClick", function()
          CratesUI.Dispatch("TOGGLE_CARD", { goalKey = capGK, currentExpanded = capExp })
        end)
      end

      if cardW.chevronTex then
        Widgets.SafeClearPoints(cardW.chevronTex)
        Widgets.SafeSetPoint(cardW.chevronTex, "LEFT", cardW.headerBtn or cardW, "LEFT", 12, 0)
      end
      if cardW.chevronFallback then
        Widgets.SafeClearPoints(cardW.chevronFallback)
        Widgets.SafeSetPoint(cardW.chevronFallback, "LEFT", cardW.headerBtn or cardW, "LEFT", 14, 0)
      end
      Widgets.ApplyGlyph(
        cardW.chevronTex,
        cardW.chevronFallback,
        cardVM.isExpanded and "chevron_down" or "chevron_right",
        "text.secondary"
      )

      if cardW.itemIcon then
        Widgets.SafeClearPoints(cardW.itemIcon)
        Widgets.SafeSetPoint(cardW.itemIcon, "LEFT", cardW.headerBtn or cardW, "LEFT", 32, 0)
        cardW.itemIcon:SetItem(cardVM.itemID, cardVM.name, generation)
      end

      local cardInnerY = headerH
      local cardReport = {
        goalKey = cardVM.goalKey,
        y = yCursor,
        width = rowWidth,
        headerHeight = headerH,
        headerTextBox = { x = headerTextLeft, width = headerTextW, rightReserved = rightCursor },
        isExpanded = cardVM.isExpanded,
        options = {},
      }

      if cardVM.isExpanded then
        -- Optional Writ Limitation Notice
        if cardVM.limitationNotice and cardW.writNotice then
          Widgets.SafeClearPoints(cardW.writNotice)
          Widgets.SafeSetPoint(cardW.writNotice, "TOPLEFT", cardW, "TOPLEFT", 16, -cardInnerY)
          Theme.ApplyFont(cardW.writNotice, "dense", "status.warning")
          local wnH = Theme.MeasureWrappedHeight(
            cardW.writNotice,
            (not cardVM.quantityVerified and "Unverified writ quantity (1 assumed) · " or "") .. cardVM.limitationNotice,
            rowWidth - 32,
            "dense",
            18,
            4
          )
          Widgets.SafeShow(cardW.writNotice, true)
          cardInnerY = cardInnerY + wnH + 4
        elseif cardW.writNotice then
          Widgets.SafeShow(cardW.writNotice, false)
        end

        -- Table Column Header (24 high)
        if cardW.tableHeader then
          Widgets.SafeClearPoints(cardW.tableHeader)
          Widgets.SafeSetPoint(cardW.tableHeader, "TOPLEFT", cardW, "TOPLEFT", 1, -cardInnerY)
          Widgets.SafeSetSize(cardW.tableHeader, rowWidth - 2, Theme.METRICS.tableHeaderHeight)

          local function placeTH(fs, colSpec, txt, alignRight)
            if not fs or not colSpec then
              if fs then Widgets.SafeShow(fs, false) end
              return
            end
            Widgets.SafeClearPoints(fs)
            Widgets.SafeSetPoint(fs, "LEFT", cardW.tableHeader, "LEFT", colSpec.x, 0)
            Widgets.SafeSetWidth(fs, colSpec.w)
            Theme.ApplyFont(fs, "dense", "text.muted")
            if type(fs.SetJustifyH) == "function" then
              pcall(fs.SetJustifyH, fs, alignRight and "RIGHT" or "LEFT")
            end
            if type(fs.SetText) == "function" then
              fs:SetText(txt)
            end
            Widgets.SafeShow(fs, true)
          end

          placeTH(cardW.thMat, cols.mat, "Material / requirement", false)
          placeTH(cardW.thBags, cols.bags, "Bags", true)
          placeTH(cardW.thBank, cols.bank, "Bank", true)
          placeTH(cardW.thBuy, cols.buy, "Buy", true)
          placeTH(cardW.thCost, cols.cost, "Est. cost", true)
          placeTH(cardW.thPlan, cols.plan, "Plan", true)
          Widgets.SafeShow(cardW.tableHeader, true)
          cardInnerY = cardInnerY + Theme.METRICS.tableHeaderHeight + 4
        end

        -- Render Evaluated Option Blocks
        for _, optVM in ipairs(cardVM.options or {}) do
          usedOptions = usedOptions + 1
          local optW = acquireOptionWidget(usedOptions, cardW)
          if optW then
            local optInnerW = rowWidth - 16
            local optCols = CratesUI.ComputeOptionColumns(optInnerW, cols.isCompact)
            -- Keep column X aligned with card tableHeader (indented by 8px inside card)
            local colShift = -8
            local function shiftedCol(cSpec)
              if not cSpec then return nil end
              return { x = math.max(8, cSpec.x + colShift), w = cSpec.w }
            end
            local cIcon = shiftedCol(cols.icon)
            local cMat = shiftedCol(cols.mat)
            local cBags = shiftedCol(cols.bags)
            local cBank = shiftedCol(cols.bank)
            local cBuy = shiftedCol(cols.buy)
            local cCost = shiftedCol(cols.cost)
            local cPlan = cols.plan and { x = cols.plan.x + colShift, w = math.max(224, optInnerW - (cols.plan.x + colShift) - 8) } or nil
            optCols = {
              isCompact = cols.isCompact,
              icon = cIcon,
              mat = cMat,
              bags = cBags,
              bank = cBank,
              buy = cBuy,
              cost = cCost,
              plan = cPlan,
            }

            Widgets.SafeClearPoints(optW)
            Widgets.SafeSetPoint(optW, "TOPLEFT", cardW, "TOPLEFT", 8, -cardInnerY)

            local optSurf = optVM.isReserved and "surface.reserved"
              or (optVM.isSelected and "surface.selected" or "surface.window")
            local optBorder = optVM.isReserved and "status.reserved"
              or (optVM.isSelected and "accent.gold" or "border.subtle")
            Widgets.ApplySurface(optW, optSurf, optBorder, optVM.isSelected and 0.85 or 0.8)

            if optW.leftAccent then
              if optVM.isSelected or optVM.isReserved then
                Widgets.SafeSetSolidColor(optW.leftAccent, optVM.isReserved and "status.reserved" or "accent.gold", 1.0)
                Widgets.SafeShow(optW.leftAccent, true)
              else
                Widgets.SafeShow(optW.leftAccent, false)
              end
            end

            local ingY = 8
            local ingReports = {}
            for _, matVM in ipairs(optVM.materials or {}) do
              usedIngredients = usedIngredients + 1
              local iRow = acquireIngredientRowWidget(usedIngredients, optW)
              if iRow then
                Widgets.SafeClearPoints(iRow)
                Widgets.SafeSetPoint(iRow, "TOPLEFT", optW, "TOPLEFT", 0, -ingY)

                if iRow.matText then
                  Widgets.SafeClearPoints(iRow.matText)
                  Widgets.SafeSetPoint(iRow.matText, "LEFT", iRow, "LEFT", optCols.mat.x, 0)
                  Theme.ApplyFont(iRow.matText, "body", "text.primary")
                end
                local mH = Theme.MeasureWrappedHeight(
                  iRow.matText,
                  matVM.requirementLabel,
                  optCols.mat.w,
                  "body",
                  Theme.METRICS.ingredientRowMinHeight,
                  8
                )

                if iRow.costText then
                  Widgets.SafeClearPoints(iRow.costText)
                  Widgets.SafeSetPoint(iRow.costText, "LEFT", iRow, "LEFT", optCols.cost.x, 0)
                  Theme.ApplyFont(iRow.costText, "body", "text.primary")
                end
                local cH = Theme.MeasureWrappedHeight(
                  iRow.costText,
                  matVM.estCostText,
                  optCols.cost.w,
                  "body",
                  Theme.METRICS.ingredientRowMinHeight,
                  8
                )

                local rowH = math.max(Theme.METRICS.ingredientRowMinHeight, mH, cH)
                Widgets.SafeSetSize(iRow, optInnerW, rowH)

                if iRow.icon then
                  Widgets.SafeClearPoints(iRow.icon)
                  Widgets.SafeSetPoint(iRow.icon, "LEFT", iRow, "LEFT", optCols.icon.x, 0)
                  iRow.icon:SetItem(matVM.itemID, matVM.name, generation)
                end

                local function setNumCell(fs, colS, valStr, tok)
                  if not fs or not colS then return end
                  Widgets.SafeClearPoints(fs)
                  Widgets.SafeSetPoint(fs, "LEFT", iRow, "LEFT", colS.x, 0)
                  Widgets.SafeSetWidth(fs, colS.w)
                  Theme.ApplyFont(fs, "body", tok)
                  if type(fs.SetWordWrap) == "function" then pcall(fs.SetWordWrap, fs, false) end
                  if type(fs.SetText) == "function" then fs:SetText(tostring(valStr)) end
                end

                setNumCell(
                  iRow.bagsText,
                  optCols.bags,
                  tostring(matVM.freeBags),
                  matVM.freeBags > 0 and "status.ready" or "text.muted"
                )
                setNumCell(
                  iRow.bankText,
                  optCols.bank,
                  matVM.bankCellText,
                  matVM.freeBank > 0 and "status.bank" or "text.muted"
                )
                setNumCell(
                  iRow.buyText,
                  optCols.buy,
                  tostring(matVM.buyUnits),
                  matVM.buyUnits > 0 and "status.buy" or "text.muted"
                )

                table.insert(ingReports, {
                  itemID = matVM.itemID,
                  y = ingY,
                  height = rowH,
                  cells = {
                    icon = optCols.icon,
                    mat = optCols.mat,
                    bags = optCols.bags,
                    bank = optCols.bank,
                    buy = optCols.buy,
                    cost = optCols.cost,
                  },
                })
                ingY = ingY + rowH
              end
            end

            local ingredientsBottomY = ingY + 8
            if optW.footerDivider then
              Widgets.SafeClearPoints(optW.footerDivider)
              Widgets.SafeSetPoint(optW.footerDivider, "TOPLEFT", optW, "TOPLEFT", 10, -ingredientsBottomY)
              Widgets.SafeSetPoint(optW.footerDivider, "TOPRIGHT", optW, "TOPRIGHT", -10, -ingredientsBottomY)
              Widgets.SafeShow(optW.footerDivider, true)
            end

            -- Option Badges & Summary in Footer Band (Astra rule: optionHeight = 16 + sum(ing) + footerH)
            local badgeX = optCols.mat.x
            local badgeY = ingredientsBottomY + 7

            if optVM.isBest and optVM.bestLabel then
              usedBadges = usedBadges + 1
              local bb = acquireBadge(CratesUI.badgePool, usedBadges, optW)
              if bb then
                local bw = bb:Configure(optVM.bestLabel, "accent.gold", "check", true, "Recommended Option", optVM.bestTooltip)
                Widgets.SafeClearPoints(bb)
                Widgets.SafeSetPoint(bb, "TOPLEFT", optW, "TOPLEFT", badgeX, -badgeY)
                badgeX = badgeX + bw + 6
              end
            end

            if optVM.consumesReservedStock then
              usedBadges = usedBadges + 1
              local cb = acquireBadge(CratesUI.badgePool, usedBadges, optW)
              if cb then
                local bw = cb:Configure(
                  "Uses reserved stock",
                  "status.danger",
                  "warning",
                  false,
                  "Reservation Conflict",
                  { optVM.conflictWarning or "Consumes stock reserved by a higher-priority goal." }
                )
                Widgets.SafeClearPoints(cb)
                Widgets.SafeSetPoint(cb, "TOPLEFT", optW, "TOPLEFT", badgeX, -badgeY)
                badgeX = badgeX + bw + 6
              end
            end

            if optVM.displacesLowerPriorityStock then
              usedBadges = usedBadges + 1
              local db = acquireBadge(CratesUI.badgePool, usedBadges, optW)
              if db then
                local bw = db:Configure(
                  "Shifts lower prio",
                  "status.warning",
                  "warning",
                  false,
                  "Downstream Displacement",
                  { optVM.displacementWarning or "Displaces stock allocated to a lower-priority reservation." }
                )
                Widgets.SafeClearPoints(db)
                Widgets.SafeSetPoint(db, "TOPLEFT", optW, "TOPLEFT", badgeX, -badgeY)
                badgeX = badgeX + bw + 6
              end
            end

            if optVM.isStalePrice then
              usedBadges = usedBadges + 1
              local sb = acquireBadge(CratesUI.badgePool, usedBadges, optW)
              if sb then
                local bw = sb:Configure(
                  "Stale price",
                  "status.warning",
                  "info",
                  false,
                  "Stale Auctionator Price",
                  { "Cached scan age exceeds your configured freshness threshold." }
                )
                Widgets.SafeClearPoints(sb)
                Widgets.SafeSetPoint(sb, "TOPLEFT", optW, "TOPLEFT", badgeX, -badgeY)
                badgeX = badgeX + bw + 6
              end
            end

            local footerSummaryStr = string.format(
              "Option #%d  ·  Est. buy: %s  ·  Full value: %s",
              optVM.optionIndex,
              optVM.estCostFormatted,
              optVM.replacementFormatted
            )
            if optVM.isSelected and type(optVM.selectedRowOpportunityDetailText) == "string" and optVM.selectedRowOpportunityDetailText ~= "" then
              footerSummaryStr = footerSummaryStr .. "\n" .. optVM.selectedRowOpportunityDetailText
            end

            local footerH = Theme.METRICS.optionFooterHeight
            local controlsReport = {}
            local capKind = cardVM.kind
            local capItemID = cardVM.itemID
            local capGK = cardVM.goalKey
            local capOptIdx = optVM.optionIndex
            local capDraftQty = optVM.draftQuantity

            if not optCols.isCompact then
              -- Standard Layout (>=900): QuantityEditor sits in `plan` column in ingredient band;
              -- Primary `Reserve` / `Choose` sits in `plan` column in the footer band!
              local footerTextRightLimit = optCols.plan.x - 8
              local availFooterTextW = math.max(120, footerTextRightLimit - badgeX)
              local ftY = badgeY + 1
              local ftX = badgeX
              if (availFooterTextW < 180 or optVM.isSelected) and badgeX > optCols.mat.x then
                -- Drop summary cleanly onto a second sub-line inside footer if badges are active or selected details are shown
                ftX = optCols.mat.x
                ftY = badgeY + 22
                availFooterTextW = math.max(180, footerTextRightLimit - ftX)
              end
              if optW.footerText then
                Widgets.SafeClearPoints(optW.footerText)
                Widgets.SafeSetPoint(optW.footerText, "TOPLEFT", optW, "TOPLEFT", ftX, -ftY)
                Theme.ApplyFont(optW.footerText, "dense", "text.secondary")
              end
              local ftH = Theme.MeasureWrappedHeight(optW.footerText, footerSummaryStr, availFooterTextW, "dense", 18, 0)
              local extraBottomClearance = (optVM.isSelected and cardVM.isReserved and optVM.isReserved) and 30 or 6
              footerH = math.max(Theme.METRICS.optionFooterHeight, (ftY - ingredientsBottomY) + ftH + extraBottomClearance)

              if optVM.isSelected then
                if optW.chooseBtn then Widgets.SafeShow(optW.chooseBtn, false) end
                if optW.qtyEditor then
                  Widgets.SafeClearPoints(optW.qtyEditor)
                  Widgets.SafeSetPoint(optW.qtyEditor, "TOPRIGHT", optW, "TOPRIGHT", -8, -12)
                  optW.qtyEditor:Configure(capDraftQty, cardVM.charOwned, function(newQty)
                    CratesUI.Dispatch("SET_DRAFT_QUANTITY", { goalKey = capGK, quantity = newQty })
                  end)
                  Widgets.SafeShow(optW.qtyEditor, true)
                  controlsReport.qtyEditor = { x = optInnerW - 8 - 224, y = 12, w = 224, h = 24 }
                end

                if optW.primaryBtn then
                  Widgets.SafeClearPoints(optW.primaryBtn)
                  Widgets.SafeSetPoint(optW.primaryBtn, "BOTTOMRIGHT", optW, "BOTTOMRIGHT", -8, 4)
                  optW.primaryBtn:SetLabel(optVM.primaryActionLabel)
                  optW.primaryBtn:SetButtonEnabled(optVM.primaryActionEnabled)
                  optW.primaryBtn:SetOnClick(function()
                    CratesUI.Dispatch("COMMIT_RESERVATION", {
                      kind = capKind,
                      itemID = capItemID,
                      goalKey = capGK,
                      optionIndex = capOptIdx,
                      quantity = capDraftQty,
                    })
                  end)
                  Widgets.SafeShow(optW.primaryBtn, true)
                  controlsReport.primaryBtn = { x = optInnerW - 8 - 112, y = ingredientsBottomY + 4, w = 112, h = 26 }
                end

                if cardVM.isReserved and optVM.isReserved then
                  if optW.removeBtn then
                    Widgets.SafeClearPoints(optW.removeBtn)
                    Widgets.SafeSetPoint(optW.removeBtn, "RIGHT", optW.primaryBtn, "LEFT", -4, 0)
                    optW.removeBtn:SetOnClick(function()
                      CratesUI.Dispatch("UNRESERVE_GOAL", { goalKey = capGK })
                    end)
                    Widgets.SafeShow(optW.removeBtn, true)
                  end
                  if optW.doneBtn then
                    Widgets.SafeClearPoints(optW.doneBtn)
                    Widgets.SafeSetPoint(optW.doneBtn, "RIGHT", optW.removeBtn, "LEFT", -4, 0)
                    optW.doneBtn:SetOnClick(function()
                      CratesUI.Dispatch("COMPLETE_TURNIN", { kind = capKind, itemID = capItemID, count = 1 })
                    end)
                    Widgets.SafeShow(optW.doneBtn, true)
                  end
                else
                  if optW.doneBtn then Widgets.SafeShow(optW.doneBtn, false) end
                  if optW.removeBtn then Widgets.SafeShow(optW.removeBtn, false) end
                end
              else
                if optW.qtyEditor then Widgets.SafeShow(optW.qtyEditor, false) end
                if optW.primaryBtn then Widgets.SafeShow(optW.primaryBtn, false) end
                if optW.doneBtn then Widgets.SafeShow(optW.doneBtn, false) end
                if optW.removeBtn then Widgets.SafeShow(optW.removeBtn, false) end
                if optW.chooseBtn then
                  Widgets.SafeClearPoints(optW.chooseBtn)
                  Widgets.SafeSetPoint(optW.chooseBtn, "BOTTOMRIGHT", optW, "BOTTOMRIGHT", -8, 4)
                  optW.chooseBtn:SetLabel("Choose")
                  optW.chooseBtn:SetOnClick(function()
                    CratesUI.Dispatch("SELECT_DRAFT_OPTION", { goalKey = capGK, optionIndex = capOptIdx })
                  end)
                  Widgets.SafeShow(optW.chooseBtn, true)
                  controlsReport.chooseBtn = { x = optInnerW - 8 - 88, y = ingredientsBottomY + 4, w = 88, h = 26 }
                end
              end
            else
              -- Dedicated Compact Layout (<900 window width):
              -- Top footer band holds badges + option summary; bottom band holds QuantityEditor + Primary Action!
              local rightButtonReserve = optVM.isSelected and 0 or 98
              local ftX = badgeX
              local ftY = badgeY + 1
              local availW = (optInnerW - 12 - rightButtonReserve) - ftX
              if availW < 180 and badgeX > optCols.mat.x then
                ftX = optCols.mat.x
                ftY = badgeY + 22
                availW = (optInnerW - 12 - rightButtonReserve) - ftX
              end
              if optW.footerText then
                Widgets.SafeClearPoints(optW.footerText)
                Widgets.SafeSetPoint(optW.footerText, "TOPLEFT", optW, "TOPLEFT", ftX, -ftY)
                Theme.ApplyFont(optW.footerText, "dense", "text.secondary")
              end
              local ftH = Theme.MeasureWrappedHeight(optW.footerText, footerSummaryStr, math.max(160, availW), "dense", 18, 0)
              local topBandH = (ftY - ingredientsBottomY) + ftH + 6

              if optVM.isSelected then
                footerH = topBandH + 34
                if optW.chooseBtn then Widgets.SafeShow(optW.chooseBtn, false) end
                if optW.qtyEditor then
                  Widgets.SafeClearPoints(optW.qtyEditor)
                  Widgets.SafeSetPoint(optW.qtyEditor, "BOTTOMLEFT", optW, "BOTTOMLEFT", optCols.mat.x, 6)
                  optW.qtyEditor:Configure(capDraftQty, cardVM.charOwned, function(newQty)
                    CratesUI.Dispatch("SET_DRAFT_QUANTITY", { goalKey = capGK, quantity = newQty })
                  end)
                  Widgets.SafeShow(optW.qtyEditor, true)
                  controlsReport.qtyEditor = { x = optCols.mat.x, y = ingredientsBottomY + topBandH + 4, w = 224, h = 24 }
                end
                if optW.primaryBtn then
                  Widgets.SafeClearPoints(optW.primaryBtn)
                  Widgets.SafeSetPoint(optW.primaryBtn, "BOTTOMRIGHT", optW, "BOTTOMRIGHT", -8, 5)
                  optW.primaryBtn:SetLabel(optVM.primaryActionLabel)
                  optW.primaryBtn:SetButtonEnabled(optVM.primaryActionEnabled)
                  optW.primaryBtn:SetOnClick(function()
                    CratesUI.Dispatch("COMMIT_RESERVATION", {
                      kind = capKind,
                      itemID = capItemID,
                      goalKey = capGK,
                      optionIndex = capOptIdx,
                      quantity = capDraftQty,
                    })
                  end)
                  Widgets.SafeShow(optW.primaryBtn, true)
                  controlsReport.primaryBtn = { x = optInnerW - 8 - 112, y = ingredientsBottomY + topBandH + 3, w = 112, h = 26 }
                end
                if cardVM.isReserved and optVM.isReserved then
                  if optW.removeBtn then
                    Widgets.SafeClearPoints(optW.removeBtn)
                    Widgets.SafeSetPoint(optW.removeBtn, "RIGHT", optW.primaryBtn, "LEFT", -4, 0)
                    optW.removeBtn:SetOnClick(function()
                      CratesUI.Dispatch("UNRESERVE_GOAL", { goalKey = capGK })
                    end)
                    Widgets.SafeShow(optW.removeBtn, true)
                  end
                  if optW.doneBtn then
                    Widgets.SafeClearPoints(optW.doneBtn)
                    Widgets.SafeSetPoint(optW.doneBtn, "RIGHT", optW.removeBtn, "LEFT", -4, 0)
                    optW.doneBtn:SetOnClick(function()
                      CratesUI.Dispatch("COMPLETE_TURNIN", { kind = capKind, itemID = capItemID, count = 1 })
                    end)
                    Widgets.SafeShow(optW.doneBtn, true)
                  end
                else
                  if optW.doneBtn then Widgets.SafeShow(optW.doneBtn, false) end
                  if optW.removeBtn then Widgets.SafeShow(optW.removeBtn, false) end
                end
              else
                footerH = math.max(34, topBandH)
                if optW.qtyEditor then Widgets.SafeShow(optW.qtyEditor, false) end
                if optW.primaryBtn then Widgets.SafeShow(optW.primaryBtn, false) end
                if optW.doneBtn then Widgets.SafeShow(optW.doneBtn, false) end
                if optW.removeBtn then Widgets.SafeShow(optW.removeBtn, false) end
                if optW.chooseBtn then
                  Widgets.SafeClearPoints(optW.chooseBtn)
                  Widgets.SafeSetPoint(optW.chooseBtn, "BOTTOMRIGHT", optW, "BOTTOMRIGHT", -8, 4)
                  optW.chooseBtn:SetLabel("Choose")
                  optW.chooseBtn:SetOnClick(function()
                    CratesUI.Dispatch("SELECT_DRAFT_OPTION", { goalKey = capGK, optionIndex = capOptIdx })
                  end)
                  Widgets.SafeShow(optW.chooseBtn, true)
                  controlsReport.chooseBtn = { x = optInnerW - 8 - 88, y = ingredientsBottomY + 4, w = 88, h = 26 }
                end
              end
            end

            local optTotalH = ingredientsBottomY + footerH
            Widgets.SafeSetSize(optW, optInnerW, optTotalH)

            table.insert(cardReport.options, {
              optionIndex = optVM.optionIndex,
              isSelected = optVM.isSelected,
              y = cardInnerY,
              width = optInnerW,
              height = optTotalH,
              ingredientsHeight = ingredientsBottomY,
              footerHeight = footerH,
              ingredients = ingReports,
              controls = controlsReport,
            })

            cardInnerY = cardInnerY + optTotalH + 6
          end
        end
        cardInnerY = cardInnerY + 4
      else
        if cardW.tableHeader then Widgets.SafeShow(cardW.tableHeader, false) end
        if cardW.writNotice then Widgets.SafeShow(cardW.writNotice, false) end
      end

      Widgets.SafeSetSize(cardW, rowWidth, cardInnerY)
      cardReport.height = cardInnerY
      table.insert(layoutReport.cards, cardReport)
      yCursor = yCursor + cardInnerY + 8
    end
  end

  -- Hide unused pooled widgets strictly
  resetPoolList(CratesUI.cardPool, usedCards)
  resetPoolList(CratesUI.optionPool, usedOptions)
  resetPoolList(CratesUI.ingredientRowPool, usedIngredients)
  resetPoolList(CratesUI.badgePool, usedBadges)

  -- Update Scroll Viewport dimensions while preserving scroll offset
  local totalScrollHeight = math.max(viewportH, yCursor + 8)
  layoutReport.totalScrollHeight = totalScrollHeight
  if hv.viewport then
    local savedOff = 0
    local uiState = ns.State and ns.State.GetWorkspaceUIState and ns.State.GetWorkspaceUIState()
    if uiState and uiState.cratesView then
      savedOff = tonumber(uiState.cratesView.scrollOffset) or 0
    end
    hv.viewport:SetDimensions(cw, viewportH, totalScrollHeight)
    hv.viewport:SetScrollOffset(savedOff, true)
  end

  CratesUI.lastLayoutReport = layoutReport
  return layoutReport
end

function CratesUI.RenderInHost(contentWidth, contentHeight, isCompact)
  local uiState = (ns.State and ns.State.GetWorkspaceUIState and ns.State.GetWorkspaceUIState()) or {}
  local snap = CratesPresenter.CaptureSnapshot({
    pendingSuggestionPreview = CratesUI.pendingSuggestionPreview,
  })
  local vm = CratesPresenter.Build(snap, uiState, CratesUI.draftState)
  CratesUI.lastViewModel = vm
  return CratesUI.RenderViewModel(vm, contentWidth, contentHeight, isCompact)
end

function CratesUI.GetLastLayoutReport()
  return CratesUI.lastLayoutReport
end

function CratesUI.GetLastViewModel()
  return CratesUI.lastViewModel
end

function CratesUI.OnItemInfoReceived(itemID, success)
  if not success or not itemID then
    return
  end
  if Workspace.frame and type(Workspace.frame.IsShown) == "function" and Workspace.frame:IsShown() then
    Workspace.RefreshIfShown()
  end
end

function CratesUI.Refresh()
  CratesUI.EnsureInitialized()
  if Workspace.frame and type(Workspace.frame.IsShown) == "function" and Workspace.frame:IsShown() then
    Workspace.Refresh()
  end
end

function CratesUI.RefreshIfShown()
  if Workspace.frame and type(Workspace.frame.IsShown) == "function" and Workspace.frame:IsShown() then
    Workspace.Refresh()
  end
end

function CratesUI.Toggle()
  CratesUI.EnsureInitialized()
  Workspace.Toggle("crates")
end

return CratesUI
