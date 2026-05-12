-- ============================================================
-- ProjEP AH Trader - Mats.lua
-- Material-Analyse: Preisabweichung, Geschichte, Kauf-Dialog
-- WotLK 3.3.5 / Lua 5.1 (Project Epoch)
--
-- Bietet:
--   1. Material-Verwaltung (Add/Remove Dialog)
--   2. Material-Analyse-Fenster (Preisabweichung + Historie)
--   3. Material-Kauf-Dialog
-- ============================================================

local AHT = PROJEP_AHT

-- ── Layout-Konstanten ────────────────────────────────────────
local MATS_FRAME_W  = 780
local MATS_FRAME_H  = 480
local MATS_ROW_H    = 20
local MATS_MAX_ROWS = 14

local matsScrollOffset = 0

-- ── Gewichteter Durchschnitt ─────────────────────────────────
-- Neuere Werte werden höher gewichtet (exponentiell)
-- Gibt den neuen gewichteten Durchschnitt zurück
function AHT:CalcWeightedMatAverage(itemName, newPrice)
    local hist = AHT.matsHistory[itemName]
    if not hist or #hist == 0 then
        return newPrice
    end

    -- Letzten gespeicherten weighted_avg holen
    local lastEntry = hist[#hist]
    local prevWA    = lastEntry.weighted_avg or lastEntry.p or newPrice
    -- EMA mit alpha=0.3 (neuere Daten 30% gewichten)
    local alpha     = 0.3
    return math.floor(prevWA * (1 - alpha) + newPrice * alpha)
end

-- ── Mats-Margen berechnen ────────────────────────────────────
function AHT:CalculateMatsMargins()
    local results = {}
    local matList = AHT:GetMaterialsList()

    for _, matName in ipairs(matList) do
        local currentPrice  = AHT.prices[matName]
        local listingCount  = AHT.listingCounts[matName] or 0
        local hist          = AHT.matsHistory[matName] or {}
        local historyLength = #hist

        -- Gewichteten Durchschnitt aus Historie berechnen
        local weighted_avg = nil
        if historyLength > 0 then
            weighted_avg = hist[historyLength].weighted_avg or hist[historyLength].p
        end

        -- Abweichung berechnen
        local deviation = nil
        if currentPrice and weighted_avg and weighted_avg > 0 then
            deviation = ((currentPrice - weighted_avg) / weighted_avg) * 100
        end

        -- Letzten Scan-Zeitpunkt
        local lastUpdate = AHT.priceUpdated[matName]
        if not lastUpdate and historyLength > 0 then
            lastUpdate = hist[historyLength].t
        end

        table.insert(results, {
            name          = matName,
            currentPrice  = currentPrice,
            weighted_avg  = weighted_avg,
            deviation     = deviation,
            listingCount  = listingCount,
            historyLength = historyLength,
            lastUpdate    = lastUpdate,
        })
    end

    -- Sortierung anwenden
    local mode = AHT.matsSortMode or "deviation"
    local dir  = AHT.matsSortDir  or "desc"

    local sortFuncs = {
        name = function(a, b)
            if dir == "asc" then return a.name < b.name
            else return a.name > b.name end
        end,
        current = function(a, b)
            local pa = a.currentPrice or 0
            local pb = b.currentPrice or 0
            return dir == "asc" and pa < pb or pa > pb
        end,
        deviation = function(a, b)
            local da = a.deviation or 0
            local db = b.deviation or 0
            return dir == "asc" and da < db or da > db
        end,
    }

    local fn = sortFuncs[mode] or sortFuncs["deviation"]
    table.sort(results, fn)

    -- Filter anwenden
    local filter  = AHT.matsSearchFilter or ""
    local display = {}
    for _, r in ipairs(results) do
        if filter == "" or r.name:lower():find(filter:lower(), 1, true) then
            table.insert(display, r)
        end
    end

    AHT.matsResults        = results
    AHT.matsDisplayResults = display
end

-- ── Material-Analyse-Fenster ─────────────────────────────────
function AHT:ShowMatsUI()
    if not AHT.matsMainFrame then
        AHT:CreateMatsUI()
    end
    AHT:CalculateMatsMargins()
    AHT.matsMainFrame:Show()
    AHT:RefreshMatsUI()
end

function AHT:RefreshMatsUI()
    if not AHT.matsMainFrame or not AHT.matsMainFrame:IsVisible() then return end

    local L = AHT.L
    local statusText = AHT.matsMainFrame._statusText
    if statusText then
        if AHT:IsMatScanning() then
            statusText:SetText(string.format(L["mats_status_scanning"],
                AHT.matsScanQueueIdx or 0, #(AHT.matsScanQueue or {}),
                AHT.matsCurrentItem or ""))
        else
            statusText:SetText(string.format(L["mats_status_ready"],
                #AHT.matsDisplayResults))
        end
    end

    -- Suchfilter aktualisieren
    local sb = AHT.matsSearchBox
    if sb and sb:GetText() ~= AHT.matsSearchFilter then
        -- nicht überschreiben wenn der User gerade tippt
    end

    local rowFrames = AHT.matsRowFrames
    if not rowFrames then return end

    for i = 1, MATS_MAX_ROWS do
        local idx = i + matsScrollOffset
        local row = rowFrames[i]
        if not row then break end

        if idx <= #AHT.matsDisplayResults then
            local r = AHT.matsDisplayResults[idx]
            row._matData = r

            -- Checkbox
            local cb = row.cells.sel
            if cb then
                cb:SetChecked(AHT.matsSelected[r.name] ~= false)
            end

            -- Name
            if row.cells.name then
                row.cells.name:SetText(r.name)
            end

            -- Aktueller Preis
            if row.cells.current then
                row.cells.current:SetText(r.currentPrice
                    and AHT:FormatMoneyPlain(r.currentPrice)
                    or L["ui_not_on_ah"])
            end

            -- Gewichteter Durchschnitt
            if row.cells.weighted then
                row.cells.weighted:SetText(r.weighted_avg
                    and AHT:FormatMoneyPlain(r.weighted_avg)
                    or "|cff888888–|r")
            end

            -- Abweichung (farbcodiert)
            if row.cells.deviation then
                if r.deviation then
                    local d = r.deviation
                    local hex
                    if d < -20 then hex = "ff00ff00"     -- günstig: grün
                    elseif d > 20 then hex = "ffff4444"  -- teuer: rot
                    else hex = "ffffff00" end             -- normal: gelb
                    row.cells.deviation:SetText(string.format("|c%s%+.1f%%|r", hex, d))
                else
                    row.cells.deviation:SetText("|cff888888–|r")
                end
            end

            -- Listings
            if row.cells.listings then
                row.cells.listings:SetText(tostring(r.listingCount))
            end

            -- Historieneinträge
            if row.cells.history then
                row.cells.history:SetText(tostring(r.historyLength))
            end

            row:Show()
        else
            row:Hide()
        end
    end

    -- Scroll-Buttons
    if AHT.matsScrollUpBtn then
        if matsScrollOffset > 0 then AHT.matsScrollUpBtn:Enable()
        else AHT.matsScrollUpBtn:Disable() end
    end
    if AHT.matsScrollDownBtn then
        if matsScrollOffset + MATS_MAX_ROWS < #AHT.matsDisplayResults then
            AHT.matsScrollDownBtn:Enable()
        else AHT.matsScrollDownBtn:Disable() end
    end
end

function AHT:CreateMatsUI()
    if AHT.matsMainFrame then return end

    local L = AHT.L
    local f = CreateFrame("Frame", "ProjEP_AHT_MatsUI", UIParent)
    f:SetWidth(MATS_FRAME_W)
    f:SetHeight(MATS_FRAME_H)
    f:SetPoint("CENTER", UIParent, "CENTER", 300, 50)
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

    -- Titelleiste
    local titleTex = f:CreateTexture(nil, "ARTWORK")
    titleTex:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    titleTex:SetWidth(320); titleTex:SetHeight(64)
    titleTex:SetPoint("TOP", f, "TOP", 0, 12)

    local titleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOP", f, "TOP", 0, -5)
    titleText:SetText(L["mats_title"])

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)
    closeBtn:SetScript("OnClick", function(self) self:GetParent():Hide() end)

    -- Status
    local statusText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("TOPLEFT", f, "TOPLEFT", 15, -28)
    statusText:SetWidth(MATS_FRAME_W - 250)
    statusText:SetJustifyH("LEFT")
    f._statusText = statusText

    -- Buttons oben rechts
    local btnManage = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnManage:SetSize(140, 22)
    btnManage:SetText(L["mats_btn_manage"])
    btnManage:SetPoint("TOPRIGHT", f, "TOPRIGHT", -50, -24)
    btnManage:SetScript("OnClick", function() AHT:ShowMatsManageDialog() end)

    -- Scan-Button
    local btnScan = CreateFrame("Button", "ProjEP_AHT_MatsScanBtn", f, "UIPanelButtonTemplate")
    btnScan:SetSize(130, 22)
    btnScan:SetText(L["mats_button"])
    btnScan:SetPoint("TOPRIGHT", f, "TOPRIGHT", -195, -24)
    btnScan:SetScript("OnClick", function()
        if AHT:IsMatScanning() then AHT:CancelMatsScan()
        else AHT:StartMatsScan() end
    end)
    AHT.matsScanBtn = btnScan

    -- Suchfeld
    local searchLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 15, -50)
    searchLabel:SetText("|cffaaaaaa" .. L["ui_search_hint"] .. "|r")

    local searchBox = CreateFrame("EditBox", "ProjEP_AHT_MatsSearchBox", f, "InputBoxTemplate")
    searchBox:SetSize(160, 20)
    searchBox:SetPoint("TOPLEFT", f, "TOPLEFT", 60, -48)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(30)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchBox:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)
    searchBox:SetScript("OnTextChanged", function(self)
        AHT.matsSearchFilter = self:GetText() or ""
        matsScrollOffset = 0
        AHT:CalculateMatsMargins()
        AHT:RefreshMatsUI()
    end)
    AHT.matsSearchBox = searchBox

    -- Spalten-Header
    local COLS = {
        { id="sel",      label="",                          w=18,  x=12  },
        { id="name",     label=L["mats_col_name"],          w=155, x=35  },
        { id="current",  label=L["mats_col_current"],       w=90,  x=193 },
        { id="weighted", label=L["mats_col_avg"],           w=90,  x=286 },
        { id="deviation",label=L["mats_col_deviation"],     w=85,  x=379 },
        { id="listings", label=L["mats_col_listings"],      w=65,  x=467 },
        { id="history",  label=L["mats_col_scans"],         w=65,  x=535 },
    }

    for _, col in ipairs(COLS) do
        if col.id ~= "sel" and col.label ~= "" then
            local sortable = (col.id == "current" or col.id == "deviation")
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
                    if AHT.matsSortMode == self._colId then
                        AHT.matsSortDir = AHT.matsSortDir == "desc" and "asc" or "desc"
                    else
                        AHT.matsSortMode = self._colId
                        AHT.matsSortDir  = "desc"
                    end
                    matsScrollOffset = 0
                    AHT:CalculateMatsMargins()
                    AHT:RefreshMatsUI()
                end)
            else
                local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                fs:SetPoint("TOPLEFT", f, "TOPLEFT", col.x, -70)
                fs:SetWidth(col.w)
                fs:SetJustifyH(col.id == "name" and "LEFT" or "RIGHT")
                fs:SetText("|cffffff00" .. col.label .. "|r")
            end
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
    for i = 1, MATS_MAX_ROWS do
        local yOff = -90 - (i - 1) * MATS_ROW_H
        local row  = CreateFrame("Button", nil, f)
        row:SetPoint("TOPLEFT",  f, "TOPLEFT",  10, yOff)
        row:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, yOff)
        row:SetHeight(MATS_ROW_H)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        if i % 2 == 0 then
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetTexture(1, 1, 1, 0.04)
            bg:SetAllPoints(row)
        end

        local cells = {}

        -- Checkbox
        local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        cb:SetSize(18, 18)
        cb:SetPoint("LEFT", row, "LEFT", 12, 0)
        cb:SetScript("OnClick", function(self)
            local r = row._matData
            if not r then return end
            AHT.matsSelected[r.name] = self:GetChecked() and true or false
            AHT:SaveDB()
            AHT:CalculateMatsMargins()
            AHT:RefreshMatsUI()
        end)
        cells.sel = cb

        -- Name
        local nameFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameFs:SetPoint("LEFT", row, "LEFT", 35, 0)
        nameFs:SetWidth(155)
        nameFs:SetJustifyH("LEFT")
        cells.name = nameFs

        -- Current
        local curFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        curFs:SetPoint("LEFT", row, "LEFT", 193, 0)
        curFs:SetWidth(85)
        curFs:SetJustifyH("RIGHT")
        cells.current = curFs

        -- Weighted Avg
        local waFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        waFs:SetPoint("LEFT", row, "LEFT", 286, 0)
        waFs:SetWidth(85)
        waFs:SetJustifyH("RIGHT")
        cells.weighted = waFs

        -- Deviation
        local devFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        devFs:SetPoint("LEFT", row, "LEFT", 379, 0)
        devFs:SetWidth(80)
        devFs:SetJustifyH("RIGHT")
        cells.deviation = devFs

        -- Listings
        local listFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        listFs:SetPoint("LEFT", row, "LEFT", 467, 0)
        listFs:SetWidth(60)
        listFs:SetJustifyH("RIGHT")
        cells.listings = listFs

        -- History
        local histFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        histFs:SetPoint("LEFT", row, "LEFT", 535, 0)
        histFs:SetWidth(60)
        histFs:SetJustifyH("RIGHT")
        cells.history = histFs

        row.cells = cells
        row:EnableMouse(true)

        -- Tooltip + Rechtsklick = Kaufdialog
        row:SetScript("OnEnter", function(self)
            local r = self._matData
            if not r then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine("|cffffd700" .. r.name .. "|r")
            if r.currentPrice then
                GameTooltip:AddDoubleLine("Aktuell:", AHT:FormatMoney(r.currentPrice), 1,1,1, 1,1,0)
            end
            if r.weighted_avg then
                GameTooltip:AddDoubleLine("Ø (gewichtet):", AHT:FormatMoney(r.weighted_avg), 1,1,1, 0.7,0.7,0.7)
            end
            if r.deviation then
                local d = r.deviation
                local cr = d < -20 and 0 or (d > 20 and 1 or 1)
                local cg = d < -20 and 1 or (d > 20 and 0.3 or 1)
                GameTooltip:AddDoubleLine("Abweichung:", string.format("%+.1f%%", d), 1,1,1, cr,cg,0)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff00ccffRechtsklick: Kaufen|r")
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        row:SetScript("OnClick", function(self, btn)
            local r = self._matData
            if not r then return end
            if btn == "RightButton" then
                AHT:ShowMatsBuyDialog(r)
            end
        end)

        row:Hide()
        rowFrames[i] = row
    end
    AHT.matsRowFrames = rowFrames

    -- Scroll-Buttons
    local scrollUp = CreateFrame("Button", nil, f, "UIPanelScrollUpButtonTemplate")
    scrollUp:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -89)
    scrollUp:SetScript("OnClick", function()
        if matsScrollOffset > 0 then
            matsScrollOffset = matsScrollOffset - 1
            AHT:RefreshMatsUI()
        end
    end)
    AHT.matsScrollUpBtn = scrollUp

    local scrollDown = CreateFrame("Button", nil, f, "UIPanelScrollDownButtonTemplate")
    scrollDown:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 32)
    scrollDown:SetScript("OnClick", function()
        if matsScrollOffset + MATS_MAX_ROWS < #AHT.matsDisplayResults then
            matsScrollOffset = matsScrollOffset + 1
            AHT:RefreshMatsUI()
        end
    end)
    AHT.matsScrollDownBtn = scrollDown

    -- Mausrad-Scroll
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            if matsScrollOffset > 0 then
                matsScrollOffset = matsScrollOffset - 1
                AHT:RefreshMatsUI()
            end
        else
            if matsScrollOffset + MATS_MAX_ROWS < #AHT.matsDisplayResults then
                matsScrollOffset = matsScrollOffset + 1
                AHT:RefreshMatsUI()
            end
        end
    end)

    -- Alle an/aus
    local btnAllOn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnAllOn:SetSize(75, 20)
    btnAllOn:SetText(L["mats_btn_all_on"])
    btnAllOn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 8)
    btnAllOn:SetScript("OnClick", function()
        for n in pairs(AHT.materials) do AHT.matsSelected[n] = true end
        AHT:SaveDB(); AHT:CalculateMatsMargins(); AHT:RefreshMatsUI()
    end)

    local btnAllOff = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnAllOff:SetSize(75, 20)
    btnAllOff:SetText(L["mats_btn_all_off"])
    btnAllOff:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 94, 8)
    btnAllOff:SetScript("OnClick", function()
        for n in pairs(AHT.materials) do AHT.matsSelected[n] = false end
        AHT:SaveDB(); AHT:CalculateMatsMargins(); AHT:RefreshMatsUI()
    end)

    AHT.matsMainFrame = f
