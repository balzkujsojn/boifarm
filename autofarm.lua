-- Wait for game and local player to fully load
repeat task.wait() until game:IsLoaded()
local Players = game:GetService("Players")
repeat task.wait() until Players.LocalPlayer
local player = Players.LocalPlayer

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")

-- Configuration
local CONFIG = {
    FIRE_RATE = 0.05,
    TOOL_NAME = "Equinox Cannon",
    REMOTE_NAME = "RemoteFunction",
    TARGET_UPDATE_INTERVAL = 0.5,
    WORLD_UPDATE_INTERVAL = 2,
    HEALTH_CHECK_INTERVAL = 1,
    MAX_TARGET_DISTANCE = 300,
    SHIELD_COOLDOWN = 5,
    ARBITER_TARGET_POSITION = Vector3.new(2170, 14, 1554)
}

-- Priority enemies
local PRIORITY_ENEMIES = {
    ["The Arbiter"] = true,
    ["Gilgamesh, the Consumer of Reality"] = true,
    ["Controller Turret"] = true
}

-- Special target positions for specific enemies
local SPECIAL_TARGET_POSITIONS = {
    ["The Arbiter"] = CONFIG.ARBITER_TARGET_POSITION
}

-- Special target parts for specific enemies
local SPECIAL_TARGET_PARTS = {
    ["The Arbiter"] = "HumanoidRootPart"
}

-- Teleport position
local TELEPORT_POSITION = Vector3.new(-21, 103, -469)
local SPECIFIC_PLACE_ID = 96516249626799

-- State management
local State = {
    isRunning = true,
    specialMode = false,
    lastFireTime = 0,
    currentTarget = nil,
    chargeValue = 100,
    gilgameshHasSpawned = false,
    gilgameshCompleted = false,
    playerAlive = true,
    skipSaid = false,
    skipAllSaid = false,
    shieldUsed = false,
    lastShieldUse = 0,
    teleported = false,
    connectionPool = {},
    lastHealthCheck = 0,
    lastTargetUpdate = 0,
    lastWorldUpdate = 0,
    arbiterSpawned = false,
    lastArbiterCheck = 0
}

-- Object pools for memory efficiency
local ObjectPools = {
    enemyCache = {},
    workspaceCache = {}
}

-- Get TextChatService channel safely
local function getChatChannel()
    if TextChatService.ChatVersion == Enum.ChatVersion.LegacyChatService then
        return nil
    end
    
    local channel = TextChatService:FindFirstChild("TextChannels")
    if channel then
        channel = channel:FindFirstChild("RBXGeneral")
        if channel and channel:IsA("TextChannel") then
            return channel
        end
    end
    
    for _, child in pairs(TextChatService:GetChildren()) do
        if child:IsA("TextChannel") then
            return child
        end
    end
    
    return nil
end

-- Optimized chat message function
local chatChannel = getChatChannel()
local function chatMessage(str)
    if type(str) ~= "string" then str = tostring(str) end
    
    if TextChatService.ChatVersion == Enum.ChatVersion.LegacyChatService then
        local events = ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents")
        if events then
            local remote = events:FindFirstChild("SayMessageRequest")
            if remote then
                task.spawn(function()
                    pcall(remote.FireServer, remote, str, "All")
                end)
            end
        end
    elseif chatChannel then
        task.spawn(function()
            pcall(chatChannel.SendAsync, chatChannel, str)
        end)
    end
end

-- Check if The Arbiter has spawned
local function checkArbiterSpawned()
    local now = tick()
    if now - State.lastArbiterCheck < 1 then
        return State.arbiterSpawned
    end
    
    State.lastArbiterCheck = now
    local arbiter = workspace:FindFirstChild("The Arbiter")
    State.arbiterSpawned = arbiter ~= nil
    
    return State.arbiterSpawned
end

