# Shared CLI help helpers.

function Get-ClagnosValidCommandList {
    return @('configure', 'create', 'initialize', 'update', 'list', 'show', 'do', 'task', 'program', 'component', 'connect', 'move', 'resize', 'set', 'exec', 'delete', 'help')
}

function Write-ClagnosHelpLines {
    param([string[]]$Lines)

    foreach ($line in @($Lines)) {
        Write-Host $line
    }
}

function Show-ClagnosCommandHelp {
    param(
        [string]$Topic = '',
        [switch]$Overview
    )

    if ($Overview) {
        Show-ClagnosCommandHelpOverview
        return
    }

    Show-ClagnosCommandHelpDetailed -Topic $Topic
}

function Show-ClagnosCommandHelpOverview {
    Write-ClagnosHelpLines @(
        'clagnos quick help'
        'Usage: clagnos <command> [--option value] [--option=value]'
        ''
        'Commands (full details: clagnos help <command>):'
        '  configure  Open the interactive .env editor and validate saved settings safely.'
        '  create     Create a fresh managed resource group, network, and VM.'
        '  initialize Run vm-init tasks on one existing managed virtual computer.'
        '  update     Run non-program maintenance tasks on one existing managed VM.'
        '  list       List managed resource groups and managed Azure resources by type.'
        '  show       Print system and configuration dump for resource groups and VMs.'
        '  do         Apply one VM lifecycle action or print current VM state.'
        '  task       List tasks, run one task, or save/restore one task app-state payload.'
        '  program    Check, install, update, or uninstall a catalogued VM program.'
        '  component  Manage Clagnos-owned Azure resource components.'
        '  connect    Launch SSH or RDP client/test for a managed VM.'
        '  move       Move an existing VM to another Azure region.'
        '  resize     Change VM size or expand the managed OS disk for an existing VM.'
        '  set        Apply hibernation and validate or store nested virtualization settings.'
        '  exec       Open an interactive SSH shell or run one remote command.'
        '  delete     Delete selected managed resources and linked dependencies.'
        '  help       Show detailed docs (all commands or one command).'
        ''
        'Global options:'
        '  --version                  Print the current clagnos release version and exit.'
        '  --auto[=true|false]         Auto mode (create/initialize/update/delete only).'
        '  --perf[=true|false]         Print timing metrics.'
        '  --windows / --linux         Force VM platform where supported.'
        '  -g, --group                 Target resource group where required.'
        '  -v, --vm-name               Target VM name where required.'
        '  -s, --subscription-id       Target Azure subscription for Azure-touching commands.'
        '  -c, --command               Remote one-shot command text for exec.'
        '  -f, --file                  Local script file to run remotely through exec.'
        '  -q, --quiet                 Exec-only quiet output mode for one-shot commands.'
        '  -h, --help                  Show this overview or command-specific help.'
        "  Azure CLI sign-in via 'az login' is required for Azure-touching commands."
        "  configure opens without az login; Azure-backed configure fields require az login to edit or verify."
        ''
        'Quick examples:'
        '  clagnos --version'
        '  clagnos create --auto'
        '  clagnos initialize --group <resource-group> --vm-name <vm-name>'
        '  clagnos update --auto'
        '  clagnos task --list --vm-update'
        '  clagnos task --run-vm-init 01 --group <resource-group> --vm-name <vm-name>'
        '  clagnos task --run-vm-update 10002 --group <resource-group> --vm-name <vm-name>'
        '  clagnos task --save-app-state --vm-update-task=115 --group <resource-group> --vm-name <vm-name>'
        '  clagnos task --save-app-state --source=lm --user=.current. --vm-update-task=115 --windows'
        '  clagnos task --restore-app-state --target=lm --user=.current. --vm-update-task=115 --windows'
        '  clagnos exec --command "Get-Date" --group <resource-group> --vm-name <vm-name>'
        '  clagnos exec --file .\tools\scripts\sample-remote.ps1 --group <resource-group> --vm-name <vm-name>'
        '  clagnos exec --group <resource-group> --vm-name <vm-name>'
        '  clagnos connect --ssh --vm-name <vm-name> --test'
        '  clagnos connect --rdp --vm-name <vm-name> --user assistant'
        '  clagnos do --vm-action=redeploy --group <resource-group> --vm-name <vm-name>'
        '  clagnos delete --target group --group <resource-group> --yes'
    )
}

