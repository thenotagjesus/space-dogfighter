# Space Dogfighter

A 90s-style low-poly "boomer shooter in space": fast arcade dogfights among asteroids, with netplay and bots.
Made with **Godot 4.7** (GDScript only, Compatibility renderer, so it runs on old GPUs too). MIT licensed.
All meshes, effects and HUD are built in code. There are no third-party assets.

## Download

Playable Windows build: see the [Releases](../../releases) page.

## Open source, pay what you want

Space Dogfighter is open source (MIT, see `LICENSE`) and pay-what-you-want. 50% of what you pay goes to cancer charities.

## Open / run
1. Install Godot 4.7.x (standard build, not .NET) from https://godotengine.org.
2. Choose Import, pick `project.godot`, then press F5 (Play).

The game renders at 480x270 and is upscaled to a 1280x720 window for the chunky low-res look.

## Controls
| Action | Gamepad (Xbox layout) | Keyboard + mouse |
|---|---|---|
| Pitch / yaw | Left stick | Mouse, or the arrow keys |
| Roll (strafe in mech mode on planets) | Right stick X | Q / E |
| Strafe up/down | Right stick Y | Space / C |
| Strafe left/right | (right stick in mech) | A / D |
| Fire selected weapon | RT | Left mouse or Ctrl |
| Fire homing missile (locks onto the target in the yellow diamond) | LT | Right mouse or F |
| Previous / next weapon | D-pad left / right | Mouse wheel |
| Pick weapon directly | | 1-7 |
| Boost (uses the boost meter); in mech: walk forward | RB | W |
| Brake (tighter turns); in mech: back off | LB | S |
| **Drift**: hold to cut grip and slide, release for a mini-turbo | A | Shift |
| **Mech mode** toggle | Y | R |
| Scoreboard | Back/View | Tab |
| Camera: chase / cockpit (first person) | R3 (right-stick click) | V |
| Pause / options (resume or leave match) | Start/Menu | Esc |

