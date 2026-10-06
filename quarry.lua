-- ============================================================================
-- CC: Tweaked Mining Turtle - Quarry Engine (v1.0.0-alpha)
-- ============================================================================
-- Features:
-- - 16x16 Quarry Mining with 3-block vertical slicing
-- - State persistence & automatic crash/chunk-unload recovery
-- - Standard turtle compatible monochrome TUI (39x13 display)
-- - Automated level-corner alcove storage with chest reuse & dig protection
-- - Intelligent fuel tracking with supply halt prompts
-- - Bedrock collision handling
-- ============================================================================

local STATE_FILE = "quarry_state.txt"
local WIDTH, LENGTH = 16, 16
local NORTH, EAST, SOUTH, WEST = 0, 1, 2, 3
local DIR_NAMES = { [0] = "N", [1] = "E", [2] = "S", [3] = "W" }

-- State Vector
local state = {
    x = 1, y = 1, z = 0,
    dir = SOUTH,
    status = "INIT",
    isDone = false,
    logs = {"System Init..."}
}

-- Target/Home Markers
local HOME = { x = 1, y = 1, z = 0, dir = SOUTH }

-- Item Identity Wrappers
local CHEST_NAMES = {
    ["minecraft:chest"] = true,
    ["minecraft:trapped_chest"] = true,
    ["minecraft:barrel"] = true
}

-- ----------------------------------------------------------------------------
-- State Management (Optimized Disk I/O)
-- ----------------------------------------------------------------------------
local function saveState()
    local f = fs.open(STATE_FILE, "w")
    if f then
        f.writeLine(textutils.serialize(state))
        f.close()
    end
end

local function loadState()
    if fs.exists(STATE_FILE) then
        local f = fs.open(STATE_FILE, "r")
        if f then
            local data = f.readAll()
            f.close()
            local loaded = textutils.unserialize(data)
            if type(loaded) == "table" then
                state = loaded
                return true
            end
        end
    end
    return false
end

-- ----------------------------------------------------------------------------
-- UI / TUI Engine (39x13 Monochromatic Layout)
-- ----------------------------------------------------------------------------
local function addLog(msg)
    table.insert(state.logs, 1, msg)
    if #state.logs > 3 then table.remove(state.logs, 4) end
    saveState()
end

local function drawTUI()
    term.clear()
    term.setCursorPos(1, 1)
    print("+-------------------------------------+")
    print("| QUARRY TURTLE v1.0-alpha            |")
    print("+-------------------------------------+")
    term.setCursorPos(1, 4)
    print(string.format("| Pos: X:%-2d Y:%-2d Z:%-3d | Dir: %s    |", state.x, state.y, state.z, DIR_NAMES[state.dir]))
    print(string.format("| Fuel: %-6d        | Slot1: Fuel |", turtle.getFuelLevel()))
    print(string.format("| Status: %-19s |", string.sub(state.status, 1, 19)))
    print("+-------------------------------------+")
    print("| LOGS:                               |")
    for i = 1, 3 do
        local l = state.logs[i] or ""
        print(string.format("| %-35s |", string.sub(l, 1, 35)))
    end
    print("+-------------------------------------+")
end

local function setStatus(status)
    state.status = status
    drawTUI()
    saveState()
end

-- ----------------------------------------------------------------------------
-- Navigation & Spatial Helpers
-- ----------------------------------------------------------------------------
local function turnTo(targetDir)
    while state.dir ~= targetDir do
        local diff = (targetDir - state.dir) % 4
        if diff == 3 then
            turtle.turnLeft()
            state.dir = (state.dir - 1) % 4
        else
            turtle.turnRight()
            state.dir = (state.dir + 1) % 4
        end
        drawTUI()
    end
    saveState()
end

local function isBedrock(inspectFunc)
    local success, data = inspectFunc()
    return success and data.name == "minecraft:bedrock"
end

local function isChest(inspectFunc)
    local success, data = inspectFunc()
    if not success then return false end
    if CHEST_NAMES[data.name] then return true end
    return data.name:find("chest") ~= nil or data.name:find("shulker") ~= nil
