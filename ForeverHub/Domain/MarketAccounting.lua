local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.Domain = ns.Domain or {}

local MarketAccounting = {}
ns.Domain.MarketAccounting = MarketAccounting

MarketAccounting.EXPORT_SCHEMA_VERSION = 1
MarketAccounting.PROJECTION_SCHEMA_VERSION = 1
MarketAccounting.PROJECTION_ARTIFACT_TYPE = "market-projection-v1"

-- Safe exact integer copper bound: +/-(2^50 - 1), strictly inside Lua 5.1 53-bit mantissa (2^53 - 1).
MarketAccounting.MAX_SAFE_COPPER = 1125899906842623
MarketAccounting.MAX_OBSERVATIONS = 512
MarketAccounting.MAX_DEPOSIT_QUOTES = 128
MarketAccounting.MAX_MAIL_OUTCOMES = 128
MarketAccounting.MAX_LADDER_RUNGS = 32
MarketAccounting.MAX_EXACT_DP_UNITS = 500

local VALID_DURATIONS_HOURS = {
  [2] = true,
  [8] = true,
  [24] = true,
}

local VALID_ROUNDING_MODES = {
  half_up = true,
  floor = true,
}

local function isSecret(v)
  if ns.Compat and type(ns.Compat.IsSecretOrRestrictedValue) == "function" then
    return ns.Compat.IsSecretOrRestrictedValue(v) == true
  end
  local checkFn = _G.issecretvalue
  if type(checkFn) == "function" then
    local ok, res = pcall(checkFn, v)
    if ok and res == true then
      return true
    end
  end
  return false
end

function MarketAccounting.IsSafeIntegerCopper(v)
  if isSecret(v) or type(v) ~= "number" then
    return false
  end
  if v ~= v or v == math.huge or v == -math.huge then
    return false
  end
  if math.floor(v) ~= v then
    return false
  end
  return v >= -MarketAccounting.MAX_SAFE_COPPER and v <= MarketAccounting.MAX_SAFE_COPPER
end

function MarketAccounting.CheckNonNegativeCopper(v)
  return MarketAccounting.IsSafeIntegerCopper(v) and v >= 0
end

-- Overflow-checked multiplication of two non-negative integers bounded to `MAX_SAFE_COPPER`
-- without ever allowing an intermediate IEEE-754 float product to exceed `2^50 - 1`.
function MarketAccounting.SafeMulNonNegativeCopper(a, b)
  if not MarketAccounting.CheckNonNegativeCopper(a) or not MarketAccounting.CheckNonNegativeCopper(b) then
    return nil, "invalid_copper_factor"
  end
  if a == 0 or b == 0 then
    return 0, nil
  end
  if a > math.floor(MarketAccounting.MAX_SAFE_COPPER / b) then
    return nil, "copper_overflow"
  end
  local prod = a * b
  if not MarketAccounting.CheckNonNegativeCopper(prod) then
    return nil, "copper_overflow"
  end
  return prod, nil
end

-- Exact integer division with `"half_up"` or `"floor"` rounding for `numer >= 0, denom >= 1`
-- using quotient + remainder decomposition to prevent 53-bit mantissa overflow.
function MarketAccounting.RoundDivWithMode(numer, denom, roundingMode)
  if not MarketAccounting.CheckNonNegativeCopper(numer) then
    return nil, "invalid_numerator"
  end
  if not MarketAccounting.IsSafeIntegerCopper(denom) or denom <= 0 or denom > 1000000000 then
    return nil, "invalid_denominator"
  end
  local mode = roundingMode or "half_up"
  if isSecret(mode) or not VALID_ROUNDING_MODES[mode] then
    return nil, "invalid_rounding_mode"
  end
  local q = math.floor(numer / denom)
  local rem = numer - (q * denom)
  if mode == "half_up" and (rem * 2) >= denom then
    q = q + 1
  end
  if not MarketAccounting.CheckNonNegativeCopper(q) then
    return nil, "copper_overflow"
  end
  return q, nil
end

function MarketAccounting.RoundHalfUpDiv(numer, denom)
  return MarketAccounting.RoundDivWithMode(numer, denom, "half_up")
end

-- Exact `round(amountCopper * bps / 10000)` across the full `MAX_SAFE_COPPER` domain
-- without `amountCopper * bps` ever overflowing Lua 5.1's 53-bit integer mantissa.
function MarketAccounting.ScaleCopperByBps(amountCopper, bps, roundingMode)
  if not MarketAccounting.CheckNonNegativeCopper(amountCopper) then
    return nil, "invalid_amount_copper"
  end
  if not MarketAccounting.IsSafeIntegerCopper(bps) or bps < 0 or bps > 1000000 then
    return nil, "invalid_bps"
  end
  local mode = roundingMode or "half_up"
  if isSecret(mode) or not VALID_ROUNDING_MODES[mode] then
    return nil, "invalid_rounding_mode"
  end
  if amountCopper == 0 or bps == 0 then
    return 0, nil
  end
  local qBase = math.floor(amountCopper / 10000)
  local remBase = amountCopper - (qBase * 10000)
  local qScaled, errQ = MarketAccounting.SafeMulNonNegativeCopper(qBase, bps)
  if not qScaled then
    return nil, errQ
  end
  local remScaled, errR = MarketAccounting.RoundDivWithMode(remBase * bps, 10000, mode)
  if not remScaled then
    return nil, errR
  end
  if qScaled > (MarketAccounting.MAX_SAFE_COPPER - remScaled) then
    return nil, "copper_overflow"
  end
  return qScaled + remScaled, nil
end

-- Exact `(a * b) / c` with `"half_up"` or `"floor"` rounding where `a <= MAX_SAFE_COPPER`
-- and `1 <= b, c <= 1,000,000` without `a * b` overflowing `2^53 - 1`.
local function mulSmallAndRoundDiv(a, b, c, roundingMode)
  local q = math.floor(a / c)
  local r = a - (q * c)
  local qb, errQB = MarketAccounting.SafeMulNonNegativeCopper(q, b)
  if not qb then
    return nil, errQB
  end
  local rbDiv, errRB = MarketAccounting.RoundDivWithMode(r * b, c, roundingMode or "half_up")
  if not rbDiv then
    return nil, errRB
  end
  if qb > (MarketAccounting.MAX_SAFE_COPPER - rbDiv) then
    return nil, "copper_overflow"
  end
  return qb + rbDiv, nil
end

-- Computes venue commission in copper for a SINGLE auction lot (`cutBps`: 500 = 5%, 1500 = 15%).
function MarketAccounting.ComputeCommissionCopper(grossSaleCopper, cutBps, roundingMode)
  if not MarketAccounting.CheckNonNegativeCopper(grossSaleCopper) then
    return nil, "invalid_gross_sale_copper"
  end
  if not MarketAccounting.IsSafeIntegerCopper(cutBps) or cutBps < 0 or cutBps > 10000 then
    return nil, "invalid_cut_bps"
  end
  local res, err = MarketAccounting.ScaleCopperByBps(grossSaleCopper, cutBps, roundingMode or "half_up")
  if not res then
    if err == "copper_overflow" then
      return nil, "commission_overflow"
    end
    return nil, err
  end
  return res, nil
end

-- Computes total commission across `numLots` separate auctions of `lotGrossCopper` each.
-- Enforces per-transaction commission rounding (`numLots * round(lotGross * cutBps / 10000)`).
function MarketAccounting.ComputeLotBatchCommissionCopper(lotGrossCopper, numLots, cutBps, roundingMode)
  if not MarketAccounting.IsSafeIntegerCopper(numLots) or numLots <= 0 or numLots > 1000000 then
    return nil, "invalid_num_lots"
  end
  local perLot, err = MarketAccounting.ComputeCommissionCopper(lotGrossCopper, cutBps, roundingMode)
  if not perLot then
    return nil, err
  end
  return MarketAccounting.SafeMulNonNegativeCopper(perLot, numLots)
end

-- Reconciles an observed sale invoice (`grossSaleCopper`, `commissionCopper`, `cutBps`)
-- to identify whether the client applied `"floor"`, `"half_up"`, `"both_agree"`, or `"mismatch"`.
function MarketAccounting.InferInvoiceCommissionRule(grossSaleCopper, commissionCopper, cutBps)
  if not MarketAccounting.CheckNonNegativeCopper(grossSaleCopper) or grossSaleCopper <= 0
    or not MarketAccounting.CheckNonNegativeCopper(commissionCopper)
    or not MarketAccounting.IsSafeIntegerCopper(cutBps) or cutBps <= 0 or cutBps > 10000
  then
    return nil, "invalid_invoice_rule_inputs"
  end
  local halfUp, errH = MarketAccounting.ComputeCommissionCopper(grossSaleCopper, cutBps, "half_up")
  local floored, errF = MarketAccounting.ComputeCommissionCopper(grossSaleCopper, cutBps, "floor")
  if not halfUp or not floored then
    return nil, errH or errF
  end
  local matchesHalfUp = (commissionCopper == halfUp)
  local matchesFloor = (commissionCopper == floored)
  local status = "mismatch"
  if matchesHalfUp and matchesFloor then
    status = "both_agree"
  elseif matchesHalfUp then
    status = "half_up"
  elseif matchesFloor then
    status = "floor"
  end
  return {
    status = status,
    matchesHalfUp = matchesHalfUp,
    matchesFloor = matchesFloor,
    expectedHalfUpCopper = halfUp,
    expectedFloorCopper = floored,
  }, nil
end

-- Computes `round_half_up(askUnitCopper * 10000 / vendorUnitCopper)` ONLY when `vendorable == true`
-- and `vendorUnitCopper > 0`. Returns `(nil, "vendor_floor_unavailable")` for zero-vendor items!
function MarketAccounting.ComputeVendorFloorRatioBps(askUnitCopper, vendorable, vendorUnitCopper)
  if not MarketAccounting.IsSafeIntegerCopper(askUnitCopper) or askUnitCopper <= 0 then
    return nil, "invalid_ask_unit_copper"
  end
  if isSecret(vendorable) or vendorable ~= true then
    return nil, "vendor_floor_unavailable"
  end
  local vu = tonumber(not isSecret(vendorUnitCopper) and vendorUnitCopper or nil)
  if not MarketAccounting.IsSafeIntegerCopper(vu) or vu <= 0 then
    return nil, "vendor_floor_unavailable"
  end
  return mulSmallAndRoundDiv(askUnitCopper, 10000, vu, "half_up")
