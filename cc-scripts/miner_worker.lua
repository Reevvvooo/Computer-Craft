-- miner_worker.lua
-- Worker-Teil der Miner-Colony: meldet sich per Funk bei einer laufenden
-- miner_colony.lua an, bekommt einen Streifen des Quaders zugewiesen und
-- graebt ihn eigenstaendig aus (gleiche Grab-Engine wie miner.lua). Braucht
-- ein Wireless Modem und keine Benutzereingabe -- alles kommt vom
-- Koordinator (Groesse, Position, Kisten-Option).

local loadOk, minerlib = pcall(dofile, "minerlib.lua")
if not loadOk then
  printError("minerlib.lua fehlt oder ist fehlerhaft. Bitte install.lua erneut ausfuehren.")
  return
end

local PROTOCOL = "minercolony"
local JOIN_RETRY_SECONDS = 2
local JOIN_TIMEOUT_SECONDS = 30

local modem = peripheral.find("modem")
if not modem then
  printError("Kein Funkmodem gefunden. Bitte ein Wireless Modem anbringen.")
  return
end
rednet.open(peripheral.getName(modem))

print("Suche Miner-Colony (miner_colony.lua muss dort bereits laufen)...")

local myId = os.getComputerID()
local job
local deadline = os.clock() + JOIN_TIMEOUT_SECONDS

while not job do
  rednet.broadcast({ type = "join", id = myId }, PROTOCOL)
  local senderId, message = rednet.receive(PROTOCOL, JOIN_RETRY_SECONDS)
  if message and message.type == "job" and message.targetId == myId then
    job = message
  elseif os.clock() > deadline then
    printError("Keine Miner-Colony gefunden (Timeout). Abbruch.")
    return
  end
end

print(string.format("Auftrag erhalten: Streifen %d, %dx%dx%d.", job.laneIndex, job.sizeY, job.sizeX, job.sizeZ))

local controllerId = job.controllerId

local function onEvent(event)
  rednet.send(controllerId, { type = "status", id = myId, laneIndex = job.laneIndex, event = event }, PROTOCOL)
end

minerlib.run(job.sizeY, job.sizeX, job.sizeZ, { hasChest = job.hasChest, onEvent = onEvent })
