---
name: CloudFlare auth classification
overview: Classify all CloudFlareModule Public cmdlets by auth method (legacy ApiKey-only vs backward-compatible ApiKey or ApiToken) and produce a single output file; identify any outliers.
todos: []
isProject: false
---

# CloudFlareModule Auth Classification Plan

## Summary of findings

**Auth patterns in the module**

- **Legacy:** Cmdlet has `$Email` and `$ApiKey` in its `param()` block and **no** `$ApiToken` (e.g. [Add-CFDNSRecord.ps1](dxc-deployment-automation/InternalModules/CloudFlareModule/Public/Add-CFDNSRecord.ps1)).
- **Backward-compatible:** Cmdlet has both `$ApiKey` (with `$Email`) and `$ApiToken`, typically via parameter sets (e.g. [Add-CFAccount.ps1](dxc-deployment-automation/InternalModules/CloudFlareModule/Public/Add-CFAccount.ps1), [Get-CFZoneSettings.ps1](dxc-deployment-automation/InternalModules/CloudFlareModule/Public/Get-CFZoneSettings.ps1)).
- **Outlier:** Cmdlet does not accept `$ApiKey` or `$ApiToken` (e.g. no auth parameters).

The private helper [GetCFApiRequestSplattingHash.ps1](dxc-deployment-automation/InternalModules/CloudFlareModule/Private/GetCFApiRequestSplattingHash.ps1) already supports both `UseApiKey` (Email + ApiKey) and `UseApiToken`; public cmdlets that support ApiToken pass it through when that parameter set is used.

**Verified counts (from codebase search)**

- **Backward-compatible (accept either ApiKey or ApiToken):** 7 cmdlets — `Add-CFAccount`, `Get-CFAdvancedCertificatePack`, `Get-CFCustomHostname`, `Get-CFDNSRecord`, `Get-CFDNSZone`, `Get-CFUniversalSSLSetting`, `Get-CFZoneSettings`.
- **Legacy (ApiKey only):** All other Public cmdlets that declare `$ApiKey` (and usually `$Email`) but do **not** declare `$ApiToken`. Grep found 43 files containing `$ApiKey`; of those, 7 also contain `$ApiToken`, so **36** are legacy from that set. The remaining **126** Public scripts (169 total − 43) do not contain the literal `$ApiKey` in the same way in the searched scope; many still take `Email` + `ApiKey` (e.g. `Add-CFDNSRecord`, `Add-CFDNSZone`, `Get-CFAccount`) but may appear in a different workspace or path in search. So the **definitive list** must be produced by a single pass over all Public scripts.

## Approach

Use a **one-time PowerShell script** that:

1. Iterates over all `Public/*.ps1` in [InternalModules/CloudFlareModule](dxc-deployment-automation/InternalModules/CloudFlareModule).
2. For each script:
  - Derives the command name from the file base name (e.g. `Add-CFDNSRecord.ps1` → `Add-CFDNSRecord`).
  - Reads the file and detects whether the **param block** (or script) contains a parameter named `ApiToken` and/or `ApiKey` (e.g. via regex on `param(...)` or `[String] $ApiToken` / `[String] $ApiKey`).
3. Classifies:
  - **Backward-compatible:** param block (or equivalent) includes `ApiToken` (and typically also `ApiKey`/`Email`).
  - **Legacy:** param block includes `ApiKey` (and usually `Email`) but **not** `ApiToken`.
  - **Outlier:** has neither `ApiKey` nor `ApiToken` in the param block.
4. Writes a **single output file** (e.g. `CloudFlareModule-AuthClassification.txt` or `.md`) under the CloudFlareModule folder (or a path you choose) with:
  - **1. Legacy auth (ApiKey only):** one command per line.
  - **2. Backward-compatible (ApiKey or ApiToken):** one command per line.
  - **3. Outliers:** list or "None" if there are no outliers.

## Implementation steps

1. **Add a small PowerShell script** (e.g. `Scripts/Get-CloudFlareAuthClassification.ps1` or in the module folder) that:
  - Uses `Get-ChildItem -Path $PSScriptRoot\Public\*.ps1` (or the repo-relative path to `InternalModules/CloudFlareModule/Public`).
  - For each file, gets content and checks for:
    - Presence of a parameter `$ApiToken` (e.g. regex like `\$\s*ApiToken` or `Parameter.*ApiToken` in the param block).
    - Presence of a parameter `$ApiKey` (e.g. `\$\s*ApiKey` or `Parameter.*ApiKey` in the param block).
  - Classifies into three arrays; then outputs to a single file (e.g. `CloudFlareModule-AuthClassification.txt`) in a clear, readable format (sections 1, 2, 3 as above).
2. **Run the script** from the `dxc-deployment-automation` repo (or from the CloudFlareModule directory) so the paths to `Public/*.ps1` resolve correctly.
3. **Deliverable:** One file containing:
  - **1. Legacy (ApiKey only):** full list.
  - **2. Backward-compatible (ApiKey or ApiToken):** full list.
  - **3. Outliers:** list or "None".

## Edge cases

- **Add-CFAccount** is backward-compatible (parameter sets `UseApiKey` and `UseApiToken`); it does not call the API with credentials itself but sets `PSDefaultParameterValues` for other cmdlets.
- **Get-CFAccount** (and any other that only has `Email` + `ApiKey`) is legacy.
- If a script has no auth parameters at all (e.g. a utility that doesn't call CloudFlare API), it is an outlier; from the current codebase, all Public cmdlets that call the API appear to take either Email+ApiKey or ApiToken, so outliers may be none or few.

## File to create

- **Classification script:** e.g. `dxc-deployment-automation/InternalModules/CloudFlareModule/Scripts/Get-CloudFlareAuthClassification.ps1` (or a single script next to the module).
- **Output file:** e.g. `dxc-deployment-automation/InternalModules/CloudFlareModule/CloudFlareModule-AuthClassification.txt` (or `.md`), written when the script is run.

## Verification

- Manually confirm a few legacy (e.g. `Add-CFDNSRecord`, `Remove-CFDNSRecord`, `Get-CFAccount`) and backward-compatible (e.g. `Get-CFDNSZone`, `Get-CFZoneSettings`) from the generated file.
- If the script reports 0 outliers, the output file will state "Outliers: None" as requested.

## Run the classification script

From a PowerShell prompt:

```powershell
c:\Source\dxc-deployment-automation\InternalModules\CloudFlareModule
.\Scripts\Get-CloudFlareAuthClassification.ps1
```

Or as a one-liner (from any location):

```powershell
Set-Location c:\Source\dxc-deployment-automation\InternalModules\CloudFlareModule; .\Scripts\Get-CloudFlareAuthClassification.ps1
```
