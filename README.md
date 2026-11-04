# g3d-iluminacao

> Parte do [g3d-cube-tools](https://github.com/genericocube/g3d-cube-tools) (luz + [som3d](https://github.com/genericocube/g3d-som3d) + [g3d-glb](https://github.com/genericocube/g3d-glb) num lugar só).

## Instalação / Installation

Rode `love .` na pasta do repositório para ver a demo. Para usar no seu projeto, mantenha a pasta `g3d/` e copie a pasta `g3d-iluminacao/`:

```text
meu-jogo/
├── conf.lua        (use t.window.depth = 24)
├── main.lua
├── g3d/
└── g3d-iluminacao/
    ├── init.lua
    └── shaders/
```

Run `love .` in this folder to see the demo. To use it in your project, keep the `g3d/` folder and copy the `g3d-iluminacao/` folder as shown above. LÖVE 11.4+ recommended.

---

**🇧🇷 Português** · **🇺🇸 English** (below)

Iluminação em tempo real para o [g3d](https://github.com/groverburger/g3d) 1.6.0 + LÖVE 11.x. Não altera nenhum arquivo do g3d.

## Recursos

- **Sol** (luz direcional) com **sombras suaves** (shadow map, filtro 1 / 3×3 / 5×5, borda que some suavemente).
- **Luzes de ponto**, **spots** (lanterna, holofote) e **luzes direcionais de preenchimento** (lua, céu), todas coloridas.
- **Até 32 luzes por frame** (padrão 16). Você pode criar quantas quiser: só as mais importantes (mais perto e mais fortes) são usadas.
- **Ambiente de hemisfério** (cor do céu em cima, cor do chão embaixo), **rim light**, **toon / cel shading**, **neblina**, **exposição**.
- **Tremida de tocha** (`flicker`) em qualquer luz.
- Material por modelo: brilho, intensidade do brilho, cor emissiva.
- **Presets de qualidade**: `low`, `medium`, `high`, `ultra`.
- **Otimizações**: o shadow map só é redesenhado quando algo muda, modelos fora da câmera não são desenhados, modelos fora do alcance da sombra não entram no shadow map, luzes atrás da câmera ou longe demais são ignoradas, nenhum lixo de memória por frame, e dá para ver tudo em `lighting:getStats()`.

## Uso rápido

```lua
local g3d = require "g3d"
local Lighting = require "g3d-iluminacao"

local lighting, sol

function love.load()
    lighting = Lighting.new({ quality = "high" })
    lighting:setDirection(0.4, 0.3, -0.8)          -- direção do sol
    lighting:setHemisphere({0.2, 0.24, 0.32}, {0.12, 0.1, 0.08})

    local cubo = g3d.newModel("cubo.obj", "cubo.png", {0, 0, 1})
    lighting:addModel(cubo, { shininess = 48, specularStrength = 0.3 })

    lighting:addPointLight({ position = {2, 0, 2}, color = {1, 0.4, 0.1}, intensity = 3, range = 8 })
end

function love.draw()
    lighting:drawAll()     -- uma vez por frame: sombras + luzes + desenho
end
```

`drawAll()` é o jeito rápido. `lighting:draw(modelo)` desenha um modelo só, mas refaz a preparação a cada chamada.

## Tipos de luz

```lua
-- ponto: brilha para todos os lados
local lamp = lighting:addPointLight({ position = {x,y,z}, color = {r,g,b}, intensity = 3, range = 8 })

-- spot: cone de luz (ângulos em GRAUS)
local lanterna = lighting:addSpotLight({
    position = {x,y,z}, direction = {dx,dy,dz},   -- ou target = {x,y,z}
    color = {1,1,1}, intensity = 3, range = 25,
    innerAngle = 12, outerAngle = 26,             -- cheio até 12°, some até 26°
})

-- direcional de preenchimento: sem posição, sem queda, sem sombra (barata)
local lua = lighting:addDirectionalLight({ direction = {-0.5,-0.3,-0.4}, color = {0.35,0.45,0.9}, intensity = 0.2 })
```

Todas aceitam `flicker = {amount = 0.4, speed = 9}` (tocha) e `enabled = false`. Métodos (todos retornam a própria luz):
`setPosition`, `setColor`, `setIntensity`, `setRange`, `setDirection`, `setTarget`, `setAngles(inner, outer)`, `setEnabled`, `setFlicker(amount, speed)` e `remove()`.
Os campos `position`, `color`, `intensity` etc. também podem ser mudados direto (ex.: `lamp.position[1] = 5`).

O sol é configurado no próprio `lighting`: `setDirection`, `setDirectionalColor`, `setDirectionalIntensity`.

## Opções do visual

| Comando | O que faz |
|---|---|
| `setAmbient(valor ou {r,g,b})` | Luz ambiente simples |
| `setHemisphere(céu, chão)` | Ambiente com cor diferente em cima e embaixo (`nil` desliga) |
| `setRim(cor, potência, força)` | Brilho nas bordas dos objetos (`nil` desliga) |
| `setToon(passos)` | Sombreamento estilo desenho, ex. 3 faixas (`0` ou `false` desliga) |
| `setFog(cor, perto, longe)` | Neblina linear (`nil` desliga) |
| `setExposure(valor)` | Brilho geral |
| `addModel(modelo, opções)` | `castsShadow`, `receivesShadows`, `specularStrength`, `shininess`, `emissiveColor`, `emissiveStrength`, `frustumCulled` |

## Desempenho e qualidade

`Lighting.new({ quality = "low" | "medium" | "high" | "ultra" })` ou `lighting:setQuality(nome)`:

| Preset | Shadow map | Suavidade da sombra | Luzes ao mesmo tempo |
|---|---|---|---|
| `low` | 512 | dura (1 amostra) | 4 |
| `medium` (padrão) | 1024 | 3×3 | 8 |
| `high` | 2048 | 3×3 | 16 |
| `ultra` | 4096 | 5×5 | 32* |

\* limitado por `maxLights` (padrão 16; use `Lighting.new({ maxLights = 32 })` para liberar).

Ajustes finos (sobrescrevem o preset): `setShadowResolution(512|1024|2048|4096)`, `setShadowPcf(0|1|2)`, `setLightLimit(n)`,
`setShadowUpdateEvery(n)` (redesenha a sombra a cada n frames), `setLightDistance(d)` (ignora luzes a mais de d da câmera),
`setFrustumCulling(bool)`, `setShadowsEnabled(bool)`, `setLightsEnabled(bool)` (liga/desliga todas as luzes locais; o sol não muda),
`setShadowRange`, `setShadowDistance`, `setShadowBias`, `setShadowStrength`.

Dicas: use `drawAll()`; mantenha o `shadowRange` o menor possível para a cena (sombra mais nítida); modelos que não precisam projetar sombra com `castsShadow = false` (chão, céu) deixam o shadow map mais barato; `getStats()` retorna `modelsDrawn`, `modelsCulled`, `shadowCasters`, `shadowUpdates`, `lightsActive` e `lightsTotal`.

Se você mudar os vértices de um modelo depois de adicioná-lo, chame `lighting:updateBounds(modelo)`. A projeção ortográfica desliga o culling de câmera automaticamente.

## Demo

Teclas: `WASD`/`Espaço`/`Shift` movem, mouse olha (clique para capturar), `F` sombras, `G` luzes locais, `L` lanterna (spot), `T` toon, `B` rim light, `V` neblina, `Q` troca a qualidade, setas giram o sol, `H` mostra/esconde o painel, `R` reseta a câmera.

---

# English

Real-time lighting for [g3d](https://github.com/groverburger/g3d) 1.6.0 + LÖVE 11.x. It does not modify any g3d file.

## Features

- **Sun** (directional light) with **soft shadows** (shadow map, 1 / 3×3 / 5×5 filter, edge fade).
- Colored **point lights**, **spot lights** (flashlight, searchlight) and **directional fill lights** (moon, sky).
- **Up to 32 lights per frame** (default 16). Create as many as you like: only the most important ones (closest and brightest) are used.
- **Hemisphere ambient**, **rim light**, **toon shading**, **fog**, **exposure**.
- **Torch flicker** on any light.
- Per-model material: shininess, specular strength, emissive color.
- **Quality presets**: `low`, `medium`, `high`, `ultra`.
- **Optimizations**: the shadow map is only redrawn when something changes, off-screen models are not drawn, models outside the shadow volume skip the shadow pass, lights behind the camera or too far away are ignored, no per-frame garbage, and `lighting:getStats()` shows what is happening.

## Quick start

```lua
local g3d = require "g3d"
local Lighting = require "g3d-iluminacao"

local lighting

function love.load()
    lighting = Lighting.new({ quality = "high" })
    lighting:setDirection(0.4, 0.3, -0.8)                      -- sun direction
    lighting:setHemisphere({0.2, 0.24, 0.32}, {0.12, 0.1, 0.08})

    local cube = g3d.newModel("cube.obj", "cube.png", {0, 0, 1})
    lighting:addModel(cube, { shininess = 48, specularStrength = 0.3 })

    lighting:addPointLight({ position = {2, 0, 2}, color = {1, 0.4, 0.1}, intensity = 3, range = 8 })
end

function love.draw()
    lighting:drawAll()   -- once per frame: shadows + lights + drawing
end
```

`drawAll()` is the fast path. `lighting:draw(model)` draws a single model but repeats the per-frame setup on every call.

## Light types

```lua
local lamp = lighting:addPointLight({ position = {x,y,z}, color = {r,g,b}, intensity = 3, range = 8 })

local flashlight = lighting:addSpotLight({
    position = {x,y,z}, direction = {dx,dy,dz},   -- or target = {x,y,z}
    color = {1,1,1}, intensity = 3, range = 25,
    innerAngle = 12, outerAngle = 26,             -- DEGREES: full brightness to 12°, fades out at 26°
})

-- no position, no falloff, no shadows (cheap)
local moon = lighting:addDirectionalLight({ direction = {-0.5,-0.3,-0.4}, color = {0.35,0.45,0.9}, intensity = 0.2 })
```

All of them take `flicker = {amount = 0.4, speed = 9}` and `enabled = false`. Chainable methods:
`setPosition`, `setColor`, `setIntensity`, `setRange`, `setDirection`, `setTarget`, `setAngles(inner, outer)`, `setEnabled`, `setFlicker(amount, speed)` and `remove()`.
The fields (`position`, `color`, `intensity`...) can also be changed directly, e.g. `lamp.position[1] = 5`.

The sun lives on `lighting` itself: `setDirection`, `setDirectionalColor`, `setDirectionalIntensity`.

## Look options

`setAmbient(v | {r,g,b})`, `setHemisphere(sky, ground)`, `setRim(color, power, strength)`, `setToon(steps)`, `setFog(color, near, far)`, `setExposure(v)` (pass `nil` / `0` to turn each effect off), and `addModel(model, options)` with `castsShadow`, `receivesShadows`, `specularStrength`, `shininess`, `emissiveColor`, `emissiveStrength`, `frustumCulled`.

## Performance and quality

`Lighting.new({ quality = "low" | "medium" | "high" | "ultra" })` or `lighting:setQuality(name)`. The table in the Portuguese section lists what each preset sets (shadow-map size, shadow softness, simultaneous lights). Fine control (overrides the preset): `setShadowResolution`, `setShadowPcf(0|1|2)`, `setLightLimit(n)`, `setShadowUpdateEvery(n)`, `setLightDistance(d)`, `setFrustumCulling(bool)`, `setShadowsEnabled(bool)`, `setLightsEnabled(bool)`, `setShadowRange`, `setShadowDistance`, `setShadowBias`, `setShadowStrength`. Use `Lighting.new({ maxLights = 32 })` to allow more than 16 lights at once.

Tips: use `drawAll()`; keep `shadowRange` as small as the scene allows; set `castsShadow = false` on floors and skies; call `lighting:updateBounds(model)` if you change a model's vertices after adding it. Orthographic projection turns camera culling off automatically.

## Demo

`WASD`/`Space`/`Shift` move, mouse looks (click to capture), `F` shadows, `G` local lights, `L` flashlight (spot), `T` toon, `B` rim, `V` fog, `Q` quality preset, arrows rotate the sun, `H` toggles the panel, `R` resets the camera.
