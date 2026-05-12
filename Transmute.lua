-- ============================================================
-- ProjEP AH Trader - Transmute.lua
-- WotLK Transmutations-Analyse
-- WotLK 3.3.5 / Lua 5.1 (Project Epoch)
--
-- WotLK Transmutes (alle teilen 20h Cooldown):
--   Titanium Bar:   8× Saronite Bar → 1× Titanium Bar
--   Ametrine:       Eternal Shadow + Eternal Fire → Ametrine
--   Cardinal Ruby:  Eternal Fire + Eternal Life → Cardinal Ruby
--   Dreadstone:     Eternal Shadow + Eternal Life → Dreadstone
--   Eye of Zul:     Eternal Life + Eternal Water → Eye of Zul
--   King's Amber:   Eternal Life + Eternal Air → King's Amber
--   Majestic Zircon: Eternal Air + Eternal Water → Majestic Zircon
-- ============================================================

local AHT = PROJEP_AHT

-- ── Transmute-Definitionen ────────────────────────────────────
-- EN-Namen (WotLK Standard); DE als Fallback
AHT.transmuteData = {
    {
        id      = "titanium",
        nameEN  = "Transmute: Titanium",
        nameDE  = "Transmutieren: Titan",
        inputs  = {
            { name = "Saronite Bar", nameDE = "Saroniitbarren", count = 8 },
        },
        output  = { name = "Titanium Bar", nameDE = "Titanbarren", count = 1 },
        cooldown = "20h",
    },
    {
        id      = "ametrine",
        nameEN  = "Transmute: Ametrine",
        nameDE  = "Transmutieren: Ametrin",
        inputs  = {
            { name = "Eternal Shadow", nameDE = "Ewiger Schatten", count = 1 },
            { name = "Eternal Fire",   nameDE = "Ewiges Feuer",    count = 1 },
        },
        output  = { name = "Ametrine", nameDE = "Ametrin", count = 1 },
        cooldown = "20h",
    },
    {
        id      = "cardinal_ruby",
        nameEN  = "Transmute: Cardinal Ruby",
        nameDE  = "Transmutieren: Kardinalsrubin",
        inputs  = {
            { name = "Eternal Fire",   nameDE = "Ewiges Feuer",  count = 1 },
            { name = "Eternal Life",   nameDE = "Ewiges Leben",  count = 1 },
        },
        output  = { name = "Cardinal Ruby", nameDE = "Kardinalsrubin", count = 1 },
        cooldown = "20h",
    },
    {
        id      = "dreadstone",
        nameEN  = "Transmute: Dreadstone",
        nameDE  = "Transmutieren: Angststein",
        inputs  = {
            { name = "Eternal Shadow", nameDE = "Ewiger Schatten", count = 1 },
            { name = "Eternal Life",   nameDE = "Ewiges Leben",    count = 1 },
        },
        output  = { name = "Dreadstone", nameDE = "Angststein", count = 1 },
        cooldown = "20h",
    },
    {
        id      = "eye_of_zul",
        nameEN  = "Transmute: Eye of Zul",
        nameDE  = "Transmutieren: Auge des Zul",
        inputs  = {
            { name = "Eternal Life",  nameDE = "Ewiges Leben",   count = 1 },
            { name = "Eternal Water", nameDE = "Ewiges Wasser",  count = 1 },
        },
        output  = { name = "Eye of Zul", nameDE = "Auge des Zul", count = 1 },
        cooldown = "20h",
    },
    {
        id      = "kings_amber",
        nameEN  = "Transmute: King's Amber",
        nameDE  = "Transmutieren: Bernstein des Königs",
        inputs  = {
            { name = "Eternal Life", nameDE = "Ewiges Leben", count = 1 },
            { name = "Eternal Air",  nameDE = "Ewige Luft",   count = 1 },
        },
        output  = { name = "King's Amber", nameDE = "Bernstein des Königs", count = 1 },
        cooldown = "20h",
    },
    {
        id      = "majestic_zircon",
        nameEN  = "Transmute: Majestic Zircon",
        nameDE  = "Transmutieren: Majestätischer Zirkon",
        inputs  = {
            { name = "Eternal Air",   nameDE = "Ewige Luft",   count = 1 },
            { name = "Eternal Water", nameDE = "Ewiges Wasser", count = 1 },
        },
        output  = { name = "Majestic Zircon", nameDE = "Majestätischer Zirkon", count = 1 },
        cooldown = "20h",
    },
}

