#ref: http://social.technet.microsoft.com/Forums/en-US/winserversecurity/thread/7c8ecd4f-eb2a-49f9-ae53-aad3e653d788/
#ref: http://blogs.msdn.com/b/alejacma/archive/2012/04/13/how-to-export-issued-certificates-from-a-ca-programatically-powershell.aspx

#ref for revoking: http://msdn.microsoft.com/en-us/library/windows/desktop/aa383251(v=vs.85).aspx

#Functions from Common-Functions-v2.ps1
Function Write-Log($msg,$switches)
	{
		If($gLogFile -eq $null)
			{}
		Else
			{Add-Content $gLogFile $msg}
	}
	
Function write-openingBlock
	{
		$CS = Gwmi Win32_ComputerSystem -Comp "."
		$computer = $CS.Name
		#$loggedInUser = $CS.UserName
		$loggedInUser = $env:username
		$dateTime = get-date
		
		$switches = ""
		If($gArrArguments -ne $null)
			{
				$i = 1
				Foreach($argument in $gArrArguments)
					{
						$switches = $switches + $argument
						If($i -lt $gArrArguments.count)
							{$switches = $switches + ", "}
						Else
							{}
						$i++
					}
			}
		$msgs = $null
		$msgs = @()
		$msgs += $gScriptName + " " + $gScriptVersion
		$msgs += "Running on " + $dateTime + " by " + $loggedInUser + " from " + $computer
		$msgs += "Verbosity Level: " + $gVerbosityLevel
		$msgs += "Arguments: " + $allArgs
		$msgs += "Switches: " + $switches
		$msgs += "Log File: " + $gLogFile
		$msgs += ""
		$msgs += "___ STARTING WORK ___"
		$msgs += ""
		
		Foreach($msg in $msgs)
			{Write-Out $msg "white" 1}
	}
	
Function Throw-Warning($msg)
{Write-Out $msg "magenta" 1}

#Params 
$strServer = "sccm-chm1"
$strCAName = "SCCM_CHM Site Server"
$strPathForCerts = "C:\workingtemp\"

# Constants 
$CV_OUT_BASE64HEADER = 0
$CV_OUT_BINARY = 2

# Connect to the Certificate Authority
$oCAView = New-Object -ComObject CertificateAuthority.View
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

While ($oRow.Next() -ne -1)
	{
		$Cert = New-Object PsObject
		$ColObj = $oRow.EnumCertViewColumn()
		[void]$ColObj.Next()
		do
			{
				$current = $ColObj.GetName()
				$Cert | Add-Member -MemberType NoteProperty $($ColObj.GetDisplayName()) -Value $($ColObj.GetValue(1)) -Force
			}
		until ($ColObj.Next() -eq -1)
		Clear-Variable ColObj
		$cert
	}

$oRow.Reset()
$oCAView = $null
[GC]::Collect()