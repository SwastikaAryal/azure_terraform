# Join-StorageAccountToDomain.ps1
param(
  [Parameter(Mandatory=$true)][string]$StorageAccountName,
  [Parameter(Mandatory=$true)][string]$StorageAccountResourceGroup,
  [Parameter(Mandatory=$true)][string]$DomainName,
  [Parameter(Mandatory=$true)][string]$DomainUser,           # e.g. "CORP\svc-storage"
  [Parameter(Mandatory=$false)][string]$DomainPassword,
  [string]$OUPath       = "",                                # e.g. "OU=StorageAccounts,DC=corp,DC=contoso,DC=com"
  [string[]]$DnsServers = @()
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
if (-not (Get-Module -ListAvailable -Name AzFilesHybrid)) {
  Write-Error @"
AzFilesHybrid module not found.
Download from: https://github.com/Azure-Samples/azure-files-samples/releases
Extract and run .\CopyToPSPath.ps1, then re-run this script.
"@
  exit 1
}
Import-Module AzFilesHybrid -ErrorAction Stop

# ── Connect to Azure ──────────────────────────────────────────────────────────
Write-Host "Connecting to Azure..."
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
    ResourceGroupName  = $StorageAccountResourceGroup
    StorageAccountName = $StorageAccountName
    DomainAccountType  = "ComputerAccount"
  }
  if ($OUPath) {
    $joinParams["OrganizationalUnitDistinguishedName"] = $OUPath
  }

  Join-AzStorageAccountForAuth @joinParams -ErrorAction Stop
  Write-Host "  Storage account successfully joined to domain."
} catch {
  Write-Error "Domain join failed: $($_.Exception.Message)"
  if ($_.Exception.InnerException) { Write-Error "  Inner: $($_.Exception.InnerException.Message)" }
  exit 2
}

# ── Verify AD DS configuration ────────────────────────────────────────────────
Write-Host "Verifying AD DS configuration on storage account..."
try {
  $acct    = Get-AzStorageAccount -ResourceGroupName $StorageAccountResourceGroup `
                                   -Name $StorageAccountName -ErrorAction Stop
  $adProps = $acct.AzureFilesIdentityBasedAuth.ActiveDirectoryProperties
  if ($adProps) {
    Write-Host "  AD Domain   : $($adProps.DomainName)"
    Write-Host "  Domain GUID : $($adProps.DomainGuid)"
    Write-Host "  Directory   : $($acct.AzureFilesIdentityBasedAuth.DirectoryServiceOptions)"
  } else {
    Write-Warning "  AD properties not yet visible — allow a few minutes for propagation."
  }
} catch {
  Write-Warning "Could not verify: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "Done. Summary:"
Write-Host "  Storage account : $StorageAccountName"
Write-Host "  Resource group  : $StorageAccountResourceGroup"
Write-Host "  Domain          : $DomainName"
Write-Host ""
Write-Host "Next step: Assign RBAC role to AD users/groups via Azure portal or:"
Write-Host "  New-AzRoleAssignment -SignInName user@domain ``"
Write-Host "    -RoleDefinitionName 'Storage File Data SMB Share Contributor' ``"
Write-Host "    -Scope '/subscriptions/<sub-id>/resourceGroups/$StorageAccountResourceGroup/providers/Microsoft.Storage/storageAccounts/$StorageAccountName'"
