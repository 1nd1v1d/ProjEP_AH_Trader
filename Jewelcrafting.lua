-- ============================================================
-- ProjEP AH Trader - Jewelcrafting.lua
-- Schmuckkunst: Edelstein-Schliff-Analyse + Prospektions-Analyse
-- WotLK 3.3.5 / Lua 5.1 (Project Epoch)
--
-- Zwei Analysepfade:
--   A) Roher Edelstein → Schliff → Gewinn
--   B) Erz prospektieren → erwartete Gems → bester Schliff → Profit
-- ============================================================

local AHT = PROJEP_AHT

-- Profession-Namen zur Erkennung
local JC_NAMES = {
    ["jewelcrafting"]     = true,
    ["schmuckkunst"]      = true,
    ["joaillerie"]        = true,
    ["joyería"]           = true,
    ["gemmologia"]        = true,
}

-- ── Standard-Prospektionsraten (pro 5 Erz) ───────────────────
-- [erzName] = { [gemName] = rate, ... }
-- Empirische WotLK-Werte (konfigurierbar via AHT.prospectRates)
local DEFAULT_PROSPECT_RATES = {
    ["Cobalt Ore"] = {
        ["Bloodstone"]     = 0.5,
        ["Shadow Crystal"] = 0.5,
        ["Chalcedony"]     = 0.5,
        ["Dark Jade"]      = 0.5,
        ["Huge Citrine"]   = 0.5,
        ["Sun Crystal"]    = 0.5,
    },
    ["Saronite Ore"] = {
        ["Bloodstone"]     = 0.60,
        ["Shadow Crystal"] = 0.60,
        ["Chalcedony"]     = 0.60,
        ["Dark Jade"]      = 0.60,
        ["Huge Citrine"]   = 0.60,
        ["Sun Crystal"]    = 0.60,
        -- Seltene epische Gems (sehr niedrig)
        ["Cardinal Ruby"]  = 0.01,
        ["King's Amber"]   = 0.01,
        ["Ametrine"]       = 0.01,
        ["Dreadstone"]     = 0.01,
        ["Eye of Zul"]     = 0.01,
        ["Majestic Zircon"]= 0.01,
    },
    ["Titanium Ore"] = {
        ["Cardinal Ruby"]  = 0.15,
        ["King's Amber"]   = 0.15,
        ["Ametrine"]       = 0.15,
        ["Dreadstone"]     = 0.15,
        ["Eye of Zul"]     = 0.15,
        ["Majestic Zircon"]= 0.15,
        -- Auch häufige Gems
        ["Bloodstone"]     = 0.30,
        ["Chalcedony"]     = 0.30,
    },
    -- Deutsche Namen
    ["Kobaltliterz"] = {
        ["Blutstein"]   = 0.5,
        ["Schattenkristall"] = 0.5,
        ["Chalzedon"]   = 0.5,
        ["Dunkler Jade"]= 0.5,
        ["Riesencitrin"]= 0.5,
        ["Sonnenkristall"]= 0.5,
    },
    ["Saroniiterz"] = {
        ["Blutstein"]   = 0.60,
        ["Schattenkristall"] = 0.60,
        ["Chalzedon"]   = 0.60,
        ["Dunkler Jade"]= 0.60,
        ["Riesencitrin"]= 0.60,
        ["Sonnenkristall"] = 0.60,
    },
    ["Titanerz"] = {
        ["Kardinalsrubin"]          = 0.15,
        ["Amber des Königs"]        = 0.15,
        ["Ametrin"]                 = 0.15,
        ["Angststein"]              = 0.15,
        ["Auge des Zul"]            = 0.15,
        ["Majestätischer Zirkon"]   = 0.15,
    },
}

-- ── Rezepte aus dem Berufe-Fenster laden ─────────────────────
AHT.gemCuts            = AHT.gemCuts or {}
AHT.gemCutSortMode     = "profit"
AHT.gemCutSortDir      = "desc"
AHT.gemCutSearchFilter = ""
AHT._jcLoaded          = false

