local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.Domain = ns.Domain or {}

local AuctionPostMath = {}
ns.Domain.AuctionPostMath = AuctionPostMath

AuctionPostMath.SCHEMA = "foreverhub-auction-post-math-v1"
AuctionPostMath.FOREVER_DURATION_HOURS = {
  [1] = 2,
  [2] = 8,
  [3] = 24,
}
AuctionPostMath.BREAK_EVEN_CAPTION = "Break-even sale chance for one listing, then vendor if unsold"

local MAX_SAFE_INT = 9007199254740991

local function isPositiveInt(v)
  return type(v) == "number" and v == v and v >= 1 and v <= MAX_SAFE_INT and math.floor(v) == v
end

local function isNonNegInt(v)
  return type(v) == "number" and v == v and v >= 0 and v <= MAX_SAFE_INT and math.floor(v) == v
end

local function resolveClientBuild(explicitBuild)
  if type(explicitBuild) == "string" and explicitBuild ~= "" then
    return explicitBuild
  end
  if ns.Compat and type(ns.Compat.ProbeEconomyRuntimeCapabilities) == "function" then
    local ok, cap = pcall(ns.Compat.ProbeEconomyRuntimeCapabilities)
    if ok and type(cap) == "table" and type(cap.client) == "table" and type(cap.client.build) == "string" then
      local v = tostring(cap.client.version or "")
      local b = tostring(cap.client.build or "")
      if v ~= "" and b ~= "" and not string.find(b, "%.", 1) then
        return v .. "." .. b
      elseif b ~= "" then
        return b
      end
    end
  end
  if type(_G.GetBuildInfo) == "function" then
    local ok, ver, buildNum = pcall(_G.GetBuildInfo)
    if ok then
      local v = tostring(ver or "")
      local b = tostring(buildNum or "")
      if v ~= "" and b ~= "" and not string.find(b, "%.", 1) then
        return v .. "." .. b
      elseif b ~= "" then
        return b
      end
    end
  end
  return "UNKNOWN_BUILD"
end

-- ============================================================================
-- 1. Venue Identity Classifier (`P0-2`, `P0-3`, `P1` State Machine)
-- Never infers house identity from `uiMapID` alone or from fee percentages!
-- ============================================================================

function AuctionPostMath.ClassifyOpenVenue(ctx)
  ctx = type(ctx) == "table" and ctx or {}
  local build = resolveClientBuild(ctx.clientBuild)
  local sessionID = isPositiveInt(tonumber(ctx.sessionID)) and tonumber(ctx.sessionID) or 1

  -- Path A: Explicit verified native market/venue key (`m1:wowf:...`):
  if type(ctx.verifiedNativeVenueKey) == "string" and string.find(ctx.verifiedNativeVenueKey, "^m1:") then
    return {
      venueVerified = true,
      venueStatus = "VERIFIED_NATIVE_VENUE",
      venueIdentity = ctx.verifiedNativeVenueKey,
      houseScope = string.find(ctx.verifiedNativeVenueKey, ":neutral$") and "neutral" or "faction",
      clientBuild = build,
    }
  end

  -- Path B: Build-specific verified auctioneer creature NPC ID (`uiMapID` is corroboration only):
  local npcID = tonumber(ctx.verifiedNpcID)
  if not isPositiveInt(npcID) and type(ctx.npcGuid) == "string" and ns.Compat and type(ns.Compat.ParseCreatureGUIDSafe) == "function" then
    local parsed = ns.Compat.ParseCreatureGUIDSafe(ctx.npcGuid)
    if parsed and parsed.status == "VERIFIED_NPC_GUID" then
      npcID = parsed.npcID
    end
  end

  local buildMap = type(ctx.verifiedAuctioneerNpcMap) == "table" and ctx.verifiedAuctioneerNpcMap[build] or nil
  if isPositiveInt(npcID) and type(buildMap) == "table" and type(buildMap[npcID]) == "table" then
    local entry = buildMap[npcID]
    local mapMatches = (entry.expectedUiMapID == nil) or (tonumber(ctx.uiMapID) == tonumber(entry.expectedUiMapID))
    if mapMatches and type(entry.venueKey) == "string" and string.find(entry.venueKey, "^m1:") then
      return {
        venueVerified = true,
        venueStatus = "VERIFIED_AUCTIONEER_NPC",
        venueIdentity = entry.venueKey,
        houseScope = tostring(entry.houseScope or (string.find(entry.venueKey, ":neutral$") and "neutral" or "faction")),
        npcID = npcID,
        clientBuild = build,
      }
    end
  end

  -- Fallback: Session-isolated `UNKNOWN_AH` (`P0-3` — never shared across AH sessions!)
  return {
    venueVerified = false,
    venueStatus = "UNKNOWN_AH",
    venueIdentity = string.format("UNKNOWN_AH:session:%d", sessionID),
    houseScope = "unknown",
    clientBuild = build,
  }
