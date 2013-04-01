#ref: stolen from http://blogs.technet.com/b/heyscriptingguy/archive/2011/05/11/check-for-admin-credentials-in-a-powershell-script.aspx
If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
	[Security.Principal.WindowsBuiltInRole] "Administrator"))
	{
		Write-Warning "You do not have Administrator rights to run this script!`nPlease re-run this script as an Administrator!"
		Exit
	}

#FEATURE REQUETS AND CHANGES!
#Anything interacting with AD need Trap{}'ed
#Linux tests - UID with no GID and vice versa, and 6-Digit+ UID's.
#when running CLI do not display row numbers

###NOTES
##to add a check:
##build-testset
##build-actionset

## commented out homeFilePermissions tests. - 01.22.13 - JP
### problem with function; claiming JP needs removed from every run then fails to do so


[GC]::Collect()
$error.clear()
$results = $null
$results = $false

Write-Host ""
Write-Host ""
Write-Host ""

$gScriptName = "Create-Accounts.ps1"
$gScriptVersion = "039"

. .\Common-Functions-v2.ps1
. .\PSMod-FSFunctions-v1.ps1
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
$gArgumentDependents.Add("/startnumber","1")
$gArgumentDependents.Add("/limit","1")
$gArgumentDependents.Add("/eval","0")
$gArgumentDependents.Add("/verbose","0")
$gArgumentDependents.Add("/return","0")
$gArgumentDependents.Add("/rebuild","0")
$gArgumentDependents.Add("/newhome","1")

$gValidSwitches = @()
$gValidSwitches += "/precopy"
$gValidSwitches += "/fix"
$gValidSwitches += "/guicreate"
$gValidSwitches += "/file"
$gValidSwitches += "/user"
$gValidSwitches += "/group"
$gValidSwitches += "/folder"
$gValidSwitches += "/startnumber"
$gValidSwitches += "/limit"
$gValidSwitches += "/eval"
$gValidSwitches += "/verbose"
$gValidSwitches += "/return"
$gValidSwitches += "/rebuild"
$gValidSwitches += "/newhome"

$gArrCoreArguments = @()
$gArrCoreArguments += "/fix"
$gArrCoreArguments += "/precopy"
$gArrCoreArguments += "/guicreate"

$gArrInputArguments = @()
$gArrInputArguments += "/file"
$gArrInputArguments += "/folder"
$gArrInputArguments += "/group"
$gArrInputArguments += "/user"

$gArrControlArguments = @()
$gArrControlArguments += "/limit"
$gArrControlArguments += "/startnumber"
$gArrControlArguments += "/eval"
$gArrControlArguments += "/verbose"
$gArrControlArguments += "/return"
$gArrControlArguments += "/rebuild"
$gArrControlArguments += "/newhome"

$gArrValidFileExtensions = @()
$gArrValidFileExtensions += "xlsx"
$gArrValidFileExtensions += "csv"

###global vars### -- all read from (f)read-variable in the common-functions module as of now

#Initialize Logging
$logFilePath = Read-Variable "logFilePath"
$logFilePath = Trim-TrailingSlash $logFilePath
#$logFileDate = get-date -uformat '%d%m%Y-%H%M-%S'

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


#### Common Functions

function write-usageInfo
	{
		$msgs = @()
		$msgs += ""
		$msgs += "Usage:"
		$msgs += $gScriptName + " (/PRECOPY | /FIX /GUICREATE) (/FILE | /USER | /GROUP | /FOLDER) <filename, username, groupname, or folder>"
		$msgs += "`t[/VERBOSE | /STARTNUMBER <###> | /LIMIT <###> | /EVAL | /RETURN]"
		$msgs += ""
		$msgs += "`t/PRECOPY"
		$msgs += "`t*Tests a user's home directory permissions, fixes them, then copies data to the intended location."
		$msgs += ""
		$msgs += "`t/FIX"
		$msgs += "`t*Scans a given user for account problems, then attempts to fix the problems."
		$msgs += ""
		$msgs += "`t/GUICREATE"
		$msgs += "`t*Prompts for user information, then creates a user."
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
		$msgs += "`t/VERBOSE"
		$msgs += "`t*Writes all logging information to the screen."
		$msgs += ""
		$msgs += "`t/STARTNUMBER"
		$msgs += "`t*Begins processing at the specified object number."
		$msgs += ""
		$msgs += "`t/LIMIT"
		$msgs += "`t*Ends processing a file at the specified object number."
		$msgs += ""
		$msgs += "`t/RETURN"
		$msgs += "`t*Returns true if no users failed. Returns false if one user or the script fails. This is used for scripting."
		$msgs += ""
		$msgs += "`t/EVAL"
		$msgs += "`t*Does not make changes to the account."
		$msgs += "`t*WARNING: THIS DOES NOT WORK YET!!"
		$msgs += ""
		$msgs += "`t/REBUILD"
		$msgs += "`t*Rebuilds the user's homedrive on the LUN with the most free space."
		$msgs += ""
		$msgs += "`t/NEWHOME"
		$msgs += "`t*Used with /rebuild to specify the new home drive mount directory. Ex: ""homes0"""
		$msgs += ""
		
		
		Foreach($msg in $msgs)
			{write-out $msg "white" 1}
	}



#### Unique Functions



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
				"gui"
					{
						$hshProposedUserInfo = Pull-UserFromGUI
					}
				
			}
		
		#is the user the current script user?
		
		#Error Checking
		If($hshProposedUserInfo -eq $false -or $hshProposedUserInfo -eq $null)
			{$failThisFunction = $True}
		If($failThisFunction -eq $false -and $failFunction -eq $false)
			{$hshProcessedUserInfo = Process-UserInfo $hshProposedUserInfo}
			
		If($failThisFunction -eq $true -or $failFunction -eq $true)
			{$retval = $false}
		Else
			{$retval = $hshProcessedUserInfo}
				
		Return $retval
	}

Function Populate-TableFromsAMAccountName($sAMAccountName)
	{
		$failFunction = $null
		$failFunction = $false
		
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
								$failFunction = $true
							}
						Else
							{
								#write-host -f yellow "DEBUG!`tAdding $attribute \ $attributeValue"
								$hshUserInfo.Add($attribute,$attributeValue)	
							}
					}
			}
		
		If($failFunction -eq $true)
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


### ___GUI Input Functions___

Function Pull-UserFromGUI()
	{
		$failFunction = $false
		$hshUserInfo = $null
		$hshUserInfo = @{}
		
		$starline = "*****************************************************"
		
		
		
		$hshUserInfo = Build-UserTableFromGUI
		If($hshUserInfo -eq $false)
			{
				$warningMsg = "ERROR`tScript canceled."
				Throw-Warning $warningMsg
				$failFunction = $true
			}
		Else
			{
				$memberOf = Build-GroupMembershipArray
				If($memberOf -eq $false)
					{
						$warningMsg = "ERROR`tScript canceled."
						Throw-Warning $warningMsg
						$failFunction = $true
					}
				Else
					{
						$blnMemberOfVerified = $null
						#(f)Verify-MemberOf still needs done.
						$blnMemberOfVerified = $true
						If($blnMemberOfVerified)
							{
								[string]$strGroups = $null
								$strGroups = ""
								$i = 0
								Foreach($groupCN in $memberof)
									{
										If($i -eq 0)
											{$strGroups += $groupCN}
										Else
											{$strGroups += "," + $groupCN}
										$i++
									}
								#Write-host -f yellow "adding groups: $strGroups to hash table"
								$hshUserInfo.Add("memberof",$strGroups)
							}
						Else
							{
								$warningMsg = "ERROR`tCould not verify group memberships."
								Throw-Warning $warningMsg
								$failFunction = $true
							}
					}
			}
		
		#add profilePath
		If($hshUserInfo -ne $null -and $hshUserInfo -ne $false -and $hshUserInfo -ne "")
			{
				$keys = $hshUserInfo.Keys
				If($keys -contains "profilePath")
					{}
				Else
					{
						If($keys -contains "sAMAccountName")
							{
								$sAMAccountName = $hshUserInfo.Get_Item("sAMAccountName")
								$fileServer = Read-Variable "fileServer-profiles"
								$profilePath = "\\" + $fileserver + "\profiles$\" + $sAMAccountName
								$hshUserInfo.Add("profilePath",$profilePath)
							}
					}
			}
		
		If($failFunction -eq $true)
			{Return $false}
		Else
			{Return $hshUserInfo}
	}

Function Show-TextBoxPromptForm($title,$label,$text) #done
	{
		$failFunction = $null
		$failFunction = $false
		$blnUserText = $null
		$blnUserText = $false
		
		$objForm = New-Object System.Windows.Forms.Form
		$objForm.Text = "User Account Creation Form"
		$objForm.Size = New-Object System.Drawing.Size(290,335) 
		$objForm.StartPosition = "CenterScreen"
		
		$objForm.KeyPreview = $True
		$objForm.Add_KeyDown({if ($_.KeyCode -eq "Escape") 
		    {$failFunction = $true; $objForm.Close()}})
		$objForm.Add_FormClosing({If($blnUserText -eq $false){$failFunction = $true}; $objForm.Close})
		
		#textboxes
		$startPosition = 10
		$pad = 20
		$labelSize = @(280,15)
		$textboxSize = @(260,20)
			
		$objLabel = New-Object System.Windows.Forms.Label
		If($label.length -gt 51)
			{$objLabel.Size = New-Object System.Drawing.Size(280,40)}
		Else
			{$objLabel.Size = New-Object System.Drawing.Size(280,20)}
		$objLabel.Location = New-Object System.Drawing.Size(10,$startPosition);
		$objLabel.Text = $label
		$objForm.Controls.Add($objLabel)
		If($label.length -gt 51)
			{$startPosition = $startPosition + 40}
		Else
			{$startPosition = $startPosition + 20}
		
		$objTextBox = New-Object System.Windows.Forms.TextBox
		$objTextBox.Size = New-Object System.Drawing.Size(260,200) 
		$objTextBox.Text = $text
		$objTextBox.Location = New-Object System.Drawing.Size(10,($startPosition)) 
		$objTextBox.Multiline = $true
    $objTextBox.ScrollBars = "vertical"
    $objTextBox.AcceptsReturn = $false
		$objForm.Controls.Add($objTextBox)
		$startPosition = $startPosition + 200 + $pad
		
		$OKButton = New-Object System.Windows.Forms.Button
		$OKButton.Location = New-Object System.Drawing.Size(75,$startPosition)
		$OKButton.Size = New-Object System.Drawing.Size(75,23)
		$OKButton.Text = "OK"
		$OKButton.Add_Click({$x=$objTextBox.Text;$blnUserText = $true;$objForm.Close()})
		$objForm.Controls.Add($OKButton)
		
		$CancelButton = New-Object System.Windows.Forms.Button
		$CancelButton.Location = New-Object System.Drawing.Size(150,$startPosition)
		$CancelButton.Size = New-Object System.Drawing.Size(75,23)
		$CancelButton.Text = "Cancel"
		$CancelButton.Add_Click({$failFunction = $true; $objForm.Close()})
		$objForm.Controls.Add($CancelButton)
		
		$objForm.Topmost = $True
		
		$objForm.Add_Shown({$objForm.Activate()})
		
		[void]$objForm.ShowDialog()
		$retval = $objTextBox.Text
		
		$retval = $null
		If($failFunction -eq $true)
			{$retval = $false}
		Else
			{$retval = $objTextBox.Text}
		Return $retval
	}

Function Interpret-TextBoxImport($strBlock)
	{
		$attributes = @(`
			"givenName",`
			"sn",`
			"sAMAccountName",`
			"accountExpires",`
			"mail",`
			"telephoneNumber",`
			"physicalDeliveryOfficeName",`
			"description",`
			"comment",`
			"title",`
			"gidNumber",`
			"uidNumber",`
			"employeeID")
		
		$strOneLineBlock = $strBlock -replace("`r`n",",")
		$arrBlock = Parse-CSVStringToArray $strOneLineBlock
		
		$hshMappings = $null
		$hshMappings = @{}
		$hshMappings.Add("First Name: ","givenName")
		$hshMappings.Add("Last Name: ","sn")
		$hshMappings.Add("Office: ","physicalDeliveryOfficeName")
		$hshMappings.Add("Office Number: ","physicalDeliveryOfficeName")
		$hshMappings.Add("Phone #: ","telephoneNumber")
		$hshMappings.Add("Telephone: ","telephoneNumber")
		$hshMappings.Add("Buck ID Number: ","employeeID")
		$hshMappings.Add("Buck ID: ","employeeID")
		$hshMappings.Add("Other Comments: ","comment")
		$hshMappings.Add("Comments: ","comment")
		$hshMappings.Add("Expiration Date: ","accountExpires")
		
		$hshPreprocessedUserInfo = $null
		$hshPreprocessedUserInfo = @{}
		
		#import mapped and unmapped attributes
		$mapKeys = $hshMappings.Keys
		Foreach($row in $arrBlock)
			{
				Foreach($map in $mapKeys)
					{
						If($row -like ("*" + $map + "*"))
							{
								$rowValue = $row -replace($map,"")
								$attribute = $hshMappings.Get_Item($map)
								$keys = $null
								$keys = $hshPreprocessedUserInfo.Keys
								If($keys -notcontains $attribute)
									{$hshPreprocessedUserInfo.Add($attribute,$rowValue)}
							}
						Else
							{}
					}
				Foreach($attribute in $attributes)
					{
						If($row -like ("*" + $attribute + ": *"))
							{
								$rowValue = $row -replace($attribute,"")
								$rowValue = $rowValue.TrimStart(": ")
								$keys = $null
								$keys = $hshPreprocessedUserInfo.Keys
								If($keys -notcontains $attribute)
									{$hshPreprocessedUserInfo.Add($attribute,$rowValue)}
							}
						Else
							{}
					}
			}
		
		#reprocess some attributes
		If($hshPreprocessedUserInfo -eq $null -or $hshPreprocessedUserInfo -eq $false -or $hshPreprocessedUserInfo -eq "")
			{}
		Else
			{
				$keys = $null
				$keys = @()
				[array]$keys = $hshPreprocessedUserInfo.Keys
				Foreach($attribute in $keys)
					{
						write-host -f yellow "DEBUG`tchecking attribute: $attribute"
						Switch($attribute)
							{
								"telephoneNumber"
									{
										$phone = $hshPreprocessedUserInfo.Get_Item($attribute)
										#write-host -f yellow "DEBUG`told phone: $phone"
										If($phone -like "2-*")
											{
												$phone = "(614) 29" + $phone
												$hshPreprocessedUserInfo.Set_Item($attribute,$phone)
											}
										ElseIf($phone -like "292-*")
											{
												$phone = "(614) " + $phone
												$hshPreprocessedUserInfo.Set_Item($attribute,$phone)
											}
										ElseIf($phone -like "7-*")
											{
												$phone = "(614) 24" + $phone
												$hshPreprocessedUserInfo.Set_Item($attribute,$phone)
											}
										ElseIf($phone -like "247-*")
											{
												$phone = "(614) " + $phone
												$hshPreprocessedUserInfo.Set_Item($attribute,$phone)
											}
										ElseIf($phone -like "8-*")
											{
												$phone = "(614) 68" + $phone
												$hshPreprocessedUserInfo.Set_Item($attribute,$phone)
											}
										ElseIf($phone -like "688-*")
											{
												$phone = "(614) " + $phone
												$hshPreprocessedUserInfo.Set_Item($attribute,$phone)
											}
									#	write-host -f yellow "DEBUG`tnew phone: $phone"
									}
								"physicalDeliveryOfficeName"
									{
										$office = $hshPreprocessedUserInfo.Get_Item($attribute)
										$office = $office.TrimStart()
										$office = $office.TrimEnd()
									#	write-host -f yellow "DEBUG`told office: $office"
										If($office -like "*Evans Labs")
											{
												$office = $office -replace("Evans Labs","")
												$office = "EL" + $office
												$office = $office.TrimStart()
												$office = $office.TrimEnd()
												$hshPreprocessedUserInfo.Set_Item($attribute,$office)
											}
										ElseIf($office -like "*Evans Lab")
											{
												$office = $office -replace("Evans Lab","")
												$office = "EL" + $office
												$office = $office.TrimStart()
												$office = $office.TrimEnd()
												$hshPreprocessedUserInfo.Set_Item($attribute,$office)
											}
										ElseIf($office -like "*Evans")
											{
												$office = $office -replace("Evans","")
												$office = "EL" + $office
												$office = $office.TrimStart()
												$office = $office.TrimEnd()
												$hshPreprocessedUserInfo.Set_Item($attribute,$office)
											}
									#	write-host -f yellow "DEBUG`tnew office: $office"
									}
							}
					}
			}
		
		If($hshPreprocessedUserInfo -eq $null -or $hshPreprocessedUserInfo -eq $false -or $hshPreprocessedUserInfo -eq "")
			{$results = $false}
		Else
			{$results = $hshPreprocessedUserInfo}
		Return $results
	}

