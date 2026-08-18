-- Comitter
local HttpService = game:GetService("HttpService")

-- Config
-- Config.lua — Constantes do Comitter
local Config = {}

Config.PROXY_URL = "http://127.0.0.1:3016"
Config.PLUGIN_NAME = "Comitter"
Config.PLUGIN_VERSION = "1.5.0"
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
	local data = HttpService:JSONDecode(resp)
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
-- GUI.lua — Comitter (design GitHub Desktop: toolbar, 2 painéis, terminal, status bar)
local GUI = {}
GUI.widget = nil
GUI.OnCommit = nil; GUI.OnPush = nil; GUI.OnPull = nil
GUI.OnBranchSelect = nil; GUI.OnCreateBranch = nil; GUI.OnCommand = nil
GUI.OnConfigSave = nil; GUI.loadConfig = nil
GUI.OnBranchDelete = nil; GUI.OnBranchRename = nil
GUI.OnCherryPick = nil
GUI.OnHistory = nil
GUI.OnScanConfig = nil

local termIn, branchList, statusLabel, statusDot, fileList, diffView, nameBox, msgBox, newBranchForm
local guiScreen

-- ===== PALETA — neutra, um accent só (espelho do comitter_gui.py) =====
local C = {
	bg = Color3.fromRGB(30, 30, 31),
	header = Color3.fromRGB(36, 36, 38),
	sidebarBg = Color3.fromRGB(32, 32, 34),
	panel = Color3.fromRGB(28, 28, 30),
	border = Color3.fromRGB(58, 58, 61),
	input = Color3.fromRGB(42, 42, 44),
	accent = Color3.fromRGB(47, 111, 165),
	accentHover = Color3.fromRGB(58, 125, 181),
	text = Color3.fromRGB(201, 201, 204),
	textDim = Color3.fromRGB(135, 135, 141),
	textBright = Color3.fromRGB(242, 242, 244),
	selectBg = Color3.fromRGB(18, 58, 92),
	diffBg = Color3.fromRGB(26, 26, 28),
	diffAddFg = Color3.fromRGB(143, 209, 143),
	diffAddBg = Color3.fromRGB(18, 32, 22),
	diffDelFg = Color3.fromRGB(242, 166, 166),
	diffDelBg = Color3.fromRGB(36, 20, 20),
	diffHunkFg = Color3.fromRGB(108, 182, 242),
	statusM = Color3.fromRGB(215, 186, 125),
	statusA = Color3.fromRGB(108, 182, 242),
	statusD = Color3.fromRGB(241, 76, 76),
	statusS = Color3.fromRGB(137, 209, 133),
	statusQ = Color3.fromRGB(135, 135, 141),
	online = Color3.fromRGB(108, 194, 108),
	offline = Color3.fromRGB(224, 96, 96),
}
local F = {
	h = Enum.Font.GothamBold,
	b = Enum.Font.GothamMedium,
	m = Enum.Font.Code,
}

local function rnd(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 4)
	c.Parent = inst
end

local function stroke(inst, c, t)
	local s = Instance.new("UIStroke")
	s.Color = c or C.border
	s.Thickness = t or 1
	s.Parent = inst
end

local function addHover(b, normal, over)
	b.MouseEnter:Connect(function() b.BackgroundColor3 = over end)
	b.MouseLeave:Connect(function() b.BackgroundColor3 = normal end)
end

local function eyebrow(text)
	return text:gsub("(.)", "%1 ")
end

local function vline(parent)
	local f = Instance.new("Frame")
	f.Size = UDim2.new(0, 1, 1, 0)
	f.BackgroundColor3 = C.border
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local function hline(parent)
	local f = Instance.new("Frame")
	f.Size = UDim2.new(1, 0, 0, 1)
	f.BackgroundColor3 = C.border
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

-- Botão flat estilo GitHub Desktop (kind: primary/default/ghost/danger)
local function flatBtn(parent, text, kind, cb, w, hgt)
	local kinds = {
		primary = {C.accent, C.accentHover, Color3.fromRGB(255, 255, 255)},
		default = {Color3.fromRGB(44, 44, 46), Color3.fromRGB(55, 55, 58), C.text},
		ghost = {C.header, Color3.fromRGB(47, 47, 49), C.textDim},
		danger = {Color3.fromRGB(58, 31, 34), Color3.fromRGB(74, 36, 41), Color3.fromRGB(255, 156, 156)},
	}
	local k = kinds[kind] or kinds.default
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, w or 90, 0, hgt or 24)
	b.BackgroundColor3 = k[1]
	b.TextColor3 = k[3]
	b.Font = F.b
	b.TextSize = 11
	b.Text = text
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	rnd(b, 4)
	b.Parent = parent
	addHover(b, k[1], k[2])
	if cb then
		b.MouseButton1Click:Connect(function() cb() end)
	end
	return b
end

