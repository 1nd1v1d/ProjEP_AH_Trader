-- ============================================================
-- ProjEP AH Trader - Inscription.lua
-- Inschriftenkunde: Glyphen-Analyse + Ink-Kostenberechnung
-- WotLK 3.3.5 / Lua 5.1 (Project Epoch)
--
-- Materialfluss:
--   5× Northrend-Kraut → mahlen → Azure Pigment (häufig) + Icy Pigment (selten)
--   2× Azure Pigment   → Ink of the Sea
--   2× Icy Pigment     → Snowfall Ink
--   Glyph = 2× Ink of the Sea + 1× Common Parchment (Vendor 50c)
-- ============================================================

local AHT = PROJEP_AHT

-- ── Standard-Mahl-Raten (pro 5 Kräuter) ─────────────────────
-- azure = durchschnittliche Azure Pigmente pro 5 Kräuter
-- icy   = durchschnittliche Icy Pigmente pro 5 Kräuter
-- Konfigurierbar über /aht millrate
local DEFAULT_MILL_RATES = {
    -- Northrend
    ["Icethorn"]       = { azure = 2.5,  icy = 0.12 },
    ["Lichbloom"]      = { azure = 2.5,  icy = 0.12 },
    ["Adder's Tongue"] = { azure = 2.5,  icy = 0.10 },
    ["Goldclover"]     = { azure = 2.3,  icy = 0.04 },
    ["Tiger Lily"]     = { azure = 2.3,  icy = 0.04 },
    ["Talandra's Rose"]= { azure = 2.3,  icy = 0.06 },
    ["Deadnettle"]     = { azure = 2.2,  icy = 0.04 },
    -- Deutsche Namen
    ["Eisdorn"]        = { azure = 2.5,  icy = 0.12 },
    ["Lichblüte"]      = { azure = 2.5,  icy = 0.12 },
    ["Otterngras"]     = { azure = 2.5,  icy = 0.10 },
    ["Goldklee"]       = { azure = 2.3,  icy = 0.04 },
    ["Tigerlilie"]     = { azure = 2.3,  icy = 0.04 },
    ["Talandras Rose"] = { azure = 2.3,  icy = 0.06 },
    ["Taubnessel"]     = { azure = 2.2,  icy = 0.04 },
}

-- Parchment-Preise (Vendor)
local PARCHMENT_COSTS = {
    ["Light Parchment"]     = 25,
    ["Common Parchment"]    = 50,
    ["Heavy Parchment"]     = 100,
    ["Leichtes Pergament"]  = 25,
    ["Normales Pergament"]  = 50,
    ["Schweres Pergament"]  = 100,
}

-- Standard-Parchment für Northrend-Glyphen
local DEFAULT_PARCHMENT    = "Common Parchment"
local DEFAULT_PARCHMENT_DE = "Normales Pergament"
local INK_NAME_EN = "Ink of the Sea"
local INK_NAME_DE = "Tinte des Meeres"
local SNOWFALL_NAME_EN = "Snowfall Ink"
local SNOWFALL_NAME_DE = "Schneefallstinte"
local AZURE_PIGMENT_EN = "Azure Pigment"
local AZURE_PIGMENT_DE = "Azurpigment"

-- Profession names for detection
local INSCRIPTION_NAMES = {
    ["inscription"]       = true,
    ["inschriftenkunde"]  = true,
    ["calligraphie"]      = true,
    ["inscripción"]       = true,
}

-- ── Glyphen-Rezepte aus Berufe-Fenster lesen ─────────────────
AHT.glyphs             = AHT.glyphs or {}
AHT.glyphSortMode      = "profit"
AHT.glyphSortDir       = "desc"
AHT.glyphSearchFilter  = ""
AHT._inscriptionLoaded = false

