-- grandchaos/entities.lua
-- Entidades inimigas da Fase 1: Slime (básico), Arqueiro (à distância) e o chefe Ent.

local function get_nearest_player(self, range)
	local pos = self.object:get_pos()
	local nearest, dist = nil, range
	for _, player in ipairs(core.get_connected_players()) do
		local ppos = player:get_pos()
		local d = vector.distance(pos, ppos)
		if d < dist then nearest, dist = player, d end
	end
	return nearest, dist
end

local function get_player_visual(player)
	if not player then return nil end
	local name = player:get_player_name()
	if mt2d and mt2d.user and mt2d.user[name] and mt2d.user[name].object then return mt2d.user[name].object end
	return player
end

-- Vira o inimigo para encarar o alvo usando só o eixo X (o eixo do
-- trilho). Antes isso considerava também o eixo Z (vector.direction), o
-- que fazia sentido enquanto todo mundo compartilhava a mesma trilha (Z
-- fixo = mesma diferença sempre). Agora que um mob pode estar numa trilha
-- de Z diferente da do jogador (ex.: o chefe, que anda entre a parede e a
-- trilha de plataformas), usar o Z real deixaria o modelo "de lado",
-- torto, em vez de olhar reto para a esquerda/direita como o visual 2D
-- (mt2d) espera. Resultado é idêntico ao de antes nos casos em que Z já
-- era igual (slime, arqueiro).
local function face_target(self, target_pos)
	local pos = self.object:get_pos()
	local dx = target_pos.x - pos.x
	local yaw = (dx >= 0) and (-math.pi / 2) or (math.pi / 2)
	self.object:set_yaw(yaw)
end

-- Trava o inimigo no seu próprio "trilho" (eixo Z fixo), assim como o
-- jogador: ele só pode se mover para frente/para trás (eixo X), que é o
-- mesmo eixo em que o corredor da fase avança.
local RAIL_EPSILON = 0.02
local function rail_lock_entity(self)
	local pos = self.object:get_pos()
	if not pos then return end
	if not self.rail_z then self.rail_z = pos.z end
	if math.abs(pos.z - self.rail_z) > RAIL_EPSILON then
		self.object:set_pos({x = pos.x, y = pos.y, z = self.rail_z})
	end
end

-- Distância "de trilho": só considera o eixo X, já que Z está sempre fixo
-- tanto no inimigo quanto no jogador.
local function rail_distance_x(pos, tpos) return tpos.x - pos.x end
-- Distância vertical: usada pra evitar que o inimigo "acerte" o jogador só porque ele está pulando por cima
local function rail_distance_y(pos, tpos) return math.abs(tpos.y - pos.y) end

-- Faz a câmera do jogador tremer verticalmente (eixo Y) por um tempo.
-- Usa set_eye_offset alternando o sinal do deslocamento a cada "step" e
-- zera o offset no final para não deixar a câmera deslocada.
local function shake_camera(player, duration, strength, step_time)
	if not player or not player:is_player() then return end
	duration = duration or 0.5
	strength = strength or 0.4
	step_time = step_time or 0.05
	local elapsed = 0
	local sign = 1
	local function step()
		if not player or not player:is_player() then return end
		if elapsed >= duration then
			player:set_eye_offset({x = 0, y = 0, z = 0}, {x = 0, y = 0, z = 0})
			return
		end
		sign = -sign
		player:set_eye_offset({x = 0, y = sign * strength, z = 0}, {x = 0, y = sign * strength, z = 0})
		elapsed = elapsed + step_time
		core.after(step_time, step)
	end
	step()
end

local GRAVITY = -20

local function apply_gravity(self)
	local pos = self.object:get_pos()
	if not pos then return end
	local below = {x = pos.x, y = pos.y, z = pos.z} -- nó logo abaixo dos pés
	local node = core.get_node_or_nil(below)
	if not node then return end
	local def = core.registered_nodes[node.name]
	if def and def.walkable then self.object:set_acceleration({x = 0, y = 0, z = 0}) -- no chão
	else self.object:set_acceleration({x = 0, y = GRAVITY, z = 0}) -- caindo
	end
