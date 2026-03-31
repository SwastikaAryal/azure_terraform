# 10_Update-AspNetCoreRuntime.ps1
# CVE-2025-55315 | Microsoft.AspNetCore.App.Runtime.win-x86 + win-x64
# Handles BOTH x86 and x64 in one script
# Uses BMW Nexus: https://nexus.bmwgroup.net

param(
    [string]$NexusBaseUrl = "https://nexus.bmwgroup.net",
    [string]$NexusRepo    = "nuget_proxy",
    [string]$MinVersion   = "8.0.21",
    [string]$DownloadDir  = "C:\Temp\AspNetCoreRuntime",
    [string]$LogFile      = "C:\Temp\AspNetCoreRuntime_Update_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
)

$ErrorActionPreference = "SilentlyContinue"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    Write-Host $entry
    Add-Content -Path $LogFile -Value $entry
}

function Get-InstalledVersions {
    $searchPaths = @(
        [PSCustomObject]@{ Arch="x86"; Base="C:\Program Files (x86)\dotnet\shared\Microsoft.AspNetCore.App" },
        [PSCustomObject]@{ Arch="x64"; Base="C:\Program Files\dotnet\shared\Microsoft.AspNetCore.App" }
    )
    $results = @()
    foreach ($sp in $searchPaths) {
        if (Test-Path $sp.Base) {
            Get-ChildItem $sp.Base -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $results += [PSCustomObject]@{
                    Arch    = $sp.Arch
                    Version = $_.Name
                    Path    = $_.FullName
                    Base    = $sp.Base
                }
            }
        }
    }
    return $results
}

function Is-Vulnerable {
    param([string]$Version)
    try { return ([version]$Version -ge [version]"8.0.0" -and [version]$Version -le [version]"8.0.20") }
    catch { return $false }
}

function Get-BestNexusVersion {
    param([string]$Package)
    $pkgLower = $Package.ToLower()

    # Method 1: REST API
    try {
        $url  = "$NexusBaseUrl/service/rest/v1/search?repository=$NexusRepo&name=$Package&sort=version&direction=desc"
        $resp = Invoke-RestMethod -Uri $url -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        $best = $resp.items |
                ForEach-Object { $_.version } |
                Where-Object   { $_ -match '^\d+\.\d+\.\d+$' } |
                Sort-Object    { [version]$_ } -Descending |
                Where-Object   { [version]$_ -ge [version]$MinVersion } |
                Select-Object  -First 1
        if ($best) { Write-Log "[$Package] REST API found: $best"; return $best }
        Write-Log "[$Package] REST API: no version >= $MinVersion" "WARN"
    } catch {
        Write-Log "[$Package] REST API error: $_" "WARN"
    }

    # Method 2: Browse page scrape (lowercase URL)
    try {
        $browseUrl = "$NexusBaseUrl/service/rest/repository/browse/$NexusRepo/$pkgLower/"
        Write-Log "[$Package] Scraping: $browseUrl"
        $html = Invoke-WebRequest -Uri $browseUrl -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        $best = ([regex]'href="(\d+\.\d+\.\d+)/"').Matches($html.Content) |
                ForEach-Object { $_.Groups[1].Value } |
                Where-Object   { [version]$_ -ge [version]$MinVersion } |
                Sort-Object    { [version]$_ } -Descending |
                Select-Object  -First 1
        if ($best) { Write-Log "[$Package] Browse scrape found: $best"; return $best }
        Write-Log "[$Package] Browse scrape: no version >= $MinVersion" "WARN"
    } catch {
        Write-Log "[$Package] Browse scrape error: $_" "WARN"
    }

    return $null
}

