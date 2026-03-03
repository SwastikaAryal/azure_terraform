param(
    [Parameter(Mandatory=$true)]
    [string]$StorageAccountName,

    [Parameter(Mandatory=$true)]
    [string]$StorageAccountResourceGroup,

    [Parameter(Mandatory=$true)]
    [string]$DomainName,

    [Parameter(Mandatory=$true)]
    [string]$DomainUser,  # e.g. "CORP\svc-storage"

    [Parameter(Mandatory=$false)]
    [SecureString]$DomainPassword,

    [Parameter(Mandatory=$false)]
    [ValidateSet("ComputerAccount","ServiceLogonAccount")]
    [string]$DomainAccountType = "ComputerAccount",

    [Parameter(Mandatory=$false)]
    [string]$OrganizationalUnitName
)

# Ensure script runs elevated
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "This script must be run as Administrator."
    exit 2
}

# Ensure Az module is available
if (-not (Get-Module -ListAvailable -Name Az.Storage)) {
    Write-Error "Az.Storage module not found. Install with 'Install-Module -Name Az.Storage -Scope CurrentUser'."
    exit 3
}

# Login to Azure if not already
Connect-AzAccount -ErrorAction Stop

# Set correct subscription if user has multiple
$context = Get-AzContext
if (-not $context) {
    Write-Error "No Azure context found. Ensure you are logged in and select a subscription using Set-AzContext."
    exit 4
}
Write-Host "Using subscription: $($context.Subscription.Name) [$($context.Subscription.Id)]"

# Prompt for password if not provided
if (-not $DomainPassword) {
    $cred = Get-Credential -UserName $DomainUser -Message "Enter password for domain account"
    $DomainPassword = $cred.Password
}

# Optional DNS flush and wait
Clear-DnsClientCache
Start-Sleep -Seconds 10

# Join Storage Account to AD
$joinParams = @{
    ResourceGroupName = $StorageAccountResourceGroup
    Name = $StorageAccountName
    DomainName = $DomainName
    DomainUser = $DomainUser
    DomainPassword = $DomainPassword
    DomainAccountType = $DomainAccountType
}

if ($OrganizationalUnitName) {
    $joinParams["OrganizationalUnitName"] = $OrganizationalUnitName
}

try {
    Write-Host "Joining Storage Account '$StorageAccountName' to domain '$DomainName'..."
    Join-AzStorageAccountForAuth @joinParams
    Write-Host "Domain join successful."
}
catch {
    Write-Error "Domain join failed: $_"
    Write-Host "Hint: Ensure the user '$DomainUser' has the correct RBAC in subscription '$($context.Subscription.Id)'."
    exit 5
}
