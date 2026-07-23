-- miner.lua
-- Graebt einen Quader (X x Y x Z) vollstaendig aus.
-- Die Turtle steht dabei nicht im Quader, sondern direkt davor, an dessen
-- unterer linker Ecke, und blickt hinein: die Abmessungen erstrecken sich
-- nach oben, nach rechts und in die Tiefe (nach vorne, vor der Turtle).
-- Aufruf ohne Argumente, Abmessungen werden interaktiv abgefragt.
--
-- Fuer mehrere Turtles gleichzeitig am selben Quader: miner_colony.lua /
-- miner_worker.lua (nutzen dieselbe Grab-Engine aus minerlib.lua).

local loadOk, minerlib = pcall(dofile, "minerlib.lua")
if not loadOk then
  printError("minerlib.lua fehlt oder ist fehlerhaft. Bitte install.lua erneut ausfuehren.")
  return
end

local function askDimension(label)
  while true do
    io.write(label .. ": ")
    local value = tonumber(read())
    if value and value >= 1 and value == math.floor(value) then
      return value
    end
    print("Bitte eine ganze Zahl >= 1 eingeben.")
  end
end

local function validDimension(raw)
  local value = tonumber(raw)
  if value and value >= 1 and value == math.floor(value) then
    return value
  end
  return nil
end

-- Fuer erprobte Nutzer: miner.lua <Hoehe> <Breite> <Tiefe> ueberspringt die
-- interaktive Abfrage, wenn alle drei Argumente gueltig sind.
local args = { ... }
local sizeY, sizeX, sizeZ

if args[1] and args[2] and args[3] then
  sizeY = validDimension(args[1])
  sizeX = validDimension(args[2])
  sizeZ = validDimension(args[3])
  if not (sizeY and sizeX and sizeZ) then
    printError("Ungueltige Argumente. Benutzung: miner.lua <Hoehe> <Breite> <Tiefe>")
    return
  end
else
  print("Quader-Abmessungen eingeben (Turtle startet unten links, Blick in den Quader):")
  sizeY = askDimension("Hoehe (nach oben)")
  sizeX = askDimension("Breite (nach rechts)")
  sizeZ = askDimension("Tiefe (nach vorne)")
end

-- Optional: Kiste/Inventar hinter dem Startpunkt zum automatischen Entladen.
local hasChest
if args[4] ~= nil then
  hasChest = tostring(args[4]):lower():sub(1, 1) == "j"
else
  io.write("Steht eine Kiste/ein Inventar hinter dem Startpunkt zum Entladen? (j/n): ")
  local chestAnswer = read()
  hasChest = chestAnswer ~= nil and chestAnswer:lower():sub(1, 1) == "j"
end

local function confirmRefuel()
  io.write("Aus dem Inventar auftanken und direkt starten? (j/n): ")
  local answer = read()
  return answer ~= nil and answer:lower():sub(1, 1) == "j"
end

minerlib.run(sizeY, sizeX, sizeZ, { hasChest = hasChest, confirmRefuel = confirmRefuel })