function GUI:init()
	local sg = Instance.new("ScreenGui"); sg.Name = "Comitter"; sg.Parent = game:GetService("CoreGui")
	sg.ResetOnSpawn = false; sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	guiScreen = sg

	local main = Instance.new("Frame")
	main.Size = UDim2.new(0, 680, 0, 460)
	main.Position = UDim2.new(0.5, -340, 0.5, -230)
	main.BackgroundColor3 = C.bg
	main.BorderSizePixel = 0
	stroke(main, Color3.fromRGB(45, 45, 48), 1)
	main.Parent = sg

	-- ===== TOOLBAR (28px, estilo GitHub Desktop) =====
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 0, 28)
	bar.BackgroundColor3 = C.header
	bar.BorderSizePixel = 0
	bar.Parent = main

	local left = Instance.new("Frame")
	left.Size = UDim2.new(0, 180, 1, 0)
	left.BackgroundColor3 = C.header
	left.BorderSizePixel = 0
	left.Parent = bar

	local projLbl = Instance.new("TextLabel")
	projLbl.Size = UDim2.new(0, 46, 1, 0); projLbl.Position = UDim2.new(0, 8, 0, 0)
	projLbl.BackgroundTransparency = 1; projLbl.TextColor3 = C.textDim; projLbl.Font = F.b
	projLbl.TextSize = 9; projLbl.Text = "Project"; projLbl.TextXAlignment = Enum.TextXAlignment.Left
	projLbl.Parent = left

	nameBox = Instance.new("TextBox")
	nameBox.Size = UDim2.new(0, 110, 0, 20); nameBox.Position = UDim2.new(0, 56, 0, 4)
	nameBox.BackgroundColor3 = C.input; nameBox.TextColor3 = C.textBright
	nameBox.PlaceholderColor3 = C.textDim; nameBox.PlaceholderText = "place"
	nameBox.Font = F.m; nameBox.TextSize = 11; nameBox.Text = "MeuJogo"
	nameBox.BorderSizePixel = 0; rnd(nameBox, 3)
	nameBox.Parent = left

	local right = Instance.new("Frame")
	right.Size = UDim2.new(1, -180, 1, 0); right.Position = UDim2.new(0, 180, 0, 0)
	right.BackgroundColor3 = C.header
	right.BorderSizePixel = 0
	right.Parent = bar

	local settingsBtn = flatBtn(right, "⚙", "ghost", function()
		if GUI.OnConfigSave then GUI.OnConfigSave() end
	end, 24, 20)
	settingsBtn.Position = UDim2.new(1, -28, 0, 4)
	settingsBtn.TextSize = 12

	local scanBtn = flatBtn(right, "↻", "ghost", function()
		if GUI.OnScanConfig then GUI.OnScanConfig() end
	end, 24, 20)
	scanBtn.Position = UDim2.new(1, -56, 0, 4)
	scanBtn.TextSize = 12

	local f2 = Instance.new("Frame")
	f2.Size = UDim2.new(0, 240, 1, 0); f2.Position = UDim2.new(1, -250, 0, 0)
	f2.BackgroundColor3 = C.header
	f2.BorderSizePixel = 0
	f2.Parent = right
	local vl = vline(f2)
	vl.Position = UDim2.new(0, 0, 0, 4)

	local histBtn = flatBtn(f2, "History", "ghost", function()
		if GUI.OnHistory then GUI.OnHistory() end
	end, 60, 20)
	histBtn.Position = UDim2.new(0, 6, 0, 4)
	local pushBtn = flatBtn(f2, "Push", "default", function()
		if GUI.OnPush then GUI.OnPush() end
	end, 46, 20)
	pushBtn.Position = UDim2.new(0, 70, 0, 4)
	local pullBtn = flatBtn(f2, "Pull", "default", function()
		if GUI.OnPull then GUI.OnPull() end
	end, 46, 20)
	pullBtn.Position = UDim2.new(0, 120, 0, 4)

	hline(main)

	-- ===== MAIN (2 painéis: left | diff) =====
	local body = Instance.new("Frame")
	body.Size = UDim2.new(1, 0, 1, -28)
	body.Position = UDim2.new(0, 0, 0, 28)
	body.BackgroundColor3 = C.bg
	body.Parent = main

	-- LEFT COLUMN (280px fixo)
	local leftCol = Instance.new("Frame")
	leftCol.Size = UDim2.new(0, 280, 1, 0)
	leftCol.BackgroundColor3 = C.bg
	leftCol.BorderSizePixel = 0
	leftCol.Parent = body

	-- --- staged changes ---
	local head = Instance.new("Frame")
	head.Size = UDim2.new(1, -16, 0, 20); head.Position = UDim2.new(0, 8, 0, 6)
	head.BackgroundColor3 = C.bg; head.BorderSizePixel = 0
	head.Parent = leftCol

	local stagedLbl = Instance.new("TextLabel")
	stagedLbl.Size = UDim2.new(0, 140, 1, 0)
	stagedLbl.BackgroundTransparency = 1; stagedLbl.TextColor3 = C.textDim; stagedLbl.Font = F.h
	stagedLbl.TextSize = 9; stagedLbl.Text = eyebrow("STAGED CHANGES")
	stagedLbl.TextXAlignment = Enum.TextXAlignment.Left; stagedLbl.Parent = head

	local cpBtn = flatBtn(head, "Cherry-pick", "ghost", function()
		if GUI.OnCherryPick then GUI.OnCherryPick() end
	end, 70, 16)
	cpBtn.Position = UDim2.new(1, -74, 0, 2)
	cpBtn.TextSize = 9

	local treeFrame = Instance.new("Frame")
	treeFrame.Size = UDim2.new(1, -12, 0, 96); treeFrame.Position = UDim2.new(0, 6, 0, 28)
	treeFrame.BackgroundColor3 = C.panel
	treeFrame.BorderSizePixel = 0
	treeFrame.Parent = leftCol

	fileList = Instance.new("ScrollingFrame")
	fileList.Size = UDim2.new(1, 0, 1, 0)
	fileList.BackgroundTransparency = 1
	fileList.ScrollBarThickness = 4
	fileList.CanvasSize = UDim2.new(0, 0, 0, 0)
	fileList.BorderSizePixel = 0
	fileList.Parent = treeFrame
	local fll = Instance.new("UIListLayout"); fll.Padding = UDim.new(0, 1); fll.Parent = fileList

	-- --- commit message ---
	local msgLbl = Instance.new("TextLabel")
	msgLbl.Size = UDim2.new(1, -16, 0, 14); msgLbl.Position = UDim2.new(0, 8, 0, 128)
	msgLbl.BackgroundTransparency = 1; msgLbl.TextColor3 = C.textDim; msgLbl.Font = F.h
	msgLbl.TextSize = 9; msgLbl.Text = eyebrow("COMMIT MESSAGE")
	msgLbl.TextXAlignment = Enum.TextXAlignment.Left; msgLbl.Parent = leftCol

	msgBox = Instance.new("TextBox")
	msgBox.Size = UDim2.new(1, -12, 0, 46); msgBox.Position = UDim2.new(0, 6, 0, 144)
	msgBox.BackgroundColor3 = C.input; msgBox.TextColor3 = C.textBright
	msgBox.PlaceholderColor3 = C.textDim; msgBox.PlaceholderText = "Describe what changed..."
	msgBox.Font = F.m; msgBox.TextSize = 11; msgBox.Text = ""
	msgBox.TextWrapped = true; msgBox.TextYAlignment = Enum.TextYAlignment.Top
	msgBox.BorderSizePixel = 0; rnd(msgBox, 4)
	msgBox.Parent = leftCol

	local commitBtn = flatBtn(leftCol, "Commit changes", "primary", function()
		if GUI.OnCommit then GUI.OnCommit() end
	end, 260, 26)
	commitBtn.Position = UDim2.new(0, 6, 0, 194)
	commitBtn.TextSize = 11

	hline(leftCol)
	local branchHdr = Instance.new("Frame")
	branchHdr.Size = UDim2.new(1, -16, 0, 20); branchHdr.Position = UDim2.new(0, 8, 0, 224)
	branchHdr.BackgroundColor3 = C.bg; branchHdr.BorderSizePixel = 0
	branchHdr.Parent = leftCol

	local branchLbl = Instance.new("TextLabel")
	branchLbl.Size = UDim2.new(0, 100, 1, 0)
	branchLbl.BackgroundTransparency = 1; branchLbl.TextColor3 = C.textDim; branchLbl.Font = F.h
	branchLbl.TextSize = 9; branchLbl.Text = eyebrow("BRANCHES")
	branchLbl.TextXAlignment = Enum.TextXAlignment.Left; branchLbl.Parent = branchHdr

	local newBranchBtn = flatBtn(branchHdr, "+", "ghost", function()
		newBranchForm.Visible = not newBranchForm.Visible
	end, 20, 16)
	newBranchBtn.Position = UDim2.new(1, -24, 0, 2)

	-- New branch form (oculto, toggle pelo +)
	newBranchForm = Instance.new("Frame")
	newBranchForm.Size = UDim2.new(1, -16, 0, 64); newBranchForm.Position = UDim2.new(0, 8, 0, 246)
	newBranchForm.BackgroundColor3 = C.bg; newBranchForm.BorderSizePixel = 0
	newBranchForm.Visible = false
	newBranchForm.Parent = leftCol

	local nbLbl = Instance.new("TextLabel")
	nbLbl.Size = UDim2.new(1, 0, 0, 12)
	nbLbl.BackgroundTransparency = 1; nbLbl.TextColor3 = C.textDim; nbLbl.Font = F.h
	nbLbl.TextSize = 9; nbLbl.Text = eyebrow("NEW BRANCH")
	nbLbl.TextXAlignment = Enum.TextXAlignment.Left; nbLbl.Parent = newBranchForm

	local newName = Instance.new("TextBox")
	newName.Size = UDim2.new(1, 0, 0, 18); newName.Position = UDim2.new(0, 0, 0, 14)
	newName.BackgroundColor3 = C.input; newName.TextColor3 = C.textBright
	newName.PlaceholderColor3 = C.textDim; newName.PlaceholderText = "2.0-name"
	newName.Font = F.m; newName.TextSize = 10; newName.Text = ""
	newName.BorderSizePixel = 0; rnd(newName, 3)
	newName.Parent = newBranchForm

	local createBtn = flatBtn(newBranchForm, "Create branch", "primary", function()
		local name = newName.Text:match("^%s*(.-)%s*$")
		if name ~= "" and GUI.OnCreateBranch then
			GUI.OnCreateBranch(name)
			newName.Text = ""
			newBranchForm.Visible = false
		end
	end, 130, 20)
	createBtn.Position = UDim2.new(0, 0, 0, 36)
	createBtn.TextSize = 10

	-- Branch list (ocupa o resto)
	local branchFrame = Instance.new("Frame")
	branchFrame.Size = UDim2.new(1, -12, 1, -252); branchFrame.Position = UDim2.new(0, 6, 0, 246)
	branchFrame.BackgroundColor3 = C.panel
	branchFrame.BorderSizePixel = 0
	branchFrame.Parent = leftCol

	branchList = Instance.new("ScrollingFrame")
	branchList.Size = UDim2.new(1, 0, 1, 0)
	branchList.BackgroundTransparency = 1
	branchList.ScrollBarThickness = 4
	branchList.CanvasSize = UDim2.new(0, 0, 0, 0)
	branchList.BorderSizePixel = 0
	branchList.Parent = branchFrame
	local bll = Instance.new("UIListLayout"); bll.Padding = UDim.new(0, 2); bll.Parent = branchList

	local sep = vline(body)
	sep.Position = UDim2.new(0, 280, 0, 0)

	-- ===== DIFF PANE =====
	local diffPane = Instance.new("Frame")
	diffPane.Size = UDim2.new(1, -281, 1, 0); diffPane.Position = UDim2.new(0, 281, 0, 0)
	diffPane.BackgroundColor3 = C.bg
	diffPane.BorderSizePixel = 0
	diffPane.Parent = body

	local diffLbl = Instance.new("TextLabel")
	diffLbl.Size = UDim2.new(1, -16, 0, 14); diffLbl.Position = UDim2.new(0, 8, 0, 6)
	diffLbl.BackgroundTransparency = 1; diffLbl.TextColor3 = C.textDim; diffLbl.Font = F.h
	diffLbl.TextSize = 9; diffLbl.Text = eyebrow("DIFF")
	diffLbl.TextXAlignment = Enum.TextXAlignment.Left; diffLbl.Parent = diffPane

	local diffOuter = Instance.new("Frame")
	diffOuter.Size = UDim2.new(1, -12, 1, -24); diffOuter.Position = UDim2.new(0, 6, 0, 22)
	diffOuter.BackgroundColor3 = C.diffBg
	diffOuter.BorderSizePixel = 1; diffOuter.BorderColor3 = C.border
	diffOuter.Parent = diffPane

	diffView = Instance.new("ScrollingFrame")
	diffView.Size = UDim2.new(1, 0, 1, 0)
	diffView.BackgroundTransparency = 1
	diffView.ScrollBarThickness = 4
	diffView.CanvasSize = UDim2.new(0, 0, 0, 0)
	diffView.BorderSizePixel = 0
	diffView.Parent = diffOuter
	local dvl = Instance.new("UIListLayout"); dvl.Padding = UDim.new(0, 0); dvl.Parent = diffView

	-- ===== TERMINAL =====
	hline(main)
	local term = Instance.new("Frame")
	term.Size = UDim2.new(1, 0, 0, 26); term.Position = UDim2.new(0, 0, 1, -26)
	term.BackgroundColor3 = C.header
	term.BorderSizePixel = 0
	term.Parent = main

	local prompt = Instance.new("TextLabel")
	prompt.Size = UDim2.new(0, 16, 1, 0); prompt.Position = UDim2.new(0, 8, 0, 0)
	prompt.BackgroundTransparency = 1; prompt.TextColor3 = C.textDim; prompt.Font = F.m
	prompt.TextSize = 12; prompt.Text = "❯"
	prompt.Parent = term

	termIn = Instance.new("TextBox")
	termIn.Size = UDim2.new(1, -30, 0, 20); termIn.Position = UDim2.new(0, 24, 0, 3)
	termIn.BackgroundColor3 = C.header; termIn.TextColor3 = Color3.fromRGB(159, 207, 159)
	termIn.PlaceholderColor3 = C.textDim; termIn.PlaceholderText = "type a command…"
	termIn.Font = F.m; termIn.TextSize = 11; termIn.Text = ""
	termIn.BorderSizePixel = 0
	termIn.Parent = term
	termIn.FocusLost:Connect(function(ep)
		if ep and termIn.Text ~= "" and GUI.OnCommand then
			GUI.OnCommand(termIn.Text); termIn.Text = ""
		end
	end)

	-- ===== STATUS BAR =====
	hline(main)
	local sbar = Instance.new("Frame")
	sbar.Size = UDim2.new(1, 0, 0, 20); sbar.Position = UDim2.new(0, 0, 1, -46)
	sbar.BackgroundColor3 = C.header
	sbar.BorderSizePixel = 0
	sbar.Parent = main

	local dot = Instance.new("Frame")
	dot.Size = UDim2.new(0, 8, 0, 8); dot.Position = UDim2.new(0, 8, 0, 6)
	dot.BackgroundColor3 = C.online
	dot.BorderSizePixel = 0
	rnd(dot, 4)
	dot.Parent = sbar
	statusDot = dot

	statusLabel = Instance.new("TextLabel")
	statusLabel.Size = UDim2.new(1, -40, 1, 0); statusLabel.Position = UDim2.new(0, 20, 0, 0)
	statusLabel.BackgroundTransparency = 1; statusLabel.TextColor3 = C.textDim; statusLabel.Font = F.b
	statusLabel.TextSize = 9; statusLabel.Text = "Online"
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left; statusLabel.Parent = sbar

	-- Minimize toggle (canto direito da status bar)
	local minBtn = Instance.new("TextButton")
	minBtn.Size = UDim2.new(0, 16, 0, 14); minBtn.Position = UDim2.new(1, -20, 0, 3)
	minBtn.BackgroundColor3 = C.header; minBtn.TextColor3 = C.textDim
	minBtn.Font = F.h; minBtn.TextSize = 10; minBtn.Text = "─"
	minBtn.AutoButtonColor = false; minBtn.BorderSizePixel = 0
	minBtn.Parent = sbar

	-- Close button (✕) ao lado do minimize
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 16, 0, 14); closeBtn.Position = UDim2.new(1, -40, 0, 3)
	closeBtn.BackgroundColor3 = C.header; closeBtn.TextColor3 = C.offline
	closeBtn.Font = F.h; closeBtn.TextSize = 10; closeBtn.Text = "✕"
	closeBtn.AutoButtonColor = false; closeBtn.BorderSizePixel = 0
	closeBtn.Parent = sbar

	local toggleBtn = Instance.new("TextButton")
	toggleBtn.Size = UDim2.new(0, 32, 0, 24)
	toggleBtn.Position = UDim2.new(1, -36, 0, 4)
	toggleBtn.BackgroundColor3 = C.header
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

	-- Drag pela toolbar
	local d, ds, sp = false
	bar.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 and i.UserInputState == Enum.UserInputState.Begin then
			d = true; ds = i.Position; sp = main.Position
		end
	end)
	bar.InputChanged:Connect(function(i)
		if d and i.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = i.Position - ds
			main.Position = UDim2.new(sp.X.Scale, sp.X.Offset + delta.X, sp.Y.Scale, sp.Y.Offset + delta.Y)
		end
	end)
	bar.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then d = false end
	end)

	GUI.widget = main