end

-- ============================================================================
-- 2. AH Post Session State Machine (`CLOSED -> OPEN_UNCLASSIFIED -> SELECTION_PENDING -> SNAPSHOT_READY -> QUOTE_READY`)
-- ============================================================================

function AuctionPostMath.CreateSessionController()
  local ctrl = {
    state = "CLOSED",
    sessionID = 0,
    selectionRevision = 0,
    venue = nil,
    snapshot = nil,
    quotesByDuration = {},
    lastFingerprint = nil,
  }

  function ctrl:Open(venueCtx)
    self.sessionID = self.sessionID + 1
    self.selectionRevision = 1
    self.quotesByDuration = {}
    self.snapshot = nil
    self.lastFingerprint = nil

    local vInput = type(venueCtx) == "table" and venueCtx or {}
    vInput.sessionID = self.sessionID
    self.venue = AuctionPostMath.ClassifyOpenVenue(vInput)
    self.state = self.venue.venueVerified and "SELECTION_PENDING" or "OPEN_UNCLASSIFIED"

    if ns.State and type(ns.State.BeginOpenAhSession) == "function" then
      ns.State.BeginOpenAhSession({
        venueIdentity = self.venue.venueVerified and self.venue.venueIdentity or nil,
        venueVerified = self.venue.venueVerified,
        clientBuild = self.venue.clientBuild,
      })
    end
    return self.state
  end

  function ctrl:UpdateSelection(sel)
    if self.state == "CLOSED" then
      return self.state, "ah_closed"
    end
    if type(sel) ~= "table" then
      self.selectionRevision = self.selectionRevision + 1
      self.quotesByDuration = {}
      self.snapshot = nil
      self.lastFingerprint = nil
      self.state = self.venue and self.venue.venueVerified and "SELECTION_PENDING" or "OPEN_UNCLASSIFIED"
      if ns.State and type(ns.State.BumpAhSelectionRevision) == "function" then
        ns.State.BumpAhSelectionRevision()
      end
      return self.state
    end

    local fp = string.format(
      "%s|%s|%s|%s|%s|%s|%s|%s",
      tostring(self.venue and self.venue.venueIdentity or "UNKNOWN"),
      tostring(sel.activeTab or "sell"),
      tostring(sel.itemKey or ""),
      tostring(sel.stackSize or ""),
      tostring(sel.numStacks or ""),
      tostring(sel.startingBidPerLotCopper or ""),
      tostring(sel.buyoutPerLotCopper or ""),
      tostring(sel.durationIndex or "")
    )
    if fp ~= self.lastFingerprint then
      self.selectionRevision = self.selectionRevision + 1
      self.quotesByDuration = {}
      self.lastFingerprint = fp
      if ns.State and type(ns.State.BumpAhSelectionRevision) == "function" then
        ns.State.BumpAhSelectionRevision()
      end
    end

    local hasCompleteSnapshot = (type(sel.itemKey) == "string" and sel.itemKey ~= "" and not string.find(sel.itemKey, "^i1:unk_var:"))
      and isPositiveInt(tonumber(sel.stackSize))
      and isPositiveInt(tonumber(sel.numStacks))
      and isNonNegInt(tonumber(sel.startingBidPerLotCopper))
      and isNonNegInt(tonumber(sel.buyoutPerLotCopper or 0))
      and (tonumber(sel.startingBidPerLotCopper) > 0 or tonumber(sel.buyoutPerLotCopper or 0) > 0)

    if not hasCompleteSnapshot then
      self.snapshot = nil
      self.quotesByDuration = {}
      self.state = (self.venue and self.venue.venueVerified) and "SELECTION_PENDING" or "OPEN_UNCLASSIFIED"
      return self.state
    end

    self.snapshot = {
      itemID = tonumber(sel.itemID),
      itemKey = sel.itemKey,
      stackSize = tonumber(sel.stackSize),
      numStacks = tonumber(sel.numStacks),
      startingBidPerLotCopper = tonumber(sel.startingBidPerLotCopper),
      buyoutPerLotCopper = tonumber(sel.buyoutPerLotCopper or 0),
      durationIndex = tonumber(sel.durationIndex) or 2,
      unitVendorCopper = sel.unitVendorCopper,
      isSoulbound = (sel.isSoulbound == true),
      synchronizedSource = tostring(sel.synchronizedSource or "manual_scenario"),
      selectionRevision = self.selectionRevision,
    }
    self.state = "SNAPSHOT_READY"
    return self.state
  end

  function ctrl:AttachQuotes(quotesByDuration)
    if self.state ~= "SNAPSHOT_READY" and self.state ~= "QUOTE_READY" then
      return self.state, "snapshot_not_ready"
    end
    if type(quotesByDuration) ~= "table" or next(quotesByDuration) == nil then
      return self.state, "empty_quotes"
    end
    self.quotesByDuration = {}
    local snap = self.snapshot
    for durIdx, q in pairs(quotesByDuration) do
      if type(q) == "table" and isNonNegInt(tonumber(q.perLotDepositCopper)) and isNonNegInt(tonumber(q.batchDepositCopper)) then
        self.quotesByDuration[durIdx] = q
        if ns.State and type(ns.State.RecordOpenAhDepositQuote) == "function" and snap then
          local activeSessRev = (type(ns.State.currentAhSession) == "table" and tonumber(ns.State.currentAhSession.selectionRevision))
            or self.selectionRevision
          ns.State.RecordOpenAhDepositQuote({
            clientBuild = self.venue and self.venue.clientBuild or nil,
            venueIdentity = self.venue and self.venue.venueIdentity or nil,
            venueVerified = self.venue and self.venue.venueVerified or false,
            selectionRevision = activeSessRev,
            itemKey = snap.itemKey,
            durationIndex = durIdx,
            stackSize = snap.stackSize,
            numStacks = snap.numStacks,
            startingBid = snap.startingBidPerLotCopper,
            buyoutPerStack = snap.buyoutPerLotCopper,
            quotedDepositCopper = (snap.numStacks == 1) and q.perLotDepositCopper or q.batchDepositCopper,
          })
        end
      end
    end
    if next(self.quotesByDuration) ~= nil then
      self.state = "QUOTE_READY"
    end
    return self.state
  end

  function ctrl:Close()
    self.state = "CLOSED"
    self.venue = nil
    self.snapshot = nil
    self.quotesByDuration = {}
    self.lastFingerprint = nil
    if ns.State and type(ns.State.EndOpenAhSession) == "function" then
      ns.State.EndOpenAhSession()
    end
    return self.state
  end

  return ctrl
