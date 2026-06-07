**Godot AI Assistant Hub**
<img src="https://github.com/FlamxGames/godot-ai-assistant-hub/blob/main/logo.png" width="50px">
==========================
**Latest version: 1.8.3**
<sub>([What's new?](#whats-new-in-the-latest-version))</sub>
<sub>([Upgrading to a newer version](#upgrading-to-a-newer-version))</sub>

A Flexible Godot Plugin for AI Assistants
-----------------------------------------

Embed AI assistants in Godot with the ability to read and write code in Godot's Code Editor.

This plugin does not run LLM models directly, but acts as an interface between Godot and an LLM provider. There are plenty of options to run LLMs locally or call them remotely. Thanks to the community this tool supports the following:

* [Ollama](https://ollama.com/)*
* OpenAI
* Claude
* Google Gemini
* OpenAI-compatible endpoints
* OpenRouter

**Ollama** is officially supported, while the other LLM providers are maintained by community contributions. Older provider resources may still exist for backward compatibility, but the main provider picker now focuses on this shorter modern set. The core chat, quick prompt, and code editor workflows are shared across providers, but each provider and model may differ in speed, context length, reasoning behavior, and output quality.

If you use other LLM tools not listed here, you could easily extend this plugin to work with them if they have a REST API. This plugin was designed to be API agnostic. See the videos for more information on this.

For services that expose the OpenAI Chat Completions shape, select **OpenAI Compatible** and configure the base URL without the endpoint suffix, for example `http://localhost:1234/v1`. The addon will call `/models` and `/chat/completions` from that base URL. The API key is optional for this provider: leave it blank for local servers that do not require authentication, or set it for remote endpoints that expect a bearer token. If the provider option does not appear after updating the addon files, reload the project or disable and re-enable the plugin so Godot rebuilds the provider list.

Tutorial Playlist
-----------------------------------------

[Click here to go to the tutorial playlist](https://www.youtube.com/playlist?list=PL2PLLTlAI2ogvgcY8mG-QsMI1dDUDPyF2)

First Video 👇

[![YouTube Video](http://i.ytimg.com/vi/3PDKJYp-upU/hqdefault.jpg)](https://www.youtube.com/watch?v=3PDKJYp-upU&list=PL2PLLTlAI2ogvgcY8mG-QsMI1dDUDPyF2&index=1)

**Key Features**
---------------

#### ✍️ Assistants can write code or documentation directly in Godot's Code Editor.
#### 👀 Assistants can read the code you highlight for quick interactions.
#### 🪄 Save reusable prompts to ask your assistant to act with a single button.
#### 🤖 Create your own assistant types and quick prompts without coding.
#### 💬 Have multiple chat sessions with different types of assistants simultaneously.
#### ⏪ Edit the conversation history in case your assistant gets confused by some of your prompts.
#### 💻 Call LLMs locally or remotely.

**System Requirements**
-----------------------

The system requirements to run local LLMs depend on the models you use and the speed you expect. Of course, if you use the plugin to run remote models (OpenAI, Claude, Gemini, etc.), then you don't need to worry about this (just about the bills).

**Tested in versions**

* Godot 4.3 to 4.6

Tested in stable versions only.

**Getting Started**
--------------------
This section assumes you have installed [Ollama](https://ollama.com/) and installed at least one model. If you are not sure about the models to download, read section "Not sure what models to use?".

### ▶️ If you are feeling like not reading much
Just install it and follow the hints it gives you in Godot itself.

### ▶️ If you want to understand it better
There are 2 main concepts for this addon, familiarize yourself with them, both are Godot [Resources](https://docs.godotengine.org/en/stable/tutorials/scripting/resources.html):

#### A) AI assistant type (AIAssistantResource). 🤖
This is the setup for an assistant, it describes what the assistant does, what LLM model to use, and what Quick Prompts it can use.

Think of it as a template for creating assistants. For example, you can have an assistant that helps with coding, and one that helps with writing. In that case, you would have 2 assistant types, and you can summon as many coders or writers you need.

#### B) Quick Prompt (AIQuickPromptResource). 🪄
Allows to send a prompt in the chat by clicking a button instead of writing it every time. It adds the ability to insert the assistant's answer in the Godot's Code Editor.
The following keywords are used to allow the prompt to pull data from the Code Editor or from the chat prompt.
* Use `{CODE}` to insert the code currently selected in the editor.
* Use `{CHAT}` to include the current content of the text prompt.

**Note**: When a Quick Prompt writes directly to the Code Editor, the plugin can either use the default fenced Markdown parser or a structured JSON edit response. The structured mode is safer for code-writing prompts because the addon validates the operation before touching the editor. In that mode, ask for exactly one JSON object:

    {
      "operation": "replace_selection",
      "content": "updated code"
    }

Supported operations are `replace_selection`, `insert_before_selection`, `insert_after_selection`, and `chat_only`.

For backward-compatible editor-writing prompts that use the default fenced Markdown parser, give explicit instructions in the assistant description or quick prompt, for example:

    Return code in exactly one GDScript fenced block, for example:
    ```gdscript
    var x:String = "abc"
    ```

Stable prompt patterns matter more than model-specific wording here: ask for focused changes, one structured object or fenced block for code that should be inserted, and chat-only explanations for reviews or debugging.

When project context is enabled, chat assistants can also use project tools to list, search, read, create, and edit allowed project text files under `res://`. File writes are limited to the same project file types used by project context (`.gd`, `.tscn`, `.tres`, `.cs`, `.shader`, and `project.godot`) and capped at 256 KB per file. Existing files are edited with exact-text replacement or explicit full-file overwrite.

By default, Quick Prompts that write to the Code Editor show a review dialog before applying AI-generated code. Disable **Project Settings > General > Plugins > AI Assistant Hub > Preferences > Confirm Code Edits** to restore direct writes.

## Setup steps
In general this is what you need to do:

0. If running your LLMs locally, install Ollama or some other LLM supported and download at least one model.
1. Download this addon from [here](https://github.com/FlamxGames/godot-ai-assistant-hub/archive/refs/heads/main.zip), unzip it, and copy the folder ai_assistant_hub into your addons folder `res://addons/ai_assistant_hub/`. (You may see errors, those should go away after next step.)
2. Reload your project: **Project > Reload Current Project** (this will reload the whole project, so make sure to save before doing this).
3. Enable the plugin in your project settings (**Project > Project Settings... > Plugins**), you should see a new tab `AI Hub` in the bottom panel.
4. Select an LLM provider, by default Ollama is selected.
5. You should see a list of models you have installed. Click one and use the "New assistant type" button.
6. Fill up the data for your assistant.
7. After saving, you should see a new button for your assistant type.
8. Your assistant type will open in the Inspector panel, there you can optionally configure an icon and Quick Prompts for your assistant type, the later would allow it to interact with the code editor.
9. Click the assistant type button to start a chat with a new assistant of this type.

### Configuring Quick Prompts and icon ###
1. Right-click the button for your assistant type, there you can select Edit or Delete.
2. Select Edit.
3. In the *Type Icon* property select an image to display in the assistant button. (The addon has some icons under `res://addons/ai_assistant_hub/graphics/icons`, you can use those by using a *New AtlasTexture* in this property, loading the icons file in the *Atlas* property of the AtlasTexture, then clicking *Edit Region* to select the icon you want.)
4. If you click the property *Quick Prompts* you will see an empty array, click *Add Element*, then in the empty slot select *New AIQuickPromptResource*.
5. Click the new resource to open its properties in the editor.
6. You will see a few properties:
    * **Action Name**. This name will be displayed in the Quick Prompt button.
    * **Action Prompt**. This is what this prompt will send to the chat. There are two keywords:
        * Use `{CODE}` to insert the code currently selected in the editor.
        * Use `{CHAT}` to include the current content of the text prompt.
    * **Icon**. The icon to display in the Quick Prompt button.
    * **Response Target**. Where should the bot's answer go in Godot's editor.
    * **Code Placement**. Only relevant when the Response Target is the Code Editor.
    * **Format Response as Comment**. Only relevant when the Response Target is the Code Editor. Useful when the prompt is used to create inline code documentation.
7. Once done start a new chat to see the Quick Prompt.

Experiment and build the right type of assistants for your workflow.

### Not sure what models to use?

Model recommendations change quickly, so this README avoids hardcoding a "best" model list. The example assistant resources intentionally leave the model field blank; use the model picker to select a model that is currently available in your provider.

For local coding assistants, check current recommendations regularly and include your hardware in the search. For example: “best local coding LLM for Godot GDScript with 8 GB VRAM”. Then test the candidates with the actual workflows you care about: code review, small edits, debugging, and documentation.

The rule of thumb I follow is to check the output speed by chatting with it. If it is slow, the model is not being loaded onto my GPU; it is using RAM/CPU. You probably only want to do that if the results the model produces are remarkably better, or simply if you don’t have a GPU capable of loading any models.

The stable part of the workflow is provider-agnostic: select a model that responds quickly enough, handles your project context well, and reliably follows fenced-code instructions when you use Quick Prompts that write into the Code Editor.

**What's new in the latest version**
-----------------------
**1.8.3**
* Added reasoning level support for Ollama (help wanted to add it to other LLM Providers!)
* "Make floating" option (by right-click to the plugin tab) is now enabled in Godot 4.6 without need to do any manual code changes (closes #64).
* Thinking content is now obtained when it comes separate to the agent response and displayed accordingly to the user settings (Project Settings > General > Plugins > AI Assistant Hub > Thinking Target).
* Reworked error/debugging handling, a new option exists now to ease debugging (Project Settings > General > Plugins > AI Assistant Hub > Debug Mode). This supports logging to a log file that skips keys automatically.
* System message is no longer lost in saved chats (closes #75).
* Added anonymous (counting) usage stats to understand better what versions and APIs most people use.

**1.8.1**
* When you select an assistant tab, the chat text box is now focused automatically.
* Added commented code in ai_hub_plugin.gd under _enter_tree() and _exit_tree(), in Godot 4.6 you can uncomment this to enable making the plugin screen floating by right-clicking its tab.
* Fixed bugs in code placement when replacing the selection. Also improved code placement in general removing extra lines around it.
* Fixed bug that caused freeze when editing an assistant resource in Linux.

**1.8.0**
* xAI API support

[Full version history](versions.md)

**Upgrading to a newer version**
-----------------------
If you had the plugin installed and want to upgrade to the latest version, follow these steps:

***Download > Disable current > Install new > Reload project > Enable***

1. Download the latest version [here](https://github.com/FlamxGames/godot-ai-assistant-hub/archive/refs/heads/main.zip) and unzip it.
2. **Disable** the plugin from **Project > Project Settings... > Plugins**.
3. Pull the **ai_assistant_hub** folder from the new version into your addons folder (don't delete the previous one so you don't lose your assistants). You may see errors in Godot's output tab, that is fine.
4. Ensure Godot loads into memory the new version: **Project > Reload Current Project** (this will reload the whole project, so make sure to save before doing this).
5. **Enable** the plugin. You should not see any errors in the output tab, but in some cases you may see some message confirming the migration of old settings.

**Leave a contribution**
-----------------------
If you like this project check the following page for ideas about how to support it: https://github.com/FlamxGames/godot-ai-assistant-hub/blob/main/support.md

**Who is developing this**
----------
Hi, I'm Forest, I created this addon for my personal use and decided to share it, hope you find it useful.

I'm a solo game developer that sometimes ends up building game dev tools. This a hobby project I may keep improving from time to time. Right now I'm planning to improve it on a need-basis, so there is no formal roadmap. However I welcome ideas in the Discussions section.

**License**
----------
This project is licensed under the MIT license.
