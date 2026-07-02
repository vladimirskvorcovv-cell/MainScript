--!nonstrict

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local VirtualInputManager = select(2, pcall(function()
	return game:GetService("VirtualInputManager")
end))

local LocalPlayer = Players.LocalPlayer

local Config = {
	FlySpeed = 50,
	FastSpeed = 120,
	MinSpeed = 1,
	MaxSpeed = 300,
	FlySmooth = 10,
	Hotkey = Enum.KeyCode.F,
	AntiAFKHotkey = Enum.KeyCode.G,
	NoClipHotkey = Enum.KeyCode.N,
	ClickerHotkey = Enum.KeyCode.C,
	AntiAFKInterval = 120,
	KeyTapTime = 0.08,
	ClickInterval = 0.1,
	MinClickInterval = 0.03,
	MaxClickInterval = 10,
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

local random = Random.new()
local antiAfkKeys = {
	Enum.KeyCode.W,
	Enum.KeyCode.A,
	Enum.KeyCode.S,
	Enum.KeyCode.D,
}

local function hasVirtualInput()
	return typeof(VirtualInputManager) == "Instance"
end

local function tapKey(keyCode, holdTime)
	if not hasVirtualInput() then
		return false, "VirtualInputManager is unavailable"
	end
	local ok, err = pcall(function()
		VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
		task.wait(holdTime or Config.KeyTapTime)
		VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
	end)
	if not ok then
		return false, err
	end
	return true
end

local function clickMouse()
	if not hasVirtualInput() then
		return false, "VirtualInputManager is unavailable"
	end
	local ok, err = pcall(function()
		local position = UserInputService:GetMouseLocation()
		VirtualInputManager:SendMouseButtonEvent(position.X, position.Y, 0, true, game, 0)
		task.wait(0.015)
		VirtualInputManager:SendMouseButtonEvent(position.X, position.Y, 0, false, game, 0)
	end)
	if not ok then
		return false, err
	end
	return true
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
	_token = 0,
}