function Show-ClagnosCommandHelpDetailed {
    param([string]$Topic)

    $validCommands = Get-ClagnosValidCommandList
    $topicText = [string]$Topic
    $topicName = $topicText.Trim().ToLowerInvariant()

    if ([string]::IsNullOrWhiteSpace($topicName)) {
        Write-ClagnosHelpLines @(
            'clagnos detailed help'
            'Usage: clagnos <command> [--option value] [--option=value]'
            ''
            'Common options:'
            '  --version                # print the current clagnos release version and exit'
            '  --auto[=true|false]      # create/initialize/update/delete only'
            '  --perf[=true|false]'
            '  --windows[=true|false]   # create/update/task/resize'
            '  --linux[=true|false]     # create/update/task/resize'
            '  -g, --group'
            '  -v, --vm-name'
            '  -s, --subscription-id'
            '  -c, --command'
            '  -f, --file'
            '  -q, --quiet              # exec one-shot quiet output only'
            '  -h, --help'
            "  Azure CLI sign-in via 'az login' is required for Azure-touching commands."
            "  configure opens without az login; Azure-backed configure fields require az login to edit or verify."
            ''
            'Command reference:'
            '  configure  : interactive .env editor with validation and next-create preview'
            '  create     : fresh infrastructure and VM deployment flow'
            '  initialize : vm-init tasks for one existing managed VM'
            '  update     : non-program vm-update maintenance flow'
            '  list       : managed inventory output'
            '  show       : system and configuration dump'
            '  do         : lifecycle and repair actions'
            '  task       : task list, isolated task runs, task app-state save/restore'
            '  program    : catalogued program status, install/update, and uninstall'
            '  component  : managed Azure component CRUD and dependency-aware deletion'
            '  connect    : connect --ssh / connect --rdp plus --test'
            '  move       : managed region move'
            '  resize     : VM-size or disk expand guidance'
            '  set        : hibernation and nested virtualization settings'
            '  exec       : remote command or interactive shell only'
            '  delete     : resource deletion by target scope'
            ''
            'For per-command docs: clagnos help <configure|create|initialize|update|list|show|do|task|program|component|connect|move|resize|set|exec|delete>'
        )
        return
    }

    if ($validCommands -notcontains $topicName) {
        Throw-FriendlyError `
            -Detail ("Unknown help topic '{0}'." -f $topicText) `
            -Code 2 `
            -Summary 'Unknown help topic.' `
            -Hint 'Use clagnos help or clagnos help <configure|create|initialize|update|list|show|do|task|program|component|connect|move|resize|set|exec|delete>.'
    }

    switch ($topicName) {
        'configure' {
            Write-ClagnosHelpLines @(
                'Command: configure'
                'Description: open the interactive .env editor, validate field values safely, preview the next create naming plan, and save the updated .env contract.'
                'Usage:'
                '  clagnos configure [--perf]'
                'Examples:'
                '  clagnos configure'
                'Notes: configure is interactive-only. It edits supported .env keys in sections, uses pickers for every finite or discoverable multi-option field, validates before save, stages changes in memory until final confirmation, and shows a next-create preview before writing .env. configure opens without az login, but Azure-backed fields become read-only and advise running az login when Azure validation is unavailable. Blank-permitted fields recover softly, and save is blocked only when create-critical values remain unresolved.'
            )
            return
        }
        'create' {
            Write-ClagnosHelpLines @(
                'Command: create'
                'Description: create one fresh managed resource group, required network resources, and one fresh managed VM. Run guest tasks separately.'
                'Usage:'
                '  clagnos create [--windows|--linux] [--subscription-id <subscription-id>] [--perf]'
                '  clagnos create --auto [--subscription-id <subscription-id>] [--perf]'
                '  clagnos create --auto --windows --vm-name <vm-name> --vm-region <azure-region> --vm-size <vm-sku> [--subscription-id <subscription-id>] [--perf]'
                '  clagnos create --auto --linux --vm-name <vm-name> --vm-region <azure-region> --vm-size <vm-sku> [--subscription-id <subscription-id>] [--perf]'
                '  clagnos create --step <step> [--subscription-id <subscription-id>]'
                '  clagnos create --step-from <step> [--subscription-id <subscription-id>]'
                '  clagnos create --step-to <step> [--subscription-id <subscription-id>]'
                'Default steps: configure, group, network, vm-deploy, vm-summary'
                'Examples:'
                '  clagnos create --auto -s <subscription-guid>'
                '  clagnos create --auto --windows --vm-name <vm-name> --vm-region <azure-region> --vm-size <vm-sku> -s <subscription-guid>'
                '  clagnos initialize --group <resource-group> --vm-name <vm-name>'
                'Notes: create always targets a fresh managed resource group and fresh managed resources for full runs. Interactive mode prompts for Azure subscription when --subscription-id is omitted, asks for VM OS type first when --windows/--linux is omitted, proposes the next global gX name plus globally unique nX resource ids, and asks yes/no/cancel review checkpoints only for group, vm-deploy, vm-init, and vm-update. Auto mode runs from the fully resolved selection set: CLI overrides win, otherwise .env SELECTED_* values plus the platform VM defaults must resolve platform, VM name, Azure region, and VM size. When a partial create window starts at vm-init, vm-update, or vm-summary, clagnos reuses the existing managed target created earlier instead of generating a new gX resource group name. Reboot-signaling vm-init and vm-update tasks restart the VM immediately, wait for recovery, and then continue with the next task. Windows vm-update also ends with one additional final restart before vm-summary. vm-summary starts with a read-only guest readback block and then prints the normal connection details. vm-summary always renders, even for partial step windows. For a destructive rebuild, run delete first and then create again.'
            )
            return
        }
        'initialize' {
            Write-ClagnosHelpLines @(
                'Command: initialize'
                'Description: run the platform vm-init task stage for one existing managed virtual computer.'
                'Usage:'
                '  clagnos initialize [--group <resource-group>] [--vm-name <vm-name>] [--subscription-id <subscription-id>] [--windows|--linux] [--auto] [--perf]'
                'Examples:'
                '  clagnos initialize --group <resource-group> --vm-name <vm-name>'
                'Notes: initialize never creates Azure resources and runs only enabled vm-init tasks. Task review and reboot recovery follow the shared stage contract.'
            )
            return
        }
        'update' {
            Write-ClagnosHelpLines @(
                'Command: update'
                'Description: run enabled non-program vm-update maintenance tasks on one existing managed VM.'
                'Usage:'
                '  clagnos update [--windows|--linux] [--group <resource-group>] [--vm-name <vm-name>] [--subscription-id <subscription-id>] [--perf]'
                '  clagnos update --auto [--subscription-id <subscription-id>] [--perf]'
                '  clagnos update --auto --group <resource-group> --vm-name <vm-name> [--subscription-id <subscription-id>] [--perf]'
                '  clagnos update --step <step> [--subscription-id <subscription-id>]'
                '  clagnos update --step-from <step> [--subscription-id <subscription-id>]'
                '  clagnos update --step-to <step> [--subscription-id <subscription-id>]'
                'Steps: configure, group, network, vm-deploy, vm-init, vm-update, vm-summary'
                'Examples:'
                '  clagnos update --group <resource-group>'
                '  clagnos update --auto -s <subscription-guid>'
                '  clagnos update --auto --group <resource-group> --vm-name <vm-name> -s <subscription-guid>'
                'Notes: update requires an existing managed resource group and an existing managed VM. Interactive mode prompts for Azure subscription when --subscription-id is omitted, selects only managed existing targets, and asks yes/no/cancel review checkpoints only for group, vm-deploy, vm-init, and vm-update. Auto mode runs from the resolved managed target: CLI overrides win, otherwise .env SELECTED_RESOURCE_GROUP and SELECTED_VM_NAME are used, with single-VM auto-resolution still allowed when the selected group contains exactly one VM. Existing VMs are redeployed after Azure create-or-update. Reboot-signaling vm-init and vm-update tasks restart the VM immediately, wait for recovery, and then continue with the next task. Windows vm-update also ends with one additional final restart before vm-summary, and vm-summary starts with a read-only guest readback block before the normal connection details. vm-summary always renders, even for partial step windows.'
            )
            return
        }
        'list' {
            Write-ClagnosHelpLines @(
                'Command: list'
                'Description: print read-only managed inventory sections for clagnos-tagged resource groups and resources.'
                'Usage:'
                '  clagnos list [--type <group,vm,disk,vnet,subnet,nic,ip,nsg,nsg-rule>] [--group <resource-group>] [--subscription-id <subscription-id>] [--perf]'
                'Examples:'
                '  clagnos list'
                '  clagnos list --type group,vm -s <subscription-guid>'
                '  clagnos list --type nsg,nsg-rule --group <resource-group>'
                'Notes: list is Azure-read-only, supports --type and --group for managed inventory output, and keeps a deterministic managed-section order. --type uses comma-separated values. --group is an exact managed resource-group filter. Without --type, list prints all supported managed inventory sections in deterministic order.'
            )
            return
        }
        'show' {
            Write-ClagnosHelpLines @(
                'Command: show'
                'Description: print a full system and configuration dump for app resource groups and VMs.'
                'Usage:'
                '  clagnos show [--subscription-id <subscription-id>] [--perf]'
                '  clagnos show --group <resource-group> [--vm-name <vm-name>] [--subscription-id <subscription-id>]'
                'Examples:'
                '  clagnos show'
                '  clagnos show --group <resource-group> --vm-name <vm-name> -s <subscription-guid>'
                'Notes: password-bearing .env values are redacted in the rendered report. When show can resolve exactly one managed VM target, it also prints a read-only target-derived configuration section using actual Azure state without writing .env. When the VM is running, nested virtualization is shown from guest validation evidence.'
            )
            return
        }
        'do' {
            Write-ClagnosHelpLines @(
                'Command: do'
                'Description: apply one VM lifecycle action or print the current VM lifecycle state.'
                'Usage:'
                '  clagnos do [--group <resource-group>] [--vm-name <vm-name>] [--vm-action=<status|start|restart|stop|deallocate|hibernate-deallocate|hibernate-stop|reapply|redeploy>] [--subscription-id <subscription-id>] [--perf]'
                'Examples:'
                '  clagnos do --vm-action=status --vm-name <vm-name>'
                '  clagnos do --vm-action=reapply --group <resource-group> --vm-name <vm-name>'
                '  clagnos do --vm-action=redeploy --group <resource-group> --vm-name <vm-name>'
                '  clagnos do --vm-action=hibernate-stop --group <resource-group> --vm-name <vm-name>'
                '  clagnos do --vm-action=hibernate-deallocate --group <resource-group> --vm-name <vm-name>'
                "Notes: hibernate-stop uses SSH to run 'shutdown /h /f' inside a running VM and waits until the guest is no longer running without Azure deallocation. hibernate-deallocate uses Azure's deallocation-based hibernate path. Reapply calls 'az vm reapply' and then prints refreshed VM status; unlike the power actions, it remains available when provisioning is not currently succeeded. Redeploy calls 'az vm redeploy', waits for provisioning recovery, and restores the original started/stopped lifecycle state when Azure reports it deterministically."
            )
            return
        }
        'task' {
            Write-ClagnosHelpLines @(
                'Command: task'
                'Description: list discovered init/update tasks, run one task in isolation, or save/restore one task-owned app-state payload against a VM or the local Windows machine.'
                'Usage:'
                '  clagnos task --list [--vm-init] [--vm-update] [--disabled] [--windows|--linux] [--perf]'
                '  clagnos task --run-vm-init <task-number|task-name> [--group <resource-group>] [--vm-name <vm-name>] [--subscription-id <subscription-id>] [--windows|--linux] [--perf]'
                '  clagnos task --run-vm-update <task-number|task-name> [--group <resource-group>] [--vm-name <vm-name>] [--subscription-id <subscription-id>] [--windows|--linux] [--perf]'
                '  clagnos task --save-app-state --vm-init-task <task-number|task-name> [--source <vm|lm>] [--user <.all.|.current.|user[,user...]>] [--group <resource-group>] [--vm-name <vm-name>] [--subscription-id <subscription-id>] [--windows|--linux] [--perf]'
                '  clagnos task --save-app-state --vm-update-task <task-number|task-name> [--source <vm|lm>] [--user <.all.|.current.|user[,user...]>] [--group <resource-group>] [--vm-name <vm-name>] [--subscription-id <subscription-id>] [--windows|--linux] [--perf]'
                '  clagnos task --restore-app-state --vm-init-task <task-number|task-name> [--target <vm|lm>] [--user <.all.|.current.|user[,user...]>] [--group <resource-group>] [--vm-name <vm-name>] [--subscription-id <subscription-id>] [--windows|--linux] [--perf]'
                '  clagnos task --restore-app-state --vm-update-task <task-number|task-name> [--target <vm|lm>] [--user <.all.|.current.|user[,user...]>] [--group <resource-group>] [--vm-name <vm-name>] [--subscription-id <subscription-id>] [--windows|--linux] [--perf]'
                'Examples:'
                '  clagnos task --list --vm-update'
                '  clagnos task --run-vm-init 01 --group <resource-group> --vm-name <vm-name>'
                '  clagnos task --run-vm-update 10002 --group <resource-group> --vm-name <vm-name>'
                '  clagnos task --save-app-state --vm-update-task=115 --group <resource-group> --vm-name <vm-name> -s <subscription-guid>'
                '  clagnos task --save-app-state --source=lm --user=.current. --vm-update-task=115 --windows'
                '  clagnos task --restore-app-state --target=lm --user=.current. --vm-update-task=115 --windows'
                '  clagnos task --restore-app-state --target=vm --user=assistant --vm-update-task=115 --group <resource-group> --vm-name <vm-name>'
                'Notes: --list is local-only and scans tracked plus local task trees with the same discovery rules used by init/update execution. --run-vm-init uses Azure run-command and replays the full guest transcript after each task completes. --run-vm-update uses the SSH task runner and streams guest stdout/stderr live; it still honors task-signaled immediate restarts, it does not perform the workflow-only final vm-update restart, and Windows Store-backed isolated reruns append `10003-create-public-desktop-shortcuts` so Public Desktop shortcuts refresh in the same task-run path. --save-app-state defaults to --source=vm and --restore-app-state defaults to --target=vm. Both default to --user=.all.. VM save/restore is SSH-based and remains limited to the managed manager/assistant profiles; vm-init app-state replay defers until SSH is ready. Local save/restore is Windows-host-only, reads or deploys only `<task-folder>/app-state/app-state.zip`, and writes a restore journal plus backup root before local replay.'
            )
            return
        }
        'program' {
            Write-ClagnosHelpLines @(
                'Command: program'
                'Description: inspect, install/update, or uninstall one platform-specific program declared by an enabled vm-update task.'
                'Usage:'
                '  clagnos program --action list [--group <resource-group>] [--vm-name <vm-name>] [--windows|--linux]'
                '  clagnos program --action status|install|uninstall --program <program-id> --group <resource-group> --vm-name <vm-name> [--windows|--linux] [--yes]'
                'Examples:'
                '  clagnos program --action list --group <resource-group> --vm-name <vm-name> --windows'
                '  clagnos program --action install --program visual-studio-code --group <resource-group> --vm-name <vm-name> --windows'
                'Notes: installations run the owning task synchronously. Status checks and uninstall actions come from validated task.json program metadata. Uninstall requires an explicit confirmation unless --yes is supplied.'
            )
            return
        }
        'component' {
            Write-ClagnosHelpLines @(
                'Command: component'
                'Description: list, inspect, create, update, or dependency-aware delete Clagnos-managed Azure resource components.'
                'Usage:'
                '  clagnos component --action list|show|create|update|delete --type <group|vm|disk|vnet|subnet|nic|ip|nsg|nsg-rule> [--group <resource-group>] [--name <component-name>]'
                'Examples:'
                '  clagnos component --action list --type disk --group <resource-group>'
                '  clagnos component --action update --type nsg-rule --group <resource-group>'
                '  clagnos component --action delete --type nic --group <resource-group>'
                'Notes: component creation and property changes use type-specific validated prompts. Deletion shows the linked resource chain and requires DELETE ALL for a multi-resource plan. Azure delete is verified; provider purge and name reuse are best-effort where supported.'
            )
            return
        }
        'connect' {
            Write-ClagnosHelpLines @(
                'Command: connect'
                'Description: launch Windows OpenSSH client or mstsc for a managed VM, or run connection tests without launching the client.'
                'Usage:'
                '  clagnos connect --ssh [--group <resource-group>] [--vm-name <vm-name>] [--user <manager|assistant>] [--test] [--subscription-id <subscription-id>] [--perf]'
                '  clagnos connect --rdp [--group <resource-group>] [--vm-name <vm-name>] [--user <manager|assistant>] [--test] [--subscription-id <subscription-id>] [--perf]'
                'Examples:'
                '  clagnos connect --ssh --vm-name <vm-name> -s <subscription-guid>'
                '  clagnos connect --ssh --group <resource-group> --vm-name <vm-name> --user assistant'
                '  clagnos connect --ssh --group <resource-group> --vm-name <vm-name> --user manager --test'
                '  clagnos connect --rdp --vm-name <vm-name> --user assistant'
                '  clagnos connect --rdp --group <resource-group> --vm-name <vm-name> --user manager --test'
                'Notes: the VM must already be running. connect --ssh uses Windows OpenSSH. connect --rdp uses cmdkey plus mstsc and is only available for Windows VMs. --test performs a non-interactive reachability/authentication check instead of launching the external client.'
            )
            return
        }
        'move' {
            Write-ClagnosHelpLines @(
                'Command: move'
                'Description: move VM deployment to a target Azure region.'
                'Usage:'
                '  clagnos move --group <resource-group> --vm-name <vm-name> --vm-region <azure-region> [--subscription-id <subscription-id>]'
                'Examples:'
                '  clagnos move --group <resource-group> --vm-name <vm-name> --vm-region swedencentral -s <subscription-guid>'
                'Notes: region move uses a deallocate -> snapshot-copy -> target rebuild -> target health-check -> old-group-delete flow with rollback safeguards.'
            )
            return
        }
        'resize' {
            Write-ClagnosHelpLines @(
                'Command: resize'
                'Description: resize VM SKU or expand the managed OS disk in the same region.'
                'Usage:'
                '  clagnos resize [--group <resource-group>] [--vm-name <vm-name>] [--vm-size <vm-sku>] [--subscription-id <subscription-id>] [--windows|--linux] [--perf]'
                '  clagnos resize [--group <resource-group>] [--vm-name <vm-name>] --disk-size <number>gb|mb --expand [--subscription-id <subscription-id>] [--windows|--linux] [--perf]'
                '  clagnos resize [--group <resource-group>] [--vm-name <vm-name>] --disk-size <number>gb|mb --shrink [--subscription-id <subscription-id>] [--windows|--linux] [--perf]'
                'Examples:'
                '  clagnos resize --group <resource-group> --vm-name <vm-name> --vm-size Standard_D4as_v5'
                '  clagnos resize --group <resource-group> --vm-name <vm-name> --disk-size 196gb --expand'
                '  clagnos resize --group <resource-group> --vm-name <vm-name> --disk-size 64gb --shrink'
                "Notes: resize stays in the current region. --vm-size changes the VM SKU. --disk-size requires exactly one intent flag: --expand or --shrink. --disk-size with --expand performs a supported managed OS disk growth. --disk-size with --shrink is a non-mutating guidance path that explains Azure's OS disk shrink limits and lists supported alternatives."
            )
            return
        }
        'set' {
            Write-ClagnosHelpLines @(
                'Command: set'
                'Description: apply hibernation changes and validate or store nested virtualization settings in .env.'
                'Usage:'
                '  clagnos set --group <resource-group> --vm-name <vm-name> --hibernation on|off [--subscription-id <subscription-id>]'
                '  clagnos set --group <resource-group> --vm-name <vm-name> --nested-virtualization on|off [--subscription-id <subscription-id>]'
                '  clagnos set --group <resource-group> --vm-name <vm-name> --hibernation on|off --nested-virtualization on|off [--subscription-id <subscription-id>]'
                'Examples:'
                '  clagnos set --group <resource-group> --vm-name <vm-name> --hibernation off'
                '  clagnos set --group <resource-group> --vm-name <vm-name> --nested-virtualization off'
                'Notes: hibernation is changed through Azure. Nested virtualization is governed by VM size and security type, so --nested-virtualization on validates guest readiness on a running VM and --nested-virtualization off saves the requested setting in .env because Azure does not expose a separate single-VM disable toggle.'
            )
            return
        }
        'exec' {
            Write-ClagnosHelpLines @(
                'Command: exec'
                'Description: open an interactive SSH shell on the target VM, or run one remote command over SSH.'
                'Usage:'
                '  clagnos exec [--group <resource-group>] [--vm-name <vm-name>] [--subscription-id <subscription-id>] [--perf]'
                '  clagnos exec --command "<remote-command>" [--quiet] [--group <resource-group>] [--vm-name <vm-name>] [--subscription-id <subscription-id>] [--perf]'
                '  clagnos exec --file <script-file> [--quiet] [--group <resource-group>] [--vm-name <vm-name>] [--subscription-id <subscription-id>] [--perf]'
                '  clagnos exec -c "<remote-command>" [-q] [--group <resource-group>] [--vm-name <vm-name>] [--subscription-id <subscription-id>] [--perf]'
                'Examples:'
                '  clagnos exec --group <resource-group> --vm-name <vm-name>'
                '  clagnos exec --command "Get-Date" --group <resource-group> --vm-name <vm-name>'
                '  clagnos exec --file .\tools\scripts\sample-remote.ps1 --group <resource-group> --vm-name <vm-name>'
                '  clagnos exec --quiet --command "Get-Date" --group <resource-group> --vm-name <vm-name>'
                '  clagnos exec -c "uname -a" --group <resource-group> --vm-name <vm-name>'
                'Notes: exec is SSH-only. When no --command or --file is provided, it opens the interactive SSH shell for the actual target VM OS. When --command or --file is provided, it runs one one-shot remote command and returns the exit result. --quiet / -q is valid only together with --command / -c / --file and prints only the remote command result.'
            )
            return
        }
        'delete' {
            Write-ClagnosHelpLines @(
                'Command: delete'
                'Description: delete a managed resource scope after showing its dependency-aware deletion plan.'
                'Usage:'
                '  clagnos delete --target <group|network|vm|disk> [--group <resource-group>] [--subscription-id <subscription-id>] [--yes]'
                'Examples:'
                '  clagnos delete --target vm --group <resource-group> -s <subscription-guid>'
                '  clagnos delete --target group --group <resource-group> --yes'
                'Notes: delete is Azure-touching and writes CLI-provided --subscription-id into SELECTED_AZURE_SUBSCRIPTION_ID.'
            )
            return
        }
        'help' {
            Write-ClagnosHelpLines @(
                'Command: help'
                "Description: show quick overview or one command's detailed usage."
                'Usage:'
                '  clagnos help'
                '  clagnos help <configure|create|update|list|show|do|task|connect|move|resize|set|exec|delete>'
                'Examples:'
                '  clagnos help'
                '  clagnos help create'
                '  clagnos help connect'
            )
            return
        }
    }
}
