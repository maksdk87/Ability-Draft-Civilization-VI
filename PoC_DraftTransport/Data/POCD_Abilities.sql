-- =============================================================================
-- POCD 0.1.1: abilities and the drafted unique items.
-- Runs after POCD_Apply.sql (needs POCD_Slots, POCD_SlotCivs, POCD_MajorItemTraits).
-- Only in a drafted game: every change below depends on rows in POCD_Slots.
-- =============================================================================

-- every base district/building and the unique ones that replace it (a "kind")
CREATE TABLE IF NOT EXISTS POCD_Kinds (
	Member TEXT NOT NULL,
	Base TEXT NOT NULL,
	PRIMARY KEY (Member)
);
INSERT OR IGNORE INTO POCD_Kinds (Member, Base) SELECT CivUniqueDistrictType, ReplacesDistrictType FROM DistrictReplaces;
INSERT OR IGNORE INTO POCD_Kinds (Member, Base) SELECT CivUniqueBuildingType, ReplacesBuildingType FROM BuildingReplaces;
INSERT OR IGNORE INTO POCD_Kinds (Member, Base) SELECT DISTINCT Base, Base FROM POCD_Kinds;

-- ability traits (not the trait of a unique item) of the drafted leaders and civilizations
CREATE TABLE IF NOT EXISTS POCD_AbilityTraits (
	TraitType TEXT NOT NULL,
	PRIMARY KEY (TraitType)
);
INSERT OR IGNORE INTO POCD_AbilityTraits (TraitType)
SELECT lt.TraitType FROM LeaderTraits lt JOIN POCD_Slots s ON s.LeaderType = lt.LeaderType
WHERE lt.TraitType NOT IN (SELECT TraitType FROM POCD_MajorItemTraits);
INSERT OR IGNORE INTO POCD_AbilityTraits (TraitType)
SELECT ct.TraitType FROM CivilizationTraits ct JOIN POCD_SlotCivs c ON c.CivilizationType = ct.CivilizationType
WHERE ct.TraitType NOT IN (SELECT TraitType FROM POCD_MajorItemTraits);

-- -----------------------------------------------------------------------------
-- (a) A mine/farm bonus next to a unique district belongs to the civilization's ability,
--     not to the district (Korea: mines and farms next to a Seowon; Maya: farms next to an
--     Observatory). The game gives it to every such plot next to the district, so in a draft
--     anybody who drafted the district got it. Now it goes to that civilization's own plots,
--     +1 for EACH adjacent finished district of the same kind (Korea without the Seowon: each
--     adjacent campus, as the Seowon would count).
--     How (like the Nazca Line, which gives +1 faith to the plots next to it): the ability
--     attaches a modifier to each of the player's districts of the kind; that modifier, owned
--     by the district, gives the yield to the player's plots next to its owner while the
--     district is functioning. Two districts next to a plot = two modifiers = +2.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS POCD_AdjMoves (
	AdjacencyId TEXT NOT NULL,
	ImprovementType TEXT NOT NULL,
	DistrictType TEXT NOT NULL,
	Base TEXT NOT NULL,
	CivilizationType TEXT NOT NULL,
	YieldType TEXT NOT NULL,
	Amount INTEGER NOT NULL,
	PRIMARY KEY (AdjacencyId, ImprovementType)
);
INSERT OR IGNORE INTO POCD_AdjMoves (AdjacencyId, ImprovementType, DistrictType, Base, CivilizationType, YieldType, Amount)
SELECT a.ID, ia.ImprovementType, a.AdjacentDistrict, k.Base, ct.CivilizationType, a.YieldType, a.YieldChange
FROM Improvement_Adjacencies ia
JOIN Improvements imp ON imp.ImprovementType = ia.ImprovementType AND imp.TraitType IS NULL
JOIN Adjacency_YieldChanges a ON a.ID = ia.YieldChangeId
JOIN Districts d ON d.DistrictType = a.AdjacentDistrict AND d.TraitType IS NOT NULL
JOIN POCD_Kinds k ON k.Member = d.DistrictType
JOIN POCD_OrigCivTraits ct ON ct.TraitType = d.TraitType
WHERE EXISTS (SELECT 1 FROM POCD_Slots)
  AND a.TilesRequired = 1 AND a.YieldChange > 0
  AND a.PrereqTech IS NULL AND a.PrereqCivic IS NULL AND a.ObsoleteTech IS NULL AND a.ObsoleteCivic IS NULL;

