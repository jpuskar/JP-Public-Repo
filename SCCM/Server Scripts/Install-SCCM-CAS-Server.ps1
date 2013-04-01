##Global vars (user-settable)
$hshDrivesNeeded = $null
$hshDrivesNeeded = @{"C" = 100;"D" = 30;"E" = 17;"F" = 100} #in GB
$sInstallFilesPath = "C:\Install_Files"

#$siteCode = "TES"
#$siteName = "Test Primary Site"

$siteCode = "CAS"
$siteName = "Dev Central Admin Site"
$casServerFqdn = "dev-sccm.local"

$domainShort = "dev-sccm"
$domainSuffix = "dev-sccm.local"
$aclGroupOuDn = "OU=Security Groups,DC=dev-sccm,DC=local"
$roleGroupOuDn = "OU=Security Groups,DC=dev-sccm,DC=local"
$serviceAccountsOUDN = "OU=Service Accounts,DC=dev-sccm,DC=local"
$dnSuffix = "DC=dev-sccm,DC=local"

#build action set
If(($env:computername) -like "*CAS*")
	{$bCASInstall = $true}
Else
	{
		If($CasServerFqdn -eq $null -or $CasServerFqdn -eq "")
			{
				$msg = "Error`tPlease specify CasServerFqdn as a variable and rerun the script."
				Write-host -f magenta $msg
				Exit
			}
		$bCASInstall = $false
	}

$actions = @()
$actions += "preUpgradeCheck"
$actions += "createSccmGroups"
$actions += "serverConfig"
$actions += "configureSystemsManagementContainer"
If($bCasInstall -eq $false)
	{
		$actions += "createSCCMUsers"
		$actions += "createSCCMShares"
	}
$actions += "installDotNet35"
$actions += "installDotNet4"
$actions += "installSQL2008"
$actions += "configureSQL"
$actions += "installSCCMRoles"
$actions += "Configure-IISForSCCM"
$actions += "installWSUS"
$actions += "installWSUS-kb2734608"
$actions += "install-SubCA"
$actions += "Configure-SubCA"
$actions += "download-sccm-prereqs"
$actions += "install-sccmsiteserver"
$actions += "update-sccm-cu2"
If($bCasInstall -eq $false){$actions += "configure-webdav-dirbrowsing"}


