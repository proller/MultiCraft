-- Weather:
-- * rain
-- * snow
-- * wind (not implemented)

assert(core.add_particlespawner, "I told you to run the latest GitHub!")
assert(core.get_heat, "I told you to run the latest freeminer!")

addvectors = function (v1, v2)
	return {x=v1.x+v2.x, y=v1.y+v2.y, z=v1.z+v2.z}
end

local cloud_height = tonumber(core.setting_get("cloud_height"));
local snow_humidity = 65
local rain_humidity = 75

get_snow = function (p)
	if not p then return 0 end
	if p.y > cloud_height then return 0 end
	local heat = core.get_heat(p)
	if heat >= 0 then return 0 end
	local humidity = core.get_humidity(p)
	if humidity < snow_humidity then return 0 end
	--print('S h='..core.get_heat(p)..' h='..core.get_humidity(p))
	return (humidity-snow_humidity)/(100-snow_humidity)
end

get_rain = function (p)
	if not p then return 0 end
	if p.y > cloud_height then return 0 end
	local heat = core.get_heat(p)
	if heat <= 0 then return 0 end
	if heat > 50 then return 0 end
	local humidity = core.get_humidity(p)
	if humidity < rain_humidity then return 0 end
	--print('R h='..core.get_heat(p)..' h='..core.get_humidity(p))
	return (humidity-rain_humidity)/(100-rain_humidity)
end

if default.weather then
	if core.setting_getbool("liquid_real") then
		dofile(core.get_modpath("weather").."/rain.lua")
	end

	dofile(core.get_modpath("weather").."/snow.lua")
end
