# ProjEP AH Trader – Umsetzungsdokumentation

> **Zielplattform:** Project Epoch (WoW WotLK 3.3.5a) | Interface `30300` | Lua 5.1  
> **Version:** 1.1.0  
> **SavedVariables:** `ProjEP_AHT_DB`  
> **Globales Objekt:** `PROJEP_AHT` (Alias: lokales `local AHT = PROJEP_AHT` in jeder Datei)  
> **Deploy:** `powershell -ExecutionPolicy Bypass -File deploy.ps1`

---

## 1. Projektübersicht

ProjEP AH Trader ist ein WoW-Addon für den privaten WotLK-Server **Project Epoch**. Es analysiert Auktionshaus-Preise und berechnet Gewinnmargen für:

- **Alchemie** – Tränke, Elixiere, Fläschchen
- **Transmutation** – Titan-Barren und epische Edelsteine (mit Transmutation-Master-Proc)
- **Inschriftenkunde** – Glyphen (alle Klassen)
- **Schmuckkunst** – Edelstein-Schliffe und Prospektions-Analyse
- **Materialien** – Rohstoff-Preisverfolgung mit gewichtetem Durchschnitt

Das Addon ist eine WotLK-Migration des bestehenden `TWOW_AH_Trader` (Vanilla 1.12.1), portiert auf Lua 5.1 und die WotLK-3.3.5-API.

---

## 2. Dateistruktur

```
ProjEP_AH_Trader/
├── ProjEP_AH_Trader.toc   TOC-Datei, Interface 30300, Ladereihenfolge
├── ProjEP_AH_Trader.xml   Event-Frame mit OnLoad/OnEvent/OnUpdate
├── Core.lua               Kernobjekt, Helpers, Persistenz, Event-Routing
├── Locales.lua            Lokalisierung: Deutsch (deDE) + Englisch
├── Calculator.lua         Margenkalkulation (Alchemie + Deposit)
├── Alchemy.lua            Rezept-Erkennung aus dem Berufe-Fenster
├── Inscription.lua        Glyphen-Analyse, Mahl-Raten, Tintenkosten
├── Transmute.lua          Transmutations-Daten und Kalkulation
├── Jewelcrafting.lua      Gem-Schliff- und Prospektions-Analyse
├── Buyer.lua              Auctionator-Bridge: Materialsuche via Atr_SelectPane + Atr_Search_Onclick
├── Poster.lua             Stub (Poster-Automatik entfernt)
├── Mats.lua               Material-Verwaltung, Analyse, Kaufdialog
├── Scanner.lua            Scan-Maschinen (Item-Scan, GetAll, Mats-Scan)
├── UI.lua                 Tabbed-Hauptfenster + alle Dialoge
└── deploy.ps1             Deployment-Skript nach AddOns-Verzeichnis
```

### Ladereihenfolge (TOC)

```
Core → Locales → Calculator → Alchemy → Inscription → Transmute
     → Jewelcrafting → Buyer → Poster → Mats → Scanner → UI
     → ProjEP_AH_Trader.xml
```

Alle Funktionen werden erst zur Laufzeit (nicht beim Laden) aufgerufen, daher ist gegenseitige Abhängigkeit zwischen späteren Dateien unproblematisch. Die XML-Datei lädt **zuletzt** und erstellt den Event-Frame, dessen `OnLoad` die globalen Funktionen `ProjEP_AHT_RegisterEvents`, `ProjEP_AHT_OnEvent` und `ProjEP_AHT_OnUpdate` (definiert in `Core.lua`) aufruft.

### Event-Frame (XML-Pattern, analog Auctionator)

```xml
<Frame name="ProjEP_AHT_EventFrame">
  <Scripts>
    <OnLoad>ProjEP_AHT_RegisterEvents(self);</OnLoad>
    <OnUpdate>ProjEP_AHT_OnUpdate(self, elapsed);</OnUpdate>
    <OnEvent>ProjEP_AHT_OnEvent(self, event, ...);</OnEvent>
  </Scripts>
</Frame>
```

Dieses Muster (statt `CreateFrame` in Lua) ist auf Project Epoch deutlich zuverlässiger – Lua-erstellte Event-Frames feuerten dort sporadisch keine Events.

---

## 3. Modul-Beschreibungen

### 3.1 `Core.lua`

**Verantwortung:** Zentrale Initialisierung, Datenhaltung, Hilfsfunktionen, Event-Dispatcher

**Tabellen auf `AHT`:**

