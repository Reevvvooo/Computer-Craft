-- startup_config.lua
-- Verwaltet, welche Programme startup.lua beim Hochfahren des Computers
-- automatisch startet. Jeder Eintrag hat einen Namen, ein Programm (z.B.
-- "roundrobin.lua"), optionale Argumente und einen Aktiv/Inaktiv-Schalter.
-- Das Ergebnis landet in startup.cfg und wird von startup.lua bei jedem
-- Boot neu eingelesen -- Aenderungen hier wirken also erst beim naechsten
-- Neustart (oder "reboot").
--
-- Kein Dauerbetrieb, kein Event-Loop -- das Skript beendet sich nach jedem
-- Aufruf, wie roundrobin_config.lua. Erst "s" (speichern) schreibt
-- startup.cfg; "q" verwirft alle Aenderungen der laufenden Sitzung.
--
-- Aufruf:
--   startup_config.lua

local loadOk, uilib = pcall(dofile, "uilib.lua")
if not loadOk then
  printError("uilib.lua fehlt oder ist fehlerhaft. Bitte install.lua erneut ausfuehren.")
  return
end

local STARTUP_CONFIG_PATH = "startup.cfg"

-- Diese Dateien tauchen bewusst nicht in der Programm-Vorschlagsliste auf:
-- startup.lua darf sich nicht selbst starten, startup_config.lua wuerde beim
-- Booten auf eine Eingabe warten und den Computer blockieren, uilib.lua und
-- install.lua sind keine eigenstaendigen Programme.
local HIDDEN_FROM_SUGGESTIONS = {
  ["startup.lua"] = true,
  ["startup_config.lua"] = true,
  ["uilib.lua"] = true,
  ["install.lua"] = true,
}

-- ---------------------------------------------------------------------------
-- Laden/Speichern (gleiches Muster wie roundrobin_config.lua: fs +
-- textutils.serialize)
-- ---------------------------------------------------------------------------

local function loadEntries(path)
  if not fs.exists(path) then
    return {}
  end
  local file = fs.open(path, "r")
  local content = file.readAll()
  file.close()
  local ok, data = pcall(textutils.unserialize, content)
  if not ok or type(data) ~= "table" or type(data.entries) ~= "table" then
    printError(string.format("'%s' ist beschaedigt -- wird ignoriert, leere Liste.", path))
    return {}
  end
  return data.entries
end

local function saveEntries(path, entries)
  local file = fs.open(path, "w")
  file.write(textutils.serialize({ entries = entries }))
  file.close()
end

local entries = loadEntries(STARTUP_CONFIG_PATH)

-- ---------------------------------------------------------------------------
-- Hilfsfunktionen
-- ---------------------------------------------------------------------------

local function hasEntryNamed(name)
  for _, e in ipairs(entries) do
    if e.name == name then
      return true
    end
  end
  return false
end

local function askYesNo(label)
  return uilib.askChoice(label, {
    { key = "j", text = "Ja" },
    { key = "n", text = "Nein" },
  }) == "j"
end

local function listRunnableFiles()
  local files = {}
  for _, name in ipairs(fs.list(".")) do
    if not fs.isDir(name) and name:match("%.lua$") and not HIDDEN_FROM_SUGGESTIONS[name] then
      table.insert(files, name)
    end
  end
  table.sort(files)
  return files
end

-- Laesst den Nutzer ein Programm entweder aus der Vorschlagsliste (Nummer)
-- waehlen oder einen beliebigen Dateinamen eingeben -- letzteres auch dann
-- gueltig, wenn die Datei aktuell (noch) nicht existiert, z.B. weil sie erst
-- beim naechsten install.lua-Lauf dazukommt.
local function askProgram(current)
  local files = listRunnableFiles()
  while true do
    print()
    if #files > 0 then
      print("Verfuegbare Programme:")
      for i, name in ipairs(files) do
        print(string.format("  %d) %s", i, name))
      end
    end
    local hint = current and string.format(" (bisher: %s)", current) or ""
    io.write("Nummer oder Dateiname" .. hint .. ": ")
    local answer = read()
    local index = tonumber(answer)

    local program = nil
    if index and files[index] then
      program = files[index]
    elseif answer and answer ~= "" then
      program = answer
    end

    if not program then
      print("Bitte eine Nummer oder einen Dateinamen eingeben.")
    elseif program == "startup.lua" then
      print("startup.lua darf sich nicht selbst starten.")
    else
      return program
    end
  end
