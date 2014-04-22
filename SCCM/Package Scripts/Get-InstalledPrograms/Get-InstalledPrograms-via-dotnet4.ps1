$hive64 = $null
$hive64 = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
$rootKey64 = $null
$rootKey64 = $hive64.OpenSubKey("SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall")
$subKeyList64 = $null
$subKeyList64 = $rootKey64.GetSubkeyNames()

$progs = $null
$progs = @()

$subKeyList64 | % {
	$subkey = $null
	$subkey = $RootKey64.OpenSubKey($_, $false)
	
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
		}
	}
}

#$progs | sort displayName | format-table -property displayname,displayversion,uninstallstring,quietuninstallstring