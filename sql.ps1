#Requires -Version 5.1
<#
.SYNOPSIS
    Read-only collection of SQL Server configuration, database settings,
    security configuration, and associated Azure/Windows VM metadata.
    Exports all data to CSV files.

.DESCRIPTION
    JIRA-006 | No write operations are performed.
    Requires: SqlServer module  ->  Install-Module SqlServer -Scope CurrentUser
              Az module         ->  Install-Module Az -Scope CurrentUser  (for Azure VM metadata)

.PARAMETER SqlInstances
    Comma-separated list of SQL Server instance names to collect from.
    Defaults to the local machine default instance.

.PARAMETER OutputDir
    Directory where CSV files will be written. Defaults to .\SQLConfigExport_<timestamp>

.PARAMETER Credential
    Optional PSCredential for SQL auth. Omit for Windows auth.

.EXAMPLE
    .\Collect-SQLConfig.ps1 -SqlInstances "SQL01","SQL02\INST1" -OutputDir "C:\Exports"
#>

[CmdletBinding()]
param(
    [string[]] $SqlInstances  = @($env:COMPUTERNAME),
    [string]   $OutputDir     = ".\SQLConfigExport_$(Get-Date -Format 'yyyyMMdd_HHmmss')",
    [System.Management.Automation.PSCredential] $Credential
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ── helpers ──────────────────────────────────────────────────────────────────

function Write-Header ($msg) {
    Write-Host "`n=== $msg ===" -ForegroundColor Cyan
}

function Safe-Query {
    param($ServerInstance, $Query, [PSCredential]$Cred)
    $params = @{ ServerInstance = $ServerInstance; Query = $Query; ErrorAction = 'Stop' }
    if ($Cred) { $params.Credential = $Cred }
    try   { Invoke-Sqlcmd @params }
    catch { Write-Warning "Query failed on $ServerInstance : $_"; return $null }
}

function Export-Csv-Safe ($Data, $Path) {
    if ($Data) {
        $Data | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8 -Force
        Write-Host "  Saved: $Path" -ForegroundColor Green
    } else {
        Write-Warning "  No data to export for: $Path"
    }
}

# ── pre-flight ────────────────────────────────────────────────────────────────

if (-not (Get-Module -ListAvailable -Name SqlServer)) {
    Write-Error "SqlServer module not found. Run: Install-Module SqlServer -Scope CurrentUser"
    exit 1
}
Import-Module SqlServer -ErrorAction Stop

$null = New-Item -ItemType Directory -Path $OutputDir -Force
Write-Host "Output directory: $(Resolve-Path $OutputDir)" -ForegroundColor Yellow

# ═════════════════════════════════════════════════════════════════════════════
# 1. WINDOWS VM HOST INFORMATION
# ═════════════════════════════════════════════════════════════════════════════
Write-Header "1. Windows VM Host Information"

$vmRows = foreach ($inst in $SqlInstances) {
    $hostName = $inst.Split('\')[0]
    try {
        $os   = Get-CimInstance -ComputerName $hostName -ClassName Win32_OperatingSystem -ErrorAction Stop
        $cpu  = Get-CimInstance -ComputerName $hostName -ClassName Win32_Processor       -ErrorAction Stop | Select-Object -First 1
        $mem  = Get-CimInstance -ComputerName $hostName -ClassName Win32_PhysicalMemory  -ErrorAction Stop
        $nic  = Get-CimInstance -ComputerName $hostName -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" -ErrorAction Stop | Select-Object -First 1
        $disk = Get-CimInstance -ComputerName $hostName -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop
        $pf   = Get-CimInstance -ComputerName $hostName -ClassName Win32_PageFileUsage  -ErrorAction SilentlyContinue
        $pp   = Get-CimInstance -ComputerName $hostName -ClassName Win32_PowerPlan -Namespace root\cimv2\power -ErrorAction SilentlyContinue | Where-Object IsActive -eq $true

        $totalRam = [math]::Round(($mem | Measure-Object -Property Capacity -Sum).Sum / 1GB, 2)
        $diskInfo = ($disk | ForEach-Object { "$($_.DeviceID) $([math]::Round($_.Size/1GB,1))GB free:$([math]::Round($_.FreeSpace/1GB,1))GB" }) -join ' | '

        # Azure IMDS (returns nothing on non-Azure hosts — safe to call)
        $azMeta = try {
            $r = Invoke-RestMethod -Uri 'http://169.254.169.254/metadata/instance?api-version=2021-02-01' `
                                   -Headers @{Metadata='true'} -TimeoutSec 3 -ErrorAction Stop
            "vmSize=$($r.compute.vmSize) region=$($r.compute.location) resourceGroup=$($r.compute.resourceGroupName) subscriptionId=$($r.compute.subscriptionId)"
        } catch { "Not Azure or IMDS unavailable" }

        [PSCustomObject]@{
            SqlInstance        = $inst
            HostName           = $hostName
            OSCaption          = $os.Caption
            OSVersion          = $os.Version
            OSBuildNumber      = $os.BuildNumber
            OSLastBootTime     = $os.LastBootUpTime
            CPUName            = $cpu.Name
            CPUCores           = $cpu.NumberOfCores
            CPULogicalProcs    = $cpu.NumberOfLogicalProcessors
            TotalRAM_GB        = $totalRam
            PagefileConfig     = if ($pf) { "$($pf.Name) AllocatedMB=$($pf.AllocatedBaseSize)" } else { 'N/A' }
            PowerPlan          = if ($pp) { $pp.ElementName } else { 'N/A' }
            DomainOrWorkgroup  = $os.CSName + '\' + (Get-CimInstance -ComputerName $hostName -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue).Domain
            IPAddresses        = ($nic.IPAddress -join ', ')
            MACAddress         = $nic.MACAddress
            DNSSuffix          = $nic.DNSDomainSuffixSearchOrder -join ', '
            DiskLayout         = $diskInfo
            AzureMetadata      = $azMeta
            CollectedAt        = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        }
    } catch {
        Write-Warning "Could not collect VM info for $hostName : $_"
    }
}
Export-Csv-Safe $vmRows "$OutputDir\01_VM_Host_Info.csv"


# ═════════════════════════════════════════════════════════════════════════════
# 2. SQL INSTANCE-LEVEL CONFIGURATION
# ═════════════════════════════════════════════════════════════════════════════
Write-Header "2. SQL Instance-Level Configuration"

$instanceRows = foreach ($inst in $SqlInstances) {

    $q = @"
SELECT
    SERVERPROPERTY('ServerName')               AS InstanceName,
    SERVERPROPERTY('ProductVersion')           AS ProductVersion,
    SERVERPROPERTY('ProductLevel')             AS ProductLevel,
    SERVERPROPERTY('Edition')                  AS Edition,
    SERVERPROPERTY('EngineEdition')            AS EngineEdition,
    SERVERPROPERTY('Collation')                AS ServerCollation,
    SERVERPROPERTY('IsIntegratedSecurityOnly') AS WindowsAuthOnly,
    SERVERPROPERTY('IsClustered')              AS IsClustered,
    SERVERPROPERTY('IsHadrEnabled')            AS IsAGEnabled,
    SERVERPROPERTY('ComputerNamePhysicalNetBIOS') AS PhysicalHost,
    @@SERVICENAME                              AS ServiceName,
    @@VERSION                                  AS FullVersion;
"@
    $srv = Safe-Query -ServerInstance $inst -Query $q -Cred $Credential

    $spCfg = Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
SELECT name, value_in_use AS CurrentValue, description
FROM sys.configurations WITH (NOLOCK)
ORDER BY name;
"@

    # Pivot sp_configure into columns
    $cfgMap = @{}
    if ($spCfg) { $spCfg | ForEach-Object { $cfgMap[$_.name] = $_.CurrentValue } }

    # SQL Agent service account (read from registry via xp_regread — read-only)
    $agentAcct = Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
EXEC xp_instance_regread
    N'HKEY_LOCAL_MACHINE',
    N'SYSTEM\CurrentControlSet\Services\SQLSERVERAGENT',
    N'ObjectName';
"@

    $svcAcct = Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
EXEC xp_instance_regread
    N'HKEY_LOCAL_MACHINE',
    N'SYSTEM\CurrentControlSet\Services\MSSQLSERVER',
    N'ObjectName';
"@

    # Startup parameters
    $startupParams = Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
EXEC xp_instance_regread
    N'HKEY_LOCAL_MACHINE',
    N'SOFTWARE\Microsoft\MSSQLServer\MSSQLServer\Parameters',
    N'SQLArg0';
"@

    # Enabled protocols
    $protocols = Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
SELECT protocol_desc, is_enabled
FROM sys.dm_server_services WITH (NOLOCK);
"@

    # Error log path
    $errLog = Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
EXEC xp_instance_regread
    N'HKEY_LOCAL_MACHINE',
    N'SOFTWARE\Microsoft\MSSQLServer\MSSQLServer',
    N'ErrorLogPath';
"@

    if ($srv) {
        [PSCustomObject]@{
            SqlInstance             = $inst
            ServerName              = $srv.InstanceName
            PhysicalHost            = $srv.PhysicalHost
            ServiceName             = $srv.ServiceName
            ProductVersion          = $srv.ProductVersion
            ProductLevel            = $srv.ProductLevel
            Edition                 = $srv.Edition
            FullVersion             = ($srv.FullVersion -replace '\r?\n',' ')
            ServerCollation         = $srv.ServerCollation
            WindowsAuthOnly         = $srv.WindowsAuthOnly
            IsClustered             = $srv.IsClustered
            IsAGEnabled             = $srv.IsAGEnabled
            SqlServiceAccount       = if ($svcAcct)   { $svcAcct.Data }  else { 'N/A' }
            AgentServiceAccount     = if ($agentAcct) { $agentAcct.Data } else { 'N/A' }
            MaxServerMemory_MB      = $cfgMap['max server memory (MB)']
            MinServerMemory_MB      = $cfgMap['min server memory (MB)']
            MaxDOP                  = $cfgMap['max degree of parallelism']
            CostThresholdParallel   = $cfgMap['cost threshold for parallelism']
            RemoteAccess            = $cfgMap['remote access']
            XPCmdShellEnabled       = $cfgMap['xp_cmdshell']
            CLREnabled              = $cfgMap['clr enabled']
            OLEAutomation           = $cfgMap['Ole Automation Procedures']
            LinkedServersAllowed    = $cfgMap['ad hoc distributed queries']
            OptimizeForAdHoc        = $cfgMap['optimize for ad hoc workloads']
            FillFactor              = $cfgMap['fill factor (%)']
            NetworkPacketSize       = $cfgMap['network packet size (B)']
            Protocols               = if ($protocols) { ($protocols | ForEach-Object { "$($_.protocol_desc)=$($_.is_enabled)" }) -join ' | ' } else { 'N/A' }
            ErrorLogPath            = if ($errLog) { $errLog.Data } else { 'N/A' }
            CollectedAt             = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        }
    }
}
Export-Csv-Safe $instanceRows "$OutputDir\02_Instance_Config.csv"


# ═════════════════════════════════════════════════════════════════════════════
# 3. PER-DATABASE CONFIGURATION
# ═════════════════════════════════════════════════════════════════════════════
Write-Header "3. Per-Database Configuration"

$dbRows = foreach ($inst in $SqlInstances) {
    $results = Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
SELECT
    d.name                          AS DatabaseName,
    d.database_id                   AS DatabaseID,
    d.state_desc                    AS State,
    d.user_access_desc              AS UserAccess,
    SUSER_SNAME(d.owner_sid)        AS DatabaseOwner,
    d.recovery_model_desc           AS RecoveryModel,
    d.compatibility_level           AS CompatibilityLevel,
    d.collation_name                AS DatabaseCollation,
    d.is_read_only                  AS IsReadOnly,
    d.is_auto_close_on              AS AutoClose,
    d.is_auto_shrink_on             AS AutoShrink,
    d.is_auto_update_stats_on       AS AutoUpdateStats,
    d.is_auto_create_stats_on       AS AutoCreateStats,
    d.is_encrypted                  AS TDEEnabled,
    d.is_query_store_on             AS QueryStoreEnabled,
    d.snapshot_isolation_state_desc AS SnapshotIsolation,
    d.is_read_committed_snapshot_on AS RCSI,
    d.page_verify_option_desc       AS PageVerify,
    d.log_reuse_wait_desc           AS LogReuseWait,
    d.create_date                   AS CreateDate,
    d.is_in_standby                 AS IsStandby,

    -- File info
    (SELECT STRING_AGG(CAST(mf.name + '|' + mf.physical_name + '|type:' + mf.type_desc
        + '|sizeMB:' + CAST(mf.size*8/1024 AS varchar)
        + '|maxsizeMB:' + CASE WHEN mf.max_size=-1 THEN 'Unlimited' ELSE CAST(mf.max_size*8/1024 AS varchar) END
        + '|growth:' + CAST(mf.growth AS varchar) + CASE WHEN mf.is_percent_growth=1 THEN '%' ELSE 'pages' END
        AS nvarchar(max)), ' || ')
     FROM sys.master_files mf WHERE mf.database_id = d.database_id)
                                AS FileDetails,

    -- Backup history
    (SELECT TOP 1 CONVERT(varchar,backup_finish_date,120) FROM msdb..backupset
     WHERE database_name=d.name AND type='D' ORDER BY backup_finish_date DESC) AS LastFullBackup,
    (SELECT TOP 1 CONVERT(varchar,backup_finish_date,120) FROM msdb..backupset
     WHERE database_name=d.name AND type='I' ORDER BY backup_finish_date DESC) AS LastDiffBackup,
    (SELECT TOP 1 CONVERT(varchar,backup_finish_date,120) FROM msdb..backupset
     WHERE database_name=d.name AND type='L' ORDER BY backup_finish_date DESC) AS LastLogBackup,

    -- Size summary
    (SELECT CAST(SUM(CASE WHEN type=0 THEN size END)*8.0/1024 AS decimal(18,2))
     FROM sys.master_files WHERE database_id=d.database_id)  AS DataSize_MB,
    (SELECT CAST(SUM(CASE WHEN type=1 THEN size END)*8.0/1024 AS decimal(18,2))
     FROM sys.master_files WHERE database_id=d.database_id)  AS LogSize_MB

FROM sys.databases d WITH (NOLOCK)
ORDER BY d.name;
"@

    if ($results) {
        $results | Select-Object *, @{N='SqlInstance';E={$inst}}, @{N='CollectedAt';E={(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')}}
    }
}
Export-Csv-Safe $dbRows "$OutputDir\03_Database_Config.csv"


# ═════════════════════════════════════════════════════════════════════════════
# 4. STORAGE — DATA & LOG FILES DETAIL
# ═════════════════════════════════════════════════════════════════════════════
Write-Header "4. Database File Details"

$fileRows = foreach ($inst in $SqlInstances) {
    Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
SELECT
    DB_NAME(mf.database_id)                         AS DatabaseName,
    mf.file_id                                      AS FileID,
    mf.name                                         AS LogicalName,
    mf.physical_name                                AS PhysicalPath,
    mf.type_desc                                    AS FileType,
    mf.state_desc                                   AS FileState,
    CAST(mf.size * 8.0 / 1024 AS decimal(18,2))    AS CurrentSize_MB,
    CASE WHEN mf.max_size = -1 THEN 'Unlimited'
         ELSE CAST(mf.max_size * 8.0 / 1024 AS varchar) END AS MaxSize_MB,
    CASE WHEN mf.is_percent_growth = 1
         THEN CAST(mf.growth AS varchar) + '%'
         ELSE CAST(mf.growth * 8.0 / 1024 AS varchar) + ' MB' END AS AutoGrowth,
    mf.is_percent_growth                            AS GrowthIsPercent
FROM sys.master_files mf WITH (NOLOCK)
ORDER BY DB_NAME(mf.database_id), mf.type, mf.file_id;
"@ | Select-Object *, @{N='SqlInstance';E={$inst}}, @{N='CollectedAt';E={(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')}}
}
Export-Csv-Safe $fileRows "$OutputDir\04_Database_Files.csv"


# ═════════════════════════════════════════════════════════════════════════════
# 5. HIGH AVAILABILITY & DISASTER RECOVERY
# ═════════════════════════════════════════════════════════════════════════════
Write-Header "5. HA/DR Configuration"

$haRows = foreach ($inst in $SqlInstances) {
    Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
SELECT
    ag.name                         AS AGName,
    agl.dns_name                    AS ListenerDNS,
    agl.port                        AS ListenerPort,
    ars.role_desc                   AS ReplicaRole,
    ar.replica_server_name          AS ReplicaServer,
    ar.availability_mode_desc       AS AvailabilityMode,
    ar.failover_mode_desc           AS FailoverMode,
    ar.seeding_mode_desc            AS SeedingMode,
    ar.secondary_role_allow_connections_desc AS SecondaryConnections,
    adb.database_name               AS AGDatabase,
    adb.synchronization_state_desc  AS SyncState,
    adb.synchronization_health_desc AS SyncHealth,
    adb.log_send_queue_size         AS LogSendQueue_KB,
    adb.redo_queue_size             AS RedoQueue_KB
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar         ON ag.group_id = ar.group_id
JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id
LEFT JOIN sys.availability_group_listeners agl    ON ag.group_id = agl.group_id
LEFT JOIN sys.dm_hadr_database_replica_states adb ON ar.replica_id = adb.replica_id
ORDER BY ag.name, ar.replica_server_name;
"@ | Select-Object *, @{N='SqlInstance';E={$inst}}, @{N='CollectedAt';E={(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')}}
}
Export-Csv-Safe $haRows "$OutputDir\05_HA_DR_Config.csv"


# ═════════════════════════════════════════════════════════════════════════════
# 6. SQL LOGINS & SERVER-LEVEL SECURITY
# ═════════════════════════════════════════════════════════════════════════════
Write-Header "6. SQL Logins & Server Security"

$loginRows = foreach ($inst in $SqlInstances) {
    Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
SELECT
    sp.name                         AS LoginName,
    sp.type_desc                    AS LoginType,
    sp.is_disabled                  AS IsDisabled,
    sp.is_policy_checked            AS PasswordPolicyChecked,
    sp.is_expiration_checked        AS PasswordExpirationChecked,
    sp.create_date                  AS CreateDate,
    sp.modify_date                  AS ModifyDate,
    sp.default_database_name        AS DefaultDatabase,
    sp.default_language_name        AS DefaultLanguage,
    STUFF((SELECT ', ' + spr2.name
           FROM sys.server_role_members srm2
           JOIN sys.server_principals spr2 ON srm2.role_principal_id = spr2.principal_id
           WHERE srm2.member_principal_id = sp.principal_id
           FOR XML PATH('')), 1, 2, '') AS ServerRoles
FROM sys.server_principals sp WITH (NOLOCK)
WHERE sp.type IN ('S','U','G','E','X')   -- SQL, Windows user, Windows group, External
  AND sp.name NOT LIKE '##%'
ORDER BY sp.type_desc, sp.name;
"@ | Select-Object *, @{N='SqlInstance';E={$inst}}, @{N='CollectedAt';E={(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')}}
}
Export-Csv-Safe $loginRows "$OutputDir\06_Logins_Security.csv"


# ═════════════════════════════════════════════════════════════════════════════
# 7. DATABASE USERS & ROLES (ALL DATABASES)
# ═════════════════════════════════════════════════════════════════════════════
Write-Header "7. Database Users & Roles"

$dbUserRows = foreach ($inst in $SqlInstances) {
    # Get list of online databases
    $dbs = Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
SELECT name FROM sys.databases WITH (NOLOCK)
WHERE state_desc = 'ONLINE' AND name NOT IN ('tempdb')
ORDER BY name;
"@
    foreach ($db in $dbs) {
        Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
USE [$($db.name)];
SELECT
    DB_NAME()                       AS DatabaseName,
    dp.name                         AS UserName,
    dp.type_desc                    AS UserType,
    dp.authentication_type_desc     AS AuthType,
    dp.create_date                  AS CreateDate,
    dp.modify_date                  AS ModifyDate,
    ISNULL(sl.name, 'No Login')     AS MappedLogin,
    dp.default_schema_name          AS DefaultSchema,
    STUFF((SELECT ', ' + rp.name
           FROM sys.database_role_members drm
           JOIN sys.database_principals rp ON drm.role_principal_id = rp.principal_id
           WHERE drm.member_principal_id = dp.principal_id
           FOR XML PATH('')),1,2,'') AS DatabaseRoles
FROM sys.database_principals dp WITH (NOLOCK)
LEFT JOIN sys.server_principals sl ON dp.sid = sl.sid
WHERE dp.type NOT IN ('R')
  AND dp.name NOT IN ('dbo','guest','sys','INFORMATION_SCHEMA')
ORDER BY dp.name;
"@ | Select-Object *, @{N='SqlInstance';E={$inst}}, @{N='CollectedAt';E={(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')}}
    }
}
Export-Csv-Safe $dbUserRows "$OutputDir\07_Database_Users_Roles.csv"


# ═════════════════════════════════════════════════════════════════════════════
# 8. LINKED SERVERS
# ═════════════════════════════════════════════════════════════════════════════
Write-Header "8. Linked Servers"

$linkedRows = foreach ($inst in $SqlInstances) {
    Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
SELECT
    ls.name                         AS LinkedServerName,
    ls.product                      AS Product,
    ls.provider                     AS Provider,
    ls.data_source                  AS DataSource,
    ls.catalog                      AS Catalog,
    ls.is_remote_login_enabled      AS RemoteLoginEnabled,
    ls.is_rpc_out_enabled           AS RPCOutEnabled,
    ls.is_data_access_enabled       AS DataAccessEnabled,
    ls.modify_date                  AS ModifyDate,
    ll.remote_name                  AS RemoteLoginMapped,
    ll.uses_self_credential         AS UsesSelfCredential
FROM sys.servers ls WITH (NOLOCK)
LEFT JOIN sys.linked_logins ll ON ls.server_id = ll.server_id
WHERE ls.is_linked = 1
ORDER BY ls.name;
"@ | Select-Object *, @{N='SqlInstance';E={$inst}}, @{N='CollectedAt';E={(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')}}
}
Export-Csv-Safe $linkedRows "$OutputDir\08_Linked_Servers.csv"


# ═════════════════════════════════════════════════════════════════════════════
# 9. SQL SERVER AGENT JOBS
# ═════════════════════════════════════════════════════════════════════════════
Write-Header "9. SQL Agent Jobs"

$jobRows = foreach ($inst in $SqlInstances) {
    Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
SELECT
    j.name                          AS JobName,
    j.enabled                       AS IsEnabled,
    j.description                   AS Description,
    c.name                          AS CategoryName,
    SUSER_SNAME(j.owner_sid)        AS JobOwner,
    j.date_created                  AS DateCreated,
    j.date_modified                 AS DateModified,
    jh.run_status                   AS LastRunStatus,  -- 0=Failed,1=Succeeded,2=Retry,3=Cancelled
    CONVERT(varchar,
        CAST(CAST(jh.run_date AS varchar(8)) AS datetime)
        + ' ' +
        STUFF(STUFF(RIGHT('000000'+CAST(jh.run_time AS varchar(6)),6),3,0,':'),6,0,':'),
        120)                        AS LastRunDateTime,
    js.next_run_date                AS NextRunDate,
    js.next_run_time                AS NextRunTime
FROM msdb.dbo.sysjobs j WITH (NOLOCK)
JOIN msdb.dbo.syscategories c      ON j.category_id = c.category_id
LEFT JOIN msdb.dbo.sysjobhistory jh ON j.job_id = jh.job_id
    AND jh.instance_id = (
        SELECT MAX(instance_id) FROM msdb.dbo.sysjobhistory
        WHERE job_id = j.job_id AND step_id = 0)
LEFT JOIN msdb.dbo.sysjobschedules js ON j.job_id = js.job_id
ORDER BY j.name;
"@ | Select-Object *, @{N='SqlInstance';E={$inst}}, @{N='CollectedAt';E={(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')}}
}
Export-Csv-Safe $jobRows "$OutputDir\09_SQL_Agent_Jobs.csv"


# ═════════════════════════════════════════════════════════════════════════════
# 10. AUDITING & THREAT PROTECTION
# ═════════════════════════════════════════════════════════════════════════════
Write-Header "10. Auditing Configuration"

$auditRows = foreach ($inst in $SqlInstances) {
    Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
SELECT
    a.name                          AS AuditName,
    a.audit_guid                    AS AuditGUID,
    a.type_desc                     AS AuditDestinationType,
    a.log_file_path                 AS LogFilePath,
    a.log_file_max_size_mb          AS MaxFileSizeMB,
    a.log_file_max_files            AS MaxFiles,
    a.is_state_enabled              AS IsEnabled,
    a.queue_delay                   AS QueueDelayMS,
    a.on_failure_desc               AS OnFailure,
    sa.name                         AS AuditSpecName,
    sa.is_state_enabled             AS SpecEnabled
FROM sys.server_audits a WITH (NOLOCK)
LEFT JOIN sys.server_audit_specifications sa ON a.audit_guid = sa.audit_guid
ORDER BY a.name;
"@ | Select-Object *, @{N='SqlInstance';E={$inst}}, @{N='CollectedAt';E={(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')}}
}
Export-Csv-Safe $auditRows "$OutputDir\10_Audit_Config.csv"


# ═════════════════════════════════════════════════════════════════════════════
# 11. TDE (TRANSPARENT DATA ENCRYPTION) STATUS
# ═════════════════════════════════════════════════════════════════════════════
Write-Header "11. TDE Status"

$tdeRows = foreach ($inst in $SqlInstances) {
    Safe-Query -ServerInstance $inst -Cred $Credential -Query @"
SELECT
    DB_NAME(dek.database_id)        AS DatabaseName,
    dek.encryption_state_desc       AS EncryptionState,
    dek.key_algorithm               AS KeyAlgorithm,
    dek.key_length                  AS KeyLength,
    dek.encryptor_type              AS EncryptorType,
    dek.percent_complete            AS EncryptionPct,
    c.name                          AS CertificateName,
    c.expiry_date                   AS CertExpiry,
    c.pvt_key_encryption_type_desc  AS KeyEncryptionType
FROM sys.dm_database_encryption_keys dek WITH (NOLOCK)
LEFT JOIN sys.certificates c ON dek.encryptor_thumbprint = c.thumbprint
ORDER BY DB_NAME(dek.database_id);
"@ | Select-Object *, @{N='SqlInstance';E={$inst}}, @{N='CollectedAt';E={(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')}}
}
Export-Csv-Safe $tdeRows "$OutputDir\11_TDE_Status.csv"


# ═════════════════════════════════════════════════════════════════════════════
# 12. AZURE VM METADATA (IMDS — only runs if host is an Azure VM)
# ═════════════════════════════════════════════════════════════════════════════
Write-Header "12. Azure VM IMDS Metadata"

$azureRows = foreach ($inst in $SqlInstances) {
    $hostName = $inst.Split('\')[0]
    try {
        $meta = Invoke-RestMethod `
            -Uri 'http://169.254.169.254/metadata/instance?api-version=2021-02-01' `
            -Headers @{Metadata = 'true'} `
            -TimeoutSec 3 `
            -ErrorAction Stop

        [PSCustomObject]@{
            SqlInstance       = $inst
            HostName          = $hostName
            VMName            = $meta.compute.name
            VMSize            = $meta.compute.vmSize
            Region            = $meta.compute.location
            Zone              = $meta.compute.zone
            ResourceGroup     = $meta.compute.resourceGroupName
            SubscriptionId    = $meta.compute.subscriptionId
            OSType            = $meta.compute.osType
            ImageOffer        = $meta.compute.storageProfile.imageReference.offer
            ImageSKU          = $meta.compute.storageProfile.imageReference.sku
            ImageVersion      = $meta.compute.storageProfile.imageReference.version
            OSDiskType        = $meta.compute.storageProfile.osDisk.managedDisk.storageAccountType
            DataDisks         = ($meta.compute.storageProfile.dataDisks | ForEach-Object { "$($_.name):$($_.diskSizeGB)GB:$($_.managedDisk.storageAccountType)" }) -join ' | '
            Tags              = ($meta.compute.tags | ConvertTo-Json -Compress)
            PrivateIPv4       = ($meta.network.interface[0].ipv4.ipAddress[0].privateIpAddress)
            PublicIPv4        = ($meta.network.interface[0].ipv4.ipAddress[0].publicIpAddress)
            CollectedAt       = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        }
    } catch {
        Write-Warning "  $hostName is not an Azure VM or IMDS is unreachable — skipping Azure metadata."
    }
}
Export-Csv-Safe $azureRows "$OutputDir\12_Azure_VM_Metadata.csv"


# ═════════════════════════════════════════════════════════════════════════════
# SUMMARY MANIFEST
# ═════════════════════════════════════════════════════════════════════════════
Write-Header "Export Complete"

$manifest = Get-ChildItem -Path $OutputDir -Filter "*.csv" | Select-Object Name,
    @{N='Rows';E={ (Import-Csv $_.FullName | Measure-Object).Count }},
    @{N='SizeKB';E={ [math]::Round($_.Length/1KB,1) }},
    LastWriteTime

$manifest | Format-Table -AutoSize
$manifest | Export-Csv "$OutputDir\00_MANIFEST.csv" -NoTypeInformation -Encoding UTF8

Write-Host "`nAll files written to: $(Resolve-Path $OutputDir)" -ForegroundColor Green
Write-Host "To review: Import-Csv '<file>.csv' | Out-GridView" -ForegroundColor Yellow
