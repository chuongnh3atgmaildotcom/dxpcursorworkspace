# Requires CloudFlareModule (e.g. Import-Module from dxc-deployment-automation).
# this in module path so don't need path
Import-Module CloudFlareModule -Force

#region load .env (same dir as script)
# Env root: script dir when run as file; $Global:EnvLoadRoot or $PWD when run via F8 (so F8-set vars persist)
$envDir = if ($PSScriptRoot) { $PSScriptRoot } else { Join-Path -Path $PWD -ChildPath "30755" }
$envPath = Join-Path $envDir '.env'
if (-not (Test-Path -LiteralPath $envPath)) {
    throw "Missing .env at: $envPath. When using F8, set `$Global:EnvLoadRoot = 'C:\Source\_workspace\30755' first, or cd to 30755."
}
$envLoadedKeys = [System.Collections.ArrayList]@()
Get-Content -LiteralPath $envPath -Encoding UTF8 | ForEach-Object {
    $line = $_.Trim()
    if ($line -and $line -notmatch '^\s*#') {
        $firstEq = $line.IndexOf('=')
        if ($firstEq -gt 0) {
            $key = $line.Substring(0, $firstEq).Trim()
            $value = $line.Substring($firstEq + 1).Trim()
            if ($value.Length -ge 2 -and (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'")))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            [void]$envLoadedKeys.Add($key)
            Set-Variable -Scope Global -Name $key -Value $value -ErrorAction SilentlyContinue
        }
    }
}
foreach ($k in $envLoadedKeys) {
    $v = (Get-Variable -Scope Global -Name $k -ErrorAction SilentlyContinue).Value
    Write-Host "$k = $v"
}
# Load cert/key from files if paths set in .env (stored in Global so F8 snippets can use them)
if (Get-Variable -Name 'CF_CERT_FILE' -Scope Global -ErrorAction SilentlyContinue) {
    $certPath = Join-Path $envDir $Global:CF_CERT_FILE
    if (Test-Path -LiteralPath $certPath) {
        $Global:CFCert = Get-Content -LiteralPath $certPath -Raw
    }
}
if (Get-Variable -Name 'CF_KEY_FILE' -Scope Global -ErrorAction SilentlyContinue) {
    $keyPath = Join-Path $envDir $Global:CF_KEY_FILE
    if (Test-Path -LiteralPath $keyPath) {
        $Global:CFKey = Get-Content -LiteralPath $keyPath -Raw
    }
}
#endregion

$apiToken = $userApiToken

#region verify token
$headers = @{
    "Authorization" = "Bearer $userApiToken"
}
#Verify token via User Endpoint:
Invoke-RestMethod -Method Get -Uri "https://api.cloudflare.com/client/v4/user/tokens/verify" -Headers $headers
#Verify token via account Endpoint:
Invoke-RestMethod -Method Get -Uri "https://api.cloudflare.com/client/v4/accounts/$accountId/tokens/verify" -Headers $headers
#endregion


# Run Add-CFPageRule with SpecificByIdAndValueWithApiKey (Email + ApiKey)
# Set $email, $apiKey, $zoneId to real values or use Add-CFAccount first for session defaults.
# $email = 'user@example.com'
# $apiKey = 'your-api-key'
# Add-CFPageRule -Email $email -ApiKey $apiKey -ZoneId $zoneId -URLPattern '*.domain.com/DisableWaf/*' -ActionId waf -ActionValue off -Enabled

#region test


#region manual test
#Add-CFPageRule
$apiToken =  $userApiToken
$actions = @(
    @{ 'id' = 'browser_cache_ttl'; 'value' = 0 }
    @{ 'id' = 'cache_level'; 'value' = 'cache_everything' }
    @{ 'id' = 'edge_cache_ttl'; 'value' = 300 }
)
Add-CFPageRule -ApiToken $apiToken -ZoneId $zoneId -URLPattern '*.domain.com/CacheEverything/*' -Actions $actions -Priority 1 -Enabled

# Add-CFDNSZone
$apiToken = $accApiToken
$zoneName = "30873.paastest.co.uk"
# #(email + key auth)):Add-CFDNSZone -Email $email -ApiKey $apiKey -ZoneName '29486.paastest.co.uk' -OrganizationId $accountId
Add-CFDNSZone -ApiToken $apiToken -ZoneName $zoneName -OrganizationId $accountId -ZoneType 'partial'

# Add-CFDNSRecord
# zone created above
$zoneId = "64cfea78ced4076b1e491d442f02e938"
Add-CFDNSRecord -ApiToken $apiToken -ZoneId $zoneId -Name 'inte' -Type 'CNAME' -Content 'inte.chngcmswin95r1z.chng.epimore.com'

# Add-CFCustomHostname
Add-CFCustomHostname -ApiToken $apiToken -ZoneId $zoneId -Name 'example30873.com'

#region test Add-CFCustomSSLCertificate
# Certificate and private key loaded from .env paths (CF_CERT_FILE, CF_KEY_FILE) at script start
if ($CFCert -and $CFKey) {
    Add-CFCustomSSLCertificate -ApiToken $apiToken -ZoneId $zoneId -Certificate $CFCert -PrivateKey $CFKey
}
else {
    Write-Warning "CFCert or CFKey not loaded; skip Add-CFCustomSSLCertificate. Set CF_CERT_FILE and CF_KEY_FILE in .env and ensure PEM files exist."
}
#endregion

#region test Add-CFFirewallAccessRule

# with apikey, Account Firewall Access Rules: ok
# Add-CFFirewallAccessRule -Email $email -ApiKey $apiKey -Mode 'block' -Target 'ip' -Value '104.124.145.85' -Notes '30873 -block access from example IP' -Id $accountId -IsOrganization
# Add-CFFirewallAccessRule -Email $email -ApiKey $apiKey -Mode 'block' -Target 'ip' -Value '104.124.145.86' -Notes '30873 - another block access from example IP' -Id $accountId -IsOrganization

# with apikey, zone Firewall Access Rules: ok
# Add-CFFirewallAccessRule -Email $email -ApiKey $apiKey -Mode 'block' -Target 'ip' -Value '104.124.145.85' -Notes '30873 -block access from example IP' -Id $zoneId

# I added Account Firewall Access Rules:Edit and Zone firewall service: edit
$apiToken = $userApiToken
# use acc token with acc permission
$apiToken = $chuongCustomerAccApiToken
# with apitoken, Account Firewall Access Rules: ok
Add-CFFirewallAccessRule -ApiToken $apiToken -Mode 'block' -Target 'ip' -Value '104.124.145.85' -Notes '30873 acc apitoken -block access from example IP' -Id $accountId -IsOrganization
# with apitoken, zone Firewall Access Rules: failed. 
# API call failed! The error was: The remote server returned an error: (403) Forbidden. Error code: 10000. Message: Authentication error RayId: 9d4607b7a93b04ce-HKG. 
Add-CFFirewallAccessRule -ApiToken $apiToken -Mode 'block' -Target 'ip' -Value '104.124.145.85' -Notes '30873 zone apitoken  -block access from example IP' -Id $zoneId

#region result question
# create on acc 1d39e29aacb3f678097dd9d4b64e12b7, why it show on zone 64cfea78ced4076b1e491d442f02e938: ?
# Because it is scoped to the Account parent, a single rule automatically trickles down to protect every single Zone (website) owned by that account.
# id            : ea5c4a513f134c169975bbb9b68130dd
# paused        : False
# modified_on   : 2026-02-27T03:19:46.573431173Z
# allowed_modes : {whitelist, block, challenge, js_challenge...}
# mode          : block
# notes         : block access from example IP
# configuration : @{target=ip; value=104.124.145.85}
# scope         : @{id=4bb68a5f37bf5a71ec0dc0bf6f343a0e; type=organization}
# created_on    : 2026-02-27T03:19:46.573431173Z
# and what is return scope @{id=4bb68a5f37bf5a71ec0dc0bf6f343a0e; type=organization}?
# just an unique scope.id represent entity (in this case account) scope. The reason Cloudflare still uses a separate scope.id is mostly system boundaries (cf tech debt), not uniqueness
#endregion

# 1st test id: ea5c4a513f134c169975bbb9b68130dd
# 2nd test id: id            : c5d9d158022b44c2ab7e11d9b57e1db8
# delete for acc
# Remove-CFFirewallAccessRule -Email $email -ApiKey $apiKey -Id $accountId -AccessRuleId "87903a1fb53c462c9b78862f49b404a6" -IsOrganization
# delete for zone
# Remove-CFFirewallAccessRule -Email $email -ApiKey $apiKey -Id $zoneId -AccessRuleId "7ac09a75beae4e41a7dba0fd9e8945f3"


#endregion

#region Add-CFRuleset (one line per parameter set)
# Add-CFRuleset -Email $email -ApiKey $apiKey -ZoneId $zoneId -Name "Test Ruleset" -Description "Test" -Kind zone -Phase "http_request_firewall_custom"
# Add-CFRuleset -Email $email -ApiKey $apiKey -AccountId $accountId -Name "Test Ruleset" -Description "Test" -Kind custom -Phase "http_request_firewall_custom"
# Add-CFRuleset -Email $email -ApiKey $apiKey -AccountId $accountId -Name "30873 apitoken managed http_request_firewall_custom Ruleset" -Description "Test" -Kind managed -Phase "http_request_firewall_custom"
# I added Account WAF Write
$apiToken = $accApiToken
Add-CFRuleset -ApiToken $apiToken -ZoneId $zoneId -Name "30873 apitoken custom http_request_firewall_custom Ruleset" -Description "Test" -Kind custom -Phase "http_request_firewall_custom"
Add-CFRuleset -ApiToken $apiToken -ZoneId $zoneId -Name "30873 apitoken zone ddos_l4 Ruleset " -Description "Test" -Kind zone -Phase "ddos_l4"
Add-CFRuleset -ApiToken $apiToken -AccountId $accountId -Name "30873 apitoken managed http_request_firewall_custom Ruleset" -Description "Test" -Kind managed -Phase "http_request_firewall_custom"
#endregion add cf ruleset


#region Add-CFRulesetRule
$apiToken = $userApiToken
# Yes — different scope = different ruleset list: zone rulesets (zones/{zone_id}/rulesets) vs account rulesets (accounts/{account_id}/rulesets).
# Use zone ruleset id for ZoneById-* and account ruleset id for AccountById-*. Fetch both for current zone/account (Get-CFRuleset uses Email+ApiKey).
$zoneRulesets = @(Get-CFRuleset -Email $email -ApiKey $apiKey -ZoneId $zoneId)
# description  :
# id           : cc213f5bbc5e4711a67649e0d1250662
# kind         : zone
# last_updated : 2026-03-02T08:59:56.289425Z
# name         : default
# phase        : http_request_firewall_custom
# source       : firewall_custom
# version      : 1
$zoneCustomRuleset = $zoneRulesets | Where-Object { $_.kind -eq "zone" -and $_.phase -eq "http_request_firewall_custom" } | Select-Object -First 1
$zoneWAFCustomRulesetId = if ($zoneCustomRuleset) { $zoneCustomRuleset.id } else { $null }

$accountRulesets = @(Get-CFRuleset -Email $email -ApiKey $apiKey -AccountId $accountId)
# Rate-limit ruleset: phase http_ratelimit and (kind custom or name 30873-acc-rate-dashboard)
$accountRateLimitRuleset = $accountRulesets | Where-Object {
    ($_.phase -eq 'http_ratelimit' -and  $_.kind -eq 'custom') -or $_.name -eq '30873-acc-rate-dashboard'
} | Select-Object -First 1
$accountRateLimitRulesetId = if ($accountRateLimitRuleset) { $accountRateLimitRuleset.id } else { $null }
# custom ruleset: phase http_ratelimit and (kind custom or name 30873-acc-rate-dashboard)
$accountCustomRuleset = $accountRulesets | Where-Object {
    ($_.phase -eq 'http_request_firewall_custom' -and $_.kind -eq 'custom') -or $_.name -eq '30873-acc-custom-dashboard'
} | Select-Object -First 1
$accountCustomRulesetId = if ($accountCustomRuleset) { $accountCustomRuleset.id } else { $null }
#region verify
# Dashboard vs API ID mapping (rate-limit):
#   Dashboard URL shows the RULE id (e.g. 251395adb...) — the "execute" rule in the phase entrypoint that points to the ruleset.
#   API ruleset calls need the RULESET id (e.g. 8086f39bb...) — the custom ruleset that rule executes.
#   Map dashboard → API: fetch phase entrypoint, find rule where rule.id == <dashboard rule id>, then rulesetId = Get-RulesetIdFromExecuteRule(rule).
#   Map API → dashboard: find rule in entrypoint where Get-RulesetIdFromExecuteRule(rule) == <ruleset id>; rule.id is the dashboard URL id.
#   Note: action_parameters can display empty in Format-Table but still contain .id; we read it via several fallbacks.
function Get-RulesetIdFromExecuteRule {
    param([Parameter(Mandatory = $true)] $Rule)
    $ap = $Rule.action_parameters
    if (-not $ap) { return $null }
    $rid = $ap.id
    if (-not $rid -and $ap.PSObject.Properties['Id']) { $rid = $ap.Id }
    $idProp = $ap.PSObject.Properties | Where-Object { $_.Name -eq 'id' } | Select-Object -First 1
    if (-not $rid -and $idProp) { $rid = $idProp.Value }
    return $rid
}
$ruleIdPointingToRateLimitRuleset = $null
$rulesetIdFromDashboardRuleId = $null   # Map dashboard rule id → ruleset id (for reverse lookup)
if ($accountRateLimitRulesetId) {
    $entrypointUri = "https://api.cloudflare.com/client/v4/accounts/$accountId/rulesets/phases/http_ratelimit/entrypoint"
    $entrypointHeaders = @{
        'X-Auth-Email'   = $email
        'X-Auth-Key'     = $apiKey
        'Content-Type'  = 'application/json'
    }
    $response = Invoke-RestMethod -Method Get -Uri $entrypointUri -Headers $entrypointHeaders -ErrorAction Stop
    $entrypoint = $response.result
    $allRules = @($entrypoint.rules)
    $pointingRule = $allRules | Where-Object { (Get-RulesetIdFromExecuteRule -Rule $_) -eq $accountRateLimitRulesetId } | Select-Object -First 1
    if ($pointingRule) {
        $ruleIdPointingToRateLimitRuleset = $pointingRule.id
        $rulesetIdFromDashboardRuleId = Get-RulesetIdFromExecuteRule -Rule $pointingRule
    }
    # Reverse map: given dashboard rule id, resolve to ruleset id (so you can use it in API)
    if ($ruleIdPointingToRateLimitRuleset) {
        $ruleByDashboardId = $allRules | Where-Object { $_.id -eq $ruleIdPointingToRateLimitRuleset } | Select-Object -First 1
        if ($ruleByDashboardId) { $rulesetIdFromDashboardRuleId = Get-RulesetIdFromExecuteRule -Rule $ruleByDashboardId }
        # If action_parameters.id was empty in REST deserialization, try raw JSON (keys may be preserved)
        if (-not $rulesetIdFromDashboardRuleId) {
            try {
                $raw = Invoke-WebRequest -Method Get -Uri $entrypointUri -Headers $entrypointHeaders -UseBasicParsing -ErrorAction Stop
                $json = $raw.Content | ConvertFrom-Json
                $ruleJson = $json.result.rules | Where-Object { $_.id -eq $ruleIdPointingToRateLimitRuleset } | Select-Object -First 1
                if ($ruleJson -and $ruleJson.action_parameters.id) { $rulesetIdFromDashboardRuleId = $ruleJson.action_parameters.id }
            }
            catch { }
        }
    }
    Write-Host "Rate-limit ruleset: id=$accountRateLimitRulesetId name=$($accountRateLimitRuleset.name). Rule (dashboard URL): id=$ruleIdPointingToRateLimitRuleset. Dashboard rule id → ruleset id: $rulesetIdFromDashboardRuleId"
}
if ($accountCustomRulesetId) {
    $entrypointUri = "https://api.cloudflare.com/client/v4/accounts/$accountId/rulesets/phases/http_request_firewall_custom/entrypoint"
    $entrypointHeaders = @{
        'X-Auth-Email'   = $email
        'X-Auth-Key'     = $apiKey
        'Content-Type'  = 'application/json'
    }
    $response = Invoke-RestMethod -Method Get -Uri $entrypointUri -Headers $entrypointHeaders -ErrorAction Stop
    $entrypoint = $response.result
    $allRules = @($entrypoint.rules)
    $pointingRule = $allRules | Where-Object { (Get-RulesetIdFromExecuteRule -Rule $_) -eq $accountCustomRulesetId } | Select-Object -First 1
    if ($pointingRule) {
        $ruleIdPointingToCustomRuleset = $pointingRule.id
        $rulesetIdFromDashboardRuleId = Get-RulesetIdFromExecuteRule -Rule $pointingRule
    }
    # Reverse map: given dashboard rule id, resolve to ruleset id (so you can use it in API)
    # if ($ruleIdPointingToCustomRuleset) {
    #     $ruleByDashboardId = $allRules | Where-Object { $_.id -eq $ruleIdPointingToCustomRuleset } | Select-Object -First 1
    #     if ($ruleByDashboardId) { $rulesetIdFromDashboardRuleId = Get-RulesetIdFromExecuteRule -Rule $ruleByDashboardId }
    #     # If action_parameters.id was empty in REST deserialization, try raw JSON (keys may be preserved)
    #     if (-not $rulesetIdFromDashboardRuleId) {
    #         try {
    #             $raw = Invoke-WebRequest -Method Get -Uri $entrypointUri -Headers $entrypointHeaders -UseBasicParsing -ErrorAction Stop
    #             $json = $raw.Content | ConvertFrom-Json
    #             $ruleJson = $json.result.rules | Where-Object { $_.id -eq $ruleIdPointingToRateLimitRuleset } | Select-Object -First 1
    #             if ($ruleJson -and $ruleJson.action_parameters.id) { $rulesetIdFromDashboardRuleId = $ruleJson.action_parameters.id }
    #         }
    #         catch { }
    #     }
    # }
    Write-Host "custom acc ruleset: id=$accountCustomRulesetId name=$($accountCustomRuleset.name). Rule (dashboard URL): id=$ruleIdPointingToCustomRuleset. Dashboard rule id → ruleset id: $rulesetIdFromDashboardRuleId"
}
if (-not $rulesetId) { Write-Warning "No zone rulesets for zone $zoneId; ZoneById-* samples will fail." }
if (-not $accountRulesetId) { Write-Warning "No account rulesets for account $accountId; AccountById-* sample will fail." }
#endregion

#region test security rule
# ZoneById-blockWithApiKey
Add-CFRulesetRule -Email $email -ApiKey $apiKey -ZoneId $zoneId -RulesetId $zoneWAFCustomRulesetId -Description "30873 - ZoneById-blockWithApiKey" -Expression "true" -Block
# ZoneById-blockWithApiToken
Add-CFRulesetRule -ApiToken $apiToken -ZoneId $zoneId -RulesetId $zoneWAFCustomRulesetId -Description "30873 - ZoneById-blockWithApiToken" -Expression "true" -Block
# AccountById-executeWithApiToken (uses account-scoped ruleset id)
$accRateLimitEntryRulesetId = (Get-CFRulesetEntryPoint  -Email $email -ApiKey $apiKey -AccountId $accountId -Phase 'http_ratelimit').id
Add-CFRulesetRule -ApiToken $apiToken -AccountId $accountId -RulesetId $accRateLimitEntryRulesetId -Description "30873 - AccountById-executeWithApiToken" -Expression '(cf.zone.plan eq "ENT")' -RulesetToExecute $accountRateLimitRulesetId
# AccountById-skipWithApiToken
Add-CFRulesetRule -ApiToken $apiToken -AccountId $accountId -RulesetId $accountCustomRulesetId -Description "30873 - AccountById-skipWithApiToken" -Expression "true" -PhaseToSkip @("http_request_firewall_managed")
# ZoneById-actionWithApiToken
Add-CFRulesetRule -ApiToken $apiToken -ZoneId $zoneId -RulesetId $zoneWAFCustomRulesetId -Description "30873 - ZoneById-actionWithApiToken" -Expression "true" -Action "log"
#endregion

#region test routing/perfomance rule
#region create entry point rulesets: account bulk redirect (get only), zone single redirect, zone cache (create if missing)
try {
    $accRedirectEntryRulesetId = (Get-CFRulesetEntryPoint -Email $email -ApiKey $apiKey -AccountId $accountId -Phase 'http_request_redirect').id
} catch {
    Write-Warning "Could not find account redirect entrypoint ruleset: $_"
}
try {
    $zoneRedirectEntryRulesetId = (Get-CFRulesetEntryPoint -Email $email -ApiKey $apiKey -ZoneId $zoneId -Phase 'http_request_dynamic_redirect').id
} catch {
    Write-Warning "Could not find zone redirect entrypoint ruleset: $_"
}
try {
    $zoneCacheEntryRulesetId = (Get-CFRulesetEntryPoint -Email $email -ApiKey $apiKey -ZoneId $zoneId -Phase 'http_request_cache_settings').id
} catch {
    Write-Warning "Could not find zone cache entrypoint ruleset: $_"
}

if (-not $accRedirectEntryRulesetId) {
    try {
        $zoneRedirectEntryRulesetId = (Add-CFRuleset -ApiToken $apiToken -AccountId $accountId -Name "30873 apikey acc bulk redirect" -Description "Entry point for http_request_redirect (bulk Redirects)" -Kind root -Phase "http_request_redirect").id
    } catch { Write-Warning "Could not create zone ruleset for http_request_dynamic_redirect: $_" }
}
if (-not $zoneRedirectEntryRulesetId) {
    try {
        $zoneRedirectEntryRulesetId = (Add-CFRuleset -ApiToken $apiToken -ZoneId $zoneId -Name "30873 apikey zone single redirect" -Description "Entry point for http_request_dynamic_redirect (Single Redirects)" -Kind zone -Phase "http_request_dynamic_redirect").id
    } catch { Write-Warning "Could not create zone ruleset for http_request_dynamic_redirect: $_" }
}
if (-not $zoneCacheEntryRulesetId) {
    try {
        #account rulesets + zone cache rules
        $zoneCacheEntryRulesetId = (Add-CFRuleset -ApiToken $apiToken -ZoneId $zoneId -Name "30873 apikey zone cache" -Description "Entry point for http_request_cache_settings (Cache Rules)" -Kind zone -Phase "http_request_cache_settings").id
    } catch { Write-Warning "Could not create zone ruleset for http_request_cache_settings: $_" }
}
#endregion


# Routing: redirect rule (phase http_request_redirect). Action "redirect"; action_parameters: from_value.target_url.value, from_value.status_code.
# permission: zone single redirect
Add-CFRulesetRule -ApiToken $apiToken -AccountId $accountId -RulesetId $accRedirectEntryRulesetId -Description "30873 - AccountById-actionWithApiToken (redirect)" -Expression "true" -Action "redirect" -ActionParameter  @{ from_list = @{ "name"="demo"; "key" = "http.request.full_uri"} }
# Routing: redirect rule (phase http_request_dynamic_redirect). Action "redirect"; action_parameters: from_value.target_url.value, from_value.status_code. 
# permission: zone single redirect
Add-CFRulesetRule -ApiToken $apiToken -ZoneId $zoneId -RulesetId $zoneRedirectEntryRulesetId -Description "30873 - ZoneById-actionWithApiToken (redirect)" -Expression "true" -Action "redirect" -ActionParameter @{ from_value = @{ target_url = @{ value = "https://example.com" }; status_code = 302 } }

# Performance: cache rule (phase http_request_cache_settings). Action "set_cache_settings"; action_parameters: cache (bool), etc.
# Zone scope:
Add-CFRulesetRule -ApiToken $apiToken -ZoneId $zoneId -RulesetId $zoneCacheEntryRulesetId -Description "30873 - ZoneById-actionWithApiToken (set_cache_settings)" -Expression "true" -Action "set_cache_settings" -ActionParameter @{ cache = $true }
#endregion

#endregion Add-CFRulesetRule

#region add-cffirewallruletozone
Add-CFFirewallruleToZone -ApiToken $apiToken -ZoneId $zoneId -Description "30873 - Add-CFFirewallruleToZone zone WithApiToken" -Expression "true" -Action "log"
Add-CFFirewallruleToZone -ApiToken $apiToken -OrganizationId $accountId -Description "30873 - Add-CFFirewallruleToZone OrganizationIDWithApiToken" -Expression "true" -Action "log"
# Bulk remove: rule "30873 - Add-CFFirewallruleToZone OrganizationIDWithApiToken" from every zone in account
$zonesInAccount = Get-CFDNSZone -ApiToken $apiToken | Where-Object { $_.owner.id -eq $accountId }
Write-Host "Bulk remove: zones in account ($accountId): $($zonesInAccount.Count)" -ForegroundColor Cyan
$zonesInAccount | ForEach-Object { Write-Host "  zone id=$($_.id) name=$($_.name)" }
$ruleDescriptionToRemove = '30873 - Add-CFFirewallruleToZone OrganizationIDWithApiToken'
foreach ($zone in $zonesInAccount) {
    $zoneId = $zone.id
    Write-Host "Zone $zoneId ($($zone.name)): Get-CFRuleset (list)" -ForegroundColor Yellow
    $zoneRulesets = Get-CFRuleset -ApiToken $apiToken -ZoneId $zoneId
    Write-Host "  rulesets: $($zoneRulesets.Count)"
    $firewallCustom = $zoneRulesets | Where-Object { $_.phase -eq 'http_request_firewall_custom' -and $_.kind -eq 'zone' } | Select-Object -First 1
    if (-not $firewallCustom) { Write-Host "  no phase=firewall_custom kind=zone; skip"; continue }
    Write-Host "  firewall_custom ruleset id=$($firewallCustom.id). Get-CFRuleset (by id)" -ForegroundColor Yellow
    $fullRuleset = Get-CFRuleset -ApiToken $apiToken -ZoneId $zoneId -RulesetId $firewallCustom.id
    $rulesToRemove = @(if ($fullRuleset.rules) { $fullRuleset.rules | Where-Object { $_.description -eq $ruleDescriptionToRemove } })
    Write-Host "  rules matching '$ruleDescriptionToRemove': $($rulesToRemove.Count)"
    foreach ($r in $rulesToRemove) {
        Write-Host "  Remove-CFRulesetRule ZoneId=$zoneId RulesetId=$($firewallCustom.id) RuleId=$($r.id) description=$($r.description)" -ForegroundColor Magenta
        Remove-CFRulesetRule -ApiToken $apiToken -ZoneId $zoneId -RulesetId $firewallCustom.id -RuleId $r.id
        Write-Host "  removed."
    }
}
Write-Host "Bulk remove done." -ForegroundColor Cyan

#endregion add-cffirewallruletozone

#region Add-CFLBMonitor
# perm: acc - lb monitor and pool
Add-CFLBMonitor -ApiToken $apiToken -OrganizationId $accountId -MonitorType 'HTTPS' -Description '30873 - apitoken monitor' 
$lBMonitorId = '7b146e38314708d7c8158b661dfbff55'
#endregion Add-CFLBMonitor


#region Add-CFLBOriginPool
# Import-Module CloudFlareModule -Force
Add-CFLBOriginPool -ApiToken $apiToken -OrganizationId $accountId -Description "30873 - another lbpool apitoken" -Name "30873-another-lbpool-apitoken" -MonitorId $lBMonitorId -Origins @("origin1.azurewebsites.net", "origin2.azurewebsites.net")
$lBpoolId = '1d28360077f62c4db8d2b16e96e06576'
#endregion Add-CFLBOriginPool.

#region Add-CFLBRecord
#perm: zone: load balancer
Add-CFLBRecord -ApiToken $apiToken -ZoneId $zoneId -Name "lbrecord.$zoneName" -Description "30873-lbrec-apitoken ($zoneName)" -DefaultPools @($lBpoolId)
#endregion Add-CFLBrecord

#region Add-CFSpectrumApplication
#perm: zone - zone setting write
Add-CFSpectrumApplication -ApiToken $apiToken -ZoneId $zoneId -Name "30873-apitoken-spectrum.$zoneName" -Port 80 -TrafficType 'http' -EdgeIp '217.114.94.1' -OriginIp '217.114.85.70'
#endregion Add-CFSpectrumApplication

#region test Add-CFWorkerRoute
# Requires a Workers script to exist (ScriptName). Pattern maps URL pattern to that script.
# add perm: 
Add-CFWorkerRoute -ApiToken $apiToken -ZoneId $zoneId -Pattern "*.$zoneName/30873-worker/*" -ScriptName "ngdk-test-redirect"
# Add-CFWorkerRoute -Email $email -ApiKey $apiKey -ZoneId $zoneId -Pattern "*.$zoneName/30873-worker/*" -ScriptName "30873-worker"
#endregion

#endregion manual test

#region pester test

$dxcRepoRoot = 'C:\Source\dxc-deployment-automation'
$cfModuleTestRoot = Join-Path $dxcRepoRoot 'InternalModules\CloudFlareModule\Tests'
$unitTestRoot = Join-Path $cfModuleTestRoot 'Unit'
$integrationTestFile = Join-Path $cfModuleTestRoot 'Integration\CloudFlareModule.Integration.Tests.ps1'

function Invoke-PesterTestForFunction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FunctionName
    )
    $unitTestPath = Join-Path $unitTestRoot "$FunctionName.Unit.Tests.ps1"
    if (Test-Path -LiteralPath $unitTestPath) {
        Invoke-Pester -Script $unitTestPath
    }
    else {
        Write-Warning "Unit test not found at: $unitTestPath"
    }
    # if (Test-Path -LiteralPath $integrationTestFile) {
    #     Invoke-Pester -Script $integrationTestFile -TestName "*$FunctionName*"
    # }
    # else {
    #     Write-Warning "Integration test file not found at: $integrationTestFile"
    # }
}

$doneList1 = @('Add-CFPageRule', 'Add-CFDNSZone', 'Add-CFDNSRecord', 'Add-CFCustomHostname', 'Add-CFCustomSSLCertificate', 'Add-CFFirewallAccessRule', 'Add-CFRuleset', 'Add-CFRulesetRule', 'Add-CFFirewallruleToZone')
foreach ($functionName in $doneList1) {
    Invoke-PesterTestForFunction -FunctionName $functionName
}
$doneList2 = @('Add-CFLBOriginPool', 'Add-CFLBMonitor', 'Add-CFLBRecord', 'Add-CFSpectrumApplication', 'Add-CFWorkerRoute')
foreach ($functionName in $doneList2) {
    Invoke-PesterTestForFunction -FunctionName $functionName
}

#endregion pester test

#endregion