----------------------------
-- Civ 6 Enumerated Types --
----------------------------
--
-- PLOT_TYPE
--
-- Civ 4 and 5 had separate types for Plots (water, hills, land, mountain) and Terrain (grassland, plains, tundra).  But once map generation was complete and the game
-- commenced there was no longer a need for the distinction between the two.  For Civ 6 we are going to still generate the map in these two passes.  However inside the
-- game we will store the data as a single type (Terrain).  We therefore need a new intermediate data type (PLOT_TYPE) just for map generation.  This data is stored using
-- the enumeration below
function GetGameInfoIndex(table_name, type_name) 
	local index;
	local table = GameInfo[table_name];
	if(table) then
		local t = table[type_name];
		if(t) then
			index = t.Index;
		end
	end

	return index;
end

-- These are internal to the map generator code, it is ok they are hard-coded.
g_PLOT_TYPE_NONE		= -1;
g_PLOT_TYPE_MOUNTAIN	= 0;
g_PLOT_TYPE_HILLS		= 1;
g_PLOT_TYPE_LAND		= 2;
g_PLOT_TYPE_OCEAN		= 3;

-- These come from the database.  Get the runtime index values.
g_TERRAIN_TYPE_NONE					= -1;
g_TERRAIN_TYPE_GRASS				= GetGameInfoIndex("Terrains", "TERRAIN_GRASS");
g_TERRAIN_TYPE_GRASS_HILLS			= GetGameInfoIndex("Terrains", "TERRAIN_GRASS_HILLS");
g_TERRAIN_TYPE_GRASS_MOUNTAIN		= GetGameInfoIndex("Terrains", "TERRAIN_GRASS_MOUNTAIN");
g_TERRAIN_TYPE_PLAINS				= GetGameInfoIndex("Terrains", "TERRAIN_PLAINS");
g_TERRAIN_TYPE_PLAINS_HILLS			= GetGameInfoIndex("Terrains", "TERRAIN_PLAINS_HILLS");
g_TERRAIN_TYPE_PLAINS_MOUNTAIN		= GetGameInfoIndex("Terrains", "TERRAIN_PLAINS_MOUNTAIN");
g_TERRAIN_TYPE_DESERT				= GetGameInfoIndex("Terrains", "TERRAIN_DESERT");
g_TERRAIN_TYPE_DESERT_HILLS			= GetGameInfoIndex("Terrains", "TERRAIN_DESERT_HILLS");
g_TERRAIN_TYPE_DESERT_MOUNTAIN		= GetGameInfoIndex("Terrains", "TERRAIN_DESERT_MOUNTAIN");
g_TERRAIN_TYPE_TUNDRA				= GetGameInfoIndex("Terrains", "TERRAIN_TUNDRA");
g_TERRAIN_TYPE_TUNDRA_HILLS			= GetGameInfoIndex("Terrains", "TERRAIN_TUNDRA_HILLS");
g_TERRAIN_TYPE_TUNDRA_MOUNTAIN		= GetGameInfoIndex("Terrains", "TERRAIN_TUNDRA_MOUNTAIN");
g_TERRAIN_TYPE_SNOW					= GetGameInfoIndex("Terrains", "TERRAIN_SNOW");
g_TERRAIN_TYPE_SNOW_HILLS			= GetGameInfoIndex("Terrains", "TERRAIN_SNOW_HILLS");
g_TERRAIN_TYPE_SNOW_MOUNTAIN		= GetGameInfoIndex("Terrains", "TERRAIN_SNOW_MOUNTAIN");
g_TERRAIN_TYPE_COAST				= GetGameInfoIndex("Terrains", "TERRAIN_COAST");
g_TERRAIN_TYPE_OCEAN				= GetGameInfoIndex("Terrains", "TERRAIN_OCEAN");

-- We are stil going to make an assumption about the ordering if the TerrainTypes, relative to the 'base' type.  
-- This may change, probably to a lookup table to avoid database ordering dependencies.
g_TERRAIN_BASE_TO_HILLS_DELTA		= 1;
g_TERRAIN_BASE_TO_MOUNTAIN_DELTA	= 2;

