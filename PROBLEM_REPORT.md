# ProjEP AH Trader – Fehlerbericht & Aufgabe für Claude Opus 4.7

## Ziel

Das WoW-Addon **ProjEP AH Trader** soll auf dem privaten Server **Project Epoch** (WoW WotLK 3.3.5a, Lua 5.1) korrekt laden und:

1. Beim Einloggen eine Chat-Nachricht ausgeben: `[AH Trader] v1.0.0 geladen. /aht für Hilfe.`
2. Einen Minimap-Button anzeigen (Klick öffnet das Hauptfenster)
3. Beim Öffnen des Auktionshauses Buttons in der AH-Titelleiste anzeigen (Scan, Mats, GetAll, Transmutes, Glyphs, Gems)

## Problem

**Das Addon tut beim Einloggen absolut nichts.** Keine Chat-Nachricht, kein Minimap-Button, keine AH-Buttons. Das Addon ist in der Addon-Liste des Spiels sichtbar und aktiviert, wird aber offenbar nie ausgeführt.

## Umgebung

- **Server:** Project Epoch (WoW WotLK 3.3.5a Custom Server)
- **Client-Version:** WoW 3.3.5a (Build 12340)
- **Interface-Nummer:** `30300` (bestätigt durch funktionierendes Referenz-Addon Auctionator)
- **Addon-Pfad:** `C:\Ascension\Launcher\resources\epoch-live\Interface\AddOns\ProjEP_AH_Trader\`
- **Lua-Version:** 5.1

## Referenz-Addon (funktioniert)

Das Addon **Auctionator** funktioniert auf demselben Server einwandfrei. Es nutzt:

- `## Interface: 30300` in der `.toc`
- Eine **XML-Datei** (`Auctionator.xml`) mit einem `<Frame>` und `<OnLoad>` Script
- `<OnLoad>` ruft eine **globale Funktion** `Atr_RegisterEvents(self)` auf
- Diese registriert Events inkl. `VARIABLES_LOADED` und `ADDON_LOADED`

```xml
<Frame name="Atr_core">
  <Scripts>
    <OnLoad>Atr_RegisterEvents(self);</OnLoad>
    <OnUpdate>Atr_OnUpdate(self, elapsed);</OnUpdate>
    <OnEvent>Atr_EventHandler(self, event, ...);</OnEvent>
  </Scripts>
</Frame>
```

## Aktueller Stand des Addons

### Dateistruktur

```
ProjEP_AH_Trader/
├── ProjEP_AH_Trader.toc
├── ProjEP_AH_Trader.xml   ← NEU hinzugefügt (nach Auctionator-Muster)
├── Core.lua               ← Hauptlogik, Event-Handler
├── Locales.lua
├── Calculator.lua
├── Alchemy.lua
├── Inscription.lua
├── Transmute.lua
├── Jewelcrafting.lua
├── Buyer.lua
├── Poster.lua
├── Mats.lua
├── Scanner.lua            ← AH-Buttons + OnAHShow()
└── UI.lua
```

### ProjEP_AH_Trader.toc (aktuell)

```
## Interface: 30300
## Title: ProjEP AH Trader
## Notes: AH-Analyse fuer Alchemie, Inschriftenkunde und Schmuckkunst (Project Epoch / WotLK 3.3.5)
## Author: ProjEP_AHT
## Version: 1.0.0
## SavedVariables: ProjEP_AHT_DB

Core.lua
Locales.lua
Calculator.lua
Alchemy.lua
Inscription.lua
Transmute.lua
Jewelcrafting.lua
Buyer.lua
Poster.lua
Mats.lua
Scanner.lua
UI.lua
ProjEP_AH_Trader.xml
```

### ProjEP_AH_Trader.xml (aktuell)

```xml
<Ui xmlns="http://www.blizzard.com/wow/ui/"
   xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
   xsi:schemaLocation="http://www.blizzard.com/wow/ui/">

  <Frame name="ProjEP_AHT_EventFrame">
    <Scripts>
      <OnLoad>
        ProjEP_AHT_RegisterEvents(self);
      </OnLoad>
      <OnUpdate>
        ProjEP_AHT_OnUpdate(self, elapsed);
      </OnUpdate>
      <OnEvent>
        ProjEP_AHT_OnEvent(self, event, ...);
      </OnEvent>
    </Scripts>
  </Frame>

</Ui>
```

### Core.lua – relevante Abschnitte

**Globales Objekt:**
```lua
PROJEP_AHT = {}
local AHT = PROJEP_AHT
```

**OnLoad (wird von Event aufgerufen):**
```lua
function AHT:OnLoad()
    -- SavedVariables laden...
    AHT:Print(string.format(AHT.L["addon_loaded"], AHT.VERSION))
    local ok, err = pcall(function() AHT:CreateMinimapButton() end)
    if not ok then AHT:Print("MinimapBtn Fehler: " .. tostring(err)) end
end
```

**Globale Event-Funktionen (nach Auctionator-Muster):**
```lua
function ProjEP_AHT_RegisterEvents(self)
    self:RegisterEvent("ADDON_LOADED")
    self:RegisterEvent("VARIABLES_LOADED")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("PLAYER_LOGOUT")
    self:RegisterEvent("TRADE_SKILL_SHOW")
    self:RegisterEvent("AUCTION_HOUSE_SHOW")
    self:RegisterEvent("AUCTION_HOUSE_CLOSED")
    self:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
    self:RegisterEvent("CHAT_MSG_SYSTEM")
    self:RegisterEvent("NEW_AUCTION_UPDATE")
    self:RegisterEvent("UI_ERROR_MESSAGE")
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
        if not AHT.minimapBtn then
            local ok, err = pcall(function() AHT:CreateMinimapButton() end)
            if not ok then AHT:Print("MinimapBtn Fehler: " .. tostring(err)) end
        end
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
        local ok, err = pcall(function() AHT:OnAHShow() end)
        if not ok then AHT:Print("OnAHShow Fehler: " .. tostring(err)) end
    -- ... weitere Events
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
    -- ... weitere OnUpdate-Logik
end
```

