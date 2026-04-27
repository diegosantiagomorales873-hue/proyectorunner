-- main.lua (Runner Solar2D) - CORREGIDO Y MEJORADO
-- TABLETA + Controles Touch + Teclado solo en Simulador
-- Ajuste de salto: mas controlado (menos alto) + gravedad un poco mayor
-- Requiere: fondo.mp3, jump.mp3, collect.mp3

display.setStatusBar(display.HiddenStatusBar)

-- FORZAR HORIZONTAL (Método correcto en Solar2D)
native.setProperty("windowOrientation", "landscapeRight")

local physics = require("physics")
physics.start()

-- Ajuste: caída mas natural (ligeramente reducida para mejor control)
physics.setGravity(0, 42)  -- Balance entre control y sensación de peso

physics.setDrawMode("normal") -- pon "hybrid" para ver colisiones

local CX, CY = display.contentCenterX, display.contentCenterY
local W, H = display.contentWidth, display.contentHeight
math.randomseed(os.time())

local isSimulator = (system.getInfo("environment") == "simulator")


-- ESCALAS TABLETA (todo relativo a pantalla)
--------------------------------------------------------------------------------

local minSide = math.min(W, H)

local UI_MARGIN   = math.floor(minSide * 0.03)
local BTN_SIZE    = math.max(92, math.floor(minSide * 0.14)) -- botones grandes
local HUD_SIZE    = math.max(22, math.floor(minSide * 0.05))

local PLAYER_W    = math.max(44, math.floor(minSide * 0.06))
local PLAYER_H    = math.max(58, math.floor(minSide * 0.08))
local COIN_R      = math.max(12, math.floor(minSide * 0.018))
local ENEMY_W     = math.max(44, math.floor(minSide * 0.065))
local ENEMY_H     = math.max(38, math.floor(minSide * 0.045))
local PLATFORM_H  = math.max(18, math.floor(minSide * 0.026))

local GROUND_Y    = math.floor(H * 0.74)

--------------------------------------------------------------------------------
-- REGLAS
--------------------------------------------------------------------------------

local TARGET_SCORE = 100
local COIN_SCORE   = 1
local STOMP_SCORE  = 2
local HIT_PENALTY  = 5

local score = 0
local lives = 3
local state = "playing" -- playing / win / lose


--------------------------------------------------------------------------------
-- AUDIO (CORREGIDO: pcall en todo el bloque de carga)
--------------------------------------------------------------------------------

audio.reserveChannels(4)  -- Aumentado para más efectos

local sndJump    = nil
local sndCollect = nil
local sndStomp   = nil
local sndHurt    = nil
local music      = nil

-- Carga segura de audio
pcall(function()
    sndJump = audio.loadSound("jump.mp3")
end)

pcall(function()
    sndCollect = audio.loadSound("collect.mp3")
end)

pcall(function()
    music = audio.loadStream("fondo.mp3")
end)

-- Efectos opcionales (no crashean si no existen)
pcall(function()
    sndStomp = audio.loadSound("stomp.mp3")
end)

pcall(function()
    sndHurt = audio.loadSound("hurt.mp3")
end)

-- Configurar volúmenes solo si los recursos existen
if music then
    audio.setVolume(0.35, { channel=1 })
    audio.play(music, { channel=1, loops=-1 })
end

if sndJump then
    audio.setVolume(0.85, { channel=2 })
end

if sndCollect then
    audio.setVolume(0.75, { channel=3 })
end

-- Función segura para reproducir sonidos
local function playSound(sound, channel)
    if sound then
        pcall(function()
            audio.play(sound, { channel=channel })
        end)
    end
end

--------------------------------------------------------------------------------
-- GRUPOS
--------------------------------------------------------------------------------

local gWorld = display.newGroup()
local gUI    = display.newGroup()

-- Fondo simple (placeholder)
local bg = display.newRect(gWorld, CX, CY, W, H)
bg:setFillColor(0.06, 0.08, 0.14)

