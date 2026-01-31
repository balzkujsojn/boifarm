repeat task.wait() until game:IsLoaded()
local Players = game:GetService("Players")
repeat task.wait() until Players.LocalPlayer
local player = Players.LocalPlayer

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")

local CONFIG = {
    FIRE_RATE = 0.05,
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
    autoTeleportTriggered = false,
    teleportAttempts = 0,
    maxTeleportAttempts = 3,
    teleportInProgress = false,
    shootingEnabled = true,
    shootingErrors = 0,
    maxShootingErrors = 10,
    lastToolEquipTime = 0,
    toolEquipCooldown = 2,
    arbiterPresent = false,
    arbiterForceShoot = false,
    dungeonTeleportQueued = false,
    lastArbiterCheck = 0,
    arbiterCheckInterval = 1,
    bossSpawnConfirmed = false,
    lastBossCheck = 0,
    bossCheckCooldown = 5,
    forceKeepShooting = false, -- NEW: Force shooting even when no enemies found
    lastEquipAttempt = 0,
    equipCheckInterval = 3, -- Check tool equip every 3 seconds
    consecutiveNoTargetCount = 0, -- Track how many times no target was found
    maxConsecutiveNoTarget = 10 -- After 10 times with no target, force check for Arbiter
}

local cache = {
    workspaceChildren = {},
    lastWorkspaceUpdate = 0,
    workspaceUpdateInterval = 0.5,
    lastPriorityCheck = 0
}

local function sendSkipCommands()
    if game.PlaceId ~= SPECIFIC_PLACE_ID then return end
    if State.skipAllSaid and State.skipSaid then return end
    
    task.spawn(function()
        if not State.skipAllSaid then
            task.wait(0.5)
            local success = pcall(function()
                local args = {
                    [1] = "skipall"
                }
                local commandsRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Commands")
                if commandsRemote then
                    commandsRemote:FireServer(unpack(args))
                    State.skipAllSaid = true
                    return true
                end
            end)
        end
        
        task.wait(1)
        
        if not State.skipSaid then
            local success = pcall(function()
                local args = {
                    [1] = "skip"
                }
                local commandsRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Commands")
                if commandsRemote then
                    commandsRemote:FireServer(unpack(args))
                    State.skipSaid = true
                    return true
                end
            end)
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

local function checkLives()
    local now = tick()
    if now - State.lastLivesCheck < 2 then
        return false
    end
    
    State.lastLivesCheck = now
    
    local livesValue = player:FindFirstChild("Lives")
    if livesValue and livesValue:IsA("NumberValue") then
        local livesNumber = livesValue.Value
        
        if livesNumber == 1 and not State.livesChecked then
            State.livesChecked = true
            State.dungeonTeleportQueued = true
            return true
        end
        
        if livesNumber > 1 then
            State.livesChecked = false
            State.dungeonTeleportQueued = false
        end
    end
    
    return false
end

local function useShield()
    local now = tick()
    
    if now - State.lastShieldUse < State.shieldCooldown then
        return
    end
    
    local char = player.Character
    if not char then return end
    
    local shield = char:FindFirstChild("Shield")
    if not shield then return end
    
    local remote = shield:FindFirstChild("ShieldRemote")
    if not remote then return end
    
    task.spawn(function()
        pcall(remote.FireServer, remote)
        State.shieldUsed = true
        State.lastShieldUse = now
    end)
end

local function setupHealthMonitoring()
    local char = player.Character
    if not char then return end
    
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    
    humanoid.HealthChanged:Connect(function(health)
        if humanoid.MaxHealth > 0 then
            local healthPercent = (health / humanoid.MaxHealth) * 100
            
            if healthPercent < 50 and not State.shieldUsed and health > 0 then
                useShield()
            elseif healthPercent >= 50 then
                State.shieldUsed = false
            end
        end
    end)
end

local function checkAutoTeleport()
    if State.autoTeleportTriggered then
        return false
    end
    
    if game.PlaceId == AUTOTELEPORT_PLACE_ID then
        State.autoTeleportTriggered = true
        return true
    end
    
    return false
end

local function getTargetPart(model)
    local enemyName = model.Name
    
    if SPECIAL_TARGET_PARTS[enemyName] then
        local specialPart = model:FindFirstChild(SPECIAL_TARGET_PARTS[enemyName])
        if specialPart then
            return specialPart
        end
    end
    
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
    
    for _, child in ipairs(model:GetChildren()) do
        if child:IsA("BasePart") then
            return child
        end
    end
    
    return nil
end

local function checkArbiterInWorkspace()
    local arbiter = workspace:FindFirstChild("The Arbiter")
    if arbiter then
        local humanoid = arbiter:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.Health > 0 then
            return true
        end
    end
    return false
end

local function findEnemies()
    if not State.playerAlive or not State.shootingEnabled then 
        return {}, {}, false, false
    end
    
    local now = tick()
    
    if now - cache.lastWorkspaceUpdate > cache.workspaceUpdateInterval then
        cache.workspaceChildren = workspace:GetChildren()
        cache.lastWorkspaceUpdate = now
    end
    
    local enemies = {}
    local priorityEnemies = {}
    local hasArbiter = false
    local hasBoss = false
    
    for _, model in ipairs(cache.workspaceChildren) do
        if model:IsA("Model") and model.Parent == workspace then
            local enemyName = model.Name
            
            -- Check if this is a boss
            if enemyName == "Gilgamesh, the Consumer of Reality" or 
               enemyName == "The Supreme Uber Bringer of Light and Space Time Annihilation" then
                hasBoss = true
                State.bossSpawnConfirmed = true
            end
            
            local humanoid = model:FindFirstChildOfClass("Humanoid")
            
            if humanoid and humanoid.Health > 0 then
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
                            Name = enemyName,
                            IsPriority = PRIORITY_ENEMIES[enemyName] == true,
                            LastSeen = now,
                            IsArbiter = enemyName == "The Arbiter",
                            IsBoss = enemyName == "Gilgamesh, the Consumer of Reality" or 
                                    enemyName == "The Supreme Uber Bringer of Light and Space Time Annihilation"
                        }
                        
                        if enemyData.IsArbiter then
                            hasArbiter = true
                            enemyData.IsPriority = true
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
    
    -- Always check for Arbiter even if not found in normal search
    if not hasArbiter then
        hasArbiter = checkArbiterInWorkspace()
    end
    
    State.arbiterPresent = hasArbiter
    
    -- Update boss status
    if hasBoss then
        State.bossHasSpawned = true
    elseif State.bossSpawnConfirmed and not hasArbiter then
        State.bossHasSpawned = false
    end
    
    return priorityEnemies, enemies, hasArbiter, hasBoss
