# Car Sim

GT racing sim. Blender builds the cars by script, Godot drives them.

`Play.bat` starts the game (Godot 4.7) on the main menu.

## What you can play
- **Race** against up to 5 AI drivers (1-10 laps), grid start with five red lights.
- **Championship**: 4 rounds (afternoon, sunset, rain, night), 25-18-15-12-10-8 points, final table.
- **Time trial**: alone against a see-through ghost of your best lap, with a live gap. Best laps are
  saved per car and conditions (in Godot's user folder) and shown in the menu.
- **Practice**: free laps alone.
- After a race: **Watch replay** with TV-style trackside cameras
  (Left/Right other car, Space pause, Up/Down speed, V TV or chase camera, Esc back).

## Menu options
- **Mode**: Realistic (full damage) or Arcade (a tenth of the damage, no leaks or fires, stability
  control, +15 % grip and brakes, +8 % power).
- **Circuit**: Valley GP (3.6 km, hills up to ~28 m) or the same circuit in reverse.
- **Car**: Cutlass 442 (front V8 sedan), Kiri Turbo (turbo four), Phoenix 455 (big V8), Saba V12 (mid-engined).
  Bodies and interiors from Sketchfab (CC BY 4.0, see `docs/CREDITS.md`) on our own chassis, wheels and physics.
- **Time**: day, sunset, night (floodlights, headlights). **Weather**: dry or rain (about 25 % less grip,
  spray, wet reflective track, rain sound).
- **Driving line**: off, braking zones, or the full racing line (green push, yellow lift, red brake).
- **Tyres & fuel**: tyres wear, fuel burns (and weighs). Pit lane on the north side of the pit straight,
  60 km/h limiter; stop in the yellow box for tyres, fuel and repairs.
- **Car setup**: rear wing, brake balance, springs, anti-roll balance, gearing (your car only).

## Racing
- **Slipstream**: up to 35 % less drag tucked in behind another car (within ~40 m); very close behind you also
  lose some downforce in the dirty air.
- **AI level**: Easy, Medium, Hard, Expert. Each driver has a personality (late braker, defender, steadiness)
  and form that varies race to race; the starting order is shuffled every race.
- **Sound and flames**: throttle blips on downshifts, pops and flames on lift-off and flat-out upshifts,
  brake discs glow when hot.
- **Saved between sessions**: menu choices, lap records per circuit / car / conditions, and an unfinished
  championship (Continue championship in the menu). Stored in Godot's user folder.

## Race control
- Track limits: whole car past the white line for over half a second = a strike. 3 warnings, then +5 s each.
- Yellow flag (incident ahead, the AI lifts too), blue flag (leader about to lap you), chequered flag.

## Controls
W/S gas, brake, reverse - A/D steer - Space handbrake - Q/E shift (Y = auto) - R back on track - V camera
N traction control - B ABS - M drift assist - 1/2 doors - H hood - T trunk - F windows - G repair
X x-ray - Tab debug bars - F1 help - F2 mute - F5 proving ground - F6 restart race - Esc menu
Gamepad: left stick steer (progressive curve), triggers gas/brake, A/X handbrake, Start menu; rumble on
kerbs, gravel, slides and impacts.

## Files
- `blender/import_car.py` puts a downloaded body on our chassis and splits it into damage panels
  (`CAR_VARIANT=midship CAR_OUT=saba.glb CAR_SRC=path/saba.glb blender --background --python blender/import_car.py`).
  `blender/build_all.py` + `variants.py` are the older fully scripted bodies (no longer used in the game).
- `tools/make_trailer.sh` records the trailer scenes with Godot's Movie Maker and cuts them with ffmpeg.
- `godot/scripts/`: `car.gd` physics, `car_specs.gd` the four cars + arcade factors, `car_setup.gd` setup
  and wear/fuel option, `parts.gd` damage, `track.gd` circuit, terrain, pit lane, floodlights,
  `race.gd` race flow, racing line, flags, penalties, pit stops, `ai_driver.gd` opponents,
  `championship.gd`, `ghost.gd` time trial, `replay.gd`, `racing_line.gd` driving line,
  `weather.gd` time of day and rain, `world.gd` sky and proving ground, `surfaces.gd` ground materials,
  `engine_audio.gd` / `remote_engine.gd` sound, `effects.gd` / `skidmarks.gd` smoke, spray, marks,
  `menu.gd` menus, `hud.gd` HUD, `main.gd` game flow + self tests.

## Self tests
`godot --headless --fixed-fps 120 --path godot -- --selftest=NAME [--car=fastback] [--arcade] [--rain]
[--night|--sunset] [--reverse] [--setup=downforce:2,gearing:-1] [--from=200]`, result in `godot/selftest_NAME.txt`.
Physics: settle, accel, brake, corner, drift, bumps, crash, lap, contacttest (car-to-car crashes), offtrack, fliptest. Race: race (all six AI-driven), ai1,
pittest, champtest, tttest, terraincheck. Audio: audio (writes `shots/engine_sample.wav`).
Screenshots (run without `--headless`): shot, trackshot, crashshot, raceshot, driftshot, dentshot,
carsshot, menushot, hillshot, replayshot.
