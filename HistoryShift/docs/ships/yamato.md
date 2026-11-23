# 戦艦大和 / IJN Battleship Yamato

- Era: showa_war / Year: 1945
- Type: Yamato-class battleship (Kure Naval Arsenal; commissioned 16 Dec 1941)
- Spec: `data/ships/yamato.json`

## Dimensions

- length_overall_m: 263.0
- length_wl_m: 256.0
- beam_m: 38.9
- draft_m: 11.0
- displacement_t: {'standard': 65000, 'full': 72800, 'confidence': 'typical (widely cited; not verified this session)'}
- freeboard_m: {'bow': 10.0, 'mid': 8.7, 'stern': 6.4, 'confidence': 'typical'}
- bridge_top_above_deck_m: 30
- turrets: 3
- funnels: 1

## Crew

- 3332 3,332 at the final sortie

## Layout (deck by deck)

### 防空指揮所 / Air-defence command post (top of bridge tower) (level 39.0 m)

- **防空指揮所 Open AA command post**: captain (Aruga Kosaku) directed anti-aircraft evasion here in 1945; mid-forward, centre; ~[10, 8] m [typical]
- **15 m 主砲測距儀 Main rangefinder and director**: fire control for the 46 cm guns; tower top, transverse; ~[15, 3] m [sourced (top rangefinder)]

### 第一艦橋 First bridge (level 33.0 m)

- **第一艦橋 Main navigating bridge**: ship handling and command; tower, centre; ~[10, 6] m [sourced (exists, Yamato Museum)]
- **作戦室 Operations room**: plotting; tower, aft of the bridge; ~[6, 5] m [typical]

### 第二艦橋 / 司令塔 Second bridge and conning tower (level 16.0 m)

- **第二艦橋 Secondary bridge**: backup conn; tower, lower level; ~[8, 5] m [typical]
- **司令塔 Armoured conning tower**: battle steering with 500 mm armour; base of the tower; ~[6, 5] m [typical]

### 上甲板 Upper (weather) deck (level 8.7 m)

- **第一・第二主砲塔 No.1 and No.2 46 cm turrets**: main battery (superfiring); bow, centre; ~[20, 15] m [sourced]
- **第三主砲塔 No.3 turret**: main battery; stern-mid, centre; ~[20, 15] m [sourced]
- **15.5 cm secondary turret(s)**: secondary battery (one fore, one aft by 1945); fore and aft of the superstructure, centre; ~[10, 8] m [typical]
- **AA gun galleries**: 12.7 cm twin HA guns and ~150 25 mm machine guns (1945); mid, port and starboard; ~[80, 8] m [typical]
- **Aft catapult deck and hangar hatch**: 2 catapults, crane, seaplane hangar below; stern; ~[40, 30] m [typical]
- **Forecastle**: anchors and chain; bow; ~[50, 30] m [typical]

### 中甲板 / 下甲板 Middle and lower decks (living spaces) (level 3.5 m)

- **兵員居住区 Crew berthing**: mess decks for ~3,000 men; bow and stern, outside the citadel and above it; ~[30, 30] m [typical]
- **長官室・艦長室 Admiral's and captain's quarters**: flag quarters; stern, upper deck level; ~[8, 6] m [typical]
- **士官室 Wardroom**: officers' mess; stern; ~[12, 8] m [typical]
- **烹炊所 Galleys**: steam rice cookers for 3,000+; mid; ~[15, 10] m [typical]
- **医務室 Sick bay**: medical; mid; ~[10, 8] m [typical]

### Below the armour deck (citadel) (level -3.0 m)

- **主砲弾庫・火薬庫 Main magazines and shell rooms**: 46 cm shells (1.46 t each) and charges; under each main turret; ~[20, 30] m [sourced (lower belt)]
- **罐室 Boiler rooms (12 Kampon boilers)**: steam generation; mid, port, centre and starboard groups; ~[60, 30] m [sourced (count); typical (layout)]
- **機械室 Engine rooms (4 turbine sets)**: propulsion; mid-stern, 4 rooms side by side; ~[40, 30] m [sourced (flooding); typical (layout)]
- **舵取機室 Steering gear rooms**: main and auxiliary rudders; stern; ~[10, 10] m [typical]

## Exterior