end

-- ============================================================================
-- 3. Live `GetAuctionDeposit` Query with Batch/Per-Lot Semantics Guard (`P0-1`)
-- ============================================================================

function AuctionPostMath.QueryLiveDepositForDuration(params)
  if type(params) ~= "table" then
    return { ok = false, status = "INVALID_PARAMS" }
  end
  if ns.Compat and type(ns.Compat.IsInCombat) == "function" and ns.Compat.IsInCombat() then
    return { ok = false, status = "COMBAT_DEFERRED" }
  end
  local getDep = params.getAuctionDepositFn or _G.GetAuctionDeposit
  if type(getDep) ~= "function" then
    return { ok = false, status = "API_UNAVAILABLE" }
  end
  if params.slottedItemVerified ~= true then
    return { ok = false, status = "SLOTTED_ITEM_UNVERIFIED" }
  end

  local durIdx = tonumber(params.durationIndex)
  local startBid = tonumber(params.startingBidPerLotCopper)
  local buyout = tonumber(params.buyoutPerLotCopper or 0)
  local stackSize = tonumber(params.stackSize)
  local numStacks = tonumber(params.numStacks)
  if (durIdx ~= 1 and durIdx ~= 2 and durIdx ~= 3)
    or not isNonNegInt(startBid)
    or not isNonNegInt(buyout)
    or not isPositiveInt(stackSize)
    or not isPositiveInt(numStacks)
  then
    return { ok = false, status = "INVALID_QUOTE_ARGUMENTS" }
  end

  local okSingle, dSingle = pcall(getDep, durIdx, startBid, buyout, stackSize, 1)
  if not okSingle or not isNonNegInt(tonumber(dSingle)) then
    return { ok = false, status = "QUOTE_CALL_FAILED" }
  end
  dSingle = math.floor(tonumber(dSingle))

  if numStacks == 1 then
    return {
      ok = true,
      status = "QUOTE_VERIFIED",
      durationIndex = durIdx,
      foreverDisplayHours = AuctionPostMath.FOREVER_DURATION_HOURS[durIdx],
      depositSemantics = "EXACT_SINGLE_LOT",
      perLotDepositCopper = dSingle,
      batchDepositCopper = dSingle,
    }
  end

  local okBatch, dMulti = pcall(getDep, durIdx, startBid, buyout, stackSize, numStacks)
  if not okBatch or not isNonNegInt(tonumber(dMulti)) then
    return { ok = false, status = "MULTI_STACK_QUOTE_FAILED" }
  end
  dMulti = math.floor(tonumber(dMulti))

  local explicitSemantics = params.verifiedMultiStackSemantics
  if explicitSemantics == "BATCH_TOTAL" or (dSingle > 0 and dMulti == (dSingle * numStacks)) then
    return {
      ok = true,
      status = "QUOTE_VERIFIED",
      durationIndex = durIdx,
      foreverDisplayHours = AuctionPostMath.FOREVER_DURATION_HOURS[durIdx],
      depositSemantics = "BATCH_TOTAL",
      perLotDepositCopper = dSingle,
      batchDepositCopper = dMulti,
    }
  elseif explicitSemantics == "PER_LOT" then
    return {
      ok = true,
      status = "QUOTE_VERIFIED",
      durationIndex = durIdx,
      foreverDisplayHours = AuctionPostMath.FOREVER_DURATION_HOURS[durIdx],
      depositSemantics = "PER_LOT",
      perLotDepositCopper = dMulti,
      batchDepositCopper = dMulti * numStacks,
    }
  elseif dSingle == 0 and dMulti == 0 then
    return {
      ok = true,
      status = "QUOTE_VERIFIED",
      durationIndex = durIdx,
      foreverDisplayHours = AuctionPostMath.FOREVER_DURATION_HOURS[durIdx],
      depositSemantics = "ZERO_DEPOSIT",
      perLotDepositCopper = 0,
      batchDepositCopper = 0,
    }
  end

  -- Ambiguous multi-stack return (e.g. `dMulti == dSingle` when `dSingle > 0` without verified probe rule): fail closed!
  return {
    ok = false,
    status = "UNVERIFIED_MULTI_STACK_SEMANTICS",
    durationIndex = durIdx,
    observedSingleStackCopper = dSingle,
    observedMultiStackCopper = dMulti,
  }