--------------------------------------------------------------------------------
-- HUD
--------------------------------------------------------------------------------

local hud = display.newText({
    parent = gUI,
    text = "Score: 0/100  Lives: 3",
    x = UI_MARGIN, y = UI_MARGIN,
    font = native.systemFontBold,
    fontSize = HUD_SIZE
})
hud.anchorX, hud.anchorY = 0, 0

local helpTxt = display.newText({
    parent = gUI,
    text = "◄ ► Mover  |  ▲ Saltar",
    x = CX, y = H - UI_MARGIN * 0.5,
    width = W * 0.5,  -- Reducido para no tapar botones
    font = native.systemFont,
    fontSize = math.max(16, math.floor(HUD_SIZE * 0.55)),
    align = "center"
})

helpTxt.anchorY = 1
helpTxt:setFillColor(1, 1, 1, 0.5)  -- Más tenue para no distraer

local function updateHUD()
    hud.text = ("Score: %d/%d  Lives: %d"):format(score, TARGET_SCORE, lives)
    
    -- Color dinámico según estado
    if lives == 1 then
        hud:setFillColor(1, 0.3, 0.3)  -- Rojo peligro
    elseif score >= 80 then
        hud:setFillColor(0.3, 1, 0.5)  -- Verde cerca de ganar
    else
        hud:setFillColor(1, 1, 1)      -- Blanco normal
    end
end

--------------------------------------------------------------------------------
-- CAMARA / SCROLL
--------------------------------------------------------------------------------

local cameraX = 0
local scrollSpeed = math.floor(W * 0.18) -- px/s (ajusta a gusto)

local function setCamera(x)
    cameraX = math.max(0, x)  -- Evita valores negativos
    gWorld.x = -cameraX
end

--------------------------------------------------------------------------------
-- INPUT (touch + teclado solo simulador)
--------------------------------------------------------------------------------

local move = { left=false, right=false }   -- touch
local keys = { left=false, right=false }   -- teclado (simulador)

-- Prevención de toques múltiples accidentales
local lastTouchTime = 0
local TOUCH_COOLDOWN = 30  -- ms entre toques

--------------------------------------------------------------------------------
-- BOTONES TOUCH (TABLETA, muy claros) - MEJORADOS
--------------------------------------------------------------------------------

local function makeBtn(label, x, y)
    local g = display.newGroup()
    gUI:insert(g)

    local btn = display.newRoundedRect(g, x, y, BTN_SIZE, BTN_SIZE, math.floor(BTN_SIZE * 0.22))
    btn:setFillColor(0, 0, 0, 0.28)
    btn.strokeWidth = 3
    btn:setStrokeColor(1, 1, 1, 0.35)

    local t = display.newText({
        parent = g,
        text = label,
        x = x, y = y,
        font = native.systemFontBold,
        fontSize = math.floor(BTN_SIZE * 0.48)
    })
    t:setFillColor(1, 1, 1, 0.95)

    -- Guardar referencia para animaciones
    btn._originalFill = {0, 0, 0, 0.28}
    btn._originalX = x
    btn._originalY = y
    
    return btn
end

local baseY = H - UI_MARGIN - BTN_SIZE * 0.5

-- Movimiento (Izquierda)
local btnLeft  = makeBtn("◄", UI_MARGIN + BTN_SIZE * 0.6, baseY)
local btnRight = makeBtn("►", UI_MARGIN + BTN_SIZE * 1.8, baseY)

-- Salto (Derecha)
local btnJump  = makeBtn("▲", W - UI_MARGIN - BTN_SIZE * 0.6, baseY)

