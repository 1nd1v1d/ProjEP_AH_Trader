-- ============================================================
-- ProjEP AH Trader - Core.lua
-- Hauptobjekt, Initialisierung, Events, Slash-Befehle
-- WotLK 3.3.5 / Lua 5.1 (Project Epoch)
-- ============================================================

PROJEP_AHT = {}
local AHT = PROJEP_AHT

AHT.VERSION = "1.1.0"

-- Diagnostik-Marker: zeigt welche Module geladen wurden
AHT._loadStatus = AHT._loadStatus or {}
AHT._loadStatus.coreStart = true
if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[AHT-DIAG]|r Core.lua TOP")
end

-- ── Laufzeit-Daten ────────────────────────────────────────────
AHT.prices        = {}   -- [itemName] = günstigster Buyout pro Stück (Kupfer)
AHT.recipes       = {}   -- [{name, reagents=[{name,count}], link}] – Alchemie
AHT.results       = {}   -- Berechnete Ergebnisse nach Scan
AHT.selected      = {}   -- [recipeName] = true/false
AHT.priceUpdated  = {}   -- [itemName] = Unix-Timestamp
AHT.priceHistory  = {}   -- [itemName] = { {t=,p=}, ... }
AHT.listingCounts = {}   -- [itemName] = Anzahl Listings
AHT.allOffersCache = {}  -- [itemName] = {t=, offers=[{ppu,count,buyout}]}

-- itemId <-> itemName Lookup (aus GetAll-Scan befüllt)
AHT.idToName  = {}   -- [itemId (number)] = itemName
AHT.nameToId  = {}   -- [itemName] = itemId (number)

-- ── Optionen ──────────────────────────────────────────────────
AHT.ahCutRate = 0.05   -- 5% Provision (Fraktions-AH); 0.15 für Goblin-AH

-- ── GetAll-Scan ───────────────────────────────────────────────
AHT.getAllLastTime    = 0
AHT.GET_ALL_COOLDOWN = 900  -- 15 Minuten in Sekunden

-- ── Materialien ───────────────────────────────────────────────
AHT.materials          = {}
AHT.matsSelected       = {}
AHT.matsCategories     = {}
AHT.matsResults        = {}
AHT.matsDisplayResults = {}
AHT.matsHistory        = {}
AHT.matsSortMode       = "deviation"
AHT.matsSortDir        = "desc"
AHT.matsSearchFilter   = ""
AHT.matsButton         = nil
AHT.matsOfferCache     = {}

-- ── Schmiedekunst ─────────────────────────────────────────────
AHT.bsRecipes        = {}
AHT.bsSelected       = {}
AHT.bsResults        = {}
AHT.bsDisplayResults = {}

-- ── Schneiderei ───────────────────────────────────────────────
AHT.tailRecipes        = {}
AHT.tailSelected       = {}
AHT.tailResults        = {}
AHT.tailDisplayResults = {}

-- ── Lederverarbeitung ─────────────────────────────────────────
AHT.lwRecipes        = {}
AHT.lwSelected       = {}
AHT.lwResults        = {}
AHT.lwDisplayResults = {}

-- ── Ingenieurskunst ───────────────────────────────────────────
AHT.engRecipes        = {}
AHT.engSelected       = {}
AHT.engResults        = {}
AHT.engDisplayResults = {}

-- ── Sortierung & Filter (Alchemie) ────────────────────────────
AHT.sortMode     = "profit"
AHT.sortDir      = "desc"
AHT.searchFilter = ""
AHT.displayResults = {}

-- ── Session-Kaufgedächtnis ────────────────────────────────────
AHT.sessionBought = {}   -- [recipeName][itemName] = Anzahl

-- ── Konstanten ────────────────────────────────────────────────
AHT.MAX_HISTORY    = 20
AHT.UNDERCUT       = 1
AHT.DEAL_THRESHOLD = 0.20

-- ── WotLK AH-Kategorien (classIndex für QueryAuctionItems) ───
AHT.MAT_CATEGORY_IDS = {
    { id = 1,  key = "cat_weapon"     },
    { id = 2,  key = "cat_armor"      },
    { id = 3,  key = "cat_container"  },
    { id = 4,  key = "cat_consumable" },
    { id = 5,  key = "cat_trade_goods"},
    { id = 6,  key = "cat_projectile" },
    { id = 7,  key = "cat_quiver"     },
    { id = 8,  key = "cat_recipe"     },
    { id = 9,  key = "cat_reagent"    },
    { id = 10, key = "cat_misc"       },
    { id = 11, key = "cat_gem"        },
    { id = 12, key = "cat_glyph"      },
}

