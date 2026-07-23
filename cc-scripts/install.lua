-- install.lua
-- Auf dem CC-Computer ausfuehren, um Skripte von GitHub zu laden:
--   wget https://raw.githubusercontent.com/Reevvvooo/Computer-Craft/main/cc-scripts/install.lua install.lua
--   install.lua
--
-- Die Liste der zu ladenden Dateien steht in files.txt im Repo (eine
-- Datei pro Zeile). install.lua selbst muss dadurch nicht mehr angefasst
-- werden, wenn neue Skripte dazukommen -- einfach files.txt im Repo
-- erweitern.

local REPO = "https://raw.githubusercontent.com/Reevvvooo/Computer-Craft/main/cc-scripts/"

-- Cache-Busting: raw.githubusercontent.com liefert sonst bis zu einige
-- Minuten lang eine gecachte, veraltete Version aus.
local function fetch(name)
  local url = REPO .. name .. "?nocache=" .. os.epoch("utc")
  local response, err = http.get(url)
  if not response then
    return nil, tostring(err)
  end
  local content = response.readAll()
  response.close()
  if not content or #content == 0 then
    return nil, "leere Antwort"
  end
  return content
end

print("Lade Dateiliste (files.txt) ...")
local manifest, manifestErr = fetch("files.txt")
if not manifest then
  printError("Konnte files.txt nicht laden: " .. tostring(manifestErr))
  return
end

local files = {}
for line in manifest:gmatch("[^\r\n]+") do
  local name = line:match("^%s*(.-)%s*$")
  if name ~= "" then
    table.insert(files, name)
  end
end

for _, name in ipairs(files) do
  print("Lade " .. name .. " ...")
  local content, err = fetch(name)
  if not content then
    printError("Fehler beim Laden von " .. name .. ": " .. err)
  else
    if fs.exists(name) then
      fs.delete(name)
    end
    local file = fs.open(name, "w")
    file.write(content)
    file.close()
    print(name .. " aktualisiert (" .. #content .. " Bytes).")
  end
end

print("Installation abgeschlossen.")
