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
 arbiterForceShoot = false
}

local cache = {
 workspaceChildren = {},
 lastWorkspaceUpdate = 0,
 workspaceUpdateInterval = 0.5
}

local function isToolEquipped()
 local character = player.Character
 if not character then return false end
 local humanoid = character:FindFirstChildOfClass("Humanoid")
 if not humanoid then return false end
 local equipped = humanoid.EquippedTool
 if equipped and equipped.Name == CONFIG.TOOL_NAME then return true end
 local tool = character:FindFirstChild(CONFIG.TOOL_NAME)
 if tool then return true end
 return false
end

local function getTargetPart(model)
 local specialName = model.Name
 if SPECIAL_TARGET_PARTS[specialName] then
  local specialPart = model:FindFirstChild(SPECIAL_TARGET_PARTS[specialName])
  if specialPart then return specialPart end
 end
 local possible = {"HumanoidRootPart","Head","Torso","UpperTorso","LowerTorso"}
 for _, partName in ipairs(possible) do
  local p = model:FindFirstChild(partName)
  if p and p:IsA("BasePart") then return p end
 end
 for _, child in ipairs(model:GetChildren()) do
  if child:IsA("BasePart") then return child end
 end
 return nil
end

local function findEnemies()
 if not State.playerAlive or not State.shootingEnabled then return {}, {}, false end
 local now = tick()
 if now - cache.lastWorkspaceUpdate > cache.workspaceUpdateInterval then
  cache.workspaceChildren = workspace:GetChildren()
  cache.lastWorkspaceUpdate = now
 end

 local prio = {}
 local regular = {}
 local arbiterFound = false

 for _, model in ipairs(cache.workspaceChildren) do
  if model:IsA("Model") and model.Parent == workspace then
   local hum = model:FindFirstChildOfClass("Humanoid")
   if hum and hum.Health > 0 then
    local isPlayer = false
    for _, plr in ipairs(Players:GetPlayers()) do
     if plr.Character == model then
      isPlayer = true
      break
     end
    end
    if not isPlayer then
     local part = getTargetPart(model)
     if part then
      local data = {
       Model = model,
       TargetPart = part,
       Position = part.Position,
       Name = model.Name,
       IsPriority = PRIORITY_ENEMIES[model.Name] == true,
       IsArbiter = model.Name == "The Arbiter"
      }
      if data.IsArbiter then
       arbiterFound = true
       data.IsPriority = true
      end
      if data.IsPriority then
       table.insert(prio, data)
      else
       table.insert(regular, data)
      end
     end
    end
   end
  end
 end

 State.arbiterPresent = arbiterFound
 return prio, regular, arbiterFound
end

local function selectTarget()
 if not State.playerAlive or not State.shootingEnabled then return nil end
 local prio, regular, hasArb = findEnemies()
 if hasArb then
  State.arbiterForceShoot = true
  for _, e in ipairs(prio) do
   if e.IsArbiter then return e end
  end
 end
 State.arbiterForceShoot = false
 if #prio > 0 then return prio[1] end
 if #regular > 0 then
  local char = player.Character
  if char then
   local root = char:FindFirstChild("HumanoidRootPart")
   if root then
    local pos = root.Position
    local closest = regular[1]
    local dist = (closest.Position - pos).Magnitude
    for _, e in ipairs(regular) do
     local d = (e.Position - pos).Magnitude
     if d < dist then
      closest = e
      dist = d
     end
    end
    return closest
   end
  end
  return regular[1]
 end
 return nil
end

local function getValidTool()
 if not State.playerAlive or not State.shootingEnabled then return nil end
 local char = player.Character
 if not char then return nil end
 local tool = char:FindFirstChild(CONFIG.TOOL_NAME)
 if not tool then return nil end
 local remote = tool:FindFirstChild(CONFIG.REMOTE_NAME)
 if remote and remote:IsA("RemoteFunction") then
  return {Tool = tool, Remote = remote}
 end
 return nil
end

local function equipTool()
 local now = tick()
 if now - State.lastToolEquipTime < State.toolEquipCooldown then return false end
 local char = player.Character
 if not char then task.wait(0.5) return equipTool() end
 local humanoid = char:FindFirstChildOfClass("Humanoid")
 if not humanoid then task.wait(0.5) return equipTool() end
 if isToolEquipped() then
  State.lastToolEquipTime = now
  return true
 end
 local tool = char:FindFirstChild(CONFIG.TOOL_NAME)
 if tool then
  local suc = pcall(function() humanoid:EquipTool(tool) end)
  if suc then State.lastToolEquipTime = now return true end
 end
 local backpack = player:FindFirstChild("Backpack")
 if backpack then
  local t2 = backpack:FindFirstChild(CONFIG.TOOL_NAME)
  if t2 then
   t2.Parent = char
   task.wait(0.1)
   local suc2 = pcall(function() humanoid:EquipTool(t2) end)
   if suc2 then State.lastToolEquipTime = now return true end
  end
 end
 return false
end

local function attemptFire()
 if not State.isRunning or State.specialMode or State.bossCompleted then return end
 if not State.playerAlive or not State.shootingEnabled then return end

 local target = selectTarget()
 State.currentTarget = target
 if not target and not State.arbiterForceShoot then return end

 local toolData = getValidTool()
 if not toolData then
  if not equipTool() then return end
  toolData = getValidTool()
  if not toolData then return end
 end

 local now = tick()
 if now - State.lastFireTime < CONFIG.FIRE_RATE then return end
 State.lastFireTime = now

 local targetPos
 if State.arbiterForceShoot then
  targetPos = ARBITER_TARGET_POSITION
 else
  targetPos = target.TargetPart.Position
 end

 local cam = workspace.CurrentCamera
 if not cam then return end

 local startPos = cam.CFrame.Position
 pcall(function()
  toolData.Remote:InvokeServer("fire", {startPos, targetPos, State.chargeValue})
 end)
end

local function farmingLoop()
 while State.isRunning and not State.bossCompleted do
  State.playerAlive = (player.Character and player.Character:FindFirstChildOfClass("Humanoid") and player.Character:FindFirstChildOfClass("Humanoid").Health > 0)
  attemptFire()
  RunService.Heartbeat:Wait()
 end
end

task.spawn(farmingLoop)

return {
 Stop = function() State.isRunning = false State.shootingEnabled = false end,
 Start = function() if not State.isRunning then State.isRunning = true task.spawn(farmingLoop) end end
}
