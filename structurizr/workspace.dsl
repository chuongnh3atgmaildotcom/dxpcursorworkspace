workspace "DXC Deployment Automation" "C4 model and process views for DXC deployment automation (multi-repo)." {

    model {
        # --- Actors ---
        ci = person "CI/CD" "GitHub Actions or other caller that triggers code deployment"

        # --- Systems and boundaries ---
        # Boundary: dxc-deployment-automation repo (code + workflow)
        dxc = softwareSystem "DXC Deployment Automation" "PowerShell modules, runbooks, and build scripts (dxc-deployment-automation repo)." {
            workflow = container "Run Code Deployment Workflow" "_runCodeDeployment.yml" "GitHub Actions workflow; triggers automation account deployment."
            deploy_script = container "Invoke-AutomationAccountDeployment" "Invoke-AutomationAccountDeployment.ps1" "Orchestrates deployment: prepare account, upload modules, DSC, runbooks, schedules."
            update_module = container "Update-AutomationModule" "Update-AutomationModule.ps1" "Uploads internal (EpiDeploy, etc.) and external modules to storage and Automation Account."
            set_dsc = container "Set-AutomationDscConfiguration" "Set-AutomationDscConfiguration.ps1" "Imports and compiles DSC config; optionally syncs hybrid workers (DSC cycle)."
            prepare = container "Invoke-PrepareAutomationAccountDeployment" "Invoke-PrepareAutomationAccountDeployment.ps1" "Stops schedules, waits for running jobs, sets StartReleaseTime variable."
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
    }

    docs {
        "Process: Install EpiDeploy on Hybrid Runbook" "process-install-epideploy-hybrid-runbook.md"
    }
}
