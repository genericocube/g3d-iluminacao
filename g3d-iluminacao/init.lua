-- g3d-iluminacao
-- feito por generico_cube
-- Real-time lighting for g3d 1.6.0: sun with shadows, point / spot / directional lights,
-- hemisphere ambient, rim light, toon shading, fog, quality presets and culling.
-- MIT License. See the repository LICENSE file.

local g3d = require("g3d")
local newMatrix = require(g3d.path .. ".matrices")

local Lighting = {}
Lighting.__index = Lighting

local Light = {}
Light.__index = Light
Lighting.Light = Light

local MODULE_PATH = (...):gsub("%.", "/")
local SHADER_DIR = MODULE_PATH .. "/shaders/"

local DEFAULT_MAX_LIGHTS = 16 -- size of the light arrays in the shader (can be changed in Lighting.new)
local ABSOLUTE_MAX_LIGHTS = 32

local TYPE_CODE = { point = 0, spot = 1, directional = 2 }

-- quality presets: shadow-map size, shadow filter (0 = 1 tap, 1 = 3x3, 2 = 5x5)
-- and how many local lights are shaded at once
local QUALITY = {
    low    = { shadowResolution = 512,  shadowPcf = 0, lightLimit = 4 },
    medium = { shadowResolution = 1024, shadowPcf = 1, lightLimit = 8 },
    high   = { shadowResolution = 2048, shadowPcf = 1, lightLimit = 16 },
    ultra  = { shadowResolution = 4096, shadowPcf = 2, lightLimit = 32 },
}

local function readShader(path)
    local source, err = love.filesystem.read(path)
    assert(source, ("[g3d-iluminacao] Could not read %s: %s"):format(path, tostring(err)))
    return source
end

local function vec3(value, fallback)
    value = value or fallback
    return { value[1] or 0, value[2] or 0, value[3] or 0 }
end

local function normalize(x, y, z)
    local length = math.sqrt(x*x + y*y + z*z)
    assert(length > 0.000001, "[g3d-iluminacao] Direction vector cannot be zero.")
    return x/length, y/length, z/length
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function multiplyMatrices(a, b)
    local result = {}
    for row = 0, 3 do
        for column = 0, 3 do
            local value = 0
            for k = 0, 3 do
                value = value + a[row*4 + k + 1] * b[k*4 + column + 1]
            end
            result[row*4 + column + 1] = value
        end
    end
    return result
end

-- sends a uniform only if the shader kept it (the compiler drops unused uniforms)
local function send(shader, name, ...)
    if shader:hasUniform(name) then
        shader:send(name, ...)
    end
end

