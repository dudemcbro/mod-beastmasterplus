-- DEV/TEST ONLY. Seed BMP test pets for a specific character.
-- Run against the CHARACTERS database. Reads creature data from the world
-- database, which is assumed to be named acore_world (edit the
-- acore_world references below if yours differs).
--
-- Usage (in the same MySQL session):
--   SET @owner := <characters.guid of the hunter>;
--   SET @n := 99;  -- optional, number of pets to create
--   SOURCE sql/characters/optional_seed_bmp_test_pets.sql;
--
-- WARNING: deletes ALL existing pets of @owner first.
-- Run it while worldserver is stopped: pet ids are taken from MAX(id) and
-- would collide with pet numbers a running server hands out.
-- If @owner is not set, nothing is deleted or inserted.

SET @n := IFNULL(@n, 99);

-- Wipe pets for this owner (optional; comment out to keep existing pets)
DELETE FROM character_pet WHERE @owner IS NOT NULL AND owner = @owner;

-- Tameable, non-exotic beasts
DROP TEMPORARY TABLE IF EXISTS tmp_tameable;
CREATE TEMPORARY TABLE tmp_tameable (
  rn INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  entry INT UNSIGNED NOT NULL
) ENGINE=MEMORY;

SET @sql := CONCAT(
  'INSERT INTO tmp_tameable (entry) ',
  'SELECT ct.entry ',
  'FROM acore_world.creature_template ct ',
  'WHERE ct.type = 1 ',
  '  AND ct.family <> 0 ',
  '  AND (ct.type_flags & 0x00000001) <> 0 ',
  '  AND (ct.type_flags & 0x00010000) = 0 ',
  'ORDER BY ct.entry ',
  'LIMIT ', @n
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Sequential ids
SET @start_id := (SELECT COALESCE(MAX(id), 0) + 1 FROM character_pet);

-- Model id mapping (first model per creature entry)
DROP TEMPORARY TABLE IF EXISTS tmp_model;
CREATE TEMPORARY TABLE tmp_model (
  CreatureID INT UNSIGNED NOT NULL PRIMARY KEY,
  CreatureDisplayID INT UNSIGNED NOT NULL
) ENGINE=MEMORY;

INSERT INTO tmp_model (CreatureID, CreatureDisplayID)
SELECT ctm.CreatureID, ctm.CreatureDisplayID
FROM acore_world.creature_template_model ctm
JOIN (
  SELECT CreatureID, MIN(Idx) AS MinIdx
  FROM acore_world.creature_template_model
  GROUP BY CreatureID
) m ON m.CreatureID = ctm.CreatureID AND m.MinIdx = ctm.Idx;

INSERT INTO character_pet (
  id, entry, owner, modelid, CreatedBySpell, PetType, level, exp, Reactstate,
  name, renamed, slot, curhealth, curmana, curhappiness, savetime, abdata
)
SELECT
  (@start_id + t.rn - 1) AS id,
  t.entry,
  @owner,
  COALESCE(tm.CreatureDisplayID, 0),
  0,
  1,
  80,
  0,
  0,
  CONCAT('BMP_Test_', @start_id + t.rn - 1),
  0,
  100,
  5000,
  1000,
  0,
  UNIX_TIMESTAMP(),
  ''
FROM tmp_tameable t
LEFT JOIN tmp_model tm ON tm.CreatureID = t.entry
WHERE @owner IS NOT NULL;

-- Verify
SELECT COUNT(*) AS pet_count FROM character_pet WHERE owner = @owner;
SELECT MIN(id) AS min_id, MAX(id) AS max_id FROM character_pet WHERE owner = @owner;
