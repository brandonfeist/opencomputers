local computer = require('computer')
local component = require('component')
local robot = require('robot')
local sides = require('sides')
local serialization = require('serialization')

local STATES = {
  ERROR = "ERROR",
  CALIBRATING = "CALIBRATING",
  MINING = "MINING",
  REFUELING = "REFUELING",
  SOLAR = "SOLAR",
  CHARGING_HOME = "CHARGING_HOME",
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
local address = '1.0.0.1'
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
local workbenchArea = {1, 2, 3, 5, 6, 7, 9, 10, 11}
local quads = {{-7, -7}, {-7, 1}, {1, -7}, {1, 1}}
local X, Y, Z, D, border = 0, 0, 0, 0
local steps, turns = 0, 0
local TAGGED = {x = {}, y = {}, z= {}}
local energyRate, wearRate = 0, 0
local ignoreCheck = false
local hasSolar = false

-- Global methods --
local removePoint, checkEnergyLevel, sleep, report, chargeGenerator, chargeSolar, checkLocalBlocksAndMine, check, step, turn, smartTurn, go, scan, sort, goHome, inventoryCheck, calibrateEnergyUse, calibrateWearRate, calibrateDirection, calibration, main

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
removePoint = function(point)
  table.remove(TAGGED.x, point)
  table.remove(TAGGED.y, point)
  table.remove(TAGGED.z, point)
end

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
    modem.broadcast(port, serialization.serialize(stateTable))
  end
  computer.beep()
  if stop then
    error(message, 0)
  end
end

chargeGenerator = function()
  report('Refueling solid fuel generators', STATES.REFUELING)
  for slot = 1, inventorySize do
    robot.select(slot)
    generator.insert()
  end
  report('Returing to work', STATES.MINING, false)
end

chargeSolar = function()
  while not geolyzer.isSunVisible() and step(sides.top, true) do end
  report('Re-charging in the sun', STATES.SOLAR, false)
  sort(true)
  while (checkEnergyLevel() < 0.98) and geolyzer.isSunVisible() do
    local time = os.date('*t')
    if time.hour >= 5 and time.hour < 19 then
      sleep(60)
    else
      break
    end
  end
  report('Returing to work', STATES.MINING, false)
end

checkLocalBlocksAndMine = function()
  if #TAGGED.x ~= 0 then
    for i = 1, #TAGGED.x do
      if TAGGED.y[i] == Y and ((TAGGED.x[i] == X and ((TAGGED.z[i] == Z+1 and D == 0) or (TAGGED.z[i] == Z-1 and D == 2))) or (TAGGED.z[i] == Z and ((TAGGED.x[i] == X+1 and D == 3) or (TAGGED.x[i] == X-1 and D == 1)))) then
        robot.swing()
        removePoint(i)
      end

      if X == TAGGED.x[i] and (Y-1 <= TAGGED.y[i] and Y+1 >= TAGGED.y[i]) and Z == TAGGED.z[i] then
        if TAGGED.y[i] == Y+1 then
          robot.swingUp()
        elseif TAGGED.y[i] == Y-1 then
          robot.swingDown()
        end
        removePoint(i)
      end
    end
  end
end

check = function(forced)
  if not ignoreCheck and (steps % 32 == 0 or forced) then
    inventoryCheck()
    local distanceDelta = math.abs(X) + math.abs(Y) + math.abs(Z) + 64
    if robot.durability() / wearRate < distanceDelta then
      report('Tool is worn', STATES.GO_HOME, false)
      ignoreCheck = true
      goHome(true)
    end

    if distanceDelta * energyRate > computer.energy() then
      report('Battery level is low', STATES.GO_HOME, false)
      ignoreCheck = true
      goHome(true)
    end

    if checkEnergyLevel() < 0.3 then -- Energy less than 30%
      local time = os.date('*t')
      if generator and generator.count() == 0 and not forced then
        chargeGenerator()
      elseif hasSolar and (time.hour > 4 and time.hour < 17) then
        chargeSolar()
      end
    end
  end

  checkLocalBlocksAndMine()
end

step = function(side, stepIgnoreCheck)
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

  if not stepIgnoreCheck then
    check()
  end

  return true
end

turn = function(clockwise)
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
smartTurn = function(cardinalSide)
  while D ~= cardinalSide do
    turn((cardinalSide - D) % 4 == 1)
  end
end

go = function(x, y, z)
  if border and y < border then
    y = border
  end

  while Y ~= y do
    if Y < y then
      step(sides.top)
    elseif Y > y then
      step(sides.bottom)
    end
  end

  if X < x then
    smartTurn(3)
  elseif X > x then
    smartTurn(1)
  end
  while X ~= x do
    step(sides.front)
  end

  if Z < z then
    smartTurn(0)
  elseif Z > z then
    smartTurn(2)
  end
  while Z ~= z do
    step(sides.front)
  end
end

scan = function(xx, zz)
  local raw, index = geolyzer.scan(xx, zz, -1, 8, 8, 1), 1
  for z = zz, zz + 7 do
    for x = xx, xx + 7 do
      if raw[index] >= minDensity and raw[index] <= maxDensity then
        table.insert(TAGGED.x, X + x)
        table.insert(TAGGED.y, Y - 1)
        table.insert(TAGGED.z, Z + z)
      elseif raw[index] < -0.31 then
        border = Y
      end
      index = index + 1
    end
  end
end

sort = function(forcePackItems)
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
    for itemName, itemAmnt in pairs(available) do
      if itemAmnt > 8 then
        for l = 1, math.ceil(itemAmnt / 576) do
          inventoryCheck()
          -- Cleaning work area --
          for i = 1, 9 do
            if robot.count(workbenchArea[i]) > 0 then
              robot.select(workbenchArea[i])
              -- brute force invenotry and ignore workbench slots
              for slot = 4, inventorySize do
                if slot == 4 or slot == 8 or slot > 11 then
                  robot.transferTo(slot)
                  if robot.count(slot) == 0 then
                    break
                  end
                end
              end
              -- If overload detected pack up from buffer
              if robot.count() > 0 then
                while robot.suckUp() do end
                return
              end
            end
          end
          -- Fragment search looping
          for slot = 4, inventorySize do
            local item = inventoryController.getStackInInternalSlot(slot)
            if item and (slot == 4 or slot == 8 or slot > 11) then
              -- If items match
              if itemName == item.name:gsub('%g+:', '') then
                robot.select(slot)
                for n = 1, 10 do
                  robot.transferTo(workbenchArea[n % 9 + 1], item.size / 9)
                end
                -- reset when filling the workbench
                if robot.count(1) == 64 then
                  break
                end
              end
            end
          end
          robot.select(inventorySize) -- select last slot
          crafting.craft()
          -- Consolidate same items into same slots
          for slotA = 1, inventorySize do
            local size = robot.count(slotA)
            if size > 0 and size < 64 then
              for slotB = slotA + 1, inventorySize do
                if robot.compareTo(slotB) then
                  robot.select(slotA)
                  robot.transferTo(slotB, 64 - robot.count(slotB))
                end
                if robot.count() == 0 then
                  break
                end
              end
            end
          end
        end
      end
    end
  end
  while robot.suckUp() do end
  inventoryCheck()
end

goHome = function(forceGoHome, interrupt)
  local x, y, z, d
  ignoreCheck = true
  local enderChest
  for slot = 1, inventorySize do
    local item = inventoryController.getStackInInternalSlot(slot)
    if item then
      if item.name == 'enderstorage:ender_storage' then
        enderChest = slot
        break
      end
    end
  end
  if enderChest and not forceGoHome then
    robot.swing()
    robot.select(enderChest)
    robot.place(sides.front)
  else
    x, y, z, d = X, Y, Z, D
    go(0, -2, 0)
    go(0, 0, 0)
  end
  report('Home safe', STATES.HOME, false)

  sort()
  local externalInvSize = nil
  while true do
    for side = 1, 4 do
      externalInvSize = inventoryController.getInventorySize(sides.front)
      if externalInvSize and externalInvSize > 26 then
        break
      end
      turn()
    end
    if not externalInvSize or externalInvSize < 26 then
      report('Container not found, or chest full', STATES.ERROR, true)
    else
      break
    end
  end
  for slot = 1, inventorySize do
    local item = inventoryController.getStackInInternalSlot(slot)
    if item then
      if not whiteList[item.name] then
        robot.select(slot)
        local dropSuccess, dropErrMsg = robot.drop()
        if not dropSuccess and dropErrMsg == 'inventory full' then
          report('Container is full, please empty', STATES.ERROR, true)
        end
      end
    end
  end

  if crafting then
    for slot = 1, externalInvSize do
      local item = inventoryController.getStackInSlot(sides.front, slot)
      if item then
        if itemsToKeep[item.name:gsub('%g+', '')] then
          inventoryController.suckFromSlot(sides.front, slot)
        end
      end
    end
    sort(true)
    for slot = 1, inventorySize do
      local item = inventoryController.getStackInInternalSlot(slot)
      if item then
        if not whiteList[item.name] then
          robot.select(slot)
          robot.drop()
        end
      end
    end
  end

  if generator and not forceGoHome then
    for slot = 1, externalInvSize do
      local item = inventoryController.getStackInSlot(sides.front, slot);
      if item then
        if item.name:sub(11, 15) == 'coal' then
          inventoryController.suckFromSlot(sides.front, slot)
          break
        end
      end
    end
  end

  if forceGoHome then
    if robot.durability() < 0.3 then
      robot.select(1)
      inventoryController.equip()
      local tool = inventoryController.getStackInInternalSlot(1)
      for slot = 1, externalInvSize do
        local item = inventoryController.getStackInSlot(sides.front, slot)
        if item then
          if item.name == tool.name and item.damage < tool.damage then
            robot.drop()
            inventoryController.suckFromSlot(sides.front, slot)
            break
          end
        end
      end
      inventoryController.equip()
    end
  end

  if enderChest and not forceGoHome then
    robot.swing() -- Picks up chest
  else
    while checkEnergyLevel() < 0.98 do
      report('Charging', STATES.CHARGING_HOME, false)
      sleep(30)
    end
  end
  ignoreCheck = nil
  if not interrupt then
    report('Returning to work', STATES.MINING, false)
    go(0, -2, 0)
    go(x, y, z)
    smartTurn(d)
  end
end

inventoryCheck = function()
  if ignoreCheck then
    return
  end
  local items = 0
  for slot = 1, inventorySize do
    if robot.count(slot) > 0 then
      items = items + 1
    end
  end
  if inventorySize - items < 10 or items / inventorySize > 0.9 then
    while robot.suckUp() do end
    report('Inventory full, going home', STATES.GO_HOME, false)
    goHome(true)
  end
end

calibrateEnergyUse = function()
  local recordedEnergy = computer.energy()
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

calibration = function()
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

main = function()
  border = nil
  while not border do
    step(sides.bottom)
    for q = 1, 4 do
      scan(table.unpack(quads[q]))
    end
    check(true)
  end
  while #TAGGED.x ~= 0 do
    local nDelta, cDelta, current = math.huge, math.huge
    for index = 1, #TAGGED.x do
      nDelta = math.abs(X - TAGGED.x[index]) + math.abs(Y - TAGGED.y[index]) + math.abs(Z - TAGGED.z[index]) - border + TAGGED.y[index]
      if (TAGGED.x[index] > X and D ~= 3) or
      (TAGGED.x[index] < X and D ~= 1) or
      (TAGGED.z[index] > Z and D ~= 0) or
      (TAGGED.z[index] < Z and D ~= 2) then
        nDelta = nDelta + 1
      end
      if nDelta < cDelta then
        cDelta, current = nDelta, index
      end
    end
    if TAGGED.x[current] == X and TAGGED.y[current] == Y and TAGGED.z[current] == Z then
      removePoint(current)
    else
      local yc = TAGGED.y[current]
      if yc-1 > Y then
        yc = yc-1
      elseif yc+1 < Y then
        yc = yc+1
      end
      go(TAGGED.x[current], yc, TAGGED.z[current])
    end
  end
  sort()
end

calibration()
local Tau = computer.uptime()
local chunkCoords = {0, 0, 0, [0] = 1}
for o = 1, 10 do
  for i = 1, 2 do
    for a = 1, o do
      main()
      report('Chunk #'..(chunkCoords[3] + 1)..' processed', STATES.MINING, false)
      chunkCoords[i], chunkCoords[3] = chunkCoords[i] + chunkCoords[0], chunkCoords[3] + 1
      if chunkCoords[3] == chunks then -- last chunk reached
        report('Max chunks mined', STATES.GO_HOME, false)
        goHome(true, true)
        report(computer.uptime() - Tau..'seconds\nsteps: '..steps..'\nturns: '..turns, STATES.MINING, false)
      else
        TAGGED = {x = {}, y = {}, z = {}}
        go(chunkCoords[1] * 16, -2, chunkCoords[2] * 16) -- go to next chunk
        go(X, 0, Z) -- go to scan start point
      end
    end
  end
  chunkCoords[0] = 0 - chunkCoords[0]
end
