-------------------------------------------------
-- Player Setup Logic
-------------------------------------------------
include( "InstanceManager" );
include( "GameSetupLogic" );
include( "SupportFunctions" );
include( "Civ6Common" ); --GetLeaderUniqueTraits

g_PlayerParameters = {};
local m_currentInfo = {											--m_currentInfo is a duplicate of the data which is currently selected for the local player
		CivilizationIcon = "ICON_CIVILIZATION_UNKNOWN",
		LeaderIcon = "ICON_LEADER_DEFAULT",
		CivilizationName = "LOC_RANDOM_CIVILIZATION",
		LeaderName = "LOC_RANDOM_LEADER"
	};

local m_tooltipControls = {};
local m_teamColors = {};

-------------------------------------------------------------------------------
-- Parameter Hooks
-------------------------------------------------------------------------------
function Player_ReadParameterValues(o, parameter)
	
	-- This is a bit of a hack.   First, obtain the player's type ID to see if it's -1.
	-- If not -1, then use typename.
	if(parameter.ParameterId == "PlayerLeader") then	
		local playerConfig = PlayerConfigurations[o.PlayerId];
		if(playerConfig) then

			local value = playerConfig:GetLeaderTypeID();
			if(value ~= -1) then
				value = playerConfig:GetLeaderTypeName();
			else
				local pool_id:number = playerConfig:GetLeaderRandomPoolID();
				if pool_id == LeaderRandomPoolTypes.LEADER_RANDOM_POOL_1 then
					value = "RANDOM_POOL1";
				elseif pool_id == LeaderRandomPoolTypes.LEADER_RANDOM_POOL_2 then
					value = "RANDOM_POOL2";
				else
					value = "RANDOM";
				end
			end

			return value;
		end
	else
		return SetupParameters.Config_ReadParameterValues(o, parameter);
	end
end


-------------------------------------------------------------------------------
-- POCD v20 draft lobby: helpers (lookups in the Configuration database, player values)
-------------------------------------------------------------------------------
local function PocdLog(msg)
	print("[POCD][Lobby] " .. tostring(msg));
end

local function PocdQuery(sql, ...)
	local ok, rows = pcall(DB.ConfigurationQuery, sql, ...);
	if ok and rows then return rows; end
	return {};
end

local function PocdQueryOne(sql, ...)
	local rows = PocdQuery(sql, ...);
	return rows[1];
end

local function PocdGetPlayerValue(playerConfig, key)
	if playerConfig == nil then return nil; end
	local ok, v = pcall(function() return playerConfig:GetValue(key); end);
	if ok then return v; end
	return nil;
end

-- civilization picked in the player's civilization menu (nil while random or unset)
function PocdChosenCiv(playerConfig)
	if not PocdDraftActive() then return nil; end	-- 0.1.1: a value left from a draft setup is ignored
	local civ = PocdGetPlayerValue(playerConfig, "POCD_CIV");
	if type(civ) == "string" and civ ~= "" and civ ~= "RANDOM" then return civ; end
	return nil;
end

-- Menus whose "Random" was resolved when the player readied up. The result stays secret
-- until the game starts: these menus keep showing "Random" to everybody.
-- Stored in the player's settings as letters: L C D B I U.
function PocdHiddenCats(playerConfig)
	local s = PocdGetPlayerValue(playerConfig, "POCD_HIDDEN");
	if type(s) ~= "string" then return ""; end
	return s;
end

function PocdIsHidden(playerId, cat)
	local s = PocdHiddenCats(PlayerConfigurations[playerId]);
	return s ~= "" and string.find(s, cat, 1, true) ~= nil;
end

-- civilization that may be shown for this player (nil while random or secret)
function PocdVisibleCiv(playerConfig)
	if string.find(PocdHiddenCats(playerConfig), "C", 1, true) then return nil; end
	return PocdChosenCiv(playerConfig);
end

-- the civilization menu also sets the civilization the game gives the player;
-- while it is random the leader's own civilization is shown
function PocdWriteCivConfig(o)
	local playerConfig = PlayerConfigurations[o.PlayerId];
	if playerConfig == nil then return; end
	local civ = PocdChosenCiv(playerConfig);
	if civ == nil then
		local leader = playerConfig:GetLeaderTypeName();
		if type(leader) == "string" then
			local domain = PocdGetPlayerValue(playerConfig, "LEADER_VALUE_DOMAIN") or PocdGetPlayerValue(playerConfig, "LEADER_DOMAIN");
			local r = PocdQueryOne("SELECT CivilizationType FROM Players WHERE Domain = ? AND LeaderType = ? LIMIT 1", domain, leader)
				or PocdQueryOne("SELECT CivilizationType FROM Players WHERE LeaderType = ? ORDER BY CASE Domain WHEN 'Players:Expansion2_Players' THEN 0 ELSE 1 END LIMIT 1", leader);
			civ = r and r.CivilizationType;
		end
	end
	o:Config_Write("Player", "CIVILIZATION_TYPE_NAME", civ);
	o:Config_Write("Player", "CIVILIZATION_TYPE_ID", civ and DB.MakeHash(civ) or nil);
	PocdLog("player " .. tostring(o.PlayerId) .. " civilization = " .. tostring(civ));
end

-- Leader menu filter: only leaders are unique in the draft.
-- Civilizations may repeat, so the game's duplicate-civilization mark is lifted.
-- Personas of one person are different leaders (Victoria and Victoria "Age of Steam",
-- Eleanor of England and Eleanor of France): the game's persona mark is lifted too (v23).
-- A leader held by another player is always marked as taken.
function PocdPlayer_FilterValues(o, parameter, values)
	local out = SetupParameters.Parameter_FilterValues(o, parameter, values);
	if parameter.ParameterId ~= "PlayerLeader" or type(out) ~= "table" or not PocdDraftActive() then return out; end
	local used = {};
	for _, pid in ipairs(GameConfiguration.GetParticipatingPlayerIDs()) do
		if pid ~= o.PlayerId then
			local cfg = PlayerConfigurations[pid];
			local l = cfg and cfg:GetLeaderTypeName();
			if type(l) == "string" then used[l] = true; end
		end
	end
	local result = {};
	for _, v in ipairs(out) do
		local nv = v;
		if v.Invalid and (v.InvalidReason == "LOC_SETUP_ERROR_NO_DUPLICATE_CIVILIZATIONS"
				or v.InvalidReason == "LOC_SETUP_ERROR_NO_DUPLICATE_LEADERS") then
			nv = {};
			for k, x in pairs(v) do nv[k] = x; end
			nv.Invalid = nil;
			nv.InvalidReason = nil;
		end
		if not nv.Invalid and used[nv.Value] then
			local c = {};
			for k, x in pairs(nv) do c[k] = x; end
			c.Invalid = true;
			c.InvalidReason = "LOC_SETUP_ERROR_NO_DUPLICATE_LEADERS";
			nv = c;
		end
		table.insert(result, nv);
	end
	return result;
end

function Player_WriteParameterValues(o, parameter)

	-- This is a hack.  Right now changing a player's leader requires many explicit calls in a specific order.
	-- Ultimately, this *should* be a matter of setting a single key that represents the player.
	-- This was pulled from PlayerSetupLogic.
	if(parameter.ParameterId == "PlayerLeader" and o:Config_CanWriteParameter(parameter)) then	
		local playerConfig = PlayerConfigurations[o.PlayerId];
		if(playerConfig) then
			if(parameter.Value ~= nil) then
				local value = parameter.Value.Value;
				if(value == -1 or value == "RANDOM") then
					playerConfig:SetLeaderName(nil);
					playerConfig:SetLeaderTypeName(nil);
					playerConfig:SetLeaderRandomPoolID(LeaderRandomPoolTypes.LEADER_RANDOM_POOL_DEFAULT);
				elseif(value == "RANDOM_POOL1") then
					playerConfig:SetLeaderName(nil);
					playerConfig:SetLeaderTypeName(nil);
					playerConfig:SetLeaderRandomPoolID(LeaderRandomPoolTypes.LEADER_RANDOM_POOL_1);
				elseif(value == "RANDOM_POOL2") then
					playerConfig:SetLeaderName(nil);
					playerConfig:SetLeaderTypeName(nil);
					playerConfig:SetLeaderRandomPoolID(LeaderRandomPoolTypes.LEADER_RANDOM_POOL_2);
				else
					local leaderType:string = parameter.Value.Value;

					playerConfig:SetLeaderName(parameter.Value.RawName or parameter.Value.Name);


					playerConfig:SetLeaderTypeName(leaderType);
				end
			else
				playerConfig:SetLeaderName(nil);
				playerConfig:SetLeaderTypeName(nil);
			end

			o:Config_WriteAuxParameterValues(parameter);					
			
			if not g_PocdBatchWrite then Network.BroadcastPlayerInfo(o.PlayerId); end	-- POCD: rolling randoms broadcasts once per slot
			return true;
		end
	else
		local result = SetupParameters.Config_WriteParameterValues(o, parameter);
		-- POCD: the civilization menu also sets the player's civilization
		if(result and o.PlayerId ~= nil and parameter.ParameterId == "PocdCiv") then
			PocdWriteCivConfig(o);
		end
		if(result and o.PlayerId ~= nil) then
			if not g_PocdBatchWrite then Network.BroadcastPlayerInfo(o.PlayerId); end	-- POCD: rolling randoms broadcasts once per slot
		end
		return result;
	end
end


-- The method used to create a UI control associated with the parameter.
function Player_UI_CreateParameter(o, parameter)
	-- Do nothing for now.  Player controls are explicitly instantiated in the UIs.
end


-- Called whenever a parameter is no longer relevant and should be destroyed.
function Player_UI_DestroyParameter(o, parameter)
	-- Do nothing for now.  Player controls are explicitly instantiated in the UIs.
end


