-- SQLite doesn't need to have the charset changed.

-- Update database version number
UPDATE settings SET value = '102' WHERE setting = 'version';