end

-- ============================================================================
-- 4. Break-Even Sale Probability (`p*`) & Finite Changing-Price Schedule (`P1`)
-- ============================================================================

function AuctionPostMath.ComputeOneTryBreakEvenSaleProbability(netSaleKeepCopper, vendorValueCopper, failedDepositLossCopper)
  local N = tonumber(netSaleKeepCopper)
  local V = tonumber(vendorValueCopper)
  local D = tonumber(failedDepositLossCopper)

  if not isNonNegInt(N) or not isNonNegInt(V) or not isNonNegInt(D) then
    return {
      status = "INCOMPLETE_INPUTS",
      caption = AuctionPostMath.BREAK_EVEN_CAPTION,
      prescribesShorterDuration = false,
      pStar = nil,
    }
  end

  if N == 0 and V == 0 and D == 0 then
    return {
      status = "CASH_INDIFFERENT",
      caption = AuctionPostMath.BREAK_EVEN_CAPTION,
      prescribesShorterDuration = false,
      pStar = nil,
      label = "Cash-indifferent (0c net keep, 0c vendor value, 0c deposit)",
    }
  end

  if N < V then
    return {
      status = "BELOW_VENDOR_ALTERNATIVE",
      caption = AuctionPostMath.BREAK_EVEN_CAPTION,
      prescribesShorterDuration = false,
      pStar = nil,
      shortfallVsVendorCopper = V - N,
      label = "Below client vendor value even if sold on first listing",
    }
  end

  if N == V then
    if D == 0 then
      return {
        status = "NO_PROCEEDS_ADVANTAGE_ZERO_DEPOSIT",
        caption = AuctionPostMath.BREAK_EVEN_CAPTION,
        prescribesShorterDuration = false,
        pStar = nil,
        label = "Matches client vendor value (0c upside; 0c deposit)",
      }
    end
    return {
      status = "NO_PROCEEDS_ADVANTAGE",
      caption = AuctionPostMath.BREAK_EVEN_CAPTION,
      prescribesShorterDuration = false,
      pStar = nil,
      label = "Matches client vendor value on sale, but loses deposit if unsold",
    }
  end

  -- Here strictly `N > V`:
  local upside = N - V
  if D == 0 then
    return {
      status = "ZERO_DEPOSIT_THRESHOLD",
      caption = AuctionPostMath.BREAK_EVEN_CAPTION,
      prescribesShorterDuration = false,
      pStar = 0,
      pStarPct = 0,
      numerator = 0,
      denominator = upside,
      label = "0.0% — 0c deposit risk; any positive sale chance beats vendor",
    }
  end

  local denom = upside + D
  local pStar = D / denom
  local pStarPct = (D * 100.0) / denom
  return {
    status = "COMPUTED",
    caption = AuctionPostMath.BREAK_EVEN_CAPTION,
    prescribesShorterDuration = false,
    pStar = pStar,
    pStarPct = pStarPct,
    numerator = D,
    denominator = denom,
    label = string.format("%.1f%% (%s)", pStarPct, AuctionPostMath.BREAK_EVEN_CAPTION),
  }
