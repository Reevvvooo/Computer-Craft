-- uilib.lua
-- Generische Eingabe-Hilfsfunktionen fuer beliebige Computer/Turtle-Skripte
-- (kein Turtle-API noetig).

local uilib = {}

-- Fragt interaktiv eine Ganzzahl ab, bis eine gueltige eingegeben wird.
-- min ist Pflicht, max optional (nil = unbegrenzt nach oben).
function uilib.askInt(label, min, max)
  while true do
    io.write(label .. ": ")
    local value = tonumber(read())
    if value and value >= min and (not max or value <= max) and value == math.floor(value) then
      return value
    end
    print(string.format("Bitte eine ganze Zahl zwischen %d und %s eingeben.", min, max and tostring(max) or "beliebig"))
  end
end

-- Reine Validierung ohne I/O, z.B. zum Parsen von CLI-Argumenten.
-- Gibt die Zahl zurueck wenn gueltig, sonst nil.
function uilib.validInt(raw, min, max)
  local value = tonumber(raw)
  if value and value >= min and (not max or value <= max) and value == math.floor(value) then
    return value
  end
  return nil
end

-- Fragt interaktiv nach einer Auswahl aus mehreren Ein-Buchstaben-Antworten,
-- bis eine gueltige eingegeben wird. choices ist eine Liste von
-- { key = "i", text = "Eingang" } in Anzeige-Reihenfolge. Gibt den
-- gewaehlten (kleingeschriebenen) key zurueck.
function uilib.askChoice(label, choices)
  local valid, parts = {}, {}
  for _, choice in ipairs(choices) do
    local key = choice.key:lower()
    valid[key] = true
    table.insert(parts, string.format("%s=%s", choice.key, choice.text))
  end
  local hint = table.concat(parts, ", ")
  while true do
    io.write(string.format("%s (%s): ", label, hint))
    local answer = read()
    if answer and valid[answer:lower()] then
      return answer:lower()
    end
    print("Bitte eine der folgenden Eingaben verwenden: " .. hint)
  end
end

-- Datei, in der network.lua die Peripheral-Rollen ablegt. Wird bewusst NICHT
-- in files.txt gefuehrt (siehe network.lua) -- install.lua wuerde die
-- gespeicherte Konfiguration sonst bei jedem Update ueberschreiben.
uilib.NETWORK_CONFIG_PATH = "network.cfg"

-- Laedt die von network.lua geschriebene Konfiguration. Erfolg liefert:
--   config       -- Tabelle: Peripheral-Name -> { role = "input"/"output", type = ... }
--   inputNames   -- sortierte Liste der Namen mit role "input"
--   outputNames  -- sortierte Liste der Namen mit role "output"
-- Fehlt die Datei oder ist sie kaputt, liefert es stattdessen nil, Fehlertext.
function uilib.loadNetworkConfig(path)
  path = path or uilib.NETWORK_CONFIG_PATH
  if not fs.exists(path) then
    return nil, string.format("'%s' nicht gefunden. Bitte zuerst network.lua ausfuehren.", path)
  end
  local file = fs.open(path, "r")
  local content = file.readAll()
  file.close()
  local ok, config = pcall(textutils.unserialize, content)
  if not ok or type(config) ~= "table" then
    return nil, string.format("'%s' ist beschaedigt. Bitte network.lua erneut ausfuehren.", path)
  end
  local inputNames, outputNames = {}, {}
  for name, entry in pairs(config) do
    if type(entry) == "table" then
      if entry.role == "input" then
        table.insert(inputNames, name)
      elseif entry.role == "output" then
        table.insert(outputNames, name)
      end
    end
  end
  table.sort(inputNames)
  table.sort(outputNames)
  return config, inputNames, outputNames
end

return uilib
