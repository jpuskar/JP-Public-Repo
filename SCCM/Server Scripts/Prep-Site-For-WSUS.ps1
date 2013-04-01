###########################################################
# AUTHOR  : Marius / Hican - http://www.hican.nl - @hicannl
# DATE    : 16-08-2012
# COMMENT : This script creates the Collection / Package /
#           Metering / Etc. Folders in SCCM 2012, based on
#           an input file.
###########################################################

#ERROR REPORTING ALL
#Set-StrictMode -Version latest

$orgName = "Chemistry"
$sitecode = "TES"
$domainShort = "dev-sccm"

Function Get-FolderID ($folderName,$parentID,$siteCode)
	{
		$folderID = $null
		$query = $null
		$query = "SELECT ContainerNodeID FROM SMS_ObjectContainerNode WHERE Name = '" + $folderName + "' AND ObjectType = '5000' AND ParentContainerNodeID = '" + $parentID + "'"
		$oFolder = $null
		Try{$oFolder = GWMI -Namespace ("ROOT\SMS\Site_" + $sitecode) -Query $query}
		Catch{$oFolder = $false}
		
		If($oFolder -eq $false -or $oFolder -eq $null -or $oFolder -eq "")
			{$folderID = $false}
		Else
			{$folderID = $oFolder.ContainerNodeID}
		Return $folderID
	}

Function Create-DeviceFolderPath($folderPath,$siteCode)
	{
		$folders = $null
		If($folderPath -like "*/*")
			{$folders = $folderPath.Split("/")}
		Else
			{$folders = @(); $folders += $folderPath}
		
		$cleanFolders = $null
		$cleanFolders = @()
		$folders | % {
			$length = $_.length
			If($length -gt 0)
				{$cleanFolders += $_}
		}
		$folders = $cleanFolders
		
		$i = 0
		While($i -lt $folders.Count)
			{
				$newFolderName = $folders[$i]
				#write-host -f cyan "working on folder $i named $newFolderName"
				
				$j = $i
				$curParentID = 0
				#Figure out what the parentID of the current folder we're looking at would be if it exists
				while ($j -gt 0)
					{$curParentID = Get-FolderID $folders[($i - $j)] $curParentID $siteCode; $j = $j - 1}
				$expectedParentID = $curParentID
				
				#If we plug that expectedID in, do we get a result? If not, the folder doesn't exist.
				$CurFolderID = $null
				#write-host -f cyan "Checking the ID of folder $newfoldername with expected ID of $expectedParentID in site $sitecode"
				$CurFolderID = Get-FolderID $newFolderName $expectedParentID $siteCode
				#write-host -f cyan "folder has parent ID $CurFolderID"
				
				#This is a little redundant, but it's more clear to me. Sorry to waste space.
				$bCurFolderExists = $false
				If($CurFolderID -eq $false -or $CurFolderID -eq $null -or $CurFolderID -eq "")
					{$bCurFolderExists = $false}
				Else{$bCurFolderExists = $true}
				#create the folder if DNE
				If($bCurFolderExists -eq $true)
					{}
				Else
					{
						$newFolderName = $folders[$i]
						write-host -f cyan "Creating folder $newFolderName"
						$action = Create-DeviceFolder $newFolderName $expectedParentID $siteCode
					}
				$i++
			}
	}
		
Function Create-DeviceFolder ($folderName,$parentID,$siteCode)
	{
		$folderClass                     = [WMIClass] ("ROOT\SMS\Site_" + $siteCode + ":SMS_ObjectContainerNode")
    $newFolder                       = $folderClass.CreateInstance()
    $newFolder.Name                  = $folderName
    $newFolder.ObjectType            = 5000
    $newFolder.ParentContainerNodeid = $ParentID
    $folderPath                      = $newFolder.Put()
	}

Function Get-CollectionID($siteCode, $colName)
	{
		#Search folders and subfolders for the first collection matching $colName and return it's ID.
		
		$rootFolderID = $null
		$rootFolderID = Get-FolderID $orgName 0 $siteCode
		
		$query = "SELECT * FROM SMS_Collection WHERE Name = '" + $colName + "' AND CollectionType = '2'"
		$oCollections = GWMI -Namespace ("ROOT\SMS\Site_" + $sitecode) -Query $query
		$ColId = $oCollections.CollectionID
		
		#write-host -f yellow $colId
		Return $colId
	}

Function Search-OrgFolders-NameToFolderID($siteCode,$orgName,$folderName)
	{
		#get orgname folder ID
		$rootID = Get-FolderID $orgName 0 $siteCode
		
		#Get all folders named $folderName
		$query = $null
		$query = "SELECT * FROM SMS_ObjectContainerNode WHERE Name = '" + $folderName + "' AND ObjectType = '5000'"
		$oFolders = $null
		$oFolders = GWMI -Namespace ("ROOT\SMS\Site_" + $sitecode) -Query $query
		
		$retval = 0
		$oFolders | % {
			$curID = $_.ParentContainerNodeID
			While($curID -ne $rootID -and $curID -ne 0)
				{
					$query = $null
					$query = "SELECT * FROM SMS_ObjectContainerNode WHERE ContainerNodeID = '" + $curID + "'"
					$oFolder = $null
					$oFolder = GWMI -Namespace ("ROOT\SMS\Site_" + $sitecode) -Query $query
					$curID = $oFolder.ParentContainerNodeID
					
					#$curName = $oFolder.Name
					#write-host -f yellow "checking folder $curName with parent $curID to see if it matches the orgname folder $orgName with ID $rootID"
				}
			
			If($curID -eq 0)
				{}
			Else
				{$retval = $_.ContainerNodeID}
		}
		
		#write-host -f cyan "`treturning container id $retval"
		
		Return $retval
	}


