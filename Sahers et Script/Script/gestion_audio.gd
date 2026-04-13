extends Node

enum EngineState { OFF, STARTING, RUNNING, STOPPING, STOP_SOUND }
var state: EngineState = EngineState.OFF

var current_rpm: float = 0.0
var target_rpm:  float = 0.0

const RPM_RAMP_UP:   float = 0.6
const RPM_RAMP_DOWN: float = 0.35

@onready var audio_start: AudioStreamPlayer3D = $AudioStart
@onready var audio_stop:  AudioStreamPlayer3D = $AudioStop
@onready var audio_idle:  AudioStreamPlayer3D = $AudioIdle
@onready var audio_low:   AudioStreamPlayer3D = $AudioLow
@onready var audio_mid:   AudioStreamPlayer3D = $AudioMid
@onready var audio_high:  AudioStreamPlayer3D = $AudioHigh

func _ready() -> void:
	_start_loops()
	audio_stop.finished.connect(_on_stop_sound_finished)

func _start_loops() -> void:
	for ch in [audio_idle, audio_low, audio_mid, audio_high]:
		ch.volume_db = -80.0
		ch.play()

# ── API publique ──────────────────────────────────────────────────────────────

func start_engine() -> void:
	if state != EngineState.OFF:
		return
	state = EngineState.STARTING
	_mute_all_loops()
	audio_start.play()
	await audio_start.finished
	if state == EngineState.STARTING:
		current_rpm = 0.08
		target_rpm  = 0.08
		state = EngineState.RUNNING

func stop_engine() -> void:
	if state != EngineState.RUNNING:
		return
	# On passe juste en STOPPING, audio_process fait descendre le RPM
	state = EngineState.STOPPING
	target_rpm = 0.0

func set_throttle(throttle: float) -> void:
	if state != EngineState.RUNNING:
		return
	target_rpm = lerpf(0.08, 1.0, throttle)

# ── Appelé chaque frame depuis buoyancy.gd ───────────────────────────────────

func audio_process(delta: float) -> void:
	match state:
		EngineState.RUNNING:
			var ramp := RPM_RAMP_UP if target_rpm > current_rpm else RPM_RAMP_DOWN
			current_rpm = move_toward(current_rpm, target_rpm, ramp * delta)
			_update_layers()

		EngineState.STOPPING:
			current_rpm = move_toward(current_rpm, 0.0, RPM_RAMP_DOWN * delta)
			_update_layers()
			# Quand le RPM est assez bas → coupe les boucles et joue le son d'arrêt
			if current_rpm <= 0.02:
				current_rpm = 0.0
				_mute_all_loops()
				state = EngineState.STOP_SOUND
				audio_stop.play()

		EngineState.STOP_SOUND:
			pass  # on attend le signal finished

# ── Crossfade layers ──────────────────────────────────────────────────────────

func _update_layers() -> void:
	var rpm := current_rpm
	audio_idle.volume_db = linear_to_db(_bell(rpm, 0.0,  0.18))
	audio_low.volume_db  = linear_to_db(_bell(rpm, 0.33, 0.22))
	audio_mid.volume_db  = linear_to_db(_bell(rpm, 0.66, 0.22))
	audio_high.volume_db = linear_to_db(_bell(rpm, 1.0,  0.22))
	var p := lerpf(0.92, 1.12, rpm)
	for ch in [audio_idle, audio_low, audio_mid, audio_high]:
		ch.pitch_scale = p

func _bell(rpm: float, center: float, width: float) -> float:
	return clampf(1.0 - abs(rpm - center) / width, 0.0, 1.0)

func _mute_all_loops() -> void:
	for ch in [audio_idle, audio_low, audio_mid, audio_high]:
		ch.volume_db = -80.0

func _on_stop_sound_finished() -> void:
	state = EngineState.OFF
