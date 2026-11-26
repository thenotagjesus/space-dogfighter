# Space Dogfighter  v0.4.0

A 90s-style low-poly "boomer shooter in space": fast arcade dogfights among drifting space rocks, with netplay and bots, plus a co-op top-down **Horde** mode with waves, score chains, drops and bosses.
Made with **Godot Engine** 4.7 (GDScript only, Compatibility renderer, so it runs on old GPUs too). This game is MIT licensed (see `LICENSE`).
Godot Engine is copyright (c) 2014-present Godot Engine contributors and (c) 2007-2014 Juan Linietsky, Ariel Manzur, and is used under the MIT licence. The engine licence and third-party notices are bundled as `GODOT_LICENSE.txt` and `GODOT_COPYRIGHT.txt` (from the 4.7.2-stable tag) and are also listed on the in-game Credits screen.

Open source and pay-what-you-want. 50% goes to cancer charities.
All meshes, effects, icons and HUD are built in code. There are no third-party assets.

## Open / run
1. Install Godot 4.7.x (standard build, not .NET) from https://godotengine.org.
2. Choose Import, pick `project.godot`, then press F5 (Play).

The game renders at 480x270 and is upscaled to a 1280x720 window for the chunky low-res look.

## Controls
| Action | Gamepad (Xbox layout) | Keyboard + mouse |
|---|---|---|
| Pitch / yaw (direct steering; fighter auto-banks into turns) | Left stick | Mouse, or the arrow keys |
| Hard bank (hold: banks 70 deg and turns much tighter); mech: lateral thrust | Right stick X | Q / E, or A / D |
| Barrel roll: double-tap a bank direction within 0.3 s. Free, 1 s cooldown. Deflects shots for most of the roll (the server decides) | Flick the right stick twice | Double-tap Q or E (or A or D) |
| Mech: vertical thrust | Right stick Y | Space / C |
| Fire selected weapon | RT | Left mouse or Ctrl |
| Homing missile: tap to fire on release; hold 0.85 s to charge a wider, longer lock (ring around the crosshair, reticle on the target) | LT | Right mouse or F |
| Previous / next weapon | D-pad left / right | Mouse wheel |
| Pick weapon directly |  | 1-7 |
| Boost (drains the meter); mech: forward thrust | RB | W |
| Brake (drains the meter, tighter turns); mech: reverse thrust | LB | S |
| Somersault loop (costs 25 meter); mech: boost-dash | A | Shift |
| U-turn: hold brake, then press the loop button (costs 20 meter) | LB + A | S + Shift |
| Mech quick-step: double-tap any thrust direction | double-tap RB / LB or flick a stick twice | double-tap W A S D Space C |
| Energy blade (mech): windup then lunge; parry an incoming lunge with the same button as it connects; after a parry press again to riposte; a mistimed press is a whiff and leaves you open | B | B |
| Mech mode toggle | Y | R |
| Scoreboard | Back/View | Tab |
| Camera: chase / cockpit | R3 | V |
| Pause / options | Start/Menu | Esc |

