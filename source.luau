local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local TweenService = game:GetService("TweenService")

local Client = getsenv(LocalPlayer.PlayerGui.Client)
local Weapons = ReplicatedStorage:WaitForChild("Weapons")

local MIN_DAMAGE = 5
local FOV = 180
local targetHitboxes = {"Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot", "HeadHB", "FakeHead"}
local modifiers = {
	["Head"] = 4, ["FakeHead"] = 4, ["HeadHB"] = 4,
	["UpperTorso"] = 1, ["LowerTorso"] = 1.25,
	["LeftUpperArm"] = 1, ["LeftLowerArm"] = 1, ["LeftHand"] = 1,
	["RightUpperArm"] = 1, ["RightLowerArm"] = 1, ["RightHand"] = 1,
	["LeftUpperLeg"] = 0.75, ["LeftLowerLeg"] = 0.75, ["LeftFoot"] = 0.75,
	["RightUpperLeg"] = 0.75, ["RightLowerLeg"] = 0.75, ["RightFoot"] = 0.75,
}


local InputService = game:GetService("UserInputService")

local Movement = {}

local Workspace = game:GetService("Workspace")
local DebrisFolder = Workspace:WaitForChild("Debris")

local function fixWeapon(weapon)
	local spread = weapon:FindFirstChild("Spread")
	if spread then
		for _, v in ipairs(spread:GetDescendants()) do
			if v:IsA("NumberValue") then v.Value = 0 end
		end
	end
	local penetration = weapon:FindFirstChild("Penetration")
	if penetration and penetration:IsA("IntValue") then
		penetration.Value = 999999999
	end
end

for _, weapon in ipairs(Weapons:GetChildren()) do
	fixWeapon(weapon)
end
Weapons.ChildAdded:Connect(fixWeapon)

local function canWallbang(from, targetPart, ignore, penetrationValue)
	local to = targetPart.Position
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = ignore
	rayParams.FilterType = Enum.RaycastFilterType.Blacklist
	local dir = (to - from)
	local result = workspace:Raycast(from, dir.Unit * dir.Magnitude, rayParams)
	if result and not result.Instance:IsDescendantOf(targetPart.Parent) then
		local material = result.Material
		local materialResistance = ({
			[Enum.Material.Concrete] = 100,
			[Enum.Material.Metal] = 80,
			[Enum.Material.Wood] = 40,
			[Enum.Material.Glass] = 20,
			[Enum.Material.Plastic] = 30
		})[material] or 50
		if penetrationValue > materialResistance then
			local secondRay = workspace:Raycast(result.Position + dir.Unit * 0.1, (to - result.Position).Unit * (to - result.Position).Magnitude, rayParams)
			if secondRay and secondRay.Instance:IsDescendantOf(targetPart.Parent) then
				local wallThickness = (secondRay.Position - result.Position).Magnitude
				return wallThickness < (penetrationValue / materialResistance) * 30
			end
		end
		return false
	end
	return true
end

local function calculateShots(damagePerShot, penetrationValue)
	local shotsNeeded = {}
	for _, hitbox in ipairs(targetHitboxes) do
		local modifier = modifiers[hitbox] or 1
		local effectiveDamage = damagePerShot * modifier * (penetrationValue >= 100 and 0.9 or 1)
		if effectiveDamage >= MIN_DAMAGE then
			local shots = math.ceil(100 / effectiveDamage)
			table.insert(shotsNeeded, {hitbox = hitbox, shots = shots, damage = effectiveDamage})
		end
	end
	table.sort(shotsNeeded, function(a,b) return a.shots < b.shots end)
	return shotsNeeded[1]
end

local function getClosestHitbox(currentWeapon)
	local closestPart, bestInfo, closestDist = nil, nil, math.huge
	local baseDamage = currentWeapon and currentWeapon:FindFirstChild("DMG") and currentWeapon.DMG.Value or 0
	local penetration = currentWeapon and currentWeapon:FindFirstChild("Penetration") and currentWeapon.Penetration.Value or 0
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer and plr.Team ~= LocalPlayer.Team and plr:FindFirstChild("Status") and plr.Status:FindFirstChild("Alive") and plr.Status.Alive.Value and plr.Character then
			local info = calculateShots(baseDamage, penetration)
			if info then
				local part = plr.Character:FindFirstChild(info.hitbox)
				if part and canWallbang(Camera.CFrame.Position, part, {LocalPlayer.Character}, penetration) then
					local dist = (part.Position - Camera.CFrame.Position).Magnitude
					if dist < closestDist then
						closestDist = dist
						closestPart = part
						bestInfo = info
					end
				end
			end
		end
	end
	return closestPart, bestInfo
