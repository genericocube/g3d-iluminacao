-- g3d-iluminacao
-- feito por generico_cube
-- Real-time lighting and directional shadow mapping for g3d 1.6.0.
-- MIT License. See the repository LICENSE file.

local g3d = require("g3d")
local newMatrix = require(g3d.path .. ".matrices")

local Lighting = {}
Lighting.__index = Lighting

local MAX_POINT_LIGHTS = 4
local SHADER_DIR = "g3d-iluminacao/shaders/"

local function readShader(path)
    local source, err = love.filesystem.read(path)
    assert(source, ("[g3d-iluminacao] Could not read %s: %s"):format(path, tostring(err)))
    return source
end

local function vec3(value, fallback)
    value = value or fallback
    return {value[1] or 0, value[2] or 0, value[3] or 0}
end

local function normalize(x, y, z)
    local length = math.sqrt(x*x + y*y + z*z)
    assert(length > 0.000001, "[g3d-iluminacao] Direction vector cannot be zero.")
    return x/length, y/length, z/length
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

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

function Lighting.new(options)
    options = options or {}

    assert(love and love.graphics and love.graphics.newShader,
        "[g3d-iluminacao] LÖVE graphics must be initialized before creating Lighting.")

    local self = setmetatable({}, Lighting)
    self.g3d = g3d
    self.models = {}
    self.pointLights = {}

    self.direction = {0.4, 0.35, -0.8}
    self.directionalColor = vec3(options.directionalColor, {1.0, 0.94, 0.82})
    self.directionalIntensity = options.directionalIntensity or 0.9
    self.ambientColor = vec3(options.ambientColor, {0.19, 0.21, 0.26})

    self.shadowsEnabled = options.shadowsEnabled ~= false
    self.pointLightsEnabled = options.pointLightsEnabled ~= false
    self.shadowRange = options.shadowRange or 22
    self.shadowDistance = options.shadowDistance or 42
    self.shadowBias = options.shadowBias or 0.0018
    self.shadowStrength = options.shadowStrength or 0.9

    self.lightView = newMatrix()
    self.lightProjection = newMatrix()
    self.lightViewProjection = {}

    self.lightingShader = love.graphics.newShader(readShader(SHADER_DIR .. "lighting.glsl"))
    self.shadowShader = love.graphics.newShader(readShader(SHADER_DIR .. "shadow.glsl"))

    self:setDirection(unpack(self.direction))
    self:setShadowResolution(options.shadowResolution or 1024)

    return self
end

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
    self.shadowsEnabled = not not enabled
    return self
end

function Lighting:setPointLightsEnabled(enabled)
    self.pointLightsEnabled = not not enabled
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
    return self
end

