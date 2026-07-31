-- network.lua
-- Durchsucht das Kabelnetz nach allen erreichbaren Peripherals und laesst den
-- Nutzer fuer jedes davon per Tastendruck "i" (Eingang) oder "o" (Ausgang)
-- eine Rolle festlegen. Das Ergebnis landet in network.cfg und kann von
-- anderen Skripten ueber uilib.loadNetworkConfig() eingelesen werden, statt
-- Peripheral-Namen hart zu kodieren wie aktuell in crafter.lua/mechanism.lua.
--
-- Kein Dauerbetrieb, kein Event-Loop -- das Skript beendet sich nach jedem
-- Aufruf. Drei Modi:
--
-- "Geaendert" (im Standard-Modus) heisst: der Peripheral-Typ unter einem
-- bekannten Namen hat sich geaendert (z.B. eine Kiste wurde durch ein Fass
-- ersetzt) -- das ist das einzige Signal, das ohne Blick ins Spiel verfuegbar
-- ist. Verschwindet ein bekannter Name komplett aus dem Netz, wird der
-- Eintrag stillschweigend aus der neuen Konfiguration entfernt (nur als
-- Hinweis ausgegeben, keine Frage).
--
-- Laeuft auf einem NORMALEN COMPUTER, wie crafter.lua/mechanism.lua.
--
-- Aufruf:
--   network.lua              -- prueft auf neue/geaenderte/entfernte
--                                Peripherals, fragt nur dafuer nach
--   network.lua change       -- listet die gespeicherte Konfiguration auf
--                                und aendert gezielt einzelne Eintraege
--   network.lua change all   -- fragt die Rolle fuer ALLE aktuell
--                                gefundenen Peripherals neu ab

local loadOk, uilib = pcall(dofile, "uilib.lua")
if not loadOk then
  printError("uilib.lua fehlt oder ist fehlerhaft. Bitte install.lua erneut ausfuehren.")
  return
end

local CONFIG_PATH = uilib.NETWORK_CONFIG_PATH
local USAGE = "Benutzung: network.lua | network.lua change | network.lua change all"
local ROLE_LABELS = { input = "Eingang", output = "Ausgang" }

-- Ein Wired Modem selbst ist Infrastruktur, kein Ein-/Ausgang -- eine
-- Rollenfrage dazu waere sinnlos.
local SKIP_TYPES = { modem = true }

local function scanPeripherals()
  local result = {}
  for _, name in ipairs(peripheral.getNames()) do
    local ptype = peripheral.getType(name)
    if ptype and not SKIP_TYPES[ptype] then
      table.insert(result, { name = name, type = ptype })
    end
  end
  table.sort(result, function(a, b) return a.name < b.name end)
  return result
end

local function loadSavedConfig(path)
  if not fs.exists(path) then
    return {}, false
  end
  local file = fs.open(path, "r")
  local content = file.readAll()
  file.close()
  local ok, config = pcall(textutils.unserialize, content)
  if not ok or type(config) ~= "table" then
    printError(string.format("'%s' ist beschaedigt -- wird ignoriert, alle Peripherals gelten als neu.", path))
    return {}, false
  end
  return config, true
end

local function saveConfig(path, config)
  local file = fs.open(path, "w")
  file.write(textutils.serialize(config))
  file.close()
end

-- Vergleicht den aktuellen Scan mit der gespeicherten Konfiguration.
local function classify(scanned, saved)
  local scannedByName = {}
  for _, entry in ipairs(scanned) do scannedByName[entry.name] = entry end

  local added, changed, unchanged = {}, {}, {}
  for _, entry in ipairs(scanned) do
    local prev = saved[entry.name]
    if type(prev) ~= "table" or not prev.role then
      table.insert(added, entry)
    elseif prev.type ~= entry.type then
      table.insert(changed, { name = entry.name, type = entry.type, previousRole = prev.role, previousType = prev.type })
    else
      table.insert(unchanged, { name = entry.name, type = entry.type, role = prev.role })
    end
  end

  local removed = {}
  for name, prev in pairs(saved) do
    if not scannedByName[name] and type(prev) == "table" then
      table.insert(removed, { name = name, type = prev.type or "?", role = prev.role or "?" })
    end
  end
  table.sort(removed, function(a, b) return a.name < b.name end)

  return added, changed, removed, unchanged