Function Build-UserTableFromGUI() #ECC
	{
		$failFunction = $false
		
		$hshRawUserTable = $null
		$hshRawUserTable = @{}
		
		#these are the attributes we're going to ask for, in the order we're going to ask.
		$attributes = $null
		$attributes = @(`
			"givenName",`
			"sn",`
			"sAMAccountName",`
			"accountExpires",`
			"mail",`
			"telephoneNumber",`
			"physicalDeliveryOfficeName",`
			"description",`
			"comment",`
			"title",`
			"employeeID")
			#"department",`

# Removed per sfabian on 10/25/12
#			"gidNumber",`
#			"uidNumber",`
			
					
		# do we want to build user table from GUI or text box? we should offer the text box, and fill in any others missing or that don't match regex
		[string]$strTextBoxImport = $null
		[string]$strTextBoxImport = Show-TextBoxPromptForm "Text Box Input" "If you want to import data from a text-block, please paste it below. Otherwise, press OK."
		$verifiedAttributes = $null
		If($strTextBoxImport -eq $false)
			{
				$failFunction = $true
			}
		ElseIf($strTextBoxImport -eq $null -or $strTextBoxImport -eq "")
			{}
		Else
			{
				$hshTextBoxImport = $null
				$hshTextBoxImport = Interpret-TextBoxImport $strTextBoxImport
				If($hshTextBoxImport -eq $null -or $hshTextBoxImport -eq "" -or $hshTextBoxImport -eq $false)
					{}
				Else
					{
						$importedAttributes = $null
						$importedAttributes = $hshTextBoxImport.Keys
					}
			}
		
#		write-host -f yellow "imported attributes: $importedAttributes"
#		$hshTextBoxImport | out-host
		
		Foreach($attribute in $attributes)
			{
				If($failFunction -ne $true)
					{
						#write-host -f green "hshRawUserTable:"
						#$hshRawUserTable | out-host
						Switch($attribute)
							{
								"uidNumber"
									{
										$keys = $hshRawUserTable.Keys
										If($keys -contains "gidNumber")
											{
												$gidNumber = $hshRawUserTable.get_item("gidNumber")
												If($gidNumber -eq $null -or $gidNumber -eq "")
													{}
												Else
													{
														$label = $null
														$label = Get-FieldInfo "label" $attribute $hshRawUserTable
														$text = $null
														$text = Get-FieldInfo "text" $attribute $hshRawUserTable
														
														$blnValidated = $null
														While($blnValidated -ne $true -and $failFunction -ne $true)
															{
																$guiInput = $null
																$guiInput = Show-ldapPromptsForm $attribute $label $text
																If($guiInput -eq $false)
																	{$failFunction = $true}
																Else
																	{
																		$blnValidated = $null
																		$blnValidated = validate-field $attribute $guiInput
																	}
															}
														If($failFunction -ne $true)
															{
																$msg = "INFO`tAttribute: " + $attribute + "`t`tread as: " + $guiInput
																Write-Out $msg "white" 2
																$hshRawUserTable.add($attribute,$guiInput)
															}
														Else
															{}
													}
											}
									}
								Default
									{
										$label = Get-FieldInfo "label" $attribute $hshRawUserTable
										#grab imported default text if it's there
										If($importedAttributes -eq $null -or $importedAttributes -eq $false -or $importedAttributes -eq "" -or $importedAttributes -notcontains $attribute)
											{$text = Get-FieldInfo "text" $attribute $hshRawUserTable}
										Else
											{$text = $hshTextBoxImport.Get_Item($attribute)}
										$validated = $false
										While($validated -ne $true -and $failFunction -ne $true)
											{
												$guiInput = Show-ldapPromptsForm $attribute $label $text
												If($guiInput -eq $false)
													{$failFunction = $true}
												Else
													{$validated = validate-field $attribute $guiInput}
											}
										If($failFunction -ne $true)
											{
												$msg = "INFO`tAttribute: " + $attribute + "`tread as: " + $guiInput
												Write-Out $msg "white" 2
												$hshRawUserTable.add($attribute,$guiInput)
											}
										Else
											{}
									}
							}
					}
				Else
					{}
			}
		
		If($failFunction -eq $true)
			{}
		Else
			{
				$hshVerifiedTable = Verify-UserTable $hshRawUserTable
				If($hshVerifiedTable -eq $false)
					{$failFunction = $true}
				Else
					{
						#Prune table of blank attributes
						$hshUsertable_Pruned = $null
						$hshUsertable_Pruned = @{}
						$keys = $null
						$keys = $hshVerifiedTable.keys
						Foreach($key in $keys)
							{
								$value = $hshVerifiedTable.Get_Item($key)
								If($value -ne $null -and $value -ne "")
									{$hshUsertable_Pruned.Add($key,$value)}
							}
						
						#Remove trailing spaces
						$hshUsertable_Trimmed = $null
						$hshUsertable_Trimmed = @{}
						$keys = $null
						$keys = $hshUserTable_Pruned.keys
						Foreach($key in $keys)
							{
								$value = $hshUserTable_Pruned.Get_Item($key)
								If($value -ne $null -and $value -ne "")
									{
										$trimmedValue = $value.Trim()
										$hshUsertable_Trimmed.Add($key,$trimmedValue)
									}
							}
						
						$hshFinalUsertable = $null
						$hshFinalUsertable = $hshUsertable_Trimmed
						
						$strUnformattedDisplayName = $hshFinalUsertable.givenName + " " + $hshFinalUsertable.sn
						$strFormattedDisplayName = (Get-Culture).TextInfo.ToTitleCase($strUnformattedDisplayName)
						$hshFinalUserTable.Add("displayName",$strFormattedDisplayName)
						$upnSuffix = Read-Variable "domainFull"
						$userPrincipalName = $hshFinalUserTable.sAMAccountName + "@" + $upnSuffix
						$hshFinalUserTable.Add("userPrincipalName",$userPrincipalName)
				
#						#add other unix attributes
#						$keys = $hshFinalUserTable.Keys
#						If($keys -contains "UIDNumber")
#							{
#								$sAMAccountName = $hshFinalUserTable.Get_Item("sAMAccountName")
#								$arrProxySuffixes = $null
#								$arrProxySuffixes = Read-Variable "ProxyAddressSuffixes"
#								[array]$arrProxyAddress = @()
#								If($arrProxySuffixes -ne $null)
#									{
#										Foreach($suffix in $arrProxySuffixes)
#											{
#												[string]$proxyLine = $sAMAccountName + "@" + $suffix
#												$arrProxyAddress += $proxyLine
#											}
#										
#										Write-host -f yellow "proxyAddresses: $arrProxyAddress"
#										#set them in hshuserinfo
#										$arrNewProxyAddr = @()
#										$arrNewProxyAddr += "prox.2@chemistry.ohio-state.edu"
#										$arrNewProxyAddr += "prox.2@chemistry.osu.edu"
#										$arrNewProxyAddr += "prox.2@chem.osu.edu"
#										$hshFinalUserTable.Add("proxyAddresses",$arrNewProxyAddr)
#									}
#								Else
#									{
#										$msg = "Error`tCould not build proxyAddress attribute."
#										Throw-Warning $msg
#										$failFunction = $true
#									}
#							}
					}
			}
		
		#add profilePath
		If($failFunction -eq $false)
			{
				$keys = $hshFinalUserTable.Keys
				If($keys -contains "profilePath")
					{}
				Else
					{$hshFinalUserTable.Add("profilePath","placeholder")}
			}
		
		If($failFunction -eq $true)
			{return $false}
		Else
			{return $hshFinalUserTable}
	}

Function Get-FieldInfo($category,$field,$usertable) #done
	{
		switch($category)
			{
				"label"
					{
						switch($field)
							{
								"sAMAccountName" {$retval = "Enter the sAMAccountName (username). Usually lastname.## ."}
								"givenName" {$retval = "Enter the givenName (first name)."}
								"sn" {$retval = "Enter the sn (surname or last name)."}
								"accountExpires" {$retval = "Enter the accountExpires date (expiration date). Format: mm/dd/yyyy."}
								"telephoneNumber" {$retval = "Enter the telephoneNumber number. Format: (###) ###-####. Ex. (614) 292-6446"}
								"physicalDeliveryOfficeName" {$retval = "Enter the physicalDeliveryOfficeName (office number). Format: LL####(-L). Ex. NW2105-A"}
								"mail" {$retval = "Enter the desired email address. This should always be username@domain. Leave blank for no email address."}
								"description" {$retval = "Enter a brief description of the account. This is world-readable."}
								"comment" {$retval = "Enter a comment about this account. This is only readable by support."}
								"title" {$retval = "Enter the user's title (Job Title)."}
								"department" {$retval = "Enter the user's department."}
								"uidNumber" {$retval = "Enter the desired unix uidNumber. This box cannot be left blank. The text box is pre-populated with the next available number."}
								"gidNumber" {$retval = "Enter the desired unix gidNumber. Leave blank for no GID. You can also try typing a faculty member's lastname."}
								"employeeID" {$retval = "Enter the user's buckID. Format: 10 digits."}
							}
					}
				"text"
					{
						Switch($field)
							{
								"givenName" {$retval = "givenName"}
								"sn" {$retval = "sn"}
								"sAMAccountName" {$retval = ((($usertable.get_item("sn") + ".#") -replace(" ",""))).ToLower()}
								"accountExpires" {$a = get-date; $a = $a.addyears(2); $retval = $a.toshortdatestring()}
								"telephoneNumber" {$retval = "(614) 292-####"}
								"physicalDeliveryOfficeName" {$retval = "XX####-X"}
								"mail"
									{
										$domainFull = Read-Variable "domainFull"
										$retval = ($usertable.get_item("sAMAccountName") + "@" + $domainFull)
									}
								"description" {$retval = "description"}
								"comment" {$retval = ""}
								"title" {$retval = ""}
								"department" {$retval = ""}
								"uidNumber" {$retval = Find-NextAvailableUID}
								"gidNumber" {$retval = ""}
								"employeeID" {$retval = "##########"}
							}
					}
			}
		return $retval
	}

Function Show-ldapPromptsForm($title,$label,$text) #done
	{
		$failFunction = $false
		$blnUserText = $null
		$blnUserText = $false
		
		$objForm = New-Object System.Windows.Forms.Form
		$objForm.Text = "User Account Creation Form"
		$objForm.Size = New-Object System.Drawing.Size(300,150) 
		$objForm.StartPosition = "CenterScreen"
		
		$objForm.KeyPreview = $True
		$objForm.Add_KeyDown({if ($_.KeyCode -eq "Enter") 
		    {$blnUserText = $true;$objForm.Close()}})
		$objForm.Add_KeyDown({if ($_.KeyCode -eq "Escape") 
		    {$failFunction = $true; $objForm.Close()}})
		
		$objForm.Add_FormClosing( { If($blnUserText -eq $false){$failFunction = $true}; $objForm.Close}) 
		
		#textboxes
		$startPosition = 10
		$pad = 20
		$labelSize = @(280,15)
		$textboxSize = @(260,20)
			
		$objLabel = New-Object System.Windows.Forms.Label
		If($label.length -gt 51)
			{$objLabel.Size = New-Object System.Drawing.Size(280,40)}
		Else
			{$objLabel.Size = New-Object System.Drawing.Size(280,20)}
		$objLabel.Location = New-Object System.Drawing.Size(10,$startPosition);
		$objLabel.Text = $label
		$objForm.Controls.Add($objLabel)
		If($label.length -gt 51)
			{$startPosition = $startPosition + 40}
		Else
			{$startPosition = $startPosition + 20}
				
		$objTextBox = New-Object System.Windows.Forms.TextBox
		$objTextBox.Size = New-Object System.Drawing.Size(260,20) 
		$objTextBox.Text = $text
		$objTextBox.Location = New-Object System.Drawing.Size(10,($startPosition)) 
		$objForm.Controls.Add($objTextBox)
		$startPosition = $startPosition + 20 + $pad
		
		$OKButton = New-Object System.Windows.Forms.Button
		$OKButton.Location = New-Object System.Drawing.Size(75,$startPosition)
		$OKButton.Size = New-Object System.Drawing.Size(75,23)
		$OKButton.Text = "OK"
		$OKButton.Add_Click({$x=$objTextBox.Text;$blnUserText = $true;$objForm.Close()})
		$objForm.Controls.Add($OKButton)
		
		$CancelButton = New-Object System.Windows.Forms.Button
		$CancelButton.Location = New-Object System.Drawing.Size(150,$startPosition)
		$CancelButton.Size = New-Object System.Drawing.Size(75,23)
		$CancelButton.Text = "Cancel"
		$CancelButton.Add_Click({$failFunction = $true; $objForm.Close()})
		$objForm.Controls.Add($CancelButton)
		
		$objForm.Topmost = $True
		
		$objForm.Add_Shown({$objForm.Activate()})
		
		[void]$objForm.ShowDialog()
		$retval = $objTextBox.Text
		
		$retval = $null
		If($failFunction -eq $true)
			{$retval = $false}
		Else
			{$retval = $objTextBox.Text}
		Return $retval
	}

Function Validate-Field($field,$text) #done
	{
		$failFuncton = $false
		
		$regex = Find-RegexForAttribute $field
		
		Switch($field)
			{
				"sAMAccountName"
					{
						#is the sAMAccountName valid?
						If($text -notmatch $regex)
							{
								$msg = "Sorry, the username contains invalid characters. (letters, numbers, ., and _ only)"
								Write-host -f yellow $msg
								$results = $false
							}
						ElseIf($text -eq "")
							{
								$msg = "Sorry, sAMAccountName is a required attribute."
								Write-host -f yellow $msg
								$results = $false
							}
						Else
							{
								#is it unique?
								$test = Get-DNbySAMAccountName $text "user"
								If($test -eq $false)
									{$results = $true}
								Else
									{
										$msg = "Sorry, the username """ + $text + """ is already taken."
										Write-host -f yellow $msg
									}
							}
					}
				"givenName"
					{
						If($text -notmatch $regex)
							{
								$msg = "Sorry, the givenName contains invalid characters (letters and ' only)."
								Write-host -f yellow $msg
								$results = $false
							}
						ElseIf($text -eq "")
							{
								$msg = "Sorry, givenName is a required attribute."
								Write-host -f yellow $msg
								$results = $false
							}
						Else
							{$results = $true}
					}
				"sn"
					{
						If($text -notmatch $regex)
							{
								$msg = "Sorry, the sn contains invalid characters (letters and ' only)."
								Write-host -f yellow $msg
								$results = $false
							}
						ElseIf($text -eq "")
							{
								$msg = "Sorry, sn is a required attribute."
								Write-host -f yellow $msg
								$results = $false
							}
						Else
							{$results = $true}
					}
				"mail"
					{
						If($text -notmatch $regex)
							{
								$msg = "Sorry, the email address is not valid."
								Write-host -f yellow $msg
								$results = $false
							}
						ElseIf($text -eq "")
							{
								$msg = "Sorry, mail is a required attribute."
								Write-host -f yellow $msg
								$results = $false
							}
						Else
							{$results = $true}
					}
				"accountExpires"
					{
						If($text -notmatch $regex)
							{
								$msg = "Sorry, the date does not seem to be valid. Please use the format mm/dd/yyyy ."
								Write-host -f yellow $msg
								$results = $false
							}
						Else
							{$results = $true}
					}
				"telephoneNumber"
					{
						If($text -notmatch $regex)
							{
								$msg = "Sorry, the telephoneNumber number does not seem to match the required format. Please use (###) ###-#### ."
								Write-host -f yellow $msg
								$results = $false
							}
						Else
							{$results = $true}
					}
				"physicalDeliveryOfficeName"
					{
						If($text -notmatch $regex)
							{
								$msg = "Sorry, the telephoneNumber number does not seem to match the required format. Please use LL####-?? ."
								Write-host -f yellow $msg
								$results = $false
							}
						Else
							{$results = $true}
					}
				"uidNumber"
					{
						If($text.length -gt 5)
							{
								$msg = "Sorry, the UID must be 3-5 digits."
								Write-host -f yellow $msg
								$results = $false
							}
						ElseIf($text -notmatch $regex)
							{
								$msg = "Sorry, the UID must be 3-5 digits."
								Write-host -f yellow $msg
								$results = $false
							}
						ElseIf($text -eq "")
							{
								$msg = "Sorry, the script cannot accept a blank UID value since a GID value is already specified."
								Write-host -f yellow $msg
								$msg = "Please press cancel and restart the script if you did not intend to specify unix attributes."
								Write-host -f yellow $msg
								$results = $false
							}
						Else
							{
								$blnTextCheck = Check-UIDUnique $text
								If($blnTextCheck -eq $true)
									{
										#unique?
										$msg = "Sorry, the UID is taken."
										Write-host -f yellow $msg
										$nextAvailableUID = Find-NextAvailableUID
										$msg = "The next available looks like it's:" + $nextAvailableUID
										Write-host -f yellow $msg
										$results = $false
									}
								Else
									{$results = $true}
							}
					}
				"gidNumber"
					{
						If($text -eq "")
							{$results = $true}
						ElseIf($text -notmatch $regex)
							{
								$searchResults = Search-ForGID $text
								$results = $false
							}
						Else
							{
								$test = check-gidExists $text
								If($test -eq $false)
									{
										$msg = "Sorry, the GID doesn't appear to exist. Try typing part of the name to search."
										Write-host -f yellow $msg
									}
								Else
									{$results = $true}
							}
					}
				"employeeID"
					{
						If($text -notmatch $regex)
							{
								$msg = "Sorry, the BuckID should be 10 digits (no more, no less, no letters)."
								Write-host -f yellow $msg
								$results = $false
							}
						ElseIf($text -eq "")
							{
								$msg = "Sorry, employeeID is a required attribute."
								Write-host -f yellow $msg
								$results = $false
							}
						Else
							{$results = $true}
					}
				default
					{$results = $true}
			}
		
		return $results
	}

Function Search-ForGroup($groupCN) #done
	{
		$failFunction = $false
		$msg = "Searching for group """ + $groupCN + """."
		Write-Host -f yellow $msg
		
		$compGroupPrefix = $null
		$compGroupPrefix = Read-Variable "computerGroupPrefix"
		
		#grab all grops with GID's
		$searchRoot = [ADSI]''
		$searcher = new-object System.DirectoryServices.DirectorySearcher($searchRoot)
		$searcher.filter = "(&(objectClass=group)(cn=" + $groupCN + "*)(!cn=" + $compGroupPrefix + "))"
		$searchResults = $searcher.findall()
		
		$groupsFound = $null
		$groupsFound = @()
#		###replace this with a better ldap search filter!!!
#		foreach($group in $searchResults)
#			{
#				$groupPath = $group.path
#				$objGroup = [adsi]$groupPath
#				$objGroupCN = Pull-LDAPAttribute $objGroup "cn"
#				If($objGroupCN -like ("*" + $compGroupPrefix + "*"))
#					{}
#				Else
#					{$groupsFound += $objGroupCN}
#			}
		
		foreach($group in $searchResults)
			{
				$groupPath = $group.path
				$groupCN = Convert-SearchPathtoCN-Local $groupPath
				$groupsFound += $groupCN
			}
		
		$searchResults.Dispose()
		$searchResults = $null
		$searcher.Dispose()
		$searcher = $null
		
		If($groupsFound.count -eq 0)
			{
				$msg = "Sorry, no match found."
				Write-Host -f yellow $msg
				$failFunction = $true
			}
		Else
			{
				$msgs = $null
				$msgs = @()
				$msgs += "Found the following groups:"
				Foreach($groupCNFound in $groupsFound)
					{$msgs += "`t*" + $groupCNFound}
				Foreach($msg in $msgs)
					{write-host -f yellow $msg}
			}
		
		If($failFunction -eq $true)
			{$retval = $false}
		Else
			{$retval = $groupsFound}
		Return $retval
	}

Function Search-ForGID($groupCN) #done
	{
		$failFunction = $false
		$blnMatch = $null
		$blnMatch = $false
		
		$msg = "Searching for all groups with a GID number that match """ + $groupCN + """."
		Write-host -f yellow $msg
		
		#grab all grops with GID's
		$searchRoot = [ADSI]''
		$searcher = new-object System.DirectoryServices.DirectorySearcher($searchRoot)
		$searcher.filter = "(&(objectClass=group)(cn=" + $groupCN + "*)(gidNumber>=0))"
		$searchResults = $searcher.findall()
		
		$hshMatchedGroups = $null
		$hshMatchedGroups = @{}
		foreach($group in $searchResults)
			{
				$groupDN = $group.path
				$groupDN = $groupDN.Substring(7)
				$objGroup = [adsi]("LDAP://" + $groupDN)
				$objGroupCN = Pull-LDAPAttribute $objGroup "cn"
				If($objGroupCN -like ("*" + $groupCN + "*"))
					{
						#Write-Host -f green "FOUND A MATCH!!"
						$gidNumber = Pull-LDAPAttribute $objGroup "gidNumber"
						$hshMatchedGroups.add($gidNumber,$objGroupCN)
						$blnMatch = $true
					}
			}
		
		$searchResults.Dispose()
		$searchResults = $null
		$searcher.Dispose()
		$searcher = $null
		
		If($blnMatch)
			{
				$msgs = $null
				$msgs = @()
				$msgs += "Found the following group(s):"
				$keys = $hshMatchedGroups.Keys
				Foreach($gidNumber in $keys)
					{
						$groupCN = $hshMatchedGroups.Get_Item($gidNumber)
						$msgs += "`t*" + $groupCN + " with gid number " + $gidNumber
					}
				Foreach($msg in $msgs)
					{write-host -f yellow $msg}
			}
		Else
			{
				$msg = "Sorry, no match found for " + $groupCN
				Write-Host -f yellow $msg
			}
		
		If($failFunction -eq $true)	
			{$retval = $false}
		Else
			{$retval = $blnMatch}
		Return $retval
	}

Function Verify-UserTable($userTable) #done
	{
		$failFunction = $false
		#show the user the usertable, ask if they want to change anything.
		$done = $null
		$done = $false
		While($done -eq $false)
			{
				If($failFunction -ne $true)
					{
						Write-Host -f green "`n`t---- User Table ----"
						$userTable.GetEnumerator() | out-host
						
						$msgs = $null
						$msgs = @()
						$msgs += "Do you want to change anything in the table above?"
						$msgs += "If so, type the attribute name. You don't have to type the full name, just enough that it's unique."
						$msgs += "If not, or when done, just hit Enter."
						Foreach($msg in $msgs)
							{Write-Host -f white $msg}
						
						$userInput = Read-Host ">"
						If($userInput -eq "")
							{$done = $true}
						Else
							{
								$keyToChange = $null
								$keys = $userTable.Keys
								Foreach($key in $keys)
									{
										If($key -like ($userInput + "*"))
											{$keyToChange = $key}
									}
								If($KeytoChange -eq $null)
									{Write-Host "Could not match ""$userInput"" to an ldap attribute. Sorry!"}
								Else
									{
										$label = Get-FieldInfo "label" $keyToChange $userTable
										$text = $userTable.$keyToChange
										$blnValidated = $false
										While($blnValidated -ne $true)
											{
												$guiInput = Show-ldapPromptsForm $keyToChange $label $text
												If($guiInput -eq $false)
													{
														Write-Host -f yellow "Script aborted by user."
														$failFunction = $true
													}
												$blnValidated = validate-field $keyToChange $guiInput
											}
										$userTable.Set_Item($keyToChange,$guiInput)
									}
							}
						Write-Host -f green $starline
					}
			}
		
		If($failFunction -eq $true)
			{Return $false}
		Else
			{Return $userTable}
	}

Function Build-GroupMembershipArray() #done
	{ 
		$failFunction = $false
		
		#grab quota group dn's
		$strQuotaGroupsCN = Read-Variable "quotaGroupsCN"
		$objQuotaGroupDN = Get-DNbyCN $strQuotaGroupsCN "group"
		$objQuotaGroup = [adsi]("LDAP://" + $objQuotaGroupDN)
		$quotaGroupDNs = $objQuotaGroup.member
		
		#Add Groups
		$groupMemberships = $null
		[array]$groupMemberships = @()
		$blnGroupsComplete = $null
		$blnGroupsComplete = $false
		While($blnGroupsComplete -ne $true -and $failFunction -ne $true)
			{
				$guiInput = Show-GroupPromptsForm $textBoxText
				$textBoxText = $null
				
				If($guiInput -eq $false)
					{$failFunction = $true}
				ElseIf($guiInput -eq "")
					{
						#if web-only, ignore this.
						$strWebOnlyGroupCN = $null
						$strWebOnlyGroupCN = Read-Variable "webOnlyGroupCN"
						$strWebOnlyGroupDN = $null
						$strWebOnlyGroupDN = Get-DNbyCN $strWebOnlyGroupCN
						
						#make sure we have a quota group and a role group
						$blnMemberOfRoleGroup = $null
						$blnMemberOfRoleGroup = $false
						$blnMemberOfQuotaGroup = $null
						$blnMemberOfQuotaGroup = $false
						
						$quotaGroupsCN = Read-Variable "quotaGroupsCN"
						$objQuotaGroupsDN = Get-DNbyCN $quotaGroupsCN "group"
						$objQuotaGroups = [adsi]("LDAP://" + $objQuotaGroupsDN)
						$arrQuotaGroupDNs = $objQuotaGroups.member
						
						Foreach($groupCN in $groupMemberships)
							{
								$groupDN = Get-DNbyCN $groupCN "group"
								If($arrQuotaGroupDNs -contains $groupDN -or $groupDN -eq $strWebOnlyGroupDN)
									{$blnMemberOfQuotaGroup = $true}
								Else
									{
										If($groupCN -eq "Domain Users")
											{}
										Else
											{$blnMemberOfRoleGroup = $true}
									}
							}
						
						If($blnMemberOfQuotaGroup -eq $false -or $blnMemberOfRoleGroup -eq $false)
							{
								$msg = "The user must be a member of at least 1 quota group and 1 non-quota group to continue."
								write-host -f yellow $msg
								Write-Host "`n--List of Quota Groups--`n"
								Foreach($quotaGroup in $quotaGroupDNs)
									{
										$objGroup = [adsi]("LDAP://" + $quotaGroup)
										$objGroupCN = Pull-LDAPAttribute $objGroup "cn"
										Write-Host -f white $objGroupCN
									}
								Write-Host ""
							}
						Else
							{$blnGroupsComplete = $true}
					}
				Else
					{
						$blnGroupExists = Check-DoesGroupExist $guiInput
						If($blnGroupExists -eq $true)
							{
								$groupCN = $guiInput
								$groupDN = Get-DNbyCN $groupCN "group"
								$msg = "Adding group: " + $groupDN
								Write-Host -f green $msg
								$groupMemberships += $groupCN
							}
						Else
							{
								[array]$arrGroupsFound = $null
								$arrGroupsFound = Search-ForGroup $guiInput
								If($arrGroupsFound -eq $false -or $groupSearch -eq "" -or ($arrGroupsFound[0]) -eq $false)
									{$textBoxText = ""}
								Else
									{$textBoxText = $arrGroupsFound[0]}
							}
					}
			}
		
		If($failFunction -eq $true)
			{Return $false}
		Else
			{Return $groupMemberships}
	}

Function Show-GroupPromptsForm($text) #done
	{
		$failFunction = $null
		$failFunction = $false
		$blnUserText = $null
		$blnUserText = $false
		
		$objForm = $null
		$objForm = New-Object System.Windows.Forms.Form 
		$objForm.Text = "User Account Creation Form"
		$objForm.Size = New-Object System.Drawing.Size(390,172)
		$objForm.StartPosition = "CenterScreen"
		
		$objForm.KeyPreview = $True
		$objForm.Add_KeyDown({if ($_.KeyCode -eq "Enter"){$blnUserText = $true;$objForm.Close()}})
		$objForm.Add_KeyDown({if ($_.KeyCode -eq "Escape"){$failFunction = $true; $objForm.Close()}})
		$objForm.Add_FormClosing({If($blnUserText -eq $false){$failFunction = $true}; $objForm.Close})
		
		#textboxes
		$startPosition = 10
		$pad = 20
		$labelSize = @(280,15)
		$textboxSize = @(260,20)
		
		$objLabel = New-Object System.Windows.Forms.Label
		$objLabel.Size = New-Object System.Drawing.Size(350,40)
		$objLabel.Location = New-Object System.Drawing.Size(10,$startPosition);
		$objLabel.Text = "Enter a group to add.`
			You must enter the full cn (common name) of the group.`
			Typing a partial name will search. Leave blank to continue."
		$objForm.Controls.Add($objLabel)
		$startPosition = $startPosition + 40
		
		$objTextBox = New-Object System.Windows.Forms.TextBox
		$objTextBox.Size = New-Object System.Drawing.Size(350,20) 
		$objTextBox.Text = $text
		$objTextBox.Location = New-Object System.Drawing.Size(10,($startPosition)) 
		$objForm.Controls.Add($objTextBox)
		$startPosition = $startPosition + 20 + $pad
		
		$OKButton = New-Object System.Windows.Forms.Button
		$OKButton.Location = New-Object System.Drawing.Size(115,$startPosition)
		$OKButton.Size = New-Object System.Drawing.Size(75,23)
		$OKButton.Text = "OK"
		$OKButton.Add_Click({$x=$objTextBox.Text;$blnUserText = $true;$objForm.Close()})
		$objForm.Controls.Add($OKButton)
		
		$CancelButton = New-Object System.Windows.Forms.Button
		$CancelButton.Location = New-Object System.Drawing.Size(190,$startPosition)
		$CancelButton.Size = New-Object System.Drawing.Size(75,23)
		$CancelButton.Text = "Cancel"
		$CancelButton.Add_Click({$failFunction = $true; $objForm.Close()})
		$objForm.Controls.Add($CancelButton)
		
		$objForm.Topmost = $True
		
		$objForm.Add_Shown({$objForm.Activate()})
		[void]$objForm.ShowDialog()
		
		$retval = $null
		If($failFunction -eq $true)
			{$retval = $false}
		Else
			{$retval = $objTextBox.Text}
		Return $retval
	}

### ___Other Functions___

Function Verify-GroupMemberships($groupMemberships)
	{
		$failFunction = $false
		
		#show the user the usertable, ask if they want to change anything.
		$done = $null
		$done = $false
		While($done -eq $false)
			{
				$msgs = $null
				$msgs = @()
				$msgs += "Do you want to modify the group memberships in the list above?"
				$msgs += "If so, type ""add"" or ""remove"" the attribute name."
				$msgs += "If not, just hit Enter."
				Foreach($msg in $msgs)
					{Write-Host -f yellow $msg}
				
				$userInput = Read-Host ">"
				If($userInput -eq "")
					{$done = $true}
				ElseIf($userInput -eq "add")
					{Write-Host -f yellow ""}
				Else
					{
						$keyToChange = ""
						Foreach($key in $userTable.keys)
							{
								If($key -match $userInput)
									{$keyToChange = $key}
							}
						If($KeytoChange -eq "")
							{Write-Host "Could not match ""$userInput"" to an ldap attribute. Sorry!"}
						Else
							{
								$label = get-info "label" $keyToChange
								$text = $userTable.$keyToChange
								$blnValidated = $false
								While($blnValidated -ne $true -and $failFunction -ne $true)
									{
										$guiInput = Show-ldapPromptsForm $keyToChange $label $text
										If($guiInput -eq $false)
											{
												Write-Host -f yellow "Script aborted by user."
												$failFunction = $true
											}
										Else
											{
												$blnValidated = validate-field $keyToChange $guiInput
											}
									}
								If($failFunction -ne $true)
									{$userTable.$keyToChange = $text}
							}
					}
				Write-Host -f cyan $starline
			}
		
		If($failFunction -eq $true)
			{Return $false}
		Else
			{Return $userTable}
	}

Function Validate-UserInfo($hshUserInfo,$mode) #ECC
	{
		#sanitizes our data. The returned userInfo should be clean, and not able to hoze Process-User().
		$failFunction = $false
		#the framework for optionalAttributeValid is created but the tests aren't implemented.
		Switch($mode)
			{
				"processing"
					{
						$tests = @(`
							"requiredAttribtesForProcessingPresent",`
							"attributesMatchRegex")
					}
				"creation"
					{
						$tests = @("requiredAttribtesForCreationPresent",`
							"attributesMatchRegex",`
							"attributesValid")
					}
				Default
					{
						$msg = "ERROR`t`tValidate-UserInfo was passed a mode it doesn't understand. Mode: """ + $mode + """."
						Throw-Warning $msg
						$failFunction = $true
					}
			}
		
		If($failFunction -eq $false)
			{
				$arrMsg = $null
				$arrMsg = @()
				$arrMsg += "INFO`t`tRunning the following validation tests:"
				Foreach($test in $tests)
					{$arrMsg += "INFO`t`t`t*" + $test}
				Foreach($msg in $arrMsg)
					{Write-Out $msg "white" 2}
				
				Foreach($test in $tests)
					{
						$validationTestResults = $false
						If($failFunction -ne $true)
							{
								$msg = "ACTION`t`tBeginning validation test: """ + $test + """."
								Write-Out $msg "white" 2
								
								$validationTestResults = Run-ValidationTest $test $hshUserInfo
								If($validationTestResults -eq $true)
									{
										$msg = "INFO`t`t`tValidation test """ + $test + """ passed successfully."
										Write-Out $msg "white" 3
									}
								Else
									{
										$failFunction = $true
										$warningMsg = "ERROR`tValidation test """ + $test + """ failed."
										Throw-Warning $warningMsg
									}
							}
					}
			}
		
		If($failFunction -eq $false)
			{return $true}
		Else
			{return $false}
	}

Function Run-ValidationTest($test,$hshUserInfo) #ECC
	{
		$results = $false
		$failFunction = $false
		Switch($test)
			{
				"requiredAttribtesForCreationPresent"
					{$results = Check-RequiredAttributesPresent $hshUserInfo "creation"}
				"requiredAttribtesForProcessingPresent"
					{$results = Check-RequiredAttributesPresent $hshUserInfo "processing"}
				"attributesMatchRegex"
					{$results = Check-AttributesMatchRegex $hshUserInfo}
				"attributesValid"
					{$results = Check-AttributesValid $hshUserInfo}
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

Function Process-UserInfo($hshUserInfo)
	{
		$keys = $null
		$keys = $hshUserInfo.Keys
		$hshNewUserInfo = $null
		$hshNewUserInfo = @{}
		
		#process specific attributes and delete empty ones
		Foreach($attribute in $keys)
			{
				$attributeName = $null
				$attributeValue = $null
				$processedValue = $null
				
				$attributeName = $attribute
				$attributeValue = $hshUserInfo.Get_Item($attributeName)
				$processedValue = Process-Attribute $attributeName $attributeValue
				#write-host -f green "name: $attributeName`tValue: $processedValue"
				If($processedValue -ne $null -and $processedValue -ne "")
					{$hshNewUserInfo.Add($attributeName,$processedValue)}
			}
		
		#add missing unix attributes
		$newKeys = $null
		$newKeys = $hshNewUserInfo.Keys
		If($newKeys -contains "uidNumber" -or $newKeys -contains "gidNumber")
			{
				#Add msSFU30NisDomain
				If($newKeys -contains "msSFU30NisDomain")
					{}
				Else
					{
						$domainShort = Read-Variable "domainShort"
						$hshNewUserInfo.Add("msSFU30NisDomain",$domainShort)
					}
				
				#Add unixHomeDirectory
				If($newKeys -contains "unixHomeDirectory")
					{}
				Else
					{
						$sAMAccountName = $null
						$sAMAccountName = $hshNewUserInfo.Get_Item("sAMAccountName")
						$unixHomeDirectory = $null
						$unixHomeDirectory = "/export/home/" + $sAMAccountName
						$hshNewUserInfo.Add("unixHomeDirectory",$unixHomeDirectory)
					}
				
				#Add loginShell
				If($newKeys -contains "loginShell")
					{}
				Else	
					{
						$loginShell = $null
						$loginShell = "/bin/tcsh"
						$hshNewUserInfo.Add("loginShell",$loginShell)
					}
				
				#Add proxyAddresses
				[string]$sAMAccountName = $hshNewUserInfo.Get_Item("sAMAccountName")
				$arrSuffix = Read-Variable "proxyAddressSuffixes"
				[array]$proxyAddresses = @()
				Foreach($suffix in $arrSuffix)
					{
						[string]$newLine = "SMTP:" + $sAMAccountName + $suffix
						$proxyAddresses += $newLine
					}
				$hshNewUserInfo.Add("proxyAddresses",$proxyAddresses)
			}
		
		#add missing userPrincipalName
		If($newKeys -contains "userPrincipalName")
			{}
		Else
			{
				$sAMAccountName = $null
				$sAMAccountName = $hshNewUserInfo.Get_Item("sAMAccountName")
				$upnSuffix = Read-Variable "domainFull"
				$userPrincipalName = $null
				$userPrincipalName = $sAMAccountName + "@" + $upnSuffix
				$hshNewUserInfo.Add("userPrincipalName",$userPrincipalName)
			}
		
		Return $hshNewUserInfo
	}

Function Process-Attribute($attributeName,$attributeValue)
	{
		#Remove trailing and double spaces
		$tmpValue = $null
		[string]$tmpValue = $attributeValue
		If($tmpValue -like "*  *")
			{
				While($tmpValue -like "*  *")
					{$tmpValue = $tmpValue.replace("  "," ")}
			}
		$attributeValue = $tmpValue.Trim()
		
		Switch($attributeValue)
			{
				"memberof"
					{
						$processedValue = $attributeValue
						
#						#correct for double-spaces
#						$groupList = $attributeValue
#						If($groupList -like "*  *")
#							{
#								$msg = "ACTION`t`tCorrecting group names by replacing all ""  "" with "" ""."
#								Write-Out $msg "white" 2
#								While($groupList -like "*  *")
#									{$groupList = $groupList.replace("  "," ")}
#								$processedValue = $groupList
#							}
						
						#correct for starting\trailing spaces inside the CSV string
						$arrMemberof = @()
						$groups = $attributeValue.Split(",")
						If($groups -is [array])
							{
								Foreach($group in $groups)
									{
										$newGroup = $group
										$newGroup = $newGroup.TrimStart()
										$newGroup = $newGroup.TrimEnd()
										$arrMemberOf += $newGroup
									}
								}
						Else
							{
								$newGroup = $attributeValue
								$newGroup = $newGroup.TrimStart()
								$newGroup = $newGroup.TrimEnd()
								$arrMemberOf += $newGroup
							}
						
						#convert array back to string
						$OFS = ","
						[string]$strMemberOf = $arrMemberOf
						$OFS = " "
						
						$processedValue = $strMemberOf
					}
				"sAMAccountName"
					{$processedValue = $attributeValue.ToLower()}
				"mail"
					{$processedValue = $attributeValue.ToLower()}
				"userPrincipalName"
					{$processedValue = $attributeValue.ToLower()}
				Default
					{$processedValue = $attributeValue}
			}
		Return $processedValue
	}

Function Check-RequiredAttributesPresent($hshUserInfo,$strMode)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		$results = $true
		
		Switch($strMode)
			{
				"processing"
					{
						$requiredAttributes = Read-Variable "requiredAttributesForProcessing"
					}
				"creation"
					{
						$requiredAttributes = Read-Variable "requiredAttributesForCreation"
					}	
				Default
					{
						$msg = "WARNING`tCannot check required attributes because the given processing mode is not defined!"
						Throw-Warning $msg
						$failThisFunction = $true
					}
			}
		
		If($failThisFunction -eq $false)
			{
				$keys = $hshUserInfo.Keys
				$msg = "ACTION`t`t`tChecking the presence of the required attributes for " + $strMode + "."
				Write-Out $msg "white" 4
				Foreach($requiredAttribute in $requiredAttributes)
					{	
						$msg = "INFO`t`t`tTesting for the attribute: """ + $requiredAttribute + """."
						Write-Out $msg "darkcyan" 3
						If(($keys -contains $requiredAttribute) -eq $false)
							{
								$results = $false
								$warningMsg = "ERROR`tThe following required attribute is missing: """ + $requiredAttribute + """."
								Throw-Warning $warningMsg
								Break
							}
						ElseIf(($hshUserInfo.Get_Item($requiredAttribute)) -eq $null)
							{
								$results = $false
								$warningMsg = "ERROR`tThe following required attribute is null: """ + $requiredAttribute + """."
								Throw-Warning $warningMsg
								Break
							}
					}
			}
		Else
			{$results = $false}
		
		Return $results
	}

Function Check-AttributesMatchRegex($hshUserInfo)
	{
		$results = $true
		$keys = $hshUserInfo.Keys
		Foreach($attribute in $keys)
			{
				$regex = $null
				If($results -ne $false)
					{
						$regex = Find-RegexForAttribute $attribute
						If($regex -ne $null -and $regex -ne "" -and $regex -ne $false)
							{
								$attributeValue = $hshUserInfo.Get_Item($attribute)
								If($attributeValue -eq $null -or $attributeValue -eq "")
									{
										$msg = "INFO`t`t`tSkipping attribute regex test on field """ + $key + """ because the value is null."
										Write-Out $msg "white" 3
									}
								Else
									{
										$msg = "INFO`t`t`tRegex for attribute """ + $attribute + """ is """ + $regex + """."
										Write-Out $msg "white" 3
										
										If($attributeValue -eq $null -or $attributeValue -eq "")
											{$results = $false}
										$msg = "ACTION`t`t`tChecking attribute """ + $attribute + """ against it's regex value."
										Write-Out $msg "white" 4
										$msg = "ACTION`t`t`tMatching value """ + $attributeValue + """ to Regular Expression: """ + $regex + """."
										Write-Out $msg "white" 4
										$regexTestResults = Check-StringAgainstRegex $attributeValue $regex
										If($regexTestResults -eq $true)
											{}
										Else
											{
												$results = $false
												$warningMsg = "ERROR`tThe following attribute did not match the regex test: """ + $attribute + """."
												Throw-Warning $warningMsg
												$results = $false
											}
									}
							}
						Else
							{}
					}
				Else
					{}
			}
		Return $results
	}

Function Check-AttributesValid($hshUserInfo)
	{
		$failFunction = $false
		$results = $null
		$keys = $null
		
		#Test specific attributes
		$keys = $hshUserInfo.Keys
		Foreach($attribute in $keys)
			{
				If($results -ne $false)
					{
						If($attribute -eq $null)
							{$results = $false}
						Else
							{
								Switch($attribute)
									{
										"memberof"
											{
												$memberof = $null
												$memberof = $hshUserInfo.Get_Item($attribute)
												
												write-host -f cyan "memberof: $memberOf"
												
												#make sure we have multiple groups
												$blnMultipleGroups = $null
												If($memberOf -like "*,*")
													{$blnMultipleGroups = $true}
												Else
													{$blnMultipleGroups = $false}
												
												If($blnMultipleGroups -eq $false)
													{
														#write-host -f magenta "multiplegroups check failed"
														$results = $false
													}
												Else
													{
														#make sure we have a quota group and a role group
														$groupCNs = $null
														$groupCNs = @()
														$groupCNs = $memberof.Split(",")
														
														$blnMemberOfQuotaGroup = $null
														$blnMemberOfQuotaGroup = $false
														$blnMemberOfRoleGroup = $null
														$blnMemberOfRoleGroup = $false
														
														$quotaGroupsCN = Read-Variable "quotaGroupsCN"
														$objQuotaGroupsDN = Get-DNbyCN $quotaGroupsCN "group"
														$objQuotaGroups = [adsi]("LDAP://" + $objQuotaGroupsDN)
														$arrQuotaGroupDNs = $objQuotaGroups.member
														
														$WebOnlyGroupDN = $null
														$WebOnlyGroupDN = Get-DNbyCN (Read-Variable "WebOnlyGroupCN")
														
														Foreach($groupCN in $groupCNs)
															{
																write-host -f cyan "groupCN: $groupCN"
																$groupDN = Get-DNbyCN $groupCN "group"
																If($arrQuotaGroupDNs -contains $groupDN -or $groupDN -eq $WebOnlyGroupDN)
																	{$blnMemberOfQuotaGroup = $true}
																Else
																	{$blnMemberOfRoleGroup = $true}
															}
														
														If($blnMemberOfQuotaGroup -eq $true -and $blnMemberOfRoleGroup -eq $true)
															{$results = $true}
														Else
															{
																$msg = "Error`tMemberOf validation failed -- the user would not be a member of both a quota and role group."
																Throw-Warning $msg
																#write-host -f magenta "qouta and role check failed"
																$results = $false
															}
													}
											}
										"uidNumber"
											{
												If($keys -contains "gidNumber")
													{$results = $true}
												Else
													{$results = $false}
											}
										"gidNumber"
											{
												If($keys -contains "uidNumber")
													{$results = $true}
												Else
													{$results = $false}
											}
										Default
											{$results = $true}
									}
							}
						If($results -eq $false)
							{
								$warningMsg = "ERROR`tThe following attribute failed to check as valid: """ + $attribute + """."
								Throw-Warning $warningMsg
							}
					}
			}
		
		#Check bad attribute combinations
		$blnUnixAttributesPresent = $null
		$blnUnixAttributesPresent = $false
		$unixAttributes = $null
		$unixAttributes = @(`
			"loginShell",`
			"msSFU30NisDomain",`
			"unixHomeDirectory")
		Foreach($unixAttribute in $unixAttributes)
			{
				If($keys -contains $unixAttribute)
					{$blnUnixAttributesPresent = $true}
			}
		If($blnUnixAttributesPresent -eq $true)
			{
				If($keys -contains "uidNumber")
					{
						If($keys -contains "gidNumber")
							{}
						Else
							{
								$warningMsg = "ERROR`tSome unix attributes present, but no gidNumber present."
								Throw-Warning $warningMsg
								$results = $false
							}
					}
				Else
					{
						$warningMsg = "ERROR`tSome unix attributes present, but no uidNumber present."
						Throw-Warning $warningMsg
						$results = $false
					}
			}
		
		If($failFunction -eq $true)
			{Return $false}
		Else
			{Return $results}
	}

Function Precopy-User($hshUserInfo)
	{
		#bind to the user
		$sAMAccountName = $null
		$sAMAccountName = $hshUserInfo.Get_Item("sAMAccountName")
		$objUserDN = $null
		$objUserDN = Get-DNbySAMAccountName $sAMAccountName "user"
		$msg = "INFO`tBinding to the DN """ + $objUserDN + """."
		Write-Out $msg "white" 4
		$objUser = $null
		$objUser = [adsi]("LDAP://" + $objUserDN)
		
		$failthisuser = $null
		$failthisuser = $false
		
		$tasks = $null
		$tasks = @()
		$tasks += "enforce-homePermissions"
		$tasks += "groupmembership-quotagroup"
		$tasks += "precopy-userdata"
		
		#basic checks
		$msg = "ACTION`tPerforming basic home directory tests."
		Write-Out $msg "darkcyan" 4
		$homeDirectory = $null
		$homeDirectory = Pull-ldapAttribute $objUser "homeDirectory"
		If($homeDirectory -eq $null -or $false)
			{
				$warningMsg = "WARNING`tThis user has no home directory; failing user."
				Throw-Warning $warningMsg
				$failthisuser = $true
			}
		ElseIf((Test-Path $homeDirectory) -eq $false)
			{
				$warningMsg = "WARNING`tAttempts to access the home directory failed; failing user."
				Throw-Warning $warningMsg
				$failthisuser = $true
			}
		
		
		$task = $null
		Foreach($task in $tasks)
			{
				If($failthisuser -eq $true)
					{}
				Else
					{
						Switch($task)
							{
								"enforce-homePermissions"
									{
										$msg = "ACTION`t`Testing home directory permissions."
										Write-Out $msg "darkcyan" 4
										$homeTest = $null
										$homeTest = CheckAndFix-HomeDirectoryPermissions $objUser
										If($homeTest -eq $true)
											{
												$msg = "INFO`t`Home directory permissions verified."
												Write-Out $msg "darkcyan" 4
											}
										Else
											{
												$msg = "INFO`t`Home directory permissions test failed."
												Write-Out $msg "darkcyan" 4
												$msg = "ACTION`t`Fixing directory permissions."
												Write-Out $msg "darkcyan" 4
												$homeFix = $null
												$homeFix = CheckAndFix-HomeDirectoryPermissions $objUser
												If($homeFix -eq $true)
													{
														$msg = "INFO`t`Home directory permissions fixed."
														Write-Out $msg "darkcyan" 4
													}
												Else
													{
														$warningMsg = "ERROR`t`could not fix home directory permissions."
														Throw-Warning $warningMsg
														$failthisuser = $false
													}
											}
									}
								"groupmembership-quotagroup"
									{
										$msg = "ACTION`tChecking this user for quota group membership."
										Write-Out $msg "darkcyan" 4
										$results = $null
										$results = Check-GroupMembership-QuotaGroup $objUser
										If($results -eq $false)
											{
												$warningMsg = "ERROR`tUser is not a member of a quota group. Skipping user """ + $sAMAccountName + """."
												Throw-Warning $warningMsg
												$failthisuser = $true
											}
										Else
											{
												$msg = "INFO`tQuota group check successful."
												Write-Out $msg "darkcyan" 4
											}
									}
								"precopy-userdata"
									{
										$msg = "ACTION`tPremigrating user data."
										Write-Out $msg "darkcyan" 4
										$precopyd = $null
										$precopyd = precopy-Userdata $objUser
										If($precopyd -eq $false)
											{
												$warningMsg = "ERROR`tProblem premigrating user data."
												Throw-Warning $warningMsg
												$failthisuser = $true
											}
										Else
											{
												$msg = "ACTION`tUser precopyd successfully."
												Write-Out $msg "darkcyan" 4
											}
									}
							}
					}
			}
		
		$retval = $null
		If($failthisuser -eq $true)
			{$retval = $false}
		Else
			{$retval = $true}
		
		Return $retval
	}

Function precopy-Userdata($objUser)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		
		#common variables
		$sAMAccountName = Pull-ldapAttribute $objUser "sAMAccountName"
		
		$fileserver = Get-UserHomeFS $objUser
		$homeFS = $fileserver
		
		#build destination folder path
		$msg = "ACTION`tBuilding home folder destination path."
		Write-Out $msg "darkcyan" 4
		$strDestinationPath = $null
		$strDestinationPath = Build-HomeFolderDestinationPath $objUser
		$blnDestinationPathBuilt = $null
		If($strDestinationPath -eq "" -or $strDestinationPath -eq $null -or $strDestinationPath -eq $false)
			{$blnDestinationPathBuilt = $false}
		Else
			{$blnDestinationPathBuilt = $true}
		
		If($blnDestinationPathBuilt -eq $true)
			{
				$msg = "INFO`tHome folder destination path built as """ + $strDestinationPath + """."
				Write-Out $msg "darkcyan" 4
			}
		Else
			{
				$warningMsg = "ERROR`tCould not build a destination path."
				Throw-Warning $warningMsg
				$failThisFunction = $true
			}
		
		#check destination against relative source path
		$shareName = $null
		$shareName = $sAMAccountName + "$"
		$relativeSharePath = $null
		$relativeSharePath = Get-SharePathAsAdminUNC $shareName $homeFS
		$msg = "INFO`t`tHome share relative path is """ + $relativeSharePath + """."
		Write-Out $msg "darkcyan" 4
		If($relativeSharePath -eq $strDestinationPath)
			{
				$msg = "INFO`t`tUser already migrated!"
				Write-Out $msg "darkcyan" 4
			}
		Else
			{
				#create the destination folder
				$msg = "ACTION`tCreating the destination folder."
				Write-Out $msg "darkcyan" 4
				If($failThisFunction -eq $false)
					{
						$blnFolderCreated = $null
						$blnFolderCreated = Create-Folder $strDestinationPath
						If($blnFolderCreated -eq $true)
							{
								$msg = "INFO`tDestination folder created."
								Write-Out $msg "darkcyan" 4
							}
						Else
							{
								$warningMsg = "ERROR`tCould not create the destination folder."
								Throw-Warning $warningMsg
								$failThisFunction = $true
							}
					}
				
				#get the source data
				$source = "\\" + $fileserver + "\" + $sAMAccountName + "$"
				
				#copy the data
				If($failThisFunction -eq $false)
					{
						$destination = $null
						$destination = $strDestinationPath
						$msg = "ACTION`t`tCopying the data from source to destination """ + $destination + """."
						Write-Out $msg "darkcyan" 4
						$switches = $null
						#/XO means 'eXclude Older'.
						#If a file exists in both the source and destination, /XO makes sure that robocopy leaves whichever file is newer.
						$switches = "/XO"
						$blnFolderCopied = $null
						$blnFolderCopied = Robocopy-Folder $source $destination $switches
						$blnFolderCopied = $true
						If($blnFolderCopied -eq $true)
							{
								$msg = "ACTION`t`tData transfer complete."
								Write-Out $msg "darkcyan" 4
							}
						Else
							{
								$warningMsg = "ERROR`t`tData transfer reports errors."
								Throw-Warning $warningMsg
								$failThisfunction = $true
							}
					}
				
				#Verify the folder copy
				If($failThisFunction -eq $false)
					{
						$msg = "ACTION`t`tVerifying the data transfer."
						Write-Out $msg "darkcyan" 4
						$blnCopyVerified = $null
						$blnCopyVerified = Verify-FolderCopy $source $destination
						If($blnCopyVerified -eq $true)
							{
								$msg = "ACTION`t`tData transfer verified."
								Write-Out $msg "darkcyan" 4
							}
						Else
							{
								$warningMsg = "ERROR`t`tFailed to verify data transfer."
								Throw-Warning $warningMsg
								$failThisfunction = $true
							}
					}
			}
		
		$retval = $null
		If($failThisFunction -eq $true)
			{$retval = $false}
		Else
			{$retval = $true}
		Return $retval
	}

Function Process-User($hshUserInfo) #ECC
	{
		$results = $null
		$failFunction = $false
		#Run create-user
		
		$blnReadOnly = $null
		$blnReadOnly = $false
		$blnReadOnly = Read-Variable "ReadOnly"
		
		$msg = "ACTION`tChecking if the user """ + $sAMAccountName + """ exists."
		Write-Out $msg "white" 2
		
		$usercheck = Check-DoesUserExist $sAMAccountName
		If($userCheck -eq $false)
			{
				$msg = "INFO`t`tUser """ + $sAMAccountName + """ does not exist."
				Write-Out $msg "white" 3
				$msg = "ACTION`tValidating user info for account creation."
				Write-Out $msg "white" 2
				
				$msg = "ACTION`tCreating user """ + $sAMAccountName + """."
				Write-Out $msg "white" 2
				
				$userCreated = $false
				$userCreated = Create-User $hshUserInfo
				If($userCreated -eq $false)
					{
						$failFunction = $true
						$warningMsg = "ERROR`tFailed to create user """+ $sAMAccountName + """."
						Throw-Warning $warningMsg
					}
				#	}
			}
		Else
			{
				$msg = "INFO`tUser """ + $sAMAccountName + """ already exists."
				Write-Out $msg "white" 3
			}
		
		#If all's well, then process the user.
		If($failfunction -ne $true)
			{
				#### if hash table keys contains password, then run Run-CreationTask-setPassword($hshUserInfo)
				##### make sure to write statements to the console and log and document \ test this change!!! OMG
				
				############################
				#
				#
				#  stupid hacks I will regret later
				#
				#
				############################
				
				#PASSWORDS
				$keys = $hshUserInfo.Keys
				If($keys -contains "password")
					{
						$msg = "Info`tPassword attribute found in file. Resetting password!"
						Write-Out $msg "magenta" 2
						$strPassword = $null
						$strPassword = $hshUserInfo.Get_Item("password")
						
						#write-host -f yellow "strPassword: $strPassword"
						
						If($strPassword -eq $null -or $strPassword -eq "")
							{
								$msg = "ERROR`tThe password key was blank! Skipping the set-password."
								Throw-Warning $msg
							}
						Else
							{
								$results = $null
								$results = Run-CreationTask-SetPassword $hshUserInfo
							}
					}
				
				#Bind to user
				$sAMAccountName = $hshUserInfo.Get_Item("sAMAccountName")
				$objUserDN = Get-DNbySAMAccountName $sAMAccountName "user"
				$msg = "INFO`tBinding to the DN """ + $objUserDN + """."
				Write-Out $msg "white" 4
				$objUser = [adsi]("LDAP://" + $objUserDN)
				
				##MSS GROUP
				$MSSGroup = $null
				$MSSGroupCN = Read-Variable "MSSGroupCN"
				$MSSGroupDN = $null
				If($MSSGroupCN -eq $null -or $MSSGroupCN -eq $false)
					{}
				Else
					{
						$MSSGroupDN = Get-DNbyCN $MSSGroupCN "group"
						If($MSSGroupDN -eq $null -or $MSSGroupDN -eq $false)
							{}
						Else
							{
								$blnGroupCheck = $null
								$blnGroupCheck = $false
								$blnGroupCheck = Check-IsMemberOfGroup $objUserDN $MSSGroupDN
								If($blnGroupCheck -eq $true)
									{
										###MOVE DEM
										$MSS2010OU = Read-Variable "MSS2010OU"
										$msg = "Info`t`tFound the MSS conference group."
										Write-Out $msg "white" 4
										
										If($objUserDN -like ("*" + $SMS2010OU + "*"))
											{}
										Else
											{
												$msg = "Action`t`tMoving user to the conference group OU."
												Write-Out $msg "white" 4
												$blnMoved = $null
												$blnMoved = Move-UserToOU $objUser $MSS2010OU
												$objUserDN = $null
												$objUserDN = Get-DNbySAMAccountName $sAMAccountName "user"
												$msg = "INFO`tRe-binding to the DN """ + $objUserDN + """."
												Write-Out $msg "white" 4
												$objUser = $null
												$objUser = [adsi]("LDAP://" + $objUserDN)
											}
										
										###Set account expires
										$mssExpirationDate = Read-Variable "MSSExpirationDate"
										$msg = "Action`tEnforcing expiration date of """ + $mssExpirationDate + """."
										Write-Out $msg "white" 4
										$expectedExpirationDate = $null
										$expectedExpirationDate = $mssExpirationDate
										$results = Set-AccountExpirationDate $objUser $expectedExpirationDate
									}
							}
					}
				
				#CONFERENCE ATTENDEES
				$conferenceGroup = $null
				$conferenceGroup = Read-Variable "ConferenceAttendeeGroupCN"
				If($conferenceGroup -eq $null -or $conferenceGroup -eq $false)
					{}
				Else
					{
						$conferenceGroupDN = $null
						$conferenceGroupDN = Get-DNbyCN $conferenceGroup "group"
						If($conferenceGroupDN -eq $null -or $conferenceGroupDN -eq $false)
							{}
						Else
							{
								$blnGroupCheck = $null
								$blnGroupCheck = $false
								$blnGroupCheck = Check-IsMemberOfGroup $objUserDN $conferenceGroupDN
								If($blnGroupCheck -eq $true)
									{
										##do not change password on first login
										$msg = "Info`t`tFound the """ + $conferenceGroup + """ group."
										Write-Out $msg "white" 4
										$msg = "Action`t`tUnchecking ""user must change password on first login""."
										Write-Out $msg "white" 4
										
										$blnAction = $null
										$blnAction = Set-QADUser $sAMAccountName -usermustchangepassword $false
										$blnAction = $null
									}
							}
					}
		
				#Check against data
				$checkAgainstData = Check-AccountAgainstGivenData $objUser $hshUserInfo
				If($checkAgainstData -eq $false)
					{$failFunction = $true}
				
				If($failFunction -eq $false)
					{
						#Process this user
						$msg = "ACTION`tBeginning account tests."
						Write-Out $msg "cyan" 2
						$testResults = $null
						$testResults = Test-Account $objUser
						If($testResults -eq $false)
							{
								$warningMsg = "ERROR`t`tProblem testing the account."
								Throw-Warning $warningMSg
								$failFunction = $true
							}
						ElseIf($testResults -ne $true)
							{
								If($blnReadOnly -eq $false)
									{
										$firstFailedTest = $testResults
										$msg = "ACTION`tBeginning account fixes."
										Write-Out $msg "cyan" 2
										$fixed = Fix-Account $objUser $firstFailedTest
										If($fixed -eq $true)
											{}
										Else
											{
												$failFunction = $true
												$warningMsg = "WARNING`tFailed to process the user account."
												Throw-Warning $warningMsg
											}
									}
								Else
									{
										$warningMsg = "WARNING`tSkipping account fixes because read-only mode was invoked by /eval."
										Throw-WArning $warningMsg
										$failFunction = $true
									}
							}
					}
			}
		Else
			{}
		
		If($failFunction -eq $true)
			{$results = $false}
		Else
			{$results = $true}
			
		#write-host -f yellow "DEBUG`t(F)Process-User`tresults: $results"
		#$results | gm | out-host
		Return $results
	}

Function Check-AccountAgainstGivenData($objUser,$hshUserInfo)
	{
		$failThisfunction = $null
		$failThisfunction = $false
		#group memberships
		#Run-CreationTask-AddToGroups $hshUserInfo
		
		#buckID
		$msg = "ACTION`tChecking that the user's employeeID matches the read employeeID"
		Write-Out $msg "white" 2
		$keys = $hshUserInfo.Keys
		#$hshUserInfo | out-host
		#$keys | out-host
		If($keys -contains "employeeid")
			{
				$objUserEmployeeID = Pull-ldapAttribute $objUser "employeeID"
				$userInfoEmployeeID = $hshUserInfo.Get_Item("employeeID")
				$msg = "INFO`t`tAD employeeID: """ + $objUserEmployeeID + """."
				Write-Out $msg "darkcyan" 4
				$msg = "INFO`t`tfile employeeID: """ + $userInfoEmployeeID + """."
				Write-Out $msg "darkcyan" 4
				
				If($objUserEmployeeID -eq $null`
					-or $objUserEmployeeID -eq $false`
					-or $objUserEmployeeID -ne $userInfoEmployeeID`
					)
					{
						$msg = "ACTION`tOverwriting user's current employeeID with the read value of: """ + $userInfoEmployeeID + """."
						Write-Out $msg "darkcyan" 4
						$objUser.Put("employeeID",$userInfoEmployeeID)
						$objUser.SetInfo()
					}	
			}
		
		#group memberships
		#do we have memberof in hshUserInfo?
		$arrHashKeys = $null
		$arrHashKeys = $hshUserInfo.Keys
		If($arrHashKeys -contains "memberof")
			{
				$msg = "ACTION`tChecking that the user is a member of the given groups."
				Write-Out $msg "white" 2
				
				$arrHshMemberOf = $null
				$arrHshMemberOf = Parse-MemberOfHashToArray $hshUserInfo
				$arrADMemberOf = $null
				$arrADMemberOf = Pull-ldapAttribute $objUser "memberof"
				$objUserDN = $null
				$objUserDN = Pull-ldapAttribute $objUser "distinguishedName"
				$strGivenCN = $null
				Foreach($strGivenCN in $arrHshMemberOf)
					{
						$msg = "ACTION`t`tTesting for group membership in the group """ + $strGivenCN + """."
						Write-Out $msg "darkcyan" 4
						$groupDN = $null
						$groupDN = Get-DNbyCN $strGivenCN "group"
						$groupCN = $null
						$groupCN = $strGivenCN
						$blnGroupExists = $null
						$blnGroupExists = $false
						
						#does the group exist?
						$blnGroupExists = Check-DNexists $groupDN
						If($blnGroupExists -eq $false)
							{
								#if it's classes, create it.
								If($groupCN -like "*classes*" -or $groupDN -like "*student teaching assistants*")
									{
										$blnGroupCreated = $null
										$blnGroupCreated = Create-ClassGroup $strGivenCN
										$i = 0
										Do
											{
												$groupDN = $null
												$groupDN = Get-DNbyCN $strGivenCN "group"
												If($groupDN -eq $false)
													{Sleep -s 1}
												Else
													{$i = 10}
												$i++
											}
										Until($i -gt 5)
										If($blnGroupCreated -eq $true)
											{
												$msg = "INFO`t`tCreated missing class group: """ + $groupCN + """."
												Write-Out $msg "white" 2
											}
										Else
											{
												$warningMsg = "ERROR`t`tCould not create the class group!"
												Throw-Warning $warningMsg
												$failThisfunction = $true
											}
									}
								Else
									{
										$warningMsg = "ERROR`t`tThe group """ + $strGivenCN + """ doesn't exist in AD."
										Throw-Warning $warningMsg
										$warningMsg = "ERROR`t`tThe script is unwilling to create a group whose name`n`t`t`tisn't like ""*classes*"" or ""*student teaching assistants*""."
										Throw-Warning $warningMsg
										$failThisfunction = $true
									}
							}
						Else
							{
								$groupCheck = $null
								$groupCheck = Check-IsMemberOfGroup $objUserDN $groupDN
								If(($groupCheck -eq $false -or $groupCheck -eq $null) -and $failThisfunction -eq $false)
									{
										#add user to group
										$msg = "ACTION`t`tAdding user to group """ + $strGivenCN + """."
										Write-Out $msg "white" 2
										$objUserDN = Pull-LDAPAttribute $objUser "distinguishedName"
										$groupDN = Get-DNbyCN $strGivenCN
										$userAdded = Add-ToGroup $objUserDN $groupDN
										
										Do
											{
												$groupCheck = $null
												$groupCheck = Check-IsMemberOfGroup $objUserDN $groupDN
												If($groupCheck -eq $false -or $groupCheck -eq $null)
													{Sleep -s 1}
												Else
													{$i = 10}
												$i++
											}
										Until($i -gt 5)
										$groupCheck = $null
										$groupCheck = Check-IsMemberOfGroup $objUserDN $groupDN
										If($groupCheck -eq $false -or $groupCheck -eq $null)
											{
												$warningMsg = "ERROR`t`tCould not add user to group."
												Throw-Warning $warningMsg
												$failThisfunction = $true
											}
									}
							}
					}
				
			}
		
		#accountExpires
		$blnNoChange = $null
		$blnNoChange = $false
		$arrHashKeys = $null
		$arrHashKeys = $hshUserInfo.Keys
		If($arrHashKeys -contains "accountExpires")
			{
				$msg = "ACTION`tChecking the user's accountExpires attribute."
				Write-Out $msg "white" 2
				$hshAccountExpires = $hshUserInfo.Get_Item("accountExpires")
				$msg = "Info`t`tHash table's expiration date: """ + $hshAccountExpires + """."
				Write-Out $msg "darkcyan" 4
				
				#If the hash's proposed date is blank
				If($hshAccountExpires -eq $null -or $hshAccountExpires -eq "never" -or $hshAccountExpires -eq "none" -or $hshAccountExpires -eq "")
					{
						$blnNoChange = $true
						$msg = "Info`t`tThe hash table for this user doesn't contain a date entry. Canceling check."
						Write-Out $msg "white" 2
					}
				Else
					{
						$usrAccountExpires = Find-ExpirationDate $objUser
						$msg = "Info`t`tUser's current expiration date: """ + $usrAccountExpires + """."
						Write-Out $msg "darkcyan" 4
						If($usrAccountExpires -eq $null -or $usrAccountExpires -eq "never" -or $usrAccountExpires -eq "none" -or $usrAccountExpires -eq "")
							{
								$msg = "Info`t`tThe user does not currently have an expiration date."
								Write-Out $msg "white" 2
								$msg = "Info`t`tThe script is unwilling to update the expiration date from the file`n`t`tunless the user already has an expiration date set."
								Write-Out $msg "white" 2
								$blnNoChange = $true
							}
						Else
							{
								$usrDate = Get-Date $usrAccountExpires
								#compensate for a date difference caused by differences in interpretation of 11:59 vs 12:00, etc.
								$usrDate = $usrDate.AddDays(1)
								$hshDate = Get-Date $hshAccountExpires
								If($usrDate -lt $hshDate)
									{
										$msg = "Action`tUpdating the user's account creation date to the hash's date: """ + $hshAccountExpires + """."
										Write-Out $msg "magenta" 2
										$action = $null
										$action = Set-AccountExpirationDate $objUser $hshDate
									}
								Else
									{
										$msg = "Info`t`tThe user's current expiration date is equal to or farther out than the hash table's expiration date."
										Write-Out $msg "darkcyan" 4
										$msg = "Info`t`tSkipping the accountExpires update just to be safe."
										Write-Out $msg "darkcyan" 4
										$action = $null
										$action = Set-AccountExpirationDate $objUser $hshDate
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



Function Create-User($hshUserInfo) #ECC
	{
		$failthisuser = $false
		
		#important -- always addToGroups last. It's the most likely to fail, and if you don't set
		#the password first the account won't be able to work until you delete and recreate it or
		#manually set a password.
		$creationTasks = @(`
			"createUser",`
			"writeLDAPattributes",`
			"addToGroups",`
			"setPassword"`
			)
		
		Foreach($creationTask in $creationTasks)
			{
				If($failThisUser -ne $true)
					{
						$msg = "ACTION`tRunning the following creation task: """
						Write-Out $msg "white" 2 "-nonewline"
						$msg = $creationTask
						Write-Out $msg "cyan" 2 "-nonewline"
						$msg = """."
						Write-Out $msg "white" 2
						$taskResults = $null
						$taskResults = Run-AccountCreationTask $creationTask $hshUserInfo
						If($taskResults -eq $false)
							{
								$warningMsg = "ERROR`tFailed account creation task """ + $creationTask + """."
								Throw-Warning $warningMsg
								$failthisuser = $true
								Break
							}
						Else
							{}
					}
			}
		
		If($failthisuser -eq $true)
			{return $false}
		Else
			{return $true}
	}

Function Run-AccountCreationTask($task, $hshUserInfo)
	{
		$failFunction = $false
		$results = $true
		Switch($task)
			{
				"createUser"
					{$results = Run-CreationTask-CreateUser $hshUserInfo}
				"writeLDAPattributes"
					{$results = Run-CreationTask-writeLDAPattributes $hshUserInfo}
				"addToGroups"
					{$results = Run-CreationTask-addToGroups $hshUserInfo}
				"setPassword"
					{$results = Run-CreationTask-setPassword $hshUserInfo}
				"setAccountExpires"
					{$results = Run-CreationTask-setAccountsExpires $hshUserInfo}
				Default
					{
						$warningMsg = "ERROR`tRun-AccountCreationTask does not have an entry for task: """ + $task + """."
						Throw-Warning $warningMsg
						$failFunction = $true
					}
			}
		
		If($failFunction -eq $true)
			{Return $false}
		Else
			{Return $results}
				
	}
	
Function Run-CreationTask-CreateUser($hshUserInfo)
	{
		$results = $true
		$failFunction = $false
		$displayName = $hshUserInfo.Get_Item("displayName")
		$sAMAccountName = $hshUserInfo.Get_Item("sAMAccountName")
		#Find the OU we're creating into
		###class OU?
		$blnClassOnlyAccount = $null
		$blnClassOnlyAccount = Check-WillAccountBeClassOnly $hshUserInfo
		
		$strOUType = $null
		If($blnClassOnlyAccount -eq $true)
			{$strOUType = "roaming-classes"}
		Else
			{$strOUType = "roaming"}
		$destinationOU = Pick-OU $strOUType $displayName
		
		If($destinationOU -eq $false)
			{
				$failFunction = $true
				$warningMsg = "ERROR`tCould not find a suitable destination OU for displayName: """ + $displayName + """."
				Throw-Warning $warningMsg
			}
		Else
			{
				#Actually create the user
				$objUserDN = "CN=" + $displayName + "," + $destinationOU
				$msg = "ACTION`tCreating user as: CN=" + $displayName + "," + $destinationOU
				Write-Out $msg "white" 2
				$objOU = [adsi]("LDAP://" + $destinationOU)
				$objUser = $objOU.Create("user","cn=$displayName")
				
				#write the sAMAccountName
				$sAMAccountName = $hshUserInfo.Get_Item("sAMAccountName")
				$objUser.Put("sAMAccountName",$sAMAccountName)
				$objUser.Put("userAccountControl",514)
				$objUser.SetInfo()
			}
		
		$objUserDN = $null
		$objUserDN = "CN=" + $displayName + "," + $destinationOU
		
		#Does the user exist now?
		$blnUserExists = Check-DoesUserExist $sAMAccountName
		If($blnUserExists -eq $false)
			{$results = $false}
		Else
			{$results = $true}
		
		Return $results
	}

Function Check-WillAccountBeClassOnly($hshUserInfo)
	{
		$results = $null
		$results = $false
		
		#checks to see if the only groups are *classes*, *ACL*, or *RES*
		$groupCNs = $null
		$groupCNs = Parse-MemberOfHashToArray $hshUserInfo
		If($groupCNs -eq $null -or $groupCNs -eq $false)
			{$results = $false}
		Else
			{
				$classAccountsGroupCN = Read-Variable "classAccountsQuotaGroupCN"
				If($groupCNs -contains $classAccountsGroupCN)
					{
						$results = $true
						Foreach($group in $groupCNs)
							{
								If(`
											$group -like "*classes*" `
									-or $group -like "ACL_*" `
									-or $group -like "RES_*"`
									-or $group -like ("*" + $classAccountsGroupCN + "*")
									)
									{}
								Else
									{$results = $false}
							}
					}
				Else
					{$results = $false}
			}
		Return $results
	}

Function Run-CreationTask-writeLDAPattributes($hshUserInfo)
	{
		Write-Host -f yellow "HSHUSERINFO-------------------"
		$hshUserInfo | out-host
		#Write all LDAP attributes ($hshUserinfo -> $objUser)
		$msg = "ACTION`tWriting LDAP Attributes: "
		Write-Out $msg "white" 2
		
		$sAMAccountName = $hshUserInfo.Get_Item("sAMAccountName")
		$objUserDN = Get-DNbySAMAccountName $sAMAccountName "user"
		$objUser = [adsi]("LDAP://" + $objUserDN)
		
		###FOR CONFERENCE ACCNTS
		#write-host -f yellow "removing check box: user must change password"
		#Set-QADUser $sAMAccountName -UserMustChangePassword $false
		###oops! only works if accnt is enabled?
		
		$unchangableAttributes = Read-Variable "unchangableAttributes"
		
		$keys = $hshUserInfo.Keys
		foreach($attributeName in $keys)
			{
				$attributeName = $attributeName.ToLower()
				If($attributeName -eq "accountexpires")
					{
						$msg = "Action`t`tWriting accountExpires: """ + $hshUserInfo.$attributeName + """ ."
						Write-Out $msg "darkcyan" 4
						$attributeValue = $hshUserInfo.Get_Item($attributeName)
						$date = Get-Date $attributeValue
						$results = Set-AccountExpirationDate $objUser $date
					}
				ElseIf($attributeName -eq "password")
					{}
				ElseIf($attributeName -eq "proxyAddresses")
					{
						$arrProxyAddr = $hshUserInfo.Get_Item($attributeName)
						$msg = "Action`t`t`tWriting ProxyAddresses."
						Write-Out $msg "darkcyan" 4
						$objUser.Put("proxyAddresses",$arrProxyAddr)
					}
				ElseIf(($unchangableAttributes -contains $attributeName) -eq $false)
					{
						[string]$attributeValue = $hshUserInfo.Get_Item($attributeName)
						$msg =  "INFO`t`tWriting attribute: " + $attributeName + "`t`tValue: " + $attributeValue
						write-out $msg "darkcyan" 4
						$objUser.Put($attributeName,$attributeValue)
					}
			}
		$objUser.SetInfo()
		$objUser = $null
		
		Return $true
	}

Function Run-CreationTask-addToGroups($hshUserInfo)
	{
		$failFunction = $false
		$results = $true
		$groupsToAdd = $null
		$groupsValidated = $null
		
		$msg = "ACTION`tAdding user to initial groups."
		Write-Out $msg "white" 2
		$groupCNsToAdd = Parse-MemberOfHashToArray $hshUserInfo
		If($groupCNsToAdd -eq $null -or $groupCNsToAdd -eq $false)
			{
				$msg = "INFO`tDone; No initial groups were specified."
				Write-Out $msg "darkcyan" 4
				$results = $true
			}
		Else
			{
				If(($groupCNsToAdd -is [array]) -eq $false)
					{
						$arrGroupCNs = @()
						$arrGroupCNs += $groupCNsToAdd
						$groupCNsToAdd = $arrGroupCNs
					}
				
				#sanitize group CNs
#				$processedGroupCNs = @()
#				Foreach($groupCN in $groupCNsToAdd)
#					{
#						$newGroupCN = Sanitize-GroupCN $groupCN
#						write-host -f yellow $newGroupCN
#						If($newGroupCN -ne $false)
#							{$processedGroupCNs += $newGroupCN}
#					}
				
				#create any missing class groups
				Foreach($groupCN in $groupCNsToAdd)
					{
						$groupDN = Get-DNbyCN $groupCN "group"
						If($groupDN -eq $false)
							{
								If($groupCN -like "*classes*")
									{
										$blnGroupCreated = $null
										$blnGroupCreated = Create-ClassGroup $groupCN
										If($blnGroupCreated -eq $true)
											{
												$msg = "INFO`t`tCreated missing group: """ + $groupCN + """."
												Write-Out $msg "white" 2
											}
										Else
											{
												$warningMsg = "ERROR`tCould not create missing class group: """ + $groupCN + """."
												Throw-Warning $warningMsg
												$failFunction = $true
											}
									}
								Else
									{
										$warningMsg = "ERROR`tUnwilling to create missing group: """ + $groupCN + """."
										Throw-Warning $warningMsg
										$failFunction = $true
									}
							}
						Else
							{}	
					}
				
				#Validate Groups and Change Membership
				If($failFunction -eq $false)
					{
						$blnGroupsValidated = $null
						$blnGroupsValidated = Validate-MemberOfGroups $groupCNsToAdd
						If($blnGroupsValidated -eq $true)
							{
								Foreach($groupCN in $groupCNsToAdd)
									{
										$msg = "ACTION`t`tAdding user to group: """ + $groupCN + """."
										Write-Out $msg "darkcyan" 4
										$sAMAccountName = $hshUserInfo.Get_Item("sAMAccountName")
										$userDN = Get-DNbySAMAccountName $sAMAccountName "user"
										$objUser = [ADSI]("LDAP://" + $objUserDN)
										$groupDN = Get-DNbyCN $groupCN
										Add-ToGroup $userDN $groupDN
										$objGroupDN = Get-DNbyCN $groupCN "group"
										$blnGroupCheck = Check-IsMemberOfGroup $userDN $objGroupDN
										If($blnGroupCheck -eq $false)
											{
												$warningMsg = "ERROR`tFailed to add user to the group: """ + $groupCN + """."
												Throw-Warning $warningMsg
												$failFunction = $true
												$results = $false
											}
									}
							}
						Else
							{
								$failFunction = $true
								$sAMAccountName = $hshUserInfo.Get_Item("sAMAccountNAme")
								$warningMsg = "ERROR`tCould not validate groups for this user."
								Throw-Warning $warningMsg
								$warningMsg = "ERROR`tFailed to add this user ( """ + $sAMAccountName + """ ) to their inital groups."
								Throw-Warning $warningMsg
							}
					}
			}
		
		If($failFunction -eq $true)
			{Return $false}
		Else
			{Return $results}
	}

Function Run-CreationTask-setPassword($hshUserInfo) ## WARNING - NOECC
	{
		#Generate password
		$error.clear()
		
		#configure the trap
		trap
			{
				#log the error
				$warningMsg = "ERROR`tPowerShell threw an exception. More info should follow this line."
				Throw-Warning $warningMsg
				Foreach($errorLine in $error)
					{
						$warningMsg = $errorLine
						Throw-Warning $warningMsg
					}
				continue;
			}
		
		$sAMAccountName = $hshUserInfo.Get_Item("sAMAccountName")
		$objUserDN = Get-DNbySAMAccountName $sAMAccountName "user"
		$objUser = [adsi]("LDAP://" + $objUserDN)
		
		#Generate the password
		####grab keys -- if keys contains password then take it from the hash table, don't generate
		$keys = $hshUserInfo.Keys
		If($keys -eq "password")
			{
				$password = $hshUserInfo.Get_Item("password")
			}
		Else
			{
				$givenName = Pull-LDAPAttribute $objUser "givenName"
				$sn = Pull-LDAPAttribute $objUser "sn"
				$employeeID = Pull-LDAPAttribute $objUser "employeeID"
				
				If(`
					$givenName -eq $null -or `
					$sn -eq $null -or `
					$employeeID -eq $null `
					)
					{$failfunction = $true}
				
				$givenName = $givenName.Substring(0,1)
				$givenName = $givenName.ToUpper()
				$sn = $sn.Substring(0,1)
				$sn = $sn.ToLower()
				$employeeIDLength = $employeeID.Length
				$employeeIDStart = $employeeIDLength - 6
				$employeeID = $employeeID.substring($employeeIDStart, 6)
				$password = $givenName + $employeeID + $sn
			}
		$msg = "INFO`tPassword generated as: """ + $password + """."
		Write-Out $msg "white" 2
		
		#Set the password
		$objUser.SetPassword($password)
		$objUser.SetInfo()
		$objUser.pwdLastSet = 0
		$objUser.SetInfo()
		$objUser = $null
		
		Return $true
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

Function Test-Account($objUser)
	{
		$failFunction = $false
		$results = $null
		#Build Test Groups
		$msg = "ACTION`tBuilding the test groups."
		Write-Out $msg "white" 2
		$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
		$objUserDN = Get-DNbySAMAccountName $sAMAccountName "user"
		$TestGroups = Build-TestGroups $objUserDN
		#Test the test groups
		If($testGroups -eq $false)
			{$failFunction = $true}
		Else
			{$results = Run-TestGroups $testGroups $objUser}
		
		If($failFunction -eq $true)
			{Return $false}
		Else
			{Return $results}
	}

Function Run-TestGroups($testGroups,$objUser)
	{
		$failFunction = $false
		$results = $true
		Foreach($testGroup in $testGroups)
			{
				If($results -eq $true -and $failFunction -ne $true)
					{
						$msg = "ACTION`tRunning test group:`t""" + $testGroup + """."
						Write-Out $msg "white" 2
						$testSet = Build-TestSet $testGroup $objUser
						#get time
						$startTime = $null
						$startTime = Get-Date
						$results = Run-TestSet $testSet $objUser
						If($results -ne $true)
							{
								$msg = "INFO`tTest group returned failed test: """
								Write-Out $msg "white" 3 "-nonewline"
								$msg = $results
								Write-Out $msg "magenta" 3 "-nonewline"
								$msg = """."
								Write-Out $msg "white" 3
							}
						Else
							{
								$msg = "INFO`tTest group passed."
								Write-Out $msg "white" 3
							}
						$completionTime = $null
						$completionTime = (get-date) - $startTime
						$secondsToComplete = $null
						$secondsToComplete = $completionTime.Duration().TotalSeconds
						$secondsToComplete = [Math]::Round($secondsToComplete,1)
						$msg = "INFO`tTest group took " + $secondsToComplete + " seconds to complete."
						Write-Out $msg "white" 4
					}
			}
		If($failFunction -eq $true)
			{Return $false}
		Else
			{Return $results}
	}

Function Run-TestSet($testSet,$objUser)
	{
		$sAMAccountName = $null
		$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
		
		$results = $true
		$failFunction = $false
		$testResults = $null
		
		Foreach($test in $testSet)
			{
				If($testResults -ne $false -and $failFunction -ne $true)
					{
						#rebind to user in case OU changed or something
						$objUserDN = $null
						$objUserDN = Get-DNbySAMAccountName $sAMAccountName "user"
						$objUser = $null
						$objUser = [adsi]("LDAP://" + $objUserDN)
						
						$startTime = $null
						$startTime = get-date
						If($script:arrTestsToSkip -contains $test)
							{
								$msg = "ACTION`t`tSkipping test " + $test + "."
								Write-Out $msg "darkcyan" 4
								$testResults = $true
							}
						Else
							{
								$error.clear()
								#[GC]::Collect()
								$script:arrTestsToSkip += $test
								$testResults = $null
								$msg = "ACTION`t`tRunning test:`t"""
								Write-Out $msg "white" 2 "-nonewline"
								$msg = $test 
								Write-Out $msg "cyan" 2 "-nonewline"
								$msg = """"
								Write-Out $msg "white" 2 
								$testResults = Run-AccountTest $test $objUser
								
								#report on the test
										$complTime = $null
								$complTime = (get-date) - $startTime
								$complMseconds = $complTime.duration().totalmilliseconds
								$complMseconds = [Math]::Round($complMseconds,0)
								$msg = "Info`t`tTest took " + $complMseconds + " totalmilliseconds to complete."
								Write-Out $msg "darkcyan" 4
								If($testResults -eq $true)
									{
										$msg = "INFO`t`tTest Results:`t"
										Write-Out $msg "white" 3 "-nonewline"
										$msg = $testResults
										Write-Out $msg "green" 3 
									}
								ElseIf($testResults -eq $false)
									{
										$msg = "INFO`t`tTest Results:`t"
										Write-Out $msg "white" 3 "-nonewline"
										$msg = $testResults
										Write-Out $msg "magenta" 3
										$results = $test
									}
								Else
									{
										$warningMsg = "ERROR`tUnexpected result from Run-AccountTest: """ + $testResults + """."
										Throw-Warning $warningMsg
										$failFunction = $true
										Break
									}
							}
					}
			}
		If($failFunction -eq $true)
			{return $false}
		Else
			{return $results}
	}

Function Build-TestGroups($objUserDN)
	{
		$failFunction = $null
		$failFunction = $false
		$DNcheckResults = $null
		$DNcheckResults = Check-DNexists $objUserDN
		If($DNcheckResults -eq $true)
			{
				$testGroups = @()
				
				#Add standard account tests
				$testGroups += "basicAccountHealth"
				$testGroups += "homedriveAccessibility"
				$testGroups += "homedriveConformity"
				$testGroups += "ldapAttributes"
				$testGroups += "groupMemberships"
				
				#Is this a user with an RDP profile?
				$blnRDPUser = $null
				$blnRDPUser = $false
				$arrRDPGroups = Read-Variable "RDPGroups"
				$arrRDPGroups | % {
					$grpDN = $null
					$grpDN = Get-DNbyCN $_
					$grpTest = $null
					$grpTest = $false
					$grpTest = Check-IsMemberOfGroup $objUserDN $grpDN
					If($grpTest -eq $true)
						{$blnRDPUser = $true}
				}
				If($blnRDPUser -eq $true)
					{$testGroups += "rdpProfile"}
				
				#Is user a roaming user?
				If($objUserDN -like "*roaming*")
					{
						$testGroups +=	"profileAccessibility"
						$testGroups +=	"profileConformity"
					}
				
				#is this a user with unix attributes?
				$blnUnixAttribute = $null
				$blnUnixAttribute = $false
				$objUser = $null
				$objUser = [adsi]("LDAP://" + $objUserDN)
				$UIDNumber = $null
				$UIDNumber = Pull-LDAPAttribute $objUser "uidNumber"\
				If($UIDNumber -eq $null -or $UIDNumber -eq $false)
					{$blnUnixAttribute = $false}
				Else
					{$blnUnixAttribute = $true}
				$objUser = $null
				$UIDNumber = $null
				If($blnUnixAttribute -eq $true)
					{$testGroups +=	"unixAttributes"}
			}
		Else
			{
				$failFunction = $true
				$warningMsg = "ERROR`t`tBuild-TestGroups failed because it was passed an invalid DN: """ + $objUserDN + """."
				Throw-Warning $warningMsg
			}
		
		If($failFunction -eq $true)
			{Return $false}
		Else
			{Return $testgroups}
	}

Function Build-TestSet($testGroup,$objUser) #ECC
	{
		#returns an array of problems to test for.
		$problems = $null
		$problems = @()
		switch($testGroup)
			{
				"basicAccountHealth"
					{
						#$problems += "AccountIsNotArchived"
						$problems += "accountNeedsReactivated"
						$problems += "ldapAttribute-sAMAccountName"
						$problems += "OUisOK"
						$problems += "primaryGroupCorrect"
						$problems += "accountIsEnabled"
						$problems += "ldapAttribute-userAccountControl"
						$problems += "groupMembership-quotaGroup"
						$problems += "groupMembership-classAccounts"
						$problems += "malformedProfilePath"
						$problems += "ldapAttribute-accountExpires"
						$problems += "ldapAttribute-ProfilePath"
					}
				"groupMemberships"
					{
						$problems += "groupMembership-roleGroup"
						$problems += "groupMembership-RES_PrintingGroups"
					}
				"homedriveAccessibility"
					{
						$problems += "ldapAttribute-homeDrive"
						$problems += "ldapAttribute-homeDirectory"
						$problems += "homeDirectoryTarget"
						$problems += "homeShareExists"
						$problems += "HomeShareOrphans"
						$problems += "homeSharePathExists"
					}
				"homedriveConformity"
					{
						$problems += "homeSharePermissions"
						$problems += "homeFolderOrphans"
						$problems += "homeFolderLocation"
					#	$problems += "homeDirectoryPermissions"
					}
				"profileAccessibility"
					{
						$problems += "profilePathExists"
						$problems += "profilePathPermissions"
					}
				"profileConformity"
					{
						$problems += "profileNotCluttered"
					}
				"ldapAttributes"
					{
						$problems += "ldapAttribute-scriptPath"
						$problems += "ldapAttribute-userPrincipalName"
					}
				"unixAttributes"
					{
						$problems += "ldapAttribute-GIDNumber"
						$problems += "ldapAttribute-mssfu30nisdomain"
						$problems += "ldapAttribute-unixhomedirectory"
						$problems += "ldapAttribute-proxyAddresses"
					}
				"rdpProfile"
					{
						 $problems += "terminalServicesAttributes"
					}
				default
					{
						$warningMsg = "ERROR`tCannot build test set for testgroup """ + $testGroup + """ because it is not implemented."
						Throw-Warning $warningMsg
						$problems = $false
					}
			}
			
		#web-only tweaks
		$blnWebOnly = $null
		$blnWebOnly = $false
		$blnWebOnly = Check-IsUserWebOnly $objUser
		If($blnWebOnly -eq $true)
			{
				$script:arrTestsToSkip += "groupmembership-quotaGroup"
				$script:arrTestsToSkip += "ldapAttribute-ProfilePath"
				$script:arrTestsToSkip += "groupMembership-RES_PrintingGroups"
				$script:arrTestsToSkip += "groupMembership-roleGroup"
				$script:arrTestsToSkip += "ldapAttribute-homeDrive"
				$script:arrTestsToSkip += "ldapAttribute-homeDirectory"
				$script:arrTestsToSkip += "homeShareExists"
				$script:arrTestsToSkip += "homeSharePathExists"
				$script:arrTestsToSkip += "homeDirectoryTarget"
				$script:arrTestsToSkip += "homeSharePermissions"
				$script:arrTestsToSkip += "homeFolderOrphans"
				$script:arrTestsToSkip += "homeFolderLocation"
				$script:arrTestsToSkip += "homeDirectoryPermissions"
				$script:arrTestsToSkip += "profilePathExists"
				$script:arrTestsToSkip += "profilePathPermissions"
				$script:arrTestsToSkip += "profileNotCluttered"
				$script:arrTestsToSkip += "RdpProfileExists"
			}
		
		#read tests to skip from settings file
		$arrSettingsFileTestsToSkip = Read-Variable "testsToSkip"
		If($arrSettingsFileTestsToSkip -eq $null -or $arrSettingsFileTestsToSkip -eq $false -or $arrSettingsFileTestsToSkip -eq "")
			{}
		ElseIf($arrSettingsFileTestsToSkip -is [array])
			{
				Foreach($test in $arrSettingsFileTestsToSkip)
					{
						$script:arrTestsToSkip += $test
					}
			}
		Else
			{
				$test = $arrSettingsFileTestsToSkip
				$script:arrTestsToSkip += $test
			}
		
		return $problems
	}

Function Run-AccountTest($test,$objUser) #ECC
	{
		$objUserDN = Pull-LDAPAttribute $objUser "distinguishedName"
		$objUser = $null
		$objUser = [adsi]("LDAP://" + $objUserDN)
		
		$failFunction = $false
		Switch($test)
			{
				#basicAccountHealth
				"accountNeedsReactivated"
					{$results = Check-AccountNeedsReactivated $objUser}
				"AccountIsNotArchived"
					{$results = Check-AccountIsNotArchived $objUser}
				"OUisOK"
					{$results = Check-OUIsOK $objUser}
				"primaryGroupCorrect"
					{$results = Check-PrimaryGroupCorrect $objUser}
				"accountIsEnabled"
					{$results = Check-AccountIsEnabled $objUser}
				"ldapAttribute-userAccountControl"
					{$results = Check-ldapAttribute-userAccountControl $objUser}
				"ldapAttribute-accountExpires"
					{$results = Check-ldapAttribute-accountExpires $objUser}
				"malformedProfilePath"
					{$results = Check-MalformedProfilePath $objUser}
				"ldapAttribute-ProfilePath"
					{$results = Check-ldapAttribute-profilePath $objUser}
				"groupMembership-quotaGroup"
					{$results = Check-GroupMembership-QuotaGroup $objUser}
				"groupMembership-ClassAccounts"
					{$results = Check-groupMembership-ClassAccounts $objUser}
				
				#groupMemberships
				"groupMembership-roleGroup"
					{$results = Check-GroupMembership-RoleGroup $objUser}
				"groupMembership-RES_PrintingGroups"
					{$results = Check-GroupMembership-RES_PrintingGroups $objUser}
				
				#homeDriveAccessibility
				"ldapAttribute-homeDrive"
					{$results = Check-ldapAttribute-homeDrive $objUser}
				"ldapAttribute-homeDirectory"
					{$results = Check-ldapAttribute-homeDirectory $objUser}
				"HomeShareOrphans"
					{$results = Check-HomeShareOrphans $objUser}
				"homeShareExists"
					{$results = Check-homeShareExists $objUser}
				"homeSharePathExists"
					{$results = Check-homeSharePathExists $objUser}
				"homeDirectoryTarget"
					{$results = Check-homeDirectoryTarget $objUser}
				
				#homeDriveConformity
				"homeSharePermissions"
					{$results = Check-homeSharePermissions $objUser}
				"homeFolderOrphans"
					{$results = Check-homeFolderOrphans $objUser}
				"homeFolderLocation"
					{$results = Check-homeFolderLocation $objUser}
				"homeDirectoryPermissions"
					{$results = CheckAndFix-HomeDirectoryPermissions $objUser}
				
				#profileAccessibility
				"profilePathExists"
					{$results = Check-profilePathExists $objUser}
				"profilePathPermissions"
					{$results = CheckAndFix-ProfilePathPermissions $objUser}
					
				#profileConformity
				"profileNotCluttered"
					{$results = Check-ProfileNotCluttered $objUser}
				
				#rdp profiles
				"terminalServicesAttributes"
					{$results = Check-TerminalServicesAttributes $objUser}
				
				#ldapAttribute
				"ldapAttribute-scriptPath"
					{$results = Check-ldapAttribute-scriptPath $objUser}
				"ldapAttribute-userPrincipalName"
					{$results = Check-ldapAttribute-userPrincipalName $objUser}
				"ldapAttribute-sAMAccountName"
					{$results = Check-ldapAttribute-sAMAccountName $objUser}
				"ldapAttribute-GIDNumber"
					{$results = Check-ldapAttribute-GIDNumber $objUser}
				"ldapAttribute-mssfu30nisdomain"
					{$results = Check-ldapAttribute-mssfu30nisdomain $objUser}
				"ldapAttribute-unixhomedirectory"
					{$results = Check-ldapAttribute-unixhomedirectory $objUser}
				"ldapAttribute-proxyAddresses"
					{$results = Check-ldapAttribute-proxyAddresses $objUser}
				Default
					{
						$failFunction = $true
						$warningMsg = "Run-AccountTest was asked to run a test that isn't implemented: """ + $test + """."
						Throw-Warning $warningMsg
					}
			}
		
		If($failFunction -eq $true -or $results -eq $null)
			{Return $false}
		Else
			{Return $results}
	}

Function Fix-Account($objUser,$firstFailedTest)
	{
		$testResults = $null
		$failthisuser = $false
		
		$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
		
		$msg = "ACTION`tFixing account problem: """ + $firstFailedTest + """."
		Write-Out $msg "white" 2
		$fixResults = Fix-AccountProblem $firstFailedTest $objUser
		If($fixResults -eq $false)
			{
				$warningMsg = "ERROR`tCould not fix the account problem: """ + $firstFailedTest + """."
				Throw-Warning $warningMsg
				$failFunction = $true
				$failThisUser = $true
			}
		Else
			{
				$msg = "INFO`t`tAccount problem fixed successfully: """ + $firstFailedTest + """."
				Write-Out $msg "green" 3
			}
		
		#rebind in case we moved the user's OU or something
		$objUserDN = Get-DNbySAMAccountName $sAMAccountName "user"
		$objUser = $null
		$objUser = [adsi]("LDAP://" + $objUserDN)
		
		$continueProcessing = $true
		While($continueProcessing -eq $true -and $failThisUser -ne $true)
			{
				$problem = $null
				$testResults = $null
				
				$msg = "ACTION`t`tRetesting the account for more problems."
				Write-Out $msg "white" 2
				
				$objUserDN = Get-DNbySAMAccountName $sAMAccountName "user"
				$objUser = $null
				$objUser = [adsi]("LDAP://" + $objUserDN)
				
				$testResults = Test-Account $objUser
				$problem = $testResults
				If($testResults -eq $true)
					{
						$continueProcessing = $false
						$results = $true
					}
				ElseIf($testResults -eq $false)
					{
						$warningMsg = "ERROR`tCould not fix account problem. Failing this user."
						Throw-Warning $warningMsg
						$failthisuser = $true
					}
				ElseIf($testResults -eq $lastProblem)
					{
						$warningMsg = "ERROR`tCould not fix account problem: """ + $testResults + """."
						Throw-Warning $warningMsg
						$failThisUser = $true
						$continueProcessing = $false
					}
				Else
					{
						$msg = "ACTION`t`tFixing account problem: """ + $problem + """."
						Write-Out $msg "white" 2
						$fixResults = $null
						$fixResults = Fix-AccountProblem $problem $objUser
						$msg = "ACTION`t`tChecking that the problem is fixed: """ + $problem + """."
						Write-Out $msg "white" 2
						If($fixResults -eq $false)
							{
								$warningMsg = "ERROR`tCould not fix account problem: """ + $testResults + """."
								Throw-Warning $warningMsg
								$failThisUser = $true
							}
						Else
							{
								$msg = "INFO`t`tAccount problem fixed successfully: """ + $testResults + """."
								Write-Out $msg "white" 3
							}
					}
				$lastProblem = $problem
			}
		
		If($failThisUser -eq $true)
			{return $false}
		Else
			{return $true}
	}

Function Fix-AccountProblem($problem,$objUser)
	{
		$blnRetest = $true
		$sAMAccountName = $null
		$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
		$objUserDN = $null
		$objUserDN = Get-DNbySAMAccountName $sAMAccountName "user"
		$objUser = $null
		$objUser = [adsi]("LDAP://" + $objUserDN)
		
		$failFunction = $false
		Switch($problem)
			{
				#basicAccountHealth
				"AccountNeedsReactivated"
					{$results = Fix-AccountNeedsReactivated $objUser}
				"AccountIsNotArchived"
					{$results = Fix-AccountIsNotArchived $objUser}
				"OUisOK"
					{$results = Fix-OUisOK $objUser}
				"primaryGroupCorrect"
					{$results = Fix-PrimaryGroupCorrect $objUser}
				"accountIsEnabled"
					{$results = Fix-AccountIsEnabled $objUser}
				"ldapAttribute-userAccountControl"
					{$results = Fix-ldapAttribute-userAccountControl $objUser}
				"ldapAttribute-accountExpires"
					{$results = Fix-ldapAttribute-accountExpires $objUser}
				"malformedProfilePath"
					{$results = Fix-MalformedProfilePath $objUser}
				"groupMembership-quotaGroup"
					{$results = Fix-GroupMembership-QuotaGroup $objUser}
				"ldapAttribute-ProfilePath"
					{$results = Fix-ldapAttribute-profilePath $objUser}
				"groupMembership-classAccounts"
					{$results = Fix-groupMembership-classAccounts $objUser}
				
				#groupMemberships
				"groupMembership-roleGroup"
					{$results = Fix-GroupMembership-RoleGroup $objUser}
				"groupMembership-RES_PrintingGroups"
					{$results = Fix-groupMembership-RES_PrintingGroups $objUser}
				
				#homeDriveAccessibility
				"ldapAttribute-homeDrive"
					{$results = Fix-ldapAttribute-homeDrive $objUser}
				"ldapAttribute-homeDirectory"
					{$results = Fix-ldapAttribute-homeDirectory $objUser}
				"HomeShareOrphans"
					{$results = Fix-HomeShareOrphans $objUser}
				"homeShareExists"
					{$results = Fix-homeShareExists $objUser}
				"homeSharePathExists"
					{$results = Fix-homeSharePathExists $objUser}
				"homeDirectoryTarget"
					{$results = Fix-homeDirectoryTarget $objUser}
				
				#homeDriveConformity
				"homeSharePermissions"
					{$results = Fix-homeSharePermissions $objUser}
				"homeFolderOrphans"
					{$results = Fix-homeFolderOrphans $objUser}
				"homeFolderLocation"
					{
						$results = Fix-homeFolderLocation $objUser
						$blnRetest = $false
					}

				###since CheckAndFix-HomeDirectoryPermissions will only return false if it failed to fix permissions, then doing it again isn't useful so fail.
				"homeDirectoryPermissions"
					{
						$results = $false
						$failFunction = $true
					}
				
				#profileAccessibility
				"profilePathExists"
					{$results = Fix-profilePathExists $objUser}
				###since CheckAndFix-ProfilePathPermissions will only return false if it failed to fix permissions, then doing it again isn't useful so fail.
				"profilePathPermissions"
					{
						$results = $false
						$failFunction = $true
					}
				
				#profileConformity
				"profileNotCluttered"
					{$results = Fix-profileNotCluttered $objUser}
				
				#rdp profiles
				"terminalServicesAttributes"
					{$results = Fix-TerminalServicesAttributes $objUser}
				
				#ldapAttribute
				"ldapAttribute-scriptPath"
					{$results = Fix-ldapAttribute-scriptPath $objUser}
				"ldapAttribute-userPrincipalName"
					{$results = Fix-ldapAttribute-userPrincipalName $objUser}
				"ldapAttribute-sAMAccountName"
					{$results = Fix-ldapAttribute-sAMAccountName $objUser}
				
				#unix attributes
				"ldapAttribute-GIDNumber"
					{$results = Fix-ldapAttribute-GIDNumber $objUser}
				"ldapAttribute-mssfu30nisdomain"
					{$results = Fix-ldapAttribute-mssfu30nisdomain $objUser}
				"ldapAttribute-unixhomedirectory"
					{$results = Fix-ldapAttribute-unixhomedirectory $objUser}
				"ldapAttribute-proxyAddresses"
					{$results = Fix-ldapAttribute-proxyAddresses $objUser}
				
				Default
					{
						$failFunction = $true
						$warningMsg = "Fix-AccountTest was asked to run a problem that isn't implemented: """ + $problem + """."
						Throw-Warning $warningMsg
					}
			}
		
		If($failFunction -ne $true)
			{
				If($blnRetest -eq $false)
					{
						$msg = "INFO`tSkipping double-check per the fix's direction."
						Write-Out $msg "cyan" 4
					}
				Else
					{
						$msg = "ACTION`tDouble-checking the fix."
						Write-Out $msg "cyan" 4
						$results = $null
						$results = Run-AccountTest $problem $objUser
						If($results -ne $true)
							{$results = $false}
					}
			}
		
		If($failFunction -eq $true)
			{Return $false}
		Else
			{Return $results}
	}

Function Director($strRunMode,$strInputMode,$inputArgDep,$intStartNumber,$intLimit)
	{
		$failFunction = $null
		$failFunction = $false
		
		$scriptUser = $env:username
		
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
		
		#determine runmode. Add libraries if needed.
		$msg = "INFO`tRun Mode is: """ + $strRunMode + """."
		Write-Out $msg "white" 2
		Switch($strRunMode)
			{
				"fix" {}
				"precopy" {}
				"guicreate"
					{
						[void][System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")
						[void][System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
						$strInputMode = "gui"  #hack -- goes to (f)Find-UserInfo
					} 
				Default {}
			}
		
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
								
								$objGroup = $null
								$objGroup = [adsi]("LDAP://" + $groupDN)
								$member = $null
								$member = Pull-LDAPAttribute $objGroup "member"
								Foreach($DN in $member)
									{
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
									}
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
				Default {$formattedInputDep = $inputArgDep}
			}
		
		#write-host -f yellow "DEBUG!`tformattedInputDep: $formattedInputDep"
		
		#loop through all the users
		If($failFunction -eq $false)
			{
				$blnAUserFailed = $null
				$blnAUserFailed = $false
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
								$script:arrTestsToSkip = $null
								$script:arrTestsToSkip = @()
								
								$hshUserInfo = $null
								$hshUserInfo = Find-UserInfo $strInputMode $formattedInputDep $intUserNumber
								
#								Write-host -f yellow "----------------------hshUserInfo!-------------------------------"
#								$hshUserInfo | out-host
								
								
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
										ElseIf($strInputMode -eq "/folder" -or $strInputMode -eq "/group")
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
										$hshUserInfo = PreProcess-UserInfo $hshUserInfo
										
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
												$msg = "ACTION`tBuilding the action set for this user."
												Write-Out $msg "white" 2
												$actionSet = $null 
												$actionSet = Build-ActionSet $hshUserInfo $strRunMode
												If($actionSet -eq $false -or $actionSet -eq $null)
													{
														$warningMsg = "ERROR`tCould not build action set for this user."
														Throw-Warning $warningMsg
														$failedUser = $sAMAccountName
														$arrFailedUsers += $failedUser
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
																		$actionResults = $null
																		$actionResults = $false
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
											{
												$blnAUserFailed = $true
												Write-Fail
											}
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
				#If($intStartNumber)
				$intTotalUsers = $intProcessedUsers
				#If($intTotalUsers -lt 0){$intTotalUsers = 0}
				#ASSERT - intTotalUsers doesn't equal zero
				Report $intTotalUsers $arrFailedUsers
			}
		
		If($failFunction -eq $true)
			{
				$warningMsg = "ERROR`tFailing the script"
				Throw-Warning $warningMsg
				$results = $false
			}
		ElseIf($blnAUserFailed -eq $true)
			{$results = $false}
		Else
			{$results = $true}
		
		Return $results
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

Function PreProcess-UserInfo($hshUserInfo)
	{
		$arrKeys = $null
		$arrKeys = @()
		Foreach($key in $hshUserInfo.Keys)
			{$arrKeys += $key}
		
		#write-host -f yellow "keys: $keys"
		Foreach($key in $arrKeys)
			{
				#write-host -f magenta "current key: $key"
				Switch($key)
					{
						"accountExpires"
							{
								$accountExpires = $hshUserInfo.$key
								$accountExpires = $accountExpires.Replace("\","/")
								$accountExpires = $accountExpires.Replace(".","/")
								$hshUserInfo.Set_Item($key,$accountExpires)
							}
						"gidNumber"
							{
								If($arrKeys -contains "uidNumber")
									{}
								Else
									{
										$uidNumber = $null
										$uidNumber = Find-NextAvailableUID
										$hshUserInfo.Add("uidNumber",$uidNumber)
									}
							}
						Default
							{}
					}
			}
		
		Return $hshUserInfo
	}
	
Function Build-ActionSet($hshUserInfo,$strRunMode)
	{
		$failFunction = $false
		$actionSet = $null
		$actionSet = @()
		$sAMAccountName = $hshUserInfo.Get_Item("sAMAccountName")
		If($sAMAccountName -eq "null" -or $sAMAccountName -eq "")
			{
				$warningMsg = "ERROR`tNo username provided."
				Throw-Warning $warningMsg
				$failFunction = $true
			}
		Else
			{
				$userExists = Check-DoesUserExist $sAMAccountName
				If($userExists)
					{$actionSet += "Validate-UserInfo-ForProcessing"}
				Else
					{$actionSet += "Validate-UserInfo-ForCreation"}
			}
		
		If($strRunMode -like "*precopy*")
			{
				$actionSet += "Precopy-User"
			}
		Else
			{$actionSet += "Process-User"}
		
		If($failFunction -eq $true)
			{return $false}
		Else
			{Return $actionSet}
	}

Function Run-Action($action,$hshUserInfo)
	{
		$results = $null
		$results = $false
		$failFunction = $null
		$failFunction = $false
		Switch($action)
			{
				"Validate-UserInfo-ForCreation"
					{$results = Validate-UserInfo $hshUserInfo "creation"}
				"Validate-UserInfo-ForProcessing"
					{$results = Validate-UserInfo $hshUserInfo "processing"}
				"Process-User"
					{$results = Process-User $hshUserInfo}
				"precopy-user"
					{$results = Precopy-User $hshUserInfo}
				Default
					{
						$warningMsg = "ERROR`tRun-Action was asked to perform an action that isn't defined: """ + $action + """."
						Throw-Warning $warningMsg
						$failFunction = $true
					}
			}
		
		If($failFunction -eq $true)
			{$results = $false}
		Else
			{}
		
		Write-Host -f yellow "DEBUG`t(f)Run-Action`tResults: $results"
		
		Return $results
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


### Account Tests



#basicAccountHealth

Function Check-OUisOK($objUser)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		$results = $null
		$results = $false
		
		#build OU string
		$strRootDN = Read-Variable "domainRootDN"
		 ## DC=Chemistry,DC=ohio-state,DC=edu
		$msg = "Info`t`t`tDomain root read as: """ + $strRootDN + """."
		Write-Out $msg "darkcyan" 4
		
		#users OU
		$strUsersOUCN = $null
		$strUsersOUCN = Read-Variable "UsersOUCN"
		$msg = "Info`t`t`tUsers' OU read as: """ + $strUsersOUCN + """."
		Write-Out $msg "darkcyan" 4
		
		#if all accounts are roaming, skip the filesystem OU
		$blnSkipFilesystemOU = $null
		$blnSkipFilesystemOU = $false
		$blnAllAccountsAreRoaming = $null
		$blnAllAccountsAreRoaming = $false
		$blnAllAccountsAreRoaming = Read-Variable "AllAccountsAreRoaming"
		
		If($blnblnAllAccountsAreRoaming -eq $true)
			{
				$msg = "Info`t`t`tAll accounts are roaming, skipping filesystem OU checks."
				Write-Out $msg "darkcyan" 4
				$blnSkipFilesystemOU = $true
			}
		Else
			{
				$msg = "Info`t`t`tAll accounts are -not- roaming, continuing filesystem OU checks."
				Write-Out $msg "darkcyan" 4
				$blnSkipFilesystemOU = $false
			}
		
		#find the user's filesystem OU
		If($blnSkipFilesystemOU -eq $false)
			{
				$strFileSystemOUCN = $null
				$blnFileSystemOUFound = $null
				$blnFileSystemOUFound = $false
				
				#check for web-only
				$blnWebOnly = $null
				$blnWebOnly = $false
				$blnWebOnly = Check-IsUserWebOnly $objUser
				If($blnWebOnly -eq $true)
					{
						$msg = "Info`t`t`tThis user is Web-Only."
						Write-Out $msg "darkcyan" 4
						$strFileSystemOUCN = Read-Variable "WebOnlyOUCN"
						$blnFileSystemOUFound = $true
					}
				Else
					{
						$msg = "Info`t`t`tThis user is -not- Web-Only."
						Write-Out $msg "darkcyan" 4
					}
				
				If($blnFileSystemOUFound -eq $false)
					{
						#check for roaming
						$blnRoaming = $null
						$blnRoaming = $false
						$blnRoaming = Check-IsUserRoaming $objUser
						If($blnRoaming -eq $true)
							{
								$msg = "Info`t`t`tThis user has a roaming profile."
								Write-Out $msg "darkcyan" 4
								$strFileSystemOUCN = Read-Variable "RoamingOUCN"
								$blnFileSystemOUFound = $true
							}
						Else
							{
								$msg = "Info`t`t`tThis user does -not- have a roaming profile."
								Write-Out $msg "darkcyan" 4
							}
					}
				
				#default to redirected
				If($blnFileSystemOUFound -eq $false)
					{
						$strFileSystemOUCN = Read-Variable "RedirectedOUCN"
					}
				
				$msg = "Info`t`t`tfilesystem OU: """ + $strFileSystemOUCN + """."
				Write-Out $msg "darkcyan" 4
			}
		
		#check class-only users are in "class-only" OU	
		$blnClassOnly = $null
		$blnClassOnly = $false
		$blnClassOnly = Check-IsUserClassOnly $objUser
		If($blnClassOnly -eq $true)
			{
				$msg = "Info`t`t`tThis user has a Class-Only account."
				Write-Out $msg "darkcyan" 4
				$blnAllClassAccountsAreRoaming = $null
				$blnAllClassAccountsAreRoaming = Read-Variable "allClassAccountsAreRoaming"
				If($blnAllClassAccountsAreRoaming -eq $true)
					{
						$msg = "Info`t`t`tAll class accounts are roaming."
						Write-Out $msg "darkcyan" 4
						$strFileSystemOUCN = Read-Variable "RoamingOUCN"
					}
				Else
					{}
			}
		Else
			{
				$msg = "Info`t`t`tThis user does -not- have a Class-Only account."
				Write-Out $msg "darkcyan" 4
			}
		
		#put all the pieces together
		If($blnSkipFilesystemOU -eq $false)
			{$strTargetDN += "OU=" + $strFileSystemOUCN}
		$strTargetDN += ",OU=" + $strUsersOUCN
		$strTargetDN += "," + $strRootDN
		$msg = "Info`t`t`tTarget DN generated as: """ + $strTargetDN + """."
		Write-Out $msg "darkcyan" 4
		
		
		
		#build the test string
		$strTestString = $null
		If($blnClassOnly -eq $true)
			{
				$strClassOnlyOUCN = $null
				$strClassOnlyOUCN = Read-Variable "ClassOnlyOUCN"
				$msg = "Info`t`t`tClass-Only OU: """ + $strClassOnlyOUCN + """."
				Write-Out $msg "darkcyan" 4
				$strTestString = "*" + $strClassOnlyOUCN + "*," + $strTargetDN
			}
		Else
			{$strTestString = "*group*," + $strTargetDN}
		$msg = "Info`t`t`tBuilt the following test string: """ + $strTestString + """."
		Write-Out $msg "darkcyan" 4
		
		#Get user's DN
		$strUserDN = $null
		$strUserDN = Pull-LdapAttribute $objUser "distinguishedName"
		$msg = "INFO`t`t`tUser DN read as """ + $strUserDN + """."
		Write-Out $msg "darkcyan" 4
		
		#compare the user's DN to the test string
		If($strUserDN -like $strTestString)
			{
				$msg = "Info`t`t`tThe user DN Matches the test string."
				Write-Out $msg "darkcyan" 4
				$results = $true
			}
		Else
			{
				$msg = "Warning`t`t`tThe user DN does -not- match the test string."
				Throw-Warning $msg "darkcyan" 4
				$results = $false
			}
		
		Return $results
	}

Function Check-IsUserRoaming($objUser)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		$results = $null
		$results = $false
		
		$profilePath = Pull-LdapAttribute $objUser "profilePath"
		If($profilePath -eq $null)
			{$results = $false}
		Else
			{$results = $true}
		
		If($failThisFunction -eq $true)
			{$results = $false}
		Else
			{}
		Return $results
	}

Function Check-IsUserClassOnly($objUser)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		$results = $null
		$results = $true
		
		$blnClassGroups = $null
		$blnClassGroups = $false
		$blnClassGroups = Check-GroupMembership-AnyClassGroup $objUser
		If($blnClassGroups -eq $true)
			{
				$arrExemptGroupCNPrefixes = $null
				$arrExemptGroupCNPrefixes = Read-Variable "GroupCNsExemptFromClassOnlyChecks"
				
				$memberOf = $null
				$memberOf = Pull-LDAPAttribute $objUser "memberof"
				Foreach($groupDN in $memberOf)
					{
						$blnExempt = $null
						$blnExempt = $false
						Foreach($exemptCN in $arrExemptGroupCNPrefixes)
							{
								If($groupDN -like ("CN=" + $exemptCN + "*"))
									{$blnExempt = $true}
								Else
									{}
							}
						
						If($blnExempt -eq $false)
							{
								$results = $false
								Break
							}
						Else
							{}
					}
			}
		Else
			{$results = $false}
		
		#write-host -f yellow "debug`t(f)check-isuserclassonly: $results"
		
		If($failThisFunction -eq $true)
			{$results = $false}
		Else
			{}
		Return $results
	}

Function Check-AccountIsEnabled($objUser) #SkipECC
	{
		$objUserDN = $null
		$objUserDN = Pull-LDAPAttribute $objUser "distinguishedName"
		$objUser = $null
		$objUser = [adsi]("LDAP://" + $objUserDN)
		
		$UAC_1 = $null
		$UAC_1 = Pull-LDAPAttribute $objUser "userAccountControl"
		$msg = "INFO`t(LDAP Read)`tUser's UAC value (Method 1): """ + $UAC_1 + """."
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
		$msg = "INFO`t(Variable)`tUAC Flags: """ + $strFlags+ """."
		Write-Out $msg "darkcyan" 4
		
		If($UAC_1_Flags -contains "ACCOUNTDISABLE")
			{$results = $false}
		Else
			{$results = $true}
		
		If($results -eq $false)
			{
				$UAC_2 = $null
				$UAC_2 = $objUser.userAccountControl.value
				$msg = "INFO`t(LDAP Read)`tUser's UAC valued (Method 2): """ + $UAC_2 + """."
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
				$msg = "INFO`t(Variable)`tUAC Flags: """ + $strFlags+ """."
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

Function Check-ldapAttribute-userAccountControl($objUser)
	{
		$results = $null
		$results = $true
		$UAC = Pull-LDAPAttribute $objUser "userAccountControl"
		$msg = "INFO`t(Variable)`tUAC: """ + $UAC+ """."
		Write-Out $msg "darkcyan" 4
		
		$flags = Get-UACFlags $uac
		$i = 0
		Foreach($flag in $flags)
			{
				If($i -eq 0)
					{$strFlags += $flag}
				Else
					{$strFlags = $strFlags + ", " + $flag}
				$i++
			}
		$msg = "INFO`t(Variable)`tUAC Flags: """ + $strFlags+ """."
		Write-Out $msg "darkcyan" 4
		
		$badUACFlags = Read-Variable "badUACflags"
		Foreach($flag in $flags)
			{
				If($badUACFlags -contains $flag)
					{
						$msg = "INFO`t`t`tFound bad UAC flag """ + $flag + """ ."
						Write-Out $msg "darkcyan" 4
						$results = $false
					}
			}
		Return $results
	}

Function Check-ldapAttribute-accountExpires($objUser)
	{
		$failFunction = $null
		$blnAccountExpires = $null
		$blnAccountShouldExpire = $null
		$expectedExpirationDate = $null
		$expirationDate = $null
		$sAMAccountName = $null
		$results = $false
		
			$startTime = $null
			$startTime = get-date
		$msg = "ACTION`t`t`tChecking if this account should be expired."
		Write-Out $msg "darkcyan" 4
		$blnAccountShouldBeExpired = Check-AccountShouldBeExpired $objUser
		#$blnAccountShouldBeExpired = $true
		$msg = "INFO`t`t`tAccount should be expired: " + $blnAccountShouldBeExpired + "."
		Write-Out $msg "darkcyan" 4
			$complTime = $null
			$complTime = (get-date) - $startTime
			$complMseconds = $complTime.duration().totalmilliseconds
			$complMseconds = [Math]::Round($complMseconds,0)
			$msg = "Info`t`t`tTest took " + $complMseconds + " totalmilliseconds to complete."
			Write-Out $msg "darkcyan" 4
			
			$startTime = $null
			$startTime = get-date
		$msg = "ACTION`t`t`tChecking if this account should expire."
		Write-Out $msg "darkcyan" 4
		$blnAccountShouldExpire = Check-AccountShouldExpire $objUser
		#$blnAccountShouldExpire = $true
		$msg = "INFO`t`t`tAccount should expire: " + $blnAccountShouldExpire + "."
		Write-Out $msg "darkcyan" 4
			$complTime = $null
			$complTime = (get-date) - $startTime
			$complMseconds = $complTime.duration().totalmilliseconds
			$complMseconds = [Math]::Round($complMseconds,0)
			$msg = "Info`t`t`tTest took " + $complMseconds + " totalmilliseconds to complete."
			Write-Out $msg "darkcyan" 4
					
			$startTime = $null
			$startTime = get-date
		$msg = "ACTION`t`t`tChecking if this account _is_ expired."
		Write-Out $msg "darkcyan" 4
		$blnAccountIsExpired = Check-AccountIsExpired $objUser
		#$blnAccountIsExpired = $true
		$msg = "INFO`t`t`tAccount is expired: " + $blnAccountIsExpired + "."
		Write-Out $msg "darkcyan" 4
			$complTime = $null
			$complTime = (get-date) - $startTime
			$complMseconds = $complTime.duration().totalmilliseconds
			$complMseconds = [Math]::Round($complMseconds,0)
			$msg = "Info`t`t`tTest took " + $complMseconds + " totalmilliseconds to complete."
			Write-Out $msg "darkcyan" 4
			
			$startTime = $null
			$startTime = get-date
		$msg = "ACTION`t`t`tChecking if this account does expire."
		Write-Out $msg "darkcyan" 4
		$blnAccountExpires = Check-AccountExpires $objUser
		#$blnAccountExpires = $true
		$msg = "INFO`t`t`tAccount expires: " + $blnAccountExpires + "."
		Write-Out $msg "darkcyan" 4
			$complTime = $null
			$complTime = (get-date) - $startTime
			$complMseconds = $complTime.duration().totalmilliseconds
			$complMseconds = [Math]::Round($complMseconds,0)
			$msg = "Info`t`t`tTest took " + $complMseconds + " totalmilliseconds to complete."
			Write-Out $msg "darkcyan" 4
			
		$startTime = $null
		$startTime = get-date
		
		If($blnAccountShouldBeExpired -eq $true)
			{
				If($blnAccountIsExpired -eq $true)
					{$results = $true}
				Else
					{$results = $false}
			}
		Else
			{
				#If the account should eventually someday expire
				If($blnAccountShouldExpire -eq $true)
					{
						If($blnAccountExpires -eq $true)
							{
								$expirationDate = Find-ExpirationDate $objUser
								$msg = "INFO`t`t`tRead expiration date: " + $expirationDate + "."
								Write-Out $msg "darkcyan" 4
								$expectedExpirationDate = Find-ExpectedExpirationDate $objUser
								$msg = "INFO`t`t`tExpected Expiration Date: " + $expectedExpirationDate + "."
								Write-Out $msg "darkcyan" 4
								
								$expectedExpirationDateType = ($ExpectedExpirationDate.gettype().name)
								If($expectedExpirationDateType -ne "DateTime")
									{
										$warningMsg = "WARNING`t`t`tCannot determine the user's expected expiration date. This will have to be done manually."
										Throw-Warning $warningMsg
										$results = $true
#										If($blnAccountIsExpired)
#											{
#												$msg = "ACTION`t`t`tFailing this user because they are expired."
#												Write-Out $msg "white" 2
#												$results = $false
#											}
#										Else
#											{
#												$msg = "ACTION`t`t`tPassing this user because they are not expired."
#												Write-Out $msg "white" 2
#												$results = $true
#											}
									}
								ElseIf($expectedExpirationDate -eq $expirationDate)
									{$results = $true}
								ElseIf(($expectedExpirationDate.AddDays(1)) -eq $expirationDate)
									{$results = $true}
								ElseIf(($expectedExpirationDate.AddDays(-1)) -eq $expirationDate)
									{$results = $true}
							}
						Else
							{$results = $false}
							
					}
				Else
					{
						#If the account should never expire
						If($blnAccountExpires -eq $true)
							{$results = $false}
						Else
							{$results = $true}
					}
			}
		
			$complTime = $null
			$complTime = (get-date) - $startTime
			$complMseconds = $complTime.duration().totalmilliseconds
			$complMseconds = [Math]::Round($complMseconds,0)
			$msg = "Info`t`t`tParsing results took " + $complMseconds + " totalmilliseconds to complete."
			Write-Out $msg "darkcyan" 4
		
		Return $results
	}

Function Check-AccountShouldBeExpired($objUser)
	{
		$results = $null
		$blnClassAccountsOnly = $null
		$blnClassAccountsOnly = $false
		$blnClassAccountsOnly = Check-OnlyQuotaGroupIsClassAccounts $objUser
		$blnCurrentClassGroup = $null
		$blnCurrentClassGroup = $false
		$blnCurrentClassGroup = Check-IsMemberOfCurrentClassGroup $objUser
		
		#check for ugrad major
		$sUserDN = $null
		$sUserDN = Pull-LDAPAttribute $objUser "distinguishedName"
		$sUgradMajorCN = $null
		$sUgradMajorCN = Read-Variable "ugradMajorGroupCN"
		$sUgradMajorDN = $null
		$sUgradMajorDN = Get-DNbyCN $sUgradMajorCN
		$blnUgradMajor = $null
		$blnUgradMajor = $false
		$blnUgradMajor = Check-IsMemberOfGroup $sUserDN $sUgradMajorDN
		
		#write-host -f cyan "blnCurrentClassGroup: " + $blnCurrentClassGroup 
		If($blnCurrentClassGroup -eq $true)
			{$results = $false}
		ElseIf($blnClassAccountsOnly -eq $true -and $blnCurrentClassGroup -eq $false)
			{$results = $true}
		ElseIf($blnUgradMajor -eq $true)
			{$results = $false}	
		Else
			{$results = Check-AccountIsExpired $objUser}
		
		Return $results
	}

Function Check-IsMemberOfCurrentClassGroup($objUser)
	{
		$results = $false
		$groups = $objUser.MemberOf
		$currentQuarterClassString = Read-Variable "currentQuarterClassString"
		#write-host -f yellow "DEBUG`tcurrentQuarterClassString: $currentQuarterClassString"
		Foreach($groupDN in $groups)
			{
				If($groupDN -like "*classes*")
					{
						If($groupDN -like ("*" + $currentQuarterClassString + "*"))
							{$results = $true}
					}
			}
		
		Return $results
	}

Function Check-AccountIsExpired($objUser) #SkipECC
	{
		$expirationDate = Find-Expirationdate $objUser
		If($expirationDate -eq $false)
			{$results = $false}
		Else
			{
				$today = get-date
				If($expirationDate -lt $today)
					{$results = $true}
				Else
					{$results = $false}
			}
		
		$expirationDate = $null
		
		Return $results
	}

Function Check-AccountShouldExpire($objUser) #SkipECC
	{
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

Function Check-AccountExpires($objUser)
	{
		$blnAccountExpires = $null
		$expirationDate = $null
		$sAMAccountName = $null
		$results = $false
		
		#$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
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

Function Find-ExpectedExpirationDate($objUser) #ECC
	{
		$failFunction = $false
		$expectedGroupExpiration = $false
		$results = $false
		$keys = $false
		$groups = $objUser.MemberOf
		
		$hshGroupExpirationDates = Read-Variable "hshGroupExpirationDates"
		$keys = $hshGroupExpirationDates.Keys
		Foreach($group in $groups)
			{
				If($results -ne "never" -and $results -ne "unknown")
					{
						$expectedGroupExpiration = Find-GroupExpirationDate $group
						#$msg = "INFO`t`t`tFind-GroupExpirationDate returned: """ + $expectedGroupExpiration + """."
						#Write-Out $msg "darkcyan" 4
						If($expectedGroupExpiration -eq "never")
							{$results = "never"}
						ElseIf($expectedGroupExpiration -eq "unknown")
							{$results = "unknown"}
						ElseIf($expectedGroupExpiration -eq $false) #should never happen
							{}
						Else
							{
								$resultType = ($results.gettype().name)
								$expectedExpirationType = ($expectedGroupExpiration.gettype().name)
								#write-host -f yellow "results: $results`nresultType: $resultType`nexpectedGroupExpiration: $expectedGroupExpiration"
								If($resultType -eq "DateTime" -and $expectedExpirationType -eq "DateTime")
									{
										If($expectedGroupExpiration -gt $results)
											{$results = $expectedGroupExpiration}
										Else
											{}
									}
								Else
									{$results = $expectedGroupExpiration}
								
								#$resultType = ($results.gettype().name)
								#write-host -f yellow "(2)results: $results`nresultType: $resultType`nexpectedGroupExpiration: $expectedGroupExpiration"
							}
					}
			}
		
		If($results -eq $false)
			{
				$failFunction = $true
				$warningMsg = "ERROR`tCould not calculate expected expiration date from user's group memberships."
				Throw-Warning $warningMsg
			}
		
		#write-host -f yellow "returning $results"
		
		If($failfunction -eq $true)
			{Return $false}
		Else
			{Return $results}
	}
	
Function Find-GroupExpirationDate($group) #SkipECC
	{
		$results = $false
		$hshGroupExpirationDates = Read-Variable "hshGroupExpirationDates"
		#Write-Host -f yellow "hshGroupExpirationDates"
		#$hshGroupExpirationDates | out-host
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

Function Check-MalformedProfilePath($objUser)
	{
		$results = $true
		#trap{continue;}
		
		$profilePath = Pull-LDAPAttribute $objUser "profilePath"
		$msg = "INFO`t`t`tldapAttribute-profilePath: """ + $profilePath + """."
		Write-Out $msg "darkcyan" 4
		#Is the attribute filled?
		If($profilePath -eq " ")
			{$results = $false}
		Return $results
	}

Function Check-ldapAttribute-profilePath($objUser) #SkipECC
	{
		trap{continue;}
		$profilePath = Pull-LDAPAttribute $objUser "profilePath"
		$msg = "INFO`t`t`tldapAttribute-profilePath: """ + $profilePath + """."
		Write-Out $msg "darkcyan" 4
		
		#if the user is redirected, profilepath needs to be null
		$objUserDN = Pull-LDAPAttribute $objUser "distinguishedName"
		If($objUserDN -like "*redirected*")
			{
				If($profilePath -eq $null -or $profilePath -eq "")
					{$results = $true}
				Else
					{$results = $false}
			}
		ElseIf($objUserDN -like "*roaming*")
			{
				If($profilePath -eq $null -or $profilePath -eq " ")
					{$results = $false}
				Else
					{
						$fileserver = Read-Variable "fileserver-profiles"
						$generatedProfilePath = "\\" + $fileserver + "\profiles$\" + $sAMAccountName
						$msg = "INFO`t`t`tgeneratedProfilePath: """ + $generatedProfilePath+ """."
						Write-Out $msg "darkcyan" 4
						#Is the attribute correct?
						If($profilePath -eq $generatedProfilePath)
							{$results = $true}
						Else
							{$results = $false}
					}
				
				
			}
		
		#Is the attribute filled?
		
		Return $results
	}



#HomeDirectoryAccessibility

Function Check-ldapAttribute-homeDrive($objUser) #SkipECC
	{
		$results = $null
		trap{continue;}
		
		#Check the homeDrive attribute
		$validHomedriveAttribute = Read-Variable "homeDriveAttribute"
		$homeDrive = Pull-LDAPAttribute $objUser "homeDrive"
		$msg = "INFO`t`t`tldapAttribute-homeDrive: """ + $homeDrive + """."
		Write-Out $msg "darkcyan" 4
		$msg = "INFO`t`t`tValid Homedrive Attribute: """ + $validHomedriveAttribute + """."
		Write-Out $msg "darkcyan" 4
		If($homeDrive -eq $validHomedriveAttribute)
			{$results = $true}
		Else
			{$results = $false}
		
		Return $results
	}

Function Check-ldapAttribute-homeDirectory($objUser) #SkipECC
	{
		$results = $null
		trap{continue;}
		
		#Check the homeDirectory attribute
		$homeDirectory = Pull-LDAPAttribute $objUser "homeDirectory"
		$msg = "INFO`t`t`tldapAttribute-homeDirectory: """ + $homeDirectory + """."
		Write-Out $msg "darkcyan" 4
		If($homeDirectory -ne $null`
			-and $homeDirectory -ne " ")
			{$results = $true}
		Else
			{$results = $false}
		
		Return $results
	}






Function Check-HomeShareOrphans($objUser)
	{
		$arrFS = Read-Variable "fileserverlist"
		$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
		$sharename = $sAMAccountName + "$"
		
		$homeFS = $null
		$homeFS = Generate-UserHomeFS $objUser
		$msg = "Info`t`tGenerated user home file server is """ + $homeFS + """."
		Write-Out $msg "darkcyan" 3
		
		$fsFount = 1
		$arrFS | % {
			$fs = $_
			If($fs -eq $homeFS)
				{}
			Else
				{
					$msg = "Action`t`tTesting for orphaned share on file server """ + $fs + """."
					Write-Out $msg "darkcyan" 3
					$bShareExists = $null
					$bShareExists = $false
					$bShareExists = Check-DoesShareExist $shareName $fs
					If($bShareExists -eq $true)
						{
							$msg = "INFO`t`tFound orphaned share on file server """ + $fs + """."
							Write-Out $msg "darkcyan" 3
							$fsCount++
						}
				}
		}
		
		If($fsCount -gt 1)
			{$results = $false}
		Else
			{$results = $true}
		Return $results
	}

Function Check-homeShareExists($objUser) #SkipECC
	{
		trap{continue}
		$sharePath = $null
		$homeFS = Generate-UserHomeFS $objUser
		
		$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
		$shareName = $sAMAccountName + "$"
		
		$sharePath = Get-SharePath $shareName $homeFS
		$msg = "INFO`t`t`tshareName: ""\\" + $homeFS + "\" + $shareName + """."
		Write-Out $msg "darkcyan" 4
		$msg = "INFO`t`t`tsharePath: """ + $sharePath + """."
		Write-Out $msg "darkcyan" 4
		If($sharePath -eq $null)
			{$results = $false}
		Else
			{$results = $true}
		Return $results
	}

Function Check-homeSharePathExists($objUser) #SkipECC
	{
		$homeFS = Get-UserHomeFS $objUser
		
		$sAMAccountName = $null
		$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
		$shareName = $null
		$shareName = $sAMAccountName + "$"
		
		$sharePath = Get-SharePath $shareName $homeFS
		$remoteSharePath = $null
		$remoteSharePath = Convert-SharePathtoUNCPath $sharePath $homeFS
		$test = $null
		$test = Test-Path $remoteSharePath
		If($test -eq $true)
			{$results = $true}
		Else
			{$results = $false}
		Return $results
	}

Function Check-homeDirectoryTarget($objUser)
	{
		trap{continue;}
		
		$fileServer = Generate-UserHomeFS $objUser
		
		$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
		$homeDirectory = Pull-LDAPAttribute $objUser "homeDirectory"
		$generatedHomeDirectoryAttribute = "\\" + $fileserver + "\" + $sAMAccountName + "$"
		
		$msg = "INFO`t`t`tldapAttribute-homeDirectory: """ + $homeDirectory + """."
		Write-Out $msg "darkcyan" 4
		$msg = "INFO`t`t`tgenerated homeDirectory: """ + $generatedHomeDirectoryAttribute + """."
		Write-Out $msg "darkcyan" 4
		
		If($homeDirectory -eq $generatedHomeDirectoryAttribute)
			{$results = $true}
		Else
			{$results = $false}
		Return $results
	}



#homeDirectoryConformity
	
Function Check-homeSharePermissions($objUser)
	{
		#Get Some Info
		$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
		$shareName = $sAMAccountName + "$"
		
		#Start some variables aworkin'.
		$results = $true
		
		
		#Get Share Users
		$homeDirectory = Pull-LDAPAttribute $objUser "homeDirectory"
		$fileServer = [regex]::match($homeDirectory,'[^\\]+').value
		If($fileServer -eq $null -or $fileServer -eq "")
			{$fileServer = Read-Variable "fileserver"}
		
		$strWMI = $null
		$strWMI = "\\" + $fileserver + "\root\cimv2:Win32_LogicalShareSecuritySetting.name='" + $shareName + "'"
		$lsss = $null
		$lsss = [wmi]$strWMI
		$shareUsers = $null
		$shareUsers = @()
		$dacl = $null
		$dacl = $LSSS.GetSecurityDescriptor().descriptor.dacl
		$dacl | %{$shareUsers += $_.Trustee.Name}
		
		#write-host -f yellow "debug`tshareUsers: $shareUsers"
		
		#Check for obvious bad values (false, null, and single-user)
		If($shareUsers -eq $false`
			-or $shareUsers -eq $null)
			{$results = $false}
		ElseIf(($shareUsers -is [array]) -eq $false)
			{
				$msg = "INFO`t`t`tOnly a single user was returned."
				Write-Out $msg "darkcyan" 4
				$results = $false
			}
		Else
			{
				$homeDriveAdminsGroup = Read-Variable "homedriveAdminsGroup"
				$goodUsers = @($homeDriveAdminsGroup,$sAMAccountName)
				Foreach($user in $shareUsers)
					{
						If($goodUsers -contains $user)
							{}
						Else
							{
								$msg = "INFO`t`t`tUser does not belong in the ACL: """ + $user + """."
								Write-Out $msg "darkcyan" 4
								$results = $false
							}
					}
			}
		
		#Check that all users have "full control".
		#REFERENCE: http://www.peetersonline.nl/index.php/powershell/listing-share-permissions-for-remote-shares/
		Foreach($acl in $dacl)
			{
				If($results -ne $false)
					{
						$rawAccessMask = $acl.AccessMask
						If($rawAccessMask -eq 2032127)
							{}
						Else
							{
								Switch ($rawAccessMask)
									{
										2032127 {$AccessMask = "FullControl"}
										1179785 {$AccessMask = "Read"}
										1180063 {$AccessMask = "Read, Write"}
										1179817 {$AccessMask = "ReadAndExecute"}
										-1610612736 {$AccessMask = "ReadAndExecuteExtended"}
										1245631 {$AccessMask = "ReadAndExecute, Modify, Write"}
										1180095 {$AccessMask = "ReadAndExecute, Write"}
										268435456 {$AccessMask = "FullControl (Sub Only)"}
										default {$AccessMask = $DACL.AccessMask}
									}
								$username = $acl.trustee.name
								$msg = "INFO`t`t`tTrustee: """ + $username + """ is listed incorrectly as """ + $accessMask + """."
								Write-Out $msg "darkcyan" 4
								$results = $false
							}
					}
			}
		
		
		#Chcek to make sure all 'goodUsers' are present.
		If($results -ne $false)
			{
				Foreach($user in $goodUsers)
					{
						If($shareUsers -contains $user)
							{}
						Else
							{
								$msg = "INFO`t`t`tUser must be added to the ACL: """ + $user + """."
								Write-Out $msg "darkcyan" 4
								$results = $false
							}
					}
			}
		
		Return $results
	}

Function Check-homeFolderOrphans($objUser)
	{
		$orphans = $null
		$orphans = Find-OrphanedHomeDirectories $objUser
		$results = $null
		If($orphans -eq $false)
			{
				$msg = "INFO`t`t`tNo orphans found."
				Write-Out $msg "darkcyan" 4
				$results = $true
			}
		Else
			{
				$msgs = $null
				$msgs = @()
				$msgs += "INFO`t`t`tFound the following orphaned folders:"
				Foreach($strOrphan in $orphans)
					{$msgs += "INFO`t`t`t*" + $strOrphan}
				Foreach($msg in $msgs)
					{write-Out $msg "darkcyan" 4}
				$results = $false
			}
		
		Return $results
	}

Function Check-homeFolderLocation($objUser)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		
		$sAMAccountName = $null
		$sAMAccountName = pull-ldapattribute $objUser "sAMAccountName"
		$shareName = $null
		$shareName = $sAMAccountName + "$"
		
		$fileserver = Get-UserHomeFS $objUser
		$homeFS = $fileserver
		
		$strGeneratedHomePath = $null
		$strGeneratedHomePath = Build-HomeFolderDestinationPath $objUser
		If($strGeneratedHomePath -eq $null -or $strGeneratedHomePath -eq $false)
			{
				$warningMsg = "ERROR`t`t`tCould not build home folder destination path for user."
				Throw-warning $warningMsg
				$failThisFunction = $true
			}
		Else
			{
				$msg = "INFO`t`t`tGenerated home folder destination path: """ + $strGeneratedHomePath + """."
				Write-Out $msg "darkcyan" 4
			}
		
		$strSharePath = $null
		$strSharePath = Get-SharePathAsAdminUNC $shareName $homeFS
		If($strSharePath -eq $null -or $strGeneratedHomePath -eq $false)
			{
				$warningMsg = "ERROR`t`t`tCould not find home share for this user."
				Throw-warning $warningMsg
				$failThisFunction = $true
			}
		Else
			{
				$msg = "INFO`t`t`tCurrent home share read as: """ + $strSharePath + """."
				Write-Out $msg "darkcyan" 4
			}
		
		If($failThisFunction -eq $false)
			{
				If($strGeneratedHomePath -eq $strSharePath)
					{$results = $true}
				Else
					{$results = $false}
			}
		
		If($failThisFunction -eq $true)
			{$results = $false}
		Else
			{}
			
		Return $results
	}

Function CheckAndFix-HomeDirectoryPermissions($objUser)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		
		$blnReadOnly = $null
		$blnReadOnly = $false
		$blnReadOnly = Read-Variable "ReadOnly"
		
		$homeDirectory = Pull-LDAPAttribute $objUser "homeDirectory"
		$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
		$shareName = $null
		$shareName = $sAMAccountName + "$"
		
		$fileserver = Get-UserHomeFS $objUser
		$homefs = $fileserver
		
		$uncPath = $null
		$uncPath = Get-SharePathAsAdminUNC $shareName $homeFS
		
		#check permissions
		$blnPermissionsOK = $null
		$blnPermissionsOK = $false
		$blnPermissionsOK = CheckAndFix-FolderPermissions $uncPath $sAMAccountName
		If($blnPermissionsOK -ne $true)
			{$blnPermissionsOK = $false}
		
		#report
		$results = $blnPermissionsOK
		
		If($results -ne $null)
			{Return $results}
		Else
			{Return $false}
	}

Function CheckAndFix-FolderPermissions($folderPath,$sAMAccountName,$blnCheckOnly,$strOptionalRootPath)
	{
		If($blnCheckOnly -ne $true)
			{$blnCheckOnly = $false}
		$fail = $false
		$blnReadOnly = $null
		$blnReadOnly = $false
		$blnReadOnly = Read-Variable "ReadOnly"
		$results = $true
		$intFixed = $null
		$intFixed = 0
		$intNotFixed = $null
		$intNotFixed = 0
		
		#basic sanity checks
		$arrProtectedFolders = $null
		$arrProtectedFolders = @()
		$profileShare = Read-Variable "profileShare"
		$profileShare = Trim-TrailingSlash $profileShare
		$arrInternalHomeDirectoryRoots = Read-Variable "internalHomeDirectoryRoots"
		$arrHomeDirectoryQuotaPaths =  Read-Variable "homeDirectoryQuotaPaths"
		
		$arrInternalHomeDirectoryRoots | % {
			$strRoot = $null
			$strRoot = Trim-TrailingSlash $_
			$arrHomeDirectoryQuotaPaths | % {
				$newPath = $null
				$newPath = $strRoot + "\" + $_
				$arrProtectedFolders += $newPath
			}			
		}
		$arrProtectedFolders += $profileShare
		
		$folderPath = Trim-TrailingSlash $folderPath
		If($arrProtectedFolders -contains $folderPath)
			{
				$warningMsg = "WARNING`t`tScript attempted to change permissions on a protected path: """ + $folderPath + """."
				Throw-Warning $warningMsg
				$fail = $true
			}
		Else
			{}
		
		
		
		###DEBUG!!!
		#$arrProtectedFolders | % {write-host -f cyan $_}
		
		If($fail -eq $false)
			{
				#Check Root Permissions
				$msg = "ACTION`t`tChecking root folder permissions."
				Write-Out $msg "darkcyan" 4
				$userDN = Get-DNbySAMAccountName $sAMAccountName
				$root = Get-Item $folderPath -force
				$rootCheck = Check-FSObjectACLPermissions $sAMAccountName $folderPath
			}
		
		If($rootCheck -eq $false -and $fail -eq $false)
			{
				$warningMsg = "INFO`t`tRoot folder permissions check FAILED."
				Throw-Warning $warningMsg
				If($blnReadOnly -eq $false -and $blnCheckOnly -eq $false)
					{
						$msg = "ACTION`t`tAttempting root folder permissions repair."
						Write-Out $msg "darkcyan" 2
						$blnFixed = $null
						$blnFixed = $false
						$blnFixed = Fix-FSObjectPermissions $folderPath $userDN $strOptionalRootPath
						$blnFixed = Check-FSObjectACLPermissions $sAMAccountName $folderPath
						If($blnFixed -eq $false)
							{
								$warningMsg = "WARNING`tCould not fix permissions problem with the directory root."
								Throw-Warning $warningMsg
								$fail = $true
							}
						Else
							{
								$msg = "INFO`t`tRoot folder permissions repair was successful. Root folder permissions are now OK."
								Write-Out $msg "darkcyan" 2
							}
					}
				Else
					{$fail = $true}
				$intFixed++
			}
		Else
			{
				$msg = "INFO`t`tRoot folder permissions are OK."
				Write-Out $msg "darkcyan" 4
			}
		
		#continue by checking the children
		If($fail -eq $false)
			{
				$blnResetAll = $null
				$blnResetAll = $false
				$msg = "ACTION`t`tChecking children permissions."
				Write-Out $msg "darkcyan" 4
				If($fail -eq $false)
					{
						#grab children objects
						$children = get-childitem -force -recurse $folderPath
						If($children -ne $null)
							{
								#loop through them
								Foreach($child in $children)
									{
										#if we've fixed a bunch then just reset them all
										If($intFixed -ge 11 -or $fail -eq $true)
											{
												$blnResetAll = $true
												$msg = "INFO`tSingle-object repair limit exceeded."
												Write-Out $msg "darkcyan" 4
												Break
											}
										Else
											{}
										#filter out names longer than get-acl can handle
										$strRegex = Read-Variable "ACLRegex"
										$blnTooLong = $null
										$blnTooLong = $false
										If($child.fullname.length -gt 220)
											{$blnTooLong = $true}
										Else
											{}
										
										#Check the permissions on the current object
										If($child.fullname -match $strRegex -and $blnTooLong -eq $false)
											{
												$targetPath = $child.fullname
												$childCheck = Check-FSObjectACLPermissions $sAMAccountName $targetPath
												If($childCheck -eq $false)
													{
														#if read-only mode, mark and continue. otherwise repair and increment repaired count
														If($blnReadOnly -eq $true)
															{
																$msg = "INFO`t`tSkipping the repair of this object since read-only mode was invoked with /eval."
																Write-Out $msg "darkcyan" 4
																$intNotFixed++
															}
														Else
															{
																If($blnCheckOnly -eq $false)
																	{
																		$msg = "Action`t`tAttempting to repair permissions for this object."
																		Write-Out $msg "darkcyan" 4
																		$blnFixed = $null
																		$blnFixed = $false
																		$blnFixed = Fix-FSObjectPermissions $targetPath $userDN $strOptionalRootPath
																		$blnFixed = Check-FSObjectACLPermissions $sAMAccountName $targetPath
																		If($blnFixed -eq $false)
																			{
																				$warningMsg = "WARNING`t`tPermissions repair for this object FAILED."
																				Throw-Warning $warningMsg
																				$intNotFixed++
																			}
																		Else
																			{
																				$msg = "INFO`t`tPermissions repair was successful for this object."
																				Write-Out $msg "green" 4
																			}
																		$intFixed++
																	}
															}
													}
												Else
													{}
											}
										Else
											{
												$msg = "INFO`t`tSkipped: """ + $child.fullname + """."
												Write-Out $msg "magenta" 4
											}
									}
								
								#if it's come down to nuking permissions on the whole share; do that.
								If($blnResetAll -eq $true -and $blnCheckOnly -eq $false -and $fail -eq $false)
									{
										#little bit of recursion :)
										$msg = "Action`t`tRebuilding permissions on the entire homedrive."
										Write-Out $msg "darkcyan" 4
										$blnFixed = $null
										$blnFixed = $false
										$blnFixed = Fix-FSObjectPermissions $folderPath $userDN  $strOptionalRootPath
										$blnFixed = CheckAndFix-FolderPermissions $folderPath $sAMAccountName $true
										If($blnFixed -eq $false)
											{
												$warningMsg = "WARNING`t`tPermissions repair for the homedrive FAILED."
												Throw-Warning $warningMsg
												$intNotFixed++
												$fail = $true
											}
										Else
											{
												$msg = "INFO`t`tPermissions repair was successful for the entire homedrive."
												Write-Out $msg "green" 4
											}
										$intFixed++
									}
							}
					}
			}
		
		
		##some reporting
		$msg = "INFO`t`tRepaired """ + $intFixed + """ items."
		Write-Out $msg "darkcyan" 4
		
		If($intNotFixed -eq 0 -and $fail -eq $false)
			{
				$msg = "ACTION`t`tAll permissions finished testing as OK."
				Write-Out $msg "darkcyan" 4
			}
		Else
			{
				$warningMsg = "WARNING`t`tNot all permission problems could be repaired. Count of broken items: """ + $intNotFixed + """."
				Throw-Warning $warningMsg
			}
		
		If($intNotFixed -ge 7)
			{$results = $false}
		Else
			{}
		
		If($fail -eq $true)
			{$results = $false}
		
		return $results
	}

#profileAccessibility

Function Check-ProfilePathExists($objUser) #SkipECC
	{
		$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
		$fileserver = Read-Variable "fileserver-profiles"
		$profilePath = "\\" + $fileserver + "\profiles$\" + $sAMAccountName
		$test = Test-Path $profilePath
		If($test -eq $true)
			{$results = $true}
		Else
			{$results = $false}
		Return $results
	}

Function CheckAndFix-ProfilePathPermissions($objUser)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		
		$profilePath = Pull-LDAPAttribute $objUser "profilePath"
		$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
		$rootPermsPath = Read-Variable "homeDrivesRootPath"
		
		#check permissions on profilePath
		$msg = "ACTION`t`tChecking V1 profile permissions at """ + $profilePath + """."
		Write-Out $msg "darkcyan" 4
		$targetPath = $profilePath
		$blnPermissionsOK = $null
		$blnPermissionsOK = $false
		$blnPermissionsOK = CheckAndFix-FolderPermissions $targetPath $sAMAccountName $null $rootPermsPath
		If($blnPermissionsOK -ne $true)
			{$blnPermissionsOK = $false}
		
		#check permissions on profilePath.V2
		If($blnPermissionsOK -eq $true)
			{
				$msg = "ACTION`t`tTesting for V2 profile."
				Write-Out $msg "darkcyan" 4
				$profilePath2 = $profilePath + ".V2"
				$targetPath = $profilePath2
				If((Test-Path $profilePath2) -eq $true)
					{
						$msg = "INFO`t`tFound a V2 profile at """ + $profilePath2 + """."
						Write-Out $msg "darkcyan" 4
						$msg = "ACTION`t`tChecking V2 profile permissions."
						Write-Out $msg "darkcyan" 4
						$blnPermissionsOK = CheckAndFix-FolderPermissions $targetPath $sAMAccountName $null $rootPermsPath
					}
				Else
					{
						$msg = "INFO`t`tNo V2 profile was found."
						Write-Out $msg "darkcyan" 4
					}
			}
		If($blnPermissionsOK -ne $true)
			{$blnPermissionsOK = $false}
		
		#check permissions on RDP Profile
		If($blnPermissionsOK -eq $true)
			{
				$msg = "ACTION`t`tTesting for RDP profile."
				Write-Out $msg "darkcyan" 4
				$RdpProfilePath = $null
				$RdpProfilePath = $false
				$RdpProfilePath = Pull-TSAttribute $objUser "tsProfilePath"
				
				If($rdpProfilePath -ne $null -and $rdpProfilePath -ne "" -and $rdpProfilePath -ne $false)
					{
						$targetPath = $RdpProfilePath
						If((Test-Path $targetPath) -ne $true)
							{$strAction = Create-Folder $targetPath}								
						$msg = "INFO`t`tFound a V1 RDP profile at """ + $targetPath + """."
						Write-Out $msg "darkcyan" 4
						$msg = "ACTION`t`tChecking RDP profile permissions."
						Write-Out $msg "darkcyan" 4
						$blnPermissionsOK = CheckAndFix-FolderPermissions $targetPath $sAMAccountName
						$targetPath = $RdpProfilePath + ".V2"
						If((Test-Path $targetPath) -ne $true)
							{$strAction = Create-Folder $targetPath}								
						$msg = "INFO`t`tFound a V2 RDP profile at """ + $targetPath + """."
						Write-Out $msg "darkcyan" 4
						$msg = "ACTION`t`tChecking RDP profile permissions."
						Write-Out $msg "darkcyan" 4
						$blnPermissionsOK = CheckAndFix-FolderPermissions $targetPath $sAMAccountName
					}
				Else
					{
						$msg = "INFO`t`tNo RDP profile was found."
						Write-Out $msg "darkcyan" 4
					}
			}
		If($blnPermissionsOK -ne $true)
			{$blnPermissionsOK = $false}
		
		#report
		$results = $blnPermissionsOK
		
		If($results -ne $null)
			{Return $results}
		Else
			{Return $false}
	}

#profileConformity

Function Check-ProfileNotCluttered($objUser)
	{
		$results = $true
		$badFolders = Read-Variable "redirectedProfileFolders"
		$profilePath = Pull-LDAPAttribute $objUser "profilePath"
		If($objUserDN -like "*roaming*")
			{
				Foreach($badFolder in $badFolders)
					{
						$badPath = $profilePath + "\" + $badfolder
						If((Test-Path $badPath) -eq $true)
							{
								$msg = "INFO`t`t`tFound bad folder: """ + $badFolder + """."
								Write-Out $msg "darkcyan" 4
								$results = $false
							}
					}
			}
		Return $results
	}

Function Pull-TSAttribute($objUser,$strAttribute)
	{
		$retval = $null
		Trap{continue;}
		Switch($strAttribute)
			{
				"tsAllowLogin"
					{
						$strCurAllowLogon = $objUser.psbase.invokeget("allowLogon")
						[string]$retval = $strCurAllowLogon
					}
				"tsHomeDrive"
					{
						$strCurTSHomeDrv = $objUser.psbase.invokeget("TerminalServicesHomeDrive")
						[string]$retval = $strCurTSHomeDrv
					}
				"tsHomeDirectory"
					{
						$strCurTSHomePath = $objUser.psbase.invokeget("TerminalServicesHomeDirectory")
						[string]$retval = $strCurTSHomePath
					}
				"tsProfilePath"
					{
						$strCurTSProfilePath = $objUser.psbase.invokeget("TerminalServicesProfilePath")
						[string]$retval = $strCurTSProfilePath
					}
				Default
					{$retval = $null}
			}
		Return $retval
	}

Function Build-TSAttribute($objUser,$strAttribute)
	{
		#build expected attributes
		Switch($strAttribute)
			{
				"tsAllowLogin"
					{
						$strExpectedAllowLogon = 1
						$retval = $strExpectedAllowLogon
					}
				"tsHomeDrive"
					{
						$strHomeDrive = Pull-LDAPAttribute $objUser "homeDrive"
						$retval = $strHomeDrive
					}
				"tsHomeDirectory"
					{
						$strHomeDirectory = Pull-LDAPAttribute $objUser "homeDirectory"
						$retval = $strHomeDirectory
					}
				"tsProfilePath"
					{
						$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
						$RDPProfileRoot = Read-Variable "RDPProfileRoot"
						$RDPProfileRoot = Trim-TrailingSlash $RDPProfileRoot
						$rdpProfilePath = $RDPProfileRoot + "\" + $sAMAccountName
						$retval = $rdpProfilePath
					}
				Default
					{$retval = $null}
			}
		Return $retval
	}

Function Check-TerminalServicesAttributes($objUser)
	{
		$fail = $null
		$fail = $false
		$arrTSAttributes = $null
		$arrTSAttributes = @()
		$arrTSAttributes += "tsAllowLogin"
		$arrTSAttributes += "tsHomeDrive"
		$arrTSAttributes += "tsHomeDirectory"
		$arrTSAttributes += "tsProfilePath"
		
		Foreach ($strCurAttrib in $arrTSAttributes)
			{
				$strReadAttribute = $null
				$strReadAttribute = Pull-TSAttribute $objUser $strCurAttrib
				$strReadAttribute = [System.Convert]::ToString($strReadAttribute)
				$msg = "INFO`t`tRead TS attribute """ + $strCurAttrib + """ as: """ + $strReadAttribute + """."
				Write-Out $msg "darkcyan" 4
				
				$strBuiltAttribute = $null
				$strBuiltAttribute = Build-TSAttribute $objUser $strCurAttrib
				$strBuiltAttribute = [System.Convert]::ToString($strBuiltAttribute)
				$msg = "INFO`t`tCalculated correct TS attribute """ + $strCurAttrib + """ as: """ + $strBuiltAttribute + """."
				Write-Out $msg "darkcyan" 4
				
				If($strReadAttribute -eq $strBuiltAttribute)
					{}
				Else
					{
						$warningMsg = "WARNING`t`tRead TS attribute does not match calculated TS attribute!"
						Throw-Warning $warningMsg
						$fail = $true
					}
		}
		
		#read current attributes
		If($fail -eq $true)
			{$results = $false}
		Else
			{$results = $true}
		Return $results
	}

#ldapAttributes

Function Check-ldapAttribute-scriptPath($objUser)
	{
		$results = $false
		trap{continue;}
		$scriptPath = Pull-LDAPAttribute $objUser "scriptPath"
		$msg = "INFO`t`t`tldapAttribute-scriptPath: """ + $scriptPath	 + """."
		Write-Out $msg "darkcyan" 4
		If($scriptPath -ne $null)
			{$results = $false}
		Else{$results = $true}
		Return $results
	}

Function Check-ldapAttribute-userPrincipalName($objUser) #DONE
	{
		$results = $false
		#trap{continue;}
		$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
		$upn = Pull-LDAPAttribute $objUser "userPrincipalName"
		$domainFull = Read-Variable "domainFull"
		$generatedUpn = $sAMAccountName + "@" + $domainFull
		$generatedUpn = $generatedUpn.ToLower()
		$msg = "INFO`t`t`tgenerated upn: " + $generatedUpn
		Write-Out $msg "darkcyan" 4
		$msg = "INFO`t`t`tldapAttribute-userPrincipalName: """ + $upn	 + """."
		Write-Out $msg "darkcyan" 4
		If($upn -cne $generatedUpn -or $upn -eq $null)
			{$results = $false}
		Else{$results = $true}
		Return $results
	}

Function Check-ldapAttribute-sAMAccountName($objUser) #DONE
	{
		$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
		$msg = "INFO`t`t`tsAMAccountName: " + $sAMAccountName
		Write-Out $msg "darkcyan" 4
		$msg = "INFO`t`t`tChecking if sAMAccountName matches [A-Z]+"
		Write-Out $msg "darkcyan" 4
		If($sAMAccountName -cmatch "[A-Z]")
			{$results = $false}
		Else
			{$results = $true}
		Return $results
	}

Function Check-ldapAttribute-GIDNumber($objUser)
	{
		$gidNumber = $null
		$gidNumber = Pull-LDAPAttribute $objUser "gidNumber"
		$msg = "Info`t`t`tRead gidNumber: """ + $gidNumber + """ ."
		Write-Out $msg "darkcyan" 4
		If($gidNumber -eq $null -or $gidNumber -eq "" -or $gidNumber -eq $false)
			{
				$msg = "Warning`t`tThis user has a uidNumber but no gidNumber!"
				Throw-Warning $msg
			}
		Return $true
	}

Function Check-ldapAttribute-mssfu30nisdomain($objUser)
	{
		$results = $null
		$results = $false
		$domainShort = $null
		$domainShort = Read-Variable "domainShort"
		$msg = "Info`t`t`tRead domain name: """ + $domainShort + """."
		Write-Out $msg "darkcyan" 4
		$mssdomain = $null
		$mssdomain = Pull-LDAPAttribute $objUser "mssfu30nisdomain"
		$msg = "Info`t`t`tRead mssfu30nisdomain value: """ + $mssdomain + """."
		Write-Out $msg "darkcyan" 4
		If($mssdomain -ne $domainShort)
			{$results = $false}
		Else
			{$results = $true}
		Return $results
	}

Function Check-ldapAttribute-proxyAddresses($objUser)
	{
		$results = $null
		$results = $true
		
		#only add missing proxyAddresses, don't delete current ones that might have been added or tweaked manually
		$proxyAddresses = $null
		$proxyAddresses = Pull-LDAPAttribute $objUser "proxyAddresses"
		If($proxyAddresses -eq $null -or $proxyAddresses -eq $false)
			{
				$results = $false
				$msg = "Warning`t`t`tUser has no proxyAddresses atribute."
				Throw-Warning $msg
			}
		Else
			{
				$GeneratedProxyAddresses = $null
				$GeneratedProxyAddresses = @()
				
				$suffixes = Read-Variable "proxyAddressSuffixes"
				Foreach($suffix in $suffixes)
					{
						$GeneratedProxyAddress = ("SMTP:" + $sAMAccountName + $suffix)
						$msg = "Action`t`t`tChecking for proxy address: """ + $generatedProxyAddress + """."
						Write-Out $msg "darkcyan" 4
						If($proxyAddresses -contains $GeneratedProxyAddress)
							{}
						Else
							{
								$msg = "Warning`t`t`tUser is missing the following proxyAddress: """ + $GeneratedProxyAddress + """."
								Throw-Warning $msg
								$results = $false
							}
					}
			}
		
		Return $results
	}

Function Check-ldapAttribute-unixhomedirectory($objUser)
	{
		$results = $null
		$results = $false
		$sAMAccountName = $null
		$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
		$generatedHomeDirectory = $null
		$generatedHomeDirectory = "/export/home/" + $sAMAccountName
		$msg = "Info`t`t`tGenerated unixHomeDirectory value: """ + $generatedHomeDirectory + """."
		Write-Out $msg "darkcyan" 4
		$unixHomeDirectory = $null
		$unixHomeDirectory = Pull-LDAPAttribute $objUser "unixHomeDirectory"
		$msg = "Info`t`t`tRead unixHomeDirectory value: """ + $unixHomeDirectory + """."
		Write-Out $msg "darkcyan" 4
		If($unixHomeDirectory -eq $generatedHomeDirectory)
			{}
		Else
			{
				$msg = "Warning`t`tThis user's unixHomeDirectory doesn't match the template!"
				Throw-Warning $msg
				$results = $false
			}
			
		Return $true
	}

Function Check-AccountIsArchived($objUser)
	{
		$strUserDN = $null
		$strUserDN = Pull-LDAPAttribute $objUser "distinguishedName"
		
		$blnArchived = $null
		$blnArchived = $false
		
		$arrArchivalGroups = $null
		$arrArchivalGroups = Find-ArchivalGroups
		$arrArchivalGroups | % {
			$groupCN = $null
			$groupCN = $_
			$groupDN = $null
			$groupDN = Get-DNbyCN $groupCN
			$blnGroupCheck = $null
			$blnGroupCheck = Check-IsMemberOfGroup $strUserDN $groupDN
			If($blnGroupCheck -eq $true)
				{$blnArchived = $true}
		}
		
		Return $blnArchived
	}

Function Check-AccountNeedsReactivated($objUser)
	{
		#if member of current class group and archived group, then return false.
		$blnCurrentClassGroup = $null
		$blnCurrentClassGroup = $false
		$blnCurrentClassGroup = Check-IsMemberOfCurrentClassGroup $objUser
		If($blnCurrentClassGroup -eq $true)
			{$msg = "INFO`t`t`tUser is a member of a current class group."}
		Else
			{$msg = "INFO`t`t`tUser is -not- a member of a current class group."}
		Write-Out $msg "darkcyan" 4
		
		$blnArchived = $null
		$blnArchived = $false
		$blnArchived = Check-AccountIsArchived $objUser
		If($blnArchived -eq $true)
			{$msg = "INFO`t`t`tUser is archived!"}
		Else
			{$msg = "INFO`t`t`tUser is -not- archived."}
		Write-Out $msg "darkcyan" 4
		
		
		$retval = $null
		$retval = $true
		If($blnCurrentClassGroup -eq $true -and $blnArchived -eq $true)
			{
				$msg = "WARNING`t`tThis user needs to be reanimated."
				Throw-Warning $msg
				$retval = $false
			}
		Else
			{$retval = $true}
		
		Return $retval
	}

Function Find-ArchivalGroups
	{
		$DenyLoginsGroupCN = Read-Variable "DenyLoginsGroupCN"
		$ReadyForWindowsArchiveGroupCN = Read-Variable "ReadyForWindowsArchiveGroupCN"
		$ReadyForLinuxArchiveGroupCN = Read-Variable "ReadyForLinuxArchiveGroupCN"
		$WindowsArchiveDoneGroupCN = Read-Variable "WindowsArchiveDoneGroupCN"
		$LinuxArchiveDoneGroupCN = Read-Variable "LinuxArchiveDoneGroupCN"
		$deletionGroupCN = Read-Variable "deletionGroupCN"
		
		$arrArchivalGroups = $null
		$arrArchivalGroups = @()
		$arrArchivalGroups += $DenyLoginsGroupCN
		$arrArchivalGroups += $ReadyForWindowsArchiveGroupCN
		$arrArchivalGroups += $ReadyForLinuxArchiveGroupCN
		$arrArchivalGroups += $WindowsArchiveDoneGroupCN
		$arrArchivalGroups += $LinuxArchiveDoneGroupCN
		$arrArchivalGroups += $deletionGroupCN
		
		Return $arrArchivalGroups
	}

Function Reanimate-User($objUser)
	{
		$fail = $null
		$fail = $false
		
		#We don't need to do anything about archived data; the rebuild-homefolders action will take care of that later.
		#All we need to do is pull the user out of any archival groups!
		
		$msg = "Action`t`tRemoving the user from archival groups."
		Write-Out $msg "white" 2
		
		$userDN = $null
		$userDN = Pull-LDAPAttribute $objUser "distinguishedName"
		
		$arrArchivalGroups = $null
		$arrArchivalGroups = Find-ArchivalGroups
		
		$arrArchivalGroups | % {
			$groupCN = $null
			$groupCN = $_
			$groupDN = $null
			$groupDN = Get-DNbyCN $groupCN
			
			$blnAction = $null
			$blnAction = Remove-FromGroup $userDN $groupDN
			$blnAction = $null
		}
		
		$blnRemoved = $null
		$arrArchivalGroups | % {
			$groupCN = $null
			$groupCN = $_
			$groupDN = $null
			$groupDN = Get-DNbyCN $groupCN
			
			$blnRemoved = Check-IsMemberOfGroup $userDN $groupDN
			If($blnRemoved -eq $true)
				{
					$msg = "Warning`t`tCould not remove user from the group """ + $groupCN + """."
					Throw-Warning $msg
				}		
		}
	}

Function Fix-AccountNeedsReactivated($objUser)
	{
		$blnFixed = $null
		$blnFixed = Reanimate-User $objUser
	}

Function Check-AccountIsNotArchived($objUser)
	{
		$results = $null
		
		$userDN = $null
		$userDN = Pull-LdapAttribute $objUser "distinguishedName"
		$groupCN = $null
		$groupCN = Read-Variable "ArchivedUsersGroupCN"
		$groupDN = $null
		$groupDN = Get-DNbyCN $groupCN "group"
		$objGroup = $null
		$objGroup = [adsi]("LDAP://" + $groupDN)
		
		$msg = "ACTION`t`t`tChecking if user is a member of the group """ + $groupCN + """."
		Write-Out $msg "darkcyan" 4
		$blnMemberOfGroup = $null
		$blnMemberOfGroup = Check-IsMemberOfGroup $userDN $groupDN
		If($blnMemberOfGroup -eq $true)
			{$results = $false}
		Else
			{$results = $true}
		
		$msg = "ACTION`t`t`tresults: """ + $blnMemberOfGroup + """."
		Write-Out $msg "darkcyan" 4
		
		Return $results
	}


#groupMemberships

Function Check-GroupMembership-ClassAccounts($objUser)
	{
		#this is not a good check.
		#what does it do? If you are in a class, put you in class accounts
		#if you are not in a class, remove you from class accounts
		#if you are in class accounts, and no RES_Diskquota groups, put you in RES_Diskquota_Classes
		
		#is the user a member of the "class accounts" role group?
		$classAccountsCN = $null
		$classAccountsCN = Read-Variable "classAccountsCN"
		$classAccountsDN = $null
		$classAccountsDN = Get-DNbyCN $classAccountsCN
		$strUserDN = $null
		$strUserDN = Pull-LDAPAttribute $objUser "distinguishedName"
		$blnMemberOfClassAccounts = $null
		$blnMemberOfClassAccounts = $false
		$blnMemberOfClassAccounts = Check-IsMemberOfGroup $strUserDN $classAccountsDN
		$msg = "INFO`t`t`tMember of class accounts quota group: " + $blnMemberOfClassAccounts
		Write-Out $msg "darkcyan" 4
		
		#is the user a member of any actual class groups?
		$blnMemberOfClassGroup = $null
		$blnMemberOfClassGroup = $false
		$blnMemberOfClassGroup = Check-GroupMembership-anyClassGroup $objUser
		$msg = "INFO`t`t`tMember of any class groups: " + $blnMemberOfClassGroup
		Write-Out $msg "darkcyan" 4
		If($blnMemberOfClassAccounts -eq $blnMemberOfClassGroup)
			{$results = $true}
		Else
			{$results = $false}
		
		Return $results
	}

Function Check-OnlyQuotaGroupIsClassAccounts($objUser)
	{
		$results = $null
		$results = $true
		$quotaGroupsCN = Read-Variable "quotaGroupsCN"
		$objQuotaGroupsDN = $null
		$objQuotaGroupsDN = Get-DNbyCN $quotaGroupsCN
		$objQuotaGroups = $null
		$objQuotaGroups = [adsi]("LDAP://" + $objQuotaGroupsDN)
		$objQuotaGroupsMembers = $null
		$objQuotaGroupsMembers = $objQuotaGroups.member
		
		$objUserDN = $null
		$objUserDN = Pull-LdapAttribute $objUser "distinguishedName"
		$strClassAccountsQuotaGroupCN = $null
		$strClassAccountsQuotaGroupCN = Read-Variable "classAccountsQuotaGroupCN"
		$strClassAccountsQuotaGroupDN = $null
		$strClassAccountsQuotaGroupDN = Get-DNbyCN $strClassAccountsQuotaGroupCN "group"
		
		$classAccountsCN = $null
		$classAccountsCN = Read-Variable "classAccountsGroupCN"
		$classAccountsDN = $null
		$classAccountsDN = Get-DNbyCN $classAccountsCN
		
		#first, make sure we're a member of the class accounts group
		$blnClassAccountsCheck = $null
		$blnClassAccountsCheck = Check-IsMemberOfGroup $objUserDN $strClassAccountsQuotaGroupDN
		If($blnClassAccountsCheck -eq $false)
			{$results = $false}
		Else
			{
				$quotaGroupDN = $null
				Foreach($quotaGroupDN in $objQuotaGroupsMembers)
					{
						If($quotaGroupDN -ne $strClassAccountsQuotaGroupDN -and $quotaGroupDN -ne $classAccountsDN)
							{
								$groupCheck = $null
								$groupCheck = Check-IsMemberOfGroup $objUserDN $quotaGroupDN
								If($groupCheck -eq $true)
									{
										$results = $false
										Break
									}
							}
					}
			}
		
		Return $results
	}

Function Check-GroupMembership-QuotaGroup($objUser) #SkipECC
	{
		$failThisFunction = $null
		$failThisFunction = $false
		$results = $null
		$results = $false
		
		$strUserDN = $null
		$strUserDN = Pull-LdapAttribute $objUser "distinguishedName"
		
		#look through the user's groups
		#is group like RES_Diskquota?
		#does old groups contains group? -> does groups contain corresponding new one?
		
		$hshOldToNewMapping = $null
		$hshOldToNewMapping = Read-Variable "hshOldQuotaGroupMappings"
		$arrOldQuotaGroupsCNs = $null
		$arrOldQuotaGroupsCNs = $hshOldToNewMapping.Keys
		
		$newQuotaGroupsCN = $null
		$newQuotaGroupsCN = Read-Variable "transitionalQuotaGroupsCN"
		$newQuotaGroupsDN = $null
		$newQuotaGroupsDN = Get-DNbyCN $newQuotaGroupsCN
		$objNewQuotaGroups = [adsi]("LDAP://" + $newQuotaGroupsDN)
		$objQuotaGroupsMembers = Pull-LDAPAttribute $objNewQuotaGroups "member"
		$arrNewQuotaGroupsDNs = $null
		$arrNewQuotaGroupsDNs = $objQuotaGroupsMembers

		###in case I actually needed CN's
#		$arrNewQuotaGroups = $objQuotaGroupsMembers | %{
#				$objGroup = $null;
#				$objGroup = [adsi]("LDAP://$_");
#				Pull-LDAPAttribute $objGroup "cn";
#			}
		
		$blnFoundAQuotaGroup = $null
		$blnFoundAQuotaGroup = $false
		
		###check old\new mappings.
		$msg = "Action`t`tLooking for membership in old quota groups."
		Write-Out $msg "darkcyan" 4
		Foreach($strOldGroupCN in $arrOldQuotaGroupsCNs)
			{
				#write-host -f yellow "debug`tstrOldGroupCN: $strOldGroupCN"
				$strOldGroupDN = $null
				$strOldGroupDN = Get-DNbyCN $strOldGroupCN
				$blnMember = $null
				$blnMember = $false
				$blnMember = Check-IsMemberOfGroup $strUserDN $strOldGroupDN
				If($blnMember -eq $true)
					{
						$msg = "Info`t`tUser is a member of the old quota group """ + $strOldGroupCN + """."
						Write-Out $msg "darkcyan" 4
						$strNewQuotaGroupCN = $null
						$strNewQuotaGroupCN = $hshOldToNewMapping.Get_Item($strOldGroupCN)
						$msg = "Action`t`tChecking for the corresponding new quota group """ + $strNewQuotaGroupCN + """."
						Write-Out $msg "darkcyan" 4
						$strNewQuotaGroupDN = $null
						$strNewQuotaGroupDN = Get-DNbyCN $strNewQuotaGroupCN
						$blnMember2 = $null
						$blnMember2 = $false
						$blnMember2 = Check-IsMemberOfGroup $strUserDN $strNewQuotaGroupDN
						If($blnMember2 -eq $true)
							{
								$msg = "Info`t`tUser is a member of the corresponding new group."
								Write-Out $msg "darkcyan" 4
								$blnFoundAQuotaGroup = $true
							}
						Else
							{
								$msg = "Warning`t`tUser is -not- a member of the corresponding new group."
								Throw-Warning $msg
								$failThisFunction = $true
								$results = $false
								Break
							}
					}
			}
		
		#check for any quota groups
		If($blnFoundAQuotaGroup -eq $false -and $failThisFunction -eq $false)
			{
				$msg = "ACTION`t`tChecking if the user is a member of any new (current) quota groups."
				Write-Out $msg "darkcyan" 4
				Foreach($quotaGroupDN in $arrNewQuotaGroupsDNs)
					{
						$blnMember = $null
						$blnMember = $false
						$blnMember = Check-IsMemberOfGroup $strUserDN $quotaGroupDN
						If($blnMember -eq $true)
							{
								$objGroup = [adsi]("LDAP://" + $quotaGroupDN)
								$objGroupCN = Pull-ldapAttribute $objGroup "CN"
								$msg = "INFO`t`t`tFound membership of at least one quota group: """ + $objGroupCN + """."
								Write-Out $msg "darkcyan" 4				
								$blnFoundAQuotaGroup = $true
								Break
							}
						Else
							{}
					}
				If($blnFoundAQuotaGroup -eq $false)
					{
						$msg = "Warning`t`tThe user is not a member of any new (current) quota groups."
						Throw-Warning $msg
						$failThisFunction = $true
					}
			}
		
		If($blnFoundAQuotaGroup -eq $true -and $failThisFunction -eq $false)
			{$results = $true}
		Else
			{$results = $false}
		
		Return $results
	}

Function Check-GroupMembership-RoleGroup($objUser) #SkipECC
	{
		$groups = $objUser.Memberof
		$quotaGroupsCN = Read-Variable "quotaGroupsCN"
		$objQuotaGroupsDN = Get-DNbyCN $quotaGroupsCN "group"
		$objQuotaGroups = [adsi]("LDAP://" + $objQuotaGroupsDN)
		$objQuotaGroupsMembers = $objQuotaGroups.member
		
		$results = $false
		Foreach($groupDN in $groups)
			{
				If($results -eq $false)
					{
						If($objQuotaGroupsMembers -contains $groupDN)
							{}
						Else
							{
								$msg = "INFO`t`t`tFound role group: """ + $groupDN + """."
								Write-Out $msg "darkcyan" 4
								$results = $true
							}
					}
			}
		
		Return $results
	}

Function Check-GroupMembership-RES_PrintingGroups($objUser)
	{
		$results = $null
		$results = $true
		
		$intRESPrintingCount = $null
		$intRESPrintingCount = 0
		$arrGroupDNs = Pull-LDAPAttribute $objUser "memberof"
		Foreach($arrGroupDN in $arrGroupDNs)
			{
				If($arrGroupDN -like "*RES_Printing*")
					{
						$objGroup = $null
						$objGroup = [adsi]("LDAP://" + $arrGroupDN)
						$groupCN = $null
						$groupCN = Pull-LDAPAttribute $objGroup "CN"
						$objGroup = $null
						$msg = "Info`t`tFound RES_Printing group: """ + $groupCN + """."
						Write-Out $msg "darkcyan" 4
						$groupCN = $null
						$intRESPrintingCount++
					}
			}
		
		If($intRESPrintingCount -eq 0)
			{
				$msg = "Warning`t`tThis user is not a member of an RES_Printing group. They cannot access \\metered-printers!"
				Throw-Warning $msg
			}
		ElseIf($intRESPrintingCount -gt 1)
			{
				$msg = "Error`t`tThe user is a member of more than one RES_Printing group."
				Throw-Warning $msg
				$msg = "Info`t`tThis user effectively has free printing."
				Throw-Warning $msg
				$results = $false
			}
		
		Return $results
	}

Function Check-GroupMembership-ClassAccountsQuotaGroup($objUser) #SkipECC
	{
		$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
		$objUserDN = Get-DNbySAMAccountName $sAMAccountName "user"
		$results = $false
		
		$classAccountsQuotaGroupCN = Read-Variable "classAccountsQuotaGroupCN"
		$ClassAccountsQuotaGroupDN = Get-DNbyCN $classAccountsQuotaGroupCN "group"
		$groupCheck = Check-IsMemberOfGroup $objUserDN $ClassAccountsQuotaGroupDN
		If($groupCheck -eq $true)
			{$results = $true}
		Else
			{}
		
		$classAccountsQuotaGroupCN = Read-Variable "classAccountsQuotaGroupCN2"
		$ClassAccountsQuotaGroupDN = Get-DNbyCN $classAccountsQuotaGroupCN "group"
		$groupCheck = Check-IsMemberOfGroup $objUserDN $ClassAccountsQuotaGroupDN
		If($groupCheck -eq $true)
			{$results = $true}
		Else
			{}
		
		Return $results
	}

Function Check-GroupMembership-AnyClassGroup($objUser) #SkipECC
	{
		
		$arrUserMemberOf = $null
		$arrUserMemberOf = Pull-LDAPAttribute $objUser "memberOf"
		
		$strClassesPrefix = $null
		$strClassesPrefix = Read-Variable "classGroupPrefix"
		
		$blnMemberOfClassGroup = $null
		$blnMemberOfClassGroup = $false
		Foreach($groupDN in $arrUserMemberOf)
			{
				If($groupDN -like ("CN=" + $strClassesPrefix + "*"))
					{
						$blnMemberOfClassGroup = $true
					}
			}
		
		$results = $blnMemberOfClassGroup
		Return $results
	}

Function Check-PrimaryGroupCorrect($objUser)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		
		$intendedPGID = $null
		$intendedPGID = 513
		
		$primaryGroupID = $null
		$primaryGroupID = Pull-LdapAttribute $objUser "primaryGroupID"
		$msg = "INFO`t`t`tPrimary Group ID read as """ + $primaryGroupID + """."
		Write-Out $msg "darkcyan" 4
		$msg = "INFO`t`t`tNote: Primary Group ID should be """ + $intendedPGID + """."
		Write-Out $msg "darkcyan" 4
		If($primaryGroupID -eq $false -or $primaryGroupID -eq $null)
			{$failThisFunction = $true}
		ElseIf($primaryGroupID -eq $intendedPGID)
			{}
		Else
			{$failThisFunction = $true}
		
		If($failThisFunction -eq $false)
			{$results = $true}
		Else
			{$results = $false}
		Return $results
	}


### Account Fixes



#basicAccountHealth

Function Fix-OUisOK($objUser)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		$results = $null
		$results = $false
		
		$strOUMode = $null
		
		#if all accounts are roaming, skip the filesystem OU
		$blnSkipFilesystemOU = $null
		$blnSkipFilesystemOU = $false
		$blnAllAccountsAreRoaming = $null
		$blnAllAccountsAreRoaming = $false
		$blnAllAccountsAreRoaming = Read-Variable "AllAccountsAreRoaming"
		If($blnblnAllAccountsAreRoaming -eq $true)
			{
				$msg = "Info`t`t`tAll accounts are roaming, skipping filesystem OU checks."
				Write-Out $msg "darkcyan" 4
				$blnSkipFilesystemOU = $true
				$strOUMode = "roaming"
			}
		Else
			{
				$msg = "Info`t`t`tAll accounts are -not- roaming, continuing filesystem OU checks."
				Write-Out $msg "darkcyan" 4
				$blnSkipFilesystemOU = $false
			}
		
		#find the user's filesystem OU
		If($blnSkipFilesystemOU -eq $false)
			{
				$strFileSystemOUCN = $null
				$blnFileSystemOUFound = $null
				$blnFileSystemOUFound = $false
				
				#check for web-only
				$blnWebOnly = $null
				$blnWebOnly = $false
				$blnWebOnly = Check-IsUserWebOnly $objUser
				If($blnWebOnly -eq $true)
					{
						$msg = "Info`t`t`tThis user is Web-Only."
						Write-Out $msg "darkcyan" 4
						$strOUMode = "web"
						$blnFileSystemOUFound = $true
					}
				Else
					{
						$msg = "Info`t`t`tThis user is -not- Web-Only."
						Write-Out $msg "darkcyan" 4
					}
				
				If($blnFileSystemOUFound -eq $false)
					{
						#check for roaming
						$blnRoaming = $null
						$blnRoaming = $false
						$blnRoaming = Check-IsUserRoaming $objUser
						If($blnRoaming -eq $true)
							{
								$msg = "Info`t`t`tThis user has a roaming profile."
								Write-Out $msg "darkcyan" 4
								$strOUMode = "roaming"
								$blnFileSystemOUFound = $true
							}
						Else
							{
								$msg = "Info`t`t`tThis user does -not- have a roaming profile."
								Write-Out $msg "darkcyan" 4
							}
					}
				
				#default to redirected
				If($blnFileSystemOUFound -eq $false)
					{
						$strOUMode = "redirected"
					}
			}
		
			#check class-only users are in "class-only" OU	
			$blnClassOnly = $null
			$blnClassOnly = $false
			$blnClassOnly = Check-IsUserClassOnly $objUser
			If($blnClassOnly -eq $true)
				{
					$msg = "Info`t`t`tThis user has a Class-Only account."
					Write-Out $msg "darkcyan" 4
					$blnAllClassAccountsRoaming = $null
					$blnAllClassAccountsRoaming = Read-Variable "allClassAccountsAreRoaming"
					If($blnAllClassAccountsRoaming -eq $true)
						{
							$strOUMode = "roaming-classes"
						}
					Else
						{$strOUMode += "-classes"}
				}
			Else
				{
					$msg = "Info`t`t`tThis user does -not- have a Class-Only account."
					Write-Out $msg "darkcyan" 4
				}
		
		#put all the pieces together
		$msg = "Action`t`t`tPicking the following type of OU: """ + $strOUMode + """."
		Write-Out $msg "darkcyan" 4
		$strUserCN = Pull-LDAPAttribute $objUser "cn"
		$strTargetOU = $null
		$strTargetOU = Pick-OU $strOUMode $strUserCN
		If($strTargetOU -eq $false -or $strTargetOU -eq $null -or $strTargetOU -eq "")
			{
				$msg = "Error`tCould not pick a target OU for this user."
				Throw-Warning $msg
				$failThisFunction = $true
			}
		Else
			{
				$msg = "Info`t`t`tTarget OU picked: """ + $strTargetOU + """."
				Write-Out $msg "darkcyan" 4
			}
		
		#move the user
		$results = $null
		If($failThisFunction -eq $false)
			{
				$msg = "ACTION`t`tMoving this user to the following OU """ + $strTargetOU + """."
				Write-Out $msg "darkcyan" 4
				$results = Move-UserToOU $objUser $strTargetOU
				If($results -eq $null)
					{$results = $false}
			}
		
		#make sure to rerun some tests if necessary
		#REF: http://www.powershellcommunity.org/Forums/tabid/54/aff/1/aft/3993/afv/topic/Default.aspx
		$arrTestsToSkip = $script:arrTestsToSkip
		$newGlobalArrTestToSkip = @($arrTestsToSkip | Where-Object {@('ldapAttribute-ProfilePath','profilePathExists') -notcontains $_})
		$script:arrTestsToSkip = $newGlobalArrTestToSkip
		
		Return $results
	}

Function Fix-AccountIsNotArchived($objUser)
	{
		$warningMsg = "ERROR`t`tAccount is a member of the ""Archived Accounts"" group."
		Throw-Warning $warningMsg
		$warningMsg = "ERROR`t`tThis script will not test or modify accounts in this group."
		Throw-Warning $warningMsg
		Return $false
	}

Function Fix-AccountIsEnabled($objUser)
	{
		#write a log message
		$loopTimeExceeded = $false
		$loopRetriesExceeded = $false
		$passwordTooWeak = $false
		$userDNE = $false
		$loopRetries = 0
		$loopRetry = $true
		$loopStartTime = Get-Date
		$error.clear()
		
		$msg = "ACTION`t`t`tEnabling account."
		Write-Out $msg "darkcyan" 4
		
		#configure the trap
		trap
			{
				#log error
				$warningMsgs = $null
				$warningMsgs = @()
				$warningMsgs += "ERROR`tPowerShell threw an exception."
				$warningMsgs += "ERROR`t`tThis probably means that the user has a blank or weak password."
				$warningMsgs += "ERROR`t`tMore info should follow this line."
				Foreach($warningMsg in $warningMsgs)
					{Throw-Warning $warningMsg}
				Foreach($errorLine in $error)
					{
						$warningMsg = "ERROR`t`t" + $errorLine
						Throw-Warning $warningMsg
					}
				
#				###HACK FOR MASS MIGRATION
#				#Set-Password
#				$password = <redacted>
#				$objUser.SetPassword($password)
#				$objUser.SetInfo()
#				$objUser.pwdLastSet = 0
#				$objUser.SetInfo()
#				$objUser = $null
				continue;
			}
		
		#attempt to enable the account
		while($loopRetry -eq $true)
			{
				$userUAC = $null
				$userUAC = Pull-LDAPAttribute $objUser "userAccountControl"
				
				#clear the error log
				$error.clear()
				
				#quick info gathering
				$loopRetries++
				$curTime = Get-Date
				$loopSeconds = ($curTime - $loopStartTime).TotalSeconds
				
				#check loop conditions
				If($loopRetries -gt 500){$loopRetry = $false}
				If($loopSeconds -gt 10){$loopRetry = $false}
				
				#attempt to enable account
				$objUser.Put("userAccountControl",512)
				$objUser.SetInfo()
				
				#test success
				If(($userUAC -band 2) -eq 0)
					{$loopRetry = $false}
			}
		
		#finishing up
		$userUAC = $null
		$userUAC = Pull-LDAPAttribute $objUser "userAccountControl"
		If(($userUAC -band 2) -eq 0)
			{$results = $true}
		Else
			{$results = $false}
		
		Return $results
	}

Function Fix-groupMembership-ClassAccounts($objUser)
	{
		$failFunction = $null
		$failFunction = $false
		$results = $null
		$results = $false
		
		#is the user a member of the "class accounts" role group?
		$classAccountsCN = $null
		$classAccountsCN = Read-Variable "classAccountsCN"
		$classAccountsDN = $null
		$classAccountsDN = Get-DNbyCN $classAccountsCN
		$strUserDN = $null
		$strUserDN = Pull-LDAPAttribute $objUser "distinguishedName"
		$blnMemberOfClassAccounts = $null
		$blnMemberOfClassAccounts = $false
		$blnMemberOfClassAccounts = Check-IsMemberOfGroup $strUserDN $classAccountsDN
		$msg = "INFO`t`t`tMember of class accounts quota group: " + $blnMemberOfClassAccounts
		Write-Out $msg "darkcyan" 4
		
		#is the user a member of any actual class groups?
		$blnMemberOfClassGroup = $null
		$blnMemberOfClassGroup = $false
		$blnMemberOfClassGroup = Check-GroupMembership-anyClassGroup $objUser
		$msg = "INFO`t`t`tMember of any class groups: " + $blnMemberOfClassGroup
		Write-Out $msg "darkcyan" 4
		
		If($blnMemberOfClassAccounts -eq $true -and $blnMemberOfClassGroup -eq $false)
			{
				$results = Remove-FromGroup $strUserDN $classAccountsDN
				
				$strDiskQuotaGroupPrefix = $null
				$strDiskQuotaGroupPrefix = Read-Variable "diskQuotaCNPrefix"
				$strClassAccountsQuotaGroupCN = $null
				$strClassAccountsQuotaGroupCN = Read-Variable "classAccountsQuotaGroupCN"
				$strClassAccountsQuotaGroupDN = $null
				$strClassAccountsQuotaGroupDN = Get-DNbyCN $strClassAccountsQuotaGroupCN
				
				#if RES_DiskQuota_Classes is there but not the only RES group, remove it.
				$msg = "Action`t`t`tChecking to see if the user is a member of the " + $strClassAccountsQuotaGroupCN + " disk quota group."
				Write-Out $msg "darkcyan" 4
				$groups = Pull-LDAPAttribute $objUser "memberOf"
				If($groups -contains $strClassAccountsQuotaGroupDN)
					{
						$msg = "Info`t`t`tThe user is a member of the " + $strClassAccountsQuotaGroupCN + " quota group."
						Write-Out $msg "darkcyan" 4
						$msg = "Action`t`t`tChecking to see if the user is a member of other quota groups."
						Write-Out $msg "darkcyan" 4
						Foreach($group in $groups)
							{
								If($group -like ("*" + $strDiskQuotaGroupPrefix + "*") -and $group -ne $strClassAccountsQuotaGroupDN)
									{
										$msg = "Info`t`t`tFound the quota group """ + $group + """."
										Write-Out $msg "darkcyan" 4
										$msg = "Info`t`t`tThe user is a member of multiple quota groups."
										Write-Out $msg "darkcyan" 4
										$msg = "Action`t`t`tRemoving user from the " + $strClassAccountsQuotaGroupCN + " Quota Group."
										Write-Out $msg "darkcyan" 4
										$results = Remove-FromGroup $strUserDN $strClassAccountsQuotaGroupDN
										Break
									}
							}
					}
			}
		ElseIf($blnMemberOfClassAccounts -eq $false -and $blnMemberOfClassGroup -eq $true)
			{
				$results = Add-ToGroup $strUserDN $classAccountsDN
			}
		
		If($failFunction -eq $true)
			{$results = $false}
		Else
			{}
		Return $results
	}


Function Fix-ldapAttribute-userAccountControl($objUser)
	{
		$UAC = Pull-LDAPAttribute $objUser "userAccountControl"
		$flags = Get-UACFlags $UAC
		$badFlags = Read-Variable "badUACflags"
		Foreach($flag in $flags)
			{
				If($badFlags -contains $flag)
					{
						$msg = "ACTION`t`t`tRemoving the flag """ + $flag + """."
						Write-Out $msg "darkcyan" 4
						$intFlag = Get-UACFlagInt $flag
						$UAC = $UAC - $intFlag
						
					}
			}
			
		$objUser.Put("userAccountControl",$UAC)
		$objUser.SetInfo()
	}

Function Fix-ldapAttribute-accountExpires($objUser) #DONE
	{
		$failFunction = $null
		$blnAccountExpires = $null
		$blnAccountShouldExpire = $null
		$expectedExpirationDate = $null
		$expirationDate = $null
		$sAMAccountName = $null
		$results = $false
		
		#
		
		#$msg = "ACTION`t`t`tChecking if this account should be expired."
		#Write-Out $msg "darkcyan" 4
		$blnAccountShouldBeExpired = Check-AccountShouldBeExpired $objUser
		#$msg = "INFO`t`t`tAccount should be expired: " + $blnAccountShouldBeExpired + "."
		#Write-Out $msg "darkcyan" 4
		
		#$msg = "ACTION`t`t`tChecking if this account should expire."
		#Write-Out $msg "darkcyan" 4
		$blnAccountShouldExpire = Check-AccountShouldExpire $objUser
		#$msg = "INFO`t`t`tAccount should expire: " + $blnAccountShouldExpire + "."
		#Write-Out $msg "darkcyan" 4
		
		#$msg = "ACTION`t`t`tChecking if this account _is_ expired."
		#Write-Out $msg "darkcyan" 4
		$blnAccountIsExpired = Check-AccountIsExpired $objUser
		#$msg = "INFO`t`t`tAccount is expired: " + $blnAccountIsExpired + "."
		#Write-Out $msg "darkcyan" 4
		
		#$msg = "ACTION`t`t`tChecking if this account does expire."
		#Write-Out $msg "darkcyan" 4
		$blnAccountExpires = Check-AccountExpires $objUser
		#$msg = "INFO`t`t`tAccount expires: " + $blnAccountExpires + "."
		#Write-Out $msg "darkcyan" 4
		
		If($blnAccountShouldBeExpired)
			{
				If($blnAccountIsExpired)
					{$results = $true}
				Else
					{
						$msg = "ACTION`t`t`tExpiring the account."
						Write-Out $msg "darkcyan" 4
						$today = Get-Date
						$yesterday = $today.AddDays(-1)
						Set-AccountExpirationDate $objUser $yesterday
					}
			}
		Else
			{
				#If the account should eventually someday expire
				If($blnAccountShouldExpire)
					{
						$expirationDate = Find-ExpirationDate $objUser
						#$msg = "INFO`t`t`tRead expiration date: " + $expirationDate + "."
						#Write-Out $msg "darkcyan" 4
						$expectedExpirationDate = Find-ExpectedExpirationDate $objUser
						#$msg = "INFO`t`t`tExpected Expiration Date: " + $expectedExpirationDate + "."
						#Write-Out $msg "darkcyan" 4
						
						If($blnAccountExpires)
							{
								If($expectedExpirationDate -ne $expirationDate)
									{
										$msg = "ACTION`t`t`tSetting expiration date to: """ + $expectedExpirationDate + """."
										Write-Out $msg "darkcyan" 4
										Set-AccountExpirationDate $objUser $expectedExpirationDate
									}
								Else
									{$results = $true}
							}
						Else
							{
								$msg = "ACTION`t`t`tSetting expiration date to: """ + $expectedExpirationDate + """."
								Write-Out $msg "darkcyan" 4
								Set-AccountExpirationDate $objUser $expectedExpirationDate
							}
							
					}
				Else
					{
						#If the account should never expire
						If($blnAccountExpires)
							{
								$msg = "ACTION`t`t`tClearing expiration date."
								Write-Out $msg "darkcyan" 4
								Set-AccountExpirationDate $objUser $null
							}
						Else
							{$results = $true}
					}
			}
		
		#Return $results
	}

Function Fix-MalformedProfilePath($objUser)
	{
		$objUser.PutEx(1,"profilePath",0)
		$objUser.SetInfo()
	}

Function Fix-ldapAttribute-profilePath($objUser)
	{
		$objUserDN = Pull-LDAPAttribute $objUser "distinguishedName"
		If($objUserDN -like "*roaming*")
			{
				$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
				$fileserver = Read-Variable "fileserver-profiles"
				$profilePath = "\\" + $fileserver + "\profiles$\" + $sAMAccountName
				$objUser.Put("profilePath",$profilePath)
				$objUser.SetInfo()
			}
		Else
			{
				$objUser.PutEx(1,"profilePath",0)
				$objUser.SetInfo()
			}
		
		#make sure to rerun some tests if necessary
		#REF: http://www.powershellcommunity.org/Forums/tabid/54/aff/1/aft/3993/afv/topic/Default.aspx
		$arrTestsToSkip = $script:arrTestsToSkip
		$newGlobalArrTestToSkip = @($arrTestsToSkip | Where-Object {$_ -ne "profilePathPermissions"})
		$script:arrTestsToSkip = $newGlobalArrTestToSkip
		
	}


#groupMemberships

#Function Fix-GroupMembership-QuotaGroup($objUser) #SkipECC
#	{
#		$failThisFunction = $null
#		$failThisFunction = $false
#		$results = $null
#		$results = $false
#		
#		$hshOldGroupMapping = Read-Variable "hshOldQuotaGroupMappings"
#		$oldGroups = $hshOldGroupMapping.Keys
#		$arrUserGroups = Pull-LDAPAttribute $objUser "memberOf"
#		$strUserDN = Pull-LDAPAttribute $objUser "distinguishedName"
#		
#		$msg = "Action`t`t`tChecking to see if the user is a member of any old quota groups."
#		Write-Out $msg "darkcyan" 4
#		$blnQuotaGroupAdded = $null
#		$blnQuotaGroupAdded = $false
#		Foreach($groupDN in $arrUserGroups)
#			{
#				$groupCN = ($groupDN.substring(3)).split(",")[0]
#				If($oldGroups -contains $groupCN)
#					{
#						$msg = "Info`t`t`tFound an old quota group: """ + $groupCN + """."
#						Write-Out $msg "darkcyan" 4
#						$msg = "Action`t`t`tLooking up the new quota group for """ + $groupCN + """."
#						Write-Out $msg "darkcyan" 4
#						$newGroupCN = $null
#						$newGroupCN = $hshOldGroupMapping.Get_Item($groupCN)
#						#write-host -f yellow "debug`tnewgroupCN: $newGroupCN"
#						$newGroupDN = $null
#						$newGroupDN = Get-DNbyCN $newGroupCN
#						$msg = "Action`t`t`tAdding user to the group """ + $newGroupDN + """."
#						Write-Out $msg "darkcyan" 4
#						$blnGroupAdded = $null
#						$blnGroupAdded = $false
#						$blnGroupAdded = Add-ToGroup $strUserDN $newGroupDN
#						If($blnGroupAdded -eq $true)
#							{
#								$msg = "Info`t`t`tGroup added successfully."
#								Write-Out $msg "darkcyan" 4
#								$blnQuotaGroupAdded = $true
#							}
#						Else
#							{
#								$msg = "Error`t`t`tGroup could not be added."
#								Throw-Warning $msg
#							}
#					}
#			}
#		
#		If($blnQuotaGroupFound -eq $true)
#			{$results = $true}
#		Else
#			{
#				$msg = "Warning`t`t`tCould not find an old or new quota group for this user."
#				Throw-Warning $msg
#				
#				$results = $false
#			}
#		
#		If($failthisFunction -eq $true)
#			{$results = $false}
#		Else
#			{}
#		Return $results
#	}

Function Fix-GroupMembership-QuotaGroup($objUser) #SkipECC
	{
		$failThisFunction = $null
		$failThisFunction = $false
		$results = $null
		$results = $false
		
		$strUserDN = $null
		$strUserDN = Pull-LdapAttribute $objUser "distinguishedName"
		
		#look through the user's groups
		#is group like RES_Diskquota?
		#does old groups contains group? -> does groups contain corresponding new one?
		
		$hshOldToNewMapping = $null
		$hshOldToNewMapping = Read-Variable "hshOldQuotaGroupMappings"
		$arrOldQuotaGroupsCNs = $null
		$arrOldQuotaGroupsCNs = $hshOldToNewMapping.Keys
		
		$newQuotaGroupsCN = $null
		$newQuotaGroupsCN = Read-Variable "transitionalQuotaGroupsCN"
		$newQuotaGroupsDN = $null
		$newQuotaGroupsDN = Get-DNbyCN $newQuotaGroupsCN
		$objNewQuotaGroups = [adsi]("LDAP://" + $newQuotaGroupsDN)
		$objQuotaGroupsMembers = Pull-LDAPAttribute $objNewQuotaGroups "member"
		$arrNewQuotaGroupsDNs = $null
		$arrNewQuotaGroupsDNs = $objQuotaGroupsMembers

		###in case I actually needed CN's
#		$arrNewQuotaGroups = $objQuotaGroupsMembers | %{
#				$objGroup = $null;
#				$objGroup = [adsi]("LDAP://$_");
#				Pull-LDAPAttribute $objGroup "cn";
#			}
		
		$blnFoundAQuotaGroup = $null
		$blnFoundAQuotaGroup = $false
		
		###check old\new mappings.
		$msg = "Action`t`tLooking for membership in old quota groups."
		Write-Out $msg "darkcyan" 4
		Foreach($strOldGroupCN in $arrOldQuotaGroupsCNs)
			{
				If($failThisFunction -eq $true)
					{Break}
				Else
					{}
				
				#write-host -f yellow "debug`tstrOldGroupCN: $strOldGroupCN"
				$strOldGroupDN = $null
				$strOldGroupDN = Get-DNbyCN $strOldGroupCN
				$blnMember = $null
				$blnMember = $false
				$blnMember = Check-IsMemberOfGroup $strUserDN $strOldGroupDN
				If($blnMember -eq $true)
					{
						$msg = "Info`t`tUser is a member of the old quota group """ + $strOldGroupCN + """."
						Write-Out $msg "darkcyan" 4
						$strNewQuotaGroupCN = $null
						$strNewQuotaGroupCN = $hshOldToNewMapping.Get_Item($strOldGroupCN)
						$msg = "Action`t`tChecking for the corresponding new quota group """ + $strNewQuotaGroupCN + """."
						Write-Out $msg "darkcyan" 4
						$strNewQuotaGroupDN = $null
						$strNewQuotaGroupDN = Get-DNbyCN $strNewQuotaGroupCN
						$blnMember2 = $null
						$blnMember2 = $false
						$blnMember2 = Check-IsMemberOfGroup $strUserDN $strNewQuotaGroupDN
						If($blnMember2 -eq $true)
							{
								$msg = "Info`t`tUser is a member of the corresponding new group."
								Write-Out $msg "darkcyan" 4
								$blnFoundAQuotaGroup = $true
							}
						Else
							{
								$msg = "Info`t`tUser is -not- a member of the corresponding new group."
								Write-Out $msg "darkcyan" 4
								$msg = "Action`t`tAdding user to the corresponding new group."
								Write-Out $msg "darkcyan" 4
								$blnAdded = $null
								$blnAdded = $false
								$blnAdded = Add-ToGroup $strUserDN $strNewQuotaGroupDN
								If($blnAdded -eq $true)
									{
										$msg = "Info`t`tUser added to the new group successfully."
										Write-Out $msg "darkcyan" 4
										$blnFoundAQuotaGroup = $true
									}
								Else
									{
										$msg = "Warning`t`tFailed to add user to the new group."
										Throw-Warning $msg
										$failThisFunction = $true
									}
							}
					}
			}
		
		#check for any quota groups
		If($blnFoundAQuotaGroup -eq $false -and $failThisFunction -eq $false)
			{
				$msg = "ACTION`t`tChecking if the user is a member of any new (current) quota groups."
				Write-Out $msg "darkcyan" 4
				Foreach($quotaGroupDN in $arrNewQuotaGroupsDNs)
					{
						$blnMember = $null
						$blnMember = $false
						$blnMember = Check-IsMemberOfGroup $strUserDN $quotaGroupDN
						If($blnMember -eq $true)
							{
								$objGroup = [adsi]("LDAP://" + $quotaGroupDN)
								$objGroupCN = Pull-ldapAttribute $objGroup "CN"
								$msg = "INFO`t`t`tFound membership of at least one quota group: """ + $objGroupCN + """."
								Write-Out $msg "darkcyan" 4				
								$blnFoundAQuotaGroup = $true
								Break
							}
						Else
							{}
					}
				If($blnFoundAQuotaGroup -eq $false)
					{
						$msg = "Warning`t`tThe user is not a member of any new (current) quota groups."
						Throw-Warning $msg
						$failThisFunction = $true
					}
			}
		
		If($blnFoundAQuotaGroup -eq $true -and $failThisFunction -eq $false)
			{$results = $true}
		Else
			{
				$msg = "Warning`t`tYou must manually add the user to a quota group before the script can continue."
				Throw-Warning $msg
			}
		
		Return $results
	}

Function Fix-GroupMembership-RoleGroup($objUser) #SkipECC
	{
		$warningMsg = "Warning`t`tYou must manually add the user to a role group before the script can continue."
		Throw-Warning $warningMsg
		Return $false

#		###HACK FOR MIGRATING OLD ACCOUNTS - JP 10/02/10 REMOVE IMMEDIATELU
#		$groupDN = Get-DNbyCN "Mystery Users"
#		$userDN = Pull-LDAPAttribute $objUser "distinguishedName"
#		$results = Add-ToGroup $userDN $groupDN
#		Return $true
	}

Function Fix-groupMembership-RES_PrintingGroups($objUser)
	{
		$results = $null
		$results = $true
		
		$intRESPrintingCount = $null
		$intRESPrintingCount = 0
		$arrGroupDNs = Pull-LDAPAttribute $objUser "memberof"
		$arrRESPrintingGroups = @()
		Foreach($arrGroupDN in $arrGroupDNs)
			{
				If($arrGroupDN -like "*RES_Printing*")
					{
						
						$objGroup = $null
						$objGroup = [adsi]("LDAP://" + $arrGroupDN)
						$groupCN = $null
						$groupCN = Pull-LDAPAttribute $objGroup "CN"
						$arrRESPrintingGroups += $groupCN
						$objGroup = $null
						$msg = "Info`t`t`tFound RES_Printing group: """ + $groupCN + """."
						Write-Out $msg "darkcyan" 4
						$groupCN = $null
						$intRESPrintingCount++
					}
			}
		
		If($intRESPrintingCount -eq 0)
			{
				$msg = "Warning`t`tThis user is not a member of an RES_Printing group. They cannot access \\metered-printers!"
				Throw-Warning $msg
			}
		ElseIf($intRESPrintingCount -gt 1)
			{
				$msg = "Action`t`t`tRemoving this user from all RES_Printing Groups."
				Write-Out $msg "white" 2
				$strUserDN = $null
				$strUserDN = Pull-LDAPAttribute $objUser "distinguishedName"
				Foreach($groupCN in $arrRESPrintingGroups)
					{
						$msg = "Action`t`t`tRemoving user from group """ + $groupCN + """."
						Write-Out $msg "darkcyan" 4
						$strGroupDN = Get-DNbyCN $groupCN
						$action = $null
						$action = $true
						$action = Remove-FromGroup $strUserDN $strGroupDN
						If($action -eq $false)
							{$results = $false}
					}
			}
		
		Return $results
	}

Function Fix-GroupMembership-ClassAccountsQuotaGroup($objUser) #SkipECC
	{
		$CN = $null
		$results = $null
		
		$groupCN = Read-Variable "classAccountsQuotaGroupCN"
		$userDN = Pull-LDAPAttribute $objUser "distinguishedName"
		$groupDN = Get-DNbyCN $groupCN
		$results = Add-ToGroup $userDN $groupDN
		If($results -eq $null)
			{$results = $false}
		Return $results
	}

Function Fix-GroupMembership-anyClassGroup($objUser) #SkipECC
	{
		$warningMsg = "You must manually add the user to any class group before the script can continue."
		Throw-Warning $warningMsg
		Return $false
	}

Function Fix-PrimaryGroupCorrect($objUser)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		
		$intendedPGID = $null
		$intendedPGID = 513
		$objUser.Put("primaryGroupID",$intendedPGID)
		$objUser.SetInfo()
		#make sure it worked
		$primaryGroupID = $null
		$primaryGroupID = Pull-LDAPAttribute $objUser "primaryGroupID"
		If($primaryGroupID -eq $false -or $primaryGroupID -eq $null)
			{$failThisFunction = $true}
		ElseIf($primaryGroupID -eq $intendedPGID)
			{}
		Else
			{
				$msg = "INFO`t`tPrimary Group ID read as """ + $primaryGroupID + """."
				Write-Out $msg "darkcyan" 4
				$msg = "INFO`t`tNote: Primary Group ID should be """ + $intendedPGID + """."
				Write-Out $msg "darkcyan" 4
				$failThisFunction = $true
			}
		
		If($failThisFunction -eq $false)
			{$results = $true}
		Else
			{$results = $false}
		Return $results
	}


#HomeDirectoryAccessibility

Function Fix-ldapAttribute-homeDrive($objUser) #SkipECC
	{
		$homeDrive = Read-Variable "homedriveAttribute"
		$objUser.Put("homeDrive",$homeDrive)
		$objUser.SetInfo()
	}

Function Fix-ldapAttribute-homeDirectory($objUser) #SkipECC
	{
		$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
		$fileserver = Generate-UserHomeFS $objUser
		
		$homeDirectory = "\\" + $fileserver + "\" + $sAMAccountName + "$"
		$objUser.Put("homeDirectory",$homeDirectory)
		$objUser.SetInfo()
	}

Function Fix-HomeShareOrphans($objUser)
	{
		$arrFS = Read-Variable "fileserverlist"
		$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
		$sharename = $sAMAccountName + "$"
		
		$homeFS = $null
		$homeFS = Generate-UserHomeFS $objUser
		$msg = "Info`t`tGenerated user home file server is """ + $homeFS + """."
		Write-Out $msg "darkcyan" 3
		
		$arrFS | % {
			$fs = $_
			If($fs -eq $homeFS)
				{}
			Else
				{
					$bShareExists = $null
					$bShareExists = $false
					$bShareExists = Check-DoesShareExist $shareName $fs
					If($bShareExists -eq $true)
						{
							$msg = "INFO`t`tFound orphaned share on file server """ + $fs + """."
							Write-Out $msg "darkcyan" 3
							$msg = "Action`t`tDeleting orphaned share on file server """ + $fs + """."
							Write-Out $msg "darkcyan" 3
							$action = Delete-Share $shareName $fs
						}
				}
		}
	}
		
#homeDirectoryConformity
Function Fix-homeShareExists($objUser) #SkipECC
	{
		$failThisFunction = $null
		$failThisFunction = $false
		
		#Generate home directory path
		$UNCSharePath = Build-HomeFolderDestinationPath $objUser
		If($UNCSharePath -eq $false -or $UNCSharePath -eq $null)
			{$failThisFunction = $true}
		
		$fileServer = [regex]::match($UNCSharePath,'[^\\]+').value
		
		If($failThisFunction -eq $false)
			{
				#if not exist, create it
				$pathTest = Test-Path $UNCSharePath
				If($pathTest -eq $false)
					{$blnCreateFolder = Create-Folder $UNCSharePath}
				
				#create-share
				$shareName = $sAMAccountName + "$"
				$sharePath = Convert-UNCPathtoSharePath $UNCSharePath $fileserver
				
				$msg = "Action`t`tCreating a share on """ + $fileserver + """."
				Write-Out $msg "darkcyan" 3
				$msg = "Info`t`tshare path: """ + $sharePath+ """."
				Write-Out $msg "darkcyan" 3
				$msg = "Info`t`tShare name: """ + $shareName+ """."
				Write-Out $msg "darkcyan" 3
				
				$blnShareCreated = $null 
				$blnShareCreated = Create-Share $shareName $sharePath $fileserver
				
				$action = Fix-ldapAttribute-homeDirectory $objUser
				
				$blnPermsFixed = $null
				$blnPermsFixed = Fix-HomeSharePermissions $objUser
			}
		
		If($failThisFunction -eq $true)
			{$results = $false}
		Else
			{}
		
		#make sure to rerun some tests if necessary
		#REF: http://www.powershellcommunity.org/Forums/tabid/54/aff/1/aft/3993/afv/topic/Default.aspx
		$arrTestsToSkip = $script:arrTestsToSkip
		$newGlobalArrTestToSkip = @($arrTestsToSkip | Where-Object {@('homeSharePathExists','homeFolderOrphans') -notcontains $_})
		$script:arrTestsToSkip = $newGlobalArrTestToSkip
		
		Return $results
	}

Function Fix-homeSharePathExists($objUser) #SkipECC
	{
		$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
		$shareName = $sAMAccountName + "$"
		$homefs = Get-UserHomeFS $objUser
		Delete-Share $shareName $homefs
		$blnHomeShareFixed = Fix-HomeShareExists $objUser
	}

Function Fix-homeDirectoryTarget($objUser) #SkipECC
	{
		$objUser.PutEx(1,"homeDirectory",0)
		$objUser.SetInfo()
		Fix-ldapAttribute-homeDirectory $objUser
	}

Function Fix-homeSharePermissions($objUser) #SkipECC
	{
		$sAMAccountName = $null
		$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
		
		$fileserver = Get-UserHomeFS $objUser

		$sharename = $null
		$shareName = $sAMAccountName + "$"
		$strWMI = $null
		$strWMI = "\\" + $fileserver + "\root\cimv2:win32_share.name='" + $shareName + "'"
		$objShare = [wmi]$strWMI
		$objShare_NewSD = $null
		$objShare_NewSD = Build-HomeShareDACL $sAMAccountName
		#Write the ACE to the Share
		$objShare.SetShareInfo($Null,$Null,$objShare_NewSD.PSObject.BaseObject) | out-null
	}

Function Fix-homeFolderOrphans($objUser) #SkipECC
	{
		$results = $null
		$results = rebuild-homeFolders $objUser
		$homedircheck = $null
		$homedircheck = CheckAndFix-HomeDirectoryPermissions $objUser
		
		#make sure to rerun some tests if necessary
		#REF: http://www.powershellcommunity.org/Forums/tabid/54/aff/1/aft/3993/afv/topic/Default.aspx
		$arrNewTestsToSkip = $script:arrTestsToSkip
		$arrNewTestsToSkip += "homeShareExists"
		$arrNewTestsToSkip += "homeSharePermissions"
		$arrNewTestsToSkip += "homeDirectoryPermissions"
		$arrNewTestsToSkip += "homeFolderLocation"
		$script:arrTestsToSkip = $arrNewTestsToSkip
		
		Return $results
	}

Function Rebuild-HomeFolders($objUser)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		
		#common variables
		$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
		
		$msg = "ACTION`tRebuilding home folder."
		Write-Out $msg "darkcyan" 4
		
		#build destination folder path
		$msg = "ACTION`tBuilding home folder destination path."
		Write-Out $msg "darkcyan" 4
		$strDestinationPath = $null
		$strDestinationPath = Build-HomeFolderDestinationPath $objUser
		$blnDestinationPathBuilt = $null
		If($strDestinationPath -eq "" -or $strDestinationPath -eq $null -or $strDestinationPath -eq $false)
			{$blnDestinationPathBuilt = $false}
		Else
			{$blnDestinationPathBuilt = $true}
		If($blnDestinationPathBuilt -eq $true)
			{
				$msg = "INFO`tHome folder destination path built as """ + $strDestinationPath + """."
				Write-Out $msg "darkcyan" 4
			}
		Else
			{
				$warningMsg = "ERROR`tCould not build a destination path."
				Throw-Warning $warningMsg
				$failThisFunction = $true
			}
		
		
		
		#create the destination folder
		If($failThisFunction -eq $false)
			{
				$msg = "ACTION`tCreating the destination folder."
				Write-Out $msg "darkcyan" 4
				$blnFolderCreated = $null
				$blnFolderCreated = Create-Folder $strDestinationPath
				If($blnFolderCreated -eq $true)
					{
						$msg = "INFO`tDestination folder created."
						Write-Out $msg "darkcyan" 4
					}
				Else
					{
						$warningMsg = "ERROR`tCould not create the destination folder."
						Throw-Warning $warningMsg
						$failThisFunction = $true
					}
			}
		
		#search for \ precopy displaced folders
		If($failThisFunction -eq $false)
			{
				$msg = "ACTION`tSearching for and pre-copying any displaced folders."
				Write-Out $msg "darkcyan" 4
				$displacedFolders = $null
				$displacedFolders = Precopy-DisplacedFolders $objUser $strDestinationPath
				If($displacedFolders -eq $false)
					{
						$warningMsg = "ERROR`tCould not process displaced folders."
						Throw-Warning $warningMsg
						$FailThisFunction = $true
					}
				Else
					{
						$msg = "INFO`tDisplaced folders precopied successfully."
						Write-Out $msg "darkcyan" 4
					}
			}
		
		#switch sharepath \ recreate the share
		If($failThisFunction -eq $false)
			{
				$msg = "ACTION`tTesting \ rebuilding the user share."
				Write-Out $msg "darkcyan" 4
				$action = Fix-HomeShareOrphans $objUser
				$shareName = $sAMAccountName + "$"
				$blnShareRecreated = $null
				$blnShareRecreated = Rebuild-Share $shareName $strDestinationPath $objUser
				If($blnShareRecreated -eq $true)
					{
						$msg = "INFO`tUser share tested ok."
						Write-Out $msg "darkcyan" 4
					}
				Else
					{
						$warningMsg = "ERROR`tCould not recreate the user share."
						Throw-Warning $warningMsg
						$failThisFunction = $true
					}
			}
		
		#migrate any orphaned folders into the destination
		$msg = "ACTION`tMerging any displaced folders into the destination path."
		Write-Out $msg "darkcyan" 4
		If($failThisFunction -eq $false)
			{
				$orphansMerged = $null
				$orphansMerged = Merge-OrphanedHomeDirectories $objUser $strDestinationPath
				If($orphansMerged -eq $true)
					{
						$msg = "INFO`tDisplaced folders merged successfully."
						Write-Out $msg "darkcyan" 4
					}
				Else
					{
						$warningMsg = "ERROR`tCould not merge displaced folders."
						Throw-Warning $warningMsg
						$failThisFunction = $true
					}
			}
		
		#enforcing home directory permissions
		If($failThisFunction -eq $false)
			{
				$msg = "ACTION`tEnforcing proper target home directory permissions."
				Write-Out $msg "darkcyan" 4
				$blnPermissionsEnforced = $null
				$blnPermissionsEnforced = CheckAndFix-HomeDirectoryPermissions $objUser
				If($blnPermissionsEnforced -eq $true)
					{
						$msg = "INFO`tHome directory permissions enforced successfully."
						Write-Out $msg "darkcyan" 4
					}
				Else
					{
						$warningMsg = "ERROR`tFailed to enforce home directory permissions."
						Throw-Warning $warningMsg
						$failThisFunction = $true
					}
			}
		
		#rename original folder
		
		If($failThisFunction -eq $true)
			{$retval = $false}
		Else
			{$retval = $true}
		Return $retval
	}

Function Build-HomeFolderDestinationPath($objUser)
	{
		#find the quota folder name
		$strQuotaFolder = $null
		$strQuotaFolder = find-quota $objUser
		If($strQuotaFolder -eq $null -or $strQuotaFolder -eq $false -or $strQuotaFolder -eq "")
			{
				$warningMsg = "ERROR`t`t`tCould not determine quota folder for this user."
				Throw-Warning $warningMsg
				$failThisFunction = $true
			}
		Else
			{
				$msg = "INFO`t`t`tQuota folder determined to be """ + $strQuotaFolder + """."
				Write-Out $msg "darkcyan" 4
			}
		
		#build potential paths
		If($strQuotaFolder -eq "classes" -or $strQuotaFolder -eq "majors")
			{$fileserver = Read-Variable "fileserver-classes"}
		Else
			{$fileserver = Read-Variable "fileserver"}
		
		$strServerShareMountPath = $null
		$strServerShareMountPath = "\\" + $fileserver + "\c$\mount\"
		$strTargetRoot = $null
		$strTargetRoot = $strServerShareMountPath + "homes"
		$strTargetPath = $null
		$strTargetPath = ""
		
		$i = 0
		$blnStopLoop = $null
		$blnStopLoop = $false
		$arrPotentialPaths = $null
		$arrPotentialPaths = @()
		While($blnStopLoop -eq $false)
			{
				$strNewTargetRoot = $strTargetRoot + $i
				If((Test-Path $strNewTargetRoot) -eq $true)
					{$arrPotentialPaths += $strNewTargetRoot + "\data\" + $strQuotaFolder + "\" + $sAMAccountName}
				Else
					{$blnStopLoop = $true}		
				$i++
			}
		If($arrPotentialPaths.count -eq 0)
			{
				$warningMsg = "ERROR`tFailed to build potential target homefolder paths."
				Throw-Warning $warningMsg
				$failThisFunction = $true
			}
		
		$blnRebuildArg = $false
		$blnRebuildArg = Read-Variable "LunRebalance"
		If($blnRebuildArg -eq $true)
			{
				#pull home volume by argument if specified, free space if not.
				$sNewHome = Read-Variable "newHome"
				If ($sNewHome -eq $false -or $sNewHome -eq "" -or $sNewHome -eq $null)
					{$strHomeVolume = Pick-HomeVolumeByFreeSpace $fileServer}
				Else
					{$strHomeVolume = $sNewHome}
				
				$strTargetPath = $strTargetPath + $strServerShareMountPath + $strHomeVolume + "\data\" + $strQuotaFolder + "\" + $sAMAccountName
			}
		
		#look for a active folders
		If($failThisFunction -eq $false -and $strTargetPath -eq "")
			{
				$strPotentialPath = $null
				$arrActivePaths = $null
				$arrActivePaths = @()
				$arrEmptyActivePaths = $null
				$arrEmptyActivePaths = @()
				Foreach($strPotentialPath in $arrPotentialPaths)
					{
						If((Test-Path $strPotentialPath) -eq $true)
							{
								$blnFolderIsEmpty = $null
								$blnFolderIsEmpty = Check-IsFolderEmpty $strPotentialPath
								#write-host "checking for empty folder ""$strPotentialPath""`n	tResults: $blnFolderIsEmpty"
								If($blnFolderIsEmpty -eq $false)
									{
										$msg = "INFO`t`t`tFound active path """ + $strPotentialPath + """."
										Write-Out $msg "darkcyan" 4
										$arrActivePaths += $strPotentialPath
									}
								Else
									{
										$msg = "INFO`t`t`tFound empty active path """ + $strPotentialPath + """."
										Write-Out $msg "darkcyan" 4
										$arrEmptyActivePaths += $strPotentialPath
									}
							}
					}
			}
		
		#If we have an empty folder, and no non-empty folders, use the empty folder.
		If($strTargetPath -eq "" -and $arrActivePaths.Count -eq 0 -and $arrEmptyActivePaths.Count -gt 0)
			{
				$arrActivePaths += $arrEmptyActivePaths[0]
			}
		
		If($failThisFunction -eq $false -and $strTargetPath -eq "")
			{
				#if found zero, (pick a path based on free space)
				If($arrActivePaths.Count -eq 0 -or $blnRebuildArg -eq $true)
					{
						$strHomeVolume = $null
						$strHomeVolume = Pick-HomeVolumeByFreeSpace $fileserver
						$strTargetPath = $strServerShareMountPath + $strHomeVolume + "\data\" + $strQuotaFolder + "\" + $sAMAccountName
					}
				#if found one, use it
				ElseIf($arrActivePaths.Count -eq 1)
					{$strTargetPath = $arrActivePaths[0]}
				#if found more than one
				ElseIf($arrActivePaths.Count -gt 1)
					{
						#look for a sharepath
						$shareName = $null
						$shareName = $sAMAccountName + "$"
						$sharePath = $null
						$sharePath = Get-SharePath $shareName $fileserver
						If($sharePath -eq $null -or $sharePath -eq $false)
							{}
						Else
							{
								#if found, and it matches an active path, use it
								Foreach($strActivePath in $arrActivePaths)
									{
										$externalSharePath = $null
										$externalSharePath = $sharePath -replace("C:",("\\" + $fileserver + "\c$"))
										If($externalSharePath -eq $strActivePath)
											{$strTargetPath = $strActivePath}
									}
							}
						
						#if not found, or doesn't match a potential path, (pick one of the paths based on free space)
						If($strTargetPath -eq $null)
							{
								$strHomeVolume = Pick-HomeVolumeByFreeSpace $fileserver
								$strTargetPath = $strTargetPath + $strServerShareMountPath + $strHomeVolume + "\data\" + $strQuotaFolder + "\" + $sAMAccountName
							}	
					}
			}
		
		#last minute error checking
		If($strTargetPath -eq $null)
			{$failThisFunction = $true}
		Else
			{}
		
		$results = $null
		If($failThisFunction -eq $true)
			{$results = $false}
		Else
			{$results = $strTargetPath}
		Return $results	
	}

Function Precopy-DisplacedFolders($objUser,$strDestinationPath)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		
		#find orphaned folders
		[array]$arrOrphans = $null
		[array]$arrOrphans = @()
		$blnOrphansFound = $null
		$findOrphansResults = Find-OrphanedHomeDirectories $objUser
		If($findOrphansResults -eq $false)
			{$blnOrphansFound = $false}
		Else
			{
				#force results to be an array
				If($findOrphansResults -is [array])
					{$arrOrphans = $findOrphansResults}
				Else
					{$arrOrphans += $findOrphansResults}
				$blnOrphansFound = $true
				#fail if the results are broken
				If($arrOrphans -eq "" -or $arrOrphans -eq $null -or $arrOrphans -eq $false)
					{
						$warningMsg = "ERROR`t`tProblem finding orphaned home folders."
						Throw-Warning $warningMsg
						$failThisFunction = $true
					}
				#remove strDestinationPath if it's a member
				ElseIf($arrOrphans -contains $strDestinationPath)
					{
						#REF http://powershellcommunity.org/Forums/tabid/54/aff/1/aft/3993/afv/topic/Default.aspx
						$arrOrphans = @($arrOrphans | Where-Object {$_ -ne $strDestinationPath})
					}
				Else
					{}
			}
		
		#test home folder location
		$msg = "ACTION`t`tTesting the home folder location."
		Write-Out $msg "darkcyan" 4
		$results = Check-HomeFolderLocation $objUser
		If($results -ne $true)
			{
				$msg = "INFO`t`tHome folder location is bad."
				Write-Out $msg "darkcyan" 4
				$msg = "INFO`t`tAdding relative share path to the orphan list."
				Write-Out $msg "darkcyan" 4
				
				$fileserver = Get-UserHomeFS $objUser
				
				$blnOrphansFound = $true
				$sAMAccountName = $null
				$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
				$shareName = $null
				$shareName = $sAMAccountName + "$"
				$strRelativeSharePath = $null
				$strRelativeSharePath = Get-SharePathAsAdminUNC $shareName $fileServer
				If($arrOrphans -contains $strRelativeSharePath)
					{}
				Else
					{$arrOrphans += $strRelativeSharePath}
			}
		
		#precopy orphans
		If($blnOrphansFound -eq $true)
			{
				#display orphaned folders
				$msgs = $null
				$msgs = @()
				$msgs += "INFO`t`tFound the following bad\orphaned folders:"
				Foreach($strOrphan in $arrOrphans)
					{$msgs += "INFO`t`t`t*" + $strOrphan}
				Foreach($msg in $msgs)
					{write-Out $msg "darkcyan" 4}
				
				#do the copying
				Foreach($strOrphan in $arrOrphans)
					{
						If($failThisFunction -eq $false)
							{
								#precopy them
								$msg = "ACTION`t`tPrecopying orphan: """ + $strOrphan + """."
								Write-Out $msg "darkcyan" 4
								$results = $null
								$results = $false
								$results = Robocopy-Folder $strOrphan $strDestinationPath
								#$results = $true
								If($results -eq $true)
									{
										$msg = "INFO`t`tOrphan precopied successfully."
										Write-Out $msg "darkcyan" 4
									}
								Else
									{
										$warningMsg = "ERROR`t`tOrphan precopy failed."
										Throw-Warning $warningMsg
										$failThisFunction = $true
									}
							}
					}
			}
		
		If($failThisFunction -eq $false -and $blnOrphansFound -eq $true)
			{
				$msg = "ACTION`t`tUpdating Permissions at destination."
				Write-Out $msg "darkcyan" 4
				$DN = $null
				$DN = Pull-LDAPAttribute $objUser "distinguishedName"
				$permsUpdated = $null
				$permsUpdated = Fix-FSObjectPermissions $strDestinationPath $DN
			}
		
		$retval = $null
		If($failThisFunction -eq $true)
			{$retval = $false}
		Else
			{$retval = $true}
		Return $retval
	}

Function Merge-OrphanedHomeDirectories($objUser,$strDestinationPath)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		
		#find orphaned folders
		$msg = "ACTION`t`tSearching for orphaned folders."
		write-Out $msg "darkcyan" 4
		[array]$arrOrphans = $null
		[array]$arrOrphans = @()
		$blnOrphansFound = $null
		$findOrphansResults = Find-OrphanedHomeDirectories $objUser
		If($findOrphansResults -eq $false)
			{
				$msg = "INFO`t`tNo orphans found."
				Write-Out $msg "darkcyan" 4
				$blnOrphansFound = $false
			}
		Else
			{$blnOrphansFound = $true}
		
		If($blnOrphansFound -eq $true)
			{
				If($findOrphansResults -is [array])
					{$arrOrphans = $findOrphansResults}
				Else
					{$arrOrphans += $findOrphansResults}
				
				If($arrOrphans -eq "" -or $arrOrphans -eq $null -or $arrOrphans -eq $false)
					{
						$warningMsg = "ERROR`t`tProblem finding orphaned home folders."
						Throw-Warning $warningMsg
						$failThisFunction = $true
					}
				Else
					{
						#display orphaned folders
						$msgs = $null
						$msgs = @()
						$msgs += "INFO`t`tFound the following orphaned folders:"
						Foreach($strOrphan in $arrOrphans)
							{$msgs += "INFO`t`t`t*" + $strOrphan}
						Foreach($msg in $msgs)
							{write-Out $msg "darkcyan" 4}
					}
			}
		
		If($blnOrphansFound -eq $true)
			{
				#migrate orphans
				Foreach($strOrphan in $arrOrphans)
					{
						If($failThisFunction -eq $false)
							{
								$msg = "ACTION`t`tMigrating orphan: """ + $strOrphan + """."
								Write-Out $msg "darkcyan" 4
								$results = $null
								$results = $false
								$results = Migrate-Folder $strOrphan $strDestinationPath $objUser
								If($results -eq $true)
									{
										$msg = "INFO`t`tOrphan migrated successfully."
										Write-Out $msg "darkcyan" 4
									}
								Else
									{
										$warningMsg = "ERROR`t`tOrphan migration failed."
										Throw-Warning $warningMsg
										$failThisFunction = $true
									}
							}
					}
			}
		
		$retval = $null
		If($failThisFunction -eq $true)
			{$retval = $false}
		Else
			{$retval = $true}
		Return $retval
	}



Function Fix-homeFolderLocation($objUser) #SkipECC
	{
		$results = $null
		$results = rebuild-homeFolders $objUser
		
		#make sure to rerun some tests if necessary
		#REF: http://www.powershellcommunity.org/Forums/tabid/54/aff/1/aft/3993/afv/topic/Default.aspx
		$arrNewTestsToSkip = $script:arrTestsToSkip
		$arrNewTestsToSkip += "homeShareExists"
		$arrNewTestsToSkip += "homeSharePermissions"
		$arrNewTestsToSkip += "homeDirectoryPermissions"
		$arrNewTestsToSkip += "homeFolderLocation"
		$script:arrTestsToSkip = $arrNewTestsToSkip
		
		Return $results
	}

#profileAccessibility

Function Fix-profilePathExists($objUser) #SkipECC
	{
		$results = $null
		$profileShare = Read-Variable "profileShare"
		$blnAdminShareUp = Test-Path $profileShare
		If($blnAdminShareUp -eq $true)
			{
				$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
				$fileserver = Read-Variable "fileserver-profiles"
				$targetFolder = "\\" + $fileserver + "\profiles$\" + $sAMAccountName
				new-item $targetFolder -itemType Directory | out-null
				Fix-ProfilePathPermissions $objUser
				
				#make sure to rerun some tests if necessary
				#REF: http://www.powershellcommunity.org/Forums/tabid/54/aff/1/aft/3993/afv/topic/Default.aspx
				$arrTestsToSkip = $script:arrTestsToSkip
				$newGlobalArrTestToSkip = @($arrTestsToSkip | Where-Object {@('profileNotCluttered','profilePathPermissions') -notcontains $_})
				$script:arrTestsToSkip = $newGlobalArrTestToSkip
			}
		Else
			{
				$warningMsg = "ERROR`t`tProfile share: """ + $profileShare + """ is not available!"
				Throw-Warning $warningMsg
				$results = $false
			}
		
		Return $results
	}

Function Fix-ProfilePathPermissions($objUser) #SkipECC
	{
		$failThisFunction = $null
		$failThisFunction = $false
		
		$profileShare = Read-Variable "profileShare"
		$blnAdminShareUp = Test-Path $profileShare
		If($blnAdminShareUp -eq $true)
			{
				$profilePath = $null
				$profilePath = Pull-LDAPAttribute $objUser "profilePath"
				$profilePath2 = $null
				$profilePath2 = $profilePath + ".V2"
				
				$homeDirectoryPath = $null
				$homeDirectoryPath = Build-HomeFolderDestinationPath $objUser
				$results = $null
				If($homeDirectoryPath -eq $null -or $homeDirectoryPath -eq $false)
					{$failThisFunction = $true}
				Else
					{
						$permissionsRootPath = $null
						$permissionsRootPath = Trim-OneFolderLevel $homeDirectoryPath
						$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
						$DN = $null
						$DN = Pull-LDAPAttribute $objUser "distinguishedName"
						$results = Fix-FSObjectPermissions $profilePath $DN $permissionsRootPath
						If((Test-Path $profilePath2) -eq $true)
							{
								$results = Fix-FSObjectPermissions $profilePath2 $DN $permissionsRootPath
							}
					}
			}
		Else
			{
				$warningMsg = "ERROR`t`tProfile share: """ + $profileShare + """ is not available!"
				Throw-Warning $warningMsg
				$failThisFunction = $true
			}
		
		If($failThisFunction -eq $true)
			{$results = $false}
		
		Return $results
	}



#profileConformity

Function Fix-profileNotCluttered($objUser) #SkipECC
	{
		$profileShare = Read-Variable "profileShare"
		$blnAdminShareUp = Test-Path $profileShare
		If($blnAdminShareUp -eq $true)
			{
				$profilePath = Pull-LDAPAttribute $objUser "profilePath"
				$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
				$badFolders = Read-Variable "redirectedProfileFolders"
				$fileserver = Read-Variable "fileserver-profiles"
				Foreach($badFolder in $badFolders)
					{
						$badPath = $profilePath + "\" + $badfolder
						$newBadPath = $profileShare + "\badFolders\" + $sAMAccountName + "\" + $badFolder
						If(Test-Path $badPath)
							{$results = migrate-folder $badPath $newBadPath $objUser}
							
					}
			}
		Else
			{
				$warningMsg = "ERROR`t`tProfile share: """ + $profileShare + """ is not available!"
				Throw-Warning $warningMsg
				$results = $false
			}
		
		Return $results
	}

				
#ldapAttributes

Function Put-TerminalServicesAttributes($objUser,$strAttribute,$strAttrValue)
	{
		$retval = $null
		#build expected attributes
		Switch($strAttribute)
			{
				"tsAllowLogin"
					{
						$objUser.psbase.invokeSet("allowLogon",1)
						$objUser.SetInfo()
					}
				"tsHomeDrive"
					{
						$objUser.psbase.invokeSet("TerminalServicesHomeDrive",$strAttrValue)
						$objUser.SetInfo()
					}
				"tsHomeDirectory"
					{
						$objUser.psbase.invokeSet("TerminalServicesHomeDirectory",$strAttrValue)
						$objUser.SetInfo()
					}
				"tsProfilePath"
					{
						$objUser.psbase.invokeSet("TerminalServicesProfilePath",$strAttrValue)
						$objUser.SetInfo()
					}
				Default
					{}
			}
		
		$strUserVal = $null
		$strUserVal = Pull-TSAttribute $objUser $strAttribute
		If($strUserVal -eq $strAttrValue)
			{$retval = $true}
		Else
			{$retval = $false} 
		
		Return $retval
	}

Function Fix-TerminalServicesAttributes($objUser)
	{
		$fail = $null
		$fail = $false
		$arrTSAttributes = $null
		$arrTSAttributes = @()
		$arrTSAttributes += "tsAllowLogin"
		$arrTSAttributes += "tsHomeDrive"
		$arrTSAttributes += "tsHomeDirectory"
		$arrTSAttributes += "tsProfilePath"
		
		Foreach ($strCurAttrib in $arrTSAttributes)
			{
				$strReadAttribute = $null
				$strReadAttribute = Pull-TSAttribute $objUser $strCurAttrib
				$strReadAttribute = [System.Convert]::ToString($strReadAttribute)
				
				$strBuiltAttribute = $null
				$strBuiltAttribute = Build-TSAttribute $objUser $strCurAttrib
				$strBuiltAttribute = [System.Convert]::ToString($strBuiltAttribute)
				
				If($strReadAttribute -eq $strBuiltAttribute)
					{}
				Else
					{
						$msg = "Updating the TS attribute """ + $strCurAttrib + """ to value """ + $strBuiltAttribute + """."
						Write-Out $msg "darkcyan" 4
						$strAction = Put-TerminalServicesAttributes $objUser $strCurAttrib $strBuiltAttribute
					}
		}
		
		If($fail -eq $true)
			{$results = $false}
		Else
			{$results = $true}
		Return $results
	}

Function Fix-ldapAttribute-scriptPath($objUser)
	{
		$objUser.PutEx(1,"scriptPath",0)
		$objUser.SetInfo()
	}

Function Fix-ldapAttribute-userPrincipalName($objUser)
	{
		$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
		$upnSuffix = Read-Variable "domainFull"
		$upn = $sAMAccountName + "@" + $upnSuffix
		$upn = $upn.ToLower()
		$objUser.Put("userPrincipalName",$upn)
		$objUser.SetInfo()
	}

Function Fix-ldapAttribute-sAMAccountName($objUser) #DONE
	{
		$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
		$sAMAccountName = $sAMAccountName.ToLower()
		$objUser.Put("sAMAccountName",$sAMAccountName)
		$objUser.SetInfo()
	}

Function Fix-ldapAttribute-GIDNumber($objUser)
	{
		#this can't be fixed in a programatic way
		return $False
	}

Function Fix-ldapAttribute-mssfu30nisdomain($objUser)
	{
		$mssfu30nisdomain = Read-Variable "domainShort"
		$objUser.Put("mssfu30nisdomain",$mssfu30nisdomain)
		$objUSer.SetInfo()
	}

Function Fix-ldapAttribute-proxyAddresses($objUser)
	{
		#only add missing proxyAddresses, don't delete current ones that might have been added or tweaked manually
		$GeneratedProxyAddresses = $null
		$GeneratedProxyAddresses = @()
		$suffixes = Read-Variable "proxyAddressSuffixes"
		Foreach($suffix in $suffixes)
			{$GeneratedProxyAddresses += ("SMTP:" + $sAMAccountName + $suffix)}
		
		$newProxyAddresses = $null
		$newProxyAddresses = @()
		
		$proxyAddresses = $null
		$proxyAddresses = Pull-LDAPAttribute $objUser "proxyAddresses"
		If($proxyAddresses -eq $null -or $proxyAddresses -eq $false)
			{
				[array]$newProxyAddresses = $generatedProxyAddresses
			}
		Else
			{
				
				If($proxyAddresses -is [array])
					{
						#$intProxCount = $proxyAddresses.Count
						Foreach($addr in $proxyAddresses)
							{
								[string]$addrLine = $addr
								$newProxyAddresses += $addrLine
							}
					}
				Else
					{
						[string]$addrLine = $proxyAddress
						$newProxyAddresses += $addrLine
					}
				
				Foreach($generatedAddr in $generatedProxyAddresses)
					{
						If($newProxyAddresses -contains $generatedAddr)
							{}
						Else
							{$newProxyAddresses += $generatedAddr}
					}
			}
		
		$objUser.Put("proxyAddresses",$newProxyAddresses)
		$objUSer.SetInfo()
	}

Function Fix-ldapAttribute-unixhomedirectory($objUser)
	{
		#this can't be fixed in a programatic way
		return $false
	}

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
		
		$coreArg = Get-CoreArgument $arrArguments
		If($coreArg -eq $false)
			{
				$msg = "Error`tCould not determine core argument (run mode)."
				Throw-Warning $msg
				$results = $false
			}
		
		Return $results
	}

Function Get-CoreArgument($arrArguments)
	{
		$results = $null
		$results = $true
		
		$intCoreArgCounter = $null
		$intCoreArgCounter = 0
		$arrCoreArgs = $gArrCoreArguments
		Foreach($argument in $arrArguments)
			{
				If($arrCoreArgs -contains $argument)
					{
						$strCoreArgument = $argument
						$intCoreArgCounter++
					}
			}
		
		If($intCoreArgCounter -eq 0)
			{
				$msg = "ERROR`tMissing a core argument (either /precopy, /fix, or /guicreate)."
				Throw-Warning $msg
				$results = $false
			}
		ElseIf($intCoreArgCounter -gt 1)
			{
				$msg = "ERROR`tToo many core arguments. Please use only one of the following: /precopy, /fix, or /guicreate ."
				Throw-Warning $msg
				$results = $false
			}
		Else
			{$results = $true}
		
		$retval = $null
		$retval = $false
		If($results -eq $true)
			{$retval = $strCoreArgument}
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
		$arrInputArgs = $gArrInputArguments
		Foreach($argument in $arrArguments)
			{
				If($arrInputArgs -contains $argument)
					{
						$strInputArgument = $argument
						$intInputArgCounter++
					}
			}
		
		#for /guicreate, we souldn't have any input arguments
		$coreArgument = Get-CoreArgument $arrArguments
		If($coreArgument -eq "/guicreate")
			{
				If($intInputArgCounter -eq 0)
					{
						$continue = $false
						$results = $true
					}
				Else
					{
						$msg = "ERROR`tInput arguments found. When using /guicreate, please do not specify an input argument."
						Throw-Warning $msg
						$results = $false
					}
			}
		Else
			{
				If($intInputArgCounter -eq 0)
					{
						$msg = "ERROR`tNo input arguments given. The following arguments are input arguments: /folder, /file, /group, and /user ."
						Throw-Warning $msg
						$results = $false
					}
				ElseIf($intInputArgCounter -gt 1)
					{
						$msg = "ERROR`tToo many input arguments given. Please use only one of the following: /folder, /file, /group, and /user ."
						Throw-Warning $msg
						$results = $false
					}
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
				$arrValidExtensions = $gArrValidFileExtensions
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
		$validControlArgs = $gArrControlArguments
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
								"/return" {}
								"/rebuild" {}
								"/newhome"
									{
										#tests whether newhome given exists
										$sNewHome = $dependentArgs
										#####THIS NEEDS FIXED -- this won't always check the correct file server, just the default one.
										##### Example:  /newhome on a /user <class account username> will check winfs even though the user's data is on winfs-ug
										$fs = Read-Variable "fileserver"
										$mountRoot = Read-Variable "fileServer-LocalMountFolder"
										$sRootLetter = $mountRoot.Substring(0,1)
										$sRootPath = $mountRoot.Substring(3)
										$mountPath = "\\" + $fs + "\" + $sRootLetter + "$\" + $sRootPath + "\" + $sNewHome
										#write-host -f magenta "mountPath: """ $mountPath """."
										$pathTest = Test-Path $mountPath
										If($pathTest -eq $true)
											{}
										Else
											{
												$msg = "ERROR`tThe mountPath given in /newhome doesn't exist. Tested path: """ + $mountPath + """."
												Throw-Warning $msg
												$results = $false
											}
									}
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
		$arrInputArgs = $gArrInputArguments
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
		$validControlArgs = $gArrControlArguments
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
		
		$coreArgument = Get-CoreArgument $arrArguments
		$inputArgument = Get-InputArgument $arrArguments
		$controlArguments = Get-ControlArguments $arrArguments
		
		$coreArgCount = $null
		$coreArgCount = 1
		$coreArgDepsCount = $null
		$coreArgDepsCount = $gArgumentDependents.Get_Item($coreArgument)
		$intTotalCoreArgCount = $coreArgCount + $coreArgDepsCount
		
		$inputArgumentCount = $null
		$inputArgumentCount = 0
		$inputArgumentDepsCount = $null
		$inputArgumentDepsCount = 0
		If($coreArgument -ne "/guicreate")
			{
				$inputArgumentCount++
				$inputArgumentDepsCount = $gArgumentDependents.Get_Item($inputArgument)
			}
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
$gArrArguments = @()
$gArrArguments = $args

##General Variables
[array]$gArrArguments = $null	#Global copy of $args
$lArrArguments = $null								#Local scope copy of args (though, at the root)
$gStrRunMode = $null									#Run mode can be: gui, file, cli
$gStrRunModeModifiers = $null					#Run mode modifiers can be: verbose, eval, precopy, user, group
$gHshRunModeVariables = $null					#Run mode hash table of variables needed for that specific run mode to work.
$script:gOverrideVals = $null					#Hash table used to convey argument overrides to read-variable
$script:gOverrideVals = @{}

##Regulatory Variables
$gBlnBadArgument = $null
$gBlnBadArgument = $false

$msg = "Verifying Arguments, please wait."
Write-Out $msg "white" 2

#Inital check - any arguments present
[array]$gArrArguments = $args
$lArrArguments = $gArrArguments
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
$script:gVerbosityLevel = 4
$gFilename = $null
$gsAMAccountName = $null
$gIntLimit = 10000
$gStrRunMode = $null
$gStrAccountType = $null

If($gBlnBadArgument -eq $true)
	{
		$warningMsg = "ERROR`tExiting script."
		Throw-Warning $warningMsg
		Write-Fail
		Write-UsageInfo
	}
Else
	{
		#find runmode
		$coreArgument = $null
		$coreArgument = Get-CoreArgument $lArrArguments
		$gStrRunMode = $null
		Switch($coreArgument)
			{
				"/guicreate"
					{$gStrRunMode = "guicreate"}
				"/fix"
					{$gStrRunMode = "fix"}
				"/precopy"
					{$gStrRunMode = "precopy"}
				Default
					{
						$msg = "Error`tCore argument isn't defined."
						Throw-Warning $msg
						Exit
					}
			}
		
		#parse control arguments
		#find startnumber
		$controlArgs = $null
		$controlArgs = Get-ControlArguments $lArrArguments
		If($controlArgs -contains "/startnumber")
			{
				[int]$gIntStartNumber = $null
				$gIntStartNumber = Get-DependentArgs "/startnumber" 1 $lArrArguments
				#write-host -f green "gIntStartNumber: $gIntStartNumber"
			}
		Else
			{$gIntStartNumber = 0}
		
		#find limit
		If($controlArgs -contains "/limit")
			{
				[int]$gIntLimit = $null
				$gIntLimit = Get-DependentArgs "/limit" 1 $lArrArguments
				#write-host -f green "gintlimit: $gintlimit"
			}
		Else
			{$gIntLimit = 10000}
		
		#enable verbose mode
		If($controlArgs -contains "/verbose")
			{
				$script:gVerbosityLevel = 4
			}
		
		If($controlArgs -contains "/eval")
			{
				$script:gOverrideVals.Add("ReadOnly",$true)
			}
		
		If($controlArgs -contains "/rebuild")
			{
				$script:gOverrideVals.Add("LunRebalance",$true)
			}
		
		If($controlArgs -contains "/newhome")
			{
				$gNewHome = Get-DependentArgs "/newhome" 1 $lArrArguments
				$script:gOverrideVals.Add("newHome",$gNewHome)
			}
		
		#parse input arguments
		$gStrInputMode = Get-InputArgument $lArrArguments
		$gStrInputDep = Get-DependentArgs $gStrInputMode 1 $lArrArguments
		
		Write-OpeningBlock
		$results = Director $gStrRunMode $gStrInputMode $gStrInputDep $gIntStartNumber $gIntLimit
		
		
	}

If($controlArgs -eq $null){$controlArgs = Get-ControlArguments $gArrArguments}
If($controlArgs -contains "/return")
	{
		Return $results
	}

[GC]::Collect()