-- install.lua
-- Auf dem CC-Computer ausfuehren, um Skripte von GitHub zu laden:
--   wget https://raw.githubusercontent.com/Reevvvooo/Computer-Craft/main/cc-scripts/install.lua install.lua
--   install.lua

local REPO = "https://raw.githubusercontent.com/Reevvvooo/Computer-Craft/main/cc-scripts/"

local files = {
  "miner.lua",
}

for _, name in ipairs(files) do
  if fs.exists(name) then
    fs.delete(name)
  end

  print("Lade " .. name .. " ...")
  local ok = shell.run("wget", REPO .. name, name)
  if not ok then
    printError("Fehler beim Laden von " .. name)
  end
end

print("Installation abgeschlossen.")
