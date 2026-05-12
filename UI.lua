-- ============================================================
-- ProjEP AH Trader - UI.lua
-- Hauptfenster mit Tab-Navigation:
--   1. Alchemie       – Trank/Elixier-Margenanalyse
--   2. Schmiedekunst  – Waffen/Rüstungs-Analyse
--   3. Schneiderei    – Stoff-Analyse
--   4. Lederverarb.   – Leder-Analyse
--   5. Ingenieurskunst– Technik-Analyse
--   6. Materialien    – Rohstoff-Preis-Abweichung
-- WotLK 3.3.5 / Lua 5.1 (Project Epoch)
-- ============================================================

local AHT = PROJEP_AHT

-- ── Layout-Konstanten ────────────────────────────────────────
local FRAME_W  = 800
local FRAME_H  = 530
local ROW_H    = 20
local MAX_ROWS = 14

local HEADER_Y    = -75
local FIRST_ROW_Y = -96

local scrollOffset = 0

-- ── Spaltendefinitionen (Alchemie-Tab) ───────────────────────
local ALCHEMY_COLS = {
    { id="sel",    label="",  w=18,  x=12,  sortable=false },
    { id="rank",   label="#", w=20,  x=32,  sortable=false },
    { id="name",   label="",  w=175, x=55,  sortable=false },
    { id="cost",   label="",  w=90,  x=233, sortable=false },
    { id="sell",   label="",  w=90,  x=326, sortable=false },
    { id="fee",    label="",  w=75,  x=419, sortable=false },
    { id="profit", label="",  w=90,  x=497, sortable=true  },
    { id="margin", label="",  w=55,  x=590, sortable=true  },
    { id="upd",    label="",  w=90,  x=650, sortable=false },
}

-- ── Hauptframe ───────────────────────────────────────────────
local mainFrame = CreateFrame("Frame", "ProjEP_AHT_UI", UIParent)
mainFrame:SetSize(FRAME_W, FRAME_H)
mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
mainFrame:SetBackdrop({
    bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
mainFrame:SetBackdropColor(0.07, 0.07, 0.07, 1)
mainFrame:EnableMouse(true)
mainFrame:SetMovable(true)
mainFrame:RegisterForDrag("LeftButton")
mainFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
mainFrame:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
mainFrame:SetFrameStrata("DIALOG")
mainFrame:Hide()
ProjEP_AHT_MainFrame = mainFrame

mainFrame:EnableMouseWheel(true)
mainFrame:SetScript("OnMouseWheel", function(self, delta)
    if AHT.activeTab == "alchemy" then
        if delta > 0 then
            if scrollOffset > 0 then scrollOffset = scrollOffset - 1; AHT:RefreshUI() end
        else
            if scrollOffset + MAX_ROWS < #(AHT.displayResults or {}) then
                scrollOffset = scrollOffset + 1; AHT:RefreshUI()
            end
        end
    end
end)

-- ── Titelleiste ───────────────────────────────────────────────
local titleTex = mainFrame:CreateTexture(nil, "ARTWORK")
titleTex:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
titleTex:SetSize(320, 64)
titleTex:SetPoint("TOP", mainFrame, "TOP", 0, 12)

local titleText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
titleText:SetPoint("TOP", mainFrame, "TOP", 0, -5)
titleText:SetText("ProjEP AH Trader")

local closeBtn = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -5, -5)
closeBtn:SetScript("OnClick", function(self) self:GetParent():Hide() end)

-- ── Tab-Buttons ───────────────────────────────────────────────
local tabDefs = {
    { id="alchemy",       labelKey="tab_alchemy"       },
    { id="blacksmithing", labelKey="tab_blacksmithing" },
    { id="tailoring",     labelKey="tab_tailoring"     },
    { id="leatherworking",labelKey="tab_leatherworking"},
    { id="engineering",   labelKey="tab_engineering"   },
    { id="mats",          labelKey="tab_mats"          },
}

local tabBtns   = {}
local tabPanels = {}

AHT.activeTab = AHT.activeTab or "alchemy"

local function ShowTab(tabId)
    AHT.activeTab = tabId
    scrollOffset  = 0
    for _, t in ipairs(tabDefs) do
        local btn = tabBtns[t.id]
        if btn then
            if t.id == tabId then
                btn:SetNormalFontObject("GameFontHighlight")
                btn:SetHighlightFontObject("GameFontHighlight")
            else
                btn:SetNormalFontObject("GameFontNormal")
                btn:SetHighlightFontObject("GameFontHighlightSmall")
            end
        end
        if tabPanels[t.id] then
            if t.id == tabId then tabPanels[t.id]:Show()
            else tabPanels[t.id]:Hide() end
        end
    end

    if tabId == "alchemy" then
        AHT:ApplyFilterAndSort()
        AHT:RefreshUI()
    elseif tabId == "blacksmithing" then
        AHT:CalculateBlacksmithingMargins()
        AHT:RefreshBlacksmithingTab()
    elseif tabId == "tailoring" then
        AHT:CalculateTailoringMargins()
        AHT:RefreshTailoringTab()
    elseif tabId == "leatherworking" then
        AHT:CalculateLeatherworkingMargins()
        AHT:RefreshLeatherworkingTab()
    elseif tabId == "engineering" then
        AHT:CalculateEngineeringMargins()
        AHT:RefreshEngineeringTab()
    elseif tabId == "mats" then
        AHT:CalculateMatsMargins()
        AHT:RefreshMatsTab()
    end
end

local tabBtnsCreated = false
local function EnsureTabsCreated()
    if tabBtnsCreated then return end
    tabBtnsCreated = true
    local L    = AHT.L
    local tabW = 120
    local tabX = 12
    for _, t in ipairs(tabDefs) do
        local btn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
        btn:SetSize(tabW, 22)
        btn:SetText(L[t.labelKey] or t.labelKey)
        btn:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", tabX, -30)
        tabX = tabX + tabW + 4
        local tabId = t.id
        btn:SetScript("OnClick", function() ShowTab(tabId) end)
        tabBtns[t.id] = btn

        local panel = CreateFrame("Frame", nil, mainFrame)
        panel:SetPoint("TOPLEFT",     mainFrame, "TOPLEFT",  10, -55)
        panel:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -10, 10)
        panel:Hide()
        tabPanels[t.id] = panel
    end
