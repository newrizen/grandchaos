-- grandchaos/mpbar.lua
-- Barra de MP no HUD (posição espelhada em relação à vida), com sistema de
-- regeneração e um "gancho" pronto para o futuro ataque espacial (tecla E / aux1).
--
-- IMPORTANTE: este arquivo é carregado via dofile() a partir do init.lua
-- (igual items.lua / entities.lua) e por isso NÃO recria a tabela
-- `grandchaos` — ela já existe (criada em init.lua) e é só complementada
-- aqui com os campos/funções de MP.

local c = core

-- Configurações (ajuste à vontade)
grandchaos.max_mp          = 20   -- MP máximo do jogador
-- OBS: o motor sempre desenha 1 ícone cheio a cada 2 pontos (igual ao HP),
-- então não há como configurar "pontos por ícone" na barra em si — deixe
-- max_mp como um número par para os ícones baterem certinho.
grandchaos.regen_amount    = 1     -- quanto MP regenera por "tick"
grandchaos.regen_time      = 2     -- intervalo (segundos) entre regenerações
grandchaos.attack_cost     = 15    -- custo em MP do ataque espacial
grandchaos.attack_cooldown = 3.0   -- tempo mínimo (segundos) entre ataques

-- Estado interno (local a este arquivo)
local hud_ids         = {}
local bg_ids          = {}
local regen_timer      = {}
local last_attack_time = {}

-- Helpers de leitura/escrita do MP (persistido nos metadados do jogador)
local function get_mp(player)
	return player:get_meta():get_int("grandchaos:mp")
end

local function set_mp_raw(player, value)
	value = math.max(0, math.min(grandchaos.max_mp, value))
	player:get_meta():set_int("grandchaos:mp", value)
	return value
end

local function update_hud(player)
	local name = player:get_player_name()
	local id = hud_ids[name]
	if id then player:hud_change(id, "number", get_mp(player)) end -- "number" do statbar já é em meio-ícones (2 unidades = 1 ícone cheio), igual ao HP nativo: passamos o MP cru, sem dividir.
end

-- API pública (mp_bar.get_mp / set_mp / add_mp, dentro de `grandchaos`)
function grandchaos.get_mp(player) return get_mp(player) end

function grandchaos.set_mp(player, value)
	local v = set_mp_raw(player, value)
	update_hud(player)
	return v
end

function grandchaos.add_mp(player, amount)
	return grandchaos.set_mp(player, get_mp(player) + amount)
end

-- Placeholder do ataque espacial: substitua o conteúdo desta função
-- pelo efeito real (projétil, partículas, dano em área, etc.)
function grandchaos.ataque_espacial(player)
    local mtplayer = mt2d.user[player:get_player_name()]
    if not mtplayer or not mtplayer.object then return end
    local obj = mtplayer.object
    local pos = obj:get_pos()
    -- pequeno pulo
    local vel = obj:get_velocity()
    obj:set_velocity({x = vel.x, y = 8, z = vel.z})
    c.chat_send_player(player:get_player_name(), "Ataque espacial: Haijin - Lâmina Lunar!")
    -- posição do sprite
    -- mt2d: yaw ≈ 0 = direita, yaw ≈ pi = esquerda
    core.sound_play("gc_specialpunch", {object=obj, gain=0.05, max_hear_distance=16}, true)
    core.after(0.1, function()
    -- animação de soco: liga o "trava" do cam por tempo suficiente
    -- pra animação não ser resetada pro próximo on_step
    local pob = obj:get_luaentity()
    if pob then pob.special_attack_timer = 0.5 end
    core.sound_play("gc_firespecial", {object=obj, gain=1, max_hear_distance=16}, true)
    local yaw = obj:get_yaw() or 0        -- animação de soco
        local facing_left = math.abs(yaw - math.pi) < math.pi / 2
        local sprite_pos
        local minp
        local maxp
        if facing_left then sprite_pos = {x = pos.x + 1, y = pos.y + 1.5, z = pos.z}
        else sprite_pos = {x = pos.x - 1, y = pos.y + 1.5, z = pos.z}
        end
        local sprite = core.add_entity(sprite_pos, "grandchaos:special_attack")
	sprite:set_properties({
	    textures = {facing_left and "gc_special3_left.png" or "gc_special3.png"}, -- espelha horizontalmente quando olha para a esquerda
	    visual_size = {x = 4, y = 4}
	}) 
        -- área do golpe (4x4 blocos)
        minp = {x = sprite_pos.x - 2.3, y = sprite_pos.y - 4,  z = sprite_pos.z - 1}
        maxp = {x = sprite_pos.x + 2.3, y = sprite_pos.y + 4, z = sprite_pos.z + 1}
        for _, obj in ipairs(core.get_objects_in_area(minp, maxp)) do
            if obj ~= player and obj ~= mtplayer.object then obj:punch(player, 1.0, {full_punch_interval = 1, damage_groups = {fleshy = 30}}) end
        end
        core.after(0.6, function() if sprite and sprite:get_pos() then sprite:remove() end end)
    end)
