-- roundrobin.lua
-- Verteilt dauerhaft Items zwischen den in network.cfg getaggten Eingaengen und
-- Ausgaengen. Die Zusammensetzung (welche Eingaenge/Ausgaenge, Item-Filter,
-- Batchgroesse, Zyklus-Intervall) steht in Gruppen, die roundrobin_config.lua
-- in roundrobin.cfg ablegt.
--
-- Jede Gruppe rotiert ueber ALLE Eingang-Ausgang-Kombinationen ihrer
-- Teilmenge (nicht nur ein festes Paar). Sind mehrere Gruppen konfiguriert,
-- laufen sie gleichzeitig (parallel.waitForAll) statt nacheinander.
--
-- network.cfg und roundrobin.cfg werden JEDEN Zyklus neu eingelesen: neue
-- Peripherals (network.lua) oder geaenderte Gruppen (roundrobin_config.lua)
-- wirken damit im naechsten Zyklus, ohne diesen Lauf neu zu starten. Wird eine
-- Gruppe zwischenzeitlich geloescht, pausiert nur ihr Zweig (Fehlermeldung,
-- kein Absturz der anderen Gruppen).
--
-- Laeuft auf einem NORMALEN COMPUTER, wie crafter.lua/mechanism.lua/network.lua.
--
-- Aufruf:
--   roundrobin.lua      -- Abbruch mit Strg+T

local loadOk, uilib = pcall(dofile, "uilib.lua")
if not loadOk then
  printError("uilib.lua fehlt oder ist fehlerhaft. Bitte install.lua erneut ausfuehren.")
  return
end

local RR_CONFIG_PATH = "roundrobin.cfg"
local DEFAULT_INTERVAL = 2

local function loadGroups(path)
  if not fs.exists(path) then
    return nil, string.format("'%s' nicht gefunden. Bitte zuerst roundrobin_config.lua ausfuehren.", path)
  end
  local file = fs.open(path, "r")
  local content = file.readAll()
  file.close()
  local ok, data = pcall(textutils.unserialize, content)
  if not ok or type(data) ~= "table" or type(data.groups) ~= "table" then
    return nil, string.format("'%s' ist beschaedigt. Bitte roundrobin_config.lua erneut ausfuehren.", path)
  end
  return data.groups
end

-- Erststart-Pruefung, damit offensichtliche Konfigurationsfehler sofort
-- auffallen statt erst nach einem stillen ersten Zyklus.
local startConfig, startErr = uilib.loadNetworkConfig()
if not startConfig then
  printError(startErr)
  return
end

local startGroups, startGroupsErr = loadGroups(RR_CONFIG_PATH)
if not startGroups then
  printError(startGroupsErr)
  return
end

if #startGroups == 0 then
  printError("roundrobin.cfg enthaelt keine Gruppen. Bitte roundrobin_config.lua ausfuehren.")
  return
end

-- Ein Inventar wird nur akzeptiert, wenn es wirklich list/pushItems anbietet --
-- gleiches Duck-Typing wie in mechanism.lua, damit ein Storage-Mod-Block ohne
-- IItemHandler nicht mit einer kryptischen Fehlermeldung mittendrin abbricht.
local function tryInventory(name)
  if not peripheral.isPresent(name) then
    return nil
  end
  local inv = peripheral.wrap(name)
  if inv and inv.list and inv.pushItems then
    return inv
  end
  return nil
end

-- Loest die aktive Namensliste einer Gruppenseite (Eingang/Ausgang) auf: bei
-- allFlag=true alle aktuellen Namen aus network.cfg, sonst nur die
-- konfigurierten Namen, die dort GERADE JETZT auch wirklich mit der
-- passenden Rolle stehen -- so wirkt eine Rollenaenderung in network.lua
-- sofort, auch fuer Gruppen mit fester Teilmenge.
local function resolveNames(configured, allFlag, currentNames)
  if allFlag then
    return currentNames
  end
  local currentSet = {}
  for _, n in ipairs(currentNames) do
    currentSet[n] = true
  end
  local result = {}
  for _, n in ipairs(configured or {}) do
    if currentSet[n] then
      table.insert(result, n)
    end
  end
  return result
end

-- Dreht eine Liste um `offset` Positionen weiter (mit Umlauf). Sorgt dafuer,
-- dass nicht bei jedem Zyklus derselbe Eingang/Ausgang zuerst bedient wird --
-- klassische Round-Robin-Fairness.
local function rotate(list, offset)
  local n = #list
  if n == 0 then
    return list
  end
  offset = offset % n
  if offset == 0 then
    return list
  end
  local rotated = {}
  for i = 1, n do
    rotated[i] = list[((i - 1 + offset) % n) + 1]
  end
  return rotated
end

local function passesFilter(group, itemName)
  if group.filterMode == "whitelist" then
    return group.items[itemName] == true
  elseif group.filterMode == "blacklist" then
    return group.items[itemName] ~= true
  end
  return true
