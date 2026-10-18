-- POCD v27.5: start biases from the draft picks, for BBS (Better Balanced Starts).
-- By default every player keeps the standard biases of the civilization in the slot (BBS reads them
-- by civilization as usual). Picks tied to the sea add a coastal bias for that player only;
-- the Open-Air Museum adds BBS's "King of the North"; Lady Six Sky brings BBS's "away from the sea"
-- (taken from the Maya civilization) and Menelik brings the hills (taken from Ethiopia). The map generator reads POCD_SlotBias through the hook in
-- Maps/Utility/MapEnums.lua (only when BBS is active).
-- Tier: 1-2 = mandatory, 3-5 = secondary (as in BBS). When a player gets the same bias twice,
-- the strongest tier (smallest number) is kept.
-- Mode: ADD = add (or strengthen) a bias; DROP = remove a standard bias of the civilization;
-- SET = change the tier of a standard bias of the civilization. DROP and SET go first, then ADD.
-- POCD_CivBiasEdits also carries the fixes BBG makes to the game's biases (Ethiopia, Mongolia,
-- Scythia): with the plain game data BBS finds no start for them and falls back to Firaxis.

CREATE TABLE IF NOT EXISTS POCD_BiasRules (
	ItemType TEXT NOT NULL,		-- leader, civilization or unique item
	BiasType TEXT NOT NULL,		-- TERRAINS, FEATURES, RESOURCES or a BBS custom placement (CUSTOM_...)
	TargetType TEXT NOT NULL DEFAULT '',	-- terrain, feature or resource; '' for a custom placement
	Tier INTEGER NOT NULL,
	PRIMARY KEY (ItemType, BiasType, TargetType)
);

-- changes to the standard biases of a civilization (every player of that civilization)
CREATE TABLE IF NOT EXISTS POCD_CivBiasEdits (
	CivilizationType TEXT NOT NULL,
	Mode TEXT NOT NULL,			-- DROP, SET or ADD
	BiasType TEXT NOT NULL,		-- TERRAINS, FEATURES, RESOURCES or CUSTOM_...
	TargetType TEXT NOT NULL DEFAULT '',
	Tier INTEGER NOT NULL DEFAULT 0,
	PRIMARY KEY (CivilizationType, BiasType, TargetType)
);

CREATE TABLE IF NOT EXISTS POCD_SlotBias (
	Slot INTEGER NOT NULL,
	Mode TEXT NOT NULL DEFAULT 'ADD',
	BiasType TEXT NOT NULL,
	TargetType TEXT,
	Tier INTEGER NOT NULL,
	Source TEXT NOT NULL
);

INSERT OR REPLACE INTO POCD_BiasRules (ItemType, BiasType, TargetType, Tier) VALUES
-- leaders tied to the sea (by their ability text): coast, tier 1
('LEADER_ELIZABETH',				'TERRAINS', 'TERRAIN_COAST', 1),	-- Drake's Legacy: great admirals, naval raids
('LEADER_GITARJA',					'TERRAINS', 'TERRAIN_COAST', 1),	-- naval units for faith, city centre next to coast
('LEADER_HARDRADA',					'TERRAINS', 'TERRAIN_COAST', 1),	-- coastal raids, naval melee production
('LEADER_HOJO',						'TERRAINS', 'TERRAIN_COAST', 1),	-- combat on coastal tiles and shallow water
('LEADER_VICTORIA',					'TERRAINS', 'TERRAIN_COAST', 1),	-- Age of Empire: Royal Navy Dockyard, other continents
-- Lady Six Sky: away from the sea (BBS custom placement, always tier 1), instead of the Maya civilization
('LEADER_LADY_SIX_SKY',				'CUSTOM_HYDROPHOBIC', '', 1),
-- Menelik: hills (his ability: cities on hills, combat on hills), tiers as BBG gives Ethiopia; instead of Ethiopia
('LEADER_MENELIK',					'TERRAINS', 'TERRAIN_GRASS_HILLS', 3),
('LEADER_MENELIK',					'TERRAINS', 'TERRAIN_PLAINS_HILLS', 3),
-- civilizations tied to the sea: coast, tier 1
('CIVILIZATION_AUSTRALIA',			'TERRAINS', 'TERRAIN_COAST', 1),
('CIVILIZATION_INDONESIA',			'TERRAINS', 'TERRAIN_COAST', 1),
('CIVILIZATION_MAORI',				'TERRAINS', 'TERRAIN_COAST', 1),
('CIVILIZATION_NETHERLANDS',		'TERRAINS', 'TERRAIN_COAST', 1),
('CIVILIZATION_NORWAY',				'TERRAINS', 'TERRAIN_COAST', 1),
('CIVILIZATION_PHOENICIA',			'TERRAINS', 'TERRAIN_COAST', 1),
('CIVILIZATION_PORTUGAL',			'TERRAINS', 'TERRAIN_COAST', 1),
('CIVILIZATION_SPAIN',				'TERRAINS', 'TERRAIN_COAST', 1),	-- Treasure Fleet: fleets and armadas
-- districts built on water: coast, tier 1 (not Copacabana; Kupe is not a sea leader either)
('DISTRICT_COTHON',					'TERRAINS', 'TERRAIN_COAST', 1),
('DISTRICT_ROYAL_NAVY_DOCKYARD',	'TERRAINS', 'TERRAIN_COAST', 1),
-- building: Navigation School (naval production, science from coast and lake tiles)
('BUILDING_NAVIGATION_SCHOOL',		'TERRAINS', 'TERRAIN_COAST', 3),
-- improvements on coast tiles: tier 3
('IMPROVEMENT_POLDER',				'TERRAINS', 'TERRAIN_COAST', 3),
('IMPROVEMENT_KAMPUNG',				'TERRAINS', 'TERRAIN_COAST', 3),
('IMPROVEMENT_FEITORIA',			'TERRAINS', 'TERRAIN_COAST', 3),
-- Open-Air Museum: King of the North (north or south third of the map), as Sweden has in BBS
('IMPROVEMENT_OPEN_AIR_MUSEUM',		'CUSTOM_KING_OF_THE_NORTH', '', 1),
-- naval units: ancient and classical tier 4, later tier 5
('UNIT_NORWEGIAN_LONGSHIP',			'TERRAINS', 'TERRAIN_COAST', 4),
('UNIT_PHOENICIA_BIREME',			'TERRAINS', 'TERRAIN_COAST', 4),
('UNIT_BYZANTINE_DROMON',			'TERRAINS', 'TERRAIN_COAST', 4),
('UNIT_INDONESIAN_JONG',			'TERRAINS', 'TERRAIN_COAST', 5),
('UNIT_OTTOMAN_BARBARY_CORSAIR',	'TERRAINS', 'TERRAIN_COAST', 5),
('UNIT_PORTUGUESE_NAU',				'TERRAINS', 'TERRAIN_COAST', 5),
('UNIT_ENGLISH_SEADOG',				'TERRAINS', 'TERRAIN_COAST', 5),
('UNIT_DE_ZEVEN_PROVINCIEN',		'TERRAINS', 'TERRAIN_COAST', 5),
('UNIT_BRAZILIAN_MINAS_GERAES',		'TERRAINS', 'TERRAIN_COAST', 5),
('UNIT_GERMAN_UBOAT',				'TERRAINS', 'TERRAIN_COAST', 5);