-- MEJORADO: Sistema de hold con feedback visual mejorado
local function bindHold(btn, key)
    btn:addEventListener("touch", function(e)
        if state ~= "playing" then return true end
        
        local now = system.getTimer()
        
        if e.phase == "began" then
            -- Verificar cooldown para prevenir toques fantasma
            if now - lastTouchTime < TOUCH_COOLDOWN then
                return true
            end
            lastTouchTime = now
            
            display.getCurrentStage():setFocus(e.target)
            move[key] = true
            
            -- Feedback visual mejorado
            e.target:setFillColor(0.2, 0.6, 1, 0.5)  -- Azul al presionar
            transition.to(e.target, { 
                xScale=0.9, yScale=0.9, 
                time=50 
            })
            
        elseif e.phase == "ended" or e.phase == "cancelled" then
            display.getCurrentStage():setFocus(nil)
            move[key] = false
            
            -- Volver al estado normal
            e.target:setFillColor(unpack(e.target._originalFill))
            transition.to(e.target, { 
                xScale=1.0, yScale=1.0, 
                time=100 
            })
        end
        return true
    end)
end

bindHold(btnLeft, "left")
bindHold(btnRight, "right")

--------------------------------------------------------------------------------
-- PLAYER
--------------------------------------------------------------------------------

local player = display.newRoundedRect(gWorld, 160, GROUND_Y - PLAYER_H, PLAYER_W, PLAYER_H, math.floor(PLAYER_W * 0.25))
player:setFillColor(0.95, 0.62, 0.18)

physics.addBody(player, "dynamic", { density=1.0, friction=0.0, bounce=0.0 })
player.isFixedRotation = true

player.isPlayer = true
player.groundContacts = 0
player.onGround = false
player.flag = "player"  -- Para identificación única

-- doble salto
player.maxJumps = 2
player.jumpsLeft = player.maxJumps

-- coyote time
local COYOTE_TIME = 0.12
player.coyote = 0

-- Invulnerabilidad
player.invul = 0

-- Control de colisiones únicas (evita múltiples detecciones)
player.lastCollisionTime = {}
player.COLLISION_COOLDOWN = 0.1  -- 100ms entre colisiones del mismo tipo

local MOVE_SPEED = math.floor(W * 0.22)

-- Ajuste: salto balanceado
local JUMP_VY = -math.floor(H * 0.82)

-- Efecto visual de daño
local function flashPlayer()
    transition.to(player, { 
        xScale=1.2, yScale=0.8, 
        time=100,
        onComplete=function()
            transition.to(player, { 
                xScale=1.0, yScale=1.0, 
                time=100 
            })
        end
    })
end

-- Efecto visual de stomp
local function stompEffect(x, y)
    local ring = display.newCircle(gWorld, x, y + PLAYER_H*0.5, 10)
    ring:setFillColor(1, 1, 1, 0.8)
    transition.to(ring, { 
        xScale=3, yScale=0.5, 
        alpha=0, 
        time=300,
        onComplete=function() ring:removeSelf() end
    })
end

--------------------------------------------------------------------------------
-- WORLD ARRAYS
--------------------------------------------------------------------------------

local platforms = {}
local coins = {}
local enemies = {}

local CHUNK_W = math.floor(W * 0.42)

local function removeObj(obj)
    if obj and obj.removeSelf then 
        obj:removeSelf() 
    end
end