end

-- Summiert die Menge aller Items in `src`, die den Gruppen-Filter bestehen --
-- Grundlage fuer die Mindestmengen-Option (minInputEnabled/minInputAmount):
-- nur was ohnehin bewegt werden duerfte, zaehlt auch fuer den Schwellwert.
local function filteredCount(group, src)
  local total = 0
  for _, item in pairs(src.list()) do
    if passesFilter(group, item.name) then
      total = total + item.count
    end
  end
  return total
end

-- Schiebt bis zu `limit` Items von `src` nach `dstName`, deren Item-ID den
-- Gruppen-Filter besteht. Rueckgabe: tatsaechlich bewegte Menge -- der
-- Rueckgabewert von pushItems ist die einzige verlaessliche Quelle dafuer,
-- ein Slot kann trotz freiem Zielplatz weniger annehmen als angefragt.
local function pushFiltered(group, src, dstName, limit)
  local moved = 0
  for slot, item in pairs(src.list()) do
    if moved >= limit then
      break
    end
    if passesFilter(group, item.name) then
      local want = math.min(limit - moved, item.count)
      local got = src.pushItems(dstName, slot, want) or 0
      moved = moved + got
      if got == 0 then
        -- Ziel nimmt gerade nichts mehr an (voll?) -- weitere Slots fuer
        -- dasselbe Ziel bringen dann auch nichts.
        break
      end
    end
  end
  return moved
end

-- Ein kompletter Zyklus einer Gruppe: Konfiguration neu lesen, aktive
-- Eingaenge/Ausgaenge bestimmen, jede Kombination bis zur Batchgroesse
-- bedienen. Rueckgabe: Intervall bis zum naechsten Zyklus.
local function runCycle(name, offset)
  local netConfig, inputNames, outputNames = uilib.loadNetworkConfig()
  if not netConfig then
    printError(string.format("[%s] %s", name, inputNames))
    return DEFAULT_INTERVAL
  end

  local rrGroups, rrErr = loadGroups(RR_CONFIG_PATH)
  if not rrGroups then
    printError(string.format("[%s] %s", name, rrErr))
    return DEFAULT_INTERVAL
  end

  local group = nil
  for _, g in ipairs(rrGroups) do
    if g.name == name then
      group = g
      break
    end
  end

  if not group then
    printError(string.format("[%s] Gruppe wurde aus roundrobin.cfg entfernt -- Lauf pausiert.", name))
    return DEFAULT_INTERVAL
  end

  local activeInputs = rotate(resolveNames(group.inputs, group.allInputs, inputNames), offset)
  local activeOutputs = rotate(resolveNames(group.outputs, group.allOutputs, outputNames), offset)

  if #activeInputs == 0 or #activeOutputs == 0 then
    print(string.format("[%s] keine Eingaenge/Ausgaenge aktiv -- warte.", name))
    return group.intervalSeconds or DEFAULT_INTERVAL
  end

  local validOutputs = {}
  for _, outName in ipairs(activeOutputs) do
    if tryInventory(outName) then
      table.insert(validOutputs, outName)
    end
  end

  local totalMoved = 0
  for _, inName in ipairs(activeInputs) do
    local src = tryInventory(inName)
    if src then
      -- Mindestmengen-Option: fehlt sie (alte Gruppen), bleibt die Bedingung
      -- falsy und der Eingang wird wie bisher immer bedient.
      local meetsMinimum = true
      if group.minInputEnabled and group.minInputAmount then
        meetsMinimum = filteredCount(group, src) >= group.minInputAmount
      end
      if meetsMinimum then
        for _, outName in ipairs(validOutputs) do
          totalMoved = totalMoved + pushFiltered(group, src, outName, group.batchSize)
        end
      end
    end
  end

  if totalMoved > 0 then
    print(string.format("[%s] Zyklus: %d Item(s) bewegt.", name, totalMoved))
  end

  return group.intervalSeconds or DEFAULT_INTERVAL
end

local function runGroup(initialGroup)
  local name = initialGroup.name
  local offset = 0
  while true do
    local interval = runCycle(name, offset)
    offset = offset + 1
    os.sleep(interval)
  end
end

print("=== Round-Robin ===")
local groupNames = {}
for _, g in ipairs(startGroups) do
  table.insert(groupNames, g.name)
end
print(string.format("%d Gruppe(n) aktiv: %s", #startGroups, table.concat(groupNames, ", ")))
print("Abbruch mit Strg+T.")

local groupRunners = {}
for _, group in ipairs(startGroups) do
  table.insert(groupRunners, function() runGroup(group) end)
end

local ok, err = pcall(parallel.waitForAll, table.unpack(groupRunners))

print("--- Beendet ---")
if not ok then
  printError("Abbruch: " .. tostring(err))
end