-- ── Vendor-Preise (WotLK) ─────────────────────────────────────
-- In WotLK gibt es keine Phiolen mehr für die meisten Northrend-Tränke.
-- Parchments werden von Händlern gekauft (für Inscription).
AHT.vendorPrices = {
    -- Parchments (Inschriftenkunde)
    ["Light Parchment"]  = 25,    -- 25c
    ["Common Parchment"] = 50,    -- 50c
    ["Heavy Parchment"]  = 100,   -- 1s
    -- Deutsche Namen
    ["Leichtes Pergament"]  = 25,
    ["Normales Pergament"]  = 50,
    ["Schweres Pergament"]  = 100,
    -- Vanilla-Phiolen (für TBC/Vanilla Rezepte die noch gelernt wurden)
    ["Crystal Vial"]       = 18,
    ["Leaded Vial"]        = 180,
    ["Imbued Vial"]        = 2250,
    ["Enchanted Vial"]     = 27000,
    ["Empty Vial"]         = 1,
    ["Kristallphiole"]     = 18,
    ["Gesprungene Phiole"] = 180,
    ["Besudelte Phiole"]   = 2250,
    ["Geschmolzene Phiole"] = 27000,
    ["Leere Phiole"]       = 1,
}

-- ── Hilfsfunktionen ──────────────────────────────────────────
function AHT:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[AH Trader]|r " .. tostring(msg))
end

-- Toleranter Name-Vergleich. WoW's AH liefert auf manchen Servern (Project Epoch
-- inkl.) Item-Namen mit abweichender Gross-/Kleinschreibung zurueck. Strikte
-- Gleichheit verfehlt dann alle Treffer und der Scan speichert keine Preise.
-- Identisch zum Pattern in Auctionator's zc.StringSame.
function AHT:NameMatches(a, b)
    if a == b then return true end
    if not a or not b then return false end
    return string.lower(a) == string.lower(b)
end

function AHT:FormatMoney(copper)
    if not copper then return "|cffaaaaaa?|r" end
    local neg = copper < 0
    if neg then copper = -copper end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local out = ""
    if g > 0 then out = out .. "|cffffd700" .. g .. "g|r " end
    if s > 0 or g > 0 then out = out .. "|cffc7c7cf" .. s .. "s|r " end
    out = out .. "|cffeda55f" .. c .. "c|r"
    if neg then out = "-" .. out end
    return out
end

function AHT:FormatMoneyPlain(copper)
    if not copper then return "?" end
    local neg = copper < 0
    if neg then copper = -copper end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local out = ""
    if g > 0 then out = out .. g .. "g " end
    if s > 0 or g > 0 then out = out .. s .. "s " end
    out = out .. c .. "c"
    if neg then out = "-" .. out end
    return out
end

-- Parst "5g 20s 10c", "90c", "2g", reine Zahl → Kupfer
function AHT:ParseMoney(str)
    if not str or str == "" then return nil end
    str = string.lower(str)
    local total = 0
    local g = tonumber(str:match("(%d+)g")) or 0
    local s = tonumber(str:match("(%d+)s")) or 0
    local c = tonumber(str:match("(%d+)c")) or 0
    total = g * 10000 + s * 100 + c
    if total == 0 then
        total = tonumber(str) or 0
    end
    return total > 0 and total or nil
end

function AHT:FormatMoneyInput(copper)
    if not copper or copper <= 0 then return "0c" end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local parts = {}
    if g > 0 then table.insert(parts, g .. "g") end
    if s > 0 then table.insert(parts, s .. "s") end
    if c > 0 then table.insert(parts, c .. "c") end
    return table.concat(parts, " ")
end

