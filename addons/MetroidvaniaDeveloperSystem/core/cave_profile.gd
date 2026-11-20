@tool
class_name MDSCaveProfile
extends RefCounted
## What a family of caves looks like, as numbers only (no geometry): the ranges a generated room should fall in
## ([code]targets[/code]) and the distributions a generator draws from ([code]passage[/code]). A profile is
## measured from any set of rooms ([method MDSCaveStats.measure] on each) or written by hand, and is plain JSON,
## so rooms from any source (another game, rooms painted by hand) can make one. This class holds no profile of
## its own: with none, [MDSCaveSkeleton] draws from generic defaults.
## [codeblock]
## {"format": 1, "name": "...", "units": "tiles",
##  "targets": {"air_frac": {"min": 0.13, "p50": 0.27, "max": 0.52}, "thickness_p50": {...}},
##  "passage": {"width": {"p10": 4.0, "p50": 7.0, "p90": 12.9}}}
## [/codeblock]

const FORMAT := 1

var data: Dictionary = {}


## Profiles read from files: path -> {time (the file's modified time), data}. A file is read again when it changes,
## so Generate all reads a profile once, not once per room.
static var _cache: Dictionary = {}


## A profile from a dictionary, or from the path of a JSON file; empty for anything else (a path that can't be
## read warns and gives an empty profile: the generator then draws from its generic defaults).
static func from_value(value: Variant) -> MDSCaveProfile:
	var p := MDSCaveProfile.new()
	if value is Dictionary:
		p.data = value
	elif value is String and not (value as String).is_empty():
		p.data = load_json(value)
		if p.data.is_empty():
			push_warning("MDS: the cave profile %s is missing or not a JSON object; using the generic defaults." % value)
	return p


static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var stamp := FileAccess.get_modified_time(path)
	var hit: Variant = _cache.get(path)
	if hit is Dictionary and int((hit as Dictionary).time) == stamp:
		return (hit as Dictionary).data
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var data: Dictionary = parsed if parsed is Dictionary else {}
	_cache[path] = {"time": stamp, "data": data}
	return data


func is_empty() -> bool:
	return data.is_empty()


## The statistics a room should have: key -> {min, p50, max} (keys as [method MDSCaveStats.measure] returns them).
func targets() -> Dictionary:
	var t: Variant = data.get("targets", {})
	return t if t is Dictionary else {}


## How far [param stats] lies outside the targets: 0 when every target the stats have is inside min..max, else the
## sum, over the targets, of the distance outside in units of the target's range. Targets the stats lack are skipped.
func distance(stats: Dictionary) -> float:
	var total := 0.0
	var t := targets()
	for key in t:
		if not stats.has(key) or not (t[key] is Dictionary):
			continue
		var r: Dictionary = t[key]
		var v := float(stats[key])
		var lo := float(r.get("min", v))
		var hi := float(r.get("max", v))
		var span := maxf(hi - lo, 0.001)
		if v < lo:
			total += (lo - v) / span
		elif v > hi:
			total += (v - hi) / span
	return total


## A dictionary at a dotted [param path] ("passage.width"), or [param fallback].
func quantiles(path: String, fallback: Dictionary) -> Dictionary:
	var cur: Variant = data
	for key in path.split("."):
		if cur is Dictionary and (cur as Dictionary).has(key):
			cur = (cur as Dictionary)[key]
		else:
			return fallback
	return cur if cur is Dictionary else fallback
