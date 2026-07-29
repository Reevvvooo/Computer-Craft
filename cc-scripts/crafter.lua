-- crafter.lua
-- Versorgt eine externe Craft-Anlage (erster Anwendungsfall: eine Create
-- Sequenced Assembly fuer Precision Mechanisms) mit Zutaten-Sets und legt
-- bei fehlgeschlagenen Crafts automatisch nach, bis die bestellte Menge
-- fertig ist oder das Material ausgeht.
--
-- Laeuft auf einem NORMALEN COMPUTER, nicht auf einer Turtle: Turtles
-- koennen benachbarte Inventare nicht als Peripheral ansprechen (links und
-- rechts sind dort die eigenen Upgrade-Slots) und damit keine bestimmten
-- Item-IDs in bestimmten Mengen entnehmen. Das Crafting macht die Anlage,
-- nicht der Computer -- Turtle-Faehigkeiten braucht es also nicht.
--
-- Aufbau:
--
--     [Storage] [Computer] [Ziel]
--
--   links  (STORAGE_SIDE) : Inventar mit den Zutaten
--   rechts (TARGET_SIDE)  : Inventar, aus dem sich die Anlage bedient
--   hinten (FAIL_SIDE)    : Redstone, 1 Impuls je FEHLGESCHLAGENEM Craft
--   unten  (SUCCESS_SIDE) : Redstone, 1 Impuls je FERTIGEM Endprodukt
--
-- "links" und "rechts" gelten aus Sicht des Computers und sind damit
-- gespiegelt zur Spieleransicht. Sind die Seiten vertauscht, einfach die
-- beiden Konstanten unten tauschen.
--
-- Die Impulse muessen mindestens EXPECTED_PULSE_TICKS Ticks breit sein. Ein
-- 1-Tick-Impuls kann verloren gehen, weil steigende und fallende Flanke im
-- selben Tick liegen und redstone.getInput() beim Verarbeiten des Events
-- schon wieder false liefern kann. In Create notfalls mit einem Pulse
-- Repeater verbreitern.
--
-- Aufruf:
--   crafter.lua        -- fragt die Anzahl interaktiv ab
--   crafter.lua 5      -- 5 Endprodukte mit dem Rezept aus DEFAULT_RECIPE
--   crafter.lua 5 modid:a=1 modid:b=5
--                      -- 5 Endprodukte; die id=Menge-Argumente ERSETZEN
--                         DEFAULT_RECIPE komplett (beliebig viele Zutaten)

local STORAGE_SIDE = "left"
local TARGET_SIDE = "right"
local FAIL_SIDE = "back"
local SUCCESS_SIDE = "bottom"

-- Nur Dokumentation und Diagnose. Es wird absichtlich NICHT entprellt --
-- eine Entprellung wuerde dicht aufeinanderfolgende echte Impulse
-- verschlucken und damit Fehlschlaege uebersehen.
local EXPECTED_PULSE_TICKS = 2

-- HIER ANPASSEN: Zutaten pro EINEM fertigen Endprodukt. Die IDs muessen
-- exakt den Minecraft-Item-IDs entsprechen (im Spiel per F3+H sichtbar
-- machen). Die Liste darf beliebig viele Zutaten enthalten.
local DEFAULT_RECIPE = {
  { id = "modid:zutat_a", count = 1 },
  { id = "modid:zutat_b", count = 1 },
  { id = "modid:zutat_c", count = 1 },
  { id = "modid:zutat_d", count = 1 },
}

local USAGE = "Benutzung: crafter.lua [Anzahl] [item:id=Menge ...]"

local function askInt(label, min, max)
  while true do
    io.write(label .. ": ")
    local value = tonumber(read())
    if value and value >= min and (not max or value <= max) and value == math.floor(value) then
      return value
    end
    print(string.format("Bitte eine ganze Zahl zwischen %d und %s eingeben.", min, max and tostring(max) or "beliebig"))
  end
end

-- Argumente lesen: erstes Argument ist die Anzahl, alle id=Menge-Argumente
-- bilden zusammen das Rezept.
local args = { ... }
local orderSize = nil
local recipe = {}

