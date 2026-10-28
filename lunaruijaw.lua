--[[
	LunarUI v6 Unified Omniverse — Single-File Client UI Framework
	Permanent glass surfaces, user wallpaper support, gradient veils, edge
	highlights, specular sweep, optional world blur and live glass controls.

	Notification redesign (merged):
	- Sharp corners (no UICorner)
	- Header bar
	- Soft black → soft white gradient (left → right)
	- Top-right stacking (BocusLuke-inspired)
	- Type accent strip + progress bar
	- Typewriter, audio, icon, hard cap, Duration=0 manual close
	- Live theme refresh on window + all components

	Stress / leak fixes (v2 Hardened):
	- Slider: UIS InputChanged/Ended only while dragging (no permanent global hooks)
	- MakeDraggable: active move/end connections tracked + killed on Destroy
	- Notifications: hard cap (MAX_NOTIFICATIONS), drop oldest
	- Windows list: remove on window Close/Destroy
	- Dropdown expand still pushes content below
	- Theme presets + ApplyTheme
	- Signal/Changed, Get/Set, CancelOnObject and tracked cleanup

	Usage (single-file source in a LocalScript for your own Roblox experience):
        local LunarUI = _G.LunarUI
        local Window = LunarUI:CreateWindow({
            Title = "Lunar // Control Deck", Layout = "side", Style = "Lunar",
            Width = 760, Height = 560, Resizable = true, ChatTrigger = "+67+",
        })
        local Main = Window:CreateTab({Name="Main", Icon="home"})
        local General = Main:CreateSection({Name="General", Description="A real, reusable section."})
        General:CreateButton({Name="Test", Callback=function() LunarUI:Notify({Title="Done",Description="Callback ran."}) end})

		local Tab = Window:CreateTab({ Name = "Main" })
		Tab:CreateSection({ Name = "Section 1" })
		Tab:CreateButton({ Name = "Test", Callback = function() end })
		-- ... Toggle, Slider, Dropdown, Keybind, Textbox, Label, Divider

		Library:Notify({
			Title = "Ready",
			Description = "Loaded.",
			Duration = 5,           -- 0 = stay until :Close()
			Type = "Success",       -- Info | Success | Warning | Error
			Typewriter = true,
			Audio = "rbxassetid://...",   -- optional sound
			Image = "rbxassetid://...",   -- optional icon
			BarColor = Color3.fromRGB(80, 200, 120),
		})

		-- Alurt-style alias:
		local n = Library:CreateNode({
			Title = "Welcome",
			Content = "You're using VeyraUI",
			Length = 8,
			Audio = "rbxassetid://...",
			Image = "rbxassetid://...",
			BarColor = Color3.fromRGB(255, 75, 75),
		})
		-- n:Close()
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local HttpService = game:GetService("HttpService")
local TextService = game:GetService("TextService")
local TextChatService = game:GetService("TextChatService")

-- A second execution in this client environment unloads the previous instance.
-- This source targets Roblox's normal client UI container (PlayerGui).
local SharedEnvironment = _G
local _previousLunar = SharedEnvironment.LunarUI
if type(_previousLunar) == "table" and type(_previousLunar.Destroy) == "function" then
    pcall(function() _previousLunar:Destroy() end)
end

----------------------------------------------------------------
-- SIGNAL (Changed events for components)
----------------------------------------------------------------
local function CreateSignal()
	local handlers = {}
	local destroyed = false
	local api = {}

	function api:Connect(fn)
		if destroyed or type(fn) ~= "function" then
			return { Disconnect = function() end, Connected = false }
		end
		local conn = { _fn = fn, Connected = true }
		function conn:Disconnect()
			if not self.Connected then return end
			self.Connected = false
			for i = #handlers, 1, -1 do
				if handlers[i] == self then
					table.remove(handlers, i)
					break
				end
			end
		end
		table.insert(handlers, conn)
		return conn
	end

	function api:Once(fn)
		local conn
		conn = api:Connect(function(...)
			conn:Disconnect()
			fn(...)
		end)
		return conn
	end

	function api:Fire(...)
		if destroyed then return end
		local snap = table.clone(handlers)
		for _, c in ipairs(snap) do
			if c.Connected then
				task.spawn(c._fn, ...)
			end
		end
	end

	function api:DisconnectAll()
		for _, c in ipairs(handlers) do
			c.Connected = false
		end
		table.clear(handlers)
	end

	function api:Destroy()
		if destroyed then return end
		destroyed = true
		api:DisconnectAll()
	end

	function api:IsDestroyed()
		return destroyed
	end

	return api
end

-- Standard Roblox client parenting. This library is designed for LocalScripts in
-- experiences you own; it does not parent UI into CoreGui or executor-specific roots.
local function ProtectAndParent(sg)
    sg.ResetOnSpawn = false
    sg.Parent = PlayerGui
end

----------------------------------------------------------------
-- THEME
----------------------------------------------------------------
local Theme = {
	Background = Color3.fromRGB(12, 12, 14),
	Secondary = Color3.fromRGB(18, 18, 22),
	Tertiary = Color3.fromRGB(24, 24, 28),
	Hover = Color3.fromRGB(28, 28, 34),
	Text = Color3.fromRGB(240, 240, 245),
	SecondaryText = Color3.fromRGB(150, 150, 160),
	MutedText = Color3.fromRGB(100, 100, 110),
	Accent = Color3.fromRGB(145, 118, 255),
	Accent2 = Color3.fromRGB(63, 224, 213),
	Border = Color3.fromRGB(76, 79, 106),
	ToggleOn = Color3.fromRGB(255, 255, 255),
	ToggleOff = Color3.fromRGB(50, 50, 58),
	SliderTrack = Color3.fromRGB(35, 35, 42),
	SliderFill = Color3.fromRGB(255, 255, 255),
	NotificationBackground = Color3.fromRGB(8, 8, 10),
	NotificationBorder = Color3.fromRGB(30, 30, 36),
	NotificationTitle = Color3.fromRGB(245, 245, 250),
	NotificationDescription = Color3.fromRGB(160, 160, 170),
	NotificationInfo = Color3.fromRGB(100, 160, 255),
	NotificationSuccess = Color3.fromRGB(80, 200, 120),
	NotificationWarning = Color3.fromRGB(255, 180, 60),
	NotificationError = Color3.fromRGB(255, 80, 80),
	Font = Enum.Font.GothamMedium,
	FontBold = Enum.Font.GothamBold,
	FontMono = Enum.Font.Code,
	CornerRadius = 6,
	ElementHeight = 36,
	AnimationSpeed = 0.35,
	HoverSpeed = 0.15,
}

-- Built-in presets (use Library:ApplyTheme("Light") or SetTheme(ThemePresets.Light))
local ThemePresets = {
	Dark = {
		Background = Color3.fromRGB(12, 12, 14),
		Secondary = Color3.fromRGB(18, 18, 22),
		Tertiary = Color3.fromRGB(24, 24, 28),
		Hover = Color3.fromRGB(28, 28, 34),
		Text = Color3.fromRGB(240, 240, 245),
		SecondaryText = Color3.fromRGB(150, 150, 160),
		MutedText = Color3.fromRGB(100, 100, 110),
		Accent = Color3.fromRGB(255, 255, 255),
		Border = Color3.fromRGB(40, 40, 48),
		ToggleOn = Color3.fromRGB(255, 255, 255),
		ToggleOff = Color3.fromRGB(50, 50, 58),
		SliderTrack = Color3.fromRGB(35, 35, 42),
		SliderFill = Color3.fromRGB(255, 255, 255),
		NotificationBackground = Color3.fromRGB(8, 8, 10),
		NotificationBorder = Color3.fromRGB(30, 30, 36),
		NotificationTitle = Color3.fromRGB(245, 245, 250),
		NotificationDescription = Color3.fromRGB(160, 160, 170),
		NotificationInfo = Color3.fromRGB(100, 160, 255),
		NotificationSuccess = Color3.fromRGB(80, 200, 120),
		NotificationWarning = Color3.fromRGB(255, 180, 60),
		NotificationError = Color3.fromRGB(255, 80, 80),
	},
	Light = {
		Background = Color3.fromRGB(245, 245, 248),
		Secondary = Color3.fromRGB(255, 255, 255),
		Tertiary = Color3.fromRGB(235, 235, 240),
		Hover = Color3.fromRGB(225, 225, 232),
		Text = Color3.fromRGB(20, 20, 28),
		SecondaryText = Color3.fromRGB(90, 90, 105),
		MutedText = Color3.fromRGB(140, 140, 155),
		Accent = Color3.fromRGB(30, 30, 40),
		Border = Color3.fromRGB(210, 210, 220),
		ToggleOn = Color3.fromRGB(40, 40, 50),
		ToggleOff = Color3.fromRGB(200, 200, 210),
		SliderTrack = Color3.fromRGB(220, 220, 230),
		SliderFill = Color3.fromRGB(40, 40, 50),
		NotificationBackground = Color3.fromRGB(255, 255, 255),
		NotificationBorder = Color3.fromRGB(220, 220, 230),
		NotificationTitle = Color3.fromRGB(20, 20, 28),
		NotificationDescription = Color3.fromRGB(90, 90, 105),
		NotificationInfo = Color3.fromRGB(40, 120, 220),
		NotificationSuccess = Color3.fromRGB(30, 160, 90),
		NotificationWarning = Color3.fromRGB(210, 140, 30),
		NotificationError = Color3.fromRGB(210, 50, 50),
	},
	Neon = {
		Background = Color3.fromRGB(8, 6, 16),
		Secondary = Color3.fromRGB(14, 10, 28),
		Tertiary = Color3.fromRGB(22, 16, 40),
		Hover = Color3.fromRGB(32, 24, 56),
		Text = Color3.fromRGB(230, 220, 255),
		SecondaryText = Color3.fromRGB(160, 140, 220),
		MutedText = Color3.fromRGB(110, 90, 160),
		Accent = Color3.fromRGB(180, 80, 255),
		Border = Color3.fromRGB(60, 40, 100),
		ToggleOn = Color3.fromRGB(180, 80, 255),
		ToggleOff = Color3.fromRGB(40, 30, 70),
		SliderTrack = Color3.fromRGB(30, 20, 55),
		SliderFill = Color3.fromRGB(180, 80, 255),
		NotificationBackground = Color3.fromRGB(10, 8, 20),
		NotificationBorder = Color3.fromRGB(50, 30, 90),
		NotificationTitle = Color3.fromRGB(240, 230, 255),
		NotificationDescription = Color3.fromRGB(160, 140, 220),
		NotificationInfo = Color3.fromRGB(120, 160, 255),
		NotificationSuccess = Color3.fromRGB(80, 220, 160),
		NotificationWarning = Color3.fromRGB(255, 180, 80),
		NotificationError = Color3.fromRGB(255, 80, 120),
	},
}

-- Additional design systems in the same engine. They share behavior/API but
-- intentionally vary density, radius, font sizes, contrast, and accents.
local function CloneTheme(source)
    local out = {}
    for k, v in pairs(source) do out[k] = v end
    return out
end

ThemePresets.Lunar = CloneTheme(ThemePresets.Neon)
ThemePresets.Lunar.Background = Color3.fromRGB(12, 13, 20)
ThemePresets.Lunar.Secondary = Color3.fromRGB(19, 20, 31)
ThemePresets.Lunar.Tertiary = Color3.fromRGB(28, 29, 44)
ThemePresets.Lunar.Hover = Color3.fromRGB(38, 37, 58)
ThemePresets.Lunar.Text = Color3.fromRGB(244, 243, 255)
ThemePresets.Lunar.SecondaryText = Color3.fromRGB(166, 163, 193)
ThemePresets.Lunar.MutedText = Color3.fromRGB(112, 110, 142)
ThemePresets.Lunar.Accent = Color3.fromRGB(151, 124, 255)
ThemePresets.Lunar.Border = Color3.fromRGB(64, 60, 94)
ThemePresets.Lunar.ToggleOn = ThemePresets.Lunar.Accent
ThemePresets.Lunar.SliderFill = ThemePresets.Lunar.Accent
ThemePresets.Lunar.CornerRadius = 12
ThemePresets.Lunar.ElementHeight = 40

ThemePresets.Veyra = CloneTheme(ThemePresets.Dark)
ThemePresets.Veyra.Background = Color3.fromRGB(11, 13, 16)
ThemePresets.Veyra.Secondary = Color3.fromRGB(18, 22, 25)
ThemePresets.Veyra.Tertiary = Color3.fromRGB(25, 31, 34)
ThemePresets.Veyra.Hover = Color3.fromRGB(32, 43, 44)
ThemePresets.Veyra.Text = Color3.fromRGB(241, 246, 245)
ThemePresets.Veyra.SecondaryText = Color3.fromRGB(157, 175, 174)
ThemePresets.Veyra.MutedText = Color3.fromRGB(103, 126, 125)
ThemePresets.Veyra.Accent = Color3.fromRGB(75, 211, 190)
ThemePresets.Veyra.Border = Color3.fromRGB(45, 64, 64)
ThemePresets.Veyra.ToggleOn = ThemePresets.Veyra.Accent
ThemePresets.Veyra.SliderFill = ThemePresets.Veyra.Accent
ThemePresets.Veyra.CornerRadius = 9
ThemePresets.Veyra.ElementHeight = 38

ThemePresets.Skeet = CloneTheme(ThemePresets.Dark)
ThemePresets.Skeet.Background = Color3.fromRGB(14, 14, 17)
ThemePresets.Skeet.Secondary = Color3.fromRGB(20, 20, 24)
ThemePresets.Skeet.Tertiary = Color3.fromRGB(27, 28, 33)
ThemePresets.Skeet.Hover = Color3.fromRGB(35, 38, 42)
ThemePresets.Skeet.Text = Color3.fromRGB(230, 233, 235)
ThemePresets.Skeet.SecondaryText = Color3.fromRGB(157, 164, 168)
ThemePresets.Skeet.MutedText = Color3.fromRGB(108, 115, 119)
ThemePresets.Skeet.Accent = Color3.fromRGB(139, 199, 92)
ThemePresets.Skeet.Border = Color3.fromRGB(49, 53, 56)
ThemePresets.Skeet.ToggleOn = ThemePresets.Skeet.Accent
ThemePresets.Skeet.SliderFill = ThemePresets.Skeet.Accent
ThemePresets.Skeet.CornerRadius = 5
ThemePresets.Skeet.ElementHeight = 32

ThemePresets.Material = CloneTheme(ThemePresets.Neon)
ThemePresets.Material.Background = Color3.fromRGB(246, 243, 255)
ThemePresets.Material.Secondary = Color3.fromRGB(255, 255, 255)
ThemePresets.Material.Tertiary = Color3.fromRGB(235, 228, 255)
ThemePresets.Material.Hover = Color3.fromRGB(224, 212, 255)
ThemePresets.Material.Text = Color3.fromRGB(55, 33, 92)
ThemePresets.Material.SecondaryText = Color3.fromRGB(100, 74, 145)
ThemePresets.Material.MutedText = Color3.fromRGB(140, 120, 176)
ThemePresets.Material.Accent = Color3.fromRGB(126, 57, 242)
ThemePresets.Material.Border = Color3.fromRGB(211, 193, 245)
ThemePresets.Material.ToggleOn = ThemePresets.Material.Accent
ThemePresets.Material.SliderFill = ThemePresets.Material.Accent
ThemePresets.Material.NotificationBackground = Color3.fromRGB(255, 255, 255)
ThemePresets.Material.NotificationBorder = Color3.fromRGB(211, 193, 245)
ThemePresets.Material.NotificationTitle = ThemePresets.Material.Text
ThemePresets.Material.NotificationDescription = ThemePresets.Material.SecondaryText
ThemePresets.Material.CornerRadius = 12
ThemePresets.Material.ElementHeight = 42

ThemePresets.Aurora = CloneTheme(ThemePresets.Veyra)
ThemePresets.Aurora.Accent = Color3.fromRGB(85, 230, 201)
ThemePresets.Aurora.ToggleOn = ThemePresets.Aurora.Accent
ThemePresets.Aurora.SliderFill = ThemePresets.Aurora.Accent
ThemePresets.Aurora.NotificationSuccess = Color3.fromRGB(94, 231, 178)
ThemePresets.Crimson = CloneTheme(ThemePresets.Dark)
ThemePresets.Crimson.Accent = Color3.fromRGB(246, 70, 91)
ThemePresets.Crimson.ToggleOn = ThemePresets.Crimson.Accent
ThemePresets.Crimson.SliderFill = ThemePresets.Crimson.Accent
ThemePresets.Crimson.Border = Color3.fromRGB(82, 36, 47)
ThemePresets.AMOLED = CloneTheme(ThemePresets.Dark)
ThemePresets.AMOLED.Background = Color3.fromRGB(0, 0, 0)
ThemePresets.AMOLED.Secondary = Color3.fromRGB(5, 5, 7)
ThemePresets.AMOLED.Tertiary = Color3.fromRGB(13, 13, 17)
ThemePresets.AMOLED.Hover = Color3.fromRGB(22, 22, 28)
ThemePresets.Ocean = CloneTheme(ThemePresets.Dark)
ThemePresets.Ocean.Accent = Color3.fromRGB(78, 160, 255)
ThemePresets.Ocean.ToggleOn = ThemePresets.Ocean.Accent
ThemePresets.Ocean.SliderFill = ThemePresets.Ocean.Accent
ThemePresets.Ocean.Background = Color3.fromRGB(7, 13, 23)
ThemePresets.Ocean.Secondary = Color3.fromRGB(13, 22, 36)
ThemePresets.Ocean.Tertiary = Color3.fromRGB(20, 34, 53)

-- PrismGlass is LunarUI's new visual direction: a dark, translucent canvas,
-- cool aurora gradients, brighter edge treatment, and tintable image layers.
-- Glass itself remains enabled regardless of which color preset is selected.
ThemePresets.PrismGlass = CloneTheme(ThemePresets.Dark)
ThemePresets.PrismGlass.Background = Color3.fromRGB(11, 13, 24)
ThemePresets.PrismGlass.Secondary = Color3.fromRGB(20, 22, 37)
ThemePresets.PrismGlass.Tertiary = Color3.fromRGB(30, 33, 53)
ThemePresets.PrismGlass.Hover = Color3.fromRGB(41, 45, 69)
ThemePresets.PrismGlass.Text = Color3.fromRGB(246, 248, 255)
ThemePresets.PrismGlass.SecondaryText = Color3.fromRGB(184, 193, 217)
ThemePresets.PrismGlass.MutedText = Color3.fromRGB(131, 143, 171)
ThemePresets.PrismGlass.Accent = Color3.fromRGB(151, 124, 255)
ThemePresets.PrismGlass.Accent2 = Color3.fromRGB(66, 226, 213)
ThemePresets.PrismGlass.Border = Color3.fromRGB(116, 130, 178)
ThemePresets.PrismGlass.ToggleOn = ThemePresets.PrismGlass.Accent
ThemePresets.PrismGlass.SliderFill = ThemePresets.PrismGlass.Accent
ThemePresets.PrismGlass.CornerRadius = 14
ThemePresets.PrismGlass.ElementHeight = 42
ThemePresets.PrismGlass.NotificationBackground = Color3.fromRGB(15, 18, 31)
ThemePresets.PrismGlass.NotificationBorder = Color3.fromRGB(91, 104, 148)
ThemePresets.PrismGlass.NotificationTitle = ThemePresets.PrismGlass.Text
ThemePresets.PrismGlass.NotificationDescription = ThemePresets.PrismGlass.SecondaryText

ThemePresets.Frost = CloneTheme(ThemePresets.PrismGlass)
ThemePresets.Frost.Background = Color3.fromRGB(21, 29, 43)
ThemePresets.Frost.Secondary = Color3.fromRGB(29, 41, 59)
ThemePresets.Frost.Tertiary = Color3.fromRGB(39, 54, 75)
ThemePresets.Frost.Hover = Color3.fromRGB(50, 68, 93)
ThemePresets.Frost.Accent = Color3.fromRGB(127, 210, 255)
ThemePresets.Frost.Accent2 = Color3.fromRGB(188, 158, 255)
ThemePresets.Frost.Border = Color3.fromRGB(141, 189, 219)
ThemePresets.Frost.ToggleOn = ThemePresets.Frost.Accent
ThemePresets.Frost.SliderFill = ThemePresets.Frost.Accent

ThemePresets.MidnightGlass = CloneTheme(ThemePresets.PrismGlass)
ThemePresets.MidnightGlass.Background = Color3.fromRGB(5, 6, 13)
ThemePresets.MidnightGlass.Secondary = Color3.fromRGB(10, 12, 23)
ThemePresets.MidnightGlass.Tertiary = Color3.fromRGB(19, 22, 38)
ThemePresets.MidnightGlass.Accent = Color3.fromRGB(176, 128, 255)
ThemePresets.MidnightGlass.Accent2 = Color3.fromRGB(70, 162, 255)
ThemePresets.MidnightGlass.Border = Color3.fromRGB(91, 79, 135)


-- Additional original palettes inspired by broad design patterns in modern UI
-- frameworks. These are LunarUI-authored tokens, not copied source or assets.
ThemePresets.FluentGlass = CloneTheme(ThemePresets.PrismGlass)
ThemePresets.FluentGlass.Background = Color3.fromRGB(13, 19, 27)
ThemePresets.FluentGlass.Secondary = Color3.fromRGB(21, 31, 42)
ThemePresets.FluentGlass.Tertiary = Color3.fromRGB(29, 43, 58)
ThemePresets.FluentGlass.Hover = Color3.fromRGB(38, 57, 75)
ThemePresets.FluentGlass.Accent = Color3.fromRGB(83, 197, 255)
ThemePresets.FluentGlass.Accent2 = Color3.fromRGB(122, 240, 216)
ThemePresets.FluentGlass.Border = Color3.fromRGB(87, 140, 167)
ThemePresets.FluentGlass.ToggleOn = ThemePresets.FluentGlass.Accent
ThemePresets.FluentGlass.SliderFill = ThemePresets.FluentGlass.Accent

ThemePresets.OrionClean = CloneTheme(ThemePresets.Dark)
ThemePresets.OrionClean.Background = Color3.fromRGB(16, 18, 25)
ThemePresets.OrionClean.Secondary = Color3.fromRGB(24, 27, 37)
ThemePresets.OrionClean.Tertiary = Color3.fromRGB(33, 37, 50)
ThemePresets.OrionClean.Hover = Color3.fromRGB(45, 50, 66)
ThemePresets.OrionClean.Accent = Color3.fromRGB(150, 125, 255)
ThemePresets.OrionClean.Accent2 = Color3.fromRGB(108, 207, 255)
ThemePresets.OrionClean.Border = Color3.fromRGB(79, 83, 111)
ThemePresets.OrionClean.ToggleOn = ThemePresets.OrionClean.Accent
ThemePresets.OrionClean.SliderFill = ThemePresets.OrionClean.Accent

ThemePresets.LinoriaGraphite = CloneTheme(ThemePresets.Dark)
ThemePresets.LinoriaGraphite.Background = Color3.fromRGB(18, 19, 21)
ThemePresets.LinoriaGraphite.Secondary = Color3.fromRGB(25, 27, 30)
ThemePresets.LinoriaGraphite.Tertiary = Color3.fromRGB(34, 37, 41)
ThemePresets.LinoriaGraphite.Hover = Color3.fromRGB(47, 51, 56)
ThemePresets.LinoriaGraphite.Accent = Color3.fromRGB(120, 215, 180)
ThemePresets.LinoriaGraphite.Accent2 = Color3.fromRGB(144, 183, 255)
ThemePresets.LinoriaGraphite.Border = Color3.fromRGB(74, 80, 88)
ThemePresets.LinoriaGraphite.ToggleOn = ThemePresets.LinoriaGraphite.Accent
ThemePresets.LinoriaGraphite.SliderFill = ThemePresets.LinoriaGraphite.Accent

ThemePresets.AcrylicIce = CloneTheme(ThemePresets.Frost)
ThemePresets.AcrylicIce.Background = Color3.fromRGB(13, 25, 43)
ThemePresets.AcrylicIce.Secondary = Color3.fromRGB(23, 40, 62)
ThemePresets.AcrylicIce.Tertiary = Color3.fromRGB(34, 56, 83)
ThemePresets.AcrylicIce.Hover = Color3.fromRGB(48, 76, 108)
ThemePresets.AcrylicIce.Accent = Color3.fromRGB(112, 201, 255)
ThemePresets.AcrylicIce.Accent2 = Color3.fromRGB(182, 167, 255)
ThemePresets.AcrylicIce.Border = Color3.fromRGB(112, 164, 209)
ThemePresets.AcrylicIce.ToggleOn = ThemePresets.AcrylicIce.Accent
ThemePresets.AcrylicIce.SliderFill = ThemePresets.AcrylicIce.Accent

local ThemeListeners = {}

local function GetTheme()
	return Theme
end

local function SetTheme(t)
	if type(t) ~= "table" then return end
	for k, v in pairs(t) do
		Theme[k] = v
	end
	for _, fn in ipairs(ThemeListeners) do
		task.spawn(fn)
	end
end

local function ApplyThemePreset(name)
	local preset = ThemePresets[name]
	if not preset then
		warn("[LunarUI] Unknown theme preset:", tostring(name))
		return false
	end
	SetTheme(preset)
	return true
end

local function OnThemeChange(fn)
	table.insert(ThemeListeners, fn)
	return function()
		local i = table.find(ThemeListeners, fn)
		if i then table.remove(ThemeListeners, i) end
	end
end

----------------------------------------------------------------
-- CLEANUP
----------------------------------------------------------------
local function CreateCleanup()
	local connections, instances, tasks, callbacks = {}, {}, {}, {}
	local destroyed = false

	local api = {}

	function api:AddConnection(c)
		if destroyed then
			if c and c.Connected then c:Disconnect() end
			return
		end
		table.insert(connections, c)
	end

	function api:AddInstance(i)
		if destroyed then
			if i then i:Destroy() end
			return
		end
		table.insert(instances, i)
	end

	function api:AddTask(t)
		if destroyed then
			pcall(task.cancel, t)
			return
		end
		table.insert(tasks, t)
	end

	function api:AddCallback(fn)
		if destroyed then return end
		table.insert(callbacks, fn)
	end

	function api:Destroy()
		if destroyed then return end
		destroyed = true
		-- Cancel any running animations on tracked instances first
		for _, i in ipairs(instances) do
			if i then
				pcall(function() TweenEngine.CancelOnObject(i) end)
			end
		end
		for _, c in ipairs(connections) do
			if c and c.Connected then pcall(function() c:Disconnect() end) end
		end
		for _, i in ipairs(instances) do
			if i and i.Parent then pcall(function() i:Destroy() end) end
		end
		for _, t in ipairs(tasks) do
			pcall(task.cancel, t)
		end
		for _, fn in ipairs(callbacks) do
			pcall(fn)
		end
		table.clear(connections)
		table.clear(instances)
		table.clear(tasks)
		table.clear(callbacks)
	end

	function api:IsDestroyed()
		return destroyed
	end

	return api
end

----------------------------------------------------------------
-- EASING
----------------------------------------------------------------
local Easing = {}

function Easing.Linear(t) return t end
function Easing.QuadIn(t) return t * t end
function Easing.QuadOut(t) return t * (2 - t) end
function Easing.QuadInOut(t)
	if t < 0.5 then return 2 * t * t end
	return -1 + (4 - 2 * t) * t
end
function Easing.CubicIn(t) return t * t * t end
function Easing.CubicOut(t)
	local t1 = t - 1
	return t1 * t1 * t1 + 1
end
function Easing.CubicInOut(t)
	if t < 0.5 then return 4 * t * t * t end
	local t1 = 2 * t - 2
	return 0.5 * t1 * t1 * t1 + 1
end
function Easing.QuartIn(t) return t * t * t * t end
function Easing.QuartOut(t)
	local t1 = t - 1
	return 1 - t1 * t1 * t1 * t1
end
function Easing.QuartInOut(t)
	if t < 0.5 then return 8 * t * t * t * t end
	local t1 = t - 1
	return 1 - 8 * t1 * t1 * t1 * t1
end
function Easing.QuintIn(t) return t * t * t * t * t end
function Easing.QuintOut(t)
	local t1 = t - 1
	return 1 + t1 * t1 * t1 * t1 * t1
end
function Easing.QuintInOut(t)
	if t < 0.5 then return 16 * t * t * t * t * t end
	local t1 = 2 * t - 2
	return 0.5 * t1 * t1 * t1 * t1 * t1 + 1
end
function Easing.SineIn(t) return 1 - math.cos(t * math.pi / 2) end
function Easing.SineOut(t) return math.sin(t * math.pi / 2) end
function Easing.SineInOut(t) return -0.5 * (math.cos(math.pi * t) - 1) end
function Easing.CircularIn(t) return 1 - math.sqrt(1 - t * t) end
function Easing.CircularOut(t) return math.sqrt(1 - (t - 1) * (t - 1)) end
function Easing.CircularInOut(t)
	if t < 0.5 then return 0.5 * (1 - math.sqrt(1 - 4 * t * t)) end
	return 0.5 * (math.sqrt(1 - (2 * t - 2) * (2 * t - 2)) + 1)
end
function Easing.ExpoIn(t)
	if t == 0 then return 0 end
	return math.pow(2, 10 * (t - 1))
end
function Easing.ExpoOut(t)
	if t == 1 then return 1 end
	return 1 - math.pow(2, -10 * t)
end
function Easing.ExpoInOut(t)
	if t == 0 then return 0 end
	if t == 1 then return 1 end
	if t < 0.5 then return 0.5 * math.pow(2, 20 * t - 10) end
	return 1 - 0.5 * math.pow(2, -20 * t + 10)
end
function Easing.BackIn(t)
	local s = 1.70158
	return t * t * ((s + 1) * t - s)
end
function Easing.BackOut(t)
	local s = 1.70158
	local t1 = t - 1
	return t1 * t1 * ((s + 1) * t1 + s) + 1
end
function Easing.BackInOut(t)
	local s = 1.70158 * 1.525
	if t < 0.5 then
		return 0.5 * (t * 2) * (t * 2) * ((s + 1) * (t * 2) - s)
	end
	local t1 = t * 2 - 2
	return 0.5 * (t1 * t1 * ((s + 1) * t1 + s) + 2)
end
function Easing.ElasticIn(t)
	if t == 0 or t == 1 then return t end
	return -math.pow(2, 10 * (t - 1)) * math.sin((t - 1.1) * 5 * math.pi)
end
function Easing.ElasticOut(t)
	if t == 0 or t == 1 then return t end
	return math.pow(2, -10 * t) * math.sin((t - 0.1) * 5 * math.pi) + 1
end
function Easing.ElasticInOut(t)
	if t == 0 or t == 1 then return t end
	t = t * 2
	if t < 1 then
		return -0.5 * math.pow(2, 10 * (t - 1)) * math.sin((t - 1.1) * 5 * math.pi)
	end
	return 0.5 * math.pow(2, -10 * (t - 1)) * math.sin((t - 1.1) * 5 * math.pi) + 1
end
function Easing.BounceOut(t)
	if t < 1 / 2.75 then
		return 7.5625 * t * t
	elseif t < 2 / 2.75 then
		t = t - 1.5 / 2.75
		return 7.5625 * t * t + 0.75
	elseif t < 2.5 / 2.75 then
		t = t - 2.25 / 2.75
		return 7.5625 * t * t + 0.9375
	else
		t = t - 2.625 / 2.75
		return 7.5625 * t * t + 0.984375
	end
end
function Easing.BounceIn(t) return 1 - Easing.BounceOut(1 - t) end
function Easing.BounceInOut(t)
	if t < 0.5 then return Easing.BounceIn(t * 2) * 0.5 end
	return Easing.BounceOut(t * 2 - 1) * 0.5 + 0.5
end

local EasingNamed = {
	Linear = Easing.Linear,
	QuadIn = Easing.QuadIn, QuadOut = Easing.QuadOut, QuadInOut = Easing.QuadInOut,
	CubicIn = Easing.CubicIn, CubicOut = Easing.CubicOut, CubicInOut = Easing.CubicInOut,
	QuartIn = Easing.QuartIn, QuartOut = Easing.QuartOut, QuartInOut = Easing.QuartInOut,
	QuintIn = Easing.QuintIn, QuintOut = Easing.QuintOut, QuintInOut = Easing.QuintInOut,
	SineIn = Easing.SineIn, SineOut = Easing.SineOut, SineInOut = Easing.SineInOut,
	CircularIn = Easing.CircularIn, CircularOut = Easing.CircularOut, CircularInOut = Easing.CircularInOut,
	ExpoIn = Easing.ExpoIn, ExpoOut = Easing.ExpoOut, ExpoInOut = Easing.ExpoInOut,
	BackIn = Easing.BackIn, BackOut = Easing.BackOut, BackInOut = Easing.BackInOut,
	ElasticIn = Easing.ElasticIn, ElasticOut = Easing.ElasticOut, ElasticInOut = Easing.ElasticInOut,
	BounceIn = Easing.BounceIn, BounceOut = Easing.BounceOut, BounceInOut = Easing.BounceInOut,
}

local function GetEasing(name)
	if type(name) == "function" then return name end
	return EasingNamed[name] or Easing.Linear
end

----------------------------------------------------------------
-- ANIMATION SCHEDULER + ENGINE (Hardened)
----------------------------------------------------------------
local ActiveAnims = {}
local SchedulerConn = nil
local AnimIdCounter = 0

local function SchedulerUpdate(dt)
	local remove = {}
	for id, anim in pairs(ActiveAnims) do
		if anim.Cancelled or anim._finished then
			table.insert(remove, id)
		else
			local ok, done = pcall(function()
				return anim:Update(dt)
			end)
			if not ok or done then
				anim._finished = true
				table.insert(remove, id)
				if ok and anim.OnComplete and not anim.Cancelled then
					-- Only fire OnComplete if not cancelled
					task.spawn(anim.OnComplete)
				end
			end
		end
	end
	for _, id in ipairs(remove) do
		local anim = ActiveAnims[id]
		if anim then
			anim.Id = nil
		end
		ActiveAnims[id] = nil
	end
	if next(ActiveAnims) == nil and SchedulerConn then
		SchedulerConn:Disconnect()
		SchedulerConn = nil
	end
end

local function SchedulerAdd(anim)
	if anim.Cancelled or anim._finished then
		return nil
	end
	AnimIdCounter += 1
	local id = "a" .. AnimIdCounter
	anim.Id = id
	ActiveAnims[id] = anim
	if not SchedulerConn then
		SchedulerConn = RunService.Heartbeat:Connect(SchedulerUpdate)
	end
	return id
end

local function SchedulerRemove(anim)
	if anim and anim.Id and ActiveAnims[anim.Id] then
		ActiveAnims[anim.Id] = nil
		anim.Id = nil
	end
end

-- Lerp helpers
local function LerpNumber(a, b, t) return a + (b - a) * t end
local function LerpColor3(a, b, t)
	return Color3.new(LerpNumber(a.R, b.R, t), LerpNumber(a.G, b.G, t), LerpNumber(a.B, b.B, t))
end
local function LerpVector2(a, b, t) return Vector2.new(LerpNumber(a.X, b.X, t), LerpNumber(a.Y, b.Y, t)) end
local function LerpVector3(a, b, t)
	return Vector3.new(LerpNumber(a.X, b.X, t), LerpNumber(a.Y, b.Y, t), LerpNumber(a.Z, b.Z, t))
end
local function LerpUDim(a, b, t)
	return UDim.new(LerpNumber(a.Scale, b.Scale, t), LerpNumber(a.Offset, b.Offset, t))
end
local function LerpUDim2(a, b, t)
	return UDim2.new(
		LerpNumber(a.X.Scale, b.X.Scale, t), LerpNumber(a.X.Offset, b.X.Offset, t),
		LerpNumber(a.Y.Scale, b.Y.Scale, t), LerpNumber(a.Y.Offset, b.Y.Offset, t)
	)
end
local function LerpCFrame(a, b, t) return a:Lerp(b, t) end

local function GetLerp(v)
	local t = typeof(v)
	if t == "number" then return LerpNumber
	elseif t == "Color3" then return LerpColor3
	elseif t == "Vector2" then return LerpVector2
	elseif t == "Vector3" then return LerpVector3
	elseif t == "UDim" then return LerpUDim
	elseif t == "UDim2" then return LerpUDim2
	elseif t == "CFrame" then return LerpCFrame
	end
	return nil
end

local Animation = {}
Animation.__index = Animation

function Animation.new(object, goals, options)
	local self = setmetatable({}, Animation)
	options = options or {}
	self.Object = object
	self.Goals = goals
	self.Duration = math.max(options.Duration or 0.4, 0.001)
	self.Delay = options.Delay or 0
	self.EasingFn = GetEasing(options.Easing or "QuadOut")
	self.OnComplete = options.OnComplete
	self.Loop = options.Loop or false
	self.Yoyo = options.Yoyo or false
	self.Cancelled = false
	self._finished = false
	self.Elapsed = 0
	self.Started = false
	self.Direction = 1
	self.StartValues = {}
	self.LerpFns = {}
	self.Id = nil

	for prop, goal in pairs(goals) do
		local ok, current = pcall(function() return object[prop] end)
		if ok and current ~= nil then
			self.StartValues[prop] = current
			self.LerpFns[prop] = GetLerp(current)
		end
	end
	return self
end

function Animation:Update(dt)
	if self.Cancelled or self._finished then return true end
	-- Destroyed UI objects must not keep a Heartbeat animation alive until its
	-- original duration expires. This also makes reload/close cleanup reliable.
	if not self.Object or not self.Object.Parent then
		-- Treat removal as a completed step (not a cancellation) so parallel and
		-- sequential controllers can release their bookkeeping safely.
		self._finished = true
		return true
	end

	if not self.Started then
		self.Elapsed += dt
		if self.Elapsed < self.Delay then return false end
		self.Started = true
		self.Elapsed = 0
	end

	self.Elapsed += dt
	local alpha = math.clamp(self.Elapsed / self.Duration, 0, 1)
	local eased = self.EasingFn(alpha)

	for prop, goal in pairs(self.Goals) do
		local lerp = self.LerpFns[prop]
		local start = self.StartValues[prop]
		if lerp and start ~= nil then
			local value = (self.Direction > 0) and lerp(start, goal, eased) or lerp(goal, start, eased)
			pcall(function()
				if self.Object and self.Object.Parent then
					self.Object[prop] = value
				end
			end)
		end
	end

	if self.Elapsed >= self.Duration then
		if self.Yoyo and self.Direction > 0 then
			-- First leg is complete: reverse toward the captured start values.
			self.Direction = -1
			self.Elapsed = 0
			return false
		elseif self.Yoyo and self.Loop then
			-- A looping yoyo repeats full out-and-back cycles.
			self.Direction = 1
			self.Elapsed = 0
			return false
		elseif self.Loop then
			self.Elapsed = 0
			return false
		else
			for prop, goal in pairs(self.Goals) do
				local final = (self.Direction > 0) and goal or self.StartValues[prop]
				pcall(function()
					if self.Object and self.Object.Parent then
						self.Object[prop] = final
					end
				end)
			end
			self._finished = true
			return true
		end
	end
	return false
end

function Animation:Cancel()
	if self.Cancelled or self._finished then return end
	self.Cancelled = true
	self._finished = true
	-- Do not fire OnComplete on cancel
	self.OnComplete = nil
	SchedulerRemove(self)
end

function Animation:Play()
	if self.Cancelled or self._finished then return self end
	self.Id = SchedulerAdd(self)
	return self
end

local TweenEngine = {}

function TweenEngine.Play(object, goals, options)
	if not object or not object.Parent or type(goals) ~= "table" then return nil end
	local ok, anim = pcall(Animation.new, object, goals, options)
	if not ok or not anim then
		warn("[LunarUI][Tween] Could not create tween:", anim)
		return nil
	end
	return anim:Play()
end

-- Plays multiple motion steps concurrently. Each step is
-- {Object=Instance, Goals={...}, Options={...}}.
function TweenEngine.Parallel(steps, onComplete)
	local controller = {Cancelled=false, Active={}, Remaining=0}
	if type(steps) ~= "table" then
		if type(onComplete) == "function" then task.spawn(onComplete) end
		return controller
	end
	local count = #steps
	controller.Remaining = count
	local function finishOne()
		if controller.Cancelled then return end
		controller.Remaining -= 1
		if controller.Remaining <= 0 then
			controller.Completed = true
			if type(onComplete) == "function" then task.spawn(onComplete) end
		end
	end
	if count == 0 then
		controller.Completed = true
		if type(onComplete) == "function" then task.spawn(onComplete) end
		return controller
	end
	for index, step in ipairs(steps) do
		if type(step) == "table" and step.Object and type(step.Goals) == "table" then
			local opts = type(step.Options) == "table" and table.clone(step.Options) or {}
			local prior = opts.OnComplete
			opts.OnComplete = function()
				if type(prior) == "function" then pcall(prior) end
				finishOne()
			end
			controller.Active[index] = TweenEngine.Play(step.Object, step.Goals, opts)
			if not controller.Active[index] then finishOne() end
		else
			finishOne()
		end
	end
	function controller:Cancel()
		if self.Cancelled or self.Completed then return end
		self.Cancelled = true
		for _, animation in pairs(self.Active) do
			if animation and animation.Cancel then pcall(function() animation:Cancel() end) end
		end
		table.clear(self.Active)
	end
	return controller
end

-- Sequential counterpart. The next step begins only after the current tween
-- finishes; if a step cannot be created, the sequence safely advances.
function TweenEngine.Sequence(steps, onComplete)
	local controller = {Cancelled=false, Active={}, Index=0, Completed=false}
	if type(steps) ~= "table" or #steps == 0 then
		controller.Completed = true
		if type(onComplete) == "function" then task.spawn(onComplete) end
		return controller
	end
	local playNext
	playNext = function()
		if controller.Cancelled or controller.Completed then return end
		controller.Index += 1
		local step = steps[controller.Index]
		if not step then
			controller.Completed = true
			if type(onComplete) == "function" then task.spawn(onComplete) end
			return
		end
		if type(step) ~= "table" or not step.Object or type(step.Goals) ~= "table" then
			playNext()
			return
		end
		local stepIndex = controller.Index
		local opts = type(step.Options) == "table" and table.clone(step.Options) or {}
		local prior = opts.OnComplete
		opts.OnComplete = function()
			if type(prior) == "function" then pcall(prior) end
			controller.Active[stepIndex] = nil
			playNext()
		end
		local animation = TweenEngine.Play(step.Object, step.Goals, opts)
		controller.Active[stepIndex] = animation
		if not animation then controller.Active[stepIndex] = nil; playNext() end
	end
	function controller:Cancel()
		if self.Cancelled or self.Completed then return end
		self.Cancelled = true
		for _, animation in pairs(self.Active) do
			if animation and animation.Cancel then pcall(function() animation:Cancel() end) end
		end
		table.clear(self.Active)
	end
	task.defer(playNext)
	return controller
end

function TweenEngine.Spring(object, property, target, options)
	if not object or not object.Parent then return nil end
	options = options or {}
	local stiffness = options.Stiffness or 180
	local damping = options.Damping or 18
	local mass = options.Mass or 1

	local spring = setmetatable({}, Animation)
	spring.Object = object
	spring.Cancelled = false
	spring._finished = false
	spring.OnComplete = options.OnComplete
	spring.Property = property
	spring.Target = target
	spring.Stiffness = stiffness
	spring.Damping = damping
	spring.Mass = mass
	spring.Velocity = 0
	spring.Id = nil

	local ok, current = pcall(function() return object[property] end)
	if not ok then return nil end
	spring.Current = current

	function spring:Update(dt)
		if self.Cancelled or self._finished then return true end
		if not self.Object or not self.Object.Parent then
			self._finished = true
			return true
		end
		if typeof(self.Current) == "number" then
			local force = -self.Stiffness * (self.Current - self.Target)
			local damp = -self.Damping * self.Velocity
			local accel = (force + damp) / self.Mass
			self.Velocity += accel * dt
			self.Current += self.Velocity * dt
			pcall(function() self.Object[self.Property] = self.Current end)
			if math.abs(self.Current - self.Target) < 0.001 and math.abs(self.Velocity) < 0.001 then
				pcall(function() self.Object[self.Property] = self.Target end)
				self._finished = true
				return true
			end
		elseif typeof(self.Current) == "UDim2" then
			local cx, cy = self.Current.X.Offset, self.Current.Y.Offset
			local tx, ty = self.Target.X.Offset, self.Target.Y.Offset
			self.Velocity = self.Velocity or Vector2.zero
			local forceX = -self.Stiffness * (cx - tx)
			local forceY = -self.Stiffness * (cy - ty)
			local vx = self.Velocity.X + (forceX - self.Damping * self.Velocity.X) / self.Mass * dt
			local vy = self.Velocity.Y + (forceY - self.Damping * self.Velocity.Y) / self.Mass * dt
			self.Velocity = Vector2.new(vx, vy)
			cx += vx * dt
			cy += vy * dt
			self.Current = UDim2.new(self.Current.X.Scale, cx, self.Current.Y.Scale, cy)
			pcall(function() self.Object[self.Property] = self.Current end)
			if math.abs(cx - tx) < 0.5 and math.abs(cy - ty) < 0.5 and math.abs(vx) < 1 and math.abs(vy) < 1 then
				pcall(function() self.Object[self.Property] = self.Target end)
				self._finished = true
				return true
			end
		else
			self._finished = true
			return true
		end
		return false
	end

	function spring:Cancel()
		if self.Cancelled or self._finished then return end
		self.Cancelled = true
		self._finished = true
		self.OnComplete = nil
		SchedulerRemove(self)
	end

	function spring:Play()
		if self.Cancelled or self._finished then return self end
		self.Id = SchedulerAdd(self)
		return self
	end
	return spring:Play()
end

function TweenEngine.Shake(object, options)
	if not object or not object.Parent then return nil end
	options = options or {}
	local magnitude = options.Magnitude or 4
	local duration = options.Duration or 0.3
	local frequency = options.Frequency or 25
	local property = options.Property or "Position"

	local ok, original = pcall(function() return object[property] end)
	if not ok then return nil end

	local shake = setmetatable({}, Animation)
	shake.Object = object
	shake.Cancelled = false
	shake._finished = false
	shake.OnComplete = options.OnComplete
	shake.Original = original
	shake.Elapsed = 0
	shake.Duration = duration
	shake.Magnitude = magnitude
	shake.Frequency = frequency
	shake.Property = property
	shake.Id = nil

	function shake:Update(dt)
		if self.Cancelled or self._finished then
			pcall(function()
				if self.Object and self.Object.Parent then
					self.Object[self.Property] = self.Original
				end
			end)
			return true
		end
		if not self.Object or not self.Object.Parent then
			self._finished = true
			return true
		end
		self.Elapsed += dt
		if self.Elapsed >= self.Duration then
			pcall(function() self.Object[self.Property] = self.Original end)
			self._finished = true
			return true
		end
		local progress = self.Elapsed / self.Duration
		local damp = 1 - progress
		local ox = math.sin(self.Elapsed * self.Frequency * math.pi * 2) * self.Magnitude * damp
		local oy = math.cos(self.Elapsed * self.Frequency * math.pi * 1.7) * self.Magnitude * damp * 0.7
		if typeof(self.Original) == "UDim2" then
			pcall(function()
				self.Object[self.Property] = UDim2.new(
					self.Original.X.Scale, self.Original.X.Offset + ox,
					self.Original.Y.Scale, self.Original.Y.Offset + oy
				)
			end)
		end
		return false
	end

	function shake:Cancel()
		if self.Cancelled or self._finished then return end
		self.Cancelled = true
		self._finished = true
		self.OnComplete = nil
		pcall(function()
			if self.Object and self.Object.Parent then
				self.Object[self.Property] = self.Original
			end
		end)
		SchedulerRemove(self)
	end

	function shake:Play()
		if self.Cancelled or self._finished then return self end
		self.Id = SchedulerAdd(self)
		return self
	end
	return shake:Play()
end

function TweenEngine.CancelAll()
	local snapshot = {}
	for _, anim in pairs(ActiveAnims) do snapshot[#snapshot + 1] = anim end
	for _, anim in ipairs(snapshot) do
		if anim and anim.Cancel then
			pcall(function() anim:Cancel() end)
		else
			if anim then anim.Cancelled = true; anim._finished = true; anim.OnComplete = nil end
		end
	end
	table.clear(ActiveAnims)
	if SchedulerConn then
		SchedulerConn:Disconnect()
		SchedulerConn = nil
	end
end

function TweenEngine.CancelOnObject(object)
	if not object then return end
	for id, anim in pairs(ActiveAnims) do
		if anim and anim.Object == object and not anim.Cancelled then
			anim:Cancel()
		end
	end
end

----------------------------------------------------------------
-- INPUT / DRAG
----------------------------------------------------------------
local function MakeDraggable(handle, target, options)
	options = options or {}
	target = target or handle
	local enabled = true
	local dragging = false
	local dragStart, startPos
	local conns = {}
	local activeMoveC, activeEndC = nil, nil

	local function clearDragConns()
		if activeMoveC then
			pcall(function() activeMoveC:Disconnect() end)
			activeMoveC = nil
		end
		if activeEndC then
			pcall(function() activeEndC:Disconnect() end)
			activeEndC = nil
		end
		dragging = false
	end

	local function update(input)
		local delta = input.Position - dragStart
		local newPos = UDim2.new(
			startPos.X.Scale, startPos.X.Offset + delta.X,
			startPos.Y.Scale, startPos.Y.Offset + delta.Y
		)
		target.Position = newPos
		if options.OnDrag then options.OnDrag(newPos, delta) end
	end

	table.insert(conns, handle.InputBegan:Connect(function(input)
		if not enabled then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			clearDragConns()
			dragging = true
			dragStart = input.Position
			startPos = target.Position
			if options.OnDragStart then options.OnDragStart() end

			activeMoveC = UserInputService.InputChanged:Connect(function(inp)
				if (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) and dragging then
					update(inp)
				end
			end)
			activeEndC = UserInputService.InputEnded:Connect(function(inp)
				if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
					dragging = false
					clearDragConns()
					if options.OnDragEnd then options.OnDragEnd() end
				end
			end)
		end
	end))

	return {
		SetEnabled = function(s) enabled = s end,
		Destroy = function()
			clearDragConns()
			for _, c in ipairs(conns) do
				pcall(function() c:Disconnect() end)
			end
			table.clear(conns)
		end
	}
end

----------------------------------------------------------------
-- TYPEWRITER
----------------------------------------------------------------
local function CreateTypewriter(label, options)
	options = options or {}
	local speed = options.Speed or 0.025
	local fullText = label.Text or ""
	local cancelled = false
	local finished = false
	local thread = nil

	local api = {}

	function api:Start(text)
		if text then fullText = text end
		cancelled = false
		finished = false
		label.Text = ""
		thread = task.spawn(function()
			for i = 1, #fullText do
				if cancelled then return end
				label.Text = string.sub(fullText, 1, i)
				local char = string.sub(fullText, i, i)
				local d = speed
				if char == "." or char == "!" or char == "?" then
					d = speed * 4
				elseif char == "," or char == ";" then
					d = speed * 2
				elseif char == " " then
					d = speed * 0.6
				end
				task.wait(d)
			end
			finished = true
			if options.OnComplete then options.OnComplete() end
		end)
	end

	function api:Finish()
		cancelled = true
		if thread then pcall(task.cancel, thread) end
		label.Text = fullText
		finished = true
	end

	function api:Cancel()
		cancelled = true
		if thread then pcall(task.cancel, thread) end
	end

	function api:IsFinished()
		return finished
	end

	return api
end

----------------------------------------------------------------
-- ETHEREAL SEPARATOR
----------------------------------------------------------------
local function CreateEtherealSeparator(parent)
	local container = Instance.new("Frame")
	container.Name = "EtherealSeparator"
	container.BackgroundTransparency = 1
	container.Size = UDim2.new(1, 0, 0, 8)
	container.BorderSizePixel = 0
	container.Parent = parent

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.BackgroundColor3 = Theme.NotificationTitle
	bar.BackgroundTransparency = 0.7
	bar.BorderSizePixel = 0
	bar.Size = UDim2.new(0.6, 0, 0, 1)
	bar.Position = UDim2.new(0.2, 0, 0.5, 0)
	bar.AnchorPoint = Vector2.new(0, 0.5)
	bar.Parent = container

	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.4),
		NumberSequenceKeypoint.new(0.5, 0.15),
		NumberSequenceKeypoint.new(0.8, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = bar

	local api = { Container = container, Bar = bar }

	function api:PlayIn(dur)
		dur = dur or 0.45
		bar.Size = UDim2.new(0, 0, 0, 1)
		bar.BackgroundTransparency = 1
		bar.Position = UDim2.new(0.5, 0, 0.5, 0)
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		TweenEngine.Play(bar, {
			Size = UDim2.new(0.7, 0, 0, 1),
			BackgroundTransparency = 0.65,
			Position = UDim2.new(0.15, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
		}, { Duration = dur, Easing = "ExpoOut" })
	end

	function api:PlayOut(dur)
		dur = dur or 0.25
		TweenEngine.Play(bar, {
			Size = UDim2.new(0, 0, 0, 1),
			BackgroundTransparency = 1,
			Position = UDim2.new(0.5, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
		}, { Duration = dur, Easing = "QuadIn" })
	end

	function api:Destroy()
		if container then container:Destroy() end
	end

	return api
end

----------------------------------------------------------------
-- NOTIFICATION SYSTEM (LunarUI Prism / Hybrid-inspired)
-- A separate visual language from the old Veyra card: glass rail, status
-- beacon, compact metadata, hover pause, close affordance, action buttons,
-- queue animation, and per-notification accent/tint customization.
local NotificationManager = {}
NotificationManager.__index = NotificationManager

local NOTIF_WIDTH = 356
local NOTIF_GAP = 10
local NOTIF_MAX = 8

local NOTIF_TYPES = {
    Info = {Glyph = "i", Theme = "NotificationInfo"},
    Success = {Glyph = "✓", Theme = "NotificationSuccess"},
    Warning = {Glyph = "!", Theme = "NotificationWarning"},
    Error = {Glyph = "×", Theme = "NotificationError"},
    Custom = {Glyph = "◆", Theme = "Accent"},
}

local function _notifColor(config)
    if config.Color and typeof(config.Color) == "Color3" then return config.Color end
    local spec = NOTIF_TYPES[config.Type or "Info"] or NOTIF_TYPES.Info
    return Theme[spec.Theme] or Theme.Accent
end

function NotificationManager.new()
    local self = setmetatable({}, NotificationManager)
    self.Notifications = {}
    self.MaxNotifications = NOTIF_MAX
    self.Spacing = NOTIF_GAP
    self.Gui = Instance.new("ScreenGui")
    self.Gui.Name = "LunarUI_Notifications"
    self.Gui.ResetOnSpawn = false
    self.Gui.IgnoreGuiInset = true
    self.Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    self.Gui.DisplayOrder = 2147483647
    ProtectAndParent(self.Gui)

    self.Container = Instance.new("Frame")
    self.Container.Name = "Stack"
    self.Container.BackgroundTransparency = 1
    self.Container.AnchorPoint = Vector2.new(1, 0)
    self.Container.Position = UDim2.new(1, -18, 0, 18)
    self.Container.Size = UDim2.new(0, NOTIF_WIDTH, 1, -36)
    self.Container.Parent = self.Gui

    self._themeUnsubscribe = OnThemeChange(function()
        for _, n in ipairs(self.Notifications) do
            if n and not n.Closed then pcall(function() n:RefreshTheme() end) end
        end
    end)
    return self
end

function NotificationManager:_reflow(animated)
    local y = 0
    for i = 1, #self.Notifications do
        local n = self.Notifications[i]
        if n and not n.Closed and n.Frame and n.Frame.Parent then
            local h = math.max(n.Frame.AbsoluteSize.Y, 72)
            local target = UDim2.new(0, 0, 0, y)
            if animated then
                TweenEngine.Play(n.Frame, {Position = target}, {Duration = .32, Easing = "QuintOut"})
            else
                n.Frame.Position = target
            end
            y += h + self.Spacing
        end
    end
end

function NotificationManager:Notify(config)
    config = config or {}
    local duration = config.Duration
    if duration == nil then duration = config.Length end
    if duration == nil then duration = 5 end

    local ntype = config.Type or "Info"
    local spec = NOTIF_TYPES[ntype] or NOTIF_TYPES.Info
    local accent = _notifColor(config)
    local titleText = tostring(config.Title or "LunarUI")
    local descText = tostring(config.Description or config.Content or "")
    local iconText = tostring(config.Glyph or spec.Glyph)
    local imageId = config.Image or config.Icon
    local paused = false
    local closed = false
    local remaining = duration
    local startedAt = os.clock()

    local frame = Instance.new("Frame")
    frame.Name = "LunarToast"
    frame.Size = UDim2.new(0, NOTIF_WIDTH, 0, 0)
    frame.AutomaticSize = Enum.AutomaticSize.Y
    frame.BackgroundColor3 = Theme.Secondary
    frame.BackgroundTransparency = .16
    frame.BorderSizePixel = 0
    frame.ClipsDescendants = true
    frame.Position = UDim2.new(0, NOTIF_WIDTH + 30, 0, 0)
    frame.ZIndex = 100
    frame.Parent = self.Container

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 17)
    corner.Parent = frame

    local glass = Instance.new("UIGradient")
    glass.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, accent:Lerp(Color3.new(1,1,1), .12)),
        ColorSequenceKeypoint.new(.28, Theme.Secondary),
        ColorSequenceKeypoint.new(1, Theme.Tertiary),
    })
    glass.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, .04),
        NumberSequenceKeypoint.new(.55, .18),
        NumberSequenceKeypoint.new(1, .08),
    })
    glass.Rotation = 18
    glass.Parent = frame

    local edge = Instance.new("UIStroke")
    edge.Color = accent
    edge.Transparency = .42
    edge.Thickness = 1
    edge.Parent = frame

    local sheen = Instance.new("Frame")
    sheen.Name = "Sheen"
    sheen.BackgroundColor3 = Color3.new(1,1,1)
    sheen.BackgroundTransparency = .94
    sheen.BorderSizePixel = 0
    sheen.Size = UDim2.new(1, 0, 0, 1)
    sheen.Position = UDim2.new(0,0,0,0)
    sheen.ZIndex = 102
    sheen.Parent = frame

    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 13)
    pad.PaddingRight = UDim.new(0, 12)
    pad.PaddingTop = UDim.new(0, 12)
    pad.PaddingBottom = UDim.new(0, 12)
    pad.Parent = frame

    local row = Instance.new("Frame")
    row.BackgroundTransparency = 1
    row.Size = UDim2.new(1, 0, 0, 42)
    row.Parent = frame

    local beacon = Instance.new("Frame")
    beacon.Size = UDim2.new(0, 38, 0, 38)
    beacon.Position = UDim2.new(0,0,.5,-19)
    beacon.BackgroundColor3 = accent
    beacon.BackgroundTransparency = .78
    beacon.Parent = row
    local bc = Instance.new("UICorner"); bc.CornerRadius=UDim.new(1,0); bc.Parent=beacon
    local bicon = Instance.new("TextLabel")
    bicon.BackgroundTransparency=1; bicon.Size=UDim2.new(1,0,1,0)
    bicon.Font=Enum.Font.GothamBold; bicon.TextSize=16; bicon.Text=iconText
    bicon.TextColor3=Color3.new(1,1,1); bicon.Parent=beacon

    local textWrap = Instance.new("Frame")
    textWrap.BackgroundTransparency=1
    textWrap.Position=UDim2.new(0,50,0,0)
    textWrap.Size=UDim2.new(1,-88,1,0)
    textWrap.Parent=row

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency=1
    title.Size=UDim2.new(1,0,0,20)
    title.Font=Theme.FontBold; title.TextSize=14; title.TextXAlignment=Enum.TextXAlignment.Left
    title.TextColor3=Theme.Text; title.Text=titleText; title.Parent=textWrap

    local meta = Instance.new("TextLabel")
    meta.BackgroundTransparency=1
    meta.Position=UDim2.new(0,0,0,20); meta.Size=UDim2.new(1,0,0,17)
    meta.Font=Theme.Font; meta.TextSize=10; meta.TextXAlignment=Enum.TextXAlignment.Left
    meta.TextColor3=accent; meta.Text=string.upper(ntype); meta.Parent=textWrap

    local close = Instance.new("TextButton")
    close.BackgroundTransparency=1; close.Size=UDim2.new(0,25,0,25)
    close.Position=UDim2.new(1,-25,.5,-12); close.Text="×"
    close.Font=Enum.Font.GothamMedium; close.TextSize=18; close.TextColor3=Theme.SecondaryText
    close.Parent=row

    local desc = Instance.new("TextLabel")
    desc.BackgroundTransparency=1
    desc.AutomaticSize=Enum.AutomaticSize.Y
    desc.Size=UDim2.new(1,0,0,0)
    desc.Position=UDim2.new(0,0,0,47)
    desc.Font=Theme.Font; desc.TextSize=12; desc.TextWrapped=true
    desc.TextXAlignment=Enum.TextXAlignment.Left; desc.TextYAlignment=Enum.TextYAlignment.Top
    desc.TextColor3=Theme.SecondaryText; desc.Text=descText
    desc.Parent=frame

    local actionHolder = Instance.new("Frame")
    actionHolder.BackgroundTransparency=1
    actionHolder.AutomaticSize=Enum.AutomaticSize.Y
    actionHolder.Size=UDim2.new(1,0,0,0)
    actionHolder.Position=UDim2.new(0,0,0,0)
    actionHolder.Parent=frame
    local actionLayout = Instance.new("UIListLayout")
    actionLayout.FillDirection=Enum.FillDirection.Horizontal
    actionLayout.HorizontalAlignment=Enum.HorizontalAlignment.Right
    actionLayout.Padding=UDim.new(0,6)
    actionLayout.Parent=actionHolder

    if type(config.Actions) == "table" then
        for _, action in ipairs(config.Actions) do
            local btn = Instance.new("TextButton")
            btn.Size=UDim2.new(0, action.Width or 72, 0, 28)
            btn.BackgroundColor3=accent; btn.BackgroundTransparency=.72
            btn.Text=tostring(action.Name or action.Text or "Action")
            btn.Font=Theme.FontMedium; btn.TextSize=11; btn.TextColor3=Theme.Text
            btn.AutoButtonColor=false; btn.Parent=actionHolder
            local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,8); c.Parent=btn
            btn.Activated:Connect(function()
                safeCallback(action.Callback, n)
                if action.Close ~= false then n:Close() end
            end)
        end
    end

    local progressBack = Instance.new("Frame")
    progressBack.BackgroundColor3=Color3.new(1,1,1); progressBack.BackgroundTransparency=.9
    progressBack.BorderSizePixel=0; progressBack.Size=UDim2.new(1,0,0,2)
    progressBack.Position=UDim2.new(0,0,1,-2); progressBack.Parent=frame
    local progress=Instance.new("Frame")
    progress.BackgroundColor3=accent; progress.BorderSizePixel=0
    progress.Size=UDim2.new(1,0,1,0); progress.Parent=progressBack

    local cleanup = CreateCleanup()
    cleanup:AddInstance(frame)
    local notif = {
        Frame=frame, TitleLabel=title, DescLabel=desc, Closed=false, Config=config,
        Cleanup=cleanup, Manager=self, Accent=accent, Paused=false
    }

    function notif:RefreshTheme()
        title.TextColor3=Theme.Text
        desc.TextColor3=Theme.SecondaryText
        close.TextColor3=Theme.SecondaryText
        frame.BackgroundColor3=Theme.Secondary
        edge.Color=self.Accent
        beacon.BackgroundColor3=self.Accent
        meta.TextColor3=self.Accent
        progress.BackgroundColor3=self.Accent
    end

    function notif:Close()
        if closed then return end
        closed=true; self.Closed=true
        local idx=table.find(self.Manager.Notifications,self)
        if idx then table.remove(self.Manager.Notifications,idx) end
        TweenEngine.Play(frame,{
            Position=UDim2.new(0,NOTIF_WIDTH+30,0,frame.Position.Y.Offset),
            Size=UDim2.new(0,NOTIF_WIDTH,0,0),
            BackgroundTransparency=1,
        },{Duration=.28,Easing="QuintIn",OnComplete=function()
            cleanup:Destroy()
            self.Manager:_reflow(true)
        end})
    end

    function notif:SetTitle(v) title.Text=tostring(v); config.Title=v end
    function notif:SetDescription(v) desc.Text=tostring(v); config.Description=v end
    function notif:SetAccent(v)
        if typeof(v)~="Color3" then return end
        self.Accent=v; edge.Color=v; beacon.BackgroundColor3=v; meta.TextColor3=v; progress.BackgroundColor3=v
    end
    function notif:SetPaused(v) paused=v==true; self.Paused=paused end

    close.Activated:Connect(function() notif:Close() end)

    frame.MouseEnter:Connect(function()
        if config.PauseOnHover ~= false then
            paused=true; notif.Paused=true
        end
    end)
    frame.MouseLeave:Connect(function()
        if config.PauseOnHover ~= false then
            paused=false; notif.Paused=false
            startedAt=os.clock()
        end
    end)

    table.insert(self.Notifications,1,notif)
    while #self.Notifications > (self.MaxNotifications or NOTIF_MAX) do
        local old=self.Notifications[#self.Notifications]
        if old then old:Close() else table.remove(self.Notifications,#self.Notifications) end
    end

    task.defer(function()
        if closed then return end
        self:_reflow(true)
        frame.Position=UDim2.new(0,NOTIF_WIDTH+30,0,0)
        TweenEngine.Play(frame,{Position=UDim2.new(0,0,0,0),BackgroundTransparency=.16},
            {Duration=.42,Easing="BackOut"})
        TweenEngine.Play(sheen,{Position=UDim2.new(1,0,0,0)},{Duration=1.2,Easing="SineInOut"})
    end)

    if duration > 0 then
        task.spawn(function()
            local elapsed=0
            while not closed and elapsed < duration do
                task.wait(.05)
                if not paused then
                    elapsed += .05
                    local ratio=math.clamp(1-elapsed/duration,0,1)
                    progress.Size=UDim2.new(ratio,0,1,0)
                end
            end
            if not closed then notif:Close() end
        end)
    else
        progressBack.Visible=false
    end

    return notif
end

function NotificationManager:Remove(notif)
    if notif then notif:Close() end
end

function NotificationManager:Clear()
    for i=#self.Notifications,1,-1 do
        local n=self.Notifications[i]
        if n then n:Close() end
    end
end

function NotificationManager:Destroy()
    self:Clear()
    if self._themeUnsubscribe then pcall(self._themeUnsubscribe); self._themeUnsubscribe=nil end
    if self.Gui then self.Gui:Destroy() end
end

-- BUILT-IN LUCIDE-LIKE LINE ICONS (no dependency required)
-- IconProvider hooks allow a compatible Lucide.lua package to be supplied.
----------------------------------------------------------------
local VectorIcons = {
    home = { lines = {{3,10,12,3},{12,3,21,10},{5,9,5,21},{19,9,19,21},{5,21,19,21},{9,21,9,14},{9,14,15,14},{15,14,15,21}}, circles = {} },
    house = { lines = {{3,10,12,3},{12,3,21,10},{5,9,5,21},{19,9,19,21},{5,21,19,21},{9,21,9,14},{9,14,15,14},{15,14,15,21}}, circles = {} },
    search = { lines = {{16,16,22,22}}, circles = {{10,10,7}} },
    user = { lines = {{4,21,4,19},{4,19,7,15},{7,15,12,14},{12,14,17,15},{17,15,20,19},{20,19,20,21},{4,21,20,21}}, circles = {{12,7,4.2}} },
    settings = { lines = {{12,2,12,5},{12,19,12,22},{2,12,5,12},{19,12,22,12},{5,5,7,7},{17,17,19,19},{19,5,17,7},{7,17,5,19}}, circles = {{12,12,5}} },
    sliders = { lines = {{3,6,21,6},{3,12,21,12},{3,18,21,18}}, circles = {{8,6,3},{15,12,3},{10,18,3}} },
    palette = { lines = {{21,12,21,15},{21,15,19,18},{19,18,16,19}}, circles = {{12,12,9},{8,9,1},{12,6,1},{16,9,1},{8,15,1}} },
    code = { lines = {{8,6,3,12},{3,12,8,18},{16,6,21,12},{21,12,16,18},{14,4,10,20}}, circles = {} },
    terminal = { lines = {{5,6,10,12},{10,12,5,18},{13,18,19,18}}, circles = {} },
    bell = { lines = {{5,17,7,14},{7,14,7,10},{7,10,9,6},{9,6,12,5},{12,5,15,6},{15,6,17,10},{17,10,17,14},{17,14,19,17},{5,17,19,17},{10,20,14,20}}, circles = {} },
    monitor = { lines = {{3,4,21,4},{21,4,21,17},{21,17,3,17},{3,17,3,4},{12,17,12,21},{8,21,16,21}}, circles = {} },
    shield = { lines = {{12,2,20,5},{20,5,19,14},{19,14,12,22},{12,22,5,14},{5,14,4,5},{4,5,12,2}}, circles = {} },
    zap = { lines = {{13,2,5,13},{5,13,11,13},{11,13,9,22},{9,22,19,9},{19,9,12,9},{12,9,13,2}}, circles = {} },
    star = { lines = {{12,2,15,9},{15,9,22,9},{22,9,17,14},{17,14,18,21},{18,21,12,17},{12,17,6,21},{6,21,7,14},{7,14,2,9},{2,9,9,9},{9,9,12,2}}, circles = {} },
    heart = { lines = {{12,21,4,13},{4,13,3,10},{3,10,4,6},{4,6,7,4},{7,4,10,5},{10,5,12,8},{12,8,14,5},{14,5,17,4},{17,4,20,6},{20,6,21,10},{21,10,20,13},{20,13,12,21}}, circles = {} },
    menu = { lines = {{4,6,20,6},{4,12,20,12},{4,18,20,18}}, circles = {} },
    list = { lines = {{8,6,21,6},{8,12,21,12},{8,18,21,18}}, circles = {{4,6,1},{4,12,1},{4,18,1}} },
    key = { lines = {{14,10,22,2},{18,6,21,9},{15,9,18,12},{2,22,14,10}}, circles = {{8,16,4}} },
    activity = { lines = {{2,13,6,13},{6,13,9,5},{9,5,14,19},{14,19,17,11},{17,11,22,11}}, circles = {} },
    folder = { lines = {{2,6,9,6},{9,6,11,9},{11,9,22,9},{22,9,20,20},{20,20,3,20},{3,20,2,6}}, circles = {} },
    command = { lines = {{5,6,10,12},{10,12,5,18},{13,18,19,18}}, circles = {} },
    sparkles = { lines = {{12,2,14,9},{14,9,21,12},{21,12,14,14},{14,14,12,21},{12,21,10,14},{10,14,3,12},{3,12,10,9},{10,9,12,2},{19,2,19,6},{17,4,21,4}}, circles = {} },
    chevronDown = { lines = {{5,9,12,16},{12,16,19,9}}, circles = {} },
    chevronRight = { lines = {{9,5,16,12},{16,12,9,19}}, circles = {} },
    sun = { lines = {{12,2,12,5},{12,19,12,22},{2,12,5,12},{19,12,22,12},{5,5,7,7},{17,17,19,19},{19,5,17,7},{7,17,5,19}}, circles = {{12,12,4}} },
    moon = { lines = {{16,3,13,3},{13,3,9,5},{9,5,7,9},{7,9,8,14},{8,14,12,18},{12,18,17,18},{17,18,20,15}}, circles = {} },
    x = { lines = {{5,5,19,19},{19,5,5,19}}, circles = {} },
    plus = { lines = {{12,4,12,20},{4,12,20,12}}, circles = {} },
    minus = { lines = {{4,12,20,12}}, circles = {} },
    check = { lines = {{4,13,9,18},{9,18,20,6}}, circles = {} },
    chevronUp = { lines = {{5,15,12,8},{12,8,19,15}}, circles = {} },
    chevronLeft = { lines = {{15,5,8,12},{8,12,15,19}}, circles = {} },
    arrowUpRight = { lines = {{6,18,18,6},{8,6,18,6},{18,6,18,16}}, circles = {} },
    arrowDownRight = { lines = {{5,7,18,20},{8,20,18,20},{18,10,18,20}}, circles = {} },
    trash2 = { lines = {{4,7,20,7},{9,7,9,4},{9,4,15,4},{15,4,15,7},{7,7,8,20},{8,20,16,20},{16,20,17,7},{10,10,10,17},{14,10,14,17}}, circles = {} },
    clock = { lines = {{12,3,12,12},{12,12,18,15}}, circles = {{12,12,9}} },
    calendar = { lines = {{4,6,20,6},{4,6,4,21},{4,21,20,21},{20,21,20,6},{8,3,8,8},{16,3,16,8},{4,10,20,10}}, circles = {} },
    download = { lines = {{12,3,12,15},{7,10,12,15},{12,15,17,10},{4,20,20,20}}, circles = {} },
    upload = { lines = {{12,16,12,4},{7,9,12,4},{12,4,17,9},{4,20,20,20}}, circles = {} },
    save = { lines = {{5,3,17,3},{17,3,21,7},{21,7,21,21},{21,21,3,21},{3,21,3,3},{3,3,5,3},{7,3,7,10},{7,10,16,10},{16,10,16,3},{7,15,17,15},{17,15,17,19},{17,19,7,19},{7,19,7,15}}, circles = {} },
    copy = { lines = {{8,8,20,8},{20,8,20,21},{20,21,8,21},{8,21,8,8},{4,16,3,16},{3,16,3,3},{3,3,15,3},{15,3,15,5}}, circles = {} },
    clipboard = { lines = {{8,5,8,3},{8,3,16,3},{16,3,16,5},{16,5,19,5},{19,5,19,21},{19,21,5,21},{5,21,5,5},{5,5,8,5}}, circles = {} },
    refreshCw = { lines = {{20,7,20,3},{20,3,16,3},{20,3,15,8},{16,8,20,8},{20,12,19,16},{19,16,15,20},{15,20,11,20},{6,17,4,17},{4,17,4,21},{4,21,9,16}}, circles = {} },
    wifi = { lines = {{3,9,5,7},{5,7,8,5},{8,5,12,4},{12,4,16,5},{16,5,19,7},{19,7,21,9},{6,12,8,10},{8,10,12,9},{12,9,16,10},{16,10,18,12},{10,16,12,14},{12,14,14,16}}, circles = {} },
    volume2 = { lines = {{3,9,7,9},{7,9,12,5},{12,5,12,19},{12,19,7,15},{7,15,3,15},{3,15,3,9},{16,9,18,12},{18,12,16,15},{19,6,22,12},{22,12,19,18}}, circles = {} },
    volumeX = { lines = {{3,9,7,9},{7,9,12,5},{12,5,12,19},{12,19,7,15},{7,15,3,15},{3,15,3,9},{16,9,22,15},{22,9,16,15}}, circles = {} },
    messageSquare = { lines = {{4,4,20,4},{20,4,20,17},{20,17,10,17},{5,22,10,17},{4,4,4,17},{4,17,10,17}}, circles = {} },
    send = { lines = {{3,11,21,3},{21,3,15,21},{15,21,11,13},{11,13,3,11},{11,13,21,3}}, circles = {} },
    fileText = { lines = {{6,3,15,3},{15,3,20,8},{20,8,20,21},{20,21,4,21},{4,21,4,3},{4,3,6,3},{15,3,15,8},{15,8,20,8},{8,12,16,12},{8,16,16,16}}, circles = {} },
    folderOpen = { lines = {{3,7,10,7},{10,7,12,10},{12,10,21,10},{21,10,18,20},{18,20,2,20},{2,20,3,7},{2,13,21,13}}, circles = {} },
    mousePointer2 = { lines = {{5,3,5,21},{5,21,10,16},{10,16,13,22},{16,20,13,14},{13,14,20,14},{5,3,20,14}}, circles = {} },
    move = { lines = {{12,2,12,22},{2,12,22,12},{12,2,9,5},{12,2,15,5},{12,22,9,19},{12,22,15,19},{2,12,5,9},{2,12,5,15},{22,12,19,9},{22,12,19,15}}, circles = {} },
    maximize2 = { lines = {{8,3,3,3},{3,3,3,8},{16,3,21,3},{21,3,21,8},{3,16,3,21},{3,21,8,21},{21,16,21,21},{21,21,16,21}}, circles = {} },
    minimize2 = { lines = {{3,12,9,12},{9,12,9,18},{9,18,3,18},{3,18,3,12},{15,6,21,6},{21,6,21,12},{21,12,15,12},{15,12,15,6}}, circles = {} },
    circleHelp = { lines = {{9,9,10,7},{10,7,13,7},{13,7,15,9},{15,9,15,11},{15,11,12,13},{12,13,12,15},{12,19,12,19}}, circles = {{12,12,10}} },
    circleCheck = { lines = {{7,12,10,15},{10,15,17,8}}, circles = {{12,12,10}} },
    circleX = { lines = {{8,8,16,16},{16,8,8,16}}, circles = {{12,12,10}} },
    rocket = { lines = {{12,21,12,16},{12,16,8,13},{8,13,8,8},{8,8,12,3},{12,3,16,8},{16,8,16,13},{16,13,12,16},{8,13,4,17},{4,17,8,17},{16,13,20,17},{20,17,16,17}}, circles = {{12,8,2}} },
    flame = { lines = {{12,22,7,20},{7,20,5,16},{5,16,7,11},{7,11,9,6},{9,6,10,11},{10,11,14,8},{14,8,17,13},{17,13,19,17},{19,17,16,21},{16,21,12,22}}, circles = {} },
    cpu = { lines = {{6,6,18,6},{18,6,18,18},{18,18,6,18},{6,18,6,6},{9,9,15,9},{15,9,15,15},{15,15,9,15},{9,15,9,9},{9,2,9,6},{15,2,15,6},{9,18,9,22},{15,18,15,22},{2,9,6,9},{2,15,6,15},{18,9,22,9},{18,15,22,15}}, circles = {} },
    database = { lines = {{4,5,4,18},{4,18,12,21},{12,21,20,18},{20,18,20,5},{4,5,12,2},{12,2,20,5},{4,11,12,14},{12,14,20,11}}, circles = {} },
    layers = { lines = {{12,2,22,7},{22,7,12,12},{12,12,2,7},{2,7,12,2},{2,12,12,17},{12,17,22,12},{2,17,12,22},{12,22,22,17}}, circles = {} },
    package = { lines = {{3,7,12,2},{12,2,21,7},{21,7,21,18},{21,18,12,23},{12,23,3,18},{3,18,3,7},{3,7,12,12},{12,12,21,7},{12,12,12,23}}, circles = {} },
    lock = { lines = {{5,10,19,10},{19,10,19,21},{19,21,5,21},{5,21,5,10},{8,10,8,7},{8,7,10,4},{10,4,14,4},{14,4,16,7},{16,7,16,10}}, circles = {} },
    unlock = { lines = {{5,10,19,10},{19,10,19,21},{19,21,5,21},{5,21,5,10},{8,10,8,7},{8,7,10,4},{10,4,14,4}}, circles = {} },
    shieldCheck = { lines = {{12,2,20,5},{20,5,19,14},{19,14,12,22},{12,22,5,14},{5,14,4,5},{4,5,12,2},{8,12,11,15},{11,15,16,9}}, circles = {} },
    wandSparkles = { lines = {{4,20,16,8},{16,8,19,5},{19,5,17,3},{17,3,14,6},{14,6,4,16},{4,16,4,20},{18,14,19,17},{19,17,22,18},{22,18,19,19},{19,19,18,22},{18,22,17,19},{17,19,14,18},{14,18,17,17},{17,17,18,14}}, circles = {} },
    users = { lines = {{3,21,3,18},{3,18,6,15},{6,15,10,15},{10,15,13,18},{13,18,13,21},{3,21,13,21},{14,15,18,15},{18,15,21,18},{21,18,21,21},{13,21,21,21}}, circles = {{8,8,4},{17,9,3}} },
    logOut = { lines = {{10,3,4,3},{4,3,4,21},{4,21,10,21},{10,21,10,18},{10,6,10,3},{13,8,18,12},{18,12,13,16},{18,12,8,12}}, circles = {} },
    bookOpen = { lines = {{12,6,12,21},{12,6,8,4},{8,4,3,4},{3,4,3,18},{3,18,8,18},{8,18,12,21},{12,6,16,4},{16,4,21,4},{21,4,21,18},{21,18,16,18},{16,18,12,21}}, circles = {} },
    lifeBuoy = { lines = {{8,8,4,4},{4,4,8,8},{16,8,20,4},{20,4,16,8},{8,16,4,20},{4,20,8,16},{16,16,20,20},{20,20,16,16}}, circles = {{12,12,9},{12,12,4}} },
}

local function DrawVectorIcon(parent, name, color, size, provider)
    size = size or 18
    local providerRaw
    local providerData
    if provider then
        local ok, result = pcall(function()
            if type(provider) == "function" then return provider(name, parent, color, size) end
            if type(provider) == "table" then
                if type(provider.Create) == "function" then return provider:Create(name, parent, color, size) end
                if type(provider.GetIcon) == "function" then return provider:GetIcon(name, color, size) end
                if type(provider.getIcon) == "function" then return provider.getIcon(name, color, size) end
                if type(provider.Icons) == "table" then return provider.Icons[name] end
                return provider[name]
            end
        end)
        if ok and typeof(result) == "Instance" then
            if result.Parent == nil then result.Parent = parent end
            return result
        elseif ok and type(result) == "string" then
            providerRaw = result
        elseif ok and type(result) == "table" then
            providerData = result
        elseif not ok then
            warn("[LunarUI][IconProvider]", result)
        end
    end
    local raw = providerRaw or tostring(name or "")
    if raw:match("^rbxassetid://%d+$") or raw:match("^%d+$") then
        local image = Instance.new("ImageLabel")
        image.Name = "Icon_" .. raw
        image.BackgroundTransparency = 1
        image.Size = UDim2.fromOffset(size, size)
        image.Image = raw:match("^%d+$") and ("rbxassetid://" .. raw) or raw
        image.ImageColor3 = color or Theme.Text
        image.ScaleType = Enum.ScaleType.Fit
        image.Parent = parent
        return image
    end
    local data = providerData or VectorIcons[string.lower(raw)] or VectorIcons.list
    local root = Instance.new("Frame")
    root.Name = "Lucide_" .. raw
    root.BackgroundTransparency = 1
    root.Size = UDim2.fromOffset(size, size)
    root.Parent = parent
    local scale = size / 24
    local thickness = math.max(1, size / 12)
    local function line(x1,y1,x2,y2)
        local x1p,y1p,x2p,y2p = x1*scale,y1*scale,x2*scale,y2*scale
        local dx,dy = x2p-x1p,y2p-y1p
        local length = math.sqrt(dx*dx+dy*dy)
        local f = Instance.new("Frame")
        f.Name = "Stroke"
        f.AnchorPoint = Vector2.new(0.5,0.5)
        f.Position = UDim2.fromOffset((x1p+x2p)/2,(y1p+y2p)/2)
        f.Size = UDim2.fromOffset(length,thickness)
        f.Rotation = math.deg(math.atan2(dy,dx))
        f.BackgroundColor3 = color or Theme.Text
        f.BorderSizePixel = 0
        f.Parent = root
        local cr=Instance.new("UICorner");cr.CornerRadius=UDim.new(1,0);cr.Parent=f
    end
    for _,v in ipairs(data.lines or {}) do line(table.unpack(v)) end
    for _,v in ipairs(data.circles or {}) do
        local d=v[3]*2*scale
        local c=Instance.new("Frame")
        c.Name="Ring";c.AnchorPoint=Vector2.new(.5,.5)
        c.Position=UDim2.fromOffset(v[1]*scale,v[2]*scale)
        c.Size=UDim2.fromOffset(d,d);c.BackgroundTransparency=1;c.Parent=root
        local cc=Instance.new("UICorner");cc.CornerRadius=UDim.new(1,0);cc.Parent=c
        local cs=Instance.new("UIStroke");cs.Color=color or Theme.Text;cs.Thickness=thickness;cs.Parent=c
    end
    return root
end

----------------------------------------------------------------
-- COMPONENTS
----------------------------------------------------------------
local function GetParentForComponent(tab)
	if #tab.Sections > 0 then
		return tab.Sections[#tab.Sections].Content
	end
	return tab.Content
end

-- SECTION
local function CreateSection(tab, config)
	config = config or {}
	local cleanup = CreateCleanup()

	local container = Instance.new("Frame")
	container.Name = "Section_" .. (config.Name or "Untitled")
	container.BackgroundTransparency = 1
	container.Size = UDim2.new(1, 0, 0, 0)
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.Parent = tab.Content

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = container

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 20)
	title.Font = Theme.FontBold
	title.TextSize = 13
	title.TextColor3 = Theme.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = config.Name or "Section"
	title.LayoutOrder = 0
	title.Parent = container

	if config.Description then
		local d = Instance.new("TextLabel")
		d.BackgroundTransparency = 1
		d.Size = UDim2.new(1, 0, 0, 16)
		d.Font = Theme.Font
		d.TextSize = 11
		d.TextColor3 = Theme.SecondaryText
		d.TextXAlignment = Enum.TextXAlignment.Left
		d.Text = config.Description
		d.LayoutOrder = 1
		d.Parent = container
	end

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.new(1, 0, 0, 0)
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.LayoutOrder = 2
	content.Parent = container

	local cl = Instance.new("UIListLayout")
	cl.SortOrder = Enum.SortOrder.LayoutOrder
	cl.Padding = UDim.new(0, 6)
	cl.Parent = content

	cleanup:AddInstance(container)

	local descLabel = nil
	if config.Description then
		descLabel = container:FindFirstChildWhichIsA("TextLabel")
		-- title is first, description is second TextLabel
		for _, ch in ipairs(container:GetChildren()) do
			if ch:IsA("TextLabel") and ch ~= title then
				descLabel = ch
				break
			end
		end
	end

	local section = {
		Container = container,
		Content = content,
		Cleanup = cleanup,
		Tab = tab,
		Window = tab.Window,
	}
	-- Controls can be created from either Tab:CreateX(...) or Section:CreateX(...).
	-- Factories are filled at the bottom after every component constructor exists.
	function section:_create(name, config)
		local factory = self.Window and self.Window.Library and self.Window.Library._ComponentFactories and self.Window.Library._ComponentFactories[name]
		if not factory then warn("[LunarUI] Missing component factory:", name); return nil end
		local proxy = { Sections = { self }, Components = tab.Components, Window = tab.Window, Content = tab.Content }
		local ok, component = pcall(factory, proxy, config)
		if not ok then warn("[LunarUI][Component:" .. tostring(name) .. "]", component); return nil end
		if type(config)=="table" and config.Flag and self.Window.Library then self.Window.Library.Flags[config.Flag]=component end
		return component
	end

	function section:RefreshTheme()
		if cleanup:IsDestroyed() then return end
		title.Font = Theme.FontBold
		title.TextColor3 = Theme.Text
		if descLabel then
			descLabel.Font = Theme.Font
			descLabel.TextColor3 = Theme.SecondaryText
		end
	end

	function section:Destroy()
		cleanup:Destroy()
	end

	table.insert(tab.Sections, section)
	for _, method in ipairs({"Button","Toggle","Slider","Label","Dropdown","Textbox","Keybind","Colorpicker","MultiDropdown","ProgressBar","Paragraph","ButtonGroup"}) do
		local methodName = method
		section["Create" .. methodName] = function(self, c) return self:_create(methodName, c) end
	end
	section.CreateDivider = function(self) return self:_create("Divider", {}) end
	section.CreateColorPicker = section.CreateColorpicker
	section.CreateInput = section.CreateTextbox
	section.CreateProgress = section.CreateProgressBar
	section.CreateSwitch = section.CreateToggle
	section.CreateRange = section.CreateSlider
	section.CreateColor = section.CreateColorpicker
	section.CreateMultiSelect = section.CreateMultiDropdown
	section.CreateChoice = section.CreateDropdown
	section.CreateTextDisplay = section.CreateParagraph
	return section
end

-- BUTTON (function callback; arbitrary source strings are never evaluated)
local function CreateButton(tab, config)
	config = config or {}
	local cleanup = CreateCleanup()
	local enabled = true
	local parent = GetParentForComponent(tab)

	local frame = Instance.new("TextButton")
	frame.Name = "Button_" .. (config.Name or "Untitled")
	frame.BackgroundColor3 = Theme.Secondary
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, Theme.ElementHeight)
	frame.AutoButtonColor = false
	frame.Text = ""
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.CornerRadius)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Border
	stroke.Thickness = 1
	stroke.Transparency = 0.5
	stroke.Parent = frame

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -24, 0, 16)
	title.Position = UDim2.new(0, 12, 0.5, config.Description and -8 or 0)
	title.Font = Theme.Font
	title.TextSize = 13
	title.TextColor3 = Theme.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = config.Name or "Button"
	title.Parent = frame

	local desc
	if config.Description then
		desc = Instance.new("TextLabel")
		desc.BackgroundTransparency = 1
		desc.Size = UDim2.new(1, -24, 0, 14)
		desc.Position = UDim2.new(0, 12, 0.5, 4)
		desc.Font = Theme.Font
		desc.TextSize = 11
		desc.TextColor3 = Theme.SecondaryText
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.Text = config.Description
		desc.Parent = frame
	end

	cleanup:AddConnection(frame.MouseEnter:Connect(function()
		if not enabled then return end
		TweenEngine.Play(frame, { BackgroundColor3 = Theme.Hover }, { Duration = Theme.HoverSpeed, Easing = "QuadOut" })
	end))
	cleanup:AddConnection(frame.MouseLeave:Connect(function()
		if not enabled then return end
		TweenEngine.Play(frame, { BackgroundColor3 = Theme.Secondary }, { Duration = Theme.HoverSpeed, Easing = "QuadOut" })
	end))
	cleanup:AddConnection(frame.MouseButton1Down:Connect(function()
		if not enabled then return end
		TweenEngine.Play(frame, { BackgroundColor3 = Theme.Tertiary }, { Duration = 0.08 })
	end))
	cleanup:AddConnection(frame.MouseButton1Up:Connect(function()
		if not enabled then return end
		TweenEngine.Play(frame, { BackgroundColor3 = Theme.Hover }, { Duration = 0.1 })
	end))

	cleanup:AddConnection(frame.MouseButton1Click:Connect(function()
		if not enabled then return end

-- Button callbacks are deliberately isolated; a component never evaluates arbitrary strings.
		if config.Callback then
			task.spawn(config.Callback)
		end
	end))

	cleanup:AddInstance(frame)

	local btn = { Frame = frame, Cleanup = cleanup }

	function btn:RefreshTheme()
		if cleanup:IsDestroyed() then return end
		frame.BackgroundColor3 = Theme.Secondary
		stroke.Color = Theme.Border
		title.Font = Theme.Font
		title.TextColor3 = enabled and Theme.Text or Theme.MutedText
		if desc then
			desc.Font = Theme.Font
			desc.TextColor3 = enabled and Theme.SecondaryText or Theme.MutedText
		end
	end

	function btn:SetEnabled(state)
		enabled = state
		frame.BackgroundTransparency = state and 0.1 or 0.5
		title.TextColor3 = state and Theme.Text or Theme.MutedText
		if desc then desc.TextColor3 = state and Theme.SecondaryText or Theme.MutedText end
	end

	function btn:SetCallback(fn)
		config.Callback = fn
	end

	function btn:Destroy()
		cleanup:Destroy()
	end

	table.insert(tab.Components, btn)
	return btn
