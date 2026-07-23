-- miner.lua
-- Graebt einen Quader (X x Y x Z) vollstaendig aus.
-- Die Turtle steht dabei nicht im Quader, sondern direkt davor, an dessen
-- unterer linker Ecke, und blickt hinein: die Abmessungen erstrecken sich
-- nach oben, nach rechts und in die Tiefe (nach vorne, vor der Turtle).
-- Aufruf ohne Argumente, Abmessungen werden interaktiv abgefragt.

local SAFETY_FUEL = 15 -- zusaetzlicher Treibstoffpuffer fuer den Rueckweg
local MAX_DIG_TRIES = 6

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

-- Position relativ zum Startpunkt (0,0,0). dir: 0=+Z, 1=+X, 2=-Z, 3=-X
local pos = { x = 0, y = 0, z = 0, dir = 0 }

local function hasUnlimitedFuel()
  return turtle.getFuelLevel() == "unlimited"
end

local function turnRight()
  turtle.turnRight()
  pos.dir = (pos.dir + 1) % 4
end

local function turnLeft()
  turtle.turnLeft()
  pos.dir = (pos.dir + 3) % 4
end

-- Dreht auf dem kuerzesten Weg (nie mehr als eine Drehung noetig, ausser
-- bei einer 180-Grad-Wende).
local function faceDir(target)
  local diff = (target - pos.dir) % 4
  if diff == 1 then
    turnRight()
  elseif diff == 3 then
    turnLeft()
  elseif diff == 2 then
    turnRight()
    turnRight()
  end
end

local function digRetry(detectFn, digFn)
  local tries = 0
  while detectFn() do
    if digFn() then
      tries = 0
    else
      tries = tries + 1
      if tries > MAX_DIG_TRIES then
        return false
      end
      turtle.attack()
      sleep(0.4)
    end
  end
  return true
end

local function forward()
  if not digRetry(turtle.detect, turtle.dig) then
    error("Block vor der Turtle konnte nicht abgebaut werden.")
  end
  local tries = 0
  while not turtle.forward() do
    turtle.attack()
    tries = tries + 1
    if tries > MAX_DIG_TRIES then
      error("Konnte nicht vorwaerts fahren (blockiert oder kein Treibstoff).")
    end
    sleep(0.4)
  end
  if pos.dir == 0 then pos.z = pos.z + 1
  elseif pos.dir == 1 then pos.x = pos.x + 1
  elseif pos.dir == 2 then pos.z = pos.z - 1
  else pos.x = pos.x - 1 end
end

local function up()
  if not digRetry(turtle.detectUp, turtle.digUp) then
    error("Block ueber der Turtle konnte nicht abgebaut werden.")
  end
  local tries = 0
  while not turtle.up() do
    turtle.attackUp()
    tries = tries + 1
    if tries > MAX_DIG_TRIES then
      error("Konnte nicht nach oben fahren (blockiert oder kein Treibstoff).")
    end
    sleep(0.4)
  end
  pos.y = pos.y + 1
end

local function down()
  if not digRetry(turtle.detectDown, turtle.digDown) then
    error("Block unter der Turtle konnte nicht abgebaut werden.")
  end
  local tries = 0
  while not turtle.down() do
    turtle.attackDown()
    tries = tries + 1
    if tries > MAX_DIG_TRIES then
      error("Konnte nicht nach unten fahren (blockiert oder kein Treibstoff).")
    end
    sleep(0.4)
  end
  pos.y = pos.y - 1
end

-- Bewegt die Turtle zu einer Zielposition und graebt dabei alles im Weg frei.
local function goTo(tx, ty, tz)
  while pos.y < ty do up() end
  while pos.y > ty do down() end

  if pos.x < tx then
    faceDir(1)
    while pos.x < tx do forward() end
  elseif pos.x > tx then
    faceDir(3)
    while pos.x > tx do forward() end
  end

  if pos.z < tz then
    faceDir(0)
    while pos.z < tz do forward() end
  elseif pos.z > tz then
    faceDir(2)
    while pos.z > tz do forward() end
  end
end

-- Grobe Treibstoff-Schaetzung: abzubauende Bloecke + Umwege zwischen den
-- Ebenen + Rueckweg zum Start, mit 10% Puffer.
local function estimateFuel(x, y, z)
  local blocks = x * y * z
  local layerTravel = y * (x + z)
  local returnTrip = x + y + z
  return math.ceil((blocks + layerTravel + returnTrip) * 1.1) + SAFETY_FUEL
end

local function distanceHome()
  return pos.x + pos.y + pos.z
end

