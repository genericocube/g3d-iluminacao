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