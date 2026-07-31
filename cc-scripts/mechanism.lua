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
--                    [Deployer]   <- Wired Modem
--                         :          Blick nach unten, "Use", Rotationskraft
--   [Monitor]  [ Kiste  ]  :       <- Wired Modem  (Bruecke, siehe unten)
--   [Monitor]  [Computer] [Depot]     Depot braucht kein Modem
--                   ^
--    Wired Modem am Computer, per Networking Cable mit Kiste und Deployer
--
-- Der Monitor ist OPTIONAL. Fehlt er, laeuft alles unveraendert weiter, nur
-- ohne Dashboard. Ein ADVANCED MONITOR bringt Farbe und Rechtsklick; ein
-- ADVANCED COMPUTER ist dafuer NICHT noetig, denn beides sind Eigenschaften
-- des Monitors. Ein normaler Computer bleibt nur auf seinem eigenen
-- Bildschirm monochrom, was hier egal ist. 2x2 Bloecke reichen, 3x2 ist
-- komfortabel; das Layout passt sich der Groesse an.
--
-- Rechtsklick auf den Monitor schaltet "Stopp nach diesem Versuch" um. Das ist
-- der saubere Weg zum Beenden: der laufende Mechanism wird noch fertig, es
-- bleibt kein halbes Werkstueck auf dem Depot liegen. Strg+T geht weiterhin,
-- bricht aber sofort ab.
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

local loadOk, uilib = pcall(dofile, "uilib.lua")
if not loadOk then
  printError("uilib.lua fehlt oder ist fehlerhaft. Bitte install.lua erneut ausfuehren.")
  return
end

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

-- Monitor ist optional. nil = Autoerkennung, sonst Seite oder Netzwerkname.
local MONITOR_NAME = nil
local MONITOR_SCALE = 0.5

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

-- ---------------------------------------------------------------------------
-- Anzeige
-- ---------------------------------------------------------------------------

local done = 0
local failed = 0
local attempts = 0
local finishReason = nil

-- Reine Anzeigedaten. Die Ablauflogik schreibt hier rein und ruft render() --
-- so bleiben Monitor-Aufrufe aus dem Ablaufcode heraus.
local view = {
  step = 0,
  item = nil,
  status = "Bereit",
  statusColour = colours.lightGrey,
  stock = 0,
  stopAfter = false,
  startedAt = os.clock(),
}

local monitor = nil
if MONITOR_NAME then
  monitor = peripheral.wrap(MONITOR_NAME)
  if not (monitor and monitor.setCursorPos) then
    printError(string.format("'%s' ist kein Monitor -- laeuft ohne Dashboard weiter.", MONITOR_NAME))
    monitor = nil
  end
else
  monitor = peripheral.find("monitor")
end

if monitor then
  monitor.setTextScale(MONITOR_SCALE)
  print(string.format("Monitor: %s (%s)",
    MONITOR_NAME or peripheral.getName(monitor),
    monitor.isColour() and "farbig" or "monochrom"))
else
  print("Kein Monitor gefunden -- laeuft ohne Dashboard.")
end

-- Schreibt gekuerzt auf die Restbreite. Das Kuerzen ist Pflicht:
-- create:incomplete_precision_mechanism ist laenger als die meisten Monitore.
local function writeAt(x, y, text, fg, bg)
  local width = monitor.getSize()
  if x > width then
    return
  end
  monitor.setCursorPos(x, y)
  monitor.setTextColour(fg or colours.white)
  monitor.setBackgroundColour(bg or colours.black)
  monitor.write(text:sub(1, width - x + 1))
end

-- Fuellt eine Zeile bis zum rechten Rand mit der Hintergrundfarbe, damit
-- Reste des vorherigen Bildes nicht stehen bleiben.
local function fillLine(y, bg)
  local width = monitor.getSize()
  monitor.setCursorPos(1, y)
  monitor.setBackgroundColour(bg or colours.black)
  monitor.write(string.rep(" ", width))
end

