#FEATURE REQUETS AND CHANGES!
#Anything interacting with AD need Trap{}'ed
#Linux tests - UID with no GID and vice versa, and 6-Digit+ UID's.
#when running CLI do not display row numbers

###NOTES
##to add a check:
##build-actionset

[GC]::Collect()
$error.clear()


Write-Host ""
Write-Host ""
Write-Host ""

$gScriptName = "Archive-User-v3.ps1"
$gScriptVersion = "032"

. .\Common-Functions-v2.ps1
. .\PSMod-FSFunctions-v1.ps1
. .\Archive-Users-Settings.ps1
. .\Create-Accounts-Settings.ps1

#Load Snap-Ins
#references: http://mcpmag.com/articles/2009/05/19/snapins-on-standby.aspx
$snapin="Quest.ActiveRoles.ADManagement"
if(get-pssnapin $snapin -ea "silentlycontinue")
	{}
elseif(get-pssnapin $snapin -registered -ea "silentlycontinue")
	{Add-PSSnapin $snapin}
else
	{
		Write-Host "PSSnapin $snapin not found" -foregroundcolor Red
		Exit
	}

#argument information
$gArgumentDependents = @{}
$gArgumentDependents.Add("/file","1")
$gArgumentDependents.Add("/user","1")
$gArgumentDependents.Add("/group","1")
$gArgumentDependents.Add("/folder","1")
$gArgumentDependents.Add("/allusers","0")
$gArgumentDependents.Add("/startnumber","1")
$gArgumentDependents.Add("/limit","1")
$gArgumentDependents.Add("/eval","0")
$gArgumentDependents.Add("/mark","0")
$gArgumentDependents.Add("/archive","0")
$gArgumentDependents.Add("/delete","0")
$gArgumentDependents.Add("/verbose","0")

$gValidSwitches = @()
$gValidSwitches += "/mark"
$gValidSwitches += "/scan"
$gValidSwitches += "/archive"
$gValidSwitches += "/delete"
$gValidSwitches += "/file"
$gValidSwitches += "/user"
$gValidSwitches += "/group"
$gValidSwitches += "/folder"
$gValidSwitches += "/allusers"
$gValidSwitches += "/startnumber"
$gValidSwitches += "/limit"
$gValidSwitches += "/eval"
$gValidSwitches += "/verbose"

$global:arrCoreArguments = @()
$global:arrCoreArguments += "/mark"
$global:arrCoreArguments += "/archive"
$global:arrCoreArguments += "/delete"
$global:arrCoreArguments += "/scan"

$global:arrInputArguments = @()
$global:arrInputArguments += "/file"
$global:arrInputArguments += "/folder"
$global:arrInputArguments += "/group"
$global:arrInputArguments += "/user"
$global:arrInputArguments += "/allusers"

$global:arrControlArguments = @()
$global:arrControlArguments += "/limit"
$global:arrControlArguments += "/startnumber"
$global:arrControlArguments += "/eval"
$global:arrControlArguments += "/verbose"

$global:arrValidFileExtensions = @()
$global:arrValidFileExtensions += "xlsx"
$global:arrValidFileExtensions += "csv"

###global vars### -- all read from (f)read-variable in the common-functions module as of now

#Initialize Logging
$logFilePath = Read-Variable "logFilePath"
$logFilePath = Trim-TrailingSlash $logFilePath
$logFileDate = get-date -uformat '%d%m%Y-%H%M-%S'
$global:logFileDateString = $logFileDate
 #NOTE: $global:logFileDateString is used by other functions which create log files,
 # so that all the files have the same datestamp. Ootherwise, without using some kind of ID#
 #(which would be the better choice), it's hard to cross-reference the main script log with
 #other logs such as robocopy, directoryFixer, etc.
$logFileName = $gScriptName + "_" + $logFileDate + ".txt"
$logPath = $logFilePath + "\" + $gScriptName + "\"
$logPathTest = Test-Path $logPath
If($logPathTest -eq  $false)
	{new-item $logPath -itemType Directory | out-null}
$gLogFile = $logPath + $logFileName
New-Item -ItemType file $gLogFile | out-null
$logFileDate = $null
$logFileName = $null
$logPath = $null
$logPathTest = $null



#### Common Functions

function write-usageInfo
	{
		$msgs = @()
		$msgs += ""
		$msgs += "Usage:"
		$msgs += $gScriptName + " (/MARK, /ARCHIVE, /DELETE, /SCAN)"
		$msgs += "`t(/FILE | /USER | /GROUP | /FOLDER | /ALLUSERS) <filename, username, groupname, or folder>"
		$msgs += "`t[/VERBOSE | /STARTNUMBER <###> | /LIMIT <###> | /EVAL]"
		$msgs += ""
		$msgs += "`t/MARK"
		$msgs += "`t*Validates users for archival, and puts them in the ""Ready to Archive from Windows"" group."
		$msgs += ""
		$msgs += "`t/ARCHIVE"
		$msgs += "`t*Archives the specified user(s) and puts them in the ""Ready to Archive from Linux"" group."
		$msgs += ""
		$msgs += "`t/DELETE"
		$msgs += "`t*Deletes the account(s). Must be members of the ""Ready to Delete"" group."
		$msgs += ""
		$msgs += "`t/SCAN"
		$msgs += "`t*Scans the account(s) to check if accounts that should expire, do actually expire."
		$msgs += ""
		$msgs += "`t/FILE"
		$msgs += "`t*Opens a CSV or XLSX file for processing."
		$msgs += "`t*CSV must have headers as first row."
		$msgs += "`t*XLSX must be a specific template."
		$msgs += ""
		$msgs += "`t/USER"
		$msgs += "`t*Processes an existing user."
		$msgs += ""
		$msgs += "`t/GROUP"
		$msgs += "`t*Processes all users in a group."
		$msgs += ""
		$msgs += "`t/FOLDER"
		$msgs += "`t*Works through all subfolders in a given folder, treating each subfolder as a username."
		$msgs += ""
		$msgs += "`t/ALLUSERS"
		$msgs += "`t*Works through all users in the domain."
		$msgs += ""
		$msgs += "`t/VERBOSE"
		$msgs += "`t*Writes all logging information to the screen."
		$msgs += ""
		$msgs += "`t/STARTNUMBER"
		$msgs += "`t*Begins processing at the specified object number."
		$msgs += ""
		$msgs += "`t/LIMIT"
		$msgs += "`t*Ends processing a file at the specified object number."
		$msgs += ""
		
		Foreach($msg in $msgs)
			{write-out $msg "white" 1}
	}



#### Unique Functions


Function Open-File($filename,$strFileType,$intStartNumber,$intLimit) #ECC
	{
		$failFunction = $false
		#open file according to its type
		Switch($strFileType)
			{
				"csv" {$objFile = OpenCSV $filename}
				"xlsx"
					{$objFile = OpenXLSXasCSV $filename $intStartNumber $intLimit}
				default
					{
						$failFunction = $true
						$warningMsg = "ERROR`tFiletype not CSV or XLSX."
						Throw-Warning $warningMsg
					}
			}
		
		#If we didn't open the file
		If($objFile -eq $false -or $objFile -eq $null)
			{
				$failFunction = $true
				Throw-Warning "ERROR`tProblem opening file."
			}
		
		#If there was some other problem
		If($failFunction -eq $false)
			{return $objFile}
		Else
			{return $false}
	}

Function OpenCSV($filename)
	{
		#$warningMsg = "CSV support is still experimental."
		$failFunction = $false
		$msg = "Opening CSV file: " + $filename
		Write-Out $msg "white" 2
		
		#open the file if the path test is okay.
		$pathtest = Test-Path $filename
		If($pathtest -eq $true)
			{
				$objCSV = Get-Content $filename
			}
		Else
			{
				$failFunction = $true
				$warningMsg = "ERROR`tfile doesn't exist or isn't accessible: " + $filename
				Throw-Warning $warningMsg
			}
			
		If($failFunction -eq $false)
			{return $objCSV}
		Else
			{return $false}
	}

Function OpenXLSXasCSV($filename,$intStartNumber,$intLimit) #ECC
	{
		$error.clear()
		trap
			{
				#log the error
				$warningMsg = "ERROR`tPowerShell threw an exception. More info should follow this line."
				Throw-Warning $warningMsg
				$warningMsg = "ERROR`tThis probably means that Excel is not installed on this system."
				Throw-Warning $warningMsg
				Foreach($errorLine in $error)
					{
						$warningMsg = $errorLine
						Throw-Warning $warningMsg
					}
				Return $false
			}
		
		$failFunction = $false
		
		#open the file if the path tests as okay.
		$pathtest = Test-Path $filename
		If($pathTest -eq $true)
			{
				$xlCSV = 6
				$xlsFile = get-item $filename
				$xls = $filename
				
				#get the file name's path
				$csvFilePath = $xlsFile.fullname.substring(0,($xlsFile.fullname.length - $xlsFile.name.length - 1))
				
				#create a new filename that's filename + mmddyy + mmss.csv
				$csvFileName = "tempCSVFile-" + $global:logFileDateString + ".csv"
				
				#stitch it together
				$csv = $csvFilePath + $csvFileName
				
				#open the XLSX and save worksheet 2 as CSV
				$msg = "ACTION`tRunning Excel."
				Write-Out $msg
				$xl = New-Object -com "Excel.Application"
				$xl.displayalerts = $false
				$wb = $xl.workbooks.open($xls)
				$ws2 = $wb.Worksheets.Item(2)
				$msg = "ACTION`tSaving Excel file as CSV."
				Write-Out $msg
				$action = $ws2.SaveAs($csv,$xlCSV)
				$msg = "ACTION`tClosing Excel."
				Write-Out $msg
				$action = release-ref $ws2
				$wb.Close($false)
				$action = release-ref $wb
				$xl.Quit()
				$action = release-ref $xl
				$ws2 = $null
				$wb = $null
				$xl = $null
				
				[GC]::Collect()
				
				#import worksheet 2 as CSV to an array
				$msg = "ACTION`tCaching CSV File."
				Write-Out $msg
				$objCachedFile = Get-Content $csv
				
				#delete the CSV
				$msg = "ACTION`tRemoving the temporary CSV file:."
				#Write-host -f yellow $csv
				Write-Out $msg
				Remove-Item $csv -force
			}
		Else
			{
				$failFunction = $true
				$warningMsg = "Cannot find the file: " + $filename
				Throw-Warning $warningMsg
			}
		
		If($failFunction -eq $false)
			{return $objCachedFile}
		Else
			{return $false}
	}

Function CloseXLSX($filename)
	{
		$global:excel.Workbooks.Close($filename)
		$global:excel = $null
	}

Function Find-UserInfo($strInputMode,$strInputModeDependent,$intUserNumber) #ECC
	{
		$failFunction = $false
		$failThisFunction = $false
		$hshUserInfo = $null
		$hshUserInfo = $false
		#Pull user info from the respective file handler
		
		Switch($strInputMode)
			{
				"/file"
					{
						$hshProposedUserInfo = Pull-UserFromCSV $strInputModeDependent $intUserNumber
					}
				"/user"
					{
						If($intUserNumber -gt 1)
							{$hshUserInfo = $false}
						Else
							{
								$sAMAccountName = $strInputModeDependent
								$hshProposedUserInfo = Populate-TableFromsAMAccountName $sAMAccountName
								#$hshUserInfo | out-host
							}
							#write-host -f yellow "DEBUG!`tsAMaccountName: $sAMAccountName`nDEBUG!`tintUserNumber: $intUserNumber"	
					}
				"/group"
					{
						$hshProposedUserInfo = Pull-UserFromUsernamesArray $strInputModeDependent $intUserNumber
					}
				"/folder"
					{
						$hshProposedUserInfo = Pull-UserFromUsernamesArray $strInputModeDependent $intUserNumber
					}
				"/allusers"
					{
						$hshProposedUserInfo = Pull-UserFromUsernamesArray $strInputModeDependent $intUserNumber
					}
				
			}
		
		#is the user the current script user?
		
		#Error Checking
		If($hshProposedUserInfo -eq $false -or $hshProposedUserInfo -eq $null)
			{$failThisFunction = $true}
		
#		If($failThisFunction -eq $false -and $failFunction -eq $false)
#			{$hshProcessedUserInfo = Process-UserInfo $hshProposedUserInfo}
		$hshProcessedUserInfo = $hshProposedUserInfo
		
		If($failThisFunction -eq $true -or $failFunction -eq $true)
			{$retval = $false}
		Else
			{$retval = $hshProcessedUserInfo}
				
		Return $retval
	}