-- Get target position for specific enemy
local function getTargetPositionForEnemy(enemyName, enemyModel)
    -- Check if this enemy has a fixed target position
    if SPECIAL_TARGET_POSITIONS[enemyName] then
        return SPECIAL_TARGET_POSITIONS[enemyName]
    end
    
    -- For other enemies, get their actual part position
    local specialPartName = SPECIAL_TARGET_PARTS[enemyName]
    if specialPartName then
        local specialPart = enemyModel:FindFirstChild(specialPartName)
        if specialPart then
            return specialPart.Position
        end
    end
    
    -- Default fallback
    return enemyModel:FindFirstChild("HumanoidRootPart") or 
           enemyModel:FindFirstChild("Torso") or 
           enemyModel:FindFirstChild("UpperTorso") or
           enemyModel:FindFirstChild("Head") or
           enemyModel:FindFirstChild("Chest")
end

-- Get target part for validation
local function getTargetPartForValidation(model)
    local enemyName = model.Name
    
    -- Check if this enemy has a special target part
    if SPECIAL_TARGET_PARTS[enemyName] then
        local specialPart = model:FindFirstChild(SPECIAL_TARGET_PARTS[enemyName])
        if specialPart then
            return specialPart
        end
    end
    
    -- Default part search order for regular enemies
    return model:FindFirstChild("HumanoidRootPart") or 
           model:FindFirstChild("Torso") or 
           model:FindFirstChild("UpperTorso") or
           model:FindFirstChild("Head") or
           model:FindFirstChild("Chest")
end

-- Optimized object cleanup
local function cleanConnectionPool()
    for i = #State.connectionPool, 1, -1 do
        local connection = State.connectionPool[i]
        if not connection.Connected then
            table.remove(State.connectionPool, i)
        end
    end
end

-- Optimized workspace children cache
local function updateWorkspaceCache()
    local now = tick()
    if now - State.lastWorldUpdate > CONFIG.WORLD_UPDATE_INTERVAL then
        ObjectPools.workspaceCache = workspace:GetChildren()
        State.lastWorldUpdate = now
        return true
    end
    return false
end

-- Optimized enemy detection
local function findEnemies()
    if not State.playerAlive then return ObjectPools.enemyCache end
    
    updateWorkspaceCache()
    
    -- Clear cache
    for i = #ObjectPools.enemyCache, 1, -1 do
        ObjectPools.enemyCache[i] = nil
    end
    
    local priorityEnemies = {}
    local regularEnemies = {}
    
    for _, model in ipairs(ObjectPools.workspaceCache) do
        if not State.isRunning then break end
        
        if model:IsA("Model") and model.Parent == workspace then
            local enemyMain = model:FindFirstChild("EnemyMain")
            local humanoid = model:FindFirstChildOfClass("Humanoid")
            
            if enemyMain and humanoid and humanoid.Health > 0 then
                -- Get the correct target part for this enemy
                local targetPart = getTargetPartForValidation(model)
                if targetPart then
                    local enemyData = {
                        Model = model,
                        Humanoid = humanoid,
                        TargetPart = targetPart,
                        Position = targetPart.Position,
                        Name = model.Name,
                        IsPriority = PRIORITY_ENEMIES[model.Name] == true,
                        LastSeen = tick()
                    }
                    
                    if model.Name == "Gilgamesh, the Consumer of Reality" or "The Supreme Uber Bringer of Light and Space Time Annihilation" then
                        State.gilgameshHasSpawned = true
                    elseif model.Name == "The Arbiter" then
                        State.arbiterSpawned = true
                    end
                    
                    if enemyData.IsPriority then
                        table.insert(priorityEnemies, enemyData)
                    else
                        table.insert(regularEnemies, enemyData)
                    end
                end
            end
        end
    end
    
    if #priorityEnemies > 0 then
        ObjectPools.enemyCache = priorityEnemies
    else
        ObjectPools.enemyCache = regularEnemies
    end
    
    return ObjectPools.enemyCache
end

