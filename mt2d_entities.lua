minetest.register_entity("grandchaos:cam",{
	hp_max = 99999,
	collisionbox = {0,0,0,0,0,0},
	visual = "sprite",
	textures = {"mt2d_air.png"},
	jump_timer = 0,
	walk_speed = 4,
	run_speed = 8,
	last_left_press = 0,
	last_right_press = 0,
	left_was_down = false,
	right_was_down = false,
	dash_window = 0.25,
	running = 0,
	on_activate=function(self, staticdata)
		self.timer=0
		self.dmgtimer=0
		self.breath=11
		self.user_pos={x=0,y=0,z=0}
		self.powersaving={dir=0,x=0,y=0,timer=0,timeout=0.1,time=0,count=5}
		return self
	end,
	on_step=function(self, dtime)
		if self.powersaving.timeout>0 then
			self.powersaving.timeout=self.powersaving.timeout-dtime
			return self
		elseif not (self.user and mt2d.user[self.username] and mt2d.user[self.username].id==self.id ) then
			self.object:remove()
			return self
		elseif not (self.ob and self.ob:get_luaentity()) then
			local pos=self.object:get_pos()
			self.ob=minetest.add_entity({x=pos.x,y=pos.y+1,z=pos.z-5}, "grandchaos:player")

			self.ob:get_luaentity().user=self.user
			self.ob:get_luaentity().id=self.id
			self.ob:get_luaentity().username=self.username

			self.fly=minetest.check_player_privs(self.username, {fly=true})
			self.noclip=minetest.check_player_privs(self.username, {noclip=true})

			self.ob:set_properties({
				textures={"mt2d_air.png",mt2d.user[self.username].texture},
				nametag=self.username,
				nametag_color="#FFFFFF",
			})

			self.user:set_properties({
				textures="mt2d_air.png",
				nametag="",
			})

			mt2d.user[self.username].object=self.ob
		end

		local pos=self.object:get_pos()
		local pos2=self.ob:get_pos()
		local key=self.user:get_player_control()
		local now = minetest.get_us_time() / 1000000

		if key.left and not self.left_was_down then
		    if now - self.last_left_press <= self.dash_window then self.running = -1 end
		    self.last_left_press = now
		end

		if key.right and not self.right_was_down then
		    if now - self.last_right_press <= self.dash_window then self.running = 1
		    end self.last_right_press = now
		end

		self.left_was_down = key.left
		self.right_was_down = key.right

		if self.running == -1 and not key.left then self.running = 0
		elseif self.running == 1 and not key.right then self.running = 0
		end
		local v=self.ob:get_velocity()
		if not pos2 then
			local user=self.user
			self.object:remove()
			user:set_hp(0)
			return
		end
		local node=minetest.registered_nodes[minetest.get_node({x=pos2.x,y=pos2.y-1,z=0}).name]
		local node2=minetest.registered_nodes[minetest.get_node({x=pos2.x,y=pos2.y+1,z=0}).name]

		if not (node and node2) then return end

		if node.damage_per_second>0 then
			self.dmgtimer=self.dmgtimer+dtime
			if self.dmgtimer>1 then
				self.dmgtimer=0
				mt2d.punch(self.user,self.ob,node.damage_per_second)
			end
		end
--breath
		if node2.drowning>0 then
			self.breath=self.breath-dtime
			self.user:set_breath(self.breath)
			if self.breath<=0 then
				self.breath=0
				self.dmgtimer=self.dmgtimer+dtime
				if self.dmgtimer>1 then
					self.dmgtimer=0
					mt2d.punch(self.user,self.ob,1)
				end
			end
		elseif self.breath<11 then
			self.breath=self.breath+dtime
			self.user:set_breath(self.breath)
		end
--physics
		if node.liquid_viscosity>0 or node.climbable then
			if v.y<-0.1 then v={x = v.x*0.99, y =v.y*0.99, z =v.z*0.99} end
			if not self.floating then
				self.fallingfrom=nil
				self.ob:set_acceleration({x=0,y=0,z=0})
				self.floating=true
			end
		elseif self.floating then
			self.ob:set_acceleration({x=0,y=-20,z =0})
			self.floating=nil
		elseif v.y<0 and not self.fallingfrom then self.fallingfrom=pos.y
		elseif self.fallingfrom and v.y==0 then
			local from=math.floor(self.fallingfrom+0.5)
			local hit=math.floor(pos.y+0.5)
			local d=from-hit
			self.fallingfrom=nil
			if minetest.get_node({x=pos2.x,y=pos2.y-2,z=0}).name~="ignore" and d>=10 then mt2d.punch(self.ob,self.ob,d) end
		end
--input & anim
		local pob=self.ob:get_luaentity()
		local staggered=pob.stagger_timer and pob.stagger_timer>0

		-- solta a trava do último frame do "sneak" assim que o jogador
		-- deixa de segurar shift/S, pra animação poder tocar de novo da
		-- próxima vez que ele agachar parado
		if not (key.sneak or key.down) then pob.sneak_anim_played=false end
		-- solta a trava do som de ataque assim que o jogador para de
		-- segurar o botão, pra poder tocar de novo no próximo golpe
		if not (key.RMB or key.LMB) then pob.punch_anim_played=false end
		if not (pob.special_attack_timer and pob.special_attack_timer>0) then pob.special_attack_anim_played=false end
		-- ao sair do stagger, devolve a gravidade normal ao jogador (durante
		-- o stagger ela fica zerada pra ele ficar "deitado" no chão sem cair)
		-- e restaura a colisão física (durante o stagger ele fica intangível
		-- aos mobs, ver register_on_punchplayer)
		if self.was_staggered and not staggered then
			self.was_staggered=nil
			self.ob:set_acceleration({x=0,y=-20,z=0})
			self.user:set_properties({collide_with_objects=true})
			self.ob:set_properties({collide_with_objects=true})
		end
		if staggered then self.was_staggered=true end

		if self.ob:get_luaentity().dead or mt2d.attach[self.username] then
			self.object:set_velocity({x=((pos2.x-pos.x)*10)+self.user_pos.x,y=(-0.5+(pos2.y-pos.y))*10,z=(5-(pos.z-pos2.z))*10})
			return self
			elseif staggered then
				-- Não deixa o jogador controlar o personagem, mas preserva o impulso do golpe.
				v = self.ob:get_velocity()
				-- Apenas reduz um pouco a velocidade horizontal, simulando atrito enquanto desliza.
				v.x = v.x * 0.985
				self.ob:set_acceleration({x=0,y=-20,z=0})
			if not pob.stagger_anim_played then
				pob.stagger_anim_played=true
				mt2d.player_anim(self,"lay")
				minetest.sound_play("character_die", {object=self.ob, gain=0.5, max_hear_distance=16}, true)
				-- mt2d.player_anim liga a animação com loop (igual faz pra
				-- "walk"/"stand"), mas "lay" aqui é a queda, não deve
				-- repetir -- força frame_loop=false pra tocar uma vez e
				-- congelar no último frame (jogador fica deitado parado)
				local frame_range,frame_speed,frame_blend=self.ob:get_animation()
				if frame_range then self.ob:set_animation(frame_range,frame_speed,frame_blend,false) end
			end
		elseif pob.special_attack_timer and pob.special_attack_timer>0 then v.x=0
		    if not pob.special_attack_anim_played then
			pob.special_attack_anim_played=true
			mt2d.player_anim(self,"mine")
			-- toca uma vez só e congela no último frame (igual ao stagger/sneak),
			-- em vez de reiniciar a animação a cada on_step
			local frame_range,frame_speed,frame_blend=self.ob:get_animation()
			if frame_range then self.ob:set_animation(frame_range,frame_speed,frame_blend,false) end
		    end
		elseif pob.recoil_timer and pob.recoil_timer>0 then
			-- recuo leve: mantém o impulso do golpe (a gravidade cuida do
			-- arco) e ignora o input de movimento/ataque por um instante
			mt2d.player_anim(self,"stand")
		elseif self.laying then
			v={x=0,y=0,z=0}
			self.ob:set_acceleration({x=0,y=0,z=0})
			mt2d.player_anim(self,"lay")
			if not pob.laying_sound_played then
				pob.laying_sound_played=true
				minetest.sound_play("character_die", {object=self.ob, gain=0.5, max_hear_distance=16}, true)
			end
			if key.up or key.left or key.right or self.wakeup then
				self.laying=nil
				self.wakeup=nil
				pob.laying_sound_played=false
				self.ob:set_acceleration({x=0,y=-20,z=0})
			end
		elseif key.up and (v.y==0 or self.floating) and self.jump_timer <= 0 then
			self.jump_timer = 0.05
			v.y=12
		elseif key.jump and (v.y==0 or self.floating) and self.jump_timer <= 0 then
			self.jump_timer = 0.05
			v.y=12
		elseif key.left then
		    if self.running == -1 then
			v.x = self.run_speed
			mt2d.player_anim(self, "run")
		    elseif key.sneak or key.down then
			v.x = self.walk_speed
			mt2d.player_anim(self, "hugwalk")
			pob.sneak_anim_played=false
		    else
			v.x = self.walk_speed
			mt2d.player_anim(self, "walk")
		    end
		    self.ob:set_yaw(4.71)

		elseif key.right then
		    if self.running == 1 then
			v.x = -self.run_speed
			mt2d.player_anim(self, "run")
		    elseif key.sneak or key.down then
			v.x = -self.walk_speed
			mt2d.player_anim(self, "hugwalk")
			pob.sneak_anim_played=false
		    else
			v.x = -self.walk_speed
			mt2d.player_anim(self, "walk")
		    end
		    self.ob:set_yaw(1.57)
		elseif key.sneak or key.down then
			-- agachado parado (sem direção pressionada): toca "sneak" uma
			-- vez só e congela no último frame, igual ao "lay" do stagger
			v.x=0
			if not pob.sneak_anim_played then
				pob.sneak_anim_played=true
				mt2d.player_anim(self,"sneak")
				local frame_range,frame_speed,frame_blend=self.ob:get_animation()
				if frame_range then self.ob:set_animation(frame_range,frame_speed,frame_blend,false) end
			end
		elseif key.RMB or key.LMB then
			mt2d.player_anim(self,"mine")
			v.x=0
			if not pob.punch_anim_played then
				pob.punch_anim_played=true
				minetest.sound_play("character_punch", {object=self.ob, gain=0.1, max_hear_distance=16}, true)
			end
		elseif key.aux1 and 	minetest.check_player_privs(self.username, {leave2d=true}) then
			mt2d.to_3dplayer(self.user)
			return
		else
			mt2d.player_anim(self,"stand")
			v={x=0,y=v.y,z=0}
		end

		if self.jump_timer > 0 and v.y == 0 then
			self.jump_timer = self.jump_timer -dtime
		elseif self.floating then
			v.x=v.x/2
			v.y=v.y/2
			if key.down then
				v.y=-2
			end
		end

		if self.fly and key.sneak then
			self.ob:set_acceleration({x=0,y=0,z=0})
			if key.up then v.y=12
			elseif key.jump then v.y=12
			elseif key.down then v.y=-8
			else v.y=0
			end
			self.flying=true
			if self.noclip and not self.noclip_enabled then
				v={x=0.1,y=12,z=0}
				self.noclip_enabled=true
				self.ob:set_properties({physical=false})
			end
			v.x=v.x*2
			self.fallingfrom=nil
		elseif self.noclip_enabled or self.flying then
			self.noclip_enabled=nil
			self.flying=nil
			self.ob:set_properties({physical=true})
			self.ob:set_acceleration({x=0,y=-20,z=0})
		elseif key.sneak and v.x~=0 then
			v.x=v.x/4
		end
--movment
		self.ob:set_velocity(v)
		if self.powersaving.time==0 then self.object:set_velocity({x=((pos2.x-pos.x)*10)+self.user_pos.x,y=(-0.5+(pos2.y-pos.y))*10,z=(5-(pos.z-pos2.z))*10})
		else self.object:set_velocity({x=((pos2.x-pos.x))+self.user_pos.x,y=(-0.5+(pos2.y-pos.y)),z=(5-(pos.z-pos2.z))})
		end
		local yaw=self.user:get_look_yaw()
		local pitch=self.user:get_look_pitch()
		local tyaw=math.abs(yaw-4.71)
		local tpitch=math.abs(pitch)
		local npointable=not mt2d.pointable(pos2,self.user)
		if tyaw>0.5 or (npointable and tyaw>0.2) then self.user:set_look_horizontal(3.14+((yaw-4.71)*0.9))
		elseif tpitch>0.5 or (npointable and tpitch>0.2) then self.user:set_look_vertical((pitch*0.9)*-1) end
		if self.powersaving.dir~=tyaw+tpitch or self.powersaving.x~=v.x or self.powersaving.y~=v.y then
			self.powersaving={
				dir=tyaw+tpitch,
				x=v.x,
				y=v.y,
				timer=0,
				time=0,
				count=5,
				timeout=0
			}
		else
			self.powersaving.timer=self.powersaving.timer+dtime*2	
			if self.powersaving.timer>self.powersaving.count and self.powersaving.time<2 then
				self.powersaving.count=1
				self.powersaving.timer=0
				self.powersaving.time=self.powersaving.time+0.1
				self.powersaving.timeout=self.powersaving.time
			end
		end
		self.powersaving.timeout=self.powersaving.time
		return self
	end,
	start=0.1,
	type="npc",
})

