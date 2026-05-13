-- ============================================================
-- ProjEP AH Trader - Scanner.lua
-- AH-Scan: Item-für-Item-Scan + GetAll-Scan (WotLK)
-- WotLK 3.3.5 / Lua 5.1 (Project Epoch)
--
-- Scan-Zustandsautomat:
--   "idle"         – kein Scan aktiv
--   "waiting"      – wartet auf CanSendAuctionQuery()
--   "sent"         – QueryAuctionItems gesendet
--   "getall_waiting" – wartet für GetAll-Query
--   "getall_sent"  – GetAll gesendet, wartet auf Antwort
-- ============================================================

local AHT = PROJEP_AHT

-- ── Scan-Zustand ─────────────────────────────────────────────
AHT.scanState     = "idle"
AHT.scanTimer     = 0
AHT.sentTimer     = 0
AHT.scanRetries   = 0
AHT.scanQueue     = {}
AHT.scanQueueIdx  = 0
AHT.currentItem   = nil
AHT.scanPage      = 0
AHT.scanMinPrices = {}
AHT.scanListingCounts = {}
AHT.scanOffers    = {}   -- [itemName] = [{ppu,count,buyout}]
AHT.lastScanTime  = nil

AHT.SCAN_DELAY   = 0.3
AHT.SENT_TIMEOUT = 15.0
AHT.WAIT_TIMEOUT = 30.0
AHT.MAX_RETRIES  = 2

-- ── AH öffnen ────────────────────────────────────────────────
function AHT:OnAHShow()
    AHT:RefreshAuctionQueryCaches()
    local ok, err = pcall(function() AHT:CreateAHTMainButton() end)
    if not ok then AHT:Print("AHTMainBtn Fehler: " .. tostring(err)) end
end

