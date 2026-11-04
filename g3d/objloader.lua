-- written by groverbuger for g3d
-- MIT license

----------------------------------------------------------------------------------------------------
-- simple obj loader
----------------------------------------------------------------------------------------------------

-- turns an obj index into an absolute one, obj allows negative (relative to the end) indices
local function resolveIndex(index, count)
    if index < 0 then return count + index + 1 end
    return index
end

-- give path of file
-- returns a lua table representation
return function (path, uFlip, vFlip)
    local positions, uvs, normals = {}, {}, {}
    local result = {}

    -- go line by line through the file
    for line in love.filesystem.lines(path) do
        local words = {}

        -- split the line into words
        for word in line:gmatch "([^%s]+)" do
            table.insert(words, word)
        end

        local firstWord = words[1]

        if firstWord == "v" then
            -- if the first word in this line is a "v", then this defines a vertex's position

            table.insert(positions, {tonumber(words[2]), tonumber(words[3]), tonumber(words[4])})
        elseif firstWord == "vt" then
            -- if the first word in this line is a "vt", then this defines a texture coordinate

            local u, v = tonumber(words[2]), tonumber(words[3])

            -- optionally flip these texture coordinates
            if uFlip then u = 1 - u end
            if vFlip then v = 1 - v end

            table.insert(uvs, {u, v})
        elseif firstWord == "vn" then
            -- if the first word in this line is a "vn", then this defines a vertex normal
            table.insert(normals, {tonumber(words[2]), tonumber(words[3]), tonumber(words[4])})
        elseif firstWord == "f" and #words >= 4 then

            -- if the first word in this line is a "f", then this is a face
            -- a face takes three or more point definitions
            -- the arguments a point definition takes are vertex, vertex texture, vertex normal in that order

            local vertices = {}
            local missingNormal = false
            for i = 2, #words do
                local v, vt, vn = words[i]:match "^(%-?%d+)/?(%-?%d*)/?(%-?%d*)$"
                v, vt, vn = tonumber(v), tonumber(vt), tonumber(vn)
                if not v or v == 0 or vt == 0 or vn == 0 then
                    error("g3d objloader invalid face token: " .. words[i])
                end
                v = resolveIndex(v, #positions)
                vt = vt and resolveIndex(vt, #uvs)
                vn = vn and resolveIndex(vn, #normals)
                if not positions[v] or (vt and not uvs[vt]) or (vn and not normals[vn]) then
                    error("g3d objloader face token points to a missing element: " .. words[i])
                end
                if not vn then missingNormal = true end
                table.insert(vertices, {
                    positions[v][1],
                    positions[v][2],
                    positions[v][3],
                    vt and uvs[vt][1] or 0,
                    vt and uvs[vt][2] or 0,
                    vn and normals[vn][1] or 0,
                    vn and normals[vn][2] or 0,
                    vn and normals[vn][3] or 0,
                })
            end

            -- faces without normals get a flat normal, otherwise lighting would make them black
            if missingNormal then
                local a, b, c = vertices[1], vertices[2], vertices[3]
                local ux, uy, uz = b[1]-a[1], b[2]-a[2], b[3]-a[3]
                local wx, wy, wz = c[1]-a[1], c[2]-a[2], c[3]-a[3]
                local nx, ny, nz = uy*wz - uz*wy, uz*wx - ux*wz, ux*wy - uy*wx
                local len = math.sqrt(nx*nx + ny*ny + nz*nz)
                if len > 0 then nx, ny, nz = nx/len, ny/len, nz/len end
                for _, vert in ipairs(vertices) do
                    if vert[6] == 0 and vert[7] == 0 and vert[8] == 0 then
                        vert[6], vert[7], vert[8] = nx, ny, nz
                    end
                end
            end

            -- triangulate the face if it's not already a triangle
            if #vertices > 3 then
                -- choose a central vertex
                local centralVertex = vertices[1]

                -- connect the central vertex to each of the other vertices to create triangles
                -- every triangle gets its own copy of the central vertex, so that editing one
                -- triangle (like model:makeNormals does) can't change the others
                for i = 2, #vertices - 1 do
                    table.insert(result, {unpack(centralVertex)})
                    table.insert(result, vertices[i])
                    table.insert(result, vertices[i + 1])
                end
            else
                for i = 1, #vertices do
                    table.insert(result, vertices[i])
                end
            end

        end
    end

    return result
end
