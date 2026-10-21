@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_text_reveal_words.svg")
class_name MDSTextRevealWords
extends MDSTextReveal
## Shows the line a word at a time, with a beat after the words that end in punctuation. A word
## comes with the spaces after it.

const SPACES: PackedStringArray = [" ", "\t", "\n"]

## Words shown per second.
@export_range(0.5, 60.0) var words_per_second := 6.0
## Seconds it waits after a word ending in . ! ? or …
@export_range(0.0, 2.0) var pause_after_stop := 0.3
## Seconds it waits after a word ending in , ; : or a dash.
@export_range(0.0, 2.0) var pause_after_comma := 0.1

static func make(per_second: float, stop := 0.3, comma := 0.1) -> MDSTextRevealWords:
	var r := MDSTextRevealWords.new()
	r.words_per_second = per_second
	r.pause_after_stop = stop
	r.pause_after_comma = comma
	return r

## Where each word of [param text] ends (with the spaces after it on its line), in order.
static func word_ends(text: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	var i := 0
	var n := text.length()
	while i < n:
		while i < n and text[i] in SPACES:
			i += 1
		if i >= n:
			break
		while i < n and not text[i] in SPACES:
			i += 1
		var word_end := i
		while i < n and text[i] in [" ", "\t"]:
			i += 1
		out.append(i if i < n else word_end)
	return out

func visible_characters(text: String, elapsed: float) -> int:
	var step := 1.0 / maxf(words_per_second, 0.001)
	var t := 0.0
	var shown := 0
	for end in word_ends(text):
		t += step
		if t > elapsed:
			return shown
		shown = end
		# The word's last letter (before the spaces after it) may hold the next one back.
		var j := end - 1
		while j > 0 and text[j] in SPACES:
			j -= 1
		t += punctuation_pause(text[j], pause_after_stop, pause_after_comma)
	return text.length()