end

local function forceDig(digFunc, inspectFunc)
    if isBedrock(inspectFunc) then return false, "BEDROCK" end
    while inspectFunc() do
        if not digFunc() then
            sleep(0.5)
        end
    end
    return true
end

local function forward()
    if isBedrock(turtle.inspect) then
        return false, "BEDROCK"
    end
    while not turtle.forward() do
        if isChest(turtle.inspect) then
            -- Avoid destroying chests during travel
            return false, "CHEST_OBSTACLE"
        end
        turtle.dig()
        sleep(0.2)
    end
    
    if state.dir == NORTH then state.y = state.y - 1
    elseif state.dir == EAST then state.x = state.x + 1
    elseif state.dir == SOUTH then state.y = state.y + 1
    elseif state.dir == WEST then state.x = state.x - 1
    end
    
    drawTUI()
    saveState()
    return true
end

local function up()
    if isBedrock(turtle.inspectUp) then return false, "BEDROCK" end
    while not turtle.up() do
        if isChest(turtle.inspectUp) then return false, "CHEST_OBSTACLE" end
        turtle.digUp()
        sleep(0.2)
    end
    state.z = state.z + 1
    drawTUI()
    saveState()
    return true
end

local function down()
    if isBedrock(turtle.inspectDown) then return false, "BEDROCK" end
    while not turtle.down() do
        if isChest(turtle.inspectDown) then return false, "CHEST_OBSTACLE" end
        turtle.digDown()
        sleep(0.2)
    end
    state.z = state.z - 1
    drawTUI()
    saveState()
    return true
end

local function goTo(tx, ty, tz)
    -- Vertical clearance path optimization
    while state.z < tz do if not up() then break end end
    
    -- X navigation
    if state.x < tx then turnTo(EAST) while state.x < tx do forward() end
    elseif state.x > tx then turnTo(WEST) while state.x > tx do forward() end end
    
    -- Y navigation
    if state.y < ty then turnTo(SOUTH) while state.y < ty do forward() end
    elseif state.y > ty then turnTo(NORTH) while state.y > ty do forward() end end
    
    -- Descent
    while state.z > tz do if not down() then break end end
end

-- ----------------------------------------------------------------------------
-- Inventory & Refueling Systems
-- ----------------------------------------------------------------------------
local function calculateFuelNeeded(tx, ty, tz)
    local dist = math.abs(state.x - tx) + math.abs(state.y - ty) + math.abs(state.z - tz)
    return dist + 50 -- Safety margin
end

local function haltForFuel(needed)
    setStatus("HALTED: NEED FUEL")
    addLog("Fuel depleted! Min: " .. needed)
    while turtle.getFuelLevel() < needed do
        turtle.select(1)
        turtle.refuel()
        sleep(2)
    end
    setStatus("RESUMING")
    addLog("Fuel replenished.")
end

local function haltForChests()
    setStatus("HALTED: NEED CHESTS")
    addLog("Insert chests in Slot 2!")
    while true do
        turtle.select(2)
        local detail = turtle.getItemDetail(2)
        if detail and detail.count > 0 then
            break
        end
        sleep(2)
    end
    setStatus("RESUMING")
    addLog("Chests acquired.")
end

local function checkFuel(tx, ty, tz)
    local needed = calculateFuelNeeded(tx, ty, tz)
    if turtle.getFuelLevel() < needed then
        turtle.select(1)
        turtle.refuel()
        if turtle.getFuelLevel() < needed then
            local cx, cy, cz, cdir = state.x, state.y, state.z, state.dir
            goTo(HOME.x, HOME.y, HOME.z)
            turnTo(NORTH)
            
            -- Attempt refuel from home container
            turtle.suck()
            turtle.refuel()
            
            if turtle.getFuelLevel() < needed then
                haltForFuel(needed)
            end
            
            goTo(cx, cy, cz)
            turnTo(cdir)
        end
    end
end

local function isInventoryFull()
    for i = 1, 16 do
        if turtle.getItemCount(i) == 0 then return false end
    end
    return true