| Tabelle | Inhalt |
|---|---|
| `prices` | `[itemName] = preis_in_copper` – günstigstes AH-Angebot |
| `priceHistory` | `[itemName] = [{t, p}, ...]` – Preishistorie |
| `priceUpdated` | `[itemName] = timestamp` – letzter Scan-Zeitpunkt |
| `listingCounts` | `[itemName] = anzahl` – Anzahl AH-Listings |
| `allOffersCache` | `[itemName] = [{count, ppu, owner}, ...]` – alle Angebote |
| `idToName` | `[itemId] = name` – ID→Name-Cache |
| `nameToId` | `[name] = itemId` – Name→ID-Cache |
| `recipes` | `[name] = {reagents, output, ...}` – Alchemie-Rezepte |
| `selected` | `[name] = bool` – Rezept-Auswahl für Scan/Kauf |
| `materials` | `[name] = {category}` – überwachte Rohstoffe |
| `matsSelected` | `[name] = bool` – Rohstoff aktiv? |
| `matsHistory` | `[name] = [{t, p, weighted_avg}, ...]` – Preishistorie Mats |
| `glyphs` | `[name] = {class, inkCost, ...}` – Glyphen-Rezepte |
| `gemCuts` | `[{name, rawGem, reagents, link}]` – JC-Schliff-Rezepte |

**Optionen:**

| Feld | Standard | Bedeutung |
|---|---|---|
| `ahCutRate` | `0.05` | AH-Gebühr (5% Fraktions-AH, 15% Goblin) |
| `isMasterAlch` | `false` | Transmutation-Master-Proc aktiviert |
| `GET_ALL_COOLDOWN` | `900` | Sekunden zwischen GetAll-Scans |

**Wichtige Hilfsfunktionen:**

```lua
AHT:FormatMoney(copper)          -- "5g 30s 10k"
AHT:FormatMoneyPlain(copper)     -- "5g30s" (kompakt)
AHT:FormatMoneyInput(copper)     -- "5g30s" (für Eingabefelder)
AHT:ParseMoney(str)              -- "5g30s" → copper-Zahl
AHT:GetItemId(link)              -- ItemLink → ItemID
AHT:CountItemInBags(name)        -- Anzahl in allen Taschen
AHT:FindItemInBags(name)         -- (bag, slot) des ersten Stacks
AHT:IsVendorItem(name)           -- Hat Vendor-Preis?
AHT:AddPriceHistory(name, price) -- Preiseintrag + priceUpdated setzen
AHT:GetPriceAverage(name)        -- Durchschnitt der letzten N Scans
AHT:IsDeal(name, price)          -- Ist deutlich unter Durchschnitt?
AHT:CanGetAllScan()              -- GetAll nicht auf Cooldown?
AHT:AddMaterial(name)            -- Material zur Überwachung hinzufügen
AHT:RemoveMaterial(name)         -- Material entfernen
AHT:GetMaterialsList()           -- sortierte Liste aller Materialien
```

**Persistenz:**  
`SaveDB()` speichert alle Tabellen in `ProjEP_AHT_DB` beim Logout.  
`OnLoad()` lädt sie beim Login zurück und füllt Defaults.

**Events:**

Registriert via `ProjEP_AHT_RegisterEvents(self)` (aufgerufen aus dem XML-`OnLoad`):

| Event | Handler |
|---|---|
| `ADDON_LOADED` (für `ProjEP_AH_Trader`) | `OnLoad()` (mit `_loaded`-Dedupe) |
| `VARIABLES_LOADED` | `OnLoad()` (mit `_loaded`-Dedupe) |
| `PLAYER_ENTERING_WORLD` | Minimap-Button + AH-Hook (falls noch nicht angelegt) |
| `PLAYER_LOGOUT` | `SaveDB()` |
| `TRADE_SKILL_SHOW` | `OnTradeSkillShow()` |
| `AUCTION_HOUSE_SHOW` | `[Event AUCTION_HOUSE_SHOW]` + `OnAHShow()` |
| `AUCTION_HOUSE_CLOSED` | `OnAHClosed()` |
| `AUCTION_ITEM_LIST_UPDATE` | `OnAuctionItemListUpdate()` (Dispatcher: GetAll/Mats/Scan) |

**Minimap-Button (`AHT:CreateMinimapButton`):**

- Parent: `UIParent` (nicht `MinimapCluster`, vermeidet Klick-Probleme)
- Strata: `TOOLTIP`, FrameLevel `100` (über allen anderen UI-Layern)
- Größe 40×40 px, gelber Hintergrund + „AHT"-Label, sichtbar links vom Minimap
- `EnableMouse(true)` + `RegisterForClicks("LeftButtonUp", "RightButtonUp")` explizit
- Klick-Handler in zwei `pcall`-Schritten getrennt für gezielte Fehlerlokalisierung
- Hover-Diagnose: druckt einmal `[Minimap-Hover OK]`