end

-- ── Mats-Verwaltungs-Dialog ───────────────────────────────────
function AHT:ShowMatsManageDialog()
    if not AHT.matsManageDlg then
        AHT:CreateMatsManageDialog()
    end
    AHT:RefreshMatsManageList()
    AHT.matsManageDlg:Show()
end

function AHT:CreateMatsManageDialog()
    if AHT.matsManageDlg then return end

    local L = AHT.L
    local dlg = CreateFrame("Frame", "ProjEP_AHT_MatsManageDlg", UIParent)
    dlg:SetSize(440, 520)
    dlg:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    dlg:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    dlg:SetBackdropColor(0.07, 0.07, 0.07, 1)
    dlg:EnableMouse(true)
    dlg:SetMovable(true)
    dlg:RegisterForDrag("LeftButton")
    dlg:SetScript("OnDragStart", function(self) self:StartMoving() end)
    dlg:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    dlg:SetFrameStrata("DIALOG")
    dlg:Hide()

    local innerBg = dlg:CreateTexture(nil, "BACKGROUND")
    innerBg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    innerBg:SetPoint("TOPLEFT", dlg, "TOPLEFT", 11, -12)
    innerBg:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -12, 11)
    innerBg:SetVertexColor(0.04, 0.04, 0.04, 1)

    local titleTex = dlg:CreateTexture(nil, "ARTWORK")
    titleTex:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    titleTex:SetSize(256, 64)
    titleTex:SetPoint("TOP", dlg, "TOP", 0, 12)

    local titleText = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOP", dlg, "TOP", 0, -5)
    titleText:SetText(L["mats_mgmt_title"])

    local closeBtn = CreateFrame("Button", nil, dlg, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", dlg, "TOPRIGHT", -5, -5)
    closeBtn:SetScript("OnClick", function(self) self:GetParent():Hide() end)

    -- Eingabe Neues Material
    local addLabel = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addLabel:SetPoint("TOPLEFT", dlg, "TOPLEFT", 15, -40)
    addLabel:SetText(L["mats_mgmt_add"])

    local inputBox = CreateFrame("EditBox", "ProjEP_AHT_MatsInputBox", dlg, "InputBoxTemplate")
    inputBox:SetSize(240, 20)
    inputBox:SetPoint("TOPLEFT", dlg, "TOPLEFT", 15, -58)
    inputBox:SetAutoFocus(false)
    inputBox:SetMaxLetters(50)
    inputBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    inputBox:SetScript("OnEnterPressed", function(self)
        local name = (self:GetText() or ""):match("^%s*(.-)%s*$")
        if name and name ~= "" then
            AHT:AddMaterial(name)
            self:SetText("")
            AHT:RefreshMatsManageList()
            AHT:CalculateMatsMargins()
            AHT:RefreshMatsUI()
        end
    end)
    dlg.inputBox = inputBox

    local btnAdd = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
    btnAdd:SetSize(80, 22)
    btnAdd:SetText(L["mats_mgmt_add"])
    btnAdd:SetPoint("TOPLEFT", dlg, "TOPLEFT", 263, -54)
    btnAdd:SetScript("OnClick", function()
        local name = (inputBox:GetText() or ""):match("^%s*(.-)%s*$")
        if name and name ~= "" then
            AHT:AddMaterial(name)
            inputBox:SetText("")
            AHT:RefreshMatsManageList()
            AHT:CalculateMatsMargins()
            AHT:RefreshMatsUI()
        end
    end)

    -- Liste
    local listLabel = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    listLabel:SetPoint("TOPLEFT", dlg, "TOPLEFT", 15, -88)
    listLabel:SetText("|cffffff00" .. L["mats_mgmt_title"] .. ":|r")

    local listPanel = CreateFrame("Frame", nil, dlg)
    listPanel:SetPoint("TOPLEFT",     dlg, "TOPLEFT",  12, -104)
    listPanel:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -28, 52)
    listPanel:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    listPanel:SetBackdropColor(0.10, 0.10, 0.10, 0.95)

    local scrollFrame = CreateFrame("ScrollFrame", "ProjEP_AHT_MatsManageScroll", listPanel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     listPanel, "TOPLEFT",  6,  -6)
    scrollFrame:SetPoint("BOTTOMRIGHT", listPanel, "BOTTOMRIGHT", -24, 6)

    local listBox = CreateFrame("Frame", nil, scrollFrame)
    listBox:SetWidth(368)
    listBox:SetHeight(1)
    scrollFrame:SetScrollChild(listBox)

    dlg.listBox = listBox
    dlg.removeMarked = {}

    local btnRemove = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
    btnRemove:SetSize(150, 22)
    btnRemove:SetText(L["mats_mgmt_remove"])
    btnRemove:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -14, 14)
    btnRemove:SetScript("OnClick", function()
        local removed = 0
        for name, marked in pairs(dlg.removeMarked) do
            if marked then
                AHT:RemoveMaterial(name)
                removed = removed + 1
            end
        end
        if removed == 0 and dlg.selectedMat and AHT.materials[dlg.selectedMat] then
            AHT:RemoveMaterial(dlg.selectedMat)
        end
        dlg.removeMarked = {}
        dlg.selectedMat  = nil
        AHT:RefreshMatsManageList()
        AHT:CalculateMatsMargins()
        AHT:RefreshMatsUI()
    end)

    local btnClose = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
    btnClose:SetSize(120, 22)
    btnClose:SetText(L["mats_mgmt_close"])
    btnClose:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", 14, 14)
    btnClose:SetScript("OnClick", function(self) self:GetParent():Hide() end)

    AHT.matsManageDlg = dlg