-- the district no longer gives it to everybody
DELETE FROM Improvement_Adjacencies
WHERE EXISTS (SELECT 1 FROM POCD_AdjMoves m
	WHERE m.AdjacencyId = Improvement_Adjacencies.YieldChangeId AND m.ImprovementType = Improvement_Adjacencies.ImprovementType);

-- districts of the kind (read by the gameplay script for its log)
CREATE TABLE IF NOT EXISTS POCD_AdjCount (
	DistrictType TEXT NOT NULL,
	PropertyName TEXT NOT NULL,
	PRIMARY KEY (DistrictType)
);
INSERT OR IGNORE INTO POCD_AdjCount (DistrictType, PropertyName)
SELECT DISTINCT k.Member, k.Base FROM POCD_Kinds k WHERE k.Base IN (SELECT Base FROM POCD_AdjMoves);

-- a modifier type of our own: attach a modifier to each district of the player
INSERT OR IGNORE INTO Types (Type, Kind)
SELECT 'MODIFIER_POCD_PLAYER_DISTRICTS_ATTACH_MODIFIER', 'KIND_MODIFIER' WHERE EXISTS (SELECT 1 FROM POCD_AdjMoves);
INSERT OR IGNORE INTO DynamicModifiers (ModifierType, CollectionType, EffectType)
SELECT 'MODIFIER_POCD_PLAYER_DISTRICTS_ATTACH_MODIFIER', 'COLLECTION_PLAYER_DISTRICTS', 'EFFECT_ATTACH_MODIFIER' WHERE EXISTS (SELECT 1 FROM POCD_AdjMoves);

-- district is of the kind
INSERT OR IGNORE INTO Requirements (RequirementId, RequirementType)
SELECT DISTINCT 'POCD_REQ_DISTRICT_IS_' || k.Member, 'REQUIREMENT_DISTRICT_TYPE_MATCHES'
FROM POCD_Kinds k WHERE k.Base IN (SELECT Base FROM POCD_AdjMoves);
INSERT OR IGNORE INTO RequirementArguments (RequirementId, Name, Value)
SELECT DISTINCT 'POCD_REQ_DISTRICT_IS_' || k.Member, 'DistrictType', k.Member
FROM POCD_Kinds k WHERE k.Base IN (SELECT Base FROM POCD_AdjMoves);
INSERT OR IGNORE INTO RequirementSets (RequirementSetId, RequirementSetType)
SELECT DISTINCT 'POCD_RS_DISTRICT_KIND_' || Base, 'REQUIREMENTSET_TEST_ANY' FROM POCD_AdjMoves;
INSERT OR IGNORE INTO RequirementSetRequirements (RequirementSetId, RequirementId)
SELECT DISTINCT 'POCD_RS_DISTRICT_KIND_' || k.Base, 'POCD_REQ_DISTRICT_IS_' || k.Member
FROM POCD_Kinds k WHERE k.Base IN (SELECT Base FROM POCD_AdjMoves);

-- the owner district is functioning (finished, not pillaged): its own plot holds a functioning
-- district of the kind (the plot requirement the game also uses for adjacency, range 0 = the plot itself)
INSERT OR IGNORE INTO Requirements (RequirementId, RequirementType)
SELECT DISTINCT 'POCD_REQ_SELF_' || k.Member, 'REQUIREMENT_PLOT_ADJACENT_DISTRICT_TYPE_MATCHES'
FROM POCD_Kinds k WHERE k.Base IN (SELECT Base FROM POCD_AdjMoves);
INSERT OR IGNORE INTO RequirementArguments (RequirementId, Name, Value)
SELECT DISTINCT 'POCD_REQ_SELF_' || k.Member, 'DistrictType', k.Member
FROM POCD_Kinds k WHERE k.Base IN (SELECT Base FROM POCD_AdjMoves);
INSERT OR IGNORE INTO RequirementArguments (RequirementId, Name, Value)
SELECT DISTINCT 'POCD_REQ_SELF_' || k.Member, 'MinRange', 0
FROM POCD_Kinds k WHERE k.Base IN (SELECT Base FROM POCD_AdjMoves);
INSERT OR IGNORE INTO RequirementArguments (RequirementId, Name, Value)
SELECT DISTINCT 'POCD_REQ_SELF_' || k.Member, 'MaxRange', 0
FROM POCD_Kinds k WHERE k.Base IN (SELECT Base FROM POCD_AdjMoves);
INSERT OR IGNORE INTO RequirementArguments (RequirementId, Name, Value)
SELECT DISTINCT 'POCD_REQ_SELF_' || k.Member, 'MustBeFunctioning', 1
FROM POCD_Kinds k WHERE k.Base IN (SELECT Base FROM POCD_AdjMoves);
INSERT OR IGNORE INTO RequirementSets (RequirementSetId, RequirementSetType)
SELECT DISTINCT 'POCD_RS_SELF_KIND_' || Base, 'REQUIREMENTSET_TEST_ANY' FROM POCD_AdjMoves;
INSERT OR IGNORE INTO RequirementSetRequirements (RequirementSetId, RequirementId)
SELECT DISTINCT 'POCD_RS_SELF_KIND_' || k.Base, 'POCD_REQ_SELF_' || k.Member
FROM POCD_Kinds k WHERE k.Base IN (SELECT Base FROM POCD_AdjMoves);

