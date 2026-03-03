.\JoinStorageAccount.ps1 `
    -StorageAccountName "mystorageacct01" `
    -StorageAccountResourceGroup "myResourceGroup" `
    -DomainName "corp.local" `
    -DomainUser "CORP\svc-storage" `
    -DomainPassword (ConvertTo-SecureString "MySecretPassword123!" -AsPlainText -Force) `
    -DomainAccountType "ComputerAccount" `
    -OrganizationalUnitName "OU=StorageAccounts,DC=corp,DC=local"
