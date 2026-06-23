```
                           (((((((             (((((((
                        (((((((((((           (((((((((((
                        (((((((((((((       (((((((((((((
                        (((((((((((((((((((((((((((((((((
                        (((((((((((((((((((((((((((((((((
         (((((      (((((((((((((((((((((((((((((((((((((((((      (((((
       (((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((
     ((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((
    ((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((
      (((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((
        (((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((
         (((((((((((@@@@@@@(((((((((((((((((((((((((((@@@@@@@(((((((((((
         (((((((((@@@@,,,,,@@@(((((((((((((((((((((@@@,,,,,@@@@(((((((((
         ((((((((@@@,,,,,,,,,@@(((((((@@@@@(((((((@@,,,,,,,,,@@@((((((((
         ((((((((@@@,,,,,,,,,@@(((((((@@@@@(((((((@@,,,,,,,,,@@@((((((((
         (((((((((@@@,,,,,,,@@((((((((@@@@@((((((((@@,,,,,,,@@@(((((((((
         ((((((((((((@@@@@@(((((((((((@@@@@(((((((((((@@@@@@((((((((((((
         (((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((
         (((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((
         @@@@@@@@@@@@@((((((((((((@@@@@@@@@@@@@((((((((((((@@@@@@@@@@@@@
         ((((((((( @@@(((((((((((@@(((((((((((@@(((((((((((@@@ (((((((((
         (((((((((( @@((((((((((@@@(((((((((((@@@((((((((((@@ ((((((((((
          (((((((((((@@@@@@@@@@@@@@(((((((((((@@@@@@@@@@@@@@(((((((((((
           (((((((((((((((((((((((((((((((((((((((((((((((((((((((((((
              (((((((((((((((((((((((((((((((((((((((((((((((((((((
                 (((((((((((((((((((((((((((((((((((((((((((((((
                        (((((((((((((((((((((((((((((((((
```

```
   ______      __                     ___    ____
  / ____/___  / /__  ____ ___        /   |  /  _/
 / / __/ __ \/ / _ \/ __ `__ \______/ /| |  / /  
/ /_/ / /_/ / /  __/ / / / / /_____/ ___ |_/ /   
\____/\____/_/\___/_/ /_/ /_/     /_/  |_/___/   
```

> **Golem-AI** — el golem de Godot con inteligencia artificial.


# Golem-AI

<p align="center">
  <img src="icon.png" alt="Golem-AI logo" width="180">
</p>

**AI-powered editor assistant for Godot 4** — chat with local or cloud models, run a multi-step agent with editor tools, search the web, download assets, interact with other plugins, and manage sessions from the dock.

Created by **[sancheznotdev](https://github.com/sancheznot)** · MIT License · **v1.4.1**

---

## Screenshots

**Editor dock** — chat, model/skills toolbar, context/agent toggles, and vision/thinking options.

<p align="center">
  <img src="docs/preview_dock.jpg" alt="Golem-AI dock in the Godot editor" width="520">
</p>

**Agent history & `@` context** — searchable sessions, multi-select, pin/archive, and autocomplete for scenes, files, and skills.

<p align="center">
  <img src="docs/preview_autocomplete.jpg" alt="Golem-AI history panel and @ mention autocomplete" width="520">
</p>

**Models & providers** — one dropdown with local and cloud models grouped by provider (Ollama, LM Studio, MiniMax, Cursor, OpenRouter, Kimi, OpenAI, Anthropic, Gemini).

<p align="center">
  <img src="docs/preview_models.jpg" alt="Golem-AI model selector with Ollama, LM Studio, MiniMax and Cursor providers" width="520">
</p>

---

## Features

### Chat & composer

- **Bubble UI** with collapsible thinking blocks, tool calls, tool results, and code blocks
- **Copy button** on assistant messages and collapsible code blocks
- **Attachments**: text files (`.gd`, `.tscn`, `.md`, …) and **images** (PNG, JPG, WebP, …)
- **`@` mentions** and **`/` commands** with autocomplete
- **Vision** and **Think** toggles — auto-enabled only when the selected model supports them (preferences persist between sessions)

### Providers & models

| Provider | Notes |
|----------|--------|
| **Ollama** | Local models |
| **LM Studio** | Local server; reads `capabilities.vision` from native API |
| **OpenRouter** | Many cloud models, pay-as-you-go |
| **Kimi** | Moonshot AI |
| **MiniMax** | M3 = visión + thinking; M2.x = solo texto + thinking (sin imágenes) |
| **OpenAI** | Cloud API |
| **Anthropic** | Cloud API |
| **Gemini** | Google API |
| **Cursor** | Local OpenAI-compatible proxy or cloud agents |

- Model dropdown grouped by **provider separators**
- **↻ Refresh** loads models from each enabled provider
- Capability detection (`model_capabilities.gd`) + provider metadata (LM Studio / OpenRouter) to avoid invalid vision/thinking options

#### MiniMax models (official API)

Source: [MiniMax models](https://platform.minimax.io/docs/guides/models-intro) · [Anthropic-compatible API](https://platform.minimax.io/docs/api-reference/text-anthropic-api)

| Model | Vision (images) | Thinking |
|-------|-----------------|----------|
| **MiniMax-M3** | Yes (image + video) | Yes (toggle `disabled` / `adaptive`) |
| MiniMax-M2.7 / highspeed | No | Yes (always on at API) |
| MiniMax-M2.5 / highspeed | No | Yes (always on at API) |
| MiniMax-M2.1 / highspeed | No | Yes (always on at API) |
| MiniMax-M2 | No | Yes (always on at API) |
| M2-her | No | No (dialogue / roleplay) |

Only **MiniMax-M3** accepts `image_url` / `video_url` in chat. All other MiniMax chat models are **text + tools only**.

### Agent & tools

- **Editor tools** — optional tool-calling loop in the Godot editor (scenes, scripts, nodes, TileMap, spatial mapping)
- **Agent loop** — multi-step verify & fix with compact tool results and smarter step efficiency
- **Minimal bootstrap** — lightweight first prompt; fetch project context on demand via tools
- **Internet & assets**
  - **`web_search`** — search the web via **Serper** ([serper.dev](https://serper.dev)) or **Brave Search API** (`mode`: `web` or `images` for textures)
  - **`download_file`** — download HTTPS files (textures, `.glb`, audio) straight into `res://`
  - Typical flow: `web_search` → pick a URL → `download_file` → place in scene
