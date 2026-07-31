-- turtlelib.lua
-- Wiederverwendbare, turtle-spezifische Hilfsfunktionen (Treibstoff,
-- Bewegung/Graben, Inventar) fuer Turtle-Skripte.

local turtlelib = {}

local MAX_DIG_TRIES = 6

function turtlelib.hasUnlimitedFuel()
  return turtle.getFuelLevel() == "unlimited"
end

-- Verbraucht Brennstoff aus dem Inventar (slotweise, ein Item nach dem
-- anderen), bis der Zielwert erreicht ist oder nichts mehr brennbar ist.
function turtlelib.refuelToLevel(target)
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

-- Position/Blickrichtung relativ zu einem Startpunkt (0,0,0).
-- dir: 0=+Z, 1=+X, 2=-Z, 3=-X
function turtlelib.newPos()
  return { x = 0, y = 0, z = 0, dir = 0 }
end

function turtlelib.turnRight(pos)
  turtle.turnRight()
  pos.dir = (pos.dir + 1) % 4
end

function turtlelib.turnLeft(pos)
  turtle.turnLeft()
  pos.dir = (pos.dir + 3) % 4
end

-- Dreht auf dem kuerzesten Weg (nie mehr als eine Drehung noetig, ausser
-- bei einer 180-Grad-Wende).
function turtlelib.faceDir(pos, target)
  local diff = (target - pos.dir) % 4
  if diff == 1 then
    turtlelib.turnRight(pos)
  elseif diff == 3 then
    turtlelib.turnLeft(pos)
  elseif diff == 2 then
    turtlelib.turnRight(pos)
    turtlelib.turnRight(pos)
  end
end

function turtlelib.digRetry(detectFn, digFn)
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

function turtlelib.forward(pos)
  if not turtlelib.digRetry(turtle.detect, turtle.dig) then
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

function turtlelib.up(pos)
  if not turtlelib.digRetry(turtle.detectUp, turtle.digUp) then
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

function turtlelib.down(pos)
  if not turtlelib.digRetry(turtle.detectDown, turtle.digDown) then
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
function turtlelib.goTo(pos, tx, ty, tz)
  while pos.y < ty do turtlelib.up(pos) end
  while pos.y > ty do turtlelib.down(pos) end

  if pos.x < tx then
    turtlelib.faceDir(pos, 1)
    while pos.x < tx do turtlelib.forward(pos) end
  elseif pos.x > tx then
    turtlelib.faceDir(pos, 3)
    while pos.x > tx do turtlelib.forward(pos) end
  end

  if pos.z < tz then
    turtlelib.faceDir(pos, 0)
    while pos.z < tz do turtlelib.forward(pos) end
  elseif pos.z > tz then
    turtlelib.faceDir(pos, 2)
    while pos.z > tz do turtlelib.forward(pos) end
  end
end

function turtlelib.distanceHome(pos)
  return pos.x + pos.y + pos.z
end

function turtlelib.isInventoryFull()
  for slot = 1, 16 do
    if turtle.getItemCount(slot) == 0 then
      return false
    end
  end
  return true
end

-- Legt den Inhalt aller Slots in die Kiste hinter dem Startpunkt (dir 2,
-- also entgegen der urspruenglichen Blickrichtung).
function turtlelib.dropAllItems(pos)
  local originalSlot = turtle.getSelectedSlot()
  turtlelib.faceDir(pos, 2)
  for slot = 1, 16 do
    if turtle.getItemCount(slot) > 0 then
      turtle.select(slot)
      turtle.drop()
    end
  end
  turtle.select(originalSlot)
  turtlelib.faceDir(pos, 0)
end

return turtlelib
