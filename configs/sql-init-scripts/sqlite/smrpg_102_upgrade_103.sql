PRAGMA foreign_keys=OFF;

-- Delete lines that should not exist
DELETE FROM player_upgrades WHERE player_id NOT IN (SELECT player_id FROM players) OR upgrade_id NOT IN (SELECT upgrade_id FROM upgrades);

-- Rename table to keep old data.
ALTER TABLE player_upgrades RENAME TO player_upgrades_old;

-- Recreate table with foreign key constraints to avoid data pollution.
CREATE TABLE player_upgrades (
	player_id INTEGER, 
	upgrade_id INTEGER, 
	purchasedlevel INTEGER NOT NULL, 
	selectedlevel INTEGER NOT NULL, 
	enabled INTEGER DEFAULT '1', 
	visuals INTEGER DEFAULT '1', 
	sounds INTEGER DEFAULT '1', 
	PRIMARY KEY (player_id, upgrade_id),
	FOREIGN KEY (player_id) REFERENCES players(player_id) ON DELETE CASCADE,
	FOREIGN KEY (upgrade_id) REFERENCES upgrades(upgrade_id) ON DELETE CASCADE
);

-- Restore old data.
INSERT INTO player_upgrades SELECT * FROM player_upgrades_old;

-- Get rid of the old table.
DROP TABLE player_upgrades_old;

PRAGMA foreign_keys=ON;

-- Update database version number
UPDATE settings SET value = '103' WHERE setting = 'version';