**Options** (main menu > OPTIONS, or Start/Esc in a match): Invert Pitch (Y), Invert Yaw (X), Invert Roll, Invert Mech Aim Y, and camera view (Chase/Cockpit). They apply to both gamepad and mouse and are saved in `user://settings.cfg`, so they survive restarts (on Windows: `%APPDATA%\Godot\app_userdata\Space Dogfighter\`). The menu's "Invert Y" checkbox is the same setting as Invert Pitch.

**Cockpit view**: the camera is fixed to the ship, with a low-poly canopy frame, dashboard and nose, and only a light G-lean and shake. In mech mode you look out of the torso window, with the arm guns at the bottom corners. Your own hull is hidden in this view so it doesn't clip the camera.

**Video** (same Options screen, saved): Display mode (Fullscreen = exclusive, Borderless = borderless fullscreen (default), Windowed = 75% of the screen, centred), Render scale (100% / 75% / 50% / Retro 480p pixelated), VSync, MSAA (Off / 2x / 4x), and a Show FPS counter toggle. The game opens at your monitor's native resolution, which it reads from the display (e.g. 3840x2160), and renders the 3D at full resolution. The HUD and menus are laid out on a 640x360 base and drawn crisply at native res, so text stays readable at 4K. Rendering uses the Compatibility (OpenGL 3.3) renderer for broad, safe Windows support, with filmic tonemapping, soft glow/bloom, distance fog and sun shadows.

The main menu also has the arena picker. You can change all bindings in Project > Project Settings > Input Map.

## Flight feel
The fighter flies at a constant 50 m/s cruise; boost to 100, brake to 26. The nose follows the stick directly (2.1 rad/s yaw, 2.0 rad/s pitch, with a soft centre), turns tighten when braking and widen when boosting. It auto-banks about 35 deg into turns and springs back level with no wobble. The meter (bar bottom-left, four pips of 25) feeds boost, brake, loop and U-turn; it refills 20/s after 0.9 s of rest, and if you run it dry, boost and brake stay off until it is back to 25 ("METER EMPTY"). Loop: a tight 1.25 s somersault that ends on the same heading, good for getting behind a chaser. U-turn: half loop and roll-out in 1 s, ends facing back the way you came. Steering is locked during loop and U-turn but you can still shoot. The server checks the meter, cooldowns, roll deflects and charged locks, so everyone plays by the same rules online. The camera pulls back with a wider view when boosting and tucks in when braking.
* Key moves:
  * Loop: 1.25 s somersault
  * U-turn: half loop and roll-out in 1 s
  * Barrel roll: deflects shots for most of the roll

The HUD shows the meter pips, LOOP / U-TURN readiness, a charge ring around the crosshair, a reticle on the locked target, and ROLL / LOOP / U-TURN / DEFLECT! cues. Bots use the barrel roll, loop and U-turn too.

## Mech mode
Press Y / R. Over 0.6 s the wings fold up, the nose tilts up into a torso, and legs, arms, shoulder pods, a backpack and a head with a crest extend. **While transforming you take 1.6x damage.** As a mech you aim the torso freely with the left stick / mouse and fire the **mech chaingun** (RT). Armour cuts incoming damage to 45%, but gravity bombs hit mechs for 150%. Homing missiles (LT) still work.

**Free 6DOF flight on thrusters.** The mech isn't parked any more: back, leg and shoulder thrusters push it along every axis. RB/LB (W/S) thrust forward/back, the right stick (A/D or Q/E, Space/C) thrusts sideways and up/down. Momentum carries and the thrusters fight it, so you drift to a stop instead of halting dead (top cruise is about 42 m/s). On the planet arenas (Star Surface, Ocean, Desert, Tech Planet) gravity pulls the mech down harder than a fighter: the passive hover jets carry half your weight, so you slowly sink unless you thrust up (right stick up / Space). Deep Space has no gravity.

**Quick-boost and quick-step.** Tap A (Shift) to dash in the direction you're thrusting (forward if you're not), or double-tap any thrust direction for a quick-step. A quick-boost keeps your existing speed, cancels only the component that fights the dash, adds a short punch and a 0.15 s burst, then a low-drag slide. Each dash costs 22 boost (the pips next to the BOOST bar show how many you have), has a 0.55 s cooldown, and a short **i-frame window (~0.20 s)** in which weapon hits and blade lunges whiff ("DODGE!"). Environmental hazards still hurt. **Dash cancel:** pull the trigger mid-dash (after the i-frames) to retro-burn out of the slide and snap your torso onto the locked target. Transforming at speed starts a separate inherit-glide, so your first shot does not slam the brakes.

**Momentum through the transform.** Transforming at speed turns your fighter velocity into a long, low-drag mech glide instead of a dead stop. Transforming back while dashing or moving fast **slingshots** you: the fighter keeps your velocity, multiplies it by 1.35 and adds a burst (up to 160).

**Body language.** Thruster flares fire from the nozzles that are actually pushing you (backpack for forward, feet for up, shoulders for sideways, braking and down). The head and torso turn to track the nearest enemy in front of you, the legs swing behind your momentum, and a hard dash leans the whole mech into it.

**Energy blade.** Press B (gamepad B; keyboard B — F is still the missile) in mech mode. There is a 0.3 s windup tell — the blade extends with a glowing flare and a rising hum, visible and audible to the target and everyone nearby, and an "INCOMING BLADE!" warning if it's aimed at you — then a forward lunge toward your lock (or straight ahead). The server checks a short range (~22 m) and a ~40° cone, like the laser, and deals a heavy slash (armour still applies). Then a 1.35 s cooldown. Bots will lunge at close range.

**Parry and riposte.** If you press B in a short server-checked window around the moment a lunge would connect (about 0.12 s early to 0.14 s late), the blades clash: sparks, a metallic clash sound, the attacker is staggered (brief control loss and a slow), and you get a ~0.7 s punish window to **riposte** — a lunge with only a 0.06 s windup. A **whiffed parry** (you pressed B because a lunge was coming, but you missed the window) puts the blade on cooldown and leaves you briefly open (you take 1.35× damage and can't parry). Pressing B with no incoming lunge just starts your own lunge. Two lunges that meet in the cone clash and stagger both sides, with no riposte. A dash or quick-step whose i-frames overlap the lunge's hit moment is an **evade** and shows DODGE!; the slash whiffs, hazards still hurt.

**Bots** fly mechs the same way: they hold a fighting range on thrusters, circle-strafe, fight gravity, quick-step when you line them up, and bail out of a dash into a slingshot. They also lunge at close range, and when a blade is coming they will sometimes parry (skill varies per bot, not always) and sometimes dash out of the way.

Netplay: movement stays owned by each pilot and syncs the thrust vector. Each dash is sent to the server as a reliable, numbered notice (replays and skipped numbers are refused). The server keeps its own boost meter per pilot, regenerating at the same 15/s rate the client uses, and only grants dash i-frames when that meter has at least 22 boost and at least 0.35 s have passed since the last granted dash; otherwise it refuses the i-frames and tells the pilot to cancel the dash. A granted dash window is backdated by half your ping (at most 100 ms), so it lines up with what you saw, and non-lethal hits that landed in that gap are refunded (a lethal hit stays lethal). Starting a blade windup ends your own i-frames, so a riposte is never invulnerable. A parry press is credited for your ping (at most 120 ms), and it only counts against a lunge that could actually reach you (within about 1.3x blade range and inside the attacker's hit cone). The server also caps how fast each remote ship may move for its state (fighter boost, mech, dash, slingshot 160 m/s, plus about 15%); a ship that moves faster is clamped and snapped back, not kicked. Blade windups, hits, parries, whiffs, evades and staggers are decided on the server and broadcast to every ready peer. The server is still authoritative for damage.

## Hangar and loadout
Before every Solo, Host or Join match the **Hangar** asks you to pick **2 weapons** from the pool of 7. The energy blade is always available in mech mode (B) and does not use a slot. The Hangar is pad- and keyboard-friendly: arrows or D-pad move, A / Enter (or keys 1-7) toggles a card, Start or Launch confirms when two are selected, B / Esc goes back. Your last pick is saved in `user://settings.cfg` and is the default next time. Procedural icons on the Hangar cards are the same icons the HUD uses for your two slots. Weapon cycling (wheel / previous / next) only switches between those two; keys 1-7 select a slot only if it is in your loadout. LT still fires a homing missile only if missile is one of your two weapons.

`--loadout=1,5` (1-based numbers, or 0-based) skips the Hangar and uses that pair. Headless / dedicated runs also skip the Hangar and use the saved or default loadout (Twin Blaster + Homing Missile). The client sends the pick with its join, and the server checks it at spawn: exactly two valid, distinct types, or it falls back to the default. Fire RPCs for a weapon that is not in that loadout are rejected. Bots each get a random different 2-weapon loadout.

## Weapons (pool of 7; you take 2)
1 Twin Blaster (infinite) - 2 Spread Fan (5-bolt fan) - 3 Laser Beam (continuous hitscan) - 4 Wave Beam (sine-weaving pair) - 5 Homing Missile (lock-on, splash) - 6 Rocket Salvo (4 dumbfire rockets) - 7 Gravity Bomb (falls, arms after 0.7 s, proximity fuse, big splash; good against mechs).
The HUD shows the current weapon, its ammo and the two loadout icons. Spinning crystal **pickups** around the arena refill one weapon type and repair 20 hull; they respawn after 15 s. You respawn with starter ammo. The server handles all fire validation, loadout, ammo, hits and damage.

## Arenas (chosen by the host / solo menu, or `--arena=N`)
0 **Deep Space**: drifting rock field, zero gravity.
1 **Star Surface**: glowing plasma floor that burns you, solar flare columns (they glow as a warning, then erupt and deal damage), heat haze.
2 **Ocean**: rolling waves, sea stacks and arches; flying low kicks up spray and hitting the water does damage.
3 **Desert**: dunes, mesas, a winding canyon, haze.
4 **Tech Planet**: city grid, towers, a megastructure trench run, pylons.
5 **Circuit Yard**, 6 **Ember Basin**, 7 **Bastion Line**: top-down arenas (see Modes below).
The planet arenas have gentle gravity, a ceiling and an ALT readout (the top-down arenas have no gravity and no ALT readout). Every arena is generated from a fixed seed, so all clients build the same one. Joining clients are told which arena to build.

## Modes
Two modes, picked in the main menu "Mode (host/solo)" dropdown or with `--mode=horde` / `--mode=dogfight` on the command line: **Dogfight** (free-for-all frags, the classic mode) and **Horde** (co-op survival against waves on a top-down arena).

Top-down arenas: 5 **Circuit Yard** (neon grid, pillar rings, L-shaped walls), 6 **Ember Basin** (dark basalt columns, lava cracks, floating rocks), 7 **Bastion Line** (steel deck, bunker rows, a glowing defended line along the south edge). Play is locked to one horizontal plane 30 m above the floor; the camera looks down from above with a slight tilt. You can play Dogfight on them too. Choosing Horde with a non-top-down arena switches to Circuit Yard.

Horde levels (one per top-down arena): Circuit Yard = **GRID SWARM**, boss **HIVE MOTHER** (circles the yard, hatches swarmers, fires rings of bolts). Ember Basin = **MAGMA BREAK**: big magma rocks split into two smaller rocks, then into shards; boss **CINDER COLOSSUS** (stomps after the nearest pilot, fires fans of bolts, sheds new rocks as it cracks). Bastion Line = **SKYFALL LINE**: rows of marchers sweep side to side and step closer; any marcher that reaches the defended line costs a life; boss **DREADNOUGHT BARGE** (sweeps the far edge, fires broadsides, drops fresh formations).

Enemy types: Swarmers (flock straight at you), Darters (pause, then dash), Gunners (keep 70-110 m away, circle you and shoot red bolts), magma rocks, Marchers, and the bosses.

5 waves per level; wave 5 is the boss. Waves grow bigger each time and scale with the number of pilots. Clear the boss for +2000 each and the level loops harder (more enemies, more health, faster, faster bolts). The team shares 6 lives. Every pilot death costs one. At 0 it is GAME OVER: the run's scores and your high-score table are shown for 9 s, then a fresh run starts.

Score: every kill scores the enemy's points. Kills within 2.5 s of each other build a chain: the multiplier rises by 1 every 3 kills, up to x8, and resets if you pause or die. Later loops score 50% more per loop.

Drops (enemies sometimes drop them, the boss drops all three): REPAIR (+40 hull), AMMO (refills both loadout weapons and missiles), OVERDRIVE (halves weapon cooldowns for 8 s).

High scores: each PC keeps its own top 10 per level for its own pilot in `user://horde_scores.cfg`.

Co-op: no friendly fire in Horde. Host a game with Horde selected and friends join as normal; bots fight the horde alongside you. The barrel roll still deflects enemy bolts back at them.

HUD in Horde: SCORE, CHAIN xN, level / wave / loop, lives, a centre banner (WAVE 3, WARNING, LEVEL CLEAR, GAME OVER), a boss health bar, OVERDRIVE timer, red boxes on enemies, labelled drop markers. The Tab scoreboard adds a SCORE column.

### Top-down controls
Left stick (or arrow keys): point it in the direction you want to fly on screen; the ship turns to that heading. A mech also thrusts that way when the stick is pushed past about half way. Mouse X still turns. RT / LT, weapon switch, boost / brake, mech toggle, blade and the barrel roll (double-tap a bank direction) work as normal. Loop and U-turn are switched off on the plane (no climbing).

The gravity bomb becomes a proximity mine that drifts to a stop on the plane (in Horde it only triggers on enemies). The server keeps every ship on the plane: if a ship leaves it, the ship is clamped back and resynced. The Hangar 2-weapon loadout and its HUD icons work the same in every mode.

## Multiplayer
- **Solo vs bots**: offline play. Set the bot count in the menu (at least 1).
- **Host game**: starts a listen server on **UDP port 7777** (you can change it in the menu). The host plays too, and the menu's bots are added as well.
- **Join game**: type the host's IP and port.

The server is authoritative for shots, hits, damage, frags and respawns. Each player's own ship movement is client-owned, so flying feels responsive; the server clamps impossible speeds and resyncs the pilot. ENet allows up to 16 players.

**Port forwarding (playing over the internet):** on the host's router, forward **UDP 7777** (UDP only, not TCP) to the host PC's LAN IP. Then allow the game through the OS firewall; on Windows, accept the prompt or add an inbound UDP 7777 rule. Players join using the host's public IP. On a LAN, use the host's local IP (e.g. 192.168.x.x). Tools such as Tailscale, ZeroTier or Radmin VPN also work and need no port forwarding.

### Controllers
Any XInput / Xbox-style pad (and most others Godot recognises) works on every device slot: all bindings use device -1, so nothing is tied to "pad 0" or a known GUID. Pads can be plugged in after launch (hot-plug); a small "Controller connected: <name>" note appears bottom-left. Menus, Options, Credits and the Hangar all navigate by pad: D-pad or left stick to move, A to select, B to go back, Start to launch from the Hangar or pause in a match. If a pad still does nothing, run `SpaceDogfighter.exe -- --debug-input` from a terminal: it prints every connected pad's id, name and GUID at startup and on hot-plug, plus raw button/axis presses, which shows whether Windows is passing the pad to the game.

### Command line (handy for testing or a dedicated server)
`godot --path . -- --host --bots=3`, `-- --join=1.2.3.4`, `-- --solo`, `--name=Ace`, `--arena=0..7`, `--mode=dogfight|horde`, `--horde-wave=N` (testing: start Horde at wave N; 5 = boss), `--loadout=1,5` (skip Hangar; 1-based weapon numbers), `--view=0|1` (chase/cockpit, not saved), `--video=mode,scale,msaa` (test video settings), `--dedicated` (the host does not spawn its own ship), `--debug-net`, `--debug-input` (log pads, names, GUIDs and raw pad events).
Headless dedicated server: `godot --headless --path . -- --host --dedicated --bots=4`.

## Export for Windows
1. In Godot: Editor > Manage Export Templates > Download and Install (it must match 4.7.x).
2. Project > Export > Add... > Windows Desktop. The defaults are fine; x86_64 is the usual choice.
3. Export Project, which gives you a `.exe` + `.pck` (or tick "Embed PCK" to get a single exe).
A ready-made `export_presets.cfg` (Windows Desktop, single exe) is included. Optionally, rcedit can set the exe icon.

## Code map
- `scripts/main.gd`: menu, Hangar, credits and session start (ENet host/join/offline)
- `scripts/hangar.gd`: pre-match 2-weapon Hangar with procedural icons
- `scripts/world.gd`: arena, starfield, space rocks, MultiplayerSpawner, server combat rules and RPCs
- `scripts/ship.gd`: flight model, input, 2 MultiplayerSynchronizers (movement owned by the pilot, health/alive owned by the server), bot AI, chase camera with shake
- `scripts/projectile.gd`: bolts and homing rockets (ray-swept hits)
- `scripts/fx.gd`: explosions, sparks, muzzle flashes
- `scripts/hud.gd`: crosshair, bars, target boxes, lock, killfeed, scoreboard, Horde panel / boss bar / high scores
- `scripts/horde.gd`: Horde mode (server-run waves, enemy AI, bosses, chains, drops, team lives, high-score file; snapshot sync to clients)
- `scripts/horde_enemy.gd`: one horde enemy (procedural low-poly shape, hit sphere, client interpolation)
- `scripts/arenas.gd`: the 8 seeded arenas, including the 3 top-down ones
- `scripts/meshes.gd`: hand-built flat-shaded vertex-coloured meshes
