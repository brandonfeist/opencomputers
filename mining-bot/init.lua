local computer = require('computer')
local component = require('component')
local robot = require('robot')
local sides = require('sides')
local serialization = require('serialization')

local chunks = 3
local minDensity, maxDensity = 2.2, 40
local port = 80
local X, Y, Z, D, border = 0, 0, 0, 0
local steps, turns = 0, 0
local TAGGED = {x = {}, y = {}, z= {}}
local energyCons, wearRate = 0, 0

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
local energyLevel, hasSolar, state

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

report = function(message, stop)
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
    report('Invalid step side given', true)
    return false
  end

  if not ignore then
    checkStatus()
  end

  return true
end

calibration = function()
  -- Check for essential components --
  if not controller then
    report('Inventory controller not detected', true)
  elseif not geolyzer then
    report('Geolyzer not detected', true)
  elseif not robot.detectDown() then
    report('Bottom solid block is not detected', true)
  elseif robot.durability() == nil then
    report('There is no suitable tool in the manipulator', true)
  end

  local computerList = computer.getDeviceInfo()
  for i, j in pairs(computerList) do -- See if robot has solar panel
    if j.description == 'Solar panel' then
      hasSolar = true
      break
    end
  end
  if modem then
    modem.setStrenth(400)
  end
  for slot = 1, inventorySize do -- Select an open slot
    if robot.count(slot) == 0 then
      robot.select(slot)
      break
    end
  end
  local recordedEnergy = commputer.energy()
  step(sides.bottom)
  energyCons = math.ceil(recordedEnergy - computer.energy())

end

main = function()

end

calibration()
calibration = nil
local Tau = computer.uptime()
local pos = {0, 0, 0, [0] = 1} -- table for storing chunk coords

