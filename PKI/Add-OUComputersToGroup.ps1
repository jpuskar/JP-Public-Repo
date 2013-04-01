#This script searches for computer objects in and below the specified OU, then adds them to the specified group.
$rootOU = "DC=chemistry,DC=ohio-state,DC=edu"
$tgtGroupCN = "COMP_ChemistryWorkstations"
$gLogFile = $null

$gScriptName = "Add-OUComputersToGroup"
$gScriptVersion = "5"
#You need to make sure that the share and NTFS permissions on the target allow writing and appending
# from whatever account is running the script. If this is a startup script, then you need to grant
# permissions to the computer's domain account.
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


Function Pull-LDAPAttribute($objUser,$attribute)
	{
		trap{continue;}
		$objUserDN = $null
		$objUserDN = $objUser.Get("distinguishedName")
		$objUser = $null
		$objUser = [adsi]("LDAP://" + $objUserDN)
		$value = $null
		$value = $objUser.Get($attribute)
		If($value -eq "" -or $value -eq $null)
			{Return $null}
		Else
			{Return $value}
	}

Function Check-DNExists($dn)
	{
		#grab all grops with GID's
		$searchRoot = [ADSI]''
		$searcher = new-object System.DirectoryServices.DirectorySearcher($searchRoot)
		$searcher.filter = "(&(objectClass=*)(distinguishedName=" + $dn + "))"
		$searchResults = $searcher.findall()
		
		If($searchResults.count -lt 1)
			{$results = $false}
		Else
			{$results = $true}
		
		$searchResults.Dispose()
		$searcher.Dispose()
		$searchResults = $null
		$searcher = $null
		
		Return $results
	}

Function Get-DNbyCN($CN,$objectCategory)
	{
		$results = $null
		$root = [ADSI]''
		$searcher = new-object System.DirectoryServices.DirectorySearcher($root)
		Switch($objectCategory)
			{
				"group"
					{$searcher.filter = "(&(objectClass=group)(cn=" + $CN + "))"}
				"user"
					{$searcher.filter = "(&(objectClass=user)(cn=" + $CN + "))"}
				Default
					{$searcher.filter = "(&(|(objectClass=user)(objectClass=group))(cn=" + $CN + "))"}
			}
		
		$searchResults = $searcher.findall()
		
		If($searchResults.count -gt 0)
			{    
				$groupDN = $searchResults[0].path
				$groupDN = $groupDN.Substring(7)
				$results = $groupDN
			}
		Else
			{
				$results = $false
			}
		
		$searchResults.Dispose()
		$searcher.Dispose()
		$searchResults = $null
		$searcher = $null
		$root = $null
		
		Return $results
	}

Function Check-IsMemberOfGroup($strSourceDN,$strGroupDN)
	{
		$results = $null
		$results = $false
		$fail = $null
		$fail = $false
		
		$blnSourceExists = Check-DNExists $strSourceDN
		If($blnSourceExists -eq $false)
			{
				$results = $false
				$fail = $true
			}
		
		$blnGroupExists = Check-DNExists $strGroupDN
		If($blnSourceExists -eq $false)
			{
				$results = $false
				$fail = $true
			}
			
		If($fail -eq $false)
			{
				$ldapFilter = $null
				$ldapFilter = "(&(objectCategory=group)(member=" + $strSourceDN + "))"
				#write-host -f yellow "check-ismemberofgroup - ldapfilter: $ldapFilter"
				
				$strGroupDN = $strGroupDN.substring(3)
				# THIS CODE TOTALLY WORKS!!!
				$searchRoot = [ADSI]''
				$searcher = New-Object System.DirectoryServices.DirectorySearcher($searchRoot)
				$searcher.Filter = $ldapFilter
				$searcher.PageSize = 1000
				$searchResults = $null
				$searchResults = $searcher.FindAll()
				Foreach($result in $searchResults)
					{
						$resultDN = ($result.path).substring(10)
						If($resultDN -eq $strGroupDN)
							{
								$results = $true
								Break
							}
					}
				
				$searchResults.Dispose()
				$searcher.Dispose()
				$searchResults = $null
				$searcher = $null
				$adsGroupPath = $null
				$domainSuffix = $null
				$strGroupDN = $null
			}
		
		Return $results
	}

