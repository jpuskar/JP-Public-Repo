#ref: http://social.technet.microsoft.com/Forums/en-US/winserversecurity/thread/7c8ecd4f-eb2a-49f9-ae53-aad3e653d788/
#ref: http://blogs.msdn.com/b/alejacma/archive/2012/04/13/how-to-export-issued-certificates-from-a-ca-programatically-powershell.aspx
#ref for revoking: http://msdn.microsoft.com/en-us/library/windows/desktop/aa383251(v=vs.85).aspx


$gScriptName = "Revoke-DuplicateSCCMClientCerts"
$gScriptVersion = "11"
$gLogFilePath = "\\winfs\logs\scripts\"



#Functions from Common-Functions-v2.ps1
Function Trim-TrailingSlash($path)
	{
		$retval = $path.TrimEnd("\")
		Return $retval
	}


Function Write-Log($msg,$switches)
	{
		If($gLogFile -eq $null)
			{}
		Else
			{Add-Content $gLogFile $msg}
	}
	
Function write-openingBlock($allArgs)
	{
		$CS = Gwmi Win32_ComputerSystem -Comp "."
		$computer = $CS.Name
		$loggedInUser = $env:username
		$dateTime = get-date
		
		$msgs = $null
		$msgs = @()
		$msgs += $gScriptName + " " + $gScriptVersion
		$msgs += "Running on " + $dateTime + " by " + $loggedInUser + " from " + $computer
		$msgs += "Verbosity Level: " + $gVerbosityLevel
		$msgs += "Arguments: " + $AllArgs
		$msgs += "Log File: " + $gLogFile
		$msgs += ""
		$msgs += "___ STARTING WORK ___"
		$msgs += ""
		
		Foreach($msg in $msgs)
			{Write-Out $msg "white" 1}
	}
	
Function Write-Out($msg,$color,$msgVerbosity,$switches)
	{
		#$msg | out-file -append $gLogFile
		
		If($gVerbosityLevel -eq $null)
			{$gVerbosityLevel = 10}
		
		Write-Log $msg
		If($color -eq $null)
			{$color = "white"}
		If($msgVerbosity -le $gVerbosityLevel)
			{
				If($switches -eq "-nonewline")
					{Write-Host -nonewline -f $color "$msg"}
				Else{Write-Host -f $color "$msg"}
			}
	}

	
Function Throw-Warning($msg)
{Write-Out $msg "magenta" 1}

#== Main ==

#Initialize Logging
$logFilePath = $gLogFilePath
$logFilePath = Trim-TrailingSlash $logFilePath

 #NOTE: $script:logFileDateString is used by other functions which create log files,
 # so that all the files have the same datestamp. Ootherwise, without using some kind of ID#
 #(which would be the better choice), it's hard to cross-reference the main script log with
 #other logs such as robocopy, directoryFixer, etc.
$logFileName = $gScriptName + "_" + $logFileDate + ".txt"
$logPath = $logFilePath + "\" + $gScriptName + "\"
$logPathTest = Test-Path $logPath
If($logPathTest -eq  $false)
	{new-item $logPath -itemType Directory | out-null}
$logfiletest = $null
$logfiletest = $true
While ($logFileTest -eq $true)
	{
		$logFileDate = get-date -uformat '%d%m%Y-%H%M-%S'
		$logFileName = $gScriptName + "_" + $logFileDate + ".txt"
		$logFileTest = Test-Path $logFileName	
		#write-host -f yellow "debug`tlogfilename: $logfilename"
		If ($logFileTest -eq $false) 
			{break}
		Else
			{Sleep -s 1}
	}
$script:logFileDateString = $logFileDate
		
$gLogFile = $logPath + $logFileName
New-Item -ItemType file $gLogFile | out-null
$logFileDate = $null
$logFileName = $null
$logPath = $null
$logPathTest = $null

$allArgs = ""
$Args | %{
	[string]$curArg = $_
	$AllArgs += ($curArg + " ")
}
write-openingBlock $allArgs

#Params 
$strServer = "sccm-chm1"
$strCAName = "SCCM_CHM Site Server"
#$strServer = "ca1"
#$strCAName = "Test Issuing CA1"
$strPathForCerts = "C:\workingtemp\"
$strSCCMClientCertTemplateOID = "1.3.6.1.4.1.311.21.8.3858753.1941150.1526201.15537621.13786382.63.818369.8199813"
#$strSCCMClientCertTemplateOID = "1.3.6.1.4.1.311.21.8.13579606.14849176.13518728.9321214.1879859.147.12212259.10171541"

# Constants 
$CV_OUT_BASE64HEADER = 0
$CV_OUT_BINARY = 2

$msg = "ACTION`tSearching for duplicate SCCM Client Certificates on CA """ + $strServer + "\" + $strCAName + """."
write-out $msg

# Connect to the Certificate Authority
$oCAView = New-Object -ComObject CertificateAuthority.View

If($oCAView -eq $null)
	{
		$msg = "Error`tCould not connect to the CA """ + $strServer + "\" + $strCAName + """."
		Throw-Warning $msg
		Exit
	}

$oCAView.OpenConnection($strServer + "\" + $strCAName)

## Get a column count and place columns into the view 
$oCAView.SetResultColumnCount(6)
$index0 = $oCAView.GetColumnIndex($6false, "Requester Name")
$index1 = $oCAView.GetColumnIndex($false, "Certificate Expiration Date")
$index2 = $oCAView.GetColumnIndex($false, "Request ID")
$index3 = $oCAView.GetColumnIndex($false, "Certificate Template")
$index4 = $oCAView.GetColumnIndex($false, "Request Disposition")
$index5 = $oCAView.GetColumnIndex($false, "Serial Number")
$index0, $index1, $index2, $index3, $index4, $index5 | %{$oCAView.SetResultColumn($_)}

# Open the View and reset the row position 
$oRow = $oCAView.OpenView()

#Create a collection of certs
$Certs = @()

#Create Cert Object
While ($oRow.Next() -ne -1)
	{
		$Cert = New-Object PsObject
		$ColObj = $oRow.EnumCertViewColumn()
		[void]$ColObj.Next()
		do
			{
				$current = $ColObj.GetName()
				$Cert | Add-Member -MemberType NoteProperty -Name ($ColObj.GetDisplayName()) -Value ($ColObj.GetValue(1)) -Force
			}
		until ($ColObj.Next() -eq -1)
		Clear-Variable ColObj
		if(($cert."Certificate Template" -eq $strSCCMClientCertTemplateOID) -and ($cert."Request Disposition" -eq 20)) {
			$Certs += $cert
		}
	}

#Sort Certs into Buckets
$CertMap = @{}
$CertMapKeys = @()
foreach($i in $Certs) {
	if ($CertMap.ContainsKey($i."Requester Name")) {
		$arr = @()
		$arr = $CertMap.Get_Item($i."Requester Name")
		$arr += $i
		$CertMap.Set_Item($i."Requester Name",$arr)
	
	} else {
		$CertMap.Add($i."Requester Name",@($i))
		$CertMapKeys += $i."Requester Name"
	}
}


#$certMap.Get_Item("CHEMISTRY\MP0008-01$") | out-host
#SExit

#Process Buckets
#If actually removing create cert admin
if($args[0] -eq "/force") {
	$CertAdmin = New-Object -com CertificateAuthority.Admin
}

foreach($map in $CertMapKeys) {
	$proc = $false
	$arr = $null
	$arr = $CertMap.Get_Item($map)
	
	If($arr.count -gt 1) {
		$msg = "INFO`tFound " + ($arr.count) + " duplicates for system " + $map
		write-out $msg
		Foreach($cert in $Arr) {
			$bSupersede = $false
			$rid = $cert."Request ID"
			Foreach ($cert2 in $Arr) {
				If($cert2."Request ID" -gt $rid) {
					$bSupersede = $true
				}
			}
			If(!$bSupersede) {
				$msg = "INFO`t`tKeeping certificate with request ID " + $rid + ", serial number " + $cert."Serial Number"
				write-out $msg
			} Else {
				$msg = "ACTION`t`tRevoking certificate with request ID " + $rid + ", serial number " + $cert."Serial Number"
				write-out $msg
				If($args[0] -eq "/force"){
					#Revoke Certificate In 5 Minutes
					$CertAdmin.RevokeCertificate("$strServer\$strCAName",$cert."Serial Number", 4,(Get-Date).AddMinutes(5).ToUniversalTime())
					$msg = "INFO`t`tRevoke Successful."
					write-out $msg
					#Exit
				}
			}
		}
	}
}
	
$oRow.Reset()
$oCAView = $null
[GC]::Collect()

$msg = "Script Completed"
write-out $msg