function Lighting:addModel(model, options)
    assert(model and model.mesh and model.matrix,
        "[g3d-iluminacao] addModel expects a model created by g3d.newModel().")

    options = options or {}
    if type(options) == "boolean" then
        options = {castsShadow = options}
    end

    local entry = {
        model = model,
        castsShadow = options.castsShadow ~= false,
        receivesShadows = options.receivesShadows ~= false,
        specularStrength = options.specularStrength == nil and 0.18 or options.specularStrength,
        shininess = options.shininess or 32,
        emissiveColor = vec3(options.emissiveColor, {0, 0, 0}),
        emissiveStrength = options.emissiveStrength or 0
    }

    self.models[#self.models + 1] = entry
    return model, entry
end

function Lighting:removeModel(model)
    for i = #self.models, 1, -1 do
        if self.models[i].model == model then
            table.remove(self.models, i)
            return true
        end
    end
    return false
end

function Lighting:clearModels()
    for i = #self.models, 1, -1 do
        self.models[i] = nil
    end
end

function Lighting:addPointLight(options)
    assert(#self.pointLights < MAX_POINT_LIGHTS,
        ("[g3d-iluminacao] This version supports up to %d point lights."):format(MAX_POINT_LIGHTS))

    options = options or {}
    local light = {
        position = vec3(options.position, {0, 0, 0}),
        color = vec3(options.color, {1, 1, 1}),
        intensity = options.intensity or 1,
        range = options.range or 8
    }

    assert(light.range > 0, "[g3d-iluminacao] Point-light range must be greater than zero.")
    self.pointLights[#self.pointLights + 1] = light
    return light
end

function Lighting:removePointLight(light)
    for i = #self.pointLights, 1, -1 do
        if self.pointLights[i] == light then
            table.remove(self.pointLights, i)
            return true
        end
    end
    return false
end

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
    local target = {centerX, centerY, centerZ}
    local up = {0, 0, 1}

    if math.abs(dz) > 0.96 then
        up = {0, 1, 0}
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

function Lighting:renderShadows()
    -- Keep the light matrix valid even when shadows are temporarily disabled.
    self:_updateLightMatrices()

    if not self.shadowsEnabled then
        return false
    end

    love.graphics.push("all")
    love.graphics.setCanvas({self.shadowMap, depth = true})
    love.graphics.clear(1, 1, 1, 1, 1, 0)
    love.graphics.setDepthMode("lequal", true)
    love.graphics.setBlendMode("replace")
    love.graphics.setShader(self.shadowShader)

    for i = 1, #self.models do
        local entry = self.models[i]
        if entry.castsShadow then
            self.shadowShader:send("modelMatrix", entry.model.matrix)
            self.shadowShader:send("lightViewProjection", self.lightViewProjection)
            love.graphics.draw(entry.model.mesh)
        end
    end

    love.graphics.pop()
    return true
end

function Lighting:_sendSceneUniforms(shader)
    local camera = self.g3d.camera

    shader:send("viewMatrix", camera.viewMatrix)
    shader:send("projectionMatrix", camera.projectionMatrix)
    shader:send("lightViewProjection", self.lightViewProjection)
    shader:send("lightDirection", self.direction)
    shader:send("directionalColor", self.directionalColor)
    shader:send("directionalIntensity", self.directionalIntensity)
    shader:send("ambientColor", self.ambientColor)
    shader:send("cameraPosition", camera.position)
    shader:send("shadowMap", self.shadowMap)
    shader:send("shadowTexelSize", {self.shadowTexelSize, self.shadowTexelSize})
    shader:send("shadowBias", self.shadowBias)
    shader:send("shadowStrength", self.shadowStrength)
    shader:send("shadowsEnabled", self.shadowsEnabled)
    shader:send("isCanvasEnabled", love.graphics.getCanvas() ~= nil)

    local positions, colors, intensities, ranges = {}, {}, {}, {}
    for i = 1, MAX_POINT_LIGHTS do
        local light = self.pointLights[i]
        if light then
            positions[i] = light.position
            colors[i] = light.color
            intensities[i] = self.pointLightsEnabled and light.intensity or 0
            ranges[i] = light.range
        else
            positions[i] = {0, 0, 0}
            colors[i] = {0, 0, 0}
            intensities[i] = 0
            ranges[i] = 1
        end
    end

    shader:send("pointPosition", unpack(positions))
    shader:send("pointColor", unpack(colors))
    shader:send("pointIntensity", unpack(intensities))
    shader:send("pointRange", unpack(ranges))
end

function Lighting:_drawEntry(entry, shader)
    shader:send("modelMatrix", entry.model.matrix)
    shader:send("receivesShadows", entry.receivesShadows)
    shader:send("materialSpecularStrength", entry.specularStrength)
    shader:send("materialShininess", entry.shininess)
    shader:send("emissiveColor", entry.emissiveColor)
    shader:send("emissiveStrength", entry.emissiveStrength)
    love.graphics.draw(entry.model.mesh)
end

function Lighting:drawAll()
    self:renderShadows()

    local shader = self.lightingShader
    love.graphics.push("all")
    love.graphics.setDepthMode("lequal", true)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setShader(shader)
    self:_sendSceneUniforms(shader)

    for i = 1, #self.models do
        self:_drawEntry(self.models[i], shader)
    end

    love.graphics.pop()
end

function Lighting:draw(model)
    self:renderShadows()

    for i = 1, #self.models do
        local entry = self.models[i]
        if entry.model == model then
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
