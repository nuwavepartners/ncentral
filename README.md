# N-Central Scripts

## Install-NCentralAgent.ps1

```powershell
& ([scriptblock]::Create((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/nuwavepartners/ncentral/main/Install-NCentralAgent.ps1'))) -Server 'rmm.example.net' -CustomerId {code} -RegistrationToken '{guid}' -AgentVersion '2024.1.2.3'
```