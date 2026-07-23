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
grandchaos.attack_cost     = 15    -- custo em MP do ataque espacial (sempre esse valor, mesmo que a carga ultrapasse)
grandchaos.attack_cooldown = 1.5   -- tempo mínimo (segundos) entre ataques

-- Barra branca de "carga" (segurar E): sobrepõe a barra de MP e vai
-- enchendo enquanto aux1 fica pressionado. O especial só dispara quando
-- ela alcança o nível atual da barra de MP (e, claro, com MP suficiente).
grandchaos.charge_tick_time = 0.1  -- intervalo (segundos) entre incrementos da barra branca
grandchaos.charge_rate      = 1    -- quanto a barra branca avança a cada tick de charge_tick_time

-- Estado interno (local a este arquivo)
local hud_ids         = {}
local bg_ids          = {}
local charge_hud_ids   = {}
local regen_timer      = {}
local last_attack_time = {}
local charge_amount    = {}
local charge_timer     = {}
local charge_particle_ids = {}

-- Helpers de leitura/escrita do MP (persistido nos metadados do jogador)
local function get_mp(player) return player:get_meta():get_int("grandchaos:mp") end

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

-- Atualiza a barra branca de carga (mesmo sistema de "meio-ícones" da statbar).
-- number = 0 esconde a barra na prática (nenhum ícone desenhado).
local function update_charge_hud(player)
	local name = player:get_player_name()
	local id = charge_hud_ids[name]
	if id then player:hud_change(id, "number", charge_amount[name] or 0) end
end

-- API pública (mp_bar.get_mp / set_mp / add_mp, dentro de `grandchaos`)
function grandchaos.get_mp(player) return get_mp(player) end

function grandchaos.set_mp(player, value)
	local v = set_mp_raw(player, value)
	update_hud(player)
	return v
end

function grandchaos.add_mp(player, amount) return grandchaos.set_mp(player, get_mp(player) + amount) end

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

-- Barra de vida do Boss (topo da tela)
grandchaos.boss_bar_range = 20   -- distância (nós) pra barra aparecer ao se aproximar
grandchaos.boss_bar_width = 400  -- LARGURA em pixels da sua textura de fundo/preenchimento

-- nomes de exibição por entidade registrada (mapeie outros bosses aqui se criar mais)
grandchaos.boss_display_names = {["grandchaos:boss"] = "Ent Guardião"}

local boss_hud          = {}  -- [playername] = {bg=id, fill=id, name=id}
local player_boss       = {}  -- [playername] = luaentity do boss atualmente exibido
local boss_check_timer  = {}  -- [playername] = acumulador pra throttle da busca

local function boss_hp_fraction(boss)
	local max_hp = boss.max_hp or 1
	local hp = math.max(0, boss.hp or 0)
	return math.min(1, hp / max_hp)
end

local function boss_display_name(boss)
	local ent_name = boss.object and boss.object:get_entity_name()
	return (ent_name and grandchaos.boss_display_names[ent_name]) or "Chefe"
end

function grandchaos.show_boss_bar(player, boss)
	local name = player:get_player_name()
	if boss_hud[name] then return end -- já tem uma barra mostrada
	local frac = boss_hp_fraction(boss)
	local half_w = grandchaos.boss_bar_width / 2
	boss_hud[name] = {
		bg = player:hud_add({
			type = "image",
			position = {x = 0.5, y = 0},
			offset = {x = 0, y = 55},
			text = "gc_bossbar_bg.png",
			alignment = {x = 0, y = 0}, -- ancora a borda ESQUERDA no offset
			scale = {x = 1, y = 1},
		}),
		name = player:hud_add({
			type = "text",
			position = {x = 0.5, y = 0},
			offset = {x = 0, y = 33},
			text = boss_display_name(boss),
			number = 0xFFFFFF,
			alignment = {x = 0, y = 0},
		}),
		fill = player:hud_add({
			type = "image",
			position = {x = 0.5, y = 0},
			offset = {x = -half_w, y = 55},
			text = "gc_bossheart.png",
			alignment = {x = 1, y = 0}, -- mesma âncora esquerda: cresce pra direita
			scale = {x = frac, y = 1},
		}),
	}
end


