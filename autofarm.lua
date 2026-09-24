repeat task.wait() until game:IsLoaded()
local Players = game:GetService("Players")
repeat task.wait() until Players.LocalPlayer
local player = Players.LocalPlayer
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local TextChatService = game:GetService("TextChatService")
local HttpService = game:GetService("HttpService")
local CONFIG = {
    FIRE_RATE = 0.05,
    TOOL_NAME = "Equinox Cannon",
    REMOTE_NAME = "RemoteFunction",
    toolEquipCooldown = 3,
    TARGET_REFRESH_INTERVAL = 0.05,
    TELEPORT_TIMEOUT = 5,
    TELEPORT_RETRY_DELAY = 1,
    ARBITER_SURFACE_BUFFER = 1,
    START_POSITION_CHECK_INTERVAL = 0.15,
    START_POSITION_TOLERANCE = 8,
    LIVES_SCAN_INTERVAL = 0.1,
    WAIT_FOR_GILGAMESH_AFTER_ALRASID = true,
    GILGAMESH_NAME = "Gilgamesh, the Consumer of Reality",
    DUMMY_TOOL_NAME = "Simulation Dummy",
    DUMMY_MODEL_NAME = "SimulationDummy",
    DUMMY_REMOTE_NAME = "RemoteFunction",
    DUMMY_SPAWN_TIMEOUT = 3,
    DUMMY_SHIELD_TIMEOUT = 3,
    DUMMY_SHIELD_DELAY = 0.1,
    DUMMY_SETUP_RETRY_DELAY = 1,
    DUMMY_POSITION_SETTLE_TIME = 0.3,
    GIGATON_TOOL_NAME = "Gigaton Hammer",
    GIGATON_REMOTE_NAME = "RemoteFunction",
    GIGATON_INTERVAL = 1,
    WEBHOOK_URL = "",
    LOOT_CHAT_DELAY = 2,
    LOOT_GUI_SCAN_INTERVAL = 0.5,
    LOOT_DUPLICATE_WINDOW = 2,
    LOOT_MIN_TEXT_LENGTH = 5
}
local PRIORITY_ENEMIES = {
    ["The Arbiter"] = true,
    ["Gilgamesh, the Consumer of Reality"] = true,
    ["The Supreme Uber Bringer of Light and Space Time Annihilation"] = true,
    ["Controller Turret"] = true,
    ["Alrasid, Archbishop of the Equinox"] = true
}
local IGNORE_ENEMIES = {
    ["SimulationDummy"] = true
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
    currentTargetName = "None",
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
    arbiterSpawnTime = 0,
    lifeTeleportTriggered = false,
    dummySetupStarted = false,
    dummySetupCompleted = false,
    dummyShieldEnabled = false,
    dummyContext = nil,
    lastDummySetupAttempt = 0,
    gigatonLoopStarted = false,
    gigatonEnabled = false,
    startPositionReady = false,
    startPositionStableSince = nil
}
local cache = {
    enemyModels = {},
    enemyIndex = {},
    enemyData = {},
    lastTargetUpdate = 0,
    lastEnemyScan = 0,
    toolData = nil,
    toolCharacter = nil,
    humanoid = nil,
    temperatureFolder = nil,
    temperatureValue = nil,
    partyRemote = nil,
    livesObject = nil,
    lastLivesScan = 0,
    lastLivesValue = nil,
    lastStartPositionCheck = 0,
    simulationDummy = nil,
    dummyTool = nil,
    dummyPlaceRemote = nil,
    dummyShieldRemote = nil,
    gigatonRemote = nil
}
local arbiterPlatform = nil
local arbiterSpawnConnection = nil
local workspaceChildAddedConnection = nil
local workspaceChildRemovedConnection = nil
local playerChildAddedConnection = nil
local characterHealthConnection = nil
local teleportToArbiterPlatform
local lootConnections = {}
local lootRecentMessages = {}
local lootMonitorStarted = false

local function trimText(text)
    if type(text) ~= "string" then
        return nil
    end

    text = text:gsub("%[SERVER%]:%s*", "")
    text = text:gsub("^%s*(.-)%s*$", "%1")
    return text
end

