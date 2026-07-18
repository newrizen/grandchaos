-- mt2d.lua
mt2d={
	timer=0,
	user3d={},	--3d users
	user={},		--users data
	attach={},	--attached objects (pushing them)
	playeranim={
		stand={x=0/25,y=41/25,speed=1},
		walk={x=43/25,y=63/25,speed=1},
		run={x=43/25,y=63/25,speed=2},
		mine={x=64/25,y=69/25,speed=1},
		sneak={x=82/25,y=85/25,speed=1},
		hugwalk={x=85/25,y=100/25,speed=1},
		sit={x=101/25,y=111/25,speed=1},
		lay={x=113/25,y=123/25,speed=1},
	},
}

dofile(minetest.get_modpath("grandchaos") .. "/mt2d_entities.lua")

minetest.register_privilege("leave2d", {
	description = "Leave Dimension",
	give_to_singleplayer= false,
})
minetest.register_on_mods_loaded(function()
--minetest.after(0.1, function()
	for i, v in pairs(minetest.registered_items) do
		if not v.range or v.range<8 then minetest.override_item(i, {range=8}) end
	end
	if sethome then
	sethome.go=function(name)
		local pos=sethome.get(name)
		if pos and mt2d.user[name] then
			pos.z=0
			pos.y=pos.y+1
			mt2d.user[name].object:set_pos(pos)
			mt2d.user[name].cam:set_pos(pos)
			return true
		elseif not pos then return false
		else minetest.chat_send_player(name,"You can't go home in 3D mode") return true end
	end
	end
end)

mt2d.new_player=function(player)
	player:get_meta():set_string("mt2d_active","1")
	local pos=player:get_pos()
	pos={x=pos.x,y=pos.y,z=0}
	for i=0,100,1 do
		local n=minetest.registered_nodes[minetest.get_node({x=pos.x, y=pos.y+i, z=0}).name]
		if n and not n.walkable then pos.y=pos.y+i break end
	end
	player:set_pos(pos)
	local id=math.random(1,9999)
	local cam=minetest.add_entity({x=pos.x,y=pos.y,z=pos.z+5}, "grandchaos:cam")
	cam:get_luaentity().user=player
	cam:get_luaentity().username=player:get_player_name()
	cam:get_luaentity().id=id
	mt2d.user[player:get_player_name()]={id=id,cam=cam,texture="character.png"}
	player:set_attach(cam, "",{x = 0, y = 0, z = 0}, {x = 0, y = 0, z = 0})
	player:hud_set_flags({wielditem=false})
	player:set_nametag_attributes({color={a=0,r=255,g=255,b=255}})
	player:set_properties({textures={"mt2d_air.png"}})
end
	
mt2d.to_3dplayer=function(player)
	local name=player:get_player_name()
	if mt2d.user3d[name] then return end
	player:get_meta():set_string("mt2d_active","0")
	player:set_nametag_attributes({color={a=255,r=255,g=255,b=255}})
	player:set_properties({textures={mt2d.user[name].texture}})
	player:hud_set_flags({wielditem=true})
	player:set_detach()
	mt2d.user[name]=nil
	mt2d.user3d[name]={timeout=false,player=player}
end

minetest.register_globalstep(function(dtime)
	for name, a in pairs(mt2d.attach) do
		if not (mt2d.user[name] or mt2d.user[name].id==a.id) or not (a.ob1:get_pos() and a.ob2:get_pos()) then
			minetest.after(0, function(name)
				mt2d.attach[name]=nil
			end,name)
			break
		end
		local pos1=a.ob1:get_pos()
		local pos2=a.ob2:get_pos()
		a.ob2:set_velocity({x=((pos1.x-pos2.x)+a.pos.x)*10,y=((pos1.y-pos2.y)+a.pos.y)*10,z=((pos1.z-pos2.z)+a.pos.z)*10})
		local user
		if a.ob1:get_luaentity() and a.ob1:get_luaentity().user then user=a.ob1:get_luaentity().user
		elseif a.ob2:get_luaentity() and a.ob2:get_luaentity().user then user=a.ob2:get_luaentity().user
		elseif a.ob1:is_player() then user=a.ob1
		elseif a.ob2:is_player() then user=a.ob2
		end
		if user then
			local yaw=user:get_look_yaw()
			local pitch=user:get_look_pitch()
			local tyaw=math.abs(yaw-4.71)
			local tpitch=math.abs(pitch)
			local npointable=not mt2d.pointable(pos2,user)
			if tyaw>0.5 or (npointable and tyaw>0.2) then user:set_look_yaw(3.14+((yaw-4.71)*0.99))
			elseif tpitch>0.5 or (npointable and tpitch>0.2) then user:set_look_pitch((pitch*0.99)*-1)
			end
		end
	end
	mt2d.timer=mt2d.timer+dtime
	if mt2d.timer<2 then return end
	mt2d.timer=0
	-- Antes, segurar aux1 (sprint) em modo 3D reativava o 2D sozinho.
	-- Agora o 2D só é ativado por comando direto (/join2d) ou pelo
	-- /gcstart, então esse gatilho automático foi removido daqui.
end)

-- O modo 2D não é mais ativado automaticamente para todo mundo que
-- entra no servidor. Ele só é reativado sozinho ao reconectar se o
-- jogador estiver no meio de uma fase do grandchaos (fase ativa) —
-- caso contrário, ele permanece em modo 3D até usar /join2d ou /gcstart.
minetest.register_on_joinplayer(function(player)
	if player:get_meta():get_string("mt2d_active") ~= "1" then return end
	mt2d.new_player(player)
end)

-- Mesma lógica no respawn: só volta pro 2D sozinho se havia uma fase
-- em andamento (quem cuida do reposicionamento fino nesse caso é o
-- register_on_respawnplayer do grandchaos, em init.lua).
minetest.register_on_respawnplayer(function(player)
	local name=player:get_player_name()
	if not (grandchaos and grandchaos.is_phase_active and grandchaos.is_phase_active(name)) then return end
	minetest.after(0, function(player) local pos=player:get_pos() player:set_pos({x=pos.x,y=pos.y,z=5}) end,player)
	minetest.after(1, function(player) mt2d.new_player(player) end,player)
end)

-- Comandos para entrar/sair do modo 2D manualmente.
minetest.register_chatcommand("join2d", {
	description = "Entra manualmente no modo 2D",
	func = function(name)
		if grandchaos and grandchaos.hide_hint then grandchaos.hide_hint(name) end
		local player = minetest.get_player_by_name(name)
		if not player then return false, "Jogador não encontrado." end
		if mt2d.user[name] then return false, "Você já está no modo 2D." end
		mt2d.new_player(player)
		return true, "Você entrou no modo 2D."
	end,
})

minetest.register_chatcommand("leave2d", {
	description = "Sai do modo 2D e volta ao modo 3D normal",
	func = function(name)
		local player = minetest.get_player_by_name(name)
		if not player then return false, "Jogador não encontrado." end
		if not minetest.check_player_privs(name, {leave2d = true}) then
			return false, "Você não tem o privilégio 'leave2d' necessário para usar este comando."
		end
		if grandchaos and grandchaos.is_phase_active and grandchaos.is_phase_active(name) then
			return false, "Você não pode sair do modo 2D durante uma fase em andamento. Use /gcreset para cancelá-la primeiro."
		end
		if not mt2d.user[name] then return false, "Você já está no modo 3D." end
		mt2d.to_3dplayer(player)
		return true, "Você saiu do modo 2D."
	end,
})

minetest.register_on_dieplayer(function(player)
	player:set_detach()
	minetest.after(0.1, function(player)
		local bones_pos=minetest.find_node_near(player:get_pos(), 2, {"bones:bones"})
		if bones_pos then
			local bones=minetest.get_node(bones_pos)
			local name=player:get_player_name()
			for i, replace_pos in pairs(mt2d.get_nodes_radius(bones_pos,15)) do
				local replace=minetest.get_node(replace_pos).name
				if (minetest.registered_nodes[replace] and minetest.registered_nodes[replace].buildable_to) then
					minetest.set_node(replace_pos,bones)
					minetest.get_meta(replace_pos):from_table(minetest.get_meta(bones_pos):to_table())
					minetest.set_node(bones_pos,{name="air"})
					return
				end
			end
			local replace_pos={x=bones_pos.x,y=bones_pos.y,z=0}
			local replace=minetest.get_node(replace_pos).name

			if minetest.is_protected(replace_pos, name)==false and
			(minetest.get_item_group(replace,"stone")>0
			or minetest.get_item_group(replace,"soil")>0
			or minetest.get_item_group(replace,"sand")>0) then
				minetest.set_node(replace_pos,bones)
				minetest.get_meta(replace_pos):from_table(minetest.get_meta(bones_pos):to_table())
				minetest.get_meta(replace_pos):get_inventory():add_item("main",{name=replace})
				minetest.set_node(bones_pos,{name="air"})
				return
			end

		end
	end,player)
end)

minetest.register_on_leaveplayer(function(player)
	player:set_detach()
	mt2d.user[player:get_player_name()]=nil
	mt2d.user3d[player:get_player_name()]=nil
end)

mt2d.pointable=function(p1,user)
	local dir=user:get_look_dir()
	local p2=user:get_pos()
	p2={x=p2.x+(dir.x*5),y=p2.y+1.6+(dir.y*5),z=p2.z+(dir.z*5)}
	p1.y=p1.y+0.6
	local v = {x = p1.x - p2.x, y = p1.y - p2.y, z = p1.z - p2.z}
	local amount = (v.x ^ 2 + v.y ^ 2 + v.z ^ 2) ^ 0.5
	local d=math.sqrt((p1.x-p2.x)*(p1.x-p2.x) + (p1.y-p2.y)*(p1.y-p2.y) + (p1.z-p2.z)*(p1.z-p2.z))
	v.x = (v.x  / amount)*-1
	v.y = (v.y  / amount)*-1
	v.z = (v.z  / amount)*-1
	local hit
	for i=1,d,0.5 do
		local node=minetest.get_node({x=p1.x+(v.x*i),y=p1.y+(v.y*i),z=p1.z+(v.z*i)})
		if hit and minetest.registered_nodes[node.name] and minetest.registered_nodes[node.name].walkable then
			return false
		end
		hit=true
	end
	return true
end

mt2d.player_anim=function(self,typ)
	if typ==self.anim then
		return
	end
	self.anim=typ
	self.ob:set_animation({x=mt2d.playeranim[typ].x, y=mt2d.playeranim[typ].y, },mt2d.playeranim[typ].speed,0)

	if self.user and self.user:get_wielded_item()~=self.wielditem then
		self.wielditem=self.user:get_wielded_item():get_name()
		local t="mt2d_air.png"

		local def1=minetest.registered_items[self.wielditem]

		if def1 and def1.inventory_image and def1.inventory_image~="" then
			t=def1.inventory_image
		elseif def1 and def1.tiles and type(def1.tiles[1])=="string" then
			t=def1.tiles[1]
		end
		self.ob:set_properties({textures={mt2d.user[self.username].texture,t}})
	end
	return self
end


mt2d.punch=function(ob1,ob2,hp)
	if not (ob1 and ob2) then
		return
	end
	hp=hp or 1
	if ob1:is_player() then
		ob1:set_hp(ob1:get_hp()-hp)
	else
		ob1:punch(ob2,1,{full_punch_interval=1,damage_groups={fleshy=hp}})
	end	
end

minetest.spawn_item=function(pos, item)
	local e=minetest.add_entity(pos, "__builtin:item")
	if e then
		e:get_luaentity():set_item(ItemStack(item):to_string())
		minetest.after(0, function(e)
			local self=e:get_luaentity()
			if self and self.dropped_by and mt2d.user[self.dropped_by] then
				local ob=mt2d.user[self.dropped_by].object
				local yaw=math.floor(ob:get_yaw()*10)*0.1
				local v={x=0,y=0,z=0}
				local p=ob:get_pos()

				if yaw==4.7 then
					v.x=2
				elseif yaw==1.5 then
					v.x=-2
				else
					v.x=0
				end

				e:set_pos({x=pos.x+(v.x/2),y=pos.y-0.5,z=0})
				e:set_velocity({x=v.x,y=0,z=0})

			end
		end,e)

		minetest.after(10, function(e)
			if e and e:get_luaentity() then
				local node=minetest.registered_nodes[minetest.get_node(e:get_pos()).name]
				if node and node.damage_per_second>0 then
					e:remove()
				end
			end
		end,e)
	end
	return e
end

minetest.register_on_placenode(function(pos, newnode, placer, oldnode, itemstack, pointed_thing)
	local ppos=placer:get_pos()

	if pos.x==math.floor(ppos.x+0.5) and (pos.y==math.floor(ppos.y) or pos.y==math.floor(ppos.y+1)) then
		minetest.set_node(pos,oldnode)
		return true
	end
	for x=-1,1,1 do
	for y=-1,1,1 do
		if x+y~=0 and minetest.get_node({x=pos.x+x,y=pos.y+y,z=0}).name~="air" then
			return
		end
	end
	end
	minetest.set_node(pos,oldnode)
	return true
end)

mt2d.get_nodes_radius=function(pos,rad)
	rad=rad or 2
	local nodes={}
	local p
	for r=0,rad,1.5 do
	for a=-r,r,0.5 do
		p={	x=pos.x+(math.cos(a)*r)*0.5,
			y=pos.y+(math.sin(a)*r)*0.5,
			z=0
		}
		nodes[minetest.pos_to_string(p)]=p
	end
	end
	return nodes
end

mt2d.set_attach=function(name,object,object_to_attach,pos)
	pos=pos or {}
	pos={x=pos.x or 0,y=pos.y or 0,z=pos.z or 0}
	mt2d.attach[name]={
		name=name,
		id=mt2d.user[name].id,
		ob1=object,
		ob2=object_to_attach,
		pos=pos or {x=0,y=0,z=0}
	}
end

mt2d.get_attach=function(name)
	return mt2d.attach[name]
end

mt2d.set_detach=function(name)
	if mt2d.attach[name] then
		mt2d.attach[name]=nil
	end
end

mt2d.path_iremove=function(path,index)
	path[minetest.pos_to_string(path[index])]=nil
	table.remove(path,index)
	return path
end

mt2d.path=function(pos,l,dir,group)
	local c={}
	local lastpos={x=math.floor(pos.x),y=math.floor(pos.y),z=0}
	for i=dir,l*dir,dir do
		c,lastpos=mt2d.path_add(dir,c,lastpos,group)
		if not lastpos then
			break
		end
	end
	return c
end

mt2d.path_add=function(d,c,lp,group)
	for i, r in pairs({{x=0,y=0},{x=d,y=0},{x=0,y=1},{x=0,y=-1},{x=-d,y=0}}) do
		local p={x=lp.x+r.x,y=lp.y+r.y,z=0}
		local ps=minetest.pos_to_string(p)
		if not c[ps] and minetest.get_item_group(minetest.get_node(p).name,group)>0 then
			c[ps]=p
			table.insert(c,p)
			return c,p
		end
	end
	return c
end
