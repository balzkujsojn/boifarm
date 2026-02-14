repeat task.wait() until game:IsLoaded()
local Players = game:GetService("Players")
repeat task.wait() until Players.LocalPlayer
local player = Players.LocalPlayer
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")
local CONFIG = {
    FIRE_RATE = 0.05,
    TOOL_NAME = "Equinox Cannon",
    REMOTE_NAME = "RemoteFunction",
    toolEquipCooldown = 3
}
local PRIORITY_ENEMIES = {
    ["The Arbiter"] = true,
    ["Gilgamesh, the Consumer of Reality"] = true,
    ["The Supreme Uber Bringer of Light and Space Time Annihilation"] = true,
    ["Controller Turret"] = true,
    ["Alrasid, Archbishop of the Equinox"] = true
}
local SPECIAL_TARGET_PARTS = {
    ["The Arbiter"] = "HumanoidRootPart"
}
local TELEPORT_POSITION = Vector3.new(-21, 103, -469)
local SPECIFIC_PLACE_ID = 96516249626799
local AUTOTELEPORT_PLACE_ID = 8811271345
local ARBITER_BASE_POSITION = Vector3.new(2170, 14, 1554)
local ARBITER_PLATFORM_OFFSET = Vector3.new(0, 250, 0)
local ARBITER_PLATFORM_SIZE = Vector3.new(10, 2, 10)
local ARBITER_PLATFORM_NAME = "ArbiterTempPlatform"
local State = {
    isRunning = true,
    specialMode = false,
    lastFireTime = 0,
    currentTarget = nil,
    chargeValue = 100,
    bossHasSpawned = false,
    bossCompleted = false,
    alrasidDead = false,
    playerAlive = true,
    skipSaid = false,
    skipAllSaid = false,
    shieldUsed = false,
    lastShieldUse = 0,
    shieldCooldown = 5,
    teleported = false,
    autoTeleportTriggered = false,
    teleportAttempts = 0,
    maxTeleportAttempts = 3,
    shootingEnabled = true,
    shootingErrors = 0,
    maxShootingErrors = 10,
    lastToolEquipTime = 0,
    arbiterPresent = false,
    arbiterForceShoot = false,
    hasTeleportedToArbiterThisSpawn = false,
    arbiterSpawnTime = 0
}
local cache = {
    workspaceChildren = {},
    lastWorkspaceUpdate = 0,
    workspaceUpdateInterval = 0.5
}
local arbiterPlatform = nil
local function createArbiterPlatform()
    if arbiterPlatform then
        arbiterPlatform:Destroy()
        arbiterPlatform = nil
    end
    local part = Instance.new("Part")
    part.Name = ARBITER_PLATFORM_NAME
    part.Size = ARBITER_PLATFORM_SIZE
    part.Position = ARBITER_BASE_POSITION + ARBITER_PLATFORM_OFFSET
    part.Anchored = true
    part.CanCollide = true
    part.Transparency = 1
    part.Color = Color3.new(0, 0, 0)
    part.Material = Enum.Material.Plastic
    part.Parent = workspace
    arbiterPlatform = part
