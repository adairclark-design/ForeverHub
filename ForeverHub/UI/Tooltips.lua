local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.UI = ns.UI or {}
local Tooltips = {}
ns.UI.Tooltips = Tooltips

local function col(token, text)
  local Theme = ns.UI and ns.UI.Theme
  if Theme and type(Theme.Colorize) == "function" then
    return Theme.Colorize(token, text)
  end
  return tostring(text or "")
end

local function unpackRGB(token, dr, dg, db)
  local Theme = ns.UI and ns.UI.Theme
  if Theme and type(Theme.UnpackRGBA) == "function" then
    local r, g, b = Theme.UnpackRGBA(token)
    return r, g, b
  end
  return dr, dg, db
end

local function safeAddDoubleLine(tooltip, leftText, rightText, lr, lg, lb, rr, rg, rb)
  if type(tooltip.AddDoubleLine) == "function" then
    tooltip:AddDoubleLine(leftText, rightText, lr, lg, lb, rr, rg, rb)
  elseif type(tooltip.AddLine) == "function" then
    tooltip:AddLine(tostring(leftText or "") .. "  " .. tostring(rightText or ""), lr or 0.9, lg or 0.9, lb or 0.9, true)
  end
end

local function formatOptionMaterialsShort(opt)
  local parts = {}
  for _, m in ipairs(opt.materials or {}) do
    table.insert(parts, string.format("%dx %s (Unreserved:%d/%d)", m.requiredQty, m.name, m.freeBags, m.freeBags + m.freeTransfer))
  end
  return table.concat(parts, " + ")
end