end

-- ── Status & Empfehlungszeile (Alchemy) ──────────────────────
local statusText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
statusText:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 15, -56)
statusText:SetWidth(FRAME_W - 200)
statusText:SetJustifyH("LEFT")
AHT.statusText = statusText

local recText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
recText:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 15, -68)
recText:SetWidth(FRAME_W - 200)
recText:SetJustifyH("LEFT")
recText:SetText("")
AHT.recText = recText

-- ── Suchfeld ─────────────────────────────────────────────────
local searchBox = CreateFrame("EditBox", "ProjEP_AHT_SearchBox", mainFrame, "InputBoxTemplate")
searchBox:SetSize(150, 20)
searchBox:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -80, -56)
searchBox:SetAutoFocus(false)
searchBox:SetMaxLetters(30)
searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
searchBox:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)
searchBox:SetScript("OnTextChanged", function(self)
    AHT.searchFilter = self:GetText() or ""
    scrollOffset = 0
    if AHT.activeTab == "alchemy" then
        AHT:ApplyFilterAndSort()
        AHT:RefreshUI()
    end
end)
AHT.mainSearchBox = searchBox

-- ── Alchemy-Tab: Spalten-Header ───────────────────────────────
local alcHeaderBtns   = {}
local alcHeaderLabels = {}

local function BuildAlchemyHeader()
    local L = AHT.L
    local colLabelMap = {
        name   = "ui_col_recipe",
        cost   = "ui_col_cost",
        sell   = "ui_col_sell",
        fee    = "ui_col_ahfee",
        profit = "ui_col_profit",
        margin = "ui_col_margin",
        upd    = "ui_col_updated",
    }
    for _, col in ipairs(ALCHEMY_COLS) do
        local key = colLabelMap[col.id]
        local lbl = key and L[key] or col.label
        if col.id == "sel" or col.id == "rank" then
            -- kein Header
        elseif col.sortable then
            local btn = CreateFrame("Button", nil, mainFrame)
            btn:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", col.x - 2, HEADER_Y + 2)
            btn:SetSize(col.w + 4, 16)
            local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetAllPoints(btn)
            fs:SetJustifyH("RIGHT")
            fs:SetText("|cffffff00" .. lbl .. "|r")
            btn._colId = col.id
            btn._fs    = fs
            btn:SetScript("OnClick", function(self)
                if AHT.sortMode == self._colId then
                    AHT.sortDir = AHT.sortDir == "desc" and "asc" or "desc"
                else
                    AHT.sortMode = self._colId
                    AHT.sortDir  = "desc"
                end
                scrollOffset = 0
                AHT:ApplyFilterAndSort()
                AHT:RefreshUI()
            end)
            alcHeaderBtns[col.id] = btn
        else
            local fs = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", col.x, HEADER_Y)
            fs:SetWidth(col.w)
            fs:SetJustifyH(col.id == "name" and "LEFT" or "RIGHT")
            fs:SetText("|cffffff00" .. lbl .. "|r")
            alcHeaderLabels[col.id] = fs
        end
    end
    local sep = mainFrame:CreateTexture(nil, "ARTWORK")
    sep:SetTexture(0.6, 0.6, 0.6, 0.4)
    sep:SetPoint("TOPLEFT",  mainFrame, "TOPLEFT",  14,  HEADER_Y - 14)
    sep:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -14, HEADER_Y - 14)
    sep:SetHeight(1)
end

-- ── Alchemy-Tab: Datenzeilen ─────────────────────────────────
local rowFrames = {}

