-- ============================================================
-- ProjEP AH Trader - Tailoring.lua
-- Schneiderei: Rezept-Analyse
-- WotLK 3.3.5 / Lua 5.1 (Project Epoch)
-- ============================================================

local AHT = PROJEP_AHT

local TAIL_NAMES = {
    ["tailoring"]   = true,
    ["schneiderei"] = true,
    ["couture"]     = true,
    ["sastrería"]   = true,
    ["sartoria"]    = true,
}

AHT.tailRecipes        = AHT.tailRecipes        or {}
AHT.tailSelected       = AHT.tailSelected       or {}
AHT.tailResults        = AHT.tailResults        or {}
AHT.tailDisplayResults = AHT.tailDisplayResults or {}
AHT.tailSortMode       = "profit"
AHT.tailSortDir        = "desc"
AHT._tailRetryPending  = false
AHT._tailRetryTimer    = 0
AHT._tailRetryMax      = 3
AHT._tailRetryCount    = 0
AHT._tailLoadGuard     = false

function AHT:LearnTailoringRecipes()
    if AHT._tailLoadGuard then return end
    AHT._tailLoadGuard = true

    local profName = GetTradeSkillLine()
    if not profName or not TAIL_NAMES[profName:lower()] then
        AHT._tailLoadGuard = false; return
    end

    local numSkills = GetNumTradeSkills()
    if not numSkills or numSkills == 0 then
        AHT._tailLoadGuard = false; return
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
    for _, r in ipairs(AHT.tailRecipes) do existingMap[r.name] = true end
    for _, recipe in ipairs(recipes) do
        if not existingMap[recipe.name] then
            table.insert(AHT.tailRecipes, recipe)
            if AHT.tailSelected[recipe.name] == nil then
                AHT.tailSelected[recipe.name] = true
            end
        end
    end

    AHT:SaveDB()
    AHT:Print(string.format(AHT.L["recipes_loaded_count"], #AHT.tailRecipes))

    if retryNeeded and AHT._tailRetryCount < AHT._tailRetryMax then
        AHT._tailRetryCount   = AHT._tailRetryCount + 1
        AHT._tailRetryPending = true
        AHT._tailRetryTimer   = 0
    end
    AHT._tailLoadGuard = false
end

local tailRetryFrame = CreateFrame("Frame")
tailRetryFrame:SetScript("OnUpdate", function(self, elapsed)
    if AHT._tailRetryPending then
        AHT._tailRetryTimer = AHT._tailRetryTimer + elapsed
        if AHT._tailRetryTimer >= 1.0 then
            AHT._tailRetryPending = false
            AHT._tailRetryTimer   = 0
            if TradeSkillFrame and TradeSkillFrame:IsVisible() then
                AHT:LearnTailoringRecipes()
            end
        end
    end
end)

function AHT:CalculateTailoringMargins()
    local results = {}
    for _, recipe in ipairs(AHT.tailRecipes) do
        if AHT.tailSelected[recipe.name] ~= false then
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
    local mode = AHT.tailSortMode or "profit"
    local dir  = AHT.tailSortDir  or "desc"
    table.sort(results, function(a, b)
        local va = (mode == "margin") and (a.margin or -9e9) or (a.profit or -9e9)
        local vb = (mode == "margin") and (b.margin or -9e9) or (b.profit or -9e9)
        return dir == "asc" and va < vb or va > vb
    end)
    AHT.tailResults        = results
    AHT.tailDisplayResults = results
    return results
end

function AHT:StartTailoringScan()
    if AHT:IsScanning() then AHT:Print(AHT.L["scan_already_running"]); return end
    if not AuctionFrame or not AuctionFrame:IsVisible() then
        AHT:Print(AHT.L["scan_ah_required"]); return
    end
    if #AHT.tailRecipes == 0 then AHT:Print(AHT.L["tail_no_recipes"]); return end

    local seen, queue = {}, {}
    for _, recipe in ipairs(AHT.tailRecipes) do
        if AHT.tailSelected[recipe.name] ~= false then
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
    AHT._loadStatus.tailoring = true
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[AHT-DIAG]|r Tailoring.lua OK")
    end
end