local function appendTargetTooltip(tooltip, kind, record)
  local eval = ns.Domain.Costs.EvaluateTargetOptions(kind, record)
  if not eval then
    return
  end

  local focusOpt = eval.bestOption or (eval.options and eval.options[1])
  for _, opt in ipairs(eval.options or {}) do
    if opt.isReserved then
      focusOpt = opt
      break
    end
  end
  if not focusOpt then
    return
  end

  local priR, priG, priB = unpackRGB("text.primary", 0.93, 0.91, 0.86)
  local secR, secG, secB = unpackRGB("text.secondary", 0.74, 0.77, 0.80)
  local mutR, mutG, mutB = unpackRGB("text.muted", 0.57, 0.62, 0.66)
  local wrnR, wrnG, wrnB = unpackRGB("status.warning", 0.95, 0.77, 0.38)
  local dngR, dngG, dngB = unpackRGB("status.danger", 0.91, 0.54, 0.50)

  local turnInCount = tonumber(focusOpt.quantity) or 1
  local badge = focusOpt.isReserved
    and (" " .. col("status.reserved", string.format("[Reserved x%d]", turnInCount)))
    or ""

  local buyEstStr
  if eval.acquisitionMode == "bags_only" then
    if focusOpt.isBagDeficitKnown then
      buyEstStr = ns.Compat.FormatCopper(focusOpt.bagDeficitEstimate) .. " (bags only)"
      if focusOpt.isTransferDeficitKnown and (focusOpt.transferDeficitEstimate or 0) ~= (focusOpt.bagDeficitEstimate or 0) then
        buyEstStr = buyEstStr .. string.format(" [%s w/ bank]", ns.Compat.FormatCopper(focusOpt.transferDeficitEstimate))
      end
    elseif focusOpt.isTransferDeficitKnown then
      buyEstStr = string.format("%s w/ bank (bags-only unpriced)", ns.Compat.FormatCopper(focusOpt.transferDeficitEstimate))
    else
      buyEstStr = "Unpriced (scan AH)"
    end
  else
    -- Default "after_bank" mode: primary purchase estimate uses verified bank + bags
    if focusOpt.isTransferDeficitKnown then
      buyEstStr = ns.Compat.FormatCopper(focusOpt.transferDeficitEstimate)
      if (focusOpt.totalRetrieveBankUnits or 0) > 0 or (focusOpt.totalRetrieveAltUnits or 0) > 0 then
        buyEstStr = buyEstStr .. " (w/ bank)"
      end
      if focusOpt.isBagDeficitKnown and (focusOpt.bagDeficitEstimate or 0) > (focusOpt.transferDeficitEstimate or 0) then
        buyEstStr = buyEstStr .. string.format(" [bags-only: %s]", ns.Compat.FormatCopper(focusOpt.bagDeficitEstimate))
      end
    elseif focusOpt.isBagDeficitKnown then
      buyEstStr = ns.Compat.FormatCopper(focusOpt.bagDeficitEstimate)
    else
      buyEstStr = "Unpriced (scan AH)"
    end
  end

  -- Line 1: Best/Reserved Option + Est. Buy (AH cache) + Scope label
  tooltip:AddLine(
    string.format(
      "%s Opt #%d (%s)%s · Est. Buy: %s %s",
      col("accent.gold", "ForeverHub:"),
      focusOpt.optionIndex,
      formatOptionMaterialsShort(focusOpt),
      badge,
      buyEstStr,
      col("text.muted", "[" .. tostring(eval.recommendationScopeLabel or "Lowest known buy cost") .. "]")
    ),
    priR, priG, priB, true
  )

  -- Line 2: Materials consumed value + freshness + reservation conflict or downstream displacement warning
  local replStr = focusOpt.isPriced and ns.Compat.FormatCopper(focusOpt.replacementEstimate) or "Unpriced"
  local ageTag = ""
  if focusOpt.isStalePrice then
    ageTag = " " .. col("status.warning", "(stale AH scan)")
  elseif focusOpt.isUnknownPriceAge then
    ageTag = " " .. col("status.warning", "(AH age >21d)")
  end

  if focusOpt.consumesReservedStock and focusOpt.conflictWarning then
    tooltip:AddLine(
      string.format("%s (Est. Mat Val: %s%s)", col("status.danger", focusOpt.conflictWarning), replStr, ageTag),
      dngR, dngG, dngB, true
    )
  elseif focusOpt.displacesLowerPriorityStock and focusOpt.displacementWarning then
    tooltip:AddLine(
      string.format("%s (Est. Mat Val: %s%s)", col("status.warning", focusOpt.displacementWarning), replStr, ageTag),
      wrnR, wrnG, wrnB, true
    )
  else
    local retrieveTag = (focusOpt.totalRetrieveBankUnits and focusOpt.totalRetrieveBankUnits > 0)
      and string.format(" · Retrieve %d from bank", focusOpt.totalRetrieveBankUnits)
      or ""
    tooltip:AddLine(
      string.format("%s %s%s%s %s", col("text.secondary", "Est. Mat Value:"), replStr, ageTag, retrieveTag, col("text.muted", "(/fh to plan)")),
      secR, secG, secB, true
    )
  end

  -- Line 3 (or Shift breakdown): Provenance / Writ limitation / Reputation rule
  if IsShiftKeyDown and IsShiftKeyDown() and #(eval.options or {}) > 1 then
    for _, opt in ipairs(eval.options) do
      local rTag = opt.isReserved and (" " .. col("status.reserved", string.format("[Reserved x%d]", opt.quantity or 1))) or ""
      local dTag = opt.displacesLowerPriorityStock and (" " .. col("status.warning", "[Displaces Lower Prio]")) or ""
      local cStr = opt.isActiveDeficitKnown and ns.Compat.FormatCopper(opt.activeDeficitEstimate) or "Unpriced"
      local rVal = opt.isPriced and ns.Compat.FormatCopper(opt.replacementEstimate) or "Unpriced"
      safeAddDoubleLine(
        tooltip,
        string.format("  Opt #%d: %s%s%s", opt.optionIndex, formatOptionMaterialsShort(opt), rTag, dTag),
        string.format("Est. Buy: %s · Val: %s", cStr, rVal),
        priR, priG, priB, secR, secG, secB
      )
    end
  elseif kind == "writ" then
    tooltip:AddLine(
      col("status.warning", tostring(eval.limitationNotice or "Finished item reserved; crafting reagents are not protected.")),
      wrnR, wrnG, wrnB, true
    )
  else
    local altNote = (eval.altSoulboundCrates and eval.altSoulboundCrates > 0)
      and string.format(" · Alt Crates: %d (soulbound)", eval.altSoulboundCrates)
      or ""
    tooltip:AddLine(
      col("text.muted", "Turn-in: Merchant's Favor (0 rep; intro Shipping Label = 2,000 rep)" .. altNote .. "."),
      mutR, mutG, mutB, true
    )
  end
