-- Beispiel-Skript: einfacher Turtle-Miner
-- Graebt geradeaus und sammelt Bloecke ein

local function digAndMove()
  while turtle.detect() do
    turtle.dig()
    sleep(0.4)
  end
  turtle.forward()
end

local steps = tonumber(arg and arg[1]) or 10
for i = 1, steps do
  digAndMove()
end

print("Fertig: " .. steps .. " Bloecke vorangegraben.")