-- Balken ueber die volle Breite mit Prozentzahl rechts.
local function bar(y, fraction, colour)
  local width = monitor.getSize()
  fraction = math.max(0, math.min(1, fraction or 0))
  local label = string.format("%3d%%", math.floor(fraction * 100))
  local barWidth = width - 2 - #label - 1
  if barWidth < 4 then
    -- Zu schmal fuer einen Balken, dann nur die Zahl.
    fillLine(y)
    writeAt(2, y, label, colour)
    return
  end
  local filled = math.floor(barWidth * fraction + 0.5)
  fillLine(y)
  monitor.setCursorPos(2, y)
  monitor.setBackgroundColour(colour)
  monitor.write(string.rep(" ", filled))
  monitor.setBackgroundColour(colours.grey)
  monitor.write(string.rep(" ", barWidth - filled))
  writeAt(width - #label, y, label, colour)
end

local function elapsed()
  local seconds = math.floor(os.clock() - view.startedAt)
  return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- Zeichnet das Dashboard. Von oben nach unten mit einem Zeilenzaehler;
-- Leerzeilen entfallen zuerst, wenn die Hoehe knapp wird, danach die
-- optionalen Zeilen. Die Statuszeile steht immer ganz unten.
local function render()
  if not monitor then
    return
  end

  local width, height = monitor.getSize()
  local roomy = height >= 12
  local order = orderSize or 0

  monitor.setBackgroundColour(colours.black)
  monitor.clear()

  -- Kopfzeile
  fillLine(1, colours.blue)
  writeAt(2, 1, "PRECISION MECHANISMS", colours.white, colours.blue)
  local clock = elapsed()
  if width >= 28 then
    writeAt(width - #clock, 1, clock, colours.lightBlue, colours.blue)
  end

  local y = roomy and 3 or 2

  local function skip()
    if roomy then
      y = y + 1
    end
  end

  writeAt(2, y, "Auftrag", colours.lightGrey)
  writeAt(12, y, string.format("%d / %d", done, order), colours.white)
  y = y + 1
  bar(y, order > 0 and done / order or 0, colours.lime)
  y = y + 1
  skip()

  -- Auf sehr flachen Monitoren (z.B. 1x1 bei Textgroesse 1) bleiben nur
  -- Kopfzeile, Auftragsbalken und Status -- alles Weitere wuerde in die
  -- Statuszeile hineinlaufen.
  if height >= 8 then
    writeAt(2, y, string.format("Versuch %d", attempts), colours.white)
    if width >= 30 then
      writeAt(18, y, string.format("Schritt %d / %d", view.step, TOTAL_STEPS), colours.white)
    else
      y = y + 1
      writeAt(2, y, string.format("Schritt %d / %d", view.step, TOTAL_STEPS), colours.white)
    end
    y = y + 1
    bar(y, view.step / TOTAL_STEPS, colours.cyan)
    y = y + 1

    if view.item and y <= height - 2 then
      writeAt(2, y, "> " .. view.item, colours.lightBlue)
      y = y + 1
    end
    skip()

    -- Optionale Zeile: entfaellt, wenn die Statuszeile sonst kollidiert.
    if y <= height - 2 then
      writeAt(2, y, string.format("Fehlschlaege %d", failed),
        failed > 0 and colours.red or colours.lightGrey)
      if width >= 30 then
        writeAt(22, y, string.format("Material %dx", view.stock), colours.lightGrey)
      end
    end
  end

  -- Statuszeile immer ganz unten
  local statusText = view.status
  local statusColour = view.statusColour
  if view.stopAfter and statusColour == colours.yellow then
    statusText = "STOPP NACH DIESEM VERSUCH"
    statusColour = colours.orange
  end
  fillLine(height, statusColour)
  writeAt(2, height, statusText, colours.black, statusColour)
end

local function setStatus(text, colour)
  view.status = text
  view.statusColour = colour or colours.yellow
  render()
end

-- Wie sleep, verarbeitet aber nebenbei Monitor-Touches. os.pullEvent (nicht
-- pullEventRaw) laesst Strg+T weiterhin durch.
local function nap(seconds)
  local timer = os.startTimer(seconds)
  while true do
    local event, p1 = os.pullEvent()
    if event == "timer" and p1 == timer then
      return
    end
    if event == "monitor_touch" then
      view.stopAfter = not view.stopAfter
      print(view.stopAfter and "Stopp nach diesem Versuch angefordert."
        or "Stopp wieder aufgehoben.")
      render()
    end
  end
end

render()

if not orderSize then
  orderSize = uilib.askInt("Anzahl der gewuenschten Precision Mechanisms", 1)
  render()
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

-- Wie viele Versuche gibt das Material noch her? Gibt zusaetzlich die knappste
-- Zutat zurueck, damit Meldungen konkret werden -- gleiche Bauart wie
-- maxSets() in crafter.lua. Liefert beides auf einmal: die Zahl fuers
-- Dashboard und die Abbruchbedingung (< 1).
local function stockAttempts()
  local available = countAvailable()
  local possible = nil
  local scarcest = BASE_ITEM
  for id, count in pairs(REQUIREMENT) do
    local n = math.floor((available[id] or 0) / count)
    if possible == nil or n < possible then
      possible, scarcest = n, id
    end
  end
  return possible or 0, string.format("%s (%d von %d da)",
    scarcest, available[scarcest] or 0, REQUIREMENT[scarcest])
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
    nap(POLL_INTERVAL)
  end
end

-- Wartet, bis das Depot nicht mehr den Zwischenstand zeigt. Nach dem letzten
-- Deploy-Schritt kann zwischen "Deployer ist leer" und "Depot zeigt das
-- Ergebnis" ein Tick liegen. Ohne dieses Warten wuerde ein fertiger Mechanism
-- faelschlich als Fehlschlag gezaehlt.
local function waitDepotSettled()
  local deadline = os.clock() + 2
  while depotItem() == PROGRESS_ITEM and os.clock() < deadline do
    nap(POLL_INTERVAL)
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
  view.step = 0
  view.item = nil
  setStatus("Vorbereiten")

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
      view.step = step
      view.item = id
      setStatus("Laeuft")

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
      nap(POLL_INTERVAL)

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

-- Schlusszustand fuer die Statuszeile, wird an jedem Ausstieg aus run() gesetzt.
local endLabel = "AUFTRAG KOMPLETT"
local endColour = colours.lime

local function run()
  print(string.format("Auftrag: %d Precision Mechanism(s), %d Deploy-Schritte pro Versuch.",
    orderSize, TOTAL_STEPS))
  print("Material pro Versuch:")
  print(string.format("  %s x1 (Basis)", BASE_ITEM))
  for _, id in ipairs(SEQUENCE) do
    print(string.format("  %s x%d", id, LOOPS))
  end
  print("Abbruch mit Strg+T" .. (monitor and " oder Rechtsklick auf den Monitor." or "."))

  while done < orderSize do
    local stock, missing = stockAttempts()
    view.stock = stock
    if stock < 1 then
      finishReason = string.format("Material erschoepft (es fehlt %s) - %d von %d fertig.",
        missing, done, orderSize)
      endLabel, endColour = "MATERIAL ALLE", colours.orange
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
      endLabel, endColour = "AUFBAU PRUEFEN", colours.red
      return
    end

    print(string.format("[%d/%d fertig | %d Fehlschlaege | %d Versuche]",
      done, orderSize, failed, attempts))
    view.step = 0
    view.item = nil
    render()

    -- Der Stopp-Wunsch wird bewusst erst HIER geprueft: das Werkstueck ist
    -- fertig und in der Kiste, es bleibt nichts auf dem Depot liegen.
    if view.stopAfter and done < orderSize then
      finishReason = string.format("Per Monitor gestoppt - %d von %d fertig.", done, orderSize)
      endLabel, endColour = "GESTOPPT", colours.orange
      return
    end
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

-- Endbild stehen lassen: der Monitor soll nach dem Lauf noch zeigen, was
-- herausgekommen ist.
view.step = 0
view.item = nil
view.stopAfter = false
if not ok then
  setStatus("ABGEBROCHEN", colours.red)
else
  setStatus(endLabel, endColour)
end