local function BuildAlchemyRows()
    for i = 1, MAX_ROWS do
        local yOffset = FIRST_ROW_Y - (i - 1) * ROW_H
        local row = CreateFrame("Button", nil, mainFrame)
        row:SetPoint("TOPLEFT",  mainFrame, "TOPLEFT",  10, yOffset)
        row:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -10, yOffset)
        row:SetHeight(ROW_H)
        row:RegisterForClicks("RightButtonUp", "LeftButtonUp")

        if i % 2 == 0 then
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetTexture(1, 1, 1, 0.04)
            bg:SetAllPoints(row)
        end

        local cells = {}
        for _, col in ipairs(ALCHEMY_COLS) do
            if col.id == "sel" then
                local cb = CreateFrame("CheckButton", "ProjEP_AHT_CB" .. i, row, "UICheckButtonTemplate")
                cb:SetSize(18, 18)
                cb:SetPoint("LEFT", row, "LEFT", col.x - 10, 0)
                cb._rowIdx = i
                cb:SetScript("OnClick", function(self)
                    local idx = self._rowIdx + scrollOffset
                    if idx <= #(AHT.displayResults or {}) then
                        local rName = AHT.displayResults[idx].name
                        AHT.selected[rName] = self:GetChecked() and true or false
                        AHT:SaveDB()
                        AHT:RefreshUI()
                    end
                end)
                cells[col.id] = cb
            else
                local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                fs:SetPoint("LEFT", row, "LEFT", col.x, 0)
                fs:SetWidth(col.w)
                fs:SetJustifyH(col.id == "name" and "LEFT" or "RIGHT")
                cells[col.id] = fs
            end
        end

        row.cells = cells
        row:EnableMouse(true)

        row:SetScript("OnEnter", function(self)
            local data = self._data
            if not data then return end
            local L = AHT.L
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine("|cffffd700" .. data.name .. "|r")
            if data.reagents and #data.reagents > 0 then
                GameTooltip:AddLine(L["tt_ingredients"], 1, 1, 0)
                for _, reag in ipairs(data.reagents) do
                    local p = AHT.prices[reag.name] or 0
                    local vendor = AHT:IsVendorItem(reag.name)
                    local src    = vendor and L["tt_source_vendor"] or L["tt_source_ah"]
                    GameTooltip:AddDoubleLine(
                        string.format("  %dx %s (%s)", reag.count, reag.name, src),
                        AHT:FormatMoney(p * reag.count), 0.9, 0.9, 0.9, 1, 1, 0)
                end
            end
            if data.sellPrice then
                GameTooltip:AddDoubleLine(L["tt_sell_price"], AHT:FormatMoney(data.sellPrice), 1,1,1, 0,1,0)
            end
            if data.avgSellPrice then
                GameTooltip:AddDoubleLine(L["tt_avg_price"], AHT:FormatMoney(data.avgSellPrice), 1,1,1, 0.7,0.7,0.7)
            end
            if data.volume then
                GameTooltip:AddDoubleLine(L["tt_volume"], tostring(data.volume), 1,1,1, 0.8,0.8,0.8)
            end
            if data.provision then
                GameTooltip:AddDoubleLine(L["tt_ah_cut"], AHT:FormatMoney(data.provision), 1,1,1, 0.7,0.7,0.7)
            end
            if data.deposit then
                GameTooltip:AddDoubleLine(L["tt_deposit"], AHT:FormatMoney(data.deposit), 1,1,1, 0.7,0.7,0.7)
            end
            if data.profit then
                local cr = data.profit > 0 and 0 or 1
                local cg = data.profit > 0 and 1 or 0.3
                GameTooltip:AddDoubleLine(L["tt_profit"], AHT:FormatMoney(data.profit), 1,1,1, cr,cg,0)
            end
            if data.margin then
                GameTooltip:AddDoubleLine(L["tt_margin"], string.format("%.1f%%", data.margin), 1,1,1, 1,1,0)
            end
            if data.lastUpdated then
                local age = time() - data.lastUpdated
                GameTooltip:AddDoubleLine(L["tt_updated"],
                    string.format("%dm ago", math.floor(age / 60)), 1,1,1, 0.7,0.7,0.7)
            end
            if data.isDeal then
                GameTooltip:AddLine("|cff00ff00" .. L["tt_deal"] .. "|r")
            end
            if data.missingReag and #data.missingReag > 0 then
                GameTooltip:AddLine(L["tt_missing"] .. table.concat(data.missingReag, ", "), 1, 0.5, 0)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff888888" .. L["help_actions"] .. "|r")
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        row:SetScript("OnClick", function(self, btn)
            local data = self._data
            if not data then return end
            if btn == "RightButton" then
                if IsShiftKeyDown() then
                    AHT:ShowPostDialog(data.name, data)
                else
                    AHT:ShowBuyDialog(data)
                end
            end
        end)

        row:Hide()
        rowFrames[i] = row
    end
end

-- ── Buttons unten ────────────────────────────────────────────
local btnAllOn, btnAllOff

local function BuildBottomButtons()
    local L = AHT.L
    btnAllOn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    btnAllOn:SetSize(80, 22)
    btnAllOn:SetText(L["ui_all_on"])
    btnAllOn:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 14, 8)
    btnAllOn:SetScript("OnClick", function()
        for _, recipe in ipairs(AHT.recipes) do
            AHT.selected[recipe.name] = true
        end
        AHT:SaveDB(); AHT:CalculateMargins(); AHT:RefreshUI()
    end)

    btnAllOff = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    btnAllOff:SetSize(80, 22)
    btnAllOff:SetText(L["ui_all_off"])
    btnAllOff:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 98, 8)
    btnAllOff:SetScript("OnClick", function()
        for _, recipe in ipairs(AHT.recipes) do
            AHT.selected[recipe.name] = false
        end
        AHT:SaveDB(); AHT:CalculateMargins(); AHT:RefreshUI()
    end)

    local btnScan = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    btnScan:SetSize(120, 22)
    btnScan:SetText(L["scan_button"])
    btnScan:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 182, 8)
    btnScan:SetScript("OnClick", function(self)
        if AHT:IsScanning() then
            AHT:CancelScan()
            self:SetText(L["scan_button"])
        else
            AHT:StartScan()
            if AHT:IsScanning() then self:SetText(L["scan_cancel"]) end
        end
    end)
    btnScan:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if AHT:IsScanning() then
            GameTooltip:AddLine(L["scan_tooltip_cancel"], 1, 0.5, 0.5)
        else
            local n = 0
            for _, r in ipairs(AHT.recipes) do
                if AHT.selected[r.name] ~= false then n = n + 1 end
            end
            GameTooltip:AddLine(string.format(L["scan_tooltip_ready"], n), 1, 1, 1)
            GameTooltip:AddLine(L["scan_ah_required"], 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    btnScan:SetScript("OnLeave", function() GameTooltip:Hide() end)
    AHT.uiScanButton = btnScan
end

-- ── ShowUI / RefreshUI ────────────────────────────────────────
function AHT:ShowUI()
    AHT:Print("|cff00ff00ShowUI() aufgerufen|r")
    if not mainFrame then
        AHT:Print("|cffff4444mainFrame ist nil!|r"); return
    end

    if not tabBtnsCreated then
        AHT:Print("Build-Schritte starten...")
        local ok, err
        ok, err = pcall(EnsureTabsCreated)
        if not ok then AHT:Print("|cffff4444EnsureTabs:|r " .. tostring(err))
        else AHT:Print("  EnsureTabs OK") end
        ok, err = pcall(BuildAlchemyHeader)
        if not ok then AHT:Print("|cffff4444AlcHeader:|r " .. tostring(err))
        else AHT:Print("  AlcHeader OK") end
        ok, err = pcall(BuildAlchemyRows)
        if not ok then AHT:Print("|cffff4444AlcRows:|r " .. tostring(err))
        else AHT:Print("  AlcRows OK") end
        ok, err = pcall(BuildBottomButtons)
        if not ok then AHT:Print("|cffff4444BottomBtns:|r " .. tostring(err))
        else AHT:Print("  BottomBtns OK") end
    end

    local ok, err = pcall(function() mainFrame:Show() end)
    if not ok then
        AHT:Print("|cffff4444mainFrame:Show() Fehler:|r " .. tostring(err))
    else
        AHT:Print(string.format("mainFrame visible=%s, point=%s",
            tostring(mainFrame:IsVisible()), tostring(mainFrame:GetPoint(1))))
    end

    ok, err = pcall(ShowTab, AHT.activeTab or "alchemy")
    if not ok then AHT:Print("|cffff4444ShowTab:|r " .. tostring(err)) end
end

function AHT:RefreshUI()
    if not mainFrame:IsVisible() then return end
    if AHT.activeTab ~= "alchemy" then return end

    local L       = AHT.L
    local results = AHT.displayResults or {}

    if AHT.statusText then
        if #results > 0 then
            AHT.statusText:SetText(string.format(L["ui_status_ready"], #results))
        else
            AHT.statusText:SetText(L["ui_status_no_data"])
        end
    end

    if AHT.recText then
        local best = results[1]
        if best and best.profit and best.profit > 0 then
            AHT.recText:SetText(string.format(L["ui_best_recipe"],
                best.name, AHT:FormatMoney(best.profit), best.margin or 0))
        else
            AHT.recText:SetText(L["ui_no_recommendation"])
        end
    end

    for i = 1, MAX_ROWS do
        local idx = i + scrollOffset
        local row = rowFrames[i]
        if not row then break end

        if idx <= #results then
            local r = results[idx]
            row._data = r
            local cells = row.cells

            if cells.sel then
                cells.sel:SetChecked(AHT.selected[r.name] ~= false)
            end
            if cells.rank then
                cells.rank:SetText(tostring(idx))
            end
            if cells.name then
                local tag = AHT.selected[r.name] == false and "|cff888888" or ""
                local isDeal = r.isDeal and "|cff00ff00★ |r" or ""
                cells.name:SetText(isDeal .. tag .. r.name .. (tag ~= "" and "|r" or ""))
            end
            if cells.cost then
                cells.cost:SetText(r.ingredCost and r.ingredCost > 0
                    and AHT:FormatMoneyPlain(r.ingredCost) or "|cff888888–|r")
            end
            if cells.sell then
                cells.sell:SetText(r.sellPrice
                    and AHT:FormatMoneyPlain(r.sellPrice) or L["ui_not_on_ah"])
            end
            if cells.fee then
                local fee = (r.provision or 0) + (r.deposit or 0)
                cells.fee:SetText(fee > 0 and AHT:FormatMoneyPlain(fee) or "|cff888888–|r")
            end
            if cells.profit then
                if r.profit then
                    local col = r.profit > 0 and "ff00ff00" or "ffff4444"
                    cells.profit:SetText(string.format("|c%s%s|r", col,
                        AHT:FormatMoneyPlain(math.abs(r.profit))))
                else
                    cells.profit:SetText(L["ui_missing_data"])
                end
            end
            if cells.margin then
                if r.margin then
                    local col = r.margin > 0 and "ff00ff00" or "ffff4444"
                    cells.margin:SetText(string.format("|c%s%.0f%%|r", col, r.margin))
                else
                    cells.margin:SetText("|cff888888–|r")
                end
            end
            if cells.upd then
                local p = AHT.priceUpdated and AHT.priceUpdated[r.name]
                if p then
                    local age = time() - p
                    if age < 3600 then
                        cells.upd:SetText(string.format("%dm", math.floor(age / 60)))
                    else
                        cells.upd:SetText(string.format("%.1fh", age / 3600))
                    end
                else
                    cells.upd:SetText("|cff888888–|r")
                end
            end
            row:Show()
        else
            row._data = nil
            row:Hide()
        end
    end
end

-- ── Sortier-Defaults (Alchemie) ──────────────────────────────
AHT.sortMode     = AHT.sortMode     or "profit"
AHT.sortDir      = AHT.sortDir      or "desc"
AHT.searchFilter = AHT.searchFilter or ""

-- ══════════════════════════════════════════════════════════════
-- CRAFT-TAB HELPER – Gemeinsamer Aufbau für alle 4 Handwerks-Tabs
-- ══════════════════════════════════════════════════════════════

local CRAFT_COL_DEFS = {
    { id="name",   x=4,   w=230, align="LEFT"  },
    { id="cost",   x=237, w=100, align="RIGHT" },
    { id="sell",   x=340, w=100, align="RIGHT" },
    { id="profit", x=443, w=100, align="RIGHT" },
    { id="margin", x=546, w=80,  align="RIGHT" },
}

local CRAFT_ROW_H    = 20
local CRAFT_MAX_ROWS = 12

local function BuildCraftTab(panel)
    local L = AHT.L
    local hdrDefs = {
        { label=L["ui_col_recipe"],  x=4,   w=230, align="LEFT"  },
        { label=L["ui_col_cost"],    x=237, w=100, align="RIGHT" },
        { label=L["ui_col_sell"],    x=340, w=100, align="RIGHT" },
        { label=L["ui_col_profit"],  x=443, w=100, align="RIGHT" },
        { label=L["ui_col_margin"],  x=546, w=80,  align="RIGHT" },
    }
    for _, h in ipairs(hdrDefs) do
        local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", panel, "TOPLEFT", h.x, -5)
        fs:SetWidth(h.w)
        fs:SetJustifyH(h.align)
        fs:SetText("|cffffff00" .. h.label .. "|r")
    end

    local sep = panel:CreateTexture(nil, "ARTWORK")
    sep:SetTexture(0.6, 0.6, 0.6, 0.4)
    sep:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, -22)
    sep:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -22)
    sep:SetHeight(1)

    local rows = {}
    for i = 1, CRAFT_MAX_ROWS do
        local yOff = -26 - (i - 1) * CRAFT_ROW_H
        local row  = CreateFrame("Frame", nil, panel)
        row:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, yOff)
        row:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, yOff)
        row:SetHeight(CRAFT_ROW_H)
        if i % 2 == 0 then
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetTexture(1, 1, 1, 0.04)
            bg:SetAllPoints(row)
        end
        local c = {}
        for _, cd in ipairs(CRAFT_COL_DEFS) do
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", row, "LEFT", cd.x, 0)
            fs:SetWidth(cd.w)
            fs:SetJustifyH(cd.align)
            c[cd.id] = fs
        end
        row.cells = c
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            local d = self._data
            if not d then return end
            local L = AHT.L
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine("|cffffd700" .. d.name .. "|r")
            if d.reagents then
                GameTooltip:AddLine(L["tt_ingredients"], 1, 1, 0)
                for _, reag in ipairs(d.reagents) do
                    local p = AHT.prices[reag.name] or 0
                    local isVend = AHT:IsVendorItem(reag.name)
                    local src = isVend and L["tt_source_vendor"] or L["tt_source_ah"]
                    GameTooltip:AddDoubleLine(
                        string.format("  %dx %s (%s)", reag.count, reag.name, src),
                        AHT:FormatMoney(p * reag.count), 0.9,0.9,0.9, 1,1,0)
                end
            end
            if d.sellPrice then
                GameTooltip:AddDoubleLine(L["tt_sell_price"], AHT:FormatMoney(d.sellPrice), 1,1,1, 0,1,0)
            end
            if d.profit then
                local cr = d.profit > 0 and 0 or 1
                local cg = d.profit > 0 and 1 or 0.3
                GameTooltip:AddDoubleLine(L["tt_profit"], AHT:FormatMoney(d.profit), 1,1,1, cr,cg,0)
            end
            if d.margin then
                GameTooltip:AddDoubleLine(L["tt_margin"],
                    string.format("%.1f%%", d.margin), 1,1,1, 1,1,0)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:Hide()
        rows[i] = row
    end
    return rows
