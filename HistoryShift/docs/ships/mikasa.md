# 戦艦三笠 / IJN Battleship Mikasa

- Era: meiji / Year: 1905
- Type: pre-dreadnought battleship (Vickers, Barrow; commissioned 1 Mar 1902)
- Spec: `data/ships/mikasa.json`

## Dimensions

- length_overall_m: 131.7
- length_pp_m: 122.0
- beam_m: 23.2
- draft_m: 8.3
- displacement_t: 15140
- freeboard_m: {'bow': 7.0, 'mid': 5.5, 'stern': 5.0, 'confidence': 'typical (estimated from period photos; not sourced)'}
- upper_deck_above_waterline_m: 5.5
- mast_height_above_wl_m: {'value': 45, 'confidence': 'reconstruction'}
- funnels: 2
- masts: 2

## Crew

- 860 Plus Togo's fleet staff in 1905.

## Layout (deck by deck)

### 最上艦橋 / Compass deck (open top bridge) (level 16.0 m)

- **Open compass platform**: Togo's command post at Tsushima; bow-mid, centre (forward superstructure top); ~[8, 4] m [sourced]

### 前部艦橋 / Fore bridge, chart room, conning tower (level 11.0 m)

- **海図室 Chart room**: navigation plotting; bow-mid, centre; ~[4, 3] m [sourced]
- **司令塔 Conning tower**: armoured steering and command position; bow-mid, centre, below the bridge; ~[4, 3.5] m [sourced (existence); typical (armour)]

### 上甲板 Upper deck (level 5.5 m)

- **前部主砲塔 Fore 12-inch twin turret**: main battery; bow, centre; ~[11, 11] m [sourced]
- **8 cm gun battery**: anti-torpedo-boat guns; mid, port and starboard; ~[60, 3] m [sourced]
- **Upper-deck 6-inch casemates**: secondary battery; 4 corners of the battery (fore/aft, port/starboard); ~[4, 4] m [typical]
- **Funnels and boat stowage**: 2 funnels with ship's boats on booms between them; mid; ~[30, 15] m [typical]
- **後部艦橋 Aft bridge**: secondary conning position; stern-mid, centre; ~[8, 3] m [typical]
- **後部主砲塔 Aft 12-inch twin turret**: main battery; stern, centre; ~[11, 11] m [sourced]
- **錨甲板 Forecastle / anchor gear**: anchoring; bow; ~[15, 12] m [sourced]

### 中甲板 Main (battery) deck (level 3.0 m)

- **6-inch casemate battery**: 10 secondary guns with the mess spaces between them; mid, port and starboard; ~[55, 20] m [typical]
- **長官公室 Admiral's day cabin**: conference and dining room of the C-in-C; stern, centre; ~[10, 14] m [typical]
- **長官室 Admiral's sleeping cabin**: Togo's cabin; stern, starboard; ~[4, 4] m [typical]
- **艦長室 Captain's cabin**: Captain Ijichi Hikojiro's quarters; stern, port; ~[5, 4] m [sourced (exists); typical (position)]
- **参謀長室 Chief of Staff's cabin**: Kato Tomosaburo's quarters; stern; ~[3.5, 3.5] m [typical]
- **士官室 Wardroom**: officers' mess; stern-mid; ~[10, 8] m [typical]
- **烹炊所 Galley**: cooking for ~860 men; mid, near the funnel casings; ~[8, 6] m [typical]
- **厠 Heads**: latrines; bow (crew), stern (officers); ~[4, 3] m [typical]

### 下甲板 Lower deck (level 0.5 m)

