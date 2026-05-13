-- ============================================================
-- ProjEP AH Trader - Buyer.lua
-- Materialien kaufen via Auctionator (Atr_SearchAH)
-- ============================================================

local AHT = PROJEP_AHT

-- ── Auctionator-Bridge ────────────────────────────────────────
-- recipe: { name=string, reagents=[{name,count}] }  (Rezept-Modus)
--      ODER { name=string }                          (Material-Modus, Mats-Tab)
--
-- Hinweis: Atr_SearchAH wird NICHT verwendet, da es intern fälschlich zum
-- Sell-Tab wechselt. Stattdessen wird direkt zum Buy-Tab (BUY_TAB=3)
-- gewechselt und dann die Suche ausgelöst.
function AHT:BuyMaterialsViaAuctionator(recipe)
    if not Atr_SList or not Atr_SelectPane or not Atr_SetSearchText or not Atr_Search_Onclick then
        AHT:Print("|cffff4444Auctionator nicht gefunden! Bitte Auctionator-Addon aktivieren.|r")
        return
    end
    if not recipe or not recipe.name then return end

    local items = {}
    if recipe.reagents then
        -- Rezept-Modus: herstellbares Item selbst + Zutaten (Vendor-Items ausgenommen)
        table.insert(items, recipe.name)
        for _, reag in ipairs(recipe.reagents) do
            if not AHT:IsVendorItem(reag.name) then
                table.insert(items, reag.name)
            end
        end
    else
        -- Material-Modus: einzelnes Item direkt suchen
        table.insert(items, recipe.name)
    end

    if #items == 0 then
        AHT:Print("Keine AH-Materialien fuer " .. recipe.name .. " - alle beim Haendler.")
        return
    end

    -- Temporäre Einkaufsliste erstellen
    local slist = Atr_SList.create(recipe.name, false, true)
    for _, item in ipairs(items) do
        slist:AddItem('"' .. item .. '"')
    end

    -- Zum Buy-Reiter wechseln (BUY_TAB = 3 in Auctionator)
    Atr_SelectPane(3)

    -- Suche starten
    Atr_SetSearchText("{ " .. recipe.name .. " }")
    Atr_Search_Onclick()
end

-- ── Stubs (werden von Core.lua noch referenziert) ────────────
AHT.buyState  = "idle"
AHT.postState = "idle"
function AHT:IsBuying()               return false end
function AHT:CancelBuy()              end
function AHT:IsPosting()              return false end
function AHT:CancelPost()             end
function AHT:IsMatsBuying()           return false end
function AHT:CancelMatsBuy()          end
function AHT:OnBidPlaced()            end
function AHT:OnBuyUpdate()            end
function AHT:OnBuyAuctionListUpdate() end
function AHT:OnMatsBuyUpdate()        end
function AHT:OnMatsBuyAuctionListUpdate() end
function AHT:OnPostUpdate()           end
function AHT:OnNewAuctionUpdate()     end
function AHT:ShowPriceCheckResult()   end
function AHT:OnPostPriceCheckResult() end

if AHT._loadStatus then AHT._loadStatus.buyer = true end
