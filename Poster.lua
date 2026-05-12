-- ============================================================
-- ProjEP AH Trader - Poster.lua
-- Postet hergestellte Items (Tränke, Glyphen, Gems) ins AH
-- WotLK 3.3.5 / Lua 5.1 (Project Epoch)
--
-- Ablauf:
--   1. Spieler wählt Item im Ergebnisfenster (Shift+Rechtsklick)
--   2. Addon findet alle Stacks in den Taschen
--   3. Berechnet Undercut-Preis (1c unter günstigstem AH-Angebot)
--   4. Postet einen Stack nach dem anderen
--   5. Zusammenfassung im Chat
--
-- API: PickupContainerItem → ClickAuctionSellItemButton → StartAuction
-- GetAuctionDeposit(duration, maxStack, numStacks) – WotLK exakt
-- ============================================================

local AHT = PROJEP_AHT

-- ── Poster-State ─────────────────────────────────────────────
AHT.postState       = "idle"     -- idle / splitting / split_wait / placing / confirming / done
AHT.postRecipeName  = nil
AHT.postStacks      = {}         -- { count1, count2, ... }
AHT.postStackIdx    = 0
AHT.postPrice       = 0          -- Buyout pro Stück (Kupfer)
AHT.postTimer       = 0
AHT.postTotalPosted = 0
AHT.postTotalStacks = 0
AHT.postDuration    = 2          -- 1=12h 2=24h 3=48h
AHT.postStackSize   = 1
AHT.postSplitTarget = nil
AHT.postSplitExpect = 0
AHT.postReadySlot   = nil

-- Preis-Prüfung vor dem Posten
AHT.postPriceCheck = nil

local POST_DELAY  = 0.5
local SPLIT_POLL  = 0.1

-- ── Optimalen Post-Preis berechnen ───────────────────────────
-- Undercut: 1c unter dem günstigsten AH-Preis/Stück
-- Minimum: Zutatenkosten × 1.05 (5% Aufschlag)
-- Fallback (kein AH-Preis): × 1.20
function AHT:CalcPostPrice(recipe)
    local currentAH  = AHT.prices[recipe.name]
    local ingredCost = recipe.ingredCost or 0

    local minPrice = math.floor(ingredCost * 1.05)
    if minPrice < 1 then minPrice = 1 end

    if currentAH and currentAH > 0 then
        local undercut = currentAH - AHT.UNDERCUT
        return undercut >= minPrice and undercut or minPrice
    else
        local markup = math.floor(ingredCost * 1.20)
        return markup >= minPrice and markup or minPrice
    end
end

-- ── Posting-Plan erstellen ────────────────────────────────────
function AHT:BuildPostPlan(totalCount, stackSize)
    local plan = {}
    local remaining = totalCount
    while remaining > 0 do
        local take = math.min(remaining, stackSize)
        table.insert(plan, take)
        remaining = remaining - take
    end
    return plan
end

-- ── Taschensuche ─────────────────────────────────────────────
function AHT:FindFirstBagStack(itemName, minCount)
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local name = link:match("%[(.-)%]")
                if name == itemName then
                    local _, count = GetContainerItemInfo(bag, slot)
                    count = count or 1
                    if not minCount or count >= minCount then
                        return bag, slot, count
                    end
                end
            end
        end
    end
    return nil, nil, 0
end

function AHT:FindExactBagStack(itemName, exactCount)
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local name = link:match("%[(.-)%]")
                if name == itemName then
                    local _, count = GetContainerItemInfo(bag, slot)
                    if (count or 1) == exactCount then
                        return bag, slot
                    end
                end
            end
        end
    end
    return nil, nil
end

function AHT:FindEmptyBagSlot()
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            if not GetContainerItemLink(bag, slot) then
                return bag, slot
            end
        end
    end
    return nil, nil
end