end

-- TOGGLE
local function CreateToggle(tab, config)
	config = config or {}
	local cleanup = CreateCleanup()
	local value = config.Default == true
	local enabled = true
	local parent = GetParentForComponent(tab)

	local frame = Instance.new("Frame")
	frame.Name = "Toggle_" .. (config.Name or "Untitled")
	frame.BackgroundColor3 = Theme.Secondary
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, Theme.ElementHeight)
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.CornerRadius)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Border
	stroke.Thickness = 1
	stroke.Transparency = 0.5
	stroke.Parent = frame

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -60, 0, 16)
	title.Position = UDim2.new(0, 12, 0.5, config.Description and -8 or 0)
	title.Font = Theme.Font
	title.TextSize = 13
	title.TextColor3 = Theme.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = config.Name or "Toggle"
	title.Parent = frame

	if config.Description then
		local d = Instance.new("TextLabel")
		d.BackgroundTransparency = 1
		d.Size = UDim2.new(1, -60, 0, 14)
		d.Position = UDim2.new(0, 12, 0.5, 4)
		d.Font = Theme.Font
		d.TextSize = 11
		d.TextColor3 = Theme.SecondaryText
		d.TextXAlignment = Enum.TextXAlignment.Left
		d.Text = config.Description
		d.Parent = frame
	end

	local switch = Instance.new("Frame")
	switch.BackgroundColor3 = value and Theme.ToggleOn or Theme.ToggleOff
	switch.BorderSizePixel = 0
	switch.Size = UDim2.new(0, 40, 0, 22)
	switch.Position = UDim2.new(1, -52, 0.5, -11)
	switch.Parent = frame

	local sc = Instance.new("UICorner")
	sc.CornerRadius = UDim.new(1, 0)
	sc.Parent = switch

	local knob = Instance.new("Frame")
	knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	knob.BorderSizePixel = 0
	knob.Size = UDim2.new(0, 16, 0, 16)
	knob.Position = value and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
	knob.Parent = switch

	local kc = Instance.new("UICorner")
	kc.CornerRadius = UDim.new(1, 0)
	kc.Parent = knob

	local function updateVisual(animate)
		local targetColor = value and Theme.ToggleOn or Theme.ToggleOff
		local targetPos = value and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
		if animate then
			TweenEngine.Play(switch, { BackgroundColor3 = targetColor }, { Duration = 0.2, Easing = "QuadOut" })
			TweenEngine.Play(knob, { Position = targetPos }, { Duration = 0.25, Easing = "BackOut" })
		else
			switch.BackgroundColor3 = targetColor
			knob.Position = targetPos
		end
	end

	local hit = Instance.new("TextButton")
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.new(1, 0, 1, 0)
	hit.Text = ""
	hit.Parent = frame

	local changed = CreateSignal()

	cleanup:AddConnection(hit.MouseButton1Click:Connect(function()
		if not enabled then return end
		value = not value
		updateVisual(true)
		changed:Fire(value)
		if config.Callback then task.spawn(config.Callback, value) end
	end))

	cleanup:AddInstance(frame)
	updateVisual(false)

	local toggle = { Frame = frame, Cleanup = cleanup, Changed = changed }

	function toggle:RefreshTheme()
		if cleanup:IsDestroyed() then return end
		frame.BackgroundColor3 = Theme.Secondary
		stroke.Color = Theme.Border
		title.Font = Theme.Font
		title.TextColor3 = Theme.Text
		updateVisual(false)
	end

	function toggle:Set(v, suppress)
		if value == v then return end
		value = v
		updateVisual(true)
		if not suppress then
			changed:Fire(value)
			if config.Callback then task.spawn(config.Callback, value) end
		end
	end

	function toggle:Get()
		return value
	end

	function toggle:SetEnabled(state)
		enabled = state
		frame.BackgroundTransparency = state and 0.15 or 0.5
	end

	function toggle:Destroy()
		changed:Destroy()
		cleanup:Destroy()
	end

	function toggle:IsDestroyed()
		return cleanup:IsDestroyed()
	end

	table.insert(tab.Components, toggle)
	return toggle
