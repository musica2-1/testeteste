--[[
	PixelSnow.lua  —  Luau para Roblox Studio
	Coloque como LocalScript em StarterPlayerScripts ou StarterGui.

	Equivalente ao componente React PixelSnow (React Bits).
	Como Roblox não tem shaders GLSL, os flocos são simulados como
	partículas 2D individuais — muito mais leve que tentar emular
	raymarching 3D no Heartbeat.

	━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
	CONFIGURAÇÕES
	━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
	color           – Color3 dos flocos
	flakeCount      – quantidade de flocos (substitui density+pixelResolution)
	minSize / maxSize – tamanho em pixels dos flocos
	speed           – velocidade de queda (multiplicador)
	direction       – ângulo do vento em graus (0 = direita, 90 = baixo, 125 = padrão)
	depthLayers     – camadas de profundidade (simula perspectiva 3D)
	variant         – "square" | "round"   (round = TextLabel com UICorner)
	brightness      – transparência geral (0–1)
	pixelSnap       – arredonda posição para grid (efeito pixelado retro)
	pixelSnapSize   – tamanho do grid de snap em pixels
	pageLoadAnim    – fade-in ao iniciar
--]]

local CFG = {
	color         = Color3.fromHex("FFFFFF"),
	flakeCount    = 120,        -- ← principal controle de performance
	minSize       = 3,
	maxSize       = 10,
	speed         = 1.25,
	direction     = 125,        -- graus (igual ao prop React)
	depthLayers   = 4,          -- 1 = plano, 4 = profundidade máxima
	variant       = "square",   -- "square" ou "round"
	brightness    = 1.0,
	pixelSnap     = true,
	pixelSnapSize = 4,          -- grid retro em pixels
	pageLoadAnim  = true,
}

-- ── Serviços ───────────────────────────────────────────────────
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local LocalPlayer      = Players.LocalPlayer
local PlayerGui        = LocalPlayer:WaitForChild("PlayerGui")

-- ── Math ───────────────────────────────────────────────────────
local sin, cos, floor, random, sqrt =
	math.sin, math.cos, math.floor, math.random, math.sqrt
local function clamp(v,lo,hi) return v<lo and lo or v>hi and hi or v end
local function lerp(a,b,t)    return a+(b-a)*t                        end

local RAD  = math.pi / 180
local dirX = cos(CFG.direction * RAD)   -- componente X do vento
local dirY = sin(CFG.direction * RAD)   -- componente Y do vento
-- No espaço da tela: X = direita, Y = baixo
-- direction 125° → vento vai para baixo-esquerda (como no shader original)
local windX =  dirX * 0.6   -- fator horizontal
local windY =  dirY * 0.6   -- fator vertical (positivo = desce)

-- ── GUI ────────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name           = "PixelSnow"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.DisplayOrder   = 10
gui.Parent         = PlayerGui

local container = Instance.new("Frame")
container.Name                   = "SnowContainer"
container.Size                   = UDim2.fromScale(1, 1)
container.BackgroundTransparency = 1
container.ClipsDescendants       = true
container.Parent                 = gui

-- ── Criação dos flocos ─────────────────────────────────────────
--[[
	Cada floco tem:
	  frame   – Frame (quadrado) ou Frame+UICorner (redondo)
	  x, y    – posição 0..1 (relativa ao container)
	  vx, vy  – velocidade por segundo (0..1 por segundo)
	  size    – tamanho em pixels
	  layer   – 0..1 (profundidade: 0 = longe/pequeno/transparente, 1 = perto)
	  phase   – offset de oscilação lateral (seno) aleatório
	  wobble  – amplitude da oscilação lateral
--]]

local flakes = table.create(CFG.flakeCount)