**Options** (main menu > OPTIONS, or Start/Esc in a match): Invert Pitch (Y), Invert Yaw (X), Invert Roll, Invert Mech Aim Y, and camera view (Chase/Cockpit). They apply to both gamepad and mouse and are saved in `user://settings.cfg`, so they survive restarts (on Windows: `%APPDATA%\Godot\app_userdata\Space Dogfighter\`). The menu's "Invert Y" checkbox is the same setting as Invert Pitch.

**Cockpit view**: the camera is fixed to the ship, with a low-poly canopy frame, dashboard and nose, and only a light G-lean and shake. In mech mode you look out of the torso window, with the arm guns at the bottom corners. Your own hull is hidden in this view so it doesn't clip the camera.

**Video** (same Options screen, saved): Display mode (Fullscreen = exclusive, Borderless = borderless fullscreen (default), Windowed = 75% of the screen, centred), Render scale (100% / 75% / 50% / Retro 480p pixelated), VSync, MSAA (Off / 2x / 4x), and a Show FPS counter toggle. The game opens at your monitor's native resolution, which it reads from the display (e.g. 3840x2160), and renders the 3D at full resolution. The HUD and menus are laid out on a 640x360 base and drawn crisply at native res, so text stays readable at 4K. Rendering uses the Compatibility (OpenGL 3.3) renderer for broad, safe Windows support, with filmic tonemapping, soft glow/bloom, distance fog and sun shadows.

The main menu also has the arena picker. You can change all bindings in Project > Project Settings > Input Map.

## Flight feel
Your velocity lags behind the nose (grip), so you swing through turns instead of rotating on the spot. The faster you fly, the wider you turn; braking tightens the turn. The ship banks into yaw turns, and on planets it levels itself out Ace Combat-style. The camera lags and leans, and speed lines plus a wider FOV kick in when you boost. Hold Drift to slide sideways while aiming, then let go for a burst of speed.

## Mech mode
Press Y / R. Over 0.6 s the wings fold up, the nose tilts up into a torso, and legs and arms extend. **While transforming you take 1.6x damage.** As a mech you hover in place, strafe slowly in any direction, aim the torso freely and fire the **mech chaingun** (RT). Armour cuts incoming damage to 45%, but gravity bombs hit mechs for 150%. Homing missiles (LT) still work. Bots transform now and then when an enemy is close.

## Weapons (1-7, plus the missile on LT)
1 Twin Blaster (infinite) - 2 Spread Fan (5-bolt fan) - 3 Laser Beam (continuous hitscan) - 4 Wave Beam (sine-weaving pair) - 5 Homing Missile (lock-on, splash) - 6 Rocket Salvo (4 dumbfire rockets) - 7 Gravity Bomb (falls, arms after 0.7 s, proximity fuse, big splash; good against mechs).
The HUD shows the current weapon, its ammo and the weapon strip. Spinning crystal **pickups** around the arena refill one weapon type and repair 20 hull; they respawn after 15 s. You respawn with starter ammo. The server handles all fire validation, ammo, hits and damage.

## Arenas (chosen by the host / solo menu, or `--arena=N`)
0 **Deep Space**: asteroid field, zero gravity.
1 **Star Surface**: glowing plasma floor that burns you, solar flare columns (they glow as a warning, then erupt and deal damage), heat haze.
2 **Ocean**: rolling waves, sea stacks and arches; flying low kicks up spray and hitting the water does damage.
3 **Desert**: dunes, mesas, a winding canyon, haze.
4 **Tech Planet**: city grid, towers, a Death-Star-style trench, pylons.
The planet arenas have gentle gravity, a ceiling and an ALT readout. Every arena is generated from a fixed seed, so all clients build the same one. Joining clients are told which arena to build.

## Multiplayer
- **Solo vs bots**: offline play. Set the bot count in the menu (at least 1).
- **Host game**: starts a listen server on **UDP port 7777** (you can change it in the menu). The host plays too, and the menu's bots are added as well.
- **Join game**: type the host's IP and port.

The server is authoritative for shots, hits, damage, frags and respawns. Each player's own ship movement is client-owned, so flying feels responsive. ENet allows up to 16 players.

**Port forwarding (playing over the internet):** on the host's router, forward **UDP 7777** (UDP only, not TCP) to the host PC's LAN IP. Then allow the game through the OS firewall; on Windows, accept the prompt or add an inbound UDP 7777 rule. Players join using the host's public IP. On a LAN, use the host's local IP (e.g. 192.168.x.x). Tools such as Tailscale, ZeroTier or Radmin VPN also work and need no port forwarding.

### Command line (handy for testing or a dedicated server)
`godot --path . -- --host --bots=3`, `-- --join=1.2.3.4`, `-- --solo`, `--name=Ace`, `--arena=0..4`, `--view=0|1` (chase/cockpit, not saved), `--video=mode,scale,msaa` (test video settings), `--dedicated` (the host does not spawn its own ship), `--debug-net`.
Headless dedicated server: `godot --headless --path . -- --host --dedicated --bots=4`.

## Export for Windows
1. In Godot: Editor > Manage Export Templates > Download and Install (it must match 4.7.x).
2. Project > Export > Add... > Windows Desktop. The defaults are fine; x86_64 is the usual choice.
3. Export Project, which gives you a `.exe` + `.pck` (or tick "Embed PCK" to get a single exe).
A ready-made `export_presets.cfg` (Windows Desktop, single exe) is included. Optionally, rcedit can set the exe icon.

## Code map
- `scripts/main.gd`: menu and session start (ENet host/join/offline)
- `scripts/world.gd`: arena, starfield, asteroids, MultiplayerSpawner, server combat rules and RPCs
- `scripts/ship.gd`: flight model, input, 2 MultiplayerSynchronizers (movement owned by the pilot, health/alive owned by the server), bot AI, chase camera with shake
- `scripts/projectile.gd`: bolts and homing rockets (ray-swept hits)
- `scripts/fx.gd`: explosions, sparks, muzzle flashes
- `scripts/hud.gd`: crosshair, bars, target boxes, lock, killfeed, scoreboard
- `scripts/meshes.gd`: hand-built flat-shaded vertex-coloured meshes
