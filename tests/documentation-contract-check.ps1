param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Test-ContainsTurkishLetters {
    param(
        [string]$Text
    )

    if ($null -eq $Text) {
        return $false
    }

    $turkishLetters = @([char]0x00E7,[char]0x00C7,[char]0x011F,[char]0x011E,[char]0x0131,[char]0x0130,[char]0x00F6,[char]0x00D6,[char]0x015F,[char]0x015E,[char]0x00FC,[char]0x00DC)
    foreach ($letter in @($turkishLetters)) {
        if ($Text.Contains([string]$letter)) {
            return $true
        }
    }

    return $false
}

function Assert-HeadingOrder {
    param(
        [string]$Text,
        [string[]]$Headings,
        [string]$DocumentLabel = 'document'
    )

    $lastIndex = -1
    foreach ($heading in @($Headings)) {
        $match = [regex]::Match($Text, ('(?m)^{0}\r?$' -f [regex]::Escape([string]$heading)))
        Assert-True -Condition $match.Success -Message ("{0} must contain heading '{1}'." -f $DocumentLabel, [string]$heading)
        Assert-True -Condition ($match.Index -gt $lastIndex) -Message ("{0} headings are out of order around '{1}'." -f $DocumentLabel, [string]$heading)
        $lastIndex = [int]$match.Index
    }
}

$requiredFiles = @(
    'AGENTS.md',
    'README.md',
    'LICENSE',
    'CONTRIBUTING.md',
    'SUPPORT.md',
    'SECURITY.md',
    'CODE_OF_CONDUCT.md',
    'CHANGELOG.md',
    'release-notes.md',
    'roadmap.md',
    'docs\prompt-history.md',
    'tools\enable-git-hooks.ps1',
    'tools\disable-git-hooks.ps1',
    'tests\pre-commit-release-doc-check.ps1',
    'tests\sensitive-content-check.ps1',
    '.githooks\pre-commit',
    '.githooks\commit-msg',
    '.github\workflows\quality-gate.yml',
    '.github\ISSUE_TEMPLATE\bug-report.yml',
    '.github\ISSUE_TEMPLATE\feature-request.yml',
    '.github\ISSUE_TEMPLATE\config.yml',
    '.github\pull_request_template.md'
)

foreach ($relativePath in $requiredFiles) {
    $fullPath = Join-Path $RepoRoot $relativePath
    Assert-True -Condition (Test-Path -LiteralPath $fullPath) -Message ("Required documentation file is missing: {0}" -f $relativePath)
}

$agentsPath = Join-Path $RepoRoot 'AGENTS.md'
$readmePath = Join-Path $RepoRoot 'README.md'
$licensePath = Join-Path $RepoRoot 'LICENSE'
$contributingPath = Join-Path $RepoRoot 'CONTRIBUTING.md'
$supportPath = Join-Path $RepoRoot 'SUPPORT.md'
$securityPath = Join-Path $RepoRoot 'SECURITY.md'
$codeOfConductPath = Join-Path $RepoRoot 'CODE_OF_CONDUCT.md'
$changelogPath = Join-Path $RepoRoot 'CHANGELOG.md'
$releaseNotesPath = Join-Path $RepoRoot 'release-notes.md'
$roadmapPath = Join-Path $RepoRoot 'roadmap.md'
$promptHistoryPath = Join-Path $RepoRoot 'docs\prompt-history.md'
$preCommitCheckPath = Join-Path $RepoRoot 'tests\pre-commit-release-doc-check.ps1'
$sensitiveContentCheckPath = Join-Path $RepoRoot 'tests\sensitive-content-check.ps1'
$preCommitPath = Join-Path $RepoRoot '.githooks\pre-commit'
$commitMsgPath = Join-Path $RepoRoot '.githooks\commit-msg'
$workflowPath = Join-Path $RepoRoot '.github\workflows\quality-gate.yml'

$agentsText = Get-Content -LiteralPath $agentsPath -Raw
$readmeText = Get-Content -LiteralPath $readmePath -Raw
$licenseText = Get-Content -LiteralPath $licensePath -Raw
$contributingText = Get-Content -LiteralPath $contributingPath -Raw
$supportText = Get-Content -LiteralPath $supportPath -Raw
$securityText = Get-Content -LiteralPath $securityPath -Raw
$codeOfConductText = Get-Content -LiteralPath $codeOfConductPath -Raw
$changelogText = Get-Content -LiteralPath $changelogPath -Raw
$releaseNotesText = Get-Content -LiteralPath $releaseNotesPath -Raw
$roadmapText = Get-Content -LiteralPath $roadmapPath -Raw
$promptHistoryText = Get-Content -LiteralPath $promptHistoryPath -Raw
$preCommitCheckText = Get-Content -LiteralPath $preCommitCheckPath -Raw
$sensitiveContentCheckText = Get-Content -LiteralPath $sensitiveContentCheckPath -Raw
$preCommitText = Get-Content -LiteralPath $preCommitPath -Raw
$commitMsgText = Get-Content -LiteralPath $commitMsgPath -Raw
$workflowText = Get-Content -LiteralPath $workflowPath -Raw

$requiredCommandTokens = @('configure','create','update','list','show','do','task','connect','exec','move','resize','set','delete','help')
foreach ($token in $requiredCommandTokens) {
    $commandNeedle = ([string][char]96) + $token + ([string][char]96)
    Assert-True -Condition ($readmeText.Contains($commandNeedle)) -Message ("README.md must mention command '{0}'." -f $token)
}

$requiredDocTokens = @('LICENSE','CONTRIBUTING.md','SUPPORT.md','SECURITY.md','CODE_OF_CONDUCT.md','CHANGELOG.md','release-notes.md','roadmap.md','docs/prompt-history.md')
foreach ($token in $requiredDocTokens) {
    Assert-True -Condition ($readmeText -match [regex]::Escape($token)) -Message ("README.md must mention '{0}'." -f $token)
}

