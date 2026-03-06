<#
.SYNOPSIS
    Classifies CloudFlareModule Public cmdlets by auth method and writes a single output file.

.DESCRIPTION
    Scans all Public/*.ps1 in the CloudFlareModule and classifies each by whether it accepts
    only ApiKey (legacy), both ApiKey and ApiToken (backward-compatible), or neither (outlier).
    Writes CloudFlareModule-AuthClassification.txt in the script folder (30755).

.PARAMETER CloudFlareModulePath
    Path to the CloudFlareModule folder (containing Public\). Default: resolved relative to
    this script when run from _workspace\30755 (goes to ..\..\dxc-deployment-automation\InternalModules\CloudFlareModule).

.EXAMPLE
    .\Get-CloudFlareAuthClassification.ps1

.EXAMPLE
    .\Get-CloudFlareAuthClassification.ps1 -CloudFlareModulePath c:\Source\dxc-deployment-automation\InternalModules\CloudFlareModule
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [String] $CloudFlareModulePath = $null
)

# Resolve module root: when script lives in _workspace\30755, CloudFlareModule is at ../../dxc-deployment-automation/InternalModules/CloudFlareModule
if (-not $CloudFlareModulePath) {
    $relativePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\dxc-deployment-automation\InternalModules\CloudFlareModule'
    $resolved = Resolve-Path -LiteralPath $relativePath -ErrorAction SilentlyContinue
    if ($resolved) { $CloudFlareModulePath = $resolved.Path }
}
if (-not $CloudFlareModulePath -or -not (Test-Path -LiteralPath $CloudFlareModulePath -PathType Container)) {
    Write-Error "CloudFlareModule not found. Pass -CloudFlareModulePath or run from _workspace\30755 so default path resolves. Tried: $CloudFlareModulePath"
    exit 1
}

$moduleRoot = $CloudFlareModulePath
$publicPath = Join-Path -Path $moduleRoot -ChildPath 'Public'
$outputPath = Join-Path -Path $PSScriptRoot -ChildPath 'CloudFlareModule-AuthClassification.txt'

if (-not (Test-Path -LiteralPath $publicPath -PathType Container)) {
    Write-Error "Public folder not found: $publicPath"
    exit 1
}

$legacy = [System.Collections.Generic.List[string]]::new()
$backwardCompatible = [System.Collections.Generic.List[string]]::new()
$outliers = [System.Collections.Generic.List[string]]::new()

# Match only inside the param block: e.g. [String] $ApiKey or [String] $ApiToken (declared parameters only)
$apiKeyParamPattern = '\$\s*ApiKey\b'
$apiTokenParamPattern = '\$\s*ApiToken\b'

function Get-ParamBlockText {
    param([string]$Content)
    # Word-boundary "param" then optional whitespace then "(" (handles param( and param ( ); avoids .PARAMETER
    $m = [regex]::Match($Content, '\bparam\s*\(', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $m.Success) { return $null }
    $idx = $m.Index
    $open = $Content.IndexOf('(', $idx)
    if ($open -lt 0) { return $null }
    $depth = 1
    $i = $open + 1
    $len = $Content.Length
    while ($depth -gt 0 -and $i -lt $len) {
        $c = $Content[$i]
        if ($c -eq '(') { $depth++ }
        elseif ($c -eq ')') { $depth-- }
        $i++
    }
    return $Content.Substring($idx, $i - $idx)
}

$files = Get-ChildItem -Path $publicPath -Filter '*.ps1' -File | Sort-Object Name
foreach ($file in $files) {
    $commandName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
    $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop
    $paramBlock = Get-ParamBlockText -Content $content
    $hasApiKey = $paramBlock -and ($paramBlock -match $apiKeyParamPattern)
    $hasApiToken = $paramBlock -and ($paramBlock -match $apiTokenParamPattern)

    if ($hasApiToken) {
        $backwardCompatible.Add($commandName) | Out-Null
    }
    elseif ($hasApiKey) {
        $legacy.Add($commandName) | Out-Null
    }
    else {
        $outliers.Add($commandName) | Out-Null
    }
}

$lines = @(
    "CloudFlareModule Auth Classification",
    "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "",
    "1. Legacy auth (accept param ApiKey only, e.g. Email + ApiKey)",
    "--------------------------------------------------------------------------------",
    ($legacy | Sort-Object | ForEach-Object { $_ }),
    "",
    "2. Backward-compatible auth (accept either ApiKey or ApiToken)",
    "--------------------------------------------------------------------------------",
    ($backwardCompatible | Sort-Object | ForEach-Object { $_ }),
    "",
    "3. Outliers (no ApiKey or ApiToken parameter)",
    "--------------------------------------------------------------------------------",
    $(if ($outliers.Count -eq 0) { "None" } else { $outliers | Sort-Object | ForEach-Object { $_ } })
)

$lines | Set-Content -Path $outputPath -Encoding UTF8
Write-Host "Written: $outputPath"
Write-Host "  Legacy: $($legacy.Count) | Backward-compatible: $($backwardCompatible.Count) | Outliers: $($outliers.Count)"
