######################################################################################
#Script Name: Get-PackageInfo.ps1
#Authored By: Robert Holbert - Holbert.26@Chemistry.Ohio-State.edu
#Created On: 9/19/2012
#Function: Checks For Changes in Software Packages and Pushes any Changes to GitHub Repo
######################################################################################


##Variables
$GitPath = "C:\GitHub\ASC-SCCM-Private"
$gitUsername = "ASC-SCCM-Robot"
$gitEmail = "win-team@chem.osu.edu"
$PackagePath = $GitPath + "\Packages\"
$logFileRoot = "C:\logs\Get-PackageInfo\"
$PasswordPath = "C:\Scripts\Get-PackageInfo\GitPassword.txt"
$GitPasswd = get-content $PasswordPath
$WebRepositoryPath = "github.com/ASCTech/ASC-SCCM-Private.git"
$AuthWebRepositoryPath = "https://" + $GitUsername + ':' + $GitPasswd + '@' + $WebRepositoryPath

If((Test-Path $GitPath) -eq $false)
	{
		$msg = "Repo root path DNE (" + $GitPath + ")."
		Write-host -f magenta
		Exit
	}


##LOG FILE FUNCTION Code REF - http://powershellcommunity.org/Forums/tabid/54/aft/4700/Default.aspx  
function write-log([string]$info){
    if($loginitialized -eq $false){            
        $FileHeader | Out-File $logfile -Append -Confirm:$false -encoding "UTF8"          
        $script:loginitialized = $True            
    }            
    $info | Out-File $logfile -Append -Confirm:$false -encoding "UTF8"
}            
   
##############################################################################

Function WritePackageFilesToFile($ThisPackage)
{
trap [Exception] { 
      write-log
      write-log $("TRAPPED: " + $_.Exception.GetType().FullName); 
      write-log $("TRAPPED: " + $_.Exception.Message); 
      continue; 
	  }
	  
	  ##Writing Package Header
	  $PackageID = $ThisPackage.PackageID
	  $PackageName = $ThisPackage.Name
	  $PkgSourcePath = $ThisPackage.PkgSourcePath
	  $lineToWrite = "File Name" + ',' + "File Date" + ',' + "File Size (bytes)" + ',' + "PackageID" + ',' + "Package Name" + ',' + "Package Source Path"
	  $fileName = $PackagePath + $PackageID + "_files.txt"
	  $logLine = "Getting File Info For Package " + $PackageID
	  write-log $logLine
	  
	  #Check if package is new
	  $changesMade = $false
	  if((Test-Path $filename) -eq $false) {
		$changesMade = $true
		$logLine = "Package: " + $PackageID + " is a new package."
		$ChangeMSG = "(NEW PACKAGE) " + $PackageID + " - " + $PackageName + ", "
		write-log $logLine
	}
		
	  $oldFile = Get-Content $fileName
	  $lineToWrite | Out-File $fileName -Confirm:$false -encoding "UTF8"
	  
	  if(Test-Path $PkgSourcePath) {
		##Writing File Info For Package
		  $files = ls -recurse $PkgSourcePath
		  foreach($file in $files) {
			if(!($file.PSIsContainer)) {
				$lineToWrite = $file.fullName + ',' + $file.LastWriteTime + ',' + $file.length + ',' + $PackageID + ',' + $PackageName + ',' + $PkgSourcePath
				$lineToWrite | Out-File $fileName -append -Confirm:$false -encoding "UTF8"
			}
		}
	  } else {
		$logLine = "Location: " + $PkgSourcePath + " is unavailable."
		write-log $logLine
	  }

		if(!$changesMade) {
		  #CompareFiles
		  $newFile = Get-Content $fileName
		  $diff = diff $oldFile $newFile
		  if($diff.count -gt 0) {
			$changesMade = $true
			$logLine = "Changes have been made to " + $PackageID + ".txt"
			$ChangeMSG = "(changed) " + $PackageID + " - " + $PackageName + ", "
			write-log $logLine
		}
	}
  $retval = @()
  $retval += $changesMade
  $retval += $ChangeMSG
  Return $retval
}

