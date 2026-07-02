--!nonstrict

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local VirtualUser = game:GetService("VirtualUser")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer

local Config = {
	FlySpeed = 50,
	FastSpeed = 120,
	MinSpeed = 1,
	MaxSpeed = 300,
	FlySmooth = 10,
	Hotkey = Enum.KeyCode.F,
}

local Theme = {
	Window = Color3.fromRGB(24, 25, 31),
	Panel = Color3.fromRGB(33, 35, 44),
	PanelSoft = Color3.fromRGB(40, 43, 54),
	Stroke = Color3.fromRGB(61, 65, 78),
	Text = Color3.fromRGB(241, 243, 248),
	Muted = Color3.fromRGB(159, 166, 181),
	Accent = Color3.fromRGB(55, 153, 117),
	AccentDark = Color3.fromRGB(37, 108, 84),
	Off = Color3.fromRGB(69, 73, 86),
	Button = Color3.fromRGB(48, 51, 63),
	Danger = Color3.fromRGB(176, 74, 74),
}

local function getCharacter()
	return LocalPlayer.Character
end

local function getRootAndHumanoid()
	local character = getCharacter()
	if not character then
		return nil, nil
	end
	return character:FindFirstChild("HumanoidRootPart"), character:FindFirstChildOfClass("Humanoid")
end

local function clampNumber(value, minValue, maxValue)
	value = tonumber(value)
	if not value then
		return nil
	end
	return math.clamp(value, minValue, maxValue)
end

local function disconnect(connection)
	if connection then
		connection:Disconnect()
	end
end

local function destroy(instance)
	if instance then
		instance:Destroy()
	end
end

local Fly = {
	Enabled = false,
	_render = nil,
	_inputBegan = nil,
	_inputEnded = nil,
	_root = nil,
	_keys = {},
	_vel = Vector3.zero,
	_attach = nil,
	_lv = nil,
	_ao = nil,
	_humanoid = nil,
	_prevPlatformStand = nil,
	_prevAutoRotate = nil,
}

local FLY_KEYS = {
	[Enum.KeyCode.W] = true,
	[Enum.KeyCode.A] = true,
	[Enum.KeyCode.S] = true,
	[Enum.KeyCode.D] = true,
	[Enum.KeyCode.Space] = true,
	[Enum.KeyCode.LeftControl] = true,
	[Enum.KeyCode.LeftShift] = true,
}

local function getCameraVectors()
	local camera = Workspace.CurrentCamera
	if not camera then
		return Vector3.zero, Vector3.zero
	end
	local cframe = camera.CFrame
	return cframe.LookVector, cframe.RightVector
end