for index, value in ipairs(args) do
  local id, count = value:match("^(.+)=(%d+)$")
  if id then
    table.insert(recipe, { id = id, count = tonumber(count) })
  elseif index == 1 then
    orderSize = tonumber(value)
    if not orderSize or orderSize < 1 or orderSize ~= math.floor(orderSize) then
      printError("Anzahl muss eine ganze Zahl >= 1 sein. " .. USAGE)
      return
    end
  else
    printError("Ungueltiges Argument: " .. value .. ". " .. USAGE)
    return
  end
end

if #recipe == 0 then
  recipe = DEFAULT_RECIPE
end

for _, ingredient in ipairs(recipe) do
  if ingredient.count < 1 then
    printError("Menge fuer " .. ingredient.id .. " muss >= 1 sein. " .. USAGE)
    return
  end
  if ingredient.id:match("^modid:") then
    printError("DEFAULT_RECIPE enthaelt noch Platzhalter (modid:...).")
    printError("Bitte die echten Item-IDs und Mengen oben im Skript eintragen")
    printError("oder per Argument uebergeben, z.B.:")
    printError("  crafter.lua 5 create:golden_sheet=1 create:cogwheel=5")
    return
  end
end

local storageInv = peripheral.wrap(STORAGE_SIDE)
if not storageInv or not storageInv.list or not storageInv.pushItems then
  printError(string.format(
    "Auf Seite '%s' ist kein Inventar. Dort muss das Storage mit den Zutaten stehen.", STORAGE_SIDE))
  return
end

local targetInv = peripheral.wrap(TARGET_SIDE)
if not targetInv or not targetInv.list then
  printError(string.format(
    "Auf Seite '%s' ist kein Inventar. Dort muss das Zielinventar der Anlage stehen.", TARGET_SIDE))
  return
end

if not orderSize then
  print(string.format("Crafter: gibt Zutaten-Sets von '%s' nach '%s'.", STORAGE_SIDE, TARGET_SIDE))
  orderSize = askInt("Anzahl der gewuenschten Endprodukte", 1)
end

-- Zaehlt alle Items im Storage zu name -> Gesamtmenge zusammen.
local function countAvailable()
  local available = {}
  for _, item in pairs(storageInv.list()) do
    available[item.name] = (available[item.name] or 0) + item.count
  end
  return available
end

-- Wie viele vollstaendige Sets liegen im Storage? Gibt zusaetzlich die
-- knappste Zutat zurueck, damit Warnungen konkret werden.
local function maxSets()
  local available = countAvailable()
  local sets = nil
  local scarcest = recipe[1].id
  for _, ingredient in ipairs(recipe) do
    local possible = math.floor((available[ingredient.id] or 0) / ingredient.count)
    if sets == nil or possible < sets then
      sets = possible
      scarcest = ingredient.id
    end
  end
  return sets or 0, scarcest
end

-- Gibt `sets` komplette Zutaten-Sets ins Zielinventar. Rueckgabe: Anzahl
-- der tatsaechlich vollstaendig uebergebenen Sets. Der Rueckgabewert von
-- pushItems ist die einzige verlaessliche Quelle fuer die bewegte Menge --
-- er ist kleiner als angefordert, wenn das Zielinventar voll ist.
--
-- Aufgerufen wird nur mit einer Menge, fuer die maxSets() genug von JEDER
-- Zutat gesehen hat. Ein Fehlbetrag kann daher nur vom vollen Zielinventar
-- kommen. Dann kann es passieren, dass von einer Zutat schon mehr drin ist
-- als von einer anderen; der Ueberschuss bleibt im Zielinventar liegen und
-- wird von den folgenden Sets mitverbraucht.
local function pushSets(sets)
  local completeSets = nil
  for _, ingredient in ipairs(recipe) do
    local wanted = ingredient.count * sets
    local moved = 0
    for slot, item in pairs(storageInv.list()) do
      if moved >= wanted then
        break
      end
      if item.name == ingredient.id then
        local justMoved = storageInv.pushItems(TARGET_SIDE, slot, math.min(wanted - moved, item.count)) or 0
        moved = moved + justMoved
        if justMoved == 0 then
          -- Ziel nimmt nichts mehr an, weitere Slots zu probieren ist zwecklos.
          break
        end
      end
    end
    if moved < wanted then
      print(string.format("Warnung: nur %d von %d %s uebergeben.", moved, wanted, ingredient.id))
    end
    local possible = math.floor(moved / ingredient.count)
    if completeSets == nil or possible < completeSets then
      completeSets = possible
    end
  end
  return completeSets or 0