-- Function to select best target with priority
local function selectTarget()
    if not State.playerAlive then return nil end
    
    local enemies = findEnemies()
    
    if #enemies == 0 then
        return nil
    end
    
    if State.currentTarget then
        local targetModel = State.currentTarget.Model
        if targetModel and targetModel.Parent then
            local humanoid = targetModel:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.Health > 0 then
                if State.currentTarget.IsPriority then
                    return State.currentTarget
                end
                
                local hasPriority = false
                for _, enemy in ipairs(enemies) do
                    if enemy.IsPriority then
                        hasPriority = true
                        break
                    end
                end
                
                if not hasPriority then
                    return State.currentTarget
                end
            end
        end
    end
    
    local character = player.Character
    if not character then return enemies[1] end
    
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then return enemies[1] end
    
    local playerPos = humanoidRootPart.Position
    local closestEnemy = enemies[1]
    local closestDistance = math.huge
    
    for i = 1, math.min(#enemies, 15) do
        local enemy = enemies[i]
        local distance = (enemy.Position - playerPos).Magnitude
        if distance < closestDistance then
            closestDistance = distance
            closestEnemy = enemy
        end
    end
    
    return closestEnemy
end

-- Add missing equipTool function
local function equipTool()
    if not State.playerAlive then 
        task.wait(0.5)
        return equipTool()
    end
    
    local character = player.Character
    if not character then 
        task.wait(0.5)
        return equipTool()
    end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then 
        task.wait(0.5)
        return equipTool()
    end
    
    local tool = character:FindFirstChild(CONFIG.TOOL_NAME)
    if not tool then
        local backpack = player:FindFirstChild("Backpack")
        if backpack then
            tool = backpack:FindFirstChild(CONFIG.TOOL_NAME)
            if tool then
                tool.Parent = character
            else
                return false
            end
        else
            task.wait(0.5)
            return equipTool()
        end
    end
    
    if tool then
        humanoid:EquipTool(tool)
        task.wait(0.2)
        
        if character:FindFirstChild(CONFIG.TOOL_NAME) then
            return true
        end
    end
    
    return false
end

-- Optimized function to get valid tool
local function getValidTool()
    if not State.playerAlive then return nil end
    
    local character = player.Character
    if not character then return nil end
    
    local tool = character:FindFirstChild(CONFIG.TOOL_NAME)
    if not tool then return nil end
    
    local remote = tool:FindFirstChild(CONFIG.REMOTE_NAME)
    local handle = tool:FindFirstChild("Handle")
    
    if remote and handle and remote:IsA("RemoteFunction") then
        return {Tool = tool, Remote = remote, Handle = handle}
    end
    
    return nil
end

-- Optimized firing logic with special target part handling
local function attemptFire()
    if not State.isRunning or State.specialMode or State.gilgameshCompleted then return end
    if not State.playerAlive then return end
    
    State.currentTarget = selectTarget()
    if not State.currentTarget then
        return
    end
    
    local toolData = getValidTool()
    if not toolData then 
        local equipped = equipTool()
        if not equipped then return end
        
        toolData = getValidTool()
        if not toolData then return end
    end
    
    -- Get target position (fixed for Arbiter at 2170, 14, 1554, actual for others)
    local targetPos
    if State.currentTarget.Name == "The Arbiter" then
        targetPos = CONFIG.ARBITER_TARGET_POSITION  -- 2170, 14, 1554
    else
        targetPos = State.currentTarget.TargetPart.Position
    end
    
    local camera = workspace.CurrentCamera
    if not camera then return end
    
    local cameraPosition = camera.CFrame.Position
    local cameraToTarget = (targetPos - cameraPosition).Unit
    
    -- Shoot directly at target part
    local startPos = targetPos
    local endPos = targetPos
    
    local travelDistance = (endPos - startPos).Magnitude
    if travelDistance < 0.1 then
        startPos = targetPos - (cameraToTarget * 0.1)
    end
    
    local success = pcall(function()
        return toolData.Remote:InvokeServer("fire", {startPos, endPos, State.chargeValue})
    end)
    
    if not success then
        local attachment = toolData.Handle:FindFirstChild("Attachment")
        if attachment then
            local toolPosition = attachment.WorldPosition
            local direction = (targetPos - toolPosition).Unit
            local nearTargetPos = targetPos - (direction * 0.01)
            
            pcall(function()
                return toolData.Remote:InvokeServer("fire", {nearTargetPos, targetPos, State.chargeValue})
            end)
        end
    end
end

-- Optimized shield system
local function useShield()
    local now = tick()
    if now - State.lastShieldUse < CONFIG.SHIELD_COOLDOWN then return end
    
    local char = player.Character
    if not char then return end
    
    local shield = char:FindFirstChild("Shield")
    if not shield then return end
    
    local remote = shield:FindFirstChild("ShieldRemote")
    if not remote then return end
    
    task.spawn(function()
        pcall(remote.FireServer, remote)
        State.lastShieldUse = now
        State.shieldUsed = true
    end)
end

-- Function to check if player is alive
local function isPlayerAlive()
    if not player.Character then return false end
    
    local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end
    
    return humanoid.Health > 0
end

-- Optimized health monitoring
local function setupHealthMonitoring()
    cleanConnectionPool()
    
    local char = player.Character
    if not char then return end
    
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    
    local maxHealth = humanoid.MaxHealth
    
    local connection = humanoid.HealthChanged:Connect(function(currentHealth)
        if currentHealth > 0 and maxHealth > 0 then
            local healthPercent = (currentHealth / maxHealth) * 100
            
            if healthPercent < 50 and not State.shieldUsed then
                useShield()
            elseif healthPercent >= 50 then
                State.shieldUsed = false
            end
        end
    end)
    
    table.insert(State.connectionPool, connection)
end

-- Function to monitor player death
local function setupDeathMonitoring()
    cleanConnectionPool()
    
    local char = player.Character
    if not char then return end
    
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    
    local connection = humanoid.HealthChanged:Connect(function(health)
        local wasAlive = State.playerAlive
        State.playerAlive = health > 0
        
        if health <= 0 and wasAlive then
            State.currentTarget = nil
            State.shieldUsed = false
        elseif health > 0 and not wasAlive then
            task.wait(1.5)
            if State.isRunning and not State.specialMode and not State.gilgameshCompleted then
                equipTool()
                State.shieldUsed = false
            end
        end
    end)
    
    State.playerAlive = humanoid.Health > 0
    table.insert(State.connectionPool, connection)
end

-- Optimized skip commands with delay
local function sendSkipCommands()
    if game.PlaceId ~= SPECIFIC_PLACE_ID then return end
    if State.skipAllSaid and State.skipSaid then return end
    
    task.spawn(function()
        if not State.skipAllSaid then
            task.wait(0.5)
            chatMessage("/skipall")
            State.skipAllSaid = true
        end
        
        task.wait(1)
        
        if not State.skipSaid then
            chatMessage("/skip")
            State.skipSaid = true
        end
    end)
end

-- Optimized teleport with safety check
local function teleportToPosition()
    if State.teleported then return end
    if game.PlaceId ~= SPECIFIC_PLACE_ID then return end
    
    local char = player.Character
    if not char then return end
    
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    State.teleported = true
    
    local tweenInfo = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local tween = TweenService:Create(hrp, tweenInfo, {CFrame = CFrame.new(TELEPORT_POSITION)})
    tween:Play()
end

-- Function to handle dungeon entry
local function handleGilgameshCompletion()
    if State.gilgameshCompleted then return end
    State.gilgameshCompleted = true
    State.specialMode = true
    State.isRunning = false
    
    task.wait(3)
    
    local tool = getValidTool()
    if tool and tool.Tool then
        tool.Tool.Parent = player.Backpack
    end
    
    task.wait(1)
    
    local character = player.Character
    if character then
        local artifact = character:FindFirstChild("Mysterious Artifact")
        if not artifact then
            local backpack = player:FindFirstChild("Backpack")
            if backpack then
                artifact = backpack:FindFirstChild("Mysterious Artifact")
                if artifact then
                    artifact.Parent = character
                end
            end
        end
        
        if artifact then
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if humanoid then
                humanoid:EquipTool(artifact)
            end
        end
    end
    
    task.wait(2)
    
    pcall(function()
        local args = {
            [1] = "createParty",
            [2] = {
                ["settings"] = {
                    ["FriendsOnly"] = false,
                    ["Visual"] = true
                },
                ["subplace"] = "Stronghold"
            }
        }
        
        local partyRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PartySystem"):WaitForChild("PartyFunction")
        partyRemote:InvokeServer(unpack(args))
    end)
    
    task.wait(3)
    
    pcall(function()
        local args = {
            [1] = "joinSubplace",
            [2] = {}
        }
        
        local partyRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PartySystem"):WaitForChild("PartyFunction")
        partyRemote:InvokeServer(unpack(args))
    end)
end

-- Function to check Gilgamesh status
local function checkGilgameshStatus()
    local gilgamesh = workspace:FindFirstChild("Gilgamesh, the Consumer of Reality")
    
    if gilgamesh then
        State.gilgameshHasSpawned = true
        
        local humanoid = gilgamesh:FindFirstChildOfClass("Humanoid")
        if humanoid then
            if humanoid.Health <= 0 then
                return "dead"
            else
                return "alive"
            end
        else
            return "spawning"
        end
    else
        return "not_spawned"
    end
end

-- Main farming loop
local function farmingLoop()
    local heartbeat = RunService.Heartbeat
    local lastEnemyCheck = 0
    local enemyCheckInterval = 0.3
    local lastGilgameshCheck = 0
    local gilgameshCheckInterval = 1
    
    while State.isRunning and not State.gilgameshCompleted do
        local now = tick()
        
        State.playerAlive = isPlayerAlive()
        
        if State.playerAlive then
            if now - lastGilgameshCheck > gilgameshCheckInterval then
                local gilgameshStatus = checkGilgameshStatus()
                
                if State.gilgameshHasSpawned and gilgameshStatus == "dead" and not State.gilgameshCompleted then
                    handleGilgameshCompletion()
                    break
                end
                
                lastGilgameshCheck = now
            end
            
            if now - lastEnemyCheck > enemyCheckInterval then
                State.currentTarget = selectTarget()
                lastEnemyCheck = now
            end
            
            if State.currentTarget then
                if not getValidTool() then
                    equipTool()
                end
                
                if now - State.lastFireTime >= CONFIG.FIRE_RATE then
                    State.lastFireTime = now
                    attemptFire()
                end
            end
        else
            State.currentTarget = nil
        end
        
        heartbeat:Wait()
    end
end

-- Character handling
local function onCharacterAdded(character)
    task.wait(2)
    
    setupDeathMonitoring()
    setupHealthMonitoring()
    
    -- Teleport to position if in specific game (only once)
    if game.PlaceId == SPECIFIC_PLACE_ID and not State.teleported then
        task.wait(1)
        teleportToPosition()
    end
    
    -- Send skip commands in specific game
    if game.PlaceId == SPECIFIC_PLACE_ID and (not State.skipAllSaid or not State.skipSaid) then
        task.spawn(function()
            sendSkipCommands()
        end)
    end
    
    if State.isRunning and not State.specialMode and not State.gilgameshCompleted then
        if isPlayerAlive() then
            equipTool()
        end
    end
end

-- Optimized initialization
local function initialize()
    if not player.Character then
        player.CharacterAdded:Wait()
    end
    
    player.CharacterAdded:Connect(onCharacterAdded)
    
    onCharacterAdded(player.Character)
    
    task.spawn(farmingLoop)
    
    -- SIMPLIFIED memory management (no collectgarbage needed)
    task.spawn(function()
        while State.isRunning and not State.gilgameshCompleted do
            task.wait(60)
            -- Just clear caches periodically
            ObjectPools.workspaceCache = {}
            ObjectPools.enemyCache = {}
            cleanConnectionPool()
        end
    end)
end

-- Safe start with auto-execute compatibility
local function safeStart()
    -- Wait for everything to load
    while not game:IsLoaded() do
        task.wait(0.5)
    end
    
    while not Players.LocalPlayer do
        task.wait(0.5)
    end
    
    player = Players.LocalPlayer
    
    if not player.Character then
        player.CharacterAdded:Wait()
    end
    
    task.wait(2)
    
    local success, err = pcall(initialize)
    if not success then
        task.wait(5)
        safeStart()
    end
end

-- Auto-start the script
task.spawn(safeStart)

-- Return API
return {
    Stop = function()
        State.isRunning = false
        for _, conn in ipairs(State.connectionPool) do
            pcall(conn.Disconnect, conn)
        end
    end,
    
    Start = function()
        if not State.isRunning then
            State.isRunning = true
            task.spawn(farmingLoop)
        end
    end,
    
    EquipTool = equipTool,
    
    ForceCleanup = function()
        -- Simple cleanup without collectgarbage
        cleanConnectionPool()
        ObjectPools.enemyCache = {}
        ObjectPools.workspaceCache = {}
    end,
    
    ForceSkipCommands = function()
        sendSkipCommands()
    end,
    
    TeleportToPosition = function()
        teleportToPosition()
    end
}
