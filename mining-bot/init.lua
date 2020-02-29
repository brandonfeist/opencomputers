local computer = require('computer')
local component = require('component')
local robot = require('robot')
local sides = require('sides')
local serialization = require('serialization')

local STATES = {
  ERROR = "ERROR",
  CALIBRATING = "CALIBRATING",
  MINING = "MINING",
  SOLAR = "SOLAR",
  GO_HOME = "GO_HOME",
  HOME = "HOME"
}

-- Takes an array and turns it into an associative array
local function arrToTable(table)
  for i = #table, 1, -1 do
    table[table[i]], table[i] = true, nil
  end
end

-- Configuration Variables --
local chunks = 3
local minDensity, maxDensity = 2.2, 40
local port = 80
local whiteList = {'enderstorage:ender_storage'}
local itemsToKeep = {'redstone', 'coal', 'dye', 'diamond', 'emerald'}
local garbage = {'cobblestone','granite','diorite','andesite','marble','limestone','dirt','gravel','sand','stained_hardened_clay','sandstone','stone','grass','end_stone','hardened_clay','mossy_cobblestone','planks','fence','torch','nether_brick','nether_brick_fence','nether_brick_stairs','netherrack','soul_sand'}
arrToTable(whiteList)
arrToTable(itemsToKeep)
arrToTable(garbage)

-- Tracking Variables --
local X, Y, Z, D, border = 0, 0, 0, 0
local steps, turns = 0, 0
local TAGGED = {x = {}, y = {}, z= {}}
local energyRate, wearRate = 0, 0
local energyLevel = 0
local hasSolar = false

-- Add a component through proxy
local function add_component(name)
  name = component.list(name)()
  if name then
    return component.proxy(name)
  end
end

-- Component Loading --
local inventoryController = add_component('inventory_controller')
local generator = add_component('generator')
local crafting = add_component('crafting')
local geolyzer = add_component('geolyzer')
local modem = add_component('modem')
local inventorySize = robot.inventorySize()

-- Functions --
local function removePoint(point)
  table.remove(TAGGED.x, point)
  table.remove(TAGGED.y, point)
  table.remove(TAGGED.z, point)
end

local function checkEnergyLevel()
  return computer.energy() / computer.maxEnergy()
end

local function sleep(timeout)
  local deadline = computer.uptime() + timeout
  repeat
    computer.pullSignal(timeout)
  until computer.uptime() >= deadline
end

local function report(message, state, stop)
  if stop then
    state = STATES.ERROR
  end

  if modem then
    local stateTable = {
      state = state,
      position = X..', '..Y..', '..Z..': Direct: '..D,
      message = message,
      energy = checkEnergyLevel(),
      timestamp = os.clock()
    }
    modem.send(address, port, serialization.serialize(stateTable))
  end
  computer.beep()
  if stop then
    error(message, 0)
  end
end

local function check()

end

local function chargeSolar()

end

local function go(x, y, z)

end

local function scan(xx, zz)

end

local function goHome()

end

local function sort(forcePackItems)
  -- Make room to drop trash
  robot.swingDown()
  robot.swingUp()

  -- Dump garabge items and track items to keep
  local numEmptySlots, available = 0, {}
  for slot = 1, inventorySize do
    local item = inventoryController.getStackInInternalSlot(slot)
    if item then
      local name = item.name:gsub('%g+:', '')
      if garbage[name] then
        robot.select(slot)
        robot.dropDown()
        numEmptySlots = numEmptySlots + 1
      elseif itemsToKeep[name] then
        if available[name] then -- check if this item has already been seen
          available[name] = available[name] + item.size
        else
          available[name] = item.size
        end
      end
    else
      numEmptySlots = numEmptySlots + 1
    end
  end

  -- Pack items into blocks
  if crafting and (numEmptySlots < 12 or forcePackItems) then
    -- Transfer excess items to the buffer if not enough room for workbench
    if numEmptySlots < 10 then
      numEmptySlots = 10 - numEmptySlots -- Num of slots to empty to get to 10 empty slots
      for slot = 1, inventorySize do
        local item = inventoryController.getStackInInternalSlot(slot)
        if item then
          if not whiteList[item.name] then
            local name = item.name:gsub('%g+:', '')
            if available[name] then
              available[name] = available[name] - item.size
            end

            robot.select(slot)
            robot.dropUp()
            numEmptySlots = numEmptySlots - 1
          end
        end
        if numEmptySlots == 0 then
          break
        end
      end
    end

    -- Crafting items to pack them
    
  end
end

-- Solar charge function

-- Go to specified coord

-- Scan function

-- Go home function

-- Loot sorting?

local function step(side, ignoreCheck)
  if side == sides.bottom then
    local swingSuccess, block = robot.swingDown()
    if not swingSuccess and block ~= 'air' and robot.detectDown() then
      return false
    else
      while robot.swingDown() do end
    end

    steps = steps + 1
    robot.down()
    Y = Y - 1
  elseif side == sides.top then
    local swingSuccess, block = robot.swingUp()
    if not swingSuccess and block ~= 'air' and robot.detectUp() then
      return false
    else
      while robot.swingUp() do end
    end
    steps = steps + 1

    steps = steps + 1
    robot.up()
    Y = Y + 1
  elseif side == sides.front then
    local swingSuccess, block = robot.swing()
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
    report('Invalid step side given', STATES.ERROR, true)
    return false
  end

  if not ignoreCheck then
    check()
  end

  return true
end

local function turn(clockwise)
  clockwise = clockwise or false
  if clockwise then
    robot.turnRight()
    D = (D + 1) % 4
  else
    robot.turnLeft()
    D = (D - 1) % 4
  end

  check()
end

-- Probably need a clear definition of what cardinal side is what
local function smartTurn(cardinalSide)
  while D ~= cardinalSide do
    turn((cardinalSide - D) % 4 == 1)
  end
end

local function calibrateEnergyUse()
  local recordedEnergy = computer.energy()
  step(sides.bottom)
  energyRate = math.ceil(recordedEnergy - computer.energy())
end

local function calibrateWearRate()
  local itemDurability = robot.durability()
  while itemDurability == robot.durability() do
    robot.place()
    robot.swing()
  end
  wearRate = itemDurability - robot.durability()
end

local function calibrateDirection()
  local cardinalPoints = {2, 1, 3, 0}
  D = nil
  for s = 1, #cardinalPoints do
    if robot.detect() or robot.place() then
      local A = geolyzer.scan(-1, -1, 0, 3, 3, 1)
      robot.swing()
      local B = geolyzer.scan(-1, -1, 0, 3, 3, 1)
      for n = 2, 8, 2 do
        if math.ceil(B[n]) - math.ceil(A[n]) < 0 then -- if the block disappeared
          D = cardinalPoints[n / 2]
          break
        end
      end
    else
      turn()
    end
  end
  if not D then
    report('Direction calibration error', STATES.ERROR, true)
  end
end

local function calibration()
  report('Calibrating...', STATES.CALIBRATING, false)

  -- Check for essential components --
  if not inventoryController then
    report('Inventory controller not detected', STATES.ERROR, true)
  elseif not geolyzer then
    report('Geolyzer not detected', STATES.ERROR, true)
  elseif not robot.detectDown() then
    report('Bottom solid block is not detected', STATES.ERROR, true)
  elseif robot.durability() == nil then
    report('There is no suitable tool in the manipulator', STATES.ERROR, true)
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

  report('Calibration completed', STATES.MINING, false)
end

local function main()

end

calibration()
local Tau = computer.uptime()
local pos = {0, 0, 0, [0] = 1} -- table for storing chunk coords

