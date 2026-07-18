-- grandchaos/items.lua
-- Itens e nós usados na fase: espada do herói, barreira mágica, portal e troféu.
-- Espada do herói (arma inicial da fase)
core.register_tool("grandchaos:sword", {
	description = "Shinai\nEspada de Bambu\n[Nível Treinamento I]\nArma inicial",
	inventory_image = "gc_shinaisword.png",
	tool_capabilities = {
		full_punch_interval = 0.6,
		max_drop_level = 1,
		groupcaps = {fleshy = {times = {[1] = 1.2, [2] = 0.6, [3] = 0.3}, uses = 0, maxlevel = 3}},
		damage_groups = {fleshy = 5},
	},
	range = 1,
	groups = {not_repaired_by_anvil = 1},
})
-- Espada de conclusão da fase
core.register_tool("grandchaos:sword2", {
	description = "Bokken\nEspada de Madeira\n[Nível Treinamento II]",
	inventory_image = "gc_bokkensword.png",
	stack_max = 1,
	tool_capabilities = {
		full_punch_interval = 0.7, -- Mais pesada ataca mais devagar
		max_drop_level = 1,
		groupcaps = {fleshy = {times = {[1] = 1.4, [2] = 0.7, [3] = 0.35}, uses = 0, maxlevel = 3}},
		damage_groups = {fleshy = 10}, -- Maciça e maais pesada, o dobro de dano
	},
	range = 1.5,
	groups = {not_repaired_by_anvil = 1},
})
-- Parede de tronco: bloqueia o avanço até a onda ser derrotada E o jogador
-- alcançar o bloco luminoso no chão do trecho. Usa a textura de tronco do
-- jogo base (default:tree), mas é indestrutível para o jogador.
core.register_node("grandchaos:trunk_wall", {
	description = "Tronco da Parede (Barreira da Fase)",
	tiles = {"default_tree.png"},
	paramtype2 = "facedir",
	is_ground_content = false,
	walkable = true,
	diggable = false,
	pointable = true,
	on_blast = function() end,
	groups = {not_in_creative_inventory = 1, immortal = 1},
})
core.register_node("grandchaos:trunk_platform", {
	description = "Tronco Flutuante (Paltaforma da Fase)",
	tiles = {"default_tree_top.png", "default_tree_top.png", "default_tree.png"},
	collision_box = {type = "fixed", fixed = {-0.5, -0.5, -0.5, -0.3, 0.5, 0.5}},
	paramtype2 = "facedir",
	place_param2 = 12,
	is_ground_content = false,
	walkable = true,
	diggable = false,
	pointable = true,
	on_blast = function() end,
	groups = {not_in_creative_inventory = 1, immortal = 1},
	sounds = default.node_sound_wood_defaults(),
})
-- Versão "fantasma" (não sólida) do tronco flutuante: usada só
-- temporariamente pelo init.lua, no lugar de grandchaos:trunk_platform,
-- para deixar o jogador atravessar a plataforma ao apertar agachar/baixo
-- enquanto está em pé sobre ela. Nunca é colocada permanentemente nem
-- aparece no inventário — é sempre trocada de volta para o tronco sólido
-- logo em seguida.
core.register_node("grandchaos:trunk_platform_ghost", {
	description = "Tronco Flutuante (passável)",
	tiles = {"default_tree_top.png", "default_tree_top.png", "default_tree.png"},
	collision_box = {type = "fixed", fixed = {-0.5, -0.5, -0.5, -0.3, 0.5, 0.5}},
	paramtype2 = "facedir",
	place_param2 = 12,
	is_ground_content = false,
	walkable = false,
	diggable = false,
	pointable = false,
	drop = "",
	on_blast = function() end,
	groups = {not_in_creative_inventory = 1, immortal = 1},
})
-- A mecânica de atravessar a plataforma de baixo pra cima ao pular vive
-- em init.lua (try_jump_through_platform), espelhando exatamente o
-- try_drop_through_platform que já existe lá para o sneak/down: troca o
-- nó por um instante fixo (grandchaos:trunk_platform_ghost) e depois
-- volta a ser sólido sozinho. Isso mantém as duas direções (subir/descer
-- através da plataforma) com o mesmo mecanismo, no mesmo arquivo.

