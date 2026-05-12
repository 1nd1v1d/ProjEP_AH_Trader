-- ============================================================
-- ProjEP AH Trader - Buyer.lua
-- Kauft Zutaten aus dem AH fÃ¼r einen gewÃ¤hlten Trank/Glyph/Gem
-- WotLK 3.3.5 / Lua 5.1 (Project Epoch)
--
-- Ablauf:
--   1. Spieler wÃ¤hlt Rezept + Anzahl im Kaufdialog
--   2. Einkaufsliste berechnen (Vendor-Items ausgenommen)
--   3. Zweiphasig: Phase 1 = alle Seiten scannen, Angebote sammeln
--                  Phase 2 = gÃ¼nstigste Angebote der Reihe nach kaufen
--   4. Zusammenfassung im Chat
--
-- API: PlaceAuctionBid("list", index, buyoutPrice) = Sofortkauf
-- ============================================================

local AHT = PROJEP_AHT

local MIN_MARGIN = 0.10  -- 10% Mindestmarge nach Kauf

-- â”€â”€ Buyer-State â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
AHT.buyState        = "idle"     -- idle / searching / buying / done
AHT.buyRecipe       = nil        -- Das Ergebnis-Objekt
AHT.buyCount        = 0
AHT.buyList         = {}         -- { { name, totalNeeded, bought, maxPPU } }
AHT.buyListIdx      = 0
AHT.buyPage         = 0
AHT.buyTimer        = 0
AHT.buyLocked       = false
AHT.buyPendingOffer = nil
AHT.buyTotalSpent   = 0
AHT.buyItemsBought  = 0
AHT.buySentTimer    = 0
AHT.buyCollecting   = false
AHT.buyAllOffers    = {}
AHT.buyTargetPPU    = 0
AHT.buyLockTimer    = 0
AHT.buyRetries      = 0

local BUY_DELAY        = 0.4
local BUY_TIMEOUT      = 12.0
local BUY_WAIT_TIMEOUT = 30.0
local BUY_LOCK_TIMEOUT = 8.0
local BUY_MAX_RETRIES  = 3

-- â”€â”€ Maximalen StÃ¼ckpreis berechnen â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Garantiert mind. MIN_MARGIN nach dem Kauf (10%)
-- Formel: netIncome / (1 + MIN_MARGIN) = max Gesamtzutatenkosten
function AHT:CalcMaxPPU(recipe, reagentName, reagentCount)
    if not recipe or not recipe.sellPrice then return nil end

    local sellPrice  = recipe.sellPrice
    local provision  = math.floor(sellPrice * AHT.ahCutRate)
    local deposit    = AHT:CalcDeposit(recipe.name)
    local netIncome  = sellPrice - provision - deposit

    local maxIngredCost = math.floor(netIncome / (1 + MIN_MARGIN))

    local otherCost = 0
    for _, reag in ipairs(recipe.reagents) do
        if reag.name ~= reagentName then
            local price = AHT.vendorPrices[reag.name] or AHT.prices[reag.name]
            if price then
                otherCost = otherCost + price * reag.count
            end
        end
    end

    local budget = maxIngredCost - otherCost
    if budget <= 0 then return 0 end
    return math.floor(budget / reagentCount)
end

