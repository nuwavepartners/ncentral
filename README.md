# N-Central Scripts

## Install-NCentralAgent.ps1

```powershell
& ([scriptblock]::Create((New-Object System.Net.WebClient).DownloadString('https://nuwave.link/rmm/Install-NCentralAgent.ps1'))) -CustomerId {code} -RegistrationToken '{guid}'
```