end

local highlightColor = Color3.fromRGB(255, 255, 255)
local function addHighlight(player)
	if player == LocalPlayer then return end
	if player.Team == LocalPlayer.Team then return end
	if player.Character and not player.Character:FindFirstChild("EnemyHighlight") then
		local highlight = Instance.new("Highlight")
		highlight.Name = "EnemyHighlight"
		highlight.Adornee = player.Character
		highlight.FillColor = highlightColor
		highlight.FillTransparency = 0
		highlight.OutlineColor = highlightColor
		highlight.OutlineTransparency = 0
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Parent = player.Character
	end
end

local function removeHighlight(player)
	if player.Character then
		local highlight = player.Character:FindFirstChild("EnemyHighlight")
		if highlight then highlight:Destroy() end
	end
end

for _, player in pairs(Players:GetPlayers()) do
	addHighlight(player)
	player.CharacterAdded:Connect(function() addHighlight(player) end)
	player:GetPropertyChangedSignal("Team"):Connect(function()
		removeHighlight(player)
		addHighlight(player)
	end)
end

Players.PlayerAdded:Connect(function(player)
	addHighlight(player)
	player.CharacterAdded:Connect(function() addHighlight(player) end)
	player:GetPropertyChangedSignal("Team"):Connect(function()
		removeHighlight(player)
		addHighlight(player)
	end)
end)

