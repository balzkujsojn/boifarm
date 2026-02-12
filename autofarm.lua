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
    arbiterSpawned = false,
    teleportedToArbiter = false
}

local cache = {
    workspaceChildren = {},
    lastWorkspaceUpdate = 0,
    workspaceUpdateInterval = 0.5
}

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

local function teleportToArbiterPosition()
    if State.teleportedToArbiter then return end
    if game.PlaceId ~= SPECIFIC_PLACE_ID then return end
   
    local char = player.Character
    if not char then return end
   
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
   
    State.teleportedToArbiter = true
   
    local tweenInfo = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local tween = TweenService:Create(hrp, tweenInfo, {CFrame = CFrame.new(ARBITER_TARGET_POSITION)})
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
            return true
        end
       
        if livesNumber > 1 then
            State.livesChecked = false
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
    if now - cache.lastWorkspaceUpdate > cache.workspaceUpdateInterval then
        cache.workspaceChildren = workspace:GetChildren()
        cache.lastWorkspaceUpdate = now
    end
   
    local enemies = {}
    local priorityEnemies = {}
    local hasArbiter = false
   
    for _, model in ipairs(cache.workspaceChildren) do
        if model:IsA("Model") and model.Parent == workspace then
            local humanoid = model:FindFirstChildOfClass("Humanoid")
           
            if humanoid and humanoid.Health > 0 then
                local isPlayerCharacter = false
                local characterName = model.Name
               
                if Players:GetPlayerFromCharacter(model) then
                    isPlayerCharacter = true
                end
               
                if not isPlayerCharacter then
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
                        end
                       
                        if characterName == "Gilgamesh, the Consumer of Reality" or
                           characterName == "The Supreme Uber Bringer of Light and Space Time Annihilation" then
                            State.bossHasSpawned = true
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
   
    State.arbiterPresent = hasArbiter
    if hasArbiter and not State.arbiterSpawned then
        State.arbiterSpawned = true
        task.spawn(teleportToArbiterPosition)
    end
   
    if #priorityEnemies > 0 then return priorityEnemies end
    return enemies
end

local function selectTarget()
    if not State.playerAlive or not State.shootingEnabled then return nil end
   
    local enemies = findEnemies()
    if #enemies == 0 then
        State.arbiterForceShoot = false
        return nil
    end
   
    -- Force The Arbiter as target when present. This fixes the damage bug.
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
            arbiterEnemy.Position = ARBITER_TARGET_POSITION
        end
        return arbiterEnemy
    end
   
    -- Original logic unchanged for all other cases
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
   
    if now - State.lastToolEquipTime < State.toolEquipCooldown then return false end
   
    local character = player.Character
    if not character then return false end
   
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end
   
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

local function attemptFire()
    if not State.isRunning or State.specialMode or State.bossCompleted then return end
    if not State.playerAlive or not State.shootingEnabled then return end
   
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
   
    if not targetResult and not State.arbiterForceShoot then return end
   
    if State.arbiterForceShoot and (not targetResult or not targetResult.IsArbiter) then return end
   
    local isArbiter = State.arbiterForceShoot or (targetResult and targetResult.IsArbiter)
   
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
   
    local now = tick()
    if now - State.lastFireTime < CONFIG.FIRE_RATE then return end
    State.lastFireTime = now
   
    local targetPos
    if isArbiter then
        targetPos = ARBITER_TARGET_POSITION
    else
        local targetPart = targetResult and targetResult.TargetPart
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
                if artifact then artifact.Parent = character end
            end
        end
       
        if artifact then
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if humanoid then humanoid:EquipTool(artifact) end
        end
    end
   
    task.wait(2)
   
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
            task.wait(2)
            continue
        end
       
        task.wait(3)
       
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
        State.livesChecked = false
        State.shootingEnabled = true
        State.arbiterForceShoot = false
    end
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
    local lastBossCheck = 0
    local bossCheckInterval = 2
    local lastRecoveryCheck = 0
    local recoveryCheckInterval = 5
   
    while State.isRunning and not State.bossCompleted do
        local now = tick()
        State.playerAlive = isPlayerAlive()
       
        if State.playerAlive then
            if checkLives() then
                handleDungeonTeleport()
                break
            end
           
            if checkAutoTeleport() then
                handleDungeonTeleport()
                break
            end
           
            if now - lastBossCheck > bossCheckInterval then
                local bossStatus = checkBossStatus()
                if State.bossHasSpawned and bossStatus == "dead" and not State.bossCompleted then
                    handleDungeonTeleport()
                    break
                end
                lastBossCheck = now
            end
           
            if now - lastRecoveryCheck > recoveryCheckInterval then
                if State.shootingEnabled and State.isRunning and not State.bossCompleted and State.playerAlive then
                    if tick() - State.lastFireTime > 10 then
                        State.shootingErrors = State.maxShootingErrors + 1
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
        local livesValue = player:FindFirstChild("Lives")
        local currentLives = "Not found"
        if livesValue and livesValue:IsA("NumberValue") then
            currentLives = tostring(livesValue.Value)
        end
        return {
            BossSpawned = State.bossHasSpawned,
            BossCompleted = State.bossCompleted,
            CurrentTarget = State.currentTarget and State.currentTarget.Name or "None",
            LivesValue = currentLives,
            LivesTriggered = State.livesChecked,
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
            ArbiterForceShoot = State.arbiterForceShoot
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
        equipTool()
    end
}
