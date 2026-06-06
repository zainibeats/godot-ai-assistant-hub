@tool
class_name OpenAICompatibleAPI
extends LLMInterface

var _headers: PackedStringArray


func _rebuild_headers() -> void:
	_headers = ["Content-Type: application/json"]
	if not _api_key.is_empty():
		_headers.append("Authorization: Bearer %s" % _api_key)


func _initialize() -> void:
	_rebuild_headers()
	llm_config_changed.connect(_rebuild_headers)


func send_get_models_request(http_request: HTTPRequest) -> bool:
	var error := http_request.request(_models_url, _headers, HTTPClient.METHOD_GET)
	if error != OK:
		AIHubPlugin.print_err("OpenAI-compatible models request failed: %s" % _models_url)
		return false
	return true


func read_models_response(body: PackedByteArray) -> Array[String]:
	var json := JSON.new()
	var parse_result := json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		AIHubPlugin.print_err("Failed to parse OpenAI-compatible models response: %s" % json.get_error_message())
		return [INVALID_RESPONSE]

	var response = json.get_data()
	if not (response is Dictionary) or not response.has("data") or not (response.data is Array):
		AIHubPlugin.print_err("Failed to get model list from OpenAI-compatible endpoint: %s" % JSON.stringify(response))
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
	if model.is_empty():
		AIHubPlugin.print_err("ERROR: You need to set an AI model for this assistant type.")
		return false

	var body_dict := {
		"model": model,
		"messages": content,
		"stream": false
	}
	if override_temperature:
		body_dict["temperature"] = temperature

	var body := JSON.stringify(body_dict)
	var error := http_request.request(_chat_url, _headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		AIHubPlugin.print_err("OpenAI-compatible chat request failed.\nURL: %s\nRequest body: %s" % [_chat_url, body])
		return false
	return true


func read_response(body: PackedByteArray) -> String:
	var json := JSON.new()
	var parse_result := json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		AIHubPlugin.print_err("Failed to parse OpenAI-compatible chat response: %s" % json.get_error_message())
		return INVALID_RESPONSE

	var response = json.get_data()
	if not (response is Dictionary):
		AIHubPlugin.print_err("Failed to parse OpenAI-compatible chat response: %s" % JSON.stringify(response))
		return INVALID_RESPONSE

	if response.has("choices") and response.choices.size() > 0:
		var choice = response.choices[0]
		if choice.has("message") and choice.message.has("content"):
			return _msg_cleaner.clean(choice.message.content)

	AIHubPlugin.print_err("Failed to parse OpenAI-compatible chat response: %s" % JSON.stringify(response))
	return INVALID_RESPONSE
