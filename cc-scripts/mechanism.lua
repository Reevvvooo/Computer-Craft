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
-- Aufbau:
--
--          [Deployer]   <- Wired Modem
--               :          Blick nach unten, "Use"-Modus, Rotationskraft
--   [ Kiste  ]  :       <- Wired Modem  (Bruecke, siehe unten)
--   [Computer] [Depot]     Depot braucht kein Modem
--        ^
--    Wired Modem am Computer, per Networking Cable mit Kiste und Deployer
--
-- WIRED, nicht WIRELESS: Ein Wireless Modem macht keine Bloecke zu
-- Peripherals, es transportiert nur Rednet-Nachrichten zwischen Computern. Am
-- Deployer angebracht tut es gar nichts. Gebraucht wird ein Wired Modem (das
-- flache) plus Networking Cable. Jedes Modem am Peripheral einmal
-- rechtsklicken, bis es rot leuchtet -- der Chat nennt dann den Netzwerknamen.
--
-- Ein Wired Modem belegt den Blockplatz NEBEN dem Peripheral, es muss also auf
-- eine freie Seite. Bei der Kiste darf es nicht die Seite zum Computer sein --
-- dort steht schon der Computer, und die direkte Nachbarschaft wird ja
-- gebraucht.
--
-- Warum die Kiste eine "Bruecke" ist: pushItems loest den Zielnamen nur im
-- Namensraum der QUELLE auf. Ein direkt am Computer anliegendes Inventar kennt
-- nur die sechs Seitennamen, ein Netzwerk-Peripheral nur Netzwerknamen --
-- mischen geht in einem einzelnen Aufruf nicht. Ein Block, der am Computer
-- anliegt UND ein Wired Modem hat, ist aber unter BEIDEN Namen erreichbar. Da
-- jede Uebergabe hier die Kiste an einem Ende hat (Kiste<->Depot,
-- Kiste<->Deployer; Depot und Deployer tauschen nie direkt), genuegt die Kiste
-- als Bruecke: Kiste<->Depot laeuft ueber Seitennamen, Kiste<->Deployer ueber
-- Netzwerknamen.
--
-- Wer es einheitlich mag, gibt auch dem Depot ein Modem und faehrt alles ueber
-- Netzwerknamen. Das Skript erkennt beide Varianten (und den reinen
-- Seiten-Aufbau) von selbst.
--
-- Aufruf:
--   mechanism.lua      -- fragt die Anzahl interaktiv ab
--   mechanism.lua 5    -- 5 Precision Mechanisms

-- Leer lassen (nil) fuer Autoerkennung. Sonst eine Seite ("top") oder einen
-- Netzwerknamen ("create:depot_0") eintragen -- oder beide Namen desselben
-- Blocks als Liste, wenn er Bruecke sein soll:
--   local CHEST_NAME = { "top", "minecraft:barrel_0" }
local CHEST_NAME = nil
local DEPOT_NAME = nil
local DEPLOYER_NAME = nil

-- Blocktypen fuer die Autoerkennung, anpassbar fuer abweichende Modpacks.
local DEPOT_TYPE = "create:depot"
local DEPLOYER_TYPE = "create:deployer"

-- HIER ANPASSEN, falls das Modpack abweichende Item-IDs benutzt (im Spiel per
-- F3+H sichtbar machen).
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

local SIDES = {
  top = true, bottom = true, left = true, right = true, front = true, back = true,
}

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

-- Wrappt einen Namen und gibt ihn nur zurueck, wenn dahinter wirklich ein
-- Inventar steckt. Bewusst Duck-Typing statt peripheral.hasType, damit auch
-- aeltere CC:Tweaked-Versionen mitspielen. CC:Tweaked erkennt nur Bloecke als
-- Inventar, die Forges IItemHandler anbieten -- Netzwerkbloecke von
-- Storage-Mods (z.B. Simple Storage Network) tun das nicht.
local function tryInventory(name)
  local inv = peripheral.wrap(name)
  if inv and inv.list and inv.pushItems then
    return inv
  end
  return nil
end

