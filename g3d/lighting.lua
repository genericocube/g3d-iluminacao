-- lighting module for g3d
-- MIT license

local g3d = package.loaded[(...):match("^(.*)%.[^.]+$")]
local camera = require(g3d.path .. ".camera")

----------------------------------------------------------------------------------------------------
-- lighting singleton
----------------------------------------------------------------------------------------------------
-- one directional light (sun), a flat ambient color, and up to maxLights point lights
-- all colors are {r, g, b} with values from 0 to 1

local MAX_LIGHTS = 8 -- must match MAX_LIGHTS in light.frag

local lighting = {
    maxLights = MAX_LIGHTS,
    ambient = {0.15, 0.15, 0.2},
    sun = {
        enabled = true,
        direction = {-0.4, -0.3, -0.8},
        color = {1, 0.95, 0.85},
        intensity = 1,
    },
    lights = {},
}

-- bumped every time something changes, shaders only get new data when this changes
local version = 0
-- what each shader last received, keyed weakly so shaders can be collected
local sent = setmetatable({}, {__mode = "k"})

-- call this after editing lighting.ambient or lighting.sun fields directly
function lighting.markDirty()
    version = version + 1
end

function lighting.setAmbient(r, g, b)
    lighting.ambient[1], lighting.ambient[2], lighting.ambient[3] = r, g or r, b or r
    version = version + 1
end

function lighting.setSun(dx, dy, dz, r, g, b, intensity)
    local sun = lighting.sun
    if dx then sun.direction[1], sun.direction[2], sun.direction[3] = dx, dy, dz end
    if r then sun.color[1], sun.color[2], sun.color[3] = r, g, b end
    if intensity then sun.intensity = intensity end
    version = version + 1
end

function lighting.setSunEnabled(enabled)
    lighting.sun.enabled = enabled and true or false
    version = version + 1
end

----------------------------------------------------------------------------------------------------
-- point lights
----------------------------------------------------------------------------------------------------

local light = {}
light.__index = light

function light:setPosition(x, y, z)
    self.position[1], self.position[2], self.position[3] = x, y, z
    version = version + 1
end

function light:setColor(r, g, b)
    self.color[1], self.color[2], self.color[3] = r, g, b
    version = version + 1
end

function light:setRadius(radius)
    self.radius = radius
    version = version + 1
end

function light:setIntensity(intensity)
    self.intensity = intensity
    version = version + 1
end

function light:setEnabled(enabled)
    self.enabled = enabled and true or false
    version = version + 1
end

-- returns a new point light, or nil if there are already maxLights of them
function lighting.newLight(x, y, z, r, g, b, radius, intensity)
    if #lighting.lights >= MAX_LIGHTS then
        print("[g3d warning] maximum of " .. MAX_LIGHTS .. " point lights reached")
        return nil
    end
    local self = setmetatable({
        position = {x or 0, y or 0, z or 0},
        color = {r or 1, g or r or 1, b or r or 1},
        radius = radius or 10,
        intensity = intensity or 1,
        enabled = true,
    }, light)
    table.insert(lighting.lights, self)
    version = version + 1
    return self
end

function lighting.removeLight(target)
    for i, l in ipairs(lighting.lights) do
        if l == target then
            table.remove(lighting.lights, i)
            version = version + 1
            return true
        end
    end
    return false
end

function lighting.clear()
    lighting.lights = {}
    version = version + 1
end

----------------------------------------------------------------------------------------------------
-- sending data to shaders
----------------------------------------------------------------------------------------------------

local function sendIfPresent(shader, name, ...)
    if shader:hasUniform(name) then shader:send(name, ...) end
end

-- sends the whole lighting state to a shader built from light.frag
-- called automatically by model:draw, only does work when something changed
function lighting.apply(shader)
    local cam = camera.position
    local state = sent[shader]
    if not state then
        state = {version = -1}
        sent[shader] = state
    end

    -- the camera moves often, but only the specular highlight depends on it
    if state.cx ~= cam[1] or state.cy ~= cam[2] or state.cz ~= cam[3] then
        state.cx, state.cy, state.cz = cam[1], cam[2], cam[3]
        sendIfPresent(shader, "cameraPosition", {cam[1], cam[2], cam[3]})
    end

    if state.version == version then return end
    state.version = version

    local a, sun = lighting.ambient, lighting.sun
    sendIfPresent(shader, "ambientColor", {a[1], a[2], a[3]})

    local k = sun.enabled and sun.intensity or 0
    sendIfPresent(shader, "sunDirection", {sun.direction[1], sun.direction[2], sun.direction[3]})
    sendIfPresent(shader, "sunColor", {sun.color[1]*k, sun.color[2]*k, sun.color[3]*k})

    -- pack the enabled point lights, padded with zeros up to the fixed array size
    local positions, colors, radii = {}, {}, {}
    local count = 0
    for _, l in ipairs(lighting.lights) do
        if l.enabled then
            count = count + 1
            positions[count] = {l.position[1], l.position[2], l.position[3]}
            colors[count] = {l.color[1]*l.intensity, l.color[2]*l.intensity, l.color[3]*l.intensity}
            radii[count] = l.radius
        end
    end
    for i = count + 1, MAX_LIGHTS do
        positions[i], colors[i], radii[i] = {0, 0, 0}, {0, 0, 0}, 1
    end
    sendIfPresent(shader, "lightCount", count)
    sendIfPresent(shader, "lightPositions", unpack(positions))
    sendIfPresent(shader, "lightColors", unpack(colors))
    sendIfPresent(shader, "lightRadii", unpack(radii))
end

return lighting