end

-- ----------------------------------------------------------------------------
-- Alcove Storage System (Level-Corner Offloading)
-- ----------------------------------------------------------------------------
local function depositInAlcove()
    local retX, retY, retZ, retDir = state.x, state.y, state.z, state.dir
    setStatus("STORING ITEMS")
    addLog("Navigating to corner storage...")
    
    -- Go to level corner (1, 1, Z)
    goTo(1, 1, state.z)
    
    -- Face North toward wall (1, 0, Z)
    turnTo(NORTH)
    
    -- Safe Alcove Digging Routine
    if not isChest(turtle.inspect) then
        turtle.dig()
    end
    
    -- Ceiling clearance for chest opening mechanism
    if not isChest(turtle.inspectUp) then
        turtle.digUp()
    end
    
    -- Verify presence of chest or place a new one
    if not isChest(turtle.inspect) then
        turtle.select(2)
        local detail = turtle.getItemDetail(2)
        if not detail or detail.count == 0 then
            haltForChests()
        end
        turtle.place()
        addLog("Placed alcove chest at Z=" .. state.z)
    else
        addLog("Reusing alcove chest at Z=" .. state.z)
    end
    
    -- Dump mined inventory items (Slots 3 to 16)
    for i = 3, 16 do
        turtle.select(i)
        if turtle.getItemCount(i) > 0 then
            turtle.drop()
        end
    end
    
    turtle.select(1)
    addLog("Items deposited.")
    
    -- Return to active slice position
    goTo(retX, retY, retZ)
    turnTo(retDir)
    setStatus("MINING")
end

-- ----------------------------------------------------------------------------
-- Primary Quarry Slicing Loop
-- ----------------------------------------------------------------------------
local function mineSlice()
    turtle.digUp()
    turtle.digDown()
end

local function runQuarry()
    setStatus("MINING")
    
    while not state.isDone do
        checkFuel(HOME.x, HOME.y, HOME.z)
        
        -- Descend 3 blocks per slice layer
        local targetZ = state.z - 3
        local hitBedrock = false
        
        while state.z > targetZ do
            if isBedrock(turtle.inspectDown) then
                hitBedrock = true
                break
            end
            if not down() then
                hitBedrock = true
                break
            end
        end
        
        if hitBedrock then
            addLog("Bedrock encountered at Z=" .. state.z)
            break
        end
        
        -- Snake pattern across 16x16 plane
        for x = 1, WIDTH do
            for y = 1, LENGTH - 1 do
                mineSlice()
                if isInventoryFull() then
                    depositInAlcove()
                end
                
                local ok, err = forward()
                if not ok and err == "BEDROCK" then
                    hitBedrock = true
                    break
                end
            end
            
            if hitBedrock then break end
            mineSlice()
            
            -- Column turnaround logic
            if x < WIDTH then
                if x % 2 == 1 then
                    turnTo(EAST)
                    forward()
                    turnTo(NORTH)
                else
                    turnTo(EAST)
                    forward()
                    turnTo(SOUTH)
                end
            end
        end
        
        -- Re-orient to start position of next lower layer plane
        goTo(1, 1, state.z)
        turnTo(SOUTH)
    end
    
    -- Task Completion Routine
    setStatus("RETURNING HOME")
    addLog("Quarry complete. Going home.")
    goTo(HOME.x, HOME.y, HOME.z)
    turnTo(HOME.dir)
    state.isDone = true
    setStatus("FINISHED")
    addLog("Job complete!")
end

-- ----------------------------------------------------------------------------
-- Program Entry Point
-- ----------------------------------------------------------------------------
local function main()
    if loadState() and not state.isDone then
        addLog("Resumed state at (" .. state.x .. "," .. state.y .. "," .. state.z .. ")")
    else
        state = {
            x = 1, y = 1, z = 0,
            dir = SOUTH,
            status = "STARTING",
            isDone = false,
            logs = {"Initialized release build"}
        }
        saveState()
    end

    drawTUI()
    runQuarry()
end

main()
