# Shared CLI help helpers.

function Get-ProdicloudValidCommandList {
    return @('configure', 'create', 'initialize', 'update', 'list', 'show', 'do', 'task', 'package', 'component', 'connect', 'move', 'resize', 'set', 'exec', 'delete', 'help')
}

function Write-ProdicloudHelpLines {
    param([string[]]$Lines)

    foreach ($line in @($Lines)) {
        Write-Host $line
    }
}

function Show-ProdicloudCommandHelp {
    param(
        [string]$Topic = '',
        [switch]$Overview
    )

    if ($Overview) {
        Show-ProdicloudCommandHelpOverview
        return
    }

    Show-ProdicloudCommandHelpDetailed -Topic $Topic
}

function Show-ProdicloudCommandHelpOverview {
    Write-ProdicloudHelpLines @(
        'prodicloud quick help'
        'Usage: prodicloud <command> [--option value] [--option=value]'
        ''
        'Commands (full details: prodicloud help <command>):'
        '  configure  Open the interactive global prodicloud.env editor and validate saved settings safely.'
        '  create     Create a fresh managed resource group, network, and VM.'
        '  initialize Run vm-init tasks on one existing managed virtual computer.'
        '  update     Normalize the VM public DNS label and run non-package maintenance tasks on one managed VM.'
        '  list       List managed resource groups and managed Azure resources by type.'
        '  show       Print system and configuration dump for resource groups and VMs.'
        '  do         Apply one VM lifecycle action or print current VM state.'
        '  task       List tasks, enable/disable one task, run one task, or save/restore task app-state.'
        '  package    Check, install, update, or uninstall a catalogued VM package.'
        '  component  Manage Prodicloud-owned Azure resource components.'
        '  connect    Launch SSH/RDP clients or a Windows PowerShell remoting session for a managed VM.'
        '  move       Move an existing VM to another Azure region.'
        '  resize     Change VM size or expand the managed OS disk for an existing VM.'
        '  set        Apply hibernation and validate or store nested virtualization settings.'
        '  exec       Open an interactive SSH shell or run one remote command.'
        '  delete     Delete selected managed resources and linked dependencies.'
        '  help       Show detailed docs (all commands or one command).'
        ''
        'Global options:'
        '  --version                  Print the current prodicloud release version and exit.'
        '  --auto[=true|false]         Auto mode (create/initialize/update/delete only).'
        '  --perf[=true|false]         Print timing metrics.'
        '  --windows / --linux         Force VM platform where supported (create/initialize/update/exec/resize/package).'
        '  -g, --group                 Target resource group where required.'
        '  -v, --vm-name               Target VM name where required.'
        '  -s, --subscription-id       Target Azure subscription for Azure-touching commands.'
        '  -c, --command               Remote one-shot command text for exec.'
        '  -f, --file                  Local script file to run remotely through exec.'
        '  -q, --quiet                 Exec-only remote-output suppression; local Doing progress remains visible.'
        '  -h, --help                  Show this overview or command-specific help.'
        "  Azure CLI sign-in via 'az login' is required for Azure-touching commands."
        "  configure opens without az login; Azure-backed configure fields require az login to edit or verify."
        ''
        'Quick examples:'
        '  prodicloud --version'
        '  prodicloud create --auto'
        '  prodicloud initialize --group <resource-group> --vm-name <vm-name>'
        '  prodicloud update --auto'
        '  prodicloud task --list --vm-update'
        '  prodicloud task --run-vm-init 01 --group <resource-group> --vm-name <vm-name>'
        '  prodicloud task --run-vm-update 10002 --group <resource-group> --vm-name <vm-name>'
        '  prodicloud task --save-app-state --vm-update-task=115 --group <resource-group> --vm-name <vm-name>'
        '  prodicloud task --save-app-state --package=visual-studio-code --package-catalog=builtin --group <resource-group> --vm-name <vm-name>'
        '  prodicloud task --save-app-state --source=lm --user=.current. --vm-update-task=115 --windows'
        '  prodicloud task --restore-app-state --target=lm --user=.current. --vm-update-task=115 --windows'
        '  prodicloud exec --command "Get-Date" --group <resource-group> --vm-name <vm-name>'
        '  prodicloud exec --file .\tools\scripts\sample-remote.ps1 --group <resource-group> --vm-name <vm-name>'
        '  prodicloud exec --group <resource-group> --vm-name <vm-name>'
        '  prodicloud connect --ssh --vm-name <vm-name> --test'
        '  prodicloud connect --rdp --vm-name <vm-name> --user assistant'
        '  prodicloud do --vm-action=redeploy --group <resource-group> --vm-name <vm-name>'
        '  prodicloud delete --target group --group <resource-group> --yes'
    )
}