---

### 3.2 `Locales.lua`

Vollständige Lokalisierung für **Deutsch (deDE)** und **Englisch (alle anderen)** via `GetLocale()`.

Schlüsselkategorien: allgemein, scan, GetAll, UI-Tabs, Tooltips, Kaufdialog, Post-Dialog, Transmute, Inscription, Jewelcrafting, Mats, Kategorien, Slash-Hilfe, Debug.

Aufruf: `local L = AHT.L` — dann `L["schluessel"]`.

---

### 3.3 `Calculator.lua`

**`AHT:CalcDeposit(itemName, duration)`**  
Berechnet das AH-Deposit für eine Auktion.
- Bevorzugt `GetAuctionDeposit(duration, count, 1)` wenn AH offen
- Fallback: `vendorSellPrice * depositRate * (duration/24)`

**`AHT:CalculateMargins()`**  
Kernfunktion der Alchemie-Analyse. Iteriert über alle `AHT.recipes`, berechnet:
- `ingredCost` – Summe aller Zutatenpreise
- `sellPrice` – günstigstes eigenes Verkaufsangebot (ohne eigene Listings)
- `provision` – AH-Gebühr (5% oder 15%)
- `deposit` – Auktionskaution
- `profit` – `sellPrice - provision - deposit - ingredCost`
- `margin` – `profit / ingredCost * 100`
- `isDeal` – Schnäppchen-Flag (Preis deutlich unter Durchschnitt)

Ergebnis in `AHT.alcResults` (Rohliste), nach `ApplyFilterAndSort()` in `AHT.displayResults`.

**`AHT:ApplyFilterAndSort()`**  
Defensiv implementiert (Stand 1.0.1):
- Sicherer `nil`-Schutz: Einträge ohne `r.name` werden ausgesiebt
- `getKey(x)`-Helper liefert garantiert eine Zahl (Fallback `-1e9` für `nil`/Nicht-Tabellen) – verhindert „attempt to index"-Fehler beim Sortieren
- `table.sort` wird in einem `pcall` ausgeführt; bei Fehler wird Modus, Richtung und Anzahl der Einträge in den Chat geschrieben
- Saubere strict-weak-order-Logik (`if isDesc then return va > vb else return va < vb end` statt der fehleranfälligen `and/or`-Ternary)

---

### 3.4 `Alchemy.lua`

**`AHT:LearnAlchemyRecipes()`**  
Liest alle Alchemie-Rezepte aus dem offenen Berufe-Fenster (`GetTradeSkillInfo`, `GetTradeSkillReagentInfo`). Unterstützt Retry-Logik falls der Item-Cache noch nicht geladen ist. Gefundene Rezepte werden in `AHT.recipes` gespeichert.

**`AHT:OnTradeSkillShow()`** (definiert in `Core.lua`)  
Dispatcht auf `LearnAlchemyRecipes()`, `LearnInscriptionRecipes()`, oder `LearnJewelcraftingRecipes()` je nach Beruf.

---

### 3.5 `Inscription.lua`

**Datenstrukturen:**
- `DEFAULT_MILL_RATES` – Mahl-Raten für alle Northrend-Kräuter (EN + DE Namen)
- `PARCHMENT_COSTS` – Pergamentkosten nach Tier
- Ink-Konstanten für Tinte des Meeres, Schneefallstinte etc.

**`AHT:LearnInscriptionRecipes()`**  
Liest Glyphen-Rezepte aus dem Berufe-Fenster, extrahiert Klasse aus dem Glyphen-Namen.

**`AHT:CalculateInkCosts()`**  
Findet das günstigste Kraut als Tintenquelle basierend auf aktuellen AH-Preisen und den Mahl-Raten.

**`AHT:CalculateGlyphMargins()`**  
Berechnet Gewinn pro Glyph unter Berücksichtigung von Tintenkosten und AH-Gebühr. Ergebnis in `AHT.glyphResults`.

**`AHT:ApplyGlyphFilterAndSort()`**  
Filtert nach Klasse (`AHT.glyphClassFilter`) und sortiert nach Gewinn/Marge.

---

### 3.6 `Transmute.lua`

**`AHT.transmuteData`** – Hardcoded WotLK-Transmutations-Definitionen:
- Titanbarren (Saronit → Titan)
- 6 Epische Edelsteine: Cardinal Ruby, King's Amber, Ametrine, Dreadstone, Eye of Zul, Majestic Zircon

**`AHT:CalculateAllTransmutes()`**  
Berechnet für jede Transmutation:
- `inputCost` – Materialkosten
- `outputValue` – Verkaufserlös (minus AH-Gebühr)
- `profit` – normaler Gewinn
- `profitWithProc` – Gewinn mit Transmutation-Master (+20% erwarteter Extraertrag)

