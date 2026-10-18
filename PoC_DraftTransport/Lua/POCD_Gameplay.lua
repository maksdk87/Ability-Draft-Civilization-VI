-- POCD v27 gameplay script
-- The draft is applied by the database when the game loads (conditional actions + POCD_Apply.sql).
-- This script grants nothing. It only logs what the database gave each player.

local TAG = "[POCD][Gameplay] "
local function Log(msg) print(TAG .. tostring(msg)) end

-- rows of a database table (works for the mod's own tables too); returns list or nil + error text
local function Rows(tableName)
	local out = {}
	local ok, err = pcall(function()
		for row in GameInfo[tableName]() do table.insert(out, row) end
	end)
	if not ok then return nil, tostring(err) end
	return out
end

local function DumpDraftTables()
	for _, t in ipairs({ "POCD_SlotPicks", "POCD_Slots", "POCD_SlotCivs", "POCD_SlotItems", "POCD_AdjMoves", "POCD_Clones", "POCD_Hits" }) do
		local rows, err = Rows(t)
		if rows == nil then
			Log("table " .. t .. ": not readable (" .. tostring(err) .. ")")
		else
			local parts = {}
			for _, r in ipairs(rows) do
				table.insert(parts, tostring(r.Slot or "") .. ":" .. tostring(r.Cat and (r.Cat .. "#" .. tostring(r.Idx)) or r.LeaderType or (r.AdjacencyId and (r.AdjacencyId .. ">" .. tostring(r.CivilizationType))) or r.CivilizationType or r.ItemType or r.NewId or r.Name))
			end
			Log("table " .. t .. " (" .. #rows .. "): " .. table.concat(parts, ", "))
		end
	end
end

local function TraitsOf(tableName, keyCol, key)
	local out = {}
	for row in GameInfo[tableName]() do
		if row[keyCol] == key then table.insert(out, row.TraitType) end
	end
	table.sort(out)
	return table.concat(out, ", ")
end

-- v26: draft start biases (POCD_SlotBias, used by the BBS hook in MapEnums.lua) and where every
-- major actually started: coastal or not, river, terrain, and the map row (north/south third or middle)
function LogStarts()
	local bias = {}
	for _, r in ipairs(Rows("POCD_SlotBias") or {}) do
		local s = tonumber(r.Slot)
		if s ~= nil then
			local what = tostring(r.TargetType or r.BiasType)
			if r.Mode == "DROP" then what = "drop " .. what
			elseif r.Mode == "SET" then what = "set " .. what .. " t" .. tostring(r.Tier)
			else what = what .. " t" .. tostring(r.Tier) end
			bias[s] = (bias[s] and (bias[s] .. ", ") or "") .. what .. " (" .. tostring(r.Source) .. ")"
		end
	end
	local _, h = Map.GetGridSize()
	for _, pid in ipairs(PlayerManager.GetAliveMajorIDs()) do
		local ok, err = pcall(function()
			local cfg = PlayerConfigurations[pid]
			local plot = Players[pid]:GetStartingPlot()
			local where = "no starting plot"
			if plot ~= nil then
				local t = GameInfo.Terrains[plot:GetTerrainType()]
				local y = plot:GetY()
				local band = (y < h / 3 or y > 2 * h / 3) and "north/south third" or "middle third"
				where = string.format("start %d,%d coastal=%s river=%s %s, %s", plot:GetX(), y, tostring(plot:IsCoastalLand()),
					tostring(plot:IsRiver()), t and t.TerrainType or "?", band)
			end
			Log(string.format("player %d %s %s: %s | draft biases: %s", pid, tostring(cfg:GetLeaderTypeName()),
				tostring(cfg:GetCivilizationTypeName()), where, bias[pid] or "none"))
		end)
		if not ok then Log("start log failed for player " .. tostring(pid) .. ": " .. tostring(err)) end
	end
end

local function LogPlayers()
	for _, pid in ipairs(PlayerManager.GetAliveMajorIDs()) do
		local pPlayer = Players[pid]
		local cfg = PlayerConfigurations[pid]
		local civ, leader = cfg:GetCivilizationTypeName(), cfg:GetLeaderTypeName()
		if pPlayer:IsHuman() then
			Log(string.format("player %d HUMAN civ=%s leader=%s", pid, tostring(civ), tostring(leader)))
			Log("  leader traits: " .. TraitsOf("LeaderTraits", "LeaderType", leader))
			Log("  civ traits:    " .. TraitsOf("CivilizationTraits", "CivilizationType", civ))
			local okO, ocean = pcall(function() return GameInfo.Leaders_XP2[leader] and GameInfo.Leaders_XP2[leader].OceanStart end)
			Log("  leader OceanStart=" .. tostring(okO and ocean))
			local units = {}
			pcall(function()
				for _, u in pPlayer:GetUnits():Members() do
					local plot = Map.GetPlot(u:GetX(), u:GetY())
					table.insert(units, GameInfo.Units[u:GetType()].UnitType .. "@" .. u:GetX() .. "," .. u:GetY()
						.. (plot and plot:IsWater() and " water" or " land"))
				end
			end)
			Log("  starting units: " .. table.concat(units, ", "))
		else
			Log(string.format("player %d AI civ=%s leader=%s leader traits: %s", pid, tostring(civ), tostring(leader),
				TraitsOf("LeaderTraits", "LeaderType", leader)))
			Log("  civ traits:    " .. TraitsOf("CivilizationTraits", "CivilizationType", civ))
		end
	end
	DumpDraftTables()
	LogStarts()
	local okB, bind = pcall(GameConfiguration.GetValue, "POCD_STOCK_BIND")
	Log("stock binding setting = " .. tostring(okB and bind))
end

pcall(function()
	LuaEvents.NewGameInitialized.Add(function()
		Log("NewGameInitialized turn=" .. tostring(Game.GetCurrentGameTurn()))
		LogPlayers()
	end)
end)

Events.LoadScreenClose.Add(function()
	Log("LoadScreenClose turn=" .. tostring(Game.GetCurrentGameTurn()))
	if Game.GetCurrentGameTurn() > GameConfiguration.GetStartTurn() then LogPlayers() end
end)

-------------------------------------------------------------------------------
-- v25: log of the Korea/Maya bonus next to districts of a kind (the bonus itself is given by
-- modifiers attached to each district, POCD_Abilities.sql). For players of those
-- civilizations, at the start of every turn: each own plot with the improvement next to such
-- districts, how many of them are finished / placed, and the plot's yield. Only printed when
-- something changed. Reads the game, writes nothing.
-------------------------------------------------------------------------------
local g_adjKinds = nil		-- district index -> base district
local g_adjMoves = {}		-- { civ, improvement index, improvement, yield index, yield }
local g_adjLast = {}		-- plot index -> last printed line

local function AdjInit()
	if g_adjKinds ~= nil then return end
	g_adjKinds = {}
	for _, r in ipairs(Rows("POCD_AdjCount") or {}) do
		local d = GameInfo.Districts[r.DistrictType]
		if d ~= nil then g_adjKinds[d.Index] = r.PropertyName end
	end
	for _, r in ipairs(Rows("POCD_AdjMoves") or {}) do
		local imp, y = GameInfo.Improvements[r.ImprovementType], GameInfo.Yields[r.YieldType]
		if imp ~= nil and y ~= nil then
			table.insert(g_adjMoves, { Civ = r.CivilizationType, Imp = imp.Index, ImpName = r.ImprovementType, Yield = y.Index, YieldName = r.YieldType })
		end
	end
end

function PocdAdjLog(reason)
	AdjInit()
	if #g_adjMoves == 0 then return 0 end
	local printed = 0
	for _, pid in ipairs(PlayerManager.GetAliveMajorIDs()) do
		local cfg = PlayerConfigurations[pid]
		local pPlayer = Players[pid]
		local civ = cfg and cfg:GetCivilizationTypeName()
		if pPlayer ~= nil then
			-- districts of the kind next to each plot: finished / placed
			local done, placed = {}, {}
			for _, d in pPlayer:GetDistricts():Members() do
				if g_adjKinds[d:GetType()] ~= nil then
					for dir = 0, DirectionTypes.NUM_DIRECTION_TYPES - 1 do
						local adj = Map.GetAdjacentPlot(d:GetX(), d:GetY(), dir)
						if adj ~= nil and adj:GetOwner() == pid then
							local i = adj:GetIndex()
							placed[i] = (placed[i] or 0) + 1
							if d:IsComplete() and not d:IsPillaged() then done[i] = (done[i] or 0) + 1 end
						end
					end
				end
			end
			for i, n in pairs(placed) do
				local plot = Map.GetPlotByIndex(i)
				for _, m in ipairs(g_adjMoves) do
					if m.Civ == civ and plot ~= nil and plot:GetImprovementType() == m.Imp then
						local line = string.format("player %d plot %d,%d %s: districts finished %d / placed %d, %s = %s",
							pid, plot:GetX(), plot:GetY(), m.ImpName, done[i] or 0, n, m.YieldName, tostring(plot:GetYield(m.Yield)))
						local key = i .. "|" .. m.YieldName
						if g_adjLast[key] ~= line then
							g_adjLast[key] = line
							Log("bonus next to districts (" .. tostring(reason) .. "): " .. line)
							printed = printed + 1
						end
					end
				end
			end
		end
	end
	return printed
end

pcall(function()
	GameEvents.OnGameTurnStarted.Add(function(turn)
		local ok, err = pcall(PocdAdjLog, "turn " .. tostring(turn))
		if not ok then Log("bonus log failed: " .. tostring(err)) end
	end)
end)

Log("v27 gameplay script loaded turn=" .. tostring(Game.GetCurrentGameTurn()))