local function extractObtainedItem(text)
    text = trimText(text)
    if not text or #text < CONFIG.LOOT_MIN_TEXT_LENGTH then
        return nil
    end

    local lowered = string.lower(text)
    local names = {player.Name}

    if player.DisplayName and player.DisplayName ~= player.Name then
        names[#names + 1] = player.DisplayName
    end

    for _, name in ipairs(names) do
        local loweredName = string.lower(name)
        local markers = {
            loweredName .. " has obtained ",
            '"' .. loweredName .. '" has obtained '
        }

        for _, marker in ipairs(markers) do
            local startIndex, endIndex = lowered:find(marker, 1, true)

            if startIndex then
                local item = text:sub(endIndex + 1)
                item = item:gsub("^%s+", "")
                item = item:gsub("^[Aa][Nn]?%s+", "")
                item = item:gsub('^"', "")
                item = item:gsub('"[%s%!%.]*$', "")
                item = item:gsub("[%s%!%.]+$", "")

                if item ~= "" then
                    return item
                end
            end
        end
    end

    return nil
end

local function getWebhookRequestFunction()
    if typeof(request) == "function" then
        return request
    end

    if typeof(http_request) == "function" then
        return http_request
    end

    if syn and typeof(syn.request) == "function" then
        return syn.request
    end

    if http and typeof(http.request) == "function" then
        return http.request
    end

    if fluxus and typeof(fluxus.request) == "function" then
        return fluxus.request
    end

    return nil
end

local function sendLootWebhook(itemName)
    if type(CONFIG.WEBHOOK_URL) ~= "string" or CONFIG.WEBHOOK_URL == "" then
        return false
    end

    local payload = HttpService:JSONEncode({
        content = "@everyone " .. player.Name .. " has obtained " .. itemName,
        allowed_mentions = {
            parse = {"everyone"}
        }
    })

    local requestFunction = getWebhookRequestFunction()

    if requestFunction then
        local success = pcall(function()
            requestFunction({
                Url = CONFIG.WEBHOOK_URL,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = payload
            })
        end)

        if success then
            return true
        end
    end

    local success = pcall(function()
        HttpService:PostAsync(
            CONFIG.WEBHOOK_URL,
            payload,
            Enum.HttpContentType.ApplicationJson,
            false
        )
    end)

    return success
end

local function processLootMessage(message)
    local itemName = extractObtainedItem(message)
    if not itemName then
        return false
    end

    local normalized = string.lower(trimText(message) or message)
    local now = os.clock()
    local lastProcessed = lootRecentMessages[normalized]

    if lastProcessed and now - lastProcessed < CONFIG.LOOT_DUPLICATE_WINDOW then
        return false
    end

    lootRecentMessages[normalized] = now

    task.spawn(function()
        sendLootWebhook(itemName)
    end)

    return true
end

local function connectLootTextChannel(channel)
    if not channel or not channel:IsA("TextChannel") then
        return
    end

    local connection = channel.MessageReceived:Connect(function(message)
        if message then
            processLootMessage(message.Text)
        end
    end)

    lootConnections[#lootConnections + 1] = connection
end

local function startLootMonitor()
    if lootMonitorStarted then
        return
    end

    lootMonitorStarted = true

    task.spawn(function()
        task.wait(CONFIG.LOOT_CHAT_DELAY)

        local textChannels = TextChatService:FindFirstChild("TextChannels")

        if textChannels then
            for _, channel in ipairs(textChannels:GetChildren()) do
                connectLootTextChannel(channel)
            end

            local connection = textChannels.ChildAdded:Connect(function(channel)
                connectLootTextChannel(channel)
            end)

            lootConnections[#lootConnections + 1] = connection
        end
    end)

    task.spawn(function()
        task.wait(CONFIG.LOOT_CHAT_DELAY)

        local playerGui = player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui", 10)
        if not playerGui then
            return
        end

        local seenTexts = {}

        while lootMonitorStarted do
            for _, descendant in ipairs(playerGui:GetDescendants()) do
                if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
                    if descendant.Visible then
                        local text = descendant.Text

                        if type(text) == "string" and #text >= CONFIG.LOOT_MIN_TEXT_LENGTH then
                            local oldText = seenTexts[descendant]

                            if oldText ~= text then
                                seenTexts[descendant] = text
                                processLootMessage(text)
                            end
                        end
                    end
                end
            end

            task.wait(CONFIG.LOOT_GUI_SCAN_INTERVAL)
        end
    end)
end

local function stopLootMonitor()
    lootMonitorStarted = false

    for _, connection in ipairs(lootConnections) do
        if connection and connection.Connected then
            connection:Disconnect()
        end
    end

    table.clear(lootConnections)
    table.clear(lootRecentMessages)
end
local function createArbiterPlatform()
    if arbiterPlatform and arbiterPlatform.Parent then return end
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
local function isBossName(name)
    return name == "Gilgamesh, the Consumer of Reality"
        or name == "The Supreme Uber Bringer of Light and Space Time Annihilation"
        or name == "Alrasid, Archbishop of the Equinox"
end

local function refreshCharacterCache(character)
    cache.humanoid = character and character:FindFirstChildOfClass("Humanoid") or nil
    cache.toolData = nil
    cache.toolCharacter = character

    local stats = character and character:FindFirstChild("Stats")
    cache.temperatureFolder = stats
    cache.temperatureValue = stats and stats:FindFirstChild("Temperature") or nil
end

local function getCachedHumanoid()
    local character = player.Character

    if character ~= cache.toolCharacter then
        refreshCharacterCache(character)
    end

    if cache.humanoid and cache.humanoid.Parent then
        return cache.humanoid
    end

    if character then
        cache.humanoid = character:FindFirstChildOfClass("Humanoid")
    end

    return cache.humanoid
end

local function getOrFindTemperature()
    local character = player.Character
    if not character then
        return nil
    end

    if character ~= cache.toolCharacter then
        refreshCharacterCache(character)
    end

    if cache.temperatureValue and cache.temperatureValue.Parent then
        return cache.temperatureValue
    end

    local stats = cache.temperatureFolder

    if not stats or not stats.Parent then
        stats = character:FindFirstChild("Stats")
        cache.temperatureFolder = stats
    end

    if stats then
        cache.temperatureValue = stats:FindFirstChild("Temperature")
    end

    return cache.temperatureValue
end

local function isValidEnemyData(data)
    if not data then
        return false
    end

    local model = data.Model
    local humanoid = data.Humanoid

    return model
        and model.Parent == workspace
        and humanoid
        and humanoid.Parent
        and humanoid.Health > 0
end

local function removeEnemyModel(model)
    local index = cache.enemyIndex[model]
    if not index then
        return
    end

    local lastIndex = #cache.enemyModels
    local lastModel = cache.enemyModels[lastIndex]

    if index ~= lastIndex then
        cache.enemyModels[index] = lastModel
        cache.enemyIndex[lastModel] = index
    end

    cache.enemyModels[lastIndex] = nil
    cache.enemyIndex[model] = nil
    cache.enemyData[model] = nil

    if State.currentTarget and State.currentTarget.Model == model then
        State.currentTarget = nil
        State.currentTargetName = "None"
    end

    if model.Name == "The Arbiter" then
        State.arbiterPresent = false
        State.arbiterForceShoot = false
    end
end

local function registerEnemyModel(model)
    if not model:IsA("Model") or model.Parent ~= workspace then
        return
    end

    if IGNORE_ENEMIES[model.Name] then
        return
    end

    if cache.enemyIndex[model] then
        return
    end

    if Players:GetPlayerFromCharacter(model) then
        return
    end

    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        task.delay(0.1, function()
            if model.Parent == workspace and not cache.enemyIndex[model] then
                registerEnemyModel(model)
            end
        end)
        return
    end

    local name = model.Name
    local isArbiter = name == "The Arbiter"

    local data = {
        Model = model,
        Humanoid = humanoid,
        TargetPart = nil,
        Position = Vector3.new(),
        Name = name,
        IsPriority = PRIORITY_ENEMIES[name] == true or isArbiter,
        IsArbiter = isArbiter
    }

    cache.enemyModels[#cache.enemyModels + 1] = model
    cache.enemyIndex[model] = #cache.enemyModels
    cache.enemyData[model] = data

    if isBossName(name) then
        State.bossHasSpawned = true
    end

    if isArbiter then
        State.arbiterPresent = true
        State.arbiterForceShoot = true
        State.currentTarget = data
        State.currentTargetName = data.Name

        if State.arbiterSpawnTime <= 0 then
            State.arbiterSpawnTime = tick()
        end

        createArbiterPlatform()

        if not State.hasTeleportedToArbiterThisSpawn then
            task.spawn(function()
                task.wait(2.5)

                if cache.enemyIndex[model]
                    and model.Parent == workspace
                    and not State.hasTeleportedToArbiterThisSpawn then

                    State.hasTeleportedToArbiterThisSpawn = true
                    if teleportToArbiterPlatform then
                        teleportToArbiterPlatform()
                    end
                end
            end)
        end
    end
end

local function refreshEnemyModels(force)
    local now = tick()

    if not force and now - cache.lastEnemyScan < 1 then
        return
    end

    cache.lastEnemyScan = now

    for _, child in ipairs(workspace:GetChildren()) do
        if child:IsA("Model") and not cache.enemyIndex[child] then
            registerEnemyModel(child)
        end
    end

    for i = #cache.enemyModels, 1, -1 do
        local model = cache.enemyModels[i]

        if model.Parent ~= workspace then
            removeEnemyModel(model)
        end
    end
end

local function getGilgameshModel()
    local model = workspace:FindFirstChild(CONFIG.GILGAMESH_NAME)

    if model and model:IsA("Model") then
        return model
    end

    return nil
end

local function isGilgameshEncounter()
    return getGilgameshModel() ~= nil
end

local function isGilgameshPhase()
    local map = workspace:FindFirstChild("Map")
    return map ~= nil and map:FindFirstChild("NoVoid") ~= nil
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
local function teleportToPosition(force)
    if game.PlaceId ~= SPECIFIC_PLACE_ID then return false end
    if State.specialMode or State.bossCompleted then return false end
    if isGilgameshPhase() then return false end

    local char = player.Character
    if not char then return false end

    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end

    local distance = (hrp.Position - TELEPORT_POSITION).Magnitude
    if force or distance > CONFIG.START_POSITION_TOLERANCE then
        State.startPositionReady = false
        State.startPositionStableSince = nil
        hrp.CFrame = CFrame.new(TELEPORT_POSITION)
        State.teleported = true
        return true
    end

    return false
end
teleportToArbiterPlatform = function()
    if game.PlaceId ~= SPECIFIC_PLACE_ID then return end

    local char = player.Character
    if not char then return end

    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    if not arbiterPlatform or not arbiterPlatform.Parent then return end

    local targetCFrame = CFrame.new(arbiterPlatform.Position + Vector3.new(0, (ARBITER_PLATFORM_SIZE.Y / 2) + 3, 0))
    hrp.CFrame = targetCFrame
end

local function maintainStartPosition(now)
    if game.PlaceId ~= SPECIFIC_PLACE_ID then
        State.startPositionReady = false
        State.startPositionStableSince = nil
        return false
    end

    if State.specialMode or State.bossCompleted or State.arbiterPresent or isGilgameshPhase() then
        return false
    end

    if now - cache.lastStartPositionCheck < CONFIG.START_POSITION_CHECK_INTERVAL then
        return State.startPositionReady
    end

    cache.lastStartPositionCheck = now

    local character = player.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")

    if not hrp then
        State.startPositionReady = false
        State.startPositionStableSince = nil
        return false
    end

    local distance = (hrp.Position - TELEPORT_POSITION).Magnitude

    if distance > CONFIG.START_POSITION_TOLERANCE then
        State.startPositionReady = false
        State.startPositionStableSince = nil
        hrp.CFrame = CFrame.new(TELEPORT_POSITION)
        State.teleported = true
        return false
    end

    if not State.startPositionStableSince then
        State.startPositionStableSince = now
        State.startPositionReady = false
        return false
    end

    if now - State.startPositionStableSince >= CONFIG.DUMMY_POSITION_SETTLE_TIME then
        State.startPositionReady = true
    end

    return State.startPositionReady
end

local function isValueObject(object)
    return object:IsA("IntValue")
        or object:IsA("NumberValue")
        or object:IsA("StringValue")
end

local function resolveLivesObject(now)
    if cache.livesObject and cache.livesObject.Parent == player then
        return cache.livesObject
    end

    cache.livesObject = player:FindFirstChild("Lives")
    return cache.livesObject
end

local function getLivesCount(now)
    local lives = resolveLivesObject(now)
    if not lives then
        return nil
    end

    return tonumber(lives.Value)
end
local function isPlayerAlive()
    local humanoid = getCachedHumanoid()
    return humanoid ~= nil and humanoid.Health > 0
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
    local humanoid = getCachedHumanoid()

    if not humanoid then
        return
    end

    if characterHealthConnection then
        characterHealthConnection:Disconnect()
    end

    characterHealthConnection = humanoid.HealthChanged:Connect(function(health)
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
local TARGET_PART_NAMES = {
    "HumanoidRootPart",
    "Head",
    "Torso",
    "UpperTorso",
    "LowerTorso",
    "Chest",
    "Body"
}

local function getTargetPart(model)
    local data = cache.enemyData[model]

    if data and data.TargetPart and data.TargetPart.Parent then
        return data.TargetPart
    end

    local specialName = SPECIAL_TARGET_PARTS[model.Name]

    if specialName then
        local specialPart = model:FindFirstChild(specialName)

        if specialPart and specialPart:IsA("BasePart") then
            if data then
                data.TargetPart = specialPart
            end

            return specialPart
        end
    end

    for _, partName in ipairs(TARGET_PART_NAMES) do
        local part = model:FindFirstChild(partName)

        if part and part:IsA("BasePart") then
            if data then
                data.TargetPart = part
            end

            return part
        end
    end

    for _, child in ipairs(model:GetChildren()) do
        if child:IsA("BasePart") then
            if data then
                data.TargetPart = child
            end

            return child
        end
    end

    return nil
end

local function findArbiterSurfaceShot(model, cameraPosition)
    if not model or model.Parent ~= workspace then
        return nil, nil
    end

    local boxCFrame, boxSize = model:GetBoundingBox()
    local center = boxCFrame.Position
    local toCamera = cameraPosition - center

    if toCamera.Magnitude <= 0.001 then
        toCamera = Vector3.new(0, 0, 1)
    end

    local direction = toCamera.Unit

    local halfExtent =
        math.abs(direction:Dot(boxCFrame.RightVector)) * (boxSize.X * 0.5) +
        math.abs(direction:Dot(boxCFrame.UpVector)) * (boxSize.Y * 0.5) +
        math.abs(direction:Dot(boxCFrame.LookVector)) * (boxSize.Z * 0.5)

    local surfaceDistance = math.max(halfExtent, 1)
    local endPos = center + direction * surfaceDistance
    local startPos = center + direction * (surfaceDistance + CONFIG.ARBITER_SURFACE_BUFFER + 5)

    return startPos, endPos
end

local function selectTarget()
    if not State.playerAlive or not State.shootingEnabled then
        return nil
    end

    local now = tick()

    if not State.arbiterPresent and now - cache.lastTargetUpdate < CONFIG.TARGET_REFRESH_INTERVAL then
        if isValidEnemyData(State.currentTarget) then
            return State.currentTarget
        end
    end

    cache.lastTargetUpdate = now
    refreshEnemyModels(false)

    local character = player.Character
    local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
    local playerPos = humanoidRootPart and humanoidRootPart.Position or Vector3.new()

    local arbiterEnemy = nil
    local priorityEnemy = nil
    local closestEnemy = nil
    local closestDistanceSquared = math.huge

    for _, model in ipairs(cache.enemyModels) do
        local data = cache.enemyData[model]

        if data and model.Parent == workspace then
            local humanoid = data.Humanoid

            if humanoid and humanoid.Parent and humanoid.Health > 0 then
                if data.IsArbiter then
                    data.TargetPart = getTargetPart(model)

                    if data.TargetPart then
                        data.Position = data.TargetPart.Position
                    else
                        data.Position = ARBITER_BASE_POSITION
                    end

                    arbiterEnemy = data
                else
                    local targetPart = getTargetPart(model)

                    if targetPart then
                        data.Position = targetPart.Position

                        if data.IsPriority and not priorityEnemy then
                            priorityEnemy = data
                        end

                        local dx = data.Position.X - playerPos.X
                        local dy = data.Position.Y - playerPos.Y
                        local dz = data.Position.Z - playerPos.Z
                        local distanceSquared = dx * dx + dy * dy + dz * dz

                        if not data.IsPriority and distanceSquared < closestDistanceSquared then
                            closestDistanceSquared = distanceSquared
                            closestEnemy = data
                        end
                    elseif data.IsPriority and not priorityEnemy then
                        data.Position = Vector3.new()
                        priorityEnemy = data
                    end
                end
            end
        end
    end

    if arbiterEnemy then
        State.currentTarget = arbiterEnemy
        State.currentTargetName = arbiterEnemy.Name
        State.arbiterPresent = true
        State.arbiterForceShoot = true
        return arbiterEnemy
    end

    State.arbiterPresent = false
    State.arbiterForceShoot = false

    local chosenTarget = priorityEnemy or closestEnemy

    if chosenTarget then
        State.currentTarget = chosenTarget
        State.currentTargetName = chosenTarget.Name
        return chosenTarget
    end

    State.currentTarget = nil
    State.currentTargetName = "None"
    return nil
end
local function hasTemperature()
    return getOrFindTemperature() ~= nil
end
local function getValidTool()
    if not State.playerAlive or not State.shootingEnabled then
        return nil
    end

    local character = player.Character

    if not character then
        return nil
    end

    if cache.toolCharacter == character and cache.toolData then
        local tool = cache.toolData.Tool
        local remote = cache.toolData.Remote
        local handle = cache.toolData.Handle

        if tool and tool.Parent == character
            and remote and remote.Parent == tool
            and handle and handle.Parent == tool then
            return cache.toolData
        end

        cache.toolData = nil
    end

    local tool = character:FindFirstChild(CONFIG.TOOL_NAME)

    if not tool or not tool:IsA("Tool") then
        return nil
    end

    local remote = tool:FindFirstChild(CONFIG.REMOTE_NAME)
    local handle = tool:FindFirstChild("Handle")

    if remote and handle and remote:IsA("RemoteFunction") then
        cache.toolCharacter = character
        cache.toolData = {
            Tool = tool,
            Remote = remote,
            Handle = handle
        }

        return cache.toolData
    end

    return nil
end
local function equipTool(force)
    if not State.playerAlive then
        return false
    end

    local character = player.Character
    if not character then
        return false
    end

    local equipped = character:FindFirstChild(CONFIG.TOOL_NAME)
    if equipped and equipped:IsA("Tool") then
        return true
    end

    local now = tick()
    if not force and now - State.lastToolEquipTime < CONFIG.toolEquipCooldown then
        return false
    end

    local humanoid = getCachedHumanoid()
    if not humanoid then
        return false
    end

    local backpack = player:FindFirstChild("Backpack")
    local tool = backpack and backpack:FindFirstChild(CONFIG.TOOL_NAME) or nil

    if not tool or not tool:IsA("Tool") then
        return false
    end

    local success = pcall(function()
        humanoid:EquipTool(tool)
    end)

    if not success then
        return false
    end

    local deadline = os.clock() + 0.5
    repeat
        equipped = character:FindFirstChild(CONFIG.TOOL_NAME)
        if equipped and equipped:IsA("Tool") then
            cache.toolData = nil
            State.lastToolEquipTime = tick()
            return true
        end
        task.wait(0.02)
    until os.clock() >= deadline

    return false
end

local function findToolAnywhere(toolName)
    local character = player.Character

    if character then
        local tool = character:FindFirstChild(toolName)
        if tool and tool:IsA("Tool") then
            return tool
        end
    end

    local backpack = player:FindFirstChild("Backpack")

    if backpack then
        local tool = backpack:FindFirstChild(toolName)
        if tool and tool:IsA("Tool") then
            return tool
        end
    end

    return nil
end

local function equipNamedTool(toolName)
    local character = player.Character
    local humanoid = getCachedHumanoid()

    if not character or not humanoid then
        return nil
    end

    local alreadyEquipped = character:FindFirstChild(toolName)
    if alreadyEquipped and alreadyEquipped:IsA("Tool") then
        return alreadyEquipped
    end

    local backpack = player:FindFirstChild("Backpack")
    local tool = backpack and backpack:FindFirstChild(toolName) or nil

    if not tool or not tool:IsA("Tool") then
        return nil
    end

    local success = pcall(function()
        humanoid:EquipTool(tool)
    end)

    if not success then
        return nil
    end

    local deadline = os.clock() + 0.6
    repeat
        local equipped = character:FindFirstChild(toolName)
        if equipped and equipped:IsA("Tool") then
            return equipped
        end
        task.wait(0.02)
    until os.clock() >= deadline

    return nil
end

local function enableSimulationDummyShield(dummy, dummyTool, placeRemote)
    if not dummy or dummy.Parent ~= workspace then
        return false
    end

    if not placeRemote then
        return false
    end

    local isRemote = false
    local remoteCheckSuccess = pcall(function()
        isRemote = placeRemote:IsA("RemoteFunction")
    end)

    if not remoteCheckSuccess or not isRemote then
        return false
    end

    local character = player.Character
    local equippedDummyTool = character and character:FindFirstChild(CONFIG.DUMMY_TOOL_NAME)

    if equippedDummyTool and equippedDummyTool:IsA("Tool") then
        dummyTool = equippedDummyTool
    elseif dummyTool and dummyTool.Parent then
        dummyTool = equipNamedTool(CONFIG.DUMMY_TOOL_NAME) or dummyTool
    end

    task.wait(CONFIG.DUMMY_SHIELD_DELAY)

    local deadline = os.clock() + CONFIG.DUMMY_SHIELD_TIMEOUT

    repeat
        local success = pcall(function()
            placeRemote:InvokeServer("Shielded", true)
        end)

        if success then
            cache.dummyShieldRemote = placeRemote
            State.dummyShieldEnabled = true
            return true
        end

        task.wait(0.05)
    until os.clock() >= deadline

    return false
end

local function spawnSimulationDummy()
    local tool = findToolAnywhere(CONFIG.DUMMY_TOOL_NAME)
    if not tool then
        return nil
    end

    local placeRemote = tool:FindFirstChild(CONFIG.DUMMY_REMOTE_NAME)
    if not placeRemote or not placeRemote:IsA("RemoteFunction") then
        return nil
    end

    local dummyTool = equipNamedTool(CONFIG.DUMMY_TOOL_NAME)

    if not dummyTool then
        return nil
    end

    local existing = {}
    for _, child in ipairs(workspace:GetChildren()) do
        if child:IsA("Model") and child.Name == CONFIG.DUMMY_MODEL_NAME then
            existing[child] = true
        end
    end

    local spawnedDummy = nil
    local childAddedConnection

    childAddedConnection = workspace.ChildAdded:Connect(function(child)
        if child:IsA("Model")
            and child.Name == CONFIG.DUMMY_MODEL_NAME
            and not existing[child] then
            spawnedDummy = child
        end
    end)

    cache.dummyTool = dummyTool
    cache.dummyPlaceRemote = placeRemote
    cache.dummyShieldRemote = nil

    local placeSuccess = pcall(function()
        placeRemote:InvokeServer("place")
    end)

    if not placeSuccess then
        childAddedConnection:Disconnect()
        return nil
    end

    local deadline = os.clock() + CONFIG.DUMMY_SPAWN_TIMEOUT

    repeat
        if spawnedDummy and spawnedDummy.Parent == workspace then
            break
        end

        for _, child in ipairs(workspace:GetChildren()) do
            if child:IsA("Model")
                and child.Name == CONFIG.DUMMY_MODEL_NAME
                and not existing[child] then
                spawnedDummy = child
                break
            end
        end

        if spawnedDummy then
            break
        end

        task.wait(0.03)
    until os.clock() >= deadline

    childAddedConnection:Disconnect()

    if not spawnedDummy then
        return nil
    end

    return spawnedDummy
end

local function getGigatonRemote()
    if cache.gigatonRemote then
        local valid = false
        pcall(function()
            valid = cache.gigatonRemote:IsA("RemoteFunction")
        end)

        if valid then
            return cache.gigatonRemote
        end

        cache.gigatonRemote = nil
    end

    local backpack = player:FindFirstChild("Backpack")
    local tool = backpack and backpack:FindFirstChild(CONFIG.GIGATON_TOOL_NAME) or nil

    if not tool then
        local character = player.Character
        tool = character and character:FindFirstChild(CONFIG.GIGATON_TOOL_NAME) or nil
    end

    if not tool or not tool:IsA("Tool") then
        return nil
    end

    local remote = tool:FindFirstChild(CONFIG.GIGATON_REMOTE_NAME)

    if remote and remote:IsA("RemoteFunction") then
        cache.gigatonRemote = remote
        return remote
    end

    return nil
end

local function primeGigatonHammer()
    local deadline = os.clock() + 8

    repeat
        local tool = equipNamedTool(CONFIG.GIGATON_TOOL_NAME)

        if tool then
            local remote = tool:FindFirstChild(CONFIG.GIGATON_REMOTE_NAME)

            if remote and remote:IsA("RemoteFunction") then
                cache.gigatonRemote = remote
            end

            task.wait(0.15)

            if isPlayerAlive() then
                equipTool(true)
            end

            return true
        end

        task.wait(0.1)
    until os.clock() >= deadline

    return false
end

local function startGigatonLoop()
    State.gigatonEnabled = true

    if State.gigatonLoopStarted then
        return
    end

    State.gigatonLoopStarted = true

    task.spawn(function()
        while State.gigatonLoopStarted do
            if State.gigatonEnabled
                and State.isRunning
                and State.playerAlive
                and not State.bossCompleted then

                local remote = getGigatonRemote()

                if remote then
                    pcall(function()
                        remote:InvokeServer("GigatonSlam")
                    end)
                end
            end

            task.wait(CONFIG.GIGATON_INTERVAL)
        end
    end)
end

local function resetDummySetupForContext(context)
    State.dummyContext = context
    State.dummySetupCompleted = false
    State.dummyShieldEnabled = false
    State.gigatonEnabled = false
    cache.simulationDummy = nil
    cache.dummyTool = nil
    cache.dummyPlaceRemote = nil
    cache.dummyShieldRemote = nil
end

local function setupSimulationDummy(context)
    if State.dummySetupStarted then
        return false
    end

    if State.dummyContext ~= context then
        resetDummySetupForContext(context)
    end

    if State.dummySetupCompleted
        and State.dummyShieldEnabled
        and cache.simulationDummy
        and cache.simulationDummy.Parent == workspace then
        startGigatonLoop()
        return true
    end

    local now = tick()
    if now - State.lastDummySetupAttempt < CONFIG.DUMMY_SETUP_RETRY_DELAY then
        return false
    end

    State.lastDummySetupAttempt = now
    State.dummySetupStarted = true

    local previousShootingEnabled = State.shootingEnabled
    State.shootingEnabled = false

    local dummy = cache.simulationDummy

    if not dummy or dummy.Parent ~= workspace then
        dummy = spawnSimulationDummy()
        cache.simulationDummy = dummy
    else
        cache.dummyTool = equipNamedTool(CONFIG.DUMMY_TOOL_NAME)
    end

    local shieldEnabled = false

    if dummy and dummy.Parent == workspace then
        shieldEnabled = enableSimulationDummyShield(
            dummy,
            cache.dummyTool,
            cache.dummyPlaceRemote
        )
    end

    State.dummyShieldEnabled = shieldEnabled
    State.dummySetupCompleted = dummy ~= nil and shieldEnabled

    State.playerAlive = isPlayerAlive()

    if State.playerAlive then
        equipTool()
    end

    if previousShootingEnabled and State.playerAlive then
        State.shootingEnabled = true
    end

    State.dummySetupStarted = false

    if State.dummySetupCompleted then
        startGigatonLoop()
        return true
    end

    return false
end

local function ensureCombatBuffSetup(context)
    if State.dummyContext ~= context then
        resetDummySetupForContext(context)
    end

    if State.dummySetupCompleted or State.dummySetupStarted then
        return
    end

    if tick() - State.lastDummySetupAttempt < CONFIG.DUMMY_SETUP_RETRY_DELAY then
        return
    end

    task.spawn(setupSimulationDummy, context)
end

local function attemptFire()
    if not State.isRunning or State.specialMode or State.bossCompleted then
        return
    end

    if not State.playerAlive or not State.shootingEnabled then
        return
    end

    local now = tick()

    if now - State.lastFireTime < CONFIG.FIRE_RATE then
        return
    end

    local targetResult = State.currentTarget

    if State.arbiterPresent then
        targetResult = selectTarget()
    elseif not isValidEnemyData(targetResult) then
        targetResult = selectTarget()
    elseif not targetResult.IsPriority and not targetResult.IsArbiter
        and now - cache.lastTargetUpdate >= CONFIG.TARGET_REFRESH_INTERVAL then
        targetResult = selectTarget()
    end

    if not targetResult then
        return
    end

    local isArbiter = targetResult.IsArbiter == true

    if isArbiter and State.arbiterSpawnTime > 0 and now - State.arbiterSpawnTime < 3 then
        return
    end

    local toolData = getValidTool()

    if not toolData then
        equipTool()
        toolData = getValidTool()

        if not toolData then
            State.shootingErrors += 1
            return
        end
    end

    if not hasTemperature() then
        equipTool()

        if not hasTemperature() then
            State.shootingErrors += 1
            return
        end
    end

    local targetPos = targetResult.Position
    local startPos

    if isArbiter then
        startPos, targetPos = findArbiterSurfaceShot(
            targetResult.Model,
            toolData.Handle.Position
        )

        if not startPos or not targetPos then
            targetPos = ARBITER_BASE_POSITION

            local direction = targetPos - toolData.Handle.Position

            if direction.Magnitude <= 0.001 then
                return
            end

            startPos = targetPos - direction.Unit * 5
        end
    else
        local targetPart = targetResult.TargetPart

        if not targetPart or not targetPart.Parent then
            targetResult = selectTarget()
            targetPart = targetResult and targetResult.TargetPart

            if not targetPart or not targetPart.Parent then
                return
            end
        end

        targetPos = targetPart.Position

        local camera = workspace.CurrentCamera
        local originPosition = camera and camera.CFrame.Position or toolData.Handle.Position
        local direction = targetPos - originPosition

        if direction.Magnitude <= 0.001 then
            return
        end

        startPos = targetPos - direction.Unit * 5
    end

    State.lastFireTime = now

    local fireSuccess = pcall(function()
        toolData.Remote:InvokeServer("fire", {
            startPos,
            targetPos,
            State.chargeValue
        })
    end)

    if fireSuccess then
        State.shootingErrors = 0
        return
    end

    State.shootingErrors += 1

    if isArbiter then
        task.defer(function()
            pcall(function()
                toolData.Remote:InvokeServer("fire", {
                    startPos,
                    targetPos,
                    State.chargeValue
                })
            end)
        end)
    end

    if State.shootingErrors > State.maxShootingErrors and not State.arbiterPresent then
        State.shootingEnabled = false

        task.delay(1.5, function()
            if State.isRunning and State.playerAlive then
                State.shootingErrors = 0
                State.shootingEnabled = true
            end
        end)
    end
end
local function getPartyRemote()
    if cache.partyRemote and cache.partyRemote.Parent then
        return cache.partyRemote
    end

    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local partySystem = remotes and remotes:FindFirstChild("PartySystem")
    local partyRemote = partySystem and partySystem:FindFirstChild("PartyFunction")

    if partyRemote then
        cache.partyRemote = partyRemote
    end

    return partyRemote
end

local function checkTeleportSuccess()
    local deadline = os.clock() + CONFIG.TELEPORT_TIMEOUT

    repeat
        local teleportState = TeleportService:GetLocalPlayerTeleportState()

        if teleportState ~= Enum.TeleportState.None
            and teleportState ~= Enum.TeleportState.Failed then
            return true
        end

        task.wait(0.2)
    until os.clock() >= deadline

    return false
end

local function attemptDungeonTeleport()
    if State.bossCompleted then
        return false
    end

    State.bossCompleted = true
    State.specialMode = true
    State.isRunning = false
    State.shootingEnabled = false
    State.teleportAttempts = 0

    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")

    if character then
        local cannon = character:FindFirstChild(CONFIG.TOOL_NAME)

        if cannon then
            cannon.Parent = player.Backpack
            cache.toolData = nil
        end

        local artifact = character:FindFirstChild("Mysterious Artifact")

        if not artifact then
            local backpack = player:FindFirstChild("Backpack")
            artifact = backpack and backpack:FindFirstChild("Mysterious Artifact") or nil

            if artifact then
                artifact.Parent = character
            end
        end

        if artifact and humanoid then
            humanoid:EquipTool(artifact)
        end
    end

    task.wait(0.25)

    local partyRemote = getPartyRemote()

    if not partyRemote then
        State.bossCompleted = false
        return false
    end

    for attempt = 1, State.maxTeleportAttempts do
        State.teleportAttempts = attempt

        local createSuccess = false

        local createCallSuccess = pcall(function()
            local result = partyRemote:InvokeServer("createParty", {
                settings = {
                    FriendsOnly = true,
                    Visual = true
                },
                subplace = "Stronghold"
            })

            createSuccess = result ~= false
        end)

        if createCallSuccess and createSuccess then
            task.wait(0.45)

            local joinSuccess = false

            local joinCallSuccess = pcall(function()
                local result = partyRemote:InvokeServer("joinSubplace", {})
                joinSuccess = result ~= false
            end)

            if joinCallSuccess and joinSuccess and checkTeleportSuccess() then
                return true
            end
        end

        if attempt < State.maxTeleportAttempts then
            task.wait(CONFIG.TELEPORT_RETRY_DELAY)
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
        State.autoTeleportTriggered = false
        State.lifeTeleportTriggered = false
        cache.lastLivesValue = nil
        cache.livesObject = nil
        cache.lastLivesScan = 0
    end
end
local function checkBossStatus()
    local gilgamesh = workspace:FindFirstChild("Gilgamesh, the Consumer of Reality")
    local uberBringer = workspace:FindFirstChild("The Supreme Uber Bringer of Light and Space Time Annihilation")
    local alrasid = workspace:FindFirstChild("Alrasid, Archbishop of the Equinox")

    if CONFIG.WAIT_FOR_GILGAMESH_AFTER_ALRASID then
        if gilgamesh then
            State.bossHasSpawned = true

            local humanoid = gilgamesh:FindFirstChildOfClass("Humanoid")
            if not humanoid then
                return "gilgamesh_spawning"
            end

            if humanoid.Health <= 0 then
                return "gilgamesh_dead"
            end

            return "gilgamesh_alive"
        end

        if alrasid then
            local humanoid = alrasid:FindFirstChildOfClass("Humanoid")

            if humanoid and humanoid.Health <= 0 then
                State.alrasidDead = true
                return "waiting_for_gilgamesh"
            end

            if humanoid then
                return "alrasid_alive"
            end

            return "alrasid_spawning"
        end

        if State.alrasidDead then
            return "waiting_for_gilgamesh"
        end

        return "not_spawned"
    end

    local boss = gilgamesh or uberBringer or alrasid

    if boss then
        State.bossHasSpawned = true
        local humanoid = boss:FindFirstChildOfClass("Humanoid")

        if humanoid then
            if humanoid.Health <= 0 then
                if boss.Name == "Alrasid, Archbishop of the Equinox" then
                    State.alrasidDead = true
                    return "alrasid_dead"
                end

                return "dead"
            end

            return "alive"
        end

        return "spawning"
    end

    return "not_spawned"
end
local function farmingLoop()
    local lastBossCheck = 0
    local bossCheckInterval = 1
    local lastRecoveryCheck = 0
    local recoveryCheckInterval = 3

    while State.isRunning and not State.bossCompleted do
        local loopSuccess = pcall(function()
            local now = tick()
            State.playerAlive = isPlayerAlive()

            if State.playerAlive then
                if checkAutoTeleport() then
                    handleDungeonTeleport()
                    return
                end

                local gilgameshEncounter = isGilgameshEncounter()
                local gilgameshPhase = isGilgameshPhase()

                if gilgameshPhase then
                    ensureCombatBuffSetup("Gilgamesh")
                else
                    local startPositionReady = maintainStartPosition(now)

                    if startPositionReady then
                        ensureCombatBuffSetup("Stronghold")
                    end
                end

                local lives = getLivesCount(now)
                local allowLifeRetry = not (gilgameshPhase and CONFIG.WAIT_FOR_GILGAMESH_AFTER_ALRASID)

                if lives ~= nil and allowLifeRetry then
                    if lives <= 1 and not State.lifeTeleportTriggered then
                        State.lifeTeleportTriggered = true
                        handleDungeonTeleport()
                        return
                    elseif lives > 1 then
                        State.lifeTeleportTriggered = false
                    end
                elseif gilgameshPhase then
                    State.lifeTeleportTriggered = false
                end

                if now - lastBossCheck >= bossCheckInterval then
                    local bossStatus = checkBossStatus()

                    local shouldTeleportAfterBoss = false

                    if CONFIG.WAIT_FOR_GILGAMESH_AFTER_ALRASID then
                        shouldTeleportAfterBoss = bossStatus == "gilgamesh_dead"
                    else
                        shouldTeleportAfterBoss = bossStatus == "dead" or bossStatus == "alrasid_dead"
                    end

                    if State.bossHasSpawned
                        and shouldTeleportAfterBoss
                        and not State.bossCompleted then
                        handleDungeonTeleport()
                        return
                    end

                    lastBossCheck = now
                end

                if now - lastRecoveryCheck >= recoveryCheckInterval then
                    if State.shootingEnabled
                        and State.isRunning
                        and not State.bossCompleted
                        and State.playerAlive
                        and now - State.lastFireTime > 10 then
                        State.shootingErrors += 2
                    end

                    lastRecoveryCheck = now
                end

                attemptFire()
            else
                State.currentTarget = nil
                State.currentTargetName = "None"
                State.arbiterForceShoot = false
                cache.lastTargetUpdate = 0
            end
        end)

        if not loopSuccess then
            task.wait(0.25)
        else
            RunService.Heartbeat:Wait()
        end
    end
end
local function onCharacterAdded(character)
    State.hasTeleportedToArbiterThisSpawn = false
    State.arbiterSpawnTime = 0
    State.currentTarget = nil
    State.currentTargetName = "None"
    State.arbiterPresent = false
    State.lifeTeleportTriggered = false
    State.dummySetupStarted = false
    State.dummySetupCompleted = false
    State.dummyShieldEnabled = false
    State.dummyContext = nil
    State.lastDummySetupAttempt = 0
    State.gigatonEnabled = false
    State.startPositionReady = false
    State.startPositionStableSince = nil
    cache.simulationDummy = nil
    cache.dummyTool = nil
    cache.dummyPlaceRemote = nil
    cache.dummyShieldRemote = nil
    cache.livesObject = nil
    cache.lastLivesScan = 0
    cache.lastLivesValue = nil
    State.arbiterForceShoot = false
    cache.lastTargetUpdate = 0

    if arbiterPlatform and arbiterPlatform.Parent then
        arbiterPlatform:Destroy()
        arbiterPlatform = nil
    end

    refreshCharacterCache(character)

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

    refreshEnemyModels(true)
end
local function initialize()
    if not player.Character then
        player.CharacterAdded:Wait()
    end

    refreshCharacterCache(player.Character)
    cache.livesObject = player:FindFirstChild("Lives")
    refreshEnemyModels(true)

    player.CharacterAdded:Connect(onCharacterAdded)
    onCharacterAdded(player.Character)

    primeGigatonHammer()
    startLootMonitor()

    if workspaceChildAddedConnection then
        workspaceChildAddedConnection:Disconnect()
    end

    if workspaceChildRemovedConnection then
        workspaceChildRemovedConnection:Disconnect()
    end

    workspaceChildAddedConnection = workspace.ChildAdded:Connect(function(child)
        if child:IsA("Model") then
            if child.Name == CONFIG.DUMMY_MODEL_NAME then
                cache.simulationDummy = child
            end

            if not IGNORE_ENEMIES[child.Name] then
                task.defer(registerEnemyModel, child)
            end

            if child.Name == CONFIG.GILGAMESH_NAME then
                task.defer(function()
                    ensureCombatBuffSetup("Gilgamesh")
                end)
            end
        end
    end)

    workspaceChildRemovedConnection = workspace.ChildRemoved:Connect(function(child)
        if child:IsA("Model") then
            removeEnemyModel(child)
        end
    end)

    if playerChildAddedConnection then
        playerChildAddedConnection:Disconnect()
    end

    playerChildAddedConnection = player.ChildAdded:Connect(function(child)
        if child.Name == "Lives" then
            cache.livesObject = child
        end
    end)

    arbiterSpawnConnection = workspaceChildAddedConnection

    task.spawn(farmingLoop)
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
        if arbiterSpawnConnection then
            arbiterSpawnConnection:Disconnect()
            arbiterSpawnConnection = nil
        end

        if workspaceChildAddedConnection then
            workspaceChildAddedConnection:Disconnect()
            workspaceChildAddedConnection = nil
        end

        if workspaceChildRemovedConnection then
            workspaceChildRemovedConnection:Disconnect()
            workspaceChildRemovedConnection = nil
        end

        if playerChildAddedConnection then
            playerChildAddedConnection:Disconnect()
            playerChildAddedConnection = nil
        end

        if characterHealthConnection then
            characterHealthConnection:Disconnect()
            characterHealthConnection = nil
        end

        State.gigatonEnabled = false
        State.gigatonLoopStarted = false
        stopLootMonitor()

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
        local currentLives = getLivesCount(tick())
        if currentLives == nil then
            currentLives = "Not detected"
        end
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
            PlatformExists = (arbiterPlatform and arbiterPlatform.Parent) ~= nil,
            WaitForGilgameshAfterAlrasid = CONFIG.WAIT_FOR_GILGAMESH_AFTER_ALRASID,
            GilgameshEncounter = isGilgameshEncounter(),
            DummySetupCompleted = State.dummySetupCompleted,
            DummyShieldEnabled = State.dummyShieldEnabled,
            DummyContext = State.dummyContext or "None",
            GigatonEnabled = State.gigatonEnabled
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