Ergebnis in `AHT.transmuteResults`.

---

### 3.7 `Jewelcrafting.lua`

**`AHT:LearnJewelcraftingRecipes()`**  
Liest Schliff-Rezepte aus dem JC-Berufe-Fenster. Erkennt rohen Edelstein als ersten Reagenten.

**`AHT:CalculateGemCutMargins()`**  
Berechnet Gewinn pro Schliff:
- `ingredCost` – Preis des rohen Edelsteins
- `sellPrice` – Preis des geschliffenen Steins im AH
- `profit` / `margin` – nach AH-Gebühr

Ergebnis in `AHT.gemCutResults` / `AHT.gemCutDisplayResults`.

**`AHT:CalculateProspectingResults(oreAmount)`**  
Prospektions-Simulation: Erz-Menge → erwartete Gem-Ausbeute → bester Schliff → Profit.  
Verwendet `DEFAULT_PROSPECT_RATES` (konfigurierbar via `AHT.prospectRates`):

| Erz | Relevante Gems |
|---|---|
| Kobaltliterz | Häufige Gems (Blutstein, Chalzedon, …) |
| Saroniiterz | Häufige Gems + seltene Epics (sehr niedrig) |
| Titanerz | Epische Gems (Cardinal Ruby, King's Amber, …) |

---

### 3.8 `Buyer.lua`

**Auctionator-Bridge** – delegiert die Materialsuche an das Addon **Auctionator** statt einen eigenen Kauf-Automaten zu betreiben.

> **Voraussetzung:** Das Addon `Auctionator` muss aktiviert sein.

**`AHT:BuyMaterialsViaAuctionator(recipe)`**

Akzeptiert zwei Formen:
- **Rezept-Modus** (`recipe.reagents` vorhanden): Fügt das herzustellende Item **und** alle nicht-Vendor-Zutaten in eine temporäre Auctionator-Einkaufsliste ein.
- **Material-Modus** (nur `recipe.name`, kein `reagents`): Sucht das Item direkt (Mats-Tab).

Ablauf:
1. Temporäre Shopping-List via `Atr_SList.create(recipe.name, false, true)` erstellen
2. Items als `"ItemName"`-Strings eintragen
3. `Atr_SelectPane(3)` – wechselt zum **Buy-Reiter** (BUY_TAB = 3)
4. `Atr_SetSearchText("{ ListenName }")` + `Atr_Search_Onclick()` – startet Scan

> **Hinweis:** `Atr_SearchAH()` wird bewusst **nicht** verwendet, da es intern `Atr_SelectPane(SELL_TAB=1)` aufruft und so den Scan auf dem falschen Reiter (Verkauf statt Kauf) auslöst.

**Stubs** (für rückwärtskompatible Aufrufe aus Core.lua):  
`IsBuying()`, `CancelBuy()`, `IsPosting()`, `CancelPost()`, `IsMatsBuying()`, `CancelMatsBuy()`, alle `On*Update()`-Handler → alle geben `false` zurück bzw. sind No-Ops.

---

### 3.9 `Poster.lua`

Die Poster-Automatik wurde entfernt. Das Einstellen von Auktionen erfolgt manuell direkt über das Auktionshaus oder Auctionator.

Die Datei enthält nur noch den Load-Status-Marker:
```lua
if AHT._loadStatus then AHT._loadStatus.poster = true end
```

---

### 3.10 `Mats.lua`

Rohstoff-Preisüberwachung mit Statistikanalyse:

**`AHT:CalcWeightedMatAverage(name, newPrice)`**  
Exponentieller gleitender Durchschnitt (EMA) mit α = 0.3:

```
neuerWA = alter_WA × 0.7 + neuerPreis × 0.3
```

Neuere Scans werden höher gewichtet, ältere Werte klingen exponentiell ab.

**`AHT:CalculateMatsMargins()`**  
Berechnet für jedes Material:
- `currentPrice` – aktuelles AH-Minimum
- `weighted_avg` – EMA aus `matsHistory`
- `deviation` – Abweichung in % vom gewichteten Durchschnitt (farbcodiert: grün < -20%, rot > +20%)
- `listingCount`, `historyLength`, `lastUpdate`

Ergebnis in `AHT.matsDisplayResults` (gefiltert + sortiert).

**Verwaltungsdialog (`ShowMatsManageDialog`):**  
Materialien per Name hinzufügen oder entfernen.

**Kaufen via Auctionator:**  
Rechtsklick auf eine Zeile im Mats-Tab ruft `AHT:BuyMaterialsViaAuctionator({name=...})` auf, welches Auctionator zum Buy-Reiter wechselt und das Material direkt sucht.

---

### 3.11 `Scanner.lua`

Drei unabhängige Scan-Maschinen:

#### Item-Scan
Scannt Items einzeln (Standard bei offenem Berufe-Fenster).

```
idle → waiting → sent → [AUCTION_ITEM_LIST_UPDATE] → nächstes Item → complete
```

- `StartScan()` – baut Queue aus ausgewählten Rezept-Zutaten + Outputs
- `StartSnipeScan()` – scannt alle Items mit Preishistorie
- Timeout-Behandlung: Items ohne Antwort nach 5s überspringen

#### GetAll-Scan
Einmaliger Vollscan des AH (`QueryAuctionItems(..., getAll=true)`).

- 15-Minuten-Cooldown (`GET_ALL_COOLDOWN = 900`)
- Cooldown-Anzeige im Button-Label: `GetAll (MM:SS)`
- Fallback auf Item-Scan wenn nicht verfügbar
- Nach Abschluss: alle Margen neu berechnen + alle UIs aktualisieren

#### Mats-Scan
Eigene Scan-Queue nur für Rohstoffe:

```
waiting → sent → [AUCTION_ITEM_LIST_UPDATE] → nächstes Mat → complete
```

- `StartMatsScan()` / `CancelMatsScan()` / `IsMatScanning()`
- Nach Abschluss: `CalcWeightedMatAverage()` + `CalculateMatsMargins()` + `RefreshMatsUI()`

**AH-Buttons (werden in `AUCTION_HOUSE_SHOW` erstellt):**

| Button | Funktion |
|---|---|
| Trank-Analyse | Item-Scan starten / Hauptfenster öffnen |
| Mats Analyse | Mats-Scan starten |
| GetAll-Scan | Vollscan starten (mit Cooldown-Anzeige) |
| Transmuten | Transmutations-Fenster öffnen |
| Glyphen | Inschrift-Tab öffnen |
| Edelsteine | JC-Tab öffnen |

---

### 3.12 `UI.lua`

Tabbed-Hauptfenster (780 × 530 px) mit 5 Tabs:

#### Tab 1: Alchemie
- 14 scrollbare Zeilen mit: Rang, Rezeptname, Kosten, Verkauf, AH-Gebühren, Gewinn, Marge, Aktualisierungszeit
- Sortierung nach Gewinn oder Marge (auf/absteigend)
- Suchfeld (Echtzeitfilter)
- Alle-an / Alle-aus Buttons
- Rechtsklick: Auctionator Buy-Reiter öffnen mit Endprodukt + allen Zutaten
- Hover-Tooltip: vollständige Aufschlüsselung (Zutaten, Preise, Gewinn, Trend)

#### Tab 2: Transmuten
- 10 Zeilen: Transmutationsname, Materialkosten, Erlös, Gewinn (inkl. Master-Proc-Bonus)
- Checkbox: Transmutation Master aktivieren/deaktivieren
- Hover-Tooltip: Materialdetails + 20h Cooldown-Hinweis

#### Tab 3: Inschrift
- 12 Zeilen: Glyphenname, Klasse, Tintenkosten, Verkauf, Gewinn, Marge
- Klassenfilter (Textfeld)
- Shift+Rechtsklick: Post-Dialog

#### Tab 4: Schmuckkunst
- 12 Zeilen: Edelstein-Schliff, Roh-Preis, Schliff-Preis, Gewinn, Marge
- Hinweis wenn keine JC-Rezepte vorhanden

#### Tab 5: Materialien
- 12 Zeilen: Materialname, aktueller Preis, gewichteter Durchschnitt, Abweichung, Listings, Scan-Anzahl
- Rechtsklick: Auctionator Buy-Reiter mit dem Material öffnen
- Button: Materialverwaltung öffnen

#### Kaufdialog / Post-Dialog
Entfernt. Kauf wird via Auctionator durchgeführt (Rechtsklick → Buy-Reiter).

**`AHT:RefreshAllUIs()`**  
Aktualisiert den aktiven Tab + alle sichtbaren externen Fenster (Mats-Fenster, JC-Fenster).

---

## 4. WotLK-API-Referenz

### `GetAuctionItemInfo("list", i)` – 18 Felder

```lua
name, texture, count, quality, canUse, level, levelColHeader,
minBid, minIncrement, buyoutPrice, bidAmount, highBidder,
bidderFullName, owner, ownerFullName, saleStatus, itemId, hasAllInfo
= GetAuctionItemInfo("list", i)
```

**Eigene Auktionen erkennen:**
```lua
local player = UnitName("player")
local isOwn  = (owner == player) or
               (ownerFull and ownerFull:match("^" .. player))
```

### `GetAuctionDeposit(duration, maxStack, numStacks)`

```lua
-- duration: 1=12h, 2=24h, 3=48h
local deposit = GetAuctionDeposit(2, stackSize, 1)
```

### `QueryAuctionItems(name, minLevel, maxLevel, invTypeIndex, classIndex, subclassIndex, page, isUsable, qualityIndex, getAll)`

```lua
-- GetAll-Scan:
QueryAuctionItems("", nil, nil, nil, nil, nil, 0, nil, nil, true)

-- Item-Scan:
QueryAuctionItems(itemName, nil, nil, nil, nil, nil, page, nil, nil, false)
```

### `GetItemInfo(itemIdOrName)` – 11 Felder

```lua
name, link, quality, iLevel, reqLevel, class, subclass,
maxStack, equipSlot, texture, vendorSellPrice
= GetItemInfo(itemId)
```

---

## 5. Lua-5.1-Migrationshinweise (vs. Vanilla Lua 5.0)

| Vanilla (Lua 5.0) | WotLK (Lua 5.1) |
|---|---|
| `this` | `self` (in `SetScript`-Callbacks) |
| `getn(t)` | `#t` |
| `mod(a, b)` | `a % b` |
| `tinsert(t, v)` | `table.insert(t, v)` |
| `strfind(s, p)` | `s:find(p)` oder `string.find(s, p)` |
| `strmatch(s, p)` | `s:match(p)` oder `string.match(s, p)` |
| `arg1`, `arg2` in Events | `function(self, event, ...)` + `select()` |

---

## 6. Bekannte Einschränkungen & offene Punkte

### 6.1 AH-Gebührensatz
`AHT.ahCutRate = 0.05` (5%) ist der Standard-Fraktions-AH-Satz.  
Für das Goblin-AH muss auf `0.15` umgestellt werden:

```lua
/aht  -- dann manuell: AHT.ahCutRate = 0.15
```

→ Ein Konfigurations-Slash-Command kann bei Bedarf ergänzt werden.

### 6.2 GetAll-Verfügbarkeit
Der `getAll=true`-Parameter in `QueryAuctionItems` ist in WotLK grundsätzlich verfügbar, kann aber auf manchen privaten Servern deaktiviert sein.  
Das Addon fällt automatisch auf Item-Scans zurück wenn `CanGetAllScan()` `false` zurückgibt.

### 6.3 Prospektions-Raten
Die Raten in `DEFAULT_PROSPECT_RATES` sind empirische Wowhead-WotLK-Werte.  
Server-spezifische Anpassungen können über `AHT.prospectRates` vorgenommen werden (überschreibt Defaults per Item).

### 6.4 Mahl-Raten (Inscription)
Die `DEFAULT_MILL_RATES` in `Inscription.lua` sind WotLK-Standard-Werte.  
Fallen auf Project Epoch ab, können sie in der Datei angepasst werden.

### 6.5 Transmutations-Abklingzeit
Das Addon berechnet keine Echtzeit-Cooldown-Prüfung für Transmutationen.  
Die 20h-Abklingzeit wird nur als Tooltip-Hinweis angezeigt.

---

## 7. Slash-Befehle

Drei gleichwertige Slash-Aliase (zur Vermeidung von Konflikten mit anderen Addons):

```
/aht | /ahtrader | /projepaht
```

```
/aht              Hauptfenster öffnen/schließen
/aht scan         Item-für-Item AH-Scan starten
/aht getall       Vollständigen AH-Scan (GetAll) starten
/aht snipe        Schnäppchen-Scan (Items mit Preishistorie)
/aht stop         Alle laufenden Operationen abbrechen
/aht reset        Alle Preisdaten löschen
/aht mats         Materialverwaltungs-Dialog öffnen
/aht rezepte      Geladene Alchemie-Rezepte auflisten
/aht master       Transmutation Master umschalten
/aht debug        Diagnose-Informationen ausgeben
```

Die Slash-Befehle sind **doppelt registriert**: einmal beim Laden von `Core.lua` (Top-Level) und ein zweites Mal in `OnLoad()` als defensive Absicherung. Beim Aufruf druckt der Handler `[Slash-Handler erreicht] msg='...'` zur Bestätigung.

---

## 8. Installations- & Nutzungsanleitung

### Installation
1. Ordner `ProjEP_AH_Trader` nach `WoW/Interface/AddOns/` kopieren
2. WoW (Project Epoch) starten
3. Im Charakter-Auswahl-Bildschirm prüfen ob das Addon aktiviert ist

### Ersteinrichtung

**Alchemie-Rezepte laden:**
1. Alchemie-Fenster öffnen (Tastenkürzel: K → Alchemie → Öffnen)
2. Addon lädt automatisch alle gelernten Rezepte
3. Meldung: `X Rezepte geladen`

**Inschriften-Glyphen laden:**
1. Inschriftenkunde-Fenster öffnen
2. Addon lädt automatisch alle Glyphen-Rezepte

**JC-Schliffe laden:**
1. Schmuckkunst-Fenster öffnen
2. Addon lädt alle bekannten Schliff-Rezepte

**Materialien hinzufügen:**
```
/aht mats
```
Dann im Dialog Materialnamen eingeben und „Hinzufügen" klicken.

### Auktionshaus-Nutzung

1. AH öffnen → Buttons erscheinen automatisch
2. **Trank-Analyse** → Item-Scan starten
3. Nach Scan: Hauptfenster öffnet sich automatisch
4. Ergebnisse nach Gewinn/Marge sortiert
5. Rechtsklick auf Zeile → Auctionator Buy-Reiter mit Endprodukt + Zutaten

### GetAll-Scan (empfohlen)
- **GetAll-Scan**-Button klicken
- Scannt das gesamte AH in einem Durchgang
- 15-Minuten-Cooldown (Anzeige im Button: `GetAll (MM:SS)`)
- Aktualisiert automatisch alle Tabs

---

## 9. Datenbankstruktur (SavedVariables)

```lua
ProjEP_AHT_DB = {
    prices         = {},    -- [itemName] = copper
    priceHistory   = {},    -- [itemName] = [{t, p}]
    priceUpdated   = {},    -- [itemName] = timestamp
    listingCounts  = {},    -- [itemName] = count
    recipes        = {},    -- Alchemie-Rezepte
    selected       = {},    -- Alchemie-Auswahl
    glyphs         = {},    -- Glyphen-Rezepte
    glyphSelected  = {},    -- Glyphen-Auswahl
    gemCuts        = {},    -- JC-Schliff-Rezepte
    gemCutSelected = {},    -- JC-Auswahl
    materials      = {},    -- Rohstoff-Definitionen
    matsSelected   = {},    -- Rohstoff-Auswahl
    matsHistory    = {},    -- [{t, p, weighted_avg}]
    transmuteResults={},    -- Transmutations-Ergebnisse
    isMasterAlch   = false,
    ahCutRate      = 0.05,
    getAllLastTime  = 0,
    sortMode       = "profit",
    sortDir        = "desc",
    activeTab      = "alchemy",
    gemCutSortMode = "profit",
    gemCutSortDir  = "desc",
    matsSortMode   = "deviation",
    matsSortDir    = "desc",
}
```

---

## 10. Entwicklungshistorie

| Version | Änderung |
|---|---|
| 1.0.0 | Vollständige WotLK-Migration von TWOW_AH_Trader |
| | Neue Module: Inscription, Transmute, Jewelcrafting, Mats |
| | GetAll-Scan mit 15-Minuten-Cooldown |
| | EMA-gewichteter Materialdurchschnitt (α=0.3) |
| | Tabbed-UI mit 5 Tabs |
| | WotLK-API: 18-Feld-GetAuctionItemInfo, GetAuctionDeposit |
| 1.0.1 | XML-basierter Event-Frame (`ProjEP_AH_Trader.xml`) statt Lua-`CreateFrame` für zuverlässiges Event-Routing auf Project Epoch |
| | Diagnostik-Marker `[AHT-DIAG]` am Ende jeder Lua-Datei (`AHT._loadStatus`) |
| | Slash-Befehle defensiv doppelt registriert (Top-Level + `OnLoad`) plus dritter Alias `/projepaht` |
| | Minimap-Button: gelb, „AHT"-Label, Strata `TOOLTIP`, links neben dem Minimap (RIGHT/LEFT-Anker), `EnableMouse` + `RegisterForClicks` explizit gesetzt |
| | `ApplyFilterAndSort()` defensiv: `nil`-Filter, `getKey()`-Helper, `pcall`-geschütztes `table.sort`, saubere strict-weak-order-Logik |
| | Click-Handler des Minimap-Buttons mit getrennten `pcall`-Schritten (`Schritt 1: CalculateMargins`, `Schritt 2: ShowUI`) für gezielte Fehlerlokalisierung |
| 1.1.0 | **Auctionator-Integration:** Kauf-/Post-Automatik vollständig entfernt |
| | `Buyer.lua` ersetzt durch Auctionator-Bridge `BuyMaterialsViaAuctionator()` |
| | `Poster.lua` auf Stub reduziert |
| | Rechtsklick (alle Tabs): öffnet Auctionator Buy-Reiter mit Endprodukt + Zutaten |
| | Rechtsklick (Mats-Tab): öffnet Auctionator Buy-Reiter für das Material |
| | `Atr_SelectPane(3)` statt `Atr_SearchAH()` – wechselt korrekt zum Buy-Reiter (BUY_TAB=3) |
| | Core.lua: Events `CHAT_MSG_SYSTEM`, `NEW_AUCTION_UPDATE`, `UI_ERROR_MESSAGE` abgemeldet |
| | `OnAHClosed`, `ProjEP_AHT_OnUpdate`, `/stop`-Befehl von Buy/Post-Referenzen bereinigt |

---

## 11. Diagnose & Fehlerbehebung

### 11.1 Lade-Status-Marker (`AHT._loadStatus`)

Jede `.lua`-Datei setzt am Ende einen Marker und schreibt in den Chat:

```
[AHT-DIAG] Core.lua TOP
[AHT-DIAG] Locales.lua OK
[AHT-DIAG] Calculator.lua OK
... (für jedes Modul)
[AHT-DIAG] UI.lua OK
[AHT-DIAG] Core.lua END (slash=true)
```

Beim Aufruf von `OnLoad()` wird zusätzlich eine kompakte Übersicht aller Module + Slash-Status ausgegeben:

```
[AHT-DIAG] Module-Load: core=true locales=true calc=true alch=true inscr=true
transm=true jc=true buyer=true poster=true mats=true scanner=true ui=true slash=true
```

**Diagnose-Pfad:**
- Fehlt `Core.lua END` → Syntaxfehler oder Laufzeitfehler in `Core.lua`
- Fehlt eines der Modul-`OK`s → das vorherige Modul hat einen Fehler verursacht
- `slash=false` → `SLASH_PROJEP_AHT1` wurde überschrieben oder Core.lua nicht vollständig geladen

### 11.2 Click- und Slash-Handler-Bestätigung

| Trigger | Erwartete Ausgabe |
|---|---|
| Minimap-Hover | `[Minimap-Hover OK]` (einmal pro Session) |
| Minimap-Klick | `[Minimap-Klick] button=LeftButton recipes=N results=M` |
| `/aht` (alle Aliase) | `[Slash-Handler erreicht] msg='...'` |
| AH öffnen | `[Event AUCTION_HOUSE_SHOW]` |

### 11.3 Click-Pfad-Diagnose

Der Minimap-Klick ist in zwei `pcall`-geschützte Schritte zerlegt:

```
[Minimap-Klick] button=LeftButton recipes=42 results=0
Schritt 1: CalculateMargins...
  CalculateMargins OK (results=42)
Schritt 2: ShowUI...
[ShowUI() aufgerufen]
Build-Schritte starten...
  EnsureTabs OK
  AlcHeader OK
  AlcRows OK
  BottomBtns OK
mainFrame visible=true, point=CENTER
```

Bricht einer der Schritte ab, erscheint die rote Fehlerzeile (`CalculateMargins-Fehler:` oder `ShowUI-Fehler:`) mit Datei und Zeilennummer.

### 11.4 Häufige Probleme

| Symptom | Ursache | Behebung |
|---|---|---|
| Keine `[AHT-DIAG]`-Meldungen | Addon nicht aktiviert oder TOC fehlerhaft | Im AddOn-Menü aktivieren, TOC prüfen |
| Nur `Core.lua TOP`, sonst nichts | Syntaxfehler in `Core.lua` | Letzte Änderung rückgängig machen |
| `slash=false` in Übersicht | Anderes Addon überschreibt `SLASH_PROJEP_AHT1` | `/projepaht` als Alternative nutzen |
| Klick auf Minimap-Button reagiert nicht | Frame von anderem Frame überdeckt | Strata `TOOLTIP` + `FrameLevel 100` löst das |
| Klick erkannt, aber rote Fehlermeldung | Laufzeitfehler in `CalculateMargins`/`ShowUI` | Fehlerzeile lesen → Datei/Zeile prüfen |
| `attempt to call method '...'` auf Frame | Locale-Key fehlt oder Frame nil | `Locales.lua` prüfen, defensives `nil`-Check ergänzen |

### 11.5 Deployment

```powershell
powershell.exe -ExecutionPolicy Bypass -File "<repo>\deploy.ps1"
```

Kopiert alle `*.lua`, `*.toc`, `*.xml` (außer `deploy.ps1` selbst) nach:

```
C:\Ascension\Launcher\resources\epoch-live\Interface\AddOns\ProjEP_AH_Trader\
```

Anschließend in WoW: `/reload` oder `/console reloadui`.
