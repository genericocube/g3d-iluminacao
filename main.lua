-- g3d-iluminacao demo
-- feito por generico_cube
-- Run the repository demo with: love .

local g3d = require("g3d")
local Lighting = require("g3d-iluminacao")

local lighting
local whiteTexture
local warmLight
local coolLight
local warmMarker
local coolMarker
local movingSphere
local time = 0
local lightAngle = 0
local showHelp = true

local function vertex(out, position, normal, u, v, color)
    out[#out + 1] = {
        position[1], position[2], position[3],
        u or 0, v or 0,
        normal[1], normal[2], normal[3],
        color[1], color[2], color[3], 1
    }
end

local function triangle(out, a, b, c, normalA, normalB, normalC, color)
    vertex(out, a, normalA or a, 0, 0, color)
    vertex(out, b, normalB or b, 1, 0, color)
    vertex(out, c, normalC or c, 1, 1, color)
end

local function addQuad(out, a, b, c, d, normal, color)
    triangle(out, a, b, c, normal, normal, normal, color)
    triangle(out, a, c, d, normal, normal, normal, color)
end

local function makeCube(color)
    local vertices = {}
    local faces = {
        {{{ 0.5,-0.5,-0.5},{ 0.5, 0.5,-0.5},{ 0.5, 0.5, 0.5},{ 0.5,-0.5, 0.5}}, { 1, 0, 0}},
        {{{-0.5, 0.5,-0.5},{-0.5,-0.5,-0.5},{-0.5,-0.5, 0.5},{-0.5, 0.5, 0.5}}, {-1, 0, 0}},
        {{{ 0.5, 0.5,-0.5},{-0.5, 0.5,-0.5},{-0.5, 0.5, 0.5},{ 0.5, 0.5, 0.5}}, { 0, 1, 0}},
        {{{-0.5,-0.5,-0.5},{ 0.5,-0.5,-0.5},{ 0.5,-0.5, 0.5},{-0.5,-0.5, 0.5}}, { 0,-1, 0}},
        {{{-0.5,-0.5, 0.5},{ 0.5,-0.5, 0.5},{ 0.5, 0.5, 0.5},{-0.5, 0.5, 0.5}}, { 0, 0, 1}},
        {{{-0.5, 0.5,-0.5},{ 0.5, 0.5,-0.5},{ 0.5,-0.5,-0.5},{-0.5,-0.5,-0.5}}, { 0, 0,-1}}
    }

    for i = 1, #faces do
        local face = faces[i]
        addQuad(vertices, face[1][1], face[1][2], face[1][3], face[1][4], face[2], color)
    end

    return vertices
end

local function makePlane(width, depth, color)
    local vertices = {}
    local x, y = width * 0.5, depth * 0.5
    addQuad(vertices,
        {-x,-y,0}, {x,-y,0}, {x,y,0}, {-x,y,0},
        {0,0,1}, color
    )
    return vertices
end

local function spherePoint(latitude, longitude)
    local radius = math.cos(latitude)
    return {
        radius * math.cos(longitude),
        radius * math.sin(longitude),
        math.sin(latitude)
    }
end

local function makeSphere(color, slices, stacks)
    local vertices = {}
    slices = slices or 18
    stacks = stacks or 12

    for y = 0, stacks - 1 do
        local lat0 = -math.pi * 0.5 + math.pi * y / stacks
        local lat1 = -math.pi * 0.5 + math.pi * (y + 1) / stacks

        for x = 0, slices - 1 do
            local lon0 = math.pi * 2 * x / slices
            local lon1 = math.pi * 2 * (x + 1) / slices

            local a = spherePoint(lat0, lon0)
            local b = spherePoint(lat0, lon1)
            local c = spherePoint(lat1, lon1)
            local d = spherePoint(lat1, lon0)

            addQuad(vertices, a, b, c, d, nil, color)
        end
    end

    return vertices
end

