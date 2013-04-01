Param([string]$password,[switch]$confirm)


$gMessages = @{}
$gMessages.Add(0,"SUCCESSFUL")
$gMessages.Add(1,"UNSUCCESSFUL")
$gMessages.Add(2,"REBOOT_REQUIRED")
$gMessages.Add(3,"DEP_SOFT_ERROR")
$gMessages.Add(4,"DEP_HARD_ERROR")
$gMessages.Add(5,"QUAL_HARD_ERROR")
$gMessages.Add(6,"REBOOTING_SYSTEM")
$gMessages.Add(7,"Invalid BIOS Password")

$gLogFile = $null
$gLogFile = "C:\Windows\ccm\logs\BiosUpdates.log"

Function write-openingBlock
	{
		$CS = Gwmi Win32_ComputerSystem -Comp "."
		$computer = $CS.Name
		$loggedInUser = $Env:username
		$dateTime = Get-Date
		
		$msgs = $null
		$msgs = @()
		$msgs += "Running on " + $dateTime + " by " + $loggedInUser + " from " + $computer
		$msgs += ""
		$msgs += "___ STARTING WORK ___"
		$msgs += ""
		
		Foreach($msg in $msgs)
			{Write-Log $msg "white" 1}
	}

Function Write-Log($msg,$switches)
	{
		If($gLogFile -eq $null)
			{}
		Else
			{Add-Content $gLogFile $msg}
			
		write-host $msg
	}

