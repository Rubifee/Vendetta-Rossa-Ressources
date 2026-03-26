extends Label


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Engine.max_fps = 0
	print("ok")


# Called every frame. 'delta' is the elapsed time since the previous frame

func _process(_delta):
	text = "FPS: " + str(Engine.get_frames_per_second())
