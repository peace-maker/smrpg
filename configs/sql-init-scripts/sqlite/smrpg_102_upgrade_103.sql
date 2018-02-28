-- Delete lines that should not exist
DELETE FROM player_upgrades WHERE player_id NOT IN (SELECT player_id FROM players) OR upgrade_id NOT IN (SELECT upgrade_id FROM upgrades);

-- Add foreign key constraints to avoid data pollution
ALTER TABLE player_upgrades ADD FOREIGN KEY (player_id) REFERENCES players(player_id) ON DELETE CASCADE;
ALTER TABLE player_upgrades ADD FOREIGN KEY (upgrade_id) REFERENCES upgrades(upgrade_id) ON DELETE CASCADE;

-- Update database version number
UPDATE settings SET value = '103' WHERE setting = 'version';
