class_name WeaponModels
extends RefCounted
## 手に持つ武器の簡単な形（Humanoid.part のプリミティブ）。右手の Weapon ノードの下に付ける（+Z が刃先・銃口）。
## 品質が高いほど刃が明るく光る（名工の地鉄）。


static func build(id: String, q := 0.5) -> Node3D:
	var root := Node3D.new()
	root.name = "ArmsModel"
	var steel := Humanoid.mat(Color(0.72, 0.74, 0.78).lerp(Color(0.92, 0.94, 1.0), q), 0.25 - 0.15 * q, 0.95)
	var dark := Humanoid.mat(Color(0.1, 0.1, 0.11), 0.4, 0.8)
	var wood := Humanoid.mat(Color(0.36, 0.22, 0.12), 0.7)
	var ito := Humanoid.mat(Color(0.12, 0.1, 0.2), 0.9)       # 柄巻き
	var gold := Humanoid.mat(Color(0.78, 0.62, 0.25), 0.3, 0.9)
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	match id:
		"tachi", "uchigatana", "wakizashi", "guntou", "chokuto", "tekken":
			var blade_len := {"tachi": 0.8, "uchigatana": 0.72, "wakizashi": 0.48, "guntou": 0.72, "chokuto": 0.75, "tekken": 0.6}.get(id, 0.7) as float
			var curve := 0.0 if id in ["chokuto", "tekken"] else (8.0 if id == "tachi" else 5.0)
			Humanoid.part(root, "box", ito, Vector3(0, 0, -0.06), Vector3(0.035, 0.035, 0.24))
			Humanoid.part(root, "cyl", gold if id != "tekken" else dark, Vector3(0, 0, 0.07), Vector3(0.09, 0.012, 0.07), Vector3(90, 0, 0))  # 鍔
			var blade := Node3D.new()
			blade.position = Vector3(0, 0, 0.08)
			blade.rotation_degrees.x = -curve
			root.add_child(blade)
			Humanoid.part(blade, "box", steel, Vector3(0, 0.0, blade_len * 0.5), Vector3(0.008 if id != "tekken" else 0.012, 0.032, blade_len))
			Humanoid.part(blade, "box", Humanoid.mat(Color(1, 1, 1), 0.1, 1.0, 0.3 + q * 1.2), Vector3(0, -0.017, blade_len * 0.5), Vector3(0.004, 0.004, blade_len * 0.97))  # 刃文
		"yari", "naginata":
			var pole := 2.0 if id == "yari" else 1.6
			Humanoid.part(root, "cyl", wood, Vector3(0, 0, pole * 0.25), Vector3(0.03, pole, 0.03), Vector3(90, 0, 0))
			if id == "yari":
				Humanoid.part(root, "box", steel, Vector3(0, 0, pole * 0.75 + 0.12), Vector3(0.025, 0.025, 0.25))
			else:
				Humanoid.part(root, "box", steel, Vector3(0, 0.02, pole * 0.75 + 0.2), Vector3(0.01, 0.05, 0.42), Vector3(-8, 0, 0))
		"jutte":
			Humanoid.part(root, "cyl", dark, Vector3(0, 0, 0.18), Vector3(0.018, 0.45, 0.018), Vector3(90, 0, 0))
			Humanoid.part(root, "box", dark, Vector3(0, 0.03, 0.05), Vector3(0.01, 0.06, 0.08))
		"wakyu", "tankyu":
			var h := 1.1 if id == "wakyu" else 0.7
			for i in 7:
				var a := (i - 3) / 3.0
				Humanoid.part(root, "box", wood, Vector3(0, a * h * 0.5, 0.12 - absf(a) * absf(a) * 0.14), Vector3(0.025, h / 6.5, 0.02), Vector3(a * 25.0, 0, 0))
			Humanoid.part(root, "box", Humanoid.mat(Color(0.95, 0.92, 0.85), 0.8), Vector3(0, 0, -0.03), Vector3(0.004, h, 0.004))
			muzzle.position = Vector3(0, 0, 0.15)
		"hinawaju", "murataju", "arisaka38":
			var ln := {"hinawaju": 1.25, "murataju": 1.2, "arisaka38": 1.25}.get(id, 1.2) as float
			Humanoid.part(root, "box", wood, Vector3(0, -0.02, ln * 0.25), Vector3(0.05, 0.06, ln * 0.75))
			Humanoid.part(root, "cyl", dark, Vector3(0, 0.02, ln * 0.45), Vector3(0.022, ln * 0.85, 0.022), Vector3(90, 0, 0))
			if id == "hinawaju":
				Humanoid.part(root, "box", gold, Vector3(0.03, 0.03, 0.05), Vector3(0.02, 0.03, 0.06))   # 火挟み
			else:
				Humanoid.part(root, "cyl", dark, Vector3(0.04, 0.02, 0.02), Vector3(0.02, 0.06, 0.02), Vector3(0, 0, 90))  # 遊底
			muzzle.position = Vector3(0, 0.02, ln * 0.88)
		"pistol14":
			Humanoid.part(root, "box", dark, Vector3(0, 0.03, 0.08), Vector3(0.03, 0.04, 0.2))
			Humanoid.part(root, "box", wood, Vector3(0, -0.04, -0.01), Vector3(0.028, 0.1, 0.04), Vector3(-15, 0, 0))
			muzzle.position = Vector3(0, 0.03, 0.19)
		"lmg96":
			Humanoid.part(root, "box", dark, Vector3(0, 0.0, 0.3), Vector3(0.06, 0.08, 0.8))
			Humanoid.part(root, "cyl", dark, Vector3(0, 0.02, 0.8), Vector3(0.025, 0.5, 0.025), Vector3(90, 0, 0))
			Humanoid.part(root, "box", dark, Vector3(0, 0.1, 0.32), Vector3(0.03, 0.12, 0.1), Vector3(-20, 0, 0))   # 上の弾倉
			muzzle.position = Vector3(0, 0.02, 1.05)
		"jikuju":
			Humanoid.part(root, "box", dark, Vector3(0, 0, 0.18), Vector3(0.07, 0.1, 0.42))
			Humanoid.part(root, "box", Humanoid.mat(Effects.CYAN, 0.3, 0.0, 1.5), Vector3(0, 0.04, 0.2), Vector3(0.075, 0.02, 0.3))
			muzzle.position = Vector3(0, 0.03, 0.42)
		_:
			pass   # 素手：何も持たない
	root.add_child(muzzle)
	return root
