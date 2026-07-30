-- mechanism.lua
-- Faehrt eine Create Sequenced Assembly Schritt fuer Schritt selbst und stellt
-- damit Precision Mechanisms her. Der Computer holt die Zutaten mit fest
-- hinterlegten Item-IDs aus einer Kiste, legt die Basis aufs Depot, gibt dem
-- Deployer immer genau EIN Item, wartet bis es verbraucht ist, und raeumt das
-- Ergebnis am Ende zurueck in die Kiste.
--
-- Unterschied zu crafter.lua: dort craftet die Anlage selbst und meldet nur per
-- Redstone-Impuls "fertig" oder "fehlgeschlagen". Hier kennt und kontrolliert
-- der Computer jeden einzelnen Deploy-Schritt.
--
-- Laeuft auf einem NORMALEN COMPUTER, nicht auf einer Turtle: Turtles koennen
-- benachbarte Inventare nicht als Peripheral ansprechen (links und rechts sind
-- dort die eigenen Upgrade-Slots) und damit keine bestimmten Item-IDs in
-- bestimmten Mengen entnehmen. Turtle-Faehigkeiten braucht es hier nicht --
-- das Deployen macht der Create-Deployer.
--
-- Aufbau (Kreuzanordnung, KEINE Wired Modems noetig):
--
--          [Deployer]     oben   (DEPLOYER_SIDE)
--               |
--   [Kiste] [Computer]    links  (CHEST_SIDE)
--               |
--          [ Depot  ]     unten  (DEPOT_SIDE)
--
-- Deployer und Depot haben einen Block Abstand, dazwischen sitzt der Computer.
-- Der Deployer reicht durch den Computer hindurch bis aufs Depot. Er muss auf
-- "Use" stehen (nicht "Punch") und Rotationskraft bekommen. Weil alle drei
-- Inventare direkt am Computer haengen, koennen sie ohne Netzwerkkabel
-- untereinander schieben.
--
-- "links" und "rechts" gelten aus Sicht des Computers und sind damit
-- gespiegelt zur Spieleransicht. Sind die Seiten vertauscht, einfach die
-- Konstanten unten tauschen.
--
-- Aufruf:
--   mechanism.lua      -- fragt die Anzahl interaktiv ab
--   mechanism.lua 5    -- 5 Precision Mechanisms

local CHEST_SIDE = "left"
local DEPOT_SIDE = "bottom"
local DEPLOYER_SIDE = "top"

-- HIER ANPASSEN, falls das Modpack abweichende IDs benutzt (im Spiel per F3+H
-- sichtbar machen).
local BASE_ITEM = "create:golden_sheet"
local PROGRESS_ITEM = "create:incomplete_precision_mechanism"
local RESULT_ITEM = "create:precision_mechanism"

-- Die Reihenfolge ist zwingend: jeder Schritt muss zum naechsten Schritt der
-- Sequenced Assembly passen. LOOPS Durchlaeufe ergeben #SEQUENCE * LOOPS
-- Deploy-Schritte.
local SEQUENCE = {
  "create:cogwheel",
  "create:large_cogwheel",
  "minecraft:iron_nugget",
}
local LOOPS = 5

-- Sekunden, die ein einzelner Deploy-Schritt hoechstens dauern darf. Danach
-- wird mit einer Diagnose abgebrochen, statt endlos zu warten.
local STEP_TIMEOUT = 30
local POLL_INTERVAL = 0.2

local USAGE = "Benutzung: mechanism.lua [Anzahl]"

local TOTAL_STEPS = #SEQUENCE * LOOPS

-- Alles, was waehrend eines Versuchs auf dem Depot liegen DARF. Die
-- Fehlschlagerkennung ist bewusst eine reine "is not"-Pruefung gegen diese
-- Liste: bei einem Fehlschlag kann alles Moegliche herauskommen, das laesst
-- sich nicht aufzaehlen. Was nicht hier drin steht, beendet den Versuch.
local KNOWN_ITEMS = {
  [BASE_ITEM] = true,
  [PROGRESS_ITEM] = true,
  [RESULT_ITEM] = true,
}

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

