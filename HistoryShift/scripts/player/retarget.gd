class_name Retarget
extends RefCounted
## 骨格の階層が違う人型（VRM など：肩・首・上胸の骨がある）へアニメーションを焼き直す。
## 元と先の両方が T ポーズ基準（人型プロファイルの向き）である前提で、
## 各骨の「休止姿勢からのワールド回転差」を写し、先の骨格の階層でローカル回転に戻す。

const SKEL := "%GeneralSkeleton:"
static var _src_cache := {}    # 元 glb のパス → {rest: name→Basis(global), parent: name→name, order: [name]}
static var _lib_cache := {}    # 先骨格のキー → AnimationLibrary


static func _skel_info(sk: Skeleton3D) -> Dictionary:
	var rest := {}
	var parent := {}
	var local := {}
	var order: Array = []
	for i in sk.get_bone_count():
		var n := sk.get_bone_name(i)
		order.append(n)
		var p := sk.get_bone_parent(i)
		parent[n] = sk.get_bone_name(p) if p >= 0 else ""
		rest[n] = sk.get_bone_global_rest(i).basis.get_rotation_quaternion()
		local[n] = sk.get_bone_rest(i).basis.get_rotation_quaternion()
	return {"rest": rest, "parent": parent, "local": local, "order": order}


static func _src_info(path: String) -> Dictionary:
	if _src_cache.has(path):
		return _src_cache[path]
	var inst: Node = (load(path) as PackedScene).instantiate()
	var sks := inst.find_children("*", "Skeleton3D", true, false)
	var info := _skel_info(sks[0]) if sks.size() > 0 else {}
	inst.free()
	_src_cache[path] = info
	return info


## 先の骨格向けに焼き直したライブラリ（骨格の形ごとにキャッシュ）
static func library_for(tgt: Skeleton3D, key: String) -> AnimationLibrary:
	if _lib_cache.has(key):
		return _lib_cache[key]
	var src_lib := Humanoid.anim_library()
	var ti := _skel_info(tgt)
	var out := AnimationLibrary.new()
	for an in src_lib.get_animation_list():
		var a := src_lib.get_animation(an)
		var sp: String = a.get_meta("src", "")
		if sp == "":
			continue
		out.add_animation(an, _convert(a, _src_info(sp), ti))
	_lib_cache[key] = out
	return out


static func _convert(a: Animation, si: Dictionary, ti: Dictionary) -> Animation:
	var rot_tracks := {}
	var times := {}
	var pos_track := -1
	for t in a.get_track_count():
		var p := String(a.track_get_path(t))
		if not p.begins_with(SKEL):
			continue
		var bone := p.substr(SKEL.length())
		if a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			rot_tracks[bone] = t
		elif a.track_get_type(t) == Animation.TYPE_POSITION_3D and bone == "Hips":
			pos_track = t
		else:
			continue
		for k in a.track_get_key_count(t):
			times[snappedf(a.track_get_key_time(t, k), 0.0001)] = true
	var tlist: Array = times.keys()
	tlist.sort()
	var b := Animation.new()
	b.length = a.length
	b.loop_mode = a.loop_mode
	var srest: Dictionary = si.rest
	var slocal: Dictionary = si.local
	var sparent: Dictionary = si.parent
	var trest: Dictionary = ti.rest
	var tlocal: Dictionary = ti.local
	var tparent: Dictionary = ti.parent
	# 先の骨のうち、元にも同名の骨がある（＝動きを写す）もの
	var mapped := {}    # 先の骨 → 動きを借りる元の骨
	for n in ti.order:
		if srest.has(n):
			mapped[n] = n
		else:
			var al := _alias(n)
			if al != "" and srest.has(al):
				mapped[n] = al
	var out_tracks := {}
	for n in ti.order:
		if mapped.has(n) or _has_mapped_descendant(n, ti, mapped):
			var tr := b.add_track(Animation.TYPE_ROTATION_3D)
			b.track_set_path(tr, SKEL + n)
			out_tracks[n] = tr
	var out_pos := -1
	if pos_track >= 0:
		out_pos = b.add_track(Animation.TYPE_POSITION_3D)
		b.track_set_path(out_pos, SKEL + "Hips")
	for time in tlist:
		# 元：ワールド回転と休止姿勢からの差
		var sg := {}
		var delta := {}
		for n in si.order:
			var lq: Quaternion = slocal[n]
			if rot_tracks.has(n):
				lq = a.rotation_track_interpolate(rot_tracks[n], time)
			var pn: String = sparent[n]
			var g: Quaternion = (sg[pn] * lq) if pn != "" and sg.has(pn) else lq
			sg[n] = g
			delta[n] = g * (srest[n] as Quaternion).inverse()
		# 先：差を当ててから自分の階層でローカルへ
		var tg := {}
		for n in ti.order:
			var pn2: String = tparent[n]
			var pg: Quaternion = tg[pn2] if pn2 != "" and tg.has(pn2) else Quaternion.IDENTITY
			var g2: Quaternion
			if mapped.has(n):
				g2 = (delta[mapped[n]] as Quaternion) * (trest[n] as Quaternion)
			else:
				g2 = pg * (tlocal[n] as Quaternion)
			tg[n] = g2
			if out_tracks.has(n):
				b.rotation_track_insert_key(out_tracks[n], time, (pg.inverse() * g2).normalized())
		if out_pos >= 0:
			b.position_track_insert_key(out_pos, time, a.position_track_interpolate(pos_track, time))
	return b


## VRoid のねじれ補助骨（J_Aim_L_UpperArm / J_Roll_R_LowerArm など）→ 対応する人型の骨
static func _alias(n: String) -> String:
	var re := RegEx.create_from_string("^J_(?:Aim|Roll|Twist)_([LR])_(?:Tops)?(\\w+?)(?:_end)?$")
	var m := re.search(n)
	if m == null:
		return ""
	return ("Left" if m.get_string(1) == "L" else "Right") + m.get_string(2)


static func _has_mapped_descendant(n: String, ti: Dictionary, mapped: Dictionary) -> bool:
	# 肩・首など：子が動くだけなので自分は休止姿勢のままでよい
	return false
