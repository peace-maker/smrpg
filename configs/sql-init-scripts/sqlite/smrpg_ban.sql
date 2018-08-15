-- Table to store the rpg bans of smrpg_ban.smx
CREATE TABLE bans (
	ban_id INTEGER PRIMARY KEY AUTOINCREMENT,
	name VARCHAR(128) NOT NULL,
	steamid INTEGER NOT NULL,
	start INTEGER NOT NULL,
	length INTEGER NOT NULL,
	reason VARCHAR(256) NOT NULL,
	unban_time INTEGER DEFAULT NULL
);
