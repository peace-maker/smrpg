-- Allow NULL as steamid value
ALTER TABLE players CHANGE steamid steamid VARCHAR(64) CHARACTER SET utf8 COLLATE utf8_general_ci NULL;

-- Set bot's steamid to NULL
UPDATE players SET steamid = NULL WHERE steamid NOT LIKE 'STEAM_%';

-- Convert STEAM_X:Y:Z steamids to account ids
UPDATE players SET steamid = CAST(SUBSTRING(steamid, 9, 1) AS UNSIGNED) + CAST(SUBSTRING(steamid, 11) * 2 AS UNSIGNED) WHERE steamid LIKE 'STEAM_%';

-- Save the steamids as integers now.
ALTER TABLE players CHANGE steamid steamid INTEGER NULL;

-- Update database version number
UPDATE settings SET value = '101' WHERE setting = 'version';