end

local function appendMaterialTooltip(tooltip, itemID, matRecord)
  local status = ns.Domain.Reservations.GetMaterialStatus(itemID)
  if not status then
    return
  end

  local priR, priG, priB = unpackRGB("text.primary", 0.93, 0.91, 0.86)
  local secR, secG, secB = unpackRGB("text.secondary", 0.74, 0.77, 0.80)
  local rsvR, rsvG, rsvB = unpackRGB("status.reserved", 0.56, 0.75, 0.89)

  -- Line 1: Reservation-aware stock summary (never says "safe to vendor")
  local lineColorR, lineColorG, lineColorB = priR, priG, priB
  if status.reservedTotal > 0 then
    lineColorR, lineColorG, lineColorB = rsvR, rsvG, rsvB
  end
  tooltip:AddLine(
    string.format("%s %s", col("accent.gold", "ForeverHub:"), status.summaryText),
    lineColorR, lineColorG, lineColorB, true
  )

  -- Line 2: Usage count + unit price + freshness + alt visibility
  local usages = matRecord.usages or {}
  local pInfo = ns.Providers.Auctionator and ns.Providers.Auctionator.GetItemPriceInfo(itemID)
  local priceTag = ""
  if pInfo and pInfo.unitPrice then
    local fTag = pInfo.isStale and " (stale)" or (pInfo.isUnknownAge and " (age >21d)" or "")
    priceTag = string.format(" · Est. AH unit: %s%s", ns.Compat.FormatCopper(pInfo.unitPrice), fTag)
  end

  local altTag = ""
  if (status.altEligibleCount or 0) > 0 or (status.altUnknownCount or 0) > 0 then
    local boundaryTag = status.altBoundaryNote and " [uncommitted alt est.]" or ""
    altTag = string.format(" · Alts: %d elig, %d unverified%s", status.altEligibleCount or 0, status.altUnknownCount or 0, boundaryTag)
  end

  if #usages > 0 then
    local firstUsage = usages[1]
    local moreCount = math.max(0, #usages - 1)
    local moreSuffix = (moreCount > 0) and string.format(" (+%d more; hold Shift)", moreCount) or ""
    tooltip:AddLine(
      string.format(
        "%s %dx for %s%s%s%s",
        col("text.secondary", "Used in:"),
        firstUsage.quantity or 1,
        firstUsage.targetName or "Crate",
        moreSuffix,
        priceTag,
        altTag
      ),
      secR, secG, secB, true
    )
  end

  if IsShiftKeyDown and IsShiftKeyDown() and #usages > 1 then
    local maxLines = math.min(#usages, 5)
    for i = 1, maxLines do
      local u = usages[i]
      safeAddDoubleLine(
        tooltip,
        string.format("  · %s (Opt #%d)", u.targetName, u.optionIndex or 1),
        string.format("%dx required", u.quantity or 1),
        priR, priG, priB, secR, secG, secB
      )
    end
  end
end

local function appendSealedCrateTooltip(tooltip, sealedRecord)
  if not sealedRecord then
    return
  end
  local rdyR, rdyG, rdyB = unpackRGB("status.ready", 0.49, 0.83, 0.64)
  local mutR, mutG, mutB = unpackRGB("text.muted", 0.57, 0.62, 0.66)
  tooltip:AddLine(
    string.format(
      "%s %s (%s Tier) · %s",
      col("accent.gold", "ForeverHub:"),
      tostring(sealedRecord.name or "Sealed Crate"),
      tostring(sealedRecord.tier or "Crate"),
      col("status.ready", "Ready for Delivery")
    ),
    rdyR, rdyG, rdyB, true
  )
  tooltip:AddLine(
    col("text.muted", "Deliver to Marcy Baker (Alliance) or Dokimi (Horde) for Merchant's Favor."),
    mutR, mutG, mutB, true
  )
end

local function isSecretValue(v)
  return v ~= nil and ns.Compat ~= nil and type(ns.Compat.IsSecretOrRestrictedValue) == "function" and ns.Compat.IsSecretOrRestrictedValue(v)
end

local function isTooltipSafeToAccess(tt)
  if type(tt) ~= "table" or isSecretValue(tt) then
    return false
  end
  if type(tt.IsForbidden) == "function" then
    local okF, forbidden = pcall(tt.IsForbidden, tt)
    if not okF or isSecretValue(forbidden) or forbidden == true then
      return false
    end
  end
  return true
end

local function extractPublicPositiveInt(v)
  if v == nil or isSecretValue(v) or type(v) ~= "number" then
    return nil
  end
  if v ~= v or v <= 0 or v >= math.huge then
    return nil
  end
  return math.floor(v)
end

local function extractPublicNonNegInt(v)
  if v == nil or isSecretValue(v) or type(v) ~= "number" then
    return nil
  end
  if v ~= v or v < 0 or v >= math.huge then
    return nil
  end
  return math.floor(v)
end

local function getTooltipLineCount(tt)
  if type(tt.NumLines) == "function" then
    local okN, n = pcall(tt.NumLines, tt)
    if okN and not isSecretValue(n) and type(n) == "number" and n >= 0 then
      return math.floor(n)
    end
  end
  if type(tt.__lines) == "table" then
    return #tt.__lines
  end
  return nil
end

local function clearTooltipRenderState(self)
  if type(self) ~= "table" or isSecretValue(self) then
    return
  end
  self.__fhLastRenderKey = nil
  self.__fhRenderedLineCount = nil
  self.__fhLastTooltipData = nil
  self.__fhLastItemLink = nil
  self.__fhLastItemID = nil
  self.__fhSourceKind = "unknown"
  self.__fhBagID = nil
  self.__fhSlotID = nil
  self.__fhHyperlink = nil
end

function Tooltips.OnTooltipSetItem(tooltip, explicitItemID)
  if not isTooltipSafeToAccess(tooltip) then
    return
  end

  -- Detect if C++/Lua cleared & rebuilt the tooltip without firing OnTooltipCleared/OnHide
  local curLineCount = getTooltipLineCount(tooltip)
  if curLineCount ~= nil and tooltip.__fhRenderedLineCount ~= nil and curLineCount < tooltip.__fhRenderedLineCount then
    clearTooltipRenderState(tooltip)
  end

  local itemID = extractPublicPositiveInt(explicitItemID)
  local itemLink = nil
  if type(tooltip.GetItem) == "function" then
    local okGet, _, link = pcall(tooltip.GetItem, tooltip)
    if okGet and not isSecretValue(link) and type(link) == "string" then
      itemLink = link
    end
  end
  if not itemID and itemLink and ns.Compat and ns.Compat.ExtractItemID then
    itemID = ns.Compat.ExtractItemID(itemLink)
  end
  if not itemID then
    return
  end

  local shiftState = (IsShiftKeyDown and IsShiftKeyDown()) and "1" or "0"
  local invRev, resRev, priceRev = 1, 1, 1
  if ns.State and ns.State.GetRevisions then
    invRev, resRev, priceRev = ns.State.GetRevisions()
  end
  local acqMode = (ns.State and ns.State.GetAcquisitionMode and ns.State.GetAcquisitionMode()) or "after_bank"
  local renderKey = string.format("%d:%s:%d:%d:%d:%s", itemID, shiftState, invRev, resRev, priceRev, acqMode)
  if tooltip.__fhLastRenderKey == renderKey then
    return
  end
  tooltip.__fhLastRenderKey = renderKey
  tooltip.__fhLastItemLink = itemLink
  tooltip.__fhLastItemID = itemID

  local beforeCount = curLineCount or 0
  local crates = ns.Data and ns.Data.cratesByItemID
  local writs = ns.Data and ns.Data.writsByItemID
  local mats = ns.Data and ns.Data.materialToCrates
  local sealedCrates = ns.Data and ns.Data.sealedCratesByItemID

  local appended = false
  if crates and crates[itemID] then
    appendTargetTooltip(tooltip, "crate", crates[itemID])
    appended = true
  elseif writs and writs[itemID] then
    appendTargetTooltip(tooltip, "writ", writs[itemID])
    appended = true
  elseif mats and mats[itemID] then
    appendMaterialTooltip(tooltip, itemID, mats[itemID])
    appended = true
  elseif sealedCrates and sealedCrates[itemID] then
    appendSealedCrateTooltip(tooltip, sealedCrates[itemID])
    appended = true
  end
  if appended then
    local afterCount = getTooltipLineCount(tooltip)
    tooltip.__fhRenderedLineCount = afterCount or (beforeCount + 1)
    if type(tooltip.Show) == "function" then
      pcall(tooltip.Show, tooltip)
    end
  end
end

local function resolveSupportedBagSlotFromOwner(tt)
  if type(tt.GetOwner) ~= "function" then
    return nil, nil
  end
  local okO, owner = pcall(tt.GetOwner, tt)
  if not okO or type(owner) ~= "table" or isSecretValue(owner) then
    return nil, nil
  end
  if type(owner.IsForbidden) == "function" then
    local okF, forbidden = pcall(owner.IsForbidden, owner)
    if not okF or forbidden == true then
      return nil, nil
    end
  end
  if type(owner.GetBagID) == "function" and type(owner.GetID) == "function" then
    local okB, rawBag = pcall(owner.GetBagID, owner)
    local okS, rawSlot = pcall(owner.GetID, owner)
    if okB and okS then
      local bagID = extractPublicNonNegInt(rawBag)
      local slotID = extractPublicPositiveInt(rawSlot)
      if bagID ~= nil and slotID ~= nil then
        return bagID, slotID
      end
    end
  end
  return nil, nil
end

local function refreshSingleTooltip(tt)
  if not isTooltipSafeToAccess(tt) or type(tt.IsShown) ~= "function" then
    return
  end
  local okShown, shown = pcall(tt.IsShown, tt)
  if not okShown or isSecretValue(shown) or shown ~= true then
    return
  end

  local srcKind = tt.__fhSourceKind or "unknown"

  -- 1) Confirmed bag-slot source (either recorded via SetBagItem or explicit ContainerFrameItemButton owner methods)
  if type(tt.SetBagItem) == "function" then
    local bagID, slotID = nil, nil
    if srcKind == "bag" and tt.__fhBagID ~= nil and tt.__fhSlotID ~= nil then
      bagID, slotID = tt.__fhBagID, tt.__fhSlotID
    elseif srcKind == "unknown" then
      bagID, slotID = resolveSupportedBagSlotFromOwner(tt)
    end
    if bagID ~= nil and slotID ~= nil then
      clearTooltipRenderState(tt)
      pcall(tt.SetBagItem, tt, bagID, slotID)
      return
    end
  end

  -- 2) Confirmed hyperlink source ONLY (never replace contextual Merchant/Quest/Inventory tooltips with a generic hyperlink!)
  if srcKind == "hyperlink" and type(tt.__fhHyperlink) == "string" and tt.__fhHyperlink ~= "" and type(tt.SetHyperlink) == "function" then
    local savedLink = tt.__fhHyperlink
    clearTooltipRenderState(tt)
    pcall(tt.SetHyperlink, tt, savedLink)
  end
