CREATE TABLE players (
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

CREATE TABLE upgrades (
	upgrade_id INTEGER PRIMARY KEY AUTOINCREMENT, 
	shortname VARCHAR(32) UNIQUE NOT NULL, 
	date_added INTEGER
);

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

CREATE TABLE settings (
	setting VARCHAR(64) PRIMARY KEY NOT NULL, 
	value VARCHAR(256) NOT NULL
);

INSERT INTO settings (setting, value) VALUES ('version', '103');
