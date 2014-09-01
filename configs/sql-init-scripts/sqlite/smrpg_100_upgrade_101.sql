-- Create a new table with the changed steamid field.
-- SQLite doesn't support altering column types of existing tables.
CREATE TABLE players_X (
	player_id INTEGER PRIMARY KEY AUTOINCREMENT, 
	name VARCHAR(64) NOT NULL DEFAULT ' ', 
	steamid INTEGER DEFAULT NULL UNIQUE, 
	level INTEGER DEFAULT '1', 
	experience INTEGER DEFAULT '0', 
	credits INTEGER DEFAULT '0', 
	showmenu INTEGER DEFAULT '1', 
	fadescreen INTEGER DEFAULT '1', 
	lastseen INTEGER DEFAULT '0', 
	lastreset INTEGER DEFAULT '0'
);

-- Insert all bots with NULL steamid.
INSERT INTO players_X SELECT player_id, name, NULL, level, experience, credits, showmenu, fadescreen, lastseen, lastreset FROM players WHERE steamid NOT LIKE 'STEAM_%';

-- Insert all players and convert the steamid to accountid.
INSERT INTO players_X SELECT player_id, name, CAST(SUBSTRING(steamid, 9, 1) AS INTEGER) + CAST(SUBSTRING(steamid, 11) * 2 AS INTEGER), level, experience, credits, showmenu, fadescreen, lastseen, lastreset FROM players WHERE steamid LIKE 'STEAM_%';

-- Drop the old player table.
DROP TABLE players;

-- Rename the copied new one to match the correct table name of the old table.
ALTER TABLE players_X RENAME TO players;

-- Update database version number
UPDATE settings SET value = '101' WHERE setting = 'version';