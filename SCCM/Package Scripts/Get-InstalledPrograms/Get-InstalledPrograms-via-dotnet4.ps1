#reads 64bit and 32bit reg keys on 64-bit systems
#this script requires .NET 4.0
#http://stackoverflow.com/questions/630382/how-to-access-the-64-bit-registry-from-a-32-bit-powershell-instance

$CLRVer = $null
$CLRVer = [environment]::Version
If($CLRVer.Major -lt 4) {
	Write-Host -f red "This script requires .Net CLR 4 or above. Please install WMF 3+"
	Exit
}

$regStrings = $null
$regStrings = @()
$regStrings += "SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
$regStrings += "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"

$hive = $null
$hive = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)

$progs = $null
$progs = @()

$regStrings | % {
	$rootKey = $null
	$rootKey = $hive.OpenSubKey($_)
	
	If($rootKey -ne $null -and $rootKey -ne "") {
		$subKeyList = $null
		$subKeyList = $rootKey.GetSubkeyNames()
		
		$subKeyList | % {
			$subkey = $null
			$subkey = $RootKey.OpenSubKey($_, $false)
			
			$displayName = $null
			$displayName = $subkey.GetValue("DisplayName")
			
			If($displayName -ne $null -and $displayName -ne "") {
				$uninstallString = $null
				$uninstallString = $subkey.GetValue("UninstallString")
				
				$quietUninstallString = $null
				$quietUninstallString = $subkey.GetValue("QuietUninstallString")
				
				$displayVersion = $null
				$displayVersion = $subkey.GetValue("DisplayVersion")
				
				$progs += New-Object psObject -Property @{
					"DisplayName" = $displayName;
					"DisplayVersion" = $displayVersion;
					"UninstallString" = $uninstallString;
					"QuietUninstallString" = $quietUninstallString
				} #progs object
			} #grabs progs properties
		} #subkeyList
	} #rootKey
} #keys to search

$progs