Function Add-ToGroup($sourceDN, $groupDN)
	{
		$results = $null
		#Bind to the group
		
		If($groupDN -eq $false)
			{
				$warningMsg = "ERROR`tCannot add object to group; Group DNE: """ + $groupDN + """."
				Throw-Warning $warningMsg
				$failFunction = $true
			}
		Else
			{
				$objGroup = [adsi]("LDAP://" + $groupDN)
				$OC = Pull-LDAPAttribute $objGroup "objectCategory"
				#write-host -f yellow $OC
				If($OC -notlike "*group*")
					{
						$msg = "ERROR`t`tThe group specified is not actually a group!"
						Throw-Warning $msg
						$results = $false
					}
				Else
					{
						#Check to see if the user is already a member of the group
						$objGroupMember = Pull-LDAPAttribute $objGroup "member"
						$objSourceADObject = [adsi]("LDAP://" + $sourceDN)
						$objSourceMemberOf = Pull-LDAPAttribute $objSourceADObject "memberOf"
						If($objGroupMember -contains $sourceDN)
							{$results = $true}
						ElseIf($objSourceMemberOf -contains $groupDN)
							{$results = $true}
						Else
							{
								#Add the user to the group
								#write-host -f yellow "source dn: $sourceDN"
								$objGroup.Add(("LDAP://" + $sourceDN)) | Out-Null
								$objGroup.SetInfo()
								#Check to see if it worked
								$objGroupMember = Pull-LDAPAttribute $objGroup "member"
								$objSourceMemberOf = Pull-LDAPAttribute $objSourceADObject "memberOf"
								If($objGroupMember -contains $sourceDN)
									{$results = $true}
								ElseIf($objSourceMemberOf -contains $groupDN)
									{$results = $true}
								Else
									{$results = $false}
							}
					}
			}
		
		If($results -eq $null)
			{$results = $false}
		
		Return $results
	}

# = Main =
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

#actually create the log file
$gLogFile = $logPath + $logFileName
New-Item -ItemType file $gLogFile | out-null
If((Test-Path $gLogFile) -eq $false)
	{
		$msg = "Error`tCould not open log file at """ + $gLogFile + """."
		Throw-Warning $msg
		Exit
	}
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

$fail = $false
$tgtGroupDN = Get-DNbyCN $tgtGroupCN
If($tgtGroupDN -eq $false)
	{
		$msg = "Error`tTarget group """ + $tgtGroupCN + """ does not exist in the directory."
		Throw-Warning $msg
		$fail = $true
	}

$bTgtDNOK = Check-DNExists $rootOU
If($bTgtDNOK -eq $false)
	{
		$msg = "Error`tTarget Root OU """ + $rootOU + """ does not exist in the directory."
		Throw-Warning $msg
		$fail = $true
	}

If($fail -eq $false)
	{
		$msg = "Searching the OU: """ + $rootOU + """ and adding computers to the """ + $tgtGroupCN + """ group."
		Write-Out $msg
		$DN = $null
		$searcher = new-object System.DirectoryServices.DirectorySearcher
		$searcher.SearchRoot = ("LDAP://" + $rootOU)
		$searcher.Filter = "objectClass=computer"
		$searchResults = $searcher.findall()
		$searchResults | % {
			$computerDN = $_.properties.distinguishedname
			$computerName = $_.properties.name
			#Write-Host -f green "computer's DN: $computerDN"
			#check is member of group
			If((Check-IsMemberOfGroup $computerDN $tgtGroupDN) -ne $true)
				{
					$msg = "Action`tAdding computer """ + $computerName + """ to the group """ + $tgtGroupCN + """."
					Write-Out $msg
					$action = Add-ToGroup $computerDN $tgtGroupDN
					If($action -ne $true)
						{
							$msg = "Error`t`tCould not add """ + $computerDN + """ to the group " + $tgtGroupDN + """."
							Throw-Warning $msg
						}
					Else
						{
							$msg = "Info`t`tComputer added successfully."
							Write-Out $msg
						}
				}
		}
	}