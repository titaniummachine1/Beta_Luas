local config = {
	polygon = {
		enabled = true;
		r = 255;
		g = 200;
		b = 155;
		a = 50;

		size = 10;
		segments = 20;
	};
	
	line = {
		enabled = true;
		r = 255;
		g = 255;
		b = 255;
		a = 255;
	};

	flags = {
		enabled = true;
		r = 255;
		g = 0;
		b = 0;
		a = 255;

		size = 5;
	};

	outline = {
		line_and_flags = true;
		polygon = true;
		r = 0;
		g = 0;
		b = 0;
		a = 155;
	};

	-- 0.5 to 8, determines the size of the segments traced, lower values = worse performance (default 2.5)
	measure_segment_size = 2.5;
};


-- Boring shit ahead!
local CROSS = (function(a, b, c) return (b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1]); end);
local CLAMP = (function(a, b, c) return (a<b) and b or (a>c) and c or a; end);
local TRACE_HULL = engine.TraceHull;
local WORLD2SCREEN = client.WorldToScreen;
local POLYGON = draw.TexturedPolygon;
local LINE = draw.Line;
local COLOR = draw.Color;

local aItemDefinitions = {};
do
	local laDefinitions = {
		[222]	= 11;		--Mad Milk                                      tf_weapon_jar_milk
		[812]	= 12;		--The Flying Guillotine                         tf_weapon_cleaver
		[833]	= 12;		--The Flying Guillotine (Genuine)               tf_weapon_cleaver
		[1121]	= 11;		--Mutated Milk                                  tf_weapon_jar_milk

		[18]	= -1;		--Rocket Launcher                               tf_weapon_rocketlauncher
		[205]	= -1;		--Rocket Launcher (Renamed/Strange)             tf_weapon_rocketlauncher
		[127]	= -1;		--The Direct Hit                                tf_weapon_rocketlauncher_directhit
		[228]	= -1;		--The Black Box                                 tf_weapon_rocketlauncher
		[237]	= -1;		--Rocket Jumper                                 tf_weapon_rocketlauncher
		[414]	= -1;		--The Liberty Launcher                          tf_weapon_rocketlauncher
		[441]	= -1;		--The Cow Mangler 5000                          tf_weapon_particle_cannon	
		[513]	= -1;		--The Original                                  tf_weapon_rocketlauncher
		[658]	= -1;		--Festive Rocket Launcher                       tf_weapon_rocketlauncher
		[730]	= -1;		--The Beggar's Bazooka                          tf_weapon_rocketlauncher
		[800]	= -1;		--Silver Botkiller Rocket Launcher Mk.I         tf_weapon_rocketlauncher
		[809]	= -1;		--Gold Botkiller Rocket Launcher Mk.I           tf_weapon_rocketlauncher
		[889]	= -1;		--Rust Botkiller Rocket Launcher Mk.I           tf_weapon_rocketlauncher
		[898]	= -1;		--Blood Botkiller Rocket Launcher Mk.I          tf_weapon_rocketlauncher
		[907]	= -1;		--Carbonado Botkiller Rocket Launcher Mk.I      tf_weapon_rocketlauncher
		[916]	= -1;		--Diamond Botkiller Rocket Launcher Mk.I        tf_weapon_rocketlauncher
		[965]	= -1;		--Silver Botkiller Rocket Launcher Mk.II        tf_weapon_rocketlauncher
		[974]	= -1;		--Gold Botkiller Rocket Launcher Mk.II          tf_weapon_rocketlauncher
		[1085]	= -1;		--Festive Black Box                             tf_weapon_rocketlauncher
		[1104]	= -1;		--The Air Strike                                tf_weapon_rocketlauncher_airstrike
		[15006]	= -1;		--Woodland Warrior                              tf_weapon_rocketlauncher
		[15014]	= -1;		--Sand Cannon                                   tf_weapon_rocketlauncher
		[15028]	= -1;		--American Pastoral                             tf_weapon_rocketlauncher
		[15043]	= -1;		--Smalltown Bringdown                           tf_weapon_rocketlauncher
		[15052]	= -1;		--Shell Shocker                                 tf_weapon_rocketlauncher
		[15057]	= -1;		--Aqua Marine                                   tf_weapon_rocketlauncher
		[15081]	= -1;		--Autumn                                        tf_weapon_rocketlauncher
		[15104]	= -1;		--Blue Mew                                      tf_weapon_rocketlauncher
		[15105]	= -1;		--Brain Candy                                   tf_weapon_rocketlauncher
		[15129]	= -1;		--Coffin Nail                                   tf_weapon_rocketlauncher
		[15130]	= -1;		--High Roller's                                 tf_weapon_rocketlauncher
		[15150]	= -1;		--Warhawk                                       tf_weapon_rocketlauncher

		[442]	= -1;		--The Righteous Bison                           tf_weapon_raygun

		[1178]	= -1;		--Dragon's Fury                                 tf_weapon_rocketlauncher_fireball

		[39]	= 8;		--The Flare Gun                                 tf_weapon_flaregun
		[351]	= 8;		--The Detonator                                 tf_weapon_flaregun
		[595]	= 8;		--The Manmelter                                 tf_weapon_flaregun_revenge
		[740]	= 8;		--The Scorch Shot                               tf_weapon_flaregun
		[1180]	= 0;		--Gas Passer                                    tf_weapon_jar_gas

		[19]	= 5;		--Grenade Launcher                              tf_weapon_grenadelauncher
		[206]	= 5;		--Grenade Launcher (Renamed/Strange)            tf_weapon_grenadelauncher
		[308]	= 5;		--The Loch-n-Load                               tf_weapon_grenadelauncher
		[996]	= 6;		--The Loose Cannon                              tf_weapon_cannon
		[1007]	= 5;		--Festive Grenade Launcher                      tf_weapon_grenadelauncher
		[1151]	= 4;		--The Iron Bomber                               tf_weapon_grenadelauncher
		[15077]	= 5;		--Autumn                                        tf_weapon_grenadelauncher
		[15079]	= 5;		--Macabre Web                                   tf_weapon_grenadelauncher
		[15091]	= 5;		--Rainbow                                       tf_weapon_grenadelauncher
		[15092]	= 5;		--Sweet Dreams                                  tf_weapon_grenadelauncher
		[15116]	= 5;		--Coffin Nail                                   tf_weapon_grenadelauncher
		[15117]	= 5;		--Top Shelf                                     tf_weapon_grenadelauncher
		[15142]	= 5;		--Warhawk                                       tf_weapon_grenadelauncher
		[15158]	= 5;		--Butcher Bird                                  tf_weapon_grenadelauncher

		[20]	= 1;		--Stickybomb Launcher                           tf_weapon_pipebomblauncher
		[207]	= 1;		--Stickybomb Launcher (Renamed/Strange)         tf_weapon_pipebomblauncher
		[130]	= 3;		--The Scottish Resistance                       tf_weapon_pipebomblauncher
		[265]	= 3;		--Sticky Jumper                                 tf_weapon_pipebomblauncher
		[661]	= 1;		--Festive Stickybomb Launcher                   tf_weapon_pipebomblauncher
		[797]	= 1;		--Silver Botkiller Stickybomb Launcher Mk.I     tf_weapon_pipebomblauncher
		[806]	= 1;		--Gold Botkiller Stickybomb Launcher Mk.I       tf_weapon_pipebomblauncher
		[886]	= 1;		--Rust Botkiller Stickybomb Launcher Mk.I       tf_weapon_pipebomblauncher
		[895]	= 1;		--Blood Botkiller Stickybomb Launcher Mk.I      tf_weapon_pipebomblauncher
		[904]	= 1;		--Carbonado Botkiller Stickybomb Launcher Mk.I  tf_weapon_pipebomblauncher
		[913]	= 1;		--Diamond Botkiller Stickybomb Launcher Mk.I    tf_weapon_pipebomblauncher
		[962]	= 1;		--Silver Botkiller Stickybomb Launcher Mk.II    tf_weapon_pipebomblauncher
		[971]	= 1;		--Gold Botkiller Stickybomb Launcher Mk.II      tf_weapon_pipebomblauncher
		[1150]	= 2;		--The Quickiebomb Launcher                      tf_weapon_pipebomblauncher
		[15009]	= 1;		--Sudden Flurry                                 tf_weapon_pipebomblauncher
		[15012]	= 1;		--Carpet Bomber                                 tf_weapon_pipebomblauncher
		[15024]	= 1;		--Blasted Bombardier                            tf_weapon_pipebomblauncher
		[15038]	= 1;		--Rooftop Wrangler                              tf_weapon_pipebomblauncher
		[15045]	= 1;		--Liquid Asset                                  tf_weapon_pipebomblauncher
		[15048]	= 1;		--Pink Elephant                                 tf_weapon_pipebomblauncher
		[15082]	= 1;		--Autumn                                        tf_weapon_pipebomblauncher
		[15083]	= 1;		--Pumpkin Patch                                 tf_weapon_pipebomblauncher
		[15084]	= 1;		--Macabre Web                                   tf_weapon_pipebomblauncher
		[15113]	= 1;		--Sweet Dreams                                  tf_weapon_pipebomblauncher
		[15137]	= 1;		--Coffin Nail                                   tf_weapon_pipebomblauncher
		[15138]	= 1;		--Dressed to Kill                               tf_weapon_pipebomblauncher
		[15155]	= 1;		--Blitzkrieg                                    tf_weapon_pipebomblauncher

		[588]	= -1;		--The Pomson 6000                               tf_weapon_drg_pomson
		[997]	= 9;		--The Rescue Ranger                             tf_weapon_shotgun_building_rescue

		[17]	= 10;		--Syringe Gun                                   tf_weapon_syringegun_medic
		[204]	= 10;		--Syringe Gun (Renamed/Strange)                 tf_weapon_syringegun_medic
		[36]	= 10;		--The Blutsauger                                tf_weapon_syringegun_medic
		[305]	= 9;		--Crusader's Crossbow                           tf_weapon_crossbow
		[412]	= 10;		--The Overdose                                  tf_weapon_syringegun_medic
		[1079]	= 9;		--Festive Crusader's Crossbow                   tf_weapon_crossbow

		[56]	= 7;		--The Huntsman                                  tf_weapon_compound_bow
		[1005]	= 7;		--Festive Huntsman                              tf_weapon_compound_bow
		[1092]	= 7;		--The Fortified Compound                        tf_weapon_compound_bow

		[58]	= 11;		--Jarate                                        tf_weapon_jar
		[1083]	= 11;		--Festive Jarate                                tf_weapon_jar
		[1105]	= 11;		--The Self-Aware Beauty Mark                    tf_weapon_jar
	};

	local iHighestItemDefinitionIndex = 0;
	for i, _ in pairs(laDefinitions) do
		iHighestItemDefinitionIndex = math.max(iHighestItemDefinitionIndex, i);
	end

	for i = 1, iHighestItemDefinitionIndex do
		table.insert(aItemDefinitions, laDefinitions[i] or false)
	end