end

function AHT:RefreshMatsManageList()
    local dlg = AHT.matsManageDlg
    if not dlg or not dlg.listBox then return end

    -- Existierende Buttons entfernen
    local children = { dlg.listBox:GetChildren() }
    for _, child in ipairs(children) do child:Hide() end

    local list      = AHT:GetMaterialsList()
    local rowHeight = 0

    for i, matName in ipairs(list) do
        local btn = CreateFrame("Button", nil, dlg.listBox)
        btn:SetSize(368, 22)
        btn:SetPoint("TOPLEFT", dlg.listBox, "TOPLEFT", 2, -(i - 1) * 22)
        btn:SetBackdropColor(0.2, 0.2, 0.2, 0.3)

        -- Checkbox
        local cb = CreateFrame("CheckButton", nil, btn, "UICheckButtonTemplate")
        cb:SetSize(18, 18)
        cb:SetPoint("LEFT", btn, "LEFT", 2, 0)
        cb:SetChecked(dlg.removeMarked[matName] and true or false)
        cb:SetScript("OnClick", function(self)
            dlg.removeMarked[matName] = self:GetChecked() and true or nil
        end)

        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", btn, "LEFT", 24, 0)
        fs:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
        fs:SetJustifyH("LEFT")
        fs:SetText(matName)

        btn:SetScript("OnClick", function()
            dlg.selectedMat = matName
        end)

        btn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.3, 0.3, 0.6, 0.5)
        end)
        btn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.2, 0.2, 0.2, 0.3)
        end)

        rowHeight = rowHeight + 22
    end

    dlg.listBox:SetHeight(math.max(22, rowHeight))
