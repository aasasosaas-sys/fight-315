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


static var _warm_state := {}   # 先骨格のキー → 焼き直しの途中 {out, names, i, ti}


## 先の骨格向けに焼き直したライブラリ（骨格の形ごとにキャッシュ。全員で共有する）
static func library_for(tgt: Skeleton3D, key: String) -> AnimationLibrary:
	if not _lib_cache.has(key):
		warm(tgt, key, -1)
	return _lib_cache[key]


## もう焼き直しが済んでいるか
static func is_ready(key: String) -> bool:
	return _lib_cache.has(key)


## 少しずつ焼き直す（budget_usec を使い切ったら途中で戻る。-1 なら最後まで）。済んだら true
## 人物を組み立てる前に何フレームかに分けて呼ぶと、初めての素体でフレームが止まらない
static func warm(tgt: Skeleton3D, key: String, budget_usec: int) -> bool:
	if _lib_cache.has(key):
		return true
	var t0 := Time.get_ticks_usec()
	var src_lib := Humanoid.anim_library()
	var w: Dictionary = _warm_state.get(key, {})
	if w.is_empty():
		w = {"out": AnimationLibrary.new(), "names": Array(src_lib.get_animation_list()), "i": 0, "ti": _skel_info(tgt)}
		_warm_state[key] = w
	var names: Array = w["names"]
	var out: AnimationLibrary = w["out"]
	while int(w["i"]) < names.size():
		var an: StringName = names[int(w["i"])]
		w["i"] = int(w["i"]) + 1
		var a := src_lib.get_animation(an)
		var sp: String = a.get_meta("src", "")
		if sp != "":
			out.add_animation(an, _convert(a, _src_info(sp), w["ti"]))
		if budget_usec >= 0 and Time.get_ticks_usec() - t0 > budget_usec:
			break
	if int(w["i"]) >= names.size():
		_lib_cache[key] = out
		_warm_state.erase(key)
		return true
	return false


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
	# 計算の要る骨だけ：先は「動きを写す骨とその祖先」、元は「写される骨とその祖先」（髪・服の揺れ骨などは飛ばす。結果は同じ）
	var t_need := {}
	for n in mapped:
		var c: String = n
		while c != "" and not t_need.has(c):
			t_need[c] = true
			c = tparent.get(c, "")
	var t_order: Array = ti.order.filter(func(n: String) -> bool: return t_need.has(n))
	var s_need := {}
	for n in mapped:
		var c2: String = mapped[n]
		while c2 != "" and not s_need.has(c2):
			s_need[c2] = true
			c2 = sparent.get(c2, "")
	var s_order: Array = si.order.filter(func(n: String) -> bool: return s_need.has(n))
	var out_pos := -1
	if pos_track >= 0:
		out_pos = b.add_track(Animation.TYPE_POSITION_3D)
		b.track_set_path(out_pos, SKEL + "Hips")
	for time in tlist:
		# 元：ワールド回転と休止姿勢からの差
		var sg := {}
		var delta := {}
		for n in s_order:
			var lq: Quaternion = slocal[n]
			if rot_tracks.has(n):
				lq = a.rotation_track_interpolate(rot_tracks[n], time)
			var pn: String = sparent[n]
			var g: Quaternion = (sg[pn] * lq) if pn != "" and sg.has(pn) else lq
			sg[n] = g
			delta[n] = g * (srest[n] as Quaternion).inverse()
		# 先：差を当ててから自分の階層でローカルへ
		var tg := {}
		for n in t_order:
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
