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
				"fog_color": Color(0.86, 0.8, 0.8), "fog_density": 0.0011, "vol_fog": 0.006,
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
				"rot": 3, "sky": "day", "sun_color": Color(1.0, 0.9, 0.76), "sun_energy": 1.6,
				"fog_color": Color(0.8, 0.8, 0.78), "fog_density": 0.0012, "vol_fog": 0.006,
				"vol_albedo": Color(0.96, 0.94, 0.9),
				"saturation": 1.04, "contrast": 1.05, "brightness": 1.02,
				"grass_tint": Color(1.0, 0.94, 0.8),
				"forest": 0.38, "trees": {"broadleaf": 0.45, "pine": 0.2, "sakura": 0.15, "cedar": 0.2},
				"road": "asphalt", "plaza": "concrete", "street": "asphalt", "lamp": "electric",
			}, true)
	s.merge(_anime(era_id), true)
	return s


## アニメ背景調のパレット（空・雲・セル影・地面・水・ポスト）
static func _anime(era_id: String) -> Dictionary:
	var a := {
		"sun_az": 216.0, "sun_elev": 38.0,
		"sky_zenith": Color(0.18, 0.45, 0.88), "sky_horizon": Color(0.6, 0.8, 0.97), "sky_haze": Color(0.86, 0.93, 0.99),
		"sunset_color": Color(1.0, 0.58, 0.32), "sunset_amount": 1.0,
		"cloud_light": Color(1.0, 1.0, 1.0), "cloud_mid": Color(0.88, 0.92, 0.99), "cloud_shade": Color(0.62, 0.68, 0.86),
		"cloud_cover": 0.45, "tower": 0.6, "cirrus": 0.4, "cloud_seed": 0.0,
		"shade_color": Color(0.5, 0.56, 0.86), "shade_strength": 0.5, "ambient_energy": 0.45,
		"grass_a": Color(0.42, 0.66, 0.24), "grass_b": Color(0.28, 0.56, 0.28), "grass_c": Color(0.68, 0.78, 0.32),
		"tip_light": Color(0.8, 0.9, 0.45),
		"forest_col": Color(0.18, 0.38, 0.24), "dirt_col": Color(0.76, 0.62, 0.44), "sand_col": Color(0.95, 0.88, 0.7),
		"rock_col": Color(0.6, 0.52, 0.44), "rock_col2": Color(0.42, 0.4, 0.42), "field_col": Color(0.46, 0.68, 0.28),
		"water_shallow": Color(0.3, 0.78, 0.82), "water_deep": Color(0.1, 0.42, 0.7),
		"aerial": Color(0.7, 0.82, 0.96), "aerial_density": 0.0016,
		"exposure": 1.0, "glow": 0.6, "line": 0.85, "rays": 0.3, "glare": 0.3,
		# 塗りの色味（漆喰の白は真っ白にしない）・低い霞
		"plaster_tint": Color(0.97, 0.95, 0.9), "wood_tint": Color(1, 1, 1), "roof_tint": Color(1, 1, 1),
		"haze_height": 4.0, "haze_density": 0.004,
		# カラーグレーディング（sRGB の LUT。atmosphere.gd の grade_lut）
		"grade": {"contrast": 1.08, "sat": 1.0, "green_sat": 0.84, "green_shift": 0.015, "blue_sat": 1.1,
			"shadow": Vector3(-0.015, 0.0, 0.035), "high": Vector3(0.02, 0.01, -0.015), "lift": Color(0.012, 0.016, 0.035)},
	}
	match era_id:
		"jomon_kofun":
			# 原始の森と夏の朝: 濃い緑、大きな入道雲
			a.merge({"sun_elev": 34.0, "tower": 0.85, "cloud_cover": 0.4, "cloud_seed": 0.13,
				"grass_a": Color(0.36, 0.64, 0.22), "grass_b": Color(0.22, 0.52, 0.26), "grass_c": Color(0.6, 0.76, 0.28),
				"forest_col": Color(0.14, 0.34, 0.2), "shade_color": Color(0.42, 0.56, 0.82),
				"plaster_tint": Color(0.92, 0.86, 0.76), "haze_density": 0.006,
				"grade": {"contrast": 1.08, "sat": 1.04, "green_sat": 0.86, "green_shift": 0.02, "blue_sat": 1.08,
					"shadow": Vector3(-0.02, 0.005, 0.03), "high": Vector3(0.025, 0.015, -0.02), "lift": Color(0.01, 0.02, 0.03)}}, true)
		"asuka_nara":
			# 澄んだ青空の昼: 高い太陽、薄い雲
			a.merge({"sun_elev": 56.0, "tower": 0.45, "cloud_cover": 0.3, "cirrus": 0.7, "cloud_seed": 0.41,
				"sky_zenith": Color(0.12, 0.4, 0.9), "sky_horizon": Color(0.56, 0.78, 0.98),
				"shade_color": Color(0.5, 0.58, 0.9), "plaster_tint": Color(0.96, 0.94, 0.9),
				"grade": {"contrast": 1.1, "sat": 1.02, "green_sat": 0.84, "green_shift": 0.015, "blue_sat": 1.16,
					"shadow": Vector3(-0.02, 0.0, 0.04), "high": Vector3(0.02, 0.012, -0.01), "lift": Color(0.01, 0.015, 0.035)}}, true)
		"heian":
			# 春の柔らかな午後: 淡い桜色の霞、パステル
			a.merge({"sun_elev": 26.0, "tower": 0.5, "cloud_cover": 0.45, "cloud_seed": 0.27,
				"sky_zenith": Color(0.36, 0.52, 0.86), "sky_horizon": Color(0.86, 0.8, 0.92), "sky_haze": Color(0.98, 0.9, 0.92),
				"sunset_color": Color(1.0, 0.7, 0.62), "sunset_amount": 0.6,
				"cloud_shade": Color(0.74, 0.68, 0.86), "cloud_mid": Color(0.96, 0.9, 0.96),
				"shade_color": Color(0.62, 0.56, 0.86), "shade_strength": 0.56,
				"grass_a": Color(0.5, 0.7, 0.32), "grass_b": Color(0.36, 0.6, 0.34), "grass_c": Color(0.76, 0.8, 0.42),
				"aerial": Color(0.92, 0.86, 0.92), "exposure": 1.04,
				"plaster_tint": Color(0.98, 0.95, 0.93), "wood_tint": Color(1.02, 0.98, 0.98), "haze_density": 0.006, "glow": 0.75,
				"grade": {"contrast": 0.97, "sat": 0.92, "green_sat": 0.8, "green_shift": 0.01, "blue_sat": 0.96, "warm_sat": 1.05,
					"shadow": Vector3(0.012, -0.01, 0.04), "high": Vector3(0.03, 0.005, 0.015), "lift": Color(0.05, 0.04, 0.06),
					"vibrance": 0.08}}, true)
		"kamakura_muromachi":
			# 真夏の昼: 強い日差し、くっきりした積雲
			a.merge({"sun_elev": 44.0, "tower": 0.75, "cloud_cover": 0.55, "cloud_seed": 0.61,
				"grass_a": Color(0.38, 0.62, 0.22), "grass_b": Color(0.24, 0.5, 0.26),
				"shade_color": Color(0.46, 0.52, 0.84), "plaster_tint": Color(0.94, 0.92, 0.87),
				"grade": {"contrast": 1.1, "sat": 1.02, "green_sat": 0.84, "green_shift": 0.02, "blue_sat": 1.12,
					"shadow": Vector3(-0.02, 0.0, 0.04), "high": Vector3(0.025, 0.012, -0.015), "lift": Color(0.01, 0.015, 0.035)}}, true)
		"sengoku":
			# 合戦の黄金色の夕刻: 低い太陽、茜色の雲
			a.merge({"sun_elev": 11.0, "tower": 0.7, "cloud_cover": 0.5, "cloud_seed": 0.83,
				"sky_zenith": Color(0.3, 0.48, 0.76), "sky_horizon": Color(0.98, 0.78, 0.52), "sky_haze": Color(1.0, 0.84, 0.62), "cirrus": 0.25,
				"sunset_color": Color(1.0, 0.52, 0.24),
				"cloud_light": Color(1.0, 0.92, 0.78), "cloud_mid": Color(0.98, 0.72, 0.56), "cloud_shade": Color(0.56, 0.46, 0.66),
				"shade_color": Color(0.5, 0.42, 0.72), "shade_strength": 0.52,
				"grass_a": Color(0.5, 0.62, 0.24), "grass_b": Color(0.36, 0.52, 0.24), "grass_c": Color(0.78, 0.74, 0.32),
				"aerial": Color(0.98, 0.78, 0.6), "rays": 0.55, "glow": 0.85, "glare": 0.5,
				"plaster_tint": Color(0.96, 0.9, 0.82), "haze_density": 0.007, "haze_height": 6.0,
				"grade": {"contrast": 1.14, "sat": 1.06, "green_sat": 0.8, "green_shift": -0.01, "blue_sat": 1.05, "warm_sat": 1.12,
					"gain": Color(1.04, 1.0, 0.92), "shadow": Vector3(-0.03, 0.0, 0.04), "high": Vector3(0.05, 0.02, -0.035),
					"lift": Color(0.02, 0.015, 0.04)}}, true)
		"edo":
			# 浮世絵の藍の青空と白い雲
			a.merge({"sun_elev": 46.0, "tower": 0.7, "cloud_cover": 0.5, "cloud_seed": 0.07,
				"sky_zenith": Color(0.1, 0.36, 0.84), "sky_horizon": Color(0.58, 0.8, 0.98),
				"shade_color": Color(0.46, 0.52, 0.88), "plaster_tint": Color(0.95, 0.94, 0.9),
				"grade": {"contrast": 1.12, "sat": 1.02, "green_sat": 0.82, "green_shift": 0.025, "blue_sat": 1.16,
					"shadow": Vector3(-0.025, 0.0, 0.045), "high": Vector3(0.018, 0.01, -0.012), "lift": Color(0.008, 0.016, 0.04)}}, true)
		"meiji_taisho":
			# ノスタルジックな午後: 少し暖色の光
			a.merge({"sun_elev": 30.0, "tower": 0.6, "cloud_cover": 0.5, "cloud_seed": 0.55,
				"sky_zenith": Color(0.26, 0.48, 0.84), "sky_horizon": Color(0.78, 0.84, 0.92), "sky_haze": Color(0.96, 0.92, 0.86),
				"sunset_amount": 0.7, "shade_color": Color(0.56, 0.54, 0.82),
				"grass_a": Color(0.46, 0.64, 0.28), "grass_b": Color(0.32, 0.54, 0.3), "grass_c": Color(0.72, 0.76, 0.38),
				"aerial": Color(0.88, 0.86, 0.84), "plaster_tint": Color(0.95, 0.91, 0.84), "wood_tint": Color(1.02, 0.97, 0.92),
				"grade": {"contrast": 1.06, "sat": 0.84, "green_sat": 0.82, "green_shift": -0.01, "blue_sat": 0.92, "warm_sat": 1.05,
					"gain": Color(1.04, 1.0, 0.92), "shadow": Vector3(0.01, 0.0, 0.01), "high": Vector3(0.045, 0.025, -0.03),
					"lift": Color(0.045, 0.035, 0.03)}}, true)
		"showa":
			# 昭和の夕焼け: 茜と紫のグラデーション
			# 昭和の夏の午後: 大きな入道雲、少し褪せたフィルムの色（持ち上がった黒・青緑の影・暖かい光）
			a.merge({"sun_elev": 24.0, "tower": 1.0, "cloud_cover": 0.4, "cloud_seed": 0.36, "cirrus": 0.2,
				"sky_zenith": Color(0.14, 0.4, 0.84), "sky_horizon": Color(0.66, 0.84, 0.96), "sky_haze": Color(0.94, 0.94, 0.88),
				"sunset_color": Color(1.0, 0.64, 0.4), "sunset_amount": 0.5,
				"cloud_light": Color(1.0, 0.99, 0.95), "cloud_mid": Color(0.9, 0.92, 0.96), "cloud_shade": Color(0.58, 0.66, 0.84),
				"shade_color": Color(0.42, 0.52, 0.8), "shade_strength": 0.5,
				"grass_a": Color(0.4, 0.62, 0.24), "grass_b": Color(0.26, 0.52, 0.3), "grass_c": Color(0.7, 0.76, 0.32),
				"aerial": Color(0.84, 0.88, 0.92), "rays": 0.4, "glow": 0.75, "glare": 0.45,
				"plaster_tint": Color(0.93, 0.92, 0.88), "haze_density": 0.005,
				"grade": {"contrast": 1.04, "sat": 0.96, "green_sat": 0.82, "green_shift": 0.035, "blue_sat": 1.04, "warm_sat": 1.04,
					"gain": Color(1.03, 1.0, 0.95), "shadow": Vector3(-0.025, 0.012, 0.03), "high": Vector3(0.035, 0.02, -0.025),
					"lift": Color(0.045, 0.05, 0.05), "vibrance": 0.1}}, true)
	return a


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
