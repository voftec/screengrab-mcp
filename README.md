# screengrab-mcp

Servidor MCP (stdio) en Swift 6 para macOS que permite a cualquier IDE/IA (Cursor, Claude Desktop, Windsurf, Zed…) listar apps y ventanas abiertas y capturar imágenes PNG de una app concreta, una ventana, o una región de la pantalla — igual que ⌘⇧4 pero automatizado.

Usa **ScreenCaptureKit** (`SCScreenshotManager`, disponible desde macOS 14). La API antigua `CGWindowListCreateImage` está obsoleta en macOS 15+, por eso no se usa.

## Requisitos

- macOS 14+
- Swift 6 / Xcode 16+ (solo para compilar)

## Instalación

```bash
git clone https://github.com/voftec/screengrab-mcp.git
cd screengrab-mcp
scripts/install.sh        # swift build -c release + copia a /usr/local/bin (o ~/.local/bin)
```

O manualmente:

```bash
swift build -c release
cp .build/release/screengrab-mcp /usr/local/bin/
```

## Permisos

La captura requiere el permiso de **Screen Recording** (Grabación de pantalla). El permiso se pide al proceso host que lanza el binario:

`System Settings > Privacy & Security > Screen Recording` → activar el IDE (Cursor, Claude, Terminal…).

El tool `check_permissions` informa del estado y `{"request": true}` dispara el diálogo del sistema.

`read_ui` y `event_driven_screengrab` requieren además el permiso de **Accessibility** (Accesibilidad): `System Settings > Privacy & Security > Accessibility`.

## Configuración

### Cursor (`~/.cursor/mcp.json`) / Claude Desktop (`claude_desktop_config.json`) / Windsurf

```json
{
  "mcpServers": {
    "screengrab": {
      "command": "/usr/local/bin/screengrab-mcp"
    }
  }
}
```

### Zed (`settings.json`)

```json
{
  "context_servers": {
    "screengrab": {
      "command": { "path": "/usr/local/bin/screengrab-mcp", "args": [] }
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
| `read_ui` | Árbol de accesibilidad de la ventana de una app (roles, títulos, valores, frames). Requiere permiso de Accessibility |
| `event_driven_screengrab` | Espera un evento de UI (ventana creada/movida, cambio de título/foco/valor) y captura al ocurrir (o al timeout). Requiere Accessibility + Screen Recording |
| `check_permissions` | Estado de los permisos de Screen Recording y Accessibility |

### Parámetros de captura (capture_app, capture_window, capture_screen, event_driven_screengrab)

| Parámetro | Descripción |
|---|---|
| `quality` | `"high"` (defecto): PNG a resolución nativa · `"low"`: JPEG q0.6 reducido a `max_width` |
| `format` | `"png"` \| `"jpeg"` — explícito, sobreescribe el defecto de `quality` |
| `jpeg_quality` | 0–1 (defecto 0.6 en low, 0.85 en high+jpeg) |
| `max_width` | Reduce para que width ≤ max_width (defecto 1024 en low) |
| `save_path` | Ruta destino (defecto `~/Pictures/mcp-captures/`) |
| `return_image` | Incluir la imagen base64 en la respuesta (defecto true) |
| `compare_with` | Ruta a un PNG/JPEG previo: compara píxel a píxel y escribe `<path>-diff.png` |
| `return_diff_image` | Incluir también la imagen de diff inline (defecto false) |

`capture_app` además acepta: `window_title`, `bring_to_front`, `open` (abre la app si no está corriendo y espera hasta 15s a que tenga ventana), `delay_seconds` (0–60). `capture_window` acepta `delay_seconds`. `event_driven_screengrab` acepta `events` (array), `timeout_seconds` (máx 300) y `settle_ms`.

`read_ui` acepta: `app`, `window_title`, `max_depth` (defecto 12), `max_nodes` (defecto 1500).

### Ejemplos

```json
{"name": "list_apps"}
{"name": "list_windows", "arguments": {"app_name": "chrome"}}
{"name": "capture_app", "arguments": {"app": "Safari"}}
{"name": "capture_app", "arguments": {"app": "com.apple.finder", "window_title": "Descargas", "bring_to_front": true, "return_image": false}}
{"name": "capture_app", "arguments": {"app": "Notes", "open": true, "delay_seconds": 2, "quality": "low"}}
{"name": "capture_app", "arguments": {"app": "Safari", "compare_with": "~/Pictures/mcp-captures/Safari-20260101-120000.png", "return_image": false}}
{"name": "capture_window", "arguments": {"window_id": 12345}}
{"name": "capture_screen", "arguments": {"region": {"x": 0, "y": 0, "w": 800, "h": 600}}}
{"name": "read_ui", "arguments": {"app": "Simulator", "max_depth": 6}}
{"name": "event_driven_screengrab", "arguments": {"app": "Simulator", "events": ["ui_changed", "title_changed"], "timeout_seconds": 10, "quality": "low"}}
{"name": "check_permissions", "arguments": {"request": true}}
```

Todas las capturas guardan la imagen (por defecto en `~/Pictures/mcp-captures/<app>-<timestamp>.<png|jpg>`, o en `save_path`) y devuelven la imagen en base64 más un JSON con `path`, `width`, `height`, `app`, `window_id`, `title`, `timestamp`. Con `return_image: false` se omite el base64 para respuestas más rápidas. Con `compare_with` el JSON incluye `diff` (`changed_pixels`, `changed_percent`, `bounding_box`, `diff_path`).

### Resources

El servidor expone `~/Pictures/mcp-captures/` como recursos MCP (`resources/list` → `file://` URIs, `resources/read` devuelve el binario base64). Solo se sirven archivos dentro de ese directorio.

## Para agentes

Bucle barato para verificar cambios de UI sin saturar el contexto:

1. `read_ui` para inspeccionar el árbol de accesibilidad (texto, gratis en tokens).
2. Actuar (clic, teclear) desde tu IDE o con `event_driven_screengrab` esperando el evento resultante.
3. `event_driven_screengrab` con `quality: "low"` + `return_image: false` → JSON con `path` y `bytes`, imagen pequeña si se pide.
4. `capture_app` con `compare_with` apuntando a la captura anterior → `diff.changed_percent` te dice si la UI cambió sin enviar imágenes, y `<path>-diff.png` marca en rojo lo que cambió.

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

## Licencia

Software propietario de Voftec — ver `LICENSE`. No es código abierto: se prohíbe su reproducción, redistribución e ingeniería inversa sin autorización escrita.
