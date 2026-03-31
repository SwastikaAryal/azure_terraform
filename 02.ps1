param(
    [string]$NexusBaseUrl   = "https://nexus.bmwgroup.net",
    [string]$NexusRepo      = "nuget_proxy",
    [string]$PackageName    = "Microsoft.AspNetCore.Server.Kestrel.Core",
    [string]$PluginBase     = "C:\Packages\Plugins",
    [string]$LogFile        = "C:\Temp\KestrelCore_Update_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
)

# Safe versions per major branch based on Wiz findings:
# Branch 2.x -> fixed at 2.3.6
# Branch 8.x -> fixed at 8.0.21
$SafeVersionMap = @{
    "2" = "2.3.6"
    "8" = "8.0.21"
}

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    Write-Host $entry
    Add-Content -Path $LogFile -Value $entry
}

function Get-SafeVersion {
    param([string]$CurrentVersion)
    try {
        $major = ([version]$CurrentVersion).Major.ToString()
        if ($SafeVersionMap.ContainsKey($major)) { return $SafeVersionMap[$major] }
    } catch {}
    # Default to latest 8.x if unknown
    return "8.0.21"
}

function Get-LatestNexusVersion {
    param([string]$Package, [string]$MinVersion)
    $pkgLower = $Package.ToLower()
    try {
        $resp = Invoke-RestMethod -Uri "$NexusBaseUrl/service/rest/v1/search?repository=$NexusRepo&name=$Package&sort=version&direction=desc" -UseBasicParsing -TimeoutSec 30
        $ver  = $resp.items | ForEach-Object { $_.version } |
                Where-Object { $_ -match '^\d+\.\d+\.\d+$' } |
                Sort-Object  { [version]$_ } -Descending |
                Where-Object { [version]$_ -ge [version]$MinVersion } |
                Select-Object -First 1
        if ($ver) { Write-Log "REST API found: $Package $ver"; return $ver }
        Write-Log "REST API: no version >= $MinVersion" "WARN"
    } catch { Write-Log "REST API error: $_" "WARN" }
    try {
        $html = Invoke-WebRequest -Uri "$NexusBaseUrl/service/rest/repository/browse/$NexusRepo/$pkgLower/" -UseBasicParsing -TimeoutSec 30
        $ver  = ([regex]'href="(\d+\.\d+\.\d+)/"').Matches($html.Content) |
                ForEach-Object { $_.Groups[1].Value } |
                Where-Object   { [version]$_ -ge [version]$MinVersion } |
                Sort-Object    { [version]$_ } -Descending |
                Select-Object  -First 1
        if ($ver) { Write-Log "Browse scrape found: $Package $ver"; return $ver }
        Write-Log "Browse scrape: no version >= $MinVersion" "WARN"
    } catch { Write-Log "Browse scrape error: $_" "WARN" }
    return $null
}

function Get-NupkgUrl {
    param([string]$Package, [string]$Version)
    $pkgLower = $Package.ToLower()
    try {
        $html  = Invoke-WebRequest -Uri "$NexusBaseUrl/service/rest/repository/browse/$NexusRepo/$pkgLower/$Version/" -UseBasicParsing -TimeoutSec 30
        $match = ([regex]'href="([^"]*\.nupkg)"').Matches($html.Content) | Select-Object -First 1
        if ($match) { return "$NexusBaseUrl/service/rest/repository/browse/$NexusRepo/$pkgLower/$Version/$($match.Groups[1].Value)" }
    } catch {}
    return "$NexusBaseUrl/repository/$NexusRepo/$pkgLower/$Version/$pkgLower.$Version.nupkg"
}

function Find-AllKestrelInstalls {
    $depsFiles = Get-ChildItem -Path $PluginBase -Recurse -Filter "*.deps.json" -ErrorAction SilentlyContinue
    $results   = @()
    foreach ($f in $depsFiles) {
        $c = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
        if ($c -match '"Microsoft\.AspNetCore\.Server\.Kestrel\.Core/([\d\.]+)"') {
            $results += [PSCustomObject]@{
                Version  = $Matches[1]
                DepsFile = $f.FullName
                CsprojDir= $f.DirectoryName
            }
        }
    }
    return $results
}

function Is-Vulnerable {
    param([string]$Version)
    try {
        $major = ([version]$Version).Major
        if ($major -eq 2) { return [version]$Version -le [version]"2.3.0" }
        if ($major -eq 8) { return [version]$Version -le [version]"8.0.20" }
        return $false
    } catch { return $false }
}

