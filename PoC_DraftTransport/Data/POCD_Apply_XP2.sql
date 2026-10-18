-- POCD v17, Gathering Storm (Leaders_XP2). Applied without criteria: the draft mod targets Gathering Storm.
-- An ocean start (Kupe) relies on the leader's own civilization being able to embark from turn 1
-- (Maori "Mana": ABILITY_MANA, ocean terrain, Sailing and Shipbuilding). When the drafted leader
-- leads another civilization, the starting units cannot be placed on water and the player gets none.
-- In that case the leader starts on land, like in BBG (which turns the ocean start off for everyone).
UPDATE Leaders_XP2 SET OceanStart = 0
WHERE OceanStart = 1
  AND LeaderType IN (
	SELECT s.LeaderType FROM POCD_Slots s
	JOIN POCD_SlotCivs c ON c.Slot = s.Slot
	WHERE NOT EXISTS (
		SELECT 1 FROM POCD_OrigCivLeaders o
		WHERE o.LeaderType = s.LeaderType AND o.CivilizationType = c.CivilizationType));

INSERT OR IGNORE INTO POCD_Hits (Name) VALUES ('apply_xp2_done');
