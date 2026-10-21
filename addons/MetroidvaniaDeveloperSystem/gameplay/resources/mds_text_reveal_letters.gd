@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_text_reveal_letters.svg")
class_name MDSTextRevealLetters
extends MDSTextReveal
## Types the line out letter by letter (a typewriter), with a beat after punctuation.

## Letters shown per second.
@export_range(1.0, 400.0) var letters_per_second := 45.0
## Seconds the typing waits after . ! ? and …
@export_range(0.0, 2.0) var pause_after_stop := 0.25
## Seconds it waits after , ; : and dashes.
@export_range(0.0, 2.0) var pause_after_comma := 0.08

static func make(per_second: float, stop := 0.25, comma := 0.08) -> MDSTextRevealLetters:
	var r := MDSTextRevealLetters.new()
	r.letters_per_second = per_second
	r.pause_after_stop = stop
	r.pause_after_comma = comma
	return r

func visible_characters(text: String, elapsed: float) -> int:
	var step := 1.0 / maxf(letters_per_second, 0.001)
	var t := 0.0
	for i in text.length():
		t += step
		if t > elapsed:
			return i
		t += punctuation_pause(text[i], pause_after_stop, pause_after_comma) if i < text.length() - 1 else 0.0
	return text.length()