end

local function FillCraftRows(rows, display)
    local L = AHT.L
    for i = 1, CRAFT_MAX_ROWS do
        local row = rows[i]
        if not row then break end
        local d = display[i]
        if d then
            row._data = d
            local c   = row.cells
            if c.name   then c.name:SetText(d.name) end
            if c.cost   then c.cost:SetText(d.ingredCost and d.ingredCost > 0
                and AHT:FormatMoneyPlain(d.ingredCost) or "|cff888888–|r") end
            if c.sell   then c.sell:SetText(d.sellPrice
                and AHT:FormatMoneyPlain(d.sellPrice) or L["ui_not_on_ah"]) end
            if c.profit then
                if d.profit then
                    local col = d.profit > 0 and "ff00ff00" or "ffff4444"
                    c.profit:SetText(string.format("|c%s%s|r", col,
                        AHT:FormatMoneyPlain(math.abs(d.profit))))
                else c.profit:SetText("|cff888888–|r") end
            end
            if c.margin then
                if d.margin then
                    local col = d.margin > 0 and "ff00ff00" or "ffff4444"
                    c.margin:SetText(string.format("|c%s%.0f%%|r", col, d.margin))
                else c.margin:SetText("|cff888888–|r") end
            end
            row:Show()
        else
            row._data = nil; row:Hide()
        end
    end
