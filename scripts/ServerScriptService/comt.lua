-- Comitter
local HttpService = game:GetService("HttpService")

-- Config
-- Config.lua — Constantes do Comitter
local Config = {}

Config.PROXY_URL = "http://127.0.0.1:3016"
Config.PLUGIN_NAME = "Comitter"
Config.PLUGIN_VERSION = "0.1.0"
Config.COMMIT_TYPES = {"feat", "fix", "chore", "refactor", "docs", "test", "style", "perf"}


-- RPC
-- RPC.lua — Cliente HTTP pro proxy/daemon
local HttpService = game:GetService("HttpService")
local PROXY = "http://127.0.0.1:3016"

local RPC = {}
RPC.connected = false

--- Envia ação pro daemon via proxy
function RPC:send(action, params)
	-- Lua {} vira [] no JSON — força {} com _ dummy
	local p = params or {}
	if type(p) == "table" then
		local n = 0
		for _ in pairs(p) do n = n + 1; break end
		if n == 0 then p = { _ = "" } end
	end

	local body = HttpService:JSONEncode({
		action = action,
		params = p,
	})

	print("[RPC] POST /rpc " .. action)

	local ok, resp = pcall(function()
		return HttpService:PostAsync(PROXY .. "/rpc", body, Enum.HttpContentType.ApplicationJson)
	end)

	if not ok then
		print("[RPC] FALHA HTTP: " .. tostring(resp))
		return {success = false, error = tostring(resp)}
	end

	print("[RPC] resp: " .. resp:sub(1, 150))
	local decodeOk, data = pcall(function() return HttpService:JSONDecode(resp) end)
	if not decodeOk then
		print("[RPC] resposta inválida: " .. tostring(data))
		return {success = false, error = "invalid_json_response"}
	end
	return data
end

--- Ping no daemon
function RPC:ping()
	print("[RPC] ping...")
	local r = self:send("ping")
	self.connected = r.success == true
	print("[RPC] ping result: " .. tostring(self.connected))
	return self.connected
end


-- DiffView
-- DiffView.lua — Renderiza diff unificado com cores
local DiffView = {}

function DiffView.render(parent, text)
	for _, c in ipairs(parent:GetChildren()) do
		if c:IsA("TextLabel") then c:Destroy() end
	end

	if not text or text == "" then
		local e = Instance.new("TextLabel")
		e.Size = UDim2.new(1, -8, 0, 20)
		e.Position = UDim2.new(0, 4, 0, 2)
		e.BackgroundTransparency = 1
		e.TextColor3 = Color3.fromRGB(180, 180, 180)
		e.Font = Enum.Font.Code
		e.TextSize = 12
		e.TextXAlignment = Enum.TextXAlignment.Left
		e.Text = "Sem mudanças"
		e.Parent = parent
		parent.CanvasSize = UDim2.new(0, 0, 0, 24)
		return 0
	end

	local y = 2
	for line in text:gmatch("[^\r\n]+") do
		local lc = Color3.fromRGB(200, 200, 200)
		local bg = Color3.fromRGB(30, 30, 30)

		if line:sub(1, 1) == "+" and line:sub(1, 3) ~= "+++" then
			lc = Color3.fromRGB(100, 255, 100); bg = Color3.fromRGB(20, 45, 20)
		elseif line:sub(1, 1) == "-" and line:sub(1, 3) ~= "---" then
			lc = Color3.fromRGB(255, 100, 100); bg = Color3.fromRGB(45, 20, 20)
		elseif line:sub(1, 2) == "@@" then
			lc = Color3.fromRGB(100, 180, 255); bg = Color3.fromRGB(25, 35, 50)
		elseif line:sub(1, 3) == "+++" or line:sub(1, 3) == "---" then
			lc = Color3.fromRGB(255, 255, 150); bg = Color3.fromRGB(40, 40, 20)
		end

		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, -4, 0, 15)
		lbl.Position = UDim2.new(0, 2, 0, y)
		lbl.BackgroundColor3 = bg
		lbl.BorderSizePixel = 0
		lbl.TextColor3 = lc
		lbl.Font = Enum.Font.Code
		lbl.TextSize = 11
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Text = line
		lbl.Parent = parent
		y = y + 16
	end

	parent.CanvasSize = UDim2.new(0, 0, 0, y + 4)
	return y / 16
end


-- GUI
-- GUI.lua — Comitter (design refinado: minimalista, escuro, cantos suaves)
local GUI = {}
GUI.widget = nil
GUI.OnCommit = nil; GUI.OnPush = nil; GUI.OnPull = nil
GUI.OnBranchSelect = nil; GUI.OnCreateBranch = nil; GUI.OnCommand = nil
GUI.OnConfigSave = nil; GUI.loadConfig = nil
GUI.OnBranchDelete = nil; GUI.OnBranchRename = nil
GUI.OnCherryPick = nil
GUI.OnHistory = nil

local termOut, termIn, branchList, statusLabel, fileList, diffView, nameBox, msgBox
local guiScreen

-- ===== HELPERS =====
local C = {
	bg = Color3.fromRGB(26, 26, 28),
	panel = Color3.fromRGB(32, 32, 35),
	top = Color3.fromRGB(40, 40, 44),
	input = Color3.fromRGB(50, 50, 54),
	accent = Color3.fromRGB(0, 120, 212),
	accentHover = Color3.fromRGB(20, 140, 232),
	green = Color3.fromRGB(14, 138, 74),
	greenHover = Color3.fromRGB(24, 158, 84),
	red = Color3.fromRGB(160, 35, 45),
	redHover = Color3.fromRGB(180, 45, 55),
	text = Color3.fromRGB(204, 204, 204),
	textDim = Color3.fromRGB(120, 120, 130),
	textBright = Color3.fromRGB(224, 224, 224),
	border = Color3.fromRGB(55, 55, 60),
	hover = Color3.fromRGB(55, 55, 60),
}
local F = {
	h = Enum.Font.GothamBold,
	b = Enum.Font.GothamMedium,
	m = Enum.Font.Code,
}

local function rnd(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 6)
	c.Parent = inst
end

local function stroke(inst, c, t)
	local s = Instance.new("UIStroke")
	s.Color = c or Color3.fromRGB(50, 50, 55)
	s.Thickness = t or 1
	s.Parent = inst
end

local function addHover(b, normal, over)
	b.MouseEnter:Connect(function() b.BackgroundColor3 = over end)
	b.MouseLeave:Connect(function() b.BackgroundColor3 = normal end)
end