minetest.register_entity("grandchaos:player",{
	hp_max = 20,
	physical = true,
	collisionbox = {-0.15,-1,-0.15,0.15,0.7,0.15},
	visual =  "mesh",
	mesh = "mt2d_character3D.glb",
	textures = {"mt2d_air.png", "mt2d_air.png"},
	is_visible = true,
	makes_footstep_sound = true,
	on_activate=function(self, staticdata)
		local rndlook={4.71,1.57}
		self.object:set_yaw(rndlook[math.random(1,2)])
		self.object:set_acceleration({x=0,y=-20,z =0})
		return self
	end,
	on_punch=function(self, puncher, time_from_last_punch, tool_capabilities, dir)
		if not self.user then self.object:remove()
		elseif not (puncher:is_player() and puncher:get_player_name(puncher)==self.username) and tool_capabilities and tool_capabilities.damage_groups and tool_capabilities.damage_groups.fleshy then
			self.user:set_hp(self.user:get_hp()-tool_capabilities.damage_groups.fleshy)
		end
		return self
	end,
	-- recuo leve a cada hit
	recoil_timer=0,
	recoil_duration=0.2,
	knockback_speed=10,
	hit_hop_speed=5,
	-- controle de golpes rápidos (3 hits -> recuo alto + deitar)
	hit_count=0,
	last_hit_time=0,
	hit_window=0.8,
	hits_to_stagger=3,
	stagger_timer=0,
	stagger_duration=1.6,
	stagger_knockback_speed=20,
	stagger_hop_speed=4,
	-- controla se a animação de "cair e deitar" já foi disparada para o
	-- stagger atual. Fica na mesma entidade/tabela que stagger_timer (e não
	-- numa flag à parte no "cam") justamente para não perder sincronia caso
	-- o cam seja reprocessado/recriado no meio do stagger.
	stagger_anim_played=false,
	on_step=function(self, dtime)
		self.recoil_timer=math.max(0,(self.recoil_timer or 0)-dtime)
		self.stagger_timer=math.max(0,(self.stagger_timer or 0)-dtime)
		self.special_attack_timer=math.max(0,(self.special_attack_timer or 0)-dtime)
		self.timer=self.timer+dtime
		if self.start>0 then
			self.start=self.start-dtime
			return self
		elseif not (mt2d.user[self.username] and mt2d.user[self.username].id==self.id) then
			self.object:remove()
			return self
		elseif self.user:get_hp()<=0 then
			self.ob=self.object
			self.ob:get_luaentity().dead=true
			mt2d.player_anim(self,"lay")
			-- toca o som de morte uma única vez (o ramo acima roda a
			-- cada on_step enquanto o hp continuar <=0)
			if not self.die_sound_played then
				self.die_sound_played=true
				minetest.sound_play("character_die", {object=self.object, gain=0.5, max_hear_distance=16}, true)
			end
		elseif self.timer>3 then
			self.timer=0
			if not self.user:get_attach() then mt2d.new_player(self.user) return end
		end
	end,
	id=0,
	username="",
	start=0.1,
	type="npc",
	team="Sam",
	timer=0,
})