local function makeFlake(startOffscreen)
	local layer = random() ^ 1.5            -- bias para flocos próximos
	local size  = lerp(CFG.minSize, CFG.maxSize, layer)

	-- Velocidade proporcional à camada (perto = rápido)
	local baseSpeed = lerp(0.03, 0.12, layer) * CFG.speed

	-- Posição inicial
	local x = random()
	local y = startOffscreen and -0.05 or random()

	local frame = Instance.new("Frame")
	frame.BorderSizePixel      = 0
	frame.BackgroundColor3     = CFG.color
	frame.Size                 = UDim2.fromOffset(size, size)
	frame.BackgroundTransparency = 1   -- começa invisível (page load)
	frame.ZIndex               = math.ceil(layer * 5)
	frame.Parent               = container

	if CFG.variant == "round" then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)   -- círculo perfeito
		corner.Parent = frame
	end

	-- Brilho por camada (longe = mais transparente, simula depthFade)
	local alpha = clamp(layer * CFG.brightness, 0.05, CFG.brightness)

	flakes[#flakes + 1] = {
		frame    = frame,
		x        = x,
		y        = y,
		baseSpeed= baseSpeed,
		size     = size,
		layer    = layer,
		alpha    = alpha,
		phase    = random() * math.pi * 2,
		wobble   = lerp(0.002, 0.012, random()),  -- amplitude lateral do seno
		loaded   = not CFG.pageLoadAnim,           -- false = ainda fazendo fade-in
		loadT    = random() * 1.2,                 -- delay do fade-in
	}
end

for i = 1, CFG.flakeCount do
	makeFlake(false)
end

-- ── Pixel snap helper ──────────────────────────────────────────
local function snap(v, grid)
	return floor(v / grid + 0.5) * grid
end

-- ── Loop ──────────────────────────────────────────────────────
local t            = 0
local loadProgress = CFG.pageLoadAnim and 0 or 1

RunService.Heartbeat:Connect(function(dt)
	t = t + dt

	-- Page load fade global
	if loadProgress < 1 then
		loadProgress = clamp(loadProgress + dt * 0.7, 0, 1)
	end

	local vp   = container.AbsoluteSize
	local vpW  = vp.X
	local vpH  = vp.Y
	if vpW == 0 or vpH == 0 then return end

	local snapGrid = CFG.pixelSnapSize

	for i = 1, #flakes do
		local f   = flakes[i]
		local frm = f.frame

		-- ── Movimento ──────────────────────────────────────────
		-- Vento direcional + oscilação senoidal lateral
		local wobble = sin(t * 1.1 + f.phase) * f.wobble
		f.x = f.x + (windX * f.baseSpeed + wobble) * dt
		f.y = f.y + (windY * f.baseSpeed + f.baseSpeed) * dt
		-- (baseSpeed adicionado ao Y garante queda mesmo com direction horizontal)

		-- ── Wrap / reciclagem ───────────────────────────────────
		if f.y > 1.06 then
			-- Saiu por baixo → reaparece no topo
			f.y = -0.04 - random() * 0.1
			f.x = random()
		elseif f.y < -0.1 then
			f.y = 1.04
			f.x = random()
		end
		if f.x > 1.08 then
			f.x = -0.05
		elseif f.x < -0.08 then
			f.x = 1.04
		end

		-- ── Posição em pixels ────────────────────────────────────
		local px = f.x * vpW - f.size * 0.5
		local py = f.y * vpH - f.size * 0.5

		if CFG.pixelSnap then
			px = snap(px, snapGrid)
			py = snap(py, snapGrid)
		end

		frm.Position = UDim2.fromOffset(px, py)

		-- ── Page load fade-in por floco ─────────────────────────
		local alpha = f.alpha
		if not f.loaded then
			local flakeProgress = clamp((loadProgress - f.loadT * 0.5) / 0.35, 0, 1)
			alpha = alpha * flakeProgress
			if flakeProgress >= 1 then f.loaded = true end
		end

		frm.BackgroundTransparency = clamp(1 - alpha, 0, 1)
	end
end)

--[[
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
API pública (se usar como ModuleScript)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
]]
return {
	gui       = gui,
	container = container,
	flakes    = flakes,

	--- Muda a direção do vento em tempo real (graus)
	setDirection = function(deg)
		CFG.direction = deg
		windX = cos(deg * RAD) * 0.6
		windY = sin(deg * RAD) * 0.6
	end,

	--- Muda a cor de todos os flocos
	setColor = function(color)
		CFG.color = color
		for _, f in ipairs(flakes) do
			f.frame.BackgroundColor3 = color
		end
	end,

	--- Muda a quantidade de flocos (recria todos)
	setCount = function(n)
		for _, f in ipairs(flakes) do f.frame:Destroy() end
		table.clear(flakes)
		CFG.flakeCount = n
		for i = 1, n do makeFlake(false) end
	end,

	setSpeed = function(s) CFG.speed = s end,
	setBrightness = function(b)
		CFG.brightness = b
		for _, f in ipairs(flakes) do
			f.alpha = clamp(f.layer * b, 0.05, b)
		end
	end,
}