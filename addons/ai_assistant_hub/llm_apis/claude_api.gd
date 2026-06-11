@tool
class_name ClaudeAPI
extends LLMInterface

const ANTHROPIC_VERSION := "2023-06-01"

var _headers: PackedStringArray


func _rebuild_headers() -> void:
	_headers = [
		"Content-Type: application/json",
		"anthropic-version: %s" % ANTHROPIC_VERSION,
	]
	if not _api_key.is_empty():
		_headers.append("x-api-key: %s" % _api_key)


func _initialize() -> void:
	_rebuild_headers()
	llm_config_changed.connect(_rebuild_headers)


func send_get_models_request(http_request: HTTPRequest) -> bool:
	if _api_key.is_empty():
		AIHubPlugin.print_err("Claude API key not set. Configure the API key in the main tab and try again.")
		return false

	var error := http_request.request(_models_url, _headers, HTTPClient.METHOD_GET)
	if error != OK:
		AIHubPlugin.print_err("Claude models request failed: %s" % _models_url)
		return false
	return true


func read_models_response(body: PackedByteArray) -> Array[String]:
	var json := JSON.new()
	var parse_result := json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		AIHubPlugin.print_err("Failed to parse Claude models response: %s" % json.get_error_message())
		return [INVALID_RESPONSE]

	var response = json.get_data()
	if not (response is Dictionary) or not response.has("data") or not (response.data is Array):
		AIHubPlugin.print_err("Failed to get model list from Claude: %s" % JSON.stringify(response))
		return [INVALID_RESPONSE]

	var model_names: Array[String] = []
	for entry in response.data:
		if entry is Dictionary:
			if entry.has("id"):
				model_names.append(str(entry.id))
			elif entry.has("name"):
				model_names.append(str(entry.name))
	model_names.sort()
	return model_names


func send_chat_request(http_request: HTTPRequest, content: Array) -> bool:
	if _api_key.is_empty():
		AIHubPlugin.print_err("Claude API key not set. Configure the API key in the main tab and spawn a new assistant.")
		return false

	if model.is_empty():
		AIHubPlugin.print_err("ERROR: You need to set an AI model for this assistant type.")
		return false

	var body := JSON.stringify(_build_chat_body(content))
	var error := http_request.request(_chat_url, _headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		AIHubPlugin.print_err("Claude chat request failed.\nURL: %s\nRequest body: %s" % [_chat_url, body])
		return false
	return true


func read_response(body: PackedByteArray) -> String:
	var json := JSON.new()
	var parse_result := json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		AIHubPlugin.print_err("Failed to parse Claude chat response: %s" % json.get_error_message())
		return INVALID_RESPONSE

	var response = json.get_data()
	if not (response is Dictionary):
		AIHubPlugin.print_err("Failed to parse Claude chat response: %s" % JSON.stringify(response))
		return INVALID_RESPONSE
	if response.has("error"):
		AIHubPlugin.print_err("Claude API Error: %s" % JSON.stringify(response.error))
		return INVALID_RESPONSE

	if response.has("content") and response.content is Array:
		var text := ""
		for block in response.content:
			if block is Dictionary and block.get("type", "") == "text" and block.has("text"):
				text += str(block.text)
		if not text.is_empty():
			return _msg_cleaner.clean(text)

	AIHubPlugin.print_err("Failed to parse Claude chat response: %s" % JSON.stringify(response))
	return INVALID_RESPONSE


func _build_chat_body(content: Array) -> Dictionary:
	# Claude accepts system text separately and only user/assistant roles in the message list.
	var messages := []
	var system_parts: Array[String] = []
	for entry in content:
		if not (entry is Dictionary):
			continue
		var role := str(entry.get("role", "user"))
		var text := str(entry.get("content", entry.get("text", "")))
		if role == "system":
			system_parts.append(text)
			continue
		if role != "assistant":
			role = "user"
		_append_message(messages, role, text)

	var body_dict := {
		"model": model,
		"max_tokens": 4096,
		"messages": messages,
	}
	if not system_parts.is_empty():
		body_dict["system"] = _join_system_parts(system_parts)
	if override_temperature:
		body_dict["temperature"] = temperature
	return body_dict


func _join_system_parts(system_parts: Array[String]) -> String:
	var text := ""
	for part in system_parts:
		if not text.is_empty():
			text += "\n\n"
		text += part
	return text


func _append_message(messages: Array, role: String, text: String) -> void:
	if not messages.is_empty():
		var last_message = messages[messages.size() - 1]
		if last_message is Dictionary and last_message.get("role", "") == role:
			# Claude requires alternating roles, so consecutive entries with the same role are merged.
			last_message["content"] = "%s\n\n%s" % [last_message.get("content", ""), text]
			messages[messages.size() - 1] = last_message
			return
	messages.append({
		"role": role,
		"content": text,
	})
