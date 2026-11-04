# g3d-iluminação

[g3d](https://github.com/groverburger/g3d) (LÖVE/Lua) com iluminação por pixel (Blinn-Phong).

## Uso

```lua
local g3d = require "g3d"
local lighting = g3d.lighting

lighting.setAmbient(0.12, 0.12, 0.18)                    -- luz ambiente
lighting.setSun(1, 0.5, -0.4,  1, 0.95, 0.85,  0.9)      -- direção, cor, intensidade
local lamp = lighting.newLight(x, y, z,  r, g, b,  raio, intensidade) -- até 8 luzes de ponto

lamp:setPosition(x, y, z)   -- também: setColor, setRadius, setIntensity, setEnabled
lighting.removeLight(lamp)

model:setMaterial(shininess, specularStrength)  -- brilho do modelo
model:setLit(false)                             -- ignora luzes (céu, etc.)
```

Modelos são iluminados por padrão (`model:draw()` usa `g3d.lightShader`). A normal do modelo
acompanha rotação e escala, e faces de `.obj` sem normais ganham normal plana automaticamente.

`g3d.primitives.sphere()` e `g3d.primitives.plane()` geram malhas sem precisar de arquivos.
O demo (`main.lua`) usa `assets/` se existir; senão gera malhas e texturas no código.

Teclas do demo: `WASD`/`espaço`/`shift` movem, mouse olha, `1` liga/desliga o sol, `2` a luz laranja.
