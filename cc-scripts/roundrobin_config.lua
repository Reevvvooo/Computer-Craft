-- roundrobin_config.lua
-- Verwaltet Gruppen fuer roundrobin.lua: welche Eingaenge/Ausgaenge aus
-- network.cfg zusammengehoeren, mit welchem Item-Filter, welcher Batchgroesse
-- und welchem Zyklus-Intervall. Das Ergebnis landet in roundrobin.cfg und wird
-- von roundrobin.lua bei jedem Zyklus neu eingelesen -- Aenderungen hier wirken
-- also, ohne roundrobin.lua neu zu starten.
--
-- Kein Dauerbetrieb, kein Event-Loop -- das Skript beendet sich nach jedem
-- Aufruf, wie network.lua. Erst "s" (speichern) schreibt roundrobin.cfg; "q"
-- verwirft alle Aenderungen der laufenden Sitzung.
--
-- Setzt eine bereits mit network.lua erstellte network.cfg voraus: dort werden
-- die Eingaenge/Ausgaenge festgelegt, hier nur noch zu Gruppen zusammengefasst.
--
-- Aufruf:
--   roundrobin_config.lua

local loadOk, uilib = pcall(dofile, "uilib.lua")
if not loadOk then
  printError("uilib.lua fehlt oder ist fehlerhaft. Bitte install.lua erneut ausfuehren.")
  return
end

local RR_CONFIG_PATH = "roundrobin.cfg"
local FILTER_LABELS = { none = "kein Filter", whitelist = "Whitelist", blacklist = "Blacklist" }

local netConfig, inputNames, outputNames = uilib.loadNetworkConfig()
if not netConfig then
  printError(inputNames)
  return
end

if #inputNames == 0 or #outputNames == 0 then
  printError("network.cfg enthaelt noch keine Eingaenge/Ausgaenge.")
  printError("Bitte zuerst network.lua ausfuehren und Rollen vergeben.")
  return
end

-- ---------------------------------------------------------------------------
-- Laden/Speichern (gleiches Muster wie network.lua: fs + textutils.serialize)
-- ---------------------------------------------------------------------------

local function loadGroups(path)
  if not fs.exists(path) then
    return {}
  end
  local file = fs.open(path, "r")
  local content = file.readAll()
  file.close()
  local ok, data = pcall(textutils.unserialize, content)
  if not ok or type(data) ~= "table" or type(data.groups) ~= "table" then
    printError(string.format("'%s' ist beschaedigt -- wird ignoriert, leere Gruppenliste.", path))
    return {}
  end
  return data.groups
end

local function saveGroups(path, groups)
  local file = fs.open(path, "w")
  file.write(textutils.serialize({ groups = groups }))
  file.close()
end

local groups = loadGroups(RR_CONFIG_PATH)

-- ---------------------------------------------------------------------------
-- Hilfsfunktionen
-- ---------------------------------------------------------------------------

local function hasGroupNamed(name)
  for _, g in ipairs(groups) do
    if g.name == name then
      return true
    end
  end
  return false
end

local function setToSortedList(set)
  local list = {}
  for name in pairs(set) do
    table.insert(list, name)
  end
  table.sort(list)
  return list
end

local function askYesNo(label)
  return uilib.askChoice(label, {
    { key = "j", text = "Ja" },
    { key = "n", text = "Nein" },
  }) == "j"
end

-- Laesst den Nutzer aus `names` (Liste) eine Teilmenge an-/abwaehlen. `selected`
-- ist der Ausgangszustand als Menge (Name -> true), wird nicht veraendert.
local function pickSubset(label, names, selected)
  local picked = {}
  for name in pairs(selected) do
    picked[name] = true
  end

  while true do
    print()
    print(label .. ":")
    for i, name in ipairs(names) do
      print(string.format("  %d) [%s] %s", i, picked[name] and "x" or " ", name))
    end
    print("  Zahl = an/abwaehlen, a = alle, k = keine, 0 = fertig")
    io.write("> ")
    local answer = read()

    if answer == "0" then
      break
    elseif answer == "a" then
      for _, name in ipairs(names) do
        picked[name] = true
      end
    elseif answer == "k" then
      picked = {}
    else
      local n = tonumber(answer)
      if n and names[n] then
        local name = names[n]
        picked[name] = not picked[name] and true or nil
      else
        print("Ungueltige Eingabe.")
      end
    end
  end

  return picked
end

local function askFilter(currentMode, currentItems)
  local answer = uilib.askChoice("Item-Filter", {
    { key = "n", text = "kein Filter" },
    { key = "w", text = "Whitelist" },
    { key = "b", text = "Blacklist" },
  })
  local filterMode = (answer == "w") and "whitelist" or (answer == "b") and "blacklist" or "none"

  local items = {}
  if filterMode ~= "none" then
    local existing = {}
    for id in pairs(currentItems or {}) do
      table.insert(existing, id)
    end
    table.sort(existing)
    if #existing > 0 then
      print("Bisherige Item-IDs: " .. table.concat(existing, ", "))
    end
    io.write("Item-IDs kommagetrennt (z.B. minecraft:iron_ore,minecraft:copper_ore): ")
    local raw = read() or ""
    for id in raw:gmatch("[^,%s]+") do
      items[id] = true
    end
    if next(items) == nil then
      print("Keine Item-IDs eingegeben -- Filter laesst dann nichts durch (Whitelist) bzw. alles (Blacklist).")
    end
  end

  return filterMode, items