core.register_node("grandchaos:floor1", {
	description = "Chão de grama (piso da Fase)",
	tiles = {"default_grass.png", "default_dirt.png", "default_dirt.png^default_grass_side.png"},
	paramtype2 = "facedir",
	is_ground_content = false,
	walkable = true,
	diggable = false,
	pointable = true,
	on_blast = function() end,
	groups = {not_in_creative_inventory = 1, immortal = 1},
	sounds = default.node_sound_dirt_defaults(),
})
core.register_node("grandchaos:floor2", {
	description = "chão de terra (base da Fase)",
	tiles = {"default_dirt.png"},
	paramtype2 = "facedir",
	is_ground_content = false,
	walkable = true,
	diggable = false,
	pointable = true,
	on_blast = function() end,
	groups = {not_in_creative_inventory = 1, immortal = 1},
})
-- Portal de início / reinício da fase
core.register_node("grandchaos:portal", {
	description = "Portal da Floresta de Aria\nClique com o botão direito para iniciar a Fase 1",
	drawtype = "nodebox",
	tiles = {"grandchaos_portal.png"},
	paramtype = "light",
	light_source = 8,
	walkable = false,
	node_box = {type = "fixed", fixed = {-0.4, -0.5, -0.05, 0.4, 0.5, 0.05}},
	groups = {oddly_breakable_by_hand = 3},
	on_rightclick = function(pos, node, clicker)
		if clicker and clicker:is_player() then grandchaos.start_phase(clicker, pos) end
	end,
})
core.register_craftitem("grandchaos:copper_coin", {
	description = "Moeda de Cobre",
	inventory_image = "gc_coppercoin.png",
	stack_max = 100,
	light_source = 10,
})
core.register_craftitem("grandchaos:silver_coin", {
	description = "Moeda de Prata",
	inventory_image = "gc_silvercoin.png",
	stack_max = 100,
	light_source = 10,
})
core.register_craftitem("grandchaos:gold_coin", {
	description = "Moeda de Ouro",
	inventory_image = "gc_goldcoin.png",
	stack_max = 100,
	light_source = 10,
})
core.register_craftitem("grandchaos:platinum_coin", {
	description = "Moeda de Platina",
	inventory_image = "gc_platinumcoin.png",
	stack_max = 100,
	light_source = 10,
})
-- Troféu de conclusão da fase
core.register_craftitem("grandchaos:trophy", {
	description = "Troféu da Floresta de Aria\nPrêmio por concluir a Fase 1",
	inventory_image = "grandchaos_trophy.png",
	stack_max = 1,
	light_source = 10,
})

-- Moedas com metade do tamanho ao serem largadas no chão.
-- register_craftitem não tem um campo pra controlar o tamanho do item
-- largado (isso é calculado pelo motor quando a entidade é criada), então
-- o único jeito é observar as entidades ativas e ajustar o visual_size logo
-- depois que elas aparecem. Fica tudo aqui, então funciona não importa de
-- onde a moeda seja largada (mob, baú, comando, etc.), sem precisar mexer
-- em mais nada.
local COIN_SIZE_SCALE = 0.4
local COIN_ITEMS = {
	["grandchaos:copper_coin"] = true,
	["grandchaos:silver_coin"] = true,
	["grandchaos:gold_coin"] = true,
	["grandchaos:platinum_coin"] = true,
}

core.register_globalstep(function(dtime)
	for _, luaentity in pairs(core.luaentities) do
		if luaentity.itemstring and not luaentity._gc_coin_scaled then
			local itemname = ItemStack(luaentity.itemstring):get_name()
			if COIN_ITEMS[itemname] then
				luaentity._gc_coin_scaled = true
				local obj = luaentity.object
				if obj then
					local props = obj:get_properties()
					local vs = props.visual_size or {x = 1, y = 1}
					obj:set_properties({
						visual_size = {x = vs.x * COIN_SIZE_SCALE, y = vs.y * COIN_SIZE_SCALE},
					})
				end
			end
		end
	end
end)
