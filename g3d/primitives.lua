-- basic procedural shapes for g3d, so demos don't need external .obj files
-- every function returns a vertex table that can be passed straight to g3d.newModel
-- vertex format: {x, y, z, u, v, nx, ny, nz}

local primitives = {}

-- unit sphere (radius 1) with smooth normals, z is up
function primitives.sphere(rings, segments)
    rings, segments = rings or 24, segments or 48
    local function vertex(i, j)
        local theta = math.pi * j / rings        -- 0 at the top pole, pi at the bottom
        local phi = 2 * math.pi * i / segments
        local x = math.sin(theta) * math.cos(phi)
        local y = math.sin(theta) * math.sin(phi)
        local z = math.cos(theta)
        return {x, y, z, i / segments, j / rings, x, y, z}
    end

    local verts = {}
    for j = 0, rings - 1 do
        for i = 0, segments - 1 do
            local a, b = vertex(i, j), vertex(i + 1, j)
            local c, d = vertex(i, j + 1), vertex(i + 1, j + 1)
            -- counter-clockwise when seen from outside
            verts[#verts + 1], verts[#verts + 2], verts[#verts + 3] = a, c, b
            verts[#verts + 1], verts[#verts + 2], verts[#verts + 3] = b, c, d
        end
    end
    return verts
end

-- flat square on the xy plane facing +z, centered at the origin
-- size is the side length, tiles is how many times the texture repeats
function primitives.plane(size, tiles)
    local h = (size or 1) / 2
    local t = tiles or 1
    return {
        {-h, -h, 0, 0, t, 0, 0, 1}, {h, -h, 0, t, t, 0, 0, 1}, {h, h, 0, t, 0, 0, 0, 1},
        {-h, -h, 0, 0, t, 0, 0, 1}, {h, h, 0, t, 0, 0, 0, 1}, {-h, h, 0, 0, 0, 0, 0, 1},
    }
end

return primitives
