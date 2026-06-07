# AI Assistant Update Findings

This document captures update opportunities found during a repo review of the Godot AI Assistant Hub addon. It is intended to be iterated on as a roadmap, issue list, or implementation checklist.

## Context

The addon currently works well as a prompt-template chat interface inside Godot. Its core architecture is provider-specific HTTP requests, simple `{ role, content }` conversation history, quick prompts, and direct code-editor insertion.

Recent AI assistant patterns have moved toward streaming output, structured responses, tool/function calling, multimodal context, and project-aware agent workflows. The highest-value updates below focus on bringing those capabilities into this addon without losing its provider-agnostic design.

## Priority Checklist

### 1. Add Streaming Responses

**Status:** Proposed

Current behavior waits for a full HTTP response before showing the assistant answer.

Relevant files:

- `addons/ai_assistant_hub/llm_apis/llm_interface.gd`
- `addons/ai_assistant_hub/ai_chat.gd`
- `addons/ai_assistant_hub/llm_apis/ollama_api.gd`
- Provider API scripts under `addons/ai_assistant_hub/llm_apis/`

Why update:

- Modern assistant UX expects token-by-token feedback.
- Streaming enables visible progress for long code answers.
- Streaming is also the basis for showing tool calls, reasoning status, or partial structured output.

Possible implementation:

- Add streaming capability flags per provider.
- Add stream lifecycle signals to `LLMInterface`, such as `response_started`, `response_delta`, `response_completed`, and `response_failed`.
- Keep non-streaming as a fallback for providers that do not support it.
- Start with Ollama because the current request already sets `"stream": false`.

Acceptance criteria:

- Chat output updates incrementally.
- Cancel still works.
- Saved chat stores only the final assistant message.
- Non-streaming providers continue working.

### 2. Replace Fenced-Code Extraction With Structured Edits

**Status:** Proposed

Current code-writing quick prompts depend on the model returning fenced `gdscript` blocks.

Relevant files:

- `addons/ai_assistant_hub/ai_answer_handler.gd`
- `addons/ai_assistant_hub/tools/assistant_tool_code_writer.gd`
- `addons/ai_assistant_hub/quick_prompts/ai_quick_prompt_resource.gd`
- `examples/quick_prompts/ai_qp_write_code.tres`

Why update:

- Markdown code fences are brittle.
- Models can include explanations, multiple code blocks, or omit language tags.
- Structured output would make code editor writes safer and more predictable.

Possible implementation:

- Add a structured response mode for quick prompts.
- Define a JSON schema or local equivalent for operations:
  - `replace_selection`
  - `insert_before_selection`
  - `insert_after_selection`
  - `chat_only`
- Validate the response before applying editor changes.
- Show an error instead of writing if validation fails.

Acceptance criteria:

- Code write prompts can apply edits without parsing Markdown fences.
- Invalid structured responses do not modify the editor.
- Existing quick prompts remain backward compatible.

### 3. Add Diff Review Before Applying Code Changes

**Status:** Proposed

Current code edits are written directly into the editor after matching the previous selection.

Relevant files:

- `addons/ai_assistant_hub/tools/assistant_tool_code_writer.gd`
- `addons/ai_assistant_hub/tools/assistant_tool_selection.gd`
- `addons/ai_assistant_hub/ai_answer_handler.gd`

Why update:

- Larger AI-generated edits need user review.
- A diff view reduces accidental code loss.
- It prepares the addon for multi-file or project-level edits.

Possible implementation:

- Add an optional diff confirmation dialog.
- Show original text and proposed replacement.
- Support accept, reject, and copy.
- Store enough state to rollback a just-applied edit.

Acceptance criteria:

- User can inspect AI-generated changes before applying.
- Direct-write behavior can remain available as a preference.
- Rejected edits do not alter the code editor.

### 4. Add Tool/Function Calling Abstraction

**Status:** Proposed

The addon has local quick prompt tools, but the model cannot currently request tools during a conversation.

Relevant files:

- `addons/ai_assistant_hub/llm_apis/llm_interface.gd`
- `addons/ai_assistant_hub/ai_conversation.gd`
- `addons/ai_assistant_hub/ai_chat.gd`
- `addons/ai_assistant_hub/tools/`

Why update:

