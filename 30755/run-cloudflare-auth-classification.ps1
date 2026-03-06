# Run CloudFlare auth classification (script and CloudFlareModule are under Source)
# Usage: run from _workspace\30755 so the default path to dxc-deployment-automation resolves.

Set-Location $PSScriptRoot
.\Get-CloudFlareAuthClassification.ps1