end

-- Enforces P0.6 Writ/Craft quantity eligibility: unverified default quantities (`quantityVerified ~= true`)
-- return `eligible = false`, `requiredQuantity = nil`, `quantityStatus = "UNKNOWN"`.
function MarketAccounting.EvaluateWritEconomicEligibility(writRecord)
  if isSecret(writRecord) or type(writRecord) ~= "table" then
    return nil, "invalid_writ_record"
  end
  local verified = (not isSecret(writRecord.quantityVerified)) and (writRecord.quantityVerified == true) or false
  if not verified then
    return {
      eligible = false,
      requiredQuantity = nil,
      quantityStatus = "UNKNOWN",
      reason = "unverified_writ_quantity",
    }, nil
  end
  local qty = tonumber(not isSecret(writRecord.quantity) and writRecord.quantity or nil)
  if not MarketAccounting.IsSafeIntegerCopper(qty) or qty <= 0 or qty > 10000 then
    return {
      eligible = false,
      requiredQuantity = nil,
      quantityStatus = "UNKNOWN",
      reason = "invalid_verified_quantity",
    }, nil
  end
  return {
    eligible = true,
    requiredQuantity = qty,
    quantityStatus = "VERIFIED",
    reason = nil,
  }, nil
end

-- Exact overflow-free rational comparison of `buyoutA / sizeA` vs `buyoutB / sizeB`
-- for `0 <= buyout <= 2^50 - 1` and `1 <= size <= 10,000` (`rA * sizeB < 10^8 << 2^53`).
function MarketAccounting.CompareUnitPricesExact(buyoutA, sizeA, buyoutB, sizeB)
  local qA = math.floor(buyoutA / sizeA)
  local qB = math.floor(buyoutB / sizeB)
  if qA ~= qB then
    return (qA < qB) and -1 or 1
  end
  local rA = buyoutA - (qA * sizeA)
  local rB = buyoutB - (qB * sizeB)
  local lhs = rA * sizeB
  local rhs = rB * sizeA
  if lhs ~= rhs then
    return (lhs < rhs) and -1 or 1
  end
  return 0
end

-- Walks an observed ask ladder (`{ stackSize, stackBuyoutCopper, numStacks }`) for `targetQty`.
-- Solves exact minimum-cash-outlay indivisible stack selection via bounded DP when `targetQty <= 500`,
-- and explicitly flags `"greedy_heuristic_upper_bound"` above 500 units.
function MarketAccounting.WalkAskLadderEntryCost(ladderRungs, targetQty, allowPartialStackPurchase, salvageOpts)
  if isSecret(ladderRungs) or type(ladderRungs) ~= "table" then
    return nil, "invalid_ladder"
  end
  if not MarketAccounting.IsSafeIntegerCopper(targetQty) or targetQty <= 0 or targetQty > 1000000 then
    return nil, "invalid_target_quantity"
  end

  local vendorSalvageUnit = nil
  if salvageOpts ~= nil then
    if isSecret(salvageOpts) or type(salvageOpts) ~= "table" then
      return nil, "invalid_salvage_opts"
    end
    if (not isSecret(salvageOpts.vendorable)) and salvageOpts.vendorable == true then
      local vu = tonumber(not isSecret(salvageOpts.vendorUnitCopper) and salvageOpts.vendorUnitCopper or nil)
      if vu ~= nil then
        if not MarketAccounting.CheckNonNegativeCopper(vu) then
          return nil, "invalid_vendor_unit_copper"
        end
        if vu > 0 then
          vendorSalvageUnit = vu
        end
      end
    end
  end

  local normalized = {}
  local totalAvailableUnits = 0
  for idx, rung in ipairs(ladderRungs) do
    if isSecret(rung) or type(rung) ~= "table" then
      return nil, "invalid_ladder_rung"
    end
    local stackSize = tonumber(not isSecret(rung.stackSize) and rung.stackSize or nil)
    local stackBuyout = tonumber(not isSecret(rung.stackBuyoutCopper) and rung.stackBuyoutCopper or nil)
    local numStacks = tonumber(not isSecret(rung.numStacks) and rung.numStacks or 1)
    if not MarketAccounting.IsSafeIntegerCopper(stackSize) or stackSize <= 0 or stackSize > 10000 then
      return nil, "invalid_stack_size"
    end
    if not MarketAccounting.IsSafeIntegerCopper(stackBuyout) or stackBuyout <= 0 then
      return nil, "invalid_stack_buyout"
    end
    if not MarketAccounting.IsSafeIntegerCopper(numStacks) or numStacks <= 0 or numStacks > 100000 then
      return nil, "invalid_num_stacks"
    end
    totalAvailableUnits = totalAvailableUnits + (stackSize * numStacks)
    table.insert(normalized, {
      origIndex = idx,
      stackSize = stackSize,
      stackBuyoutCopper = stackBuyout,
      numStacks = numStacks,
    })
  end

  if totalAvailableUnits < targetQty then
    return {
      status = "insufficient_depth",
      selectionMode = "insufficient_depth",
      sufficientDepth = false,
      requestedQty = targetQty,
      availableUnits = totalAvailableUnits,
      acquiredUnits = 0,
      excessUnits = 0,
      entryCostCopper = nil,
      excessVendorSalvageCopper = nil,
    }, nil
  end

  table.sort(normalized, function(a, b)
    local cmp = MarketAccounting.CompareUnitPricesExact(
      a.stackBuyoutCopper,
      a.stackSize,
      b.stackBuyoutCopper,
      b.stackSize
    )
    if cmp ~= 0 then
      return cmp < 0
    end
    if a.stackSize ~= b.stackSize then
      return a.stackSize < b.stackSize
    end
    return a.origIndex < b.origIndex
  end)

  local allowPartial = (allowPartialStackPurchase == true)
  local acquired = 0
  local cost = 0
  local fills = {}
  local selectionMode

  if allowPartial then
    selectionMode = "partial_commodity_exact"
    for _, r in ipairs(normalized) do
      if acquired >= targetQty then
        break
      end
      local needed = targetQty - acquired
      local availInRung = r.stackSize * r.numStacks
      local takeUnits = math.min(needed, availInRung)
      local rungCost, err = mulSmallAndRoundDiv(r.stackBuyoutCopper, takeUnits, r.stackSize, "half_up")
      if not rungCost then
        return nil, err
      end
      if cost > (MarketAccounting.MAX_SAFE_COPPER - rungCost) then
        return nil, "entry_cost_overflow"
      end
      acquired = acquired + takeUnits
      cost = cost + rungCost
      table.insert(fills, {
        units = takeUnits,
        stacksPurchased = nil,
        costCopper = rungCost,
      })
    end
  elseif targetQty <= MarketAccounting.MAX_EXACT_DP_UNITS then
    selectionMode = "exact_min_outlay_dp"
    -- `dpCost[u]` for `u = 0 .. targetQty` (`targetQty` is the terminal `>= targetQty` state).
    local dpCost = { [0] = 0 }
    local dpAcq = { [0] = 0 }
    local dpPrevState = {}
    local dpBundleIdx = {}
    local bundles = {}

    for rIdx, r in ipairs(normalized) do
      local maxStacks = 1
      if r.stackSize < targetQty then
        local ceilNeeded = math.ceil(targetQty / r.stackSize)
        maxStacks = math.min(r.numStacks, ceilNeeded)
      end
      -- Decompose `maxStacks` into binary bundles `1, 2, 4, ...` for exact subset coverage
      local remStacks = maxStacks
      local k = 1
      while remStacks > 0 do
        local take = (remStacks < k) and remStacks or k
        remStacks = remStacks - take
        k = k * 2
        local bUnits = take * r.stackSize
        local bCost, errBC = MarketAccounting.SafeMulNonNegativeCopper(r.stackBuyoutCopper, take)
        if not bCost then
          return nil, "entry_cost_overflow"
        end
        table.insert(bundles, {
          rungIdx = rIdx,
          stacks = take,
          units = bUnits,
          cost = bCost,
        })
        local bIdx = #bundles
        for u = targetQty - 1, 0, -1 do
          local baseCost = dpCost[u]
          if baseCost ~= nil then
            if baseCost > (MarketAccounting.MAX_SAFE_COPPER - bCost) then
              return nil, "entry_cost_overflow"
            end
            local candCost = baseCost + bCost
            local candAcq = dpAcq[u] + bUnits
            local dest = (candAcq >= targetQty) and targetQty or candAcq
            local curCost = dpCost[dest]
            local curAcq = dpAcq[dest]
            if curCost == nil or candCost < curCost or (candCost == curCost and candAcq < curAcq) then
              dpCost[dest] = candCost
              dpAcq[dest] = candAcq
              dpPrevState[dest] = { prevU = u, prevNode = dpBundleIdx[u] }
              dpBundleIdx[dest] = { bundleIdx = bIdx, prev = dpPrevState[dest] }
            end
          end
        end
      end
    end

    cost = dpCost[targetQty]
    acquired = dpAcq[targetQty]
    local countsByRung = {}
    local node = dpBundleIdx[targetQty]
    while node ~= nil do
      local b = bundles[node.bundleIdx]
      countsByRung[b.rungIdx] = (countsByRung[b.rungIdx] or 0) + b.stacks
      node = node.prev and node.prev.prevNode or nil
    end
    for rIdx, r in ipairs(normalized) do
      local cnt = countsByRung[rIdx]
      if cnt and cnt > 0 then
        local fillCost, _ = MarketAccounting.SafeMulNonNegativeCopper(r.stackBuyoutCopper, cnt)
        table.insert(fills, {
          units = cnt * r.stackSize,
          stackSize = r.stackSize,
          stacksPurchased = cnt,
          costCopper = fillCost,
        })
      end
    end
  else
    selectionMode = "greedy_heuristic_upper_bound"
    for _, r in ipairs(normalized) do
      if acquired >= targetQty then
        break
      end
      local needed = targetQty - acquired
      local stacksNeeded = math.ceil(needed / r.stackSize)
      local stacksToBuy = math.min(stacksNeeded, r.numStacks)
      local unitsGot = stacksToBuy * r.stackSize
      local rungCost, errRC = MarketAccounting.SafeMulNonNegativeCopper(r.stackBuyoutCopper, stacksToBuy)
      if not rungCost or cost > (MarketAccounting.MAX_SAFE_COPPER - rungCost) then
        return nil, "entry_cost_overflow"
      end
      acquired = acquired + unitsGot
      cost = cost + rungCost
      table.insert(fills, {
        units = unitsGot,
        stackSize = r.stackSize,
        stacksPurchased = stacksToBuy,
        costCopper = rungCost,
      })
    end

    if acquired > targetQty then
      for _, singleRung in ipairs(normalized) do
        if singleRung.stackSize >= targetQty and singleRung.stackBuyoutCopper < cost then
          acquired = singleRung.stackSize
          cost = singleRung.stackBuyoutCopper
          fills = {
            {
              units = singleRung.stackSize,
              stackSize = singleRung.stackSize,
              stacksPurchased = 1,
              costCopper = singleRung.stackBuyoutCopper,
            },
          }
        end
      end
    end
  end

  local excessUnits = acquired - targetQty
  local excessSalvage = nil
  if vendorSalvageUnit ~= nil then
    local salv, errSalv = MarketAccounting.SafeMulNonNegativeCopper(vendorSalvageUnit, excessUnits)
    if not salv then
      return nil, errSalv
    end
    excessSalvage = salv
  end

  return {
    status = "ok",
    selectionMode = selectionMode,
    sufficientDepth = true,
    requestedQty = targetQty,
    availableUnits = totalAvailableUnits,
    acquiredUnits = acquired,
    excessUnits = excessUnits,
    entryCostCopper = cost,
    excessVendorSalvageCopper = excessSalvage,
    fills = fills,
  }, nil
