Set-Content -Path "C:\Users\fsamdevmadmin\Desktop\02.ps1" -Encoding UTF8 -Value @'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

param(
    [string]$NexusBaseUrl   = "https://nexus.bmwgroup.net",
    [string]$NexusRepo      = "nuget_proxy",
    [string]$PackageName    = "Microsoft.AspNetCore.Server.Kestrel.Core",
    [string]$MinSafeVersion = "8.0.21",
    [string]$PluginBase     = "C:\Packages\Plugins\Microsoft.SqlServer.Management.SqlIaaSAgent",
    [string]$LogFile        = "C:\Temp\KestrelCore_Update_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    Write-Host $entry
    Add-Content -Path $LogFile -Value $entry
}

function Get-LatestNexusVersion {
    param([string]$Package, [string]$MinVersion)
    Write-Log "Trying Nexus REST API..."
    try {
        $searchUrl = "$NexusBaseUrl/service/rest/v1/search?repository=$NexusRepo&name=$Package&sort=version&direction=desc"
        $resp = Invoke-RestMethod -Uri $searchUrl -UseBasicParsing -TimeoutSec 30
        $safe = $resp.items | ForEach-Object { $_.version } |
                Where-Object { $_ -match '^\d+\.\d+\.\d+$' } |
                Sort-Object { [version]$_ } -Descending |
                Where-Object { [version]$_ -ge [version]$MinVersion } |
                Select-Object -First 1
        if ($safe) { Write-Log "Found via REST API: $safe"; return $safe }
        Write-Log "REST API returned no version >= $MinVersion" "WARN"
    } catch {
        Write-Log "Nexus REST API error: $_" "WARN"
    }
    Write-Log "Trying Nexus browse page scrape..."
    try {
        $browseUrl = "$NexusBaseUrl/service/rest/repository/browse/$NexusRepo/$Package/"
        $html = Invoke-WebRequest -Uri $browseUrl -UseBasicParsing -TimeoutSec 30
        $safe = ([regex]'href="(\d+\.\d+\.\d+)/"').Matches($html.Content) |
               ForEach-Object { $_.Groups[1].Value } |
               Where-Object { [version]$_ -ge [version]$MinVersion } |
               Sort-Object { [version]$_ } -Descending |
               Select-Object -First 1
        if ($safe) { Write-Log "Found via browse scrape: $safe"; return $safe }
        Write-Log "Browse scrape returned no version >= $MinVersion" "WARN"
    } catch {
        Write-Log "Nexus browse scrape error: $_" "WARN"
    }
    return $null
}

function Get-CurrentKestrelVersion {
    $depsFiles = Get-ChildItem -Path $PluginBase -Recurse -Filter "*.deps.json" -ErrorAction SilentlyContinue
    foreach ($f in $depsFiles) {
        $content = Get-Content $f.FullName -Raw
        if ($content -match '"Microsoft\.AspNetCore\.Server\.Kestrel\.Core/([\d\.]+)"') {
            return $Matches[1], $f.FullName
        }
    }
    return $null, $null
}

New-Item -ItemType Directory -Path (Split-Path $LogFile) -Force | Out-Null
Write-Log "--- Kestrel.Core Update Started | CVE-2025-55315 | Min safe: $MinSafeVersion ---"

$latestVersion = Get-LatestNexusVersion -Package $PackageName -MinVersion $MinSafeVersion
if (-not $latestVersion) { Write-Log "No version >= $MinSafeVersion found in Nexus. Aborting." "ERROR"; exit 1 }
Write-Log "Target version: $latestVersion"

$currentVersion, $depsPath = Get-CurrentKestrelVersion
if ($currentVersion) {
    Write-Log "Current version: $currentVersion"
    if ([version]$currentVersion -ge [version]$latestVersion) { Write-Log "Already at $currentVersion. No action needed." "SUCCESS"; exit 0 }
} else {
    Write-Log "Could not detect current version from deps.json." "WARN"
}

if ($depsPath) {
    $backupDir = "C:\Temp\KestrelCore_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    Copy-Item $depsPath "$backupDir\" -Force
    Write-Log "Backed up $depsPath -> $backupDir"
}

$azAvailable = Get-Command az -ErrorAction SilentlyContinue
if ($azAvailable) {
    try {
        $vmMeta = Invoke-RestMethod -Uri "http://169.254.169.254/metadata/instance?api-version=2021-02-01" -Headers @{Metadata="true"} -UseBasicParsing -TimeoutSec 10
        & az vm extension set --resource-group $vmMeta.compute.resourceGroupName --vm-name $vmMeta.compute.name --name "SqlIaaSAgent" --publisher "Microsoft.SqlServer.Management" --force-update 2>&1 | ForEach-Object { Write-Log $_ }
        Write-Log "Azure CLI extension update triggered."
    } catch { Write-Log "Azure CLI method failed: $_" "WARN" }
} else { Write-Log "Azure CLI not found. Skipping." "WARN" }

$nupkgUrl = "$NexusBaseUrl/service/rest/repository/browse/$NexusRepo/$PackageName/$latestVersion/$PackageName.$latestVersion.nupkg"
$dlPath = "C:\Temp\$PackageName.$latestVersion.nupkg"
Write-Log "Downloading nupkg from: $nupkgUrl"
try {
    Invoke-WebRequest -Uri $nupkgUrl -OutFile $dlPath -UseBasicParsing -TimeoutSec 120
    Write-Log "Downloaded -> $dlPath ($((Get-Item $dlPath).Length) bytes)"
} catch { Write-Log "Nexus download failed: $_" "ERROR" }

$csprojFiles = Get-ChildItem -Path $PluginBase -Recurse -Filter "*.csproj" -ErrorAction SilentlyContinue
foreach ($proj in $csprojFiles) {
    try {
        & dotnet add $proj.FullName package $PackageName --version $latestVersion 2>&1 | ForEach-Object { Write-Log $_ }
    } catch { Write-Log "dotnet update failed for $($proj.Name): $_" "WARN" }
}

$newVersion, $_ = Get-CurrentKestrelVersion
if ($newVersion -and ([version]$newVersion -ge [version]$MinSafeVersion)) {
    Write-Log "SUCCESS: Kestrel.Core updated to $newVersion" "SUCCESS"
} else {
    Write-Log "ACTION REQUIRED: Azure Portal -> VM (fs-msl-app1) -> Extensions + Applications -> SqlIaaSAgent -> Update" "WARN"
}
'@
