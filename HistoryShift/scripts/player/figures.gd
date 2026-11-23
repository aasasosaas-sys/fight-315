class_name Figures
extends RefCounted
## ミッションに登場する歴史上の人物（故人のみ）を、ひと目でわかるアニメ調の姿で組み立てる。
##   Figures.spec_for("織田信長")  -> 人物の設計（素体・衣装・髪・配色・顔・家紋・小物・肩書き）。知らない名前なら {}
##   Figures.build("織田信長", seed) -> VRM 素体（"Anim" の AnimationPlayer 付き）を返す
##   Figures.decorate(model, spec, seed) -> AnimeChar.build 済みの素体へ髪色・顔・家紋・小物を後付けする（Humanoid 組み込み用）
## 小物は GDScript で手続き生成したメッシュ（MToon の雛形を複製してセル塗り）を BoneAttachment3D で骨に付ける。
## 家紋は assets/characters/props/kamon/<名>.png（tools/props/make_kamon.gd で焼いたもの）を Decal で衣の背・袖・胸へ投影する。
## 顔（年齢・髭・肌・目）は scripts/player/anime_face.gd（AnimeFace.apply）があればそれに任せ、無ければ髭だけ簡易メッシュで付ける。

const FACE_SCRIPT := "res://scripts/player/anime_face.gd"
const KAMON_DIR := "res://assets/characters/props/kamon/"
const NODE_PREFIX := "Fig_"

## 髪の色 → AnimeHair の tint（髪の絵が暗いので 1 を超える値で明るくする）
const HAIR_TINT := {
	"black": Color(1, 1, 1), "gray": Color(2.6, 2.6, 2.6), "white": Color(3.9, 3.9, 3.7),
	"brown": Color(2.3, 1.55, 0.95), "blond": Color(3.9, 3.1, 1.6), "auburn": Color(2.6, 1.3, 0.8),
	"shaved": Color(3.9, 3.2, 2.3),
}
## 髭（簡易メッシュ）の色
const BEARD_COL := {"black": Color(0.1, 0.09, 0.1), "gray": Color(0.52, 0.5, 0.5), "white": Color(0.88, 0.87, 0.85),
	"brown": Color(0.36, 0.22, 0.12), "blond": Color(0.8, 0.64, 0.36), "auburn": Color(0.5, 0.22, 0.12), "shaved": Color(0.1, 0.09, 0.1)}

## 小物用の追加の色（AnimeChar.DYES に無いもの）。[地, 影]
const EXTRA_COL := {
	"gin": [Color(0.8, 0.82, 0.86), Color(0.5, 0.52, 0.6)],          # 銀
	"urushi": [Color(0.1, 0.08, 0.08), Color(0.03, 0.02, 0.03)],     # 黒漆
	"seidou": [Color(0.72, 0.55, 0.3), Color(0.42, 0.3, 0.16)],      # 青銅（鏡）
	"hisui": [Color(0.3, 0.7, 0.48), Color(0.14, 0.42, 0.3)],        # 翡翠
	"biro": [Color(0.7, 0.08, 0.12), Color(0.36, 0.02, 0.07)],       # 南蛮の天鵞絨（赤）
	"tetsu": [Color(0.3, 0.3, 0.33), Color(0.14, 0.14, 0.17)],       # 鉄
	"zouge": [Color(0.95, 0.9, 0.78), Color(0.72, 0.64, 0.54)],      # 象牙（笏）
	"glass": [Color(0.75, 0.85, 0.95), Color(0.5, 0.6, 0.72)],
	"hada": [Color(1.0, 0.86, 0.77), Color(0.85, 0.66, 0.6)],
	"midori": [Color(0.2, 0.42, 0.3), Color(0.1, 0.24, 0.18)],
	"ki": [Color(0.95, 0.8, 0.3), Color(0.7, 0.52, 0.14)],
}

const FEMALE_OBI := ["taiko", "obiage", "obijime"]

# ---------------------------------------------------------------------------
# 人物の型（時代・身分ごとの装い）。人物ごとの指定がこれを上書きする（palette / face は項目ごとに合成）
#   outfit: AnimeChar.SETS の名前 / hair: AnimeHair のスタイル / hair_color: HAIR_TINT のキー
#   palette: 部位 → "色:柄:差し色" / hide: 隠す衣装部位 / extra: 衣装に足す部位（wasou glb にあるもの）
#   acc: 小物（"名" または "名:色:色2"）/ kamon_at: 家紋を置く場所（back, chest, sleeve, do, kataginu）
#   face: AnimeFace へ渡す顔の指定 / height: 身長(m) / build: 体格の拡縮（Vector3）
# ---------------------------------------------------------------------------
const ARCH := {
	# 古墳：白い衣と袴、髻、勾玉、環頭大刀
	"kofun_king": {"outfit": "hakama", "hair": "court_bun",
		"palette": {"kosode": "shiro:plain", "eri": "shiro", "haneri": "shiro", "hakama": "shiro:plain", "obi": "enji", "tabi": "shiro", "zori": "wara:weave:kuchiba"},
		"acc": ["kofun_crown", "magatama", "kanto_tachi"], "face": {"age": 40}},
	"kofun_chief": {"outfit": "hakama", "hair": "court_bun",
		"palette": {"kosode": "kinari:plain", "eri": "kinari", "haneri": "shiro", "hakama": "kuchiba:plain", "obi": "enji", "tabi": "kinari", "zori": "wara:weave:kuchiba"},
		"acc": ["magatama", "kanto_tachi"], "face": {"age": 45}},
	# 古墳の武人（短甲＋衝角付冑：当世具足を流用し兜を差し替え）
	"kofun_warrior": {"outfit": "busho", "hair": "court_bun", "hide": ["kabuto", "maedate", "shikoro", "haidate"],
		"palette": {"kosode_t": "shiro:plain", "do": "sumi:ita:kin", "kusazuri": "sumi:ita:kin", "sode": "sumi:ita:kin", "kote": "kuro", "kobakama": "shiro:plain", "suneate": "kuro:shino:kin"},
		"acc": ["shokaku_kabuto", "kanto_tachi", "magatama"], "face": {"age": 40}},
	# 卑弥呼・壱与：白の巫女装束、勾玉と鏡
	"priestess": {"outfit": "kimono", "hair": "suberakashi", "female": true, "hide": FEMALE_OBI,
		"palette": {"kosode": "shiro:plain", "eri": "shu", "haneri": "shiro", "robe": "shiro:plain", "obi": "shu", "tabi": "shiro", "zori": "wara:weave:kuchiba", "zori_hanao": "shu"},
		"acc": ["magatama", "mirror", "hachimaki:shu", "hire:sakura"], "face": {"age": 30, "eyes": "gentle"}},
	# 飛鳥・奈良の朝服：裾長の袍、幞頭、笏、直刀
	"asuka_court": {"outfit": "kimono", "hair": "court_bun", "hide": FEMALE_OBI,
		"palette": {"kosode": "kuchiba:plain", "eri": "kuchiba", "haneri": "shiro", "robe": "kuchiba:plain", "obi": "kuro", "tabi": "shiro", "zori": "kuro"},
		"acc": ["boku", "shaku", "chokuto"], "face": {"age": 35}},
	"asuka_lady": {"outfit": "kimono", "hair": "suberakashi", "female": true, "hide": FEMALE_OBI,
		"palette": {"kosode": "moegi:plain", "eri": "enji", "haneri": "shiro", "robe": "enji:shima:shiro", "obi": "shu", "tabi": "shiro", "zori": "kinari", "zori_hanao": "enji"},
		"acc": ["hokan", "hire:shiro"], "face": {"age": 40}},
	# 平安以降の束帯：黒の袍（四位以上）、冠、笏、裾（きょ）
	"sokutai": {"outfit": "kimono", "hair": "court_bun", "hide": FEMALE_OBI,
		"palette": {"kosode": "kuro:plain", "eri": "kuro", "haneri": "shiro", "robe": "kuro:plain", "obi": "kuro", "tabi": "shiro", "zori": "kuro"},
		"acc": ["kanmuri", "shaku", "kyo:kuro"], "face": {"age": 45}},
	# 天皇の束帯（黄櫨染）、立纓の冠
	"emperor": {"outfit": "kimono", "hair": "court_bun", "hide": FEMALE_OBI,
		"palette": {"kosode": "kuchiba:plain", "eri": "kuchiba", "haneri": "shiro", "robe": "kuchiba:plain", "obi": "kuro", "tabi": "shiro", "zori": "kuro"},
		"acc": ["kanmuri_ryuei", "shaku", "kyo:kuchiba"], "face": {"age": 45}},
	# 公家の狩衣（烏帽子・扇）
	"kariginu": {"outfit": "hakama", "hair": "court_bun",
		"palette": {"kosode": "shiro:asanoha:kinari", "eri": "shiro", "haneri": "shiro", "hakama": "murasaki:plain", "obi": "shiro", "tabi": "shiro", "zori": "kuro"},
		"acc": ["eboshi", "sensu"], "face": {"age": 50}},
	# 平安の女房装束（十二単ふう：重ね色目の衿、裳、檜扇、垂髪）
	"heian_lady": {"outfit": "kimono", "hair": "suberakashi", "female": true, "hide": FEMALE_OBI,
		"palette": {"kosode": "enji:asanoha:kin", "eri": "moegi", "haneri": "shiro", "robe": "enji:plain", "obi": "enji", "tabi": "shiro", "zori": "kinari"},
		"acc": ["kasane:moegi:ki:shu:sakura:shiro", "mo:shiro", "hiougi"], "face": {"age": 30, "brows": "hikimayu"}},
	# 僧：墨染の衣と袈裟、数珠、剃髪
	"monk": {"outfit": "kimono", "hair": "buzz", "hair_color": "shaved", "hide": FEMALE_OBI,
		"palette": {"kosode": "sumi:plain", "eri": "sumi", "haneri": "shiro", "robe": "sumi:plain", "obi": "sumi", "tabi": "shiro", "zori": "wara:weave:kuchiba", "zori_hanao": "kuro"},
		"acc": ["kesa:kuchiba:kin", "juzu"], "face": {"age": 55, "eyes": "gentle"}},
	# 平安末〜鎌倉の武者（大鎧ふう：当世具足で代用）
	"warrior_old": {"outfit": "busho", "hair": "court_bun",
		"palette": {"kosode_t": "enji:plain", "do": "kuro:odoshi:enji", "kusazuri": "kuro:odoshi:enji", "sode": "kuro:odoshi:enji", "kabuto": "kuro:suji:kin", "shikoro": "kuro:odoshi:enji", "maedate": "kin"},
		"acc": ["tachi"], "kamon_at": ["back"], "face": {"age": 38, "eyes": "sharp"}},
	# 鎌倉・室町の武家（直垂＋折烏帽子＋太刀）
	"bushi": {"outfit": "samurai", "hair": "court_bun",
		"palette": {"kosode": "ai:plain", "eri": "ai", "haneri": "shiro", "hakama": "ai:plain", "obi": "kuro", "tabi": "shiro", "zori": "wara:weave:kuchiba"},
		"acc": ["ori_eboshi", "tachi", "sensu"], "kamon_at": ["back", "sleeve", "chest"], "face": {"age": 40}},
	# 戦国の武将（当世具足）
	"busho": {"outfit": "busho", "hair": "chasen",
		"palette": {}, "acc": ["katana"], "kamon_at": ["do"], "face": {"age": 40, "eyes": "sharp"}},
	# 戦国〜江戸初期の武家の平服（小袖＋袴、大小）
	"sengoku_lord": {"outfit": "hakama", "hair": "chasen",
		"palette": {"kosode": "kon:plain", "eri": "kuro", "haneri": "shiro", "hakama": "nezumi:shima:kuro", "obi": "kuro", "tabi": "shiro", "zori": "wara:weave:kuchiba"},
		"acc": ["katana", "wakizashi", "sensu"], "kamon_at": ["back", "sleeve", "chest"], "face": {"age": 40}},
	# 江戸の裃（肩衣＋袴）、大小、丁髷
	"kamishimo": {"outfit": "hakama", "hair": "chonmage",
		"palette": {"kosode": "kinari:plain", "eri": "kuro", "haneri": "shiro", "hakama": "nezumi:plain", "obi": "kuro", "tabi": "shiro", "zori": "wara:weave:kuchiba"},
		"acc": ["kataginu:nezumi", "katana", "wakizashi", "sensu"], "kamon_at": ["kataginu", "sleeve"], "face": {"age": 45}},
	# 江戸の学者（総髪・書物）
	"scholar": {"outfit": "hakama", "hair": "court_bun",
		"palette": {"kosode": "cha:plain", "eri": "kuro", "haneri": "shiro", "hakama": "kogecha:shima:kuro", "obi": "kuro", "tabi": "shiro", "zori": "wara:weave:kuchiba"},
		"acc": ["book"], "face": {"age": 55, "eyes": "gentle"}},
	# 神職（白の狩衣、烏帽子、笏）
	"shinto": {"outfit": "hakama", "hair": "court_bun",
		"palette": {"kosode": "shiro:plain", "eri": "shiro", "haneri": "shiro", "hakama": "murasaki:plain", "obi": "shiro", "tabi": "shiro", "zori": "kuro"},
		"acc": ["eboshi", "shaku"], "face": {"age": 50}},
	# 幕末の志士（黒紋付＋袴）
	"bakumatsu": {"outfit": "samurai", "hair": "chasen",
		"palette": {"kosode": "kuro:plain", "eri": "kuro", "haneri": "shiro", "hakama": "nezumi:shima:sumi", "obi": "kuro", "tabi": "shiro", "zori": "wara:weave:kuchiba"},
		"acc": ["katana", "wakizashi"], "kamon_at": ["back", "sleeve", "chest"], "face": {"age": 30}},
	# 明治の政治家（三つ揃いの背広）
	"meiji_suit": {"outfit": "suit_meiji", "hair": "zangiri", "hide": ["bowler"],
		"palette": {"jacket": "kuro", "vest": "kuro", "trousers": "nezumi:shima:sumi", "tie": "kuro"},
		"acc": [], "face": {"age": 50}},
	# 大正・昭和の政治家（背広）
	"showa_suit": {"outfit": "showa_suit", "hair": "zangiri",
		"palette": {"jacket": "sumi", "lapel": "kuro", "trousers": "sumi", "tie": "kuro"},
		"acc": [], "face": {"age": 60}},
	# 陸軍の将官（将校は長靴：巻脚絆を革色に）
	"army": {"outfit": "army", "hair": "buzz",
		"palette": {"puttee": "cha:plain", "boots": "cha", "collar_tab": "shu"},
		"acc": ["gunto", "medals", "aiguillette"], "face": {"age": 55, "eyes": "sharp"}},
	# 海軍の将官（第二種軍装＝白）
	"navy": {"outfit": "navy", "hair": "buzz",
		"palette": {}, "acc": ["tanken", "medals"], "face": {"age": 55}},
	"navy_dark": {"outfit": "navy", "hair": "buzz",
		"palette": {"jacket": "kon", "collar_st": "kon", "trousers": "kon", "shoes": "kuro", "pcap_top": "kon", "epaulet": "kin"},
		"acc": ["tanken", "medals"], "face": {"age": 60}},
	# イエズス会の宣教師（黒の修道服＝裾長の衣で代用）
	"jesuit": {"outfit": "kimono", "hair": "zangiri", "hair_color": "brown", "hide": ["taiko", "obiage", "obijime", "eri", "haneri"],
		"palette": {"kosode": "kuro:plain", "robe": "kuro:plain", "obi": "kuro", "tabi": "kuro", "zori": "cha", "zori_hanao": "cha"},
		"acc": ["crucifix", "white_collar"], "face": {"age": 45, "beard": "full", "eye_color": "brown"}},
	# 欧米の外交官
	"diplomat": {"outfit": "suit_meiji", "hair": "zangiri", "hair_color": "brown", "hide": ["bowler"],
		"palette": {"jacket": "kuro", "vest": "kuro", "trousers": "sumi"},
		"acc": [], "face": {"age": 55, "eye_color": "blue"}},
	# 桃山の女性（小袖、細帯、垂髪）
	"momoyama_lady": {"outfit": "kimono", "hair": "suberakashi", "female": true, "hide": FEMALE_OBI,
		"palette": {"kosode": "enji:asanoha:kin", "eri": "kin", "haneri": "shiro", "robe": "enji:asanoha:kin", "obi": "kin:plain", "tabi": "shiro", "zori": "kinari", "zori_hanao": "enji"},
		"acc": ["sensu:kin"], "kamon_at": ["sleeve"], "face": {"age": 45, "eyes": "gentle"}},
	# 大正の女性（女袴・編み上げ靴・束髪）
	"taisho_woman": {"outfit": "haikara", "hair": "sokuhatsu", "female": true,
		"palette": {}, "acc": ["book"], "face": {"age": 28}},
	# 職人
	"artisan": {"outfit": "hakama", "hair": "chonmage",
		"palette": {"kosode": "kaki:plain", "eri": "kuro", "haneri": "shiro", "hakama": "kon:plain", "obi": "kuro", "tabi": "kon", "zori": "wara:weave:kuchiba"},
		"acc": ["hachimaki:shiro", "hammer"], "face": {"age": 50}},
}