local TRANSMUTE_MASTER_PROC = 0.20  -- 20% extra proc

-- ── Lokalisierte Namen ────────────────────────────────────────
local function IsDE()
    return GetLocale and GetLocale() == "deDE"
end

local function GetItemLocalName(itemDef)
    return (IsDE() and itemDef.nameDE) or itemDef.name
end

local function GetTransmuteLocalName(t)
    return (IsDE() and t.nameDE) or t.nameEN
end

-- ── Alle Transmutes berechnen ─────────────────────────────────
AHT.transmuteResults = {}

function AHT:CalculateAllTransmutes()
    local results = {}

    for _, t in ipairs(AHT.transmuteData) do
        local inputCost   = 0
        local allFound    = true
        local missing     = {}
        local costDetails = {}

        for _, inp in ipairs(t.inputs) do
            local itemName = GetItemLocalName(inp)
            -- Versuche beide Namen (EN + DE)
            local price = AHT.prices[itemName] or AHT.prices[inp.name] or AHT.prices[inp.nameDE or ""]
            if price then
                local total = price * inp.count
                inputCost   = inputCost + total
                table.insert(costDetails, {
                    name  = itemName,
                    count = inp.count,
                    ppu   = price,
                    total = total,
                })
            else
                allFound = false
                table.insert(missing, itemName)
            end
        end

        local outputName  = GetItemLocalName(t.output)
        local outputPrice = AHT.prices[outputName] or AHT.prices[t.output.name] or AHT.prices[t.output.nameDE or ""]

        -- Zeitstempel
        local updatedAt = nil
        local names = { outputName, t.output.name }
        for _, inp in ipairs(t.inputs) do
            table.insert(names, GetItemLocalName(inp))
            table.insert(names, inp.name)
        end
        for _, n in ipairs(names) do
            local ts = AHT.priceUpdated[n]
            if ts then
                if not updatedAt or ts < updatedAt then updatedAt = ts end
            end
        end

        local r = {
            id          = t.id,
            name        = GetTransmuteLocalName(t),
            outputName  = outputName,
            inputs      = t.inputs,
            inputCost   = inputCost,
            outputPrice = outputPrice,
            costDetails = costDetails,
            missing     = missing,
            allFound    = allFound,
            updatedAt   = updatedAt,
            listingCount = AHT.listingCounts[outputName] or AHT.listingCounts[t.output.name] or 0,
        }

        -- Gewinn ohne/mit Master-Proc
        if allFound and outputPrice then
            local provision = math.floor(outputPrice * AHT.ahCutRate)
            local deposit   = AHT:CalcDeposit(outputName)
            local netIncome = outputPrice - provision - deposit

            r.profit = netIncome - inputCost

            if AHT.isMasterAlch then
                -- Mit Transmutation Master: effektiv 1.2× Output im Erwartungswert
                local effectiveOut = outputPrice * (1 + TRANSMUTE_MASTER_PROC)
                local netWithProc  = effectiveOut - provision - deposit
                r.profitWithProc   = netWithProc - inputCost
                r.effectiveOutput  = 1 + TRANSMUTE_MASTER_PROC
            else
                r.profitWithProc  = r.profit
                r.effectiveOutput = 1.0
            end
            r.margin = inputCost > 0 and (r.profit / inputCost) * 100 or 0
        end

        table.insert(results, r)
    end

    -- Nach Gewinn sortieren (absteigend)
    table.sort(results, function(a, b)
        local pa = a.profit or -999999
        local pb = b.profit or -999999
        return pa > pb
    end)

    AHT.transmuteResults = results
    return results
end

-- ── Scan-State für Transmute-Items ───────────────────────────
AHT.transmuteScanState     = "idle"
AHT.transmuteScanTimer     = 0
AHT.transmuteSentTimer     = 0
AHT.transmuteScanRetries   = 0
AHT.transmuteScanQueue     = {}
AHT.transmuteScanQueueIdx  = 0
AHT.transmuteCurrentItem   = nil
AHT.transmuteCurrentPage   = 0
AHT.transmuteScanMinPrices = {}
AHT.transmuteScanListings  = {}

function AHT:IsTransmuteScanning()
    return AHT.transmuteScanState ~= "idle"
end