end

-- SLIDER
local function CreateSlider(tab, config)
	config = config or {}
	local cleanup = CreateCleanup()
	local minv = config.Min or 0
	local maxv = config.Max or 100
	local step = config.Step or 1
	local value = config.Default or minv
	local enabled = true
	local parent = GetParentForComponent(tab)
	local dragging = false

	local frame = Instance.new("Frame")
	frame.Name = "Slider_" .. (config.Name or "Untitled")
	frame.BackgroundColor3 = Theme.Secondary
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, 52)
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.CornerRadius)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Border
	stroke.Thickness = 1
	stroke.Transparency = 0.5
	stroke.Parent = frame

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(0.7, 0, 0, 16)
	title.Position = UDim2.new(0, 12, 0, 8)
	title.Font = Theme.Font
	title.TextSize = 13
	title.TextColor3 = Theme.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = config.Name or "Slider"
	title.Parent = frame

	local valueLabel = Instance.new("TextLabel")
	valueLabel.BackgroundTransparency = 1
	valueLabel.Size = UDim2.new(0.3, -12, 0, 16)
	valueLabel.Position = UDim2.new(0.7, 0, 0, 8)
	valueLabel.Font = Theme.FontMono
	valueLabel.TextSize = 12
	valueLabel.TextColor3 = Theme.SecondaryText
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.Text = tostring(value)
	valueLabel.Parent = frame

	local track = Instance.new("Frame")
	track.BackgroundColor3 = Theme.SliderTrack
	track.BorderSizePixel = 0
	track.Size = UDim2.new(1, -24, 0, 4)
	track.Position = UDim2.new(0, 12, 1, -16)
	track.Parent = frame

	local tc = Instance.new("UICorner")
	tc.CornerRadius = UDim.new(1, 0)
	tc.Parent = track

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = Theme.SliderFill
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.Parent = track

	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(1, 0)
	fc.Parent = fill

	local knob = Instance.new("Frame")
	knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	knob.BorderSizePixel = 0
	knob.Size = UDim2.new(0, 12, 0, 12)
	knob.Position = UDim2.new(0, -6, 0.5, -6)
	knob.ZIndex = 2
	knob.Parent = track

	local kc = Instance.new("UICorner")
	kc.CornerRadius = UDim.new(1, 0)
	kc.Parent = knob

	local function snap(v)
		local s = math.floor((v - minv) / step + 0.5) * step + minv
		return math.clamp(s, minv, maxv)
	end

	local function setVisual(v, animate)
		local alpha = math.clamp((v - minv) / (maxv - minv), 0, 1)
		local ts = UDim2.new(alpha, 0, 1, 0)
		local tp = UDim2.new(alpha, -6, 0.5, -6)
		if animate then
			TweenEngine.Play(fill, { Size = ts }, { Duration = 0.15, Easing = "QuadOut" })
			TweenEngine.Play(knob, { Position = tp }, { Duration = 0.15, Easing = "QuadOut" })
		else
			fill.Size = ts
			knob.Position = tp
		end
		valueLabel.Text = tostring(math.floor(v * 100 + 0.5) / 100)
	end

	local function updateFromInput(pos)
		local rel = math.clamp((pos.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		local raw = minv + rel * (maxv - minv)
		local newVal = snap(raw)
		if newVal ~= value then
			value = newVal
			setVisual(newVal, false)
			changed:Fire(newVal)
			if config.Callback then task.spawn(config.Callback, newVal) end
		else
			setVisual(newVal, false)
		end
	end

	local changed = CreateSignal()

	local hit = Instance.new("TextButton")
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.new(1, 0, 0, 20)
	hit.Position = UDim2.new(0, 0, 1, -24)
	hit.Text = ""
	hit.Parent = frame

	local moveConn, endConn = nil, nil
	local function clearSliderDrag()
		if moveConn then
			pcall(function() moveConn:Disconnect() end)
			moveConn = nil
		end
		if endConn then
			pcall(function() endConn:Disconnect() end)
			endConn = nil
		end
		dragging = false
	end

	cleanup:AddConnection(hit.InputBegan:Connect(function(input)
		if not enabled then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			clearSliderDrag()
			dragging = true
			updateFromInput(input.Position)
			-- only live while dragging (avoids N permanent global UIS hooks)
			moveConn = UserInputService.InputChanged:Connect(function(inp)
				if not dragging then return end
				if inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch then
					updateFromInput(inp.Position)
				end
			end)
			endConn = UserInputService.InputEnded:Connect(function(inp)
				if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
					clearSliderDrag()
				end
			end)
		end
	end))

	cleanup:AddCallback(clearSliderDrag)

	cleanup:AddInstance(frame)
	setVisual(value, false)

	local slider = { Frame = frame, Cleanup = cleanup, Changed = changed }

	function slider:RefreshTheme()
		if cleanup:IsDestroyed() then return end
		frame.BackgroundColor3 = Theme.Secondary
		stroke.Color = Theme.Border
		title.Font = Theme.Font
		title.TextColor3 = Theme.Text
		valueLabel.Font = Theme.FontMono
		valueLabel.TextColor3 = Theme.SecondaryText
		track.BackgroundColor3 = Theme.SliderTrack
		fill.BackgroundColor3 = Theme.SliderFill
	end

	function slider:Set(v, suppress)
		v = snap(math.clamp(v, minv, maxv))
		if value == v then return end
		value = v
		setVisual(v, true)
		if not suppress then
			changed:Fire(v)
			if config.Callback then task.spawn(config.Callback, v) end
		end
	end

	function slider:Get()
		return value
	end

	function slider:Destroy()
		changed:Destroy()
		cleanup:Destroy()
	end

	function slider:IsDestroyed()
		return cleanup:IsDestroyed()
	end

	table.insert(tab.Components, slider)
	return slider
end

-- LABEL
local function CreateLabel(tab, config)
	config = config or {}
	local cleanup = CreateCleanup()
	local parent = GetParentForComponent(tab)

	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, config.Description and 36 or 20)
	frame.Parent = parent

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 16)
	title.Font = Theme.Font
	title.TextSize = 13
	title.TextColor3 = Theme.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = config.Name or "Label"
	title.Parent = frame

	local desc
	if config.Description then
		desc = Instance.new("TextLabel")
		desc.BackgroundTransparency = 1
		desc.Size = UDim2.new(1, 0, 0, 14)
		desc.Position = UDim2.new(0, 0, 0, 18)
		desc.Font = Theme.Font
		desc.TextSize = 11
		desc.TextColor3 = Theme.SecondaryText
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.Text = config.Description
		desc.Parent = frame
	end

	cleanup:AddInstance(frame)

	local label = { Frame = frame, TitleLabel = title, DescLabel = desc, Cleanup = cleanup }

	function label:RefreshTheme()
		if cleanup:IsDestroyed() then return end
		title.Font = Theme.Font
		title.TextColor3 = Theme.Text
		if desc then
			desc.Font = Theme.Font
			desc.TextColor3 = Theme.SecondaryText
		end
	end

	function label:SetTitle(t) title.Text = t end
	function label:SetDescription(t) if desc then desc.Text = t end end
	function label:Destroy() cleanup:Destroy() end

	table.insert(tab.Components, label)
	return label
end

-- DROPDOWN (expands frame so content below sinks via UIListLayout)
local function CreateDropdown(tab, config)
	config = config or {}
	local cleanup = CreateCleanup()
	local options = config.Options or {}
	local value = config.Default or (options[1] or "")
	local open = false
	local transitioning = false
	local destroyed = false
	local parent = GetParentForComponent(tab)
	local outsideConn = nil
	local closedHeight = Theme.ElementHeight
	local listGap = 4
	local optionH = 28
	local maxListH = 140

	-- Declare early so closures can safely reference them
	local changed = CreateSignal()
	local dd = { Frame = nil, Cleanup = cleanup, Changed = changed }

	local frame = Instance.new("Frame")
	frame.Name = "Dropdown_" .. (config.Name or "Untitled")
	frame.BackgroundColor3 = Theme.Secondary
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, closedHeight)
	frame.ClipsDescendants = true -- clip list while animating height
	frame.Parent = parent
	dd.Frame = frame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.CornerRadius)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Border
	stroke.Thickness = 1
	stroke.Transparency = 0.5
	stroke.Parent = frame

	-- Header row (always visible)
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, closedHeight)
	header.Position = UDim2.new(0, 0, 0, 0)
	header.ZIndex = 2
	header.Parent = frame

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -40, 1, 0)
	title.Position = UDim2.new(0, 12, 0, 0)
	title.Font = Theme.Font
	title.TextSize = 13
	title.TextColor3 = Theme.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = (config.Name or "Dropdown") .. ": " .. tostring(value)
	title.Parent = header

	local arrow = Instance.new("TextLabel")
	arrow.BackgroundTransparency = 1
	arrow.Size = UDim2.new(0, 20, 1, 0)
	arrow.Position = UDim2.new(1, -28, 0, 0)
	arrow.Font = Enum.Font.GothamBold
	arrow.TextSize = 12
	arrow.TextColor3 = Theme.SecondaryText
	arrow.Text = "▼"
	arrow.Parent = header

	local list = Instance.new("Frame")
	list.Name = "List"
	list.BackgroundColor3 = Theme.Tertiary
	list.BorderSizePixel = 0
	list.Size = UDim2.new(1, 0, 0, 0)
	list.Position = UDim2.new(0, 0, 0, closedHeight + listGap)
	list.Visible = false
	list.ZIndex = 3
	list.Parent = frame

	local lc = Instance.new("UICorner")
	lc.CornerRadius = UDim.new(0, Theme.CornerRadius)
	lc.Parent = list

	local ls = Instance.new("UIStroke")
	ls.Color = Theme.Border
	ls.Thickness = 1
	ls.Transparency = 0.4
	ls.Parent = list

	local ll = Instance.new("UIListLayout")
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Parent = list

	local function getListHeight()
		return math.min(#options * optionH, maxListH)
	end

	local function forceClose(instant)
		if destroyed then return end
		open = false
		transitioning = false
		if outsideConn then
			outsideConn:Disconnect()
			outsideConn = nil
		end
		TweenEngine.CancelOnObject(list)
		TweenEngine.CancelOnObject(frame)
		if instant then
			list.Size = UDim2.new(1, 0, 0, 0)
			list.Visible = false
			frame.Size = UDim2.new(1, 0, 0, closedHeight)
		else
			transitioning = true
			TweenEngine.Play(list, { Size = UDim2.new(1, 0, 0, 0) }, {
				Duration = 0.18, Easing = "QuadIn",
			})
			TweenEngine.Play(frame, { Size = UDim2.new(1, 0, 0, closedHeight) }, {
				Duration = 0.2, Easing = "QuadIn",
				OnComplete = function()
					if not destroyed then
						list.Visible = false
						transitioning = false
					end
				end
			})
		end
		arrow.Text = "▼"
	end

	local function openList()
		if destroyed or transitioning or open then return end
		transitioning = true
		open = true
		local height = getListHeight()
		local totalH = closedHeight + listGap + height
		list.Visible = true
		list.Size = UDim2.new(1, 0, 0, 0)
		-- Grow frame first so layout sinks content below, then expand list
		TweenEngine.Play(frame, { Size = UDim2.new(1, 0, 0, totalH) }, {
			Duration = 0.22, Easing = "QuadOut",
		})
		TweenEngine.Play(list, { Size = UDim2.new(1, 0, 0, height) }, {
			Duration = 0.22, Easing = "QuadOut",
			OnComplete = function()
				transitioning = false
			end
		})
		arrow.Text = "▲"

		task.defer(function()
			if destroyed or not open then return end
			outsideConn = UserInputService.InputBegan:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
					return
				end
				local pos = input.Position
				local absPos = frame.AbsolutePosition
				local absSize = frame.AbsoluteSize
				if pos.X < absPos.X or pos.X > absPos.X + absSize.X or
				   pos.Y < absPos.Y or pos.Y > absPos.Y + absSize.Y + 4 then
					forceClose(false)
				end
			end)
			cleanup:AddConnection(outsideConn)
		end)
	end

	for i, opt in ipairs(options) do
		local btn = Instance.new("TextButton")
		btn.BackgroundColor3 = Theme.Tertiary
		btn.BorderSizePixel = 0
		btn.Size = UDim2.new(1, 0, 0, optionH)
		btn.Font = Theme.Font
		btn.TextSize = 12
		btn.TextColor3 = Theme.Text
		btn.Text = tostring(opt)
		btn.TextXAlignment = Enum.TextXAlignment.Left
		btn.AutoButtonColor = false
		btn.LayoutOrder = i
		btn.Parent = list

		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 12)
		pad.Parent = btn

		btn.MouseEnter:Connect(function()
			if destroyed then return end
			TweenEngine.Play(btn, { BackgroundColor3 = Theme.Hover }, { Duration = 0.1 })
		end)
		btn.MouseLeave:Connect(function()
			if destroyed then return end
			TweenEngine.Play(btn, { BackgroundColor3 = Theme.Tertiary }, { Duration = 0.1 })
		end)
		btn.MouseButton1Click:Connect(function()
			if destroyed or transitioning then return end
			value = opt
			title.Text = (config.Name or "Dropdown") .. ": " .. tostring(opt)
			changed:Fire(opt)
			if config.Callback then task.spawn(config.Callback, opt) end
			forceClose(false)
		end)
	end

	local hit = Instance.new("TextButton")
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.new(1, 0, 1, 0)
	hit.Text = ""
	hit.ZIndex = 5
	hit.Parent = header

	cleanup:AddConnection(hit.MouseButton1Click:Connect(function()
		if destroyed or transitioning then return end
		if open then
			forceClose(false)
		else
			openList()
		end
	end))

	cleanup:AddInstance(frame)

	function dd:RefreshTheme()
		if destroyed or cleanup:IsDestroyed() then return end
		frame.BackgroundColor3 = Theme.Secondary
		stroke.Color = Theme.Border
		title.Font = Theme.Font
		title.TextColor3 = Theme.Text
		arrow.TextColor3 = Theme.SecondaryText
		list.BackgroundColor3 = Theme.Tertiary
		ls.Color = Theme.Border
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("TextButton") then
				child.BackgroundColor3 = Theme.Tertiary
				child.Font = Theme.Font
				child.TextColor3 = Theme.Text
			end
		end
	end

	function dd:Set(v, suppress)
		if destroyed then return end
		if value == v then return end
		value = v
		title.Text = (config.Name or "Dropdown") .. ": " .. tostring(v)
		if not suppress then
			changed:Fire(v)
			if config.Callback then task.spawn(config.Callback, v) end
		end
	end

	function dd:Get()
		return value
	end

	function dd:Close()
		forceClose(true)
	end

	function dd:Destroy()
		if destroyed then return end
		destroyed = true
		forceClose(true)
		TweenEngine.CancelOnObject(frame)
		TweenEngine.CancelOnObject(list)
		changed:Destroy()
		cleanup:Destroy()
	end

	function dd:IsDestroyed()
		return destroyed or cleanup:IsDestroyed()
	end

	table.insert(tab.Components, dd)
	return dd
end

-- TEXTBOX
local function CreateTextbox(tab, config)
	config = config or {}
	local cleanup = CreateCleanup()
	local parent = GetParentForComponent(tab)

	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Theme.Secondary
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, Theme.ElementHeight)
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.CornerRadius)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Border
	stroke.Thickness = 1
	stroke.Transparency = 0.5
	stroke.Parent = frame

	local box = Instance.new("TextBox")
	box.BackgroundTransparency = 1
	box.Size = UDim2.new(1, -24, 1, 0)
	box.Position = UDim2.new(0, 12, 0, 0)
	box.Font = Theme.FontMono
	box.TextSize = 13
	box.TextColor3 = Theme.Text
	box.PlaceholderColor3 = Theme.MutedText
	box.PlaceholderText = config.Placeholder or "Enter text..."
	box.Text = config.Default or ""
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Parent = frame

	if config.MaxLength then
		box:GetPropertyChangedSignal("Text"):Connect(function()
			if #box.Text > config.MaxLength then
				box.Text = string.sub(box.Text, 1, config.MaxLength)
			end
		end)
	end

	local changed = CreateSignal()

	cleanup:AddConnection(box.Focused:Connect(function()
		TweenEngine.Play(stroke, { Color = Theme.Accent, Transparency = 0.2 }, { Duration = 0.15 })
	end))
	cleanup:AddConnection(box.FocusLost:Connect(function(enter)
		TweenEngine.Play(stroke, { Color = Theme.Border, Transparency = 0.5 }, { Duration = 0.15 })
		changed:Fire(box.Text)
		if config.Callback then task.spawn(config.Callback, box.Text, enter) end
	end))

	cleanup:AddInstance(frame)

	local tb = { Frame = frame, Box = box, Cleanup = cleanup, Changed = changed }

	function tb:RefreshTheme()
		if cleanup:IsDestroyed() then return end
		frame.BackgroundColor3 = Theme.Secondary
		stroke.Color = Theme.Border
		box.Font = Theme.FontMono
		box.TextColor3 = Theme.Text
		box.PlaceholderColor3 = Theme.MutedText
	end

	function tb:Set(t, suppress)
		box.Text = t or ""
		if not suppress then
			changed:Fire(box.Text)
		end
	end
	function tb:Get() return box.Text end
	function tb:Clear()
		box.Text = ""
		changed:Fire("")
	end
	function tb:Destroy()
		changed:Destroy()
		cleanup:Destroy()
	end
	function tb:IsDestroyed()
		return cleanup:IsDestroyed()
	end

	table.insert(tab.Components, tb)
	return tb
