-- miner.lua
-- Graebt einen Quader (X x Y x Z) vollstaendig aus.
-- Die Turtle startet in der unteren linken Ecke des Quaders und blickt
-- in Richtung der Z-Achse (wie ein Spieler, der beim Bauen "vorwaerts" schaut).
-- Aufruf: miner.lua <X> <Y> <Z>

local SAFETY_FUEL = 15 -- zusaetzlicher Treibstoffpuffer fuer den Rueckweg
local MAX_DIG_TRIES = 6

local args = { ... }
local sizeX = tonumber(args[1])
local sizeY = tonumber(args[2])
local sizeZ = tonumber(args[3])

if not sizeX or not sizeY or not sizeZ or sizeX < 1 or sizeY < 1 or sizeZ < 1 then
  printError("Benutzung: miner.lua <X> <Y> <Z>")
  return
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

local function faceDir(target)
  while pos.dir ~= target do
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

-- Anfangs-Check: Schaetzung vor Programmstart gegen aktuellen Treibstoff pruefen.
local needed = estimateFuel(sizeX, sizeY, sizeZ)
if not hasUnlimitedFuel() and turtle.getFuelLevel() < needed then
  printError(string.format(
    "Zu wenig Treibstoff: %d vorhanden, ~%d geschaetzt benoetigt.",
    turtle.getFuelLevel(), needed))
  return
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
        goTo(xi, yi, zi)

        -- Regelmaessiger Fuel-Check, damit die Turtle rechtzeitig umkehren kann.
        if fuelCriticallyLow() then
          aborted = true
          return
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

if aborted then
  printError("Abbau abgebrochen (Treibstoff oder Fehler). Rueckkehr wurde versucht.")
else
  print("Quader vollstaendig ausgehoben. Turtle ist zurueck am Start.")
end