function AHT:StartTransmuteScan()
    if AHT:IsTransmuteScanning() then
        AHT:Print(AHT.L["transmute_scan_already"]); return
    end
    if not AuctionFrame or not AuctionFrame:IsVisible() then
        AHT:Print(AHT.L["scan_ah_required"]); return
    end

    -- Alle Transmute-Items in die Queue
    local seen, queue = {}, {}
    for _, t in ipairs(AHT.transmuteData) do
        local outName = GetItemLocalName(t.output)
        if not seen[outName] then seen[outName] = true; table.insert(queue, outName) end
        if not seen[t.output.name] and t.output.name ~= outName then
            seen[t.output.name] = true; table.insert(queue, t.output.name)
        end
        for _, inp in ipairs(t.inputs) do
            local inpName = GetItemLocalName(inp)
            if not seen[inpName] then seen[inpName] = true; table.insert(queue, inpName) end
        end
    end

    AHT.transmuteScanQueue     = queue
    AHT.transmuteScanQueueIdx  = 0
    AHT.transmuteScanMinPrices = {}
    AHT.transmuteScanListings  = {}
    AHT.transmuteScanState     = "waiting"
    AHT.transmuteScanTimer     = 0
    AHT.transmuteSentTimer     = 0

    AHT:Print(string.format(AHT.L["transmute_scan_start"], #queue))
    AHT:AdvanceTransmuteScanQueue()
end

function AHT:CancelTransmuteScan()
    if not AHT:IsTransmuteScanning() then return end
    AHT.transmuteScanState = "idle"
    AHT:Print(AHT.L["transmute_scan_cancelled"])
    if PROJEP_AHT_TransmuteUI and PROJEP_AHT_TransmuteUI:IsVisible() then
        AHT:RefreshTransmuteUI()
    end
end

function AHT:AdvanceTransmuteScanQueue()
    AHT.transmuteScanQueueIdx = AHT.transmuteScanQueueIdx + 1
    if AHT.transmuteScanQueueIdx > #AHT.transmuteScanQueue then
        AHT:OnTransmuteScanComplete(); return
    end
    AHT.transmuteCurrentItem  = AHT.transmuteScanQueue[AHT.transmuteScanQueueIdx]
    AHT.transmuteCurrentPage  = 0
    AHT.transmuteScanRetries  = 0
    AHT.transmuteScanState    = "waiting"
    AHT.transmuteScanTimer    = 0
    AHT.transmuteSentTimer    = 0
end

-- Wird von Core.lua's OnUpdate aufgerufen wenn transmuteScanState ~= idle
function AHT:OnUpdateTransmute(elapsed)
    if AHT.transmuteScanState == "waiting" then
        AHT.transmuteScanTimer = AHT.transmuteScanTimer + elapsed
        AHT.transmuteSentTimer = AHT.transmuteSentTimer + elapsed
        if AHT.transmuteSentTimer >= 30 then
            AHT:Print(string.format(AHT.L["scan_timeout"], AHT.transmuteCurrentItem or "?"))
            AHT:AdvanceTransmuteScanQueue(); return
        end
        if AHT.transmuteScanTimer >= 0.3 then
            AHT.transmuteScanTimer = 0
            if CanSendAuctionQuery() then
                local _, ci, si = AHT:GetAuctionQueryFilters(AHT.transmuteCurrentItem)
                AHT.transmuteSentTimer = 0
                AHT.transmuteScanState = "sent"
                QueryAuctionItems(AHT.transmuteCurrentItem, nil, nil, nil, ci, si,
                    AHT.transmuteCurrentPage, nil, nil)
            end
        end
    elseif AHT.transmuteScanState == "sent" then
        AHT.transmuteSentTimer = AHT.transmuteSentTimer + elapsed
        if AHT.transmuteSentTimer >= 15 then
            AHT.transmuteSentTimer   = 0
            AHT.transmuteScanRetries = AHT.transmuteScanRetries + 1
            if AHT.transmuteScanRetries > 2 then
                AHT:Print(string.format(AHT.L["scan_timeout"], AHT.transmuteCurrentItem or "?"))
                AHT:AdvanceTransmuteScanQueue()
            else
                AHT.transmuteScanState = "waiting"
                AHT.transmuteScanTimer = 0
            end
        end
    end
end

function AHT:OnTransmuteAuctionListUpdate()
    if AHT.transmuteScanState ~= "sent" then return end
    AHT.transmuteSentTimer = 0
    local numItems = GetNumAuctionItems("list")
    local player   = UnitName("player")

    for i = 1, numItems do
        local name, _, count, _, _, _, _, _, buyoutPrice, _, _, _, _, owner, ownerFull =
            GetAuctionItemInfo("list", i)
        local isOwn = (owner == player) or (ownerFull and ownerFull:match("^" .. player))
        if AHT:NameMatches(name, AHT.transmuteCurrentItem)
           and buyoutPrice and buyoutPrice > 0
           and count and count > 0 and not isOwn then
            local key = AHT.transmuteCurrentItem
            local ppu = math.floor(buyoutPrice / count)
            if not AHT.transmuteScanMinPrices[key] or ppu < AHT.transmuteScanMinPrices[key] then
                AHT.transmuteScanMinPrices[key] = ppu
            end
            AHT.transmuteScanListings[key] = (AHT.transmuteScanListings[key] or 0) + 1
        end
    end

    if numItems >= 50 then
        AHT.transmuteCurrentPage = AHT.transmuteCurrentPage + 1
        AHT.transmuteScanState   = "waiting"
        AHT.transmuteScanTimer   = 0
    else
        AHT:AdvanceTransmuteScanQueue()
    end
end

function AHT:OnTransmuteScanComplete()
    AHT.transmuteScanState = "idle"
    local now = time()
    for name, price in pairs(AHT.transmuteScanMinPrices) do
        AHT.prices[name]       = price
        AHT.priceUpdated[name] = now
        AHT:AddPriceHistory(name, price)
    end
    for name, cnt in pairs(AHT.transmuteScanListings) do
        AHT.listingCounts[name] = cnt
    end
    AHT:SaveDB()
    AHT:CalculateAllTransmutes()
    AHT:Print(string.format(AHT.L["transmute_scan_complete"],
        AHT:TableCount(AHT.transmuteScanMinPrices)))

    -- Besten Transmute ausgeben
    if #AHT.transmuteResults > 0 then
        local best = AHT.transmuteResults[1]
        if best.profit and best.profit > 0 then
            AHT:Print(string.format(AHT.L["transmute_best"],
                best.name, AHT:FormatMoney(best.profit)))
        end
    end

    if PROJEP_AHT_TransmuteUI and PROJEP_AHT_TransmuteUI:IsVisible() then
        AHT:RefreshTransmuteUI()
    end
end

-- ── Transmute-Button ─────────────────────────────────────────
function AHT:CreateTransmuteButton()
    if AHT.transmuteButton then AHT.transmuteButton:Show(); return end
    local btn = CreateFrame("Button", "ProjEP_AHT_TransmuteBtn", UIParent, "UIPanelButtonTemplate")
    btn:SetSize(120, 22)
    btn:SetText(AHT.L["transmute_button"])
    btn:SetPoint("TOPLEFT", AuctionFrame, "TOPLEFT", 471, -28)
    btn:SetScript("OnClick", function(self)
        if AHT:IsTransmuteScanning() then AHT:CancelTransmuteScan()
        else AHT:ShowTransmuteUI() end
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(AHT.L["transmute_title"])
        if AHT:IsTransmuteScanning() then
            GameTooltip:AddLine(AHT.L["transmute_tooltip_cancel"], 1, 0.5, 0.5)
        else
            GameTooltip:AddLine(AHT.L["transmute_tooltip_open"], 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    AHT.transmuteButton = btn
end

-- ── Transmute-UI ─────────────────────────────────────────────
local TFRAME_W = 640
local TFRAME_H = 380

function AHT:ShowTransmuteUI()
    if not PROJEP_AHT_TransmuteUI then AHT:CreateTransmuteUI() end
    AHT:CalculateAllTransmutes()
    PROJEP_AHT_TransmuteUI:Show()
    AHT:RefreshTransmuteUI()
end

function AHT:CreateTransmuteUI()
    if PROJEP_AHT_TransmuteUI then return end

    local f = CreateFrame("Frame", "PROJEP_AHT_TransmuteUI", UIParent)
    f:SetSize(TFRAME_W, TFRAME_H)
    f:SetPoint("CENTER", 0, -100)
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

    local titleStr = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleStr:SetPoint("TOP", f, "TOP", 0, -5)
    titleStr:SetText(AHT.L["transmute_title"])

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)
    closeBtn:SetScript("OnClick", function(self) self:GetParent():Hide() end)

    -- Status
    local statusText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("TOPLEFT", f, "TOPLEFT", 15, -28)
    statusText:SetWidth(TFRAME_W - 80)
    statusText:SetJustifyH("LEFT")
    f._status = statusText

    -- Transmutation Master Checkbox
    local masterCB = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    masterCB:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, -24)
    masterCB:SetSize(20, 20)
    masterCB:SetChecked(AHT.isMasterAlch)
    masterCB:SetScript("OnClick", function(self)
        AHT.isMasterAlch = self:GetChecked() and true or false
        AHT:SaveDB()
        AHT:CalculateAllTransmutes()
        AHT:RefreshTransmuteUI()
    end)
    local masterLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    masterLabel:SetPoint("RIGHT", masterCB, "LEFT", -2, 0)
    masterLabel:SetText(AHT.L["transmute_master_label"])
    f._masterCB = masterCB

    -- Header-Zeile
    local cols = {
        { text = AHT.L["transmute_col_name"],   x = 14,  w = 200 },
        { text = AHT.L["transmute_col_input"],  x = 220, w = 120 },
        { text = AHT.L["transmute_col_output"], x = 350, w = 100 },
        { text = AHT.L["transmute_col_profit"], x = 460, w = 100 },
        { text = AHT.L["transmute_col_updated"],x = 568, w = 60  },
    }
    local headerY = -56
    for _, col in ipairs(cols) do
        local h = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h:SetPoint("TOPLEFT", f, "TOPLEFT", col.x, headerY)
        h:SetWidth(col.w)
        h:SetJustifyH("LEFT")
        h:SetText("|cffffff00" .. col.text .. "|r")
    end

    -- Trennlinie
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetTexture(0.6, 0.6, 0.6, 0.4)
    sep:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -68)
    sep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -68)
    sep:SetHeight(1)

    -- Scrollframe für Zeilen
    local sf = CreateFrame("ScrollFrame", nil, f)
    sf:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -72)
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 46)

    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(TFRAME_W - 44, 1)
    sf:SetScrollChild(content)
    f._content = content

    -- Scrollbar
    local sb = CreateFrame("Slider", nil, f, "UIPanelScrollBarTemplate")
    sb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -72)
    sb:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 46)
    sb:SetMinMaxValues(0, 0)
    sb:SetValueStep(20)
    sb:SetValue(0)
    sb:SetScript("OnValueChanged", function(self, val)
        sf:SetVerticalScroll(val)
    end)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local cur = sb:GetValue()
        sb:SetValue(cur - delta * 20)
    end)
    f._scrollbar = sb

    -- Scan-Button
    local scanBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    scanBtn:SetSize(130, 22)
    scanBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 12)
    scanBtn:SetScript("OnClick", function(self)
        if AHT:IsTransmuteScanning() then AHT:CancelTransmuteScan()
        elseif not AuctionFrame or not AuctionFrame:IsVisible() then
            AHT:Print(AHT.L["scan_ah_required"])
        else
            AHT:StartTransmuteScan()
        end
    end)
    f._scanBtn = scanBtn

    f._rows = {}
    PROJEP_AHT_TransmuteUI = f
