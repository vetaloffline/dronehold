class_name Settings
extends RefCounted
## Player settings that survive restarts, in user://settings.cfg (ConfigFile).
## Sound off = the Master audio bus is muted, so every sound in the game goes quiet at once.

const PATH := "user://settings.cfg"


static func sound_on() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(PATH)  # no file yet = defaults
	return cfg.get_value("audio", "sound_on", true)


static func set_sound_on(on: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("audio", "sound_on", on)
	var err := cfg.save(PATH)
	if err != OK:
		push_warning("settings: cannot save %s (error %d)" % [PATH, err])
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), not on)


## Call once at start (the menu does it).
static func apply() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), not sound_on())
