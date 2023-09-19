local requestPipeDir = "LogisticsPipes:Request_3"
local storageChestDir = "diamond_0"
local inboundChestDir = "chest_1"
local inboundChestProcessDir = "UP"

local bundledRedstoneDir = "back"
local clockColour = colours.white
local inboundComparatorColour = colours.yellow

-- TODO switch to side based instead of colour based

local requestsFilePath = "autostock.cfg"

local statusOutput = peripheral.wrap("monitor_1")

-------------------------------------------------------

local requestPipe = peripheral.wrap(requestPipeDir)
local storageChest = peripheral.wrap(storageChestDir)
local inboundChest = peripheral.wrap(inboundChestDir)

function getExistingStockingRequests() 
    if not fs.exists(requestsFilePath) then return {} end 
    if fs.isDir(requestsFilePath) then return {} end 
    if fs.isReadOnly(requestsFilePath) then return {} end 

    requestsFile = fs.open(requestsFilePath, "r")
    local stockingRequests = textutils.unserialize(requestsFile.readAll())
    requestsFile.close()
    return stockingRequests
end

function saveStockingRequests(stockingRequests) 
    requestsFile = fs.open(requestsFilePath, "w")
    requestsFile.write(textutils.serialize(stockingRequests))
    requestsFile.close()
end