Assert-True -Condition ($readmeText -match 'tools[\\/]+enable-git-hooks\.ps1') -Message 'README.md must mention tools/enable-git-hooks.ps1.'
Assert-True -Condition ($readmeText -match 'tools[\\/]+disable-git-hooks\.ps1') -Message 'README.md must mention tools/disable-git-hooks.ps1.'
Assert-True -Condition ($readmeText -match [regex]::Escape('At a glance:')) -Message 'README.md must include the audience-facing at-a-glance intro.'
Assert-True -Condition ($readmeText -match '(?m)^## Quick Start Guide\r?$') -Message 'README.md must define the merged Quick Start Guide heading.'
Assert-True -Condition ($readmeText -match '(?m)^## Executive Summary\r?$') -Message 'README.md must define Executive Summary as a top-level heading.'
Assert-True -Condition ($readmeText -match '(?m)^## Value By Audience\r?$') -Message 'README.md must define the Value By Audience section.'
Assert-True -Condition ($readmeText -match '(?m)^## Operational Command Matrix\r?$') -Message 'README.md must define the Operational Command Matrix section.'
Assert-True -Condition ($readmeText -match '(?m)^### Global Options Matrix\r?$') -Message 'README.md must define the Global Options Matrix subsection.'
Assert-True -Condition ($readmeText -match '(?m)^### Command Matrix\r?$') -Message 'README.md must define the Command Matrix subsection.'
Assert-True -Condition ($readmeText -match '(?m)^### Command Variations By Command\r?$') -Message 'README.md must define the command variation matrix subsection.'
Assert-True -Condition (-not ($readmeText -match '(?m)^## Quick Start\r?$')) -Message 'README.md must not keep the retired Quick Start heading.'
Assert-True -Condition (-not ($readmeText -match '(?m)^### Quick Accelerator\r?$')) -Message 'README.md must not keep Quick Accelerator as a separate heading.'
Assert-HeadingOrder -Text $readmeText -DocumentLabel 'README.md' -Headings @(
    '## Quick Start Guide',
    '## Customer Business Value',
    '## Executive Summary',
    '## Value By Audience',
    '## Delivered VM Outcome Matrix',
    '## Who clagnos Is For',
    '## Why clagnos Exists',
    '## Operational Command Matrix',
    '## Practical And Extensive Usage Scenarios',
    '## Command Guide',
    '## Task Authoring And Execution',
    '## Configuration Guide',
    '## Developer Benefits',
    '## Core Mental Model',
    '## Architecture From Zero To Hero',
    '## Troubleshooting Guide',
    '## Developer Workflow',
    '## Documentation Set',
    '## License And Sponsorship'
)
Assert-True -Condition ($agentsText -match [regex]::Escape('docs/prompt-history.md')) -Message 'AGENTS.md must mention docs/prompt-history.md.'
Assert-True -Condition ($agentsText -match [regex]::Escape('CONTRIBUTING.md')) -Message 'AGENTS.md must mention CONTRIBUTING.md.'
Assert-True -Condition ($agentsText -match [regex]::Escape('SUPPORT.md')) -Message 'AGENTS.md must mention SUPPORT.md.'
Assert-True -Condition ($agentsText -match [regex]::Escape('SECURITY.md')) -Message 'AGENTS.md must mention SECURITY.md.'
Assert-True -Condition ($agentsText -match [regex]::Escape('CODE_OF_CONDUCT.md')) -Message 'AGENTS.md must mention CODE_OF_CONDUCT.md.'
Assert-True -Condition ($agentsText -match [regex]::Escape('Do not auto-record very short approval, confirmation, interruption, or follow-up prompts')) -Message 'AGENTS.md must define the short follow-up prompt-history exclusion.'
Assert-True -Condition ($agentsText -match [regex]::Escape('Do not auto-record non-mutating user prompts that only ask questions, request analysis, or request investigation without causing repo file changes.')) -Message 'AGENTS.md must define the non-mutating prompt-history exclusion.'
Assert-True -Condition ($agentsText -match [regex]::Escape('For those excluded prompt types, the assistant must answer normally and end with a short hint that the prompt can be recorded on request.')) -Message 'AGENTS.md must define the short opt-in hint for excluded prompt types.'
Assert-True -Condition ($agentsText -match [regex]::Escape('Record every other completed user prompt in `docs/prompt-history.md`, including substantive repo-changing prompts and substantive operational prompts')) -Message 'AGENTS.md must define the mandatory recording path for substantive prompts.'
Assert-True -Condition ($agentsText -match [regex]::Escape('If the user replies yes or gives another clearly positive confirmation')) -Message 'AGENTS.md must define the opt-in recording path for excluded prompts.'
Assert-True -Condition ($agentsText -match [regex]::Escape('Record prompt-history entries in English.')) -Message 'AGENTS.md must require English-normalized prompt-history entries.'
Assert-True -Condition ($agentsText -match [regex]::Escape('If the original user prompt or assistant summary is not English')) -Message 'AGENTS.md must define translation before prompt-history recording.'
Assert-True -Condition ($agentsText -match [regex]::Escape('Keep maintained repository documentation in English.')) -Message 'AGENTS.md must require English documentation.'
Assert-True -Condition ($agentsText -match [regex]::Escape('Local-machine task app-state save/restore is Windows-host-only, must validate the current `task.json` allow-list before local restore, and must write task-adjacent backup snapshots plus both `restore-journal.json` and `verify-report.json` before mutating the operator machine.')) -Message 'AGENTS.md must define the local-machine restore safety contract.'
Assert-True -Condition ($agentsText -match [regex]::Escape('Keep app-wide customization, secrets, operator identity, and reusable overrides in `.env`.')) -Message 'AGENTS.md must require app-wide customization to live in .env.'
Assert-True -Condition ($agentsText -match [regex]::Escape('Keep task-only customization in a clearly labeled config block at the top of the owning `vm-init` or `vm-update` script.')) -Message 'AGENTS.md must define the task-local config-block rule.'
Assert-True -Condition ($agentsText -match [regex]::Escape('Managed app-state save and restore must target only the `manager` and `assistant` OS profiles.')) -Message 'AGENTS.md must lock managed app-state profile targeting to manager and assistant.'
Assert-True -Condition ($agentsText -match [regex]::Escape('Do not hard-code personal, company-specific, or secret fallback values in runtime code or shared orchestration paths.')) -Message 'AGENTS.md must forbid hard-coded personal/company/secret fallbacks.'
Assert-True -Condition ($agentsText -match [regex]::Escape('No commit may introduce concrete secrets, contact-style values, personal identifiers, organization identifiers, or live-target sample values into tracked code, docs, examples, tests, or commit messages.')) -Message 'AGENTS.md must forbid committing concrete sensitive or identity-like values.'
Assert-True -Condition ($agentsText -match [regex]::Escape('Maintain an always-on sensitive-content audit in local hooks and CI; update that audit in the same change whenever new committed surfaces or new leak-prone example formats are introduced.')) -Message 'AGENTS.md must require an always-on sensitive-content audit.'
Assert-True -Condition ($agentsText -match [regex]::Escape('`create` is fresh-only: it creates one new managed resource group plus one new managed VM target and must not be documented or wired as an existing-resource reuse path.')) -Message 'AGENTS.md must define the fresh-only create contract.'
Assert-True -Condition ($agentsText -match [regex]::Escape('`update` is existing-managed-target only: it requires one existing managed resource group plus one existing VM and must not fall through to implicit fresh-create behavior.')) -Message 'AGENTS.md must define the existing-only update contract.'
Assert-True -Condition ($agentsText -match [regex]::Escape('`configure` is the interactive `.env` frontend: it must stay focused on reviewing, editing, validating, previewing, and saving supported `.env` values, and it must not sync `.env` from a live Azure target.')) -Message 'AGENTS.md must define the configure interactive editor contract.'
Assert-True -Condition ($agentsText -match [regex]::Escape('`configure` must recover softly for blank-permitted fields: stale or empty picker-backed values should guide the operator back to a valid choice when possible, otherwise clear the staged value and continue; save may be blocked only by unresolved create-critical values.')) -Message 'AGENTS.md must define configure soft recovery and create-critical save blocking.'
Assert-True -Condition ($agentsText -match [regex]::Escape('Azure-touching commands support `--subscription-id` plus `-s`; resolution precedence is CLI override -> `.env` `SELECTED_AZURE_SUBSCRIPTION_ID` -> active Azure CLI subscription.')) -Message 'AGENTS.md must define subscription precedence.'
Assert-True -Condition ($agentsText -match [regex]::Escape('Azure-touching commands require an authenticated Azure CLI session; help, README, and runtime errors must say `az login` is required. `configure` is the exception: it may open without `az login`, but Azure-backed configure fields must stay read-only until Azure validation is available.')) -Message 'AGENTS.md must define the az login requirement and configure exception.'
Assert-True -Condition ($agentsText -match [regex]::Escape('Interactive `create` and `update` must prompt for Azure subscription selection when `--subscription-id` is omitted.')) -Message 'AGENTS.md must define the interactive subscription picker rule.'
Assert-True -Condition ($agentsText -match [regex]::Escape('Interactive `initialize` must also prompt for Azure subscription selection when `--subscription-id` is omitted.')) -Message 'AGENTS.md must define the interactive initialize subscription picker rule.'
Assert-True -Condition ($agentsText -match [regex]::Escape('The TUI `Cloud subscriptions` menu must list every accessible Azure subscription, mark both the Clagnos-selected subscription and Azure CLI active default, and allow numeric selection. A selection must update `az account set` and persist `SELECTED_AZURE_SUBSCRIPTION_ID` so all later TUI operations use the selected subscription.')) -Message 'AGENTS.md must define the interactive cloud subscription selection contract.'
Assert-True -Condition ($agentsText -match [regex]::Escape('`list` is the managed inventory command: it must stay Azure-read-only, must not mutate Azure resources, and must expose managed resource listings through `--type` plus optional exact `--group` filtering.')) -Message 'AGENTS.md must define the list inventory contract.'
Assert-True -Condition ($agentsText -match [regex]::Escape('`create --auto` must resolve platform, VM name, Azure region, and platform VM size from CLI or `SELECTED_*` plus platform defaults in `.env`; `update --auto` must resolve one managed target from CLI or the selected target values in `.env`.')) -Message 'AGENTS.md must define the strict auto-mode contract.'
Assert-True -Condition ($agentsText -match [regex]::Escape('Managed resource group ids use a globally increasing `gX` suffix across all managed groups, regardless of region.')) -Message 'AGENTS.md must document global managed resource-group ids.'
Assert-True -Condition ($agentsText -match [regex]::Escape('Managed resource ids use a globally increasing `nX` suffix across all generated managed resources; one generated `nX` must not be reused by another managed resource, even across resource types.')) -Message 'AGENTS.md must document global managed resource ids.'
Assert-True -Condition ($agentsText -match [regex]::Escape('Interactive `create`, `initialize`, and `update` are review-first flows: `create` reviews `group` and `vm-deploy`; `initialize` reviews `vm-init`; `update` reviews `vm-update`.')) -Message 'AGENTS.md must define lifecycle-specific review checkpoints.'
Assert-True -Condition ($agentsText -match [regex]::Escape('`configure` and `vm-summary` must always render without confirmation, even when partial step selection skips interior mutation stages.')) -Message 'AGENTS.md must define the always-visible configure/vm-summary rule.'
Assert-True -Condition ($agentsText -match [regex]::Escape('VM_ENABLE_HIBERNATION')) -Message 'AGENTS.md must mention the shared VM_ENABLE_HIBERNATION config key.'
Assert-True -Condition ($agentsText -match [regex]::Escape('VM_ENABLE_NESTED_VIRTUALIZATION')) -Message 'AGENTS.md must mention the shared VM_ENABLE_NESTED_VIRTUALIZATION config key.'
Assert-True -Condition ($agentsText -match [regex]::Escape('<task-number>-verb-noun-target')) -Message 'AGENTS.md must define the normalized task folder contract.'
Assert-True -Condition ($agentsText -match [regex]::Escape('01-99')) -Message 'AGENTS.md must describe the initial task-number band.'
Assert-True -Condition ($agentsText -match [regex]::Escape('101-999')) -Message 'AGENTS.md must describe the normal task-number band.'
Assert-True -Condition ($agentsText -match [regex]::Escape('1001-9999')) -Message 'AGENTS.md must describe the local task-number band.'
Assert-True -Condition ($agentsText -match [regex]::Escape('10001-10099')) -Message 'AGENTS.md must describe the final task-number band.'
Assert-True -Condition ($agentsText -match [regex]::Escape('`task.json` may supply `priority`, `enabled`, `timeout`, `assets`, `appState`, `dependsOn`, and validated `program` metadata.')) -Message 'AGENTS.md must define the task-folder metadata contract.'
Assert-True -Condition ($agentsText -match [regex]::Escape('Runtime discovery and execution must not auto-write, auto-sync, or auto-reconcile `task.json` files. The explicit `task --enable` / `task --disable` operation may change only the task''s `enabled` field after typed confirmation, must preserve all other metadata, and must verify the resulting catalog state; location-disabled folders must move only between their matching active and `disabled/` roots.')) -Message 'AGENTS.md must define the explicit task enable/disable safety contract.'
Assert-True -Condition ($agentsText -match [regex]::Escape('Program screens must label each entry''s lifecycle type (`initial` or `add-on`) and execution target (`local` or `remote`); mark local-only catalog entries separately so catalog location is not confused with the guest execution target.')) -Message 'AGENTS.md must define the program type and execution-target label contract.'
Assert-True -Condition ($agentsText -match [regex]::Escape('They must list disabled program tasks with a disabled marker, allow explicit enable/disable, keep status and uninstall available while disabled, and block install/update until re-enabled.')) -Message 'AGENTS.md must define the program enable/disable interaction contract.'
Assert-True -Condition ($agentsText -match [regex]::Escape('Intentionally local-only tasks live under `local/` as portable task folders and are discovered from disk at runtime.')) -Message 'AGENTS.md must define the local-only task directory contract.'
Assert-True -Condition ($agentsText -match [regex]::Escape('Intentionally local-only disabled tasks live under `local/disabled/` and remain disabled by location.')) -Message 'AGENTS.md must define the local-only disabled task directory contract.'
Assert-True -Condition ($agentsText -match [regex]::Escape('Each task folder must contain one same-named task script plus one `task.json`.')) -Message 'AGENTS.md must define the portable task-folder layout.'
Assert-True -Condition ($agentsText -match [regex]::Escape('`task.json` is the execution-order, enable-state, timeout, asset, and app-state source of truth for tracked and local-only task folders.')) -Message 'AGENTS.md must define task.json as the task contract.'
Assert-True -Condition ($agentsText -match [regex]::Escape('The only allowed task app-state source is the task-local plugin zip `<task-folder>/app-state/app-state.zip`.')) -Message 'AGENTS.md must define the task-local app-state path.'
Assert-True -Condition ($agentsText -match [regex]::Escape('Task-adjacent `backup-app-states/` folders are untracked and git-ignored; local-machine restore must write backups under `<stage-root>/backup-app-states/<task-name>` or `<stage-root>/local/backup-app-states/<task-name>`, verify the restored content, and roll back from that backup root if verification fails.')) -Message 'AGENTS.md must define the task-adjacent backup-app-states contract.'
Assert-True -Condition ($agentsText -match [regex]::Escape('Task priority precedence is: `task.json priority` -> filename task number -> deterministic fallback within the current task-number band.')) -Message 'AGENTS.md must define the task-folder priority precedence rule.'
Assert-True -Condition ($agentsText -match [regex]::Escape('For task folders with missing `priority`, default to the filename task number when available, otherwise `1000`.')) -Message 'AGENTS.md must document the task-folder priority fallback.'
Assert-True -Condition ($agentsText -match [regex]::Escape('For task folders with missing `timeout`, default to `180`.')) -Message 'AGENTS.md must document the task-folder timeout fallback.'
Assert-True -Condition ($agentsText -match [regex]::Escape('Before creating the final commit for a repo-changing prompt, update `CHANGELOG.md` and `release-notes.md`')) -Message 'AGENTS.md must require changelog and release-notes updates before the final commit.'
Assert-True -Condition ($agentsText -match [regex]::Escape('YYYY.M.D.N')) -Message 'AGENTS.md must define the release versioning format.'
Assert-True -Condition ($agentsText -match [regex]::Escape('For live publish or release-readiness claims, require one successful end-to-end live acceptance cycle against the active profile')) -Message 'AGENTS.md must define the live release-acceptance gate.'
Assert-True -Condition ($agentsText -match [regex]::Escape('When maintained repository documentation records a time-of-day, record it in UTC.')) -Message 'AGENTS.md must require UTC documentation timestamps.'
Assert-True -Condition ($agentsText -match [regex]::Escape('Record prompt-history timestamps as `### YYYY-MM-DD HH:MM UTC`.')) -Message 'AGENTS.md must require UTC prompt-history headings.'
Assert-True -Condition ($licenseText -match [regex]::Escape('Commercial licensing requires explicit permission from the developer.')) -Message 'LICENSE must define the commercial licensing rule.'
Assert-True -Condition ($licenseText -match [regex]::Escape('contact the developer')) -Message 'LICENSE must mention the developer contact path.'
Assert-True -Condition ($contributingText -match [regex]::Escape('contact-first')) -Message 'CONTRIBUTING.md must define the contact-first contribution model.'
Assert-True -Condition ($contributingText -match [regex]::Escape('CHANGELOG.md')) -Message 'CONTRIBUTING.md must require release-doc alignment.'
Assert-True -Condition ($supportText -match [regex]::Escape('README.md')) -Message 'SUPPORT.md must route users to the main docs first.'
Assert-True -Condition ($supportText -match [regex]::Escape('SECURITY.md')) -Message 'SUPPORT.md must route sensitive reports to SECURITY.md.'
Assert-True -Condition ($securityText -match [regex]::Escape('do not open a public GitHub issue')) -Message 'SECURITY.md must forbid public vulnerability reporting.'
Assert-True -Condition ($codeOfConductText -match [regex]::Escape('respectful')) -Message 'CODE_OF_CONDUCT.md must define respectful participation.'
Assert-True -Condition ($readmeText -match [regex]::Escape('This repository is distributed under the custom non-commercial license')) -Message 'README.md must summarize the custom non-commercial license.'
Assert-True -Condition ($readmeText -match [regex]::Escape('commercial licensing and sponsorship discussions should be directed to the developer')) -Message 'README.md must mention the sponsorship/contact path.'
Assert-True -Condition ($readmeText -match [regex]::Escape('English-normalized')) -Message 'README.md must describe the English-normalized prompt-history policy.'
Assert-True -Condition ($readmeText -match [regex]::Escape('Very short approval/confirmation/follow-up prompts are not auto-recorded.')) -Message 'README.md must describe the short follow-up prompt-history exclusion.'
Assert-True -Condition ($readmeText -match [regex]::Escape('All other substantive prompts are recorded.')) -Message 'README.md must describe the substantive prompt-history recording rule.'
Assert-True -Condition ($readmeText -match [regex]::Escape('Task-only constants should stay in the owning task script')) -Message 'README.md must explain the task-local configuration policy.'
Assert-True -Condition ($readmeText -match [regex]::Escape('task --save-app-state --vm-update-task=115')) -Message 'README.md must include the task save-app-state example.'
Assert-True -Condition ($readmeText -match [regex]::Escape('task --restore-app-state --vm-update-task=115')) -Message 'README.md must include the task restore-app-state example.'
Assert-True -Condition ($readmeText -match [regex]::Escape('task --save-app-state --source=lm --user=.current.')) -Message 'README.md must include the local save-app-state example.'
Assert-True -Condition ($readmeText -match [regex]::Escape('task --restore-app-state --target=lm --user=.current.')) -Message 'README.md must include the local restore-app-state example.'
Assert-True -Condition ($readmeText -match [regex]::Escape('.\cg.cmd --version')) -Message 'README.md must include the --version example.'
Assert-True -Condition ($readmeText -match [regex]::Escape('backup-app-states/<task-name>/')) -Message 'README.md must document the task-adjacent backup-app-states root.'
Assert-True -Condition ($readmeText -match [regex]::Escape('verify-report.json')) -Message 'README.md must document the restore verify report.'
Assert-True -Condition ($readmeText -match [regex]::Escape('Managed app-state save and restore target only the `manager` and `assistant` OS profiles.')) -Message 'README.md must describe the managed app-state profile-target contract.'
Assert-True -Condition ($readmeText -match [regex]::Escape('init and update restore flows both reuse the same shared per-task app-state post-process over SSH; init defers replay until SSH is reachable and update replays immediately over SSH')) -Message 'README.md must document the SSH-only VM app-state replay contract.'
Assert-True -Condition (-not ($readmeText -match [regex]::Escape('init routes it through Azure Run Command and update routes it through SSH'))) -Message 'README.md must not keep the retired run-command app-state replay wording.'
Assert-True -Condition ($readmeText -match [regex]::Escape('task --run-vm-init 01')) -Message 'README.md must include the task run-vm-init example.'
Assert-True -Condition ($readmeText -match [regex]::Escape('task --run-vm-update 10002')) -Message 'README.md must include the task run-vm-update example.'
Assert-True -Condition ($readmeText -match [regex]::Escape('connect --ssh')) -Message 'README.md must document connect --ssh.'
Assert-True -Condition ($readmeText -match [regex]::Escape('connect --rdp')) -Message 'README.md must document connect --rdp.'
Assert-True -Condition ($readmeText -match [regex]::Escape('exec --command')) -Message 'README.md must document exec --command.'
Assert-True -Condition ($readmeText -match [regex]::Escape('SELECTED_COMPANY_WEB_ADDRESS')) -Message 'README.md must document SELECTED_COMPANY_WEB_ADDRESS.'
Assert-True -Condition ($readmeText -match [regex]::Escape('SELECTED_COMPANY_EMAIL_ADDRESS')) -Message 'README.md must document SELECTED_COMPANY_EMAIL_ADDRESS.'
Assert-True -Condition ($readmeText -match [regex]::Escape('SELECTED_VM_NAME')) -Message 'README.md must document SELECTED_VM_NAME.'
Assert-True -Condition ($readmeText -match [regex]::Escape('{SELECTED_VM_NAME}')) -Message 'README.md must document the {SELECTED_VM_NAME} naming placeholder.'
Assert-True -Condition ($readmeText -match [regex]::Escape('__SELECTED_VM_NAME__')) -Message 'README.md must document the __SELECTED_*__ task placeholder contract.'
Assert-True -Condition ($readmeText -match [regex]::Escape('SELECTED_COMPANY_NAME is required for the Windows business public desktop shortcut flow.')) -Message 'README.md must document the current Windows shortcut validation wording.'
Assert-True -Condition ($readmeText -match [regex]::Escape('`-h`, `--help`')) -Message 'README.md must document the -h and --help aliases together.'
Assert-True -Condition ($readmeText -match [regex]::Escape('--user=manager --test')) -Message 'README.md must document the automated --test examples for connection commands.'
Assert-True -Condition ($readmeText -match [regex]::Escape('password-bearing `.env` values are redacted')) -Message 'README.md must document show redaction for password-bearing values.'
Assert-True -Condition ($readmeText -match [regex]::Escape('`create` now stays dedicated to one fresh managed resource group plus one fresh managed VM; use `delete` and then `create` when a destructive rebuild is intentional.')) -Message 'README.md must describe create as fresh-only.'
Assert-True -Condition ($readmeText -match [regex]::Escape('`initialize` runs initial guest bootstrap on an existing managed VM; `update` runs non-program maintenance tasks without recreating or redeploying Azure resources.')) -Message 'README.md must describe the separated initialize and update flows.'
Assert-True -Condition ($readmeText -match [regex]::Escape('Purpose: review, edit, validate, preview, and save the supported `.env` contract through one interactive frontend.')) -Message 'README.md must describe configure as the interactive .env frontend.'
Assert-True -Condition ($readmeText -match [regex]::Escape('recovers softly for blank-permitted fields, including clearing `SELECTED_RESOURCE_GROUP` when no managed resource groups exist, and blocks save only when create-critical values remain unresolved')) -Message 'README.md must describe configure soft recovery and create-critical save blocking.'
Assert-True -Condition ($readmeText -match [regex]::Escape('Purpose: print read-only managed inventory sections for clagnos-tagged resource groups and resources.')) -Message 'README.md must describe list as a read-only inventory command.'
Assert-True -Condition ($readmeText -match [regex]::Escape('Azure CLI sign-in is strictly required for Azure-touching commands.')) -Message 'README.md must document the az login requirement.'
Assert-True -Condition ($readmeText -match [regex]::Escape('`configure` can open without Azure sign-in, but its Azure-backed pickers stay read-only until `az login` is available.')) -Message 'README.md must document the configure exception.'
Assert-True -Condition ($readmeText -match [regex]::Escape('Azure subscription selection precedence is: CLI `--subscription-id` / `-s` -> `.env` `SELECTED_AZURE_SUBSCRIPTION_ID` -> active Azure CLI subscription.')) -Message 'README.md must document subscription precedence.'
Assert-True -Condition ($readmeText -match [regex]::Escape('`SELECTED_AZURE_SUBSCRIPTION_ID`: optional repo-local default Azure subscription id for Azure-touching commands')) -Message 'README.md must document SELECTED_AZURE_SUBSCRIPTION_ID.'
Assert-True -Condition ($readmeText -match [regex]::Escape('`-s`, `--subscription-id=<subscription-guid>`: target Azure subscription for every Azure-touching command; successful CLI usage also writes `SELECTED_AZURE_SUBSCRIPTION_ID` into `.env`.')) -Message 'README.md must document the subscription global option.'
Assert-True -Condition ($readmeText -match [regex]::Escape('Auto `create` succeeds when CLI overrides or `.env` `SELECTED_*` values plus the platform defaults resolve platform, VM name, Azure region, and VM size.')) -Message 'README.md must document strict create auto options.'
Assert-True -Condition ($readmeText -match [regex]::Escape('Auto `update` resolves its target from CLI overrides first, then `.env` `SELECTED_RESOURCE_GROUP` and `SELECTED_VM_NAME`')) -Message 'README.md must document strict update auto options.'
Assert-True -Condition ($readmeText -match [regex]::Escape('Reboot-signaling tasks restart the VM immediately, wait for the required transport recovery, and then resume from the next task. The `update` stage retains its Windows final restart after the non-program maintenance stage; isolated `task --run-vm-update` reruns skip that workflow-only final restart.')) -Message 'README.md must document the task-immediate and workflow-only final Windows vm-update restart behavior.'
Assert-True -Condition ($readmeText -match [regex]::Escape('isolated `task --run-vm-update` reruns skip that workflow-only final restart')) -Message 'README.md must document that isolated vm-update task reruns skip the workflow-only final restart.'
Assert-True -Condition ($readmeText -match [regex]::Escape('Windows Store-backed isolated `task --run-vm-update` reruns append `10003-create-public-desktop-shortcuts` automatically after the selected Store app task so Public Desktop shortcuts refresh in the same diagnostic run.')) -Message 'README.md must document the isolated Store-task shortcut refresh follow-up.'
Assert-True -Condition ($readmeText -match [regex]::Escape('if `--windows` or `--linux` is omitted, interactive mode asks for the VM OS type first and then scopes size, disk, and image defaults to that selection')) -Message 'README.md must document the interactive create OS prompt.'
Assert-True -Condition ($readmeText -match [regex]::Escape('Interactive `create` reviews the resource group and VM deployment steps; `initialize` and `update` have their own task-stage reviews.')) -Message 'README.md must document lifecycle-specific review checkpoints.'
Assert-True -Condition ($readmeText -match [regex]::Escape('`configure` and `vm-summary` stay visible in `create` and `update` flows, even when partial step selection skips interior stages.')) -Message 'README.md must document the always-visible configure/vm-summary rule.'
Assert-True -Condition ($readmeText -match [regex]::Escape('`vm-init` relays the full guest transcript back to the local clagnos console as soon as each task completes, while `vm-update` streams guest stdout/stderr live over SSH while the task is still running.')) -Message 'README.md must document the guest output relay contract.'
Assert-True -Condition ($readmeText -match [regex]::Escape('Managed resource group ids use a global `gX` suffix that increments across all managed groups, regardless of region.')) -Message 'README.md must document global gX naming.'
Assert-True -Condition ($readmeText -match [regex]::Escape('Managed resource ids use a global `nX` suffix that increments across all generated managed resources and is never reused by another managed resource of any type.')) -Message 'README.md must document global nX naming.'
Assert-True -Condition ($readmeText -match [regex]::Escape('`create` never reuses an existing managed resource group or existing managed resource names, and `update` never falls through to an implicit fresh-create path.')) -Message 'README.md must reject create reuse and implicit update create behavior.'
Assert-True -Condition ($readmeText -match [regex]::Escape('`list` gives a read-only managed inventory view across groups and resource types')) -Message 'README.md must explain the list inventory outcome.'
Assert-True -Condition ($readmeText -match [regex]::Escape('`configure` gives a safe interactive frontend for every supported `.env` key')) -Message 'README.md must explain the configure interactive frontend outcome.'
Assert-True -Condition ($readmeText -match [regex]::Escape('interactive mode prompts for Azure subscription first when `--subscription-id` is omitted')) -Message 'README.md must document the interactive subscription prompt for create/update.'
Assert-True -Condition ($readmeText -match [regex]::Escape('Azure-read-only output; `--subscription-id` / `-s` only changes the subscription context and persists `SELECTED_AZURE_SUBSCRIPTION_ID` when it comes from the CLI')) -Message 'README.md must explain list subscription persistence clearly.'
Assert-True -Condition ($readmeText -match [regex]::Escape('Azure single-VM APIs do not expose a separate nested-virtualization toggle')) -Message 'README.md must document the nested virtualization control model accurately.'
Assert-True -Condition ($readmeText -match [regex]::Escape('builtin `initial` task folders, builtin `normal` task folders, local task folders from `local/`, then builtin `final` task folders')) -Message 'README.md must document the natural task execution order.'
Assert-True -Condition ($readmeText -match [regex]::Escape('VM_ENABLE_HIBERNATION')) -Message 'README.md must document VM_ENABLE_HIBERNATION.'
Assert-True -Condition ($readmeText -match [regex]::Escape('VM_ENABLE_NESTED_VIRTUALIZATION')) -Message 'README.md must document VM_ENABLE_NESTED_VIRTUALIZATION.'
Assert-True -Condition ($readmeText -match [regex]::Escape('tools/pyssh/ssh_client.py')) -Message 'README.md must document the default PYSSH client path.'
Assert-True -Condition ($readmeText -match [regex]::Escape('.github/workflows/quality-gate.yml')) -Message 'README.md must mention the GitHub Actions quality gate workflow.'
Assert-True -Condition ($readmeText -match [regex]::Escape('For a release push, the job is not finished until the pushed `main` SHA completes this workflow green.')) -Message 'README.md must document the post-push GitHub Actions release gate.'
Assert-True -Condition ($readmeText -match [regex]::Escape('The local hook path blocks obvious contact-style values, concrete identity leaks, and non-placeholder sensitive config drift before commits and pushes are shared.')) -Message 'README.md must explain the local sensitive-content guardrail.'
Assert-True -Condition ($readmeText -match [regex]::Escape('.\tests\sensitive-content-check.ps1')) -Message 'README.md must document the sensitive-content check entrypoint.'
Assert-True -Condition ($readmeText -match [regex]::Escape('### Live Release Acceptance')) -Message 'README.md must define the live release-acceptance section.'
Assert-True -Condition ($readmeText -match [regex]::Escape('confirm `clagnos do --vm-action=status --vm-name=<vm-name>` reports the VM as started')) -Message 'README.md must require a started-state check in the live release gate.'
Assert-True -Condition ($readmeText -match [regex]::Escape('<task-number>-verb-noun-target/')) -Message 'README.md must define the normalized task folder contract.'
Assert-True -Condition ($readmeText -match [regex]::Escape('01-99')) -Message 'README.md must describe the initial task-number band.'
Assert-True -Condition ($readmeText -match [regex]::Escape('101-999')) -Message 'README.md must describe the normal task-number band.'
Assert-True -Condition ($readmeText -match [regex]::Escape('1001-9999')) -Message 'README.md must describe the local task-number band.'
Assert-True -Condition ($readmeText -match [regex]::Escape('10001-10099')) -Message 'README.md must describe the final task-number band.'
Assert-True -Condition ($readmeText -match [regex]::Escape('The folder name defines the task identity, the same-named script defines the executable body, and `task.json` defines ordering, enable state, timeout, assets, and app-state capture coverage.')) -Message 'README.md must define the portable task-folder contract.'
Assert-True -Condition ($readmeText -match [regex]::Escape('local-only tasks under `local/` are discovered from disk dynamically')) -Message 'README.md must document local-only disk discovery.'
Assert-True -Condition ($readmeText -match [regex]::Escape('local-only tasks under `local/disabled/` remain disabled by location')) -Message 'README.md must document local-only disabled placement.'
Assert-True -Condition ($readmeText -match [regex]::Escape('missing `priority`: default to the filename task number when available, otherwise `1000`')) -Message 'README.md must document the task-folder priority fallback.'
Assert-True -Condition ($readmeText -match [regex]::Escape('missing `timeout`: default to `180`')) -Message 'README.md must document the task-folder timeout fallback.'
Assert-True -Condition ($readmeText -match [regex]::Escape('<task-folder>/app-state/app-state.zip')) -Message 'README.md must document the task-local app-state zip path.'
Assert-True -Condition ($readmeText -match [regex]::Escape('Prompt-history headings use `### YYYY-MM-DD HH:MM UTC`.')) -Message 'README.md must require UTC prompt-history headings.'
Assert-True -Condition ($roadmapText -match [regex]::Escape('business value')) -Message 'roadmap.md must be framed around business value.'
Assert-True -Condition ($preCommitText -match [regex]::Escape('tests/pre-commit-release-doc-check.ps1')) -Message '.githooks/pre-commit must run the release-doc pre-commit check.'
Assert-True -Condition ($commitMsgText -match [regex]::Escape('tests/sensitive-content-check.ps1')) -Message '.githooks/commit-msg must run the sensitive-content check.'
Assert-True -Condition ($sensitiveContentCheckText -match [regex]::Escape('VM_ADMIN_PASS')) -Message 'sensitive-content-check.ps1 must validate the .env.example admin-password placeholder.'
Assert-True -Condition ($sensitiveContentCheckText -match [regex]::Escape('VM_ASSISTANT_PASS')) -Message 'sensitive-content-check.ps1 must validate the .env.example assistant-password placeholder.'
Assert-True -Condition ($sensitiveContentCheckText -match [regex]::Escape('SELECTED_EMPLOYEE_EMAIL_ADDRESS')) -Message 'sensitive-content-check.ps1 must validate the SELECTED_EMPLOYEE_EMAIL_ADDRESS placeholder.'
Assert-True -Condition ($sensitiveContentCheckText -match [regex]::Escape('log --all --format=%B')) -Message 'sensitive-content-check.ps1 must scan reachable commit messages.'
Assert-True -Condition ($workflowText -match [regex]::Escape('tests\code-quality-check.ps1')) -Message 'quality-gate.yml must run tests/code-quality-check.ps1.'
Assert-True -Condition ($preCommitCheckText -match [regex]::Escape('CHANGELOG.md')) -Message 'pre-commit-release-doc-check.ps1 must require CHANGELOG.md.'
Assert-True -Condition ($preCommitCheckText -match [regex]::Escape('release-notes.md')) -Message 'pre-commit-release-doc-check.ps1 must require release-notes.md.'
Assert-True -Condition ($preCommitCheckText -match [regex]::Escape('docs/prompt-history.md')) -Message 'pre-commit-release-doc-check.ps1 must exempt docs/prompt-history.md from recursive release-doc enforcement.'
Assert-True -Condition ($workflowText -match [regex]::Escape('tests\powershell-compatibility-check.ps1')) -Message 'quality-gate.yml must use tests/powershell-compatibility-check.ps1.'
Assert-True -Condition ($workflowText -match [regex]::Escape('tests\clagnos-smoke-tests.ps1')) -Message 'quality-gate.yml must run the non-live smoke contract suite.'
Assert-True -Condition (-not ($workflowText -match [regex]::Escape('tests\powershell-matrix.ps1'))) -Message 'quality-gate.yml must not reference the removed powershell-matrix.ps1 file.'

