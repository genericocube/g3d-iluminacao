-- written by groverbuger for g3d
-- MIT license
-- lighting demo: the earth spins under a sun and an orbiting orange light
-- if the files in assets/ are missing, the meshes and textures are generated in code

local g3d = require "g3d"
local lighting = g3d.lighting

----------------------------------------------------------------------------------------------------
-- assets (loaded from disk when present, generated otherwise)
----------------------------------------------------------------------------------------------------

local function loadTexture(path, generate)
    if love.filesystem.getInfo(path) then return love.graphics.newImage(path) end
    return love.graphics.newImage(generate())
end

-- fills an image by calling fn(u, v) -> r, g, b for every pixel
local function paint(size, fn)
    local data = love.image.newImageData(size * 2, size)
    data:mapPixel(function(x, y)
        local r, g, b = fn(x / (size * 2), y / size)
        return r, g, b, 1
    end)
    return data
end

-- smooth fake noise built from sines, x frequencies are whole numbers so the texture tiles around
local function noise(u, v)
    local x, y = u * 2 * math.pi, v * math.pi
    return (math.sin(x * 6) * math.sin(y * 5) + math.sin(x * 13 + y * 7) * 0.5 + math.sin(x * 29 - y * 23) * 0.25) / 1.75
end

local function generateEarth()
    return paint(256, function(u, v)
        local n = noise(u, v)
        if math.abs(v - 0.5) > 0.44 then return 0.9, 0.95, 1 end -- ice caps
        if n > 0.15 then return 0.2 + n * 0.2, 0.5 + n * 0.2, 0.15 end -- land
        return 0.05, 0.2 + n * 0.1, 0.55 + n * 0.2 -- sea
    end)
end

local function generateMoon()
    return paint(128, function(u, v)
        local c = 0.55 + noise(u * 2 % 1, v) * 0.15
        return c, c, c
    end)
end

local function generateStars()
    love.math.setRandomSeed(1)
    local data = love.image.newImageData(1024, 512)
    for _ = 1, 700 do
        local c = 0.4 + love.math.random() * 0.6
        data:setPixel(love.math.random(0, 1023), love.math.random(0, 511), c, c, c, 1)
    end
    return data
end

local sphere = love.filesystem.getInfo("assets/sphere.obj") and "assets/sphere.obj" or g3d.primitives.sphere()

local earth = g3d.newModel(sphere, loadTexture("assets/earth.png", generateEarth), {4,0,0})
local moon = g3d.newModel(sphere, loadTexture("assets/moon.png", generateMoon), {4,5,0}, nil, 0.5)
local background = g3d.newModel(sphere, loadTexture("assets/starfield.png", generateStars), nil, nil, 500)

-- the sky shouldn't react to lights
background:setLit(false)
-- the moon is rough, the ocean on earth is a little shiny
moon:setMaterial(8, 0.05)
earth:setMaterial(48, 0.4)

----------------------------------------------------------------------------------------------------
-- lights
----------------------------------------------------------------------------------------------------

lighting.setAmbient(0.12, 0.12, 0.18)
lighting.setSun(1, 0.5, -0.4, 1, 0.95, 0.85, 0.9)
local orbitLight = lighting.newLight(4, 6, 2, 1, 0.45, 0.15, 14, 1.4)

g3d.camera.lookAt(-8, 0, 3, 4, 0, 0)

local timer = 0

function love.update(dt)
    timer = timer + dt
    moon:setTranslation(math.cos(timer)*5 + 4, math.sin(timer)*5, 0)
    moon:setRotation(0, 0, timer - math.pi/2)
    earth:setRotation(0, 0, timer * 0.4)
    orbitLight:setPosition(math.cos(timer * 0.7 + math.pi) * 7 + 4, math.sin(timer * 0.7 + math.pi) * 7, 2)
    g3d.camera.firstPersonMovement(dt)
    if love.keyboard.isDown "escape" then
        love.event.push "quit"
    end
end

function love.draw()
    earth:draw()
    moon:draw()
    background:draw()

    -- 2D text must not be depth tested against the 3D scene
    love.graphics.setDepthMode()
    love.graphics.print("WASD/space/shift: move   mouse: look   1: sun   2: orange light   esc: quit", 8, 8)
    love.graphics.setDepthMode("lequal", true)
end

function love.keypressed(key)
    if key == "1" then
        lighting.setSunEnabled(not lighting.sun.enabled)
    elseif key == "2" then
        orbitLight:setEnabled(not orbitLight.enabled)
    end
end

function love.mousemoved(x,y, dx,dy)
    g3d.camera.firstPersonLook(dx,dy)
end

function love.resize(width, height)
    g3d.camera.resize(width, height)
end