end

local function AddScanButton(panel, noRecKey, startFn)
    local L = AHT.L
    local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btn:SetSize(130, 22)
    btn:SetText(L["scan_button"])
    btn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 4)
    btn:SetScript("OnClick", function(self)
        if AHT:IsScanning() then
            AHT:CancelScan()
            self:SetText(L["scan_button"])
        else
            startFn()
            if AHT:IsScanning() then self:SetText(L["scan_cancel"]) end
        end
    end)

    local noRecLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    noRecLbl:SetPoint("CENTER", panel, "CENTER", 0, 0)
    noRecLbl:SetText(L[noRecKey] or noRecKey)
    noRecLbl:SetTextColor(1, 0.5, 0)
    panel._noRecLbl = noRecLbl
    return btn
end

-- ══════════════════════════════════════════════════════════════
-- SCHMIEDEKUNST-TAB
-- ══════════════════════════════════════════════════════════════
local bsCreated  = false
local bsRowFrames = {}

function AHT:RefreshBlacksmithingTab()
    if not mainFrame:IsVisible() then return end
    local panel = tabPanels["blacksmithing"]
    if not panel or not panel:IsVisible() then return end

    if not bsCreated then
        bsCreated  = true
        bsRowFrames = BuildCraftTab(panel)
        AddScanButton(panel, "bs_no_recipes", function() AHT:StartBlacksmithingScan() end)
    end

    if panel._noRecLbl then
        panel._noRecLbl:SetShown(#AHT.bsRecipes == 0)
    end
    FillCraftRows(bsRowFrames, AHT.bsDisplayResults or {})
end

-- ══════════════════════════════════════════════════════════════
-- SCHNEIDEREI-TAB
-- ══════════════════════════════════════════════════════════════
local tailCreated   = false
local tailRowFrames = {}

function AHT:RefreshTailoringTab()
    if not mainFrame:IsVisible() then return end
    local panel = tabPanels["tailoring"]
    if not panel or not panel:IsVisible() then return end

    if not tailCreated then
        tailCreated   = true
        tailRowFrames = BuildCraftTab(panel)
        AddScanButton(panel, "tail_no_recipes", function() AHT:StartTailoringScan() end)
    end

    if panel._noRecLbl then
        panel._noRecLbl:SetShown(#AHT.tailRecipes == 0)
    end
    FillCraftRows(tailRowFrames, AHT.tailDisplayResults or {})
end

-- ══════════════════════════════════════════════════════════════
-- LEDERVERARBEITUNGS-TAB
-- ══════════════════════════════════════════════════════════════
local lwCreated   = false
local lwRowFrames = {}

function AHT:RefreshLeatherworkingTab()
    if not mainFrame:IsVisible() then return end
    local panel = tabPanels["leatherworking"]
    if not panel or not panel:IsVisible() then return end

    if not lwCreated then
        lwCreated   = true
        lwRowFrames = BuildCraftTab(panel)
        AddScanButton(panel, "lw_no_recipes", function() AHT:StartLeatherworkingScan() end)
    end

    if panel._noRecLbl then
        panel._noRecLbl:SetShown(#AHT.lwRecipes == 0)
    end
    FillCraftRows(lwRowFrames, AHT.lwDisplayResults or {})
end

-- ══════════════════════════════════════════════════════════════
-- INGENIEURSKUNST-TAB
-- ══════════════════════════════════════════════════════════════
local engCreated   = false
local engRowFrames = {}

function AHT:RefreshEngineeringTab()
    if not mainFrame:IsVisible() then return end
    local panel = tabPanels["engineering"]
    if not panel or not panel:IsVisible() then return end

    if not engCreated then
        engCreated   = true
        engRowFrames = BuildCraftTab(panel)
        AddScanButton(panel, "eng_no_recipes", function() AHT:StartEngineeringScan() end)
    end

    if panel._noRecLbl then
        panel._noRecLbl:SetShown(#AHT.engRecipes == 0)
    end
    FillCraftRows(engRowFrames, AHT.engDisplayResults or {})
end

-- ── Mats-Tab ─────────────────────────────────────────────────
local matsTabCreated    = false
local matsTabRowFrames  = {}
local matsTabScrollOff  = 0
local MATS_TAB_ROW_H    = 20
local MATS_TAB_MAX_ROWS = 12

function AHT:RefreshMatsTab()
    if not mainFrame:IsVisible() then return end
    local panel = tabPanels["mats"]
    if not panel or not panel:IsVisible() then return end

    local L = AHT.L

    if not matsTabCreated then
        matsTabCreated = true

        local hdr = {
            { label=L["mats_col_name"],      x=4,   w=160, align="LEFT"  },
            { label=L["mats_col_current"],   x=167, w=100, align="RIGHT" },
            { label=L["mats_col_avg"],       x=270, w=100, align="RIGHT" },
            { label=L["mats_col_deviation"], x=373, w=90,  align="RIGHT" },
            { label=L["mats_col_listings"],  x=466, w=70,  align="RIGHT" },
            { label=L["mats_col_scans"],     x=539, w=70,  align="RIGHT" },
        }
        for _, h in ipairs(hdr) do
            local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetPoint("TOPLEFT", panel, "TOPLEFT", h.x, -5)
            fs:SetWidth(h.w)
            fs:SetJustifyH(h.align)
            fs:SetText("|cffffff00" .. h.label .. "|r")
        end

        local sep = panel:CreateTexture(nil, "ARTWORK")
        sep:SetTexture(0.6, 0.6, 0.6, 0.4)
        sep:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, -22)
        sep:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -22)
        sep:SetHeight(1)

        local btnMgr = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        btnMgr:SetSize(140, 22)
        btnMgr:SetText(L["mats_btn_manage"])
        btnMgr:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 4)
        btnMgr:SetScript("OnClick", function() AHT:ShowMatsManageDialog() end)

        local btnScan = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        btnScan:SetSize(120, 22)
        btnScan:SetText(L["mats_btn_scan"])
        btnScan:SetPoint("BOTTOMRIGHT", btnMgr, "BOTTOMLEFT", -6, 0)
        btnScan:SetScript("OnClick", function(self)
            if AHT:IsMatScanning() then
                AHT:CancelMatsScan()
                self:SetText(L["mats_btn_scan"])
            else
                AHT:StartMatsScan()
                if AHT:IsMatScanning() then self:SetText(L["scan_cancel"]) end
            end
        end)
        btnScan:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            if AHT:IsMatScanning() then
                GameTooltip:AddLine(L["mats_tooltip_cancel"], 1, 0.5, 0.5)
            else
                local n = 0
                for _ in pairs(AHT.materials or {}) do n = n + 1 end
                if n == 0 then
                    GameTooltip:AddLine(L["mats_tooltip_no_materials"])
                else
                    GameTooltip:AddLine(string.format(L["mats_tooltip_ready"], n), 1, 1, 1)
                end
            end
            GameTooltip:Show()
        end)
        btnScan:SetScript("OnLeave", function() GameTooltip:Hide() end)
        panel._matsScanBtn = btnScan

        for i = 1, MATS_TAB_MAX_ROWS do
            local yOff = -26 - (i - 1) * MATS_TAB_ROW_H
            local row  = CreateFrame("Button", nil, panel)
            row:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, yOff)
            row:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, yOff)
            row:SetHeight(MATS_TAB_ROW_H)
            row:RegisterForClicks("RightButtonUp")
            if i % 2 == 0 then
                local bg = row:CreateTexture(nil, "BACKGROUND")
                bg:SetTexture(1,1,1,0.04)
                bg:SetAllPoints(row)
            end
            local c = {}
            local colDefs = {
                { id="name", x=4,   w=160, align="LEFT"  },
                { id="cur",  x=167, w=100, align="RIGHT" },
                { id="avg",  x=270, w=100, align="RIGHT" },
                { id="dev",  x=373, w=90,  align="RIGHT" },
                { id="list", x=466, w=70,  align="RIGHT" },
                { id="hist", x=539, w=70,  align="RIGHT" },
            }
            for _, cd in ipairs(colDefs) do
                local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                fs:SetPoint("LEFT", row, "LEFT", cd.x, 0)
                fs:SetWidth(cd.w)
                fs:SetJustifyH(cd.align)
                c[cd.id] = fs
            end
            row.cells = c
            row:EnableMouse(true)
            row:SetScript("OnClick", function(self, btn)
                if btn == "RightButton" and self._data then
                    AHT:ShowMatsBuyDialog(self._data)
                end
            end)
            row:Hide()
            matsTabRowFrames[i] = row
        end
    end

    AHT:CalculateMatsMargins()
    local display = AHT.matsDisplayResults or {}

    for i = 1, MATS_TAB_MAX_ROWS do
        local idx = i + matsTabScrollOff
        local row = matsTabRowFrames[i]
        if not row then break end
        if idx <= #display then
            local r   = display[idx]
            row._data = r
            local c   = row.cells
            if c.name then c.name:SetText(r.name) end
            if c.cur  then c.cur:SetText(r.currentPrice
                and AHT:FormatMoneyPlain(r.currentPrice) or "|cff888888–|r") end
            if c.avg  then c.avg:SetText(r.weighted_avg
                and AHT:FormatMoneyPlain(r.weighted_avg) or "|cff888888–|r") end
            if c.dev  then
                if r.deviation then
                    local d   = r.deviation
                    local hex = d < -20 and "ff00ff00" or (d > 20 and "ffff4444" or "ffffff00")
                    c.dev:SetText(string.format("|c%s%+.1f%%|r", hex, d))
                else c.dev:SetText("|cff888888–|r") end
            end
            if c.list then c.list:SetText(tostring(r.listingCount)) end
            if c.hist then c.hist:SetText(tostring(r.historyLength)) end
            row:Show()
        else
            row._data = nil; row:Hide()
        end
    end