end

-- KEYBIND (Hardened Toggle / Hold)
local function CreateKeybind(tab, config)
	config = config or {}
	local cleanup = CreateCleanup()
	local key = config.Default or Enum.KeyCode.Unknown
	local mode = config.Mode or "Toggle" -- "Toggle" or "Hold"
	local active = false
	local listening = false
	local destroyed = false
	local changed = CreateSignal()
	local parent = GetParentForComponent(tab)

	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Theme.Secondary
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, Theme.ElementHeight)
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.CornerRadius)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Border
	stroke.Thickness = 1
	stroke.Transparency = 0.5
	stroke.Parent = frame

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -80, 1, 0)
	title.Position = UDim2.new(0, 12, 0, 0)
	title.Font = Theme.Font
	title.TextSize = 13
	title.TextColor3 = Theme.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = config.Name or "Keybind"
	title.Parent = frame

	local keyLabel = Instance.new("TextLabel")
	keyLabel.BackgroundColor3 = Theme.Tertiary
	keyLabel.BorderSizePixel = 0
	keyLabel.Size = UDim2.new(0, 60, 0, 22)
	keyLabel.Position = UDim2.new(1, -72, 0.5, -11)
	keyLabel.Font = Theme.FontMono
	keyLabel.TextSize = 11
	keyLabel.TextColor3 = Theme.Text
	keyLabel.Text = (key == Enum.KeyCode.Unknown) and "None" or key.Name
	keyLabel.Parent = frame

	local kc = Instance.new("UICorner")
	kc.CornerRadius = UDim.new(0, 4)
	kc.Parent = keyLabel

	local hit = Instance.new("TextButton")
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.new(1, 0, 1, 0)
	hit.Text = ""
	hit.Parent = frame

	local function stopListening()
		if not listening then return end
		listening = false
		keyLabel.Text = (key == Enum.KeyCode.Unknown) and "None" or key.Name
		TweenEngine.Play(stroke, { Color = Theme.Border }, { Duration = 0.15 })
	end

	cleanup:AddConnection(hit.MouseButton1Click:Connect(function()
		if destroyed then return end
		if listening then
			stopListening()
			return
		end
		listening = true
		keyLabel.Text = "..."
		TweenEngine.Play(stroke, { Color = Theme.Accent }, { Duration = 0.15 })
	end))

	cleanup:AddConnection(UserInputService.InputBegan:Connect(function(input, processed)
		if destroyed then return end
		if processed then return end

		if listening then
			-- Accept keyboard or gamepad buttons for binding
			if input.UserInputType == Enum.UserInputType.Keyboard or input.UserInputType == Enum.UserInputType.Gamepad1 then
				-- Escape cancels rebinding without changing
				if input.KeyCode == Enum.KeyCode.Escape then
					stopListening()
					return
				end
				key = input.KeyCode
				keyLabel.Text = key.Name
				listening = false
				changed:Fire(key)
				TweenEngine.Play(stroke, { Color = Theme.Border }, { Duration = 0.15 })
			end
			return
		end

		if key == Enum.KeyCode.Unknown then return end
		if input.KeyCode == key and config.Callback then
			if mode == "Hold" then
				task.spawn(config.Callback, true)
			else
				active = not active
				task.spawn(config.Callback, active)
			end
		end
	end))

	if mode == "Hold" then
		cleanup:AddConnection(UserInputService.InputEnded:Connect(function(input)
			if destroyed then return end
			if key ~= Enum.KeyCode.Unknown and input.KeyCode == key and config.Callback then
				task.spawn(config.Callback, false)
			end
		end))
	end

	cleanup:AddInstance(frame)

	local kb = { Frame = frame, Cleanup = cleanup, Changed = changed }

	function kb:RefreshTheme()
		if destroyed or cleanup:IsDestroyed() then return end
		frame.BackgroundColor3 = Theme.Secondary
		stroke.Color = Theme.Border
		title.Font = Theme.Font
		title.TextColor3 = Theme.Text
		keyLabel.BackgroundColor3 = Theme.Tertiary
		keyLabel.Font = Theme.FontMono
		keyLabel.TextColor3 = Theme.Text
	end

	function kb:Set(k, suppress)
		if destroyed then return end
		key = k or Enum.KeyCode.Unknown
		keyLabel.Text = (key == Enum.KeyCode.Unknown) and "None" or key.Name
		if listening then stopListening() end
		if not suppress then changed:Fire(key) end
	end

	function kb:Clear()
		self:Set(Enum.KeyCode.Unknown)
	end

	function kb:Get()
		return key
	end

	function kb:IsListening()
		return listening
	end

	function kb:Destroy()
		if destroyed then return end
		destroyed = true
		listening = false
		active = false
		TweenEngine.CancelOnObject(frame)
		TweenEngine.CancelOnObject(stroke)
		changed:Destroy()
		cleanup:Destroy()
	end

	table.insert(tab.Components, kb)
	return kb
end

-- COLOR PICKER — true hue + saturation/value planes, HSV state, RGB display,
-- editable hex, presets, touch/mouse drag, live callback, Get/Set/Reset.
local function CreateColorpicker(tab, config)
    config = config or {}
    local cleanup = CreateCleanup()
    local parent = GetParentForComponent(tab)
    local color = typeof(config.Default) == "Color3" and config.Default or Color3.fromRGB(151, 124, 255)
    local hue, sat, val = Color3.toHSV(color)
    local alpha = tonumber(config.Transparency) or 0
    local open, draggingSV, draggingHue = false, false, false
    local changed = CreateSignal()
    local height = Theme.ElementHeight
    local frame = Instance.new("Frame")
    frame.Name = "Colorpicker_" .. (config.Name or "Accent")
    frame.BackgroundColor3 = Theme.Secondary
    frame.BackgroundTransparency = 0.08
    frame.BorderSizePixel = 0
    frame.Size = UDim2.new(1,0,0,height)
    frame.ClipsDescendants = true
    frame.Parent = parent
    local cr = Instance.new("UICorner"); cr.CornerRadius = UDim.new(0,Theme.CornerRadius); cr.Parent = frame
    local border = Instance.new("UIStroke"); border.Color=Theme.Border;border.Transparency=.46;border.Thickness=1;border.Parent=frame
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency=1;label.Font=Theme.Font;label.TextSize=13;label.TextColor3=Theme.Text
    label.TextXAlignment=Enum.TextXAlignment.Left;label.Text=config.Name or "Color";label.Position=UDim2.fromOffset(12,0)
    label.Size=UDim2.new(1,-82,0,height);label.Parent=frame
    local chip=Instance.new("TextButton")
    chip.Name="ColorSwatch";chip.Text="";chip.AutoButtonColor=false;chip.BorderSizePixel=0
    chip.BackgroundColor3=color;chip.Size=UDim2.fromOffset(40,23);chip.Position=UDim2.new(1,-54,.5,-11.5);chip.Parent=frame
    local chipCr=Instance.new("UICorner");chipCr.CornerRadius=UDim.new(0,5);chipCr.Parent=chip
    local chipStroke=Instance.new("UIStroke");chipStroke.Color=Theme.Border;chipStroke.Transparency=.15;chipStroke.Parent=chip

    local pop=Instance.new("Frame")
    pop.Name="PickerPanel";pop.BackgroundColor3=Theme.Tertiary;pop.BorderSizePixel=0
    pop.Size=UDim2.new(1,-18,0,306);pop.Position=UDim2.new(0,9,0,height+7);pop.Visible=false;pop.ZIndex=30;pop.Parent=frame
    local popCr=Instance.new("UICorner");popCr.CornerRadius=UDim.new(0,Theme.CornerRadius+2);popCr.Parent=pop
    local popSt=Instance.new("UIStroke");popSt.Color=Theme.Border;popSt.Transparency=.15;popSt.Parent=pop

    local sv=Instance.new("ImageButton")
    sv.Name="SaturationValue";sv.AutoButtonColor=false;sv.BackgroundColor3=Color3.fromHSV(hue,1,1)
    sv.BorderSizePixel=0;sv.Active=true;sv.Selectable=true;sv.Size=UDim2.new(1,-24,0,142);sv.Position=UDim2.fromOffset(12,12);sv.ZIndex=31;sv.Parent=pop
    local svCr=Instance.new("UICorner");svCr.CornerRadius=UDim.new(0,7);svCr.Parent=sv
    local white=Instance.new("Frame");white.BackgroundColor3=Color3.new(1,1,1);white.BorderSizePixel=0;white.Size=UDim2.fromScale(1,1);white.ZIndex=32;white.Parent=sv
    local whiteCr=Instance.new("UICorner");whiteCr.CornerRadius=UDim.new(0,7);whiteCr.Parent=white
    local whiteGrad=Instance.new("UIGradient");whiteGrad.Rotation=0
    whiteGrad.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(1,1)});whiteGrad.Parent=white
    local black=Instance.new("Frame");black.BackgroundColor3=Color3.new(0,0,0);black.BorderSizePixel=0;black.Size=UDim2.fromScale(1,1);black.ZIndex=33;black.Parent=sv
    local blackCr=Instance.new("UICorner");blackCr.CornerRadius=UDim.new(0,7);blackCr.Parent=black
    local blackGrad=Instance.new("UIGradient");blackGrad.Rotation=90
    blackGrad.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(1,0)});blackGrad.Parent=black
    local cursor=Instance.new("Frame");cursor.Name="Cursor";cursor.BackgroundTransparency=1;cursor.BorderSizePixel=0
    cursor.Size=UDim2.fromOffset(12,12);cursor.ZIndex=35;cursor.Parent=sv
    local ccr=Instance.new("UICorner");ccr.CornerRadius=UDim.new(1,0);ccr.Parent=cursor
    local cst=Instance.new("UIStroke");cst.Color=Color3.new(1,1,1);cst.Thickness=2;cst.Parent=cursor
    local cst2=Instance.new("UIStroke");cst2.Color=Color3.new(0,0,0);cst2.Thickness=1;cst2.Parent=cursor

    local hueBar=Instance.new("Frame");hueBar.Name="Hue";hueBar.BorderSizePixel=0;hueBar.BackgroundColor3=Color3.new(1,1,1);hueBar.Active=true;hueBar.Selectable=true
    hueBar.Size=UDim2.new(1,-24,0,13);hueBar.Position=UDim2.fromOffset(12,164);hueBar.ZIndex=31;hueBar.Parent=pop
    local hueCr=Instance.new("UICorner");hueCr.CornerRadius=UDim.new(1,0);hueCr.Parent=hueBar
    local hueGrad=Instance.new("UIGradient");hueGrad.Color=ColorSequence.new({
        ColorSequenceKeypoint.new(0,Color3.fromRGB(255,0,0)),ColorSequenceKeypoint.new(.167,Color3.fromRGB(255,255,0)),
        ColorSequenceKeypoint.new(.333,Color3.fromRGB(0,255,0)),ColorSequenceKeypoint.new(.5,Color3.fromRGB(0,255,255)),
        ColorSequenceKeypoint.new(.667,Color3.fromRGB(0,0,255)),ColorSequenceKeypoint.new(.833,Color3.fromRGB(255,0,255)),
        ColorSequenceKeypoint.new(1,Color3.fromRGB(255,0,0))});hueGrad.Parent=hueBar
    local hueCursor=Instance.new("Frame");hueCursor.BackgroundColor3=Color3.new(1,1,1);hueCursor.BorderSizePixel=0
    hueCursor.Size=UDim2.fromOffset(5,19);hueCursor.Position=UDim2.new(hue,-2,0,-3);hueCursor.ZIndex=33;hueCursor.Parent=hueBar
    local hcc=Instance.new("UICorner");hcc.CornerRadius=UDim.new(1,0);hcc.Parent=hueCursor

    local hex=Instance.new("TextBox");hex.Name="Hex";hex.ClearTextOnFocus=false;hex.BackgroundColor3=Theme.Background
    hex.BorderSizePixel=0;hex.Font=Theme.FontMono;hex.TextSize=12;hex.TextColor3=Theme.Text;hex.Text="#"..color:ToHex()
    hex.PlaceholderText="#RRGGBB";hex.Size=UDim2.new(.53,-14,0,30);hex.Position=UDim2.fromOffset(12,188);hex.ZIndex=31;hex.Parent=pop
    local hexCr=Instance.new("UICorner");hexCr.CornerRadius=UDim.new(0,5);hexCr.Parent=hex
    local rgb=Instance.new("TextLabel");rgb.Name="RGB";rgb.BackgroundTransparency=1;rgb.Font=Theme.FontMono;rgb.TextSize=10
    rgb.TextColor3=Theme.SecondaryText;rgb.TextXAlignment=Enum.TextXAlignment.Left;rgb.Size=UDim2.new(.47,-8,0,30)
    rgb.Position=UDim2.new(.53,0,0,188);rgb.ZIndex=31;rgb.Parent=pop
    local function smallBtn(text,x,width)
        local b=Instance.new("TextButton");b.AutoButtonColor=false;b.BackgroundColor3=Theme.Background;b.BorderSizePixel=0;b.Font=Theme.Font
        b.TextSize=10;b.TextColor3=Theme.Text;b.Text=text;b.Size=UDim2.new(width, -4,0,25);b.Position=UDim2.new(x,2,0,226);b.ZIndex=31;b.Parent=pop
        local c=Instance.new("UICorner");c.CornerRadius=UDim.new(0,5);c.Parent=b
        return b
    end
    local presets={Color3.fromRGB(151,124,255),Color3.fromRGB(68,206,188),Color3.fromRGB(82,161,255),Color3.fromRGB(245,81,117),Color3.fromRGB(255,181,76),Color3.fromRGB(111,223,134),Color3.fromRGB(238,238,245)}
    local presetButtons={}
    for i,c in ipairs(presets) do
        local b=Instance.new("TextButton");b.Name="Preset"..i;b.Text="";b.AutoButtonColor=false;b.BackgroundColor3=c;b.BorderSizePixel=0
        b.Size=UDim2.fromOffset(23,23);b.Position=UDim2.new(0,12+(i-1)*29,0,264);b.ZIndex=31;b.Parent=pop
        local q=Instance.new("UICorner");q.CornerRadius=UDim.new(1,0);q.Parent=b
        table.insert(presetButtons,{Button=b,Color=c})
    end

    local function emit(fire)
        color=Color3.fromHSV(hue,sat,val);chip.BackgroundColor3=color;sv.BackgroundColor3=Color3.fromHSV(hue,1,1)
        cursor.Position=UDim2.new(sat,-6,1-val,-6);hueCursor.Position=UDim2.new(hue,-2,0,-3)
        hex.Text="#"..color:ToHex()
        rgb.Text=string.format("R %d  G %d  B %d",math.floor(color.R*255+.5),math.floor(color.G*255+.5),math.floor(color.B*255+.5))
        if fire then changed:Fire(color,alpha);if config.Callback then task.spawn(config.Callback,color,alpha)end end
    end
    local function setSV(position)
        sat=math.clamp(position.X/math.max(sv.AbsoluteSize.X,1),0,1)
        val=1-math.clamp(position.Y/math.max(sv.AbsoluteSize.Y,1),0,1);emit(true)
    end
    local function setHue(position)
        hue=math.clamp(position.X/math.max(hueBar.AbsoluteSize.X,1),0,1);emit(true)
    end
    cleanup:AddConnection(sv.InputBegan:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then draggingSV=true;setSV(input.Position-sv.AbsolutePosition) end
    end))
    cleanup:AddConnection(hueBar.InputBegan:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then draggingHue=true;setHue(input.Position-hueBar.AbsolutePosition) end
    end))
    cleanup:AddConnection(UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch then
            if draggingSV then setSV(input.Position-sv.AbsolutePosition) end
            if draggingHue then setHue(input.Position-hueBar.AbsolutePosition) end
        end
    end))
    cleanup:AddConnection(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then draggingSV=false;draggingHue=false end
    end))
    cleanup:AddConnection(hex.FocusLost:Connect(function()
        local raw=hex.Text:gsub("#",""):gsub("%s","")
        if #raw==6 then local ok,c=pcall(function()return Color3.fromHex(raw)end);if ok and c then color=c;hue,sat,val=Color3.toHSV(c);emit(true)else warn("[LunarUI] Invalid hex color")end
        else warn("[LunarUI] Hex color must be RRGGBB")end
    end))
    for _,entry in ipairs(presetButtons) do cleanup:AddConnection(entry.Button.MouseButton1Click:Connect(function()
        color=entry.Color;hue,sat,val=Color3.toHSV(color);emit(true)
    end)) end
    cleanup:AddConnection(chip.MouseButton1Click:Connect(function()
        if not open then open=true;frame.Size=UDim2.new(1,0,0,height+7+306);pop.Visible=true
            TweenEngine.Play(frame,{Size=UDim2.new(1,0,0,height+7+306)},{Duration=.22,Easing="QuadOut"})
        else open=false;pop.Visible=false;frame.Size=UDim2.new(1,0,0,height) end
    end))
    cleanup:AddInstance(frame)
    local comp={Frame=frame,Cleanup=cleanup,Changed=changed}
    function comp:RefreshTheme()
        frame.BackgroundColor3=Theme.Secondary;label.TextColor3=Theme.Text;label.Font=Theme.Font
        border.Color=Theme.Border;chipStroke.Color=Theme.Border;pop.BackgroundColor3=Theme.Tertiary;popSt.Color=Theme.Border
        hex.BackgroundColor3=Theme.Background;hex.TextColor3=Theme.Text;rgb.TextColor3=Theme.SecondaryText
    end
    function comp:Set(c,suppress)
        if typeof(c)~="Color3" then return end;color=c;hue,sat,val=Color3.toHSV(c);emit(not suppress)
    end
    function comp:Get() return color end
    function comp:GetTransparency() return alpha end
    function comp:SetTransparency(a,suppress) alpha=math.clamp(tonumber(a)or 0,0,1);if not suppress and config.Callback then task.spawn(config.Callback,color,alpha)end end
    function comp:Reset() self:Set(config.Default or Color3.fromRGB(151,124,255)) end
    function comp:Destroy() changed:Destroy();cleanup:Destroy() end
    table.insert(tab.Components,comp)
    if config.Flag and tab.Window.Library then tab.Window.Library.Flags[config.Flag]=comp end
    return comp
end

-- MULTI SELECT DROPDOWN; selections are returned as a fresh array.
local function CreateMultiDropdown(tab, config)
    config=config or {};config.Options=config.Options or {}
    local cleanup=CreateCleanup();local parent=GetParentForComponent(tab)
    local selected={};local initial=config.Default or {}
    if type(initial)~="table" then initial={initial} end
    for _,v in ipairs(initial) do selected[tostring(v)]=true end
    local closedH=Theme.ElementHeight;local optionH=config.OptionHeight or 28;local maxH=config.MaxHeight or 160
    local open=false;local dead=false;local changed=CreateSignal()
    local frame=Instance.new("Frame");frame.Name="MultiDropdown_"..(config.Name or "Options");frame.BackgroundColor3=Theme.Secondary
    frame.BackgroundTransparency=.12;frame.BorderSizePixel=0;frame.Size=UDim2.new(1,0,0,closedH);frame.ClipsDescendants=true;frame.Parent=parent
    local cr=Instance.new("UICorner");cr.CornerRadius=UDim.new(0,Theme.CornerRadius);cr.Parent=frame
    local st=Instance.new("UIStroke");st.Color=Theme.Border;st.Transparency=.5;st.Parent=frame
    local title=Instance.new("TextLabel");title.BackgroundTransparency=1;title.Font=Theme.Font;title.TextSize=13;title.TextColor3=Theme.Text
    title.TextXAlignment=Enum.TextXAlignment.Left;title.Position=UDim2.fromOffset(12,0);title.Size=UDim2.new(1,-44,0,closedH);title.Parent=frame
    local arrow=Instance.new("TextLabel");arrow.BackgroundTransparency=1;arrow.Font=Enum.Font.GothamBold;arrow.TextSize=12;arrow.TextColor3=Theme.SecondaryText
    arrow.Text="▼";arrow.Size=UDim2.fromOffset(20,closedH);arrow.Position=UDim2.new(1,-28,0,0);arrow.Parent=frame
    local list=Instance.new("ScrollingFrame");list.BackgroundColor3=Theme.Tertiary;list.BorderSizePixel=0;list.Size=UDim2.new(1,-12,0,0)
    list.Position=UDim2.fromOffset(6,closedH+5);list.CanvasSize=UDim2.new();list.ScrollBarThickness=4;list.Visible=false;list.Parent=frame
    local lc=Instance.new("UICorner");lc.CornerRadius=UDim.new(0,5);lc.Parent=list
    local layout=Instance.new("UIListLayout");layout.SortOrder=Enum.SortOrder.LayoutOrder;layout.Padding=UDim.new(0,3);layout.Parent=list
    local function array() local out={};for _,opt in ipairs(config.Options)do if selected[tostring(opt)]then table.insert(out,opt)end end;return out end
    local function refreshTitle()
        local a=array();title.Text=(config.Name or "Select").."  •  "..(#a>0 and table.concat(a,", ")or "None")
    end
    local function resizeList()
        local h=math.min(#config.Options*optionH,maxH);list.Size=UDim2.new(1,-12,0,h);list.CanvasSize=UDim2.new(0,0,0,#config.Options*(optionH+3))
        frame.Size=UDim2.new(1,0,0,closedH+(open and h+7 or 0))
    end
    local function build()
        for _,o in ipairs(list:GetChildren())do if o:IsA("TextButton")then o:Destroy()end end
        for i,opt in ipairs(config.Options)do
            local b=Instance.new("TextButton");b.AutoButtonColor=false;b.BackgroundColor3=selected[tostring(opt)]and Theme.Hover or Theme.Tertiary;b.BorderSizePixel=0
            b.Font=Theme.Font;b.TextSize=12;b.TextColor3=Theme.Text;b.TextXAlignment=Enum.TextXAlignment.Left
            b.Text=(selected[tostring(opt)]and "✓   "or "      ")..tostring(opt);b.Size=UDim2.new(1,-5,0,optionH);b.LayoutOrder=i;b.Parent=list
            local pad=Instance.new("UIPadding");pad.PaddingLeft=UDim.new(0,8);pad.Parent=b
            cleanup:AddConnection(b.MouseButton1Click:Connect(function()
                if dead then return end;selected[tostring(opt)]=not selected[tostring(opt)] or nil
                b.BackgroundColor3=selected[tostring(opt)]and Theme.Hover or Theme.Tertiary;b.Text=(selected[tostring(opt)]and "✓   "or "      ")..tostring(opt)
                refreshTitle();changed:Fire(array());if config.Callback then task.spawn(config.Callback,array())end
            end))
        end
        refreshTitle();resizeList()
    end
    cleanup:AddConnection(title:GetPropertyChangedSignal("Text"):Connect(function()end))
    local hit=Instance.new("TextButton");hit.BackgroundTransparency=1;hit.Text="";hit.Size=UDim2.new(1,0,0,closedH);hit.ZIndex=4;hit.Parent=frame
    cleanup:AddConnection(hit.MouseButton1Click:Connect(function()
        open=not open;list.Visible=open;arrow.Text=open and "▲"or"▼";resizeList()
        TweenEngine.Play(frame,{Size=UDim2.new(1,0,0,closedH+(open and math.min(#config.Options*optionH,maxH)+7 or 0))},{Duration=.18,Easing="QuadOut"})
    end))
    build();cleanup:AddInstance(frame)
    local comp={Frame=frame,Cleanup=cleanup,Changed=changed}
    function comp:RefreshTheme()
        frame.BackgroundColor3=Theme.Secondary;st.Color=Theme.Border;title.Font=Theme.Font;title.TextColor3=Theme.Text;list.BackgroundColor3=Theme.Tertiary;arrow.TextColor3=Theme.SecondaryText
        for _,b in ipairs(list:GetChildren())do if b:IsA("TextButton")then b.Font=Theme.Font;b.TextColor3=Theme.Text end end
    end
    function comp:Get() return array() end
    function comp:Set(values,suppress)
        selected={};if type(values)~="table"then values={values}end
        for _,v in ipairs(values)do selected[tostring(v)]=true end;build()
        if not suppress then changed:Fire(array());if config.Callback then task.spawn(config.Callback,array())end end
    end
    function comp:Refresh(values,keep)
        local previous=array();config.Options=values or {};if not keep then selected={}else selected={};for _,v in ipairs(previous)do selected[tostring(v)]=true end end;build()
    end
    function comp:Destroy()dead=true;changed:Destroy();cleanup:Destroy()end
    table.insert(tab.Components,comp);if config.Flag and tab.Window.Library then tab.Window.Library.Flags[config.Flag]=comp end
    return comp
end

-- Progress meter, percentage setter, increment helper.
local function CreateProgressBar(tab, config)
    config=config or {};local cleanup=CreateCleanup();local parent=GetParentForComponent(tab)
    local value=math.clamp(tonumber(config.Default)or 0,0,100)
    local frame=Instance.new("Frame");frame.Name="Progress_"..(config.Name or "Progress");frame.BackgroundColor3=Theme.Secondary;frame.BorderSizePixel=0
    frame.Size=UDim2.new(1,0,0,config.Height or 54);frame.Parent=parent
    local cr=Instance.new("UICorner");cr.CornerRadius=UDim.new(0,Theme.CornerRadius);cr.Parent=frame
    local title=Instance.new("TextLabel");title.BackgroundTransparency=1;title.Font=Theme.Font;title.TextSize=12;title.TextColor3=Theme.Text
    title.TextXAlignment=Enum.TextXAlignment.Left;title.Position=UDim2.fromOffset(12,4);title.Size=UDim2.new(1,-90,0,20);title.Text=config.Name or "Progress";title.Parent=frame
    local valLabel=Instance.new("TextLabel");valLabel.BackgroundTransparency=1;valLabel.Font=Theme.FontMono;valLabel.TextSize=11;valLabel.TextColor3=Theme.SecondaryText
    valLabel.TextXAlignment=Enum.TextXAlignment.Right;valLabel.Position=UDim2.new(1,-75,0,4);valLabel.Size=UDim2.fromOffset(62,20);valLabel.Parent=frame
    local track=Instance.new("Frame");track.BackgroundColor3=Theme.SliderTrack;track.BorderSizePixel=0;track.Position=UDim2.new(0,12,0,31);track.Size=UDim2.new(1,-24,0,8);track.Parent=frame
    local tc=Instance.new("UICorner");tc.CornerRadius=UDim.new(1,0);tc.Parent=track
    local fill=Instance.new("Frame");fill.BackgroundColor3=config.Color or Theme.SliderFill;fill.BorderSizePixel=0;fill.Size=UDim2.new(value/100,0,1,0);fill.Parent=track
    local fc=Instance.new("UICorner");fc.CornerRadius=UDim.new(1,0);fc.Parent=fill
    local changed=CreateSignal()
    local function set(v,suppress) value=math.clamp(tonumber(v)or 0,0,100);fill.Size=UDim2.new(value/100,0,1,0);valLabel.Text=string.format("%d%%",math.floor(value+.5));if not suppress then changed:Fire(value);if config.Callback then task.spawn(config.Callback,value)end end end
    set(value,true);cleanup:AddInstance(frame)
    local comp={Frame=frame,Cleanup=cleanup,Changed=changed}
    function comp:Set(v,suppress)set(v,suppress)end;function comp:Get()return value end;function comp:Increment(d)set(value+(tonumber(d)or 1))end
    function comp:RefreshTheme()frame.BackgroundColor3=Theme.Secondary;title.TextColor3=Theme.Text;title.Font=Theme.Font;valLabel.TextColor3=Theme.SecondaryText;track.BackgroundColor3=Theme.SliderTrack;if not config.Color then fill.BackgroundColor3=Theme.SliderFill end end
    function comp:Destroy()changed:Destroy();cleanup:Destroy()end
    table.insert(tab.Components,comp);if config.Flag and tab.Window.Library then tab.Window.Library.Flags[config.Flag]=comp end;return comp
end

local function CreateParagraph(tab, config)
    config=config or {};local cleanup=CreateCleanup();local parent=GetParentForComponent(tab)
    local frame=Instance.new("Frame");frame.Name="Paragraph_"..(config.Title or "Info");frame.BackgroundColor3=Theme.Secondary;frame.BorderSizePixel=0
    frame.Size=UDim2.new(1,0,0,0);frame.AutomaticSize=Enum.AutomaticSize.Y;frame.Parent=parent
    local cr=Instance.new("UICorner");cr.CornerRadius=UDim.new(0,Theme.CornerRadius);cr.Parent=frame
    local st=Instance.new("UIStroke");st.Color=Theme.Border;st.Transparency=.5;st.Parent=frame
    local pad=Instance.new("UIPadding");pad.PaddingTop=UDim.new(0,11);pad.PaddingBottom=UDim.new(0,12);pad.PaddingLeft=UDim.new(0,13);pad.PaddingRight=UDim.new(0,13);pad.Parent=frame
    local layout=Instance.new("UIListLayout");layout.Padding=UDim.new(0,6);layout.SortOrder=Enum.SortOrder.LayoutOrder;layout.Parent=frame
    local title=Instance.new("TextLabel");title.BackgroundTransparency=1;title.Font=Theme.FontBold;title.TextSize=13;title.TextColor3=Theme.Text
    title.TextXAlignment=Enum.TextXAlignment.Left;title.Text=config.Title or "Information";title.Size=UDim2.new(1,0,0,18);title.LayoutOrder=1;title.Parent=frame
    local body=Instance.new("TextLabel");body.BackgroundTransparency=1;body.Font=Theme.Font;body.TextSize=12;body.TextColor3=Theme.SecondaryText
    body.TextXAlignment=Enum.TextXAlignment.Left;body.TextYAlignment=Enum.TextYAlignment.Top;body.TextWrapped=true;body.AutomaticSize=Enum.AutomaticSize.Y
    body.Size=UDim2.new(1,0,0,0);body.Text=config.Content or config.Description or "";body.LayoutOrder=2;body.Parent=frame
    cleanup:AddInstance(frame);local comp={Frame=frame,Cleanup=cleanup,Title=title,Body=body}
    function comp:SetText(t)body.Text=tostring(t)end;function comp:SetTitle(t)title.Text=tostring(t)end
    function comp:RefreshTheme()frame.BackgroundColor3=Theme.Secondary;st.Color=Theme.Border;title.Font=Theme.FontBold;title.TextColor3=Theme.Text;body.Font=Theme.Font;body.TextColor3=Theme.SecondaryText end
    function comp:Destroy()cleanup:Destroy()end
    table.insert(tab.Components,comp);return comp
end

local function CreateButtonGroup(tab, config)
    config=config or {};local cleanup=CreateCleanup();local parent=GetParentForComponent(tab)
    local frame=Instance.new("Frame");frame.Name="ButtonGroup_"..(config.Name or "Actions");frame.BackgroundTransparency=1;frame.Size=UDim2.new(1,0,0,Theme.ElementHeight);frame.Parent=parent
    local layout=Instance.new("UIListLayout");layout.FillDirection=Enum.FillDirection.Horizontal;layout.Padding=UDim.new(0,6);layout.SortOrder=Enum.SortOrder.LayoutOrder;layout.Parent=frame
    local buttons={};local options=config.Buttons or {}
    for i,opt in ipairs(options)do
        local btn=Instance.new("TextButton");btn.AutoButtonColor=false;btn.BackgroundColor3=Theme.Secondary;btn.BorderSizePixel=0;btn.Font=Theme.Font;btn.TextSize=12
        btn.TextColor3=Theme.Text;btn.Text=opt.Name or tostring(opt);btn.Size=UDim2.new(1/math.max(#options,1),-6,1,0);btn.LayoutOrder=i;btn.Parent=frame
        local cr=Instance.new("UICorner");cr.CornerRadius=UDim.new(0,Theme.CornerRadius);cr.Parent=btn
        local st=Instance.new("UIStroke");st.Color=Theme.Border;st.Transparency=.5;st.Parent=btn
        cleanup:AddConnection(btn.MouseButton1Click:Connect(function()if opt.Callback then task.spawn(opt.Callback)end;if config.Callback then task.spawn(config.Callback,opt.Name or opt,i)end end))
        table.insert(buttons,btn)
    end
    cleanup:AddInstance(frame);local comp={Frame=frame,Cleanup=cleanup,Buttons=buttons}
    function comp:RefreshTheme()for _,b in ipairs(buttons)do b.BackgroundColor3=Theme.Secondary;b.TextColor3=Theme.Text;b.Font=Theme.Font;local q=b:FindFirstChildOfClass("UIStroke");if q then q.Color=Theme.Border end end end
    function comp:Destroy()cleanup:Destroy()end
    table.insert(tab.Components,comp);return comp
end

-- DIVIDER
local function CreateDivider(tab)
	local cleanup = CreateCleanup()
	local parent = GetParentForComponent(tab)

	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, 12)
	frame.Parent = parent

	local line = Instance.new("Frame")
	line.BackgroundColor3 = Theme.Border
	line.BackgroundTransparency = 0.5
	line.BorderSizePixel = 0
	line.Size = UDim2.new(1, 0, 0, 1)
	line.Position = UDim2.new(0, 0, 0.5, 0)
	line.Parent = frame

	cleanup:AddInstance(frame)

	local div = { Frame = frame, Cleanup = cleanup }
	function div:RefreshTheme()
		if cleanup:IsDestroyed() then return end
		line.BackgroundColor3 = Theme.Border
	end
	function div:Destroy() cleanup:Destroy() end
	table.insert(tab.Components, div)
	return div
end

----------------------------------------------------------------
-- TAB
----------------------------------------------------------------
local function CreateTab(window, config)
	config = config or {}
	local cleanup = CreateCleanup()
	local name = config.Name or "Tab"

	local content = Instance.new("ScrollingFrame")
	content.Name = "TabContent_" .. name
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Size = UDim2.new(1, 0, 1, 0)
	-- Keep the window at a fixed size and make long tabs scroll instead of
	-- allowing component content to run off-screen.
	content.CanvasSize = UDim2.new(0, 0, 0, 0)
	content.AutomaticCanvasSize = Enum.AutomaticSize.None
	content.ScrollingDirection = Enum.ScrollingDirection.Y
	content.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	content.Active = true
	content.ScrollBarThickness = 5
	content.ScrollBarImageColor3 = Theme.Border
	content.ScrollBarImageTransparency = 0.15
	content.Visible = false
	content.Parent = window.ContentContainer

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = content

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.Parent = content

	-- AutomaticCanvasSize can be unreliable with dynamically resized controls
	-- (dropdowns/sections). Track the list's actual height explicitly.
	local function updateCanvas()
		local height = layout.AbsoluteContentSize.Y + padding.PaddingTop.Offset + padding.PaddingBottom.Offset
		content.CanvasSize = UDim2.new(0, 0, 0, math.max(0, height))
	end
	cleanup:AddConnection(layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas))
	cleanup:AddConnection(content:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateCanvas))
	task.defer(updateCanvas)

	local tabBtn = Instance.new("TextButton")
	tabBtn.Name = "TabBtn_" .. name
	tabBtn.BackgroundColor3 = Theme.Secondary
	tabBtn.BackgroundTransparency = 1
	tabBtn.BorderSizePixel = 0
	tabBtn.Size = UDim2.new(0, 90, 0, 28)
	tabBtn.Font = Theme.Font
	tabBtn.TextSize = 12
	tabBtn.TextColor3 = Theme.SecondaryText
	tabBtn.Text = name
	tabBtn.AutoButtonColor = false
	local navIsSide = window.Layout == "side"
	tabBtn.Size = navIsSide and UDim2.new(1, -8, 0, 34) or UDim2.new(0, 98, 0, 28)
	tabBtn.TextXAlignment = Enum.TextXAlignment.Left
	if config.Icon then
		tabBtn.Text = "   " .. name
		tabBtn.Parent = navIsSide and window.Sidebar or window.TabBar
		local icon = DrawVectorIcon(tabBtn, config.Icon, Theme.SecondaryText, 15, window.IconProvider)
		if icon then icon.Position = UDim2.fromOffset(7, (tabBtn.Size.Y.Offset-15)/2) end
	else
		tabBtn.Parent = navIsSide and window.Sidebar or window.TabBar
	end

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 4)
	btnCorner.Parent = tabBtn

	cleanup:AddInstance(content)
	cleanup:AddInstance(tabBtn)

	local tab = {
		Name = name,
		Icon = config.Icon,
		Content = content,
		Button = tabBtn,
		IconObject = config.Icon and tabBtn:FindFirstChild("Lucide_" .. tostring(config.Icon)) or nil,
		Sections = {},
		Components = {},
		Cleanup = cleanup,
		Window = window,
	}

	cleanup:AddConnection(tabBtn.MouseButton1Click:Connect(function()
		window:SelectTab(tab)
	end))

	function tab:SetActive(active)
		if active then
			updateCanvas()
			-- A newly selected tab always starts at the top.
			content.CanvasPosition = Vector2.new(0, 0)
			content.Visible = true
			tabBtn.BackgroundTransparency = 0.05
			tabBtn.BackgroundColor3 = Theme.Hover
			tabBtn.TextColor3 = Theme.Text
		else
			content.Visible = false
			tabBtn.BackgroundTransparency = 1
			tabBtn.TextColor3 = Theme.SecondaryText
		end
	end

	function tab:RefreshTheme()
		if cleanup:IsDestroyed() then return end
		content.ScrollBarImageColor3 = Theme.Border
		tabBtn.BackgroundColor3 = Theme.Secondary
		tabBtn.Font = Theme.Font
		if content.Visible then
			tabBtn.BackgroundTransparency = 0.3
			tabBtn.TextColor3 = Theme.Text
		else
			tabBtn.BackgroundTransparency = 1
			tabBtn.TextColor3 = Theme.SecondaryText
		end
		for _, s in ipairs(tab.Sections) do
			if s.RefreshTheme then s:RefreshTheme() end
		end
		for _, c in ipairs(tab.Components) do
			if c.RefreshTheme then c:RefreshTheme() end
		end
	end

	function tab:CreateSection(c) return CreateSection(tab, c) end
	local function makeComponent(factory, c, name)
        if name == "Colorpicker" and window.Config.Colorpicker == false then
            warn("[LunarUI] Colorpicker feature is disabled in this window config")
            return nil
        end
		local ok, component = pcall(factory, tab, c)
		if not ok then warn("[LunarUI][Component:" .. tostring(name) .. "]", component); return nil end
		if type(c)=="table" and c.Flag then window.Library.Flags[c.Flag]=component end
		return component
	end
	function tab:CreateButton(c) return makeComponent(CreateButton, c, "Button") end
	function tab:CreateToggle(c) return makeComponent(CreateToggle, c, "Toggle") end
	function tab:CreateSlider(c) return makeComponent(CreateSlider, c, "Slider") end
	function tab:CreateLabel(c) return makeComponent(CreateLabel, c, "Label") end
	function tab:CreateDropdown(c) return makeComponent(CreateDropdown, c, "Dropdown") end
	function tab:CreateTextbox(c) return makeComponent(CreateTextbox, c, "Textbox") end
	function tab:CreateKeybind(c) return makeComponent(CreateKeybind, c, "Keybind") end
	function tab:CreateDivider(c) return makeComponent(CreateDivider, nil, "Divider") end
	function tab:CreateColorpicker(c) return makeComponent(CreateColorpicker, c, "Colorpicker") end
	function tab:CreateColorPicker(c) return makeComponent(CreateColorpicker, c, "Colorpicker") end
	function tab:CreateMultiDropdown(c) return makeComponent(CreateMultiDropdown, c, "MultiDropdown") end
	function tab:CreateProgressBar(c) return makeComponent(CreateProgressBar, c, "ProgressBar") end
	function tab:CreateParagraph(c) return makeComponent(CreateParagraph, c, "Paragraph") end
	function tab:CreateButtonGroup(c) return makeComponent(CreateButtonGroup, c, "ButtonGroup") end
	function tab:CreateStatus(c)
		c = c or {}
		return makeComponent(CreateLabel, { Name = (c.Name or "Status") .. "  •  " .. (c.Value or "Ready"), Description = c.Description }, "Status")
	end
	function tab:CreateInput(c) return makeComponent(CreateTextbox, c, "Input") end
	function tab:CreateTextBox(c) return makeComponent(CreateTextbox, c, "Textbox") end
	function tab:CreateProgress(c) return makeComponent(CreateProgressBar, c, "Progress") end
	function tab:AddButton(c) return tab:CreateButton(c) end
	function tab:AddToggle(c) return tab:CreateToggle(c) end
	function tab:AddSlider(c) return tab:CreateSlider(c) end
	function tab:AddDropdown(c) return tab:CreateDropdown(c) end
	function tab:AddColorpicker(c) return tab:CreateColorpicker(c) end
	function tab:AddColorPicker(c) return tab:CreateColorpicker(c) end
	function tab:AddKeybind(c) return tab:CreateKeybind(c) end
	function tab:AddTextbox(c) return tab:CreateTextbox(c) end
	function tab:AddLabel(c) return tab:CreateLabel(c) end
	function tab:AddParagraph(c) return tab:CreateParagraph(c) end
	function tab:AddSection(c) return tab:CreateSection(c) end
	function tab:CreateSwitch(c) return tab:CreateToggle(c) end
	function tab:CreateRange(c) return tab:CreateSlider(c) end
	function tab:CreateColor(c) return tab:CreateColorpicker(c) end
	function tab:CreateMultiSelect(c) return tab:CreateMultiDropdown(c) end
	function tab:CreateChoice(c) return tab:CreateDropdown(c) end
	function tab:CreateTextDisplay(c) return tab:CreateParagraph(c) end

	function tab:Destroy()
		for _, c in ipairs(tab.Components) do
			if c.Destroy then c:Destroy() end
		end
		for _, s in ipairs(tab.Sections) do
			if s.Destroy then s:Destroy() end
		end
		cleanup:Destroy()
	end

	return tab
end

----------------------------------------------------------------
-- PRISM GLASS / IMAGE BACKDROP
-- Fluent's public example exposes an Acrylic option and credits a standalone
-- acrylic component. LunarUI uses an independent layered composition instead:
-- optional wallpaper ImageLabel, tinted base, multi-stop gradient veil, soft
-- abstract light forms, a specular sweep and an optional Lighting blur effect.
-- Roblox does not provide a per-ImageLabel blur kernel, so world blur is handled
-- separately and image blur is best supplied as a pre-blurred asset when wanted.
----------------------------------------------------------------
local function NormalizeImageId(value)
    if value == nil then return "" end
    if type(value) == "number" then return "rbxassetid://" .. tostring(math.floor(value)) end
    local text = tostring(value):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return "" end
    if text:match("^%d+$") then return "rbxassetid://" .. text end
    return text
end

local function BuildColorSequence(colors, fallbackA, fallbackB, fallbackC)
    if typeof(colors) == "ColorSequence" then return colors end
    if type(colors) ~= "table" or #colors < 2 then
        return ColorSequence.new({
            ColorSequenceKeypoint.new(0, fallbackA),
            ColorSequenceKeypoint.new(0.52, fallbackB or fallbackA),
            ColorSequenceKeypoint.new(1, fallbackC or fallbackA),
        })
    end
    local points = {}
    for index, item in ipairs(colors) do
        local color = item
        local time = (#colors == 1) and 0 or ((index - 1) / (#colors - 1))
        if type(item) == "table" then
            color = item.Color or item[1]
            time = tonumber(item.Time or item[2]) or time
        end
        if typeof(color) == "Color3" then
            table.insert(points, ColorSequenceKeypoint.new(math.clamp(time, 0, 1), color))
        end
    end
    if #points < 2 then
        return ColorSequence.new(fallbackA, fallbackC or fallbackA)
    end
    table.sort(points, function(a, b) return a.Time < b.Time end)
    if points[1].Time > 0 then table.insert(points, 1, ColorSequenceKeypoint.new(0, points[1].Value)) end
    if points[#points].Time < 1 then table.insert(points, ColorSequenceKeypoint.new(1, points[#points].Value)) end
    return ColorSequence.new(points)
end

local function SetGuiImage(imageObject, imageValue)
    local image = NormalizeImageId(imageValue)
    imageObject.Image = image
    imageObject.Visible = image ~= ""
    return image
end

local function CreateGlassBackdrop(main, config, theme, cleanup)
    local stack = Instance.new("Frame")
    stack.Name = "PrismGlassBackdrop"
    stack.BackgroundTransparency = 1
    stack.BorderSizePixel = 0
    stack.Size = UDim2.fromScale(1, 1)
    stack.ClipsDescendants = true
    stack.ZIndex = 1
    stack.Parent = main

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, tonumber(config.GlassCornerRadius) or 16)
    corner.Parent = stack

    local base = Instance.new("Frame")
    base.Name = "GlassBase"
    base.BackgroundColor3 = config.GlassBaseColor or theme.Background
    base.BackgroundTransparency = math.clamp(tonumber(config.GlassTransparency) or 0.34, 0.08, 0.88)
    base.BorderSizePixel = 0
    base.Size = UDim2.fromScale(1, 1)
    base.ZIndex = 1
    base.Parent = stack

    local wallpaper = Instance.new("ImageLabel")
    wallpaper.Name = "UserWallpaper"
    wallpaper.BackgroundTransparency = 1
    wallpaper.BorderSizePixel = 0
    wallpaper.Size = UDim2.fromScale(1, 1)
    wallpaper.Position = UDim2.fromScale(0, 0)
    wallpaper.Image = NormalizeImageId(config.BackgroundImage or config.Wallpaper or config.ImageBackground)
    wallpaper.ImageTransparency = math.clamp(tonumber(config.BackgroundImageTransparency) or 0.16, 0, 1)
    wallpaper.ImageColor3 = config.BackgroundImageTint or Color3.new(1, 1, 1)
    wallpaper.ScaleType = Enum.ScaleType.Crop
    wallpaper.Visible = wallpaper.Image ~= ""
    wallpaper.ZIndex = 2
    wallpaper.Parent = stack

    -- A custom asset texture can be used for detailed art; when no image is
    -- supplied, the soft aurora shapes below still make the glass feel designed.
    local orbA = Instance.new("Frame")
    orbA.Name = "AuroraBloom_A"
    orbA.AnchorPoint = Vector2.new(0.5, 0.5)
    orbA.Position = UDim2.new(0.18, 0, 0.18, 0)
    orbA.Size = UDim2.new(0.74, 0, 0.64, 0)
    orbA.BackgroundColor3 = config.GlassColor or theme.Accent
    orbA.BackgroundTransparency = wallpaper.Visible and 0.84 or 0.68
    orbA.BorderSizePixel = 0
    orbA.ZIndex = 3
    orbA.Parent = stack
    local orbACorner = Instance.new("UICorner")
    orbACorner.CornerRadius = UDim.new(1, 0)
    orbACorner.Parent = orbA
    local orbAGradient = Instance.new("UIGradient")
    orbAGradient.Color = BuildColorSequence(config.GlassGradient, config.GlassColor or theme.Accent, theme.Accent2 or Color3.fromRGB(64, 225, 220), theme.Background)
    orbAGradient.Rotation = tonumber(config.GradientRotation) or 22
    orbAGradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.18),
        NumberSequenceKeypoint.new(0.48, 0.55),
        NumberSequenceKeypoint.new(1, 0.12),
    })
    orbAGradient.Parent = orbA

    local orbB = Instance.new("Frame")
    orbB.Name = "AuroraBloom_B"
    orbB.AnchorPoint = Vector2.new(0.5, 0.5)
    orbB.Position = UDim2.new(0.94, 0, 0.82, 0)
    orbB.Size = UDim2.new(0.82, 0, 0.78, 0)
    orbB.BackgroundColor3 = theme.Accent2 or Color3.fromRGB(63, 224, 213)
    orbB.BackgroundTransparency = wallpaper.Visible and 0.88 or 0.77
    orbB.BorderSizePixel = 0
    orbB.ZIndex = 3
    orbB.Parent = stack
    local orbBCorner = Instance.new("UICorner")
    orbBCorner.CornerRadius = UDim.new(1, 0)
    orbBCorner.Parent = orbB
    local orbBGradient = Instance.new("UIGradient")
    orbBGradient.Color = BuildColorSequence({theme.Accent2 or theme.Accent, config.GlassColor or theme.Accent, theme.Background}, theme.Accent, theme.Accent2 or theme.Accent, theme.Background)
    orbBGradient.Rotation = tonumber(config.GradientRotation) or 210
    orbBGradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.35),
        NumberSequenceKeypoint.new(0.5, 0.68),
        NumberSequenceKeypoint.new(1, 0.15),
    })
    orbBGradient.Parent = orbB

    local tint = Instance.new("Frame")
    tint.Name = "GlassTintVeil"
    tint.BackgroundColor3 = config.GlassColor or theme.Accent
    tint.BackgroundTransparency = math.clamp(tonumber(config.GlassTintTransparency) or 0.61, 0.12, 0.94)
    tint.BorderSizePixel = 0
    tint.Size = UDim2.fromScale(1, 1)
    tint.ZIndex = 4
    tint.Parent = stack
    local tintGradient = Instance.new("UIGradient")
    tintGradient.Color = BuildColorSequence(config.GlassGradient, config.GlassColor or theme.Accent, theme.Accent2 or Color3.fromRGB(64, 225, 220), theme.Background)
    tintGradient.Rotation = tonumber(config.GradientRotation) or 18
    tintGradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.28),
        NumberSequenceKeypoint.new(0.46, 0.58),
        NumberSequenceKeypoint.new(1, 0.18),
    })
    tintGradient.Parent = tint

    local shine = Instance.new("Frame")
    shine.Name = "GlassSpecularSweep"
    shine.BackgroundColor3 = Color3.new(1, 1, 1)
    shine.BackgroundTransparency = 0.92
    shine.BorderSizePixel = 0
    shine.Position = UDim2.new(-0.22, 0, -0.25, 0)
    shine.Size = UDim2.new(0.48, 0, 1.6, 0)
    shine.Rotation = 18
    shine.ZIndex = 5
    shine.Parent = stack
    local shineGradient = Instance.new("UIGradient")
    shineGradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(1, 1, 1))
    shineGradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.45, 0.83),
        NumberSequenceKeypoint.new(0.52, 0.56),
        NumberSequenceKeypoint.new(0.6, 0.85),
        NumberSequenceKeypoint.new(1, 1),
    })
    shineGradient.Parent = shine

    local topEdge = Instance.new("Frame")
    topEdge.Name = "GlassTopHighlight"
    topEdge.BackgroundColor3 = Color3.new(1, 1, 1)
    topEdge.BackgroundTransparency = 0.60
    topEdge.BorderSizePixel = 0
    topEdge.Position = UDim2.fromOffset(14, 1)
    topEdge.Size = UDim2.new(1, -28, 0, 1)
    topEdge.ZIndex = 7
    topEdge.Parent = stack
    local edgeGradient = Instance.new("UIGradient")
    edgeGradient.Color = BuildColorSequence({theme.Accent, Color3.new(1, 1, 1), theme.Accent2 or theme.Accent}, theme.Accent, Color3.new(1, 1, 1), theme.Accent)
    edgeGradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.75),
        NumberSequenceKeypoint.new(0.5, 0.10),
        NumberSequenceKeypoint.new(1, 0.75),
    })
    edgeGradient.Parent = topEdge

    local optionalTexture = Instance.new("ImageLabel")
    optionalTexture.Name = "GlassTextureOverlay"
    optionalTexture.BackgroundTransparency = 1
    optionalTexture.BorderSizePixel = 0
    optionalTexture.Size = UDim2.fromScale(1, 1)
    optionalTexture.Image = NormalizeImageId(config.GlassTextureImage or config.NoiseImage)
    optionalTexture.ImageTransparency = math.clamp(tonumber(config.GlassTextureTransparency) or 0.93, 0, 1)
    optionalTexture.ImageColor3 = config.GlassTextureTint or Color3.new(1, 1, 1)
    optionalTexture.ScaleType = Enum.ScaleType.Tile
    optionalTexture.TileSize = UDim2.fromOffset(96, 96)
    optionalTexture.Visible = optionalTexture.Image ~= ""
    optionalTexture.ZIndex = 6
    optionalTexture.Parent = stack

    local blur
    if config.WorldBlur ~= false and config.AcrylicBlur ~= false then
        blur = Instance.new("BlurEffect")
        blur.Name = "LunarUI_AcrylicBlur"
        blur.Size = math.clamp(tonumber(config.BlurSize) or 8, 0, 24)
        blur.Enabled = true
        blur.Parent = Lighting
        cleanup:AddInstance(blur)
    end

    local result = {
        Stack = stack,
        Base = base,
        Wallpaper = wallpaper,
        Tint = tint,
        TintGradient = tintGradient,
        OrbA = orbA,
        OrbB = orbB,
        OrbAGradient = orbAGradient,
        OrbBGradient = orbBGradient,
        Shine = shine,
        Texture = optionalTexture,
        TopEdge = topEdge,
        EdgeGradient = edgeGradient,
        Blur = blur,
        Color = config.GlassColor or theme.Accent,
        Transparency = math.clamp(tonumber(config.GlassTransparency) or 0.34, 0.08, 0.88),
        TintTransparency = math.clamp(tonumber(config.GlassTintTransparency) or 0.61, 0.12, 0.94),
        GradientColors = config.GlassGradient,
        GradientRotation = tonumber(config.GradientRotation) or 18,
    }
    return result