end

function Tooltips.RefreshActiveTooltips()
  refreshSingleTooltip(_G.GameTooltip)
  refreshSingleTooltip(_G.ItemRefTooltip)
end

local function safeHookScript(frame, scriptName, handler)
  if not frame or type(frame.HookScript) ~= "function" then
    return false
  end
  if type(frame.HasScript) == "function" then
    local okHas, supported = pcall(frame.HasScript, frame, scriptName)
    if not okHas or not supported then
      return false
    end
  end
  local okHook = pcall(frame.HookScript, frame, scriptName, handler)
  return okHook == true
end

function Tooltips.Init()
  local useDataProcessor = false
  if type(TooltipDataProcessor) == "table"
    and type(TooltipDataProcessor.AddTooltipPostCall) == "function"
    and type(Enum) == "table"
    and type(Enum.TooltipDataType) == "table"
    and Enum.TooltipDataType.Item ~= nil
  then
    if Tooltips._dataProcessorHooked then
      useDataProcessor = true
    else
      local okProc = pcall(
        TooltipDataProcessor.AddTooltipPostCall,
        Enum.TooltipDataType.Item,
        function(tooltip, data)
          if not isTooltipSafeToAccess(tooltip) then
            return
          end
          if tooltip ~= _G.GameTooltip and tooltip ~= _G.ItemRefTooltip and not tooltip.__fhHooked then
            return
          end
          if data == nil or isSecretValue(data) or type(data) ~= "table" then
            return
          end

          local curLines = getTooltipLineCount(tooltip)
          local lineCountDropped = (curLines ~= nil and tooltip.__fhRenderedLineCount ~= nil and curLines < tooltip.__fhRenderedLineCount)
          local okSame, isSameData = pcall(function()
            return data == tooltip.__fhLastTooltipData
          end)
          local isNewBuild = lineCountDropped or (okSame and not isSameData)
          if isNewBuild then
            -- New tooltip build started before any post-hooks run: reset stale source & render markers
            clearTooltipRenderState(tooltip)
            tooltip.__fhLastTooltipData = data
          end

          local explicitID = nil
          local okId, rawId = pcall(function()
            return data.id
          end)
          if okId and not isSecretValue(rawId) then
            explicitID = extractPublicPositiveInt(tonumber(rawId))
          end
          Tooltips.OnTooltipSetItem(tooltip, explicitID)
        end
      )
      if okProc then
        Tooltips._dataProcessorHooked = true
        useDataProcessor = true
      end
    end
  end

  local function hookTooltip(tt)
    if not isTooltipSafeToAccess(tt) or tt.__fhHooked then
      return
    end
    tt.__fhHooked = true
    if type(hooksecurefunc) == "function" then
      if type(tt.ClearLines) == "function" then
        pcall(hooksecurefunc, tt, "ClearLines", clearTooltipRenderState)
      end
      if type(tt.SetBagItem) == "function" then
        pcall(hooksecurefunc, tt, "SetBagItem", function(self, bagID, slotID)
          if not isTooltipSafeToAccess(self) then
            return
          end
          local b = not isSecretValue(bagID) and extractPublicNonNegInt(tonumber(bagID)) or nil
          local s = not isSecretValue(slotID) and extractPublicPositiveInt(tonumber(slotID)) or nil
          if b ~= nil and s ~= nil then
            -- Post-hook runs AFTER TooltipDataProcessor/OnTooltipSetItem: record source WITHOUT clearing __fhLastRenderKey!
            self.__fhSourceKind = "bag"
            self.__fhBagID = b
            self.__fhSlotID = s
            self.__fhHyperlink = nil
          end
        end)
      end
      if type(tt.SetHyperlink) == "function" then
        pcall(hooksecurefunc, tt, "SetHyperlink", function(self, link)
          if not isTooltipSafeToAccess(self) then
            return
          end
          if not isSecretValue(link) and type(link) == "string" and link ~= "" then
            self.__fhSourceKind = "hyperlink"
            self.__fhHyperlink = link
            self.__fhBagID = nil
            self.__fhSlotID = nil
          end
        end)
      end
    end
    if not useDataProcessor then
      safeHookScript(tt, "OnTooltipSetItem", function(self)
        Tooltips.OnTooltipSetItem(self)
      end)
    end
    safeHookScript(tt, "OnTooltipCleared", clearTooltipRenderState)
    safeHookScript(tt, "OnHide", clearTooltipRenderState)
  end

  hookTooltip(_G.GameTooltip)
  hookTooltip(_G.ItemRefTooltip)
end
