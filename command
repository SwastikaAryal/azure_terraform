Get-ChildItem -Path "C:\" -Recurse -Filter "libssl-3-x64.dll" -ErrorAction SilentlyContinue | ForEach-Object {
    $raw   = $_.VersionInfo.FileVersion -replace ',','.' -replace '\s',''
    $parts = $raw.Split('.')
    $ver   = [System.Version]"$($parts[0]).$($parts[1]).$($parts[2])"
    $status = if ($ver -ge [System.Version]"3.5.5") {"SAFE - PATCHED"} 
              elseif ($ver -ge [System.Version]"3.5.0") {"VULNERABLE"}
              else {"NOT IN RANGE"}
    [PSCustomObject]@{
        Version    = $ver
        Status     = $status
        LastWrite  = $_.LastWriteTime
        Path       = $_.FullName
    }
} | Sort-Object Version -Descending | Format-Table -AutoSize