end

local PhysicsEnvironment = physics.CreateEnvironment();
do
	PhysicsEnvironment:SetGravity( Vector3( 0, 0, -800 ) )
	PhysicsEnvironment:SetAirDensity( 2.0 )
	PhysicsEnvironment:SetSimulationTimestep(1/66)
end

local PhysicsObjectHandler = {};
do
	PhysicsObjectHandler.m_aObjects = {};
	PhysicsObjectHandler.m_iActiveObject = 0;

	function PhysicsObjectHandler:Initialize()
		if #self.m_aObjects > 0 then
			return;
		end

		local function new(path)
			local solid, model = physics.ParseModelByName(path);
			table.insert(self.m_aObjects, PhysicsEnvironment:CreatePolyObject(model, solid:GetSurfacePropName(), solid:GetObjectParameters()));
		end

		new("models/weapons/w_models/w_stickybomb.mdl");										--Stickybomb
		new("models/workshop/weapons/c_models/c_kingmaker_sticky/w_kingmaker_stickybomb.mdl");	--QuickieBomb
		new("models/weapons/w_models/w_stickybomb_d.mdl");										--ScottishResistance, StickyJumper
		
		self.m_aObjects[1]:Wake();
		self.m_iActiveObject = 1;
	end

	function PhysicsObjectHandler:Destroy()
		self.m_iActiveObject = 0;
		
		if #self.m_aObjects == 0 then
			return;
		end
		
		for i, obj in pairs(self.m_aObjects) do
			PhysicsEnvironment:DestroyObject(obj)
			self.m_aObjects[i] = nil;
		end
	end

	setmetatable(PhysicsObjectHandler, {
		__call = function(self, iRequestedObject)
			if iRequestedObject ~= self.m_iActiveObject then
				self.m_aObjects[self.m_iActiveObject]:Sleep();
				self.m_aObjects[iRequestedObject]:Wake();

				self.m_iActiveObject = iRequestedObject;
			end
			
			return self.m_aObjects[self.m_iActiveObject];
		end;
	});
