@tool
class_name AssistantToolCodeWriter

const REVIEW_DIALOG_MIN_SIZE := Vector2i(820, 540)

var _plugin:EditorPlugin
var _code_selector:AssistantToolSelection
var _pending_edit := {}


func _init(_plugin:EditorPlugin, code_selector:AssistantToolSelection) -> void:
	self._plugin = _plugin
	_code_selector = code_selector


func write_to_code_editor(text_answer:String, code_placement:AIQuickPromptResource.CodePlacement) -> bool:
	var select_success := _code_selector.back_to_selection()
	if select_success:
		var script_editor := EditorInterface.get_script_editor().get_current_editor()
		if script_editor == null:
			AIHubPlugin.print_err("No script editor is active for the AI-generated edit.")
			return false
		var code_editor = script_editor.get_base_editor()
		var start_line:int = code_editor.get_selection_from_line()
		var text_to_apply := strip_empty_surrounding_lines(text_answer)
		if ProjectSettings.get_setting(AIHubPlugin.PREF_CONFIRM_CODE_EDITS, true):
			_show_review_dialog(code_editor, text_to_apply, code_placement)
		else:
			_apply_edit_to_code_editor(code_editor, text_to_apply, code_placement)
			code_editor.scroll_vertical = code_editor.get_scroll_pos_for_line(start_line) - 10
			code_editor.select(start_line, 0, start_line, 0)
		return true
	return false


func strip_empty_surrounding_lines(text:String) -> String:
	var lines:PackedStringArray = text.split("\n")
	while not lines.is_empty() and lines[0].is_empty():
		lines.remove_at(0)
	while not lines.is_empty() and lines[lines.size() - 1].is_empty():
		lines.remove_at(lines.size() - 1)
	return "\n".join(lines)


func _show_review_dialog(code_editor:TextEdit, text_answer:String, code_placement:AIQuickPromptResource.CodePlacement) -> void:
	var original_selection := code_editor.get_selected_text()
	_pending_edit = {
		"code_editor": code_editor,
		"text_answer": text_answer,
		"code_placement": code_placement,
		"selection_text": original_selection,
		"from_line": code_editor.get_selection_from_line(),
		"from_column": code_editor.get_selection_from_column(),
		"to_line": code_editor.get_selection_to_line(),
		"to_column": code_editor.get_selection_to_column()
	}

	var dialog := ConfirmationDialog.new()
	dialog.title = "Review AI Code Edit"
	dialog.min_size = REVIEW_DIALOG_MIN_SIZE
	dialog.ok_button_text = "Apply"
	dialog.cancel_button_text = "Reject"
	dialog.confirmed.connect(_on_review_dialog_confirmed.bind(dialog))
	dialog.canceled.connect(_on_review_dialog_closed.bind(dialog))
	dialog.close_requested.connect(_on_review_dialog_closed.bind(dialog))

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_new_review_label("Original selection"))
	root.add_child(_new_review_text(original_selection))
	root.add_child(_new_review_label("Proposed edit"))
	root.add_child(_new_review_text(text_answer))

	var copy_button := Button.new()
	copy_button.text = "Copy proposed edit"
	copy_button.pressed.connect(func(): DisplayServer.clipboard_set(text_answer))
	root.add_child(copy_button)

	dialog.add_child(root)
	_plugin.get_editor_interface().get_base_control().add_child(dialog)
	dialog.popup_centered(REVIEW_DIALOG_MIN_SIZE)


func _new_review_label(text:String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _new_review_text(text:String) -> TextEdit:
	var text_edit := TextEdit.new()
	text_edit.text = text
	text_edit.editable = false
	text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return text_edit


func _on_review_dialog_confirmed(dialog:ConfirmationDialog) -> void:
	if _pending_edit.is_empty():
		_on_review_dialog_closed(dialog)
		return
	var code_editor:TextEdit = _pending_edit.get("code_editor")
	if code_editor == null:
		AIHubPlugin.print_err("The Code Editor was closed before the AI-generated edit was applied.")
		_on_review_dialog_closed(dialog)
		return

	code_editor.select(
		_pending_edit.from_line,
		_pending_edit.from_column,
		_pending_edit.to_line,
		_pending_edit.to_column
	)
	if code_editor.get_selected_text() != _pending_edit.selection_text:
		AIHubPlugin.print_err("The original selection changed before the AI-generated edit was applied.")
		_on_review_dialog_closed(dialog)
		return

	var start_line:int = _pending_edit.from_line
	var text_answer:String = str(_pending_edit.get("text_answer", ""))
	var code_placement:AIQuickPromptResource.CodePlacement = int(_pending_edit.get("code_placement", AIQuickPromptResource.CodePlacement.ReplaceSelection))
	_apply_edit_to_code_editor(code_editor, text_answer, code_placement)
	code_editor.scroll_vertical = code_editor.get_scroll_pos_for_line(start_line) - 10
	code_editor.select(start_line, 0, start_line, 0)
	_on_review_dialog_closed(dialog)


func _on_review_dialog_closed(dialog:ConfirmationDialog) -> void:
	_pending_edit = {}
	if dialog:
		dialog.queue_free()


func _apply_edit_to_code_editor(code_editor:TextEdit, text_answer:String, code_placement:AIQuickPromptResource.CodePlacement) -> void:
	var start_line:int = code_editor.get_selection_from_line()
	var end_line:int = code_editor.get_selection_to_line()
	match code_placement:
		AIQuickPromptResource.CodePlacement.BeforeSelection:
			code_editor.set_caret_line(start_line)
			code_editor.insert_line_at(start_line, text_answer)
		AIQuickPromptResource.CodePlacement.AfterSelection:
			code_editor.set_caret_line(start_line)
			if end_line == code_editor.get_line_count() - 1: #it is at the end of the editor
				code_editor.text += "\n%s" % text_answer
			else:
				code_editor.insert_line_at(end_line + 1, text_answer)
		AIQuickPromptResource.CodePlacement.ReplaceSelection:
			code_editor.delete_selection()
			code_editor.insert_text_at_caret(text_answer)
		_:
			AIHubPlugin.print_err("Unexpected Quick Prompt code placement value: %s" % code_placement)
