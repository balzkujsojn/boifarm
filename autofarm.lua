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
    shootingEnabled = true,
    shootingErrors = 0,
    maxShootingErrors = 10,
    lastToolEquipTime = 0,
    toolEquipCooldown = 2,
    arbiterPresent = false,
    arbiterForceShoot = false
}

local cache = {
    workspaceChildren = {},
    lastWorkspaceUpdate = 0,
    workspaceUpdateInterval = 0.5
}

local function isPlayerAlive()
    local char = player.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    return hum.Health > 0
end

local function getTargetPart(model)
    local name = model.Name

    if SPECIAL_TARGET_PARTS[name] then
        local p = model:FindFirstChild(SPECIAL_TARGET_PARTS[name])
        if p and p:IsA("BasePart") then return p end
    end

    local fallback = model:FindFirstChild("HumanoidRootPart")
    if fallback and fallback:IsA("BasePart") then return fallback end

    for _, v in ipairs(model:GetDescendants()) do
        if v:IsA("BasePart") then
            return v
        end
    end

    return nil
end

local function refreshWorkspaceCache()
    local now = tick()
    if now - cache.lastWorkspaceUpdate > cache.workspaceUpdateInterval then
        cache.workspaceChildren = workspace:GetChildren()
        cache.lastWorkspaceUpdate = now
    end
end

local function findEnemies()
    if not State.playerAlive or not State.shootingEnabled then return {} end

    refreshWorkspaceCache()

    local enemies = {}
    local priority = {}
    local hasArbiter = false

    for _, model in ipairs(cache.workspaceChildren) do
        if model:IsA("Model") then
            local hum = model:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                local isPlayer = Players:GetPlayerFromCharacter(model)
                if not isPlayer then
                    local part = getTargetPart(model)
                    if part then
                        local data = {
                            Model = model,
                            Humanoid = hum,
                            TargetPart = part,
                            Position = part.Position,
                            Name = model.Name,
                            IsPriority = PRIORITY_ENEMIES[model.Name] == true,
                            IsArbiter = model.Name == "The Arbiter"
                        }

                        if data.IsArbiter then
                            hasArbiter = true
                            data.IsPriority = true
                        end

                        if data.IsPriority then
                            table.insert(priority, data)
                        else
                            table.insert(enemies, data)
                        end
                    end
                end
            end
        end
    end

    State.arbiterPresent = hasArbiter
    if #priority > 0 then return priority end
    return enemies
end

local function selectTarget()
    local enemies = findEnemies()
    if #enemies == 0 then
        State.arbiterForceShoot = false
        return nil
    end

    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")

    if not hrp then return enemies[1] end

    local pos = hrp.Position
    local closest = enemies[1]
    local dist = math.huge

    for _, e in ipairs(enemies) do
        if e.TargetPart and e.TargetPart.Parent then
            local d = (e.Position - pos).Magnitude
            if d < dist then
                dist = d
                closest = e
            end
        end
    end

    if closest and closest.IsArbiter then
        State.arbiterForceShoot = true
    else
        State.arbiterForceShoot = false
    end

    return closest
end

local function getValidTool()
    local char = player.Character
    if not char then return nil end

    local tool = char:FindFirstChild(CONFIG.TOOL_NAME)
    if not tool then return nil end

    local remote = tool:FindFirstChild(CONFIG.REMOTE_NAME)
    local handle = tool:FindFirstChild("Handle")

    if remote and handle and remote:IsA("RemoteFunction") then
        return {Tool = tool, Remote = remote}
    end
end

local function equipTool()
    local now = tick()
    if now - State.lastToolEquipTime < State.toolEquipCooldown then return false end

    local char = player.Character
    if not char then return false end

    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return false end

    local tool = char:FindFirstChild(CONFIG.TOOL_NAME)
    if not tool then
        local bp = player:FindFirstChild("Backpack")
        if bp then
            tool = bp:FindFirstChild(CONFIG.TOOL_NAME)
            if tool then tool.Parent = char end
        end
    end

    if tool then
        hum:EquipTool(tool)
        State.lastToolEquipTime = now
        return true
    end

    return false
end

local function attemptFire()
    if not State.isRunning or not State.shootingEnabled then return end

    State.playerAlive = isPlayerAlive()
    if not State.playerAlive then return end

    local target = selectTarget()
    if not target then return end

    local tool = getValidTool()
    if not tool then
        if not equipTool() then return end
        tool = getValidTool()
        if not tool then return end
    end

    local now = tick()
    if now - State.lastFireTime < CONFIG.FIRE_RATE then return end
    State.lastFireTime = now

    local part = target.TargetPart
    if not part or not part.Parent then return end

    local targetPos
    if target.IsArbiter then
        targetPos = part.Position or ARBITER_TARGET_POSITION
    else
        targetPos = part.Position
    end

    local cam = workspace.CurrentCamera
    if not cam then return end

    local camPos = cam.CFrame.Position
    local dir = (targetPos - camPos).Unit

    local startPos = targetPos - dir * 5
    local endPos = targetPos

    local ok = pcall(function()
        tool.Remote:InvokeServer("fire", {startPos, endPos, State.chargeValue})
    end)

    if not ok then
        State.shootingErrors += 1
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

local function farmingLoop()
    while State.isRunning and not State.bossCompleted do
        attemptFire()
        RunService.Heartbeat:Wait()
    end
end

task.spawn(farmingLoop)

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
    end
}