end

local TrajectoryLine = {};
do
	TrajectoryLine.m_aPositions = {};
	TrajectoryLine.m_iSize = 0;
	TrajectoryLine.m_vFlagOffset = Vector3(0, 0, 0);

	function TrajectoryLine:Insert(vec)
		self.m_iSize = self.m_iSize + 1;
		self.m_aPositions[self.m_iSize] = vec;
	end

	local iLineRed,    iLineGreen,    iLineBlue,    iLineAlpha    = config.line.r,    config.line.g,    config.line.b,    config.line.a;
	local iFlagRed,    iFlagGreen,    iFlagBlue,    iFlagAlpha    = config.flags.r,   config.flags.g,   config.flags.b,   config.flags.a;
	local iOutlineRed, iOutlineGreen, iOutlineBlue, iOutlineAlpha = config.outline.r, config.outline.g, config.outline.b, config.outline.a;
	local iOutlineOffsetInner = (config.flags.size < 1) and -1 or 0;
	local iOutlineOffsetOuter = (config.flags.size < 1) and -1 or 1;

	local metatable = {__call = nil;};
	if not config.line.enabled and not config.flags.enabled then
		function metatable:__call() end
	
	elseif config.outline.line_and_flags then
		if config.line.enabled and config.flags.enabled then
			function metatable:__call()
				local positions, offset, last = self.m_aPositions, self.m_vFlagOffset, nil;
				
				COLOR(iOutlineRed, iOutlineGreen, iOutlineBlue, iOutlineAlpha);
				for i = self.m_iSize, 1, -1 do
					local this_pos = positions[i];
					local new, newf = WORLD2SCREEN(this_pos), WORLD2SCREEN(this_pos + offset);
				
					if last and new then
						if math.abs(last[1] - new[1]) > math.abs(last[2] - new[2]) then
							LINE(last[1], last[2] - 1, new[1], new[2] - 1);
							LINE(last[1], last[2] + 1, new[1], new[2] + 1);

						else
							LINE(last[1] - 1, last[2], new[1] - 1, new[2]);
							LINE(last[1] + 1, last[2], new[1] + 1, new[2]);
						end
					end

					if new and newf then
						LINE(newf[1], newf[2] - 1, new[1], new[2] - 1);
						LINE(newf[1], newf[2] + 1, new[1], new[2] + 1);
						LINE(newf[1] - iOutlineOffsetOuter, newf[2] - 1, newf[1] - iOutlineOffsetOuter, newf[2] + 2);
					end
					
					last = new;
				end

				last = nil;

				for i = self.m_iSize, 1, -1 do
					local this_pos = positions[i];
					local new, newf = WORLD2SCREEN(this_pos), WORLD2SCREEN(this_pos + offset);
				
					if last and new then
						COLOR(iLineRed, iLineGreen, iLineBlue, iLineAlpha);
						LINE(last[1], last[2], new[1], new[2]);
					end

					if new and newf then
						COLOR(iFlagRed, iFlagGreen, iFlagBlue, iFlagAlpha);
						LINE(newf[1], newf[2], new[1], new[2]);
					end
					
					last = new;
				end
			end

		elseif config.line.enabled then
			function metatable:__call()
				local positions, offset, last = self.m_aPositions, self.m_vFlagOffset, nil;
				
				for i = self.m_iSize, 1, -1 do
					local this_pos = positions[i];
					local new = WORLD2SCREEN(this_pos);
				
					if last and new then
						COLOR(iOutlineRed, iOutlineGreen, iOutlineBlue, iOutlineAlpha);
						if math.abs(last[1] - new[1]) > math.abs(last[2] - new[2]) then
							LINE(last[1], last[2] - 1, new[1], new[2] - 1);
							LINE(last[1], last[2] + 1, new[1], new[2] + 1);

						else
							LINE(last[1] - 1, last[2], new[1] - 1, new[2]);
							LINE(last[1] + 1, last[2], new[1] + 1, new[2]);
						end

						COLOR(iLineRed, iLineGreen, iLineBlue, iLineAlpha);
						LINE(last[1], last[2], new[1], new[2]);
					end
					
					last = new;
				end
			end

		else
			function metatable:__call()
				local positions, offset = self.m_aPositions, self.m_vFlagOffset;
				
				for i = self.m_iSize, 1, -1 do
					local this_pos = positions[i];
					local new, newf = WORLD2SCREEN(this_pos), WORLD2SCREEN(this_pos + offset);
				
					if new and newf then
						COLOR(iOutlineRed, iOutlineGreen, iOutlineBlue, iOutlineAlpha);
						LINE(new[1] + iOutlineOffsetInner, new[2] - 1, new[1] + iOutlineOffsetInner, new[2] + 2);
						LINE(newf[1], newf[2] - 1, new[1], new[2] - 1);
						LINE(newf[1], newf[2] + 1, new[1], new[2] + 1);
						LINE(newf[1] - iOutlineOffsetOuter, newf[2] - 1, newf[1] - iOutlineOffsetOuter, newf[2] + 2);

						COLOR(iFlagRed, iFlagGreen, iFlagBlue, iFlagAlpha);
						LINE(newf[1], newf[2], new[1], new[2]);
					end
				end
			end
		end

	elseif config.line.enabled and config.flags.enabled then
		function metatable:__call()
			local positions, offset, last = self.m_aPositions, self.m_vFlagOffset, nil;
				
			for i = self.m_iSize, 1, -1 do
				local this_pos = positions[i];
				local new, newf = WORLD2SCREEN(this_pos), WORLD2SCREEN(this_pos + offset);
				
				if last and new then
					COLOR(iLineRed, iLineGreen, iLineBlue, iLineAlpha);
					LINE(last[1], last[2], new[1], new[2]);
				end

				if new and newf then
					COLOR(iFlagRed, iFlagGreen, iFlagBlue, iFlagAlpha);
					LINE(newf[1], newf[2], new[1], new[2]);
				end
					
				last = new;
			end
		end

	elseif config.line.enabled then
		function metatable:__call()
			local positions, last = self.m_aPositions, nil;
			
			COLOR(iLineRed, iLineGreen, iLineBlue, iLineAlpha);
			for i = self.m_iSize, 1, -1 do
				local new = WORLD2SCREEN(positions[i]);
				
				if last and new then
					LINE(last[1], last[2], new[1], new[2]);
				end
					
				last = new;
			end
		end

	else
		function metatable:__call()
			local positions, offset = self.m_aPositions, self.m_vFlagOffset;
			
			COLOR(iFlagRed, iFlagGreen, iFlagBlue, iFlagAlpha);
			for i = self.m_iSize, 1, -1 do
				local this_pos = positions[i];
				local new, newf = WORLD2SCREEN(this_pos), WORLD2SCREEN(this_pos + offset);
				
				if new and newf then
					LINE(newf[1], newf[2], new[1], new[2]);
				end
			end
		end
	end

	setmetatable(TrajectoryLine, metatable);