function AntiAFK.pressRandomKey()
	local keyCode = antiAfkKeys[random:NextInteger(1, #antiAfkKeys)]
	return tapKey(keyCode, Config.KeyTapTime)
end

function AntiAFK.start()
	if AntiAFK.Enabled then
		return true
	end
	if not hasVirtualInput() then
		return false, "VirtualInputManager is unavailable"
	end

	AntiAFK.Enabled = true
	AntiAFK._token += 1
	local token = AntiAFK._token

	task.spawn(function()
		while AntiAFK.Enabled and AntiAFK._token == token do
			local ok = AntiAFK.pressRandomKey()
			if not ok then
				AntiAFK.stop()
				break
			end
			local elapsed = 0
			while elapsed < Config.AntiAFKInterval and AntiAFK.Enabled and AntiAFK._token == token do
				elapsed += task.wait(1)
			end
		end
	end)

	return true
end

function AntiAFK.stop()
	if not AntiAFK.Enabled then
		return true
	end
	AntiAFK.Enabled = false
	AntiAFK._token += 1
	return true
end

function AntiAFK.toggle(state)
	if state then
		return AntiAFK.start()
	end
	return AntiAFK.stop()
end

local Clicker = {
	Enabled = false,
	_token = 0,
}

function Clicker.start()
	if Clicker.Enabled then
		return true
	end
	if not hasVirtualInput() then
		return false, "VirtualInputManager is unavailable"
	end

	Clicker.Enabled = true
	Clicker._token += 1
	local token = Clicker._token

	task.spawn(function()
		while Clicker.Enabled and Clicker._token == token do
			local ok = clickMouse()
			if not ok then
				Clicker.stop()
				break
			end
			task.wait(Config.ClickInterval)
		end
	end)

	return true
end

function Clicker.stop()
	if not Clicker.Enabled then
		return true
	end
	Clicker.Enabled = false
	Clicker._token += 1
	return true
end

function Clicker.toggle(state)
	if state then
		return Clicker.start()
	end
	return Clicker.stop()
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

local storage = (getgenv and getgenv()) or _G
storage.FlyAntiAFK_State = storage.FlyAntiAFK_State or {}
local sessionState = storage.FlyAntiAFK_State
sessionState.Hotkeys = sessionState.Hotkeys or {}

for _, configKey in ipairs({ "Hotkey", "AntiAFKHotkey", "NoClipHotkey", "ClickerHotkey" }) do
	local keyName = sessionState.Hotkeys[configKey]
	if type(keyName) == "string" and Enum.KeyCode[keyName] then
		Config[configKey] = Enum.KeyCode[keyName]
	end
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

local isTouchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local screenPadding = isTouchOnly and 10 or 8
local rowHeight = isTouchOnly and 50 or 44

local function getViewportSize()
	local camera = Workspace.CurrentCamera
	if camera then
		return camera.ViewportSize
	end
	return Vector2.new(1280, 720)
end

local function getExpandedSize()
	local viewport = getViewportSize()
	local widthLimit = math.max(160, viewport.X - screenPadding * 2)
	local heightLimit = math.max(180, viewport.Y - screenPadding * 2)
	local preferredWidth = isTouchOnly and 330 or 306
	local preferredHeight = isTouchOnly and math.max(320, math.floor(viewport.Y * 0.64)) or 360
	return UDim2.fromOffset(math.min(preferredWidth, widthLimit), math.min(preferredHeight, heightLimit))
end

local function getCollapsedSize()
	return isTouchOnly and UDim2.fromOffset(62, 50) or UDim2.fromOffset(52, 42)
end

local function clampOffsetPosition(position, size)
	local viewport = getViewportSize()
	local maxX = math.max(screenPadding, viewport.X - size.X.Offset - screenPadding)
	local maxY = math.max(screenPadding, viewport.Y - size.Y.Offset - screenPadding)
	local x = math.clamp(position.X.Offset, screenPadding, maxX)
	local y = math.clamp(position.Y.Offset, screenPadding, maxY)
	return UDim2.fromOffset(x, y)
end

local function savePosition(key, position)
	sessionState[key] = {
		X = math.floor(position.X.Offset),
		Y = math.floor(position.Y.Offset),
	}
end

local function loadPosition(key, fallback)
	local saved = sessionState[key]
	if typeof(saved) == "table" and type(saved.X) == "number" and type(saved.Y) == "number" then
		return UDim2.fromOffset(saved.X, saved.Y)
	end
	return fallback
end

local function defaultExpandedPosition()
	local size = getExpandedSize()
	return UDim2.fromOffset(screenPadding + 12, math.max(screenPadding, math.floor(getViewportSize().Y * 0.5 - size.Y.Offset * 0.5)))
end

local expandedSize = getExpandedSize()
local collapsedSize = getCollapsedSize()
local expandedPosition = loadPosition("ExpandedPosition", defaultExpandedPosition())
local collapsedPosition = loadPosition("CollapsedPosition", expandedPosition)
local collapsed = sessionState.Collapsed == true
local animatingCollapse = false

local frame = Instance.new("Frame")
frame.Name = "Main"
frame.Size = expandedSize
frame.Position = clampOffsetPosition(expandedPosition, expandedSize)
frame.Visible = not collapsed
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

local function createTab(name, text, xOffset)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.fromOffset(86, 30)
	button.Position = UDim2.fromOffset(xOffset, 2)
	button.BackgroundColor3 = Theme.Button
	button.BorderSizePixel = 0
	button.Text = text
	button.Font = Enum.Font.GothamBold
	button.TextSize = 14
	button.TextColor3 = Theme.Text
	button.AutoButtonColor = false
	button.Parent = tabBar
	addCorner(button, 6)
	return button
end

local mainTab = createTab("MainTab", "Main", 0)
local clickerTab = createTab("ClickerTab", "Clicker", 94)

local function createPage(name)
	local scrollingPage = Instance.new("ScrollingFrame")
	scrollingPage.Name = name
	scrollingPage.Size = UDim2.new(1, 0, 1, -40)
	scrollingPage.Position = UDim2.fromOffset(0, 40)
	scrollingPage.BackgroundTransparency = 1
	scrollingPage.BorderSizePixel = 0
	scrollingPage.Active = true
	scrollingPage.ScrollBarThickness = isTouchOnly and 4 or 6
	scrollingPage.ScrollingDirection = Enum.ScrollingDirection.Y
	scrollingPage.CanvasSize = UDim2.fromOffset(0, 0)
	scrollingPage.CanvasPosition = Vector2.zero
	scrollingPage.Parent = content

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scrollingPage

	return scrollingPage, layout
end

local page, pageLayout = createPage("MainPage")
local clickerPage, clickerPageLayout = createPage("ClickerPage")
clickerPage.Visible = false

local function updateCanvasSize()
	page.CanvasSize = UDim2.fromOffset(0, pageLayout.AbsoluteContentSize.Y + 8)
	clickerPage.CanvasSize = UDim2.fromOffset(0, clickerPageLayout.AbsoluteContentSize.Y + 8)
end

local function selectTab(name)
	local mainActive = name == "Main"
	page.Visible = mainActive
	clickerPage.Visible = not mainActive
	mainTab.BackgroundColor3 = mainActive and Theme.AccentDark or Theme.Button
	clickerTab.BackgroundColor3 = mainActive and Theme.Button or Theme.AccentDark
end

track(pageLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvasSize))
track(clickerPageLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvasSize))
track(mainTab.MouseButton1Click:Connect(function()
	selectTab("Main")
end))
track(clickerTab.MouseButton1Click:Connect(function()
	selectTab("Clicker")
end))
selectTab("Main")

