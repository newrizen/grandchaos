-- grandchaos/init.lua
-- Mod: Fase 1 do grandchaos (Floresta de Aria) para Luanti/Minetest Game.
--
-- Corredor de combate dividido em trechos fechados por paredes de tronco
-- PERMANENTES (nunca somem). Cada trecho tem, no chão:
--   - um bloco luminoso de POUSO no início (onde o jogador chega)
--   - um bloco luminoso de FIM no final, logo antes da parede seguinte
-- Ao pisar sobre o bloco de fim, aparece a mensagem "agache para prosseguir".
-- Se o jogador agachar (sneak) enquanto está sobre esse bloco, ele é
-- teleportado para o bloco de pouso do próximo trecho. O trecho 1 não tem
-- inimigos (só andar até o bloco já basta) e tem uma parede logo atrás do
-- ponto de partida do jogador. No último trecho (o do chefe), a saída
-- teleporta o jogador para fora de todos os trechos e libera o movimento
-- normal (sem trilho).
-- O personagem se move apenas para frente/para trás (eixo X) enquanto a
-- fase está em andamento, como em trilho. O eixo X foi escolhido porque é
-- o único eixo horizontal que o motor mt2d realmente controla via input do
-- jogador (key.left/key.right em mt2d_entities.lua só alteram v.x); o eixo
-- Z é sempre fixo (é o "para dentro da tela", usado só pelo offset da
-- câmera, cam.z = obj.z + 5) e nunca muda sozinho com o jogador andando.
-- Uso em jogo: comando /gcstart (ou clicar no portal).
--
-- NOTA DE TRADUÇÃO: todos os textos exibidos ao jogador (mensagens de
-- chat, HUD, descrições de comandos) estão em inglês no código-fonte e
-- passam pelo tradutor (S = core.get_translator("grandchaos")). A
-- tradução para português (pt-BR) fica em locale/grandchaos.pt.tr.
local c = core
c.log("action", "[GrandChaos] init.lua loaded")
local S = c.get_translator("grandchaos")

grandchaos = {}
local WIDTH = 4             -- largura do corredor (eixo Z, travado/trilho)
local HEIGHT = 15             -- altura do corredor (eixo Y)
local SEG_LEN = 40            -- comprimento de cada trecho (eixo X) — inalterado
local WALL_THICKNESS = 3      -- espessura das paredes (início, entre trechos e no final)
local LAMP_GAP = 1            -- distância (em blocos) dos maselamps/vidros até a parede mais próxima
-- O jogador e as plataformas aéreas ficam na trilha z = origin.z + 0 (ver
-- apply_rail_movement e as "Plataformas aéreas" em build_arena). A parede
-- lateral fica em z = origin.z + min_z, onde min_z = -floor(WIDTH/2). O
-- chefe anda numa trilha própria, um passo à frente da parede e antes da
-- trilha do jogador/plataformas, para não competir com o corredor central.
local BOSS_RAIL_OFFSET = -math.floor(WIDTH / 2) + 1
local NUM_WAVE_SEGMENTS = 4      -- trechos de onda (o 1º fica vazio de inimigos)
local TOTAL_SEGMENTS = NUM_WAVE_SEGMENTS + 1 -- + o trecho do chefe (o último)

-- Estado por jogador:
-- { origin=pos, stage=1..TOTAL_SEGMENTS, alive_mobs={}, mobs_remaining=n, segment_started={[seg]=true}, saved_nodes={}, finished=bool, checkpoint_state=nil|"wait"|"go", landing_state=nil|"go", was_sneaking=bool, boss=objref, total_len=n }
local players_data = {}

-- HUD fixo no topo central da tela, com as instruções iniciais de como
-- entrar no modo 2D (/join2d) ou começar a fase (/gcstart). Fica
-- visível até o jogador usar um desses dois comandos (ver
-- grandchaos.hide_hint, chamado no /join2d em mt2d.lua e no /gcstart
-- logo abaixo).
local hud_hint = {}
local function hint_text()
	return S("Type '/gcstart' to start the stage ('/gcreset' cancels),@nOr type '/gcvs' to start Versus Mode (PvP) [server],@nOr type '/join2d' to just try 2D mode [experimental]@n(back to 3D: creative -> '/grantme leave2d' -> '/leave2d')")
end

function grandchaos.show_hint(player)
	local pname = player:get_player_name()
	if hud_hint[pname] then return end
	hud_hint[pname] = player:hud_add({
		type = "text",
		position = {x = 0.5, y = 0},
		offset = {x = 0, y = 20},
		alignment = {x = 0, y = 3},
		number = 0xFFFFFF,
		text = hint_text(),
	})
end

function grandchaos.hide_hint(pname)
	local player = c.get_player_by_name(pname)
	if player and hud_hint[pname] then player:hud_remove(hud_hint[pname]) end
	hud_hint[pname] = nil
end

c.register_on_leaveplayer(function(player)
	hud_hint[player:get_player_name()] = nil
end)

dofile(c.get_modpath("grandchaos") .. "/items.lua")
dofile(c.get_modpath("grandchaos") .. "/mpbar.lua")
dofile(c.get_modpath("grandchaos") .. "/entities.lua")

mt2d = {
    timer = 0,
    user = {},
    user3d = {},
    attach = {},
    playeranim = {
        stand={x=1,y=39,speed=30},
        walk={x=41,y=61,speed=30},
        run={x=41,y=61,speed=60},
        mine={x=65,y=75,speed=30},
        hugwalk={x=80,y=99,speed=30},
        lay={x=113,y=123,speed=0},
        sit={x=101,y=111,speed=0},
    },
}

dofile(c.get_modpath("grandchaos").."/mt2d_entities.lua")
dofile(c.get_modpath("grandchaos").."/mt2d.lua")

-- Comprimento "ocupado" por um trecho + a parede que vem logo depois dele.
local SEG_SPAN = SEG_LEN + WALL_THICKNESS

local function seg_x_start(seg) return (seg - 1) * SEG_SPAN + WALL_THICKNESS + 1 end
local function seg_x_end(seg) return seg_x_start(seg) + SEG_LEN - 1 end
-- Parede logo após o trecho (ou a parede final, após o último trecho):
-- agora com WALL_THICKNESS blocos de espessura, começando logo no fim do
-- trecho e terminando bem onde o próximo trecho começa (sem sobreposição).
local function wall_x_start(seg) return seg_x_end(seg) + 1 end
local function wall_x_end(seg) return seg_x_end(seg) + WALL_THICKNESS end
-- Ponto de pouso (chegada) de cada trecho: fica LAMP_GAP blocos após o fim
-- da parede anterior (ou da parede inicial, no caso do trecho 1).
local function landing_x(seg) return seg_x_start(seg) + LAMP_GAP end
-- Posição do bloco luminoso de FIM de trecho: fica LAMP_GAP blocos antes
-- do início da parede seguinte (o limite real do trecho, usado por
-- plataformas e área de spawn de inimigos, continua sendo seg_x_end).
local function end_marker_x(seg) return seg_x_end(seg) - LAMP_GAP end
-- A fase está "ativa" (trilho ligado) enquanto o jogador não tiver concluído
local function phase_active(data) return data and not data.finished end
-- Exposto para o mt2d.lua: diz se o jogador está no meio de uma fase do
-- grandchaos (usado para saber se o modo 2D deve ser reativado sozinho
-- ao reconectar/respawnar, já que fora de fase o 2D só entra por
-- comando direto — /join2d — ou pelo /gcstart).
function grandchaos.is_phase_active(pname) return phase_active(players_data[pname]) end
-- Bloco luminoso de FIM de trecho: "apagado" enquanto houver inimigos vivos
-- naquele trecho, e "aceso" (e só então libera a passagem) quando todos
-- forem derrotados. O trecho 1 não tem inimigos, então já nasce aceso.
local LAMP_ON = "grandchaos:meselamp"
local LAMP_OFF = "grandchaos:glassblock"

local function end_lamp_pos(origin, seg) return {x = origin.x - end_marker_x(seg), y = origin.y, z = origin.z} end
local function landing_lamp_pos(origin, seg) return {x = origin.x - landing_x(seg), y = origin.y, z = origin.z} end
local function set_end_lamp(origin, seg, lit)
	c.set_node(end_lamp_pos(origin, seg), {name = lit and LAMP_ON or LAMP_OFF})
end
local function set_landing_lamp(origin, seg, lit)
	c.set_node(landing_lamp_pos(origin, seg), {name = lit and LAMP_ON or LAMP_OFF})
end

-- Acende/apaga os dois blocos luminosos de um trecho (pouso e fim) juntos.
-- O bloco de pouso do trecho 1 nunca é apagado: não há trecho anterior
-- para se voltar, então ele já nasce (e permanece) aceso.
local function set_segment_lamps(origin, seg, lit)
	set_end_lamp(origin, seg, lit)
	if seg > 1 then set_landing_lamp(origin, seg, lit) end
end