local function createModel(vertices, x, y, z, sx, sy, sz)
    local model = g3d.newModel(
        vertices,
        whiteTexture,
        {x or 0, y or 0, z or 0},
        {0, 0, 0},
        {sx or 1, sy or sx or 1, sz or sx or 1}
    )
    return model
end

local function register(model, options)
    lighting:addModel(model, options)
    return model
end

local function makeTextPanel()
    love.graphics.push("all")
    love.graphics.setDepthMode()
    love.graphics.setColor(0.025, 0.035, 0.055, 0.86)
    love.graphics.rectangle("fill", 16, 16, 430, showHelp and 186 or 64, 8, 8)

    love.graphics.setColor(0.92, 0.96, 1, 1)
    love.graphics.print("g3d-iluminacao  |  real-time lighting demo", 30, 28)

    local status = ("Shadows: %s   |   Point lights: %s   |   Map: %d")
        :format(
            lighting.shadowsEnabled and "ON" or "OFF",
            lighting.pointLightsEnabled and "ON" or "OFF",
            lighting.shadowResolution
        )
    love.graphics.print(status, 30, 54)

    if showHelp then
        love.graphics.setColor(0.72, 0.82, 0.94, 1)
        love.graphics.print("WASD: move camera     Mouse: look around", 30, 84)
        love.graphics.print("Space / Shift: move up / down", 30, 106)
        love.graphics.print("F: toggle shadows     G: toggle point lights", 30, 128)
        love.graphics.print("1 / 2 / 3: shadow map 512 / 1024 / 2048", 30, 150)
        love.graphics.print("Arrows: rotate sun    H: hide this panel", 30, 172)
        love.graphics.print(("FPS: %d"):format(love.timer.getFPS()), 30, 196)
    else
        love.graphics.setColor(0.72, 0.82, 0.94, 1)
        love.graphics.print("Press H to show controls", 30, 80)
    end

    love.graphics.pop()
end

function love.load()
    love.window.setTitle("g3d-iluminacao | Real-time lighting")
    love.graphics.setBackgroundColor(0.035, 0.045, 0.065, 1)

    local imageData = love.image.newImageData(1, 1)
    imageData:setPixel(0, 0, 1, 1, 1, 1)
    whiteTexture = love.graphics.newImage(imageData)
    whiteTexture:setFilter("nearest", "nearest")

    lighting = Lighting.new({
        shadowResolution = 1024,
        shadowRange = 19,
        shadowDistance = 40,
        shadowBias = 0.0018,
        shadowStrength = 0.92,
        ambientColor = {0.16, 0.18, 0.23},
        directionalColor = {1.0, 0.92, 0.78},
        directionalIntensity = 0.9
    })
    lighting:setDirection(0.42, 0.34, -0.84)

    -- A large receiver plane, plus several solid objects that cast shadows.
    register(createModel(makePlane(28, 28, {0.48, 0.52, 0.60}), 0, 0, -0.08),
        {castsShadow = false, specularStrength = 0.04})

    register(createModel(makeCube({0.78, 0.24, 0.12}), -3.8, 0.0, 0.85, 1.7, 1.7, 1.7),
        {specularStrength = 0.24, shininess = 40})
    register(createModel(makeCube({0.16, 0.42, 0.72}), 0.0, 1.8, 0.65, 1.3, 1.3, 1.3),
        {specularStrength = 0.38, shininess = 64})
    register(createModel(makeCube({0.72, 0.62, 0.20}), 3.8, 0.4, 1.15, 1.4, 1.4, 2.3),
        {specularStrength = 0.2})

    register(createModel(makeSphere({0.25, 0.72, 0.42}), -1.4, -3.0, 0.85, 1.7),
        {specularStrength = 0.52, shininess = 80})
    movingSphere = register(createModel(makeSphere({0.72, 0.30, 0.68}), 2.0, -3.0, 1.0, 1.35),
        {specularStrength = 0.46, shininess = 72})

    -- Colored point lights illuminate nearby surfaces. Their marker spheres are emissive.
    warmLight = lighting:addPointLight({
        position = {-3.2, -1.0, 2.6},
        color = {1.0, 0.34, 0.12},
        intensity = 3.5,
        range = 8
    })
    coolLight = lighting:addPointLight({
        position = {3.0, 2.5, 2.8},
        color = {0.12, 0.42, 1.0},
        intensity = 3.2,
        range = 8
    })

    warmMarker = register(createModel(makeSphere({1.0, 0.42, 0.16}, 14, 9),
        warmLight.position[1], warmLight.position[2], warmLight.position[3], 0.28),
        {castsShadow = false, receivesShadows = false, emissiveColor = {1.0, 0.28, 0.08}, emissiveStrength = 2.8})
    coolMarker = register(createModel(makeSphere({0.18, 0.48, 1.0}, 14, 9),
        coolLight.position[1], coolLight.position[2], coolLight.position[3], 0.28),
        {castsShadow = false, receivesShadows = false, emissiveColor = {0.10, 0.32, 1.0}, emissiveStrength = 2.8})

    g3d.camera.lookAt(10, -14, 9, 0, 0, 0.6)
