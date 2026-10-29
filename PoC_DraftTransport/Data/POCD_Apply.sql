-- POCD v19: turn the lobby picks (bits written by the conditional actions) into real traits.
-- Runs after every conditional action (higher LoadOrder).

-- pick number of every slot and category = sum of its bits
CREATE TABLE IF NOT EXISTS POCD_SlotPicks (
	Slot INTEGER NOT NULL,
	Cat TEXT NOT NULL,
	Idx INTEGER NOT NULL,
	PRIMARY KEY (Slot, Cat)
);
INSERT OR REPLACE INTO POCD_SlotPicks (Slot, Cat, Idx)
SELECT Slot, Cat, SUM(1 << Bit) FROM POCD_SlotBits GROUP BY Slot, Cat;

CREATE TABLE IF NOT EXISTS POCD_Slots (
	Slot INTEGER NOT NULL,
	LeaderType TEXT NOT NULL,
	PRIMARY KEY (Slot)
);
CREATE TABLE IF NOT EXISTS POCD_SlotCivs (
	Slot INTEGER NOT NULL,
	CivilizationType TEXT NOT NULL,
	PRIMARY KEY (Slot)
);
CREATE TABLE IF NOT EXISTS POCD_SlotItems (
	Slot INTEGER NOT NULL,
	ItemType TEXT NOT NULL,
	PRIMARY KEY (Slot, ItemType)
);

INSERT OR REPLACE INTO POCD_Slots (Slot, LeaderType)
SELECT p.Slot, x.Entity FROM POCD_SlotPicks p
JOIN POCD_Index x ON x.Cat = 'L' AND x.Idx = p.Idx
WHERE p.Cat = 'L' AND x.Entity IN (SELECT LeaderType FROM Leaders);

INSERT OR REPLACE INTO POCD_SlotCivs (Slot, CivilizationType)
SELECT p.Slot, x.Entity FROM POCD_SlotPicks p
JOIN POCD_Index x ON x.Cat = 'C' AND x.Idx = p.Idx
WHERE p.Cat = 'C' AND x.Entity IN (SELECT CivilizationType FROM Civilizations);

INSERT OR IGNORE INTO POCD_SlotItems (Slot, ItemType)
SELECT p.Slot, x.Entity FROM POCD_SlotPicks p
JOIN POCD_Index x ON x.Cat = p.Cat AND x.Idx = p.Idx
WHERE p.Cat IN ('D', 'B', 'I', 'U');

-- traits of major civilizations and their leaders (city-state, barbarian and placeholder traits are left alone)
CREATE TABLE IF NOT EXISTS POCD_MajorTraits (
	TraitType TEXT NOT NULL,
	PRIMARY KEY (TraitType)
);
INSERT OR IGNORE INTO POCD_MajorTraits (TraitType)
SELECT ct.TraitType FROM CivilizationTraits ct
JOIN Civilizations c ON c.CivilizationType = ct.CivilizationType
WHERE c.StartingCivilizationLevelType = 'CIVILIZATION_LEVEL_FULL_CIV';
INSERT OR IGNORE INTO POCD_MajorTraits (TraitType)
SELECT lt.TraitType FROM LeaderTraits lt
JOIN CivilizationLeaders cl ON cl.LeaderType = lt.LeaderType
JOIN Civilizations c ON c.CivilizationType = cl.CivilizationType
WHERE c.StartingCivilizationLevelType = 'CIVILIZATION_LEVEL_FULL_CIV';

-- unique items of major civilizations and leaders, with the trait that unlocks each
CREATE TABLE IF NOT EXISTS POCD_MajorItemTraits (
	ItemType TEXT NOT NULL,
	TraitType TEXT NOT NULL,
	PRIMARY KEY (ItemType)
);
INSERT OR IGNORE INTO POCD_MajorItemTraits (ItemType, TraitType)
SELECT UnitType, TraitType FROM Units WHERE TraitType IN (SELECT TraitType FROM POCD_MajorTraits);
INSERT OR IGNORE INTO POCD_MajorItemTraits (ItemType, TraitType)
SELECT BuildingType, TraitType FROM Buildings WHERE TraitType IN (SELECT TraitType FROM POCD_MajorTraits);
INSERT OR IGNORE INTO POCD_MajorItemTraits (ItemType, TraitType)
SELECT DistrictType, TraitType FROM Districts WHERE TraitType IN (SELECT TraitType FROM POCD_MajorTraits);
INSERT OR IGNORE INTO POCD_MajorItemTraits (ItemType, TraitType)
SELECT ImprovementType, TraitType FROM Improvements WHERE TraitType IN (SELECT TraitType FROM POCD_MajorTraits);