-- plot is next to the owner district / plot has the improvement
INSERT OR IGNORE INTO Requirements (RequirementId, RequirementType)
SELECT 'POCD_REQ_PLOT_ADJACENT_TO_OWNER', 'REQUIREMENT_PLOT_ADJACENT_TO_OWNER' WHERE EXISTS (SELECT 1 FROM POCD_AdjMoves);
INSERT OR IGNORE INTO Requirements (RequirementId, RequirementType)
SELECT DISTINCT 'POCD_REQ_HAS_' || ImprovementType, 'REQUIREMENT_PLOT_IMPROVEMENT_TYPE_MATCHES' FROM POCD_AdjMoves;
INSERT OR IGNORE INTO RequirementArguments (RequirementId, Name, Value)
SELECT DISTINCT 'POCD_REQ_HAS_' || ImprovementType, 'ImprovementType', ImprovementType FROM POCD_AdjMoves;
INSERT OR IGNORE INTO RequirementSets (RequirementSetId, RequirementSetType)
SELECT 'POCD_RS_' || AdjacencyId || '_' || ImprovementType, 'REQUIREMENTSET_TEST_ALL' FROM POCD_AdjMoves;
INSERT OR IGNORE INTO RequirementSetRequirements (RequirementSetId, RequirementId)
SELECT 'POCD_RS_' || AdjacencyId || '_' || ImprovementType, 'POCD_REQ_PLOT_ADJACENT_TO_OWNER' FROM POCD_AdjMoves;
INSERT OR IGNORE INTO RequirementSetRequirements (RequirementSetId, RequirementId)
SELECT 'POCD_RS_' || AdjacencyId || '_' || ImprovementType, 'POCD_REQ_HAS_' || ImprovementType FROM POCD_AdjMoves;

-- the yield, owned by one district
INSERT OR IGNORE INTO Modifiers (ModifierId, ModifierType, OwnerRequirementSetId, SubjectRequirementSetId)
SELECT 'POCD_MOD_' || AdjacencyId || '_' || ImprovementType, 'MODIFIER_PLAYER_ADJUST_PLOT_YIELD',
	'POCD_RS_SELF_KIND_' || Base, 'POCD_RS_' || AdjacencyId || '_' || ImprovementType FROM POCD_AdjMoves;
INSERT OR IGNORE INTO ModifierArguments (ModifierId, Name, Value)
SELECT 'POCD_MOD_' || AdjacencyId || '_' || ImprovementType, 'YieldType', YieldType FROM POCD_AdjMoves;
INSERT OR IGNORE INTO ModifierArguments (ModifierId, Name, Value)
SELECT 'POCD_MOD_' || AdjacencyId || '_' || ImprovementType, 'Amount', Amount FROM POCD_AdjMoves;

-- the ability attaches it to each of the player's districts of the kind
INSERT OR IGNORE INTO Modifiers (ModifierId, ModifierType, SubjectRequirementSetId)
SELECT 'POCD_ATTACH_' || AdjacencyId || '_' || ImprovementType, 'MODIFIER_POCD_PLAYER_DISTRICTS_ATTACH_MODIFIER',
	'POCD_RS_DISTRICT_KIND_' || Base FROM POCD_AdjMoves;