end

-- ── Mats-Kaufdialog ───────────────────────────────────────────
function AHT:ShowMatsBuyDialog(matData)
    if not AHT.matsBuyDlg then
        AHT:CreateMatsBuyDialog()
    end

    local dlg = AHT.matsBuyDlg
    dlg._matData = matData
    AHT.matsBuyDialog = dlg

    local L = AHT.L

    -- Felder befüllen
    if dlg.nameLabel then
        dlg.nameLabel:SetText("|cffffd700" .. matData.name .. "|r")
    end
    if dlg.priceLabel then
        dlg.priceLabel:SetText(string.format(L["mats_buy_current"],
            AHT:FormatMoney(matData.currentPrice)))
    end
    if dlg.avgLabel then
        dlg.avgLabel:SetText(string.format(L["mats_buy_weighted_avg"],
            AHT:FormatMoney(matData.weighted_avg)))
    end
    if dlg.devLabel and matData.deviation then
        dlg.devLabel:SetText(string.format(L["mats_buy_deviation"], matData.deviation))
    end

    -- Standard-Menge: 20
    if dlg.amountBox then dlg.amountBox:SetText("20") end

    -- Max-Preis: aktueller Preis oder gewichteter Avg
    if dlg.maxPriceBox then
        local maxP = matData.currentPrice or matData.weighted_avg or 0
        dlg.maxPriceBox:SetText(AHT:FormatMoneyInput(maxP))
    end

    -- Daten-Aktualitätsprüfung
    local updated = AHT.priceUpdated[matData.name] or 0
    local stale   = (time() - updated) > 600  -- > 10 Minuten
    if dlg.staleLabel then
        if stale then
            dlg.staleLabel:SetText(L["mats_buy_stale"])
        else
            dlg.staleLabel:SetText("")
        end
    end

    dlg:Show()
