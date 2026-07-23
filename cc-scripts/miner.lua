-- Beispiel-Skript: einfacher Turtle-Miner
-- Graebt geradeaus und sammelt Bloecke ein

local function digAndMove()
  while turtle.detect() do
    if not turtle.dig() then
      return false, "Block konnte nicht abgebaut werden (z.B. Bedrock/geschuetzt)."
    end
    sleep(0.4)
  end

  if not turtle.forward() then
    return false, "Konnte nicht vorwaerts fahren (blockiert oder kein Treibstoff)."
  end

  return true
end

local args = { ... }
local steps = tonumber(args[1]) or 10

if turtle.getFuelLevel() ~= "unlimited" and turtle.getFuelLevel() < steps then
  printError("Zu wenig Treibstoff: " .. turtle.getFuelLevel() .. " (benoetigt: " .. steps .. ")")
  return
end

local moved = 0
for i = 1, steps do
  local ok, err = digAndMove()
  if not ok then
    printError(err)
    break
  end
  moved = moved + 1
end

print("Fertig: " .. moved .. "/" .. steps .. " Bloecke vorangegraben.")