INSERT OR IGNORE INTO ModifierArguments (ModifierId, Name, Value)
SELECT 'POCD_ATTACH_' || AdjacencyId || '_' || ImprovementType, 'ModifierId', 'POCD_MOD_' || AdjacencyId || '_' || ImprovementType FROM POCD_AdjMoves;

INSERT OR IGNORE INTO TraitModifiers (TraitType, ModifierId)
SELECT ct.TraitType, 'POCD_ATTACH_' || m.AdjacencyId || '_' || m.ImprovementType
FROM POCD_AdjMoves m
JOIN CivilizationTraits ct ON ct.CivilizationType = m.CivilizationType
WHERE ct.TraitType NOT IN (SELECT TraitType FROM POCD_MajorItemTraits);

-- -----------------------------------------------------------------------------
-- (b) An ability that names a district/building of some kind works with every district/building
--     of that kind the player may have drafted: the base one and the unique ones replacing it
--     (Gaul: campus -> Seowon, Observatory; oppidum -> industrial zone, Hansa. Victoria: Royal Navy
--     Dockyard -> harbor, Cothon. Theodora: hippodrome -> entertainment complex, Street Carnival).
--     The game matches these arguments by the exact type (it lists Tsikhe and Seowon separately
--     itself), and a player has only one district/building of a kind, so nothing counts twice.
--     Skipped when the ability already has the same modifier for that type (Georgia: tsikhe and
--     star fort).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS POCD_Clones (
	TraitType TEXT NOT NULL,
	ModifierId TEXT NOT NULL,
	NewId TEXT NOT NULL,
	ArgName TEXT NOT NULL,
	NewValue TEXT NOT NULL,
	PRIMARY KEY (TraitType, NewId)
);
INSERT OR IGNORE INTO POCD_Clones (TraitType, ModifierId, NewId, ArgName, NewValue)
SELECT tm.TraitType, tm.ModifierId, tm.ModifierId || '_POCD_' || y.Member, a.Name, y.Member
FROM TraitModifiers tm
JOIN POCD_AbilityTraits t ON t.TraitType = tm.TraitType
JOIN Modifiers m ON m.ModifierId = tm.ModifierId
JOIN ModifierArguments a ON a.ModifierId = tm.ModifierId AND a.Name IN ('DistrictType', 'BuildingType')
JOIN POCD_Kinds x ON x.Member = a.Value
JOIN POCD_Kinds y ON y.Base = x.Base AND y.Member <> x.Member
WHERE m.ModifierType IN (
		'MODIFIER_PLAYER_CITIES_IMPROVEMENT_ADJACENCY', 'MODIFIER_PLAYER_CITIES_DISTRICT_ADJACENCY',
		'MODIFIER_PLAYER_CITIES_FEATURE_ADJACENCY', 'MODIFIER_PLAYER_CITIES_TERRAIN_ADJACENCY',
		'MODIFIER_PLAYER_CITIES_RIVER_ADJACENCY', 'MODIFIER_PLAYER_DISTRICTS_ADJUST_YIELD_BASED_ON_APPEAL',
		'MODIFIER_PLAYER_CITIES_ADJUST_DISTRICT_PRODUCTION', 'MODIFIER_PLAYER_CITIES_ADJUST_BUILDING_PRODUCTION',
		'MODIFIER_PLAYER_DISTRICT_CREATE_UNIT', 'MODIFIER_PLAYER_ADJUST_DISTRICT_ADD_NAVAL_UNIT',
		'MODIFIER_PLAYER_ADD_CULTURE_BOMB_TRIGGER', 'MODIFIER_PLAYER_CITIES_ENABLE_BUILDING_FAITH_PURCHASE',
		'MODIFIER_PLAYER_DISTRICT_ADJUST_PLAYER_DISTRICT_AND_BUILDINGS_CREATE_UNIT_WITH_ABILITY_BY_CLASS_GREAT_NEGOTIATORS',
		'MODIFIER_PLAYER_CITIES_ADJUST_EXTRA_GREAT_WORK_SLOTS', 'MODIFIER_PLAYER_CITIES_ADJUST_BUILDING_YIELD_CHANGE')
  AND NOT EXISTS (
	SELECT 1 FROM TraitModifiers tm2
	JOIN Modifiers m2 ON m2.ModifierId = tm2.ModifierId AND m2.ModifierType = m.ModifierType
	JOIN ModifierArguments a2 ON a2.ModifierId = tm2.ModifierId AND a2.Name = a.Name AND a2.Value = y.Member
	WHERE tm2.TraitType = tm.TraitType
	  AND NOT EXISTS (
		SELECT Name, Value FROM ModifierArguments WHERE ModifierId = tm.ModifierId AND Name <> a.Name
		EXCEPT
		SELECT Name, Value FROM ModifierArguments WHERE ModifierId = tm2.ModifierId))
  AND NOT EXISTS (SELECT 1 FROM Modifiers z WHERE z.ModifierId = tm.ModifierId || '_POCD_' || y.Member);