end

-- Define the ImpactPolygon class
local ImpactPolygon = {}
ImpactPolygon.__index = ImpactPolygon

function ImpactPolygon:new(config)
    local self = setmetatable({}, ImpactPolygon)
    self.config = config  -- Assign the config to self.config
    self.m_iTexture = draw.CreateTextureRGBA(string.char(0xff, 0xff, 0xff, config.polygon.a, 0xff, 0xff, 0xff, config.polygon.a, 0xff, 0xff, 0xff, config.polygon.a, 0xff, 0xff, 0xff, config.polygon.a), 2, 2)
    self.iSegments = config.polygon.segments
    self.fSegmentAngleOffset = math.pi / self.iSegments
    self.fSegmentAngle = self.fSegmentAngleOffset * 2
    return self
end

function ImpactPolygon:destroy()
    if self.m_iTexture then
        draw.DeleteTexture(self.m_iTexture)
        self.m_iTexture = nil
    end
end

local impactPolygon = ImpactPolygon:new(config)

-- Reusable function to calculate positions
function ImpactPolygon:calculatePositions(plane, origin, radius)
    local positions = {}

    if math.abs(plane.z) >= 0.99 then
        for i = 1, self.iSegments do
            local ang = i * self.fSegmentAngle + self.fSegmentAngleOffset
            positions[i] = WORLD2SCREEN(origin + Vector3(radius * math.cos(ang), radius * math.sin(ang), 0))
            if not positions[i] then return nil end
        end
    else
        local right = Vector3(-plane.y, plane.x, 0)
        local up = Vector3(plane.z * right.y, -plane.z * right.x, (plane.y * right.x) - (plane.x * right.y))
        radius = radius / math.cos(math.asin(plane.z))

        for i = 1, self.iSegments do
            local ang = i * self.fSegmentAngle + self.fSegmentAngleOffset
            positions[i] = WORLD2SCREEN(origin + (right * (radius * math.cos(ang))) + (up * (radius * math.sin(ang))))
            if not positions[i] then return nil end
        end
    end

    return positions