function Fly.start()
	if Fly.Enabled then
		return true
	end

	local root, humanoid = getRootAndHumanoid()
	if not root or not humanoid or humanoid.Health <= 0 then
		return false, "Character is not ready"
	end

	Fly.Enabled = true
	Fly._keys = {}
	Fly._root = root
	Fly._humanoid = humanoid
	Fly._vel = Vector3.zero
	Fly._prevPlatformStand = humanoid.PlatformStand
	Fly._prevAutoRotate = humanoid.AutoRotate

	humanoid.PlatformStand = true
	humanoid.AutoRotate = false

	local attach = Instance.new("Attachment")
	attach.Name = "FlyAttach"
	attach.Parent = root

	local lv = Instance.new("LinearVelocity")
	lv.Name = "FlyVelocity"
	lv.Attachment0 = attach
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.ForceLimitMode = Enum.ForceLimitMode.Magnitude
	lv.MaxForce = math.huge
	lv.VectorVelocity = Vector3.zero
	lv.Parent = root

	local ao = Instance.new("AlignOrientation")
	ao.Name = "FlyOrientation"
	ao.Attachment0 = attach
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.RigidityEnabled = false
	ao.Responsiveness = 50
	ao.MaxTorque = math.huge
	ao.Parent = root

	Fly._attach = attach
	Fly._lv = lv
	Fly._ao = ao

	Fly._inputBegan = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if FLY_KEYS[input.KeyCode] then
			Fly._keys[input.KeyCode] = true
		end
	end)

	Fly._inputEnded = UserInputService.InputEnded:Connect(function(input)
		if FLY_KEYS[input.KeyCode] then
			Fly._keys[input.KeyCode] = nil
		end
	end)

	Fly._render = RunService.RenderStepped:Connect(function(dt)
		if not Fly.Enabled or not root.Parent or not humanoid.Parent or humanoid.Health <= 0 then
			Fly.stop()
			return
		end

		local look, right = getCameraVectors()
		local move = Vector3.zero
		local keys = Fly._keys

		if keys[Enum.KeyCode.W] then move += look end
		if keys[Enum.KeyCode.S] then move -= look end
		if keys[Enum.KeyCode.D] then move += right end
		if keys[Enum.KeyCode.A] then move -= right end
		if keys[Enum.KeyCode.Space] then move += Vector3.yAxis end
		if keys[Enum.KeyCode.LeftControl] then move -= Vector3.yAxis end

		local speed = keys[Enum.KeyCode.LeftShift] and Config.FastSpeed or Config.FlySpeed
		local targetVel = Vector3.zero

		if move.Magnitude > 0 then
			targetVel = move.Unit * speed
		end

		Fly._vel = Fly._vel:Lerp(targetVel, math.clamp(Config.FlySmooth * dt, 0, 1))

		if lv.Parent then
			lv.VectorVelocity = Fly._vel
		end

		local flatLook = Vector3.new(look.X, 0, look.Z)
		if flatLook.Magnitude < 0.001 then
			flatLook = Vector3.new(0, 0, -1)
		end

		if ao.Parent then
			ao.CFrame = CFrame.lookAt(Vector3.zero, flatLook.Unit)
		end
	end)

	return true
end

function Fly.stop()
	if not Fly.Enabled and not Fly._lv and not Fly._ao and not Fly._attach then
		return true
	end

	Fly.Enabled = false
	Fly._keys = {}

	disconnect(Fly._render)
	disconnect(Fly._inputBegan)
	disconnect(Fly._inputEnded)

	Fly._render = nil
	Fly._inputBegan = nil
	Fly._inputEnded = nil

	destroy(Fly._lv)
	destroy(Fly._ao)
	destroy(Fly._attach)

	Fly._lv = nil
	Fly._ao = nil
	Fly._attach = nil
	Fly._root = nil
	Fly._vel = Vector3.zero

	local humanoid = Fly._humanoid
	if humanoid and humanoid.Parent then
		humanoid.PlatformStand = if Fly._prevPlatformStand == nil then false else Fly._prevPlatformStand
		humanoid.AutoRotate = if Fly._prevAutoRotate == nil then true else Fly._prevAutoRotate
	end

	Fly._humanoid = nil
	Fly._prevPlatformStand = nil
	Fly._prevAutoRotate = nil

	return true
end

function Fly.toggle(state)
	if state then
		return Fly.start()
	end
	return Fly.stop()
end

local AntiAFK = {
	Enabled = false,
	_conn = nil,
}

function AntiAFK.toggle(state)
	AntiAFK.Enabled = state

	if state then
		if not AntiAFK._conn then
			AntiAFK._conn = LocalPlayer.Idled:Connect(function()
				VirtualUser:CaptureController()
				VirtualUser:ClickButton2(Vector2.zero)
			end)
		end
	else
		disconnect(AntiAFK._conn)
		AntiAFK._conn = nil
	end

	return true
end

local NoClip = {
	Enabled = false,
	_conn = nil,
	_descendantAdded = nil,
	_parts = {},
	_original = setmetatable({}, { __mode = "k" }),
}

local function registerNoClipPart(part)
	if not part:IsA("BasePart") then
		return
	end
	if NoClip._original[part] == nil then
		NoClip._original[part] = part.CanCollide
		table.insert(NoClip._parts, part)
	end
	part.CanCollide = false
end

local function scanNoClipCharacter()
	local character = getCharacter()
	if not character then
		return false
	end
	for _, descendant in ipairs(character:GetDescendants()) do
		registerNoClipPart(descendant)
	end
	disconnect(NoClip._descendantAdded)
	NoClip._descendantAdded = character.DescendantAdded:Connect(registerNoClipPart)
	return true
end