-- Os mobs de entities.lua atacam o jogador real (target:punch(...), onde
-- "target" vem de core.get_connected_players()) e não a entidade visual
-- "grandchaos:player" -- por isso o recuo/stagger não pode viver no
-- on_punch dela (nunca é chamado nesse fluxo). on_punchplayer é quem
-- realmente dispara nesse caso, e aqui aplicamos o impulso na entidade
-- visual (self.ob), que é o que o cam.on_step já está lendo.
minetest.register_on_punchplayer(function(player, hitter, time_from_last_punch, tool_capabilities, dir, damage)
	if not (tool_capabilities and tool_capabilities.damage_groups and tool_capabilities.damage_groups.fleshy) then return end
	local name=player:get_player_name()
	local u=mt2d.user[name]
	if not (u and u.object and u.object:get_luaentity()) then return end
	-- ignora golpes vindos de outro jogador (pvp), só reage a mobs
	if hitter and hitter:is_player() then return end
	local ob=u.object
	local pob=ob:get_luaentity()
	-- já está em stagger: intangível, não conta hit nem sofre novo recuo
	if pob.stagger_timer>0 then return end
	local now=minetest.get_us_time()/1e6
	if (now-pob.last_hit_time)<=pob.hit_window then pob.hit_count=pob.hit_count+1
	else pob.hit_count=1
	end
	pob.last_hit_time=now

	-- Calcula a direção do recuo usando as posições reais do mob e da
	-- entidade visual do jogador. Em um jogo 2D isso é muito mais confiável
	-- do que o vetor "dir" fornecido pelo motor.
	local kb_dir = 1
	if hitter and hitter:get_pos() then
		local mob_pos = hitter:get_pos()
		local player_pos = ob:get_pos()
		if mob_pos and player_pos then kb_dir = (player_pos.x >= mob_pos.x) and 1 or -1 end
	end
	if pob.hit_count>=pob.hits_to_stagger then
		pob.hit_count=0
		pob.stagger_timer=pob.stagger_duration
		pob.stagger_anim_played=false
		pob.recoil_timer=0
		ob:set_velocity({x = kb_dir * pob.stagger_knockback_speed, y = pob.stagger_hop_speed, z = 0})
		-- intangível durante o stagger: mobs deixam de colidir/empurrar o jogador
		player:set_properties({collide_with_objects=false})
		ob:set_properties({collide_with_objects=false})
	else
		pob.recoil_timer=pob.recoil_duration
		ob:set_velocity({x = kb_dir * pob.knockback_speed, y = pob.hit_hop_speed, z = 0})
	end
end)

