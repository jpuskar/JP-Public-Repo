#Create-Accounts-Settings.ps1

# when changing quarters:
#  currentQuarterClassString
#  expirationDate_Classes

Function Read-Variable($variable)
	{
		$results = $null
		
		If($script:gOverrideVals -is "System.Collections.Hashtable")
		  {
		    If($script:gOverrideVals.Keys -contains $variable)
					{$results = $script:gOverrideVals.$variable}
				Else
					{$results = $null}
			}
		Else
			{$results = $null}
		
		If($results -eq $null)
		  {
    		Switch($variable)
    			{
    				"fileserverlist"
    					{
    						##This should check for duplicates too before returning...
    						$arrFSList = @()
    						$arrFSList += Read-Variable "fileserver"
    						$arrFSList += Read-Variable "fileserver-classes"
    						
    						$results = $arrFSList
    					}
    				"unixAttributeList"
    					{
    						$arrAttributes = @()
    						$arrAttributes += "mssfu30nisdomain"
    						$arrAttributes += "gidNumber"
    						$arrAttributes += "uidNumber"
    						$results = $arrAttributes
    					}
    				"newHome"
    					{
    						#used to specify a new homedrive folder for users. done via gOverrides; this is the default value.
    						#used with /rebuild.
    						#removing this will cause homedrive rebuild operations to fail. Setting it will mandate a homedrive mount point to use.
    						#ex: $results = "homes1"
    						$results = $false
    					}	
    				"RDPProfileRoot"
    					{
    						$profileShare = Read-Variable "profileShare"
    						$profileShare = Trim-TrailingSlash $profileShare
    						$rdpProfileRoot = $profileShare + "\rdp"
    						$results = $rdpProfileRoot
    					}
    				"RDPGroups"
    					{
    						$arrRDPGroups = $null
    						$arrRDPGroups = @()
    						$arrRDPGroups += "Computer Support"
    						$arrRDPGroups += "Remote Desktop Profile Users"
    						$results = $arrRDPGroups
    					}
    				"ReadOnly"
    					{
    						$results = $false
    					}
    				"LunRebalance"
    					{
    						$results = $false
    					}
    				"DenyLoginsGroupCN"
    					{
    						$results = "ACL_InteractiveLogin_Deny"
    					}
    				"ReadyForWindowsArchiveGroupCN"
    					{
    						$results = "Ready for Windows Archival"
    					}
    				"ReadyForLinuxArchiveGroupCN"
    					{
    						$results = "Ready for Linux Archival"
    					}
    				"WindowsArchiveDoneGroupCN"
    					{
    						$results = "Windows Data Archived"
    					}
    				"LinuxArchiveDoneGroupCN"
    					{
    						$results = "Linux Data Archived"
    					}
    				"deletionGroupCN"
    					{
    						$results = "Ready to Delete"
    					}
    				"archiveRootUNC"
    					{
    						$results = "\\winfs\archived_users$"
    					}
    				"expiryNotificationAttribute"
    					{
    						$results = "extensionAttribute4"
    					}
    				"allClassAccountsAreRoaming"
    					{
    						#used by (f)Fix-OUisOK
    						#makes all class accounts DN like "classes,roaming".
    						$results = $true
    					}
    				"GroupCNsExemptFromClassOnlyChecks"
    					{
    						$arrGroups = $null
    						$arrGroups = @()
    						
    						$classAccountsGroupCN = $null
    						$classAccountsGroupCN = Read-Variable "classAccountsGroupCN"
    						$arrGroups += $classAccountsGroupCN
    						
    						$strClassGroupPrefix = $null
    						$strClassGroupPrefix = Read-Variable "ClassGroupPrefix"
    						$arrGroups += $strClassGroupPrefix
    						
    						$resGroupPrefix = $null
    						$resGroupPrefix = Read-Variable "resGroupPrefix"
    						$arrGroups += $resGroupPrefix
    						
    						$aclGroupPrefix = $null
    						$aclGroupPrefix = Read-Variable "aclGroupPrefix"
    						$arrGroups += $aclGroupPrefix
    						
    						$webOnlyGroupCN = $null
    						$webOnlyGroupCN = Read-Variable "WebOnlyGroupCN"
    						$arrGroups += $webOnlyGroupCN
    						
    						$readyForWinArchiveGroupCN = $null
    						$readyForWinArchiveGroupCN = Read-Variable "ReadyForWindowsArchiveGroupCN"
    						$arrGroups += $readyForWinArchiveGroupCN
    						
    						$readyForLinArchiveGroupCN = $null
    						$readyForLinArchiveGroupCN = Read-Variable "ReadyForLinuxArchiveGroupCN"
    						$arrGroups += $readyForLinArchiveGroupCN
    						
    						$WinArchiveDoneGroupCN = $null
    						$WinArchiveDoneGroupCN = Read-Variable "WindowsArchiveDoneGroupCN"
    						$arrGroups += $WinArchiveDoneGroupCN
    						
    						$LinArchiveDoneGroupCN = $null
    						$LinArchiveDoneGroupCN = Read-Variable "LinuxArchiveDoneGroupCN"
    						$arrGroups += $LinArchiveDoneGroupCN
    						
    						$readyToDeleteGroupCN = $null
    						$readyToDeleteGroupCN = Read-Variable "deletionGroupCN"
    						$arrGroups += $readyToDeleteGroupCN
    						
    						$needsExpirationGroupCN = $null
    						$needsExpirationGroupCN = Read-Variable "needsExpirationGroupCN"
    						$arrGroups += $needsExpirationGroupCN
    						
    						$arrGroups += "Archive Test 042212"
    						
    						$results = $arrGroups
    					}
    				"needsExpirationGroupCN"
    					{
    						$results = "Needs Expiration Date"
    					}
    				"ReadyForWindowsArchiveGroupCN"
    					{
    						$results = "Ready for Windows Archival"
    					}
    				"ReadyForLinuxArchiveGroupCN"
    					{
    						$results = "Ready for Linux Archival"
    					}
    				"WindowsArchiveDoneGroupCN"
    					{
    						$results = "Windows Data Archived"
    					}
    				"LinuxArchiveDoneGroupCN"
    					{
    						$results = "Linux Data Archived"
    					}
    				"deletionGroupCN"
    					{
    						$results = "Ready to Delete"
    					}
    				"testsToSkip"
    					{
    						##return as an array or a string
    						
    						#string example
    						#$results = "ldapattribute-sAMAccountName"
    						
    						#array example
    						#$results = @("ldapattribute-sAMAccountName","OUisOK")
    						
    						$results = $null
    					}
    				"oldQuotaGroupsCN"
    					{
    						$results = "Old Quota Groups"
    					}
    				"transitionalQuotaGroupsCN"
    					{
    						$results = "Transitional Quota Groups"
    					}
    				"hshOldQuotaGroupMappings"
    					{
    						$hshQuotaGroupMappings = @{}
    						$hshQuotaGroupMappings.Add("Grads","RES_DiskQuota_Grads")
    						$hshQuotaGroupMappings.Add("Post Docs","RES_DiskQuota_Grads")
    						$hshQuotaGroupMappings.Add("Undergrad Majors","RES_DiskQuota_Majors")
    						$hshQuotaGroupMappings.Add("Class Accounts","RES_DiskQuota_Classes")
    						$hshQuotaGroupMappings.Add("General Staff","RES_DiskQuota_Staff")
    						$hshQuotaGroupMappings.Add("Teaching Assistants","RES_DiskQuota_Staff")
    						$hshQuotaGroupMappings.Add("Faculty","RES_DiskQuota_Faculty")
    						$hshQuotaGroupMappings.Add("Undergrad Researchers","RES_DiskQuota_Other")
    						$hshQuotaGroupMappings.Add("Visitors","RES_DiskQuota_Other")
    						$results = $hshQuotaGroupMappings
    					}
    				"ugradMajorGroupCN"
    					{
    						#used by check-accountShouldBeExpired
    						$results = "Undergrad Majors"
    					}
    				"AllAccountsAreRoaming"
    					{
    						#this allows for systems where all accounts are roaming. OU checks are done differently, specifically in (f)Check-OUisOK
    						$results = $false
    					}
    				"badUACflags"
    					{
    						$results = @()
    						$results += "LOCKOUT"
    						$results += "HOMEDIR_REQUIRED"
    						$results += "PASSWD_NOTREQD"
    						$results += "PASSWD_CANT_CHANGE"
    						$results += "ENCRYPTED_TEXT_PWD_ALLOWED"
    						$results += "TEMP_DUPLICATE_ACCOUNT"
    						$results += "INTERDOMAIN_TRUST_ACCOUNT"
    						$results += "WORKSTATION_TRUST_ACCOUNT"
    						$results += "SERVER_TRUST_ACCOUNT"
    						$results += "DONT_EXPIRE_PASSWORD"
    						$results += "MNS_LOGON_ACCOUNT"
    						$results += "SMARTCARD_REQUIRED"
    						$results += "TRUSTED_FOR_DELEGATION"
    						$results += "NOT_DELEGATED"
    						$results += "USE_DES_KEY_ONLY"
    						$results += "DONT_REQ_PREAUTH"
    						$results += "TRUSTED_TO_AUTH_FOR_DELEGATION"
    					}
    				"ProxyAddressSuffixes"
    					{
    						$arrProxyAddressSuffixes = @()
    						$arrProxyAddressSuffixes += "@chemistry.ohio-state.edu"
    						$arrProxyAddressSuffixes += "@chemistry.osu.edu"
    						$arrProxyAddressSuffixes += "@chem.osu.edu"
    						$results = $arrProxyAddressSuffixes
    					}
    				"departmentalUsersOUString"
    					{
    						$results = Read-Variable "UsersOUCN"
    					}
    				"UsersOUCN"
    					{
    						$results = "Chemistry Users"
    					}
    				"UsersOUDN"
    					{
    						$results = "OU=Chemistry Users,DC=chemistry,DC=ohio-state,DC=edu"
    					}
    				"WebOnlyGroupCN"
    					{
    						$results = "Web-Only Users"
    					}
    				"WebOnlyOU"
    					{
    						$results = "OU=Web-Only,OU=Chemistry Users,DC=chemistry,DC=ohio-state,DC=edu"
    					}
    				"WebOnlyOUCN"
    					{
    						$results = "Web-Only"
    					}
    				"hshGroupQuotas"
    					{
    						$hshGroupQuotas = @{}
    						$hshGroupQuotas.Add((Get-DNbyCN "Class Accounts"),"classes")
    						$hshGroupQuotas.Add((Get-DNbyCN "Faculty"),"faculty")
    						$hshGroupQuotas.Add((Get-DNbyCN "Post Docs"),"grads")
    						$hshGroupQuotas.Add((Get-DNbyCN "Grads"),"grads")
    						$hshGroupQuotas.Add((Get-DNbyCN "Undergrad Majors"),"majors")
    						$hshGroupQuotas.Add((Get-DNbyCN "Visitors"),"other")
    						$hshGroupQuotas.Add((Get-DNbyCN "General Staff"),"staff")
    						$hshGroupQuotas.Add((Get-DNbyCN "Teaching Assistants"),"staff")
    						$hshGroupQuotas.Add((Get-DNbyCN "Undergrad Researchers"),"staff")
    						
    						#new groups
    						$hshGroupQuotas.Add((Get-DNbyCN "RES_DiskQuota_Staff"),"staff")
    						$hshGroupQuotas.Add((Get-DNbyCN "RES_DiskQuota_Grads"),"grads")
    						$hshGroupQuotas.Add((Get-DNbyCN "RES_DiskQuota_Faculty"),"faculty")
    						$hshGroupQuotas.Add((Get-DNbyCN "RES_DiskQuota_Other"),"other")
    						$hshGroupQuotas.Add((Get-DNbyCN "RES_DiskQuota_Classes"),"classes")
    						$hshGroupQuotas.Add((Get-DNbyCN "RES_DiskQuota_Majors"),"majors")
    						
    						#delete empty ones
    						$hshProcessedQuotas = $null
    						$hshProcessedQuotas = @{}
    						$keys = $null
    						$keys = $hshGroupQuotas.Keys
    						Foreach($key in $keys)
    							{
    								$value = $hshGroupQuotas.Get_Item($key)
    								If($value -eq $false)
    									{}
    								Else
    									{
    										$newKeys = $hshProcessedQuotas.Keys
    										If($newKeys -contains $key)
    											{}
    										Else
    											{
    												$hshProcessedQuotas.Add($key,$value)
    											}
    									}
    							}
    						
    						$results = $hshProcessedQuotas
    					}
    				"profileShare"
    					{
    						$fileserver = Read-Variable "fileserver"
    						$results = "\\" + $fileserver + "\profiles$"
    					}
    				"linuxFS"
    					{
    						$results = "linuxfs"
    					}
    				"computerSupportGroupCN"
    					{
    						$results = "Computer Support"
    					}
    				"computerSupportCompGroupCN"
    					{
    						$results = "COMP_ComputerSupport"
    					}
    				"pathTo7Zip"
    					{
    						$results = "C:\scripts\bin\7z.exe"
    					}
    				"pathToCSCCMD"
    					{
    						$results = "C:\scripts\bin"
    					}
    				"pathToPSExec"
    					{
    						$results = "C:\scripts\bin"
    					}
    				"ArchivedUsersGroupCN"
    					{
    						$results = "Archived Users"
    					}
    				"homeDrivesRootPath"
    					{
    						$fileServer = Read-Variable "fileserver"
    						$buffer = Read-Variable "fileserver-BufferFolderName"
    						$results = "\\" + $fileServer + "\c$\mount\homes5\" + $buffer + "\staff"
    					}
    				"DriveMappingScript"
    					{
    						$results = "\\dc1\netlogon\mapdrives.vbs"
    					}
    				"RoamingOUCN"
    					{
    						$results = "Roaming"
    					}
    				"RedirectedOUCN"
    					{
    						$results = "Redirected"
    					}
    				"CRGroupsOU"
    					{
    						$results = "OU=Capability Resource Groups,OU=Security Groups,DC=chemistry,DC=ohio-state,DC=edu"
    					}
    				"fileServer-PossibleOldGroupPaths"
    					{
    						$arrPaths = @()
    						$arrPaths += "J:\Shares"
    						$results = $arrPaths
    					}
    				"fileServer-BufferFolderName"
    					{
    						$results = "data"
    					}
    				"fileServer-LocalMountFolder"	
    					{
    						$results = "c:\mount"
    					}
    				"logFilePath"
    					{
    						$fileServer = Read-Variable "fileserver-logs"
    						$results = "\\" + $fileserver + "\logs\scripts\"
    						#$results = "C:\scripts\logs\"
    					}
    				"alternateLogFilePath"
    					{
    						$fileServer = Read-Variable "fileserver"
    						#$results = "\\" + $fileserver + "\logs\scripts\"
    						$results = "C:\scripts\logs\"
    					}
    				"ACLRegex"
    					{
    						#matches pretty well the file names that Get-ACL and Set-ACL can handle.
    						$results = "^[-a-z_0-9()\=\#\,\;\~\@\+\{\}\!\&':\%\$\\\s.]*[a-zA-Z0-9()\{\}\@\$\%\^\&\-\+\=\!\~\#\,\`\'\;]$"
    					}
    				"logFileFolder"
    					{
    						$fileserver = $null
    						$fileserver = Read-Variable "fileserver"
    						$results = "\\" + $fileserver + "\logs\scripts\Create-Accounts\"
    					}
    				"pathToSubinAcl"
    					{
    						$fileserver = Read-Variable "fileserver"
    						#$results = "\\" + $fileserver + "\computer_support\scripting\subinacl.exe"
    						$results = "C:\scripts\bin\subinacl.exe"
    					}
    				"pathToRobocopy"
    					{
    						$fileserver = Read-Variable "fileserver"
    					#	$results = "\\" + $fileserver + "\computer_support\scripting\robocopy.exe"
    						$results = "C:\scripts\bin\robocopy.exe"
    					}
    				"pathToDirectoryfixer"
    					{
    						$fileserver = Read-Variable "fileserver"
    					#	$results = "\\" + $fileserver + "\computer_support\scripting\directoryfixer.exe"
    						$results = "C:\scripts\bin\directoryfixer.exe"
    					}
					"pathToLdifArchives"
						{
							$fileserver = Read-Variable "fileserver"
							$results = "\\" + $fileserver + "\archived_users$\records\"
						}
    				"homedriveAdminsGroup"
    					{
    						$results = read-variable "homedriveAdminsGroupCN"
    					}
    				"homedriveAdminsGroupCN"
    					{
    						$results = "Homedrive Administrators"
    					}
    				"groupdriveAdminsGroup"
    					{
    						$results = Read-Variable "groupdriveAdminsGroupCN"
    					}
    				"groupdriveAdminsGroupCN"
    					{
    						$results = "Group Drive Administrators"
    					}
    				"internalHomeDirectoryRoots"
    					{
    						$fileserver = Read-Variable "fileserver"
    						$arrFS1 = @(`
    							("\\" + $fileserver + "\x$\"),`
    							("\\" + $fileserver + "\x$\shares\"),`
    							("\\" + $fileserver + "\x$\shares\false\"),`
    							("\\" + $fileserver + "\x$\shares\homes2\"),`
    							("\\" + $fileserver + "\x$\shares\homes3\"),`
    							("\\" + $fileserver + "\x$\shares\homes4\"),`
    							("\\" + $fileserver + "\c$\mount\homes0\"),`
    							("\\" + $fileserver + "\c$\mount\homes0\data\"),`
    							("\\" + $fileserver + "\c$\mount\homes1\"),`
    							("\\" + $fileserver + "\c$\mount\homes1\data\"),`
    							("\\" + $fileserver + "\c$\mount\homes2\"),`
    							("\\" + $fileserver + "\c$\mount\homes2\data\"),`
    							("\\" + $fileserver + "\c$\mount\homes3\"),`
    							("\\" + $fileserver + "\c$\mount\homes3\data\"),`
    							("\\" + $fileserver + "\c$\mount\homes4\"),`
    							("\\" + $fileserver + "\c$\mount\homes4\data\"),`
    							("\\" + $fileserver + "\c$\mount\homes5\"),`
    							("\\" + $fileserver + "\c$\mount\homes5\data\"),`
    							("\\" + $fileserver + "\c$\mount\homes6\"),`
    							("\\" + $fileserver + "\c$\mount\homes6\data\"),`
    							("\\" + $fileserver + "\c$\mount\homes7\"),`
    							("\\" + $fileserver + "\c$\mount\homes7\data\"),`
    							("\\" + $fileserver + "\c$\mount\homes8\"),`
    							("\\" + $fileserver + "\c$\mount\homes8\data\")`
    							)
    						$fileserver = Read-Variable "fileserver-classes"
    						$arrFS2 = @(`
    							("\\" + $fileserver + "\c$\mount\homes0\"),`
    							("\\" + $fileserver + "\c$\mount\homes0\data\"),`
    							("\\" + $fileserver + "\c$\mount\homes1\"),`
    							("\\" + $fileserver + "\c$\mount\homes1\data\")`
    							)
    						$results = $arrFS1 + $arrFS2
    					}
    				"internalHomeDirectoryRoots-classes"
    					{$results = $null}
    				"homeDirectoryQuotaPaths"
    					{
    						$results = @("classes","faculty","staff","grads","majors","other")
    					}
    				"fileserver"
    					{
    						$results = "winfs"
    					}
    				"fileserver-logs"
    					{
    						$results = "winfs"
    					}
    				"fileserver-classes"
    					{
    						$results = "winfs-ug"
    					}
    				"fileserver-profiles"
    					{
    						$results = "winfs"
    					}
    				"log-server"
    					{
    						$results = "winfs"
    					}
    				"MSSGroupCN"
    					{
    						$results = "MSS 2010"
    					}
    				"MSS2010OU"
    					{
    						$results = "OU=MSS Conference 2010,OU=Roaming,OU=Chemistry Users,DC=chemistry,DC=ohio-state,DC=edu"
    					}
    				"MSSExpirationDate"
    					{
    						$results = "07/04/2010"
    					}
    				"ConferenceAttendeeGroupCN"
    					{
    						$results = "Conference Attendees"
    					}
    				"endOfWinter2012"
    					{
    						$results = Get-Date "03/18/2012"
    					}
    				"endOfSummer2010"
    					{
    						$results = Get-Date "09/15/2010"
    					}
    				"endOfSummer2011"
    					{
    						$results = Get-Date "08/19/2011"
    					}
    				"endOfAutumn2010"
    					{
    						$results = Get-Date "12/18/2010"
    					}
    				"endOfAutumn2011"
    					{
    						$results = Get-Date "12/08/2011"
    					}
    				"endOfWinter2011"
    					{
    						$results = Get-Date "03/24/2011"
    					}
    				"endOfSpring2011"
    					{
    						$results = Get-Date "06/13/2011"
    					}
    				"endOfSchoolYear2010"
    					{
    						$results = Get-Date "09/15/2010"
    					}
    				"endOfSchoolYear2011"
    					{
    						$results = Get-Date "09/30/2011"
    					}
    				"endOfSchoolYear2012"
    					{
    						$results = Get-Date "08/12/2012"
    					}
					"endOfSchoolYear2013"
    					{
    						$results = Get-Date "08/10/2013"
    					}
    				"endOfSp2012"
    					{
    						$results = Get-Date "07/10/2012"
    					}
    				"endofSu2012"
    					{
    						$results = Get-Date "08/15/2012"
    					}
					"endOfAu2012"
						{
							$results = Get-Date "12/20/2012"
						}
					"endOfSp2013"
						{
							$results = Get-Date "05/05/2013"
						}
    				"expirationDate_Classes"
    					{
    						#used by read-variable "hshGroupExpirationDates"
    						$results = Read-Variable "endOfSp2013"
    					}
    				"expirationDate_Majors"
    					{
    						#used by read-variable "hshGroupExpirationDates"
    						$results = Read-Variable "endOfSchoolYear2013"
    					}
    				"expirationDate_TAs"
    					{
    						#used by read-variable "hshGroupExpirationDates"
    						$results = Read-Variable "endOfSchoolYear2013"
    					}
    				"hshGroupExpirationDates"
    					{
    						#used by (f)Find-GroupExpirationDate
    						$results = @{`
    							"Class Accounts" = Read-Variable "expirationDate_Classes";`
    							"RES_Diskquota_Classes" = Read-Variable "expirationDate_Classes";`
    							"Undergrad Majors" = Read-Variable "expirationDate_Majors";`
    							"RES_Diskquota_Majors" = Read-Variable "expirationDate_Majors";`
    							"Teaching Assistants" = Read-Variable "expirationDate_TAs";`
    							"Faculty" = "never";`
    							"RES_Diskquota_Faculty" = "never";`
    							"Staff" = "never";`
    							"RES_Diskquota_Staff" = "never";`
    							"Undergrad Researchers" = "unknown";`
    							"Grads" = "unknown";`
    							"RES_Diskquota_Grads" = "unknown";`
    							"Post Docs" = "unknown";`
    							"Visitors" = "unknown";`
    							"RES_Diskquota_Visitors" = "unknown";`
    							}
    					}
    				"currentQuarterClassString"
    					{
    						#used by (f)Check-IsMemberOfCurrentClassGroup
    						$results = "Sp13"
    					}
    				"homeDriveAttribute"
    					{
    						#used by (f)Check-ldapAttribute-homeDrive
    						#used by (f)Fix-ldapAttribute-homeDrive
    						$results = "U:"
    					}
    				"domainSuffix"
    					{
    						#not used
    						$results = Read-Variable "domainRootDN"
    					}
    				"domainRootDN"
    					{
    						#not used
    						$results = "DC=chemistry,DC=ohio-state,DC=edu"
    					}
    				"domainName_Short"
    					{
    						#used by (f)build-shareDACL
    						$results = "chemistry"
    					}
    				"domainShort"
    					{
    						#used by (f)Set-FolderOwner
    						$results = "chemistry"
    					}
    				"domainFull"
    					{
    						#used by (f)build-UserTableFromGUI
    						$results = "chemistry.ohio-state.edu"
    					}
    				"redirectedProfileFolders"
    					{
    						#used by (f)Check-ProfileNotCluttered
    						#used by (f)Fix-ProfileNotCluttered
    						$results = @("Application Data","My Documents","Desktop","Cookies")
    					}
    				"usersOU"
    					{
    						$results = "OU=Chemistry Users,DC=chemistry,DC=ohio-state,DC=edu"
    					}
    				"WebOnlyOrganizationalUnits"
    					{
    						$arrOUs = @()
    						$arrOUs += "OU=Group 1,OU=Web-Only,OU=Chemistry Users,DC=chemistry,DC=ohio-state,DC=edu"
    						$arrOUs += "OU=Group 2,OU=Web-Only,OU=Chemistry Users,DC=chemistry,DC=ohio-state,DC=edu"
    						$arrOUs += "OU=Group 3,OU=Web-Only,OU=Chemistry Users,DC=chemistry,DC=ohio-state,DC=edu"
    						$results = $arrOUs
    					}
    				"WebOnlyClassesOrganizationalUnits"
    					{
    						$arrOUs = @()
    						$arrOUs += "OU=Classes 1,OU=Web-Only,OU=Chemistry Users,DC=chemistry,DC=ohio-state,DC=edu"
    						$arrOUs += "OU=Classes 2,OU=Web-Only,OU=Chemistry Users,DC=chemistry,DC=ohio-state,DC=edu"
    						$arrOUs += "OU=Classes 3,OU=Web-Only,OU=Chemistry Users,DC=chemistry,DC=ohio-state,DC=edu"
    						$results = $arrOUs
    					}
    				"classOrganizationalUnits"
    					{
    						#used by (f)Pick-OU
    						$results = @(`
    							"OU=Classes 1,OU=Roaming,OU=Chemistry Users,DC=chemistry,DC=ohio-state,DC=edu",`
    							"OU=Classes 2,OU=Roaming,OU=Chemistry Users,DC=chemistry,DC=ohio-state,DC=edu",`
    							"OU=Classes 3,OU=Roaming,OU=Chemistry Users,DC=chemistry,DC=ohio-state,DC=edu",`
    							"OU=Classes 4,OU=Roaming,OU=Chemistry Users,DC=chemistry,DC=ohio-state,DC=edu",`
    							"OU=Classes 5,OU=Roaming,OU=Chemistry Users,DC=chemistry,DC=ohio-state,DC=edu"`
    							)
    					}
    				"roamingClassesOrganizationalUnits"
    					{
    						$results = Read-Variable "classOrganizationalUnits"
    					}
    				"roamingOrganizationalUnits"
    					{
    						#used by (f)Pick-OU
    						$results = @(`
    							"OU=Group 1,OU=Roaming,OU=Chemistry Users,DC=chemistry,DC=ohio-state,DC=edu",`
    							"OU=Group 2,OU=Roaming,OU=Chemistry Users,DC=chemistry,DC=ohio-state,DC=edu",`
    							"OU=Group 3,OU=Roaming,OU=Chemistry Users,DC=chemistry,DC=ohio-state,DC=edu",`
    							"OU=Group 4,OU=Roaming,OU=Chemistry Users,DC=chemistry,DC=ohio-state,DC=edu",`
    							"OU=Group 5,OU=Roaming,OU=Chemistry Users,DC=chemistry,DC=ohio-state,DC=edu"`
    							)
    					}
    				"redirectedOrganizationalUnits"
    					{
    						#used by (f)Pick-OU
    						$results = @(`
    							"OU=Group 1,OU=Redirected,OU=Chemistry Users,DC=chemistry,DC=ohio-state,DC=edu",`
    							"OU=Group 2,OU=Redirected,OU=Chemistry Users,DC=chemistry,DC=ohio-state,DC=edu",`
    							"OU=Group 3,OU=Redirected,OU=Chemistry Users,DC=chemistry,DC=ohio-state,DC=edu",`
    							"OU=Group 4,OU=Redirected,OU=Chemistry Users,DC=chemistry,DC=ohio-state,DC=edu",`
    							"OU=Group 5,OU=Redirected,OU=Chemistry Users,DC=chemistry,DC=ohio-state,DC=edu"`
    							)
    					}
    				"classAccountsCN"
    					{
    						$results = Read-Variable "classAccountsGroupCN"
    					}
    				"classAccountsGroupCN"
    					{
    						$results = "Class Accounts"
    					}
    				"classGroupPrefix"
    					{
    						$results = "classes"
    					}
    				"ClassOnlyOUCN"
    					{
    						$results = "Classes"
    					}
    				"aclGroupPrefix"
    					{
    						$Results = "ACL_"
    					}
    				"resGroupPrefix"
    					{
    						$Results = "RES_"
    					}
    				"classAccountGroups"
    					{
    						$arrGroups = $null
    						$arrGroups = @()
    						$arrGroups += "Class Accounts"
    						$arrGroups += "RES_DiskQuota_Classes"
    						$results = $arrGroups
    					}
    				"computerGroupPrefix"
    					{
    						$results = "COMP_"
    					}
    				"diskQuotaCNPrefix"
    					{
    						$results = "RES_DiskQuota"
    					}
    				"classAccountsQuotaGroupCN"
    					{
    						#used by (f)Check-OnlyQuotaGroupIsClassAccounts
    						#used by (f)Check-GroupMembership-ClassAccountsQuotaGroup
    						#used by (f)Fix-ClassAccountStatus
    						#used by (f)Fix-GroupMembership-ClassAccountsQuotaGroup
    						#used by (f)Find-IsAccountClassOnly
    						$results = "RES_DiskQuota_Classes"
    					}
    				"classAccountsQuotaGroupCN2"
    					{
    						#used by (f)Check-OnlyQuotaGroupIsClassAccounts
    						#used by (f)Check-GroupMembership-ClassAccountsQuotaGroup
    						#used by (f)Fix-ClassAccountStatus
    						#used by (f)Fix-GroupMembership-ClassAccountsQuotaGroup
    						#used by (f)Find-IsAccountClassOnly
    						$results = "RES_DiskQuota_Classes"
    					}
    				"quotaGroupsCN"
    					{
    						#used by (f)Build-GroupMembershipArray
    						#used by (f)Check-AttributesValid
    						#used by (f)Check-OnlyQuotaGroupIsClassAccounts
    						#used by (f)Check-GroupMembership-QuotaGroup
    						#used by (f)Check-GroupMembership-RoleGroup
    						$results = "Quota Groups"
    					}
    				"studentGroupsOUDN"
    					{
    						#used by (f)Create-ClassGroup
    						$results = "OU=Students,OU=Security Groups,DC=chemistry,DC=ohio-state,DC=edu"
    					}
    				"requiredAttributesForCreation"
    					{
    						#used by (f)Check-RequiredAttributesForCreationPresent
    						$results = @(`
    							"displayName",`
    							"employeeID",`
    							"sAMAccountName",`
    							"mail",`
    							"givenName",`
    							"sn"`
    							)
    					}
    				"requiredAttributesForProcessing"
    					{
    						#used by (f)Populate-TableFromsAMAccountName
    						#used by (f)Check-RequiredAttributesForProcessingPresent
    						$results = @(`
    							"displayName",`
    							"sAMAccountName"`
    							)
    					}
    				"unchangableAttributes"
    					{
    						#used by (f)Run-CreationTask-writeLDAPattributes
    							#Attributes which won't be set with $objUser.Put, even if they're listed in the XLSX file.
    							#(attributes exempt from the "Writing LDAP Attributes" phase of (f)create-user.)
    						$results = @(`
    							"name",`
    							"distinguishedname",`
    							"cn",`
    							"memberof"`
    							)
    					}
    				Default
    					{
    						$results = $null
    					}
    			}
    	}
		
		Return $results
	}