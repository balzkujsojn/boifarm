-- Wait for game and local player to fully load
repeat task.wait() until game:IsLoaded()
local Players = game:GetService("Players")
repeat task.wait() until Players.LocalPlayer
local player = Players.LocalPlayer

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- Configuration
local CONFIG = {
    FIRE_RATE = 0.08,
    TOOL_NAME = "Equinox Cannon",
    REMOTE_NAME = "RemoteFunction",
    TARGET_UPDATE_INTERVAL = 0.5,  -- FIXED: Correct variable name
    WORLDUPDATE_INTERVAL = 2,
    HEALTHCHECK_INTERVAL = 1,
    MAX_TARGET_DISTANCE = 300,
    SHIELD_COOLDOWN = 5,
    ARBITER_TARGET_POSITION = Vector3.new(2199, -1, 1555)
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

-- Special target parts with fallbacks
local SPECIAL_TARGET_PARTS = {
    ["Gilgamesh, the Consumer of Reality"] = {"HumanoidRootPart", "Torso", "UpperTorso", "Head"},
    ["Controller Turret"] = {"HumanoidRootPart", "Torso", "UpperTorso"}
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

-- Performance tracking
local Performance = {
    frameCount = 0,
    lastPerfCheck = tick(),
    fps = 60,
    memoryUsage = 0
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
    
    if State.arbiterSpawned and not State.currentTarget then
        warn("⚠️ The Arbiter has spawned! Switching to fixed position targeting...")
    end
    
    return State.arbiterSpawned
end

-- Get target position for specific enemy
local function getTargetPositionForEnemy(enemyName, enemyModel)
    -- Check if this enemy has a fixed target position
    if SPECIAL_TARGET_POSITIONS[enemyName] then
        return SPECIAL_TARGET_POSITIONS[enemyName]
    end
    
    -- For other enemies, get their actual part position
    local specialParts = SPECIAL_TARGET_PARTS[enemyName]
    if specialParts then
        for _, partName in ipairs(specialParts) do
            local part = enemyModel:FindFirstChild(partName)
            if part then
                return part.Position
            end
        end
    end
    
    -- Default fallback
    local rootPart = enemyModel:FindFirstChild("HumanoidRootPart")
    if rootPart then
        return rootPart.Position
    end
    
    local torso = enemyModel:FindFirstChild("Torso") or enemyModel:FindFirstChild("UpperTorso")
    if torso then
        return torso.Position
    end
    
    return enemyModel:GetPivot().Position
end

-- Get target part for visual/validation
local function getTargetPartForValidation(model)
    local rootPart = model:FindFirstChild("HumanoidRootPart")
    if rootPart then return rootPart end
    
    local torso = model:FindFirstChild("Torso") or model:FindFirstChild("UpperTorso")
    if torso then return torso end
    
    return model:FindFirstChild("Head")
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
    if now - State.lastWorldUpdate > CONFIG.WORLDUPDATE_INTERVAL then
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
    
    local char = player.Character
    local playerPos = char and char:FindFirstChild("HumanoidRootPart") and 
                      char.HumanoidRootPart.Position or Vector3.zero
    
    local priorityFound = false
    
    for _, model in ipairs(ObjectPools.workspaceCache) do
        if not State.isRunning then break end
        
        if model:IsA("Model") and model.Parent == workspace then
            local humanoid = model:FindFirstChildOfClass("Humanoid")
            local enemyMain = model:FindFirstChild("EnemyMain")
            
            if humanoid and humanoid.Health > 0 and enemyMain then
                local targetPart = getTargetPartForValidation(model)
                if targetPart then
                    local distance = (targetPart.Position - playerPos).Magnitude
                    if distance < CONFIG.MAX_TARGET_DISTANCE then
                        local isPriority = PRIORITY_ENEMIES[model.Name] == true
                        
                        -- Track special enemies
                        if model.Name == "Gilgamesh, the Consumer of Reality" then
                            State.gilgameshHasSpawned = true
                        elseif model.Name == "The Arbiter" then
                            State.arbiterSpawned = true
                        end
                        
                        -- Get the actual shooting position for this enemy
                        local shootPosition = getTargetPositionForEnemy(model.Name, model)
                        
                        local enemyData = {
                            Model = model,
                            Humanoid = humanoid,
                            TargetPart = targetPart,
                            ShootPosition = shootPosition,
                            Name = model.Name,
                            IsPriority = isPriority,
                            Distance = distance,
                            HasFixedPosition = SPECIAL_TARGET_POSITIONS[model.Name] ~= nil
                        }
                        
                        if isPriority then
                            table.insert(ObjectPools.enemyCache, 1, enemyData)
                            priorityFound = true
                            if #ObjectPools.enemyCache > 10 then break end
                        elseif not priorityFound then
                            table.insert(ObjectPools.enemyCache, enemyData)
                            if #ObjectPools.enemyCache > 15 then break end
                        end
                    end
                end
            end
        end
    end
    
    -- Sort by priority first, then distance
    if #ObjectPools.enemyCache > 0 and not priorityFound then
        table.sort(ObjectPools.enemyCache, function(a, b)
            return a.Distance < b.Distance
        end)
    end
    
    return ObjectPools.enemyCache
end

-- Optimized target selection
local function selectTarget()
    if not State.playerAlive then return nil end
    
    local now = tick()
    -- FIXED: Changed CONFIG.TARGETUPDATE_INTERVAL to CONFIG.TARGET_UPDATE_INTERVAL
    if now - State.lastTargetUpdate < CONFIG.TARGET_UPDATE_INTERVAL and State.currentTarget then
        -- Validate current target still exists
        local target = State.currentTarget
        if target.Model and target.Model.Parent then
            local humanoid = target.Model:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.Health > 0 then
                return target
            end
        end
    end
    
    State.lastTargetUpdate = now
    local enemies = findEnemies()
    
    if #enemies == 0 then
        State.currentTarget = nil
        return nil
    end
    
    -- Return first enemy (already sorted by priority/distance)
    State.currentTarget = enemies[1]
    
    -- Log special targeting for The Arbiter
    if State.currentTarget.Name == "The Arbiter" and State.currentTarget.HasFixedPosition then
        warn("🎯 Targeting The Arbiter at fixed position:", CONFIG.ARBITER_TARGET_POSITION)
    end
    
    return State.currentTarget
end

-- FIXED: Add missing equipTool function
local function equipTool()
    if not State.playerAlive then 
        return false
    end
    
    local character = player.Character
    if not character then 
        task.wait(0.5)
        return equipTool()
    end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then 
        return false
    end
    
    -- Check if tool is already in character
    local tool = character:FindFirstChild(CONFIG.TOOL_NAME)
    if not tool then
        -- Check backpack
        local backpack = player:FindFirstChild("Backpack")
        if backpack then
            tool = backpack:FindFirstChild(CONFIG.TOOL_NAME)
            if tool then
                tool.Parent = character
                task.wait(0.2)
            else
                warn("✗ Equinox Cannon not found in backpack!")
                return false
            end
        else
            warn("✗ Backpack not found!")
            return false
        end
    end
    
    -- Equip the tool
    if tool then
        humanoid:EquipTool(tool)
        task.wait(0.3)
        
        if character:FindFirstChild(CONFIG.TOOL_NAME) then
            warn("✓ Equinox Cannon equipped")
            cachedToolData = nil  -- Clear cache so it gets fresh tool data
            return true
        end
    end
    
    return false
end

-- Optimized tool handling with caching
local lastToolCheck = 0
local cachedToolData = nil
local function getValidTool()
    if not State.playerAlive then
        cachedToolData = nil
        return nil
    end
    
    local now = tick()
    if cachedToolData and now - lastToolCheck < 1 then
        return cachedToolData
    end
    
    lastToolCheck = now
    local char = player.Character
    if not char then
        cachedToolData = nil
        return nil
    end
    
    local tool = char:FindFirstChild(CONFIG.TOOL_NAME)
    if not tool then
        -- Try to equip if not found
        local equipped = equipTool()
        if not equipped then
            cachedToolData = nil
            return nil
        end
        tool = char:FindFirstChild(CONFIG.TOOL_NAME)
        if not tool then
            cachedToolData = nil
            return nil
        end
    end
    
    if tool then
        local remote = tool:FindFirstChild(CONFIG.REMOTE_NAME)
        local handle = tool:FindFirstChild("Handle")
        
        if remote and remote:IsA("RemoteFunction") and handle then
            cachedToolData = {Tool = tool, Remote = remote, Handle = handle}
            return cachedToolData
        end
    end
    
    cachedToolData = nil
    return nil
end

-- Optimized firing with special position handling
local function attemptFire()
    if not State.isRunning or State.specialMode or State.gilgameshCompleted then return end
    if not State.playerAlive then return end
    
    local target = selectTarget()
    if not target then return end
    
    local toolData = getValidTool()
    if not toolData then
        -- Try to equip again
        if equipTool() then
            toolData = getValidTool()
            if not toolData then return end
        else
            return
        end
    end
    
    local now = tick()
    if now - State.lastFireTime < CONFIG.FIRE_RATE then return end
    
    State.lastFireTime = now
    
    -- Use the correct shooting position for this enemy
    local targetPos = target.ShootPosition
    
    -- For moving enemies with fixed positions, add slight offset for accuracy
    if target.HasFixedPosition and target.Humanoid.MoveDirection.Magnitude > 0 then
        local velocity = target.Humanoid.MoveDirection * target.Humanoid.WalkSpeed
        targetPos = targetPos + (velocity * 0.15)
    end
    
    -- Log targeting info for The Arbiter
    if target.Name == "The Arbiter" then
        local arbiterActualPos = target.TargetPart.Position
        local distanceToFixedPos = (arbiterActualPos - CONFIG.ARBITER_TARGET_POSITION).Magnitude
        warn(string.format("🎯 Shooting The Arbiter: Actual(%.1f, %.1f, %.1f) → Target(%.1f, %.1f, %.1f) | Distance: %.1f studs",
            arbiterActualPos.X, arbiterActualPos.Y, arbiterActualPos.Z,
            targetPos.X, targetPos.Y, targetPos.Z,
            distanceToFixedPos))
    end
    
    -- Fire at target position
    local success = pcall(function()
        return toolData.Remote:InvokeServer("fire", {targetPos, targetPos, State.chargeValue})
    end)
    
    if not success then
        -- Fallback: fire from camera
        local camera = workspace.CurrentCamera
        if camera then
            local startPos = camera.CFrame.Position
            local direction = (targetPos - startPos).Unit
            local nearTarget = targetPos - (direction * 0.5)
            
            pcall(function()
                return toolData.Remote:InvokeServer("fire", {nearTarget, targetPos, State.chargeValue})
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

-- Optimized health monitoring
local function setupHealthMonitoring()
    cleanConnectionPool()
    
    local char = player.Character
    if not char then return end
    
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    
    local connection = humanoid.HealthChanged:Connect(function(health)
        if not State.isRunning then return end
        
        State.playerAlive = health > 0
        
        if not State.playerAlive then
            State.currentTarget = nil
            cachedToolData = nil
            State.shieldUsed = false
            return
        end
        
        local now = tick()
        if now - State.lastHealthCheck < CONFIG.HEALTHCHECK_INTERVAL then return end
        
        State.lastHealthCheck = now
        local maxHealth = humanoid.MaxHealth
        
        if maxHealth > 0 and health > 0 then
            local healthPercent = (health / maxHealth) * 100
            
            if healthPercent < 50 and not State.shieldUsed then
                useShield()
            elseif healthPercent >= 50 then
                State.shieldUsed = false
            end
        end
    end)
    
    table.insert(State.connectionPool, connection)
end

-- Optimized performance monitoring
local function monitorPerformance()
    Performance.frameCount = Performance.frameCount + 1
    
    local now = tick()
    if now - Performance.lastPerfCheck >= 1 then
        Performance.fps = Performance.frameCount
        Performance.frameCount = 0
        
        local mem = collectgarbage("count")
        Performance.memoryUsage = mem
        
        if mem > 50000 then
            warn("High memory detected (" .. math.floor(mem) .. " KB), cleaning up...")
            collectgarbage("collect")
            cleanConnectionPool()
            cachedToolData = nil
            ObjectPools.enemyCache = {}
        end
        
        Performance.lastPerfCheck = now
    end
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
    
    local tweenInfo = TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local tween = TweenService:Create(hrp, tweenInfo, {CFrame = CFrame.new(TELEPORT_POSITION)})
    tween:Play()
end

-- FIXED: Optimized main loop with simplified Gilgamesh check
local function farmingLoop()
    local heartbeat = RunService.Heartbeat
    
    while State.isRunning and not State.gilgameshCompleted do
        monitorPerformance()
        
        if State.playerAlive and not State.specialMode then
            -- Check for Arbiter spawn
            checkArbiterSpawned()
            
            -- Update target periodically
            local target = selectTarget()
            
            if target then
                if not getValidTool() then
                    if equipTool() then
                        task.wait(0.2)
                    end
                else
                    attemptFire()
                end
            end
            
            -- SIMPLIFIED: Check Gilgamesh status every frame
            if State.gilgameshHasSpawned and not State.gilgameshCompleted then
                local gilgamesh = workspace:FindFirstChild("Gilgamesh, the Consumer of Reality")
                if not gilgamesh then
                    State.gilgameshCompleted = true
                    break
                end
            end
        end
        
        heartbeat:Wait()
    end
    
    if State.gilgameshCompleted then
        task.spawn(function()
            task.wait(2)
            warn("Transitioning to dungeon sequence...")
        end)
    end
end

-- Optimized initialization
local function initialize()
    warn("🚀 Starting AutoFarm initialization...")
    
    local function setupCharacter()
        warn("Setting up character...")
        setupHealthMonitoring()
        
        if game.PlaceId == SPECIFIC_PLACE_ID then
            if not State.teleported then
                warn("Teleporting to position...")
                task.wait(2)
                teleportToPosition()
            end
            
            if not State.skipAllSaid or not State.skipSaid then
                warn("Sending skip commands...")
                task.wait(3)
                sendSkipCommands()
            end
        end
        
        -- Auto-equip tool on startup
        task.wait(1)
        if equipTool() then
            warn("✓ AutoFarm initialized successfully!")
        else
            warn("⚠️ Could not equip tool initially, will retry when needed")
        end
    end
    
    if player.Character then
        setupCharacter()
    end
    
    local charAddedConn = player.CharacterAdded:Connect(function(char)
        warn("Character added, re-initializing...")
        task.wait(2)
        setupCharacter()
    end)
    
    table.insert(State.connectionPool, charAddedConn)
    
    -- Start main loop
    warn("Starting farming loop...")
    task.spawn(farmingLoop)
    
    -- Memory management loop
    task.spawn(function()
        while State.isRunning do
            task.wait(30)
            cleanConnectionPool()
            updateWorkspaceCache()
            
            if tick() % 120 < 1 then
                collectgarbage("collect")
            end
        end
    end)
end

-- FIXED: Safe start with auto-execute compatibility
local function safeStart()
    -- Wait for everything to load
    warn("⏳ Waiting for game to load...")
    while not game:IsLoaded() do
        task.wait(0.5)
    end
    
    warn("⏳ Waiting for local player...")
    while not Players.LocalPlayer do
        task.wait(0.5)
    end
    
    player = Players.LocalPlayer
    
    warn("⏳ Waiting for character...")
    if not player.Character then
        player.CharacterAdded:Wait()
    end
    
    task.wait(2) -- Extra safety delay
    
    warn("✅ Starting AutoFarm...")
    local success, err = pcall(initialize)
    if not success then
        warn("❌ Initialization error:", err)
        warn("🔄 Retrying in 5 seconds...")
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
    
    GetPerformance = function()
        return {
            FPS = Performance.fps,
            MemoryKB = Performance.memoryUsage,
            TargetsCached = #ObjectPools.enemyCache,
            ArbiterSpawned = State.arbiterSpawned,
            CurrentTarget = State.currentTarget and State.currentTarget.Name or "None",
            ToolEquipped = cachedToolData ~= nil
        }
    end,
    
    ForceCleanup = function()
        collectgarbage("collect")
        cleanConnectionPool()
        ObjectPools.enemyCache = {}
        cachedToolData = nil
    end,
    
    GetTargetInfo = function()
        if State.currentTarget then
            return {
                Name = State.currentTarget.Name,
                ShootPosition = State.currentTarget.ShootPosition,
                ActualPosition = State.currentTarget.TargetPart and State.currentTarget.TargetPart.Position,
                HasFixedPosition = State.currentTarget.HasFixedPosition
            }
        end
        return nil
    end
}