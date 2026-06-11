@tool
class_name AIAnswerHandler

signal bot_message_produced(message:String)
signal error_message_produced(message:String)

const COMMENT_LENGTH := 80
const STRUCTURED_EDIT_OPERATIONS := {
	"replace_selection": AIQuickPromptResource.CodePlacement.ReplaceSelection,
	"insert_before_selection": AIQuickPromptResource.CodePlacement.BeforeSelection,
	"insert_after_selection": AIQuickPromptResource.CodePlacement.AfterSelection,
	"chat_only": -1
}

var _code_writer: AssistantToolCodeWriter


func _init(plugin:EditorPlugin, code_selector:AssistantToolSelection) -> void:
	_code_writer = AssistantToolCodeWriter.new(plugin, code_selector)


func handle(text_answer:String, quick_prompt:AIQuickPromptResource) -> void:
	if quick_prompt == null:
		bot_message_produced.emit(text_answer)
	else:
		var chat_answer := text_answer
		if quick_prompt.format_response_as_comment and not _uses_structured_edit_response(quick_prompt):
			chat_answer = _convert_to_comment(chat_answer)
		bot_message_produced.emit(chat_answer)
		apply_actions(text_answer, quick_prompt)


func apply_actions(text_answer:String, quick_prompt:AIQuickPromptResource) -> void:
	if quick_prompt == null:
		return
	if _uses_structured_edit_response(quick_prompt):
		_apply_structured_edit(text_answer, quick_prompt)
		return
	if quick_prompt.format_response_as_comment:
		text_answer = _convert_to_comment(text_answer)
	match quick_prompt.response_target:
		AIQuickPromptResource.ResponseTarget.CodeEditor:
			_write_to_code_editor(text_answer, quick_prompt.code_placement)
		AIQuickPromptResource.ResponseTarget.OnlyCodeToCodeEditor:
			var code = _extract_gdscript(text_answer)
			if code.length() > 0:
				_write_to_code_editor(code, quick_prompt.code_placement)


func _uses_structured_edit_response(quick_prompt:AIQuickPromptResource) -> bool:
	return quick_prompt.response_target != AIQuickPromptResource.ResponseTarget.Chat \
		and quick_prompt.code_response_format == AIQuickPromptResource.CodeResponseFormat.StructuredEditJson


func _apply_structured_edit(text_answer:String, quick_prompt:AIQuickPromptResource) -> void:
	var parsed_edit := _parse_structured_edit(text_answer)
	if parsed_edit.has("error"):
		error_message_produced.emit(str(parsed_edit.get("error", "")))
		return
	var operation:String = str(parsed_edit.get("operation", ""))
	if operation == "chat_only":
		return
	var content:String = str(parsed_edit.get("content", ""))
	if quick_prompt.format_response_as_comment:
		content = _convert_to_comment(content)
	var code_placement:AIQuickPromptResource.CodePlacement = int(STRUCTURED_EDIT_OPERATIONS[operation])
	_write_to_code_editor(content, code_placement)


func _parse_structured_edit(text:String) -> Dictionary:
	# Structured edits are intentionally strict so a malformed model response never changes the Code Editor.
	var json_text := _extract_json_object_text(text)
	if json_text.is_empty():
		return _structured_edit_error("The assistant did not return a structured edit JSON object. The Code Editor was not modified.")
	var json := JSON.new()
	var parse_result := json.parse(json_text)
	if parse_result != OK:
		return _structured_edit_error("The assistant returned invalid structured edit JSON. The Code Editor was not modified.")
	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		return _structured_edit_error("The structured edit response must be a JSON object. The Code Editor was not modified.")
	var operation := str(data.get("operation", "")).strip_edges()
	if not STRUCTURED_EDIT_OPERATIONS.has(operation):
		return _structured_edit_error("The structured edit operation is not supported. The Code Editor was not modified.")
	if operation == "chat_only":
		return {
			"operation": operation,
			"content": ""
		}
	var content := ""
	if data.has("content"):
		content = str(data.get("content", ""))
	elif data.has("code"):
		content = str(data.get("code", ""))
	if content.strip_edges(true, true).is_empty():
		return _structured_edit_error("The structured edit response did not include edit content. The Code Editor was not modified.")
	return {
		"operation": operation,
		"content": content
	}


func _extract_json_object_text(text:String) -> String:
	var trimmed := text.strip_edges()
	if trimmed.begins_with("{") and trimmed.ends_with("}"):
		return trimmed
	# Accept fenced JSON or surrounding prose, since some models wrap valid JSON in a short explanation.
	var fenced_json := _extract_fenced_block(text, "json")
	if not fenced_json.is_empty():
		return fenced_json.strip_edges()
	var start := text.find("{")
	var end := text.rfind("}")
	if start != -1 and end > start:
		return text.substr(start, end - start + 1).strip_edges()
	return ""


func _extract_fenced_block(text:String, language:String) -> String:
	var fence := "```%s" % language
	var start := text.find(fence)
	if start == -1:
		return ""
	var content_start := text.find("\n", start + fence.length())
	if content_start == -1:
		return ""
	var end := text.find("```", content_start + 1)
	if end == -1:
		return ""
	return text.substr(content_start + 1, end - content_start - 1)


func _structured_edit_error(message:String) -> Dictionary:
	return {
		"error": message
	}


func _write_to_code_editor(text_answer:String, code_placement:AIQuickPromptResource.CodePlacement) -> void:
	var succeed = _code_writer.write_to_code_editor(text_answer, code_placement)
	if not succeed:
		error_message_produced.emit("The selection sent to the assistant was not found, you need to make the changes manually based on the response in the chat.")


func _extract_gdscript(text:String) -> String:
	var extracted_code:= ""
	var start:= text.find("```gdscript")
	var end:= text.find("```", start + 11)
	while start >= 0 and end >= start:
		if extracted_code.length() > 0:
			extracted_code += "\n"
		extracted_code += text.substr(start+11, end-start-11)
		start = text.find("```gdscript", end+3)
		end = text.find("```", start + 11)
	return extracted_code


func _convert_to_comment(text:String) -> String:
	text = text.strip_edges(true, true)
	if text.begins_with("#"):
		# Preserve model-provided comment formatting when it is already present.
		return text
	else:
		var result := "# "
		var line_length := COMMENT_LENGTH
		var curr_line_length := 0
		for i in range(text.length()):
			if curr_line_length >= line_length and text[i] == " ":
				result += "\n# "
				curr_line_length = 0
			else:
				result += text[i]
				if text[i] == "\n":
					result += "# "
					curr_line_length = 0
				curr_line_length += 1
		return result