$legacyTokens = @('SSH_PORT','TASK_OUTCOME_MODE','SERVER_NAME','VM_USER','VM_PASS','NAMING_TEMPLATE_ACTIVE','clagnos config ','substep mode','--single-step','--from-step','--to-step')
foreach ($legacyToken in $legacyTokens) {
    if ($legacyToken -match '^[A-Z0-9_]+$') {
        $pattern = ('(?<![A-Za-z0-9_]){0}(?![A-Za-z0-9_])' -f [regex]::Escape($legacyToken))
    }
    else {
        $pattern = [regex]::Escape($legacyToken)
    }

    Assert-True -Condition (-not ($readmeText -match $pattern)) -Message ("README.md must not contain legacy token '{0}'." -f $legacyToken)
    Assert-True -Condition (-not ($agentsText -match $pattern)) -Message ("AGENTS.md must not contain legacy token '{0}'." -f $legacyToken)
}

Assert-True -Condition (-not ($readmeText -match [regex]::Escape('### `group`'))) -Message 'README.md must not document the removed group command.'
Assert-True -Condition (-not ($readmeText -match [regex]::Escape('.\cg.cmd group'))) -Message 'README.md must not keep removed group command examples.'
Assert-True -Condition (-not ($agentsText -match [regex]::Escape('Current public commands are: `configure`, `create`, `update`, `group`'))) -Message 'AGENTS.md must not keep the removed group command in the public command list.'
Assert-True -Condition (-not ($readmeText -match [regex]::Escape('### `ssh`'))) -Message 'README.md must not document ssh as a standalone command.'
Assert-True -Condition (-not ($readmeText -match [regex]::Escape('### `rdp`'))) -Message 'README.md must not document rdp as a standalone command.'
Assert-True -Condition (-not ($readmeText -match [regex]::Escape('.\cg.cmd ssh'))) -Message 'README.md must not keep retired ssh command examples.'
Assert-True -Condition (-not ($readmeText -match [regex]::Escape('.\cg.cmd rdp'))) -Message 'README.md must not keep retired rdp command examples.'
Assert-True -Condition (-not ($readmeText -match [regex]::Escape('exec --init-task'))) -Message 'README.md must not keep retired exec --init-task examples.'
Assert-True -Condition (-not ($readmeText -match [regex]::Escape('exec --update-task'))) -Message 'README.md must not keep retired exec --update-task examples.'
Assert-True -Condition (-not ($agentsText -match [regex]::Escape('Current public commands are: `configure`, `create`, `update`, `list`, `show`, `do`, `task`, `exec`, `ssh`, `rdp`, `move`, `resize`, `set`, `delete`, `help`'))) -Message 'AGENTS.md must not keep ssh or rdp in the current public command list.'
Assert-True -Condition (-not ($readmeText -match [regex]::Escape('# clagnos-task-meta: {...}'))) -Message 'README.md must not keep the retired task-meta comment contract.'
Assert-True -Condition (-not ($readmeText -match '(?<!backup-)app-states/<task-name>')) -Message 'README.md must not keep the retired stage-local app-states path.'
Assert-True -Condition (-not ($agentsText -match '(?<!backup-)app-states/<task-name>')) -Message 'AGENTS.md must not keep the retired stage-local app-states path.'
Assert-True -Condition (-not ($promptHistoryText -match [regex]::Escape('TRT'))) -Message 'docs/prompt-history.md must not keep TRT timestamps.'