end

local function selectTarget()
    if not State.playerAlive or not State.shootingEnabled then 
        return nil
    end
    
    local priorityEnemies, regularEnemies, hasArbiter, hasBoss = findEnemies()
    
    -- Reset no target counter if we found any enemy
    if #priorityEnemies > 0 or #regularEnemies > 0 or hasArbiter then
        State.consecutiveNoTargetCount = 0
    else
        State.consecutiveNoTargetCount = State.consecutiveNoTargetCount + 1
    end
    
    -- Force keep shooting if we've had no targets for a while (Arbiter might be hiding)
    if State.consecutiveNoTargetCount > State.maxConsecutiveNoTarget then
        State.forceKeepShooting = true
    else
        State.forceKeepShooting = false
    end
    
    -- Always prioritize Arbiter if present
    if hasArbiter then
        State.arbiterForceShoot = true
        for _, enemy in ipairs(priorityEnemies) do
            if enemy.IsArbiter then
                return enemy
            end
        end
        -- If Arbiter is in workspace but not in priority list, create dummy target
        return {
            Model = nil,
            Humanoid = nil,
            TargetPart = nil,
            Position = ARBITER_TARGET_POSITION,
            Name = "The Arbiter",
            IsArbiter = true,
            IsPriority = true
        }
    else
        State.arbiterForceShoot = false
    end
    
    -- Use priority enemies if available
    if #priorityEnemies > 0 then
        return priorityEnemies[1]
    end
    
    -- Use regular enemies if available
    if #regularEnemies > 0 then
        local character = player.Character
        if not character then 
            return regularEnemies[1] 
        end
        
        local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
        if not humanoidRootPart then 
            return regularEnemies[1] 
        end
        
        local playerPos = humanoidRootPart.Position
        local closestEnemy = regularEnemies[1]
        local closestDistance = math.huge
        
        for _, enemy in ipairs(regularEnemies) do
            local distance = (enemy.Position - playerPos).Magnitude
            if distance < closestDistance then
                closestDistance = distance
                closestEnemy = enemy
            end
        end
        
        return closestEnemy
    end
    
    return nil
end

