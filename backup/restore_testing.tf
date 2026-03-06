# -----------------------------------------------------------------
# Automation Account for scheduled restore tests
# -----------------------------------------------------------------
resource "azurerm_automation_account" "backup_restore" {
  name                = "aa-minitrue-backup-restore"
  location            = local.location
  resource_group_name = local.resource_group_name
  sku_name            = "Basic"
  tags                = local.tags

  identity {
    type = "SystemAssigned"
  }
}

# Grant the Automation Account "Backup Contributor" on the vault
resource "azurerm_role_assignment" "automation_backup_contributor" {
  scope                = azurerm_recovery_services_vault.main.id
  role_definition_name = "Backup Contributor"
  principal_id         = azurerm_automation_account.backup_restore.identity[0].principal_id
}

# Grant "Virtual Machine Contributor" so it can create restore VMs
resource "azurerm_role_assignment" "automation_vm_contributor" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_automation_account.backup_restore.identity[0].principal_id
}

data "azurerm_client_config" "current" {}

# -----------------------------------------------------------------
# Task 1 & 2: Full VM Restore Runbook (original + alternate location)
# -----------------------------------------------------------------
resource "azurerm_automation_runbook" "full_vm_restore" {
  name                    = "Invoke-FullVMRestore"
  location                = local.location
  resource_group_name     = local.resource_group_name
  automation_account_name = azurerm_automation_account.backup_restore.name
  log_verbose             = true
  log_progress            = true
  runbook_type            = "PowerShell"
  tags                    = local.tags

  content = <<-POWERSHELL
    <#
    .SYNOPSIS
        MINITRUE-9414: Full VM Restore – original or alternate location.

    .PARAMETER VaultName
        Recovery Services Vault name.

    .PARAMETER ResourceGroupName
        Resource group of the vault.

    .PARAMETER VMName
        Name of the VM to restore.

    .PARAMETER RestoreMode
        "OriginalLocation" or "AlternateLocation"

    .PARAMETER TargetResourceGroup
        (AlternateLocation only) Target resource group for restored VM.

    .PARAMETER TargetVNetName
        (AlternateLocation only) Target VNet name.

    .PARAMETER TargetSubnetName
        (AlternateLocation only) Target subnet name.
    #>
    param(
        [Parameter(Mandatory=$true)] [string]$VaultName,
        [Parameter(Mandatory=$true)] [string]$ResourceGroupName,
        [Parameter(Mandatory=$true)] [string]$VMName,
        [Parameter(Mandatory=$false)][string]$RestoreMode = "OriginalLocation",
        [Parameter(Mandatory=$false)][string]$TargetResourceGroup,
        [Parameter(Mandatory=$false)][string]$TargetVNetName,
        [Parameter(Mandatory=$false)][string]$TargetSubnetName
    )

    Import-Module Az.RecoveryServices -ErrorAction Stop
    Connect-AzAccount -Identity

    $vault = Get-AzRecoveryServicesVault -Name $VaultName -ResourceGroupName $ResourceGroupName
    Set-AzRecoveryServicesVaultContext -Vault $vault

    # Get the backup container and item
    $container = Get-AzRecoveryServicesBackupContainer `
        -ContainerType AzureVM `
        -FriendlyName $VMName

    if (-not $container) {
        Write-Error "No backup container found for VM: $VMName"
        exit 1
    }

    $backupItem = Get-AzRecoveryServicesBackupItem `
        -Container $container `
        -WorkloadType AzureVM

    # Get the latest recovery point
    $recoveryPoints = Get-AzRecoveryServicesBackupRecoveryPoint `
        -Item $backupItem | Sort-Object -Property RecoveryPointTime -Descending

    $latestRP = $recoveryPoints[0]
    Write-Output "Latest recovery point: $($latestRP.RecoveryPointTime)"

    if ($RestoreMode -eq "OriginalLocation") {
        # Task 1: Restore to original location
        Write-Output "Starting full VM restore to ORIGINAL location..."
        $restoreJob = Restore-AzRecoveryServicesBackupItem `
            -RecoveryPoint $latestRP `
            -StorageAccountName "sa$(Get-Random -Minimum 1000 -Maximum 9999)staging" `
            -StorageAccountResourceGroupName $ResourceGroupName

        Write-Output "Restore job submitted: $($restoreJob.JobId)"

    } elseif ($RestoreMode -eq "AlternateLocation") {
        # Task 2: Restore to alternate location
        Write-Output "Starting full VM restore to ALTERNATE location..."

        $targetVNet = Get-AzVirtualNetwork -Name $TargetVNetName -ResourceGroupName $TargetResourceGroup
        $targetSubnet = $targetVNet.Subnets | Where-Object { $_.Name -eq $TargetSubnetName }

        $restoreJob = Restore-AzRecoveryServicesBackupItem `
            -RecoveryPoint        $latestRP `
            -StorageAccountName   "sastaging$(Get-Random -Minimum 1000 -Maximum 9999)" `
            -StorageAccountResourceGroupName $TargetResourceGroup `
            -TargetResourceGroupName         $TargetResourceGroup `
            -VirtualNetworkId                $targetVNet.Id `
            -SubnetId                        $targetSubnet.Id

        Write-Output "Alternate location restore job submitted: $($restoreJob.JobId)"
    }

    # Wait for job completion and report
    $job = Get-AzRecoveryServicesBackupJob -JobId $restoreJob.JobId
    Write-Output "Job status: $($job.Status)"
  POWERSHELL
}

