-- minerlib.lua
-- Wiederverwendbare Grab-Engine fuer einen einzelnen Quader-Abschnitt.
-- Wird sowohl von miner.lua (Solo-Betrieb) als auch von miner_colony.lua /
-- miner_worker.lua (mehrere Turtles, je ein Streifen) genutzt.

local minerlib = {}

local SAFETY_FUEL = 15 -- zusaetzlicher Treibstoffpuffer fuer den Rueckweg
local MAX_DIG_TRIES = 6

function minerlib.hasUnlimitedFuel()
  return turtle.getFuelLevel() == "unlimited"
end

-- Grobe Treibstoff-Schaetzung: abzubauende Bloecke + Umwege zwischen den
-- Ebenen + Rueckweg zum Start, mit 10% Puffer.
function minerlib.estimateFuel(x, y, z)
  local blocks = x * y * z
  local layerTravel = y * (x + z)
  local returnTrip = x + y + z
  return math.ceil((blocks + layerTravel + returnTrip) * 1.1) + SAFETY_FUEL
end

-- Verbraucht Brennstoff aus dem Inventar (slotweise, ein Item nach dem
-- anderen), bis der Zielwert erreicht ist oder nichts mehr brennbar ist.
function minerlib.refuelToLevel(target)
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

-- Graebt einen Quader (sizeY x sizeX x sizeZ) vor der Turtle aus. Die
-- Turtle steht dabei einen Block davor, an dessen unterer linker Ecke,
-- und blickt hinein.
--
-- opts:
--   hasChest      - bool, Kiste/Inventar hinter dem Startpunkt vorhanden
--   confirmRefuel - function(needed, current) -> bool, wird gefragt wenn
--                   der Start-Treibstoff nicht reicht. Fehlt sie, wird
--                   ohne Nachfrage automatisch versucht nachzutanken
--                   (fuer unbeaufsichtigte Worker-Turtles).
--   onEvent       - function(event) fuer optionale externe Status-Meldungen
--                   (z.B. per rednet), event = { type = ..., ... }
--
-- Rueckgabe: ok (bool), info { aborted = bool, reason = string|nil }
function minerlib.run(sizeY, sizeX, sizeZ, opts)
  opts = opts or {}
  local hasChest = opts.hasChest
  local onEvent = opts.onEvent or function() end

  -- Position relativ zum Startpunkt (0,0,0). dir: 0=+Z, 1=+X, 2=-Z, 3=-X
  local pos = { x = 0, y = 0, z = 0, dir = 0 }

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

  local function distanceHome()
    return pos.x + pos.y + pos.z
  end

  -- Bricht die Grabung ab, wenn der Treibstoff nicht mehr fuer den Rueckweg
  -- (plus Sicherheitspuffer) reicht.
  local function fuelCriticallyLow()
    if minerlib.hasUnlimitedFuel() then
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
    onEvent({ type = "chest_unloaded" })
  end

  -- Anfangs-Check: Schaetzung vor Start gegen aktuellen Treibstoff pruefen.
  local needed = minerlib.estimateFuel(sizeX, sizeY, sizeZ)
  if not minerlib.hasUnlimitedFuel() and turtle.getFuelLevel() < needed then
    printError(string.format(
      "Zu wenig Treibstoff: %d vorhanden, ~%d geschaetzt benoetigt.",
      turtle.getFuelLevel(), needed))
    onEvent({ type = "fuel_low", current = turtle.getFuelLevel(), needed = needed })

    local shouldRefuel
    if opts.confirmRefuel then
      shouldRefuel = opts.confirmRefuel(needed, turtle.getFuelLevel())
    else
      shouldRefuel = true
    end

    if not shouldRefuel then
      onEvent({ type = "done", aborted = true, reason = "fuel_declined" })
      return false, { aborted = true, reason = "fuel_declined" }
    end

    if not minerlib.refuelToLevel(needed) then
      printError(string.format(
        "Immer noch zu wenig Treibstoff: %d vorhanden, ~%d benoetigt. Abbruch.",
        turtle.getFuelLevel(), needed))
      onEvent({ type = "done", aborted = true, reason = "insufficient_fuel" })
      return false, { aborted = true, reason = "insufficient_fuel" }
    end
    print(string.format("Aufgetankt auf %d. Starte Abbau.", turtle.getFuelLevel()))
    onEvent({ type = "refueled", level = turtle.getFuelLevel() })
  end

  print(string.format("Grabe Quader %dx%dx%d aus (~%d Treibstoff geschaetzt).", sizeX, sizeY, sizeZ, needed))
  onEvent({ type = "started", sizeX = sizeX, sizeY = sizeY, sizeZ = sizeZ, needed = needed })

  local aborted = false
  local abortReason = nil

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
            abortReason = "fuel_critical"
            return
          end

          if hasChest and isInventoryFull() then
            unloadInventory()
          end
        end
      end
      onEvent({ type = "layer_done", layer = yi + 1, totalLayers = sizeY })
    end
  end)

  if not ok then
    printError("Fehler: " .. tostring(err))
    aborted = true
    abortReason = "error"
    onEvent({ type = "error", message = tostring(err) })
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
    onEvent({ type = "done", aborted = true, reason = abortReason })
    return false, { aborted = true, reason = abortReason }
  end

  print("Quader vollstaendig ausgehoben. Turtle ist zurueck am Start.")
  onEvent({ type = "done", aborted = false })
  return true, { aborted = false }
end

return minerlib
