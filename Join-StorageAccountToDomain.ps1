# Join-StorageAccountToDomain.ps1
param(
  [Parameter(Mandatory=$true)][string]$StorageAccountName,
  [Parameter(Mandatory=$true)][string]$StorageAccountResourceGroup,
  [Parameter(Mandatory=$true)][string]$DomainName,           # e.g. "corp.contoso.com"
  [Parameter(Mandatory=$true)][string]$DomainUser,           # e.g. "CORP\svc-storage"
  [Parameter(Mandatory=$false)][string]$DomainPassword,
  [string]$ShareName        = "data",                        # Azure file share name
  [string]$DriveLetter      = "Z",                           # Mount point, e.g. "Z"
  [string]$OUPath           = "",                            # OU for the storage account computer object
  [string[]]$DnsServers     = @(),
  [switch]$PersistMount     = $true                          # Create scheduled task to re-mount on logon
)

# ── Elevation check ───────────────────────────────────────────────────────────
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Error "Run this script as Administrator."; exit 1
}

# ── Build credential ──────────────────────────────────────────────────────────
if ($DomainPassword) {
  $securePwd = ConvertTo-SecureString $DomainPassword -AsPlainText -Force
  $cred = New-Object System.Management.Automation.PSCredential($DomainUser, $securePwd)
} else {
  $cred = Get-Credential -UserName $DomainUser -Message "Enter password for $DomainUser"
}

# ── Optional DNS configuration ────────────────────────────────────────────────
if ($DnsServers.Count -gt 0) {
  Write-Host "Setting DNS servers: $($DnsServers -join ',')"
  Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' } | ForEach-Object {
    try {
      Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ServerAddresses $DnsServers -ErrorAction Stop
      Write-Host "  Updated DNS on '$($_.Name)'."
    } catch {
      Write-Warning "  Failed on '$($_.Name)': $($_.Exception.Message)"
    }
  }
  Start-Sleep -Seconds 3
}

# ── Prerequisite: Az.Storage module ──────────────────────────────────────────
if (-not (Get-Module -ListAvailable -Name Az.Storage)) {
  Write-Host "Installing Az.Storage module..."
  Install-Module -Name Az.Storage -Scope CurrentUser -Force -AllowClobber
}
Import-Module Az.Storage -ErrorAction Stop

# ── Prerequisite: AzFilesHybrid module ───────────────────────────────────────
# Download from: https://github.com/Azure-Samples/azure-files-samples/releases
if (-not (Get-Module -ListAvailable -Name AzFilesHybrid)) {
  Write-Error @"
AzFilesHybrid module not found.
Download it from:
  https://github.com/Azure-Samples/azure-files-samples/releases
Extract and run .\CopyToPSPath.ps1, then re-run this script.
"@
  exit 1
}
Import-Module AzFilesHybrid -ErrorAction Stop

# ── Connect to Azure ──────────────────────────────────────────────────────────
Write-Host "Connecting to Azure (sign-in prompt may appear)..."
try {
  Connect-AzAccount -ErrorAction Stop | Out-Null
  Write-Host "  Azure connection established."
} catch {
  Write-Error "Azure login failed: $($_.Exception.Message)"; exit 1
}

# ── Domain-join the Storage Account ──────────────────────────────────────────
Write-Host "Joining storage account '$StorageAccountName' to domain '$DomainName'..."
try {
  $joinParams = @{
    ResourceGroupName                   = $StorageAccountResourceGroup
    StorageAccountName                  = $StorageAccountName
    DomainAccountType                   = "ComputerAccount"   # or "ServiceLogonAccount"
    OrganizationalUnitDistinguishedName = if ($OUPath) { $OUPath } else { $null }
  }
  # Remove null values
  $joinParams = $joinParams.GetEnumerator() |
    Where-Object { $null -ne $_.Value } |
    ForEach-Object -Begin { $h = @{} } -Process { $h[$_.Key] = $_.Value } -End { $h }

  Join-AzStorageAccountForAuth @joinParams -ErrorAction Stop
  Write-Host "  Storage account successfully joined to domain."
} catch {
  Write-Error "Domain join failed: $($_.Exception.Message)"
  if ($_.Exception.InnerException) { Write-Error "  Inner: $($_.Exception.InnerException.Message)" }
  exit 2
}

