extends SceneTree

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	assert(args.size() == 1)
	var pack = PCKPacker.new()
	assert(pack.pck_start(args[0]) == OK and pack.flush() == OK)
	print("PASS: empty data-mod payload")
	quit()
