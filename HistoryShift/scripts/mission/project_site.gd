class_name ProjectSite
extends Node3D
## 自由探索の「国家事業」の現場（data/projects/<era>.json）。名所に立つ看板。E で事業の内容を見て着手する（ActorInteract）。

var project: Dictionary = {}
var done := false
var _tag: Label3D
var _post: MeshInstance3D
var _ring: MeshInstance3D


static func spawn(parent: Node, pos: Vector3, p_project: Dictionary) -> ProjectSite:
	var s := ProjectSite.new()
	s.project = p_project
	parent.add_child(s)
	s.global_position = pos
	return s


func _ready() -> void:
	add_to_group("project_site")
	_post = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.4, 1.0, 0.12)
	_post.mesh = bm
	_post.position = Vector3(0, 1.6, 0)
	_post.material_override = Humanoid.mat(Color(0.55, 0.4, 0.25), 0.8)
	add_child(_post)
	var leg := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.06
	cm.bottom_radius = 0.06
	cm.height = 1.2
	leg.mesh = cm
	leg.position = Vector3(0, 0.6, 0)
	leg.material_override = Humanoid.mat(Color(0.35, 0.25, 0.15), 0.9)
	add_child(leg)
	_tag = Label3D.new()
	_tag.font = load("res://assets/fonts/NotoSansJP-Bold.ttf")
	_tag.font_size = 44
	_tag.pixel_size = 0.006
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.outline_size = 10
	_tag.position = Vector3(0, 2.6, 0)
	add_child(_tag)
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.2
	tm.outer_radius = 1.32
	_ring.mesh = tm
	_ring.position = Vector3(0, 0.05, 0)
	add_child(_ring)
	refresh()


func refresh() -> void:
	done = WarModel.is_done(Game.state.actions, str(project.get("id", "")))
	_tag.text = ("【国家事業・完了】" if done else "【国家事業】") + str(project.get("name", ""))
	_tag.modulate = Color(0.6, 0.9, 0.7) if done else Color(0.55, 0.85, 1.0)
	_ring.material_override = Effects.emissive(Color(0.4, 0.9, 0.6) if done else Color(0.35, 0.8, 1.0), 1.4)


func _process(dt: float) -> void:
	_ring.rotation.y += dt * 0.7