end

-- ===== PUBLIC METHODS =====

function GUI:setStatus(t, on)
	if statusLabel then
		statusLabel.Text = t
		statusLabel.TextColor3 = on and C.textDim or C.offline
	end
	if statusDot then
		statusDot.BackgroundColor3 = on and C.online or C.offline
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
		item.BackgroundColor3 = b.current and Color3.fromRGB(23, 54, 80) or Color3.fromRGB(40, 40, 43)
		item.TextColor3 = b.current and C.textBright or C.text
		item.Font = F.m
		item.TextSize = 10
		item.TextXAlignment = Enum.TextXAlignment.Left
		item.AutoButtonColor = false
		item.BorderSizePixel = 0
		item.Text = (b.current and "✓  " or "    ") .. b.name
		if b.created then
			item.Text = item.Text .. "  " .. (b.created:sub(5, 10) or b.created)
		end
		rnd(item, 4)
		item.Parent = row
		if not b.current then
			addHover(item, Color3.fromRGB(40, 40, 43), Color3.fromRGB(50, 50, 53))
		end
		item.MouseButton1Click:Connect(function()
			if GUI.OnBranchSelect then GUI.OnBranchSelect(b.name) end
		end)

		if hasMenu then
			local menu = Instance.new("TextButton")
			menu.Size = UDim2.new(0, 22, 1, 0)
			menu.Position = UDim2.new(1, -22, 0, 0)
			menu.BackgroundColor3 = Color3.fromRGB(48, 48, 51)
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
		local raw = tostring(f)
		local status = raw:sub(1, 1)
		local path = raw:sub(5)
		local color = C.textDim
		if status == "A" then color = C.statusA
		elseif status == "M" then color = C.statusM
		elseif status == "D" then color = C.statusD
		elseif status == "S" then color = C.statusS end
		local item = Instance.new("TextButton")
		item.Size = UDim2.new(1, -6, 0, 20)
		item.BackgroundTransparency = 1; item.TextColor3 = color
		item.Font = F.m; item.TextSize = 10
		item.TextXAlignment = Enum.TextXAlignment.Left
		item.Text = (status == "S" and "  " or "  " .. status .. " ") .. path
		item.AutoButtonColor = false; item.BorderSizePixel = 0; item.Parent = fileList
	end
	fileList.CanvasSize = UDim2.new(0, 0, 0, #files * 21 + 2)
end

function GUI:setDiff(text)
	if not diffView then return end
	for _, c in ipairs(diffView:GetChildren()) do if c:IsA("TextLabel") then c:Destroy() end end
	if not text or text == "" then return end
	local y = 4
	local function addLine(line, color, bg, size)
		local l = Instance.new("TextLabel")
		l.Size = UDim2.new(1, -4, 0, 15)
		l.Position = UDim2.new(0, 2, 0, y)
		l.BackgroundColor3 = bg or C.diffBg
		l.BorderSizePixel = 0
		l.TextColor3 = color or C.text; l.Font = F.m; l.TextSize = size or 11
		l.TextXAlignment = Enum.TextXAlignment.Left; l.Text = line
		l.Parent = diffView; y = y + 16
	end
	local currentFile = nil
	local shownLines = 0
	local hiddenLines = 0
	for line in text:gmatch("[^\r\n]+") do
		local fileHeader = line:match("^diff %-%-git a/(.+) b/")
		if fileHeader then
			if currentFile and hiddenLines > 0 then
				addLine("  … (" .. hiddenLines .. " mais)", C.textDim, nil, 10)
			end
			currentFile = fileHeader
			shownLines = 0
			hiddenLines = 0
			addLine("▸ " .. fileHeader, C.diffHunkFg, nil, 11)
		elseif currentFile then
			if line:sub(1, 5) == "index" or line:sub(1, 3) == "---" or line:sub(1, 3) == "+++" or line:sub(1, 2) == "@@" then
				-- skip git headers
			elseif line:sub(1, 1) == "+" then
				if shownLines >= 20 then hiddenLines = hiddenLines + 1 else
					addLine("  " .. line, C.diffAddFg, C.diffAddBg, 12)
					shownLines = shownLines + 1
				end
			elseif line:sub(1, 1) == "-" then
				if shownLines >= 20 then hiddenLines = hiddenLines + 1 else
					addLine("  " .. line, C.diffDelFg, C.diffDelBg, 12)
					shownLines = shownLines + 1
				end
			elseif line:sub(1, 1) == " " then
				if shownLines >= 20 then hiddenLines = hiddenLines + 1 else
					addLine("  " .. line, C.textDim, nil, 12)
					shownLines = shownLines + 1
				end
			end
		else
			-- Linha fora de um diff (ex: "Commit: abc1234")
			addLine(line, C.textBright, nil, 12)
		end
	end
	if currentFile and hiddenLines > 0 then
		addLine("  … (" .. hiddenLines .. " mais)", C.textDim, nil, 10)
	end
	diffView.CanvasSize = UDim2.new(0, 0, 0, y + 4)
end

function GUI:termLog(t, c) print("[Comitter] " .. t) end
function GUI:termWrite(t, c) GUI:termLog(t, c) end
function GUI:getName() return nameBox and nameBox.Text or "MeuJogo" end
function GUI:setName(n) if nameBox then nameBox.Text = n end end
function GUI:getMsg() return msgBox and msgBox.Text or "save" end


-- init
-- init.lua — Comitter v1.5.0
-- Ordem CRÍTICA: helpers → callbacks → GUI:init()

-- Serviços escaneáveis
local SCAN_SERVICES = {
	{ name = "ServerScriptService", path = "ServerScriptService" },
	{ name = "ServerStorage", path = "ServerStorage" },
	{ name = "ReplicatedStorage", path = "ReplicatedStorage" },
	{ name = "StarterPlayerScripts", path = "StarterPlayer/StarterPlayerScripts" },
	{ name = "StarterCharacterScripts", path = "StarterPlayer/StarterCharacterScripts" },
	{ name = "StarterGui", path = "StarterGui" },
	{ name = "StarterPack", path = "StarterPack" },
	{ name = "Workspace (tracked)", path = "Workspace" },
}

-- Serviços ativos (default: todos)
local state = { online = false, branch = "main", place = "MeuJogo", branches = {}, staged = {}, config = {}, currentHash = "", dirty = false,
	scanMask = {}, lastPartes = {} }

-- Inicializa scanMask com todos ativos
for _, svc in ipairs(SCAN_SERVICES) do state.scanMask[svc.name] = true end; state.scanMask["Workspace (tracked)"] = false

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
	-- Workspace: only scan Parts/Models with Comitter_track attribute
	local function scanTracked(parent, prefix)
		for _, child in ipairs(parent:GetChildren()) do
			if child:IsA("BasePart") or child:IsA("Model") then
				if child:GetAttribute("Comitter_track") then
					local props = { className = child.ClassName }
					local ok
					-- Global position and orientation
					local cf = child:GetPivot()
					ok, props.position = pcall(function() local p = cf.Position; return {p.X, p.Y, p.Z} end)
					ok, props.orientation = pcall(function() local o = cf:ToOrientation(); return {o.X, o.Y, o.Z} end)
					ok, props.size = pcall(function() local s = child.Size; return {s.X, s.Y, s.Z} end)
					ok, props.anchored = pcall(function() return child.Anchored end)
					ok, props.canCollide = pcall(function() return child.CanCollide end)
					ok, props.transparency = pcall(function() return child.Transparency end)
					ok, props.brickColor = pcall(function() return child.BrickColor.Number end)
					ok, props.material = pcall(function() return child.Material.Name end)
					-- Scan direct LuaSourceContainer children
					for _, sub in ipairs(child:GetChildren()) do
						if sub:IsA("LuaSourceContainer") then
							local rel = prefix .. "/" .. child.Name .. "/" .. sub.Name
							files[rel] = {
								source = sub.Source,
								obj = sub,
								path = rel,
								uid = ensureUID(sub),
								base = getBaseHash(sub),
								class = sub.ClassName,
								parteMeta = props,
							}
							if not sub:GetAttribute("Comitter_dirtyConnected") then
								sub:SetAttribute("Comitter_dirtyConnected", true)
								local ok, sig = pcall(function()
									return sub:GetPropertyChangedSignal("Source")
								end)
								if ok and sig then
									sig:Connect(function() state.dirty = true end)
								end
							end
						end
					end
				end
				-- Always recurse — an untracked parent might contain a tracked child
				scanTracked(child, prefix .. "/" .. child.Name)
			end
		end
	end
	if state.scanMask["Workspace (tracked)"] then
		scanTracked(workspace, "Workspace")
	end
	if state.scanMask["ServerScriptService"] then scan(game:GetService("ServerScriptService"), "ServerScriptService") end
	if state.scanMask["ServerStorage"] then scan(game:GetService("ServerStorage"), "ServerStorage") end
	if state.scanMask["ReplicatedStorage"] then scan(game:GetService("ReplicatedStorage"), "ReplicatedStorage") end
	local sp = game:GetService("StarterPlayer")
	if sp then
		if state.scanMask["StarterPlayerScripts"] then
			local sps = sp:FindFirstChild("StarterPlayerScripts")
			if sps then scan(sps, "StarterPlayer/StarterPlayerScripts") end
		end
		if state.scanMask["StarterCharacterScripts"] then
			local scs = sp:FindFirstChild("StarterCharacterScripts")
			if scs then scan(scs, "StarterPlayer/StarterCharacterScripts") end
		end
	end
	if state.scanMask["StarterGui"] then scan(game:GetService("StarterGui"), "StarterGui") end
	local spk = game:GetService("StarterPack")
	if state.scanMask["StarterPack"] and spk then scan(spk, "StarterPack") end
	return files
end

-- Scripts built-in do Roblox que nunca devem ser versionados
local BUILTIN_SCRIPTS = {
	["Animate"] = true,
	["Health"] = true,
	["Sound"] = true,
	["RbxCharacterSound"] = true,
	["Chat"] = true,
	["ClientChat"] = true,
	["ChatServiceRunner"] = true,
	["BubbleChat"] = true,
	["Emotes"] = true,
	["Camera"] = true,
}

local function isBuiltin(path)
	local name = path:match("/([^/]+)$")
	return name and BUILTIN_SCRIPTS[name]
end

local function stagedList(preScanned)
	-- Lista TODOS os scripts do scan com status: S (salvo), A (novo),
	-- M (modificado), D (deletado — existia no baseline e sumiu do scan).
	local current = preScanned or scanScripts()
	local baseline = state.baseline or {}
	local t = {}
	for k, info in pairs(current) do
		if not isBuiltin(k) then
			local old = baseline[k]
			if not old then
				t[k] = "A  " .. k
			elseif old.source ~= info.source then
				t[k] = "M  " .. k
			else
				t[k] = "S  " .. k
			end
		end
	end
	for k in pairs(baseline) do
		if not isBuiltin(k) and not current[k] then
			t[k] = "D  " .. k
		end
	end
	local list = {}
	for _, v in pairs(t) do table.insert(list, v) end
	table.sort(list)
	return list
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

-- Fingerprint da lista staged (status+path concatenados) pra comparar
-- sem re-renderizar a UI quando nada mudou.
local lastStagedFingerprint = ""

local function autoRefresh()
	while true do
		task.wait(1)
		if not state.online then continue end
		-- Fingerprint inclui o source pra detectar edição de conteúdo
		-- (status M não muda quando o script é editado de novo)
		local ok, cur = pcall(scanScripts)
		if not ok then continue end
		local arr = {}
		for k, info in pairs(cur) do
			if not isBuiltin(k) then
				table.insert(arr, k .. ":" .. info.source)
			end
		end
		table.sort(arr)
		local fp = table.concat(arr, "|")
		if fp ~= lastStagedFingerprint then
			lastStagedFingerprint = fp
			state.staged = cur
			GUI:setFiles(stagedList(cur))
		end
	end
end

local function log(msg, color)
	print("[Comitter] " .. msg)
end

-- ===== INJECT SCRIPTS INTO STUDIO =====
local SCRIPT_SERVICES = {"ServerScriptService", "ServerStorage", "ReplicatedStorage", "StarterGui", "StarterPack"}

local function clearStudioScripts()
	for _, svcName in ipairs(SCRIPT_SERVICES) do
		local svc = game:GetService(svcName)
		if svc then
			for _, child in ipairs(svc:GetChildren()) do
				if child:IsA("LuaSourceContainer") then
					child:Destroy()
				end
			end
		end
	end
	-- Clear StarterPlayer sub-services
	local sp = game:GetService("StarterPlayer")
	if sp then
		for _, subName in ipairs({"StarterPlayerScripts", "StarterCharacterScripts"}) do
			local sub = sp:FindFirstChild(subName)
			if sub then
				for _, child in ipairs(sub:GetChildren()) do
					if child:IsA("LuaSourceContainer") then
						child:Destroy()
					end
				end
			end
		end
	end
end

local function clearTrackedParts(keepPartes)
	-- Remove workspace Parts that are tracked but no longer in the incoming data
	local ws = workspace
	local toRemove = {}
	local function findTracked(parent)
		for _, child in ipairs(parent:GetChildren()) do
			if (child:IsA("BasePart") or child:IsA("Model")) and child:GetAttribute("Comitter_track") then
				if not (keepPartes and keepPartes[child.Name]) then
					table.insert(toRemove, child)
				end
			end
			if child:IsA("BasePart") or child:IsA("Model") or child:IsA("Folder") then
				findTracked(child)
			end
		end
	end
	findTracked(ws)
	for _, obj in ipairs(toRemove) do
		pcall(function() obj:Destroy() end)
	end
end

local function findInTree(parent, name)
	-- Search recursively for instance by name
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == name then return child end
		local found = findInTree(child, name)
		if found then return found end
	end
	return nil
end

local function injectPartes(partes, fileMap)
	clearTrackedParts(partes)
	if not partes then return end
	local ws = workspace
	for partName, meta in pairs(partes) do
		-- Try exact path from fileMap first: Workspace/<model>/<part>/Script
		local existing = ws:FindFirstChild(partName)
		if not existing then
			existing = findInTree(ws, partName)
		end
		if not existing then
			local className = meta.className or "Part"
			local ok, obj = pcall(function() return Instance.new(className) end)
			if ok and obj then
				obj.Name = partName
				obj.Parent = ws
				obj:SetAttribute("Comitter_track", true)
				pcall(function() if meta.position then obj.Position = Vector3.new(unpack(meta.position)) end end)
				pcall(function() if meta.size then obj.Size = Vector3.new(unpack(meta.size)) end end)
				pcall(function() if meta.orientation then obj.Orientation = Vector3.new(unpack(meta.orientation)) end end)
				pcall(function() if meta.anchored ~= nil then obj.Anchored = meta.anchored end end)
				pcall(function() if meta.canCollide ~= nil then obj.CanCollide = meta.canCollide end end)
				pcall(function() if meta.transparency ~= nil then obj.Transparency = meta.transparency end end)
				pcall(function() if meta.brickColor then obj.BrickColor = BrickColor.new(meta.brickColor) end end)
				pcall(function() if meta.material then obj.Material = Enum.Material[meta.material] end end)
			end
		else
			if not existing:GetAttribute("Comitter_track") then
				existing:SetAttribute("Comitter_track", true)
			end
		end
	end
end

local function injectScripts(fileMap, uids, commitHash, classes, partes)
	injectPartes(partes, fileMap)
	clearStudioScripts()
	local n = 0
	for fp, src in pairs(fileMap) do
		local svcName = fp:match("^([^/]+)")
		if svcName then
			local svc
			if svcName == "Workspace" then
				svc = workspace
			else
				svc = game:GetService(svcName)
			end
			if svc then
				local parts = {}
				for seg in (fp:sub(#svcName + 2)):gmatch("[^/]+") do table.insert(parts, seg) end
				local cur = svc
				for i = 1, #parts - 1 do
					-- Try direct child first, then search recursively
					local f = cur:FindFirstChild(parts[i])
					if not f then
						f = findInTree(cur, parts[i])
					end
					if not f then
						if svcName == "Workspace" then cur = nil; break end
						f = Instance.new("Folder"); f.Name = parts[i]; f.Parent = cur
					end
					cur = f
				end
				if cur and #parts > 0 then
					local sname = parts[#parts]:gsub("%.lua$", ""):gsub("%.server$", ""):gsub("%.client$", "")
					local existing = cur:FindFirstChild(sname)
					local classType = (classes and classes[fp]) or "Script"
					if not existing then
						if classType == "LocalScript" then existing = Instance.new("LocalScript")
						elseif classType == "ModuleScript" then existing = Instance.new("ModuleScript")
						else existing = Instance.new("Script")
						end
						existing.Name = sname; existing.Parent = cur
					end
					existing.Source = src
					-- Restore UID if we have one for this path
					if uids and uids[fp] then
						existing:SetAttribute("Comitter_uid", uids[fp])
					else
						ensureUID(existing)
					end
					-- Update base hash so safety checks work
					if commitHash and commitHash ~= "" then
						setBaseHash(existing, commitHash)
					end
					n = n + 1
				end
			end
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
	local email = GUI.loadConfig and GUI.loadConfig().email or ""
	RPC:send("config_set", {user = user, token = token, email = email, remote_template = remote})
	state.config = {user = user, token = token, email = email, remote_template = remote}
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

-- Carrega place: branches + baseline do git + scan atual
local function loadPlace()
	loadBranches()
	local r = RPC:send("read_branch", {place = state.place, branch = state.branch})
	state.currentHash = (r.success and r.commit_hash) or ""
	state.baseline = {}
	state.lastPartes = {}
	if r.success and r.files then
		for path, src in pairs(r.files) do
			state.baseline[path] = {source = src}
		end
	end
	if r.success and r.partes then
		state.lastPartes = r.partes
	end
	state.staged = scanScripts()
	refreshUI()
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
	local partes = {}
	local scanWorkspace = state.scanMask["Workspace (tracked)"]
	for key, info in pairs(all) do
		if isBuiltin(key) then
			-- skip Roblox built-in scripts
		else
			payload[key] = info.source
			uids[key] = info.uid
			classes[key] = info.class or "Script"
			if info.parteMeta then
				local parentName = key:match("^Workspace/([^/]+)/")
				if parentName and not partes[parentName] then
					partes[parentName] = info.parteMeta
				end
			end
			count = count + 1
		end
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
	local rpcPayload = {place = state.place, message = msg, files = payload, uids = uids, classes = classes, branch = state.branch, game_id = gameId}
	if scanWorkspace then
		-- Scan de Workspace ligado: manda as partes escaneadas (pode ser vazio se
		-- todas sumiram — aí clear_partes=true limpa de verdade).
		rpcPayload.partes = partes
		if next(partes) == nil then
			rpcPayload.clear_partes = true
		end
	else
		-- Scan desligado: preserva as partes do baseline (último estado conhecido).
		if state.lastPartes and next(state.lastPartes) then
			rpcPayload.partes = state.lastPartes
		end
	end
	local r = RPC:send("commit", rpcPayload)
	if r.success then
		local short = r.hash and r.hash:sub(1, 7) or "?"
		log("✓ " .. short .. " " .. msg)
		-- Update Comitter_base on all committed instances
		for key, info in pairs(all) do
			if not isBuiltin(key) then setBaseHash(info.obj, r.hash) end
		end
		-- Guarda o estado das partes pra preservar em commits futuros com scan desligado
		if next(partes) then state.lastPartes = partes end
		state.currentHash = r.hash
		state.dirty = false
		state.staged = all
		-- Atualiza o baseline pro estado recém-commitado (evita falso M/A)
		state.baseline = {}
		for key, info in pairs(all) do
			if not isBuiltin(key) then state.baseline[key] = {source = info.source} end
		end
		GUI:setFiles(stagedList())
		local diffText = "Commit: " .. short .. "\n"
		if r.diff and r.diff ~= "" then
			diffText = diffText .. r.diff
		else
			for key in pairs(payload) do
				diffText = diffText .. "+ " .. key .. "\n"
			end
		end
		GUI:setDiff(diffText)
		log("Commit salvo localmente — use Push para enviar ao GitHub")
	else
		log("✗ " .. (r.error or "commit failed"))
	end
end

local function doPull()
	state.place = GUI:getName()
	log("Pulling " .. state.branch .. "...")
	local r = RPC:send("pull", {place = state.place, branch = state.branch})
	if r.success then
		log("✓ Pulled")
		if r.files then
			local n = injectScripts(r.files, r.uids, r.commit_hash, r.classes, r.partes)
			log("Applied " .. n .. " scripts to Studio")
		end
		state.staged = scanScripts()
		GUI:setFiles(stagedList())
	else
		log("✗ " .. (r.error or "pull failed"))
	end
end

local function applyBranch(name, files, uids, commitHash, classes, partes)
	local n = injectScripts(files, uids, commitHash, classes, partes)
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
				applyBranch(name, r.files, r.uids, r.commit_hash, r.classes, r.partes)
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
									local sname = parts[#parts]:gsub("%.lua$", ""):gsub("%.server$", ""):gsub("%.client$", "")
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
				applyBranch(name, r.files, r.uids, r.commit_hash, r.classes, r.partes)
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
			applyBranch(name, r.files, r.uids, r.commit_hash, r.classes, r.partes)
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
						applyBranch(name, r2.files, r2.uids, r2.commit_hash, r2.classes, r2.partes)
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
GUI.OnScanConfig = function()
	local sg = GUI.widget and GUI.widget.Parent
	if not sg then return end
	local existing = sg:FindFirstChild("ScanConfigPopup")
	if existing then existing:Destroy() end

	local popup = Instance.new("Frame")
	popup.Name = "ScanConfigPopup"
	popup.Size = UDim2.new(0, 260, 0, #SCAN_SERVICES * 30 + 100)
	popup.Position = UDim2.new(0.5, -130, 0.5, -popup.Size.Y.Offset/2)
	popup.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
	popup.BorderSizePixel = 1; popup.BorderColor3 = Color3.fromRGB(60, 60, 70)
	popup.ZIndex = 500; popup.Parent = sg

	local hd = Instance.new("Frame"); hd.Size = UDim2.new(1, 0, 0, 28)
	hd.BackgroundColor3 = Color3.fromRGB(40, 40, 48); hd.Parent = popup
	local ht = Instance.new("TextLabel"); ht.Size = UDim2.new(1, -30, 1, 0); ht.Position = UDim2.new(0, 8, 0, 0)
	ht.BackgroundTransparency = 1; ht.TextColor3 = Color3.fromRGB(220, 220, 240); ht.Font = Enum.Font.GothamBold
	ht.TextSize = 13; ht.Text = "Scan targets"; ht.TextXAlignment = Enum.TextXAlignment.Left; ht.Parent = hd
	local hx = Instance.new("TextButton"); hx.Size = UDim2.new(0, 24, 0, 24); hx.Position = UDim2.new(1, -26, 0, 2)
	hx.BackgroundColor3 = Color3.fromRGB(80, 30, 30); hx.TextColor3 = Color3.fromRGB(255, 130, 130); hx.Font = Enum.Font.Code
	hx.TextSize = 14; hx.Text = "X"; hx.Parent = hd
	hx.MouseButton1Click:Connect(function() popup:Destroy() end)

	local maskCopy = {}
	for k, v in pairs(state.scanMask) do maskCopy[k] = v end

	local function refreshToggles()
		for _, c in ipairs(popup:GetChildren()) do
			if c:IsA("TextButton") and not (c == hx) then c:Destroy() end
		end
		local y = 32
		for _, svc in ipairs(SCAN_SERVICES) do
			local btn = Instance.new("TextButton")
			btn.Size = UDim2.new(1, -16, 0, 26); btn.Position = UDim2.new(0, 8, 0, y)
			btn.BorderSizePixel = 0; btn.AutoButtonColor = false
			btn.Font = Enum.Font.GothamBold; btn.TextSize = 12
			btn.TextXAlignment = Enum.TextXAlignment.Left
			btn.Text = (maskCopy[svc.name] and "✓ " or "✗ ") .. svc.name
			btn.BackgroundColor3 = maskCopy[svc.name] and Color3.fromRGB(35, 50, 35) or Color3.fromRGB(45, 35, 35)
			btn.TextColor3 = maskCopy[svc.name] and Color3.fromRGB(150, 255, 150) or Color3.fromRGB(255, 150, 150)
			btn.Parent = popup
			btn.MouseButton1Click:Connect(function()
				maskCopy[svc.name] = not maskCopy[svc.name]
				refreshToggles()
			end)
			y = y + 28
		end
		-- Save button
		local saveBtn = Instance.new("TextButton")
		saveBtn.Size = UDim2.new(1, -16, 0, 26); saveBtn.Position = UDim2.new(0, 8, 0, y)
		saveBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 212); saveBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		saveBtn.Font = Enum.Font.GothamBold; saveBtn.TextSize = 12; saveBtn.Text = "Save & Rescan"
		saveBtn.BorderSizePixel = 0; saveBtn.Parent = popup
		saveBtn.MouseButton1Click:Connect(function()
			state.scanMask = maskCopy
			state.staged = scanScripts()
			GUI:setFiles(stagedList())
			log("Scan targets updated: " .. #stagedList() .. " scripts")
			popup:Destroy()
		end)
	end
	refreshToggles()
end
GUI.OnCherryPick = function()
	log("Cherry-pick opened")
	local sg = GUI.widget and GUI.widget.Parent
	if not sg then log("Cherry-pick: no sg"); return end
	local branchNames = {}
	for _, b in ipairs(state.branches) do
		if b.name ~= state.branch then table.insert(branchNames, b.name) end
	end
	if #branchNames == 0 then
		log("No other branches to cherry-pick from")
		return
	end

	local existingCp = sg:FindFirstChild("CherryPickPopup")
	if existingCp then existingCp:Destroy() end

	local popup = Instance.new("Frame")
	popup.Name = "CherryPickPopup"
	popup.Size = UDim2.new(0, 360, 0, 420)
	popup.Position = UDim2.new(0.5, -180, 0.5, -210)
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

	local ddOpen = false
	local ddFrame = Instance.new("Frame"); ddFrame.Size = UDim2.new(1, -16, 0, #branchNames * 22)
	ddFrame.Position = UDim2.new(0, 8, 0, 70); ddFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
	ddFrame.BorderSizePixel = 1; ddFrame.BorderColor3 = Color3.fromRGB(60, 60, 70); ddFrame.ZIndex = 405
	ddFrame.Visible = false; ddFrame.Parent = sg
	local ddLayout = Instance.new("UIListLayout"); ddLayout.Parent = ddFrame
	for _, bn in ipairs(branchNames) do
		local ddb = Instance.new("TextButton"); ddb.Size = UDim2.new(1, 0, 0, 22)
		ddb.BackgroundColor3 = Color3.fromRGB(40, 40, 48); ddb.TextColor3 = Color3.fromRGB(220, 220, 240)
		ddb.Font = Enum.Font.Code; ddb.TextSize = 11; ddb.Text = bn; ddb.Parent = ddFrame
		ddb.MouseButton1Click:Connect(function()
			selBranch = bn; selBtn.Text = bn; ddFrame.Visible = false; ddOpen = false
			loadScripts(bn)
		end)
	end
	selBtn.MouseButton1Click:Connect(function()
		ddOpen = not ddOpen; ddFrame.Visible = ddOpen
		-- Reposition dropdown relative to screen
		local ap = selBtn.AbsolutePosition
		ddFrame.Position = UDim2.new(0, ap.X - sg.AbsolutePosition.X, 0, ap.Y + 22 - sg.AbsolutePosition.Y)
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
								if not f then f = findInTree(cur, parts[i]) end
								if not f then
									if svcName == "Workspace" then cur = nil; break end
									f = Instance.new("Folder"); f.Name = parts[i]; f.Parent = cur
								end
								cur = f
							end
							if cur and #parts > 0 then
								local sname = parts[#parts]:gsub("%.lua$", "")
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
								log("✓ Cherry-picked " .. p .. " from " .. branchName)
							else
								log("✗ Cherry-pick: path not found in Studio: " .. p)
							end
						else
							log("✗ Cherry-pick: service not found: " .. svcName)
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
			local row = Instance.new("Frame"); row.Size = UDim2.new(1, 0, 0, 52)
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

			-- Apply button
			local applyBtn = Instance.new("TextButton"); applyBtn.Size = UDim2.new(0, 80, 0, 18); applyBtn.Position = UDim2.new(1, -84, 0, 32)
			applyBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 212); applyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
			applyBtn.Font = Enum.Font.GothamBold; applyBtn.TextSize = 10; applyBtn.Text = "Apply"
			applyBtn.BorderSizePixel = 0; applyBtn.Parent = row
			applyBtn.MouseButton1Click:Connect(function()
				local ack = RPC:send("apply_commit", {place = state.place, hash = c.hash, branch = histBranch})
				if ack.success and ack.files then
					local n = injectScripts(ack.files, {}, ack.hash, ack.classes, ack.partes)
					state.staged = scanScripts()
					GUI:setFiles(stagedList())
					log("Applied " .. n .. " scripts from " .. (c.shortHash or c.hash:sub(1,7)))
				else
					log("✗ Apply failed: " .. (ack.error or "unknown"))
				end
			end)
		end
		histList.CanvasSize = UDim2.new(0, 0, 0, #r.commits * 54 + 4)
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

-- Auto-refresh da staged list: re-scan de 1 em 1s e re-renderiza
-- somente quando algo mudou (edição de Source, add/remove de script).
task.spawn(autoRefresh)

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
									loadPlace()
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
								loadPlace()
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
		loadPlace()
	end
	log("Comitter v1.5.0 ready")
else
	log("Comitter v1.5.0 — Offline. Rode: ./start.sh")
end