-- ── AH-Buttons ────────────────────────────────────────────────
function AHT:CreateAHTMainButton()
    if AHT.ahtMainButton then AHT.ahtMainButton:Show(); return end
    local btn = CreateFrame("Button", "ProjEP_AHT_MainBtn", AuctionFrame, "UIPanelButtonTemplate")
    btn:SetSize(110, 22)
    btn:SetText("|cffffff00AH Trader|r")
    btn:SetPoint("TOPLEFT", AuctionFrame, "TOPLEFT", 70, -28)
    btn:SetScript("OnClick", function()
        AHT:ShowUI()
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("ProjEP AH Trader", 1, 1, 0)
        GameTooltip:AddLine("Öffnet das AH-Trader Fenster", 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    AHT.ahtMainButton = btn
end

-- ── Scan-Status ───────────────────────────────────────────────
function AHT:IsScanning()
    return AHT.scanState ~= "idle"
end

-- ── Scan abbrechen ────────────────────────────────────────────
function AHT:CancelScan()
    if AHT.scanState == "idle" then
        AHT:Print(AHT.L["scan_no_active"]); return
    end
    AHT:Print(AHT.L["scan_cancelled"])
    -- bereits gesammelte Preise übernehmen
    local now = time()
    for name, price in pairs(AHT.scanMinPrices) do
        AHT.prices[name] = price
        AHT.priceUpdated[name] = now
    end
    AHT.scanState = "idle"
    AHT:SetScanButtonText(AHT.L["scan_button"])
    AHT:SaveDB()
end

-- ─────────────────────────────────────────────────────────────
-- ITEM-FÜR-ITEM SCAN
-- ─────────────────────────────────────────────────────────────

function AHT:StartScan()
    if AHT:IsScanning() then
        AHT:Print(AHT.L["scan_already_running"]); return
    end
    if not AuctionFrame or not AuctionFrame:IsVisible() then
        AHT:Print(AHT.L["scan_ah_required"]); return
    end
    if #AHT.recipes == 0 then
        AHT:Print(AHT.L["scan_no_recipes"]); return
    end

    for name, price in pairs(AHT.vendorPrices) do
        AHT.prices[name] = price
    end

    local seen, queue = {}, {}
    for _, recipe in ipairs(AHT.recipes) do
        if AHT.selected[recipe.name] ~= false then
            if not seen[recipe.name] and not AHT:IsVendorItem(recipe.name) then
                table.insert(queue, recipe.name); seen[recipe.name] = true
            end
            for _, r in ipairs(recipe.reagents) do
                if not seen[r.name] and not AHT:IsVendorItem(r.name) then
                    table.insert(queue, r.name); seen[r.name] = true
                end
            end
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

    AHT:Print(string.format(AHT.L["scan_start"], #queue))
    AHT:SetScanButtonText(AHT.L["scan_cancel"])
    AHT:AdvanceScanQueue()
end

function AHT:StartSnipeScan()
    if AHT:IsScanning() then
        AHT:Print(AHT.L["scan_already_running"]); return
    end
    if not AuctionFrame or not AuctionFrame:IsVisible() then
        AHT:Print(AHT.L["scan_ah_required"]); return
    end
    local seen, queue = {}, {}
    for name in pairs(AHT.priceHistory) do
        if not seen[name] and not AHT:IsVendorItem(name) then
            table.insert(queue, name); seen[name] = true
        end
    end
    if #queue == 0 then
        AHT:Print(AHT.L["scan_no_history"]); return
    end
    AHT.scanQueue         = queue
    AHT.scanQueueIdx      = 0
    AHT.scanMinPrices     = {}
    AHT.scanListingCounts = {}
    AHT.scanOffers        = {}
    AHT:Print(string.format(AHT.L["scan_snipe_start"], #queue))
    AHT:SetScanButtonText(AHT.L["scan_cancel"])
    AHT:AdvanceScanQueue()
end

function AHT:AdvanceScanQueue()
    AHT.scanQueueIdx = AHT.scanQueueIdx + 1
    if AHT.scanQueueIdx > #AHT.scanQueue then
        AHT:OnScanComplete(); return
    end
    AHT.currentItem = AHT.scanQueue[AHT.scanQueueIdx]
    AHT.scanPage    = 0
    AHT.scanRetries = 0
    AHT.scanState   = "waiting"
    AHT.scanTimer   = 0
    AHT.sentTimer   = 0
    AHT:UpdateScanProgress()
end

function AHT:OnUpdate(elapsed)
    if AHT.scanState == "waiting" then
        AHT.scanTimer = AHT.scanTimer + elapsed
        AHT.sentTimer = AHT.sentTimer + elapsed
        if AHT.sentTimer >= AHT.WAIT_TIMEOUT then
            AHT:Print(string.format(AHT.L["scan_timeout"], AHT.currentItem or "?"))
            AHT:AdvanceScanQueue(); return
        end
        if AHT.scanTimer >= AHT.SCAN_DELAY then
            AHT.scanTimer = 0
            if CanSendAuctionQuery() then
                local _, ci, si = AHT:GetAuctionQueryFilters(AHT.currentItem)
                AHT.sentTimer = 0
                AHT.scanState = "sent"
                QueryAuctionItems(AHT.currentItem, nil, nil, nil, ci, si, AHT.scanPage, nil, nil)
            end
        end

    elseif AHT.scanState == "sent" then
        AHT.sentTimer = AHT.sentTimer + elapsed
        if AHT.sentTimer >= AHT.SENT_TIMEOUT then
            AHT.sentTimer   = 0
            AHT.scanRetries = AHT.scanRetries + 1
            if AHT.scanRetries > AHT.MAX_RETRIES then
                AHT:Print(string.format(AHT.L["scan_timeout"], AHT.currentItem or "?"))
                AHT:AdvanceScanQueue()
            else
                AHT.scanState = "waiting"
                AHT.scanTimer = 0
            end
        end

    elseif AHT.scanState == "getall_waiting" then
        AHT.scanTimer = AHT.scanTimer + elapsed
        if AHT.scanTimer >= AHT.SCAN_DELAY then
            AHT.scanTimer = 0
            if CanSendAuctionQuery() then
                AHT.scanState = "getall_sent"
                AHT.sentTimer = 0
                AHT.getAllLastTime = GetTime()
                QueryAuctionItems("", nil, nil, nil, nil, nil, 0, nil, nil, true)
                AHT:Print(AHT.L["getall_scan_sending"])
            end
        end

    elseif AHT.scanState == "getall_sent" then
        AHT.sentTimer = AHT.sentTimer + elapsed
        if AHT.sentTimer >= 60.0 then
            -- GetAll-Timeout nach 60s
            AHT:Print("GetAll-Timeout. Abgebrochen.")
            AHT.scanState = "idle"
        end
    end
end

-- ── AH-Ergebnis (Item-Scan) ───────────────────────────────────
function AHT:OnAuctionListUpdate()
    if AHT.scanState ~= "sent" then return end
    AHT.sentTimer = 0

    local numItems  = GetNumAuctionItems("list")
    local player    = UnitName("player")

    for i = 1, numItems do
        local name, _, count, _, _, _, _, _, buyoutPrice, _, _, _, _, owner, ownerFull, _, itemId =
            GetAuctionItemInfo("list", i)

        -- In WotLK: ownerFullName enthält "Name-Realm" oder nur "Name"
        local isOwn = (owner == player) or (ownerFull and ownerFull:match("^" .. player))

        if AHT:NameMatches(name, AHT.currentItem)
           and buyoutPrice and buyoutPrice > 0
           and count and count > 0
           and not isOwn then
            -- Kanonischen Namen (aus dem Scan-Queue) verwenden, damit Lookups in
            -- AHT.prices/recipes konsistent matchen.
            local key = AHT.currentItem
            local ppu = math.floor(buyoutPrice / count)
            if not AHT.scanMinPrices[key] or ppu < AHT.scanMinPrices[key] then
                AHT.scanMinPrices[key] = ppu
            end
            AHT.scanListingCounts[key] = (AHT.scanListingCounts[key] or 0) + 1
            -- Angebots-Cache für Kaufdialog
            if not AHT.scanOffers[key] then AHT.scanOffers[key] = {} end
            table.insert(AHT.scanOffers[key], { ppu = ppu, count = count, buyout = buyoutPrice })
            -- itemId cachen wenn verfügbar
            if itemId and itemId > 0 then
                AHT.nameToId[key] = itemId
                AHT.idToName[itemId] = key
            end
        end
    end

    if numItems >= 50 then
        AHT.scanPage  = AHT.scanPage + 1
        AHT.scanState = "waiting"
        AHT.scanTimer = 0
    else
        AHT:AdvanceScanQueue()
    end
end

-- ── Scan abgeschlossen ────────────────────────────────────────
function AHT:OnScanComplete()
    AHT.scanState    = "idle"
    AHT.lastScanTime = GetTime()
    local now        = time()

    for name, price in pairs(AHT.scanMinPrices) do
        AHT.prices[name]       = price
        AHT.priceUpdated[name] = now
        AHT:AddPriceHistory(name, price)
    end
    for name, cnt in pairs(AHT.scanListingCounts) do
        AHT.listingCounts[name] = cnt
    end
    for _, item in ipairs(AHT.scanQueue) do
        if not AHT.scanListingCounts[item] then
            AHT.listingCounts[item] = 0
        end
        -- Nicht gefundene Items: Preis löschen
        if not AHT.scanMinPrices[item] and not AHT:IsVendorItem(item) then
            AHT.prices[item]       = nil
            AHT.priceUpdated[item] = nil
        end
    end
    -- Angebots-Cache aktualisieren
    for name, offers in pairs(AHT.scanOffers) do
        AHT.allOffersCache[name] = { t = now, offers = offers }
    end

    AHT:SaveDB()

    local found, missing = 0, 0
    for _, item in ipairs(AHT.scanQueue) do
        if AHT.prices[item] then found = found + 1 else missing = missing + 1 end
    end
    local msg = string.format(AHT.L["scan_complete"], found)
    msg = msg .. (missing > 0 and string.format(AHT.L["scan_missing"], missing) or ".")
    AHT:Print(msg)

    -- Schnäppchen-Erkennung
    local deals = {}
    for name, price in pairs(AHT.scanMinPrices) do
        if AHT:IsDeal(name) then
            local avg = AHT:GetPriceAverage(name)
            local pct = math.floor((1 - price / avg) * 100)
            table.insert(deals, { name = name, price = price, avg = avg, pct = pct })
        end
    end
    if #deals > 0 then
        AHT:Print(string.format(AHT.L["scan_deals_found"], #deals))
        for _, d in ipairs(deals) do
            AHT:Print("  |cff00ffff★|r " .. d.name .. ": " .. AHT:FormatMoney(d.price) ..
                " |cffaaaaaa(Avg: " .. AHT:FormatMoney(d.avg) .. ", -" .. d.pct .. "%)|r")
        end
    end

    AHT:SetScanButtonText(AHT.L["scan_button"])
    AHT:CalculateMargins()
    if #(AHT.bsRecipes   or {}) > 0 then AHT:CalculateBlacksmithingMargins() end
    if #(AHT.tailRecipes or {}) > 0 then AHT:CalculateTailoringMargins() end
    if #(AHT.lwRecipes   or {}) > 0 then AHT:CalculateLeatherworkingMargins() end
    if #(AHT.engRecipes  or {}) > 0 then AHT:CalculateEngineeringMargins() end
    AHT:RefreshAllUIs()
end

-- ─────────────────────────────────────────────────────────────
-- GETALL SCAN
-- ─────────────────────────────────────────────────────────────

function AHT:StartGetAllScan()
    if AHT:IsScanning() then
        AHT:Print(AHT.L["scan_already_running"]); return
    end
    if not AuctionFrame or not AuctionFrame:IsVisible() then
        AHT:Print(AHT.L["scan_ah_required"]); return
    end
    if not AHT:CanGetAllScan() then
        local r = AHT:GetAllRemainingCooldown()
        AHT:Print(string.format(AHT.L["getall_on_cooldown"], math.floor(r/60), r%60))
        return
    end

    AHT.scanMinPrices     = {}
    AHT.scanListingCounts = {}
    AHT.scanOffers        = {}
    AHT.scanState         = "getall_waiting"
    AHT.scanTimer         = 0
    AHT.sentTimer         = 0
    AHT:Print(AHT.L["getall_scan_start"])
end

-- Wird durch OnAuctionItemListUpdate aufgerufen wenn scanState == "getall_sent"
function AHT:OnGetAllAuctionListUpdate()
    if AHT.scanState ~= "getall_sent" then return end

    local numItems = GetNumAuctionItems("list")
    AHT:Print(string.format(AHT.L["getall_scan_processing"], numItems))

    local player = UnitName("player")
    local now    = time()

    for i = 1, numItems do
        local name, _, count, _, _, _, _, _, buyoutPrice, _, _, _, _, owner, ownerFull, _, itemId =
            GetAuctionItemInfo("list", i)

        local isOwn = (owner == player) or (ownerFull and ownerFull:match("^" .. player))

        if name and buyoutPrice and buyoutPrice > 0
           and count and count > 0 and not isOwn then
            local ppu = math.floor(buyoutPrice / count)

            if not AHT.scanMinPrices[name] or ppu < AHT.scanMinPrices[name] then
                AHT.scanMinPrices[name] = ppu
            end
            AHT.scanListingCounts[name] = (AHT.scanListingCounts[name] or 0) + 1

            if not AHT.scanOffers[name] then AHT.scanOffers[name] = {} end
            table.insert(AHT.scanOffers[name], { ppu = ppu, count = count, buyout = buyoutPrice })

            -- itemId <-> name Mapping aufbauen
            if itemId and itemId > 0 then
                AHT.nameToId[name]   = itemId
                AHT.idToName[itemId] = name
            end
        end
    end

    AHT:OnGetAllScanComplete(numItems)
end

function AHT:OnGetAllScanComplete(numItems)
    AHT.scanState = "idle"
    local now     = time()
    local updated = 0

    for name, price in pairs(AHT.scanMinPrices) do
        AHT.prices[name]       = price
        AHT.priceUpdated[name] = now
        AHT:AddPriceHistory(name, price)
        updated = updated + 1
    end
    for name, cnt in pairs(AHT.scanListingCounts) do
        AHT.listingCounts[name] = cnt
    end
    -- Angebots-Cache aktualisieren
    for name, offers in pairs(AHT.scanOffers) do
        AHT.allOffersCache[name] = { t = now, offers = offers }
        -- Für Mats-Kaufdialog kompatibel auch in matsOfferCache
        AHT.matsOfferCache[name] = { t = now, offers = offers }
    end

    AHT:SaveDB()
    AHT:Print(string.format(AHT.L["getall_scan_complete"], updated))

    -- Alle bekannten Analysen neu berechnen
    if #AHT.recipes > 0        then AHT:CalculateMargins()         end
    if AHT.transmuteData       then AHT:CalculateAllTransmutes()    end
    if #(AHT.glyphs or {}) > 0 then AHT:CalculateGlyphMargins()    end
    if #(AHT.gemCuts or {}) > 0 then AHT:CalculateGemCutMargins()  end
    if AHT:TableCount(AHT.materials) > 0 then AHT:CalculateMatsMargins() end

    AHT:RefreshAllUIs()
end

-- ── Mats-Scan ─────────────────────────────────────────────────
AHT.matsScanState     = "idle"
AHT.matsScanTimer     = 0
AHT.matsSentTimer     = 0
AHT.matsScanRetries   = 0
AHT.matsScanQueue     = {}
AHT.matsScanQueueIdx  = 0
AHT.matsCurrentItem   = nil
AHT.matsCurrentPage   = 0
AHT.matsScanMinPrices = {}
AHT.matsScanListingCounts = {}
AHT.matsScanOffers    = {}

function AHT:IsMatScanning()
    return AHT.matsScanState and AHT.matsScanState ~= "idle" or false
end

function AHT:StartMatsScan()
    if AHT:IsMatScanning() then
        AHT:Print(AHT.L["mats_scan_already_running"]); return
    end
    if not AuctionFrame or not AuctionFrame:IsVisible() then
        AHT:Print(AHT.L["scan_ah_required"]); return
    end
    if AHT:TableCount(AHT.materials) == 0 then
        AHT:Print(AHT.L["mats_no_materials"]); return
    end

    local queue = {}
    for name in pairs(AHT.materials) do
        if AHT.matsSelected[name] ~= false then
            table.insert(queue, name)
        end
    end
    if #queue == 0 then
        AHT:Print(AHT.L["mats_no_selected"]); return
    end

    AHT.matsScanQueue         = queue
    AHT.matsScanQueueIdx      = 0
    AHT.matsScanMinPrices     = {}
    AHT.matsScanListingCounts = {}
    AHT.matsScanOffers        = {}
    AHT.matsScanState         = "waiting"
    AHT.matsScanTimer         = 0
    AHT.matsSentTimer         = 0

    AHT:Print(string.format(AHT.L["mats_scan_start"], #queue))
    if AHT.matsScanBtn then AHT.matsScanBtn:SetText(AHT.L["mats_cancel"]) end
    AHT:AdvanceMatsScanQueue()
end

function AHT:CancelMatsScan()
    if not AHT:IsMatScanning() then return end
    AHT:Print(AHT.L["mats_scan_cancelled"])
    AHT.matsScanState = "idle"
    if AHT.matsScanBtn then AHT.matsScanBtn:SetText(AHT.L["mats_button"]) end
    AHT:SaveDB()
end

function AHT:AdvanceMatsScanQueue()
    AHT.matsScanQueueIdx = AHT.matsScanQueueIdx + 1
    if AHT.matsScanQueueIdx > #AHT.matsScanQueue then
        AHT:OnMatsScanComplete(); return
    end
    AHT.matsCurrentItem  = AHT.matsScanQueue[AHT.matsScanQueueIdx]
    AHT.matsCurrentPage  = 0
    AHT.matsScanRetries  = 0
    AHT.matsScanState    = "waiting"
    AHT.matsScanTimer    = 0
    AHT.matsSentTimer    = 0
end

function AHT:OnUpdateMats(elapsed)
    if AHT.matsScanState == "waiting" then
        AHT.matsScanTimer = AHT.matsScanTimer + elapsed
        AHT.matsSentTimer = AHT.matsSentTimer + elapsed
        if AHT.matsSentTimer >= AHT.WAIT_TIMEOUT then
            AHT:Print(string.format(AHT.L["scan_timeout"], AHT.matsCurrentItem or "?"))
            AHT:AdvanceMatsScanQueue(); return
        end
        if AHT.matsScanTimer >= AHT.SCAN_DELAY then
            AHT.matsScanTimer = 0
            if CanSendAuctionQuery() then
                local _, ci, si = AHT:GetAuctionQueryFilters(
                    AHT.matsCurrentItem, AHT:GetMatCategoryId(AHT.matsCurrentItem))
                AHT.matsSentTimer = 0
                AHT.matsScanState = "sent"
                QueryAuctionItems(AHT.matsCurrentItem, nil, nil, nil, ci, si,
                    AHT.matsCurrentPage, nil, nil)
            end
        end
    elseif AHT.matsScanState == "sent" then
        AHT.matsSentTimer = AHT.matsSentTimer + elapsed
        if AHT.matsSentTimer >= AHT.SENT_TIMEOUT then
            AHT.matsSentTimer   = 0
            AHT.matsScanRetries = AHT.matsScanRetries + 1
            if AHT.matsScanRetries > AHT.MAX_RETRIES then
                AHT:Print(string.format(AHT.L["scan_timeout"], AHT.matsCurrentItem or "?"))
                AHT:AdvanceMatsScanQueue()
            else
                AHT.matsScanState = "waiting"
                AHT.matsScanTimer = 0
            end
        end
    end
end

function AHT:OnMatsAuctionListUpdate()
    if AHT.matsScanState ~= "sent" then return end
    AHT.matsSentTimer = 0
    local numItems = GetNumAuctionItems("list")
    local player   = UnitName("player")

    for i = 1, numItems do
        local name, _, count, _, _, _, _, _, buyoutPrice, _, _, _, _, owner, ownerFull, _, itemId =
            GetAuctionItemInfo("list", i)
        local isOwn = (owner == player) or (ownerFull and ownerFull:match("^" .. player))
        if AHT:NameMatches(name, AHT.matsCurrentItem)
           and buyoutPrice and buyoutPrice > 0
           and count and count > 0 and not isOwn then
            local key = AHT.matsCurrentItem
            local ppu = math.floor(buyoutPrice / count)
            if not AHT.matsScanMinPrices[key] or ppu < AHT.matsScanMinPrices[key] then
                AHT.matsScanMinPrices[key] = ppu
            end
            AHT.matsScanListingCounts[key] = (AHT.matsScanListingCounts[key] or 0) + 1
            if not AHT.matsScanOffers[key] then AHT.matsScanOffers[key] = {} end
            table.insert(AHT.matsScanOffers[key], { ppu = ppu, count = count, buyout = buyoutPrice })
            if itemId and itemId > 0 then
                AHT.nameToId[key] = itemId; AHT.idToName[itemId] = key
            end
        end
    end

    if numItems >= 50 then
        AHT.matsCurrentPage = AHT.matsCurrentPage + 1
        AHT.matsScanState   = "waiting"
        AHT.matsScanTimer   = 0
    else
        AHT:AdvanceMatsScanQueue()
    end
end

function AHT:OnMatsScanComplete()
    AHT.matsScanState = "idle"
    local now = time()
    for name, price in pairs(AHT.matsScanMinPrices) do
        AHT.prices[name]       = price
        AHT.priceUpdated[name] = now
        if not AHT.matsHistory[name] then AHT.matsHistory[name] = {} end
        local wa = AHT:CalcWeightedMatAverage(name, price)
        table.insert(AHT.matsHistory[name], { t = now, p = price, weighted_avg = wa })
        while #AHT.matsHistory[name] > 100 do table.remove(AHT.matsHistory[name], 1) end
    end
    for name, cnt in pairs(AHT.matsScanListingCounts) do
        AHT.listingCounts[name] = cnt
    end
    for _, item in ipairs(AHT.matsScanQueue) do
        if not AHT.matsScanListingCounts[item] then AHT.listingCounts[item] = 0 end
    end
    for name, offers in pairs(AHT.matsScanOffers) do
        AHT.matsOfferCache[name] = { t = now, offers = offers }
        AHT.allOffersCache[name] = { t = now, offers = offers }
    end
    AHT:SaveDB()
    AHT:CalculateMatsMargins()
    AHT:RefreshMatsUI()
    if AHT.matsBuyDialog and AHT.matsBuyDialog:IsVisible() then
        AHT:RefreshMatsBuyDialogAfterScan()
    end
    AHT:Print(string.format(AHT.L["mats_scan_complete"], AHT:TableCount(AHT.matsScanMinPrices)))
    if AHT.matsScanBtn then AHT.matsScanBtn:SetText(AHT.L["mats_button"]) end
end

-- ── Hilfsfunktionen ──────────────────────────────────────────
function AHT:SetScanButtonText(text)
    if AHT.scanButton then AHT.scanButton:SetText(text) end
end

function AHT:UpdateScanProgress()
    if ProjEP_AHT_UI and ProjEP_AHT_UI:IsVisible() then AHT:RefreshUI() end
end

-- RefreshAllUIs is defined in UI.lua

if AHT and AHT._loadStatus then
    AHT._loadStatus.scanner = true
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[AHT-DIAG]|r Scanner.lua OK")
    end
end
