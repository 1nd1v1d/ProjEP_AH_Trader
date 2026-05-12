-- ============================================================
-- ProjEP AH Trader - Blacksmithing.lua
-- Schmiedekunst: Rezept-Analyse
-- WotLK 3.3.5 / Lua 5.1 (Project Epoch)
-- ============================================================

local AHT = PROJEP_AHT

local BS_NAMES = {
    ["blacksmithing"] = true,
    ["schmiedekunst"]  = true,
    ["forge"]          = true,
    ["herrería"]       = true,
    ["fabbricazione"]  = true,
}

AHT.bsRecipes        = AHT.bsRecipes        or {}
AHT.bsSelected       = AHT.bsSelected       or {}
AHT.bsResults        = AHT.bsResults        or {}
AHT.bsDisplayResults = AHT.bsDisplayResults or {}
AHT.bsSortMode       = "profit"
AHT.bsSortDir        = "desc"
AHT._bsRetryPending  = false
AHT._bsRetryTimer    = 0
AHT._bsRetryMax      = 3
AHT._bsRetryCount    = 0
AHT._bsLoadGuard     = false

function AHT:LearnBlacksmithingRecipes()
    if AHT._bsLoadGuard then return end
    AHT._bsLoadGuard = true

    local profName = GetTradeSkillLine()
    if not profName or not BS_NAMES[profName:lower()] then
        AHT._bsLoadGuard = false; return
    end

    local numSkills = GetNumTradeSkills()
    if not numSkills or numSkills == 0 then
        AHT._bsLoadGuard = false; return
    end

    local recipes     = {}
    local seen        = {}
    local retryNeeded = false

    for i = 1, numSkills do
        local skillName, skillType = GetTradeSkillInfo(i)
        if skillName and skillType ~= "header" then
            if not seen[skillName] then
                seen[skillName] = true
                local reagents  = {}
                local allLoaded = true
                local numReag   = GetTradeSkillNumReagents(i)
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
                                else allLoaded = false end
                            else allLoaded = false end
                        else allLoaded = false end
                    end
                end
                if not allLoaded then
                    retryNeeded = true
                else
                    local outputLink = GetTradeSkillItemLink and GetTradeSkillItemLink(i) or nil
                    table.insert(recipes, { name = skillName, link = outputLink, reagents = reagents })
                end
            end
        end
    end

    local existingMap = {}
    for _, r in ipairs(AHT.bsRecipes) do existingMap[r.name] = true end
    for _, recipe in ipairs(recipes) do
        if not existingMap[recipe.name] then
            table.insert(AHT.bsRecipes, recipe)
            if AHT.bsSelected[recipe.name] == nil then
                AHT.bsSelected[recipe.name] = true
            end
        end
    end

    AHT:SaveDB()
    AHT:Print(string.format(AHT.L["recipes_loaded_count"], #AHT.bsRecipes))

    if retryNeeded and AHT._bsRetryCount < AHT._bsRetryMax then
        AHT._bsRetryCount   = AHT._bsRetryCount + 1
        AHT._bsRetryPending = true
        AHT._bsRetryTimer   = 0
    end
    AHT._bsLoadGuard = false
end

local bsRetryFrame = CreateFrame("Frame")
bsRetryFrame:SetScript("OnUpdate", function(self, elapsed)
    if AHT._bsRetryPending then
        AHT._bsRetryTimer = AHT._bsRetryTimer + elapsed
        if AHT._bsRetryTimer >= 1.0 then
            AHT._bsRetryPending = false
            AHT._bsRetryTimer   = 0
            if TradeSkillFrame and TradeSkillFrame:IsVisible() then
                AHT:LearnBlacksmithingRecipes()
            end
        end
    end
end)

function AHT:CalculateBlacksmithingMargins()
    local results = {}
    for _, recipe in ipairs(AHT.bsRecipes) do
        if AHT.bsSelected[recipe.name] ~= false then
            local ingredCost = 0
            local allFound   = true
            local missing    = {}
            for _, reag in ipairs(recipe.reagents) do
                local p = AHT.vendorPrices[reag.name] or AHT.prices[reag.name]
                if p then
                    ingredCost = ingredCost + p * reag.count
                else
                    allFound = false
                    table.insert(missing, reag.name)
                end
            end
            local sellPrice = AHT.prices[recipe.name]
            local r = {
                name        = recipe.name,
                link        = recipe.link,
                reagents    = recipe.reagents,
                ingredCost  = ingredCost,
                sellPrice   = sellPrice,
                missingReag = missing,
                allFound    = allFound,
                volume      = AHT.listingCounts[recipe.name] or 0,
            }
            if allFound and sellPrice and sellPrice > 0 then
                local provision = math.floor(sellPrice * AHT.ahCutRate)
                local deposit   = AHT:CalcDeposit(recipe.name)
                r.profit    = sellPrice - provision - deposit - ingredCost
                r.margin    = ingredCost > 0 and (r.profit / ingredCost * 100) or 0
                r.provision = provision
                r.deposit   = deposit
            end
            table.insert(results, r)
        end
    end
    local mode = AHT.bsSortMode or "profit"
    local dir  = AHT.bsSortDir  or "desc"
    table.sort(results, function(a, b)
        local va = (mode == "margin") and (a.margin or -9e9) or (a.profit or -9e9)
        local vb = (mode == "margin") and (b.margin or -9e9) or (b.profit or -9e9)
        return dir == "asc" and va < vb or va > vb
    end)
    AHT.bsResults        = results
    AHT.bsDisplayResults = results
    return results
end

function AHT:StartBlacksmithingScan()
    if AHT:IsScanning() then AHT:Print(AHT.L["scan_already_running"]); return end
    if not AuctionFrame or not AuctionFrame:IsVisible() then
        AHT:Print(AHT.L["scan_ah_required"]); return
    end
    if #AHT.bsRecipes == 0 then AHT:Print(AHT.L["bs_no_recipes"]); return end

    local seen, queue = {}, {}
    for _, recipe in ipairs(AHT.bsRecipes) do
        if AHT.bsSelected[recipe.name] ~= false then
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
    if #queue == 0 then AHT:Print(AHT.L["scan_no_items"]); return end

    AHT.scanQueue         = queue
    AHT.scanQueueIdx      = 0
    AHT.scanMinPrices     = {}
    AHT.scanListingCounts = {}
    AHT.scanOffers        = {}
    AHT:Print(string.format(AHT.L["scan_start"], #queue))
    AHT:AdvanceScanQueue()
end

if AHT and AHT._loadStatus then
    AHT._loadStatus.blacksmithing = true
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[AHT-DIAG]|r Blacksmithing.lua OK")
    end
end