end

-- Solta itens de drop na posição informada (ou na posição atual do objeto,
-- se pos não for passado). Usado ao matar slime, arqueiro e o chefe.
local function drop_items(pos, itemstrings)
	if not pos then return end
	for _, itemstring in ipairs(itemstrings) do core.add_item(pos, itemstring) end
end

-- Exibe um efeito de impacto temporário sobre o inimigo
local function show_hit_effect(pos)
	local effect = core.add_entity({x = pos.x, y = pos.y + 0.5, z = pos.z + 0.5}, "grandchaos:hit_effect")
	if effect then
		core.after(0.12, function() if effect and effect:get_luaentity() then effect:remove() end end)
	end
end

core.register_entity("grandchaos:hit_effect", {
	initial_properties = {
		physical = false,
		collide_with_objects = false,
		pointable = false,
		visual = "sprite",
		visual_size = {x = 1, y = 1},
		textures = {"gc_hit_effect.png"},
		use_texture_alpha = true,
		glow = 14,
		static_save = false,
	},
	on_activate = function(self)
		self.object:set_armor_groups({immortal = 1})
	end,
})

-- SLIME: inimigo básico corpo a corpo, pouca vida, avança e ataca
local use_alpha
	if core.features and core.features.use_texture_alpha_string then use_alpha = "blend"
	else use_alpha = true
end

