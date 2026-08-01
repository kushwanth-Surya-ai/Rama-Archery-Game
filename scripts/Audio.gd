extends Node
## Lightweight audio bus autoload. Holds one looping BGM player and spawns
## throwaway players for one-shot SFX so overlapping shots/hits don't cut each
## other off. Call Audio.play_shoot() / play_draw() / play_hit() from anywhere.

const BgmStream := preload("res://assets/audio/bgm.wav")
const IntroStream := preload("res://assets/audio/war_horn_intro.mp3")  # war horn + drums — the opening-cinematic cue
const ArrivalStream := preload("res://assets/audio/the_arrival_varanasi.mp3")  # "The Arrival - Varanasi", reused only for the victory close-up sting
const INTRO_START := 0.0    # war horn is ~18s; start from the top and loop until Rama's entry (stop_intro)
const ARRIVAL_STING_START := 163.0    # 2:43 — replayed for the post-win close-up on Rama
const ARRIVAL_STING_SECONDS := 8.0    # runs to 2:51, then hard-stops
const DrawStream := preload("res://assets/audio/bow_draw.wav")
const ShootStream := preload("res://assets/audio/arrow_swish.mp3")
const HitStream := preload("res://assets/audio/arrow_hit.wav")
const RoarStream := preload("res://assets/audio/monster_roar.mp3")
const DeathStream := preload("res://assets/audio/monster_death.mp3")  # sewer-beast, pre-trimmed to 5s

var _bgm: AudioStreamPlayer
var _intro: AudioStreamPlayer


func _ready() -> void:
	# Background music: loop by replaying on finish (import-setting agnostic).
	_bgm = AudioStreamPlayer.new()
	_bgm.stream = BgmStream
	_bgm.volume_db = -18.0   # soft & low — sits well under the SFX
	_bgm.bus = "Master"
	add_child(_bgm)
	_bgm.finished.connect(_bgm.play)
	# BGM is NOT started here — it begins only once the player clicks "Play Now"
	# (see Main._on_welcome_done -> Audio.start_bgm()).

	# Intro cue: war horn + drums over the opening cinematic. Loops SEAMLESSLY inside the
	# MP3 decoder (stream.loop = true) — no finished→replay gap — so if the cinematic
	# outlasts the clip the music flows on unbroken until stop_intro() hands off to the BGM.
	_intro = AudioStreamPlayer.new()
	_intro.stream = IntroStream
	if _intro.stream is AudioStreamMP3:
		_intro.stream.loop = true
		_intro.stream.loop_offset = INTRO_START
	_intro.volume_db = -16.0   # present but soft — sits gently under the scene, not blaring
	_intro.bus = "Master"
	add_child(_intro)


# Kept for the stop-intro flag only; the stream now loops itself, so no replay hook.
var _intro_active := false


## War-horn cue for the opening cinematic. Loops from the top until stop_intro().
func play_intro() -> void:
	if _intro:
		_intro_active = true
		_intro.stop()
		_intro.play(INTRO_START)   # start at 1:35


## Stop the intro cue (called when the cinematic hands off to gameplay).
func stop_intro() -> void:
	_intro_active = false
	if _intro:
		_intro.stop()


## Start the looping background music. Called when the player commits from the
## welcome card. Safe to call more than once.
func start_bgm() -> void:
	if _bgm and not _bgm.playing:
		_bgm.play()


## Replay the arrival theme's 2:43–2:51 swell as the victory sting for the
## close-up on Rama's face. Uses a throwaway player (so it never disturbs the
## intro player) seeked to 2:43 and hard-cut at 2:47.
func play_arrival_sting() -> void:
	var p := AudioStreamPlayer.new()
	p.stream = ArrivalStream
	p.volume_db = -4.0   # lift it for the hero beat — this is the moment
	p.bus = "Master"
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play(ARRIVAL_STING_START)   # start at 2:43
	get_tree().create_timer(ARRIVAL_STING_SECONDS).timeout.connect(stop_player.bind(p))


func set_music_enabled(on: bool) -> void:
	if on:
		if not _bgm.playing:
			_bgm.play()
	else:
		_bgm.stop()


## Victory fanfare for Rama's close-up: the war-horn + drums cue lifted into a triumphant
## swell (deliberately NOT the arrival theme). Throwaway player, hard-cut after a few
## seconds so it carries the reveal + win card without looping on underneath.
const VICTORY_FANFARE_SECONDS := 9.0
var _fanfare: AudioStreamPlayer

func play_victory_fanfare() -> void:
	var p := AudioStreamPlayer.new()
	p.stream = IntroStream
	p.volume_db = -2.0   # lift it for the hero beat
	p.bus = "Master"
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play(0.0)
	_fanfare = p
	# Safety hard-cut if nothing stops it sooner (the win card calls stop_victory_fanfare).
	get_tree().create_timer(VICTORY_FANFARE_SECONDS).timeout.connect(stop_player.bind(p))


## Cut the victory fanfare — called the instant the win card appears so the music
## ends on the card rather than playing on underneath it.
func stop_victory_fanfare() -> void:
	if _fanfare and is_instance_valid(_fanfare):
		stop_player(_fanfare)
		_fanfare = null


func play_draw() -> void:
	_one_shot(DrawStream, -8.0, randf_range(0.97, 1.03))


func play_shoot() -> void:
	_one_shot(ShootStream, -3.0, randf_range(0.95, 1.06))


func play_hit() -> void:
	_one_shot(HitStream, -4.0, randf_range(0.92, 1.08))


## Bright arrow-flash zip on impact — the divine arrow's flash, NOT the old drum thud.
## Reuses the swish clip pitched up so the hit reads as a flash of light, not a thump.
func play_arrow_flash() -> void:
	_one_shot(ShootStream, -3.0, randf_range(1.15, 1.3))


## Monster shout/roar. `deep` = a louder, lower death roar; otherwise a pain roar
## as Rama's arrows pile up. Gating (how often) lives in GiantTarget, not here.
func play_monster_roar(deep := false) -> void:
	# Roar must read louder than the arrow SFX (shoot -3, hit -4): keep both the
	# death and pain roar above them so the monster always dominates the mix.
	var db := 4.0 if deep else 1.0
	var pitch := randf_range(0.72, 0.85) if deep else randf_range(0.9, 1.05)
	_one_shot(RoarStream, db, pitch)


## Death cry — plays when a monster is killed and topples. Uses the sewer-beast
## clip but hard-stops at 3s so only the first 3 seconds ever sound. Same sound
## for every monster's fall.
const DEATH_CLIP_SECONDS := 3.0

func play_monster_death() -> void:
	var p := AudioStreamPlayer.new()
	p.stream = DeathStream
	p.volume_db = 4.0
	p.bus = "Master"
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	# Cut the clip off at 3s regardless of its full length.
	get_tree().create_timer(DEATH_CLIP_SECONDS).timeout.connect(stop_player.bind(p))


## Stop and free a one-shot player early. Safe to call on an already-freed player —
## the param is UNTYPED on purpose: a safety timer can fire with a player that was
## already freed (e.g. the win card cut the fanfare first), and a typed AudioStreamPlayer
## param would throw "can't convert freed Object" before the validity check could run.
func stop_player(p) -> void:
	if is_instance_valid(p) and p is AudioStreamPlayer:
		p.stop()
		p.queue_free()


func _one_shot(stream: AudioStream, db: float, pitch: float) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	p.pitch_scale = pitch
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
