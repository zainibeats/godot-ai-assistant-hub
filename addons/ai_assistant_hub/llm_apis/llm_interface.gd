@tool
class_name LLMInterface
# The intention of this class is to serve as a base class for any LLM API
# to be implemented in this plugin. It is mainly to have a clear definition
# of what properties or functions should be used by other classes.

signal model_changed(model:String)
signal override_temperature_changed(value:bool)
signal temperature_changed(temperature:float)
signal reasoning_changed(reasoning:String)
signal llm_config_changed
signal response_started
signal response_delta(delta:String)
signal response_completed(full_response:String)
signal response_failed(message:String)

const INVALID_RESPONSE := "[INVALID_RESPONSE]"

# Public properties can be modified from the chat tab, you can subscribe to their change events
var model: String:
	set(value):
		model = value
		model_changed.emit(value)
	get:
		return model

var override_temperature: bool:
	set(value):
		override_temperature = value
		override_temperature_changed.emit(value)
	get:
		return override_temperature

var temperature: float:
	set(value):
		temperature = value
		temperature_changed.emit(value)
	get:
		return temperature

var reasoning: String:
	set(value):
		reasoning = value
		reasoning_changed.emit(value)
	get:
		return reasoning

var _msg_cleaner:= ResponseCleaner.new()

var _base_url:String
var _models_url:String
var _chat_url:String
var _api_key:String
var _llm_provider:LLMProviderResource
var _stream_http_client: HTTPClient
var _stream_request_pending := false
var _stream_request_sent := false
var _stream_path := ""
var _stream_headers: PackedStringArray
var _stream_body := ""
var _stream_line_buffer := ""
var _stream_full_response := ""
var _stream_done := false


func _init(llm_provider:LLMProviderResource) -> void:
	if llm_provider == null:
		AIHubPlugin.print_err("Tried to create LLM instance with no provider.")
		return
	_llm_provider = llm_provider
	load_llm_parameters()
	_initialize()


func load_llm_parameters() -> void:
	var config = LLMConfigManager.new(_llm_provider.api_id)
	if _llm_provider.fix_url.is_empty():
		_base_url = config.load_url()
	else:
		_base_url = _llm_provider.fix_url
	_models_url = _base_url + _llm_provider.models_url_postfix
	_chat_url = _base_url + _llm_provider.chat_url_postfix
	_api_key = config.load_key()
	llm_config_changed.emit()


func get_full_response(body: PackedByteArray) -> Variant:
	var json := JSON.new()
	var parse_result := json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		AIHubPlugin.print_err("Failed to parse JSON in get_full_response: %s" % json.get_error_message())
		return body.get_string_from_utf8()
	var data = json.get_data()
	if typeof(data) == TYPE_DICTIONARY:
		return data
	else:
		AIHubPlugin.print_err("Parsed JSON is not a Dictionary in get_full_response.")
		return body.get_string_from_utf8()


#--- All methods below should be overriden by child classes, see for example OllamaAPI ---

func send_get_models_request(http_request:HTTPRequest) -> bool:
	return false


func read_models_response(body:PackedByteArray) -> Array[String]:
	return [INVALID_RESPONSE]


func send_chat_request(http_request:HTTPRequest, content:Array) -> bool:
	return false


func send_streaming_chat_request(content:Array) -> bool:
	return false


func read_response(body:PackedByteArray) -> String:
	return INVALID_RESPONSE


func poll_stream_response() -> void:
	if _stream_http_client == null:
		return
	var error := _stream_http_client.poll()
	if error != OK:
		_fail_streaming_response("Streaming request failed while polling: %s" % error)
		return

	match _stream_http_client.get_status():
		HTTPClient.STATUS_CONNECTED:
			if _stream_request_pending:
				_stream_request_pending = false
				_stream_request_sent = true
				error = _stream_http_client.request(HTTPClient.METHOD_POST, _stream_path, _stream_headers, _stream_body)
				if error != OK:
					_fail_streaming_response("Streaming request failed while sending: %s" % error)
					return
				response_started.emit()
		HTTPClient.STATUS_BODY:
			_read_streaming_body()
		HTTPClient.STATUS_DISCONNECTED:
			if _stream_request_sent:
				_finish_streaming_response()
			elif _stream_request_pending:
				_fail_streaming_response("Streaming request disconnected before sending.")


func cancel_streaming_chat_request() -> void:
	if _stream_http_client:
		_stream_http_client.close()
	_clear_streaming_state()


func is_streaming_response_active() -> bool:
	return _stream_http_client != null


func supports_streaming() -> bool:
	return _llm_provider != null and _llm_provider.supports_streaming


func supports_tools() -> bool:
	return _llm_provider != null and _llm_provider.supports_tools


func supports_structured_output() -> bool:
	return _llm_provider != null and _llm_provider.supports_structured_output


func supports_images() -> bool:
	return _llm_provider != null and _llm_provider.supports_images


func supports_reasoning_effort() -> bool:
	return _llm_provider != null and _llm_provider.supports_reasoning_effort


func supports_json_schema() -> bool:
	return _llm_provider != null and _llm_provider.supports_json_schema