**Minimap-Button:**
```lua
function AHT:CreateMinimapButton()
    if AHT.minimapBtn then return end
    local btn = CreateFrame("Button", "ProjEP_AHT_MinimapBtn", MinimapCluster or Minimap)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:SetSize(24, 24)
    btn:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -4, 4)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
    btn:SetScript("OnClick", function()
        if #AHT.recipes > 0 then AHT:CalculateMargins() end
        AHT:ShowUI()
    end)
    btn:Show()
    AHT.minimapBtn = btn
    AHT:Print("Minimap-Button erstellt.")
end
```

### Scanner.lua – AH-Buttons

```lua
function AHT:OnAHShow()
    AHT:RefreshAuctionQueryCaches()
    local ok, err
    ok, err = pcall(function() AHT:CreateScanButton() end)
    if not ok then AHT:Print("ScanBtn Fehler: " .. tostring(err)) end
    -- ... weitere Buttons
end

function AHT:CreateScanButton()
    if AHT.scanButton then AHT.scanButton:Show(); return end
    local btn = CreateFrame("Button", "ProjEP_AHT_ScanBtn", AuctionFrame, "UIPanelButtonTemplate")
    btn:SetSize(130, 22)
    btn:SetText(AHT.L["scan_button"])
    btn:SetPoint("TOPLEFT", AuctionFrame, "TOPLEFT", 70, -28)
    -- ...
    AHT.scanButton = btn
end
```

## Was bisher versucht wurde (ohne Erfolg)

| Versuch | Ergebnis |
|---|---|
| `VARIABLES_LOADED` Event per `CreateFrame` in Lua | Kein Output |
| `ADDON_LOADED` Event hinzugefügt | Kein Output |
| `PLAYER_ENTERING_WORLD` Event hinzugefügt | Kein Output |
| `AuctionFrame:HookScript("OnShow")` | Keine Buttons |
| Interface-Version auf `30305` geändert | Kein Output |
| Interface-Version zurück auf `30300` | Kein Output |
| XML-Datei nach Auctionator-Muster erstellt | Kein Output |
| `pcall` um alle kritischen Calls | Keine Fehler sichtbar |
| Minimap-Button mit verschiedenen Texturen | Kein Button |

## Schlüsselfrage

**Warum wird die Nachricht `[AH Trader] v1.0.0 geladen.` nie im Chat ausgegeben**, obwohl:
- Das Addon in der Addon-Liste aktiviert ist
- Die Struktur identisch mit Auctionator ist (das funktioniert)
- `AHT:Print()` einfach `DEFAULT_CHAT_FRAME:AddMessage(...)` aufruft

## Vermutete Ursachen (zur Prüfung)

1. **Lua-Syntaxfehler** in einer der `.lua`-Dateien verhindert das Laden – da Project Epoch keinen Lua-Error-Handler anzeigt, bleibt es still
2. **Reihenfolge in der TOC**: `ProjEP_AH_Trader.xml` steht am Ende – evtl. muss es früher stehen
3. **`PROJEP_AHT` ist zum Zeitpunkt des XML-OnLoad noch nil** weil Core.lua zuerst lädt, aber `PROJEP_AHT` lokal ist
4. **`AHT.L` ist nil** wenn `OnLoad` aufgerufen wird (Locales.lua lädt nach Core.lua, aber `AHT.L["addon_loaded"]` könnte nil sein und `string.format` crashen)

## Aufgabe für Claude Opus 4.7

1. **Prüfe alle `.lua`-Dateien auf Syntax-Fehler** (besonders Core.lua, Locales.lua)
2. **Identifiziere warum `AHT:OnLoad()` nie aufgerufen wird** – tracke den Pfad von XML-OnLoad → `ProjEP_AHT_RegisterEvents` → Event → `AHT:OnLoad()`
3. **Prüfe speziell**: Ist `AHT.L` bereits befüllt wenn `OnLoad` läuft? `Locales.lua` lädt nach `Core.lua` in der TOC – ist `AHT.L["addon_loaded"]` in `OnLoad` verfügbar?
4. **Fixe das Problem** so dass beim Einloggen mindestens die Chat-Nachricht erscheint
5. **Stelle sicher** dass AH-Buttons erscheinen wenn das Auktionshaus geöffnet wird
6. **Deploy** via `deploy.ps1` nach: `C:\Ascension\Launcher\resources\epoch-live\Interface\AddOns\ProjEP_AH_Trader\`

## Deploy-Befehl

```powershell
powershell.exe -ExecutionPolicy Bypass -File "c:\Users\daosm\GitHub\all-repos\ProjEP_AH_Trader\deploy.ps1"
```

## Wichtige Randbedingungen

- **Lua 5.1** – kein `#` für Stringlänge, kein `goto`, kein `table.pack`
- **WoW 3.3.5a API** – `CreateFrame`, `UIParent`, `GameTooltip`, `AuctionFrame`, `DEFAULT_CHAT_FRAME`
- **Kein externen Libs** wie LibStub, AceAddon etc.
- **Globales Objekt** heißt `PROJEP_AHT`, lokaler Alias `AHT` in jeder Datei via `local AHT = PROJEP_AHT`
- Änderungen müssen in **allen betroffenen Dateien** konsistent sein
