-- Create a simple 2x2 white texture for coloring the polygon
local texture = draw.CreateTextureRGBA(string.char(
    0xff, 0xff, 0xff, 255,
    0xff, 0xff, 0xff, 255,
    0xff, 0xff, 0xff, 255,
    0xff, 0xff, 0xff, 255
), 2, 2)

-- Function to generate circle vertices using parametric equations
function GenerateCircleVertices(radius)
    local vertices = {}
    local numSegments = math.max(12, math.floor(radius * 2 * math.pi))  -- Ensures smoothness based on radius
    local angleStep = (2 * math.pi) / numSegments

    local addedPoints = {}  -- To avoid duplicate points

    for i = 0, numSegments do
        local theta = i * angleStep
        local x = radius * math.cos(theta)
        local y = radius * math.sin(theta)

        -- Round to integer values for pixel-perfect drawing
        local ix = math.floor(x + 0.5)
        local iy = math.floor(y + 0.5)

        local key = ix .. "," .. iy
        if not addedPoints[key] then
            table.insert(vertices, {ix, iy})
            addedPoints[key] = true
        end
    end

    return vertices
end

-- Function to draw a circle at a given position and radius
function DrawCircle(originX, originY, radius, r, g, b, a)
    -- Generate vertices for the circle
    local circleVertices = GenerateCircleVertices(radius)

    -- Adjust vertices based on the origin position
    local adjustedVertices = {}
    for i, vertex in ipairs(circleVertices) do
        local adjustedX = originX + vertex[1]
        local adjustedY = originY + vertex[2]
        table.insert(adjustedVertices, {adjustedX, adjustedY, 0, 0})
    end

    -- Set color before drawing
    draw.Color(r, g, b, a)

    -- Draw the polygon using the provided vertices and texture
    draw.TexturedPolygon(texture, adjustedVertices, false)
end

-- Set up parameters for the sine wave motion
local timePos = 0       -- Time variable for position oscillation
local timeRadius = 0    -- Time variable for radius oscillation

-- Define the limits for position and radius oscillation
local posAmplitude = 100   -- Amplitude for position oscillation
local minRadius = 10       -- Minimum radius for oscillation
local maxRadius = 100      -- Maximum radius for oscillation

-- Function to render the circle with sine wave oscillation
function RenderCircle()
    local screenW, screenH = draw.GetScreenSize()

    -- Calculate the origin with sine wave oscillation
    local originX = math.floor(screenW / 2) + math.floor(posAmplitude * math.sin(timePos))
    local originY = math.floor(screenH / 2) + math.floor(posAmplitude * math.cos(timePos))

    -- Calculate the radius with sine wave oscillation
    local amplitudeRadius = (maxRadius - minRadius) / 2
    local midpointRadius = (maxRadius + minRadius) / 2
    local radius = midpointRadius + amplitudeRadius * math.sin(timeRadius)

    -- Increment time variables for smooth animation
    timePos = timePos + 0.05      -- Adjust this to control position oscillation speed
    timeRadius = timeRadius + 0.1 -- Adjust this to control radius oscillation speed

    -- Draw the circle with calculated position and radius
    DrawCircle(originX, originY, radius, 255, 165, 0, 255)  -- Orange color
end


-- Register the named function to the 'Draw' callback for rendering
callbacks.Register("Draw", "RenderCircleCallback", RenderCircle)
