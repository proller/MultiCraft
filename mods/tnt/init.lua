-- loss probabilities array (one in X will be lost)
local loss_prob = {}

loss_prob["default:cobble"] = 3
loss_prob["default:dirt"] = 4

local radius_max = tonumber(core.setting_get("tnt_radius_max") or 25)
local time_max = tonumber(core.setting_get("tnt_time_max") or 3)
local liquid_real = core.setting_getbool("liquid_real")

local eject_drops = function(pos, stack)
	local obj = core.add_item(pos, stack)

	if obj == nil then
		return
	end
	obj:get_luaentity().collect = true
	obj:setacceleration({x=0, y=-10, z=0})
	obj:setvelocity({x=math.random(0,6)-3, y=10, z=math.random(0,6)-3})
end

--[[
local function rand_pos(center, pos, radius)
	local def
	local reg_nodes = minetest.registered_nodes
	local i = 0
	repeat
		-- Give up and use the center if this takes too long
		if i > 4 then
			pos.x, pos.z = center.x, center.z
			break
		end
		pos.x = center.x + math.random(-radius, radius)
		pos.z = center.z + math.random(-radius, radius)
		def = reg_nodes[minetest.get_node(pos).name]
		i = i + 1
	until def and not def.walkable
end
]]

local add_drop = function(drops, pos, item)
	if loss_prob[item] ~= nil then
		if math.random(1,loss_prob[item]) == 1 then
			return
		end
	end

	if drops[item] == nil then
		drops[item] = ItemStack(item)
	else
		drops[item]:add_item(item)
	end

	if drops[item]:get_free_space() == 0 then
		stack = drops[item]
		eject_drops(pos, stack)
		drops[item] = nil
	end
end

local function destroy(drops, pos, last, fast)
	if core.is_protected(pos, "") then
		return
	end

	local nodename = core.get_node(pos).name
	if nodename ~= "air" then

		local def = core.registered_nodes[nodename]
		if def and def.on_blast then
			def.on_blast(vector.new(pos), 1)
			return
		end

		core.remove_node(pos, (fast and 1 or 0))
		if last then
			nodeupdate(pos)
		end
		if not def or not def.groups then
			-- broken map and unknown nodes
			return
		end
		if def.groups.flammable ~= nil then
			core.set_node(pos, {name="fire:basic_flame"}, (fast and 2 or 0))
			return
		end
		local drop = core.get_node_drops(nodename, "")
		for _,item in ipairs(drop) do
			if type(item) == "string" then
				add_drop(drops, pos, item)
			else
				for i=1,item:get_count() do
					add_drop(drops, pos, item:get_name())
				end
			end
		end
	end
end