end

-- Evaluates explicit liquidation policies `R_pi(q, H)` (`contracts/market-identity-v1.md` Section 5)
-- without multiplicative liquidity haircuts, enforcing per-lot commission rounding and 53-bit safety.
function MarketAccounting.EvaluateLiquidationPolicy(params)
  if isSecret(params) or type(params) ~= "table" then
    return nil, "invalid_params"
  end

  local qty = tonumber(not isSecret(params.quantity) and params.quantity or nil)
  if not MarketAccounting.IsSafeIntegerCopper(qty) or qty <= 0 or qty > 1000000 then
    return nil, "invalid_quantity"
  end

  local vendorable = (params.vendorable == true)
  local vendorUnit = 0
  if vendorable then
    vendorUnit = tonumber(not isSecret(params.vendorUnitCopper) and params.vendorUnitCopper or nil)
    if not MarketAccounting.CheckNonNegativeCopper(vendorUnit) then
      return nil, "invalid_vendor_unit_copper"
    end
  end

  local roundingMode = params.commissionRoundingMode or "half_up"
  if isSecret(roundingMode) or not VALID_ROUNDING_MODES[roundingMode] then
    return nil, "invalid_rounding_mode"
  end

  local policies = {}
  local bestPolicy = nil
  local bestProceeds = nil

  if vendorable and vendorUnit > 0 then
    local vendorTotal, errVT = MarketAccounting.SafeMulNonNegativeCopper(vendorUnit, qty)
    if not vendorTotal then
      return nil, "vendor_overflow"
    end
    policies.vendor_now = {
      policy = "vendor_now",
      feasible = true,
      expectedNetProceedsCopper = vendorTotal,
      unsoldCarryoverUnits = 0,
      terminalFallbackCopper = vendorTotal,
      expectedDepositLostCopper = 0,
    }
    bestPolicy = "vendor_now"
    bestProceeds = vendorTotal
  end

  if params.saleUnitPriceCopper ~= nil and params.saleProbabilityBps ~= nil then
    local saleUnit = tonumber(not isSecret(params.saleUnitPriceCopper) and params.saleUnitPriceCopper or nil)
    local pSaleBps = tonumber(not isSecret(params.saleProbabilityBps) and params.saleProbabilityBps or nil)
    local cutBps = tonumber(not isSecret(params.cutBps) and params.cutBps or 500)
    local lotSize = tonumber(not isSecret(params.lotSize) and params.lotSize or qty)
    local depositPerAttempt = tonumber(not isSecret(params.depositPerAttemptCopper) and params.depositPerAttemptCopper or 0)
    local expectedFailedAttemptsBps = tonumber(
      not isSecret(params.expectedFailedAttemptsBps) and params.expectedFailedAttemptsBps or 0
    )
    local cancelFee = tonumber(not isSecret(params.expectedCancelFeeCopper) and params.expectedCancelFeeCopper or 0)
    local liqCost = tonumber(not isSecret(params.liquidationOpsCopper) and params.liquidationOpsCopper or 0)

    if not MarketAccounting.IsSafeIntegerCopper(saleUnit) or saleUnit <= 0 then
      return nil, "invalid_sale_unit_price"
    end
    if not MarketAccounting.IsSafeIntegerCopper(pSaleBps) or pSaleBps < 0 or pSaleBps > 10000 then
      return nil, "invalid_sale_probability_bps"
    end
    if not MarketAccounting.IsSafeIntegerCopper(lotSize) or lotSize <= 0 or lotSize > qty then
      return nil, "invalid_lot_size"
    end
    if not MarketAccounting.CheckNonNegativeCopper(depositPerAttempt)
      or not MarketAccounting.IsSafeIntegerCopper(expectedFailedAttemptsBps)
      or expectedFailedAttemptsBps < 0 or expectedFailedAttemptsBps > 1000000
      or not MarketAccounting.CheckNonNegativeCopper(cancelFee)
      or not MarketAccounting.CheckNonNegativeCopper(liqCost)
    then
      return nil, "invalid_liquidation_cost_inputs"
    end

    local grossBatch, errGB = MarketAccounting.SafeMulNonNegativeCopper(saleUnit, qty)
    if not grossBatch then
      return nil, errGB
    end

    -- Per-auction-lot commission rounding (`fullLots` of `lotSize` + optional remainder lot)
    local fullLots = math.floor(qty / lotSize)
    local remUnits = qty - (fullLots * lotSize)
    local fullLotGross, errFLG = MarketAccounting.SafeMulNonNegativeCopper(saleUnit, lotSize)
    if not fullLotGross then
      return nil, errFLG
    end
    local fullLotsComm, errFLC = MarketAccounting.ComputeLotBatchCommissionCopper(
      fullLotGross,
      fullLots,
      cutBps,
      roundingMode
    )
    if not fullLotsComm then
      return nil, errFLC
    end
    local remComm = 0
    if remUnits > 0 then
      local remGross, errRG = MarketAccounting.SafeMulNonNegativeCopper(saleUnit, remUnits)
      if not remGross then
        return nil, errRG
      end
      local rc, errRC = MarketAccounting.ComputeCommissionCopper(remGross, cutBps, roundingMode)
      if not rc then
        return nil, errRC
      end
      remComm = rc
    end
    if fullLotsComm > (MarketAccounting.MAX_SAFE_COPPER - remComm) then
      return nil, "commission_overflow"
    end
    local fullCommission = fullLotsComm + remComm
    local netIfAllSold = grossBatch - fullCommission
    local expectedSalesProceeds, errSales = MarketAccounting.ScaleCopperByBps(netIfAllSold, pSaleBps, "half_up")
    if not expectedSalesProceeds then
      return nil, errSales
    end

    local unsoldBps = 10000 - pSaleBps
    local terminalFallback = 0
    if vendorable and vendorUnit > 0 and unsoldBps > 0 then
      local vendorTotalAll, errVTA = MarketAccounting.SafeMulNonNegativeCopper(vendorUnit, qty)
      if not vendorTotalAll then
        return nil, errVTA
      end
      local fb, errFb = MarketAccounting.ScaleCopperByBps(vendorTotalAll, unsoldBps, "half_up")
      if not fb then
        return nil, errFb
      end
      terminalFallback = fb
    end

    local expectedDepositLost, errDep = MarketAccounting.ScaleCopperByBps(
      depositPerAttempt,
      expectedFailedAttemptsBps,
      "half_up"
    )
    if not expectedDepositLost then
      return nil, errDep
    end

    local expectedNet = expectedSalesProceeds + terminalFallback - expectedDepositLost - cancelFee - liqCost
    policies.ah_horizon = {
      policy = "ah_horizon",
      feasible = true,
      lotSize = lotSize,
      commissionRoundingMode = roundingMode,
      totalCommissionIfAllSoldCopper = fullCommission,
      expectedNetProceedsCopper = expectedNet,
      expectedSalesProceedsCopper = expectedSalesProceeds,
      terminalFallbackCopper = terminalFallback,
      expectedDepositLostCopper = expectedDepositLost,
      expectedCancelFeeCopper = cancelFee,
      liquidationOpsCopper = liqCost,
      unsoldProbabilityBps = unsoldBps,
    }

    if bestProceeds == nil or expectedNet > bestProceeds then
      bestProceeds = expectedNet
      bestPolicy = "ah_horizon"
    end
  end

  if bestProceeds == nil then
    return {
      status = "insufficient_evidence",
      bestPolicy = nil,
      totalRealizableCopper = nil,
      unitRealizableCopper = nil,
      policies = policies,
    }, nil
  end

  local unitRealizable
  if bestProceeds >= 0 then
    unitRealizable = MarketAccounting.RoundHalfUpDiv(bestProceeds, qty)
  else
    local absUnit = MarketAccounting.RoundHalfUpDiv(-bestProceeds, qty)
    unitRealizable = -absUnit
  end

  return {
    status = "ok",
    bestPolicy = bestPolicy,
    totalRealizableCopper = bestProceeds,
    unitRealizableCopper = unitRealizable,
    policies = policies,
  }, nil
end