function AHT:LearnInscriptionRecipes()
    if AHT._inscriptionLoadGuard then return end
    AHT._inscriptionLoadGuard = true

    local profName = GetTradeSkillLine()
    if not profName or not INSCRIPTION_NAMES[profName:lower()] then
        AHT._inscriptionLoadGuard = false; return
    end

    local numSkills = GetNumTradeSkills()
    if not numSkills or numSkills == 0 then
        AHT._inscriptionLoadGuard = false; return
    end

    local newGlyphs = {}
    local seen      = {}

    for i = 1, numSkills do
        local skillName, skillType = GetTradeSkillInfo(i)
        if skillName and skillType ~= "header" then
            local lower = skillName:lower()
            -- Nur Glyphen verarbeiten (Name enthält "Glyph" / "Glyphe")
            if lower:find("glyph") or lower:find("glyphe") then
                if not seen[skillName] then
                    seen[skillName] = true

                    local reagents  = {}
                    local numReag   = GetTradeSkillNumReagents(i)
                    local allLoaded = true

                    for r = 1, numReag do
                        local rName, _, rCount = GetTradeSkillReagentInfo(i, r)
                        if rName and rName ~= "" then
                            table.insert(reagents, { name = rName, count = rCount or 1 })
                        else
                            allLoaded = false
                        end
                    end

                    if allLoaded then
                        local link = GetTradeSkillItemLink and GetTradeSkillItemLink(i) or nil
                        -- Klassen-Extraktion: "Glyph of Fireball" → Klasse aus Reagenz oder heuristisch
                        table.insert(newGlyphs, {
                            name     = skillName,
                            link     = link,
                            reagents = reagents,
                        })
                        if AHT.glyphSelected[skillName] == nil then
                            AHT.glyphSelected[skillName] = true
                        end
                    end
                end
            end
        end
    end

    -- Zusammenführen
    local existingMap = {}
    for _, g in ipairs(AHT.glyphs) do existingMap[g.name] = true end
    for _, g in ipairs(newGlyphs) do
        if not existingMap[g.name] then
            table.insert(AHT.glyphs, g)
        end
    end

    AHT._inscriptionLoaded = #AHT.glyphs > 0
    AHT:SaveDB()
    AHT:Print(string.format(AHT.L["recipes_loaded_count"]:gsub("Rezepte", "Glyphen"):gsub("recipes", "glyphs"), #AHT.glyphs))
    AHT._inscriptionLoadGuard = false
end

-- ── Ink-Kosten berechnen ──────────────────────────────────────
-- Gibt zurück: { cost, herb, herbPrice } oder nil
function AHT:CalcInkCost()
    -- 1) Direkte Tinte vom AH (beide Sprachnamen prüfen)
    local inkDE = GetLocale() == "deDE" and INK_NAME_DE or INK_NAME_EN
    local inkPrice = AHT.prices[INK_NAME_EN] or AHT.prices[INK_NAME_DE]

    -- 2) Günstigstes Kraut errechnen
    local millRates = AHT.millRates or {}
    local bestHerbCost  = nil
    local bestHerbName  = nil

    for herbName, rates in pairs(DEFAULT_MILL_RATES) do
        -- Aktuelle Mahl-Rates aus SavedVars überschreiben Defaults
        local finalRates = millRates[herbName] or rates
        local herbPrice  = AHT.prices[herbName]
        if herbPrice and finalRates.azure and finalRates.azure > 0 then
            -- Inks pro 5 Kräuter: azure_pigments / 2
            local inksPerFive = finalRates.azure / 2
            if inksPerFive > 0 then
                local costPerInk = math.ceil((herbPrice * 5) / inksPerFive)
                if not bestHerbCost or costPerInk < bestHerbCost then
                    bestHerbCost = costPerInk
                    bestHerbName = herbName
                end
            end
        end
    end

    -- Günstigste Quelle wählen
    if bestHerbCost and (not inkPrice or bestHerbCost < inkPrice) then
        return { cost = bestHerbCost, source = bestHerbName, sourcePrice = AHT.prices[bestHerbName] }
    elseif inkPrice then
        return { cost = inkPrice, source = INK_NAME_EN, sourcePrice = inkPrice }
    end
    return nil
end