boom = function(pos, time, force)
	core.after(time, function(pos)
		if not force and core.get_node(pos).name ~= "tnt:tnt_burning" then
			return
		end
		core.sound_play("tnt_explode", {pos=pos, gain=1.5, max_hear_distance=10*64})
		core.set_node(pos, {name="tnt:boom"}, 2)
		core.after(0.5, function(pos)
			core.remove_node(pos, 2)
		end, {x=pos.x, y=pos.y, z=pos.z})
		

		local radius = 2
		local drops = {}
		local list = {}
		local dr = 0
		local tnts = 1
		local destroyed = 0
		local melted = 0
		local end_ms = os.clock() + time_max
		local last = nil;
		while dr<radius do
			dr=dr+1
			if os.clock() > end_ms or dr>=radius then last=1 end
			for dx=-dr,dr,dr*2 do
				for dy=-dr,dr,1 do
					for dz=-dr,dr,1 do
						table.insert(list, {x=dx, y=dy, z=dz})
					end
				end
			end
			for dy=-dr,dr,dr*2 do
				for dx=-dr+1,dr-1,1 do
					for dz=-dr,dr,1 do
						table.insert(list, {x=dx, y=dy, z=dz})
					end
				end
			end
			for dz=-dr,dr,dr*2 do
				for dx=-dr+1,dr-1,1 do
					for dy=-dr+1,dr-1,1 do
						table.insert(list, {x=dx, y=dy, z=dz})
					end
				end
			end
				for _,p in ipairs(list) do
					local np = {x=pos.x+p.x, y=pos.y+p.y, z=pos.z+p.z}
					
					local node =  core.get_node(np)
					if node.name == "air" then
					elseif node.name == "tnt:tnt" or node.name == "tnt:tnt_burning" then
						if radius < radius_max and not last and dr < radius then
							if radius <= 5 then
								radius = radius + 1
							elseif radius <= 10 then
								radius = radius + 0.5
							elseif radius <= 20 then
								radius = radius + 0.3
							else
								radius = radius + 0.2
							end
							core.remove_node(np, 2)
						tnts = tnts + 1
						else
						core.set_node(np, {name="tnt:tnt_burning"}, 2)
						boom(np, 1)
						end
					elseif node.name == "fire:basic_flame"
						--or string.find(node.name, "default:water_") 
						--or string.find(node.name, "default:lava_") 
						or node.name == "tnt:boom"
						then
						
					elseif liquid_real and last and radius > 10 and math.random(1,15) <= 1 then
						melted = melted + core.freeze_melt(np, 1)
					else
						if math.abs(p.x)<2 and math.abs(p.y)<2 and math.abs(p.z)<2 then
							destroy(drops, np, dr == radius, radius > 7)
							destroyed = destroyed + 1
						else
							if math.random(1,5) <= 4 then
								destroy(drops, np, dr == radius, radius > 7)
								destroyed = destroyed + 1
							end
						end
					end
				end
			if last then break end
		end

		local objects = core.get_objects_inside_radius(pos, radius*2)
		for _,obj in ipairs(objects) do
			--if obj:is_player() or (obj:get_luaentity() and obj:get_luaentity().name ~= "__builtin:item") then
				local p = obj:getpos()
				local v = obj:getvelocity()
				local vec = {x=p.x-pos.x, y=p.y-pos.y, z=p.z-pos.z}
				local dist = (vec.x^2+vec.y^2+vec.z^2)^0.5
				local damage = ((radius*20)/dist)
				--print("DMG dist="..dist.." damage="..damage)
				if obj:is_player() or (obj:get_luaentity() and obj:get_luaentity().name ~= "__builtin:item") then
				obj:punch(obj, 1.0, {
					full_punch_interval=1.0,
					damage_groups={fleshy=damage},
				}, vec)
				end
				if v ~= nil then
					--obj:setvelocity({x=(p.x - pos.x) + (radius / 4) + v.x, y=(p.y - pos.y) + (radius / 2) + v.y, z=(p.z - pos.z) + (radius / 4) + v.z})
					obj:setvelocity({x=(p.x - pos.x) + (radius / 2) + v.x, y=(p.y - pos.y) + radius + v.y,       z=(p.z - pos.z) + (radius / 2) + v.z})
				end
			--end
		end

		core.log("action", "tnt:tnt : exploded=" .. tnts .. " radius=".. dr .." radius_want=" .. radius .. " destroyed="..destroyed .. " melted="..melted)

		for _,stack in pairs(drops) do
			eject_drops(pos, stack)
		end
		local radiusp = radius+1
		core.add_particlespawner({
			amount=100,
			time=0.1,
			minpos={x=pos.x-radiusp, y=pos.y-radiusp, z=pos.z-radiusp},
			maxpos={x=pos.x+radiusp, y=pos.y+radiusp, z=pos.z+radiusp},
			minvel={x=-0, y=-0, z=-0},
			maxvel={x=0, y=0, z=0},
			minacc={x=-0.5,y=5,z=-0.5},
			maxacc={x=0.5,y=5,z=0.5},
			minexptime=0.1,
			minexptime=1,
			minsize=8,
			maxsize=15,
			collisiondetection=false,
			texture="tnt_smoke.png"
		})
	end, pos)
end

core.register_node("tnt:tnt", {
	description = "TNT",
	tiles = {"tnt_top.png", "tnt_bottom.png", "tnt_side.png"},
	is_ground_content = false,
	groups = {dig_immediate=2, mesecon=2},
	sounds = default.node_sound_wood_defaults(),
	
	on_punch = function(pos, node, puncher)
		if puncher:get_wielded_item():get_name() == "default:torch" then
			core.sound_play("tnt_ignite", {pos=pos})
			core.set_node(pos, {name="tnt:tnt_burning"})
			boom(pos, 4)
		elseif math.random(1, 200) <= 1 then
			boom(pos, 0.1, 1)
		end
	end,

	on_dig = function(pos, node, puncher)
		if math.random(1,10) <= 1 then
			boom(pos, 0.1, 1)
		else
			return core.node_dig(pos, node, puncher)
		end
	end,
	
	mesecons = {
		effector = {
			action_on = function(pos, node)
				core.set_node(pos, {name="tnt:tnt_burning"})
				boom(pos, 0)
			end
		},
	},
})

core.register_node("tnt:tnt_burning", {
	tiles = {{name="tnt_top_burning_animated.png", animation={type="vertical_frames", aspect_w=16, aspect_h=16, length=1}}, "tnt_bottom.png", "tnt_side.png"},
	light_source = 5,
	drop = "",
	sounds = default.node_sound_wood_defaults(),
})

core.register_node("tnt:boom", {
	drawtype = "plantlike",
	tiles = {"tnt_boom.png"},
	light_source = default.LIGHT_MAX,
	walkable = false,
	drop = "",
	groups = {dig_immediate=3},
})