end

function AHT:CreateMatsBuyDialog()
    if AHT.matsBuyDlg then return end

    local L = AHT.L
    local dlg = CreateFrame("Frame", "ProjEP_AHT_MatsBuyDlg", UIParent)
    dlg:SetSize(360, 280)
    dlg:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    dlg:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    dlg:SetBackdropColor(0.07, 0.07, 0.07, 1)
    dlg:EnableMouse(true)
    dlg:SetMovable(true)
    dlg:RegisterForDrag("LeftButton")
    dlg:SetScript("OnDragStart", function(self) self:StartMoving() end)
    dlg:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    dlg:SetFrameStrata("DIALOG")
    dlg:Hide()

    -- Titel
    local titleTex = dlg:CreateTexture(nil, "ARTWORK")
    titleTex:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    titleTex:SetSize(256, 64)
    titleTex:SetPoint("TOP", dlg, "TOP", 0, 12)

    local titleText = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOP", dlg, "TOP", 0, -5)
    titleText:SetText(L["mats_buy_title"])

    local closeBtn = CreateFrame("Button", nil, dlg, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", dlg, "TOPRIGHT", -5, -5)
    closeBtn:SetScript("OnClick", function(self) self:GetParent():Hide() end)

    -- Item-Name
    local nameLabel = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("TOPLEFT", dlg, "TOPLEFT", 15, -36)
    nameLabel:SetWidth(320)
    nameLabel:SetJustifyH("LEFT")
    dlg.nameLabel = nameLabel

    -- Preisinformationen
    local priceLabel = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    priceLabel:SetPoint("TOPLEFT", dlg, "TOPLEFT", 15, -58)
    priceLabel:SetWidth(320)
    dlg.priceLabel = priceLabel

    local avgLabel = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    avgLabel:SetPoint("TOPLEFT", dlg, "TOPLEFT", 15, -74)
    avgLabel:SetWidth(320)
    dlg.avgLabel = avgLabel

    local devLabel = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    devLabel:SetPoint("TOPLEFT", dlg, "TOPLEFT", 15, -90)
    devLabel:SetWidth(320)
    dlg.devLabel = devLabel

    local staleLabel = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    staleLabel:SetPoint("TOPLEFT", dlg, "TOPLEFT", 15, -106)
    staleLabel:SetWidth(320)
    dlg.staleLabel = staleLabel

    -- Menge
    local amountLabel = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    amountLabel:SetPoint("TOPLEFT", dlg, "TOPLEFT", 15, -128)
    amountLabel:SetText(L["mats_buy_amount"])

    local amountBox = CreateFrame("EditBox", "ProjEP_AHT_MatsBuyAmount", dlg, "InputBoxTemplate")
    amountBox:SetSize(80, 20)
    amountBox:SetPoint("TOPLEFT", dlg, "TOPLEFT", 130, -126)
    amountBox:SetAutoFocus(false)
    amountBox:SetNumeric(true)
    amountBox:SetMaxLetters(5)
    amountBox:SetText("20")
    amountBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    dlg.amountBox = amountBox

    -- Max-Preis
    local maxPriceLabel = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    maxPriceLabel:SetPoint("TOPLEFT", dlg, "TOPLEFT", 15, -152)
    maxPriceLabel:SetText(L["mats_buy_maxprice"])

    local maxPriceBox = CreateFrame("EditBox", "ProjEP_AHT_MatsBuyMaxPrice", dlg, "InputBoxTemplate")
    maxPriceBox:SetSize(130, 20)
    maxPriceBox:SetPoint("TOPLEFT", dlg, "TOPLEFT", 130, -150)
    maxPriceBox:SetAutoFocus(false)
    maxPriceBox:SetMaxLetters(20)
    maxPriceBox:SetText("")
    maxPriceBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    dlg.maxPriceBox = maxPriceBox

    -- Buttons
    local btnBuy = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
    btnBuy:SetSize(100, 22)
    btnBuy:SetText(L["mats_buy_btn"])
    btnBuy:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", 14, 14)
    btnBuy:SetScript("OnClick", function()
        local matData = dlg._matData
        if not matData then return end
        if not AuctionFrame or not AuctionFrame:IsVisible() then
            AHT:Print(L["scan_ah_required"]); return
        end
        local needed  = tonumber(amountBox:GetText()) or 0
        local maxPStr = maxPriceBox:GetText() or ""
        local maxPPU  = AHT:ParseMoney(maxPStr) or matData.currentPrice or 999999999
        if needed <= 0 then
            AHT:Print("Bitte gültige Menge eingeben."); return
        end
        dlg:Hide()
        AHT:StartMatsBuy(matData.name, needed, maxPPU)
    end)

    local btnRescan = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
    btnRescan:SetSize(110, 22)
    btnRescan:SetText(L["mats_buy_rescan_btn"])
    btnRescan:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", 120, 14)
    btnRescan:SetScript("OnClick", function()
        local matData = dlg._matData
        if not matData then return end
        -- Mini-Scan nur für dieses eine Item starten
        local queue = { matData.name }
        AHT.matsScanQueue         = queue
        AHT.matsScanQueueIdx      = 0
        AHT.matsScanMinPrices     = {}
        AHT.matsScanListingCounts = {}
        AHT.matsScanOffers        = {}
        AHT.matsScanState         = "waiting"
        AHT.matsScanTimer         = 0
        AHT.matsSentTimer         = 0
        AHT:AdvanceMatsScanQueue()
    end)

    local btnCancel = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
    btnCancel:SetSize(90, 22)
    btnCancel:SetText(L["mats_buy_cancel"])
    btnCancel:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -14, 14)
    btnCancel:SetScript("OnClick", function(self) self:GetParent():Hide() end)

    AHT.matsBuyDlg = dlg
end

-- Nach Scan: Kaufdialog-Preise aktualisieren
function AHT:RefreshMatsBuyDialogAfterScan()
    local dlg = AHT.matsBuyDialog
    if not dlg or not dlg:IsVisible() then return end
    local matData = dlg._matData
    if not matData then return end

    -- Daten aktualisieren
    local newPrice = AHT.prices[matData.name]
    if newPrice then
        matData.currentPrice = newPrice
        local L = AHT.L
        if dlg.priceLabel then
            dlg.priceLabel:SetText(string.format(L["mats_buy_current"], AHT:FormatMoney(newPrice)))
        end
        if dlg.staleLabel then
            dlg.staleLabel:SetText("")
        end
        if dlg.maxPriceBox then
            dlg.maxPriceBox:SetText(AHT:FormatMoneyInput(newPrice))
        end
    end
end

-- (OnAHClosed, OnTradeSkillShow, and RefreshAllUIs defined in Core.lua / UI.lua)

if AHT and AHT._loadStatus then
    AHT._loadStatus.mats = true
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[AHT-DIAG]|r Mats.lua OK")
    end
end
