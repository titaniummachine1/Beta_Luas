-- Configuration
local CAMERA_TEXTURE_NAME = "sentry_cam_texture"
local CAMERA_MATERIAL_NAME = "sentry_cam_material"
local CAMERA_WIDTH, CAMERA_HEIGHT = 500, 400
local FONT_DEBUG = draw.CreateFont("Tahoma", 14, 800, FONTFLAG_OUTLINE)

-- If true, draw the camera ONLY when the sentry has a valid enemy target.
-- If false, draw the camera feed always (even if no target).
local ONLY_DRAW_WHEN_TARGET = false

-- Index of the barrel hitbox. Adjust as needed for your model:
local SENTR_HITBOX_BARREL = 5

-- Globals
local cameraTexture = nil
local cameraMaterial = nil
local sentryEntity  = nil
local materialsInitialized = false

----------------------------------------------------------------
-- Initialization and Cleanup
----------------------------------------------------------------

local function InitializeMaterials()
    if materialsInitialized then return true end

    cameraTexture = materials.CreateTextureRenderTarget(CAMERA_TEXTURE_NAME, CAMERA_WIDTH, CAMERA_HEIGHT)
    if not cameraTexture then
        print("Failed to create camera texture.")
        return false
    end

    cameraMaterial = materials.Create(CAMERA_MATERIAL_NAME, string.format([[
        UnlitGeneric
        {
            $basetexture    "%s"
            $ignorez        1
        }
    ]], CAMERA_TEXTURE_NAME))
    if not cameraMaterial then
        print("Failed to create camera material.")
        draw.DeleteTexture(cameraTexture:GetID())
        cameraTexture = nil
        return false
    end

    materialsInitialized = true
    return true
end

local function CleanupMaterials()
    if cameraTexture then
        draw.DeleteTexture(cameraTexture:GetID())
        cameraTexture = nil
    end
    cameraMaterial = nil
    materialsInitialized = false
end

----------------------------------------------------------------
-- Utility: Find the local player’s sentry
----------------------------------------------------------------

local function FindSentry()
    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then return nil end

    local sentries = entities.FindByClass("CObjectSentrygun")
    for _, sentry in pairs(sentries) do
        if sentry:IsValid() and not sentry:IsDormant() then
            local builder = sentry:GetPropEntity("m_hBuilder")
            if builder == localPlayer then
                return sentry
            end
        end
    end
    return nil
end

----------------------------------------------------------------
-- Compute the camera position & angle from the barrel’s bone
-- m_hEnemy is used ONLY to check if a target is present.
----------------------------------------------------------------

local function GetSentryAimData(sentry)
    local hitboxes = sentry:GetHitboxes()
    if not hitboxes or not hitboxes[SENTR_HITBOX_BARREL] then
        return nil, nil, false
    end

    -- Barrel center
    local barrelHitbox = hitboxes[SENTR_HITBOX_BARREL]
    local barrelPos = Vector3(
        (barrelHitbox[1].x + barrelHitbox[2].x) / 2,
        (barrelHitbox[1].y + barrelHitbox[2].y) / 2,
        (barrelHitbox[1].z + barrelHitbox[2].z) / 2
    )

    -- Check if there’s a valid target
    local target = sentry:GetPropEntity("m_hEnemy")
    local hasTarget = (target and target:IsValid() and not target:IsDormant())

    -- We do NOT use target position for angles, only the bone’s forward vector.
    -- Let’s read the bone matrix for the barrel to get its forward direction.
    local boneMatrices = sentry:SetupBones()
    if not boneMatrices then
        return barrelPos, EulerAngles(0,0,0), hasTarget
    end

    -- Example approach: use the same index as the hitbox for the bone,
    -- or you might have a different bone index. Adjust as needed if
    -- the bone index differs from the hitbox index.
    local barrelMatrix = boneMatrices[SENTR_HITBOX_BARREL]
    if not barrelMatrix then
        return barrelPos, EulerAngles(0,0,0), hasTarget
    end

    -- The forward vector is stored in columns [1][3], [2][3], [3][3] of the matrix.
    local forwardVector = Vector3(
        -barrelMatrix[1][1],
        -barrelMatrix[2][1]
    )
    local aimAngles = forwardVector:Angles()
    aimAngles = EulerAngles(aimAngles.x, aimAngles.y, 0)

    return barrelPos, aimAngles, hasTarget
end

----------------------------------------------------------------
-- Optional: Debugging Hitboxes
----------------------------------------------------------------

local function DrawHitboxes(sentry)
    local hitboxes = sentry:GetHitboxes()
    if not hitboxes then return end

    for i, hitbox in ipairs(hitboxes) do
        local centerPos = Vector3(
            (hitbox[1].x + hitbox[2].x) / 2,
            (hitbox[1].y + hitbox[2].y) / 2,
            (hitbox[1].z + hitbox[2].z) / 2
        )
        local screenPos = client.WorldToScreen(centerPos)
        if screenPos then
            draw.Color(255, 255, 0, 255)
            draw.FilledRect(screenPos[1] - 2, screenPos[2] - 2, screenPos[1] + 2, screenPos[2] + 2)
            draw.SetFont(FONT_DEBUG)
            draw.Text(screenPos[1] + 5, screenPos[2] - 5, string.format("Hitbox %d", i))
        end
    end
end

----------------------------------------------------------------
-- Rendering the Sentry POV
----------------------------------------------------------------

callbacks.Register("PostRenderView", function(view)
    if not InitializeMaterials() then return end

    if not sentryEntity or not sentryEntity:IsValid() then
        sentryEntity = FindSentry()
    end
    if not sentryEntity then return end

    local barrelPos, sentryAngles, hasTarget = GetSentryAimData(sentryEntity)
    if not barrelPos or not sentryAngles then return end

    -- If config says "only draw if target is found" and we have no target, skip
    if ONLY_DRAW_WHEN_TARGET and not hasTarget then
        return
    end

    -- Create a custom view from the sentry’s muzzle
    local sentryView = view
    sentryView.origin = barrelPos
    sentryView.angles = sentryAngles

    -- Render the scene into our camera texture
    render.Push3DView(sentryView, E_ClearFlags.VIEW_CLEAR_COLOR | E_ClearFlags.VIEW_CLEAR_DEPTH, cameraTexture)
    render.ViewDrawScene(true, true, sentryView)
    render.PopView()

    -- Draw the camera on HUD
    local screenWidth, screenHeight = draw.GetScreenSize()
    local x, y = screenWidth - CAMERA_WIDTH - 10, screenHeight - CAMERA_HEIGHT - 10
    render.DrawScreenSpaceRectangle(
        cameraMaterial,
        x, y,
        CAMERA_WIDTH, CAMERA_HEIGHT,
        0, 0,
        CAMERA_WIDTH, CAMERA_HEIGHT,
        CAMERA_WIDTH, CAMERA_HEIGHT
    )
end)

-- Draw the sentry’s hitboxes for debugging
callbacks.Register("Draw", function()
    if sentryEntity and sentryEntity:IsValid() then
        DrawHitboxes(sentryEntity)
    end
end)

----------------------------------------------------------------
-- Cleanup on script unload
----------------------------------------------------------------

callbacks.Register("Unload", function()
    CleanupMaterials()
end)
