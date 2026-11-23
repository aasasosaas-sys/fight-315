class_name EraStyles
extends RefCounted
## 時代ごとの見た目パラメータ（空・太陽・霧・色調・植生・道・建築様式）。

## HDRI 内の太陽位置（tools で測定: u≈0.6 → 方位 216°）
const HDRI_SUN := {
	"day": {"az": 216.0, "elev": 29.5},
	"clear": {"az": 216.5, "elev": 52.0},
	"hazy": {"az": 216.0, "elev": 12.7},
	"evening": {"az": 218.0, "elev": 9.8},
}


static func get_style(era_id: String) -> Dictionary:
	var s := _base()
	match era_id:
		"jomon_kofun":
			s.merge({
				"rot": 0, "sky": "day", "sun_color": Color(1.0, 0.95, 0.86), "sun_energy": 1.45,
				"fog_color": Color(0.62, 0.72, 0.70), "fog_density": 0.0011, "vol_fog": 0.006,
				"vol_albedo": Color(0.86, 0.92, 0.88),
				"saturation": 1.12, "contrast": 1.04, "brightness": 1.0,
				"grass_tint": Color(0.86, 1.02, 0.78), "grass_base": Color(0.10, 0.20, 0.05), "grass_tip": Color(0.42, 0.62, 0.18),
				"forest": 0.62, "trees": {"broadleaf": 0.5, "cedar": 0.25, "pine": 0.1, "bamboo": 0.15},
				"road": "dirt", "plaza": "dirt", "street": "dirt",
				"lamp": "none",
			}, true)
		"asuka_nara":
			s.merge({
				"rot": 1, "sky": "clear", "sun_color": Color(1.0, 0.96, 0.9), "sun_energy": 1.5,
				"fog_color": Color(0.66, 0.74, 0.84), "fog_density": 0.0009, "vol_fog": 0.004,
				"vol_albedo": Color(0.9, 0.92, 0.96),
				"saturation": 1.06, "contrast": 1.03,
				"grass_tint": Color(0.92, 1.0, 0.82), "grass_base": Color(0.12, 0.21, 0.06), "grass_tip": Color(0.46, 0.62, 0.22),
				"forest": 0.5, "trees": {"broadleaf": 0.35, "cedar": 0.3, "pine": 0.25, "bamboo": 0.1},
				"road": "dirt", "plaza": "sand", "street": "dirt", "lamp": "none",
			}, true)
		"heian":
			s.merge({
				"rot": 2, "sky": "hazy", "sun_color": Color(1.0, 0.86, 0.72), "sun_energy": 1.35,
				"fog_color": Color(0.86, 0.78, 0.78), "fog_density": 0.0016, "vol_fog": 0.008,
				"vol_albedo": Color(1.0, 0.9, 0.9),
				"saturation": 0.92, "contrast": 0.97, "brightness": 1.04,
				"grass_tint": Color(0.98, 1.0, 0.86), "grass_base": Color(0.14, 0.21, 0.08), "grass_tip": Color(0.55, 0.64, 0.30),
				"forest": 0.5, "trees": {"broadleaf": 0.25, "cedar": 0.2, "pine": 0.2, "sakura": 0.25, "bamboo": 0.1},
				"road": "dirt", "plaza": "sand", "street": "sand", "lamp": "none",
			}, true)
		"kamakura_muromachi":
			s.merge({
				"rot": 3, "sky": "day", "sun_color": Color(1.0, 0.94, 0.84), "sun_energy": 1.45,
				"fog_color": Color(0.66, 0.72, 0.76), "fog_density": 0.0011, "vol_fog": 0.005,
				"saturation": 1.0, "contrast": 1.05,
				"grass_tint": Color(0.9, 0.98, 0.8),
				"forest": 0.55, "trees": {"cedar": 0.4, "pine": 0.25, "broadleaf": 0.2, "bamboo": 0.15},
				"road": "dirt", "plaza": "sand", "street": "dirt", "lamp": "none",
			}, true)
		"sengoku":
			s.merge({
				"rot": 1, "sky": "hazy", "sun_color": Color(1.0, 0.8, 0.6), "sun_energy": 1.6,
				"fog_color": Color(0.7, 0.62, 0.55), "fog_density": 0.0015, "vol_fog": 0.010,
				"vol_albedo": Color(1.0, 0.88, 0.78),
				"saturation": 1.02, "contrast": 1.12, "brightness": 0.98,
				"grass_tint": Color(0.98, 0.96, 0.78), "grass_base": Color(0.13, 0.19, 0.06), "grass_tip": Color(0.55, 0.58, 0.24),
				"forest": 0.5, "trees": {"pine": 0.35, "cedar": 0.3, "broadleaf": 0.2, "bamboo": 0.15},
				"road": "dirt", "plaza": "dirt", "street": "dirt", "lamp": "lantern",
			}, true)
		"edo":
			s.merge({
				"rot": 0, "sky": "clear", "sun_color": Color(1.0, 0.92, 0.8), "sun_energy": 1.5,
				"fog_color": Color(0.78, 0.74, 0.68), "fog_density": 0.001, "vol_fog": 0.004,
				"saturation": 1.05, "contrast": 1.04, "brightness": 1.02,
				"grass_tint": Color(1.0, 0.98, 0.82),
				"forest": 0.45, "trees": {"pine": 0.35, "sakura": 0.2, "cedar": 0.25, "broadleaf": 0.1, "bamboo": 0.1},
				"road": "dirt", "plaza": "dirt", "street": "dirt", "lamp": "lantern",
			}, true)
		"meiji_taisho":
			s.merge({
				"rot": 2, "sky": "day", "sun_color": Color(1.0, 0.95, 0.88), "sun_energy": 1.4,
				"fog_color": Color(0.7, 0.72, 0.74), "fog_density": 0.0014, "vol_fog": 0.006,
				"saturation": 0.84, "contrast": 1.06, "brightness": 1.0,
				"grass_tint": Color(0.92, 0.96, 0.84),
				"forest": 0.4, "trees": {"broadleaf": 0.35, "pine": 0.25, "sakura": 0.15, "cedar": 0.2, "bamboo": 0.05},
				"road": "cobble", "plaza": "cobble", "street": "cobble", "lamp": "gas",
			}, true)
		"showa":
			s.merge({
				"rot": 3, "sky": "evening", "sun_color": Color(1.0, 0.72, 0.46), "sun_energy": 1.7,
				"fog_color": Color(0.82, 0.66, 0.54), "fog_density": 0.0014, "vol_fog": 0.009,
				"vol_albedo": Color(1.0, 0.86, 0.72),
				"saturation": 1.04, "contrast": 1.05, "brightness": 1.02,
				"grass_tint": Color(1.0, 0.94, 0.8),
				"forest": 0.38, "trees": {"broadleaf": 0.45, "pine": 0.2, "sakura": 0.15, "cedar": 0.2},
				"road": "asphalt", "plaza": "concrete", "street": "asphalt", "lamp": "electric",
			}, true)
	return s


static func _base() -> Dictionary:
	return {
		"rot": 0, "sky": "day", "sun_color": Color(1, 0.95, 0.88), "sun_energy": 1.4,
		"fog_color": Color(0.7, 0.75, 0.8), "fog_density": 0.001, "vol_fog": 0.005,
		"vol_albedo": Color(0.92, 0.94, 0.96),
		"saturation": 1.0, "contrast": 1.0, "brightness": 1.0,
		"grass_tint": Color(1, 1, 1), "grass_base": Color(0.11, 0.2, 0.06), "grass_tip": Color(0.45, 0.6, 0.2),
		"forest": 0.5, "trees": {"broadleaf": 0.4, "cedar": 0.3, "pine": 0.3},
		"road": "dirt", "plaza": "dirt", "street": "dirt", "lamp": "none",
	}