$sInstallFilesPath = $sInstallFilesPath.TrimEnd("\")
$bFail = $false
#references
. .\AD-Functions.ps1
Import-Module ServerManager



###===========FS Functions Begin ======

Function Build-SourceShareDACL($sccmServerName,$hshUserAccess)
	{
		#References
		#http://mow001.blogspot.com/2006/05/powershell-import-shares-and-security.html
		#http://thepowershellguy.com/blogs/posh/archive/2007/01/23/powershell-converting-accountname-to-sid-and-vice-versa.aspx
		$domain = $domainShort
		$mode = "Full"
		$targetServer = $sccmServerName
		
		# Get the needed WMI Classes
		$strWMI = $null
		$strWMI = "//" + $targetServer + "/root/cimv2:Win32_SecurityDescriptor"
		$SdObject = [wmiclass]$strWMI
		$sd = $SdObject.CreateInstance()
		#Create Objects for SCCM Server AD Account
		$strWMI = $null
		$strWMI = "//" + $targetServer + "/root/cimv2:Win32_ACE"
		$AceObject = [wmiclass]$strWMI
		$strWMI = $null
		$strWMI = "//" + $targetServer + "/root/cimv2:Win32_Trustee"
		$TrusteeObject = [wmiclass]$strWMI
		$Ace_SccmServer = $AceObject.CreateInstance()
		$Trustee_SCCMServer = $TrusteeObject.CreateInstance()
		
		#Start the security descriptor
		$SdDaclList = @()
		$Sd.DACL = @()
				
		$users = $hshUserAccess.Keys
		$users | % {
			#Create Objects for SCCM Server SYSTEM Account
			$strWMI = $null
			$strWMI = "//" + $targetServer + "/root/cimv2:Win32_ACE"
			$AceObjectClass = [wmiclass]$strWMI
			$strWMI = $null
			$strWMI = "//" + $targetServer + "/root/cimv2:Win32_Trustee"
			$TrusteeObjectClass = [wmiclass]$strWMI
			$AceObject = $AceObjectClass.CreateInstance()
			$TrusteeObject = $TrusteeObjectClass.CreateInstance()
			
			$domain = $_.Split("\")[0]
			If($domain -like "builtin" -or $domain -like ".")
				{$domain = $null}
			$name = $_.Split("\")[1]
			$rights = $hshUserAccess.$_
			
			#Get the SID, and convert it into binary form
			$TrusteeObject.Domain = $domain
			$TrusteeObject.Name = $name
			
			$SidAccountObject = New-Object System.Security.Principal.NtAccount($domain,$name)
			$StringSid = $SidAccountObject.Translate([system.security.principal.securityidentifier])
			[byte[]]$BinarySid = ,0 * $StringSid.BinaryLength
			$StringSid.GetBinaryForm($BinarySid,0)
			$TrusteeObject.SID = $BinarySid
			
			#Set up the ACE for the sccm server system account.
			#ref \ access masks: http://blogs.msdn.com/b/helloworld/archive/2008/06/10/common-accessmask-value-when-configuring-share-permission-programmatically.aspx
			If($rights -like "read"){$AceObject.AccessMask = 1179817} #read and execute
			ElseIf($rights -like "writelogs"){$AceObject.AccessMask = 1245631} #read, modify, write
			Else{$AceObject.AccessMask = ([System.Security.AccessControl.FileSystemRights]$rights).Value__}
			$AceObject.AceType = 0
			$AceObject.AceFlags = 3
			$AceObject.Trustee = $TrusteeObject.psobject.baseobject
			
			$SdDaclList += ($AceObject.psobject.baseobject)
		}
		
		$sd.DACL = $sdDaclList
		Return $sd
	}

Function Set-FolderPermissions($targetPath,$hshUserAccess,$optional_rootPath)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		
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
						
						$users = $hshUserAccess.Keys
						Foreach($user in $users)
							{
								If($user -eq "BUILTIN\SYSTEM")
									{}
								Else
									{
										$rights = $hshUserAccess.$user
										If($rights -like "*read*"){$rights = "ReadAndExecute, Synchronize"}
										ElseIf($rights -like "*writelogs*"){$rights = "AppendData, Traverse, CreateFiles, Write, WriteData, WriteAttributes"}
										$msg = "Action`t`t`tBuilding ACE for object """ + $user + """."
										Write-Out $msg "darkcyan" 4
										$dirAccessRule = new-object System.Security.AccessControl.FileSystemAccessRule($user,$rights,$inherit,$propagation,$access)
										$dirAccessRule.AccessToString | out-null
										$rootACL.AddAccessRule($dirAccessRule)
									}
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
						$regex = "^[-a-z_0-9()\=\#\,\;\~\@\+\{\}\!\&':\%\$\\\s.]*[a-zA-Z0-9()\{\}\@\$\%\^\&\-\+\=\!\~\#\,\`\'\;]$"
						Get-ChildItem -recurse -force -path $targetPath -erroraction silentlycontinue | `
							% {
								$path = $_.fullname.ToString()
								If($path -match $regex)
									{Set-ACL -aclObject $childAcl -path $path}
								}
						
						#fix Ownership
						$destOwner = $null
						$destOwner = "BUILTIN\Administrators"
						$msg = "ACTION`t`tGiving ownership of target path """ + $targetPath + """ to """ + $destOwner + """."
						Write-Out $msg "darkcyan" 4
						set-folderOwner $destOwner $targetPath
					}
			}
		
		$results = $null
		If($failThisfunction -eq $true)
			{$results = $false}
		Else
			{$results = $true}
		return $results
	}

Function Set-FolderOwner($sAMAccountName,$targetPath)
	{
		$fileServer = $env:computername
		
		#add "domain\" if needed
		If($sAMAccountName -match "\\")
			{$newOwner = $sAMAccountName}
		Else
			{
				$shortDomain = $domainShort
		 		$newOwner = $shortDomain + "\" + $sAMAccountName
		 	}
		
 		#Build commands
 		$pathToSubInACL = "F:\Shares\subinacl.exe"
 		If($PathToSubInACL -eq $null -or $pathToSubInACL -eq $false -or $pathToSubInACL -eq "")
 			{
 				$msg = "Error`t`tCould not read the path to SubInACL.exe from the script settings file."
 				Throw-Warning $msg
 				$failThisFunction = $true
 			}
 		
 		$command1 = $pathToSubInACL + " /nostatistic /noverbose /file """ + $TargetPath + """ /setowner=" + $NewOwner
 		$command2 = $pathToSubInACL + " /nostatistic /noverbose /subdirectories """ + $TargetPath + "\*"" /setowner=" + $NewOwner
 		#Run commands
		
		#run first set-owner expression
		$command1 = $pathToSubInACL + " /nostatistic /noverbose /file """ + $TargetPath + """ /setowner=" + $NewOwner
 		$results = $null
		$results = Run-RemoteCommand $fileServer $command1
		
		#run second second-owner expression
		$command2 = $pathToSubInACL + " /nostatistic /noverbose /subdirectories """ + $TargetPath + "\*"" /setowner=" + $NewOwner
 		$results = $null
		$results = Run-RemoteCommand $fileServer $command2
		Return $results
	}

Function Create-Share($shareName,$sharePath,$fileserver)
	{
		$newSharePath = $null
		If($sharePath -like "\\*")
			{$newSharePath = Convert-UNCPathToSharePath $sharePath $fileserver}
		Else
			{$newSharePath = $sharePath}
		[string]$newSharePath = Trim-TrailingSlash $newSharePath
		
		If($fileserver -eq $null -or $fileserver -eq "")
			{$fileserver = $env:computername}
		$strWMI = $null
		$strWMI = "\\" + $fileserver + "\root\CIMv2:Win32_Share"
		
		$Win32ShareClass = $null
		$Win32ShareClass = [wmiclass]$strWMI
		
		$action = $Win32ShareClass.Create($newSharePath,$ShareName,"0",$Null,$Null)
		
		#Make sure the share was created
		$results = $false
		$i = $null
		$i = 0
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

Function Check-DoesShareExist($shareName,$fileserver)
	{
		If($fileServer -eq $null -or $fileServer -eq "")
			{$fileServer = $env:computername}
		$shareExists = $null
		$sharePath = $null
		$sharePath = Get-SharePath $shareName $fileserver
		If($sharePath -eq $false -or $sharePath -eq $null)
			{$shareExists = $false}
		Else
			{$shareExists = $true}
		Return $shareExists
	}

Function Get-SharePath($shareName,$fileserver)
	{
		Trap{continue;}
		If($fileServer -eq $null -or $fileServer -eq "")
			{$fileServer = $env:computername}
		$strWMI = $null
		$strWMI = "\\" + $fileserver + "\root\cimv2:win32_share.name='" + $shareName + "'"
		$sharePath = $null
		$sharePath = ([wmi]$strWMI).path
		Return $sharePath
	}

###===========FS Functions End ========

Function PreUpgradeCheck()
	{
		Write-host -f cyan "= Performing Pre-Install System Check ="
		$bFail = $false
		
		###Check Drives
		Write-host -f cyan "== Validating system drives =="
		
		
		$oSysVolumes = $null
		$oSysVolumes = gwmi win32_Volume | where {$_.DriveType -eq 3 -and $_.DriveLetter -ne $null}
		$hshSysVolumes = @{}
		$oSysVolumes | % {
			$hshSysVolumes.Add(($_.DriveLetter).Substring(0,1),($_.capacity * 9.31323e-10))
		}
		
		$hshDrivesNeeded.Keys | Sort | % {
			If ($hshSysVolumes.Keys -notcontains $_)
				{
					$msg = "`tERROR`tThe system does not have a drive letter """ + $_ + """ with at least " + $hshDrivesNeeded.$_ + "GB free space."
					write-host -f magenta $msg
				}
			ElseIf($hshSysVolumes.$_ -lt ($hshDrivesNeeded.$_ * 0.95)) # give a little bit of wiggle room
						{
							$msg = "`tERROR`tThe volume on drive letter """ + $_ + """ must have at least " + $hshDrivesNeeded.$_ + "GB free space."
							Write-host -f magenta $msg
							$bFail = $true
						}
			Else
				{
					$msg = "`tDrive letter """ + $_ + """ meets the requirement of " + $hshDrivesNeeded.$_ + "GB free space."
					write-host -f green $msg
				}
		}
		
		
		### Validating Prereq files and folders
		Write-host -f cyan "== Validating Prereq Files and Folders =="
		
		$arrFilesNeeded = @()
		$arrFilesNeeded += "dotNetFx40_Full_x86_x64.exe"											#.net 4 extended standalone installer
		$arrFilesNeeded += "WSUS30-KB972455-x64.exe"													#WSUS 3.0 SP2
		$arrFilesNeeded += "WSUS-KB2734608-x64.exe"														#WSUS Hotfix
		$arrFilesNeeded += "subinacl.exe"																			#for share creation script
		$arrFilesNeeded += "MicrosoftDeploymentToolkit2012_x64.msi"						#MDT 2012 u1
		#$arrFilesNeeded += "AD-Functions.ps1"																	#Powershell AD Plugins written by JP
		$arrFilesNeeded += "capolicy.inf"
		$arrFilesNeeded += "SQLServer2008R2Std_wSP2\setup.exe"								#SQL
		$arrFilesNeeded += "CustomSccmSqlInstall.ini"													#SQL SCCM Custom Setup
		$arrFilesNeeded += "SCCM 2012\SMSSETUP\BIN\X64\setupdl.exe" 					#SCCM Prereqs Downloader
		$arrFilesNeeded += "SCCM 2012\SMSSETUP\BIN\X64\setup.exe" 						#SCCM Installer Proper
		$arrFilesNeeded += "SCCMDownloads"																		#SCCM prereq downloads folder
		$arrFilesNeeded += "SCCM 2012\SMSSETUP\BIN\I386\AdminConsole.msi"			#SCCM Console
		$arrFilesNeeded += "SCCM 2012 CU2\configmgr2012-rtm-cu2-kb2780664-x64-enu.msi"	#Server CU2
		$arrFilesNeeded += "SCCM 2012 CU2\configmgr2012adminui-rtm-kb2780664-i386.msp"	#Console CU2
		
		$arrFilesNeededFullPath = @()
		$arrFilesNeededFullPath = $arrFilesNeeded | % {$sInstallFilesPath + "\" + $_}
		
		If((Test-Path $sInstallFilesPath) -eq $false)
			{$msg = "`tError`tThe prereq files path """ + $sInstallFilesPath + """ does not exist."
				Write-host -f magenta $msg
				$bFail = $true
			}
		Else
			{
				$installFiles = $null
				$installFiles = dir $sInstallFilesPath -recurse | % {$_.FullName}
				$arrFilesNeededFullPath | % {
					If ($InstallFiles -notcontains $_)
						{
							$msg = "`tError`tInstall files path does not contain required file """ + $_ + """."
							Write-host -f magenta $msg
							$bFail = $true
						}
					Else
						{
							$msg = "`tInstall files path contains required file """ + $_ + """."
							write-host -f green $msg
						}
				}
			}
		
		$msg = "== Checking Powershell Modules =="; write-host -f cyan $msg
		$adMod = $false
		Try {Import-Module ActiveDirectory -ea silentlycontinue}
		Finally {Get-Module | % {If($_.Name -eq "ActiveDirectory"){$adMod = $true}}}
		
		If($adMod -eq $false)
			{
				$msg = "`t* Installing AD Powershell Module."; Write-Host $msg
				$action = Add-WindowsFeature RSAT-AD-Powershell
				
				$msg = "`t* Please close this powershell session and re-open powershell to initialize the AD Powershell module."
				Write-host -f magenta $msg
				$bFail = $true
			}
		Else
			{$msg = "`t* Loaded ActiveDirectory module."; write-host -f green $msg}
		
		
		#Test CAS SQL Connectivity
		If($bCASInstall -eq $false)
			{
				$msg = "== Testing CAS SQL Connectivity =="
				Write-Host -f cyan $msg
				$action = $null
				$action = Check-CasConnectivity
				If($action -eq $true)
					{$msg = "`tCAS Connectivity Verfied."; Write-Host -f green $msg}
				Else
					{
						$msg = "`tError`tCannot connect to the cas at """ + $casServerFQDN + """."; write-host -f magenta $msg
						$bFail = $true
					}
			}
		
		If($bFail -eq $false)
			{
				$msg = "== Testing for Schema Updates =="
				write-host -f cyan $msg
				$schemaExtended = $false
				$schemaObjects = Get-ADObject -SearchBase ((Get-ADRootDSE).schemaNamingContext) -SearchScope OneLevel -Filter * -Property  name
				$schemaObjects | % {If($_.Name -eq "MS-SMS-Site"){$schemaExtended = $true}}
				If($schemaExtended -eq $true)
					{$msg = "`tSchema has been extended for SCCM."; Write-Host -f green $msg}
				Else
					{
						$msg = "`tThe schema has not been extended for SCCM."; Write-Host -f magenta $msg
						$bFail = $true
					}
			}
		
		$retval = $true
		If($bFail -eq $true)
			{$retval = $false}
		Return $retval
	}

Function Check-CasConnectivity()
	{
		$bFail = $false
		
		$SQLServer = $casServerFqdn.ToLower()
		$SQLDBName = "master"
		$SqlQuery1 = "select @@Version"
		
		$SqlConnection = New-Object System.Data.SqlClient.SqlConnection
		$SqlConnection.ConnectionString = "Server = " + $SQLServer + "; Database = master; Integrated Security = True"
		
		$SqlCmd1 = New-Object System.Data.SqlClient.SqlCommand
		$SqlCmd1.CommandText = $SqlQuery1
		$SqlCmd1.Connection = $SqlConnection
		$SqlCmd1.CommandTimeout = 5
		
		$SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
		$SqlAdapter.SelectCommand = $SqlCmd1
		$DataSet = New-Object System.Data.DataSet
		Try{$SqlAdapter.Fill($DataSet)}
		Catch{$bFail = $true}
		
		$action = $SqlConnection.Close()
		
		If($bFail -eq $true){$retval = $false}
		Else{$retval = $true}
		Return $retval
	}

Function Create-SCCMGroups()
	{
		$bFail = $false
		#Create accounts and shares for SCCM
		$msg = "== Creating Security Groups for SCCM =="
		write-host -f cyan $msg
		
		#test vars
		$dnFail = $null
		$dnFail = $false
		If((Check-DNExists $aclGroupOuDn) -eq $false)
			{
				$dnFail = $true
				Write-Host -f magenta "Failed to find ACL Group DN at $aclGroupOuDn."
			}
		If((Check-DNExists $aclGroupOuDn) -eq $false)
			{
				$dnFail = $true
				Write-Host -f magenta "Failed to find role Group DN at $roleGroupOuDn."
			}
		If($dnFail -eq $true)
			{bFail = $true}
		
		#Create Initial Groups
		$aclGroupNames = @()
		$aclGroupNames += "ACL_SCCM-" + $siteCode + "1_SourceShare_AllowRead"
		$aclGroupNames += "ACL_SCCM-" + $siteCode + "1_SourceShare_AllowReadWrite"
		$aclGroupNames += "ACL_SCCM-" + $siteCode + "1_PrivateSourceShare_AllowRead"
		$aclGroupNames += "ACL_SCCM-" + $siteCode + "1_PrivateSourceShare_AllowReadWrite"
		$aclGroupNames += "ACL_SCCM_" + $siteCode + "_AutoEnrollCertificates"
		$aclGroupNames += "ACL_SCCM_" + $siteCode + "_PowerUsers"
		$aclGroupNames += "ACL_SCCM_" + $siteCode + "_SiteAdministrators"
		$aclGroupNames += "ADM_" + $env:computername
		
		$roleGroupNames = @()
		$roleGroupNames += $siteCode + " SCCM Admins"
		$roleGroupNames += $siteCode + " SCCM Users"
		$roleGroupNames += $siteCode + " Computers"
		
		#ACL's
		If($bFail -eq $false)
			{
				$aclGroupNames | % {
					$action = $false
					$cn = Sanitize-GroupCN $_
					If((Check-DoesGroupExist $cn) -eq $false)
						{
							$action = Create-Group $cn $aclGroupOuDn
							If($action -eq $false)
								{
									Write-Host -f magenta "ERROR`tFailed to create group $cn."
									$bFail = $true
								}
							Else
								{Write-Host -f green "`tCreated group $cn."}
						}
					Else
						{Write-Host -f green "`tGroup $cn already exists."}
					
					$DN = Get-DNbyCN $cn
					$objGroup = [adsi]("LDAP://" + $DN)
					$sAMAccountName = Pull-LDAPAttribute $objGroup "sAMAccountName"
					If($sAMAccountName -ne $cn)
						{
							Write-host -f green "`tSetting group $cn sAMAccountName."
							$action = Put-LDAPAttribute $objGroup "sAMAccountName" $cn
						}
					
				}
			}
		
		#Roles
		If($bFail -eq $false)
			{
				$roleGroupNames | % {
					$action = $false
					$cn = Sanitize-GroupCN $_
					If((Check-DoesGroupExist $cn) -eq $false)
						{
							$action = Create-Group $cn $roleGroupOuDn
							If($action -eq $false)
								{
									Write-Host -f magenta "`tERROR`tFailed to create group $cn."
									Exit
								}
							Else
								{Write-Host -f green "`tCreated group $cn."}
						}
					Else
						{Write-Host -f green "`tGroup $cn already exists."}
						
					$DN = Get-DNbyCN $cn
					$objGroup = [adsi]("LDAP://" + $DN)
					$sAMAccountName = Pull-LDAPAttribute $objGroup "sAMAccountName"
					If($sAMAccountName -ne $cn)
						{
							Write-host -f green "Setting group $cn sAMAccountName."
							$action = Put-LDAPAttribute $objGroup "sAMAccountName" $cn
						}
				}
			}
		
		#Nest SCCM Admins into Read-Writes and ADM
		If($bFail -eq $false)
			{
				$sourceCNs = @()
				$sourceCNs += "ADM_" + $env:computername
				$sourceCNs += "ACL_SCCM-" + $siteCode + "1_SourceShare_AllowReadWrite"
				$sourceCNs += "ACL_SCCM-" + $siteCode + "1_PrivateSourceShare_AllowReadWrite"
				
				$mbrCn = $siteCode + " SCCM Admins"
				$mbrDn = Get-DNbyCN $mbrCn
				
				$sourceCNs | % {
					$action = $false
					$sourceDN = Get-DNbyCN $_
					$action = Add-ToGroup $mbrDN $sourceDN
					If($action -eq $false)
						{Write-Host -f magenta "`tERROR`tFailed to add $mbrCN to the group $_."; $bFail = $true}
					Else
						{Write-Host -f green "`tSuccessfully added $mbrCN to the group $_."}
				}
			}
		
		#Nest SCCM Users into Read-Writes
		If($bFail -eq $false)
			{
				$sourceCNs = @()
				$sourceCNs += "ACL_SCCM-" + $siteCode + "1_SourceShare_AllowReadWrite"
				$sourceCNs += "ACL_SCCM-" + $siteCode + "1_PrivateSourceShare_AllowReadWrite"
				
				$mbrCn = $siteCode + " SCCM Users"
				$mbrDn = Get-DNbyCN $mbrCn
				
				$sourceCNs | % {
					$action = $false
					$sourceDN = Get-DNbyCN $_
					$action = Add-ToGroup $mbrDN $sourceDN
					If($action -eq $false)
						{Write-Host -f magenta "`tERROR`tFailed to add $mbrCN to the group $_."; $bFail = $true}
					Else
						{Write-Host -f green "`tSuccessfully added $mbrCN to the group $_."}
				}
			}
		
		#Next SCCM Computers into ACL...AutoEnrollCerts
		If($bFail -eq $false)
			{
				$sourceCNs = @()
				$sourceCNs += "ACL_SCCM_" + $siteCode + "_AutoEnrollCertificates"
				
				$mbrCn = $siteCode + " Computers"
				$mbrDn = Get-DNbyCN $mbrCn
				
				$sourceCNs | % {
					$action = $false
					$sourceDN = Get-DNbyCN $_
					$action = Add-ToGroup $mbrDN $sourceDN
					If($action -eq $false)
						{Write-Host -f magenta "`tERROR`tFailed to add $mbrCN to the group $_."; $bFail = $true}
					Else
						{Write-Host -f green "`tSuccessfully added $mbrCN to the group $_."}
				}
			}
		
		#Nest SCCM Admins into Site Admins
		If($bFail -eq $false)
			{
				$sourceCNs = @()
				$sourceCNs = "ACL_SCCM_" + $siteCode + "_SiteAdministrators"
				
				$mbrCn = $siteCode + " SCCM Admins"
				$mbrDn = Get-DNbyCN $mbrCn
				
				$sourceCNs | % {
					$action = $false
					$sourceDN = Get-DNbyCN $_
					$action = Add-ToGroup $mbrDN $sourceDN
					If($action -eq $false)
						{Write-Host -f magenta "`tERROR`tFailed to add $mbrCN to the group $_."; $bFail = $true}
					Else
						{Write-Host -f green "`tSuccessfully added $mbrCN to the group $_."}
				}
			}
		
		#Nest SCCM Users into PowerUsers
		If($bFail -eq $false)
			{
				$sourceCNs = @()
				$sourceCNs = "ACL_SCCM_" + $siteCode + "_PowerUsers"
				
				$mbrCn = $siteCode + " SCCM Users"
				$mbrDn = Get-DNbyCN $mbrCn
				
				$sourceCNs | % {
					$action = $false
					$sourceDN = Get-DNbyCN $_
					$action = Add-ToGroup $mbrDN $sourceDN
					If($action -eq $false)
						{Write-Host -f magenta "`tERROR`tFailed to add $mbrCN to the group $_."; $bFail = $true}
					Else
						{Write-Host -f green "`tSuccessfully added $mbrCN to the group $_."}
				}
			}
		
		$retval = $true
		If($bFail -eq $true){$retval = $false}
		Return $retval
	}

Function Check-LocalAdminsForGroupCN($groupCN)
	{
		$adminsGroup = [ADSI]("WinNT://./Administrators,group")   
		$oMembers = $adminsGroup.psbase.invoke("Members") 
		$admins = @()
		$oMembers | % {$admins += $_.GetType().InvokeMember("Name",'GetProperty', $null, $_, $null)}
		If ($admins -contains $admGroupCN)
			{$retval = $true}
		Else
			{$retval = $false}
		Return $retval
	}

Function serverConfig()
	{
		$bFail = $false
		$msg = "== Add ADM_SCCM group to Local Admin =="
		Write-Host -f cyan $msg
		$localHost = $env:COMPUTERNAME
		$admGroupCN = "ADM_" + $env:computername
		If((Check-LocalAdminsForGroupCN $admGroupCN) -eq $false) {
			([ADSI]"WinNT://./Administrators,group").Add("WinNT://$domainShort/$admGroupCN")
    }
		If((Check-LocalAdminsForGroupCN $admGroupCN) -eq $true)
			{$msg = "`tSuccessfully added " + $admGroupCN + " to local admins."; write-host -f green $msg}
		Else
			{$msg = "`tError`tCould not add " + $admGroupCN + " to local admins."; write-host -f magenta $msg; $bFail = $true}
			
		$msg = "== Disable Host Firewall =="
		Write-Host -f cyan $msg
		$cmdPath = "c:\windows\system32\netsh.exe"
		$cmdArgs = "advfirewall set allprofiles state off"
		$p = Start-Process $cmdPath -ArgumentList $cmdArgs -Wait -NoNewWindow -PassThru -RedirectStandardOutput "out.txt"
		$exitCode = $p.ExitCode
		If($exitCode -eq 0 -or $exitcode -eq 3010)
			{$msg = "`tNetsh has completed with exit code " + $exitcode + "."; write-host -f green $msg}
		Else {
			$msg = "`tError`tNetsh failed with return code: " + $exitCode + "."
			Write-host -f magenta $msg
			$bFail = $true
		}
		
		$Retval = $true
		If($bFail -eq $true){$retval = $false}
		Return $retval
	}

Function Create-SCCMUsers
	{
		$bFail = $false
		write-host -f cyan "== Creating SCCM Users =="
		
		$destinationOU = $serviceAccountsOUDN
		If((Check-DNExists($destinationOU)) -eq $false)
			{
				$msg = "`tError`tDestination service accounts OU """ + $destinationOU + """ does not exist!"; Write-host -f magenta $msg
				$bFail = $true
			}
		
		$arrUsers = @()
		$arrUsers += "sccm-" + $siteCode + "-naa"
		$arrUsers | % {
			If($bFail -eq $false)
				{
					$blnUserExists = Check-DoesUserExist $_
					If($blnUserExists -eq $true -and $bFail -eq $false)
						{$msg = "`tUser """ + $_ + """ already exists."; Write-host -f green $msg}
					Else
						{
							#Actually create the user
							$displayName = $_
							$sAMAccountName = $_
							
							$objUserDN = "CN=" + $displayName + "," + $destinationOU
							$msg = "ACTION`tCreating user as: CN=" + $displayName + "," + $destinationOU
							Write-Out $msg "white" 2
							$objOU = [adsi]("LDAP://" + $destinationOU)
							$objUser = $objOU.Create("user","cn=$displayName")
							
							#write the sAMAccountName
							$objUser.Put("sAMAccountName",$sAMAccountName)
							$objUser.Put("userAccountControl",514)
							$objUser.SetInfo()
							
							$objUserDN = $null
							$objUserDN = "CN=" + $displayName + "," + $destinationOU
							
							#Does the user exist now?
							$blnUserExists = Check-DoesUserExist $sAMAccountName
							If($blnUserExists -eq $true -and $bFail -eq $false)
								{$msg = "`tSuccessfully created user """ + $sAMAccountName + """."; write-host -f green $msg}
							Else
								{
									$msg = "`tError`tFailed to create user """ + $sAMAccountName + """."; write-host -f magenta $msg
									$bFail = $true
								}
						}
				}
		}
		
		If($bFail -eq $true){$retval = $false}
		Else {$retval = $true}
		Return $retval
	}

Function Check-AddRemovePrograms($appName)
	{
		#ref: http://blogs.technet.com/b/heyscriptingguy/archive/2011/11/13/use-powershell-to-quickly-find-installed-software.aspx
		$arrProgList = @()
		$unistallPath = "\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\"
		$unistallWow6432Path = "\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\"
		@(
		if (Test-Path "HKLM:$unistallWow6432Path" ) { Get-ChildItem "HKLM:$unistallWow6432Path"}
		if (Test-Path "HKLM:$unistallPath" ) { Get-ChildItem "HKLM:$unistallPath" }
		if (Test-Path "HKCU:$unistallWow6432Path") { Get-ChildItem "HKCU:$unistallWow6432Path"}
		if (Test-Path "HKCU:$unistallPath" ) { Get-ChildItem "HKCU:$unistallPath" }
		) | ForEach-Object { Get-ItemProperty $_.PSPath } | Where-Object {
		  $_.DisplayName -and !$_.SystemComponent -and !$_.ReleaseType -and !$_.ParentKeyName -and ($_.UninstallString -or $_.NoRemove)
		} | Sort-Object DisplayName | Select-Object DisplayName | % {$arrProgList += $_}
		
		$retval = $false
		$arrProgList | % {
			If($_ -like "*$appName*"){$retval = $true}
		}
		
		Return $retval
	}

Function Get-AppInstallObject($app)
	{
		
		Switch($app)
			{
				"dotnet4"
					{
						$fullFilePath = ($sInstallFilesPath.TrimEnd("\") + "\dotNetFx40_Full_x86_x64.exe")
						$oApp = New-Object System.Object
						$oApp | Add-Member -type NoteProperty -name "FullFilePath" -value $fullFilePath
						$oApp | Add-Member -type NoteProperty -name "Args" -value "/q /norestart"
						$oApp | Add-Member -type NoteProperty -name "DisplayName" -value "Microsoft .NET Framework 4 Extended"
					}
				"sql2008"
					{
						$fullFilePath = ($sInstallFilesPath.TrimEnd("\") + "\SQLServer2008R2Std_wSP2\setup.exe")
						$cmdArgs = "/IAcceptSQLServerLicenseTerms /ACTION=INSTALL /CONFIGURATIONFILE=" + ($sInstallFilesPath.TrimEnd("\") + "\CustomSccmSqlInstall.ini")
						$oApp = New-Object System.Object
						$oApp | Add-Member -type NoteProperty -name "FullFilePath" -value $fullFilePath
						$oApp | Add-Member -type NoteProperty -name "Args" -value $cmdArgs
						$oApp | Add-Member -type NoteProperty -name "DisplayName" -value "Microsoft SQL Server 2008"
					}
				"wsus"
					{
						$fullFilePath = ($sInstallFilesPath.TrimEnd("\") + "\WSUS30-KB972455-x64.exe")
						$cmdArgs = "/q CONTENT_LOCAL=1 CONTENT_DIR=F:\Updates SQLINSTANCE_NAME=" + $env:ComputerName + " MU_ROLLUP=1 DEFAULT_WEBSITE=0 CREATE_DATABASE=1 CONSOLE_INSTALL=0"
						$oApp = New-Object System.Object
						$oApp | Add-Member -type NoteProperty -name "FullFilePath" -value $fullFilePath
						$oApp | Add-Member -type NoteProperty -name "Args" -value $cmdArgs
						$oApp | Add-Member -type NoteProperty -name "DisplayName" -value "Windows Server Update Services"
					}
				"WSUS-KB2734608"
					{
						$fullFilePath = ($sInstallFilesPath.TrimEnd("\") + "\WSUS-KB2734608-x64.exe")
						$cmdArgs = "/q"
						$oApp = New-Object System.Object
						$oApp | Add-Member -type NoteProperty -name "FullFilePath" -value $fullFilePath
						$oApp | Add-Member -type NoteProperty -name "Args" -value $cmdArgs
						$oApp | Add-Member -type NoteProperty -name "DisplayName" -value "WSUS-KB2734608"
					}
				Default {$oApp = $false}
			}
		Return $oApp
	}

Function Check-HotfixIdInstalled($hotfixID)
	{
		$installed = $false
		GWMI win32_QuickFixEngineering | % {If($_.HotfixID -like $hotfixID){$installed = $true}}
		Return $installed
	}

Function Check-WsusHotfix($appName)
	{
		#ref: http://social.technet.microsoft.com/Forums/en-US/winserverwsus/thread/76279753-4b45-47f9-905d-e473a8758dad/
		$minWsusVersion = 0
		If($appName -eq "WSUS-KB2734608"){$minWsusVersion = "3.2.7600.256"}
		
		#get current wsus version
		
		###This right here is the mark of am amateur. What I need to do is try it once as env:computername
		####try it again as localhost, then try resetting IIS and doing it again, then giving the user the error if it still fails.
		Try
			{
				[reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null
				Sleep -s 5
				$curWsusVersion = ([Microsoft.UpdateServices.Administration.AdminProxy]::getUpdateServer((($env:computername).ToLower()),$False,"8530")).Version.ToString()
				Sleep -s 5
			}
		Catch
			{
				Try {$curWsusVersion = ([Microsoft.UpdateServices.Administration.AdminProxy]::getUpdateServer("localhost",$False,"8530")).Version.ToString()}
				Catch{$curWsusVersion = 0}
			}
		
		
		
		#this doesn't work; only shows initial version.
		#(Get-ItemProperty -Path "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Update Services\Server\Setup\").VersionString
		
		$retval = $false
		If($curWsusVersion -ge $minWsusVersion)
			{$retval = $true}
		Return $retval
	}

Function Check-AppIsInstalled($appName)
	{
		$appInstalled = $false
		If($appName -eq "WSUS-KB2734608")
			{$appInstalled = Check-WsusHotfix $appName}
		Else
			{$appInstalled = Check-AddRemovePrograms $appName}
		Return $appInstalled
	}

Function Install-App($app)
	{
		$msg = "== Installing Application " + $app + " =="
		Write-Host -f cyan $msg
		$bFail = $false
		$cmdArgs = $null
		$bInstallApp = $false
		
		$oApp = $null
		$oApp = Get-AppInstallObject $app
		If($oApp -eq $null -or $oApp -eq $false)
			{
				$msg = "`tError`tFailed to retrieve application info for the app """ + $app + """."
				Write-host -f magenta $msg
				$bFail = $true
			}
				
		If($bFail -eq $false)
			{
				$cmdPath = $oApp.FullFilePath
				$cmdArgs = $oApp.Args
				$appDisplayName = $oApp.Displayname
			}
				
		#check if the app is installed in cpanel
		If($bFail -eq $false)
			{
				$bAppInstalled = Check-AppIsInstalled $appDisplayName
				If($bAppInstalled -eq $true)
					{$msg = "`tApplication """ + $app + """ is already installed."; write-host -f green $msg; $bInstallApp = $false}
				Else
					{$bInstallApp = $true}
			}
		
		If($bInstallApp -eq $true)
			{
				$msg = "`tInstalling the application """ + $app + """.`n`tRunning command """ + $cmdPath + " " + $cmdArgs + """."
				Write-Host $msg
				
				$p = Start-Process $cmdPath -ArgumentList $cmdArgs -Wait -NoNewWindow -PassThru
				$exitCode = $p.ExitCode
				If($exitCode -eq 0 -or $exitcode -eq 3010)
					{$msg = "`tApplication install """ + $app + """ has completed with exit code " + $exitcode + "."; write-host -f green $msg}
				Else {
					$msg = "`tError`tApplication Installed failed with return code: " + $exitCode + "."
					Write-host -f magenta $msg
					$bFail = $true
				}
			}
		
		If($bInstallApp -eq $false){}
		Else
			{
				$bAppInstalled = Check-AppIsInstalled $appDisplayName
				If($bAppInstalled -eq $true)
					{$msg = "`tApplication """ + $app + """ has installed successfully."; write-host -f green $msg}
				Else
					{$msg = "`tERROR`tFailed to install """ + $app + """."; Write-host -f magenta $msg; $bFail = $true}
			}
		
		If($bFail -eq $true){$retval = $false}
		Else {$retval = $true}
		Return $retval
	}

Function Check-IsRoleInstalled($role)
	{
		$retval = $false
		$installedRoles = Get-WindowsFeature | where {$_.Installed -eq "True"}
		$installedRoles | % {
			If($_.Name -like $role)
				{$retval = $true}
		}
		Return $retval
	}

Function Install-Role($role)
	{
		$msg = "== Intalling Role " + $role + " =="
		Write-Host -f cyan $msg
		$roleName = $null
		Switch($role) {
			"dotnet35" {$roleName = "net-framework-core"}
		}
		$bInstalled = $false
		$bInstalled = Check-IsRoleInstalled $roleName
		If($bInstalled -eq $true)
			{}
		Else
			{Add-WindowsFeature net-framework-core}
		
		#sleep -s 5
		$bInstalled = $false
		$bInstalled = Check-IsRoleInstalled $roleName
		If($bInstalled -eq $true)
			{$msg = "`tDotNet 3.5 is already installed."; write-host -f green $msg; $retval = $true}
		Else
			{$msg = "`tError`tFailed to install DotNet 3.5.";write-host -f magenta $msg; $retval = $false}
		
		Return $retval
	}

Function Configure-IISForSCCM()
	{
		Write-Host -f cyan "== Configuring IIS for SCCM =="
		
		$system32 = ($env:windir).TrimEnd("\") + "\system32"
		$moveto = "F:\"
		$movelog = "E:\"
		
		Write-host "`tMoving wwwroot to F drive."
		
		#build commands
		$arrCmds = @()
		#run backup
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\inetsrv\appcmd.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value ("add backup beforeRootMove-" + (get-date -format yyyy-MM-dd-mmss))
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Backing up iis config."
		$arrCmds += $oCmd
		
		#stop iis
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\iisreset.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "/stop"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Stopping IIS."
		$arrCmds += $oCmd
		
		#Copy current content
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\xcopy.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "C:\inetpub F:\inetpub /O /E /I /Q /Y"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Copying current wwwroot content to destination."
		$arrCmds += $oCmd
		
		#Moving logs
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\reg.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "add HKLM\System\CurrentControlSet\Services\WAS\Parameters /v ConfigIsolationPath /t REG_SZ /d F:\inetpub\temp\appPools /f"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Moving appPool path."
		$arrCmds += $oCmd
		
		#Moving logs
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\inetsrv\appcmd.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "set config -section:system.applicationHost/sites -siteDefaults.traceFailedRequestsLogging.directory:""F:\inetpub\logs\FailedReqLogFiles"""
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Moving trace logs."
		$arrCmds += $oCmd
		
		#Moving more logs
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\inetsrv\appcmd.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "set config -section:system.applicationHost/sites -siteDefaults.logfile.directory:""F:\inetpub\logs\logfiles"""
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Moving default logs."
		$arrCmds += $oCmd
		
		#Moving more logs
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\inetsrv\appcmd.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "set config -section:system.applicationHost/log -centralBinaryLogFile.directory:""F:\inetpub\logs\logfiles"""
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Moving binary logs."
		$arrCmds += $oCmd
		
		#Moving more logs
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\inetsrv\appcmd.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "set config -section:system.applicationHost/log -centralW3CLogFile.directory:""F:\inetpub\logs\logfiles"""
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Moving W3C logs."
		$arrCmds += $oCmd
		
		#Moving history
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\inetsrv\appcmd.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "set config -section:system.applicationhost/configHistory -path:F:\inetpub\history"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Moving configHistory."
		$arrCmds += $oCmd
		
		#Moving template cache
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\inetsrv\appcmd.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "set config -section:system.webServer/asp -cache.disktemplateCacheDirectory:""F:\inetpub\temp\ASP Compiled Templates"""
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Moving template cache directory."
		$arrCmds += $oCmd
		
		#Moving iis temp compressed files
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\inetsrv\appcmd.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "set config -section:system.webServer/httpCompression -directory:""F:\inetpub\temp\IIS Temporary Compressed Files"""
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Moving IIS temp compressed files."
		$arrCmds += $oCmd
		
		#Moving default site path
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\inetsrv\appcmd.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "set vdir ""Default Web Site/"" -physicalPath:F:\inetpub\wwwroot"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Moving default web site physical path."
		$arrCmds += $oCmd
		
		#Moving http 401 errors
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\inetsrv\appcmd.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "set config -section:httpErrors /[statusCode='401'].prefixLanguageFilePath:F:\inetpub\custerr"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Moving 401 error path."
		$arrCmds += $oCmd
		
		#Moving http 403 errors
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\inetsrv\appcmd.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "set config -section:httpErrors /[statusCode='403'].prefixLanguageFilePath:F:\inetpub\custerr"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Moving 403 error path."
		$arrCmds += $oCmd
		
		#Moving http 404 errors
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\inetsrv\appcmd.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "set config -section:httpErrors /[statusCode='404'].prefixLanguageFilePath:F:\inetpub\custerr"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Moving 404 error path."
		$arrCmds += $oCmd
		
		#Moving http 405 errors
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\inetsrv\appcmd.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "set config -section:httpErrors /[statusCode='405'].prefixLanguageFilePath:F:\inetpub\custerr"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Moving 405 error path."
		$arrCmds += $oCmd
		
		#Moving http 406 errors
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\inetsrv\appcmd.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "set config -section:httpErrors /[statusCode='406'].prefixLanguageFilePath:F:\inetpub\custerr"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Moving 406 error path."
		$arrCmds += $oCmd
		
		#Moving http 412 errors
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\inetsrv\appcmd.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "set config -section:httpErrors /[statusCode='412'].prefixLanguageFilePath:F:\inetpub\custerr"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Moving 412 error path."
		$arrCmds += $oCmd
		
		#Moving http 500 errors
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\inetsrv\appcmd.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "set config -section:httpErrors /[statusCode='500'].prefixLanguageFilePath:F:\inetpub\custerr"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Moving 500 error path."
		$arrCmds += $oCmd
		
		#Moving http 501 errors
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\inetsrv\appcmd.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "set config -section:httpErrors /[statusCode='501'].prefixLanguageFilePath:F:\inetpub\custerr"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Moving 501 error path."
		$arrCmds += $oCmd
		
		#Moving http 502 errors
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\inetsrv\appcmd.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "set config -section:httpErrors /[statusCode='502'].prefixLanguageFilePath:F:\inetpub\custerr"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Moving 502 error path."
		$arrCmds += $oCmd
		
		#Moving WWWPath
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\reg.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "add HKLM\Software\Microsoft\inetstp /v PathWWWRoot /t REG_SZ /d F:\inetpub\wwwroot /f"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Changing WWWRoot path in the registry."
		$arrCmds += $oCmd
		
		#Moving FTP Path
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\reg.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "add HKLM\Software\Microsoft\inetstp /v PathFTPRoot /t REG_SZ /d F:\inetpub\ftproot /f"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Changing FTP Path in the registry."
		$arrCmds += $oCmd
		
		#Moving WWWPath (32_64)
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\reg.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "add HKLM\Software\Wow6432Node\Microsoft\inetstp /v PathWWWRoot /t REG_EXPAND_SZ /d F:\inetpub\wwwroot /f"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Changing the WWWRoot Path (WoW64-32)."
		$arrCmds += $oCmd
		
		#Moving FTP Path (32_64)
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\reg.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "add HKLM\Software\Wow6432Node\Microsoft\inetstp /v PathFTPRoot /t REG_EXPAND_SZ /d F:\inetpub\ftproot /f"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Changing the FTP Path (WoW64-32)."
		$arrCmds += $oCmd
		
		#Allow double-escaping
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\inetsrv\appcmd.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "set config /section:requestfiltering /allowdoubleescaping:true"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Enabling double-escaping."
		$arrCmds += $oCmd
		
		#Deny dsfr
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\inetsrv\appcmd.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "set config /section:requestfiltering /+denyurlsequences.[sequence='DfsrPrivate']"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Enabling DFSRStaging deny filter."
		$arrCmds += $oCmd
		
		#Start IIS
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\iisreset.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "/start"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Starting IIS."
		$arrCmds += $oCmd
		
		$bFail = $false
		$arrCmds | % {
			$cmdPath = $_.FullFilePath
			$cmdArgs = $_.Args
			$appDisplayName = $_.Displayname
			
			$p = $null
			$p = Start-Process $cmdPath -ArgumentList $cmdArgs -Wait -NoNewWindow -PassThru -RedirectStandardOutput out.txt
			$exitCode = $p.ExitCode
			If($exitCode -eq 0 -or $exitcode -eq 3010 -or $exitcode -eq 183)
				{
					$msg = "`t" + $appDisplayName + " completed with exit code " + $exitcode + "."; write-host -f green $msg
					If($cmdPath -like "*iisreset*"){sleep -s 5}
				}
			Else {
				$msg = "`tError`t" + $appDisplayName + " failed with return code: " + $exitCode + "."
				Write-host -f magenta $msg
				$bFail = $true
			}
		}
		$retval = $true
		If($bFail -eq $true){$retval = $false}
		Return $retval
	}

# Vadims Podans (c) 2011
# http://en-us.sysadmins.lv/
Function Install-CertificationAuthority {
[CmdletBinding(
	DefaultParameterSetName = 'NewKeySet',
	ConfirmImpact = 'None',
	SupportsShouldProcess = $true
)]
	param(
		[Parameter(ParameterSetName = 'NewKeySet')]
		[string]$CAName,
		[Parameter(ParameterSetName = 'NewKeySet')]
		[string]$CADNSuffix,
		[Parameter(ParameterSetName = 'NewKeySet')]
		[ValidateSet("Standalone Root","Standalone Subordinate","Enterprise Root","Enterprise Subordinate")]
		[string]$CAType,
		[Parameter(ParameterSetName = 'NewKeySet')]
		[string]$ParentCA,
		[Parameter(ParameterSetName = 'NewKeySet')]
		[string]$CSP,
		[Parameter(ParameterSetName = 'NewKeySet')]
		[int]$KeyLength,
		[Parameter(ParameterSetName = 'NewKeySet')]
		[string]$HashAlgorithm,
		[Parameter(ParameterSetName = 'NewKeySet')]
		[int]$ValidForYears = 5,
		[Parameter(ParameterSetName = 'NewKeySet')]
		[string]$RequestFileName,
		[Parameter(Mandatory = $true, ParameterSetName = 'PFXKeySet')]
		[IO.FileInfo]$CACertFile,
		[Parameter(Mandatory = $true, ParameterSetName = 'PFXKeySet')]
		[Security.SecureString]$Password,
		[Parameter(Mandatory = $true, ParameterSetName = 'ExistingKeySet')]
		[string]$Thumbprint,
		[string]$DBDirectory,
		[string]$LogDirectory,
		[switch]$OverwriteExisting,
		[switch]$AllowCSPInteraction,
		[switch]$Force
	)

#region OS and existing CA checking
	# check if script running on Windows Server 2008 or Windows Server 2008 R2
	$OS = Get-WmiObject Win32_OperatingSystem -Property Version, ProductType
	if ([int][string]$OS.Version[0] -lt 6 -and $OS.ProductType -ne 1) {
		Write-Error -Category NotImplemented -ErrorId "NotSupportedException" `
		-ErrorAction Stop -Message "Windows XP, Windows Server 2003 and Windows Server 2003 R2 are not supported!"
	}	
	$CertConfig = New-Object -ComObject CertificateAuthority.Config
	try {$ExistingDetected = $CertConfig.GetConfig(3)}
	catch {}
	if ($ExistingDetected) {
		Write-Error -Category ResourceExists -ErrorId "ResourceExistsException" `
		-ErrorAction Stop -Message @"
Certificate Services are already installed on this computer. Only one Certification Authority instance per computer is supported.
"@
	}
	
#endregion

#region Binaries checking and installation if necessary
	try {Import-Module ServerManager -ErrorAction Stop}
	catch {
		ocsetup 'ServerManager-PSH-Cmdlets' /quiet | Out-Null
		Start-Sleep 1
		Import-Module ServerManager -ErrorAction Stop
	}
	$status = (Get-WindowsFeature -Name AD-Certificate).Installed
	# if still no, install binaries, otherwise do nothing
	if (!$status) {$retn = Add-WindowsFeature -Name AD-Certificate -ErrorAction Stop
		if (!$retn.Success) {
			Write-Warning "Unable to install ADCS installation packages due of the following error:"
			Write-Warning $retn.breakCode
		}
	}
	try {$CASetup = New-Object -ComObject CertOCM.CertSrvSetup.1}
	catch {
		Write-Error -Category NotImplemented -ErrorId "NotImplementedException" `
		-ErrorAction Stop -Message "Unable to load necessary interfaces. Your Windows Server operating system is not supported!"
	}
	# initialize setup binaries
	try {$CASetup.InitializeDefaults($true, $false)}
	catch {
		Write-Error -Category InvalidArgument -ErrorId ParameterIncorrectException `
		-ErrorAction Stop -Message "Cannot initialize setup binaries!"
	}
#endregion

#region Property enums
	$CATypesByName = @{"Enterprise Root" = 0; "Enterprise Subordinate" = 1; "Standalone Root" = 3; "Standalone Subordinate" = 4}
	$CATypesByVal = @{}
	$CATypesByName.keys | ForEach-Object {$CATypesByVal.Add($CATypesByName[$_],$_)}
	$CAPRopertyByName = @{"CAType"=0;"CAKeyInfo"=1;"Interactive"=2;"ValidityPeriodUnits"=5;
		"ValidityPeriod"=6;"ExpirationDate"=7;"PreserveDataBase"=8;"DBDirectory"=9;"Logdirectory"=10;
		"ParentCAMachine"=12;"ParentCAName"=13;"RequestFile"=14;"WebCAMachine"=15;"WebCAName"=16
	}
	$CAPRopertyByVal = @{}
	$CAPRopertyByName.keys | ForEach-Object {$CAPRopertyByVal.Add($CAPRopertyByName[$_],$_)}
	$ValidityUnitsByName = @{"years" = 6}
	$ValidityUnitsByVal = @{6 = "years"}
#endregion
	$ofs = ", "
#region Key set processing functions

#region NewKeySet
Function NewKeySet ($CAName, $CADNSuffix, $CAType, $ParentCA, $CSP, $KeyLength, $HashAlgorithm, $ValidForYears, $RequestFileName) {

	#region CSP, key length and hashing algorithm verification
	$CAKey = $CASetup.GetCASetupProperty(1)
	if ($CSP -ne "" -or $KeyLength -ne 0 -or $HashAlgorithm -ne "") {
		if ($CSP -ne "") {
			if ($CASetup.GetProviderNameList() -notcontains $CSP) {
				# TODO add available CSP list
				Write-Error -Category InvalidArgument -ErrorId "InvalidCryptographicServiceProviderException" `
				-ErrorAction Stop -Message "Specified CSP '$CSP' is not valid!"
			}
			$CAKey.ProviderName = $CSP
		}
		if ($KeyLength -ne 0) {
			if ($CASetup.GetKeyLengthList($CSP).Length -eq 1) {
				$CAKey.Length = $CASetup.GetKeyLengthList($CSP)[0]
			} else {
				if (@($CASetup.GetKeyLengthList($CSP) -notcontains $KeyLength)) {
					Write-Error -Category InvalidArgument -ErrorId "InvalidKeyLengthException" `
					-ErrorAction Stop -Message @"
The specified key length '$KeyLength' is not supported by the selected CSP '$CSP' The following
key lengths are supported by this CSP: $($CASetup.GetKeyLengthList($CSP))
"@
				}
				$CAKey.Length = $KeyLength
			}
		}
		if ($HashAlgorithm -ne "") {
			if ($CASetup.GetHashAlgorithmList($CSP) -notcontains $HashAlgorithm) {
					Write-Error -Category InvalidArgument -ErrorId "InvalidHashAlgorithmException" `
					-ErrorAction Stop -Message @"
The specified hash algorithm is not supported by the selected CSP '$CSP' The following
hash algorithms are supported by this CSP: $($CASetup.GetHashAlgorithmList($CSP))
"@
			}
			$CAKey.HashAlgorithm = $HashAlgorithm
		}
	}
	
	#$SETUPPROP_Interactive = 2
	$CASetup.SetCASetupProperty(1,$CAKey)
	#$CASetup.SetCASetupProperty($SETUPPROP_Interactive,$false)
#endregion

#region Setting CA type
	if ($CAType) {
		$SupportedTypes = $CASetup.GetSupportedCATypes()
		$SelectedType = $CATypesByName[$CAType]
		if ($SupportedTypes -notcontains $CATypesByName[$CAType]) {
			Write-Error -Category InvalidArgument -ErrorId "InvalidCATypeException" `
			-ErrorAction Stop -Message @"
Selected CA type: '$CAType' is not supported by current Windows Server installation.
The following CA types are supported by this installation: $([int[]]$CASetup.GetSupportedCATypes() | %{$CATypesByVal[$_]})
"@
		} else {$CASetup.SetCASetupProperty($CAPRopertyByName.CAType,$SelectedType)}
	}
#endregion

#region setting CA certificate validity
	if ($SelectedType -eq 0 -or $SelectedType -eq 3 -and $ValidForYears -ne 0) {
		try{$CASetup.SetCASetupProperty(6,$ValidForYears)}
		catch {
			Write-Error -Category InvalidArgument -ErrorId "InvalidCAValidityException" `
			-ErrorAction Stop -Message "The specified CA certificate validity period '$ValidForYears' is invalid."
		}
	}
#endregion

#region setting CA name
	if ($CAName -ne "") {
		if ($CADNSuffix -ne "") {$Subject = "CN=$CAName" + ",$CADNSuffix"} else {$Subject = "CN=$CAName"}
		$DN = New-Object -ComObject X509Enrollment.CX500DistinguishedName
		# validate X500 name format
		try {$DN.Encode($Subject,0x0)}
		catch {
			Write-Error -Category InvalidArgument -ErrorId "InvalidX500NameException" `
			-ErrorAction Stop -Message "Specified CA name or CA name suffix is not correct X.500 Distinguished Name."
		}
		$CASetup.SetCADistinguishedName($Subject, $true, $true, $true)
	}
#endregion

#region set parent CA/request file properties
	if ($CASetup.GetCASetupProperty(0) -eq 1 -and $ParentCA) {
		[void]($ParentCA -match "^(.+)\\(.+)$")
		try {$CASetup.SetParentCAInformation($ParentCA)}
		catch {
			Write-Error -Category ObjectNotFound -ErrorId "ObjectNotFoundException" `
			-ErrorAction Stop -Message @"
The specified parent CA information '$ParentCA' is incorrect. Make sure if parent CA
information is correct (you must specify existing CA) and is supplied in a 'CAComputerName\CASanitizedName' form.
"@
		}
	} elseif ($CASetup.GetCASetupProperty(0) -eq 1 -or $CASetup.GetCASetupProperty(0) -eq 4 -and $RequestFileName -ne "") {
		$CASetup.SetCASetupProperty(14,$RequestFileName)
	}
#endregion
}

#endregion

#region PFXKeySet
function PFXKeySet ($CACertFile, $Password) {
	$FilePath = Resolve-Path $CACertFile -ErrorAction Stop
	try {[void]$CASetup.CAImportPFX(
		$FilePath.Path,
		[Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)),
		$true)
	} catch {Write-Error $_ -ErrorAction Stop}
}
#endregion

#region ExistingKeySet
function ExistingKeySet ($Thumbprint) {
	$ExKeys = $CASetup.GetExistingCACertificates() | ?{
		([Security.Cryptography.X509Certificates.X509Certificate2]$_.ExistingCACertificate).Thumbprint -eq $Thumbprint
	}
	if (!$ExKeys) {
		Write-Error -Category ObjectNotFound -ErrorId "ElementNotFoundException" `
		-ErrorAction Stop -Message "The system cannot find a valid CA certificate with thumbprint: $Thumbprint"
	} else {$CASetup.SetCASetupProperty(1,@($ExKeys)[0])}
}
#endregion

#endregion

#region set database settings
	if ($DBDirectory -ne "" -and $LogDirectory -ne "") {
		try {$CASetup.SetDatabaseInformation($DBDirectory,$LogDirectory,$null,$OverwriteExisting)}
		catch {
			Write-Error -Category InvalidArgument -ErrorId "InvalidPathException" `
			-ErrorAction Stop -Message "Specified path to either database directory or log directory is invalid."
		}
	} elseif ($DBDirectory -ne "" -and $LogDirectory -eq "") {
		Write-Error -Category InvalidArgument -ErrorId "InvalidPathException" `
		-ErrorAction Stop -Message "CA Log file directory cannot be empty."
	} elseif ($DBDirectory -eq "" -and $LogDirectory -ne "") {
		Write-Error -Category InvalidArgument -ErrorId "InvalidPathException" `
		-ErrorAction Stop -Message "CA database directory cannot be empty."
	}

#endregion
	# process parametersets.
	switch ($PSCmdlet.ParameterSetName) {
		"ExistingKeySet" {ExistingKeySet $Thumbprint}
		"PFXKeySet" {PFXKeySet $CACertFile $Password}
		"NewKeySet" {NewKeySet $CAName $CADNSuffix $CAType $ParentCA $CSP $KeyLength $HashAlgorithm $ValidForYears $RequestFileName}
	}
	try {
		Write-Host "Installing Certification Authority role on $env:computername ..." -ForegroundColor Cyan
		if ($Force -or $PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Install Certification Authority")) {
			$CASetup.Install()
			$PostRequiredMsg = @"
Certification Authority role was successfully installed, but not completed. To complete installation submit
request file '$($CASetup.GetCASetupProperty(14))' to parent Certification Authority
and install issued certificate by running the following command: certutil -installcert 'PathToACertFile'
"@
			if ($CASetup.GetCASetupProperty(0) -eq 1 -and $ParentCA -eq "") {
				Write-Host $PostRequiredMsg -ForegroundColor Yellow -BackgroundColor Black
			} elseif ($CASetup.GetCASetupProperty(0) -eq 1 -and $PSCmdlet.ParameterSetName -eq "NewKeySet" -and $ParentCA -ne "") {
				$SetupStatus = (Get-ItemProperty HKLM:\System\CurrentControlSet\Services\CertSvc\Configuration\$($CASetup.GetCASetupProperty(3))).SetupStatus
				$RequestID = (Get-ItemProperty HKLM:\System\CurrentControlSet\Services\CertSvc\Configuration\$($CASetup.GetCASetupProperty(3))).RequestID
				if ($SetupStatus -ne 1) {
					Write-Host @"
Certification Authority role was successfully installed, but not completed. CA certificate request
was submitted to '$ParentCA' and is waiting for approval. RequestID is '$RequestID'.
Once certificate request is issued, finish the installtion by running the following command:
certutil -installcert 'PathToACertFile'
"@ -ForegroundColor Yellow -BackgroundColor Black
				}
			} elseif ($CASetup.GetCASetupProperty(0) -eq 4) {
				Write-Host $PostRequiredMsg -ForegroundColor Yellow -BackgroundColor Black
			} else {Write-Host "Certification Authority role is successfully installed!" -ForegroundColor Green}
		} else {
			#[void](Remove-WindowsFeature ADCS-Cert-Authority)
		}
	} catch {Write-Error $_ -ErrorAction Stop}
}

Function Install-SubCA()
	{
		$caName = "SCCM-" + $sitecode.ToUpper() + " Issuing CA"
		$csp = "RSA#Microsoft Software Key Storage Provider"
		$caType = "Enterprise Subordinate"
		$caDNSuffix = $dnSuffix
		$hashAlg = "SHA256"
		$dbDir = "D:\certdb"
		$logDir = "E:\certlogs"
		
		write-host -f cyan  "== Installing Subordinate Enterprise CA Role =="
		
		Try {Import-Module ServerManager}
		Catch {}
		
		$caInstalled = (Get-WindowsFeature -Name AD-Certificate).Installed
		If($caInstalled -eq $true)
			{Write-Host -f green "`tCA already installed."}
		Else
			{
				If((Test-Path $dbDir) -eq $false){mkdir $dbDir | out-null}
				If((Test-Path $logDir) -eq $false){mkdir $logDir | out-null}
				$caPolicySource = $sInstallFilesPath + "\capolicy.inf"
				copy $caPolicySource "C:\Windows\" -force | out-null
				
				$action = Install-CertificationAuthority -CAName $caName -CSP $csp -CADNSuffix $caDnSuffix -CAType $caType -HashAlgorith $hashAlg -DBDirectory $dbDir -LogDirectory $logDir
				$retval = $true
				$retval = $action
			}
		
		$retval = (Get-WindowsFeature -Name AD-Certificate).Installed
		Return $retval
	}

Function Configure-SubCA()
	{
		$msg = "== Configure CA =="
		Write-host -f cyan $msg
		
		$system32 = ($env:windir).TrimEnd("\") + "\system32"
		
		$cdpString = $null
		$cdpString = """"
		$cdpString += "65:" + $env:windir + "\system32\CertSrv\CertEnroll\%3%8%9.crl\n"
		$cdpString += "65:F:\inetpub\wwwroot\certdata\%3%8%9.crl\n"
		$cdpString += "6:http://cdp." + $domainSuffix + "/certdata/%3%8%9.crl\n"
		$cdpString += "6:http://" + ($env:computername).ToLower() + "." + $domainSuffix + "/certdata/%3%8%9.crl"
		$cdpString += """"
		
		$aiaString = $null
		$aiaString = """"
		$aiaString += "1:" + $env:windir + "\system32\CertSrv\CertEnroll\%1_%3%4.crt\n"
		$aiaString += "1:F:\inetpub\wwwroot\certdata\%1_%3%4.crt\n"
		$aiaString += "2:http://aia." + $domainSuffix + "/certdata/%1_%3%4.crt\n"
		$aiaString += "2:http://" + ($env:computername).ToLower() + "." + $domainSuffix + "/certdata/%1_%3%4.crt"
		$aiaString += """"
		
		
		$arrCmds = @()
		#Domain suffix
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\certutil.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value ("-setreg CA\DSConfigDN CN=Configuration," + $dnSuffix)
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Configuring CA domain suffix."
		$arrCmds += $oCmd
		
		#CRL Period Units
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\certutil.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "-setreg CA\CRLPeriodUnits 8"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Setting CRL Period (units)."
		$arrCmds += $oCmd
		
		#CRL Period Value
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\certutil.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "-setreg CA\CRLPeriod ""Days"""
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Setting CRL Period value."
		$arrCmds += $oCmd
		
		#CRL Overlap Units
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\certutil.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "-setreg CA\CRLOverlapUnits 1"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Setting CRL Overlap (units)."
		$arrCmds += $oCmd
		
		#CRL Overlap Value
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\certutil.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "-setreg CA\CRLOverlapPeriod ""Days"""
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Setting CRL Overlap value."
		$arrCmds += $oCmd
		
		#CRL Delta Units
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\certutil.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "-setreg CA\CRLDeltaPeriodUnits 12"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Setting CRL Delta (units)."
		$arrCmds += $oCmd
		
		#CRL Delta Value
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\certutil.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "-setreg CA\CRLDeltaPeriod ""Hours"""
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Setting CRL Delta value."
		$arrCmds += $oCmd
		
		#CDP Values
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\certutil.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value ("-setreg CA\CRLPublicationURLs " + $cdpString)
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Setting CDP values."
		$arrCmds += $oCmd
		
		#AIA Values
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\certutil.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value ("-setreg CA\CACertPublicationURLs " + $aiaString)
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Setting AIA Values."
		$arrCmds += $oCmd
		
		#Audit Values
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\certutil.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "-setreg CA\AuditFilter 127"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Setting Audit value."
		$arrCmds += $oCmd
		
		#Discreet sigs
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\certutil.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "–setreg CA\csp\DiscreteSignatureAlgorithm 1"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Enablind discreet signatures."
		$arrCmds += $oCmd
		
		#Max Validity Units
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\certutil.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "-setreg CA\ValidityPeriodUnits 5"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Setting Max Validity Period (units)."
		$arrCmds += $oCmd
		
		#Max Validity Values
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\certutil.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "-setreg CA\ValidityPeriod ""Years"""
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Setting Max Validity Period value."
		$arrCmds += $oCmd
		
		$bFail = $false
		$arrCmds | % {
			$cmdPath = $_.FullFilePath
			$cmdArgs = $_.Args
			$appDisplayName = $_.Displayname
			
			$p = $null
			$p = Start-Process $cmdPath -ArgumentList $cmdArgs -Wait -NoNewWindow -PassThru -RedirectStandardOutput out.txt
			$exitCode = $p.ExitCode
			If($exitCode -eq 0 -or $exitcode -eq 3010 -or $exitcode -eq 183)
				{
					$msg = "`t" + $appDisplayName + " completed with exit code " + $exitcode + "."; write-host -f green $msg
					If($cmdPath -like "*iisreset*"){sleep -s 5}
				}
			Else {
				$msg = "`tError`t" + $appDisplayName + " failed with return code: " + $exitCode + "."
				Write-host -f magenta $msg
				$bFail = $true
			}
		}
		$retval = $true
		If($bFail -eq $true){$retval = $false}
		Return $retval
	}

Function Install-SCCMRoles()
	{
		$msg = "== Intalling SCCM Prereq Roles =="
		Write-Host -f cyan $msg
		
		$msg = "`tInstalling IIS, BITS, RDC, File Services, and WebDAV"
		Write-Host $msg
		$action = Add-WindowsFeature Web-Server,Web-WebServer,Web-Common-Http,Web-Static-Content,Web-Default-Doc,Web-Dir-Browsing,Web-Http-Errors,Web-Http-Redirect,Web-App-Dev,Web-Asp-Net,Web-Net-Ext,Web-ASP,Web-ISAPI-Ext,Web-ISAPI-Filter,Web-Health,Web-Http-Logging,Web-Request-Monitor,Web-Http-Tracing,Web-Security,Web-Basic-Auth,Web-Windows-Auth,Web-Url-Auth,Web-Filtering,Web-IP-Security,Web-Performance,Web-Stat-Compression,Web-Mgmt-Tools,Web-Mgmt-Console,Web-Scripting-Tools,Web-Mgmt-Service,Web-Mgmt-Compat,Web-Metabase,Web-WMI,Web-Lgcy-Scripting,Web-Lgcy-Mgmt-Console,BITS,BITS-Compact-Server,BITS-IIS-Ext,WAS,WAS-Process-Model,WAS-NET-Environment,WAS-Config-APIs,RDC,File-Services,FS-FileServer,WinRM-IIS-Ext,Web-DAV-Publishing
		$action = $action.success
		If($action -eq $true){$msg = "`tInstall succeeded."; Write-Host -f green $msg}
		Else{$msg = "`tError`tInstall failed."; Write-Host -f magenta $msg}
		$retval = $action
		
		Return $retval
	}

Function Create-SCCMShares()
	{
		write-host -f cyan "== Creating SCCM Shares =="
		
		$sccmSourceReadGroup = "ACL_SCCM-" + $siteCode + "1_SourceShare_AllowRead"
		$sccmSourceReadWriteGroup = "ACL_SCCM-" + $siteCode + "1_SourceShare_AllowReadWrite"
		$sccmPrivateSourceReadGroup = "ACL_SCCM-" + $siteCode + "1_PrivateSourceShare_AllowRead"
		$sccmPrivateSourceReadWriteGroup = "ACL_SCCM-" + $siteCode + "1_PrivateSourceShare_AllowReadWrite"
		$sccmNetworkAccessAccount = ("sccm-" + $siteCode + "-naa").ToLower()
		
		#folder structure
		$folders = @()
		$folders += "source"
		$folders += "source\packages"
		$folders += "source\driverpackages"
		$folders += "source\driversource"
		$folders += "source\driversource\Win7"
		$folders += "source\driversource\WinXP"
		$folders += "source\driversource\WinPE"
		$folders += "source\driversource\WinPE\x86"
		$folders += "source\driversource\WinPE\x64"
		$folders += "source\images"
		$folders += "source\updates"
		$folders += "source\temp"
		$folders += "source\images"
		$folders += "source\bootimages"
		$folders += "source\ossource"
		$folders += "captures"
		$folders += "privateSource"
		$folders += "logs"
		
		$sourceLocalPath = "F:\Shares"
		
		#create folder structure
		If((test-path $sourceLocalPath) -eq $false)
			{mkdir $sourceLocalPath | out-null}
		
		#prep subinacl
		copy ($sInstallFilesPath + "\subinacl.exe") F:\Shares -force | out-null
		$PathToSubinacl = "F:\shares\subinacl.exe"
		$sccmServerName = $env:computername
			
		$folders | % {
			$path = $sourceLocalPath + "\" + $_
			If((Test-Path $path) -eq $false)
				{mkdir $path | out-null}
		}
		
		#Create Shares
		$shares = @()
		$shares += "source$"
		$shares += "captures$"
		$shares += "privateSource$"
		$shares += "logs$"
		
		$shares | % {
			$shareName = $_
			$sharePath = $sourceLocalPath + "\" + ($shareName.TrimEnd("$"))
			$action = Create-Share $shareName $sharePath $sccmServerName
			
			If($ShareName -like "private*")
				{
					#hshUserAccess
					$hshUserAccess = $null
					$hshUserAccess = @{}
					$hshUserAccess.Add("BUILTIN\SYSTEM","FullControl")
					$hshUserAccess.Add(($domainShort + "\" + $sccmNetworkAccessAccount),"Read")
					$hshUserAccess.Add(($domainShort + "\" + $sccmPrivateSourceReadGroup),"Read")
					$hshUserAccess.Add(($domainShort + "\" + $sccmPrivateSourceReadWriteGroup),"FullControl")
					$hshUserAccess.Add(($domainShort + "\" + $SCCMServerName + "$"),"FullControl")
				}
			ElseIf($shareName -like "source*")
				{
					#hshUserAccess
					$hshUserAccess = $null
					$hshUserAccess = @{}
					$hshUserAccess.Add("BUILTIN\SYSTEM","FullControl")
					$hshUserAccess.Add(($domainShort + "\" + $sccmNetworkAccessAccount),"Read")
					$hshUserAccess.Add(($domainShort + "\" + $sccmSourceReadGroup),"Read")
					$hshUserAccess.Add(($domainShort + "\" + $sccmSourceReadWriteGroup),"FullControl")
					$hshUserAccess.Add(($domainShort + "\" + $SCCMServerName + "$"),"FullControl")
				}
			ElseIf($shareName -like "captures*")
				{
					#hshUserAccess
					$hshUserAccess = $null
					$hshUserAccess = @{}
					$hshUserAccess.Add("BUILTIN\SYSTEM","FullControl")
					$hshUserAccess.Add(($domainShort + "\" + $sccmNetworkAccessAccount),"FullControl")
					$hshUserAccess.Add(($domainShort + "\" + $sccmSourceReadGroup),"Read")
					$hshUserAccess.Add(($domainShort + "\" + $sccmSourceReadWriteGroup),"FullControl")
					$hshUserAccess.Add(($domainShort + "\" + $SCCMServerName + "$"),"FullControl")
				}
			ElseIf($shareName -like "logs*")
				{
					#hshUserAccess
					$hshUserAccess = $null
					$hshUserAccess = @{}
					$hshUserAccess.Add("BUILTIN\SYSTEM","FullControl")
					$hshUserAccess.Add(($domainShort + "\" + $sccmNetworkAccessAccount),"FullControl")
					$hshUserAccess.Add(($domainShort + "\" + $sccmSourceReadGroup),"Read")
					$hshUserAccess.Add(($domainShort + "\" + $sccmSourceReadWriteGroup),"FullControl")
					$hshUserAccess.Add(($domainShort + "\" + $SCCMServerName + "$"),"FullControl")
					$hshUserAccess.Add(($domainShort + "\" + "Domain Computers"),"writelogs")
				}
			
			#set share perms
			$strWMI = $null
			$strWMI = "\\" + $sccmServerName + "\root\cimv2:win32_share.name='" + $shareName + "'"
			$objShare = [wmi]$strWMI
			$objShare_NewSD = $null
			$objShare_NewSD = Build-SourceShareDACL $sccmServerName $hshUserAccess
			$objShare.SetShareInfo($Null,$Null,$objShare_NewSD.PSObject.BaseObject) | out-null
			
			#set folder perms
			Set-FolderPermissions $sharePath $hshUserAccess
		}
		
	}

Function Set-SQLMemory()
	{
		$bFail = $false
		
		$SQLServer = "localhost" #use Server\Instance for named SQL instances! 
		$SQLDBName = "master"
		$SqlQuery1 = "EXEC sp_configure 'show advanced option',1 reconfigure"
		$SqlQuery2 = "EXEC sp_configure 'Max Server Memory',2048 reconfigure"
		
		$SqlConnection = New-Object System.Data.SqlClient.SqlConnection
		$SqlConnection.ConnectionString = "Server = $SQLServer; Database = $SQLDBName; Integrated Security = True"
		
		$SqlCmd1 = New-Object System.Data.SqlClient.SqlCommand
		$SqlCmd1.CommandText = $SqlQuery1
		$SqlCmd1.Connection = $SqlConnection
		
		$SqlCmd2 = New-Object System.Data.SqlClient.SqlCommand
		$SqlCmd2.CommandText = $SqlQuery2
		$SqlCmd2.Connection = $SqlConnection
		
		$SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
		$SqlAdapter.SelectCommand = $SqlCmd1
		$DataSet = New-Object System.Data.DataSet
		$action = $SqlAdapter.Fill($DataSet)
		$SqlAdapter.SelectCommand = $SqlCmd2
		$action = $SqlAdapter.Fill($DataSet)
		 
		$action = $SqlConnection.Close()
		
		$retval = $true
		If($bFail -eq $true){$retval = $false}
		Return $retval
	}

Function Set-SqlTcpEnabled()
	{
		# Load the assemblies
		[reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")
		[reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlWmiManagement")
		$smo = 'Microsoft.SqlServer.Management.Smo.'
		$wmi = new-object ($smo + 'Wmi.ManagedComputer')
		
		# List the object properties, including the instance names.
#		$tcpProperties = $wmi.ExecQuery("select * from ServerNetworkProtocolProperty " `
#    + "where InstanceName='SQLEXPRESS' and " `
#    + "ProtocolName='Tcp' and IPAddressName='IPAll'")
		
		# Enable the TCP protocol on the default instance.
		$uri = "ManagedComputer[@Name='" + $env:computerName +  "']/ ServerInstance[@Name='MSSQLSERVER']/ServerProtocol[@Name='Tcp']"
		$Tcp = $wmi.GetSmoObject($uri)
		$Tcp.IsEnabled = $true
		$Tcp.Alter()
		$IPAddresses = $Tcp.IPAddresses
		
		$IPAddresses | % {$_.IPAddressProperties | Where {$_.Name -eq "Enabled"} | % {$_.Value = $true}}
		$Tcp.Alter()
		Return $true
	}

Function Configure-SQL()
	{
		$msg = "== Configuring SQL =="
		Write-Host -f cyan $msg
		
		$bFail = $false
		$action = $null
		$action = Set-SQLMemory
		#write-host -f yellow "action: $action"
		If($action -eq $false)
			{$msg = "`tFailed to set SQL Max Memory."; write-host -f magenta $msg; $bFail = $true}
		Else
			{$msg = "`tSQL Max Memory set to 2GB."; write-host -f green $msg}
		
		$action = Set-SqlTcpEnabled
		If($action -eq $false)
			{$msg = "`tFailed to set enable TCP."; write-host -f magenta $msg; $bFail = $true}
		Else
			{$msg = "`tSQL TCP and IP Addresses have been enabled."; write-host -f green $msg}
		
		$retval = $true
		If($bFail -eq $true){$retval = $false}
		Return $retval
	}

#Michael Niehaus
#http://technet.microsoft.com/en-us/magazine/ff642467.aspx
Function Configure-SystemsManagementContainer()
	{
		$bFail = $false
		$msg = "== Configuring Systems Management Container =="
		write-host -f cyan $msg
		
		#get the container DN
		$root = (Get-ADRootDSE).defaultNamingContext
		$sysPath = ("CN=System Management,CN=System," + $root)
		
		# Test for DNE; create if necessary
		$ou = $null
		try{$ou = Get-ADObject $sysPath}
		catch{}
		If ($ou -eq $null)
			{
				$msg = "`t* Creating Systems Management container.";Write-Host $msg
				$ou = New-ADObject -Type Container -name "System Management" -Path "CN=System,$root" -Passthru
				
				# Create
				try {$ou = Get-ADObject $sysPath}
				catch {}
				If($ou -eq $null)
					{
						$msg = "`tError`tFailed to create the container: """ + $sysPath + """."
						write-host -f magenta $msg
						$bFail = $true
					}
				Else
					{$msg = "`t * Created Systems Management Container successfully."; Write-host -f green $msg}
			}
		Else
			{
				$msg = "`t* Systems Management container exists at """ + $sysPath + """."
				Write-host -f green $msg
			}
		
		# Perms
		$acl = get-acl ("AD:" + $sysPath)
		$permsOK = $false
		$IDRef = ($domainShort + "\" + $env:computername).ToUpper() + "$"
		$acl.access | % {$name = $_.IdentityReference.Value; If($name -eq $IDRef){$permsOK = $true}}
		If($permsOK -eq $true)
			{}
		Else
			{
				$msg = "`t* Adding local system to Systems Management Container ACL."; write-host $msg
				$computer = get-adcomputer $env:ComputerName
				$sid = [System.Security.Principal.SecurityIdentifier] $computer.SID
				# Create a new access control entry to allow access to the OU
				$ace = new-object System.DirectoryServices.ActiveDirectoryAccessRule $sid, "GenericAll", "Allow", "All"
				# Add the ACE to the ACL, then set the ACL to save the changes
				$acl.AddAccessRule($ace)
				Set-acl -aclobject $acl ("AD:" + $sysPath)
			}
		
		$acl = get-acl ("AD:" + $sysPath)
		$permsOK = $false
		$acl.access | % {$name = $_.IdentityReference.Value; If($name -eq $IDRef){$permsOK = $true}}
		If($permsOK -eq $true)
			{$msg = "`t* System Management Container permissions are correct."; write-host -f green $msg}
		Else
			{
				$msg = "`tError`tFailed to set System Management Container permissions."; write-host -f magenta $msg
				$bFail = $true
			}
		
		If($bFail -eq $true){$retval = $false}
		Else {$retval = $true}
		return $retval
	}

Function Prep-SCCMInstall()
	{
		$msg = "== Preparing for SCCM Install =="
		Write-Host -f cyan $msg
		
		$msg = "`t* Downloading setup prereq files."
		Write-Host $msg
		
		$system32 = ($env:windir).TrimEnd("\") + "\system32"
		
		$arrCmds = @()
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\xcopy.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value ($sInstallFilesPath + "\SCCMDownloads  C:\SCCMDownloads\ /y")
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Copying locally cached prereq files."
		$arrCmds += $oCmd
		
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($sInstallFilesPath.TrimEnd("\") + "\SCCM 2012\SMSSETUP\BIN\X64\setupdl.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "/noui C:\SCCMDownloads"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Downloading newer SCCM Prereq files."
		$arrCmds += $oCmd
		
		If((Test-Path "C:\SCCMDownloads") -eq $false) {mkdir "C:\SCCMDownloads"}
		
		$bFail = $false
		$arrCmds | % {
			$cmdPath = $_.FullFilePath
			$cmdArgs = $_.Args
			$appDisplayName = $_.Displayname
			
			$p = $null
			$p = Start-Process $cmdPath -ArgumentList $cmdArgs -Wait -NoNewWindow -PassThru -RedirectStandardOutput out.txt
			$exitCode = $p.ExitCode
			If($exitCode -eq 0 -or $exitcode -eq 3010 -or $exitcode -eq 183)
				{
					$msg = "`t" + $appDisplayName + " Completed with exit code " + $exitcode + "."; write-host -f green $msg
					If($cmdPath -like "*iisreset*"){sleep -s 5}
				}
			Else {
				$msg = "`tError`t" + $appDisplayName + " Failed with return code: " + $exitCode + "."
				Write-host -f magenta $msg
				$bFail = $true
			}
		}
		
		$msg = "`t* Generating customized setup config file."
		Write-Host $msg
		
		$serverFQDN = ($env:Computername).ToLower() + "." + $domainSuffix
		
		If($bCASInstall -eq $true)
			{
				$rows = @()
				$rows += "[Identification]"
				$rows += "Action=InstallCAS"
				$rows += ""
				$rows += "[Options]"
				$rows += "ProductID=EVAL"
				$rows += "SiteCode=" + $siteCode
				$rows += "SiteName=" + $siteName
				$rows += "SMSInstallDir=C:\Program Files\Microsoft Configuration Manager"
				$rows += "SDKServer=" + $serverFQDN
				$rows += "PrerequisiteComp=0"
				$rows += "PrerequisitePath=C:\SCCMDownloads"
				$rows += "MobileDeviceLanguage=0"
				$rows += "AdminConsole=1"
				$rows += "JoinCEIP=1"
				$rows += ""
				$rows += "[SQLConfigOptions]"
				$rows += "SQLServerName=" + $serverFQDN
				$rows += "DatabaseName=CM_" + $siteCode
				$rows += "SQLSSBPort=4022"
				$rows += ""
				$rows += "[HierarchyExpansionOption]"
			}
		Else
			{
				$rows = @()
				$rows += "[Identification]"
				$rows += "Action=InstallPrimarySite"
				$rows += ""
				$rows += "[Options]"
				$rows += "ProductID=EVAL"
				$rows += "SiteCode=" + $siteCode
				$rows += "SiteName=" + $siteName
				$rows += "SMSInstallDir=C:\Program Files\Microsoft Configuration Manager"
				$rows += "SDKServer=" + $serverFQDN
				$rows += "RoleCommunicationProtocol=HTTPorHTTPS"
				$rows += "ClientsUsePKICertificate=1"
				$rows += "PrerequisiteComp=0"
				$rows += "PrerequisitePath=C:\SCCMDownloads"
				$rows += "MobileDeviceLanguage=0"
				$rows += "ManagementPoint=" + $serverFQDN
				$rows += "ManagementPointProtocol=HTTP"
				$rows += "DistributionPoint=" + $serverFQDN
				$rows += "DistributionPointProtocol=HTTP"
				$rows += "DistributionPointInstallIIS=0"
				$rows += "AdminConsole=1"
				$rows += "JoinCEIP=1"
				$rows += ""
				$rows += "[SQLConfigOptions]"
				$rows += "SQLServerName=" + $serverFQDN
				$rows += "DatabaseName=CM_" + $siteCode
				$rows += "SQLSSBPort=4022"
				$rows += ""
				$rows += "[HierarchyExpansionOption]"
				$rows += "CCARSiteServer=" + $CasServerFQDN
			}
		
		$file = $sInstallFilesPath + "\sccmCustomInstall.ini"
		If((Test-Path $file) -eq $true)
			{(Rename-Item $file ("SccmCustomInstall-" + (get-date -format yyyy-MM-dd_hhmm-ss))) | out-host}
		If((Test-Path $file) -eq $true)
			{
				$msg = "`tFailed to backup existing file named """ + $file + """."; write-host -f magenta $msg
				$bFail = $true
			}
		
		If($bFail -eq $false)
			{$rows | % {Add-Content $file $_}}
		
		$retval = $true
		If($bFail -eq $true){$retval = $false}
		Return $retval
	}

Function Install-SCCM()
	{
		$msg = "== Installing SCCM Site Server =="
		Write-host -f Cyan $msg
		
		$system32 = ($env:SystemRoot + "\system32")
		$serverFQDN = ($env:Computername).ToLower() + "." + $domainSuffix
		
		$arrCmds = @()
		
		$bSCCMInstalled = $false
		$arrSccmNames = @()
		$arrSccmNames += "Microsoft System Center 2012 Configuration Manager CAS Site"
		$arrSccmNames += "Microsoft System Center 2012 Configuration Manager Primary Site"
		$arrSccmNames | % {If((Check-AppIsInstalled $_) -eq $true){$bSccmInstalled = $true}}
		If($bSCCMInstalled -eq $true){$msg = "`t* SCCM is already installed."; Write-Host -f green $msg}
		Else
			{
				#site server \ CAS
				$oCmd = New-Object System.Object
				$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($sInstallFilesPath.TrimEnd("\") + "\SCCM 2012\SMSSETUP\BIN\X64\setup.exe")
				$oCmd | Add-Member -type NoteProperty -name "Args" -value ("/script " + $sInstallFilesPath + "\SCCMCustomInstall.ini /NoUserInput")
				$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Installing SCCM Proper."
				$arrCmds += $oCmd
			}
		
		If((Check-AppIsInstalled "Microsoft System Center 2012 Configuration Manager Console") -eq $true){$msg = "`t* SCCM Console is already installed."; write-host -f green $msg}
		Else
			{
				#Admin Console
				$oCmd = New-Object System.Object
				$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\msiexec.exe")
				$oCmd | Add-Member -type NoteProperty -name "Args" -value ("/i """ + $sInstallFilesPath + "\SCCM 2012\SMSSETUP\BIN\I386\AdminConsole.msi"" TargetDir=""" + $env:programfiles + "\SCCM2012Console"" DefaultSiteServername=" + $serverFQDN + " /qb")
				$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Installing SCCM Console."
				$arrCmds += $oCmd
			}
		
		
		If((Check-AppIsInstalled "Microsoft Deployment Toolkit 2012") -eq $true){$msg = "`t* MDT 2012 is already installed."; write-host -f green $msg}
		Else
			{
				#MDT
				$oCmd = New-Object System.Object
				$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\msiexec.exe")
				$oCmd | Add-Member -type NoteProperty -name "Args" -value ("/i """ + $sInstallFilesPath + "\MicrosoftDeploymentToolkit2012_x64.msi"" /qb")
				$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Installing MDT 2012 u1."
				$arrCmds += $oCmd
			}
		
		If((Test-Path "C:\SCCMDownloads") -eq $false) {mkdir "C:\SCCMDownloads"}
		
		$bFail = $false
		If($arrCmds.Count -ge 1)
			{
				$arrCmds | % {
					$cmdPath = $_.FullFilePath
					$cmdArgs = $_.Args
					$appDisplayName = $_.Displayname
					
					$msg = "`tRunning: " + $cmdPath + " " + $cmdArgs
					write-host -f green $msg
					
					$bAppInstalled = $false
					$bAppInstalled = Check-AppIsInstalled $appDisplayName
					If($bAppInstalled -eq $true)
						{$msg = "`tApplication """ + $app + """ is already installed."; write-host -f green $msg; $bInstallApp = $false}
					Else
						{$bInstallApp = $true}
					
					$p = $null
					$p = Start-Process $cmdPath -ArgumentList $cmdArgs -Wait -NoNewWindow -PassThru -RedirectStandardOutput out.txt
					$exitCode = $p.ExitCode
					If($exitCode -eq 0 -or $exitcode -eq 3010 -or $exitcode -eq 183)
						{
							$msg = "`t" + $appDisplayName + " Completed with exit code " + $exitcode + "."; write-host -f green $msg
							If($cmdPath -like "*iisreset*"){sleep -s 5}
						}
					Else {
						$msg = "`tError`t" + $appDisplayName + " Failed with return code: " + $exitCode + "."
						Write-host -f magenta $msg
						$bFail = $true
					}
				}
			}
		
		$retval = $true
		If($bFail -eq $true){$retval = $false}
		Return $retval
	}

Function Update-SCCM()
	{
		$system32 = ($env:SystemRoot + "\system32")
		
		$arrCmds = @()
		#check sccm server version
		$serverVersion = (get-item 'C:\Program Files\Microsoft Configuration Manager\bin\x64\ccm.dll').VersionInfo.ProductVersion
		If($serverVersion.Substring(0,1) -eq 5 -and ($serverVersion.Substring((($serverVersion.length) - 3),3)) -ge 301)
			{$msg = "`t* SCCM Server is already at version CU2."; write-host -f green $msg}
		Else
			{
				#Server CU2
				$oCmd = New-Object System.Object
				$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\msiexec.exe")
				$oCmd | Add-Member -type NoteProperty -name "Args" -value ("/i """ + $sInstallFilesPath + "\SCCM 2012 CU2\configmgr2012-rtm-cu2-kb2780664-x64-enu.msi"" /qb")
				$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Installing SCCM Server 2012 Patch CU2."
				$arrCmds += $oCmd
			}
		
		#check sccm console version
		$serverVersion = (get-item "C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin\Adminui.application.dll").VersionInfo.ProductVersion
		If($serverVersion.Substring(0,1) -eq 5 -and ($serverVersion.Substring((($serverVersion.length) - 3),3)) -ge 301)
			{$msg = "`t* SCCM Console is already at version CU2."; write-host -f green $msg}
		Else
			{
				#Console CU2
				$oCmd = New-Object System.Object
				$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\msiexec.exe")
				$oCmd | Add-Member -type NoteProperty -name "Args" -value ("/p """ + $sInstallFilesPath + "\SCCM 2012 CU2\configmgr2012adminui-rtm-kb2780664-i386.msp"" /qb")
				$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Installing SCCM Console 2012 Patch CU2."
				$arrCmds += $oCmd
			}
		
		$bFail = $false
		If($arrCmds.Count -ge 1)
			{
				$arrCmds | % {
					$cmdPath = $_.FullFilePath
					$cmdArgs = $_.Args
					$appDisplayName = $_.Displayname
					
#					$msg = "`t* " + $appDisplayName
#					write-host $msg
					
					$p = $null
					$p = Start-Process $cmdPath -ArgumentList $cmdArgs -Wait -NoNewWindow -PassThru -RedirectStandardOutput out.txt
					$exitCode = $p.ExitCode
					If($exitCode -eq 0 -or $exitcode -eq 3010 -or $exitcode -eq 183)
						{
							$msg = "`t" + $appDisplayName + " Completed with exit code " + $exitcode + "."; write-host -f green $msg
							If($cmdPath -like "*iisreset*"){sleep -s 5}
						}
					Else {
						$msg = "`tError`t" + $appDisplayName + " Failed with return code: " + $exitCode + "."
						Write-host -f magenta $msg
						$bFail = $true
					}
				}
			}
		
		$retval = $true
		If($bFail -eq $true){$retval = $false}
		Return $retval
	}

Function Configure-Webdav-Dirbrowsing()
	{
		$msg = "== Configuring WebDAV and Directory Browsing =="
		Write-host -f cyan $msg
		
		##REF: http://www.iis.net/learn/publish/using-webdav/how-to-configure-webdav-settings-using-appcmd
		
		$system32 = ($env:windir).TrimEnd("\") + "\system32"
		$arrCmds = @()
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\inetsrv\AppCmd.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "add vdir /app.name:""Default Web Site/"" /path:/source /physicalPath:F:\shares\source"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Adding IIS virtual directory ""/source""."
		$arrCmds += $oCmd
		
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\inetsrv\AppCmd.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "set config ""Default Web Site/"" /section:system.webServer/webdav/authoring /enabled:true /commit:apphost"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Enabling WebDAV."
		$arrCmds += $oCmd
		
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\inetsrv\AppCmd.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "set config ""Default Web Site/"" /section:system.webServer/webdav/authoring /requireSsl:true /commit:apphost"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Enabling WebDAV SSL Requirement."
		$arrCmds += $oCmd
		
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\inetsrv\AppCmd.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "set config ""Default Web Site/"" /section:system.webServer/webdav/authoring /fileSystem.allowHiddenFiles:false /commit:apphost"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Enabling WebDAV hidden files filter."
		$arrCmds += $oCmd
		
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\inetsrv\AppCmd.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "set config ""Default Web Site/source"" /section:system.webServer/webdav/authoringRules /allowNonMimeMapFiles:true /commit:apphost"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Adding WebDAV to serve non-mime files."
		$arrCmds += $oCmd
		
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\inetsrv\AppCmd.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value ("set config ""Default Web Site/source"" /section:system.webServer/webdav/authoringRules /+[users='ACL_SCCM-" + $siteCode + "1_SourceShare_AllowRead',path='*',access='Read,Source'] /commit:apphost")
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Adding WebDAV authoring rule."
		$arrCmds += $oCmd
		
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\inetsrv\AppCmd.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "set config ""Default Web Site/source"" /section:directoryBrowse /enabled:true"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Enabling directory browsing."
		$arrCmds += $oCmd
		
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\inetsrv\AppCmd.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value ("set config ""Default Web Site/source"" /section:BasicAuthentication /defaultLogonDomain:" + $domainSuffix + " /realm:" + $domainSuffix + " /Enabled:True /commit:APPHOST")
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Enabling Basic Authentication on source vDir."
		$arrCmds += $oCmd
		
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\inetsrv\AppCmd.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "set config ""Default Web Site/source"" /section:anonymousAuthentication /enabled:false /commit:apphost"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Disabling Anonymous Authentication on source vDir."
		$arrCmds += $oCmd
		
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\inetsrv\AppCmd.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "set config ""Default Web Site/source"" /section:access /sslFlags:Ssl /commit:APPHOST"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Enabling SSL Required on source vDir."
		$arrCmds += $oCmd
		
		$msg = "`tAdding IIS_IUSRS to permissions on source directory."
		Write-Host $msg
		$hshUsers = @{}
		$hshUsers.Add(("BUILTIN\IIS_IUSRS"), "Read")
		Set-FolderPermissions "F:\Shares\Source" $hshUsers
		
		$bFail = $false
		$arrCmds | % {
			$cmdPath = $_.FullFilePath
			$cmdArgs = $_.Args
			$appDisplayName = $_.Displayname
			
			$p = $null
			$p = Start-Process $cmdPath -ArgumentList $cmdArgs -Wait -NoNewWindow -PassThru -RedirectStandardOutput out.txt
			$exitCode = $p.ExitCode
			If($exitCode -eq 0 -or $exitcode -eq 3010 -or $exitcode -eq 183)
				{
					$msg = "`t" + $appDisplayName + " completed with exit code " + $exitcode + "."; write-host -f green $msg
					If($cmdPath -like "*iisreset*"){sleep -s 5}
				}
			Else {
				$msg = "`tError`t" + $appDisplayName + " failed with return code: " + $exitCode + "."
				Write-host -f magenta $msg
				$bFail = $true
			}
		}
		$retval = $true
		If($bFail -eq $true){$retval = $false}
		Return $retval
	}

Function Run-Action($sAction)
	{
		$retval = $true
		Switch($sAction)
			{
				"preUpgradeCheck" {$retval = PreUpgradeCheck}
				"createSCCMGroups" {$retval = Create-SCCMGroups}
				"serverConfig" {$retval = ServerConfig}
				"configureSystemsManagementContainer" {$retval = Configure-SystemsManagementContainer}
				"createSCCMUsers" {$retval = Create-SCCMUsers}
				"createSCCMShares" {$retval = Create-SCCMShares}
				"installDotNet35" {$retval = Install-Role "dotNet35"}
				"installDotNet4" {$retval = Install-App "dotNet4"}
				"installSQL2008" {$retval = Install-App "SQL2008"}
				"configureSQL" {$retval = Configure-SQL}
				"installSCCMRoles" {$retval = Install-SCCMRoles}
				"Configure-IISForSCCM" {$retval = Configure-IISForSCCM}
				"installWSUS" {$retval = Install-App "WSUS"}
				"installWSUS-kb2734608" {$retval = Install-App "WSUS-KB2734608"}
				"install-subca" {$retval = Install-SubCA}
				"Configure-SubCA" {$retval = Configure-SubCA}
				"download-sccm-prereqs" {$retval = Prep-SCCMInstall}
				"install-sccmsiteserver" {$retval = Install-SCCM}
				"update-sccm-cu2" {$retval = Update-SCCM}
				"configure-webdav-dirbrowsing" {$retval = Configure-Webdav-Dirbrowsing}
				Default {$msg = "`tError - action """ + $sAction + """ isn't defined."; Write-host -f magenta $msg; $retval = $false}
			}
		Return $retval
	}

$actions | % {
	If($bFail -eq $false)
		{
			$results = $null; $results = Run-Action $_
			If($results -eq $false){$bFail = $true}
		}
}

#$test = PreUpgradeCheck
#write-host -f yellow $test
