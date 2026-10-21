@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_text_reveal.svg")
class_name MDSTextReveal
extends Resource
## How a line of dialogue comes onto the screen in an [MDSDialogueBox]. This one shows the whole
## line at once; [MDSTextRevealLetters] types it letter by letter and [MDSTextRevealWords] word by
## word. Set one on the dialogue box (every line), on an [MDSDialogueData] (a conversation: a
## boss speaking word by word) or on an [MDSDialogueLine] (one line).
##
## Another style is a script extending this one that overrides [method visible_characters]:
## [codeblock]
## class_name RevealHalves extends MDSTextReveal
## ## The first half of the line at once, the rest a second later.
## func visible_characters(text: String, elapsed: float) -> int:
##     return text.length() if elapsed >= 1.0 else text.length() / 2
## [/codeblock]
## The player's [member MDSOptions.text_speed] speeds every style up or down (Instant shows lines
## whole), and pressing an advance action shows the rest of the line.

## How many characters of [param text] show [param elapsed] seconds after the line came up (the
## whole line: [code]text.length()[/code]). It never goes down as [param elapsed] grows.
func visible_characters(text: String, _elapsed: float) -> int:
	return text.length()

## Whether all of [param text] shows after [param elapsed] seconds.
func is_done(text: String, elapsed: float) -> bool:
	return visible_characters(text, elapsed) >= text.length()

## Extra seconds a character holds the reveal after it shows, for a beat after punctuation:
## [param after_stop] after . ! ? and …, [param after_pause] after , ; : and dashes.
static func punctuation_pause(c: String, after_stop: float, after_pause: float) -> float:
	if c in [".", "!", "?", "…"]:
		return after_stop
	if c in [",", ";", ":", "—", "–"]:
		return after_pause
	return 0.0