# ── MAIN ──
New-Item -ItemType Directory -Path (Split-Path $LogFile) -Force | Out-Null
Write-Log "--- KestrelCore Update | CVE-2025-55315 | Machine: $env:COMPUTERNAME ---"
Write-Log "Safe versions: 2.x -> 2.3.6 | 8.x -> 8.0.21"

# Find ALL Kestrel installs under Plugins folder
[array]$installs = @(Find-AllKestrelInstalls)
if ($installs.Count -eq 0) {
    Write-Log "No Kestrel installs found under $PluginBase. No action needed." "SUCCESS"
    exit 0
}

Write-Log "Found $($installs.Count) Kestrel installation(s):"
foreach ($i in $installs) { Write-Log "  Version: $($i.Version) | Path: $($i.DepsFile)" }

[array]$vulnerable = @($installs | Where-Object { Is-Vulnerable $_.Version })
if ($vulnerable.Count -eq 0) {
    Write-Log "All installations are already at safe versions. No action needed." "SUCCESS"
    exit 0
}

Write-Log "Found $($vulnerable.Count) vulnerable installation(s):"
foreach ($v in $vulnerable) { Write-Log "  VULNERABLE: $($v.Version) at $($v.DepsFile)" "WARN" }

$successCount = 0
$failCount    = 0

foreach ($install in $vulnerable) {
    $currentVer  = $install.Version
    $safeVersion = Get-SafeVersion -CurrentVersion $currentVer
    Write-Log "--- Remediating $currentVer -> $safeVersion ---"

    # Backup deps.json
    $backupDir = "C:\Temp\KestrelCore_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    Copy-Item $install.DepsFile "$backupDir\" -Force
    Write-Log "Backed up -> $backupDir"

    # Get version from Nexus
    $nexusVersion = Get-LatestNexusVersion -Package $PackageName -MinVersion $safeVersion
    if (-not $nexusVersion) {
        Write-Log "$PackageName $safeVersion not in Nexus. Ask admin to cache it in $NexusRepo." "ERROR"
        $failCount++
        continue
    }
    Write-Log "Nexus version to install: $nexusVersion"

    # Download nupkg
    $nupkgUrl = Get-NupkgUrl -Package $PackageName -Version $nexusVersion
    $dlPath   = "C:\Temp\$PackageName.$nexusVersion.nupkg"
    Write-Log "Downloading from: $nupkgUrl"
    try {
        Invoke-WebRequest -Uri $nupkgUrl -OutFile $dlPath -UseBasicParsing -TimeoutSec 120
        Write-Log "Downloaded -> $dlPath ($((Get-Item $dlPath).Length) bytes)"
    } catch {
        Write-Log "Download failed: $_" "ERROR"
        $failCount++
        continue
    }

    # Try dotnet add package in the same directory as the deps.json
    $csprojFiles = Get-ChildItem -Path $install.CsprojDir -Filter "*.csproj" -ErrorAction SilentlyContinue
    if ($csprojFiles) {
        foreach ($proj in $csprojFiles) {
            try {
                Write-Log "Running: dotnet add $($proj.FullName) package $PackageName --version $nexusVersion"
                & dotnet add $proj.FullName package $PackageName --version $nexusVersion 2>&1 | ForEach-Object { Write-Log $_ }
                $successCount++
            } catch { Write-Log "dotnet failed: $_" "WARN" }
        }
    } else {
        Write-Log "No .csproj in $($install.CsprojDir). nupkg at $dlPath for manual replacement." "WARN"
        Write-Log "ACTION: Update SqlIaaSAgent extension via Azure Portal -> VM -> Extensions -> SqlIaaSAgent -> Update" "WARN"
        $failCount++
    }
}

# Verify all installs
Write-Log "--- Verification ---"
[array]$postInstalls = @(Find-AllKestrelInstalls)
foreach ($i in $postInstalls) {
    if (Is-Vulnerable $i.Version) {
        Write-Log "STILL VULNERABLE: $($i.Version) at $($i.DepsFile)" "WARN"
    } else {
        Write-Log "SAFE: $($i.Version) at $($i.DepsFile)" "SUCCESS"
    }
}

[array]$stillVuln = @($postInstalls | Where-Object { Is-Vulnerable $_.Version })
if ($stillVuln.Count -eq 0) {
    Write-Log "--- SUCCESS: All Kestrel installs patched on $env:COMPUTERNAME ---" "SUCCESS"
} elseif ($successCount -gt 0) {
    Write-Log "--- PARTIAL: $successCount patched, $failCount need manual Azure Portal update ---" "WARN"
} else {
    Write-Log "--- ACTION REQUIRED: Update SqlIaaSAgent via Azure Portal -> VM -> Extensions -> SqlIaaSAgent -> Update ---" "WARN"
}