end

-- Finite changing-price repost recurrence:
--   EV_{k+1} = V
--   EV_j     = p_j * N_j + (1 - p_j) * (EV_{j+1} - D_j)
function AuctionPostMath.EvaluateFiniteRepostSchedule(steps, terminalVendorCopper)
  local V = tonumber(terminalVendorCopper)
  if not isNonNegInt(V) or type(steps) ~= "table" or #steps == 0 or #steps > 20 then
    return {
      status = "INVALID_SCHEDULE",
      isUserAssumedScenario = true,
      expectedValueCopper = nil,
    }
  end

  local parsed = {}
  for idx, st in ipairs(steps) do
    if type(st) ~= "table" then
      return { status = "INVALID_SCHEDULE_STEP", stepIndex = idx }
    end
    local N = tonumber(st.netKeepCopper)
    local D = tonumber(st.depositLossCopper)
    local p = tonumber(st.assumedSaleProb)
    if p == nil and st.assumedSaleProbBps ~= nil then
      local bps = tonumber(st.assumedSaleProbBps)
      if type(bps) == "number" and bps == bps and bps >= 0 and bps <= 10000 then
        p = bps / 10000.0
      end
    end
    if not isNonNegInt(N) or not isNonNegInt(D) or type(p) ~= "number" or p ~= p or p < 0 or p > 1 then
      return { status = "INVALID_SCHEDULE_STEP", stepIndex = idx }
    end
    parsed[idx] = { netKeepCopper = N, depositLossCopper = D, p = p }
  end

  local evNext = V
  local stepEVs = {}
  for j = #parsed, 1, -1 do
    local s = parsed[j]
    local evHere = (s.p * s.netKeepCopper) + ((1.0 - s.p) * (evNext - s.depositLossCopper))
    stepEVs[j] = evHere
    evNext = evHere
  end

  return {
    status = "SCENARIO_COMPUTED",
    isUserAssumedScenario = true,
    prescribesShorterDuration = false,
    terminalVendorCopper = V,
    expectedValueCopper = stepEVs[1],
    vsImmediateVendorDeltaCopper = stepEVs[1] - V,
    stepExpectedValues = stepEVs,
  }
