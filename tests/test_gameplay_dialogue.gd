extends "res://tests/test_case.gd"
## Gameplay Kit: dialogue between the player and what it talks to. Text reveal styles (letter by
## letter with a beat after punctuation, word by word, all at once, one of your own); the dialogue
## box picks a line's style, else its conversation's, else its own, and the player's Text speed
## option scales it (Instant: whole lines); the player's lines are named and pictured on the right;
## the other side is named after who speaks: an NPC, a boss (its intro as the fight starts, its
## defeat as it falls), an MDSDialogueTrigger on any object (interact or touch, once, conditions,
## story alternatives), with flags set even without a dialogue box.

const Fixture := preload("res://tests/game_fixture.gd")

var game: MDSWorldGame
var kit: MDSGameplay
var box: MDSDialogueBox

## A style of one's own: half the line at once, the rest a second later.
class Halves extends MDSTextReveal:
	func visible_characters(text: String, elapsed: float) -> int:
		return text.length() if elapsed >= 1.0 else text.length() / 2

func _run() -> void:
	MDSGameplaySetup.ensure_runtime_actions()
	MDSOptions.reset()
	_styles()
	Fixture.build()
	game = Fixture.make_game()
	kit = MDSGameplay.new()
	kit.name = "Gameplay"
	game.add_child(kit)
	box = MDSDialogueBox.new()
	box.name = "DialogueBox"
	game.add_child(box)
	add_child(game)
	await game.room_loaded
	await get_tree().process_frame
	_box_styles()
	_text_speed()
	_player_lines()
	await _npc_and_trigger()
	await _boss()
	await _without_box()
	MDSOptions.reset()
	game.queue_free()
	await get_tree().process_frame
	get_tree().paused = false

func _styles() -> void:
	var text := "Hi, you. Stay."
	var letters := MDSTextRevealLetters.make(10.0, 0.5, 0.2)
	check(letters.visible_characters(text, 0.0) == 0 and letters.visible_characters(text, 0.1) == 1, "letters: the first one after 1/10 s")
	check(letters.visible_characters(text, 0.301) == 3, "the comma shows at 0.3 s (%d)" % letters.visible_characters(text, 0.301))
	check(letters.visible_characters(text, 0.45) == 3, "and holds the typing a beat (0.2 s) after it (%d)" % letters.visible_characters(text, 0.45))
	check(letters.visible_characters(text, 0.6) == 4, "then it goes on (%d)" % letters.visible_characters(text, 0.6))
	check(letters.visible_characters(text, 1.45) == 8 and letters.visible_characters(text, 1.61) == 9, "a longer beat (0.5 s) after the full stop (%d, %d)" % [letters.visible_characters(text, 1.45), letters.visible_characters(text, 1.61)])
	check(letters.is_done(text, 10.0) and not letters.is_done(text, 1.0), "and is done in the end")
	var words := MDSTextRevealWords.make(4.0, 0.5, 0.2)
	check(MDSTextRevealWords.word_ends(text) == PackedInt32Array([4, 9, 14]), "words end with their spaces: %s" % [MDSTextRevealWords.word_ends(text)])
	var seen: Array[int] = []
	for i in 40:
		var n := words.visible_characters(text, i * 0.05)
		if seen.is_empty() or seen[seen.size() - 1] != n:
			seen.append(n)
	check(seen == [0, 4, 9, 14], "word by word, never part of a word: %s" % [seen])
	check(words.visible_characters(text, 0.25) == 4 and words.visible_characters(text, 0.65) == 4 and words.visible_characters(text, 0.75) == 9, "the next word waits a beat after the comma")
	check(MDSTextReveal.new().visible_characters(text, 0.0) == text.length(), "the plain style shows the line at once")
	var halves := Halves.new()
	check(halves.visible_characters(text, 0.2) == 7 and halves.is_done(text, 1.0), "a style of one's own works (%d)" % halves.visible_characters(text, 0.2))

func _talk(d: MDSDialogueData, speaker: Node = null) -> void:
	box.start(d, speaker)

func _box_styles() -> void:
	var d := MDSDialogueData.make("styles", "Elder", ["One two three.", "Four five.", "Six."])
	d.lines[1].reveal = MDSTextRevealWords.make(10.0, 0.0, 0.0)
	_talk(d)
	check(box.is_open() and get_tree().paused, "the box opens and pauses the game")
	check(box.line_reveal is MDSTextRevealLetters and is_equal_approx((box.line_reveal as MDSTextRevealLetters).letters_per_second, 45.0), "with no style set, letters at chars_per_second")
	box._reveal_more(3.0 / 45.0 + 0.001)
	check(box.get_visible_text() == "One", "three letters after 3/45 s ('%s')" % box.get_visible_text())
	box.advance()
	check(not box.is_typing() and box.get_visible_text() == "One two three.", "advance shows the rest of the line")
	box.advance()
	check(box.line_index == 1 and box.line_reveal is MDSTextRevealWords, "the line's own style wins")
	box._reveal_more(0.15)
	check(box.get_visible_text() == "Four ", "a whole word at a time ('%s')" % box.get_visible_text())
	box.advance()
	box.advance()
	check(box.line_index == 2 and box.line_reveal is MDSTextRevealLetters, "the next line goes back to the box's")
	box.end()
	var counts: Array[int] = []
	box.characters_shown.connect(func(n: int) -> void: counts.append(n))
	d.reveal = MDSTextRevealWords.make(5.0, 0.0, 0.0)
	box.reveal = Halves.new()
	_talk(d)
	check(box.line_reveal is MDSTextRevealWords, "the conversation's style comes before the box's")
	box._reveal_more(0.21)
	box._reveal_more(0.2)
	check(counts == [4, 8], "characters_shown tells how far the text came (%s)" % [counts])
	box.end()
	d.reveal = null
	_talk(d)
	check(box.line_reveal is Halves and box.get_visible_text() == "One two", "else the box's own, a style of one's own too ('%s')" % box.get_visible_text())
	box.end()
	box.reveal = null