-- ── Posting starten ──────────────────────────────────────────
function AHT:StartPost(recipeName, recipe, stackSize, maxStacks)
    local L = AHT.L
    if AHT.postState ~= "idle" then
        AHT:Print(L["post_cancelled"]); return
    end
    if not AuctionFrame or not AuctionFrame:IsVisible() then
        AHT:Print(L["scan_ah_required"]); return
    end

    local totalCount = AHT:CountItemInBags(recipeName)
    if totalCount == 0 then
        AHT:Print(string.format("|cffff4444Keine %s in den Taschen.|r", recipeName))
        return
    end

    local plan = AHT:BuildPostPlan(totalCount, stackSize or 1)
    if maxStacks and maxStacks > 0 and #plan > maxStacks then
        local limited = {}
        for i = 1, maxStacks do limited[i] = plan[i] end
        plan = limited
    end

    local price = AHT:CalcPostPrice(recipe)

    AHT.postRecipeName  = recipeName
    AHT.postStacks      = plan
    AHT.postStackIdx    = 0
    AHT.postPrice       = price
    AHT.postStackSize   = stackSize or 1
    AHT.postTotalPosted = 0
    AHT.postTotalStacks = 0
    AHT.postTimer       = 0

    AHT:Print(string.format(L["post_starting"], totalCount, recipeName))
    AHT:AdvancePostQueue()
end

-- ── Post-Queue vorrücken ─────────────────────────────────────
function AHT:AdvancePostQueue()
    AHT.postStackIdx = AHT.postStackIdx + 1

    if AHT.postStackIdx > #AHT.postStacks then
        AHT:OnPostComplete(); return
    end

    AHT.postReadySlot   = nil
    AHT.postSplitTarget = nil
    AHT.postSplitExpect = 0
    AHT.postState       = "splitting"
    AHT.postTimer       = 0
end