end

-- ============================================================================
-- 5. Deterministic Lot & Batch Posting Evaluator (`EvaluatePostingScenario`)
-- Rounds commission PER LOT (`N_batch = m * (G_lot - C(G_lot))`), checks both
-- `minBid` and `buyout` against vendor (`BID_FLOOR_LOSS`), never subtracts
-- refundable deposits from sale proceeds (`P0-2`), and never guesses fees!
-- ============================================================================

local function computeLotCommission(grossLotCopper, commissionRule)
  if type(commissionRule) ~= "table" or commissionRule.verified ~= true or commissionRule.venueVerified ~= true then
    return nil, "commission_rule_unverified"
  end
  local num = tonumber(commissionRule.commissionNumerator)
  local den = tonumber(commissionRule.commissionDenominator)
  if not isNonNegInt(num) or not isPositiveInt(den) or num >= den then
    return nil, "invalid_commission_fraction"
  end
  local mode = (commissionRule.roundingMode == "floor") and "floor" or "half_up"
  if den == 10000 and ns.Domain.MarketAccounting and type(ns.Domain.MarketAccounting.ComputeCommissionCopper) == "function" then
    return ns.Domain.MarketAccounting.ComputeCommissionCopper(grossLotCopper, num, mode)
  end
  local q = math.floor(grossLotCopper / den)
  local rem = grossLotCopper - (q * den)
  local qScaled = q * num
  local remProd = rem * num
  local remScaled = (mode == "floor") and math.floor(remProd / den) or math.floor((remProd + math.floor(den / 2)) / den)
  return qScaled + remScaled, nil
end

