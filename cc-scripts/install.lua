-- install.lua
-- Auf dem CC-Computer ausfuehren, um Skripte von GitHub zu laden:
--   wget https://raw.githubusercontent.com/<user>/<repo>/main/install.lua install.lua
--   install.lua

local REPO = "https://raw.githubusercontent.com/<dein-user>/cc-scripts/main/"

local files = {
  "miner.lua",
}

for _, name in ipairs(files) do
  print("Lade " .. name .. " ...")
  local ok = shell.run("wget", REPO .. name, name)
  if not ok then
    printError("Fehler beim Laden von " .. name)
  end
end

print("Installation abgeschlossen.")