-- bounding sphere (center + radius) of a vertex table, used for culling
local function computeBounds(verts)
    if type(verts) ~= "table" or #verts == 0 then return nil end

    local minX, minY, minZ = math.huge, math.huge, math.huge
    local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
    for i = 1, #verts do
        local v = verts[i]
        local x, y, z = v[1], v[2], v[3]
        if x < minX then minX = x end
        if y < minY then minY = y end
        if z < minZ then minZ = z end
        if x > maxX then maxX = x end
        if y > maxY then maxY = y end
        if z > maxZ then maxZ = z end
    end

    local cx, cy, cz = (minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2
    local radiusSquared = 0
    for i = 1, #verts do
        local v = verts[i]
        local dx, dy, dz = v[1] - cx, v[2] - cy, v[3] - cz
        local d = dx*dx + dy*dy + dz*dz
        if d > radiusSquared then radiusSquared = d end
    end
    return cx, cy, cz, math.sqrt(radiusSquared)
end

----------------------------------------------------------------------------------------------------
-- lights
----------------------------------------------------------------------------------------------------
-- a light is a table with these public fields (you can also change them directly):
--   type ("point", "spot" or "directional"), position, color, intensity, range, direction,
--   target (spot only, optional), innerAngle, outerAngle (degrees), enabled

function Light:setPosition(x, y, z)
    self.position[1], self.position[2], self.position[3] = x, y, z
    return self
end

function Light:setColor(r, g, b)
    self.color[1], self.color[2], self.color[3] = r, g, b
    return self
end

function Light:setIntensity(value)
    self.intensity = math.max(0, value)
    return self
end

function Light:setRange(value)
    assert(value > 0, "[g3d-iluminacao] Light range must be greater than zero.")
    self.range = value
    return self
end

-- the direction the light points to (spot and directional lights)
function Light:setDirection(x, y, z)
    self.direction[1], self.direction[2], self.direction[3] = normalize(x, y, z)
    self.target = nil
    return self
end

-- aim a spot light at a point; the light keeps pointing at it when it moves
-- call setTarget(nil) to go back to a fixed direction
function Light:setTarget(x, y, z)
    if x == nil then
        self.target = nil
    else
        self.target = { x, y, z }
    end
    return self
end

-- cone angles in degrees: full brightness inside innerAngle, fades out until outerAngle
function Light:setAngles(innerAngle, outerAngle)
    outerAngle = outerAngle or self.outerAngle
    innerAngle = innerAngle or self.innerAngle
    assert(outerAngle > 0 and outerAngle < 90, "[g3d-iluminacao] outerAngle must be between 0 and 90 degrees.")
    assert(innerAngle >= 0 and innerAngle <= outerAngle, "[g3d-iluminacao] innerAngle must be between 0 and outerAngle.")
    self.innerAngle, self.outerAngle = innerAngle, outerAngle
    return self
end

function Light:setEnabled(enabled)
    self.enabled = not not enabled
    return self
end

-- makes the intensity wobble like a torch or a candle
-- amount: 0 to 1 (how much it varies), speed: how fast (around 8 is a nice torch)
-- setFlicker(0) turns it off
function Light:setFlicker(amount, speed)
    self.flickerAmount = clamp(amount or 0, 0, 1)
    self.flickerSpeed = speed or self.flickerSpeed or 8
    return self
end

function Light:remove()
    if self.owner then
        return self.owner:removeLight(self)
    end
    return false
end

local function newLight(self, kind, options)
    options = options or {}

    local light = setmetatable({
        type = kind,
        position = vec3(options.position, { 0, 0, 0 }),
        color = vec3(options.color, { 1, 1, 1 }),
        intensity = math.max(0, options.intensity or 1),
        range = options.range or 8,
        direction = vec3(options.direction, { 0, 0, -1 }),
        innerAngle = 20,
        outerAngle = 35,
        enabled = options.enabled ~= false,
        flickerAmount = 0,
        flickerSpeed = 8,
        phase = math.random() * 100,
        owner = self,
    }, Light)

    assert(light.range > 0, "[g3d-iluminacao] Light range must be greater than zero.")

    if kind ~= "point" then
        light.direction[1], light.direction[2], light.direction[3] =
            normalize(light.direction[1], light.direction[2], light.direction[3])
    end

    if kind == "spot" then
        light:setAngles(options.innerAngle, options.outerAngle)
        if options.target then
            light.target = vec3(options.target)
        end
    end

    if options.flicker then
        if type(options.flicker) == "table" then
            light:setFlicker(options.flicker.amount or options.flicker[1], options.flicker.speed or options.flicker[2])
        else
            light:setFlicker(options.flicker)
        end
    end

    self.lights[#self.lights + 1] = light
    return light
end

----------------------------------------------------------------------------------------------------
-- creating a lighting system
----------------------------------------------------------------------------------------------------
-- options (all optional):
--   quality              "low", "medium" (default), "high" or "ultra"
--   shadowResolution     512, 1024, 2048 or 4096 (overrides the quality preset)
--   shadowPcf            0, 1 or 2: shadow edge softness (overrides the quality preset)
--   lightLimit           how many local lights are shaded at once (overrides the preset)
--   maxLights            size of the light arrays in the shader, 1 to 32 (default 16)
--   shadowsEnabled, lightsEnabled, shadowRange, shadowDistance, shadowBias, shadowStrength
--   shadowUpdateEvery    redraw the shadow map every N frames (default 1)
--   frustumCulling       skip models outside the camera view (default true)
--   ambientColor, ambientGround (hemisphere), directionalColor, directionalIntensity
--   exposure, toonSteps, lightDistance

function Lighting.new(options)
    options = options or {}

    assert(love and love.graphics and love.graphics.newShader,
        "[g3d-iluminacao] LÖVE graphics must be initialized before creating Lighting.")

    local quality = options.quality or "medium"
    local preset = QUALITY[quality]
    assert(preset, "[g3d-iluminacao] quality must be \"low\", \"medium\", \"high\" or \"ultra\".")

    local maxLights = options.maxLights or DEFAULT_MAX_LIGHTS
    assert(maxLights >= 1 and maxLights <= ABSOLUTE_MAX_LIGHTS,
        "[g3d-iluminacao] maxLights must be between 1 and " .. ABSOLUTE_MAX_LIGHTS .. ".")

    local self = setmetatable({}, Lighting)
    self.g3d = g3d
    self.models = {}
    self.lights = {}
    self.maxLights = math.floor(maxLights)
    self.quality = quality

    self.direction = { 0.4, 0.35, -0.8 }
    self.directionalColor = vec3(options.directionalColor, { 1.0, 0.94, 0.82 })
    self.directionalIntensity = options.directionalIntensity or 0.9
    self.ambientColor = vec3(options.ambientColor, { 0.19, 0.21, 0.26 })
    self.ambientGround = options.ambientGround and vec3(options.ambientGround) or nil

    self.shadowsEnabled = options.shadowsEnabled ~= false
    self.lightsEnabled = options.lightsEnabled ~= false
    self.shadowRange = options.shadowRange or 22
    self.shadowDistance = options.shadowDistance or 42
    self.shadowBias = options.shadowBias or 0.0018
    self.shadowStrength = options.shadowStrength or 0.9
    self.shadowPcf = options.shadowPcf or preset.shadowPcf
    self.shadowUpdateEvery = math.max(1, math.floor(options.shadowUpdateEvery or 1))
    self.lightLimit = math.min(options.lightLimit or preset.lightLimit, self.maxLights)
    self.lightDistance = options.lightDistance or 0
    self.frustumCulling = options.frustumCulling ~= false
    self.exposure = options.exposure or 1
    self.toonSteps = options.toonSteps or 0
    self.rim = nil
    self.fog = nil

    self.lightView = newMatrix()
    self.lightProjection = newMatrix()
    self.lightViewProjection = {}
    for i = 1, 16 do self.lightViewProjection[i] = 0 end

    -- buffers reused every frame so lighting does not create garbage
    self._lightA, self._lightB, self._lightC, self._lightD = {}, {}, {}, {}
    for i = 1, self.maxLights do
        self._lightA[i] = { 0, 0, 0, 1 }
        self._lightB[i] = { 0, 0, 0, 0 }
        self._lightC[i] = { 0, 0, -1, -2 }
        self._lightD[i] = 0
    end
    self._visibleLights = {}
    self._lightCount = 0
    self._lastLightVP = {}
    self._frame = 0
    self._lastShadowFrame = -math.huge
    self._shadowValid = false

    self.stats = {
        modelsDrawn = 0, modelsCulled = 0,
        shadowCasters = 0, shadowUpdated = false, shadowUpdates = 0,
        lightsActive = 0, lightsTotal = 0,
    }

    local define = "#define MAX_LIGHTS " .. self.maxLights .. "\n"
    self.lightingShader = love.graphics.newShader(define .. readShader(SHADER_DIR .. "lighting.glsl"))
    self.shadowShader = love.graphics.newShader(readShader(SHADER_DIR .. "shadow.glsl"))

    self:setDirection(unpack(self.direction))
    self:setShadowResolution(options.shadowResolution or preset.shadowResolution)

    return self
end

-- applies a quality preset: shadow-map size, shadow softness and the local light limit
function Lighting:setQuality(name)
    local preset = QUALITY[name]
    assert(preset, "[g3d-iluminacao] quality must be \"low\", \"medium\", \"high\" or \"ultra\".")
    self.quality = name
    self:setShadowResolution(preset.shadowResolution)
    self.shadowPcf = preset.shadowPcf
    self.lightLimit = math.min(preset.lightLimit, self.maxLights)
    return self
end

----------------------------------------------------------------------------------------------------
-- sun, ambient and look
----------------------------------------------------------------------------------------------------

function Lighting:setDirection(x, y, z)
    self.direction[1], self.direction[2], self.direction[3] = normalize(x, y, z)
    return self
end

function Lighting:setDirectionalDirection(x, y, z)
    return self:setDirection(x, y, z)
end

function Lighting:setDirectionalColor(r, g, b)
    self.directionalColor[1] = r
    self.directionalColor[2] = g
    self.directionalColor[3] = b
    return self
end

function Lighting:setDirectionalIntensity(value)
    self.directionalIntensity = math.max(0, value)
    return self
end

function Lighting:setAmbient(value)
    if type(value) == "number" then
        self.ambientColor[1], self.ambientColor[2], self.ambientColor[3] = value, value, value
    else
        self.ambientColor = vec3(value, self.ambientColor)
    end
    return self
end

-- hemisphere ambient: sky color lights the surfaces facing up, ground color the ones facing down
-- setHemisphere(nil) goes back to a flat ambient
function Lighting:setHemisphere(sky, ground)
    if sky == nil then
        self.ambientGround = nil
        return self
    end
    self:setAmbient(sky)
    if type(ground) == "number" then
        self.ambientGround = { ground, ground, ground }
    else
        self.ambientGround = vec3(ground, self.ambientColor)
    end
    return self
end

-- rim light: a colored glow on the edges of objects, seen from the camera
-- setRim(nil) turns it off
function Lighting:setRim(color, power, strength)
    if color == nil then
        self.rim = nil
    else
        self.rim = { color = vec3(color), power = power or 3, strength = strength or 0.6 }
    end
    return self
end

-- toon (cel) shading: steps is the number of light bands, setToon(0) or setToon(false) turns it off
function Lighting:setToon(steps)
    if not steps then steps = 0 end
    if steps == true then steps = 3 end
    self.toonSteps = math.max(0, math.floor(steps))
    return self
end

-- linear fog between near and far distances from the camera
-- setFog(nil) turns it off
function Lighting:setFog(color, near, far)
    if color == nil then
        self.fog = nil
    else
        assert(far and near and far > near, "[g3d-iluminacao] setFog needs near < far.")
        self.fog = { color = vec3(color), near = near, far = far }
    end
    return self
end

-- overall brightness multiplier
function Lighting:setExposure(value)
    self.exposure = math.max(0, value)
    return self
end

----------------------------------------------------------------------------------------------------
-- shadow options
----------------------------------------------------------------------------------------------------

function Lighting:setShadowRange(value)
    assert(value > 0, "[g3d-iluminacao] Shadow range must be greater than zero.")
    self.shadowRange = value
    return self
end

function Lighting:setShadowDistance(value)
    assert(value > 0, "[g3d-iluminacao] Shadow distance must be greater than zero.")
    self.shadowDistance = value
    return self
end

function Lighting:setShadowBias(value)
    self.shadowBias = math.max(0, value)
    return self
end

function Lighting:setShadowStrength(value)
    self.shadowStrength = clamp(value, 0, 1)
    return self
end

function Lighting:setShadowsEnabled(enabled)
    enabled = not not enabled
    if enabled and not self.shadowsEnabled then
        self._shadowValid = false -- the map is out of date after being off
    end
    self.shadowsEnabled = enabled
    return self
end

-- shadow edge softness: 0 = hard (fastest), 1 = soft (3x3), 2 = softer (5x5)
function Lighting:setShadowPcf(level)
    assert(level == 0 or level == 1 or level == 2, "[g3d-iluminacao] Shadow filter must be 0, 1 or 2.")
    self.shadowPcf = level
    return self
end

-- redraw the shadow map only every N frames (2 or 3 saves a lot of time in busy scenes)
function Lighting:setShadowUpdateEvery(frames)
    self.shadowUpdateEvery = math.max(1, math.floor(frames))
    return self
end

function Lighting:setShadowResolution(resolution)
    assert(
        resolution == 512 or resolution == 1024 or resolution == 2048 or resolution == 4096,
        "[g3d-iluminacao] Shadow resolution must be 512, 1024, 2048 or 4096."
    )

    if self.shadowMap and self.shadowResolution == resolution then
        return self
    end

    local newCanvas = love.graphics.newCanvas(resolution, resolution, {
        format = "rgba8",
        readable = true,
        msaa = 0,
        dpiscale = 1
    })

    newCanvas:setFilter("nearest", "nearest")
    newCanvas:setWrap("clamp", "clamp")

    if self.shadowMap then
        self.shadowMap:release()
    end

    self.shadowMap = newCanvas
    self.shadowResolution = resolution
    self.shadowTexelSize = 1 / resolution
    self._shadowValid = false
    return self
end

----------------------------------------------------------------------------------------------------
-- performance options
----------------------------------------------------------------------------------------------------

-- turns all point / spot / directional lights on or off (the sun is not affected)
function Lighting:setLightsEnabled(enabled)
    self.lightsEnabled = not not enabled
    return self
end
Lighting.setPointLightsEnabled = Lighting.setLightsEnabled -- old name

-- how many local lights are shaded at once (the most important ones are chosen)
function Lighting:setLightLimit(count)
    self.lightLimit = clamp(math.floor(count), 0, self.maxLights)
    return self
end

-- ignore local lights farther than this from the camera (0 = no limit)
function Lighting:setLightDistance(distance)
    self.lightDistance = math.max(0, distance)
    return self
end

-- skip drawing models that are outside the camera view
function Lighting:setFrustumCulling(enabled)
    self.frustumCulling = not not enabled
    return self
end

-- numbers from the last frame: models drawn / culled, shadow casters, shadow-map redraws, lights used
function Lighting:getStats()
    return self.stats
end

----------------------------------------------------------------------------------------------------
-- models
----------------------------------------------------------------------------------------------------
-- options: castsShadow, receivesShadows, specularStrength, shininess, emissiveColor,
--          emissiveStrength, frustumCulled (default true)

function Lighting:addModel(model, options)
    assert(model and model.mesh and model.matrix,
        "[g3d-iluminacao] addModel expects a model created by g3d.newModel().")

    options = options or {}
    if type(options) == "boolean" then
        options = { castsShadow = options }
    end

    local entry = {
        model = model,
        castsShadow = options.castsShadow ~= false,
        receivesShadows = options.receivesShadows ~= false,
        specularStrength = options.specularStrength == nil and 0.18 or options.specularStrength,
        shininess = options.shininess or 32,
        emissiveColor = vec3(options.emissiveColor, { 0, 0, 0 }),
        emissiveStrength = options.emissiveStrength or 0,
        frustumCulled = options.frustumCulled ~= false,
        visible = true,
        shadowVisible = true,
        _sm = {}, -- copy of the matrix the shadow map was last drawn with
    }
    for i = 1, 12 do entry._sm[i] = 0 end
    entry.bx, entry.by, entry.bz, entry.radius = computeBounds(model.verts)

    self.models[#self.models + 1] = entry
    self._shadowValid = false
    return model, entry
end

-- call this if you changed a model's vertices after adding it (the culling bounds are recomputed)
function Lighting:updateBounds(model)
    for i = 1, #self.models do
        local entry = self.models[i]
        if entry.model == model then
            entry.bx, entry.by, entry.bz, entry.radius = computeBounds(model.verts)
            return true
        end
    end
    return false
end

function Lighting:removeModel(model)
    for i = #self.models, 1, -1 do
        if self.models[i].model == model then
            table.remove(self.models, i)
            self._shadowValid = false
            return true
        end
    end
    return false
end

function Lighting:clearModels()
    for i = #self.models, 1, -1 do
        self.models[i] = nil
    end
    self._shadowValid = false
end

----------------------------------------------------------------------------------------------------
-- local lights
----------------------------------------------------------------------------------------------------
-- you can create as many lights as you want: each frame only the most important
-- ones (closest and brightest, up to lightLimit) are sent to the GPU.

-- options: position, color, intensity, range, flicker, enabled
function Lighting:addPointLight(options)
    return newLight(self, "point", options)
end

-- options: position, direction (or target), color, intensity, range, innerAngle, outerAngle (degrees),
--          flicker, enabled
function Lighting:addSpotLight(options)
    return newLight(self, "spot", options)
end

-- a light that shines from one direction on everything, with no position, falloff or shadows
-- (a cheap fill / moon light). options: direction, color, intensity, enabled
function Lighting:addDirectionalLight(options)
    return newLight(self, "directional", options)
end

function Lighting:removeLight(light)
    for i = #self.lights, 1, -1 do
        if self.lights[i] == light then
            table.remove(self.lights, i)
            return true
        end
    end
    return false
end
Lighting.removePointLight = Lighting.removeLight -- old name

function Lighting:clearLights()
    for i = #self.lights, 1, -1 do
        self.lights[i] = nil
    end
end

----------------------------------------------------------------------------------------------------
-- per frame work
----------------------------------------------------------------------------------------------------

function Lighting:_updateLightMatrices()
    local camera = self.g3d.camera
    local lookX, lookY, lookZ = camera.getLookVector()

    local centerX = camera.position[1] + lookX * self.shadowRange * 0.35
    local centerY = camera.position[2] + lookY * self.shadowRange * 0.35
    local centerZ = camera.position[3] + lookZ * self.shadowRange * 0.35

    local dx, dy, dz = self.direction[1], self.direction[2], self.direction[3]
    local eye = {
        centerX - dx * self.shadowDistance,
        centerY - dy * self.shadowDistance,
        centerZ - dz * self.shadowDistance
    }
    local target = { centerX, centerY, centerZ }
    local up = { 0, 0, 1 }

    if math.abs(dz) > 0.96 then
        up = { 0, 1, 0 }
    end

    self.lightView:setViewMatrix(eye, target, up)

    -- Texel snapping reduces shadow shimmer while the camera moves.
    local worldUnitsPerTexel = (self.shadowRange * 2) / self.shadowResolution
    self.lightView[4] = math.floor(self.lightView[4] / worldUnitsPerTexel + 0.5) * worldUnitsPerTexel
    self.lightView[8] = math.floor(self.lightView[8] / worldUnitsPerTexel + 0.5) * worldUnitsPerTexel

    self.lightProjection:setOrthographicMatrix(
        math.pi / 2,
        self.shadowRange,
        0.1,
        self.shadowDistance * 2 + self.shadowRange,
        1
    )

    local combined = multiplyMatrices(self.lightProjection, self.lightView)
    for i = 1, 16 do
        self.lightViewProjection[i] = combined[i]
    end
end

-- works out which models the camera and the sun's shadow map can see
function Lighting:_updateVisibility()
    local camera = self.g3d.camera
    local v, p = camera.viewMatrix, camera.projectionMatrix
    local lv = self.lightView
    local range = self.shadowRange

    -- culling only works with a perspective projection
    local cull = self.frustumCulling and p[15] == -1 and p[16] == 0
    local near, far = camera.nearClip, camera.farClip
    local tanX, tanY = 1 / p[1], 1 / p[6]
    local cosX, cosY = 1 / math.sqrt(1 + tanX * tanX), 1 / math.sqrt(1 + tanY * tanY)

    local drawn, culled, casters = 0, 0, 0

    for i = 1, #self.models do
        local entry = self.models[i]
        local m = entry.model.matrix
        entry.visible = true
        entry.shadowVisible = true

        if entry.radius and entry.frustumCulled then
            local bx, by, bz = entry.bx, entry.by, entry.bz
            local wx = m[1] * bx + m[2] * by + m[3] * bz + m[4]
            local wy = m[5] * bx + m[6] * by + m[7] * bz + m[8]
            local wz = m[9] * bx + m[10] * by + m[11] * bz + m[12]

            local sx = math.sqrt(m[1] * m[1] + m[5] * m[5] + m[9] * m[9])
            local sy = math.sqrt(m[2] * m[2] + m[6] * m[6] + m[10] * m[10])
            local sz = math.sqrt(m[3] * m[3] + m[7] * m[7] + m[11] * m[11])
            local r = entry.radius * math.max(sx, sy, sz)

            if cull then
                -- the camera looks down -z in view space
                local vx = v[1] * wx + v[2] * wy + v[3] * wz + v[4]
                local vy = v[5] * wx + v[6] * wy + v[7] * wz + v[8]
                local depth = -(v[9] * wx + v[10] * wy + v[11] * wz + v[12])

                if depth + r < near or depth - r > far
                    or (math.abs(vx) - tanX * depth) * cosX > r
                    or (math.abs(vy) - tanY * depth) * cosY > r then
                    entry.visible = false
                end
            end

            -- the shadow box is a square of half-size shadowRange in light space;
            -- models between the sun and the box can still cast into it, so depth is not tested
            local lx = lv[1] * wx + lv[2] * wy + lv[3] * wz + lv[4]
            local ly = lv[5] * wx + lv[6] * wy + lv[7] * wz + lv[8]
            if math.abs(lx) > range + r or math.abs(ly) > range + r then
                entry.shadowVisible = false
            end
        end

        if entry.visible then drawn = drawn + 1 else culled = culled + 1 end
        if entry.castsShadow and entry.shadowVisible then casters = casters + 1 end
    end

    self.stats.modelsDrawn, self.stats.modelsCulled, self.stats.shadowCasters = drawn, culled, casters
end

local function byScore(a, b)
    return a._score > b._score
end

-- picks the lights to shade this frame and packs them into the reusable buffers
function Lighting:_collectLights()
    local list = self._visibleLights
    local n = 0
    local total = #self.lights
    self.stats.lightsTotal = total

    if self.lightsEnabled and self.lightLimit > 0 then
        local camera = self.g3d.camera
        local cx, cy, cz = camera.position[1], camera.position[2], camera.position[3]
        local lookX, lookY, lookZ = camera.getLookVector()
        local time = love.timer.getTime()
        local maxDistance = self.lightDistance

        for i = 1, total do
            local light = self.lights[i]
            local intensity = light.intensity

            if light.enabled and intensity > 0 then
                if light.flickerAmount > 0 then
                    local t = time * light.flickerSpeed + light.phase
                    local wobble = 0.6 * math.sin(t) + 0.4 * math.sin(t * 2.37 + 1.3)
                    intensity = intensity * math.max(0, 1 + light.flickerAmount * wobble)
                end

                local keep, score = true, 1e9

                if light.type ~= "directional" then
                    local p = light.position
                    local dx, dy, dz = p[1] - cx, p[2] - cy, p[3] - cz
                    local distanceSquared = dx * dx + dy * dy + dz * dz
                    local r = light.range

                    -- a light more than its range behind the camera can't reach anything in view
                    if dx * lookX + dy * lookY + dz * lookZ < -r then
                        keep = false
                    elseif maxDistance > 0 and math.sqrt(distanceSquared) - r > maxDistance then
                        keep = false
                    else
                        local c = light.color
                        local brightness = intensity * (0.3 * c[1] + 0.59 * c[2] + 0.11 * c[3] + 0.001)
                        score = brightness * r * r / (distanceSquared + 1)
                    end
                else
                    local c = light.color
                    score = 1e9 + intensity * (c[1] + c[2] + c[3])
                end

                if keep then
                    n = n + 1
                    list[n] = light
                    light._score = score
                    light._intensity = intensity
                end
            end
        end
    end

    for i = #list, n + 1, -1 do
        list[i] = nil
    end

    local limit = math.min(self.lightLimit, self.maxLights)
    if n > limit then
        table.sort(list, byScore)
        n = limit
    end

    for i = 1, n do
        local light = list[i]
        local a, b, c = self._lightA[i], self._lightB[i], self._lightC[i]
        local k = light._intensity
        local color = light.color

        a[1], a[2], a[3], a[4] = light.position[1], light.position[2], light.position[3], light.range
        b[1], b[2], b[3], b[4] = color[1] * k, color[2] * k, color[3] * k, TYPE_CODE[light.type]

        if light.type == "point" then
            c[4] = -2
            self._lightD[i] = 0
        else
            local dx, dy, dz = light.direction[1], light.direction[2], light.direction[3]
            if light.target then
                dx = light.target[1] - light.position[1]
                dy = light.target[2] - light.position[2]
                dz = light.target[3] - light.position[3]
                if dx * dx + dy * dy + dz * dz < 0.000001 then
                    dx, dy, dz = light.direction[1], light.direction[2], light.direction[3]
                end
            end
            local length = math.sqrt(dx * dx + dy * dy + dz * dz)
            if length > 0.000001 then
                c[1], c[2], c[3] = dx / length, dy / length, dz / length
            else
                c[1], c[2], c[3] = 0, 0, -1
            end

            if light.type == "spot" then
                local cosOuter = math.cos(math.rad(light.outerAngle))
                local cosInner = math.cos(math.rad(light.innerAngle))
                c[4] = cosOuter
                self._lightD[i] = 1 / math.max(cosInner - cosOuter, 0.0001)
            else
                c[4] = -2
                self._lightD[i] = 0
            end
        end
    end

    self._lightCount = n
    self.stats.lightsActive = n
end

function Lighting:_prepare()
    self._frame = self._frame + 1
    self:_updateLightMatrices()
    self:_updateVisibility()
    self:_collectLights()
end

----------------------------------------------------------------------------------------------------
-- shadow pass
----------------------------------------------------------------------------------------------------

-- the shadow map is only redrawn when the sun's view or a shadow caster changed
function Lighting:renderShadows()
    self.stats.shadowUpdated = false
    if not self.shadowsEnabled then
        return false
    end

    local valid = self._shadowValid
    if valid and self._frame - self._lastShadowFrame < self.shadowUpdateEvery then
        return false
    end

    local changed = not valid
    local lastVP, vp = self._lastLightVP, self.lightViewProjection
    for i = 1, 16 do
        if lastVP[i] ~= vp[i] then
            changed = true
            lastVP[i] = vp[i]
        end
    end

    for i = 1, #self.models do
        local entry = self.models[i]
        if entry.castsShadow then
            local m, saved = entry.model.matrix, entry._sm
            for k = 1, 12 do
                if saved[k] ~= m[k] then
                    changed = true
                    saved[k] = m[k]
                end
            end
            if entry._smMesh ~= entry.model.mesh then
                changed = true
                entry._smMesh = entry.model.mesh
            end
            if entry._smVisible ~= entry.shadowVisible then
                changed = true
                entry._smVisible = entry.shadowVisible
            end
        end
    end

    if not changed then
        return false
    end

    love.graphics.push("all")
    love.graphics.setCanvas({ self.shadowMap, depth = true })
    love.graphics.clear(1, 1, 1, 1, true, true)
    love.graphics.setDepthMode("lequal", true)
    love.graphics.setBlendMode("replace")
    love.graphics.setShader(self.shadowShader)
    self.shadowShader:send("lightViewProjection", self.lightViewProjection)

    for i = 1, #self.models do
        local entry = self.models[i]
        if entry.castsShadow and entry.shadowVisible then
            self.shadowShader:send("modelMatrix", entry.model.matrix)
            love.graphics.draw(entry.model.mesh)
        end
    end

    love.graphics.pop()

    self._shadowValid = true
    self._lastShadowFrame = self._frame
    self.stats.shadowUpdated = true
    self.stats.shadowUpdates = self.stats.shadowUpdates + 1
    return true
end

----------------------------------------------------------------------------------------------------
-- main pass
----------------------------------------------------------------------------------------------------

function Lighting:_sendSceneUniforms(shader)
    local camera = self.g3d.camera

    send(shader, "viewMatrix", camera.viewMatrix)
    send(shader, "projectionMatrix", camera.projectionMatrix)
    send(shader, "lightViewProjection", self.lightViewProjection)
    send(shader, "lightDirection", self.direction)
    send(shader, "directionalColor", self.directionalColor)
    send(shader, "directionalIntensity", self.directionalIntensity)
    send(shader, "ambientColor", self.ambientColor)
    send(shader, "ambientGround", self.ambientGround or self.ambientColor)
    send(shader, "cameraPosition", camera.position)
    send(shader, "shadowMap", self.shadowMap)
    send(shader, "shadowTexelSize", { self.shadowTexelSize, self.shadowTexelSize })
    send(shader, "shadowBias", self.shadowBias)
    send(shader, "shadowStrength", self.shadowStrength)
    send(shader, "shadowPcf", self.shadowPcf)
    send(shader, "shadowsEnabled", self.shadowsEnabled and 1 or 0)
    send(shader, "isCanvasEnabled", love.graphics.getCanvas() ~= nil and 1 or 0)
    send(shader, "toonSteps", self.toonSteps)
    send(shader, "exposure", self.exposure)

    local rim = self.rim
    send(shader, "rimColor", rim and rim.color or { 0, 0, 0 })
    send(shader, "rimSettings", rim and { rim.power, rim.strength } or { 1, 0 })

    local fog = self.fog
    send(shader, "fogColor", fog and fog.color or { 0, 0, 0 })
    send(shader, "fogRange", fog and { fog.near, fog.far } or { 0, 0 })

    -- the whole array is sent, the shader only reads the first lightCount entries
    send(shader, "lightCount", self._lightCount)
    send(shader, "lightA", unpack(self._lightA, 1, self.maxLights))
    send(shader, "lightB", unpack(self._lightB, 1, self.maxLights))
    send(shader, "lightC", unpack(self._lightC, 1, self.maxLights))
    send(shader, "lightD", unpack(self._lightD, 1, self.maxLights))
end

function Lighting:_drawEntry(entry, shader)
    send(shader, "modelMatrix", entry.model.matrix)
    send(shader, "receivesShadows", entry.receivesShadows and 1 or 0)
    send(shader, "materialSpecularStrength", entry.specularStrength)
    send(shader, "materialShininess", entry.shininess)
    send(shader, "emissiveColor", entry.emissiveColor)
    send(shader, "emissiveStrength", entry.emissiveStrength)
    love.graphics.draw(entry.model.mesh)
end

-- draws every registered model: updates the shadow map if needed, then lights and draws them
-- (use this once per frame, it is much cheaper than calling draw(model) for each model)
function Lighting:drawAll()
    self:_prepare()
    self:renderShadows()

    local shader = self.lightingShader
    love.graphics.push("all")
    love.graphics.setDepthMode("lequal", true)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setShader(shader)
    self:_sendSceneUniforms(shader)

    for i = 1, #self.models do
        local entry = self.models[i]
        if entry.visible then
            self:_drawEntry(entry, shader)
        end
    end

    love.graphics.pop()
end

-- draws a single registered model
function Lighting:draw(model)
    self:_prepare()
    self:renderShadows()

    for i = 1, #self.models do
        local entry = self.models[i]
        if entry.model == model then
            if not entry.visible then
                return true
            end
            local shader = self.lightingShader
            love.graphics.push("all")
            love.graphics.setDepthMode("lequal", true)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.setShader(shader)
            self:_sendSceneUniforms(shader)
            self:_drawEntry(entry, shader)
            love.graphics.pop()
            return true
        end
    end

    return false
end

function Lighting:release()
    if self.shadowMap then self.shadowMap:release() end
    if self.shadowShader then self.shadowShader:release() end
    if self.lightingShader then self.lightingShader:release() end
end

return Lighting
