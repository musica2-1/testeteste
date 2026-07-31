--[[
	AtivadorCorrupcaoOcular
	Chama o VFX de CorrupcaoOcularVFX e deixa ele rodando permanentemente.
	Local: ServerScriptService
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CorrupcaoOcularVFX = require(ReplicatedStorage:WaitForChild("CorrupcaoOcularVFX"))

-- Configurações do efeito
local POSICAO = Vector3.new(0, 5, 0)
local TEXTURA_ID = "rbxassetid://72012030715430"

-- Cria o efeito (permanente)
local efeito = CorrupcaoOcularVFX.criar(POSICAO, TEXTURA_ID, {
	intensidade = 1,
	comSom = false, -- ou true, se já tiver um ID de som válido
	comPosProcessamento = true,
})

print("Efeito de corrupção ocular criado permanentemente em:", POSICAO)