INSERT OR IGNORE INTO Modifiers (ModifierId, ModifierType, RunOnce, NewOnly, Permanent, Repeatable,
	OwnerRequirementSetId, SubjectRequirementSetId, OwnerStackLimit, SubjectStackLimit)
SELECT DISTINCT c.NewId, m.ModifierType, m.RunOnce, m.NewOnly, m.Permanent, m.Repeatable,
	m.OwnerRequirementSetId, m.SubjectRequirementSetId, m.OwnerStackLimit, m.SubjectStackLimit
FROM POCD_Clones c JOIN Modifiers m ON m.ModifierId = c.ModifierId;
INSERT OR IGNORE INTO ModifierArguments (ModifierId, Name, Type, Value, Extra, SecondExtra)
SELECT DISTINCT c.NewId, a.Name, a.Type, CASE WHEN a.Name = c.ArgName THEN c.NewValue ELSE a.Value END, a.Extra, a.SecondExtra
FROM POCD_Clones c JOIN ModifierArguments a ON a.ModifierId = c.ModifierId;
INSERT OR IGNORE INTO ModifierStrings (ModifierId, Context, Text)
SELECT DISTINCT c.NewId, s.Context, s.Text
FROM POCD_Clones c JOIN ModifierStrings s ON s.ModifierId = c.ModifierId;
INSERT OR IGNORE INTO TraitModifiers (TraitType, ModifierId)
SELECT TraitType, NewId FROM POCD_Clones;

-- -----------------------------------------------------------------------------
-- (c) A requirement of an ability that checks one district/building of some kind (city has an
--     industrial zone, district is a holy site, plot next to an aqueduct, city has a factory...)
--     accepts every district/building of that kind (Lincoln with a Hansa, Byzantium with a Lavra,
--     Sweden with an Electronics Factory). Like (b), but for requirements instead of modifier
--     arguments. Only the drafted abilities' own modifiers change (and what they attach); the
--     shared requirement sets are copied, never edited, so nothing else in the game is touched.
--     How: requirement R (type argument = X) is replaced in the copied set by a wrapper
--     "set POCD_RSKA_R is met" (same Inverse as R), and that TEST_ANY set holds a copy of R for
--     every member of X's kind. A nested "set is met" requirement that leads to such a set is
--     copied too and points to the copied set.
-- -----------------------------------------------------------------------------
-- modifiers of the drafted abilities and everything they attach (4 levels deep)
CREATE TABLE IF NOT EXISTS POCD_KMods (
	ModifierId TEXT NOT NULL,
	PRIMARY KEY (ModifierId)
);
INSERT OR IGNORE INTO POCD_KMods (ModifierId)
SELECT tm.ModifierId FROM TraitModifiers tm JOIN POCD_AbilityTraits t ON t.TraitType = tm.TraitType
WHERE tm.ModifierId IN (SELECT ModifierId FROM Modifiers);
INSERT OR IGNORE INTO POCD_KMods (ModifierId)
SELECT a.Value FROM ModifierArguments a JOIN POCD_KMods k ON k.ModifierId = a.ModifierId
WHERE a.Name = 'ModifierId' AND a.Value IN (SELECT ModifierId FROM Modifiers);
INSERT OR IGNORE INTO POCD_KMods (ModifierId)
SELECT a.Value FROM ModifierArguments a JOIN POCD_KMods k ON k.ModifierId = a.ModifierId
WHERE a.Name = 'ModifierId' AND a.Value IN (SELECT ModifierId FROM Modifiers);
INSERT OR IGNORE INTO POCD_KMods (ModifierId)
SELECT a.Value FROM ModifierArguments a JOIN POCD_KMods k ON k.ModifierId = a.ModifierId
WHERE a.Name = 'ModifierId' AND a.Value IN (SELECT ModifierId FROM Modifiers);
INSERT OR IGNORE INTO POCD_KMods (ModifierId)
SELECT a.Value FROM ModifierArguments a JOIN POCD_KMods k ON k.ModifierId = a.ModifierId
WHERE a.Name = 'ModifierId' AND a.Value IN (SELECT ModifierId FROM Modifiers);

