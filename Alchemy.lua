-- ============================================================
-- ProjEP AH Trader - Alchemy.lua
-- Alchemie-Rezepte aus dem Berufe-Fenster lesen (WotLK)
-- WotLK 3.3.5 / Lua 5.1 (Project Epoch)
-- ============================================================

local AHT = PROJEP_AHT

AHT._alchemyRetryPending = false
AHT._alchemyRetryTimer   = 0
AHT._alchemyRetryMax     = 3
AHT._alchemyRetryCount   = 0
AHT._alchemyLoadGuard    = false

-- Alchemie-Professionsnamen (alle Lokalisierungen)
local ALCHEMY_NAMES = {
    ["alchemy"]   = true,
    ["alchemie"]  = true,
    ["alchimie"]  = true,
    ["alchimia"]  = true,
    ["alquimia"]  = true,
}

-- ── Rezepte aus Berufe-Fenster lesen ─────────────────────────
function AHT:LearnAlchemyRecipes()
    if AHT._alchemyLoadGuard then return end
    AHT._alchemyLoadGuard = true

    local profName = GetTradeSkillLine()
    if not profName or not ALCHEMY_NAMES[profName:lower()] then
        AHT._alchemyLoadGuard = false
        return
    end

    local numSkills = GetNumTradeSkills()
    if not numSkills or numSkills == 0 then
        AHT._alchemyLoadGuard = false
        return
    end

    local recipes   = {}
    local seen      = {}
    local retryNeeded = false

    for i = 1, numSkills do
        local skillName, skillType = GetTradeSkillInfo(i)

        -- "header" überspringen
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
                        -- Name noch nicht im Cache → Retry
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
                    -- ItemLink des Outputs holen (optional)
                    local outputLink = GetTradeSkillItemLink and GetTradeSkillItemLink(i) or nil
                    table.insert(recipes, {
                        name     = skillName,
                        link     = outputLink,
                        reagents = reagents,
                    })
                end
            end
        end
    end

    -- Rezepte zusammenführen (neue überschreiben alte bei gleichem Namen)
    local existingMap = {}
    for _, r in ipairs(AHT.recipes) do existingMap[r.name] = true end

    for _, recipe in ipairs(recipes) do
        if not existingMap[recipe.name] then
            table.insert(AHT.recipes, recipe)
            -- Standardmäßig ausgewählt
            if AHT.selected[recipe.name] == nil then
                AHT.selected[recipe.name] = true
            end
        end
    end

    AHT:SaveDB()
    AHT:Print(string.format(AHT.L["recipes_loaded_count"], #AHT.recipes))

    if retryNeeded and AHT._alchemyRetryCount < AHT._alchemyRetryMax then
        AHT._alchemyRetryCount   = AHT._alchemyRetryCount + 1
        AHT._alchemyRetryPending = true
        AHT._alchemyRetryTimer   = 0
    end

    AHT._alchemyLoadGuard = false
end

-- ── Retry-Timer (für fehlende Item-Cache-Einträge) ────────────
local retryFrame = CreateFrame("Frame")
retryFrame:SetScript("OnUpdate", function(self, elapsed)
    if AHT._alchemyRetryPending then
        AHT._alchemyRetryTimer = AHT._alchemyRetryTimer + elapsed
        if AHT._alchemyRetryTimer >= 1.0 then
            AHT._alchemyRetryPending = false
            AHT._alchemyRetryTimer   = 0
            -- Erneut versuchen falls Berufe-Fenster noch offen
            if TradeSkillFrame and TradeSkillFrame:IsVisible() then
                AHT:LearnAlchemyRecipes()
            end
        end
    end
end)

-- ── Rezepte zurücksetzen ─────────────────────────────────────
function AHT:ResetAlchemyRecipes()
    AHT.recipes             = {}
    AHT._alchemyRetryCount  = 0
    AHT._alchemyRetryPending = false
    AHT:SaveDB()
    AHT:Print("Alchemie-Rezepte zurückgesetzt.")
end

-- ── Schneller Inventar-Check für Tränke ──────────────────────
function AHT:GetAlchemyPotionCount(recipeName)
    return AHT:CountItemInBags(recipeName)
end

if AHT and AHT._loadStatus then
    AHT._loadStatus.alchemy = true
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[AHT-DIAG]|r Alchemy.lua OK")
    end
end