# ---------------------------------------------------------------------------
# 人物（ミッションの npc 名 → 設計）。aka は別名（「厩戸王（聖徳太子）」のような表記も別名で引ける）
# ---------------------------------------------------------------------------
const FIGURES := {
	# ── 弥生・古墳 ──
	"卑弥呼": {"arch": "priestess", "title": "邪馬台国の女王", "base": "Sendagaya_Shino", "face": {"age": 62}},
	"壱与": {"arch": "priestess", "title": "卑弥呼の後継の女王", "base": "HairSample_Female",
		"palette": {"eri": "moegi", "obi": "moegi", "zori_hanao": "moegi"}, "acc": ["magatama", "mirror", "hachimaki:moegi", "hire:mizu"], "face": {"age": 13}},
	"難升米": {"arch": "kofun_chief", "title": "魏へ渡った卑弥呼の使者", "acc": ["magatama", "scroll"], "face": {"mustache": "thin"}},
	"卑弥弓呼": {"arch": "kofun_warrior", "title": "邪馬台国と争った狗奴国の王", "face": {"age": 45, "beard": "short"}},
	"倭王武": {"arch": "kofun_warrior", "title": "倭の五王・ワカタケル大王", "aka": ["ワカタケル大王", "雄略天皇"], "acc": ["shokaku_kabuto", "kanto_tachi", "magatama", "kofun_crown_band"],
		"palette": {"do": "sumi:ita:kin", "kusazuri": "sumi:ita:kin"}, "face": {"age": 40, "mustache": "thin", "beard": "goatee"}},
	"筑紫君磐井": {"arch": "kofun_warrior", "title": "ヤマト政権に抗った筑紫の国造", "aka": ["磐井"], "face": {"age": 50, "beard": "short"}},
	"欽明天皇": {"arch": "kofun_king", "title": "仏教公伝の大王", "face": {"age": 45, "mustache": "thin", "beard": "goatee"}},
	"物部尾輿": {"arch": "kofun_chief", "title": "排仏を唱えた大連", "palette": {"kosode": "kon:plain", "hakama": "shiro:plain"}, "face": {"age": 50, "beard": "short", "brows": "thick"}},
	"蘇我稲目": {"arch": "kofun_chief", "title": "崇仏を唱えた大臣", "palette": {"kosode": "enji:plain", "hakama": "shiro:plain"}, "acc": ["magatama", "scroll"], "face": {"age": 50, "mustache": "thin"}},
	"上毛野君": {"arch": "kofun_chief", "title": "東国・上毛野の豪族", "face": {"age": 42, "beard": "short"}},
	# ── 飛鳥・奈良 ──
	"厩戸王": {"arch": "asuka_court", "title": "推古朝の政治を担った皇子", "aka": ["聖徳太子"], "base": "Sakurada_Fumiriya",
		"face": {"age": 33, "mustache": "thin", "beard": "goatee"}},
	"蘇我馬子": {"arch": "asuka_court", "title": "飛鳥の大臣", "palette": {"kosode": "murasaki:plain", "robe": "murasaki:plain", "eri": "murasaki"}, "acc": ["boku", "shaku"],
		"face": {"age": 60, "beard": "long", "hair_color": "gray"}},
	"中大兄皇子": {"arch": "asuka_court", "title": "乙巳の変・のちの天智天皇", "base": "Sendagaya_Shibu",
		"palette": {"kosode": "enji:plain", "robe": "enji:plain", "eri": "enji"}, "face": {"age": 20, "eyes": "sharp"}},
	"中臣鎌足": {"arch": "asuka_court", "title": "大化改新の功臣（藤原氏の祖）", "palette": {"kosode": "kon:plain", "robe": "kon:plain", "eri": "kon"},
		"face": {"age": 31, "mustache": "full", "beard": "long"}},
	"中臣御食子": {"arch": "asuka_court", "title": "神祇を掌った中臣氏の長（鎌足の父）", "palette": {"kosode": "shiro:plain", "robe": "shiro:plain", "eri": "shiro"}, "face": {"age": 60, "beard": "long", "hair_color": "gray"}},
	"大海人皇子": {"arch": "asuka_court", "title": "壬申の乱・のちの天武天皇", "palette": {"kosode": "ai:plain", "robe": "ai:plain", "eri": "ai"}, "acc": ["boku", "chokuto", "sensu:kuro"],
		"face": {"age": 40, "mustache": "thin", "eyes": "sharp"}},
	"皇極天皇": {"arch": "asuka_lady", "title": "飛鳥の女帝（のち斉明天皇）", "base": "Sendagaya_Shino", "face": {"age": 48}},
	"豊璋": {"arch": "asuka_court", "title": "倭に滞在した百済の王子", "palette": {"kosode": "shu:plain", "robe": "shu:plain", "eri": "kin"}, "acc": ["hokan_m", "chokuto"], "face": {"age": 30}},
	"長屋王": {"arch": "asuka_court", "title": "三世一身法の頃の右大臣（のち左大臣）", "palette": {"kosode": "murasaki:plain", "robe": "murasaki:plain", "eri": "murasaki"}, "face": {"age": 45, "mustache": "thin"}},
	"橘諸兄": {"arch": "asuka_court", "title": "聖武天皇を支えた左大臣", "palette": {"kosode": "murasaki:plain", "robe": "murasaki:plain", "eri": "murasaki"}, "face": {"age": 55, "beard": "goatee"}},
	"山部王": {"arch": "asuka_court", "title": "白壁王の皇子・のちの桓武天皇", "palette": {"kosode": "ai:plain", "robe": "ai:plain"}, "face": {"age": 6}},
	"聖武天皇": {"arch": "emperor", "title": "大仏造立を発願した天皇", "palette": {"kosode": "shiro:plain", "robe": "shiro:plain", "eri": "kin"}, "acc": ["kanmuri_ryuei", "shaku"],
		"face": {"age": 40, "mustache": "thin"}},
	"小野妹子": {"arch": "asuka_court", "title": "遣隋使", "palette": {"kosode": "ai:plain", "robe": "ai:plain"}, "acc": ["boku", "scroll", "chokuto"], "face": {"age": 35}},
	"高向玄理": {"arch": "asuka_court", "title": "隋・唐に学んだ国博士", "palette": {"kosode": "moegi:plain", "robe": "moegi:plain"}, "acc": ["boku", "scroll"], "face": {"age": 55, "beard": "long"}},
	"僧旻": {"arch": "monk", "title": "隋で学んだ学問僧・国博士", "acc": ["kesa:kuchiba:kin", "scroll"], "face": {"age": 55}},
	"南淵請安": {"arch": "scholar", "title": "中大兄皇子らに儒教を講じた学者", "outfit": "kimono", "hide": FEMALE_OBI, "palette": {"kosode": "kinari:plain", "robe": "kinari:plain", "eri": "kuchiba"},
		"acc": ["boku", "scroll"], "face": {"age": 60, "beard": "long", "hair_color": "gray"}},
	"鑑真": {"arch": "monk", "title": "日本に戒律を伝えた唐の高僧", "palette": {"kosode": "kuchiba:plain", "robe": "kuchiba:plain", "eri": "kuchiba"},
		"acc": ["kesa:enji:kin", "juzu"], "face": {"age": 66, "eyes": "closed"}},
	# ── 平安 ──
	"桓武天皇": {"arch": "emperor", "title": "平安京に遷都した天皇", "face": {"age": 50, "mustache": "thin", "beard": "goatee"}},
	"最澄": {"arch": "monk", "title": "天台宗の開祖（伝教大師）", "acc": ["kesa:shu:kin", "juzu"], "face": {"age": 45}},
	"和気清麻呂": {"arch": "sokutai", "title": "宇佐八幡宮神託事件", "palette": {"kosode": "enji:plain", "robe": "enji:plain", "eri": "enji"}, "face": {"age": 40, "mustache": "thin"}},
	"吉備真備": {"arch": "asuka_court", "title": "遣唐留学生から右大臣へ", "acc": ["kanmuri", "shaku", "scroll"], "face": {"age": 65, "beard": "long", "hair_color": "white"}},
	"平将門": {"arch": "warrior_old", "title": "新皇を称した坂東の武者", "kamon": "kuyo", "face": {"age": 37, "mustache": "full", "eyes": "sharp"}},
	"藤原秀郷": {"arch": "warrior_old", "title": "将門を討った下野の武者（俵藤太）", "kamon": "sagarifuji", "acc": ["tachi", "yumi"],
		"palette": {"do": "kuro:odoshi:moegi", "kusazuri": "kuro:odoshi:moegi", "sode": "kuro:odoshi:moegi", "shikoro": "kuro:odoshi:moegi"}, "face": {"age": 45, "beard": "short"}},
	"藤原純友": {"arch": "bushi", "title": "瀬戸内の海賊を率いた元伊予掾", "acc": ["hachimaki:ai", "tachi"], "hair": "court_bun",
		"palette": {"kosode": "kaki:plain", "hakama": "kon:plain"}, "kamon_at": [], "face": {"age": 40, "beard": "short", "eyes": "sharp"}},
	"藤原忠平": {"arch": "sokutai", "title": "朱雀朝の摂政・関白", "face": {"age": 55, "mustache": "thin"}},
	"藤原良房": {"arch": "sokutai", "title": "人臣初の摂政", "face": {"age": 60, "mustache": "thin", "beard": "goatee"}},
	"藤原基経": {"arch": "sokutai", "title": "初の関白", "face": {"age": 50, "mustache": "thin"}},
	"藤原実資": {"arch": "sokutai", "title": "『小右記』を記した賢人右府", "face": {"age": 65, "beard": "goatee", "hair_color": "gray"}},
	"藤原頼通": {"arch": "sokutai", "title": "宇治の関白（平等院鳳凰堂）", "face": {"age": 45, "mustache": "thin"}},
	"法然": {"arch": "monk", "title": "浄土宗の開祖", "acc": ["kesa:kuchiba:kin", "juzu"], "face": {"age": 65}},
	"成尋": {"arch": "monk", "title": "宋に渡った天台僧", "face": {"age": 60}},
	"定朝": {"arch": "monk", "title": "寄木造を完成させた仏師", "aka": ["仏師定朝"], "acc": ["kesa:kuchiba:kin", "chisel"], "face": {"age": 50}},
	"平清盛": {"arch": "monk", "title": "太政大臣・日宋貿易（入道相国）", "kamon": "ageha", "kamon_at": ["back", "chest"],
		"palette": {"kosode": "enji:plain", "robe": "enji:plain", "eri": "enji"}, "acc": ["kesa:kin:shu", "ogi_open:kin"], "face": {"age": 55, "eyes": "sharp"}},
	"白河天皇": {"arch": "emperor", "title": "院政を始めた天皇（白河上皇）", "aka": ["白河上皇", "白河法皇"], "face": {"age": 40, "mustache": "thin"}},
	"源為義": {"arch": "warrior_old", "title": "河内源氏の棟梁", "palette": {"do": "kuro:odoshi:ai", "kusazuri": "kuro:odoshi:ai", "sode": "kuro:odoshi:ai", "shikoro": "kuro:odoshi:ai"},
		"face": {"age": 60, "beard": "full", "hair_color": "gray"}},
	"紫式部": {"arch": "heian_lady", "title": "『源氏物語』の作者", "base": "Sendagaya_Shino",
		"palette": {"kosode": "murasaki:asanoha:kin", "robe": "murasaki:plain", "eri": "murasaki"}, "acc": ["kasane:murasaki:sakura:shiro:moegi:enji", "mo:shiro", "hiougi"]},
	"清少納言": {"arch": "heian_lady", "title": "『枕草子』の作者", "base": "HairSample_Female",
		"palette": {"kosode": "sakura:sakura_komon:shiro", "robe": "enji:plain", "eri": "sakura"}, "acc": ["kasane:sakura:shiro:moegi:ki:enji", "mo:shiro", "hiougi"]},
	# ── 鎌倉・室町 ──
	"源頼朝": {"arch": "sokutai", "title": "鎌倉幕府を開いた征夷大将軍", "acc": ["kanmuri", "shaku", "tachi"], "face": {"age": 45, "mustache": "thin"}},
	"後白河法皇": {"arch": "monk", "title": "院政を敷いた法皇", "palette": {"kosode": "kon:plain", "robe": "kon:plain", "eri": "kon"}, "acc": ["kesa:kin:enji", "juzu"], "face": {"age": 60}},
	"藤原秀康": {"arch": "bushi", "title": "後鳥羽上皇の近臣（承久の乱）", "palette": {"kosode": "enji:plain", "hakama": "shiro:plain"}, "kamon_at": [], "face": {"age": 40}},
	"北条泰時": {"arch": "bushi", "title": "御成敗式目を定めた執権", "kamon": "mitsuuroko", "face": {"age": 50, "mustache": "thin"}},
	"北条時頼": {"arch": "bushi", "title": "執権・最明寺入道", "kamon": "mitsuuroko", "palette": {"kosode": "moegi:plain", "hakama": "moegi:plain"}, "face": {"age": 30}},
	"北条時宗": {"arch": "warrior_old", "title": "元寇を退けた執権", "kamon": "mitsuuroko", "hair": "court_bun", "acc": ["tachi"],
		"palette": {"do": "kuro:odoshi:shiro", "kusazuri": "kuro:odoshi:shiro", "sode": "kuro:odoshi:shiro", "shikoro": "kuro:odoshi:shiro"}, "face": {"age": 22}},
	"後醍醐天皇": {"arch": "emperor", "title": "建武の新政を行った天皇", "acc": ["kanmuri_ryuei", "kesa:kin:shu", "vajra"],
		"palette": {"kosode": "kuchiba:plain", "robe": "kuchiba:plain"}, "face": {"age": 45, "mustache": "full", "beard": "long"}},
	"二条道平": {"arch": "sokutai", "title": "後醍醐天皇に仕えた前関白", "face": {"age": 45}},
	"楠木正成": {"arch": "warrior_old", "title": "南朝に尽くした河内の武将", "kamon": "kikusui", "hair": "court_bun",
		"palette": {"do": "kuro:odoshi:ai", "kusazuri": "kuro:odoshi:ai", "sode": "kuro:odoshi:ai", "shikoro": "kuro:odoshi:ai"}, "acc": ["tachi"], "face": {"age": 42, "mustache": "thin"}},
	"足利尊氏": {"arch": "bushi", "title": "室町幕府の初代将軍", "kamon": "futatsubiki", "palette": {"kosode": "kuro:plain", "hakama": "kuro:plain"}, "face": {"age": 45, "mustache": "thin", "brows": "thick"}},
	"足利直義": {"arch": "bushi", "title": "尊氏の弟・幕政の執行者", "kamon": "futatsubiki", "palette": {"kosode": "nezumi:plain", "hakama": "nezumi:plain"}, "face": {"age": 40}},
	"足利義満": {"arch": "monk", "title": "北山文化・明に「日本国王」と称された将軍", "kamon": "futatsubiki", "kamon_at": ["back"],
		"palette": {"kosode": "kuro:plain", "robe": "kuro:plain"}, "acc": ["kesa:kin:murasaki", "sensu:kin"], "face": {"age": 45}},
	"足利義教": {"arch": "bushi", "title": "くじ引きで選ばれた六代将軍", "kamon": "futatsubiki", "palette": {"kosode": "enji:plain", "hakama": "kuro:plain"}, "face": {"age": 40, "eyes": "sharp"}},
	"足利義政": {"arch": "bushi", "title": "東山文化・銀閣を築いた将軍", "kamon": "futatsubiki", "palette": {"kosode": "murasaki:plain", "hakama": "kon:plain"}, "face": {"age": 40, "eyes": "gentle"}},
	"細川勝元": {"arch": "bushi", "title": "応仁の乱・東軍の総帥", "kamon": "futatsubiki", "palette": {"kosode": "ai:plain", "hakama": "ai:plain"}, "face": {"age": 38}},
	"山名宗全": {"arch": "monk", "title": "応仁の乱・西軍の総帥（赤入道）", "palette": {"kosode": "enji:plain", "robe": "enji:plain"}, "acc": ["kesa:kuro:kin", "tachi"], "face": {"age": 64, "brows": "bushy"}},
	"道元": {"arch": "monk", "title": "曹洞宗の開祖", "acc": ["kesa:sumi:kuchiba", "juzu"], "face": {"age": 45}},
	"栄西": {"arch": "monk", "title": "臨済宗を伝え茶を広めた禅僧", "acc": ["kesa:kuchiba:kin", "chawan"], "face": {"age": 65}},
	"絶海中津": {"arch": "monk", "title": "五山文学の禅僧", "acc": ["kesa:kuchiba:kin", "scroll"], "face": {"age": 55}},
	"蓮如": {"arch": "monk", "title": "浄土真宗を広めた本願寺の中興の祖", "kamon": "sagarifuji", "kamon_at": ["back"], "face": {"age": 60}},
	# ── 戦国・安土桃山 ──
	"織田信長": {"arch": "busho", "title": "天下布武を掲げた尾張の大名", "base": "Sendagaya_Shibu", "kamon": "mokko",
		"hide": ["kabuto", "shikoro", "maedate"], "kamon_at": ["do", "chest"],
		"palette": {"kosode_t": "enji:plain", "do": "kuro:odoshi:enji", "kusazuri": "kuro:odoshi:enji", "sode": "kuro:odoshi:enji", "haidate": "kuro:odoshi:enji"},
		"acc": ["cape:biro:kin", "katana", "tessen"], "acc_opt": {"helmet": ["nanban_kabuto"]}, "face": {"age": 40, "mustache": "thin", "beard": "goatee", "eyes": "sharp"}, "height": 1.66},
	"羽柴秀吉": {"arch": "busho", "title": "天下統一へ駆け上がる羽柴筑前守", "kamon": "kiri", "hide": ["maedate"],
		"palette": {"kosode_t": "shu:plain", "do": "kin:odoshi:shu", "kusazuri": "kin:odoshi:shu", "sode": "kin:odoshi:shu", "kabuto": "kuro:suji:kin", "shikoro": "kin:odoshi:shu"},
		"acc": ["bariki", "hyotan", "katana", "gunbai"], "face": {"age": 45, "mustache": "thin", "eyes": "gentle"}, "height": 1.52},
	"豊臣秀吉": {"arch": "sokutai", "title": "関白・太閤", "kamon": "kiri", "kamon_at": ["back", "sleeve", "chest"],
		"palette": {"kosode": "shiro:asanoha:kin", "robe": "shiro:plain", "eri": "shiro", "obi": "kuro"}, "acc": ["kanmuri", "shaku", "hyotan"],
		"face": {"age": 58, "mustache": "thin", "beard": "goatee", "hair_color": "gray"}, "height": 1.52},
	"徳川家康": {"arch": "busho", "title": "江戸幕府を開いた天下人", "kamon": "aoi", "hide": ["maedate"],
		"palette": {"kosode_t": "kon:plain", "do": "kuro:odoshi:kon", "kusazuri": "kuro:odoshi:kon", "sode": "kuro:odoshi:kon", "shikoro": "kuro:odoshi:kon"},
		"acc": ["shida_maedate", "katana", "gunbai"], "face": {"age": 58, "mustache": "thin", "beard": "goatee"}, "build": Vector3(1.08, 1.0, 1.08)},
	"今川義元": {"arch": "busho", "title": "海道一の弓取り", "kamon": "futatsubiki",
		"palette": {"do": "kuro:odoshi:shiro", "kusazuri": "kuro:odoshi:shiro", "sode": "kuro:odoshi:shiro", "shikoro": "kuro:odoshi:shiro"}, "acc": ["katana", "tessen"], "face": {"age": 41}},
	"石田三成": {"arch": "sengoku_lord", "title": "五奉行・関ヶ原の西軍の中心", "palette": {"kosode": "ai:plain", "hakama": "kon:shima:ai"}, "kamon_at": [], "face": {"age": 40, "eyes": "sharp"}},
	"加藤清正": {"arch": "busho", "title": "賤ヶ岳の七本槍・肥後の虎", "kamon": "janome", "hide": ["kabuto", "maedate"],
		"palette": {"do": "kuro:odoshi:kuro", "kusazuri": "kuro:odoshi:kuro", "sode": "kuro:odoshi:kuro", "shikoro": "kuro:odoshi:kuro"}, "acc": ["nagaeboshi", "katana"],
		"face": {"age": 45, "beard": "full", "mustache": "full", "brows": "thick"}, "height": 1.78},
	"北政所": {"arch": "momoyama_lady", "title": "秀吉の正室（高台院）", "aka": ["ねね", "高台院"], "kamon": "kiri", "base": "Sendagaya_Shino"},
	"小早川秀秋": {"arch": "busho", "title": "関ヶ原の去就を握った若き大名", "kamon": "chigaigama",
		"palette": {"kosode_t": "shu:plain", "do": "kuro:odoshi:shu", "kusazuri": "kuro:odoshi:shu", "sode": "kuro:odoshi:shu", "shikoro": "kuro:odoshi:shu"}, "face": {"age": 19}},
	"小早川隆景": {"arch": "sengoku_lord", "title": "毛利両川の知将", "kamon": "mitsudomoe", "palette": {"kosode": "kon:plain", "hakama": "kuchiba:shima:kaki"}, "face": {"age": 60, "mustache": "thin"}},
	"毛利輝元": {"arch": "busho", "title": "五大老・関ヶ原の西軍総大将", "kamon": "mori", "face": {"age": 47, "mustache": "thin"}},
	"黒田長政": {"arch": "busho", "title": "関ヶ原の調略を担った筑前の大名", "kamon": "kuroda", "hide": ["maedate"],
		"palette": {"do": "kuro:odoshi:kuro", "kusazuri": "kuro:odoshi:kuro"}, "acc": ["ichinotani", "katana"], "face": {"age": 32, "mustache": "thin"}},
	"後藤又兵衛": {"arch": "busho", "title": "黒田家の猛将", "aka": ["後藤基次"], "acc": ["katana", "yari"], "face": {"age": 40, "beard": "short", "brows": "thick"}},
	"フランシスコ＝ザビエル": {"arch": "jesuit", "title": "日本にキリスト教を伝えたイエズス会士", "aka": ["ザビエル"], "face": {"age": 43}},
	"ガスパル＝コエリョ": {"arch": "jesuit", "title": "イエズス会日本準管区長", "aka": ["コエリョ"], "hair_color": "gray", "face": {"age": 55, "hair_color": "gray"}},
	"種子島時堯": {"arch": "sengoku_lord", "title": "鉄砲を買い求めた種子島の島主", "palette": {"kosode": "moegi:plain", "hakama": "kuchiba:shima:kaki"}, "acc": ["teppo", "wakizashi"], "kamon_at": [], "face": {"age": 16}},
	"八板金兵衛": {"arch": "artisan", "title": "国産鉄砲を造った刀鍛冶", "face": {"age": 50, "brows": "thick"}},
	"顕如": {"arch": "monk", "title": "石山合戦を戦った本願寺の法主", "kamon": "sagarifuji", "kamon_at": ["back"], "palette": {"kosode": "kuro:plain", "robe": "kuro:plain"},
		"acc": ["kesa:kin:murasaki", "juzu"], "face": {"age": 37}},
	"吉田兼見": {"arch": "shinto", "title": "吉田神道の神主", "face": {"age": 47}},
	"里村紹巴": {"arch": "monk", "title": "連歌師", "palette": {"kosode": "cha:plain", "robe": "cha:plain"}, "acc": ["sensu", "tanzaku"], "face": {"age": 55}},
	"森蘭丸": {"arch": "sengoku_lord", "title": "信長の小姓", "base": "Sakurada_Fumiriya", "palette": {"kosode": "sakura:sakura_komon:shiro", "hakama": "murasaki:plain", "eri": "enji"},
		"kamon_at": [], "face": {"age": 17, "eyes": "large"}},
	"明智光秀": {"arch": "busho", "title": "本能寺の変を起こした惟任日向守", "kamon": "kikyo", "palette": {"do": "kuro:odoshi:ai", "kusazuri": "kuro:odoshi:ai", "sode": "kuro:odoshi:ai"}, "face": {"age": 55}},
	"武田信玄": {"arch": "busho", "title": "甲斐の虎", "kamon": "takeda",
		"palette": {"kosode_t": "shu:plain", "do": "shu:odoshi:kuro", "kusazuri": "shu:odoshi:kuro", "sode": "shu:odoshi:kuro", "shikoro": "shu:odoshi:kuro"}, "acc": ["katana", "gunbai"],
		"face": {"age": 50, "mustache": "full", "beard": "full"}, "build": Vector3(1.1, 1.0, 1.1)},
	"上杉謙信": {"arch": "sengoku_lord", "title": "越後の龍", "kamon": "takesuzume", "hair": "buzz", "hair_color": "shaved",
		"palette": {"kosode": "kon:plain", "hakama": "nezumi:plain"}, "acc": ["zukin:shiro", "katana", "tessen"], "face": {"age": 45}},
	# ── 江戸 ──
	"本多正純": {"arch": "kamishimo", "title": "家康・秀忠の側近", "palette": {"hakama": "kuro:plain"}, "acc": ["kataginu:kuro", "katana", "wakizashi", "sensu"], "face": {"age": 45}},
	"徳川家光": {"arch": "kamishimo", "title": "三代将軍・参勤交代と鎖国", "kamon": "aoi", "palette": {"kosode": "shiro:plain", "hakama": "murasaki:plain"},
		"acc": ["kataginu:murasaki", "katana", "wakizashi", "sensu"], "face": {"age": 35}},
	"金地院崇伝": {"arch": "monk", "title": "家康の外交・法度を担った「黒衣の宰相」", "aka": ["崇伝"], "acc": ["kesa:kin:enji", "scroll"], "face": {"age": 55}},
	"松平信綱": {"arch": "kamishimo", "title": "「知恵伊豆」と呼ばれた老中", "palette": {"hakama": "kon:plain"}, "acc": ["kataginu:kon", "katana", "wakizashi", "sensu"], "face": {"age": 42}},
	"天草四郎": {"arch": "sengoku_lord", "title": "島原・天草一揆の総大将", "aka": ["益田時貞"], "hair": "court_bun",
		"palette": {"kosode": "shiro:plain", "hakama": "kuchiba:plain", "eri": "shiro"}, "acc": ["ruff", "crucifix", "katana"], "kamon_at": [], "face": {"age": 16, "eyes": "large"}},
	"徳川吉宗": {"arch": "kamishimo", "title": "享保の改革を行った八代将軍", "kamon": "aoi", "palette": {"kosode": "kinari:plain", "hakama": "kon:plain"},
		"acc": ["kataginu:kon", "katana", "wakizashi", "sensu"], "face": {"age": 45}, "height": 1.8},
	"大黒屋光太夫": {"arch": "meiji_suit", "title": "ロシアから帰国した漂流民（18世紀末のロシア風の装い）", "hair": "court_bun",
		"hide": ["bowler", "tie", "shirt_v", "collar_st", "lapel"],
		"palette": {"jacket": "kogecha", "vest": "kogecha", "trousers": "kon"}, "acc": ["fur_hat"], "face": {"age": 42}},
	"松平定信": {"arch": "kamishimo", "title": "寛政の改革を行った老中首座", "kamon": "umebachi", "palette": {"hakama": "kogecha:plain"},
		"acc": ["kataginu:kogecha", "katana", "wakizashi", "sensu"], "face": {"age": 32, "eyes": "sharp"}},
	"柴野栗山": {"arch": "scholar", "title": "寛政異学の禁を進めた儒学者", "palette": {"kosode": "kuro:plain"}, "face": {"age": 55}},
	"中井竹山": {"arch": "scholar", "title": "大坂・懐徳堂の学主", "face": {"age": 60}},
	"本居宣長": {"arch": "scholar", "title": "『古事記伝』を著した国学者", "acc": ["suzu", "book"], "palette": {"kosode": "kon:plain", "hakama": "cha:plain"}, "face": {"age": 60}},
	"吉雄耕牛": {"arch": "scholar", "title": "長崎のオランダ通詞・蘭方医", "hair": "chonmage", "acc": ["book"], "face": {"age": 50}},
	"田沼意次": {"arch": "kamishimo", "title": "重商主義政策を進めた老中", "kamon": "shichiyo", "palette": {"hakama": "kon:plain"},
		"acc": ["kataginu:kon", "katana", "wakizashi", "sensu"], "face": {"age": 55}},
	"堀田正睦": {"arch": "kamishimo", "title": "条約勅許を求めて上洛した老中", "acc": ["kataginu:nezumi", "katana", "wakizashi", "sensu"], "face": {"age": 48}},
	"岩瀬忠震": {"arch": "kamishimo", "title": "通商条約の交渉に当たった幕臣", "acc": ["kataginu:ai", "katana", "wakizashi", "scroll"], "palette": {"hakama": "ai:plain"}, "face": {"age": 40}},
	"森山栄之助": {"arch": "scholar", "title": "英語を学んだ長崎のオランダ通詞", "aka": ["森山多吉郎"], "hair": "chonmage", "face": {"age": 38}},
	"タウンゼント＝ハリス": {"arch": "diplomat", "title": "初代アメリカ総領事", "aka": ["ハリス"], "hair_color": "gray", "acc": ["top_hat"], "face": {"age": 53, "hair_color": "gray"}},
	"九条尚忠": {"arch": "kariginu", "title": "幕末の関白", "face": {"age": 60}},
	"坂本龍馬": {"arch": "bakumatsu", "title": "薩長同盟を仲立ちした土佐の志士", "aka": ["坂本竜馬"], "kamon": "kikyokaku", "base": "HairSample_Male",
		"hide": ["tabi", "zori", "zori_hanao"], "extra": ["boots"], "palette": {"boots": "kuro"}, "acc": ["katana", "wakizashi", "pistol"],
		"face": {"age": 31}, "height": 1.74},
	# ── 明治・大正 ──
	"西郷隆盛": {"arch": "army", "title": "維新の三傑・陸軍大将", "hide": ["fcap", "fcap_star"],
		"palette": {"jacket": "kon", "collar_st": "kon", "pockets": "kon", "trousers": "kon", "collar_tab": "kin", "puttee": "kuro:plain", "boots": "kuro"},
		"acc": ["gunto", "aiguillette"], "face": {"age": 45, "brows": "bushy", "eyes": "large", "jaw": "broad"}, "height": 1.8, "build": Vector3(1.2, 1.0, 1.22)},
	"大久保利通": {"arch": "meiji_suit", "title": "維新の三傑・内務卿", "face": {"age": 45, "beard": "full", "mustache": "full", "sideburns": true}, "height": 1.78},
	"大隈重信": {"arch": "meiji_suit", "title": "立憲改進党を率いた政治家", "face": {"age": 60, "hair_color": "gray"}},
	"伊藤博文": {"arch": "meiji_suit", "title": "初代内閣総理大臣", "acc": ["top_hat"], "face": {"age": 55, "beard": "full", "mustache": "full", "hair_color": "gray"}, "height": 1.6},
	"井上毅": {"arch": "meiji_suit", "title": "大日本帝国憲法の起草者", "face": {"age": 45, "mustache": "thin"}},
	"三条実美": {"arch": "meiji_suit", "title": "明治政府の太政大臣", "face": {"age": 45, "mustache": "thin", "eyes": "gentle"}},
	"植木枝盛": {"arch": "meiji_suit", "title": "私擬憲法を起草した民権家", "outfit": "shosei", "hide": ["pcap_top", "pcap_band", "pcap_badge"], "palette": {}, "acc": ["book"], "face": {"age": 26}},
	"後藤象二郎": {"arch": "meiji_suit", "title": "大政奉還を建白した土佐の政治家", "face": {"age": 50, "mustache": "full"}},
	"陸奥宗光": {"arch": "meiji_suit", "title": "領事裁判権を撤廃させた外相", "face": {"age": 50, "mustache": "thin", "eyes": "sharp"}},
	"加藤高明": {"arch": "showa_suit", "title": "護憲三派内閣の首相", "face": {"age": 65, "mustache": "walrus", "hair_color": "gray"}},
	"小村寿太郎": {"arch": "meiji_suit", "title": "関税自主権を回復した外相", "face": {"age": 55, "mustache": "full", "beard": "goatee"}, "height": 1.5},
	"桂太郎": {"arch": "meiji_suit", "title": "日英同盟を結んだ首相", "face": {"age": 60, "mustache": "kaiser"}, "build": Vector3(1.08, 1.0, 1.08)},
	"高橋是清": {"arch": "showa_suit", "title": "「ダルマ」と親しまれた蔵相", "hair_color": "white",
		"face": {"age": 78, "beard": "full", "mustache": "full", "hair_color": "white", "jaw": "round"}, "build": Vector3(1.12, 1.0, 1.12)},
	"平塚らいてう": {"arch": "taisho_woman", "title": "『青鞜』を創刊した女性運動家", "aka": ["平塚雷鳥", "平塚明"], "base": "HairSample_Female"},
	"若槻礼次郎": {"arch": "showa_suit", "title": "憲政会・民政党の首相", "face": {"age": 60, "mustache": "thin"}},
	"原敬": {"arch": "showa_suit", "title": "初の本格的政党内閣を組織した首相", "hair_color": "white", "face": {"age": 63, "hair_color": "white"}},
	"幣原喜重郎": {"arch": "showa_suit", "title": "協調外交を進めた外相", "face": {"age": 55, "mustache": "thin"}},
	"英国公使マクドナルド": {"arch": "diplomat", "title": "駐日英国公使", "aka": ["クロード＝マクドナルド"], "face": {"age": 52, "mustache": "handlebar"}, "height": 1.8},
	# ── 昭和 ──
	"井上準之助": {"arch": "showa_suit", "title": "金解禁を断行した蔵相", "face": {"age": 60}},
	"田中義一": {"arch": "showa_suit", "title": "政友会総裁・首相（陸軍大将）", "face": {"age": 64, "mustache": "kaiser"}},
	"伊東巳代治": {"arch": "meiji_suit", "title": "憲法起草に参画した枢密顧問官", "face": {"age": 70, "mustache": "full", "beard": "goatee", "hair_color": "gray"}},
	"團琢磨": {"arch": "showa_suit", "title": "三井合名の理事長", "aka": ["団琢磨"], "face": {"age": 73, "mustache": "full", "beard": "short", "hair_color": "white"}},
	"リットン卿": {"arch": "diplomat", "title": "国際連盟調査団の団長", "aka": ["リットン"], "outfit": "showa_suit", "hide": [], "palette": {"jacket": "haiiro", "trousers": "haiiro", "tie": "kon"},
		"face": {"age": 56, "mustache": "thin"}, "height": 1.8},
	"内田康哉": {"arch": "showa_suit", "title": "「焦土外交」の外相", "face": {"age": 67, "mustache": "full", "hair_color": "gray"}},
	"犬養毅": {"arch": "showa_suit", "title": "「話せばわかる」政友会の首相", "hair_color": "white", "face": {"age": 76, "beard": "goatee", "mustache": "full", "hair_color": "white"}, "height": 1.55},
	"和田博雄": {"arch": "showa_suit", "title": "農地改革を進めた農林大臣", "acc": ["glasses"], "face": {"age": 44}},
	"渋沢敬三": {"arch": "showa_suit", "title": "戦後の蔵相・民俗学者", "acc": ["glasses"], "face": {"age": 50}},
	"十河信二": {"arch": "showa_suit", "title": "新幹線を実現させた国鉄総裁", "hair_color": "white", "acc": ["glasses"], "face": {"age": 75, "hair_color": "white"}},
	"下村治": {"arch": "showa_suit", "title": "所得倍増計画を理論づけた経済学者", "acc": ["glasses"], "face": {"age": 50}},
	"米内光政": {"arch": "navy_dark", "title": "日独伊三国同盟に反対した海軍大将・首相", "face": {"age": 60}, "height": 1.78},
	"畑俊六": {"arch": "army", "title": "陸軍大臣（元帥）", "face": {"age": 60, "mustache": "full"}},
	"松岡洋右": {"arch": "showa_suit", "title": "国際連盟脱退の全権・外相", "acc": ["glasses"], "face": {"age": 55, "mustache": "toothbrush"}},
	"コーデル・ハル": {"arch": "diplomat", "title": "アメリカ国務長官", "aka": ["ハル"], "outfit": "showa_suit", "hide": [], "hair_color": "white",
		"palette": {"jacket": "nezumi", "trousers": "nezumi", "tie": "kon"}, "face": {"age": 70, "hair_color": "white"}, "height": 1.78},
	"グルー大使": {"arch": "diplomat", "title": "駐日アメリカ大使", "aka": ["グルー"], "outfit": "showa_suit", "hide": [], "hair_color": "gray",
		"palette": {"jacket": "sumi", "trousers": "sumi", "tie": "enji"}, "face": {"age": 60, "mustache": "full", "brows": "bushy", "hair_color": "gray"}, "height": 1.8},
	"鈴木貫太郎": {"arch": "showa_suit", "title": "終戦を導いた首相（海軍大将）", "hair_color": "white", "face": {"age": 77, "mustache": "full", "brows": "bushy", "hair_color": "white"}},
	"東條英機": {"arch": "army", "title": "陸軍大将・首相", "acc": ["gunto", "medals", "glasses"], "face": {"age": 57, "mustache": "toothbrush"}},
	"山本五十六": {"arch": "navy", "title": "連合艦隊司令長官", "face": {"age": 57}, "height": 1.6},
}