end

local function askArgs(current)
  local hint = current and #current > 0 and string.format(" (bisher: %s)", table.concat(current, " ")) or ""
  io.write("Argumente, leerzeichengetrennt, leer = keine" .. hint .. ": ")
  local raw = read() or ""
  local args = {}
  for token in raw:gmatch("%S+") do
    table.insert(args, token)
  end
  return args
end

local function summarize(entry)
  local argsText = #entry.args > 0 and (" " .. table.concat(entry.args, " ")) or ""
  local status = entry.enabled and "aktiv" or "deaktiviert"
  return string.format("%s: %s%s (%s)", entry.name, entry.program, argsText, status)
end

-- Legt einen neuen Eintrag an oder bearbeitet `existing`. Der Name eines
-- bestehenden Eintrags laesst sich hier bewusst nicht aendern (Umbenennen
-- waere gleichbedeutend mit Loeschen+Neuanlegen, das deckt "d"+"n" schon ab).
local function editEntry(existing)
  local name = existing and existing.name
  if not name then
    while true do
      io.write("Name des Eintrags: ")
      name = read()
      if name == nil or name == "" then
        print("Name darf nicht leer sein.")
      elseif hasEntryNamed(name) then
        print("Name bereits vergeben.")
      else
        break
      end
    end
  end

  print()
  local program = askProgram(existing and existing.program)
  print()
  local args = askArgs(existing and existing.args)
  print()
  local enabled = askYesNo("Beim Hochfahren aktiv?")

  return {
    name = name,
    program = program,
    args = args,
    enabled = enabled,
  }
end

-- ---------------------------------------------------------------------------
-- Hauptmenue
-- ---------------------------------------------------------------------------

print("=== Startup-Konfiguration ===")

while true do
  print()
  if #entries == 0 then
    print("Keine Eintraege konfiguriert.")
  else
    print("Eintraege (Reihenfolge = Startreihenfolge bei genau einem aktiven Eintrag):")
    for i, e in ipairs(entries) do
      print(string.format("  %d) %s", i, summarize(e)))
    end
  end
  print()
  print("n = neuer Eintrag, Zahl = bearbeiten, dZahl = loeschen (z.B. d2), s = speichern & Ende, q = ohne speichern beenden")
  io.write("> ")
  local answer = read()

  if answer == "q" then
    print("Beendet ohne zu speichern.")
    return
  elseif answer == "s" then
    saveEntries(STARTUP_CONFIG_PATH, entries)
    print(string.format("Gespeichert: %s (%d Eintrag/Eintraege). Wirkt ab dem naechsten Neustart.", STARTUP_CONFIG_PATH, #entries))
    return
  elseif answer == "n" then
    print()
    print("=== Neuer Eintrag ===")
    local entry = editEntry(nil)
    table.insert(entries, entry)
    print(string.format("Eintrag '%s' angelegt (noch nicht gespeichert -- 's' zum Speichern).", entry.name))
  elseif answer and answer:match("^d%d+$") then
    local index = tonumber(answer:sub(2))
    if entries[index] then
      print(string.format("Eintrag '%s' geloescht (noch nicht gespeichert -- 's' zum Speichern).", entries[index].name))
      table.remove(entries, index)
    else
      print("Ungueltige Nummer.")
    end
  else
    local index = tonumber(answer)
    if index and entries[index] then
      print()
      print(string.format("=== Eintrag bearbeiten: %s ===", entries[index].name))
      entries[index] = editEntry(entries[index])
      print("Aenderung uebernommen (noch nicht gespeichert -- 's' zum Speichern).")
    else
      print("Ungueltige Eingabe.")
    end
  end
end
