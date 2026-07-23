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
local STATUS_PRINT_SECONDS = 10
-- Reines Sicherheitsnetz, falls nie eine Colony startet -- normalerweise
-- wartet der Worker beliebig lange, auch waehrend die Colony selbst noch
-- auf Nutzereingaben wartet. Manueller Abbruch weiterhin per Ctrl+T moeglich.
local SAFETY_TIMEOUT_SECONDS = 600

local modem = peripheral.find("modem")
if not modem then
  printError("Kein Funkmodem gefunden. Bitte ein Wireless Modem anbringen.")
  return
end
rednet.open(peripheral.getName(modem))

print("Suche Miner-Colony (miner_colony.lua muss dort bereits laufen)...")

local myId = os.getComputerID()
local job
local startClock = os.clock()
local lastStatusPrint = startClock
local lastBroadcast = -math.huge

-- WICHTIG: NICHT bei jeder empfangenen Nachricht neu broadcasten. Sobald
-- mehrere Worker gleichzeitig suchen, empfaengt jeder Worker die join-
-- Broadcasts der anderen; ein sofortiges Neu-Broadcasten wuerde daraus
-- einen Broadcast-Sturm machen, der die Event-Queue flutet und dabei die
-- job-Nachricht des Koordinators verwerfen kann. Deshalb: fester Sende-
-- Takt (JOIN_RETRY_SECONDS) und nur ein kurzer Empfangs-Timeout, damit wir
-- trotzdem zuegig auf den eintreffenden Job reagieren.
while not job do
  local now = os.clock()
  if now - lastBroadcast >= JOIN_RETRY_SECONDS then
    rednet.broadcast({ type = "join", id = myId }, PROTOCOL)
    lastBroadcast = now
  end

  local _, message = rednet.receive(PROTOCOL, 0.5)
  if message and message.type == "job" and message.targetId == myId then
    job = message
  end

  now = os.clock()
  if now - lastStatusPrint >= STATUS_PRINT_SECONDS then
    print("... suche weiter nach einer Miner-Colony")
    lastStatusPrint = now
  end
  if now - startClock > SAFETY_TIMEOUT_SECONDS then
    printError("Keine Miner-Colony gefunden (Timeout nach " .. SAFETY_TIMEOUT_SECONDS .. "s). Abbruch.")
    return
  end
end

print(string.format("Auftrag erhalten: Streifen %d, %dx%dx%d.", job.laneIndex, job.sizeY, job.sizeX, job.sizeZ))

local controllerId = job.controllerId

local function onEvent(event)
  rednet.send(controllerId, { type = "status", id = myId, laneIndex = job.laneIndex, event = event }, PROTOCOL)
end

minerlib.run(job.sizeY, job.sizeX, job.sizeZ, { hasChest = job.hasChest, onEvent = onEvent })