-- Enquanto o stagger estiver ativo, nenhum dano é aplicado (jogador
-- "intangível" a ataques também no sentido de dano, não só de colisão)
minetest.register_on_player_hpchange(function(player, hp_change, reason)
	if hp_change>=0 then return hp_change end
	local u=mt2d.user[player:get_player_name()]
	if not (u and u.object and u.object:get_luaentity()) then return hp_change end
	local pob=u.object:get_luaentity()
	if pob.stagger_timer and pob.stagger_timer>0 then return 0 end
	return hp_change
end, true)

minetest.register_entity("grandchaos:boat",{
	hp_max = 10,
	physical = true,
	visual =  "upright_sprite",
	collisionbox = {-0.9,-0.1,0,0.9,1.25,0},
	visual_size={x=1.8,y=0.2},
	textures = {"default_wood.png"},
	is_visible = true,
	makes_footstep_sound = false,
	on_rightclick=function(self, clicker,name)
		local name=clicker:get_player_name()
		if not self.user and mt2d.user[name] and mt2d.user[name].object then
			self.user=clicker
			self.username=name
			self.id=mt2d.user[name].id
			self.ob=mt2d.user[name].object
			mt2d.player_anim(self,"sit")
			mt2d.set_attach(name,self.object,self.ob,{y=0.8})
		elseif self.user and self.username==name then
			self.user=nil
			self.username=nil
			self.id=nil
			self.ob=nil
			mt2d.set_detach(name)
			self.anim=nil
		end
	end,
	on_punch=function(self, puncher, time_from_last_punch, tool_capabilities, dir)

		tool_capabilities.damage_groups.fleshy=tool_capabilities.damage_groups.fleshy or 1

		if not self.user then
			if puncher:get_inventory() then
				puncher:get_inventory():add_item("main","boats:boat")
			else
				minetest.add_item(self.object:get_pos(),"boats:boat")
			end
			self.object:remove()
		elseif self.object:get_hp()-tool_capabilities.damage_groups.fleshy<=0 then
			self.anim=nil
			mt2d.set_detach(self.username)
			mt2d.player_anim(self,"stand")
		end
	end,
	on_step=function(self, dtime)
		if self.timer>0 then
			self.timer=self.timer+dtime
			if self.timer>1 then
				self.timer=0.001
			else
				return self
			end
		end
		local v=self.object:get_velocity()
		local pos=self.object:get_pos()
		local l=minetest.registered_nodes[minetest.get_node({x=pos.x,y=pos.y,z=0}).name]
		local lu=minetest.registered_nodes[minetest.get_node({x=pos.x,y=pos.y-1,z=0}).name]

		if l and l.liquid_viscosity>0 then 
			v.y=1
			self.object:set_acceleration({x=0,y=0,z=0})
			self.delaytimer=0
		elseif lu and lu.liquid_viscosity==0 then
			self.object:set_acceleration({x=0,y=-20,z=0})
			self.delaytimer=0
		else
			self.delaytimer=self.delaytimer+dtime
			self.object:set_acceleration({x=0,y=0,z=0})
			v.y=0
			if self.delaytimer>10 then
				self.timer=0.001
			else
				self.timer=0
			end
		end

		self.object:set_velocity(v)

		if not self.user then
			if math.abs(v.x)>0.2 then
				v.x=v.x*0.99
				self.object:set_velocity(v)
			end
			return self
		elseif self.id~=mt2d.user[self.username].id then --or not (self.ob and self.ob:get_attach())
			mt2d.set_detach(self.username)
			self.user=nil
			self.username=nil
			self.id=nil
			self.ob=nil
			return self
		end

		local key=self.user:get_player_control()
		local now = minetest.get_us_time() / 1e6
		-- Detecta o segundo toque para correr
		if key.left and not self.left_was_down then
			if now - self.last_left_press <= self.dash_window then self.running = -1 end
			self.last_left_press = now
		end
		if key.right and not self.right_was_down then
			if now - self.last_right_press <= self.dash_window then self.running = 1 end
			self.last_right_press = now
		end
		self.left_was_down = key.left
		self.right_was_down = key.right
		-- Cancela a corrida quando solta a direção
		if self.running == -1 and not key.left then self.running = 0
		elseif self.running == 1 and not key.right then self.running = 0
		end
		if key.left and v.x<4 then
			v.x=v.x+0.1
			self.delaytimer=0
			self.ob:set_yaw(4.71)
		elseif key.right and v.x>-4 then
			v.x=v.x-0.1
			self.delaytimer=0
			self.ob:set_yaw(1.57)
		elseif not (key.right or key.left) and math.abs(v.x)>0.2 then
			v.x=v.x*0.99
			self.delaytimer=0
		end
		self.object:set_velocity(v)
	end,
	timer=0,
	delaytimer=0,
	type="npc",
	team="Sam",
})

