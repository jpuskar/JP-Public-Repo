Readme File For Get-TS.ps1

INSTALLATION:

The script will be installed on sccm-chm1

GitHub should be configured with the repository for Task Sequences set to - C:\GitHub\ASC-SCCM-Private

The folder C:\logs\Get-TSeInfo\ must be created to store the logfiles.

Get-TSInfo.ps1 should be stored at C:\Scripts\Get-TSInfo\
C:\Scripts\Get-TSInfo\ must contain a text file called GitPassword.txt which contains a single line which is the password for the Git Account ASC-SCCM-Robot

service-sccmgithub must have permissions to query sccm

git (command line) must be installed on sccm-chm1 and set up so that powershell can use its commands

A scheduled task should be set up to execute Get-TSInfo.ps1 daily at 4:00am, running from Chemistry\service-sccmgithub


PREREQUISITES:
The repository github.com/ASCTech/ASC-SCCM-Private.git must exist
ASC-SCCM-Robot must have permissions to push to that repository

TROUBLESHOOTING:
Log Files Are Stored at C:\Logs\Get-TSInfo
Driver Package csv files will be stored in C:\GitHub\ASC-SCCM-Private\TaskSequences
GitHub for Windows can be configured to confirm commits and syncs to GitHub are working properly if the driver package downloads are working correctly.
