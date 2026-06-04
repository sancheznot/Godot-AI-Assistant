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
     /$$   /$$                 /$$        /$$                               /$$           /$$                 /$$                             /$$     /$$
    | $$  | $$                | $$       | $$                              | $$          | $$                | $$                            | $$    |__/
    | $$  | $$  /$$$$$$   /$$$$$$$  /$$$$$$ | $$$$$$$   /$$$$$$   /$$$$$$  | $$ /$$$$$$  | $$$$$$$   /$$$$$$  | $$        /$$$$$$   /$$$$$$ | $$     /$$  /$$$$$$$
    | $$$$$$$$ /$$__  $$ /$$__  $$ /$$__  $$| $$__  $$ /$$__  $$ /$$__  $$ | $$|_  $$_/  | $$__  $$ /$$__  $$ | $$       /$$__  $$ /$$__  $$| $$    | $$ /$$_____/
    | $$__  $$| $$$$$$$$| $$  | $$| $$$$$$$$| $$  \ $$| $$$$$$$$| $$  \__/ | $$  | $$    | $$  \ $$| $$$$$$$$ | $$      | $$  \ $$| $$  \__/| $$    | $$|  $$$$$$$
    | $$  | $$| $$_____/| $$  | $$| $$_____/| $$  | $$| $$_____/| $$       | $$  | $$ /$$| $$  | $$| $$_____/ | $$      | $$  | $$| $$      | $$    | $$ \____  $$
    | $$  | $$|  $$$$$$$|  $$$$$$$|  $$$$$$$| $$  | $$|  $$$$$$$| $$       | $$  |  $$$$/| $$  | $$|  $$$$$$$ | $$      |  $$$$$$/| $$      | $$ /$$| $$ /$$$$$$$/
    |__/  |__/ \_______/ \_______/ \_______/|__/  |__/ \_______/|__/       |__/   \___/  |__/  |__/ \_______/ |__/       \______/ |__/      |__/|__/|__/|_______/
```

# Godot AI Assistant

**AI-powered editor assistant for Godot 4** — chat with local or cloud models, edit scenes, run editor tools, and attach project context directly from the dock.

Created by **[sancheznotdev](https://github.com/sancheznot)** · MIT License

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
├── plugin.cfg
├── config/
├── harness/          # System prompt layers
├── locales/          # en.json, es.json
├── scenes/           # Dock UI
├── scripts/          # Plugin logic
└── skills/           # Built-in skills (.md)
```

## Publish on the Godot Asset Library

To list this plugin in **AssetLib** (the screen you see in the editor):

### 1. Prepare the repository

- Public repo: `https://github.com/sancheznot/Godot-AI-Assistant`
- Root of the repo **is** the addon folder (correct for this project)
- `LICENSE` and `README.md` at repo root (included)
- Working `plugin.cfg` and Godot 4 compatibility

### 2. Create an icon (required)

- Square image, **minimum 128×128** (256×256 recommended)
- Host it on GitHub and use a **raw** URL, e.g.  
  `https://raw.githubusercontent.com/sancheznot/Godot-AI-Assistant/main/icon.png`

### 3. Push to GitHub

Make sure `main` is up to date:

```bash
git push origin main
```

### 4. Submit the asset

1. Log in at [godotengine.org/asset-library](https://godotengine.org/asset-library/asset)
2. **Submit Assets**
3. Fill in:
   - **Name**: `Godot AI Assistant` (or similar)
   - **Category**: `Tools`
   - **Godot version**: `4.2` (or your minimum)
   - **License**: `MIT`
   - **Repository host**: GitHub
   - **Repository URL**: `https://github.com/sancheznot/Godot-AI-Assistant`
   - **Issues URL**: same repo `/issues`
   - **Download commit** (or tag): latest commit on `main`
   - **Plugin path**: leave empty if repo root **is** the addon (this repo)
4. English description + icon URL
5. Submit and wait for moderator review (usually a few days)

Official guide: [Submitting to the Asset Library](https://docs.godotengine.org/en/stable/community/asset_library/submitting_to_assetlib.html)

> **Tip:** After approval, users install via **AssetLib → search → Download → Install** into `addons/ai_assistant_plugin`.

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

Asistente de IA integrado en el editor de Godot 4. Chat con modelos locales o en la nube, contexto del proyecto (`@escena`, `@archivo`), comandos `/`, historial de agentes y UI en inglés/español.

**Autor:** [sancheznotdev](https://github.com/sancheznot) · Licencia MIT

Instalación: copia la carpeta a `addons/ai_assistant_plugin`, activa el plugin en Ajustes del proyecto y configura un proveedor (Ollama, OpenAI, etc.) desde **Config** en el dock.

Para publicarlo en AssetLib: sube el repo a GitHub, añade un icono cuadrado (128px+), regístrate en [godotengine.org/asset-library](https://godotengine.org/asset-library/asset) y envía el asset con licencia MIT y la URL del repositorio.