$oldHookInstallerPattern = [regex]::Escape('install-git-hooks.ps1')
Assert-True -Condition (-not ($readmeText -match $oldHookInstallerPattern)) -Message 'README.md must not mention install-git-hooks.ps1.'
Assert-True -Condition (-not ($agentsText -match $oldHookInstallerPattern)) -Message 'AGENTS.md must not mention install-git-hooks.ps1.'
Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $RepoRoot 'tools\install-git-hooks.ps1'))) -Message 'tools/install-git-hooks.ps1 must not remain in the repository.'

$maintainedEnglishDocs = @(
    $agentsPath,
    $readmePath,
    $licensePath,
    $contributingPath,
    $supportPath,
    $securityPath,
    $codeOfConductPath,
    $changelogPath,
    $releaseNotesPath,
    $roadmapPath,
    $promptHistoryPath
)
foreach ($docPath in @($maintainedEnglishDocs)) {
    $docText = Get-Content -LiteralPath $docPath -Raw
    $languageAuditText = [string]$docText
    if ([System.IO.Path]::GetFileName($docPath) -in @('CHANGELOG.md','release-notes.md','prompt-history.md')) {
        foreach ($literalLabel in @('q1EkşiSözlük','EkşiSözlük','Ekşi Sözlük','r13ÇiçekSepeti Business','r14ÇiçekSepeti Personal','r13Ã‡iÃ§ekSepeti Business','ÇiçekSepeti')) {
            $languageAuditText = $languageAuditText.Replace([string]$literalLabel, 'approved literal display label')
        }
    }
    Assert-True -Condition (-not (Test-ContainsTurkishLetters -Text $languageAuditText)) -Message ("Maintained document must stay English-only outside preserved literal display labels: {0}" -f [System.IO.Path]::GetFileName($docPath))
}

