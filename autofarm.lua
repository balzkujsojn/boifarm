repeat task.wait() until game:IsLoaded()
local Players = game:GetService("Players")
repeat task.wait() until Players.LocalPlayer
local player = Players.LocalPlayer

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")

local CONFIG = {
    FIRE_RATE = 0.05,
    TOOL_NAME = "Equinox Cannon",
    REMOTE_NAME = "RemoteFunction",
    LIVES_CHECK_INTERVAL = 5
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
    workspaceUpdateInterval = 1,
    lastPriorityCheck = 0
}

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

local function isPlayerAlive()
    if not player.Character then return false end
    
    local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end
    
    return humanoid.Health > 0
end

local function checkLives()
    local now = tick()
    if now - State.lastLivesCheck < CONFIG.LIVES_CHECK_INTERVAL then
        return false
    end
    
    State.lastLivesCheck = now
    
    local livesValue = player:FindFirstChild("Lives")
    if livesValue and livesValue:IsA("StringValue") then
        local livesText = livesValue.Value
        local livesNumber = tonumber(livesText)
        
        if livesNumber == 1 and not State.livesChecked then
            State.livesChecked = true
            return true
        end
    end
    
    return false
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

local function setupHealthMonitoring()
    local char = player.Character
    if not char then return end
    
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    
    local maxHealth = humanoid.MaxHealth
    
    humanoid.HealthChanged:Connect(function(currentHealth)
        if currentHealth > 0 and maxHealth > 0 then
            local healthPercent = (currentHealth / maxHealth) * 100
            
            if healthPercent < 50 and not State.shieldUsed then
                useShield()
            elseif healthPercent >= 50 then
                State.shieldUsed = false
            end
        end
    end)
end

local function setupDeathMonitoring()
    local char = player.Character
    if not char then return end
    
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    
    humanoid.HealthChanged:Connect(function(health)
        local wasAlive = State.playerAlive
        State.playerAlive = health > 0
        
        if health <= 0 and wasAlive then
            State.currentTarget = nil
            State.shieldUsed = false
        elseif health > 0 and not wasAlive then
            task.wait(1.5)
            if State.isRunning and not State.specialMode and not State.bossCompleted then
                equipTool()
                cache.lastPriorityCheck = 0
                State.shieldUsed = false
            end
        end
    end)
    
    State.playerAlive = humanoid.Health > 0
end

local function getTargetPart(model)
    local enemyName = model.Name
    
    if SPECIAL_TARGET_PARTS[enemyName] then
        local specialPart = model:FindFirstChild(SPECIAL_TARGET_PARTS[enemyName])
        if specialPart then
            return specialPart
        end
    end
    
    return model:FindFirstChild("HumanoidRootPart") or 
           model:FindFirstChild("Torso") or 
           model:FindFirstChild("UpperTorso") or
           model:FindFirstChild("Head") or
           model:FindFirstChild("Chest")
end

local function findEnemies()
    if not State.playerAlive then return {} end
    
    local now = tick()
    local forceUpdate = false
    
    if now - cache.lastPriorityCheck > 0.5 then
        forceUpdate = true
        cache.lastPriorityCheck = now
    end
    
    if forceUpdate or now - cache.lastWorkspaceUpdate > cache.workspaceUpdateInterval then
        cache.workspaceChildren = workspace:GetChildren()
        cache.lastWorkspaceUpdate = now
    end
    
    local enemies = {}
    local priorityEnemies = {}
    
    for _, model in ipairs(cache.workspaceChildren) do
        if model:IsA("Model") and model.Parent == workspace then
            local enemyMain = model:FindFirstChild("EnemyMain")
            local humanoid = model:FindFirstChildOfClass("Humanoid")
            
            if enemyMain and humanoid and humanoid.Health > 0 then
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
    
    if #priorityEnemies > 0 then
        return priorityEnemies
    end
    
    return enemies
end

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

local function attemptFire()
    if not State.isRunning or State.specialMode or State.bossCompleted then return end
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
    
    local now = tick()
    if now - State.lastFireTime < CONFIG.FIRE_RATE then return end
    
    State.lastFireTime = now
    
    local targetPart = State.currentTarget.TargetPart
    local targetPos = targetPart.Position
    
    local camera = workspace.CurrentCamera
    if not camera then return end
    
    local cameraPosition = camera.CFrame.Position
    local cameraToTarget = (targetPos - cameraPosition).Unit
    
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

local function handleBossCompletion()
    if State.bossCompleted then return end
    State.bossCompleted = true
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
    local heartbeat = RunService.Heartbeat
    local lastEnemyCheck = 0
    local enemyCheckInterval = 0.3
    local lastBossCheck = 0
    local bossCheckInterval = 1
    
    while State.isRunning and not State.bossCompleted do
        local now = tick()
        
        State.playerAlive = isPlayerAlive()
        
        if State.playerAlive then
            if checkAutoTeleport() then
                handleBossCompletion()
                break
            end
            
            if checkLives() then
                handleBossCompletion()
                break
            end
            
            if now - lastBossCheck > bossCheckInterval then
                local bossStatus = checkBossStatus()
                
                if State.bossHasSpawned and bossStatus == "dead" and not State.bossCompleted then
                    handleBossCompletion()
                    break
                end
                
                lastBossCheck = now
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

local function onCharacterAdded(character)
    task.wait(2)
    
    setupDeathMonitoring()
    setupHealthMonitoring()
    
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
            cache.lastPriorityCheck = 0
        end
    end
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
            task.wait(60)
            cache.workspaceChildren = {}
        end
    end)
end

local function safeStart()
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

task.spawn(safeStart)

return {
    Stop = function()
        State.isRunning = false
    end,
    
    Start = function()
        if not State.isRunning then
            State.isRunning = true
            task.spawn(farmingLoop)
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
        local livesValue = player:FindFirstChild("Lives")
        local currentLives = "Not found"
        if livesValue and livesValue:IsA("StringValue") then
            currentLives = livesValue.Value
        end
        
        return {
            BossSpawned = State.bossHasSpawned,
            BossCompleted = State.bossCompleted,
            CurrentTarget = State.currentTarget and State.currentTarget.Name or "None",
            LivesValue = currentLives,
            LivesTriggered = State.livesChecked,
            AutoTeleportTriggered = State.autoTeleportTriggered,
            CurrentPlaceId = game.PlaceId,
            PlayerAlive = State.playerAlive
        }
    end,
    
    TriggerDungeon = function()
        if not State.bossCompleted then
            handleBossCompletion()
        end
    end
}
