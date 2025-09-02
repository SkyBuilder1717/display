local modname = core.get_current_modname()

_G[modname] = {
    pixels = {},
    S = core.get_translator(modname),
    saved_pictures = {}
}

local BASE_URL = core.settings:get(modname .. ".base_url") or "https://skybuilder.synology.me/display/convert"

local S = _G[modname].S

local pf = "[" .. modname .. "] "
local TEX = modname .. "_pixel.png"
local http = core.request_http_api()

local function hex(r,g,b)
    return string.format("#%02X%02X%02X", r,g,b)
end

local function alpha(a)
    return math.max(0, math.min(255, a))
end

core.register_entity(modname .. ":pixel", {
    initial_properties = {
        visual = "sprite",
        visual_size = {x = 1, y = 1},
        textures = {TEX},
        use_texture_alpha = true,
        physical = false,
        pointable = false,
        collide_with_objects = false,
        static_save = false
    },
    on_activate = function(self, sd)
        if sd and sd ~= "" then
            local d = core.parse_json(sd)
            if d then
                self.object:set_properties({
                    textures = {TEX},
                    visual_size = {x = d.size, y = d.size}
                })
                self.object:set_texture_mod("^[multiply:" .. hex(d.r, d.g, d.b) .. "^[opacity:" .. alpha(d.a))
            end
        end
    end,
    get_staticdata = function(self)
        return self._data and core.write_json(self._data) or ""
    end
})

local function remove_image(name)
    local list = _G[modname].pixels[name]
    if list then
        for _, obj in ipairs(list) do
            if obj and obj:get_luaentity() and obj:is_valid() then
                obj:remove()
            end
        end
        _G[modname].pixels[name] = nil
    end
end

local function spawn_pixel(base, x, y, r, g, b, a, size, rot, dir, name)
    local pos = {x = base.x, y = base.y, z = base.z}
    if dir == "y+" then
        pos.x = base.x + x*size
        pos.z = base.z + y*size
    elseif dir == "y-" then
        pos.x = base.x + x*size
        pos.z = base.z - y*size
    elseif dir == "x+" then
        pos.z = base.z + x*size
        pos.y = base.y - y*size
    elseif dir == "x-" then
        pos.z = base.z - x*size
        pos.y = base.y - y*size
    elseif dir == "z-" then
        pos.x = base.x - x*size
        pos.y = base.y - y*size
    else
        pos.x = base.x + x*size
        pos.y = base.y - y*size
    end
    local o = core.add_entity(pos, modname .. ":pixel")
    if o then
        local e = o:get_luaentity()
        if e then
            e._data = {r = r, g = g, b = b, a = a, size = size}
            o:set_properties({
                visual_size = {x = size, y = size},
                textures = {TEX},
                rotation= rot
            })
            o:set_texture_mod("^[multiply:" .. hex(r, g, b) .. "^[opacity:" .. alpha(a))
            _G[modname].pixels[name] = _G[modname].pixels[name] or {}
            table.insert(_G[modname].pixels[name], o)
        end
    end
end

local function render_image(pos, tbl, size, rot, dir, name)
    local w, h = tbl.width, tbl.height
    local px = tbl.pixels
    if not (w and h and px and #px == w*h) then return false end

    local flipped_x = false
    local flipped_y = false
    if dir == "y+" then
        flipped_x = true
        flipped_y = true
    end
    if dir == "x+" or dir == "x-" then
        flipped_x = true
    end

    for y=0,h-1 do
        local iy = y
        if flipped_y then
            iy = h - 1 - y
        end
        for x=0,w-1 do
            local ix = x
            if flipped_x then
                ix = w - 1 - x
            end
            local p = px[iy*w + ix + 1]
            if p[4] > 0 then
                spawn_pixel(pos, x, y, p[1], p[2], p[3], p[4], size, rot, dir, name)
            end
        end
    end
    return true
end

local function get_rotation(player)
    local dir = player:get_look_dir()
    if math.abs(dir.y) > math.abs(dir.x) and math.abs(dir.y) > math.abs(dir.z) then
        if dir.y > 0 then
            return {x=-math.pi/2, y=0, z=0}
        else
            return {x=math.pi/2, y=0, z=0}
        end
    elseif math.abs(dir.x) > math.abs(dir.z) then
        if dir.x > 0 then
            return {x=0, y=math.pi/2, z=0}
        else
            return {x=0, y=-math.pi/2, z=0}
        end
    else
        if dir.z > 0 then
            return {x=0, y=0, z=0}
        else
            return {x=0, y=math.pi, z=0}
        end
    end
end

core.register_chatcommand(modname, {
    params = "<url> <size>",
    description = S("Render url image"),
    privs = {server=true},
    func = function(name, param)
        local player = core.get_player_by_name(name)
        if not player then return false, S("No player") end
        if not http then return false, S("HTTP not available") end
        local img_url, size_s = param:match("^(%S+)%s+(%S+)$")
        if not img_url or not size_s then return false end
        local size = tonumber(size_s) or 0.1
        local pos = vector.round(player:get_pos()); pos.y = pos.y + 1
        local rot = get_rotation(player)
        local dir
        local d = player:get_look_dir()
        if math.abs(d.y) > math.abs(d.x) and math.abs(d.y) > math.abs(d.z) then
            dir = d.y > 0 and "y+" or "y-"
        elseif math.abs(d.x) > math.abs(d.z) then
            dir = d.x > 0 and "x+" or "x-"
        else
            dir = d.z > 0 and "z+" or "z-"
        end
        local url = BASE_URL .. "?url="..core.formspec_escape(img_url)
        local tbl = _G[modname].saved_pictures[url]
        if tbl then
            core.chat_send_player(name, S("Saved picture found!"))
            remove_image(name)
            local ok = render_image(pos, tbl, size, rot, dir, name)
            if not ok then
                return false, pf.. S("Render failed")
            end
            return true, pf.. S("Done")
        end
        http.fetch({url = url, timeout = 20}, function(res)
            if res.timeout then
                core.chat_send_player(name, pf.. S("Time out connection"))
                return
            end
            if not res.succeeded or res.code ~= 200 then
                core.chat_send_player(name, pf.. S("HTTP error"))
                return
            end
            local tbl = core.parse_json(res.data)
            if not tbl then
                core.chat_send_player(name, pf.. S("Bad JSON"))
                return
            end
            if tbl.error then
                core.chat_send_player(name, pf.. S("Server error: @1", tbl.error))
                return
            end
            _G[modname].saved_pictures[url] = tbl
            remove_image(name)
            local ok = render_image(pos, tbl, size, rot, dir, name)
            if not ok then
                core.chat_send_player(name, pf.. S("Render failed"))
                return
            end
            core.chat_send_player(name, pf.. S("Done"))
        end)
        return true, S("Fetching...")
    end
})