end

----------------------------------------------------------------
-- WINDOW
----------------------------------------------------------------
local function CreateWindow(library, config)
	config = config or {}
	local cleanup = CreateCleanup()
    if config.CloseSound == nil then config.CloseSound = 4307186075 end
    if config.CloseSoundVolume == nil then config.CloseSoundVolume = 0.42 end
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1024,768)
	local touchClient = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	local width = config.Width or math.min(touchClient and 420 or 760, math.max(320, viewport.X - 24))
	local height = config.Height or math.min(touchClient and 540 or 560, math.max(280, viewport.Y - 24))
	local minimized = false
	local tabs = {}
	local activeTab = nil
    local resizeHandle, settingsBtn, headerSheen, headerGradient, commandFrame

	local gui = Instance.new("ScreenGui")
	gui.Name = "LunarUI_" .. (config.Title or "Window")
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 50
	ProtectAndParent(gui)

	local main = Instance.new("Frame")
	main.Name = "Main"
	main.BackgroundColor3 = Theme.Background
	main.BackgroundTransparency = 1 -- permanent glass: all color comes from layered glass below.
	main.BorderSizePixel = 0
	main.ClipsDescendants = true
	main.Size = UDim2.new(0, width, 0, height)
	main.Position = UDim2.new(0.5, -width / 2, 0.5, -height / 2)
	main.Parent = gui

	local mainCorner = Instance.new("UICorner")
	mainCorner.CornerRadius = UDim.new(0, tonumber(config.GlassCornerRadius) or 16)
	mainCorner.Parent = main

	-- A dedicated scale transform gives all window motion the same focal point.
	-- It is animated by Lunar's scheduler, never Roblox TweenService.
	local motionScale = Instance.new("UIScale")
	motionScale.Name = "LunarMotionScale"
	motionScale.Scale = 1
	motionScale.Parent = main

    local glass = CreateGlassBackdrop(main, config, Theme, cleanup)
    main.Name = "Lunar_Prism_Glass_Window"

	local mainStroke = Instance.new("UIStroke")
	mainStroke.Color = config.GlassBorderColor or Theme.Accent
	mainStroke.Thickness = tonumber(config.GlassBorderThickness) or 1.15
	mainStroke.Transparency = tonumber(config.GlassBorderTransparency) or 0.35
	mainStroke.Parent = main

    local innerStroke = Instance.new("UIStroke")
    innerStroke.Name = "GlassInnerEdge"
    innerStroke.Color = Color3.new(1, 1, 1)
    innerStroke.Thickness = 1
    innerStroke.Transparency = 0.86
    innerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    innerStroke.Parent = main

	-- Title bar
	local titleBar = Instance.new("Frame")
	titleBar.Name = "TitleBar"
	titleBar.BackgroundColor3 = Theme.Secondary
	titleBar.BackgroundTransparency = 0.31
	titleBar.BorderSizePixel = 0
	titleBar.Size = UDim2.new(1, 0, 0, 40)
	titleBar.Parent = main

	local titleCorner = Instance.new("UICorner")
	titleCorner.CornerRadius = UDim.new(0, 8)
	titleCorner.Parent = titleBar

	local titleFix = Instance.new("Frame")
	titleFix.BackgroundColor3 = Theme.Secondary
	titleFix.BackgroundTransparency = 0.31
	titleFix.BorderSizePixel = 0
	titleFix.Size = UDim2.new(1, 0, 0, 12)
	titleFix.Position = UDim2.new(0, 0, 1, -12)
	titleFix.Parent = titleBar

	headerSheen = Instance.new("Frame")
	headerSheen.Name = "HeaderSheen"
    headerSheen.Visible = config.Shine ~= false and not (config.Features and config.Features.Shine == false)
	headerSheen.BackgroundColor3 = Theme.Accent
	headerSheen.BackgroundTransparency = 0.82
	headerSheen.BorderSizePixel = 0
	headerSheen.Size = UDim2.new(1, 0, 0, 2)
	headerSheen.Position = UDim2.new(0, 0, 1, -2)
	headerSheen.Parent = titleBar
	headerGradient = Instance.new("UIGradient")
	headerGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Theme.Accent),
		ColorSequenceKeypoint.new(0.55, Theme.Accent),
		ColorSequenceKeypoint.new(1, Theme.Accent2 or Theme.Accent),
	})
	headerGradient.Parent = headerSheen
    headerGradient.Enabled = config.Gradients ~= false and not (config.Features and config.Features.Gradients == false)

    local headerGlassGradient = Instance.new("UIGradient")
    headerGlassGradient.Name = "PrismHeaderGradient"
    headerGlassGradient.Color = BuildColorSequence(config.GlassGradient, glass.Color, Theme.Accent2 or Color3.fromRGB(64, 225, 220), Theme.Background)
    headerGlassGradient.Rotation = tonumber(config.GradientRotation) or 0
    headerGlassGradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.22),
        NumberSequenceKeypoint.new(0.48, 0.55),
        NumberSequenceKeypoint.new(1, 0.18),
    })
    headerGlassGradient.Parent = titleBar

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.new(1, -80, 0, 18)
	titleLabel.Position = UDim2.new(0, 14, 0, 6)
	titleLabel.Font = Theme.FontBold
	titleLabel.TextSize = 14
	titleLabel.TextColor3 = Theme.Text
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Text = config.Title or "LunarUI"
	titleLabel.Parent = titleBar

	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Size = UDim2.new(1, -80, 0, 14)
	subtitle.Position = UDim2.new(0, 14, 0, 22)
	subtitle.Font = Theme.Font
	subtitle.TextSize = 11
	subtitle.TextColor3 = Theme.SecondaryText
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Text = config.Subtitle or ""
	subtitle.Parent = titleBar

	local closeBtn = Instance.new("TextButton")
	closeBtn.BackgroundTransparency = 1
	closeBtn.Size = UDim2.new(0, 28, 0, 28)
	closeBtn.Position = UDim2.new(1, -34, 0.5, -14)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 16
	closeBtn.TextColor3 = Theme.SecondaryText
	closeBtn.Text = "×"
	closeBtn.Parent = titleBar

	local minBtn = Instance.new("TextButton")
	minBtn.BackgroundTransparency = 1
	minBtn.Size = UDim2.new(0, 28, 0, 28)
	minBtn.Position = UDim2.new(1, -62, 0.5, -14)
	minBtn.Font = Enum.Font.GothamBold
	minBtn.TextSize = 14
	minBtn.TextColor3 = Theme.SecondaryText
	minBtn.Text = "−"
	minBtn.Parent = titleBar

	settingsBtn = Instance.new("TextButton")
	settingsBtn.Name = "SettingsButton"
	settingsBtn.BackgroundTransparency = 1
	settingsBtn.Size = UDim2.new(0, 28, 0, 28)
	settingsBtn.Position = UDim2.new(1, -90, 0.5, -14)
	settingsBtn.Font = Enum.Font.GothamBold
	settingsBtn.TextSize = 14
	settingsBtn.TextColor3 = Theme.SecondaryText
	settingsBtn.Text = "⚙"
	settingsBtn.Parent = titleBar
    settingsBtn.Visible = config.Settings ~= false and (config.Features == nil or config.Features.Settings ~= false)

	local tabBar = Instance.new("Frame")
	tabBar.Name = "TabBar"
	tabBar.BackgroundTransparency = 1
	tabBar.Size = UDim2.new(1, -20, 0, 32)
	tabBar.Position = UDim2.new(0, 10, 0, 44)
	tabBar.Visible = string.lower(config.Layout or "top") ~= "side"
	tabBar.Parent = main

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Padding = UDim.new(0, 6)
	tabLayout.Parent = tabBar

	local sidebar = Instance.new("Frame")
	sidebar.Name = "SideTabBar"
	sidebar.BackgroundColor3 = Theme.Secondary
	sidebar.BackgroundTransparency = 0.30
	sidebar.BorderSizePixel = 0
	sidebar.Position = UDim2.new(0, 0, 0, 44)
	sidebar.Size = UDim2.new(0, 142, 1, -44)
	sidebar.Visible = string.lower(config.Layout or "top") == "side"
	sidebar.Parent = main
	local sidebarCorner = Instance.new("UICorner")
	sidebarCorner.CornerRadius = UDim.new(0, Theme.CornerRadius + 4)
	sidebarCorner.Parent = sidebar
    local sidebarStroke = Instance.new("UIStroke")
    sidebarStroke.Name = "GlassSidebarEdge"
    sidebarStroke.Color = glass.Color
    sidebarStroke.Transparency = 0.68
    sidebarStroke.Thickness = 1
    sidebarStroke.Parent = sidebar
    local sidebarGradient = Instance.new("UIGradient")
    sidebarGradient.Color = BuildColorSequence(config.GlassGradient, glass.Color, Theme.Accent2 or glass.Color, Theme.Secondary)
    sidebarGradient.Rotation = 90
    sidebarGradient.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,0.34),NumberSequenceKeypoint.new(1,0.72)})
    sidebarGradient.Parent = sidebar
	local sidebarLayout = Instance.new("UIListLayout")
	sidebarLayout.SortOrder = Enum.SortOrder.LayoutOrder
	sidebarLayout.Padding = UDim.new(0, 6)
	sidebarLayout.Parent = sidebar
	local sidebarPadding = Instance.new("UIPadding")
	sidebarPadding.PaddingTop = UDim.new(0, 10)
	sidebarPadding.PaddingLeft = UDim.new(0, 7)
	sidebarPadding.PaddingRight = UDim.new(0, 7)
	sidebarPadding.Parent = sidebar

	local contentContainer = Instance.new("Frame")
	contentContainer.Name = "ContentContainer"
	contentContainer.BackgroundTransparency = 1
	contentContainer.Size = string.lower(config.Layout or "top") == "side" and UDim2.new(1, -152, 1, -56) or UDim2.new(1, 0, 1, -80)
	contentContainer.Position = string.lower(config.Layout or "top") == "side" and UDim2.new(0, 152, 0, 50) or UDim2.new(0, 0, 0, 76)
	contentContainer.ClipsDescendants = true
	contentContainer.Parent = main

	local window = {
		Gui = gui,
		Main = main,
		TitleBar = titleBar,
		TabBar = tabBar,
		Sidebar = sidebar,
		ContentContainer = contentContainer,
		SettingsButton = settingsBtn,
		Tabs = tabs,
		Width = width,
		Height = height,
		Layout = string.lower(config.Layout or "top"),
		Style = config.Style or "Lunar",
		IconProvider = config.IconProvider or library.IconProvider,
		Config = config,
		Library = library,
		Cleanup = cleanup,
        Features = config.Features or {},
        Glass = glass,
        GlassColor = glass.Color,
        GlassColorCustom = config.GlassColor ~= nil,
        GlassGradient = config.GlassGradient,
        GlassTransparency = glass.Transparency,
        GlassTintTransparency = glass.TintTransparency,
        BackgroundImage = glass.Wallpaper.Image,
        WorldBlur = glass.Blur,
	}
    -- Per-feature switches are independent. A missing entry means enabled.
    function window:IsFeatureEnabled(name)
        local value = self.Features[name]
        if value == nil then value = self.Config[name] end
        return value ~= false
    end
    function window:SetFeature(name, enabled)
        if type(name) ~= "string" or type(enabled) ~= "boolean" then
            warn("[LunarUI] SetFeature(name, boolean) expected")
            return false
        end
        self.Features[name] = enabled
        if name == "Resizable" and resizeHandle then resizeHandle.Visible = enabled end
        if name == "Settings" and settingsBtn then settingsBtn.Visible = enabled end
        if name == "Profile" and self.ProfilePage then self.ProfilePage.Visible = enabled end
        if name == "Shine" and headerSheen then headerSheen.Visible = enabled end
        if name == "Gradients" and headerGradient then headerGradient.Enabled = enabled end
        if name == "CommandBar" and commandFrame then commandFrame.Visible = false end
        if name == "Colorpicker" or name == "Notifications" or name == "Animations" or name == "CloseEffect" then
            -- Applied by the corresponding component/window call on next use.
        end
        return true
    end

    function window:SetGlassColor(color)
        if typeof(color) ~= "Color3" then warn("[LunarUI][Glass] SetGlassColor expects Color3"); return false end
        self.GlassColor = color
        self.GlassColorCustom = true
        glass.Color = color
        glass.Tint.BackgroundColor3 = color
        glass.OrbA.BackgroundColor3 = color
        glass.OrbB.BackgroundColor3 = Theme.Accent2 or color
        local colors = self.GlassGradient or {color, Theme.Accent2 or color, Theme.Background}
        local seq = BuildColorSequence(colors, color, Theme.Accent2 or color, Theme.Background)
        glass.TintGradient.Color = seq
        glass.OrbAGradient.Color = seq
        glass.OrbBGradient.Color = BuildColorSequence({Theme.Accent2 or color, color, Theme.Background}, color, Theme.Accent2 or color, Theme.Background)
        headerGlassGradient.Color = seq
        sidebarGradient.Color = seq
        mainStroke.Color = color
        sidebarStroke.Color = color
        glass.EdgeGradient.Color = seq
        if self.SettingsPanel and self.SettingsGlassHex then self.SettingsGlassHex.Text = "#" .. color:ToHex() end
        return true
    end

    function window:SetGlassTransparency(value)
        value = tonumber(value)
        if not value then warn("[LunarUI][Glass] Transparency expects a number from 0 to 1"); return false end
        value = math.clamp(value, 0.08, 0.88)
        self.GlassTransparency = value
        glass.Transparency = value
        glass.Base.BackgroundTransparency = value
        glass.TintTransparency = math.clamp(value + 0.27, 0.12, 0.94)
        glass.Tint.BackgroundTransparency = glass.TintTransparency
        return true
    end

    function window:SetBackgroundImage(image, options)
        options = options or {}
        local normalized = NormalizeImageId(image)
        glass.Wallpaper.Image = normalized
        glass.Wallpaper.Visible = normalized ~= ""
        self.BackgroundImage = normalized
        if options.Transparency ~= nil then
            glass.Wallpaper.ImageTransparency = math.clamp(tonumber(options.Transparency) or 0.16, 0, 1)
        end
        if options.Tint ~= nil and typeof(options.Tint) == "Color3" then
            glass.Wallpaper.ImageColor3 = options.Tint
        end
        if options.ScaleType then
            local ok, scale = pcall(function() return Enum.ScaleType[options.ScaleType] end)
            if ok and scale then glass.Wallpaper.ScaleType = scale end
        end
        glass.OrbA.BackgroundTransparency = normalized ~= "" and 0.86 or 0.68
        glass.OrbB.BackgroundTransparency = normalized ~= "" and 0.90 or 0.77
        return true
    end

    function window:SetImageTint(color)
        if typeof(color) ~= "Color3" then warn("[LunarUI][Glass] SetImageTint expects Color3"); return false end
        glass.Wallpaper.ImageColor3 = color
        return true
    end

    function window:SetBackgroundGradient(colors, rotation)
        if type(colors) ~= "table" and typeof(colors) ~= "ColorSequence" then
            warn("[LunarUI][Glass] SetBackgroundGradient expects a Color3 array or ColorSequence"); return false
        end
        self.GlassGradient = colors
        glass.GradientColors = colors
        if rotation ~= nil then
            glass.GradientRotation = tonumber(rotation) or glass.GradientRotation
        end
        local seq = BuildColorSequence(colors, self.GlassColor, Theme.Accent2 or self.GlassColor, Theme.Background)
        glass.TintGradient.Color = seq
        glass.OrbAGradient.Color = seq
        glass.OrbBGradient.Color = BuildColorSequence({Theme.Accent2 or self.GlassColor, self.GlassColor, Theme.Background}, self.GlassColor, Theme.Accent2 or self.GlassColor, Theme.Background)
        headerGlassGradient.Color = seq
        sidebarGradient.Color = seq
        glass.EdgeGradient.Color = seq
        for _, g in ipairs({glass.TintGradient, glass.OrbAGradient, glass.OrbBGradient, headerGlassGradient, sidebarGradient, glass.EdgeGradient}) do
            g.Rotation = glass.GradientRotation
        end
        return true
    end

    function window:SetWorldBlur(enabled, size)
        if not glass.Blur and enabled then
            local b = Instance.new("BlurEffect")
            b.Name = "LunarUI_AcrylicBlur"
            b.Size = math.clamp(tonumber(size) or tonumber(config.BlurSize) or 8, 0, 24)
            b.Enabled = true
            b.Parent = Lighting
            cleanup:AddInstance(b)
            glass.Blur = b
            self.WorldBlur = b
        elseif glass.Blur then
            glass.Blur.Enabled = enabled == true
            if size ~= nil then glass.Blur.Size = math.clamp(tonumber(size) or glass.Blur.Size, 0, 24) end
        end
        return true
    end

    function window:SetGlassSettings(settings)
        settings = settings or {}
        if settings.Color then self:SetGlassColor(settings.Color) end
        if settings.Transparency ~= nil then self:SetGlassTransparency(settings.Transparency) end
        if settings.Image ~= nil then self:SetBackgroundImage(settings.Image, settings) end
        if settings.Gradient then self:SetBackgroundGradient(settings.Gradient, settings.Rotation) end
        if settings.Blur ~= nil then self:SetWorldBlur(settings.Blur, settings.BlurSize) end
        return true
    end

	-- Drag
	local drag = MakeDraggable(titleBar, main)
	cleanup:AddCallback(function() drag:Destroy() end)

	resizeHandle = Instance.new("TextButton")
	resizeHandle.Name = "ResizeHandle";resizeHandle.BackgroundColor3=Theme.Accent;resizeHandle.BackgroundTransparency=.15
	resizeHandle.BorderSizePixel=0;resizeHandle.Text="◢";resizeHandle.Font=Enum.Font.GothamBold;resizeHandle.TextSize=10;resizeHandle.TextColor3=Theme.Text
	resizeHandle.Size=UDim2.fromOffset(17,17);resizeHandle.AnchorPoint=Vector2.new(1,1);resizeHandle.Position=UDim2.new(1,0,1,0)
	resizeHandle.Visible=config.Resizable~=false and not (config.Features and config.Features.Resizable==false);resizeHandle.Parent=main
	local rhc=Instance.new("UICorner");rhc.CornerRadius=UDim.new(0,4);rhc.Parent=resizeHandle
	local resizing=false;local resizeStart;local sizeStart
	cleanup:AddConnection(resizeHandle.InputBegan:Connect(function(input)
		if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
			resizing=true;resizeStart=input.Position;sizeStart=main.AbsoluteSize
		end
	end))
	cleanup:AddConnection(UserInputService.InputChanged:Connect(function(input)
		if not resizing or (input.UserInputType~=Enum.UserInputType.MouseMovement and input.UserInputType~=Enum.UserInputType.Touch) then return end
		local delta=input.Position-resizeStart
		local vp=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1024,768)
		local nw=math.clamp(sizeStart.X+delta.X,tonumber(config.MinWidth)or 320,math.min(tonumber(config.MaxWidth)or 1200,vp.X-12))
		local nh=math.clamp(sizeStart.Y+delta.Y,tonumber(config.MinHeight)or 260,math.min(tonumber(config.MaxHeight)or 900,vp.Y-12))
		window.Width=nw;window.Height=nh;main.Size=UDim2.fromOffset(nw,nh)
	end))
	cleanup:AddConnection(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then resizing=false end
	end))

	cleanup:AddConnection(closeBtn.MouseButton1Click:Connect(function()
		window:Close()
	end))

	cleanup:AddConnection(minBtn.MouseButton1Click:Connect(function()
		window:ToggleMinimize()
	end))

	-- Custom entrance: slight lift + scale settle + glass reveal + specular sweep.
	-- Each parallel tween is isolated, so one invalid property cannot block the rest.
    local targetWindowPosition = UDim2.new(0.5, -width / 2, 0.5, -height / 2)
    if config.Animations == false or (config.Features and config.Features.Animations == false) then
        main.Size = UDim2.fromOffset(width, height)
        main.Position = targetWindowPosition
        motionScale.Scale = 1
        glass.Base.BackgroundTransparency = glass.Transparency
    else
        main.Size = UDim2.fromOffset(width, height)
        main.Position = UDim2.new(0.5, -width / 2, 0.5, -height / 2 + 22)
        motionScale.Scale = 0.91
        glass.Base.BackgroundTransparency = 1
        glass.Tint.BackgroundTransparency = 1
        TweenEngine.Parallel({
            {Object=main, Goals={Position=targetWindowPosition}, Options={Duration=0.58, Easing="BackOut"}},
            {Object=motionScale, Goals={Scale=1}, Options={Duration=0.52, Easing="ElasticOut"}},
            {Object=glass.Base, Goals={BackgroundTransparency=glass.Transparency}, Options={Duration=0.42, Easing="QuartOut"}},
            {Object=glass.Tint, Goals={BackgroundTransparency=glass.TintTransparency}, Options={Duration=0.46, Delay=0.04, Easing="QuadOut"}},
        })
        if glass.Shine and glass.Shine.Parent then
            local originalShinePosition = glass.Shine.Position
            glass.Shine.Position = UDim2.new(-0.35, 0, originalShinePosition.Y.Scale, originalShinePosition.Y.Offset)
            TweenEngine.Play(glass.Shine, {Position=UDim2.new(1.15, 0, originalShinePosition.Y.Scale, originalShinePosition.Y.Offset)}, {Duration=1.1, Delay=0.14, Easing="SineInOut"})
        end
    end

	cleanup:AddInstance(gui)

	local function refreshWindowTheme()
		if cleanup:IsDestroyed() then return end
		main.BackgroundColor3 = Theme.Background
        glass.Base.BackgroundColor3 = Theme.Background
        if not window.GlassColorCustom then
            window.GlassColor = Theme.Accent
            glass.Color = Theme.Accent
            glass.Tint.BackgroundColor3 = Theme.Accent
            glass.OrbA.BackgroundColor3 = Theme.Accent
        end
        glass.OrbB.BackgroundColor3 = Theme.Accent2 or glass.Color
        glass.Wallpaper.ImageColor3 = config.BackgroundImageTint or glass.Wallpaper.ImageColor3
        local glassSeq = BuildColorSequence(window.GlassGradient, window.GlassColor or Theme.Accent, Theme.Accent2 or Theme.Accent, Theme.Background)
        glass.TintGradient.Color = glassSeq
        glass.OrbAGradient.Color = glassSeq
        glass.OrbBGradient.Color = BuildColorSequence({Theme.Accent2 or Theme.Accent, window.GlassColor or Theme.Accent, Theme.Background}, Theme.Accent, Theme.Accent2 or Theme.Accent, Theme.Background)
        headerGlassGradient.Color = glassSeq
        sidebarGradient.Color = glassSeq
        glass.EdgeGradient.Color = glassSeq
        glass.Tint.BackgroundColor3 = window.GlassColor or Theme.Accent
        glass.OrbA.BackgroundColor3 = window.GlassColor or Theme.Accent
		mainStroke.Color = window.GlassColor or Theme.Border
        sidebarStroke.Color = window.GlassColor or Theme.Border
		sidebar.BackgroundColor3 = Theme.Secondary
		titleBar.BackgroundColor3 = Theme.Secondary
		titleFix.BackgroundColor3 = Theme.Secondary
		headerSheen.BackgroundColor3 = Theme.Accent
		headerGradient.Color = ColorSequence.new({ColorSequenceKeypoint.new(0,Theme.Accent),ColorSequenceKeypoint.new(.55,Theme.Accent),ColorSequenceKeypoint.new(1,Theme.Accent2 or Theme.Accent)})
		titleLabel.TextColor3 = Theme.Text
		titleLabel.Font = Theme.FontBold
		subtitle.TextColor3 = Theme.SecondaryText
		subtitle.Font = Theme.Font
		closeBtn.TextColor3 = Theme.SecondaryText
		minBtn.TextColor3 = Theme.SecondaryText
		settingsBtn.TextColor3 = Theme.SecondaryText
		for _, obj in ipairs(gui:GetDescendants()) do
			if obj:IsA("UICorner") then obj.CornerRadius = UDim.new(0, Theme.CornerRadius or 6)
			elseif obj:IsA("UIStroke") and obj.Name ~= "AccentStroke" then obj.Color = Theme.Border end
		end
		for _, tab in ipairs(tabs) do
			if tab.RefreshTheme then
				tab:RefreshTheme()
			end
		end
	end

	cleanup:AddCallback(OnThemeChange(refreshWindowTheme))

	function window:CreateTab(c)
		local tab = CreateTab(window, c)
		table.insert(tabs, tab)
		if not activeTab then
			window:SelectTab(tab)
		end
		return tab
	end

	function window:SelectTab(tab)
		if not tab or activeTab == tab or window._closing or window._destroyed then return end
		if activeTab then
			TweenEngine.CancelOnObject(activeTab.Content)
			activeTab:SetActive(false)
		end
		activeTab = tab
		tab:SetActive(true)
		if window:IsFeatureEnabled("Animations") and tab.Content and tab.Content.Parent then
			TweenEngine.CancelOnObject(tab.Content)
			tab.Content.Position = UDim2.fromOffset(13, 0)
			tab.Content.ScrollBarImageTransparency = 0.9
			TweenEngine.Parallel({
				{Object=tab.Content, Goals={Position=UDim2.fromOffset(0, 0)}, Options={Duration=0.25, Easing="QuintOut"}},
				{Object=tab.Content, Goals={ScrollBarImageTransparency=0.15}, Options={Duration=0.3, Easing="SineOut"}},
			})
		end
	end

	function window:RefreshTheme()
		refreshWindowTheme()
	end

	function window:Notify(config)
        if not self:IsFeatureEnabled("Notifications") then return nil end
		return library:Notify(config)
	end

	function window:ToggleMinimize()
		if window._closing or window._destroyed then return false end
		minimized = not minimized
		TweenEngine.CancelOnObject(main)
		TweenEngine.CancelOnObject(motionScale)
		if minimized then
			TweenEngine.Parallel({
				{Object=motionScale, Goals={Scale=0.985}, Options={Duration=0.18, Easing="QuadIn"}},
				{Object=main, Goals={Size=UDim2.fromOffset(window.Width, 42)}, Options={Duration=0.28, Easing="QuintInOut"}},
			})
			task.delay(0.08, function()
				if not minimized or window._destroyed or window._closing then return end
				contentContainer.Visible = false
				tabBar.Visible = false
				sidebar.Visible = false
			end)
		else
			contentContainer.Visible = true
			tabBar.Visible = window.Layout ~= "side"
			sidebar.Visible = window.Layout == "side"
			main.Size = UDim2.fromOffset(window.Width, 42)
			motionScale.Scale = 0.985
			TweenEngine.Parallel({
				{Object=main, Goals={Size=UDim2.fromOffset(window.Width, window.Height)}, Options={Duration=0.42, Easing="BackOut"}},
				{Object=motionScale, Goals={Scale=1}, Options={Duration=0.36, Easing="ElasticOut"}},
			})
		end
		return minimized
	end

	function window:SetLayout(layout)
		layout = string.lower(tostring(layout or "top"))
		if layout ~= "top" and layout ~= "side" then warn("[LunarUI] Layout must be 'top' or 'side'"); return false end
		window.Layout = layout
		local side = layout == "side"
		tabBar.Visible = not side and not minimized
		sidebar.Visible = side and not minimized
		contentContainer.Position = side and UDim2.new(0,152,0,50) or UDim2.new(0,0,0,76)
		contentContainer.Size = side and UDim2.new(1,-152,1,-56) or UDim2.new(1,0,1,-80)
		for _,t in ipairs(tabs) do
			if t.Button then
				t.Button.Parent = side and sidebar or tabBar
				t.Button.Size = side and UDim2.new(1,-8,0,34) or UDim2.new(0,98,0,28)
				if t.IconObject then t.IconObject:Destroy();t.IconObject=DrawVectorIcon(t.Button,t.Icon,Theme.SecondaryText,15,window.IconProvider);t.IconObject.Position=UDim2.fromOffset(7,(t.Button.Size.Y.Offset-15)/2) end
			end
		end
		return true
	end

	function window:ApplyStyle(style)
		style = tostring(style or "Lunar")
		window.Style = style
		local map = {Veyra="Veyra", Skeet="Skeet", Material="Material", Lunar="Lunar", Aurora="Aurora", Crimson="Crimson", Ocean="Ocean", AMOLED="AMOLED", Dark="Dark", Light="Light", Neon="Neon", PrismGlass="PrismGlass", Frost="Frost", MidnightGlass="MidnightGlass", FluentGlass="FluentGlass", AcrylicIce="AcrylicIce", OrionClean="OrionClean", LinoriaGraphite="LinoriaGraphite"}
		local preset = map[style]
		if not preset then warn("[LunarUI] Unknown style:", style); return false end
		return library:ApplyTheme(preset)
	end

	function window:OpenSettings()
        if not self:IsFeatureEnabled("Settings") then return false end
		if not window.SettingsPanel then
			local panel=Instance.new("Frame");panel.Name="LunarSettingsPanel";panel.BackgroundColor3=Theme.Secondary;panel.BackgroundTransparency=0.22;panel.BorderSizePixel=0
			panel.Position=UDim2.fromOffset(8,44);panel.Size=UDim2.new(1,-16,1,-52);panel.ZIndex=40;panel.Visible=false;panel.Parent=main
			local cr=Instance.new("UICorner");cr.CornerRadius=UDim.new(0,Theme.CornerRadius+2);cr.Parent=panel
			local st=Instance.new("UIStroke");st.Color=Theme.Border;st.Transparency=.18;st.Parent=panel
			local head=Instance.new("TextLabel");head.BackgroundTransparency=1;head.Font=Theme.FontBold;head.TextSize=15;head.TextColor3=Theme.Text
			head.TextXAlignment=Enum.TextXAlignment.Left;head.Text="LUNAR SETTINGS";head.Position=UDim2.fromOffset(16,12);head.Size=UDim2.new(1,-54,0,25);head.ZIndex=41;head.Parent=panel
			local close=Instance.new("TextButton");close.BackgroundColor3=Theme.Tertiary;close.BorderSizePixel=0;close.Text="×";close.Font=Enum.Font.GothamBold;close.TextSize=17;close.TextColor3=Theme.Text
			close.Size=UDim2.fromOffset(32,30);close.Position=UDim2.new(1,-43,0,8);close.ZIndex=41;close.Parent=panel
			local cc=Instance.new("UICorner");cc.CornerRadius=UDim.new(0,7);cc.Parent=close
			local scroll=Instance.new("ScrollingFrame");scroll.BackgroundTransparency=1;scroll.BorderSizePixel=0;scroll.Position=UDim2.fromOffset(12,48);scroll.Size=UDim2.new(1,-24,1,-58)
			scroll.ScrollBarThickness=3;scroll.CanvasSize=UDim2.new();scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y;scroll.ZIndex=41;scroll.Parent=panel
			local lay=Instance.new("UIListLayout");lay.Padding=UDim.new(0,7);lay.SortOrder=Enum.SortOrder.LayoutOrder;lay.Parent=scroll
			local pad=Instance.new("UIPadding");pad.PaddingBottom=UDim.new(0,10);pad.Parent=scroll
			local function settingsLabel(text)
				local l=Instance.new("TextLabel");l.BackgroundTransparency=1;l.Font=Theme.FontBold;l.TextSize=11;l.TextColor3=Theme.SecondaryText;l.TextXAlignment=Enum.TextXAlignment.Left
				l.Text=text;l.Size=UDim2.new(1,0,0,22);l.ZIndex=42;l.Parent=scroll;return l
			end
			local function settingsButton(text, callback)
				local b=Instance.new("TextButton");b.AutoButtonColor=false;b.BackgroundColor3=Theme.Tertiary;b.BackgroundTransparency=0.18;b.BorderSizePixel=0;b.Font=Theme.Font;b.TextSize=12;b.TextColor3=Theme.Text;b.Text=text
				b.Size=UDim2.new(1,0,0,34);b.ZIndex=42;b.Parent=scroll
				local bc=Instance.new("UICorner");bc.CornerRadius=UDim.new(0,Theme.CornerRadius);bc.Parent=b
				local bs=Instance.new("UIStroke");bs.Color=Theme.Border;bs.Transparency=.5;bs.Parent=b
				cleanup:AddConnection(b.MouseButton1Click:Connect(function()local ok,err=pcall(callback);if not ok then warn("[LunarUI][Settings]",err)end end));return b
			end
			settingsLabel("DESIGN GENERATION")
			for _,style in ipairs({"PrismGlass","Frost","MidnightGlass","FluentGlass","AcrylicIce","OrionClean","LinoriaGraphite","Lunar","Veyra","Skeet","Material","Aurora","Crimson","Ocean","AMOLED"}) do
				settingsButton("Apply "..style,function()window:ApplyStyle(style)end)
			end
			settingsLabel("NAVIGATION")
			settingsButton("Horizontal top tabs",function()window:SetLayout("top")end)
			settingsButton("Vertical side tabs",function()window:SetLayout("side")end)
			settingsLabel("ACCENT COLOR  •  HEX")
			local accentBox=Instance.new("TextBox");accentBox.ClearTextOnFocus=false;accentBox.BackgroundColor3=Theme.Background;accentBox.BorderSizePixel=0;accentBox.Font=Theme.FontMono
			accentBox.TextSize=12;accentBox.TextColor3=Theme.Text;accentBox.PlaceholderText="#977CFF";accentBox.Text="#"..Theme.Accent:ToHex();accentBox.Size=UDim2.new(1,0,0,34);accentBox.ZIndex=42;accentBox.Parent=scroll
			local ac=Instance.new("UICorner");ac.CornerRadius=UDim.new(0,6);ac.Parent=accentBox
			settingsButton("Apply custom accent",function()
				local raw=accentBox.Text:gsub("#","");if #raw~=6 then warn("[LunarUI] Enter a six-digit hex value");return end
				local ok,c=pcall(function()return Color3.fromHex(raw)end);if ok and c then local changed=CloneTheme(Theme);changed.Accent=c;changed.ToggleOn=c;changed.SliderFill=c;changed.Border=Theme.Border;library:SetTheme(changed);window:SetGlassColor(c)end
			end)
            settingsLabel("GLASS COLOR  •  HEX")
            local glassHex=Instance.new("TextBox");glassHex.Name="GlassHexInput";glassHex.ClearTextOnFocus=false;glassHex.BackgroundColor3=Theme.Background;glassHex.BorderSizePixel=0;glassHex.Font=Theme.FontMono
            glassHex.TextSize=12;glassHex.TextColor3=Theme.Text;glassHex.PlaceholderText="#977CFF";glassHex.Text="#"..(window.GlassColor or Theme.Accent):ToHex();glassHex.Size=UDim2.new(1,0,0,34);glassHex.ZIndex=42;glassHex.Parent=scroll
            local ghc=Instance.new("UICorner");ghc.CornerRadius=UDim.new(0,6);ghc.Parent=glassHex
            window.SettingsGlassHex=glassHex
            settingsButton("Apply glass tint",function()
                local raw=glassHex.Text:gsub("#","");if #raw~=6 then warn("[LunarUI] Enter a six-digit hex value");return end
                local ok,c=pcall(function()return Color3.fromHex(raw)end);if ok and c then window:SetGlassColor(c)else warn("[LunarUI] Invalid glass tint")end
            end)
            settingsLabel("WALLPAPER IMAGE  •  ROBLOX ASSET ID")
            local wallpaperBox=Instance.new("TextBox");wallpaperBox.Name="WallpaperAssetInput";wallpaperBox.ClearTextOnFocus=false;wallpaperBox.BackgroundColor3=Theme.Background;wallpaperBox.BorderSizePixel=0;wallpaperBox.Font=Theme.FontMono
            wallpaperBox.TextSize=11;wallpaperBox.TextColor3=Theme.Text;wallpaperBox.PlaceholderText="rbxassetid://123456789";wallpaperBox.Text=window.BackgroundImage or "";wallpaperBox.Size=UDim2.new(1,0,0,34);wallpaperBox.ZIndex=42;wallpaperBox.Parent=scroll
            local whc=Instance.new("UICorner");whc.CornerRadius=UDim.new(0,6);whc.Parent=wallpaperBox
            settingsButton("Apply wallpaper image",function()window:SetBackgroundImage(wallpaperBox.Text,{Transparency=config.BackgroundImageTransparency or 0.16,Tint=Color3.new(1,1,1)})end)
            settingsButton("Clear wallpaper • use aurora gradients",function()wallpaperBox.Text="";window:SetBackgroundImage("")end)
			settingsLabel("BEHAVIOR")
			settingsButton("Toggle close effect: "..tostring(window.Config.CloseEffect ~= false),function()window.Config.CloseEffect=not (window.Config.CloseEffect ~= false);window:Notify({Title="Close effect",Description=tostring(window.Config.CloseEffect),Duration=2,Type="Info"})end)
			settingsButton("Command bar: "..tostring(window.Config.CommandBar ~= false),function()window.Config.CommandBar=not (window.Config.CommandBar ~= false);if window.CommandFrame then window.CommandFrame.Visible=false end;window:Notify({Title="Command bar",Description=tostring(window.Config.CommandBar),Duration=2,Type="Info"})end)
			settingsButton("Reset window size",function()window:SetSize(width,height)end)
			window.SettingsPanel=panel
			local settingsRefresh = OnThemeChange(function()
				if not panel.Parent then return end
				panel.BackgroundColor3=Theme.Secondary;st.Color=Theme.Border;head.TextColor3=Theme.Text
				close.BackgroundColor3=Theme.Tertiary;close.TextColor3=Theme.Text
				for _,obj in ipairs(scroll:GetDescendants()) do
					if obj:IsA("TextButton") then obj.BackgroundColor3=Theme.Tertiary;obj.TextColor3=Theme.Text;obj.Font=Theme.Font
					elseif obj:IsA("TextLabel") then obj.TextColor3=Theme.SecondaryText
					elseif obj:IsA("TextBox") then obj.BackgroundColor3=Theme.Background;obj.TextColor3=Theme.Text end
				end
			end)
			cleanup:AddCallback(settingsRefresh)
			cleanup:AddConnection(close.MouseButton1Click:Connect(function()panel.Visible=false;contentContainer.Visible=true;tabBar.Visible=window.Layout~="side";sidebar.Visible=window.Layout=="side"end))
		end
		window.SettingsPanel.Visible=true;contentContainer.Visible=false;tabBar.Visible=false;sidebar.Visible=false
	end

	function window:SetSize(w,h)
		local vp=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1024,768)
		w=math.clamp(tonumber(w) or width,320,math.max(320,vp.X-12));h=math.clamp(tonumber(h) or height,260,math.max(260,vp.Y-12))
		window.Width=w;window.Height=h
		TweenEngine.Play(main,{Size=UDim2.fromOffset(w,h)},{Duration=.18,Easing="QuadOut"})
	end

	function window:Init()
		gui.Enabled=true;main.Visible=true
		if minimized then window:ToggleMinimize() end
		return window
	end

	function window:Close()
		if window._closing or window._destroyed then return end
		window._closing = true
		if window.Config.CloseSound and tostring(window.Config.CloseSound) ~= "" then
			pcall(function()
				local sound = Instance.new("Sound")
				local id = tostring(window.Config.CloseSound)
				if not id:find("rbxassetid://", 1, true) then id = "rbxassetid://" .. id end
				sound.SoundId = id
				sound.Volume = math.clamp(tonumber(window.Config.CloseSoundVolume) or 0.42, 0, 1)
				sound.Parent = SoundService
				sound:Play()
				task.delay(7, function() pcall(function() sound:Destroy() end) end)
			end)
		end

		if not window:IsFeatureEnabled("CloseEffect") or not window:IsFeatureEnabled("Animations") then
			TweenEngine.Parallel({
				{Object=motionScale, Goals={Scale=0.84}, Options={Duration=0.23, Easing="BackIn"}},
				{Object=main, Goals={Size=UDim2.fromOffset(0, 0)}, Options={Duration=0.28, Easing="QuintIn"}},
			}, function() window:Destroy() end)
			return
		end

		-- Signature close: impact flash, custom slash, then 40 independently tweened
		-- glass shards. All motion uses the Lunar scheduler and is cancel-safe.
		local absPos, absSize = main.AbsolutePosition, main.AbsoluteSize
		if absSize.X < 2 or absSize.Y < 2 then window:Destroy(); return end
		local centerX, centerY = absPos.X + absSize.X / 2, absPos.Y + absSize.Y / 2
		local flash = Instance.new("Frame")
		flash.Name = "LunarCloseImpact"
		flash.BackgroundColor3 = Color3.new(1, 1, 1)
		flash.BackgroundTransparency = 0.08
		flash.BorderSizePixel = 0
		flash.Position = UDim2.fromOffset(absPos.X, absPos.Y)
		flash.Size = UDim2.fromOffset(absSize.X, absSize.Y)
		flash.ZIndex = 200
		flash.Parent = gui

		local slash = Instance.new("Frame")
		slash.Name = "LunarCloseSlash"
		slash.BackgroundColor3 = Theme.Accent
		slash.BorderSizePixel = 0
		slash.AnchorPoint = Vector2.new(0.5, 0.5)
		slash.Position = UDim2.fromOffset(centerX, centerY)
		slash.Size = UDim2.fromOffset(absSize.X * 0.2, 4)
		slash.Rotation = -24
		slash.ZIndex = 201
		slash.Parent = gui

		TweenEngine.Parallel({
			{Object=flash, Goals={BackgroundTransparency=1}, Options={Duration=0.2, Easing="QuadOut"}},
			{Object=slash, Goals={Size=UDim2.fromOffset(absSize.X * 1.65, 1), BackgroundTransparency=1, Rotation=8}, Options={Duration=0.28, Easing="ExpoOut"}},
		})
		TweenEngine.Play(motionScale, {Scale=1.025}, {Duration=0.09, Easing="QuadOut"})
		task.delay(0.12, function()
			if window._destroyed or not main.Parent then return end
			main.Visible = false
			local rows, cols = 5, 8
			local shardSteps = {}
			for r = 1, rows do
				for c = 1, cols do
					local ok, part, x, y = pcall(function()
						local part = Instance.new("Frame")
						part.Name = "LunarGlassShard"
						part.BackgroundColor3 = (c + r) % 2 == 0 and (window.GlassColor or Theme.Background) or Theme.Accent
						part.BackgroundTransparency = 0.24
						part.BorderSizePixel = 0
						local px = absPos.X + (c - 1) * absSize.X / cols
						local py = absPos.Y + (r - 1) * absSize.Y / rows
						part.Position = UDim2.fromOffset(px, py)
						part.Size = UDim2.fromOffset(math.max(1, absSize.X / cols - 1), math.max(1, absSize.Y / rows - 1))
						part.Rotation = math.random(-3, 3)
						part.ZIndex = 190
						part.Parent = gui
						return part, px, py
					end)
					if ok and part then
						local rowBias = (r - (rows + 1) / 2)
						local colBias = (c - (cols + 1) / 2)
						local dx = colBias * math.random(22, 54) + math.random(-12, 12)
						local dy = rowBias * math.random(24, 58) + math.random(-16, 16)
						local delayTime = math.clamp((math.abs(rowBias) + math.abs(colBias)) * 0.035, 0, 0.42)
						table.insert(shardSteps, {
							Object=part,
							Goals={Position=UDim2.fromOffset(x + dx, y + dy), Rotation=math.random(-55, 55), BackgroundTransparency=1},
							Options={Duration=4.45, Delay=delayTime, Easing="QuintIn", OnComplete=function() if part.Parent then part:Destroy() end end},
						})
					end
				end
			end
			TweenEngine.Parallel(shardSteps, function() if not window._destroyed then window:Destroy() end end)
			task.delay(5.2, function() if not window._destroyed then window:Destroy() end end)
		end)
	end

	function window:Destroy()
		if window._destroyed then return end
		window._destroyed = true
		window._closing = true
		if main and main.Parent then TweenEngine.CancelOnObject(main) end
		if gui and gui.Parent then
			for _, node in ipairs(gui:GetDescendants()) do
				TweenEngine.CancelOnObject(node)
			end
		end
		for _, tab in ipairs(tabs) do
			tab:Destroy()
		end
		cleanup:Destroy()
		if window.CommandGui and window.CommandGui.Parent then pcall(function()window.CommandGui:Destroy()end)end
		if window._commandConnections then for _,c in ipairs(window._commandConnections)do pcall(function()c:Disconnect()end)end end
	end

	-- Dedicated floating command bar. It is distinct from the notification UI
	-- and can be invoked by the chat trigger, keybind, header, or API.
	window.Commands = {}
	window._commandConnections = {}
	window.RegisterCommand = function(self, name, description, callback, aliases)
		local item={Name=name,Description=description or "",Callback=callback,Aliases=aliases or {}}
		self.Commands[string.lower(name)]=item
		for _,alias in ipairs(aliases or {})do self.Commands[string.lower(alias)]=item end
		return item
	end
	window.ExecuteCommand = function(self, raw)
		local args, current, quoted = {}, {}, false
		local text = tostring(raw or "")
		local i = 1
		while i <= #text do
			local ch = text:sub(i, i)
			if ch == '"' then
				quoted = not quoted
			elseif ch == "\\" and i < #text and text:sub(i + 1, i + 1) == '"' then
				table.insert(current, '"')
				i = i + 1
			elseif ch:match("%s") and not quoted then
				if #current > 0 then
					table.insert(args, table.concat(current))
					current = {}
				end
			else
				table.insert(current, ch)
			end
			i = i + 1
		end
		if #current>0 then table.insert(args,table.concat(current)) end
		if #args==0 then return end
		local cmd=self.Commands[string.lower(args[1])]
		if not cmd then library:Notify({Title="Unknown command",Description=args[1],Type="Warning",Duration=2.8});return end
		table.remove(args,1)
		local ok,err=pcall(cmd.Callback,args,self)
		if not ok then warn("[LunarUI][Command]",err);library:Notify({Title="Command failed",Description=tostring(err),Type="Error",Duration=4})end
	end
	window.OpenCommandBar = function(self)
		if self.Config.CommandBar==false then return end
		self.CommandGui.Enabled=true;self.CommandBar.Visible=true;self.CommandInput:CaptureFocus()
	end
	window.CloseCommandBar = function(self)
		if self.CommandInput then self.CommandInput:ReleaseFocus()end
		if self.CommandBar then self.CommandBar.Visible=false end
	end
	local commandGui=Instance.new("ScreenGui");commandGui.Name="LunarUI_CommandBar";commandGui.ResetOnSpawn=false;commandGui.DisplayOrder=2147483000;commandGui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling;ProtectAndParent(commandGui)
	window.CommandGui=commandGui
	commandFrame=Instance.new("Frame");commandFrame.Name="CommandBar";commandFrame.BackgroundColor3=Theme.Secondary;commandFrame.BorderSizePixel=0
	commandFrame.AnchorPoint=Vector2.new(.5,.5);commandFrame.Position=UDim2.fromScale(.5,.5);commandFrame.Size=UDim2.new(0,math.min(520,width-24),0,62);commandFrame.Visible=false;commandFrame.Parent=commandGui
	local commandCorner=Instance.new("UICorner");commandCorner.CornerRadius=UDim.new(0,12);commandCorner.Parent=commandFrame
	local commandStroke=Instance.new("UIStroke");commandStroke.Color=Theme.Accent;commandStroke.Transparency=.35;commandStroke.Parent=commandFrame
	local commandPrompt=Instance.new("TextLabel");commandPrompt.BackgroundTransparency=1;commandPrompt.Font=Enum.Font.Code;commandPrompt.TextSize=18;commandPrompt.TextColor3=Theme.Accent;commandPrompt.Text=">_";commandPrompt.Size=UDim2.fromOffset(48,62);commandPrompt.Parent=commandFrame
	local commandInput=Instance.new("TextBox");commandInput.BackgroundTransparency=1;commandInput.ClearTextOnFocus=false;commandInput.Font=Theme.FontMono;commandInput.TextSize=14;commandInput.TextColor3=Theme.Text
	commandInput.PlaceholderText="type a command • help";commandInput.PlaceholderColor3=Theme.MutedText;commandInput.Text="";commandInput.TextXAlignment=Enum.TextXAlignment.Left
	commandInput.Position=UDim2.fromOffset(52,0);commandInput.Size=UDim2.new(1,-62,1,0);commandInput.Parent=commandFrame
	window.CommandBar=commandFrame;window.CommandInput=commandInput
	cleanup:AddConnection(commandInput.FocusLost:Connect(function(enter)
		if enter then window:ExecuteCommand(commandInput.Text);commandInput.Text="";window:CloseCommandBar()end
	end))
	window:RegisterCommand("help","List commands",function(_,win)
		local seen={};local rows={};for _,cmd in pairs(win.Commands)do if not seen[cmd.Name]then seen[cmd.Name]=true;table.insert(rows,cmd.Name.." — "..cmd.Description)end end;table.sort(rows)
		library:Notify({Title="Lunar commands",Description=table.concat(rows,"\n"),Duration=6,Type="Info"})
	end)
	window:RegisterCommand("theme","Change the UI theme",function(args,win)if args[1]then win:ApplyStyle(args[1])end end,{"style"})
	window:RegisterCommand("layout","Use top or side tabs",function(args,win)if args[1]then win:SetLayout(args[1])end end)
	window:RegisterCommand("hide","Minimize the window",function(_,win)win:ToggleMinimize()end)
	window:RegisterCommand("notify","Show a notification",function(args)library:Notify({Title="Command",Description=table.concat(args," "),Type="Info",Duration=3})end)
	if config.CommandBar~=false and not (config.Features and config.Features.CommandBar==false) then
		local trigger=config.ChatTrigger or "+67+"
		local function onChat(message)if message==trigger then window:OpenCommandBar()end end
		local okChat,chatConn=pcall(function()return LocalPlayer.Chatted:Connect(onChat)end);if okChat and chatConn then table.insert(window._commandConnections,chatConn)end
		local okText,msgConn=pcall(function()return TextChatService.MessageReceived:Connect(function(message)
			local text=message.Text
			local source=message.TextSource
			if text==trigger and source and source.UserId==LocalPlayer.UserId then window:OpenCommandBar()end
		end)end);if okText and msgConn then table.insert(window._commandConnections,msgConn)end
		local key=config.CommandKey or Enum.KeyCode.RightShift
		local okInput,keyConn=pcall(function()return UserInputService.InputBegan:Connect(function(input,processed)
			if not processed and input.KeyCode==key then if commandFrame.Visible then window:CloseCommandBar()else window:OpenCommandBar()end end
		end)end);if okInput and keyConn then table.insert(window._commandConnections,keyConn)end
	end
	cleanup:AddConnection(settingsBtn.MouseButton1Click:Connect(function()
		window:OpenSettings()
	end))
	return window
