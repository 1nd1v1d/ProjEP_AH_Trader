-- ============================================================
-- ProjEP AH Trader - Calculator.lua
-- Margen-Berechnung für Alchemie, Mats, Glyphen, Edelsteine
-- WotLK 3.3.5 / Lua 5.1 (Project Epoch)
--
-- WotLK Verbesserungen vs. TWOW:
--  - GetAuctionDeposit() statt Schätzformel
--  - itemSellPrice aus GetItemInfo() für echte Vendor-Preise
-- ============================================================

local AHT = PROJEP_AHT

-- ── Deposit-Berechnung (WotLK: echte API) ────────────────────
-- duration: 1=12h, 2=24h, 3=48h
-- Fallback falls API nicht verfügbar: 2%-Schätzung wie TWOW
function AHT:CalcDeposit(itemName, duration)
    duration = duration or 2  -- Standard: 24h
    if GetAuctionDeposit then
        -- WotLK API: braucht Item im Sell-Slot → nutzen wir für Live-Berechnung
        -- Für Pre-Berechnung ohne Sell-Slot: vendorSellPrice-Weg
        local _, _, _, _, _, _, _, _, _, _, vendorSellPrice = GetItemInfo(itemName)
        if vendorSellPrice and vendorSellPrice > 0 then
            -- Formel: floor(vendorSellPrice * stackSize * (durationMin/120) * stackAdjust * 0.025)
            -- 24h=1440min, stackSize=1, maxStack meist 5 → stackAdjust=1.2
            local durationMin = 720  -- 12h
            if duration == 2 then durationMin = 1440 end
            if duration == 3 then durationMin = 2880 end
            local stackAdjust = 1.2  -- (1 + (5-1)*0.05)
            return math.max(1, math.floor(vendorSellPrice * (durationMin/120) * stackAdjust * 0.025))
        end
    end
    -- Fallback: TWOW-Schätzformel
    local price = AHT.prices[itemName] or 0
    local vendorEstimate = math.floor(price * 0.02)
    return math.max(1, math.floor(vendorEstimate * 0.36))
end

-- ── Alchemie: Margen berechnen ───────────────────────────────
function AHT:CalculateMargins()
    local results = {}

    for _, recipe in ipairs(AHT.recipes) do
        local result = {
            name         = recipe.name,
            link         = recipe.link,
            reagents     = recipe.reagents,
            sellPrice    = AHT.prices[recipe.name],
            ingredCost   = 0,
            depositCost  = 0,
            ahProvision  = 0,
            profit       = nil,
            margin       = nil,
            missingReag  = {},
            notOnAH      = false,
            volume       = AHT.listingCounts[recipe.name] or 0,
            avgSellPrice = AHT:GetPriceAverage(recipe.name),
            sellTrend    = AHT:GetPriceTrend(recipe.name),
            isDeal       = AHT:IsDeal(recipe.name),
            hasReagDeal  = false,
        }

        local allFound  = true
        local costDetails = {}

        for _, reagent in ipairs(recipe.reagents) do
            local vendorP = AHT.vendorPrices[reagent.name]
            local ahP     = AHT.prices[reagent.name]
            local price   = vendorP or ahP

            if price then
                local total = price * reagent.count
                result.ingredCost = result.ingredCost + total
                table.insert(costDetails, {
                    name     = reagent.name,
                    count    = reagent.count,
                    ppu      = price,
                    total    = total,
                    source   = vendorP and AHT.L["tt_source_vendor"] or AHT.L["tt_source_ah"],
                    avgPrice = AHT:GetPriceAverage(reagent.name),
                    isDeal   = AHT:IsDeal(reagent.name),
                })
                if AHT:IsDeal(reagent.name) then result.hasReagDeal = true end
            else
                allFound = false
                table.insert(result.missingReag, reagent.name)
                table.insert(costDetails, {
                    name   = reagent.name,
                    count  = reagent.count,
                    ppu    = 0, total = 0,
                    source = "???",
                })
            end
        end
        result.costDetails = costDetails

        -- Aktualisierungszeitpunkt (ältester Zeitstempel)
        local oldest = AHT.priceUpdated[recipe.name]
        for _, reagent in ipairs(recipe.reagents) do
            if not AHT:IsVendorItem(reagent.name) then
                local ts = AHT.priceUpdated[reagent.name]
                if ts then
                    if not oldest or ts < oldest then oldest = ts end
                else
                    oldest = nil; break
                end
            end
        end
        result.updatedAt = oldest

        if not result.sellPrice then
            result.notOnAH = true
        elseif allFound then
            result.ahProvision = math.floor(result.sellPrice * AHT.ahCutRate)
            result.depositCost = AHT:CalcDeposit(recipe.name)
            local net      = result.sellPrice - result.ahProvision - result.depositCost
            result.profit  = net - result.ingredCost
            result.margin  = result.ingredCost > 0
                and (result.profit / result.ingredCost) * 100 or 0
        end

        table.insert(results, result)
    end

    AHT.results = results
    AHT:ApplyFilterAndSort()
    return results