burn = function(pos)
	if core.get_node(pos).name == "tnt:tnt" then
		core.sound_play("tnt_ignite", {pos=pos})
		core.set_node(pos, {name="tnt:tnt_burning"})
		boom(pos, 1)
		return
	end
	if core.get_node(pos).name ~= "tnt:gunpowder" then
		return
	end
	core.sound_play("tnt_gunpowder_burning", {pos=pos, gain=2})
	core.set_node(pos, {name="tnt:gunpowder_burning"})
	
	core.after(1, function(pos)
		if core.get_node(pos).name ~= "tnt:gunpowder_burning" then
			return
		end
		core.after(0.5, function(pos)
			core.remove_node(pos)
		end, {x=pos.x, y=pos.y, z=pos.z})
		for dx=-1,1 do
			for dz=-1,1 do
				for dy=-1,1 do
					pos.x = pos.x+dx
					pos.y = pos.y+dy
					pos.z = pos.z+dz
					
					if not (math.abs(dx) == 1 and math.abs(dz) == 1) then
						if dy == 0 then
							burn({x=pos.x, y=pos.y, z=pos.z})
						else
							if math.abs(dx) == 1 or math.abs(dz) == 1 then
								burn({x=pos.x, y=pos.y, z=pos.z})
							end
						end
					end
					
					pos.x = pos.x-dx
					pos.y = pos.y-dy
					pos.z = pos.z-dz
				end
			end
		end
	end, pos)
end

core.register_node("tnt:gunpowder", {
	description = "Gun Powder",
	drawtype = "raillike",
	paramtype = "light",
	is_ground_content = false,
	sunlight_propagates = true,
	walkable = false,
	tiles = {"tnt_gunpowder_straight.png", "tnt_gunpowder_curved.png", "tnt_gunpowder_t_junction.png", "tnt_gunpowder_crossing.png"},
	inventory_image = "tnt_gunpowder_inventory.png",
	wield_image = "tnt_gunpowder_inventory.png",
	selection_box = {
		type = "fixed",
		fixed = {-1/2, -1/2, -1/2, 1/2, -1/2+1/16, 1/2},
	},
	groups = {dig_immediate=2,attached_node=1,connect_to_raillike=minetest.raillike_group("gunpowder")},
	sounds = default.node_sound_leaves_defaults(),
	
	on_punch = function(pos, node, puncher)
		if puncher:get_wielded_item():get_name() == "default:torch" then
			burn(pos)
		end
	end,
})

core.register_node("tnt:gunpowder_burning", {
	drawtype = "raillike",
	paramtype = "light",
	sunlight_propagates = true,
	walkable = false,
	light_source = 5,
	tiles = {{
		name = "tnt_gunpowder_burning_straight_animated.png",
		animation = {
			type = "vertical_frames",
			aspect_w = 16,
			aspect_h = 16,
			length = 1,
		}
	},
	{
		name = "tnt_gunpowder_burning_curved_animated.png",
		animation = {
			type = "vertical_frames",
			aspect_w = 16,
			aspect_h = 16,
			length = 1,
		}
	},
	{
		name = "tnt_gunpowder_burning_t_junction_animated.png",
		animation = {
			type = "vertical_frames",
			aspect_w = 16,
			aspect_h = 16,
			length = 1,
		}
	},
	{
		name = "tnt_gunpowder_burning_crossing_animated.png",
		animation = {
			type = "vertical_frames",
			aspect_w = 16,
			aspect_h = 16,
			length = 1,
		}
	}},
	selection_box = {
		type = "fixed",
		fixed = {-1/2, -1/2, -1/2, 1/2, -1/2+1/16, 1/2},
	},
	drop = "",
	groups = {dig_immediate=2,attached_node=1,connect_to_raillike=minetest.raillike_group("gunpowder")},
	sounds = default.node_sound_leaves_defaults(),
})

core.register_abm({
	nodenames = {"tnt:tnt", "tnt:gunpowder"},
	neighbors = {"fire:basic_flame", "default:lava_source", "default:lava_flowing"},
	interval = 2,
	chance = 10,
	action = function(pos, node)
		if node.name == "tnt:tnt" then
			core.set_node(pos, {name="tnt:tnt_burning"})
			boom({x=pos.x, y=pos.y, z=pos.z}, 0)
		else
			burn(pos)
		end
	end
})

core.register_craft({
	output = "tnt:gunpowder",
	type = "shapeless",
	recipe = {"default:coal_lump", "default:gravel"}
})

core.register_craft({
	output = "tnt:tnt",
	recipe = {
		{"", "group:wood", ""},
		{"group:wood", "tnt:gunpowder", "group:wood"},
		{"", "group:wood", ""}
	}
})

if core.setting_get("log_mods") then
	core.log("action", "tnt loaded")
end