- Materials: steel, wooden (Japanese cypress/teak) deck planking on the upper deck
- Colours: {'hull': 'IJN Kure grey (軍艦色)', 'deck': 'natural wood with dark steel strips', 'boot_topping': 'dark red'}
- Features: pagoda-like compact bridge tower, single swept-back funnel, three triple 46 cm turrets, flared bow with chrysanthemum crest, dense 25 mm AA batteries (1945), aft catapults

## Flooding / sinking

- watertight_subdivision: Extremely subdivided: the common figure is 1,147 watertight compartments (1,065 below the armour deck). The armoured citadel covers the magazines and machinery over roughly the middle half of the waterline length.
- pumps: Electric drainage pumps; counter-flooding system with remote-controlled valves to correct list (sourced in effect, through the 1945 counter-flooding)
- sea_cocks: Counter-flooding valves to the outboard voids and the starboard machinery rooms; magazine sprinkler and flooding systems
- freeboard_m: 8.7
- **Operation Ten-Go sinking (1945-04-07)**: 12:32 first air attack wave; bombs aft → Torpedoes concentrated on the port side cause a growing port list → ~13:33 starboard engine and boiler rooms counter-flooded to correct the list, drowning the engineering crews → Speed falls; rudder jammed → ~14:05 begins to capsize to port → ~14:20 capsizes → ~14:23 magazine explosion (fore No.1/2 or aft secondary, disputed); mushroom cloud → Wreck in two main pieces at ~340 m depth (typical figure) ([source](https://warhistory.org/@msw/article/the-sortie-of-the-battleship-yamato))
- Game hook: List meter: port flooding raises the list; the player can open starboard counter-flooding valves (trading engine power for stability)
- Game hook: Above ~20 degrees list, magazine shells shift inside the turret: explosion risk while capsizing
- Game hook: Many small compartments: slow progressive flooding along the damaged side

## Uncertain / reconstructed

- Bridge tower level heights are approximate; the tower had ~13 levels and the game uses 4 representative levels.
- Beam: 38.9 m (Wikipedia) vs 36.9 m (other sources).
- 1,147-compartment figure, displacement figures and wreck depth are widely cited but were not verified in this session.
- Which magazine exploded is disputed.
- Hammock vs bunk mix in the berthing.
- Yamato Museum (yamato-museum.com) pages could not be fetched; museum facts come from secondary articles.

## Sources

- Length 263 m overall (256 m waterline), beam 38.9 m, draught ~11 m — <https://en.wikipedia.org/wiki/Japanese_battleship_Yamato>
- 12 boilers, 4 steam turbines, 4 shafts, 150,000 shp, 27 kt — <https://en.Wikipedia.com/wiki/Yamato-class_battleship>
- Complement 3,233 (design); 3,332 aboard at the final sortie, of whom ~3,056 died — <https://www.mlit.go.jp/tagengo-db/R2-01781.html>
- 9 x Type 94 46 cm guns in 3 triple turrets; each turret 2,774 t; each gun 162 t — <https://www.scribd.com/book/375401205/Yamato-Japan-S-Doomed-Flagship>
- Main belt 41 cm over the citadel, lower belt 28 cm protecting the magazines; turret face ~65 cm — <https://www.pressreader.com/uk/history-of-war/20171102/282686162485768>
- Turret face armour 25 in (~64 cm), the heaviest ever fitted; total armour ~23,000 t; bridge top rangefinder ~100 ft (30 m) above the deck — <https://www.pbs.org/wgbh/nova/supership/expl-12.html>
- Yamato Museum 1/10 model: 26.3 m long, 3.9 m wide, reconstructed from drawings, dive-survey footage and crew testimony — <https://www.walkerplus.com/article/1006917/>
- 7 Apr 1945: at least 11 torpedoes (most on the port side) and 6+ bombs hit — <https://www.slashgear.com/1355015/yamoto-battleship-sinking-japan-history>
- Starboard engine and boiler rooms were counter-flooded to correct the port list (~13:33), drowning the men at their stations; capsized ~14:20; magazine explosion ~14:23 (which magazine is disputed) — <https://warhistory.org/@msw/article/the-sortie-of-the-battleship-yamato>
- Explosion cloud visible ~100 miles away — <https://www.usni.org/magazines/proceedings/1995/april/50-years-ago-kamikaze-yamato>

Confidence tags: sourced = from a cited source; typical = standard practice for the type/period, not verified; reconstruction = game simplification.