core.register_entity("grandchaos:slime", {
	initial_properties = {
		hp_max = 18,
		physical = true,
		collide_with_objects = true,
		collisionbox = {-0.35, 0.0, -0.35, 0.35, 0.6, 0.35},
		visual_size = {x = 20, y = 20},
		visual        = "mesh",
		mesh          = "planslime.glb",
		use_texture_alpha = use_alpha,
		textures = {"planaria_slime2.png", "planaria_slime2.png"},
		makes_footstep_sound = false,
	},
	hp = 18,
	max_hp = 18,
	damage = 3,
	speed = 1.6,
	attack_range = 0.5,
	attack_cooldown = 0,
	is_gc_mob = true,
	-- leve recuo + salto a cada ataque
	recoil_timer = 0,
	recoil_duration = 0.25, -- quanto tempo o impulso do recuo dura
	recoil_speed = 1.5,     -- velocidade horizontal do recuo (para trás)
	hop_speed = 4,          -- velocidade vertical do salto
	-- recuo ao receber dano
	hit_knockback_speed = 2.0, -- maior que recoil_speed (1.5)
	hit_hop_speed = 5.0,       -- maior que hop_speed (4)
	-- Salto em investida
	charge_timer = 0,
	charge_distance = 5,
	charge_delay = 1.5,
	charge_speed = 9.0,
	charge_hop_speed = 5.0,
	-- drops ao morrer
	drops = {"grandchaos:copper_coin 2"},
	animation = { speed_normal = 1, stand_start = 0, stand_end = 0, walk_start = 0, walk_end = 0.63 },
	sounds = { footstep = "nh_slime", random = "slime_som", damage = "nh_slimehurt" },
	sound_timer = 0,
	sound_interval = 8,
	-- controle de estado da animação
	anim_state = nil,
	-- função auxiliar: só troca animação se o estado mudou
	set_anim = function(self, name)
		if self.anim_state == name then return end
		self.anim_state = name
		local a = self.animation
		if name == "stand" then self.object:set_animation({x = a.stand_start, y = a.stand_end}, a.speed_normal, 0, true)
		elseif name == "walk" then self.object:set_animation({x = a.walk_start, y = a.walk_end}, a.speed_normal, 0, true)
		end
	end,
	on_activate = function(self, staticdata)
		self.object:set_armor_groups({fleshy = 100})
		self:set_anim("stand")
	end,
	on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir, damage)
		show_hit_effect(self.object:get_pos())
		self.hp = self.hp - (damage or 1)
		if self.sounds and self.sounds.damage then
			core.sound_play(self.sounds.damage, {object = self.object, max_hear_distance = 10}, true)
		end
		-- recuo ao receber dano
		if dir then
			self.object:set_velocity({x = dir.x * self.hit_knockback_speed, y = self.hit_hop_speed, z = 0})
			self.recoil_timer = self.recoil_duration
		end
		if self.hp <= 0 then
			drop_items(self.object:get_pos(), self.drops)
			self.object:remove()
			if grandchaos then grandchaos.on_mob_death(self) end
		end
	end,
	on_step = function(self, dtime)
		self.attack_cooldown = math.max(0, self.attack_cooldown - dtime)
		self.recoil_timer = math.max(0, self.recoil_timer - dtime)
		--self.charge_timer = math.max(0, self.charge_timer - dtime)
		rail_lock_entity(self)
		apply_gravity(self)
		self.sound_timer = self.sound_timer + dtime
		if self.sound_timer >= self.sound_interval then
			self.sound_timer = 0
			if self.sounds and self.sounds.random and math.random() < 0.5 then
				core.sound_play(self.sounds.random, {object = self.object, max_hear_distance = 10}, true)
			end
		end
		-- enquanto o recuo do golpe está ativo, mantém o impulso (deixa a
		-- gravidade curvar o salto) e não deixa a IA de movimento sobrescrevê-lo
		if self.recoil_timer > 0 then self:set_anim("stand") return end
		local target = get_nearest_player(self, 14)
		if not target then
			self.object:set_velocity({x = 0, y = 0, z = 0})
			self:set_anim("stand")
			return
		end
		local visual = get_player_visual(target)
		local pos = self.object:get_pos()
		local tpos = visual:get_pos()
		face_target(self, tpos)
		local dx = rail_distance_x(pos, tpos)
		local d = math.abs(dx)
		local dy = rail_distance_y(pos, tpos)
		-- acumula tempo com o jogador próximo
		if d <= self.charge_distance and dy <= 1.75 then self.charge_timer = self.charge_timer + dtime
		else self.charge_timer = 0
		end
		local in_melee_range = d <= self.attack_range and dy <= 1.75 -- ~2 blocos de tolerância vertical
		-- investida em salto
		if self.charge_timer >= self.charge_delay then
			self.charge_timer = 0
			local dir_x = dx > 0 and 1 or -1
			self.object:set_velocity({x = dir_x * self.charge_speed, y = self.charge_hop_speed, z = 0})
			self.recoil_timer = 0.45
			self:set_anim("walk")
			return
		end
		if not in_melee_range then
		    local dir_x = dx > 0 and 1 or -1
		    self.object:set_velocity({x = dir_x * self.speed, y = self.object:get_velocity().y, z = 0})
		    self:set_anim("walk")
		    -- ... som de passo
		else
		    self.object:set_velocity({x = 0, y = self.object:get_velocity().y, z = 0})
		    self:set_anim("stand")
 		   if self.attack_cooldown <= 0 then
 		       self.attack_cooldown = 1.0
  		      target:punch(self.object, 1.0, {full_punch_interval = 1.0, damage_groups = {fleshy = self.damage}}, nil)
			-- leve recuo + salto ao golpear
			local recoil_dir = (dx > 0) and -1 or 1
			self.object:set_velocity({x = recoil_dir * self.recoil_speed, y = self.hop_speed, z = 0})
			self.recoil_timer = self.recoil_duration
  		   end
		end
	end,
})

