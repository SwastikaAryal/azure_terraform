param(
    [string]$NexusBaseUrl  = "https://nexus.bmwgroup.net",
    [string]$NexusRepo     = "nuget_proxy",
    [string]$PackageName   = "NuGet.Packaging",
    [string]$MinVersion    = "5.11.6",
    [string]$TargetPath    = "E:\Octopus\Tools\Calamari.win-x64",
    [string]$LogFile       = "C:\Temp\NuGetPackaging_Update_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    Write-Host $entry
    Add-Content -Path $LogFile -Value $entry
}

function Parse-SafeVersion {
    param([string]$Ver)
    # Handle 4-part versions like 6.0.0.4243 -> take first 3 parts only
    try {
        $parts = $Ver -split '\.'
        $clean = ($parts[0..2] -join '.')
        return [version]$clean
    } catch { return $null }
}

function Get-BestNexusVersion {
    param([string]$Package, [string]$MinVer)
    $pkgLower = $Package.ToLower()
    $minParsed = Parse-SafeVersion -Ver $MinVer

    # Use browse scrape only - REST API returns versions not in browse index
    try {
        $html = Invoke-WebRequest -Uri "$NexusBaseUrl/service/rest/repository/browse/$NexusRepo/$pkgLower/" -UseBasicParsing -TimeoutSec 30
        $best = ([regex]'href="(\d+\.\d+[^"]*?)/"').Matches($html.Content) |
                ForEach-Object { $_.Groups[1].Value } |
                Where-Object   { $_ -match '^\d+\.\d+\.\d+' } |
                Where-Object   {
                    $parsed = Parse-SafeVersion -Ver $_
                    $parsed -ne $null -and $parsed -ge $minParsed
                } |
                Sort-Object { Parse-SafeVersion -Ver $_ } |
                Select-Object -First 1
        if ($best) { Write-Log "Browse scrape found: $Package $best"; return $best }
        Write-Log "Browse scrape: no version >= $MinVer found in Nexus" "WARN"
    } catch { Write-Log "Browse scrape error: $_" "WARN" }

    return $null
}

function Get-NupkgUrl {
    param([string]$Package, [string]$Version)
    $pkgLower = $Package.ToLower()
    # Confirmed exact URL from Nexus HTML source:
    # <a href="https://nexus.bmwgroup.net/repository/nuget_proxy/nuget.packaging/6.3.1">
    # No trailing filename - version folder IS the download endpoint
    return "$NexusBaseUrl/repository/$NexusRepo/$pkgLower/$Version"
}

function Get-CurrentVersion {
    if (-not (Test-Path $TargetPath)) {
        Write-Log "Target path not found: $TargetPath" "WARN"
        return $null, $null
    }
    [array]$depsFiles = @(Get-ChildItem -Path $TargetPath -Recurse -Filter "Calamari.deps.json" -ErrorAction SilentlyContinue)
    if ($depsFiles.Count -eq 0) { Write-Log "No Calamari.deps.json found under $TargetPath" "WARN"; return $null, $null }
    $depsFile = $depsFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $content  = Get-Content $depsFile.FullName -Raw
    if ($content -match '"NuGet\.Packaging/([\d\.]+)"') { return $Matches[1], $depsFile.FullName }
    return $null, $depsFile.FullName
}

New-Item -ItemType Directory -Path (Split-Path $LogFile) -Force | Out-Null
Write-Log "--- NuGet.Packaging Update | CVE-2024-0057 | Machine: $env:COMPUTERNAME ---"
Write-Log "Min safe version: $MinVersion | Target path: $TargetPath"

# Exit cleanly if Octopus not installed on this VM
if (-not (Test-Path $TargetPath)) {
    Write-Log "Target path not found: $TargetPath" "INFO"
    Write-Log "This VM does not have Octopus/Calamari installed. No action needed." "SUCCESS"
    exit 0
}

$nexusVersion = Get-BestNexusVersion -Package $PackageName -MinVer $MinVersion
if (-not $nexusVersion) {
    Write-Log "Cannot find $PackageName >= $MinVersion in Nexus. Ask admin to cache it in $NexusRepo." "ERROR"
    exit 1
}
Write-Log "Target version from Nexus: $nexusVersion"

$currentVersion, $depsPath = Get-CurrentVersion
if ($currentVersion) {
    Write-Log "Current version: $currentVersion"
    $currentParsed = Parse-SafeVersion -Ver $currentVersion
    $nexusParsed   = Parse-SafeVersion -Ver $nexusVersion
    if ($currentParsed -ge $nexusParsed) {
        Write-Log "Already at $currentVersion. No action needed." "SUCCESS"
        exit 0
    }
} else { Write-Log "Could not detect current version from deps.json." "WARN" }

# Backup
if ($depsPath) {
    $backupPath = "C:\Temp\NuGetPackaging_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
    Copy-Item $depsPath "$backupPath\" -Force
    Write-Log "Backed up -> $backupPath"
}

# Download nupkg
$nupkgUrl = Get-NupkgUrl -Package $PackageName -Version $nexusVersion
$dlPath   = "C:\Temp\$PackageName.$nexusVersion.nupkg"
Write-Log "Downloading from: $nupkgUrl"
try {
    $webClient = New-Object System.Net.WebClient

    $webClient.DownloadFile($nupkgUrl, $dlPath)
    $size = (Get-Item $dlPath).Length
    Write-Log "Downloaded -> $dlPath ($size bytes)"
} catch {
    Write-Log "Download failed: $_" "ERROR"
    exit 1
}

# Try dotnet add package
[array]$csprojFiles = @(Get-ChildItem -Path $TargetPath -Recurse -Filter "*.csproj" -ErrorAction SilentlyContinue)
if ($csprojFiles.Count -gt 0) {
    foreach ($proj in $csprojFiles) {
        try {
            $result = & dotnet add $proj.FullName package $PackageName --version $nexusVersion 2>&1
            Write-Log "dotnet result: $result"
        } catch { Write-Log "dotnet failed: $_" "WARN" }
    }
} else {
    Write-Log "No .csproj found. Extracting nupkg and replacing DLL directly..."
    $extractDir = "C:\Temp\NuGetPackaging_extracted"
    if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue }
    $zipPath = $dlPath -replace "\.nupkg$", ".zip"
    Copy-Item $dlPath $zipPath -Force
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
    Write-Log "Extracted to $extractDir"
    [array]$newDlls = @(Get-ChildItem $extractDir -Recurse -Filter "NuGet.Packaging.dll" -ErrorAction SilentlyContinue)
    if ($newDlls.Count -gt 0) {
        $newDll = $newDlls[0]
        Write-Log "Found patched DLL: $($newDll.FullName)"
        [array]$existingDlls = @(Get-ChildItem $TargetPath -Recurse -Filter "NuGet.Packaging.dll" -ErrorAction SilentlyContinue)
        if ($existingDlls.Count -gt 0) {
            foreach ($dll in $existingDlls) {
                try {
                    Copy-Item $newDll.FullName $dll.FullName -Force
                    Write-Log "Replaced: $($dll.FullName)" "SUCCESS"
                } catch { Write-Log "Could not replace $($dll.FullName): $_" "WARN" }
            }
        } else {
            Write-Log "No existing NuGet.Packaging.dll found in $TargetPath" "WARN"
        }
    } else {
        Write-Log "NuGet.Packaging.dll not found inside nupkg." "WARN"
    }
}