$versionHeaderPattern = '(?m)^## \[(\d{4}\.\d{1,2}\.\d{1,2}\.(\d+))\] - \d{4}-\d{2}-\d{2}$'
$changelogMatches = [regex]::Matches($changelogText, $versionHeaderPattern)
Assert-True -Condition ($changelogMatches.Count -gt 0) -Message 'CHANGELOG.md must contain versioned headings.'

$currentCommitCount = [int](& git -C $RepoRoot rev-list --count HEAD)
$allowedCurrentCounts = @($currentCommitCount, ($currentCommitCount + 1))
$topVersionCount = [int]$changelogMatches[0].Groups[2].Value
Assert-True -Condition ($allowedCurrentCounts -contains $topVersionCount) -Message ("Top changelog version count must match HEAD or HEAD+1. Actual: {0}; allowed: {1}" -f $topVersionCount, ($allowedCurrentCounts -join ', '))

$releaseHeaderMatch = [regex]::Match($releaseNotesText, '(?m)^## Release (\d{4}\.\d{1,2}\.\d{1,2}\.(\d+)) - \d{4}-\d{2}-\d{2}$')
Assert-True -Condition $releaseHeaderMatch.Success -Message 'release-notes.md must contain a versioned release heading.'
$releaseVersionCount = [int]$releaseHeaderMatch.Groups[2].Value
Assert-True -Condition ($topVersionCount -eq $releaseVersionCount) -Message 'CHANGELOG.md and release-notes.md must use the same current version count.'

