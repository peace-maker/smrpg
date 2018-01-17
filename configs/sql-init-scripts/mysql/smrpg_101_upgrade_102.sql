-- Change charset of all varchar columns to utf8mb4 to allow 4-byte multibyte characters (like emojis!)
ALTER TABLE players CONVERT TO CHARACTER SET utf8mb4;
ALTER TABLE upgrades CONVERT TO CHARACTER SET utf8mb4;
ALTER TABLE player_upgrades CONVERT TO CHARACTER SET utf8mb4;
ALTER TABLE settings CONVERT TO CHARACTER SET utf8mb4;

-- Update database version number
UPDATE settings SET value = '102' WHERE setting = 'version';