end

function love.update(dt)
    time = time + dt
    g3d.camera.firstPersonMovement(dt)

    -- Animate the two point lights to show that their illumination updates every frame.
    local warmX = -3.2 + math.cos(time * 0.85) * 1.6
    local warmY = -1.0 + math.sin(time * 0.85) * 1.2
    local warmZ = 2.2 + math.sin(time * 1.3) * 0.55
    warmLight.position[1], warmLight.position[2], warmLight.position[3] = warmX, warmY, warmZ
    warmMarker:setTranslation(warmX, warmY, warmZ)

    local coolX = 3.0 + math.cos(time * 0.7 + 1.4) * 1.4
    local coolY = 2.5 + math.sin(time * 0.7 + 1.4) * 1.6
    local coolZ = 2.6 + math.cos(time * 1.1) * 0.45
    coolLight.position[1], coolLight.position[2], coolLight.position[3] = coolX, coolY, coolZ
    coolMarker:setTranslation(coolX, coolY, coolZ)

    movingSphere:setTranslation(2.0, -3.0, 1.0 + math.sin(time * 1.2) * 0.55)
    movingSphere:setRotation(0, time * 0.35, time * 0.6)

    if love.keyboard.isDown("left") then lightAngle = lightAngle - dt * 0.7 end
    if love.keyboard.isDown("right") then lightAngle = lightAngle + dt * 0.7 end
    if lightAngle ~= 0 then
        lighting:setDirection(math.cos(lightAngle) * 0.42, math.sin(lightAngle) * 0.42 + 0.34, -0.84)
    end
end

function love.draw()
    love.graphics.clear(0.035, 0.045, 0.065, 1)
    lighting:drawAll()
    makeTextPanel()
end

function love.mousepressed()
    love.mouse.setRelativeMode(true)
end

function love.mousemoved(_, _, dx, dy)
    if love.mouse.getRelativeMode() then
        g3d.camera.firstPersonLook(dx, dy)
    end
end

function love.keypressed(key)
    if key == "escape" then
        love.mouse.setRelativeMode(false)
    elseif key == "f" then
        lighting:setShadowsEnabled(not lighting.shadowsEnabled)
    elseif key == "g" then
        lighting:setPointLightsEnabled(not lighting.pointLightsEnabled)
    elseif key == "1" then
        lighting:setShadowResolution(512)
    elseif key == "2" then
        lighting:setShadowResolution(1024)
    elseif key == "3" then
        lighting:setShadowResolution(2048)
    elseif key == "h" then
        showHelp = not showHelp
    elseif key == "r" then
        g3d.camera.lookAt(10, -14, 9, 0, 0, 0.6)
    end
end

function love.quit()
    if lighting then lighting:release() end
    if whiteTexture then whiteTexture:release() end
end