- **External plugin support** — `list_plugins`, `inspect_plugin`, and `call_node_method` work with **any** installed plugin (Terrain3D, DialogueManager, etc.)
- **Skills system** — Markdown skills (`/skill`, dropdown, `@skill:id`)
- **Project context** — open scene, selection, `@file` mentions, hybrid project index + docs search

### Session history

- **Search**, **pin**, **archive**, and **New Agent** (`Ctrl+N`; `Alt` replaces current session)
- **Multi-select** — checkboxes per chat, **Select all**, bulk **Archive** / **Restore** / **Delete**
- **Delete confirmation** — single chat or bulk; clears selection after archive/restore/delete
- More menu (⋮): clear messages, delete active chat, open config

### Localization

- **English / Spanish** UI (Config → UI language: `auto`, `en`, `es`)

---

## Requirements

- **Godot 4.2+** (tested on 4.6.x)
- At least one AI provider configured (e.g. [Ollama](https://ollama.com/) or [LM Studio](https://lmstudio.ai/) for local use)

## Installation

### From the Godot Asset Library

Search for **Golem-AI**, install, then enable it in **Project → Project Settings → Plugins**.
It installs to `res://addons/ai_assistant_plugin/`.

### Manual

Copy the `addons/ai_assistant_plugin/` folder from this repo into your project's `addons/`, then enable the plugin in Project Settings.

### From GitHub

```bash
git clone https://github.com/sancheznot/Godot-AI-Assistant.git
cp -r Godot-AI-Assistant/addons/ai_assistant_plugin your_project/addons/
```

Then enable the plugin in Project Settings and open the **Golem-AI** dock tab.

## Quick start

1. Click **Config** in the dock toolbar
2. Enable a provider (e.g. Ollama or LM Studio) and set endpoint + model
3. Click **↻** to refresh the model list
4. Choose **Context**, **Tools**, **Agent**, **Think**, and **Vision** as needed (greyed-out toggles = model does not support that feature)
5. Type a message and press **Enter**

### Attachments

| Control | Action |
|---------|--------|
| **📎** | Attach a text file (content injected into context) |
| **🖼** | Attach an image (requires **Vision** on + vision-capable model) |

You can send attachments without text; the plugin uses a default analysis prompt.

### Composer shortcuts

| Input | Action |
|--------|--------|
| `@` | Attach context (scene, files, skills) |
| `/` | Commands (`/help`, `/clear`, `/history`, `/skill`, …) |
| `Enter` | Send message |
| `Shift+Enter` | New line |
| `Ctrl+N` | New agent (session) |
| `Alt+click` **+** | Replace current agent (clear messages) |

### History panel

| Control | Action |
|---------|--------|
| Checkbox on row | Select chat for bulk actions |
| **All** | Select / deselect visible chats |
| **Archive** / **Restore** | Bulk archive or unarchive selection |
| **Delete** | Bulk delete with confirmation |
| **⋯** / **🗑** | Per-chat menu or delete |

---

## Configuration

Copy the example config on first setup:

```
cp addons/ai_assistant_plugin/config/plugin_config.example.json \
   addons/ai_assistant_plugin/config/plugin_config.json
```

Settings (endpoints, models, toggles) are stored in `config/plugin_config.json`. **API keys are never written there.**

### API keys & secrets

| Storage | Path / variable | Notes |
|--------|------------------|--------|
| **Encrypted file** | `user://ai_assistant_plugin/secrets.enc` | Default. Keys from the Config UI are saved here via Godot's encrypted file API. |
| **Passphrase** | `GOLEM_AI_SECRETS_PASSPHRASE` | Optional. Custom passphrase for `secrets.enc`. Default: machine id (per device). |
| **Environment** | `GOLEM_AI_API_KEY_<PROVIDER>` | Optional override per provider, e.g. `GOLEM_AI_API_KEY_OPENAI`, `GOLEM_AI_API_KEY_MINIMAX`. Takes priority over the encrypted store. |
| **Web search** | `GOLEM_AI_API_KEY_SERPER`, `GOLEM_AI_API_KEY_BRAVE` | Optional keys for the `web_search` tool (Config → Settings). |

On first launch after updating, keys still present in an old `plugin_config.json` are **migrated automatically** to `secrets.enc` and removed from the JSON.

> **Do not commit API keys.** `plugin_config.json` is gitignored; use `plugin_config.example.json` as the template. If keys were ever pushed to git, **rotate them** in each provider's dashboard.

Key options in `plugin_config.json`:

- **Providers** — endpoints, API keys, default models
- **Context depth** — `basic` / `intermediate` / `full`
- **Agent loop** — multi-step verify & fix with editor tools
- **Web search** — Serper or Brave API (`enable_web_search`, provider + API key in Config → Settings)
- **enable_vision** / **enable_thinking** — persisted preferences (respect model capabilities)
- **Skills path** — folder with `.md` skill files
- **UI language** — `auto`, `en`, `es`

Chat history is saved under `user://ai_assistant_plugin/chat_history.json`.

## Project structure

```
Godot-AI-Assistant/             # repo root (for GitHub / Asset Library)
├── README.md
├── LICENSE
├── icon.png
├── docs/                       # AssetLib previews + store copy
│   ├── preview_dock.jpg
│   ├── preview_autocomplete.jpg
│   ├── preview_models.jpg
│   └── asset_library_description.txt
└── addons/
    └── ai_assistant_plugin/    # the plugin (installs here in your project)
        ├── plugin.cfg
        ├── config/
        ├── harness/            # System prompt layers
        ├── locales/            # en.json, es.json
        ├── scenes/             # Dock UI
        ├── scripts/
        │   ├── ui_plugin.gd
        │   ├── ai_model_handler.gd
        │   └── …
        └── skills/             # Built-in skills (.md)
```

## Contributing

Issues and PRs welcome on GitHub. Please keep changes focused and match existing code style.

## License

MIT — see [LICENSE](LICENSE).

Copyright (c) 2026 **sancheznotdev**

## Author

**sancheznotdev**  
GitHub: [@sancheznot](https://github.com/sancheznot)

If you use this plugin in a project or video, a mention or link is appreciated — not required by the license.

---

## Español

**Golem-AI** — asistente de IA integrado en el editor de Godot 4.

**Autor:** [sancheznotdev](https://github.com/sancheznot) · Licencia MIT

### Novedades recientes (v1.4.x)

- **Búsqueda web**: tool `web_search` con API de **Serper** o **Brave** (modo `web` o `images` para texturas)
- **Descarga de assets**: tool `download_file` — URLs HTTPS → `res://` (texturas, modelos, audio)
- **Plugins externos**: `list_plugins`, `inspect_plugin`, `call_node_method` para cualquier addon (Terrain3D, etc.)
- **Agente más eficiente**: bootstrap mínimo, menos steps desperdiciados, respuestas informacionales en 1 paso
- **Adjuntos**: archivos de texto e imágenes en el compositor (📎 / 🖼)
- **Proveedores**: Ollama, LM Studio, OpenRouter, Kimi, MiniMax, OpenAI, Anthropic, Gemini, Cursor
- **Historial**: selección múltiple, archivar/restaurar/eliminar en lote, `@` autocomplete, UI EN/ES

Instalación: copia la carpeta a `addons/ai_assistant_plugin`, activa el plugin en Ajustes del proyecto y configura un proveedor desde **Config** en el dock.

Capturas: ver sección **Screenshots** arriba (dock, historial con `@`, selector de modelos).