function AuctionPostMath.EvaluatePostingScenario(params)
  if type(params) ~= "table" then
    return { status = "INVALID_INPUT", actionable = false }
  end

  if params.isSoulbound == true or tonumber(params.bindType) == 1 or params.bindingStatus == "BOP" or params.bindingStatus == "QUEST" or params.bindingStatus == "ACCOUNT" then
    return {
      status = "NON_AUCTIONABLE_BOUND",
      actionable = false,
      reason = "item_is_bound_or_non_transferable",
    }
  end

  local stackSize = tonumber(params.stackSize)
  local numStacks = tonumber(params.numStacks)
  local bidLot = tonumber(params.startingBidPerLotCopper or 0)
  local buyoutLot = tonumber(params.buyoutPerLotCopper or 0)

  if not isPositiveInt(stackSize) or not isPositiveInt(numStacks) or not isNonNegInt(bidLot) or not isNonNegInt(buyoutLot) then
    return {
      status = "INCOMPLETE_LOT_PARAMETERS",
      actionable = false,
      reason = "missing_or_invalid_stack_or_price_integers",
    }
  end

  local isBidOnly = (buyoutLot == 0)
  if isBidOnly and bidLot <= 0 then
    return {
      status = "ZERO_PRICE_INPUT",
      actionable = false,
      reason = "both_bid_and_buyout_are_zero",
    }
  end
  if not isBidOnly and bidLot > buyoutLot then
    return {
      status = "INVALID_BID_EXCEEDS_BUYOUT",
      actionable = false,
      reason = "starting_bid_exceeds_buyout",
    }
  end
  if not isBidOnly and bidLot <= 0 then
    -- If caller specifies buyout without explicit minBid, treat minBid == buyout unless explicitly passed
    bidLot = buyoutLot
  end

  local totalUnits = stackSize * numStacks
  if totalUnits > MAX_SAFE_INT or (bidLot * numStacks) > MAX_SAFE_INT or (buyoutLot * numStacks) > MAX_SAFE_INT then
    return {
      status = "INTEGER_OVERFLOW_GUARD",
      actionable = false,
      reason = "copper_exceeds_safe_integer_ceiling",
    }
  end

  local vendorKnown = isNonNegInt(tonumber(params.unitVendorCopper)) and (params.vendorMetadataComplete ~= false)
  local unitVendor = vendorKnown and math.floor(tonumber(params.unitVendorCopper)) or nil
  local lotVendor = vendorKnown and (unitVendor * stackSize) or nil
  local batchVendor = vendorKnown and (lotVendor * numStacks) or nil

  local commissionRule = params.commissionRule
  local bidCommLot = computeLotCommission(bidLot, commissionRule)
  local commissionKnown = (bidCommLot ~= nil)

  local bidKeepLot = commissionKnown and math.max(0, bidLot - bidCommLot) or nil
  local bidKeepBatch = commissionKnown and (numStacks * bidKeepLot) or nil
  local bidBelowVendor = (commissionKnown and vendorKnown) and (bidKeepLot < lotVendor) or nil

  local buyoutScenario = nil
  if not isBidOnly then
    local boCommLot = computeLotCommission(buyoutLot, commissionRule)
    local boKeepLot = (boCommLot ~= nil) and math.max(0, buyoutLot - boCommLot) or nil
    local boKeepBatch = (boKeepLot ~= nil) and (numStacks * boKeepLot) or nil
    local boBelowVendor = (boKeepLot ~= nil and vendorKnown) and (boKeepLot < lotVendor) or nil
    buyoutScenario = {
      perUnitFloorCopper = math.floor(buyoutLot / stackSize),
      perUnitExact = ((buyoutLot % stackSize) == 0),
      perLotGrossCopper = buyoutLot,
      batchGrossCopper = buyoutLot * numStacks,
      perLotCommissionCopper = boCommLot,
      batchCommissionCopper = (boCommLot ~= nil) and (numStacks * boCommLot) or nil,
      perLotNetKeepExclDepositRefundCopper = boKeepLot,
      batchNetKeepExclDepositRefundCopper = boKeepBatch,
      belowVendor = boBelowVendor,
      advantageOverVendorBatchCopper = (boKeepBatch ~= nil and batchVendor ~= nil) and (boKeepBatch - batchVendor) or nil,
    }
  end

  local bidScenario = {
    perUnitFloorCopper = math.floor(bidLot / stackSize),
    perUnitExact = ((bidLot % stackSize) == 0),
    perLotGrossCopper = bidLot,
    batchGrossCopper = bidLot * numStacks,
    perLotCommissionCopper = bidCommLot,
    batchCommissionCopper = commissionKnown and (numStacks * bidCommLot) or nil,
    perLotNetKeepExclDepositRefundCopper = bidKeepLot,
    batchNetKeepExclDepositRefundCopper = bidKeepBatch,
    belowVendor = bidBelowVendor,
    advantageOverVendorBatchCopper = (bidKeepBatch ~= nil and batchVendor ~= nil) and (bidKeepBatch - batchVendor) or nil,
  }

  local bidFloorLossWarning = (bidBelowVendor == true) and (isBidOnly or bidLot < buyoutLot)
  local buyoutLossWarning = (buyoutScenario ~= nil and buyoutScenario.belowVendor == true)

  -- Detect classic "unit price typed into stack-price box" error (`s > 1`, `G_lot < V_lot` or `G_lot == unitPrice` suspicion):
  local primaryGrossLot = isBidOnly and bidLot or buyoutLot
  local suspectedUnitAsStackMistake = (stackSize > 1)
    and vendorKnown
    and (lotVendor > 0)
    and (primaryGrossLot < lotVendor)
    and ((primaryGrossLot * stackSize) >= lotVendor)

  -- Evaluate deposit exposure & optional 1-try break-even probability across provided durations (`1=2h, 2=8h, 3=24h`):
  local primaryKeepLot = isBidOnly and bidKeepLot or (buyoutScenario and buyoutScenario.perLotNetKeepExclDepositRefundCopper or nil)
  local durationEvaluations = {}
  local quotesByDuration = type(params.quotesByDuration) == "table" and params.quotesByDuration or {}

  for _, durIdx in ipairs({ 1, 2, 3 }) do
    local q = quotesByDuration[durIdx]
    if type(q) == "table" and isNonNegInt(tonumber(q.perLotDepositCopper)) and isNonNegInt(tonumber(q.batchDepositCopper)) then
      local perLotDep = math.floor(tonumber(q.perLotDepositCopper))
      local batchDep = math.floor(tonumber(q.batchDepositCopper))
      local beBuyout = (not isBidOnly and primaryKeepLot ~= nil and lotVendor ~= nil)
          and AuctionPostMath.ComputeOneTryBreakEvenSaleProbability(primaryKeepLot, lotVendor, perLotDep)
        or nil
      local beBid = (bidKeepLot ~= nil and lotVendor ~= nil)
          and AuctionPostMath.ComputeOneTryBreakEvenSaleProbability(bidKeepLot, lotVendor, perLotDep)
        or nil
      durationEvaluations[durIdx] = {
        durationIndex = durIdx,
        foreverDisplayHours = AuctionPostMath.FOREVER_DURATION_HOURS[durIdx],
        depositKnown = true,
        depositSemantics = tostring(q.depositSemantics or "VERIFIED"),
        perLotDepositCopper = perLotDep,
        batchDepositCopper = batchDep,
        refundableOnSale = true,
        lostOnExpiryOrCancel = true,
        breakEvenBuyout = beBuyout,
        breakEvenBid = beBid,
      }
    else
      durationEvaluations[durIdx] = {
        durationIndex = durIdx,
        foreverDisplayHours = AuctionPostMath.FOREVER_DURATION_HOURS[durIdx],
        depositKnown = false,
      }
    end
  end

  -- Purse / riding reserve impact check (`Reserves.lua`) for upfront batch deposit cash lock:
  local selectedDurIdx = tonumber(params.durationIndex) or 2
  local selDurEval = durationEvaluations[selectedDurIdx]
  local depositReserveWarning = nil
  if selDurEval and selDurEval.depositKnown and selDurEval.batchDepositCopper > 0 and ns.Domain.Reserves and type(ns.Domain.Reserves.CanAffordOutlay) == "function" then
    local canAfford, reason, snap = ns.Domain.Reserves.CanAffordOutlay(selDurEval.batchDepositCopper, params.reserveOpts)
    if not canAfford and type(snap) == "table" and snap.status == "ok" then
      depositReserveWarning = {
        code = "DEPOSIT_LOCKS_PROTECTED_PURSE",
        batchDepositCopper = selDurEval.batchDepositCopper,
        investableCopper = snap.investableCopper,
        summaryReason = reason,
      }
    end
  end

  local warningCodes = {}
  if buyoutLossWarning then
    table.insert(warningCodes, "BUYOUT_BELOW_VENDOR")
  end
  if bidFloorLossWarning then
    table.insert(warningCodes, "BID_FLOOR_LOSS")
  end
  if suspectedUnitAsStackMistake then
    table.insert(warningCodes, "SUSPECTED_UNIT_PRICE_ENTERED_AS_STACK")
  end
  if depositReserveWarning then
    table.insert(warningCodes, "DEPOSIT_LOCKS_PROTECTED_PURSE")
  end

  return {
    status = "OK",
    actionable = true,
    prescribesShorterDuration = false,
    synchronizedToForm = (params.synchronizedToForm == true),
    modeBanner = (params.synchronizedToForm == true)
      and "Synchronized read-only to open posting form"
      or "Scenario calculator — not synchronized to posting form",
    stackSize = stackSize,
    numStacks = numStacks,
    totalUnits = totalUnits,
    isBidOnly = isBidOnly,
    hasDistinctMinBid = (not isBidOnly and bidLot < buyoutLot),
    vendorKnown = vendorKnown,
    unitVendorCopper = unitVendor,
    perLotVendorCopper = lotVendor,
    batchVendorCopper = batchVendor,
    commissionKnown = commissionKnown,
    bidScenario = bidScenario,
    buyoutScenario = buyoutScenario,
    bidFloorLossWarning = bidFloorLossWarning,
    buyoutLossWarning = buyoutLossWarning,
    suspectedUnitAsStackMistake = suspectedUnitAsStackMistake,
    durationEvaluations = durationEvaluations,
    selectedDurationIndex = selectedDurIdx,
    depositReserveWarning = depositReserveWarning,
    warningCodes = warningCodes,
  }
end

return AuctionPostMath