function GUI:init()
	local sg = Instance.new("ScreenGui"); sg.Name = "Comitter"; sg.Parent = game:GetService("CoreGui")
	sg.ResetOnSpawn = false; sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	guiScreen = sg

	local main = Instance.new("Frame")
	main.Size = UDim2.new(0, 560, 0, 480)
	main.Position = UDim2.new(0.5, -280, 0.5, -240)
	main.BackgroundColor3 = C.bg
	main.BorderSizePixel = 0
	rnd(main, 8)
	stroke(main)
	main.Parent = sg

	-- ===== TOP BAR =====
	local top = Instance.new("Frame")
	top.Size = UDim2.new(1, 0, 0, 40)
	top.BackgroundColor3 = C.top
	top.BorderSizePixel = 0
	rnd(top, 8)
	top.Parent = main
	-- Bottom separator line
	local topLine = Instance.new("Frame")
	topLine.Size = UDim2.new(1, 0, 0, 1)
	topLine.Position = UDim2.new(0, 0, 1, 0)
	topLine.BackgroundColor3 = C.border
	topLine.BorderSizePixel = 0
	topLine.Parent = top

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(0, 100, 1, 0)
	title.Position = UDim2.new(0, 12, 0, 0)
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.fromRGB(200, 210, 230)
	title.Font = F.h
	title.TextSize = 14
	title.Text = "Comitter"
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = top

	statusLabel = Instance.new("TextLabel")
	statusLabel.Size = UDim2.new(0, 90, 1, 0)
	statusLabel.Position = UDim2.new(0, 116, 0, 0)
	statusLabel.BackgroundTransparency = 1
	statusLabel.TextColor3 = Color3.fromRGB(100, 220, 100)
	statusLabel.Font = F.b
	statusLabel.TextSize = 10
	statusLabel.Text = "● Online"
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.Parent = top

	nameBox = Instance.new("TextBox")
	nameBox.Size = UDim2.new(0, 80, 0, 24)
	nameBox.Position = UDim2.new(0, 208, 0, 8)
	nameBox.BackgroundColor3 = C.input
	nameBox.TextColor3 = C.textBright
	nameBox.PlaceholderColor3 = C.textDim
	nameBox.PlaceholderText = "place"
	nameBox.Font = F.m
	nameBox.TextSize = 11
	nameBox.Text = "MeuJogo"
	nameBox.BorderSizePixel = 0
	rnd(nameBox, 4)
	nameBox.Parent = top

	-- Top bar buttons
	local function tbtn(text, x, w, bg, action)
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0, w, 0, 26)
		b.Position = UDim2.new(0, x, 0, 7)
		b.BackgroundColor3 = bg
		b.TextColor3 = Color3.fromRGB(255, 255, 255)
		b.Font = F.h
		b.TextSize = 11
		b.Text = text
		b.AutoButtonColor = false
		b.BorderSizePixel = 0
		rnd(b, 4)
		b.Parent = top
		local map = {commit = "OnCommit", pull = "OnPull", push = "OnPush", history = "OnHistory"}
		local cb = map[action]
		if cb then
			b.MouseButton1Click:Connect(function()
				if GUI[cb] then GUI[cb]() end
			end)
		end
		if bg ~= C.green then
			addHover(b, bg, Color3.fromRGB(65, 65, 70))
		else
			addHover(b, bg, C.greenHover)
		end
	end

	tbtn("Commit", 300, 56, C.green, "commit")
	tbtn("Pull", 360, 36, Color3.fromRGB(58, 58, 62), "pull")
	tbtn("Push", 400, 36, Color3.fromRGB(58, 58, 62), "push")
	tbtn("Hist", 440, 28, Color3.fromRGB(55, 55, 60), "history")

	-- Config gear
	local conf = Instance.new("TextButton")
	conf.Size = UDim2.new(0, 28, 0, 26)
	conf.Position = UDim2.new(0, 472, 0, 7)
	conf.BackgroundColor3 = Color3.fromRGB(58, 58, 62)
	conf.TextColor3 = C.textBright
	conf.Font = F.h
	conf.TextSize = 14
	conf.Text = "⚙"
	conf.AutoButtonColor = false
	conf.BorderSizePixel = 0
	rnd(conf, 4)
	conf.Parent = top
	addHover(conf, Color3.fromRGB(58, 58, 62), Color3.fromRGB(65, 65, 70))

	-- Minimize / Close
	local minBtn = Instance.new("TextButton")
	minBtn.Size = UDim2.new(0, 26, 0, 26)
	minBtn.Position = UDim2.new(0, 504, 0, 7)
	minBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 65)
	minBtn.TextColor3 = Color3.fromRGB(180, 180, 190)
	minBtn.Font = F.h
	minBtn.TextSize = 12
	minBtn.Text = "─"
	minBtn.AutoButtonColor = false
	minBtn.BorderSizePixel = 0
	rnd(minBtn, 4)
	minBtn.Parent = top
	addHover(minBtn, Color3.fromRGB(60, 60, 65), Color3.fromRGB(70, 70, 75))

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 26, 0, 26)
	closeBtn.Position = UDim2.new(0, 534, 0, 7)
	closeBtn.BackgroundColor3 = C.red
	closeBtn.TextColor3 = Color3.fromRGB(255, 160, 160)
	closeBtn.Font = F.h
	closeBtn.TextSize = 12
	closeBtn.Text = "✕"
	closeBtn.AutoButtonColor = false
	closeBtn.BorderSizePixel = 0
	rnd(closeBtn, 4)
	closeBtn.Parent = top
	addHover(closeBtn, C.red, C.redHover)

	local toggleBtn = Instance.new("TextButton")
	toggleBtn.Size = UDim2.new(0, 32, 0, 24)
	toggleBtn.Position = UDim2.new(1, -36, 0, 4)
	toggleBtn.BackgroundColor3 = C.top
	toggleBtn.TextColor3 = Color3.fromRGB(180, 200, 220)
	toggleBtn.Font = F.h
	toggleBtn.TextSize = 11
	toggleBtn.Text = "C"
	toggleBtn.Visible = false
	toggleBtn.BorderSizePixel = 0
	rnd(toggleBtn, 4)
	toggleBtn.Parent = sg

	minBtn.MouseButton1Click:Connect(function()
		main.Visible = false; toggleBtn.Visible = true
	end)
	closeBtn.MouseButton1Click:Connect(function()
		main.Visible = false; toggleBtn.Visible = true
	end)
	toggleBtn.MouseButton1Click:Connect(function()
		main.Visible = true; toggleBtn.Visible = false
	end)

	conf.MouseButton1Click:Connect(function()
		local popup = Instance.new("Frame")
		popup.Size = UDim2.new(0, 340, 0, 250)
		popup.Position = UDim2.new(0.5, -170, 0.5, -125)
		popup.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
		popup.BorderSizePixel = 0
		popup.ZIndex = 200
		rnd(popup, 8)
		popup.Parent = sg
		stroke(popup)

		local hd = Instance.new("Frame")
		hd.Size = UDim2.new(1, 0, 0, 32)
		hd.BackgroundColor3 = Color3.fromRGB(40, 40, 46)
		hd.Parent = popup
		local ht = Instance.new("TextLabel")
		ht.Size = UDim2.new(1, -30, 1, 0); ht.Position = UDim2.new(0, 12, 0, 0)
		ht.BackgroundTransparency = 1; ht.TextColor3 = C.textBright; ht.Font = F.h
		ht.TextSize = 13; ht.Text = "Settings"; ht.TextXAlignment = Enum.TextXAlignment.Left; ht.Parent = hd
		local hx = Instance.new("TextButton")
		hx.Size = UDim2.new(0, 24, 0, 24); hx.Position = UDim2.new(1, -28, 0, 4)
		hx.BackgroundColor3 = C.red; hx.TextColor3 = Color3.fromRGB(255, 160, 160)
		hx.Font = F.h; hx.TextSize = 12; hx.Text = "✕"; hx.AutoButtonColor = false
		hx.BorderSizePixel = 0; rnd(hx, 4); hx.Parent = hd
		addHover(hx, C.red, C.redHover)
		hx.MouseButton1Click:Connect(function() popup:Destroy() end)

		local y = 40
		local function addField(label, ph)
			local lbl = Instance.new("TextLabel")
			lbl.Size = UDim2.new(1, -16, 0, 12); lbl.Position = UDim2.new(0, 8, 0, y)
			lbl.BackgroundTransparency = 1; lbl.TextColor3 = C.textDim; lbl.Font = F.h
			lbl.TextSize = 9; lbl.Text = label; lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = popup
			y = y + 14
			local tb = Instance.new("TextBox")
			tb.Size = UDim2.new(1, -16, 0, 26); tb.Position = UDim2.new(0, 8, 0, y)
			tb.BackgroundColor3 = C.input; tb.TextColor3 = C.textBright
			tb.PlaceholderColor3 = C.textDim; tb.PlaceholderText = ph
			tb.Font = F.m; tb.TextSize = 11; tb.Text = ""
			tb.BorderSizePixel = 0; rnd(tb, 4); tb.Parent = popup
			y = y + 30
			return tb
		end
		local userBox = addField("GitHub User:", "seu-usuario")
		local tokenBox = addField("GitHub Token:", "ghp_...")
		local remoteBox = addField("Remote URL:", "https://github.com/{user}/{place}.git")

		if GUI.loadConfig then
			local cfg = GUI.loadConfig()
			if cfg then
				userBox.Text = cfg.user or ""
				tokenBox.Text = cfg.token or ""
				remoteBox.Text = cfg.remote_template or ""
			end
		end

		local saveBtn = Instance.new("TextButton")
		saveBtn.Size = UDim2.new(1, -16, 0, 30); saveBtn.Position = UDim2.new(0, 8, 0, y + 4)
		saveBtn.BackgroundColor3 = C.accent; saveBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		saveBtn.Font = F.h; saveBtn.TextSize = 12; saveBtn.Text = "Save"
		saveBtn.AutoButtonColor = false; saveBtn.BorderSizePixel = 0
		rnd(saveBtn, 6); saveBtn.Parent = popup
		addHover(saveBtn, C.accent, C.accentHover)
		saveBtn.MouseButton1Click:Connect(function()
			if GUI.OnConfigSave then GUI.OnConfigSave(userBox.Text, tokenBox.Text, remoteBox.Text) end
			popup:Destroy()
		end)
	end)

	-- Drag
	local d, ds, sp = false
	top.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 and i.UserInputState == Enum.UserInputState.Begin then
			d = true; ds = i.Position; sp = main.Position
		end
	end)
	top.InputChanged:Connect(function(i)
		if d and i.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = i.Position - ds
			main.Position = UDim2.new(sp.X.Scale, sp.X.Offset + delta.X, sp.Y.Scale, sp.Y.Offset + delta.Y)
		end
	end)
	top.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then d = false end
	end)

	-- ===== BODY =====
	local body = Instance.new("Frame")
	body.Size = UDim2.new(1, 0, 1, -40)
	body.Position = UDim2.new(0, 0, 0, 40)
	body.BackgroundColor3 = C.bg
	body.Parent = main

	-- LEFT panel
	local left = Instance.new("Frame")
	left.Size = UDim2.new(0, 150, 1, 0)
	left.BackgroundColor3 = C.panel
	left.BorderSizePixel = 0
	left.Parent = body

	local lb = Instance.new("TextLabel")
	lb.Size = UDim2.new(1, -12, 0, 18); lb.Position = UDim2.new(0, 8, 0, 8)
	lb.BackgroundTransparency = 1; lb.TextColor3 = C.textDim; lb.Font = F.h
	lb.TextSize = 10; lb.Text = "BRANCHES"; lb.TextXAlignment = Enum.TextXAlignment.Left; lb.Parent = left

	branchList = Instance.new("ScrollingFrame")
	branchList.Size = UDim2.new(1, -8, 1, -116); branchList.Position = UDim2.new(0, 4, 0, 30)
	branchList.BackgroundTransparency = 1
	branchList.ScrollBarThickness = 4; branchList.CanvasSize = UDim2.new(0, 0, 0, 0)
	branchList.BorderSizePixel = 0; branchList.Parent = left
	local bll = Instance.new("UIListLayout"); bll.Padding = UDim.new(0, 2); bll.Parent = branchList

	-- New branch section
	local newLbl = Instance.new("TextLabel")
	newLbl.Size = UDim2.new(1, -12, 0, 12); newLbl.Position = UDim2.new(0, 8, 1, -80)
	newLbl.BackgroundTransparency = 1; newLbl.TextColor3 = C.textDim; newLbl.Font = F.h
	newLbl.TextSize = 9; newLbl.Text = "NEW BRANCH"; newLbl.TextXAlignment = Enum.TextXAlignment.Left; newLbl.Parent = left

	local newName = Instance.new("TextBox")
	newName.Size = UDim2.new(1, -12, 0, 20); newName.Position = UDim2.new(0, 6, 1, -64)
	newName.BackgroundColor3 = C.input; newName.TextColor3 = C.textBright; newName.PlaceholderColor3 = C.textDim
	newName.PlaceholderText = "2.0-name"; newName.Font = F.m; newName.TextSize = 11; newName.Text = ""
	newName.BorderSizePixel = 0; rnd(newName, 4); newName.Parent = left

	local newDesc = Instance.new("TextBox")
	newDesc.Size = UDim2.new(1, -12, 0, 20); newDesc.Position = UDim2.new(0, 6, 1, -42)
	newDesc.BackgroundColor3 = C.input; newDesc.TextColor3 = C.textBright; newDesc.PlaceholderColor3 = C.textDim
	newDesc.PlaceholderText = "description"; newDesc.Font = F.m; newDesc.TextSize = 11; newDesc.Text = ""
	newDesc.BorderSizePixel = 0; rnd(newDesc, 4); newDesc.Parent = left

	local newBtn = Instance.new("TextButton")
	newBtn.Size = UDim2.new(1, -12, 0, 20); newBtn.Position = UDim2.new(0, 6, 1, -20)
	newBtn.BackgroundColor3 = C.green; newBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	newBtn.Font = F.h; newBtn.TextSize = 11; newBtn.Text = "Create"
	newBtn.AutoButtonColor = false; newBtn.BorderSizePixel = 0
	rnd(newBtn, 4); newBtn.Parent = left
	addHover(newBtn, C.green, C.greenHover)
	newBtn.MouseButton1Click:Connect(function()
		if newName.Text == "" then return end
		local name = newName.Text .. (newDesc.Text ~= "" and "-" .. newDesc.Text:gsub("%s+", "-"):lower() or "")
		if GUI.OnCreateBranch then GUI.OnCreateBranch(name) end
		newName.Text = ""; newDesc.Text = ""
	end)

	-- Border between left and right
	local sep1 = Instance.new("Frame")
	sep1.Size = UDim2.new(0, 1, 1, 0); sep1.Position = UDim2.new(1, 0, 0, 0)
	sep1.BackgroundColor3 = C.border; sep1.BorderSizePixel = 0; sep1.Parent = left

	-- RIGHT panel
	local right = Instance.new("Frame")
	right.Size = UDim2.new(1, -151, 1, 0); right.Position = UDim2.new(0, 151, 0, 0)
	right.BackgroundColor3 = C.bg; right.BorderSizePixel = 0; right.Parent = body

	-- Staged changes
	local ff = Instance.new("TextLabel")
	ff.Size = UDim2.new(1, -80, 0, 18); ff.Position = UDim2.new(0, 10, 0, 8)
	ff.BackgroundTransparency = 1; ff.TextColor3 = C.textDim; ff.Font = F.h
	ff.TextSize = 10; ff.Text = "STAGED CHANGES"; ff.TextXAlignment = Enum.TextXAlignment.Left; ff.Parent = right

	local cpBtn = Instance.new("TextButton")
	cpBtn.Size = UDim2.new(0, 66, 0, 18); cpBtn.Position = UDim2.new(1, -76, 0, 8)
	cpBtn.BackgroundColor3 = Color3.fromRGB(48, 48, 55); cpBtn.TextColor3 = C.text
	cpBtn.Font = F.h; cpBtn.TextSize = 9; cpBtn.Text = "Cherry-pick"
	cpBtn.AutoButtonColor = false; cpBtn.BorderSizePixel = 0
	rnd(cpBtn, 3); cpBtn.Parent = right
	addHover(cpBtn, Color3.fromRGB(48, 48, 55), Color3.fromRGB(58, 58, 65))
	cpBtn.MouseButton1Click:Connect(function()
		if GUI.OnCherryPick then GUI.OnCherryPick() end
	end)

	fileList = Instance.new("ScrollingFrame")
	fileList.Size = UDim2.new(1, -12, 0, 110); fileList.Position = UDim2.new(0, 6, 0, 28)
	fileList.BackgroundTransparency = 1; fileList.ScrollBarThickness = 4
	fileList.CanvasSize = UDim2.new(0, 0, 0, 0); fileList.BorderSizePixel = 0; fileList.Parent = right
	local fll = Instance.new("UIListLayout"); fll.Padding = UDim.new(0, 1); fll.Parent = fileList

	-- Commit message
	local cl = Instance.new("TextLabel")
	cl.Size = UDim2.new(1, -12, 0, 14); cl.Position = UDim2.new(0, 10, 0, 144)
	cl.BackgroundTransparency = 1; cl.TextColor3 = C.textDim; cl.Font = F.h
	cl.TextSize = 10; cl.Text = "COMMIT MESSAGE"; cl.TextXAlignment = Enum.TextXAlignment.Left; cl.Parent = right

	msgBox = Instance.new("TextBox")
	msgBox.Size = UDim2.new(1, -12, 0, 26); msgBox.Position = UDim2.new(0, 6, 0, 160)
	msgBox.BackgroundColor3 = C.input; msgBox.TextColor3 = C.textBright; msgBox.PlaceholderColor3 = C.textDim
	msgBox.PlaceholderText = "Describe what changed..."; msgBox.Font = F.m; msgBox.TextSize = 12; msgBox.Text = ""
	msgBox.BorderSizePixel = 0; rnd(msgBox, 4); msgBox.Parent = right

	-- Diff viewer
	local dl = Instance.new("TextLabel")
	dl.Size = UDim2.new(1, -12, 0, 14); dl.Position = UDim2.new(0, 10, 0, 192)
	dl.BackgroundTransparency = 1; dl.TextColor3 = C.textDim; dl.Font = F.h
	dl.TextSize = 10; dl.Text = "DIFF VIEWER"; dl.TextXAlignment = Enum.TextXAlignment.Left; dl.Parent = right

	diffView = Instance.new("ScrollingFrame")
	diffView.Size = UDim2.new(1, 0, 1, -230); diffView.Position = UDim2.new(0, 0, 0, 208)
	diffView.BackgroundTransparency = 0; diffView.BackgroundColor3 = Color3.fromRGB(24, 24, 26)
	diffView.ScrollBarThickness = 4; diffView.CanvasSize = UDim2.new(0, 0, 0, 0)
	diffView.BorderSizePixel = 0; diffView.Parent = right

	-- Terminal
	local tf = Instance.new("Frame")
	tf.Size = UDim2.new(1, 0, 0, 28); tf.Position = UDim2.new(0, 0, 1, -28)
	tf.BackgroundColor3 = Color3.fromRGB(24, 24, 26); tf.BorderSizePixel = 0; tf.Parent = right
	-- Terminal top border
	local tfLine = Instance.new("Frame")
	tfLine.Size = UDim2.new(1, 0, 0, 1); tfLine.Position = UDim2.new(0, 0, 0, 0)
	tfLine.BackgroundColor3 = C.border; tfLine.BorderSizePixel = 0; tfLine.Parent = tf

	termIn = Instance.new("TextBox")
	termIn.Size = UDim2.new(1, -10, 0, 22); termIn.Position = UDim2.new(0, 5, 0, 3)
	termIn.BackgroundColor3 = C.input; termIn.BorderSizePixel = 0
	termIn.TextColor3 = Color3.fromRGB(180, 220, 180); termIn.PlaceholderColor3 = C.textDim
	termIn.PlaceholderText = "> help"; termIn.Font = F.m; termIn.TextSize = 12; termIn.Text = ""
	rnd(termIn, 4); termIn.Parent = tf
	termIn.FocusLost:Connect(function(ep)
		if ep and termIn.Text ~= "" and GUI.OnCommand then GUI.OnCommand(termIn.Text); termIn.Text = "" end
	end)

	GUI.widget = main