-- Reconciles a completed sale invoice or expired/cancelled listing to the exact 1 copper.
-- Deposit refunds on sold items are returned principal (`principalReturnedCopper`), NOT profit.
function MarketAccounting.ReconcileMailOutcome(record)
  if isSecret(record) or type(record) ~= "table" then
    return nil, "invalid_mail_record"
  end

  local outcomeType = not isSecret(record.outcomeType) and tostring(record.outcomeType or "") or ""
  local entryCost = 0
  local hasEntryCost = false
  if record.entryCostCopper ~= nil then
    if not MarketAccounting.CheckNonNegativeCopper(record.entryCostCopper) then
      return nil, "invalid_entry_cost"
    end
    entryCost = record.entryCostCopper
    hasEntryCost = true
  end

  local priorFailedDeposits = 0
  if record.priorFailedDepositsCopper ~= nil then
    if not MarketAccounting.CheckNonNegativeCopper(record.priorFailedDepositsCopper) then
      return nil, "invalid_prior_failed_deposits"
    end
    priorFailedDeposits = record.priorFailedDepositsCopper
  end

  if outcomeType == "SALE_INVOICE" then
    local grossSale = tonumber(not isSecret(record.grossSaleCopper) and record.grossSaleCopper or nil)
    local commission = tonumber(not isSecret(record.commissionCopper) and record.commissionCopper or nil)
    local depositRefund = tonumber(not isSecret(record.depositRefundedCopper) and record.depositRefundedCopper or nil)
    local cashReceived = tonumber(not isSecret(record.cashReceivedCopper) and record.cashReceivedCopper or nil)

    if not MarketAccounting.CheckNonNegativeCopper(grossSale) or grossSale <= 0
      or not MarketAccounting.CheckNonNegativeCopper(commission)
      or not MarketAccounting.CheckNonNegativeCopper(depositRefund)
      or not MarketAccounting.CheckNonNegativeCopper(cashReceived)
    then
      return nil, "invalid_sale_invoice_fields"
    end

    local expectedCash = grossSale - commission + depositRefund
    local discrepancy = cashReceived - expectedCash
    local netProceedsExDeposit = grossSale - commission

    local impliedCutOk = nil
    local impliedCommissionRule = nil
    if record.expectedCutBps ~= nil then
      local mode = record.expectedRoundingMode or "half_up"
      local expectedComm, errC = MarketAccounting.ComputeCommissionCopper(grossSale, record.expectedCutBps, mode)
      if not expectedComm then
        return nil, errC
      end
      impliedCutOk = (expectedComm == commission)
      local inferredRule = MarketAccounting.InferInvoiceCommissionRule(grossSale, commission, record.expectedCutBps)
      if inferredRule then
        impliedCommissionRule = inferredRule.status
      end
    end

    return {
      outcomeType = "SALE_INVOICE",
      reconciledExact = (discrepancy == 0),
      discrepancyCopper = discrepancy,
      impliedCutMatchesVenue = impliedCutOk,
      impliedCommissionRule = impliedCommissionRule,
      grossSaleCopper = grossSale,
      commissionCopper = commission,
      principalReturnedCopper = depositRefund,
      depositLostCopper = priorFailedDeposits,
      netProceedsExDepositCopper = netProceedsExDeposit,
      cashReceivedCopper = cashReceived,
      economicProfitCopper = hasEntryCost and (netProceedsExDeposit - entryCost - priorFailedDeposits) or nil,
    }, nil
  elseif outcomeType == "EXPIRED_RETURN" or outcomeType == "CANCELLED_RETURN" then
    local depositPosted = tonumber(not isSecret(record.depositPostedCopper) and record.depositPostedCopper or nil)
    local cancelFee = tonumber(not isSecret(record.cancelFeeCopper) and record.cancelFeeCopper or 0)
    if not MarketAccounting.CheckNonNegativeCopper(depositPosted)
      or not MarketAccounting.CheckNonNegativeCopper(cancelFee)
    then
      return nil, "invalid_failed_listing_fields"
    end
    local totalLost = depositPosted + cancelFee + priorFailedDeposits
    return {
      outcomeType = outcomeType,
      reconciledExact = true,
      discrepancyCopper = 0,
      principalReturnedCopper = 0,
      depositLostCopper = depositPosted + priorFailedDeposits,
      cancelFeeCopper = cancelFee,
      totalFeeLossCopper = totalLost,
      cashReceivedCopper = 0,
      -- Unsold item remains in inventory; realized fee loss on this attempt is `-totalLost`.
      realizedAttemptFeeDeltaCopper = -totalLost,
    }, nil
  end

  return nil, "unsupported_outcome_type"
end

-- ============================================================================
-- Sibling Addon Reader (`_G.ForeverHub_MarketData`)
-- ============================================================================

function MarketAccounting.GetSiblingMarketDataStatus(explicitNowEpochSec, expectedMarketKey)
  local raw = _G.ForeverHub_MarketData
  if raw == nil then
    return {
      loaded = false,
      status = "missing",
      reason = "sibling_addon_not_loaded",
    }
  end
  if isSecret(raw) or type(raw) ~= "table" then
    return {
      loaded = false,
      status = "invalid_schema",
      reason = "non_table_payload",
    }
  end

  local schemaVer = not isSecret(raw.schemaVersion) and tonumber(raw.schemaVersion) or nil
  local artifactType = not isSecret(raw.artifactType) and raw.artifactType or nil
  local revision = not isSecret(raw.contentRevision) and tonumber(raw.contentRevision) or nil
  local marketKey = not isSecret(raw.marketKey) and raw.marketKey or nil
  local publishedAt = not isSecret(raw.publishedAtEpoch) and tonumber(raw.publishedAtEpoch) or nil
  local validUntil = not isSecret(raw.validUntilEpoch) and tonumber(raw.validUntilEpoch) or nil

  if schemaVer ~= MarketAccounting.PROJECTION_SCHEMA_VERSION
    or artifactType ~= MarketAccounting.PROJECTION_ARTIFACT_TYPE
    or not MarketAccounting.IsSafeIntegerCopper(revision) or revision < 1
    or type(marketKey) ~= "string" or marketKey == ""
    or not MarketAccounting.CheckNonNegativeCopper(publishedAt)
    or not MarketAccounting.CheckNonNegativeCopper(validUntil)
    or validUntil <= publishedAt
    or type(raw.items) ~= "table"
  then
    return {
      loaded = false,
      status = "invalid_schema",
      reason = "header_validation_failed",
    }
  end

  local targetMarketKey = expectedMarketKey
  if not targetMarketKey and ns.Domain and ns.Domain.MarketIdentity then
    targetMarketKey = ns.Domain.MarketIdentity.ResolveCurrentClientMarketKey()
  end
  if type(targetMarketKey) == "string" and targetMarketKey ~= "" and targetMarketKey ~= marketKey then
    return {
      loaded = true,
      status = "wrong_market",
      reason = "market_key_mismatch",
      contentRevision = revision,
      marketKey = marketKey,
      expectedMarketKey = targetMarketKey,
      publishedAtEpoch = publishedAt,
      validUntilEpoch = validUntil,
    }
  end

  local nowEpoch = explicitNowEpochSec
  if nowEpoch == nil and ns.Compat and type(ns.Compat.GetServerTimeSafe) == "function" then
    local st = ns.Compat.GetServerTimeSafe()
    nowEpoch = st and st.epochSec or nil
  end

  local isExpired = (type(nowEpoch) == "number" and nowEpoch >= validUntil) or false
  local publishedAgeSec = nil
  local expiresInSec = nil
  if type(nowEpoch) == "number" then
    expiresInSec = validUntil - nowEpoch
    if nowEpoch >= publishedAt then
      publishedAgeSec = nowEpoch - publishedAt
    end
  end

  local itemCount = 0
  local newestObsAt = nil
  local oldestObsAt = nil
  for k, rec in pairs(raw.items) do
    if not isSecret(k) and not isSecret(rec) and type(rec) == "table" then
      itemCount = itemCount + 1
      local obsAt = not isSecret(rec.observedAtEpoch) and tonumber(rec.observedAtEpoch) or nil
      if obsAt and obsAt > 0 then
        if newestObsAt == nil or obsAt > newestObsAt then
          newestObsAt = obsAt
        end
        if oldestObsAt == nil or obsAt < oldestObsAt then
          oldestObsAt = obsAt
        end
      end
    end
  end

  local newestObsAgeSec = nil
  if type(nowEpoch) == "number" and newestObsAt ~= nil and nowEpoch >= newestObsAt then
    newestObsAgeSec = nowEpoch - newestObsAt
  end

  return {
    loaded = true,
    status = isExpired and "expired" or "active",
    contentRevision = revision,
    marketKey = marketKey,
    publishedAtEpoch = publishedAt,
    validUntilEpoch = validUntil,
    publishedAgeSec = publishedAgeSec,
    expiresInSec = expiresInSec,
    newestObservedAtEpoch = newestObsAt,
    oldestObservedAtEpoch = oldestObsAt,
    newestObservationAgeSec = newestObsAgeSec,
    itemCount = itemCount,
    basis = not isSecret(raw.evidenceBasis) and tostring(raw.evidenceBasis or "USER_REPORTED") or "USER_REPORTED",
  }
end

function MarketAccounting.LookupProjectedItem(itemKey, explicitNowEpochSec, expectedMarketKey)
  if isSecret(itemKey) or type(itemKey) ~= "string" or itemKey == "" then
    return nil, "invalid_item_key"
  end
  local status = MarketAccounting.GetSiblingMarketDataStatus(explicitNowEpochSec, expectedMarketKey)
  if status.status ~= "active" then
    return nil, status.status
  end
  local items = _G.ForeverHub_MarketData and _G.ForeverHub_MarketData.items
  local rec = items and items[itemKey] or nil
  if isSecret(rec) or type(rec) ~= "table" then
    return nil, "item_not_in_projection"
  end
  return rec, nil
end

-- ============================================================================
-- ForeverHub-Owned Snapshot Export Envelope (`ForeverHubDB.marketExport`)
-- ============================================================================

local function pushBounded(list, maxLen, entry)
  table.insert(list, entry)
  while #list > maxLen do
    table.remove(list, 1)
  end
end