-- requirement sets they use, with the sets nested in them (not our own POCD_ sets)
CREATE TABLE IF NOT EXISTS POCD_KSets (
	RequirementSetId TEXT NOT NULL,
	PRIMARY KEY (RequirementSetId)
);
INSERT OR IGNORE INTO POCD_KSets (RequirementSetId)
SELECT m.SubjectRequirementSetId FROM Modifiers m JOIN POCD_KMods k ON k.ModifierId = m.ModifierId
WHERE m.SubjectRequirementSetId IS NOT NULL;
INSERT OR IGNORE INTO POCD_KSets (RequirementSetId)
SELECT m.OwnerRequirementSetId FROM Modifiers m JOIN POCD_KMods k ON k.ModifierId = m.ModifierId
WHERE m.OwnerRequirementSetId IS NOT NULL;
INSERT OR IGNORE INTO POCD_KSets (RequirementSetId)
SELECT ra.Value FROM POCD_KSets s
JOIN RequirementSetRequirements rsr ON rsr.RequirementSetId = s.RequirementSetId
JOIN Requirements r ON r.RequirementId = rsr.RequirementId AND r.RequirementType = 'REQUIREMENT_REQUIREMENTSET_IS_MET'
JOIN RequirementArguments ra ON ra.RequirementId = r.RequirementId AND ra.Name = 'RequirementSetId'
WHERE ra.Value IN (SELECT RequirementSetId FROM RequirementSets);
INSERT OR IGNORE INTO POCD_KSets (RequirementSetId)
SELECT ra.Value FROM POCD_KSets s
JOIN RequirementSetRequirements rsr ON rsr.RequirementSetId = s.RequirementSetId
JOIN Requirements r ON r.RequirementId = rsr.RequirementId AND r.RequirementType = 'REQUIREMENT_REQUIREMENTSET_IS_MET'
JOIN RequirementArguments ra ON ra.RequirementId = r.RequirementId AND ra.Name = 'RequirementSetId'
WHERE ra.Value IN (SELECT RequirementSetId FROM RequirementSets);
INSERT OR IGNORE INTO POCD_KSets (RequirementSetId)
SELECT ra.Value FROM POCD_KSets s
JOIN RequirementSetRequirements rsr ON rsr.RequirementSetId = s.RequirementSetId
JOIN Requirements r ON r.RequirementId = rsr.RequirementId AND r.RequirementType = 'REQUIREMENT_REQUIREMENTSET_IS_MET'
JOIN RequirementArguments ra ON ra.RequirementId = r.RequirementId AND ra.Name = 'RequirementSetId'
WHERE ra.Value IN (SELECT RequirementSetId FROM RequirementSets);
INSERT OR IGNORE INTO POCD_KSets (RequirementSetId)
SELECT ra.Value FROM POCD_KSets s
JOIN RequirementSetRequirements rsr ON rsr.RequirementSetId = s.RequirementSetId
JOIN Requirements r ON r.RequirementId = rsr.RequirementId AND r.RequirementType = 'REQUIREMENT_REQUIREMENTSET_IS_MET'
JOIN RequirementArguments ra ON ra.RequirementId = r.RequirementId AND ra.Name = 'RequirementSetId'
WHERE ra.Value IN (SELECT RequirementSetId FROM RequirementSets);
DELETE FROM POCD_KSets WHERE substr(RequirementSetId, 1, 5) = 'POCD_';

-- requirements in those sets that name one district/building of a kind
CREATE TABLE IF NOT EXISTS POCD_KReqs (
	RequirementId TEXT NOT NULL,
	ArgName TEXT NOT NULL,
	Base TEXT NOT NULL,
	PRIMARY KEY (RequirementId)
);
INSERT OR IGNORE INTO POCD_KReqs (RequirementId, ArgName, Base)
SELECT DISTINCT ra.RequirementId, ra.Name, k.Base
FROM POCD_KSets s
JOIN RequirementSetRequirements rsr ON rsr.RequirementSetId = s.RequirementSetId
JOIN RequirementArguments ra ON ra.RequirementId = rsr.RequirementId AND ra.Name IN ('DistrictType', 'BuildingType')
JOIN POCD_Kinds k ON k.Member = ra.Value
WHERE substr(ra.RequirementId, 1, 5) <> 'POCD_';