Function Populate-TableFromsAMAccountName($sAMAccountName)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		
		If($sAMAccountName -eq $null -or $sAMAccountName -eq "")
			{
				$failThisFunction = $true
			}
		Else
			{
				$objUserDN = $null
				$objUserDN = Get-DNbySAMAccountName $sAMAccountName "user"
				#write-host -f yellow "DEBUG`tobjUserDN: $objUserDN"
				$objUser = $null
				$objUser = [adsi]("LDAP://" + $objUserDN)
				$hshUserInfo = $null
				$hshUserInfo = @{}
				$requiredAttributesForProcessing = $null
				$requiredAttributesForProcessing = Read-Variable "requiredAttributesForProcessing"
				Foreach($attribute in $requiredAttributesForProcessing)
					{
						$attributeValue = $null
						$attributeValue = Pull-LDAPAttribute $objUser $attribute
						If($attributeValue -eq $false -or $attributeValue -eq $null)
							{
								$warningMsg = "ERROR`tCould not read required attribute: """ + $attribute + """ from user """ + $sAMAccountName + """."
								Throw-Warning $warningMsg
								write-host -f white "DNG DING DING"
								$failThisFunction = $true
							}
						Else
							{
								#write-host -f yellow "DEBUG!`tAdding $attribute \ $attributeValue"
								$hshUserInfo.Add($attribute,$attributeValue)	
							}
					}
			}
		
		If($failThisFunction -eq $true)
			{Return $false}
		Else
			{Return $hshUserInfo}
	}

Function Pull-UserFromCSV($objFile,$intUserNumber)
	{
		#$intRowNumber = $intUserNumber + 1 ## no longer needed. You can't specify "/startnumber 0"
		$intRowNumber = $intUserNumber
		$endOfFile = $false
		$objFileRowCount = $objFile.Count
		If($intRowNumber -ge $objFileRowCount)
			{$endOfFile = $true}
		Else
			{
				$headers = Parse-CSVStringToArray $objFile[0]
				$userRowData = Parse-CSVStringToArray $objFile[$intRowNumber]
				$hshUserInfo = $null
				$hshUserInfo = @{}
				$i = 0
				Foreach($header in $headers)
					{
						$value = $userRowData[$i]
						If($value -ne $null -and $value -ne "")
							{
								$hshUserInfo.Add($header,$value)
							}
						Else
							{}
						$i++
					}
			}
		
		If($endOfFile -eq $true)
			{$retval = $false}
		Else
			{
				$strType = $hshUserInfo.GetType()
				If($strType -notlike "*hashtable*")
					{$endOfFile = $true}
				Else
					{
						$sAMAccountName = $null
						$sAMAccountName = $hshUserInfo.Get_Item("sAMAccountName")
						If($sAMAccountName -eq $null -or $sAMAccountName -eq "")
							{$endOfFile = $true}
					}
			}
		
		If($hshUserInfo -eq $false)
			{}
		Else
			{$hshUserInfo.Add("profilePath","placeholder")}
		
		If($endOfFile -eq $true)
			{$results = $false}
		Else
			{$results = $hshUserInfo}
		
		Return $results
	}

Function Pull-UserFromXLSX($objFile,$intUserNumber) #SkipECC
	{
		#$intRowNumber = $intUserNumber + 1
		#bind to worksheets
		$worksheet_one = $objFile.Worksheets.Item(1)
		$worksheet_two = $objFile.Worksheets.Item(2)
		
		#Init header table
		$range = $worksheet_two.UsedRange
		
		#Read header from worksheet
		$headers = $null
		$headers = @()
		$intHeaderRowNumber = 1
		$i = 1
		While($cell -ne "")
			{
				$cell = $worksheet_two.cells.item($intHeaderRowNumber,$i).Text
				If($cell -ne "")
					{$headers += $cell}
				$i++
			}
		
		#Read user info
		$intUserRowNumber = $intUserNumber + $intHeaderRowNumber
		$intNumOfHeaders = $headers.length
		$hshUserInfo = $null
		$hshUserInfo = @{}
		
		$i = 0
		foreach($header in $headers)
			{
				$column = $i + 1
				$cell = $worksheet_two.cells.item($intUserRowNumber,$column).Text
				$hshUserInfo.add($headers[$i],$cell)
				$i++
			}
		
		$sAMAccountName = $hshUserInfo.Get_Item("sAMAccountName")
		If($sAMAccountName -eq "#VALUE!")
			{$hshUserInfo = $false}
		ElseIf($sAMAccountName -eq $null)
			{$hshUserInfo = $false}	
		ElseIf($sAMAccountName -eq "")
			{$hshUserInfo = $false}
		
		return $hshUserInfo
	}

Function Find-FileType($filename) #ECC
	{
		$failFunction = $false
		#Just a simple extension check
		$filetype = $false
		If(($filename.substring($filename.length - 4,4) -eq "xlsx"))
			{$filetype = "xlsx"}
		ElseIf(($filename.substring($filename.length - 3,3) -eq "csv"))
			{$filetype = "csv"}
		Else
			{$failFunction = $true}
		
		#Error Checking
		If($failFunction -eq $false)
			{Return $filetype}
		Else
			{Return $false}
	}

Function Pull-UserFromUsernamesArray($arrUsernames,$intUserNumber)
	{
		$results = $null
		$results = $false
		
		#Write-host -f yellow "DEBUG!`tintUserNumber: $intUserNumber"
		$intUsernamesCount = $arrUsernames.count
		If($intUserNumber -gt $intUsernamesCount)
			{$results = $false}
		Else
			{
				$sAMAccountName = $arrUsernames[$intUserNumber]
				If($sAMAccountName -eq $null -or $sAMAccountName -eq "")
					{$results = $false}
				Else
					{
						$hshUserInfo = Populate-TableFromsAMAccountName $sAMAccountName
						$results = $hshUserInfo
					}
			}
		
		Return $results
	}


### ___Other Functions___

Function Director($arrCoreArgs,$strInputMode,$inputArgDep,$intStartNumber,$intLimit)
	{
		$failFunction = $null
		$failFunction = $false
		
		$scriptUser = $env:username
		
		#cleanup core args -- in case it's not an array
		If($arrCoreArgs -is [array])
			{}
		Else
			{[array]$arrCoreArgs = $arrCoreArgs}
		#foreach($coreArg in $arrCoreArgs){Write-Host -f green "coreArg: $coreArg"}
		
		#init vars
		If($intStartNumber -lt 1){$intStartNumber = 1}
		[int]$intUserNumber = $null
		$intUserNumber = 0
		$intUserNumber += $intStartNumber
		#quick hack -- Excel and CSV rows start at 1 not zero. We can never have a usernumber be 0
		If($intUsernumber -lt 1)
			{$intUserNumber = 1}
		Else{}
		
		$hshUserInfo = $null
		$failedUser = @()
		$arrFailedUsers = @()
		$intTotalUsers = 0
		$strFileType = $null
		
		#check input mode. Open and cache files \ folders \ groups if needed
		Switch($strInputMode)
			{
				"/file"
					{
						$filename = $inputArgDep
						#init file ops
						$msg = "ACTION`tDetermining file type for file """ + $filename + """."
						Write-Out $msg "white" 3
						$strFileType = Find-FileType $filename
						If($strFileType -eq $false)
							{
								$failFunction = $true
								$warningMsg = "ERROR`tCould not determine the file type."
								Throw-Warning $warningMsg
							}
						Else
							{
								$msg = "INFO`tFile type for file """ + $filename + """ determined to be """ + $strFileType + """."
								Write-Out $msg "white" 3
								$msg = "ACTION`tOpening file """ + $filename + """."
								Write-Out $msg "white" 3
								
								$objSourceFile = Open-File $filename $strFileType $intStartNumber $intLimit
								If($objSourceFile -eq $false)
									{
										$failFunction = $true
										$warningMsg = "ERROR`tCould not open source file """ + $filename + """."
										Throw-Warning $warningMsg
									}
								Else
									{
										$msg = "INFO`tFile """ + $filename + """ opened correctly."
										Write-Out $msg "gray" 2
										$formattedFile = $null
										$formattedFile = @()
										Foreach($row in $objSourceFile)
											{
												#Write-Host -f yellow "DEBUG!!!`tRow: $row"
												$regex = "^[\,\s]+$"
												If($row -match $regex)
													{}
												Else
													{
														$formattedFile += $row
													}
											}
										$formattedInputDep = $formattedFile
									}
							}
					}
				"/folder"
					{
						$foldername = $null
						$foldername = $inputArgDep
						$msg = "Action`tReading folders from """ + $foldername + """. This may take a couple minutes."
						Write-Out $msg "white" 2
						[array]$arrUsernames = @()
						[array]$arrUsernames += "<placeholder>"
						[array]$arrSubfolderNames = gci $foldername | %{If($_.PSIsContainer -eq $true){$_.Name}}
						$arrSubfolderNames | %{
							$blnUserExists = $null
							$blnUserExists = $false
							$blnUserExists = Check-DoesUserExist $_
							If($blnUserExists -eq $true)
								{$arrUsernames +=  $_}
							Else
								{}
						}
						
						$formattedInputDep = $arrUsernames
						#write-host -f yellow "DEBUG! $arrUsernames"
					}
				"/group"
					{
						$name = $null
						$name = $inputArgDep
						$msg = "Action`tReading users from """ + $name + """. This may take a couple minutes."
						Write-Out $msg "white" 2
						$arrUsernames = $null
						[array]$arrUsernames = @()
						[array]$arrUsernames += "<placeholder>"
						$blnGroupExists = $null
						$blnGroupExists = $false
						$blnGroupExists = Check-DoesGroupExist $name
						If($blnGroupExists -eq $true)
							{
								$groupDN = $null
								$groupDN = Get-DNbyCN $name
								$member = $null
								$member = Get-GroupMembers $groupDN
								$i = $null
								$i = 0
								Foreach($DN in $member)
									{
										If($i % 125 -eq 0){Write-Host -f green -nonewline "."}
										$objUser = $null
										$objUser = [adsi]("LDAP://" + $DN)
										$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
										If($sAMAccountName -eq $null)
											{
												$msg = "Warning`tThe DN """ + $DN + """ doesn't have a sAMAccountName."
												Throw-Warning $msg
												$msg = "Warning`t`tSkipping this user."
												Throw-Warning $msg
											}
										Else
											{
												$arrUsernames += $sAMAccountName
											}
										$i++
									}
								Write-Host -f green ""
							}
						Else
							{
								$msg = "Warning`tThe group """ + $name + """ doesn't exist."
								Throw-Warning $msg
								$failThisFunction = $true
							}
						
						$formattedInputDep = $arrUsernames
						#write-host -f yellow "DEBUG! $arrUsernames"
					}
				"/allusers"
					{
						$strDomainShort = $null
						$strDomainShort = Read-Variable "domainShort"
						$msg = "Action`tReading users from the domain """ + $strDomainShort + """. This may take a couple minutes."
						Write-Out $msg "white" 2
						
						$usersOUCN = Read-Variable "UsersOUCN"
						$strUsersOUDN = Read-Variable "UsersOUDN"
						$msg = "Info`tThe search is limited to the following OU: """ + $strUsersOUDN + """."
						Write-Out $msg "darkcyan" 4
						
						$arrUsernames = $null
						$arrUsernames = @()
						$arrUsernames += "<placeholder>"	
						$arrUsers = $null
						$arrUsers = Get-AllUsersInOU $strUsersOUDN
						If($arrUsers -eq $null -or $arrUsers -eq $false -or $allUsers -eq "")
							{
								$msg = "Error`tCannot enumerate domain users."
								Throw-Warning $msg
								$failThisFunction = $true
							}
						Else
							{
								Foreach($user in $arrUsers)
									{
										$arrUsernames += $user
									}
							}
						$formattedInputDep = $arrUsernames
						#write-host -f yellow "DEBUG! $arrUsernames"
					}
				Default {$formattedInputDep = $inputArgDep}
			}
		
		#write-host -f yellow "DEBUG!`tformattedInputDep: $formattedInputDep"
		
		#loop through all the users
		If($failFunction -eq $false)
			{
				[int]$intProcessedUsers = $null
				$intProcessedUsers = 0
				$blnStop = $null
				$blnStop = $false
				While($blnStop -eq $false)
					{
						If($intLimit -ge $intUserNumber)
							{
								#reinit vars
				 				$hshUserInfo = $null
				 				$hshUserInfo = $false
								$hshUserInfo = $null
								$validated = $false
								$hshUserInfo = $null
								$processed = $false
								
								If($strInputMode -eq "/user")
									{
										If($intUserNumber -eq 0)
											{
												$msg = "ACTION`tAttempting to get user data for user """ + $formattedInputDep + """."
												Write-Out $msg "white" 2
											}
									}
								Else
									{
										$msg = "ACTION`tAttempting to get user data for user number " + $intUserNumber + "."
										Write-Out $msg "white" 2
									}
								
								#Write-host -f yellow "DEBUG!`tintUserNumber: $intUserNumber"
								
								$startTime = $null
								$startTime = get-date
								
								
								#used to predictively (and I use that word loosely) skip tests
								$global:arrTestsToSkip = $null
								$global:arrTestsToSkip = @()
								
								$hshUserInfo = $null
								$hshUserInfo = Find-UserInfo $strInputMode $formattedInputDep $intUserNumber
								
							#	Write-host -f yellow "----------------------hshUserInfo!-------------------------------"
							#	$hshUserInfo | out-host
							#	$hshUserInfo = $false
								
								#check -- are we done?
								If($hshUserInfo -eq $false -or $hshUserInfo -eq $null)
									{
										If($strInputMode -eq "/user")
											{$blnStop = $true}
										ElseIf($strInputMode -eq "/file")
											{
												$blnEndOfFile = Check-EndOfFile $formattedInputDep $intUserNumber
												If($blnEndOfFile -eq $true)
													{
														$msg = "INFO`tReached the end of the file."
														Write-Out $msg "white" 2
														$blnStop = $true
													}
												Else
													{
														$msg = "Warning`tCould not process the current user. Giving up on this user."
														Throw-Warning $msg
														$intUserNumber++
													}
											}
										ElseIf($strInputMode -eq "/folder" -or $strInputMode -eq "/group" -or $strInputMode -eq "/allusers")
											{
												
												$rowCount = $formattedInputDep.count - 1
												If($intUserNumber -ge $rowCount)
													{
														$msg = "Info`tAll users have been processed."
														Write-Out $msg "white" 2
														$blnStop = $true
													}
												Else
													{
														$msg = "Warning`tCould not process the current user. Giving up on this user."
														Throw-Warning $msg
														$sAMAccountName = $formattedInputDep[$intUserNumber]
														$arrFailedUsers += $sAMAccountName
														$intUserNumber++
													}
											}
										Else
											{
												$msg = "The script has finished all the users."
												Write-Out $msg "green" 2
												$blnStop = $true
											}
									}
								Else
									{
										#preprocessing and string conversion
										#e.g. dates to "\" delimiter
										#$hshUserInfo = PreProcess-UserInfo $hshUserInfo
										$failThisUser = $false
										$intProcessedUsers++
										$sAMAccountName = $null
										$sAMAccountName = $hshUserInfo.Get_Item("sAMAccountName")
										If($sAMAccountName -eq $scriptUser)
											{
												$msg = "Warning`tSkipping user """ + $sAMAccountName + """ because it is the current script-user."
												$arrFailedUsers += $sAMAccountName
												Throw-Warning $msg
												$failThisUser = $true
											}
										Else
											{
												$arrMsg = $null
												$arrMsg = @()
												$arrMsg += "INFO`tData set for user """ + $sAMAccountName + """ (User number: " + $intUserNumber + ")"
												$keys = $null
												$keys = $hshUserInfo.Keys
												Foreach($key in $keys)
													{$arrMsg += "INTO`t`t""" + $key + """, """ + $hshUserInfo.Get_Item($key) + """"}
												Foreach($msg in $arrMsg)
													{Write-Out $msg "white" 2}
												
												$actionSet = $null
												$msg = "ACTION`t`tBuilding the action set for this user."
												Write-Out $msg "white" 2
												$actionSet = $null 
												$actionSet = Build-ActionSet $hshUserInfo $arrCoreArgs
												If($actionSet -eq $false)
													{
														$warningMsg = "ERROR`tCould not build action set for this user."
														Throw-Warning $warningMsg
														$failedUser = $sAMAccountName
														$arrFailedUsers += $failedUser
													}
												ElseIf($actionSet -eq $null)
													{
														$msg = "Info`t`tThis user does not require any work. Skipping user."
														Write-Out $msg "white" 2
													}
												Else
													{
														$msgs = $null
														$msgs = @()
														$msgs += "INFO`tAction set for this user:"
														Foreach($action in $actionSet)
															{$msgs += "INFO`t`t*" + $action}
														Foreach($msg in $msgs)
															{Write-Out $msg "white" 2}
														$failThisUser = $false
														$complSeconds = $null
														$complSeconds = ((get-date) - $startTime).duration().totalmilliseconds
														$complSeconds = [Math]::Round($complSeconds,0)
														$msg = "INFO`tIt took " + $complSeconds + " milliseconds to load this user."
														Write-Out $msg "yellow" 2
														
														Foreach($action in $actionSet)
															{
																If($failthisuser -ne $true)
																	{
																		$actionStartTime = $null
																		$actionStartTime = get-date
																		$msg = "ACTION`tRunning action: """ + $action + """."
																		Write-Out $msg "white" 2
																		$actionResults = Run-Action $action $hshUserInfo
																		If($actionResults -eq $false)
																			{
																				$warningMsg = "ERROR`tAction failed: """ + $action + """."
																				Throw-Warning $warningMsg
																				$failthisuser = $true
																				$failedUser = $sAMAccountName
																				$arrFailedUsers += $failedUser
																			}
																		$complSeconds = $null
																		$complSeconds = ((get-date) - $actionStartTime).duration().totalmilliseconds
																		$complSeconds = [Math]::Round($complSeconds,0)
																		$msg = "INFO`tThe action took " + $complSeconds + " milliseconds."
																		Write-Out $msg "yellow" 2
																	}
															}
													}
												
												$complSeconds = $null
												$complSeconds = ((get-date) - $startTime).duration().TotalSeconds
												$complSeconds = [Math]::Round($complSeconds,1)
												$msg = "INFO`tThis user took " + $complSeconds + " seconds to complete."
												Write-Out $msg "white" 2	
											}
										
										If($failthisuser -eq $true)
											{Write-Fail}
										Else
											{Write-Win}
										$intUserNumber++
									}
							}
						Else
							{
								$msg = "INFO`tReached the end of specified user range."
								Write-Out $msg "white" 2
								$blnStop = $true
							}
					}
				
				#we started at user 1, not user 0. This fixes the starting value so that we report properly.
				$intTotalUsers = $intProcessedUsers
				#If($intTotalUsers -lt 0){$intTotalUsers = 0}
				#ASSERT - intTotalUsers doesn't equal zero
				Report $intTotalUsers $arrFailedUsers
			}
		
		If($failFunction -eq $true)
			{
				$warningMsg = "ERROR`tFailing the script"
				Throw-Warning $warningMsg
				Return $false
			}
		Else
			{Return $true}
	}

Function Run-ValidationTest($test,$objUser) #ECC
	{
		$results = $false
		$failFunction = $false
		Switch($test)
			{
				"validateFor-MarkAccountForArchival"
					{
						$results = Check-AccountReadyForWindowsArchival $objUser
					}
				"validateFor-ArchiveUserFromWindows"
					{
						$results = Check-AccountReadyForWindowsArchival $objUser
					}
				"validateFor-DeleteUserFromAD"
					{
						$results = Check-AccountReadyForDeletion $objUser
					}
				Default
					{
						$failFunction = $true
						$warningMsg = "ERROR`tAttempted to run a validation test that does not exist: """ + $test + """."
						Throw-Warning $warningMsg
					}
			}
		If($failFunction -eq $false)
			{Return $results}
		Else
			{Return $false}
	}

Function Check-AccountReadyForWindowsArchival($objUser)
	{
		$results = $null
		$results = $false
		$failThisFunction = $null
		$failThisFunction = $false
		
		#is the account expired > 1yr?
		$msg = "Action`t`tChecking the account's expiration date."
		Write-Out $msg "darkcyan" 4
		$expirationDate = $null
		$expirationDate = Find-ExpirationDate $objUser
		#write-host -f yellow "debug`t(f)check-AccountReadyForWindowsArchival`texpirationDate: $expirationDate"
		
		If($expirationDate -eq $null)
			{
				$msg = "Info`t`tAccount does not have an expiration date."
				Write-Out $msg "darkcyan" 4
			}
		Else
			{
				$msg = "Info`t`tThe user's expiration date is """ + $expirationDate + """."
				$dateExpirationDate = Get-Date $expirationDate
				$today = Get-Date
				$OneYearAgo = $today.AddYears(-1)
				If($dateExpirationDate -lt $oneYearAgo)
					{
						$msg = "Info`t`tThe user has been expired for longer than a year."
						Write-Out $msg "darkcyan" 4
						$results = $true
					}
				Else
					{
						$msg = "Info`t`tThe user's expiration date is less than one year ago."
						Write-Out $msg "darkcyan" 4
						$results = $false
					}
			}
		
		If($failThisFunction -eq $false -and $results -eq $true)
			{
				$msg = "Action`t`tChecking if this account is marked as archived."
				Write-Out $msg "darkcyan" 4
				$WindowsArchiveDoneGroupCN = $null
				$WindowsArchiveDoneGroupCN = Read-Variable "WindowsArchiveDoneGroupCN"
				$strGroupDN = $null
				$strGroupDN = Get-DNbyCN $WindowsArchiveDoneGroupCN
				$strUserDN = $null
				$strUserDN = Pull-LDAPAttribute $objUser "distinguishedName"
				$blnMemberCheck = $null
				$blnMemberCheck = $false
				$blnMemberCheck = Check-IsMemberOfGroup $strUserDN $strGroupDN
				If($blnMemberCheck -eq $true)
					{
						###HACK###
						
						$msg = "Info`t`tThis account is already archived. Skipping user."
						Write-Out $msg "darkcyan" 4
						$results = $false
						
						#$msg = "Debug`t(f)Check-AccountReadyForWindowsArchival: Re-Archiving this account."
						#Write-Out $msg "yellow" 4
						#$results = $true
					}
				Else
					{
						$msg = "Info`t`tThis account has not yet been archived."
						Write-Out $msg "darkcyan" 4
						$results = $true
					}
			}
		
		If($failThisFunction -eq $true)
			{$results = $false}
		Else
			{}
		Return $results
	}

Function Check-AccountReadyForDeletion($objUser)
	{
		$results = $null
		$results = $false
		$failThisFunction = $null
		$failThisFunction = $false
		$blnContinue = $null
		$blnContinue = $true
		
		$strUserDN = $null
		$strUserDN = Pull-LDAPAttribute $objUser "distinguishedName"
		
		#check member of deletion group
		$deletionGroupCN = $null
		$deletionGroupCN = Read-Variable "deletionGroupCN"
		$deletionGroupDN = $null
		$deletionGroupDN = Get-DNbyCN $deletionGroupCN
		$msg = "Action`t`tChecking if the user is a member of the """ + $deletionGroupCN + """ group."
		Write-Out $msg "darkcyan" 4
		$blnMemberCheck = $null
		$blnMemberCheck = $false
		$blnMemberCheck = Check-IsMemberOfGroup $strUserDN $deletionGroupDN
		If($blnMemberCheck -eq $true)
			{
				$msg = "Info`t`tUser -IS- a member of the group."
				Write-Out $msg "darkcyan" 4
			}
		Else
			{
				$msg = "Info`t`tUser is not a member of the group."
				Write-Out $msg "darkcyan" 4
				$blnContinue = $false
			}
		
#		If($blnContinue -eq $true)
#			{
#				#check enabled
#				$blnExpired = $null
#				$blnExpired = $false
#				$msg = "Action`tChecking that the user matches archival requirements."
#				Write-Out $msg "darkcyan" 4
#				$blnExpired = Run-ValidationTest "validateFor-ArchiveUserFromWindows" $objUser
#				If($blnExpired -eq $true)
#					{
#						$msg = "Info`t`tUser matches archival requirements."
#						Write-Out $msg "darkcyan" 4
#					}
#				Else
#					{
#						$msg = "Info`t`tUser does not match archival requirements."
#						Write-Out $msg "darkcyan" 4
#					}
#			}
		
#		If($blnMemberCheck -eq $true -and $blnExpired -eq $true)
		If($blnMemberCheck -eq $true)
			{$results = $true}
		
		If($failThisFunction -eq $true)
			{$results = $false}
		Else
			{}
		Return $results
	}

Function Validate-MemberOfGroups($groups)
	{
		$failFunction = $false
		$results = $true
		
		If($groups -eq $false -or $groups -eq $null)
			{$failFunction = $true}
		Else
			{
				$groupsType = ($groups.gettype().name)
				$groupsType_2 = ($groups.GetType().BaseObject.Name)
				
				$arrGroups = @()
				#make damn sure this is an array.
				If($groupsType = "string")
					{$arrGroups += $groups}
				ElseIf($groupsType_2 -eq "array")
					{$arrGroups = $groups}
				Else
					{
						$warningMsg = "ERROR`tCould not validate groups."
						Throw-Warning $warningMsg
						$failFunction = $true
					}
				
				#If any groups DNE then fail
				If($failFunction -ne $true)
					{
						Foreach($group in $arrGroups)
							{
								$groupDN = $null
								$groupDN = Get-DNbyCN $group "group"
								If($groupDN -eq $false)
									{
										$warningMsg = "ERROR`t`tMissing group detected: """ + $group + """."
										Throw-Warning $warningMsg
										$failFunction = $true
									}
								Else
									{}
							}
					}
			}
		
		If($failFunction -eq $true)
			{Return $false}
		Else
			{Return $true}
	}

Function Remove-FromArray($strElement,$arrArray)
	{
		$newArray = $null
		$newArray = @()
		Foreach($element in $arrArray)
			{
				If($element -eq $strElement)
					{}
				Else
					{$newArray += $element}
			}
		Return $newArray
	}

Function Check-EndOfFile($file,$intUserNumber)
	{
		$fileRows = $file.count - 1  #offset for the headers
		#write-host -f yellow "DEBUG! fileRows $filerows`nDEBUG!`tintUserNumber: $intUserNumber"
		If($intUserNumber -ge $fileRows)
			{$retval = $true}
		Else
			{$retval = $false}
		Return $retval
	}
	
Function Build-ActionSet($hshUserInfo,$arrCoreArgs)
	{
		$failFunction = $false
		$actionSet = $null
		$actionSet = @()
		$sAMAccountName = $hshUserInfo.Get_Item("sAMAccountName")
		If($sAMAccountName -eq "null" -or $sAMAccountName -eq "")
			{
				$warningMsg = "ERROR`tNo username provided. Skipping user."
				Throw-Warning $warningMsg
				$failFunction = $true
			}
		Else
			{
				$userExists = Check-DoesUserExist $sAMAccountName
				If($userExists)
					{}
				Else
					{
						$warningMsg = "Error`tUser does not exist. Skipping user."
						Throw-Warning $warningMsg
						$failFunction = $true
					}
			}
		
		If($failFunction -eq $false)
			{
				$objUserDN = $null
				$objUserDN = Get-DNbySAMAccountName $sAMAccountName
				$objUser = $null
				$objUser = [adsi]("LDAP://" + $objUserDN)
				
				If($arrCoreArgs -contains "/scan")
					{
						#$msg = "Action`t`tScanning this user for accountExpires problmems."
						$actionSet += "ScanForAccountExpiresProblems"
					}
				
				If($arrCoreArgs -contains "/mark")
					{
						$actionSet += "checkandfix-ArchiveGroupMembership"
						$msg = "Action`t`tValidating this user for archival."
						Write-Out $msg "darkcyan" 4
						$strAccountTest = $null
						$strAccountTest = "validateFor-MarkAccountForArchival"
						$blnAccountTest = $null
						$blnAccountTest = $false
						$blnAccountTest = Run-ValidationTest $strAccountTest $objUser
						If($blnAccountTest -eq $true)
							{
								$msg = "Info`t`tUser meets the requirements for archival."
								Write-Out $msg "darkcyan" 4
								$actionSet += "MarkAccountForArchival"
							}
						Else
							{
								$msg = "Info`t`tThis user does not meet the requirements for archival."
								Write-Out $msg "darkcyan" 4
								
							}
					}
				
				If($arrCoreArgs -contains "/archive")
					{
						$actionSet += "checkandfix-ArchiveGroupMembership"
						$msg = "Action`t`tValidating this user for archival."
						Write-Out $msg "darkcyan" 4
						$strAccountTest = $null
						$strAccountTest = "validateFor-ArchiveUserFromWindows"
						$blnAccountTest = $null
						$blnAccountTest = $false
						$blnAccountTest = Run-ValidationTest $strAccountTest $objUser
						If($blnAccountTest -eq $true)
							{
								$msg = "Info`t`tUser meets the requirements for archival."
								Write-Out $msg "darkcyan" 4
								$actionSet += "ArchiveUserFromWindows"
							}
						Else
							{
								$msg = "Info`t`tThis user does not meet the requirements for archival."
								Write-Out $msg "darkcyan" 4
								$actionSet += "checkandfix-ArchiveGroupMembership"
							}
					}
				
				If($arrCoreArgs -contains "/delete")
					{
						$actionSet += "checkandfix-ArchiveGroupMembership"
						$msg = "Action`t`tValidating this user for deletion."
						Write-Out $msg "darkcyan" 4
						$strAccountTest = $null
						$strAccountTest = "validateFor-DeleteUserFromAD"
						$blnAccountTest = $null
						$blnAccountTest = $false
						$blnAccountTest = Run-ValidationTest $strAccountTest $objUser
						If($blnAccountTest -eq $true)
							{
								$msg = "Info`t`tUser meets the requirements for deletion."
								Write-Out $msg "darkcyan" 4
								$actionSet += "DeleteUserFromAD"
							}
						Else
							{
								$msg = "Info`t`tThis user does not meet the requirements for deletion."
								Write-Out $msg "darkcyan" 4
							}
					}
			}
		
		$retval = $null
		If($failFunction -eq $true)
			{$retval = $false}
		Else
			{$retval = $actionSet}
			Return $retval
	}

Function Run-Action($action,$hshUserInfo)
	{
		$failFunction = $false
		$results = $null
		$results = $false
		Switch($action)
			{
				"checkandfix-ArchiveGroupMembership"
					{$results = CheckAndFix-ArchiveGroupMembership $hshUserInfo}
				"MarkAccountForArchival"
					{$results = Mark-AccountForArchival $hshUserInfo}
				"ArchiveUserFromWindows"
					{$results = Archive-UserFromWindows $hshUserInfo}
				"DeleteUserFromAD"
					{$results = Delete-UserFromAD $hshUserInfo}
				"ScanForAccountExpiresProblems"
					{$results = Scan-AccountExpires $hshUserInfo}
				Default
					{
						$warningMsg = "ERROR`tRun-Action was asked to perform an action that isn't defined: """ + $action + """."
						Throw-Warning $warningMsg
						$failFunction = $true
					}
			}
		
		If($failFunction -eq $true)
			{$retval = $false}
		Else
			{$retval = $results}
		Return $retval
	}

Function Report($intTotalUsers,$failedUsers)
	{
		$intFailedUsers = $failedUsers.count
		
		$arrMsg = @()
		$arrMsg += "Total Users Processed: " + $intTotalUsers
		$arrMsg += "Number of failed users: " + $intFailedUsers
		$arrMsg += "Log file: " + $gLogFile
		If($intFailedUsers -eq 0)
			{}
		Else
			{
				$arrMsg += "List of failed usernames:"
				Foreach($failedUser in $failedUsers)
				{$arrMsg += "`t" + $failedUser}
			}
		Foreach($msg in $arrMsg)
			{Write-Out $msg "white" 2}
		
	}


#### Work Functions ####


Function CheckAndFix-ArchiveGroupMembership($hshUserInfo)
	{
		$failthisfunction = $false
		$results = $true
		$sAMAccountName = $null
		$sAMAccountName = $hshUserInfo.Get_Item("sAMAccountName")
		$strUserDN = $null
		$strUserDN = Get-DNbySAMAccountName $sAMAccountName
		
		$bArchivable = $false
		$objUser = [adsi]("LDAP://" + $strUserDN)
		$expirationDate = Find-Expirationdate $objUser
		If($expirationDate -eq $null)
			{
				$msg = "Info`t`tAccount does not have an expiration date."
				Write-Out $msg "darkcyan" 4
				$bArchivable = $false
			}
		Else
			{
				$msg = "Info`t`tThe user's expiration date is """ + $expirationDate + """."
				$dateExpirationDate = Get-Date $expirationDate
				$today = Get-Date
				$OneYearAgo = $today.AddYears(-1)
				If($dateExpirationDate -lt $oneYearAgo)
					{
						$msg = "Info`t`tThe user has been expired for longer than a year."
						Write-Out $msg "darkcyan" 4
						$bArchivable = $true
					}
				Else
					{
						$msg = "Info`t`tThe user's expiration date is less than one year ago."
						Write-Out $msg "darkcyan" 4
						$bArchivable = $false
					}
			}
		
		If($bArchivable -eq $false)
			{
				$readyToArchiveCN = Read-Variable "ReadyForWindowsArchiveGroupCN"
				$readyToArchiveDN = Get-DNbyCN $readyToArchiveCN 
				$blnMemberCheck = $null
				$blnMemberCheck = $false
				$blnMemberCheck = Check-IsMemberOfGroup $strUserDN $readyToArchiveDN
				If($blnMemberCheck -eq $true)
					{
						$msg = "WARNING`tThis user doesn't meet archive requirements, but is a member of the """ + $readyToArchiveCN + """ group."
						Throw-Warning $msg
						$msg = "Action`t`tRemoving user from this group."
						Write-Out $msg "white" 1
						$action = Remove-FromGroup $strUserDN $readyToArchiveDN
					}
				
				$blnMemberCheck = $null
				$blnMemberCheck = $false
				$blnMemberCheck = Check-IsMemberOfGroup $strUserDN $readyToArchiveDN
				If($blnMemberCheck -eq $true)
					{
						$msg = "WARNING`tFailed to remove user from archive group."
						Throw-Warning $msg
						$failthisfunction = $true
					}
			}
		
		#check other grp membership.
		If($bArchivable -eq $false -and $failthisfunction -eq $false)
			{
				$arrGroupsToCheck = @()
				$arrGroupsToCheck += (Get-DNbyCN (Read-Variable "ArchivedUsersGroupCN"))
				$arrGroupsToCheck += (Get-DNbyCN (Read-Variable "ReadyForLinuxArchiveGroupCN"))
				$arrGroupsToCheck += (Get-DNbyCN (Read-Variable "WindowsArchiveDoneGroupCN"))
				$arrGroupsToCheck += (Get-DNbyCN (Read-Variable "ReadyForLinuxArchiveGroupCN"))
				$arrGroupsToCheck += (Get-DNbyCN (Read-Variable "LinuxArchiveDoneGroupCN"))
				$arrGroupsToCheck += (Get-DNbyCN (Read-Variable "deletionGroupCN"))
				
				$arrGroupsToCheck | % {
					$groupDN = $_
					$blnMemberCheck = $null
					$blnMemberCheck = $false
					$blnMemberCheck = Check-IsMemberOfGroup $strUserDN $groupDN
					If($blnMemberCheck -eq $true)
						{
							$objGroup = [adsi]("LDAP://" + $groupDN)
							$groupCN = Pull-LDAPAttribute $objGroup "CN"
							$msg = "WARNING`tThis user doesn't meet archive requirements, but is a member of the """ + $groupCN + """ group."
							Throw-Warning $msg
							$results = $false
							$failthisfunction = $true
							Break
						}
				}
			}
		
		If($failthisfunction -eq $true)
			{$results = $false}
		Return $results
	}

Function Mark-AccountForArchival($hshUserInfo)
	{
		####USE THE (F)AddToGroup instead of this (f) doing that in-house.
		$failThisFunction = $null
		$failThisFunction = $false
		$results = $null
		
		$msg = "Action`t`tMarking this user for archival."
		Write-Out $msg "darkcyan" 4
		
		$archiveGroupCN = $null
		$archiveGroupCN = Read-Variable "ReadyForWindowsArchiveGroupCN"
		$archiveGroupDN = $nulkl
		$archiveGroupDN = Get-DNbyCN $archiveGroupCN
		
		$msg = "Info`t`tArchival group read as: """ + $archiveGroupCN + """."
		Write-Out $msg "darkcyan" 4
		
		$sAMAccountName = $null
		$sAMAccountName = $hshUserInfo.Get_Item("sAMAccountName")
		$strUserDN = $null
		$strUserDN = Get-DNbySAMAccountName $sAMAccountName
		
		$msg = "Action`t`tChecking if this user is a member of the archive group."
		Write-Out $msg "darkcyan" 4
		
		$blnMemberCheck = $null
		$blnMemberCheck = $false
		$blnMemberCheck = Check-IsMemberOfGroup $strUserDN $archiveGroupDN
		If($blnMemberCheck -eq $true)
			{
				$msg = "Info`t`tUser is already a member of the archive group."
				Write-Out $msg "darkcyan" 4
			}
		Else
			{
				$msg = "Info`t`tUser is -not- a member of the archive group."
				Write-Out $msg "darkcyan" 4
				$msg = "Action`t`tAdding this user to the archive group."
				Write-Out $msg "darkcyan" 4
				
				$blnAdded = $null
				$blnAdded = $false
				$blnAdded = Add-ToGroup $strUserDN $archiveGroupDN
				If($blnAdded -eq $true)
					{
						$msg = "Action`t`tUser added successfully."
						Write-Out $msg "darkcyan" 4
					}
				Else
					{
						$msg = "Warning`t`tFailed to add this user to the archive group."
						Throw-Warning $msg
						$failThisFunction = $true
					}
			}
		
		#final check
		$blnMemberCheck = $null
		$blnMemberCheck = $false
		$blnMemberCheck = Check-IsMemberOfGroup $strUserDN $archiveGroupDN
		If($blnMemberCheck -eq $true)
			{$results = $true}
		Else
			{$results = $false}
		
		If($failThisFunction -eq $true)
			{$retval = $false}
		Else
			{$retval = $results}
		Return $retval
	}

Function Archive-UserFromWindows($hshUserInfo)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		$results = $null
		
		#look up the DN
		$sAMAccountName = $null
		$sAMAccountName = $hshUserInfo.Get_Item("sAMAccountName")
		$blnUserCheck = $null
		$blnUserCheck = $false
		$blnUserCheck = Check-DoesUserExist $sAMAccountName
		If($blnUserCheck -eq $null -or $blnUserCheck -eq $false -or $blnUserCheck -eq "")
			{
				$msg = "Error`t`tThe user given does not exist: """ + $sAMAccountName + """."
				Throw-Warning $msg
				$failThisFunction = $true
			}
		Else
			{
				$strUserDN = $null
				$strUserDN = Get-DNbySAMAccountName $sAMAccountName
				If($strUserDN -eq $null -or $strUserDN -eq $false -or $strUserDN -eq "")
					{
						$msg = "Error`t`tCould not lookup the DN for user """ + $sAMAccountName + """."
						Throw-Warning $msg
						$failThisFunction = $true
					}
				Else
					{}
			}
		
		#bind to the user
		If($failThisFunction -eq $false)
			{
				$objUser = $null
				$objUser = [adsi]("LDAP://" + $strUserDN)
				$OC = $null
				$OC = Pull-LDAPAttribute $objUser "objectCategory"
				If($OC -like "*person*")
					{}
				Else
					{
						$msg = "Warning`t`tThe following DN is unavailable or not a user object: """ + $strUserDN + """."
						Throw-Warning $msg
						$failThisFunction = $true
					}
			}
		
		#construct and run task set
		If($failThisFunction -eq $false)
			{
				$tasklist = $null
				$tasklist = @()
				$tasklist += "runFixScript"
				$tasklist += "ArchiveAndStoreData"
				$tasklist += "deleteWindowsShareAndRenameSource"
				$tasklist += "Disable-Account"
				$tasklist += "AddToGroup-DenyLogins"
				$tasklist += "RemoveFromGroup-ReadyForWinArchival"
				$tasklist += "AddToGroup-WindowsArchiveDone"
				
				$msg = "Action`tTesting this account for unix attributes."
				Write-Out $msg "cyan" 2
				$bUnixAccount = $null
				$bUnixAccount = Check-IsUnixAccount $objUser
				If($bUnixAccount -eq $true)
					{
						$msg = "Info`tThis account has unix attributes."
						Write-Out $msg "cyan" 2
						$tasklist += "AddToGroup-ReadyForLinuxArchival"
					}
				Else
					{
						$msg = "Info`tThis account does not have unix attributes."
						Write-Out $msg "cyan" 2
						$tasklist += "AddToGroup-ReadyToDelete"
					}
				
				$sAMAccountName = $null
				$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
				Foreach($task in $tasklist)
					{
						$msg = "Action`tRunning archive task: """ + $task + """."
						Write-Out $msg "cyan" 2
						$DN = $null
						$DN = Get-DNbysAMAccountname $sAMAccountName
						$objUser = $null
						$objUser = [adsi]("LDAP://" + $DN)
						$blnTask = $null
						$blnTask = $false
						$blnTask = Run-ArchiveTask $task $objUser
						If($blnTask -eq $false)
							{
								$msg = "Warning`tCould not successfully complete the task """ + $task + """."
								Throw-Warning $msg
								$failThisFunction = $true
								Break
							}
						Else
							{
								$msg = "Info`tSuccessfully completed the task """ + $task + """."
								Write-Out $msg "green" 2
							}
					}
			}
		
		If($failThisFunction -eq $true)
			{$retval = $false}	
		Else
			{$retval = $results}
		Return $retval
	}

Function Scan-AccountExpires($hshUserInfo)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		$results = $null
		$results = $true
		
		#look up the DN
		$sAMAccountName = $null
		$sAMAccountName = $hshUserInfo.Get_Item("sAMAccountName")
		$blnUserCheck = $null
		$blnUserCheck = $false
		$blnUserCheck = Check-DoesUserExist $sAMAccountName
		If($blnUserCheck -eq $null -or $blnUserCheck -eq $false -or $blnUserCheck -eq "")
			{
				$msg = "Error`t`tThe user given does not exist: """ + $sAMAccountName + """."
				Throw-Warning $msg
				$failThisFunction = $true
			}
		Else
			{
				$strUserDN = $null
				$strUserDN = Get-DNbySAMAccountName $sAMAccountName
				If($strUserDN -eq $null -or $strUserDN -eq $false -or $strUserDN -eq "")
					{
						$msg = "Error`t`tCould not lookup the DN for user """ + $sAMAccountName + """."
						Throw-Warning $msg
						$failThisFunction = $true
					}
				Else
					{}
			}
		
		#bind to the user
		If($failThisFunction -eq $false)
			{
				$objUser = $null
				$objUser = [adsi]("LDAP://" + $strUserDN)
				$OC = $null
				$OC = Pull-LDAPAttribute $objUser "objectCategory"
				If($OC -like "*person*")
					{}
				Else
					{
						$msg = "Warning`t`tThe following DN is unavailable or not a user object: """ + $strUserDN + """."
						Throw-Warning $msg
						$failThisFunction = $true
					}
			}
		
		####run tests####
		
		#should expire?
		If($failThisFunction -eq $false)
			{
				$msg = "Action`tChecking if the account should expire."
				$blnShouldExpire = $null
				$blnShouldExpire = $true
				$blnShouldExpire = Check-AccountShouldExpire $objUser
				If($blnShouldExpire -eq $true)
					{
						$msg = "Info`t`tThis account -should- expire."
						Write-Out $msg "darkcyan" 4
					}
				ElseIf($blnShouldExpire -eq $false)
					{
						$msg = "Info`t`tThis account should not expire."
						Write-Out $msg "darkcyan" 4
					}
				Else
					{
						$msg = "Warning`t`tCould not tell if the account should expire."
						Throw-Warning $msg
						$results = $false
						$failThisFunction = $true
					}
			}
		
		#does expire?
		If($failThisFunction -eq $false)
			{
				$msg = "Action`tChecking if the account should expire."
				$blnExpires = $null
				$blnExpires = $false
				$blnExpires = Check-AccountExpires $objUser
				If($blnExpires -eq $true)
					{
						$msg = "Info`t`tThis account expires."
						Write-Out $msg "darkcyan" 4
					}
				ElseIf($blnExpires -eq $false)
					{
						$msg = "Info`t`tThis account does -not- expire."
						Write-Out $msg "darkcyan" 4
					}
				Else
					{
						$msg = "Warning`t`tCould not tell if the account expires."
						Throw-Warning $msg
						$results = $false
						$failThisFunction = $true
					}
			}
		
		#compare
		If($blnShouldExpire -eq $true -and $blnExpires -eq $false)
			{
				$msg = "Warning`t`tThis account should expire but doesn't!"
				Throw-Warning $msg
				$msg = "Action`t`tAdding this user to the ""Needs Expiration Date"" group."
				Write-Out $msg "white" 2
				$blnAction = $null
				$blnAction = $false
				$blnAction = AddToGroup-NeedsExpirationDate $objUser
				If($blnAction -eq $false)
					{
						$msg = "Error`t`tCould not add user to group. Failing user."
						Throw-Warning $msg
						$failThisFunction = $true
					}
				Else
					{
						$msg = "Info`t`tUser added successfully."
						Write-Out $msg "darkcyan" 4
						$results = $true
					}
			}
		Else
			{$results = $true}
		
		If($failThisFunction -eq $true)
			{$results = $false}
		
		Return $results
		
	}

Function Check-AccountExpires($objUser)
	{
		#### HACK #### COPIED FROM CREATE-ACCOUNTS-B30.PS1
		$blnAccountExpires = $null
		$expirationDate = $null
		$sAMAccountName = $null
		$results = $false
		
		$expirationDate = Find-ExpirationDate $objUser
		
		If($expirationDate -ne $null)
			{$blnAccountExpires = $true}
		Else
			{$blnAccountExpires = $false}
		
		$expirationDate = $null
		
		If($blnAccountExpires -eq $true)
			{$results = $true}
		Else
			{$results = $false}
		Return $results
	}

Function Check-AccountShouldExpire($objUser) #SkipECC
	{
		#### HACK #### COPIED FROM CREATE-ACCOUNTS-B30.PS1
		$results = $true
		$groups = $objUser.MemberOf
		$hshGroupExpirationDates = Read-Variable "hshGroupExpirationDates"
		$keys = $hshGroupExpirationDates.Keys
		
		Foreach($group in $groups)
			{
				If($results -eq $true)
					{
						$expectedGroupExpiration = Find-GroupExpirationDate $group
						If($expectedGroupExpiration -eq "never")
							{$results = $false}
						Else
							{}
					}
			}
		
		Return $results
	}

Function Find-GroupExpirationDate($group) #SkipECC
	{
		#### HACK #### COPIED FROM CREATE-ACCOUNTS-B30.PS1
		$results = $false
		$hshGroupExpirationDates = Read-Variable "hshGroupExpirationDates"
		$keys = $hshGroupExpirationDates.Keys
		
		Foreach($key in $keys)
			{
				If($results -eq $false)
					{
						If($group -like ("*" + $key + "*"))
							{
								$date = $hshGroupExpirationDates.$Key
								If($date -ne $null -and $date -ne $false -and $date -ne "never" -and $date -ne "unknown")
									{$results = Get-Date $date}
								Else
									{$results = $date}
							}
					}
			}
		return $results
	}


Function Run-ArchiveTask($task,$objUser)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		$results = $null
		
		$blnTaskResults = $null
		$blnTaskResults = $false
		Switch($task)
			{
				"deleteWindowsShareAndRenameSource"
					{
						$blnTaskResults = Delete-WindowsShareAndRenameSource $objUser
					}
				"RunFixScript"
					{
						$blnTaskResults = Run-FixScript $objUser
					}
				"ArchiveAndStoreData"
					{
						$blnTaskResults = Archive-WinFSData $objUser
					}
				"AddToGroup-DenyLogins"
					{
						$blnTaskResults = AddToGroup-DenyLogins $objUser
					}
				"RemoveFromGroup-ReadyForWinArchival"
					{
						$blnTaskResults = RemoveFromGroup-ReadyForWinArchival $objUser
					}
				"AddToGroup-WindowsArchiveDone"
					{
						$blnTaskResults = AddToGroup-WindowsArchiveDone $objUser
					}
				"AddToGroup-ReadyForLinuxArchival"
					{
						$blnTaskResults = AddToGroup-ReadyForLinuxArchival $objUser
					}
				"AddToGroup-ReadyToDelete"
					{
						$blnTaskResults = AddToGroup-ReadytoDelete $objUser
					}
				"Export-LDAPRecord"
					{
						$blnTaskResults = Export-LDAPRecord $objUser
					}
				"Verify-LDAPRecord"
					{
						$blnTaskResults = Verify-LDAPRecord $objUser
					}
				"Disable-Account"
					{
						$blnTaskResults = Disable-Account $objUser
					}
				"Delete-Account"
					{
						$blnTaskResults = Delete-Account $objUser
					}
				Default
					{
						$msg = "Debug`t`t(f)Run-ArchiveTask was passed a task that isn't defined: """ + $task + """."
						Throw-Warning $msg
						$failThisFunction = $true
					}
			}
		
		If($failThisFunction -eq $true)
			{$retval = $false}
		Else
			{$retval = $blnTaskResults}
		Return $retval
	}

#### Archive WinFS Data Functions


Function Run-FixScript($objUser)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		$results = $null
		$results = $false
		
		$msg = "Action`t`tCalling the account creation\fix script to make sure this user conforms for archival."
		Write-Out $msg "cyan" 4
		
		$sAMAccountName = $null
		$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
		If($sAMAccountName -eq $null -or $sAMAccountName -eq $false)
			{
				$msg = "Warning`t`tCould not look up username for user """ + $sAMAccountName + """."
				Throw-Warning $msg
				$failThisFunction = $true
			}
		Else
			{}
		
		$strCreateAccountsFilename = $null
		$strCreateAccountsFilename = Read-ArchVariable "createAccountsFilename"
		$cmdString = $null
		$cmdString = ".\" + $strCreateAccountsFilename
		$msg = "Action`tRunning the following command: " + $cmdString
		Write-Out $msg "darkcyan" 4
		$arrScriptResults = $null
		$arrScriptResults = @()
		$a = $null
		#from http://poshoholic.com/2008/03/18/powershell-deep-dive-using-myinvocation-and-invoke-expression-to-support-dot-sourcing-and-direct-invocation-in-shared-powershell-scripts/
		$blnScriptResults = $null
		$blnScriptResults = $false
		$blnScriptResults = &$cmdString "/fix" "/user" $sAMAccountName "/return"
		If($blnScriptResults -eq $true)
			{
				$msg = "Info`t`tThe account creation\fix script was able to conform this user."
				Write-Out $msg "darkcyan" 4
				$results = $true
			}
		Else
			{
				$msg = "Warning`t`tThe account creation\fix script was not able to conform this user."
				Write-Out $msg "cyan" 4
				$results = $false
			}
		
		If($failThisFunction -eq $true)
			{$retval = $false}
		Else
			{$retval = $results}
		Return $retval
	}

Function Delete-WindowsShareAndRenameSource($objUser)
	{
		#find windows share, delete it.
		$homeFS = $null
		$homeFS = Get-UserHomeFS $objUser
		
		$failThisFunction = $null
		$failThisFunction = $false
		$results = $null
		
		$sAMAccountName = $null
		$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
		If($sAMAccountName -eq $null -or $sAMAccountName -eq $false)
			{
				$msg = "Warning`t`tCould not look up username for user """ + $sAMAccountName + """."
				Throw-Warning $msg
				$failThisFunction = $true
			}
		Else
			{}
		
		$arrSourcePaths = $null
		$arrSourcePaths = @()
		#profile folders?
		If($failThisFunction -eq $false)
			{
				$msg = "Action`t`tChecking for profile folders."
				Write-Out $msg "darkcyan" 4
				
				$profileShare = Read-Variable "profileShare"
				$XPprofileRoot = $null
				$XPprofileRoot = $profileShare + "\" + $sAMAccountName
				$msg = "Info`t`tWinXP Profile path generated as: """ + $XPProfileRoot + """."
				Write-Out $msg "darkcyan" 4
				If((Test-Path $XPprofileRoot) -eq $true)
					{
						$msg = "Info`t`tFound a WinXP profile."
						Write-Out $msg "darkcyan" 4
						$blnXPProfile = $true
						$arrSourcePaths += $XPprofileRoot
					}
				Else
					{
						$msg = "Info`t`tNo XP profile found."
						Write-Out $msg "darkcyan" 4
						$blnXPProfile = $false
					}
				
				$Win7ProfileRoot = $null
				$Win7ProfileRoot = $profileShare + "\" + $sAMAccountName + ".V2"
				$msg = "Info`t`tWin7 Profile path generated as: """ + $Win7ProfileRoot + """."
				Write-Out $msg "darkcyan" 4
				If((Test-Path $Win7ProfileRoot) -eq $true)
					{
						$msg = "Info`t`tFound a Win7 profile."
						Write-Out $msg "darkcyan" 4
						$Win7ProfileRoot = $true
						$arrSourcePaths += $Win7ProfileRoot
					}
				Else
					{
						$msg = "Info`t`tNo Win7 profile found."
						Write-Out $msg "darkcyan" 4
						$Win7ProfileRoot = $false
					}
				
				If($blnXPProfile -eq $true -or $blnWin7Profile -eq $true)
					{$blnContinue = $true}
				Else
					{
						$msg = "Info`t`tNo profiles found, skipping this user."
						Write-Out $msg "darkcyan" 4
						$results = $true
						$blnContinue = $false
					}
			}
		
		If($failThisFunction -eq $false)
			{
				$shareName = $null
				$shareName = $sAMAccountName + "$"
				$msg = "Info`t`tSharename should be """ + $shareName + """."
				Write-Out $msg "darkcyan" 4
				
				$msg = "Action`t`tChecking for a share on the fileserver """ + $homeFS + """."
				Write-Out $msg "darkcyan" 4
				$blnShareExists = $null
				$blnShareExists = $false
				$blnShareExists = Check-DoesShareExist $shareName $homeFS
				If($blnShareExists -eq $true)
					{
						$sharePath = $null
						$i = $null
						$i = 0
						While($sharePath -eq $null -or $i -gt 10)
							{
								$sharePath = Get-SharePath $shareName $homeFS
								If($sharePath -eq $null)
									{Sleep -s 1}
								Else
									{Break}
								$i++
							}
						$uncSharePath = $null
						$uncSharePath = Convert-SharePathtoUNCPath $sharePath $homeFS
						$arrSourcePaths += $uncSharePath
						
						$msg = "Info`t`tFound a share at: """ + $uncSharePath + """."
						Write-Out $msg "darkcyan" 4
						$msg = "Action`t`tDeleting the share """ + $shareName + """."
						Write-Out $msg "darkcyan" 4
						$blnAction = $null
						$blnAction = $false
						$blnAction = Delete-Share $shareName $homeFS
						
						$blnShareExistsTwo = $null
						$blnShareExistsTwo = $false
						$blnShareExistsTwo = Check-DoesShareExist $shareName $homeFS
						If($blnShareExistsTwo -eq $true)
							{
								$msg = "Error`t`tCould not delete the share."
								Throw-Warning $msg
								$failThisFunction = $true
							}
						Else
							{
								$msg = "Info`t`tShare deleted successfully."
								Write-Out $msg "darkcyan" 4
							}
					}
				Else
					{
						$msg = "Info`t`tThis user does not have a share on a fileserver."
						Write-Out $msg "darkcyan" 4
					}
			}
		
		#rename the source if we're skipping migration
		If($failThisFunction -eq $false)
			{
				$strPath = $null
				Foreach($strPath in $arrSourcePaths)
					{
						$pathTest = Test-Path $strPath
						If($pathTest -eq $true -and $failThisFunction -eq $false)
							{
								$msg = "Action`t`tRenaming the path: """ + $strPath + """."
								Write-Out $msg "darkcyan" 4
								$blnAction = $null
								$blnAction = Rename-BadFolder $strPath
								$blnAction = $null
								If((Test-Path $strPath) -eq $true)
									{
										$msg = "Error`t`tSource folder could not be renamed."
										Throw-Warning $msg
										$failThisFunction = $true
									}
								Else
									{
										$msg = "Info`t`tSource folder renamed successfully."
										Write-Out $msg "darkcyan" 4
									}
							}
					}
			}
		
		
		If($failThisFunction -eq $true)
			{$retval = $false}
		Else
			{$retval = $results}
		Return $retval
	}

Function Build-ArchiveFolderDestinationPath($objUser,$strType)
	{
		If($strType -eq $null){$strType = "home"}
		
		$failThisFunction = $null
		$failThisFunction = $false
		$results = $null
		$results = $false
		
		$archiveRootUNC = $null
		$archiveRootUNC = Read-Variable "archiveRootUNC"
		$archiveRootUNC = Trim-TrailingSlash $archiveRootUNC
		If($archiveRootUNC -eq $null -or $archiveRootUNC -eq "" -or $archiveRootUNC -eq $false)
			{
				$msg = "Warning`t`tCould not read ""archiveRootUNC"" from the script's settings file."
				Throw-Warning $msg
				$failThisFunction = $true
			}
		
		If($failThisFunction -eq $false)
			{
				$sAMAccountName = $null
				$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
				If($sAMAccountName -eq $null -or $sAMAccountName -eq "" -or $sAMAccountName -eq $false)
					{
						$msg = "Debug`t`t(f)Build-ArchiveFolderDestinationPath could not read ""sAMAccountName"" from the user object passed to it."
						Throw-Warning $msg
						$failThisFunction = $true
					}
			}
		
		#find root + user-##
		If($failThisFunction -eq $false)
			{
				Switch($strType)
					{
						"home"
							{
								$folderName = "winfsdata"
							}
						"WinXPProfile"
							{
								$folderName = "WinXP_Profile"
							}
						"Win7Profile"
							{
								$folderName = "Win7_Profile"
							}
						Default
							{$folderName = "winfsdata"}	
					}
				
				$i = $null
				$i = 0
				$freePath = $null
				While($i -lt 1000)
					{
						
						$potentialPath = $null
						$potentialPath = $archiveRootUNC + "\" + $sAMAccountName + "\" + $foldername + "-" + $i
						$pathTest = $null
						$pathTest = $false
						$pathTest = Test-Path $potentialPath
						If($pathTest -eq $true)
							{}
						Else
							{
								$freePath = $null
								$freePath = $potentialPath
								Break
							}
						$i++ 		
					}
			}
		
		If($freePath -eq $null -or $freePath -eq "" -or $freePath -eq $false)
			{
				$msg = "Warning`t`tCould not generate an archive path for this user."
				Throw-Warning $msg
				$failThisFunction = $true
			}
		
		$results = $freePath
		
		If($failThisFunction -eq $true)
			{$retval = $false}
		Else
			{$retval = $results}
		Return $retval
	}

Function Archive-Win7Profile($objUser)
	{
		$fail = $false
		$msg = "Action`t`tChecking for Win7 profile folders."
		Write-Out $msg "darkcyan" 4
		
		$profileShare = Read-Variable "profileShare"
		$pRoot = $null
		$pRoot = $profileShare + "\" + $sAMAccountName + ".V2"
		$msg = "Info`t`tWin7 Profile path generated as: """ + $pRoot + """."
		Write-Out $msg "darkcyan" 4
		If((Test-Path $pRoot) -eq $true -and (gci -recurse $pRoot) -ne $null)
			{
				$msg = "Info`t`tFound a Win7 profile."
				Write-Out $msg "darkcyan" 4
				#zip and archive the share
				
				#make a filename
				$destRoot = Read-Variable "archiveRootUNC"
				$destPath = (Trim-TrailingSlash $destRoot) + "\profiles\"
				$fileDate = $null
				$fileDate = get-date -uformat '%d-%m-%Y-%H%M'
				$destFName = $null
				$destFNameRoot = "profileArchive_win7_(" + $sAMAccountName + ")_" + $fileDate
				$i = 0
				While($true)
					{
						$test = $null
						$test = $false
						$test = Test-Path (($destPath + "\" + $destFNameRoot + "_" + $i + ".7z"))
						If($test -eq $false)
							{
								$destFName = $destFNameRoot + "_" + $i + ".7z"
								Break
							}
					}
						
				$source = $null
				$source = $pRoot
				$destFile = $null
				$destFile = (Trim-TrailingSlash $destPath) + "\" + $destFName
				
				$bZipped = $null
				$bZipped = Zip-Folder $source $destFile
				If($bZipped -eq $false)
					{
						$msg = "WARNING`t`tFailed to create the zip archive."
						Throw-Warning $msg
						$fail = $true
					}
				
				If($fail -eq $false)
					{
						$action = $null
						$action = Verify-ZipFile $source $destFile
						If($action -eq $true)
							{
								$msg = "Info`t`tZip file verified."
								Write-Out $msg "darkcyan" 3
							}
						Else
							{
								$msg = "WARNING`t`tFailed to verify zip file."
								Throw-Warning $msg
								$fail = $true
							}
					}	
			}
		Else
			{
				$msg = "Info`t`tNo Win7 profile found."
				Write-Out $msg "darkcyan" 4
				$blnXPProfile = $false
			}
		
		$retval = $null
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $true}
		
		Return $retval
	}

Function Archive-WinXPProfile($objUser)
	{
		$fail = $false
		$msg = "Action`t`tChecking for Win7 profile folders."
		Write-Out $msg "darkcyan" 4
		
		$profileShare = Read-Variable "profileShare"
		$pRoot = $null
		$pRoot = $profileShare + "\" + $sAMAccountName
		$msg = "Info`t`tWin7 Profile path generated as: """ + $pRoot + """."
		Write-Out $msg "darkcyan" 4
		If((Test-Path $pRoot) -eq $true -and (gci -recurse $pRoot) -ne $null)
			{
				$msg = "Info`t`tFound a WinXP profile."
				Write-Out $msg "darkcyan" 4
				
				#zip and archive the share
				
				#make a filename
				$destRoot = Read-Variable "archiveRootUNC"
				$destPath = (Trim-TrailingSlash $destRoot) + "\profiles\"
				$fileDate = $null
				$fileDate = get-date -uformat '%d-%m-%Y-%H%M'
				$destFName = $null
				$destFNameRoot = "profileArchive_winxp_(" + $sAMAccountName + ")_" + $fileDate
				$i = 0
				While($true)
					{
						$test = $null
						$test = $false
						$test = Test-Path (($destPath + "\" + $destFNameRoot + "_" + $i + ".7z"))
						If($test -eq $false)
							{
								$destFName = $destFNameRoot + "_" + $i + ".7z"
								Break
							}
					}
				
				$source = $null
				$source = $pRoot
				$destFile = $null
				$destFile = (Trim-TrailingSlash $destPath) + "\" + $destFName
				
				$bZipped = $null
				$bZipped = Zip-Folder $source $destFile
				If($bZipped -eq $false)
					{
						$msg = "WARNING`t`tFailed to create the zip archive."
						Throw-Warning $msg
						$fail = $true
					}
				
				If($fail -eq $false)
					{
						$action = $null
						$action = Verify-ZipFile $source $destFile
						If($action -eq $true)
							{
								$msg = "Info`t`tZip file verified."
								Write-Out $msg "darkcyan" 3
							}
						Else
							{
								$msg = "WARNING`t`tFailed to verify zip file."
								Throw-Warning $msg
								$fail = $true
							}
					}
			}
		Else
			{
				$msg = "Info`t`tNo WinXP profile found."
				Write-Out $msg "darkcyan" 4
				$blnXPProfile = $false
			}
		
		$retval = $null
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $true}
		
		Return $retval
	}

Function Archive-ProfileFolders($objUser)
	{
		$results = $null
		$fail = $false
		
		$sAMAccountName = $null
		$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
		
		$action = $null
		$action = Archive-Win7Profile $objUser
		If($action -eq $true)
			{
				$msg = "INFO`t`tWindows 7 Profile archived successfully."
				Write-Out $msg "darkcyan" 4
			}
		Else
			{
				$msg = "WARNING`tFailed to archive Windows 7 profile."
				Throw-Warning $msg
				$fail = $true
			}
		
		If($fail -eq $false)
			{
				$action = $null
				$action = Archive-WinXPProfile $objUser
				If($action -eq $true)
					{
						$msg = "INFO`t`tWindows XP Profile archived successfully."
						Write-Out $msg "darkcyan" 4
					}
				Else
					{
						$msg = "WARNING`tFailed to archive Windows XP profile."
						Throw-Warning $msg
						$fail = $true
					}
			}
		
		If($fail -eq $true)
			{$results = $false}
		Else
			{$results = $true}
		Return $results
	}

Function Archive-HomeShareData($objUser)
	{
		$fail = $false
		
		$msg = "Action`t`tChecking for a home file share."
		Write-Out $msg "darkcyan" 4
		$sharePath = $null
		$i = $null
		$i = 0
		While($sharePath -eq $null -and $i -le 10)
			{
				$homeFS = Get-UserHomeFS $objUser
					
				$sAMAccountName = $null
				$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
				$shareName = $null
				$shareName = $sAMAccountName + "$"
				$sharePath = $null
				$sharePath = Get-SharePath $shareName $homeFS
				If($sharePath -eq $null -or $sharePath -eq "" -or $sharePath -eq $false)
					{
						#write-host -f yellow "debug`t(f)Archive-WinFSData`tsamaccountName: $sAMAccountName`n`t`t`t`tshareName: $shareName"
						$i++
						Sleep -s 1
						Write-Host -f green -nonewline "."
					}
				Else
					{
						#write-host -f yellow "debug`t(f)Archive-WinFSData`tsamaccountName: $sAMAccountName`n`t`t`t`tshareName: $shareName"
						Break
					}
					
			}
		
		$sourcePath = Convert-SharePathToUNCPath $sharePath $homeFS
		If($sourcePath -eq $null -or $sourcePath -eq $false -or $sourcePath -eq "")
			{
				$msg = "Warning`t`tCould not read the sharePath for this user's home drive share."
				Throw-Warning $msg
				$fail = $true
			}
		Else
			{
				$msg = "Info`t`tSource folder read as """ + $sourcePath + """."
				Write-Out $msg "darkcyan" 4
				$arrSourcePaths += $sourcePath
			}
		
			
		#zip and archive the share
		If($fail -eq $false)
			{
				$msg = "Action`t`tZipping home folder."
				Write-Out $msg "darkcyan" 4
				#make a filename
				$destRoot = Read-Variable "archiveRootUNC"
				$destPath = (Trim-TrailingSlash $destRoot) + "\homes\"
				$fileDate = $null
				$fileDate = get-date -uformat '%d-%m-%Y-%H%M'
				$destFName = $null
				$destFNameRoot = "homeArchive_(" + $sAMAccountName + ")_" + $fileDate
				$i = 0
				While($true)
					{
						$test = $null
						$test = $false
						$test = Test-Path (($destPath + "\" + $destFNameRoot + "_" + $i + ".7z"))
						If($test -eq $false)
							{
								$destFName = $destFNameRoot + "_" + $i + ".7z"
								Break
							}
					}
				
				$source = $null
				$source = $sourcePath
				$destFile = $null
				$destFile = (Trim-TrailingSlash $destPath) + "\" + $destFName
				$bSkipped = $false
				If((gci -recurse -force $source).count -gt 1)
					{
						$bZipped = $null
						$bZipped = Zip-Folder $source $destFile
						If($bZipped -eq $false)
							{
								$msg = "WARNING`t`tFailed to create the zip archive."
								Throw-Warning $msg
								$fail = $true
							}
					}
				Else
					{
						$msg = "Info`t`tThis user's homedrive is blank. Skipping archive."
						Write-Out $msg "darkcyan" 3
						$fileMsg = "No content was found at the homedrive location """ + $source + """ on """ + $fileDate + """."
						$destFile = ($destfile.Substring(0,($destFile.Length)-2)) + "txt"
						$fileMsg | Out-File $destFile
						$bSkipped = $true
					}
			}
		
		#verify
		If($fail -eq $false -and $bSkipped -eq $false)
			{
				$action = $null
				$action = Verify-ZipFile $source $destFile
				If($action -eq $true)
					{
						$msg = "Info`t`tZip file verified."
						Write-Out $msg "darkcyan" 3
					}
				Else
					{
						$msg = "WARNING`t`tFailed to verify zip file."
						Throw-Warning $msg
						$fail = $true
					}
			}
		
		If($fail -eq $true)
			{$results = $false}
		Else
			{$results = $true}
		Return $results
	}

Function Archive-WinFSData($objUser)
	{
		$fail = $null
		$fail = $false
		$results = $null
		$results = $false
		
		$dn = $null
		$dn = Pull-LDAPAttribute $distinguishedName
		$sAMAccountName = $null
		$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
		
		$blnXPProfile = $null
		$blnXPProfile = $false
		$bln7Profile = $null
		$bln7Profile = $false
		
		$blnContinue = $null
		$blnContinue = $true
		
		$arrSourcePaths = $null
		$arrSourcePaths = @()
		
		#profile folders?
		If($fail -eq $false)
			{
				$action = $null
				$action = Archive-ProfileFolders $objUser
				If($action -eq $false)
					{$fail = $true}
			}
		
		#read source folder
		If($fail -eq $false)
			{
				$action = $null
				$action = Archive-HomeShareData $objUser
				If($action -eq $false)
					{$fail = $true}
			}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $true}
		Return $retval
	}

Function Archive-Profile($objUser)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		$results = $null
		
		$dn = $null
		$dn = Pull-LDAPAttribute $distinguishedName
		$sAMAccountName = $null
		$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
		
		$blnXPProfile = $null
		$blnXPProfile = $false
		$bln7Profile = $null
		$bln7Profile = $false
		
		$blnContinue = $null
		$blnContinue = $true
		
		$arrSourcePaths = $null
		$arrSourcePaths = @()
		
		#profile folders?
		If($failThisFunction -eq $false)
			{
				$msg = "Action`t`tChecking for profile folders."
				Write-Out $msg "darkcyan" 4
				
				$fileserver = $null
				$fileserver = Read-Variable "fileserver"
				$profileShare = Read-Variable "profileShare"
				
				$XPprofileRoot = $null
				$XPprofileRoot = $profileShare + "\" + $sAMAccountName
				$msg = "Info`t`tWinXP Profile path generated as: """ + $XPProfileRoot + """."
				Write-Out $msg "darkcyan" 4
				If((Test-Path $XPprofileRoot) -eq $true)
					{
						$msg = "Info`t`tFound a WinXP profile."
						Write-Out $msg "darkcyan" 4
						$blnXPProfile = $true
						$arrSourcePaths += $XPprofileRoot
					}
				Else
					{
						$msg = "Info`t`tNo XP profile found."
						Write-Out $msg "darkcyan" 4
						$blnXPProfile = $false
					}
				
				$Win7ProfileRoot = $null
				$Win7ProfileRoot = $profileShare + "\" + $sAMAccountName + ".V2"
				$msg = "Info`t`tWin7 Profile path generated as: """ + $Win7ProfileRoot + """."
				Write-Out $msg "darkcyan" 4
				If((Test-Path $Win7ProfileRoot) -eq $true)
					{
						$msg = "Info`t`tFound a Win7 profile."
						Write-Out $msg "darkcyan" 4
						$Win7ProfileRoot = $true
						$arrSourcePaths += $Win7ProfileRoot
					}
				Else
					{
						$msg = "Info`t`tNo Win7 profile found."
						Write-Out $msg "darkcyan" 4
						$Win7ProfileRoot = $false
					}
				
				If($blnXPProfile -eq $true -or $blnWin7Profile -eq $true)
					{$blnContinue = $true}
				Else
					{
						$msg = "Info`t`tNo profiles found, skipping this user."
						Write-Out $msg "darkcyan" 4
						$results = $true
						$blnContinue = $false
					}
			}
		
		#generate dest root folder
		If($failThisFunction -eq $false -and $blnContinue -eq $true)
			{
				$msg = "Action`t`tGenerating the destination root folder."
				Write-Out $msg "darkcyan" 4
				$archiveRootUNC = $null
				$archiveRootUNC = Read-Variable "archiveRootUNC"
				$archiveRootUNC = Trim-TrailingSlash $archiveRootUNC
				$sAMAccountName = $null
				$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
				$destRootPath = $null
				$destRootPath = $archiveRootUNC + "\" + $sAMAccountName
				If($destRootPath -eq $null -or $destRootPath -eq $false -or $destRootPath -eq "")
						{
							$msg = "Error`t`tCould not generate the destination root folder."
							Throw-Warning $msg
							$failThisFunction = $true
						}
				Else
						{
							$msg = "Info`t`tDestination root folder generated as """ + $destRootPath + """."
							Write-Out $msg "darkcyan" 4
						}
			}
		
		#create the destination root folder
		If($failThisFunction -eq $false)
			{
				$msg = "Action`t`tCreating the destination root folder."
				Write-Out $msg "darkcyan" 4
				$blnFolderCreated = $null
				$blnFolderCreated = Create-Folder $destRootPath
				If($blnFolderCreated -eq $true)
					{
						$msg = "Info`t`tDestination root folder created."
						Write-Out $msg "darkcyan" 4
					}
				Else
					{
						$warningMsg = "Error`t`tCould not create the destination root folder."
						Throw-Warning $warningMsg
						$failThisFunction = $true
					}
			}
		
		If($failThisFunction -eq $false -and $blnContinue -eq $true)
			{
				$strPath = $null
				Foreach($strPath in $arrSourcePaths)
					{
						
						#check source folder for children in XP path
						If($failThisFunction -eq $false)
							{
								$msg = "Action`t`tChecking for child items inside the source folder."
								Write-Out $msg "darkcyan" 4
								$children = $null
								$children = GCI $sourcePath
								$blnFoundKids = $null
								If($children -eq $null -or $children -eq "")
									{
										$msg = "Info`t`tNo child items found, skipping archival."
										Write-Out $msg "darkcyan" 4
										$blnFoundKids = $false
									}
								Else
									{
										$msg = "Info`t`tChild items found, proceeding with archival."
										Write-Out $msg "darkcyan" 4
										$blnFoundKids = $true
									}
							}
						
						#write file if no kids
						If($failThisFunction -eq $false -and $blnFoundKids -eq $false)
							{
								$msg = "Action`t`tWriting a 'nokids' file to the destination path."
								Write-Out $msg "darkcyan" 4
								$fullFileName = $destRootPath + "\" + "profiledata-readme.txt"
								$scriptUser = $null
								$scriptUser = $env:username
								$curDate = $null
								$curDate = get-date -uformat '%d%m%Y-%H%M-%S'
								
								$msgs = $null
								$msgs = @()
								$msgs += "WinFS Data Archival Script run by """ + $scriptUser + """ on """ + $curDate + """ ."
								$msgs += "`tNo data was found in the profile folder: """ + $sourcePath + """."
								$msgs | out-file -append $fullFileName
								$msgs = $null
								If((Test-Path $fullFileName) -eq $false)
									{
										$msg = "Warning`t`tCould not write the 'nokids' file: """ + $fullFileName + """."
										Throw-Warning $msg
										$failThisFunction = $true
									}
							}
						
						#generate dest folder
						If($failThisFunction -eq $false -and $blnFoundKids -eq $true)
							{
								$msg = "Action`t`tGenerating the destination folder."
								Write-Out $msg "darkcyan" 4
								$destPath = $null
								$destPath = Build-ArchiveFolderDestinationPath $objUser
								If($destPath -eq $null -or $destPath -eq $false -or $destPath -eq "")
										{
											$msg = "Error`t`tCould not generate the destination folder."
											Throw-Warning $msg
											$failThisFunction = $true
										}
								Else
										{
											$msg = "Info`t`tDestination folder generated as """ + $destPath + """."
											Write-Out $msg "darkcyan" 4
										}
							}
						
						#create the destination folder
						If($failThisFunction -eq $false -and $blnFoundKids -eq $true)
							{
								$msg = "Action`t`tCreating the destination folder."
								Write-Out $msg "darkcyan" 4
								$blnFolderCreated = $null
								$blnFolderCreated = Create-Folder $destPath
								If($blnFolderCreated -eq $true)
									{
										$msg = "Info`t`tDestination folder created."
										Write-Out $msg "darkcyan" 4
									}
								Else
									{
										$warningMsg = "Error`t`tCould not create the destination folder."
										Throw-Warning $warningMsg
										$failThisFunction = $true
									}
							}
						
						#Migrate-Folder
						If($failThisFunction -eq $false -and $blnFoundKids -eq $true)
							{
								$msg = "Action`t`tMigrating share data."
								Write-Out $msg "darkcyan" 4
								$results = $null
								$results = $false
								$results = Migrate-Folder $sourcePath $destPath $objUser
								If($results -eq $true)
									{
										$msg = "INFO`t`tData migrated successfully."
										Write-Out $msg "darkcyan" 4
									}
								Else
									{
										$warningMsg = "Warning`t`tData migration failed."
										Throw-Warning $warningMsg
										$failThisFunction = $true
									}
							}
					}
			}
		
		If($failThisFunction -eq $true)
			{$retval = $false}
		Else
			{$retval = $true}
		Return $retval
	}

Function AddToGroup-DenyLogins($objUser)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		$results = $null
		
		$DenyLoginsGroupCN = $null
		$DenyLoginsGroupCN = Read-Variable "DenyLoginsGroupCN"
		$DenyLoginsGroupDN = $null
		$DenyLoginsGroupDN = Get-DNbyCN $DenyLoginsGroupCN
		If($denyLoginsGroupDN -eq $null -or $denyLoginsGroupDN -eq $false -or $denyLoginsGroupDN -eq "")
			{
				$msg = "Warning`t`tCould not bind to the deny logins group """ + $denyLoginsGroupCN + """."
				Throw-Warning $msg
				$failThisFunction = $true
			}
		Else
			{
				$msg = "Info`t`tDeny Logins Group CN read as: """ + $denyLoginsGroupCN + """."
				Write-Out $msg "darkcyan" 4
			}
		
		If($failThisFunction -eq $false)
			{
				$msg = "Action`t`tAdding user to the group."
				Write-Out $msg "darkcyan" 4
				$strUserDN = $null
				$strUserDN = Pull-LDAPAttribute $objUser "distinguishedName"				
				$blnAdded = $null
				$blnAdded = $false
				$blnAdded = Add-ToGroup $strUserDN $DenyLoginsGroupDN
				If($blnAdded -eq $true)
					{
						$msg = "Info`t`tUser added to the group successfully."
						Write-Out $msg "darkcyan" 4
					}
				Else
					{
						$msg = "Warning`t`tCould not add the user to the group."
						Throw-Warning $msg
						$failThisFunction = $true
					}
				$results = $blnAdded
			}
		
		
		If($failThisFunction -eq $true)
			{$retval = $false}
		Else
			{$retval = $results}
		Return $retval
	}

Function RemoveFromGroup-ReadyForWinArchival($objUser) ##MODIFY
	{
		$failThisFunction = $null
		$failThisFunction = $false
		$results = $null
		
		$groupCN = $null
		$groupCN = Read-Variable "ReadyForWindowsArchiveGroupCN"
		$groupDN = $null
		$groupDN = Get-DNbyCN $groupCN
		If($groupDN -eq $null -or $groupDN -eq $false -or $groupDN -eq "")
			{
				$msg = "Warning`t`tCould not bind to the group """ + $groupCN + """."
				Throw-Warning $msg
				$failThisFunction = $true
			}
		Else
			{
				$msg = "Info`t`rGroup CN read as: """ + $groupCN + """."
				Write-Out $msg "darkcyan" 4
			}
		
		If($failThisFunction -eq $false)
			{
				$msg =  "Action`t`tChecking user's group membership"
				Write-Out $msg "darkcyan" 4
				
				$blnMember = $null
				$blnMember = $false
				$blnMember = Check-IsMemberOfGroup $strUserDN $groupDN
				If($blnMember -eq $false)
					{
						$msg = "Info`t`tUser is -not- a member of the group."
						Write-Out $msg "darkcyan" 4
						$results = $true
					}
				Else
					{
						$results = $false
						$msg = "Info`t`tUser is a member of the group."
						Write-Out $msg "darkcyan" 4
#						$msg = "Action`t`tRemoving user from the group."
#						Write-Out $msg "darkcyan" 4
						$strUserDN = $null
						$strUserDN = Pull-LDAPAttribute $objUser "distinguishedName"				
						$blnRemoved = $null
						$blnRemoved = $false
						$blnRemoved = Remove-FromGroup $strUserDN $groupDN
						#check the work
						$blnMemberTwo = $null
						$blnMemberTwo = $false
						$blnMemberTwo = Check-IsMemberOfGroup $strUserDN $groupDN
						If($blnMemberTwo -eq $false)
							{
#								$msg = "Info`t`tUser removed from the group successfully."
#								Write-Out $msg "darkcyan" 4
								$results = $true
							}
						Else
							{
								$msg = "Warning`t`tCould not remove the user from the group."
								Throw-Warning $msg
								$failThisFunction = $true
								$results = $false
							}
					}
			}
		
		If($results -eq $null -or $results -eq "")
			{$results = $false}
		
		If($failThisFunction -eq $true)
			{$retval = $false}
		Else
			{$retval = $results}
		Return $retval
	}

Function AddToGroup-ReadyForWinArchival($objUser)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		$results = $null
		
		$groupCN = $null
		$groupCN = Read-Variable "ReadyForWindowsArchiveGroupCN"
		$groupDN = $null
		$groupDN = Get-DNbyCN $groupCN
		If($groupDN -eq $null -or $groupDN -eq $false -or $groupDN -eq "")
			{
				$msg = "Warning`t`tCould not bind to the group """ + $groupCN + """."
				Throw-Warning $msg
				$failThisFunction = $true
			}
		Else
			{
				$msg = "Info`t`tGroup CN read as: """ + $groupCN + """."
				Write-Out $msg "darkcyan" 4
			}
		
		If($failThisFunction -eq $false)
			{
				$msg = "Action`t`tAdding user to the group."
				Write-Out $msg "darkcyan" 4
				$strUserDN = $null
				$strUserDN = Pull-LDAPAttribute $objUser "distinguishedName"				
				$blnAdded = $null
				$blnAdded = $false
				$blnAdded = Add-ToGroup $strUserDN $groupDN
				If($blnAdded -eq $true)
					{
						$msg = "Info`t`tUser added to the group successfully."
						Write-Out $msg "darkcyan" 4
					}
				Else
					{
						$msg = "Warning`t`tCould not add the user to the group."
						Throw-Warning $msg
						$failThisFunction = $true
					}
				$results = $blnAdded
			}
		
		
		If($failThisFunction -eq $true)
			{$retval = $false}
		Else
			{$retval = $results}
		Return $retval
	}

Function AddToGroup-WindowsArchiveDone($objUser)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		$results = $null
		
		$groupCN = $null
		$groupCN = Read-Variable "WindowsArchiveDoneGroupCN"
		$groupDN = $null
		$groupDN = Get-DNbyCN $groupCN
		If($groupDN -eq $null -or $groupDN -eq $false -or $groupDN -eq "")
			{
				$msg = "Warning`t`tCould not bind to the group """ + $groupCN + """."
				Throw-Warning $msg
				$failThisFunction = $true
			}
		Else
			{
				$msg = "Info`t`tGroup CN read as: """ + $groupCN + """."
				Write-Out $msg "darkcyan" 4
			}
		
		If($failThisFunction -eq $false)
			{
				$msg = "Action`t`tAdding user to the group."
				Write-Out $msg "darkcyan" 4
				$strUserDN = $null
				$strUserDN = Pull-LDAPAttribute $objUser "distinguishedName"				
				$blnAdded = $null
				$blnAdded = $false
				$blnAdded = Add-ToGroup $strUserDN $groupDN
				If($blnAdded -eq $true)
					{
						$msg = "Info`t`tUser added to the group successfully."
						Write-Out $msg "darkcyan" 4
					}
				Else
					{
						$msg = "Warning`t`tCould not add the user to the group."
						Throw-Warning $msg
						$failThisFunction = $true
					}
				$results = $blnAdded
			}
		
		
		If($failThisFunction -eq $true)
			{$retval = $false}
		Else
			{$retval = $results}
		Return $retval
	}

Function AddToGroup-ReadytoDelete($objUser)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		$results = $null
		
		$groupCN = $null
		$groupCN = Read-Variable "deletionGroupCN"
		$groupDN = $null
		$groupDN = Get-DNbyCN $groupCN
		If($groupDN -eq $null -or $groupDN -eq $false -or $groupDN -eq "")
			{
				$msg = "Warning`t`tCould not bind to the group """ + $groupCN + """."
				Throw-Warning $msg
				$failThisFunction = $true
			}
		Else
			{
				$msg = "Info`t`tGroup CN read as: """ + $groupCN + """."
				Write-Out $msg "darkcyan" 4
			}
		
		If($failThisFunction -eq $false)
			{
				$msg = "Action`t`tAdding user to the group."
				Write-Out $msg "darkcyan" 4
				$strUserDN = $null
				$strUserDN = Pull-LDAPAttribute $objUser "distinguishedName"				
				$blnAdded = $null
				$blnAdded = $false
				$blnAdded = Add-ToGroup $strUserDN $groupDN
				If($blnAdded -eq $true)
					{
						$msg = "Info`t`tUser added to the group successfully."
						Write-Out $msg "darkcyan" 4
					}
				Else
					{
						$msg = "Warning`t`tCould not add the user to the group."
						Throw-Warning $msg
						$failThisFunction = $true
					}
				$results = $blnAdded
			}
		
		
		If($failThisFunction -eq $true)
			{$retval = $false}
		Else
			{$retval = $results}
		Return $retval
	}

Function AddToGroup-ReadyForLinuxArchival($objUser)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		$results = $null
		
		$groupCN = $null
		$groupCN = Read-Variable "ReadyForLinuxArchiveGroupCN"
		$groupDN = $null
		$groupDN = Get-DNbyCN $groupCN
		If($groupDN -eq $null -or $groupDN -eq $false -or $groupDN -eq "")
			{
				$msg = "Warning`t`tCould not bind to the group """ + $groupCN + """."
				Throw-Warning $msg
				$failThisFunction = $true
			}
		Else
			{
				$msg = "Info`t`tGroup CN read as: """ + $groupCN + """."
				Write-Out $msg "darkcyan" 4
			}
		
		If($failThisFunction -eq $false)
			{
				$msg = "Action`t`tAdding user to the group."
				Write-Out $msg "darkcyan" 4
				$strUserDN = $null
				$strUserDN = Pull-LDAPAttribute $objUser "distinguishedName"				
				$blnAdded = $null
				$blnAdded = $false
				$blnAdded = Add-ToGroup $strUserDN $groupDN
				If($blnAdded -eq $true)
					{
						$msg = "Info`t`tUser added to the group successfully."
						Write-Out $msg "darkcyan" 4
					}
				Else
					{
						$msg = "Warning`t`tCould not add the user to the group."
						Throw-Warning $msg
						$failThisFunction = $true
					}
				$results = $blnAdded
			}
		
		
		If($failThisFunction -eq $true)
			{$retval = $false}
		Else
			{$retval = $results}
		Return $retval
	}

Function AddToGroup-NeedsExpirationDate($objUser)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		$results = $null
		
		$groupCN = $null
		$groupCN = Read-ArchVariable "NeedsExpirationDateGroupCN"
		$groupDN = $null
		$groupDN = Get-DNbyCN $groupCN
		If($groupDN -eq $null -or $groupDN -eq $false -or $groupDN -eq "")
			{
				$msg = "Warning`t`tCould not bind to the group """ + $groupCN + """."
				Throw-Warning $msg
				$failThisFunction = $true
			}
		Else
			{
				$msg = "Info`t`tGroup CN read as: """ + $groupCN + """."
				Write-Out $msg "darkcyan" 4
			}
		
		If($failThisFunction -eq $false)
			{
				$msg = "Action`t`tAdding user to the group."
				Write-Out $msg "darkcyan" 4
				$strUserDN = $null
				$strUserDN = Pull-LDAPAttribute $objUser "distinguishedName"				
				$blnAdded = $null
				$blnAdded = $false
				$blnAdded = Add-ToGroup $strUserDN $groupDN
				If($blnAdded -eq $true)
					{
						$msg = "Info`t`tUser added to the group successfully."
						Write-Out $msg "darkcyan" 4
					}
				Else
					{
						$msg = "Warning`t`tCould not add the user to the group."
						Throw-Warning $msg
						$failThisFunction = $true
					}
				$results = $blnAdded
			}
		
		
		If($failThisFunction -eq $true)
			{$retval = $false}
		Else
			{$retval = $results}
		Return $retval
	}

Function Export-LDAPRecord($objUser)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		$results = $null
		
		$sAMAccountName = $null
		$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
		$curDate = $null
		$curDate = get-date -uformat '%d%m%Y-%H%M-%S'
		
		#generate temp file name \ path
		If($failThisFunction -eq $false)
			{
				$dc = $null
				$dc = Read-ArchVariable "domainController"
				$i = $null
				$i = 0
				$tempLocalFilename = $null
				While($i -lt 1000)
					{
						$potentialFilename = $null
						$potentialFilename = "\\" + $dc + "\c$\workingtemp\" + "ldif-" + $sAMAccountName + "-" + $i + ".ldf"
						$pathTest = $null
						$pathTest = $false
						$pathTest = Test-Path $potentialFileName
						If($pathTest -eq $true)
							{}
						Else
							{
								$tempUNCFilename = $null
								$tempUNCFilename = $potentialFilename
								Break
							}
						$i++ 		
					}
				If($tempUNCFilename -eq $null)
					{
						$msg = "Warning`t`tCould not generate the ldif target temporary filename."
						Throw-Warning $msg
						$failThisFunction = $true
					}
				Else
					{
						$tempLocalfilename = $null
						$tempLocalfilename = Convert-UNCPathtoSharePath $tempUNCFilename $dc
						#write-host -f yellow "DEBUG`t(f)Export-LDAPRecord`ttempLocalFilename: $tempLocalfilename"
						$msg = "Info`t`tLDIF Temporary filename generated as """ + $tempUNCFilename + """."
						Write-Out $msg "darkcyan" 4
					}
			}
		
		#generate final file name \ path
		If($failThisFunction -eq $false)
			{
				$archiveRootUNC = $null
				$archiveRootUNC = Read-Variable "archiveRootUNC"
				$i = $null
				$i = 0
				$fileName = $null
				While($i -lt 1000)
					{
						$potentialFileName = $null
						$potentialFileName = $archiveRootUNC + "\" + $sAMAccountName + "\" + "ldif-" + $sAMAccountName + "-" + $i + ".ldf"
						$pathTest = $null
						$pathTest = $false
						$pathTest = Test-Path $potentialFileName
						If($pathTest -eq $true)
							{}
						Else
							{
								$fileName = $null
								$fileName = $potentialFileName
								Break
							}
						$i++ 		
					}
				If($fileName -eq $null)
					{
						$msg = "Warning`t`tCould not generate the ldif target filename."
						Throw-Warning $msg
						$failThisFunction = $true
					}
				Else
					{
						$msg = "Info`t`tLDIF Filename generated as """ + $fileName + """."
						Write-Out $msg "darkcyan" 4
					}
			}
		
		#construct the remote command
		If($failThisFunction -eq $false)
			{
				$msg = "Action`t`tGenerating the remote ldifde command."
				Write-Out $msg "darkcyan" 4
				
				#generate ldapFilter
				$filter = $null
				$filter = "(sAMAccountName=" + $sAMAccountName + ")"
				
				$strSlash = $null
				$strSlash = "\"
				$strSpace = $null
				$strSpace = " "
				
				$pathToLDIFDE = $null
				$pathToLDIFDE = Read-ArchVariable "pathToLDIFDE"
				#$pathToLDIFDE = Add-TrailingSlash $pathToLDIFDE
				
				$strRemoteCommand = $null
				#$strRemoteCommand = $pathToLDIFDE + $strSlash + "ldifde.exe -f" + $strSpace + $fileName + $strSpace + "-r" + $strSpace + $filter
				$strRemoteCommand = $pathToLDIFDE + " -f " + $tempLocalfilename + " -r " + $filter
				##ldifde.exe -f $outFileName -r $ldapFilter (do I need anything more to include all attributes???)
				
				$msg = "Info`t`tRemote command generated as """ + $strRemoteCommand + """."
				Write-Out $msg "darkcyan" 4
			}
		
		#run the command
		If($failThisFunction -eq $false)
			{
				$domainController = $null
				$domainController = Read-ArchVariable "domainController"
				
				$msg = "Action`t`tRunning the remote command on server """ + $domainController + """."
				Write-Out $msg "darkcyan" 4
				$blnAction = $null
				$blnAction = $false
				$blnAction = Run-RemoteCommand $domainController $strRemoteCommand
				If($blnAction -eq 0){$results = $true}
				Else{$blnAction = $false}
				
				#did it work?
				$msg = "Action`t`tLooking for the LDIF file on the remote system at """ + $tempUNCFilename + """."
				Write-Out $msg "darkcyan" 4
				$i = $null
				$i = 0
				While($i -lt 15)
					{
						$blnAction = $null
						$blnAction = $false
						$blnAction = Test-Path $tempUNCFilename
						If($blnAction -eq $true)
							{Break}
						Else
							{
								write-host -f green "." -nonewline
								Sleep -s 1
							}
						$i++
					}
				Write-Host "`n"
				
				If((Test-Path $tempUNCFilename) -eq $true)
					{
						$msg = "Info`t`tThe LDIF file was generated properly."
						Write-Out $msg "darkcyan" 4
					}
				Else
					{
						$msg = "Info`t`tThe LDIF file was -not- generated properly."
						Throw-Warning $msg
						$failThisFunction = $true
					}
			}
		
		#copy the file to archived root
		If($failThisFunction -eq $false)
			{
				$strSource = $tempUNCFileName
				$strDest = $filename
				
				$destRoot = $archiveRootUNC + "\" + $sAMAccountName
				$msg = "Action`t`tChecking existance of the target folder: """ + $destRoot + """."
				Write-Out $msg "darkcyan" 4
				If((Test-Path $destRoot) -eq $true)
					{
						$msg = "Info`t`tDestination path exists."
						Write-Out $msg "darkcyan" 4
					}
				Else
					{
						$msg = "Action`t`tCreating destination path."
						Write-Out $msg "darkcyan" 4
						$blnAction = $null
						$blnAction = Create-Folder $destRoot
						$blnAction = $null
						If((Test-Path $destRoot) -eq $true)
							{
								$msg = "Info`t`tDestination created successfully."
								Write-Out $msg "darkcyan" 4
							}
						Else
							{
								$msg = "Warning`t`tCould not create destination folder for LDIF file."
								Throw-Warning $msg
								$failThisFunction = $true
							}
					}
				
				$msg = "Action`t`tMoving the ldif file."
				Write-Out $msg "darkcyan" 4
				$msg = "Info`t`t`tFrom: """ + $strSource + """."
				Write-Out $msg "darkcyan" 4
				$msg = "Info`t`t`tTo: """ + $strDest + """."
				Write-Out $msg "darkcyan" 4
				
				If((Test-Path $strDest) -eq $true)
					{
						$msg = "Warning`t`tThere is already a destination file in place."
						Throw-Warning $msg
						$failThisFunction = $true
					}
				Else
					{
						$blnAction = $null
						$blnAction = $false
						$blnAction = Move-Item $strSource $strDest
						If((Test-Path $strDest) -eq $true)
							{
								$msg = "Info`t`tFile moved successfully."
								Write-Out $msg "darkcyan" 4
							}
						Else
							{
								$msg = "Warning`t`tCould not move the file."
								Throw-Warning $msg
								$failThisFunction = $true
							}
					}
			}
		
		If($failThisFunction -eq $false)
			{
				$msg = "Action`t`tVerifing the ldif export file."
				Write-Out $msg "darkcyan" 4
				$results = $null
				$results = $false
				$results = Verify-LDIFRecord $filename $objUser
			}
		
		If($failThisFunction -eq $true)
			{$retval = $false}
		Else
			{$retval = $results}
		Return $retval
	}

Function Check-LineAgainstAttribute($attribute,$line,$objUser)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		$results = $null
		$results = $false
		
		If($attribute -eq $null -or $line -eq $null -or $objUser -eq $null)
			{
				$msg = "Debug`t(f)Check-LineAgainstAttribute was passed a blank variable."
				Throw-Warning $msg
				$failThisFunction = $true
			}
		
		If($failThisFunction -eq $false)
			{
				$userAttribute = Pull-LDAPAttribute $objUser $attribute
				$msg = "Info`t`t`tuserAttribtute: """ + $userAttribute + """."
				Write-Out $msg "darkcyan" 4
				$lineAttribute = $line -replace(($attribute + ": "),"")
				$msg = "Info`t`t`tlineAttribute: """ + $lineAttribute + """."
				Write-Out $msg "darkcyan" 4
				If($userAttribute -eq $lineAttribute)
					{$results = $true}
				Else
					{$failThisFunction = $true}
			}
		
		If($failThisFunction -eq $true)
			{$retval = $false}
		Else
			{$retval = $results}
		Return $retval
	}

Function Verify-LDIFRecord($ldifFilePath,$objUser)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		$results = $null
		
		If($ldifFilePath -eq $null)
			{
				$msg = "Warning`t`t(f)Verify-LDIFRecord was not passed an LDIF record to verify."
				Throw-Warning $msg
				$failThisFunction = $true
			}
		ElseIf((Test-Path $ldifFilePath) -eq $null)
			{
				$msg = "Warning`t`t(f)Verify-LDIFRecord could not open the LDIF record to verify: """ + $ldifFilePath + """."
				Throw-Warning $msg
				$failThisFunction = $true
			}
		
		#Open the file and look for a few key attributes to match up
		$arrLDIFFile = $null
		$arrLDIFFile = Get-Content $ldifFilePath
		$arrAttributesToCheck = $null
		$arrAttributesToCheck = Read-ArchVariable "LDIFattributesToVerify"
		$intAttributesChecked = $null
		$intAttributesChecked = 0
		Foreach($line in $arrLDIFFile)
			{
				Foreach($attribute in $arrAttributesToCheck)
					{
						If($line -like ($attribute + ":*"))
							{
								$msg = "Action`t`tChecking the attribute: """ + $attribute + """."
								Write-Out $msg "darkcyan" 4
								$blnAttributeCheck = $null
								$blnAttributeCheck = $false
								$blnAttributeCheck = Check-LineAgainstAttribute $attribute $line $objUser
								If($blnAttributecheck -eq $true)
									{
										$msg = "Info`t`tAttribute passed checks."
										Write-Out $msg "darkcyan" 4
										$intAttributesChecked++
									}
								Else
									{
										$msg = "Info`t`tAttribute failed to pass checks!"
										Throw-Warning $msg
										$failThisFunction = $true
										Break
									}
							}
						If($failThisFunction -eq $true)
							{Break}
					}
				
				If($failThisFunction -eq $true)
					{Break}
			}
		
		If($failThisFunction -eq $false)
			{
				If($intAttributesChecked -lt 3)
					{
						$msg = "Warning`t`tLess than 3 attributes were checked, failing the verification."
						Throw-Warning $msg
						$failThisFunction = $true
					}
			}
		
		If($failThisFunction -eq $true)
			{$retval = $false}
		Else
			{$retval = $results}
		Return $retval
	}

Function Disable-Account($objUser)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		$results = $null
		
		$msg = "Action`t`tChecking the status of the account."
		Write-Out $msg "darkcyan" 4
		$blnEnabled = $null
		$blnEnabled = $false
		$blnEnabled = Check-AccountIsEnabled $objUser
		If($blnEnabled -eq $true)
			{
				$results = $false
				$msg = "Info`t`tAccount is currently enabled."
				Write-Out $msg "darkcyan" 4
				$msg = "Action`t`tDisabling the account."
				Write-Out $msg "darkcyan" 4
				$action = $null
				$action = Put-LDAPAttribute $objUser "userAccountControl" 514	
				$action = $null
			}
		Else
			{
				$msg = "Info`t`tAccount is already disabled."
				Write-Out $msg "darkcyan" 4
				$results = $true
			}
		
		##check the work
		$blnEnabled = $null
		$blnEnabled = $false
		$blnEnabled = Check-AccountIsEnabled $objUser
		If($blnEnabled -eq $true)
			{
				$msg = "Warning`tThe script could not disable the account for an unknown reason."
				Throw-Warning $msg
				$failThisFunction = $true
				$results = $false
			}
		Else
			{
				$msg = "Info`tThe account was disabled successfully."
				Write-Out $msg "darkcyan" 4
				$results = $true
			}
		
		If($failThisFunction -eq $true)
			{$retval = $false}
		Else
			{$retval = $results}
		Return $retval
	}	


####SWIPED FROM Create-Accounts-b29!!!
Function Check-AccountIsEnabled($objUser) #SkipECC
	{
		$objUserDN = $null
		$objUserDN = Pull-LDAPAttribute $objUser "distinguishedName"
		$objUser = $null
		$objUser = [adsi]("LDAP://" + $objUserDN)
		
		$UAC_1 = $null
		$UAC_1 = Pull-LDAPAttribute $objUser "userAccountControl"
		$msg = "INFO`t`t`tUser's UAC value (Method 1): """ + $UAC_1 + """."
		Write-Out $msg "darkcyan" 4
		
		$UAC_1_Flags = $null
		$UAC_1_Flags = Get-UACFlags $UAC_1
		$strFlags = $null
		$i = 0
		Foreach($flag in $UAC_1_Flags)
			{
				If($i -eq 0)
					{$strFlags += $flag}
				Else
					{$strFlags = $strFlags + ", " + $flag}
				$i++
			}
		$msg = "INFO`t`t`tUAC Flags: """ + $strFlags+ """."
		Write-Out $msg "darkcyan" 4
		
		If($UAC_1_Flags -contains "ACCOUNTDISABLE")
			{$results = $false}
		Else
			{$results = $true}
		
		If($results -eq $false)
			{
				$UAC_2 = $null
				$UAC_2 = $objUser.userAccountControl.value
				$msg = "INFO`t`t`tUser's UAC valued (Method 2): """ + $UAC_2 + """."
				Write-Out $msg "darkcyan" 4
				$UAC_2_Flags = $null
				$UAC_2_Flags = Get-UACFlags $UAC_2
				$strFlags = $null
				$i = 0
				Foreach($flag in $UAC_1_Flags)
					{
						If($i -eq 0)
							{$strFlags += $flag}
						Else
							{$strFlags = $strFlags + ", " + $flag}
						$i++
					}
				$msg = "INFO`t`t`tUAC Flags: """ + $strFlags+ """."
				Write-Out $msg "darkcyan" 4
				If($UAC_2_Flags -contains "ACCOUNTDISABLE")
					{$results = $false}
				Else
					{$results = $true}
			}
		
		$msg = "INFO`t`t`tAccountIsEnabled: " + $results + "."
		Write-Out $msg "darkcyan" 4
		Return $results
	}




#### Delete from AD Functions

Function Delete-Account($objUser)
	{
		$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
		$searcher = New-Object System.DirectoryServices.DirectorySearcher([ADSI]"","(&(objectcategory=user)(sAMAccountName=$sAMAccountName))")
		$user = $searcher.findone().GetDirectoryEntry()
		
		[string]$readPath = $user.path
		$readDN = $readPath.TrimStart("LDAP://")
		$givenDN = Pull-LDAPAttribute $objUser "distinguishedName"
		If($readDN.ToLower() -eq $givenDN.ToLower())
			{
				$msg = "ACTION`tDeleting the following account: """ + $sAMAccountName + """."
				Write-Out $msg "white" 2
				$user.psbase.DeleteTree()
				$results = $true
			}
		Else
			{$results = $false}
		Return $results
	}

Function Delete-UserFromAD($hshUserInfo)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		$results = $null
		
		#look up the DN
		$sAMAccountName = $null
		$sAMAccountName = $hshUserInfo.Get_Item("sAMAccountName")
		$blnUserCheck = $null
		$blnUserCheck = $false
		$blnUserCheck = Check-DoesUserExist $sAMAccountName
		If($blnUserCheck -eq $null -or $blnUserCheck -eq $false -or $blnUserCheck -eq "")
			{
				$msg = "Error`t`tThe user given does not exist: """ + $sAMAccountName + """."
				Throw-Warning $msg
				$failThisFunction = $true
			}
		Else
			{
				$strUserDN = $null
				$strUserDN = Get-DNbySAMAccountName $sAMAccountName
				If($strUserDN -eq $null -or $strUserDN -eq $false -or $strUserDN -eq "")
					{
						$msg = "Error`t`tCould not lookup the DN for user """ + $sAMAccountName + """."
						Throw-Warning $msg
						$failThisFunction = $true
					}
				Else
					{}
			}
		
		#bind to the user
		If($failThisFunction -eq $false)
			{
				$objUser = $null
				$objUser = [adsi]("LDAP://" + $strUserDN)
				$OC = $null
				$OC = Pull-LDAPAttribute $objUser "objectCategory"
				If($OC -like "*person*")
					{}
				Else
					{
						$msg = "Warning`t`tThe following DN is unavailable or not a user object: """ + $strUserDN + """."
						Throw-Warning $msg
						$failThisFunction = $true
					}
			}
		
		$arrTasklist = $null
		$arrTasklist = @()
		$arrTasklist += "Export-LDAPRecord"
		$arrTasklist += "Delete-Account"
		
		$sAMAccountName = $null
		$sAMAccountName = $hshUserInfo.Get_Item("sAMAccountName")
		Foreach($task in $arrTasklist)
			{
				$msg = "Action`tRunning archive task: """ + $task + """."
				Write-Out $msg "cyan" 2
				$DN = $null
				$DN = Get-DNbysAMAccountname $sAMAccountName
				$objUser = $null
				$objUser = [adsi]("LDAP://" + $DN)
				$blnTask = $null
				$blnTask = $false
				$blnTask = Run-ArchiveTask $task $objUser
				If($blnTask -eq $false)
					{
						$msg = "Warning`tCould not successfully complete the task """ + $task + """."
						Throw-Warning $msg
						$failThisFunction = $true
						Break
					}
				Else
					{
						$msg = "Info`tSuccessfully completed the task """ + $task + """."
						Write-Out $msg "green" 2
						$results = $true
					}
			}
		
		If($failThisFunction -eq $true)
			{$retval = $false}
		Else
			{$retval = $results}
		Return $retval
	}


#### Functions copied directly from other scripts ####





#### Parse Arguments ###

Function Validate-Arguments($arrArguments)
	{
		$results = $true
		
		#check /file
		If($arrArguments -contains "/file" -and 
				(`
					$arrArguments -contains "/user" -or `
					$arrArguments -contains "/group" -or `
					$arrArguments -contains "/guicreate" -or `
					$arrArguments -contains "/precopy" -or `
					$arrArguments -contains "/fix"`
				)`
			)
			{
				$warningMsg = "ERROR`t/file only supports the arguments /startnumber, /limit, and /verbose."
				Throw-Warning $warningMsg
				$results = $false
			}
		
		#check /fix
		If($arrArguments -contains "/fix" -and `
				($arrArguments -contains "/limit" -or `
				$arrArguments -contains "/file" -or `
				$arrArguments -contains "/startnumber" -or `
				$arrArguments -contains "/precopy" -or `
				$arrArguments -contains "/guicreate"))
			{
				$warningMsg = "ERROR`t/fix only supports the arguments /verbose, /user, and /group."
				Throw-Warning $warningMsg
				$results = $false
			}
		
		#check /fix parameters
		If($arrArguments -contains "/fix")
			{
				Switch($gStrAccountType)
					{
						"user"
							{
								#validate user name
								$blnDoesUserExist = Check-DoesUserExist $gsAMAccountName
								If($blnDoesUserExist -eq $false)
									{
										$warningMsg = "ERROR`tInvalid username specified or user does not exist."
										Throw-Warning $warningMsg
										$results = $false
									}
							}
						"group"
							{
								#validate group name
								$blnDoesUserExist = $null
								$blnDoesUserExist = Check-DoesGroupExist $gsAMAccountName
								If($blnDoesUserExist -eq $false)
									{
										$warningMsg = "ERROR`tInvalid group specified or group does not exist."
										Throw-Warning $warningMsg
										$results = $false
									}
								
								#make sure group does not contain nested groups
								$blnGroupContainsGroups = $null
								$blnGroupContainsGroups = Check-GroupContainsGroups $gsAMAccountName
								If($blnGroupContainsGroups -eq $true)
									{
										$warningMsg = "ERROR`t/group can only process groups when all members' objectCatagory = *person* or *user*."
										Throw-Warning $warningMsg
										$results = $false
									}
							}
					}
			}
		
		#check /precopy
		If($arrArguments -contains "/precopy" -and `
				($arrArguments -contains "/limit" -or `
				$arrArguments -contains "/file" -or `
				$arrArguments -contains "/startnumber" -or `
				$arrArgumets -contains "/fix" -or `
				$arrArguments -contains "/guicreate"))
			{
				$warningMsg = "ERROR`t/precopy only supports the arguments /verbose, /user, and /group."
				Throw-Warning $warningMsg
				$results = $false
			}
		
		#check /precopy parameters
		If($arrArguments -contains "/precopy")
			{
				Switch($gStrAccountType)
					{
						"user"
							{
								#validate user name
								$blnDoesUserExist = Check-DoesUserExist $gsAMAccountName
								If($blnDoesUserExist -eq $false)
									{
										$warningMsg = "ERROR`tInvalid username specified or user does not exist."
										Throw-Warning $warningMsg
										$results = $false
									}
							}
						"group"
							{
								#validate group name
								$blnDoesUserExist = $null
								$blnDoesUserExist = Check-DoesGroupExist $gsAMAccountName
								If($blnDoesUserExist -eq $false)
									{
										$warningMsg = "ERROR`tInvalid group specified or group does not exist."
										Throw-Warning $warningMsg
										$results = $false
									}
								
								#make sure group does not contain nested groups
								$blnGroupContainsGroups = $null
								$blnGroupContainsGroups = Check-GroupContainsGroups $gsAMAccountName
								If($blnGroupContainsGroups -eq $true)
									{
										$warningMsg = "ERROR`t/group can only process groups when all members' objectCatagory = *person* or *user*."
										Throw-Warning $warningMsg
										$results = $false
									}
							}
					}
			}
		
		#check optional arguments
		If($arrArguments -notcontains "/fix" -and `
			$arrArguments -notcontains "/guicreate" -and `
			$arrArguments -notcontains "/file" -and `
			$arrArguments -notcontains "/precopy")
			{
				$warningMsg = "ERROR`tThe script must be run with a mandatory argument (/precopy, /fix, /gui, or /file)."
				Throw-Warning $warningMsg
				$results = $false
			}
		
		#check for /user and /group arguments
		If($arrArguments -contains "/user" -and $arrArguments -contains "/group")
			{
				$warningMsg = "ERROR`tThe arguments /user and /group are mutually exclusive."
				Throw-Warning $warningMsg
				$results = $false
			}
		
		#check /gui
		If($arrArguments -contains "/guicreate" -and `
			($arrArguments -contains "/limit" -or `
			$arrArguments -contains "/startnumber" -or `
			$arrArguments -contains "/fix" -or `
			$arrArguments -contains "/file" -or `
			$arrArguments -contains "/user" -or `
			$arrArguments -contains "/group"))
			{
				$warningMsg = "ERROR`t/gui only supports the argument /verbose."
				Throw-Warning $warningMsg
				$results = $false
			}
		Return $results
	}

Function Run-ArgTest($argTest,$arrArguments)	
	{
		$results = $null
		Switch($argTest)
			{
				"argTest-CoreArgumentChecks"
					{
						$results = Run-argTest-CoreArgumentChecks $arrArguments
					}
				"argTest-InputArgumentChecks"
					{
						$results = Run-argTest-InputArgumentChecks $arrArguments
					}
				"argTest-ControlArgumentChecks"
					{
						$results = Run-ArgTest-ControlArgumentChecks $arrArguments
					}
				"argTest-NumberofArgs"
					{
						$results = Run-ArgTest-NumberOfArgs $arrArguments
					}
				Default
					{
						$msg = "Error`t(f)Run-ArgTest was asked to run a test that isn't defined: """ + $argTest + """."
						Throw-Warning $msg
						$results = $false
					}
			}
		Return $results
	}

Function Run-argTest-CoreArgumentChecks($arrArguments)
	{
		$results = $null
		$results = $true
		
		$arrCoreArgs = $null
		$arrCoreArgs = Get-CoreArguments $arrArguments
		If($arrCoreArgs -eq $false -or $arrCoreArgs -eq $false -or $arrCoreArgs -eq "")
			{
				$msg = "Error`tCould not find at least 1 core argument (run mode)."
				Throw-Warning $msg
				$results = $false
			}
		
#		If($arrCoreArgs -contains "/mark" -and $arrCoreArgs -contains "/archive")
#			{
#				$msg = "Error`tThe core arguments /mark and /archive are mutually exclusive."
#				Throw-Warning $msg
#				$results = $false
#			}
		
		If($arrCoreArgs.count -gt 1)
			{
				$msg = "Error`tOnly 1 core argument is supported at a time (/archive, /mark, /delete, /scan)."
				Throw-Warning $msg
				$results = $false
			}
		
		Return $results
	}

Function Get-CoreArguments($arrArguments)
	{
		$results = $null
		$results = $true
		
		$intCoreArgCounter = $null
		$intCoreArgCounter = 0
		$arrCoreArgs = $global:arrCoreArguments
		$arrCoreArgumentsFound = $null
		$arrCoreArgumentsFound = @()
		Foreach($argument in $arrArguments)
			{
				If($arrCoreArgs -contains $argument)
					{
						$arrCoreArgumentsFound += $argument
						$intCoreArgCounter++
					}
			}
		
		If($intCoreArgCounter -eq 0)
			{
				$msg = "ERROR`tMissing a core argument (/mark, /archive, /delete)."
				Throw-Warning $msg
				$results = $false
			}
		Else
			{$results = $true}
		
		$retval = $null
		$retval = $false
		If($results -eq $true)
			{$retval = $arrCoreArgumentsFound}
		Else
			{$retval = $false}
		
		Return $retval
	}

Function Run-argTest-InputArgumentChecks($arrArguments)
	{
		$results = $null
		$results = $true
		$continue = $null
		$continue = $true
		
		#check to make sure we only have 1 input argument
		$intInputArgCounter = $null
		$intInputArgCounter = 0
		$strInputArgument = $null
		$arrInputArgs = $global:arrInputArguments
		Foreach($argument in $arrArguments)
			{
				If($arrInputArgs -contains $argument)
					{
						$strInputArgument = $argument
						$intInputArgCounter++
					}
			}
		
		If($intInputArgCounter -eq 0)
			{
				$msg = "ERROR`tNo input arguments given. The following arguments are input arguments: /folder, /file, /group, /user, /allusers ."
				Throw-Warning $msg
				$results = $false
			}
		ElseIf($intInputArgCounter -gt 1)
			{
				$msg = "ERROR`tToo many input arguments given. Please use only one of the following: /folder, /file, /group, /user, /allusers ."
				Throw-Warning $msg
				$results = $false
			}
		
		#check that the input argument is valid
		If($results -eq $true -and $continue -eq $true)
			{
				Switch($strInputArgument)
					{
						"/file"
							{
								$results = Run-argTest-fileDependentArg $arrArguments
							}
						"/folder"
							{
								$results = Run-argTest-folderDependentArg $arrArguments
							}
						"/group"
							{
								$results = Run-argTest-groupDependentArg $arrArguments
							}
						"/user"
							{
								$results = Run-argTest-userDependentArg $arrArguments
							}
						"/allusers"
							{}
						Default
							{
								$msg = "DEBUG`tRun-argTest-InputArgument was passed an input argument that isn't defined."
								Throw-Warning $msg
								$msg = "DEBUG`tUndefined input argument: """ + $strInputArgument + """."
								Throw-Warning $msg
								$results = $false
							}
					}
			}
		
		Return $results
	}

Function Run-argTest-FileDependentArg($arrArguments)
	{
		$results = $null
		$results = $true
		
		$rootArg = $null
		$rootArg = "/file"
		
		[int32]$intNumberOfArgs = $gArgumentDependents.Get_Item($rootArg)
		$dependentArg = $null
		$dependentArg = Get-DependentArgs $rootArg $intNumberOfArgs $arrArguments
		
		$blnNoDependents = $null
		If($dependentArg -eq $null -or $dependentArg -eq $false)
			{
				$blnNoDependents = $true
				$msg = "Error`tNo filepath or filename was given."
				Throw-Warning $msg
				$results = $false
			}
		Else
			{$blnNoDependents = $false}
		
		If($blnNoDependents -eq $false)
			{
				#can we access the file?
				$pathTest = Test-Path $dependentArg
				If($pathTest -eq $true)
					{}
				Else
					{
						$msg = "Error`tCould not open the file. Either the file doesn't exist or you don't have access to it."
						Throw-Warning $msg
						$results = $false
					}
			}
		
		#does the file end in XLSX or CSV?
		If($blnNoDependents -eq $false)
			{
				$blnExtensionOK = $null
				$blnExtensionOK = $false
				$arrValidExtensions = $global:arrValidFileExtensions
				Foreach($extension in $arrValidExtensions)
					{
						If($dependentArg -like ("*." + $extension))
							{$blnExtensionOK = $true}
					}
				If($blnExtensionOK -eq $false)
					{
						$msg = "Error`tThe file extension isn't supported. Please use a file ending with .xlsx or .csv ."
						Throw-Warning $msg
						$results = $false
					}
				Else
					{
						$results = $blnExtensionOK
					}
			}
		Return $results
	}

Function Run-argTest-FolderDependentArg($arrArguments)
	{
		$results = $null
		$results = $true
		
		$rootArg = $null
		$rootArg = "/folder"
		
		#grab dependent args (folder path)
		[int32]$intNumberOfArgs = $gArgumentDependents.Get_Item($rootArg)
		$dependentArg = $null
		$dependentArg = Get-DependentArgs $rootArg $intNumberOfArgs $arrArguments
		
		#do we have any dependent args?
		$blnNoDependents = $null
		If($dependentArg -eq $null -or $dependentArg -eq $false)
			{
				$blnNoDependents = $true
				$msg = "Error`tNo folder path or folder name was given."
				Throw-Warning $msg
				$results = $false
			}
		Else
			{$blnNoDependents = $false}
		
		#is the folder accessable?
		If($blnNoDependents -ne $true)
			{
				#can we access the file?
				$blnFolderAccessable = $null
				$pathTest = Test-Path $dependentArg
				If($pathTest -eq $true)
					{
						$blnFolderAccessable = $true
					}
				Else
					{
						$msg = "Error`tCould not open the folder. Either the folder doesn't exist or you don't have access to it."
						Throw-Warning $msg
						$results = $false
						$blnFolderAccessable = $false
					}
			}
		
		#is the path a folder?
		If($blnFolderAccessable -eq $true)
			{
				$objFolder = Get-Item $dependentArg
				$isContainer = $objFolder.PSIsContainer
				If($isContainer -ne $true)
					{
						$msg = "Error`tThe folder name or folder path given is a not actually a folder. It is probably a file."
						Throw-Warning $msg
						$results = $false
					}
			}
		
		#Does the folder have any subfolderes that resolve to usernames?
#		If($blnFolderAccessable -eq $true -and $isContainer -eq $true)
#			{
#				$foldername = $dependentArg
#				[array]$arrUsernames = @()
#				[array]$arrSubfolderNames = gci $foldername | %{If($_.PSIsContainer -eq $true){$_.Name}}
#				$blnUserCheck = $null
#				$blnUserCheck = $false
#				$arrSubfolderNames | %{
#					$blnUserExists = $null
#					$blnUserExists = $false
#					$blnUserExists = Check-DoesUserExist $_
#					If($blnUserExists -eq $true)
#						{
#							$blnUserCheck = $true
#							Break
#						}
#					Else
#						{}
#				}
#				If($blnUserCheck -ne $true)
#					{
#						$msg = "Error`tThe folder name or folder path given does not contain any subfolder with active usernames."
#						Throw-Warning $msg
#						$results = $false
#					}
#			}
		
		
		Return $results
	}

Function Run-argTest-GroupDependentArg($arrArguments)
	{
		$results = $null
		$results = $true
		
		$rootArg = $null
		$rootArg = "/group"
		
		#grab dependent args (folder path)
		[int32]$intNumberOfArgs = $gArgumentDependents.Get_Item($rootArg)
		$dependentArg = $null
		$dependentArg = Get-DependentArgs $rootArg $intNumberOfArgs $arrArguments
		
		#do we have any dependent args?
		$blnNoDependents = $null
		If($dependentArg -eq $null -or $dependentArg -eq $false)
			{
				$blnNoDependents = $true
				$msg = "Error`tNo group name was given."
				Throw-Warning $msg
				$results = $false
			}
		Else
			{$blnNoDependents = $false}
		
		#does the group exist?
		If($blnNoDependents -ne $true)
			{
				#can we access the file?
				$blnGroupExists = $null
				$blnGroupExists = $false
				$blnGroupExists = Check-DoesGroupExist $dependentArg
				If($blnGroupExists -ne $true)
					{
						$msg = "Error`tThe group given does not exist in AD."
						Throw-Warning $msg
						$results = $false
						$blnGroupExists = $false
					}
				Else
					{
						$blnGroupExists = $true
					}
			}
		
		#does the group contain any users?
		If($blnGroupExists -eq $true)
			{
				$groupDN = Get-DNbyCN $dependentArg
				$blnFoundUser = $null
				$blnFoundUser = $false
				
				If($groupDN -eq $false)
					{
						$msg = "Error`tCould not look up the group's DN."
						Throw-Warning $msg
						$results = $false
					}
				Else
					{
						$objGroup = [adsi]("LDAP://" + $groupDN)
						$member = Pull-LDAPAttribute $objGroup "member"
						$member | % {
								$objMember = $null
								$objMember = [adsi]("LDAP://" + $_)
								$OC = $null
								$OC = Pull-LDAPAttribute $objMember "objectCategory"
								#Write-Host -f yellow "dn: $_`nOC:$OC`n"
								If($OC -like "*person*" -or $OC -like "*user*")
									{
										$blnFoundUser = $true
										Break
									}
							}
					}
				If($blnFoundUser -ne $true)
					{
						$msg = "Error`tThis group doesn't contain any user objects."
						Throw-Warning $msg
						$results = $false
					}
			}
		
		Return $results
	}

Function Run-argTest-UserDependentArg($arrArguments)
	{
		$results = $null
		$results = $true
		
		$rootArg = $null
		$rootArg = "/user"
		
		#grab dependent args (folder path)
		[int32]$intNumberOfArgs = $gArgumentDependents.Get_Item($rootArg)
		$dependentArg = $null
		$dependentArg = Get-DependentArgs $rootArg $intNumberOfArgs $arrArguments
		
		#do we have any dependent args?
		$blnNoDependents = $null
		If($dependentArg -eq $null -or $dependentArg -eq $false)
			{
				$blnNoDependents = $true
				$msg = "Error`tNo user name was given."
				Throw-Warning $msg
				$results = $false
			}
		Else
			{$blnNoDependents = $false}
		
		#does the user exist?
		If($blnNoDependents -ne $true)
			{
				#can we access the file?
				$blnGroupExists = $null
				$blnGroupExists = $false
				$blnGroupExists = Check-DoesUserExist $dependentArg
				If($blnGroupExists -ne $true)
					{
						$msg = "Error`tThe user given does not exist in AD."
						Throw-Warning $msg
						$results = $false
						$blnGroupExists = $false
					}
				Else
					{
						$blnGroupExists = $true
					}
			}
		
		Return $results
	}

Function Verify-Arguments($arrArguments) #done
	{
		$results = $null
		$results = $false
		
		$arrArgTests = @()
		$arrArgTests += "argTest-CoreArgumentChecks"
		$arrArgTests += "argTest-InputArgumentChecks"
		$arrArgTests += "argTest-ControlArgumentChecks"
		$arrArgTests += "argTest-NumberofArgs"
		
		Foreach($strArgTest in $arrArgTests)
			{
				$results = Run-ArgTest $strArgTest $arrArguments
				If($results -eq $false)
					{Break}
			}
		Return $results
	}

Function Check-StandardIntArgTests($dependentArgs)
	{
		$results = $null
		$results = $true
		
		#Is the dependent an int?
		$blnIntTestOK = $null
		$blnIntTestOK = $false
		$blnIntTestOK = Check-StringToInt $dependentArgs
		#Is the dependent positive?
		If($blnIntTestOK -eq $true)
			{
				$blnPositiveTest = $null
				$blnPositiveTest = $false
				[int32]$intDependentArg = $dependentArgs
				If($intDependentArg -lt 1)
					{
						$blnPositiveTest = $false
					}
				Else
					{
						$blnPositiveTest = $true
					}
			}
		
		If($blnIntTestOK -ne $true -or $blnPositiveTest -ne $true)
			{
				$results = $false
			}
		Else
			{}
		
		Return $results
	}

Function Run-ArgTest-ControlArgumentChecks($arrArguments)
	{
		$results = $null
		$results = $true
		
		#find all control args present
		$controlArgsPresent = @()
		$validControlArgs = $global:arrControlArguments
		Foreach($argument in $arrArguments)
			{
				If($validControlArgs -contains $argument)
					{$controlArgsPresent += $argument}
			}
		
		#if we have control args, are they ok?
		If($controlArgsPresent.count -gt 0)
			{
				Foreach($controlArgPresent in $controlArgsPresent)
					{
						$rootArg = $null
						$rootArg = $controlArgPresent
						[int32]$intNumberOfArgs = $null
						$intNumberOfArgs = $gArgumentDependents.Get_Item($controlArgPresent)
						$dependentArgs = $null
						$dependentArgs = Get-DependentArgs $rootArg $intNumberOfArgs $arrArguments
						
						Switch($controlArgPresent)
							{
								"/startnumber"
									{
										If($dependentArgs -eq $false -or $dependentArgs -eq $null)
											{
												$msg = "Error`tWhen using " + $controlArgPresent + " please specifify a positive integer for it."
												Throw-Warning $msg
												$results = $false
											}
										Else
											{
												$blnTestResults = Check-StandardIntArgTests $dependentArgs
												If($blnTestResults -eq $false)
													{
														$msg = "Error`t" + $controlArgPresent + " only supports positive integers greater than 0"
														Throw-Warning $msg
														$results = $false
													}
											}
									}
								"/limit"
									{
										If($dependentArgs -eq $false -or $dependentArgs -eq $null)
											{
												$msg = "Error`tWhen using " + $controlArgPresent + " please specifify a positive integer for it."
												Throw-Warning $msg
												$results = $false
											}
										Else
											{
												$blnTestResults = Check-StandardIntArgTests $dependentArgs
												If($blnTestResults -eq $false)
													{
														$msg = "Error`t" + $controlArgPresent + " only supports positive integers greater than 0"
														Throw-Warning $msg
														$results = $false
													}
											}
									}
								"/eval" {}
								"/verbose" {}
								Default
									{
										$msg = "Error`tI do not understand the control argument """ + $controlArgPresent + """ ."
										Throw-Warning $msg
										$results = $false
									}
							}
						
					}
				
				#is limit less than startnumber?
				If($controlArgsPresent -contains "/limit" -and $controlArgsPresent -contains "/startnumber" -and $results -eq $true)
					{
						[int]$intStartNumber = Get-DependentArgs "/startnumber" 1 $arrArguments
						[int]$intLimit = Get-DependentArgs "/limit" 1 $arrArguments
						If($intStartNumber -gt $intLimit)
							{
								$msg = "Error`tThe limit has to be greater than the startnumber."
								Throw-Warning $msg
								$results = $false
							}
					}
			}
		Else
			{$results = $true}
		
		Return $results
	}

Function Verify-ArgumentContent($arrArguments)
	{
		$results = $null
		$results = $false
		
		$arrArgTests = @()
		$arrArgTests += "argTest-DependentsExist"
		$arrArgTests += "argTest-DependentsValid"
		
		Foreach($strArgTest in $arrArgTests)
			{
				$results = Run-ArgTest $strArgTest $arrArguments
				If($results -eq $false)
					{Break}
			}
		Return $results
	}

Function Run-argtest-DependentsExist($arrArguments)
	{
		$results = $null
		$results = $false
		
		$keys = $gArgumentDependents.Keys
		Foreach($argument in $arrArguments)
			{
				If($keys -contains $argument)
					{
						$intDependents = $gArgumentDependents.Get_Item($argument)
						$i = $null
						$i = 1
						While($i -le $intDependents)
							{
								$dependent = $null
								$dependent = Get-DependentArgs $argument $intDependents $arrArguments
								If($dependent -eq $null -or $dependent -eq $false)
									{
										$msg = "Error`tThere is a problem with the usage of the following argument: """ + $argument + """."
										Throw-Warning $msg
										$msg = "Info`tMissing at least one dependent argument."
										Throw-Warning $msg
									}
							}
					}
				Else
					{}
			}
		
		Return $results
	}

Function Get-InputArgument($arrArguments)
	{
		$arrInputArgs = $global:arrInputArguments
		Foreach($argument in $arrArguments)
			{
				If($arrInputArgs -contains $argument)
					{
						$strInputArgument = $argument
					}
			}
		Return $strInputArgument
	}

Function Get-ControlArguments($arrArguments)
	{
		$controlArgsPresent = @()
		$validControlArgs = $global:arrControlArguments
		Foreach($argument in $arrArguments)
			{
				If($validControlArgs -contains $argument)
					{$controlArgsPresent += $argument}
			}
		Return $controlArgsPresent
	}

Function Run-ArgTest-NumberOfArgs($arrArguments)
	{
		$results = $null
		$results = $true
		
		$argCount = $arrArguments.count
		
		[array]$arrCoreArguments = Get-CoreArguments $arrArguments
		[array]$controlArguments = Get-ControlArguments $arrArguments
		$inputArgument = Get-InputArgument $arrArguments
		
		#count core arguments
		$coreArgCount = $null
		$coreArgCount = $arrCoreArguments.Count
		$intTotalCoreArgCount = $coreArgCount
		#write-host -f yellow "debug`t(f)Run-ArgTest-NumberofArgs`tarrCoreArguments: $arrCoreArguments"
		#write-host -f yellow "debug`t(f)Run-ArgTest-NumberofArgs`tintTotalCoreArgCount: $intTotalCoreArgCount"
		
		$inputArgumentCount = $null
		$inputArgumentCount = 1 #assumes we have 1 input argument, since only 1 is allowed
		$inputArgumentDepsCount = $null
		$inputArgumentDepsCount = $gArgumentDependents.Get_Item($inputArgument)
		$inputArgumentDepsCount = $gArgumentDependents.Get_Item($inputArgument)
		$intTotalInputArgCount = $inputArgumentCount + $inputArgumentDepsCount
		
		$intControlArgCount = $null
		$intControlArgCount = 0
		Foreach($controlArg in $controlArguments)
			{
				If($controlArg -eq $null)
					{}
				Else
					{
						$intControlArgCount++
						$currentControlArgCount = $gArgumentDependents.Get_Item($controlArg)
						$intControlArgCount += $currentControlArgCount
					}
			}
		$intTotalControlArgCount = $intControlArgCount
		
		$intTotalCalculatedArgs = $null
		$intTotalCalculatedArgs = $intTotalCoreArgCount + $intTotalInputArgCount + $intTotalControlArgCount
		
		If($argCount -ne $intTotalCalculatedArgs)
			{
				$msg = "Error`tThe number of arguments given doesn't look right. Please check your arguments."
				Throw-Warning $msg
				$msg = "Debug`tExpected """ + $intTotalCalculatedArgs + """ arguments. Was given """ + $argCount + """. "
				Throw-Warning $msg
				$results = $false
			}
		
		Return $results
	}

Function Get-DependentArgs($rootArgument,$intNumberOfArgs,$arrArguments) #done
	{
		$retval = $null
		$fail = $null
		$fail = $false
		$continue = $null
		$continue = $true
		
		If(($intNumberOfArgs -is [int32]) -eq $false)
			{
				trap
					{
						$msg = "DEBUG`tImproper use of (f)get-dependentArgs - intNumberOfArgs isn't an int32."
						Throw-Warning $msg
						$msg = "DEBUG`t`tintNumberOfArgs: """ + $intNumberofArgs + """."
						Throw-Warning $msg
						$fail = $true
					}
				[int32]$intNumberOfArgs = $intNumberOfArgs
			}
		ElseIf($intNumberOfArgs -le 0 -or $intNumberOfArgs -eq "" -or $intNumberOfArgs -eq $null)
			{
				$retval = $null
				$continue = $false
			}
		
		If($continue -eq $true -and $fail -eq $false)
			{
				$arrDependents = Get-NextNArguments $arrArguments $rootArgument $intNumberOfArgs
				
				#remove any other valid arguments from nextNarguments
				$arrValidSwitches = $gValidSwitches
				$arrNewDependents = @()
				Foreach($strMember in $arrDependents)
					{
						#write-host -f green "strmember: $strmember"
						#write-host -f green "arrvalidswitches: $arrValidSwitches"
						If($arrValidSwitches -contains $strMember)
							{}
						Else
							{$arrNewDependents += $strMember}
					}
				$arrDependents = $arrNewDependents
				
				If($arrDependents -eq $null -or $arrDependents -eq "")
					{
						$msg = "ERROR`tNo sub-arguments found for the argument: """ + $rootArgument + """."
						Throw-Warning $msg
						$fail = $true
					}
				ElseIf($intNumberOfArgs -gt 1 -and $arrDependents -isnot [array])
					{
						$msg = "ERROR`tNot enough dependent arguments retrieved for root argument: """ + $rootArgument + """ (read dependents: """ + $arrDependents + """)."
						Throw-Warning $msg
						$fail = $true
					}
				Else
					{
						Foreach($dependent in $arrDependents)
							{
								If($gValidArguments -contains $dependent)
									{
										$msg = "Error`tNot enough arguments supplied."
										Throw-Warning $msg
										$fail = $true
										Break
									}
							}
					}
			}
		
		If($fail -eq $false)
			{$retval = $arrDependents}
		
		If($fail -eq $true)
			{$retval = $false}
		
		Return $retval
	}

Function Get-NextNArguments($arrArguments,$rootArgument,$numberOfArgsToRead) #done
	{
		$fail = $null
		$retval = $null
		
		$argCount = $null
		$argCount = $arrArguments.count
		
		$i = $null
		$i = 0
		While($i -le $argCount)
			{
				$iArgument = $null
				$iArgument = $arrArguments[$i]
				If($rootArgument -eq $iArgument)
					{
						$returnArguments = $null
						$returnArguments = @()
						#$returnArguments += $iArgument
						
						$j = $null
						$j = 1
						While($j -le $numberOfArgsToRead)
							{
								$nextArgCounter = $null
								$nextArgCounter = $i + $j
								$nextArg = $null
								[string]$nextArg = $arrArguments[$nextArgCounter]
								If($nextArg -eq $null -or $nextArg -eq "")
									{
										$fail = $true
										Break
									}
								Else
									{$returnArguments += $nextArg}
								$j++
							}
						Break
					}
				$i++
			}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $returnArguments}
		
		Return $retval
	}

#----Parse Arguments----
$global:gArrArguments = @()
$global:gArrArguments = $args

##General Variables
[array]$global:gArrArguments = $null	#Global copy of $args
$lArrArguments = $null								#Local scope copy of args (though, at the root)
$gStrRunMode = $null									#Run mode can be: gui, file, cli
$gStrRunModeModifiers = $null					#Run mode modifiers can be: verbose, eval, precopy, user, group
$gHshRunModeVariables = $null					#Run mode hash table of variables needed for that specific run mode to work.

##Regulatory Variables
$gBlnBadArgument = $null
$gBlnBadArgument = $false

$msg = "Verifying Arguments, please wait."
Write-Out $msg "white" 2

#Inital check - any arguments present
[array]$global:gArrArguments = $args
$lArrArguments = $global:gArrArguments
$intArgCount = $null
$intargCount = $lArrArguments.Count
If($intArgCount -le 0)
	{
		$warningMsg = "ERROR`tNo arguments."
		Throw-Warning $warningMsg
		$gBlnBadArgument = $true
	}

#Second check - extensive checks
If($gBlnBadArgument -eq $false)
	{
		$blnArgCheckOK = $null
		$blnArgCheckOK = $false
		$blnArgCheckOK = Verify-Arguments $lArrArguments
		If($blnArgCheckOK -eq $false)
			{
				$warningMsg = "ERROR`tCould not verify arguments."
				Throw-Warning $warningMsg
				$gBlnBadArgument = $true
			}
	}

#prepare information for director

$intCurrentArgument = 0
$intFilenameArgument = 0
$intArgumentCount = 0
$intArgumentCount = $args.count
$global:gVerbosityLevel = 4
$gFilename = $null
$gsAMAccountName = $null
$gIntLimit = 50000
$gStrRunMode = $null
$gStrAccountType = $null

If($gBlnBadArgument -eq $true)
	{
		$warningMsg = "ERROR`tExiting script."
		Throw-Warning $warningMsg
		Write-Fail
		Write-UsageInfo
		Exit
	}
Else
	{
		#find runmode
		$arrCoreArgs = $null
		[array]$arrCoreArgs = Get-CoreArguments $lArrArguments
		
		#parse control arguments
		#find startnumber
		$arrControlArgs = $null
		[array]$arrControlArgs = Get-ControlArguments $lArrArguments
		If($arrControlArgs -contains "/startnumber")
			{
				[int]$gIntStartNumber = $null
				$gIntStartNumber = Get-DependentArgs "/startnumber" 1 $lArrArguments
				#write-host -f green "gIntStartNumber: $gIntStartNumber"
			}
		Else
			{$gIntStartNumber = 0}
		
		#find limit
		If($arrControlArgs -contains "/limit")
			{
				[int]$gIntLimit = $null
				$gIntLimit = Get-DependentArgs "/limit" 1 $lArrArguments
				#write-host -f green "gintlimit: $gintlimit"
			}
		Else
			{}
		
		#enable verbose mode
		If($arrControlArgs -contains "/verbose")
			{
				$global:gVerbosityLevel = 4
			}
		
		#parse input arguments
		$gStrInputMode = Get-InputArgument $lArrArguments
		$gStrInputDep = Get-DependentArgs $gStrInputMode 1 $lArrArguments
		
		Write-OpeningBlock
		[string]$strDirectorCall = "Director: arrCoreArgs """ + $arrCoreArgs + """, strInputMode """ + $gStrInputMode + """, inputDep """ + $gStrInputDep + """, startNum """ + $gIntStartNumber + """, lim """ + $gIntLimit + """ ."
		#Write-Host -f yellow "DEBUG`t(f)`tstrDirectorCall: $strDirectorCall"
		$results = Director $arrCoreArgs $gStrInputMode $gStrInputDep $gIntStartNumber $gIntLimit
	}

[GC]::Collect()