static var _alias_cache := {}
static var _kamon_cache := {}
static var _mesh_cache := {}


# ===========================================================================
# 公開 API
# ===========================================================================

## 名前（「老中 田沼意次」「厩戸王（聖徳太子）」のような表記も可）→ 人物の設計。知らない人物なら {}
static func spec_for(name: String) -> Dictionary:
	var key := resolve(name)
	if key == "":
		return {}
	var f: Dictionary = FIGURES[key]
	var a: Dictionary = ARCH.get(f.get("arch", ""), {})
	var s := {}
	for d: Dictionary in [a, f]:
		for k: String in d:
			var v: Variant = d[k]
			if (k == "palette" or k == "face") and s.has(k):
				var merged: Dictionary = (s[k] as Dictionary).duplicate()
				merged.merge(v as Dictionary, true)
				s[k] = merged
			elif v is Dictionary or v is Array:
				s[k] = (v as Variant).duplicate()
			else:
				s[k] = v
	s["name"] = key
	s.erase("arch")
	s.erase("aka")
	var female: bool = s.get("female", false)
	s["female"] = female
	if not s.has("base"):
		var pool: Array = ["Sendagaya_Shino", "HairSample_Female"] if female else ["HairSample_Male", "Sakurada_Fumiriya", "Sendagaya_Shibu"]
		s["base"] = pool[absi(hash(key)) % pool.size()]
	var face: Dictionary = s.get("face", {})
	if s.has("hair_color") and not face.has("hair_color"):
		face["hair_color"] = s["hair_color"]
	face["female"] = female
	s["face"] = face
	if not s.has("hair_color"):
		s["hair_color"] = face.get("hair_color", "black")
	if not s.has("height"):
		var modern: bool = String(s.get("outfit", "")) in ["suit_meiji", "showa_suit", "army", "navy", "shosei", "haikara", "showa_m", "showa_f"]
		s["height"] = (1.55 if female else 1.68) if modern else (1.5 if female else 1.62)
	return s


## 名前 → FIGURES のキー（見つからなければ ""）
static func resolve(name: String) -> String:
	if _alias_cache.has(name):
		return _alias_cache[name]
	var n := name.strip_edges()
	var best := ""
	var cands := {}
	for k: String in FIGURES:
		cands[k] = k
		for al: String in (FIGURES[k] as Dictionary).get("aka", []):
			cands[al] = k
	if cands.has(n):
		best = cands[n]
	else:
		# 「肩書き 名前」「名前（別名）」「X（のちの名前）」の形だけを認める（「ザビエルの従者」は本人ではない）
		var best_len := 0
		var inner := ""
		var lp := n.find("（")
		if lp >= 0 and n.ends_with("）"):
			inner = n.substr(lp + 1, n.length() - lp - 2)
			if inner.begins_with("のちの"):
				inner = ""
		for c: String in cands:
			if c.length() < 2 or c.length() <= best_len:
				continue
			var ok := n.ends_with(" " + c) or n.ends_with("　" + c) or n.ends_with("・" + c) or n.begins_with(c + "（") or inner == c
			if ok:
				best = cands[c]
				best_len = c.length()
	_alias_cache[name] = best
	return best


## 歴史上の人物の姿を組み立てる（AnimeChar.build ＋ decorate）。知らない名前なら null
static func build(name: String, seed: int = 0, opts: Dictionary = {}) -> Node3D:
	var s := spec_for(name)
	if s.is_empty():
		push_warning("Figures: unknown figure " + name)
		return null
	var model: Node3D = AnimeChar.build(s["base"], s.get("outfit", "modern"), s.get("palette", {}), "")
	decorate(model, s, seed, opts)
	# 身長と体格（Humanoid に組み込む場合は Humanoid 側で同じ計算をする：integration_scale）
	model.scale = integration_scale(model, s)
	model.set_meta("figure", s["name"])
	model.set_meta("figure_title", s.get("title", ""))
	return model


## 身長・体格に合わせた素体の拡縮（Humanoid._construct_anime の model.scale の代わりに使える）
static func integration_scale(model: Node3D, s: Dictionary) -> Vector3:
	var h := _rest_height(model)
	var k: float = float(s.get("height", 1.62)) / maxf(h, 0.5)
	var b: Vector3 = s.get("build", Vector3.ONE)
	return Vector3(k * b.x, k * b.y, k * b.z)


## AnimeChar.build 済みの素体へ人物の特徴を後付けする。spec は spec_for の戻り値か名前
static func decorate(model: Node3D, spec: Variant, seed: int = 0, opts: Dictionary = {}) -> void:
	var s: Dictionary = spec if spec is Dictionary else spec_for(String(spec))
	if s.is_empty():
		return
	var sk := _skeleton(model)
	if sk == null:
		return
	# 髪（色つき）
	var hair: String = s.get("hair", "")
	if hair != "":
		AnimeHair.apply(model, hair, HAIR_TINT.get(s.get("hair_color", "black"), Color(1, 1, 1)))
	# 衣装の部位を隠す／足す
	for p: String in s.get("hide", []):
		var g := sk.get_node_or_null("Garment_" + p)
		if g:
			(g as Node3D).visible = false
	if not (s.get("extra", []) as Array).is_empty():
		_add_parts(model, sk, s["base"], s["extra"], s.get("palette", {}))
	var ctx := _context(model, sk, s)
	# 顔
	var face: Dictionary = s.get("face", {})
	var face_done := false
	if ResourceLoader.exists(FACE_SCRIPT):
		var fs := load(FACE_SCRIPT) as GDScript
		if fs and fs.can_instantiate():
			var applied: Variant = fs.call("apply", model, seed, face_opts(s))
			face_done = applied is Dictionary and not (applied as Dictionary).is_empty()
	if face_done:
		# AnimeFace の髭は顔に描く（口髭・顎髭・頬髭）。描けない形の口髭だけメッシュで足す
		var mf := {"mustache": face.get("mustache", "none"), "hair_color": face.get("hair_color", "black")}
		if String(mf["mustache"]) in ["kaiser", "walrus", "toothbrush", "handlebar"]:
			_fallback_facial_hair(ctx, mf)
	else:
		_fallback_facial_hair(ctx, face)
	if String(face.get("eyes", "")) == "closed":
		_close_eyes(model, 0.9)
	# 家紋
	var kamon: String = s.get("kamon", "")
	if kamon != "":
		_place_kamon(ctx, kamon, s.get("kamon_at", ["back", "sleeve", "chest"]), s.get("kamon_color", ""))
	# 小物（opts で選べる差分：例 {"helmet": true} で信長に南蛮兜）
	var accs: Array = (s.get("acc", []) as Array).duplicate()
	var opt_acc: Dictionary = s.get("acc_opt", {})
	for ok: String in opt_acc:
		if opts.get(ok, false):
			accs.append_array(opt_acc[ok])
	for a: String in accs:
		_accessory(ctx, a)


## 登録済みの人物名の一覧
static func names() -> Array:
	return FIGURES.keys()


## 人物の顔の指定 → AnimeFace.apply の opts（"fixed" で乱択の値を上書きする）
## face の項目: age(int) / beard(none|goatee|short|full|long) / mustache(none|thin|full|kaiser|walrus|toothbrush|handlebar)
##   sideburns / brows(thick|bushy|hikimayu) / eyes(gentle|sharp|closed|large) / jaw(broad|round) / skin / eye_color / hair_color
static func face_opts(s: Dictionary) -> Dictionary:
	var f: Dictionary = s.get("face", {})
	var female: bool = s.get("female", false)
	var age_n := int(f.get("age", 35))
	var age := "child" if age_n < 13 else ("young" if age_n < 26 else ("adult" if age_n < 56 else "elder"))
	var fx := {"height": 1.0, "glasses": false, "eyepatch": false, "scar": false, "mole": 0, "freckles": 0.0, "stoop": 0.0 if age_n < 70 else 5.0}
	if not female:
		var b: String = f.get("beard", "none")
		var m: String = f.get("mustache", "none")
		var has_m := m != "none"
		var beard := "none"
		match b:
			"full", "short":
				beard = "full"
			"long":
				beard = "mustache_goatee" if has_m else "goatee"
			"goatee":
				beard = "mustache_goatee" if has_m else "goatee"
			_:
				if has_m:
					beard = "dojo" if m == "thin" else ("none" if m in ["kaiser", "toothbrush", "handlebar"] else "mustache")
		if bool(f.get("sideburns", false)) and beard == "none":
			beard = "stubble"
		fx["beard"] = beard
		fx["long_beard"] = b == "long"
		fx["stubble"] = 0.0
		fx["blush"] = 0.0
	var hc: String = s.get("hair_color", f.get("hair_color", "black"))
	fx["hair_gray"] = 2 if hc == "white" else (1 if hc == "gray" else 0)
	if hc in ["brown", "blond", "auburn", "shaved"]:
		# AnimeFace は丸刈り（buzz）の髪色を 1.5 倍にするので割り戻す
		var ht: Color = HAIR_TINT[hc]
		fx["hair_tint"] = ht / 1.5 if String(s.get("hair", "")) == "buzz" else ht
	elif hc == "black":
		fx["hair_tint"] = Color(1, 1, 1)
	match String(f.get("eyes", "")):
		"gentle": fx["mood"] = "gentle"
		"sharp": fx["mood"] = "sharp"
		"closed": fx["mood"] = "calm"
		"large":
			fx["mood"] = "neutral"
			fx["eye_h"] = 1.0
			fx["iris_scale"] = 1.06
		_: fx["mood"] = "neutral" if age_n < 56 else "calm"
	match String(f.get("brows", "")):
		"thick": fx["brow_thick"] = 1.0
		"bushy":
			fx["brow_thick"] = 1.0
			fx["brow_y"] = -0.5
		"hikimayu":
			fx["brow_thick"] = -1.0
			fx["brow_y"] = 1.0
	match String(f.get("jaw", "")):
		"broad":
			fx["jaw"] = 1.0
			fx["cheek"] = 0.5
		"round":
			fx["cheek"] = 1.0
			fx["chin"] = -0.5
	if f.has("skin"):
		fx["skin"] = f["skin"]
	match String(f.get("eye_color", "")):
		"blue": fx["iris"] = Color(0.24, 0.42, 0.66)
		"brown": fx["iris"] = Color(0.42, 0.26, 0.13)
		"gray": fx["iris"] = Color(0.45, 0.5, 0.55)
	return {"age": age, "female": female, "modern": false, "fixed": fx}