local miniButton = Instance.new("TextButton")
miniButton.Name = "OpenButton"
miniButton.Size = collapsedSize
miniButton.Position = collapsed and clampOffsetPosition(collapsedPosition, collapsedSize) or frame.Position
miniButton.BackgroundColor3 = Theme.AccentDark
miniButton.BorderSizePixel = 0
miniButton.Text = "FA"
miniButton.Font = Enum.Font.GothamBold
miniButton.TextSize = 15
miniButton.TextColor3 = Theme.Text
miniButton.Visible = collapsed
miniButton.Active = true
miniButton.Parent = screenGui
addCorner(miniButton, 8)
addStroke(miniButton, Theme.Stroke, 0.2)

local function createRow(name, order, parentPage)
	local row = Instance.new("Frame")
	row.Name = name
	row.Size = UDim2.new(1, -2, 0, rowHeight)
	row.BackgroundColor3 = Theme.Panel
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	row.Parent = parentPage or page
	addCorner(row, 7)
	addStroke(row, Theme.Stroke, 0.45)
	return row
end

local function createSwitch(text, order, onChanged, parentPage)
	local row = createRow(text .. "Row", order, parentPage)

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

	local switchWidth = isTouchOnly and 56 or 50
	local switchHeight = isTouchOnly and 30 or 26
	local knobSize = switchHeight - 6

	local switch = Instance.new("Frame")
	switch.Name = "Switch"
	switch.Size = UDim2.fromOffset(switchWidth, switchHeight)
	switch.Position = UDim2.new(1, -(switchWidth + 12), 0.5, -math.floor(switchHeight * 0.5))
	switch.BackgroundColor3 = Theme.Off
	switch.BorderSizePixel = 0
	switch.Parent = row
	addCorner(switch, math.floor(switchHeight * 0.5))

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.Size = UDim2.fromOffset(knobSize, knobSize)
	knob.Position = UDim2.fromOffset(3, 3)
	knob.BackgroundColor3 = Theme.Text
	knob.BorderSizePixel = 0
	knob.Parent = switch
	addCorner(knob, math.floor(knobSize * 0.5))

	local enabled = false
	local busy = false

	local control = {}

	local function render(animated)
		local color = enabled and Theme.Accent or Theme.Off
		local knobPosition = enabled and UDim2.fromOffset(switchWidth - knobSize - 3, 3) or UDim2.fromOffset(3, 3)

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

	local pressPosition = nil

	track(row.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			pressPosition = input.Position
		end
	end))

	track(row.InputEnded:Connect(function(input)
		if not pressPosition then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local moved = (input.Position - pressPosition).Magnitude
		pressPosition = nil
		if moved <= 10 then
			control.toggle()
		end
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

local clickerControl = createSwitch("Auto clicker", 1, Clicker.toggle, clickerPage)

local clickDelayRow = createRow("ClickDelayRow", 2, clickerPage)

local clickDelayLabel = Instance.new("TextLabel")
clickDelayLabel.Name = "Label"
clickDelayLabel.Size = UDim2.new(0.5, -12, 1, 0)
clickDelayLabel.Position = UDim2.fromOffset(12, 0)
clickDelayLabel.BackgroundTransparency = 1
clickDelayLabel.Text = "Click delay"
clickDelayLabel.Font = Enum.Font.GothamMedium
clickDelayLabel.TextSize = 14
clickDelayLabel.TextColor3 = Theme.Text
clickDelayLabel.TextXAlignment = Enum.TextXAlignment.Left
clickDelayLabel.Parent = clickDelayRow

local clickDelayBox = Instance.new("TextBox")
clickDelayBox.Name = "DelayBox"
clickDelayBox.Size = UDim2.fromOffset(82, 30)
clickDelayBox.Position = UDim2.new(1, -94, 0.5, -15)
clickDelayBox.BackgroundColor3 = Theme.PanelSoft
clickDelayBox.BorderSizePixel = 0
clickDelayBox.Font = Enum.Font.GothamMedium
clickDelayBox.TextSize = 14
clickDelayBox.TextColor3 = Theme.Text
clickDelayBox.PlaceholderColor3 = Theme.Muted
clickDelayBox.Text = tostring(Config.ClickInterval)
clickDelayBox.PlaceholderText = "Delay"
clickDelayBox.ClearTextOnFocus = false
clickDelayBox.Parent = clickDelayRow
addCorner(clickDelayBox, 6)

track(clickDelayBox.FocusLost:Connect(function()
	local value = clampNumber(clickDelayBox.Text, Config.MinClickInterval, Config.MaxClickInterval)
	if value then
		Config.ClickInterval = value
	end
	clickDelayBox.Text = tostring(Config.ClickInterval)
end))

local bindingHotkey = nil
local hotkeyBindings = {}

local function updateHotkeyBindings()
	for _, binding in ipairs(hotkeyBindings) do
		binding.value.Text = Config[binding.configKey].Name
		binding.button.Text = bindingHotkey == binding and "..." or "Bind"
		binding.button.BackgroundColor3 = bindingHotkey == binding and Theme.AccentDark or Theme.Button
	end
end

local function createHotkeyRow(text, order, configKey, parentPage)
	local row = createRow(text .. "HotkeyRow", order, parentPage)

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, -132, 1, 0)
	label.Position = UDim2.fromOffset(12, 0)
	label.BackgroundTransparency = 1
	label.Text = text .. " bind"
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 14
	label.TextColor3 = Theme.Text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = row

	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.Size = UDim2.fromOffset(42, 30)
	value.Position = UDim2.new(1, -112, 0.5, -15)
	value.BackgroundColor3 = Theme.PanelSoft
	value.BorderSizePixel = 0
	value.Text = Config[configKey].Name
	value.Font = Enum.Font.GothamBold
	value.TextSize = 13
	value.TextColor3 = Theme.Text
	value.Parent = row
	addCorner(value, 6)

	local button = Instance.new("TextButton")
	button.Name = "Bind"
	button.Size = UDim2.fromOffset(62, 30)
	button.Position = UDim2.new(1, -66, 0.5, -15)
	button.BackgroundColor3 = Theme.Button
	button.BorderSizePixel = 0
	button.Text = "Bind"
	button.Font = Enum.Font.GothamBold
	button.TextSize = 13
	button.TextColor3 = Theme.Text
	button.AutoButtonColor = true
	button.Parent = row
	addCorner(button, 6)

	local binding = {
		button = button,
		value = value,
		configKey = configKey,
	}

	table.insert(hotkeyBindings, binding)

	track(button.MouseButton1Click:Connect(function()
		bindingHotkey = if bindingHotkey == binding then nil else binding
		updateHotkeyBindings()
	end))

	return binding
end

createHotkeyRow("Fly", 5, "Hotkey")
createHotkeyRow("AntiAFK", 6, "AntiAFKHotkey")
createHotkeyRow("NoClip", 7, "NoClipHotkey")
createHotkeyRow("Clicker", 3, "ClickerHotkey", clickerPage)
updateHotkeyBindings()
updateCanvasSize()

local function setContentVisible(visible)
	topBar.Visible = visible
	content.Visible = visible
end

local function setMiniPosition(position)
	collapsedPosition = clampOffsetPosition(position, collapsedSize)
	miniButton.Position = collapsedPosition
	savePosition("CollapsedPosition", collapsedPosition)
end

local function collapseGui()
	if collapsed or animatingCollapse then
		return
	end

	collapsed = true
	animatingCollapse = true
	sessionState.Collapsed = true
	expandedPosition = clampOffsetPosition(frame.Position, expandedSize)
	savePosition("ExpandedPosition", expandedPosition)
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
	sessionState.Collapsed = false
	frame.Position = miniButton.Position
	frame.Size = collapsedSize
	frame.Visible = true
	miniButton.Visible = false
	local targetPosition = clampOffsetPosition(miniButton.Position, expandedSize)
	expandedPosition = targetPosition
	savePosition("ExpandedPosition", expandedPosition)
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
	savePosition("ExpandedPosition", expandedPosition)
end)