minetest.after(0.1, function()
	minetest.override_item("boats:boat", {
		on_place=function(itemstack, user, pointed_thing)
			local pos=pointed_thing.under
			if not pos then return end
			local l=minetest.registered_nodes[minetest.get_node(pos).name]
			if not (l and l.liquid_viscosity>0) then return end
			itemstack:take_item()
			minetest.add_entity({x=pos.x,y=pos.y,z=0.05}, "grandchaos:boat")
			return itemstack
		end,
	})
end)

mt2d.dot=function(pos,v)
	v=v or "008"
	local a=""
	for i=1,3,1 do
		local n=tonumber(v:sub(i,i))
		if not n or n==0 or n>8 then n=1 end
		a=a .. string.sub("13579bdf",n,n):rep(2)
	end
	minetest.add_entity(pos, "grandchaos:dot"):set_properties({textures = {"bubble.png^[colorize:#"..a}})
end

minetest.register_entity("grandchaos:dot",{
	hp_max = 1,
	physical = false,
	collisionbox = {0,0,0,0,0,0},
	visual = "sprite",
	visual_size = {x=0.2, y=0.2},
	textures = {"bubble.png"},
	makes_footstep_sound = false,
	on_step = function(self, dtime)
		self.timer=self.timer+dtime
		if self.timer<0.1 then return self end
		self.object:remove()
	end,
	timer=0,
})