function grandchaos.hide_boss_bar(player)
	local name = player:get_player_name()
	local ids = boss_hud[name]
	if not ids then return end
	if ids.name then player:hud_remove(ids.name) end
	if ids.bg then player:hud_remove(ids.bg) end
	if ids.fill then player:hud_remove(ids.fill) end
	boss_hud[name] = nil
end

-- chamado pelo entities.lua (on_punch do boss) a cada hit -- atualiza na hora,
-- sem esperar o próximo tick de checagem de proximidade
function grandchaos.on_boss_damaged(boss)
    c.chat_send_all("on_boss_damaged!")
    local matched = 0
    for pname, tracked in pairs(player_boss) do
        c.chat_send_all(tostring(tracked == boss) ..
            " | tracked=" .. tostring(tracked) ..
            " boss=" .. tostring(boss)
        )
        if tracked == boss then
            matched = matched + 1
            local player = c.get_player_by_name(pname)
            if player then
                grandchaos.update_boss_bar(player, boss)
            end
        end
    end
    c.chat_send_all("matched=" .. matched)
end

function grandchaos.update_boss_bar(player, boss)
    local name = player:get_player_name()

    c.chat_send_player(name, "update: "..tostring(boss_hp_fraction(boss)))

    local ids = boss_hud[name]
    if not ids then
        c.chat_send_player(name, "[DEBUG] sem boss_hud")
        return
    end

    local frac = boss_hp_fraction(boss)
    player:hud_change(ids.fill, "scale", {x = frac, y = 1})

    c.chat_send_player(name, ("scale = %.2f"):format(frac))
end

-- chamado pelo entities.lua quando o boss morre -- some a barra na hora
function grandchaos.on_boss_death(boss)
	for pname, tracked in pairs(player_boss) do
		if tracked == boss then
			local player = c.get_player_by_name(pname)
			if player then grandchaos.hide_boss_bar(player) end
			player_boss[pname] = nil
		end
	end
end

-- procura o boss mais próximo dentro do alcance (usado só pra decidir
-- quando MOSTRAR/ESCONDER a barra; a atualização de HP em si vem dos hooks acima)
local function find_nearby_boss(player)
	local pos = player:get_pos()
	local r = grandchaos.boss_bar_range
	local minp = {x = pos.x - r, y = pos.y - r, z = pos.z - r}
	local maxp = {x = pos.x + r, y = pos.y + r, z = pos.z + r}
	local nearest, nearest_d
	for _, obj in ipairs(c.get_objects_in_area(minp, maxp)) do
		if not obj:is_player() then
			local ent = obj:get_luaentity()
			if ent and ent.is_boss and not ent.dead then
				local d = vector.distance(pos, obj:get_pos())
				if not nearest or d < nearest_d then
					nearest, nearest_d = ent, d
				end
			end
		end
	end
	return nearest
end

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
		type = "image",
		position = {x = 0.5, y = 1},
		offset = {x = 0, y = -76}, -- mesma altura da barra de MP
		text = "gc_barsbackground.png",
		scale = {x = 1, y = 1},
		alignment = {x = 0, y = 0},
	})
	hud_ids[name] = player:hud_add({
		type = "statbar",
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
	-- Barra branca de carga: MESMO offset/size/direction/alignment da barra
	-- de MP, só que com uma textura branca semitransparente. Como é
	-- adicionada DEPOIS da barra de MP, o motor a desenha por cima.
	-- number = 0 no início => nenhum ícone aparece (barra "escondida").
	charge_hud_ids[name] = player:hud_add({
		type = "statbar",
		position = {x = 0.5, y = 1},
		offset = {x = 25, y = -88},
		text = "gc_mp_charge.png", -- ícone branco/semitransparente (mesmo tamanho de gc_mp.png)
		number = 0,
		item = grandchaos.max_mp,
		direction = 0,
		size = {x = 24, y = 24},
		alignment = {x = -1, y = -1},
	})
	regen_timer[name] = 0
	last_attack_time[name] = 0
	charge_amount[name] = 0
	charge_timer[name] = 0
	boss_check_timer[name] = 0
end)

c.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	hud_ids[name] = nil
	bg_ids[name] = nil
	charge_hud_ids[name] = nil
	regen_timer[name] = nil
	last_attack_time[name] = nil
	charge_amount[name] = nil
	charge_timer[name] = nil
	if charge_particle_ids[name] then
		c.delete_particlespawner(charge_particle_ids[name])
		charge_particle_ids[name] = nil
	end
	grandchaos.hide_boss_bar(player)
	player_boss[name] = nil    
	boss_check_timer[name] = nil
end)