-- ── OnUpdate für Post-Zustandsautomat ────────────────────────
function AHT:OnPostUpdate(elapsed)
    if AHT.postState == "idle" or AHT.postState == "done" then
        -- Preis-Prüfung verarbeiten
        local pc = AHT.postPriceCheck
        if pc then
            if pc.state == "waiting" then
                pc.timer    = pc.timer + elapsed
                pc.sentTimer = (pc.sentTimer or 0) + elapsed
                if pc.sentTimer >= 30 then
                    -- Timeout
                    AHT.postPriceCheck = nil
                elseif pc.timer >= 0.3 then
                    pc.timer = 0
                    if CanSendAuctionQuery() then
                        local _, ci, si = AHT:GetAuctionQueryFilters(pc.name)
                        pc.state     = "sent"
                        pc.sentTimer = 0
                        QueryAuctionItems(pc.name, nil, nil, nil, ci, si, pc.page, nil, nil)
                    end
                end
            elseif pc.state == "sent" then
                pc.sentTimer = (pc.sentTimer or 0) + elapsed
                if pc.sentTimer >= 15 then
                    AHT.postPriceCheck = nil
                end
            end
        end
        if AHT.postState == "idle" then return end
    end

    if AHT.postState == "splitting" then
        AHT.postTimer = AHT.postTimer + elapsed
        if AHT.postTimer < POST_DELAY then return end
        AHT.postTimer = 0

        local wantCount = AHT.postStacks[AHT.postStackIdx]
        if not wantCount then AHT:AdvancePostQueue(); return end

        -- Exakter Stack vorhanden?
        local eBag, eSlot = AHT:FindExactBagStack(AHT.postRecipeName, wantCount)
        if eBag then
            AHT.postReadySlot = { eBag, eSlot }
            AHT.postState     = "placing"
            AHT.postTimer     = 0
            return
        end

        -- Stack mit mindestens wantCount
        local bag, slot, currentCount = AHT:FindFirstBagStack(AHT.postRecipeName, wantCount)
        if not bag then
            -- Kleinen Stack direkt posten
            bag, slot, currentCount = AHT:FindFirstBagStack(AHT.postRecipeName)
            if not bag then AHT:AdvancePostQueue(); return end
            AHT.postReadySlot = { bag, slot }
            AHT.postState     = "placing"
            AHT.postTimer     = 0
            return
        end

        if currentCount == wantCount then
            AHT.postReadySlot = { bag, slot }
            AHT.postState     = "placing"
            AHT.postTimer     = 0
            return
        end

        -- Splitten: leeren Slot suchen
        local emptyBag, emptySlot = AHT:FindEmptyBagSlot()
        if not emptyBag then
            AHT.postReadySlot = { bag, slot }
            AHT.postState     = "placing"
            AHT.postTimer     = 0
            return
        end

        ClearCursor()
        SplitContainerItem(bag, slot, wantCount)
        PickupContainerItem(emptyBag, emptySlot)
        ClearCursor()

        AHT.postSplitTarget  = { emptyBag, emptySlot }
        AHT.postSplitExpect  = wantCount
        AHT.postState        = "split_wait"
        AHT.postTimer        = 0
        AHT.postSplitTimeout = 0

    elseif AHT.postState == "split_wait" then
        AHT.postTimer        = AHT.postTimer        + elapsed
        AHT.postSplitTimeout = AHT.postSplitTimeout + elapsed

        if AHT.postTimer >= SPLIT_POLL then
            AHT.postTimer = 0
            local tBag  = AHT.postSplitTarget[1]
            local tSlot = AHT.postSplitTarget[2]
            local _, count = GetContainerItemInfo(tBag, tSlot)
            if count and count == AHT.postSplitExpect then
                AHT.postReadySlot = { tBag, tSlot }
                AHT.postState     = "placing"
                AHT.postTimer     = 0
            elseif AHT.postSplitTimeout > 3.0 then
                if count and count > 0 then
                    AHT.postReadySlot = { tBag, tSlot }
                    AHT.postState     = "placing"
                    AHT.postTimer     = 0
                else
                    AHT:AdvancePostQueue()
                end
            end
        end

    elseif AHT.postState == "placing" then
        local rBag  = AHT.postReadySlot[1]
        local rSlot = AHT.postReadySlot[2]

        ClearCursor()
        ClickAuctionSellItemButton()
        ClearCursor()
        PickupContainerItem(rBag, rSlot)
        ClickAuctionSellItemButton()
        ClearCursor()

        AHT.postState = "confirming"
        AHT.postTimer = 0

    elseif AHT.postState == "confirming" then
        AHT.postTimer = AHT.postTimer + elapsed
        if AHT.postTimer < 0.2 then return end

        -- Polling: ist das korrekte Item im Sell-Slot?
        local name = GetAuctionSellItemInfo()
        if name and AHT:NameMatches(name, AHT.postRecipeName) then
            AHT:DoStartAuction()
            return
        end

        if AHT.postTimer >= 3.0 then
            AHT:Print(string.format("|cffff4444Falsches Item im Sell-Slot: %s|r", name or "?"))
            ClearCursor()
            AHT:AdvancePostQueue()
        end
    end
end

-- ── Auktion tatsächlich starten ──────────────────────────────
function AHT:DoStartAuction()
    local wantCount = AHT.postStacks[AHT.postStackIdx]
    if not wantCount then AHT:AdvancePostQueue(); return end

    local name, _, count = GetAuctionSellItemInfo()
    if not name or name ~= AHT.postRecipeName then
        AHT:Print(string.format("|cffff4444Sell-Slot: %s erwartet, %s gefunden.|r",
            AHT.postRecipeName, name or "?"))
        ClearCursor()
        AHT:AdvancePostQueue(); return
    end

    count = count or 1
    local startPrice = AHT.postPrice * count
    local buyout     = AHT.postPrice * count

    -- Deposit: WotLK API (GetAuctionDeposit) wenn verfügbar
    local deposit
    if GetAuctionDeposit then
        deposit = GetAuctionDeposit(AHT.postDuration, count, 1) or 0
    else
        -- Fallback-Schätzung
        local _, _, _, _, _, _, _, _, _, _, vendorSell = GetItemInfo(AHT.postRecipeName)
        vendorSell = vendorSell or 0
        deposit    = math.max(1, math.floor(vendorSell * (AHT.postDuration == 1 and 0.018 or AHT.postDuration == 2 and 0.036 or 0.072) * count))
    end

    if deposit > GetMoney() then
        AHT:Print(string.format(L and L["post_no_gold"] or
            "|cffff4444Nicht genug Gold für Deposit (%s).|r", AHT:FormatMoney(deposit)))
        ClearCursor()
        AHT:CancelPost(); return
    end

    StartAuction(startPrice, buyout, AHT.postDuration)

    AHT.postTotalPosted = AHT.postTotalPosted + count
    AHT.postTotalStacks = AHT.postTotalStacks + 1

    AHT:Print(string.format(L and L["post_complete"] or "Gepostet: %dx %s für %s",
        count, AHT.postRecipeName, AHT:FormatMoney(buyout)))

    AHT:AdvancePostQueue()
