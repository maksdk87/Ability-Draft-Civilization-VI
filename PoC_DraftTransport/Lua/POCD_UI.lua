-- POCD v19 in-game UI context script
-- For the local player (hot seat switches it), what the capital may produce:
-- each drafted item next to the base item it replaces.

local TAG = "[POCD][UI] "
local function Log(msg) print(TAG .. tostring(msg)) end

local m_logged = {}

-- drafted items of a slot and the base items they replace
local function ItemsToCheck(slot)
	local out = {}
	pcall(function()
		for row in GameInfo.POCD_SlotItems() do
			if row.Slot == slot then
				local it = row.ItemType
				table.insert(out, it)
				local base = nil
				pcall(function() for r in GameInfo.UnitReplaces() do if r.CivUniqueUnitType == it then base = r.ReplacesUnitType end end end)
				pcall(function() for r in GameInfo.BuildingReplaces() do if r.CivUniqueBuildingType == it then base = r.ReplacesBuildingType end end end)
				pcall(function() for r in GameInfo.DistrictReplaces() do if r.CivUniqueDistrictType == it then base = r.ReplacesDistrictType end end end)
				if base ~= nil then table.insert(out, base) end
			end
		end
	end)
	return out
end

local function Check(q, itemType)
	local row, kind = GameInfo.Units[itemType], "unit"
	if row == nil then row, kind = GameInfo.Buildings[itemType], "building" end
	if row == nil then row, kind = GameInfo.Districts[itemType], "district" end
	if row == nil then
		if GameInfo.Improvements[itemType] ~= nil then return itemType .. "=improvement (built by builders)" end
		return itemType .. "=not in database"
	end
	local ok, can, results = pcall(function() return q:CanProduce(row.Hash, false, true) end)
	local reasons = {}
	if ok and results ~= nil then
		local fr = results[CityCommandResults.FAILURE_REASONS]
		if fr ~= nil then for _, v in pairs(fr) do table.insert(reasons, tostring(v)) end end
	end
	local okC, cost = pcall(function()
		if kind == "unit" then return q:GetUnitCost(row.Index) end
		if kind == "building" then return q:GetBuildingCost(row.Index) end
		return q:GetDistrictCost(row.Index)
	end)
	return itemType .. "=" .. (ok and tostring(can) or ("error " .. tostring(can)))
		.. " cost=" .. (okC and tostring(cost) or "?")
		.. (#reasons > 0 and (" [" .. table.concat(reasons, " ; ") .. "]") or "")
end

local function OnLocalPlayerTurnBegin()
	local localID = Game.GetLocalPlayer()
	if localID == nil or localID < 0 then return end
	local pCity = Players[localID]:GetCities():GetCapitalCity()
	if pCity == nil then return end
	m_logged[localID] = (m_logged[localID] or 0) + 1
	if m_logged[localID] > 2 then return end
	local q = pCity:GetBuildQueue()
	local cfg = PlayerConfigurations[localID]
	local out = {}
	for _, t in ipairs(ItemsToCheck(localID)) do table.insert(out, Check(q, t)) end
	Log("turn " .. tostring(Game.GetCurrentGameTurn()) .. " player " .. localID .. " civ=" .. tostring(cfg:GetCivilizationTypeName())
		.. " leader=" .. tostring(cfg:GetLeaderTypeName()) .. " capital=" .. tostring(pCity:GetName()) .. " | " .. table.concat(out, " | "))
end

Events.LocalPlayerTurnBegin.Add(OnLocalPlayerTurnBegin)
Log("v23 UI script loaded")