## 目を閉じる（鑑真など）。VRoid の表情（Fcl_EYE_Close）を使う
static func _close_eyes(model: Node3D, w: float) -> void:
	for mi: MeshInstance3D in model.find_children("Face", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for bi in mi.mesh.get_blend_shape_count():
			var bn := String(mi.mesh.get_blend_shape_name(bi))
			if bn.ends_with("EYE_Close"):
				mi.set_blend_shape_value(bi, w)


# ===========================================================================
# 素体の寸法（T ポーズの骨格空間：+Z が正面、+X が人物の左）
# ===========================================================================

static func _skeleton(root: Node) -> Skeleton3D:
	var s := root.get_node_or_null("%GeneralSkeleton")
	if s is Skeleton3D:
		return s
	var a := root.find_children("*", "Skeleton3D", true, false)
	return a[0] if a.size() > 0 else null


static func _rest_height(model: Node3D) -> float:
	var aabb := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.visible or m.name.begins_with(NODE_PREFIX):
			continue
		var b: AABB = m.get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	return aabb.end.y


static func _bone_o(sk: Skeleton3D, b: String) -> Vector3:
	var i := sk.find_bone(b)
	return sk.get_bone_global_rest(i).origin if i >= 0 else Vector3.ZERO


static func _context(model: Node3D, sk: Skeleton3D, s: Dictionary) -> Dictionary:
	var face_ab := AABB(Vector3(-0.112, 1.493, -0.022), Vector3(0.224, 0.247, 0.15))
	var tmpl: Material = null
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.name == "Face":
			face_ab = mi.get_aabb()
		if mi.name == "Body" and mi.mesh and tmpl == null:
			tmpl = mi.mesh.surface_get_material(0)
	var k := face_ab.size.y / 0.247
	var head := _bone_o(sk, "Head")
	var L := {}
	L["k"] = k
	L["head"] = head
	L["top"] = face_ab.end.y
	L["face_z"] = face_ab.end.z
	L["face_y0"] = face_ab.position.y
	L["face_h"] = face_ab.size.y
	L["face_w"] = face_ab.size.x * 0.5
	L["eye"] = Vector3(0, face_ab.position.y + 0.37 * face_ab.size.y, face_ab.end.z - 0.03 * k)
	L["mouth"] = Vector3(0, face_ab.position.y + 0.13 * face_ab.size.y, face_ab.end.z - 0.03 * k)
	L["chin"] = Vector3(0, face_ab.position.y + 0.01 * k, face_ab.end.z - 0.05 * k)
	L["head_c"] = Vector3(0, face_ab.position.y + 0.55 * face_ab.size.y, face_ab.end.z - 0.105 * k)
	L["neck"] = _bone_o(sk, "Neck")
	L["chest"] = _bone_o(sk, "UpperChest")
	L["hips"] = _bone_o(sk, "Hips")
	L["shoulder_l"] = _bone_o(sk, "LeftUpperArm")
	L["shoulder_r"] = _bone_o(sk, "RightUpperArm")
	L["hand_l"] = _bone_o(sk, "LeftHand")
	L["hand_r"] = _bone_o(sk, "RightHand")
	# 胴回り：帯（ガーメントは前後が反転して書き出されている）→ 無ければ胴の推定
	var waist_y: float = L["hips"].y + 0.14 * k
	var waist_hd := 0.13 * k
	var waist_hw := 0.15 * k
	var front_z := 0.12 * k
	for gn: String in ["obi", "do", "jacket", "shirt"]:
		var g := sk.get_node_or_null("Garment_" + gn) as MeshInstance3D
		if g and g.visible and g.mesh:
			var ab := g.get_aabb()
			if gn == "obi":
				waist_y = ab.get_center().y
				waist_hd = ab.size.z * 0.5
				waist_hw = ab.size.x * 0.5
			elif gn == "do":
				waist_y = ab.position.y + 0.08 * k
				waist_hd = ab.size.z * 0.5
				waist_hw = ab.size.x * 0.5
				front_z = ab.size.z * 0.5
			break
	L["waist_y"] = waist_y
	L["waist_hd"] = waist_hd
	L["waist_hw"] = waist_hw
	L["front_z"] = front_z
	L["armor"] = String(s.get("outfit", "")) == "busho"
	L["suit"] = String(s.get("outfit", "")) in ["suit_meiji", "showa_suit", "army", "navy", "shosei"]
	return {"model": model, "sk": sk, "L": L, "tmpl": tmpl, "spec": s, "bas": {}}


# ===========================================================================
# 衣装の部位を足す（AnimeChar._dress と同じ手順で wasou glb から 1 部位だけ取り出す）
# ===========================================================================

static func _add_parts(model: Node3D, sk: Skeleton3D, base: String, parts: Array, pal: Dictionary) -> void:
	var path := AnimeChar.WASOU_DIR + base + ".glb"
	if not ResourceLoader.exists(path):
		return
	var src: Node = (load(path) as PackedScene).instantiate()
	var body: MeshInstance3D = sk.get_node_or_null("Body")
	var template: Material = body.mesh.surface_get_material(0) if body and body.mesh else null
	for mi: MeshInstance3D in src.find_children("*", "MeshInstance3D", true, false):
		var part := AnimeChar._part_name(mi.name)
		if not part in parts:
			continue
		var g := MeshInstance3D.new()
		g.name = "Garment_" + part
		g.mesh = mi.mesh
		sk.add_child(g)
		g.skeleton = g.get_path_to(sk)
		g.skin = AnimeChar._rebind(mi, sk)
		g.extra_cull_margin = 2.0
		var spec: PackedStringArray = String(pal.get(part, "kuro")).split(":")
		var dye: Array = _dye(spec[0])
		var tex: Texture2D = null
		if spec.size() > 1 and spec[1] != "plain":
			tex = AnimeChar.pattern_tex(spec[1], dye[0], _dye(spec[2] if spec.size() > 2 else "shiro")[0])
		g.material_override = AnimeChar._cloth_mat(template, dye[0], dye[1], true, tex)
	src.free()


# ===========================================================================
# 色・材質・骨への取り付け
# ===========================================================================

static func _dye(n: String) -> Array:
	if EXTRA_COL.has(n):
		return EXTRA_COL[n]
	return AnimeChar.DYES.get(n, AnimeChar.DYES["ai"])


## MToon（素体の材質を複製）。pattern を渡すと AnimeChar の布柄を貼る
static func _mat(ctx: Dictionary, col: String, outline := true, pattern := "", accent := "shiro", tile := Vector2(6, 6)) -> Material:
	var key := "%s|%s|%s|%s|%s" % [col, outline, pattern, accent, tile]
	var cache: Dictionary = ctx["bas"].get("_mats", {})
	if cache.has(key):
		return cache[key]
	var d := _dye(col)
	var tex: Texture2D = null
	if pattern != "":
		tex = AnimeChar.pattern_tex(pattern, d[0], _dye(accent)[0])
	var m := AnimeChar._cloth_mat(ctx["tmpl"], d[0], d[1], outline, tex)
	if tex and m is ShaderMaterial:
		(m as ShaderMaterial).set_shader_parameter("_MainTex_ST", Vector4(tile.x, tile.y, 0, 0))
	if m is ShaderMaterial and m.next_pass is ShaderMaterial:
		# 小物は細いので輪郭線を少し細く
		(m.next_pass as ShaderMaterial).set_shader_parameter("_OutlineWidth", 0.14)
	cache[key] = m
	ctx["bas"]["_mats"] = cache
	return m


## bone に追従する節点の下へ、T ポーズの骨格空間での変換 xf で node を置く
static func _put(ctx: Dictionary, bone: String, node: Node3D, xf: Transform3D) -> Node3D:
	var sk: Skeleton3D = ctx["sk"]
	var bas: Dictionary = ctx["bas"]
	var ba: BoneAttachment3D = bas.get(bone)
	if ba == null:
		ba = BoneAttachment3D.new()
		ba.name = NODE_PREFIX + "BA_" + bone
		ba.bone_name = bone
		sk.add_child(ba)
		bas[bone] = ba
	ba.add_child(node)
	var bi := sk.find_bone(bone)
	node.transform = sk.get_bone_global_rest(bi).affine_inverse() * xf
	return node


static func _mi(mesh: Mesh, mat: Material, nm := "") -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = NODE_PREFIX + nm
	m.mesh = mesh
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return m


## 基準（X, Y, Z 軸）と位置から変換を作る。Y を主軸として直交化する
static func _xf(pos: Vector3, y_axis: Vector3, z_hint: Vector3, scl := 1.0) -> Transform3D:
	var y := y_axis.normalized()
	var x := y.cross(z_hint).normalized()
	if x.length() < 0.01:
		x = y.cross(Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.FORWARD).normalized()
	var z := x.cross(y).normalized()
	return Transform3D(Basis(x, y, z).scaled(Vector3.ONE * scl), pos)


## 手で握る位置（T ポーズ）。主軸は「親指の方向（前）＋手首の方向」：腕を下ろすと前上がりになる
static func _grip(ctx: Dictionary, side: String, up_bias := 0.5) -> Dictionary:
	var L: Dictionary = ctx["L"]
	var k: float = L["k"]
	var h: Vector3 = L["hand_" + side]
	var fingers := Vector3(1, 0, 0) if side == "l" else Vector3(-1, 0, 0)
	var pos := h + fingers * 0.05 * k + Vector3(0, -0.028 * k, 0.012 * k)
	var axis := (Vector3(0, 0, 1) - fingers * up_bias).normalized()
	return {"pos": pos, "axis": axis, "fingers": fingers, "bone": "LeftHand" if side == "l" else "RightHand"}


# ===========================================================================
# メッシュの手続き生成
# ===========================================================================

## 三角形を、与えた法線の側から表になる向きで足す
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO) -> void:
	var g := (b - a).cross(c - a)
	if g.dot(na + nb + nc) > 0.0:
		var t := b; b = c; c = t
		var tn := nb; nb = nc; nc = tn
		var tu := ub; ub = uc; uc = tu
	st.set_normal(na); st.set_uv(ua); st.add_vertex(a)
	st.set_normal(nb); st.set_uv(ub); st.add_vertex(b)
	st.set_normal(nc); st.set_uv(uc); st.add_vertex(c)


## 汎用の曲面 fn(u, v) -> Vector3（u, v ∈ [0, 1]）。
## out(u, v) -> Vector3 は外向きの目安（閉じた立体用）。thickness > 0 なら両面＋縁のある板にする
static func _surf(fn: Callable, nu: int, nv: int, closed_u := false, thickness := 0.0, out: Callable = Callable(), uvs := Vector2.ONE) -> ArrayMesh:
	var P: Array[Vector3] = []
	var N: Array[Vector3] = []
	for j in nv + 1:
		for i in nu + 1:
			P.append(fn.call(float(i) / nu, float(j) / nv))
	var W := nu + 1
	for j in nv + 1:
		for i in nu + 1:
			var i0 := i - 1
			var i1 := i + 1
			if closed_u:
				i0 = (i - 1 + nu) % nu if i == 0 else i - 1
				i1 = 1 if i == nu else i + 1
			else:
				i0 = maxi(i - 1, 0)
				i1 = mini(i + 1, nu)
			var j0 := maxi(j - 1, 0)
			var j1 := mini(j + 1, nv)
			var du := P[j * W + i1] - P[j * W + i0]
			var dv := P[j1 * W + i] - P[j0 * W + i]
			var n := du.cross(dv)
			if n.length() < 1e-9:
				# 極（半径 0）は隣の行の法線を使う
				var jj := 1 if j == 0 else nv - 1
				n = (P[jj * W + i1] - P[jj * W + i0]).cross(P[mini(jj + 1, nv) * W + i] - P[maxi(jj - 1, 0) * W + i])
			n = n.normalized()
			if out.is_valid():
				var o: Vector3 = out.call(float(i) / nu, float(j) / nv)
				if o.length() > 1e-6 and n.dot(o) < 0.0:
					n = -n
			N.append(n)
	if out.is_valid():
		# 極などで向きが決まらない点は、近傍の多数決で揃える
		pass
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := thickness * 0.5
	for side in ([1.0, -1.0] if thickness > 0.0 else [1.0]):
		var sd: float = side
		for j in nv:
			for i in nu:
				var ids := [j * W + i, j * W + i + 1, (j + 1) * W + i + 1, (j + 1) * W + i]
				var pts: Array[Vector3] = []
				var nrm: Array[Vector3] = []
				var uv: Array[Vector2] = []
				for id: int in ids:
					pts.append(P[id] + N[id] * h * sd)
					nrm.append(N[id] * sd)
					uv.append(Vector2(float(id % W) / nu * uvs.x, float(id / W) / nv * uvs.y))
				_tri(st, pts[0], pts[1], pts[2], nrm[0], nrm[1], nrm[2], uv[0], uv[1], uv[2])
				_tri(st, pts[0], pts[2], pts[3], nrm[0], nrm[2], nrm[3], uv[0], uv[2], uv[3])
	if thickness > 0.0:
		# 縁（u の両端・v の両端）
		var edges: Array = []
		for i in nu:
			edges.append([i, i + 1])                                   # v = 0 の辺
			edges.append([nv * W + i + 1, nv * W + i])                 # v = 1 の辺
		if not closed_u:
			for j in nv:
				edges.append([(j + 1) * W, j * W])                    # u = 0
				edges.append([j * W + nu, (j + 1) * W + nu])          # u = 1
		for e: Array in edges:
			var a: int = e[0]
			var b: int = e[1]
			var a1 := P[a] + N[a] * h
			var b1 := P[b] + N[b] * h
			var a2 := P[a] - N[a] * h
			var b2 := P[b] - N[b] * h
			var en := (b1 - a1).cross(N[a]).normalized()
			# 外向き：曲面の中心から離れる側
			var mid := (P[a] + P[b]) * 0.5
			var c0 := P[(nv / 2) * W + nu / 2]
			if en.dot(mid - c0) < 0.0:
				en = -en
			_tri(st, a1, b1, b2, en, en, en)
			_tri(st, a1, b2, a2, en, en, en)
	return st.commit()


## 回転体（profile: Vector2(半径, 高さ) の列）。sx, sz で楕円に、a0..a1 で一部の角度だけにできる
static func _lathe(profile: Array, segs := 24, sx := 1.0, sz := 1.0, a0 := 0.0, a1 := TAU, thickness := 0.0) -> ArrayMesh:
	var full := is_equal_approx(a1 - a0, TAU)
	var nv := profile.size() - 1
	var fn := func(u: float, v: float) -> Vector3:
		var fi := v * nv
		var i0 := mini(int(floor(fi)), nv - 1)
		var t := fi - i0
		var p: Vector2 = (profile[i0] as Vector2).lerp(profile[i0 + 1] as Vector2, t)
		var a := a0 + (a1 - a0) * u
		return Vector3(sin(a) * p.x * sx, p.y, cos(a) * p.x * sz)
	var outf := func(u: float, v: float) -> Vector3:
		var p: Vector3 = fn.call(u, v)
		return Vector3(p.x, 0.0, p.z)
	return _surf(fn, segs, nv * 2 if nv < 6 else nv, full, thickness, outf if thickness == 0.0 else Callable())


## 管（path に沿った断面 rx × ry の楕円。radii は各点の半径倍率）。端は半径 0 の点を足して閉じる
static func _tube(path: PackedVector3Array, radii: PackedFloat32Array, rx := 1.0, ry := 1.0, segs := 10, hint := Vector3.UP, cap := true) -> ArrayMesh:
	var pts := path.duplicate()
	var rr := radii.duplicate()
	if cap:
		pts.insert(0, path[0])
		rr.insert(0, 0.0)
		pts.append(path[path.size() - 1])
		rr.append(0.0)
	var n := pts.size()
	var T: Array[Vector3] = []
	for i in n:
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, n - 1)]
		var t := (b - a)
		if t.length() < 1e-6:
			t = (pts[mini(i + 2, n - 1)] - pts[maxi(i - 2, 0)])
		T.append(t.normalized())
	var NN: Array[Vector3] = []
	var nh := hint - T[0] * hint.dot(T[0])
	if nh.length() < 1e-4:
		nh = Vector3.RIGHT - T[0] * T[0].x
	nh = nh.normalized()
	for i in n:
		if i > 0:
			nh = nh - T[i] * nh.dot(T[i])
			if nh.length() < 1e-5:
				nh = NN[i - 1]
			nh = nh.normalized()
		NN.append(nh)
	var fn := func(u: float, v: float) -> Vector3:
		var i := clampi(int(round(v * (n - 1))), 0, n - 1)
		var a := u * TAU
		var b := T[i].cross(NN[i])
		return pts[i] + (NN[i] * cos(a) * ry + b * sin(a) * rx) * rr[i]
	var outf := func(u: float, v: float) -> Vector3:
		var i := clampi(int(round(v * (n - 1))), 0, n - 1)
		var p: Vector3 = fn.call(u, v)
		var o := p - pts[i]
		return o if o.length() > 1e-6 else T[i] * (1.0 if i > n / 2 else -1.0)
	return _surf(fn, segs, n - 1, true, 0.0, outf)


## 平たい板（XY 平面の多角形を Z 方向に depth だけ押し出す）
static func _extrude(poly: PackedVector2Array, depth: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx := Geometry2D.triangulate_polygon(poly)
	var h := depth * 0.5
	var ab := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		ab = ab.expand(p)
	for t in range(0, idx.size(), 3):
		var a := poly[idx[t]]
		var b := poly[idx[t + 1]]
		var c := poly[idx[t + 2]]
		var uva := (a - ab.position) / ab.size
		var uvb := (b - ab.position) / ab.size
		var uvc := (c - ab.position) / ab.size
		_tri(st, Vector3(a.x, a.y, h), Vector3(b.x, b.y, h), Vector3(c.x, c.y, h), Vector3.BACK, Vector3.BACK, Vector3.BACK, uva, uvb, uvc)
		_tri(st, Vector3(a.x, a.y, -h), Vector3(b.x, b.y, -h), Vector3(c.x, c.y, -h), Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD, uva, uvb, uvc)
	var ccw := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		ccw += p.x * q.y - q.x * p.y
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		var e := (q - p).normalized()
		var n2 := Vector2(e.y, -e.x) if ccw > 0.0 else Vector2(-e.y, e.x)
		var n := Vector3(n2.x, n2.y, 0)
		_tri(st, Vector3(p.x, p.y, h), Vector3(q.x, q.y, h), Vector3(q.x, q.y, -h), n, n, n)
		_tri(st, Vector3(p.x, p.y, h), Vector3(q.x, q.y, -h), Vector3(p.x, p.y, -h), n, n, n)
	return st.commit()


static func _circle_poly(r: float, n := 24, cx := 0.0, cy := 0.0, sy := 1.0) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		p.append(Vector2(cx + cos(a) * r, cy + sin(a) * r * sy))
	return p


static func _sphere(r: float, segs := 12) -> ArrayMesh:
	var prof: Array = []
	for i in 7:
		var a := PI * i / 6.0
		prof.append(Vector2(sin(a) * r, -cos(a) * r))
	return _lathe(prof, segs)


static func _cyl(r: float, h: float, segs := 16, r2 := -1.0) -> ArrayMesh:
	var top := r if r2 < 0.0 else r2
	return _lathe([Vector2(0, -h * 0.5), Vector2(r, -h * 0.5), Vector2(top, h * 0.5), Vector2(0, h * 0.5)], segs)


static func _box(sz: Vector3) -> ArrayMesh:
	var bm := BoxMesh.new()
	bm.size = sz
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bm.get_mesh_arrays())
	return am


# ===========================================================================
# 家紋
# ===========================================================================

## 家紋の画像（白＝紋、黒＝墨の部分、透明＝地）。焼いた PNG があればそれを使う
static func kamon_texture(kind: String) -> Texture2D:
	if _kamon_cache.has(kind):
		return _kamon_cache[kind]
	var t: Texture2D = null
	var path := KAMON_DIR + kind + ".png"
	if ResourceLoader.exists(path):
		t = load(path)
	else:
		var img := kamon_image(kind, 96, 1)
		img.generate_mipmaps()
		t = ImageTexture.create_from_image(img)
	_kamon_cache[kind] = t
	return t


const KAMON_KINDS := ["mokko", "aoi", "kiri", "takeda", "takesuzume", "shimazu", "kiku", "futatsubiki", "mitsuuroko", "mori",
	"kikyo", "kikyokaku", "mitsudomoe", "kikusui", "janome", "kuroda", "chigaigama", "ageha", "sagarifuji", "shichiyo", "kuyo", "umebachi"]


static func kamon_image(kind: String, size := 256, ss := 2) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var acc := 0.0
			var ink := 0.0
			for sy in ss:
				for sx in ss:
					var px := ((x + (sx + 0.5) / ss) / size) * 2.0 - 1.0
					var py := 1.0 - ((y + (sy + 0.5) / ss) / size) * 2.0
					var v := _crest(kind, px * 1.04, py * 1.04)
					if v == 1:
						acc += 1.0
					elif v == 2:
						ink += 1.0
			var n := float(ss * ss)
			var a := (acc + ink) / n
			var w := acc / maxf(acc + ink, 0.001)
			img.set_pixel(x, y, Color(w, w, w, a))
	return img


static func _in_circle(x: float, y: float, cx: float, cy: float, r: float) -> bool:
	return (x - cx) * (x - cx) + (y - cy) * (y - cy) < r * r


static func _in_ring(x: float, y: float, r0: float, r1: float) -> bool:
	var d := x * x + y * y
	return d >= r0 * r0 and d < r1 * r1