minetest.register_entity("grandchaos:cart",{
	hp_max = 10,
	physical = false,
	visual =  "upright_sprite",
	collisionbox = {-0.5,-0.5,0,0.5,0.5,0},
	textures = {"carts_cart_side.png"},
	is_visible = true,
	makes_footstep_sound = false,
	new_path=function(self)
		if self.d==0 then return end
		local newpath=mt2d.path(self.object:get_pos(),10,self.d,"rail")
		if newpath then
			self.path=newpath
			table.remove(self.path,1)
			return self
		end
	end,
	on_activate=function(self, staticdata)
		self.d=0
		self.v=0
		self.stucktime=0
	end,
	on_rightclick=function(self, clicker)
		local name=clicker:get_player_name()
		if not self.user and mt2d.user[name] and mt2d.user[name].object then
			self.user=clicker
			self.username=name
			self.id=mt2d.user[name].id
			self.ob=mt2d.user[name].object
			mt2d.player_anim(self,"sit")
			mt2d.set_attach(name,self.object,self.ob,{y=0.8,z=-0.1})
		elseif self.user and self.username==name then
			self.user=nil
			self.username=nil
			self.id=nil
			self.ob=nil
			mt2d.set_detach(name)
			self.anim=nil
		end
	end,
	on_punch=function(self, puncher, time_from_last_punch, tool_capabilities, dir)
		tool_capabilities.damage_groups.fleshy=tool_capabilities.damage_groups.fleshy or 1
		if not self.user then
			if puncher:get_inventory() then
				puncher:get_inventory():add_item("main","carts:cart")
			else
				minetest.add_item(self.object:get_pos(),"carts:cart")
			end
			self.object:remove()
		elseif self.object:get_hp()-tool_capabilities.damage_groups.fleshy<=0 then
			self.anim=nil
			mt2d.set_detach(self.username)
			mt2d.player_anim(self,"stand")
		end
	end,
	on_step=function(self, dtime)

		local v=self.object:get_velocity()
		local pos=self.object:get_pos()

		if self.user and mt2d.user[self.username] and self.id==mt2d.user[self.username].id then
			local key=self.user:get_player_control()
			if key.left and self.v<self.max_speed then
				self.v=self.v+0.1
				if self.v<=0.1 then
					self.d=1
					self.new_path(self)
					self.ob:set_yaw(4.71)
				end
			elseif key.right and self.v>-self.max_speed then
				self.v=self.v-0.1
				if self.v>=-0.1 then
					self.d=-1
					self.new_path(self)
					self.ob:set_yaw(1.57)
				end
			elseif key.sneak then
				self.on_rightclick(self, self.user)
			elseif math.abs(self.v)>0.1 then
				self.v=self.v*0.99
			end
		elseif self.v~=0 then
			self.v=self.v*0.99
			if math.abs(self.v)<=0.1 then
				self.d=0
				self.v=0
				self.path=nil
				self.next_pos=nil
				mt2d.set_detach(self.username)
				self.user=nil
				self.username=nil
				self.id=nil
				self.ob=nil
				self.object:set_velocity({x=0,y=0,z=0})
				return
			end
		end

		if not self.path or not self.path[1] then
			self.object:set_velocity({x=0,y=0,z=0})
			return
		end

		pos={x=math.floor(pos.x*2)*0.5,y=math.floor(pos.y*2)*0.5,z=0}
		local d=math.floor(math.abs(self.v*0.1))

		if math.abs(self.v)>10 then
			self.stucktime=self.stucktime+dtime
			if self.stucktime>0.1 and self.path[2+d] then
				self.next_pos=self.path[2+d]
				self.stucktime=0
			elseif self.stucktime>0.1 then
				self.new_path(self)
				self.next_pos=self.path[2]
			end
		end

		for i=1,9,1 do
			if self.path[i] and (pos.x==self.path[i].x and pos.y==self.path[i].y) or not self.next_pos then
				if self.path[i+1+d] then
					self.old_pos=self.next_pos
					self.next_pos=self.path[i+1+d]
					self.stucktime=0
				end
				local l=#self.path
				for ii=i,1,-1 do
					if #self.path==0 then return end
					self.path=mt2d.path_add(self.d,self.path,self.path[#self.path],"rail")
					self.path=mt2d.path_iremove(self.path,1)
				end
				break
			end
		end
		if not self.next_pos then
			return
		end
		local rail=minetest.get_node(pos).name
		local ov=self.v

		if self.v<self.max_speed and ((pos.y>self.next_pos.y) or rail=="carts:powerrail") then
			self.v=self.v*1.05
			self.v=math.floor(self.v*100)/100
		elseif self.v>-self.max_speed and ((pos.y<self.next_pos.y) or rail=="carts:brakerail") then
			self.v=self.v*0.99
			self.v=math.floor(self.v*100)/100
		elseif minetest.get_node(self.next_pos).name=="grandchaos:stoprail" then
			self.v=0.1
			if self.user then 
				self.on_rightclick(self, self.user)
				self.user=nil
			end
		end
		local a=math.abs(self.v)
		self.object:set_velocity({x=(self.next_pos.x-pos.x)*a,y=(self.next_pos.y-pos.y)*a,z=0})
	end,
	d=0,
	v=0,
	stucktime=0,
	max_speed=20,
	type="npc",
	team="Sam",
})

minetest.after(0.1, function()
	minetest.override_item("carts:cart", {
		on_place=function(itemstack, user, pointed_thing)
			if minetest.get_item_group(minetest.get_node(pointed_thing.under).name,"rail")==0 then return end
			itemstack:take_item()
			local p=pointed_thing.under
			minetest.add_entity({x=p.x,y=p.y,z=0.1}, "grandchaos:cart")
			return itemstack
		end,
	})
	minetest.override_item("carts:rail",{groups={dig_immediate=2,rail=1,connect_to_raillike=minetest.raillike_group("rail")}})
	minetest.override_item("carts:powerrail",{groups={dig_immediate=2,rail=1,connect_to_raillike=minetest.raillike_group("rail")}})
	minetest.override_item("carts:brakerail",{groups={dig_immediate=2,rail=1,connect_to_raillike=minetest.raillike_group("rail")}})
end)