local function addPlatform(x, y, w, h, kind)
    local r = display.newRect(gWorld, x + w*0.5, y + h*0.5, w, h)
    r:setFillColor(0.22, 0.24, 0.34)
    -- Borde superior para mejor visibilidad
    r.strokeWidth = 2
    r:setStrokeColor(0.3, 0.35, 0.5)
    physics.addBody(r, "static", { friction=0.95, bounce=0.0 })
    r.kind = kind or "platform"
    r.isPlatform = true
    platforms[#platforms+1] = r
    return r
end

local function addCoin(x, y)
    local c = display.newCircle(gWorld, x, y, COIN_R)
    c:setFillColor(1, 0.85, 0.25)
    -- Brillo en la moneda
    c.strokeWidth = 2
    c:setStrokeColor(1, 0.95, 0.5)
    physics.addBody(c, "static", { isSensor=true, radius=COIN_R })
    c.isCoin = true
    coins[#coins+1] = c
    
    -- Animación de flotación
    transition.to(c, { 
        y=y-5, 
        time=500,
        transition=easing.inOutSine,
        iterations=-1,
        reflect=true
    })
    
    return c
end

local function addEnemy(xMin, xMax, y)
    local e = display.newRoundedRect(gWorld, xMin, y - ENEMY_H*0.5, ENEMY_W, ENEMY_H, math.floor(ENEMY_H*0.3))
    e:setFillColor(0.85, 0.25, 0.3)
    physics.addBody(e, "kinematic", { bounce=0.0, friction=0.0 })
    e.isEnemy = true
    e.xMin, e.xMax = xMin, xMax
    e.dir = 1
    e.speed = math.random(math.floor(W*0.07), math.floor(W*0.11)) -- px/s
    enemies[#enemies+1] = e
    
    -- Ojos simples para personalidad
    local eyeL = display.newCircle(gWorld, e.x-ENEMY_W*0.2, e.y-ENEMY_H*0.1, 3)
    eyeL:setFillColor(1, 1, 1)
    local eyeR = display.newCircle(gWorld, e.x+ENEMY_W*0.2, e.y-ENEMY_H*0.1, 3)
    eyeR:setFillColor(1, 1, 1)
    e.eyes = {eyeL, eyeR}
    
    return e
end

--------------------------------------------------------------------------------
-- GENERADOR DE CHUNK
--------------------------------------------------------------------------------

local function buildChunk(startX)
    -- suelo con 1-2 huecos
    local gaps = math.random(1,2)
    local last = startX

    for _=1, gaps do
        local gapW = math.random(math.floor(W*0.07), math.floor(W*0.12))
        local segW = math.random(math.floor(W*0.12), math.floor(W*0.22))
        addPlatform(last, GROUND_Y, segW, H - GROUND_Y, "ground")
        last = last + segW + gapW
    end

    if last < startX + CHUNK_W then
        addPlatform(last, GROUND_Y, (startX+CHUNK_W) - last, H - GROUND_Y, "ground")
    end

    -- elevadas
    local elevCount = math.random(1,3)
    for _=1, elevCount do
        local pw = math.random(math.floor(W*0.10), math.floor(W*0.18))
        local px = math.random(startX + math.floor(W*0.06), startX + CHUNK_W - math.floor(W*0.06) - pw)
        local py = math.random(math.floor(H*0.44), math.floor(H*0.64))
        addPlatform(px, py, pw, PLATFORM_H, "ledge")

        -- monedas arriba
        local per = (pw < math.floor(W*0.13)) and 2 or 3
        for i=1, per do
            local cx = px + 20 + (i-1) * ((pw-40) / math.max(1, (per-1)))
            local cy = py - math.random(math.floor(H*0.05), math.floor(H*0.08))
            addCoin(cx, cy)
        end

        -- enemigo patrulla (CORREGIDO: probabilidad ajustada)
        if math.random() < 0.55 then  -- Ligeramente reducido
            addEnemy(px + 30, px + pw - 30, py)
        end
    end
end

local nextChunkX = 0
for i=1, 3 do
    buildChunk(nextChunkX)
    nextChunkX = nextChunkX + CHUNK_W
end

--------------------------------------------------------------------------------
-- SALTO (MEJORADO: lógica corregida)
--------------------------------------------------------------------------------

local function doJump()
    if state ~= "playing" then return end

    local canJump = player.onGround or player.coyote > 0 or player.jumpsLeft > 0
    if not canJump then return end

    local vx, vy = player:getLinearVelocity()
    player:setLinearVelocity(vx, JUMP_VY)
    playSound(sndJump, 2)

    -- CORREGIDO: Lógica de saltos restantes
    if player.onGround or player.coyote > 0 then
        -- Saltando desde el suelo o coyote time
        player.jumpsLeft = player.maxJumps - 1
    else
        -- Usando doble salto en el aire
        player.jumpsLeft = math.max(0, player.jumpsLeft - 1)
    end

    player.onGround = false
    player.coyote = 0
end

btnJump:addEventListener("tap", function()
    doJump()
    return true
end)

--------------------------------------------------------------------------------
-- TECLADO SOLO EN SIMULADOR
--------------------------------------------------------------------------------

if isSimulator then
    Runtime:addEventListener("key", function(e)
        local down = (e.phase == "down")

        if e.keyName == "left" or e.keyName == "a" then keys.left = down end
        if e.keyName == "right" or e.keyName == "d" then keys.right = down end

        if down and e.keyName == "r" then
            Runtime:dispatchEvent({ name="restartGame" })
        end

        if down and state == "playing" then
            if e.keyName == "space" or e.keyName == "up" or e.keyName == "w" then
                doJump()
            end
        end

        return false
    end)
end

--------------------------------------------------------------------------------
-- WIN / LOSE
--------------------------------------------------------------------------------

local endTxt = display.newText({
    parent = gUI,
    text = "",
    x = CX, y = CY,
    width = W * 0.85,
    font = native.systemFontBold,
    fontSize = math.max(42, math.floor(minSide * 0.08)),
    align = "center"
})
endTxt.isVisible = false

local function win()
    state = "win"
    endTxt.text = "¡YOU WIN!\nToca REINICIAR"
    endTxt:setFillColor(0.7, 1, 0.85)
    endTxt.isVisible = true
    
    -- Efecto de celebración
    transition.from(endTxt, { 
        xScale=0.1, yScale=0.1, 
        time=500,
        transition=easing.outBounce
    })
end

local function lose()
    state = "lose"
    endTxt.text = "GAME OVER\nToca REINICIAR"
    endTxt:setFillColor(1, 0.78, 0.85)
    endTxt.isVisible = true
    
    -- Efecto de derrota
    transition.from(endTxt, { 
        alpha=0, 
        time=800 
    })
end

local function applyPenalty()
    score = score - HIT_PENALTY
    if score < 0 then lose() end
end

--------------------------------------------------------------------------------
-- COLISIONES (CORREGIDO: prevención de múltiples detecciones)
--------------------------------------------------------------------------------

local function removeFromList(list, obj)
    for i=#list, 1, -1 do
        if list[i] == obj then 
            table.remove(list, i) 
            return 
        end
    end
end

local function onCollision(e)
    if state ~= "playing" then return end

    local a, b = e.object1, e.object2
    local ply = (a.isPlayer and a) or (b.isPlayer and b)
    if not ply then return end

    local other = (ply == a) and b or a
    
    -- Prevención de colisiones duplicadas
    local now = system.getTimer() / 1000
    local colKey = tostring(other) .. (e.phase == "began" and "b" or "e")
    
    if ply.lastCollisionTime[colKey] and 
       now - ply.lastCollisionTime[colKey] < ply.COLLISION_COOLDOWN then
        return  -- Ignorar colisión duplicada
    end
    ply.lastCollisionTime[colKey] = now

    if e.phase == "began" then
        -- Plataforma
        if other.isPlatform then
            player.groundContacts = player.groundContacts + 1
            player.onGround = true
            player.jumpsLeft = player.maxJumps
            player.coyote = 0
        end

        -- Moneda
        if other.isCoin and other.removeSelf then
            removeObj(other)
            removeFromList(coins, other)
            score = math.min(TARGET_SCORE, score + COIN_SCORE)
            updateHUD()
            playSound(sndCollect, 3)
            
            -- Efecto de partículas simple
            for i=1, 5 do
                local p = display.newCircle(gWorld, other.x, other.y, 3)
                p:setFillColor(1, 0.85, 0.25)
                local angle = math.random() * math.pi * 2
                transition.to(p, {
                    x=p.x + math.cos(angle) * 30,
                    y=p.y + math.sin(angle) * 30,
                    alpha=0,
                    time=300,
                    onComplete=function() p:removeSelf() end
                })
            end
            
            if score >= TARGET_SCORE then win() end
        end

        -- Enemigo
        if other.isEnemy and other.removeSelf then
            local vx, vy = player:getLinearVelocity()

            if vy > 30 then  -- CORREGIDO: Umbral mínimo para considerar stomp
                -- ¡STOMP!
                local ex, ey = other.x, other.y
                removeObj(other)
                -- Limpiar ojos del enemigo
                if other.eyes then
                    for _, eye in ipairs(other.eyes) do
                        if eye.removeSelf then eye:removeSelf() end
                    end
                end
                removeFromList(enemies, other)
                score = math.min(TARGET_SCORE, score + STOMP_SCORE)
                player:setLinearVelocity(vx, JUMP_VY * 0.70)
                updateHUD()
                playSound(sndStomp, 4)
                stompEffect(ex, ey)
                
                if score >= TARGET_SCORE then win() end
            else
                -- ¡DAÑO!
                if player.invul <= 0 then
                    lives = lives - 1
                    player.invul = 1.2
                    applyPenalty()
                    updateHUD()
                    playSound(sndHurt, 4)
                    flashPlayer()
                    if lives <= 0 then lose() end
                end
            end
        end

    elseif e.phase == "ended" then
        if other.isPlatform then
            player.groundContacts = math.max(0, player.groundContacts - 1)
            if player.groundContacts == 0 then
                player.onGround = false
                player.coyote = COYOTE_TIME
            end
        end
    end
end

Runtime:addEventListener("collision", onCollision)

--------------------------------------------------------------------------------
-- LIMPIEZA + GENERACION
--------------------------------------------------------------------------------

local function cleanupBehind()
    local leftLimit = cameraX - math.floor(W * 0.30)

    for i=#platforms, 1, -1 do
        local p = platforms[i]
        if p and p.x + p.width*0.5 < leftLimit then
            removeObj(p)
            table.remove(platforms, i)
        end
    end

    for i=#coins, 1, -1 do
        local c = coins[i]
        if c and c.x < leftLimit then
            removeObj(c)
            table.remove(coins, i)
        end
    end

    for i=#enemies, 1, -1 do
        local en = enemies[i]
        if en and en.x < leftLimit then
            -- Limpiar ojos
            if en.eyes then
                for _, eye in ipairs(en.eyes) do
                    if eye.removeSelf then eye:removeSelf() end
                end
            end
            removeObj(en)
            table.remove(enemies, i)
        end
    end
end

local function ensureAhead()
    while (nextChunkX - cameraX) < (W * 1.40) do
        buildChunk(nextChunkX)
        nextChunkX = nextChunkX + CHUNK_W
    end
end

--------------------------------------------------------------------------------
-- REINICIO (CORREGIDO)
--------------------------------------------------------------------------------

local function restart()
    -- Limpiar todo
    for i=#platforms, 1, -1 do 
        if platforms[i] and platforms[i].removeSelf then
            platforms[i]:removeSelf()
        end
    end
    for i=#coins, 1, -1 do 
        if coins[i] and coins[i].removeSelf then
            coins[i]:removeSelf()
        end
    end
    for i=#enemies, 1, -1 do 
        if enemies[i] then
            if enemies[i].eyes then
                for _, eye in ipairs(enemies[i].eyes) do
                    if eye.removeSelf then eye:removeSelf() end
                end
            end
            if enemies[i].removeSelf then
                enemies[i]:removeSelf()
            end
        end
    end
    platforms, coins, enemies = {}, {}, {}

    score, lives = 0, 3
    state = "playing"
    endTxt.isVisible = false
    updateHUD()

    player.groundContacts = 0
    player.onGround = false
    player.jumpsLeft = player.maxJumps
    player.invul = 0
    player.coyote = 0
    player.lastCollisionTime = {}
    player.x, player.y = 160, GROUND_Y - PLAYER_H
    player:setLinearVelocity(0, 0)
    player.xScale, player.yScale = 1, 1

    setCamera(0)
    
    nextChunkX = 0
    for i=1, 3 do
        buildChunk(nextChunkX)
        nextChunkX = nextChunkX + CHUNK_W
    end
end

Runtime:addEventListener("restartGame", restart)

-- Boton reiniciar grande (centro abajo)
local btnR = display.newRoundedRect(gUI, CX, H - UI_MARGIN - BTN_SIZE*0.25, BTN_SIZE*2.1, BTN_SIZE*0.7, 18)
btnR:setFillColor(0, 0, 0, 0.25)
local btnRT = display.newText({
    parent = gUI,
    text = "REINICIAR",
    x = CX, y = H - UI_MARGIN - BTN_SIZE*0.25,
    font = native.systemFontBold,
    fontSize = math.floor(HUD_SIZE*0.95)
})
btnRT:setFillColor(1, 1, 1, 0.95)

btnR:addEventListener("tap", function()
    restart()
    return true
end)

--------------------------------------------------------------------------------
-- LOOP PRINCIPAL (CORREGIDO)
--------------------------------------------------------------------------------

local lastTime = system.getTimer()

local function updateEnemies(dt)
    for i=1, #enemies do
        local e = enemies[i]
        if e and e.removeSelf then
            e.x = e.x + e.dir * e.speed * dt
            if e.x < e.xMin then 
                e.x = e.xMin
                e.dir = 1 
            end
            if e.x > e.xMax then 
                e.x = e.xMax
                e.dir = -1 
            end
            
            -- Actualizar posición de los ojos
            if e.eyes then
                for _, eye in ipairs(e.eyes) do
                    if eye.removeSelf then
                        eye.x = e.x + (eye == e.eyes[1] and -ENEMY_W*0.2 or ENEMY_W*0.2)
                        eye.y = e.y - ENEMY_H*0.1
                    end
                end
            end
        end
    end
end

Runtime:addEventListener("enterFrame", function()
    local now = system.getTimer()
    local dt = math.min((now - lastTime) / 1000, 0.05)  -- CAP dt para evitar saltos grandes
    lastTime = now

    if state ~= "playing" then return end

    -- Scroll
    setCamera(cameraX + scrollSpeed * dt)

    -- Movimiento horizontal (touch + teclado)
    local vx, vy = player:getLinearVelocity()
    local desiredVX = 0

    local leftPressed  = move.left or (isSimulator and keys.left)
    local rightPressed = move.right or (isSimulator and keys.right)

    if leftPressed and not rightPressed then 
        desiredVX = -MOVE_SPEED 
    elseif rightPressed and not leftPressed then 
        desiredVX = MOVE_SPEED 
    end

    -- Empujon para no quedarse atras del scroll (CORREGIDO: interpolación suave)
    local minX = cameraX + math.floor(W * 0.06)
    if player.x < minX then 
        player.x = minX + (player.x - minX) * 0.9  -- Interpolación suave
    end

    player:setLinearVelocity(desiredVX, vy)

    -- Invulnerabilidad parpadeo
    if player.invul > 0 then
        player.invul = player.invul - dt
        player.alpha = (math.floor(player.invul * 20) % 2 == 0) and 0.35 or 1
    else
        player.alpha = 1
    end

    -- Coyote time
    if player.coyote > 0 then
        player.coyote = math.max(0, player.coyote - dt)
    end

    updateEnemies(dt)

    -- Caída al vacío
    if player.y > H + 320 then
        if player.invul <= 0 then
            lives = lives - 1
            player.invul = 1.2
            applyPenalty()
            updateHUD()
            playSound(sndHurt, 4)
            flashPlayer()
            if lives <= 0 then lose() end
        end

        player.groundContacts = 0
        player.onGround = false
        player.jumpsLeft = player.maxJumps
        player.coyote = 0
        player.x, player.y = cameraX + 160, GROUND_Y - PLAYER_H
        player:setLinearVelocity(0, 0)
    end

    cleanupBehind()
    ensureAhead()
end)

updateHUD()