Function WritePackageProgramsToFile($ThisPackage)
{
trap [Exception] { 
      write-log
      write-log $("TRAPPED: " + $_.Exception.GetType().FullName); 
      write-log $("TRAPPED: " + $_.Exception.Message); 
      continue; 
	  }
	  
	  ##Writing Package Header
	  $PackageID = $ThisPackage.PackageID
	  $PackageName = $ThisPackage.Name
	  $PkgSourcePath = $ThisPackage.PkgSourcePath
	  $lineToWrite = "Program Name" + ',' + "Program Command" + ',' + "Run" + ',' + "Max Run Time" + ','  + "Program Can Run" + ',' + "Program Flag String" + ',' + "PackageID" + ',' + "Package Name" + ',' + "Package Source Path"
	  $fileName = $PackagePath + $PackageID + "_programs.txt"
	  $logLine = "Getting Program Info For Package " + $PackageID
	  write-log $logLine
	  
	  #Check if package is new
	  $changesMade = $false
	  if((Test-Path $filename) -eq $false) {
		$changesMade = $true
		$logLine = "Package: " + $PackageID + " is a new package."
		$ChangeMSG = "(NEW PACKAGE) " + $PackageID + " - " + $PackageName + ", "
		write-log $logLine
	}
		
	  $oldFile = Get-Content $fileName
	  $lineToWrite | Out-File $fileName -Confirm:$false -encoding "UTF8"
	  
		##Writing Program Info For Package
		  foreach($program in $programs) {
			if($program.PackageID -eq $PackageID) {
				$programFlagString = $program.programFlags
				$programFlagStringBin = [Convert]::ToString($programFlagString,2)
				#Calculate Run Mode
				$run = "Normal"
				if($programFlagStringBin[($programFlagStringBin.length - 22)] -eq 1) {
					$run = "Minimized"
				} elseif ($programFlagStringBin[($programFlagStringBin.length -23)] -eq 1) {
					$run = "Maximized"
				} elseif ($programFlagStringBin[($programFlagStringBin.length -24)] -eq 1) {
					$run - "Hidden"
				}
				#Calculate Program Can Run
				$PCR = "Whether or Not a User is Logged On"
				if($programFlagStringBin[($programFlagStringBin.length -14)] -eq 1) {
					$PCR = "Only When a User is Logged On"
				} elseif ($programFlagStringBin[($programFlagStringBin.length -17)] -eq 1) {
					$PCR = "Only When no User is Logged On"
				}
				$CommandLine = $program.CommandLine
				if($CommandLine.indexOf(',') -gt -1) {
					if($CommandLine.indexOf('"') -gt -1) {
						$i = 0
						while($i -lt $CommandLine.length) {
							if($CommandLine[$i] -eq '"') {
								$CommandLine = $CommandLine.SubString(0,$i) + '"' + $CommandLine.SubString($i)
								$i++
							}
							$i++
						}
					}
					$CommandLine = '"' + $CommandLine + '"'
				}
				
				#Write Output
				$lineToWrite = $program.ProgramName + ',' + $CommandLine + ',' + $run + ',' + $program.Duration + ',' + $PCR + ',"' + $programFlagStringBin + '",' + $PackageID + ',' + $PackageName + ',' + $PkgSourcePath
				$lineToWrite | Out-File $fileName -append -Confirm:$false -encoding "UTF8"
			}
		}

		if(!$changesMade) {
		  #CompareFiles
		  $newFile = Get-Content $fileName
		  $diff = diff $oldFile $newFile
		  if($diff.count -gt 0) {
			$changesMade = $true
			$logLine = "Changes have been made to " + $PackageID + ".txt"
			$ChangeMSG = "(changed) " + $PackageID + " - " + $PackageName + ", "
			write-log $logLine
		}
	}
  $retval = @()
  $retval += $changesMade
  $retval += $ChangeMSG
  Return $retval
}

