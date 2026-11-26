# Space Dogfighter: handoff notes (updated Nov 26 2026, NST)

## Current state: v0.4.0 built, NOT installed on the rig yet
- This folder holds v0.4.0 source (config/version 0.4.0, Net.VERSION "v0.4.0").
- Backup of the v0.3.0 source: /workspace/space-dogfighter-v0.3.0-backup/ (v0.3.0 is what the rig has).
- Build: /workspace/builds/SpaceDogfighter-windows-v0.4.0.zip (copied to SpaceDogfighter-windows.zip); source zip SpaceDogfighter-source-v0.4.0.zip. SHA256s are in the v0.4.0 report (not repeated here so this file can sit inside the source zip).
- Work files: /workspace/sdf-v030-work/v040/ (free-model prompts + raw drafts, build040.sh), tests in /workspace/sdf-v030-work/tests/ (run_v040_suite*.sh, run_latency.sh, run_reconnect.sh, run_plane.sh, run_horde_net.sh, *_drv.gd).

## What v0.4.0 adds
- Top-down arenas 5 Circuit Yard, 6 Ember Basin, 7 Bastion Line (arenas.gd; cfg "topdown", plane_y 30, radius 320, no gravity).
  Play locked to the plane (ship.gd _td_*: heading steering from the left stick/arrows, mouse X turns, mech thrusts past 0.55 stick; loop/U-turn off; barrel roll on; top-down camera).
  Server: _srv_plane_check clamps |y - plane| > 1.5 m back and resyncs (same hold/RPC rules as the speed clamp).
- HORDE mode (Net.mode 1; menu "Mode", --mode=horde, cl_welcome(arena, mode)): scripts/horde.gd + horde_enemy.gd under World/Horde.
  Server-run waves (5 per level, wave 5 boss, then loop harder), team lives 6 (+1 per boss clear), chains (2.5 s window, +1 per 3 kills, cap x8),
  drops REPAIR/AMMO/OVERDRIVE, game over -> 9 s high-score screen -> reset. Local top-10 per level in user://horde_scores.cfg.
  Levels: GRID SWARM / HIVE MOTHER (5), MAGMA BREAK / CINDER COLOSSUS (6), SKYFALL LINE / DREADNOUGHT BARGE (7; a marcher formation reaching the line costs 1 life and lands).
  Sync: reliable cl_spawn/cl_die/cl_drop/cl_drop_gone/cl_over, 20 Hz unreliable_ordered cl_snap, 4 Hz cl_state, sync_to() for late joiners.
  Enemies: StaticBody3D on layer 2, so existing bolts/beams/missiles/splash/blade hit them; enemy bolts are Weapons.HORDE_BOLT (index 8, never selectable) shot by "#horde", so the barrel-roll deflect works on them.
  Co-op rules: no friendly fire (ship.server_damage ignores pilot attackers in horde), no frag penalties, every pilot death costs a team life. Bots/locks target enemies (world.lock_candidates).
  Gravity bomb on the plane = drifting proximity mine (enemy-only in horde).
- Mafee review fixes (ship.gd): spawn-seeded speed-clamp reference + clamped 1 s join grace (no unclamped seed window); hold refreshed on every violation (RPC still rate-limited) in the speed clamp, the manoeuvre end check and the plane clamp; ar_in_boost/ar_in_brake on MoveSync honoured by the server meter; stale charge press expires after 8 s and clears on transform/death. Meter syncs wait out the 1 s join grace (an unreliable sync could beat the spawn under loss).
- --port=N flag; --horde-wave=N test flag.

## Known issues / next (v0.4.0)
- Horde balance is first-pass, tuned against bots only; nobody has played it on a pad yet.
- Enemies fly through arena obstacles (they hover over them); ships bump off enemies (layer 2).
- A v0.3.0 client cannot join a v0.4.0 host (cl_welcome gained the mode argument); everyone needs v0.4.0.
- Box note: a few shell edits on Nov 26 ~19:05 NST silently didn't persist; all v0.4.0 changes were re-checked by grep before the build.