-- Loop principal: regeneração de MP + escuta da tecla E (aux1) + proximidade com o boss
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
		-- Segurando aux1: a barra branca vai enchendo (1 tick a cada
		-- charge_tick_time), até no máximo max_mp (fica parada ali, cheia,
		-- se o jogador continuar segurando). O especial só dispara quando
		-- SOLTAR a tecla, e só se nesse momento a carga já tiver alcançado
		-- >= attack_cost (15 de 20) e o MP também for >= attack_cost.
		local controls = player:get_player_control()
		if controls.aux1 then
			-- efeito visual: solta partículas brancas em volta do jogador
			-- enquanto ele estiver carregando (só cria o spawner uma vez,
			-- no início do carregamento -- ele fica "vivo" até soltar E)
			if not charge_particle_ids[name] then
				local mtplayer = mt2d.user[name]
				local obj = mtplayer and mtplayer.object
				if obj then
					charge_particle_ids[name] = c.add_particlespawner({
						amount = 60,
						time = 0, -- 0 = infinito, até chamarmos delete_particlespawner
						minpos = {x = -0.4, y = -1,   z = -0.4}, -- 1 node abaixo do jogador
						maxpos = {x = 0.4,  y = 1, z = 0.4},  -- (era y=0/1.6, agora y=-1/0.6)
						minvel = {x = -0.8, y = -0.8, z = -0.8},
						maxvel = {x = 0.8,  y = 2, z = 0.8},
						minacc = {x = 0, y = 0,   z = 0},
						maxacc = {x = 0, y = 0.2, z = 0},
						minexptime = 0.4,
						maxexptime = 0.8,
						minsize = 0.2,
						maxsize = 0.4,
						collisiondetection = false,
						vertical = false,
						texture = "gc_manaparticle2.png", -- textura branca/semitransparente
						glow = 14,
						attached = obj,
					})
				end
			end

			charge_timer[name] = (charge_timer[name] or 0) + dtime
			local changed = false
			while charge_timer[name] >= grandchaos.charge_tick_time do
				charge_timer[name] = charge_timer[name] - grandchaos.charge_tick_time
				if (charge_amount[name] or 0) < grandchaos.max_mp then
					charge_amount[name] = math.min(grandchaos.max_mp, (charge_amount[name] or 0) + grandchaos.charge_rate)
					changed = true
				end
			end
			if changed then update_charge_hud(player) end
		else
			-- soltou (ou nunca segurou) a tecla: para as partículas
			if charge_particle_ids[name] then
				c.delete_particlespawner(charge_particle_ids[name])
				charge_particle_ids[name] = nil
			end
			if (charge_amount[name] or 0) ~= 0 or (charge_timer[name] or 0) ~= 0 then
				-- soltou a tecla: dispara agora se já tinha carga suficiente
				-- (>= attack_cost) e MP suficiente
				local now = c.get_gametime() or 0
				if (charge_amount[name] or 0) >= grandchaos.attack_cost
					and get_mp(player) >= grandchaos.attack_cost
					and now - (last_attack_time[name] or 0) >= grandchaos.attack_cooldown then
					grandchaos.add_mp(player, -grandchaos.attack_cost)
					last_attack_time[name] = now
					grandchaos.ataque_espacial(player)
				end
				-- soltou a tecla: some com a barra branca e zera o progresso
				-- (se soltou com carga insuficiente, ela é descartada mesmo)
				charge_amount[name] = 0
				charge_timer[name] = 0
				update_charge_hud(player)
			end
		end
		-- barra do boss: só checa proximidade a cada 0.5s
		boss_check_timer[name] = (boss_check_timer[name] or 0) + dtime
		if boss_check_timer[name] >= 0.5 then
			boss_check_timer[name] = 0
			local boss = find_nearby_boss(player)
			if boss then
				if player_boss[name] ~= boss then
					player_boss[name] = boss
					grandchaos.show_boss_bar(player, boss)
					grandchaos.update_boss_bar(player, boss)
				end
			elseif player_boss[name] then
				grandchaos.hide_boss_bar(player)
				player_boss[name] = nil
			end
		end
	end
end)