end

function AHT:ApplyFilterAndSort()
    local filtered = {}
    local filter   = string.lower(AHT.searchFilter or "")

    for _, r in ipairs(AHT.results or {}) do
        if r and r.name and (filter == "" or string.find(string.lower(r.name), filter, 1, true)) then
            table.insert(filtered, r)
        end
    end

    local mode   = AHT.sortMode or "profit"
    local isDesc = (AHT.sortDir or "desc") == "desc"

    -- Defensiver Comparator: garantiert Zahlen + saubere strict-weak-order Logik
    local function getKey(x)
        if type(x) ~= "table" then return -1e9 end
        local v = (mode == "margin") and x.margin or x.profit
        if type(v) ~= "number" then return -1e9 end
        return v
    end

    local ok, err = pcall(function()
        table.sort(filtered, function(a, b)
            local va = getKey(a)
            local vb = getKey(b)
            if isDesc then return va > vb else return va < vb end
        end)
    end)
    if not ok and AHT.Print then
        AHT:Print("|cffff4444ApplyFilterAndSort:|r " .. tostring(err)
            .. " (mode=" .. tostring(mode) .. ", isDesc=" .. tostring(isDesc)
            .. ", count=" .. tostring(#filtered) .. ")")
    end
    AHT.displayResults = filtered
end

-- ── Mats: Zeitgewichteter Durchschnitt ────────────────────────
function AHT:CalcWeightedMatAverage(matName, currentPrice)
    local hist = AHT.matsHistory[matName]
    if not hist or #hist == 0 then return currentPrice or 0 end

    local now    = time()
    local sumWP  = 0
    local sumW   = 0

    for _, entry in ipairs(hist) do
        local ageDays = math.floor((now - entry.t) / 86400)
        if ageDays <= 60 then
            local w = math.max(0, 1 - ageDays / 60)
            sumWP = sumWP + entry.p * w
            sumW  = sumW + w
        end
    end

    return sumW > 0 and math.floor(sumWP / sumW) or (currentPrice or 0)
end

function AHT:CalculateMatsMargins()
    local results = {}

    for matName in pairs(AHT.materials) do
        local currentPrice = AHT.prices[matName] or 0
        local weighted_avg, deviation

        local hist = AHT.matsHistory[matName]
        if hist and #hist > 0 then
            local last = hist[#hist]
            weighted_avg = last.weighted_avg or currentPrice
            if weighted_avg and weighted_avg > 0 then
                deviation = currentPrice > 0
                    and ((currentPrice - weighted_avg) / weighted_avg) * 100
                    or -100
            else
                deviation = 0
            end
        else
            weighted_avg = currentPrice
            deviation    = 0
        end

        local lastUpdate = AHT.priceUpdated[matName]
        if hist and #hist > 0 and hist[#hist].t then
            lastUpdate = hist[#hist].t
        end

        table.insert(results, {
            name          = matName,
            currentPrice  = currentPrice,
            weighted_avg  = weighted_avg or 0,
            deviation     = deviation or 0,
            listingCount  = AHT.listingCounts[matName] or 0,
            lastUpdate    = lastUpdate,
            isSelected    = AHT.matsSelected[matName] ~= false,
            historyLength = #(AHT.matsHistory[matName] or {}),
        })
    end

    AHT.matsResults = results
    AHT:ApplyMatsFilterAndSort()
    return results
end

function AHT:ApplyMatsFilterAndSort()
    local filtered = {}
    local filter   = string.lower(AHT.matsSearchFilter or "")

    for _, r in ipairs(AHT.matsResults) do
        if filter == "" or string.find(string.lower(r.name), filter, 1, true) then
            table.insert(filtered, r)
        end
    end

    local mode   = AHT.matsSortMode or "deviation"
    local isDesc = (AHT.matsSortDir or "desc") == "desc"

    table.sort(filtered, function(a, b)
        local va, vb
        if mode == "current"      then va, vb = a.currentPrice, b.currentPrice
        elseif mode == "weighted_avg" then va, vb = a.weighted_avg, b.weighted_avg
        elseif mode == "deviation"    then va, vb = a.deviation, b.deviation
        else                          va, vb = a.name, b.name end
        return isDesc and (va > vb) or (va < vb)
    end)
    AHT.matsDisplayResults = filtered
end

-- ── Kaufplan-Builder (Mats) ───────────────────────────────────
-- Gibt zurück: { steps=[{count, ppu, total}], totalCost, avgPpu, available }
function AHT:BuildMatsBuyPlanFromOffers(matName, needed, maxPpu)
    local cache = AHT.matsOfferCache[matName] or AHT.allOffersCache[matName]
    if not cache or not cache.offers or #cache.offers == 0 then
        return nil
    end

    -- Nach Stückpreis aufsteigend sortieren (günstigstes zuerst)
    local sorted = {}
    for _, o in ipairs(cache.offers) do
        if not maxPpu or o.ppu <= maxPpu then
            table.insert(sorted, o)
        end
    end
    table.sort(sorted, function(a, b) return a.ppu < b.ppu end)

    -- Preisstufen zusammenfassen
    local steps     = {}
    local remaining = needed
    local totalCost = 0
    local available = 0

    for _, offer in ipairs(sorted) do
        if remaining <= 0 then break end
        local qty = math.min(offer.count, remaining)
        local cost = qty * offer.ppu
        -- Gleichen Stückpreis zusammenfassen
        if #steps > 0 and steps[#steps].ppu == offer.ppu then
            steps[#steps].count = steps[#steps].count + qty
            steps[#steps].total = steps[#steps].total + cost
        else
            table.insert(steps, { count = qty, ppu = offer.ppu, total = cost })
        end
        totalCost = totalCost + cost
        available = available + qty
        remaining = remaining - qty
    end

    if #steps == 0 then return nil end

    return {
        steps     = steps,
        totalCost = totalCost,
        avgPpu    = available > 0 and math.floor(totalCost / available) or 0,
        available = available,
        needed    = needed,
    }
end

-- ── Margenschutz: Max-Stückpreis für Zutat ───────────────────
function AHT:CalcMaxIngredPpu(recipe, ingredName, targetMargin)
    targetMargin = targetMargin or 0.10  -- 10% Mindestmarge

    local sellPrice = AHT.prices[recipe.name]
    if not sellPrice or sellPrice <= 0 then return nil end

    local provision  = math.floor(sellPrice * AHT.ahCutRate)
    local deposit    = AHT:CalcDeposit(recipe.name)
    local netIncome  = sellPrice - provision - deposit

    -- Zutatenkosten anderer Items (Vendor + AH)
    local otherCost  = 0
    local ingredCount = 0
    for _, reagent in ipairs(recipe.reagents) do
        if reagent.name == ingredName then
            ingredCount = reagent.count
        else
            local vp = AHT.vendorPrices[reagent.name]
            local ap = AHT.prices[reagent.name] or 0
            otherCost = otherCost + (vp or ap) * reagent.count
        end
    end

    if ingredCount == 0 then return nil end

    -- maxIngredCost so dass Marge >= targetMargin
    -- profit = netIncome - otherCost - ingredCount * maxPpu >= targetMargin * totalCost
    -- vereinfacht: maxPpu = (netIncome - otherCost - targetMargin * otherCost) / (ingredCount * (1 + targetMargin))
    local maxIngredCost = math.floor((netIncome - otherCost * (1 + targetMargin)) / (1 + targetMargin))
    if maxIngredCost <= 0 then return 0 end
    return math.floor(maxIngredCost / ingredCount)
end

if AHT and AHT._loadStatus then
    AHT._loadStatus.calculator = true
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[AHT-DIAG]|r Calculator.lua OK")
    end
end