-- FLECHA: projétil usado pelo arqueiro
core.register_entity("grandchaos:arrow", {
	initial_properties = {
		hp_max = 1,
		physical = false,
		collide_with_objects = false,
		visual = "sprite",
		visual_size = {x = 0.2, y = 0.2},
		textures = {"gc_spore.png"},
		glow = 3,
	},
	damage = 2,
	timer = 0,
	on_step = function(self, dtime)
		self.timer = self.timer + dtime
		if self.timer > 3 then self.object:remove() return end
		local pos = self.object:get_pos()
		-- Desaparece ao atingir qualquer bloco sólido (não-ar) no seu caminho
		local node = core.get_node_or_nil(pos)
		if node and node.name ~= "air" then self.object:remove() return end
		for _, player in ipairs(core.get_connected_players()) do
			local visual = get_player_visual(player)
			if vector.distance(pos, visual:get_pos()) < 0.1 then
				player:punch(self.object, 1.0, {full_punch_interval = 1.0, damage_groups = {fleshy = self.damage}}, nil)
				self.object:remove()
				return
			end
		end
	end,
})

-- FLECHA: projétil usado pelo arqueiro
core.register_entity("grandchaos:fruit", {
	initial_properties = {
		hp_max = 1,
		physical = false,
		collide_with_objects = false,
		visual = "sprite",
		visual_size = {x = 0.5, y = 0.5},
		textures = {"gc_apple.png"},
		glow = 1,
	},
	damage = 3,
	timer = 0,
	hit_radius = 0.03,      -- tolerância de acerto em X
	hit_radius_z = 1,      -- tolerância de acerto em Z
	hit_feet = -1.1,       -- base do corpo (collisionbox y-min do player: -1, +folga)
	hit_head = 0.9,        -- topo do corpo (collisionbox y-max do player: 0.8, +folga)
	on_step = function(self, dtime)
		self.timer = self.timer + dtime
		if self.timer > 3 then self.object:remove() return end
		local pos = self.object:get_pos()
		for _, player in ipairs(core.get_connected_players()) do
			local visual = get_player_visual(player)
			local ppos = visual:get_pos()
			local dx = math.abs(ppos.x - pos.x)
			local dz = math.abs(ppos.z - pos.z)
			local dy = pos.y - ppos.y -- posição da fruta relativa à origem do personagem
			if dx < self.hit_radius and dz < self.hit_radius_z and dy > self.hit_feet and dy < self.hit_head then
				player:punch(self.object, 1.0, {full_punch_interval = 1.0, damage_groups = {fleshy = self.damage}}, nil)
				self.object:remove()
				return
			end
		end
	end,
})