##########################################################################################
<#---------Logfile Info----------#>            #Code REF - http://powershellcommunity.org/Forums/tabid/54/aft/4700/Default.aspx
$logfileFullName = $logFileRoot.TrimEnd("\\") + "\Get-PackageInfo-" + $(get-date -format MMddyyHHmmss) + ".log"
$script:logfile = $logfileFullName
$script:Seperator = @"

$("-" * 25)

"@            
$script:loginitialized = $false            
$script:FileHeader = @"
$seperator
***Application Information***
Filename:  Get-PackageInfo.ps1
Created by:  Holbert.26
"@       

# Aliases for Get-LogicalDisk
	set-alias -name Get-Storage -value Get-LogicalDisk -Scope Global -Option AllScope -Description "Alias for get-logicaldisk."
	set-alias -name st -value Get-LogicalDisk -Scope Global -Option AllScope -Description "Alias for get-logicaldisk."

############################################################################################
	
##Main	
trap [Exception] { 
		write-host -f magenta $("TRAPPED: " + $_.Exception.GetType().FullName); 
    write-host -f magenta $("TRAPPED: " + $_.Exception.Message); 
    
      write-log
      write-log $("TRAPPED: " + $_.Exception.GetType().FullName); 
      write-log $("TRAPPED: " + $_.Exception.Message); 
      continue; 
}

##Get SCCM Driver Packages, Drivers, And Linking Files
write-log "Getting SCCM Packages"
$packages = Get-WmiObject SMS_Package -namespace root\sms\site_chm
write-log "Getting SCCM Programs"
$programs = Get-WmiObject SMS_Program -namespace root\sms\site_chm

$changesMade = $false #Variable to track if changes were made and if so a commit is needed

#Create Change Message
$ChangeMSG = "The Following Changes Have Been Made: "

$PackageIDs = @()

##Output Data For Each Driver Package
foreach ($i in $packages) 
    {
		$results = WritePackageFilesToFile($i)
		if($results[0] -eq $true) {
			$changesMade = $true
			$changeMSG = $changeMSG + $results[1]
		}
		$results = WritePackageProgramsToFile($i)
		if($results[0] -eq $true) {
			$changesMade = $true
			$changeMSG = $changeMSG + $results[1]
		}
		$PackageIDs += $i.PackageID
	}	

#Check For Deleted Packages as Files
##$PackagePath - Set Only At the Top
$PackageFiles = ls $PackagePath
$filesToRMFromGit = @()
foreach ($file in $PackageFiles) {
	if(!($PackageIDs -contains $file.BaseName)) {
		$PkgCont = Import-Csv $file.FullName
		$PackageName = ($PkgCont[0]."Package Name")
		$ChangeMSG += "(REMOVED PACKAGE) " + $file.BaseName + " - " + $PackageName + ','
		$logLine = "Package: " + $file.BaseName + " no longer exists, deleting file."
		write-log $logLine
		$filesToRMFromGit += $file.FullName
		$changesMade = $true
	}
}

#convert all .txt files in repo files to UTF-8
$txtFiles = ls $gitPath | where {$_.Name -like "*.txt"} | % {
	#$newname = $_.FullName + ".utf8"
	(Get-Content -Path $_.FullName) | Set-Content -Encoding "UTF8" $_.FullName
}

#Commit to Git
if($changesMade) {
	write-log $ChangeMSG
	$logLine = "Committing Changes to Git"
	write-log $logLine
	
	#username and email set at top
	git config --global user.name $gitUsername
	git config --global user.email $gitEmail

	##$GitPath - Set Only At The Top
	cd $GitPath
	git init
	##$PackagePath - Set only at the top
	git add $PackagePath
	foreach ($fileName in $filesToRMFromGit) {
		git rm $fileName
	}
	git commit -m $ChangeMSG
	#git remote add origin https://github.com/ASCTech/ASC-SCCM-Private.git
	git push -u $AuthWebRepositoryPath master
	} else {
		write-log "No Changes Have Been Made"
	}

write-log "Complete"
	