-- sets that hold such a requirement, directly or through a nested set (4 levels up)
CREATE TABLE IF NOT EXISTS POCD_KAff (
	RequirementSetId TEXT NOT NULL,
	PRIMARY KEY (RequirementSetId)
);
INSERT OR IGNORE INTO POCD_KAff (RequirementSetId)
SELECT DISTINCT rsr.RequirementSetId FROM RequirementSetRequirements rsr
JOIN POCD_KSets s ON s.RequirementSetId = rsr.RequirementSetId
JOIN POCD_KReqs q ON q.RequirementId = rsr.RequirementId;
CREATE TABLE IF NOT EXISTS POCD_KNest (
	RequirementId TEXT NOT NULL,
	Target TEXT NOT NULL,
	PRIMARY KEY (RequirementId)
);
INSERT OR IGNORE INTO POCD_KNest (RequirementId, Target)
SELECT r.RequirementId, ra.Value FROM Requirements r
JOIN RequirementArguments ra ON ra.RequirementId = r.RequirementId AND ra.Name = 'RequirementSetId'
WHERE r.RequirementType = 'REQUIREMENT_REQUIREMENTSET_IS_MET'
  AND r.RequirementId IN (SELECT rsr.RequirementId FROM RequirementSetRequirements rsr JOIN POCD_KSets s ON s.RequirementSetId = rsr.RequirementSetId)
  AND ra.Value IN (SELECT RequirementSetId FROM POCD_KSets);
INSERT OR IGNORE INTO POCD_KAff (RequirementSetId)
SELECT DISTINCT rsr.RequirementSetId FROM RequirementSetRequirements rsr
JOIN POCD_KSets s ON s.RequirementSetId = rsr.RequirementSetId
JOIN POCD_KNest n ON n.RequirementId = rsr.RequirementId
JOIN POCD_KAff a ON a.RequirementSetId = n.Target;
INSERT OR IGNORE INTO POCD_KAff (RequirementSetId)
SELECT DISTINCT rsr.RequirementSetId FROM RequirementSetRequirements rsr
JOIN POCD_KSets s ON s.RequirementSetId = rsr.RequirementSetId
JOIN POCD_KNest n ON n.RequirementId = rsr.RequirementId
JOIN POCD_KAff a ON a.RequirementSetId = n.Target;
INSERT OR IGNORE INTO POCD_KAff (RequirementSetId)
SELECT DISTINCT rsr.RequirementSetId FROM RequirementSetRequirements rsr
JOIN POCD_KSets s ON s.RequirementSetId = rsr.RequirementSetId
JOIN POCD_KNest n ON n.RequirementId = rsr.RequirementId
JOIN POCD_KAff a ON a.RequirementSetId = n.Target;
INSERT OR IGNORE INTO POCD_KAff (RequirementSetId)
SELECT DISTINCT rsr.RequirementSetId FROM RequirementSetRequirements rsr
JOIN POCD_KSets s ON s.RequirementSetId = rsr.RequirementSetId
JOIN POCD_KNest n ON n.RequirementId = rsr.RequirementId
JOIN POCD_KAff a ON a.RequirementSetId = n.Target;
DELETE FROM POCD_KNest WHERE Target NOT IN (SELECT RequirementSetId FROM POCD_KAff);

-- copy of R for every member of the kind, and the "any of them" set
INSERT OR IGNORE INTO Requirements (RequirementId, RequirementType, Likeliness, Impact, Inverse, Reverse, Persistent, ProgressWeight, Triggered)
SELECT 'POCD_RQKM_' || r.RequirementId || '_' || k.Member, r.RequirementType, r.Likeliness, r.Impact, 0, r.Reverse, r.Persistent, r.ProgressWeight, r.Triggered
FROM POCD_KReqs q JOIN Requirements r ON r.RequirementId = q.RequirementId JOIN POCD_Kinds k ON k.Base = q.Base;
INSERT OR IGNORE INTO RequirementArguments (RequirementId, Name, Type, Value, Extra, SecondExtra)
SELECT 'POCD_RQKM_' || q.RequirementId || '_' || k.Member, a.Name, a.Type,
	CASE WHEN a.Name = q.ArgName THEN k.Member ELSE a.Value END, a.Extra, a.SecondExtra
