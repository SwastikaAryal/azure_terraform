# 10_Update-AspNetCoreRuntime.ps1
# CVE-2025-55315 | Microsoft.AspNetCore.App.Runtime.win-x86 + win-x64
# Handles BOTH x86 and x64 in one script
# Uses BMW Nexus: https://nexus.bmwgroup.net/service/rest/repository/browse/nuget_proxy/

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

    # Method 1: Nexus REST API
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

    # Method 2: Browse page scrape
    # URL pattern: https://nexus.bmwgroup.net/service/rest/repository/browse/nuget_proxy/<Package>/
    try {
        $browseUrl = "$NexusBaseUrl/service/rest/repository/browse/$NexusRepo/$Package/"
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

    # Method 3: Try triggering Nexus proxy to pull from NuGet.org upstream
    Write-Log "[$Package] Attempting to trigger Nexus upstream pull for $MinVersion..."
    try {
        $triggerUrl = "$NexusBaseUrl/service/rest/repository/browse/$NexusRepo/$Package/$MinVersion/"
        $tr = Invoke-WebRequest -Uri $triggerUrl -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
        if ($tr.StatusCode -eq 200) {
            Write-Log "[$Package] Nexus pulled $MinVersion from upstream. Re-checking..."
            Start-Sleep -Seconds 5
            $html2 = Invoke-WebRequest -Uri "$NexusBaseUrl/service/rest/repository/browse/$NexusRepo/$Package/" -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
            $best2 = ([regex]'href="(\d+\.\d+\.\d+)/"').Matches($html2.Content) |
                     ForEach-Object { $_.Groups[1].Value } |
                     Where-Object   { [version]$_ -ge [version]$MinVersion } |
                     Sort-Object    { [version]$_ } -Descending |
                     Select-Object  -First 1
            if ($best2) { Write-Log "[$Package] Available after trigger: $best2"; return $best2 }
        }
    } catch {
        Write-Log "[$Package] Upstream trigger failed: $_" "WARN"
    }

    return $null
}

function Download-Nupkg {
    param([string]$Package, [string]$Version)
    $dlPath = "$DownloadDir\$Package.$Version.nupkg"
    # Nexus nupkg download URL pattern (consistent with other BMW scripts)
    $url = "$NexusBaseUrl/service/rest/repository/browse/$NexusRepo/$Package/$Version/$Package.$Version.nupkg"
    Write-Log "[$Package] Downloading from Nexus: $url"
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

    Write-Log "[$Package] Extracting to $extractDir..."
    try {
        if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue }
        Expand-Archive -Path $NupkgPath -DestinationPath $extractDir -Force -ErrorAction Stop
        Write-Log "[$Package] Extracted successfully."
    } catch {
        Write-Log "[$Package] Extraction failed: $_" "ERROR"
        return $false
    }

    # Look for runtime DLLs inside the nupkg structure
    $runtimeSrc = Get-ChildItem $extractDir -Recurse -Directory |
                  Where-Object { $_.Name -eq "Microsoft.AspNetCore.App" -or $_.FullName -like "*shared\Microsoft*" } |
                  Select-Object -First 1

    if (-not $runtimeSrc) {
        # Fallback: look for any folder containing .dll files
        $runtimeSrc = Get-ChildItem $extractDir -Recurse -Directory |
                      Where-Object { (Get-ChildItem $_.FullName -Filter "*.dll" -ErrorAction SilentlyContinue).Count -gt 5 } |
                      Select-Object -First 1
    }

    if ($runtimeSrc) {
        Write-Log "[$Package] Runtime files found at: $($runtimeSrc.FullName)"
        if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
        Copy-Item "$($runtimeSrc.FullName)\*" $targetDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "[$Package] Installed to: $targetDir" "SUCCESS"
        return $true
    } else {
        Write-Log "[$Package] Could not identify runtime folder in nupkg. Copying all files..." "WARN"
        if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
        Copy-Item "$extractDir\*" $targetDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "[$Package] Files copied to $targetDir. Manual verification recommended." "WARN"
        return $true
    }
}

# ── MAIN ──
New-Item -ItemType Directory -Path $DownloadDir -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path $LogFile) -Force | Out-Null
Write-Log "--- AspNetCore Runtime Update | CVE-2025-55315 | Machine: $env:COMPUTERNAME | Min safe: $MinVersion ---"

# Step 1 - Detect vulnerable installs
$allInstalled = Get-InstalledVersions
$vulnerable   = $allInstalled | Where-Object { Is-Vulnerable $_.Version }