# -----------------------------------------------------------------
# Task 3: Individual Disk Restore Runbook
# -----------------------------------------------------------------
resource "azurerm_automation_runbook" "disk_restore" {
  name                    = "Invoke-DiskRestore"
  location                = local.location
  resource_group_name     = local.resource_group_name
  automation_account_name = azurerm_automation_account.backup_restore.name
  log_verbose             = true
  log_progress            = true
  runbook_type            = "PowerShell"
  tags                    = local.tags

  content = <<-POWERSHELL
    <#
    .SYNOPSIS
        MINITRUE-9414 Task 3: Individual disk restore from VM backup.
    #>
    param(
        [Parameter(Mandatory=$true)] [string]$VaultName,
        [Parameter(Mandatory=$true)] [string]$ResourceGroupName,
        [Parameter(Mandatory=$true)] [string]$VMName,
        [Parameter(Mandatory=$true)] [string]$TargetStorageAccountName,
        [Parameter(Mandatory=$true)] [string]$TargetStorageAccountRG
    )

    Import-Module Az.RecoveryServices -ErrorAction Stop
    Connect-AzAccount -Identity

    $vault = Get-AzRecoveryServicesVault -Name $VaultName -ResourceGroupName $ResourceGroupName
    Set-AzRecoveryServicesVaultContext -Vault $vault

    $container = Get-AzRecoveryServicesBackupContainer `
        -ContainerType AzureVM -FriendlyName $VMName
    $backupItem = Get-AzRecoveryServicesBackupItem `
        -Container $container -WorkloadType AzureVM
    $latestRP = (Get-AzRecoveryServicesBackupRecoveryPoint `
        -Item $backupItem | Sort-Object RecoveryPointTime -Descending)[0]

    Write-Output "Restoring disks from recovery point: $($latestRP.RecoveryPointTime)"

    # Restore disks only (not full VM) – disks land in the storage account
    $restoreJob = Restore-AzRecoveryServicesBackupItem `
        -RecoveryPoint $latestRP `
        -StorageAccountName            $TargetStorageAccountName `
        -StorageAccountResourceGroupName $TargetStorageAccountRG `
        -RestoreOnlyOSDisk              $false

    Write-Output "Disk restore job ID: $($restoreJob.JobId)"

    # Monitor job
    do {
        Start-Sleep -Seconds 30
        $job = Get-AzRecoveryServicesBackupJob -JobId $restoreJob.JobId
        Write-Output "Status: $($job.Status) | Duration: $($job.Duration)"
    } while ($job.Status -in @("InProgress","Cancelling"))

    if ($job.Status -eq "Completed") {
        Write-Output "SUCCESS: Disk restore completed."
    } else {
        Write-Error "FAILED: Disk restore ended with status $($job.Status)"
    }
  POWERSHELL
}

# -----------------------------------------------------------------
# Task 4: File-Level Recovery Runbook (ILR – Instant File Recovery)
# -----------------------------------------------------------------
resource "azurerm_automation_runbook" "file_level_recovery" {
  name                    = "Invoke-FileLevelRecovery"
  location                = local.location
  resource_group_name     = local.resource_group_name
  automation_account_name = azurerm_automation_account.backup_restore.name
  log_verbose             = true
  log_progress            = true
  runbook_type            = "PowerShell"
  tags                    = local.tags

  content = <<-POWERSHELL
    <#
    .SYNOPSIS
        MINITRUE-9414 Task 4: File-Level Recovery (ILR) from VM backup.
        Mounts the recovery point as a virtual drive on the target VM.
    #>
    param(
        [Parameter(Mandatory=$true)] [string]$VaultName,
        [Parameter(Mandatory=$true)] [string]$ResourceGroupName,
        [Parameter(Mandatory=$true)] [string]$VMName,
        [Parameter(Mandatory=$true)] [string]$ScriptOutputPath  # Local path for the ILR script
    )

    Import-Module Az.RecoveryServices -ErrorAction Stop
    Connect-AzAccount -Identity

    $vault = Get-AzRecoveryServicesVault -Name $VaultName -ResourceGroupName $ResourceGroupName
    Set-AzRecoveryServicesVaultContext -Vault $vault

    $container = Get-AzRecoveryServicesBackupContainer `
        -ContainerType AzureVM -FriendlyName $VMName
    $backupItem = Get-AzRecoveryServicesBackupItem `
        -Container $container -WorkloadType AzureVM
    $latestRP = (Get-AzRecoveryServicesBackupRecoveryPoint `
        -Item $backupItem | Sort-Object RecoveryPointTime -Descending)[0]

    Write-Output "Generating ILR script for recovery point: $($latestRP.RecoveryPointTime)"

    # Get the ILR executable script
    $ilrDetails = Get-AzRecoveryServicesBackupRPMountScript -RecoveryPoint $latestRP
    $ilrDetails.Script | Out-File -FilePath $ScriptOutputPath -Encoding utf8

    Write-Output "ILR mount script saved to: $ScriptOutputPath"
    Write-Output "Run the script on the target VM to mount the recovery point as a drive."
    Write-Output "After file recovery, revoke access with:"
    Write-Output "  Disable-AzRecoveryServicesBackupRPMountScript -RecoveryPoint <rp>"
  POWERSHELL
}

# -----------------------------------------------------------------
# Task 5: Monthly scheduled restore validation
# -----------------------------------------------------------------
resource "time_offset" "restore_schedule" {
  offset_minutes = 10
}
resource "azurerm_automation_schedule" "monthly_restore_test" {
  name                    = "sched-monthly-restore-test"
  resource_group_name     = local.resource_group_name
  automation_account_name = azurerm_automation_account.backup_restore.name
  frequency               = "Month"
  interval                = 1
  timezone                = "UTC"
  start_time              = time_offset.restore_schedule.rfc3339
  description             = "Monthly restore validation per MINITRUE-9414 runbook"
}