function getStoredItems() 
    local storedItems = {}

    local allStacks = {}
    allStacks = storageChest.getAllStacks()
    -- while (#allStacks == 0) do -- THIS WILL CRASH ON EMPTY CHEST
    --     os.sleep(1)
    --     allStacks = storageChest.getAllStacks()
    -- end

    for slot, stack in pairs(allStacks) do
        local basic = stack.basic()
        -- basic.dmg basic.qty basic.id
        local uniqueId = basic.id .. " " .. basic.dmg
        local stored = storedItems[uniqueId]
        if stored == nil then stored = 0 end
        storedItems[uniqueId] = stored + basic.qty 
    end

    return storedItems
end


function fullfillRequests(requests, storedItems, pendingRequests)
    if pendingRequests == nil then pendingRequests = {} end


    local builder = requestPipe.getLP().getItemIdentifierBuilder()
    
    for uniqueId, request in pairs(requests) do
        local pending = pendingRequests[uniqueId]
        if pending == nil then pending = 0 end
        
        
        
        local stored = storedItems[uniqueId]
        if stored == nil then stored = 0 end
        
        if stored + pending < request.amount then
            local missing = request.amount - (stored + pending)
            builder.setItemID(request.id)
            builder.setItemData(request.dmg)
            print("Requesting " .. missing .. " of " .. request.name)
            print("Stored: " .. stored .. " Pending: " .. pending .. " Requested for stock: ".. request.amount)
            local res = requestPipe.makeRequest(builder.build(), missing)
            if res == "DONE" then
                pendingRequests[uniqueId] = request.amount - stored
            else 
                write("Could not make request: ")
                print(res)
            end
        end
    end



    return pendingRequests
end

function processInboundItems(storedItems, pendingRequests)

    local allstacks = inboundChest.getAllStacks()
    for slot, stack in ipairs(allstacks) do
        local basic = stack.basic()
        -- basic.dmg basic.qty basic.id
        local uniqueId = basic.id .. " " .. basic.dmg

        local pending = pendingRequests[uniqueId]
        if pending ~= nil then
            pendingRequests[uniqueId] = math.max(0, pending - basic.qty)
            -- print("Accepting incoming " .. basic.name .. ", still expecting " .. pendingRequests[uniqueId] .. " more")
            inboundChest.pushItem(inboundChestProcessDir, slot, basic.qty)

            local stored = storedItems[uniqueId]
            if stored == nil then stored = 0 end

            storedItems[uniqueId] = stored + basic.qty
        end
    end

    return storedItems
end

function searchByName(targetName)
    targetName = string.lower(targetName)

    local matches = {}
    local nameCount = {}

    local available = requestPipe.getAvailableItems()
    for i, item in ipairs(available) do
        local val = item.getValue1()
        local name = val.getName()
        if string.find(string.lower(name), targetName, 1, true) ~= nil then
            matches[val.getIdName() .. " " .. val.getData()] = val
            nameCount[name] = (nameCount[name] or 0) + 1
        end
    end

    local craftable = requestPipe.getCraftableItems()
    for i, item in ipairs(craftable) do
        local name = item.getName()
        if string.find(string.lower(name), targetName, 1, true) ~= nil then
            if matches[item.getIdName() .. " " .. item.getData()] == nil then
                matches[item.getIdName() .. " " .. item.getData()] = item
                nameCount[name] = (nameCount[name] or 0) + 1
            end
        end
    end


    return matches, nameCount
end

function addStockingRequest(stockingRequests)
    term.clear()
    term.setCursorPos(1,1)
    print("Item to stock:")
    write("> ")
    os.sleep(0.1)
    local name = read()
    local matches, nameCount = searchByName(name)
    
    term.setTextColour(colours.lightGrey)

    local mapping = {}
    local i = 1
    for uniqueId, item in pairs(matches) do
        local name = item.getName()
        write(string.format("%2d | %s ", i, name))
        if nameCount[name] > 1 then
            term.setTextColour(colours.grey)
            write("("..uniqueId..")")
            term.setTextColour(colours.lightGrey)
        end
        print()

        mapping[i] = uniqueId
        i = i + 1
    end
    term.setTextColour(colours.white)


    print("Index of desired item:")
    write("> ")

    local index = tonumber(read())
    if index == nil then print("Not a number, cancelling") return end
    index = math.floor(index)
    if index < 1 or index > #mapping then print("Index outside valid range, cancelling") return end

    local thisUniqueId = mapping[index]

    write("Using unique id ")
    print(thisUniqueId)

    local item = matches[thisUniqueId]

    print("How many to keep stocked?")
    write("> ")

    local amount = tonumber(read())
    if amount == nil then print("Not a number, cancelling") return end
    amount = math.floor(amount)
    if amount < 1 then print("Cannot stock a 0 or negative amount, cancelling") return end
    
    local request = {}
    request.id = item.getIdName()
    request.name = item.getName()
    request.dmg = item.getData()
    request.amount = amount

    stockingRequests[thisUniqueId] = request

    saveStockingRequests(stockingRequests)
    print("Success")
end

function removeStockingRequest(stockingRequests)
    term.clear()
    term.setCursorPos(1,1)

    print("Stock to delete (empty for all results):")
    write("> ")
    os.sleep(0.1)
    local targetName = string.lower(read())

    local matches = {}
    local nameCount = {}

    for uniqueId, request in pairs(stockingRequests) do
        local name = request.name
        if string.find(string.lower(name), targetName, 1, true) ~= nil then
            matches[uniqueId] = request
            nameCount[name] = (nameCount[name] or 0) + 1
        end
    end
    term.setTextColour(colours.lightGrey)

    local mapping = {}
    local i = 1
    for uniqueId, item in pairs(matches) do
        local name = item.name
        write(string.format("%2d | %s ", i, name))
        if nameCount[name] > 1 then
            term.setTextColour(colours.grey)
            write("("..uniqueId..")")
            term.setTextColour(colours.lightGrey)
        end
        print()

        mapping[i] = uniqueId
        i = i + 1
    end
    term.setTextColour(colours.white)


    print("Index of request to remove:")
    write("> ")

    local index = tonumber(read())
    if index == nil then print("Not a number, cancelling") return end
    index = math.floor(index)
    if index < 1 or index > #mapping then print("Index outside valid range, cancelling") return end

    local thisUniqueId = mapping[index]

    stockingRequests[thisUniqueId] = nil

    saveStockingRequests(stockingRequests)
    print("Success")
end

function statusDisplay(display, stockingRequests, storedItems, pendingRequests)
    -- Ranges of [a, b) => b is not included in a range

    local sizeX, sizeY = display.getSize()
    local barWidth = sizeX / 2
    local nBarsAvailable = sizeY - 2

    display.setTextColour(colours.white)
    display.setBackgroundColour(colours.black)
    display.clear()

    local headerString = "-- Pending  Requests --"
    display.setCursorPos((sizeX - #headerString)/2 + 1, 1)
    display.write(headerString)

    local i = 1
    for uniqueId, request in pairs(stockingRequests) do
        local requested = request.amount
        local stored = storedItems[uniqueId]
        if stored == nil then stored = 0 end

        if stored < requested then
            local pending = pendingRequests[uniqueId]
            if pending == nil then pending = 0 end
            if stored + pending > requested then
                pending = requested-stored
            end


            
            local storedPortion = math.floor(stored / requested * barWidth)
            local pendingPortion = math.floor((stored+pending) / requested * barWidth) - storedPortion
            local emptyPortion = barWidth - storedPortion - pendingPortion

            display.setCursorPos(1, 1 + i)
            display.setBackgroundColour(colours.lime)

            for i=1,storedPortion do
                display.write("_")
            end

            display.setBackgroundColour(colours.lightGrey)
            for i=1,pendingPortion do
                display.write("_")
            end

            display.setBackgroundColour(colours.grey)
            for i=1, emptyPortion do
                display.write("_")
            end

            display.setBackgroundColour(colours.black)
            display.write(" ")
            display.write(request.name)

            -- display.setCursorPos(1, 1 + i)
            -- display.setBackgroundColour(colours.lime)
            -- display.write(string.rep("_", storedPortion))
            
            -- if pendingPortion - storedPortion > 0 then
            --     display.setBackgroundColour(colours.lightGrey)
            --     display.write(string.rep("_", pendingPortion - storedPortion))
            -- end

            -- if barWidth - pendingPortion > 0 then
            --     display.setBackgroundColour(colours.grey)
            --     display.write(string.rep("_", barWidth - pendingPortion))
            -- end

            -- display.setBackgroundColour(colours.black)
            -- display.write(" ")
            -- display.write(request.name)

            i = i + 1

            if i > nBarsAvailable then
                print("...")
                break
            end
        end
    end
end

function main()
    local stockingRequests = getExistingStockingRequests()
    -- local stockingRequests = {}
    -- local newRequest = {}
    -- newRequest["id"] = "minecraft:planks"
    -- newRequest["name"] = "Oak Wood Planks" 
    -- newRequest["dmg"] = 0
    -- newRequest["amount"] = 32
    -- stockingRequests[1] = newRequest 

    local storedItems = getStoredItems()
    local pendingRequests = {}
    fullfillRequests(stockingRequests, storedItems, pendingRequests)
    statusDisplay(statusOutput, stockingRequests, storedItems, pendingRequests)
    
    while true do
        local event, p1, p2, p3 = os.pullEvent()
        if event == 'redstone' then
            local bundledInput = redstone.getBundledInput(bundledRedstoneDir)

            local clockTriggered = colors.test(clockColour, bundledInput)
            local inboundTriggered = colors.test(inboundComparatorColour, bundledInput)

            -- comparator
            if colors.test(inboundComparatorColour, bundledInput) then
                storedItems = processInboundItems(storedItems, pendingRequests)
            end

            -- clock
            if clockTriggered then
                storedItems = getStoredItems()
                fullfillRequests(stockingRequests, storedItems, pendingRequests)
            end

            statusDisplay(statusOutput, stockingRequests, storedItems, pendingRequests)

            -- if clockTriggered then print("clock") end
            -- if inboundTriggered then
            --     print("inbound")
            -- end

        elseif event == "key" then
            local key = keys.getName(p1)
            if key == "n" then
                addStockingRequest(stockingRequests)
            elseif key == "d" then
                removeStockingRequest(stockingRequests)
            elseif key == "s" then
                storedItems = getStoredItems()
                fullfillRequests(stockingRequests, storedItems, pendingRequests)
                statusDisplay(statusOutput, stockingRequests, storedItems, pendingRequests)
            end            
        end
    end
end

main()
