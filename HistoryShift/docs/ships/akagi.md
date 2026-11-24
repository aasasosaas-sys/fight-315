# 航空母艦赤城 / IJN Aircraft Carrier Akagi

- Era: showa_war / Year: 1941
- Type: fleet carrier (converted battlecruiser hull; single flight deck after the 1935-38 rebuild)
- Spec: `data/ships/akagi.json`

## Dimensions

- length_overall_m: 260.67
- beam_m: 31.32
- draft_m: 8.71
- displacement_t: {'standard': 36500, 'full': 41300}
- flight_deck_m: {'length': 249.2, 'width': 30.5, 'height_above_wl': 16.0, 'confidence': 'length sourced; width and height typical'}
- freeboard_m: {'hull_main_deck': 7.0, 'flight_deck': 16.0}
- hangar_area_m2: 6521.1

## Crew

- 1630 

## Layout (deck by deck)

### 艦橋 Island (port side) (level 22.0 m)

- **羅針艦橋 Compass bridge**: conning; Nagumo and Captain Aoki at Midway; mid (slightly forward of amidships), PORT edge of the flight deck; ~[6, 4] m [sourced (port); typical (detail)]
- **発着艦指揮所 Flight control**: air officer; island, aft face; ~[4, 3] m [typical]
- **Mast and rangefinder**: signal mast; island top; ~[2, 2] m [typical]

### 飛行甲板 Flight deck (level 16.0 m)

- **Flight deck**: launch and recovery; full length; ~[249, 30.5] m [sourced (length, 3 lifts); typical (markings)]

### 上部格納庫 Upper hangar (level 10.5 m)

- **Upper hangar**: aircraft storage and arming; full length under the flight deck; ~[180, 22] m [sourced (enclosed)]

### 中部格納庫 Middle hangar (level 5.5 m)

- **Middle hangar**: aircraft storage; full length; ~[160, 20] m [typical]

### Main / living decks (level 0.5 m)

- **20 cm casemate guns**: 6 x 20 cm anti-ship guns (3 per side); stern, port and starboard, low on the hull; ~[30, 4] m [typical]
- **12 cm HA gun sponsons**: anti-aircraft; port and starboard sponsons below flight deck level; ~[6, 6] m [typical]
- **Crew berthing and messes**: ~1,600 crew, hammocks; bow and stern; ~[40, 25] m [typical]
- **Aircrew ready rooms**: briefing; island base / upper hangar side; ~[10, 8] m [reconstruction]
- **Funnel uptakes**: exhaust trunking; mid, STARBOARD side; ~[20, 6] m [sourced]

### Machinery and storage (below the waterline) (level -5.0 m)

- **Boiler and turbine rooms**: 19 Kampon boilers, 4 turbines (typical figures); mid; ~[80, 25] m [typical]
- **Aviation fuel tanks**: aviation gasoline; fore and aft, low; ~[10, 10] m [typical]
- **Bomb and torpedo magazines**: aircraft ordnance; fore and aft, low; ~[15, 15] m [typical]

## Exterior

- Materials: steel hull, wooden flight deck
- Colours: {'hull': 'IJN grey', 'flight_deck': 'natural wood (yellowish-brown)', 'markings': 'white'}
- Features: PORT-side island, starboard downward-curved funnel, long overhanging flight deck, battlecruiser-shaped hull, AA sponsons

## Flooding / sinking

- watertight_subdivision: Battlecruiser hull with armoured belt and transverse bulkheads below the main deck; the enclosed hangars above are essentially open fire zones with poor ventilation for venting explosions.
- pumps: Fire mains; electric pumps failed when power was lost (typical)
- sea_cocks: Kingston valves (typical); magazines had flooding valves
- freeboard_m: 7.0
- **Midway (1942-06-04)**: ~10:26 one 1,000 lb bomb at the aft edge of the middle elevator, exploding in the upper hangar → A near miss jams the rudder → Fuelled, armed aircraft and ordnance in the hangar explode; fire spreads through both hangars → Bridge abandoned; Nagumo transfers to cruiser Nagara → Ship burns all night, dead in the water but afloat (hull intact below the waterline) → 5 June: scuttled by destroyer torpedoes; sinks bow first ([source](https://warhistory.org/2020/05/27/sinking-of-akagi/))
- Game hook: Fire spreading between hangar bays: ordnance on trolleys causes chain explosions
- Game hook: The hull stays afloat despite total burnout; sinking requires torpedoes/scuttling (open sea cocks)
- Game hook: Fire curtains can slow the spread

## Uncertain / reconstructed

- Crew size (1,630 commonly cited, unverified).
- Exact elevator positions and sizes.
- The extent of the third (lower) hangar.
- Flight deck markings at Midway (the 'ア' marking is typical, unverified).
- Reason for the port-side island (exhaust vs paired operation with Kaga) is disputed.

## Sources

- After the 1938 rebuild: length 260.67 m, beam 31.32 m, draught 8.71 m; 36,500 long tons standard, 41,300 deep load — <https://www.wikiwand.com/en/Japanese_aircraft_carrier_Akagi>
- Rebuild gave one flight deck ~249 m long over two enclosed hangars — <https://en.wikipedia.org/wiki/Japanese_aircraft_carrier_Akagi>
- Three lifts (fore, middle, aft) — <https://navypedia.org/ships/japan/jap_cv_akagi.htm>
- Island on the port side (Kaga's on the starboard); funnels on the starboard side, angled downward, below the flight deck — <https://www.historyofwar.org/articles/weapons_akagi.html>
- Hangar area after rebuild 6,521.1 m2; aircraft 60 -> 91; flight deck made single and continuous on 31 Aug 1938 — <https://trafficnews.jp/post/89855>
- Originally completed with three stepped flight decks and twin 20 cm turrets on the middle level — <https://trafficnews.jp/post/532169/2>
- Flagship of the First Air Fleet, Apr 1941; sailed for Pearl Harbor from Hitokappu Bay 26 Nov 1941 — <https://en.Wikipedia.com/wiki/Japanese_aircraft_carrier_Akagi>
- Midway: Lt Richard Best's bomb hit at the aft edge of the middle elevator and exploded in the upper hangar among fuelled, armed B5N torpedo bombers — <https://www.maritime-executive.com/article/second-japanese-aircraft-carrier-wreck-discovered>
- Yamamoto ordered her scuttled; destroyers Arashi, Hagikaze, Maikaze, Nowaki torpedoed her on 5 June 1942 — <https://warhistory.org/2020/05/27/sinking-of-akagi/>
- Wreck found Oct 2019 by RV Petrel at ~5,490 m — <https://phys.org/news/2019-10-warship-wwii-midway.pdf>

Confidence tags: sourced = from a cited source; typical = standard practice for the type/period, not verified; reconstruction = game simplification.
