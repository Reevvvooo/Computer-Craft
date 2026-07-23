-- install.lua
-- Auf dem CC-Computer ausfuehren, um Skripte von GitHub zu laden:
--   wget https://raw.githubusercontent.com/Reevvvooo/Computer-Craft/main/cc-scripts/install.lua install.lua
--   install.lua

local REPO = "https://raw.githubusercontent.com/Reevvvooo/Computer-Craft/main/cc-scripts/"

local files = {
  "miner.lua",
}

for _, name in ipairs(files) do
  -- Cache-Busting: raw.githubusercontent.com liefert sonst bis zu einige
  -- Minuten lang eine gecachte, veraltete Version aus.
  local url = REPO .. name .. "?nocache=" .. os.epoch("utc")
  print("Lade " .. name .. " ...")

  local response, err = http.get(url)
  if not response then
    printError("Fehler beim Laden von " .. name .. ": " .. tostring(err))
  else
    local content = response.readAll()
    response.close()

    if not content or #content == 0 then
      printError(name .. " ist leer, breche ab (Datei bleibt unveraendert).")
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
end

print("Installation abgeschlossen.")
