extends AudioStreamPlayer
## 背景音乐：三首随机播放，尽量不连着重复同一首。

const TRACKS := [
	"res://audio/music_01.wav",
	"res://audio/music_02.wav",
	"res://audio/music_03.wav",
]
const VOLUME_DB := -17.0

var _last := -1


func _ready() -> void:
	volume_db = VOLUME_DB
	process_mode = Node.PROCESS_MODE_ALWAYS
	finished.connect(_next)
	_next()


## 退出时释放音频流，否则引擎会报 "resources still in use at exit"
func _exit_tree() -> void:
	stop()
	stream = null


func _next() -> void:
	if TRACKS.is_empty():
		return
	var idx := 0
	if TRACKS.size() > 1:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		idx = rng.randi() % TRACKS.size()
		var guard := 0
		while idx == _last and guard < 12:
			idx = rng.randi() % TRACKS.size()
			guard += 1
	var st: AudioStream = load(TRACKS[idx])
	if st == null:
		return
	_last = idx
	stream = st
	play()