end

function AHT:RefreshTransmuteUI()
    local f = PROJEP_AHT_TransmuteUI
    if not f or not f:IsVisible() then return end

    AHT:CalculateAllTransmutes()
    if f._masterCB then f._masterCB:SetChecked(AHT.isMasterAlch) end

    if AHT:IsTransmuteScanning() then
        f._status:SetText(string.format(AHT.L["transmute_status_scanning"],
            AHT.transmuteScanQueueIdx, #AHT.transmuteScanQueue,
            AHT.transmuteCurrentItem or "..."))
        if f._scanBtn then f._scanBtn:SetText(AHT.L["scan_cancel"]) end
    else
        f._status:SetText(#AHT.transmuteResults > 0
            and AHT.L["transmute_status_ready"]
            or  AHT.L["transmute_status_no_data"])
        if f._scanBtn then f._scanBtn:SetText(AHT.L["scan_button"]:gsub("Trank%-Analyse", "Scan"):gsub("Potion Analysis", "Scan")) end
    end

    -- Zeilen neu aufbauen
    local content = f._content
    -- Alte Zeilen verstecken
    for _, row in ipairs(f._rows or {}) do row:Hide() end
    f._rows = {}

    local rowH  = 20
    local total = #AHT.transmuteResults
    local y     = 0

    for i, r in ipairs(AHT.transmuteResults) do
        -- Zeile erstellen oder wiederverwenden
        local row = CreateFrame("Button", nil, content)
        row:SetSize(TFRAME_W - 44, rowH)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        row:EnableMouse(true)

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        if i % 2 == 0 then bg:SetTexture(0.1, 0.1, 0.1, 0.5)
        else bg:SetTexture(0, 0, 0, 0) end

        -- Name
        local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameFS:SetPoint("LEFT", row, "LEFT", 0, 0)
        nameFS:SetWidth(200)
        nameFS:SetJustifyH("LEFT")
        nameFS:SetText(r.name)

        -- Materialkosten
        local costFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        costFS:SetPoint("LEFT", row, "LEFT", 206, 0)
        costFS:SetWidth(120)
        local costText = (r.allFound and r.inputCost > 0)
            and AHT:FormatMoney(r.inputCost)
            or "|cffaaaaaa?|r"
        costFS:SetText(costText)

        -- Outputpreis
        local sellFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sellFS:SetPoint("LEFT", row, "LEFT", 336, 0)
        sellFS:SetWidth(100)
        sellFS:SetText(r.outputPrice and AHT:FormatMoney(r.outputPrice) or "|cffaaaaaa?|r")

        -- Gewinn (mit/ohne Proc)
        local profFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        profFS:SetPoint("LEFT", row, "LEFT", 446, 0)
        profFS:SetWidth(100)
        if r.profit then
            local dispProfit = AHT.isMasterAlch and (r.profitWithProc or r.profit) or r.profit
            local color = dispProfit >= 0 and "|cff00ff00" or "|cffff5555"
            profFS:SetText(color .. AHT:FormatMoney(dispProfit) .. "|r")
        else
            local mtext = #r.missing > 0
                and ("|cffff9900" .. table.concat(r.missing, ", "):sub(1,20) .. "|r")
                or  "|cffaaaaaa?|r"
            profFS:SetText(mtext)
        end

        -- Aktualisiert
        local updFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        updFS:SetPoint("LEFT", row, "LEFT", 554, 0)
        updFS:SetWidth(70)
        updFS:SetText(r.updatedAt
            and date(AHT.L["date_short"], r.updatedAt)
            or "|cffaaaaaa-|r")

        -- Tooltip
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(r.name, 1, 1, 0)
            GameTooltip:AddLine(AHT.L["transmute_cooldown"], 0.7, 0.7, 0.7)
            GameTooltip:AddLine(" ")
            for _, inp in ipairs(r.inputs or {}) do
                local inpName  = GetItemLocalName(inp)
                local inpPrice = AHT.prices[inpName] or AHT.prices[inp.name] or 0
                GameTooltip:AddDoubleLine(inp.count .. "× " .. inpName,
                    AHT:FormatMoneyPlain(inpPrice * inp.count), 0.8,0.8,0.8,1,1,1)
            end
            if r.inputCost > 0 then
                GameTooltip:AddDoubleLine(AHT.L["ui_col_cost"],
                    AHT:FormatMoneyPlain(r.inputCost), 1,1,0,1,1,0)
            end
            if r.outputPrice then
                GameTooltip:AddDoubleLine(AHT.L["transmute_col_output"],
                    AHT:FormatMoneyPlain(r.outputPrice), 1,1,1,1,1,1)
            end
            if r.profit then
                local col = r.profit >= 0 and "00ff00" or "ff5555"
                GameTooltip:AddDoubleLine(AHT.L["transmute_without_proc"],
                    AHT:FormatMoneyPlain(r.profit), 0.7,0.7,0.7,1,1,1)
                if AHT.isMasterAlch and r.profitWithProc then
                    GameTooltip:AddDoubleLine(AHT.L["transmute_with_proc"],
                        AHT:FormatMoneyPlain(r.profitWithProc), 0,1,0,0,1,0)
                end
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        table.insert(f._rows, row)
        y = y + rowH
    end

    content:SetHeight(math.max(y, 1))
    local visibleH = f:GetHeight() - 118
    local maxScroll = math.max(0, y - visibleH)
    f._scrollbar:SetMinMaxValues(0, maxScroll)
    if f._scrollbar:GetValue() > maxScroll then
        f._scrollbar:SetValue(maxScroll)
    end
end

-- OnUpdate für Transmute-Scan registrieren
local transmUpdateFrame = CreateFrame("Frame")
transmUpdateFrame:SetScript("OnUpdate", function(self, elapsed)
    if AHT.transmuteScanState and AHT.transmuteScanState ~= "idle" then
        AHT:OnUpdateTransmute(elapsed)
    end
end)

if AHT and AHT._loadStatus then
    AHT._loadStatus.transmute = true
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[AHT-DIAG]|r Transmute.lua OK")
    end
end