function AHT:LearnJewelcraftingRecipes()
    if AHT._jcLoadGuard then return end
    AHT._jcLoadGuard = true

    local profName = GetTradeSkillLine()
    if not profName or not JC_NAMES[profName:lower()] then
        AHT._jcLoadGuard = false; return
    end

    local numSkills = GetNumTradeSkills()
    if not numSkills or numSkills == 0 then
        AHT._jcLoadGuard = false; return
    end

    local newCuts = {}
    local seen    = {}
    local retryNeeded = false

    for i = 1, numSkills do
        local skillName, skillType = GetTradeSkillInfo(i)
        if skillName and skillType ~= "header" then
            if not seen[skillName] then
                seen[skillName] = true

                local reagents   = {}
                local allLoaded  = true
                local numReag    = GetTradeSkillNumReagents(i)

                for r = 1, numReag do
                    local reagName, _, reagCount = GetTradeSkillReagentInfo(i, r)
                    if reagName and reagName ~= "" then
                        table.insert(reagents, { name = reagName, count = reagCount or 1 })
                    else
                        if GetTradeSkillReagentItemLink then
                            local link = GetTradeSkillReagentItemLink(i, r)
                            if link then
                                local name = link:match("%[(.-)%]")
                                if name then
                                    table.insert(reagents, { name = name, count = reagCount or 1 })
                                else
                                    allLoaded = false
                                end
                            else
                                allLoaded = false
                            end
                        else
                            allLoaded = false
                        end
                    end
                end

                if not allLoaded then
                    retryNeeded = true
                else
                    local outputLink = GetTradeSkillItemLink and GetTradeSkillItemLink(i) or nil
                    -- Rohen Edelstein aus Reagents extrahieren (erster Reagent bei Gem-Cuts)
                    local rawGem = (#reagents == 1) and reagents[1].name or nil
                    table.insert(newCuts, {
                        name     = skillName,
                        link     = outputLink,
                        rawGem   = rawGem,
                        reagents = reagents,
                    })
                end
            end
        end
    end

    -- Bestehende Cuts zusammenführen
    local existingMap = {}
    for _, c in ipairs(AHT.gemCuts) do existingMap[c.name] = true end
    for _, cut in ipairs(newCuts) do
        if not existingMap[cut.name] then
            table.insert(AHT.gemCuts, cut)
            if AHT.gemCutSelected[cut.name] == nil then
                AHT.gemCutSelected[cut.name] = true
            end
        end
    end

    AHT._jcLoadGuard = false
    AHT._jcLoaded    = true

    local L = AHT.L
    AHT:Print(string.format(L["jc_scan_complete"], #AHT.gemCuts))
    AHT:SaveDB()
end

-- ── Gem-Schliff-Margen berechnen ─────────────────────────────
AHT.gemCutResults        = AHT.gemCutResults        or {}
AHT.gemCutDisplayResults = AHT.gemCutDisplayResults or {}

function AHT:CalculateGemCutMargins()
    local results = {}

    for _, cut in ipairs(AHT.gemCuts) do
        local sellPrice   = AHT.prices[cut.name]
        local ingredCost  = 0
        local allFound    = true
        local missingReag = {}

        for _, reag in ipairs(cut.reagents) do
            local p = AHT.vendorPrices[reag.name] or AHT.prices[reag.name]
            if p then
                ingredCost = ingredCost + p * reag.count
            else
                allFound = false
                table.insert(missingReag, reag.name)
            end
        end

        local r = {
            name        = cut.name,
            link        = cut.link,
            rawGem      = cut.rawGem,
            reagents    = cut.reagents,
            sellPrice   = sellPrice,
            ingredCost  = ingredCost,
            missingReag = missingReag,
            allFound    = allFound,
            volume      = AHT.listingCounts[cut.name] or 0,
        }

        if allFound and sellPrice and sellPrice > 0 then
            local provision = math.floor(sellPrice * AHT.ahCutRate)
            local deposit   = AHT:CalcDeposit(cut.name)
            r.profit  = sellPrice - provision - deposit - ingredCost
            r.margin  = ingredCost > 0 and (r.profit / ingredCost * 100) or 0
            r.deposit = deposit
            r.provision = provision
        end

        table.insert(results, r)
    end

    -- Sortierung
    local mode = AHT.gemCutSortMode or "profit"
    local dir  = AHT.gemCutSortDir  or "desc"

    table.sort(results, function(a, b)
        local va = (mode == "margin") and (a.margin or -9e9) or (a.profit or -9e9)
        local vb = (mode == "margin") and (b.margin or -9e9) or (b.profit or -9e9)
        return dir == "asc" and va < vb or va > vb
    end)

    -- Filter
    local filter  = AHT.gemCutSearchFilter or ""
    local display = {}
    for _, r in ipairs(results) do
        if filter == "" or r.name:lower():find(filter:lower(), 1, true) then
            table.insert(display, r)
        end
    end

    AHT.gemCutResults        = results
    AHT.gemCutDisplayResults = display
end

-- ── Prospektions-Analyse ─────────────────────────────────────
-- Berechnet erwarteten Profit aus dem Prospektieren von X Erz
-- Erzmengen müssen ein Vielfaches von 5 sein (5 Erz = 1 Prospektions-Zug)
function AHT:CalculateProspectingResults(oreAmount)
    oreAmount = oreAmount or 20

    -- Prospektions-Raten zusammenführen: Server-spezifische überschreiben Defaults
    local rates = {}
    for ore, gems in pairs(DEFAULT_PROSPECT_RATES) do
        rates[ore] = {}
        for gem, r in pairs(gems) do rates[ore][gem] = r end
    end
    for ore, gems in pairs(AHT.prospectRates or {}) do
        if not rates[ore] then rates[ore] = {} end
        for gem, r in pairs(gems) do rates[ore][gem] = r end
    end

    local results = {}
    local prospects = math.floor(oreAmount / 5)

    for ore, gems in pairs(rates) do
        local orePrice = AHT.prices[ore]
        if orePrice then
            local oreCost    = orePrice * oreAmount
            local totalYield = 0
            local gemDetails = {}
            local allFound   = true

            for gem, rate in pairs(gems) do
                local expectedCount = prospects * rate
                if expectedCount >= 0.01 then
                    local bestCutProfit = 0
                    local bestCutName   = nil
                    local rawGemPrice   = AHT.prices[gem] or 0
                    local sellPrice     = rawGemPrice

                    for _, cut in ipairs(AHT.gemCuts) do
                        if cut.rawGem == gem and AHT.prices[cut.name] then
                            local cutProfit = (AHT.prices[cut.name] or 0) - rawGemPrice
                            if cutProfit > bestCutProfit then
                                bestCutProfit = cutProfit
                                bestCutName   = cut.name
                                sellPrice     = AHT.prices[cut.name]
                            end
                        end
                    end

                    if sellPrice and sellPrice > 0 then
                        local provision     = math.floor(sellPrice * AHT.ahCutRate)
                        local netPerGem     = sellPrice - provision
                        local contribution  = netPerGem * expectedCount
                        totalYield = totalYield + contribution
                        table.insert(gemDetails, {
                            gem      = gem,
                            rate     = rate,
                            expected = expectedCount,
                            bestCut  = bestCutName,
                            price    = sellPrice,
                            contrib  = contribution,
                        })
                    else
                        allFound = false
                    end
                end
            end

            table.insert(results, {
                ore        = ore,
                oreAmount  = oreAmount,
                orePrice   = orePrice,
                oreCost    = oreCost,
                totalYield = totalYield,
                profit     = totalYield - oreCost,
                allFound   = allFound,
                gemDetails = gemDetails,
            })
        end
    end

    -- Nach Profit sortieren
    table.sort(results, function(a, b)
        return (a.profit or -9e9) > (b.profit or -9e9)
    end)

    AHT.prospectResults = results
    return results
end

-- ── JC-Scan starten ──────────────────────────────────────────
-- Scannt alle rohen Gems + Cut Gems die für JC-Analyse benötigt werden
function AHT:StartJCScan()
    if AHT:IsScanning() then
        AHT:Print(AHT.L["scan_already_running"]); return
    end
    if not AuctionFrame or not AuctionFrame:IsVisible() then
        AHT:Print(AHT.L["scan_ah_required"]); return
    end
    if #AHT.gemCuts == 0 then
        AHT:Print(AHT.L["jc_no_recipes"]); return
    end

    local seen, queue = {}, {}

    -- Cut Gems (Output)
    for _, cut in ipairs(AHT.gemCuts) do
        if AHT.gemCutSelected[cut.name] ~= false and not seen[cut.name] then
            table.insert(queue, cut.name); seen[cut.name] = true
        end
        -- Raw Gems (Input)
        if cut.rawGem and not seen[cut.rawGem] then
            table.insert(queue, cut.rawGem); seen[cut.rawGem] = true
        end
    end

    -- Erzpreise für Prospecting
    local ores = { "Cobalt Ore", "Saronite Ore", "Titanium Ore",
                   "Kobaltliterz", "Saroniiterz", "Titanerz" }
    for _, ore in ipairs(ores) do
        if not seen[ore] then
            table.insert(queue, ore); seen[ore] = true
        end
    end

    if #queue == 0 then
        AHT:Print(AHT.L["scan_no_items"]); return
    end

    AHT.scanQueue         = queue
    AHT.scanQueueIdx      = 0
    AHT.scanMinPrices     = {}
    AHT.scanListingCounts = {}
    AHT.scanOffers        = {}

    AHT:Print(string.format(AHT.L["jc_scan_start"], #queue))
    AHT:SetScanButtonText(AHT.L["scan_cancel"])
    AHT:AdvanceScanQueue()
end

-- ── AH-Button ────────────────────────────────────────────────
function AHT:CreateJewelcraftingButton()
    if AHT.jcBtn then AHT.jcBtn:Show(); return end

    local btn = CreateFrame("Button", "ProjEP_AHT_JCBtn", UIParent, "UIPanelButtonTemplate")
    btn:SetSize(110, 22)
    btn:SetText(AHT.L["jc_button"])
    btn:SetPoint("TOPLEFT", AuctionFrame, "TOPLEFT", 597, -28)
    btn:SetScript("OnClick", function()
        AHT:ShowJCUI()
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("ProjEP AH Trader – Schmuckkunst")
        if #AHT.gemCuts == 0 then
            GameTooltip:AddLine(AHT.L["jc_no_recipes"], 1, 0.5, 0)
        else
            GameTooltip:AddLine(string.format(AHT.L["jc_status_ready"], #AHT.gemCuts), 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    AHT.jcBtn = btn
end

-- ── JC-Fenster ───────────────────────────────────────────────
local JC_FRAME_W  = 780
local JC_FRAME_H  = 480
local JC_ROW_H    = 20
local JC_MAX_ROWS = 14

local jcScrollOffset = 0

function AHT:ShowJCUI()
    if not AHT.jcFrame then
        AHT:CreateJCUI()
    end
    AHT:CalculateGemCutMargins()
    AHT.jcFrame:Show()
    AHT:RefreshJCUI()
end

function AHT:RefreshJCUI()
    if not AHT.jcFrame or not AHT.jcFrame:IsVisible() then return end

    local L        = AHT.L
    local display  = AHT.gemCutDisplayResults or {}

    if AHT.jcStatusText then
        AHT.jcStatusText:SetText(string.format(L["jc_status_ready"], #display))
    end

    local rows = AHT.jcRowFrames
    if not rows then return end

    for i = 1, JC_MAX_ROWS do
        local idx = i + jcScrollOffset
        local row = rows[i]
        if not row then break end

        if idx <= #display then
            local r = display[idx]
            row._data = r

            if row.cells.rank then
                row.cells.rank:SetText(tostring(idx))
            end
            if row.cells.name then
                row.cells.name:SetText(r.name)
            end
            if row.cells.rawCost then
                row.cells.rawCost:SetText(r.ingredCost > 0
                    and AHT:FormatMoneyPlain(r.ingredCost) or "|cff888888–|r")
            end
            if row.cells.sellPrice then
                row.cells.sellPrice:SetText(r.sellPrice
                    and AHT:FormatMoneyPlain(r.sellPrice) or L["ui_not_on_ah"])
            end
            if row.cells.profit then
                if r.profit then
                    local col = r.profit > 0 and "ff00ff00" or "ffff4444"
                    row.cells.profit:SetText(string.format("|c%s%s|r", col,
                        AHT:FormatMoneyPlain(math.abs(r.profit))))
                else
                    row.cells.profit:SetText("|cff888888–|r")
                end
            end
            if row.cells.margin then
                if r.margin then
                    local col = r.margin > 0 and "ff00ff00" or "ffff4444"
                    row.cells.margin:SetText(string.format("|c%s%.1f%%|r", col, r.margin))
                else
                    row.cells.margin:SetText("|cff888888–|r")
                end
            end
            row:Show()
        else
            row:Hide()
        end
    end
end

function AHT:CreateJCUI()
    if AHT.jcFrame then return end

    local L = AHT.L
    local f = CreateFrame("Frame", "ProjEP_AHT_JCUI", UIParent)
    f:SetSize(JC_FRAME_W, JC_FRAME_H)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, -30)
    f:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    f:SetBackdropColor(0.07, 0.07, 0.07, 1)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    f:SetFrameStrata("DIALOG")
    f:Hide()

    -- Titel
    local titleTex = f:CreateTexture(nil, "ARTWORK")
    titleTex:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    titleTex:SetSize(320, 64)
    titleTex:SetPoint("TOP", f, "TOP", 0, 12)

    local titleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOP", f, "TOP", 0, -5)
    titleText:SetText(L["jc_title"])

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)
    closeBtn:SetScript("OnClick", function(self) self:GetParent():Hide() end)

    -- Status
    local statusText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("TOPLEFT", f, "TOPLEFT", 15, -28)
    statusText:SetWidth(JC_FRAME_W - 200)
    statusText:SetJustifyH("LEFT")
    AHT.jcStatusText = statusText

    -- Scan-Button
    local btnScan = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnScan:SetSize(120, 22)
    btnScan:SetText(L["jc_scan_start"]:sub(1, 15) .. "…")
    btnScan:SetText("Gems scannen")
    btnScan:SetPoint("TOPRIGHT", f, "TOPRIGHT", -50, -24)
    btnScan:SetScript("OnClick", function() AHT:StartJCScan() end)

    -- Header
    local COLS = {
        { id="rank",      label="#",                     w=22,  x=12  },
        { id="name",      label=L["jc_col_gem"],         w=200, x=36  },
        { id="rawCost",   label=L["jc_col_raw_cost"],    w=100, x=239 },
        { id="sellPrice", label=L["jc_col_cut_price"],   w=100, x=342 },
        { id="profit",    label=L["jc_col_profit"],      w=100, x=445 },
        { id="margin",    label=L["jc_col_margin"],      w=70,  x=548 },
    }

    for _, col in ipairs(COLS) do
        local sortable = (col.id == "profit" or col.id == "margin")
        if sortable then
            local btn = CreateFrame("Button", nil, f)
            btn:SetPoint("TOPLEFT", f, "TOPLEFT", col.x - 2, -70 + 2)
            btn:SetSize(col.w + 4, 16)
            local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetAllPoints(btn)
            fs:SetJustifyH("RIGHT")
            fs:SetText("|cffffff00" .. col.label .. "|r")
            btn._colId = col.id
            btn:SetScript("OnClick", function(self)
                if AHT.gemCutSortMode == self._colId then
                    AHT.gemCutSortDir = AHT.gemCutSortDir == "desc" and "asc" or "desc"
                else
                    AHT.gemCutSortMode = self._colId
                    AHT.gemCutSortDir  = "desc"
                end
                jcScrollOffset = 0
                AHT:CalculateGemCutMargins()
                AHT:RefreshJCUI()
            end)
        else
            local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetPoint("TOPLEFT", f, "TOPLEFT", col.x, -70)
            fs:SetWidth(col.w)
            fs:SetJustifyH(col.id == "name" and "LEFT" or "RIGHT")
            fs:SetText("|cffffff00" .. col.label .. "|r")
        end
    end

    -- Trennlinie
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetTexture(0.6, 0.6, 0.6, 0.4)
    sep:SetPoint("TOPLEFT",  f, "TOPLEFT",  14, -86)
    sep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -86)
    sep:SetHeight(1)

    -- Datenzeilen
    local rowFrames = {}
    for i = 1, JC_MAX_ROWS do
        local yOff = -90 - (i - 1) * JC_ROW_H
        local row  = CreateFrame("Button", nil, f)
        row:SetPoint("TOPLEFT",  f, "TOPLEFT",  10, yOff)
        row:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, yOff)
        row:SetHeight(JC_ROW_H)
        row:RegisterForClicks("RightButtonUp", "LeftButtonUp")

        if i % 2 == 0 then
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetTexture(1, 1, 1, 0.04)
            bg:SetAllPoints(row)
        end

        local cells = {}
        for _, col in ipairs(COLS) do
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", row, "LEFT", col.x, 0)
            fs:SetWidth(col.w)
            fs:SetJustifyH(col.id == "name" and "LEFT" or "RIGHT")
            cells[col.id] = fs
        end
        row.cells = cells
        row:EnableMouse(true)

        row:SetScript("OnEnter", function(self)
            local d = self._data
            if not d then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine("|cffffd700" .. d.name .. "|r")
            if d.rawGem then
                GameTooltip:AddDoubleLine("Roher Edelstein:", d.rawGem, 1,1,1, 0.7,0.7,0.7)
                local rp = AHT.prices[d.rawGem]
                if rp then
                    GameTooltip:AddDoubleLine("  Preis:", AHT:FormatMoney(rp), 1,1,1, 1,1,0)
                end
            end
            if d.sellPrice then
                GameTooltip:AddDoubleLine("Verkaufspr.:", AHT:FormatMoney(d.sellPrice), 1,1,1, 0,1,0)
            end
            if d.provision then
                GameTooltip:AddDoubleLine("AH-Gebühr:", AHT:FormatMoney(d.provision), 1,1,1, 0.7,0.7,0.7)
            end
            if d.profit then
                local c = d.profit > 0 and {0, 1, 0} or {1, 0.3, 0.3}
                GameTooltip:AddDoubleLine("Gewinn:", AHT:FormatMoney(d.profit), 1,1,1, c[1],c[2],c[3])
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff00ccffShift+Rechtsklick: Posten|r")
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        row:SetScript("OnClick", function(self, btn)
            local d = self._data
            if not d then return end
            if btn == "RightButton" and IsShiftKeyDown() then
                if d.profit and d.profit > 0 then
                    AHT:ShowPostDialog(d.name, {
                        name       = d.name,
                        ingredCost = d.ingredCost,
                        sellPrice  = d.sellPrice,
                        profit     = d.profit,
                    })
                end
            end
        end)

        row:Hide()
        rowFrames[i] = row
    end
    AHT.jcRowFrames = rowFrames

    -- Scroll
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            if jcScrollOffset > 0 then jcScrollOffset = jcScrollOffset - 1; AHT:RefreshJCUI() end
        else
            if jcScrollOffset + JC_MAX_ROWS < #(AHT.gemCutDisplayResults or {}) then
                jcScrollOffset = jcScrollOffset + 1; AHT:RefreshJCUI()
            end
        end
    end)

    -- Keine Rezepte-Info
    local noRecipesLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    noRecipesLabel:SetPoint("CENTER", f, "CENTER", 0, 0)
    noRecipesLabel:SetText(L["jc_no_recipes"])
    noRecipesLabel:SetTextColor(1, 0.5, 0)
    AHT.jcNoRecipesLabel = noRecipesLabel

    AHT.jcFrame = f
end

if AHT and AHT._loadStatus then
    AHT._loadStatus.jewelcrafting = true
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[AHT-DIAG]|r Jewelcrafting.lua OK")
    end
end
