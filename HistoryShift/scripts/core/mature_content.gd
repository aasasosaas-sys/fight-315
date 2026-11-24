class_name MatureContent
extends RefCounted
## 成人向けコンテンツ（いまは「民間人への危害」設定だけ）を使えるかどうかの窓口。
## - 教育版（エクスポートの custom_features に "edu"）では常に使えない。設定は隠され、data/chaos_civil/* も読まない
##   （export_presets.cfg の「教育版」プリセットはそのフォルダ自体を書き出しから外す）。
## - 将来は別配布（Steam の無料 DLC・年齢確認つき）にする予定。_dlc_owned() がその確認の差し込み口。

## テスト用：true にすると教育版として振る舞う
static var force_edu := false
## テスト用：DLC 未所有として振る舞う
static var force_locked := false

const STEAM_DLC_APP_ID := 0   # TODO(steam): 成人向け DLC の AppID


static func is_edu() -> bool:
	return force_edu or OS.has_feature("edu")


## 成人向けコンテンツを使えるか（教育版でなく、かつ所有確認が通る）
static func is_unlocked() -> bool:
	if is_edu() or force_locked:
		return false
	return _dlc_owned()


## TODO(steam): GodotSteam などの Steamworks 連携を入れたら、ここで所有を確かめる。
##   例: return Engine.has_singleton("Steam") and Engine.get_singleton("Steam").isDLCInstalled(STEAM_DLC_APP_ID)
##   （Steamworks の ISteamApps::BIsDlcInstalled）。Steam を使わない配布では true のまま。
static func _dlc_owned() -> bool:
	return true
