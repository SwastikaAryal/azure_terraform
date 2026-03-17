# ============================================================
#  Azure VM Discovery Script
#  Description : Discovers all VMs across all accessible
#                Azure subscriptions and exports inventory
#  Requirements: Az PowerShell module (Install-Module Az)
#  Usage       : .\Get-AzureVMInventory.ps1
#                .\Get-AzureVMInventory.ps1 -SubscriptionId "xxxx"
#                .\Get-AzureVMInventory.ps1 -ExportPath "C:\Reports"
# ============================================================

param(
    [string]$SubscriptionId  = "",           # Leave blank to scan ALL subscriptions
    [string]$ExportPath      = ".",          # Output folder for CSV report
    [switch]$IncludePowerState = $true       # Include VM power state (requires extra API call)
)

# ── 1. CONNECT ───────────────────────────────────────────────
Write-Host "`n[1/4] Connecting to Azure..." -ForegroundColor Cyan

if (-not (Get-AzContext -ErrorAction SilentlyContinue)) {
    Connect-AzAccount -ErrorAction Stop
}

# ── 2. RESOLVE SUBSCRIPTIONS ────────────────────────────────
Write-Host "[2/4] Resolving subscriptions..." -ForegroundColor Cyan

if ($SubscriptionId) {
    $subscriptions = Get-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop
} else {
    $subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" }
}

Write-Host "      Found $($subscriptions.Count) subscription(s)." -ForegroundColor Gray

# ── 3. DISCOVER VMs ─────────────────────────────────────────
Write-Host "[3/4] Discovering VMs..." -ForegroundColor Cyan

$inventory = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($sub in $subscriptions) {

    Write-Host "      Scanning: $($sub.Name) [$($sub.Id)]" -ForegroundColor Gray
    Set-AzContext -SubscriptionId $sub.Id -WarningAction SilentlyContinue | Out-Null

    $vms = Get-AzVM -Status:$IncludePowerState

    foreach ($vm in $vms) {

        # OS disk details
        $osDisk  = $vm.StorageProfile.OsDisk
        $osDiskSizeGB = if ($osDisk.DiskSizeGB) { $osDisk.DiskSizeGB } else { "N/A" }

        # Data disk count & total size
        $dataDisks      = $vm.StorageProfile.DataDisks
        $dataDiskCount  = $dataDisks.Count
        $dataDiskSizeGB = ($dataDisks | Measure-Object -Property DiskSizeGB -Sum).Sum

        # NIC count
        $nicCount = $vm.NetworkProfile.NetworkInterfaces.Count

        # Power state (available when -Status flag used)
        $powerState = if ($vm.PowerState) { $vm.PowerState } else { "Unknown" }

        # Tags (flatten to key=value string)
        $tags = if ($vm.Tags) {
            ($vm.Tags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "; "
        } else { "" }

        $inventory.Add([PSCustomObject]@{
            SubscriptionName  = $sub.Name
            SubscriptionId    = $sub.Id
            ResourceGroup     = $vm.ResourceGroupName
            VMName            = $vm.Name
            Location          = $vm.Location
            VMSize            = $vm.HardwareProfile.VmSize
            OSType            = $vm.StorageProfile.OsDisk.OsType
            OSPublisher       = $vm.StorageProfile.ImageReference.Publisher
            OSImage           = "$($vm.StorageProfile.ImageReference.Offer) $($vm.StorageProfile.ImageReference.Sku)"
            PowerState        = $powerState
            ProvisioningState = $vm.ProvisioningState
            OSDiskSizeGB      = $osDiskSizeGB
            OSDiskType        = $osDisk.ManagedDisk.StorageAccountType
            DataDiskCount     = $dataDiskCount
            DataDiskTotalGB   = $dataDiskSizeGB
            NICCount          = $nicCount
            Tags              = $tags
        })
    }
}

Write-Host "      Total VMs discovered: $($inventory.Count)" -ForegroundColor Green

# ── 4. EXPORT REPORT ────────────────────────────────────────
Write-Host "[4/4] Exporting report..." -ForegroundColor Cyan

$timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $ExportPath "AzureVM_Inventory_$timestamp.csv"

$inventory | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8

Write-Host "`n  Report saved to: $outputFile" -ForegroundColor Green

# ── SUMMARY TABLE ────────────────────────────────────────────
Write-Host "`n── Summary by Subscription ──────────────────────────" -ForegroundColor Cyan
$inventory |
    Group-Object SubscriptionName |
    ForEach-Object {
        $running = ($_.Group | Where-Object { $_.PowerState -like "*running*" }).Count
        $stopped = ($_.Group | Where-Object { $_.PowerState -notlike "*running*" }).Count
        [PSCustomObject]@{
            Subscription = $_.Name
            TotalVMs     = $_.Count
            Running      = $running
            Stopped      = $stopped
        }
    } | Format-Table -AutoSize

Write-Host "── Summary by VM Size ───────────────────────────────" -ForegroundColor Cyan
$inventory |
    Group-Object VMSize |
    Sort-Object Count -Descending |
    Select-Object -First 10 |
    ForEach-Object {
        [PSCustomObject]@{ VMSize = $_.Name; Count = $_.Count }
    } | Format-Table -AutoSize

Write-Host "Done.`n" -ForegroundColor Green