end

-- Reusable function to draw outline
function ImpactPolygon:drawOutline(positions)
    local last = positions[#positions]
    COLOR(self.config.outline.r, self.config.outline.g, self.config.outline.b, self.config.outline.a)

    for i = 1, #positions do
        local new = positions[i]
        if math.abs(new[1] - last[1]) > math.abs(new[2] - last[2]) then
            LINE(last[1], last[2] + 1, new[1], new[2] + 1)
            LINE(last[1], last[2] - 1, new[1], new[2] - 1)
        else
            LINE(last[1] + 1, last[2], new[1] + 1, new[2])
            LINE(last[1] - 1, last[2], new[1] - 1, new[2])
        end
        last = new
    end
end

-- Reusable function to draw the polygon
function ImpactPolygon:drawPolygon(positions)
    -- Ensure that config is available
    if not self.config or not self.config.polygon then
        error("Configuration for polygon drawing is missing or invalid")
        return
    end

    -- Set the color based on the config
    COLOR(self.config.polygon.r, self.config.polygon.g, self.config.polygon.b, 255)

    local cords, reverse_cords = {}, {}
    local sizeof = #positions
    local sum = 0

    for i, pos in pairs(positions) do
        local convertedTbl = {pos[1], pos[2], 0, 0}
        cords[i], reverse_cords[sizeof - i + 1] = convertedTbl, convertedTbl
        -- Ensure positions table is valid before accessing it
        local nextPos = positions[(i % sizeof) + 1]
        if not nextPos then
            error("Invalid position in positions table")
            return
        end
        sum = sum + CROSS(pos, nextPos, positions[1])
    end

    -- Draw the polygon with the calculated coordinates
    POLYGON(self.m_iTexture, (sum < 0) and reverse_cords or cords, true)

    -- Draw the final outline around the polygon
    local last = positions[#positions]
    for i = 1, #positions do
        local new = positions[i]
        if not last or not new then
            error("Invalid position detected during final outline drawing")
            return
        end
        LINE(last[1], last[2], new[1], new[2])
        last = new
    end
end

-- Main function to draw impact polygon
function ImpactPolygon:drawImpactPolygon(plane, origin)
    if not self.config.polygon.enabled then return end  -- Check if polygon drawing is enabled

    local positions = self:calculatePositions(plane, origin, self.config.polygon.size)
    if not positions then return end

    if self.config.outline.polygon then
        self:drawOutline(positions)
    end

    self:drawPolygon(positions)
end

-- Metatable to allow the instance to be called like a function
setmetatable(ImpactPolygon, {
    __call = function(self, plane, origin)
        self:drawImpactPolygon(plane, origin)
    end
})

-- Define the ProjectileInfo class
local ProjectileInfo = {}
ProjectileInfo.__index = ProjectileInfo

function ProjectileInfo:new(pLocal, bDucking, iCase, iDefIndex, iWepID)
    local self = setmetatable({}, ProjectileInfo)
    self.pLocal = pLocal
    self.bDucking = bDucking
    self.iCase = iCase
    self.iDefIndex = iDefIndex
    self.iWepID = iWepID
    self.fChargeBeginTime = self:CalculateChargeBeginTime()
    return self
end

function ProjectileInfo:CalculateChargeBeginTime()
    local fChargeBeginTime = self.pLocal:GetPropFloat("PipebombLauncherLocalData", "m_flChargeBeginTime") or 0
    if fChargeBeginTime ~= 0 then
        fChargeBeginTime = globals.CurTime() - fChargeBeginTime
    end
    return fChargeBeginTime
end

function ProjectileInfo:GetOffset(index)
    local offsets = {
        Vector3(16, 8, -6),
        Vector3(23.5, -8, -3),
        Vector3(23.5, 12, -3),
        Vector3(16, 6, -8)
    }
    return offsets[index]
end

function ProjectileInfo:GetCollisionMax(index)
    local collisionMaxs = {
        Vector3(0, 0, 0),
        Vector3(1, 1, 1),
        Vector3(2, 2, 2),
        Vector3(3, 3, 3)
    }
    return collisionMaxs[index]
end

function ProjectileInfo:GetCollisionMin(index)
    return -self:GetCollisionMax(index)
end
function ProjectileInfo:GetProjectileInformation()
    -- Table mapping cases to corresponding function implementations
    local caseFunctions = {
        [-1] = function() return self:RocketLauncherInfo() end,
        [1] = function()
            return {
                self:GetOffset(1),
                900 + CLAMP(self.fChargeBeginTime / 4, 0, 1) * 1500,
                200,
                self:GetCollisionMax(3),
                0
            }
        end,
        [2] = function()
            return {
                self:GetOffset(1),
                900 + CLAMP(self.fChargeBeginTime / 1.2, 0, 1) * 1500,
                200,
                self:GetCollisionMax(3),
                0
            }
        end,
        [3] = function()
            return {
                self:GetOffset(1),
                900 + CLAMP(self.fChargeBeginTime / 4, 0, 1) * 1500,
                200,
                self:GetCollisionMax(3),
                0
            }
        end,
        [4] = function()
            return {
                self:GetOffset(1),
                1200,
                200,
                self:GetCollisionMax(3),
                400,
                0.45
            }
        end,
        [5] = function()
            return {
                self:GetOffset(1),
                (self.iDefIndex == 308) and 1500 or 1200,
                200,
                self:GetCollisionMax(3),
                400,
                (self.iDefIndex == 308) and 0.225 or 0.45
            }
        end,
        [6] = function()
            return {
                self:GetOffset(1),
                1440,
                200,
                self:GetCollisionMax(3),
                560,
                0.5
            }
        end,
        [7] = function()
            return {
                self:GetOffset(2),
                1800 + CLAMP(self.fChargeBeginTime, 0, 1) * 800,
                0,
                self:GetCollisionMax(2),
                200 - CLAMP(self.fChargeBeginTime, 0, 1) * 160
            }
        end,
        [8] = function()
            return {
                Vector3(23.5, 12, self.bDucking and 8 or -3),
                2000,
                0,
                self:GetCollisionMax(1),
                120
            }
        end,
        [9] = function()
            return {
                self:GetOffset(2),
                2400,
                0,
                self:GetCollisionMax((self.iDefIndex == 997) and 2 or 4),
                80
            }
        end,
        [10] = function()
            return {
                self:GetOffset(4),
                1000,
                0,
                self:GetCollisionMax(2),
                120
            }
        end,
        [11] = function()
            return {
                Vector3(23.5, 8, -3),
                1000,
                200,
                self:GetCollisionMax(4),
                450
            }
        end,
        [12] = function()
            return {
                Vector3(23.5, 8, -3),
                3000,
                300,
                self:GetCollisionMax(3),
                900,
                1.3
            }
        end
    }

    -- Call the function corresponding to the current case
    local caseFunction = caseFunctions[self.iCase]
    if caseFunction then
        return caseFunction()
    else
        -- Handle invalid or unhandled cases
        return nil
    end
end

function ProjectileInfo:RocketLauncherInfo()
    local vOffset = Vector3(23.5, -8, self.bDucking and 8 or -3)
    local vCollisionMax = self:GetCollisionMax(2)
    local fForwardVelocity = 0

    if self.iWepID == 22 or self.iWepID == 65 then
        vOffset.y, vCollisionMax, fForwardVelocity = (self.iDefIndex == 513) and 0 or 12, self:GetCollisionMax(1), (self.iWepID == 65) and 2000 or (self.iDefIndex == 414) and 1550 or 1100
    elseif self.iWepID == 109 then
        vOffset.y, vOffset.z = 6, -3
    else
        fForwardVelocity = 1200
    end

    return {vOffset, fForwardVelocity, 0, vCollisionMax, 0}
end

-- Configuration table for projectiles
local projectileConfigurations = {
    [-1] = function(self) return self:RocketLauncherInfo() end,
    [1] = function(self) return self:GetProjectileInformation() end,
    [2] = function(self) return self:GetProjectileInformation() end,
    [3] = function(self) return self:GetProjectileInformation() end,
    [4] = function(self) return self:GetProjectileInformation() end,
    [5] = function(self) return self:GetProjectileInformation() end,
    [6] = function(self) return self:GetProjectileInformation() end,
    [7] = function(self) return self:GetProjectileInformation() end,
    [8] = function(self) return self:GetProjectileInformation() end,
    [9] = function(self) return self:GetProjectileInformation() end,
    [10] = function(self) return self:GetProjectileInformation() end,
    [11] = function(self) return self:GetProjectileInformation() end,
    [12] = function(self) return self:GetProjectileInformation() end,
}

local g_fTraceInterval = CLAMP(config.measure_segment_size, 0.5, 8) / 66
local g_fFlagInterval = g_fTraceInterval * 1320

-- Initialize Physics
local function InitializePhysics()
    PhysicsObjectHandler:Initialize()
end

-- Check if the trajectory should be drawn
local function ShouldDrawTrajectory()
    return not (engine.Con_IsVisible() or engine.IsGameUIVisible())
end

-- Validate the local player
local function IsValidLocalPlayer(pLocal)
    return pLocal and not pLocal:InCond(7) and pLocal:IsAlive()
end

-- Validate the weapon
local function IsValidWeapon(pWeapon)
    return pWeapon and (pWeapon:GetWeaponProjectileType() or 0) >= 2
end

-- Retrieve the projectile information object
local function GetProjectileInformationObject(pLocal, pWeapon)
    local iItemDefinitionIndex = pWeapon:GetPropInt("m_iItemDefinitionIndex")
    local iItemDefinitionType = aItemDefinitions[iItemDefinitionIndex] or 0
    if iItemDefinitionType == 0 then return nil end

    local isDucking = (pLocal:GetPropInt("m_fFlags") & FL_DUCKING) == 2
    local projectileInfo = ProjectileInfo:new(pLocal, isDucking, iItemDefinitionType, iItemDefinitionIndex, pWeapon:GetWeaponID())

    local configFunction = projectileConfigurations[iItemDefinitionType]
    if configFunction then
        return configFunction(projectileInfo), iItemDefinitionType
    else
        return nil
    end
end

-- Trace and simulate the trajectory
local function TraceAndSimulateTrajectory(pLocal, pWeapon)
    TrajectoryLine.m_aPositions, TrajectoryLine.m_iSize = {}, 0

    if not ShouldDrawTrajectory() then return end
    if not IsValidLocalPlayer(pLocal) then return end
    if not IsValidWeapon(pWeapon) then return end

    local projectileInfo, iItemDefinitionType = GetProjectileInformationObject(pLocal, pWeapon)
    if not iItemDefinitionType or not projectileInfo then return end

    local vOffset, fForwardVelocity, fUpwardVelocity, vCollisionMax, fGravity, fDrag = table.unpack(projectileInfo)
    local vCollisionMin = -vCollisionMax

    local vStartPosition, vStartAngle = pLocal:GetAbsOrigin() + pLocal:GetPropVector("localdata", "m_vecViewOffset[0]"), engine.GetViewAngles()

    local results = TRACE_HULL(
        vStartPosition,
        vStartPosition + (vStartAngle:Forward() * vOffset.x) +
        (vStartAngle:Right() * (vOffset.y * (pWeapon:IsViewModelFlipped() and -1 or 1))) +
        (vStartAngle:Up() * vOffset.z),
        vCollisionMin, vCollisionMax, 100679691
    )

    if results.fraction ~= 1 then return end
    vStartPosition = results.endpos

    if iItemDefinitionType == -1 or (iItemDefinitionType >= 7 and iItemDefinitionType < 11) and fForwardVelocity ~= 0 then
        local res = engine.TraceLine(results.startpos, results.startpos + (vStartAngle:Forward() * 2000), 100679691)
        vStartAngle = (((res.fraction <= 0.1) and (results.startpos + (vStartAngle:Forward() * 2000)) or res.endpos) - vStartPosition):Angles()
    end

    local vVelocity = (vStartAngle:Forward() * fForwardVelocity) + (vStartAngle:Up() * fUpwardVelocity)
    TrajectoryLine.m_vFlagOffset = vStartAngle:Right() * -config.flags.size
    TrajectoryLine:Insert(vStartPosition)

    if iItemDefinitionType == -1 then
        results = TRACE_HULL(vStartPosition, vStartPosition + (vStartAngle:Forward() * 10000), vCollisionMin, vCollisionMax, 100679691)
        if results.startsolid then return end

        local iSegments = math.floor((results.endpos - results.startpos):Length() / g_fFlagInterval)
        local vForward = vStartAngle:Forward()

        for i = 1, iSegments do
            TrajectoryLine:Insert(vForward * (i * g_fFlagInterval) + vStartPosition)
        end

        TrajectoryLine:Insert(results.endpos)

    elseif iItemDefinitionType > 3 then

        local vPosition = Vector3(0, 0, 0)
        for i = 0.01515, 5, g_fTraceInterval do
            local scalar = (not fDrag) and i or ((1 - math.exp(-fDrag * i)) / fDrag)

            vPosition.x = vVelocity.x * scalar + vStartPosition.x
            vPosition.y = vVelocity.y * scalar + vStartPosition.y
            vPosition.z = (vVelocity.z - fGravity * i) * scalar + vStartPosition.z

            results = TRACE_HULL(results.endpos, vPosition, vCollisionMin, vCollisionMax, 100679691)

            TrajectoryLine:Insert(results.endpos)

            if results.fraction ~= 1 then break end
        end

    else
        local obj = PhysicsObjectHandler(iItemDefinitionType)

        obj:SetPosition(vStartPosition, vStartAngle, true)
        obj:SetVelocity(vVelocity, Vector3(0, 0, 0))

        for i = 2, 330 do
            results = TRACE_HULL(results.endpos, obj:GetPosition(), vCollisionMin, vCollisionMax, 100679691)
            TrajectoryLine:Insert(results.endpos)

            if results.fraction ~= 1 then break end
            PhysicsEnvironment:Simulate(g_fTraceInterval)
        end

        PhysicsEnvironment:ResetSimulationClock()
    end

    if TrajectoryLine.m_iSize == 0 then return end
    if results then
        impactPolygon = ImpactPolygon:new(config)
        impactPolygon:drawImpactPolygon(results.plane, results.endpos)
    end

    if TrajectoryLine.m_iSize == 1 then return end
    TrajectoryLine()
end

-- Initialize the physics objects
local function InitializePhysicsObjects()
    InitializePhysics()
end

-- Function to draw the trajectory
local function DrawTrajectory()
    local pLocal = entities.GetLocalPlayer()
    local pWeapon = pLocal and pLocal:GetPropEntity("m_hActiveWeapon")

    TraceAndSimulateTrajectory(pLocal, pWeapon)
end

-- Main function for OnCreateMove
local function OnCreateMove()
    -- Initialize the physics objects
    InitializePhysicsObjects()
end

local function CleanupPhysics()
    PhysicsObjectHandler:Destroy()
    physics.DestroyEnvironment(PhysicsEnvironment)
    impactPolygon:destroy()
end

local function OnUnload()
    CleanupPhysics()
end

-- Unregister this callback after initialization
callbacks.Unregister("CreateMove", "LoadPhysicsObjects")
callbacks.Register("CreateMove", "LoadPhysicsObjects", OnCreateMove)

-- Register the drawing callback for rendering the trajectory
callbacks.Register("Draw", "DrawTrajectory", DrawTrajectory)

callbacks.Register("Unload", "CleanupPhysicsObjects", OnUnload)
