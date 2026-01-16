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
    arbiterAlive = false,
    lastArbiterCheck = 0,
    arbiterCheckInterval = 1
}

local cache = {
    workspaceChildren = {},
    lastWorkspaceUpdate = 0,
    workspaceUpdateInterval = 0.5,
    lastPriorityCheck = 0
}

-- Keep all the helper functions the same until findEnemies...

local function checkArbiterStatus()
    local now = tick()
    if now - State.lastArbiterCheck < State.arbiterCheckInterval then
        return State.arbiterAlive
    end
    
    State.lastArbiterCheck = now
    
    local arbiter = workspace:FindFirstChild("The Arbiter")
    if arbiter then
        local humanoid = arbiter:FindFirstChildOfClass("Humanoid")
        if humanoid then
            State.arbiterPresent = true
            State.arbiterAlive = humanoid.Health > 0
            return State.arbiterAlive
        else
            State.arbiterPresent = true
            State.arbiterAlive = true  -- Assume alive if no humanoid found
            return true
        end
    else
        State.arbiterPresent = false
        State.arbiterAlive = false
        return false
    end
end

local function findEnemies()
    if not State.playerAlive or not State.shootingEnabled then 
        return {}
    end
    
    local now = tick()
    
    -- Check Arbiter status first
    local arbiterAlive = checkArbiterStatus()
    
    -- If Arbiter is alive, ONLY return The Arbiter as a target
    if arbiterAlive then
        local arbiter = workspace:FindFirstChild("The Arbiter")
        if arbiter then
            local humanoid = arbiter:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.Health > 0 then
                local arbiterData = {
                    Model = arbiter,
                    Humanoid = humanoid,
                    TargetPart = nil,  -- We don't need a target part for Arbiter
                    Position = ARBITER_TARGET_POSITION,  -- Use fixed position
                    Name = "The Arbiter",
                    IsPriority = true,
                    LastSeen = now,
                    IsArbiter = true
                }
                return {arbiterData}  -- Return ONLY The Arbiter
            end
        end
        return {}  -- Return empty if Arbiter is supposed to be alive but not found
    end
    
    -- Only look for other enemies if Arbiter is NOT alive
    if now - cache.lastWorkspaceUpdate > cache.workspaceUpdateInterval then
        cache.workspaceChildren = workspace:GetChildren()
        cache.lastWorkspaceUpdate = now
    end
    
    local enemies = {}
    local priorityEnemies = {}
    
    for _, model in ipairs(cache.workspaceChildren) do
        if model:IsA("Model") and model.Parent == workspace then
            -- Skip The Arbiter if he's dead or not present
            if model.Name == "The Arbiter" then
                continue
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
                            Name = model.Name,
                            IsPriority = PRIORITY_ENEMIES[model.Name] == true,
                            LastSeen = now,
                            IsArbiter = false
                        }
                        
                        if model.Name == "Gilgamesh, the Consumer of Reality" or 
                           model.Name == "The Supreme Uber Bringer of Light and Space Time Annihilation" then
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
    
    if #priorityEnemies > 0 then
        return priorityEnemies
    end
    
    return enemies
end

local function selectTarget()
    if not State.playerAlive or not State.shootingEnabled then 
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
                -- If current target is The Arbiter, keep it
                if State.currentTarget.Name == "The Arbiter" then
                    return State.currentTarget
                end
                
                -- For other enemies, check if we should keep them
                if not State.arbiterAlive then
                    return State.currentTarget
                end
            end
        end
    end
    
    -- Always return the first enemy in the list
    -- If Arbiter is alive, this will be The Arbiter
    -- If Arbiter is dead, this will be the next priority enemy
    return enemies[1]
end

local function attemptFire()
    if not State.isRunning or State.specialMode or State.bossCompleted then 
        return 
    end
    if not State.playerAlive or not State.shootingEnabled then 
        return 
    end
    
    -- Update Arbiter status
    local arbiterAlive = checkArbiterStatus()
    
    -- Get target
    local success, targetResult = pcall(function()
        State.currentTarget = selectTarget()
        return State.currentTarget
    end)
    
    if not success then
        State.shootingErrors = State.shootingErrors + 1
        if State.shootingErrors > State.maxShootingErrors then
            State.shootingEnabled = false
            task.wait(2)
            State.shootingEnabled = true
            State.shootingErrors = 0
        end
        return
    end
    
    if not targetResult then
        return
    end
    
    -- Check if target is The Arbiter
    local isArbiter = targetResult.Name == "The Arbiter"
    
    -- Verify we're shooting the right target based on Arbiter status
    if arbiterAlive and not isArbiter then
        -- Arbiter is alive but we're not targeting him - something's wrong
        return
    end
    
    if not arbiterAlive and isArbiter then
        -- Arbiter is dead but we're still targeting him - switch targets
        State.currentTarget = nil
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
    if isArbiter then
        -- Always use fixed position for The Arbiter
        targetPos = ARBITER_TARGET_POSITION
    else
        local targetPart = targetResult.TargetPart
        if targetPart then
            targetPos = targetPart.Position
        else
            return
        end
    end
    
    local camera = workspace.CurrentCamera
    if not camera then 
        return 
    end
    
    local cameraPosition = camera.CFrame.Position
    local direction = (targetPos - cameraPosition).Unit
    
    local startPos = targetPos - (direction * 5)
    local endPos = targetPos
    
    -- For Arbiter, try multiple firing methods
    local fireSuccess = false
    if isArbiter then
        -- Method 1: Standard firing
        fireSuccess = pcall(function()
            toolData.Remote:InvokeServer("fire", {startPos, endPos, State.chargeValue})
        end)
        
        -- Method 2: Simple firing if first fails
        if not fireSuccess then
            task.wait(0.01)
            fireSuccess = pcall(function()
                toolData.Remote:InvokeServer("fire", {targetPos, targetPos, State.chargeValue})
            end)
        end
    else
        -- Regular enemy firing
        fireSuccess = pcall(function()
            toolData.Remote:InvokeServer("fire", {startPos, endPos, State.chargeValue})
        end)
    end
    
    if not fireSuccess then
        State.shootingErrors = State.shootingErrors + 1
        
        if State.shootingErrors > State.maxShootingErrors then
            State.shootingEnabled = false
            task.wait(2)
            State.shootingEnabled = true
            State.shootingErrors = 0
        end
    else
        State.shootingErrors = 0
    end
end

-- Keep the rest of the functions the same, but update GetStatus to include arbiterAlive

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
            ArbiterAlive = State.arbiterAlive
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
        equipTool()
    end
}