end

-- Fragt die Rolle fuer EIN Peripheral ab. hint ist ein optionaler
-- Zusatztext (z.B. bisherige Rolle), der hinter Name+Typ angezeigt wird.
local function askRole(entry, hint)
  print(string.format("%s [%s]%s", entry.name, entry.type, hint or ""))
  local answer = uilib.askChoice("Rolle festlegen", {
    { key = "i", text = "Eingang" },
    { key = "o", text = "Ausgang" },
  })
  return (answer == "i") and "input" or "output"
end

local function promptRole(entry)
  local hint = entry.previousRole
    and string.format(" (Typ geaendert: %s -> %s, vorher Rolle: %s)", entry.previousType, entry.type, entry.previousRole)
    or ""
  return askRole(entry, hint)
end

-- Standard-Modus: nur neue/geaenderte/entfernte Peripherals anfassen.
local function runAuto()
  print("=== Netzwerk-Konfiguration ===")
  print("Durchsuche das Kabelnetz ...")

  local scanned = scanPeripherals()
  if #scanned == 0 then
    print("Keine Peripherals gefunden -- Modem aktiv? Kabel verbunden?")
    return
  end

  local saved, existed = loadSavedConfig(CONFIG_PATH)
  if existed then
    local count = 0
    for _ in pairs(saved) do count = count + 1 end
    print(string.format("Vorherige Konfiguration geladen: %s (%d Eintrag/Eintraege).", CONFIG_PATH, count))
  else
    print(string.format("Keine vorherige Konfiguration gefunden ('%s') -- alle Peripherals sind neu.", CONFIG_PATH))
  end

  local added, changed, removed, unchanged = classify(scanned, saved)

  print()
  print(string.format("%d Peripherals gefunden (%d neu, %d Typ geaendert, %d entfernt, %d unveraendert).",
    #scanned, #added, #changed, #removed, #unchanged))

  if #removed > 0 then
    print()
    print("Nicht mehr gefunden (Eintrag wird entfernt):")
    for _, entry in ipairs(removed) do
      print(string.format("  %s [%s] (war: %s)", entry.name, entry.type, entry.role))
    end
  end

  local config = {}
  for _, entry in ipairs(unchanged) do
    config[entry.name] = { role = entry.role, type = entry.type }
  end

  local toAsk = {}
  for _, e in ipairs(changed) do table.insert(toAsk, e) end
  for _, e in ipairs(added) do table.insert(toAsk, e) end

  if #toAsk > 0 then
    print()
    for i, entry in ipairs(toAsk) do
      io.write(string.format("[%d/%d] ", i, #toAsk))
      local role = promptRole(entry)
      config[entry.name] = { role = role, type = entry.type }
    end
  end

  if #added == 0 and #changed == 0 and #removed == 0 then
    print()
    print("Keine Aenderungen -- Konfiguration ist aktuell, nichts zu speichern.")
    return
  end

  saveConfig(CONFIG_PATH, config)

  local inputs, outputs = 0, 0
  for _, entry in pairs(config) do
    if entry.role == "input" then inputs = inputs + 1 else outputs = outputs + 1 end
  end
  print()
  print(string.format("Konfiguration gespeichert: %s (%d Eintraege: %d Eingang, %d Ausgang).",
    CONFIG_PATH, inputs + outputs, inputs, outputs))
end

-- "change": zeigt die gespeicherte Konfiguration als Liste, der Nutzer waehlt
-- gezielt einzelne Eintraege aus und aendert nur deren Rolle. Peripherals, die
-- aktuell nicht mehr im Netz gefunden werden, bleiben trotzdem waehlbar
-- (Rolle laesst sich auch fuer abwesende Eintraege korrigieren), werden aber
-- markiert.
local function runChange()
  local saved, existed = loadSavedConfig(CONFIG_PATH)
  if not existed or next(saved) == nil then
    printError(string.format("Keine gespeicherte Konfiguration gefunden ('%s'). Bitte zuerst 'network.lua' ausfuehren.", CONFIG_PATH))
    return
  end

  local present = {}
  for _, entry in ipairs(scanPeripherals()) do present[entry.name] = true end

  local names = {}
  for name, entry in pairs(saved) do
    if type(entry) == "table" and entry.role then
      table.insert(names, name)
    end
  end
  table.sort(names)

  print("=== Netzwerk-Konfiguration: Rolle aendern ===")

  local changedAny = false
  while true do
    print()
    print("Gespeicherte Peripherals:")
    for i, name in ipairs(names) do
      local entry = saved[name]
      local marker = present[name] and "" or " (nicht mehr im Netz gefunden)"
      print(string.format("  %d) %s [%s] - %s%s", i, name, entry.type or "?", ROLE_LABELS[entry.role] or entry.role, marker))
    end

    local choice = uilib.askInt("Nummer waehlen (0 = fertig)", 0, #names)
    if choice == 0 then
      break
    end

    local name = names[choice]
    local entry = saved[name]
    local hint = string.format(" (aktuell: %s)", ROLE_LABELS[entry.role] or entry.role)
    local role = askRole({ name = name, type = entry.type or "?" }, hint)
    entry.role = role
    changedAny = true
    print(string.format("%s -> %s gesetzt.", name, ROLE_LABELS[role]))
  end

  if not changedAny then
    print()
    print("Keine Aenderungen -- nichts zu speichern.")
    return
  end

  saveConfig(CONFIG_PATH, saved)
  print()
  print(string.format("Konfiguration gespeichert: %s.", CONFIG_PATH))
end

-- "change all": fragt fuer wirklich JEDES aktuell gefundene Peripheral die
-- Rolle neu ab, unabhaengig vom bisherigen Stand. Die bisherige Rolle wird
-- nur noch als Hinweis eingeblendet. Peripherals, die verschwunden sind,
-- fallen dabei automatisch aus der neuen Konfiguration heraus.
local function runChangeAll()
  print("=== Netzwerk-Konfiguration: alles neu ===")
  print("Durchsuche das Kabelnetz ...")

  local scanned = scanPeripherals()
  if #scanned == 0 then
    print("Keine Peripherals gefunden -- Modem aktiv? Kabel verbunden?")
    return
  end

  local saved = loadSavedConfig(CONFIG_PATH)

  print(string.format("%d Peripherals gefunden. Rolle wird fuer alle neu abgefragt.", #scanned))
  print()

  local config = {}
  for i, entry in ipairs(scanned) do
    local prev = saved[entry.name]
    local hint = (type(prev) == "table" and prev.role)
      and string.format(" (bisher: %s)", ROLE_LABELS[prev.role] or prev.role)
      or ""
    io.write(string.format("[%d/%d] ", i, #scanned))
    local role = askRole(entry, hint)
    config[entry.name] = { role = role, type = entry.type }
  end

  saveConfig(CONFIG_PATH, config)

  local inputs, outputs = 0, 0
  for _, entry in pairs(config) do
    if entry.role == "input" then inputs = inputs + 1 else outputs = outputs + 1 end
  end
  print()
  print(string.format("Konfiguration gespeichert: %s (%d Eintraege: %d Eingang, %d Ausgang).",
    CONFIG_PATH, inputs + outputs, inputs, outputs))
end

local args = { ... }
local mode = "auto"

if args[1] == "change" then
  if args[2] == nil then
    mode = "change"
  elseif args[2] == "all" and args[3] == nil then
    mode = "change-all"
  else
    printError(USAGE)
    return
  end
elseif args[1] ~= nil then
  printError(USAGE)
  return
end

if mode == "auto" then
  runAuto()
elseif mode == "change" then
  runChange()
else
  runChangeAll()
end