function MarketAccounting.EnsureMarketExportInitialized()
  if type(_G.ForeverHubDB) ~= "table" then
    _G.ForeverHubDB = {}
  end
  local db = _G.ForeverHubDB
  if type(db.marketExport) ~= "table" or db.marketExport.schemaVersion ~= MarketAccounting.EXPORT_SCHEMA_VERSION then
    db.marketExport = {
      schemaVersion = MarketAccounting.EXPORT_SCHEMA_VERSION,
      addonVersion = tostring(ns.version or "0.8.9"),
      installationSeq = 0,
      persistedAt = nil,
      capabilityMatrix = nil,
      observations = {},
      depositQuotes = {},
      mailOutcomes = {},
    }
  end
  local me = db.marketExport
  me.addonVersion = tostring(ns.version or "0.8.9")
  me.installationSeq = math.max(0, math.floor(tonumber(me.installationSeq) or 0))
  me.observations = type(me.observations) == "table" and me.observations or {}
  me.depositQuotes = type(me.depositQuotes) == "table" and me.depositQuotes or {}
  me.mailOutcomes = type(me.mailOutcomes) == "table" and me.mailOutcomes or {}
  return me
end

function MarketAccounting.RecordMaterialObservation(params)
  if isSecret(params) or type(params) ~= "table" then
    return nil, "invalid_observation_params"
  end
  local ident = ns.Domain and ns.Domain.MarketIdentity
  if not ident then
    return nil, "market_identity_unavailable"
  end

  local marketKey = params.marketKey
  if not marketKey then
    local mk, mkErr = ident.ResolveCurrentClientMarketKey(params.auctionPoolID)
    if not mk then
      return nil, mkErr
    end
    marketKey = mk
  end

  local classified, clsErr = ident.ClassifyItemIdentity({
    itemID = params.itemID,
    itemLink = params.itemLink,
    isVariantCapable = params.isVariantCapable,
    verifiedBaseSet = params.verifiedBaseSet,
  })
  if not classified then
    return nil, clsErr
  end

  local unitPrice = tonumber(not isSecret(params.unitPriceCopper) and params.unitPriceCopper or nil)
  if not MarketAccounting.IsSafeIntegerCopper(unitPrice) or unitPrice <= 0 then
    return nil, "invalid_unit_price_copper"
  end

  -- P0.1 Four-timestamp rule: preserve `nil` `observedAt` when observation timestamp is unknown
  -- (such as coarse day-age summaries from `Auctionator.API.v1`). NEVER substitute current/flush time.
  local observedAt = nil
  if params.observedAt ~= nil then
    local oa = tonumber(not isSecret(params.observedAt) and params.observedAt or nil)
    if MarketAccounting.CheckNonNegativeCopper(oa) and oa > 0 then
      observedAt = oa
    else
      return nil, "invalid_observed_at"
    end
  end

  local ageDaysCoarse = nil
  if params.ageDaysCoarse ~= nil then
    local ad = tonumber(not isSecret(params.ageDaysCoarse) and params.ageDaysCoarse or nil)
    if MarketAccounting.CheckNonNegativeCopper(ad) then
      ageDaysCoarse = ad
    end
  end

  local rungsOut = nil
  if type(params.ladderRungs) == "table" and #params.ladderRungs > 0 then
    rungsOut = {}
    for i, r in ipairs(params.ladderRungs) do
      if i > MarketAccounting.MAX_LADDER_RUNGS then
        break
      end
      if not isSecret(r) and type(r) == "table" then
        local ss = tonumber(not isSecret(r.stackSize) and r.stackSize or nil)
        local sb = tonumber(not isSecret(r.stackBuyoutCopper) and r.stackBuyoutCopper or nil)
        local nsCount = tonumber(not isSecret(r.numStacks) and r.numStacks or 1)
        if MarketAccounting.IsSafeIntegerCopper(ss) and ss > 0
          and MarketAccounting.IsSafeIntegerCopper(sb) and sb > 0
          and MarketAccounting.IsSafeIntegerCopper(nsCount) and nsCount > 0
        then
          table.insert(rungsOut, {
            stackSize = ss,
            stackBuyoutCopper = sb,
            numStacks = nsCount,
          })
        end
      end
    end
  end

  local me = MarketAccounting.EnsureMarketExportInitialized()
  me.installationSeq = me.installationSeq + 1
  local obsID = string.format("obs:%d:%s", me.installationSeq, classified.itemKey)

  local entry = {
    observationId = obsID,
    seq = me.installationSeq,
    marketKey = marketKey,
    itemKey = classified.itemKey,
    itemID = classified.itemID,
    classification = classified.classification,
    tradeSafe = classified.tradeSafe,
    evidenceClass = tostring(params.evidenceClass or "PROVIDER_SUMMARY_PRICE"),
    observedAt = observedAt,
    ageDaysCoarse = ageDaysCoarse,
    unitPriceCopper = unitPrice,
    ladderRungs = rungsOut,
    sanitizedLink = classified.sanitizedLink,
  }
  pushBounded(me.observations, MarketAccounting.MAX_OBSERVATIONS, entry)
  return entry, nil
end

-- Exports a single material observation from `Providers.Auctionator` without inventing timestamps.
function MarketAccounting.ExportProviderMaterialSlice(itemID, explicitAuctionPoolID)
  local auc = ns.Providers and ns.Providers.Auctionator
  if not auc or type(auc.GetItemPriceInfo) ~= "function" then
    return nil, "auctionator_provider_unavailable"
  end
  local pInfo = auc.GetItemPriceInfo(itemID)
  if not pInfo or not pInfo.available then
    return nil, "auctionator_not_loaded"
  end
  if not pInfo.unitPrice or pInfo.unitPrice <= 0 then
    return nil, "price_missing_in_auctionator"
  end

  return MarketAccounting.RecordMaterialObservation({
    itemID = itemID,
    auctionPoolID = explicitAuctionPoolID,
    evidenceClass = "PROVIDER_SUMMARY_PRICE",
    -- Auctionator API v1 exposes day-bucket age, NOT exact scan epoch; keep `observedAt = nil`!
    observedAt = nil,
    ageDaysCoarse = pInfo.ageDays,
    unitPriceCopper = pInfo.unitPrice,
  })
end

local function resolveObservedBuild(explicitBuild)
  if not isSecret(explicitBuild) and type(explicitBuild) == "string" and explicitBuild ~= "" then
    return explicitBuild
  end
  local getBuild = _G.GetBuildInfo
  if type(getBuild) == "function" then
    local okB, _, b = pcall(getBuild)
    if okB and not isSecret(b) and type(b) == "string" and b ~= "" then
      return b
    end
  end
  return "unknown"
end

function MarketAccounting.RecordDepositQuote(params)
  if isSecret(params) or type(params) ~= "table" then
    return nil, "invalid_deposit_quote"
  end
  local ident = ns.Domain and ns.Domain.MarketIdentity
  if not ident then
    return nil, "market_identity_unavailable"
  end

  local durationHours = tonumber(not isSecret(params.durationHours) and params.durationHours or nil)
  if not VALID_DURATIONS_HOURS[durationHours] then
    return nil, "invalid_forever_duration_hours"
  end

  local stackSize = tonumber(not isSecret(params.stackSize) and params.stackSize or nil)
  local numStacks = tonumber(not isSecret(params.numStacks) and params.numStacks or 1)
  local vendorUnit = tonumber(not isSecret(params.vendorUnitCopper) and params.vendorUnitCopper or nil)
  local quotedDeposit = tonumber(not isSecret(params.quotedDepositCopper) and params.quotedDepositCopper or nil)
  local observedAt = params.observedAt ~= nil and tonumber(not isSecret(params.observedAt) and params.observedAt or nil) or nil

  if not MarketAccounting.IsSafeIntegerCopper(stackSize) or stackSize <= 0
    or not MarketAccounting.IsSafeIntegerCopper(numStacks) or numStacks <= 0
    or (vendorUnit ~= nil and not MarketAccounting.CheckNonNegativeCopper(vendorUnit))
    or not MarketAccounting.CheckNonNegativeCopper(quotedDeposit)
    or (observedAt ~= nil and (not MarketAccounting.CheckNonNegativeCopper(observedAt) or observedAt <= 0))
  then
    return nil, "invalid_deposit_quote_numbers"
  end

  local marketKey = params.marketKey or ident.ResolveCurrentClientMarketKey(params.auctionPoolID)
  if not marketKey then
    return nil, "missing_market_key"
  end
  local classified, clsErr = ident.ClassifyItemIdentity({
    itemID = params.itemID,
    itemLink = params.itemLink,
    isVariantCapable = params.isVariantCapable,
  })
  if not classified then
    return nil, clsErr
  end

  local me = MarketAccounting.EnsureMarketExportInitialized()
  me.installationSeq = me.installationSeq + 1
  local entry = {
    quoteId = string.format("dep:%d:%s:%dh", me.installationSeq, classified.itemKey, durationHours),
    seq = me.installationSeq,
    marketKey = marketKey,
    itemKey = classified.itemKey,
    itemID = classified.itemID,
    durationHours = durationHours,
    stackSize = stackSize,
    numStacks = numStacks,
    vendorUnitCopper = vendorUnit,
    quotedDepositCopper = quotedDeposit,
    observedAt = observedAt,
    observedBuild = resolveObservedBuild(params.observedBuild),
  }
  pushBounded(me.depositQuotes, MarketAccounting.MAX_DEPOSIT_QUOTES, entry)
  return entry, nil
end

