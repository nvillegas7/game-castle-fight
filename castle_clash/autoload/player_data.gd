## Persistent player stats and progression. Saved to user://player_data.cfg.
extends Node

const SAVE_PATH := "user://player_data.cfg"
const TROPHY_WIN := 30
const TROPHY_LOSE := -20

var trophies: int = 0
var games_played: int = 0
var games_won: int = 0
var total_buildings: int = 0
var total_waves: int = 0
var kingdom_wins: int = 0
var horde_wins: int = 0
var last_win_timestamp: int = 0  # Unix timestamp
var first_win_bonus_available: bool = false

# Audio volume settings (0.0 = mute, 1.0 = full)
var music_volume: float = 0.8
var sfx_volume: float = 1.0
var ui_volume: float = 1.0


func _ready() -> void:
	_load()
	_check_first_win_bonus()
	_apply_audio_volumes()


func set_music_volume(vol: float) -> void:
	music_volume = clampf(vol, 0.0, 1.0)
	_apply_bus_volume("Music", music_volume)
	_save()

func set_sfx_volume(vol: float) -> void:
	sfx_volume = clampf(vol, 0.0, 1.0)
	_apply_bus_volume("SFX", sfx_volume)
	_save()

func set_ui_volume(vol: float) -> void:
	ui_volume = clampf(vol, 0.0, 1.0)
	_apply_bus_volume("UI", ui_volume)
	_save()

func _apply_bus_volume(bus_name: String, vol: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(vol))
		AudioServer.set_bus_mute(idx, vol <= 0.0)

func _apply_audio_volumes() -> void:
	_apply_bus_volume("Music", music_volume)
	_apply_bus_volume("SFX", sfx_volume)
	_apply_bus_volume("UI", ui_volume)


## Generic key-value getter for persistent data (used by tutorial, perks, etc.)
func get_value(key: String, default_value = null):
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		return config.get_value("data", key, default_value)
	return default_value


## Generic key-value setter for persistent data.
func set_value(key: String, value) -> void:
	var config := ConfigFile.new()
	config.load(SAVE_PATH)  # Load existing, ignore error if new
	config.set_value("data", key, value)
	config.save(SAVE_PATH)


func record_match_result(won: bool, faction: StringName, waves: int, buildings: int) -> void:
	games_played += 1
	total_waves += waves
	total_buildings += buildings

	if won:
		games_won += 1
		trophies = max(0, trophies + TROPHY_WIN)
		last_win_timestamp = int(Time.get_unix_time_from_system())
		first_win_bonus_available = false
		match faction:
			&"kingdom":
				kingdom_wins += 1
			&"horde":
				horde_wins += 1
	else:
		trophies = max(0, trophies + TROPHY_LOSE)

	_save()


func get_rank_name() -> String:
	if trophies < 100:
		return "Recruit"
	elif trophies < 300:
		return "Soldier"
	elif trophies < 600:
		return "Captain"
	elif trophies < 1000:
		return "Commander"
	elif trophies < 1500:
		return "General"
	else:
		return "Legend"


func get_faction_mastery(faction: StringName) -> String:
	var wins: int = 0
	match faction:
		&"kingdom": wins = kingdom_wins
		&"horde": wins = horde_wins
	if wins >= 25:
		return "Master"
	elif wins >= 10:
		return "Veteran"
	elif wins >= 5:
		return "Skilled"
	elif wins >= 1:
		return "Novice"
	return ""


func _check_first_win_bonus() -> void:
	if last_win_timestamp == 0:
		first_win_bonus_available = true
		return
	var now: int = int(Time.get_unix_time_from_system())
	first_win_bonus_available = (now - last_win_timestamp) > 86400  # 24 hours


func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("stats", "trophies", trophies)
	config.set_value("stats", "games_played", games_played)
	config.set_value("stats", "games_won", games_won)
	config.set_value("stats", "total_buildings", total_buildings)
	config.set_value("stats", "total_waves", total_waves)
	config.set_value("stats", "kingdom_wins", kingdom_wins)
	config.set_value("stats", "horde_wins", horde_wins)
	config.set_value("stats", "last_win_timestamp", last_win_timestamp)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("audio", "ui_volume", ui_volume)
	config.save(SAVE_PATH)


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	trophies = config.get_value("stats", "trophies", 0)
	games_played = config.get_value("stats", "games_played", 0)
	games_won = config.get_value("stats", "games_won", 0)
	total_buildings = config.get_value("stats", "total_buildings", 0)
	total_waves = config.get_value("stats", "total_waves", 0)
	kingdom_wins = config.get_value("stats", "kingdom_wins", 0)
	horde_wins = config.get_value("stats", "horde_wins", 0)
	last_win_timestamp = config.get_value("stats", "last_win_timestamp", 0)
	music_volume = config.get_value("audio", "music_volume", 0.8)
	sfx_volume = config.get_value("audio", "sfx_volume", 1.0)
	ui_volume = config.get_value("audio", "ui_volume", 1.0)