end

local done = 0
local failed = 0
local dispatched = 0
local finishReason = nil

local function inFlight()
  return dispatched - done - failed
end

-- Legt so viele Sets nach, wie noch fehlen und wie das Material hergibt.
-- Was schon in der Anlage steckt, wird mitgerechnet, damit nicht doppelt
-- ausgegeben wird. Wird nichts gebraucht, passiert nichts.
local function topUp()
  local needed = orderSize - done - inFlight()
  if needed <= 0 then
    return
  end

  local available, scarcest = maxSets()
  if available <= 0 then
    print(string.format("Kein Material fuer ein weiteres Set (es fehlt %s).", scarcest))
    return
  end
  if available < needed then
    print(string.format("Nur Material fuer %d von %d noch benoetigten Sets (knappste Zutat: %s).",
      available, needed, scarcest))
  end

  local pushed = pushSets(math.min(needed, available))
  dispatched = dispatched + pushed
  if pushed > 0 then
    print(string.format("%d Set(s) ins Zielinventar gegeben.", pushed))
  else
    print("Es konnte kein vollstaendiges Set uebergeben werden (Zielinventar voll?).")
  end
end

local function run()
  print("Rezept pro Endprodukt:")
  for _, ingredient in ipairs(recipe) do
    print(string.format("  %s x%d", ingredient.id, ingredient.count))
  end
  print(string.format("Auftrag: %d Endprodukt(e). Erwartete Impulsbreite: %d Ticks.",
    orderSize, EXPECTED_PULSE_TICKS))

  topUp()
  if dispatched == 0 then
    finishReason = "Kein Set uebergeben - Auftrag nicht gestartet."
    return
  end

  print("Warte auf Rueckmeldungen der Anlage (Abbruch mit Strg+T) ...")

  local prevFail = redstone.getInput(FAIL_SIDE)
  local prevSuccess = redstone.getInput(SUCCESS_SIDE)

  while true do
    os.pullEvent("redstone")
    local failNow = redstone.getInput(FAIL_SIDE)
    local successNow = redstone.getInput(SUCCESS_SIDE)

    -- Reine Flankenzaehlung: nur der Wechsel low -> high zaehlt, ein
    -- Dauersignal also genau einmal. Beide Seiten koennen im selben Event
    -- wechseln, daher werden immer beide geprueft.
    local risingSuccess = successNow and not prevSuccess
    local risingFail = failNow and not prevFail
    prevSuccess, prevFail = successNow, failNow

    if risingSuccess then
      done = done + 1
    end
    if risingFail then
      failed = failed + 1
    end

    if risingSuccess or risingFail then
      print(string.format("[%d/%d fertig | %d Fehlschlaege | %d in Arbeit]",
        done, orderSize, failed, inFlight()))

      if done >= orderSize then
        finishReason = "Auftrag komplett."
        return
      end

      -- Nach jeder Rueckmeldung nachlegen. Bei einem Fehlschlag fehlt genau
      -- ein Set; nach einem Erfolg ist normalerweise nichts zu tun, aber
      -- falls frueher wegen Materialmangel nicht nachgelegt werden konnte,
      -- wird es hier mit inzwischen nachgefuelltem Material aufgeholt.
      topUp()

      if inFlight() <= 0 then
        finishReason = string.format("Material erschoepft - %d von %d Endprodukt(en) fertig.",
          done, orderSize)
        return
      end
    end
  end
end

local ok, err = pcall(run)

print("--- Zusammenfassung ---")
print(string.format("Fertige Endprodukte:      %d von %d", done, orderSize))
print(string.format("Fehlgeschlagene Crafts:   %d", failed))
print(string.format("Ausgegebene Zutaten-Sets: %d", dispatched))
if inFlight() > 0 then
  print(string.format("Noch in der Anlage:       %d Set(s)", inFlight()))
end
if finishReason then
  print(finishReason)
end
if not ok then
  printError("Abbruch: " .. tostring(err))
end
