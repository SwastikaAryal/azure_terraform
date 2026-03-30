# CVE-2025-55315 | Microsoft.AspNetCore.App.Runtime.win-x86
# MODE: CHECK ONLY - makes no changes, just reports what it finds

$ErrorActionPreference = "SilentlyContinue"

Write-Host ""
Write-Host "=== CVE-2025-55315 Diagnostic Check ===" -ForegroundColor Cyan
Write-Host "Library : Microsoft.AspNetCore.App.Runtime.win-x86"
Write-Host "Vulnerable : >= 8.0.0 and <= 8.0.20"
Write-Host "Safe       : >= 8.0.21"
Write-Host ""

# Step 1 - Find all ASP.NET Core versions installed under dotnet\shared
Write-Host "--- Step 1: Scanning installed ASP.NET Core versions ---" -ForegroundColor Yellow
$searchPaths = @(
    "C:\Program Files (x86)\dotnet\shared\Microsoft.AspNetCore.App",
    "C:\Program Files\dotnet\shared\Microsoft.AspNetCore.App"
)

$found = @()
foreach ($basePath in $searchPaths) {
    if (Test-Path $basePath) {
        Write-Host "Found base path: $basePath" -ForegroundColor Green
        $versions = Get-ChildItem $basePath -Directory -ErrorAction SilentlyContinue
        foreach ($v in $versions) {
            $depsFile = Join-Path $v.FullName "Microsoft.AspNetCore.App.deps.json"
            $status = if ([version]$v.Name -ge [version]"8.0.21") { "SAFE" } 
                      elseif ([version]$v.Name -ge [version]"8.0.0") { "VULNERABLE" }
                      else { "NOT AFFECTED" }
            $color = if ($status -eq "SAFE") { "Green" } elseif ($status -eq "VULNERABLE") { "Red" } else { "Gray" }
            Write-Host "  Version: $($v.Name) | deps.json exists: $(Test-Path $depsFile) | Status: $status" -ForegroundColor $color
            $found += [PSCustomObject]@{ Version=$v.Name; Path=$v.FullName; DepsExists=(Test-Path $depsFile); Status=$status }
        }
    } else {
        Write-Host "Path not found: $basePath" -ForegroundColor Gray
    }
}

if ($found.Count -eq 0) {
    Write-Host "No ASP.NET Core installations found. This CVE does not apply to this VM." -ForegroundColor Green
    exit 0
}

# Step 2 - Check Nexus connectivity
Write-Host ""
Write-Host "--- Step 2: Checking Nexus connectivity ---" -ForegroundColor Yellow
try {
    $resp = Invoke-RestMethod -Uri "https://nexus.bmwgroup.net/service/rest/v1/search?repository=nuget_proxy&name=Microsoft.AspNetCore.App.Runtime.win-x86&sort=version&direction=desc" -UseBasicParsing -TimeoutSec 15
    $versions = $resp.items | ForEach-Object { $_.version } | Where-Object { $_ -match '^\d+\.\d+\.\d+$' } | Sort-Object { [version]$_ } -Descending
    $safeVersion = $versions | Where-Object { [version]$_ -ge [version]"8.0.21" } | Select-Object -First 1
    Write-Host "Nexus reachable: YES" -ForegroundColor Green
    Write-Host "Latest safe version in Nexus: $safeVersion" -ForegroundColor Green
} catch {
    Write-Host "Nexus reachable: NO - $_" -ForegroundColor Red
    Write-Host "Will need to download dotnet runtime directly or use Windows Update." -ForegroundColor Yellow
}

# Step 3 - Check dotnet CLI
Write-Host ""
Write-Host "--- Step 3: Checking dotnet CLI ---" -ForegroundColor Yellow
$dotnetCmd = Get-Command dotnet -ErrorAction SilentlyContinue
if ($dotnetCmd) {
    Write-Host "dotnet CLI found: $($dotnetCmd.Source)" -ForegroundColor Green
    & dotnet --list-runtimes 2>$null | Where-Object { $_ -like "*AspNetCore*" } | ForEach-Object { Write-Host "  $_" }
} else {
    Write-Host "dotnet CLI not found in PATH" -ForegroundColor Red
}

# Step 4 - Check Azure CLI
Write-Host ""
Write-Host "--- Step 4: Checking Azure CLI ---" -ForegroundColor Yellow
$azCmd = Get-Command az -ErrorAction SilentlyContinue
if ($azCmd) {
    Write-Host "Azure CLI found: YES" -ForegroundColor Green
} else {
    Write-Host "Azure CLI found: NO" -ForegroundColor Red
}

# Summary
Write-Host ""
Write-Host "=== SUMMARY ===" -ForegroundColor Cyan
$vulnerable = $found | Where-Object { $_.Status -eq "VULNERABLE" }
if ($vulnerable.Count -gt 0) {
    Write-Host "VULNERABLE versions found:" -ForegroundColor Red
    foreach ($v in $vulnerable) {
        Write-Host "  $($v.Version) at $($v.Path)" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "ACTION: Run the remediation script to upgrade to 8.0.21+" -ForegroundColor Yellow
} else {
    Write-Host "No vulnerable versions found on this VM." -ForegroundColor Green
}
Write-Host ""