local function getValidTool()
    if not State.playerAlive or not State.shootingEnabled then 
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
    local now = tick()
    
    if not State.playerAlive then 
        task.wait(0.5)
        return false
    end
    
    if now - State.lastToolEquipTime < State.toolEquipCooldown then
        return false
    end
    
    local character = player.Character
    if not character then 
        task.wait(0.5)
        return false
    end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then 
        task.wait(0.5)
        return false
    end
    
    local tool = character:FindFirstChild(CONFIG.TOOL_NAME)
    if tool then
        humanoid:EquipTool(tool)
        State.lastToolEquipTime = now
        return true
    end
    
    local backpack = player:FindFirstChild("Backpack")
    if backpack then
        tool = backpack:FindFirstChild(CONFIG.TOOL_NAME)
        if tool then
            tool.Parent = character
            task.wait(0.1)
            humanoid:EquipTool(tool)
            State.lastToolEquipTime = now
            return true
        end
    end
    
    return false
end

local function forceEquipCheck()
    local now = tick()
    if now - State.lastEquipAttempt < State.equipCheckInterval then
        return
    end
    
    State.lastEquipAttempt = now
    
    -- Force check if tool is equipped
    local toolData = getValidTool()
    if not toolData then
        equipTool()
    else
        -- Check if tool is actually equipped
        local character = player.Character
        if character then
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if humanoid then
                local equippedTool = humanoid:GetEquippedTool()
                if not equippedTool or equippedTool.Name ~= CONFIG.TOOL_NAME then
                    humanoid:EquipTool(toolData.Tool)
                end
            end
        end
    end
end

local function attemptFire()
    if not State.isRunning or State.specialMode or State.bossCompleted then 
        return 
    end
    if not State.playerAlive or not State.shootingEnabled then 
        return 
    end
    
    -- Force equip check if we haven't shot in a while
    if tick() - State.lastFireTime > 3 then
        forceEquipCheck()
    end
    
    local success, targetResult = pcall(function()
        State.currentTarget = selectTarget()
        return State.currentTarget
    end)
    
    if not success then
        State.shootingErrors = State.shootingErrors + 1
        if State.shootingErrors > State.maxShootingErrors then
            State.shootingEnabled = false
            task.wait(5)
            State.shootingEnabled = true
            State.shootingErrors = 0
        end
        return
    end
    

    if State.arbiterPresent or State.forceKeepShoot or (State.bossSpawnConfirmed and not State.bossCompleted) then
    elseif not targetResult and not State.arbiterForceShoot then
        return
    end
    
    local toolData
    local toolSuccess, toolResult = pcall(function()
        toolData = getValidTool()
        return toolData
    end)
    
    if not toolSuccess then
        State.shootingErrors = State.shootingErrors + 1
        return
    end
    
    if not toolResult then 
        local equipSuccess, equipResult = pcall(function()
            return equipTool()
        end)
        
        if not equipSuccess then
            State.shootingErrors = State.shootingErrors + 1
            return
        end
        
        if not equipResult then 
            return 
        end
        
        local toolRetrySuccess, toolRetryResult = pcall(function()
            toolData = getValidTool()
            return toolData
        end)
        
        if not toolRetrySuccess or not toolRetryResult then 
            return 
        end
        
        toolData = toolRetryResult
    end
    
    local now = tick()
    if now - State.lastFireTime < CONFIG.FIRE_RATE then 
        return 
    end
    
    State.lastFireTime = now
    
    local targetPos
    if State.arbiterForceShoot then
        targetPos = ARBITER_TARGET_POSITION
    elseif targetResult and targetResult.TargetPart then
        targetPos = targetResult.TargetPart.Position
    elseif targetResult and targetResult.Position then
        targetPos = targetResult.Position
    elseif State.arbiterPresent then
        targetPos = ARBITER_TARGET_POSITION
    elseif State.forceKeepShoot then
        -- Shoot in a random direction to keep farming active
        targetPos = Vector3.new(
            math.random(-100, 100),
            math.random(10, 50),
            math.random(-100, 100)
        )
    else
        return
    end
    
    local camera = workspace.CurrentCamera
    if not camera then 
        return 
    end
    
    local cameraPosition = camera.CFrame.Position
    local direction = (targetPos - cameraPosition).Unit
    
    local startPos = targetPos - (direction * 5)
    local endPos = targetPos
    
    local fireSuccess = pcall(function()
        toolData.Remote:InvokeServer("fire", {startPos, endPos, State.chargeValue})
    end)
    
    if not fireSuccess then
        State.shootingErrors = State.shootingErrors + 1
        
        if State.arbiterPresent then
            task.wait(0.1)
            pcall(function()
                toolData.Remote:InvokeServer("fire", {targetPos, targetPos, State.chargeValue})
            end)
        end
        
        if State.shootingErrors > State.maxShootingErrors then
            State.shootingEnabled = false
            task.wait(3)
            State.shootingEnabled = true
            State.shootingErrors = 0
        end
    else
        State.shootingErrors = 0
    end