end

core.register_entity("grandchaos:special_attack", {
    initial_properties = {
        physical = false,
        pointable = false,
        visual = "sprite",
        textures = {"gc_special3.png"},
        glow = 14,
        visual_size = {x = 3, y = 4},
        collisionbox = {0,0,0,0,0,0},
        static_save = false,
    },
    on_activate = function(self)
        self.object:set_armor_groups({immortal = 1})
    end,
})

-- HUD: adiciona a barra no lado OPOSTO ao da vida
-- (a barra de vida padrão fica em offset x = -263 ; aqui usamos
--  x = +263 com o mesmo y, que é onde a fome costuma ficar)
c.register_on_joinplayer(function(player)
	local meta = player:get_meta()
	-- inicializa o MP só na primeira vez que o jogador entra
	if meta:get_string("grandchaos:mp_initialized") ~= "true" then
		meta:set_int("grandchaos:mp", grandchaos.max_mp)
		meta:set_string("grandchaos:mp_initialized", "true")
	end
	local name = player:get_player_name()
	bg_ids[name] = player:hud_add({
		hud_elem_type = "image",
		position = {x = 0.5, y = 1},
		offset = {x = 0, y = -76}, -- mesma altura da barra de MP
		text = "gc_barsbackground.png",
		scale = {x = 1, y = 1},
		alignment = {x = 0, y = 0},
	})
	hud_ids[name] = player:hud_add({
		hud_elem_type = "statbar",
		position = {x = 0.5, y = 1},
		offset = {x = 25, y = -88}, -- espelhado em relação à barra de vida
		text = "gc_mp.png",
		-- number/item ficam em meio-ícones, iguais ao HP nativo: passar o
		-- valor cru (sem dividir) faz o motor desenhar 1 ícone a cada 2
		-- pontos de MP automaticamente.
		number = get_mp(player),
		item = grandchaos.max_mp,
		direction = 0,
		size = {x = 24, y = 24},
		alignment = {x = -1, y = -1},
	})
	regen_timer[name] = 0
	last_attack_time[name] = 0
end)

c.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	hud_ids[name] = nil
	bg_ids[name] = nil
	regen_timer[name] = nil
	last_attack_time[name] = nil
end)

-- Loop principal: regeneração de MP + escuta da tecla E (aux1)
c.register_globalstep(function(dtime)
	for _, player in ipairs(c.get_connected_players()) do
		local name = player:get_player_name()
		-- regeneração de MP
		regen_timer[name] = (regen_timer[name] or 0) + dtime
		if regen_timer[name] >= grandchaos.regen_time then
			regen_timer[name] = 0
			if get_mp(player) < grandchaos.max_mp then grandchaos.add_mp(player, grandchaos.regen_amount) end
		end
		-- tecla E = "aux1" no Minetest/Luanti por padrão
		local controls = player:get_player_control()
		if controls.aux1 then
			local now = c.get_gametime() or 0
			if now - (last_attack_time[name] or 0) >= grandchaos.attack_cooldown then
				if get_mp(player) >= grandchaos.attack_cost then
					grandchaos.add_mp(player, -grandchaos.attack_cost)
					last_attack_time[name] = now
					grandchaos.ataque_espacial(player)
				end
			end
		end
	end
end)
