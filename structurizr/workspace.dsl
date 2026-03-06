workspace "DXC Deployment Automation" "C4 model and process views for DXC deployment automation (multi-repo)." {

    model {
        # --- Actors ---
        ci = person "CI/CD" "GitHub Actions or other caller that triggers code deployment"
        ops = person "Operator" "Uses PaaS Portal to manage deployments and add custom hostnames"

        # --- Systems and boundaries ---
        # Boundary: dxc-deployment-automation repo (code + workflow)
        dxc = softwareSystem "DXC Deployment Automation" "PowerShell modules, runbooks, and build scripts (dxc-deployment-automation repo)." {
            workflow = container "Run Code Deployment Workflow" "_runCodeDeployment.yml" "GitHub Actions workflow; triggers automation account deployment."
            deploy_script = container "Invoke-AutomationAccountDeployment" "Invoke-AutomationAccountDeployment.ps1" "Orchestrates deployment: prepare account, upload modules, DSC, runbooks, schedules."
            update_module = container "Update-AutomationModule" "Update-AutomationModule.ps1" "Uploads internal (EpiDeploy, etc.) and external modules to storage and Automation Account."
            set_dsc = container "Set-AutomationDscConfiguration" "Set-AutomationDscConfiguration.ps1" "Imports and compiles DSC config; optionally syncs hybrid workers (DSC cycle)."
            prepare = container "Invoke-PrepareAutomationAccountDeployment" "Invoke-PrepareAutomationAccountDeployment.ps1" "Stops schedules, waits for running jobs, sets StartReleaseTime variable."
        }

        # Boundary: PaaS (Portal, workers, saga)
        paas = softwareSystem "PaaS Portal" "PaaS repo: Portal, workers, runbook saga (configuration/policy + state)." {
            portal = container "PaaS Portal" "ASP.NET" "Web UI; add custom hostname, complete hostname, view runbook jobs."
            provisioning_worker = container "Provisioning Worker" "WorkerServiceBase" "Producer: handles provisioning messages; starts runbooks via RunbookManager (RunbookJobStart)."
            runbook_manager = container "RunbookManager" "RunbookManager.cs" "Producer component: creates RunbookJob record, sends RunbookJobStart; uses saga state (IRunbookJobRepository) and message transport (IBus)."
            message_bus = container "Message Bus" "Azure Service Bus" "Message transport: delivers RunbookJobStart, RunbookJobWaiting, RunbookJobInProgress, RunbookJobFinished/Failed."
            env_sync_worker = container "Environment Synchronization Worker" "WorkerServiceBase" "Consumer host: runs HandleRunbookSaga; consumes runbook messages."
            saga_handler = container "HandleRunbookSaga" "HandleRunbookSaga.cs" "Saga handler: IHandleMessage for RunbookJobStart/Stop/Resume/Waiting/InProgress/Finished/Failed; updates state, calls Azure Automation; uses distributed lock when required."
        }

        # Boundary: data and external systems
        mongodb = softwareSystem "MongoDB" "Saga state and locks." {
            saga_store = container "Saga state store" "runbookjobs collection" "Saga state persistence (RunbookJobRepository); RunbookJob entity."
            lock_store = container "Distributed lock store" "distributedlocks collection" "DistributedLockManager; optional resource lock per runbook type."
        }

        # Boundary: Azure (Automation Account + Hybrid Worker)
        azure_automation = softwareSystem "Azure Automation" "Automation Account, module registry, job queue, DSC." {
            automation_account = container "Automation Account" "Azure Automation Account" "Stores modules (e.g. EpiDeploy), runbooks, variables; dispatches jobs."
            hybrid_worker = container "Hybrid Runbook Worker" "Windows VM(s)" "Runs runbooks; loads custom modules from Automation Account when executing jobs."
        }

        # --- Relationships (define before use in dynamic view) ---
        ci -> workflow "Triggers"
        workflow -> deploy_script "Calls"
        deploy_script -> prepare "Calls"
        deploy_script -> update_module "Calls (job)"
        deploy_script -> set_dsc "Calls (job)"
        update_module -> azure_automation.automation_account "Uploads modules to"
        set_dsc -> azure_automation.automation_account "Imports DSC configuration to"
        set_dsc -> azure_automation.hybrid_worker "Applies DSC / triggers sync to"
        azure_automation.automation_account -> azure_automation.hybrid_worker "Dispatches runbook jobs to; provides modules to"

        ops -> paas.portal "Add custom hostname; complete hostname"
        paas.portal -> paas.message_bus "Sends CompleteCustomHostName (provisioning)"
        paas.provisioning_worker -> paas.message_bus "Consumes CompleteCustomHostName; sends RunbookJobStart"
        paas.provisioning_worker -> paas.runbook_manager "Calls (e.g. SetCloudflareBaselineRunbook.StartNewJob)"
        paas.runbook_manager -> mongodb.saga_store "Create/update RunbookJob (saga state)"
        paas.runbook_manager -> paas.message_bus "Send RunbookJobStart"
        paas.message_bus -> paas.env_sync_worker "Delivers RunbookJobStart, RunbookJobWaiting, etc."
        paas.env_sync_worker -> paas.saga_handler "Dispatches to"
        paas.saga_handler -> mongodb.saga_store "Load/save RunbookJob"
        paas.saga_handler -> mongodb.lock_store "TryLock/Refresh/Remove (ResourceLockName)"
        paas.saga_handler -> paas.message_bus "Send RunbookJobWaiting, RunbookJobInProgress, RunbookJobFinished/Failed"
        paas.saga_handler -> azure_automation.automation_account "StartJobAsync, GetJobAsync, StopJobAsync, GetJobStreamLogAsync (IAzureAutomationManager)"
        azure_automation.automation_account -> azure_automation.hybrid_worker "Dispatches job; runbook executes (e.g. Set-EPiCloudflareBaseline.ps1)"
    }

    views {
        systemContext dxc "System Context" {
            include *
            autolayout lr
        }
        container dxc "Containers" {
            include *
            autolayout lr
        }
        !include "process-install-epideploy-hybrid-runbook.dsl"
        !include "process-add-custom-hostname-runbook-saga.dsl"
    }

    docs {
        "Process: Install EpiDeploy on Hybrid Runbook" "process-install-epideploy-hybrid-runbook.md"
        "Process: Add custom hostname (runbook saga)" "process-add-custom-hostname-runbook-saga.md"
    }
}