function Show-ProdicloudCommandHelpDetailed {
    param([string]$Topic)

    $validCommands = Get-ProdicloudValidCommandList
    $topicText = [string]$Topic
    $topicName = $topicText.Trim().ToLowerInvariant()

    if ([string]::IsNullOrWhiteSpace($topicName)) {
        Write-ProdicloudHelpLines @(
            'prodicloud detailed help'
            'Usage: prodicloud <command> [--option value] [--option=value]'
            ''
            'Common options:'
            '  --version                # print the current prodicloud release version and exit'
            '  --auto[=true|false]      # create/initialize/update/delete only'
            '  --perf[=true|false]'
            '  --windows[=true|false]   # create/initialize/update/exec/resize/package'
            '  --linux[=true|false]     # create/initialize/update/exec/resize/package'
            '  -g, --group'
            '  -v, --vm-name'
            '  -s, --subscription-id'
            '  -c, --command'
            '  -f, --file'
            '  -q, --quiet              # suppress remote exec chatter; keep local Doing progress'
            '  -h, --help'
            "  Azure CLI sign-in via 'az login' is required for Azure-touching commands."
            "  configure opens without az login; Azure-backed configure fields require az login to edit or verify."
            ''
            'Command reference:'
            '  configure  : interactive global settings editor with validation and next-create preview'
            '  create     : fresh infrastructure and VM deployment flow'
            '  initialize : vm-init tasks for one existing managed VM'
            '  update     : non-package vm-update maintenance flow'
            '  list       : managed inventory output'
            '  show       : system and configuration dump'
            '  do         : lifecycle and repair actions'
            '  task       : task inventory/history, enable/disable, isolated task runs, task app-state save/restore'
            '  package    : catalogued package status, install/update, and uninstall'
            '  component  : managed Azure component CRUD and dependency-aware deletion'
            '  connect    : connect --ssh / --rdp / --powershell plus --test'
            '  move       : managed region move'
            '  resize     : VM-size or disk expand guidance'
            '  set        : hibernation and nested virtualization settings'
            '  exec       : remote command or interactive shell only'
            '  delete     : resource deletion by target scope'
            ''
            'For per-command docs: prodicloud help <configure|create|initialize|update|list|show|do|task|package|component|connect|move|resize|set|exec|delete>'
        )
        return
    }

    if ($validCommands -notcontains $topicName) {
        Throw-FriendlyError `
            -Detail ("Unknown help topic '{0}'." -f $topicText) `
            -Code 2 `
            -Summary 'Unknown help topic.' `
            -Hint 'Use prodicloud help or prodicloud help <configure|create|initialize|update|list|show|do|task|package|component|connect|move|resize|set|exec|delete>.'
    }

    switch ($topicName) {
        'configure' {
            Write-ProdicloudHelpLines @(
                'Command: configure'
                'Description: open the interactive global prodicloud.env editor, validate global values, preview the next create naming plan, and save the supported global contract.'
                'Usage:'
                '  prodicloud configure [--perf]'
                'Examples:'
                '  prodicloud configure'
                'Notes: configure is interactive-only and edits global prodicloud.env keys. It stages edits until final confirmation and shows a next-create preview. VM-specific values remain in each <vm-name>.env profile. configure opens without az login; Azure-backed fields stay read-only until Azure validation is available.'
            )
            return
        }
        'create' {
            Write-ProdicloudHelpLines @(
                'Command: create'
                'Description: create one fresh managed resource group, required network resources, and one fresh managed VM. Run guest tasks separately.'
                'Usage:'
                '  prodicloud create [--windows|--linux] [--subscription-id <subscription-id>] [--perf]'
                '  prodicloud create --auto [--subscription-id <subscription-id>] [--perf]'
                '  prodicloud create --auto --windows --vm-name <vm-name> --vm-region <azure-region> --vm-size <vm-sku> [--subscription-id <subscription-id>] [--perf]'
                '  prodicloud create --auto --linux --vm-name <vm-name> --vm-region <azure-region> --vm-size <vm-sku> [--subscription-id <subscription-id>] [--perf]'
                '  prodicloud create --step <step> [--subscription-id <subscription-id>]'
                '  prodicloud create --step-from <step> [--subscription-id <subscription-id>]'
                '  prodicloud create --step-to <step> [--subscription-id <subscription-id>]'
                'Default steps: configure, group, network, vm-deploy, vm-summary'
                'Examples:'
                '  prodicloud create --auto -s <subscription-guid>'
                '  prodicloud create --auto --windows --vm-name <vm-name> --vm-region <azure-region> --vm-size <vm-sku> -s <subscription-guid>'
                '  prodicloud initialize --group <resource-group> --vm-name <vm-name>'
                'Allowed steps: configure, group, network, vm-deploy, vm-summary'
                'Notes: create targets a fresh managed resource group, its initial network resources, and one fresh VM. It never reuses existing resource groups or names and stops after the read-only VM summary; run initialize for vm-init tasks and use package for catalogued software. Interactive mode prompts for Azure subscription when --subscription-id is omitted, asks for VM OS type first when --windows/--linux is omitted, proposes the next global gX name plus globally unique nX resource ids, and asks yes/no/cancel only before group creation and VM deployment. Auto mode runs from the fully resolved selection set: platform, VM name, Azure region, and platform VM size must resolve from CLI overrides or global DEFAULT_* create values before Azure mutation. Resolved VM settings and credentials are stored in the matching <vm-name>.env profile. Use initialize and update for guest stages; use do for explicit lifecycle and repair actions. vm-summary always renders, even for partial step windows. For a destructive rebuild, run delete first and then create again.'
            )
            return
        }
        'initialize' {
            Write-ProdicloudHelpLines @(
                'Command: initialize'
                'Description: run the platform vm-init task stage for one existing managed virtual computer.'
                'Usage:'
                '  prodicloud initialize [--group <resource-group>] [--vm-name <vm-name>] [--subscription-id <subscription-id>] [--windows|--linux] [--auto] [--perf] [--reset-managed-user-passwords]'
                'Examples:'
                '  prodicloud initialize --group <resource-group> --vm-name <vm-name>'
                'Notes: initialize never creates Azure resources and runs only enabled vm-init tasks. Interactive mode prompts for Azure subscription when --subscription-id is omitted. Existing managed-user passwords are preserved by default. --reset-managed-user-passwords is interactive-only and requires typing RESET MANAGED USER PASSWORDS before that VC profile passwords are applied to both accounts.'
            )
            return
        }
        'update' {
            Write-ProdicloudHelpLines @(
                'Command: update'
                'Description: normalize the managed Public IP DNS label to the VM name, then run enabled non-package vm-update maintenance tasks.'
                'Usage:'
                '  prodicloud update [--windows|--linux] [--group <resource-group>] [--vm-name <vm-name>] [--subscription-id <subscription-id>] [--perf]'
                '  prodicloud update --auto [--subscription-id <subscription-id>] [--perf]'
                '  prodicloud update --auto --group <resource-group> --vm-name <vm-name> [--subscription-id <subscription-id>] [--perf]'
                '  prodicloud update --step <step> [--subscription-id <subscription-id>]'
                '  prodicloud update --step-from <step> [--subscription-id <subscription-id>]'
                '  prodicloud update --step-to <step> [--subscription-id <subscription-id>]'
                'Allowed steps: configure, vm-update, vm-summary'
                'Examples:'
                '  prodicloud update --group <resource-group>'
                '  prodicloud update --auto -s <subscription-guid>'
                '  prodicloud update --auto --group <resource-group> --vm-name <vm-name> -s <subscription-guid>'
                'Notes: update requires an existing managed resource group and VM. Before vm-update tasks, it checks the VM-name Public IP DNS label, updates only the DNS label when needed, verifies the FQDN, and records the value in the matching VC profile. It does not create, redeploy, or initialize Azure resources. Interactive mode prompts for Azure subscription when --subscription-id is omitted and asks yes/no/cancel only before the vm-update stage. Auto mode runs from the resolved managed target: CLI overrides win, otherwise ACTIVE_VM_NAME selects the VC profile containing the target group and VM name. Single-VM resolution remains available for an explicitly selected managed group. Reboot-signaling maintenance tasks restart the VM immediately and wait for recovery. The Windows update workflow retains its final restart after the non-package maintenance tasks. vm-summary always renders, even for partial step windows.'
            )
            return
        }
        'list' {
            Write-ProdicloudHelpLines @(
                'Command: list'
                'Description: print read-only managed inventory sections for prodicloud-tagged resource groups and resources.'
                'Usage:'
                '  prodicloud list [--type <group,vm,disk,vnet,subnet,nic,ip,nsg,nsg-rule>] [--group <resource-group>] [--subscription-id <subscription-id>] [--perf]'
                'Examples:'
                '  prodicloud list'
                '  prodicloud list --type group,vm -s <subscription-guid>'
                '  prodicloud list --type nsg,nsg-rule --group <resource-group>'
                'Notes: list is Azure-read-only, supports --type and --group for managed inventory output, and keeps a deterministic managed-section order. The group section shows each group location, provisioning state, and active selection. --type uses comma-separated values. --group is an exact managed resource-group filter. Without --type, list prints all supported managed inventory sections in deterministic order.'
            )
            return
        }
        'show' {
            Write-ProdicloudHelpLines @(
                'Command: show'
                'Description: print a full system and configuration report for managed resource groups and VMs, with an optional redacted JSON export.'
                'Usage:'
                '  prodicloud show [--subscription-id <subscription-id>] [--export-json <path>] [--overwrite] [--perf]'
                '  prodicloud show --group <resource-group> [--vm-name <vm-name>] [--subscription-id <subscription-id>] [--export-json <path>] [--overwrite]'
                'Examples:'
                '  prodicloud show'
                '  prodicloud show --group <resource-group> --vm-name <vm-name> -s <subscription-guid>'
                '  prodicloud show --group <resource-group> --vm-name <vm-name> --export-json .\reports\vm.json'
                'Notes: password-bearing VC profile values are redacted in rendered and exported reports. JSON export refuses to overwrite an existing file unless --overwrite is provided. When show can resolve exactly one managed VM target, it also prints a read-only target-derived configuration section using actual Azure state without writing either config file. When the VM is running, nested virtualization is shown from guest validation evidence.'
            )
            return
        }
        'do' {
            Write-ProdicloudHelpLines @(
                'Command: do'
                'Description: apply one VM lifecycle action or print the current VM lifecycle state.'
                'Usage:'
                '  prodicloud do [--group <resource-group>] [--vm-name <vm-name>] [--vm-action=<status|start|resume|restart|reset|shutdown|stop|shutdown-deallocate|power-off|power-off-deallocate|deallocate|hibernate-deallocate|hibernate-stop|reapply|redeploy>] [--subscription-id <subscription-id>] [--perf]'
                'Examples:'
                '  prodicloud do --vm-action=status --vm-name <vm-name>'
                '  prodicloud do --vm-action=reapply --group <resource-group> --vm-name <vm-name>'
                '  prodicloud do --vm-action=redeploy --group <resource-group> --vm-name <vm-name>'
                '  prodicloud do --vm-action=hibernate-stop --group <resource-group> --vm-name <vm-name>'
                '  prodicloud do --vm-action=hibernate-deallocate --group <resource-group> --vm-name <vm-name>'
                '  prodicloud do --vm-action=power-off --group <resource-group> --vm-name <vm-name>'
                '  prodicloud do --vm-action=shutdown-deallocate --group <resource-group> --vm-name <vm-name>'
                '  prodicloud do --vm-action=power-off-deallocate --group <resource-group> --vm-name <vm-name>'
                '  prodicloud do --vm-action=reset --group <resource-group> --vm-name <vm-name>'
                "Notes: shutdown asks the guest OS to stop and leaves the VM allocated; stop is the equivalent existing spelling. shutdown-deallocate runs graceful stop, verifies the stopped state, then deallocates; if retried after a partial failure, it resumes from the current stopped state. power-off uses 'az vm stop --skip-shutdown' to skip graceful guest shutdown and leaves the VM allocated; power-off-deallocate then verifies the stopped state and deallocates. resume starts only a hibernated VM. reset is the force-reboot action and uses 'az vm restart --force', which Azure implements by redeploying an unresponsive VM rather than simulating a physical reset button. hibernate-stop is Windows-only: it uses SSH to run 'shutdown /h /f' and waits until the guest is no longer running without Azure deallocation. hibernate-deallocate uses Azure's deallocation-based hibernate path. Reapply calls 'az vm reapply' and then prints refreshed VM status; unlike the power actions, it remains available when provisioning is not currently succeeded. Redeploy calls 'az vm redeploy', waits for provisioning recovery, and restores the original started/stopped lifecycle state when Azure reports it deterministically."
            )
            return
        }
        'task' {
            Write-ProdicloudHelpLines @(
                'Command: task'
                'Description: list discovered init/update tasks, view local task-run history, enable/disable tasks, run one task in isolation, or save/restore task-owned app-state.'
                'Usage:'
                '  prodicloud task --list [--vm-init] [--vm-update] [--disabled] [--windows|--linux] [--perf]'
                '  prodicloud task --history'
                '  prodicloud task --enable --vm-init-task <task-number|task-name> [--windows|--linux]'
                '  prodicloud task --disable --vm-update-task <task-number|task-name> [--windows|--linux]'
                '  prodicloud task --run-vm-init <task-number|task-name> [--group <resource-group>] [--vm-name <vm-name>] [--subscription-id <subscription-id>] [--windows|--linux] [--perf]'
                '  prodicloud task --run-vm-update <task-number|task-name> [--group <resource-group>] [--vm-name <vm-name>] [--subscription-id <subscription-id>] [--windows|--linux] [--perf]'
                '  prodicloud task --save-app-state --vm-init-task <task-number|task-name> [--source <vm|lm>] [--user <.all.|.current.|user[,user...]>] [--group <resource-group>] [--vm-name <vm-name>] [--subscription-id <subscription-id>] [--windows|--linux] [--perf]'
                '  prodicloud task --save-app-state --vm-update-task <task-number|task-name> [--source <vm|lm>] [--user <.all.|.current.|user[,user...]>] [--group <resource-group>] [--vm-name <vm-name>] [--subscription-id <subscription-id>] [--windows|--linux] [--perf]'
                '  prodicloud task --restore-app-state --vm-init-task <task-number|task-name> [--target <vm|lm>] [--user <.all.|.current.|user[,user...]>] [--group <resource-group>] [--vm-name <vm-name>] [--subscription-id <subscription-id>] [--windows|--linux] [--perf]'
                '  prodicloud task --restore-app-state --vm-update-task <task-number|task-name> [--target <vm|lm>] [--user <.all.|.current.|user[,user...]>] [--group <resource-group>] [--vm-name <vm-name>] [--subscription-id <subscription-id>] [--windows|--linux] [--perf]'
                '  prodicloud task --save-app-state --package <package-id> --package-catalog <builtin|custom> [--source <vm|lm>] [--user <.all.|.current.|user[,user...]>] [--group <resource-group>] [--vm-name <vm-name>] [--subscription-id <subscription-id>] [--windows|--linux]'
                '  prodicloud task --restore-app-state --package <package-id> --package-catalog <builtin|custom> [--target <vm|lm>] [--user <.all.|.current.|user[,user...]>] [--group <resource-group>] [--vm-name <vm-name>] [--subscription-id <subscription-id>] [--windows|--linux]'
                'Examples:'
                '  prodicloud task --list --vm-update'
                '  prodicloud task --history'
                '  prodicloud task --disable --vm-update-task 114 --windows'
                '  prodicloud task --enable --vm-update-task 114 --windows'
                '  prodicloud task --run-vm-init 01 --group <resource-group> --vm-name <vm-name>'
                '  prodicloud task --run-vm-update 10002 --group <resource-group> --vm-name <vm-name>'
                '  prodicloud task --save-app-state --vm-update-task=115 --group <resource-group> --vm-name <vm-name> -s <subscription-guid>'
                '  prodicloud task --save-app-state --source=lm --user=.current. --vm-update-task=115 --windows'
                '  prodicloud task --restore-app-state --target=lm --user=.current. --vm-update-task=115 --windows'
                '  prodicloud task --restore-app-state --target=vm --user=assistant --vm-update-task=115 --group <resource-group> --vm-name <vm-name>'
                'Notes: --list, --history, --enable, and --disable are local task-catalog operations and do not require az login. --history reads the git-ignored repo-local .logs/task-runs.jsonl file. Enable/disable updates only the selected tasks.toml boolean after a typed confirmation and leaves the task folder and task.json unchanged. Use `package --action enable|disable` for package availability. Package app-state uses --package plus --package-catalog and shares the same VM/local-machine profile rules. --run-vm-init uses Azure run-command and replays the full guest transcript after each task completes. --run-vm-update uses the task.json transport (SSH by default; selected Windows tasks may use WinRM) and streams guest output live; it still honors task-signaled immediate restarts and does not perform the workflow-only final vm-update restart. --save-app-state defaults to --source=vm and --restore-app-state defaults to --target=vm. Both default to --user=.all.. VM save/restore is SSH-based and remains limited to the managed manager/assistant profiles; vm-init app-state replay defers until SSH is ready. Local save/restore is Windows-host-only and writes a restore journal plus backup root before local replay.'
            )
            return
        }
        'package' {
            Write-ProdicloudHelpLines @(
                'Command: package'
                'Description: manage packages in the isolated builtin or custom catalog and install them on one managed VC.'
                'Usage:'
                '  prodicloud package --action list --catalog <builtin|custom> [--group <resource-group>] [--vm-name <vm-name>] [--windows|--linux]'
                '  prodicloud package --action status|install|repair|update|uninstall|reinstall --catalog <builtin|custom> --package <package-id> --group <resource-group> --vm-name <vm-name> [--windows|--linux] [--yes]'
                '  prodicloud package --action setup-all --catalog all --group <resource-group> --vm-name <vm-name> [--windows|--linux] [--yes]'
                '  prodicloud package --action enable|disable --catalog <builtin|custom> --package <package-id> [--windows|--linux]'
                '  Windows package transport: set PACKAGE_TRANSPORT=ssh or PACKAGE_TRANSPORT=winrm in the VC profile; DEFAULT_PACKAGE_TRANSPORT in prodicloud.env seeds new VCs. The selected transport is strict; failures do not fall back silently.'
                'Examples:'
                '  prodicloud package --action list --catalog builtin --group <resource-group> --vm-name <vm-name> --windows'
                '  prodicloud package --action install --catalog builtin --package visual-studio-code --group <resource-group> --vm-name <vm-name> --windows'
                '  prodicloud package --action disable --catalog custom --package my-tool --windows'
                'Notes: vm-packages/builtin/<platform> and vm-packages/custom/<platform> are separate catalogs, and each owns a tasks.toml availability list. Every package directory contains package.json and its installer script. operationTimeoutSeconds assigns bounded budgets for status, install, repair, update, uninstall, and reinstall; if reinstall is omitted, its budget defaults to the bounded sum of uninstall and install. The selected-VC menu offers p: setup all program packages and m: manage program packages. Setup-all reviews both catalogs, applies enabled packages in dependency order, and reports independent failures; the direct setup-all action uses --catalog=all and asks for SETUP ALL confirmation unless --yes is supplied. Manage Programs labels rows [builtin] or [custom]. Custom packages use the same validated status, uninstall, assets, app-state, and timeout manifest contract. Enable/disable changes only the selected tasks.toml boolean after typed confirmation, affects future operations in this repository, and does not change an installed package on a VC. Status and uninstall remain available while disabled; install/repair/update/reinstall requires an enabled package. Install is a no-op when a package is already present; repair pins the detected installed version and fails before mutation when that version or a safe provider strategy is unavailable. Update is the vendor-version upgrade path and does not downgrade a current package. Reinstall requires REINSTALL confirmation and forcefully runs uninstall followed by install. WinRM package actions stream guest progress, sample CPU/RAM/network/disk activity every 15 seconds, retry once after 60 seconds without measurable progress, and enforce a finite operation deadline.'
            )
            return
        }
        'component' {
            Write-ProdicloudHelpLines @(
                'Command: component'
                'Description: list, inspect, create, update, or dependency-aware delete Prodicloud-managed Azure resource components.'
                'Usage:'
                '  prodicloud component --action list|show|create|update|delete --type <group|vm|disk|vnet|subnet|nic|ip|nsg|nsg-rule> [--group <resource-group>] [--name <component-name>]'
                'Examples:'
                '  prodicloud component --action list --type disk --group <resource-group>'
                '  prodicloud component --action update --type nsg-rule --group <resource-group>'
                '  prodicloud component --action delete --type nic --group <resource-group>'
                'Notes: component creation and property changes use type-specific validated prompts. Deletion shows the linked resource chain and requires DELETE ALL for a multi-resource plan. Azure delete is verified; provider purge and name reuse are best-effort where supported.'
            )
            return
        }
        'connect' {
            Write-ProdicloudHelpLines @(
                'Command: connect'
                'Description: launch SSH/RDP clients or a PowerShell remoting session for a managed VM, or test connection readiness.'
                'Usage:'
                '  prodicloud connect --ssh [--group <resource-group>] [--vm-name <vm-name>] [--user <manager|assistant>] [--test] [--subscription-id <subscription-id>] [--perf]'
                '  prodicloud connect --rdp [--group <resource-group>] [--vm-name <vm-name>] [--user <manager|assistant>] [--test] [--subscription-id <subscription-id>] [--perf]'
                '  prodicloud connect --powershell [--group <resource-group>] [--vm-name <vm-name>] [--user <manager|assistant>] [--command <PowerShell-command> | --test] [--subscription-id <subscription-id>] [--perf]'
                'Examples:'
                '  prodicloud connect --ssh --vm-name <vm-name> -s <subscription-guid>'
                '  prodicloud connect --ssh --group <resource-group> --vm-name <vm-name> --user assistant'
                '  prodicloud connect --ssh --group <resource-group> --vm-name <vm-name> --user manager --test'
                '  prodicloud connect --rdp --vm-name <vm-name> --user assistant'
                '  prodicloud connect --rdp --group <resource-group> --vm-name <vm-name> --user manager --test'
                '  prodicloud connect --powershell --vm-name <vm-name> --user manager'
                '  prodicloud connect --powershell --command "Get-Service WinRM" --vm-name <vm-name>'
                '  prodicloud connect --powershell --test --vm-name <vm-name>'
                'Notes: the VM must already be running. Use exactly one of --ssh, --rdp, or --powershell. PowerShell remoting is Windows-only and uses WinRM Negotiate on TCP 5985; Windows init task 06 enables WinRM and grants both managed user accounts remote-management access. Without --command, --powershell opens a line-oriented remote PowerShell prompt; --test authenticates and runs an identity probe.'
            )
            return
        }
        'move' {
            Write-ProdicloudHelpLines @(
                'Command: move'
                'Description: move VM deployment to a target Azure region.'
                'Usage:'
                '  prodicloud move --group <resource-group> --vm-name <vm-name> --vm-region <azure-region> [--subscription-id <subscription-id>]'
                'Examples:'
                '  prodicloud move --group <resource-group> --vm-name <vm-name> --vm-region swedencentral -s <subscription-guid>'
                'Notes: region move uses a deallocate -> snapshot-copy -> target rebuild -> target health-check -> old-group-delete flow with rollback safeguards.'
            )
            return
        }
        'resize' {
            Write-ProdicloudHelpLines @(
                'Command: resize'
                'Description: resize VM hardware, or expand/shrink an attached managed disk in the current region.'
                'Usage:'
                '  prodicloud resize [--group <resource-group>] [--vm-name <vm-name>] [--vm-size <vm-sku>] [--subscription-id <subscription-id>] [--windows|--linux] [--perf]'
                '  prodicloud resize [--group <resource-group>] [--vm-name <vm-name>] [--disk-name <attached-disk-name>] --disk-size <size>MB|GB|TB --expand [--subscription-id <subscription-id>] [--windows|--linux] [--perf]'
                '  prodicloud resize [--group <resource-group>] [--vm-name <vm-name>] [--disk-name <attached-disk-name>] --disk-size <size>MB|GB|TB --shrink [--yes] [--subscription-id <subscription-id>] [--windows|--linux] [--perf]'
                'Examples:'
                '  prodicloud resize --group <resource-group> --vm-name <vm-name> --vm-size Standard_D4as_v5'
                '  prodicloud resize --group <resource-group> --vm-name <vm-name> --disk-size 196GB --expand'
                '  prodicloud resize --group <resource-group> --vm-name <vm-name> --disk-name <attached-data-disk> --disk-size 64GB --shrink --yes'
                "Notes: resize stays in the current region. --disk-name selects one attached managed disk; omitting it selects the OS disk. --disk-size requires exactly one intent flag: --expand or --shrink. Expansion updates Azure disk capacity and then the guest partition/filesystem over the configured SSH/WinRM channel. Shrink uses a same-region temporary vc-helper, requires at least 10 GiB between guest-used data and the requested size, and supports only verified disk/filesystem layouts. The helper uses Standard_D8ds_v5 with a 128 GiB StandardSSD_LRS OS disk created without an OS-disk tier update. Eligible Standard SSD copies use source-capacity/requested-target-capacity P40 temporary disks. The old disk is deleted only after replacement and guest checks pass; Azure does not shrink a managed disk in place. --yes authorizes shrink from auto mode."
            )
            return
        }
        'set' {
            Write-ProdicloudHelpLines @(
                'Command: set'
                'Description: apply hibernation changes and validate or store nested virtualization intent in the selected VC profile.'
                'Usage:'
                '  prodicloud set --group <resource-group> --vm-name <vm-name> --hibernation on|off [--subscription-id <subscription-id>]'
                '  prodicloud set --group <resource-group> --vm-name <vm-name> --nested-virtualization on|off [--subscription-id <subscription-id>]'
                '  prodicloud set --group <resource-group> --vm-name <vm-name> --hibernation on|off --nested-virtualization on|off [--subscription-id <subscription-id>]'
                'Examples:'
                '  prodicloud set --group <resource-group> --vm-name <vm-name> --hibernation off'
                '  prodicloud set --group <resource-group> --vm-name <vm-name> --nested-virtualization off'
                'Notes: hibernation is changed through Azure. The nested-virtualization option stores Prodicloud intent in the selected <vm-name>.env profile because this workflow has no separate per-VM Azure hardware-exposure toggle. Turning it on requires a running VM and validates guest CPU virtualization extensions; it does not install or configure Hyper-V inside the guest.'
            )
            return
        }
        'exec' {
            Write-ProdicloudHelpLines @(
                'Command: exec'
                'Description: open an interactive SSH shell on the target VM, or run one remote command over SSH.'
                'Usage:'
                '  prodicloud exec [--group <resource-group>] [--vm-name <vm-name>] [--subscription-id <subscription-id>] [--perf]'
                '  prodicloud exec --command "<remote-command>" [--quiet] [--group <resource-group>] [--vm-name <vm-name>] [--subscription-id <subscription-id>] [--perf]'
                '  prodicloud exec --file <script-file> [--quiet] [--group <resource-group>] [--vm-name <vm-name>] [--subscription-id <subscription-id>] [--perf]'
                '  prodicloud exec -c "<remote-command>" [-q] [--group <resource-group>] [--vm-name <vm-name>] [--subscription-id <subscription-id>] [--perf]'
                'Examples:'
                '  prodicloud exec --group <resource-group> --vm-name <vm-name>'
                '  prodicloud exec --command "Get-Date" --group <resource-group> --vm-name <vm-name>'
                '  prodicloud exec --file .\tools\scripts\sample-remote.ps1 --group <resource-group> --vm-name <vm-name>'
                '  prodicloud exec --quiet --command "Get-Date" --group <resource-group> --vm-name <vm-name>'
                '  prodicloud exec -c "uname -a" --group <resource-group> --vm-name <vm-name>'
                'Notes: exec is SSH-only. When no --command or --file is provided, it opens the interactive SSH shell for the actual target VM OS. When --command or --file is provided, it runs one one-shot remote command and returns the exit result. --quiet / -q is valid only together with --command / -c / --file and suppresses remote output chatter while local Doing progress and wait heartbeats remain visible.'
            )
            return
        }
        'delete' {
            Write-ProdicloudHelpLines @(
                'Command: delete'
                'Description: delete a managed resource scope after showing its dependency-aware deletion plan.'
                'Usage:'
                '  prodicloud delete --target <group|network|vm|disk> [--group <resource-group>] [--subscription-id <subscription-id>] [--yes]'
                'Examples:'
                '  prodicloud delete --target vm --group <resource-group> -s <subscription-guid>'
                '  prodicloud delete --target group --group <resource-group> --yes'
                'Notes: delete is Azure-touching and writes CLI-provided --subscription-id into SELECTED_AZURE_SUBSCRIPTION_ID.'
            )
            return
        }
        'help' {
            Write-ProdicloudHelpLines @(
                'Command: help'
                "Description: show quick overview or one command's detailed usage."
                'Usage:'
                '  prodicloud help'
                '  prodicloud help <configure|create|update|list|show|do|task|connect|move|resize|set|exec|delete>'
                'Examples:'
                '  prodicloud help'
                '  prodicloud help create'
                '  prodicloud help connect'
            )
            return
        }
    }
}