end
local function sendSkipCommands()
    if game.PlaceId ~= SPECIFIC_PLACE_ID then return end
    if State.skipAllSaid and State.skipSaid then return end

    task.spawn(function()
        if not State.skipAllSaid then
            task.wait(0.5)
            pcall(function()
                local args = {[1] = "skipall"}
                local commandsRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Commands")
                if commandsRemote then
                    commandsRemote:FireServer(unpack(args))
                    State.skipAllSaid = true
                end
            end)
        end
    
        task.wait(1)
    
        if not State.skipSaid then
            pcall(function()
                local args = {[1] = "skip"}
                local commandsRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Commands")
                if commandsRemote then
                    commandsRemote:FireServer(unpack(args))
                    State.skipSaid = true
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
local function teleportToArbiterPlatform()
    if game.PlaceId ~= SPECIFIC_PLACE_ID then return end

    local char = player.Character
    if not char then return end

    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    if not arbiterPlatform or not arbiterPlatform.Parent then return end

    local targetCFrame = CFrame.new(arbiterPlatform.Position + Vector3.new(0, (ARBITER_PLATFORM_SIZE.Y / 2) + 3, 0))

    local tweenInfo = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local tween = TweenService:Create(hrp, tweenInfo, {CFrame = targetCFrame})
    tween:Play()
end
local function isPlayerAlive()
    if not player.Character then return false end
    local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end
    return humanoid.Health > 0
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
    if State.autoTeleportTriggered then return false end

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
        if specialPart then return specialPart end
    end

    local possibleParts = {
        "HumanoidRootPart", "Head", "Torso", "UpperTorso",
        "LowerTorso", "Chest", "Body"
    }

    for _, partName in ipairs(possibleParts) do
        local part = model:FindFirstChild(partName)
        if part and part:IsA("BasePart") then return part end
    end

    for _, child in ipairs(model:GetChildren()) do
        if child:IsA("BasePart") then return child end
    end

    return nil
end
local function findEnemies()
    if not State.playerAlive or not State.shootingEnabled then return {} end

    local now = tick()
    local forceRefresh = State.arbiterPresent

    if forceRefresh or (now - cache.lastWorkspaceUpdate > cache.workspaceUpdateInterval) then
        cache.workspaceChildren = workspace:GetChildren()
        cache.lastWorkspaceUpdate = now
    end

    local enemies = {}
    local priorityEnemies = {}
    local hasArbiter = false
    local wasArbiterPresent = State.arbiterPresent
    local arbiterData = nil

    for _, model in ipairs(cache.workspaceChildren) do
        if model:IsA("Model") and model.Parent == workspace then
            local humanoid = model:FindFirstChildOfClass("Humanoid")
        
            if humanoid and humanoid.Health > 0 then
                local isPlayerCharacter = Players:GetPlayerFromCharacter(model) ~= nil
            
                if not isPlayerCharacter then
                    local characterName = model.Name
                    local isPriority = PRIORITY_ENEMIES[characterName] == true
                    local targetPart = getTargetPart(model)
                  
                    if targetPart or isPriority then
                        local enemyData = {
                            Model = model,
                            Humanoid = humanoid,
                            TargetPart = targetPart,
                            Position = targetPart and targetPart.Position or Vector3.new(),
                            Name = characterName,
                            IsPriority = isPriority,
                            LastSeen = now,
                            IsArbiter = characterName == "The Arbiter"
                        }
                     
                        if enemyData.IsArbiter then
                            hasArbiter = true
                            enemyData.IsPriority = true
                            arbiterData = enemyData
                        end
                     
                        if characterName == "Gilgamesh, the Consumer of Reality" or
                           characterName == "The Supreme Uber Bringer of Light and Space Time Annihilation" or
                           characterName == "Alrasid, Archbishop of the Equinox" then
                            State.bossHasSpawned = true
                        end
                     
                        if enemyData.IsPriority then
                            if enemyData.IsArbiter then
                                table.insert(priorityEnemies, 1, enemyData)
                            else
                                table.insert(priorityEnemies, enemyData)
                            end
                        else
                            table.insert(enemies, enemyData)
                        end
                    end
                end
            end
        end
    end

    if hasArbiter and not wasArbiterPresent then
        State.arbiterSpawnTime = tick()
    end

    State.arbiterPresent = hasArbiter

    if hasArbiter then
        createArbiterPlatform()
        local now = tick()
        if State.arbiterSpawnTime > 0 and now - State.arbiterSpawnTime >= 2.5 and not State.hasTeleportedToArbiterThisSpawn then
            State.hasTeleportedToArbiterThisSpawn = true
            task.spawn(teleportToArbiterPlatform)
        end
    end

    if #priorityEnemies > 0 then return priorityEnemies end
    return enemies
end
local function selectTarget()
    if not State.playerAlive or not State.shootingEnabled then return nil end

    local enemies = findEnemies()
    if #enemies == 0 then
        if State.arbiterForceShoot then
            return {IsArbiter = true, Position = ARBITER_BASE_POSITION}
        end
        State.arbiterForceShoot = false
        return nil
    end

    local arbiterEnemy = nil
    for _, enemy in ipairs(enemies) do
        if enemy.IsArbiter then
            arbiterEnemy = enemy
            break
        end
    end
    if arbiterEnemy then
        State.currentTarget = arbiterEnemy
        State.arbiterForceShoot = true
      
        local targetPart = getTargetPart(arbiterEnemy.Model)
        if targetPart then
            arbiterEnemy.TargetPart = targetPart
            arbiterEnemy.Position = targetPart.Position
        else
            arbiterEnemy.Position = ARBITER_BASE_POSITION
        end
        return arbiterEnemy
    end

    if State.currentTarget and State.currentTarget.IsArbiter then
        local arbiterModel = State.currentTarget.Model
        if arbiterModel and arbiterModel.Parent then
            local humanoid = arbiterModel:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.Health > 0 then
                State.arbiterForceShoot = true
                local targetPart = getTargetPart(arbiterModel)
                if targetPart then
                    State.currentTarget.TargetPart = targetPart
                    State.currentTarget.Position = targetPart.Position
                end
                return State.currentTarget
            else
                State.arbiterForceShoot = false
            end
        else
            State.arbiterForceShoot = false
        end
    end

    if State.currentTarget then
        local targetModel = State.currentTarget.Model
        if targetModel and targetModel.Parent then
            local humanoid = targetModel:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.Health > 0 then
                if State.currentTarget.IsPriority then
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

    for _, enemy in ipairs(enemies) do
        local distance = (enemy.Position - playerPos).Magnitude
        if distance < closestDistance then
            closestDistance = distance
            closestEnemy = enemy
        end
    end

    return closestEnemy
end
local function hasTemperature()
    local charModel = workspace:FindFirstChild(player.Name)
    if not charModel then return false end
    local stats = charModel:FindFirstChild("Stats")
    if not stats then return false end
    return stats:FindFirstChild("Temperature") ~= nil
end
local function getValidTool()
    if not State.playerAlive or not State.shootingEnabled then return nil end

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
local function equipTool()
    local now = tick()
    if not State.playerAlive then return false end

    if now - State.lastToolEquipTime < CONFIG.toolEquipCooldown then return false end

    local character = player.Character
    if not character then return false end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end

    local tool = character:FindFirstChild(CONFIG.TOOL_NAME)
    if tool then
        humanoid:EquipTool(tool)
        task.wait(0.5)
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
            task.wait(0.5)
            State.lastToolEquipTime = now
            return true
        end
    end

    return false
end
local function attemptFire()
    if not State.isRunning or State.specialMode or State.bossCompleted then return end
    if not State.playerAlive or not State.shootingEnabled then return end

    local success, targetResult = pcall(function()
        State.currentTarget = selectTarget()
        return State.currentTarget
    end)

    if not success then
        State.shootingErrors = State.shootingErrors + 1
        if State.shootingErrors > State.maxShootingErrors and not State.arbiterPresent then
            State.shootingEnabled = false
            task.wait(5)
            State.shootingEnabled = true
            State.shootingErrors = 0
        end
        return
    end

    local isArbiterForced = State.arbiterForceShoot

    if not targetResult then
        if not isArbiterForced then return end
        targetResult = {IsArbiter = true, Position = ARBITER_BASE_POSITION}
    end

    local now = tick()
    local isArbiterTarget = isArbiterForced or (targetResult and targetResult.IsArbiter)
    if isArbiterTarget and State.arbiterSpawnTime > 0 and now - State.arbiterSpawnTime < 3 then
        return
    end

    if isArbiterForced and not targetResult.IsArbiter then return end

    local isArbiter = isArbiterForced or targetResult.IsArbiter

    local toolData = getValidTool()
    if not toolData then
        equipTool()
        task.wait(0.1)
        toolData = getValidTool()
        if not toolData then
            State.shootingErrors = State.shootingErrors + 1
            return
        end
    end

    if not hasTemperature() then
        equipTool()
        task.wait(0.5)
        if not hasTemperature() then
            State.shootingErrors = State.shootingErrors + 1
            return
        end
    end

    if now - State.lastFireTime < CONFIG.FIRE_RATE then return end
    State.lastFireTime = now

    local targetPos
    if isArbiter then
        targetPos = ARBITER_BASE_POSITION
    else
        local targetPart = targetResult.TargetPart
        if targetPart then
            targetPos = targetPart.Position
        else
            return
        end
    end

    local camera = workspace.CurrentCamera
    if not camera then return end

    local cameraPosition = camera.CFrame.Position
    local direction = (targetPos - cameraPosition).Unit
    local startPos = targetPos - (direction * 5)

    local fireSuccess = pcall(function()
        toolData.Remote:InvokeServer("fire", {startPos, targetPos, State.chargeValue})
    end)

    if not fireSuccess then
        State.shootingErrors = State.shootingErrors + 1
    
        if isArbiter then
            task.wait(0.1)
            pcall(function()
                toolData.Remote:InvokeServer("fire", {targetPos, targetPos, State.chargeValue})
            end)
        end
    
        if State.shootingErrors > State.maxShootingErrors and not State.arbiterPresent then
            State.shootingEnabled = false
            task.wait(3)
            State.shootingEnabled = true
            State.shootingErrors = 0
        end
    else
        State.shootingErrors = 0
    end
end
local function checkTeleportSuccess()
    task.wait(15)
    local teleportState = TeleportService:GetLocalPlayerTeleportState()
    if teleportState == Enum.TeleportState.Failed or teleportState == Enum.TeleportState.None then
        return false
    end
    return true
end
local function attemptDungeonTeleport()
    if State.bossCompleted then return end

    State.bossCompleted = true
    State.specialMode = true
    State.isRunning = false
    State.shootingEnabled = false

    task.wait(2)

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
                if artifact then artifact.Parent = character end
            end
        end
    
        if artifact then
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if humanoid then humanoid:EquipTool(artifact) end
        end
    end

    task.wait(1)

    for attempt = 1, State.maxTeleportAttempts do
        State.teleportAttempts = attempt
    
        local createSuccess = pcall(function()
            local partyRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PartySystem"):WaitForChild("PartyFunction")
            return partyRemote:InvokeServer("createParty", {
                settings = {FriendsOnly = true, Visual = true},
                subplace = "Stronghold"
            })
        end)
    
        if not createSuccess then
            task.wait(1)
            continue
        end
    
        task.wait(1)
    
        local joinSuccess = pcall(function()
            local partyRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PartySystem"):WaitForChild("PartyFunction")
            return partyRemote:InvokeServer("joinSubplace", {})
        end)
    
        if joinSuccess then
            if checkTeleportSuccess() then return true end
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
        State.shootingEnabled = true
        State.arbiterForceShoot = false
        State.alrasidDead = false
    end
end
local function checkBossStatus()
    local gilgamesh = workspace:FindFirstChild("Gilgamesh, the Consumer of Reality")
    local uberBringer = workspace:FindFirstChild("The Supreme Uber Bringer of Light and Space Time Annihilation")
    local alrasid = workspace:FindFirstChild("Alrasid, Archbishop of the Equinox")

    local boss = gilgamesh or uberBringer or alrasid

    if boss then
        State.bossHasSpawned = true
        local humanoid = boss:FindFirstChildOfClass("Humanoid")
        if humanoid then
            if humanoid.Health <= 0 then
                if boss.Name == "Alrasid, Archbishop of the Equinox" and not State.alrasidDead then
                    State.alrasidDead = true
                    task.spawn(function()
                        task.wait(1)
                        if State.alrasidDead and not State.bossCompleted then
                            handleDungeonTeleport()
                        end
                    end)
                    return "alrasid_dead"
                end
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
    local lastBossCheck = 0
    local bossCheckInterval = 2
    local lastRecoveryCheck = 0
    local recoveryCheckInterval = 5

    while State.isRunning and not State.bossCompleted do
        local now = tick()
        State.playerAlive = isPlayerAlive()
    
        if State.playerAlive then
            if checkAutoTeleport() then
                handleDungeonTeleport()
                break
            end
        
            if now - lastBossCheck > bossCheckInterval then
                local bossStatus = checkBossStatus()
                if State.bossHasSpawned and (bossStatus == "dead" or bossStatus == "alrasid_dead") and not State.bossCompleted then
                    if bossStatus ~= "alrasid_dead" then
                        handleDungeonTeleport()
                        break
                    end
                end
                lastBossCheck = now
            end
        
            if now - lastRecoveryCheck > recoveryCheckInterval then
                if State.shootingEnabled and State.isRunning and not State.bossCompleted and State.playerAlive then
                    if tick() - State.lastFireTime > 10 then
                        State.shootingErrors = State.shootingErrors + 2
                    end
                end
                lastRecoveryCheck = now
            end
        
            attemptFire()
        else
            State.currentTarget = nil
            State.arbiterForceShoot = false
        end
    
        RunService.Heartbeat:Wait()
    end
end
local function onCharacterAdded(character)
    State.hasTeleportedToArbiterThisSpawn = false
    State.arbiterSpawnTime = 0
    State.alrasidDead = false
    task.wait(2)

    if game.PlaceId == SPECIFIC_PLACE_ID and not State.teleported then
        task.wait(1)
        teleportToPosition()
    end

    if game.PlaceId == SPECIFIC_PLACE_ID and (not State.skipAllSaid or not State.skipSaid) then
        task.spawn(sendSkipCommands)
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
    while not game:IsLoaded() do task.wait(0.5) end
    while not Players.LocalPlayer do task.wait(0.5) end
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
    end,
    DisableShooting = function() State.shootingEnabled = false end,
    EquipTool = equipTool,
    ForceSkipCommands = sendSkipCommands,
    TeleportToPosition = teleportToPosition,
    GetStatus = function()
        local currentLives = "Not tracked"
        return {
            BossSpawned = State.bossHasSpawned,
            BossCompleted = State.bossCompleted,
            AlrasidDead = State.alrasidDead,
            CurrentTarget = State.currentTarget and State.currentTarget.Name or "None",
            LivesValue = currentLives,
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
            PlatformExists = (arbiterPlatform and arbiterPlatform.Parent) ~= nil
        }
    end,
    TriggerDungeon = function()
        if not State.bossCompleted then handleDungeonTeleport() end
    end,
    ResetShooting = function()
        State.shootingEnabled = true
        State.shootingErrors = 0
        State.lastFireTime = 0
        State.arbiterForceShoot = false
        State.alrasidDead = false
        equipTool()
    end
}