local args = { ... }
local orderSize = nil

if #args > 1 then
  printError("Zu viele Argumente. " .. USAGE)
  return
end

if args[1] then
  orderSize = tonumber(args[1])
  if not orderSize or orderSize < 1 or orderSize ~= math.floor(orderSize) then
    printError("Anzahl muss eine ganze Zahl >= 1 sein. " .. USAGE)
    return
  end
end

-- Beschreibt, was auf einer Seite tatsaechlich gefunden wurde. Ohne das ist
-- ein fehlender Peripheral kaum von einem untauglichen zu unterscheiden.
local function describeSide(side)
  if not peripheral.isPresent(side) then
    return "kein Peripheral erkannt"
  end
  local types = { peripheral.getType(side) }
  local methods = peripheral.getMethods(side) or {}
  table.sort(methods)
  return string.format("Typ(en): %s | Methoden: %s",
    table.concat(types, ", "),
    #methods > 0 and table.concat(methods, ", ") or "keine")
end

-- Holt das Inventar einer Seite oder erklaert, was stattdessen da ist.
-- CC:Tweaked erkennt nur Bloecke als Inventar, die Forges IItemHandler
-- anbieten. Depot und Deployer tun das; Netzwerkbloecke von Storage-Mods
-- (z.B. Simple Storage Network) sind im Spiel Kisten, tun es aber nicht --
-- dann hilft nur eine normale Kiste als Puffer.
local function wrapInventory(side, role)
  local inv = peripheral.wrap(side)
  if inv and inv.list and inv.pushItems then
    return inv
  end
  printError(string.format("Auf Seite '%s' ist kein nutzbares Inventar (%s).", side, role))
  printError("Gefunden: " .. describeSide(side))
  printError("Gebraucht werden die Methoden list und pushItems.")
  printError("Stimmt die Seite? Sie gilt aus Sicht des COMPUTERS, nicht des")
  printError("Spielers. Storage-Mod-Bloecke bieten die Methoden meist nicht an --")
  printError("dann eine normale Kiste als Puffer daneben setzen.")
  return nil
end

local chest = wrapInventory(CHEST_SIDE, "Kiste mit den Zutaten")
if not chest then
  return
end

local depot = wrapInventory(DEPOT_SIDE, "Depot mit dem Werkstueck")
if not depot then
  return
end

local deployer = wrapInventory(DEPLOYER_SIDE, "Deployer")
if not deployer then
  return
end

if not orderSize then
  print("Mechanism: stellt Precision Mechanisms per Deployer und Depot her.")
  orderSize = askInt("Anzahl der gewuenschten Precision Mechanisms", 1)
end

-- Zutatenbedarf fuer EINEN Versuch: die Basis plus jedes Sequenz-Item so oft,
-- wie es in einem Durchlauf vorkommt, mal LOOPS.
local function requirementPerAttempt()
  local needed = { [BASE_ITEM] = 1 }
  for _, id in ipairs(SEQUENCE) do
    needed[id] = (needed[id] or 0) + LOOPS
  end
  return needed
end

local REQUIREMENT = requirementPerAttempt()

-- Zaehlt alle Items der Kiste zu name -> Gesamtmenge zusammen.
local function countAvailable()
  local available = {}
  for _, item in pairs(chest.list()) do
    available[item.name] = (available[item.name] or 0) + item.count
  end
  return available
end

-- Reicht das Material fuer einen weiteren Versuch? Nennt sonst die erste
-- fehlende Zutat, damit die Meldung konkret wird.
local function enoughMaterial()
  local available = countAvailable()
  for id, count in pairs(REQUIREMENT) do
    if (available[id] or 0) < count then
      return false, string.format("%s (%d von %d da)", id, available[id] or 0, count)
    end
  end
  return true
end

-- Erster belegter Slot eines Inventars. list() liefert eine luecken-behaftete
-- Tabelle, deshalb pairs statt ipairs.
local function firstItem(inv)
  for slot, item in pairs(inv.list()) do
    return slot, item
  end
  return nil
end

local function depotItem()
  local _, item = firstItem(depot)
  return item and item.name or nil
end

-- Schiebt genau EIN Item der gesuchten ID aus der Kiste auf die Zielseite.
-- Der Rueckgabewert von pushItems ist die einzige verlaessliche Quelle fuer
-- die bewegte Menge -- er ist 0, wenn das Ziel nichts annimmt.
local function pushOne(toSide, id)
  for slot, item in pairs(chest.list()) do
    if item.name == id then
      if (chest.pushItems(toSide, slot, 1) or 0) == 1 then
        return true
      end
      -- Dieser Slot hat nicht funktioniert; das Ziel nimmt nichts an, weitere
      -- Slots zu probieren bringt nichts.
      return false
    end
  end
  return false
end

-- Raeumt ein Inventar komplett in die Kiste zurueck. Gibt zurueck, wie viele
-- Items liegen geblieben sind.
local function drainToChest(inv, label)
  local stuck = 0
  for slot, item in pairs(inv.list()) do
    local moved = inv.pushItems(CHEST_SIDE, slot) or 0
    if moved < item.count then
      stuck = stuck + (item.count - moved)
    end
    if moved > 0 then
      print(string.format("%s geleert: %d x %s in die Kiste.", label, moved, item.name))
    end
  end
  if stuck > 0 then
    printError(string.format("%s: %d Item(s) blieben liegen -- ist die Kiste voll?", label, stuck))
  end
  return stuck
end

-- Wartet, bis der Deployer sein Item verbraucht hat. Der Deployer nimmt das
-- Item nur weg, wenn er damit wirklich ein Rezept angewendet hat -- ein leeres
-- Deployer-Inventar ist also ein eindeutiges "Schritt erledigt". Deshalb liegt
-- immer nur genau EIN Item drin.
local function waitDeployerEmpty()
  local deadline = os.clock() + STEP_TIMEOUT
  while true do
    if firstItem(deployer) == nil then
      return true
    end
    if os.clock() >= deadline then
      return false
    end
    sleep(POLL_INTERVAL)
  end
end

-- Wartet, bis das Depot nicht mehr den Zwischenstand zeigt. Nach dem letzten
-- Deploy-Schritt kann zwischen "Deployer ist leer" und "Depot zeigt das
-- Ergebnis" ein Tick liegen. Ohne dieses Warten wuerde ein fertiger Mechanism
-- faelschlich als Fehlschlag gezaehlt.
local function waitDepotSettled()
  local deadline = os.clock() + 2
  while depotItem() == PROGRESS_ITEM and os.clock() < deadline do
    sleep(POLL_INTERVAL)
  end
  return depotItem()
end

local function timeoutHelp(id)
  printError(string.format("Der Deployer hat %s nicht verbraucht (%d s Wartezeit).", id, STEP_TIMEOUT))
  printError("Bitte pruefen:")
  printError("  - bekommt der Deployer Rotationskraft?")
  printError("  - steht er auf 'Use' und nicht auf 'Punch'?")
  printError("  - zeigt er auf das Depot und liegt dort das Werkstueck?")
  printError("  - stimmt die Reihenfolge in SEQUENCE (in JEI gegenpruefen)?")
end

-- Ein kompletter Versuch. Rueckgabe: status, detail
--   "success"  -- ein Precision Mechanism liegt in der Kiste
--   "salvage"  -- Fehlschlag, detail ist die ID des angefallenen Items
--   "abort"    -- etwas stimmt am Aufbau nicht, detail ist der Grund
local function runOne(attempt)
  -- Reste vom letzten Lauf wegraeumen, sonst deployt der erste Schritt das
  -- Falsche oder das Depot ist noch belegt.
  if drainToChest(deployer, "Deployer") > 0 then
    return "abort", "Deployer liess sich nicht leeren."
  end
  if drainToChest(depot, "Depot") > 0 then
    return "abort", "Depot liess sich nicht leeren."
  end

  if not pushOne(DEPOT_SIDE, BASE_ITEM) then
    return "abort", string.format("Konnte %s nicht aufs Depot legen.", BASE_ITEM)
  end

  local step = 0
  for _ = 1, LOOPS do
    for _, id in ipairs(SEQUENCE) do
      step = step + 1
      print(string.format("[Versuch %d | Schritt %d/%d | %s]", attempt, step, TOTAL_STEPS, id))

      if not pushOne(DEPLOYER_SIDE, id) then
        return "abort", string.format("Konnte %s nicht in den Deployer legen.", id)
      end

      if not waitDeployerEmpty() then
        timeoutHelp(id)
        return "abort", string.format("Timeout bei Schritt %d (%s).", step, id)
      end

      -- Dem Depot einen Moment geben, den neuen Zustand zu uebernehmen. Zu
      -- frueh gelesen zeigt es noch den vorherigen (bekannten) Stand, ein
      -- Fehlschlag wuerde also erst einen Schritt spaeter auffallen.
      sleep(POLL_INTERVAL)

      -- "is not"-Pruefung: bei einem Fehlschlag kann alles Moegliche auf dem
      -- Depot landen, deshalb wird nicht auf bestimmte Items geprueft, sondern
      -- darauf, dass es KEINS der drei erwarteten ist.
      local onDepot = depotItem()
      if onDepot == nil then
        -- Kein Abbruch des ganzen Auftrags: das Werkstueck kann auch als
        -- Item-Entity heruntergefallen sein. Nur dieser Versuch ist verloren.
        return "salvage", string.format("nichts (Depot nach Schritt %d leer)", step)
      end
      if not KNOWN_ITEMS[onDepot] then
        return "salvage", onDepot
      end
    end
  end

  local onDepot = waitDepotSettled()
  if onDepot ~= RESULT_ITEM then
    return "salvage", onDepot or "nichts"
  end

  if drainToChest(depot, "Depot") > 0 then
    return "abort", "Endprodukt liess sich nicht in die Kiste raeumen."
  end
  return "success"
end

local done = 0
local failed = 0
local attempts = 0
local finishReason = nil

local function run()
  print(string.format("Auftrag: %d Precision Mechanism(s), %d Deploy-Schritte pro Versuch.",
    orderSize, TOTAL_STEPS))
  print("Material pro Versuch:")
  print(string.format("  %s x1 (Basis)", BASE_ITEM))
  for _, id in ipairs(SEQUENCE) do
    print(string.format("  %s x%d", id, LOOPS))
  end
  print("Abbruch mit Strg+T.")

  while done < orderSize do
    local ok, missing = enoughMaterial()
    if not ok then
      finishReason = string.format("Material erschoepft (es fehlt %s) - %d von %d fertig.",
        missing, done, orderSize)
      return
    end

    attempts = attempts + 1
    local status, detail = runOne(attempts)

    if status == "success" then
      done = done + 1
    elseif status == "salvage" then
      failed = failed + 1
      print(string.format("Versuch %d fehlgeschlagen: %s statt %s.", attempts, detail, RESULT_ITEM))
      -- Das angefallene Item ist egal, es wandert einfach zurueck in die Kiste.
      drainToChest(depot, "Depot")
    else
      printError(detail)
      finishReason = "Abgebrochen: " .. detail
      return
    end

    print(string.format("[%d/%d fertig | %d Fehlschlaege | %d Versuche]",
      done, orderSize, failed, attempts))
  end

  finishReason = "Auftrag komplett."
end

local ok, err = pcall(run)

print("--- Zusammenfassung ---")
print(string.format("Fertige Mechanisms: %d von %d", done, orderSize))
print(string.format("Fehlschlaege:       %d", failed))
print(string.format("Versuche gesamt:    %d", attempts))
if finishReason then
  print(finishReason)
end
if not ok then
  printError("Abbruch: " .. tostring(err))
end