end

----------------------------------------------------------------
-- LIBRARY
----------------------------------------------------------------
local Library = {}
Library.__index = Library

local NotifManager = NotificationManager.new()
local Windows = {}
Library.Flags = {}
Library._ComponentFactories = {
    Button = CreateButton, Toggle = CreateToggle, Slider = CreateSlider, Label = CreateLabel,
    Dropdown = CreateDropdown, Textbox = CreateTextbox, Keybind = CreateKeybind, Divider = CreateDivider,
    Colorpicker = CreateColorpicker, MultiDropdown = CreateMultiDropdown, ProgressBar = CreateProgressBar,
    Paragraph = CreateParagraph, ButtonGroup = CreateButtonGroup,
}
Library.Icons = VectorIcons
Library.Version = "6.0.0-unified"
Library.Designs = { "PrismGlass", "Frost", "MidnightGlass", "FluentGlass", "AcrylicIce", "OrionClean", "LinoriaGraphite", "Lunar", "Veyra", "Skeet", "Material", "Aurora", "Crimson", "Ocean", "AMOLED", "Dark", "Light", "Neon" }
Library.Notification = NotifManager

function Library:CreateWindow(config)
	config = config or {}
	if config.ReplaceExisting ~= false then
		local existing = table.clone(Windows)
		for _, old in ipairs(existing) do pcall(function() old:Destroy() end) end
	end
	local initialPreset = config.Theme or config.Style
	if initialPreset and ThemePresets[initialPreset] then ApplyThemePreset(initialPreset) end
	local win = CreateWindow(Library, config)
	table.insert(Windows, win)
	-- ensure list entry is dropped when this window dies
	local oldDestroy = win.Destroy
	function win:Destroy()
		local idx = table.find(Windows, self)
		if idx then table.remove(Windows, idx) end
		if oldDestroy then oldDestroy(self) end
	end
	return win
end

function Library:Notify(config)
	return NotifManager:Notify(config)
end

Library.Toast = Library.Notify
Library.CreateNode = Library.CreateNode
function Library:ClearNotifications() return NotifManager:Clear() end
function Library:SetIconProvider(provider)
	self.IconProvider = provider
	return true
end
function Library:ApplyStyle(name)
	local styleMap={Lunar="Lunar",Veyra="Veyra",Skeet="Skeet",Material="Material",Aurora="Aurora",Crimson="Crimson",Ocean="Ocean",AMOLED="AMOLED",Dark="Dark",Light="Light",Neon="Neon",PrismGlass="PrismGlass",Frost="Frost",MidnightGlass="MidnightGlass",FluentGlass="FluentGlass",AcrylicIce="AcrylicIce",OrionClean="OrionClean",LinoriaGraphite="LinoriaGraphite"}
	local preset=styleMap[tostring(name)]
	if not preset then warn("[LunarUI] Unknown design style:",tostring(name));return false end
	return self:ApplyTheme(preset)
end
function Library:SetAccent(color)
	if typeof(color)~="Color3" then warn("[LunarUI] SetAccent expects Color3");return false end
	local t=CloneTheme(Theme);t.Accent=color;t.ToggleOn=color;t.SliderFill=color
	self:SetTheme(t);return true
end
function Library:Init(config) return self:CreateWindow(config or {}) end
Library.init=Library.Init
Library.create=Library.CreateWindow
Library.New=Library.CreateWindow

