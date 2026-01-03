repeat task.wait() until game:IsLoaded()
local Players = game:GetService("Players")
repeat task.wait() until Players.LocalPlayer
local player = Players.LocalPlayer

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")

local CONFIG = {
    FIRE_RATE = 0.05,  -- 20 shots per second
    TOOL_NAME = "Equinox Cannon",
    REMOTE_NAME = "RemoteFunction"
}

local PRIORITY_ENEMIES = {
    ["The Arbiter"] = true,
    ["Gilgamesh, the Consumer of Reality"] = true,
    ["The Supreme Uber Bringer of Light and Space Time Annihilation"] = true,
    ["Controller Turret"] = true
}

local SPECIAL_TARGET_PARTS = {
    ["The Arbiter"] = "HumanoidRootPart"
}

local TELEPORT_POSITION = Vector3.new(-21, 103, -469)
local SPECIFIC_PLACE_ID = 96516249626799
local AUTOTELEPORT_PLACE_ID = 8811271345

local ARBITER_TARGET_POSITION = Vector3.new(2170, 14, 1554)

local State = {
    isRunning = true,
    specialMode = false,
    lastFireTime = 0,
    currentTarget = nil,
    chargeValue = 100,
    bossHasSpawned = false,
    bossCompleted = false,
    playerAlive = true,
    skipSaid = false,
    skipAllSaid = false,
    shieldUsed = false,
    lastShieldUse = 0,
    shieldCooldown = 5,
    teleported = false,
    livesChecked = false,
    lastLivesCheck = 0,
    autoTeleportTriggered = false
}

local cache = {
    workspaceChildren = {},
    lastWorkspaceUpdate = 0,
    workspaceUpdateInterval = 0.5,  -- Reduced for faster updates
    lastPriorityCheck = 0
}

-- Debug function
local function debugPrint(message)
    warn("[AutoFarm] " .. message)
end

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
    else
        local channel = TextChatService:FindFirstChild("TextChannels")
        if channel then
            channel = channel:FindFirstChild("RBXGeneral")
            if channel and channel:IsA("TextChannel") then
                task.spawn(function()
                    pcall(channel.SendAsync, channel, str)
                end)
            end
        end
    end
end

local function sendSkipCommands()
    if game.PlaceId ~= SPECIFIC_PLACE_ID then return end
    if State.skipAllSaid and State.skipSaid then return end
    
    task.spawn(function()
        if not State.skipAllSaid then
            task.wait(0.5)
            debugPrint("Sending /skipall...")
            chatMessage("/skipall")
            State.skipAllSaid = true
        end
        
        task.wait(1)
        
        if not State.skipSaid then
            debugPrint("Sending /skip...")
            chatMessage("/skip")
            State.skipSaid = true
        end
    end)
end

local function teleportToPosition()
    if State.teleported then return end
    if game.PlaceId ~= SPECIFIC_PLACE_ID then return end
    
    local char = player.Character
    if not char then return end
    
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    State.teleported = true
    debugPrint("Teleporting to position...")
    
    local tweenInfo = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local tween = TweenService:Create(hrp, tweenInfo, {CFrame = CFrame.new(TELEPORT_POSITION)})
    tween:Play()
end

local function isPlayerAlive()
    if not player.Character then return false end
    
    local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end
    
    return humanoid.Health > 0
end

local function getTargetPart(model)
    local enemyName = model.Name
    
    if SPECIAL_TARGET_PARTS[enemyName] then
        local specialPart = model:FindFirstChild(SPECIAL_TARGET_PARTS[enemyName])
        if specialPart then
            return specialPart
        end
    end
    
    -- Try multiple possible part names
    local possibleParts = {
        "HumanoidRootPart",
        "Head",
        "Torso", 
        "UpperTorso",
        "LowerTorso",
        "Chest",
        "Body"
    }
    
    for _, partName in ipairs(possibleParts) do
        local part = model:FindFirstChild(partName)
        if part and part:IsA("BasePart") then
            return part
        end
    end
    
    -- If no standard part found, try to find any BasePart
    for _, child in ipairs(model:GetChildren()) do
        if child:IsA("BasePart") then
            return child
        end
    end
    
    return nil
end