Function Get-BiosVersionsInRepo($hshRepo,$systemModel)
	{
		#parse the repo for files pertaining to the systemModel
		$arrBiosFiles = @()
		$hshRepo.Keys | ? {$hshRepo.Get_Item($_) -eq $false -and ($_.Split("\")[($_.Split("\").Count - 2)]) -eq $systemModel} | % {$arrBiosFiles += ($_.Split("\")[($_.Split("\").Count - 1)])}
		
		#Parse the files for version numbers
		$arrVersions = @()
		$maxVer = 0
		$arrBiosFiles | % {
			$curFileVer = $_.Substring(($_.Length - 6),2)
			If($curFileVer -match "[0-9][0-9]")
				{
					[int32]$iCurVer = $curFileVer
					$arrVersions += $iCurVer
				}
		}
		
		Return $arrVersions
	}

Function Check-BIOSUpgradeNeeded($hshRepo,$systemModel,$curBiosVer)
	{
		$bUpgradeNeeded = $false
		
		#check if upgrade needed
		$curBiosVer = $curBiosVer.Substring(1,($curBiosVer.Length - 1))
		$biosVersionsAvail = Get-BiosVersionsInRepo $hshRepo $systemModel
		$maxVer = ($biosVersionsAvail | Measure-Object -max).Maximum
		If($curBiosVer -lt $maxVer)
			{
				$msg = "This system needs upgraded to bios version ""A" + $maxVer + """."
				Write-Log $msg
				$bUpgradeNeeded = $True
			}
		Else
			{
				$msg = "This system is already at the latest bios version."
				Write-Log $msg
			}
		Return $bUpgradeNeeded
	}

Function Upgrade-Bios($hshRepo,$systemModel,$curBiosVer,$password)
	{
		#Pick the next highest update after the current version number
		$curBiosVer = $curBiosVer.Substring(1,($curBiosVer.Length - 1))
		$repoVersions = Get-BiosVersionsInRepo $hshRepo $systemModel
		$nextVersion = $repoVersions | ? {$_ -gt $curBiosVer} | Sort -descending | Select -last 1
		
		$msg = "Upgrading the system to bios version ""A" + $nextVersion + """."
		Write-Log $msg
		
		$filePath = $hshRepo.Keys | ? {$_ -like ("*" + $systemModel + "*")} | ? {$_ -like ("*A" + $nextVersion  + ".exe")} | select -first 1
		
		#unblock file so we don't get a security warning
		#ref: http://www.undermyhat.org/blog/2012/05/copy-delete-or-rename-alternate-data-streams-using-only-standard-windows-command-prompt-tools/
		$streamCmd = "cmd.exe"
		$streamArgs = "/c type NUL > """ + $filePath + ":Zone.Identifier"
		Start-Process $streamCmd $streamArgs
		Sleep 3
		
		#change for certain machines
		Switch($systemModel)
			{
				"Latitude e4300" {$cmdArgs = "-noreboot -nopause -forceit"}
				default {$cmdArgs = "/s /p=" + $password}
			}
		
		$cmd = $filePath
		$msg = "Running command: '" + $cmd + " " + $cmdArgs + "'."
		Write-Log $msg
		
		$process = (Start-Process -PassThru -Wait -filepath $cmd -argumentlist $cmdArgs)
		#$process = (Start-Process -PassThru -Wait -filepath $cmd) # -argumentlist $cmdArgs)
		$returnCode = $process.ExitCode
		
		Return $returnCode
	}

write-openingBlock

#==log about password supplied status
$passOK = $false
If($password -ne $null -and $password -ne "")
	{
		If($password.length -ge 4)
			{$passOK = $true}
		Else
			{}
	}
If($passOK -eq $true)
	{$msg = "Bios password has been specified and is at least 4 characters long."}
Else
	{$msg = "Bios password has -not- been specified or is at less than 4 characters long."}
Write-Log $msg


#==main

$systemModel = $false
$retCode = 0

#is it a dell we can upgrade?
$systemModel = ((gwmi Win32_ComputerSystem).Model).Trim(" ")
$bUpgradeSupported = $False
If($systemModel -like "Optiplex*" -or $systemModel -like "Latitude*" -or $systemModel -like "Precision*")
	{
		$msg = "This system is an upgradable Dell of model """ + $systemModel + """."
		Write-Log $msg
		#look through subfolders for model
		$repoPath = (Split-Path $MyInvocation.MyCommand.Path).Trim("\")
		$msg = "Loading the repo at """ + $repoPath + """."
		Write-Log $msg
		
		#populate hash table of repo
		$hshRepo = @{}
		Dir $repoPath -recurse | ? {$_.PSIsContainer -or $_.Name -like "*.exe"} | % {$hshRepo.Add($_.FullName,$_.PSIsContainer)}
		#$hshRepo | Out-Host
		
		#populate array of models
		$arrModels = @()
		$hshRepo.Keys | % {
			If($hshRepo.Get_Item($_) -eq $True)
				{$arrModels += ($_.Split("\")[($_.Split("\").Count - 1)])}
			}
		
		#check if current model is available in repo
		If($arrModels -contains $systemModel)
			{
				$msg = "This model has bios updates available in the repo."
				Write-Log $msg
				$bUpgradeSupported = $True
			}
		Else
			{
				$msg = "This model does not have any bios updates available in the repo."
				Write-Log $msg
			}
	}

#Does it need upgraded?
$bUpgradeNeeded = $false
If($bUpgradeSupported -eq $True)
	{
		$curBiosVer = (gwmi win32_bios).SMBiosBiosVersion
		$msg = "The current system bios version is """ + $curBiosVer + """."
		Write-Log $msg
		$bUpgradeNeeded = Check-BIOSUpgradeNeeded $hshRepo $systemModel $curBiosVer
	}

#do the upgrade!
If($bUpgradeNeeded -eq $true -and $bUpgradeSupported -eq $true)
	{
		$result = $null
		$result = Upgrade-Bios $hshRepo $systemModel $curBiosVer $password
		
		$msg = "Command returned code: " + $result
		Write-Log $msg
		
		If($gMessages.Keys -contains $result)
			{
				$returnCodeMsg = $gMessages.$result
                
                If($result -eq 0 -or $result -eq 2)
                {
				    $msg = "Dell's return code message is: """ + $returnCodeMsg + """."
				    Write-Log $msg
                }
                Else
                {
                    If($confirm)
                    {
                    $msg = "Dell's return code message is: """ + $returnCodeMsg + """."
				    Write-Log $msg
                    $null = [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
                    $null = [System.Windows.Forms.MessageBox]::Show("Bios Update Failed, Failure Name: """ + $returnCodeMsg + """." , "Bios Update Failed")
                    }
                    Else
                    {
                    $msg = "Dell's return code message is: """ + $returnCodeMsg + """."
				    Write-Log $msg
                    }
                }
			}
		
	}
Else
	{$result = 0}

Return $result