function MarketAccounting.RecordMailOutcomeObservation(params)
  if isSecret(params) or type(params) ~= "table" then
    return nil, "invalid_mail_outcome"
  end
  local reconciled, recErr = MarketAccounting.ReconcileMailOutcome(params)
  if not reconciled then
    return nil, recErr
  end
  local ident = ns.Domain and ns.Domain.MarketIdentity
  local marketKey = params.marketKey or (ident and ident.ResolveCurrentClientMarketKey(params.auctionPoolID))
  if not marketKey then
    return nil, "missing_market_key"
  end
  local classified, clsErr = ident.ClassifyItemIdentity({
    itemID = params.itemID,
    itemLink = params.itemLink,
    isVariantCapable = params.isVariantCapable,
  })
  if not classified then
    return nil, clsErr
  end

  local observedAt = nil
  if params.observedAt ~= nil then
    local oa = tonumber(not isSecret(params.observedAt) and params.observedAt or nil)
    if MarketAccounting.CheckNonNegativeCopper(oa) and oa > 0 then
      observedAt = oa
    end
  end

  local me = MarketAccounting.EnsureMarketExportInitialized()
  me.installationSeq = me.installationSeq + 1
  local entry = {
    outcomeId = string.format("mail:%d:%s", me.installationSeq, classified.itemKey),
    seq = me.installationSeq,
    marketKey = marketKey,
    itemKey = classified.itemKey,
    itemID = classified.itemID,
    outcomeType = reconciled.outcomeType,
    observedAt = observedAt,
    observedBuild = resolveObservedBuild(params.observedBuild),
    reconciledExact = reconciled.reconciledExact,
    discrepancyCopper = reconciled.discrepancyCopper,
    grossSaleCopper = reconciled.grossSaleCopper,
    commissionCopper = reconciled.commissionCopper,
    principalReturnedCopper = reconciled.principalReturnedCopper,
    depositLostCopper = reconciled.depositLostCopper,
    cancelFeeCopper = reconciled.cancelFeeCopper,
    cashReceivedCopper = reconciled.cashReceivedCopper,
    netProceedsExDepositCopper = reconciled.netProceedsExDepositCopper,
    economicProfitCopper = reconciled.economicProfitCopper,
  }
  pushBounded(me.mailOutcomes, MarketAccounting.MAX_MAIL_OUTCOMES, entry)
  return entry, nil
end

function MarketAccounting.OnPlayerLogout()
  local me = MarketAccounting.EnsureMarketExportInitialized()
  if ns.Compat and type(ns.Compat.ProbeEconomyRuntimeCapabilities) == "function" then
    me.capabilityMatrix = ns.Compat.ProbeEconomyRuntimeCapabilities()
  end
  local st = ns.Compat and ns.Compat.GetServerTimeSafe and ns.Compat.GetServerTimeSafe() or nil
  if st and st.epochSec then
    me.persistedAt = st.epochSec
  else
    me.persistedAt = nil
  end
  return me
end

-- ============================================================================
-- Stage 1: Versioned FeeRuleRecord Validation & Native Legacy AH Buyout Capture
-- ============================================================================

local VALID_FEE_STATUSES = {
  UNVERIFIED = true,
  PARTIALLY_VERIFIED = true,
  VERIFIED = true,
  STALE_BUILD = true,
  INCONSISTENT = true,
}

function MarketAccounting.EvaluateFeeRuleForBuild(record, currentBuild)
  if isSecret(record) or type(record) ~= "table" then
    return nil, "invalid_fee_rule_record"
  end
  local ruleId = not isSecret(record.ruleId) and record.ruleId or nil
  local marketKey = not isSecret(record.marketKey) and record.marketKey or nil
  local observedBuild = not isSecret(record.observedBuild) and record.observedBuild or nil
  local status = not isSecret(record.verificationStatus) and record.verificationStatus or nil
  local roundingMode = not isSecret(record.roundingMode) and record.roundingMode or "unknown"
  local minDep = record.minDepositCopper ~= nil
    and tonumber(not isSecret(record.minDepositCopper) and record.minDepositCopper or nil)
    or nil
  local captureIds = not isSecret(record.supportingCaptureIds) and record.supportingCaptureIds or nil

  if type(ruleId) ~= "string" or ruleId == ""
    or type(marketKey) ~= "string" or marketKey == ""
    or type(observedBuild) ~= "string" or observedBuild == ""
    or not VALID_FEE_STATUSES[status]
  then
    return nil, "invalid_fee_rule_fields"
  end

  local curBuild = resolveObservedBuild(currentBuild)
  local effectiveStatus = status
  if observedBuild ~= curBuild and (effectiveStatus == "VERIFIED" or effectiveStatus == "PARTIALLY_VERIFIED") then
    effectiveStatus = "STALE_BUILD"
  end

  local hasCaptures = type(captureIds) == "table" and #captureIds > 0
  local hasValidRounding = (roundingMode == "floor" or roundingMode == "half_up")
  local hasValidMinDep = minDep ~= nil and MarketAccounting.IsSafeIntegerCopper(minDep) and minDep >= 1

  local microSpreadEligible = (effectiveStatus == "VERIFIED")
    and (observedBuild == curBuild)
    and hasCaptures
    and hasValidRounding
    and hasValidMinDep

  return {
    ruleId = ruleId,
    marketKey = marketKey,
    observedBuild = observedBuild,
    currentBuild = curBuild,
    effectiveStatus = effectiveStatus,
    microSpreadEligible = microSpreadEligible,
    minDepositCopper = (effectiveStatus == "VERIFIED" and hasValidMinDep) and minDep or nil,
    roundingMode = (effectiveStatus == "VERIFIED" and hasValidRounding) and roundingMode or "unknown",
  }, nil
end

function MarketAccounting.QuoteExpectedDepositCopper(record, params)
  if isSecret(params) or type(params) ~= "table" then
    return nil, "invalid_deposit_params"
  end
  local eval, evalErr = MarketAccounting.EvaluateFeeRuleForBuild(record, params.currentBuild)
  if not eval then
    return nil, evalErr
  end
  if eval.effectiveStatus ~= "VERIFIED" or not eval.minDepositCopper then
    return nil, (eval.effectiveStatus == "STALE_BUILD") and "stale_build_fee_rule" or "unverified_fee_rule"
  end

  local durationHours = tonumber(not isSecret(params.durationHours) and params.durationHours or 24)
  local sched = not isSecret(record.durationSchedule) and record.durationSchedule or nil
  local rateBps = type(sched) == "table" and tonumber(sched[durationHours] or sched[tostring(durationHours)]) or nil
  if not rateBps or not MarketAccounting.CheckNonNegativeCopper(rateBps) then
    return nil, "missing_duration_rate"
  end

  local vendorUnit = tonumber(not isSecret(params.vendorUnitCopper) and params.vendorUnitCopper or nil)
  local stackSize = tonumber(not isSecret(params.stackSize) and params.stackSize or nil)
  local numStacks = tonumber(not isSecret(params.numStacks) and params.numStacks or 1)
  if not MarketAccounting.CheckNonNegativeCopper(vendorUnit)
    or not MarketAccounting.IsSafeIntegerCopper(stackSize) or stackSize <= 0
    or not MarketAccounting.IsSafeIntegerCopper(numStacks) or numStacks <= 0
  then
    return nil, "invalid_deposit_quote_inputs"
  end

  local stackSemantics = not isSecret(record.stackSemantics) and record.stackSemantics or "unknown"
  local stackVendor, mulErr = MarketAccounting.SafeMulNonNegativeCopper(vendorUnit, stackSize)
  if not stackVendor then
    return nil, mulErr
  end

  local perStack
  if stackSemantics == "per_stack_with_min_floor" then
    local rawStack, scErr = MarketAccounting.ScaleCopperByBps(stackVendor, rateBps, eval.roundingMode)
    if not rawStack then
      return nil, scErr
    end
    perStack = math.max(eval.minDepositCopper, rawStack)
  elseif stackSemantics == "per_unit_floor_then_stack" then
    local perUnit, uErr = MarketAccounting.ScaleCopperByBps(vendorUnit, rateBps, eval.roundingMode)
    if not perUnit then
      return nil, uErr
    end
    local unitStack, usErr = MarketAccounting.SafeMulNonNegativeCopper(perUnit, stackSize)
    if not unitStack then
      return nil, usErr
    end
    perStack = math.max(eval.minDepositCopper, unitStack)
  else
    return nil, "unsupported_stack_semantics"
  end

  return MarketAccounting.SafeMulNonNegativeCopper(perStack, numStacks)
end