end

local function checkTeleportState()
    local teleportState = TeleportService:GetLocalPlayerTeleportState()
    return teleportState == Enum.TeleportState.RequestedFromServer or 
           teleportState == Enum.TeleportState.InProgress or 
           teleportState == Enum.TeleportState.Started
end

local function checkTeleportSuccess()
    task.wait(15)
    
    local teleportState = TeleportService:GetLocalPlayerTeleportState()
    
    if teleportState == Enum.TeleportState.Failed or 
       teleportState == Enum.TeleportState.None then
        return false
    end
    
    return true
end

local function checkBossCompletelyGone()
    local now = tick()
    if now - State.lastBossCheck < State.bossCheckCooldown then
        return false
    end
    
    State.lastBossCheck = now
    
    local gilgamesh = workspace:FindFirstChild("Gilgamesh, the Consumer of Reality")
    local uberBringer = workspace:FindFirstChild("The Supreme Uber Bringer of Light and Space Time Annihilation")
    local arbiter = workspace:FindFirstChild("The Arbiter")
    
    if State.bossSpawnConfirmed and not gilgamesh and not uberBringer and not arbiter then
        return true
    end
    
    return false
end

local function attemptDungeonTeleport()
    if State.bossCompleted then 
        return 
    end
    
    State.bossCompleted = true
    State.specialMode = true
    State.isRunning = false
    State.shootingEnabled = false
    
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
    
    for attempt = 1, State.maxTeleportAttempts do
        State.teleportAttempts = attempt
        
        local createSuccess = pcall(function()
            local partyRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PartySystem"):WaitForChild("PartyFunction")
            return partyRemote:InvokeServer("createParty", {
                settings = {
                    FriendsOnly = true,
                    Visual = true
                },
                subplace = "Stronghold"
            })
        end)
        
        if not createSuccess then
            task.wait(2)
            continue
        end
        
        task.wait(3)
        
        local joinSuccess = pcall(function()
            local partyRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PartySystem"):WaitForChild("PartyFunction")
            return partyRemote:InvokeServer("joinSubplace", {})
        end)
        
        if joinSuccess then
            local teleportSuccessful = checkTeleportSuccess()
            if teleportSuccessful then
                return true
            end
        end
        
        if attempt < State.maxTeleportAttempts then
            task.wait(10)
        end
    end
    
    return false
end

local function handleDungeonTeleport()
    local success = attemptDungeonTeleport()
    
    if not success then
        State.bossCompleted = false
        State.specialMode = false
        State.isRunning = true
        State.livesChecked = false
        State.dungeonTeleportQueued = false
        State.shootingEnabled = true
        State.arbiterForceShoot = false
        State.forceKeepShooting = false
        State.consecutiveNoTargetCount = 0
    end
end

local function shootingRecoveryCheck()
    local lastShotTime = State.lastFireTime
    local currentTime = tick()
    
    if State.shootingEnabled and State.isRunning and not State.bossCompleted and State.playerAlive then
        if currentTime - lastShotTime > 10 then
            State.shootingErrors = State.maxShootingErrors + 1
            forceEquipCheck()
        end
    end
end

local function farmingLoop()
    local lastRecoveryCheck = 0
    local recoveryCheckInterval = 5
    local lastForceEquipCheck = 0
    local forceEquipCheckInterval = 3
    
    while State.isRunning and not State.bossCompleted do
        local now = tick()
        
        State.playerAlive = isPlayerAlive()
        
        if State.playerAlive then
            checkLives()
            
            -- Force equip check periodically
            if now - lastForceEquipCheck > forceEquipCheckInterval then
                forceEquipCheck()
                lastForceEquipCheck = now
            end
            
            -- Check if we should teleport
            if State.dungeonTeleportQueued and not State.arbiterPresent then
                handleDungeonTeleport()
                break
            end
            
            if checkAutoTeleport() then
                handleDungeonTeleport()
                break
            end
            
            if checkBossCompletelyGone() and not State.arbiterPresent then
                handleDungeonTeleport()
                break
            end
            
            if now - lastRecoveryCheck > recoveryCheckInterval then
                shootingRecoveryCheck()
                lastRecoveryCheck = now
            end
            
            -- ALWAYS attempt to fire, even if no enemies found
            attemptFire()
        else
            State.currentTarget = nil
            State.arbiterForceShoot = false
        end
        
        RunService.Heartbeat:Wait()
    end
