- task: AzurePowerShell@5
  inputs:
    azureSubscription: 'Your-Service-Connection'
    ScriptType: 'InlineScript'
    Inline: |
      $resourceGroup = "rg-your-vm"
      $vmName = "your-vm-name"
      $scriptPath = "C:\path\to\grafana-agent.ps1"

      Invoke-AzVMRunCommand -ResourceGroupName $resourceGroup `
                            -Name $vmName `
                            -CommandId 'RunPowerShellScript' `
                            -ScriptPath $scriptPath
    azurePowerShellVersion: 'LatestVersion'
