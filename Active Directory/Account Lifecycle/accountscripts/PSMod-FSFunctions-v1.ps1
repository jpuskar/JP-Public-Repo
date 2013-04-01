#PSMOD-FSFunctions-v1.ps1


#customizable functions

Function Find-Quota($objUser) #SkipECC
	{
		#$groups = $objUser.Memberof
		$results = $null
		$quota = 0
		$classification = $null
		$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
		$userDN = Get-DNbysAMAccountName $sAMAccountName
		#find largest quota group that the user is a member of
		$hshGroupQuotas = Read-Variable "hshGroupQuotas"
		$arrQGroups = $hshGroupQuotas.Keys
		Foreach($groupDN in $arrQGroups)
			{
				$newClassification = $null
				$bInGroup = $false
				$bInGroup = Check-IsMemberOfGroup $userDN $groupDN
				If($bInGroup -eq $true)
					{
						$newClassification = $hshGroupQuotas.Get_Item($groupDN)
						Switch($newClassification)
							{
								"none" {$newQuota = 0}
								"classes" {$newQuota = 500}
								"faculty" {$newQuota = 25000}
								"grads" {$newQuota = 1500}
								"majors" {$newQuota = 1000}
								"other" {$newQuota = 15000}
								"staff" {$newQuota = 25000}
								Default {$newQuota = 0}
							}
						If($newQuota -gt $quota)
							{
								$quota = $newQuota
								$classification = $newClassification
							}
						}
			}
		If($classification -eq "" -or $classification -eq $null)
			{$results =  $false}
		Else
			{$results = $classification}
		
		Return $results
	}


### Path Functions


Function PRIVATE_Run-MigrationTask($task,$source,$destination,$objUser)
	{
		$results = $null
		Switch($strTask)
			{
				"takeOwner-source"
					{
						$results = PRIVATE_MigrationTask_TakeOwner $source
					}
				"copyData"
					{
						$results = PRIVATE_MigrationTask_CopyData $source $destination
					}
				"mirrorData"
					{
						$results = PRIVATE_MigrationTask_MirrorData $source $destination
					}
				"verifyCopy"
					{
						$results = PRIVATE_MigrationTask_VerifyCopy $source $destination
					}
				"enforcePermissions-source"
					{
						$results = PRIVATE_MigrationTask_EnforcePermissions $source $objUser
					}
				"enforcePermissions-destination"
					{
						$results = PRIVATE_MigrationTask_EnforcePermissions $destination $objUser
					}
				"deleteSource"
					{
						$results = PRIVATE_MigrationTask_deleteSource $source
					}
				"renameSource"
					{
						$results = PRIVATE_MigrationTask_renameSource $source
					}
			}
		Return $results
	}

Function PRIVATE_MigrationTask_TakeOwner($path)
	{
		$results = Take-FolderOwnership $path
		return $true
	}