-- ARQUEIRO: inimigo à distância, mantém distância e atira flechas
core.register_entity("grandchaos:archer", {
	initial_properties = {
		hp_max = 30,
		physical = true,
		collide_with_objects = true,
		collisionbox = {-0.35, 0.0, -0.35, 0.35, 0.6, 0.35},
		visual_size = {x = 1, y = 0.5},
		visual        = "mesh",
		mesh          = "gc_mushiroomkid.glb",
		use_texture_alpha = use_alpha,
		textures = {"gc_mushiroomkid.png", "gc_mushiroomkid.png"},
		makes_footstep_sound = false,
	},
	hp = 30,
	max_hp = 30,
	speed = 1.2,
	preferred_range = 6,
	shoot_cooldown = 0,
	is_gc_mob = true,

	-- animações (frames do character.b3d, reaproveitados no glb)
	anim = {
		stand = {x = 0, y = 79/30},
		walk  = {x = 168 / 30, y = 187 / 30},
		sit   = {x = 81/30, y = 160/30},   -- pose sentada
		punch = {x = 189/30, y = 198/30},  -- animação de "mine"/ataque
		die   = {x = 162/30, y = 166/30},  -- pose deitada (lay)
	},
	sounds = {damage = "db_mushiroom_hurt", die = "db_mushiroom_die"},
	anim_state = nil,

	-- controle de golpes rápidos
	hit_count = 0,
	last_hit_time = 0,
	hit_window = 1,
	hits_to_sit = 5,
	sit_timer = 0,
	sit_duration = 2,
	-- controle da animação de ataque
	punch_timer = 0,
	punch_duration = 0.35, -- quanto tempo a animação de "punch" dura antes de voltar ao normal
	-- leve recuo + salto a cada disparo (dura o mesmo tempo do punch_timer)
	knockback_speed = 1.2, -- velocidade horizontal do recuo (para trás)
	hop_speed = 3.5,       -- velocidade vertical do salto
	-- recuo ao receber dano
	hit_knockback_speed = 1.6, -- maior que knockback_speed (1.2)
	hit_hop_speed = 4.5,       -- maior que hop_speed (3.5)
	-- estado de morte
	dead = false,
	-- drops ao morrer
	drops = {"grandchaos:copper_coin 4"},
	set_anim = function(self, name, force)
		if self.anim_state == name and not force then return end
		self.anim_state = name
		local a = self.anim[name]
		self.object:set_animation({x = a.x, y = a.y}, 1, 0, name ~= "die")
	end,
	on_activate = function(self, staticdata)
		self.object:set_armor_groups({fleshy = 100})
		self:set_anim("stand")
	end,
	on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir, damage)
		if self.dead then return true end
		show_hit_effect(self.object:get_pos())
		core.sound_play(self.sounds.damage, {pos = self.object:get_pos(), max_hear_distance = 12,gain = 1.0})
		-- recuo ao receber dano
		if dir then
			self.object:set_velocity({x = dir.x * self.hit_knockback_speed, y = self.hit_hop_speed, z = 0})
			-- impede a IA de cancelar imediatamente o impulso
			self.punch_timer = math.max(self.punch_timer, 0.25)
		end
		self.hp = self.hp - (damage or 1)
		if self.hp <= 0 then
			self.dead = true
			core.sound_play(self.sounds.die, {pos = self.object:get_pos(), max_hear_distance = 12, gain = 1})
			self.object:set_velocity({x = 0, y = 0, z = 0})
			self.object:set_acceleration({x = 0, y = 0, z = 0})
			self.object:set_properties({physical = false})
			self:set_anim("die", true)
			local drop_pos = self.object:get_pos()
			local drops = self.drops
			core.after(1.2, function()
				drop_items(drop_pos, drops)
				if self.object then self.object:remove() end
				if grandchaos then grandchaos.on_mob_death(self) end
			end)
			return true
		end
		local now = core.get_us_time() / 1e6
		if self.sit_timer <= 0 then
			if (now - self.last_hit_time) <= self.hit_window then self.hit_count = self.hit_count + 1
			else self.hit_count = 1
			end
			self.last_hit_time = now
			if self.hit_count >= self.hits_to_sit then
				self.hit_count = 0
				self.sit_timer = self.sit_duration
				self.punch_timer = 0
				self.object:set_velocity({x = 0, y = self.object:get_velocity().y, z = 0})
				self:set_anim("sit", true)
			end
		end

		return true
	end,

	on_step = function(self, dtime)
		if self.dead then return end
		self.shoot_cooldown = math.max(0, self.shoot_cooldown - dtime)
		rail_lock_entity(self)
		apply_gravity(self)
		-- estado "sentado": trava movimento e ataque até o tempo acabar
		if self.sit_timer > 0 then
			self.sit_timer = math.max(0, self.sit_timer - dtime)
			self.object:set_velocity({x = 0, y = self.object:get_velocity().y, z = 0})
			self:set_anim("sit")
			return
		end
		-- animação de ataque em andamento: segura o "punch" até acabar
		if self.punch_timer > 0 then
			self.punch_timer = math.max(0, self.punch_timer - dtime)
			self:set_anim("punch")
		end
		local target = get_nearest_player(self, 16)
		if not target then
			self.object:set_velocity({x = 0, y = 0, z = 0})
			if self.punch_timer <= 0 then self:set_anim("stand") end
			return
		end
		local visual = get_player_visual(target)
		local pos = self.object:get_pos()
		local tpos = visual:get_pos()
		face_target(self, tpos)
		local dx = rail_distance_x(pos, tpos)
		local d = math.abs(dx)
		local moving = false
		if self.punch_timer > 0 then moving = false -- em recuo: mantém o impulso do salto/recuo, sem novo controle de movimento
		elseif d > self.preferred_range + 1 then
			local dir_x = dx > 0 and 1 or -1
			self.object:set_velocity({x = dir_x * self.speed, y = self.object:get_velocity().y, z = 0})
			moving = true
		elseif d < self.preferred_range - 1.5 then
			local dir_x = dx > 0 and -1 or 1
			self.object:set_velocity({x = dir_x * self.speed, y = self.object:get_velocity().y, z = 0})
			moving = true
		else
			self.object:set_velocity({x = 0, y = self.object:get_velocity().y, z = 0})
			moving = false
		end
		-- só troca pra stand/walk se não estiver no meio da animação de ataque
		if self.punch_timer <= 0 then self:set_anim(moving and "walk" or "stand") end
		if self.shoot_cooldown <= 0 and d < 16 then
			self.shoot_cooldown = 1.8
			self.punch_timer = self.punch_duration
			self:set_anim("punch", true)
			-- leve recuo + salto ao atirar
			local recoil_dir = (dx > 0) and -1 or 1
			self.object:set_velocity({x = recoil_dir * self.knockback_speed, y = self.hop_speed, z = 0})
			local dir = vector.direction({x = pos.x, y = pos.y + 1.2, z = pos.z}, tpos)
			local arrow = core.add_entity({x = pos.x, y = pos.y + 1.2, z = pos.z}, "grandchaos:arrow")
			if arrow then arrow:set_velocity({x = dir.x * 8, y = dir.y * 8, z = dir.z * 8}) end
		end
	end,
})

