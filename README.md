# mac-screenshot-mcp

Servidor MCP (stdio) en Swift 6 para macOS que permite a cualquier IDE/IA (Cursor, Claude Desktop, Windsurf, Zed…) listar apps y ventanas abiertas y capturar imágenes PNG de una app concreta, una ventana, o una región de la pantalla — igual que ⌘⇧4 pero automatizado.

Usa **ScreenCaptureKit** (`SCScreenshotManager`, disponible desde macOS 14). La API antigua `CGWindowListCreateImage` está obsoleta en macOS 15+, por eso no se usa.

## Requisitos

- macOS 14+
- Swift 6 / Xcode 16+ (solo para compilar)

## Instalación

```bash
scripts/install.sh        # swift build -c release + copia a /usr/local/bin (o ~/.local/bin)
```

O manualmente:

```bash
swift build -c release
cp .build/release/mac-screenshot-mcp /usr/local/bin/
```

## Permisos

La captura requiere el permiso de **Screen Recording** (Grabación de pantalla). El permiso se pide al proceso host que lanza el binario:

`System Settings > Privacy & Security > Screen Recording` → activar el IDE (Cursor, Claude, Terminal…).

El tool `check_permissions` informa del estado y `{"request": true}` dispara el diálogo del sistema.

## Configuración

### Cursor (`~/.cursor/mcp.json`) / Claude Desktop (`claude_desktop_config.json`) / Windsurf

```json
{
  "mcpServers": {
    "mac-screenshot": {
      "command": "/usr/local/bin/mac-screenshot-mcp"
    }
  }
}
```

### Zed (`settings.json`)

```json
{
  "context_servers": {
    "mac-screenshot": {
      "command": { "path": "/usr/local/bin/mac-screenshot-mcp", "args": [] }
    }
  }
}
```

## Tools

| Tool | Descripción |
|---|---|
| `list_apps` | Apps con UI abiertas (instantáneo, sin permiso) |
| `list_windows` | Ventanas capturables; filtros `pid`, `app_name` |
| `capture_app` | Captura la ventana principal de una app por nombre, bundle id o pid |
| `capture_window` | Captura una ventana por `window_id` |
| `capture_screen` | Pantalla completa o `region {x,y,w,h}` |
| `check_permissions` | Estado del permiso de Screen Recording |

### Ejemplos

```json
{"name": "list_apps"}
{"name": "list_windows", "arguments": {"app_name": "chrome"}}
{"name": "capture_app", "arguments": {"app": "Safari"}}
{"name": "capture_app", "arguments": {"app": "com.apple.finder", "window_title": "Descargas", "bring_to_front": true, "return_image": false}}
{"name": "capture_window", "arguments": {"window_id": 12345}}
{"name": "capture_screen", "arguments": {"region": {"x": 0, "y": 0, "w": 800, "h": 600}}}
{"name": "check_permissions", "arguments": {"request": true}}
```

Todas las capturas guardan el PNG (por defecto en `~/Pictures/mcp-captures/<app>-<timestamp>.png`, o en `save_path`) y devuelven la imagen en base64 más un JSON con `path`, `width`, `height`, `app`, `window_id`, `title`, `timestamp`. Con `return_image: false` se omite el base64 para respuestas más rápidas.

## Desarrollo

```bash
swift build          # debug
swift test           # tests de selección de ventanas
scripts/smoke.sh     # prueba stdio end-to-end contra el binario release
```

## Troubleshooting

### `install.sh` falla al clonar dependencias (git proxy / insteadOf)

Si `scripts/install.sh` falla con un error como:

```
fatal: could not read Username for 'https://git-manager.devin.ai': terminal prompts disabled
```

Es porque la configuración global de git tiene reglas `url.*.insteadOf` que redirigen las URLs de GitHub a través de un proxy (e.g. Devin's `git-manager`). SPM usa git internamente para resolver dependencias y el proxy bloquea la autenticacion.

**Ya corregido**: el script `install.sh` exporta `GIT_CONFIG_GLOBAL=/dev/null` y `GIT_CONFIG_SYSTEM=/dev/null` para ignorar estas reglas durante el build.

Si compilas manualmente con `swift build`, usa el mismo workaround:

```bash
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null swift build -c release
```