function Library:RegisterCommand(name, description, callback, aliases)
	local active=Windows[#Windows]
	if not active then warn("[LunarUI] CreateWindow before registering commands");return false end
	return active:RegisterCommand(name,description,callback,aliases)
end

function Library:ExportConfig()
	local values={}
	for flag,component in pairs(self.Flags) do
		local ok,v=pcall(function()return component.Get and component:Get()end)
		if ok and v~=nil then
			if typeof(v)=="Color3" then values[flag]={__type="Color3",r=v.R,g=v.G,b=v.B}
			elseif typeof(v)=="EnumItem" then values[flag]={__type="EnumItem",enum=tostring(v.EnumType),name=v.Name}
			elseif type(v)=="table" then values[flag]=v
			elseif type(v)=="string" or type(v)=="number" or type(v)=="boolean" then values[flag]=v end
		end
	end
	return HttpService:JSONEncode(values)
end
function Library:ImportConfig(jsonText)
	local ok,data=pcall(function()return HttpService:JSONDecode(jsonText)end)
	if not ok or type(data)~="table" then warn("[LunarUI] Invalid config JSON");return false end
	for flag,value in pairs(data)do
		local component=self.Flags[flag]
		if component and component.Set then
			if type(value)=="table" and value.__type=="Color3" then
				value=Color3.new(value.r or 0,value.g or 0,value.b or 0)
			elseif type(value)=="table" and value.__type=="EnumItem" then
				local enumName=tostring(value.enum or ""):match("^Enum%.(.+)$")
				local okEnum,enumObj=pcall(function()return enumName and Enum[enumName] and Enum[enumName][value.name]end)
				if okEnum then value=enumObj end
			end
			local good,err=pcall(function()component:Set(value)end);if not good then warn("[LunarUI][Config]",flag,err)end
		end
	end
	return true
end

-- Alurt-style alias
function Library:CreateNode(config)
	config = config or {}
	-- Map Alurt names → Veyra
	if config.Content and not config.Description then
		config.Description = config.Content
	end
	if config.Length ~= nil and config.Duration == nil then
		config.Duration = config.Length
	end
	return NotifManager:Notify(config)
end

function Library:SetTheme(t)
	SetTheme(t)
end

function Library:ApplyTheme(name)
	return ApplyThemePreset(name)
end

function Library:GetTheme()
	return GetTheme()
end

Library.ThemePresets = ThemePresets

-- Familiar aliases: both styles of API target the same implementation.
Library.MakeWindow = Library.CreateWindow
Library.MakeNotification = Library.Notify
Library.Create = Library.CreateWindow

function Library:CreateDemo(config)
    config = config or {}
    local win = self:CreateWindow({
        Title = config.Title or "LUNAR // CONTROL DECK",
        Subtitle = config.Subtitle or "PRISM GLASS • GREAT IDEAS, ORIGINAL IMPLEMENTATION",
        Width = config.Width, Height = config.Height,
        Theme = config.Theme or config.Style or "PrismGlass", Style = config.Style or config.Theme or "PrismGlass",
        Layout = config.Layout or "side", Resizable = true,
        CommandBar = config.CommandBar ~= false, ChatTrigger = config.ChatTrigger or "+67+",
        CloseEffect = config.CloseEffect ~= false,
        BackgroundImage = config.BackgroundImage,
        BackgroundImageTransparency = config.BackgroundImageTransparency,
        GlassColor = config.GlassColor,
        GlassTransparency = config.GlassTransparency or 0.34,
        GlassTintTransparency = config.GlassTintTransparency or 0.61,
        GlassGradient = config.GlassGradient,
        GradientRotation = config.GradientRotation or 18,
        WorldBlur = config.WorldBlur ~= false,
        BlurSize = config.BlurSize or 8,
    })
    local home = win:CreateTab({Name="Overview",Icon="home"})
    local profile = win:CreateTab({Name="Profile",Icon="user"})
    win.ProfilePage = profile.Content
    profile.Content.Visible = win:IsFeatureEnabled("Profile")
    local who = profile:CreateSection({Name="PROFILE",Description="A personal landing panel built into LunarUI."})
    who:CreateParagraph({Title="yo wsp, " .. (LocalPlayer and LocalPlayer.DisplayName or "creator"),Content="enjoy the lib • three design systems, a customizable component API, and client-side callbacks."})
    profile:CreateStatus({Name="Runtime",Value="Client"})
    profile:CreateStatus({Name="Layout",Value=(config.Layout or "side")})
    who:CreateButton({Name="Open settings",Description="Themes, navigation, accent and window options",Callback=function()win:OpenSettings()end})

    local hero = home:CreateSection({Name="LUNAR UI / PRISM",Description="Three glass generations — one component API."})
    hero:CreateParagraph({Title="Welcome back",Content="Prism Glass layers user wallpaper, tinted acrylic, gradient veils, two aurora blooms, specular light, and optional world blur. Customize the glass color and wallpaper from Appearance or the Settings panel."})
    hero:CreateButton({Name="Test notification",Description="Try the independent notification stack.",Callback=function()self:Notify({Title="LunarUI is alive",Description="Notification callback executed successfully.",Type="Success",Duration=4})end})
    hero:CreateButtonGroup({Name="GLASS GENERATIONS",Buttons={{Name="Prism",Callback=function()win:ApplyStyle("PrismGlass")end},{Name="Fluent Glass",Callback=function()win:ApplyStyle("FluentGlass")end},{Name="Acrylic Ice",Callback=function()win:ApplyStyle("AcrylicIce")end},{Name="Orion Clean",Callback=function()win:ApplyStyle("OrionClean")end},{Name="Linoria Graphite",Callback=function()win:ApplyStyle("LinoriaGraphite")end}}})

    local controls = win:CreateTab({Name="Components",Icon="sliders"})
    local core = controls:CreateSection({Name="Core controls",Description="Each control returns an object with Get / Set and supports callback isolation."})
    local demoEnabled=core:CreateToggle({Name="Example feature",Description="A real boolean control",Default=true,Flag="demo.enabled",Callback=function(v)print("Example feature:",v)end})
    core:CreateSlider({Name="Intensity",Min=0,Max=100,Default=64,Increment=1,ValueName="%",Flag="demo.intensity",Callback=function(v)print("Intensity:",v)end})
    local dependent=core:AddDependencyBox({Name="DEPENDENT CONTROL GROUP",Description="This group follows the feature toggle, including programmatic Set calls.",Dependencies={{Control=demoEnabled,Value=true}}})
    if dependent then dependent:CreateSlider({Name="Only visible while enabled",Min=1,Max=10,Default=5,Flag="demo.dependent",Callback=function(v)print("Dependent value:",v)end}) end
    core:CreateDropdown({Name="Single selection",Options={"Moon","Aurora","Eclipse","Nova"},Default="Aurora",Flag="demo.mode",Callback=function(v)print("Mode:",v)end})
    core:CreateMultiDropdown({Name="Multi selection",Options={"Buttons","Sliders","Colors","Notifications","Themes"},Default={"Buttons","Colors"},Flag="demo.parts",Callback=function(v)print("Selected components:",table.concat(v,", "))end})
    core:CreateColorpicker({Name="Accent color",Default=Theme.Accent,Flag="demo.accent",Callback=function(c)self:SetAccent(c)end})
    core:CreateKeybind({Name="Toggle window",Default=Enum.KeyCode.RightShift,Mode="Toggle",Callback=function()win:ToggleMinimize()end})
    core:CreateTextbox({Name="Text input",Placeholder="Enter a value and press Enter",Default="LunarUI",Callback=function(v)print("Input:",v)end})
    core:CreateProgressBar({Name="Progress",Default=72})
    core:CreateDivider()

    local appearance=win:CreateTab({Name="Appearance",Icon="palette"})
    local look=appearance:CreateSection({Name="Prism glass studio",Description="Tune the glass tint, gradient, optional wallpaper image, and world blur live."})
    look:CreateDropdown({Name="UI skin",Options={"PrismGlass","Frost","MidnightGlass","FluentGlass","AcrylicIce","OrionClean","LinoriaGraphite","Lunar","Veyra","Skeet","Material","Aurora","Crimson","Ocean","AMOLED","Light","Neon"},Default=config.Style or config.Theme or "PrismGlass",Callback=function(v)win:ApplyStyle(v)end})
    look:CreateDropdown({Name="Navigation",Options={"top","side"},Default=config.Layout or "side",Callback=function(v)win:SetLayout(v)end})
    look:CreateColorpicker({Name="Live glass tint",Default=win.GlassColor or Theme.Accent,Callback=function(c)win:SetGlassColor(c)end})
    look:CreateSlider({Name="Glass transparency",Min=8,Max=85,Default=math.floor((win.GlassTransparency or .34)*100),Increment=1,ValueName="%",Callback=function(v)win:SetGlassTransparency(v/100)end})
    look:CreateTextbox({Name="Wallpaper image asset",Placeholder="rbxassetid://123456789",Default=win.BackgroundImage or "",Callback=function(v)win:SetBackgroundImage(v)end})
    look:CreateToggle({Name="World blur behind glass",Description="Blurs the 3D scene behind this interface, not the image texture itself.",Default=win.WorldBlur~=nil,Callback=function(v)win:SetWorldBlur(v,config.BlurSize or 8)end})
    look:CreateParagraph({Title="Glass architecture",Content="The wallpaper sits behind a permanent translucent glass base, tinted gradient veil, specular sheen, edge highlight, and two soft aurora blooms. Set an uploaded image asset to personalize the backdrop.",})

    local command = win:CreateTab({Name="Commands",Icon="terminal"})
    local commands=command:CreateSection({Name="Command palette",Description="Type +67+ in chat or press RightShift; enter `help`, `theme Skeet`, `layout top`, or `notify hello there`."})
    commands:CreateButton({Name="Open command bar",Callback=function()win:OpenCommandBar()end})
    commands:CreateButton({Name="Show notification",Callback=function()self:Notify({Title="Custom toast",Description="Progress, types, optional icons/audio and manual close are supported.",Type="Info",Duration=5})end})
    commands:CreateButton({Name="Open component search",Callback=function()win:OpenSearch()end})
    commands:CreateButton({Name="Show confirmation dialog",Callback=function()win:Dialog({Title="Lunar dialog",Content="This is a modal dialog with isolated button callbacks.",Buttons={{Title="Cancel",Callback=function()self:Notify({Title="Cancelled",Description="Dialog callback ran.",Type="Info",Duration=2})end},{Title="Confirm",Primary=true,Callback=function()self:Notify({Title="Confirmed",Description="Dialog callback ran.",Type="Success",Duration=2})end}}})end})

    local advanced=win:CreateTab({Name="Advanced",Icon="layers"})
    local columns=advanced:CreateColumns(2,{Gap=12})
    local left=columns:Column("Left"):Section({Name="PROFILE / WINDOW TOOLS",Description="Convenience APIs inspired by common UI-library patterns."})
    left:CreateButton({Name="Create FPS watermark",Callback=function()win:CreateWatermark({Title="LUNAR // PRISM"});win:Notify({Title="Watermark active",Description="FPS HUD created.",Type="Success",Duration=2})end})
    left:CreateButton({Name="Save current profile",Callback=function()local ok=self:SaveProfile("demo");win:Notify({Title="Profile",Description=ok and "Saved to this client session." or "Profile save failed.",Type=ok and "Success" or "Error",Duration=3})end})
    left:CreateButton({Name="Open search palette",Callback=function()win:OpenSearch()end})
    local right=columns:Column("Right"):Section({Name="OPTIONS / THEME TOOLS",Description="Live flags and extra original palettes."})
    right:CreateDropdown({Name="Additional palette",Options={"FluentGlass","AcrylicIce","OrionClean","LinoriaGraphite","PrismGlass"},Default="FluentGlass",Callback=function(v)win:ApplyStyle(v)end})
    right:CreateButton({Name="Dialog example",Callback=function()win:Dialog({Title="Advanced dialog",Content="Dialogs are API objects; callbacks can close or keep the dialog open.",Buttons={{Title="Keep open",Close=false,Callback=function()win:Notify({Title="Still open",Description="The dialog remains visible.",Type="Info",Duration=2})end},{Title="Close",Primary=true}}})end})

    local box=advanced:CreateTabbox({Name="Nested component tabs"})
    local one=box:AddTab("General","sliders")
    local oneSection=one:CreateSection({Name="Nested groupbox"})
    oneSection:CreateToggle({Name="Nested setting",Default=true,Flag="demo.nested",Callback=function(v)print("Nested setting:",v)end})
    oneSection:CreateTextbox({Name="Nickname",Placeholder="Display label",Default="Lunar",Callback=function(v)print("Nickname:",v)end})
    local two=box:AddTab("About","info")
    local twoSection=two:CreateSection({Name="Feature map"})
    twoSection:CreateParagraph({Title="Borrow concepts, not source",Content="Option flags and refresh patterns, dependency-driven controls, tabboxes, modal dialogs, and acrylic surfaces are combined here as an original implementation."})
    return win
end

function Library:Destroy()
	-- copy because win:Destroy mutates Windows
	local snap = table.clone(Windows)
	table.clear(Windows)
	for _, win in ipairs(snap) do
		pcall(function() win:Destroy() end)
	end
	pcall(function() NotifManager:Destroy() end)
	TweenEngine.CancelAll()
	table.clear(ThemeListeners)
	if NotifManager then pcall(function()NotifManager:Destroy()end) end
	if SharedEnvironment.LunarUI == Library then SharedEnvironment.LunarUI=nil end
end

-- Expose animation, signal, theme and icon systems for customization.
Library.Animation = TweenEngine
Library.Signal = CreateSignal
Library.ThemePresets = ThemePresets
Library.VectorIcons = VectorIcons
SharedEnvironment.LunarUI = Library

-- Single-file compatibility aliases. In a normal client LocalScript, the demo
-- is enabled by default; set Library.AutoDemo=false before creating a custom window.
Library.CreateWindow = Library.CreateWindow
Library.createWindow = Library.CreateWindow
Library.CreateTab = function(window, config) return window:CreateTab(config) end
Library.MakeTab = function(window, config) return window:CreateTab(config) end
Library.Notify = Library.Notify
Library.Icons = VectorIcons
Library.Styles = Library.Designs
Library.GetActiveWindow = function() return Windows[#Windows] end


----------------------------------------------------------------
-- THE GREATS EDITION: reusable advanced APIs (LunarUI-original code)
-- Design concepts adapted at an API level: option flags and value setters,
-- nested dependency sections, group columns/tabboxes, dialogs, and status HUDs.
----------------------------------------------------------------

Library.Options = Library.Flags
Library.Profiles = Library.Profiles or {}
Library.ComponentChanged = CreateSignal()

local function _isControl(v)
    return type(v) == "table" and (type(v.Get) == "function" or type(v.Set) == "function" or v.Frame ~= nil)
end

local function _controlFrame(component)
    if type(component) ~= "table" then return nil end
    return component.Frame or component.Root or component.Container
end

local function _lunarConnect(signal, callback, cleanupOrList, scope)
    local connection
    local ok, err = pcall(function()
        connection = signal:Connect(function(...)
            local success, callbackError = pcall(callback, ...)
            if not success then warn("[LunarUI][" .. tostring(scope or "Callback") .. "]", callbackError) end
        end)
    end)
    if not ok then warn("[LunarUI][" .. tostring(scope or "Connection") .. "]", err); return nil end
    if connection and cleanupOrList then
        if type(cleanupOrList) == "table" and type(cleanupOrList.AddConnection) == "function" then
            cleanupOrList:AddConnection(connection)
        elseif type(cleanupOrList) == "table" then
            table.insert(cleanupOrList, connection)
        end
    end
    return connection
end

local function _attachControl(component, config, tab, library)
    if type(component) ~= "table" or component._LunarGreatsEnhanced then return component end
    component._LunarGreatsEnhanced = true
    config = type(config) == "table" and config or {}
    component.Name = config.Name or config.Title or component.Name or "Control"
    component.Flag = config.Flag or component.Flag
    component.Tab = tab
    component.Window = tab and tab.Window
    component.Library = library
    component._extraConnections = component._extraConnections or {}
    if component._LunarVisible == nil then component._LunarVisible = true end
    if component._LunarDependencyVisible == nil then component._LunarDependencyVisible = true end
    if component._LunarSearchVisible == nil then component._LunarSearchVisible = true end
    component._lunarDependentRefreshers = component._lunarDependentRefreshers or {}

    local function applyCombinedVisibility(control)
        local frame = _controlFrame(control)
        if frame and frame.Parent then
            frame.Visible = control._LunarVisible ~= false
                and control._LunarDependencyVisible ~= false
                and control._LunarSearchVisible ~= false
        end
    end

    local function currentValue()
        if type(component.Get) == "function" then
            local ok, value = pcall(function() return component:Get() end)
            if ok then return value end
        end
        return component.Value
    end
    component.Value = currentValue()

    if type(component.Get) == "function" and type(component.GetValue) ~= "function" then
        component.GetValue = function(self) return self:Get() end
    end
    if type(component.Set) == "function" and not component._LunarSetWrapped then
        local originalSet = component.Set
        component._LunarSetWrapped = true
        component.Set = function(self, value, suppress, ...)
            local result = originalSet(self, value, suppress, ...)
            local ok, current = pcall(function()
                if type(self.Get) == "function" then return self:Get() end
                return self.Value
            end)
            if ok and current ~= nil then
                self.Value = current
            elseif ok and value ~= nil then
                self.Value = value
            end
            for _, refresh in ipairs(self._lunarDependentRefreshers or {}) do
                local refreshOk, refreshErr = pcall(refresh)
                if not refreshOk then warn("[LunarUI][DependencyRefresh]", refreshErr) end
            end
            -- Controls with a Changed signal already publish through that signal's
            -- single listener above. Avoid duplicating those events here.
            if not suppress and not self.Changed and self.Library and self.Library.ComponentChanged then
                self.Library.ComponentChanged:Fire(self.Flag or self.Name, self.Value, self)
            end
            return result
        end
    end
    if type(component.Set) == "function" and type(component.SetValue) ~= "function" then
        component.SetValue = function(self, value, fireCallback)
            -- The public API uses fireCallback; the internal control API uses suppress.
            return self:Set(value, fireCallback == false)
        end
    end
    if type(component.SetEnabled) ~= "function" then
        component.SetEnabled = function(self, enabled)
            self._LunarEnabled = enabled ~= false
            local frame = _controlFrame(self)
            if frame and frame:IsA("GuiObject") then
                frame.Active = self._LunarEnabled
                pcall(function() frame.Interactable = self._LunarEnabled end)
                frame.BackgroundTransparency = self._LunarEnabled and (config.BackgroundTransparency or 0.12) or 0.55
            end
            return self._LunarEnabled
        end
    end
    component.SetVisible = function(self, visible)
        if not _controlFrame(self) then return false end
        self._LunarVisible = visible ~= false
        applyCombinedVisibility(self)
        return true
    end
    component.IsVisible = function(self)
        local frame = _controlFrame(self)
        return frame and frame.Visible or false
    end
    component.OnChanged = function(self, callback)
        if type(callback) ~= "function" then
            warn("[LunarUI][OnChanged] callback must be a function")
            return nil
        end
        if self.Changed and type(self.Changed.Connect) == "function" then
            return self.Changed:Connect(callback)
        end
        warn("[LunarUI][OnChanged] this control has no value-change signal")
        return nil
    end

    -- Keep the Orion-like Options[flag].Value view current without abandoning
    -- the richer Get/Set object API used by the rest of LunarUI.
    if component.Changed and type(component.Changed.Connect) == "function" then
        local c = component.Changed:Connect(function(value)
            component.Value = currentValue()
            if component.Value == nil then component.Value = value end
            if library and library.ComponentChanged then
                library.ComponentChanged:Fire(component.Flag or component.Name, component.Value, component)
            end
        end)
        table.insert(component._extraConnections, c)
    end

    if component.Flag and library then
        library.Flags[component.Flag] = component
        library.Options = library.Flags
    end

    -- Dependency logic accepts {control, expectedValue}, or
    -- {Control=control, Value=expectedValue}. Multiple requirements are ANDed.
    component.DependsOn = function(self, dependency, expected)
        self._dependencies = self._dependencies or {}
        table.insert(self._dependencies, {Control = dependency, Value = expected})
        local frame = _controlFrame(self)
        local function refresh()
            local show = true
            for _, rule in ipairs(self._dependencies) do
                local source = rule.Control
                if type(source) == "string" and library then source = library.Flags[source] end
                local val
                if type(source) == "table" then
                    if type(source.Get) == "function" then
                        local ok, result = pcall(function() return source:Get() end)
                        if ok then val = result end
                    else
                        val = source.Value
                    end
                end
                local expectedValue = rule.Value
                if expectedValue == nil then expectedValue = true end
                local match = false
                if type(expectedValue) == "table" then
                    if type(val) == "table" then
                        for _, x in ipairs(val) do if table.find(expectedValue, x) then match = true; break end end
                    else
                        match = table.find(expectedValue, val) ~= nil
                    end
                elseif type(val) == "table" then
                    match = table.find(val, expectedValue) ~= nil
                else
                    match = (val == expectedValue)
                end
                if not match then show = false; break end
            end
            self._LunarDependencyVisible = show
            applyCombinedVisibility(self)
        end
        local source = dependency
        if type(source) == "string" and library then source = library.Flags[source] end
        if type(source) == "table" then
            source._lunarDependentRefreshers = source._lunarDependentRefreshers or {}
            table.insert(source._lunarDependentRefreshers, refresh)
            if source.Changed and type(source.Changed.Connect) == "function" then
                local c = source.Changed:Connect(refresh)
                table.insert(self._extraConnections, c)
            end
        end
        refresh()
        return self
    end

    local oldDestroy = component.Destroy
    if type(oldDestroy) == "function" then
        component.Destroy = function(self, ...)
            for _, c in ipairs(self._extraConnections or {}) do pcall(function() c:Disconnect() end) end
            table.clear(self._extraConnections or {})
            if self.Library and self.Flag then
                if self.Library.Flags[self.Flag] == self then self.Library.Flags[self.Flag] = nil end
                self.Library.Options = self.Library.Flags
            end
            return oldDestroy(self, ...)
        end
    end

    return component
end

local function _wrapComponentMethod(target, methodName, tab, library)
    local original = target[methodName]
    if type(original) ~= "function" or target["_LunarWrapped_" .. methodName] then return end
    target["_LunarWrapped_" .. methodName] = true
    target[methodName] = function(self, config, ...)
        local result = original(self, config, ...)
        return _attachControl(result, config, tab or self, library)
    end
end

local _componentMethodNames = {
    "CreateButton", "CreateToggle", "CreateSlider", "CreateLabel", "CreateDropdown",
    "CreateTextbox", "CreateKeybind", "CreateDivider", "CreateColorpicker", "CreateColorPicker",
    "CreateMultiDropdown", "CreateProgressBar", "CreateParagraph", "CreateButtonGroup",
    "CreateStatus", "CreateInput", "CreateTextBox", "CreateProgress", "CreateSwitch",
    "CreateRange", "CreateColor", "CreateMultiSelect", "CreateChoice", "CreateTextDisplay",
    "AddButton", "AddToggle", "AddSlider", "AddDropdown", "AddColorpicker", "AddColorPicker",
    "AddKeybind", "AddTextbox", "AddLabel", "AddParagraph"
}

local function _styleGroupbox(section)
    local frame = section and section.Container
    if not frame or frame:FindFirstChild("LunarGroupboxStyle") then return end
    frame.BackgroundColor3 = Theme.Secondary
    frame.BackgroundTransparency = 0.44
    frame.BorderSizePixel = 0
    local c = Instance.new("UICorner")
    c.Name = "LunarGroupboxStyle"
    c.CornerRadius = UDim.new(0, Theme.CornerRadius + 3)
    c.Parent = frame
    local st = Instance.new("UIStroke")
    st.Name = "LunarGroupboxStroke"
    st.Color = Theme.Border
    st.Transparency = 0.55
    st.Thickness = 1
    st.Parent = frame
    local p = Instance.new("UIPadding")
    p.Name = "LunarGroupboxPadding"
    p.PaddingLeft = UDim.new(0, 10)
    p.PaddingRight = UDim.new(0, 10)
    p.PaddingTop = UDim.new(0, 8)
    p.PaddingBottom = UDim.new(0, 9)
    p.Parent = frame
    section._isGroupbox = true
end

local function _wrapSection(section, tab, library)
    if not section or section._LunarGreatsEnhanced then return section end
    section._LunarGreatsEnhanced = true
    section._BaseTab = section._BaseTab or tab
    if section._LunarDependencyVisible == nil then section._LunarDependencyVisible = true end
    if section._LunarSearchVisible == nil then section._LunarSearchVisible = true end
    for _, name in ipairs(_componentMethodNames) do
        _wrapComponentMethod(section, name, tab, library)
    end
    section.CreateGroupbox = function(self, config)
        local ownerTab = self.Tab
        if type(ownerTab) ~= "table" or type(ownerTab.CreateSection) ~= "function" then ownerTab = self._BaseTab end
        if type(ownerTab) ~= "table" or type(ownerTab.CreateSection) ~= "function" then
            warn("[LunarUI][Groupbox] No section host is available")
            return nil
        end
        local nested = ownerTab:CreateSection(config or {Name="Groupbox"})
        _styleGroupbox(nested)
        return nested
    end
    section.SetupDependencies = function(self, dependencies)
        self._dependencyRules = dependencies or {}
        local function valueOf(control)
            if type(control) == "string" then control = library.Flags[control] end
            if type(control) ~= "table" then return nil, control end
            if type(control.Get) == "function" then
                local ok, val = pcall(function() return control:Get() end)
                if ok then return val, control end
            end
            return control.Value, control
        end
        local function refresh()
            local visible = true
            for _, rule in ipairs(self._dependencyRules) do
                local control = rule.Control or rule[1]
                local expected = rule.Value
                if expected == nil then expected = rule[2] end
                if expected == nil then expected = true end
                local val, resolved = valueOf(control)
                local matches
                if type(expected) == "function" then
                    local ok, result = pcall(expected, val)
                    matches = ok and result == true
                elseif type(expected) == "table" then
                    matches = type(val) == "table" and false or table.find(expected, val) ~= nil
                    if type(val) == "table" then
                        for _, item in ipairs(val) do if table.find(expected, item) then matches = true; break end end
                    end
                elseif type(val) == "table" then
                    matches = table.find(val, expected) ~= nil
                else
                    matches = val == expected
                end
                if not matches then visible = false; break end
            end
            self._LunarDependencyVisible = visible
            if self.Container and self.Container.Parent then
                self.Container.Visible = self._LunarDependencyVisible ~= false and self._LunarSearchVisible ~= false
            end
        end
        for _, rule in ipairs(self._dependencyRules) do
            local control = rule.Control or rule[1]
            if type(control) == "string" then control = library.Flags[control] end
            if type(control) == "table" then
                control._lunarDependentRefreshers = control._lunarDependentRefreshers or {}
                table.insert(control._lunarDependentRefreshers, refresh)
                if control.Changed and type(control.Changed.Connect) == "function" then
                    local c = control.Changed:Connect(refresh)
                    self.Cleanup:AddConnection(c)
                end
            end
        end
        refresh()
        return self
    end
    section.AddDependencyBox = function(self, config)
        config = config or {}
        local ownerTab = self.Tab
        if type(ownerTab) ~= "table" or type(ownerTab.CreateSection) ~= "function" then ownerTab = self._BaseTab end
        if type(ownerTab) ~= "table" or type(ownerTab.CreateSection) ~= "function" then return nil end
        local box = ownerTab:CreateSection({Name=config.Name or "Dependent options", Description=config.Description})
        _styleGroupbox(box)
        box:SetupDependencies(config.Dependencies or config.DependsOn or {})
        return box
    end
    return section
end

local function _wrapTab(tab, window, library)
    if not tab or tab._LunarGreatsEnhanced then return tab end
    tab._LunarGreatsEnhanced = true
    tab._lunarOrder = 10
    local originalSection = tab.CreateSection
    tab.CreateSection = function(self, config)
        local section = originalSection(self, config)
        if section and section.Container then
            self._lunarOrder += 10
            section.Container.LayoutOrder = self._lunarOrder
        end
        return _wrapSection(section, tab, library)
    end
    for _, name in ipairs(_componentMethodNames) do
        _wrapComponentMethod(tab, name, tab, library)
    end

    tab.CreateGroupbox = function(self, config)
        local section = self:CreateSection(config or {Name="Groupbox"})
        _styleGroupbox(section)
        return section
    end
    tab.CreateDependencyBox = function(self, config)
        config = config or {}
        local section = self:CreateSection({Name=config.Name or "Dependent options", Description=config.Description})
        _styleGroupbox(section)
        section:SetupDependencies(config.Dependencies or config.DependsOn or {})
        return section
    end

    -- Linoria-inspired layout concept: columns that flow as a unit while each
    -- groupbox retains the normal LunarUI component API and theme refreshes.
    tab.CreateColumns = function(self, count, options)
        options = options or {}
        count = math.clamp(tonumber(count) or 2, 2, 3)
        local gap = tonumber(options.Gap) or 12
        local host = Instance.new("Frame")
        host.Name = "LunarColumns"
        host.BackgroundTransparency = 1
        host.BorderSizePixel = 0
        host.Size = UDim2.new(1, 0, 0, 80)
        host.LayoutOrder = (self._lunarOrder or 10) + 10
        self._lunarOrder = host.LayoutOrder
        host.Parent = self.Content
        local row = Instance.new("UIListLayout")
        row.FillDirection = Enum.FillDirection.Horizontal
        row.SortOrder = Enum.SortOrder.LayoutOrder
        row.Padding = UDim.new(0, gap)
        row.Parent = host
        local group = {Frame = host, Tab = self, Columns = {}, Destroyed = false}
        local function makeColumn(index)
            local frame = Instance.new("Frame")
            frame.Name = "LunarColumn_" .. index
            frame.BackgroundTransparency = 1
            frame.BorderSizePixel = 0
            frame.Size = UDim2.new(1/count, -gap*(count-1)/count, 0, 60)
            frame.AutomaticSize = Enum.AutomaticSize.Y
            frame.LayoutOrder = index
            frame.Parent = host
            local layout = Instance.new("UIListLayout")
            layout.SortOrder = Enum.SortOrder.LayoutOrder
            layout.Padding = UDim.new(0, 9)
            layout.Parent = frame
            local virtualTab = {Content=frame, Sections={}, Components=self.Components, Window=self.Window, _LunarVirtual=true, _BaseTab=self}
            local column = {Frame=frame, Index=index, Tab=self, _VirtualTab=virtualTab}
            virtualTab.CreateSection = function(_, config)
                local sec = CreateSection(virtualTab, config or {Name="Groupbox"})
                table.insert(self.Sections, sec)
                sec._BaseTab = self
                _wrapSection(sec, virtualTab, library)
                if options.Groupbox ~= false then _styleGroupbox(sec) end
                return sec
            end
            column.Section = function(_, name, description)
                return virtualTab:CreateSection(type(name) == "table" and name or {Name=name or "Groupbox", Description=description})
            end
            column.CreateSection = column.Section
            column.Groupbox = column.Section
            column.CreateGroupbox = column.Section
            table.insert(group.Columns, column)
            return column
        end
        for i=1,count do makeColumn(i) end
        local function resize()
            if not host.Parent then return end
            local maxHeight = 60
            for _, col in ipairs(group.Columns) do
                local l = col.Frame:FindFirstChildOfClass("UIListLayout")
                if l then maxHeight = math.max(maxHeight, l.AbsoluteContentSize.Y) end
            end
            host.Size = UDim2.new(1, 0, 0, maxHeight)
        end
        for _, col in ipairs(group.Columns) do
            local l=col.Frame:FindFirstChildOfClass("UIListLayout")
            if l then
                local c=l:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(resize)
                self.Window.Cleanup:AddConnection(c)
            end
        end
        group.Column = function(_, indexOrName)
            if type(indexOrName) == "number" then return group.Columns[indexOrName] end
            local n = string.lower(tostring(indexOrName or ""))
            if n == "left" then return group.Columns[1] end
            if n == "right" then return group.Columns[2] end
            return group.Columns[tonumber(indexOrName) or 1]
        end
        group.Destroy = function()
            if group.Destroyed then return end
            group.Destroyed=true
            for _,col in ipairs(group.Columns) do
                for _,sec in ipairs(col._VirtualTab.Sections) do pcall(function()sec:Destroy()end) end
            end
            pcall(function()host:Destroy()end)
        end
        self.Window.Cleanup:AddInstance(host)
        task.defer(resize)
        return group
    end

    -- Fluent-style sub-tab sets: each page still uses regular Lunar sections.
    tab.CreateTabbox = function(self, config)
        config = config or {}
        local host = Instance.new("Frame")
        host.Name = "LunarTabbox_" .. tostring(config.Name or "Tabs")
        host.BackgroundColor3 = Theme.Secondary
        host.BackgroundTransparency = 0.43
        host.BorderSizePixel = 0
        host.Size = UDim2.new(1,0,0,90)
        host.AutomaticSize = Enum.AutomaticSize.None
        host.LayoutOrder = (self._lunarOrder or 10) + 10
        self._lunarOrder = host.LayoutOrder
        host.Parent = self.Content
        local cr=Instance.new("UICorner");cr.CornerRadius=UDim.new(0,Theme.CornerRadius+2);cr.Parent=host
        local edge=Instance.new("UIStroke");edge.Color=Theme.Border;edge.Transparency=.58;edge.Parent=host
        local header=Instance.new("Frame");header.BackgroundTransparency=1;header.Position=UDim2.fromOffset(8,7);header.Size=UDim2.new(1,-16,0,30);header.Parent=host
        local hLayout=Instance.new("UIListLayout");hLayout.FillDirection=Enum.FillDirection.Horizontal;hLayout.Padding=UDim.new(0,6);hLayout.Parent=header
        local pages=Instance.new("Frame");pages.BackgroundTransparency=1;pages.Position=UDim2.fromOffset(8,44);pages.Size=UDim2.new(1,-16,0,40);pages.Parent=host
        local box={Frame=host,Tab=self,Pages={},Tabs={},Active=nil,Library=library}
        local function resize(page, layout)
            local h=math.max(24,layout.AbsoluteContentSize.Y+10)
            page.Size=UDim2.new(1,0,0,h)
            if box.Active and box.Active.Page==page then host.Size=UDim2.new(1,0,0,48+h) end
        end
        function box:Select(which)
            local target=type(which)=="number" and self.Tabs[which] or nil
            if not target then for _,item in ipairs(self.Tabs)do if item.Name==which then target=item;break end end end
            if not target then return false end
            self.Active=target
            for _,item in ipairs(self.Tabs)do
                item.Page.Visible=item==target
                item.Button.BackgroundColor3=item==target and Theme.Accent or Theme.Tertiary
                item.Button.TextColor3=item==target and Theme.Background or Theme.Text
            end
            host.Size=UDim2.new(1,0,0,48+target.Page.Size.Y.Offset)
            return true
        end
        function box:AddTab(name, icon)
            local item={Name=tostring(name),Icon=icon,Sections={}}
            item.Button=Instance.new("TextButton");item.Button.AutoButtonColor=false;item.Button.BackgroundColor3=Theme.Tertiary
            item.Button.BorderSizePixel=0;item.Button.Font=Theme.Font;item.Button.TextSize=11;item.Button.TextColor3=Theme.Text
            item.Button.Text=(icon and (tostring(icon) .. "  ") or "")..item.Name;item.Button.Size=UDim2.fromOffset(116,28);item.Button.Parent=header
            local bc=Instance.new("UICorner");bc.CornerRadius=UDim.new(0,6);bc.Parent=item.Button
            item.Page=Instance.new("Frame");item.Page.Name="TabboxPage_"..item.Name;item.Page.BackgroundTransparency=1
            item.Page.Position=UDim2.new(0,0,0,0);item.Page.Size=UDim2.new(1,0,0,0);item.Page.AutomaticSize=Enum.AutomaticSize.Y;item.Page.Visible=false;item.Page.Parent=pages
            local lay=Instance.new("UIListLayout");lay.SortOrder=Enum.SortOrder.LayoutOrder;lay.Padding=UDim.new(0,8);lay.Parent=item.Page
            local pad=Instance.new("UIPadding");pad.PaddingBottom=UDim.new(0,8);pad.PaddingTop=UDim.new(0,3);pad.Parent=item.Page
            local virtualTab={Content=item.Page,Sections={},Components=self.Tab.Components,Window=self.Tab.Window,_LunarVirtual=true,_BaseTab=self.Tab}
            virtualTab.CreateSection=function(_, sectionConfig)
                local sec=CreateSection(virtualTab,sectionConfig or {Name="Section"})
                table.insert(item.Sections,sec);table.insert(self.Tab.Sections,sec);sec._BaseTab=self.Tab
                _wrapSection(sec,virtualTab,library)
                return sec
            end
            item.CreateSection=function(_, sectionConfig) return virtualTab:CreateSection(sectionConfig) end
            item.Section=item.CreateSection
            _lunarConnect(item.Button.MouseButton1Click,function()box:Select(item.Name)end,self.Tab.Window.Cleanup,"NestedTabbox")
            local c=lay:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()resize(item.Page,lay)end)
            self.Tab.Window.Cleanup:AddConnection(c)
            table.insert(self.Tabs,item);table.insert(self.Pages,item.Page)
            if #self.Tabs==1 then box:Select(1) end
            return item
        end
        function box:Destroy()
            for _,item in ipairs(self.Tabs)do
                for _,sec in ipairs(item.Sections)do pcall(function()sec:Destroy()end)end
            end
            pcall(function()host:Destroy()end)
        end
        self.Window.Cleanup:AddInstance(host)
        return box
    end

    return tab
end

local function _wrapWindow(window, library)
    if not window or window._LunarGreatsEnhanced then return window end
    window._LunarGreatsEnhanced = true
    local baseCreateTab = window.CreateTab
    window.CreateTab = function(self, config)
        local tab = baseCreateTab(self, config)
        return _wrapTab(tab, self, library)
    end

    function window:Dialog(config)
        config = config or {}
        if self._activeDialog and self._activeDialog.Destroy then pcall(function()self._activeDialog:Destroy()end) end
        local host = self.Main or self.Gui
        if not host then return nil end
        local overlay = Instance.new("Frame")
        overlay.Name = "LunarDialogOverlay"
        overlay.BackgroundColor3 = Color3.new(0,0,0)
        overlay.BackgroundTransparency = 0.42
        overlay.BorderSizePixel = 0
        overlay.Size = UDim2.fromScale(1,1)
        overlay.ZIndex = 100
        overlay.Parent = host
        local card = Instance.new("Frame")
        card.Name = "LunarDialog"
        card.AnchorPoint = Vector2.new(.5,.5)
        card.Position = UDim2.fromScale(.5,.5)
        card.Size = UDim2.new(0.82,0,0,math.clamp(tonumber(config.Height) or 220,150,380))
        card.BackgroundColor3 = Theme.Secondary
        card.BackgroundTransparency = 0.08
        card.BorderSizePixel = 0
        card.ZIndex = 101
        card.Parent = overlay
        local cc=Instance.new("UICorner");cc.CornerRadius=UDim.new(0,Theme.CornerRadius+5);cc.Parent=card
        local cs=Instance.new("UIStroke");cs.Color=Theme.Accent;cs.Transparency=.38;cs.Thickness=1.2;cs.Parent=card
        local title=Instance.new("TextLabel");title.BackgroundTransparency=1;title.Font=Theme.FontBold;title.Text=config.Title or "Confirm action?"
        title.TextColor3=Theme.Text;title.TextSize=16;title.TextXAlignment=Enum.TextXAlignment.Left;title.Position=UDim2.fromOffset(18,14);title.Size=UDim2.new(1,-36,0,25);title.ZIndex=102;title.Parent=card
        local body=Instance.new("TextLabel");body.BackgroundTransparency=1;body.Font=Theme.Font;body.Text=config.Content or config.Description or "Choose an option below."
        body.TextColor3=Theme.SecondaryText;body.TextSize=12;body.TextWrapped=true;body.TextYAlignment=Enum.TextYAlignment.Top;body.TextXAlignment=Enum.TextXAlignment.Left
        body.Position=UDim2.fromOffset(18,48);body.Size=UDim2.new(1,-36,1,-105);body.ZIndex=102;body.Parent=card
        local row=Instance.new("Frame");row.BackgroundTransparency=1;row.AnchorPoint=Vector2.new(1,1);row.Position=UDim2.new(1,-16,1,-14);row.Size=UDim2.new(1,-32,0,34);row.ZIndex=102;row.Parent=card
        local ll=Instance.new("UIListLayout");ll.FillDirection=Enum.FillDirection.Horizontal;ll.HorizontalAlignment=Enum.HorizontalAlignment.Right;ll.SortOrder=Enum.SortOrder.LayoutOrder;ll.Padding=UDim.new(0,8);ll.Parent=row
        local dialog={Overlay=overlay,Card=card,Destroyed=false,_connections={}}
        function dialog:Destroy()
            if self.Destroyed then return end
            self.Destroyed=true
            for _,connection in ipairs(self._connections) do pcall(function()connection:Disconnect()end) end
            table.clear(self._connections)
            pcall(function()overlay:Destroy()end)
            if window._activeDialog==self then window._activeDialog=nil end
        end
        function dialog:Close() self:Destroy() end
        local buttons=config.Buttons or {{Title="OK",Primary=true}}
        for i,bconf in ipairs(buttons)do
            local b=Instance.new("TextButton");b.AutoButtonColor=false;b.BorderSizePixel=0;b.BackgroundColor3=bconf.Primary and Theme.Accent or Theme.Tertiary
            b.Font=Theme.Font;b.TextSize=12;b.TextColor3=bconf.Primary and Theme.Background or Theme.Text;b.Text=bconf.Title or ("Button "..i)
            b.Size=UDim2.fromOffset(math.max(84,math.min(150,#b.Text*8+22)),34);b.LayoutOrder=i;b.ZIndex=103;b.Parent=row
            local bc=Instance.new("UICorner");bc.CornerRadius=UDim.new(0,7);bc.Parent=b
            _lunarConnect(b.Activated,function()
                if type(bconf.Callback)=="function" then
                    local ok,err=pcall(bconf.Callback,dialog)
                    if not ok then warn("[LunarUI][DialogCallback]",err) end
                end
                if bconf.Close ~= false then dialog:Destroy() end
            end,dialog._connections,"Dialog")
        end
        self._activeDialog=dialog
        self.Cleanup:AddInstance(overlay)
        return dialog
    end

    function window:CreateWatermark(config)
        config=config or {}
        if self._watermark and self._watermark.Destroy then pcall(function()self._watermark:Destroy()end)end
        local gui=self.Gui
        if not gui then return nil end
        local frame=Instance.new("Frame");frame.Name="LunarStatusWatermark";frame.BackgroundColor3=Theme.Secondary;frame.BackgroundTransparency=.16
        frame.BorderSizePixel=0;frame.Size=UDim2.fromOffset(210,34);frame.Position=config.Position or UDim2.fromOffset(16,16);frame.ZIndex=150;frame.Parent=gui
        local cr=Instance.new("UICorner");cr.CornerRadius=UDim.new(0,9);cr.Parent=frame
        local st=Instance.new("UIStroke");st.Color=Theme.Accent;st.Transparency=.45;st.Parent=frame
        local accent=Instance.new("Frame");accent.BackgroundColor3=Theme.Accent;accent.BorderSizePixel=0;accent.Size=UDim2.new(0,3,1,0);accent.ZIndex=151;accent.Parent=frame
        local txt=Instance.new("TextLabel");txt.BackgroundTransparency=1;txt.Font=Theme.FontBold;txt.TextColor3=Theme.Text;txt.TextSize=11;txt.TextXAlignment=Enum.TextXAlignment.Left
        txt.Position=UDim2.fromOffset(13,0);txt.Size=UDim2.new(1,-20,1,0);txt.ZIndex=151;txt.Parent=frame
        local total,frames=0,0
        local item={Frame=frame,Destroyed=false}
        function item:SetVisible(v)frame.Visible=v~=false end
        function item:Destroy()if self.Destroyed then return end;self.Destroyed=true;if self.Connection then self.Connection:Disconnect()end;pcall(function()frame:Destroy()end)end
        item.Connection=RunService.RenderStepped:Connect(function(dt)
            if item.Destroyed or not frame.Parent then return end
            total+=dt;frames+=1
            if total>=.5 then
                local fps=math.floor(frames/total+.5)
                txt.Text=(config.Title or "LUNAR").."  •  "..tostring(fps).." FPS"
                total,frames=0,0
            end
        end)
        self.Cleanup:AddConnection(item.Connection);self.Cleanup:AddInstance(frame)
        self._watermark=item
        return item
    end

    function window:Search(query)
        query=string.lower(tostring(query or ""))
        local tab=self._activeTab
        -- Find active tab from its page visibility instead of relying on internals.
        for _,candidate in ipairs(self.Tabs or {})do
            if candidate.Content and candidate.Content.Visible then tab=candidate;break end
        end
        if not tab then return 0 end
        local shown=0
        for _,component in ipairs(tab.Components or {})do
            local frame=_controlFrame(component)
            if frame and frame.Parent then
                local hay=string.lower(tostring(component.Name or frame.Name or ""))
                local matches=query=="" or string.find(hay,query,1,true)~=nil
                component._LunarSearchVisible=matches
                frame.Visible=component._LunarVisible~=false and component._LunarDependencyVisible~=false and matches
                if frame.Visible then shown+=1 end
            end
        end
        for _,section in ipairs(tab.Sections or {})do
            if section.Container and section.Container.Parent then
                local any=false
                for _,component in ipairs(tab.Components or {})do
                    local f=_controlFrame(component)
                    if f and f.Parent and f:IsDescendantOf(section.Container) and f.Visible then any=true;break end
                end
                section._LunarSearchVisible=(query=="" or any or string.find(string.lower(tostring(section.Name or "")),query,1,true)~=nil)
                section.Container.Visible=section._LunarDependencyVisible~=false and section._LunarSearchVisible~=false
            end
        end
        return shown
    end

    function window:OpenSearch()
        if self._searchObject and self._searchObject.Close then
            pcall(function() self._searchObject:Close(false) end)
        elseif self._searchOverlay and self._searchOverlay.Parent then
            self._searchOverlay:Destroy()
        end
        local searchConnections = {}
        local overlay=Instance.new("Frame");overlay.Name="LunarSearchOverlay";overlay.BackgroundColor3=Color3.new(0,0,0);overlay.BackgroundTransparency=.35
        overlay.Size=UDim2.fromScale(1,1);overlay.ZIndex=170;overlay.Parent=self.Gui
        local box=Instance.new("Frame");box.AnchorPoint=Vector2.new(.5,0);box.Position=UDim2.new(.5,0,.16,0);box.Size=UDim2.new(.8,0,0,52)
        box.BackgroundColor3=Theme.Secondary;box.BackgroundTransparency=.05;box.BorderSizePixel=0;box.ZIndex=171;box.Parent=overlay
        local c=Instance.new("UICorner");c.CornerRadius=UDim.new(0,11);c.Parent=box;local st=Instance.new("UIStroke");st.Color=Theme.Accent;st.Transparency=.32;st.Parent=box
        local input=Instance.new("TextBox");input.ClearTextOnFocus=false;input.BackgroundTransparency=1;input.Font=Theme.Font;input.TextSize=14;input.TextColor3=Theme.Text
        input.PlaceholderText="Search controls in this tab…";input.PlaceholderColor3=Theme.SecondaryText;input.Size=UDim2.new(1,-28,1,0);input.Position=UDim2.fromOffset(14,0);input.ZIndex=172;input.Parent=box
        local obj={Overlay=overlay,Input=input,Closed=false}
        function obj:Close(reset)
            if self.Closed then return end
            self.Closed=true
            if reset then window:Search("") end
            for _,connection in ipairs(searchConnections) do pcall(function() connection:Disconnect() end) end
            table.clear(searchConnections)
            if self.Overlay and self.Overlay.Parent then self.Overlay:Destroy() end
            if window._searchObject==self then window._searchObject=nil;window._searchOverlay=nil end
        end
        _lunarConnect(input:GetPropertyChangedSignal("Text"),function()window:Search(input.Text)end,searchConnections,"Search")
        _lunarConnect(input.FocusLost,function(enter)if enter then obj:Close(false)elseif input.Text==""then obj:Close(true)end end,searchConnections,"Search")
        _lunarConnect(UserInputService.InputBegan,function(i,processed)if not processed and i.KeyCode==Enum.KeyCode.Escape and overlay.Parent then obj:Close(true)end end,searchConnections,"SearchEscape")
        self.Cleanup:AddInstance(overlay);self._searchOverlay=overlay;self._searchObject=obj;input:CaptureFocus();return obj
    end
    local searchShortcut = UserInputService.InputBegan:Connect(function(input, processed)
        if processed or window._closing then return end
        if input.KeyCode == Enum.KeyCode.F and (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)) then
            window:OpenSearch()
        end
    end)
    window.Cleanup:AddConnection(searchShortcut)

    local originalDestroy = window.Destroy
    window.Destroy = function(self, ...)
        if self._activeDialog and self._activeDialog.Destroy then pcall(function() self._activeDialog:Destroy() end) end
        if self._watermark and self._watermark.Destroy then pcall(function() self._watermark:Destroy() end) end
        if self._searchOverlay and self._searchOverlay.Parent then pcall(function() self._searchOverlay:Destroy() end) end
        return originalDestroy(self, ...)
    end

    return window
end

-- Preserve original window construction and apply the richer API consistently
-- to both user-created windows and the demonstration window.
local _LunarBaseCreateWindow = Library.CreateWindow
function Library:CreateWindow(config)
    local window = _LunarBaseCreateWindow(self, config)
    return _wrapWindow(window, self)
end

function Library:FindOption(flag)
    return self.Flags[flag]
end
function Library:GetOption(flag)
    local opt=self.Flags[flag]
    if opt and type(opt.Get)=="function" then
        local ok,val=pcall(function()return opt:Get()end)
        if ok then return val end
    end
    return nil
end
function Library:SetOption(flag, value, fireCallback)
    local opt=self.Flags[flag]
    if not opt or type(opt.Set)~="function" then warn("[LunarUI][Options] Unknown or read-only flag:",flag);return false end
    local ok,err=pcall(function()opt:Set(value,fireCallback==false)end)
    if not ok then warn("[LunarUI][Options]",flag,err);return false end
    return true
end

-- Profiles are JSON snapshots held in memory. This intentionally avoids pretending
-- the normal Roblox client can write arbitrary files; use DataStore/server code for
-- cross-session persistence in an experience you own.
function Library:SaveProfile(name)
    if type(name)~="string" or name=="" then return false end
    local ok,data=pcall(function()return self:ExportConfig()end)
    if not ok then warn("[LunarUI][ProfileSave]",data);return false end
    self.Profiles[name]=data
    return true
end
function Library:LoadProfile(name)
    local data=self.Profiles[name]
    if not data then return false end
    return self:ImportConfig(data)
end
function Library:DeleteProfile(name)
    if self.Profiles[name]==nil then return false end
    self.Profiles[name]=nil;return true
end
function Library:ListProfiles()
    local names={};for name in pairs(self.Profiles)do table.insert(names,name)end;table.sort(names);return names
end
function Library:Dialog(config)
    local window=Windows[#Windows]
    if not window then warn("[LunarUI][Dialog] Create a window first");return nil end
    return window:Dialog(config)
end


-- HybridUI compatibility layer:
-- Hybrid's compact theme vocabulary is translated into Lunar's richer theme model.
-- This keeps Hybrid-style examples usable without replacing Lunar's glass renderer.
local HybridThemePresets = {
    Serika = {Background=Color3.fromRGB(31,32,36), Secondary=Color3.fromRGB(43,44,49), Tertiary=Color3.fromRGB(39,40,45), Hover=Color3.fromRGB(59,61,67), Accent=Color3.fromRGB(235,190,26), Text=Color3.fromRGB(245,245,247), SecondaryText=Color3.fromRGB(181,183,189), Border=Color3.fromRGB(79,81,88)},
    Rust = {Background=Color3.fromRGB(30,31,35), Secondary=Color3.fromRGB(43,44,49), Tertiary=Color3.fromRGB(37,39,44), Hover=Color3.fromRGB(60,63,71), Accent=Color3.fromRGB(255,111,48), Text=Color3.fromRGB(245,245,247), SecondaryText=Color3.fromRGB(181,183,190), Border=Color3.fromRGB(77,80,88)},
    Aqua = {Background=Color3.fromRGB(25,27,30), Secondary=Color3.fromRGB(36,39,43), Tertiary=Color3.fromRGB(31,34,38), Hover=Color3.fromRGB(52,57,62), Accent=Color3.fromRGB(48,166,151), Text=Color3.fromRGB(242,246,246), SecondaryText=Color3.fromRGB(173,185,186), Border=Color3.fromRGB(71,82,83)},
    Legacy = {Background=Color3.fromRGB(29,28,34), Secondary=Color3.fromRGB(40,38,47), Tertiary=Color3.fromRGB(35,33,42), Hover=Color3.fromRGB(57,54,67), Accent=Color3.fromRGB(144,126,173), Text=Color3.fromRGB(246,244,249), SecondaryText=Color3.fromRGB(185,180,197), Border=Color3.fromRGB(79,73,91)},
}

for name, base in pairs(HybridThemePresets) do
    local p = {}
    for k,v in pairs(ThemePresets.Dark) do p[k]=v end
    for k,v in pairs(base) do p[k]=v end
    p.ToggleOn=p.Accent
    p.SliderFill=p.Accent
    p.NotificationBackground=p.Tertiary
    p.NotificationBorder=p.Border
    p.NotificationTitle=p.Text
    p.NotificationDescription=p.SecondaryText
    p.NotificationInfo=p.Accent
    p.NotificationSuccess=Color3.fromRGB(80,200,120)
    p.NotificationWarning=Color3.fromRGB(255,180,60)
    p.NotificationError=Color3.fromRGB(255,80,80)
    ThemePresets["Hybrid_"..name]=p
end

Library.HybridThemes = HybridThemePresets
function Library:ApplyHybridTheme(name)
    local preset = ThemePresets["Hybrid_"..tostring(name)] or ThemePresets[tostring(name)]
    if not preset then
        warn("[LunarUI][Hybrid] Unknown theme:", name)
        return false
    end
    return self:ApplyTheme(preset)
end

function Library:CreateHybridWindow(config)
    config = config or {}
    config.Layout = config.Layout or "side"
    config.Style = config.Style or "PrismGlass"
    config.Theme = config.Theme or "PrismGlass"
    return self:CreateWindow(config)
end

-- The active option table and original aliases remain compatible.
Library.Options = Library.Flags
Library.Extensions = {
    OptionFlags = true, DependencySections = true, GroupColumns = true,
    NestedTabboxes = true, Dialogs = true, Watermarks = true,
    SearchPalette = true, MemoryProfiles = true,
    Layouts = {"top", "side"}, Styles = Library.Designs,
}

----------------------------------------------------------------
-- UNIFIED OMNIVERSE LAYER
-- Original compatibility adapters for Fluent/Mercury/Orion/Linoria-style APIs.
-- This is one implementation with several API dialects, not a concatenation of
-- third-party source files. UI stays inside the current player's PlayerGui.
----------------------------------------------------------------

local function _unifiedTheme(name, baseName, colors, extras)
    local base = ThemePresets[baseName or "Dark"] or ThemePresets.Dark
    local result = CloneTheme(base)
    for key, value in pairs(colors or {}) do result[key] = value end
    for key, value in pairs(extras or {}) do result[key] = value end
    result.Accent2 = result.Accent2 or result.Accent
    result.ToggleOn = result.ToggleOn or result.Accent
    result.SliderFill = result.SliderFill or result.Accent
    result.NotificationBackground = result.NotificationBackground or result.Tertiary
    result.NotificationBorder = result.NotificationBorder or result.Border
    result.NotificationTitle = result.NotificationTitle or result.Text
    result.NotificationDescription = result.NotificationDescription or result.SecondaryText
    result.NotificationInfo = result.NotificationInfo or result.Accent
    result.NotificationSuccess = result.NotificationSuccess or Color3.fromRGB(73, 201, 133)
    result.NotificationWarning = result.NotificationWarning or Color3.fromRGB(244, 182, 71)
    result.NotificationError = result.NotificationError or Color3.fromRGB(242, 91, 105)
    ThemePresets[name] = result
    return result
end

-- Fluent-like clean hierarchy and blue accent; permanent glass remains Lunar's renderer.
_unifiedTheme("Fluent", "FluentGlass", {
    Background=Color3.fromRGB(20,22,27), Secondary=Color3.fromRGB(29,32,39), Tertiary=Color3.fromRGB(37,42,51),
    Hover=Color3.fromRGB(48,56,68), Text=Color3.fromRGB(245,247,250), SecondaryText=Color3.fromRGB(181,190,203),
    MutedText=Color3.fromRGB(125,137,153), Accent=Color3.fromRGB(96,165,250), Accent2=Color3.fromRGB(126,220,255),
    Border=Color3.fromRGB(75,92,116), CornerRadius=10, ElementHeight=38,
})
_unifiedTheme("FluentDark", "Fluent", {Accent=Color3.fromRGB(96,165,250), Accent2=Color3.fromRGB(94,234,212)})
_unifiedTheme("FluentLight", "Light", {
    Background=Color3.fromRGB(243,245,248), Secondary=Color3.fromRGB(250,251,253), Tertiary=Color3.fromRGB(233,237,243),
    Hover=Color3.fromRGB(222,230,240), Text=Color3.fromRGB(25,32,43), SecondaryText=Color3.fromRGB(78,91,109),
    MutedText=Color3.fromRGB(119,132,149), Accent=Color3.fromRGB(0,103,192), Accent2=Color3.fromRGB(0,153,188),
    Border=Color3.fromRGB(202,212,225), ToggleOn=Color3.fromRGB(0,103,192), SliderFill=Color3.fromRGB(0,103,192),
    CornerRadius=8, ElementHeight=36,
})
_unifiedTheme("FluentAcrylic", "Fluent", {Accent=Color3.fromRGB(112,190,255), Accent2=Color3.fromRGB(177,151,255), Border=Color3.fromRGB(102,145,183)})

-- Mercury-like compact charcoal surfaces, paired with the shared browser-style tab history.
_unifiedTheme("Mercury", "Dark", {
    Background=Color3.fromRGB(24,26,31), Secondary=Color3.fromRGB(32,35,41), Tertiary=Color3.fromRGB(41,45,53),
    Hover=Color3.fromRGB(56,62,73), Text=Color3.fromRGB(239,242,247), SecondaryText=Color3.fromRGB(166,175,190),
    MutedText=Color3.fromRGB(117,128,146), Accent=Color3.fromRGB(103,142,255), Accent2=Color3.fromRGB(118,214,224),
    Border=Color3.fromRGB(67,74,88), CornerRadius=7, ElementHeight=35,
})
_unifiedTheme("MercuryBlue", "Mercury", {Accent=Color3.fromRGB(77,153,255), Accent2=Color3.fromRGB(73,221,226)})
_unifiedTheme("MercuryPurple", "Mercury", {Accent=Color3.fromRGB(168,123,255), Accent2=Color3.fromRGB(110,183,255)})
_unifiedTheme("MercuryMint", "Mercury", {Accent=Color3.fromRGB(73,211,171), Accent2=Color3.fromRGB(83,190,231)})

-- Additional palettes from the broader Roblox UI design space, expressed as themes only.
_unifiedTheme("Orion", "OrionClean", {Accent=Color3.fromRGB(121,102,255), Accent2=Color3.fromRGB(82,184,255)})
_unifiedTheme("Linoria", "LinoriaGraphite", {Accent=Color3.fromRGB(105,213,173), Accent2=Color3.fromRGB(140,174,255)})
_unifiedTheme("Rayfield", "Fluent", {Accent=Color3.fromRGB(46,139,255), Accent2=Color3.fromRGB(100,220,255), CornerRadius=10})
_unifiedTheme("Catppuccin", "Dark", {
    Background=Color3.fromRGB(24,24,37), Secondary=Color3.fromRGB(30,30,46), Tertiary=Color3.fromRGB(49,50,68),
    Hover=Color3.fromRGB(69,71,90), Text=Color3.fromRGB(205,214,244), SecondaryText=Color3.fromRGB(166,173,200),
    MutedText=Color3.fromRGB(127,132,156), Accent=Color3.fromRGB(203,166,247), Accent2=Color3.fromRGB(137,220,235),
    Border=Color3.fromRGB(88,91,112),
})
_unifiedTheme("TokyoNight", "Dark", {
    Background=Color3.fromRGB(22,22,36), Secondary=Color3.fromRGB(30,32,48), Tertiary=Color3.fromRGB(39,42,62),
    Hover=Color3.fromRGB(52,56,83), Text=Color3.fromRGB(192,202,245), SecondaryText=Color3.fromRGB(152,161,196),
    MutedText=Color3.fromRGB(108,115,151), Accent=Color3.fromRGB(122,162,247), Accent2=Color3.fromRGB(125,207,255),
    Border=Color3.fromRGB(61,67,99),
})
_unifiedTheme("Material3", "Light", {
    Background=Color3.fromRGB(247,242,250), Secondary=Color3.fromRGB(255,251,255), Tertiary=Color3.fromRGB(236,229,240),
    Hover=Color3.fromRGB(226,217,232), Text=Color3.fromRGB(29,27,32), SecondaryText=Color3.fromRGB(73,69,78),
    MutedText=Color3.fromRGB(112,106,117), Accent=Color3.fromRGB(103,80,164), Accent2=Color3.fromRGB(0,105,120),
    Border=Color3.fromRGB(204,195,211), CornerRadius=12,
})
_unifiedTheme("AMOLED", "Dark", {
    Background=Color3.fromRGB(0,0,0), Secondary=Color3.fromRGB(7,7,9), Tertiary=Color3.fromRGB(15,15,18),
    Hover=Color3.fromRGB(28,28,33), Text=Color3.fromRGB(250,250,252), SecondaryText=Color3.fromRGB(164,164,174),
    MutedText=Color3.fromRGB(102,102,113), Accent=Color3.fromRGB(90,200,250), Accent2=Color3.fromRGB(90,240,205),
    Border=Color3.fromRGB(45,45,53), CornerRadius=7,
})

-- Friendly aliases for historic preset names; references are copied to avoid accidental shared edits.
ThemePresets.Serika = CloneTheme(ThemePresets.Hybrid_Serika or ThemePresets.Mercury)
ThemePresets.Rust = CloneTheme(ThemePresets.Hybrid_Rust or ThemePresets.Mercury)
ThemePresets.Aqua = CloneTheme(ThemePresets.Hybrid_Aqua or ThemePresets.Fluent)
ThemePresets.Legacy = CloneTheme(ThemePresets.Hybrid_Legacy or ThemePresets.Dark)

local _unifiedStyleAliases = {
    fluent="Fluent", fluentdark="FluentDark", fluentlight="FluentLight", acrylic="FluentAcrylic", mica="FluentAcrylic",
    mercury="Mercury", mercuryui="Mercury", mercuryblue="MercuryBlue", mercurypurple="MercuryPurple", mercurymint="MercuryMint",
    orion="Orion", linoria="Linoria", rayfield="Rayfield", material="Material3", material3="Material3",
    catppuccin="Catppuccin", tokyonight="TokyoNight", amoled="AMOLED", serika="Serika", rust="Rust", aqua="Aqua", legacy="Legacy",
    prism="PrismGlass", glass="PrismGlass", acrylicice="AcrylicIce", night="TokyoNight", default="Fluent",
}

local function _resolveUnifiedStyle(style)
    if type(style) == "table" then return style end
    local raw = tostring(style or "Fluent")
    local lower = string.lower(raw)
    local alias = _unifiedStyleAliases[lower]
    if alias and ThemePresets[alias] then return alias end
    for key in pairs(ThemePresets) do
        if string.lower(tostring(key)) == lower then return key end
    end
    return nil
end

local function _normalizeUnifiedWindowConfig(config)
    config = type(config) == "table" and table.clone(config) or {}
    config.Title = config.Title or config.Name or config.WindowName or "LunarUI // Unified"
    config.Subtitle = config.Subtitle or config.SubTitle or config.Description or config.Tagline
    if config.Width == nil and config.Size and typeof(config.Size) == "UDim2" then
        local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1024,768)
        config.Width = config.Size.X.Offset > 0 and config.Size.X.Offset or math.floor(vp.X * config.Size.X.Scale)
        config.Height = config.Size.Y.Offset > 0 and config.Size.Y.Offset or math.floor(vp.Y * config.Size.Y.Scale)
    end
    if config.Width == nil and type(config.Size) == "table" then config.Width = config.Size.Width or config.Size.X end
    if config.Height == nil and type(config.Size) == "table" then config.Height = config.Size.Height or config.Size.Y end
    if config.ToggleKey and config.Hotkey == nil then config.Hotkey = config.ToggleKey end
    if config.Navigation and config.Layout == nil then config.Layout = config.Navigation end
    if config.Layout == nil then config.Layout = "side" end
    local style = _resolveUnifiedStyle(config.Theme or config.Style or config.Design)
    if type(style) == "table" then
        SetTheme(style)
        config.Theme = nil
        config.Style = nil
    elseif style then
        config.Theme = style
        config.Style = config.Style or style
    end
    return config
end

local function _normalizeUnifiedTabConfig(config)
    if type(config) == "string" then return {Name=config} end
    config = type(config) == "table" and table.clone(config) or {}
    config.Name = config.Name or config.Title or config.Label or config.Text or "Tab"
    config.Icon = config.Icon or config.Symbol
    return config
end

local function _normalizeUnifiedControlConfig(config, methodName)
    if type(config) ~= "table" then
        config = {Name=tostring(config or methodName or "Control")}
    else
        config = table.clone(config)
    end
    config.Name = config.Name or config.Title or config.Label or config.Text or methodName or "Control"
    config.Description = config.Description or config.Subtitle or config.HelperText
    if config.Description == nil and config.Title and config.Text and config.Text ~= config.Title then
        config.Description = config.Text
    end
    if config.Default == nil then
        if config.StartingState ~= nil then config.Default = config.StartingState
        elseif config.DefaultValue ~= nil then config.Default = config.DefaultValue
        elseif config.Value ~= nil then config.Default = config.Value end
    end
    config.Options = config.Options or config.Values or config.Items or config.List
    config.Placeholder = config.Placeholder or config.PlaceholderText
    config.Min = config.Min or config.Minimum
    config.Max = config.Max or config.Maximum
    config.Increment = config.Increment or config.Step
    config.Flag = config.Flag or config.OptionFlag
    config.Callback = config.Callback or config.Function or config.OnChanged
    if config.Multi ~= nil and config.AllowMulti == nil then config.AllowMulti = config.Multi end
    return config
end

local function _attachUnifiedTargetAliases(target, targetType)
    if type(target) ~= "table" or target._UnifiedAPIAliases then return target end
    target._UnifiedAPIAliases = true
    local aliases = {
        Button="CreateButton", Toggle="CreateToggle", Switch="CreateToggle", Checkbox="CreateToggle",
        Slider="CreateSlider", Range="CreateRange", Dropdown="CreateDropdown", MultiDropdown="CreateMultiDropdown",
        Textbox="CreateTextbox", TextBox="CreateTextbox", Input="CreateInput", Keybind="CreateKeybind",
        ColorPicker="CreateColorpicker", Colorpicker="CreateColorpicker", Color="CreateColorpicker",
        Label="CreateLabel", Paragraph="CreateParagraph", TextDisplay="CreateTextDisplay", Text="CreateTextDisplay",
        Divider="CreateDivider", Progress="CreateProgress", ProgressBar="CreateProgressBar", Status="CreateStatus",
        ButtonGroup="CreateButtonGroup",
    }
    for alias, methodName in pairs(aliases) do
        target[alias] = function(self, config, ...)
            local method = self[methodName]
            if type(method) ~= "function" then
                warn("[LunarUI][Unified] Missing control method:", methodName)
                return nil
            end
            return method(self, _normalizeUnifiedControlConfig(config, alias), ...)
        end
    end
    for alias, methodName in pairs({
        AddButton="CreateButton", AddToggle="CreateToggle", AddSlider="CreateSlider", AddDropdown="CreateDropdown",
        AddColorpicker="CreateColorpicker", AddColorPicker="CreateColorpicker", AddKeybind="CreateKeybind",
        AddTextbox="CreateTextbox", AddLabel="CreateLabel", AddParagraph="CreateParagraph",
    }) do
        target[alias] = function(self, config, ...)
            local method = self[methodName]
            if type(method) ~= "function" then return nil end
            return method(self, _normalizeUnifiedControlConfig(config, alias), ...)
        end
    end
    if targetType == "tab" then
        local originalSection = target.CreateSection
        if type(originalSection) == "function" then
            target.CreateSection = function(self, config, ...)
                local section = originalSection(self, type(config)=="string" and {Name=config} or config, ...)
                if section then _attachUnifiedTargetAliases(section, "section") end
                return section
            end
        end
        target.Section = function(self, config, description)
            local normalized = type(config)=="string" and {Name=config, Description=description} or config
            return self:CreateSection(normalized or {Name="Section"})
        end
        target.Groupbox = function(self, config) return self:CreateGroupbox(type(config)=="string" and {Name=config} or config or {Name="Groupbox"}) end
        target.CreateGroupBox = target.Groupbox
        target.DependencyBox = function(self, config) return self:CreateDependencyBox(config or {}) end
    elseif targetType == "section" then
        target.Section = function(self, config)
            local normalized = type(config)=="string" and {Name=config} or config or {Name="Groupbox"}
            return self:CreateGroupbox(normalized)
        end
        target.Groupbox = target.Section
        target.CreateGroupBox = target.Section
    end
    return target
end

local _UnifiedPreviousCreateWindow = Library.CreateWindow
local function _attachUnifiedWindowAliases(window, library)
    if not window or window._UnifiedAPIAliases then return window end
    window._UnifiedAPIAliases = true

    local baseCreateTab = window.CreateTab
    if type(baseCreateTab) == "function" then
        window.CreateTab = function(self, config, ...)
            local tab = baseCreateTab(self, _normalizeUnifiedTabConfig(config), ...)
            if tab then _attachUnifiedTargetAliases(tab, "tab") end
            return tab
        end
    end
    window.Tab = function(self, config, ...)
        return self:CreateTab(_normalizeUnifiedTabConfig(config), ...)
    end
    window.AddTab = window.Tab

    -- Mercury's browser-like navigation is implemented as a bounded history of real tabs.
    local baseSelectTab = window.SelectTab
    local history, historyIndex, replaying = {}, 0, false
    if type(baseSelectTab) == "function" then
        window.SelectTab = function(self, tabOrName, ...)
            local tab = tabOrName
            if type(tabOrName) == "string" then
                tab = nil
                for _, candidate in ipairs(self.Tabs or {}) do
                    if candidate.Name == tabOrName or candidate.Title == tabOrName then tab = candidate; break end
                end
            end
            if type(tab) ~= "table" then return false end
            if not replaying and history[historyIndex] ~= tab then
                while #history > historyIndex do table.remove(history) end
                history[#history+1] = tab
                historyIndex = #history
                if #history > 60 then table.remove(history, 1); historyIndex = math.max(1, historyIndex-1) end
            end
            baseSelectTab(self, tab, ...)
            self.CurrentTab = tab
            return true
        end
    end
    function window:Back()
        if historyIndex <= 1 then return false end
        historyIndex -= 1
        replaying = true
        baseSelectTab(self, history[historyIndex])
        self.CurrentTab = history[historyIndex]
        replaying = false
        return true
    end
    function window:Forward()
        if historyIndex >= #history then return false end
        historyIndex += 1
        replaying = true
        baseSelectTab(self, history[historyIndex])
        self.CurrentTab = history[historyIndex]
        replaying = false
        return true
    end
    function window:GetNavigationHistory()
        local names = {}
        for _, item in ipairs(history) do names[#names+1] = item.Name or "Tab" end
        return names, historyIndex
    end

    function window:Show() if self.Gui then self.Gui.Enabled = true end return self end
    function window:Hide() if self.Gui then self.Gui.Enabled = false end return self end
    function window:Toggle() if self.Gui then self.Gui.Enabled = not self.Gui.Enabled end return self end
    window.ToggleVisibility = window.Toggle
    function window:ApplyStyle(style)
        local ok = library:ApplyStyle(style)
        if ok and self.RefreshTheme then pcall(function() self:RefreshTheme() end) end
        return ok
    end
    window.ApplyTheme = window.ApplyStyle
    function window:SetAccent(color)
        local ok = library:SetAccent(color)
        if ok and self.RefreshTheme then pcall(function() self:RefreshTheme() end) end
        return ok
    end
    function window:GetTheme() return library:GetTheme() end
    local configuredHotkey = window.Config and (window.Config.Hotkey or window.Config.ToggleKey)
    if typeof(configuredHotkey) == "EnumItem" and configuredHotkey.EnumType == Enum.KeyCode then
        local hotkeyConnection = UserInputService.InputBegan:Connect(function(input, processed)
            if processed or window._destroyed or window._UnifiedDestroyed then return end
            if input.KeyCode == configuredHotkey and window.Gui then
                window.Gui.Enabled = not window.Gui.Enabled
            end
        end)
        if window.Cleanup and window.Cleanup.AddConnection then
            window.Cleanup:AddConnection(hotkeyConnection)
        else
            window._UnifiedHotkeyConnection = hotkeyConnection
        end
    end

    local baseNotify = window.Notify
    function window:Notification(config)
        config = type(config)=="table" and table.clone(config) or {Title="Notification"}
        config.Description = config.Description or config.Text or config.Content
        config.Duration = config.Duration or config.Length
        config.Type = config.Type or config.Kind
        if type(baseNotify) == "function" then return baseNotify(self, config) end
        return library:Notify(config)
    end
    window.Toast = window.Notification
    window.CreateNotification = window.Notification
    function window:Prompt(config)
        config = type(config)=="table" and table.clone(config) or {Title="Prompt"}
        config.Content = config.Content or config.Text or config.Description
        local buttons = config.Buttons
        if type(buttons) == "table" and #buttons == 0 then
            local keys = {}
            for key in pairs(buttons) do keys[#keys+1] = key end
            table.sort(keys, function(a,b) return tostring(a) < tostring(b) end)
            local converted = {}
            for _, key in ipairs(keys) do
                local value = buttons[key]
                if type(value) == "function" then
                    converted[#converted+1] = {
                        Title=tostring(key), Close=false,
                        Callback=function(dialog)
                            local ok, result = pcall(value, dialog)
                            if not ok then warn("[LunarUI][PromptCallback]", result); return false end
                            if result ~= false and dialog and dialog.Destroy then dialog:Destroy() end
                            return result
                        end,
                    }
                elseif type(value) == "table" then
                    local entry = table.clone(value)
                    entry.Title = entry.Title or tostring(key)
                    converted[#converted+1] = entry
                end
            end
            config.Buttons = converted
        elseif type(buttons) == "table" then
            config.Buttons = table.clone(buttons)
        end
        return self:Dialog(config)
    end
    window.Confirm = function(self, config)
        config = type(config)=="table" and table.clone(config) or {Title="Confirm action?"}
        local onConfirm, onCancel = config.OnConfirm or config.ConfirmCallback, config.OnCancel or config.CancelCallback
        config.Buttons = {
            {Title=config.CancelText or "Cancel", Callback=function(dialog) if type(onCancel)=="function" then onCancel(dialog) end end},
            {Title=config.ConfirmText or "Confirm", Primary=true, Callback=function(dialog) if type(onConfirm)=="function" then onConfirm(dialog) end end},
        }
        return self:Dialog(config)
    end
    window.CreatePrompt = window.Prompt
    function window:Credit(config)
        config = type(config)=="table" and table.clone(config) or {Name=tostring(config or "Credit")}
        local title = config.Name or config.Title or "Credit"
        local body = config.Description or config.Role or ""
        if config.Discord then body = body .. "\nContact: " .. tostring(config.Discord) end
        if config.Link then body = body .. "\nLink: " .. tostring(config.Link) end
        return self:Dialog({Title=title, Content=body, Buttons={{Title="Close", Primary=true}}})
    end

    local baseDestroy = window.Destroy
    if type(baseDestroy) == "function" then
        window.Destroy = function(self, ...)
            self._UnifiedDestroyed = true
            table.clear(history)
            historyIndex = 0
            return baseDestroy(self, ...)
        end
    end
    return window
end

function Library:CreateWindow(config)
    local normalized = _normalizeUnifiedWindowConfig(config)
    local window = _UnifiedPreviousCreateWindow(self, normalized)
    return _attachUnifiedWindowAliases(window, self)
end

local function _unifiedCreateEntry(selfOrConfig, maybeConfig)
    local config = selfOrConfig == Library and maybeConfig or selfOrConfig
    return Library:CreateWindow(config)
end
Library.Create = _unifiedCreateEntry
Library.New = _unifiedCreateEntry
Library.new = _unifiedCreateEntry
Library.MakeWindow = Library.CreateWindow
Library.createWindow = Library.CreateWindow
Library.create = Library.Create
Library.Themes = ThemePresets
Library.Presets = ThemePresets
Library.Compatibility = {
    "Fluent-style acrylic and configuration aliases", "Mercury-style Tab/Button/Toggle/Prompt/Notification API",
    "Orion-style option flags", "Linoria-style groupboxes, columns and dependencies",
    "Hybrid-style palette aliases", "Prism glass and wallpaper renderer", "Mobile and desktop input",
}

-- Theme functions accept either a preset name or a complete custom theme table.
function Library:ApplyTheme(themeOrName)
    if type(themeOrName) == "table" then SetTheme(themeOrName); return true end
    local resolved = _resolveUnifiedStyle(themeOrName)
    if type(resolved) == "table" then SetTheme(resolved); return true end
    if not resolved then warn("[LunarUI][Unified] Unknown theme:", tostring(themeOrName)); return false end
    return ApplyThemePreset(resolved)
end
function Library:ApplyStyle(style)
    return self:ApplyTheme(style)
end
Library.UseStyle = Library.ApplyStyle
function Library:SetAccent(color)
    if typeof(color) ~= "Color3" then warn("[LunarUI] SetAccent expects Color3"); return false end
    local updated = CloneTheme(Theme)
    updated.Accent = color
    updated.Accent2 = color:Lerp(Color3.new(1,1,1), 0.24)
    updated.ToggleOn = color
    updated.SliderFill = color
    SetTheme(updated)
    return true
end

local _UnifiedPreviousNotify = Library.Notify
function Library:Notify(config)
    config = type(config)=="table" and table.clone(config) or {Title="Notification"}
    config.Description = config.Description or config.Text or config.Content
    config.Duration = config.Duration or config.Length
    config.Type = config.Type or config.Kind
    return _UnifiedPreviousNotify(self, config)
end
Library.Toast = Library.Notify
Library.Notification = Library.Notify
function Library:Prompt(config)
    local window = self:GetActiveWindow()
    if not window then warn("[LunarUI][Prompt] Create a window first"); return nil end
    return window:Prompt(config)
end
function Library:CreateFluentWindow(config)
    config = type(config)=="table" and table.clone(config) or {}
    config.Theme = config.Theme or "Fluent"
    config.Layout = config.Layout or "side"
    config.Glass = config.Glass ~= false
    return self:CreateWindow(config)
end
function Library:CreateMercuryWindow(config)
    config = type(config)=="table" and table.clone(config) or {}
    config.Theme = config.Theme or "Mercury"
    config.Layout = config.Layout or "top"
    return self:CreateWindow(config)
end
function Library:CreateUnifiedWindow(config)
    config = type(config)=="table" and table.clone(config) or {}
    config.Theme = config.Theme or "Fluent"
    config.Layout = config.Layout or "side"
    return self:CreateWindow(config)
end
Library.CreateFluent = Library.CreateFluentWindow
Library.CreateMercury = Library.CreateMercuryWindow
Library.CreateOmniWindow = Library.CreateUnifiedWindow

-- Style list is generated from actual available themes, while common aliases stay visible.
Library.Designs = {}
for name in pairs(ThemePresets) do Library.Designs[#Library.Designs+1] = name end
table.sort(Library.Designs)
Library.Styles = Library.Designs
Library.GetThemePresets = function() return ThemePresets end

-- The source can be placed in a LocalScript and display a live demo. In a
-- Studio project, disable AutoDemo before calling CreateWindow for your own UI.
Library.AutoDemo = true
if Library.AutoDemo then
    task.defer(function()
        if Library.AutoDemo and #Windows == 0 then
            local ok, demo = pcall(function()
                return Library:CreateDemo({Title="LUNAR // PRISM GLASS • GREATS EDITION", Theme="PrismGlass", Style="PrismGlass", Layout="side"})
            end)
            if ok then Library.DefaultWindow = demo else warn("[LunarUI][AutoDemo]", demo) end
        end
    end)
end

return Library