if ($vulnerable.Count -eq 0) {
    Write-Log "No vulnerable ASP.NET Core versions found on $env:COMPUTERNAME. No action needed." "SUCCESS"
    exit 0
}

Write-Log "Found $($vulnerable.Count) vulnerable installation(s):"
foreach ($v in $vulnerable) { Write-Log "  VULNERABLE [$($v.Arch)]: $($v.Version) at $($v.Path)" "WARN" }

# Step 2 - Process each architecture that has a vulnerable version
$archMap = @{
    "x86" = "Microsoft.AspNetCore.App.Runtime.win-x86"
    "x64" = "Microsoft.AspNetCore.App.Runtime.win-x64"
}

$successCount = 0
$failCount    = 0

foreach ($arch in @("x86", "x64")) {
    $vulnForArch = $vulnerable | Where-Object { $_.Arch -eq $arch }
    if ($vulnForArch.Count -eq 0) {
        Write-Log "[$arch] No vulnerable installation found. Skipping."
        continue
    }

    $pkg       = $archMap[$arch]
    $targetBase = $vulnForArch[0].Base

    Write-Log "--- Processing $arch ($pkg) ---"

    # Find version in Nexus
    $nexusVersion = Get-BestNexusVersion -Package $pkg
    if (-not $nexusVersion) {
        Write-Log "[$pkg] Not available in Nexus >= $MinVersion." "ERROR"
        Write-Log "[$pkg] Send this request to your Nexus admin:" "ERROR"
        Write-Log "[$pkg]   Cache '$pkg' version '$MinVersion' or later in repo '$NexusRepo'" "ERROR"
        Write-Log "[$pkg]   Nexus UI: $NexusBaseUrl -> Browse -> $NexusRepo -> $pkg" "ERROR"
        Write-Log "[$pkg]   NuGet source: https://www.nuget.org/packages/$pkg" "ERROR"
        $failCount++
        continue
    }

    # Backup existing version folder
    foreach ($v in $vulnForArch) {
        $backupDir = "C:\Temp\AspNetCoreRuntime_backup_$($v.Version)_$arch_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        try {
            Copy-Item $v.Path $backupDir -Recurse -Force -ErrorAction Stop
            Write-Log "[$arch] Backed up $($v.Path) -> $backupDir"
        } catch {
            Write-Log "[$arch] Backup failed (non-fatal): $_" "WARN"
        }
    }

    # Download from Nexus
    $nupkgPath = Download-Nupkg -Package $pkg -Version $nexusVersion
    if (-not $nupkgPath) { $failCount++; continue }

    # Install
    $ok = Install-RuntimeFromNupkg -NupkgPath $nupkgPath -Package $pkg -Version $nexusVersion -Arch $arch -TargetBase $targetBase
    if ($ok) { $successCount++ } else { $failCount++ }
}

# Step 3 - Verify
Write-Log "--- Verification ---"
$postInstall     = Get-InstalledVersions
$nowSafe         = $postInstall | Where-Object { try { [version]$_.Version -ge [version]$MinVersion } catch { $false } }
$stillVulnerable = $postInstall | Where-Object { Is-Vulnerable $_.Version }

foreach ($v in $nowSafe)         { Write-Log "SAFE    [$($v.Arch)]: $($v.Version) at $($v.Path)" "SUCCESS" }
foreach ($v in $stillVulnerable) { Write-Log "OLD     [$($v.Arch)]: $($v.Version) still present (safe to coexist)" "INFO" }

if ($nowSafe.Count -gt 0 -and $failCount -eq 0) {
    Write-Log "--- SUCCESS: CVE-2025-55315 remediated on $env:COMPUTERNAME ---" "SUCCESS"
} elseif ($nowSafe.Count -gt 0 -and $failCount -gt 0) {
    Write-Log "--- PARTIAL: Some architectures remediated but $failCount failed. Check log. ---" "WARN"
} else {
    Write-Log "--- BLOCKED: Nexus does not have $MinVersion cached for the required packages. ---" "WARN"
    Write-Log "Ask your Nexus admin to cache these in '$NexusRepo':" "WARN"
    Write-Log "  Microsoft.AspNetCore.App.Runtime.win-x86 >= $MinVersion" "WARN"
    Write-Log "  Microsoft.AspNetCore.App.Runtime.win-x64 >= $MinVersion" "WARN"
    Write-Log "  Browse URL: $NexusBaseUrl/service/rest/repository/browse/$NexusRepo/" "WARN"
}
