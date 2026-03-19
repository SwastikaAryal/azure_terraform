#Requires -Version 5.1
<#
.SYNOPSIS
    COMPLETE read-only collection of every SQL Server configuration, setting,
    and associated Azure/Windows VM metadata. Exports to CSV.

.DESCRIPTION
    JIRA-006 — Full export. Zero write operations.
    Covers: instance config, all sp_configure values, network/endpoints,
    databases, files, HA/DR, security, users/roles/permissions, TDE,
    Always Encrypted, certificates/keys, Resource Governor, Database Mail,
    Service Broker, Extended Events, Replication, Query Store, tempdb,
    CLR assemblies, DDL triggers, startup procs, Full-Text, backup devices,
    Row-Level Security, SQL Agent, auditing, Windows services, Azure IMDS.

.REQUIREMENTS
    Install-Module SqlServer -Scope CurrentUser
    Install-Module Az       -Scope CurrentUser   (Azure VMs only)

.EXAMPLE
    .\Collect-SQLConfig-Complete.ps1 -SqlInstances "SQL01","SQL02\INST1" -OutputDir "C:\Exports"
    .\Collect-SQLConfig-Complete.ps1 -SqlInstances "SQL01" -Credential (Get-Credential)
#>

[CmdletBinding()]
param(
    [string[]] $SqlInstances = @($env:COMPUTERNAME),
    [string]   $OutputDir    = ".\SQLConfigExport_$(Get-Date -Format 'yyyyMMdd_HHmmss')",
    [System.Management.Automation.PSCredential] $Credential
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ── helpers ───────────────────────────────────────────────────────────────────

function Write-Header ($msg) {
    Write-Host "`n=== $msg ===" -ForegroundColor Cyan
}

function Safe-Query {
    param($ServerInstance, $Query, [PSCredential]$Cred, [string]$Database = 'master')
    $p = @{
        ServerInstance = $ServerInstance
        Query          = $Query
        Database       = $Database
        ErrorAction    = 'Stop'
        QueryTimeout   = 120
    }
    if ($Cred) { $p.Credential = $Cred }
    try   { Invoke-Sqlcmd @p }
    catch { Write-Warning "  [QUERY FAILED] $ServerInstance — $_"; return $null }
}

function Export-Result ($Data, $Path, $Label) {
    if ($Data) {
        $Data | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8 -Force
        $count = ($Data | Measure-Object).Count
        Write-Host "  [OK] $Label — $count row(s) → $([System.IO.Path]::GetFileName($Path))" -ForegroundColor Green
    } else {
        Write-Warning "  [SKIP] $Label — no data returned"
    }
}

function Add-Meta ($Rows, $Instance) {
    if ($null -eq $Rows) { return $null }
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $Rows | Select-Object *, @{N='SqlInstance';E={$Instance}}, @{N='CollectedAt';E={$ts}}
}

function Get-DbList ($Instance, $Cred) {
    $rows = Safe-Query -ServerInstance $Instance -Cred $Cred -Query @"
SELECT name FROM sys.databases WITH (NOLOCK)
WHERE state_desc = 'ONLINE' AND name <> 'tempdb'
ORDER BY name;
"@
    if ($rows) { $rows.name } else { @() }
}

# ── pre-flight ────────────────────────────────────────────────────────────────

if (-not (Get-Module -ListAvailable -Name SqlServer)) {
    Write-Error "SqlServer module not found.  Run: Install-Module SqlServer -Scope CurrentUser"
    exit 1
}
Import-Module SqlServer -ErrorAction Stop
$null = New-Item -ItemType Directory -Path $OutputDir -Force
Write-Host "Output → $(Resolve-Path $OutputDir)" -ForegroundColor Yellow
Write-Host "Instances: $($SqlInstances -join ', ')" -ForegroundColor Yellow

# =============================================================================
# 01  WINDOWS VM HOST INFORMATION
# =============================================================================
Write-Header "01 — Windows VM Host Information"
$s01 = foreach ($inst in $SqlInstances) {
    $h = $inst.Split('\')[0]
    try {
        $os   = Get-CimInstance -ComputerName $h Win32_OperatingSystem            -EA Stop
        $cpu  = Get-CimInstance -ComputerName $h Win32_Processor                  -EA Stop | Select-Object -First 1
        $mem  = Get-CimInstance -ComputerName $h Win32_PhysicalMemory             -EA Stop
        $cs   = Get-CimInstance -ComputerName $h Win32_ComputerSystem             -EA Stop
        $nic  = Get-CimInstance -ComputerName $h Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" -EA Stop
        $disk = Get-CimInstance -ComputerName $h Win32_LogicalDisk -Filter "DriveType=3" -EA Stop
        $pf   = Get-CimInstance -ComputerName $h Win32_PageFileSetting            -EA SilentlyContinue
        $pp   = Get-CimInstance -ComputerName $h Win32_PowerPlan -NS root\cimv2\power -EA SilentlyContinue | Where-Object IsActive
        $bios = Get-CimInstance -ComputerName $h Win32_BIOS                       -EA SilentlyContinue
        $ram  = [math]::Round(($mem | Measure-Object Capacity -Sum).Sum / 1GB, 2)
        $diskStr = ($disk | ForEach-Object {
            "$($_.DeviceID) total:$([math]::Round($_.Size/1GB,1))GB free:$([math]::Round($_.FreeSpace/1GB,1))GB fs:$($_.FileSystem)"
        }) -join ' | '
        $nicStr = ($nic | ForEach-Object {
            "$($_.Description) IP:$(($_.IPAddress -join ',')) MAC:$($_.MACAddress)"
        }) -join ' | '
        [PSCustomObject]@{
            SqlInstance       = $inst
            HostName          = $h
            OSCaption         = $os.Caption
            OSVersion         = $os.Version
            OSBuildNumber     = $os.BuildNumber
            OSArchitecture    = $os.OSArchitecture
            OSInstallDate     = $os.InstallDate
            OSLastBoot        = $os.LastBootUpTime
            Domain            = $cs.Domain
            DomainRole        = $cs.DomainRole   # 0=Standalone,1=Member,4=DC
            Manufacturer      = $cs.Manufacturer
            Model             = $cs.Model
            SystemType        = $cs.SystemType
            BIOSVersion       = $bios.SMBIOSBIOSVersion
            BIOSReleaseDate   = $bios.ReleaseDate
            CPUName           = $cpu.Name
            CPUSockets        = ($mem | Measure-Object).Count   # proxy
            CPUCores          = $cpu.NumberOfCores
            CPULogical        = $cpu.NumberOfLogicalProcessors
            CPUMaxClockMHz    = $cpu.MaxClockSpeed
            TotalRAM_GB       = $ram
            NUMANodes         = $cpu.NumberOfCores   # best effort
            PagefileConfig    = if ($pf)  { ($pf  | ForEach-Object { "$($_.Name) init:$($_.InitialSize)MB max:$($_.MaximumSize)MB" }) -join ' | ' } else { 'System Managed' }
            PowerPlan         = if ($pp)  { $pp.ElementName } else { 'N/A' }
            NICDetails        = $nicStr
            DiskLayout        = $diskStr
            CollectedAt       = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        }
    } catch { Write-Warning "  VM info failed for $h : $_" }
}
Export-Result $s01 "$OutputDir\01_VM_Host_Info.csv" "VM Host Info"


# =============================================================================
# 02  WINDOWS SQL SERVICES STATUS
# =============================================================================
Write-Header "02 — Windows SQL Services"
$s02 = foreach ($inst in $SqlInstances) {
    $h = $inst.Split('\')[0]
    try {
        $services = Get-CimInstance -ComputerName $h Win32_Service -EA Stop |
            Where-Object { $_.Name -match 'MSSQL|SQLAgent|SQLBrowser|ReportServer|MsDts|MSOlap|SQLWriter|SQLTELEMETRY' }
        $services | ForEach-Object {
            [PSCustomObject]@{
                SqlInstance    = $inst
                HostName       = $h
                ServiceName    = $_.Name
                DisplayName    = $_.DisplayName
                State          = $_.State
                StartMode      = $_.StartMode
                ServiceAccount = $_.StartName
                PathName       = $_.PathName
                ProcessID      = $_.ProcessId
                CollectedAt    = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            }
        }
    } catch { Write-Warning "  Services failed for $h : $_" }
}
Export-Result $s02 "$OutputDir\02_Windows_SQL_Services.csv" "Windows SQL Services"


# =============================================================================
# 03  AZURE VM IMDS METADATA
# =============================================================================
Write-Header "03 — Azure VM IMDS Metadata"
$s03 = foreach ($inst in $SqlInstances) {
    $h = $inst.Split('\')[0]
    try {
        $m = Invoke-RestMethod -Uri 'http://169.254.169.254/metadata/instance?api-version=2021-02-01' `
            -Headers @{Metadata='true'} -TimeoutSec 4 -EA Stop
        [PSCustomObject]@{
            SqlInstance          = $inst
            HostName             = $h
            VMName               = $m.compute.name
            VMSize               = $m.compute.vmSize
            Region               = $m.compute.location
            Zone                 = $m.compute.zone
            ResourceGroup        = $m.compute.resourceGroupName
            SubscriptionId       = $m.compute.subscriptionId
            VMId                 = $m.compute.vmId
            OSType               = $m.compute.osType
            ImagePublisher       = $m.compute.storageProfile.imageReference.publisher
            ImageOffer           = $m.compute.storageProfile.imageReference.offer
            ImageSKU             = $m.compute.storageProfile.imageReference.sku
            ImageVersion         = $m.compute.storageProfile.imageReference.version
            OSDiskStorageType    = $m.compute.storageProfile.osDisk.managedDisk.storageAccountType
            OSDiskSizeGB         = $m.compute.storageProfile.osDisk.diskSizeGB
            DataDisks            = ($m.compute.storageProfile.dataDisks | ForEach-Object {
                                    "$($_.name):$($_.diskSizeGB)GB:$($_.managedDisk.storageAccountType):lun$($_.lun)" }) -join ' | '
            AcceleratedNetworking = $m.network.interface[0].macAddress
            PrivateIP            = $m.network.interface[0].ipv4.ipAddress[0].privateIpAddress
            PublicIP             = $m.network.interface[0].ipv4.ipAddress[0].publicIpAddress
            Tags                 = ($m.compute.tags | ConvertTo-Json -Compress)
            CollectedAt          = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        }
    } catch { Write-Warning "  $h — not Azure or IMDS unreachable" }
}
Export-Result $s03 "$OutputDir\03_Azure_VM_Metadata.csv" "Azure VM IMDS"


# =============================================================================
# 04  SQL INSTANCE-LEVEL CONFIGURATION
# =============================================================================
Write-Header "04 — SQL Instance Config"
$s04 = foreach ($inst in $SqlInstances) {
    $q = @"
SELECT
    SERVERPROPERTY('ServerName')                   AS InstanceName,
    SERVERPROPERTY('ComputerNamePhysicalNetBIOS')  AS PhysicalHost,
    SERVERPROPERTY('ProductVersion')               AS ProductVersion,
    SERVERPROPERTY('ProductLevel')                 AS ProductLevel,
    SERVERPROPERTY('ProductUpdateLevel')           AS UpdateLevel,
    SERVERPROPERTY('ProductUpdateReference')       AS UpdateRef,
    SERVERPROPERTY('Edition')                      AS Edition,
    SERVERPROPERTY('EngineEdition')                AS EngineEdition,
    SERVERPROPERTY('BuildClrVersion')              AS CLRVersion,
    SERVERPROPERTY('Collation')                    AS ServerCollation,
    SERVERPROPERTY('IsIntegratedSecurityOnly')     AS WindowsAuthOnly,
    SERVERPROPERTY('IsClustered')                  AS IsClustered,
    SERVERPROPERTY('IsHadrEnabled')                AS IsAGEnabled,
    SERVERPROPERTY('IsXTPSupported')               AS InMemoryOLTPSupported,
    SERVERPROPERTY('IsPolyBaseInstalled')          AS PolyBaseInstalled,
    SERVERPROPERTY('IsFullTextInstalled')          AS FullTextInstalled,
    SERVERPROPERTY('IsAdvancedAnalyticsInstalled') AS AdvancedAnalyticsInstalled,
    SERVERPROPERTY('FilestreamEffectiveLevel')     AS FilestreamLevel,
    SERVERPROPERTY('FilestreamShareName')          AS FilestreamShare,
    SERVERPROPERTY('InstanceDefaultDataPath')      AS DefaultDataPath,
    SERVERPROPERTY('InstanceDefaultLogPath')       AS DefaultLogPath,
    SERVERPROPERTY('InstanceDefaultBackupPath')    AS DefaultBackupPath,
    @@SERVICENAME                                  AS ServiceName,
    @@VERSION                                      AS FullVersion,
    @@LANGUAGE                                     AS Language;
"@
    $row = Safe-Query -ServerInstance $inst -Cred $Credential -Query $q
    if ($row) {
        $svc = Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
EXEC xp_instance_regread N'HKEY_LOCAL_MACHINE',
    N'SYSTEM\CurrentControlSet\Services\MSSQLSERVER', N'ObjectName';
"@
        $agt = Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
EXEC xp_instance_regread N'HKEY_LOCAL_MACHINE',
    N'SYSTEM\CurrentControlSet\Services\SQLSERVERAGENT', N'ObjectName';
"@
        $errlog = Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
EXEC xp_instance_regread N'HKEY_LOCAL_MACHINE',
    N'SOFTWARE\Microsoft\MSSQLServer\MSSQLServer', N'ErrorLogPath';
"@
        $row | Select-Object *,
            @{N='SqlInstance'      ; E={ $inst }},
            @{N='SqlServiceAccount'; E={ if ($svc) { $svc.Data } else { 'N/A' } }},
            @{N='AgentAccount'     ; E={ if ($agt) { $agt.Data } else { 'N/A' } }},
            @{N='ErrorLogPath'     ; E={ if ($errlog) { $errlog.Data } else { 'N/A' } }},
            @{N='CollectedAt'      ; E={ Get-Date -Format 'yyyy-MM-dd HH:mm:ss' }}
    }
}
Export-Result $s04 "$OutputDir\04_Instance_Config.csv" "Instance Config"


# =============================================================================
# 05  ALL SP_CONFIGURE VALUES (all 70+ options)
# =============================================================================
Write-Header "05 — sp_configure (all options)"
$s05 = foreach ($inst in $SqlInstances) {
    Add-Meta (Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
SELECT name, minimum, maximum, value_configured AS ConfiguredValue,
       value_in_use AS RunningValue, description,
       is_dynamic, is_advanced
FROM sys.configurations WITH (NOLOCK)
ORDER BY name;
"@) $inst
}
Export-Result $s05 "$OutputDir\05_sp_configure_All.csv" "sp_configure"


# =============================================================================
# 06  NETWORK & ENDPOINTS
# =============================================================================
Write-Header "06 — Network Config & Endpoints"

# TCP Port from registry
$s06a = foreach ($inst in $SqlInstances) {
    $instKey = if ($inst -like '*\*') { $inst.Split('\')[1] } else { 'MSSQLSERVER' }
    $tcpPort = Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
EXEC xp_instance_regread N'HKEY_LOCAL_MACHINE',
    N'SOFTWARE\Microsoft\Microsoft SQL Server\MSSQLServer\SuperSocketNetLib\Tcp\IpAll',
    N'TcpPort';
"@
    $tcpDyn = Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
EXEC xp_instance_regread N'HKEY_LOCAL_MACHINE',
    N'SOFTWARE\Microsoft\Microsoft SQL Server\MSSQLServer\SuperSocketNetLib\Tcp\IpAll',
    N'TcpDynamicPorts';
"@
    $pipes = Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
EXEC xp_instance_regread N'HKEY_LOCAL_MACHINE',
    N'SOFTWARE\Microsoft\Microsoft SQL Server\MSSQLServer\SuperSocketNetLib\Np',
    N'PipeName';
"@
    [PSCustomObject]@{
        SqlInstance      = $inst
        StaticTCPPort    = if ($tcpPort) { $tcpPort.Data } else { 'Dynamic' }
        DynamicTCPPort   = if ($tcpDyn)  { $tcpDyn.Data  } else { 'N/A' }
        NamedPipePath    = if ($pipes)   { $pipes.Data   } else { 'N/A' }
        CollectedAt      = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    }
}
Export-Result $s06a "$OutputDir\06a_Network_TCP_Config.csv" "Network TCP Config"

# sys.endpoints
$s06b = foreach ($inst in $SqlInstances) {
    Add-Meta (Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
SELECT e.name, e.endpoint_id, e.protocol_desc, e.type_desc, e.state_desc,
       e.is_admin_endpoint, e.is_dynamic_port,
       te.port         AS tcp_port,
       he.site         AS http_site,
       he.url_path     AS http_path,
       he.is_session_timeout_enabled,
       he.session_timeout
FROM sys.endpoints e WITH (NOLOCK)
LEFT JOIN sys.tcp_endpoints  te ON e.endpoint_id = te.endpoint_id
LEFT JOIN sys.http_endpoints he ON e.endpoint_id = he.endpoint_id
ORDER BY e.type_desc, e.name;
"@) $inst
}
Export-Result $s06b "$OutputDir\06b_Endpoints.csv" "Endpoints"


# =============================================================================
# 07  SERVER-LEVEL PERMISSIONS
# =============================================================================
Write-Header "07 — Server-Level Permissions"
$s07 = foreach ($inst in $SqlInstances) {
    Add-Meta (Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
SELECT
    perm.class_desc                 AS PermClass,
    perm.permission_name            AS Permission,
    perm.state_desc                 AS PermState,
    prin.name                       AS Grantee,
    prin.type_desc                  AS GranteeType,
    gran.name                       AS Grantor
FROM sys.server_permissions perm WITH (NOLOCK)
JOIN sys.server_principals prin ON perm.grantee_principal_id = prin.principal_id
JOIN sys.server_principals gran ON perm.grantor_principal_id = gran.principal_id
ORDER BY prin.name, perm.permission_name;
"@) $inst
}
Export-Result $s07 "$OutputDir\07_Server_Permissions.csv" "Server Permissions"


# =============================================================================
# 08  SQL LOGINS & SERVER ROLES
# =============================================================================
Write-Header "08 — SQL Logins & Server Roles"
$s08 = foreach ($inst in $SqlInstances) {
    Add-Meta (Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
SELECT
    sp.name                         AS LoginName,
    sp.type_desc                    AS LoginType,
    sp.is_disabled                  AS IsDisabled,
    sp.is_policy_checked            AS PwdPolicyChecked,
    sp.is_expiration_checked        AS PwdExpirationChecked,
    sp.create_date                  AS CreateDate,
    sp.modify_date                  AS ModifyDate,
    sp.default_database_name        AS DefaultDatabase,
    sp.default_language_name        AS DefaultLanguage,
    ISNULL(sl.password_hash,'N/A')  AS PasswordHashPresent,   -- hash only, never plain text
    STUFF((SELECT ', '+r.name FROM sys.server_role_members m
           JOIN sys.server_principals r ON m.role_principal_id=r.principal_id
           WHERE m.member_principal_id=sp.principal_id FOR XML PATH('')),1,2,'') AS ServerRoles
FROM sys.server_principals sp WITH (NOLOCK)
LEFT JOIN sys.sql_logins sl ON sp.principal_id = sl.principal_id
WHERE sp.type IN ('S','U','G','E','X')
  AND sp.name NOT LIKE '##%'
ORDER BY sp.type_desc, sp.name;
"@) $inst
}
Export-Result $s08 "$OutputDir\08_Logins_ServerRoles.csv" "Logins & Server Roles"


# =============================================================================
# 09  DATABASE CONFIGURATION
# =============================================================================
Write-Header "09 — Database Configuration"
$s09 = foreach ($inst in $SqlInstances) {
    Add-Meta (Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
SELECT
    d.name, d.database_id, d.state_desc, d.user_access_desc,
    SUSER_SNAME(d.owner_sid)            AS Owner,
    d.recovery_model_desc, d.compatibility_level, d.collation_name,
    d.is_read_only, d.is_auto_close_on, d.is_auto_shrink_on,
    d.is_auto_update_stats_on, d.is_auto_update_stats_async_on,
    d.is_auto_create_stats_on, d.is_auto_create_incremental_stats_on,
    d.is_encrypted                      AS TDEEnabled,
    d.is_query_store_on                 AS QueryStoreOn,
    d.snapshot_isolation_state_desc     AS SnapshotIsolation,
    d.is_read_committed_snapshot_on     AS RCSI,
    d.page_verify_option_desc           AS PageVerify,
    d.log_reuse_wait_desc               AS LogReuseWait,
    d.is_fulltext_enabled               AS FullTextEnabled,
    d.is_trustworthy_on                 AS IsTrustworthy,
    d.is_db_chaining_on                 AS DBChaining,
    d.is_parameterization_forced        AS ForcedParameterization,
    d.is_in_standby                     AS IsStandby,
    d.is_cleanly_shutdown               AS CleanlyShutdown,
    d.target_recovery_time_in_seconds   AS TargetRecoveryTimeSec,
    d.delayed_durability_desc           AS DelayedDurability,
    d.is_memory_optimized_elevate_to_snapshot_on AS InMemoryElevateToSnapshot,
    d.create_date,
    -- File summary
    (SELECT CAST(SUM(CASE WHEN type=0 THEN size END)*8.0/1024 AS decimal(18,2))
     FROM sys.master_files WHERE database_id=d.database_id) AS DataSize_MB,
    (SELECT CAST(SUM(CASE WHEN type=1 THEN size END)*8.0/1024 AS decimal(18,2))
     FROM sys.master_files WHERE database_id=d.database_id) AS LogSize_MB,
    (SELECT COUNT(*) FROM sys.master_files WHERE database_id=d.database_id AND type=0) AS DataFileCount,
    (SELECT COUNT(*) FROM sys.master_files WHERE database_id=d.database_id AND type=1) AS LogFileCount,
    -- Backup history
    (SELECT TOP 1 CONVERT(varchar,backup_finish_date,120) FROM msdb..backupset
     WHERE database_name=d.name AND type='D' ORDER BY backup_finish_date DESC) AS LastFullBackup,
    (SELECT TOP 1 CONVERT(varchar,backup_finish_date,120) FROM msdb..backupset
     WHERE database_name=d.name AND type='I' ORDER BY backup_finish_date DESC) AS LastDiffBackup,
    (SELECT TOP 1 CONVERT(varchar,backup_finish_date,120) FROM msdb..backupset
     WHERE database_name=d.name AND type='L' ORDER BY backup_finish_date DESC) AS LastLogBackup
FROM sys.databases d WITH (NOLOCK)
ORDER BY d.name;
"@) $inst
}
Export-Result $s09 "$OutputDir\09_Database_Config.csv" "Database Config"


# =============================================================================
# 10  DATABASE FILES (DATA & LOG)
# =============================================================================
Write-Header "10 — Database Files"
$s10 = foreach ($inst in $SqlInstances) {
    Add-Meta (Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
SELECT
    DB_NAME(mf.database_id)                         AS DatabaseName,
    mf.file_id, mf.name AS LogicalName, mf.physical_name AS PhysicalPath,
    mf.type_desc AS FileType, mf.state_desc AS FileState,
    mf.data_space_id                                AS FileGroupID,
    fg.name                                         AS FileGroupName,
    fg.type_desc                                    AS FileGroupType,
    fg.is_default                                   AS IsDefaultFG,
    CAST(mf.size*8.0/1024 AS decimal(18,2))         AS CurrentSize_MB,
    CASE WHEN mf.max_size=-1 THEN 'Unlimited'
         ELSE CAST(mf.max_size*8.0/1024 AS varchar) END AS MaxSize_MB,
    CASE WHEN mf.is_percent_growth=1
         THEN CAST(mf.growth AS varchar)+'%'
         ELSE CAST(mf.growth*8.0/1024 AS varchar)+' MB' END AS AutoGrowth,
    mf.is_sparse, mf.is_read_only, mf.is_media_read_only
FROM sys.master_files mf WITH (NOLOCK)
LEFT JOIN sys.filegroups fg ON mf.data_space_id = fg.data_space_id
    AND mf.database_id = DB_ID(DB_NAME(mf.database_id))
ORDER BY DB_NAME(mf.database_id), mf.type, mf.file_id;
"@) $inst
}
Export-Result $s10 "$OutputDir\10_Database_Files.csv" "Database Files"


# =============================================================================
# 11  TEMPDB CONFIGURATION
# =============================================================================
Write-Header "11 — tempdb Configuration"
$s11 = foreach ($inst in $SqlInstances) {
    Add-Meta (Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
SELECT
    mf.file_id, mf.name AS LogicalName, mf.physical_name AS PhysicalPath,
    mf.type_desc AS FileType,
    CAST(mf.size*8.0/1024 AS decimal(18,2))       AS CurrentSize_MB,
    CASE WHEN mf.max_size=-1 THEN 'Unlimited'
         ELSE CAST(mf.max_size*8.0/1024 AS varchar) END AS MaxSize_MB,
    CASE WHEN mf.is_percent_growth=1
         THEN CAST(mf.growth AS varchar)+'%'
         ELSE CAST(mf.growth*8.0/1024 AS varchar)+' MB' END AS AutoGrowth,
    (SELECT value_in_use FROM sys.configurations WITH (NOLOCK)
     WHERE name='tempdb metadata memory-optimized')  AS InMemoryMetadata,
    (SELECT COUNT(*) FROM sys.master_files WITH (NOLOCK)
     WHERE database_id=2 AND type=0)                AS TotalDataFiles
FROM sys.master_files mf WITH (NOLOCK)
WHERE mf.database_id = 2
ORDER BY mf.type, mf.file_id;
"@) $inst
}
Export-Result $s11 "$OutputDir\11_tempdb_Config.csv" "tempdb Config"


# =============================================================================
# 12  DATABASE USERS & ROLES (all online DBs)
# =============================================================================
Write-Header "12 — Database Users & Roles"
$s12 = foreach ($inst in $SqlInstances) {
    foreach ($db in (Get-DbList $inst $Credential)) {
        Add-Meta (Safe-Query -ServerInstance $inst -Cred $Credential -Database $db -Query @"
SELECT
    DB_NAME()                           AS DatabaseName,
    dp.name AS UserName, dp.type_desc AS UserType,
    dp.authentication_type_desc        AS AuthType,
    dp.create_date, dp.modify_date,
    ISNULL(sl.name,'No Login')         AS MappedLogin,
    dp.default_schema_name,
    dp.is_fixed_role,
    STUFF((SELECT ', '+rp.name FROM sys.database_role_members drm
           JOIN sys.database_principals rp ON drm.role_principal_id=rp.principal_id
           WHERE drm.member_principal_id=dp.principal_id FOR XML PATH('')),1,2,'') AS DatabaseRoles
FROM sys.database_principals dp WITH (NOLOCK)
LEFT JOIN sys.server_principals sl ON dp.sid=sl.sid
WHERE dp.type NOT IN ('R')
  AND dp.name NOT IN ('dbo','guest','sys','INFORMATION_SCHEMA')
ORDER BY dp.name;
"@) $inst
    }
}
Export-Result $s12 "$OutputDir\12_DB_Users_Roles.csv" "DB Users & Roles"


# =============================================================================
# 13  DATABASE-LEVEL PERMISSIONS (all online DBs)
# =============================================================================
Write-Header "13 — Database-Level Permissions"
$s13 = foreach ($inst in $SqlInstances) {
    foreach ($db in (Get-DbList $inst $Credential)) {
        Add-Meta (Safe-Query -ServerInstance $inst -Cred $Credential -Database $db -Query @"
SELECT
    DB_NAME()                       AS DatabaseName,
    perm.class_desc                 AS PermClass,
    perm.permission_name            AS Permission,
    perm.state_desc                 AS PermState,
    usr.name                        AS Grantee,
    usr.type_desc                   AS GranteeType,
    gran.name                       AS Grantor,
    OBJECT_NAME(perm.major_id)      AS ObjectName,
    perm.minor_id                   AS ColumnID
FROM sys.database_permissions perm WITH (NOLOCK)
JOIN sys.database_principals usr  ON perm.grantee_principal_id = usr.principal_id
JOIN sys.database_principals gran ON perm.grantor_principal_id = gran.principal_id
WHERE perm.class_desc <> 'DATABASE'
  OR perm.permission_name NOT IN ('CONNECT')
ORDER BY usr.name, perm.permission_name;
"@) $inst
    }
}
Export-Result $s13 "$OutputDir\13_DB_Permissions.csv" "DB Permissions"


# =============================================================================
# 14  HA / DR — AVAILABILITY GROUPS
# =============================================================================
Write-Header "14 — HA/DR Availability Groups"
$s14 = foreach ($inst in $SqlInstances) {
    Add-Meta (Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
SELECT
    ag.name AS AGName, ag.automated_backup_preference_desc,
    ag.failure_condition_level, ag.health_check_timeout,
    ag.db_failover, ag.is_distributed,
    agl.dns_name AS ListenerDNS, agl.port AS ListenerPort,
    agl.ip_configuration_string_from_cluster,
    ar.replica_server_name, ar.endpoint_url,
    ar.availability_mode_desc, ar.failover_mode_desc,
    ar.seeding_mode_desc, ar.secondary_role_allow_connections_desc,
    ar.primary_role_allow_connections_desc,
    ar.session_timeout, ar.requested_state_desc,
    ars.role_desc AS CurrentRole, ars.operational_state_desc,
    ars.connected_state_desc, ars.synchronization_health_desc,
    adb.database_name, adb.synchronization_state_desc,
    adb.synchronization_health_desc AS DBSyncHealth,
    adb.log_send_queue_size AS LogSendQueue_KB,
    adb.log_send_rate AS LogSendRate_KBs,
    adb.redo_queue_size AS RedoQueue_KB,
    adb.redo_rate AS RedoRate_KBs,
    adb.filestream_send_rate, adb.end_of_log_lsn,
    adb.last_commit_lsn, adb.last_commit_time
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar          ON ag.group_id=ar.group_id
JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id=ars.replica_id
LEFT JOIN sys.availability_group_listeners agl   ON ag.group_id=agl.group_id
LEFT JOIN sys.dm_hadr_database_replica_states adb ON ar.replica_id=adb.replica_id
ORDER BY ag.name, ar.replica_server_name;
"@) $inst
}
Export-Result $s14 "$OutputDir\14_HA_DR_AG.csv" "HA/DR Availability Groups"


# =============================================================================
# 15  TDE — TRANSPARENT DATA ENCRYPTION
# =============================================================================
Write-Header "15 — TDE Status"
$s15 = foreach ($inst in $SqlInstances) {
    Add-Meta (Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
SELECT
    DB_NAME(dek.database_id)        AS DatabaseName,
    dek.encryption_state_desc, dek.key_algorithm, dek.key_length,
    dek.encryptor_type, dek.percent_complete AS EncryptionPct,
    dek.create_date, dek.regenerate_date, dek.set_date, dek.opened_date,
    c.name AS CertificateName, c.expiry_date AS CertExpiry,
    c.pvt_key_encryption_type_desc  AS KeyEncryptionType,
    c.thumbprint AS CertThumbprint
FROM sys.dm_database_encryption_keys dek WITH (NOLOCK)
LEFT JOIN sys.certificates c ON dek.encryptor_thumbprint=c.thumbprint
ORDER BY DB_NAME(dek.database_id);
"@) $inst
}
Export-Result $s15 "$OutputDir\15_TDE_Status.csv" "TDE Status"


# =============================================================================
# 16  CERTIFICATES & ASYMMETRIC KEYS (all DBs)
# =============================================================================
Write-Header "16 — Certificates & Keys"
$s16 = foreach ($inst in $SqlInstances) {
    # Server-level
    $srv = Add-Meta (Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
SELECT 'master' AS DatabaseName, 'Certificate' AS ObjectType,
    name, certificate_id AS ObjectID, subject, start_date, expiry_date,
    pvt_key_encryption_type_desc, thumbprint, issuer_name,
    NULL AS key_algorithm, NULL AS key_length
FROM sys.certificates WITH (NOLOCK)
UNION ALL
SELECT 'master','AsymmetricKey',
    name, asymmetric_key_id, NULL, create_date, NULL,
    pvt_key_encryption_type_desc, thumbprint, NULL,
    algorithm_desc, key_length
FROM sys.asymmetric_keys WITH (NOLOCK);
"@) $inst

    # Per-DB
    $dbs = foreach ($db in (Get-DbList $inst $Credential)) {
        Add-Meta (Safe-Query -ServerInstance $inst -Cred $Credential -Database $db -Query @"
SELECT DB_NAME() AS DatabaseName, 'Certificate' AS ObjectType,
    name, certificate_id, subject, start_date, expiry_date,
    pvt_key_encryption_type_desc, thumbprint, issuer_name,
    NULL AS key_algorithm, NULL AS key_length
FROM sys.certificates WITH (NOLOCK)
UNION ALL
SELECT DB_NAME(),'AsymmetricKey',
    name, asymmetric_key_id, NULL, create_date, NULL,
    pvt_key_encryption_type_desc, thumbprint, NULL,
    algorithm_desc, key_length
FROM sys.asymmetric_keys WITH (NOLOCK);
"@) $inst
    }
    $srv; $dbs
}
Export-Result $s16 "$OutputDir\16_Certificates_Keys.csv" "Certificates & Keys"


# =============================================================================
# 17  ALWAYS ENCRYPTED — COLUMN MASTER & ENCRYPTION KEYS (all DBs)
# =============================================================================
Write-Header "17 — Always Encrypted Keys"
$s17 = foreach ($inst in $SqlInstances) {
    foreach ($db in (Get-DbList $inst $Credential)) {
        Add-Meta (Safe-Query -ServerInstance $inst -Cred $Credential -Database $db -Query @"
SELECT
    DB_NAME()                       AS DatabaseName,
    'ColumnMasterKey'               AS KeyType,
    cmk.name, cmk.column_master_key_id AS KeyID,
    cmk.key_store_provider_name,
    cmk.key_path,
    cmk.allow_enclave_computations,
    NULL AS encrypted_value, NULL AS column_master_key_id_ref
FROM sys.column_master_keys cmk WITH (NOLOCK)
UNION ALL
SELECT
    DB_NAME(),'ColumnEncryptionKey',
    cek.name, cek.column_encryption_key_id,
    NULL, NULL, NULL,
    CONVERT(varchar(max), cekv.encrypted_value, 2),
    cekv.column_master_key_id
FROM sys.column_encryption_keys cek WITH (NOLOCK)
JOIN sys.column_encryption_key_values cekv ON cek.column_encryption_key_id=cekv.column_encryption_key_id;
"@) $inst
    }
}
Export-Result $s17 "$OutputDir\17_Always_Encrypted_Keys.csv" "Always Encrypted"


# =============================================================================
# 18  SYMMETRIC KEYS (all DBs)
# =============================================================================
Write-Header "18 — Symmetric Keys"
$s18 = foreach ($inst in $SqlInstances) {
    foreach ($db in (Get-DbList $inst $Credential)) {
        Add-Meta (Safe-Query -ServerInstance $inst -Cred $Credential -Database $db -Query @"
SELECT DB_NAME() AS DatabaseName,
    name, symmetric_key_id, key_algorithm, key_length,
    create_date, modify_date, key_guid,
    pvt_key_encryption_type_desc
FROM sys.symmetric_keys WITH (NOLOCK)
WHERE name <> '##MS_DatabaseMasterKey##'
ORDER BY name;
"@) $inst
    }
}
Export-Result $s18 "$OutputDir\18_Symmetric_Keys.csv" "Symmetric Keys"


# =============================================================================
# 19  RESOURCE GOVERNOR
# =============================================================================
Write-Header "19 — Resource Governor"
$s19a = foreach ($inst in $SqlInstances) {
    Add-Meta (Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
SELECT
    rg.is_enabled, rg.classifier_function_id,
    OBJECT_NAME(rg.classifier_function_id) AS ClassifierFunction,
    rg.max_outstanding_io_per_volume
FROM sys.resource_governor_configuration rg WITH (NOLOCK);
"@) $inst
}
Export-Result $s19a "$OutputDir\19a_ResourceGovernor_Config.csv" "Resource Governor Config"

$s19b = foreach ($inst in $SqlInstances) {
    Add-Meta (Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
SELECT
    p.name AS PoolName, p.pool_id, p.min_cpu_percent, p.max_cpu_percent,
    p.min_memory_percent, p.max_memory_percent,
    p.cap_cpu_percent, p.min_iops_per_volume, p.max_iops_per_volume,
    wg.name AS WorkloadGroup, wg.group_id,
    wg.importance, wg.request_max_memory_grant_percent,
    wg.request_max_cpu_time_sec, wg.request_memory_grant_timeout_sec,
    wg.max_dop, wg.group_max_requests
FROM sys.resource_governor_resource_pools p WITH (NOLOCK)
JOIN sys.resource_governor_workload_groups wg ON p.pool_id=wg.pool_id
ORDER BY p.name, wg.name;
"@) $inst
}
Export-Result $s19b "$OutputDir\19b_ResourceGovernor_Pools.csv" "Resource Governor Pools"


# =============================================================================
# 20  DATABASE MAIL
# =============================================================================
Write-Header "20 — Database Mail"
$s20 = foreach ($inst in $SqlInstances) {
    Add-Meta (Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
SELECT
    p.name AS ProfileName, p.description AS ProfileDesc,
    p.is_default AS IsDefaultProfile,
    a.name AS AccountName, a.description AS AccountDesc,
    a.email_address AS FromAddress, a.display_name,
    a.replyto_address, a.mailserver_name, a.mailserver_type,
    a.port, a.use_default_credentials, a.enable_ssl,
    pa.sequence_number, pa.is_default AS IsDefaultAccount
FROM msdb.dbo.sysmail_profile p WITH (NOLOCK)
LEFT JOIN msdb.dbo.sysmail_profileaccount pa ON p.profile_id=pa.profile_id
LEFT JOIN msdb.dbo.sysmail_account a         ON pa.account_id=a.account_id
ORDER BY p.name, pa.sequence_number;
"@) $inst
}
Export-Result $s20 "$OutputDir\20_Database_Mail.csv" "Database Mail"


# =============================================================================
# 21  SERVICE BROKER (all DBs)
# =============================================================================
Write-Header "21 — Service Broker"
$s21 = foreach ($inst in $SqlInstances) {
    foreach ($db in (Get-DbList $inst $Credential)) {
        Add-Meta (Safe-Query -ServerInstance $inst -Cred $Credential -Database $db -Query @"
SELECT DB_NAME() AS DatabaseName, 'Queue' AS ObjectType,
    q.name, q.is_enqueue_enabled, q.is_receive_enabled, q.is_retention_on,
    q.activation_procedure, q.execute_as_principal_id,
    q.max_readers, s.name AS RelatedService
FROM sys.service_queues q WITH (NOLOCK)
LEFT JOIN sys.services s ON q.object_id=s.service_queue_id
UNION ALL
SELECT DB_NAME(),'Route',r.name,
    r.is_local AS is_enqueue_enabled,
    NULL,NULL,NULL,NULL,NULL,r.address
FROM sys.routes r WITH (NOLOCK)
ORDER BY ObjectType, name;
"@) $inst
    }
}
Export-Result $s21 "$OutputDir\21_Service_Broker.csv" "Service Broker"


# =============================================================================
# 22  EXTENDED EVENTS SESSIONS
# =============================================================================
Write-Header "22 — Extended Events Sessions"
$s22 = foreach ($inst in $SqlInstances) {
    Add-Meta (Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
SELECT
    s.name AS SessionName, s.session_id,
    s.start_time, s.event_retention_mode_desc,
    s.max_dispatch_latency, s.max_memory,
    s.max_event_size, s.memory_partition_mode_desc,
    s.track_causality, s.startup_state,
    t.name AS TargetName, t.package0_guid,
    t.execution_count AS TargetExecutionCount,
    t.execution_duration_ms AS TargetDurationMs,
    CAST(t.target_data AS nvarchar(max)) AS TargetDataSample
FROM sys.dm_xe_sessions s WITH (NOLOCK)
JOIN sys.dm_xe_session_targets t ON s.address=t.event_session_address
ORDER BY s.name;
"@) $inst
}
Export-Result $s22 "$OutputDir\22_Extended_Events.csv" "Extended Events"


# =============================================================================
# 23  REPLICATION
# =============================================================================
Write-Header "23 — Replication"
$s23 = foreach ($inst in $SqlInstances) {
    Add-Meta (Safe-Query -ServerInstance $inst -Cred $Credential -Database 'distribution' -Query @"
SELECT
    pub.name        AS PublicationName,
    pub.description,
    pub.publication_type,
    pub.status,
    pub.allow_push, pub.allow_pull, pub.allow_anonymous,
    pub.retention, pub.sync_method,
    s.name          AS PublisherDB,
    sub.subscriber_db,
    sub.subscription_type,
    sub.sync_type,
    sub.status AS SubscriptionStatus,
    sub.update_mode
FROM distribution.dbo.MSpublications pub WITH (NOLOCK)
JOIN sys.databases s ON pub.publisher_db = s.name
LEFT JOIN distribution.dbo.MSsubscriptions sub ON pub.publication_id=sub.publication_id
ORDER BY pub.name;
"@) $inst
}
Export-Result $s23 "$OutputDir\23_Replication.csv" "Replication"


# =============================================================================
# 24  QUERY STORE SETTINGS (all online DBs)
# =============================================================================
Write-Header "24 — Query Store Settings"
$s24 = foreach ($inst in $SqlInstances) {
    Add-Meta (Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
SELECT
    d.name AS DatabaseName,
    qs.desired_state_desc, qs.actual_state_desc,
    qs.readonly_reason, qs.current_storage_size_mb,
    qs.flush_interval_seconds, qs.data_flush_interval_seconds,
    qs.max_storage_size_mb, qs.stale_query_threshold_days,
    qs.max_plans_per_query, qs.query_capture_mode_desc,
    qs.size_based_cleanup_mode_desc,
    qs.wait_stats_capture_mode_desc
FROM sys.databases d WITH (NOLOCK)
JOIN sys.dm_db_tuning_recommendations tr ON 1=0   -- join placeholder
RIGHT JOIN (
    SELECT name, database_id FROM sys.databases WITH (NOLOCK) WHERE state_desc='ONLINE'
) dbs ON d.name=dbs.name
CROSS APPLY (
    SELECT * FROM sys.database_query_store_options
) qs
WHERE d.state_desc = 'ONLINE'
ORDER BY d.name;
"@) $inst
}
# Fallback: per-db approach if cross-apply variant fails
if (-not $s24) {
    $s24 = foreach ($inst in $SqlInstances) {
        foreach ($db in (Get-DbList $inst $Credential)) {
            Add-Meta (Safe-Query -ServerInstance $inst -Cred $Credential -Database $db -Query @"
SELECT DB_NAME() AS DatabaseName,
    desired_state_desc, actual_state_desc, readonly_reason,
    current_storage_size_mb, flush_interval_seconds,
    data_flush_interval_seconds, max_storage_size_mb,
    stale_query_threshold_days, max_plans_per_query,
    query_capture_mode_desc, size_based_cleanup_mode_desc,
    wait_stats_capture_mode_desc
FROM sys.database_query_store_options WITH (NOLOCK);
"@) $inst
        }
    }
}
Export-Result $s24 "$OutputDir\24_Query_Store_Settings.csv" "Query Store"


# =============================================================================
# 25  CLR ASSEMBLIES (all DBs)
# =============================================================================
Write-Header "25 — CLR Assemblies"
$s25 = foreach ($inst in $SqlInstances) {
    foreach ($db in (Get-DbList $inst $Credential)) {
        Add-Meta (Safe-Query -ServerInstance $inst -Cred $Credential -Database $db -Query @"
SELECT DB_NAME() AS DatabaseName,
    a.name AS AssemblyName, a.assembly_id,
    a.clr_name, a.permission_set_desc, a.create_date, a.modify_date,
    a.is_visible, a.is_user_defined,
    af.name AS FileName, af.file_id
FROM sys.assemblies a WITH (NOLOCK)
JOIN sys.assembly_files af ON a.assembly_id=af.assembly_id
WHERE a.is_user_defined=1
ORDER BY a.name;
"@) $inst
    }
}
Export-Result $s25 "$OutputDir\25_CLR_Assemblies.csv" "CLR Assemblies"


# =============================================================================
# 26  DDL TRIGGERS — SERVER & DATABASE LEVEL
# =============================================================================
Write-Header "26 — DDL Triggers"
$s26a = foreach ($inst in $SqlInstances) {
    Add-Meta (Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
SELECT
    'Server' AS TriggerScope, name, object_id AS trigger_id,
    type_desc, is_disabled, is_not_for_replication,
    parent_class_desc, create_date, modify_date
FROM sys.server_triggers WITH (NOLOCK)
ORDER BY name;
"@) $inst
}
Export-Result $s26a "$OutputDir\26a_DDL_Triggers_Server.csv" "DDL Triggers (Server)"

$s26b = foreach ($inst in $SqlInstances) {
    foreach ($db in (Get-DbList $inst $Credential)) {
        Add-Meta (Safe-Query -ServerInstance $inst -Cred $Credential -Database $db -Query @"
SELECT DB_NAME() AS DatabaseName, name, object_id AS trigger_id,
    type_desc, is_disabled, is_not_for_replication,
    parent_class_desc, create_date, modify_date
FROM sys.triggers WITH (NOLOCK)
WHERE parent_class_desc = 'DATABASE'
ORDER BY name;
"@) $inst
    }
}
Export-Result $s26b "$OutputDir\26b_DDL_Triggers_Database.csv" "DDL Triggers (DB)"


# =============================================================================
# 27  STARTUP STORED PROCEDURES
# =============================================================================
Write-Header "27 — Startup Stored Procedures"
$s27 = foreach ($inst in $SqlInstances) {
    Add-Meta (Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
SELECT
    o.name AS ProcedureName, o.object_id,
    o.create_date, o.modify_date,
    o.is_ms_shipped,
    OBJECTPROPERTY(o.object_id,'ExecIsStartup') AS IsStartup
FROM sys.objects o WITH (NOLOCK)
WHERE OBJECTPROPERTY(o.object_id,'ExecIsStartup')=1
  AND o.type='P'
ORDER BY o.name;
"@) $inst
}
Export-Result $s27 "$OutputDir\27_Startup_Procedures.csv" "Startup Procedures"


# =============================================================================
# 28  FULL-TEXT SEARCH
# =============================================================================
Write-Header "28 — Full-Text Search"
$s28 = foreach ($inst in $SqlInstances) {
    foreach ($db in (Get-DbList $inst $Credential)) {
        Add-Meta (Safe-Query -ServerInstance $inst -Cred $Credential -Database $db -Query @"
SELECT DB_NAME() AS DatabaseName,
    c.name AS CatalogName, c.fulltext_catalog_id,
    c.is_default, c.is_accent_sensitivity_on,
    c.data_space_id, c.file_id,
    i.name AS IndexedTableName, i.object_id,
    i.is_enabled, i.change_tracking_state_desc,
    i.crawl_type_desc, i.has_crawl_completed,
    i.crawl_start_date, i.crawl_end_date,
    i.item_count, i.fragment_count
FROM sys.fulltext_catalogs c WITH (NOLOCK)
LEFT JOIN sys.fulltext_indexes i ON c.fulltext_catalog_id=i.fulltext_catalog_id
ORDER BY c.name;
"@) $inst
    }
}
Export-Result $s28 "$OutputDir\28_FullText_Search.csv" "Full-Text Search"


# =============================================================================
# 29  BACKUP DEVICES
# =============================================================================
Write-Header "29 — Backup Devices"
$s29 = foreach ($inst in $SqlInstances) {
    Add-Meta (Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
SELECT name, device_id, type_desc, physical_name, is_temp_device
FROM sys.backup_devices WITH (NOLOCK)
ORDER BY name;
"@) $inst
}
Export-Result $s29 "$OutputDir\29_Backup_Devices.csv" "Backup Devices"


# =============================================================================
# 30  ROW-LEVEL SECURITY (all DBs)
# =============================================================================
Write-Header "30 — Row-Level Security"
$s30 = foreach ($inst in $SqlInstances) {
    foreach ($db in (Get-DbList $inst $Credential)) {
        Add-Meta (Safe-Query -ServerInstance $inst -Cred $Credential -Database $db -Query @"
SELECT DB_NAME() AS DatabaseName,
    sp.name AS PolicyName, sp.object_id AS PolicyID,
    sp.is_enabled, sp.is_schema_bound,
    OBJECT_NAME(spf.target_object_id) AS TargetTable,
    spf.filter_predicate_object_id,
    spf.block_predicate_object_id,
    spf.operation_desc
FROM sys.security_policies sp WITH (NOLOCK)
JOIN sys.security_predicates spf ON sp.object_id=spf.object_id
ORDER BY sp.name;
"@) $inst
    }
}
Export-Result $s30 "$OutputDir\30_Row_Level_Security.csv" "Row-Level Security"


# =============================================================================
# 31  AUDITING — SERVER & DATABASE SPECS
# =============================================================================
Write-Header "31 — Auditing"
$s31a = foreach ($inst in $SqlInstances) {
    Add-Meta (Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
SELECT
    a.name AS AuditName, a.audit_guid,
    a.type_desc AS DestinationType,
    a.log_file_path, a.log_file_max_size_mb, a.log_file_max_files,
    a.is_state_enabled, a.queue_delay, a.on_failure_desc,
    sa.name AS ServerAuditSpecName,
    sa.is_state_enabled AS SpecEnabled,
    sad.audit_action_name,
    sad.audited_result, sad.class_desc,
    ISNULL(OBJECT_NAME(sad.major_id),'N/A') AS AuditedObject,
    ISNULL(prin.name,'N/A') AS AuditedPrincipal
FROM sys.server_audits a WITH (NOLOCK)
LEFT JOIN sys.server_audit_specifications sa ON a.audit_guid=sa.audit_guid
LEFT JOIN sys.server_audit_specification_details sad ON sa.server_specification_id=sad.server_specification_id
LEFT JOIN sys.server_principals prin ON sad.audited_principal_id=prin.principal_id
ORDER BY a.name, sad.audit_action_name;
"@) $inst
}
Export-Result $s31a "$OutputDir\31a_Server_Audits.csv" "Server Audits"

$s31b = foreach ($inst in $SqlInstances) {
    foreach ($db in (Get-DbList $inst $Credential)) {
        Add-Meta (Safe-Query -ServerInstance $inst -Cred $Credential -Database $db -Query @"
SELECT DB_NAME() AS DatabaseName,
    das.name AS DBSpecName, das.is_state_enabled,
    dasd.audit_action_name, dasd.audited_result,
    dasd.class_desc,
    ISNULL(OBJECT_NAME(dasd.major_id),'N/A') AS AuditedObject,
    ISNULL(prin.name,'N/A') AS AuditedPrincipal
FROM sys.database_audit_specifications das WITH (NOLOCK)
JOIN sys.database_audit_specification_details dasd ON das.database_specification_id=dasd.database_specification_id
LEFT JOIN sys.database_principals prin ON dasd.audited_principal_id=prin.principal_id
ORDER BY das.name;
"@) $inst
    }
}
Export-Result $s31b "$OutputDir\31b_Database_Audit_Specs.csv" "DB Audit Specs"


# =============================================================================
# 32  LINKED SERVERS
# =============================================================================
Write-Header "32 — Linked Servers"
$s32 = foreach ($inst in $SqlInstances) {
    Add-Meta (Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
SELECT
    ls.name AS LinkedServerName, ls.product, ls.provider,
    ls.data_source, ls.catalog, ls.connect_timeout,
    ls.query_timeout, ls.is_remote_login_enabled,
    ls.is_rpc_out_enabled, ls.is_data_access_enabled,
    ls.is_collation_compatible, ls.uses_remote_collation,
    ls.is_system, ls.modify_date,
    ll.local_principal_id, ll.uses_self_credential,
    ll.remote_name AS RemoteLoginMapped
FROM sys.servers ls WITH (NOLOCK)
LEFT JOIN sys.linked_logins ll ON ls.server_id=ll.server_id
WHERE ls.is_linked=1
ORDER BY ls.name;
"@) $inst
}
Export-Result $s32 "$OutputDir\32_Linked_Servers.csv" "Linked Servers"


# =============================================================================
# 33  SQL AGENT — JOBS, SCHEDULES, ALERTS, OPERATORS
# =============================================================================
Write-Header "33 — SQL Agent"
$s33a = foreach ($inst in $SqlInstances) {
    Add-Meta (Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
SELECT
    j.name AS JobName, j.enabled, j.description,
    c.name AS Category, SUSER_SNAME(j.owner_sid) AS Owner,
    j.date_created, j.date_modified,
    jh.run_status AS LastRunStatus,
    CONVERT(varchar,
        CAST(CAST(jh.run_date AS varchar(8)) AS datetime)
        +' '+STUFF(STUFF(RIGHT('000000'+CAST(jh.run_time AS varchar(6)),6),3,0,':'),6,0,':'),120) AS LastRunTime,
    jh.run_duration AS LastRunDurationHHMMSS,
    jh.message AS LastRunMessage,
    (SELECT COUNT(*) FROM msdb.dbo.sysjobsteps WHERE job_id=j.job_id) AS StepCount,
    js.next_run_date, js.next_run_time
FROM msdb.dbo.sysjobs j WITH (NOLOCK)
JOIN msdb.dbo.syscategories c ON j.category_id=c.category_id
LEFT JOIN msdb.dbo.sysjobhistory jh ON j.job_id=jh.job_id
    AND jh.instance_id=(SELECT MAX(instance_id) FROM msdb.dbo.sysjobhistory
                        WHERE job_id=j.job_id AND step_id=0)
LEFT JOIN msdb.dbo.sysjobschedules js ON j.job_id=js.job_id
ORDER BY j.name;
"@) $inst
}
Export-Result $s33a "$OutputDir\33a_Agent_Jobs.csv" "Agent Jobs"

$s33b = foreach ($inst in $SqlInstances) {
    Add-Meta (Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
SELECT
    a.name AS AlertName, a.enabled, a.message_id,
    a.severity, a.database_name, a.event_description_keyword,
    a.occurrence_count, a.last_occurrence_date, a.last_occurrence_time,
    a.last_response_date, a.last_response_time,
    a.notification_message, a.include_event_description_in,
    j.name AS JobToExecute
FROM msdb.dbo.sysalerts a WITH (NOLOCK)
LEFT JOIN msdb.dbo.sysjobs j ON a.job_id=j.job_id
ORDER BY a.name;
"@) $inst
}
Export-Result $s33b "$OutputDir\33b_Agent_Alerts.csv" "Agent Alerts"

$s33c = foreach ($inst in $SqlInstances) {
    Add-Meta (Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
SELECT name AS OperatorName, enabled,
    email_address, pager_address, netsend_address,
    weekday_pager_start_time, weekday_pager_end_time,
    pager_days, last_email_date, last_pager_date
FROM msdb.dbo.sysoperators WITH (NOLOCK)
ORDER BY name;
"@) $inst
}
Export-Result $s33c "$OutputDir\33c_Agent_Operators.csv" "Agent Operators"


# =============================================================================
# 34  MAINTENANCE PLANS
# =============================================================================
Write-Header "34 — Maintenance Plans"
$s34 = foreach ($inst in $SqlInstances) {
    Add-Meta (Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
SELECT
    mp.id AS PlanID, mp.name AS PlanName,
    mp.description, mp.create_date, mp.owner
FROM msdb.dbo.sysmaintplan_plans mp WITH (NOLOCK)
ORDER BY mp.name;
"@) $inst
}
Export-Result $s34 "$OutputDir\34_Maintenance_Plans.csv" "Maintenance Plans"


# =============================================================================
# SUMMARY MANIFEST
# =============================================================================
Write-Header "Export Complete — Summary"

$manifest = Get-ChildItem -Path $OutputDir -Filter "*.csv" | Sort-Object Name |
    Select-Object Name,
        @{N='Rows'  ; E={ try { (Import-Csv $_.FullName | Measure-Object).Count } catch { 0 } }},
        @{N='SizeKB'; E={ [math]::Round($_.Length/1KB,1) }},
        LastWriteTime

$manifest | Format-Table -AutoSize
$manifest | Export-Csv "$OutputDir\00_MANIFEST.csv" -NoTypeInformation -Encoding UTF8

$totalFiles = ($manifest | Measure-Object).Count
$totalRows  = ($manifest | Measure-Object Rows -Sum).Sum
Write-Host "`n  $totalFiles CSV files | $totalRows total rows" -ForegroundColor Green
Write-Host "  Output: $(Resolve-Path $OutputDir)" -ForegroundColor Green
Write-Host "`n  To review any file:" -ForegroundColor Yellow
Write-Host "  Import-Csv '$OutputDir\09_Database_Config.csv' | Out-GridView" -ForegroundColor Yellow