function Get-NupkgDownloadUrl {
    param([string]$Package, [string]$Version)
    $pkgLower = $Package.ToLower()

    # Try to find the actual .nupkg filename from the Nexus version browse page
    # Nexus shows the actual filenames available - don't guess the filename
    try {
        $versionBrowseUrl = "$NexusBaseUrl/service/rest/repository/browse/$NexusRepo/$pkgLower/$Version/"
        Write-Log "[$Package] Checking version page: $versionBrowseUrl"
        $html = Invoke-WebRequest -Uri $versionBrowseUrl -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        # Find the .nupkg link on the page
        $nupkgMatch = ([regex]'href="([^"]*\.nupkg)"').Matches($html.Content) | Select-Object -First 1
        if ($nupkgMatch) {
            $filename = $nupkgMatch.Groups[1].Value
            # If relative path, build full URL
            if ($filename -notlike "http*") {
                $url = "$NexusBaseUrl/service/rest/repository/browse/$NexusRepo/$pkgLower/$Version/$filename"
            } else {
                $url = $filename
            }
            Write-Log "[$Package] Found nupkg filename from page: $filename"
            return $url
        }
    } catch {
        Write-Log "[$Package] Version page scrape failed: $_" "WARN"
    }

    # Fallback: try both common Nexus nupkg URL formats
    $urls = @(
        # Format 1: lowercase package name in filename
        "$NexusBaseUrl/repository/$NexusRepo/$pkgLower/$Version/$pkgLower.$Version.nupkg",
        # Format 2: Nexus v2 NuGet endpoint
        "$NexusBaseUrl/repository/$NexusRepo/v2/package/$Package/$Version",
        # Format 3: v3 flat endpoint
        "$NexusBaseUrl/repository/$NexusRepo/v3/flat2/$pkgLower/$Version/$pkgLower.$Version.nupkg"
    )

    foreach ($url in $urls) {
        try {
            Write-Log "[$Package] Trying URL format: $url"
            $check = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
            if ($check.StatusCode -eq 200) {
                Write-Log "[$Package] Valid URL found: $url"
                return $url
            }
        } catch {}
    }

    return $null
}

function Download-Nupkg {
    param([string]$Package, [string]$Version)
    $dlPath = "$DownloadDir\$Package.$Version.nupkg"

    $url = Get-NupkgDownloadUrl -Package $Package -Version $Version
    if (-not $url) {
        Write-Log "[$Package] Could not determine valid download URL for $Version" "ERROR"
        return $null
    }

    Write-Log "[$Package] Downloading from: $url"
    try {
        Invoke-WebRequest -Uri $url -OutFile $dlPath -UseBasicParsing -TimeoutSec 300 -ErrorAction Stop
        $size = (Get-Item $dlPath -ErrorAction Stop).Length
        Write-Log "[$Package] Downloaded: $dlPath ($size bytes)"
        if ($size -lt 10000) { Write-Log "[$Package] File too small, likely invalid." "WARN"; return $null }
        return $dlPath
    } catch {
        Write-Log "[$Package] Download failed: $_" "ERROR"
        return $null
    }
}

function Install-RuntimeFromNupkg {
    param([string]$NupkgPath, [string]$Package, [string]$Version, [string]$Arch, [string]$TargetBase)
    $targetDir  = "$TargetBase\$Version"
    $extractDir = "$DownloadDir\extracted\$Package.$Version"

    Write-Log "[$Package] Extracting nupkg..."
    try {
        if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue }
        Expand-Archive -Path $NupkgPath -DestinationPath $extractDir -Force -ErrorAction Stop
    } catch {
        Write-Log "[$Package] Extraction failed: $_" "ERROR"
        return $false
    }

    # Find folder with the most DLLs
    $runtimeSrc = Get-ChildItem $extractDir -Recurse -Directory |
                  Where-Object { (Get-ChildItem $_.FullName -Filter "*.dll" -ErrorAction SilentlyContinue).Count -gt 3 } |
                  Sort-Object  { (Get-ChildItem $_.FullName -Filter "*.dll").Count } -Descending |
                  Select-Object -First 1

    if (-not $runtimeSrc) { $runtimeSrc = Get-Item $extractDir }

    Write-Log "[$Package] Installing: $($runtimeSrc.FullName) -> $targetDir"
    try {
        if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
        Copy-Item "$($runtimeSrc.FullName)\*" $targetDir -Recurse -Force -ErrorAction Stop
        Write-Log "[$Package] Installed to: $targetDir" "SUCCESS"
        return $true
    } catch {
        Write-Log "[$Package] Copy failed: $_" "ERROR"
        return $false
    }
}