function NoClip.start()
	if NoClip.Enabled then
		return true
	end

	if not scanNoClipCharacter() then
		return false, "Character is not ready"
	end

	NoClip.Enabled = true
	NoClip._conn = RunService.Stepped:Connect(function()
		if not NoClip.Enabled then
			return
		end

		for index = #NoClip._parts, 1, -1 do
			local part = NoClip._parts[index]
			if part.Parent then
				if part.CanCollide then
					part.CanCollide = false
				end
			else
				table.remove(NoClip._parts, index)
				NoClip._original[part] = nil
			end
		end
	end)

	return true
end

function NoClip.stop()
	if not NoClip.Enabled and not NoClip._conn and not NoClip._descendantAdded then
		return true
	end

	NoClip.Enabled = false

	disconnect(NoClip._conn)
	disconnect(NoClip._descendantAdded)

	NoClip._conn = nil
	NoClip._descendantAdded = nil

	for _, part in ipairs(NoClip._parts) do
		if part.Parent then
			local original = NoClip._original[part]
			if original ~= nil then
				part.CanCollide = original
			end
		end
		NoClip._original[part] = nil
	end

	table.clear(NoClip._parts)

	return true
end

function NoClip.toggle(state)
	if state then
		return NoClip.start()
	end
	return NoClip.stop()
end

local guiParent = (gethui and gethui()) or LocalPlayer:WaitForChild("PlayerGui")
local existing = guiParent:FindFirstChild("FlyAntiAFK_GUI")
if existing then
	existing:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FlyAntiAFK_GUI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.IgnoreGuiInset = true
screenGui.Parent = guiParent

local uiConnections = {}
local destroyed = false

local function track(connection)
	table.insert(uiConnections, connection)
	return connection
end

local function addCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

local function addStroke(parent, color, transparency)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Transparency = transparency or 0
	stroke.Thickness = 1
	stroke.Parent = parent
	return stroke
end

local function tween(instance, duration, props)
	local info = TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	local activeTween = TweenService:Create(instance, info, props)
	activeTween:Play()
	return activeTween
end

local function getViewportSize()
	local camera = Workspace.CurrentCamera
	if camera then
		return camera.ViewportSize
	end
	return Vector2.new(1280, 720)
end

local function clampOffsetPosition(position, size)
	local viewport = getViewportSize()
	local x = math.clamp(position.X.Offset, 0, math.max(0, viewport.X - size.X.Offset))
	local y = math.clamp(position.Y.Offset, 0, math.max(0, viewport.Y - size.Y.Offset))
	return UDim2.fromOffset(x, y)
end

local expandedSize = UDim2.fromOffset(286, 318)
local collapsedSize = UDim2.fromOffset(52, 42)
local expandedPosition = UDim2.fromOffset(20, math.max(20, math.floor(getViewportSize().Y * 0.5 - 159)))
local collapsed = false
local animatingCollapse = false

local frame = Instance.new("Frame")
frame.Name = "Main"
frame.Size = expandedSize
frame.Position = clampOffsetPosition(expandedPosition, expandedSize)
frame.BackgroundColor3 = Theme.Window
frame.BorderSizePixel = 0
frame.Active = true
frame.ClipsDescendants = true
frame.Parent = screenGui
addCorner(frame, 8)
addStroke(frame, Theme.Stroke, 0.15)

local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.Size = UDim2.new(1, 0, 0, 42)
topBar.BackgroundTransparency = 1
topBar.Active = true
topBar.Parent = frame

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, -92, 1, 0)
title.Position = UDim2.fromOffset(12, 0)
title.BackgroundTransparency = 1
title.Text = "Fly AntiAFK"
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.TextColor3 = Theme.Text
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = topBar

local function createIconButton(name, text, xOffset)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.fromOffset(30, 28)
	button.Position = UDim2.new(1, xOffset, 0, 7)
	button.BackgroundColor3 = Theme.Button
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Text = text
	button.Font = Enum.Font.GothamBold
	button.TextSize = 15
	button.TextColor3 = Theme.Text
	button.Parent = topBar
	addCorner(button, 6)
	return button
end

local minimizeButton = createIconButton("Minimize", "-", -68)
local closeButton = createIconButton("Close", "x", -34)
closeButton.BackgroundColor3 = Theme.Danger

