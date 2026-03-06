// Process: Install EpiDeploy as custom module on Hybrid Runbook Worker
// Triggered by: dxc-deployment-automation/.github/workflows/_runCodeDeployment.yml
// See: process-install-epideploy-hybrid-runbook.md for per-step actors, triggers, actions, causality, artifacts, modes, boundaries.

dynamic * {
    title "Install EpiDeploy on Hybrid Runbook"
    description "Process triggered by Run Code Deployment workflow: deploy internal modules (EpiDeploy) to Azure Automation and make them available on Hybrid Runbook Workers."

    1: ci -> workflow "Triggers (workflow_call with automationAccount, runCodeDeployment, vars/secrets)"
    2: workflow -> deploy_script "Calls with SubscriptionId, AutomationAccountName, ResourceGroupName, ForceInternalModuleUpdate, BuildNumber, etc."
    3: deploy_script -> prepare "Calls to stop schedules, wait for running jobs, set StartReleaseTime"
    4: deploy_script -> update_module "Starts job: upload modules (EpiDeploy + external) to storage and Automation Account"
    5: update_module -> azure_automation.automation_account "Uploads module zips; registers modules in Automation Account"
    6: deploy_script -> set_dsc "Starts job: import/compile DSC config; optionally Invoke-HybridWorkerDscCycle"
    7: set_dsc -> azure_automation.automation_account "Imports DSC configuration; compiles"
    8: set_dsc -> azure_automation.hybrid_worker "Applies DSC / triggers sync (RestartHybridWorkers optional)"
    9: azure_automation.automation_account -> azure_automation.hybrid_worker "When runbook runs: dispatches job; worker loads EpiDeploy from account"
    autolayout lr
}