- Modern assistant APIs support model-selected tool calls.
- Godot editor integration becomes much more useful when the assistant can ask for context as needed.
- Tool calls reduce huge prompt stuffing.

Possible initial tools:

- `get_selected_text`
- `get_current_script_path`
- `read_current_script`
- `list_project_files`
- `search_project`
- `read_file`
- `get_open_scene_path`
- `get_selected_node_info`
- `apply_code_edit`

Possible implementation:

- Add a provider-neutral internal representation for tool definitions and tool calls.
- Add tool-call messages to `AIConversation`.
- Implement a tool loop in `AIChat`: send request, receive tool call, execute local tool, send tool result, receive final answer.
- Start with OpenAI-compatible providers and Gemini-compatible providers separately because their request/response shapes differ.

Acceptance criteria:

- The assistant can request at least one local tool and use its result in the final answer.
- Tool execution is logged in debug mode.
- Tools that modify files/editor state require explicit user confirmation.

### 5. Add Project Context and Search

**Status:** Implemented initial pass

The assistant currently sees only explicit chat text and selected code inserted through `{CODE}`.

Relevant files:

- `addons/ai_assistant_hub/ai_chat.gd`
- `addons/ai_assistant_hub/tools/`

Why update:

- Real Godot work often requires context across scripts, scenes, resources, and project settings.
- Search/read tools make the assistant more accurate without sending the whole project.

Possible implementation:

- Add project file discovery for relevant extensions:
  - `.gd`
  - `.tscn`
  - `.tres`
  - `.cs`
  - `.shader`
  - `project.godot`
- Add ignore rules for `.godot`, imports, binaries, and large files.
- Start with simple lexical search before adding embeddings or vector indexes.
- Expose project search through model-callable tools.

Implemented initial pass:

- Added `AssistantToolProjectContext` with project file listing, lexical search, and safe file reads.
- Added filtering for relevant text project files, ignored directories, `.import` files, and large files.
- Added a `plugins/ai_assistant_hub/preferences/project_context` project setting so project context can be disabled.
- Added a bounded provider-neutral agent loop in `AIChat` using `<tool_call>{...}</tool_call>` messages for project search/read/list requests.

Acceptance criteria:

- Assistant can search project files for a symbol or text query.
- Assistant can read selected files on demand.
- Large/binary files are skipped.
- User can disable project context features.

### 6. Support Multimodal Context

**Status:** Proposed

The conversation model and provider requests are text-only.

Relevant files:

- `addons/ai_assistant_hub/ai_conversation.gd`
- `addons/ai_assistant_hub/llm_apis/gemini_api.gd`
- Provider API scripts under `addons/ai_assistant_hub/llm_apis/`

Why update:

- Current models can use screenshots, images, and other file inputs.
- Godot users often need help with visual UI/layout/gameplay problems.

Possible inputs:

- Editor viewport screenshot.
- Running game screenshot.
- Selected texture/image resource.
- Scene tree metadata.
- Inspector properties for selected node.

Possible implementation:

- Extend conversation entries beyond plain string `content`.
- Add provider capability flags for image input.
- Implement Gemini image parts first, then other providers as supported.

Acceptance criteria:

- User can attach or capture an image and ask about it.
- Providers without image support hide or disable image controls.
- Saved chat handles multimodal entries gracefully.

### 7. Normalize Provider Capabilities

**Status:** Implemented initial pass

Provider resources currently define URLs, role names, keys, and reasoning levels, but not feature support.

Relevant files:

- `addons/ai_assistant_hub/llm_providers/llm_provider_resource.gd`
- Provider `.tres` files under `addons/ai_assistant_hub/llm_providers/`
- Provider API scripts under `addons/ai_assistant_hub/llm_apis/`

Why update:

- Not every provider supports streaming, tools, structured output, images, or reasoning controls.
- The UI should expose only supported features.

Possible capability fields:

- `supports_streaming`
- `supports_tools`
- `supports_structured_output`
- `supports_images`
- `supports_reasoning_effort`
- `supports_json_schema`

Implemented initial pass:

- Added exported provider capability flags with safe default `false` values.
- Added `LLMInterface` helper methods for checking provider capabilities.
- Annotated bundled provider resources with known API feature support.
- Gated the reasoning UI and request fields through `supports_reasoning_effort`.

Acceptance criteria:

- UI uses provider capabilities to show/hide controls.
- Unsupported features fail early with clear messages.
- Existing provider resources still load with safe defaults.

### 8. Add Native OpenAI Responses API Provider

**Status:** Proposed

The addon has OpenRouter and OpenAI-compatible providers, but no native OpenAI provider.

Relevant files:

- `addons/ai_assistant_hub/llm_apis/`
- `addons/ai_assistant_hub/llm_providers/`

Why update:

- OpenAI's current assistant-building direction is the Responses API.
- The Assistants API is deprecated and scheduled to shut down on August 26, 2026.
- A native Responses provider would expose modern tools, structured outputs, file search, and multimodal inputs more directly than a generic chat-completions endpoint.

Possible implementation:

- Add `openai_responses_api.gd`.
- Add `openai_responses.tres`.
- Support basic text first.
- Add streaming and structured output next.
- Add tool calling once the internal tool abstraction exists.

Acceptance criteria:

- Users can configure an OpenAI API key.
- Users can list or manually enter compatible models.
- Basic chat works through `/v1/responses`.
- Chat Completions providers remain unaffected.

### 9. Improve Reasoning Controls Across Providers

**Status:** Implemented initial pass

Reasoning controls currently exist mainly for Ollama.

Relevant files:

- `addons/ai_assistant_hub/llm_apis/ollama_api.gd`
- `addons/ai_assistant_hub/llm_apis/llm_interface.gd`
- `addons/ai_assistant_hub/llm_apis/openai_compatible_api.gd`
- `addons/ai_assistant_hub/llm_apis/xai_api.gd`
- `addons/ai_assistant_hub/llm_providers/ollama.tres`
- `addons/ai_assistant_hub/llm_providers/openai_compatible.tres`
- `addons/ai_assistant_hub/llm_providers/xai.tres`
- `addons/ai_assistant_hub/ai_chat.gd`

Why update:

- Recent reasoning models often expose effort or budget controls.
- Provider-specific request fields differ, so this should be normalized through capabilities and provider mappings.

Possible implementation:

- Keep user-facing reasoning labels provider-neutral where possible.
- Let each provider translate the selected level into its own request body.
- Handle unsupported reasoning values with clear errors or disabled UI.

Implemented initial pass:

- Kept Ollama's existing mapping for `think` values.
- Added a shared OpenAI-style `reasoning_effort` mapper for providers that use that request field.
- Added OpenAI-compatible reasoning levels and mapped them to `reasoning_effort`.
- Added xAI reasoning levels and mapped them to `reasoning_effort`.
- Left unsupported providers at `Default` only so the reasoning UI remains hidden for them.

Acceptance criteria:

- At least two providers support reasoning controls.
- Unsupported models/providers do not show misleading controls.

### 10. Modernize Example Assistants and Prompts

**Status:** Proposed

Example assistants use older model defaults and prompt patterns.

Relevant files:

- `examples/assistants/`
- `examples/quick_prompts/`
- `README.md`

Why update:

- Model recommendations age quickly.
- Examples should demonstrate the safest interaction patterns the addon supports.

Possible implementation:

- Avoid hardcoding specific "best" model claims.
- Add examples for structured edit prompts after structured output support lands.
- Add examples for project-search/tool-based workflows after tool calling lands.
- Keep a note that local coding model recommendations should be checked regularly.

Acceptance criteria:

- Example resources reflect current addon capabilities.
- README distinguishes stable workflow advice from fast-changing model suggestions.

## External API Notes

- OpenAI's current recommended assistant-building interface is the Responses API.
- OpenAI Assistants API is deprecated and scheduled to shut down on August 26, 2026.
- OpenAI supports tool/function calling, structured outputs, streaming events, file search, and multimodal inputs through newer APIs.
- Gemini supports function calling and multimodal content, with provider-specific request/response formatting.
- Ollama supports local chat, streaming, and model-dependent thinking/reasoning options.

## Suggested Implementation Order

1. Add provider capability flags with safe defaults.
2. Add streaming for Ollama and one OpenAI-compatible provider.
3. Add structured quick prompt responses for code edits.
4. Add diff review before editor writes.
5. Add local project search/read tools.
6. Add a provider-neutral tool-call loop.
7. Add native OpenAI Responses API provider.
8. Add multimodal context.
9. Refresh examples and README around the new workflows.