function AHT:TableCount(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- ── Item-ID Lookups ──────────────────────────────────────────
function AHT:GetItemId(itemName)
    if not itemName then return nil end
    if AHT.nameToId[itemName] then
        return AHT.nameToId[itemName]
    end
    local _, itemLink = GetItemInfo(itemName)
    if itemLink then
        local itemId = tonumber(itemLink:match("|Hitem:(%d+):"))
        if itemId then
            AHT.nameToId[itemName] = itemId
            AHT.idToName[itemId]   = itemName
            return itemId
        end
    end
    return nil
end

function AHT:GetNameById(itemId)
    if not itemId then return nil end
    return AHT.idToName[itemId]
end

-- Preis per Name (nutzt nameToId wenn verfügbar)
function AHT:GetPrice(itemName)
    return AHT.prices[itemName]
end

-- ── Inventar-Helfer ──────────────────────────────────────────
function AHT:CountItemInBags(itemName)
    local total = 0
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local name = link:match("%[(.-)%]")
                if name == itemName then
                    local _, count = GetContainerItemInfo(bag, slot)
                    total = total + (count or 1)
                end
            end
        end
    end
    return total
end

function AHT:FindItemInBags(itemName)
    local stacks = {}
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local name = link:match("%[(.-)%]")
                if name == itemName then
                    local _, count = GetContainerItemInfo(bag, slot)
                    table.insert(stacks, { bag = bag, slot = slot, count = count or 1 })
                end
            end
        end
    end
    return stacks
end

-- ── Preisverlauf ─────────────────────────────────────────────
function AHT:AddPriceHistory(itemName, price)
    if not price or price <= 0 then return end
    if not AHT.priceHistory[itemName] then
        AHT.priceHistory[itemName] = {}
    end
    local hist = AHT.priceHistory[itemName]
    table.insert(hist, { t = time(), p = price })
    while #hist > AHT.MAX_HISTORY do
        table.remove(hist, 1)
    end
end

function AHT:GetPriceAverage(itemName)
    local hist = AHT.priceHistory[itemName]
    if not hist or #hist == 0 then return nil end
    local sum = 0
    for _, e in ipairs(hist) do sum = sum + e.p end
    return math.floor(sum / #hist)
end

function AHT:GetPriceTrend(itemName)
    local hist = AHT.priceHistory[itemName]
    if not hist or #hist < 3 then return nil end
    local avg = AHT:GetPriceAverage(itemName)
    if not avg or avg == 0 then return nil end
    local current = hist[#hist].p
    local pct = ((current - avg) / avg) * 100
    if pct > 10 then return "up"
    elseif pct < -10 then return "down"
    else return "stable" end
end

function AHT:IsDeal(itemName)
    local price = AHT.prices[itemName]
    local avg   = AHT:GetPriceAverage(itemName)
    if not price or not avg or avg == 0 then return false end
    return price < avg * (1 - AHT.DEAL_THRESHOLD)
end

-- ── GetAll-Cooldown ──────────────────────────────────────────
function AHT:CanGetAllScan()
    return (GetTime() - AHT.getAllLastTime) >= AHT.GET_ALL_COOLDOWN
end

function AHT:GetAllRemainingCooldown()
    local r = AHT.GET_ALL_COOLDOWN - (GetTime() - AHT.getAllLastTime)
    return math.max(0, math.floor(r))
end

-- ── Vendor-Item Prüfung ───────────────────────────────────────
function AHT:IsVendorItem(name)
    return AHT.vendorPrices[name] ~= nil
end

-- ── Materialien-Management ────────────────────────────────────
function AHT:AddMaterial(itemName, categoryId)
    if not itemName or itemName == "" then return end
    AHT.materials[itemName]    = true
    AHT.matsSelected[itemName] = true
    AHT.matsCategories[itemName] = (categoryId and categoryId > 0) and categoryId or nil
    AHT:SaveDB()
end

function AHT:RemoveMaterial(itemName)
    if not itemName then return end
    AHT.materials[itemName]      = nil
    AHT.matsSelected[itemName]   = nil
    AHT.matsCategories[itemName] = nil
    AHT:SaveDB()
end

function AHT:GetMatCategoryId(itemName)
    return AHT.matsCategories[itemName]
end

function AHT:GetMatCategoryLabel(categoryId)
    local L = AHT.L
    if not categoryId or categoryId <= 0 then
        return L["mats_category_all"] or "All"
    end
    for _, cat in ipairs(AHT.MAT_CATEGORY_IDS) do
        if cat.id == categoryId then
            return L[cat.key] or tostring(categoryId)
        end
    end
    return tostring(categoryId)
end

function AHT:GetMaterialsList()
    local list = {}
    for name in pairs(AHT.materials) do
        table.insert(list, name)
    end
    table.sort(list)
    return list
end

-- ── Rezepta-Debugausgabe ─────────────────────────────────────
function AHT:PrintRecipes()
    local L = AHT.L
    if #AHT.recipes == 0 then
        AHT:Print(L["no_recipes_loaded"])
        return
    end
    AHT:Print("|cffffd700" .. string.format(L["recipes_loaded_count"], #AHT.recipes) .. "|r")
    for _, recipe in ipairs(AHT.recipes) do
        local parts = {}
        for _, ing in ipairs(recipe.reagents) do
            table.insert(parts, ing.count .. "x " .. ing.name)
        end
        local sel = (AHT.selected[recipe.name] == false)
            and ("|cff888888" .. L["recipe_disabled_tag"] .. "|r ") or ""
        AHT:Print("  " .. sel .. "|cff00ff00" .. recipe.name .. "|r: " .. table.concat(parts, ", "))
    end
end

-- ── AH-Kategorie-Cache ────────────────────────────────────────
local function NormalizeLabel(label)
    if not label then return nil end
    label = label:gsub("^%s*(.-)%s*$", "%1"):gsub("%s+", " ")
    return label ~= "" and label:lower() or nil
end

function AHT:RefreshAuctionQueryCaches()
    if not GetAuctionItemClasses or not GetAuctionItemSubClasses then return end
    local classMap, subClassMap = {}, {}
    local classes = { GetAuctionItemClasses() }
    for ci, cn in ipairs(classes) do
        local nc = NormalizeLabel(cn)
        if nc then classMap[nc] = ci end
        local sub = {}
        for si, sn in ipairs({ GetAuctionItemSubClasses(ci) }) do
            local ns = NormalizeLabel(sn)
            if ns then sub[ns] = si end
        end
        subClassMap[ci] = sub
    end
    AHT.auctionClassNameToIndex    = classMap
    AHT.auctionSubClassNameToIndex = subClassMap
end

function AHT:GetAuctionQueryFilters(itemName, preferredClassId)
    if (not AHT.auctionClassNameToIndex or not next(AHT.auctionClassNameToIndex))
       and AuctionFrame and AuctionFrame:IsVisible() then
        AHT:RefreshAuctionQueryCaches()
    end
    local classIndex    = preferredClassId
    local subClassIndex = nil
    if GetItemInfo and itemName then
        local _, _, _, _, _, iType, iSubType = GetItemInfo(itemName)
        local nt  = NormalizeLabel(iType)
        local nst = NormalizeLabel(iSubType)
        if not classIndex and nt and AHT.auctionClassNameToIndex then
            classIndex = AHT.auctionClassNameToIndex[nt]
        end
        if classIndex and nst and AHT.auctionSubClassNameToIndex then
            local sub = AHT.auctionSubClassNameToIndex[classIndex]
            if sub then subClassIndex = sub[nst] end
        end
    end
    return nil, classIndex, subClassIndex
end

-- ── Slash-Befehle ────────────────────────────────────────────
SLASH_PROJEP_AHT1 = "/aht"
SLASH_PROJEP_AHT2 = "/ahtrader"
SLASH_PROJEP_AHT3 = "/projepaht"
SlashCmdList["PROJEP_AHT"] = function(msg)
    AHT:Print("|cff00ff00[Slash-Handler erreicht]|r msg='" .. tostring(msg) .. "'")
    local L = AHT.L
    msg = string.lower(msg or "")
    if msg == "" or msg == "show" then
        if #AHT.recipes > 0 then AHT:CalculateMargins() end
        AHT:ShowUI()
    elseif msg == "scan" then
        AHT:StartScan()
    elseif msg == "getall" then
        AHT:StartGetAllScan()
    elseif msg == "stop" or msg == "cancel" then
        AHT:CancelScan()
    elseif msg == "reset" then
        AHT.prices       = {}
        AHT.priceHistory = {}
        AHT.listingCounts = {}
        AHT.allOffersCache = {}
        AHT:SaveDB()
        AHT:Print(L["price_data_reset"])
    elseif msg == "snipe" then
        AHT:StartSnipeScan()
    elseif msg == "post" then
        AHT:Print(L["post_hint"])
    elseif msg == "recipes" or msg == "rezepte" then
        AHT:PrintRecipes()
    elseif msg == "mats" then
        AHT:ShowMatsManageDialog()
    elseif msg == "master" then
        -- Transmutation Master wurde entfernt
    elseif msg == "debug" then
        AHT:Print(string.format(L["debug_version"], AHT.VERSION))
        AHT:Print(string.format(L["debug_recipes"], #AHT.recipes))
        AHT:Print(string.format(L["debug_prices"], AHT:TableCount(AHT.prices)))
        AHT:Print(string.format(L["debug_vendor"], AHT:TableCount(AHT.vendorPrices)))
        AHT:Print(string.format(L["debug_scan"], AHT.scanState or "idle"))
        AHT:Print(string.format(L["debug_getall"], AHT:GetAllRemainingCooldown()))
        AHT:Print(string.format(L["debug_master"], AHT.isMasterAlch
            and L["master_status_on"] or L["master_status_off"]))
    else
        AHT:Print(L["help_show"])
        AHT:Print(L["help_scan"])
        AHT:Print(L["help_getall"])
        AHT:Print(L["help_snipe"])
        AHT:Print(L["help_mats"])
        AHT:Print(L["help_stop"])
        AHT:Print(L["help_reset"])
        AHT:Print(L["help_recipes"])
        AHT:Print(L["help_master"])
        AHT:Print(L["help_debug"])
        AHT:Print(L["help_actions"])
    end
end

-- ── Persistenz ───────────────────────────────────────────────
function AHT:OnLoad()
    if ProjEP_AHT_DB then
        AHT.prices         = ProjEP_AHT_DB.prices         or {}
        AHT.recipes        = ProjEP_AHT_DB.recipes        or {}
        AHT.selected       = ProjEP_AHT_DB.selected       or {}
        AHT.priceUpdated   = ProjEP_AHT_DB.priceUpdated   or {}
        AHT.priceHistory   = ProjEP_AHT_DB.priceHistory   or {}
        AHT.listingCounts  = ProjEP_AHT_DB.listingCounts  or {}
        AHT.materials      = ProjEP_AHT_DB.materials      or {}
        AHT.matsSelected   = ProjEP_AHT_DB.matsSelected   or {}
        AHT.matsCategories = ProjEP_AHT_DB.matsCategories or {}
        AHT.matsHistory    = ProjEP_AHT_DB.matsHistory    or {}
        AHT.getAllLastTime  = ProjEP_AHT_DB.getAllLastTime  or 0
        AHT.bsSelected     = ProjEP_AHT_DB.bsSelected     or {}
        AHT.tailSelected   = ProjEP_AHT_DB.tailSelected   or {}
        AHT.lwSelected     = ProjEP_AHT_DB.lwSelected     or {}
        AHT.engSelected    = ProjEP_AHT_DB.engSelected    or {}
        AHT.bsRecipes      = ProjEP_AHT_DB.bsRecipes      or {}
        AHT.tailRecipes    = ProjEP_AHT_DB.tailRecipes    or {}
        AHT.lwRecipes      = ProjEP_AHT_DB.lwRecipes      or {}
        AHT.engRecipes     = ProjEP_AHT_DB.engRecipes     or {}
        AHT.nameToId       = ProjEP_AHT_DB.nameToId       or {}
        AHT.idToName       = {}
        -- idToName aus nameToId wiederherstellen
        for name, id in pairs(AHT.nameToId) do
            AHT.idToName[id] = name
        end
    end
    -- Vendor-Preise eintragen
    for name, price in pairs(AHT.vendorPrices) do
        AHT.prices[name] = price
    end
    AHT:Print(string.format(AHT.L["addon_loaded"], AHT.VERSION))

    -- Diagnostik: Load-Status aller Module
    local s = AHT._loadStatus or {}
    AHT:Print(string.format(
        "|cffffd700[AHT-DIAG]|r Module-Load: core=%s locales=%s calc=%s alch=%s "
        .. "bs=%s tail=%s lw=%s eng=%s buyer=%s poster=%s mats=%s scanner=%s ui=%s",
        tostring(s.coreEnd), tostring(s.locales), tostring(s.calculator),
        tostring(s.alchemy), tostring(s.blacksmithing), tostring(s.tailoring),
        tostring(s.leatherworking), tostring(s.engineering),
        tostring(s.buyer), tostring(s.poster),
        tostring(s.mats), tostring(s.scanner), tostring(s.ui)))

    -- Slash-Befehle defensiv erneut registrieren
    SLASH_PROJEP_AHT1 = "/aht"
    SLASH_PROJEP_AHT2 = "/ahtrader"
end

function AHT:SaveDB()
    ProjEP_AHT_DB = ProjEP_AHT_DB or {}
    ProjEP_AHT_DB.prices         = AHT.prices
    ProjEP_AHT_DB.recipes        = AHT.recipes
    ProjEP_AHT_DB.selected       = AHT.selected
    ProjEP_AHT_DB.priceUpdated   = AHT.priceUpdated
    ProjEP_AHT_DB.priceHistory   = AHT.priceHistory
    ProjEP_AHT_DB.listingCounts  = AHT.listingCounts
    ProjEP_AHT_DB.materials      = AHT.materials
    ProjEP_AHT_DB.matsSelected   = AHT.matsSelected
    ProjEP_AHT_DB.matsCategories = AHT.matsCategories
    ProjEP_AHT_DB.matsHistory    = AHT.matsHistory
    ProjEP_AHT_DB.getAllLastTime  = AHT.getAllLastTime
    ProjEP_AHT_DB.bsSelected     = AHT.bsSelected
    ProjEP_AHT_DB.tailSelected   = AHT.tailSelected
    ProjEP_AHT_DB.lwSelected     = AHT.lwSelected
    ProjEP_AHT_DB.engSelected    = AHT.engSelected
    ProjEP_AHT_DB.bsRecipes      = AHT.bsRecipes
    ProjEP_AHT_DB.tailRecipes    = AHT.tailRecipes
    ProjEP_AHT_DB.lwRecipes      = AHT.lwRecipes
    ProjEP_AHT_DB.engRecipes     = AHT.engRecipes
    ProjEP_AHT_DB.nameToId       = AHT.nameToId
end

-- ── Event-Frame (wird per XML erstellt, Funktionen muessen global sein) ───────

function ProjEP_AHT_RegisterEvents(self)
    self:RegisterEvent("ADDON_LOADED")
    self:RegisterEvent("VARIABLES_LOADED")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("PLAYER_LOGOUT")
    self:RegisterEvent("TRADE_SKILL_SHOW")
    self:RegisterEvent("AUCTION_HOUSE_SHOW")
    self:RegisterEvent("AUCTION_HOUSE_CLOSED")
    self:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
end

function ProjEP_AHT_OnEvent(self, event, ...)
    local AHT = PROJEP_AHT
    local arg1 = ...
    if event == "ADDON_LOADED" and arg1 == "ProjEP_AH_Trader" then
        if not AHT._loaded then
            AHT._loaded = true
            AHT:OnLoad()
        end
    elseif event == "VARIABLES_LOADED" then
        if not AHT._loaded then
            AHT._loaded = true
            AHT:OnLoad()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if AuctionFrame and not AHT._ahHooked then
            AHT._ahHooked = true
            AuctionFrame:HookScript("OnShow", function()
                local ok, err = pcall(function() AHT:OnAHShow() end)
                if not ok then AHT:Print("OnAHShow Fehler: " .. tostring(err)) end
            end)
        end
    elseif event == "PLAYER_LOGOUT" then
        AHT:SaveDB()
    elseif event == "TRADE_SKILL_SHOW" then
        AHT:OnTradeSkillShow()
    elseif event == "AUCTION_HOUSE_SHOW" then
        AHT:Print("|cff00ff00[Event AUCTION_HOUSE_SHOW]|r")
        local ok, err = pcall(function() AHT:OnAHShow() end)
        if not ok then AHT:Print("OnAHShow Fehler: " .. tostring(err)) end
    elseif event == "AUCTION_HOUSE_CLOSED" then
        AHT:OnAHClosed()
    elseif event == "AUCTION_ITEM_LIST_UPDATE" then
        AHT:OnAuctionItemListUpdate()
    end
end

local _ahWasVisible = false
function ProjEP_AHT_OnUpdate(self, elapsed)
    local AHT = PROJEP_AHT
    if AuctionFrame then
        local visible = AuctionFrame:IsVisible()
        if visible and not _ahWasVisible then
            local ok, err = pcall(function() AHT:OnAHShow() end)
            if not ok then AHT:Print("OnAHShow Fehler: " .. tostring(err)) end
        end
        _ahWasVisible = visible
    end
    if AHT.scanState ~= "idle" then
        AHT:OnUpdate(elapsed)
    end
    if AHT:IsMatScanning() then
        AHT:OnUpdateMats(elapsed)
    end
end


-- ── Dispatcher: AUCTION_ITEM_LIST_UPDATE ─────────────────────
function AHT:OnAuctionItemListUpdate()
    if AHT.scanState == "getall_sent" then
        AHT:OnGetAllAuctionListUpdate()
    elseif AHT:IsMatScanning() then
        AHT:OnMatsAuctionListUpdate()
    elseif AHT.scanState == "sent" then
        AHT:OnAuctionListUpdate()
    end
end

-- ── Trade Skill: Profession-Dispatcher ───────────────────────
function AHT:OnTradeSkillShow()
    local profName = GetTradeSkillLine()
    if not profName then return end
    local lower = profName:lower()

    if lower == "alchemy" or lower == "alchemie" or lower == "alchimie"
       or lower == "alchimia" or lower == "alquimia" then
        AHT:LearnAlchemyRecipes()
        AHT:CalculateMargins()
        if AHT.activeTab == "alchemy" and ProjEP_AHT_MainFrame and ProjEP_AHT_MainFrame:IsVisible() then
            AHT:ApplyFilterAndSort(); AHT:RefreshUI()
        end
    elseif lower == "blacksmithing" or lower == "schmiedekunst"
       or lower == "forge" or lower == "herrería" then
        AHT:LearnBlacksmithingRecipes()
        AHT:CalculateBlacksmithingMargins()
        if AHT.activeTab == "blacksmithing" and ProjEP_AHT_MainFrame and ProjEP_AHT_MainFrame:IsVisible() then
            AHT:RefreshBlacksmithingTab()
        end
    elseif lower == "tailoring" or lower == "schneiderei"
       or lower == "couture" or lower == "sastrería" then
        AHT:LearnTailoringRecipes()
        AHT:CalculateTailoringMargins()
        if AHT.activeTab == "tailoring" and ProjEP_AHT_MainFrame and ProjEP_AHT_MainFrame:IsVisible() then
            AHT:RefreshTailoringTab()
        end
    elseif lower == "leatherworking" or lower == "lederverarbeitung"
       or lower == "travail du cuir" or lower == "peletería" then
        AHT:LearnLeatherworkingRecipes()
        AHT:CalculateLeatherworkingMargins()
        if AHT.activeTab == "leatherworking" and ProjEP_AHT_MainFrame and ProjEP_AHT_MainFrame:IsVisible() then
            AHT:RefreshLeatherworkingTab()
        end
    elseif lower == "engineering" or lower == "ingenieurskunst"
       or lower == "ingeneurkunst" or lower == "ingénierie" then
        AHT:LearnEngineeringRecipes()
        AHT:CalculateEngineeringMargins()
        if AHT.activeTab == "engineering" and ProjEP_AHT_MainFrame and ProjEP_AHT_MainFrame:IsVisible() then
            AHT:RefreshEngineeringTab()
        end
    end
end

-- ── AH geschlossen ────────────────────────────────────────────
function AHT:OnAHClosed()
    if AHT:IsScanning()    then AHT:CancelScan() end
    if AHT:IsMatScanning() then AHT:CancelMatsScan() end
    AHT.sessionBought = {}
    -- AHT-Hauptfenster schließen
    if ProjEP_AHT_MainFrame then ProjEP_AHT_MainFrame:Hide() end
    -- AH-Buttons sind Kinder von AuctionFrame und verstecken sich automatisch
end

-- Diagnostik: Bestätigung dass Core.lua vollständig durchgelaufen ist
AHT._loadStatus.coreEnd = true
AHT._loadStatus.slashRegistered = (SLASH_PROJEP_AHT1 == "/aht")
if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[AHT-DIAG]|r Core.lua END (slash="
        .. tostring(AHT._loadStatus.slashRegistered) .. ")")
end