g_FEATURE_NONE						= -1;
g_FEATURE_FLOODPLAINS				= GetGameInfoIndex("Features", "FEATURE_FLOODPLAINS");
g_FEATURE_FLOODPLAINS_GRASSLAND		= GetGameInfoIndex("Features", "FEATURE_FLOODPLAINS_GRASSLAND");
g_FEATURE_FLOODPLAINS_PLAINS		= GetGameInfoIndex("Features", "FEATURE_FLOODPLAINS_PLAINS");
g_FEATURE_ICE						= GetGameInfoIndex("Features", "FEATURE_ICE");
g_FEATURE_JUNGLE					= GetGameInfoIndex("Features", "FEATURE_JUNGLE");
g_FEATURE_FOREST					= GetGameInfoIndex("Features", "FEATURE_FOREST");
g_FEATURE_OASIS						= GetGameInfoIndex("Features", "FEATURE_OASIS");
g_FEATURE_MARSH						= GetGameInfoIndex("Features", "FEATURE_MARSH");
g_FEATURE_REEF						= GetGameInfoIndex("Features", "FEATURE_REEF");
g_FEATURE_GEOTHERMAL_FISSURE		= GetGameInfoIndex("Features", "FEATURE_GEOTHERMAL_FISSURE");
g_FEATURE_VOLCANIC_SOIL				= GetGameInfoIndex("Features", "FEATURE_VOLCANIC_SOIL");
g_FEATURE_VOLCANO					= GetGameInfoIndex("Features", "FEATURE_VOLCANO");

g_FEATURE_BARRIER_REEF				= GetGameInfoIndex("Features", "FEATURE_BARRIER_REEF");
g_FEATURE_CLIFFS_DOVER				= GetGameInfoIndex("Features", "FEATURE_CLIFFS_DOVER");
g_FEATURE_CRATER_LAKE				= GetGameInfoIndex("Features", "FEATURE_CRATER_LAKE");
g_FEATURE_DEAD_SEA					= GetGameInfoIndex("Features", "FEATURE_DEAD_SEA");
g_FEATURE_EVEREST					= GetGameInfoIndex("Features", "FEATURE_EVEREST");
g_FEATURE_GALAPAGOS					= GetGameInfoIndex("Features", "FEATURE_GALAPAGOS");
g_FEATURE_KILIMANJARO				= GetGameInfoIndex("Features", "FEATURE_KILIMANJARO");
g_FEATURE_PANTANAL					= GetGameInfoIndex("Features", "FEATURE_PANTANAL");
g_FEATURE_PIOPIOTAHI				= GetGameInfoIndex("Features", "FEATURE_PIOPIOTAHI");
g_FEATURE_TORRES_DEL_PAINE			= GetGameInfoIndex("Features", "FEATURE_TORRES_DEL_PAINE");
g_FEATURE_TSINGY					= GetGameInfoIndex("Features", "FEATURE_TSINGY");
g_FEATURE_YOSEMITE					= GetGameInfoIndex("Features", "FEATURE_YOSEMITE");

g_YIELD_FOOD						= GetGameInfoIndex("Yields", "YIELD_FOOD");
g_YIELD_PRODUCTION					= GetGameInfoIndex("Yields", "YIELD_PRODUCTION");
g_YIELD_GOLD						= GetGameInfoIndex("Yields", "YIELD_GOLD");
g_YIELD_SCIENCE						= GetGameInfoIndex("Yields", "YIELD_SCIENCE");
g_YIELD_CULTURE						= GetGameInfoIndex("Yields", "YIELD_CULTURE");
g_YIELD_FAITH						= GetGameInfoIndex("Yields", "YIELD_FAITH");

DirectionTypes = {
		DIRECTION_NORTHEAST = 0,
		DIRECTION_EAST = 1,
		DIRECTION_SOUTHEAST = 2,
		DIRECTION_SOUTHWEST = 3,
		DIRECTION_WEST= 4,
		DIRECTION_NORTHWEST = 5,
		NUM_DIRECTION_TYPES = 6,
};