-- untouched copy of who natively leads which civilization (used by POCD_Apply_XP2.sql)
CREATE TABLE IF NOT EXISTS POCD_OrigCivLeaders (
	CivilizationType TEXT NOT NULL,
	LeaderType TEXT NOT NULL,
	PRIMARY KEY (CivilizationType, LeaderType)
);
INSERT OR IGNORE INTO POCD_OrigCivLeaders (CivilizationType, LeaderType)
SELECT CivilizationType, LeaderType FROM CivilizationLeaders;

-- untouched copy of the civilizations' traits (v23, used by POCD_Abilities.sql: whose district is it)
CREATE TABLE IF NOT EXISTS POCD_OrigCivTraits (
	CivilizationType TEXT NOT NULL,
	TraitType TEXT NOT NULL,
	PRIMARY KEY (CivilizationType, TraitType)
);
INSERT OR IGNORE INTO POCD_OrigCivTraits (CivilizationType, TraitType)
SELECT CivilizationType, TraitType FROM CivilizationTraits;

-- 1) the picked leader leads the picked civilization (capital name taken from that civilization)
INSERT OR IGNORE INTO CivilizationLeaders (CivilizationType, LeaderType, CapitalName)
SELECT c.CivilizationType, s.LeaderType,
	(SELECT cl.CapitalName FROM CivilizationLeaders cl WHERE cl.CivilizationType = c.CivilizationType LIMIT 1)
FROM POCD_Slots s
JOIN POCD_SlotCivs c ON c.Slot = s.Slot;

-- 2) a picked civilization keeps its ability but loses its unique items
DELETE FROM CivilizationTraits
WHERE TraitType IN (SELECT TraitType FROM POCD_MajorItemTraits)
  AND CivilizationType IN (SELECT CivilizationType FROM POCD_SlotCivs);

-- 3) a picked leader keeps its ability but loses its own unique items
DELETE FROM LeaderTraits
WHERE TraitType IN (SELECT TraitType FROM POCD_MajorItemTraits)
  AND LeaderType IN (SELECT LeaderType FROM POCD_Slots);

-- 0.1.3: items that are a leader's own mechanic, not a draft pick (Bolivar: Comandante General -
-- his ability grants them, the unit trait belongs to Gran Colombia). Same list as in Config.
CREATE TABLE IF NOT EXISTS POCD_LeaderMechanics (
	LeaderType TEXT NOT NULL,
	ItemType TEXT NOT NULL,
	PRIMARY KEY (LeaderType, ItemType)
);
INSERT OR REPLACE INTO POCD_LeaderMechanics (LeaderType, ItemType) VALUES
('LEADER_SIMON_BOLIVAR', 'UNIT_COMANDANTE_GENERAL');

-- 4) picked unique items become the player's own (a leader mechanic is never a pick)
INSERT OR IGNORE INTO LeaderTraits (LeaderType, TraitType)
SELECT s.LeaderType, m.TraitType
FROM POCD_Slots s
JOIN POCD_SlotItems i ON i.Slot = s.Slot
JOIN POCD_MajorItemTraits m ON m.ItemType = i.ItemType
WHERE i.ItemType NOT IN (SELECT ItemType FROM POCD_LeaderMechanics);

-- 5) 0.1.3: a leader's mechanic stays with that leader, whatever was drafted and with any stock
--    binding; nobody else gets it (a picked Gran Colombia lost it in step 2)
INSERT OR IGNORE INTO LeaderTraits (LeaderType, TraitType)
SELECT s.LeaderType, m.TraitType
FROM POCD_Slots s
JOIN POCD_LeaderMechanics lm ON lm.LeaderType = s.LeaderType
JOIN POCD_MajorItemTraits m ON m.ItemType = lm.ItemType;

INSERT OR IGNORE INTO POCD_Hits (Name) VALUES ('apply_done');