Function PRIVATE_MigrationTask_MirrorData($source,$destination)
	{
		$failThisfunction = $null
		$failThisfunction = $false
		
		$msg = "ACTION`t`tCopying the data from source to destination """ + $destination + """."
		Write-Out $msg "darkcyan" 4
		$switches = $null
		#/XO means 'eXclude Older'.
		#If a file exists in both the source and destination, /XO makes sure that robocopy leaves whichever file is newer.
		$switches = "/XO /MIR"
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
		
		$retval = $null
		If($failThisfunction -eq $true)
			{$retval = $false}
		Else
			{$retval = $true}
		Return $retval
	}

Function PRIVATE_MigrationTask_CopyData($source,$destination)
	{
		$failThisfunction = $null
		$failThisfunction = $false
		
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
		
		$retval = $null
		If($failThisfunction -eq $true)
			{$retval = $false}
		Else
			{$retval = $true}
		Return $retval
	}

Function PRIVATE_MigrationTask_VerifyCopy($source,$destination)
	{
		$failThisfunction = $null
		$failThisfunction = $false
		
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
		
		$retval = $null
		If($failThisfunction -eq $true)
			{$retval = $false}
		Else
			{$retval = $true}
		Return $retval
	}

Function PRIVATE_MigrationTask_EnforcePermissions($target,$objUser)
	{
		$DN = $null
		$DN = Pull-LdapAttribute $objUser "distinguishedName"
		$failThisfunction = $null
		$failThisfunction = $false
		
		$msg = "ACTION`t`tEnforcing proper folder permissions on """ + $target + """."
		Write-Out $msg "darkcyan" 4
		
		$blnObjectExists = $null
		$blnObjectExists = Check-DNExists $dn
		If($blnObjectExists -eq $true)
			{
				$objADObject = $null
				$objADObject = [adsi]("LDAP://" + $DN)
				$strOC = $null
				$strOC = Pull-LDAPAttribute $objADObject "objectCategory"
				If($strOC -like "*user*" -or $strOC -like "*person*")
					{
						$blnPermissionsFixed = $null
						$blnPermissionsFixed = Fix-FSObjectPermissions $target $DN
						If($blnPermissionsFixed -eq $true)
							{
								$msg = "ACTION`t`tFolder permissions enforced successfully (user object)."
								Write-Out $msg "darkcyan" 4
							}
						Else
							{
								$warningMsg = "ERROR`t`tFolder permissions enforcement failed (user object)."
								Throw-Warning $warningMsg
								$failThisfunction = $true
							}
					}
				ElseIf($strOC -like "*group*")
					{
						$blnPermissionsFixed = $null
						$blnPermissionsFixed = Fix-FSObjectPermissions $target $DN
						If($blnPermissionsFixed -eq $true)
							{
								$msg = "ACTION`t`tFolder permissions enforced successfully (group object)."
								Write-Out $msg "darkcyan" 4
							}
						Else
							{
								$warningMsg = "ERROR`t`tFolder permissions enforcement failed (group object)."
								Throw-Warning $warningMsg
								$failThisfunction = $true
							}
					}
				Else
					{
						$msg = "ERROR`t`tCould not determine if the AD object """ + $DN + """ is a user or group."
						Throw-Warning $msg
						$failThisfunction = $true
					}
			}
		Else
			{
				$msg = "ERROR`t`tThe AD object """ + $DN + """ does not exist."
				Throw-Warning $msg
				$failThisfunction = $true
			}
		
		
		
		
		
		$retval = $null
		If($failThisfunction -eq $true)
			{$retval = $false}
		Else
			{$retval = $true}
		Return $retval
	}

Function PRIVATE_MigrationTask_deleteSource($source)
	{
		$msg = "ACTION`t`tDeleting source folder."
		Write-Out $msg "darkcyan" 4
		$blnSourceDeleted = $null
		$blnSourceDeleted = Delete-Folder $source
		If($blnSourceDeleted -eq $true)
			{
				$msg = "ACTION`t`tSource folder deleted successfully."
				Write-Out $msg "darkcyan" 4
			}
		Else
			{
				$warningMsg = "WARNING`t`tFailed to delete source folder."
				Throw-Warning $warningMsg
				
				$msg = "ACTION`t`tAttempting to rename the folder."
				Write-Out $msg "darkcyan" 4
				
				$blnSourceRenamed = $null
				$blnSourceRenamed = $false
				$blnSourceRenamed = Rename-BadFolder $source
				If($blnSourceRenamed -eq $true)
					{
						$msg = "INFO`t`tSource folder renamed successfully."
						Write-Out $msg "darkcyan" 4
					}
				Else
					{
						$warningmsg = "ERROR`t`tFailed to rename source folder."
						Throw-Warning $warningMsg
						$failThisfunction = $true
					}
			}
		
		If($blnSourceDeleted -eq $true -or $blnSourceRenamed -eq $true)
			{$retval = $true}
		Else
			{$retval = $false}
		Return $retval
	}

Function PRIVATE_MigrationTask_renameSource($source)
	{
		$msg = "ACTION`t`tRenaming source folder """ + $source + """."
		Write-Out $msg "darkcyan" 4
		
		$blnSourceRenamed = $null
		$blnSourceRenamed = $false
		$blnSourceRenamed = Rename-BadFolder $source
		If($blnSourceRenamed -eq $true)
			{
				$msg = "INFO`t`tSource folder renamed successfully."
				Write-Out $msg "darkcyan" 4
			}
		Else
			{
				$warningmsg = "ERROR`t`tFailed to rename source folder."
				Throw-Warning $warningMsg
				$failThisfunction = $true
			}
		
		If($blnSourceRenamed -eq $true)
			{$retval = $true}
		Else
			{$retval = $false}
		Return $retval
	}

Function Pick-HomeVolumeByFreeSpace($fileServer)
	{
		##returns something like "homes2" --NOT-- \\winfs\c$\mount\homes2\data
		If($fileserver -eq $null -or $fileserver -eq "")
			{$fileserver = Read-Variable "fileserver"}
		$ServerName = $fileserver
		$Summary = $null
		$Summary = @()
		
		$objFSO = $null
		$objFSO = New-Object -com Scripting.FileSystemObject
		$MountPoints = $null
		$MountPoints = gwmi -class "win32_mountpoint" -namespace "root\cimv2" -computername $ServerName 
		$Volumes = $null
		$Volumes = gwmi -class "win32_volume" -namespace "root/cimv2" -ComputerName $ServerName| select name, freespace
	
	
		$highestPercFree = $null
		$strDestinationVolume = $null
		$cur_highestPercFree = 0
		
		$MP = $null
		foreach ($MP in $Mountpoints)
			{
				$MP.directory = $MP.directory.replace("\\","\")	 
				$v = $null
				foreach ($v in $Volumes)
					{
						$vshort = $null
						$vshort = $v.name.Substring(0,$v.name.length-1 )
						$vshort = ("""" + $vshort + """") #Make it look like format in $MP (line 11).
						if ($mp.directory.contains($vshort)) #only queries mountpoints that exist as drive volumes no system
							{
								$Record = $null
								$Record = new-Object -typename System.Object 
								$DestFolder = $null
								$DestFolder = "\\"+ $ServerName + "\"+ $v.name.Substring(0,$v.name.length-1 ).Replace(":","$") 
								#$destFolder #troubleshooting string to verify building dest folder correctly.
								$colItems = $null
								$colItems = (Get-ChildItem $destfolder |  where{$_.length -ne $null} |Measure-Object -property length -sum)
								#to clean up errors when folder contains no files. 
								#does not take into account subfolders. 
								
								$fsize = $null
								if($colItems.sum -eq $null)
									{$fsize = 0}
								else
									{$fsize = $colItems.sum}
								
								$percFree = $null
								$percFree = $v.freespace
								$name = $null
								$name = $v.name 
								
								#this outside IF statement was inserted to force homes9 to be the mount point during a migration.
								#commenting out - JP 01/02/12
#								If($name -like "*homes9*")
#									{
										If($percFree -gt $cur_highestPercFree)
											{
												$cur_highestPercFree = $percFree
												$strDestinationVolume = $null
												$strDestinationVolume = $name
											}
#									}

							}
					}
			}
		$folderName = $null
		$folderName = $strDestinationVolume -replace ("C:\\mount\\","")
		$folderName = $folderName -replace ("\\","")
		##returns something like "homes2" --NOT-- \\winfs\c$\mount\homes2\data
		Return $folderName
	}

Function Create-Folder($strFolder)
	{
		$results = $null
		$results = $false
		
		If($strFolder -eq $null -or $strFolder -eq "" -or $strFolder -eq $false)
			{$results = $false}
		Else
			{
				If((Test-Path $strFolder) -eq $true)
					{$results = $true}
				Else
					{New-Item $strFolder -itemType Directory}
				
				If((Test-Path $strFolder) -eq $true)
					{$results = $true}
				Else
					{$results = $false}
			}
		
		Return $results
	}

Function Migrate-Folder($source,$destination,$objADObject)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		
		$arrMigrationTasks = @()
		$arrMigrationTasks += "takeOwner-source"
		$arrMigrationTasks += "copyData"
		$arrMigrationTasks += "verifyCopy"
		$arrMigrationTasks += "renameSource"
		
		###needs to do a better test -- pull the DN?
		If($objADObject -ne $null)
			{$arrMigrationTasks += "enforcePermissions-destination"}
		#$arrMigrationTasks += "renameSource"
		
		Foreach($strTask in $arrMigrationTasks)
			{
				If($failThisFunction -eq $false)
					{
						$msg = "ACTION`t`Running folder task """ + $strTask + """."
						Write-Out $msg "darkcyan" 4
						$results = $null
						$results = PRIVATE_Run-MigrationTask $task $source $destination $objADObject
						If($results -eq $true)
							{
								$msg = "INFO`t`Task successful."
								Write-Out $msg "darkcyan" 4
							}
						Else
							{
								$warningMsg = "ERROR`t`tFolder task failed: """ + $strTask + """."
								Throw-Warning $warningMsg
								$failThisFunction = $true
							}
					}
			}
		
		If($failThisFunction -eq $true)
			{$retval = $false}
		Else
			{$retval = $true}
		Return $retval
	}

Function Precopy-Folder($source,$destination,$objUser)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		
		$arrMigrationTasks = @()
		$arrMigrationTasks += "enforcePermissions-source"
		$arrMigrationTasks += "copyData"
		$arrMigrationTasks += "verifyCopy"
		$arrMigrationTasks += "enforcePermissions-destination"
		
		Foreach($strTask in $arrMigrationTasks)
			{
				If($failThisFunction -eq $false)
					{
						$msg = "ACTION`t`Running folder task """ + $strTask + """."
						Write-Out $msg "darkcyan" 4
						$results = $null
						$results = PRIVATE_Run-MigrationTask $task $source $destination $objUser
						If($results -eq $true)
							{
								$msg = "INFO`t`Task successful."
								Write-Out $msg "darkcyan" 4
							}
						Else
							{
								$warningMsg = "ERROR`t`tFolder task failed: """ + $strTask + """."
								Throw-Warning $warningMsg
								$failThisFunction = $true
							}
					}
			}
		
		If($failThisFunction -eq $true)
			{$retval = $false}
		Else
			{$retval = $true}
		Return $retval
	}

Function Verify-FolderCopy($source,$destination)
	{
		#write-host -f yellow "source: $source`tdestination:$destination"
		$results = $null
		$results = $true
		
		#trap{continue;}
		
		#add a trailing \ to source and dest if necessary
		$source = Add-TrailingSlash $source
		$destination = Add-TrailingSlash $destination
		
		#build relative source array
		#REF: http://pauerschell.blogspot.com/2009/04/get-childitem-recursive-comparing-two.html
		$arrSourceFullFiles = Get-ChildItem -recurse -force -path $source -erroraction silentlycontinue
		$arrRelativeSource = $null
		$arrRelativeSource = @()
		$file = $null
		Foreach($file in $arrSourceFullFiles)
			{
				$fullFileName = $null
				$fullFileName = $file.FullName
				If($fullFileName -like "*autorun.inf*")
					{}
				ElseIf($fullFileName.length -gt 180)
					{}
				ElseIf($fullFileName -like "*~*")
					{}
				Else
					{
						$relativeFileName = $null
						$relativeFileName = $fullFileName.substring(($source.length))
						#write-host -f cyan "relativeFileName: $relativeFileName"
						$arrRelativeSource += $relativeFileName
					}
			}
		
		#build relative destination array
		$arrDestFullFiles = Get-ChildItem -recurse -force -path $destination -erroraction silentlycontinue
		$arrRelativeDest = $null
		$arrRelativeDest = @()
		$file = $null
		Foreach($file in $arrDestFullFiles)
			{
				$fullFileName = $null
				$fullFileName = $file.FullName
				$relativeFileName = $null
				$relativeFileName = $fullFileName.substring(($destination.length))
				$arrRelativeDest += $relativeFileName
			}
		
		#compare
		$regex = Read-Variable "ACLRegex"
		Foreach($sourceFile in $arrRelativeSource)
			{
				If($sourceFile -eq $null -or $sourceFile.fullname -eq $null)
					{}
				Else
					{
						$path = $sourceFile.fullname.ToString()
						If($sourceFile.length -gt 200 -or $sourceFile -notmatch $regex)
							{}
						ElseIf($arrRelativeDest -notcontains $sourceFile)
							{
								$msg = "ERROR`t`tFile """ + $sourceFile + """ is missing from destination."
								Write-Out $msg "darkcyan" 4
								$results = $false
							}
					}
			}
		
		Return $results
	}

Function Enforce-FolderPermissions($targetPath,$DN,$optional_rootPath)
	{
		
	}

Function Fix-FSObjectPermissions($targetPath,$DN,$optional_rootPath)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		
		If($DN -eq $false)
			{
				$msg = "ERROR`t`tThe DN passed to (f)Fix-FSObjectPermissions was ""false""."
				Throw-Warning $msg
				$failthisFunction = $true
			}
		ElseIf($DN -eq "" -or $DN -eq $null)
			{
				$msg = "ERROR`t`tNo DN was passed to (f)Fix-FSObjectPermissions."
				Throw-Warning $msg
				$failthisFunction = $true
			}
		
		#get root path
		If($failThisFunction -eq $false)
			{
				$rootPath = $null
				If($optional_rootPath -eq $null)
					{
						$rootPath = Trim-OneFolderLevel $targetPath
						If($rootPath -eq $false -or $rootPath -eq $null)
							{
								$warningMsg = "ERROR`t`t`tCannot get permissions from root folder """ + $rootPath + """."
								Throw-Warning $warningMsg
								$failThisFunction = $true
							}
						ElseIf((Test-Path $rootPath) -eq $false)
							{
								$warningMsg = "ERROR`t`t`tCannot get permissions from root folder """ + $rootPath + """."
								Throw-Warning $warningMsg
								$failThisFunction = $true
							}
					}
				Else
					{$rootPath = $optional_RootPath}
			}
		
		#lets fix these perms!
		If($failThisFunction -eq $false)
			{
				#user or group
				$blnObjectExists = $null
				$blnObjectExists = Check-DNExists $DN
				If($blnObjectExists -eq $false)
					{$failThisFunction = $true}
				Else
					{
						$ADObject = $null
						$ADObject = [adsi]("LDAP://" + $DN)
						$strOC = $null
						$strOC = Pull-LDAPAttribute $ADObject "objectCategory"
						#write-host -f yellow "strOC: $strOC"
						$strObjectType = $null
						If($strOC -like "*person*" -or $strOC -like "*user*")
							{$strObjectType = "user"}
						ElseIf($strOC -like "*group*")
							{$strObjectType = "group"}
						Else
							{
								$msg = "ERROR`t`tThis object doesn't look like a user or a group`nINFO`t`t`tDN: """ + $dn + """ ."
								$failThisFunction = $true
								Throw-Warning $msg
							}
					}
				
				#get the users we need
				If($failThisFunction -eq $false)
					{
						Switch($strObjectType)
							{
								"user"
									{
										$domainShort = $null
										$domainShort = Read-Variable "domainShort"
										$sAMAccountName = $null
										$sAMAccountName = Pull-LDAPAttribute $ADObject "sAMAccountName"
										$fullUsername = $null
										$fullUsername = $domainShort + "\" + $sAMAccountName
										$homeDriveAdminsGroup = $null
										$homeDriveAdminsGroup = Read-Variable "homedriveAdminsGroup"
										$fullHomeDriveAdmins = $null
										$fullHomeDriveAdmins = $domainShort + "\" + $homeDriveAdminsGroup
										$users = $null
										$users = @($fullHomeDriveAdmins,$fullUsername)
									}
								"group"
									{
										$CN = $null
										$CN = Pull-LDAPAttribute $ADObject "CN"
										
										###CHECK GROUP EXISTENCE!!!
										$domainShort = $null
										$domainShort = Read-Variable "domainShort"
										$strReadGroup = $null
										$strReadGroup = Get-ACLReadGroupCN $groupCN
										$fullReadGroup = $null
										$fullReadGroup = $domainShort + "\" + $strReadGroup
										
										$strWriteGroup = $null
										$strWriteGroup = Get-ACLWriteGroupCN $groupCN
										$fullWriteGroup = $null
										$fullWriteGroup = $domainShort + "\" + $strWriteGroup
										
										$strGroupDriveAdminsGroupCN = $null
										$strGroupDriveAdminsGroupCN = Read-Variable "groupdriveAdminsGroup"
										$fullAdminGroup = $domainShort + "\" + $strGroupDriveAdminsGroupCN
										
										###MAGIC!!!
										$users = $null
										$users = @($fullAdminGroup,$fullReadGroup,$fullWriteGroup)
									}
								Default
									{
										$msg = "ERROR`t`tCould not determine whether the given DN is for a user or group object.`nINFO`t`t`tDN: """ + $DN + """."
										Throw-Warning $msg
										$failThisFunction = $true
									}
							}
					}
				
				#set the perms
				If($failThisFunction -eq $false)
					{
						#Get-ACL of Parent
						$msg = "ACTION`t`tReading ACL from root path """ + $rootPath + """."
						Write-Out $msg "darkcyan" 4
						$rootAcl = Get-ACL $rootPath
						$childAcl = Get-ACL $rootPath
						
						#Set Owners
						$scriptUser = $env:username
						$msg = "ACTION`t`tTaking ownership of target path """ + $targetPath + """."
						Write-Out $msg "darkcyan" 4
						Set-FolderOwner $scriptUser $targetPath
						
						$inherit = [system.security.accesscontrol.InheritanceFlags]"ContainerInherit, ObjectInherit"
						$propagation = [system.security.accesscontrol.PropagationFlags]"None"
						$access = [System.Security.AccessControl.AccessControlType]"Allow"
						
						Foreach($user in $users)
							{
								$msg = "Action`t`t`tBuilding ACE for object """ + $user + """."
								Write-Out $msg "darkcyan" 4
								If($user -like "*AllowRead*")
									{$dirAccessRule = new-object System.Security.AccessControl.FileSystemAccessRule($user,"ReadAndExecute, Synchronize",$inherit,$propagation,$access)}
								Else
									{$dirAccessRule = new-object System.Security.AccessControl.FileSystemAccessRule($user,"FullControl",$inherit,$propagation,$access)}
								$dirAccessRule.AccessToString | out-null
								$rootACL.AddAccessRule($dirAccessRule)
							}
						
						#Msgboard Post on literal character problem (by jonwalz)
						##http://www.powershellcommunity.org/Forums/tabid/54/aff/1/aft/35/afv/topic/Default.aspx
						
						#set root acl
						$msg = "ACTION`t`tWriting ACL to target path """ + $targetPath + """."
						Write-Out $msg "darkcyan" 4
						Set-ACL -aclObject $rootAcl -path "$targetPath"
						
						#set child acl's
						$msg = "ACTION`t`tWriting ACL to children path """ + $targetPath + "\*""."
						Write-Out $msg "darkcyan" 4
						$regex = Read-Variable "ACLRegex"
						Get-ChildItem -recurse -force -path $targetPath -erroraction silentlycontinue | `
							%{
								$path = $_.fullname.ToString()
								If($path -match $regex)
									{Set-ACL -aclObject $childAcl -path $path}
								}
						
						#fix Ownership
						Switch($strObjectType)
							{
								"user"
									{
										$destOwner = $null
										$destOwner = $fullUsername
										$msg = "ACTION`t`tGiving ownership of target path """ + $targetPath + """ to """ + $destOwner + """."
										Write-Out $msg "darkcyan" 4
										set-folderOwner $destOwner $targetPath
									}
								"group"
									{
										$destOwner = $null
										$destOwner = "BUILTIN\Administrators"
										$msg = "ACTION`t`tGiving ownership of target path """ + $targetPath + """ to """ + $destOwner + """."
										Write-Out $msg "darkcyan" 4
										set-folderOwner $destOwner $targetPath
									}
								Default
									{
										$msg = "Error`t`tProblem determining who should be the final owner of the targetPath."
										Throw-Warning $msg
										$failThisFunction = $true
									}
							}
					}
			}
		
		$results = $null
		If($failThisfunction -eq $true)
			{$results = $false}
		Else
			{$results = $true}
		return $results
	}

Function Rename-BadFolder($folder)
	{
		$results = $null
		$results = $false
		
		If($folder -eq $null -or $folder -eq "" -or $folder -eq $false)
			{$results = $false}
		ElseIf((test-path $folder) -eq $false)
			{$results = $true}
		Else
			{
				#write-host -f yellow "rename-badfolder working on folder:""" + $folder + """."
				$i = $null
				$i = 0
				$blnStop = $null
				$blnStop = $false
				
				$strTargetDirectory = $null #eg X:\shares\homes2\jpuskar
				$strTargetDirectory = $folder
				
				$strRootFolder = $null #eg X:\shares\homes2\
				$strRootFolder = Trim-OneFolderLevel $strTargetDirectory
				
				$objTarget = $null
				$objTarget = Get-Item $strTargetDirectory
				$strOriginalName = $null #eg jpuskar
				$strOriginalName = $objTarget.Name
				$objTarget = $null
				
				$blnStop = $null
				$blnStop = $false
				Do
					{
						$strCurrentFolderNameAttempt = $null
						$strCurrentFolderNameAttempt = $strOriginalName + ".old-" + $i #eg jpuskar.old-0
						$strCurrentFullPath = $null
						$strCurrentFullPath = $strRootFolder + "\" + $strCurrentFolderNameAttempt
						If((Test-Path $strCurrentFullPath) -eq $true)
							{}
						Else
							{$blnStop = $true}
						$i++
					}
				Until($blnStop -eq $true)
				
				$strDestinationDirectory = $null
				$strDestinationDirectory = $strCurrentFolderNameAttempt
				
				$msg = "ACTION`t`t`tRenaming a folder:"
				Write-Out $msg "darkcyan" 4
				$msg = "INFO`t`t`t  Source Name: " + $strTargetDirectory
				Write-Out $msg "darkcyan" 4
				$msg = "INFO`t`t`t  Destination Name: " + $strDestinationDirectory
				Write-Out $msg "darkcyan" 4
				
				$blnRenamed = $null
				$blnRenamed = $false
				$blnStop = $null
				$blnStop = $false
				$i = $null
				$i = 0
				While($blnRenamed -eq $false -and $blnStop -eq $false)
					{
						$blnRenamed = $null
						$blnRenamed = $false
						$blnPathExists = $null
						$blnPathExists = Test-Path $strTargetDirectory
						If($blnPathExists -eq $true)
							{
								Start-Sleep -milliseconds 1000
								Write-Host -f green -nonewline "."
								$blnRenamed = Rename-Folder $strTargetDirectory $strDestinationDirectory
							}
						Else
							{
								write-host ""
								$blnRenamed = $true
								Break
							}
						If($i -ge 5)
							{
								$blnStop = $true
								write-host ""
								}
						$i++
					}
				
				If((test-path $strTargetDirectory) -eq $true)
					{$results = $false}
				Else
					{$results = $true}
				
				Return $results
			}
	}