-- ── Glyphen-Margen berechnen ─────────────────────────────────
function AHT:CalculateGlyphMargins()
    local inkData     = AHT:CalcInkCost()
    local inkCost     = inkData and inkData.cost or nil
    local parchLocale = (GetLocale() == "deDE") and DEFAULT_PARCHMENT_DE or DEFAULT_PARCHMENT
    local parchCost   = PARCHMENT_COSTS[parchLocale] or PARCHMENT_COSTS[DEFAULT_PARCHMENT] or 50

    local results = {}

    for _, glyph in ipairs(AHT.glyphs) do
        if AHT.glyphSelected[glyph.name] ~= false then
            local ingredCost = 0
            local allFound   = true
            local missing    = {}

            for _, reagent in ipairs(glyph.reagents) do
                -- Parchments sind Vendor-Items
                local vendorP = PARCHMENT_COSTS[reagent.name]
                if vendorP then
                    ingredCost = ingredCost + vendorP * reagent.count
                else
                    -- Tinte → verwende berechneten Ink-Preis
                    local isInk = reagent.name:lower():find("ink") or
                                  reagent.name:lower():find("tinte")
                    if isInk and inkCost then
                        ingredCost = ingredCost + inkCost * reagent.count
                    else
                        local p = AHT.prices[reagent.name]
                        if p then
                            ingredCost = ingredCost + p * reagent.count
                        else
                            allFound = false
                            table.insert(missing, reagent.name)
                        end
                    end
                end
            end

            local sellPrice = AHT.prices[glyph.name]
            local r = {
                name        = glyph.name,
                link        = glyph.link,
                reagents    = glyph.reagents,
                ingredCost  = ingredCost,
                sellPrice   = sellPrice,
                inkSource   = inkData and inkData.source or nil,
                inkCost     = inkCost,
                allFound    = allFound,
                missing     = missing,
                volume      = AHT.listingCounts[glyph.name] or 0,
                avgSellPrice = AHT:GetPriceAverage(glyph.name),
            }

            if sellPrice and allFound then
                local provision = math.floor(sellPrice * AHT.ahCutRate)
                local deposit   = AHT:CalcDeposit(glyph.name)
                local net       = sellPrice - provision - deposit
                r.profit  = net - ingredCost
                r.margin  = ingredCost > 0 and (r.profit / ingredCost) * 100 or 0
                r.depositCost = deposit
                r.ahProvision = provision
            end

            table.insert(results, r)
        end
    end

    AHT.glyphResults = results
    AHT:ApplyGlyphFilterAndSort()
    return results
end

function AHT:ApplyGlyphFilterAndSort()
    local filtered = {}
    local filter   = string.lower(AHT.glyphSearchFilter or "")
    local classF   = AHT.glyphClassFilter

    for _, r in ipairs(AHT.glyphResults) do
        local nameMatch  = filter == "" or string.find(string.lower(r.name), filter, 1, true)
        table.insert(filtered, r)
    end

    local mode   = AHT.glyphSortMode or "profit"
    local isDesc = (AHT.glyphSortDir or "desc") == "desc"

    table.sort(filtered, function(a, b)
        local va = (mode == "margin") and (a.margin or -999999) or (a.profit or -999999)
        local vb = (mode == "margin") and (b.margin or -999999) or (b.profit or -999999)
        return isDesc and (va > vb) or (va < vb)
    end)
    AHT.glyphDisplayResults = filtered
end

-- ── Scan-Queue für Glyphen aufbauen ──────────────────────────
function AHT:BuildGlyphScanQueue()
    local seen, queue = {}, {}
    for _, g in ipairs(AHT.glyphs) do
        if AHT.glyphSelected[g.name] ~= false then
            if not seen[g.name] and not AHT:IsVendorItem(g.name) then
                table.insert(queue, g.name); seen[g.name] = true
            end
            for _, r in ipairs(g.reagents) do
                if not seen[r.name] and not PARCHMENT_COSTS[r.name]
                   and not AHT:IsVendorItem(r.name) then
                    table.insert(queue, r.name); seen[r.name] = true
                end
            end
        end
    end
    -- Tinten-Namen
    for _, inkName in ipairs({ INK_NAME_EN, INK_NAME_DE }) do
        if not seen[inkName] then
            table.insert(queue, inkName); seen[inkName] = true
        end
    end
    -- Northrend-Kräuter
    for herb in pairs(DEFAULT_MILL_RATES) do
        if not seen[herb] then
            table.insert(queue, herb); seen[herb] = true
        end
    end
    return queue
end