- **兵員居住区 Crew berthing (fore)**: hammock berthing and mess for ratings; bow; ~[25, 20] m [typical]
- **Torpedo flat**: 4 submerged 45 cm torpedo tubes; bow and stern, port and starboard; ~[8, 20] m [typical]
- **無線電信室 Wireless room**: Type 36 radio (信濃丸's 'enemy sighted' message was received by this ship); mid; ~[3, 3] m [reconstruction]

### 船倉甲板 Platform / hold (machinery, magazines) (level -4.0 m)

- **前部弾火薬庫 Fore magazine and shell room**: 12-inch charges and shells; bow, centre under the fore turret; ~[12, 14] m [typical]
- **汽罐室 Boiler rooms (3)**: 25 Belleville water-tube boilers; mid; ~[36, 14] m [sourced (boilers); typical (layout)]
- **機械室 Engine rooms (2, port/starboard)**: 2 vertical triple-expansion engines; stern-mid, port and starboard, separated by a centreline bulkhead; ~[18, 9] m [typical]
- **後部弾火薬庫 Aft magazine**: 12-inch charges (this magazine exploded in 1905); stern, centre; ~[12, 14] m [sourced (explosion site)]
- **Shaft alleys and steering gear**: propeller shafts and steering engine; stern; ~[20, 3] m [typical]

## Exterior

- Materials: steel hull and superstructure, teak/wood upper-deck planking, armour belt along the waterline
- Colours: {'hull_1905': 'dark grey (wartime 鼠色)', 'boot_topping': 'dark red/black (uncertain)', 'deck': 'natural wood', 'funnels': 'grey with black tops (uncertain)', 'memorial_today': 'grey'}
- Features: two upright funnels, two military masts with fighting tops, Z flag (Z旗) at the masthead during the battle scene, rising-sun naval ensign at the stern, chrysanthemum crest on the bow, ram bow, twin 12-inch turrets fore and aft

## Flooding / sinking

- watertight_subdivision: Steel hull with transverse watertight bulkheads, a double bottom under the machinery, and side coal bunkers acting as protective compartments. The compartment count is unverified.
- pumps: Steam-driven main circulating and bilge pumps in the machinery spaces, plus hand pumps (typical)
- sea_cocks: Magazine flooding cocks (弾火薬庫注水弁) next to each magazine (standard practice; the 1905 accident shows the risk). Kingston valves for the condensers.
- freeboard_m: 5.5
- **Battle of Tsushima (1905-05-27)**: Hit ~32-40 times, mostly in the upper works → No serious flooding ([source](https://military-historian.squarespace.com/archive-1/2017/11/12/tools-of-war-the-battleship-mikasa))
- **Magazine explosion at Sasebo (1905-09-11/12)**: Fire started near the aft magazine at night (cause disputed; one theory is sailors drinking alcohol lit by flame) → Aft magazine detonated, blowing out the hull aft → Sank by the stern in shallow harbour water; settled on the bottom with superstructure and masts above water (period photos) → 251-339 dead → Refloated 8 Aug 1906 and repaired for 2+ years ([source](https://trafficnews.jp/post/133670/2))
- Game hook: Fire in the aft handling room: a timer to the magazine explosion unless the flood cocks are opened
- Game hook: Opening the magazine flood cocks floods the aft compartments, giving a stern trim
- Game hook: The Sasebo harbour scenario: the ship settles upright on the bottom rather than capsizing (shallow water)

## Uncertain / reconstructed

- Exact deck heights and room dimensions are estimates; the museum ship below the lower deck is filled with concrete, so no physical evidence of the lower spaces exists today.
- Belt armour type (Harvey vs Krupp) is disputed between sources.
- Crew 830 vs 860.
- Sasebo death toll: 251 vs 339 vs ~600 (press).
- Exact positions of the cabins (長官公室 etc.) follow RN practice and need checking against the museum floor plan (official site unreachable this session).
- 1905 paint colours.
- Official museum pages (kinenkan-mikasa.or.jp) could not be fetched; facts come from search-result snippets.

## Sources

- Standard displacement 15,140 t; length 122 m (museum figure, between perpendiculars); width 23.2 m; speed 18 kt; main armament 12-inch x4 (2 twin mounts), secondary 6-inch x14 — <https://www.kinenkan-mikasa.or.jp/en/mikasa/index.html>
- Overall length 131.7 m (432 ft), beam 23.2 m, normal draught ~8.3 m, 15,140 long tons normal load, crew about 830 — <https://en.wikipedia.org/wiki/Japanese_battleship_Mikasa>
- Crew figure 860 appears in the museum leaflet (snippet truncated) — <https://www.kinenkan-mikasa.or.jp/en/documents/leaf_e.pdf>
- 25 Belleville boilers, 2 vertical triple-expansion engines, 2 shafts, 15,000 ihp — <https://navypedia.org/ships/japan/jap_bb_mikasa.htm>
- Coal 700 t standard / 1,521 t maximum — <https://www.kinenkan-mikasa.or.jp/en/mikasa/index.html>
- Armour: belt 229-102 mm, casemates 152-51 mm, deck 76-51 mm (Harvey nickel per Navypedia; other sources say Krupp cemented) — <https://navypedia.org/ships/japan/jap_bb_mikasa.htm>
- Main guns 40-cal 30.5 cm twin mounts, one fore and one aft; 8 cm guns on the upper deck, 10 per side — <https://trafficnews.jp/post/132819>
- Upper deck is wooden planking; it sounds underfoot — <https://trafficnews.jp/post/132819>
- On the open top bridge (最上艦橋) the floor marks where Togo stood (front row, right of centre) with Chief of Staff Kato Tomosaburo and staff officer Akiyama Saneyuki behind him; chart room and conning tower adjoin — <https://trafficnews.jp/post/132819/2>
- Togo stood on the compass deck above the bridge; Z flag hoisted at about 13:55 on 27 May 1905 — <https://wikipedia.com/wiki/Battle_of_Tsushima>
- Hit 32 times at Tsushima, 8 dead (one account; others say 40+ hits) — <https://military-historian.squarespace.com/archive-1/2017/11/12/tools-of-war-the-battleship-mikasa>
- On 11 Sep 1905 the aft magazine exploded while she was moored in Sasebo harbour and she sank in shallow water — <https://trafficnews.jp/post/133670/2>
- Death toll from the Sasebo explosion: 339 or 251 depending on source; contemporary press said ~600 — <https://warshipsresearch.blogspot.com/2024/09/japanese-battleship-mikasa-lost-due-to.html>
- Refloated 8 Aug 1906; repairs took over two years — <https://www.tokyoweekender.com/?p=57291>
- Primary record: 明治三十八年 軍艦三笠罹災関係 held by the NIDS library — <https://www.nids.mod.go.jp/publication/senshi/pdf/200603/1.pdf>
- As a memorial ship, everything below the lower deck is filled with concrete and earth (Washington Treaty); the main guns are replicas — <https://trafficnews.jp/post/132819>
- The museum restored the captain's cabin and the guns; exhibits about the Battle of the Japan Sea are inside — <https://www.jalan.net/kankou/spt_guide000000189647/>
- The museum tour map lists the conning tower, main armament, 6-inch auxiliary guns, bower anchor and bow crest — <https://www.kinenkan-mikasa.or.jp/en/tourmap/bridge_upp_deck_data/cunning_tower.html>

Confidence tags: sourced = from a cited source; typical = standard practice for the type/period, not verified; reconstruction = game simplification.