local damageLabels = {}
local function createDamageLabel(targetName, damage)
	local screenGui = Instance.new("ScreenGui")
	screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.new(0, 200, 0, 20)
	textLabel.Position = UDim2.new(0.019, 0, 0.012, (#damageLabels * 0.023 * 100))
	textLabel.Text = "Hurt " .. targetName .. " for " .. math.floor(damage) .. "."
	textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	textLabel.TextScaled = true
	textLabel.Font = Enum.Font.Arimo
	textLabel.BackgroundTransparency = 1
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.Parent = screenGui
	table.insert(damageLabels, textLabel)
	task.delay(10, function()
		local tween = TweenService:Create(textLabel, TweenInfo.new(3), {TextTransparency = 1})
		tween:Play()
		tween.Completed:Connect(function()
			textLabel.Parent:Destroy()
			for i, label in ipairs(damageLabels) do
				if label == textLabel then
					table.remove(damageLabels, i)
					break
				end
			end
		end)
	end)
end

local currentWeapon = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("EquippedTool") and Weapons:FindFirstChild(LocalPlayer.Character.EquippedTool.Value)
if currentWeapon then
	fixWeapon(currentWeapon)
end

LocalPlayer.CharacterAdded:Connect(function(character)
	local equippedTool = character:WaitForChild("EquippedTool")
	equippedTool:GetPropertyChangedSignal("Value"):Connect(function()
		currentWeapon = Weapons:FindFirstChild(equippedTool.Value)
		if currentWeapon then
			fixWeapon(currentWeapon)
		end
	end)
end)

RunService.RenderStepped:Connect(function()
	if not Client or Client.vars and Client.vars.DISABLED then return end
	if not LocalPlayer:FindFirstChild("Status") or not LocalPlayer.Status:FindFirstChild("Alive") or not LocalPlayer.Status.Alive.Value then return end
	if not currentWeapon then return end

	local fireRate = currentWeapon:FindFirstChild("FireRate") and currentWeapon.FireRate.Value or 0.1
	local targetPart, bestInfo = getClosestHitbox(currentWeapon)
	if targetPart and bestInfo then
		local oldCFrame = Camera.CFrame
		Camera.CFrame = CFrame.new(Camera.CFrame.Position, targetPart.Position)
		for i = 1, bestInfo.shots do
			Client.firebullet()
			createDamageLabel(targetPart.Parent.Name, bestInfo.damage)
		end
		Camera.CFrame = oldCFrame
		task.wait(fireRate)
	end
end)

function Movement.GetCharacter()
    local character = LocalPlayer.Character
    if not character then return nil end
    local root = character:FindFirstChild("HumanoidRootPart")
    local humanoid = character:FindFirstChild("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return nil end
    if not root then return nil end
    return character, root, humanoid
end

function Movement.GetYRotation(cframe)
    local _, y = cframe:ToOrientation()
    return CFrame.new(cframe.Position) * CFrame.Angles(0, y, 0)
end

function Movement.GetMoveDirection()
    local dir = Vector3.new(0, 0, 0)
    if InputService:IsKeyDown(Enum.KeyCode.W) then dir += Vector3.new(0, 0, -1) end
    if InputService:IsKeyDown(Enum.KeyCode.S) then dir += Vector3.new(0, 0, 1) end
    if InputService:IsKeyDown(Enum.KeyCode.A) then dir += Vector3.new(-1, 0, 0) end
    if InputService:IsKeyDown(Enum.KeyCode.D) then dir += Vector3.new(1, 0, 0) end
    return dir.Magnitude > 0 and dir.Unit or nil
end

RunService.Stepped:Connect(function()
    local character, root, humanoid = Movement.GetCharacter()
    if not character then return end
    if InputService:IsKeyDown(Enum.KeyCode.Space) then
        humanoid.Jump = true
    end
    local moveDir = Movement.GetMoveDirection()
    if not moveDir then return end

    local camCF = camera.CFrame
    local forward = Movement.GetYRotation(camCF):VectorToWorldSpace(moveDir)
    local Speed = 70
    local velocity = forward * Speed
    root.Velocity = Vector3.new(velocity.X, root.Velocity.Y, velocity.Z)
end)

local player = game.Players.LocalPlayer
local rs = game:GetService("ReplicatedStorage")
local client = getsenv(player.PlayerGui.Client)

local function getSkins()
    local skins = {}
    for _,v in ipairs(rs:GetDescendants()) do
        if v.Name:find("_") then
            table.insert(skins, {v.Name})
        end
    end
    if #skins==0 then
        for _,v in ipairs(player.SkinFolder:GetDescendants()) do
            if v:IsA("StringValue") and v.Value:find("_") then
                table.insert(skins, {v.Value})
            end
        end
    end
    local uniq = {}
    for _,s in ipairs(skins) do
        if not table.find(uniq, s[1]) then table.insert(uniq, {s[1]}) end
    end
    return uniq
end

local mt = getrawmetatable(game)
local old = mt.__namecall
setreadonly(mt, false)
local unlocked = false
local allSkins = {}

mt.__namecall = newcclosure(function(self, ...)
    local args = {...}
    local method = getnamecallmethod()
    if method=="InvokeServer" and tostring(self)=="Hugh" then return end
    if method=="FireServer" then
        if args[1]==player.UserId then return end
        if #tostring(self)==38 then
            if not unlocked then
                unlocked = true
                allSkins = getSkins()
                for _,v in ipairs(allSkins) do
                    local skip = false
                    for _,a in ipairs(args[1]) do
                        if a[1]==v[1] then skip=true break end
                    end
                    if not skip then table.insert(args[1], v) end
                end
            end
            return
        end
        if tostring(self)=="DataEvent" and args[1][4] then
            local skin = args[1][4][1]:match("^.-_(.*)$")
            if args[1][2]=="Both" then
                player.SkinFolder.CTFolder[args[1][3]].Value = skin
                player.SkinFolder.TFolder[args[1][3]].Value = skin
            else
                player.SkinFolder[args[1][2].."Folder"][args[1][3]].Value = skin
            end
        end
    end
    return old(self, ...)
end)
setreadonly(mt, true)

if player:FindFirstChild("SkinFolder") then
    local t = player.SkinFolder.TFolder:Clone()
    local ct = player.SkinFolder.CTFolder:Clone()
    player.SkinFolder.TFolder:Destroy()
    player.SkinFolder.CTFolder:Destroy()
    t.Parent = player.SkinFolder
    ct.Parent = player.SkinFolder
end

spawn(function()
    wait(1)
    client.CurrentInventory = getSkins()
end)