Function Rename-Folder($strTargetDirectory,$strDestinationDirectory)
	{
		$results = $null
		$results = $false
		Trap
			{}
		
		$blnAction = $null
		$blnAction = Rename-Item $strTargetDirectory $strDestinationDirectory -ea silentlycontinue
		
		If((Test-Path $strTargetDirectory) -eq $true)
			{$results = $false}
		Else
			{$results = $true}
		Return $results
	}

Function Robocopy-Folder($sourcePath,$targetPath,$switches)
	{
		$CS = $null
		$CS = Gwmi Win32_ComputerSystem -Comp "."
		$localSystem = $null
		$localSystem = $CS.Name
		
		#find source\trgt\command fileserver names
		$sourceFileServer = [regex]::match($sourcePath,'[^\\]+').value
		If($sourceFileServer -eq $null -or $sourceFileServer -eq "")
			{$sourceFileServer = Read-Variable "fileserver"}
		$commandServer = $sourceFileServer
		
		#because of the kerberos double-hop issue, if the source\target servers are different,
		#run the command locally instead of on one of the remote systems.
		$targetFileServer = [regex]::match($targetPath,'[^\\]+').value
		If($targetFileServer -eq $null -or $targetFileServer -eq "")
			{$targetFileServer = Read-Variable "fileserver"}
		If($sourceFileServer -eq $targetFileServer)
			{$commandServer = $localSystem}
		Else
			{$commandServer = $localSystem}
		
		#initialize logging
		$logFilePath = $null
		$logFilePath = Read-Variable "logFilePath"
		$logServer = [regex]::match($logFilePath,'[^\\]+').value
		If($logServer -ne $commandServer)
			{$logFilePath = Read-Variable "alternateLogFilePath"}
		$logFilePath = (Trim-TrailingSlash $logFilePath) + "\Create-Accounts\"
		$logPathTest = Test-Path $logFilePath
		If($logPathTest -eq  $false)
			{new-item $logFilePath -itemType Directory | out-null}
		
		$logFileDate = $null
		$logFileDate = get-date -uformat '%d%m%Y-%H%M-%S'
		$logFileName = $null
		$logFileName = "Robocopy_" + $logFileDate + ".txt"
		$logFileNullName = $null
		$logFileNullName = "Robocopy_" + $logFileDate + "_null.txt"
		$logFileString = $null
		$logFileString = $logFilePath + $logFileName
		$logFileNullString = $null
		$logFileNullString = $logfilePath + $logFileNullName
		$robocopyPath = $null
		$robocopyPath = Read-Variable "pathToRobocopy"
		
		$sourcePath = Convert-UNCPathToSharePath $sourcePath $commandServer
 		$targetPath = Convert-UNCPathToSharePath $targetPath $commandServer
 		$logFileString = Convert-UNCPathToSharePath $logFileString $commandServer
		$logFileNullString = Convert-UNCPathToSharePath $logFileNullString $commandServer
		
		$command = $null
		$command = $robocopyPath + " /LOG:" + $logFileString + " " + """" + $sourcePath + """" + " " + """" + $targetPath + """" + " " + "/MT /R:1 /W:0 /E /NP /DCOPY:T" + " " + $switches
		
		$retCode = $null
		$retCode = Run-RemoteCommand $commandServer $command
		
		If($retcode.GetType().Name -eq "UInt32"){[int32]$retcode = $retcode}
		
		$arrRobocopyReturns = @{}
		$arrRobocopyReturns.Add(0,"No errors occurred, and no copying was done.")
		$arrRobocopyReturns.Add(1,"Files were copied successfully.")
		$arrRobocopyReturns.Add(2,"Some Extra files or directories were detected.")
		$arrRobocopyReturns.Add(4,"Some Mismatched files or directories were detected.")
		$arrRobocopyReturns.Add(8,"Some files or directories could not be copied.")
		$arrRobocopyReturns.Add(16,"Serious error. Robocopy did not copy any files.")
		
		$retMessage = $null
		$possibleRetCodes = $arrRobocopyReturns.Keys
		If($possibleRetCodes -contains $retCode)
			{$retMessage = $arrRobocopyReturns.Get_Item($retCode)}
		Else
			{$retMessage = "Unknown Failure"} 
		
		If($retCode -ge 0 -and $retCode -le 3)
			{
				$msg = "`t`tRobocopy returned code " + $retCode + " with message """ + $retMessage + """."
				Write-Out $msg "darkcyan" 2
			}
		Else
			{
				$msg = "ERROR`t`t`tThe command failed to start with return code " + $retCode + " and messsage """ + $retMessage + """."
				Throw-Warning $msg
				$fail = $true
			}
		
		If($fail -eq $true){$results = $false}
		Else {$results = $true}
		
		Return $results
	}

Function Zip-Folder($source,$dest)
	{
		$fail = $false
		
		#find source\trgt\command fileserver names
		$sourceFS = [regex]::match($source,'[^\\]+').value
		If($sourceFS -eq $null -or $sourceFS -eq "")
			{$sourceFS = Read-Variable "fileserver"}
		$destFS = [regex]::match($dest,'[^\\]+').value
		If($destFS -eq $null -or $destFS -eq "")
			{$destFS = Read-Variable "fileserver"}
		If($sourceFS -eq $destFS)
			{$commandServer = $destFS}
		Else
			{
				$CS = $null
				$CS = Gwmi Win32_ComputerSystem -Comp "."
				$localSystem = $null
				$localSystem = $CS.Name
				$commandServer = $localSystem
			}
		
		#zip the source to the destination
		$PathTo7Zip = Read-Variable "pathTo7Zip"
		$command = $null
		$command = $pathTo7Zip + " a -t7z " + $dest + " " + $source + "\* -r"
		$results = $null
		$results = Run-RemoteCommand $commandServer $command
		
		write-host -f yellow "results: $results"
		
		If($results -eq 0){$results = $true}
		Else{$results = $false}
		
		If($results -eq $false)
			{
				$msg = "WARNING`t`tFailed to run the command."
				Throw-Warning $msg
				$fail = $true
			}
		
		$retval = $null
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $true}
		Return $retval
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
				$csvFileName = "tempCSVFile-" + $script:logFileDateString + ".csv"
				
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

Function CloseXLSX($filename)
	{
		$global:excel.Workbooks.Close($filename)
		$global:excel = $null
	}

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

Function Verify-ZipFile($source,$zipFile)
	{
		$fail = $false
		#get source files -- all word and excel files
		$arrSourceFiles = GCI -recurse $source -force -include "*.docx,*.xlsx,*.pdf" | select name
		$bAllFiles = $false
		If($arrSourceFiles.Count -lt 10)
			{
				$msg = "Info`t`tVery few docx, xlsx, and/or pdf files were found. Verifying all files instead."
				Write-Out $msg "darkcyan" 3
				$arrSourceFiles = GCI -recurse $source -force | select name
				$bAllFiles = $true
			}
		
		#get zip files -- all word and excel files
		$PathTo7Zip = Read-Variable "pathTo7Zip"
		$command = $null
		If($bAllFiles -eq $true)
			{$command = "cmd.exe /c " + $pathTo7Zip + " l """ + $zipFile + """ -r"}
		Else
			{$command = "cmd.exe /c " + $pathTo7Zip + " l """ + $zipFile + """ -r *.docx *.xlsx *.pdf"}
		$msg = "Running the following command on the local system: " + $command
		Write-Out $msg "cyan" 3
		$arrZippedFiles = Invoke-Expression $command
		
		$arrDestFiles = $null
		$arrDestFiles = @()
		$i = 12
		While($i -lt ($arrZippedFiles.count - 2))
				{
					$filePath = $arrZippedFiles[$i].substring(53,($arrZippedFiles[$i].length - 53))
					$arrFilePath = $filePath.Split("\")
					$filename = $arrFilePath[($arrFilePath.Count-1)]
					$arrDestFiles += $filename
					$i++
				}
		
#		$arrSourceFiles | out-host
#		write-host -f green "0000000000000000000000000000000000000"
#		$arrDestFiles | out-host
		
		$i = 0
		$totalMissed = 0
		$totalSource = $arrSourceFiles.Count
		$arrSourceFiles | % {
			$curFile = $_.Name
			If($arrDestFiles -contains $curFile)
				{}
			Else
				{
					$msg = "WARNING`t`tZip file is missing the file named """ + $curFile + """."
					Throw-Warning $msg
					$totalmissed++
				}
		}
		
		If($totalmissed -gt ($totalSource * 0.2))
			{
				$msg = "WARNING`t`tZip file is missing more than 20% of docx, xlsx, and pdf files."
				Throw-Warning $msg
				$fail = $true
			}
		
		$retval = $null
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $true}
		Return $retval
		
	}

Function Delete-Folder($folder)
	{
		$results = $null
		If((test-path $folder) -eq $true)
			{
				#Get target\command fileserver
				$fileServer = [regex]::match($folder,'[^\\]+').value
				If($fileServer -eq $null -or $fileServer -eq "")
					{$fileServer = Read-Variable "fileserver"}
				
				#initialize logging
				$logFilePath = $null
				$logFilePath = Read-Variable "logFilePath"
				$logServer = [regex]::match($logFilePath,'[^\\]+').value
				If($logServer -ne $commandServer)
					{$logFilePath = Read-Variable "alternateLogFilePath"}
				$logFilePath = (Trim-TrailingSlash $logFilePath) + "\Create-Accounts\"
				$logPathTest = Test-Path $logFilePath
				If($logPathTest -eq  $false)
					{new-item $logFilePath -itemType Directory | out-null}
				
				$logFileDate = $null
				$logFileDate = get-date -uformat '%d%m%Y-%H%M-%S'
				$logFileName = $null
				$logFileName = "DirectoryFixer_" + $logFileDate + ".txt"
				$logFileNullName = $null
				$logFileNullName = "Robocopy_" + $logFileDate + "_null.txt"
				$logFileString = $null
				$logFileString = $logFilePath + $logFileName
				
				$LocalFolder = $null
				$LocalFolder = Convert-UNCPathToSharePath $folder $fileserver
				
				[array]$arrSplitPath = $localFolder.Split("\")
				#write-host -f green "arrSplitPath: $arrSplitPath"
				If($arrSplitPath.count -le 5)
					{
						$msg = "WARNING`t`tSanity Check! The script will not delete this folder because the path is not deep enough."
						Throw-Warning $msg
					}
				Else
					{
						$blnFolderExists = $null
						$blnFolderExists = $true
						$blnStop = $null
						$blnStop = $false
						$i = $null
						$i = 0
						While($blnFolderExists -eq $true -and $blnStop -eq $false)
							{
								$blnFolderExists = Test-Path $folder
								#run directory fixer
								$directoryFixerPath = $null
								$directoryFixerPath = Read-Variable "pathToDirectoryfixer"
								$command = $null
								$command = "cmd /c ECHO YES | " + $directoryFixerPath + " " + $LocalFolder + " > " + $logFileString
								$results = $null
								$results = Run-RemoteCommand $fileServer $command
								If($results -eq 0){$results = $true}
								Else{$results = $false}
								
								Start-Sleep -Milliseconds 500
								
								#remove the directory
								$msg = "ACTION`t`tCalling delete on """ + $folder + """. Attempt number : " + ($i + 1) + " of 5." 
								Write-Out $msg "darkcyan" 4
								remove-item -literalpath $folder -recurse -force -ErrorAction silentlycontinue
								
								If($i -ge 4)
									{$blnStop = $true}
									$i++
							}
					}
			}
		
		If((test-path $folder) -eq $true)
			{$results = $false}
		Else
			{$results = $true}
		Return $results
	}

Function Take-FolderOwnership($folder)
	{
		$scriptUser = $env:username
		set-folderOwner $scriptUser $folder
		return $true
	}

Function Set-FolderOwner($sAMAccountName,$targetPath)
	{
		#add "domain\" if needed
		If($sAMAccountName -match "\\")
			{$newOwner = $sAMAccountName}
		Else
			{
				$shortDomain = Read-Variable "domainShort"
		 		$newOwner = $shortDomain + "\" + $sAMAccountName
		 	}
		
 		#Build commands
 		$pathToSubInACL = Read-Variable "pathToSubInACL"
 		
 		If($PathToSubInACL -eq $null -or $pathToSubInACL -eq $false -or $pathToSubInACL -eq "")
 			{
 				$msg = "Error`t`tCould not read the path to SubInACL.exe from the script settings file."
 				Throw-Warning $msg
 				$failThisFunction = $true
 			}
 		
 		$fileServer = [regex]::match($targetPath,'[^\\]+').value
 		$targetPath = Convert-UNCPathToSharePath $targetPath $fileserver
 		
 		$command1 = $pathToSubInACL + " /nostatistic /noverbose /file """ + $TargetPath + """ /setowner=" + $NewOwner
 		$command2 = $pathToSubInACL + " /nostatistic /noverbose /subdirectories """ + $TargetPath + "\*"" /setowner=" + $NewOwner
 		#Run commands
		
		#run first set-owner expression
		$command1 = $pathToSubInACL + " /nostatistic /noverbose /file """ + $TargetPath + """ /setowner=" + $NewOwner
 		$results = $null
		$results = Run-RemoteCommand $fileServer $command1 $true
		If($results -eq 0){$results = $true}
		Else{$results = $false}
		
		#run second second-owner expression
		$command2 = $pathToSubInACL + " /nostatistic /noverbose /subdirectories """ + $TargetPath + "\*"" /setowner=" + $NewOwner
 		$results = $null
		$results = Run-RemoteCommand $fileServer $command2 $true
		If($results -eq 0){$results = $true}
		Else{$results = $false}
		
		Return $results
	}

Function Find-InternalHomeDirectories($sAMAccountName) #SkipECC
	{
		$failThisFunction = $null
		$failThisFunction = $false
		
		$rootsToSearch = Read-Variable "internalHomeDirectoryRoots"
		$affiliations = Read-Variable "homeDirectoryQuotaPaths"
		
		If($rootsToSearch -eq $null -or $affiliations -eq $null)
			{
				Write-Host -f red "WARNING`t`t(f)Find-InternalHomeDirectories depends on a couple settings from (f)Read-Variable which aren't set!!!"
				$failThisFunction = $true
			}
		
		If($failThisFunction -eq $false)
			{
				#build each potential path
				$potentialPaths = $null
				$potentialPaths = @()
				Foreach($root in $rootsToSearch)
					{
						#with affiliation
						Foreach($affiliation in $affiliations)
							{
								$potentialPathToTest = $null
								$potentialPathToTest = $root + $affiliation + "\" + $sAMAccountName
								$potentialPaths += $potentialPathToTest
							}
						
						#without affiliation
						$potentialPathToTest = $null
						$potentialPathToTest = $root + $sAMAccountName
						$potentialPaths += $potentialPathToTest
					}
				
				#Attempt to find the sharepath of the homeDirectory's target.
				$shareName = $null
				$shareName = $sAMAccountName + "$"
				$objSharePath = $null
				$objSharePath = Get-SharePathAsAdminUNC $shareName $fileserver
				If($objSharePath -ne $null)
					{$potentialPaths += $objSharePath}
				Else
					{}
				
				#write-host -f cyan "potential paths" + $potentialPaths
				
				#Test all the paths
				$pathsFound = $null
				$pathsFound = @()
				$potentialPath = $null
				Foreach($potentialPath in $potentialPaths)
					{
						$pathTest = Test-Path $potentialPath
						#Write-Host -f cyan "tested $potentialPath`nresults: $pathTest"
						
						#If the path tests as valid, make sure it's not empty, then add it to $pathsFound.
						If($pathTest -eq $true -and $pathsFound -notcontains $potentialpath)
							{
								#Write-Host -f yellow "found $potentialPath"
								$blnFolderIsEmpty = $null
								$blnFolderIsEmpty = Check-IsFolderEmpty $potentialpath
								If($blnFolderIsEmpty -eq $true -or $blnFolderIsEmpty -eq $null)
									{}
								Else
									{
										$potentialPath = $potentialPath.ToLower()
										If($pathsFound -notcontains $potentialPath)
											{$pathsFound += $potentialPath}
									}
							}
					}
				
				#write-Host -f yellow "Paths Found: $pathsFound"
			}
		
		If($failThisFunction -eq $true)
			{$retval = $false}
		ElseIf($pathsFound.length -ne 0)
			{$retval = $pathsFound}
		Else
			{$retval = $false}
		
		Return $retval
	}

Function Find-OrphanedHomeDirectories($objUser)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		
		$homeDir = Pull-LDAPAttribute $objUser "homeDirectory"
		$fileServer = [regex]::match($homeDir,'[^\\]+').value
		If($fileServer -eq $null -or $fileServer -eq "")
			{$fileServer = Read-Variable "fileserver"}
		
		#retrieve relative home share path
		$sAMAccountName = $null
		$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
		$strShareName = $null
		$strShareName = $sAMAccountName + "$"
		$strHomeSharePath = $null
		$strHomeSharePath = Get-SharePathAsAdminUNC $strShareName $fileserver
		If($strHomeSharePath -eq $false -or $strHomeSharePath -eq $null)
			{
				$warningMsg = "ERROR`t`tCould not get home share path for share """ + $shareName + """."
				Throw-Warning $warningMsg
				$failThisFunction = $true
			}
		Else
			{
				#write-host -f yellow "home share path: $strhomesharepath"
			}
		
		#retrieve all internal home directories
		[array]$arrOrphans = $null
		[array]$arrOrphans = @()
		If($failThisFunction -eq $false)
			{
				$blnOrphansFound = $null
				
				$arrInternalHomeDirectories = $null
				$arrInternalHomeDirectories = Find-InternalHomeDirectories $sAMAccountName
				If($arrInternalHomeDirectories -eq $null)
					{$blnOrphansFound = $false}
			}
			
			#write-host -f red "internal home directories: $arrInternalHomeDirectories"
		
		#add old archived folders
		If($failThisFunction -eq $false)
			{
				#look for archived data
				$strArchiveRoot = $null
				$strArchiveRoot = Read-Variable "archiveRootUNC"
				$strArchiveRoot = Trim-TrailingSlash $strArchiveRoot
				$strArchiveFolder = $null
				[string]$strArchiveFolder = $strArchiveRoot + "\" + $sAMAccountName
				$blnArchiveFolderExists = $null
				$blnArchiveFolderExists = $false
				$blnArchiveFolderExists = Test-Path $strArchiveFolder
				$blnArchiveFound = $null
				$blnArchiveFound = $false
				If($blnArchiveFolderExists -eq $true)
					{
						$folderChildren = Get-ChildItem $strArchiveFolder
						If($folderChildren -is [array])
							{$blnArchiveFound = $true}
						Else
							{$blnArchiveFound = $false}
					}
				Else
					{$blnArchiveFound = $false}
				
				If($blnArchiveFound -eq $true)
					{
						If($arrInternalHomeDirectories -is [array])
							{$arrInternalHomeDirectories += $strArchiveFolder}
						Else
							{
								$tmpArrayMember = $null
								$tmpArrayMember = $arrInternalHomeDirectories
								$arrInternalHomeDirectories = $null
								$arrInternalHomeDirectories = @()
								$arrInternalHomeDirectories += $tmpArrayMember
								$arrInternalHomeDirectories += $strArchiveFolder
								$tmpArrayMember = $null
								}
					}
			}
		
		#write-host -f red "internal home directories: $arrInternalHomeDirectories"
		
		#compare sharepath with internal home directories found, and report all non-sharepath results
		If($failThisFunction -eq $false)
			{
				If($arrInternalHomeDirectories -eq $null)
					{$blnOrphansFound = $false}
				ElseIf($arrInternalHomeDirectories -is [array])
					{
						If($arrInternalHomeDirectories.Count -eq 1)
							{
								$strIntHomeDir = $arrInternalHomeDirectories[0]
								If($strIntHomeDir -eq $strHomeSharePath)
									{}
								Else
									{
										$blnOrphansFound = $true
										$arrOrphans += $strIntHomeDir
									}
							}
						Else
							{
								Foreach($strIntHomeDir in $arrInternalHomeDirectories)
									{
										If($strIntHomeDir -eq $strHomeSharePath)
											{}
										Else
											{
												$blnOrphansFound = $true
												$arrOrphans += $strIntHomeDir
											}
									}
							}
					}
				Else
					{
						$strIntHomeDir = $arrInternalHomeDirectories
						If($strIntHomeDir -eq $strHomeSharePath)
							{}
						Else
							{
								$blnOrphansFound = $true
								$arrOrphans += $strIntHomeDir
							}
					}			
			}
		
		$retval = $null
		If($failThisFunction -eq $true)
			{$retval = $false}
		ElseIf($blnOrphansFound -eq $true)
			{$retval = $arrOrphans}
		Else
			{$retval = $false}
		
		#Write-Host -f red "find-orphans is returning: """ + $retval + """."
		Return $retval
	}

Function Get-SharePathAsAdminUNC($shareName,$fileServer)
	{
		Trap{continue;}
		If($fileServer -eq $null -or $fileServer -eq "")
			{$fileServer = Read-Variable "fileserver"}
		
		$sharePath = Get-SharePath $shareName $fileserver
		$localPath = Convert-SharePathtoUNCPath $sharePath $fileserver
		
		Return $localPath
	}

Function Check-DoesShareExist($shareName,$fileserver)
	{
		If($fileServer -eq $null -or $fileServer -eq "")
			{$fileServer = Read-Variable "fileserver"}
		$shareExists = $null
		$sharePath = $null
		$sharePath = Get-SharePath $shareName $fileserver
		If($sharePath -eq $false -or $sharePath -eq $null)
			{$shareExists = $false}
		Else
			{$shareExists = $true}
		Return $shareExists
	}

Function Create-Share($shareName,$sharePath,$fileserver)
	{
		$newSharePath = $null
		If($sharePath -like "\\*")
			{$newSharePath = Convert-UNCPathToSharePath $sharePath $fileserver}
		Else
			{$newSharePath = $sharePath}
		
		$newSharePath = Trim-TrailingSlash $newSharePath
		
		
		If($fileserver -eq $null -or $fileserver -eq "")
			{$fileserver = Read-Variable "fileserver"}
		$strWMI = $null
		$strWMI = "\\" + $fileserver + "\root\CIMv2:Win32_Share"
		$Win32ShareClass = $null
		$Win32ShareClass = [wmiclass]$strWMI
		$Win32ShareClass.Create($newSharePath,$ShareName,"0",$Null,$Null) | out-null
		
		#Make sure the share was created
		$results = $false
		$i = $null
		$i = 0
		$adminSharePath = $null
		$adminSharePath = Convert-SharePathToUNCPath $newSharePath $fileserver
		While($results -eq $false)
			{
				$results = Check-DoesShareExist $shareName $fileserver
				If($results -eq $true)
					{Break}
				Else
					{
						Sleep -s 1
						$i++
					}
				#Break after 10 tries
				If($i -ge 10)
					{
						$warningMsg = "ERROR`tFailed to create share."
						Throw-Warning $warningMsg
						$failFunction = $true
						Break
					}
			}
		
		If($failFunction -eq $true)	
			{$results = $false}
		
		Return $results
	}

Function Delete-Share($shareName,$fileserver)
	{
		trap{continue;}
		If($fileServer -eq $null -or $fileServer -eq "")
			{$fileServer = Read-Variable "fileserver"}
		$shareExists = $null
		$shareExists = Check-DoesShareExist $shareName $fileserver
		If($shareExists -eq $true)
			{
				$fullShareName = "\\" + $fileserver + "\" + $shareName
				$i = 0
				Do
					{
						#Bind to Share
						$strWMI = $null
						$strWMI = "\\" + $fileServer + "\root\cimv2:win32_share.name='" + $shareName + "'"
						$objShare = $null
						$objShare = [wmi]$strWMI
						#Delete Share
						$objShare.Delete()
						$objShare = $null
						$i++
						
						$shareExists = $null
						$shareExists = Check-DoesShareExist $shareName $fileserver
						If($shareExists -eq $true)
							{
								$retval = $false
							}
					}
				Until($shareExists -eq $false -or $i -ge 25)
				
				$shareExists = $null
				$shareExists = Check-DoesShareExist $shareName $fileserver
				If($shareExists -eq $true)
					{$retval = $false}
				Else
					{$retval = $true}
			}
		Else
			{$retval = $true}
		
		Return $retval
	}

Function Modify-SharePath($shareName,$newPath,$fileserver)
	{
		If($fileServer -eq $null -or $fileServer -eq "")
			{$fileServer = Read-Variable "fileserver"}
		$failThisFunction = $null
		$failThisFunction = $false
		#trap{continue;}
		
		#delete share
		$shareDeleted = $null
		$shareDeleted = Delete-Share $shareName $fileserver
		If($shareDeleted -eq $true)
			{
				$msg = "INFO`t`t`tShare """ + $shareName + """ deleted."
				write-out $msg "darkcyan" 4
			}
		Else
			{
				$warningMag = "ERROR`t`tCould not delete share """ + $shareName + """."
				Throw-Warning $warningMsg
				$failThisFunction = $true
			}
		
		#recreate share
		If($failThisFunction -eq $false)
			{
				$shareCreated = $null
				$shareCreated = Create-Share $shareName $newPath $fileserver
				If($shareCreated -eq $true)
					{
						$msg = "INFO`t`tShare """ + $sharename + """ created at """ + $newPath + """."
						write-out $msg "darkcyan" 4
					}
				Else
					{
						$warningMsg = "ERROR`t`tCould not create share (name: """ + $shareName + """) (path: """ + $newPath + """)."
						Throw-Warning $warningMsg
						$failThisFunction = $true
					}
			}
		
		If($failThisFunction -eq $true)
			{$results = $false}
		Else
			{$results = $true}
		
		Return $results
	}

Function Generate-UserHomeFS ($objUser)
	{
		$homeFS = $null
		$homeFS = Read-Variable "fileserver"
		
		$sQuotaFolder = Find-Quota $objUser
		If($sQuotaFolder -eq "classes" -or $sQuotaFolder -eq "majors")
			{$homeFS = Read-Variable "fileserver-classes"}
		Else
			{$homeFS = Read-Variable "fileserver"}
		
		Return $homeFS
	}

Function Rebuild-Share($shareName,$newSharePath,$objUser)
	{
		$fileserver = Generate-UserHomeFS $objUser
		
		$results = $null
		$results = $false
		
		#change share path if necessary
		$strOldSharePath = Get-SharePathAsAdminUNC $shareName $fileserver
		$msg = "INFO`t`tCurrent share path is """ + $strOldSharePath + """."
		Write-Out $msg "darkcyan" 4
		$msg = "INFO`t`tNew share path will be """ + $newSharePath + """."
		Write-Out $msg "darkcyan" 4
		
		If($strOldSharePath -eq $newSharePath)
			{
				$msg = "INFO`t`tShare path is already correct. Skipping share path modification."
				Write-Out $msg "darkcyan" 4
				$results = $true
			}
		Else
			{
				$results = Modify-SharePath $shareName $newSharePath $fileserver
				If($results -eq $null -or $results -eq "")
					{$results = $false}
				Else
					{
						$newHomedirFS = Generate-UserHomeFS $objUser
						$sAMAccountName = Pull-LDAPAttribute $objUser "sAMAccountName"
						$homeDir = "\\" + $newHomedirFS + "\" + $sAMAccountName + "$"
						$attrName = "homeDirectory"
						$attrValue = $homeDir
						$action = Put-LDAPAttribute $objUser $attrName $attrValue
					}
				
			}
		
		$strOC = $null
		$strOC = Pull-LDAPAttribute $objUser "objectCategory"
		If($strOC -like "*user*" -or $strOC -like "*person*")
			{
				#fix share permissions
				$blnPermissionsFixed = $null
				$blnPermissionsFixed = Fix-HomeSharePermissions $objUser
			}
		ElseIf($strOC -like "*group*")
			{}
		Else
			{
				$msg = "ERROR`t`tCould not determine if the AD object """ + $DN + """ is a user or group."
				Throw-Warning $msg
				$failThisfunction = $true
				$results = $false
			}
		
		Return $results
	}

Function Get-UserHomeFS($objUser)
	{
		$homeDir = Pull-LDAPAttribute $objUser "homeDirectory"
		$fileServer = [regex]::match($homeDir,'[^\\]+').value
		If($fileServer -eq $null -or $fileServer -eq "")
			{$fileServer = Read-Variable "fileserver"}
		$results = $fileserver
		Return $results
	}

Function Get-ShareAccessMask($intAccessMask)
	{
		#REF: http://bsonposh.com/archives/288
		#REF: http://www.eggheadcafe.com/software/aspnet/31909182/useraccountcontrol.aspx
		$strAccessMask = $null
		Switch($intAccessMask)
			{
				2032127 {$strAccessMask = "FullControl"}
				1179785 {$strAccessMask = "Read"}
				1180063 {$strAccessMask = "Read, Write"}
				1179817 {$strAccessMask = "ReadAndExecute"}
				-1610612736 {$strAccessMask = "ReadAndExecuteExtended"}
				1245631 {$strAccessMask = "ReadAndExecute, Modify, Write"}
				1180095 {$strAccessMask = "ReadAndExecute, Write"}
				268435456 {$strAccessMask = "FullControl (Sub Only)"}
				Default {$strAccessMask = $intAccessMask}
			}
		return $strAccessMask
	}

Function Get-SharePath($shareName,$fileserver)
	{
		Trap{continue;}
		If($fileServer -eq $null -or $fileServer -eq "")
			{$fileServer = Read-Variable "fileserver"}
		$strWMI = $null
		$strWMI = "\\" + $fileserver + "\root\cimv2:win32_share.name='" + $shareName + "'"
		$sharePath = $null
		$sharePath = ([wmi]$strWMI).path
		Return $sharePath
	}

Function Build-HomeShareDACL($sAMAccountName)
	{
		#References
		#http://mow001.blogspot.com/2006/05/powershell-import-shares-and-security.html
		#http://thepowershellguy.com/blogs/posh/archive/2007/01/23/powershell-converting-accountname-to-sid-and-vice-versa.aspx
		
		$domain = Read-Variable "domainName_Short"
		$mode = "Full"
		
		$homeDir = Pull-LDAPAttribute $objUser "homeDirectory"
		$fileServer = [regex]::match($homeDir,'[^\\]+').value
		If($fileServer -eq $null -or $fileServer -eq "")
			{$fileServer = Read-Variable "fileserver"}
		
		# Get the needed WMI Classes
		
		$strWMI = $null
		$strWMI = "//" + $fileserver + "/root/cimv2:Win32_SecurityDescriptor"
		$SdObject = [wmiclass]$strWMI
		$sd = $SdObject.CreateInstance()
		#Create Objects for User
		$strWMI = $null
		$strWMI = "//" + $fileserver + "/root/cimv2:Win32_ACE"
		$AceObject = [wmiclass]$strWMI
		$strWMI = $null
		$strWMI = "//" + $fileserver + "/root/cimv2:Win32_Trustee"
		$TrusteeObject = [wmiclass]$strWMI
		$Ace_User = $AceObject.CreateInstance()
		$Trustee_User = $TrusteeObject.CreateInstance()
		#Create Objects for Share Admin's group
		$strWMI = $null
		$strWMI = "//" + $fileserver + "/root/cimv2:Win32_ACE"
		$Ace_ShareAdmins_Object = [wmiclass]$strWMI
		$strWMI = $null
		$strWMI = "//" + $fileserver + "/root/cimv2:Win32_Trustee"
		$Trustee_ShareAdmins_Object = [wmiclass]$strWMI
		$Ace_ShareAdmins = $Ace_ShareAdmins_Object.CreateInstance()
		$Trustee_ShareAdmins = $Trustee_ShareAdmins_Object.CreateInstance()
		
		
		# Make the Trustee for the user
		
		$Trustee_User.Domain = $Domain
		$Trustee_User.Name = $sAMAccountName
		#Get the SID, and convert it into binary form
		$SidAccount_User = New-Object System.Security.Principal.NtAccount($Domain,$sAMAccountName)
		$StringSID_User = $SidAccount_User.Translate([system.security.principal.securityidentifier])
		[byte[]]$BinarySID_User = ,0 * $StringSID_User.BinaryLength
		$StringSID_User.GetBinaryForm($BinarySID_User,0)
		$Trustee_User.SID = $BinarySID_User
		
		# Make the Trustee for the Share Admin's group
		
		$Trustee_ShareAdmins.Domain = $Domain
		$homeDriveAdminsGroup = Read-Variable "homedriveAdminsGroup"
		$Trustee_ShareAdmins.Name = $homeDriveAdminsGroup
		#Get the SID, and convert it into binary form
		$homeDriveAdminsGroup = Read-Variable "homedriveAdminsGroup"
		$SidAccount_ShareAdmins = New-Object System.Security.Principal.NtAccount($Domain,$homeDriveAdminsGroup)
		$StringSID_ShareAdmins = $SidAccount_ShareAdmins.Translate([system.security.principal.securityidentifier])
		[byte[]]$BinarySID_ShareAdmins = ,0 * $StringSID_ShareAdmins.BinaryLength
		$StringSID_ShareAdmins.GetBinaryForm($BinarySID_ShareAdmins,0)
		$Trustee_ShareAdmins.SID = $BinarySID_ShareAdmins
		
		# Set up the ACE for the user
		
		$Ace_User.AccessMask = ([System.Security.AccessControl.FileSystemRights]"FullControl").Value__
		$Ace_User.AceType = 0
		$Ace_User.AceFlags = 3
		$Ace_User.Trustee = $Trustee_User.psobject.baseobject
		
		
		#Set up the ACE for the Share Admin's group.
		
		$Ace_ShareAdmins.AccessMask = ([System.Security.AccessControl.FileSystemRights]"FullControl").Value__
		$Ace_ShareAdmins.AceType = 0
		$Ace_ShareAdmins.AceFlags = 3
		$Ace_ShareAdmins.Trustee = $Trustee_ShareAdmins.psobject.baseobject
		
		# add the ACE(s) to the DACL
		$sd.DACL = @($Ace_User.psobject.baseobject, $Ace_ShareAdmins.psobject.baseobject)
		
		Return $sd
	}

Function Check-FSObjectACLPermissions($sAMAccountName,$targetPath)
	{
		$root = Get-Item $targetPath -force
		$domainShort = Read-Variable "domainShort"
		$homedriveAdminsGroupCN = Read-Variable "homedriveAdminsGroupCN"
		$homeDriveAdminsFull = $domainShort + "\" + $homedriveAdminsGroupCN
		$fullUserName = $domainShort + "\" + $sAMAccountName
		$initialAccessControl = get-acl $targetPath -ea silentlycontinue
		$goodNames = @{`
			($homeDriveAdminsFull) = $false;`
			$fullUserName = $false;`
			"NT AUTHORITY\SYSTEM" = $false;`
			"CREATOR OWNER" = $true;`
			"BUILTIN\Administrators" = $false;
			}
		$ModUsers = @{}
		
		####Check for users to add, remove, or fix
		$aclAccessRule = $initialAccessControl.Access
		$aclCheck = $true
		#Check ownership
		If($initialAccessControl.Owner -ne $fullUserName)
			{$ModUsers.Add($fullUserName,"SetOwner")}
		#If ACL is blank, add all users to modusers
		If($aclAccessRule -eq $null -or $aclAccessRule -eq "")
			{
				Foreach($key in ($goodNames.keys))
					{
						If($ModUsers.Keys -notcontains $key)
							{$ModUsers.Add($key,"Add")}
					}
			}
		Else
			{
				Foreach($Identity in $aclAccessRule)
					{
						[string]$username = $identity.IdentityReference
						[string]$Inheritance = $identity.InheritanceFlags
						#If it's a good name, aknowledge that we touched this name
						If($goodNames.ContainsKey($username) -eq $true)
							{$goodNames.Set_Item($username,$True)}
						
						#
						#
						# BEGIN HOME FOLDER CHECKS
						#
						#
						
						#Check for any users who shouldn't be here.
						If($goodNames.ContainsKey($Username) -eq $false)
							{
								Switch ($Modusers.ContainsKey($username))
									{
										$True {$ModUsers.Set_Item($username,"Remove")}
										$False {$ModUsers.Add($username,"Remove")}
									}
							}
						
						#Check for users with bad inheritence
						ElseIf($Identity.IsInherited -eq $False -and $Username -ne $fullUserName -and $username -ne $homeDriveAdminsFull)
								{
									Switch ($Modusers.ContainsKey($username))
										{
											$True {$ModUsers.Set_Item($username,"Remove")}
											$False {$ModUsers.Add($identity.IdentityReference,"Remove")}
										}
							}
					}
			}
		
		#Check for users who should be here, but aren't
		$keys = $goodNames.keys
		Foreach($key in $keys)
			{
				If($goodNames.$key -eq $false)
					{
						Switch ($Modusers.ContainsKey($key))
								{
									$True {$ModUsers.Set_Item($key,"Add")}
									$False {$ModUsers.Add($key,"Add")}
								}
					}
			}
	
			#
			#
			# END HOME FOLDER CHECKS
			#
			#
		
		$modUsersCount = $ModUsers.Get_Count()
		If($modUsersCount -ne 0)
			{
				$msg = "WARNING`t`t`tPermissions probem at """ + $targetPath + """."
				Write-Out $msg "magenta" 1
				#Display-HashTable $ModUsers
				$RetVal = $false
			}
		
		$modUsersCount = $ModUsers.Get_Count()
		If($modUsersCount -le 0)
			{$retVal = $true}
		Else
			{
				$modUsersKeys = $modUsers.Keys
				$arrMsg = @()
				Foreach($key in $modUsers.Keys)
					{
						$action = $modUsers.$key
						$arrMsg += "INFO`t`t`tACL Change needed. User: """ + $key + """ action: """ + $action + """."
					}
				Foreach($msg in $arrMsg)
					{Write-Out $msg "darkcyan" 4}
				$retVal = $false
			}
		Return $retVal
	}

Function Check-IsFolderEmpty($folderPath)
	{
		Trap{continue;}
		$pathChildren = $null
		$pathChildren = (get-childitem -force $folderPath)
		If($pathChildren -eq $null)
			{$results = $true}
		Else
			{$results = $false}
		Return $results
	}

Function check-RootGroupACLPermissions($groupCN,$targetPath) #DONE
	{
		$domainShort = $null
		$domainShort = Read-Variable "domainname_short"
		
		$strReadGroup = $null
		$strReadGroup = Get-ACLReadGroupCN $groupCN
		$fullReadGroup = $null
		$fullReadGroup = $domainShort + "\" + $strReadGroup
		
		$strWriteGroup = $null
		$strWriteGroup = Get-ACLWriteGroupCN $groupCN
		$fullWriteGroup = $null
		$fullWriteGroup = $domainShort + "\" + $strWriteGroup
		
		$groupDriveAdmins = $null
		$groupDriveAdmins = Read-Variable "groupDriveAdminsGroup"
		$fullGroupDriveAdmins = $null
		$fullGroupDriveAdmins  = $domainShort + "\" + $groupDriveAdmins
		$root = Get-Item $targetPath -force
		$initialAccessControl = get-acl $targetPath -ea silentlycontinue
		$goodNames = @{`
			$fullGroupDriveAdmins = $false;`
			$fullReadGroup = $false;`
			$fullWriteGroup = $false;`
			"NT AUTHORITY\SYSTEM" = $false;`
			"CREATOR OWNER" = $false;`
			"BUILTIN\Administrators" = $false;
			}
		$ModUsers = @{}
		
		#Check for users to add, remove, or fix
		$aclAccessRule = $initialAccessControl.Access
		$aclCheck = $true
		#Check ownership
		If($initialAccessControl.Owner -ne "BUILTIN\Administrators")
			{$ModUsers.Add("BUILTIN\Administrators","SetOwner")}
		Foreach($Identity in $aclAccessRule)
			{
				#Populate Variables
				[string]$Username = $identity.IdentityReference
				[string]$idrf = $null
				[string]$idrf = $identity.IdentityReference
		#		write-host -f green "idrf: $username"
				[string]$Inheritance = $identity.InheritanceFlags
				#If it's a good name, aknowledge that we touched this name
				If($goodNames.ContainsKey($username) -eq $true)
					{$goodNames.Set_Item($username,$True)}
				
				#Check for any users who shouldn't be here.
				If($goodNames.ContainsKey($Username) -eq $false)
					{
						Switch ($Modusers.ContainsKey($username))
							{
								$True {$ModUsers.Set_Item($username,"Remove")}
								$False {$ModUsers.Add($username,"Remove")}
							}
					}
				
				#Check for users with bad inheritence
				ElseIf($Identity.IsInherited -eq $False `
					-and $Username -ne $fullWriteGroup `
					-and $Username -ne $fullReadGroup `
					-and $username -ne $fullGroupDriveAdmins `
					)
					{
						Switch ($Modusers.ContainsKey($username))
							{
								$True {$ModUsers.Set_Item($username,"Remove")}
								$False {$ModUsers.Add($identity.IdentityReference,"Remove")}
							}
					}
				
				#Check the read group's FileSystemRights
				If($idrf -eq $fullReadGroup)
					{
						$fsRights = $null 
						$fsRights = $identity.FileSystemRights
						$strFSRights = $null
						$strFSRights = $fsRights.ToString()
						If($strFSRights -eq "ReadAndExecute, Synchronize")
							{}
						Else
							{
								Switch ($ModUsers.ContainsKey($idrf))
									{
										$True {$ModUsers.Set_Item($idrf,"ChangePermissions")}
										$False {$ModUsers.Add($idrf,"ChangePermissions")}
									}
							}
					}
				
				#Check the write group's FileSystemRights
				If($idrf -eq $fullWriteGroup)
					{
						$fsRights = $null 
						$fsRights = $identity.FileSystemRights
						$strFSRights = $null
						$strFSRights = $fsRights.ToString()
						If($strFSRights -eq "FullControl")
							{}
						Else
							{
								Switch ($Modusers.ContainsKey($idrf))
									{
										$True {$ModUsers.Set_Item($idrf,"ChangePermissions")}
										$False {$ModUsers.Add($idrf,"ChangePermissions")}
									}
							}
					} 
			}
		
		#Check for users missing from the ACL
		$keys = $goodNames.keys
		Foreach($key in $keys)
			{
				If($goodNames.$key -eq $false)
					{
						Switch ($Modusers.ContainsKey($key))
								{
									$True {$ModUsers.Set_Item($key,"Add")}
									$False {$ModUsers.Add($key,"Add")}
								}
					}
			}
		
		
		
			#
			#
			# END HOME FOLDER CHECKS
			#
			#
		
		
		
		$modUsersCount = $ModUsers.Get_Count()
		If($modUsersCount -le 0)
			{$retVal = $true}
		Else
			{
				$modUsersKeys = $modUsers.Keys
				$arrMsg = @()
				Foreach($key in $modUsers.Keys)
					{
						$action = $modUsers.$key
						$arrMsg += "INFO`t`t`tACL Change needed. User: """ + $key + """ action: """ + $action + """."
					}
				Foreach($msg in $arrMsg)
					{Write-Out $msg "darkcyan" 4}
				$retVal = $false
			}
		Return $retVal
	}

Function check-ChildGroupACLPermissions($groupCN,$targetPath) #DONE
	{
		$domainShort = $null
		$domainShort = Read-Variable "domainname_short"
		
		$strReadGroup = $null
		$strReadGroup = Get-ACLReadGroupCN $groupCN
		$fullReadGroup = $null
		$fullReadGroup = $domainShort + "\" + $strReadGroup
		
		$strWriteGroup = $null
		$strWriteGroup = Get-ACLWriteGroupCN $groupCN
		$fullWriteGroup = $null
		$fullWriteGroup = $domainShort + "\" + $strWriteGroup
		
		$GroupDriveAdmins = $null
		$GroupDriveAdmins = Read-Variable "groupDriveAdminsGroup"
		$fullGroupDriveAdmins = $null
		$fullGroupDriveAdmins = $DomainShort + "\" + $groupDriveAdmins
		
		#write-host -f red "HELP HELP HELP"
		$fixedTargetPath = $targetPath # -replace("\~","``~") -replace("\]","``]") -replace("\[","``[") #-replace("\]","``]")
		#verbose msg
		#$msg = "INFO`t`tTesting path: " + $fixedTargetPath
		#write-out $msg "darkcyan" 4
		$root = Get-Item $fixedTargetPath -force
		#trap{continue;}
		$initialAccessControl = get-acl $targetPath
		$goodNames = @{`
			$fullGroupDriveAdmins = $false;`
			$fullReadGroup = $false;`
			$fullWriteGroup = $false;`
			"NT AUTHORITY\SYSTEM" = $false;`
			"CREATOR OWNER" = $false;`
			"BUILTIN\Administrators" = $false;
			}
		
		$ModUsers = @{}
		
		#Check ownership
		If($initialAccessControl.Owner -ne "BUILTIN\Administrators")
			{$ModUsers.Add("BUILTIN\Administrators","SetOwner")}
		#Check for users to add, remove, or fix
		$aclAccessRule = $null
		$aclAccessRule = $initialAccessControl.Access
		$strAccessRule = $null
		$strAccessRule = $initialAccessControl.AccessToString
		#if the ACL is blank, add all users
		If($strAccessRule -eq $null -or $strAccessRule -eq "")
			{
				Foreach($key in ($goodNames.keys))
					{
						$ModUsers.Add($key,"Add")
					}
			}
		Else
			{
				$aclCheck = $true
				Foreach($Identity in $aclAccessRule)
					{
						[string]$Username = $identity.IdentityReference
						[string]$Inheritance = $identity.InheritanceFlags
						If($goodNames.ContainsKey($username) -eq $true)
							{$goodNames.Set_Item($username,$True)}
						#Check for any users who shouldn't be here.
						If($goodNames.ContainsKey($Username) -eq $false)
							{
								Switch($Modusers.ContainsKey($username))
									{
										$True {$ModUsers.Set_Item($username,"Remove")}
										$False {$ModUsers.Add($username,"Remove")}
									}
							}
						#Check for users with bad inheritence
						ElseIf($Identity.IsInherited -eq $False)
							{
								Switch ($Modusers.ContainsKey($username))
									{
										$True {$ModUsers.Set_Item($username,"Remove")}
										$False {$ModUsers.Add($username,"Remove")}
									}
							}
						#If we have errors, stop.
						$modUsersCount = $ModUsers.Get_Count()
						If($modUsersCount -ne 0)
							{
								$msg = "Info`t`tACL Test failure at """ + $targetPath + """."
								Write-Out $msg "darkcyan" 4
								$ModUsers.GetEnumerator() | out-host
								$RetVal = $false
								Break
							}
					}
			}
		$modUsersCount = $ModUsers.Get_Count()
		If($modUsersCount -eq 0){$retVal = $true}
		Else
			{
				$modUsersKeys = $modUsers.Keys
				$arrMsg = @()
				Foreach($key in $modUsers.Keys)
					{
						$action = $modUsers.$key
						$arrMsg += "INFO`t`t`tACL Change needed. User: """ + $key + """ action: """ + $action + """."
					}
				Foreach($msg in $arrMsg)
					{Write-Out $msg "darkcyan" 4}
				$retVal = $false
			}
		Return $retVal
	}