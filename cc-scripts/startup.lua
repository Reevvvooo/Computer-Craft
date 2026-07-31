-- startup.lua
-- Wird von CraftOS automatisch beim Hochfahren des Computers ausgefuehrt --
-- der Dateiname ist dafuer reserviert (siehe cc-tweaked-1.21.1-reference.md,
-- Abschnitt 3.1). Liest startup.cfg, das startup_config.lua schreibt, und
-- startet die dort als aktiv markierten Programme mit ihren Argumenten.
--
-- Genau ein aktiver Eintrag laeuft direkt im Vordergrund. Bei mehreren
-- aktiven Eintraegen laufen sie gleichzeitig (parallel.waitForAll), analog zu
-- den Gruppen in roundrobin.lua. shell.run faengt Fehler im gestarteten
-- Programm selbst ab und meldet sie nur auf dem Bildschirm -- ein
-- abstuerzendes Programm reisst die anderen also nicht mit.
--
-- Gibt es keine (aktive) Konfiguration, tut dieses Skript nichts weiter und
-- CraftOS faellt wie gewohnt in den interaktiven Shell-Prompt.
--
-- Konfiguration ueber:
--   startup_config.lua

local STARTUP_CONFIG_PATH = "startup.cfg"

local function loadEntries(path)
  if not fs.exists(path) then
    return {}
  end
  local file = fs.open(path, "r")
  local content = file.readAll()
  file.close()
  local ok, data = pcall(textutils.unserialize, content)
  if not ok or type(data) ~= "table" or type(data.entries) ~= "table" then
    printError(string.format("'%s' ist beschaedigt -- wird ignoriert.", path))
    return {}
  end
  return data.entries
end

local entries = loadEntries(STARTUP_CONFIG_PATH)

local active = {}
for _, entry in ipairs(entries) do
  if entry.enabled and entry.program then
    table.insert(active, entry)
  end
end

if #active == 0 then
  return
end

local function runEntry(entry)
  print(string.format("=== Starte %s (%s) ===", entry.name, entry.program))
  local ok = shell.run(entry.program, table.unpack(entry.args or {}))
  if not ok then
    printError(string.format("'%s' (%s) wurde mit Fehler beendet.", entry.name, entry.program))
  end
end

local function runAll()
  if #active == 1 then
    runEntry(active[1])
    return
  end
  local runners = {}
  for _, entry in ipairs(active) do
    table.insert(runners, function() runEntry(entry) end)
  end
  parallel.waitForAll(table.unpack(runners))
end

local ok, err = pcall(runAll)
if not ok then
  printError("Abbruch: " .. tostring(err))
end
