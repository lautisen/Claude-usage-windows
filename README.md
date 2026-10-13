# Claude Usage — Windows system tray widget

[![CI](https://github.com/lautisen/Claude-usage-windows/actions/workflows/ci.yml/badge.svg)](https://github.com/lautisen/Claude-usage-windows/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/lautisen/Claude-usage-windows)](https://github.com/lautisen/Claude-usage-windows/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A lightweight Windows system tray widget that shows your **Claude plan usage limits** in real time: the current 5‑hour session and the weekly limit — with countdowns to each reset. Pure PowerShell + WinForms, nothing to install.

> 🇪🇸 Widget para la bandeja del sistema de Windows que muestra en tiempo real el uso de los límites de tu plan de Claude (sesión de 5 h y semanal) con la cuenta atrás hasta cada reinicio. La interfaz está en español.

Looking for macOS? See [claude-usage-menubar](https://github.com/lautisen/claude-usage-menubar).

## Features

- **Two tray icons** with the current percentage drawn on them:
  - **Session (5 h)** — filled rounded square.
  - **Week** — dark square with a coloured border.
- **Severity colours** — green below 75 %, amber from 75 %, red from 90 %.
- **Tooltip and context menu** with the reset time and time remaining, e.g. `42% - reinicia 17:30 (en 2h 13m)`.
- **Auto‑refresh** every 3 minutes, plus a manual **Refresh now** menu item.
- **Start with Windows** toggle (shortcut in the user's Startup folder).
- **Double‑click** an icon to open the usage page on claude.ai.
- Single instance, no console window, DPI‑aware icons, no third‑party dependencies.

## How it works

The widget reuses the OAuth session that [Claude Code](https://claude.com/claude-code) already stores in `%USERPROFILE%\.claude\.credentials.json` (or under `CLAUDE_CONFIG_DIR` if set). The file is read‑only: nothing is copied or written. It then calls the usage endpoint that Claude Code itself uses for `/usage` (`/api/oauth/usage`) and renders the result.

Your token never leaves your machine except in the request to `api.anthropic.com`.

## Requirements

- Windows 10 or 11 with Windows PowerShell 5.1 (built in)
- Claude Code installed and logged in with a Claude subscription (`claude` → `/login`)

## Download

Grab `ClaudeUsageWidget.zip` from the [latest release](https://github.com/lautisen/Claude-usage-windows/releases/latest), unzip it anywhere (e.g. `%LOCALAPPDATA%\ClaudeUsageWidget`) and double‑click **`ClaudeUsageWidget.vbs`**.

Files downloaded from the internet are marked as blocked by Windows. If the widget does not start, unblock them once from PowerShell:

```powershell
Get-ChildItem -Recurse "$env:LOCALAPPDATA\ClaudeUsageWidget" | Unblock-File
```

The icons may land in the hidden tray area (`^`). Drag them onto the taskbar to keep them visible. Right‑click either icon for the menu, including **Iniciar con Windows**.

## Run from source

```powershell
git clone https://github.com/lautisen/Claude-usage-windows.git
cd Claude-usage-windows
wscript .\ClaudeUsageWidget.vbs
```

To see errors while developing, run the script directly in a console instead:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\ClaudeUsageWidget.ps1
```

## Tests

The logic is covered by a [Pester](https://pester.dev) 5 suite and the code is linted with [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer):

```powershell
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser -SkipPublisherCheck
Install-Module PSScriptAnalyzer -Scope CurrentUser

Invoke-Pester -Path ./tests
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

What is covered:

- **Networking** — `Get-Usage` with a mocked `Invoke-RestMethod`: the token is sent as a Bearer header, network failures map to a clear message, and no request is made without credentials.
- **Credentials** — missing file, corrupt JSON, missing token, expired token, valid token and token without expiry.
- **Error mapping** — HTTP 401/403/429/5xx and unexpected status codes to user‑facing messages.
- **Parsing & formatting** — percentage rounding, reset time and countdown strings, and the severity thresholds, using data‑driven tests.

CI runs the linter and the tests on both Windows PowerShell 5.1 and PowerShell 7 on every push and pull request.

## Project structure

| File | Responsibility |
| --- | --- |
| `ClaudeUsageWidget.ps1` | Tray UI: icon drawing, context menu, refresh timer, autostart |
| `ClaudeUsageWidget.vbs` | Launcher that starts PowerShell without a console window |
| `src/UsageLogic.ps1` | Pure logic: credential loading, API request, error mapping, severity and formatting |
| `tests/UsageLogic.Tests.ps1` | Pester tests for `src/UsageLogic.ps1` |
| `PSScriptAnalyzerSettings.psd1` | Linter rules |
| `.github/workflows/` | CI (lint + tests) and release packaging |

The logic is kept apart from the UI so it can be tested without opening windows or calling the real API.

### Implementation notes

- **Icons drawn at runtime**: each icon is rendered with GDI+ at the system small‑icon size, shrinking the font until the text (up to `100`) fits.
- **No handle leaks**: `Bitmap.GetHicon()` returns a native handle that .NET never frees, so the previous one is released with `DestroyIcon` (P/Invoke) on every update.
- **Tooltip limit**: `NotifyIcon.Text` throws above 63 characters, so tooltips are truncated.
- **Icon order**: the week icon is created first so the session icon appears to its left.
- **TLS 1.2** is forced, since Windows PowerShell 5.1 may default to older protocols.

## Disclaimer

This is an unofficial personal project, not affiliated with or endorsed by Anthropic. It relies on an undocumented endpoint that may change or stop working at any time.

## License

[MIT](LICENSE)