end

-- ── Kaufdialog ───────────────────────────────────────────────
local buyDlg = nil

function AHT:ShowBuyDialog(recipe)
    if not buyDlg then AHT:CreateBuyDialog() end
    buyDlg._recipe = recipe
    local L = AHT.L
    if buyDlg.titleFs then buyDlg.titleFs:SetText(recipe.name) end
    if buyDlg.amountBox then buyDlg.amountBox:SetText("1") end
    AHT:UpdateBuyDialogPlan(1)
    buyDlg:Show()
end

function AHT:UpdateBuyDialogPlan(count)
    if not buyDlg or not buyDlg._recipe then return end
    local L      = AHT.L
    local recipe = buyDlg._recipe
    local totalEst = 0
    local costOk   = true
    if recipe.ingredCost and recipe.ingredCost > 0 then
        totalEst = recipe.ingredCost * count
    else
        costOk = false
    end
    if buyDlg.estCostFs then
        if costOk then
            buyDlg.estCostFs:SetText(string.format(L["buy_est_cost"], AHT:FormatMoney(totalEst)))
        else
            buyDlg.estCostFs:SetText(L["ui_missing_data"])
        end
    end
    local vendorLines = {}
    if recipe.reagents then
        for _, reag in ipairs(recipe.reagents) do
            if AHT:IsVendorItem(reag.name) then
                local total = reag.count * count
                table.insert(vendorLines, string.format("%dx %s", total, reag.name))
            end
        end
    end
    if buyDlg.vendorFs and #vendorLines > 0 then
        buyDlg.vendorFs:SetText(string.format(L["buy_vendor_items"], table.concat(vendorLines, ", ")))
    elseif buyDlg.vendorFs then
        buyDlg.vendorFs:SetText("")
    end
    local playerCopper = GetMoney()
    if buyDlg.goldWarnFs then
        if costOk and totalEst > playerCopper then
            buyDlg.goldWarnFs:SetText(L["buy_not_enough_gold"])
        else
            buyDlg.goldWarnFs:SetText("")
        end
    end
