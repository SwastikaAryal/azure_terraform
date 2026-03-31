param(
    [string]$NexusBaseUrl  = "https://nexus.bmwgroup.net",
    [string]$NexusMvnRepo  = "maven-central",
    [string]$GroupId       = "commons-collections",
    [string]$ArtifactId    = "commons-collections",
    [string]$JarDir        = "C:\Program Files\Microsoft SQL Server\160\DTS\Extensions\Common\Jars",
    [string]$ServiceName   = "MsDtsServer160",
    [string]$LogFile       = "C:\Temp\CommonsCollections_Update_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    Write-Host $entry
    Add-Content -Path $LogFile -Value $entry
}

function Get-LatestMavenVersion {
    param([string]$Group, [string]$Artifact)
    $groupPath = $Group -replace '\.', '/'
    # Method 1: Nexus Maven proxy metadata
    try {
        $metaUrl  = "$NexusBaseUrl/repository/$NexusMvnRepo/$groupPath/$Artifact/maven-metadata.xml"
        Write-Log "Checking Nexus Maven metadata: $metaUrl"
        $xml      = Invoke-RestMethod -Uri $metaUrl -UseBasicParsing -TimeoutSec 30
        $latest   = $xml.metadata.versioning.latest
        if (-not $latest) { $latest = $xml.metadata.versioning.release }
        if ($latest) { Write-Log "Found via Nexus Maven proxy: $Artifact $latest"; return $latest }
    } catch { Write-Log "Nexus Maven proxy error: $_" "WARN" }
    # Method 2: Nexus REST search
    try {
        $resp   = Invoke-RestMethod -Uri "$NexusBaseUrl/service/rest/v1/search?repository=$NexusMvnRepo&name=$Artifact&sort=version&direction=desc" -UseBasicParsing -TimeoutSec 30
        $latest = $resp.items | ForEach-Object { $_.version } |
                  Where-Object { $_ -match '^[\d]+\.[\d]+' -and $_ -notlike '*SNAPSHOT*' -and $_ -notlike '*alpha*' -and $_ -notlike '*beta*' } |
                  Sort-Object  { [version]($_ -replace '[^0-9.]','') } -Descending |
                  Select-Object -First 1
        if ($latest) { Write-Log "Found via Nexus REST search: $Artifact $latest"; return $latest }
    } catch { Write-Log "Nexus REST search error: $_" "WARN" }
    return $null
}

function Get-JarDownloadUrl {
    param([string]$Group, [string]$Artifact, [string]$Version)
    $groupPath = $Group -replace '\.', '/'
    return "$NexusBaseUrl/repository/$NexusMvnRepo/$groupPath/$Artifact/$Version/$Artifact-$Version.jar"
}

New-Item -ItemType Directory -Path (Split-Path $LogFile) -Force | Out-Null
Write-Log "--- CommonsCollections Update | CVE-2015-7501 | Machine: $env:COMPUTERNAME ---"

$latestVersion = Get-LatestMavenVersion -Group $GroupId -Artifact $ArtifactId
if (-not $latestVersion) {
    Write-Log "$ArtifactId not found in Nexus Maven proxy ($NexusMvnRepo)." "ERROR"
    Write-Log "Ask your Nexus admin to set up a Maven proxy repo pointing to $NexusBaseUrl/repository/$NexusMvnRepo" "ERROR"
    Write-Log "Or manually upload $ArtifactId JAR to Nexus and re-run this script." "ERROR"
    exit 1
}
Write-Log "Target version: $latestVersion"

# Find existing JAR
$existingJars = Get-ChildItem -Path $JarDir -Filter "$ArtifactId-*.jar" -ErrorAction SilentlyContinue
if ($existingJars) {
    foreach ($j in $existingJars) {
        Write-Log "Found existing JAR: $($j.Name)"
        if ($j.Name -match 'commons-collections-([\d\.]+)\.jar') {
            $currentVersion = $Matches[1]
            Write-Log "Current version: $currentVersion"
        }
    }
} else { Write-Log "No existing $ArtifactId JAR found in $JarDir" "WARN" }

# Backup
$backupDir = "C:\Temp\CommonsCollections_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
foreach ($j in $existingJars) {
    Copy-Item $j.FullName "$backupDir\" -Force
    Write-Log "Backed up $($j.Name) -> $backupDir"
}

# Stop service
Write-Log "Stopping $ServiceName..."
try { Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 5 }
catch { Write-Log "Could not stop $ServiceName : $_" "WARN" }

# Download from Nexus
$jarUrl  = Get-JarDownloadUrl -Group $GroupId -Artifact $ArtifactId -Version $latestVersion
$newJar  = Join-Path $JarDir "$ArtifactId-$latestVersion.jar"
Write-Log "Downloading from Nexus: $jarUrl"
try {
    Invoke-WebRequest -Uri $jarUrl -OutFile $newJar -UseBasicParsing -TimeoutSec 120
    $size = (Get-Item $newJar).Length
    Write-Log "Downloaded $newJar ($size bytes)"
    if ($size -lt 50000) { Write-Log "WARNING: JAR suspiciously small ($size bytes). Verify manually." "WARN" }
} catch {
    Write-Log "Download failed: $_" "ERROR"
    Start-Service -Name $ServiceName -ErrorAction SilentlyContinue
    exit 1
}

# Remove old JARs
foreach ($j in $existingJars) {
    Remove-Item $j.FullName -Force -ErrorAction SilentlyContinue
    Write-Log "Removed old JAR: $($j.Name)"
}

# Restart service
Write-Log "Restarting $ServiceName..."
try {
    Start-Service -Name $ServiceName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    Write-Log "Service status: $($svc.Status)"
} catch { Write-Log "Service restart failed: $_" "WARN" }

# Verify
if ((Test-Path $newJar) -and -not (Get-ChildItem $JarDir -Filter "$ArtifactId-*" | Where-Object { $_.Name -ne "$ArtifactId-$latestVersion.jar" })) {
    Write-Log "--- SUCCESS: $ArtifactId updated to $latestVersion ---" "SUCCESS"
} else {
    Write-Log "--- VERIFY MANUALLY: Check $JarDir ---" "WARN"
}