func get_openai_style_reasoning_effort() -> String:
	if not supports_reasoning_effort():
		return ""
	match reasoning:
		"Disabled":
			return "none"
		"Minimal":
			return "minimal"
		"Low":
			return "low"
		"Medium":
			return "medium"
		"High":
			return "high"
		"Extra High":
			return "xhigh"
		_:
			return ""


func _start_streaming_post(url:String, headers, body:String) -> bool:
	var parsed_url := _parse_http_url(url)
	if parsed_url.is_empty():
		AIHubPlugin.print_err("Invalid streaming URL: %s" % url)
		return false

	_stream_http_client = HTTPClient.new()
	_stream_path = parsed_url.path
	_stream_headers = headers if (headers is PackedStringArray) else PackedStringArray(headers)
	_stream_body = body
	_stream_line_buffer = ""
	_stream_full_response = ""
	_stream_done = false
	_stream_request_pending = true
	_stream_request_sent = false

	var tls_options = TLSOptions.client() if parsed_url.scheme == "https" else null
	var error := _stream_http_client.connect_to_host(parsed_url.host, parsed_url.port, tls_options)
	if error != OK:
		_clear_streaming_state()
		AIHubPlugin.print_err("Failed to connect streaming request to %s: %s" % [url, error])
		return false
	return true


func _parse_http_url(url:String) -> Dictionary:
	# HTTPClient needs host, port, and path separately; HTTPRequest accepts the full URL.
	var scheme_end := url.find("://")
	if scheme_end == -1:
		return {}
	var scheme := url.substr(0, scheme_end).to_lower()
	if scheme != "http" and scheme != "https":
		return {}
	var remainder := url.substr(scheme_end + 3)
	var path_start := remainder.find("/")
	var host_port := remainder
	var path := "/"
	if path_start != -1:
		host_port = remainder.substr(0, path_start)
		path = remainder.substr(path_start)
	if host_port.is_empty():
		return {}

	var host := host_port
	var port := 443 if scheme == "https" else 80
	var port_start := host_port.rfind(":")
	if port_start > 0:
		host = host_port.substr(0, port_start)
		port = int(host_port.substr(port_start + 1))

	return {
		"scheme": scheme,
		"host": host,
		"port": port,
		"path": path
	}


func _read_streaming_body() -> void:
	while _stream_http_client != null and _stream_http_client.get_status() == HTTPClient.STATUS_BODY:
		var chunk := _stream_http_client.read_response_body_chunk()
		if chunk.is_empty():
			return
		_process_streaming_text(chunk.get_string_from_utf8())


func _process_streaming_text(text:String) -> void:
	_stream_line_buffer += text
	var lines := _stream_line_buffer.split("\n")
	# Keep the final partial line until the next chunk completes it.
	_stream_line_buffer = lines[lines.size() - 1]
	for i in range(lines.size() - 1):
		var line := lines[i].strip_edges()
		if line.is_empty():
			continue
		var parsed := _read_streaming_line(line)
		if parsed.has("error"):
			_fail_streaming_response(parsed.error)
			return
		var delta:String = parsed.get("delta", "")
		if not delta.is_empty():
			_stream_full_response += delta
			response_delta.emit(delta)
		if parsed.get("done", false):
			_finish_streaming_response()
			return


func _read_streaming_line(line:String) -> Dictionary:
	return { "error": "Provider does not support streaming response parsing." }


func _finish_streaming_response() -> void:
	if _stream_http_client == null:
		return
	# Some providers close the stream without a trailing newline, leaving one parseable event buffered.
	if not _stream_line_buffer.strip_edges().is_empty():
		var parsed := _read_streaming_line(_stream_line_buffer.strip_edges())
		if parsed.has("error"):
			_fail_streaming_response(parsed.error)
			return
		var delta:String = parsed.get("delta", "")
		if not delta.is_empty():
			_stream_full_response += delta
			response_delta.emit(delta)
	_stream_done = true
	var response := _msg_cleaner.clean(_stream_full_response)
	_clear_streaming_state()
	response_completed.emit(response)


func _fail_streaming_response(message:String) -> void:
	AIHubPlugin.print_err(message)
	_clear_streaming_state()
	response_failed.emit(message)


func _clear_streaming_state() -> void:
	if _stream_http_client:
		_stream_http_client.close()
	_stream_http_client = null
	_stream_request_pending = false
	_stream_request_sent = false
	_stream_path = ""
	_stream_body = ""
	_stream_line_buffer = ""
	_stream_full_response = ""
	_stream_done = false


func handle_thinking(thought:String) -> String:
	var think_target:AIHubPlugin.ThinkingTargets = ProjectSettings.get_setting(AIHubPlugin.PREF_REMOVE_THINK, AIHubPlugin.ThinkingTargets.Output)
	var think_content := "[Think start]:\n%s\n[Think end]" % thought
	match think_target:
		AIHubPlugin.ThinkingTargets.Chat:
			return _msg_cleaner.clean(think_content) + "\n\n"
		AIHubPlugin.ThinkingTargets.Output:
			print(think_content)
	return ""


## This is an optional method to override, only if you need to perform any logic
## after the URL and API key are loaded, e.g. generate custom headers
func _initialize() -> void:
	return


func _model_changed() -> void:
	return


func _override_temperature_changed() -> void:
	return


func _temperature_changed() -> void:
	return
