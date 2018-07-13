<?php
// Enter your database credentials.
$host = "localhost"; // The IP of your mysql server
$user = "youruser"; // The mysql user
$password   = "yourpassword"; // The mysql password
$database = "smrpg"; // The database name
?>

<!DOCTYPE html>
<html>
<head>
	<meta charset="utf-8">
	<title>SM:RPG Top 10</title>
	<style>
	.error {
		color: red;
		font-size: 20pt;
		border: 5px solid black;
	}
	</style>
</head>
<body>
	<h1>SM:RPG Top 10</h1>
	<?php
		$error = "";
		try {
			$db = new mysqli($host, $user, $password, $database);
			if ($db->connect_errno) {
                throw new Exception("Failed to connect to MySQL: (" . $db->connect_errno . ") " . $db->connect_error);
            }

			$db->set_charset('utf8mb4');
			
			// Get top 10 players
			$q = $db->query('SELECT player_id, name, (cast(\'76561197960265728\' as unsigned) + steamid) as steamid64, level, experience, credits, lastseen, lastreset FROM players ORDER BY level DESC, experience DESC LIMIT 10');
			$players = [];
			while ($player = $q->fetch_object()) {
				// fetch upgrade info of upgrades the player bought.
				$player->upgrades = [];
				$upgr_res = $db->query('SELECT u.shortname, pu.purchasedlevel, pu.selectedlevel FROM player_upgrades pu INNER JOIN upgrades u ON u.upgrade_id = pu.upgrade_id WHERE pu.player_id = ' . (int) $player->player_id . ' AND pu.purchasedlevel > 0 ORDER BY u.shortname');
				while ($upgrade = $upgr_res->fetch_object()) {
					$player->upgrades[] = $upgrade;
				}
				
				$players[] = $player;
			}
			$q->close();
			
			// Get last reset time and reason
			$q = $db->query('SELECT setting, value FROM settings WHERE setting = "last_reset" OR setting = "reset_reason"');
			$last_reset = [];
			while ($setting = $q->fetch_object()) {
				$last_reset[$setting->setting] = $setting->value;
			}
			$q->close();
		}
		catch(Exception $e) {
			$error = $e->getMessage();
		}
	?>
	<p>Listing the top 10 RPG players on the server.</p>
	<?php if (!empty($error)): ?>
	    <span class="error">Database error: <?= $error; ?></span>
	<?php else: ?>
	<table border="1">
		<tr>
			<th></th>
			<th>Name</th>
			<th>Level</th>
			<th>Experience</th>
			<th>Credits</th>
			<th>Last seen</th>
			<th>Last reset</th>
		</tr>
		<?php foreach($players as $index => $player): ?>
		<tr>
			<td><?= $index + 1; ?>.</td>
			<td><a href="http://steamcommunity.com/profiles/<?= $player->steamid64; ?>" title="Steam Profile"><?= htmlentities($player->name, ENT_QUOTES, "UTF-8"); ?></a></td>
			<td><?= $player->level; ?></td>
			<td><?= $player->experience; ?></td>
			<td><?= $player->credits; ?></td>
			<td><?= strftime("%d.%m.%Y %H:%M:%S", $player->lastseen); ?></td>
			<td><?= strftime("%d.%m.%Y %H:%M:%S", $player->lastreset); ?></td>
		</tr>
		<tr>
			<td></td>
			<td colspan="5">
				<table border="1">
					<tr>
						<th>Upgrade shortname</th>
						<th>Purchased level</th>
						<th>Selected level</th>
					</tr>
					<?php foreach($player->upgrades as $upgrade): ?>
					<tr>
						<td><?= $upgrade->shortname; ?></td>
						<td><?= $upgrade->purchasedlevel; ?></td>
						<td><?= $upgrade->selectedlevel; ?></td>
					</tr>
					<?php endforeach; ?>
				</table>
			</td>
		</tr>
		<?php endforeach; ?>
	</table>
	<?php if (isset($last_reset["last_reset"])): ?>
	    Server was last reset on <?= strftime("%d.%m.%Y %H:%M:%S", $last_reset["last_reset"]); ?>.<br />
	<?php endif; ?>
	<?php if (isset($last_reset["reset_reason"])): ?>
	    Reason: <?= $last_reset["reset_reason"]; ?>
	<?php endif; ?>
	<?php endif; ?>
</body>
</html>