local content = Instance.new("Frame")
content.Name = "Content"
content.Size = UDim2.new(1, -20, 1, -52)
content.Position = UDim2.fromOffset(10, 44)
content.BackgroundTransparency = 1
content.Parent = frame

local tabBar = Instance.new("Frame")
tabBar.Name = "Tabs"
tabBar.Size = UDim2.new(1, 0, 0, 34)
tabBar.BackgroundTransparency = 1
tabBar.Parent = content

local mainTab = Instance.new("TextButton")
mainTab.Name = "MainTab"
mainTab.Size = UDim2.fromOffset(86, 30)
mainTab.Position = UDim2.fromOffset(0, 2)
mainTab.BackgroundColor3 = Theme.AccentDark
mainTab.BorderSizePixel = 0
mainTab.Text = "Main"
mainTab.Font = Enum.Font.GothamBold
mainTab.TextSize = 14
mainTab.TextColor3 = Theme.Text
mainTab.AutoButtonColor = false
mainTab.Parent = tabBar
addCorner(mainTab, 6)

local page = Instance.new("Frame")
page.Name = "MainPage"
page.Size = UDim2.new(1, 0, 1, -40)
page.Position = UDim2.fromOffset(0, 40)
page.BackgroundTransparency = 1
page.Parent = content

local pageLayout = Instance.new("UIListLayout")
pageLayout.FillDirection = Enum.FillDirection.Vertical
pageLayout.Padding = UDim.new(0, 8)
pageLayout.SortOrder = Enum.SortOrder.LayoutOrder
pageLayout.Parent = page

local miniButton = Instance.new("TextButton")
miniButton.Name = "OpenButton"
miniButton.Size = collapsedSize
miniButton.Position = frame.Position
miniButton.BackgroundColor3 = Theme.AccentDark
miniButton.BorderSizePixel = 0
miniButton.Text = "FA"
miniButton.Font = Enum.Font.GothamBold
miniButton.TextSize = 15
miniButton.TextColor3 = Theme.Text
miniButton.Visible = false
miniButton.Active = true
miniButton.Parent = screenGui
addCorner(miniButton, 8)
addStroke(miniButton, Theme.Stroke, 0.2)

local function createRow(name, order)
	local row = Instance.new("Frame")
	row.Name = name
	row.Size = UDim2.new(1, 0, 0, 44)
	row.BackgroundColor3 = Theme.Panel
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	row.Parent = page
	addCorner(row, 7)
	addStroke(row, Theme.Stroke, 0.45)
	return row
end

local function createSwitch(text, order, onChanged)
	local row = createRow(text .. "Row", order)

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, -86, 1, 0)
	label.Position = UDim2.fromOffset(12, 0)
	label.BackgroundTransparency = 1
	label.Text = text
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 14
	label.TextColor3 = Theme.Text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = row

	local switch = Instance.new("TextButton")
	switch.Name = "Switch"
	switch.Size = UDim2.fromOffset(50, 26)
	switch.Position = UDim2.new(1, -62, 0.5, -13)
	switch.BackgroundColor3 = Theme.Off
	switch.BorderSizePixel = 0
	switch.Text = ""
	switch.AutoButtonColor = false
	switch.Parent = row
	addCorner(switch, 13)

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.Size = UDim2.fromOffset(20, 20)
	knob.Position = UDim2.fromOffset(3, 3)
	knob.BackgroundColor3 = Theme.Text
	knob.BorderSizePixel = 0
	knob.Parent = switch
	addCorner(knob, 10)

	local enabled = false
	local busy = false

	local control = {}

	local function render(animated)
		local color = enabled and Theme.Accent or Theme.Off
		local knobPosition = enabled and UDim2.fromOffset(27, 3) or UDim2.fromOffset(3, 3)

		if animated then
			tween(switch, 0.16, { BackgroundColor3 = color })
			tween(knob, 0.16, { Position = knobPosition })
		else
			switch.BackgroundColor3 = color
			knob.Position = knobPosition
		end
	end

	function control.setState(state)
		enabled = state == true
		render(false)
	end

	function control.set(state)
		if busy or enabled == state then
			return
		end

		busy = true
		local previous = enabled
		enabled = state == true
		render(true)

		local ok, result, message = pcall(onChanged, enabled)
		if not ok or result == false then
			enabled = previous
			render(true)
			if not ok then
				warn("[" .. text .. "]", result)
			elseif message then
				warn("[" .. text .. "]", message)
			end
		end

		busy = false
	end

	function control.toggle()
		control.set(not enabled)
	end

	function control.isEnabled()
		return enabled
	end

	track(row.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			control.toggle()
		end
	end))

	track(switch.MouseButton1Click:Connect(function()
		control.toggle()
	end))

	render(false)

	return control