-- â”€â”€ Kauf starten â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
function AHT:StartBuy(recipe, count)
    local L = AHT.L
    if AHT.buyState ~= "idle" then
        AHT:Print(L["buy_already_running"]); return
    end
    if not AuctionFrame or not AuctionFrame:IsVisible() then
        AHT:Print(L["scan_ah_required"]); return
    end
    if not recipe.sellPrice or not recipe.profit or recipe.profit <= 0 then
        AHT:Print(string.format("|cffff4444Kein Verkaufspreis fÃ¼r '%s' bekannt.|r", recipe.name))
        return
    end

    AHT.buyRecipe      = recipe
    AHT.buyCount       = count
    AHT.buyTotalSpent  = 0
    AHT.buyItemsBought = 0
    AHT.buyLockTimer   = 0
    AHT.buyRetries     = 0

    -- Einkaufsliste aufbauen (nur AH-Items, Taschen-Inhalte abziehen)
    local list = {}
    for _, reag in ipairs(recipe.reagents) do
        if not AHT:IsVendorItem(reag.name) then
            local totalNeeded   = reag.count * count
            local inBags        = AHT:CountItemInBags(reag.name)
            local recipeSession = AHT.sessionBought[recipe.name] or {}
            local prevBought    = recipeSession[reag.name] or 0
            local actualNeeded  = totalNeeded - inBags - prevBought

            if actualNeeded > 0 then
                local maxPPU = AHT:CalcMaxPPU(recipe, reag.name, reag.count)
                table.insert(list, {
                    name        = reag.name,
                    totalNeeded = actualNeeded,
                    bought      = 0,
                    maxPPU      = maxPPU or 0,
                    scanPPU     = AHT.prices[reag.name] or 0,
                })
            else
                local haveTotal = inBags + prevBought
                AHT:Print(string.format(L["buy_in_bags_skip"],
                    reag.name, haveTotal, totalNeeded))
            end
        end
    end

    if #list == 0 then
        -- Alle aus Taschen/Vendor â†’ Info ausgeben
        local vendorList = {}
        for _, reag in ipairs(recipe.reagents) do
            if AHT:IsVendorItem(reag.name) then
                table.insert(vendorList, reag.count * count .. "x " .. reag.name)
            end
        end
        if #vendorList > 0 then
            AHT:Print(string.format(L["buy_vendor_items"], table.concat(vendorList, ", ")))
        else
            AHT:Print(L["buy_in_bags_skip"]:format(recipe.name, count, count))
        end
        return
    end

    AHT.buyList    = list
    AHT.buyListIdx = 0

    AHT:Print(string.format(L["buy_starting"], count, recipe.name))
    for _, item in ipairs(list) do
        AHT:Print(string.format("  %dx %s (max %s/Stk)",
            item.totalNeeded, item.name, AHT:FormatMoney(item.maxPPU)))
    end

    AHT:AdvanceBuyQueue()
end

-- â”€â”€ Buy-Queue vorrÃ¼cken â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
function AHT:AdvanceBuyQueue()
    AHT.buyListIdx = AHT.buyListIdx + 1

    if AHT.buyListIdx > #AHT.buyList then
        AHT:OnBuyComplete(); return
    end

    local item = AHT.buyList[AHT.buyListIdx]
    if item.bought >= item.totalNeeded then
        AHT:AdvanceBuyQueue(); return
    end

    AHT.buyPage       = 0
    AHT.buyState      = "searching"
    AHT.buyTimer      = 0
    AHT.buySentTimer  = 0
    AHT.buyLocked     = false
    AHT.buyLockTimer  = 0
    AHT.buyCollecting = true
    AHT.buyAllOffers  = {}
    AHT.buyTargetPPU  = 0
end

-- â”€â”€ OnUpdate fÃ¼r Buy-Zustandsautomat â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
function AHT:OnBuyUpdate(elapsed)
    if AHT.buyState == "idle" or AHT.buyState == "done" then return end

    if AHT.buyState == "searching" then
        AHT.buyTimer     = AHT.buyTimer + elapsed
        AHT.buySentTimer = AHT.buySentTimer + elapsed

        if AHT.buySentTimer >= BUY_WAIT_TIMEOUT then
            AHT:Print(L and L["buy_cancelled"] or "Kauf: Timeout")
            AHT:AdvanceBuyQueue(); return
        end

        if AHT.buyTimer >= BUY_DELAY then
            AHT.buyTimer = 0
            if CanSendAuctionQuery() then
                local item = AHT.buyList[AHT.buyListIdx]
                local _, ci, si = AHT:GetAuctionQueryFilters(item.name)
                AHT.buySentTimer = 0
                AHT.buyState     = "buying"
                QueryAuctionItems(item.name, nil, nil, nil, ci, si, AHT.buyPage, nil, nil)
            end
        end

    elseif AHT.buyState == "buying" then
        if AHT.buyLocked then
            AHT.buyLockTimer = AHT.buyLockTimer + elapsed
            if AHT.buyLockTimer >= BUY_LOCK_TIMEOUT then
                AHT.buyRetries = AHT.buyRetries + 1
                if AHT.buyRetries >= BUY_MAX_RETRIES then
                    AHT:Print("|cffff4444Kauf: Gebot wiederholt blockiert (Interface action failed?). Kauf abgebrochen.|r")
                    AHT:Print("|cffaaaaaa Tipp: AH schliessen und neu oeffnen, dann erneut versuchen.|r")
                    AHT:CancelBuy()
                else
                    AHT:Print(string.format("|cffff9900Kauf: Gebot ohne Rueckmeldung, retry %d/%d...|r",
                        AHT.buyRetries, BUY_MAX_RETRIES))
                    AHT.buyLocked       = false
                    AHT.buyLockTimer    = 0
                    AHT.buyPendingOffer = nil
                    AHT.buyState        = "searching"
                    AHT.buyTimer        = 0
                    AHT.buySentTimer    = 0
                end
            end
        else
            AHT.buyLockTimer = 0
            AHT.buySentTimer = AHT.buySentTimer + elapsed
            if AHT.buySentTimer >= BUY_TIMEOUT then
                AHT:AdvanceBuyQueue()
            end
        end
    end