-------------------------------------------------------------------------------
-- Ability Draft (PoC Draft Transport) v27.5: start biases from the draft, for BBS
-- (everything above is the unchanged Gathering Storm MapEnums.lua)
--
-- BBS asks for start biases by civilization (BBS_AssignStartingPlots:__FindBias).
-- With the draft, a player's sea picks (POCD_SlotBias, built by Data/POCD_StartBias.sql)
-- must reach only that player, even when two players share a civilization. NewBBS asks for
-- the biases of every major once, in PlayerManager.GetAliveMajorIDs() order, so the n-th
-- call for a civilization belongs to the n-th player of that civilization.
-- The hook is put in lazily: the first print / MapConfiguration.GetValue call after BBS
-- is loaded wraps __FindBias (and BBS_Balance's IsTundraCiv for King of the North), then
-- both triggers are removed again. Without BBS or without draft data nothing changes.
-------------------------------------------------------------------------------
if POCD_SB == nil and TerrainBuilder ~= nil then
	POCD_SB = { ver = "27.5", armed = false, done = false, mine = {}, checks = 0, budget = 20000 };
end

if POCD_SB ~= nil and not POCD_SB.armed then
	local S = POCD_SB;
	S.armed = true;
	S.print = print;

	local function SB_Log(msg)
		pcall(S.print, "POCD_SB: " .. tostring(msg));
	end

	-- draft biases per player and the majors of every civilization, read once
	local function SB_Data()
		if S.data ~= nil then return S.data; end
		local d = { slots = {}, rows = 0, civPlayers = {}, calls = {}, ocean = {}, kotn = {}, civOf = {} };
		S.data = d;
		local ok, rows = pcall(DB.Query, "SELECT Slot, Mode, BiasType, TargetType, Tier, Source FROM POCD_SlotBias");
		if ok and type(rows) == "table" then
			for _, r in pairs(rows) do
				local slot = tonumber(r.Slot);
				if slot ~= nil and type(r.BiasType) == "string" then
					local list = d.slots[slot];
					if list == nil then list = {}; d.slots[slot] = list; end
					local target = r.TargetType;
					if target == "" then target = nil; end
					table.insert(list, { Mode = r.Mode or "ADD", BiasType = r.BiasType, TargetType = target, Tier = tonumber(r.Tier) or 1, Source = tostring(r.Source) });
					d.rows = d.rows + 1;
				end
			end
		else
			SB_Log("no draft start biases (" .. tostring(rows) .. ")");
		end
		local oceanLeaders = {};
		pcall(function()
			for row in GameInfo.Leaders_XP2() do
				if row.OceanStart == true or row.OceanStart == 1 then oceanLeaders[row.LeaderType] = true; end
			end
		end);
		-- same walk as NewBBS: majors in GetAliveMajorIDs order, spectators skipped
		local okP, errP = pcall(function()
			local ids = PlayerManager.GetAliveMajorIDs();
			for i = 1, PlayerManager.GetAliveMajorsCount() do
				local id = ids[i];
				local cfg = PlayerConfigurations[id];
				if cfg ~= nil then
					local leader = cfg:GetLeaderTypeName();
					if leader ~= "LEADER_SPECTATOR" and cfg:GetHandicapTypeID() ~= 2021024770 then
						local civ = cfg:GetCivilizationTypeName();
						local list = d.civPlayers[civ];
						if list == nil then list = {}; d.civPlayers[civ] = list; end
						table.insert(list, id);
						d.civOf[id] = civ;
						if oceanLeaders[leader] then d.ocean[id] = true; end
						local extras = d.slots[id];
						if extras ~= nil and not d.ocean[id] then
							for _, e in ipairs(extras) do
								if e.Mode == "ADD" and e.BiasType == "CUSTOM_KING_OF_THE_NORTH" then d.kotn[id] = true; end
							end
						end
					end
				end
			end
		end);
		if not okP then
			SB_Log("cannot list players (" .. tostring(errP) .. "), standard biases for everyone");
			d.civPlayers = {};
			d.kotn = {};
		end
		SB_Log("loaded " .. d.rows .. " draft bias rows");
		return d;
	end

	-- BBS bias types that point at a row of a GameInfo table
	local SB_TABLES = { TERRAINS = "Terrains", FEATURES = "Features", RESOURCES = "Resources" };

	-- the original biases of the civilization, edited and extended by this player's draft biases
	local function SB_Augment(biases, civ)
		local d = SB_Data();
		local list = d.civPlayers[civ];
		if list == nil or #list == 0 then return nil; end		-- city-state or not a major
		local n = (d.calls[civ] or 0) + 1;
		d.calls[civ] = n;
		local id = list[((n - 1) % #list) + 1];
		local extras = d.slots[id];
		if extras == nil or #extras == 0 then
			SB_Log("player " .. id .. " " .. tostring(civ) .. ": standard biases");
			return nil;
		end
		if d.ocean[id] then
			SB_Log("player " .. id .. " " .. tostring(civ) .. ": ocean start leader, standard biases");
			return nil;
		end
		local out = {};
		if type(biases) == "table" then
			for _, b in ipairs(biases) do table.insert(out, b); end
		end
		local notes = {};
		-- 1) DROP / SET: edits of the civilization's standard biases
		for _, e in ipairs(extras) do
			if e.Mode == "DROP" or e.Mode == "SET" then
				local tbl = SB_TABLES[e.BiasType];
				local v = nil;
				if tbl ~= nil then v = GetGameInfoIndex(tbl, e.TargetType or ""); end
				if tbl == nil or (v ~= nil and v >= 0) then
					local kept, hit = {}, 0;
					for _, b in ipairs(out) do
						local same = (b.Type == e.BiasType) and (tbl == nil or b.Value == v);
						if same then
							hit = hit + 1;
							if e.Mode == "SET" then
								b.Tier = e.Tier;
								table.insert(kept, b);
							end
						else
							table.insert(kept, b);
						end
					end
					out = kept;
					local what = e.TargetType or e.BiasType;
					if hit > 0 then
						table.insert(notes, (e.Mode == "SET" and ("set " .. what .. " t" .. e.Tier) or ("drop " .. what)) .. " (" .. e.Source .. ")");
					end
				end
			end
		end
		-- 2) ADD: biases from the picks (the strongest tier wins)
		for _, e in ipairs(extras) do
			local tbl = SB_TABLES[e.BiasType];
			if e.Mode == "ADD" and tbl ~= nil and e.TargetType ~= nil then
				local v = GetGameInfoIndex(tbl, e.TargetType);
				if v ~= nil and v >= 0 then
					local found = nil;
					for _, b in ipairs(out) do
						if b.Type == e.BiasType and b.Value == v then found = b; break; end
					end
					if found == nil then
						table.insert(out, { Type = e.BiasType, Value = v, Tier = e.Tier });
						table.insert(notes, e.TargetType .. " t" .. e.Tier .. " (" .. e.Source .. ")");
					elseif e.Tier < found.Tier then
						table.insert(notes, e.TargetType .. " t" .. found.Tier .. "->t" .. e.Tier .. " (" .. e.Source .. ")");
						found.Tier = e.Tier;
					else
						table.insert(notes, e.TargetType .. " already t" .. found.Tier .. " (" .. e.Source .. ")");
					end
				end
			elseif e.Mode == "ADD" and string.sub(e.BiasType, 1, 7) == "CUSTOM_" then
				local found = false;
				for _, b in ipairs(out) do
					if b.Type == e.BiasType then found = true; break; end
				end
				if not found then
					table.insert(out, { Type = e.BiasType, Tier = 1, Value = -1 });
					table.insert(notes, e.BiasType .. " (" .. e.Source .. ")");
				else
					table.insert(notes, e.BiasType .. " already (" .. e.Source .. ")");
				end
			end
		end
		table.sort(out, function(a, b) return a.Tier < b.Tier; end);
		local final = {};
		for _, b in ipairs(out) do
			table.insert(final, tostring(b.Type) .. ":" .. tostring(b.Value) .. "/t" .. tostring(b.Tier));
		end
		SB_Log("player " .. id .. " " .. tostring(civ) .. ": " .. (#notes > 0 and table.concat(notes, ", ") or "no change") .. " => " .. table.concat(final, " "));
		return out;
	end

	-- BBS_Balance: a player of this civilization counts as a tundra civilization when every
	-- player of the civilization got King of the North from the draft (no leak to a duplicate)
	local function SB_AllKotN(civ)
		local d = SB_Data();
		local list = d.civPlayers[civ];
		if list == nil or #list == 0 then return false; end
		for _, id in ipairs(list) do
			if not d.kotn[id] then return false; end
		end
		return true;
	end

	-- BBS_Balance desert civilization (Mali, Nubia; Maya is already a tundra civilization in BBS):
	-- no tundra handling from the draft, BBS would otherwise run both its desert and its tundra pass
	local function SB_IsDesertCiv(civ)
		local f = IsDesertCiv;
		if f == nil and type(_G) == "table" then f = _G.IsDesertCiv; end
		if type(f) ~= "function" then return false; end
		local ok, r = pcall(f, civ);
		return ok and r == true;
	end

	local function SB_Release()
		if S.gvWrapper ~= nil and MapConfiguration.GetValue == S.gvWrapper then
			pcall(function() MapConfiguration.GetValue = S.origGetValue; end);
		end
		if S.printWrapper ~= nil and print == S.printWrapper then
			print = S.print;
		end
	end

	local function SB_Check()
		if S.inCheck or S.done then return; end
		S.inCheck = true;
		S.checks = S.checks + 1;
		local t = BBS_AssignStartingPlots;
		if t == nil and type(_G) == "table" then t = _G.BBS_AssignStartingPlots; end
		if S.checks == 1 then
			SB_Log("first check: BBS_AssignStartingPlots " .. type(t) .. ", IsTundraCiv " .. type(IsTundraCiv));
		end
		if type(t) == "table" then
			local f = t.__FindBias;
			if type(f) == "function" and not S.mine[f] then
				local orig = f;
				local w = function(self, civilizationType)
					local biases = orig(self, civilizationType);
					if not S.used then SB_Log("BBS asks for start biases"); end
					S.used = true;
					local ok, res = pcall(SB_Augment, biases, civilizationType);
					if not ok then
						SB_Log("error: " .. tostring(res));
						return biases;
					end
					if res ~= nil then return res; end
					return biases;
				end
				S.mine[w] = true;
				t.__FindBias = w;
				S.seenBBS = true;
				SB_Log("BBS start bias hook installed (v" .. S.ver .. ")");
			end
		end
		local g = IsTundraCiv;
		local gInG = false;
		if g == nil and type(_G) == "table" and type(_G.IsTundraCiv) == "function" then g = _G.IsTundraCiv; gInG = true; end
		if type(g) == "function" and not S.mine[g] then
			local orig = g;
			local w = function(civilizationType)
				local r = orig(civilizationType);
				if r then return r; end
				if SB_IsDesertCiv(civilizationType) then
					if not S.desertLogged then S.desertLogged = {}; end
					if not S.desertLogged[civilizationType] then
						S.desertLogged[civilizationType] = true;
						local okK, k = pcall(SB_AllKotN, civilizationType);
						if okK and k then
							SB_Log(tostring(civilizationType) .. " is a desert civilization: King of the North from the draft places it, but no tundra handling");
						end
					end
					return r;
				end
				local ok, x = pcall(SB_AllKotN, civilizationType);
				if ok and x then
					if not S.kotnLogged then S.kotnLogged = {}; end
					if not S.kotnLogged[civilizationType] then
						S.kotnLogged[civilizationType] = true;
						SB_Log(tostring(civilizationType) .. " counts as a tundra civilization (King of the North from the draft)");
					end
					return true;
				end
				return r;
			end
			S.mine[w] = true;
			if gInG then _G.IsTundraCiv = w; else IsTundraCiv = w; end
			SB_Log("BBS_Balance IsTundraCiv hook installed");
		end
		-- BBS has asked for biases and IsTundraCiv is wrapped: nothing left to catch
		local cur = IsTundraCiv;
		if cur == nil and type(_G) == "table" then cur = _G.IsTundraCiv; end
		if S.used and type(cur) == "function" and S.mine[cur] then
			S.done = true;
			SB_Release();
			SB_Log("done, triggers removed");
		elseif not S.seenBBS and S.checks > S.budget then
			S.done = true;		-- no BBS in this context
			SB_Release();
			SB_Log("no BBS seen after " .. S.checks .. " calls, triggers removed");
		end
		S.inCheck = false;
	end

	-- a check from a trigger; the first trigger and the first few errors go to the log
	local function SB_Guarded(source)
		if S.firstTrigger == nil then
			S.firstTrigger = source;
			SB_Log("first trigger: " .. source);
		end
		local ok, err = pcall(SB_Check);
		S.inCheck = false;
		if not ok then
			S.errors = (S.errors or 0) + 1;
			if S.errors <= 3 then SB_Log("check failed: " .. tostring(err)); end
		end
	end

	-- trigger 1: print (a plain global, always replaceable)
	local okP = pcall(function()
		local origPrint = S.print;
		local w = function(...)
			if not S.done then SB_Guarded("print"); end
			return origPrint(...);
		end
		S.printWrapper = w;
		print = w;
	end);
	-- trigger 2: MapConfiguration.GetValue (BBS calls it first thing in Create)
	local okG = pcall(function()
		local origGV = MapConfiguration.GetValue;
		if origGV == nil then error("no MapConfiguration.GetValue"); end
		S.origGetValue = origGV;
		local w = function(...)
			if not S.done then SB_Guarded("MapConfiguration.GetValue"); end
			return origGV(...);
		end
		MapConfiguration.GetValue = w;
		if MapConfiguration.GetValue ~= w then error("not writable"); end
		S.gvWrapper = w;
	end);
	if not okG then S.gvWrapper = nil; end
	SB_Log("armed (print " .. tostring(okP) .. ", MapConfiguration.GetValue " .. tostring(okG) .. ")");
end