local function findEnemies()
    if not State.playerAlive then 
        return {}
    end
    
    local now = tick()
    
    -- Update cache less frequently for performance
    if now - cache.lastWorkspaceUpdate > cache.workspaceUpdateInterval then
        cache.workspaceChildren = workspace:GetChildren()
        cache.lastWorkspaceUpdate = now
    end
    
    local enemies = {}
    local priorityEnemies = {}
    
    for _, model in ipairs(cache.workspaceChildren) do
        if model:IsA("Model") and model.Parent == workspace then
            local humanoid = model:FindFirstChildOfClass("Humanoid")
            
            -- Check if it's an enemy by checking health and if it has EnemyMain or other indicators
            if humanoid and humanoid.Health > 0 then
                -- Check if it's an enemy (not a player)
                local isPlayerCharacter = false
                for _, plr in ipairs(Players:GetPlayers()) do
                    if plr.Character == model then
                        isPlayerCharacter = true
                        break
                    end
                end
                
                if not isPlayerCharacter then
                    local targetPart = getTargetPart(model)
                    if targetPart then
                        local enemyData = {
                            Model = model,
                            Humanoid = humanoid,
                            TargetPart = targetPart,
                            Position = targetPart.Position,
                            Name = model.Name,
                            IsPriority = PRIORITY_ENEMIES[model.Name] == true,
                            LastSeen = now
                        }
                        
                        -- Check for boss spawns
                        if model.Name == "Gilgamesh, the Consumer of Reality" or 
                           model.Name == "The Supreme Uber Bringer of Light and Space Time Annihilation" then
                            State.bossHasSpawned = true
                            debugPrint("Boss detected: " .. model.Name)
                        end
                        
                        if enemyData.IsPriority then
                            table.insert(priorityEnemies, enemyData)
                        else
                            table.insert(enemies, enemyData)
                        end
                    end
                end
            end
        end
    end
    
    -- Return priority enemies first, then regular enemies
    if #priorityEnemies > 0 then
        debugPrint("Found " .. #priorityEnemies .. " priority enemies")
        return priorityEnemies
    elseif #enemies > 0 then
        debugPrint("Found " .. #enemies .. " regular enemies")
        return enemies
    end
    
    return {}
end

local function selectTarget()
    if not State.playerAlive then 
        return nil
    end
    
    local enemies = findEnemies()
    
    if #enemies == 0 then
        return nil
    end
    
    -- Check if current target is still valid
    if State.currentTarget then
        local targetModel = State.currentTarget.Model
        if targetModel and targetModel.Parent then
            local humanoid = targetModel:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.Health > 0 then
                -- If we have a priority target, keep it
                if State.currentTarget.IsPriority then
                    return State.currentTarget
                end
            end
        end
    end
    
    -- Select new target
    local character = player.Character
    if not character then 
        return enemies[1] 
    end
    
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then 
        return enemies[1] 
    end
    
    local playerPos = humanoidRootPart.Position
    local closestEnemy = enemies[1]
    local closestDistance = math.huge
    
    -- Find closest enemy
    for _, enemy in ipairs(enemies) do
        local distance = (enemy.Position - playerPos).Magnitude
        if distance < closestDistance then
            closestDistance = distance
            closestEnemy = enemy
        end
    end
    
    debugPrint("Selected target: " .. closestEnemy.Name .. " (Distance: " .. math.floor(closestDistance) .. ")")
    return closestEnemy
end

local function getValidTool()
    if not State.playerAlive then 
        return nil 
    end
    
    local character = player.Character
    if not character then 
        return nil 
    end
    
    local tool = character:FindFirstChild(CONFIG.TOOL_NAME)
    if not tool then 
        return nil 
    end
    
    local remote = tool:FindFirstChild(CONFIG.REMOTE_NAME)
    local handle = tool:FindFirstChild("Handle")
    
    if remote and handle and remote:IsA("RemoteFunction") then
        return {Tool = tool, Remote = remote, Handle = handle}
    end
    
    return nil
end

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
    
    -- Check if tool is already equipped
    local tool = character:FindFirstChild(CONFIG.TOOL_NAME)
    if tool then
        humanoid:EquipTool(tool)
        return true
    end
    
    -- Try to find tool in backpack
    local backpack = player:FindFirstChild("Backpack")
    if backpack then
        tool = backpack:FindFirstChild(CONFIG.TOOL_NAME)
        if tool then
            tool.Parent = character
            task.wait(0.1)
            humanoid:EquipTool(tool)
            debugPrint("Equipped tool from backpack")
            return true
        end
    end
    
    debugPrint("Tool not found")
    return false
end

local function attemptFire()
    if not State.isRunning or State.specialMode or State.bossCompleted then 
        return 
    end
    if not State.playerAlive then 
        return 
    end
    
    -- Get or update current target
    State.currentTarget = selectTarget()
    if not State.currentTarget then
        return
    end
    
    -- Get tool
    local toolData = getValidTool()
    if not toolData then 
        local equipped = equipTool()
        if not equipped then 
            return 
        end
        
        toolData = getValidTool()
        if not toolData then 
            return 
        end
    end
    
    -- Check fire rate
    local now = tick()
    if now - State.lastFireTime < CONFIG.FIRE_RATE then 
        return 
    end
    
    State.lastFireTime = now
    
    -- Determine target position
    local targetPos
    if State.currentTarget.Name == "The Arbiter" then
        targetPos = ARBITER_TARGET_POSITION
        debugPrint("Firing at Arbiter (fixed position)")
    else
        local targetPart = State.currentTarget.TargetPart
        targetPos = targetPart.Position
        debugPrint("Firing at " .. State.currentTarget.Name)
    end
    
    -- Get camera for direction calculation
    local camera = workspace.CurrentCamera
    if not camera then 
        return 
    end
    
    -- Calculate firing positions
    local cameraPosition = camera.CFrame.Position
    local direction = (targetPos - cameraPosition).Unit
    
    local startPos = targetPos - (direction * 5)  -- Start 5 studs away from target
    local endPos = targetPos
    
    -- Try to fire
    local success, result = pcall(function()
        return toolData.Remote:InvokeServer("fire", {startPos, endPos, State.chargeValue})
    end)
    
    if not success then
        debugPrint("Fire failed: " .. tostring(result))
        
        -- Fallback: try different positions
        pcall(function()
            return toolData.Remote:InvokeServer("fire", {targetPos, targetPos, State.chargeValue})
        end)
    end
end

local function handleBossCompletion()
    if State.bossCompleted then 
        return 
    end
    
    debugPrint("Boss completed, preparing for dungeon...")
    State.bossCompleted = true
    State.specialMode = true
    State.isRunning = false
    
    task.wait(3)
    
    -- Unequip cannon
    local tool = getValidTool()
    if tool and tool.Tool then
        tool.Tool.Parent = player.Backpack
    end
    
    task.wait(1)
    
    -- Equip artifact if available
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
    
    -- Create party
    pcall(function()
        local partyRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PartySystem"):WaitForChild("PartyFunction")
        partyRemote:InvokeServer("createParty", {
            settings = {
                FriendsOnly = false,
                Visual = true
            },
            subplace = "Stronghold"
        })
        debugPrint("Party created")
    end)
    
    task.wait(3)
    
    -- Join dungeon
    pcall(function()
        local partyRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PartySystem"):WaitForChild("PartyFunction")
        partyRemote:InvokeServer("joinSubplace", {})
        debugPrint("Joined dungeon")
    end)
end

local function checkBossStatus()
    local gilgamesh = workspace:FindFirstChild("Gilgamesh, the Consumer of Reality")
    local uberBringer = workspace:FindFirstChild("The Supreme Uber Bringer of Light and Space Time Annihilation")
    
    local boss = gilgamesh or uberBringer
    
    if boss then
        State.bossHasSpawned = true
        
        local humanoid = boss:FindFirstChildOfClass("Humanoid")
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

local function farmingLoop()
    debugPrint("Starting farming loop...")
    
    local lastBossCheck = 0
    local bossCheckInterval = 2
    
    while State.isRunning and not State.bossCompleted do
        local now = tick()
        
        -- Update player alive status
        State.playerAlive = isPlayerAlive()
        
        if State.playerAlive then
            -- Check boss status periodically
            if now - lastBossCheck > bossCheckInterval then
                local bossStatus = checkBossStatus()
                
                if State.bossHasSpawned and bossStatus == "dead" and not State.bossCompleted then
                    handleBossCompletion()
                    break
                end
                
                lastBossCheck = now
            end
            
            -- Always try to fire if we have a target
            attemptFire()
        else
            State.currentTarget = nil
        end
        
        RunService.Heartbeat:Wait()
    end
    
    debugPrint("Farming loop ended")
end

local function onCharacterAdded(character)
    debugPrint("Character added")
    task.wait(2)
    
    -- Teleport if needed
    if game.PlaceId == SPECIFIC_PLACE_ID and not State.teleported then
        task.wait(1)
        teleportToPosition()
    end
    
    -- Send skip commands if needed
    if game.PlaceId == SPECIFIC_PLACE_ID and (not State.skipAllSaid or not State.skipSaid) then
        task.spawn(function()
            sendSkipCommands()
        end)
    end
    
    -- Equip tool if farming is active
    if State.isRunning and not State.specialMode and not State.bossCompleted then
        if isPlayerAlive() then
            equipTool()
        end
    end
end

local function initialize()
    debugPrint("Initializing AutoFarm...")
    
    if not player.Character then
        player.CharacterAdded:Wait()
    end
    
    -- Connect character events
    player.CharacterAdded:Connect(onCharacterAdded)
    
    -- Initial setup
    onCharacterAdded(player.Character)
    
    -- Start farming loop
    task.spawn(farmingLoop)
    
    -- Cache cleanup
    task.spawn(function()
        while State.isRunning and not State.bossCompleted do
            task.wait(30)
            cache.workspaceChildren = {}
        end
    end)
end

-- Main execution
task.spawn(function()
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
        debugPrint("Initialization error: " .. tostring(err))
        task.wait(5)
        pcall(initialize)
    end
end)

-- Return API
return {
    Stop = function()
        State.isRunning = false
        debugPrint("AutoFarm stopped")
    end,
    
    Start = function()
        if not State.isRunning then
            State.isRunning = true
            task.spawn(farmingLoop)
            debugPrint("AutoFarm started")
        end
    end,
    
    EquipTool = equipTool,
    
    ForceSkipCommands = function()
        sendSkipCommands()
    end,
    
    TeleportToPosition = function()
        teleportToPosition()
    end,
    
    GetStatus = function()
        return {
            BossSpawned = State.bossHasSpawned,
            BossCompleted = State.bossCompleted,
            CurrentTarget = State.currentTarget and State.currentTarget.Name or "None",
            PlayerAlive = State.playerAlive,
            IsRunning = State.isRunning
        }
    end
}
