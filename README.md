SM:RPG
=====

A modular generic RPG plugin for SourceMod 1.5+.

Based on [CSS:RPG](http://forums.alliedmods.net/showthread.php?t=51039) v1.0.5 by SeLfkiLL.

# Introduction
SM:RPG is a generic RPG plugin. Players earn experience by killing other players or other game dependent events. After they reach a certain amount of experience, they level up and get some credits.
The credits can be used to buy upgrades which give the player an advantage against his enemies.

This plugin tries to be as game independent as possible. If some upgrade or core feature isn't working in your game, leave a comment.
There's a seperate plugin for CS:S to give proper experience on game events like bomb exploded or hostage rescued.

# Modular upgrades
All upgrades are standalone plugins that register with the core. The core smrpg plugin handles the levels, experience and credits of a player as well as the upgrade levels.
When an upgrade registers itself at the core, it'll automatically be added to the rpgmenu for players to buy.

Server admins can install a new upgrade simply by loading the upgrade plugin.

# Compile requirements
* [smlib](https://github.com/bcserv/smlib)
* [AutoExecConfig](https://github.com/Impact123/AutoExecConfig)
* (optional) [DHooks](https://forums.alliedmods.net/showthread.php?t=180114) for Speed+ upgrade

# Installation
* Compile the core plugin (see Compile requirements)
* If there is a seperate experience module for your game (currently only cstrike), compile and upload that too.
* Compile all the upgrades you want to use
* Upload the .smx files as well as the gamedata and translations to your gameserver
* Add a "smrpg" section to your databases.cfg. Both mysql and sqlite are supported.

```
	"smrpg"
	{
		"driver"			"sqlite"
		"database"			"smrpg"
	}
```
* Start your server. The core config files are generated in [mod]/cfg/sourcemod/ and the config files for the single upgrades in [mod]/cfg/sourcemod/smrpg.

# API
Developers can easily add new upgrades using the extensive API provided by the core.
Have a look at the include file here: [smrpg.inc](https://github.com/peace-maker/smrpg/blob/master/scripting/include/smrpg.inc)
See the available upgrade plugins for examples.

# Available upgrades
* Damage+ - Deal additional damage on enemies.
* Denial - Keep your weapons the next time you spawn after you've died.
* Fire Grenade - Ignites players damaged by your grenade.
* Frost Pistol - Slow down players hit with a pistol.
* Health+ - Increases your health.
* Ice Stab - Freeze a player in place when knifing him.
* Impulse - Gain speed for a short time when being shot.
* Long Jump - Boosts your jump speed.
* Medic - Heals team mates around you.
* Regeneration - Regenerates HP every second.
* Resupply - Regenerates ammo every third second.
* Speed+ - Increase your average movement speed.
* Stealth - Renders yourself more and more invisible.
* Vampire - Steal HP from players when damaging them.

# Credits
* SeLfkiLL - author of original MM:S [CSS:RPG](http://forums.alliedmods.net/showthread.php?t=51039) plugin.
* arsirc - author of [THC:RPG](https://forums.alliedmods.net/showthread.php?p=1142124) plugin. Provided the Damage+ and Speed+ upgrade ideas.