func _text_speed() -> void:
	var d := MDSDialogueData.make("speed", "Elder", ["Slowly now."])
	MDSOptions.text_speed = 0
	_talk(d)
	box._reveal_more(4.0 / 45.0 + 0.001)
	check(box.get_visible_text() == "Sl", "Slow types at 0.6 times the pace ('%s')" % box.get_visible_text())
	box.end()
	MDSOptions.text_speed = 3
	_talk(d)
	check(not box.is_typing() and box.get_visible_text() == "Slowly now.", "Instant shows whole lines")
	box.end()
	box.use_text_speed_option = false
	_talk(d)
	check(box.is_typing(), "a box may ignore the option")
	box.end()
	box.use_text_speed_option = true
	MDSOptions.text_speed = 1

func _player_lines() -> void:
	var face := ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGBA8))
	box.player_name = "Wanderer"
	box.player_portrait = face
	var d := MDSDialogueData.make("chat", "", ["Who goes there?", "Only me."])
	d.lines[1].from_player = true
	var npc := MDSNPC.new()
	npc.npc_name = "Elder"
	game.room_node.add_child(npc)
	_talk(d, npc)
	check(box._name.text == "Elder" and box._name.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT, "the one talked to speaks on the left, by name")
	box.advance()
	box.advance()
	check(box._name.text == "Wanderer" and box._name.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT, "the player's line is named after the player, on the right")
	check(box._portrait_right.visible and box._portrait_right.texture == face and not box._portrait.visible, "with the player's portrait on the right")
	box.end()
	npc.queue_free()

func _npc_and_trigger() -> void:
	# A dialogue trigger on a statue: talking to the statue, by the statue's name.
	var statue := Node2D.new()
	statue.name = "MossyStatue"
	game.room_node.add_child(statue)
	var t := MDSDialogueTrigger.new()
	t.dialogue = MDSDialogueData.make("statue", "", ["It hums faintly."])
	t.dialogue.lines[0].set_flag = "heard_statue"
	t.alt_dialogues = [{"condition": "flag:heard_statue", "dialogue": MDSDialogueData.make("statue2", "", ["It is quiet now."])}]
	statue.add_child(t)
	check(t.get_dialogue_name() == "Mossy Statue", "a trigger speaks with its parent's name ('%s')" % t.get_dialogue_name())
	t.start()
	check(box.is_open() and box._name.text == "Mossy Statue" and box.data.id == "statue", "interacting with it starts its conversation in the box")
	box.advance()
	box.advance()
	await get_tree().process_frame
	check(not box.is_open() and not t.talking and kit.get_flag("heard_statue") == true, "it ends, and its line set its flag")
	check(t.get_dialogue().id == "statue2", "the story moves it on to its other conversation")
	t.speaker_name = "Old stone"
	check(t.get_dialogue_name() == "Old stone", "speaker_name names it outright")
	# Once, and only while its condition is met.
	var sign := MDSDialogueTrigger.new()
	sign.dialogue = MDSDialogueData.make("sign", "Sign", ["Beware."])
	sign.once = true
	sign.condition = "flag:sign_lit"
	game.room_node.add_child(sign)
	check(not sign.can_talk(), "silent while its condition is unmet")
	kit.set_flag("sign_lit")
	check(sign.can_talk(), "talks once it is met")
	sign.start()
	box.end()
	await get_tree().process_frame
	check(sign.is_spent() and not sign.can_talk() and game.is_object_stored(sign), "with once, it has its say the first time only (stored)")
	# On touch: walking into it starts it.
	var touch := MDSDialogueTrigger.new()
	touch.trigger = MDSDialogueTrigger.Trigger.TOUCH
	touch.dialogue = MDSDialogueData.make("whisper", "Voice", ["Turn back."])
	game.room_node.add_child(touch)
	await get_tree().process_frame
	touch.body_entered.emit(game.player)
	check(box.is_open() and box.data.id == "whisper", "a touch trigger starts as the player walks in")
	box.end()
	await get_tree().process_frame

func _boss() -> void:
	var boss := MDSBoss.new()
	boss.boss_name = "Moss Knight"
	boss.intro_dialogue = MDSDialogueData.make("intro", "", ["You shall not pass."])
	boss.defeat_dialogue = MDSDialogueData.make("defeat", "", ["The moss... takes me..."])
	boss.position = Vector2(400, 300)
	game.room_node.add_child(boss)
	await get_tree().process_frame
	boss.start_fight()
	check(box.is_open() and box.data.id == "intro" and box._name.text == "Moss Knight", "a boss says its intro as the fight starts, by its name")
	box.end()
	boss.health.take_damage(1000)
	check(boss.dying and box.is_open() and box.data.id == "defeat" and box._name.text == "Moss Knight", "and its defeat as it falls")
	box.end()
	await get_tree().process_frame

func _without_box() -> void:
	box.remove_from_group(&"mds_dialogue_box")
	var t := MDSDialogueTrigger.new()
	t.dialogue = MDSDialogueData.make("note", "", ["A note."])
	t.dialogue.lines[0].set_flag = "read_note"
	game.room_node.add_child(t)
	await t.start()
	check(kit.get_flag("read_note") == true and not t.talking, "without a dialogue box, its lines' flags are set at once")
	box.add_to_group(&"mds_dialogue_box")
