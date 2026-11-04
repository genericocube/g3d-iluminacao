# g3d-iluminacao

**Real-time lighting and shadow mapping for [g3d](https://github.com/groverburger/g3d) 1.6.0 and LÖVE 11.x.**

Choose your language: **[🇺🇸 English](#english)** · **[🇧🇷 Português](#pt-br)**

<a id="english"></a>

## 🇺🇸 English

### Features

- Per-pixel directional lighting.
- Real-time directional shadows using a shadow map.
- 3×3 PCF filtering to soften shadow edges.
- Up to **4 dynamic point lights**, with color, intensity and range.
- Adjustable ambient light and directional-light color/intensity.
- Per-model emissive color, specular strength and shininess.
- Models can independently cast shadows or receive shadows.
- Configurable shadow-map resolution: 512, 1024, 2048 or 4096.
- Texel snapping to reduce shadow shimmering during camera movement.
- GPU-side lighting calculations; Lua sends scene data once per frame.
- No external assets are required for the included demo.

### Demo

Run the repository root with LÖVE:

```bash
love .
```

The demo creates its geometry and 1×1 white texture at runtime. It demonstrates directional lighting, live directional shadows, two animated colored point lights, ambient lighting, emissive objects, specular highlights and runtime shadow-resolution changes.

**Controls**

| Key | Action |
|---|---|
| WASD | Move the camera |
| Mouse | Look around (click to capture) |
| Space / Left Shift | Move up / down |
| F | Toggle shadows |
| G | Toggle point lights |
| 1 / 2 / 3 | Shadow resolution: 512 / 1024 / 2048 |
| Left / Right arrows | Rotate the directional light |
| H | Hide / show controls |
| R | Reset camera |
| Escape | Release the mouse |

### Installation

Keep the `g3d/` folder from g3d in your project and copy the `g3d-iluminacao/` folder from this repository. The module does not replace or patch g3d's core files.

Your project should look like this:

```text
my-game/
├── conf.lua
├── main.lua
├── g3d/
│   ├── init.lua
│   ├── model.lua
│   ├── camera.lua
│   └── ...
└── g3d-iluminacao/
    ├── init.lua
    └── shaders/
        ├── lighting.glsl
        └── shadow.glsl
```

### Quick start

```lua
local g3d = require("g3d")
local Lighting = require("g3d-iluminacao")

local lighting = Lighting.new({
    shadowResolution = 1024,
    shadowRange = 22,
    shadowDistance = 42,
    ambientColor = {0.18, 0.20, 0.25},
    directionalIntensity = 0.9
})

lighting:setDirection(0.4, 0.35, -0.8)

local model = g3d.newModel(
    "assets/cube.obj",
    "assets/texture.png",
    {0, 0, 0}
)

lighting:addModel(model, {
    castsShadow = true,
    receivesShadows = true,
    specularStrength = 0.25,
    shininess = 48
})

lighting:addPointLight({
    position = {2, -2, 3},
    color = {1, 0.35, 0.12},
    intensity = 3,
    range = 8
})

function love.draw()
    -- Updates the shadow map, then renders every registered model.
    lighting:drawAll()
end
```

### API

**Lighting.new(options)**

| Option | Default | Description |
|---|---:|---|
| shadowResolution | 1024 | 512, 1024, 2048 or 4096 |
| shadowRange | 22 | Half-size of the directional shadow area, in world units |
| shadowDistance | 42 | Distance of the shadow camera |
| shadowBias | 0.0018 | Helps reduce shadow acne |
| shadowStrength | 0.9 | Shadow darkness from 0 to 1 |
| ambientColor | {0.19, 0.21, 0.26} | Ambient RGB |
| directionalColor | {1, 0.94, 0.82} | Directional-light RGB |
| directionalIntensity | 0.9 | Directional-light strength |
| shadowsEnabled | true | Enable directional shadows |
| pointLightsEnabled | true | Enable point lights |

**Main methods**

- `addModel(model, options)`: registers a g3d model.
- `removeModel(model)`: removes a registered model.
- `addPointLight(options)`: adds a point light; maximum 4.
- `removePointLight(light)`: removes a point light.
- `setDirection(x, y, z)`: changes the direction in which directional-light rays travel.
- `setAmbient(numberOrRGB)`: changes ambient light.
- `setDirectionalColor(r, g, b)` and `setDirectionalIntensity(value)`.
- `setShadowsEnabled(boolean)` and `setPointLightsEnabled(boolean)`.
- `setShadowResolution(512|1024|2048|4096)`.
- `setShadowRange(value)`, `setShadowDistance(value)`, `setShadowBias(value)`, `setShadowStrength(value)`.
- `drawAll()`: renders the shadow map and every registered model.
- `renderShadows()`: renders only the shadow map for custom render pipelines.
- `release()`: releases the library's GPU resources.

**Model options**

| Option | Default | Description |
|---|---:|---|
| castsShadow | true | Whether the model is drawn in the shadow pass |
| receivesShadows | true | Whether the model receives directional shadows |
| specularStrength | 0.18 | Specular highlight strength |
| shininess | 32 | Specular highlight sharpness |
| emissiveColor | {0, 0, 0} | Self-lit RGB color |
| emissiveStrength | 0 | Self-lit intensity |

**Point-light options**

`position`, `color`, `intensity` and `range`. The point-light table returned by `addPointLight` can be modified at runtime; update its `position`, `color`, `intensity` or `range` fields to animate it.

### Performance notes and current limits

- Lighting is calculated in the GPU shader. Scene uniforms are sent once per `drawAll()`, not once per light per model.
- The shadow pass draws only models with `castsShadow = true`.
- Start with a 512 or 1024 shadow map on low-end GPUs. Higher resolutions increase shadow-map rendering and memory costs.
- The 3×3 PCF filter uses 9 depth samples per shaded pixel when shadows are enabled.
- This version supports one shadow-casting directional light. Point lights are dynamic but do **not** cast shadows yet.
- Opaque models are the intended use case. Transparent and alpha-cutout shadow casting is not implemented.
- The directional shadow camera follows the view camera. Adjust `shadowRange` and `shadowDistance` to fit larger scenes.
- Models should have valid vertex normals. The original g3d OBJ loader supplies normals; procedural models should provide them in the standard g3d vertex format.
- Non-uniform scaling is supported by the shader's inverse-transpose normal matrix.

### Compatibility

Designed for g3d 1.6.0 and LÖVE 11.x. Requires shader support, readable RGBA canvases and a depth buffer. The g3d source in this repository retains its upstream MIT license notices.

### License

The g3d-iluminacao code is MIT licensed. See [LICENSE](LICENSE). The included g3d source remains under its original MIT license and copyright notices.

---

<a id="pt-br"></a>

## 🇧🇷 Português

### Recursos

- Iluminação direcional calculada por pixel.
- Sombras direcionais em tempo real usando shadow mapping.
- Filtro PCF 3×3 para suavizar as bordas das sombras.
- Até **4 luzes pontuais dinâmicas**, com cor, intensidade e alcance.
- Luz ambiente e cor/intensidade da luz direcional configuráveis.
- Cor emissiva, intensidade especular e brilho configuráveis por modelo.
- Cada modelo pode projetar sombras ou apenas recebê-las.
- Resolução do mapa de sombras configurável: 512, 1024, 2048 ou 4096.
- Texel snapping para reduzir o tremido das sombras ao mover a câmera.
- Cálculos de iluminação na GPU; os dados da cena são enviados uma vez por frame.
- O exemplo não precisa de assets externos.

### Exemplo

Execute a raiz do repositório com o LÖVE:

```bash
love .
```

A demonstração gera a geometria e uma textura branca de 1×1 durante a execução. Ela demonstra iluminação direcional, sombras em tempo real, duas luzes pontuais coloridas e animadas, luz ambiente, objetos emissivos, reflexos especulares e alteração da resolução das sombras durante o jogo.

**Controles**

| Tecla | Ação |
|---|---|
| WASD | Mover a câmera |
| Mouse | Olhar ao redor (clique para capturar) |
| Espaço / Shift esquerdo | Subir / descer |
| F | Ativar/desativar sombras |
| G | Ativar/desativar luzes pontuais |
| 1 / 2 / 3 | Resolução das sombras: 512 / 1024 / 2048 |
| Setas esquerda / direita | Girar a luz direcional |
| H | Ocultar / mostrar os controles |
| R | Reiniciar a câmera |
| Escape | Liberar o mouse |

### Instalação

Mantenha a pasta `g3d/` do g3d no projeto e copie a pasta `g3d-iluminacao/` deste repositório. O módulo não substitui nem altera os arquivos centrais do g3d.

A estrutura do projeto deve ficar assim:

```text
meu-jogo/
├── conf.lua
├── main.lua
├── g3d/
│   ├── init.lua
│   ├── model.lua
│   ├── camera.lua
│   └── ...
└── g3d-iluminacao/
    ├── init.lua
    └── shaders/
        ├── lighting.glsl
        └── shadow.glsl
```

### Começando

```lua
local g3d = require("g3d")
local Lighting = require("g3d-iluminacao")

local lighting = Lighting.new({
    shadowResolution = 1024,
    shadowRange = 22,
    shadowDistance = 42,
    ambientColor = {0.18, 0.20, 0.25},
    directionalIntensity = 0.9
})

lighting:setDirection(0.4, 0.35, -0.8)

local model = g3d.newModel(
    "assets/cube.obj",
    "assets/texture.png",
    {0, 0, 0}
)

lighting:addModel(model, {
    castsShadow = true,
    receivesShadows = true,
    specularStrength = 0.25,
    shininess = 48
})

lighting:addPointLight({
    position = {2, -2, 3},
    color = {1, 0.35, 0.12},
    intensity = 3,
    range = 8
})

function love.draw()
    -- Atualiza o mapa de sombras e desenha todos os modelos registrados.
    lighting:drawAll()
end
```

### API

**Lighting.new(options)**

| Opção | Padrão | Descrição |
|---|---:|---|
| shadowResolution | 1024 | 512, 1024, 2048 ou 4096 |
| shadowRange | 22 | Metade do tamanho da área de sombras, em unidades do mundo |
| shadowDistance | 42 | Distância da câmera usada para as sombras |
| shadowBias | 0.0018 | Ajuda a reduzir artefatos de sombra |
| shadowStrength | 0.9 | Escuridão das sombras, de 0 a 1 |
| ambientColor | {0.19, 0.21, 0.26} | Cor RGB da luz ambiente |
| directionalColor | {1, 0.94, 0.82} | Cor RGB da luz direcional |
| directionalIntensity | 0.9 | Intensidade da luz direcional |
| shadowsEnabled | true | Ativa as sombras direcionais |
| pointLightsEnabled | true | Ativa as luzes pontuais |

**Principais métodos**

- `addModel(model, options)`: registra um modelo do g3d.
- `removeModel(model)`: remove um modelo registrado.
- `addPointLight(options)`: adiciona uma luz pontual; máximo de 4.
- `removePointLight(light)`: remove uma luz pontual.
- `setDirection(x, y, z)`: altera a direção em que os raios da luz direcional viajam.
- `setAmbient(numberOrRGB)`: altera a iluminação ambiente.
- `setDirectionalColor(r, g, b)` e `setDirectionalIntensity(value)`.
- `setShadowsEnabled(boolean)` e `setPointLightsEnabled(boolean)`.
- `setShadowResolution(512|1024|2048|4096)`.
- `setShadowRange(value)`, `setShadowDistance(value)`, `setShadowBias(value)`, `setShadowStrength(value)`.
- `drawAll()`: renderiza o mapa de sombras e todos os modelos registrados.
- `renderShadows()`: renderiza somente o mapa de sombras para pipelines personalizados.
- `release()`: libera os recursos de GPU da biblioteca.

**Opções por modelo**

| Opção | Padrão | Descrição |
|---|---:|---|
| castsShadow | true | Define se o modelo participa da geração de sombras |
| receivesShadows | true | Define se o modelo recebe sombras direcionais |
| specularStrength | 0.18 | Intensidade do reflexo especular |
| shininess | 32 | Nitidez do reflexo especular |
| emissiveColor | {0, 0, 0} | Cor RGB própria do objeto |
| emissiveStrength | 0 | Intensidade da emissão de luz |

**Opções das luzes pontuais**

`position`, `color`, `intensity` e `range`. A tabela retornada por `addPointLight` pode ser modificada durante o jogo; altere os campos `position`, `color`, `intensity` ou `range` para animar a luz.

### Desempenho e limitações atuais

- A iluminação é calculada no shader da GPU. Os uniformes da cena são enviados uma vez por chamada de `drawAll()`, e não uma vez por luz para cada modelo.
- A etapa de sombras desenha somente os modelos com `castsShadow = true`.
- Em GPUs mais simples, comece com um mapa de sombras de 512 ou 1024. Resoluções maiores aumentam o custo de renderização e memória.
- O filtro PCF 3×3 faz 9 amostras do mapa de sombras por pixel quando as sombras estão ativadas.
- Esta versão suporta uma luz direcional que projeta sombras. As luzes pontuais são dinâmicas, mas ainda **não projetam sombras**.
- O uso principal é com modelos opacos. Sombras para transparência e alpha-cutout ainda não foram implementadas.
- A câmera das sombras acompanha a câmera de visualização. Ajuste `shadowRange` e `shadowDistance` para cenas maiores.
- Os modelos precisam ter normais válidas nos vértices. O carregador OBJ original do g3d fornece normais; modelos procedurais devem usar o formato padrão de vértices do g3d.
- Escalas não uniformes são tratadas pela matriz normal inverse-transpose do shader.

### Compatibilidade

Desenvolvido para g3d 1.6.0 e LÖVE 11.x. Requer suporte a shaders, canvases RGBA legíveis e buffer de profundidade. O código do g3d incluído neste repositório mantém os avisos de licença MIT e direitos autorais originais.

### Licença

O código do g3d-iluminacao utiliza a licença MIT. Consulte [LICENSE](LICENSE). O código do g3d incluído mantém sua licença MIT e os avisos de direitos autorais originais.