static func _dseg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _in_tri(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	return Geometry2D.point_is_inside_triangle(p, a, b, c)


## 1: 紋, 2: 墨（紋の中の黒）, 0: 地
static func _crest(kind: String, x: float, y: float) -> int:
	var p := Vector2(x, y)
	var r := p.length()
	var ang := atan2(y, x)
	match kind:
		"shimazu":   # 丸に十字
			if _in_ring(x, y, 0.8, 0.98):
				return 1
			return 1 if (absf(x) < 0.13 and absf(y) < 0.8) or (absf(y) < 0.13 and absf(x) < 0.8) else 0
		"futatsubiki":   # 丸に二つ引両（足利・細川・今川）
			if _in_ring(x, y, 0.8, 0.98):
				return 1
			return 1 if r < 0.8 and (absf(y - 0.24) < 0.13 or absf(y + 0.24) < 0.13) else 0
		"janome":    # 蛇の目（加藤）
			return 1 if _in_ring(x, y, 0.5, 0.96) else 0
		"kuroda":    # 黒餅（黒田）：白の縁取りに墨の丸
			if _in_ring(x, y, 0.86, 0.98):
				return 1
			return 2 if r < 0.86 else 0
		"mitsuuroko":   # 三つ鱗（北条）
			var tris := [[Vector2(0, 0.84), Vector2(-0.48, 0.0), Vector2(0.48, 0.0)],
				[Vector2(-0.48, 0.0), Vector2(-0.96, -0.84), Vector2(0.0, -0.84)],
				[Vector2(0.48, 0.0), Vector2(0.0, -0.84), Vector2(0.96, -0.84)]]
			for t: Array in tris:
				var c: Vector2 = ((t[0] as Vector2) + (t[1] as Vector2) + (t[2] as Vector2)) / 3.0
				var s := 0.92
				if _in_tri(p, c + ((t[0] as Vector2) - c) * s, c + ((t[1] as Vector2) - c) * s, c + ((t[2] as Vector2) - c) * s):
					return 1
			return 0
		"takeda":    # 武田菱（割菱）
			if absf(x) / 0.95 + absf(y) / 0.66 > 1.0:
				return 0
			return 0 if absf(x) < 0.045 or absf(y) < 0.04 else 1
		"mori":      # 一文字に三つ星
			if absf(x) < 0.86 and y > 0.36 and y < 0.62 + 0.04 * sin(x * 3.0):
				return 1
			for c: Vector2 in [Vector2(0, -0.02), Vector2(-0.44, -0.6), Vector2(0.44, -0.6)]:
				if p.distance_to(c) < 0.28:
					return 1
			return 0
		"shichiyo", "kuyo":   # 七曜（田沼）・九曜
			var cnt := 6 if kind == "shichiyo" else 8
			var rr := 0.3 if kind == "shichiyo" else 0.24
			var ring_r := 0.64 if kind == "shichiyo" else 0.7
			if r < rr:
				return 1
			for i in cnt:
				var a := TAU * i / cnt + PI / 2
				if p.distance_to(Vector2(cos(a), sin(a)) * ring_r) < rr:
					return 1
			return 0
		"umebachi":  # 梅鉢（松平定信）
			if r < 0.2:
				return 1 if r < 0.12 else 0
			for i in 5:
				var a := TAU * i / 5 + PI / 2
				if p.distance_to(Vector2(cos(a), sin(a)) * 0.58) < 0.36:
					return 1
			# 剣（花弁の間の小さな線）
			for i in 5:
				var a := TAU * (i + 0.5) / 5 + PI / 2
				if _dseg(p, Vector2(cos(a), sin(a)) * 0.22, Vector2(cos(a), sin(a)) * 0.4) < 0.035:
					return 1
			return 0
		"kiku":      # 十六葉菊（皇室）
			if r < 0.17:
				return 1
			if r < 0.22:
				return 0
			var w := PI / 16.0
			var d := fposmod(ang + w, 2.0 * w) - w
			var front := r < 0.66 + 0.3 * sqrt(maxf(0.0, 1.0 - pow(d / w, 2.0)))
			if front and absf(d) * r > 0.018:
				return 1
			# 裏菊：表の花弁の間に覗く先端
			var d2 := fposmod(ang, 2.0 * w) - w
			if r > 0.7 and r < 0.6 + 0.36 * sqrt(maxf(0.0, 1.0 - pow(d2 / (w * 0.9), 2.0))) and absf(d) * r > 0.03:
				return 1
			return 0
		"kikusui":   # 菊水（楠木）：水の上に半菊
			if y > -0.12:
				var q := Vector2(x, y + 0.12)
				var rq := q.length()
				var aq := atan2(q.y, q.x)
				if rq < 0.16:
					return 1
				if rq < 0.2:
					return 0
				var w := PI / 16.0
				var dq := fposmod(aq + w, 2.0 * w) - w
				if rq < 0.6 + 0.3 * sqrt(maxf(0.0, 1.0 - pow(dq / w, 2.0))) and absf(dq) * rq > 0.018:
					return 1
				return 0
			for k in 3:
				var yy := -0.3 - k * 0.22 + 0.07 * sin(x * 5.0 + k * 1.3)
				if absf(y - yy) < 0.055 and absf(x) < 0.9 - k * 0.12:
					return 1
			return 0
		"kikyo", "kikyokaku":   # 桔梗（明智）／組み合い角に桔梗（坂本）
			var sc := 1.0
			if kind == "kikyokaku":
				var ax := absf(x)
				var ay := absf(y)
				var sq := maxf(ax, ay) > 0.8 and maxf(ax, ay) < 0.95
				var rx := absf(x + y) * 0.7071
				var ry := absf(x - y) * 0.7071
				var dm := maxf(rx, ry) > 0.8 and maxf(rx, ry) < 0.95
				if sq or dm:
					return 1
				sc = 1.0 / 0.62
			var qx := x * sc
			var qy := y * sc
			var qr := sqrt(qx * qx + qy * qy)
			var qa := atan2(qy, qx) - PI / 2
			var seg := TAU / 5.0
			var dd := fposmod(qa + seg * 0.5, seg) - seg * 0.5   # 花弁の中心からの角度
			var edge := 0.95 * (0.62 + 0.38 * cos(dd * 2.5))
			if qr > 0.9 - 0.25 * absf(dd) / (seg * 0.5) - 0.0 and absf(dd) < 0.09:
				edge = 0.98
			if qr >= edge:
				return 0
			if absf(absf(dd) - seg * 0.5) * qr < 0.03:
				return 0    # 花弁の境
			if qr < 0.12:
				return 0 if qr > 0.08 else 1
			if absf(dd) * qr < 0.02 and qr < 0.45:
				return 0    # 花芯の線
			return 1
		"mitsudomoe":   # 左三つ巴（小早川）
			if r > 0.97:
				return 0
			for k in 3:
				var th := PI / 2 + TAU * k / 3
				var hc := Vector2(cos(th), sin(th)) * 0.4
				if p.distance_to(hc) < 0.3:
					return 1
				var rel := fposmod(th - ang, TAU)
				if rel < 2.3:
					var t := rel / 2.3
					var cr := 0.4 + 0.52 * t
					var hw := 0.3 * pow(1.0 - t, 0.75)
					if absf(r - cr) < hw:
						var ok := true
						for kk in 3:
							if kk == k:
								continue
							var th2 := PI / 2 + TAU * kk / 3
							if p.distance_to(Vector2(cos(th2), sin(th2)) * 0.4) < 0.35:
								ok = false
						if ok:
							return 1
			return 0
		"mokko":     # 織田木瓜
			var lob := func(rad: float, rc: float) -> bool:
				for i in 5:
					var a := TAU * i / 5 + PI / 2
					if p.distance_to(Vector2(cos(a), sin(a)) * rad) < rc:
						return true
				return false
			var o1: bool = lob.call(0.5, 0.48)
			var o2: bool = lob.call(0.5, 0.4)
			if o1 and not o2:
				return 1
			var i1: bool = lob.call(0.33, 0.3)
			var i2: bool = lob.call(0.33, 0.235)
			if i1 and not i2:
				return 1
			if r < 0.07:
				return 1
			for i in 5:
				var a := TAU * i / 5 + PI / 2 + PI / 5
				if p.distance_to(Vector2(cos(a), sin(a)) * 0.14) < 0.065:
					return 1
			# 外と内をつなぐ剣
			for i in 5:
				var a := TAU * i / 5 + PI / 2 + PI / 5
				if _dseg(p, Vector2(cos(a), sin(a)) * 0.45, Vector2(cos(a), sin(a)) * 0.62) < 0.03:
					return 1
			return 0
		"aoi":       # 丸に三つ葉葵（徳川）
			if _in_ring(x, y, 0.86, 0.98):
				return 1
			if r < 0.07:
				return 1
			for k in 3:
				var th := PI / 2 + TAU * k / 3
				var dir := Vector2(cos(th), sin(th))
				var side := Vector2(-dir.y, dir.x)
				var q := p - dir * 0.43
				# ハート形（先端が外向き、くぼみが中心向き）
				var lx := q.dot(side) / 0.38
				var ly := -q.dot(dir) / 0.38 + 0.1
				var hv := pow(lx * lx + ly * ly - 1.0, 3.0) - lx * lx * pow(ly, 3.0)
				if hv < 0.0:
					# 葉脈（中央と斜め）
					if absf(lx) < 0.035 and ly < 0.75:
						return 0
					for sgn: float in [-1.0, 1.0]:
						var vv := Vector2(lx, ly)
						if _dseg(vv, Vector2(0, 0.1 - 0.3), Vector2(sgn * 0.6, 0.55)) < 0.03 or _dseg(vv, Vector2(0, -0.45), Vector2(sgn * 0.55, -0.05)) < 0.03:
							return 0
					return 1
				if q.dot(dir) < -0.25 and absf(p.dot(side)) < 0.03 and r < 0.2:
					return 1    # 茎
			return 0
		"kiri":      # 五七の桐（豊臣）
			# 葉：中央の大葉と左右の葉
			var leaves := [[Vector2(0, -0.25), 0.42, 0.0], [Vector2(-0.5, -0.38), 0.33, 0.6], [Vector2(0.5, -0.38), 0.33, -0.6]]
			for lf: Array in leaves:
				var c: Vector2 = lf[0]
				var s: float = lf[1]
				var rot: float = lf[2]
				var q := (p - c).rotated(rot) / s
				var hv := pow(q.x * q.x + pow(q.y * 1.15, 2.0) - 1.0, 3.0) - q.x * q.x * pow(-q.y * 1.15, 3.0)
				if hv < 0.0 and q.y > -0.95:
					if absf(q.x) < 0.04 or _dseg(q, Vector2(0, 0.1), Vector2(0.45, -0.35)) < 0.035 or _dseg(q, Vector2(0, 0.1), Vector2(-0.45, -0.35)) < 0.035:
						return 0
					return 1
			# 花：中央 7、左右 5
			var stems := [[0.0, 7, 0.95], [-0.42, 5, 0.75], [0.42, 5, 0.75]]
			for sm: Array in stems:
				var sx: float = sm[0]
				var cnt: int = sm[1]
				var top: float = sm[2]
				if absf(x - sx) < 0.025 and y > 0.05 and y < top:
					return 1
				for i in cnt:
					var fy := 0.18 + (top - 0.18) * float(i) / (cnt - 1)
					var fx := sx + (0.075 if i % 2 == 0 else -0.075)
					if p.distance_to(Vector2(fx, fy)) < 0.068:
						return 1
			return 0
		"chigaigama":   # 違い鎌（小早川秀秋）
			for sgn: float in [-1.0, 1.0]:
				var q := Vector2(x * sgn, y)
				if _dseg(q, Vector2(-0.62, -0.82), Vector2(0.2, 0.25)) < 0.075:
					return 1
				var bc := Vector2(-0.05, 0.25)
				var bd := q.distance_to(bc)
				var ba := atan2(q.y - bc.y, q.x - bc.x)
				if bd > 0.42 and bd < 0.42 + 0.17 * clampf((ba - 0.2) / 1.2, 0.0, 1.0) and ba > 0.2 and ba < 2.9:
					return 1
			return 0
		"ageha":     # 揚羽蝶（平氏）：正面向きに簡略
			var ax := absf(x)
			if ax < 0.06 and y > -0.55 and y < 0.45:
				return 1
			if _dseg(Vector2(ax, y), Vector2(0.03, 0.45), Vector2(0.28, 0.9)) < 0.03:
				return 1
			var uw := Vector2(ax - 0.45, y - 0.25).rotated(-0.45)
			if pow(uw.x / 0.42, 2.0) + pow(uw.y / 0.3, 2.0) < 1.0:
				return 0 if pow(uw.x / 0.26, 2.0) + pow(uw.y / 0.15, 2.0) < 1.0 and ax > 0.35 else 1
			var lw := Vector2(ax - 0.33, y + 0.35).rotated(0.6)
			if pow(lw.x / 0.3, 2.0) + pow(lw.y / 0.22, 2.0) < 1.0:
				return 1
			return 0
		"sagarifuji":   # 下り藤（藤原・本願寺）
			for sgn: float in [-1.0, 1.0]:
				var q := Vector2(x * sgn, y)
				# 上の葉（三枚）
				for li in 3:
					var la := 1.75 - li * 0.32
					var lc := Vector2(cos(la), sin(la)) * 0.78
					var lq := (q - lc).rotated(-(la - PI / 2) - 0.2)
					if pow(lq.x / 0.2, 2.0) + pow(lq.y / 0.075, 2.0) < 1.0:
						return 1 if absf(lq.y) > 0.012 or absf(lq.x) > 0.17 else 0
				# 花房：外側を下へ垂れ、下端で内へ巻く。花は二列、下ほど小さい
				for i in 13:
					var t := float(i) / 12.0
					var a := 1.25 - t * 2.75
					var rr := 0.62 - 0.12 * t * t
					var c := Vector2(cos(a) * rr * 0.9, sin(a) * rr)
					var sz := lerpf(0.13, 0.045, t)
					var nrm := Vector2(cos(a), sin(a))
					if q.distance_to(c + nrm * sz * 0.55) < sz or q.distance_to(c - nrm * sz * 0.45) < sz * 0.85:
						return 1
			return 0
		"takesuzume":   # 竹に雀（上杉）：竹の輪と向かい合う雀
			if _in_ring(x, y, 0.8, 0.92) and not (y < -0.7 and absf(x) < 0.25):
				return 1
			for i in 6:
				var a := PI * 0.25 + i * PI * 0.3
				var c := Vector2(cos(a), sin(a)) * 0.8
				var lq := (p - c).rotated(-a + 0.6)
				if pow(lq.x / 0.2, 2.0) + pow(lq.y / 0.06, 2.0) < 1.0:
					return 1
			for sgn: float in [-1.0, 1.0]:
				var q := Vector2(x * sgn, y)
				if q.distance_to(Vector2(0.28, 0.1)) < 0.22:   # 胴
					return 1
				if q.distance_to(Vector2(0.18, 0.3)) < 0.12:   # 頭
					return 1 if q.distance_to(Vector2(0.15, 0.33)) > 0.03 else 2
				var wq := Vector2(q.x - 0.42, q.y + 0.05).rotated(0.5)
				if pow(wq.x / 0.2, 2.0) + pow(wq.y / 0.1, 2.0) < 1.0:
					return 1
				if _in_tri(q, Vector2(0.38, -0.08), Vector2(0.6, -0.4), Vector2(0.45, -0.42)):
					return 1
			return 0
	return 0


## 家紋を Decal で衣へ投影する
static func _place_kamon(ctx: Dictionary, kind: String, at: Array, col_name: String) -> void:
	var L: Dictionary = ctx["L"]
	var s: Dictionary = ctx["spec"]
	var k: float = L["k"]
	var tex := kamon_texture(kind)
	var col := Color(0.97, 0.96, 0.92)
	if col_name != "":
		col = _dye(col_name)[0]
	else:
		# 地が明るい衣なら紺で染める
		var pal: Dictionary = s.get("palette", {})
		var main := String(pal.get("kosode", pal.get("kosode_t", "kon"))).get_slice(":", 0)
		var c: Color = _dye(main)[0]
		if c.get_luminance() > 0.55:
			col = _dye("kon")[0]
	var chest: Vector3 = L["chest"]
	var wz: float = L["waist_hd"]
	for slot: String in at:
		match slot:
			"back":
				_decal(ctx, "UpperChest", tex, col, Vector3(0, chest.y + 0.05 * k, -wz), Vector3(0, 0, -1), 0.1 * k)
			"chest":
				for sx: float in [1.0, -1.0]:
					_decal(ctx, "UpperChest", tex, col, Vector3(sx * 0.095 * k, chest.y + 0.08 * k, wz * 0.9), Vector3(0, 0, 1), 0.055 * k)
			"sleeve":
				for side: String in ["l", "r"]:
					var sh: Vector3 = L["shoulder_" + side]
					var sxs := 1.0 if side == "l" else -1.0
					_decal(ctx, ("Left" if side == "l" else "Right") + "UpperArm", tex, col,
						Vector3(sh.x + sxs * 0.2 * k, sh.y - 0.02 * k, -0.12 * k), Vector3(0, 0, -1), 0.06 * k, 0.12 * k)
			"do":
				_decal(ctx, "Chest", tex, Color(0.93, 0.74, 0.32), Vector3(0, chest.y - 0.06 * k, L["front_z"]), Vector3(0, 0, 1), 0.075 * k)
				_decal(ctx, "Chest", tex, Color(0.93, 0.74, 0.32), Vector3(0, chest.y - 0.02 * k, -L["front_z"]), Vector3(0, 0, -1), 0.09 * k)
			"kataginu":
				_decal(ctx, "UpperChest", tex, col, Vector3(0, chest.y + 0.04 * k, -wz - 0.02 * k), Vector3(0, 0, -1), 0.085 * k)
				for sx: float in [1.0, -1.0]:
					_decal(ctx, "UpperChest", tex, col, Vector3(sx * 0.1 * k, chest.y + 0.06 * k, wz + 0.02 * k), Vector3(0, 0, 1), 0.055 * k)


static func _decal(ctx: Dictionary, bone: String, tex: Texture2D, col: Color, pos: Vector3, normal: Vector3, size: float, depth := 0.14) -> void:
	var d := Decal.new()
	d.name = NODE_PREFIX + "Kamon"
	d.texture_albedo = tex
	d.modulate = col
	d.size = Vector3(size, depth, size)
	d.normal_fade = 0.25
	d.upper_fade = 0.05
	d.lower_fade = 0.05
	d.albedo_mix = 1.0
	d.cull_mask = 1
	# Decal は -Y 方向へ投影する：Y を外向きの法線に。紋の上下（-Z が上）を世界の上へ
	var y := normal.normalized()
	var z := Vector3(0, -1, 0)
	if absf(y.y) > 0.9:
		z = Vector3(0, 0, 1)
	var x := y.cross(z).normalized()
	z = x.cross(y).normalized()
	_put(ctx, bone, d, Transform3D(Basis(x, y, z), pos))


# ===========================================================================
# 帯状の面（path に沿って幅 width、各点の外向き法線 normals）
# ===========================================================================

static func _ribbon(path: PackedVector3Array, normals: PackedVector3Array, width: Variant, thick := 0.004, nu := 2) -> ArrayMesh:
	var n := path.size()
	var fn := func(u: float, v: float) -> Vector3:
		var fi := v * (n - 1)
		var i0 := mini(int(floor(fi)), n - 2)
		var t := fi - i0
		var p := path[i0].lerp(path[i0 + 1], t)
		var nn := normals[i0].lerp(normals[i0 + 1], t).normalized()
		var tg := (path[mini(i0 + 1, n - 1)] - path[i0]).normalized()
		var sd := tg.cross(nn).normalized()
		var w: float = width if (width is float or width is int) else lerpf((width as Vector2).x, (width as Vector2).y, v)
		return p + sd * (u - 0.5) * w
	return _surf(fn, nu, (n - 1) * 3, false, thick)


static func _merge(items: Array) -> ArrayMesh:
	## items: [[mesh, Transform3D], ...] → 1 つのメッシュ
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for it: Array in items:
		var m: Mesh = it[0]
		var xf: Transform3D = it[1]
		for si in m.get_surface_count():
			st.append_from(m, si, xf)
	return st.commit()


# ===========================================================================
# 小物
# ===========================================================================

static func _accessory(ctx: Dictionary, spec: String) -> void:
	var parts := spec.split(":")
	var id := parts[0]
	var c1: String = parts[1] if parts.size() > 1 else ""
	var c2: String = parts[2] if parts.size() > 2 else ""
	var L: Dictionary = ctx["L"]
	var k: float = L["k"]
	match id:
		"katana", "wakizashi", "tachi", "chokuto", "kanto_tachi", "gunto", "tanken":
			_sword(ctx, id, c1)
		"sensu", "tessen":
			var g := _grip(ctx, "r", 0.7)
			var poly := PackedVector2Array([Vector2(-0.011, 0), Vector2(0.011, 0), Vector2(0.017, 0.27), Vector2(-0.017, 0.27)])
			var col := c1 if c1 != "" else ("kuro" if id == "tessen" else "shiraki")
			var m := _mi(_extrude(poly, 0.014), _mat(ctx, col), "Fan")
			_put(ctx, g["bone"], m, _xf(g["pos"] - (g["axis"] as Vector3) * 0.04 * k, g["axis"], g["fingers"], k))
			if id == "tessen":
				var e := _mi(_extrude(PackedVector2Array([Vector2(-0.018, 0.25), Vector2(0.018, 0.25), Vector2(0.018, 0.272), Vector2(-0.018, 0.272)]), 0.016), _mat(ctx, "kin"), "FanTip")
				_put(ctx, g["bone"], e, _xf(g["pos"] - (g["axis"] as Vector3) * 0.04 * k, g["axis"], g["fingers"], k))
		"ogi_open", "hiougi":
			var g := _grip(ctx, "r", 0.9)
			var poly := PackedVector2Array()
			var spread := deg_to_rad(150.0 if id == "ogi_open" else 120.0)
			var R := 0.27 if id == "ogi_open" else 0.24
			for i in 17:
				var a := PI / 2 - spread / 2 + spread * i / 16.0
				poly.append(Vector2(cos(a), sin(a)) * R)
			for i in 17:
				var a := PI / 2 + spread / 2 - spread * i / 16.0
				poly.append(Vector2(cos(a), sin(a)) * 0.05)
			var col := c1 if c1 != "" else ("kin" if id == "ogi_open" else "shiraki")
			var fan := Node3D.new()
			fan.name = NODE_PREFIX + "OpenFan"
			fan.add_child(_mi(_extrude(poly, 0.005), _mat(ctx, col, true, "asanoha" if id == "hiougi" else "", "kin", Vector2(1, 1)), "Leaf"))
			fan.add_child(_mi(_extrude(PackedVector2Array([Vector2(-0.008, -0.01), Vector2(0.008, -0.01), Vector2(0.004, 0.06), Vector2(-0.004, 0.06)]), 0.012), _mat(ctx, "kogecha"), "Rivet"))
			if id == "ogi_open":
				var sun := _mi(_extrude(_circle_poly(0.06, 24, 0.0, 0.17), 0.007), _mat(ctx, "shu", false), "Sun")
				fan.add_child(sun)
			else:
				var cols := ["enji", "moegi", "shiro", "murasaki", "ki", "sakura"]
				for i in cols.size():
					var x := -0.02 + 0.008 * i
					var cord := _mi(_tube(PackedVector3Array([Vector3(x, 0.0, 0), Vector3(x * 1.5, -0.12, 0.01), Vector3(x * 2.0, -0.28, 0.0)]), PackedFloat32Array([1, 1, 1]), 0.003, 0.003, 6), _mat(ctx, cols[i], false), "Cord")
					fan.add_child(cord)
			_put(ctx, g["bone"], fan, _xf(g["pos"] - (g["axis"] as Vector3) * 0.03 * k, g["axis"], g["fingers"], k))
		"shaku":
			var g := _grip(ctx, "r", 0.9)
			var poly := PackedVector2Array([Vector2(-0.024, -0.06), Vector2(0.024, -0.06), Vector2(0.032, 0.26), Vector2(0.026, 0.285), Vector2(0, 0.292), Vector2(-0.026, 0.285), Vector2(-0.032, 0.26)])
			var m := _mi(_extrude(poly, 0.009), _mat(ctx, c1 if c1 != "" else "zouge"), "Shaku")
			_put(ctx, g["bone"], m, _xf(g["pos"], g["axis"], g["fingers"], k))
		"gunbai":
			var g := _grip(ctx, "r", 0.8)
			var n := Node3D.new()
			n.name = NODE_PREFIX + "Gunbai"
			var leaf := PackedVector2Array()
			for i in 28:
				var a := TAU * i / 28.0
				leaf.append(Vector2(cos(a) * 0.15, 0.32 + sin(a) * 0.15 + (0.0 if sin(a) > -0.5 else (sin(a) + 0.5) * 0.06)))
			n.add_child(_mi(_extrude(leaf, 0.012), _mat(ctx, c1 if c1 != "" else "urushi"), "Leaf"))
			n.add_child(_mi(_extrude(_circle_poly(0.06, 24, 0.0, 0.33), 0.016), _mat(ctx, "kin", false), "Sun"))
			n.add_child(_mi(_extrude(PackedVector2Array([Vector2(-0.014, -0.05), Vector2(0.014, -0.05), Vector2(0.02, 0.19), Vector2(-0.02, 0.19)]), 0.02), _mat(ctx, "kin"), "Handle"))
			_put(ctx, g["bone"], n, _xf(g["pos"], g["axis"], g["fingers"], k))
		"scroll":
			var g := _grip(ctx, "l", 0.3)
			var n := Node3D.new()
			n.name = NODE_PREFIX + "Scroll"
			n.add_child(_mi(_cyl(0.022, 0.24, 16), _mat(ctx, "kinari", true, "asanoha", "kin", Vector2(2, 2)), "Roll"))
			for sy: float in [-1.0, 1.0]:
				var knob := _mi(_cyl(0.012, 0.03, 10), _mat(ctx, "kogecha"), "Knob")
				knob.position = Vector3(0, sy * 0.135, 0)
				n.add_child(knob)
			_put(ctx, g["bone"], n, _xf(g["pos"], g["axis"], g["fingers"], k))
		"book":
			var g := _grip(ctx, "l", 0.2)
			var n := Node3D.new()
			n.name = NODE_PREFIX + "Book"
			var cover := _mi(_box(Vector3(0.15, 0.21, 0.022)), _mat(ctx, c1 if c1 != "" else "kon"), "Cover")
			cover.position = Vector3(0.06, 0.06, 0)
			n.add_child(cover)
			var pages := _mi(_box(Vector3(0.152, 0.2, 0.016)), _mat(ctx, "kinari", false), "Pages")
			pages.position = Vector3(0.062, 0.06, 0)
			n.add_child(pages)
			_put(ctx, g["bone"], n, _xf(g["pos"], g["axis"], g["fingers"], k))
		"tanzaku":
			var g := _grip(ctx, "l", 0.4)
			var m := _mi(_box(Vector3(0.06, 0.36, 0.004)), _mat(ctx, "kinari", true, "asanoha", "kin", Vector2(1, 3)), "Tanzaku")
			m.position = Vector3(0, 0.12, 0)
			var n := Node3D.new()
			n.name = NODE_PREFIX + "TanzakuRoot"
			n.add_child(m)
			_put(ctx, g["bone"], n, _xf(g["pos"], g["axis"], g["fingers"], k))
		"juzu":
			var g := _grip(ctx, "l", 0.2)
			var items: Array = []
			var bead := _sphere(0.0085, 8)
			for i in 27:
				var a := TAU * i / 27.0
				items.append([bead, Transform3D(Basis(), Vector3(cos(a) * 0.075, 0, sin(a) * 0.055))])
			var big := _sphere(0.014, 10)
			items.append([big, Transform3D(Basis(), Vector3(0.075, 0, 0))])
			var n := Node3D.new()
			n.name = NODE_PREFIX + "Juzu"
			var ring := _mi(_merge(items), _mat(ctx, c1 if c1 != "" else "kogecha"), "Beads")
			n.add_child(ring)
			var tassel := _mi(_cyl(0.004, 0.06, 8, 0.016), _mat(ctx, "murasaki"), "Tassel")
			tassel.position = Vector3(0.11, 0, 0)
			tassel.rotation = Vector3(0, 0, PI / 2)
			n.add_child(tassel)
			var fingers: Vector3 = g["fingers"]
			_put(ctx, g["bone"], n, Transform3D(Basis(Vector3(fingers.x, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, fingers.x)).scaled(Vector3.ONE * k), g["pos"] + fingers * 0.01 * k))
		"vajra":
			var g := _grip(ctx, "r", 0.6)
			var n := Node3D.new()
			n.name = NODE_PREFIX + "Vajra"
			var gold := _mat(ctx, "kin")
			n.add_child(_mi(_lathe([Vector2(0, -0.06), Vector2(0.012, -0.055), Vector2(0.009, -0.03), Vector2(0.014, -0.015), Vector2(0.009, 0), Vector2(0.014, 0.015), Vector2(0.009, 0.03), Vector2(0.012, 0.055), Vector2(0, 0.06)], 12), gold, "Grip"))
			for sy: float in [-1.0, 1.0]:
				for i in 3:
					var a := TAU * i / 3.0
					var o := Vector3(cos(a), 0, sin(a))
					var pts := PackedVector3Array([Vector3(0, sy * 0.055, 0), o * 0.02 + Vector3(0, sy * 0.075, 0), o * 0.022 + Vector3(0, sy * 0.1, 0), Vector3(0, sy * 0.125, 0)])
					n.add_child(_mi(_tube(pts, PackedFloat32Array([1, 1, 0.8, 0.5]), 0.004, 0.004, 6), gold, "Prong"))
				var mid := _mi(_tube(PackedVector3Array([Vector3(0, sy * 0.055, 0), Vector3(0, sy * 0.13, 0)]), PackedFloat32Array([1, 0.4]), 0.005, 0.005, 6), gold, "Prong")
				n.add_child(mid)
			_put(ctx, g["bone"], n, _xf(g["pos"], g["axis"], g["fingers"], k))
		"chawan":
			var g := _grip(ctx, "l", 0.0)
			var m := _mi(_lathe([Vector2(0, 0), Vector2(0.025, 0), Vector2(0.03, 0.008), Vector2(0.055, 0.03), Vector2(0.062, 0.065), Vector2(0.055, 0.066), Vector2(0.048, 0.035), Vector2(0, 0.025)], 18), _mat(ctx, c1 if c1 != "" else "kuro"), "Chawan")
			var fingers: Vector3 = g["fingers"]
			_put(ctx, g["bone"], m, _xf(g["pos"] + Vector3(0, -0.02, 0.02) * k, -fingers, Vector3(0, 0, 1), k))
		"suzu":
			var g := _grip(ctx, "l", 0.2)
			var n := Node3D.new()
			n.name = NODE_PREFIX + "Suzu"
			for i in 3:
				var b := _mi(_sphere(0.017, 10), _mat(ctx, "kin"), "Bell")
				b.position = Vector3(0.025 * (i - 1), -0.06 - 0.01 * (i % 2), 0)
				n.add_child(b)
			n.add_child(_mi(_tube(PackedVector3Array([Vector3(-0.025, -0.05, 0), Vector3(0, 0.02, 0), Vector3(0.025, -0.05, 0)]), PackedFloat32Array([1, 1, 1]), 0.003, 0.003, 6), _mat(ctx, "shu", false), "Cord"))
			var fingers: Vector3 = g["fingers"]
			_put(ctx, g["bone"], n, _xf(g["pos"], -fingers, Vector3(0, 0, 1), k))
		"chisel", "hammer":
			var g := _grip(ctx, "l" if id == "chisel" else "r", 0.5)
			var n := Node3D.new()
			n.name = NODE_PREFIX + id
			if id == "chisel":
				var h := _mi(_cyl(0.011, 0.12, 10), _mat(ctx, "shiraki"), "Handle")
				h.position = Vector3(0, 0.03, 0)
				n.add_child(h)
				var b := _mi(_box(Vector3(0.016, 0.07, 0.004)), _mat(ctx, "gin"), "Blade")
				b.position = Vector3(0, 0.12, 0)
				n.add_child(b)
			else:
				var h := _mi(_cyl(0.012, 0.3, 10), _mat(ctx, "shiraki"), "Handle")
				h.position = Vector3(0, 0.08, 0)
				n.add_child(h)
				var b := _mi(_box(Vector3(0.1, 0.04, 0.04)), _mat(ctx, "tetsu"), "Head")
				b.position = Vector3(0, 0.22, 0)
				n.add_child(b)
			_put(ctx, g["bone"], n, _xf(g["pos"], g["axis"], g["fingers"], k))
		"teppo", "yari":
			var g := _grip(ctx, "r", 0.0)
			var up := -(g["fingers"] as Vector3)
			var n := Node3D.new()
			n.name = NODE_PREFIX + id
			if id == "teppo":
				var barrel := _mi(_cyl(0.012, 1.0, 10, 0.01), _mat(ctx, "tetsu"), "Barrel")
				barrel.position = Vector3(0, 0.3, 0.012)
				n.add_child(barrel)
				var stock := _mi(_extrude(PackedVector2Array([Vector2(-0.02, 0.75), Vector2(0.024, 0.75), Vector2(0.026, -0.1), Vector2(0.03, -0.22), Vector2(0.05, -0.36), Vector2(-0.01, -0.36), Vector2(-0.024, -0.1)]), 0.035), _mat(ctx, "kogecha"), "Stock")
				stock.rotation = Vector3(0, PI / 2, 0)
				n.add_child(stock)
				var lock := _mi(_box(Vector3(0.012, 0.05, 0.01)), _mat(ctx, "kin"), "Lock")
				lock.position = Vector3(0.02, -0.08, 0.0)
				n.add_child(lock)
				_put(ctx, g["bone"], n, _xf(g["pos"] + up * 0.05 * k, up, Vector3(0, 0, 1), k))
			else:
				var shaft := _mi(_cyl(0.014, 2.4, 10), _mat(ctx, "urushi"), "Shaft")
				shaft.position = Vector3(0, 0.25, 0)
				n.add_child(shaft)
				var blade := _mi(_lathe([Vector2(0, 0), Vector2(0.018, 0.02), Vector2(0.012, 0.15), Vector2(0, 0.24)], 4, 1.0, 0.35), _mat(ctx, "gin"), "Blade")
				blade.position = Vector3(0, 1.45, 0)
				n.add_child(blade)
				_put(ctx, g["bone"], n, _xf(g["pos"], up, Vector3(0, 0, 1), k))
		"yumi":
			var g := _grip(ctx, "l", 0.0)
			var up := -(g["fingers"] as Vector3)
			var pts := PackedVector3Array()
			var rad := PackedFloat32Array()
			for i in 15:
				var t := float(i) / 14.0
				var y := lerpf(-0.75, 1.35, t)
				var s := (y - 0.3) / 1.05
				pts.append(Vector3(0, y, -0.13 * (1.0 - s * s) + 0.03 * pow(absf(s), 6.0)))
				rad.append(lerpf(1.0, 0.55, absf(s)))
			var n := Node3D.new()
			n.name = NODE_PREFIX + "Yumi"
			n.add_child(_mi(_tube(pts, rad, 0.012, 0.016, 8), _mat(ctx, c1 if c1 != "" else "urushi"), "Bow"))
			n.add_child(_mi(_tube(PackedVector3Array([pts[0], pts[pts.size() - 1]]), PackedFloat32Array([1, 1]), 0.0025, 0.0025, 5, Vector3.RIGHT, false), _mat(ctx, "kinari", false), "String"))
			var grip_wrap := _mi(_cyl(0.019, 0.1, 10), _mat(ctx, "enji"), "GripWrap")
			grip_wrap.position = Vector3(0, 0, -0.13 * (1.0 - pow(-0.3 / 1.05, 2)))
			n.add_child(grip_wrap)
			_put(ctx, g["bone"], n, _xf(g["pos"], up, Vector3(0, 0, -1), k))
		"pistol":
			var n := Node3D.new()
			n.name = NODE_PREFIX + "Pistol"
			var steel := _mat(ctx, "tetsu")
			var barrel := _mi(_cyl(0.0085, 0.13, 10), steel, "Barrel")
			barrel.position = Vector3(0, -0.07, 0)
			n.add_child(barrel)
			var cylm := _mi(_cyl(0.019, 0.038, 12), steel, "Cylinder")
			cylm.position = Vector3(0, 0.0, 0)
			n.add_child(cylm)
			var frame := _mi(_box(Vector3(0.014, 0.05, 0.03)), steel, "Frame")
			frame.position = Vector3(0, 0.03, -0.012)
			n.add_child(frame)
			var gripm := _mi(_box(Vector3(0.022, 0.075, 0.016)), _mat(ctx, "cha"), "Grip")
			gripm.position = Vector3(0, 0.075, -0.035)
			gripm.rotation = Vector3(-0.45, 0, 0)
			n.add_child(gripm)
			_put(ctx, "Hips", n, Transform3D(Basis().scaled(Vector3.ONE * k), Vector3(-0.08 * k, L["waist_y"] + 0.03 * k, L["waist_hd"] + 0.022 * k)))
		"hyotan":
			var n := Node3D.new()
			n.name = NODE_PREFIX + "Hyotan"
			n.add_child(_mi(_lathe([Vector2(0, -0.11), Vector2(0.04, -0.1), Vector2(0.056, -0.07), Vector2(0.05, -0.035), Vector2(0.024, -0.01), Vector2(0.036, 0.02), Vector2(0.036, 0.045), Vector2(0.016, 0.065), Vector2(0.01, 0.08), Vector2(0, 0.082)], 16), _mat(ctx, "kin"), "Gourd"))
			var cord := _mi(_tube(PackedVector3Array([Vector3(0, 0.07, 0), Vector3(0.0, 0.12, 0.0), Vector3(0, 0.16, -0.01)]), PackedFloat32Array([1, 1, 1]), 0.004, 0.004, 6), _mat(ctx, "shu", false), "Cord")
			n.add_child(cord)
			_put(ctx, "Hips", n, Transform3D(Basis().scaled(Vector3.ONE * k), Vector3(-L["waist_hw"] * 0.8, L["waist_y"] - 0.18 * k, L["waist_hd"] * 0.55)))
		"magatama":
			var n := Node3D.new()
			n.name = NODE_PREFIX + "Magatama"
			var neck: Vector3 = L["neck"]
			var items: Array = []
			var bead := _sphere(0.0085, 8)
			var cnt := 22
			for i in cnt:
				var a := TAU * i / cnt
				var front := (cos(a) + 1.0) * 0.5
				items.append([bead, Transform3D(Basis(), Vector3(sin(a) * 0.088, -0.05 * front, cos(a) * 0.09 + 0.01))])
			n.add_child(_mi(_merge(items), _mat(ctx, "midori"), "Beads"))
			var mpoly := PackedVector2Array()
			for i in 20:
				var a := TAU * i / 20.0
				mpoly.append(Vector2(cos(a) * 0.012, sin(a) * 0.012 + 0.008))
			var tail := PackedVector2Array([Vector2(0.012, 0.004), Vector2(0.01, -0.012), Vector2(0.0, -0.024), Vector2(-0.008, -0.02), Vector2(-0.006, -0.008), Vector2(-0.012, 0.004)])
			var merged := Geometry2D.merge_polygons(mpoly, tail)
			var shape: PackedVector2Array = merged[0] if merged.size() > 0 else mpoly
			for i in 3:
				var mg := _mi(_extrude(shape, 0.008), _mat(ctx, "hisui"), "Jewel")
				mg.position = Vector3((i - 1) * 0.03, -0.05 - 0.008 * (1 - absi(i - 1)), 0.1)
				mg.rotation = Vector3(0, 0, (i - 1) * -0.3)
				n.add_child(mg)
			_put(ctx, "UpperChest", n, Transform3D(Basis().scaled(Vector3.ONE * k), Vector3(0, neck.y - 0.02 * k, neck.z)))
		"mirror":
			var chest: Vector3 = L["chest"]
			var n := Node3D.new()
			n.name = NODE_PREFIX + "Mirror"
			var disc := _mi(_lathe([Vector2(0, -0.006), Vector2(0.062, -0.006), Vector2(0.066, 0.0), Vector2(0.062, 0.006), Vector2(0.05, 0.007), Vector2(0.02, 0.006), Vector2(0.012, 0.014), Vector2(0, 0.015)], 24), _mat(ctx, "seidou"), "Disc")
			disc.rotation = Vector3(PI / 2, 0, 0)
			n.add_child(disc)
			for sx: float in [-1.0, 1.0]:
				n.add_child(_mi(_tube(PackedVector3Array([Vector3(sx * 0.01, 0.03, -0.004), Vector3(sx * 0.05, 0.13, -0.03), Vector3(sx * 0.07, 0.2, -0.08)]), PackedFloat32Array([1, 1, 1]), 0.003, 0.003, 5), _mat(ctx, "shu", false), "Cord"))
			_put(ctx, "UpperChest", n, Transform3D(Basis().scaled(Vector3.ONE * k), Vector3(0, chest.y - 0.02 * k, L["waist_hd"] + 0.035 * k)))
		"crucifix":
			var chest: Vector3 = L["chest"]
			var n := Node3D.new()
			n.name = NODE_PREFIX + "Cross"
			var gold := _mat(ctx, c1 if c1 != "" else "kin")
			var v := _mi(_box(Vector3(0.014, 0.075, 0.008)), gold, "V")
			n.add_child(v)
			var h := _mi(_box(Vector3(0.05, 0.014, 0.008)), gold, "H")
			h.position = Vector3(0, 0.015, 0)
			n.add_child(h)
			var chain := PackedVector3Array()
			for i in 13:
				var a := -PI * 0.5 + TAU * i / 12.0
				chain.append(Vector3(cos(a) * 0.075, 0.13 + sin(a) * 0.1 + 0.0, 0.0))
			n.add_child(_mi(_tube(PackedVector3Array([Vector3(0, 0.04, 0), Vector3(-0.05, 0.12, -0.03), Vector3(-0.08, 0.22, -0.1)]), PackedFloat32Array([1, 1, 1]), 0.002, 0.002, 5), gold, "Chain"))
			n.add_child(_mi(_tube(PackedVector3Array([Vector3(0, 0.04, 0), Vector3(0.05, 0.12, -0.03), Vector3(0.08, 0.22, -0.1)]), PackedFloat32Array([1, 1, 1]), 0.002, 0.002, 5), gold, "Chain"))
			_put(ctx, "UpperChest", n, Transform3D(Basis().scaled(Vector3.ONE * k), Vector3(0, chest.y - 0.04 * k, L["waist_hd"] + 0.02 * k)))
		"white_collar":
			var neck: Vector3 = L["neck"]
			var m := _mi(_lathe([Vector2(0.058, -0.02), Vector2(0.062, -0.02), Vector2(0.06, 0.012), Vector2(0.056, 0.012)], 20, 1.0, 1.05), _mat(ctx, "shiro"), "Collar")
			_put(ctx, "Neck", m, Transform3D(Basis().scaled(Vector3.ONE * k), neck + Vector3(0, 0.01 * k, 0.005 * k)))
		"ruff":
			var neck: Vector3 = L["neck"]
			var fn := func(u: float, v: float) -> Vector3:
				var a := u * TAU
				var r := lerpf(0.07, 0.16, v)
				return Vector3(sin(a) * r, 0.028 * sin(a * 22.0) * v + 0.02 * v, cos(a) * r * 1.08)
			var m := _mi(_surf(fn, 88, 3, true, 0.008), _mat(ctx, "shiro"), "Ruff")
			_put(ctx, "Neck", m, Transform3D(Basis().scaled(Vector3.ONE * k), neck + Vector3(0, -0.035 * k, 0.012 * k)))
		"medals":
			var chest: Vector3 = L["chest"]
			var n := Node3D.new()
			n.name = NODE_PREFIX + "Medals"
			var cols := ["enji", "kin", "ai", "moegi", "shiro", "murasaki"]
			for i in 6:
				var b := _mi(_box(Vector3(0.022, 0.008, 0.006)), _mat(ctx, cols[i], false), "Ribbon")
				b.position = Vector3(0.023 * (i % 3), -0.011 * (i / 3), 0)
				n.add_child(b)
			_put(ctx, "UpperChest", n, Transform3D(Basis().scaled(Vector3.ONE * k), Vector3(0.055 * k, chest.y + 0.035 * k, 0.118 * k)))
		"aiguillette":
			var chest: Vector3 = L["chest"]
			var n := Node3D.new()
			n.name = NODE_PREFIX + "Aiguillette"
			var gold := _mat(ctx, "kin", false)
			for i in 2:
				var dy := 0.035 * i
				var pts := PackedVector3Array([Vector3(-0.15, chest.y + 0.13, 0.01), Vector3(-0.15, chest.y + 0.06 - dy, 0.1), Vector3(-0.11, chest.y - 0.02 - dy, 0.13), Vector3(-0.06, chest.y + 0.02 - dy * 0.3, 0.135), Vector3(-0.035, chest.y + 0.07, 0.13)])
				n.add_child(_mi(_tube(pts, PackedFloat32Array([1, 1, 1, 1, 1]), 0.0045, 0.0045, 6), gold, "Cord"))
			_put(ctx, "UpperChest", n, Transform3D(Basis().scaled(Vector3.ONE * k), Vector3.ZERO).translated(Vector3.ZERO))
		"kesa":
			_kesa(ctx, c1 if c1 != "" else "kuchiba", c2 if c2 != "" else "kin")
		"kataginu":
			_kataginu(ctx, c1 if c1 != "" else "nezumi")
		"cape":
			_cape(ctx, c1 if c1 != "" else "biro", c2 if c2 != "" else "kin")
		"hire":
			_hire(ctx, c1 if c1 != "" else "shiro")
		"kasane":
			_kasane(ctx, parts.slice(1))
		"mo", "kyo":
			_train(ctx, id, c1 if c1 != "" else "shiro")
		"hachimaki", "kofun_crown", "kofun_crown_band", "hokan", "hokan_m", "boku", "kanmuri", "kanmuri_ryuei", "eboshi", "ori_eboshi", "zukin", "fur_hat", "top_hat":
			_headwear(ctx, id, c1)
		"shokaku_kabuto", "nanban_kabuto", "nagaeboshi", "ichinotani", "bariki", "shida_maedate":
			_helmet(ctx, id)
		"glasses":
			_glasses(ctx, c1 if c1 != "" else "kin")
		_:
			push_warning("Figures: unknown accessory " + id)


## 刀：鞘の口（鯉口）の位置と向きを決めて、柄・鍔・鞘を組む
static func _sword(ctx: Dictionary, id: String, col: String) -> void:
	var L: Dictionary = ctx["L"]
	var k: float = L["k"]
	var wy: float = L["waist_y"]
	var wd: float = L["waist_hd"]
	var blade := 0.72
	var hilt := 0.25
	var sori := 0.018
	var edge_up := true
	var saya_c := "urushi"
	var tsuka_c := "kuro"
	var fit_c := "kin"
	var koi := Vector3(0.11, wy + 0.005, wd * 0.88)
	var dir := Vector3(0.5, -0.42, -1.0)
	var bone := "Hips"
	match id:
		"wakizashi":
			blade = 0.45; hilt = 0.18
			koi = Vector3(0.065, wy + 0.025 * k, wd * 0.98)
			dir = Vector3(0.42, -0.28, -1.0)
		"tachi":
			blade = 0.78; hilt = 0.24; sori = 0.03; edge_up = false
			koi = Vector3(0.17 * k, wy - 0.06 * k, wd * 0.55)
			dir = Vector3(0.2, -0.55, -1.0)
			saya_c = "urushi"; tsuka_c = "shiro"
		"chokuto", "kanto_tachi":
			blade = 0.7; hilt = 0.2; sori = 0.0; edge_up = false
			koi = Vector3(0.17 * k, wy - 0.06 * k, wd * 0.5)
			dir = Vector3(0.2, -0.45, -1.0)
			saya_c = "urushi" if id == "chokuto" else "kogecha"; tsuka_c = "kogecha"
		"gunto":
			blade = 0.68; hilt = 0.24; sori = 0.016; edge_up = false
			koi = Vector3(0.175 * k, wy - 0.1 * k, 0.04 * k)
			dir = Vector3(0.06, -1.0, -0.42)
			saya_c = "kaki_g"; tsuka_c = "cha"
		"tanken":
			blade = 0.3; hilt = 0.13; sori = 0.0; edge_up = false
			koi = Vector3(0.17 * k, wy - 0.12 * k, 0.05 * k)
			dir = Vector3(0.05, -1.0, -0.2)
			saya_c = "urushi"; tsuka_c = "shiro"
	if col != "":
		saya_c = col
	blade *= k; hilt *= k; sori *= k
	var d := dir.normalized()
	var start := koi - d * hilt    # 柄頭
	# 局所座標：-Z が切先、+Y が刃の向き（反りは +Y と逆へふくらむ）
	var total := hilt + blade
	var cpt := func(t: float) -> Vector3:
		return Vector3(0, -sori * sin(PI * t), -total * t)
	var n := Node3D.new()
	n.name = NODE_PREFIX + "Sword_" + id
	# 柄
	var tp := PackedVector3Array()
	var tr := PackedFloat32Array()
	for i in 5:
		var t := float(i) / 4.0 * hilt / total
		tp.append(cpt.call(t))
		tr.append(1.0 - 0.08 * sin(PI * float(i) / 4.0))
	var tsuka := _mi(_tube(tp, tr, 0.0125 * k, 0.016 * k, 10, Vector3.UP), _mat(ctx, tsuka_c, true, "kasuri" if tsuka_c in ["kuro", "cha", "shiro"] else "", "shiro" if tsuka_c != "shiro" else "kuro", Vector2(1, 4)), "Tsuka")
	n.add_child(tsuka)
	if id == "kanto_tachi":
		var ring := _mi(_tube(_ring_path(0.028 * k, 14, Vector3(0, -0.0, 0.026 * k)), PackedFloat32Array([1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]), 0.005 * k, 0.005 * k, 6, Vector3.RIGHT, false), _mat(ctx, "kin"), "Ring")
		n.add_child(ring)
	else:
		var kash := _mi(_sphere(0.016 * k, 8), _mat(ctx, fit_c), "Kashira")
		kash.scale = Vector3(0.85, 1.0, 0.6)
		n.add_child(kash)
	# 鍔
	var tsuba_p: Vector3 = cpt.call(hilt / total)
	var tsuba := _mi(_lathe([Vector2(0, -0.003 * k), Vector2(0.04 * k, -0.003 * k), Vector2(0.04 * k, 0.003 * k), Vector2(0, 0.003 * k)], 18, 0.9, 1.0), _mat(ctx, "tetsu" if id != "tanken" else "kin"), "Tsuba")
	tsuba.transform = Transform3D(Basis(Vector3.RIGHT, PI / 2), tsuba_p)
	if id in ["katana", "wakizashi", "tachi", "gunto"]:
		n.add_child(tsuba)
	# 鞘
	var sp := PackedVector3Array()
	var sr := PackedFloat32Array()
	for i in 9:
		var t := lerpf(hilt / total + 0.006, 1.0, float(i) / 8.0)
		sp.append(cpt.call(t))
		sr.append(lerpf(1.0, 0.78, float(i) / 8.0))
	n.add_child(_mi(_tube(sp, sr, 0.0115 * k, 0.019 * k, 10, Vector3.UP), _mat(ctx, saya_c), "Saya"))
	var kojiri := _mi(_sphere(0.012 * k, 8), _mat(ctx, fit_c if id != "gunto" else "kin"), "Kojiri")
	kojiri.position = cpt.call(1.0)
	kojiri.scale = Vector3(0.75, 1.15, 1.2)
	n.add_child(kojiri)
	if id in ["katana", "wakizashi"]:
		# 下緒（鞘の栗形から垂れる紐）
		var a: Vector3 = cpt.call(hilt / total + 0.08)
		var cord := _mi(_tube(PackedVector3Array([a, a + Vector3(0, -0.04, 0.02) * k, a + Vector3(0, -0.1, 0.05) * k, a + Vector3(0, -0.15, 0.04) * k]), PackedFloat32Array([1, 1, 1, 1]), 0.004 * k, 0.004 * k, 5), _mat(ctx, "murasaki" if id == "katana" else "enji", false), "Sageo")
		n.add_child(cord)
	if id in ["tachi", "gunto", "chokuto", "kanto_tachi", "tanken"]:
		# 帯取（吊り紐）
		for tt: float in [0.33, 0.45]:
			var a: Vector3 = cpt.call(tt * (hilt + 0.3 * k) / total)
			var hang := _mi(_tube(PackedVector3Array([a, a + Vector3(0, -0.08, 0) * k]), PackedFloat32Array([1, 1]), 0.004 * k, 0.004 * k, 5), _mat(ctx, "kin" if id != "gunto" else "cha", false), "Hanger")
			n.add_child(hang)
	# 置く：局所 -Z を d へ、局所 +Y を刃の向き（帯に差すなら上、太刀なら下）へ
	var up_w := Vector3.UP if edge_up else Vector3.DOWN
	var zax := -d
	var xax := up_w.cross(zax).normalized()
	var yax := zax.cross(xax).normalized()
	_put(ctx, bone, n, Transform3D(Basis(xax, yax, zax), start))


static func _ring_path(r: float, n: int, c := Vector3.ZERO) -> PackedVector3Array:
	var p := PackedVector3Array()
	for i in n + 1:
		var a := TAU * i / n
		p.append(c + Vector3(0, sin(a) * r, cos(a) * r))
	return p


## 袈裟：左肩から右脇へ斜めに掛ける帯（福田衣の格子柄）
static func _kesa(ctx: Dictionary, c1: String, c2: String) -> void:
	var L: Dictionary = ctx["L"]
	var k: float = L["k"]
	var chest: Vector3 = L["chest"]
	var cen := Vector3(0, chest.y - 0.1 * k, 0.0)
	var D := Vector3(0.5, 0.86, 0).normalized()
	var R1 := 0.36 * k
	var R2: float = L["waist_hd"] + 0.025 * k
	var path := PackedVector3Array()
	var nrm := PackedVector3Array()
	for i in 33:
		var a := TAU * i / 32.0
		var w := 1.0 + 0.18 * cos(a) * cos(a)
		var p := cen + D * cos(a) * R1 + Vector3(0, 0, 1) * sin(a) * R2 * w
		# 肩の上では胴の芯から外へ
		path.append(p)
		var nn := (p - cen)
		nn = nn - D.cross(Vector3(0, 0, 1)).normalized() * nn.dot(D.cross(Vector3(0, 0, 1)).normalized())
		nrm.append(nn.normalized())
	var m := _mi(_ribbon(path, nrm, 0.12 * k, 0.006 * k, 2), _mat(ctx, c1, true, "ichimatsu", c2, Vector2(1, 10)), "Kesa")
	_put(ctx, "UpperChest", m, Transform3D.IDENTITY)
	# 袈裟の環
	var ring := _mi(TorusMesh.new(), _mat(ctx, "kin"), "KesaRing")
	(ring.mesh as TorusMesh).inner_radius = 0.016 * k
	(ring.mesh as TorusMesh).outer_radius = 0.024 * k
	var rp := cen + D * cos(0.75) * R1 + Vector3(0, 0, 1) * sin(0.75) * R2 * 1.12
	_put(ctx, "UpperChest", ring, Transform3D(Basis(Vector3.RIGHT, PI / 2), rp + Vector3(0, 0, 0.008 * k)))


## 裃の肩衣：張った両肩の羽と、胸へ V 字に下りる前身頃、背
static func _kataginu(ctx: Dictionary, col: String) -> void:
	var L: Dictionary = ctx["L"]
	var k: float = L["k"]
	var sh: Vector3 = L["shoulder_l"]
	var wy: float = L["waist_y"]
	var wd: float = L["waist_hd"]
	var sy := sh.y + 0.05 * k
	var mat := _mat(ctx, col)
	for sx: float in [1.0, -1.0]:
		# 羽（肩から外へ張り出す板）
		var wing := func(u: float, v: float) -> Vector3:
			var x := lerpf(0.06, 0.36, u) * k
			var z := lerpf(-0.12, 0.12, v) * k * (1.0 - 0.15 * u)
			return Vector3(sx * x, sy + 0.03 * k * u - 0.02 * k * (1.0 - u) * (1.0 - u) + 0.01 * k * absf(v - 0.5), z)
		_put(ctx, "UpperChest", _mi(_surf(wing, 6, 4, false, 0.008 * k), mat, "Wing"), Transform3D.IDENTITY)
		# 前身頃：肩の前縁から帯の中央へ細くなる
		var front := func(u: float, v: float) -> Vector3:
			var top_in := Vector3(sx * 0.065 * k, sy - 0.01 * k, 0.1 * k)
			var top_out := Vector3(sx * 0.26 * k, sy + 0.01 * k, 0.11 * k)
			var bot_in := Vector3(sx * 0.012 * k, wy, wd + 0.012 * k)
			var bot_out := Vector3(sx * 0.07 * k, wy, wd + 0.012 * k)
			var top := top_in.lerp(top_out, u)
			var bot := bot_in.lerp(bot_out, u)
			var p := top.lerp(bot, v)
			p.z += 0.04 * k * sin(PI * v) * (1.0 - 0.3 * u)
			return p
		_put(ctx, "UpperChest", _mi(_surf(front, 3, 8, false, 0.007 * k), mat, "Front"), Transform3D.IDENTITY)
	# 背
	var back := func(u: float, v: float) -> Vector3:
		var xw := lerpf(0.27, 0.15, v) * k
		var x := lerpf(-xw, xw, u)
		var y := lerpf(sy - 0.005 * k, wy, v)
		var z := -(lerpf(0.115 * k, wd + 0.015 * k, v) + 0.03 * k * sin(PI * v)) - 0.012 * k * (1.0 - pow(2.0 * u - 1.0, 2.0))
		return Vector3(x, y, z)
	_put(ctx, "UpperChest", _mi(_surf(back, 6, 8, false, 0.007 * k), mat, "Back"), Transform3D.IDENTITY)


## 南蛮の外套（天鵞絨のマント）：肩から膝下まで、前は開く。裾に金の縁
static func _cape(ctx: Dictionary, c1: String, c2: String) -> void:
	var L: Dictionary = ctx["L"]
	var k: float = L["k"]
	var neck: Vector3 = L["neck"]
	var sh: Vector3 = L["shoulder_l"]
	var top := neck.y - 0.01 * k
	var bot := 0.42 * k
	var fn := func(u: float, v: float) -> Vector3:
		var a := lerpf(-2.0, 2.0, u)     # 0 が背中
		var y := lerpf(top, bot, v)
		var shoulder := clampf(v * 4.0, 0.0, 1.0)
		var r := lerpf(0.09 * k, 0.32 * k, shoulder) + 0.1 * k * v
		var rx := r * lerpf(0.8, 1.0, shoulder) * (sh.x / 0.147 if v > 0.1 else 1.0)
		var rz := r * 0.72
		var p := Vector3(sin(a) * rx, y - 0.04 * k * absf(sin(a)) * shoulder, -cos(a) * rz - 0.02 * k)
		# ひだ
		p += Vector3(sin(a), 0, -cos(a)) * 0.012 * k * sin(a * 9.0) * v
		return p
	var m := _mi(_surf(fn, 36, 14, false, 0.012 * k), _mat(ctx, c1), "Cape")
	_put(ctx, "UpperChest", m, Transform3D.IDENTITY)
	# 裾と前端の金の縁
	var hem := func(u: float, v: float) -> Vector3:
		var p: Vector3 = fn.call(u, 1.0 - v * 0.04)
		var o := Vector3(p.x, 0, p.z + 0.02 * k).normalized()
		return p + o * 0.008 * k
	_put(ctx, "UpperChest", _mi(_surf(hem, 36, 1, false, 0.016 * k), _mat(ctx, c2), "CapeHem"), Transform3D.IDENTITY)
	# 立ち襟
	var collar := func(u: float, v: float) -> Vector3:
		var a := lerpf(-2.2, 2.2, u)
		var r := lerpf(0.085, 0.1, v) * k
		return Vector3(sin(a) * r, top + v * 0.06 * k, -cos(a) * r * 0.85)
	_put(ctx, "UpperChest", _mi(_surf(collar, 16, 2, false, 0.01 * k), _mat(ctx, c2), "CapeCollar"), Transform3D.IDENTITY)


## 領巾（ひれ）：肩に掛けて前へ垂らす薄布
static func _hire(ctx: Dictionary, col: String) -> void:
	var L: Dictionary = ctx["L"]
	var k: float = L["k"]
	var neck: Vector3 = L["neck"]
	var sh: Vector3 = L["shoulder_l"]
	var wy: float = L["waist_y"]
	var wd: float = L["waist_hd"]
	var path := PackedVector3Array()
	var nrm := PackedVector3Array()
	var pts := [Vector3(0.16, wy - 0.3 * k, wd + 0.06 * k), Vector3(0.15, wy - 0.05 * k, wd + 0.05 * k), Vector3(0.14, sh.y - 0.06 * k, 0.11 * k),
		Vector3(sh.x * 0.95, sh.y + 0.035 * k, 0.0), Vector3(0.09, neck.y - 0.02 * k, -0.1 * k), Vector3(0.0, neck.y - 0.05 * k, -0.125 * k)]
	for i in pts.size():
		path.append(pts[i])
	for i in range(pts.size() - 2, -1, -1):
		var p: Vector3 = pts[i]
		path.append(Vector3(-p.x, p.y, p.z))
	for p in path:
		var o := Vector3(p.x, 0, p.z)
		if p.y > sh.y - 0.02 * k:
			o += Vector3(0, 1.2, 0) * 0.1
		nrm.append(o.normalized())
	var m := _mi(_ribbon(path, nrm, 0.07 * k, 0.004 * k, 2), _mat(ctx, col), "Hire")
	_put(ctx, "UpperChest", m, Transform3D.IDENTITY)


## 重ねの衿（十二単ふう）：衿元に色の層を V 字に重ねる
static func _kasane(ctx: Dictionary, cols: Array) -> void:
	var L: Dictionary = ctx["L"]
	var k: float = L["k"]
	var neck: Vector3 = L["neck"]
	var chest: Vector3 = L["chest"]
	var wd: float = L["waist_hd"]
	var n := cols.size()
	for i in n:
		var off := 0.011 * (i + 1) * k
		for sx: float in [1.0, -1.0]:
			var pts := [Vector3(0, neck.y - 0.005 * k, -0.075 * k - off * 0.6), Vector3(sx * (0.07 * k + off), neck.y - 0.02 * k, -0.01 * k),
				Vector3(sx * (0.06 * k + off * 0.8), neck.y - 0.075 * k - off * 0.8, 0.085 * k + off * 0.3), Vector3(-sx * 0.012 * k, chest.y - 0.08 * k - off * 2.2, wd + 0.008 * k + off * 0.25)]
			var path := PackedVector3Array()
			var nrm := PackedVector3Array()
			for p: Vector3 in pts:
				path.append(p)
				nrm.append((Vector3(p.x, (p.y - neck.y) * 0.0 + 0.35, p.z)).normalized())
			var m := _mi(_ribbon(path, nrm, 0.016 * k, 0.004 * k, 1), _mat(ctx, cols[n - 1 - i]), "Kasane")
			_put(ctx, "UpperChest", m, Transform3D.IDENTITY)


## 裳・裾（きょ）：腰から後ろへ長く引く
static func _train(ctx: Dictionary, id: String, col: String) -> void:
	var L: Dictionary = ctx["L"]
	var k: float = L["k"]
	var wy: float = L["waist_y"]
	var wd: float = L["waist_hd"]
	var length := 0.95 if id == "mo" else 1.1
	var w0 := 0.3 if id == "mo" else 0.2
	var w1 := 0.46 if id == "mo" else 0.22
	var pts := [Vector3(0, wy, -wd - 0.03 * k), Vector3(0, wy - 0.35 * k, -wd - 0.09 * k), Vector3(0, wy * 0.35, -0.24 * k),
		Vector3(0, 0.05 * k, -0.42 * k), Vector3(0, 0.015 * k, -length * 0.62 * k), Vector3(0, 0.012 * k, -length * k)]
	var nrm := PackedVector3Array([Vector3(0, 0.1, -1), Vector3(0, 0.1, -1), Vector3(0, 0.3, -1), Vector3(0, 1, -0.6), Vector3(0, 1, 0), Vector3(0, 1, 0)])
	var path := PackedVector3Array()
	for p: Vector3 in pts:
		path.append(p)
	var m := _mi(_ribbon(path, nrm, Vector2(w0 * k, w1 * k), 0.006 * k, 4), _mat(ctx, col, true, "asanoha" if id == "mo" else "", "kinari", Vector2(2, 6)), "Train")
	_put(ctx, "Hips", m, Transform3D.IDENTITY)


## かぶりもの（Head の骨に付ける）
static func _headwear(ctx: Dictionary, id: String, col: String) -> void:
	var L: Dictionary = ctx["L"]
	var k: float = L["k"]
	var hc: Vector3 = L["head_c"]
	var top: float = L["top"]
	var fz: float = L["face_z"]
	var n := Node3D.new()
	n.name = NODE_PREFIX + id
	var base := Vector3(0, top, hc.z)    # 頭頂の高さ・頭の中心
	match id:
		"hachimaki":
			var band := _lathe([Vector2(0.106, -0.016), Vector2(0.114, -0.014), Vector2(0.115, 0.014), Vector2(0.107, 0.016)], 28, 1.0, 1.15)
			var m := _mi(band, _mat(ctx, col if col != "" else "shiro"), "Band")
			m.position = Vector3(0, -0.085, 0.0)
			n.add_child(m)
			var knot := _mi(_sphere(0.018, 8), _mat(ctx, col if col != "" else "shiro"), "Knot")
			knot.position = Vector3(0, -0.085, -0.128)
			n.add_child(knot)
			for sx: float in [1.0, -1.0]:
				n.add_child(_mi(_tube(PackedVector3Array([Vector3(0, -0.085, -0.13), Vector3(sx * 0.03, -0.13, -0.15), Vector3(sx * 0.05, -0.2, -0.15)]), PackedFloat32Array([1, 1, 0.8]), 0.012, 0.003, 6, Vector3.BACK), _mat(ctx, col if col != "" else "shiro"), "Tail"))
		"kofun_crown", "kofun_crown_band", "hokan", "hokan_m":
			var gold := _mat(ctx, "kin")
			var band := _lathe([Vector2(0.108, -0.02), Vector2(0.116, -0.02), Vector2(0.117, 0.02), Vector2(0.109, 0.02)], 28, 1.0, 1.15)
			var m := _mi(band, gold, "Band")
			m.position = Vector3(0, -0.07, 0)
			n.add_child(m)
			var spikes: Array = []
			if id == "kofun_crown":
				spikes = [0.0, 0.7, -0.7, 1.5, -1.5]
			elif id == "hokan" or id == "kofun_crown_band":
				spikes = [0.0]
			else:
				spikes = [0.55, -0.55]
			for a: float in spikes:
				var sp := Node3D.new()
				var trunk := _mi(_box(Vector3(0.014, 0.12, 0.003)), gold, "Trunk")
				trunk.position = Vector3(0, 0.06, 0)
				sp.add_child(trunk)
				for lv in 3:
					for sx: float in [1.0, -1.0]:
						var br := _mi(_box(Vector3(0.012, 0.045, 0.003)), gold, "Branch")
						br.position = Vector3(sx * 0.02, 0.035 + lv * 0.032, 0)
						br.rotation = Vector3(0, 0, -sx * 0.5)
						sp.add_child(br)
				if id == "hokan" or id == "kofun_crown_band":
					sp.scale = Vector3(1.2, 0.6, 1.0)
				var r := 0.118
				sp.position = Vector3(sin(a) * r, -0.06, cos(a) * r * 1.15)
				sp.rotation = Vector3(-0.15, a, 0)
				n.add_child(sp)
		"boku":
			var cap := _lathe([Vector2(0.112, -0.075), Vector2(0.118, -0.03), Vector2(0.11, 0.015), Vector2(0.075, 0.045), Vector2(0, 0.055)], 24, 1.0, 1.17)
			n.add_child(_mi(cap, _mat(ctx, "urushi"), "Cap"))
			var bun := _mi(_sphere(0.05, 12), _mat(ctx, "urushi"), "Bun")
			bun.position = Vector3(0, 0.055, -0.05)
			bun.scale = Vector3(0.9, 1.0, 1.1)
			n.add_child(bun)
			for sx: float in [1.0, -1.0]:
				n.add_child(_mi(_tube(PackedVector3Array([Vector3(sx * 0.03, 0.0, -0.12), Vector3(sx * 0.045, -0.08, -0.14), Vector3(sx * 0.05, -0.18, -0.13)]), PackedFloat32Array([1, 1, 0.9]), 0.02, 0.003, 6, Vector3.BACK), _mat(ctx, "urushi"), "Tail"))
		"kanmuri", "kanmuri_ryuei":
			var black := _mat(ctx, "urushi")
			var cap := _lathe([Vector2(0.098, -0.035), Vector2(0.104, 0.0), Vector2(0.098, 0.03), Vector2(0.06, 0.045), Vector2(0, 0.048)], 24, 1.0, 1.18)
			n.add_child(_mi(cap, black, "Cap"))
			var koji := _mi(_lathe([Vector2(0, 0), Vector2(0.038, 0.0), Vector2(0.036, 0.08), Vector2(0.025, 0.095), Vector2(0, 0.098)], 16, 0.9, 1.0), black, "Koji")
			koji.position = Vector3(0, 0.03, -0.055)
			n.add_child(koji)
			var pin := _mi(_cyl(0.004, 0.13, 6), _mat(ctx, "kin"), "Pin")
			pin.position = Vector3(0, 0.07, -0.055)
			pin.rotation = Vector3(0, 0, PI / 2)
			n.add_child(pin)
			var ei: PackedVector3Array
			if id == "kanmuri_ryuei":
				ei = PackedVector3Array([Vector3(0, 0.1, -0.085), Vector3(0, 0.15, -0.1), Vector3(0, 0.2, -0.13), Vector3(0, 0.23, -0.17)])
			else:
				ei = PackedVector3Array([Vector3(0, 0.08, -0.09), Vector3(0, 0.02, -0.14), Vector3(0, -0.1, -0.16), Vector3(0, -0.24, -0.17)])
			var enrm := PackedVector3Array([Vector3(0, 0, -1), Vector3(0, 0.2, -1), Vector3(0, 0.3, -1), Vector3(0, 0.4, -1)])
			n.add_child(_mi(_ribbon(ei, enrm, 0.034, 0.003, 1), black, "Ei"))
			n.position.y = -0.03
		"eboshi":
			var prof := [Vector2(0, -0.06), Vector2(0.104, -0.06), Vector2(0.108, 0.02), Vector2(0.1, 0.11), Vector2(0.085, 0.18), Vector2(0.06, 0.22), Vector2(0.02, 0.235), Vector2(0, 0.236)]
			var m := _mi(_lathe(prof, 24, 0.95, 1.2), _mat(ctx, "urushi"), "Eboshi")
			m.rotation = Vector3(-0.18, 0, 0)
			n.add_child(m)
			var crease := _mi(_box(Vector3(0.006, 0.12, 0.05)), _mat(ctx, "urushi"), "Maneki")
			crease.position = Vector3(0, 0.1, 0.1)
			crease.rotation = Vector3(-0.35, 0, 0)
			n.add_child(crease)
			n.position.y = -0.035
		"ori_eboshi":
			var prof := [Vector2(0, -0.055), Vector2(0.104, -0.055), Vector2(0.108, 0.0), Vector2(0.095, 0.05), Vector2(0.05, 0.07), Vector2(0, 0.072)]
			n.add_child(_mi(_lathe(prof, 24, 0.95, 1.2), _mat(ctx, "urushi"), "Cap"))
			var fold := _mi(_extrude(PackedVector2Array([Vector2(-0.07, 0), Vector2(0.07, 0), Vector2(0.05, 0.05), Vector2(-0.08, 0.08)]), 0.018), _mat(ctx, "urushi"), "Fold")
			fold.position = Vector3(0, 0.055, -0.02)
			fold.rotation = Vector3(-1.1, 0.2, 0)
			n.add_child(fold)
			n.position.y = -0.03
		"zukin":
			var prof := [Vector2(0.17, -0.33), Vector2(0.14, -0.22), Vector2(0.125, -0.12), Vector2(0.128, -0.03), Vector2(0.12, 0.03), Vector2(0.085, 0.07), Vector2(0.0, 0.085)]
			var m := _mi(_lathe(prof, 20, 1.0, 1.15, 0.9, TAU - 0.9, 0.01), _mat(ctx, col if col != "" else "shiro"), "Hood")
			m.position = Vector3(0, -0.04, -0.005)
			n.add_child(m)
			# 顔の下を覆う布
			var chin := _mi(_lathe([Vector2(0.135, -0.26), Vector2(0.12, -0.17), Vector2(0.11, -0.12)], 14, 1.0, 1.15, -0.95, 0.95, 0.01), _mat(ctx, col if col != "" else "shiro"), "Chin")
			chin.position = Vector3(0, -0.04, -0.0)
			n.add_child(chin)
		"fur_hat":
			var prof := [Vector2(0, -0.065), Vector2(0.125, -0.065), Vector2(0.135, -0.02), Vector2(0.13, 0.06), Vector2(0.11, 0.1), Vector2(0, 0.105)]
			n.add_child(_mi(_lathe(prof, 24, 1.0, 1.12), _mat(ctx, "kogecha", true, "kasuri", "cha", Vector2(3, 2)), "Fur"))
		"top_hat":
			var prof := [Vector2(0, -0.04), Vector2(0.16, -0.045), Vector2(0.165, -0.035), Vector2(0.1, -0.03), Vector2(0.097, 0.1), Vector2(0.1, 0.14), Vector2(0, 0.142)]
			n.add_child(_mi(_lathe(prof, 24, 1.0, 1.15), _mat(ctx, "kuro"), "Hat"))
			var band := _mi(_lathe([Vector2(0.099, -0.028), Vector2(0.101, -0.028), Vector2(0.1, 0.0), Vector2(0.098, 0.0)], 24, 1.0, 1.15), _mat(ctx, "sumi"), "Band")
			n.add_child(band)
			n.position.y = 0.0
	_put(ctx, "Head", n, Transform3D(Basis().scaled(Vector3.ONE * k), base + n.position * k))
	n.position = n.position   # (位置は _put で確定)


## 兜の差し替え・飾り
static func _helmet(ctx: Dictionary, id: String) -> void:
	var L: Dictionary = ctx["L"]
	var k: float = L["k"]
	var hc: Vector3 = L["head_c"]
	var top: float = L["top"]
	var fz: float = L["face_z"]
	var n := Node3D.new()
	n.name = NODE_PREFIX + id
	var base := Vector3(0, top, hc.z)
	match id:
		"shokaku_kabuto":
			var iron := _mat(ctx, "tetsu", true, "ita", "kin", Vector2(6, 2))
			var fn := func(u: float, v: float) -> Vector3:
				var a := u * TAU
				var r := 0.128 * cos(v * PI * 0.5)
				var y := -0.06 + 0.13 * sin(v * PI * 0.5)
				var fwd := maxf(0.0, cos(a))
				var z := cos(a) * r * 1.12 + 0.07 * pow(fwd, 6.0) * (1.0 - v) * (0.4 + v)
				return Vector3(sin(a) * r, y + 0.03 * pow(fwd, 6.0) * v, z)
			n.add_child(_mi(_surf(fn, 32, 8, true, 0.0, func(u: float, v: float) -> Vector3: return (fn.call(u, v) as Vector3) - Vector3(0, -0.06, 0)), iron, "Bowl"))
			var brim := _mi(_lathe([Vector2(0.125, -0.062), Vector2(0.16, -0.07), Vector2(0.16, -0.062), Vector2(0.125, -0.054)], 28, 1.0, 1.12, -1.4, 1.4), _mat(ctx, "kin"), "Brim")
			n.add_child(brim)
			var neckg := _mi(_lathe([Vector2(0.13, -0.06), Vector2(0.15, -0.12), Vector2(0.17, -0.19)], 20, 1.0, 1.1, 1.3, TAU - 1.3, 0.008), _mat(ctx, "tetsu", true, "ita", "kin", Vector2(6, 2)), "NeckGuard")
			n.add_child(neckg)
			n.position.y = -0.02
		"nanban_kabuto":
			var black := _mat(ctx, "urushi")
			n.add_child(_mi(_lathe([Vector2(0.122, -0.055), Vector2(0.126, 0.0), Vector2(0.11, 0.06), Vector2(0.07, 0.1), Vector2(0, 0.112)], 24, 1.0, 1.18), black, "Bowl"))
			var comb := PackedVector2Array()
			for i in 13:
				var a := PI * i / 12.0
				comb.append(Vector2(cos(a) * 0.12, 0.07 + sin(a) * 0.08))
			var cm := _mi(_extrude(comb, 0.01), _mat(ctx, "kin"), "Comb")
			cm.rotation = Vector3(0, PI / 2, 0)
			n.add_child(cm)
			var brim := func(u: float, v: float) -> Vector3:
				var a := u * TAU
				var r := lerpf(0.12, 0.2, v)
				var lift := 0.06 * v * v * pow(absf(cos(a)), 2.0)
				return Vector3(sin(a) * r, -0.05 + lift - 0.01 * v, cos(a) * r * 1.2)
			n.add_child(_mi(_surf(brim, 32, 3, true, 0.008), _mat(ctx, "kin"), "Brim"))
		"nagaeboshi":
			var silver := _mat(ctx, "gin")
			var prof := [Vector2(0, -0.06), Vector2(0.125, -0.06), Vector2(0.125, 0.0), Vector2(0.11, 0.1), Vector2(0.09, 0.22), Vector2(0.065, 0.33), Vector2(0.035, 0.4), Vector2(0, 0.41)]
			var m := _mi(_lathe(prof, 24, 0.82, 1.25), silver, "Tall")
			m.rotation = Vector3(-0.2, 0, 0)
			n.add_child(m)
			for sx: float in [1.0, -1.0]:
				var disc := _mi(_cyl(0.045, 0.006, 20), _mat(ctx, "shu", false), "Sun")
				disc.position = Vector3(sx * 0.098, 0.13, -0.02)
				disc.rotation = Vector3(0, 0, PI / 2 + sx * 0.12)
				n.add_child(disc)
			var visor := _mi(_lathe([Vector2(0.12, -0.06), Vector2(0.16, -0.075), Vector2(0.16, -0.065), Vector2(0.12, -0.05)], 20, 1.0, 1.2, -1.2, 1.2), _mat(ctx, "urushi"), "Visor")
			n.add_child(visor)
			n.position.y = -0.02
		"ichinotani":
			var plate := _mi(_extrude(PackedVector2Array([Vector2(0.06, 0.0), Vector2(-0.12, 0.0), Vector2(-0.2, 0.3), Vector2(-0.02, 0.32)]), 0.012), _mat(ctx, "gin"), "Cliff")
			plate.rotation = Vector3(0, PI / 2, 0)
			plate.position = Vector3(0, 0.0, 0.0)
			n.add_child(plate)
		"bariki":
			var gold := _mat(ctx, "kin")
			var spike := _cyl(0.007, 0.36, 6, 0.0015)
			var items: Array = []
			var cnt := 29
			for i in cnt:
				var a := lerpf(-1.75, 1.75, float(i) / (cnt - 1))
				var dirv := Vector3(sin(a), cos(a), 0)
				var xf := Transform3D(Basis(Vector3(0, 0, 1), -a), dirv * 0.2)
				items.append([spike, xf])
			var halo := _mi(_merge(items), gold, "Halo")
			halo.position = Vector3(0, -0.08, -0.16)
			n.add_child(halo)
			var hub := _mi(_cyl(0.05, 0.02, 16), gold, "Hub")
			hub.rotation = Vector3(PI / 2, 0, 0)
			hub.position = Vector3(0, -0.08, -0.15)
			n.add_child(hub)
		"shida_maedate":
			var poly := PackedVector2Array()
			var cnt := 15
			for i in cnt:
				var a := lerpf(0.25, PI - 0.25, float(i) / (cnt - 1))
				var rr := 0.1 if i % 2 == 0 else 0.078
				poly.append(Vector2(cos(a) * rr, sin(a) * rr))
			poly.append(Vector2(-0.012, -0.01))
			poly.append(Vector2(0.012, -0.01))
			var m := _mi(_extrude(poly, 0.006), _mat(ctx, "kin"), "Fern")
			m.position = Vector3(0, -0.04, fz - hc.z + 0.03)
			m.rotation = Vector3(-0.25, 0, 0)
			n.add_child(m)
	_put(ctx, "Head", n, Transform3D(Basis().scaled(Vector3.ONE * k), base + n.position * k))


## 丸眼鏡
static func _glasses(ctx: Dictionary, col: String) -> void:
	var L: Dictionary = ctx["L"]
	var k: float = L["k"]
	var eye: Vector3 = L["eye"]
	var fw: float = L["face_w"]
	var n := Node3D.new()
	n.name = NODE_PREFIX + "Glasses"
	var m := _mat(ctx, col, false)
	for sx: float in [1.0, -1.0]:
		var t := TorusMesh.new()
		t.inner_radius = 0.026
		t.outer_radius = 0.0295
		t.rings = 20
		t.ring_segments = 6
		var rim := _mi(t, m, "Rim")
		rim.position = Vector3(sx * 0.045, 0, 0)
		rim.rotation = Vector3(PI / 2, 0, 0)
		n.add_child(rim)
		var temple := _mi(_tube(PackedVector3Array([Vector3(sx * 0.074, 0.004, -0.004), Vector3(sx * (fw / k + 0.004), 0.008, -0.04), Vector3(sx * (fw / k + 0.006), 0.0, -0.11)]), PackedFloat32Array([1, 1, 1]), 0.0022, 0.0022, 5, Vector3.UP, false), m, "Temple")
		n.add_child(temple)
	var bridge := _mi(_tube(PackedVector3Array([Vector3(-0.017, 0.006, 0.0), Vector3(0, 0.012, 0.004), Vector3(0.017, 0.006, 0.0)]), PackedFloat32Array([1, 1, 1]), 0.0022, 0.0022, 5, Vector3.UP, false), m, "Bridge")
	n.add_child(bridge)
	_put(ctx, "Head", n, Transform3D(Basis().scaled(Vector3.ONE * k), eye + Vector3(0, 0, 0.018 * k)))


# ===========================================================================
# 顔：AnimeFace が無いときの簡易な髭（顔メッシュの形を測って沿わせる）
# ===========================================================================

static func _face_profile(ctx: Dictionary) -> Dictionary:
	## 顔の中心軸（頭の中心を通る鉛直線）から見た、角度×高さごとの顔の表面までの距離
	var model: Node3D = ctx["model"]
	var L: Dictionary = ctx["L"]
	var face: MeshInstance3D = null
	for mi: MeshInstance3D in model.find_children("Face", "MeshInstance3D", true, false):
		face = mi
	var hc: Vector3 = L["head_c"]
	var NA := 36
	var NY := 20
	var y0: float = L["face_y0"] - 0.03 * float(L["k"])
	var y1: float = L["eye"].y
	var grid := PackedFloat32Array()
	grid.resize(NA * NY)
	grid.fill(0.0)
	if face and face.mesh:
		for si in face.mesh.get_surface_count():
			var arr := face.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for v in vs:
				if v.y < y0 or v.y > y1:
					continue
				var dx := v.x
				var dz := v.z - hc.z
				var a := atan2(dx, dz)
				var ia := clampi(int((a + PI) / TAU * NA), 0, NA - 1)
				var iy := clampi(int((v.y - y0) / (y1 - y0) * NY), 0, NY - 1)
				var r := sqrt(dx * dx + dz * dz)
				if r > grid[iy * NA + ia]:
					grid[iy * NA + ia] = r
	# 空きを近傍で埋める
	for _pass in 4:
		for iy in NY:
			for ia in NA:
				if grid[iy * NA + ia] > 0.0:
					continue
				var s := 0.0
				var c := 0
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var ja := (ia + d.x + NA) % NA
					var jy := iy + d.y
					if jy < 0 or jy >= NY:
						continue
					var g := grid[jy * NA + ja]
					if g > 0.0:
						s += g
						c += 1
				if c > 0:
					grid[iy * NA + ia] = s / c
	return {"grid": grid, "NA": NA, "NY": NY, "y0": y0, "y1": y1, "c": hc}


static func _face_r(fp: Dictionary, a: float, y: float) -> float:
	var NA: int = fp["NA"]
	var NY: int = fp["NY"]
	var fa := (a + PI) / TAU * NA - 0.5
	var fy := (y - float(fp["y0"])) / (float(fp["y1"]) - float(fp["y0"])) * NY - 0.5
	var ia := int(floor(fa))
	var iy := clampi(int(floor(fy)), 0, NY - 2)
	var ta := fa - ia
	var ty := clampf(fy - iy, 0.0, 1.0)
	var g: PackedFloat32Array = fp["grid"]
	var r00 := g[iy * NA + (ia + NA) % NA]
	var r10 := g[iy * NA + (ia + 1 + NA) % NA]
	var r01 := g[(iy + 1) * NA + (ia + NA) % NA]
	var r11 := g[(iy + 1) * NA + (ia + 1 + NA) % NA]
	return lerpf(lerpf(r00, r10, ta), lerpf(r01, r11, ta), ty)


static func _fallback_facial_hair(ctx: Dictionary, face: Dictionary) -> void:
	var beard: String = face.get("beard", "none")
	var must: String = face.get("mustache", "none")
	var side: bool = face.get("sideburns", false)
	if beard == "none" and must == "none" and not side:
		return
	var L: Dictionary = ctx["L"]
	var k: float = L["k"]
	var fp := _face_profile(ctx)
	var hc: Vector3 = fp["c"]
	var col: Color = BEARD_COL.get(face.get("hair_color", "black"), BEARD_COL["black"])
	var mat := AnimeChar._cloth_mat(ctx["tmpl"], col, col * Color(0.55, 0.52, 0.6), true, null)
	if mat is ShaderMaterial and mat.next_pass is ShaderMaterial:
		(mat.next_pass as ShaderMaterial).set_shader_parameter("_OutlineWidth", 0.1)
	var mouth: Vector3 = L["mouth"]
	var chin_y: float = L["face_y0"]
	var surf_pt := func(a: float, y: float, off: float) -> Vector3:
		var r := _face_r(fp, a, y) + off
		return Vector3(hc.x + sin(a) * r, y, hc.z + cos(a) * r)
	if beard != "none":
		var spread := 1.25 if beard in ["full", "long", "short"] else 0.42
		var drop: float = {"goatee": 0.025, "short": 0.02, "full": 0.035, "long": 0.09}.get(beard, 0.02) * k
		var thick: float = {"goatee": 0.008, "short": 0.006, "full": 0.012, "long": 0.012}.get(beard, 0.008) * k
		var fn := func(u: float, v: float) -> Vector3:
			var a := lerpf(-spread, spread, u)
			var side_t := absf(a) / maxf(spread, 0.01)
			# 上端：中央は口の下、横へ行くほど頬骨（もみあげ）へ上がる
			var top_y: float = mouth.y - 0.014 * k + (0.06 * k * side_t * side_t if spread > 1.0 else 0.0)
			var bot_y: float = chin_y + 0.004 * k
			var y := lerpf(top_y, bot_y, v)
			var p: Vector3 = surf_pt.call(a, maxf(y, float(fp["y0"]) + 0.002), thick * (0.4 + 0.6 * v))
			if v > 0.75:
				# 顎の下へ回り込み、長い髭は垂らす
				var t := (v - 0.75) / 0.25
				p.y -= drop * t * (1.0 - side_t * 0.7)
				p.z += 0.006 * k * t
			return p
		var m := _mi(_surf(fn, 14, 8, false, 0.008 * k), mat, "Beard")
		_put(ctx, "Head", m, Transform3D.IDENTITY)
	if side and beard == "none":
		for sx: float in [1.0, -1.0]:
			var fn2 := func(u: float, v: float) -> Vector3:
				var a := sx * lerpf(1.05, 1.35, u)
				var y := lerpf(L["eye"].y, mouth.y - 0.01 * k, v)
				return surf_pt.call(a, y, 0.004 * k)
			_put(ctx, "Head", _mi(_surf(fn2, 2, 5, false, 0.006 * k), mat, "Sideburn"), Transform3D.IDENTITY)
	if must != "none":
		var my := mouth.y + 0.014 * k
		var w := {"thin": 0.32, "toothbrush": 0.12, "full": 0.42, "kaiser": 0.5, "walrus": 0.5, "handlebar": 0.62}.get(must, 0.35) as float
		var th := {"thin": 0.0035, "toothbrush": 0.007, "full": 0.0065, "kaiser": 0.005, "walrus": 0.008, "handlebar": 0.005}.get(must, 0.005) as float
		if must == "toothbrush":
			var fn3 := func(u: float, v: float) -> Vector3:
				var a := lerpf(-w, w, u)
				var y := lerpf(my + 0.011 * k, my + 0.003 * k, v)
				return surf_pt.call(a, y, 0.003 * k)
			_put(ctx, "Head", _mi(_surf(fn3, 4, 2, false, 0.004 * k), mat, "Mustache"), Transform3D.IDENTITY)
		else:
			for sx: float in [1.0, -1.0]:
				var pts := PackedVector3Array()
				var rr := PackedFloat32Array()
				for i in 7:
					var t := float(i) / 6.0
					var a := sx * lerpf(0.03, w, t)
					var y := my - 0.004 * k * t
					match must:
						"kaiser", "handlebar":
							y += (0.03 if must == "handlebar" else 0.02) * k * pow(t, 3.0) - 0.006 * k * sin(PI * t)
						"walrus":
							y -= 0.022 * k * t * t
						"full":
							y -= 0.01 * k * t * t
						_:
							y -= 0.006 * k * t
					pts.append(surf_pt.call(a, y, 0.0045 * k))
					rr.append(lerpf(1.0, 0.35, t) if must != "walrus" else lerpf(1.0, 0.7, t))
				_put(ctx, "Head", _mi(_tube(pts, rr, th * k * 1.5, th * k, 6, Vector3.UP), mat, "Mustache"), Transform3D.IDENTITY)