-------------------------------------------------------------------------------
-- Create parameters for all players.
-------------------------------------------------------------------------------
function CreatePlayerParameters(playerId, bHeadless)
	SetupParameters_Log("Creating player parameters for Player " .. tonumber(playerId));

	-- Don't create player parameters for minor city states.  The configuration database doesn't know city state parameter values (like city state leader types) so it will stomp on them.
	local playerConfig = PlayerConfigurations[playerId];
	--if(playerConfig == nil or playerConfig:GetCivilizationLevelTypeID() ~= CivilizationLevelTypes.CIVILIZATION_LEVEL_FULL_CIV) then
	--	return nil;
	--end

	local parameters = SetupParameters.new(playerId);
	
	-- Setup hooks.
	parameters.Parameter_GetRelevant = GetRelevantParameters;
	parameters.Config_EndWrite = Parameters_Config_EndWrite;

	-- Player specific hooks.
	-- This player logic is a bit weird due to some assumptions made in the staging room.
	-- Right now player-based parameters are not dynamically generated :(
	-- Instead, the leader pulldown, optional team pulldown and optional handicap pulldown
	-- are all allocated by the UI explicitly.
	-- Team pulldown is entirely managed in the staging room =\
	-- For now, the UI logic looks for predefined controls and populates but does not generate.
	-- In the future, I hope this can be more like the GameSetup and allow for unique player parameters to be created.
	parameters.Config_ReadParameterValues = Player_ReadParameterValues;
	parameters.Config_WriteParameterValues = Player_WriteParameterValues;
	-- POCD: only leaders are unique in the draft
	parameters.Parameter_FilterValues = PocdPlayer_FilterValues;


	-- Stub out Visualization function to do nothing if headless.
	-- While the UI_ methods should no longer be called because of this, nil them out just in case.
	if(bHeadless) then
		parameters.UpdateVisualization = function() end
	end
	parameters.UI_CreateParameter = (bHeadless ~= true) and Player_UI_CreateParameter;
	parameters.UI_DestroyParameter = (bHeadless ~= true) and Player_UI_DestroyParameter;
	parameters.UI_SetParameterPossibleValues = (bHeadless ~= true) and UI_SetParameterPossibleValues;
	parameters.UI_SetParameterValue = (bHeadless ~= true) and UI_SetParameterValue;
	parameters.UI_SetParameterEnabled = (bHeadless ~= true) and UI_SetParameterEnabled;
	parameters.UI_SetParameterVisible = (bHeadless ~= true) and UI_SetParameterVisible;

	parameters:Initialize();

	-- Treat g_PlayerParameters as an array to guarantee order of operations.
	table.insert(g_PlayerParameters, {playerId, parameters});
	table.sort(g_PlayerParameters, function(a,b) 
		return a[1] < b[1];
	end);

	return parameters;
end

function GetPlayerParameters(player_id)
	for i, v in ipairs(g_PlayerParameters) do
		if(v[1] == player_id) then
			return v[2];
		end
	end
end

function RebuildPlayerParameters(bHeadless)
	g_PlayerParameters = {};

	local player_ids = GameConfiguration.GetParticipatingPlayerIDs();
	SetupParameters_Log("There are " .. #player_ids .. " participating players.");
	for i, player_id in ipairs(player_ids) do	
		CreatePlayerParameters(player_id, bHeadless);
	end
end

function RefreshPlayerParameters()
	SetupParameters_Log("Refresh Player Parameters");
	for i,v in ipairs(g_PlayerParameters) do
		v[2]:Refresh();
	end
	SetupParameters_Log("End Refresh Player Parameters");
end

function VisualizePlayerParameters()
	SetupParameters_Log("Visualizing Player Parameters");
	for i,v in ipairs(g_PlayerParameters) do
		v[2]:UpdateVisualization();
	end
	SetupParameters_Log("End Visualizing Player Parameters");
end

function ReleasePlayerParameters()
	SetupParameters_Log("Releasing Player Parameters");
	for i,v in ipairs(g_PlayerParameters) do
		v[2]:Shutdown();
	end

	g_PlayerParameters = {};
end

function GetPlayerParameterError(playerId)
	local gameState = GameConfiguration.GetGameState(); 
	local isPreGame = (gameState == GameStateTypes.GAMESTATE_PREGAME);	
	local max_unique_players = GameConfiguration.GetValue("MAX_UNIQUE_PLAYERS");
	local unique_leaders = GameConfiguration.GetValue("NO_DUPLICATE_LEADERS");
	local unique_civilizations = GameConfiguration.GetValue("NO_DUPLICATE_CIVILIZATIONS");
	local player_ids = GameConfiguration.GetParticipatingPlayerIDs();
	local player_count = 0;

	-- Only count major civs.
	for _, pid in ipairs(player_ids) do
		local pPlayerConfig = PlayerConfigurations[pid];
		if(pPlayerConfig) then
			local civLevel = pPlayerConfig:GetCivilizationLevelTypeID();
			if(civLevel == nil or civLevel == 0 or civLevel == CivilizationLevelTypes.CIVILIZATION_LEVEL_FULL_CIV) then
				player_count = player_count + 1;
			end
		end
	end

	for i, pp in ipairs(g_PlayerParameters) do
		local id = pp[1];
		if(id == playerId) then

			local p = pp[2];	
			if(p and p.Parameters) then
				-- For now, test a specific parameter.
				-- This could probably be generalized to enumerate all
				-- parameters.
				local playerLeader = p.Parameters["PlayerLeader"];
				if(playerLeader) then

					-- Only perform this check in pre-game.
					-- After a game has been made, there will be additional participants that break this check.
					if(isPreGame) then
						if(max_unique_players and (unique_leaders or unique_civilizations)) then
							if(player_count > max_unique_players) then
								print("Player Count - " .. player_count .. " Max Unique Players - " .. max_unique_players);
								return {Reason="LOC_SETUP_PLAYER_PARAMETER_ERROR"};
							end
						end
					end

					-- TTP 31558 - In multiplayer, Open and Closed slots have nil for most of their player configuration values because the slots have not been reset yet.
					-- On the client, the player setup logic will try to change the nil values to their default values and fail because the client does not have write access.
					-- This is OK and should not count as a player parameter error, which would block game start incorrectly.
					local pPlayerConfig = PlayerConfigurations[playerId];
					if(pPlayerConfig ~= nil and not pPlayerConfig:IsParticipant()) then
						return nil;
					else
						return playerLeader.Error;
					end
				end
			end
		end
	end
end

function GetGameParametersError()
	if(g_GameParameters) then
		return g_GameParameters.Error or g_GameParameters.Stalled and "Stalled";
	end
end

function CanShowLeaderAbility(playerInfo : table)
	if (playerInfo.LeaderAbilityName and playerInfo.LeaderAbilityDescription and playerInfo.LeaderAbilityIcon) then
		return playerInfo.LeaderAbilityName ~= "NONE" and playerInfo.LeaderAbilityDescription ~= "NONE" and playerInfo.LeaderAbilityIcon ~= "NONE";
	end
	return false;
end

function CanShowCivAbility(playerInfo : table)
	if (playerInfo.CivilizationAbilityName and playerInfo.CivilizationAbilityDescription and playerInfo.CivilizationAbilityIcon) then
		return playerInfo.CivilizationAbilityName ~= "NONE" and playerInfo.CivilizationAbilityDescription ~= "NONE" and playerInfo.CivilizationAbilityIcon ~= "NONE";
	end
	return false;
end    


-- NOTE: The follow contains some duplicate code from SetupParameters.
-- This code was copied to minimize any risk of side effects.
local _PlayerInfoOverridesChanges = -1;	-- DB Change counter to know when to invalidate.
local _PlayerInfoOverrides = {};		-- Player Info Overrides.
local _PlayerItemOverrides = {};		-- Player Item Overrides;

function SyncPlayerOverrides()

	-- If the cache is up-to-date, return it.
	local changes = DB.ConfigurationChanges();
	if(changes == _PlayerInfoOverridesChanges) then 
		return _PlayerInfoOverrides, _PlayerItemOverrides;
	end

	-- Cache is out of date, fetch queries and rebuild cache.
	_PlayerInfoOverrides = {};
	_PlayerItemOverrides = {};

	local Query = function(query)
		-- This is a bit of hard-coded trickery.
		-- It's to deal with how Lua handles nil values in tables..
		local args = {};

		local parameters = query.Parameters;
		if(parameters ~= nil) then
			for i = 1, 4, 1 do
				local p = parameters[i];
				if(p ~= nil) then
					if(p.ConfigurationGroup == "Player" and p.ConfigurationId == "PLAYER_ID" and self.PlayerId) then
						args[i] = self.PlayerId;
					else			
						args[i] = self:Config_Read(p.ConfigurationGroup, p.ConfigurationId);
					end
				end
			end
		end

		return CachedQuery(query.SQL, args[1], args[2], args[3], args[4]);
	end

	local CriteriaOperators = {
		["Equals"] = function(a,b) return a == b; end,
		["NotEquals"] = function(a,b) return a ~= b; end,
		["LessThan"] = function(a, b) return a < b; end,
		["LessThanEquals"] = function(a,b) return a <= b; end,
		["GreaterThan"] = function(a,b) return a > b; end,
		["GreaterThanEquals"] = function(a,b) return a >= b; end,
		["Exists"] = function(a,b) return Exists(a,b); end,
		["NotExists"] = function(a,b) return not Exists(a,b); end
	};

	local ReadConfig = function(group, id)
		if(group == "Game") then
			return GameConfiguration.GetValue(id);
		elseif(group == "Map") then
			return MapConfiguration.GetValue(id);
		elseif(group == "Player" and self.PlayerId ~= nil) then
			return PlayerConfigurations[self.PlayerId]:GetValue(id);
		end
	end

	local MeetsCriteria = function(criteria)
		if(criteria) then
			for i, v in ipairs(criteria) do
				local cmp = CriteriaOperators[v.Operator];
				if(cmp ~= nil) then
					local expected_value = v.ConfigurationValue;
					local actual_value = ReadConfig(v.ConfigurationGroup, v.ConfigurationId);

					local t = type(actual_value);
					if(t =="boolean") then

						local a = SetupParameters.Utility_ToBool(actual_value);
						local b = SetupParameters.Utility_ToBool(expected_value);
						if(not cmp(a, b)) then
							return false;
						end

					elseif(t == "number") then
						-- If expected value was a string, and the config value was a number, use the hash.
						if(type(expected_value) == "string") then
							expected_value = DB.MakeHash(expected_value);					
						end

						local a = tonumber(actual_value);
						local b = tonumber(expected_value);

						if(not cmp(a,b)) then
							return false;
						end		
					else
						if(not cmp(actual_value, expected_value)) then
							return false;
						end
					end
				else
					SetupParameters_Log("Warning! Could not find criteria operator - " .. tostring(v.Operator));
				end
			end
		end

		return true;
	end

	--Cache data.
	local queries = {};
	for i, row in ipairs(CachedQuery("SELECT * from Queries")) do
		queries[row.QueryId] = {
			Query = row
		} 
	end

	for i, row in ipairs(CachedQuery("SELECT * from QueryParameters")) do
		local query = queries[row.QueryId];
		if(query) then
			local parameters = query.Parameters;
			if(parameters == nil) then
				parameters = {};
				query.Parameters = parameters;
			end

			parameters[tonumber(row.Index)] = row;
		end
	end

	for i, row in ipairs(CachedQuery("SELECT * from QueryCriteria")) do
		local query = queries[row.QueryId];
		if(query) then
			local criteria = query.Criteria;
			if(criteria == nil) then
				criteria = {};
				query.Criteria = criteria;
			end
			table.insert(criteria, row);
		end
	end

	-- Fetch overrides from queries
	for _, row in ipairs(CachedQuery("SELECT * FROM PlayerInfoOverrideQueries")) do
		local q = queries[row.QueryId];
		if(q) then
			-- Is the query's criteria met?
			if(q.Criteria == nil or MeetsCriteria(q.Criteria)) then
				for _, v in ipairs(Query(q.Query)) do
					table.insert(_PlayerInfoOverrides, v);
				end
			end
		end
	end

	for i, row in ipairs(CachedQuery("SELECT * FROM PlayerItemOverrideQueries")) do
		local q = queries[row.QueryId];
		if(q) then
			-- Is the query's criteria met?
			if(q.Criteria == nil or MeetsCriteria(q.Criteria)) then
				for _, v in ipairs(Query(q.Query)) do
					print(v);
					table.insert(_PlayerItemOverrides, v);
				end
			end
		end
	end

	-- Sort overrides ascending by Priority.
	local sortByPriority = function(a,b) return a.Priority < b.Priority; end
	table.sort(_PlayerInfoOverrides, sortByPriority);
	table.sort(_PlayerItemOverrides, sortByPriority);

	return _PlayerInfoOverrides, _PlayerItemOverrides;
end


-- Obtain additional information about a specific player value.
-- Returns a table containing the following fields:
--	CivilizationIcon					-- The icon id representing the civilization.
--	LeaderIcon							-- The icon id representing the leader.
--	CivilizationName					-- The name of the Civilization.
--	LeaderName							-- The name of the Leader.
--	LeaderType							-- The type name of the leader (to derive the standing portrait/background images)
--  LeaderAbility = {					-- (nullable) A table containing details about the Leader's primary ability.
--		Name							-- The name of the Leader's primary ability.
--		Description						-- The description of the Leader's primary ability.
--		Icon							-- The icon of the Leader's primary ability.
--  },
--  CivilizationAbility = {				-- (nullable) A table containing details about the Civilization's primary ability.
--		Name							-- The name of the Civilization's primary ability.
--		Description						-- The description of the Civilization's primary ability.
--		Icon							-- The icon of the Civilization's primary ability.
--  },
--	Uniques = {							-- (nullable) An array of unique items.
--		{
--			Name,						-- The name of the unique item.
--			Description,				-- The description of the unique item.
--			Icon,						-- The icon of the unique item.
--		}
--	},

local _GetPlayerIconsCache = {};
local _GetPlayerIconsDefaultValue = {
	LeaderIcon = "ICON_LEADER_DEFAULT",  
	CivIcon = "ICON_CIVILIZATION_UNKNOWN"
};

function GetPlayerIcons(domain, leader_type)
	-- Kludge:  We're special casing random for now.
	-- this will eventually change and 'RANDOM' will
	-- be just another row in the players entry.
	-- This can't happen until GameCore supports 
	-- multiple 'random' pools.
	if (leader_type == "RANDOM_POOL1") then
		return {
			LeaderIcon = "ICON_LEADER_RANDOM_POOL_1",  
			CivIcon = "ICON_CIVILIZATION_UNKNOWN"
		};
	elseif (leader_type == "RANDOM_POOL2") then
		return {
			LeaderIcon = "ICON_LEADER_RANDOM_POOL_2",  
			CivIcon = "ICON_CIVILIZATION_UNKNOWN"
		};
	elseif (leader_type ~= "RANDOM") then

		-- Does the cache need to be invalidated?
		local changes = DB.ConfigurationChanges();
		if(changes ~= _GetPlayerIconsCache[1]) then
			_GetPlayerIconsCache = {changes};
		end

		-- Create single key to look up rather than use a 2D array.
		local key = domain .. "|" .. leader_type;
		local value = _GetPlayerIconsCache[key];
		if(value) then
			return value;
		else
			local info_query = "SELECT CivilizationIcon, LeaderIcon, PlayerColor from Players where Domain = ? and LeaderType = ? LIMIT 1";
			local results = CachedQuery(info_query, domain, leader_type);		
			if(results) then
				local row = results[1];

				local playerColor = row.PlayerColor or leader_type;

				local info = {
					LeaderIcon = row.LeaderIcon, 
					CivIcon = row.CivilizationIcon,
					PlayerColor = playerColor
				};
				
				-- Cache it.
				_GetPlayerIconsCache[key] = info;

				return info;
			end
		end
	end

	return _GetPlayerIconsDefaultValue;
end

function GetPlayerInfo(domain, leader_type)
	-- Kludge:  We're special casing random for now.
	-- this will eventually change and 'RANDOM' will
	-- be just another row in the players entry.
	-- This can't happen until GameCore supports 
	-- multiple 'random' pools.
	if(leader_type ~= "RANDOM" and leader_type ~= "RANDOM_POOL1" and leader_type ~= "RANDOM_POOL2") then
		local info_query = "SELECT CivilizationIcon, LeaderIcon, LeaderName, CivilizationName, LeaderAbilityName, LeaderAbilityDescription, LeaderAbilityIcon, CivilizationAbilityName, CivilizationAbilityDescription, CivilizationAbilityIcon, Portrait, PortraitBackground, PlayerColor from Players where Domain = ? and LeaderType = ? LIMIT 1";
		local item_query = "SELECT Type, Name, Description, Icon, SortIndex from PlayerItems where Domain = ? and LeaderType = ?";
		local info_results = CachedQuery(info_query, domain, leader_type);
		local item_results = CachedQuery(item_query, domain, leader_type);

		-- Gather override data.
		local playerInfoOverrides, playerItemOverrides = SyncPlayerOverrides();

		-- Since there are many player items, reduce the list by filtering domain and leader item override matches.
		local filteredItems = {};
		for i,v in ipairs(playerItemOverrides) do
			if(v.Domain == domain and v.LeaderType == leader_type) then
				table.insert(filteredItems, v);
			end
		end
		
		if(info_results and item_results) then
			local info = {};
			info.LeaderType = leader_type;

			local abilities = {};
			for i,row in ipairs(info_results) do
				
				info.PlayerColor = row.PlayerColor or leader_type;
				info.CivilizationIcon= row.CivilizationIcon;
				info.LeaderIcon= row.LeaderIcon;
				info.LeaderName = row.LeaderName;
				info.CivilizationName = row.CivilizationName;
				info.Portrait = row.Portrait;
				info.PortraitBackground = row.PortraitBackground;

				abilities.LeaderAbilityName = row.LeaderAbilityName;
				abilities.LeaderAbilityDescription = row.LeaderAbilityDescription;
				abilities.LeaderAbilityIcon = row.LeaderAbilityIcon;

				abilities.CivilizationAbilityName = row.CivilizationAbilityName;
				abilities.CivilizationAbilityDescription = row.CivilizationAbilityDescription;
				abilities.CivilizationAbilityIcon = row.CivilizationAbilityIcon;
			end

			-- Apply any overrides.
			for i,v in ipairs(playerInfoOverrides) do
				if(v.Domain == domain and v.LeaderType == leader_type) then
					if(v.CivilizationAbilityName) then abilities.CivilizationAbilityName = v.CivilizationAbilityName; end
					if(v.CivilizationAbilityDescription) then abilities.CivilizationAbilityDescription = v.CivilizationAbilityDescription; end
					if(v.CivilizationAbilityIcon) then abilities.CivilizationAbilityIcon = v.CivilizationAbilityIcon; end
					if(v.LeaderAbilityName) then abilities.LeaderAbilityName = v.LeaderAbilityName; end
					if(v.LeaderAbilityDescription) then abilities.LeaderAbilityDescription = v.LeaderAbilityDescription; end
					if(v.LeaderAbilityIcon) then abilities.LeaderAbilityIcon = v.LeaderAbilityIcon; end
				end
			end

			-- Check whether abilities can be shown *after* overrides have been applied.
			if (CanShowLeaderAbility(abilities)) then
				info.LeaderAbility = {
					Name = abilities.LeaderAbilityName,
					Description = abilities.LeaderAbilityDescription,
					Icon = abilities.LeaderAbilityIcon
				};
			end

			if (CanShowCivAbility(abilities)) then
				info.CivilizationAbility = {
					Name = abilities.CivilizationAbilityName,
					Description = abilities.CivilizationAbilityDescription,
					Icon = abilities.CivilizationAbilityIcon
				};
			end

			-- Generate a list of unique items while overriding.
			local uniques = {};
			for i,row in ipairs(item_results) do
				uniques[row.Type] = {
					Name = row.Name,
					Description = row.Description,
					Icon = row.Icon,
					SortIndex = row.SortIndex,
					ShouldRemove = false
				};
			end

			for i,v in ipairs(filteredItems) do
				local u = uniques[v.Type];
				if(u == nil) then
					u = {
						SortIndex = 0,
						ShouldRemove = false
					};
					uniques[v.Type] = u;
				end

				if(v.Name) then u.Name = v.Name end
				if(v.Description) then u.Description = v.Description; end
				if(v.Icon) then u.Icon = v.Icon; end
				if(v.SortIndex ~= nil) then u.SortIndex = v.SortIndex; end
				if(v.ShouldRemove ~= nil) then u.ShouldRemove = v.ShouldRemove; end
			end


			-- Validate and populate unique items.
			info.Uniques = {};
			for k,v in pairs(uniques) do
				if(v.ShouldRemove == false and v.Name and v.Name ~= "NONE" and v.Description and v.Description ~= "NONE" and v.Icon) then
					table.insert(info.Uniques, {
						Name = v.Name,
						Description = v.Description,
						Icon = v.Icon,
						SortIndex = v.SortIndex;
					})
				end
			end

			-- Ensure unique items are in the correct order.
			table.sort(info.Uniques, function(a,b) return a.SortIndex < b.SortIndex; end);

			return info;
		end
	end

	return {
		CivilizationIcon = "ICON_CIVILIZATION_UNKNOWN",
		LeaderIcon = "ICON_LEADER_DEFAULT",
		CivilizationName = "LOC_RANDOM_CIVILIZATION",
		LeaderName = "LOC_RANDOM_LEADER",
		LeaderType = leader_type,
	};
end

function GenerateToolTipFromPlayerInfo(info)
	local lines = {};
	table.insert(lines, Locale.Lookup(info.LeaderName));
	table.insert(lines, Locale.Lookup(info.CivilizationName));
	if(info.CivilizationAbility) then
		local ability = info.CivilizationAbility;
		table.insert(lines, "--------------------------------");
		table.insert(lines, Locale.Lookup(ability.Name));
		table.insert(lines, Locale.Lookup(ability.Description));
	end

	if(info.LeaderAbility) then
		local ability = info.LeaderAbility;
		table.insert(lines, "--------------------------------");
		table.insert(lines, Locale.Lookup(ability.Name));
		table.insert(lines, Locale.Lookup(ability.Description));
	end

	if(info.Uniques and #info.Uniques > 0) then
		table.insert(lines, "--------------------------------");
		for i,v in ipairs(info.Uniques) do
			table.insert(lines, Locale.Lookup(v.Name));
			table.insert(lines, Locale.Lookup(v.Description) .. "[NEWLINE]");

		end
	end
	
	return table.concat(lines, "[NEWLINE]");
end

-- ===========================================================================
--	Correctly displays a special flyout for the leader selection dropdown.
--	info:				The leader and civ info that we will use to set the data
--	tooltipControls:	All of the data required for generating the tooltip.  Includes:
--							InfoStack			table	- The primary stack which holds all the data for the panel
--							InfoScrollPanel		table	- The scrollpanel for the flyout
--							UniqueIconIM		table	- Instance manager for the unique civ abilities/units
--							HeaderIconIM		table	- Instance manager for the header icon (has a different backing)
--							HeaderIM			table	- Instance manager for the headers 
--							CivToolTipSlide		table	- Flyout animation slide
--							CivToolTipAlpha		table	- Flyout animation alpha
--							HasLeaderPlacard	boolean - Indicates whether or not this tooltip should also display the leader placard flyout
--							LeaderBG			table	- The background image displayed behind the leader
--							LeaderImage			table	- The leader image
--							DummyImage			table	- This dummy image is used so that we can calculate the ratio of the original leader image.  
--														  We use this to determine how to position the leader within the placard.
--							CivLeaderSlide		table	- Flyout leader placard slide
--							CivLeaderAlpha		table	- Flyout leader placard alpha
--						<< This data is passed from the contexts where we pick leaders - AdvancedSetup and StagingRoom >>
--	alwaysHide:			A boolean indicating that we should always hide both flyouts.  The "Random" leader selection will always be hidden for example
-- ===========================================================================
function DisplayCivLeaderToolTip(info:table, tooltipControls:table, alwaysHide:boolean)

	function ShowControl(alpha, slide)
		if(alpha and slide) then
			if (alpha:IsReversing()) then
				alpha:Reverse();
				slide:Reverse();
			else
				alpha:Play();
				slide:Play();
			end
		end
	end

	function HideControl(alpha, slide) 
		if(alpha and slide) then
			if (not alpha:IsReversing()) then
				alpha:Reverse();
				slide:Reverse();
			else
				alpha:Play();
				slide:Play();
			end
		end
	end

	local showLeaderPortrait = false;
	local showToolTip = false;
	if(not alwaysHide and info.CivilizationName ~= "LOC_RANDOM_CIVILIZATION") then --If we are showing leader data flyouts, then make sure we are playing forwards, and play until shown
		showLeaderPortrait, showToolTip = SetUniqueCivLeaderData(info, tooltipControls);
	end

	if(showLeaderPortrait) then
		ShowControl(tooltipControls.CivLeaderAlpha, tooltipControls.CivLeaderSlide);
	else
		HideControl(tooltipControls.CivLeaderAlpha, tooltipControls.CivLeaderSlide);	
	end

	if(showToolTip) then
		ShowControl(tooltipControls.CivToolTipAlpha, tooltipControls.CivToolTipSlide);
	else
		HideControl(tooltipControls.CivToolTipAlpha, tooltipControls.CivToolTipSlide);	
	end
end

-- ===========================================================================
function UpdateCivLeaderToolTip()
	if m_currentInfo.LeaderType ~= nil then
		SetUniqueCivLeaderData(m_currentInfo, m_tooltipControls);
	end
end

-- ===========================================================================
--	Sets all of the data for the Unique Civilization/Leader flyout and sizes the controls accordingly
--	info				The leader and civ info that we will use to set the data
--	tooltipControls		The controls that the info data will be attached to
-- ===========================================================================
function SetUniqueCivLeaderData(info:table, tooltipControls:table)

	local hasLeaderPlacard = false;
	local hasTooltipInfo = false;

	tooltipControls.HeaderIconIM:ResetInstances();
	tooltipControls.UniqueIconIM:ResetInstances();
	tooltipControls.HeaderIM:ResetInstances();
	tooltipControls.CivHeaderIconIM:ResetInstances();

	-- Check to make sure this player panel has the leader placard
	if tooltipControls.HasLeaderPlacard then
		-- Unload leader textures
		tooltipControls.LeaderImage:UnloadTexture();
		tooltipControls.LeaderBG:UnloadTexture();
		tooltipControls.DummyImage:UnloadTexture();

		-- Set leader placard
		local leaderPortrait:string;
		if info.Portrait then
			leaderPortrait = info.Portrait;
		else
			leaderPortrait = info.LeaderType .. "_NEUTRAL";
		end
	
		tooltipControls.DummyImage:SetTexture(leaderPortrait);
		tooltipControls.LeaderImage:SetTexture(leaderPortrait);
		local imageRatio = tooltipControls.DummyImage:GetSizeX()/tooltipControls.DummyImage:GetSizeY();
		if(imageRatio > .51) then
 			tooltipControls.LeaderImage:SetTextureOffsetVal(30,10)
		else
			tooltipControls.LeaderImage:SetTextureOffsetVal(10,50)
		end

		local leaderBGImage:string;
		if info.PortraitBackground then
			leaderBGImage = info.PortraitBackground;
		else
			leaderBGImage = info.LeaderType .. "_BACKGROUND";
		end
		tooltipControls.LeaderBG:SetTexture(leaderBGImage);
		hasLeaderPlacard = true;
	end

	-- Set Leader unique data
	if (info.LeaderAbility) then
		local leaderHeader = tooltipControls.HeaderIM:GetInstance();
		leaderHeader.Header:SetText(Locale.ToUpper(Locale.Lookup(info.LeaderName)));
		local leaderAbility = tooltipControls.HeaderIconIM:GetInstance();
		leaderAbility.Icon:SetIcon(info.LeaderIcon);
		leaderAbility.Header:SetText(Locale.ToUpper(Locale.Lookup(info.LeaderAbility.Name)));
		leaderAbility.Description:LocalizeAndSetText(info.LeaderAbility.Description);
		hasTooltipInfo = true;	-- POCD: the leader flyout shows only the leader ability
	end
	
	-- Set Civ unique data
	if (info.CivilizationAbility) then
		local civHeader = tooltipControls.HeaderIM:GetInstance();
		civHeader.Header:SetText(Locale.ToUpper(Locale.Lookup(info.CivilizationName)));
		local civAbility = tooltipControls.CivHeaderIconIM:GetInstance();

		civAbility.Icon:SetIcon(info.CivilizationIcon);

		local backColor, frontColor = UI.GetPlayerColorValues(info.PlayerColor, info.PlayerColorIndex or 0);
		if(backColor and frontColor and backColor ~= 0 and frontColor ~= 0) then
			civAbility.Icon:SetColor(frontColor);
			civAbility.IconBG:SetColor(backColor);
		end


		civAbility.Header:SetText(Locale.ToUpper(Locale.Lookup(info.CivilizationAbility.Name)));
		civAbility.Description:LocalizeAndSetText(info.CivilizationAbility.Description);
		hasTooltipInfo = true;
	end

	-- Set Civ unique units data
	if (info.Uniques) then
		for _, item in ipairs(info.Uniques) do
			local instance:table = {};
			instance = tooltipControls.UniqueIconIM:GetInstance();
			instance.Icon:SetIcon(item.Icon);
			local headerText:string = Locale.ToUpper(Locale.Lookup( item.Name ));
			instance.Header:SetText( headerText );
			instance.Description:SetText(Locale.Lookup(item.Description));
			hasTooltipInfo = true;
		end
	end

	tooltipControls.InfoStack:CalculateSize();
	tooltipControls.InfoStack:ReprocessAnchoring();
	tooltipControls.InfoScrollPanel:CalculateSize();

	return hasLeaderPlacard, hasTooltipInfo;
end

-- Checks external conditions where this player parameter should be disabled.
function CheckExternalEnabled(playerID:number, inputEnabled:boolean, lockCheck:boolean, parameter)
	-- Early out if the input enabled status is already disabled.
	if(not inputEnabled) then
		return false;
	end

	-- Just use inputEnabled if this is singleplayer. 
	if(not GameConfiguration.IsAnyMultiplayer()) then
		return inputEnabled;
	end

	local pPlayerConfig = PlayerConfigurations[playerID];
	
	-- Disable if player has readied up.
	if(pPlayerConfig:GetReady()) then
		return false;
	end

	-- Disable if the game is already in progress.
	local gameInProgress:boolean = GameConfiguration.GetGameState() ~= GameStateTypes.GAMESTATE_PREGAME;
	if(gameInProgress) then
		return false;
	end

	-- Disable if the local player doesn't have control over this player slot.
	local localPlayerID = Network.GetLocalPlayerID();
	local localPlayerConfig = PlayerConfigurations[localPlayerID];
	local slotStatus = pPlayerConfig:GetSlotStatus();
	if(not GameConfiguration.IsHotseat() -- local player can change everything in hotseat.
		and playerID ~= localPlayerID -- local player always has control of themselves.
		-- Game host can alter all the non-human slots if the host is not ready.
		and (not Network.IsGameHost()
			or slotStatus == SlotStatus.SS_TAKEN
			or localPlayerConfig:GetReady())) then
		return false;
	end

	-- Disable HandicapTypeID if matchmaking
	if(GameConfiguration.IsMatchMaking() 
		and parameter ~= nil 
		and parameter.ParameterId == "PlayerDifficulty") then
		return false; 
	end

	if(lockCheck and pPlayerConfig:IsLocked()) then
		return false;
	end

	return true;
end

-------------------------------------------------------------------------------
-- Setup Player Interface
-- This gets or creates player parameters for a given player id.
-- It then appends a driver to the setup parameter to control a visual 
-- representation of the parameter
-------------------------------------------------------------------------------
function SetupLeaderPulldown(
	playerId:number, 
	instance:table, 
	pulldownControlName:string, 
	civIconControlName, 
	civIconBGControlName, 
	leaderIconControlName,
	scrollTextControlName, 
	tooltipControls:table,
	colorPullDownName,
	colorWarnName	
)
	local parameters = GetPlayerParameters(playerId);
	if(parameters == nil) then
		parameters = CreatePlayerParameters(playerId);
	end

	-- Need to save our master tooltip controls so that we can update them if we hop into advanced setup and then go back to basic setup
	if (tooltipControls.HasLeaderPlacard) then
		m_tooltipControls = {};
		m_tooltipControls = tooltipControls;
	end

	-- Defaults
	if(civIconControlName == nil) then
		civIconControlName = "CivIcon";
	end

	if(civIconBGControlName == nil) then
		civIconBGControlName = "CivIconBG";
	end

	if(leaderIconControlName == nil) then
		leaderIconControlName = "LeaderIcon";
	end

	if(scrollTextControlName == nil) then
		scrollTextControlName = "ScrollText";
	end
		
	local control = instance[pulldownControlName];
	local civIcon = instance[civIconControlName];
	local civIconBG = instance[civIconBGControlName];
	local leaderIcon = instance[leaderIconControlName];
	local scrollText = instance[scrollTextControlName];
	local instanceManager = control["InstanceManager"];
	
	-- Jersey support
	colorPullDownName = colorPullDownName or "ColorPullDown";
	colorWarnName = colorWarnName or "WarnIcon";
	
	local colorControls;
	local colorControl = instance[colorPullDownName];
	local colorWarnIcon = instance[colorWarnName];
	local colorInstanceManager;
	if(colorControl) then
		colorInstanceManager = colorControl["InstanceManager"]	
		if (colorInstanceManager == nil) then
			colorInstanceManager = PullDownInstanceManager:new( "InstanceOne", "Button", colorControl );
			colorControl["InstanceManager"] = colorInstanceManager;
		end

		if(colorInstanceManager) then
			colorControls = parameters.Controls["PlayerColorAlternate"];
			if(colorControls == nil) then
				colorControls = {};
				parameters.Controls["PlayerColorAlternate"] = colorControls;
			end
		end
	end

	if(colorControl) then
		colorControl:SetDisabled(true);
	end

	if(colorWarnIcon) then
		colorWarnIcon:SetHide(true);
	end
	
	if not instanceManager then
		instanceManager = PullDownInstanceManager:new( "InstanceOne", "Button", control );
		control["InstanceManager"] = instanceManager;
	end

	local controls = parameters.Controls["PlayerLeader"];
	if(controls == nil) then
		controls = {};
		parameters.Controls["PlayerLeader"] = controls;
	end

	m_currentInfo = {										
		CivilizationIcon = "ICON_CIVILIZATION_UNKNOWN",
		LeaderIcon = "ICON_LEADER_DEFAULT",
		CivilizationName = "LOC_RANDOM_CIVILIZATION",
		LeaderName = "LOC_RANDOM_LEADER"
	};
	
	local useJerseySelection = (colorControls ~= nil);


	-- Utility function to test setup parameter values for equality.
	function ValuesMatch(a,b)
		local at = type(a);
		local bt = type(b);

		if(at ~= bt) then
			return false;
		elseif(at == "number") then
			return a == b;
		elseif(at == "table") then
			return a.QueryId == b.QueryId and a.QueryIndex == b.QueryIndex and a.Invalid == b.Invalid and a.InvalidReason == b.InvalidReason
		else
			return a == b;
		end
	end
		
	local cache = {};
	if(useJerseySelection) then
		table.insert(colorControls, {
			UpdateValue = function(v)
				local refresh = true;

				local leaderParameter = parameters.Parameters["PlayerLeader"];
				local colorIndex = v or 0;
				if(	leaderParameter and ValuesMatch(leaderParameter.Value, cache.PlayerValue) and
					ValuesMatch(colorIndex, cache.PlayerColorValue)) then
					refresh = false;
				end

				if(refresh) then
					local button = control:GetButton();
									
					local icons;
					if(leaderParameter.Value) then
						icons = GetPlayerIcons(leaderParameter.Value.Domain, leaderParameter.Value.Value);
					end

					local backColor, frontColor = UI.GetPlayerColorValues(icons.PlayerColor, colorIndex);		
					m_teamColors[playerId] = {backColor, frontColor}
					if(backColor and frontColor and backColor ~= 0 and frontColor ~= 0) then
						civIcon:SetSizeVal(36,36);
						civIcon:SetIcon(icons.CivIcon);
        				civIcon:SetColor(frontColor);
						civIconBG:SetColor(backColor);
						civIconBG:SetHide(false);
					else
						civIcon:SetSizeVal(45,45);
						civIcon:SetIcon(icons.CivIcon, 45);
        				civIcon:SetColor(UI.GetColorValue(1,1,1,1));
						civIconBG:SetHide(true);
					end

					cache.PlayerColorValue = pcv;
				end				
			end,
			UpdateValues = function(values, parameter)

				local leaderParameter = parameters.Parameters["PlayerLeader"];
				if(	leaderParameter and ValuesMatch(leaderParameter.Value, cache.PlayerValue)) then
					refresh = false;
				end
				
				local icons;
				if(leaderParameter.Value) then
					icons = GetPlayerIcons(leaderParameter.Value.Domain, leaderParameter.Value.Value);
				end
				
				local itemCount = 0;
				colorInstanceManager:ResetInstances();

				if(icons) then
					for j = 0, 3, 1 do					
						local backColor, frontColor = UI.GetPlayerColorValues(icons.PlayerColor, j);
						if(backColor and frontColor and backColor ~= 0 and frontColor ~= 0) then
							local colorEntry = colorInstanceManager:GetInstance();
							itemCount = itemCount + 1;
	
							colorEntry.CivIcon:SetIcon(icons.CivIcon);
							colorEntry.CivIcon:SetColor(frontColor);
							colorEntry.CivIconBG:SetColor(backColor);
							colorEntry.Button:SetToolTipString(nil);
							colorEntry.Button:RegisterCallback(Mouse.eLClick, function()
								if(playerId == 0 and m_currentInfo) then
									m_currentInfo.PlayerColorIndex = j;
								end
								parameters:SetParameterValue(parameter, j);
								m_teamColors[playerId] = {backColor, frontColor}
							end);
						end           
					end
				end

				colorControl:CalculateInternals();

				local notExternalEnabled = not CheckExternalEnabled(playerId, true, true, parameter);
				local singleOrEmpty = itemCount == 0 or itemCount == 1;

				colorControl:SetDisabled(notExternalEnabled or singleOrEmpty);

				if colorWarnIcon ~= nil then
					local myTeam = m_teamColors[playerId];
					local bShowWarning = false;
					for k,v in pairs(m_teamColors) do
						if(k ~= playerId) then
							 if( myTeam and v and UI.ArePlayerColorsConflicting( v, myTeam ) ) then
								bShowWarning = true;
							end
						end
					end
					colorWarnIcon:SetHide(not bShowWarning);
					if bShowWarning == true then
						colorWarnIcon:LocalizeAndSetToolTip("LOC_SETUP_PLAYER_COLOR_COLLISION");
					else
						colorWarnIcon:SetToolTipString(nil);
					end
				end
			end,
			SetEnabled = function(enabled, parameter)
				local notExternalEnabled = not CheckExternalEnabled(playerId, enabled, true, parameter);
				--local singleOrEmpty = #parameter.Values <= 1;
				--colorControl:SetDisabled(notExternalEnabled or singleOrEmpty);
			end
		});
	end

	table.insert(controls, {
		UpdateValue = function(v)
			local refresh = true;

			local leaderParameter = parameters.Parameters["PlayerLeader"];
			local colorParameter = parameters.Parameters["PlayerColorAlternate"];
			local colorIndex = colorParameter and colorParameter.Value or 0;

			-- Compare PlayerValue (value) and PlayerColorValues (int) w/ cache.
			if(	ValuesMatch(leaderParameter.Value, cache.PlayerValue) and
				ValuesMatch(colorIndex, cache.PlayerColorValue)) then
				refresh = false;
			end

			-- If this is player 0, update the placard.
			if(playerId == 0) then
				local info = GetPlayerInfo(v.Domain, v.Value); 
				info.PlayerColorIndex = colorIndex;
				
				m_currentInfo = info;
			end

			if(refresh) then
				local button = control:GetButton();

				if(v == nil) then
					button:LocalizeAndSetText("LOC_SETUP_ERROR_INVALID_OPTION");
					button:ClearCallback(Mouse.eMouseEnter);
					button:ClearCallback(Mouse.eMouseExit);
				else
					local caption = v.Name;
					if(v.Invalid) then
						local err = v.InvalidReason or "LOC_SETUP_ERROR_INVALID_OPTION";
						caption = caption .. "[NEWLINE][COLOR_RED](" .. Locale.Lookup(err) .. ")[ENDCOLOR]";
					end

					if scrollText then 
						scrollText:SetText(caption);
					else
						button:SetText(caption);
					end
			
					local icons = GetPlayerIcons(v.Domain, v.Value);

					local backColor, frontColor = UI.GetPlayerColorValues(icons.PlayerColor, colorIndex);
					m_teamColors[playerId] = {backColor, frontColor}
					if(backColor and frontColor and backColor ~= 0 and frontColor ~= 0) then
						civIcon:SetSizeVal(36,36);
						civIcon:SetIcon(icons.CivIcon);
        				civIcon:SetColor(frontColor);
						civIconBG:SetColor(backColor);
						civIconBG:SetHide(false);
					else
						civIcon:SetSizeVal(45,45);
						civIcon:SetIcon(icons.CivIcon, 45);
        				civIcon:SetColor(UI.GetColorValue(1,1,1,1));
						civIconBG:SetHide(true);
					end
										
					if(leaderIcon) then
						leaderIcon:SetIcon(icons.LeaderIcon);
					end

					if(not tooltipControls.HasLeaderPlacard) then
						local domain = v.Domain;
						local value = v.Value;
						button:RegisterCallback( Mouse.eMouseEnter, function() 
							local info = GetPlayerInfo(domain, value);
							info.PlayerColorIndex = colorIndex;
							DisplayCivLeaderToolTip(info, tooltipControls, false); 
						end);
						button:RegisterCallback( Mouse.eMouseExit, function() 
							DisplayCivLeaderToolTip(nil, tooltipControls, true); 
						end);
					end

					cache.PlayerValue = v;
					cache.PlayerColorValue = colorIndex;
				end		
			end
		end,
		UpdateValues = function(values)

			local refresh = false;
			local cValues = cache.PlayerValues;
			if(cValues and #cValues == #values) then
				for i,v in ipairs(values) do
					local cv = cValues[i];
					if(not ValuesMatch(cv,v)) then
						refresh = true;
						break;
					end
				end
			else
				refresh = true;
			end

			if(refresh) then
				instanceManager:ResetInstances();

				-- Avoid creating call back for each value.
				local hasPlacard = tooltipControls.HasLeaderPlacard;
				local OnMouseExit = function()
					DisplayCivLeaderToolTip(m_currentInfo, tooltipControls, not hasPlacard);
				end;

				for i,v in ipairs(values) do
					
					local icons = GetPlayerIcons(v.Domain, v.Value);

					local entry = instanceManager:GetInstance();
				
					local caption = v.Name;
					if(v.Invalid) then 
						local err = v.InvalidReason or "LOC_SETUP_ERROR_INVALID_OPTION";
						caption = caption .. "[NEWLINE][COLOR_RED](" .. Locale.Lookup(err) .. ")[ENDCOLOR]";
					end

					local backColor, frontColor = UI.GetPlayerColorValues(icons.PlayerColor, 0);
					if(backColor and frontColor and backColor ~= 0 and frontColor ~= 0) then
						entry.CivIcon:SetSizeVal(36,36);
						entry.CivIcon:SetIcon(icons.CivIcon);
        				entry.CivIcon:SetColor(frontColor);
						entry.CivIconBG:SetColor(backColor);
						entry.CivIconBG:SetHide(false);
					else
						entry.CivIcon:SetSizeVal(45,45);
						entry.CivIcon:SetIcon(icons.CivIcon, 45);
        				entry.CivIcon:SetColor(UI.GetColorValue(1,1,1,1));
						entry.CivIconBG:SetHide(true);
					end
					if(entry.ScrollText ~= nil) then
						entry.ScrollText:SetText(caption);
					else
						entry.Button:SetText(caption);
					end
					entry.LeaderIcon:SetIcon(icons.LeaderIcon);

					local domain = v.Domain;
					local value = v.Value;

					entry.Button:RegisterCallback( Mouse.eMouseEnter, function() 
						local info = GetPlayerInfo(domain, value);
						DisplayCivLeaderToolTip(info, tooltipControls, false); 
					end);

					entry.Button:RegisterCallback( Mouse.eMouseExit, OnMouseExit);
					entry.Button:SetToolTipString(nil);			

					entry.Button:RegisterCallback(Mouse.eLClick, function()
						local parameter = parameters.Parameters["PlayerLeader"];
						parameters:SetParameterValue(parameter, v);

						-- Reset Jersey Color
						-- TODO: Ideally, this should try to select a jersey that doesn't conflict.
						local colorParameter = parameters.Parameters["PlayerColorAlternate"];
						if(colorParameter) then
							parameters:SetParameterValue(colorParameter, 0);
						end

					end);
				end
				control:CalculateInternals();
				cache.PlayerValues = values;
			end
		end,
		SetEnabled = function(enabled, parameter)
			local notExternalEnabled = not CheckExternalEnabled(playerId, enabled, true, parameter);
			local singleOrEmpty = #parameter.Values <= 1;

			control:SetDisabled(notExternalEnabled or singleOrEmpty);
		end,
	--	SetVisible = function(visible)
	--		control:SetHide(not visible);
	--	end
	});
end

function SetupHandicapPulldown(playerId, control)
	local parameters = GetPlayerParameters(playerId);
	if(parameters == nil) then
		parameters = CreatePlayerParameters(playerId);
	end

	parameters.Controls["PlayerDifficulty"] = {
		UpdateValue = function(value)
			local button = control:GetButton();
			button:SetText( value and value.Name or nil);
		end,
		UpdateValues = function(values)
			control:ClearEntries();
			for i,v in ipairs(values) do
				local entry = {};
				control:BuildEntry( "InstanceOne", entry );
				entry.Button:SetText(v.Name);
				entry.Button:SetToolTipString(v.Description);			
				entry.Button:RegisterCallback(Mouse.eLClick, function()
					local parameter = parameters.Parameters["PlayerDifficulty"];
					parameters:SetParameterValue(parameter, v);
				end);
			end
			control:CalculateInternals();
		end,
		SetEnabled = function(enabled, parameter)
			control:SetDisabled(not CheckExternalEnabled(playerId, enabled, false, parameter));
		end,
	};
end

function PlayerConfigurationValuesToUI(playerId)
	local parameters = GetPlayerParameters(playerId);
	if(parameters == nil) then
		parameters = CreatePlayerParameters(playerId);
	end

	GameSetup_RefreshPlayerParameter(playerId);
end

function UpdatePlayerEntry(playerId)
	GameSetup_RefreshPlayerParameter(playerId);
end

-- This event listener may be called during the act of refreshing parameters.
-- This commonly happens if the setup parameters need to update default values.
-- When this happens, simply mark that we need to do an additional refresh afterwards.
g_Refreshing = false;
g_NeedsAdditionalRefresh = false;
g_RefreshCounter = 0;
MAX_REFRESH_DEPTH = 10;

function GameSetup_RefreshParameters()
	if(g_Refreshing) then
		SetupParameters_Log("An additional refresh was requested!");
		g_NeedsAdditionalRefresh = true;
	else
		g_Refreshing = true;
		g_RefreshCounter = g_RefreshCounter + 1;
		g_NeedsAdditionalRefresh = false;

		-- Hang protection.
		-- If we loop too many times, just mark any parameters that still need to be written 
		-- as errors and bail.
		if(g_RefreshCounter > MAX_REFRESH_DEPTH) then
			SetupParameters_Log("Refreshed too many times! Setting error state and skipping to prevent hang.");
			g_RefreshCounter = 0;
			g_Refreshing = false;	
			g_GameParameters.Stalled = true;

			g_GameParameters:UpdateVisualization();
			VisualizePlayerParameters();

			if(UI_PostRefreshParameters) then
				UI_PostRefreshParameters();
			end
		else
			SetupParameters_Log("Refreshing Game parameters");
			if(g_GameParameters == nil) then
				BuildGameSetup();
			else
				g_GameParameters:Refresh();
			end
		
			SetupParameters_Log("Refreshing Player parameters");
			RefreshPlayerParameters();
		
			g_GameParameters.Stalled = nil;
			g_Refreshing = false;

			if(g_NeedsAdditionalRefresh) then
				SetupParameters_Log("Refreshing parameters again due to an intermediate request.")
				return GameSetup_RefreshParameters();
			else
				SetupParameters_Log("Finished Refreshing");
				SetupParameters_Log("Visualizing parameters"); 
				g_RefreshCounter = 0;

				g_GameParameters:UpdateVisualization();
				VisualizePlayerParameters();

				if(UI_PostRefreshParameters) then
					UI_PostRefreshParameters();
				end
			end
		end
	end
end

function GameSetup_RefreshPlayerParameter(playerId)
	SetupParameters_Log("Refreshing parameters for player " .. tostring(playerId));
	local parameters = GetPlayerParameters(playerId);
	if(parameters) then

		g_Refreshing = true;
		parameters:Refresh();
		g_Refreshing = false;

		if(g_NeedsAdditionalRefresh) then
			SetupParameters_Log("Refreshing all parameters, to be sure.")
			return GameSetup_RefreshParameters();
		else
			parameters:UpdateVisualization();
		end
	else
		SetupParameters_Log("Player parameters not found!");
	end
end

function GameSetup_ConfigurationChanged()
	SetupParameters_Log("Configuration Changed!");
	GameSetup_RefreshParameters();
end

-------------------------------------------------------------------------------
-- POCD v20 draft lobby
-- Six menus per player: the game's own leader setting (PlayerLeader) and five player
-- settings added by the mod (POCD_CIV, POCD_UD, POCD_UB, POCD_UI, POCD_UU).
-- Each player changes only their own menus (the host also the AI ones); the game
-- sends the values to everybody. Right before the game starts the host turns them into
-- bits in the game settings (POCD_S<slot>_<cat>_B<bit>), which the conditional database
-- actions read at load. The staging room draws the menus (UI/StagingRoom.lua).
-------------------------------------------------------------------------------

function PocdLobbyLog(msg)
	PocdLog(msg);
end

-- civilization picked by the player who holds this leader (leaders are unique in the draft)
function PocdCivForLeader(leader_type)
	if leader_type == nil then return nil, nil; end
	local civ, holder = nil, nil;
	pcall(function()
		for _, pid in ipairs(GameConfiguration.GetParticipatingPlayerIDs()) do
			local cfg = PlayerConfigurations[pid];
			if holder == nil and cfg ~= nil and cfg:GetLeaderTypeName() == leader_type then
				holder = cfg;
				civ = PocdChosenCiv(cfg);
			end
		end
	end);
	return civ, holder;
end

-- the game gives the player the picked civilization (the leader's own one while random)
local PocdBase_GetPlayerCivilization = GetPlayerCivilization;
function GetPlayerCivilization(domain, leader_type)
	local civ = PocdCivForLeader(leader_type);
	if civ ~= nil then return civ; end
	return PocdBase_GetPlayerCivilization(domain, leader_type);
end

-- the slot's crest shows the picked civilization (unknown while it is random or secret)
local _PocdCivIcons = {};
local PocdBase_GetPlayerIcons = GetPlayerIcons;
function GetPlayerIcons(domain, leader_type)
	local icons = PocdBase_GetPlayerIcons(domain, leader_type);
	local _, holder = PocdCivForLeader(leader_type);
	if icons == nil or holder == nil then return icons; end
	local copy = {};
	for k, v in pairs(icons) do copy[k] = v; end
	local civ = PocdVisibleCiv(holder);
	if civ ~= nil then
		local civIcon = _PocdCivIcons[civ];
		if civIcon == nil then
			local row = PocdQueryOne("SELECT CivilizationIcon FROM Players WHERE CivilizationType = ? ORDER BY CASE Domain WHEN 'Players:Expansion2_Players' THEN 0 ELSE 1 END LIMIT 1", civ);
			civIcon = (row and row.CivilizationIcon) or false;
			_PocdCivIcons[civ] = civIcon;
		end
		if civIcon then copy.CivIcon = civIcon; end
	else
		copy.CivIcon = "ICON_CIVILIZATION_UNKNOWN";
	end
	return copy;
end

-- a leader brings only the leader ability: the leader flyout shows nothing else
local PocdBase_GetPlayerInfo = GetPlayerInfo;
function GetPlayerInfo(domain, leader_type, ...)
	local info = PocdBase_GetPlayerInfo(domain, leader_type, ...);
	if info == nil or info.LeaderAbility == nil then return info; end
	local copy = {};
	for k, v in pairs(info) do copy[k] = v; end
	copy.CivilizationAbility = nil;
	copy.Uniques = {};
	return copy;
end

-------------------------------------------------------------------------------
-- Menus
-------------------------------------------------------------------------------
POCD_MENUS = {
	{ ParameterId = "PocdCiv",         Key = "POCD_CIV", Cat = "C", Control = "PocdCivButton", Icon = "PocdCivIcon", Header = "PocdHeaderCiv", Random = "LOC_POCD_RANDOM_CIV" },
	{ ParameterId = "PocdDistrict",    Key = "POCD_UD",  Cat = "D", Control = "PocdUDButton",  Icon = "PocdUDIcon",  Header = "PocdHeaderUD",  Random = "LOC_POCD_RANDOM_DISTRICT" },
	{ ParameterId = "PocdBuilding",    Key = "POCD_UB",  Cat = "B", Control = "PocdUBButton",  Icon = "PocdUBIcon",  Header = "PocdHeaderUB",  Random = "LOC_POCD_RANDOM_BUILDING" },
	{ ParameterId = "PocdImprovement", Key = "POCD_UI",  Cat = "I", Control = "PocdUIButton",  Icon = "PocdUIIcon",  Header = "PocdHeaderUI",  Random = "LOC_POCD_RANDOM_IMPROVEMENT" },
	{ ParameterId = "PocdUnit",        Key = "POCD_UU",  Cat = "U", Control = "PocdUUButton",  Icon = "PocdUUIcon",  Header = "PocdHeaderUU",  Random = "LOC_POCD_RANDOM_UNIT" },
};

function PocdIsRandomValue(val)
	return val == "RANDOM" or val == "RANDOM_POOL1" or val == "RANDOM_POOL2";
end

-- caption, icon and flyout data of one menu value
local _PocdInfoCache = {};
function PocdValueInfo(cat, v)
	if v == nil then return nil; end
	local key = cat .. "|" .. tostring(v.Value);
	local info = _PocdInfoCache[key];
	if info ~= nil then return info; end
	info = { Caption = v.Name or tostring(v.Value), Icon = v.Icon or "ICON_CIVILIZATION_UNKNOWN" };
	if PocdIsRandomValue(v.Value) then
		info.Random = true;
		info.Icon = "ICON_CIVILIZATION_UNKNOWN";
	elseif cat == "C" then
		local r = PocdQueryOne("SELECT CivilizationName, CivilizationIcon, CivilizationAbilityName, CivilizationAbilityDescription, CivilizationAbilityIcon, PlayerColor FROM Players WHERE CivilizationType = ? ORDER BY CASE Domain WHEN 'Players:Expansion2_Players' THEN 0 ELSE 1 END LIMIT 1", v.Value);
		if r ~= nil then
			info.Icon = r.CivilizationIcon or info.Icon;
			info.Tip = {
				CivilizationName = r.CivilizationName,
				CivilizationIcon = r.CivilizationIcon,
				PlayerColor = r.PlayerColor,
				CivilizationAbility = { Name = r.CivilizationAbilityName, Description = r.CivilizationAbilityDescription, Icon = r.CivilizationAbilityIcon },
				Uniques = {},
			};
		end
	else
		info.Tip = {
			CivilizationName = "POCD_ITEM",
			Uniques = { { Name = v.RawName or v.Name, Description = v.RawDescription or "", Icon = info.Icon, SortIndex = 0 } },
		};
	end
	_PocdInfoCache[key] = info;
	return info;
end

-------------------------------------------------------------------------------
-- "Random": resolved when a player readies up (the host also does its AI slots).
-- The result is kept secret (POCD_HIDDEN) and undone when the player un-readies.
-------------------------------------------------------------------------------
local POCD_RANDOMIZABLE = {
	{ ParameterId = "PlayerLeader",    Cat = "L" },
	{ ParameterId = "PocdCiv",         Cat = "C" },
	{ ParameterId = "PocdDistrict",    Cat = "D" },
	{ ParameterId = "PocdBuilding",    Cat = "B" },
	{ ParameterId = "PocdImprovement", Cat = "I" },
	{ ParameterId = "PocdUnit",        Cat = "U" },
};

local _pocdSeeded = false;
local function PocdRandom(n)
	if not _pocdSeeded then
		_pocdSeeded = true;
		local seed = 0;
		pcall(function() seed = seed + (GameConfiguration.GetValue("GAME_SYNC_RANDOM_SEED") or 0); end);
		pcall(function() seed = seed + os.time(); end);
		pcall(function() seed = seed + math.floor((Automation and Automation.GetTime and Automation.GetTime() or 0) * 1000); end);
		pcall(function() seed = seed + (Network.GetLocalPlayerID() or 0) * 7919; end);
		pcall(function() math.randomseed(seed % 2147483647); end);
		math.random(); math.random();
	end
	return math.random(1, n);
end

local _pocdIndex = nil;
function PocdIndexOf(cat, entity)
	if entity == nil then return nil; end
	if _pocdIndex == nil then
		_pocdIndex = {};
		for _, r in ipairs(PocdQuery("SELECT Cat, Idx, Entity FROM POCD_Index")) do
			_pocdIndex[r.Cat .. "|" .. r.Entity] = r.Idx;
		end
	end
	return _pocdIndex[cat .. "|" .. tostring(entity)];
end

local function PocdIsMajorSlot(cfg)
	if cfg == nil or cfg:GetCivilizationLevelTypeID() ~= CivilizationLevelTypes.CIVILIZATION_LEVEL_FULL_CIV then return false; end
	local status = cfg:GetSlotStatus();
	return status == SlotStatus.SS_TAKEN or status == SlotStatus.SS_COMPUTER;
end

-- Random leaders are rolled on each player's own computer, possibly at the same moment.
-- So that two players never roll the same leader, every computer rolls only from its own
-- share of the leaders (leader number + game seed, modulo the number of human players).
local function PocdLeaderShare()
	local humans = {};
	for _, id in ipairs(GameConfiguration.GetParticipatingPlayerIDs()) do
		local cfg = PlayerConfigurations[id];
		if cfg ~= nil and cfg:GetSlotStatus() == SlotStatus.SS_TAKEN then table.insert(humans, id); end
	end
	table.sort(humans);
	local count = #humans;
	if count <= 1 or GameConfiguration.IsHotseat() then return function() return true; end; end
	local localId = Network.GetLocalPlayerID();
	local rank = 0;
	for i, id in ipairs(humans) do if id == localId then rank = i - 1; end end
	local shift = 0;
	pcall(function() shift = math.abs(math.floor(GameConfiguration.GetValue("GAME_SYNC_RANDOM_SEED") or 0)); end);
	return function(idx)
		if idx == nil then return false; end
		return ((idx + shift) % count) == rank;
	end
end

-- One value written straight to the settings: no refresh and no broadcast per value
-- (Player_WriteParameterValues skips its broadcast while g_PocdBatchWrite is set).
-- The callers broadcast once per slot and refresh the lobby once at the end.
g_PocdBatchWrite = false;
local function PocdWriteValue(parameters, p, v)
	p.Value = v;
	return parameters:Config_WriteParameterValues(p);
end

-------------------------------------------------------------------------------
-- Stock binding (game setting POCD_STOCK_BIND, v23).
-- When it is on, the unique items named in the ability descriptions of the player's leader
-- and civilization (table POCD_Locks) are put into the item menus and the menus are locked
-- until the player picks another leader or civilization. A leader's item wins over the
-- civilization's item of the same type. Player settings:
--   POCD_LOCKED     letters of the locked menus (D B I U)
--   POCD_LOCK_PREV  what the player had in those menus before ("D=DISTRICT_HANSA;B=RANDOM"),
--                   given back when the lock goes away
-------------------------------------------------------------------------------
local POCD_ITEM_CATS = { "D", "B", "I", "U" };
local POCD_ITEM_PARAMS = { D = "PocdDistrict", B = "PocdBuilding", I = "PocdImprovement", U = "PocdUnit" };

function PocdStockBindOn()
	local ok, v = pcall(GameConfiguration.GetValue, "POCD_STOCK_BIND");
	return ok and (v == true or v == 1);
end

local _pocdLockRows = nil;
local function PocdLockRows()
	if _pocdLockRows == nil then
		_pocdLockRows = {};
		for _, r in ipairs(PocdQuery("SELECT Owner, Cat, ItemType FROM POCD_Locks")) do
			_pocdLockRows[r.Owner] = _pocdLockRows[r.Owner] or {};
			_pocdLockRows[r.Owner][r.Cat] = r.ItemType;
		end
	end
	return _pocdLockRows;
end

-- locked menus of a leader + civilization: { D = { Item = ..., Owner = ..., Kind = "L"/"C" }, ... }
function PocdLocksFor(leader, civ)
	local out = {};
	if not PocdStockBindOn() then return out; end
	local rows = PocdLockRows();
	if civ ~= nil and rows[civ] ~= nil then
		for cat, item in pairs(rows[civ]) do out[cat] = { Item = item, Owner = civ, Kind = "C" }; end
	end
	if leader ~= nil and rows[leader] ~= nil then
		for cat, item in pairs(rows[leader]) do out[cat] = { Item = item, Owner = leader, Kind = "L" }; end
	end
	return out;
end

function PocdLockedCats(playerConfig)
	local s = PocdGetPlayerValue(playerConfig, "POCD_LOCKED");
	if type(s) ~= "string" then return ""; end
	return s;
end

function PocdIsLocked(playerId, cat)
	local s = PocdLockedCats(PlayerConfigurations[playerId]);
	return s ~= "" and string.find(s, cat, 1, true) ~= nil;
end

-- the line for the flyout of a locked menu ("Locked by the ability ... (owner)"), nil if not locked
function PocdLockNote(playerId, cat)
	if not PocdIsLocked(playerId, cat) then return nil; end
	local cfg = PlayerConfigurations[playerId];
	local leader = cfg and cfg:GetLeaderTypeName();
	local lock = PocdLocksFor(type(leader) == "string" and leader or nil, PocdChosenCiv(cfg))[cat];
	if lock == nil then return nil; end
	local r;
	if lock.Kind == "L" then
		r = PocdQueryOne("SELECT LeaderName AS OwnerName, LeaderAbilityName AS AbilityName FROM Players WHERE LeaderType = ? ORDER BY CASE Domain WHEN 'Players:Expansion2_Players' THEN 0 ELSE 1 END LIMIT 1", lock.Owner);
	else
		r = PocdQueryOne("SELECT CivilizationName AS OwnerName, CivilizationAbilityName AS AbilityName FROM Players WHERE CivilizationType = ? ORDER BY CASE Domain WHEN 'Players:Expansion2_Players' THEN 0 ELSE 1 END LIMIT 1", lock.Owner);
	end
	if r == nil then return nil; end
	return Locale.Lookup("LOC_POCD_LOCKED_BY", Locale.Lookup(r.AbilityName or ""), Locale.Lookup(r.OwnerName or ""));
end

local function PocdParseLockPrev(s)
	local t = {};
	if type(s) == "string" then
		for cat, val in string.gmatch(s, "(%u)=([^;]*)") do t[cat] = val; end
	end
	return t;
end

local function PocdJoinLockPrev(t)
	local parts = {};
	for _, cat in ipairs(POCD_ITEM_CATS) do
		if t[cat] ~= nil then table.insert(parts, cat .. "=" .. t[cat]); end
	end
	return table.concat(parts, ";");
end

local function PocdCurrentValue(parameters, parameterId)
	local p = parameters.Parameters[parameterId];
	if p ~= nil and type(p.Value) == "table" then return p.Value.Value; end
	return nil;
end

local function PocdFindValue(p, value)
	if p == nil or type(p.Values) ~= "table" or value == nil then return nil; end
	for _, v in ipairs(p.Values) do
		if v.Value == value then return v; end
	end
	return nil;
end

-- Puts the locked items into the item menus of one slot and frees the menus that are no longer
-- locked. secretSources: letters of the leader/civilization menus rolled secretly just now
-- ("L", "C", "LC"); a menu changed by their lock becomes secret as well.
-- Must run inside a batch (PocdBatchIds). Returns true if anything was written.
local function PocdApplyLocksFor(playerId, secretSources)
	local parameters = GetPlayerParameters(playerId);
	local cfg = PlayerConfigurations[playerId];
	if parameters == nil or parameters.Parameters == nil or cfg == nil then return false; end
	local leader = PocdCurrentValue(parameters, "PlayerLeader");
	local civ = PocdCurrentValue(parameters, "PocdCiv");
	if leader == nil or PocdIsRandomValue(leader) then leader = nil; end
	if civ == nil or PocdIsRandomValue(civ) then civ = nil; end
	local want = PocdLocksFor(leader, civ);

	local wasLocked = PocdLockedCats(cfg);
	local prevText = PocdGetPlayerValue(cfg, "POCD_LOCK_PREV");
	if type(prevText) ~= "string" then prevText = ""; end
	local prev = PocdParseLockPrev(prevText);
	local hidden = PocdHiddenCats(cfg);
	local newHidden, letters, writes = hidden, "", {};

	for _, cat in ipairs(POCD_ITEM_CATS) do
		local p = parameters.Parameters[POCD_ITEM_PARAMS[cat]];
		local cur = PocdCurrentValue(parameters, POCD_ITEM_PARAMS[cat]);
		local was = string.find(wasLocked, cat, 1, true) ~= nil;
		local lock = want[cat];
		local target = lock and PocdFindValue(p, lock.Item);
		if target ~= nil then
			letters = letters .. cat;
			if not was then prev[cat] = cur or "RANDOM"; end
			if cur ~= target.Value then table.insert(writes, { Param = p, Value = target }); end
			if secretSources ~= nil and string.find(secretSources, lock.Kind, 1, true)
				and not string.find(newHidden, cat, 1, true) then
				newHidden = newHidden .. cat;
			end
		elseif was then
			local back = PocdFindValue(p, prev[cat]) or PocdFindValue(p, "RANDOM");
			prev[cat] = nil;
			if back ~= nil and cur ~= back.Value then table.insert(writes, { Param = p, Value = back }); end
		end
	end

	local changed = false;
	-- the secret flag goes first so nobody ever sees an item that tells the rolled leader
	if newHidden ~= hidden then cfg:SetValue("POCD_HIDDEN", newHidden); changed = true; end
	if letters ~= wasLocked then cfg:SetValue("POCD_LOCKED", letters); changed = true; end
	local newPrev = PocdJoinLockPrev(prev);
	if newPrev ~= prevText then cfg:SetValue("POCD_LOCK_PREV", newPrev); changed = true; end
	for _, w in ipairs(writes) do
		PocdWriteValue(parameters, w.Param, w.Value);
		changed = true;
	end
	if changed then
		PocdLog("player " .. tostring(playerId) .. ": locked menus '" .. letters .. "' (leader " .. tostring(leader) .. ", civilization " .. tostring(civ) .. ")");
	end
	return changed;
end

-- locks may be written only before the game exists and while the local player is not ready
-- (a ready player's menus are frozen; readying up applies the locks of the rolled picks)
local function PocdLocksAllowed()
	local okS, state = pcall(GameConfiguration.GetGameState);
	if okS and GameStateTypes ~= nil and state ~= nil and state ~= GameStateTypes.GAMESTATE_PREGAME then return false; end
	local localCfg = PlayerConfigurations[Network.GetLocalPlayerID()];
	if localCfg ~= nil and localCfg:GetReady() then return false; end
	return true;
end

local function PocdResolveRandomsFor(playerId, takenLeaders, inShare)
	local parameters = GetPlayerParameters(playerId);
	local cfg = PlayerConfigurations[playerId];
	if parameters == nil or parameters.Parameters == nil or cfg == nil then return; end

	-- which menus are random
	local todo, letters = {}, "";
	for _, r in ipairs(POCD_RANDOMIZABLE) do
		local p = parameters.Parameters[r.ParameterId];
		if p ~= nil and type(p.Value) == "table" and type(p.Values) == "table" and PocdIsRandomValue(p.Value.Value) then
			table.insert(todo, { Param = p, Cat = r.Cat, ParameterId = r.ParameterId });
			letters = letters .. r.Cat;
		end
	end
	if #todo == 0 then return PocdApplyLocksFor(playerId, ""); end

	-- the secret flag goes first so nobody ever sees the rolled values
	cfg:SetValue("POCD_HIDDEN", PocdHiddenCats(cfg) .. letters);

	-- stock binding: once the leader and civilization are known (rolled or chosen), their
	-- named items fill the item menus; those menus are not rolled
	local locked = nil;
	local function LockNow()
		if locked ~= nil then return; end
		local sources = "";
		if string.find(letters, "L", 1, true) then sources = sources .. "L"; end
		if string.find(letters, "C", 1, true) then sources = sources .. "C"; end
		PocdApplyLocksFor(playerId, sources);
		locked = PocdLockedCats(cfg);
	end

	for _, t in ipairs(todo) do
		if t.Cat ~= "L" and t.Cat ~= "C" then LockNow(); end
		if locked ~= nil and string.find(locked, t.Cat, 1, true) then
			PocdLog("player " .. tostring(playerId) .. ": " .. t.ParameterId .. " holds the locked item (no roll)");
		else
			local choices, shared = {}, {};
			for _, v in ipairs(t.Param.Values) do
				local val = v.Value;
				if not v.Invalid and not PocdIsRandomValue(val) and val ~= "LEADER_SPECTATOR" then
					if t.Cat ~= "L" then
						table.insert(choices, v);
					elseif not takenLeaders[val] and PocdIndexOf("L", val) ~= nil then
						table.insert(choices, v);
						if inShare(PocdIndexOf("L", val)) then table.insert(shared, v); end
					end
				end
			end
			if #shared > 0 then choices = shared; end
			if #choices > 0 then
				local v = choices[PocdRandom(#choices)];
				if t.Cat == "L" then takenLeaders[v.Value] = true; end
				PocdWriteValue(parameters, t.Param, v);
				PocdLog("player " .. tostring(playerId) .. ": random " .. t.ParameterId .. " rolled (secret)");
			else
				PocdLog("player " .. tostring(playerId) .. ": random " .. t.ParameterId .. " has no free value");
			end
		end
	end
	LockNow();	-- only the leader/civilization were random: their locks still apply
	return true;
end

-- back to "Random" for the menus that were rolled secretly
local function PocdRevertRandomsFor(playerId)
	local parameters = GetPlayerParameters(playerId);
	local cfg = PlayerConfigurations[playerId];
	if parameters == nil or parameters.Parameters == nil or cfg == nil then return false; end
	local letters = PocdHiddenCats(cfg);
	if letters == "" then return false; end
	cfg:SetValue("POCD_HIDDEN", "");
	for _, r in ipairs(POCD_RANDOMIZABLE) do
		if string.find(letters, r.Cat, 1, true) then
			local p = parameters.Parameters[r.ParameterId];
			if p ~= nil and type(p.Values) == "table" then
				for _, v in ipairs(p.Values) do
					if v.Value == "RANDOM" then
						PocdWriteValue(parameters, p, v);
						break;
					end
				end
			end
		end
	end
	PocdLog("player " .. tostring(playerId) .. ": secret random picks returned to random");
	-- locks of a rolled leader/civilization go away with it (the menus get back what the player had)
	PocdApplyLocksFor(playerId, nil);
	return true;
end


-- the slots this computer resolves: its own one; the host also the AI ones; hot seat all
local function PocdOwnSlots(localPlayerId)
	local targets = { localPlayerId };
	local isHost = (not Network.IsInSession()) or Network.IsGameHost();
	if isHost or GameConfiguration.IsHotseat() then
		for _, id in ipairs(GameConfiguration.GetParticipatingPlayerIDs()) do
			local cfg = PlayerConfigurations[id];
			if id ~= localPlayerId and PocdIsMajorSlot(cfg) then
				local status = cfg:GetSlotStatus();
				if status == SlotStatus.SS_COMPUTER or (GameConfiguration.IsHotseat() and status == SlotStatus.SS_TAKEN) then
					table.insert(targets, id);
				end
			end
		end
	end
	return targets;
end

-- runs f for the given slots in one batch: one broadcast per changed slot,
-- one lobby refresh at the end (each value on its own made the lobby hang on "Ready")
local function PocdBatchIds(label, ids, f)
	local changed = {};
	g_PocdBatchWrite = true;
	for _, id in ipairs(ids) do
		local ok, res = pcall(f, id);
		if not ok then
			PocdLog(label .. " for player " .. tostring(id) .. " failed: " .. tostring(res));
		elseif res then
			table.insert(changed, id);
		end
	end
	g_PocdBatchWrite = false;
	for _, id in ipairs(changed) do
		pcall(function() Network.BroadcastPlayerInfo(id); end);
	end
	if #changed > 0 and GameSetup_ConfigurationChanged ~= nil then
		local ok, err = pcall(GameSetup_ConfigurationChanged);
		if not ok then PocdLog(label .. " refresh failed: " .. tostring(err)); end
	end
	return #changed;
end

-- every slot of this computer (its own one; the host also the AI ones)
local function PocdBatch(label, localPlayerId, f)
	return PocdBatchIds(label, PocdOwnSlots(localPlayerId), f);
end

-- stock binding, after the player (or the host for an AI) picked a leader or a civilization
function PocdApplyLocksNow(playerId)
	if not PocdLocksAllowed() then return 0; end
	return PocdBatchIds("locks", { playerId }, function(id) return PocdApplyLocksFor(id, nil); end);
end

-- stock binding, consistency check of every slot of this computer (the staging room runs it
-- one frame after a row refresh: setting changed, player joined, AI slot added)
function PocdCheckLocks(localPlayerId)
	if not PocdLocksAllowed() then return 0; end
	return PocdBatch("locks", localPlayerId, function(id) return PocdApplyLocksFor(id, nil); end);
end

function PocdResolveRandoms(localPlayerId)
	if not PocdDraftActive() then return 0; end
	local taken = {};
	for _, id in ipairs(GameConfiguration.GetParticipatingPlayerIDs()) do
		local cfg = PlayerConfigurations[id];
		local l = cfg and cfg:GetLeaderTypeName();
		if type(l) == "string" then taken[l] = true; end
	end
	local inShare = PocdLeaderShare();
	return PocdBatch("random", localPlayerId, function(id) return PocdResolveRandomsFor(id, taken, inShare); end);
end

-- 0.1.1: the host, when the launch countdown starts (and right before launch): AI slots that
-- still hold "Random" (added or changed after the host readied up) are rolled now, secretly
-- as on "Ready"; un-readying returns them to "Random" like the host's other AI slots
function PocdHostFinishRandoms(reason)
	if not PocdDraftActive() then return 0; end
	if Network.IsInSession() and not Network.IsGameHost() then return 0; end
	local localPlayerId = Network.GetLocalPlayerID();
	local ids = {};
	for _, id in ipairs(PocdOwnSlots(localPlayerId)) do
		local cfg = PlayerConfigurations[id];
		local parameters = GetPlayerParameters(id);
		if id ~= localPlayerId and cfg ~= nil and cfg:GetSlotStatus() == SlotStatus.SS_COMPUTER
			and parameters ~= nil and parameters.Parameters ~= nil then
			for _, r in ipairs(POCD_RANDOMIZABLE) do
				local p = parameters.Parameters[r.ParameterId];
				if p ~= nil and type(p.Value) == "table" and PocdIsRandomValue(p.Value.Value) then
					table.insert(ids, id);
					break;
				end
			end
		end
	end
	if #ids == 0 then return 0; end
	PocdLog("host rolls " .. #ids .. " AI slot(s) still random (" .. tostring(reason) .. ")");
	local taken = {};
	for _, id in ipairs(GameConfiguration.GetParticipatingPlayerIDs()) do
		local cfg = PlayerConfigurations[id];
		local l = cfg and cfg:GetLeaderTypeName();
		if type(l) == "string" then taken[l] = true; end
	end
	local inShare = PocdLeaderShare();
	return PocdBatchIds("random", ids, function(id) return PocdResolveRandomsFor(id, taken, inShare); end);
end

function PocdRevertRandoms(localPlayerId)
	return PocdBatch("revert", localPlayerId, PocdRevertRandomsFor);
end

-------------------------------------------------------------------------------
-- Host: picks -> bits in the game settings (written when the launch countdown starts
-- and again right before launch; POCD_BITS_SEQ tells the staging room that the change
-- was only the bits, so nobody is un-readied by it)
-------------------------------------------------------------------------------
local _pocdCats = nil;
local _pocdMaxSlots = 14;
local function PocdCats()
	if _pocdCats == nil then
		_pocdCats = {};
		for _, r in ipairs(PocdQuery("SELECT Cat, Bits FROM POCD_Cats")) do
			table.insert(_pocdCats, { Cat = r.Cat, Bits = r.Bits });
		end
		local s = PocdQueryOne("SELECT Value FROM POCD_Settings WHERE Name = 'MaxSlots'");
		if s ~= nil then _pocdMaxSlots = s.Value; end
	end
	return _pocdCats, _pocdMaxSlots;
end

-- 0.1.1: the draft works only in Gathering Storm network games (LAN / internet); there the
-- five menus exist (ParameterDependencies on RULESET, no single player / hot seat / cloud)
function PocdDraftActive()
	local ok, active = pcall(function()
		if GameConfiguration.GetRuleSet() ~= "RULESET_EXPANSION_2" then return false; end
		if not GameConfiguration.IsAnyMultiplayer() then return false; end
		if GameConfiguration.IsHotseat() or GameConfiguration.IsPlayByCloud() then return false; end
		return true;
	end);
	return ok and active == true;
end

-- players with a draft: slots 0 .. PocdMaxSlots() - 1 (the staging room blocks the launch
-- when a civilization sits in a later slot)
function PocdMaxSlots()
	local _, maxSlots = PocdCats();
	return maxSlots;
end

-- pick numbers of one slot: L, C, D, B, I, U (missing = random/none)
function PocdSlotPicks(playerId)
	local picks = {};
	local cfg = PlayerConfigurations[playerId];
	if not PocdIsMajorSlot(cfg) then return picks; end
	local leader = cfg:GetLeaderTypeName();
	if type(leader) == "string" then picks.L = PocdIndexOf("L", leader); end
	picks.C = PocdIndexOf("C", PocdChosenCiv(cfg));
	for _, menu in ipairs(POCD_MENUS) do
		if menu.Cat ~= "C" then
			local v = PocdGetPlayerValue(cfg, menu.Key);
			if type(v) == "string" and not PocdIsRandomValue(v) then picks[menu.Cat] = PocdIndexOf(menu.Cat, v); end
		end
	end
	return picks;
end

function PocdHostWriteBits(reason)
	if Network.IsInSession() and not Network.IsGameHost() then return false; end
	local cats, maxSlots = PocdCats();
	local active = PocdDraftActive();
	local changed = 0;
	for slot = 0, maxSlots - 1 do
		local picks = active and PocdSlotPicks(slot) or {};	-- no draft: all bits 0
		for _, c in ipairs(cats) do
			local n = picks[c.Cat] or 0;
			for b = 0, c.Bits - 1 do
				local key = "POCD_S" .. slot .. "_" .. c.Cat .. "_B" .. b;
				local want = (math.floor(n / (2 ^ b)) % 2 == 1) and 1 or 0;
				local ok, cur = pcall(GameConfiguration.GetValue, key);
				if not ok or cur == nil then cur = 0; end
				if cur ~= want then
					GameConfiguration.SetValue(key, want);
					changed = changed + 1;
				end
			end
		end
	end
	if changed > 0 then
		local okS, seq = pcall(GameConfiguration.GetValue, "POCD_BITS_SEQ");
		if not okS or type(seq) ~= "number" then seq = 0; end
		GameConfiguration.SetValue("POCD_BITS_SEQ", seq + 1);
		pcall(function() Network.BroadcastGameConfig(); end);
		PocdLog("host wrote " .. changed .. " bit values (" .. tostring(reason) .. ")");
	end
	return changed > 0;
end

function PocdLogPicks(reason)
	local cats, maxSlots = PocdCats();
	for slot = 0, maxSlots - 1 do
		local cfg = PlayerConfigurations[slot];
		local picks = PocdSlotPicks(slot);
		if picks.L ~= nil then
			local parts = {};
			table.insert(parts, "leader=" .. tostring(cfg:GetLeaderTypeName()) .. "#" .. tostring(picks.L));
			table.insert(parts, "civ=" .. tostring(cfg:GetCivilizationTypeName()) .. "/" .. tostring(PocdGetPlayerValue(cfg, "POCD_CIV")) .. "#" .. tostring(picks.C));
			for _, menu in ipairs(POCD_MENUS) do
				if menu.Cat ~= "C" then
					table.insert(parts, menu.Cat .. "=" .. tostring(PocdGetPlayerValue(cfg, menu.Key)) .. "#" .. tostring(picks[menu.Cat]));
				end
			end
			table.insert(parts, "secret=" .. PocdHiddenCats(cfg));
			PocdLog(tostring(reason) .. " slot " .. slot .. ": " .. table.concat(parts, " "));
		end
	end
end