end

-- ===== PUBLIC METHODS =====

function GUI:setStatus(t, on)
	if statusLabel then
		statusLabel.Text = t
		statusLabel.TextColor3 = on and Color3.fromRGB(100, 220, 100) or Color3.fromRGB(255, 100, 100)
	end
end

function GUI:setBranches(branches)
	if not branchList then return end
	if guiScreen then
		local c = guiScreen:FindFirstChild("BranchCtx")
		if c then c:Destroy() end
		local b = guiScreen:FindFirstChild("CtxBlocker")
		if b then b:Destroy() end
	end
	for _, c in ipairs(branchList:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end
	for _, b in ipairs(branches or {}) do
		local hasMenu = (b.name ~= "main")
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -8, 0, 24)
		row.BackgroundTransparency = 1
		row.Parent = branchList

		local item = Instance.new("TextButton")
		item.Size = hasMenu and UDim2.new(1, -26, 1, 0) or UDim2.new(1, 0, 1, 0)
		item.BackgroundColor3 = b.current and Color3.fromRGB(20, 55, 32) or Color3.fromRGB(42, 42, 46)
		item.TextColor3 = b.current and Color3.fromRGB(180, 255, 200) or C.text
		item.Font = F.m
		item.TextSize = 10
		item.TextXAlignment = Enum.TextXAlignment.Left
		item.AutoButtonColor = false
		item.BorderSizePixel = 0
		item.Text = (b.current and "✓ " or "  ") .. b.name
		if b.created then
			item.Text = item.Text .. "  " .. (b.created:sub(5, 10) or b.created)
		end
		rnd(item, 4)
		item.Parent = row
		if not b.current then
			addHover(item, Color3.fromRGB(42, 42, 46), Color3.fromRGB(52, 52, 56))
		end
		item.MouseButton1Click:Connect(function()
			if GUI.OnBranchSelect then GUI.OnBranchSelect(b.name) end
		end)

		if hasMenu then
			local menu = Instance.new("TextButton")
			menu.Size = UDim2.new(0, 22, 1, 0)
			menu.Position = UDim2.new(1, -22, 0, 0)
			menu.BackgroundColor3 = Color3.fromRGB(50, 50, 54)
			menu.TextColor3 = C.textDim
			menu.Font = F.h
			menu.TextSize = 11
			menu.Text = "⋯"
			menu.AutoButtonColor = false
			menu.BorderSizePixel = 0
			rnd(menu, 4)
			menu.Parent = row
			menu.MouseButton1Click:Connect(function()
				if guiScreen then
					local oldCtx = guiScreen:FindFirstChild("BranchCtx")
					if oldCtx then oldCtx:Destroy() end
					local oldBlocker = guiScreen:FindFirstChild("CtxBlocker")
					if oldBlocker then oldBlocker:Destroy() end
				end
				local absPos = row.AbsolutePosition
				local absSize = row.AbsoluteSize
				local blocker = Instance.new("TextButton")
				blocker.Name = "CtxBlocker"
				blocker.Size = UDim2.new(1, 0, 1, 0)
				blocker.BackgroundTransparency = 1
				blocker.Text = ""
				blocker.Parent = guiScreen
				blocker.ZIndex = 249
				local ctx = Instance.new("Frame")
				ctx.Name = "BranchCtx"
				ctx.Size = UDim2.new(0, 120, 0, 64)
				ctx.Position = UDim2.new(0, absPos.X, 0, absPos.Y + absSize.Y)
				ctx.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
				ctx.BorderSizePixel = 0
				ctx.ZIndex = 250
				rnd(ctx, 6)
				ctx.Parent = guiScreen
				local function dismiss()
					blocker:Destroy(); ctx:Destroy()
				end
				blocker.MouseButton1Click:Connect(dismiss)

				local del = Instance.new("TextButton")
				del.Size = UDim2.new(1, 0, 0, 30)
				del.BackgroundColor3 = Color3.fromRGB(55, 22, 28)
				del.TextColor3 = Color3.fromRGB(255, 140, 140)
				del.Font = F.h; del.TextSize = 11; del.Text = "Delete"
				del.AutoButtonColor = false; del.BorderSizePixel = 0; del.Parent = ctx
				del.MouseButton1Click:Connect(function()
					dismiss()
					if GUI.OnBranchDelete then GUI.OnBranchDelete(b.name) end
				end)

				local ren = Instance.new("TextButton")
				ren.Size = UDim2.new(1, 0, 0, 30); ren.Position = UDim2.new(0, 0, 0, 32)
				ren.BackgroundColor3 = Color3.fromRGB(42, 42, 50)
				ren.TextColor3 = C.text
				ren.Font = F.h; ren.TextSize = 11; ren.Text = "Rename"
				ren.AutoButtonColor = false; ren.BorderSizePixel = 0; ren.Parent = ctx
				ren.MouseButton1Click:Connect(function()
					dismiss()
					if GUI.OnBranchRename then GUI.OnBranchRename(b.name) end
				end)
			end)
		end
	end
	branchList.CanvasSize = UDim2.new(0, 0, 0, #branches * 26 + 4)
end

function GUI:setFiles(files)
	if not fileList then return end
	for _, c in ipairs(fileList:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
	for _, f in ipairs(files or {}) do
		local item = Instance.new("TextButton")
		item.Size = UDim2.new(1, -6, 0, 20)
		item.BackgroundTransparency = 1; item.TextColor3 = C.textDim
		item.Font = F.m; item.TextSize = 10
		item.TextXAlignment = Enum.TextXAlignment.Left; item.Text = "  " .. f
		item.AutoButtonColor = false; item.BorderSizePixel = 0; item.Parent = fileList
	end
	fileList.CanvasSize = UDim2.new(0, 0, 0, #files * 21 + 2)
end

function GUI:setDiff(text)
	if not diffView then return end
	for _, c in ipairs(diffView:GetChildren()) do if c:IsA("TextLabel") then c:Destroy() end end
	if not text or text == "" then return end
	local y = 4
	for line in text:gmatch("[^\r\n]+") do
		local lc = C.text
		if line:sub(1,1) == "+" and line:sub(1,3) ~= "+++" then lc = Color3.fromRGB(100, 255, 100)
		elseif line:sub(1,1) == "-" and line:sub(1,3) ~= "---" then lc = Color3.fromRGB(255, 100, 100)
		elseif line:sub(1,2) == "@@" then lc = Color3.fromRGB(100, 180, 255) end
		local l = Instance.new("TextLabel")
		l.Size = UDim2.new(1, -8, 0, 14); l.Position = UDim2.new(0, 4, 0, y)
		l.BackgroundTransparency = 1; l.TextColor3 = lc; l.Font = F.m; l.TextSize = 11
		l.TextXAlignment = Enum.TextXAlignment.Left; l.Text = line
		l.BorderSizePixel = 0; l.Parent = diffView; y = y + 15
	end
	diffView.CanvasSize = UDim2.new(0, 0, 0, y + 4)
end

function GUI:termLog(t, c) print("[Comitter] " .. t) end
function GUI:termWrite(t, c) GUI:termLog(t, c) end
function GUI:getName() return nameBox and nameBox.Text or "MeuJogo" end
function GUI:setName(n) if nameBox then nameBox.Text = n end end
function GUI:getMsg() return msgBox and msgBox.Text or "save" end


-- init
-- init.lua — Comitter v0.7.0
-- Ordem CRÍTICA: helpers → callbacks → GUI:init()

local state = { online = false, branch = "main", place = "MeuJogo", branches = {}, staged = {}, config = {}, currentHash = "", dirty = false }

-- ===== SCANNER =====
local function ensureUID(inst)
	local uid = inst:GetAttribute("Comitter_uid")
	if not uid then
		uid = HttpService:GenerateGUID(false)
		inst:SetAttribute("Comitter_uid", uid)
	end
	return uid
end

local function getBaseHash(inst)
	return inst:GetAttribute("Comitter_base") or ""
end

local function setBaseHash(inst, hash)
	inst:SetAttribute("Comitter_base", hash or "")
end

local function scriptNameFromFilename(name)
	return name:gsub("%.lua$", ""):gsub("%.server$", ""):gsub("%.client$", "")
end

local function scanScripts()
	local files = {}
	local function scan(parent, prefix)
		for _, child in ipairs(parent:GetChildren()) do
			if child:IsA("LuaSourceContainer") then
				local key = prefix .. "/" .. child.Name
				files[key] = {
					source = child.Source,
					obj = child,
					path = key,
					uid = ensureUID(child),
					base = getBaseHash(child),
					class = child.ClassName,
				}
				if not child:GetAttribute("Comitter_dirtyConnected") then
					child:SetAttribute("Comitter_dirtyConnected", true)
					local ok, sig = pcall(function()
						return child:GetPropertyChangedSignal("Source")
					end)
					if ok and sig then
						sig:Connect(function()
							state.dirty = true
						end)
					end
				end
			end
			scan(child, prefix .. "/" .. child.Name)
		end
	end
	scan(game:GetService("ServerScriptService"), "ServerScriptService")
	scan(game:GetService("ServerStorage"), "ServerStorage")
	scan(game:GetService("ReplicatedStorage"), "ReplicatedStorage")
	local sp = game:GetService("StarterPlayer")
	if sp then
		local sps = sp:FindFirstChild("StarterPlayerScripts")
		if sps then scan(sps, "StarterPlayer/StarterPlayerScripts") end
		local scs = sp:FindFirstChild("StarterCharacterScripts")
		if scs then scan(scs, "StarterPlayer/StarterCharacterScripts") end
	end
	scan(game:GetService("StarterGui"), "StarterGui")
	local spk = game:GetService("StarterPack")
	if spk then scan(spk, "StarterPack") end
	return files
end

local function stagedList()
	local t = {}
	for k in pairs(state.staged) do table.insert(t, k) end
	table.sort(t)
	return t
end

local function refreshUI()
	-- Sort branches: main first, then by name
	local sorted = {}
	for _, b in ipairs(state.branches) do table.insert(sorted, b) end
	table.sort(sorted, function(a, b)
		if a.name == "main" then return true end
		if b.name == "main" then return false end
		return a.name < b.name
	end)
	GUI:setBranches(sorted)
	GUI:setFiles(stagedList())
end

local function log(msg, color)
	print("[Comitter] " .. msg)
end

-- ===== INJECT SCRIPTS INTO STUDIO =====
local SCRIPT_SERVICES = {"ServerScriptService", "ServerStorage", "ReplicatedStorage", "StarterGui", "StarterPack"}

local function pruneEmptyFolders(root)
	for _, child in ipairs(root:GetChildren()) do
		if child:IsA("Folder") then
			pruneEmptyFolders(child)
			if #child:GetChildren() == 0 then
				child:Destroy()
			end
		end
	end
end

local function injectScripts(fileMap, uids, commitHash, classes)
	-- Destrói só o que não existe mais na branch alvo (recursivo, cobre subpastas)
	local current = scanScripts()
	for path, info in pairs(current) do
		if not fileMap[path] then
			info.obj:Destroy()
		end
	end

	local n = 0
	for fp, src in pairs(fileMap) do
		local svcName = fp:match("^([^/]+)")
		if svcName then
			local svc = game:GetService(svcName)
			if svc then
				local parts = {}
				for seg in (fp:sub(#svcName + 2)):gmatch("[^/]+") do table.insert(parts, seg) end
				local cur = svc
				for i = 1, #parts - 1 do
					local f = cur:FindFirstChild(parts[i])
					if not f then f = Instance.new("Folder"); f.Name = parts[i]; f.Parent = cur end
					cur = f
				end
				if #parts > 0 then
					local sname = scriptNameFromFilename(parts[#parts])
					local classType = (classes and classes[fp]) or "Script"
					local existing = cur:FindFirstChild(sname)

					-- Classe mudou (ex: Script virou ModuleScript) → recria
					if existing and existing.ClassName ~= classType then
						existing:Destroy()
						existing = nil
					end

					if not existing then
						if classType == "LocalScript" then existing = Instance.new("LocalScript")
						elseif classType == "ModuleScript" then existing = Instance.new("ModuleScript")
						else existing = Instance.new("Script")
						end
						existing.Name = sname; existing.Parent = cur
					end

					if existing.Source ~= src then
						existing.Source = src
					end
					if uids and uids[fp] then
						existing:SetAttribute("Comitter_uid", uids[fp])
					else
						ensureUID(existing)
					end
					if commitHash and commitHash ~= "" then
						setBaseHash(existing, commitHash)
					end
					n = n + 1
				end
			end
		end
	end

	for _, svcName in ipairs(SCRIPT_SERVICES) do
		local svc = game:GetService(svcName)
		if svc then pruneEmptyFolders(svc) end
	end
	local sp = game:GetService("StarterPlayer")
	if sp then
		for _, subName in ipairs({"StarterPlayerScripts", "StarterCharacterScripts"}) do
			local sub = sp:FindFirstChild(subName)
			if sub then pruneEmptyFolders(sub) end
		end
	end

	return n
end

-- ===== DAEMON OPERATIONS =====

local function loadConfig()
	local r = RPC:send("config_get", {})
	if r.success and r.config then
		state.config = r.config
	end
end

local function saveConfig(user, token, remote)
	RPC:send("config_set", {user = user, token = token, remote_template = remote})
	state.config = {user = user, token = token, remote_template = remote}
	log("Config saved")
end

local function loadBranches()
	local r = RPC:send("branches", {place = state.place})
	if r.success then
		state.branches = {}
		for _, b in ipairs(r.branches or {}) do
			b.current = (b.name == state.branch)
			table.insert(state.branches, b)
		end
		refreshUI()
		log("Loaded " .. #state.branches .. " branches")
	end
end

local function doPush()
	state.place = GUI:getName()
	log("Pushing " .. state.branch .. "...")
	local r = RPC:send("push", {place = state.place, branch = state.branch})
	if r.success then
		log("✓ Pushed to GitHub")
	else
		log("✗ Push: " .. (r.error or "failed"))
	end
end

local function doCommit()
	state.place = GUI:getName()
	local all = scanScripts()
	local count = 0
	local payload = {}
	local uids = {}
	local classes = {}
	for key, info in pairs(all) do
		payload[key] = info.source
		uids[key] = info.uid
		classes[key] = info.class or "Script"
		count = count + 1
	end
	if count == 0 then
		log("No scripts found")
		return
	end
	local msg = GUI:getMsg()
	if msg == "" then msg = "save" end
	local gameId = tostring(game.GameId)
	if gameId == "0" then gameId = tostring(game.PlaceId) end
	log("Committing " .. state.place .. " [" .. state.branch .. "] " .. count .. " files")
	local r = RPC:send("commit", {place = state.place, message = msg, files = payload, uids = uids, classes = classes, branch = state.branch, game_id = gameId})
	if r.success then
		local short = r.hash and r.hash:sub(1, 7) or "?"
		log("✓ " .. short .. " " .. msg)
		-- Update Comitter_base on all committed instances
		for key, info in pairs(all) do
			setBaseHash(info.obj, r.hash)
		end
		state.currentHash = r.hash
		state.dirty = false
		state.staged = all
		GUI:setFiles(stagedList())
		local diffText = "Commit: " .. short .. "\n"
		for key in pairs(all) do
			diffText = diffText .. "+ " .. key .. "\n"
		end
		GUI:setDiff(diffText)
		task.wait(0.5)
		doPush()
	else
		log("✗ " .. (r.error or "commit failed"))
	end
end

local function doPull()
	state.place = GUI:getName()
	if state.dirty then
		log("⚠ Mudanças não commitadas — commit antes de dar pull, ou serão perdidas")
		return
	end
	log("Pulling " .. state.branch .. "...")
	local r = RPC:send("pull", {place = state.place, branch = state.branch})
	if r.success then
		log("✓ Pulled")
		if r.files then
			local n = injectScripts(r.files, r.uids, r.commit_hash, r.classes)
			log("Applied " .. n .. " scripts to Studio")
		end
		state.staged = scanScripts()
		GUI:setFiles(stagedList())
	else
		log("✗ " .. (r.error or "pull failed"))
	end
end

local function applyBranch(name, files, uids, commitHash, classes)
	local n = injectScripts(files, uids, commitHash, classes)
	log("  Loaded " .. n .. " scripts from " .. name)
	state.dirty = false
	state.staged = scanScripts()
	GUI:setFiles(stagedList())
end

local function selectBranch(name, force)
	if not force and name == state.branch then return end
	local prevBranch = state.branch
	state.branch = name
	state.place = GUI:getName()
	for _, b in ipairs(state.branches) do b.current = (b.name == name) end
	refreshUI()
	log("Switched to " .. name)
	GUI:setStatus("● Online · " .. name, true)
	local r = RPC:send("read_branch", {place = state.place, branch = state.branch})
	if not r.success or not r.files then
		log("  No scripts in " .. name)
		state.staged = scanScripts()
		GUI:setFiles(stagedList())
		return
	end

	-- Unsaved changes warning (modified but not committed)
	state.currentHash = r.commit_hash or ""

	local function doSafetyCheck()
		local edited = {}
		for _, info in pairs(scanScripts()) do
			local base = getBaseHash(info.obj)
			if base ~= "" and base ~= (r.commit_hash or "") then
				table.insert(edited, info.path)
			end
		end

		if #edited > 0 then
			log("  " .. #edited .. " scripts edited locally — safety check")
			local sg = GUI.widget and GUI.widget.Parent
			if not sg then
				applyBranch(name, r.files, r.uids, r.commit_hash, r.classes)
				return
			end
			local popup = Instance.new("Frame")
			popup.Size = UDim2.new(0, 380, 0, 220)
			popup.Position = UDim2.new(0.5, -190, 0.5, -110)
			popup.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
			popup.BorderSizePixel = 1; popup.BorderColor3 = Color3.fromRGB(60, 60, 70)
			popup.ZIndex = 300; popup.Parent = sg

			local hd = Instance.new("Frame"); hd.Size = UDim2.new(1, 0, 0, 28)
			hd.BackgroundColor3 = Color3.fromRGB(40, 40, 48); hd.Parent = popup
			local ht = Instance.new("TextLabel"); ht.Size = UDim2.new(1, -30, 1, 0); ht.Position = UDim2.new(0, 8, 0, 0)
			ht.BackgroundTransparency = 1; ht.TextColor3 = Color3.fromRGB(220, 220, 240); ht.Font = Enum.Font.GothamBold
			ht.TextSize = 13; ht.Text = "Local changes detected"; ht.TextXAlignment = Enum.TextXAlignment.Left; ht.Parent = hd

			local msg = Instance.new("TextLabel"); msg.Size = UDim2.new(1, -16, 0, 60); msg.Position = UDim2.new(0, 8, 0, 32)
			msg.BackgroundTransparency = 1; msg.TextColor3 = Color3.fromRGB(200, 200, 210); msg.Font = Enum.Font.Code
			msg.TextSize = 10; msg.TextWrapped = true; msg.TextXAlignment = Enum.TextXAlignment.Left
			msg.Text = table.concat(edited, "\n"); msg.Parent = popup

			local function makeBtn(text, clr, y, cb)
				local b = Instance.new("TextButton"); b.Size = UDim2.new(0.5, -6, 0, 26)
				b.Position = UDim2.new(0, y == 1 and 4 or 190, 0, 100)
				b.BackgroundColor3 = clr; b.TextColor3 = Color3.fromRGB(255, 255, 255)
				b.Font = Enum.Font.GothamBold; b.TextSize = 12; b.Text = text; b.Parent = popup
				b.MouseButton1Click:Connect(cb)
			end

			makeBtn("Keep mine (skip)", Color3.fromRGB(60, 60, 80), 1, function()
				popup:Destroy()
				local n = 0
				for fp, src in pairs(r.files) do
					local isEdited = false
					for _, e in ipairs(edited) do if e == fp then isEdited = true; break end end
					if isEdited then
						log("  Skipping " .. fp)
					else
						local svcName = fp:match("^([^/]+)")
						if svcName then
							local svc = game:GetService(svcName)
							if svc then
								local parts = {}
								for seg in (fp:sub(#svcName + 2)):gmatch("[^/]+") do table.insert(parts, seg) end
								local cur = svc
								for i = 1, #parts - 1 do
									local f = cur:FindFirstChild(parts[i])
									if not f then f = Instance.new("Folder"); f.Name = parts[i]; f.Parent = cur end
									cur = f
								end
								if #parts > 0 then
									local sname = scriptNameFromFilename(parts[#parts])
									local existing = cur:FindFirstChild(sname)
									local classType = (r.classes and r.classes[fp]) or "Script"
									if not existing then
										if classType == "LocalScript" then existing = Instance.new("LocalScript")
										elseif classType == "ModuleScript" then existing = Instance.new("ModuleScript")
										else existing = Instance.new("Script")
										end
										existing.Name = sname; existing.Parent = cur
									end
									existing.Source = src
									if r.uids and r.uids[fp] then
										existing:SetAttribute("Comitter_uid", r.uids[fp])
									end
									if r.commit_hash and r.commit_hash ~= "" then
										setBaseHash(existing, r.commit_hash)
									end
									n = n + 1
								end
							end
						end
					end
				end
				log("  Applied " .. n .. " scripts, kept " .. #edited .. " local")
				state.staged = scanScripts()
				GUI:setFiles(stagedList())
			end)
			makeBtn("Overwrite all", Color3.fromRGB(0, 140, 80), 2, function()
				popup:Destroy()
				applyBranch(name, r.files, r.uids, r.commit_hash, r.classes)
			end)
			local cancelBtn = Instance.new("TextButton")
			cancelBtn.Size = UDim2.new(1, -8, 0, 26); cancelBtn.Position = UDim2.new(0, 4, 0, 134)
			cancelBtn.BackgroundColor3 = Color3.fromRGB(80, 30, 30); cancelBtn.TextColor3 = Color3.fromRGB(255, 130, 130)
			cancelBtn.Font = Enum.Font.GothamBold; cancelBtn.TextSize = 12; cancelBtn.Text = "Cancel switch"
			cancelBtn.Parent = popup
			cancelBtn.MouseButton1Click:Connect(function()
				popup:Destroy()
				state.branch = prevBranch
				for _, b in ipairs(state.branches) do b.current = (b.name == state.branch) end
				refreshUI()
				GUI:setStatus("● Online · " .. state.branch, true)
			end)
		else
			applyBranch(name, r.files, r.uids, r.commit_hash, r.classes)
		end
	end

	if state.dirty then
		local sg = GUI.widget and GUI.widget.Parent
		if sg then
			local unsavedPopup = Instance.new("Frame")
			unsavedPopup.Size = UDim2.new(0, 360, 0, 120)
			unsavedPopup.Position = UDim2.new(0.5, -180, 0.5, -60)
			unsavedPopup.BackgroundColor3 = Color3.fromRGB(28, 28, 35)
			unsavedPopup.BorderSizePixel = 1; unsavedPopup.BorderColor3 = Color3.fromRGB(60, 60, 70)
			unsavedPopup.ZIndex = 350; unsavedPopup.Parent = sg

			local ut = Instance.new("TextLabel")
			ut.Size = UDim2.new(1, -16, 0, 30); ut.Position = UDim2.new(0, 8, 0, 10)
			ut.BackgroundTransparency = 1; ut.TextColor3 = Color3.fromRGB(240, 200, 100)
			ut.Font = Enum.Font.GothamBold; ut.TextSize = 13
			ut.Text = "⚠ Uncommitted changes detected"
			ut.TextXAlignment = Enum.TextXAlignment.Left; ut.Parent = unsavedPopup

			local um = Instance.new("TextLabel")
			um.Size = UDim2.new(1, -16, 0, 20); um.Position = UDim2.new(0, 8, 0, 38)
			um.BackgroundTransparency = 1; um.TextColor3 = Color3.fromRGB(200, 200, 210)
			um.Font = Enum.Font.GothamMedium; um.TextSize = 11
			um.Text = "Commit & push before switching to " .. name .. "?"
			um.TextXAlignment = Enum.TextXAlignment.Left; um.Parent = unsavedPopup

			local cpBtn = Instance.new("TextButton")
			cpBtn.Size = UDim2.new(0.5, -6, 0, 28); cpBtn.Position = UDim2.new(0, 4, 0, 74)
			cpBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 212)
			cpBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
			cpBtn.Font = Enum.Font.GothamBold; cpBtn.TextSize = 12; cpBtn.Text = "Commit & Push"
			cpBtn.BorderSizePixel = 0; cpBtn.Parent = unsavedPopup
			cpBtn.MouseButton1Click:Connect(function()
				unsavedPopup:Destroy()
				-- Commit to the original branch first
				state.branch = prevBranch
				doCommit()
				state.branch = name
				if not state.dirty then
					-- Commit succeeded: apply target branch directly
					local r2 = RPC:send("read_branch", {place = state.place, branch = state.branch})
					if r2.success and r2.files then
						for _, b in ipairs(state.branches) do b.current = (b.name == name) end
						refreshUI()
						applyBranch(name, r2.files, r2.uids, r2.commit_hash, r2.classes)
						log("Switched to " .. name)
						GUI:setStatus("● Online · " .. name, true)
					else
						log("  No scripts in " .. name)
						state.staged = scanScripts()
						GUI:setFiles(stagedList())
					end
				else
					doSafetyCheck()
				end
			end)

			local skBtn = Instance.new("TextButton")
			skBtn.Size = UDim2.new(0.5, -6, 0, 28); skBtn.Position = UDim2.new(0.5, 2, 0, 74)
			skBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 68)
			skBtn.TextColor3 = Color3.fromRGB(200, 200, 210)
			skBtn.Font = Enum.Font.GothamBold; skBtn.TextSize = 12; skBtn.Text = "Skip"
			skBtn.BorderSizePixel = 0; skBtn.Parent = unsavedPopup
			skBtn.MouseButton1Click:Connect(function()
				unsavedPopup:Destroy()
				doSafetyCheck()
			end)
			return  -- Wait for user choice (button handlers above)
		end
	end

	doSafetyCheck()
end

local function deleteBranch(name)
	log("Deleting " .. name)
	local r = RPC:send("delete_branch", {place = state.place, name = name})
	if r.success then
		log("✓ Deleted " .. name)
		if state.branch == name then state.branch = "main" end
		loadBranches()
	else
		log("✗ " .. (r.error or "delete failed"))
	end
end

local function renameBranch(oldName)
	local sg = GUI.widget and GUI.widget.Parent
	if not sg then return end
	local existing = sg:FindFirstChild("RenamePopup")
	if existing then existing:Destroy() end
	local popup = Instance.new("Frame")
	popup.Name = "RenamePopup"
	popup.Size = UDim2.new(0, 280, 0, 100)
	popup.Position = UDim2.new(0.5, -140, 0.5, -50)
	popup.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
	popup.BorderSizePixel = 1; popup.BorderColor3 = Color3.fromRGB(60, 60, 70)
	popup.ZIndex = 300; popup.Parent = sg
	local hd = Instance.new("Frame"); hd.Size = UDim2.new(1, 0, 0, 28)
	hd.BackgroundColor3 = Color3.fromRGB(40, 40, 48); hd.Parent = popup
	local ht = Instance.new("TextLabel"); ht.Size = UDim2.new(1, -30, 1, 0); ht.Position = UDim2.new(0, 8, 0, 0)
	ht.BackgroundTransparency = 1; ht.TextColor3 = Color3.fromRGB(220, 220, 240); ht.Font = Enum.Font.GothamBold
	ht.TextSize = 13; ht.Text = "Rename: " .. oldName; ht.TextXAlignment = Enum.TextXAlignment.Left; ht.Parent = hd
	local hx = Instance.new("TextButton"); hx.Size = UDim2.new(0, 24, 0, 24); hx.Position = UDim2.new(1, -26, 0, 2)
	hx.BackgroundColor3 = Color3.fromRGB(80, 30, 30); hx.TextColor3 = Color3.fromRGB(255, 130, 130); hx.Font = Enum.Font.Code
	hx.TextSize = 14; hx.Text = "X"; hx.Parent = hd
	hx.MouseButton1Click:Connect(function() popup:Destroy() end)
	local input = Instance.new("TextBox"); input.Size = UDim2.new(1, -16, 0, 24); input.Position = UDim2.new(0, 8, 0, 36)
	input.BackgroundColor3 = Color3.fromRGB(45, 45, 50); input.TextColor3 = Color3.fromRGB(240, 240, 250)
	input.Font = Enum.Font.Code; input.TextSize = 12; input.Text = oldName; input.Parent = popup
	local save = Instance.new("TextButton"); save.Size = UDim2.new(1, -16, 0, 24); save.Position = UDim2.new(0, 8, 0, 66)
	save.BackgroundColor3 = Color3.fromRGB(0, 140, 80); save.TextColor3 = Color3.fromRGB(255, 255, 255)
	save.Font = Enum.Font.GothamBold; save.TextSize = 12; save.Text = "Rename"; save.Parent = popup
	save.MouseButton1Click:Connect(function()
		local newName = input.Text:gsub("%s+", "-")
		if newName ~= oldName then
			local r = RPC:send("rename_branch", {place = state.place, old = oldName, new = newName})
			if r.success then
				log("✓ Renamed " .. oldName .. " → " .. newName)
				if state.branch == oldName then state.branch = newName end
				loadBranches()
			else
				log("✗ " .. (r.error or "rename failed"))
			end
		end
		popup:Destroy()
	end)
end

local function createBranch(name)
	-- Sanitize: spaces → dashes, lowercase
	name = name:gsub("%s+", "-"):lower()
	if name:sub(1, 9) ~= "branches/" then name = "branches/" .. name end
	log("Creating " .. name .. "...")
	local r = RPC:send("create_branch", {place = state.place, name = name, base = "main"})
	if r.success then
		state.branch = name
		loadBranches()
		log("✓ Created " .. name)
		GUI:setStatus("● Online · " .. name, true)
	else
		log("✗ " .. (r.error or "create failed"))
	end
end

local function handleCommand(cmd)
	cmd = cmd:match("^%s*(.-)%s*$")
	if cmd == "" then return end
	if cmd == "help" then
		log("commit | push | pull | merge <src> <dst> | config | scan | connect")
		return
	end
	if not state.online then
		log("Offline — run 'connect'")
		return
	end
	if cmd == "commit" then doCommit()
	elseif cmd == "push" then doPush()
	elseif cmd == "pull" then doPull()
	elseif cmd == "scan" then state.staged = scanScripts(); refreshUI(); log("Scanned " .. #stagedList() .. " scripts")
	elseif cmd == "connect" then
		state.online = RPC:ping()
		GUI:setStatus(state.online and "● Online" or "○ Offline", state.online)
		log(state.online and "Connected" or "Offline")
		if state.online then
			loadConfig()
			loadBranches()
		end
	elseif cmd:match("^merge ") then
		local src, tgt = cmd:match("^merge (%S+) (%S+)$")
		if not src then src, tgt = cmd:match("^merge (%S+)") end
		if not src then
			log("Usage: merge <source> [target]")
			return
		end
		if not tgt then tgt = "main" end
		log("Merging " .. src .. " → " .. tgt)
		local r = RPC:send("merge", {place = state.place, source = src, target = tgt})
		if r.success then log("✓ Merged " .. src .. " → " .. tgt)
		else log("✗ Merge: " .. (r.error or "failed")) end
	elseif cmd == "config" then
		log("Click the gear button in the top bar")
	else
		log("? (help)")
	end
end

-- ===== ASSIGN CALLBACKS (= ANTES DO GUI:init()) =====
GUI.OnCommit = doCommit
GUI.OnPush = doPush
GUI.OnPull = doPull
GUI.OnBranchSelect = selectBranch
GUI.OnCreateBranch = createBranch
GUI.OnBranchDelete = deleteBranch
GUI.OnBranchRename = renameBranch
GUI.OnCommand = handleCommand
GUI.OnConfigSave = saveConfig
GUI.OnCherryPick = function()
	local sg = GUI.widget and GUI.widget.Parent
	if not sg then return end
	-- Build branch list for dropdown
	local branchNames = {}
	for _, b in ipairs(state.branches) do
		if b.name ~= state.branch then table.insert(branchNames, b.name) end
	end
	if #branchNames == 0 then
		log("No other branches to cherry-pick from")
		return
	end

	local sg = GUI.widget and GUI.widget.Parent
	if not sg then return end
	-- Destroy existing cherry-pick popup if any
	local existingCp = sg:FindFirstChild("CherryPickPopup")
	if existingCp then existingCp:Destroy() end

	local popup = Instance.new("Frame")
	popup.Name = "CherryPickPopup"
	popup.Size = UDim2.new(0, 360, 0, 400)
	popup.Position = UDim2.new(0.5, -180, 0.5, -200)
	popup.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
	popup.BorderSizePixel = 1; popup.BorderColor3 = Color3.fromRGB(60, 60, 70)
	popup.ZIndex = 400; popup.Parent = sg

	local hd = Instance.new("Frame"); hd.Size = UDim2.new(1, 0, 0, 28)
	hd.BackgroundColor3 = Color3.fromRGB(40, 40, 48); hd.Parent = popup
	local ht = Instance.new("TextLabel"); ht.Size = UDim2.new(1, -30, 1, 0); ht.Position = UDim2.new(0, 8, 0, 0)
	ht.BackgroundTransparency = 1; ht.TextColor3 = Color3.fromRGB(220, 220, 240); ht.Font = Enum.Font.GothamBold
	ht.TextSize = 13; ht.Text = "Cherry-pick script"; ht.TextXAlignment = Enum.TextXAlignment.Left; ht.Parent = hd
	local hx = Instance.new("TextButton"); hx.Size = UDim2.new(0, 24, 0, 24); hx.Position = UDim2.new(1, -26, 0, 2)
	hx.BackgroundColor3 = Color3.fromRGB(80, 30, 30); hx.TextColor3 = Color3.fromRGB(255, 130, 130); hx.Font = Enum.Font.Code
	hx.TextSize = 14; hx.Text = "X"; hx.Parent = hd
	hx.MouseButton1Click:Connect(function() popup:Destroy() end)

	-- Branch selector label
	local blLbl = Instance.new("TextLabel"); blLbl.Size = UDim2.new(1, -16, 0, 14); blLbl.Position = UDim2.new(0, 8, 0, 34)
	blLbl.BackgroundTransparency = 1; blLbl.TextColor3 = Color3.fromRGB(150, 150, 160); blLbl.Font = Enum.Font.GothamBold
	blLbl.TextSize = 9; blLbl.Text = "FROM BRANCH:"; blLbl.TextXAlignment = Enum.TextXAlignment.Left; blLbl.Parent = popup

	local selBranch = branchNames[1]
	local selBtn = Instance.new("TextButton"); selBtn.Size = UDim2.new(1, -16, 0, 22); selBtn.Position = UDim2.new(0, 8, 0, 48)
	selBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 50); selBtn.TextColor3 = Color3.fromRGB(240, 240, 250)
	selBtn.Font = Enum.Font.Code; selBtn.TextSize = 11; selBtn.Text = selBranch; selBtn.Parent = popup

	-- Branch dropdown
	local ddOpen = false
	local ddFrame = Instance.new("Frame"); ddFrame.Size = UDim2.new(1, -16, 0, #branchNames * 22)
	ddFrame.Position = UDim2.new(0, 8, 0, 70); ddFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
	ddFrame.BorderSizePixel = 1; ddFrame.BorderColor3 = Color3.fromRGB(60, 60, 70); ddFrame.ZIndex = 401
	ddFrame.Visible = false; ddFrame.Parent = popup
	local ddLayout = Instance.new("UIListLayout"); ddLayout.Parent = ddFrame
	for _, bn in ipairs(branchNames) do
		local ddb = Instance.new("TextButton"); ddb.Size = UDim2.new(1, 0, 0, 22)
		ddb.BackgroundColor3 = Color3.fromRGB(40, 40, 48); ddb.TextColor3 = Color3.fromRGB(220, 220, 240)
		ddb.Font = Enum.Font.Code; ddb.TextSize = 11; ddb.Text = bn; ddb.Parent = ddFrame
		ddb.MouseButton1Click:Connect(function()
			selBranch = bn; selBtn.Text = bn; ddFrame.Visible = false; ddOpen = false
		end)
	end
	selBtn.MouseButton1Click:Connect(function()
		ddOpen = not ddOpen; ddFrame.Visible = ddOpen
	end)

	-- Script list
	local slLbl = Instance.new("TextLabel"); slLbl.Size = UDim2.new(1, -16, 0, 14); slLbl.Position = UDim2.new(0, 8, 0, 74)
	slLbl.BackgroundTransparency = 1; slLbl.TextColor3 = Color3.fromRGB(150, 150, 160); slLbl.Font = Enum.Font.GothamBold
	slLbl.TextSize = 9; slLbl.Text = "SCRIPTS:"; slLbl.TextXAlignment = Enum.TextXAlignment.Left; slLbl.Parent = popup

	local scriptList = Instance.new("ScrollingFrame"); scriptList.Size = UDim2.new(1, -16, 0, 280)
	scriptList.Position = UDim2.new(0, 8, 0, 90); scriptList.BackgroundTransparency = 1
	scriptList.ScrollBarThickness = 4; scriptList.CanvasSize = UDim2.new(0, 0, 0, 0); scriptList.Parent = popup
	local sll = Instance.new("UIListLayout"); sll.SortOrder = Enum.SortOrder.LayoutOrder; sll.Padding = UDim.new(0, 1); sll.Parent = scriptList

	local function loadScripts(branchName)
		for _, c in ipairs(scriptList:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end
		local r = RPC:send("read_branch", {place = state.place, branch = branchName})
		if not r.success or not r.files then return end
		local paths = {}
		for k in pairs(r.files) do table.insert(paths, k) end
		table.sort(paths)
		for _, p in ipairs(paths) do
			local sb = Instance.new("TextButton"); sb.Size = UDim2.new(1, 0, 0, 20)
			sb.BackgroundTransparency = 1; sb.TextColor3 = Color3.fromRGB(180, 200, 220)
			sb.Font = Enum.Font.Code; sb.TextSize = 10; sb.TextXAlignment = Enum.TextXAlignment.Left
			sb.Text = "  " .. p; sb.Parent = scriptList
			sb.MouseButton1Click:Connect(function()
				-- Cherry-pick this script
				local cp = RPC:send("cherry_pick", {place = state.place, path = p, source_branch = branchName})
				if cp.success then
					-- Inject single script (no clear)
					local svcName = p:match("^([^/]+)")
					if svcName then
						local svc = game:GetService(svcName)
						if svc then
							local parts = {}
							for seg in (p:sub(#svcName + 2)):gmatch("[^/]+") do table.insert(parts, seg) end
							local cur = svc
							for i = 1, #parts - 1 do
								local f = cur:FindFirstChild(parts[i])
								if not f then f = Instance.new("Folder"); f.Name = parts[i]; f.Parent = cur end
								cur = f
							end
							if #parts > 0 then
								local sname = scriptNameFromFilename(parts[#parts])
								local existing = cur:FindFirstChild(sname)
								local classType = cp.class or "Script"
								if not existing then
									if classType == "LocalScript" then existing = Instance.new("LocalScript")
									elseif classType == "ModuleScript" then existing = Instance.new("ModuleScript")
									else existing = Instance.new("Script")
									end
									existing.Name = sname; existing.Parent = cur
								end
								existing.Source = cp.source
								if cp.uid and cp.uid ~= "" then
									existing:SetAttribute("Comitter_uid", cp.uid)
								end
								state.dirty = true
								log("✓ Cherry-picked " .. p .. " from " .. branchName)
							end
						end
					end
					state.staged = scanScripts()
					GUI:setFiles(stagedList())
					popup:Destroy()
				else
					log("✗ Cherry-pick: " .. (cp.error or "failed"))
				end
			end)
		end
		scriptList.CanvasSize = UDim2.new(0, 0, 0, #paths * 21 + 2)
	end

	-- Load initial
	loadScripts(selBranch)

	log("Cherry-pick: select a branch and script")
end

GUI.OnHistory = function()
	local sg = GUI.widget and GUI.widget.Parent
	if not sg then return end

	local histBranch = state.branch
	local histPopup, histList, branchBtn

	local function refreshHistory()
		local r = RPC:send("commits", {place = state.place, branch = histBranch, max = 30})
		if not r.success then return end
		if not histList then return end
		for _, c in ipairs(histList:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end
		if not r.commits or #r.commits == 0 then
			local e = Instance.new("TextLabel"); e.Size = UDim2.new(1, -8, 0, 20)
			e.BackgroundTransparency = 1; e.TextColor3 = Color3.fromRGB(150, 150, 160)
			e.Font = Enum.Font.Gotham; e.TextSize = 12; e.Text = "No commits yet"; e.Parent = histList
			return
		end
		for _, c in ipairs(r.commits) do
			local row = Instance.new("Frame"); row.Size = UDim2.new(1, 0, 0, 48)
			row.BackgroundColor3 = Color3.fromRGB(35, 35, 40); row.Parent = histList
			local hashL = Instance.new("TextLabel"); hashL.Size = UDim2.new(0, 70, 0, 14); hashL.Position = UDim2.new(0, 4, 0, 2)
			hashL.BackgroundTransparency = 1; hashL.TextColor3 = Color3.fromRGB(100, 180, 255); hashL.Font = Enum.Font.Code
			hashL.TextSize = 10; hashL.Text = c.shortHash or c.hash:sub(1, 7); hashL.TextXAlignment = Enum.TextXAlignment.Left; hashL.Parent = row
			local dateL = Instance.new("TextLabel"); dateL.Size = UDim2.new(1, -80, 0, 12); dateL.Position = UDim2.new(0, 76, 0, 2)
			dateL.BackgroundTransparency = 1; dateL.TextColor3 = Color3.fromRGB(130, 130, 140); dateL.Font = Enum.Font.Gotham
			dateL.TextSize = 9; dateL.Text = (c.date or ""):sub(1, 19); dateL.TextXAlignment = Enum.TextXAlignment.Left; dateL.Parent = row
			local msgL = Instance.new("TextLabel"); msgL.Size = UDim2.new(1, -8, 0, 14); msgL.Position = UDim2.new(0, 4, 0, 18)
			msgL.BackgroundTransparency = 1; msgL.TextColor3 = Color3.fromRGB(220, 220, 230); msgL.Font = Enum.Font.GothamSemibold
			msgL.TextSize = 11; msgL.Text = c.message or ""; msgL.TextXAlignment = Enum.TextXAlignment.Left; msgL.Parent = row
			local authorL = Instance.new("TextLabel"); authorL.Size = UDim2.new(1, -8, 0, 12); authorL.Position = UDim2.new(0, 4, 0, 32)
			authorL.BackgroundTransparency = 1; authorL.TextColor3 = Color3.fromRGB(140, 140, 150); authorL.Font = Enum.Font.Gotham
			authorL.TextSize = 9; authorL.Text = c.author or ""; authorL.TextXAlignment = Enum.TextXAlignment.Left; authorL.Parent = row
		end
		histList.CanvasSize = UDim2.new(0, 0, 0, #r.commits * 50 + 4)
	end

	-- Build popup
	-- Destroy existing history popup if any
	local existingHist = sg:FindFirstChild("HistoryPopup")
	if existingHist then existingHist:Destroy() end
	histPopup = Instance.new("Frame"); histPopup.Name = "HistoryPopup"; histPopup.Size = UDim2.new(0, 420, 0, 400)
	histPopup.Position = UDim2.new(0.5, -210, 0.5, -200)
	histPopup.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
	histPopup.BorderSizePixel = 1; histPopup.BorderColor3 = Color3.fromRGB(60, 60, 70)
	histPopup.ZIndex = 400; histPopup.Parent = sg

	local hd = Instance.new("Frame"); hd.Size = UDim2.new(1, 0, 0, 28)
	hd.BackgroundColor3 = Color3.fromRGB(40, 40, 48); hd.Parent = histPopup
	branchBtn = Instance.new("TextButton"); branchBtn.Size = UDim2.new(0, 120, 1, 0); branchBtn.Position = UDim2.new(0, 8, 0, 0)
	branchBtn.BackgroundTransparency = 1; branchBtn.TextColor3 = Color3.fromRGB(220, 220, 240); branchBtn.Font = Enum.Font.GothamBold
	branchBtn.TextSize = 13; branchBtn.TextXAlignment = Enum.TextXAlignment.Left; branchBtn.Text = histBranch; branchBtn.Parent = hd
	local hx = Instance.new("TextButton"); hx.Size = UDim2.new(0, 24, 0, 24); hx.Position = UDim2.new(1, -26, 0, 2)
	hx.BackgroundColor3 = Color3.fromRGB(80, 30, 30); hx.TextColor3 = Color3.fromRGB(255, 130, 130); hx.Font = Enum.Font.Code
	hx.TextSize = 14; hx.Text = "X"; hx.Parent = hd
	hx.MouseButton1Click:Connect(function() histPopup:Destroy() end)

	histList = Instance.new("ScrollingFrame"); histList.Size = UDim2.new(1, -8, 1, -32); histList.Position = UDim2.new(0, 4, 0, 30)
	histList.BackgroundTransparency = 1; histList.ScrollBarThickness = 4; histList.CanvasSize = UDim2.new(0, 0, 0, 0); histList.Parent = histPopup
	local ll = Instance.new("UIListLayout"); ll.SortOrder = Enum.SortOrder.LayoutOrder; ll.Padding = UDim.new(0, 2); ll.Parent = histList

	-- Branch dropdown
	local ddFrame = Instance.new("Frame"); ddFrame.Size = UDim2.new(0, 120, 0, (#state.branches) * 22)
	ddFrame.Position = UDim2.new(0, 8, 0, 28); ddFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
	ddFrame.BorderSizePixel = 1; ddFrame.BorderColor3 = Color3.fromRGB(60, 60, 70); ddFrame.ZIndex = 401
	ddFrame.Visible = false; ddFrame.Parent = histPopup
	for _, b in ipairs(state.branches) do
		local ddb = Instance.new("TextButton"); ddb.Size = UDim2.new(1, 0, 0, 22)
		ddb.BackgroundColor3 = Color3.fromRGB(40, 40, 48); ddb.TextColor3 = Color3.fromRGB(220, 220, 240)
		ddb.Font = Enum.Font.Code; ddb.TextSize = 11; ddb.Text = b.name; ddb.Parent = ddFrame
		ddb.MouseButton1Click:Connect(function()
			histBranch = b.name; branchBtn.Text = b.name; ddFrame.Visible = false
			refreshHistory()
		end)
	end
	branchBtn.MouseButton1Click:Connect(function()
		ddFrame.Visible = not ddFrame.Visible
	end)

	refreshHistory()
end

GUI.loadConfig = function() return state.config end

-- ===== INIT =====
GUI:init()
task.wait(0.3)

state.place = GUI:getName()
state.online = RPC:ping()
GUI:setStatus(state.online and "● Online · " .. state.branch or "○ Offline", state.online)

if state.online then
	loadConfig()
	local gameId = tostring(game.GameId)
	if gameId == "0" then gameId = tostring(game.PlaceId) end
	if gameId == "0" then gameId = "" end

	local hasPicker = false
	local plr = RPC:send("list_places", {game_id = gameId})
	if plr.success and plr.places and #plr.places > 0 then
		local sg = GUI.widget and GUI.widget.Parent
		if sg then
			hasPicker = true
			local showAll = false
			local picker = Instance.new("Frame")
			picker.Size = UDim2.new(0, 320, 0, math.min(#plr.places * 32 + 60, 380))
			picker.Position = UDim2.new(0.5, -160, 0.5, -120)
			picker.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
			picker.BorderSizePixel = 1; picker.BorderColor3 = Color3.fromRGB(60, 60, 70)
			picker.ZIndex = 400; picker.Parent = sg

			local hd = Instance.new("Frame"); hd.Size = UDim2.new(1, 0, 0, 28)
			hd.BackgroundColor3 = Color3.fromRGB(40, 40, 48); hd.Parent = picker
			local ht = Instance.new("TextLabel"); ht.Size = UDim2.new(1, -30, 1, 0); ht.Position = UDim2.new(0, 8, 0, 0)
			ht.BackgroundTransparency = 1; ht.TextColor3 = Color3.fromRGB(220, 220, 240); ht.Font = Enum.Font.GothamBold
			ht.TextSize = 13; ht.Text = "Select Place"; ht.TextXAlignment = Enum.TextXAlignment.Left; ht.Parent = hd

			-- Unlock toggle button
			local unlockBtn = Instance.new("TextButton")
			unlockBtn.Size = UDim2.new(0, 60, 0, 20); unlockBtn.Position = UDim2.new(1, -64, 0, 4)
			unlockBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 52); unlockBtn.TextColor3 = Color3.fromRGB(180, 180, 200)
			unlockBtn.Font = Enum.Font.GothamBold; unlockBtn.TextSize = 10; unlockBtn.Text = "🔓 Show all"
			unlockBtn.BorderSizePixel = 0; unlockBtn.Parent = hd

			local listFrame = Instance.new("ScrollingFrame")
			listFrame.Size = UDim2.new(1, -8, 1, -32); listFrame.Position = UDim2.new(0, 4, 0, 30)
			listFrame.BackgroundTransparency = 1; listFrame.ScrollBarThickness = 4
			listFrame.CanvasSize = UDim2.new(0, 0, 0, 0); listFrame.Parent = picker
			local listLayout = Instance.new("UIListLayout"); listLayout.Padding = UDim.new(0, 2); listLayout.Parent = listFrame

			local function refreshList()
				for _, c in ipairs(listFrame:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end
				local y = 0
				for _, p in ipairs(plr.places) do
					if not showAll and p.has_bind and not p.bound then
						-- Skip unbound repos unless showAll is on
					else
						local btn = Instance.new("TextButton")
						btn.Size = UDim2.new(1, -4, 0, 28); btn.BorderSizePixel = 0
						btn.AutoButtonColor = false
						if p.has_bind and not p.bound then
							btn.BackgroundColor3 = Color3.fromRGB(55, 40, 30)
							btn.TextColor3 = Color3.fromRGB(255, 180, 120)
							btn.Text = "⚠ " .. p.name .. " (diferente)"
						else
							btn.BackgroundColor3 = Color3.fromRGB(45, 45, 52)
							btn.TextColor3 = Color3.fromRGB(220, 220, 240)
							btn.Text = (p.has_bind and "🔒 " or "  ") .. p.name
						end
						btn.Font = Enum.Font.GothamBold; btn.TextSize = 12
						btn.TextXAlignment = Enum.TextXAlignment.Left; btn.Parent = listFrame
						btn.MouseButton1Click:Connect(function()
							if p.has_bind and not p.bound then
								-- Show confirmation popup before loading unbound repo
								local confirm = Instance.new("Frame")
								confirm.Size = UDim2.new(0, 280, 0, 90); confirm.Position = UDim2.new(0.5, -140, 0.5, -45)
								confirm.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
								confirm.BorderSizePixel = 0; confirm.ZIndex = 500
								confirm.Parent = sg
								local cText = Instance.new("TextLabel")
								cText.Size = UDim2.new(1, -16, 0, 24); cText.Position = UDim2.new(0, 8, 0, 8)
								cText.BackgroundTransparency = 1; cText.TextColor3 = Color3.fromRGB(220, 220, 230)
								cText.Font = Enum.Font.GothamBold; cText.TextSize = 12
								cText.Text = "This repo is from another place.\nLoad anyway?"; cText.Parent = confirm

								local yesBtn = Instance.new("TextButton")
								yesBtn.Size = UDim2.new(0.5, -4, 0, 26); yesBtn.Position = UDim2.new(0, 4, 0, 50)
								yesBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 212)
								yesBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
								yesBtn.Font = Enum.Font.GothamBold; yesBtn.TextSize = 12; yesBtn.Text = "Load"
								yesBtn.BorderSizePixel = 0; yesBtn.Parent = confirm
								yesBtn.MouseButton1Click:Connect(function()
									confirm:Destroy(); picker:Destroy()
									state.place = p.name; GUI:setName(p.name)
									loadBranches(); state.staged = scanScripts(); refreshUI()
									log("Loaded place: " .. p.name)
								end)

								local noBtn = Instance.new("TextButton")
								noBtn.Size = UDim2.new(0.5, -4, 0, 26); noBtn.Position = UDim2.new(0.5, 0, 0, 50)
								noBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 65)
								noBtn.TextColor3 = Color3.fromRGB(200, 200, 210)
								noBtn.Font = Enum.Font.GothamBold; noBtn.TextSize = 12; noBtn.Text = "Cancel"
								noBtn.BorderSizePixel = 0; noBtn.Parent = confirm
								noBtn.MouseButton1Click:Connect(function() confirm:Destroy() end)
							else
								picker:Destroy()
								state.place = p.name; GUI:setName(p.name)
								loadBranches(); state.staged = scanScripts(); refreshUI()
								log("Loaded place: " .. p.name)
							end
						end)
						y = y + 30
					end
				end
				listFrame.CanvasSize = UDim2.new(0, 0, 0, y + 4)
			end

			unlockBtn.MouseButton1Click:Connect(function()
				showAll = not showAll
				unlockBtn.Text = showAll and "🔒 Filter" or "🔓 Show all"
				refreshList()
			end)

			refreshList()
		end
	end
	if not hasPicker then
		loadBranches()
		state.staged = scanScripts()
		refreshUI()
	end
	log("Comitter v0.7.0 ready")
else
	log("Comitter v0.7.0 — Offline. Rode o daemon: fuser -k 3017/tcp; cd ~/Documentos/Comitter && python3 daemon/server.py &")
end