$userPromptCount = ([regex]::Matches($promptHistoryText, [regex]::Escape('**User Prompt**'))).Count
$assistantSummaryCount = ([regex]::Matches($promptHistoryText, [regex]::Escape('**Assistant Summary**'))).Count
Assert-True -Condition ($userPromptCount -gt 0) -Message 'docs/prompt-history.md must contain at least one user prompt entry.'
Assert-True -Condition ($assistantSummaryCount -gt 0) -Message 'docs/prompt-history.md must contain at least one assistant summary entry.'
Assert-True -Condition ($userPromptCount -eq $assistantSummaryCount) -Message 'docs/prompt-history.md must keep user prompt and assistant summary counts aligned.'
Assert-True -Condition (-not ($promptHistoryText -match [regex]::Escape('No final summary was recorded for this turn.'))) -Message 'docs/prompt-history.md must not contain incomplete summary placeholders.'
Assert-True -Condition ($promptHistoryText -match [regex]::Escape('Timestamp format: UTC.')) -Message 'docs/prompt-history.md must declare UTC timestamps.'
Assert-True -Condition (($promptHistoryText -match '(?m)^### \d{4}-\d{2}-\d{2} \d{2}:\d{2} UTC\r?$')) -Message 'docs/prompt-history.md must contain UTC timestamp headings.'

Write-Host 'Documentation contract checks passed.' -ForegroundColor Green