Function Get-WsusAndEppCollections-Round1($siteCode,$domainShort)
	{
		$oCols = $null
		$oCols = @()
		
		$siteCode = $siteCode.ToUpper()
		
		$sAllUpdateComps = ("All " + $sitecode + " Update Computers")
		$sAllComps = ("All " + $sitecode + " Computers")
		$sSoftwareUpdates = "Software Updates"
		$sInitialDeployments = "Initial Deployments"
		$sEndpointFolderName = "Endpoint Custom Anti-Malware Settings"
		$domainShort = $domainShort.ToUpper()
		
		#All Update Computers
		$oCol = New-Object System.Object
		$oCol | Add-Member -type NoteProperty -name "CollectionType" -value 2
		$oCol | Add-Member -type NoteProperty -name "CollectionName" -value $sAllUpdateComps
		$oCol | Add-Member -type NoteProperty -name "LimitingCollectionID" -value (Get-CollectionID $siteCode ("All " + $siteCode + " Computers"))
		$oCol | Add-Member -type NoteProperty -name "CollectionFolder" -value (Search-OrgFolders-NameToFolderID $siteCode $orgName $sSoftwareUpdates)
		#Add Queries
		$hshQueries = $null
		$hshQueries = @{}
		$oCol | Add-Member -type NoteProperty -name "Queries" -value $hshQueries
		$oCols += $oCol
		
		
		#Domain Controllers
		$oCol = New-Object System.Object
		$oCol | Add-Member -type NoteProperty -name "CollectionType" -value 2
		$oCol | Add-Member -type NoteProperty -name "CollectionName" -value ($siteCode + " Domain Controllers")
		$oCol | Add-Member -type NoteProperty -name "LimitingCollectionID" -value (Get-CollectionID $siteCode $sAllComps)
		$oCol | Add-Member -type NoteProperty -name "CollectionFolder" -value (Search-OrgFolders-NameToFolderID $siteCode $orgName $sEndpointFolderName)
		#Add Queries
		$queryName = "Query by OU for Domain Controllers"
		$query = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System where SMS_R_System.SystemOUName = """ + $domainShort + "/DOMAIN CONTROLLERS"""
		$hshQueries = $null
		$hshQueries = @{}
		$hshQueries.Add($queryName,$query)
		$oCol | Add-Member -type NoteProperty -name "Queries" -value $hshQueries
		$oCols += $oCol
		
		
		#File Servers
		$oCol = New-Object System.Object
		$oCol | Add-Member -type NoteProperty -name "CollectionType" -value 2
		$oCol | Add-Member -type NoteProperty -name "CollectionName" -value ($siteCode + " File Servers")
		$oCol | Add-Member -type NoteProperty -name "LimitingCollectionID" -value (Get-CollectionID $siteCode $sAllComps)
		$oCol | Add-Member -type NoteProperty -name "CollectionFolder" -value (Search-OrgFolders-NameToFolderID $siteCode $orgName $sEndpointFolderName)
		#Add Queries
		$queryName = "Query by System Role for File Servers"
		$query = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System inner join SMS_G_System_SERVER_FEATURE on SMS_G_System_SERVER_FEATURE.ResourceId = SMS_R_System.ResourceId where SMS_G_System_SERVER_FEATURE.Name = ""File Server"""
		$hshQueries = $null
		$hshQueries = @{}
		$hshQueries.Add($queryName,$query)
		$oCol | Add-Member -type NoteProperty -name "Queries" -value $hshQueries
		$oCols += $oCol
		
		
		#IIS Servers
		$oCol = New-Object System.Object
		$oCol | Add-Member -type NoteProperty -name "CollectionType" -value 2
		$oCol | Add-Member -type NoteProperty -name "CollectionName" -value ($siteCode + " IIS Servers")
		$oCol | Add-Member -type NoteProperty -name "LimitingCollectionID" -value (Get-CollectionID $siteCode $sAllComps)
		$oCol | Add-Member -type NoteProperty -name "CollectionFolder" -value (Search-OrgFolders-NameToFolderID $siteCode $orgName $sEndpointFolderName)
		#Add Queries
		$queryName = "Query for IIS Management Console"
		$query = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System inner join SMS_G_System_SERVER_FEATURE on SMS_G_System_SERVER_FEATURE.ResourceId = SMS_R_System.ResourceId where SMS_G_System_SERVER_FEATURE.Name = ""IIS Management Console"""
		$hshQueries = $null
		$hshQueries = @{}
		$hshQueries.Add($queryName,$query)
		$oCol | Add-Member -type NoteProperty -name "Queries" -value $hshQueries
		$oCols += $oCol
		
		
		#Operations Manager Servers
		$oCol = New-Object System.Object
		$oCol | Add-Member -type NoteProperty -name "CollectionType" -value 2
		$oCol | Add-Member -type NoteProperty -name "CollectionName" -value ($siteCode + " Operations Manager Servers")
		$oCol | Add-Member -type NoteProperty -name "LimitingCollectionID" -value (Get-CollectionID $siteCode $sAllComps)
		$oCol | Add-Member -type NoteProperty -name "CollectionFolder" -value (Search-OrgFolders-NameToFolderID $siteCode $orgName $sEndpointFolderName)
		#Add Queries
		$queryName = "FilePath Query for OpsMgr 2012 Server"
		$query = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System inner join SMS_G_System_SoftwareFile on SMS_G_System_SoftwareFile.ResourceID = SMS_R_System.ResourceId where SMS_G_System_SoftwareFile.FilePath = ""C:\\Program Files\\System Center 2012\\Operations Manager\\Server"""
		$hshQueries = $null
		$hshQueries = @{}
		$hshQueries.Add($queryName,$query)
		$oCol | Add-Member -type NoteProperty -name "Queries" -value $hshQueries
		$oCols += $oCol
		
		
		#SCCM Servers
		$oCol = New-Object System.Object
		$oCol | Add-Member -type NoteProperty -name "CollectionType" -value 2
		$oCol | Add-Member -type NoteProperty -name "CollectionName" -value ($siteCode + " SCCM Servers")
		$oCol | Add-Member -type NoteProperty -name "LimitingCollectionID" -value (Get-CollectionID $siteCode $sAllComps)
		$oCol | Add-Member -type NoteProperty -name "CollectionFolder" -value (Search-OrgFolders-NameToFolderID $siteCode $orgName $sEndpointFolderName)
		#Add Queries
		$queryName = "Name query for SCCM-"
		$query = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System where UPPER(SMS_R_System.Name) like ""%SCCM-%"""
		$hshQueries = $null
		$hshQueries = @{}
		$hshQueries.Add($queryName,$query)
		$oCol | Add-Member -type NoteProperty -name "Queries" -value $hshQueries
		$oCols += $oCol
		
		
		#SharePoint Servers
		$oCol = New-Object System.Object
		$oCol | Add-Member -type NoteProperty -name "CollectionType" -value 2
		$oCol | Add-Member -type NoteProperty -name "CollectionName" -value ($siteCode + " SharePoint Servers")
		$oCol | Add-Member -type NoteProperty -name "LimitingCollectionID" -value (Get-CollectionID $siteCode $sAllComps)
		$oCol | Add-Member -type NoteProperty -name "CollectionFolder" -value (Search-OrgFolders-NameToFolderID $siteCode $orgName $sEndpointFolderName)
		#Add Queries
		$queryName = "Query for SCCM Admin Service"
		$query = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System inner join SMS_G_System_SERVICE on SMS_G_System_SERVICE.ResourceId = SMS_R_System.ResourceId where SMS_G_System_SERVICE.Name = ""SPAdminV4"""
		$hshQueries = $null
		$hshQueries = @{}
		$hshQueries.Add($queryName,$query)
		$oCol | Add-Member -type NoteProperty -name "Queries" -value $hshQueries
		$oCols += $oCol
		
		
		#SharePoint Servers
		$oCol = New-Object System.Object
		$oCol | Add-Member -type NoteProperty -name "CollectionType" -value 2
		$oCol | Add-Member -type NoteProperty -name "CollectionName" -value ($siteCode + " SQL Servers")
		$oCol | Add-Member -type NoteProperty -name "LimitingCollectionID" -value (Get-CollectionID $siteCode $sAllComps)
		$oCol | Add-Member -type NoteProperty -name "CollectionFolder" -value (Search-OrgFolders-NameToFolderID $siteCode $orgName $sEndpointFolderName)
		#Add Queries
		$queryName = "CPanel Query for SQL Server"
		$query = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System where SMS_R_System.ResourceId in (select SMS_R_System.ResourceID from SMS_R_System inner join SMS_G_System_ADD_REMOVE_PROGRAMS on SMS_G_System_ADD_REMOVE_PROGRAMS.ResourceID = SMS_R_System.ResourceId where SMS_G_System_ADD_REMOVE_PROGRAMS.DisplayName like ""Microsoft SQL Server%"") and SMS_R_System.Obsolete = 0 and SMS_R_System.Client = 1"
		$hshQueries = $null
		$hshQueries = @{}
		$hshQueries.Add($queryName,$query)
		$oCol | Add-Member -type NoteProperty -name "Queries" -value $hshQueries
		$oCols += $oCol
		
		
		
		Return $oCols
	}

Function Get-WsusAndEppCollections-Round2($siteCode)
	{
		$oCols = $null
		$oCols = @()
		
		$siteCode = $siteCode.ToUpper()
		
		$sAllUpdateComps = ("All " + $sitecode + " Update Computers")
		$sSoftwareUpdates = "Software Updates"
		$sInitialDeployments = "Initial Deployments"
		$sAllComps = ("All " + $siteCode + " Computers")
		$sEndpointFolderName = "Endpoint Custom Anti-Malware Settings"
		
		#IIS and SQL Servers
		$oCol = New-Object System.Object
		$oCol | Add-Member -type NoteProperty -name "CollectionType" -value 2
		$oCol | Add-Member -type NoteProperty -name "CollectionName" -value ($siteCode + " IIS and SQL Servers")
		$oCol | Add-Member -type NoteProperty -name "LimitingCollectionID" -value (Get-CollectionID $siteCode ($sitecode + " IIS Servers"))
		$oCol | Add-Member -type NoteProperty -name "CollectionFolder" -value (Search-OrgFolders-NameToFolderID $siteCode $orgName $sEndpointFolderName)
		#Add Queries
		$queryName = "Query for SQL"
		$query = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System where SMS_R_System.ResourceId in (select SMS_R_System.ResourceID from SMS_R_System inner join SMS_G_System_ADD_REMOVE_PROGRAMS on SMS_G_System_ADD_REMOVE_PROGRAMS.ResourceID = SMS_R_System.ResourceId where SMS_G_System_ADD_REMOVE_PROGRAMS.DisplayName like ""Microsoft SQL Server%"")"
		$hshQueries = $null
		$hshQueries = @{}
		$hshQueries.Add($queryName,$query)
		$oCol | Add-Member -type NoteProperty -name "Queries" -value $hshQueries
		$oCols += $oCol
		
		
		#0 Day Updates
		$oCol = New-Object System.Object
		$oCol | Add-Member -type NoteProperty -name "CollectionType" -value 2
		$oCol | Add-Member -type NoteProperty -name "CollectionName" -value ($siteCode + " 0 Day Updates")
		$oCol | Add-Member -type NoteProperty -name "LimitingCollectionID" -value (Get-CollectionID $siteCode $sAllComps)
		$oCol | Add-Member -type NoteProperty -name "CollectionFolder" -value (Search-OrgFolders-NameToFolderID $siteCode $orgName $sSoftwareUpdates)
		#Add Queries
		$hshQueries = $null
		$hshQueries = @{}
		$oCol | Add-Member -type NoteProperty -name "Queries" -value $hshQueries
		$oCols += $oCol
		
		
		#write-host -f yellow "found"
		
		#14 Day Updates
		$oCol = New-Object System.Object
		$oCol | Add-Member -type NoteProperty -name "CollectionType" -value 2
		$oCol | Add-Member -type NoteProperty -name "CollectionName" -value ($siteCode + " 14 Day Updates")
		$oCol | Add-Member -type NoteProperty -name "LimitingCollectionID" -value (Get-CollectionID $siteCode $sAllComps)
		$oCol | Add-Member -type NoteProperty -name "CollectionFolder" -value (Search-OrgFolders-NameToFolderID $siteCode $orgName $sSoftwareUpdates)
		#Add Queries
		$hshQueries = $null
		$hshQueries = @{}
		$oCol | Add-Member -type NoteProperty -name "Queries" -value $hshQueries
		$oCols += $oCol
		
		
		#Initial Windows 7 x64 Updates
		$oCol = New-Object System.Object
		$oCol | Add-Member -type NoteProperty -name "CollectionType" -value 2
		$oCol | Add-Member -type NoteProperty -name "CollectionName" -value ($siteCode + " Initial Windows 7 x64 Updates")
		$oCol | Add-Member -type NoteProperty -name "LimitingCollectionID" -value (Get-CollectionID $siteCode $sAllUpdateComps)
		$oCol | Add-Member -type NoteProperty -name "CollectionFolder" -value (Search-OrgFolders-NameToFolderID $siteCode $orgName $sInitialDeployments)
		#Add Queries
		$queryName = "Query for Win7 x64"
		$query = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System inner join SMS_G_System_COMPUTER_SYSTEM on SMS_G_System_COMPUTER_SYSTEM.ResourceID = SMS_R_System.ResourceId where (SMS_R_System.OperatingSystemNameandVersion like ""%Workstation 6.1%"" or SMS_R_System.OperatingSystemNameandVersion like ""%Windows 7%"") and SMS_G_System_COMPUTER_SYSTEM.SystemType = ""x64-based PC"""
		$hshQueries = $null
		$hshQueries = @{}
		$hshQueries.Add($queryName,$query)
		$oCol | Add-Member -type NoteProperty -name "Queries" -value $hshQueries
		$oCols += $oCol
		
		
		#Initial Windows 7 x86 Updates
		$oCol = New-Object System.Object
		$oCol | Add-Member -type NoteProperty -name "CollectionType" -value 2
		$oCol | Add-Member -type NoteProperty -name "CollectionName" -value ($siteCode + " Initial Windows 7 x86 Updates")
		$oCol | Add-Member -type NoteProperty -name "LimitingCollectionID" -value (Get-CollectionID $siteCode $sAllUpdateComps)
		$oCol | Add-Member -type NoteProperty -name "CollectionFolder" -value (Search-OrgFolders-NameToFolderID $siteCode $orgName $sInitialDeployments)
		#Add Queries
		$queryName = "Query for Win7 x86"
		$query = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System inner join SMS_G_System_COMPUTER_SYSTEM on SMS_G_System_COMPUTER_SYSTEM.ResourceID = SMS_R_System.ResourceId where (SMS_R_System.OperatingSystemNameandVersion like ""%Workstation 6.1%"" or SMS_R_System.OperatingSystemNameandVersion like ""%Windows 7%"") and SMS_G_System_COMPUTER_SYSTEM.SystemType = ""x86-based PC"""
		$hshQueries = $null
		$hshQueries = @{}
		$hshQueries.Add($queryName,$query)
		$oCol | Add-Member -type NoteProperty -name "Queries" -value $hshQueries
		$oCols += $oCol
		
		
		#Initial Windows Vista x86 Updates
		$oCol = New-Object System.Object
		$oCol | Add-Member -type NoteProperty -name "CollectionType" -value 2
		$oCol | Add-Member -type NoteProperty -name "CollectionName" -value ($siteCode + " Initial Windows Vista x86 Updates")
		$oCol | Add-Member -type NoteProperty -name "LimitingCollectionID" -value (Get-CollectionID $siteCode $sAllUpdateComps)
		$oCol | Add-Member -type NoteProperty -name "CollectionFolder" -value (Search-OrgFolders-NameToFolderID $siteCode $orgName $sInitialDeployments)
		#Add Queries
		$queryName = "Query for Vista x86"
		$query = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System inner join SMS_G_System_COMPUTER_SYSTEM on SMS_G_System_COMPUTER_SYSTEM.ResourceID = SMS_R_System.ResourceId where (SMS_R_System.OperatingSystemNameandVersion like ""%Workstation 6.0%"" or SMS_R_System.OperatingSystemNameandVersion like ""%Vista%"") and SMS_G_System_COMPUTER_SYSTEM.SystemType = ""x86-based PC"""
		$hshQueries = $null
		$hshQueries = @{}
		$hshQueries.Add($queryName,$query)
		$oCol | Add-Member -type NoteProperty -name "Queries" -value $hshQueries
		$oCols += $oCol
		
		
		#Initial Windows Vista x64 Updates
		$oCol = New-Object System.Object
		$oCol | Add-Member -type NoteProperty -name "CollectionType" -value 2
		$oCol | Add-Member -type NoteProperty -name "CollectionName" -value ($siteCode + " Initial Windows Vista x64 Updates")
		$oCol | Add-Member -type NoteProperty -name "LimitingCollectionID" -value (Get-CollectionID $siteCode $sAllUpdateComps)
		$oCol | Add-Member -type NoteProperty -name "CollectionFolder" -value (Search-OrgFolders-NameToFolderID $siteCode $orgName $sInitialDeployments)
		#Add Queries
		$queryName = "Query for Vista x64"
		$query = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System inner join SMS_G_System_COMPUTER_SYSTEM on SMS_G_System_COMPUTER_SYSTEM.ResourceID = SMS_R_System.ResourceId where (SMS_R_System.OperatingSystemNameandVersion like ""%Workstation 6.0%"" or SMS_R_System.OperatingSystemNameandVersion like ""%Vista%"") and SMS_G_System_COMPUTER_SYSTEM.SystemType = ""x64-based PC"""
		$hshQueries = $null
		$hshQueries = @{}
		$hshQueries.Add($queryName,$query)
		$oCol | Add-Member -type NoteProperty -name "Queries" -value $hshQueries
		$oCols += $oCol
		
		
		#Initial Windows XP x86 Updates
		$oCol = New-Object System.Object
		$oCol | Add-Member -type NoteProperty -name "CollectionType" -value 2
		$oCol | Add-Member -type NoteProperty -name "CollectionName" -value ($siteCode + " Initial Windows XP x86 Updates")
		$oCol | Add-Member -type NoteProperty -name "LimitingCollectionID" -value (Get-CollectionID $siteCode $sAllUpdateComps)
		$oCol | Add-Member -type NoteProperty -name "CollectionFolder" -value (Search-OrgFolders-NameToFolderID $siteCode $orgName $sInitialDeployments)
		#Add Queries
		$queryName = "Query for XP x86"
		$query = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System inner join SMS_G_System_COMPUTER_SYSTEM on SMS_G_System_COMPUTER_SYSTEM.ResourceID = SMS_R_System.ResourceId where (SMS_R_System.OperatingSystemNameandVersion like ""%Workstation 5%"" or SMS_R_System.OperatingSystemNameandVersion like ""%Windows XP%"") and SMS_G_System_COMPUTER_SYSTEM.SystemType = ""x86-based PC"""
		$hshQueries = $null
		$hshQueries = @{}
		$hshQueries.Add($queryName,$query)
		$oCol | Add-Member -type NoteProperty -name "Queries" -value $hshQueries
		$oCols += $oCol
		
		
		#Initial Windows XP x64 Updates
		$oCol = New-Object System.Object
		$oCol | Add-Member -type NoteProperty -name "CollectionType" -value 2
		$oCol | Add-Member -type NoteProperty -name "CollectionName" -value ($siteCode + " Initial Windows XP x64 Updates")
		$oCol | Add-Member -type NoteProperty -name "LimitingCollectionID" -value (Get-CollectionID $siteCode $sAllUpdateComps)
		$oCol | Add-Member -type NoteProperty -name "CollectionFolder" -value (Search-OrgFolders-NameToFolderID $siteCode $orgName $sInitialDeployments)
		#Add Queries
		$queryName = "Query for XP x64"
		$query = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System inner join SMS_G_System_COMPUTER_SYSTEM on SMS_G_System_COMPUTER_SYSTEM.ResourceID = SMS_R_System.ResourceId where (SMS_R_System.OperatingSystemNameandVersion like ""%Workstation 5%"" or SMS_R_System.OperatingSystemNameandVersion like ""%Windows XP%"") and SMS_G_System_COMPUTER_SYSTEM.SystemType = ""x64-based PC"""
		$hshQueries = $null
		$hshQueries = @{}
		$hshQueries.Add($queryName,$query)
		$oCol | Add-Member -type NoteProperty -name "Queries" -value $hshQueries
		$oCols += $oCol
		
		
		#Initial Internet Explorer 6 Updates
		$oCol = New-Object System.Object
		$oCol | Add-Member -type NoteProperty -name "CollectionType" -value 2
		$oCol | Add-Member -type NoteProperty -name "CollectionName" -value ($siteCode + " Initial Internet Explorer 6 Updates")
		$oCol | Add-Member -type NoteProperty -name "LimitingCollectionID" -value (Get-CollectionID $siteCode $sAllUpdateComps)
		$oCol | Add-Member -type NoteProperty -name "CollectionFolder" -value (Search-OrgFolders-NameToFolderID $siteCode $orgName $sInitialDeployments)
		#Add Queries
		$queryName = "Query for IE6"
		$query = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System inner join SMS_G_System_SoftwareFile on SMS_G_System_SoftwareFile.ResourceID = SMS_R_System.ResourceId where SMS_G_System_SoftwareFile.FileName = ""iexplore.exe"" and SMS_G_System_SoftwareFile.FileVersion like ""6.%"""
		$hshQueries = $null
		$hshQueries = @{}
		$hshQueries.Add($queryName,$query)
		$oCol | Add-Member -type NoteProperty -name "Queries" -value $hshQueries
		$oCols += $oCol
		
		
		#Initial Internet Explorer 7 Updates
		$oCol = New-Object System.Object
		$oCol | Add-Member -type NoteProperty -name "CollectionType" -value 2
		$oCol | Add-Member -type NoteProperty -name "CollectionName" -value ($siteCode + " Initial Internet Explorer 7 Updates")
		$oCol | Add-Member -type NoteProperty -name "LimitingCollectionID" -value (Get-CollectionID $siteCode $sAllUpdateComps)
		$oCol | Add-Member -type NoteProperty -name "CollectionFolder" -value (Search-OrgFolders-NameToFolderID $siteCode $orgName $sInitialDeployments)
		#Add Queries
		$queryName = "Query for IE7"
		$query = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System inner join SMS_G_System_SoftwareFile on SMS_G_System_SoftwareFile.ResourceID = SMS_R_System.ResourceId where SMS_G_System_SoftwareFile.FileName = ""iexplore.exe"" and SMS_G_System_SoftwareFile.FileVersion like ""7.%"""
		$hshQueries = $null
		$hshQueries = @{}
		$hshQueries.Add($queryName,$query)
		$oCol | Add-Member -type NoteProperty -name "Queries" -value $hshQueries
		$oCols += $oCol
		
		
		#Initial Internet Explorer 8 Updates
		$oCol = New-Object System.Object
		$oCol | Add-Member -type NoteProperty -name "CollectionType" -value 2
		$oCol | Add-Member -type NoteProperty -name "CollectionName" -value ($siteCode + " Initial Internet Explorer 8 Updates")
		$oCol | Add-Member -type NoteProperty -name "LimitingCollectionID" -value (Get-CollectionID $siteCode $sAllUpdateComps)
		$oCol | Add-Member -type NoteProperty -name "CollectionFolder" -value (Search-OrgFolders-NameToFolderID $siteCode $orgName $sInitialDeployments)
		#Add Queries
		$queryName = "Query for IE8"
		$query = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System inner join SMS_G_System_ADD_REMOVE_PROGRAMS_64 on SMS_G_System_ADD_REMOVE_PROGRAMS_64.ResourceID = SMS_R_System.ResourceId inner join SMS_G_System_SoftwareFile on SMS_G_System_SoftwareFile.ResourceId = SMS_R_System.ResourceId where SMS_G_System_SoftwareFile.FileName = ""iexplore.exe"" and SMS_G_System_SoftwareFile.FileVersion like ""8.%"""
		$hshQueries = $null
		$hshQueries = @{}
		$hshQueries.Add($queryName,$query)
		$oCol | Add-Member -type NoteProperty -name "Queries" -value $hshQueries
		$oCols += $oCol
		
		
		#Initial Internet Explorer 9 Updates
		$oCol = New-Object System.Object
		$oCol | Add-Member -type NoteProperty -name "CollectionType" -value 2
		$oCol | Add-Member -type NoteProperty -name "CollectionName" -value ($siteCode + " Initial Internet Explorer 9 Updates")
		$oCol | Add-Member -type NoteProperty -name "LimitingCollectionID" -value (Get-CollectionID $siteCode $sAllUpdateComps)
		$oCol | Add-Member -type NoteProperty -name "CollectionFolder" -value (Search-OrgFolders-NameToFolderID $siteCode $orgName $sInitialDeployments)
		#Add Queries
		$queryName = "Query for IE9"
		$query = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System inner join SMS_G_System_SoftwareFile on SMS_G_System_SoftwareFile.ResourceID = SMS_R_System.ResourceId where SMS_G_System_SoftwareFile.FileName = ""iexplore.exe"" and SMS_G_System_SoftwareFile.FileVersion like ""9.%"""
		$hshQueries = $null
		$hshQueries = @{}
		$hshQueries.Add($queryName,$query)
		$oCol | Add-Member -type NoteProperty -name "Queries" -value $hshQueries
		$oCols += $oCol
		
		
		#Initial Office 2002/XP Updates
		$oCol = New-Object System.Object
		$oCol | Add-Member -type NoteProperty -name "CollectionType" -value 2
		$oCol | Add-Member -type NoteProperty -name "CollectionName" -value ($siteCode + " Initial Office 2002/XP Updates")
		$oCol | Add-Member -type NoteProperty -name "LimitingCollectionID" -value (Get-CollectionID $siteCode $sAllUpdateComps)
		$oCol | Add-Member -type NoteProperty -name "CollectionFolder" -value (Search-OrgFolders-NameToFolderID $siteCode $orgName $sInitialDeployments)
		#Add Queries
		$queryName = "Query for Office 2002 or XP"
		$query = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System where SMS_R_System.ResourceId in (select SMS_R_System.ResourceID from SMS_R_System inner join SMS_G_System_ADD_REMOVE_PROGRAMS on SMS_G_System_ADD_REMOVE_PROGRAMS.ResourceID = SMS_R_System.ResourceId where SMS_G_System_ADD_REMOVE_PROGRAMS.DisplayName like ""Microsoft Office%XP%"") and SMS_R_System.Obsolete = 0 and SMS_R_System.Client = 1"
		$hshQueries = $null
		$hshQueries = @{}
		$hshQueries.Add($queryName,$query)
		$oCol | Add-Member -type NoteProperty -name "Queries" -value $hshQueries
		$oCols += $oCol
		
		
		#Initial Office 2003 Updates
		$oCol = New-Object System.Object
		$oCol | Add-Member -type NoteProperty -name "CollectionType" -value 2
		$oCol | Add-Member -type NoteProperty -name "CollectionName" -value ($siteCode + " Initial Office 2003 Updates")
		$oCol | Add-Member -type NoteProperty -name "LimitingCollectionID" -value (Get-CollectionID $siteCode $sAllUpdateComps)
		$oCol | Add-Member -type NoteProperty -name "CollectionFolder" -value (Search-OrgFolders-NameToFolderID $siteCode $orgName $sInitialDeployments)
		#Add Queries
		$queryName = "Query for Office 2003"
		$query = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System where SMS_R_System.ResourceId in (select SMS_R_System.ResourceID from SMS_R_System inner join SMS_G_System_ADD_REMOVE_PROGRAMS on SMS_G_System_ADD_REMOVE_PROGRAMS.ResourceID = SMS_R_System.ResourceId where SMS_G_System_ADD_REMOVE_PROGRAMS.DisplayName like ""Microsoft Office%2003%"") and SMS_R_System.Obsolete = 0 and SMS_R_System.Client = 1"
		$hshQueries = $null
		$hshQueries = @{}
		$hshQueries.Add($queryName,$query)
		$oCol | Add-Member -type NoteProperty -name "Queries" -value $hshQueries
		$oCols += $oCol
		
		
		#Initial Office 2007 Updates
		$oCol = New-Object System.Object
		$oCol | Add-Member -type NoteProperty -name "CollectionType" -value 2
		$oCol | Add-Member -type NoteProperty -name "CollectionName" -value ($siteCode + " Initial Office 2007 Updates")
		$oCol | Add-Member -type NoteProperty -name "LimitingCollectionID" -value (Get-CollectionID $siteCode $sAllUpdateComps)
		$oCol | Add-Member -type NoteProperty -name "CollectionFolder" -value (Search-OrgFolders-NameToFolderID $siteCode $orgName $sInitialDeployments)
		#Add Queries
		$queryName = "Query for Office 2007"
		$query = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System where SMS_R_System.ResourceId in (select SMS_R_System.ResourceID from SMS_R_System inner join SMS_G_System_ADD_REMOVE_PROGRAMS on SMS_G_System_ADD_REMOVE_PROGRAMS.ResourceID = SMS_R_System.ResourceId where SMS_G_System_ADD_REMOVE_PROGRAMS.DisplayName like ""Microsoft Office%2007%"") and SMS_R_System.Obsolete = 0 and SMS_R_System.Client = 1"
		$hshQueries = $null
		$hshQueries = @{}
		$hshQueries.Add($queryName,$query)
		$oCol | Add-Member -type NoteProperty -name "Queries" -value $hshQueries
		$oCols += $oCol
		
		
		#Initial Office 2010 Updates
		$oCol = New-Object System.Object
		$oCol | Add-Member -type NoteProperty -name "CollectionType" -value 2
		$oCol | Add-Member -type NoteProperty -name "CollectionName" -value ($siteCode + " Initial Office 2010 Updates")
		$oCol | Add-Member -type NoteProperty -name "LimitingCollectionID" -value (Get-CollectionID $siteCode $sAllUpdateComps)
		$oCol | Add-Member -type NoteProperty -name "CollectionFolder" -value (Search-OrgFolders-NameToFolderID $siteCode $orgName $sInitialDeployments)
		#Add Queries
		$queryName = "Query for Office 2010"
		$query = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System where SMS_R_System.ResourceId in (select SMS_R_System.ResourceID from SMS_R_System inner join SMS_G_System_ADD_REMOVE_PROGRAMS on SMS_G_System_ADD_REMOVE_PROGRAMS.ResourceID = SMS_R_System.ResourceId where SMS_G_System_ADD_REMOVE_PROGRAMS.DisplayName like ""Microsoft Office%2010%"") and SMS_R_System.Obsolete = 0 and SMS_R_System.Client = 1"
		$hshQueries = $null
		$hshQueries = @{}
		$hshQueries.Add($queryName,$query)
		$oCol | Add-Member -type NoteProperty -name "Queries" -value $hshQueries
		$oCols += $oCol
		
		Return $oCols
	}

Function Create-Collection($siteCode,$oCol)
	{
		#Check that collection DNE
		$query = "SELECT * FROM SMS_Collection WHERE Name = '" + $oCol.CollectionName + "' AND CollectionType = '" + $oCol.collectionType + "'"
		$testCol = GWMI -Namespace ("ROOT\SMS\Site_" + $sitecode) -Query $query
    
    $name = $oCol.CollectionName
    #create the col
    If ($testCol -eq "" -Or $testCol -eq $Null)
	    {
	    	Write-host -f cyan "Creating collection: $name"
	      $colClass                     = [WMIClass] ("ROOT\SMS\Site_" + $sitecode + ":SMS_Collection")
	      $newCol                       = $colClass.CreateInstance()
	      $newCol.Name                  = $oCol.CollectionName
	      $newCol.CollectionType        = $oCol.CollectionType
	      $newCol.LimitToCollectionID   = $oCol.LimitingCollectionID
				$colPath = $newCol.Put()
			}
		Else
			{write-host -f green "The collection named $name already exists."}
		
		#move the col
		#first, get the collection and check the current folder ID. Does it match $oCol.CollectionFolder?
		$colIdQuery = "SELECT * FROM SMS_Collection WHERE Name = '" + $oCol.CollectionName + "' AND CollectionType = '" + $oCol.collectionType + "'"
		$oNewCol = GWMI -Namespace ("ROOT\SMS\Site_" + $sitecode) -Query $colIdQuery
		$collectionID = $oNewCol.CollectionID

		#Write-Host -f cyan "Moving the collection $name."
		$method                         = "MoveMembers"
		$colClass                       = [WMIClass] ("ROOT\SMS\Site_" + $sitecode + ":SMS_ObjectContainerItem")
		$InParams                       = $colClass.psbase.GetMethodParameters($method)            
		$InParams.ContainerNodeID       = "0"
		$InParams.InstanceKeys          = $collectionID
		$InParams.ObjectType            = 5000
		$InParams.TargetContainerNodeID = $oCol.CollectionFolder
		$moveObject                     = $colClass.psbase.InvokeMethod($method,$InParams,$Null)
#			}
		
		#add the queries
		#Get the specified collection (to make sure we have the lazy properties)
		$hshQueries = $oCol.Queries
		$queryNames = $hshQueries.Keys
		If($queryNames -ne $null)
			{
				$queryNames | % {
					$newRuleName = $_
					
					#open collection object
					$wmiQuery = "\\.\ROOT\SMS\Site_" + $siteCode + ":SMS_Collection.CollectionID='" + $collectionID + "'"
					$coll = [wmi]$wmiQuery
					
					$bAlreadyExists = $false
					$colRules = $coll.CollectionRules
					$colRules | % {
						If($_.ruleName -eq $newRuleName)
							{$bAlreadyExists = $true}
					}
					
					If($bAlreadyExists -eq $false)
						{
							Write-Host -f cyan "`tAdding collection $name query rule ""$newRuleName""."
							
							#Create a new rule
							$wmiQuery =  "\\.\ROOT\SMS\Site_" + $siteCode + ":SMS_CollectionRuleQuery"
							$ruleClass = [wmiclass]$wmiQuery
							$newRule = $ruleClass.CreateInstance()
							$newRule.RuleName = $newRuleName
							$newRule.QueryExpression = $hshQueries.Get_Item($_)
							$null = $coll.AddMembershipRule($newRule)
						}
					Else
						{Write-Host -f green "`tCollection $name query rule ""$newRuleName"" already exists."}
				}
			}
		
	}


#Create org folders
$aFolders = $null
$aFolders = @()
$aFolders += "/" + $orgName + "/Software Updates/Initial Deployments"
$aFolders += "/" + $orgName + "/Endpoint Custom Anti-Malware Settings"
#$aFolders += "/John/test folder/path 2/asdf/more"
$aFolders | % {$action = Create-DeviceFolderPath $_ $siteCode}

#Create WSUS Collections and Queries
$oColls = $null
$oColls = Get-WsusAndEppCollections-Round1 $siteCode $domainShort
$oColls | % {$action = Create-Collection $siteCode $_}
$oColls = Get-WsusAndEppCollections-Round2 $siteCode
$oColls | % {$action = Create-Collection $siteCode $_}