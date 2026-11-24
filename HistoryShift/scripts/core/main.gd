extends Node
## エントリーポイント。画面遷移は Flow（scripts/ui/flow.gd）が担当する。

func _ready() -> void:
	var flow_script := load("res://scripts/ui/flow.gd")
	if flow_script:
		var flow: Node = flow_script.new()
		flow.name = "Flow"
		add_child(flow)