-- ── Inscription-Button ────────────────────────────────────────
function AHT:CreateInscriptionButton()
    if AHT.inscriptionButton then AHT.inscriptionButton:Show(); return end
    local btn = CreateFrame("Button", "ProjEP_AHT_InscBtn", UIParent, "UIPanelButtonTemplate")
    btn:SetSize(100, 22)
    btn:SetText(AHT.L["inscription_button"])
    btn:SetPoint("TOPLEFT", AuctionFrame, "TOPLEFT", 712, -28)
    btn:SetScript("OnClick", function(self) AHT:ShowInscriptionUI() end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(AHT.L["inscription_title"])
        GameTooltip:AddLine(string.format(AHT.L["inscription_status_ready"], #AHT.glyphs), 1,1,1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    AHT.inscriptionButton = btn
end

-- ── Inscription-UI (vereinfacht) ─────────────────────────────
local INS_W, INS_H = 700, 420

function AHT:ShowInscriptionUI()
    if not PROJEP_AHT_InscriptionUI then AHT:CreateInscriptionUI() end
    AHT:CalculateGlyphMargins()
    PROJEP_AHT_InscriptionUI:Show()
    AHT:RefreshInscriptionUI()
end

function AHT:CreateInscriptionUI()
    if PROJEP_AHT_InscriptionUI then return end

    local f = CreateFrame("Frame", "PROJEP_AHT_InscriptionUI", UIParent)
    f:SetSize(INS_W, INS_H)
    f:SetPoint("CENTER", 50, 0)
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
    titleTex:SetSize(320, 64); titleTex:SetPoint("TOP", f, "TOP", 0, 12)
    local titleStr = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleStr:SetPoint("TOP", f, "TOP", 0, -5)
    titleStr:SetText(AHT.L["inscription_title"])
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)
    closeBtn:SetScript("OnClick", function(self) self:GetParent():Hide() end)

    -- Status / Ink-Info
    local statusFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusFS:SetPoint("TOPLEFT", f, "TOPLEFT", 15, -28)
    statusFS:SetWidth(INS_W - 30); statusFS:SetJustifyH("LEFT")
    f._status = statusFS

    -- Header
    local hY = -50
    local headers = {
        { text = AHT.L["inscription_col_glyph"],    x = 14,  w = 230 },
        { text = AHT.L["inscription_col_ink_cost"],  x = 250, w = 110 },
        { text = AHT.L["inscription_col_sell"],      x = 366, w = 100 },
        { text = AHT.L["inscription_col_profit"],    x = 472, w = 100 },
        { text = AHT.L["inscription_col_margin"],    x = 578, w = 80  },
    }
    for _, h in ipairs(headers) do
        local hs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hs:SetPoint("TOPLEFT", f, "TOPLEFT", h.x, hY)
        hs:SetWidth(h.w); hs:SetJustifyH("LEFT")
        hs:SetText("|cffffff00" .. h.text .. "|r")
    end
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetTexture(0.6, 0.6, 0.6, 0.4)
    sep:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -62)
    sep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -62)
    sep:SetHeight(1)

    -- Scrollframe
    local sf = CreateFrame("ScrollFrame", nil, f)
    sf:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -66)
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 46)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(INS_W - 44, 1)
    sf:SetScrollChild(content)
    f._content = content

    local sb = CreateFrame("Slider", nil, f, "UIPanelScrollBarTemplate")
    sb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -66)
    sb:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 46)
    sb:SetMinMaxValues(0, 0); sb:SetValueStep(20); sb:SetValue(0)
    sb:SetScript("OnValueChanged", function(self, v) sf:SetVerticalScroll(v) end)
    sf:SetScript("OnMouseWheel", function(self, d)
        sb:SetValue(sb:GetValue() - d * 20)
    end)
    f._scrollbar = sb

    -- Scan-Button
    local scanBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    scanBtn:SetSize(130, 22)
    scanBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 12)
    scanBtn:SetText("Scannen")
    scanBtn:SetScript("OnClick", function(self)
        if not AuctionFrame or not AuctionFrame:IsVisible() then
            AHT:Print(AHT.L["scan_ah_required"]); return
        end
        -- Glyphen-Scan: Item-für-Item für alle Glyphen + Zutaten
        AHT.scanQueue        = AHT:BuildGlyphScanQueue()
        AHT.scanQueueIdx     = 0
        AHT.scanMinPrices    = {}
        AHT.scanListingCounts = {}
        AHT.scanOffers       = {}
        if #AHT.scanQueue > 0 then
            AHT:Print(string.format(AHT.L["inscription_scan_start"], #AHT.scanQueue))
            AHT:SetScanButtonText(AHT.L["scan_cancel"])
            AHT:AdvanceScanQueue()
        end
    end)
    f._scanBtn = scanBtn

    f._rows = {}
    PROJEP_AHT_InscriptionUI = f
end

function AHT:RefreshInscriptionUI()
    local f = PROJEP_AHT_InscriptionUI
    if not f or not f:IsVisible() then return end

    AHT:CalculateGlyphMargins()
    local inkData = AHT:CalcInkCost()
    if inkData then
        f._status:SetText(string.format(AHT.L["inscription_status_ready"], #AHT.glyphDisplayResults)
            .. "  |cffaaaaaa" .. string.format(AHT.L["inscription_ink_cost_calc"],
                AHT:FormatMoneyPlain(inkData.cost), inkData.source) .. "|r")
    else
        f._status:SetText(#AHT.glyphs == 0
            and AHT.L["inscription_no_recipes"]
            or  string.format(AHT.L["inscription_status_ready"], #AHT.glyphDisplayResults))
    end

    local content = f._content
    for _, row in ipairs(f._rows or {}) do row:Hide() end
    f._rows = {}

    local rowH = 18
    local y    = 0

    for i, r in ipairs(AHT.glyphDisplayResults) do
        local row = CreateFrame("Button", nil, content)
        row:SetSize(INS_W - 44, rowH)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        row:EnableMouse(true)

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        if i % 2 == 0 then bg:SetTexture(0.1, 0.1, 0.1, 0.5)
        else bg:SetTexture(0, 0, 0, 0) end

        local function fs(xOff, w, text)
            local s = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            s:SetPoint("LEFT", row, "LEFT", xOff, 0)
            s:SetWidth(w); s:SetJustifyH("LEFT"); s:SetText(text)
            return s
        end

        fs(0, 230, r.name)
        fs(236, 110, r.ingredCost > 0 and AHT:FormatMoney(r.ingredCost) or "|cffaaaaaa?|r")
        fs(352, 100, r.sellPrice and AHT:FormatMoney(r.sellPrice) or "|cffaaaaaa?|r")
        if r.profit then
            local col = r.profit >= 0 and "|cff00ff00" or "|cffff5555"
            fs(458, 100, col .. AHT:FormatMoney(r.profit) .. "|r")
            local mc = r.margin >= 20 and "|cff00ff00" or (r.margin > 0 and "|cffffff00" or "|cffff5555")
            fs(564, 80, mc .. string.format("%.1f%%", r.margin) .. "|r")
        else
            fs(458, 180, "|cffaaaaaa" .. (#r.missing > 0 and table.concat(r.missing, ", "):sub(1,25) or "?") .. "|r")
        end

        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(r.name, 1, 1, 0)
            for _, ing in ipairs(r.reagents) do
                local isVend = PARCHMENT_COSTS[ing.name]
                local p = isVend or AHT.prices[ing.name] or 0
                local src = isVend and AHT.L["tt_source_vendor"] or AHT.L["tt_source_ah"]
                GameTooltip:AddDoubleLine(ing.count .. "× " .. ing.name,
                    AHT:FormatMoneyPlain(p * ing.count) .. " (" .. src .. ")", 0.8,0.8,0.8,1,1,1)
            end
            if r.profit then
                GameTooltip:AddLine(" ")
                GameTooltip:AddDoubleLine(AHT.L["tt_profit"],
                    AHT:FormatMoneyPlain(r.profit), 0,1,0,0,1,0)
                GameTooltip:AddDoubleLine(AHT.L["tt_margin"],
                    string.format("%.1f%%", r.margin), 1,1,0,1,1,0)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        table.insert(f._rows, row)
        y = y + rowH
    end

    content:SetHeight(math.max(y, 1))
    local vis = f:GetHeight() - 112
    local ms  = math.max(0, y - vis)
    f._scrollbar:SetMinMaxValues(0, ms)
    if f._scrollbar:GetValue() > ms then f._scrollbar:SetValue(ms) end
end

if AHT and AHT._loadStatus then
    AHT._loadStatus.inscription = true
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[AHT-DIAG]|r Inscription.lua OK")
    end
end
