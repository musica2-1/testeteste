--[[
	CorrupcaoOcularVFX
	Efeito abstrato multicamadas: massa orgânica, olhos piscando,
	tendrils de energia, neblina, luz pulsante e pós-processamento.
	Local: ReplicatedStorage
]]

local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")

local CorrupcaoOcularVFX = {}

function CorrupcaoOcularVFX.criar(posicao, texturaId, opcoes)
	texturaId = texturaId or "rbxassetid://72012030715430"
	opcoes = opcoes or {}
	local intensidade = opcoes.intensidade or 1 -- multiplicador geral (0.5 = sutil, 2 = extremo)
	local comSom = opcoes.comSom ~= false -- true por padrão
	local comPosProcessamento = opcoes.comPosProcessamento ~= false

	-- ===== ESTRUTURA BASE =====
	local nucleo = Instance.new("Part")
	nucleo.Name = "CorrupcaoOcular_Nucleo"
	nucleo.Anchored = true
	nucleo.CanCollide = false
	nucleo.Transparency = 1
	nucleo.Size = Vector3.new(1, 1, 1)
	nucleo.Position = posicao
	nucleo.Parent = workspace

	local attachCentro = Instance.new("Attachment")
	attachCentro.Parent = nucleo

	-- ===== CAMADA 1: Massa orgânica pulsante =====
	local massa = Instance.new("ParticleEmitter")
	massa.Texture = texturaId
	massa.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(180, 0, 0)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 40, 40)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 0, 0))
	})
	massa.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5 * intensidade),
		NumberSequenceKeypoint.new(0.3, 4 * intensidade),
		NumberSequenceKeypoint.new(0.7, 3 * intensidade),
		NumberSequenceKeypoint.new(1, 0)
	})
	massa.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(0.4, 0.1),
		NumberSequenceKeypoint.new(1, 1)
	})
	massa.Lifetime = NumberRange.new(1.5, 3)
	massa.Rate = 25 * intensidade
	massa.Speed = NumberRange.new(0.5, 2)
	massa.SpreadAngle = Vector2.new(360, 360)
	massa.RotSpeed = NumberRange.new(-40, 40)
	massa.LightEmission = 0.3
	massa.Parent = attachCentro

	-- ===== CAMADA 2: "Olhos" piscando =====
	local olhos = Instance.new("ParticleEmitter")
	olhos.Texture = texturaId
	olhos.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	olhos.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.1, 1.2),
		NumberSequenceKeypoint.new(0.9, 1),
		NumberSequenceKeypoint.new(1, 0)
	})
	olhos.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, 0),
		NumberSequenceKeypoint.new(0.85, 0),
		NumberSequenceKeypoint.new(1, 1)
	})
	olhos.Lifetime = NumberRange.new(0.8, 1.5)
	olhos.Rate = 4 * intensidade
	olhos.Speed = NumberRange.new(0, 0.3)
	olhos.SpreadAngle = Vector2.new(180, 180)
	olhos.LightEmission = 1
	olhos.Parent = attachCentro

	-- ===== CAMADA 3: Tendrils (Beams) =====
	local numTendrils = math.floor(6 * intensidade)
	local beams = {}

	for i = 1, numTendrils do
		local anguloAleatorio = math.rad(math.random(0, 360))
		local alturaAleatoria = math.random(-100, 100) / 100

		local pontaAttach = Instance.new("Attachment")
		local distancia = math.random(4, 8)
		pontaAttach.Position = Vector3.new(
			math.cos(anguloAleatorio) * distancia,
			alturaAleatoria * distancia,
			math.sin(anguloAleatorio) * distancia
		)
		pontaAttach.Parent = nucleo

		local beam = Instance.new("Beam")
		beam.Attachment0 = attachCentro
		beam.Attachment1 = pontaAttach
		beam.Texture = texturaId
		beam.TextureMode = Enum.TextureMode.Wrap
		beam.TextureSpeed = math.random(-30, 30) / 100
		beam.TextureLength = 1
		beam.Width0 = 0.1
		beam.Width1 = math.random(4, 10) / 10
		beam.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 20, 20)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 0, 0))
		})
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 0.9)
		})
		beam.CurveSize0 = math.random(-3, 3)
		beam.CurveSize1 = math.random(-3, 3)
		beam.Segments = 20
		beam.LightEmission = 0.5
		beam.Parent = nucleo

		table.insert(beams, beam)
	end

	-- ===== CAMADA 4: Neblina escura =====
	local neblina = Instance.new("ParticleEmitter")
	neblina.Texture = "rbxassetid://243664887"
	neblina.Color = ColorSequence.new(Color3.fromRGB(10, 0, 0))
	neblina.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 3),
		NumberSequenceKeypoint.new(1, 8)
	})
	neblina.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 1)
	})
	neblina.Lifetime = NumberRange.new(2, 4)
	neblina.Rate = 6 * intensidade
	neblina.Speed = NumberRange.new(0.2, 0.8)
	neblina.Parent = attachCentro

	-- ===== LUZ PULSANTE =====
	local luz = Instance.new("PointLight")
	luz.Color = Color3.fromRGB(255, 30, 30)
	luz.Range = 16 * intensidade
	luz.Brightness = 2
	luz.Parent = nucleo

	local pulsando = true
	task.spawn(function()
		while pulsando do
			local brilho = math.random(150, 400) / 100 * intensidade
			local duracao = math.random(10, 40) / 100
			TweenService:Create(luz, TweenInfo.new(duracao, Enum.EasingStyle.Sine), {
				Brightness = brilho
			}):Play()
			task.wait(duracao)
		end
	end)

	-- ===== ROTAÇÃO LENTA =====
	local rotacionando = true
	task.spawn(function()
		while rotacionando do
			nucleo.CFrame = nucleo.CFrame * CFrame.Angles(0, math.rad(0.3), 0)
			task.wait()
		end
	end)

	-- ===== 🔊 SOM AMBIENTE (bônus picante) =====
	local som
	if comSom then
		som = Instance.new("Sound")
		som.SoundId = "rbxassetid://9126066864" -- drone/ambiente sinistro (troque pelo seu favorito)
		som.Volume = 0.5 * intensidade
		som.Looped = true
		som.RollOffMaxDistance = 60
		som.Parent = nucleo
		som:Play()
	end

	-- ===== 🌫️ PÓS-PROCESSAMENTO (bônus) =====
	local colorCorrection, bloom
	if comPosProcessamento then
		colorCorrection = Instance.new("ColorCorrectionEffect")
		colorCorrection.Name = "CorrupcaoOcular_CC"
		colorCorrection.TintColor = Color3.fromRGB(255, 200, 200)
		colorCorrection.Saturation = -0.1
		colorCorrection.Contrast = 0.3 * intensidade
		colorCorrection.Parent = Lighting

		bloom = Instance.new("BloomEffect")
		bloom.Name = "CorrupcaoOcular_Bloom"
		bloom.Intensity = 1.5 * intensidade
		bloom.Size = 30
		bloom.Threshold = 0.8
		bloom.Parent = Lighting

		-- Fade-in suave dos efeitos de pós-processamento
		colorCorrection.Contrast = 0
		bloom.Intensity = 0
		TweenService:Create(colorCorrection, TweenInfo.new(1), {Contrast = 0.3 * intensidade}):Play()
		TweenService:Create(bloom, TweenInfo.new(1), {Intensity = 1.5 * intensidade}):Play()
	end

	-- ===== 📳 CAMERA SHAKE (bônus picante, só pra quem tá perto) =====
	local function shakeCamera(jogador, forca, duracao)
		local camera = workspace.CurrentCamera
		if not camera then return end
		local tempoFinal = tick() + duracao
		task.spawn(function()
			while tick() < tempoFinal do
				local offset = Vector3.new(
					(math.random(-100, 100) / 100) * forca,
					(math.random(-100, 100) / 100) * forca,
					0
				)
				camera.CFrame = camera.CFrame * CFrame.new(offset)
				task.wait()
			end
		end)
	end

	-- ===== FUNÇÃO DE DESTRUIÇÃO SUAVE =====
	local function destruir(fadeTime)
		fadeTime = fadeTime or 2
		pulsando = false
		rotacionando = false

		massa.Rate = 0
		olhos.Rate = 0
		neblina.Rate = 0

		TweenService:Create(luz, TweenInfo.new(fadeTime), {Brightness = 0}):Play()

		for _, beam in ipairs(beams) do
			TweenService:Create(beam, TweenInfo.new(fadeTime), {
				Width0 = 0, Width1 = 0
			}):Play()
		end

		if som then
			TweenService:Create(som, TweenInfo.new(fadeTime), {Volume = 0}):Play()
		end

		if colorCorrection and bloom then
			TweenService:Create(colorCorrection, TweenInfo.new(fadeTime), {Contrast = 0}):Play()
			TweenService:Create(bloom, TweenInfo.new(fadeTime), {Intensity = 0}):Play()
			task.delay(fadeTime, function()
				colorCorrection:Destroy()
				bloom:Destroy()
			end)
		end

		task.wait(fadeTime + 2)
		nucleo:Destroy()
	end

	return {
		nucleo = nucleo,
		destruir = destruir,
		shakeCamera = shakeCamera,
	}
end

return CorrupcaoOcularVFX