end

local function askInterval(current)
  local hint = current and string.format(" (bisher: %s)", tostring(current)) or ""
  while true do
    io.write("Intervall zwischen Zyklen in Sekunden, min 0.5" .. hint .. ": ")
    local value = tonumber(read())
    if value and value >= 0.5 then
      return value
    end
    print("Bitte eine Zahl >= 0.5 eingeben.")
  end
end

local function summarize(group)
  local inCount = group.allInputs and #inputNames or #group.inputs
  local outCount = group.allOutputs and #outputNames or #group.outputs
  return string.format("%s: %d Eingang/Eingaenge, %d Ausgang/Ausgaenge, %s, Batch %d, alle %ss",
    group.name, inCount, outCount, FILTER_LABELS[group.filterMode] or group.filterMode,
    group.batchSize, tostring(group.intervalSeconds))
end

-- Legt eine neue Gruppe an oder bearbeitet `existing`. Der Name einer
-- bestehenden Gruppe laesst sich hier bewusst nicht aendern (Umbenennen waere
-- gleichbedeutend mit Loeschen+Neuanlegen, das deckt "d"+"n" schon ab).
local function editGroup(existing)
  local name = existing and existing.name
  if not name then
    while true do
      io.write("Name der neuen Gruppe: ")
      name = read()
      if name == nil or name == "" then
        print("Name darf nicht leer sein.")
      elseif hasGroupNamed(name) then
        print("Name bereits vergeben.")
      else
        break
      end
    end
  end

  local currentInputSet = {}
  for _, n in ipairs((existing and existing.inputs) or {}) do
    currentInputSet[n] = true
  end
  print()
  local allInputs = askYesNo(string.format("Alle Eingaenge verwenden (%d verfuegbar)?", #inputNames))
  local inputs = {}
  if not allInputs then
    inputs = setToSortedList(pickSubset("Eingaenge auswaehlen", inputNames, currentInputSet))
    if #inputs == 0 then
      print("Warnung: keine Eingaenge ausgewaehlt -- Gruppe bewegt aktuell nichts.")
    end
  end

  local currentOutputSet = {}
  for _, n in ipairs((existing and existing.outputs) or {}) do
    currentOutputSet[n] = true
  end
  print()
  local allOutputs = askYesNo(string.format("Alle Ausgaenge verwenden (%d verfuegbar)?", #outputNames))
  local outputs = {}
  if not allOutputs then
    outputs = setToSortedList(pickSubset("Ausgaenge auswaehlen", outputNames, currentOutputSet))
    if #outputs == 0 then
      print("Warnung: keine Ausgaenge ausgewaehlt -- Gruppe bewegt aktuell nichts.")
    end
  end

  print()
  local filterMode, items = askFilter(existing and existing.filterMode, existing and existing.items)

  print()
  local batchSize = uilib.askInt("Batchgroesse pro Transfer (Items)", 1)
  local intervalSeconds = askInterval(existing and existing.intervalSeconds)

  return {
    name = name,
    allInputs = allInputs, inputs = inputs,
    allOutputs = allOutputs, outputs = outputs,
    filterMode = filterMode, items = items,
    batchSize = batchSize,
    intervalSeconds = intervalSeconds,
  }
end

-- ---------------------------------------------------------------------------
-- Hauptmenue
-- ---------------------------------------------------------------------------

print("=== Round-Robin-Konfiguration ===")
print(string.format("network.cfg: %d Eingaenge, %d Ausgaenge verfuegbar.", #inputNames, #outputNames))

while true do
  print()
  if #groups == 0 then
    print("Keine Gruppen konfiguriert.")
  else
    print("Gruppen:")
    for i, g in ipairs(groups) do
      print(string.format("  %d) %s", i, summarize(g)))
    end
  end
  print()
  print("n = neue Gruppe, Zahl = bearbeiten, dZahl = loeschen (z.B. d2), s = speichern & Ende, q = ohne speichern beenden")
  io.write("> ")
  local answer = read()

  if answer == "q" then
    print("Beendet ohne zu speichern.")
    return
  elseif answer == "s" then
    saveGroups(RR_CONFIG_PATH, groups)
    print(string.format("Gespeichert: %s (%d Gruppe(n)).", RR_CONFIG_PATH, #groups))
    return
  elseif answer == "n" then
    print()
    print("=== Neue Gruppe ===")
    local group = editGroup(nil)
    table.insert(groups, group)
    print(string.format("Gruppe '%s' angelegt (noch nicht gespeichert -- 's' zum Speichern).", group.name))
  elseif answer and answer:match("^d%d+$") then
    local index = tonumber(answer:sub(2))
    if groups[index] then
      print(string.format("Gruppe '%s' geloescht (noch nicht gespeichert -- 's' zum Speichern).", groups[index].name))
      table.remove(groups, index)
    else
      print("Ungueltige Nummer.")
    end
  else
    local index = tonumber(answer)
    if index and groups[index] then
      print()
      print(string.format("=== Gruppe bearbeiten: %s ===", groups[index].name))
      groups[index] = editGroup(groups[index])
      print("Aenderung uebernommen (noch nicht gespeichert -- 's' zum Speichern).")
    else
      print("Ungueltige Eingabe.")
    end
  end
end