end

local flyControl = createSwitch("Fly", 1, Fly.toggle)
local antiAfkControl = createSwitch("AntiAFK", 2, AntiAFK.toggle)
local noClipControl = createSwitch("NoClip", 3, NoClip.toggle)

local speedRow = createRow("FlySpeedRow", 4)

local speedLabel = Instance.new("TextLabel")
speedLabel.Name = "Label"
speedLabel.Size = UDim2.new(0.5, -12, 1, 0)
speedLabel.Position = UDim2.fromOffset(12, 0)
speedLabel.BackgroundTransparency = 1
speedLabel.Text = "Fly speed"
speedLabel.Font = Enum.Font.GothamMedium
speedLabel.TextSize = 14
speedLabel.TextColor3 = Theme.Text
speedLabel.TextXAlignment = Enum.TextXAlignment.Left
speedLabel.Parent = speedRow

local speedBox = Instance.new("TextBox")
speedBox.Name = "SpeedBox"
speedBox.Size = UDim2.fromOffset(82, 30)
speedBox.Position = UDim2.new(1, -94, 0.5, -15)
speedBox.BackgroundColor3 = Theme.PanelSoft
speedBox.BorderSizePixel = 0
speedBox.Font = Enum.Font.GothamMedium
speedBox.TextSize = 14
speedBox.TextColor3 = Theme.Text
speedBox.PlaceholderColor3 = Theme.Muted
speedBox.Text = tostring(Config.FlySpeed)
speedBox.PlaceholderText = "Speed"
speedBox.ClearTextOnFocus = false
speedBox.Parent = speedRow
addCorner(speedBox, 6)

track(speedBox.FocusLost:Connect(function()
	local value = clampNumber(speedBox.Text, Config.MinSpeed, Config.MaxSpeed)
	if value then
		Config.FlySpeed = value
	end
	speedBox.Text = tostring(Config.FlySpeed)
end))

local hotkeyRow = createRow("FlyHotkeyRow", 5)

local hotkeyLabel = Instance.new("TextLabel")
hotkeyLabel.Name = "Label"
hotkeyLabel.Size = UDim2.new(1, -132, 1, 0)
hotkeyLabel.Position = UDim2.fromOffset(12, 0)
hotkeyLabel.BackgroundTransparency = 1
hotkeyLabel.Text = "Fly hotkey"
hotkeyLabel.Font = Enum.Font.GothamMedium
hotkeyLabel.TextSize = 14
hotkeyLabel.TextColor3 = Theme.Text
hotkeyLabel.TextXAlignment = Enum.TextXAlignment.Left
hotkeyLabel.Parent = hotkeyRow

local hotkeyValue = Instance.new("TextLabel")
hotkeyValue.Name = "Value"
hotkeyValue.Size = UDim2.fromOffset(42, 30)
hotkeyValue.Position = UDim2.new(1, -112, 0.5, -15)
hotkeyValue.BackgroundColor3 = Theme.PanelSoft
hotkeyValue.BorderSizePixel = 0
hotkeyValue.Text = Config.Hotkey.Name
hotkeyValue.Font = Enum.Font.GothamBold
hotkeyValue.TextSize = 13
hotkeyValue.TextColor3 = Theme.Text
hotkeyValue.Parent = hotkeyRow
addCorner(hotkeyValue, 6)

local bindButton = Instance.new("TextButton")
bindButton.Name = "Bind"
bindButton.Size = UDim2.fromOffset(62, 30)
bindButton.Position = UDim2.new(1, -66, 0.5, -15)
bindButton.BackgroundColor3 = Theme.Button
bindButton.BorderSizePixel = 0
bindButton.Text = "Bind"
bindButton.Font = Enum.Font.GothamBold
bindButton.TextSize = 13
bindButton.TextColor3 = Theme.Text
bindButton.AutoButtonColor = true
bindButton.Parent = hotkeyRow
addCorner(bindButton, 6)