# ── MAIN ──
New-Item -ItemType Directory -Path $DownloadDir -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path $LogFile) -Force | Out-Null
Write-Log "--- AspNetCore Runtime Update | CVE-2025-55315 | Machine: $env:COMPUTERNAME | Min safe: $MinVersion ---"

$allInstalled = Get-InstalledVersions
$vulnerable   = $allInstalled | Where-Object { Is-Vulnerable $_.Version }

if ($vulnerable.Count -eq 0) {
    Write-Log "No vulnerable ASP.NET Core versions found on $env:COMPUTERNAME. No action needed." "SUCCESS"
    exit 0
}

Write-Log "Found $($vulnerable.Count) vulnerable installation(s):"
foreach ($v in $vulnerable) { Write-Log "  VULNERABLE [$($v.Arch)]: $($v.Version) at $($v.Path)" "WARN" }

$archMap = @{
    "x86" = "Microsoft.AspNetCore.App.Runtime.win-x86"
    "x64" = "Microsoft.AspNetCore.App.Runtime.win-x64"
}

$successCount = 0
$failCount    = 0

foreach ($arch in @("x86", "x64")) {
    $vulnForArch = $vulnerable | Where-Object { $_.Arch -eq $arch }
    if ($vulnForArch.Count -eq 0) { Write-Log "[$arch] No vulnerable install found. Skipping."; continue }

    $pkg        = $archMap[$arch]
    $targetBase = $vulnForArch[0].Base

    Write-Log "--- Processing $arch ($pkg) ---"

    $nexusVersion = Get-BestNexusVersion -Package $pkg
    if (-not $nexusVersion) {
        Write-Log "[$pkg] Not available in Nexus >= $MinVersion." "ERROR"
        Write-Log "[$pkg] Ask Nexus admin to cache: $pkg >= $MinVersion in repo '$NexusRepo'" "ERROR"
        $failCount++
        continue
    }

    # Backup
    foreach ($v in $vulnForArch) {
        $backupDir = "C:\Temp\AspNetCoreBackup_$($v.Version)_$arch"
        try {
            Copy-Item $v.Path $backupDir -Recurse -Force -ErrorAction Stop
            Write-Log "[$arch] Backed up -> $backupDir"
        } catch { Write-Log "[$arch] Backup skipped: $_" "WARN" }
    }

    $nupkgPath = Download-Nupkg -Package $pkg -Version $nexusVersion
    if (-not $nupkgPath) { $failCount++; continue }

    $ok = Install-RuntimeFromNupkg -NupkgPath $nupkgPath -Package $pkg -Version $nexusVersion -Arch $arch -TargetBase $targetBase
    if ($ok) { $successCount++ } else { $failCount++ }
}

# Verify
Write-Log "--- Verification ---"
$postInstall     = Get-InstalledVersions
$nowSafe         = $postInstall | Where-Object { try { [version]$_.Version -ge [version]$MinVersion } catch { $false } }
$stillVulnerable = $postInstall | Where-Object { Is-Vulnerable $_.Version }

foreach ($v in $nowSafe)         { Write-Log "SAFE [$($v.Arch)]: $($v.Version) at $($v.Path)" "SUCCESS" }
foreach ($v in $stillVulnerable) { Write-Log "OLD  [$($v.Arch)]: $($v.Version) still present (safe to coexist)" "INFO" }

if ($nowSafe.Count -gt 0 -and $failCount -eq 0) {
    Write-Log "--- SUCCESS: CVE-2025-55315 remediated on $env:COMPUTERNAME ---" "SUCCESS"
} elseif ($nowSafe.Count -gt 0 -and $failCount -gt 0) {
    Write-Log "--- PARTIAL: $successCount arch(s) done, $failCount failed. Check log. ---" "WARN"
} else {
    Write-Log "--- BLOCKED: Could not download required packages from Nexus. ---" "WARN"
    Write-Log "Check Nexus manually:" "WARN"
    Write-Log "  $NexusBaseUrl/service/rest/repository/browse/$NexusRepo/microsoft.aspnetcore.app.runtime.win-x86/" "WARN"
    Write-Log "  $NexusBaseUrl/service/rest/repository/browse/$NexusRepo/microsoft.aspnetcore.app.runtime.win-x64/" "WARN"
}
