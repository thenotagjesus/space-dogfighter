extends RefCounted
## Weapon table. proj: 0 bolt, 1 homing missile, 2 wave bolt, 3 dumbfire rocket, 4 gravity bomb.
## ammo -1 = infinite. Index 7 (chaingun) is mech-only.
const LIST := [
	{"name": "TWIN BLASTER", "cd": 0.09, "max": -1, "start": -1, "cost": 1, "proj": 0, "speed": 300.0, "dmg": 6.0, "count": 1, "col": Color(0.4, 1.0, 0.5)},
	{"name": "SPREAD FAN", "cd": 0.32, "max": 120, "start": 60, "cost": 1, "proj": 0, "speed": 260.0, "dmg": 5.0, "count": 5, "fan": 7.0, "col": Color(1.0, 0.9, 0.3)},
	{"name": "LASER BEAM", "cd": 0.06, "max": 300, "start": 150, "cost": 1, "beam": true, "dmg": 2.6, "range": 380.0, "col": Color(1.0, 0.2, 0.3)},
	{"name": "WAVE BEAM", "cd": 0.18, "max": 160, "start": 80, "cost": 1, "proj": 2, "speed": 210.0, "dmg": 8.0, "count": 2, "col": Color(0.3, 0.8, 1.0)},
	{"name": "HOMING MISSILE", "cd": 0.7, "max": 16, "start": 8, "cost": 1, "proj": 1, "speed": 130.0, "dmg": 65.0, "splash": 16.0, "count": 1, "col": Color(1.0, 0.55, 0.15)},
	{"name": "ROCKET SALVO", "cd": 1.0, "max": 40, "start": 16, "cost": 4, "proj": 3, "speed": 170.0, "dmg": 38.0, "splash": 10.0, "count": 4, "col": Color(1.0, 0.35, 0.1)},
	{"name": "GRAVITY BOMB", "cd": 1.2, "max": 8, "start": 3, "cost": 1, "proj": 4, "speed": 0.0, "dmg": 120.0, "splash": 35.0, "count": 1, "col": Color(0.7, 0.3, 1.0)},
	{"name": "MECH CHAINGUN", "cd": 0.05, "max": -1, "start": -1, "cost": 1, "proj": 0, "speed": 340.0, "dmg": 5.0, "count": 1, "jitter": 0.025, "col": Color(1.0, 1.0, 0.6)},
]
const SELECTABLE := 7
const MECH_GUN := 7
const MISSILE := 4

static func start_ammo() -> PackedInt32Array:
	var a := PackedInt32Array()
	for w in LIST: a.append(w["start"])
	return a