-- Um trecho está "limpo" quando não resta nenhum inimigo (contagem chega a 0)
local function stage_cleared(data) return (data.mobs_remaining or 0) <= 0 end

-- Constrói o "casco" do corredor — chão, paredes laterais decoradas com
-- folhagem (z = min_z/max_z) e as camadas de vegetação de fundo — para um
-- trecho de `length` blocos a partir de `x_offset` (coordenada relativa ao
-- longo do eixo X, medida a partir de origin.x, com x crescente = mais
-- longe de origin). Usado tanto pela arena principal (build_arena) quanto
-- pela arena do modo Versus (build_vs_arena), para que ambas tenham o
-- mesmo visual. Se `saved` for uma tabela, os nós originais substituídos
-- são registrados nela (para permitir restaurar depois); passe nil quando
-- a restauração não for necessária.
local function build_corridor_shell(origin, x_offset, length, saved)
	local min_z = -math.floor(WIDTH / 2)
	local bg1_z = min_z - 1
	local bg2_z = min_z - 2
	local bg3_z = min_z - 3
	local max_z = min_z + WIDTH - 1
	local wall_leaves = {}
	local x = 0
	while x <= length do
		-- Espaço maior entre conjuntos
		x = x + math.random(2, 5)
		if x <= length then
			-- Cada conjunto ocupa 2 ou 3 colunas
			local width = math.random(2, 3)
			for xx = x, math.min(x + width - 1, length) do
				-- Um pouco mais de folhas por conjunto
				local clusters = math.random(2, 4)
				for i = 1, clusters do
					local start_y = math.random(1, HEIGHT - 2)
					local h = math.random(2, 3)
					for yy = start_y, math.min(start_y + h - 1, HEIGHT - 1) do wall_leaves[xx .. ":" .. yy] = true end
				end
			end
			x = x + width
		end
	end
	for x = 0, length do
		for z = bg3_z, max_z do
		local leaf_height = 0
		if z == min_z and math.random(8) == 1 then leaf_height = math.random(1, 3) end
			for y = -10, HEIGHT + 2 do
				local p = {x = origin.x - (x_offset + x), y = origin.y + y, z = origin.z + z}
				if saved then
					local key = c.hash_node_position(p)
					saved[key] = {pos = p, node = c.get_node(p)}
				end
				if y == 0 then
					if z == bg2_z then c.set_node(p, {name="grandchaos:floor1"})
					elseif z == bg3_z then c.set_node(p, {name="grandchaos:floor2"})
					else c.set_node(p, {name="grandchaos:floor1"})
					end

				elseif y <= -1 and y >= -10 then
					if z == bg2_z or z == bg3_z then c.set_node(p, {name="grandchaos:floor2"})
					else c.set_node(p, {name="grandchaos:floor2"})
					end

				elseif z == min_z then
					-- parede principal
					if y >= HEIGHT then c.set_node(p,{name="default:leaves"})
					elseif wall_leaves[x..":"..y] then c.set_node(p,{name="default:leaves"})
					else c.set_node(p,{name="grandchaos:trunk_wall"})
					end

				elseif z == bg1_z or z == bg2_z or z == bg3_z then
					-- camadas de vegetação atrás da parede
					if y >= HEIGHT then c.set_node(p,{name="default:leaves"})
					elseif math.random() < 0.35 then c.set_node(p,{name="default:leaves"})
					else c.set_node(p,{name="air"})
					end

				elseif z == max_z then
					if y >= HEIGHT then c.set_node(p,{name="default:leaves"})
					else c.set_node(p,{name="air"})
					end

				elseif y >= HEIGHT then c.set_node(p,{name="default:leaves"})
				else c.set_node(p,{name="air"})
				end
			end
		end
	end
end

-- Constrói uma parede de troncos (permanente), com `thickness` blocos de
-- espessura, ocupando toda a largura do corredor, começando em
-- `x_offset` (coordenada relativa, mesmo referencial de
-- build_corridor_shell). Usada para fechar as pontas da arena principal e
-- as divisões entre os trechos.
local function build_closing_wall(origin, x_offset, thickness)
	local min_z = -math.floor(WIDTH / 2)
	local max_z = min_z + WIDTH - 1
	for wx = 1, thickness do
		for z = min_z, max_z do
			for y = 1, HEIGHT - 1 do c.set_node({x = origin.x - (x_offset + wx), y = origin.y + y, z = origin.z + z}, {name = "grandchaos:trunk_wall"}) end
		end
	end
end

-- Espalha vegetação decorativa (mato, arbustos secos, cogumelos) pelo chão
-- de uma faixa do corredor (x_min..x_max, coordenadas relativas), evitando
-- as posições já reservadas em `reserved` (ex.: lâmpadas).
local function scatter_floor_decoration(origin, x_min, x_max, reserved)
	local min_z = -math.floor(WIDTH / 2)
	local max_z = min_z + WIDTH - 1
	local function random_floor_pos()
		for _ = 1, 100 do
			local x = math.random(x_min, x_max)
			local z = math.random(min_z + 1, max_z - 1)
			local key = x .. ":" .. z
			if not reserved[key] then reserved[key] = true return {x = origin.x - x, y = origin.y + 1, z = origin.z + z} end
		end
	end
	-- 15 a 20 matos baixos
	for i = 1, math.random(15, 20) do
		local p = random_floor_pos()
		if p and c.get_node(p).name == "air" then c.set_node(p, {name = "default:grass_3"}) end
	end
	-- 10 a 15 arbustos secos
	for i = 1, math.random(10, 15) do
		local p = random_floor_pos()
		if p and c.get_node(p).name == "air" then c.set_node(p, {name = "default:dry_shrub"}) end
	end
	-- 5 a 7 cogumelos
	for i = 1, math.random(5, 7) do
		local p = random_floor_pos()
		if p and c.get_node(p).name == "air" then c.set_node(p, {name = "flowers:mushroom_red"}) end
	end
end

-- Construção da arena (salva os nós originais para poder restaurar depois)
local function build_arena(origin)
	local saved = {}
	-- WALL_THICKNESS (parede inicial) + TOTAL_SEGMENTS * SEG_SPAN (cada
	-- trecho + a parede de 3 blocos que vem logo depois dele) + 3 de
	-- folga fora dos trechos, no final (mesma folga de antes).
	local total_len = WALL_THICKNESS + TOTAL_SEGMENTS * SEG_SPAN + 3
	local vs_start = total_len + 100
	local min_z = -math.floor(WIDTH / 2)
	local max_z = min_z + WIDTH - 1
	build_corridor_shell(origin, 0, total_len, saved)
	-- Parede logo ANTES do trecho 1 (fica atrás do jogador ao nascer),
	-- agora com WALL_THICKNESS blocos de espessura.
	build_closing_wall(origin, 0, WALL_THICKNESS)
	-- Paredes ao final de cada trecho (inclui a que fecha o trecho do
	-- chefe) — permanentes, nunca são removidas.
	for seg = 1, TOTAL_SEGMENTS do
		build_closing_wall(origin, seg_x_end(seg), WALL_THICKNESS)
		-- Bloco luminoso de FIM do trecho (LAMP_GAP blocos antes da
		-- parede) — começa apagado; só acende quando todos os inimigos
		-- do trecho forem derrotados (ver set_end_lamp, spawn_wave e
		-- grandchaos.spawn_boss).
		c.set_node({x = origin.x - end_marker_x(seg), y = origin.y, z = origin.z}, {name = LAMP_OFF})
		-- Bloco luminoso de POUSO no início do trecho (LAMP_GAP blocos
		-- após a parede anterior) — aceso desde o início só no trecho 1
		-- (não há trecho anterior para voltar); nos demais começa como
		-- vidro (apagado) e só vira meselamp quando o próprio trecho for
		-- totalmente limpo, podendo então ser usado para retornar ao
		-- trecho anterior (ver set_segment_lamps).
		c.set_node({x = origin.x - landing_x(seg), y = origin.y, z = origin.z}, {name = (seg == 1) and LAMP_ON or LAMP_OFF})
		-- Plataformas aéreas na trilha central
		local function make_row(y, min_len, max_len, gap, begin_x, finish_x)
			local x = begin_x
			while x <= finish_x do
				local len = math.random(min_len, max_len)
				for dx = 0, len - 1 do
					if x + dx <= finish_x then
						c.set_node({x = origin.x - (x + dx), y = origin.y + y, z = origin.z},
						{name = "grandchaos:trunk_platform", param2 = 12})
					end
				end

				for i = 1, math.random(0,1) do
					local mx = x + math.random(0, len - 1)
					local mp = {x = origin.x - mx, y = origin.y + y + 1, z = origin.z}
					if c.get_node(mp).name == "air" then c.set_node(mp,{name="flowers:mushroom_brown"}) end
				end
				x = x + len + math.random(gap[1], gap[2])
			end
		end
		if seg == 1 then
			-- Primeiro trecho:
			-- apenas plataformas baixas,
			-- maiores (4~6 blocos),
			-- começando e terminando nas paredes.
			make_row(3, 4, 6,
				{2,3},
				seg_x_start(seg),
				seg_x_end(seg)
			)
		elseif seg == 2 then
			-- Segundo trecho:
			-- plataforma baixa igual antes
			make_row(3, 3, 5,
				{2,4},
				landing_x(seg)+2,
				seg_x_end(seg)-3
			)
			-- plataforma superior
			make_row(6, 3, 5,
				{3,5},
				landing_x(seg)+4,
				seg_x_end(seg)-3
			)
		elseif seg == 3 then
			-- Igual ao segundo...
			make_row(3, 3, 5,
				{2,4},
				landing_x(seg)+2,
				seg_x_end(seg)
			)
			make_row(6, 3, 5,
				{3,5},
				landing_x(seg)-1,
				seg_x_end(seg)-3
			)
			-- ...mais uma terceira altura.
			make_row(9,3,5,
				{3,5},
				landing_x(seg)+4,
				seg_x_end(seg)+4
			)
		elseif seg == 4 then
			-- Igual ao segundo...
			make_row(3, 3, 5,
				{2,4},
				landing_x(seg)-1,
				seg_x_end(seg)-3
			)
			make_row(6, 3, 5,
				{3,5},
				landing_x(seg)+4,
				seg_x_end(seg)
			)
			-- ...mais uma terceira altura.
			make_row(9,3,5,
				{3,5},
				landing_x(seg)-1,
				seg_x_end(seg)-3
			)
		elseif seg == 5 then
			-- Segundo trecho:
			-- plataforma baixa igual antes
			make_row(3, 3, 5,
				{2,4},
				landing_x(seg)+2,
				seg_x_end(seg)
			)
			-- plataforma superior
			make_row(6, 3, 5,
				{3,5},
				landing_x(seg)+4,
				seg_x_end(seg)
			)
		else
			-- Restante da fase mantém o padrão atual.
			local height = 3
			for x = landing_x(seg)+2, seg_x_end(seg)-3, 5 do
				for dx = 0,2 do
					c.set_node({x = origin.x-(x+dx), y = origin.y+height, z = origin.z},
					{name="grandchaos:trunk_platform", param2=12})
				end
				if height==3 then height=6
				else height=3
				end
			end
		end
	end
	-- Área "fora dos trechos", além da parede do chefe
	for z = min_z, max_z do c.set_node ({x = origin.x - total_len, y = origin.y, z = origin.z + z}, {name = "default:goldblock"}) end
	-- Pontos já ocupados por decoração ou reservados (lâmpadas/vidros)
	local used = {}
	-- Reserva as posições dos blocos luminosos
	for seg = 1, TOTAL_SEGMENTS do
		used[end_marker_x(seg) .. ":0"] = true
		used[landing_x(seg) .. ":0"] = true
	end
	scatter_floor_decoration(origin, landing_x(1), seg_x_end(TOTAL_SEGMENTS) - 2, used)
	return saved, total_len
