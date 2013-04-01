REM Install and Configure DFSR for IIS Content Repl
Powershell -executionpolicy bypass -command "Import-Module ServerManager; Add-WindowsFeature File-Services,FS-DFS,FS-DFS-Replication"
dfsradmin RG New /rgname:"CDP Replication Group"
dfsrAdmin RG Set Schedule full /RGName:"CDP Replication Group"
dfsradmin member new /rgname:"CDP Replication Group" /memname:%computername%
dfsradmin RF New /rgName:"CDP Replication Group" /RfName:CertData
dfsradmin Membership Set /RgName:"CDP Replication Group" /RfName:CertData /MemName:%computername% /LocalPath:F:\inetpub\wwwroot\CertData /MembershipEnabled:true /IsPrimary:true

REM Set staging directory
IF NOT EXIST "G:\DFSR" MKDIR "G:\DFSR"
IF NOT EXIST "G:\DFSR\Staging" MKDIR "G:\DFSR\Staging"
IF NOT EXIST "G:\DFSR\Staging\CertData" MKDIR "G:\DFSR\Staging\CertData"
Powershell -ExecutionPolicy bypass -file ".\Change-DFSRStaging.ps1"
IF EXIST "F:\inetpub\wwwroot\certdata\dfsrPrivate\staging" RMDIR /s /q "F:\inetpub\wwwroot\certdata\dfsrPrivate\staging"