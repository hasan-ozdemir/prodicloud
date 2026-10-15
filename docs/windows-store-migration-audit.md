# Windows Store Migration Audit

This audit captures the current `vm-update/windows` application install surface and highlights which apps are already Store-backed, which ones have a plausible `winget + msstore` path that still needs explicit maintainer approval, and which ones should stay on their current installer source for now.

Status rules used here:
- `already-store-backed`: the current tracked task already installs from `msstore`.
- `candidate-awaiting-approval`: a credible `msstore` package was found, but the repo will not migrate the installer source until the maintainer explicitly approves the move.
- `keep-current-source`: the current source remains the recommended path for this repo at the moment.
- `not-a-store-app`: the app is not part of the Windows Store migration question for the current tracked task.

## Current Matrix

| App | Current task | Current source | msstore status | Recommendation | Notes |
| --- | --- | --- | --- | --- | --- |
| Google Chrome | `03-install-chrome-application` | direct installer / current browser check | no current Store migration plan | keep-current-source | Repo treats Chrome as a classic desktop browser and shared profile target. |
| PowerShell 7 | `101-install-powershell-tool` | Chocolatey | not-a-store-app | keep-current-source | Classic developer runtime. |
| Git | `102-install-git-tool` | Chocolatey | not-a-store-app | keep-current-source | Classic desktop/runtime install. |
| Python | `103-install-python-tool` | Chocolatey | not-a-store-app | keep-current-source | Classic developer runtime. |
| Node.js | `104-install-node-tool` | Chocolatey | not-a-store-app | keep-current-source | Classic developer runtime. |
| Azure CLI | `105-install-azure-cli-tool` | Chocolatey | no useful Store path confirmed | keep-current-source | CLI state is better handled outside Store packaging. |
| GitHub CLI | `106-install-gh-tool` | Chocolatey | no useful Store path confirmed | keep-current-source | CLI state is better handled outside Store packaging. |
| 7-Zip | `106-install-7zip-tool` | Chocolatey | not-a-store-app | keep-current-source | Classic utility install. |
| FFmpeg | `109-install-ffmpeg-tool` | Chocolatey | not-a-store-app | keep-current-source | Classic utility install. |
| Visual Studio Code | `110-install-vscode-application` | classic installer | Store package found | candidate-awaiting-approval | `XP9KHM4BK9FZ7Q` was found via `winget search --source msstore`. |
| Microsoft Edge | `111-install-edge-application` | classic installer | Store package found | candidate-awaiting-approval | `XPFFTQ037JWMHS` was found via `winget search --source msstore`. |
| Azure Developer CLI | `112-install-azd-tool` | winget/community | no useful Store path confirmed | keep-current-source | CLI state is better handled outside Store packaging. |
| WSL | `113-install-wsl-feature` | DISM + `Microsoft.WSL` bootstrap | no useful Store migration plan | keep-current-source | Repo already hardens the WSL 2 feature path directly. |
| Docker Desktop | `114-install-docker-desktop-application` | winget classic package | Store package found | candidate-awaiting-approval | `XP8CBJ40XLBWKX` was found via `winget search --source msstore`. |
| OpenAI Codex CLI | `124-install-openai-codex-tool` | npm registry | not-a-store-app | keep-current-source | Standalone global npm CLI task. |
| GitHub Copilot CLI | `125-install-github-copilot-tool` | npm registry | not-a-store-app | keep-current-source | Standalone global npm CLI task. |
| Google Gemini CLI | `126-install-google-gemini-tool` | npm registry | not-a-store-app | keep-current-source | Standalone global npm CLI task. |
| Ollama | `116-install-ollama-tool` | winget classic package | no useful Store path confirmed | keep-current-source | Service/API workflow is already modeled around the classic install. |
| Codex App | `120-install-codex-application` | `winget + msstore` | already-store-backed | keep-current-source | Public desktop shortcut now prefers `shell:AppsFolder\<AUMID>`. |
| Microsoft Teams | `118-install-teams-application` | `winget + msstore` | already-store-backed | keep-current-source | Public desktop shortcut already uses `AppsFolder` launch. |
| OneDrive | `119-install-onedrive-application` | classic package | no useful Store migration plan | keep-current-source | Current install path is acceptable for repo automation. |
| Google Drive | `120-install-google-drive-application` | classic package | no useful Store path confirmed | keep-current-source | Versioned classic install path is already supported. |
| WhatsApp | `121-install-whatsapp-application` | `winget + msstore` | already-store-backed | keep-current-source | Public desktop shortcut now prefers `shell:AppsFolder\<AUMID>`. |
| AnyDesk | `122-install-anydesk-application` | winget classic package | no useful Store path confirmed | keep-current-source | Current verification remains classic-exe based. |
| Windscribe | `123-install-windscribe-application` | winget classic package | no current migration plan | keep-current-source | Repo keeps the current installer path. |
| VLC | `124-install-vlc-application` | winget/classic | no useful Store path confirmed | keep-current-source | Classic media install remains the stable path. |
| iTunes | `125-install-itunes-application` | winget/classic | no useful Store path confirmed | keep-current-source | Current repo flow remains classic-exe based. |
| Be My Eyes | `126-install-be-my-eyes-application` | `winget + msstore` | already-store-backed | keep-current-source | Public desktop shortcut already uses `AppsFolder` launch. |
| NVDA | `127-install-nvda-application` | winget/classic | no useful Store path confirmed | keep-current-source | Accessibility app stays on current source. |
| Rclone | `128-install-rclone-tool` | winget/classic | no useful Store path confirmed | keep-current-source | CLI install stays outside Store packaging. |
| Io Unlocker | `129-configure-unlocker-settings` | Chocolatey | not-a-store-app | keep-current-source | Classic utility install. |
| iCloud | `131-install-icloud-application` | `winget + msstore` | already-store-backed | keep-current-source | Public desktop shortcut now prefers `shell:AppsFolder\<AUMID>`. |
| Visual Studio 2022 Community | `132-install-vs2022community-application-application` | Chocolatey | no useful Store path confirmed | keep-current-source | Current install path remains the practical route. |

## Approval Gate

No installer-source migration was applied for these current Store candidates:
- `Microsoft Edge`
- `Docker Desktop`
- `Visual Studio Code`

If you approve any of them, the next change should update:
- the owning install task
- installer verification logic
- public desktop shortcut expectations when the app becomes Store-backed
- smoke tests and docs in the same patch