end

-- ── NEW_AUCTION_UPDATE ────────────────────────────────────────
function AHT:OnNewAuctionUpdate()
    -- Polling-basierter Ansatz braucht dieses Event nicht aktiv
end

-- ── Preis-Prüfung (AH-Abfrage vor dem Posten) ────────────────
-- Fragt den aktuellen AH-Preis ab und ruft dann callback(preis) auf
function AHT:CheckPostPrice(itemName, callback)
    AHT.postPriceCheck = {
        state    = "waiting",
        name     = itemName,
        page     = 0,
        timer    = 0,
        sentTimer = 0,
        callback = callback,
        minPPU   = nil,
    }
end

function AHT:OnPostPriceCheckListUpdate()
    local pc = AHT.postPriceCheck
    if not pc or pc.state ~= "sent" then return end

    local numItems = GetNumAuctionItems("list")
    local player   = UnitName("player")

    for i = 1, numItems do
        local name, _, count, _, _, _, _, _, buyoutPrice, _, _, _, _, owner, ownerFull =
            GetAuctionItemInfo("list", i)

        local isOwn = (owner == player) or (ownerFull and ownerFull:match("^" .. player))

        if name == pc.name and buyoutPrice and buyoutPrice > 0
           and count and count > 0 and not isOwn then
            local ppu = math.floor(buyoutPrice / count)
            if not pc.minPPU or ppu < pc.minPPU then
                pc.minPPU = ppu
            end
        end
    end

    if numItems >= 50 then
        pc.page      = pc.page + 1
        pc.state     = "waiting"
        pc.timer     = 0
        pc.sentTimer = 0
    else
        -- Ergebnis an Callback liefern
        local minPPU = pc.minPPU
        AHT.postPriceCheck = nil
        if pc.callback then pc.callback(minPPU) end
    end
end

-- ── AH-Ergebnis-Router für Poster ────────────────────────────
function AHT:OnPosterAuctionListUpdate()
    local pc = AHT.postPriceCheck
    if pc and pc.state == "sent" then
        AHT:OnPostPriceCheckListUpdate()
    end
end

-- ── Posting abbrechen ────────────────────────────────────────
function AHT:CancelPost()
    if AHT.postState == "idle" then
        local L = AHT.L
        if L then AHT:Print(L["post_cancelled"]) end
        return
    end
    local L = AHT.L
    if L then AHT:Print(L["post_cancelled"]) end
    AHT:OnPostComplete()
end

-- ── Posting abgeschlossen ────────────────────────────────────
function AHT:OnPostComplete()
    AHT.postState = "idle"
    ClearCursor()

    local L = AHT.L
    if AHT.postTotalStacks > 0 and L then
        AHT:Print(string.format(L["post_complete"], AHT.postTotalStacks))
    end

    AHT.postRecipeName = nil
end

-- ── Prueft ob Posting läuft ───────────────────────────────────
function AHT:IsPosting()
    return AHT.postState ~= "idle"
end

if AHT and AHT._loadStatus then
    AHT._loadStatus.poster = true
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[AHT-DIAG]|r Poster.lua OK")
    end
end
