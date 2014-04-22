#Reads 64bit and 32bit uninstall reg keys on 64-bit systems
#returns object with displayname, displayversion, uninstallstring, and quietuninstallstring
#uses WMI StdRegProv. It's kinda slow.
#.net is faster but the required classes are only included in .net 4 which requires powershell 4+

$regStrings = $null
$regStrings = @()
$regStrings += "SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
$regStrings += "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"

#ref: http://msdn.microsoft.com/en-us/library/aa390788(v=vs.85).aspx
#$HKEY_CLASSES_ROOT = 2147483648
#$HKEY_CURRENT_USER = 2147483649
$HKEY_LOCAL_MACHINE = 2147483650
#$HKEY_USERS = 2147483651
#$HKEY_CURRENT_CONFIG = 2147483653

$regProv = $null
$regProv = [wmiclass]"root\default:StdRegProv"

$progs = $null
$progs = @()

$regStrings | % {
	$rootKeyPath = $null
	$rootKeyPath = $_
	$rootKey = $null
	$rootKey = $regProv.EnumKey($HKEY_LOCAL_MACHINE,$rootKeyPath)
	
	If($rootKey -ne $null -and $rootKey -ne "") {
		$subKeyList = $null
		$subKeyList = $rootKey.sNames
		
		$subKeyList | % {
			$subKeyPath = $null
			[string]$subKeyPath = $rootKeyPath.TrimEnd("\") + "\" + $_
			$subkey = $null
			$subkey = $regProv.EnumValues($hklm, $subKeyPath)
			
			$subKeyVals = $null
			$subKeyVals = $subKey.sNames
			
			If($subKeyVals -like "*DisplayName*") {
			
				$displayNameObj = $null
				$displayNameObj = $regProv.GetStringValue($hklm, $subKeyPath, "DisplayName")
				
				
				$displayNameVal = $null
				$displayNameVal = $displayNameObj.sValue
				
				If($displayNameVal -ne $null -and $displayNameVal -ne "") {
					#get UninstallString
					$uninstallString = $null
					$uninstallString = $regProv.GetStringValue($hklm, $subKeyPath, "UninstallString")
					$uninstallStringVal = $null
					If($uninstallString -ne $null -and $uninstallString -ne "")
						{$uninstallStringVal = $uninstallString.sValue}
					
					#get QuietUninstallString
					$quietUninstallString = $null
					$quietUninstallString = $regProv.GetStringValue($hklm, $subKeyPath, "QuietUninstallString")
					$quietUninstallStringVal = $null
					If($quietUninstallString -ne $null -and $quietUninstallString -ne "")
						{$quietUninstallStringVal = $quietUninstallString.sValue}
					
					#get DisplayVersion
					$displayVersion = $null
					$displayVersion = $regProv.GetStringValue($hklm, $subKeyPath, "DisplayVersion")
					$displayVersionVal = $null
					If($displayVersion -ne $null -and $displayVersion -ne "")
						{$displayVersionVal = $displayVersion.sValue}
					
					$progs += New-Object psObject -Property @{
						"DisplayName" = $displayNameVal;
						"DisplayVersion" = $displayVersionVal;
						"UninstallString" = $uninstallStringVal;
						"QuietUninstallString" = $quietUninstallStringVal
					} #fill progs object
				} #displayName not null
			} #displayName Exists
		} #subkey list
	} #rootKey not null
} #regStrings

return $progs