# ── Verify AD DS configuration ────────────────────────────────────────────────
Write-Host "Verifying AD DS authentication on storage account..."
try {
  $acct = Get-AzStorageAccount -ResourceGroupName $StorageAccountResourceGroup `
                                -Name $StorageAccountName -ErrorAction Stop
  $adProps = $acct.AzureFilesIdentityBasedAuth.ActiveDirectoryProperties
  if ($adProps) {
    Write-Host "  AD Domain:   $($adProps.DomainName)"
    Write-Host "  Domain GUID: $($adProps.DomainGuid)"
    Write-Host "  Directory Service: $($acct.AzureFilesIdentityBasedAuth.DirectoryServiceOptions)"
  } else {
    Write-Warning "  AD properties not yet visible — allow a few minutes for propagation."
  }
} catch {
  Write-Warning "Could not verify: $($_.Exception.Message)"
}

# ── Retrieve storage key for mounting ─────────────────────────────────────────
Write-Host "Retrieving storage account key..."
try {
  $keys = Get-AzStorageAccountKey -ResourceGroupName $StorageAccountResourceGroup `
                                   -Name $StorageAccountName -ErrorAction Stop
  $storageKey = $keys[0].Value
} catch {
  Write-Error "Failed to retrieve storage key: $($_.Exception.Message)"; exit 3
}

# ── Mount the Azure file share ────────────────────────────────────────────────
$uncPath     = "\\$StorageAccountName.file.core.windows.net\$ShareName"
$driveLetter = $DriveLetter.TrimEnd(':') + ':'

Write-Host "Mounting '$uncPath' as drive $driveLetter ..."

# Store credentials in Windows Credential Manager for persistence
cmdkey /add:"$StorageAccountName.file.core.windows.net" `
       /user:"localhost\$StorageAccountName" `
       /pass:$storageKey | Out-Null

# Remove existing mapping if present
if (Test-Path $driveLetter) {
  net use $driveLetter /delete /y 2>$null | Out-Null
}

try {
  $netUseResult = net use $driveLetter $uncPath /persistent:yes 2>&1
  if ($LASTEXITCODE -ne 0) { throw $netUseResult }
  Write-Host "  Drive $driveLetter mounted successfully."
} catch {
  Write-Warning "net use failed (Kerberos may need time to propagate). Falling back to key-based mount..."
  try {
    New-PSDrive -Name ($DriveLetter.TrimEnd(':')) -PSProvider FileSystem `
                -Root $uncPath `
                -Credential (New-Object System.Management.Automation.PSCredential(
                    "localhost\$StorageAccountName",
                    (ConvertTo-SecureString $storageKey -AsPlainText -Force))) `
                -Persist -ErrorAction Stop | Out-Null
    Write-Host "  Drive $driveLetter mounted via storage key fallback."
  } catch {
    Write-Error "Mount failed: $($_.Exception.Message)"; exit 4
  }
}

# ── Optional: re-mount scheduled task (machine-wide, runs at startup) ─────────
if ($PersistMount) {
  Write-Host "Creating scheduled task for persistent mount at startup..."
  $taskName   = "MountAzureShare-$StorageAccountName-$ShareName"
  $mountCmd   = "net use ${driveLetter} $uncPath /persistent:yes"
  $action     = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c `"$mountCmd`""
  $trigger    = New-ScheduledTaskTrigger -AtStartup
  $principal  = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
  $settings   = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

  Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
                         -Principal $principal -Settings $settings -Force | Out-Null
  Write-Host "  Scheduled task '$taskName' registered."
}

Write-Host ""
Write-Host "Done. Summary:"
Write-Host "  Storage account : $StorageAccountName"
Write-Host "  Domain          : $DomainName"
Write-Host "  Share UNC       : $uncPath"
Write-Host "  Drive letter    : $driveLetter"
Write-Host ""
Write-Host "NOTE: Assign RBAC role 'Storage File Data SMB Share Contributor' (or higher)"
Write-Host "      to users/groups that need access via the Azure portal or:"
Write-Host "  New-AzRoleAssignment -SignInName user@domain -RoleDefinitionName 'Storage File Data SMB Share Contributor' -Scope (storage account resource ID)"