local bindingHotkey = false

local function updateHotkeyUi()
	hotkeyValue.Text = Config.Hotkey.Name
	bindButton.Text = bindingHotkey and "..." or "Bind"
	bindButton.BackgroundColor3 = bindingHotkey and Theme.AccentDark or Theme.Button
end

track(bindButton.MouseButton1Click:Connect(function()
	bindingHotkey = not bindingHotkey
	updateHotkeyUi()
end))

local function setContentVisible(visible)
	topBar.Visible = visible
	content.Visible = visible
end

local function setMiniPosition(position)
	miniButton.Position = clampOffsetPosition(position, collapsedSize)
end

local function collapseGui()
	if collapsed or animatingCollapse then
		return
	end

	collapsed = true
	animatingCollapse = true
	expandedPosition = clampOffsetPosition(frame.Position, expandedSize)
	local targetPosition = clampOffsetPosition(expandedPosition, collapsedSize)
	setMiniPosition(targetPosition)
	setContentVisible(false)
	local activeTween = tween(frame, 0.24, { Position = targetPosition, Size = collapsedSize })

	activeTween.Completed:Connect(function()
		if destroyed then
			return
		end
		frame.Visible = false
		miniButton.Visible = true
		animatingCollapse = false
	end)
end

local function expandGui()
	if not collapsed or animatingCollapse then
		return
	end

	collapsed = false
	animatingCollapse = true
	frame.Position = miniButton.Position
	frame.Size = collapsedSize
	frame.Visible = true
	miniButton.Visible = false
	local targetPosition = clampOffsetPosition(miniButton.Position, expandedSize)
	expandedPosition = targetPosition
	local activeTween = tween(frame, 0.24, { Position = targetPosition, Size = expandedSize })

	activeTween.Completed:Connect(function()
		if destroyed then
			return
		end
		setContentVisible(true)
		animatingCollapse = false
	end)
end

local function makeDraggable(handle, target, sizeGetter, moved)
	local dragging = false
	local dragStart = nil
	local startPosition = nil

	track(handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPosition = target.Position

			local releaseConnection
			releaseConnection = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					if releaseConnection then
						releaseConnection:Disconnect()
						releaseConnection = nil
					end
				end
			end)
		end
	end))

	track(UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		local delta = input.Position - dragStart
		local nextPosition = UDim2.fromOffset(startPosition.X.Offset + delta.X, startPosition.Y.Offset + delta.Y)
		nextPosition = clampOffsetPosition(nextPosition, sizeGetter())
		target.Position = nextPosition
		if moved then
			moved(nextPosition)
		end
	end))
end

makeDraggable(topBar, frame, function()
	return expandedSize
end, function(position)
	expandedPosition = position
end)

makeDraggable(miniButton, miniButton, function()
	return collapsedSize
end, function(position)
	expandedPosition = position
end)

track(minimizeButton.MouseButton1Click:Connect(collapseGui))
track(miniButton.MouseButton1Click:Connect(expandGui))

track(UserInputService.InputBegan:Connect(function(input, processed)
	if bindingHotkey then
		if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode ~= Enum.KeyCode.Unknown then
			Config.Hotkey = input.KeyCode
			bindingHotkey = false
			updateHotkeyUi()
		end
		return
	end

	if processed then
		return
	end

	if input.KeyCode == Config.Hotkey then
		flyControl.toggle()
	end
end))

track(closeButton.MouseButton1Click:Connect(function()
	screenGui:Destroy()
end))

track(LocalPlayer.CharacterAdded:Connect(function()
	Fly.stop()
	NoClip.stop()
	flyControl.setState(false)
	noClipControl.setState(false)
end))

track(screenGui.Destroying:Connect(function()
	if destroyed then
		return
	end

	destroyed = true
	Fly.stop()
	NoClip.stop()
	AntiAFK.toggle(false)

	for _, connection in ipairs(uiConnections) do
		disconnect(connection)
	end

	table.clear(uiConnections)
end))
