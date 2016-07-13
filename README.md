SM:RPG
=====

A modular generic RPG plugin for SourceMod 1.6+.

Based on [CSS:RPG](http://forums.alliedmods.net/showthread.php?t=51039) v1.0.5 by SeLfkiLL.

# Introduction
SM:RPG is a generic RPG (Role Playing Game) plugin. Players earn experience by killing other players or on other game dependent events. After they reach a certain amount of experience, they level up and get some credits.
The credits can be used to buy upgrades which give the player an advantage against his enemies.

This plugin tries to be as game independent as possible. If some upgrade or core feature isn't working in your game, leave a comment.
There's a seperate plugin for Counter-Strike: Source/Global Offensive to give proper experience on game events like bomb exploded or hostage rescued.

# Modular upgrades
All upgrades are standalone plugins that register with the core. The core smrpg plugin handles the levels, experience and credits of a player as well as the upgrade levels.
When an upgrade registers itself at the core, it'll automatically be added to the rpgmenu for players to buy.

Server admins can install a new upgrade simply by loading the upgrade plugin.

# Compile requirements
* [smlib git master](https://github.com/bcserv/smlib)
* [AutoExecConfig](https://github.com/Impact123/AutoExecConfig)
* (optional) [DHooks](https://forums.alliedmods.net/showthread.php?t=180114) for Speed+ upgrade

# Installation
* Compile the core smrpg plugin (see Compile requirements)
  * Files in the scripting/smrpg and scripting/smrpg_effects folders are included in the respective plugins smrpg.sp and smrpg_effects.sp and mustn't be compiled on their own.
* If there is a seperate experience module for your game (currently only cstrike), compile and upload that too.
* Compile all optional features if you want them.
  * smrpg_resetstats - Automatically reset the stats on different conditions and display next reset date in chat.
  * smrpg_commandlist - Teach players about different available rpg related chat commands.
  * smrpg_effects - Central library to apply similar upgrade effects. Required by some upgrades!
  * smrpg_keyhint_info (On CS:S) - Display rpg stats and more info permanently on the screen.
  * smrpg_chatxpstats - Display infos in chat about gained experience for a kill or during the whole last life.
  * smrpg_gifting - Allow players to give other players rpg credits as a gift.
  * smrpg_turbomode - Increase the experience and credits rate for one map, but don't save the stats. For fun events.
  * smrpg_antisuicide - Punish players who commit suicide during a fight by taking some experience.
  * smrpg_disablexp - Admin option to temporarily disable experience for individual players.
* Compile all the upgrades you want to use
* Upload the .smx files as well as the configs, gamedata and translations to your gameserver
* Add a "smrpg" section to your databases.cfg. Both mysql and sqlite are supported.

```
	"smrpg"
	{
		"driver"			"sqlite"
		"database"			"smrpg"
	}
```
* Start your server. The core config files are generated in [mod]/cfg/sourcemod/ and the config files for the single upgrades in [mod]/cfg/sourcemod/smrpg.
* Next to the above generated config files there are additional config files in [mod]/addons/sourcemod/configs/smrpg.

# API
Developers can easily add new upgrades using the extensive API provided by the core.
There are forwards and natives to control the earned experience, level and credits. You can add your own items to the rpgmenu as well.
Have a look at the [include files](https://github.com/peace-maker/smrpg/blob/master/scripting/include)!

See the available upgrade plugins for examples. You can use the [example upgrade](https://github.com/peace-maker/smrpg/blob/master/scripting/upgrades/smrpg_upgrade_example.sp) as a skeleton.

# Available upgrades
* Antidote - Reduce duration of bad effects against you like burning, freezing or slow down.
* Armor+ (Counter-Strike only) - Increases your maximal armor.
* Armor Helmet (Counter-Strike only) - Gives players a chance to receive a helmet on spawn.
* Armor Regeneration (Counter-Strike only) - Regenerates armor regularly.
* Bouncy Bullets - Push enemies away by shooting them.
* Damage+ - Deal additional damage on enemies.
* Denial - Keep your weapons the next time you spawn after you've died.
* Fast Reload (Counter-Strike: Source only) - Increases the reload speed of guns.
* Fire Grenade - Ignites players damaged by your grenade.
* Fire Pistol - Ignites players hit with a pistol.
* Frost Pistol - Slow down players hit with a pistol.
* Grenade Resupply (Counter-Strike only) - Regenerates grenades x seconds after you threw them.
* Health+ - Increases your maximal health.
* HP Regeneration - Regenerates HP regularly.
* Ice Grenade - Freezes players damaged by your grenade in place.
* Ice Stab - Freeze a player in place when knifing him.
* Impulse - Gain speed for a short time when being shot.
* Increase Clipsize - Increases the size of a weapon's clip.
* Increase Firerate - Increases the firerate of weapons.
* Long Jump - Boosts your jump speed.
* Medic - Heals team mates around you.
* Poison Smoke (Counter-Strike: Source only) - Damages players inside the smoke of a smoke grenade.
* Reduced Fall Damage - Reduces the damage you take from falling from great heights.
* Reduced Gravity - Reduces your gravity and lets you jump higher.
* Resupply - Regenerates ammo every third second.
* Shrinking - Make player models smaller.
* Speed+ - Increase your average movement speed.
* Stealth - Renders yourself more and more invisible.
* Vampire - Steal HP from players when damaging them.

# RPG Top 10 on your website
There is an [example PHP script](https://github.com/peace-maker/smrpg/blob/master/helper_scripts/webtop10_example.php) to list the top 10 rpg players including their stats and selected levels. You might want to merge it into your website.

# Credits
* SeLfkiLL - author of the original MM:S [CSS:RPG](http://forums.alliedmods.net/showthread.php?t=51039) plugin.
* arsirc - author of [THC:RPG](https://forums.alliedmods.net/showthread.php?t=123596). Provided the Damage+, Speed+ and Gravity- upgrade ideas and the team lock option.
* SumGuy14 (Aka Soccerdude) - author of [RPGx](https://forums.alliedmods.net/showthread.php?t=56877). Config and visual effect ideas, using a seperate plugin to coordinate similar effects.
* freddukes - author of [SourceRPG](http://forums.eventscripts.com/viewtopic.php?f=27&t=20789). Config ideas, turbo mode, showing menu on levelup, ...