-- Ent CHEFE: chefe da fase, muita vida, ataque em área
core.register_entity("grandchaos:boss", {
	initial_properties = {
		hp_max = 160,
		physical = true,
		collide_with_objects = true,
		collisionbox = {-0.5, 0.0, -0.5, 0.5, 4, 0.5},
		visual = "mesh",
		visual_size = {x = 1.8, y = 2.5},
		mesh          = "gc_entboss.glb",
		use_texture_alpha = use_alpha,
		textures = {"gc_entboss2.png", "gc_entboss2.png"},
		makes_footstep_sound = false,
	},
	hp = 160,
	max_hp = 160,
	damage = 4,
	speed = 2,
	attack_range = 1,
	attack_cooldown = 0,
	slam_cooldown = 0,
	is_boss = true,
	is_gc_mob = true,
	-- animações (frames do character.b3d, reaproveitados no glb)
	anim = {
		stand = {x = 0, y = 79/30},
		walk  = {x = 168 / 30, y = 187 / 30},
		sit   = {x = 81/30, y = 160/30},   -- pose sentada
		punch = {x = 189/30, y = 198/30},  -- animação de ataque
		die   = {x = 162/30, y = 166/30},  -- pose deitada (lay)
	},
	sounds = {damage = "default_metal2", die = "db_devil_die"},
	anim_state = nil,
	-- controle do estado do golpe sísmico
	state = "idle", -- "idle" | "sitting"
	jump_timer = 0,
	jump_duration = 0.45,
	jump_speed = 7,
	sit_timer = 0,
	sit_duration = 0.5,
	slam_target_pos = nil,
	-- rajada de frutos
	spore_range = 16,
	spore_cooldown = 4, -- tempo até a primeira rajada ficar disponível
	spore_burst_interval = 6, -- intervalo entre rajadas
	spore_shots_left = 0,
	spore_shot_timer = 0,
	spore_shot_gap = 0.25, -- tempo entre cada tiro da rajada
	-- controle da animação de ataque
	punch_timer = 0,
	punch_duration = 0.35, -- ajuste conforme a duração real do "MINE" no mesh
	dead = false, -- estado de morte
	-- drops ao morrer: moedas de prata + o troféu da fase
	drops = {"grandchaos:copper_coin 10", "grandchaos:silver_coin 5", "grandchaos:sword2", "grandchaos:trophy 1"},
	set_anim = function(self, name, force)
		if self.anim_state == name and not force then return end
		self.anim_state = name
		local a = self.anim[name]
		self.object:set_animation({x = a.x, y = a.y}, 1, 0, name ~= "die")
	end,
	on_activate = function(self, staticdata)
		self.object:set_armor_groups({fleshy = 100})
		core.chat_send_all("[Fase 1] O Ent Guardião desperta! Prepare-se!")
		self:set_anim("stand")
	end,
	on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir, damage)
		if self.dead then return true end
		show_hit_effect(self.object:get_pos())
		core.sound_play(self.sounds.damage, {pos = self.object:get_pos(), max_hear_distance = 12,gain = 1.0})
		-- Recuo apenas em X e Y
		if dir then self.object:set_velocity({x = dir.x * 2.0, y = math.max(0, dir.y) * 2.0 + 3.5, z = 0}) end
		self.hp = self.hp - (damage or 1)
		if grandchaos then grandchaos.on_boss_damaged(self) end
			if self.hp <= 0 then
				self.dead = true
				core.sound_play(self.sounds.die, {pos = self.object:get_pos(), max_hear_distance = 12, gain = 1})
				self.state = "idle"
				self.object:set_velocity({x = 0, y = 0, z = 0})
				self.object:set_acceleration({x = 0, y = 0, z = 0})
				self.object:set_properties({physical = false})
				self:set_anim("die", true)
				local drop_pos = self.object:get_pos()
				local drops = self.drops
				core.after(1.2, function()
					drop_items(drop_pos, drops)
					if self.object then self.object:remove() end
					if grandchaos then grandchaos.on_boss_death(self) end
			end)
			return true
		end
		return true
	end,
	-- executa o golpe em área de fato (chamado após a sentada)
	do_slam = function(self)
		core.chat_send_all("[Ent] Golpe Sísmico!")
		local center = self.object:get_pos()
		for _, player in ipairs(core.get_connected_players()) do
			local ppos = player:get_pos()
			local pd = math.abs(rail_distance_x(center, ppos))
			-- verifica se o jogador está apoiado no chão
			local below = {x = ppos.x, y = ppos.y, z = ppos.z}
			local node = core.get_node_or_nil(below)
			local def = node and core.registered_nodes[node.name]
			local on_ground = def and def.walkable
			if pd < 4.5 and on_ground then player:punch(self.object, 1, {full_punch_interval = 1, damage_groups = {fleshy = 4}}, nil) end
		end
		self.state = "idle"
	end,
	-- dispara um único esporo em direção ao alvo
	shoot_spore = function(self, tpos)
		local pos = self.object:get_pos()
		local origin = {x = pos.x, y = pos.y + 1.5, z = tpos.z}
		local dir = vector.direction({x = origin.x, y = origin.y, z = tpos.z}, {x = tpos.x, y = tpos.y, z = tpos.z})
		local arrow = core.add_entity(origin, "grandchaos:fruit")
		if arrow then arrow:set_velocity({x = dir.x * 8, y = dir.y * 8, z = 0}) end
		self.punch_timer = self.punch_duration
		self:set_anim("punch", true)
	end,
	on_step = function(self, dtime)
		if self.dead then return end
		self.attack_cooldown = math.max(0, self.attack_cooldown - dtime)
		self.slam_cooldown = math.max(0, self.slam_cooldown - dtime)
		self.spore_cooldown = math.max(0, self.spore_cooldown - dtime)
		rail_lock_entity(self)
		apply_gravity(self)
		if self.state == "jumping" then
			self.jump_timer = self.jump_timer - dtime
			-- mantém a animação normal durante o salto
			self:set_anim("stand")
			-- quando tocar o chão, começa a sentar
			local pos = self.object:get_pos()
			local below = vector.offset(pos, 0, -0.1, 0)
			local node = core.get_node_or_nil(below)
			local def = node and core.registered_nodes[node.name]
			if def and def.walkable and self.object:get_velocity().y <= 0 then
				self.state = "sitting"
				self.sit_timer = self.sit_duration
				self.object:set_velocity({x = 0, y = 0, z = 0})
				self:set_anim("sit", true)

				-- tremor de câmera (vertical) no instante em que o boss
				-- aterrissa e senta, simulando o impacto no chão
				local shake_range = 10
				local center = self.object:get_pos()
				for _, player in ipairs(core.get_connected_players()) do
					local pd = math.abs(rail_distance_x(center, player:get_pos()))
					if pd < shake_range then shake_camera(player, 0.5, 0.4, 0.05) end
				end
			end
			return
		end
		-- Enquanto está sentando, trava tudo e só espera o timer
		if self.state == "sitting" then
			self.object:set_velocity({x = 0, y = self.object:get_velocity().y, z = 0})
			self:set_anim("sit")
			self.sit_timer = self.sit_timer - dtime
			if self.sit_timer <= 0 then self:do_slam() end
			return -- não faz mais nada nesse step
		end
		-- animação de ataque em andamento: segura o "punch" até acabar
		if self.punch_timer > 0 then self.punch_timer = math.max(0, self.punch_timer - dtime) end
		local target = get_nearest_player(self, 20)
		if not target then
			self.object:set_velocity({x = 0, y = 0, z = 0})
			if self.punch_timer <= 0 then self:set_anim("stand") end
			return
		end
		local visual = get_player_visual(target)
		local pos = self.object:get_pos()
		local tpos = visual:get_pos()
		face_target(self, tpos)
		local dx = rail_distance_x(pos, tpos)
		local d = math.abs(dx)
		-- Processa a rajada de esporos (tem prioridade sobre movimento comum,
		-- mas não bloqueia o boss como a sentada)
		if self.spore_shots_left > 0 then
			self.spore_shot_timer = self.spore_shot_timer - dtime
			if self.spore_shot_timer <= 0 then
				self:shoot_spore(tpos)
				self.spore_shots_left = self.spore_shots_left - 1
				self.spore_shot_timer = self.spore_shot_gap
			end
		end
		if d > self.attack_range then
			local dir_x = dx > 0 and 1 or -1
			self.object:set_velocity({x = dir_x * self.speed, y = self.object:get_velocity().y, z = 0})
			if self.punch_timer <= 0 then self:set_anim("walk") end
		else
			self.object:set_velocity({x = 0, y = self.object:get_velocity().y, z = 0})
			if self.attack_cooldown <= 0 then
				self.attack_cooldown = 1.3
				self.punch_timer = self.punch_duration
				self:set_anim("punch", true)
				target:punch(self.object, 1.0, {full_punch_interval = 1.0, damage_groups = {fleshy = self.damage}}, nil)
			elseif self.punch_timer <= 0 then self:set_anim("stand") end
		end
		-- Ataque especial: entra em estado "sentando" antes do golpe em área
		if self.slam_cooldown <= 0 and d < 4.5 then
			self.slam_cooldown = 8
			self.state = "jumping"
			self.jump_timer = self.jump_duration
			self.punch_timer = 0
			self.object:set_velocity({x = 0, y = self.jump_speed, z = 0})
			return
		end
		-- Rajada de 3 frutos: dispara quando o cooldown zera e o alvo está no alcance
		if self.spore_cooldown <= 0 and self.spore_shots_left <= 0 and d < self.spore_range then
			self.spore_cooldown = self.spore_burst_interval
			self.spore_shots_left = 3
			self.spore_shot_timer = 0 -- primeiro tiro sai já no próximo step
		end
	end,
})