end

function AHT:CreateBuyDialog()
    if buyDlg then return end
    local L = AHT.L
    local dlg = CreateFrame("Frame", "ProjEP_AHT_BuyDlg", UIParent)
    dlg:SetSize(360, 260)
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

    local titleTex = dlg:CreateTexture(nil, "ARTWORK")
    titleTex:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    titleTex:SetSize(256, 64)
    titleTex:SetPoint("TOP", dlg, "TOP", 0, 12)

    local titleHdr = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleHdr:SetPoint("TOP", dlg, "TOP", 0, -5)
    titleHdr:SetText(L["buy_title"])

    local closeBtn = CreateFrame("Button", nil, dlg, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", dlg, "TOPRIGHT", -5, -5)
    closeBtn:SetScript("OnClick", function(self) self:GetParent():Hide() end)

    local titleFs = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleFs:SetPoint("TOPLEFT", dlg, "TOPLEFT", 15, -36)
    titleFs:SetWidth(320)
    titleFs:SetJustifyH("LEFT")
    dlg.titleFs = titleFs

    local amtLbl = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    amtLbl:SetPoint("TOPLEFT", dlg, "TOPLEFT", 15, -60)
    amtLbl:SetText(L["buy_amount_label"])

    local amountBox = CreateFrame("EditBox", "ProjEP_AHT_BuyAmount", dlg, "InputBoxTemplate")
    amountBox:SetSize(80, 20)
    amountBox:SetPoint("TOPLEFT", dlg, "TOPLEFT", 140, -58)
    amountBox:SetAutoFocus(false)
    amountBox:SetNumeric(true)
    amountBox:SetMaxLetters(3)
    amountBox:SetText("1")
    amountBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    amountBox:SetScript("OnTextChanged", function(self)
        local cnt = tonumber(self:GetText()) or 1
        AHT:UpdateBuyDialogPlan(cnt)
    end)
    dlg.amountBox = amountBox

    local estCostFs = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    estCostFs:SetPoint("TOPLEFT", dlg, "TOPLEFT", 15, -84)
    estCostFs:SetWidth(320)
    dlg.estCostFs = estCostFs

    local vendorFs = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    vendorFs:SetPoint("TOPLEFT", dlg, "TOPLEFT", 15, -102)
    vendorFs:SetWidth(320)
    vendorFs:SetTextColor(0.8, 0.8, 0)
    dlg.vendorFs = vendorFs

    local goldWarnFs = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    goldWarnFs:SetPoint("TOPLEFT", dlg, "TOPLEFT", 15, -120)
    goldWarnFs:SetWidth(320)
    dlg.goldWarnFs = goldWarnFs

    local btnBuy = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
    btnBuy:SetSize(100, 22)
    btnBuy:SetText(L["buy_btn_buy"])
    btnBuy:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", 14, 14)
    btnBuy:SetScript("OnClick", function()
        local recipe = dlg._recipe
        if not recipe then return end
        if not AuctionFrame or not AuctionFrame:IsVisible() then
            AHT:Print(L["scan_ah_required"]); return
        end
        local count = tonumber(amountBox:GetText()) or 1
        if count <= 0 then return end
        dlg:Hide()
        AHT:StartBuy(recipe, count)
    end)

    local btnCancel = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
    btnCancel:SetSize(100, 22)
    btnCancel:SetText(L["buy_btn_cancel"])
    btnCancel:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -14, 14)
    btnCancel:SetScript("OnClick", function(self) self:GetParent():Hide() end)

    buyDlg = dlg
    AHT.buyDialog = dlg
end

-- ── Postier-Dialog ─────────────────────────────────────────────
local postDlg = nil

function AHT:ShowPostDialog(recipeName, recipe)
    if not postDlg then AHT:CreatePostDialog() end
    postDlg._recipeName = recipeName
    postDlg._recipe     = recipe
    local L = AHT.L
    if postDlg.titleFs then postDlg.titleFs:SetText(recipeName) end
    if postDlg.stackBox then postDlg.stackBox:SetText("1") end
    if postDlg.numBox   then postDlg.numBox:SetText("5")   end
    local suggestPrice = recipe.sellPrice
    if not suggestPrice and recipe.ingredCost and recipe.ingredCost > 0 then
        suggestPrice = math.floor(recipe.ingredCost * 1.2)
    end
    if postDlg.priceBox and suggestPrice then
        postDlg.priceBox:SetText(AHT:FormatMoneyInput(suggestPrice))
    end
    AHT:UpdatePostDialogPreview()
    postDlg:Show()
end

function AHT:UpdatePostDialogPreview()
    if not postDlg then return end
    local stack = tonumber(postDlg.stackBox and postDlg.stackBox:GetText()) or 1
    local num   = tonumber(postDlg.numBox   and postDlg.numBox:GetText())   or 1
    local total = stack * num
    local L     = AHT.L
    if postDlg.previewFs then
        postDlg.previewFs:SetText(string.format(L["post_result_preview"], num, total))
    end
    local name = postDlg._recipeName
    if name and postDlg.inBagsFs then
        local cnt = AHT:CountItemInBags(name) or 0
        postDlg.inBagsFs:SetText(string.format(L["post_in_bags"], cnt))
    end