INSERT OR REPLACE INTO POCD_CivBiasEdits (CivilizationType, Mode, BiasType, TargetType, Tier) VALUES
-- "away from the sea" belongs to Lady Six Sky now, not to the Maya civilization
('CIVILIZATION_MAYA',		'DROP',	'CUSTOM_HYDROPHOBIC',	'',						0),
-- Ethiopia: four kinds of hills at tier 2 can never all be met (BBS finds no start); the hills
-- belong to Menelik now (BBG keeps grass and plains hills at tier 3 for Ethiopia)
('CIVILIZATION_ETHIOPIA',	'DROP',	'TERRAINS',				'TERRAIN_TUNDRA_HILLS',	0),
('CIVILIZATION_ETHIOPIA',	'DROP',	'TERRAINS',				'TERRAIN_DESERT_HILLS',	0),
('CIVILIZATION_ETHIOPIA',	'DROP',	'TERRAINS',				'TERRAIN_GRASS_HILLS',	0),
('CIVILIZATION_ETHIOPIA',	'DROP',	'TERRAINS',				'TERRAIN_PLAINS_HILLS',	0),
-- as BBG (XP1/xp1__rise_and_fall.sql): horses at tier 2 are rarely dense enough
('CIVILIZATION_MONGOLIA',	'SET',	'RESOURCES',			'RESOURCE_HORSES',		4),
-- as BBG (Base/base.sql)
('CIVILIZATION_SCYTHIA',	'SET',	'RESOURCES',			'RESOURCE_HORSES',		3),
('CIVILIZATION_SCYTHIA',	'ADD',	'RESOURCES',			'RESOURCE_SHEEP',		4),
('CIVILIZATION_SCYTHIA',	'ADD',	'RESOURCES',			'RESOURCE_CATTLE',		4);

-- per slot: edits of the slot's civilization, then rules matched by the picked leader, civilization and items
INSERT INTO POCD_SlotBias (Slot, Mode, BiasType, TargetType, Tier, Source)
SELECT c.Slot, e.Mode, e.BiasType, NULLIF(e.TargetType, ''), e.Tier, e.CivilizationType
FROM POCD_SlotCivs c JOIN POCD_CivBiasEdits e ON e.CivilizationType = c.CivilizationType;

INSERT INTO POCD_SlotBias (Slot, Mode, BiasType, TargetType, Tier, Source)
SELECT s.Slot, 'ADD', r.BiasType, NULLIF(r.TargetType, ''), r.Tier, r.ItemType
FROM POCD_Slots s JOIN POCD_BiasRules r ON r.ItemType = s.LeaderType;

INSERT INTO POCD_SlotBias (Slot, Mode, BiasType, TargetType, Tier, Source)
SELECT c.Slot, 'ADD', r.BiasType, NULLIF(r.TargetType, ''), r.Tier, r.ItemType
FROM POCD_SlotCivs c JOIN POCD_BiasRules r ON r.ItemType = c.CivilizationType;

INSERT INTO POCD_SlotBias (Slot, Mode, BiasType, TargetType, Tier, Source)
SELECT i.Slot, 'ADD', r.BiasType, NULLIF(r.TargetType, ''), r.Tier, r.ItemType
FROM POCD_SlotItems i JOIN POCD_BiasRules r ON r.ItemType = i.ItemType;

INSERT OR IGNORE INTO POCD_Hits (Name) VALUES ('startbias_done');