end

local function build_vs_arena(origin)
	local players = c.get_connected_players()
	if #players ~= 2 then return false, S"Exactly two players must be online." end
	local total_len = WALL_THICKNESS + TOTAL_SEGMENTS * SEG_SPAN + 3
	local vs_start = total_len + 100
	local min_z = -math.floor(WIDTH / 2)
	local max_z = min_z + WIDTH - 1
	-- Mesmo casco de build_arena (chão, paredes laterais com folhagem e
	-- vegetação de fundo), sem as lâmpadas nem as plataformas do trecho —
	-- essas a arena Versus monta com sua própria lógica, logo abaixo.
	build_corridor_shell(origin, vs_start - WALL_THICKNESS, SEG_LEN + WALL_THICKNESS * 2)
	build_closing_wall(origin, vs_start - WALL_THICKNESS - 1, WALL_THICKNESS)
        build_closing_wall(origin, vs_start + SEG_LEN, WALL_THICKNESS)
	-- Mesma decoração espalhada pelo chão (mato, arbustos secos, cogumelos).
	scatter_floor_decoration(origin, vs_start + 2, vs_start + SEG_LEN - 2, {})
	local low = true
	local low = true
	for x = vs_start + 1, vs_start + SEG_LEN - 1, 5 do
		if low then
			-- Plataforma baixa (3)
			for dx = 0, 2 do c.set_node({x = origin.x - (x + dx) -3, y = origin.y + 3, z = origin.z}, {name = "grandchaos:trunk_platform", param2 = 12}) end
			-- Plataforma media (6)
			for dx = 0, 2 do c.set_node({x = origin.x - (x + dx) +2, y = origin.y + 6, z = origin.z}, {name = "grandchaos:trunk_platform", param2 = 12}) end
			-- Plataforma alta (9), alinhada com a baixa
			for dx = 0, 2 do c.set_node({x = origin.x - (x + dx) -3, y = origin.y + 9, z = origin.z}, {name = "grandchaos:trunk_platform", param2 = 12}) end
		end
		low = not low
	end
	-- Plataforma média extra: só na camada de altura 6, mais para o lado
	-- do x negativo (mais perto do fim da arena), além do alcance das
	-- camadas baixa/alta — mantendo o mesmo deslocamento (+2) usado nas
	-- outras plataformas médias, para ficar centralizada/intercalada do
	-- mesmo jeito. Calculada a partir de WALL_THICKNESS para nunca
	-- invadir a parede de fechamento (build_closing_wall logo abaixo).
	local extra_mid_x = vs_start + SEG_LEN - WALL_THICKNESS - 1
	for dx = 0, 2 do c.set_node({x = origin.x - (extra_mid_x + dx) -3, y = origin.y + 6, z = origin.z}, {name = "grandchaos:trunk_platform", param2 = 12}) end
	local left_spawn = {x = origin.x - (vs_start + 1), y = origin.y, z = origin.z}
	local right_spawn = {x = origin.x - (vs_start + SEG_LEN - 1), y = origin.y, z = origin.z}
	c.set_node(left_spawn, {name = "grandchaos:meselamp"})
	c.set_node(right_spawn, {name = "grandchaos:meselamp"})
	-- Buracos-armadilha simétricos no chão, centralizados entre as duas
	-- maselamps: 7 blocos de extensão em X, 3 em Z (incluindo a trilha
	-- z = origin.z, por onde o jogador realmente anda — ver
	-- apply_rail_movement) e 7 blocos de profundidade (cava o chão,
	-- y relativo 0, e as 6 camadas de "grandchaos:floor2" logo abaixo).
	-- Ficam espelhados um do outro, com 3 blocos de vão livre entre eles
	-- no ponto médio exato entre as duas maselamps. Cair neles mata o
	-- jogador (ver checagem de altura no register_globalstep, mais abaixo).
	do
		local HOLE_LEN = 5
		local HOLE_DEPTH = 8
		local HOLE_WIDTH_Z = 2
		local HOLE_GAP = 15
		local lamp_mid = math.floor(((vs_start + 1) + (vs_start + SEG_LEN - 1)) / 2)
		local half_gap = math.floor(HOLE_GAP / 2)
		local hole_z_start = min_z + 1
		local hole_z_end = hole_z_start + HOLE_WIDTH_Z - 1
		local hole_ranges = {
			{lamp_mid - half_gap - HOLE_LEN, lamp_mid - half_gap - 1}, -- buraco à esquerda do centro
			{lamp_mid + half_gap + 1, lamp_mid + half_gap + HOLE_LEN}, -- buraco à direita do centro (espelhado)
		}
		for _, range in ipairs(hole_ranges) do
			for x = range[1], range[2] do
				for z = hole_z_start, hole_z_end do
					for y = 1, -(HOLE_DEPTH - 1), -1 do c.set_node({x = origin.x - x, y = origin.y + y, z = origin.z + z}, {name = "air"}) end
				end
			end
		end
	end
	local p1, p2 = players[1], players[2]
	if math.random(2) == 2 then p1, p2 = p2, p1 end
	local pos_left = {x = left_spawn.x, y = origin.y + 1.5, z = origin.z}
	local pos_right = {x = right_spawn.x, y = origin.y + 1.5, z = origin.z}
	p1:set_pos(pos_left)
	p2:set_pos(pos_right)
	local mt1 = mt2d.user[p1:get_player_name()]
	local mt2 = mt2d.user[p2:get_player_name()]
	if mt1 then
		mt1.object:set_pos(pos_left)
		mt1.object:set_velocity({x = 0, y = 0, z = 0})
		mt1.cam:set_pos({x = pos_left.x, y = pos_left.y, z = pos_left.z + 5})
	end
	if mt2 then
		mt2.object:set_pos(pos_right)
		mt2.object:set_velocity({x = 0, y = 0, z = 0})
		mt2.cam:set_pos({x = pos_right.x, y = pos_right.y, z = pos_right.z + 5})
	end
	-- Mesma preparação de jogador feita em grandchaos.start_phase/gcstart:
	-- dar a "arma" stick (se ainda não tiver) e liberar o pulo maior.
	for _, entry in ipairs({{p1, pos_left}, {p2, pos_right}}) do
		local p, spawn_pos = entry[1], entry[2]
		local inv = p:get_inventory()
		if not inv:contains_item("main", "grandchaos:stick") then inv:add_item("main", "grandchaos:stick") end
		p:set_hp(20)
		p:set_physics_override({jump = 2})
		-- Registro mínimo em players_data: sem isso, phase_active(data) fica
		-- falso e o globalstep (apply_rail_movement, try_drop_through_platform,
		-- try_jump_through_platform) nunca roda para esses jogadores — por
		-- isso eles não conseguiam atravessar os troncos (grandchaos:trunk_platform)
		-- no modo Versus. A flag `vs = true` faz o globalstep pular toda a
		-- lógica de checkpoint/segmento da fase 1 solo (ver register_globalstep
		-- logo abaixo), já que o Versus não tem trechos nem chefe.
		-- `vs_spawn` guarda o próprio ponto de spawn do jogador (esquerda ou
		-- direita), usado para reposicioná-lo ali se ele cair em um dos
		-- buracos-armadilha e morrer (ver register_on_respawnplayer).
		players_data[p:get_player_name()] = {
			origin = origin,
			stage = 1,
			alive_mobs = {},
			mobs_remaining = 0,
			segment_started = {},
			saved_nodes = nil,
			finished = false,
			checkpoint_state = nil,
			landing_state = nil,
			vs = true,
			vs_spawn = spawn_pos,
			vs_dead = false,
		}
	end
	return true