end

local function onCharacterAdded(character)
    task.wait(2)
    
    if game.PlaceId == SPECIFIC_PLACE_ID and not State.teleported then
        task.wait(1)
        teleportToPosition()
    end
    
    if game.PlaceId == SPECIFIC_PLACE_ID and (not State.skipAllSaid or not State.skipSaid) then
        task.spawn(function()
            sendSkipCommands()
        end)
    end
    
    if State.isRunning and not State.specialMode and not State.bossCompleted then
        if isPlayerAlive() then
            equipTool()
        end
    end
    
    setupHealthMonitoring()
    
    State.shootingEnabled = true
    State.shootingErrors = 0
    State.arbiterPresent = false
    State.arbiterForceShoot = false
    State.dungeonTeleportQueued = false
    State.forceKeepShooting = false
    State.consecutiveNoTargetCount = 0
end

local function initialize()
    if not player.Character then
        player.CharacterAdded:Wait()
    end
    
    player.CharacterAdded:Connect(onCharacterAdded)
    
    onCharacterAdded(player.Character)
    
    task.spawn(farmingLoop)
    
    task.spawn(function()
        while State.isRunning and not State.bossCompleted do
            task.wait(30)
            cache.workspaceChildren = {}
        end
    end)
end

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
        task.wait(5)
        pcall(initialize)
    end
end)

return {
    Stop = function()
        State.isRunning = false
        State.shootingEnabled = false
    end,
    
    Start = function()
        if not State.isRunning then
            State.isRunning = true
            State.shootingEnabled = true
            task.spawn(farmingLoop)
        end
    end,
    
    EnableShooting = function()
        State.shootingEnabled = true
        State.shootingErrors = 0
        State.forceKeepShooting = true -- Force shooting when re-enabled
    end,
    
    DisableShooting = function()
        State.shootingEnabled = false
    end,
    
    EquipTool = equipTool,
    
    ForceSkipCommands = function()
        sendSkipCommands()
    end,
    
    TeleportToPosition = function()
        teleportToPosition()
    end,
    
    GetStatus = function()
        local livesValue = player:FindFirstChild("Lives")
        local currentLives = "Not found"
        if livesValue and livesValue:IsA("NumberValue") then
            currentLives = tostring(livesValue.Value)
        end
        
        return {
            BossSpawned = State.bossHasSpawned,
            BossSpawnConfirmed = State.bossSpawnConfirmed,
            BossCompleted = State.bossCompleted,
            CurrentTarget = State.currentTarget and State.currentTarget.Name or "None",
            LivesValue = currentLives,
            LivesTriggered = State.livesChecked,
            DungeonTeleportQueued = State.dungeonTeleportQueued,
            AutoTeleportTriggered = State.autoTeleportTriggered,
            CurrentPlaceId = game.PlaceId,
            PlayerAlive = State.playerAlive,
            TeleportAttempts = State.teleportAttempts,
            TeleportState = TeleportService:GetLocalPlayerTeleportState(),
            ShieldUsed = State.shieldUsed,
            ShootingEnabled = State.shootingEnabled,
            ShootingErrors = State.shootingErrors,
            LastShotTime = State.lastFireTime,
            TimeSinceLastShot = tick() - State.lastFireTime,
            ArbiterPresent = State.arbiterPresent,
            ArbiterForceShoot = State.arbiterForceShoot,
            ForceKeepShooting = State.forceKeepShooting,
            ConsecutiveNoTargetCount = State.consecutiveNoTargetCount,
            ToolEquipped = getValidTool() ~= nil
        }
    end,
    
    TriggerDungeon = function()
        if not State.bossCompleted then
            handleDungeonTeleport()
        end
    end,
    
    ResetShooting = function()
        State.shootingEnabled = true
        State.shootingErrors = 0
        State.lastFireTime = 0
        State.arbiterForceShoot = false
        State.forceKeepShooting = true
        State.consecutiveNoTargetCount = 0
        equipTool()
    end,
    
    ForceEquip = function()
        forceEquipCheck()
    end
}