makeDraggable(miniButton, miniButton, function()
	return collapsedSize
end, function(position)
	collapsedPosition = position
	savePosition("CollapsedPosition", collapsedPosition)
end)

local cameraViewportConnection = nil

local function refreshGuiBounds()
	expandedSize = getExpandedSize()
	collapsedSize = getCollapsedSize()
	miniButton.Size = collapsedSize
	updateCanvasSize()

	if collapsed then
		setMiniPosition(miniButton.Position)
	else
		expandedPosition = clampOffsetPosition(frame.Position, expandedSize)
		frame.Size = expandedSize
		frame.Position = expandedPosition
		savePosition("ExpandedPosition", expandedPosition)
	end
end

local function bindViewportWatcher()
	disconnect(cameraViewportConnection)
	cameraViewportConnection = nil
	local camera = Workspace.CurrentCamera
	if camera then
		cameraViewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshGuiBounds)
	end
end

bindViewportWatcher()
track(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	bindViewportWatcher()
	refreshGuiBounds()
end))
track(minimizeButton.MouseButton1Click:Connect(collapseGui))
track(miniButton.MouseButton1Click:Connect(expandGui))

track(UserInputService.InputBegan:Connect(function(input, processed)
	if bindingHotkey then
		if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode ~= Enum.KeyCode.Unknown then
			Config[bindingHotkey.configKey] = input.KeyCode
			sessionState.Hotkeys[bindingHotkey.configKey] = input.KeyCode.Name
			bindingHotkey = nil
			updateHotkeyBindings()
		end
		return
	end

	if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end

	if input.KeyCode == Config.Hotkey then
		flyControl.toggle()
	elseif input.KeyCode == Config.AntiAFKHotkey then
		antiAfkControl.toggle()
	elseif input.KeyCode == Config.NoClipHotkey then
		noClipControl.toggle()
	elseif input.KeyCode == Config.ClickerHotkey then
		clickerControl.toggle()
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
	sessionState.Collapsed = collapsed
	if collapsed then
		savePosition("CollapsedPosition", miniButton.Position)
	else
		savePosition("ExpandedPosition", frame.Position)
	end
	Fly.stop()
	NoClip.stop()
	AntiAFK.toggle(false)
	Clicker.stop()
	disconnect(cameraViewportConnection)

	for _, connection in ipairs(uiConnections) do
		disconnect(connection)
	end

	table.clear(uiConnections)
end))