---
# Previous notes (v0.3.0)

## Current state: v0.3.0 built, NOT installed on the rig yet
- This folder holds v0.3.0 source (config/version 0.3.0, Net.VERSION "v0.3.0").
- Backup of the v0.2.1 source: /workspace/space-dogfighter-v0.2.1-backup2/ (also /workspace/builds/SpaceDogfighter-windows-v0.2.1.zip).
- Build: /workspace/builds/SpaceDogfighter-windows-v0.3.0.zip (copied to SpaceDogfighter-windows.zip)
  sha256 6c648be441666b287b3f7678e7f04078a21e74c50ae354cca0ce3f4172881ab9, 38,076,611 bytes
  exe sha256 a610c4e73748e73a36db3d1d8c379ec66e4d7aaed37d0120327a0d9baef0b3ab, 109,439,912 bytes
- Source zip: /workspace/builds/SpaceDogfighter-source-v0.3.0.zip (sha256 e45e39a13098ed3f78c7074761dd84eee171f12adb97c3041b6ad0fba01bcd4c; the zip inside this note predates this line)
- Full diff vs v0.2.1: /workspace/sdf-v030-work/v0.2.1-to-v0.3.0.diff. Tests and logs: /workspace/sdf-v030-work/tests/.
- Rig still has v0.2.1. Install via the usual CopyFromBox + PowerShell flow (Shaun approved installs) — the parent agent does that, not the executor.
- v0.2.1 QA (Ben Kim) and licence re-check (Chuck) were still pending at last check.

## What v0.3.0 adds (fighter mode only; mech untouched)
- Dudley's all-range flight pass (applied from the renamed WIP: SF_* -> AR_*, flag SF_FIGHTER -> ALL_RANGE; same values).
- Turn-limited, frame-rate-safe homing (projectile.gd).
- Server checks (ship.gd "all-range server checks" block + world.gd):
  - meter: client sends boost/brake intent only (srv_ar_intent); server drains/regens/locks at 0 until 25; resync via cl_ar_meter.
  - speed clamp per state: cruise 51.9 (cruise + roll slide), boost 100 (kept 1.3 s after server-granted boost), loop/U-turn 66 only for the move, sling/mech as before; x1.15 tolerance; now measured over 250 ms windows (old per-packet 3 m slack let ~180 m/s through); hold the corrected spot while stale packets drain after a resync/respawn; seed-only for the first ~0.7 s after join.
  - barrel roll: reliable srv_ar_roll(seq,dir), replay/jump checks, start backdated by clamp(rtt/2,0,100 ms), 1.0 s cooldown (40 ms tolerance) from backdated starts, cl_reject_roll rollback; server-only deflect window 55..440 ms after start; deflected projectiles bounce back owned by the roller; non-lethal deflectable hits inside the backdated window are refunded; lethal ones are not.
  - loop / U-turn: reliable srv_ar_man(seq,kind,dir); meter cost + 1.1 s cooldown charged at start; cl_reject_man rollback; end-position jump check.
  - charged lock: srv_charge_press on trigger press; server times press->fire arrival, caps at 0.85 s, cone 14->28 deg, range 400->520 m, line of sight re-checked at fire time.
- HUD: meter pips, LOOP/U-TURN readiness, METER EMPTY, charge ring, lock reticle, ROLL/LOOP/U-TURN/DEFLECT cues; DRIFT removed; HUD tap-lock diamond uses the 14 deg/400 m server cone.
- Bots: barrel-roll when someone close is aiming at them, U-turn / loop as Dudley set.
- README: controls + flight feel rewritten (no franchise names).

## Known issues / next
- Nobody has flown it on a pad yet. Feel review from Dudley welcome after Shaun tries it.
- If a reliable boost-intent packet is delayed by loss, an honest boosting client can get one clamp + resync (not observed in tests).
- Mafee was asked to review the server diff.
- Mouse aim may stutter at 30 fps (Dudley's note; _gather_input is shared with mech, left alone).
- Next: v0.4.0 top-down levels + arcade-classics mode (original names/assets, plane clamp on the server).