end

function AHT:CreatePostDialog()
    if postDlg then return end
    local L = AHT.L
    local dlg = CreateFrame("Frame", "ProjEP_AHT_PostDlg", UIParent)
    dlg:SetSize(340, 280)
    dlg:SetPoint("CENTER", UIParent, "CENTER", 50, -50)
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

    local titleTex = dlg:CreateTexture(nil, "ARTWORK")
    titleTex:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    titleTex:SetSize(256, 64)
    titleTex:SetPoint("TOP", dlg, "TOP", 0, 12)

    local titleHdr = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleHdr:SetPoint("TOP", dlg, "TOP", 0, -5)
    titleHdr:SetText(L["post_title"])

    local closeBtn = CreateFrame("Button", nil, dlg, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", dlg, "TOPRIGHT", -5, -5)
    closeBtn:SetScript("OnClick", function(self) self:GetParent():Hide() end)

    local titleFs = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleFs:SetPoint("TOPLEFT", dlg, "TOPLEFT", 15, -36)
    titleFs:SetWidth(300)
    titleFs:SetJustifyH("LEFT")
    dlg.titleFs = titleFs

    local function MakeInput(parent, yOff, label, isNum)
        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 15, yOff)
        lbl:SetText(label)
        local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        eb:SetSize(100, 20)
        eb:SetPoint("TOPLEFT", parent, "TOPLEFT", 155, yOff + 2)
        eb:SetAutoFocus(false)
        eb:SetMaxLetters(12)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        eb:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)
        eb:SetScript("OnTextChanged", function() AHT:UpdatePostDialogPreview() end)
        if isNum then eb:SetNumeric(true) end
        return eb
    end

    dlg.stackBox = MakeInput(dlg, -60, L["post_stack_label"],  true)
    dlg.numBox   = MakeInput(dlg, -84, L["post_stacks_label"], true)
    dlg.priceBox = MakeInput(dlg, -108, L["post_price_label"], false)

    local previewFs = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    previewFs:SetPoint("TOPLEFT", dlg, "TOPLEFT", 15, -132)
    previewFs:SetWidth(300)
    dlg.previewFs = previewFs

    local inBagsFs = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    inBagsFs:SetPoint("TOPLEFT", dlg, "TOPLEFT", 15, -150)
    inBagsFs:SetWidth(300)
    dlg.inBagsFs = inBagsFs

    local priceInfoFs = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    priceInfoFs:SetPoint("TOPLEFT", dlg, "TOPLEFT", 15, -168)
    priceInfoFs:SetWidth(300)
    dlg.priceInfoFs = priceInfoFs

    local btnPost = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
    btnPost:SetSize(100, 22)
    btnPost:SetText(L["post_btn_post"])
    btnPost:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", 14, 14)
    btnPost:SetScript("OnClick", function()
        local name   = dlg._recipeName
        local recipe = dlg._recipe
        if not name or not recipe then return end
        if not AuctionFrame or not AuctionFrame:IsVisible() then
            AHT:Print(L["scan_ah_required"]); return
        end
        local stackSize = tonumber(dlg.stackBox:GetText()) or 1
        local maxStacks = tonumber(dlg.numBox:GetText())   or 1
        local priceStr  = dlg.priceBox:GetText() or ""
        local ppu       = AHT:ParseMoney(priceStr)
        if ppu and ppu > 0 then recipe.manualPrice = ppu end
        dlg:Hide()
        AHT:StartPost(name, recipe, stackSize, maxStacks)
    end)

    local btnCheck = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
    btnCheck:SetSize(105, 22)
    btnCheck:SetText(L["post_btn_check"])
    btnCheck:SetPoint("BOTTOM", dlg, "BOTTOM", 0, 14)
    btnCheck:SetScript("OnClick", function()
        local name = dlg._recipeName
        if not name then return end
        AHT:CheckPostPrice(name, function(lowestPPU)
            if not dlg or not dlg:IsVisible() then return end
            local L = AHT.L
            if lowestPPU and lowestPPU > 0 then
                local priceStr = dlg.priceBox:GetText() or ""
                local ourPrice = AHT:ParseMoney(priceStr) or 0
                if ourPrice > 0 and ourPrice < lowestPPU then
                    dlg.priceInfoFs:SetText(string.format(L["post_cheaper"],
                        AHT:FormatMoney(lowestPPU - ourPrice)))
                elseif ourPrice > 0 and ourPrice == lowestPPU then
                    dlg.priceInfoFs:SetText(L["post_same_price"])
                else
                    local suggest = math.max(lowestPPU - 1, 1)
                    dlg.priceBox:SetText(AHT:FormatMoneyInput(suggest))
                    dlg.priceInfoFs:SetText(string.format(L["post_cheaper"], AHT:FormatMoney(1)))
                end
            end
        end)
    end)

    local btnCancel = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
    btnCancel:SetSize(95, 22)
    btnCancel:SetText(L["post_btn_cancel"])
    btnCancel:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -14, 14)
    btnCancel:SetScript("OnClick", function(self) self:GetParent():Hide() end)

    postDlg = dlg
    AHT.postDialog = dlg
end

-- ── Refresh-Dispatcher ─────────────────────────────────────────
function AHT:RefreshAllUIs()
    if not mainFrame:IsVisible() then return end
    local tab = AHT.activeTab
    if tab == "alchemy" then
        AHT:ApplyFilterAndSort()
        AHT:RefreshUI()
    elseif tab == "blacksmithing" then
        AHT:RefreshBlacksmithingTab()
    elseif tab == "tailoring" then
        AHT:RefreshTailoringTab()
    elseif tab == "leatherworking" then
        AHT:RefreshLeatherworkingTab()
    elseif tab == "engineering" then
        AHT:RefreshEngineeringTab()
    elseif tab == "mats" then
        AHT:CalculateMatsMargins()
        AHT:RefreshMatsTab()
    end
end

-- ── priceUpdated-Tabelle initialisieren ───────────────────────
if not AHT.priceUpdated then AHT.priceUpdated = {} end

if AHT and AHT._loadStatus then
    AHT._loadStatus.ui = true
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[AHT-DIAG]|r UI.lua OK")
    end
end