-- Inspects visible rows on the Legacy Auction House `"list"` tab in read-only mode.
-- Gate 1 Hard Invariant:
--   - Requires `buyoutPrice > 0` (`buyout == 0` bid-only auctions are NEVER treated as buyouts;
--     they are skipped and counted in `skippedBidOnlyCount`).
--   - Rejects restricted/secret fields and `AMBIGUOUS_LINK` rows (`tradeSafe == false`).
function MarketAccounting.InspectLegacyAuctionPageBuyouts(opts)
  opts = (not isSecret(opts) and type(opts) == "table") and opts or {}
  local ident = ns.Domain and ns.Domain.MarketIdentity
  if not ident then
    return nil, "market_identity_unavailable"
  end
  if ns.Compat and ns.Compat.IsInCombat and ns.Compat.IsInCombat() then
    return nil, "combat_lockdown"
  end
  local getNumFn = _G.GetNumAuctionItems
  local getInfoFn = _G.GetAuctionItemInfo
  local getLinkFn = _G.GetAuctionItemLink
  if type(getNumFn) ~= "function" or type(getInfoFn) ~= "function" or type(getLinkFn) ~= "function" then
    return nil, "legacy_auction_api_unavailable"
  end

  local okCount, batchCount, totalCount = pcall(getNumFn, "list")
  if not okCount or isSecret(batchCount) or type(batchCount) ~= "number" or batchCount < 0 then
    return nil, "auction_list_unavailable"
  end

  local bc = math.min(math.floor(batchCount), 200)
  local skippedBidOnlyCount = 0
  local skippedAmbiguousCount = 0
  local skippedInvalidCount = 0
  local eligibleListingCount = 0
  local groupedByKey = {}
  local orderedKeys = {}

  for idx = 1, bc do
    local okRow, _, _, count, _, _, _, _, _, _, buyoutPrice, _, _, _, _, _, _, itemIdRaw = pcall(getInfoFn, "list", idx)
    local okLink, itemLink = pcall(getLinkFn, "list", idx)
    if not okRow or isSecret(count) or isSecret(buyoutPrice) then
      skippedInvalidCount = skippedInvalidCount + 1
    else
      local stackSize = tonumber(count)
      local stackBuyout = tonumber(buyoutPrice)
      if not MarketAccounting.IsSafeIntegerCopper(stackSize) or stackSize <= 0 then
        skippedInvalidCount = skippedInvalidCount + 1
      elseif not stackBuyout or not MarketAccounting.CheckNonNegativeCopper(stackBuyout) or stackBuyout <= 0 then
        -- Gate 1: `buyout == 0` (bid-only auction) MUST NEVER be treated as an executable buyout!
        skippedBidOnlyCount = skippedBidOnlyCount + 1
      else
        local safeLink = (okLink and not isSecret(itemLink) and type(itemLink) == "string" and itemLink ~= "") and itemLink or nil
        local safeId = (not isSecret(itemIdRaw) and tonumber(itemIdRaw)) or nil
        local classified = ident.ClassifyItemIdentity({
          itemID = safeId,
          itemLink = safeLink,
          verifiedBaseSet = opts.verifiedBaseSet,
        })
        if not classified or classified.tradeSafe ~= true then
          skippedAmbiguousCount = skippedAmbiguousCount + 1
        else
          eligibleListingCount = eligibleListingCount + 1
          local bucket = groupedByKey[classified.itemKey]
          if not bucket then
            bucket = {
              itemKey = classified.itemKey,
              itemID = classified.itemID,
              classification = classified.classification,
              sanitizedLink = classified.sanitizedLink,
              rungsByPair = {},
              rungsList = {},
              minUnitBuyoutNumer = stackBuyout,
              minUnitBuyoutDenom = stackSize,
            }
            groupedByKey[classified.itemKey] = bucket
            table.insert(orderedKeys, classified.itemKey)
          else
            if MarketAccounting.CompareUnitPricesExact(
              stackBuyout,
              stackSize,
              bucket.minUnitBuyoutNumer,
              bucket.minUnitBuyoutDenom
            ) < 0 then
              bucket.minUnitBuyoutNumer = stackBuyout
              bucket.minUnitBuyoutDenom = stackSize
            end
          end

          local pairKey = string.format("%d:%d", stackSize, stackBuyout)
          local rung = bucket.rungsByPair[pairKey]
          if rung then
            rung.numStacks = rung.numStacks + 1
          else
            rung = {
              stackSize = stackSize,
              stackBuyoutCopper = stackBuyout,
              numStacks = 1,
            }
            bucket.rungsByPair[pairKey] = rung
            table.insert(bucket.rungsList, rung)
          end
        end
      end
    end
  end

  local itemsOut = {}
  for _, ikey in ipairs(orderedKeys) do
    local b = groupedByKey[ikey]
    table.sort(b.rungsList, function(a, c)
      local cmp = MarketAccounting.CompareUnitPricesExact(
        a.stackBuyoutCopper,
        a.stackSize,
        c.stackBuyoutCopper,
        c.stackSize
      )
      if cmp ~= 0 then
        return cmp < 0
      end
      if a.stackSize ~= c.stackSize then
        return a.stackSize < c.stackSize
      end
      return a.stackBuyoutCopper < c.stackBuyoutCopper
    end)
    local roundedMinUnit = MarketAccounting.RoundHalfUpDiv(b.minUnitBuyoutNumer, b.minUnitBuyoutDenom) or 1
    if roundedMinUnit < 1 then
      roundedMinUnit = 1
    end
    table.insert(itemsOut, {
      itemKey = b.itemKey,
      itemID = b.itemID,
      classification = b.classification,
      sanitizedLink = b.sanitizedLink,
      minUnitPriceCopper = roundedMinUnit,
      ladderRungs = b.rungsList,
    })
  end

  return {
    batchCount = bc,
    totalCount = (not isSecret(totalCount) and type(totalCount) == "number") and math.floor(totalCount) or nil,
    eligibleListingCount = eligibleListingCount,
    skippedBidOnlyCount = skippedBidOnlyCount,
    skippedAmbiguousCount = skippedAmbiguousCount,
    skippedInvalidCount = skippedInvalidCount,
    items = itemsOut,
  }, nil
end

function MarketAccounting.CaptureOpenLegacyAuctionBuyouts(explicitAuctionPoolID, opts)
  local inspected, err = MarketAccounting.InspectLegacyAuctionPageBuyouts(opts)
  if not inspected then
    return nil, err
  end
  local st = ns.Compat and ns.Compat.GetServerTimeSafe and ns.Compat.GetServerTimeSafe() or nil
  local observedAt = (st and st.epochSec) or nil
  local recorded = {}
  for _, item in ipairs(inspected.items) do
    local obs, obsErr = MarketAccounting.RecordMaterialObservation({
      auctionPoolID = explicitAuctionPoolID,
      itemID = item.itemID,
      itemLink = item.sanitizedLink,
      verifiedBaseSet = (opts and opts.verifiedBaseSet) or { [item.itemID] = (item.classification == "EXACT_BASE_ITEM") or nil },
      evidenceClass = "NATIVE_PAGE_BUYOUT_SCAN",
      observedAt = observedAt,
      unitPriceCopper = item.minUnitPriceCopper,
      ladderRungs = item.ladderRungs,
    })
    if obs and not obsErr then
      table.insert(recorded, obs)
    end
  end
  inspected.recordedCount = #recorded
  inspected.recordedObservations = recorded
  return inspected, nil
end

-- ============================================================================
-- Stage 7A.0: Separated Commission vs. Deposit Evidence & Non-Circular
-- Seller Invoice Reconciliation State Machine (Astra Round-5 P0-2 & P1)
-- ============================================================================

local CANDIDATE_VENUE_RATES_BPS = { 500, 1500 }

