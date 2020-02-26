local computer = require('computer')
local component = require('component')
local robot = require('robot')
local sides = require('sides')
local serialization = require('serialization')

local states = {
  ["ERROR"] = "ERROR",
  ["CALIBRATING"] = "CALIBRATING",
  ["MINING"] = "MINING",
  ["SOLAR"] = "SOLAR",
  ["GO_HOME"] = "GO_HOME",
  ["HOME"] = "HOME"
}

local chunks = 3
local minDensity, maxDensity = 2.2, 40
local port = 80
local X, Y, Z, D, border = 0, 0, 0, 0
local steps, turns = 0, 0
local TAGGED = {x = {}, y = {}, z= {}}
local energyRate, wearRate = 0, 0

-- Takes an array and turns it into an associative array
local function arrToTable(table)
  for i = #table, 1, -1 do
    table[table[i]], table[i] = true, nil
  end
end

-- Add a component through proxy
local function add_component(name)
  name = component.list(name)()
  if name then
    return component.proxy(name)
  end
end

-- Component Loading --
local controller = add_component('inventory_controller')
local generator = add_component('generator')
local crafting = add_component('crafting')
local geolyzer = add_component('geolyzer')
local modem = add_component('modem')
local inventorySize = robot.inventorySize()
local energyLevel, hasSolar

-- Functions --
checkEnergyLevel = function()
  return computer.energy() / computer.maxEnergy()
end

sleep = function(timeout)
  local deadline = computer.uptime() + timeout
  repeat
    computer.pullSignal(timeout)
  until computer.uptime() >= deadline
end

report = function(message, state, stop)
  if stop do
    state = states["ERROR"]
  end

  if modem then
    stateTable = {
      ["state"]=state,
      ["position"]=X..', '..Y..', '..Z..': Direct: '..D
      ["message"]=message
      ["energy"]=checkEnergyLevel()
      ["timestamp"]=os.clock()
    }
    modem.send(address, port, serialization.serialize(stateTable))
  end
  computer.beep()
  if stop then
    error(message, 0)
  end
end

-- Solar charge function

-- Sleep function

-- Turn function

-- Go to specified coord

-- Scan function

-- Go home function

step = function(side, ignore)
  if side == sides.bottom do
    local result, obstacle = robot.swingDown()
    if not swingSuccess and block ~= 'air' and robot.detectDown() then
      return false
    else
      while robot.swingDown() do end
    end

    steps = steps + 1
    robot.down()
    Y = Y - 1
  elseif side == sides.top do
    local result, obstacle = robot.swingUp()
    if not swingSuccess and block ~= 'air' and robot.detectUp() then
      return false
    else
      while robot.swingUp() do end
    end
    steps = steps + 1

    steps = steps + 1
    robot.up()
    Y = Y + 1
  elseif side == sides.front do
    local result, obstacle = robot.swing()
    if not swingSuccess and block ~= 'air' and robot.detect() then
      return false
    else
      while robot.swing() do end
    end
    steps = steps + 1

    steps = steps + 1
    robot.forward()
    if D == 0 then
      Z = Z + 1
    elseif D == 1 then
      X = X - 1
    elseif D == 2 then
      Z = Z - 1
    else
      X = X + 1
    end
  else
    report('Invalid step side given', states["ERROR"], true)
    return false
  end

  if not ignore then
    checkStatus()
  end

  return true
end

calibrateEnergyUse = function()
  local recordedEnergy = commputer.energy()
  step(sides.bottom)
  energyRate = math.ceil(recordedEnergy - computer.energy())
end

calibrateWearRate = function()
  local itemDurability = robot.durability()
  while itemDurability == robot.durability() do
    robot.place()
    robot.swing()
  end
  wearRate = itemDurability - robot.durability()
end

calibrateDirection = function()
  local cardinalPoints = {2, 1, 3, 0}
  D = nil
  for s = 1, #sides do
    if robot.detect() or robot.place() do
      local A = geolyzer.scan(-1, -1, 0, 3, 3, 1)
      robot.swing()
      local B = geolyzer.scan(-1, -1, 0, 3, 3, 1)
      for n = 2, 8, 2 do
        if math.ceil(B[n]) - math.ceil(A[n]) < 0 then -- if the block disappeared
          D = sides[n / 2]
          break
        end
      end
    else
      turn()
    end
  end
  if not D then
    report('Direction calibration error', states["ERROR"], true)
  end
end

calibration = function()
  report('Calibrating...', states["CALIBRATING"], false)

  -- Check for essential components --
  if not controller then
    report('Inventory controller not detected', states["ERROR"], true)
  elseif not geolyzer then
    report('Geolyzer not detected', states["ERROR"], true)
  elseif not robot.detectDown() then
    report('Bottom solid block is not detected', states["ERROR"], true)
  elseif robot.durability() == nil then
    report('There is no suitable tool in the manipulator', states["ERROR"], true)
  end

  -- Check and set solar and modem --
  local computerList = computer.getDeviceInfo()
  for i, j in pairs(computerList) do
    if j.description == 'Solar panel' then
      hasSolar = true
      break
    end
  end
  if modem then
    modem.setStrength(400)
  end

  for slot = 1, inventorySize do -- Select an open slot
    if robot.count(slot) == 0 then
      robot.select(slot)
      break
    end
  end
  
  calibrateEnergyUse()
  calibrateWearRate()
  calibrateDirection()

  report('Calibration completed', states["MINING"], false)
end

main = function()

end

calibration()
calibration = nil
local Tau = computer.uptime()
local pos = {0, 0, 0, [0] = 1} -- table for storing chunk coords