FROM POCD_KReqs q JOIN RequirementArguments a ON a.RequirementId = q.RequirementId JOIN POCD_Kinds k ON k.Base = q.Base;
INSERT OR IGNORE INTO RequirementSets (RequirementSetId, RequirementSetType)
SELECT 'POCD_RSKA_' || RequirementId, 'REQUIREMENTSET_TEST_ANY' FROM POCD_KReqs;
INSERT OR IGNORE INTO RequirementSetRequirements (RequirementSetId, RequirementId)
SELECT 'POCD_RSKA_' || q.RequirementId, 'POCD_RQKM_' || q.RequirementId || '_' || k.Member
FROM POCD_KReqs q JOIN POCD_Kinds k ON k.Base = q.Base;

-- the wrapper that takes R's place
INSERT OR IGNORE INTO Requirements (RequirementId, RequirementType, Likeliness, Impact, Inverse, ProgressWeight)
SELECT 'POCD_RQK_' || r.RequirementId, 'REQUIREMENT_REQUIREMENTSET_IS_MET', r.Likeliness, r.Impact, r.Inverse, r.ProgressWeight
FROM POCD_KReqs q JOIN Requirements r ON r.RequirementId = q.RequirementId;
INSERT OR IGNORE INTO RequirementArguments (RequirementId, Name, Value)
SELECT 'POCD_RQK_' || RequirementId, 'RequirementSetId', 'POCD_RSKA_' || RequirementId FROM POCD_KReqs;

-- nested "set is met" that leads to a changed set: points to the copy
INSERT OR IGNORE INTO Requirements (RequirementId, RequirementType, Likeliness, Impact, Inverse, Reverse, Persistent, ProgressWeight, Triggered)
SELECT 'POCD_RQS_' || r.RequirementId, r.RequirementType, r.Likeliness, r.Impact, r.Inverse, r.Reverse, r.Persistent, r.ProgressWeight, r.Triggered
FROM POCD_KNest n JOIN Requirements r ON r.RequirementId = n.RequirementId;
INSERT OR IGNORE INTO RequirementArguments (RequirementId, Name, Type, Value, Extra, SecondExtra)
SELECT 'POCD_RQS_' || n.RequirementId, a.Name, a.Type,
	CASE WHEN a.Name = 'RequirementSetId' THEN 'POCD_RSK_' || n.Target ELSE a.Value END, a.Extra, a.SecondExtra
FROM POCD_KNest n JOIN RequirementArguments a ON a.RequirementId = n.RequirementId;

-- copies of the changed sets
INSERT OR IGNORE INTO RequirementSets (RequirementSetId, RequirementSetType)
SELECT 'POCD_RSK_' || s.RequirementSetId, s.RequirementSetType
FROM POCD_KAff a JOIN RequirementSets s ON s.RequirementSetId = a.RequirementSetId;
INSERT OR IGNORE INTO RequirementSetRequirements (RequirementSetId, RequirementId)
SELECT 'POCD_RSK_' || rsr.RequirementSetId,
	CASE WHEN rsr.RequirementId IN (SELECT RequirementId FROM POCD_KReqs) THEN 'POCD_RQK_' || rsr.RequirementId
	     WHEN rsr.RequirementId IN (SELECT RequirementId FROM POCD_KNest) THEN 'POCD_RQS_' || rsr.RequirementId
	     ELSE rsr.RequirementId END
FROM RequirementSetRequirements rsr JOIN POCD_KAff a ON a.RequirementSetId = rsr.RequirementSetId;

-- the drafted abilities' modifiers use the copies
UPDATE Modifiers SET SubjectRequirementSetId = 'POCD_RSK_' || SubjectRequirementSetId
WHERE ModifierId IN (SELECT ModifierId FROM POCD_KMods)
  AND SubjectRequirementSetId IN (SELECT RequirementSetId FROM POCD_KAff);
UPDATE Modifiers SET OwnerRequirementSetId = 'POCD_RSK_' || OwnerRequirementSetId
WHERE ModifierId IN (SELECT ModifierId FROM POCD_KMods)
  AND OwnerRequirementSetId IN (SELECT RequirementSetId FROM POCD_KAff);

INSERT OR IGNORE INTO POCD_Hits (Name) VALUES ('abilities_done');
