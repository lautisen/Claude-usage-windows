# Claude Usage Widget

Widget para la bandeja del sistema de Windows que muestra en tiempo real el porcentaje de uso de tu plan de Claude: **sesión de 5 horas** y **semana**.

## Características

- Dos iconos en el system tray con el % de uso (sesión rellena, semana con borde).
- Color por severidad: verde (<50%), ámbar (50–80%), rojo (≥80%).
- Tooltip y menú contextual con la hora de reinicio y el tiempo restante.
- Actualización automática cada 3 minutos, o manual desde el menú.
- Opción "Iniciar con Windows".
- Instancia única (mutex) y sin ventana de consola.
- Doble clic para abrir el panel de uso en claude.ai.

## Requisitos

- Windows 10/11 con PowerShell 5.1 (incluido por defecto).
- [Claude Code](https://claude.com/claude-code) instalado e iniciado sesión al menos una vez.

## Uso

1. Clona el repositorio.
2. Haz doble clic en `ClaudeUsageWidget.vbs` (lanza el script sin mostrar consola).
3. Busca los iconos en la bandeja del sistema. Clic derecho para ver el menú.

## Cómo funciona

El script lee en modo **solo lectura** el token OAuth que Claude Code guarda en `~/.claude/.credentials.json` (o en `CLAUDE_CONFIG_DIR` si está definido) y consulta el mismo endpoint que usa el comando `/usage`. El token no se copia, no se guarda ni se envía a ningún otro servicio.

Detalles técnicos:

- `System.Windows.Forms.NotifyIcon` para los iconos del tray.
- Iconos dibujados dinámicamente con `System.Drawing` (GDI+), con ajuste automático del tamaño de fuente y soporte DPI.
- Gestión de handles nativos (`DestroyIcon` vía P/Invoke) para evitar fugas de memoria.

## Estructura

```
ClaudeUsageWidget.ps1   UI de la bandeja: iconos, menú, timer
ClaudeUsageWidget.vbs   Lanzador sin ventana de consola
src/UsageLogic.ps1      Lógica pura: credenciales, API, severidad, formato
tests/                  Tests Pester
.github/workflows/      CI (lint + tests en Windows)
```

La lógica está separada de la interfaz para poder probarla sin abrir ventanas ni llamar a la API real.

## Tests

```powershell
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser
Install-Module PSScriptAnalyzer -Scope CurrentUser

Invoke-Pester -Path ./tests
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

Cubren los umbrales de severidad, el formato del tiempo restante, el redondeo, la validación de credenciales (ausentes, sin token, vencido, válido) y el manejo de errores de la API con `Invoke-RestMethod` simulado. El CI ejecuta el análisis estático y los tests en cada push y pull request.

## Aviso

Usa un endpoint interno no documentado de Anthropic, por lo que podría dejar de funcionar sin previo aviso. Proyecto no oficial, sin afiliación con Anthropic.

## Licencia

MIT