end

-- Composição dos trechos de inimigos (o 1º fica vazio, só para caminhar)
local WAVE_COMPOSITION = {
	{}, -- trecho 1: vazio de inimigos
	{"grandchaos:slime", "grandchaos:slime", "grandchaos:slime"},
	{"grandchaos:slime", "grandchaos:archer", "grandchaos:slime", "grandchaos:archer"},
	{"grandchaos:slime", "grandchaos:slime", "grandchaos:archer", "grandchaos:archer", "grandchaos:slime"},
}

local function spawn_wave(player, seg)
	local pname = player:get_player_name()
	local data = players_data[pname]
	if not data then return end
	local origin = data.origin
	local mobs = WAVE_COMPOSITION[seg]
	data.alive_mobs = {}
	data.mobs_remaining = 0
	if not mobs or #mobs == 0 then
		-- Trecho sem inimigos (ex.: trecho 1): os blocos já nascem acesos.
		set_segment_lamps(origin, seg, true)
		return
	end
	-- Ainda há inimigos a derrotar: os blocos de pouso e fim do trecho
	-- ficam apagados (vidro) até a limpeza completa do trecho.
	set_segment_lamps(origin, seg, false)
	local off_near = landing_x(seg) + 1
	local off_far = seg_x_end(seg) - 1
	if off_far < off_near then off_far = off_near end
	local xmin = origin.x - off_far
	local xmax = origin.x - off_near
	-- mesmas alturas usadas na construção das plataformas
	local platform_heights = {}
	local platform_x = {}
	do
		local start_x = landing_x(seg) + 2
		local end_x = seg_x_end(seg) - 3
		local height = 3
		for x = start_x, end_x, 5 do
			table.insert(platform_x, x)
			table.insert(platform_heights, height)
			if height == 3 then height = 6
			else height = 3
			end
		end
	end
	for _, mob_name in ipairs(mobs) do
		local pos
		-- 50% de chance de nascer sobre uma plataforma
		if #platform_x > 0 and math.random() < 0.5 then
			local i = math.random(#platform_x)
			pos = {x = origin.x - (platform_x[i] + 1), y = origin.y + platform_heights[i] + 1, z = origin.z}
		else pos = {x = math.random(xmin, xmax), y = origin.y + 1, z = origin.z}
		end
		local obj = c.add_entity(pos, mob_name)
		if obj then
			table.insert(data.alive_mobs, obj)
			local le = obj:get_luaentity()
			if le then
				le.gc_owner = pname
				le.gc_seg = seg
			end
		end
	end
	data.mobs_remaining = #data.alive_mobs
end

-- Movimento em trilho: trava o eixo Z do jogador (que é fixo por natureza
-- no motor mt2d) deixando-o andar apenas para frente/para trás (eixo X,
-- único eixo horizontal que o input do jogador realmente controla) e
-- pular (eixo Y).
local RAIL_EPSILON = 0.02

local function apply_rail_movement(player, data)
	local mtplayer = mt2d.user[player:get_player_name()]
	if not mtplayer or not mtplayer.object then return end
	local obj = mtplayer.object
        local pos = obj:get_pos()
	if not pos then return end
	local rail_z = data.origin.z
	local vel = obj:get_velocity()
	if vel and vel.z ~= 0 then obj:set_velocity({x = vel.x, y = vel.y, z = 0}) end
	if math.abs(pos.z - rail_z) > RAIL_EPSILON then obj:set_pos({x = pos.x, y = pos.y, z = rail_z}) end
end

-- Checkpoints: chegar no bloco luminoso do fim do trecho + agachar
local CHECKPOINT_EPSILON = 0.6

-- Altura máxima (acima do chão, origin.y) em que o jogador ainda é
-- considerado "em pé sobre o bloco" luminoso. Os blocos de fim/pouso de
-- trecho ficam no chão (y = origin.y), mas várias plataformas aéreas
-- passam exatamente nas mesmas colunas X — sem checar a altura, o
-- jogador disparava a mensagem só por estar naquele X, mesmo pulando ou
-- andando em cima de uma plataforma alta.
local CHECKPOINT_Y_EPSILON = 2

local function reached_checkpoint(player, origin, seg)
	local mtplayer = mt2d.user[player:get_player_name()]
	if not mtplayer or not mtplayer.object then return false end
	local obj = mtplayer.object
        local pos = obj:get_pos()
	if not pos then return false end
	if math.abs(pos.y - origin.y) > CHECKPOINT_Y_EPSILON then return false end
	local checkpoint_x = origin.x - end_marker_x(seg)
	return math.abs(pos.x - checkpoint_x) <= CHECKPOINT_EPSILON
end

-- Chegou no bloco de POUSO do próprio trecho (usado para voltar ao
-- trecho anterior, uma vez que o trecho atual esteja limpo).
local function reached_landing(player, origin, seg)
	local mtplayer = mt2d.user[player:get_player_name()]
	if not mtplayer or not mtplayer.object then return false end
	local obj = mtplayer.object
        local pos = obj:get_pos()
	if not pos then return false end
	if math.abs(pos.y - origin.y) > CHECKPOINT_Y_EPSILON then return false end
	local landing_x_pos = origin.x - landing_x(seg)
	return math.abs(pos.x - landing_x_pos) <= CHECKPOINT_EPSILON
end

local function teleport_to_landing(player, origin, seg)
	local mtplayer = mt2d.user[player:get_player_name()]
	player:set_pos({x = origin.x - landing_x(seg), y = origin.y + 1.5, z = origin.z})
	if mtplayer then
		-- +1.5 (não +1): a caixa de colisão da entidade "grandchaos:player"
		-- tem ymin=-1 relativo à posição, e o topo do chão fica em
		-- origin.y+0.5 (nodes ocupam ±0.5 ao redor de y inteiro). Com
		-- +1 a base da colisão ficava em origin.y, cravada meio bloco
		-- dentro do chão/lâmpada.
		local pos = {x = origin.x - landing_x(seg), y = origin.y + 1.5, z = origin.z}
		mtplayer.object:set_pos(pos)
		mtplayer.object:set_velocity({x = 0, y = 0, z = 0})
		-- a câmera fica 5 unidades à frente no eixo Z (mesma convenção
		-- usada em mt2d.new_player: cam.z = obj.z + 5).
		mtplayer.cam:set_pos({x = pos.x, y = pos.y, z = pos.z + 5})
	end
end

-- Teleporta para o bloco luminoso de FIM de um trecho — usado ao voltar
-- para o trecho anterior, já que "voltar" deve trazer o jogador para
-- perto da parede (onde está o checkpoint de avanço daquele trecho), e
-- não para o início/pouso dele, que fica longe, do outro lado do trecho.
local function teleport_to_end(player, origin, seg)
	local mtplayer = mt2d.user[player:get_player_name()]
	player:set_pos({x = origin.x - end_marker_x(seg), y = origin.y + 1.5, z = origin.z})
	if mtplayer then
		local pos = {x = origin.x - end_marker_x(seg), y = origin.y + 1.5, z = origin.z}
		mtplayer.object:set_pos(pos)
		mtplayer.object:set_velocity({x = 0, y = 0, z = 0})
		mtplayer.cam:set_pos({x = pos.x, y = pos.y, z = pos.z + 5})
	end
end

-- Tempo (em segundos) que uma plataforma fica "vazada" (não sólida)
-- depois que o jogador agacha/desce sobre ela, tempo suficiente para
-- ele cair através dela antes do nó voltar a ser sólido.
local PLATFORM_PASS_TIME = 0.5
local function round(v) return math.floor(v + 0.5) end

-- Se o jogador estiver em pé sobre uma plataforma (grandchaos:trunk_platform)
-- e apertar agachar ou "para baixo", o nó vira passável por um instante,
-- deixando-o cair através dela; depois volta a ser sólido sozinho.
local function try_drop_through_platform(player, data, drop_pressed)
	if data.dropping or not drop_pressed then return end
	local mtplayer = mt2d.user[player:get_player_name()]
	local obj = mtplayer and mtplayer.object
	local pos = obj and obj:get_pos()
	if not pos then return end
	-- A base da caixa de colisão fica em pos.y - 1 (ver comentário em
	-- teleport_to_landing); o topo do nó de plataforma logo abaixo dos
	-- pés, quando o jogador está em pé sobre ele, fica então em
	-- pos.y - 1.5.
	local under_y = round(pos.y - 1.5)
	local base_x = round(pos.x)
	-- Confere não só o bloco exatamente abaixo do centro do jogador, mas
	-- também os vizinhos (-1/+1 em x): a caixa de colisão tem largura
	-- própria, então perto da emenda entre dois blocos da mesma
	-- plataforma o bloco que realmente sustenta o jogador pode não ser
	-- o que corresponde ao arredondamento exato de pos.x.
	local swapped = {}
	for dx = -1, 1 do
		local under = {x = base_x + dx, y = under_y, z = data.origin.z}
		if c.get_node(under).name == "grandchaos:trunk_platform" then
			c.set_node(under, {name = "grandchaos:trunk_platform_ghost", param2 = 12})
			table.insert(swapped, under)
		end
	end
	if #swapped == 0 then return end
	data.dropping = true
	local pname = player:get_player_name()
	c.after(PLATFORM_PASS_TIME, function()
		for _, under in ipairs(swapped) do
			if c.get_node(under).name == "grandchaos:trunk_platform_ghost" then
				c.set_node(under, {name = "grandchaos:trunk_platform", param2 = 12})
			end
		end
		local d2 = players_data[pname]
		if d2 then d2.dropping = false end
	end)
end

-- Tempo (em segundos) que uma plataforma fica "vazada" (não sólida)
-- depois que o jogador pula por baixo dela, tempo suficiente pra ele
-- atravessar de baixo pra cima antes do nó voltar a ser sólido. Mesmo
-- valor de PLATFORM_PASS_TIME, mas com nome próprio pra deixar claro que
-- é o timer da direção contrária (subir, não descer).
local JUMP_PASS_TIME = 0.5

-- Se o jogador estiver logo abaixo de uma plataforma (grandchaos:trunk_platform)
-- e apertar pular ou "pra cima", o nó vira passável por um instante,
-- deixando-o subir através dela; depois volta a ser sólido sozinho.
-- Mesmo mecanismo de try_drop_through_platform, só que checando o nó
-- ACIMA da cabeça em vez do nó abaixo dos pés.
local function try_jump_through_platform(player, data, jump_pressed)
	if data.jumping_through or not jump_pressed then return end
	local mtplayer = mt2d.user[player:get_player_name()]
	local obj = mtplayer and mtplayer.object
	local pos = obj and obj:get_pos()
	if not pos then return end
	-- O topo da caixa de colisão da entidade "grandchaos:player" fica em
	-- pos.y + 0.7 (ver collisionbox em mt2d_entities.lua); o nó de
	-- plataforma logo acima da cabeça, quando o jogador está encostado
	-- nele por baixo, fica então em pos.y + 1.2.
	local above_y = round(pos.y + 1.2)
	local base_x = round(pos.x)
	-- Confere também os vizinhos em x (-1/+1), pelo mesmo motivo de
	-- try_drop_through_platform: perto da emenda entre dois blocos da
	-- plataforma, o bloco relevante pode não ser o do arredondamento
	-- exato de pos.x.
	local swapped = {}
	for dx = -1, 1 do
		local above = {x = base_x + dx, y = above_y, z = data.origin.z}
		if c.get_node(above).name == "grandchaos:trunk_platform" then
			c.set_node(above, {name = "grandchaos:trunk_platform_ghost", param2 = 12})
			table.insert(swapped, above)
		end
	end
	if #swapped == 0 then return end
	data.jumping_through = true
	local pname = player:get_player_name()
	c.after(JUMP_PASS_TIME, function()
		for _, above in ipairs(swapped) do
			if c.get_node(above).name == "grandchaos:trunk_platform_ghost" then
				c.set_node(above, {name = "grandchaos:trunk_platform", param2 = 12})
			end
		end
		local d2 = players_data[pname]
		if d2 then d2.jumping_through = false end
	end)
end

local restore_arena
-- Ponto de spawn configurado no servidor (ou fallback fixo). Não é
-- necessariamente seguro: pode estar num chunk ainda não carregado, ou
-- por coincidência do mapgen, dentro de terreno sólido.
local function raw_spawn_pos()
	return c.setting_get_pos("static_spawnpoint") or {x = 0, y = 10, z = 0}
end
-- Sobe (e, se preciso, desce) a partir de `pos` procurando um lugar onde
-- o jogador realmente CABE E FICA EM PÉ: pés e cabeça livres, com um nó
-- sólido logo abaixo servindo de chão (sem essa 3ª checagem, o primeiro
-- "buraco de ar" encontrado podia estar flutuando bem acima do terreno,
-- fazendo o jogador cair de queda livre até achar chão de verdade). Só é
-- confiável DEPOIS que a coluna foi emergida (ver safe_teleport_to_spawn);
-- antes disso, nós não carregados voltam como "ignore" (não-sólido), o
-- que pareceria "seguro"/"livre" sem ainda ter sido gerado.
local function find_air_pocket(pos, max_scan)
	max_scan = max_scan or 30
	local function passable(p)
		local n = c.registered_nodes[c.get_node(p).name]
		return n and not n.walkable
	end
	local function solid(p)
		local n = c.registered_nodes[c.get_node(p).name]
		return n and n.walkable
	end
	local function is_standable(feet)
		local head = {x = feet.x, y = feet.y + 1, z = feet.z}
		local floor = {x = feet.x, y = feet.y - 1, z = feet.z}
		return passable(feet) and passable(head) and solid(floor)
	end
	for dy = 0, max_scan do
		local feet = {x = pos.x, y = pos.y + dy, z = pos.z}
		if is_standable(feet) then return feet end
	end
	for dy = 1, max_scan do
		local feet = {x = pos.x, y = pos.y - dy, z = pos.z}
		if is_standable(feet) then return feet end
	end
	-- Não achou nenhum trecho com chão sólido embaixo dentro do alcance:
	-- pelo menos garante um bolsão de ar (pés+cabeça livres), sem exigir
	-- piso, pra não ficar cravado dentro de pedra — mas isso ainda pode
	-- cair de queda livre, então é só o último recurso mesmo.
	for dy = 0, max_scan do
		local feet = {x = pos.x, y = pos.y + dy, z = pos.z}
		local head = {x = feet.x, y = feet.y + 1, z = feet.z}
		if passable(feet) and passable(head) then return feet end
	end
	return {x = pos.x, y = pos.y + max_scan, z = pos.z}
end
-- Garante que a coluna em volta do spawn esteja carregada (emerge_area)
-- antes de checar solidez, acha um lugar seguro perto dela e só então
-- teleporta o jogador (real + entidade 2D). `after_teleport` roda depois
-- do teleporte — é aí que cada chamador deve restaurar/limpar a arena.
local function safe_teleport_to_spawn(player, pname, after_teleport)
	local base = raw_spawn_pos()
	c.emerge_area(
		{x = base.x - 1, y = base.y - 30, z = base.z - 1},
		{x = base.x + 1, y = base.y + 30, z = base.z + 1},
		function(_, _, remaining)
			if remaining ~= 0 then return end
			local p = c.get_player_by_name(pname)
			if not p then return end
			local safe = find_air_pocket(base)
			local spawn_pos = {x = safe.x, y = safe.y + 0.5, z = safe.z}
			p:set_pos(spawn_pos)
			p:set_physics_override({jump = 1})
			local mtplayer = mt2d.user[pname]
			if mtplayer and mtplayer.object then
				mtplayer.object:set_pos(spawn_pos)
				mtplayer.object:set_velocity({x = 0, y = 0, z = 0})
				mtplayer.cam:set_pos({x = spawn_pos.x, y = spawn_pos.y, z = spawn_pos.z + 5})
			end
			if after_teleport then after_teleport() end
		end
	)
end
-- Loop principal: trilho + checkpoints
c.register_globalstep(function(dtime)
	for pname, data in pairs(players_data) do
		local player = c.get_player_by_name(pname)
		if not player then players_data[pname] = nil
		elseif phase_active(data) then
			apply_rail_movement(player, data)
			-- Detecta a "borda de subida" do agachar (passou de solto para
			-- pressionado neste tick), para não disparar teleporte repetido
			-- enquanto o jogador segura sneak — importante agora que ida e
			-- volta podem ficar bem próximas uma da outra.
			local ctrl = player:get_player_control()
			local sneak_now = (ctrl and ctrl.sneak) or false
			local sneak_edge = sneak_now and not data.was_sneaking
			data.was_sneaking = sneak_now
			try_drop_through_platform(player, data, sneak_now or (ctrl and ctrl.down))
			try_jump_through_platform(player, data, ctrl and (ctrl.jump or ctrl.up))
			-- Modo Versus: morre ao cair em um dos buracos-armadilha.
			-- Fora dos buracos o chão é sólido em toda a arena (o jogador
			-- nunca fica abaixo do nível do chão), então basta detectar
			-- que a entidade 2D caiu abaixo do plano do chão para saber
			-- que ela está dentro de um buraco. `vs_dead` evita chamar
			-- set_hp(0) em todo tick enquanto o jogador ainda está caindo.
			-- O limiar era origin.y - 1: como a altura normal de jogo é
			-- origin.y + 1.5, isso deixava o jogador cair uns 2.5 blocos
			-- livremente dentro do buraco antes de sequer ser detectado
			-- (dava tempo de pegar bastante velocidade de queda, o que
			-- fazia a câmera parecer "cair bastante" mesmo já congelando
			-- a entidade depois). Usando origin.y (bem próximo do topo do
			-- chão, origin.y + 0.5), a queda é pega quase assim que o
			-- jogador atravessa o buraco.
			if data.vs and not data.vs_dead then
				local mtplayer_vs = mt2d.user[pname]
				local vs_pos = mtplayer_vs and mtplayer_vs.object and mtplayer_vs.object:get_pos()
				if vs_pos and vs_pos.y < data.origin.y then
					data.vs_dead = true
					player:set_hp(0)
				end
			end
			-- Modo Versus: só precisa de trilho + travessia de plataformas
			-- (acima). Não há trechos/checkpoints/chefe no Versus, então
			-- pula todo o restante, que é exclusivo da fase 1 solo.
			if not data.vs then
				local seg = data.stage
				if reached_checkpoint(player, data.origin, seg) then
					local cleared = stage_cleared(data)
					local state = cleared and "go" or "wait"
					if data.checkpoint_state ~= state then
						data.checkpoint_state = state
						if cleared then c.chat_send_player(pname, S("Sneak to continue"))
						else c.chat_send_player(pname, S("Defeat all enemies in this segment for the block to light up!"))
						end
					end
					if cleared and sneak_edge then
						if seg < TOTAL_SEGMENTS then
							local next_seg = seg + 1
							data.stage = next_seg
							data.checkpoint_state = nil
							data.landing_state = nil
							teleport_to_landing(player, data.origin, next_seg)
							-- Só gera a onda/chefe na primeira vez que o trecho é
							-- visitado; se o jogador já tinha limpado esse trecho
							-- antes (voltou e está indo para frente de novo), os
							-- blocos já estão acesos e nada precisa ser refeito.
							if not data.segment_started[next_seg] then
								data.segment_started[next_seg] = true
								if next_seg <= NUM_WAVE_SEGMENTS then spawn_wave(player, next_seg)
								elseif next_seg == TOTAL_SEGMENTS then grandchaos.spawn_boss(player)
								end
							end
						else
							-- Fim do trecho do chefe: encerra a fase por completo, igual ao
							-- primeiro bloco luminoso (landing do trecho 1) — mas antes sai do
							-- modo 2D, já que aqui (diferente do primeiro portal) o jogador
							-- deve voltar ao movimento normal em 3D.
							data.finished = true
							if mt2d.user[pname] then mt2d.to_3dplayer(player) end
							safe_teleport_to_spawn(player, pname, function()
								local d = players_data[pname]
								if d then
									restore_arena(d)
									players_data[pname] = nil
								end
								local p = c.get_player_by_name(pname)
								if p then c.chat_send_player(pname, S("You completed Stage 1 and left the stage.")) end
							end)
						end
					end
				else data.checkpoint_state = nil
				end
				-- Primeiro bloco luminoso da fase: sair da fase.
				if seg == 1 and reached_landing(player, data.origin, 1) then
					if data.landing_state ~= "exit" then
						data.landing_state = "exit"
						c.chat_send_player(pname, S("Sneak to leave the stage and return to the start"))
					end
					if sneak_edge then
					    data.finished = true
					    c.chat_send_player(pname, S("You left the stage."))
					    -- Igual à saída pelo bloco do chefe: sem isso o jogador
					    -- ficava preso no modo 2D ao sair pelo primeiro portal,
					    -- já que o mt2d só é desativado explicitamente aqui.
					    safe_teleport_to_spawn(player, pname, function()
						local d = players_data[pname]
						if d then
						    restore_arena(d)
						    players_data[pname] = nil
						end
					    end)
					    c.after(1.6, function()
						local p = c.get_player_by_name(pname)
						if p and mt2d.user[pname] then
						    mt2d.to_3dplayer(p)
						end
					    end)
					end
				-- Bloco de POUSO do trecho atual: uma vez aceso (trecho limpo),
				-- serve para voltar ao FIM do trecho anterior (não ao pouso
				-- dele, que fica longe, do outro lado do trecho anterior).
				elseif seg > 1 and reached_landing(player, data.origin, seg) then
					local cleared = stage_cleared(data)
					if cleared then
						if data.landing_state ~= "go" then
							data.landing_state = "go"
							c.chat_send_player(pname, S("Sneak to go back to the previous segment"))
						end
						if sneak_edge then
							local prev_seg = seg - 1
							data.stage = prev_seg
							data.checkpoint_state = nil
							data.landing_state = nil
							teleport_to_end(player, data.origin, prev_seg)
						end
					else if data.landing_state ~= "wait" then
							data.landing_state = "wait"
							c.chat_send_player(pname, S("Defeat all enemies in this segment for the block to light up!"))
						end
					end
				else data.landing_state = nil
				end
			end -- fim de "if not data.vs then"
		end
	end
end)


-- Chefe
function grandchaos.spawn_boss(player)
	local pname = player:get_player_name()
	local data = players_data[pname]
	if not data then return end
	local origin = data.origin
	-- Trecho do chefe: os blocos ficam apagados até o Ent ser derrotado.
	data.mobs_remaining = 1
	set_segment_lamps(origin, TOTAL_SEGMENTS, false)
	local xstart = landing_x(TOTAL_SEGMENTS)
	local xend = seg_x_end(TOTAL_SEGMENTS)
	local boss_x = origin.x - (xstart + math.floor(math.max(1, xend - xstart) / 2))
	-- O chefe nasce na sua própria trilha (entre a parede e a trilha do
	-- jogador/plataformas), não na mesma trilha do jogador.
	local pos = {x = boss_x, y = origin.y + 1, z = origin.z + BOSS_RAIL_OFFSET}
	data.boss = c.add_entity(pos, "grandchaos:boss")
	local le = data.boss and data.boss:get_luaentity()
	if le then
		le.gc_owner = pname
		le.gc_seg = TOTAL_SEGMENTS
	end
	c.chat_send_player(pname, S("[Stage 1] The Ent Guardian has appeared! This is the stage's final battle."))
end

function grandchaos.on_mob_death(self)
	local pname = self and self.gc_owner
	local data = pname and players_data[pname]
	if not data then return end
	data.mobs_remaining = math.max(0, (data.mobs_remaining or 1) - 1)
	if data.mobs_remaining <= 0 and data.stage == self.gc_seg then
		set_segment_lamps(data.origin, self.gc_seg, true)
		c.chat_send_player(pname, S("All enemies in the segment have been defeated! The lit block turned on."))
	end
end

function grandchaos.on_boss_death(self)
	local owner = self and self.gc_owner
	if owner then
		local data = players_data[owner]
		if data then
			data.mobs_remaining = 0
			set_segment_lamps(data.origin, TOTAL_SEGMENTS, true)
		end
	end
	for pname, data in pairs(players_data) do
		if data.stage == TOTAL_SEGMENTS and not data.finished then
			local player = c.get_player_by_name(pname)
			if player then c.chat_send_player(pname, S("[Stage 1 Complete!] You defeated the Ent Guardian of the Aria Forest!")) end
		end
	end
end

-- Restauração do terreno original
-- A arena é sempre construída no mesmo ponto fixo (y=500), uma altura que
-- normalmente nunca foi gerada pelo mapgen. Da primeira vez que a fase
-- roda ali, get_node() para essas posições devolve "ignore" (chunk não
-- carregado/gerado), e isso acaba sendo salvo em saved_nodes como o "nó
-- original". O motor não deixa mais colocar "ignore" de volta no mapa
-- (ver erro "Not allowing to place CONTENT_IGNORE" no debug.txt) — sem
-- esse tratamento, o bloco sintético da fase (ex.: grandchaos:floor2,
-- sólido e indestrutível) ficava permanentemente ali, e o jogador podia
-- ficar preso/sufocando nesse lixo em partidas futuras. Nesses casos, o
-- correto é restaurar para "air" em vez de tentar restaurar para "ignore".
restore_arena = function(data)
	if not data.saved_nodes then return end
	for _, entry in pairs(data.saved_nodes) do
		local node = entry.node
		if node.name == "ignore" then node = {name = "air"} end
		c.set_node(entry.pos, node)
	end
end

function grandchaos.reset_phase(player)
	local pname = player:get_player_name()
	local data = players_data[pname]
	if not data then c.chat_send_player(pname, S("You don't have an active stage to restart.")) return end
	if data.alive_mobs then for _, obj in ipairs(data.alive_mobs) do if obj and obj:get_luaentity() then obj:remove() end end end
	if data.boss and data.boss:get_luaentity() then data.boss:remove() end
	player:set_physics_override({jump = 1})
	restore_arena(data)
	players_data[pname] = nil
	c.chat_send_player(pname, S("Stage 1 has been reset. The original terrain was restored."))
end


-- Restaura o estado inicial das lâmpadas de todos os trechos: mesmo
-- estado com que nascem em build_arena (trecho 1 já aceso, por não ter
-- inimigos; os demais apagados até serem limpos).
local function reset_all_lamps(origin)
	for seg = 1, TOTAL_SEGMENTS do
		set_end_lamp(origin, seg, seg == 1)
		if seg > 1 then set_landing_lamp(origin, seg, false) end
	end
end

-- Reseta só o ESTADO da corrida (mobs, chefe, progresso, lâmpadas) —
-- não mexe em posição/HP do jogador. Pode ser chamado a qualquer
-- momento, inclusive antes da entidade visual 2D existir de novo.
local function reset_run_state(player, data)
	if data.alive_mobs then for _, obj in ipairs(data.alive_mobs) do if obj and obj:get_luaentity() then obj:remove() end end end
	if data.boss and data.boss:get_luaentity() then data.boss:remove() end
	data.alive_mobs = {}
	data.mobs_remaining = 0
	data.stage = 1
	data.segment_started = {[1] = true}
	data.checkpoint_state = nil
	data.landing_state = nil
	data.was_sneaking = false
	data.boss = nil
	data.finished = false
	reset_all_lamps(data.origin)
	spawn_wave(player, 1) -- trecho 1 é vazio: só reacende a lâmpada
end

-- Reinicia a fase a partir do trecho 1 (mantendo o terreno já
-- construído): reseta o estado da corrida e teleporta a entidade
-- visual 2D atual para o bloco luminoso de pouso do trecho 1. Assume
-- que mt2d.user[pname].object já existe — para uso manual (fora do
-- fluxo de morte, onde a entidade some e demora a voltar; ver o
-- register_on_respawnplayer abaixo para esse caso).
function grandchaos.restart_phase(player)
	local pname = player:get_player_name()
	local data = players_data[pname]
	if not data then return end
	reset_run_state(player, data)
	player:set_hp(20)
	player:set_physics_override({jump = 2})
	teleport_to_landing(player, data.origin, 1)
	c.chat_send_player(pname, S("Stage 1 has been restarted from the beginning."))
end

-- Ao morrer, se houver uma fase em andamento: reinicia o estado da
-- corrida de imediato e assume o controle do respawn.
--
-- IMPORTANTE: o mt2d (ver mt2d.lua) recria a câmera/entidade visual 2D
-- (mt2d.user[pname].object) de forma ASSÍNCRONA, ~1s depois do respawn
-- (core.after(1, mt2d.new_player, player)), usando a posição REAL
-- do jogador (player:get_pos()) como base. Ou seja, não adianta mover
-- a entidade visual antiga aqui (ela está fadada a ser descartada) —
-- é preciso mover o jogador "de verdade" (player:set_pos) desde já, e
-- só reposicionar/ajustar a entidade visual com precisão depois que o
-- mt2d terminar de recriá-la.
c.register_on_respawnplayer(function(player)
	local pname = player:get_player_name()
	local data = players_data[pname]
	if not data or not phase_active(data) then return false end

	if data.vs then
		-- Morte no modo Versus (ex.: caiu em um dos buracos-armadilha):
		-- NÃO chama reset_run_state, pois essa função mexe em inimigos e
		-- lâmpadas da fase 1 solo (que usa o mesmo `origin`, mas é uma
		-- fase totalmente diferente) — aqui devolve os DOIS jogadores da
		-- partida ao seu próprio ponto de spawn (maselamp) na arena
		-- Versus, com vida cheia — não só quem morreu.
		local vs_spawn = data.vs_spawn
		player:set_pos(vs_spawn)
		player:set_hp(20)
		player:set_physics_override({jump = 2})
		-- Acha o adversário (outro jogador com vs=true na mesma arena) e
		-- o teleporta de volta ao próprio spawn dele também. Como esse
		-- jogador não morreu de verdade, a entidade visual 2D dele
		-- continua existindo (não é recriada pelo mt2d), então dá para
		-- reposicionar tudo (jogador real, entidade e câmera) de imediato,
		-- sem precisar do c.after(1.2, ...) usado abaixo para quem morreu.
		for other_pname, other_data in pairs(players_data) do
			if other_pname ~= pname and other_data.vs and other_data.origin == data.origin then
				local other_player = c.get_player_by_name(other_pname)
				if other_player then
					local other_spawn = other_data.vs_spawn
					other_player:set_pos(other_spawn)
					other_player:set_hp(20)
					other_player:set_physics_override({jump = 2})
					other_data.vs_dead = false
					local other_mt = mt2d.user[other_pname]
					if other_mt and other_mt.object then
						other_mt.object:set_pos(other_spawn)
						other_mt.object:set_velocity({x = 0, y = 0, z = 0})
						other_mt.cam:set_pos({x = other_spawn.x, y = other_spawn.y, z = other_spawn.z + 5})
					end
					c.chat_send_player(other_pname, S("Your opponent died! Back to your spawn."))
				end
			end
		end

		c.after(1.2, function()
			local p = c.get_player_by_name(pname)
			local data2 = players_data[pname]
			if not p or not data2 then return end
			p:set_hp(20)
			data2.vs_dead = false
			local mtplayer = mt2d.user[pname]
			if mtplayer and mtplayer.object then
				mtplayer.object:set_pos(data2.vs_spawn)
				mtplayer.object:set_velocity({x = 0, y = 0, z = 0})
				mtplayer.cam:set_pos({x = data2.vs_spawn.x, y = data2.vs_spawn.y, z = data2.vs_spawn.z + 5})
			end
			c.chat_send_player(pname, S("You fell into a pit! Back to your spawn."))
		end)
		return true
	end

	reset_run_state(player, data)

	local origin = data.origin
	local pos = {x = origin.x - landing_x(1), y = origin.y + 1.5, z = origin.z}
	player:set_pos(pos)
	player:set_hp(20)
	player:set_physics_override({jump = 2})

	-- Espera o mt2d recriar a entidade visual (ver comentário acima)
	-- antes de fazer o ajuste fino de posição/câmera.
	c.after(1.2, function()
		local p = c.get_player_by_name(pname)
		local data2 = players_data[pname]
		if not p or not data2 then return end
		p:set_hp(20)
		teleport_to_landing(p, data2.origin, 1)
		c.chat_send_player(pname, S("You died! Stage 1 has been restarted from the beginning."))
	end)

	return true
end)

-- Ao reconectar (reentrar no servidor/mod), se houver uma fase em
-- andamento: o mt2d recria mtplayer.object de forma assíncrona usando
-- player:get_pos() como base (mesmo mecanismo do respawn — ver comentário
-- acima do register_on_respawnplayer). Como o jogador REAL nunca é movido
-- durante a fase (só a entidade visual 2D é), ele fica parado onde estava
-- antes de /gcstart, fora do corredor — e o mt2d recria a entidade lá,
-- fazendo o jogador cair. Aqui corrigimos os dois: movemos o jogador real
-- de imediato para o trecho/estágio em que ele estava, e reajustamos a
-- entidade visual/câmera depois que o mt2d terminar de recriá-la.
c.register_on_joinplayer(function(player)
	local pname = player:get_player_name()
	local data = players_data[pname]
	if not data or not phase_active(data) then return end

	local origin = data.origin
	if data.vs then
		-- Reconexão durante o modo Versus: não há segmento/landing da fase
		-- 1 solo aqui — volta o jogador ao seu próprio ponto de spawn na
		-- arena Versus.
		local pos = data.vs_spawn
		player:set_pos(pos)
		player:set_physics_override({jump = 2})
		c.after(1.2, function()
			local p = c.get_player_by_name(pname)
			local data2 = players_data[pname]
			if not p or not data2 then return end
			p:set_pos(data2.vs_spawn)
			local mtplayer = mt2d.user[pname]
			if mtplayer and mtplayer.object then
				mtplayer.object:set_pos(data2.vs_spawn)
				mtplayer.object:set_velocity({x = 0, y = 0, z = 0})
				mtplayer.cam:set_pos({x = data2.vs_spawn.x, y = data2.vs_spawn.y, z = data2.vs_spawn.z + 5})
			end
			c.chat_send_player(pname, S("Versus resumed."))
		end)
		return
	end
	local seg = data.stage
	local pos = {x = origin.x - landing_x(seg), y = origin.y + 1.5, z = origin.z}
	player:set_pos(pos)
	player:set_physics_override({jump = 2})
	c.after(1.2, function()
		local p = c.get_player_by_name(pname)
		local data2 = players_data[pname]
		if not p or not data2 then return end
		teleport_to_landing(p, data2.origin, data2.stage)
		c.chat_send_player(pname, S("Stage 1 resumed from segment @1.", data2.stage))
	end)
end)

-- Mostra a HUD de instrução (topo central) para quem entra e ainda não
-- tem uma fase em andamento — quem está no meio de uma fase já passou
-- do estágio de "/join2d ou /gcstart", então não precisa ver a dica.
c.register_on_joinplayer(function(player)
	local pname = player:get_player_name()
	local data = players_data[pname]
	if data and phase_active(data) then return end
	grandchaos.show_hint(player)
end)

-- Início da fase
--
-- IMPORTANTE: mt2d.new_player() cria a entidade da câmera na hora, mas
-- a entidade visual 2D propriamente dita (mtplayer.object, usada
-- abaixo) só é criada e associada a mt2d.user[pname] pelo
-- mt2d_entities.lua um tick de servidor depois (via on_activate/on_step
-- da câmera) — não é síncrono. Por isso, quando o 2D precisa ser
-- ativado aqui mesmo (ao dar /gcstart sem ter usado /join2d antes), a
-- lógica de início da fase só pode continuar depois que
-- mt2d.user[pname].object realmente existir; daí o "espera" por
-- polling abaixo em vez de seguir direto.
function grandchaos.start_phase(player, ref_pos)
	local pname = player:get_player_name()
	if players_data[pname] then c.chat_send_player(pname, S("You already have a stage in progress. Use /gcreset to restart.")) return end

	local function do_start_phase()
		local mtplayer = mt2d.user[pname]
		if not mtplayer or not mtplayer.object then c.chat_send_player(pname, S("2D mode has not been initialized yet.")) return end
		local obj = mtplayer.object
		local base = ref_pos or obj:get_pos()
	local origin = vector.round({x = 0, y = 500, z = 0})
	c.chat_send_player(pname, S("[grandchaos] Welcome to the Aria Forest — Stage 1!"))
	local half_w = math.floor(WIDTH / 2)
	c.emerge_area(
	    {x = origin.x - (WALL_THICKNESS + TOTAL_SEGMENTS * SEG_SPAN + 3), y = origin.y, z = origin.z - half_w},
	    {x = origin.x, y = origin.y + HEIGHT + 2, z = origin.z + half_w},
	    function(blockpos, action, remaining)
		if remaining ~= 0 then return end
		local saved_nodes, total_len = build_arena(origin)
		players_data[pname] = {
		    origin = origin,
		    stage = 1,
		    alive_mobs = {},
		    mobs_remaining = 0,
		    segment_started = {[1] = true}, -- trecho 1 já é "iniciado" (spawn_wave chamado abaixo)
		    saved_nodes = saved_nodes,
		    total_len = total_len,
		    finished = false,
		    checkpoint_state = nil,
		    landing_state = nil,
		}
		local inv = player:get_inventory()
		if not inv:contains_item("main", "grandchaos:sword") then inv:add_item("main", "grandchaos:sword") end
		player:set_hp(20)
		player:set_physics_override({jump = 2})
		local mtplayer = mt2d.user[player:get_player_name()]
		local pos = {x = origin.x - landing_x(1), y = origin.y + 1.5, z = origin.z}
		player:set_pos(pos)
		if mtplayer then
			mtplayer.object:set_pos(pos)
			mtplayer.object:set_velocity({x = 0, y = 0, z = 0})
			mtplayer.cam:set_pos({x = pos.x, y = pos.y, z = pos.z + 5})
		end
		spawn_wave(player, 1)
	    end
	)
	local inv = player:get_inventory()
	if not inv:contains_item("main", "grandchaos:sword") then inv:add_item("main", "grandchaos:sword") end
	player:set_hp(20)
	player:set_physics_override({jump = 2})
	end -- fim de do_start_phase
	-- Se o jogador já está em modo 2D (por ex. usou /join2d antes),
	-- segue direto. Caso contrário, ativa o 2D agora e espera a
	-- entidade visual (mtplayer.object) ser criada antes de continuar
	-- (ver comentário grande acima da função).
	if mt2d.user[pname] and mt2d.user[pname].object then do_start_phase() return end
	if not mt2d.user[pname] then mt2d.new_player(player) end
	local tries = 0
	local function wait_for_2d()
		tries = tries + 1
		local mtplayer = mt2d.user[pname]
		if mtplayer and mtplayer.object then do_start_phase()
		elseif tries < 40 then  c.after(0.1, wait_for_2d) -- tenta por até ~4 segundos
		else c.chat_send_player(pname, S("Could not activate 2D mode. Try again with: /gcstart"))
		end
	end
	c.after(0.1, wait_for_2d)
end


-- Comandos de chat
-- IMPORTANTE: assim como em grandchaos.start_phase, mt2d.new_player() cria
-- a entidade da câmera na hora, mas a entidade visual 2D (mtplayer.object)
-- só é criada um tick de servidor depois. Por isso esperamos por polling
-- até que AMBOS os jogadores tenham sua entidade 2D pronta antes de montar
-- a arena Versus (build_vs_arena usa mt2d.user[...].object para posicionar
-- os dois jogadores).
c.register_chatcommand("gcvs", {
	description = S"Starts GrandChaos Versus Mode (PvP)",
	func = function(name)
		local players = c.get_connected_players()
		if #players ~= 2 then return false, S"Exactly two players must be online." end
		local function do_start_vs()
			local origin = vector.round({x = 0, y = 500, z = 0})
			-- Mesma lógica do /gcstart: só constrói a arena e posiciona os
			-- jogadores DEPOIS que o terreno da região estiver totalmente
			-- carregado/gerado (remaining == 0). Sem isso, a arena Versus
			-- fica ~100 blocos além do fim da fase 1 (vs_start = total_len
			-- + 100), uma região que pode nunca ter sido carregada — os
			-- set_node de build_vs_arena não colocam nada em mapblocks
			-- não carregados, e os jogadores acabavam sendo teleportados
			-- para o vazio, caindo do céu.
			local total_len = WALL_THICKNESS + TOTAL_SEGMENTS * SEG_SPAN + 3
			local vs_start = total_len + 100
			local half_w = math.floor(WIDTH / 2)
			c.emerge_area(
				{x = origin.x - (vs_start + SEG_LEN + WALL_THICKNESS + 3), y = origin.y, z = origin.z - half_w - 3},
				{x = origin.x - (vs_start - WALL_THICKNESS - 3), y = origin.y + HEIGHT + 2, z = origin.z + half_w},
				function(blockpos, action, remaining)
					if remaining ~= 0 then return end
					local ok, err = build_vs_arena(origin)
					if not ok then c.chat_send_player(name, err) return end
					for _, p in ipairs(players) do grandchaos.hide_hint(p:get_player_name()) end
					c.chat_send_player(name, S"GrandChaos Versus started!")
				end
			)
		end
		for _, p in ipairs(players) do if not mt2d.user[p:get_player_name()] then mt2d.new_player(p) end end
		local tries = 0
		local function wait_for_2d()
			tries = tries + 1
			local ready = true
			for _, p in ipairs(players) do
				local mtplayer = mt2d.user[p:get_player_name()]
				if not (mtplayer and mtplayer.object) then ready = false end
			end
			if ready then do_start_vs()
			elseif tries < 40 then c.after(0.1, wait_for_2d)
			else c.chat_send_player(name, S"Could not activate 2D mode. Try again with: /gcvs")
			end
		end
		wait_for_2d()
		return true
	end
})

c.register_chatcommand("gcstart", {
	description = S("Starts grandchaos Stage 1 (Aria Forest)"),
	func = function(name)
  		local player = c.get_player_by_name(name)
  		if not player then return false, S("Player not found.") end
  		grandchaos.hide_hint(name)
   		grandchaos.start_phase(player)
   		return true
	end,
})

c.register_chatcommand("gcreset", {
	description = S("Cancels and restores the terrain of grandchaos Stage 1"),
	func = function(name)
  	        local player = c.get_player_by_name(name)
		if not player then return false, S("Player not found.") end
		grandchaos.reset_phase(player)
		return true
	end,
})

c.register_chatcommand("gcportal", {
	description = S("Gives an Aria Forest Portal that starts Stage 1 when used"),
	func = function(name)
		local player = c.get_player_by_name(name)
		if not player then return false, S("Player not found.") end
		player:get_inventory():add_item("main", "grandchaos:portal")
		return true, S("You received an Aria Forest Portal. Place it and right-click to begin.")
	end,
})

c.log("action", "[grandchaos] mod carregado")