-- Bricht die Grabung ab, wenn der Treibstoff nicht mehr fuer den Rueckweg
-- (plus Sicherheitspuffer) reicht.
local function fuelCriticallyLow()
  if hasUnlimitedFuel() then
    return false
  end
  return turtle.getFuelLevel() < distanceHome() + SAFETY_FUEL
end

local function goHome()
  goTo(0, 0, 0)
  faceDir(0)
end

-- Legt den Inhalt aller Slots in die Kiste hinter dem Startpunkt (dir 2,
-- also entgegen der urspruenglichen Blickrichtung). Turtle muss bei Aufruf
-- bereits an Position (0,0,0) stehen.
local function dropAllItems()
  local originalSlot = turtle.getSelectedSlot()
  faceDir(2)
  for slot = 1, 16 do
    if turtle.getItemCount(slot) > 0 then
      turtle.select(slot)
      turtle.drop()
    end
  end
  turtle.select(originalSlot)
  faceDir(0)
end

local function isInventoryFull()
  for slot = 1, 16 do
    if turtle.getItemCount(slot) == 0 then
      return false
    end
  end
  return true
end

-- Faehrt zwischendurch zum Start, entlaedt in die Kiste und kehrt an die
-- Abbaustelle zurueck.
local function unloadInventory()
  local savedX, savedY, savedZ = pos.x, pos.y, pos.z
  goTo(0, 0, 0)
  dropAllItems()
  goTo(savedX, savedY, savedZ)
end

-- Verbraucht Brennstoff aus dem Inventar (slotweise, ein Item nach dem
-- anderen), bis der Zielwert erreicht ist oder nichts mehr brennbar ist.
local function refuelToLevel(target)
  local originalSlot = turtle.getSelectedSlot()
  for slot = 1, 16 do
    if turtle.getFuelLevel() >= target then
      break
    end
    turtle.select(slot)
    while turtle.getFuelLevel() < target and turtle.refuel(1) do end
  end
  turtle.select(originalSlot)
  return turtle.getFuelLevel() >= target
end

-- Anfangs-Check: Schaetzung vor Programmstart gegen aktuellen Treibstoff pruefen.
local needed = estimateFuel(sizeX, sizeY, sizeZ)
if not hasUnlimitedFuel() and turtle.getFuelLevel() < needed then
  printError(string.format(
    "Zu wenig Treibstoff: %d vorhanden, ~%d geschaetzt benoetigt.",
    turtle.getFuelLevel(), needed))
  io.write("Aus dem Inventar auftanken und direkt starten? (j/n): ")
  local answer = read()
  if not (answer and answer:lower():sub(1, 1) == "j") then
    return
  end
  if not refuelToLevel(needed) then
    printError(string.format(
      "Immer noch zu wenig Treibstoff: %d vorhanden, ~%d benoetigt. Abbruch.",
      turtle.getFuelLevel(), needed))
    return
  end
  print(string.format("Aufgetankt auf %d. Starte Abbau.", turtle.getFuelLevel()))
end

print(string.format("Grabe Quader %dx%dx%d aus (~%d Treibstoff geschaetzt).", sizeX, sizeY, sizeZ, needed))

local aborted = false

local ok, err = pcall(function()
  for yi = 0, sizeY - 1 do
    local zAscending = (yi % 2 == 0)
    for zStep = 0, sizeZ - 1 do
      local zi = zAscending and zStep or (sizeZ - 1 - zStep)
      local xAscending = (zStep % 2 == 0)
      for xStep = 0, sizeX - 1 do
        local xi = xAscending and xStep or (sizeX - 1 - xStep)
        -- +1 auf Z: die Turtle steht selbst einen Block vor dem Quader.
        goTo(xi, yi, zi + 1)

        -- Regelmaessiger Fuel-Check, damit die Turtle rechtzeitig umkehren kann.
        if fuelCriticallyLow() then
          aborted = true
          return
        end

        if hasChest and isInventoryFull() then
          unloadInventory()
        end
      end
    end
  end
end)

if not ok then
  printError("Fehler: " .. tostring(err))
  aborted = true
end

print("Kehre zum Startpunkt zurueck ...")
local homeOk, homeErr = pcall(goHome)
if not homeOk then
  printError("Konnte nicht vollstaendig zurueckkehren: " .. tostring(homeErr))
end

if hasChest and homeOk then
  local unloadOk, unloadErr = pcall(dropAllItems)
  if not unloadOk then
    printError("Konnte Inventar nicht vollstaendig in die Kiste entladen: " .. tostring(unloadErr))
  end
end

if aborted then
  printError("Abbau abgebrochen (Treibstoff oder Fehler). Rueckkehr wurde versucht.")
else
  print("Quader vollstaendig ausgehoben. Turtle ist zurueck am Start.")
end