-- Beschreibt, was unter einem Namen tatsaechlich gefunden wurde. Ohne das ist
-- ein fehlendes Peripheral kaum von einem untauglichen zu unterscheiden.
local function describePeripheral(name)
  if not peripheral.isPresent(name) then
    return "kein Peripheral erkannt"
  end
  local types = { peripheral.getType(name) }
  local methods = peripheral.getMethods(name) or {}
  table.sort(methods)
  return string.format("Typ(en): %s | Methoden: %s",
    table.concat(types, ", "),
    #methods > 0 and table.concat(methods, ", ") or "keine")
end

-- Listet alles auf, was der Computer sieht. Damit laesst sich der richtige
-- Name direkt ablesen und oben eintragen, statt im Spiel Modems abzuklappern.
local function dumpPeripherals()
  print("Gefundene Peripherals:")
  local names = peripheral.getNames()
  if #names == 0 then
    print("  (keine -- Modem am Computer aktiv? Kabel verbunden?)")
    return
  end
  for _, name in ipairs(names) do
    print(string.format("  %s [%s]%s",
      name,
      peripheral.getType(name) or "?",
      tryInventory(name) and " <- Inventar" or ""))
  end
end

-- Ein Inventar wird ueber einen Record angesprochen, der BEIDE moeglichen
-- Namen und die dazugehoerigen Wraps haelt:
--   { label, side, sideInv, net, netInv, inv }
-- Beide Wraps sind noetig, nicht nur beide Namen: peripheral.wrap("top") und
-- peripheral.wrap("minecraft:barrel_0") liefern zwar denselben Block, loesen
-- Zielnamen in pushItems aber in verschiedenen Namensraeumen auf. Zum reinen
-- Lesen (list) ist egal welcher -- dafuer steht inv.
local function attach(record, name, inv)
  if SIDES[name] then
    if record.side then
      return false
    end
    record.side, record.sideInv = name, inv
  else
    if record.net then
      return false
    end
    record.net, record.netInv = name, inv
  end
  record.inv = record.inv or inv
  return true
end

local function recordNames(record)
  if record.side and record.net then
    return record.side .. " + " .. record.net
  end
  return record.side or record.net or "?"
end

-- Waehlt fuer eine Uebergabe Quell-Handle und Zielnamen aus EINEM Namensraum.
-- Netzwerknamen zuerst, weil das Kabelnetz auch Bloecke erreicht, die nicht am
-- Computer anliegen.
local function transferRoute(from, to)
  if from.netInv and to.net then
    return from.netInv, to.net
  end
  if from.sideInv and to.side then
    return from.sideInv, to.side
  end
  return nil
end

-- Baut einen Record aus einer von Hand gesetzten Konstante (String oder Liste
-- von Namen desselben Blocks).
local function recordFromConfig(label, configured)
  local record = { label = label }
  local names = type(configured) == "table" and configured or { configured }
  for _, name in ipairs(names) do
    local inv = tryInventory(name)
    if not inv then
      printError(string.format("'%s' ist kein nutzbares Inventar (%s).", name, label))
      printError("Gefunden: " .. describePeripheral(name))
      return nil
    end
    if not attach(record, name, inv) then
      printError(string.format("%s: '%s' doppelt vergeben (schon %s).", label, name, recordNames(record)))
      return nil
    end
  end
  return record
end

-- Sucht alle Inventare ab und ordnet sie ueber den Blocktyp zu. Ein Block, der
-- unter Seiten- UND Netzwerknamen auftaucht, landet dabei in EINEM Record --
-- genau so entsteht der Bruecken-Record von selbst.
local function detectRecords()
  local depot = { label = "Depot" }
  local deployer = { label = "Deployer" }
  local chestByType = {}
  local chestTypes = {}
  local ambiguous = {}

  for _, name in ipairs(peripheral.getNames()) do
    local inv = tryInventory(name)
    if inv then
      local ptype = peripheral.getType(name)
      local record
      if ptype == DEPOT_TYPE then
        record = depot
      elseif ptype == DEPLOYER_TYPE then
        record = deployer
      else
        if not chestByType[ptype] then
          chestByType[ptype] = { label = "Kiste" }
          chestTypes[#chestTypes + 1] = ptype
        end
        record = chestByType[ptype]
      end
      if not attach(record, name, inv) then
        ambiguous[record.label] = true
      end
    end
  end

  return depot, deployer, chestByType, chestTypes, ambiguous
end

local function resolveAll()
  local detectedDepot, detectedDeployer, chestByType, chestTypes, ambiguous = detectRecords()

  local depot, deployer, chest

  if DEPOT_NAME then
    depot = recordFromConfig("Depot", DEPOT_NAME)
  elseif ambiguous["Depot"] then
    printError(string.format("Mehrere Bloecke vom Typ %s gefunden.", DEPOT_TYPE))
    printError("Bitte DEPOT_NAME oben im Skript setzen.")
  elseif detectedDepot.inv then
    depot = detectedDepot
  else
    printError(string.format("Kein Depot gefunden (gesucht: Typ %s).", DEPOT_TYPE))
    printError("Unten steht, was der Computer sieht: passt dort ein Typ, ihn in")
    printError("DEPOT_TYPE eintragen, sonst den Namen in DEPOT_NAME.")
  end

  if DEPLOYER_NAME then
    deployer = recordFromConfig("Deployer", DEPLOYER_NAME)
  elseif ambiguous["Deployer"] then
    printError(string.format("Mehrere Bloecke vom Typ %s gefunden.", DEPLOYER_TYPE))
    printError("Bitte DEPLOYER_NAME oben im Skript setzen.")
  elseif detectedDeployer.inv then
    deployer = detectedDeployer
  else
    printError(string.format("Kein Deployer gefunden (gesucht: Typ %s).", DEPLOYER_TYPE))
    printError("Ein WIRELESS Modem reicht dafuer nicht -- der Deployer braucht ein")
    printError("WIRED Modem plus Networking Cable zum Computer, und das Modem muss")
    printError("per Rechtsklick aktiviert sein (leuchtet rot). Taucht er unten in")
    printError("der Liste auf, den Typ in DEPLOYER_TYPE bzw. den Namen in")
    printError("DEPLOYER_NAME eintragen.")
  end

  if CHEST_NAME then
    chest = recordFromConfig("Kiste", CHEST_NAME)
  elseif ambiguous["Kiste"] then
    printError("Mehrere gleichartige Kisten gefunden.")
    printError("Bitte CHEST_NAME oben im Skript setzen.")
  elseif #chestTypes == 1 then
    chest = chestByType[chestTypes[1]]
  elseif #chestTypes == 0 then
    printError("Keine Kiste mit den Zutaten gefunden.")
    printError("Bitte CHEST_NAME oben im Skript setzen.")
  else
    printError("Mehrere Inventare kommen als Zutatenkiste in Frage:")
    for _, ptype in ipairs(chestTypes) do
      printError(string.format("  %s (%s)", recordNames(chestByType[ptype]), ptype))
    end
    printError("Bitte CHEST_NAME oben im Skript setzen.")
  end

  if not (chest and depot and deployer) then
    print()
    dumpPeripherals()
    return nil
  end

  return chest, depot, deployer
end

-- Prueft VOR dem ersten Item, ob beide tatsaechlich benutzten Richtungen einen
-- gemeinsamen Namensraum haben. Ohne das stirbt der Lauf erst mittendrin mit
-- "Target does not exist" -- und das Material ist dann schon halb verbraucht.
local function checkRoute(a, b)
  if transferRoute(a, b) then
    return true
  end
  printError(string.format("%s (%s) und %s (%s) haengen nicht im selben Netz.",
    a.label, recordNames(a), b.label, recordNames(b)))
  printError("pushItems kann nur innerhalb EINES Namensraums schieben: entweder")
  printError("beide direkt am Computer, oder beide im Kabelnetz. Abhilfe: einem")
  printError("der beiden Bloecke ein Wired Modem geben und per Rechtsklick")
  printError("aktivieren, dann ist er unter beiden Namen erreichbar.")
  return false
end

local chest, depot, deployer = resolveAll()
if not chest then
  return
end

print("Benutzte Peripherals:")
print(string.format("  Kiste:    %s", recordNames(chest)))
print(string.format("  Depot:    %s", recordNames(depot)))
print(string.format("  Deployer: %s", recordNames(deployer)))

-- Beide Richtungen pruefen und erst danach abbrechen, damit nicht nur die
-- erste von womoeglich zwei fehlenden Verbindungen gemeldet wird.
local depotOk = checkRoute(chest, depot)
local deployerOk = checkRoute(chest, deployer)
if not (depotOk and deployerOk) then
  print()
  dumpPeripherals()
  return
end

if not orderSize then
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
  for _, item in pairs(chest.inv.list()) do
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
local function firstItem(record)
  for slot, item in pairs(record.inv.list()) do
    return slot, item
  end
  return nil
end

local function depotItem()
  local _, item = firstItem(depot)
  return item and item.name or nil
end

-- Schiebt genau EIN Item der gesuchten ID von einem Record zum anderen. Der
-- Rueckgabewert von pushItems ist die einzige verlaessliche Quelle fuer die
-- bewegte Menge -- er ist 0, wenn das Ziel nichts annimmt.
local function pushOne(from, to, id)
  local srcInv, dstName = transferRoute(from, to)
  for slot, item in pairs(srcInv.list()) do
    if item.name == id then
      if (srcInv.pushItems(dstName, slot, 1) or 0) == 1 then
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
local function drainToChest(from)
  local srcInv, dstName = transferRoute(from, chest)
  local stuck = 0
  for slot, item in pairs(srcInv.list()) do
    local moved = srcInv.pushItems(dstName, slot) or 0
    if moved < item.count then
      stuck = stuck + (item.count - moved)
    end
    if moved > 0 then
      print(string.format("%s geleert: %d x %s in die Kiste.", from.label, moved, item.name))
    end
  end
  if stuck > 0 then
    printError(string.format("%s: %d Item(s) blieben liegen -- ist die Kiste voll?", from.label, stuck))
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
  if drainToChest(deployer) > 0 then
    return "abort", "Deployer liess sich nicht leeren."
  end
  if drainToChest(depot) > 0 then
    return "abort", "Depot liess sich nicht leeren."
  end

  if not pushOne(chest, depot, BASE_ITEM) then
    return "abort", string.format("Konnte %s nicht aufs Depot legen.", BASE_ITEM)
  end

  local step = 0
  for _ = 1, LOOPS do
    for _, id in ipairs(SEQUENCE) do
      step = step + 1
      print(string.format("[Versuch %d | Schritt %d/%d | %s]", attempt, step, TOTAL_STEPS, id))

      if not pushOne(chest, deployer, id) then
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

  if drainToChest(depot) > 0 then
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
      drainToChest(depot)
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
