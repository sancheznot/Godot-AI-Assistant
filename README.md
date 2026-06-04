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

**AI-powered editor assistant for Godot 4** — chat with local or cloud models, edit scenes, run editor tools, and attach project context directly from the dock.

Created by **[sancheznotdev](https://github.com/sancheznot)** · MIT License

---

## Screenshots

**Editor dock** — chat, model/skills toolbar, and agent toggles.

<p align="center">
  <img src="docs/preview_dock.jpg" alt="Golem-AI dock in the Godot editor" width="520">
</p>

**Agent history & `@` context** — searchable sessions, pin/archive, and autocomplete for scenes, files, and skills.

<p align="center">
  <img src="docs/preview_autocomplete.jpg" alt="Golem-AI history panel and @ mention autocomplete" width="520">
</p>

---

## Features

- **Chat composer** with bubble UI, thinking blocks, and agent step progress
- **Multiple providers**: Ollama, LM Studio, OpenAI, Anthropic, Gemini, Cursor (local proxy / cloud)
- **Project context**: open scene, selection, `@file` mentions, configurable depth
- **Editor tools**: optional tool-calling loop inside the Godot editor
- **Skills system**: Markdown skills (`/skill`, dropdown, `@skill:id`)
- **Cursor-style UX**: `@` file/context autocomplete, `/` commands, agent history panel
- **Session history**: search, pin, archive, **New Agent** (`Ctrl+N`, `Alt` to replace)
- **Bilingual UI**: English / Spanish (Config → UI language)

## Requirements

- **Godot 4.2+** (tested on 4.6.x)
- At least one AI provider configured (e.g. [Ollama](https://ollama.com/) for local use)

## Installation

### Manual

1. Copy this folder into your project:

   ```
   your_project/addons/ai_assistant_plugin/
   ```

2. Open **Project → Project Settings → Plugins**
3. Enable **AI Assistant Plugin**
4. Open the **AI Assistant** dock tab in the editor

### From GitHub

```bash
git clone https://github.com/sancheznot/Godot-AI-Assistant.git addons/ai_assistant_plugin
```

Then enable the plugin in Project Settings.

## Quick start

1. Click **Config** in the dock toolbar
2. Enable a provider (e.g. Ollama) and set endpoint + model
3. Click **↻** to refresh the model list
4. Type a message and press **Enter**

### Composer shortcuts

| Input | Action |
|--------|--------|
| `@` | Attach context (scene, files, skills) |
| `/` | Commands (`/help`, `/clear`, `/skill`, …) |
| `Enter` | Send message |
| `Shift+Enter` | New line |
| `Ctrl+N` | New agent (session) |
| `Alt+click +` | Replace current agent (clear messages) |

## Configuration

Settings are stored in:

```
addons/ai_assistant_plugin/config/plugin_config.json
```

Key options:

- **Providers** — endpoints, API keys, default models
- **Context depth** — `basic` / `intermediate` / `full`
- **Agent loop** — multi-step verify & fix with editor tools
- **Skills path** — folder with `.md` skill files
- **UI language** — `auto`, `en`, `es`

Chat history is saved under `user://ai_assistant_plugin/chat_history.json`.

## Project structure

```
ai_assistant_plugin/
├── icon.png            # AssetLib icon (1024×1024)
├── docs/               # AssetLib previews
│   ├── preview_dock.jpg
│   └── preview_autocomplete.jpg
├── plugin.cfg
├── config/
├── harness/          # System prompt layers
├── locales/          # en.json, es.json
├── scenes/           # Dock UI
├── scripts/          # Plugin logic
└── skills/           # Built-in skills (.md)
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

**Golem-AI** — asistente de IA integrado en el editor de Godot 4 (el icono de Godot parece un golem, por eso el nombre).

**Autor:** [sancheznotdev](https://github.com/sancheznot) · Licencia MIT

Instalación: copia la carpeta a `addons/ai_assistant_plugin`, activa el plugin en Ajustes del proyecto y configura un proveedor (Ollama, OpenAI, etc.) desde **Config** en el dock.

Capturas: ver sección **Screenshots** arriba (dock del editor e historial con `@`).