end

-- â”€â”€ AH-Ergebnisse verarbeiten (Kauf-Modus) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Phase 1 (buyCollecting):  Alle Seiten scannen, Angebote sammeln
-- Phase 2 (!buyCollecting): GÃ¼nstigste gezielt kaufen
function AHT:OnBuyAuctionListUpdate()
    if AHT.buyState ~= "buying" then return end
    if AHT.buyLocked then return end

    local item = AHT.buyList[AHT.buyListIdx]
    if not item then return end

    local numItems = GetNumAuctionItems("list")
    local player   = UnitName("player")

    if AHT.buyCollecting then
        -- â”€â”€ Phase 1: Angebote sammeln â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        for i = 1, numItems do
            local name, _, count, _, _, _, _, _, buyoutPrice, _, _, _, _, owner, ownerFull =
                GetAuctionItemInfo("list", i)

            local isOwn = (owner == player)
                or (ownerFull and ownerFull:match("^" .. player))

            if AHT:NameMatches(name, item.name)
               and buyoutPrice and buyoutPrice > 0
               and count and count > 0
               and not isOwn then
                local ppu = math.floor(buyoutPrice / count)
                if ppu <= item.maxPPU then
                    table.insert(AHT.buyAllOffers, {
                        count  = count,
                        buyout = buyoutPrice,
                        ppu    = ppu,
                    })
                end
            end
        end

        if numItems >= 50 then
            -- Weitere Seiten scannen
            AHT.buyPage  = AHT.buyPage + 1
            AHT.buyState = "searching"
            AHT.buyTimer = 0
        else
            -- Alle Seiten gescannt â†’ auswerten
            table.sort(AHT.buyAllOffers, function(a, b) return a.ppu < b.ppu end)

            if #AHT.buyAllOffers == 0 then
                AHT:Print(string.format("|cffff4444Keine Angebote fÃ¼r '%s' (unter Preislimit).|r", item.name))
                AHT:AdvanceBuyQueue(); return
            end

            -- Optimalen Ziel-PPU berechnen
            local needed     = item.totalNeeded - item.bought
            local cumCount   = 0
            AHT.buyTargetPPU = AHT.buyAllOffers[#AHT.buyAllOffers].ppu
            for _, o in ipairs(AHT.buyAllOffers) do
                cumCount = cumCount + o.count
                if cumCount >= needed then
                    AHT.buyTargetPPU = o.ppu; break
                end
            end

            AHT:Print(string.format("|cff00ccff%s:|r %d Angebote, gÃ¼nstigste %s, Ziel-PPU %s",
                item.name, #AHT.buyAllOffers,
                AHT:FormatMoney(AHT.buyAllOffers[1].ppu),
                AHT:FormatMoney(AHT.buyTargetPPU)))

            -- Phase 2: ab Seite 0 kaufen
            AHT.buyCollecting = false
            AHT.buyPage       = 0
            AHT.buyState      = "searching"
            AHT.buyTimer      = 0
        end

    else
        -- â”€â”€ Phase 2: Kaufen â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        local offers = {}
        for i = 1, numItems do
            local name, _, count, _, _, _, _, _, buyoutPrice, _, _, _, _, owner, ownerFull =
                GetAuctionItemInfo("list", i)

            local isOwn = (owner == player)
                or (ownerFull and ownerFull:match("^" .. player))

            if AHT:NameMatches(name, item.name)
               and buyoutPrice and buyoutPrice > 0
               and count and count > 0
               and not isOwn then
                local ppu = math.floor(buyoutPrice / count)
                if ppu <= item.maxPPU and ppu <= AHT.buyTargetPPU then
                    table.insert(offers, {
                        index  = i,
                        count  = count,
                        buyout = buyoutPrice,
                        ppu    = ppu,
                    })
                end
            end
        end

        table.sort(offers, function(a, b) return a.ppu < b.ppu end)

        local stillNeeded    = item.totalNeeded - item.bought
        local boughtThisPage = false

        for _, offer in ipairs(offers) do
            if stillNeeded <= 0 then break end

            -- GoldprÃ¼fung
            if GetMoney() < offer.buyout then
                AHT:Print(AHT.L["buy_not_enough_gold"])
                AHT:CancelBuy(); return
            end

            -- Kauf auslÃ¶sen (max 1 pro Zyklus)
            AHT.buyLocked = true
            AHT.buyPendingOffer = {
                count  = offer.count,
                name   = item.name,
                buyout = offer.buyout,
                ppu    = offer.ppu,
                idx    = AHT.buyListIdx,
            }
            PlaceAuctionBid("list", offer.index, offer.buyout)
            boughtThisPage = true
            break
        end

        if not boughtThisPage then
            if numItems >= 50 then
                AHT.buyPage  = AHT.buyPage + 1
                AHT.buyState = "searching"
                AHT.buyTimer = 0
            else
                if item.bought < item.totalNeeded then
                    AHT:Print(string.format("|cffff9900Nur %d/%d %s beschafft.|r",
                        item.bought, item.totalNeeded, item.name))
                end
                AHT:AdvanceBuyQueue()
            end
        end
    end
end

-- â”€â”€ ERR_AUCTION_BID_PLACED Handler â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
function AHT:OnBidPlaced()
    -- Mats-Buy hat Vorrang wenn aktiv
    if AHT.matsBuyState and AHT.matsBuyState ~= "idle" and AHT.matsBuyLocked then
        AHT:OnMatsBidPlaced(); return
    end

    AHT.buyLocked    = false
    AHT.buyLockTimer = 0
    AHT.buyRetries   = 0

    local pending = AHT.buyPendingOffer
    if pending then
        local item = AHT.buyList[pending.idx]
        if item then
            item.bought = item.bought + pending.count
        end
        AHT.buyTotalSpent  = AHT.buyTotalSpent  + pending.buyout
        AHT.buyItemsBought = AHT.buyItemsBought + pending.count

        -- Session-GedÃ¤chtnis
        local recipeKey = AHT.buyRecipe and AHT.buyRecipe.name or "_unknown_"
        AHT.sessionBought[recipeKey] = AHT.sessionBought[recipeKey] or {}
        AHT.sessionBought[recipeKey][pending.name] =
            (AHT.sessionBought[recipeKey][pending.name] or 0) + pending.count

        AHT:Print(string.format(L and L["buy_purchased"] or "Gekauft: %dx %s fÃ¼r %s",
            pending.count, pending.name, AHT:FormatMoney(pending.buyout)))

        if item and item.bought >= item.totalNeeded then
            AHT:AdvanceBuyQueue()
        else
            AHT.buyState     = "searching"
            AHT.buyTimer     = 0
            AHT.buySentTimer = 0
        end

        AHT.buyPendingOffer = nil
    end
end

-- â”€â”€ Kauf abbrechen â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
function AHT:CancelBuy()
    if AHT.buyState == "idle" then
        AHT:Print(AHT.L["buy_no_active"]); return
    end
    AHT:Print(AHT.L["buy_cancelled"])
    AHT:OnBuyComplete()
end

-- â”€â”€ Kauf abgeschlossen â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
function AHT:OnBuyComplete()
    AHT.buyState        = "idle"
    AHT.buyLocked       = false
    AHT.buyLockTimer    = 0
    AHT.buyRetries      = 0
    AHT.buyCollecting   = false
    AHT.buyAllOffers    = {}
    AHT.buyPendingOffer = nil

    local recipe = AHT.buyRecipe
    if not recipe then return end

    local L = AHT.L
    AHT:Print(string.format(L["buy_complete"], AHT.buyItemsBought))
    for _, item in ipairs(AHT.buyList) do
        local color = item.bought >= item.totalNeeded and "|cff00ff00" or "|cffff4444"
        AHT:Print("  " .. color .. item.bought .. "/" .. item.totalNeeded .. "|r " .. item.name)
    end

    -- Vendor-Items auffÃ¼hren
    local vendorList = {}
    for _, reag in ipairs(recipe.reagents) do
        if AHT:IsVendorItem(reag.name) then
            table.insert(vendorList, reag.count * AHT.buyCount .. "x " .. reag.name)
        end
    end
    if #vendorList > 0 then
        AHT:Print(string.format(L["buy_vendor_items"], table.concat(vendorList, ", ")))
    end

    AHT.buyRecipe = nil
end

-- â”€â”€ Prueft ob Kauf lÃ¤uft â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
function AHT:IsBuying()
    return AHT.buyState ~= "idle"
end

-- â”€â”€ Kaufdialog: Angebote vorbereiten (fÃ¼r UI-Anzeige) â”€â”€â”€â”€â”€â”€â”€â”€
-- Gibt eine nach ppu sortierte Angebotsliste zurÃ¼ck
-- und berechnet Einkaufsplan fÃ¼r 'needed' StÃ¼ck
function AHT:BuildBuyPlan(itemName, needed)
    local cache = AHT.allOffersCache[itemName] or AHT.matsOfferCache[itemName]
    if not cache or not cache.offers or #cache.offers == 0 then
        return nil, nil
    end

    -- Nach ppu sortieren
    local sorted = {}
    for _, o in ipairs(cache.offers) do
        table.insert(sorted, { ppu = o.ppu, count = o.count, buyout = o.buyout })
    end
    table.sort(sorted, function(a, b) return a.ppu < b.ppu end)

    -- Einkaufsplan erstellen
    local plan        = {}
    local remaining   = needed
    local totalCost   = 0
    local totalCount  = 0
    for _, o in ipairs(sorted) do
        if remaining <= 0 then break end
        local take     = math.min(o.count, remaining)
        local cost     = math.floor(o.buyout / o.count * take)
        table.insert(plan, { count = take, ppu = o.ppu, cost = cost })
        totalCost  = totalCost  + cost
        totalCount = totalCount + take
        remaining  = remaining  - take
    end

    return plan, totalCost, totalCount
end

-- â”€â”€ Mats-KÃ¤ufer (fÃ¼r Mats-Fenster-Kaufdialog) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Vereinfachte Version: kauft ein einzelnes Material in der angegeben Menge

AHT.matsBuyState    = "idle"
AHT.matsBuyItem     = nil
AHT.matsBuyNeeded   = 0
AHT.matsBuyBought   = 0
AHT.matsBuyMaxPPU   = 0
AHT.matsBuyPage     = 0
AHT.matsBuyTimer    = 0
AHT.matsBuySent     = 0
AHT.matsBuyLocked   = false
AHT.matsBuyLockTimer = 0   -- wie lange schon locked
AHT.matsBuyRetries  = 0    -- Retry-Zaehler
AHT.matsBuyPending  = nil
AHT.matsBuySpent    = 0
AHT.matsBuyCollecting = false
AHT.matsBuyAllOffers  = {}
AHT.matsBuyTargetPPU  = 0

function AHT:IsMatsBuying()
    return AHT.matsBuyState ~= "idle"
end

function AHT:StartMatsBuy(itemName, needed, maxPPU)
    local L = AHT.L
    if AHT:IsMatsBuying() then AHT:Print(L["buy_already_running"]); return end
    if not AuctionFrame or not AuctionFrame:IsVisible() then
        AHT:Print(L["scan_ah_required"]); return
    end
    if not itemName or needed <= 0 then return end

    AHT.matsBuyState      = "searching"
    AHT.matsBuyItem       = itemName
    AHT.matsBuyNeeded     = needed
    AHT.matsBuyBought     = 0
    AHT.matsBuyMaxPPU     = maxPPU or 999999999
    AHT.matsBuyPage       = 0
    AHT.matsBuyTimer      = 0
    AHT.matsBuySent       = 0
    AHT.matsBuyLocked     = false
    AHT.matsBuyLockTimer  = 0
    AHT.matsBuyRetries    = 0
    AHT.matsBuyPending    = nil
    AHT.matsBuySpent      = 0
    AHT.matsBuyCollecting = true
    AHT.matsBuyAllOffers  = {}
    AHT.matsBuyTargetPPU  = 0

    AHT:Print(string.format(L["buy_starting"], needed, itemName))
end

function AHT:CancelMatsBuy(silent)
    if AHT.matsBuyState == "idle" then return end
    AHT.matsBuyState     = "idle"
    AHT.matsBuyLocked    = false
    AHT.matsBuyLockTimer = 0
    AHT.matsBuyRetries   = 0
    AHT.matsBuyPending   = nil
    if not silent then AHT:Print(AHT.L["buy_cancelled"]) end
end

function AHT:OnMatsBuyUpdate(elapsed)
    if AHT.matsBuyState == "idle" then return end

    if AHT.matsBuyState == "searching" then
        AHT.matsBuyTimer = AHT.matsBuyTimer + elapsed
        AHT.matsBuySent  = AHT.matsBuySent  + elapsed

        if AHT.matsBuySent >= BUY_WAIT_TIMEOUT then
            AHT:Print("|cffff4444Mats-Kauf: Timeout.|r")
            AHT:CancelMatsBuy(true); return
        end

        if AHT.matsBuyTimer >= BUY_DELAY then
            AHT.matsBuyTimer = 0
            if CanSendAuctionQuery() then
                local _, ci, si = AHT:GetAuctionQueryFilters(AHT.matsBuyItem)
                AHT.matsBuySent    = 0
                AHT.matsBuyState   = "buying"
                QueryAuctionItems(AHT.matsBuyItem, nil, nil, nil, ci, si, AHT.matsBuyPage, nil, nil)
            end
        end

    elseif AHT.matsBuyState == "buying" then
        -- Lock-Timer läuft immer: erkennt hängengebliebene Gebote
        if AHT.matsBuyLocked then
            AHT.matsBuyLockTimer = AHT.matsBuyLockTimer + elapsed
            if AHT.matsBuyLockTimer >= 8.0 then
                AHT.matsBuyRetries = AHT.matsBuyRetries + 1
                if AHT.matsBuyRetries >= 3 then
                    AHT:Print("|cffff4444Mats-Kauf: Gebot wiederholt blockiert (Interface action failed?). Kauf abgebrochen.|r")
                    AHT:Print("|cffaaaaaa Tipp: AH schliessen und neu öffnen, dann erneut versuchen.|r")
                    AHT:CancelMatsBuy(true)
                else
                    AHT:Print(string.format("|cffff9900Mats-Kauf: Gebot ohne Rückmeldung, retry %d/3...|r", AHT.matsBuyRetries))
                    AHT.matsBuyLocked    = false
                    AHT.matsBuyLockTimer = 0
                    AHT.matsBuyPending   = nil
                    AHT.matsBuyState     = "searching"
                    AHT.matsBuyTimer     = 0
                    AHT.matsBuySent      = 0
                end
            end
        else
            AHT.matsBuyLockTimer = 0
            AHT.matsBuySent = AHT.matsBuySent + elapsed
            if AHT.matsBuySent >= BUY_TIMEOUT then
                AHT:Print("|cffff4444Mats-Kauf: Timeout.|r")
                AHT:CancelMatsBuy(true)
            end
        end
    end
end

function AHT:OnMatsBuyAuctionListUpdate()
    if AHT.matsBuyState ~= "buying" then return end
    if AHT.matsBuyLocked then return end

    local numItems = GetNumAuctionItems("list")
    local player   = UnitName("player")

    if AHT.matsBuyCollecting then
        for i = 1, numItems do
            local name, _, count, _, _, _, _, _, buyoutPrice, _, _, _, _, owner, ownerFull =
                GetAuctionItemInfo("list", i)

            local isOwn = (owner == player) or (ownerFull and ownerFull:match("^" .. player))

            if AHT:NameMatches(name, AHT.matsBuyItem)
               and buyoutPrice and buyoutPrice > 0
               and count and count > 0 and not isOwn then
                local ppu = math.floor(buyoutPrice / count)
                if ppu <= AHT.matsBuyMaxPPU then
                    table.insert(AHT.matsBuyAllOffers, {
                        count  = count,
                        buyout = buyoutPrice,
                        ppu    = ppu,
                    })
                end
            end
        end

        if numItems >= 50 then
            AHT.matsBuyPage  = AHT.matsBuyPage + 1
            AHT.matsBuyState = "searching"
            AHT.matsBuyTimer = 0
        else
            table.sort(AHT.matsBuyAllOffers, function(a, b) return a.ppu < b.ppu end)
            if #AHT.matsBuyAllOffers == 0 then
                AHT:Print("|cffff4444Keine Angebote fÃ¼r " .. AHT.matsBuyItem .. ".|r")
                AHT:CancelMatsBuy(true); return
            end
            local needed  = AHT.matsBuyNeeded - AHT.matsBuyBought
            local cum     = 0
            AHT.matsBuyTargetPPU = AHT.matsBuyAllOffers[#AHT.matsBuyAllOffers].ppu
            for _, o in ipairs(AHT.matsBuyAllOffers) do
                cum = cum + o.count
                if cum >= needed then
                    AHT.matsBuyTargetPPU = o.ppu; break
                end
            end
            AHT.matsBuyCollecting = false
            AHT.matsBuyPage       = 0
            AHT.matsBuyState      = "searching"
            AHT.matsBuyTimer      = 0
        end
    else
        local offers = {}
        for i = 1, numItems do
            local name, _, count, _, _, _, _, _, buyoutPrice, _, _, _, _, owner, ownerFull =
                GetAuctionItemInfo("list", i)

            local isOwn = (owner == player) or (ownerFull and ownerFull:match("^" .. player))

            if AHT:NameMatches(name, AHT.matsBuyItem)
               and buyoutPrice and buyoutPrice > 0
               and count and count > 0 and not isOwn then
                local ppu = math.floor(buyoutPrice / count)
                if ppu <= AHT.matsBuyMaxPPU and ppu <= AHT.matsBuyTargetPPU then
                    table.insert(offers, { index = i, count = count, buyout = buyoutPrice, ppu = ppu })
                end
            end
        end

        table.sort(offers, function(a, b) return a.ppu < b.ppu end)

        local stillNeeded = AHT.matsBuyNeeded - AHT.matsBuyBought
        local bought = false

        for _, offer in ipairs(offers) do
            if stillNeeded <= 0 then break end
            if GetMoney() < offer.buyout then
                AHT:Print(AHT.L["buy_not_enough_gold"])
                AHT:CancelMatsBuy(true); return
            end
            AHT.matsBuyLocked    = true
            AHT.matsBuyLockTimer = 0
            AHT.matsBuySent      = 0
            AHT.matsBuyPending = {
                count  = offer.count,
                buyout = offer.buyout,
                ppu    = offer.ppu,
            }
            PlaceAuctionBid("list", offer.index, offer.buyout)
            bought = true
            break
        end

        if not bought then
            if numItems >= 50 then
                AHT.matsBuyPage  = AHT.matsBuyPage + 1
                AHT.matsBuyState = "searching"
                AHT.matsBuyTimer = 0
            else
                if AHT.matsBuyBought > 0 then
                    AHT:Print(string.format(L["buy_complete"], AHT.matsBuyBought))
                end
                AHT:CancelMatsBuy(true)
            end
        end
    end
end

function AHT:OnMatsBidPlaced()
    AHT.matsBuyLocked    = false
    AHT.matsBuyLockTimer = 0
    AHT.matsBuyRetries   = 0
    local pending = AHT.matsBuyPending
    if pending then
        AHT.matsBuyBought = AHT.matsBuyBought + pending.count
        AHT.matsBuySpent  = AHT.matsBuySpent  + pending.buyout
        AHT:Print(string.format(L and L["buy_purchased"] or "Gekauft: %dx %s fÃ¼r %s",
            pending.count, AHT.matsBuyItem, AHT:FormatMoney(pending.buyout)))
        AHT.matsBuyPending = nil

        if AHT.matsBuyBought >= AHT.matsBuyNeeded then
            AHT:Print(string.format(L["buy_complete"], AHT.matsBuyBought))
            AHT:CancelMatsBuy(true)
        else
            AHT.matsBuyState = "searching"
            AHT.matsBuyTimer = 0
            AHT.matsBuySent  = 0
        end
    end
end

-- â”€â”€ AH-Ergebnis-Router fÃ¼r Buyer â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Wird von Core aus AUCTION_ITEM_LIST_UPDATE aufgerufen (falls zutreffend)
function AHT:OnBuyerAuctionListUpdate()
    if AHT.matsBuyState ~= "idle" and AHT.matsBuyState == "buying" then
        AHT:OnMatsBuyAuctionListUpdate()
    elseif AHT.buyState == "buying" then
        AHT:OnBuyAuctionListUpdate()
    end
end

if AHT and AHT._loadStatus then
    AHT._loadStatus.buyer = true
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[AHT-DIAG]|r Buyer.lua OK")
    end
end