-- Evaluates commission-only verification (`CommissionRuleRecord`) WITHOUT requiring
-- `minDepositCopper` or duration schedule verification (`P0-2`).
function MarketAccounting.EvaluateCommissionRuleForBuild(record, currentBuild)
  if isSecret(record) or type(record) ~= "table" then
    return nil, "invalid_commission_rule_record"
  end
  local venueIdentity = not isSecret(record.venueIdentity) and record.venueIdentity or nil
  local observedBuild = not isSecret(record.observedBuild) and record.observedBuild or nil
  local cutBps = tonumber(not isSecret(record.cutBps) and record.cutBps or nil)
  local roundingMode = not isSecret(record.roundingMode) and record.roundingMode or "unknown"
  local status = not isSecret(record.verificationStatus) and record.verificationStatus or "UNVERIFIED"
  local invoiceIds = not isSecret(record.supportingInvoiceIds) and record.supportingInvoiceIds or nil
  local salePostBuildVerified = (not isSecret(record.salePostBuildVerified)) and (record.salePostBuildVerified == true)

  if type(venueIdentity) ~= "string" or venueIdentity == ""
    or venueIdentity == "UNKNOWN_AH" or string.sub(venueIdentity, 1, 11) == "UNKNOWN_AH:"
  then
    return nil, "unclassified_venue_identity"
  end
  if type(observedBuild) ~= "string" or observedBuild == ""
    or not MarketAccounting.IsSafeIntegerCopper(cutBps) or cutBps <= 0 or cutBps > 10000
  then
    return nil, "invalid_commission_rule_fields"
  end

  local curBuild = resolveObservedBuild(currentBuild)
  local effectiveStatus = status
  if observedBuild ~= curBuild and (effectiveStatus == "VERIFIED" or effectiveStatus == "PARTIALLY_VERIFIED") then
    effectiveStatus = "STALE_BUILD"
  end

  -- Astra P0-2: `both_agree` or missing post-build provenance NEVER establishes `VERIFIED` commission!
  local hasDiscriminatingRounding = (roundingMode == "floor" or roundingMode == "half_up")
  local hasInvoices = (type(invoiceIds) == "table" and #invoiceIds > 0)
  local commissionVerified = (effectiveStatus == "VERIFIED")
    and (observedBuild == curBuild)
    and hasDiscriminatingRounding
    and hasInvoices
    and salePostBuildVerified

  return {
    venueIdentity = venueIdentity,
    observedBuild = observedBuild,
    currentBuild = curBuild,
    cutBps = cutBps,
    roundingMode = commissionVerified and roundingMode or "unknown",
    effectiveStatus = commissionVerified and "VERIFIED" or effectiveStatus,
    commissionVerified = commissionVerified,
    depositVerified = false, -- Commission evidence NEVER establishes deposit schedules!
  }, nil
end

-- Evaluates deposit-only verification (`DepositRuleRecord`) strictly separate from seller invoices (`P0-2`).
function MarketAccounting.EvaluateDepositRuleForBuild(record, currentBuild)
  if isSecret(record) or type(record) ~= "table" then
    return nil, "invalid_deposit_rule_record"
  end
  local venueIdentity = not isSecret(record.venueIdentity) and record.venueIdentity or nil
  local observedBuild = not isSecret(record.observedBuild) and record.observedBuild or nil
  local minDep = tonumber(not isSecret(record.minDepositCopper) and record.minDepositCopper or nil)
  local sched = not isSecret(record.durationSchedule) and record.durationSchedule or nil
  local captureIds = not isSecret(record.supportingDepositCaptureIds) and record.supportingDepositCaptureIds or nil
  local batchSemantics = not isSecret(record.batchSemantics) and tostring(record.batchSemantics or "UNKNOWN") or "UNKNOWN"

  if type(venueIdentity) ~= "string" or venueIdentity == ""
    or venueIdentity == "UNKNOWN_AH" or string.sub(venueIdentity, 1, 11) == "UNKNOWN_AH:"
  then
    return nil, "unclassified_venue_identity"
  end
  if type(observedBuild) ~= "string" or observedBuild == ""
    or not MarketAccounting.CheckNonNegativeCopper(minDep)
    or type(sched) ~= "table"
  then
    return nil, "invalid_deposit_rule_fields"
  end

  local curBuild = resolveObservedBuild(currentBuild)
  local hasCaptures = (type(captureIds) == "table" and #captureIds > 0)
  local isCurrent = (observedBuild == curBuild)
  local depositVerified = isCurrent and hasCaptures and (batchSemantics == "PER_LOT" or batchSemantics == "BATCH_TOTAL")

  return {
    venueIdentity = venueIdentity,
    observedBuild = observedBuild,
    currentBuild = curBuild,
    minDepositCopper = depositVerified and minDep or nil,
    batchSemantics = batchSemantics,
    effectiveStatus = (not isCurrent and "STALE_BUILD") or (depositVerified and "VERIFIED" or "PARTIALLY_VERIFIED"),
    depositVerified = depositVerified,
    commissionVerified = false,
  }, nil
end

-- Reconciles a single raw seller mail invoice row through Astra's 5-state lifecycle:
--   `PENDING_FIELDS -> COMPLETE_UNATTRIBUTED -> ATTRIBUTED_RECONCILED -> RULE_SUPPORT -> CONFLICT_QUARANTINED`
-- Enforces:
--   1. Raw `nil`/missing fields remain `PENDING_FIELDS` (never coerced to 0).
--   2. Exact integer identity: `cashReceived == actualGross - commission + depositRefund`.
--   3. Uses verified actual-sale gross (`rawBid` when positive; checks `rawBuyout` consistency without assuming listed buyout on bid wins).
--   4. Non-circular attribution: NEVER infers `venueIdentity` from `consignment / gross`.
--   5. Low-value / `both_agree` invoices stay `ATTRIBUTED_RECONCILED` rather than promoting to `RULE_SUPPORT`.
function MarketAccounting.ReconcileSellerInvoiceEvidence(rawRow, context)
  if isSecret(rawRow) or type(rawRow) ~= "table" then
    return { state = "PENDING_FIELDS", reason = "invalid_row" }
  end
  context = (not isSecret(context) and type(context) == "table") and context or {}

  if rawRow.headerLoaded ~= true or rawRow.invoiceLoaded ~= true then
    return { state = "PENDING_FIELDS", reason = "header_or_invoice_unloaded" }
  end
  local invType = not isSecret(rawRow.invoiceType) and tostring(rawRow.invoiceType or "") or ""
  if invType == "seller_temp_invoice" then
    return { state = "PENDING_FIELDS", reason = "pending_seller_temp_invoice" }
  end
  if invType ~= "seller" then
    return { state = "PENDING_FIELDS", reason = "not_seller_invoice" }
  end

  local rawBid = not isSecret(rawRow.rawBid) and rawRow.rawBid or rawRow.bid
  local rawBuyout = not isSecret(rawRow.rawBuyout) and rawRow.rawBuyout or rawRow.buyout
  local rawDeposit = not isSecret(rawRow.rawDeposit) and rawRow.rawDeposit or rawRow.deposit
  local rawConsignment = not isSecret(rawRow.rawConsignment) and rawRow.rawConsignment or rawRow.consignment
  local rawMoney = not isSecret(rawRow.rawMoney) and rawRow.rawMoney or rawRow.money

  -- Astra P0-2: Any `nil` numeric field means `PENDING_FIELDS` — never coerce `nil` to `0`!
  if rawRow.fieldsComplete == false
    or type(rawBid) ~= "number"
    or type(rawBuyout) ~= "number"
    or type(rawDeposit) ~= "number"
    or type(rawConsignment) ~= "number"
    or type(rawMoney) ~= "number"
  then
    return { state = "PENDING_FIELDS", reason = "missing_numeric_invoice_fields" }
  end

  if not MarketAccounting.CheckNonNegativeCopper(rawBid)
    or not MarketAccounting.CheckNonNegativeCopper(rawBuyout)
    or not MarketAccounting.CheckNonNegativeCopper(rawDeposit)
    or not MarketAccounting.CheckNonNegativeCopper(rawConsignment)
    or not MarketAccounting.CheckNonNegativeCopper(rawMoney)
  then
    return { state = "CONFLICT_QUARANTINED", reason = "non_integer_or_negative_invoice_fields" }
  end

  -- Actual sale gross: in WoW seller invoices, `bid` carries the winning hammer price (`> 0`),
  -- whereas `buyout` may be `0` (bid-only auction) or `>= bid` (won by bid below buyout or at buyout).
  local actualGross = rawBid
  local grossSemantics = "verified_hammer_bid"
  if actualGross <= 0 then
    return { state = "CONFLICT_QUARANTINED", reason = "non_positive_actual_sale_gross" }
  end
  if rawBuyout > 0 and actualGross > rawBuyout then
    return { state = "CONFLICT_QUARANTINED", reason = "hammer_bid_exceeds_buyout" }
  end

  -- Exact integer cash reconciliation: `cash_received == actualGross - consignment + deposit_refund`
  local expectedCash = actualGross - rawConsignment + rawDeposit
  if expectedCash < 0 or rawMoney ~= expectedCash then
    return {
      state = "CONFLICT_QUARANTINED",
      reason = "cash_reconciliation_mismatch",
      actualGrossCopper = actualGross,
      consignmentCopper = rawConsignment,
      depositRefundCopper = rawDeposit,
      cashReceivedCopper = rawMoney,
      expectedCashCopper = expectedCash,
    }
  end

  -- Check which candidate rates (`500` vs `1500` bps) could fit `(actualGross, rawConsignment)` under floor or half_up:
  local fittingRates = {}
  for _, candBps in ipairs(CANDIDATE_VENUE_RATES_BPS) do
    local inf = MarketAccounting.InferInvoiceCommissionRule(actualGross, rawConsignment, candBps)
    if inf and inf.status ~= "mismatch" then
      table.insert(fittingRates, { cutBps = candBps, inference = inf })
    end
  end

  -- Independent venue & build attribution check (NEVER inferred from `consignment / actualGross`!):
  local venueIdentity = type(context.verifiedVenueIdentity) == "string" and context.verifiedVenueIdentity or nil
  local expectedCutBps = tonumber(context.expectedVenueCutBps)
  local salePostBuildVerified = (context.salePostBuildVerified == true)

  if not venueIdentity or venueIdentity == "" or venueIdentity == "UNKNOWN_AH" or string.sub(venueIdentity, 1, 11) == "UNKNOWN_AH:" or not expectedCutBps then
    return {
      state = "COMPLETE_UNATTRIBUTED",
      reason = "independent_venue_attribution_missing",
      actualGrossCopper = actualGross,
      grossSemantics = grossSemantics,
      consignmentCopper = rawConsignment,
      depositRefundCopper = rawDeposit,
      cashReceivedCopper = rawMoney,
      wonBelowBuyout = (rawBuyout > actualGross),
      fittingRateCount = #fittingRates,
    }
  end

  local venueInf, infErr = MarketAccounting.InferInvoiceCommissionRule(actualGross, rawConsignment, expectedCutBps)
  if not venueInf or infErr or venueInf.status == "mismatch" then
    return {
      state = "CONFLICT_QUARANTINED",
      reason = "attributed_venue_commission_mismatch",
      venueIdentity = venueIdentity,
      expectedVenueCutBps = expectedCutBps,
      actualGrossCopper = actualGross,
      consignmentCopper = rawConsignment,
    }
  end

  local rateDiscriminating = (#fittingRates == 1 and fittingRates[1].cutBps == expectedCutBps)
  local roundingDiscriminating = (venueInf.status == "floor" or venueInf.status == "half_up")

  if not salePostBuildVerified or not rateDiscriminating or not roundingDiscriminating then
    return {
      state = "ATTRIBUTED_RECONCILED",
      reason = (not salePostBuildVerified and "sale_build_provenance_unverified")
        or (not rateDiscriminating and "ambiguous_low_value_rate_fit")
        or "rounding_mode_both_agree",
      venueIdentity = venueIdentity,
      expectedVenueCutBps = expectedCutBps,
      roundingStatus = venueInf.status,
      rateDiscriminating = rateDiscriminating,
      roundingDiscriminating = roundingDiscriminating,
      actualGrossCopper = actualGross,
      consignmentCopper = rawConsignment,
      depositRefundCopper = rawDeposit,
      cashReceivedCopper = rawMoney,
      establishesDepositRule = false,
    }
  end

  return {
    state = "RULE_SUPPORT",
    venueIdentity = venueIdentity,
    cutBps = expectedCutBps,
    discriminatedRoundingMode = venueInf.status,
    actualGrossCopper = actualGross,
    consignmentCopper = rawConsignment,
    depositRefundCopper = rawDeposit,
    cashReceivedCopper = rawMoney,
    salePostBuildVerified = true,
    establishesCommissionRule = true,
    establishesDepositRule = false, -- Astra P0-2: Invoice NEVER establishes deposit rules!
  }
end

-- Processes a mailbox snapshot while preserving duplicate legitimate sales (`multiplicity`)
-- AND preventing repeated `MAIL_INBOX_UPDATE` scans of the same open inbox from fabricating
-- extra supporting observations (`P1` Invoice Multiplicity vs. Scan Deduplication).
function MarketAccounting.ReconcileInboxInvoiceBatch(rawRows, prevBatchState, context)
  rawRows = type(rawRows) == "table" and rawRows or {}
  prevBatchState = type(prevBatchState) == "table" and prevBatchState or { maxObservedMultiplicityBySig = {} }
  local prevMax = type(prevBatchState.maxObservedMultiplicityBySig) == "table"
    and prevBatchState.maxObservedMultiplicityBySig
    or {}

  local currentCountsBySig = {}
  local nextMaxBySig = {}
  for k, v in pairs(prevMax) do
    nextMaxBySig[k] = v
  end

  local evaluatedRows = {}
  local newlyObservedSupportingRows = {}

  for idx, row in ipairs(rawRows) do
    local ev = MarketAccounting.ReconcileSellerInvoiceEvidence(row, context)
    local sig = nil
    if ev.state ~= "PENDING_FIELDS" and type(row) == "table" then
      sig = string.format(
        "%s|%s|%s|%s|%s|%s",
        tostring(row.invoiceType or ""),
        tostring(row.itemName or ""),
        tostring(row.rawBid or row.bid or ""),
        tostring(row.rawBuyout or row.buyout or ""),
        tostring(row.rawDeposit or row.deposit or ""),
        tostring(row.rawConsignment or row.consignment or "")
      )
      currentCountsBySig[sig] = (currentCountsBySig[sig] or 0) + 1
      local occIdx = currentCountsBySig[sig]
      local priorSeen = nextMaxBySig[sig] or 0
      ev.occurrenceIndexInSnapshot = occIdx
      ev.isNewObservation = (occIdx > priorSeen)
      if occIdx > priorSeen then
        nextMaxBySig[sig] = occIdx
        if ev.state == "RULE_SUPPORT" then
          table.insert(newlyObservedSupportingRows, ev)
        end
      end
    else
      ev.isNewObservation = false
    end
    ev.mailIndex = idx
    table.insert(evaluatedRows, ev)
  end

  return {
    rows = evaluatedRows,
    newlyObservedSupportingRows = newlyObservedSupportingRows,
    batchState = {
      maxObservedMultiplicityBySig = nextMaxBySig,
      snapshotMultiplicityBySig = currentCountsBySig,
    },
  }
end
