-- miner_colony.lua
-- Koordiniert bis zu 5 Turtles, die gemeinsam denselben Quader ausgraben.
-- Diese Turtle ist Koordinator UND graebt selbst mit (Streifen 1). Die
-- anderen Turtles laufen miner_worker.lua und melden sich per Funk an.
--
-- Aufbau: alle Turtles stehen in einer Reihe entlang der Breite (X, nach
-- rechts), an der unteren linken Ecke vor dem Quader, gleiche Hoehe,
-- gleiche Tiefen-Startlinie, Blick hinein -- wie bei miner.lua, nur
-- nebeneinander. Der Quader wird entlang der Breite in disjunkte Streifen
-- aufgeteilt, jede Turtle graebt nur ihren eigenen Streifen -- dadurch ist
-- waehrend des Grabens keine Kollisionsgefahr und keine weitere
-- Koordination noetig. Braucht ein Wireless Modem.

local loadOk, minerlib = pcall(dofile, "minerlib.lua")
if not loadOk then
  printError("minerlib.lua fehlt oder ist fehlerhaft. Bitte install.lua erneut ausfuehren.")
  return
end

local PROTOCOL = "minercolony"
local JOIN_WAIT_SECONDS = 30
local WRAPUP_WAIT_SECONDS = 60

local modem = peripheral.find("modem")
if not modem then
  printError("Kein Funkmodem gefunden. Bitte ein Wireless Modem anbringen.")
  return
end
rednet.open(peripheral.getName(modem))

local function askInt(label, min, max)
  while true do
    io.write(label .. ": ")
    local value = tonumber(read())
    if value and value >= min and (not max or value <= max) and value == math.floor(value) then
      return value
    end
    print(string.format("Bitte eine ganze Zahl zwischen %d und %s eingeben.", min, max and tostring(max) or "beliebig"))
  end
end

print("Miner-Colony: Gesamt-Abmessungen des Quaders eingeben.")
local sizeY = askInt("Hoehe (nach oben)", 1)
local totalX = askInt("Breite (nach rechts, gesamt)", 1)
local sizeZ = askInt("Tiefe (nach vorne)", 1)
local turtleCount = askInt("Anzahl Turtles insgesamt (inkl. dieser)", 1, 5)

io.write("Steht hinter JEDEM Startpunkt eine eigene Kiste/ein Inventar zum Entladen? (j/n): ")
local chestAnswer = read()
local hasChest = chestAnswer ~= nil and chestAnswer:lower():sub(1, 1) == "j"

-- Streifenbreiten berechnen: so gleich wie moeglich, Rest auf die ersten
-- Streifen verteilt (Streifen unterscheiden sich hoechstens um 1 Block).
local baseWidth = math.floor(totalX / turtleCount)
local remainder = totalX - baseWidth * turtleCount
local laneWidths = {}
local offset = 0
print("Platzierung (Turtle 1 = diese Turtle, alle in einer Reihe entlang der Breite):")
for i = 1, turtleCount do
  local width = baseWidth + (i <= remainder and 1 or 0)
  laneWidths[i] = width
  print(string.format("  Turtle %d: Streifenbreite %d, Offset %d (Bloecke rechts von Turtle 1)", i, width, offset))
  offset = offset + width
end

if turtleCount == 1 then
  print("Nur 1 Turtle angegeben - graebt den kompletten Quader alleine (wie miner.lua).")
end

local myId = os.getComputerID()
local joined = {}
local joinedIds = {}

if turtleCount > 1 then
  print(string.format(
    "Warte bis zu %ds auf %d weitere Turtle(s) (miner_worker.lua dort starten)...",
    JOIN_WAIT_SECONDS, turtleCount - 1))
  local deadline = os.clock() + JOIN_WAIT_SECONDS
  while #joinedIds < turtleCount - 1 and os.clock() < deadline do
    local senderId, message = rednet.receive(PROTOCOL, 1)
    if message and message.type == "join" and not joined[senderId] then
      joined[senderId] = true
      table.insert(joinedIds, senderId)
      print(string.format("Turtle %d beigetreten (%d/%d).", senderId, #joinedIds, turtleCount - 1))
    end
  end

  if #joinedIds < turtleCount - 1 then
    io.write(string.format(
      "Nur %d von %d weiteren Turtles beigetreten. Trotzdem mit %d Turtle(s) starten? (j/n): ",
      #joinedIds, turtleCount - 1, #joinedIds + 1))
    local proceedAnswer = read()
    if not (proceedAnswer and proceedAnswer:lower():sub(1, 1) == "j") then
      print("Abgebrochen.")
      return
    end
    turtleCount = #joinedIds + 1
  end
end

-- Auftraege an die beigetretenen Worker verteilen (Lane 1 = diese Turtle).
for i, workerId in ipairs(joinedIds) do
  local laneIndex = i + 1
  rednet.send(workerId, {
    type = "job",
    targetId = workerId,
    controllerId = myId,
    laneIndex = laneIndex,
    sizeY = sizeY,
    sizeX = laneWidths[laneIndex],
    sizeZ = sizeZ,
    hasChest = hasChest,
  }, PROTOCOL)
end

print("Starte gemeinsamen Abbau ...")

local laneStatus = {}

local function handleStatus(senderId, message)
  if message and message.type == "status" then
    local event = message.event or {}
    laneStatus[message.laneIndex] = event
    print(string.format("[Turtle %d, Streifen %d] %s", message.id, message.laneIndex, tostring(event.type)))
  end
end

-- Status-Events der anderen Turtles protokollieren, waehrend diese Turtle
-- selbst ihren eigenen Streifen graebt (kooperative Nebenlaeufigkeit).
local function listenForStatus()
  while true do
    handleStatus(rednet.receive(PROTOCOL))
  end
end

local function digOwnLane()
  local ok, info = minerlib.run(sizeY, laneWidths[1], sizeZ, { hasChest = hasChest })
  laneStatus[1] = { type = "done", aborted = not ok, reason = info and info.reason }
end

parallel.waitForAny(digOwnLane, listenForStatus)

local function allDone()
  for lane = 1, turtleCount do
    if not laneStatus[lane] or laneStatus[lane].type ~= "done" then
      return false
    end
  end
  return true
end

if not allDone() then
  print("Warte auf Abschlussmeldungen der uebrigen Turtles ...")
  local wrapupDeadline = os.clock() + WRAPUP_WAIT_SECONDS
  while not allDone() and os.clock() < wrapupDeadline do
    handleStatus(rednet.receive(PROTOCOL, 1))
  end
end

print("Zusammenfassung:")
for lane = 1, turtleCount do
  local status = laneStatus[lane]
  if not status then
    print(string.format("  Streifen %d: keine Rueckmeldung erhalten.", lane))
  elseif status.aborted then
    print(string.format("  Streifen %d: abgebrochen (%s).", lane, tostring(status.reason)))
  else
    print(string.format("  Streifen %d: fertig.", lane))
  end
end
