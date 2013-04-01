#Group-Utils-Dangerous-b5.ps1

#Source any libraries needed
#WARNING--I can do better than this! (check if it exists, look for it, ask for it, fail if not found, etc.)
. .\Common-Functions-v2.ps1
. .\PSMod-FSFunctions-v1.ps1
. .\create-accounts-settings.ps1

#Set global variables
Write-Host ""
Write-Host ""
Write-Host ""

$gScriptName = "Group-Utils-Dangerous-b5.ps1"
$gScriptVersion = "005"
$global:gVerbosityLevel = 4				#Default verbosity level (regular)
$script:gOverrideVals = @{}
$script:arrTestsToSkip = @()

#----Unique Functions----

Function Write-UsageInfo
	{
		$msgs = @()
		$msgs += ""
		$msgs += "Usage:"
		$msgs += $gScriptName + " (/FIX|/PRECOPY) /GROUP ""group name"")"
		$msgs += "`t[/VERBOSE|/EVAL]"
		$msgs += ""
		$msgs += "`t/FIX"
		$msgs += "`t*Scans a given group for problems, then attempts to fix the problems."
		$msgs += ""
		$msgs += "`t/PRECOPY"
		$msgs += "`t*Copies a group's data to the destination volume without making any changes."
		$msgs += ""
		$msgs += "`t/VERBOSE"
		$msgs += "`t*Writes all logging information to the screen."
		$msgs += ""
		$msgs += "`t/EVAL"
		$msgs += "`t*Scans for problems but writes no changes."
		$msgs += ""
		$msgs += "`t/REBUILD"
		$msgs += "`t*Moves the groups' data to the LUN with the most free space."
		$msgs += ""
		$msgs += "`t/NEWHOME"
		$msgs += "`t*Used with /rebuild to specify the new lun mount directory. Ex: ""groups3"""
		$msgs += ""
		
		Foreach($msg in $msgs)
			{write-out $msg "white" 1}
	}

Function Director($hshArguments)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		$intStartNumber = 0
		$intLimit = $null
		
		##Parse the following items: $strRunMode,$strInputMode,$inputArgDep,$intStartNumber,$intLimit
		##intStartNumber and intLimit
		If($hshArguments.Keys -contains "/startnumber")
			{
				$bValid = $null
				$bValid = $false
				$bValid = Validate-StartNumber $hshArguments.Get_Item("/startnumber")
				If($bValid -eq $true)
					{$intStartNumber = $hshArguments.Get_Item("/startnumber")}
				Else
					{$intStartNumber = 0}
			}
		If($hshArguments.Keys -contains "/limit")
			{
				$bValid = $null
				$bValid = $false
				$bValid = Validate-LimitNumber $hshArguments.Get_Item("/limit")
				If($bValid -eq $true)
					{$intLimit = $hshArguments.Get_Item("/limit")}
				Else
					{$intLimit = 0}
			}
		
		#inputMode
		If($hshArguments.Keys -contains "/group")
			{
				$bValid = $null
				$bValid = $false
				$bValid = Validate-InputArg "group" $hshArguments.Get_Item("/group")
				If($bValid -eq $true)
					{$inputArgDep = $hshArguments.Get_Item("/group")}
				Else
					{$inputArgDep = $null}
			}
		ElseIf($hshArguments.Keys -contains "/folder")
			{
				$bValid = $null
				$bValid = $false
				$bValid = Validate-InputArg "folder" $hshArguments.Get_Item("/folder")
				If($bValid -eq $true)
					{$inputArgDep = $hshArguments.Get_Item("/folder")}
				Else
					{$inputArgDep = $null}
			}
		Else
			{
				$msg = "Warning`t`tCould not validate input argument(s)."
				Throw-Warning $msg
				$fail = $true
			}
		
		#multi-run code
		#init vars
		If($intStartNumber -lt 1){$intStartNumber = 1}
		[int]$intRunNumber = $null
		$intRunNumber = 0
		$intRunNumber += $intStartNumber
		#quick hack -- Excel and CSV rows start at 1 not zero. We can never have a run number be 0
		If($intRunNumber -lt 1)
			{$intRunNumber = 1}
		Else{}
		$hshRunInfo = $null
		$arrFailedRuns = @()
		$intTotalRuns = 0
		$strFileType = $null
		
		#check input mode. Open and cache files \ folders \ groups if needed
		Switch($strInputMode)
			{
				"/group"
					{
						$formattedInputDep = $inputArgDep
					}
				"/folder"
					{
						$foldername = $null
						$foldername = $inputArgDep
						$msg = "Action`tReading folders from """ + $foldername + """. This may take a couple minutes."
						Write-Out $msg "white" 2
						[array]$arrGroupCNs = @()
						[array]$arrGroupCNs += "<placeholder>"
						[array]$arrSubfolderNames = gci $foldername | %{If($_.PSIsContainer -eq $true){$_.Name}}
						$arrSubfolderNames | %{
							$blnGroupExists = $null
							$blnGroupExists  = $false
							$blnGroupExists  = Check-DoesGroupExist $_
							If($blnGroupExists  -eq $true)
								{$arrGroupCNs +=  $_}
							Else
								{}
						}
						
						$formattedInputDep = $arrUsernames
						write-host -f yellow "DEBUG! $arrUsernames"
					}
				Default {$formattedInputDep = $inputArgDep}
			}
		
		#pick a mode (fix, precopy, create)
		$hshArgumentKeys = $null
		$hshArgumentKeys = $hshArguments.keys
		$strRunMode = $null
		If($hshArgumentKeys -contains "/eval")
			{$strRunMode = "eval"}
		ElseIf($hshArgumentKeys -contains "/precopy")
			{$strRunMode = "precopy"}
		ElseIf($hshArgumentKeys -contains "/fix")
			{$strRunMode = "fix"}
		ElseIf($hshArgumentKeys -contains "/create")
			{$strRunMode = "create"}
		
		$msg = "Info`tRunMode determined to be """ + $strRunMode + """."
		Write-Out $msg "white" 2
		
		$hshVariables = $null
		$hshVariables = Generate-InputVariables $strRunMode $hshArguments
		
		Write-Host -f yellow "`nhshVariables:"
		$hshVariables | out-host
		
		If($hshVariables -eq $false)
			{
				$msg = "Error`tFailed to generate usable variables from the arguments given."
				Throw-Warning $msg
				$fail = $true
			}
		
		#run checks
		If($fail -eq $false)
			{
				$msg = "Action`tBuilding the action set for this run mode."
				Write-Out $msg "white" 2
				
				$arrActionList = $null
				$arrActionList = Build-ActionSet $strRunMode $hshVariables
				Display-Array $arrActionList 2 2
				Foreach($strActionSet in $arrActionList)
					{
						If($fail -eq $false)
							{
								$blnActionSetCompletionStatus = $null
								$blnActionSetCompletionStatus = 0
								$msg = "INFO`tRunning action set: """ + $strActionSet + """."
								Write-Out $msg "white" 2
								$blnActionSetCompletionStatus = Run-ActionSet $strActionSet $hshVariables
								If($blnActionSetCompletionStatus -eq $true)
									{
										$msg = "Info`tAction set completed successfully."
										Write-Out $msg "white" 2
									}
								Else
									{
										$msg = "Error`tAction set failed; fatal error!"
										Throw-Warning $msg
										$fail = $true
									}
								
							}
					}
			}

		If($fail -eq $true)
			{$retval = $false}
		Return $retval
	}

Function Generate-InputVariables($strRunMode,$hshArguments)
	{
		$retval = $null
		$fail = $null
		$fail = $false
		
		$hshVariables = $null
		$hshVariables = @{}
		Switch($strRunMode)
			{
				"create" {$fail = $true}
				"file" {$fail = $true}
				"precopy"
					{
						$groupCN = $null
						$groupCN = $hshArguments.Get_Item("/group")
						If($groupCN -eq $null -or $groupCN -eq "")
							{
								$msg = "Error`tCould not generate the groupCN from the arguments given."
								Throw-Warning $msg
								$fail = $true
							}
						Else
							{$hshVariables.Add("groupCN",$groupCN)}
						}
				"fix"
					{
						$groupCN = $null
						$groupCN = $hshArguments.Get_Item("/group")
						If($groupCN -eq $null -or $groupCN -eq "")
							{
								$msg = "Error`tCould not generate the groupCN from the arguments given."
								Throw-Warning $msg
								$fail = $true
							}
						Else
							{
								$hshVariables.Add("groupCN",$groupCN)
							}
					}
				"eval"
					{
						$groupCN = $null
						$groupCN = $hshArguments.Get_Item("/group")
						If($groupCN -eq $null -or $groupCN -eq "")
							{
								$msg = "Error`tCould not generate the groupCN from the arguments given."
								Throw-Warning $msg
								$fail = $true
							}
						Else
							{
								$hshVariables.Add("groupCN",$groupCN)
							}
					}
				Default
					{
						$msg = "Error`tCould not generate usable variables for the run mode """ + $strRunMode + """."
						Throw-Warning $msg
						$fail = $true
					}
			}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $hshVariables}
		Return $retval
	}

Function Get-DependentArgs($rootArgument,$arrArguments) #done
	{
		$retval = $null
		$fail = $null
		$fail = $false
		
		
		$numberOfArgs = $null
		
		#determine how many arguments  the root argument needs
		Switch($rootArgument)
			{
				"/precopy"
					{$numberOfArgs = 0}
				"/fix"
					{$numberOfArgs = 0}
				"/verbose"
					{$numberOfArgs = 0}
				"/eval"
					{$numberOfArgs = 0}
				"/folder"
					{$numberOfArgs = 1}
				"/group"
					{$numberOfArgs = 1}
				"/rebuild"
					{$numberOfArgs = 0}
				"/newhome"
					{$numberOfArgs = 1}
				Default
					{
						$msg = "ERROR`tThe following argument is invalid: """ + $rootArgument + """."
						Throw-Warning $msg
						$fail = $true
					}
			}
		
		#get all the required arguments
		If($numberOfArgs -eq $null -or $numberOfArgs -eq "" -or $numberOfArgs -le 0)
			{$retval = $null}
		Else
			{
				$arrDependents = Get-NextNArguments $arrArguments $rootArgument $numberOfArgs
				If($arrDependents -eq $null -or $arrDependents -eq "")
					{
						$msg = "ERROR`tNo sub-arguments found for the argument: """ + $rootArgument + """."
						Throw-Warning $msg
						$fail = $true
					}
				ElseIf($numberOfArgs -gt 1 -and $arrDependents -isnot [array])
					{
						$msg = "ERROR`tNot enough dependent arguments given for root argument: """ + $rootArgument + """ (read dependents: """ + $arrDependents + """)."
						Throw-Warning $msg
						$fail = $true
					}
				Else
					{$retval = $arrDependents}
			}
		
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
								$nextArg = $arrArguments[$nextArgCounter]
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

Function Parse-ArrayToCSVString($arrArray) #done
	{
		$retval = $null
		$fail = $null
		$fail = $false
		
		[string]$strFinishedString = $null
		If($arrArray -isnot [array])
			{$strFinishedString = $arrArray}
		Else
			{
				[string]$strArray = $null
				$strMember = $null
				$intArrayCount = $arrArray.count
				$i = $null
				$i = 0
				Foreach($strMember in $arrArray)
					{$strArray += $strMember + ","}
				#trim trailing comma
				$strFinishedString = $strArray.TrimEnd(",")
			}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $strFinishedString}
		Return $retval
	}

Function Verify-DependentArgs($argument,$arrDependents) #done
	{
		$retval = $null
		$fail = $null
		
		$blnVerified = $null
		$blnVerified = $false
		
		Switch($argument)
			{
				"/precopy"
					{$blnVerified = $true}
				"/fix"
					{$blnVerified = $true}
				"/verbose"
					{$blnVerified = $true}
				"/eval"
					{$blnVerified = $true}
				"/folder"
					{
						$blnVerified = Test-FolderArgument $arrDependents
						If($blnVerified -eq $false)
							{
								$msg = "ERROR`tCould not verify the given folder """ + $arrDependents + """."
								Throw-Warning $msg
								$fail = $true
							}
					}
				"/group"
					{
						$blnVerified = Test-GroupArgument $arrDependents
						If($blnVerified -eq $false)
							{
								$msg = "ERROR`tCould not verify the given group """ + $arrDependents + """."
								Throw-Warning $msg
								$fail = $true
							}
					}
				"/newhome"
					{
						#tests whether newhome given exists
						$sNewHome = $arrDependents
						$fs = Read-Variable "fileserver"
						$mountRoot = Read-Variable "fileServer-LocalMountFolder"
						$sRootLetter = $mountRoot.Substring(0,1)
						$sRootPath = $mountRoot.Substring(3)
						$mountPath = "\\" + $fs + "\" + $sRootLetter + "$\" + $sRootPath + "\" + $sNewHome
						#write-host -f magenta "mountPath: """ $mountPath """."
						$pathTest = Test-Path $mountPath
						If($pathTest -eq $true)
							{$blnVerified = $true}
						Else
							{
								$msg = "ERROR`tThe mountPath given in /newhome doesn't exist. Tested path: """ + $mountPath + """."
								Throw-Warning $msg
								$blnVerified = $false
								$fail = $true
							}
					}
				Default
					{
						$msg = "ERROR`tVerify-DependentArgs was passed an argument it didn't recognize: """ + $argument + """."
						Throw-Warning $msg
						$fail = $true
					}
			}
		
		If($blnVerified -eq $null)
			{$blnVerified = $false}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $blnVerified}
		
		Return $retval
	}

Function Test-FolderArgument($arrDependents) #delayed
	{
		$results = $true
		$results = $null
		#make sure folder exists and is filled with group shares.
		$folder = $null
		$folder = $arrDependents
		
		$folderCheck = $null
		$folderCheck = Test-Path $folder
		If($folderCheck -eq $null -or $folderCheck -eq "")
			{
				$folderCheck = $false
				$results = $false
			}
		
		#is the path a folder?
		If($folderCheck -eq $true)
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

Function Test-GroupArgument($arrDependents) #done
	{
		#make sure group exists
		$group = $null
		$group = $arrDependents
		
		$groupCheck = $null
		$groupCheck = $False
		$groupCheck = Check-DoesGroupExist $group
		If($groupCheck -eq $null -or $groupCheck -eq "")
			{$groupCheck = $false}
		
		#$groupCheck = $true
		Return $groupCheck
	}

Function Verify-ArgumentExclusivity($arguments) #done
	{
		$retval = $null
		$fail = $null
		
		#disable /folder until it's ready
		If($arguments -contains "/folder")
			{
				$msg = "ERROR`t/folder isn't implemented yet."
				Throw-Warning $msg
				$fail = $true
			}
		
		#check for a core argument
		If($arguments -notcontains "/fix" -and $arguments -notcontains "/precopy")
			{
				$msg = "ERROR`tMissing a core argument (either /precopy or /fix)."
				Throw-Warning $msg
				$fail = $true
			}
		
		#make sure we don't have 2 core arguments
		If($arguments -contains "/precopy" -and $arguments -contains "/fix")
			{
				$msg = "ERROR`t/precopy and /fix are mutually exclusive arguments."
				Throw-Warning $msg
				$fail = $true
			}
		
		#make sure we have an input argument
		If($arguments -notcontains "/folder" -and $arguments -notcontains "/group")
			{
				$msg = "ERROR`tNo input arguments given. Must use /folder or /group."
				Throw-Warning $msg
				$fail = $true
			}
		
		#make sure we don't have 2 input arguments
		If($arguments -contains "/folder" -and $arguments -contains "/group")
			{
				$msg = "ERROR`t/folder and /group are mutually exclusive arguments."
				Throw-Warning $msg
				$fail = $true
			}
		
		#make sure /eval is only with /fix
		If($arguments -contains "/eval" -and $arguments -notcontains "/fix")
			{
				$msg = "ERROR`t/eval can only be used with /fix."
				Throw-Warning $msg
				$fail = $true
			}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $true}
		Return $retval
	}

#_____

Function Build-ActionSet($strRunMode,$hshArguments) #done
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		$arrTasks = $null
		$arrTasks = @()
		Switch($strRunMode)
			{
				"precopy"
					{$arrTasks += "precopyGroupShare"}
				"fix"
					{$arrTasks += "scanAndFix-AllErrors"}
				"eval"
					{$arrTasks += "scan-AllErrors"}
				"create"
					{
						$msg = "Error`tCreate is not yet implemented."
						Throw-Warning $msg
						$fail = $true
					}
				Default
					{
						$msg = "Error`tCould not create a action set for run mode """ + $strRunMode + """."
						Throw-Warning $msg
						$fail = $true
					}
			}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $arrTasks}
		
		Return $retval
	}

Function Run-ActionSet($strActionSet,$hshArguments)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		#create the action list
		$msg = "Action`tBuilding the action list for this action set."
		Write-Out $msg "white" 2
		$arrActionList = $null
		$arrActionList = Build-ActionList $strActionSet
		If($arrActionList -eq $false -or $arrActionList -eq $null)
			{
				$msg = "Error`tFailed to build the action list for this action set!."
				Throw-Warning $msg
				$fail = $true
			}
		Else
			{
				$msg = "Action list for this ation set:"
				Display-Array $arrActionList 2 2
			}
		
		#run the action list
		$blnKeepActing = $null
		$blnKeepActing = $true
		While($blnKeepActing -eq $true)
			{
				$strAction = $null
				$blnKeepActing = $false
				Foreach($strAction in $arrActionList)
					{
						$blnRemediate = $null
						$blnRemediate = $false
						If($fail -eq $false)
							{
								If($script:arrTestsToSkip -contains $strAction)
									{
										$msg = "Skipping test """ + $strAction + """."
										Write-Out $msg "cyan" 2
									}
								Else
									{
										$msg = "Action`tRunning action: """ + $strAction + """."
										Write-Out $msg "cyan" 2
										$blnActionCompletionStatus = $null
										$blnActionCompletionStatus = $false
										$blnActionCompletionStatus = Run-Action $strAction $hshArguments
										If($blnActionCompletionStatus -eq $true)
											{
												$msg = "Info`tAction completed successfully."
												Write-Out $msg "green" 2
											}
										Else
											{
												$msg = "Error`tAction failed."
												Throw-Warning $msg
												$fail = $true
											}
									}
							}
						Else
							{$blnKeepActing = $false}
					}
			}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $true}
		Return $retval
	}

Function Build-ActionList($strAction)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		$arrTestList = $null
		$arrTestList = @()
		Switch($strAction)
			{
				"precopyGroupShare"
					{
						$arrTestList += "conform-groupFolderExistence"
						$arrTestList += "precopy-groupShare"
						$arrTestList += "conform-securityGroupsExist"
						$arrTestList += "conform-securityGroupsSAMAccountName"
						$arrTestList += "conform-securityGroupsLocation"
						$arrTestList += "conform-securityGroupsNesting"
						$arrTestList += "conform-groupFolderPermissions"
					}
				"scan-AllErrors"
					{
						$arrTestList += "check-securityGroupsExist"
						$arrTestList += "check-securityGroupsSAMAccountName"
						$arrTestList += "check-securityGroupsLocation"
						$arrTestList += "check-securityGroupsNesting"
						$arrTestList += "check-groupFolderExistence"
						$arrTestList += "check-shareExists"
						$arrTestList += "check-sharePath"
						$arrTestList += "check-sharePermissions"
						$arrTestList += "check-GroupFolderLocation"
						$arrTestList += "check-groupFolderOrphans"
						$arrTestList += "check-groupFolderPermissions"
						$arrTestList += "check-shareMapping"
					}
				"scanAndFix-AllErrors"
					{
						$arrTestList += "conform-securityGroupsExist"
						$arrTestList += "conform-securityGroupsSAMAccountName"
						$arrTestList += "conform-securityGroupsLocation"
						$arrTestList += "conform-securityGroupsNesting"
						$arrTestList += "conform-groupFolderExistence"
						$arrTestList += "conform-shareExists"
						$arrTestList += "conform-sharePath"
						$arrTestList += "conform-groupFolderLocation"
						$arrTestList += "conform-sharePermissions"
						$arrTestList += "conform-groupFolderOrphans"
						$arrTestList += "conform-groupFolderPermissions"
						$arrTestList += "check-shareMapping"
					}
				Default
					{
						$msg = "Error`tCould not build test list for action """ + $strAction + """."
						Throw-Warning $msg
						$fail = $true
					}
			}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $arrTestList}
		Return $retval
	}

Function Run-Action($strAction,$hshVariables)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		$blnResults = $null
		$blnResults = $false
		Switch($strAction)
			{
				"Check-SecurityGroupsExist"
					{$blnResults = Check-SecurityGroupsExist $hshVariables}
				"Check-SecurityGroupsLocation"
					{$blnResults = Check-SecurityGroupsLocation $hshVariables}
				"Check-SecurityGroupsSAMAccountName"
					{$blnResults = Check-SecurityGroupsSAMAccountName $hshVariables}
				"Check-GroupFolderExistence"
					{$blnResults = Check-GroupFolderExistence $hshVariables}
				"Check-SecurityGroupsNesting"
					{$blnResults = Check-SecurityGroupsNesting $hshVariables}
				"Check-GroupFolderPermissions"
					{$blnResults = Check-GroupFolderPermissions $hshVariables}
				"Check-SharePath"
					{$blnResults = Check-SharePath $hshVariables}
				"check-groupFolderLocation"
					{$blnResults = Check-GroupFolderLocation $hshVariables}
				"Check-ShareExists"
					{$blnResults = Check-ShareExists $hshVariables}
				"Check-SharePermissions"
					{$blnResults = Check-SharePermissions $hshVariables}
				"Check-GroupFolderOrphans"
					{$blnResults = Check-GroupFolderOrphans $hshVariables}
				"Check-ShareMapping"
					{
						$blnResults = Check-ShareMapping $hshVariables
						$blnResults = $true
					}
				"Conform-PrecopyFolderLocation"
					{$blnResults = Conform-SharePath $hshVariables}
				"Conform-SecurityGroupsExist"
					{$blnResults = Conform-SecurityGroupsExist $hshVariables}
				"Conform-SecurityGroupsLocation"
					{$blnResults = Conform-SecurityGroupsLocation $hshVariables}
				"Conform-SecurityGroupsSAMAccountName"
					{$blnResults = Conform-SecurityGroupsSAMAccountName $hshVariables}
				"Conform-GroupFolderExistence"
					{$blnResults = Conform-GroupFolderExistence $hshVariables}
				"Conform-GroupFolderLocation"
					{$blnResults = Conform-GroupFolderLocation $hshVariables}
					
				"Conform-SecurityGroupsNesting"
					{$blnResults = Conform-SecurityGroupsNesting $hshVariables}
				"Conform-GroupFolderPermissions"
					{$blnResults = Conform-GroupFolderPermissions $hshVariables}
				"Conform-SharePath"
					{$blnResults = Conform-SharePath $hshVariables}
				"Conform-ShareExists"
					{$blnResults = Conform-ShareExists $hshVariables}
				"Conform-SharePermissions"
					{$blnResults = Conform-SharePermissions $hshVariables}
				"Conform-GroupFolderOrphans"
					{$blnResults = Conform-GroupFolderOrphans $hshVariables}
				"Conform-PrecopyFolderLocation"
					{$blnResults = Conform-SharePath $hshVariables}
				"precopy-groupShare"
					{$blnResults = Precopy-groupShare $hshVariables}
				Default
					{
						$msg = "Error`tThe following action was attempted but the definition doesn't exist: """ + $strAction + """."
						Throw-Warning $msg
						$fail = $true
					}
			}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $blnResults}
		Return $retval
	}

Function Check-SecurityGroupsExist($hshVariables)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		#look for groupCN
		$groupCN = $null
		$groupCN = $hshVariables.Get_Item("groupCN")
		$groupDN = Get-DNbyCN $groupCN "group"
		If($groupDN -eq $false)
			{
				$msg = "Error`t`tThe root security group """ + $groupCN + """ does not exist!"
				Throw-Warning $msg
				$fail = $true
			}
		Else
			{}
		
		#test for groups
		$blnAllGroupsExist = $null
		$blnAllGroupsExist = $false
		If($fail -eq $false)
			{
				#prepare variables
				$strReadGroup = $null
				$strReadGroup = Get-ACLReadGroupCN $groupCN
				$msg = "Action`t`tTesting for the the read-group """ + $strReadGroup + """."
				Write-Out $msg "darkcyan" 4
				$blnReadGroupExists = $null
				$blnReadGroupExists = Get-DNbyCN $strReadGroup "group"
				If($blnReadGroupExists -eq $false)
					{
						$msg = "Info`t`tThe read group does _not_ exist!"
						Write-Out $msg "magenta" 4
					}
				Else
					{
						$msg = "Info`t`tThe read group exists."
						Write-Out $msg "darkcyan" 4
					}
			}
		
		If($fail -eq $false)
			{
				#test write group
				$strWriteGroup = $null
				$strWriteGroup = Get-ACLWriteGroupCN $groupCN
				$msg = "Action`t`tTesting for the the read-group """ + $strWriteGroup + """."
				Write-Out $msg "darkcyan" 4
				$blnWriteGroupExists = $null
				$blnWriteGroupExists = Get-DNbyCN $strWriteGroup "group"
				If($blnWriteGroupExists -eq $false)
					{
						$msg = "Info`t`tThe write group does _not_ exist!"
						Write-Out $msg "magenta" 4
					}
				Else
					{
						$msg = "Info`t`tThe write group exists."
						Write-Out $msg "darkcyan" 4
					}
			}
		
		If($blnWriteGroupExists -eq $false -or $blnReadGroupExists -eq $false)
			{$blnAllGroupsExist = $false}
		Else
			{$blnAllGroupsExist = $true}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $blnAllGroupsExist}
		Return $retval
	}

Function Check-SecurityGroupsLocation($hshVariables)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		$blnAllGroupsOK = $null
		$blnAllGroupsOK = $true
		$groupCN = $null
		$groupCN = $hshVariables.Get_Item("groupCN")
				
		#build read and write groups
		$strReadGroup = $null
		$strReadGroup = Get-ACLReadGroupCN $groupCN
		$strWriteGroup = $null
		$strWriteGroup = Get-ACLWriteGroupCN $groupCN
		
		#create a list of groups to check
		$groupsToCheck = $null
		$groupsToCheck = @()
		$groupsToCheck += $groupCN
		$groupsToCheck += $strReadGroup
		$groupsToCheck += $strWriteGroup
		
		$blnAllGroupsOK = $null
		$blnAllGroupsOK = $true
		$group = $null
		Foreach($group in $groupsToCheck)
			{
				$msg = "Action`t`tChecking the location of the group """ + $group + """."
				Write-Out $msg "darkcyan" 4
				
				#build expected strings to match
				$arrExpectedOUStrings = $null
				$arrExpectedOUStrings = @()
				If($group -like "ACL_*")
					{$arrExpectedOUStrings += "Capability Resource Groups"}
				Else
					{
						$arrExpectedOUStrings += "Role Groups"
						$arrExpectedOUStrings += "Research Groups"
						$arrExpectedOUStrings += "Share Groups"
					}
				
				#grab the DN
				$strGroupDN = $null
				$strGroupDN = Get-DNbyCN $group "group"
				If($strGroupDN -eq $false)
					{
						$msg = "Error`t`tThe following group DNE: """ + $group + """."
						Throw-Warning $msg
						$fail = $true
					}
				Else
					{
						$expectedString = $null
						$blnDN_OK = $null
						$blnDN_OK = $false
						Foreach($expectedString in $arrExpectedOUStrings)
							{
								If($strGroupDN -like ("*" + $expectedString + "*"))
									{
										$blnDN_OK = $true
										Break
									}
							}
						If($blnDN_OK -eq $false)
							{
								$msg = "Error`t`tThe following group's DN is wrong: """ + $group + """."
								Write-Out $msg "darkcyan" 4
								$msg = "Error`t`tThe current DN is: """ + $strGroupDN + """."
								Write-Out $msg "darkcyan" 4
								$blnAllGroupsOK = $false
								Break
							}
					}
				
			}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $blnAllGroupsOK}
		Return $retval
	}

Function Check-SecurityGroupsSAMAccountName($hshVariable)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		#look for
		###"GroupCN"
		$groupCN = $null
		$groupCN = $hshVariables.Get_Item("groupCN")
		
		$readGroup = $null
		$readGroup = Get-ACLReadGroupCN $groupCN
		$writeGroup = $null
		$writeGroup = Get-ACLWriteGroupCN $groupCN
		
		$arrGroupsToCheck = $null
		$arrGroupsToCheck = @()
		$arrGroupsToCheck += $readGroup
		$arrGroupsToCheck += $writeGroup
		$blnAllOK = $null
		$blnAllOK = $true
		$group = $null
		Foreach($group in $arrGroupsToCheck)
			{
				#bind
				$msg = "Action`t`tTesting the """ + $group + """ group to see if the sAMAccountName matches the CN."
				Write-Out $msg "darkcyan" 4
				$objGroupDN = $null
				$objGroupDN = Get-DNbyCN $group "group"
				$objGroup = $null
				$objGroup = [adsi]("LDAP://" + $objGroupDN)
				#get sAMAccountName
				$objGroupSAN = $null
				$objGroupSAN = $objGroup.Get("sAMAccountName")
				$msg = "Info`t`t`tsAMAccountName: """ + $objGroupSAN + """."
				Write-Out $msg "darkcyan" 4
				If($objGroupSAN -eq $group)
					{
						$msg = "Info`t`tGroup sAMAccountName matches the CN."
						Write-Out $msg "darkcyan" 4
					}
				Else
					{
						$blnAllOK = $false
						$msg = "Error`t`tGroup sAMAccountName does _not_ match the CN."
						Throw-Warning $msg
					}
				#match against CN
			}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $blnAllOK}
		Return $retval
	}

Function Check-SecurityGroupsNesting($hshVariables)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		#Is $groupCN in $ACLReadGroup and in $ACLWriteGroup
		
		#find groupCN
		$groupCN = $null
		$groupCN = $hshArguments.get_item("groupCN")
		
		#build read group
		$strReadGroup = $null
		$strReadGroup = Get-ACLReadGroupCN $groupCN
		#get DN
		$readGroupDN = $null
		$readGroupDN = Get-DNbyCN $strReadGroup "group"
		
		#build write group
		$strWriteGroup = $null
		$strWriteGroup = Get-ACLWriteGroupCN $groupCN
		#get DN
		$writeGroupDN = $null
		$writeGroupDN = Get-DNbyCN $strWriteGroup "group"
		
		#array of groups to check
		$arrGroupsToCheck = $null
		$arrGroupsToCheck = @()
		$arrGroupsToCheck += $readGroupDN
		$arrGroupsToCheck += $writeGroupDN
		
		#check
		$blnAllOK = $null
		$blnAllOK = $true
		$groupDNToCheck = $null
		Foreach($groupDNToCheck in $arrGroupsToCheck)
			{
				$objGroup = $null
				$objGroup = [adsi]("LDAP://" + $groupDNToCheck)
				$objRoleGroupDN = $null
				$objRoleGroupDN = Get-DNbyCN $groupCN "group"
				$testedGroupCN = $null
				$testedGroupCN = Pull-LDAPAttribute $objGroup "cn"
				$msg = "Action`t`tTesting group """ + $testedGroupCN + """."
				Write-Out $msg "darkcyan" 4
				$blnCheck = $null
				$blnCheck = $false
				$blnCheck = Check-IsMemberOfGroup $objRoleGroupDN $groupDNToCheck
				If($blnCheck -eq $true)
					{
						$msg = "Info`t`tThe group """ + $testedGroupCN + """ contains the group """ + $groupCN + """."
						Write-Out $msg "darkcyan" 4
					}
				Else
					{
						$msg = "Error`t`tThe group """ + $testedGroupCN + """ does not contain the group """ + $groupCN + """."
						Throw-Warning $msg
						$blnAllOK = $false
					}				
			}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $blnAllOK}
		Return $retval
	}

Function Format-GroupName-ReplaceSpaces($groupCN)
	{
		$formattedGroupCN = $null
		$formattedGroupCN = $groupCN -replace("\s","_")
		Return $formattedGroupCN
	}

Function Check-GroupFolderExistence($hshArguments)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		#get valid sharepath UNCs for this group
		$groupCN = $null
		$groupCN = $hshArguments.get_item("groupCN")
		$possibleUNCs = $null
		$possibleUNCs = Generate-PossibleValidGroupUNCs $groupCN
		
		$msg = "Info`t`tFound the following possible UNCs."
		Write-Out $msg "darkcyan" 4
		Display-Array $possibleUNCs 3 4
		
		
		#test each until found
		$blnPathFound = $null
		$blnPathFound = $false
		Foreach($possibleUNC in $possibleUNCs)
			{
				If($blnPathFound -eq $false)
					{
						$msg = "Action`t`tTesting UNC: """ + $possibleUNC + """."
						Write-Out $msg "darkcyan" 4
						$pathTest = $null
						$pathTest = Test-Path $possibleUNC
						If($pathTest -eq $true)
							{
								$msg = "Info`t`tPath """ + $possibleUNC + """ exists!"
								Write-Out $msg "darkcyan" 4
								$blnPathFound = $true
							}
					}
			}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $blnPathFound}
		Return $retval
	}

Function Generate-PossibleValidGroupUNCs($groupCN)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		#grab file server
		$fileServer = $null
		$fileServer = Read-Variable "fileserver"
		
		#change rootpath from local to unc (C:\mount to c$\mount)
		$rootPath = $null
		$rootPath = Read-Variable "fileServer-LocalMountFolder"
		$formattedRootPath = $null
		$formattedRootPath = $rootPath -replace(":","$")
		
		#format group name
		$formattedGroupCN = $null
		$formattedGroupCN = Format-GroupName-ReplaceSpaces $groupCN
		
		#grow the root a little
		$searchRoot = $null
		$searchRoot = "\\" + $fileServer + "\" + $formattedRootPath + "\groups"
		
		#find group* from searchRoot
		$groupPaths = $null
		$groupPaths  = @()
		$i = $null
		$i = 0
		While($i -lt 10)
			{
				$pathToTest = $null
				$pathToTest = $searchRoot + $i
				
				#Write-Host -f yellow "(F)Generate-PossibleValidGroupUNCs`npathToTest: $pathToTest"
				
				$pathTest = $null
				$pathTest = Test-Path $pathToTest
				
				If($pathTest -eq $true)
					{$groupPaths += $pathToTest}
				Else
					{Break}
				$i++
			}
		
		#grow the root a little
		$searchRoot = $null
		$searchRoot = "\\" + $fileServer + "\" + $formattedRootPath + "\groupbackups"
		
		#find groupbackups from searchRoot
#		$groupPaths = $null
#		$groupPaths  = @()
		$i = $null
		$i = 0
		While($i -lt 10)
			{
				$pathToTest = $null
				$pathToTest = $searchRoot + $i
				
				#Write-Host -f yellow "(F)Generate-PossibleValidGroupUNCs`npathToTest: $pathToTest"
				
				$pathTest = $null
				$pathTest = Test-Path $pathToTest
				
				If($pathTest -eq $true)
					{$groupPaths += $pathToTest}
				Else
					{Break}
				$i++
			}
		
		#add data folder and groupCN
		$strBufferFolder = $nulll
		$strBufferFolder = Read-Variable "fileServer-BufferFolderName"
		$finishedGroupPaths = $null
		$finishedGroupPaths = @()
		Foreach($groupPath in $groupPaths)
			{
				$newGroupPath = $null
				$newGroupPath = $groupPath + "\" + $strBufferFolder + "\" + $formattedGroupCN
				$finishedGroupPaths += $newGroupPath
			}
		
		###HARD CODED VARIABLE
		###MAGIC VARIABLE
		$finishedGroupPaths += "\\winfs\c$\mount\groupbackups0\shares\" + $formattedGroupCN
		$finishedGroupPaths += "\\winfs\c$\mount\desktopimages\shares\" + $formattedGroupCN
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $finishedGroupPaths}
		Return $retval
	}

Function Check-GroupFolderPermissions($hshVariables)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		$groupCN = $null
		$groupCN = $hshVariables.Get_Item("groupCN")
		
		$msg = "Action`t`tFinding group share UNC."
		Write-Out $msg "darkcyan" 4
		$shareName = $null
		$shareName = Build-GroupShareName $groupCN
		$sharePath = $null
		$sharePath = Build-GroupSharePath $hshVariables
		$shareUNC = $null
		$shareUNC = Convert-SharePathToUNCPath $sharePath
		$folderPath = $null
		$folderPath = $shareUNC
		$msg = "Info`t`tGroup share UNC read as """ + $folderPath + """."
		Write-Out $msg "darkcyan" 4
		
		$results = $true
		
		#Check root permissions
		$msg = "Action`t`tTesting root ACL."
		Write-Out $msg "darkcyan" 4
		$root = Get-Item $folderPath -force
		$rootCheck = Check-RootGroupACLPermissions $groupCN $folderPath
		
		#check children permissions
		If($rootCheck -eq $false)
			{
				$msg = "Info`t`tRoot ACL test failed."
				Write-Out $msg "darkcyan" 4
				$results = $false
			}
		Else
			{
				$msg = "Info`t`tRoot ACL test passed."
				Write-Out $msg "darkcyan" 4
				$msg = "Action`t`tRetreiving child objects."
				Write-Out $msg "darkcyan" 4
				
				$childFileRegex = $null
				$childFileRegex = Read-Variable "ACLRegex"
				
				$children = get-childitem -force -recurse $folderPath -errorAction SilentlyContinue
				If($children -ne $null)
					{
						$msg = "Info`t`tTesting the children ACL's."
						Write-Out $msg "darkcyan" 4
						Foreach($child in $children)
							{
								$targetPath = $child.fullname
								#Write-Host -f yellow "targetPath: $targetPath"
								If($targetPath -notmatch $childFileRegex)
										{
											$msg = "Info`t`tSkipped file """ + $targetPath + """ because it contains nonstandard characters."
											Write-Out $msg "magenta" 4
										}
								ElseIf($targetPath.length -gt 240)
									{
										$msg = "Info`t`tSkipped file """ + $targetPath + """ because the path is longer than 240 characters."
										Write-Out $msg "magenta" 4
									}
								Else
									{
										$childCheck = Check-ChildGroupACLPermissions $groupCN $targetPath
										If($childCheck -eq $false)
											{
												$results = $false
												break
											}
										Else
											{}
									}
							}
					}
			}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $results}
		Return $retval
	}

Function Find-GroupFolderLocation($hshVariables)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		$groupCN = $null
		$groupCN = $hshVariables.Get_Item("groupCN")
		
		#Build potential paths
		$potentialPaths = $null
		$potentialPaths = Generate-PossibleValidGroupUNCs $groupCN
		If($potentialPaths -eq $false)
			{
				$msg = "Error`t`tCould not generate valid UNC's for this group."
				Throw-Warning $msg
				$fail = $true
			}
		
		#Test them
		If($fail -eq $false)
			{
				$groupFolderPath = $null
				$groupFolderPath = $false
				$potentialPath = $null
				Foreach($potentialPath in $potentialPaths)
					{
						$pathTest = $null
						$pathTest = Test-Path $potentialPath
						If($pathTest -eq $true)
							{
								$groupFolderPath = $potentialPath
								Break
							}
						Else
							{}						
					}
			}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $groupFolderPath}
		Return $retval
	}

Function Check-ShareExists($hshVariables)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		$groupCN = $null
		$groupCN = $hshVariables.Get_Item("groupCN")
		$shareName = $null
		$shareName = Build-GroupShareName $groupCN
		
		#Test to see if the share exists
		$blnShareTest = $null
		$blnShareTest = $false
		$msg = "Action`t`tTesting if the following share exists """ + $shareName + """."
		Write-Out $msg "darkcyan" 4
		$blnShareTest = Check-DoesShareExist $shareName
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $blnShareTest}
		Return $retval
	}

Function Build-GroupShareName($groupCN)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		#Build the share name from the GroupCN
		$formattedGroupCN = $null
		$formattedGroupCN = Format-GroupName-ReplaceSpaces $groupCN
		$shareName = $null
		$shareName = $formattedGroupCN
		
		If($shareName -eq $null -or $shareName -eq "")
			{$fail = $true}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $shareName}
		Return $shareName
	}

Function Build-GroupSharePath($hshVariables)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		$groupUNCPath = $null
		$groupUNCPath = Find-GroupFolderLocation $hshVariables
		If($groupUNCPath -eq $false)
			{$fail = $true}
		Else
			{
				$sharePath = $null
				$sharePath = Convert-UNCPathToSharePath $groupUNCPath
			}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $sharePath}
		Return $retval
	}

Function Check-SharePath($hshVariables)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		#Read the sharepath
		$groupCN = $null
		$groupCN = $hshVariables.Get_Item("groupCN")
		$shareName = $null
		$shareName = Build-GroupShareName $groupCN
		If($fail -eq $false)
			{
				$readSharePath = $null
				$readSharePath = Get-SharePath $shareName
				If($readSharePath -eq $false -or $readSharePath -eq $null)
					{
						$msg = "Error`t`tCould not read sharepath for share """ + $shareName + """."
						Throw-Warning $msg
						$fail = $true
					}
				Else
					{
						$UNCpath = $null
						$UNCpath = Convert-SharePathToUNCPath $readSharePath
						
						$msg = "Info`t`tThe current share path was read as """ + $UNCpath+ """."
						Write-Out $msg "darkcyan" 4
					}
			}
		
		#generate valid share paths
		If($fail -eq $false)
			{
				$arrValidSharePaths = $null
				$msg = "Action`t`tGenerating possible valid group UNCs."
				Write-Out $msg "darkcyan" 4
				$arrValidSharePaths = Generate-PossibleValidGroupUNCs $groupCN
				If($arrValidSharePaths -eq $false -or $arrValidSharePaths -eq $null)
					{
						$msg = "Error`t`tCould not generate valid share paths for this group."
						Throw-Warning $msg
						$fail = $true
					}
				Else
					{
						$msg = "Info`t`t`tValid UNCs generated:"
						Write-Out $msg "darkcyan" 4
						Display-Array $arrValidSharePaths 4 4
					}
			}
		
		#match read-sharepath to generate-possibleValidGroupUNCs
		If($fail -eq $false)
			{
				$blnPathFound = $null
				$blnPathFound = $false
				$validSharePath = $null
				$msg = "Action`t`tChecking to see if the read share path matches a valid share path."
				Write-Out $msg "darkcyan" 4
				Foreach($validSharePath in $arrValidSharePaths)
					{
						If($blnPathFound -eq $false)
							{
								#write-host -f yellow "uncpath: $uncpath`nvalidsharepath $validSharePath"
								If($UNCpath -eq $validSharePath)
									{
										$msg = "Info`t`tThe share path is valid."
										Write-Out $msg "darkcyan" 4
										$blnPathFound = $true
									}
								Else
									{}
							}
						Else
							{Break}
					}
				If($blnPathFound -eq $false)
					{
						$msg = "Error`t`tThe share path did _not_ match a valid UNC."
						Throw-Warning $msg
					}
			}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $blnPathFound}
		Return $retval
	}

Function Check-SharePermissions($hshVariables)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		#Get groupCN's
		$groupCN = $null
		$groupCN = $hshVariables.Get_Item("groupCN")
		
		$strReadGroup = $null
		$strReadGroup = Get-ACLReadGroupCN $groupCN
		$strWriteGroup = $null
		$strWriteGroup = Get-ACLWriteGroupCN $groupCN
		
		#build 'good users' array
		$groupDriveAdmins = $null
		$groupDriveAdmins = Read-Variable "groupDriveAdminsGroup"
		$goodUsers = $null
		$goodUsers = @($groupDriveAdmins,$strReadGroup,$strWriteGroup)
		
		#build sharename
		$shareName = $null
		$shareName = Build-GroupShareName $groupCN
		If($shareName -eq $false -or $shareName -eq $null)
			{
				$msg = "Error`tCould not build share name for this group."
				Throw-Warning $msg
				$fail = $true
			}
		
		#Get Share Trustees
		If($fail -eq $false)
			{
				$msg = "Action`t`tRetrieving share ACL."
				Write-Out $msg "darkcyan" 4
				$fileServer = $null
				$fileServer = Read-Variable "fileserver"
				$strWMI = $null
				$strWMI = "\\" + $fileserver + "\root\cimv2:Win32_LogicalShareSecuritySetting.name='" + $shareName + "'"
				$lsss = $null
				$lsss = [wmi]$strWMI
				$shareUsers = $null
				$shareUsers = @()
				$dacl = $null
				$dacl = $LSSS.GetSecurityDescriptor().descriptor.dacl
				$dacl | %{$shareUsers += $_.Trustee.Name}
				
				#Check for obvious bad values (false, null, and single-user)
				$blnPermissionsCorrect = $null
				$blnPermissionsCorrect = $true
				If($shareusers -eq $false -or $shareusers -eq $null)
					{
						$msg = "Error`t`tThe ACE for this share is corrupted, possibly by deleted groups."
						Throw-Warning $msg
						$msg = "INFO`t`t`tIf the script fails on this test, wait 15 seconds are restart the script."
						Throw-Warning $msg
						$blnPermissionsCorrect = $false
					}
				ElseIf(($shareUsers -is [array]) -eq $false)
					{
						
						$msg = "Error`t`t`tOnly a single user ACE was returned."
						Throw-Warning $msg
						$blnPermissionsCorrect = $false
					}
			}
		
		#Check for users not in the 'goodUsers' array present in the ACL.
		If($fail -eq $false -and $blnPermissionsCorrect -eq $true)
			{
				$msg = "Action`t`tChecking for trustees that should not be in the ACL."
				Write-Out $msg "darkcyan" 4
				$user = $null
				Foreach($user in $shareUsers)
					{
						If($goodUsers -contains $user)
							{}
						Else
							{
								$msg = "INFO`t`t`tUser\group does not belong in the ACL: """ + $user + """."
								Write-Out $msg "darkcyan" 4
								$blnPermissionsCorrect = $false
							}
					}
			}
		
		#Check to make sure we're not missing any users
		If($fail -eq $false -and $blnPermissionsCorrect -eq $true)
			{
				$msg = "Action`t`tChecking for trustees missing from the ACL."
				Write-Out $msg "darkcyan" 4
				$user = $null
				Foreach($user in $goodUsers)
					{
						If($shareUsers -contains $user)
							{}
						Else
							{
								$msg = "Error`t`t`tUser must be added to the ACL: """ + $user + """."
								Throw-Warning $msg
								$blnPermissionsCorrect = $false
							}
					}
			}
		
		#Check that all users have the proper permissions (full control)
		#REFERENCE: http://www.peetersonline.nl/index.php/powershell/listing-share-permissions-for-remote-shares/
		If($fail -eq $false -and $blnPermissionsCorrect -eq $true)
			{
				$msg = "Action`t`tChecking trustee permissions."
				Write-Out $msg "darkcyan" 4
				Foreach($acl in $dacl)
					{
						$username = $null
						$username = $acl.trustee.name
						$rawAccessMask = $null
						$rawAccessMask = $acl.AccessMask
						$strAccessMask = $null
						$strAccessMask = Get-ShareAccessMask $rawAccessMask
						$msg = "Info`t`tTrustee: """ + $username + """`n`t`t`tAccessmask: """ + $rawAccessMask + """`n`t`t`tHuman-Readable Accessmask: """ + $strAccessMask + """."
						Write-Out $msg "darkcyan" 4
						If($username -eq $strReadGroup)
							{
								#write-host -f red "BING! matched groups"
								If($rawAccessMask -eq 1179817)
									{}
								Else
									{
										If($strAccessMask -eq "" -or $strAccessMask -eq $null)
											{$strAccessMask = $rawAccessMask}
										$msg = "Error`t`t`tTrustee """ + $username + """ is listed incorrectly as """ + $strAccessMask + """."
										Throw-Warning $msg
										$blnPermissionsCorrect = $false
									}
							}
						ElseIf($rawAccessMask -eq 2032127)
							{}
						Else
							{
								$strAccessMask = $null
								$strAccessMask = Get-ShareAccessMask $rawAccessMask
								If($strAccessMask -eq "" -or $strAccessMask -eq $null)
									{$strAccessMask = $rawAccessMask}
								#$username = $acl.trustee.name
								$msg = "Error`t`t`tTrustee """ + $username + """ is listed incorrectly as """ + $strAccessMask + """."
								Throw-Warning $msg
								$blnPermissionsCorrect = $false
							}
					}
			}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $blnPermissionsCorrect}
		Return $retval
	}

Function Check-GroupFolderLocation($hshVariables)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		
		$groupCN = $null
		$groupCN = $hshVariables.Get_Item("groupCN")
		
		$shareName = $null
		$shareName = Build-GroupShareName $groupCN
		
		$strGeneratedHomePath = $null
		$strGeneratedHomePath = Generate-NewGroupFolderPath $hshVariables
		If($strGeneratedHomePath -eq $null -or $strGeneratedHomePath -eq $false)
			{
				$warningMsg = "ERROR`t`t`tCould not build group folder destination path."
				Throw-warning $warningMsg
				$failThisFunction = $true
			}
		Else
			{
				$strGeneratedHomePath = $strGeneratedHomePath.ToLower()
				$msg = "INFO`t`tGenerated group folder destination path: """ + $strGeneratedHomePath + """."
				Write-Out $msg "darkcyan" 4
			}
		
		$strSharePath = $null
		$strSharePath = Get-SharePathAsAdminUNC $shareName
		If($strSharePath -eq $null -or $strGeneratedHomePath -eq $false)
			{
				$warningMsg = "ERROR`t`t`tCould not find group share."
				Throw-warning $warningMsg
				$failThisFunction = $true
			}
		Else
			{
				$strSharePath = $strSharePath.ToLower()
				$msg = "INFO`t`tCurrent group share read as: """ + $strSharePath + """."
				Write-Out $msg "darkcyan" 4
			}
		
		If($failThisFunction -eq $false)
			{
				$strGeneratedHomePath = $strGeneratedHomePath.ToLower()
				$strSharePath = $strSharePath.ToLower()
				If($strGeneratedHomePath -eq $strSharePath)
					{$results = $true}
				Else
					{$results = $false}
			}
		
		If($failThisFunction -eq $false)
			{}
		Else
			{$results = $true}
		
		Return $results
	}

Function Conform-GroupFolderLocation($hshVariables)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		
		$bRebuild = $false
		$bRebuild = Check-GroupFolderLocation $hshVariables
		If($bRebuild -eq $false)
			{
				$bRebuildSuccess = $false
				$bRebuildSuccess = Rebuild-GroupFolders $hshVariables
				If($bRebuildSucecss -eq $false)
					{$failThisFunction = $true}
				Else
					{
						$arrNewTestsToSkip = $script:arrTestsToSkip
						$arrNewTestsToSkip += "groupFolderLocation"
						$arrNewTestsToSkip += "groupFolderOrphans"
						$arrNewTestsToSkip += "groupFolderPermissions"
						$arrNewTestsToSkip += "groupFolderExistence"
						$arrNewTestsToSkip += "shareExists"
						$arrNewTestsToSkip += "sharePermissions"
						$arrNewTestsToSkip += "sharePath"
						$script:arrTestsToSkip = $arrNewTestsToSkip
						$results = $true
					}
			}
		Else
			{$results = $true}
		
		If($failThisFunction -eq $true)
			{$results = $false}
		Else
			{}
		
		Return $results
	}

Function Rebuild-GroupFolders($hshVariables)
	{
		$failThisFunction = $null
		$failThisFunction = $false
		
		$msg = "ACTION`tRebuilding group folder."
		Write-Out $msg "darkcyan" 4
		
		#look for current share path
		$groupCN = $hshVariables.Get_Item("groupCN")
		$shareName = Build-GroupShareName $groupCN
		$blnCurrentShareExists = $false
		$blnCurrentShareExists = Check-DoesShareExist $shareName
		If($blnCurrentShareExists -eq $true)
			{
				$strOldSharePath = $null
				$strOldSharePath = Get-SharePathAsAdminUNC $shareName
			}
		$groupDN = $null
		$groupDN = Get-DNbyCN $groupCN
		#write-host -f yellow "groupDN: $groupDN"
		$objGroup = $null
		$objGroup = [adsi]("LDAP://" + $groupDN)
		
		#build destination folder path
		$msg = "ACTION`tBuilding group folder destination path."
		Write-Out $msg "darkcyan" 4
		$strDestinationPath = $null
		$strDestinationPath = Generate-NewGroupFolderPath $hshVariables
		$blnDestinationPathBuilt = $null
		If($strDestinationPath -eq "" -or $strDestinationPath -eq $null -or $strDestinationPath -eq $false)
			{$blnDestinationPathBuilt = $false}
		Else
			{$blnDestinationPathBuilt = $true}
		If($blnDestinationPathBuilt -eq $true)
			{
				$msg = "INFO`tGroup folder destination path built as """ + $strDestinationPath + """."
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
		
		#find orphans
		$arrOrphans = $null
		$arrOrphans = Find-GroupFolderOrphans $groupCN
		If($arrOrphans -eq $false)
			{
				$msg = "Error`t`tProblem checking for group folder orphans."
				Throw-Warning $msg
				$fail = $true
			}
		ElseIf($arrOrphans -eq $null)
			{
				$msg = "Info`t`tNo orphans found."
				Write-Out $msg "darkcyan" 4
				$blnNoOrphansFound = $true
			}
		Else
			{
				$msg = "Info`t`tFound the following orphans:"
				Write-Out $msg "darkcyan" 4
				Display-Array $arrOrphans 3 4
				$blnNoOrphansFound = $false
			}
		
		#migrate orphans
		If($blnNoOrphansFound -eq $false -and $failThisFunction -eq $false)
			{
				
				$msg = "ACTION`tMigrating all orphans to: """ + $strDestinationPath + """."
				Write-Out $msg "darkcyan" 4
				$arrOrphans | % {
					$strCurrentOrphan = $_
					$strCurrentOrphan = $strCurrentOrphan.ToLower()
					$strOldSharePath = $strOldSharePath.ToLower()
					If($strCurrentOrphan -ne $strOldSharePath)
						{
							$msg = "ACTION`tMigrating orphan located at: """ + $strCurrentOrphan + """."
							Write-Out $msg "darkcyan" 4
							$results = Migrate-Folder $strCurrentOrphan $strDestinationPath $objGroup
						}
				}
			}
		
		#precopy current share
		If($failThisFunction -eq $false -and $blnCurrentShareExists -eq $true)
			{
				$msg = "ACTION`tPrecopying current share's data."
				Write-Out $msg "darkcyan" 4
				$results = $null
				$results = Precopy-Folder $strOldSharePath $strDestinationPath $objGroup
				If($results -eq $true)
					{
						$msg = "INFO`tShare's data precopied successfully."
						Write-Out $msg "darkcyan" 4
					}
				Else
					{
						$msg = "ERROR`tFailed to precopy the current share's data."
						Throw-Warning $msg
						$failThisFunction = $true
					}
			}
		
		#switch sharepath \ recreate the share
		If($failThisFunction -eq $false)
			{
				$msg = "ACTION`tTesting \ rebuilding the group share."
				Write-Out $msg "darkcyan" 4
				$shareName = Build-GroupShareName $groupCN
				$blnShareRecreated = $null
				$blnShareRecreated = Rebuild-Share $shareName $strDestinationPath $objGroup
				If($blnShareRecreated -eq $true)
					{
						$msg = "INFO`tGroup share tested ok."
						Write-Out $msg "darkcyan" 4
						$results = Conform-SharePermissions $hshVariables
					}
				Else
					{
						$warningMsg = "ERROR`tCould not recreate the group share."
						Throw-Warning $warningMsg
						$failThisFunction = $true
					}
			}
		
		#migrate current share
		If($failThisFunction -eq $false -and $blnCurrentShareExists -eq $true)
			{
				$msg = "ACTION`tMigrating current share's data."
				Write-Out $msg "darkcyan" 4
				$results = $null
				$results = Migrate-Folder $strOldSharePath $strDestinationPath $objGroup
				If($results -eq $true)
					{
						$msg = "INFO`tShare's data migrated ok."
						Write-Out $msg "darkcyan" 4
					}
				Else
					{
						$warningMsg = "ERROR`tCould not migrate the group share's data."
						Throw-Warning $warningMsg
						$failThisFunction = $true
					}
			}
		
		#enforce group directory permissions
		$msg = "ACTION`tEnforcing proper target home directory permissions."
		Write-Out $msg "darkcyan" 4
		$blnPermissionsEnforced = $null
		$blnPermissionsEnforced = Conform-GroupFolderPermissions $hshVariables
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
		
		If($failThisFunction -eq $true)
			{$retval = $false}
		Else
			{$retval = $true}
		Return $retval
	}

Function Check-GroupFolderOrphans($hshVariables)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		$groupCN = $null
		$groupCN = $hshVariables.Get_Item("groupCN")
		
		$blnNoOrphansFound = $null
		$blnNoOrphansFound = $false
		$arrOrphans = $null
		$arrOrphans = Find-GroupFolderOrphans $groupCN
		If($arrOrphans -eq $false)
			{
				$msg = "Error`t`tProblem checking for group folder orphans."
				Throw-Warning $msg
				$fail = $true
			}
		ElseIf($arrOrphans -eq $null)
			{
				$msg = "Info`t`tNo orphans found."
				Write-Out $msg "darkcyan" 4
				$blnNoOrphansFound = $true
			}
		Else
			{
				$msg = "Info`t`tFound the following orphans:"
				Write-Out $msg "darkcyan" 4
				Display-Array $arrOrphans 3 4
				$blnNoOrphansFound = $false
			}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $blnNoOrphansFound}
		Return $retval
	}

Function Find-GroupFolderOrphans($groupCN)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		#find the sharePath
		$msg = "Action`t`tFinding the share path."
		Write-Out $msg "darkcyan" 4
		$shareName = $null
		$shareName = Build-GroupShareName $groupCN
		$sharePath = $null
		$sharePath = Get-SharePath $shareName
		$shareUNCPath = Convert-SharePathToUNCPath $sharePath
		$msg = "Info`t`tShare path found as """ + $sharePath + """."
		Write-Out $msg "darkcyan" 4
		
		#define where to look
		$msg = "Action`t`tBuilding a list of places to look for orphans."
		Write-Out $msg "darkcyan" 4
		$rootsToSearch = $null
		$rootsToSearch = @()
		$formattedGroupCN = $null
		$formattedGroupCN = Format-GroupName-ReplaceSpaces $groupCN
		$fileServer = $null
		$fileServer = Read-Variable "fileServer"
		$rootsToSearch += "\\" + $fileServer + "\j$\shares\" + $formattedGroupCN
		$rootsToSearch += "\\" + $fileServer + "\l$\shares\" + $formattedGroupCN
		$rootsToSearch += "\\" + $fileServer + "\c$\mount\groupbackups\shares\" + $formattedGroupCN
		$possibleUNCs = $null
		$possibleUNCs = Generate-PossibleValidGroupUNCs $groupCN
		$UNC = $null
		Foreach($UNC in $possibleUNCs)
			{
				If($UNC -ne $shareUNCPath)
					{$rootsToSearch += $UNC}
			}
		$msg = "Info`t`tGenerated list of paths to search:"
		Write-Out $msg "darkcyan" 4
		Display-Array $rootsToSearch 3 4
		
		#search in these places
		$msg = "Action`t`tSearching the paths for data."
		Write-Out $msg "darkcyan" 4
		$validPaths = $null
		$validPaths = @()
		$potentialPath = $null
		Foreach($potentialPath in $rootsToSearch)
			{
				$pathTest = $null
				$pathTest = Test-Path $potentialPath
				If($pathTest -eq $true)
					{
						#check for children
						$blnFolderIsEmpty = $null
						$blnFolderIsEmpty = Check-IsFolderEmpty $potentialpath
						If($blnFolderIsEmpty -eq $true)
							{}
						Else
							{
								If(($validPaths -contains $potentialPath) -eq $false)
									{
										$msg = "Info`t`t`tFound the valid path: """ + $potentialPath + """."
										Write-Out $msg "darkcyan" 4
										$validPaths += $potentialPath
									}
							}
					}
			}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $validPaths}
		Return $retval
	}

Function Find-MappingCaseStatement($arrMappingScript,$groupCN)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		#look for the Case statement for this group, then find the starting\ending line numbers of that case statement
		$line = $null
		$blnFound = $null
		$blnFound = $false
		$i = $null
		$i = 0
		$intCaseLineNumber = $null
		$strLineToMatch = $null
		$strLineToMatch = "Case """ + $groupCN + """"
		$msg = "Action`t`tSearching for the line: " + $strLineToMatch
		Write-Out $msg "darkcyan" 4
		Foreach($line in $arrMappingScript)
			{
				#look for the line to match
				If($line -like ("*" + $strLineToMatch + "*"))
					{
						$msg = "Info`t`t`tFound a mapping link for this group."
						Write-Out $msg "darkcyan" 4
						$blnFound = $true
						
						#this group's case statement starts at line $i
						$intStartCaseLineNumber = $i
						
						#find the line number where this group's case statement ends
						$intEndCaseLineNumber = $null
						$j = $null
						$j = $i + 1
						While($j -lt $arrMappingScript.Count)
							{
								$newLine = $null
								$newLine = $arrMappingScript[$j]
								#write-host -f yellow "newLine: $newLine"
								If($newLine -like "*Case ""*" -or $newLine -like "*End Select*")
									{
										$intEndCaseLineNumber = $j
										Break
									}
								Else
									{}
								$j++
							}
						If($intEndCaseLineNumber -eq $null)
							{
								$msg = "Error`t`tCould not tell when the mapping entry for this group ended."
								Throw-Warning $msg
								$fail = $true
							}
					}
				$i++
			}
		
		#create an array of this group's case statement for later analysis
		If($fail -eq $false)
			{
				$msg = "Action`t`tReading the case statement for this group."
				Write-Out $msg "darkcyan" 4
				$arrCaseStatement = $null
				$arrCaseStatement = @()
				$i = $null
				$i = 0
				$i = $intStartCaseLineNumber
				While($i -lt $intEndCaseLineNumber)
					{
						$strCurrentLine = $null
						$strCurrentLine = $arrMappingScript[$i]
						$arrCaseStatement += $strCurrentLine
						$i++
					}
				
				$msg = "Info`t`tCase statement read as:"
				Write-Out $msg "darkcyan" 4
				Display-Array $arrCaseStatement 3 $null "darkcyan"
			}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $arrCaseStatement}
		Return $retval
	}

Function Check-MappingCasePattern($strCaseStatementPattern)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		$msg = "Action`t`tAnalyzing the case statement interpretation."
		Write-Out $msg "darkcyan" 4
		$regex = $null
		$regex = "^0[34]*(12)+[34]*(12)*$"
		$msg = "Info`t`t`tUsing regex: " + $regex
		Write-Out $msg "darkcyan" 4
		If($strCaseStatementPattern -match $regex)
			{
				$msg = "Info`t`t`tCase statement pattern is correct"
				Write-Out $msg "darkcyan" 4
			}
		Else
			{
				$msg = "Error`t`tThere is a problem with the structure of this group's mapping statement."
				Throw-Warning $msg
				$fail = $true
			}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $true}
		Return $retval
		
	}

Function Generate-MappingCasePattern($arrCaseStatement)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		$msg = "Action`t`tInterpreting the case statement (ignores blank and commented lines)."
		Write-Out $msg "darkcyan" 4
		[string]$strCaseStatementPattern = $null
		$line = $null
		Foreach($line in $arrCaseStatement)
			{
				If($line -like "*'*")
					{$strCaseStatementPattern += 4}
				ElseIf($line -like "*Case ""*")
					{$strCaseStatementPattern += 0}
				ElseIf($line -like "*arrDrivesToMap(i) = ""*")
					{$strCaseStatementPattern += 1}
				ElseIf($line -like "*i = i + 1")
					{$strCaseStatementPattern += 2}
				ElseIf($line -match "^\s*$")
						{$strCaseStatementPattern += 3}
				Else
					{$strCaseStatementPattern += 5}
			}
		$msg = "Info`t`t`tCase statement interpreted as """ + $strCaseStatementPattern + """."
		Write-Out $msg "darkcyan" 4
		$msg = "Info`t`t`tKey:"
		Write-Out $msg "darkcyan" 4
		$arrKey = $null
		$arrKey = @()
		$arrKey += "0 - Case Statement"
		$arrKey += "1 - Mapping Statement"
		$arrKey += "2 - Incrementer"
		$arrKey += "3 - Blank"
		$arrKey += "4 - Commented Out"
		$arrKey += "5 - Other."
		Display-Array $arrKey 3 $null "darkcyan"
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $strCaseStatementPattern}
		
		Return $retval
	}

Function Generate-PathsFromCaseStatement($strCaseStatementPattern,$arrCaseStatement)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		$msg = "Action`t`tParsing the case statement into paths mapped."
		Write-Out $msg "darkcyan" 4
		$arrPaths = $null
		$arrPaths = @()
		$i = $null
		$i = 0
		$arrCaseStatementPattern = $null
		$arrCaseStatementPattern = $strCaseStatementPattern.ToCharArray()
		$character = $null
		Foreach($character in $arrCaseStatementPattern)
			{
				If($character -eq "1")
					{
						#grab the map path
						$strLine = $null
						$strLine = $arrCaseStatement[$i]
						#write-host -f yellow "strline: $strLine"
						$strFormattedLine = $null
						$strFormattedLine = $strLine.SubString(($strLine.IndexOf("""") + 1),($strLine.LastIndexOf("""") - ($strLine.IndexOf("""") + 1)))
						$arrPaths += $strFormattedLine
					}
				$i++
			}
		$msg = "Info`t`t`tThe case statement maps to the following paths:"
		Write-Out $msg "darkcyan" 4
		Display-Array $arrPaths 3 $null "darkcyan"
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $arrPaths}
		
		Return $retval
	}

Function Check-Mapping_GroupShareMapped($arrPaths,$groupCN)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		$shareName = $null
		$shareName = Build-GroupShareName $groupCN
		$blnPathFound = $null
		$blnPathFound = $false
		$msg = "Action`t`tTesting this path for the group share name """ + $shareName + """."
		Write-Out $msg "darkcyan" 4
		$strPath = $null
		Foreach($strPath in $arrPaths)
			{
				If($strPath -like ("*" + $shareName + "*"))
					{
						$msg = "Info`t`t`tFound path map."
						Write-Out $msg "darkcyan" 4
						$blnPathFound = $true
						Break
					}
			}
		If($blnPathFound -eq $true)
			{}
		Else
			{
				$msg = "Error`t`tThe mapping link to the group share was _not_ found."
				Throw-Warning $msg
				$fail = $true
			}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $blnPathFound}
		
		Return $retval
	}

Function Check-ShareMapping($hshArguments)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		#open the mapping script file
		$mappingScript = $null
		$mappingScript = Read-Variable "driveMappingScript"
		$msg = "Action`t`tOpening the mapping file: """ + $mappingScript + """."
		Write-Out $msg "darkcyan" 4
		If((Test-Path $mappingScript) -eq $false)
			{
				$msg = "Error`tMapping script DNE. File """ + $mappingScript + """ ."
				Throw-Warning $Msg
				$fail = $true
			}
		Else
			{
				$arrMappingScript = $null
				$arrMappingScript = Get-Content $mappingScript
			}
		
		#grab the case statement for this group
		$groupCN = $null
		$groupCN = $hshArguments.Get_Item("groupCN")
		$arrCaseStatement = $null
		$arrCaseStatement = Find-MappingCaseStatement $arrMappingScript $groupCN
		If($arrCaseStatement -eq $null -or $arrCaseStatement -eq $false)
			{
				#msgs sent already from the (f)Find-MappingCaseStatement
				$fail = $true
			}
		
		#Assign numbers to the parts of the array to look for errors
		[string]$strCaseStatementPattern = $null
		$strCaseStatementPattern = Generate-MappingCasePattern $arrCaseStatement
		If($strCaseStatementPattern -eq $null -or $strCaseStatementPattern -eq $false)
			{
				#msgs sent already from the (f)Find-MappingCaseStatement
				$fail = $true
			}
		
		#Analyze the case statement interpretation for pattern errors
		$blnPatternOK = $null
		$blnPatternOK = $false
		$blnPatternOK = Check-MappingCasePattern $strCaseStatementPattern
		If($blnPatternOK -eq $null -or $blnPatternOK -eq $false)
			{
				#msgs sent already from the (f)Find-MappingCaseStatement
				$fail = $true
			}
		
		#make an array of all paths mapped to
		$arrPaths = $null
		$arrPaths = Generate-PathsFromCaseStatement $strCaseStatementPattern $arrCaseStatement
		If($arrPaths -eq $null -or $arrPaths -eq $false)
			{
				#msgs sent already from the (f)Find-MappingCaseStatement
				$fail = $true
			}
		
		#look for the share name in $arrPaths
		$blnGroupShareMapped = $null
		$blnGroupShareMapped = $false
		$blnGroupShareMapped = Check-Mapping_GroupShareMapped $arrPaths $groupCN
		If($blnGroupShareMapped -eq $null -or $blnGroupShareMapped -eq $false)
			{
				#msgs sent already from the (f)Find-MappingCaseStatement
				$fail = $true
			}
		
		#test all the $arrPaths
		$blnAllPathsOK = $null
		$blnAllPathsOK = $false
		$blnAllPathsOK = Check-Mapping_AllPathsOk $groupCN $arrPaths
		If($blnAllPathsOK -eq $null -or $blnAllPathsOK -eq $false)
			{
				#msgs sent already from the (f)Find-MappingCaseStatement
				$fail = $true
			}
		
		Return $true
	}

Function Check-Mapping_AllPathsOk($groupCN,$arrPaths)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		
		$shareName = $null
		$shareName = Build-GroupShareName $groupCN
		$msg = "Action`t`tTesting all mapped paths."
		Write-Out $msg "darkcyan" 4
		$strPath = $null
		Foreach($strPath in $arrPaths)
			{
				If((Test-Path $strPath) -eq $false)
					{
						$msg = "Error`t`tCould not reach mapped path """ + $strPath + """."
						Throw-Warning $msg
						$fail = $true
					}
			}
		If($fail -eq $true)
			{}
		Else
			{
				$msg = "Info`t`t`tAll paths tested OK."
				Write-Out $msg "darkcyan" 4
			}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $true}
		
		Return $retval
	}

Function Conform-SecurityGroupsExist($hshVariables)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		$blnResults = $null
		$blnResults = $false
		$blnResults = Check-SecurityGroupsExist $hshVariables
		If($blnResults -eq $true)
			{}
		Else
			{
				#look for root group ("GroupCN")
				$groupCN = $null
				$groupCN = $hshVariables.Get_Item("groupCN")
				$blnGroupExists = $null
				$blnGroupExists = Check-DoesGroupExist $groupCN
				If($blnGroupExists -eq $false)
					{
						$msg = "Error`t`tThe root security group """ + $groupCN + """ does not exist!"
						Throw-Warning $msg
						$fail = $true
					}
				
				#test for groups
				$blnAllGroupsExist = $null
				$blnAllGroupsExist = $false
				If($fail -eq $false)
					{
						#create read group
						$strReadGroup = $null
						$strReadGroup = Get-ACLReadGroupCN $groupCN
						##Test existence
						$msg = "Action`t`tTesting for the exitence of the read-group """ + $strReadGroup + """."
						Write-Out $msg "darkcyan" 4
						$blnReadGroupExists = $null
						$blnReadGroupExists = Check-DoesGroupExist $strReadGroup
						If($blnReadGroupExists -eq $false)
							{
								$msg = "Action`t`tCreating the read group."
								Write-Out $msg "darkcyan" 4
								$blnCreated = $null
								$blnCreated = Create-ACLGroup $strReadGroup
								If($blnCreated -eq $false)
									{
										$msg = "Error`t`tProblem creating the group."
										Throw-Warning $msg
										$fail = $true
									}
							}
						Else
							{}
					}
				
				If($fail -eq $false)
					{
						#create write group
						$strWriteGroup = $null
						$strWriteGroup = Get-ACLWriteGroupCN $groupCN
						$msg = "Action`t`tTesting for the existence of the write-group """ + $strWriteGroup + """."
						Write-Out $msg "darkcyan" 4
						$blnWriteGroupExists = $null
						$blnWriteGroupExists = Check-DoesGroupExist $strWriteGroup
						If($blnWriteGroupExists -eq $false)
							{
								$msg = "Action`t`tCreating the write group."
								Write-Out $msg "darkcyan" 4
								$blnCreated = $null
								$blnCreated = Create-ACLGroup $strWriteGroup
								If($blnCreated -eq $false)
									{
										$msg = "Error`t`tProblem creating the group."
										Throw-Warning $msg
										$fail = $true
									}
							}
						Else
							{}
					}
				
				$blnResults = $null
				$blnResults = $false
				$blnResults = Check-SecurityGroupsExist $hshVariables
			}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $blnResults}
		Return $retval
	}

Function Conform-SecurityGroupsSAMAccountName($hshVariable)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		$blnResults = $null
		$blnResults = $false
		$blnResults = Check-SecurityGroupsSAMAccountName $hshVariables
		If($blnResults -eq $true)
			{}
		Else
			{
				#look for
				###"GroupCN"
				$groupCN = $null
				$groupCN = $hshVariables.Get_Item("groupCN")
				
				$readGroup = $null
				$readGroup = Get-ACLReadGroupCN $groupCN
				$writeGroup = $null
				$writeGroup = Get-ACLWriteGroupCN $groupCN
				
				$arrGroupsToCheck = $null
				$arrGroupsToCheck = @()
				$arrGroupsToCheck += $readGroup
				$arrGroupsToCheck += $writeGroup
				$group = $null
				Foreach($group in $arrGroupsToCheck)
					{
						#bind
						$msg = "Action`t`tTesting the """ + $group + """ group to see if the sAMAccountName matches the CN."
						Write-Out $msg "darkcyan" 4
				#		$msg = "Info`t`t`tCN: """ + $group + """."
				#		Write-Out $msg "darkcyan" 4
						$objGroupDN = $null
						$objGroupDN = Get-DNbyCN $group "group"
						$objGroup = $null
						$objGroup = [adsi]("LDAP://" + $objGroupDN)
						#get sAMAccountName
						$objGroupSAN = $null
						$objGroupSAN = $objGroup.Get("sAMAccountName")
						$msg = "Info`t`t`tsAMAccountName: """ + $objGroupSAN + """."
						Write-Out $msg "darkcyan" 4
						If($objGroupSAN -eq $group)
							{
								$msg = "Info`t`tGroup sAMAccountName matches the CN."
								Write-Out $msg "darkcyan" 4
							}
						Else
							{
								$msg = "Action`t`tSetting sAMAccountName to CN."
								Write-Out $msg "darkcyan" 4
								$objGroup.Put("sAMAccountName",$group)
								$objGroup.SetInfo()
							}
						#match against CN
					}
				
				#did we fix it?
				$blnResults = $null
				$blnResults = $false
				$blnResults = Check-SecurityGroupsSAMAccountName $hshVariables
			}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $blnResults}
		Return $retval
	}

Function Conform-SecurityGroupsLocation($hshVariables)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		$blnResults = $null
		$blnResults = $false
		$blnResults = check-SecurityGroupsLocation $hshVariables
		If($blnResults -eq $true)
			{}
		Else
			{
		
				$blnAllGroupsOK = $null
				$blnAllGroupsOK = $true
				$groupCN = $null
				$groupCN = $hshVariables.Get_Item("groupCN")
				
				#build read and write groups
				$strReadGroup = $null
				$strReadGroup = Get-ACLReadGroupCN $groupCN
				$strWriteGroup = $null
				$strWriteGroup = Get-ACLWriteGroupCN $groupCN
				
				#create a list of groups to check
				$groupsToCheck = $null
				$groupsToCheck = @()
				$groupsToCheck += $groupCN
				$groupsToCheck += $strReadGroup
				$groupsToCheck += $strWriteGroup
				
				$blnAllGroupsOK = $null
				$blnAllGroupsOK = $true
				$group = $null
				Foreach($group in $groupsToCheck)
					{
						If($fail -eq $false)
							{
								$msg = "Action`t`tChecking the location of the group """ + $group + """."
								Write-Out $msg "darkcyan" 4
								
								#build expected strings to match
								$arrExpectedOUStrings = $null
								$arrExpectedOUStrings = @()
								If($group -like "ACL_*")
									{$arrExpectedOUStrings += "Capability Resource Groups"}
								Else
									{
										$arrExpectedOUStrings += "Role Groups"
										$arrExpectedOUStrings += "Research Groups"
									}
								
								#grab the DN
								$strGroupDN = $null
								$strGroupDN = Get-DNbyCN $group "group"
								If($strGroupDN -eq $false)
									{
										$msg = "Error`t`tThe following group DNE: """ + $group + """."
										Throw-Warning $msg
										$fail = $true
									}
								Else
									{
										$blnDN_OK = $null
										$blnDN_OK = $false
										$expectedString = $null
										Foreach($expectedString in $arrExpectedOUStrings)
											{
												If($strGroupDN -like ("*" + $expectedString + "*"))
													{
														$blnDN_OK = $true
														Break
													}
											}
										If($blnDN_OK -eq $false)
											{
												$msg = "Error`t`tThe following group's DN is wrong: """ + $group + """."
												Write-Out $msg "darkcyan" 4
												$msg = "Error`t`tThe current DN is: """ + $strGroupDN + """."
												Write-Out $msg "darkcyan" 4
												If($group -like "ACL_*")
													{
														$msg = "Action`t`tMoving this group to the Capability Resource Groups OU."
														Write-Out $msg "darkcyan" 4
														$objSourceGroup = $null
														$objSourceGroup = [adsi]("LDAP://" + $strGroupDN)
														$strDestinationDN = $null
														#$strDestinationDN = $global:gSecurityGroupsOU
														$strDestinationDN = Read-Variable "CRGroupsOU"
														$objDestinationOU = $null
														$objDestinationOU = [ADSI]("LDAP://" + $strDestinationDN)
														$objSourceGroup.PSBase.MoveTo($objDestinationOU)
													}
												Else
													{
														$msg = "Error`t`tThe script is unwilling to move this group because it is not an ACL_ group."
														Throw-Warning $msg
														$fail = $true
													}
											}
									}
							}
					}
				$blnResults = $null
				$blnResults = $false
				$blnResults = check-SecurityGroupsLocation $hshVariables
			}
		
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $blnResults}
		Return $retval
	}

Function Conform-GroupFolderExistence($hshVariables)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		$blnResults = $null
		$blnResults = $false
		$blnResults = Check-GroupFolderExistence $hshVariables
		If($blnResults -eq $true)
			{}
		Else
			{
				
				$groupCN = $null
				$groupCN = $hshVariables.Get_Item("groupCN")
				
				#build the full path
				$groupFolderPath = $null
				$groupFolderPath = Generate-NewGroupFolderPath $hshVariables
				If($groupFolderPath -eq $false)
					{
						$msg = "Error`t`t`tCould not generate a new group folder path."
						Throw-Warning $msg
						$fail = $true
					}
				
				#create the folder there
				$folderCreated = $null
				$folderCreated = $false
				If($fail -eq $false)
					{
						$pathTest = $null
						$pathTest = Test-Path $groupFolderPath
						If($pathTest -eq $false)
							{
								$folderCreated = Create-Folder $groupFolderPath
								If($folderCreated -eq $false)
									{
										$msg = "Error`t`t`tCould not create folder at: """ + $groupFolderPath + """."
										Throw-Warning $msg
										$fail = $true
									}
								Else
									{
										$msg = "Info`t`t`tFolder created at: """ + $groupFolderPath + """."
										Write-Out $msg "white" 2
									}
							}
					}
				
				$blnResults = $null
				$blnResults = $false
				$blnResults = Check-GroupFolderExistence $hshVariables
			}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $blnResults}
		Return $retval
	}

Function Generate-NewGroupFolderPath($hshVariables)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		$bOverride = $false
		
		#look for an override group folder
		If($script:gOverrideVals.Keys -contains "newhome")
			{$bOverride = $true}
		Else
			{}
		
		# look for membership in "Backup Share"
		
		
		#look for an existing group folder
		If($bOverride -eq $false)
			{
				$blnExistingFolder = $null
				$blnExistingFolder = $false
				$strExistingFolder = $null
				$strExistingFolder = Find-GroupFolderLocation $hshVariables
				If($strExistingFolder -ne $null -and $strExistingFolder -ne "")
					{
						$msg = "Info`t`tFound an existing group folder """ + $strExistingFolder + """."
						Write-Out $msg "darkcyan" 4
						$blnExistingFolder = $true
						$finishedPath = $strExistingFolder
					}
				Else
					{$finishedPath = $null}
			}
		
		If($finishedPath -eq "" -or $finishedPath -eq $null)
			{
				If($bOverride -eq $true)
					{$groupVolume = $script:gOverrideVals.Get_Item("newhome")}
				Else
					{$groupVolume = Pick-GroupVolumeBySpaceFree}
				
				If($groupVolume -eq $false -or $groupVolume -eq "" -or $groupVolume -eq $null)
					{
						$msg = "Error`t`t`tCould not find a suitable group volume."
						Throw-Warning $msg
						$fail = $true
					}
				Else
					{}
				
				If($fail -eq $false)
					{
						#groupCN
						$groupCN = $null
						$groupCN = $hshVariables.Get_Item("groupCN")
						
						#grab file server
						$fileServer = $null
						$fileServer = Read-Variable "fileserver"
						
						#change rootpath from local to unc (C:\mount to c$\mount)
						$rootPath = $null
						$rootPath = Read-Variable "fileServer-LocalMountFolder"
						$formattedRootPath = $null
						$formattedRootPath = $rootPath -replace(":","$")
						
						#format group name
						$formattedGroupCN = $null
						$formattedGroupCN = Format-GroupName-ReplaceSpaces $groupCN
						
						#grow the root a little
						$alphaRoot = $null
						$alphaRoot = "\\" + $fileServer + "\" + $formattedRootPath + "\"
						
						#grab the buffer folder name
						$strBufferFolder = $null
						$strBufferFolder = Read-Variable "fileServer-BufferFolderName"
					}
				
				#put together all the pieces
				If($fail -eq $false)
					{
						$betaRoot = $null
						$betaRoot = $alphaRoot + $groupVolume + "\" + $strBufferFolder + "\" + $formattedGroupCN
					}
				
				$finishedPath = $null
				$finishedPath = $betaRoot.ToLower()
			}
		
		If($fail -eq $false)
			{
				$msg = "Info`t`tGenerated folder path """ + $finishedPath + """."
				Write-Out $msg "darkcyan" 4
			}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $finishedPath}
		Return $retval
	}

Function Pick-GroupVolumeBySpaceFree
	{
		$fileServer = $null
		$fileServer = Read-Variable "fileserver"
		
		$ServerName = $null
		$ServerName = $fileServer
		
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
						$vshort = """$vshort""" #Make it look like format in $MP (line 11).
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
								
								#$TotFolderSize = $null
								#$TotFolderSize = $fsize + $v.freespace 
								$percFree = $null
								$percFree = $v.freespace
								$name = $null
								$name = $v.name 
								
								#write-host "name: $name"
								#write-host "percfree: $percFree`n"
								
								If($name -like "*groups*")
									{
										If($percFree -gt $cur_highestPercFree)
											{
												$cur_highestPercFree = $percFree
												$strDestinationVolume = $null
												$strDestinationVolume = $name
											}
									}
							}
					}
			}
		
		$folderName = $null
		$folderName = $strDestinationVolume -replace ("C:\\mount\\","")
		$folderName = $folderName -replace ("\\","")
		
		Return $folderName
	}

Function Conform-GroupFolderPermissions($hshVariables)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		$blnResults = $null
		$blnResults = $false
		$blnResults = Check-GroupFolderPermissions $hshVariables
		If($blnResults -eq $true)
			{}
		Else
			{
				$groupCN = $null
				$groupCN = $hshVariables.Get_Item("groupCN")
				$sharePath = $null
				$sharePath = Build-GroupSharePath $hshVariables
				$targetPath = $null
				$targetPath = Convert-SharePathToUNCPath $sharePath
				
				$homeDrivesRootPath = $null
				$homeDrivesRootPath = Read-Variable "homeDrivesRootPath"
				
				$DN = $null
				$DN = Get-DNbyCN $groupCN
				
				$blnFoldersFixed = $null
				$blnFoldersFixed = Fix-FSObjectPermissions $targetPath $DN $homedrivesRootPath
				If($blnFoldersFixed -eq $null)
					{$blnFoldersFixed = $false}
				
				$blnResults = $null
				$blnResults = $false
				$blnResults = Check-GroupFolderPermissions $hshVariables
			}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $blnResults}
		Return $retval
	}

Function Fix-GroupFolderLocation($hshArguments)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $true}
		Return $retval
	}

Function Conform-ShareExists($hshVariables)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		$blnResults = $null
		$blnResults = $false
		$blnResults = Check-ShareExists $hshVariables
		If($blnResults -eq $true)
			{}
		Else
			{
				
				#find folder location
				$sharePath = Build-GroupSharePath $hshVariables
				If($sharePath -eq $false -or $sharePath -eq "")
					{
						$msg = "Error`t`tCould not generate a sharepath for this group."
						Throw-Warning $msg
						$fail = $false
					}
				
				If($fail -eq $false)
					{
						#create a share
						$groupCN = $null
						$groupCN = $hshVariables.Get_Item("groupCN")
						$formattedGroupCN = $null
						$formattedGroupCN = Format-GroupName-ReplaceSpaces $groupCN
						$shareName = $null
						$shareName = $formattedGroupCN
						
						$blnShareCreated = $null
						$blnShareCreated = $false
						$msg = "Action`t`tCreating share """ + $shareName + """ at path """ + $sharePath + """."
						Write-Out $msg "magenta" 2
						$blnShareCreated = Create-Share $shareName $sharePath
						If($blnShareCreated -eq $false)
							{
								$msg = "Error`t`tCould not create share """ + $shareName + """ at path """ + $sharePath + """."
								Throw-Warning $msg
								$fail = $true
							}
					}
				$blnResults = $null
				$blnResults = $false
				$blnResults = Check-ShareExists $hshVariables
			}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $blnResults}
		Return $retval
	}

Function Conform-SharePath($hshVariables)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		$blnResults = $null
		$blnResults = $False
		$blnResults = Check-SharePath $hshVariables
		If($blnResults -eq $true)
			{}
		Else
			{
				#find f	older location
				$UNCPath = Build-GroupSharePath $hshVariables
				If($UNCPath -eq $false -or $UNCPath -eq "")
					{
						$msg = "Error`t`tCould not generate a sharepath for this group."
						Throw-Warning $msg
						$fail = $false
					}
				Else
					{
						$sharePath = $null
						$sharePath = Convert-UNCPathToSharePath $UNCPath
					}
				
				If($fail -eq $false)
					{
						#rebuild the share
						$groupCN = $null
						$groupCN = $hshVariables.Get_Item("groupCN")
						$formattedGroupCN = $null
						$formattedGroupCN = Format-GroupName-ReplaceSpaces $groupCN
						$shareName = $null
						$shareName = $formattedGroupCN
						
						$blnShareCreated = $null
						$blnShareCreated = $false
						$msg = "Action`t`tRebuilding share """ + $shareName + """ at path """ + $sharePath + """."
						Write-Out $msg "white" 2
						$blnShareCreated = Modify-SharePath $shareName $sharePath
						If($blnShareCreated -eq $false)
							{
								$msg = "Error`t`tCould not create share """ + $shareName + """ at path """ + $sharePath + """."
								Throw-Warning $msg
								$fail = $true
							}
					}
				$blnResults = $null
				$blnResults = $False
				$blnResults = Check-SharePath $hshVariables
			}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $blnResults}
		Return $retval
	}

Function Precopy-GroupShare($hshVariables)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		#define targetpath
		$groupCN = $null
		$groupCN = $hshVariables.Get_Item("groupCN")
		$destination = $null
		$destination = Generate-NewGroupFolderPath $hshVariables
		If($destination -eq $false)
			{
				$msg = "Error`t`t`tCould not generate a destination folder path."
				Throw-Warning $msg
				$fail = $true
			}
		Else
			{
				$msg = "Info`t`tDestination folder path is """ + $destination + """."
				Write-Out $msg "darkcyan" 4
			}
		
		#precopy orphans to targetpath
		If($fail -eq $false)
			{
				$shareName = $null
				$shareName = Build-GroupShareName $groupCN
				$sharePath = $null
				$sharePath = Get-SharePath $shareName
				If($sharePath -eq $null -or $sharePath -eq $false)
					{
						$msg = "Error`t`tThis group currently has no group share."
						Throw-Warning $msg
						$fail = $true
					}
				
				If($fail -eq $false)
					{
						$source = $null
						$source = Convert-SharePathToUNCPath $sharePath
						
						If($source -eq $destination)
							{
								$msg = "Info`t`tThe source and destination are the same. Skipping precopy on this source."
								Write-Out $msg "darkcyan" 4
							}
						Else
							{
								#precopy
								$msg = "Action`t`tPrecopying source """ + $source + """."
								Write-Out $msg "darkcyan" 4
								$blnPrecopied = $null
								$blnPrecopied = $false
								#$switches = "/MIR"
								$blnPrecopied = Robocopy-Folder $source $destination
								If($blnPrecopied -eq $true)
									{
										$msg = "Info`t`tSource precopy finished."
										Write-Out $msg "darkcyan" 4
									}
								
								#verify
								#Verify the folder copy
								If($fail -eq $false)
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
												$fail = $true
											}
									}
							}
					}
			}
		Else
			{}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $true}
		Return $retval
	}

Function Conform-SharePermissions($hshVariables)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		$blnResults = $null
		$blnResults = $false
		$blnResults = Check-SharePermissions $hshVariables
		
		If($blnResults -eq $true)
			{}
		Else
			{
				#get groupCN
				$groupCN = $null
				$groupCN = $hshVariables.Get_Item("groupCN")
				
				#get shareName
				$shareName = $null
				$shareName = Build-GroupShareName $groupCN
				If($shareName -eq $null -or $shareName -eq "")
					{
						$msg = "Error`t`tCould not build share name for this group."
						Throw-Warning $msg
						$fail = $true
					}
				
				#build a new share DACL
				If($fail -eq $false)
					{
						$msg = "Action`t`tBuilding a new DACL for the group share """ + $shareName + """."
						Write-Out $msg "darkcyan" 4
						$newDACL = $null
						$newDACL = Build-GroupShareDACL $groupCN
						If($newDACL -eq $false -or $newDACL -eq "")
							{
								$msg = "Error`t`tCould not build a DACL for the group share """ + $shareName + """."
								Throw-Warning $msg
								$fail = $true
							}
					}
				
				#Set the share permissions
				If($fail -eq $false)
					{
						$msg = "Action`t`tApplying the new DACL to the group share """ + $shareName + """."
						Write-Out $msg "darkcyan" 4				
						$fileServer = $null
						$fileServer = Read-Variable "fileserver"
						$strWMI = $null
						$strWMI = "\\" + $fileserver + "\root\cimv2:win32_share.name='" + $shareName + "'"
						$objShare = $null
						$objShare = [wmi]$strWMI
						$objShare.SetShareInfo($Null,$Null,$newDACL.PSObject.BaseObject) | out-null
					}
				
				$blnResults = $null
				$blnResults = $false
				$blnResults = Check-SharePermissions $hshVariables
				
			}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $blnResults}
		Return $retval
	}

Function Conform-GroupFolderOrphans($hshVariables)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		$blnResults = $null
		$blnResults = $false
		$blnResults = Check-GroupFolderOrphans $hshVariables
		If($blnResults -eq $true)
			{}
		Else
			{
				#define targetpath
				$groupCN = $null
				$groupCN = $hshVariables.Get_Item("groupCN")
				$shareName = $null
				$shareName = Build-GroupShareName $groupCN
				$fileServer = $null
				#$fileServer = $global:gFileServer
				$fileServer = Read-Variable "fileserver"
				$sharePath = $null
				$sharePath = Get-SharePath $shareName
				$destination = $null
				$destination = Convert-SharePathToUNCPath $sharePath
				
				#find orphans
				$orphans = $null
				$orphans = Find-GroupFolderOrphans $groupCN
				If($orphans -eq $null -or $orphans -eq $false)
					{
						$msg = "Error`t`tProblem finding group folder orphans."
						Throw-Warning $msg
						$fail = $true
					}
				
				#if not array, force it into an array
				$arrOrphans = $null
				$arrOrphans = @()
				If($orphans -is [array])
					{$arrOrphans = $orphans}
				Else
					{$arrOrphans += $orphans}
				
				#precopy orphans to targetpath
				$orphan = $null
				Foreach($orphan in $orphans)
					{	
						If($fail -eq $false)
							{
								#precopy
								$msg = "Action`t`tPrecopying orphan """ + $orphan + """."
								Write-Out $msg "darkcyan" 4
								$blnPrecopied = $null
								$blnPrecopied = $false
								$blnPrecopied = Robocopy-Folder $orphan $destination
								If($blnPrecopied -eq $true)
									{
										$msg = "Info`t`tOrphan precopy finished."
										Write-Out $msg "darkcyan" 4
									}
								
								$source = $orphan
								#verify
								#Verify the folder copy
								If($fail -eq $false)
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
												$fail = $true
											}
									}
							}
						Else
							{Break}
						
						#migrate orphans to targetpath
						If($fail -eq $false)
							{
								#precopy
								$msg = "Action`t`tMerging orphan """ + $orphan + """ into """ + $destination + """."
								Write-Out $msg "darkcyan" 4
								$blnMerged = $null
								$blnMerged = $false
								$blnMerged = Migrate-Folder $orphan $destination
								If($blnMerged -eq $true)
									{
										$msg = "Info`t`tOrphan merged successfully."
										Write-Out $msg "darkcyan" 4
									}
								Else
									{
										$msg = "Error`t`tOrphan merge failed."
										Throw-Warning $msg
										$fail = $true
									}
							}
						Else
							{Break}
					}
				$blnResults = $null
				$blnResults = $false
				$blnResults = Check-GroupFolderOrphans $hshVariables
			}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $blnResults}
		Return $retval
	}

Function build-GroupShareDACL($groupCN)
	{
		#References
		#http://mow001.blogspot.com/2006/05/powershell-import-shares-and-security.html
		#http://thepowershellguy.com/blogs/posh/archive/2007/01/23/powershell-converting-accountname-to-sid-and-vice-versa.aspx
		
		$domain = Read-Variable "domainName_Short"
		$mode = "Full"
		
		# Get the needed WMI Classes
		
		$fileServer = $null
		$fileServer = Read-Variable "fileserver"
		$strWMI = $null
		$strWMI = "//" + $fileserver + "/root/cimv2:Win32_SecurityDescriptor"
		$SdObject = $null
		$SdObject = [wmiclass]$strWMI
		$sd = $null
		$sd = $SdObject.CreateInstance()
		
		
		###Read Group
		
		#Create Objects for Read Group
		$strWMI = $null
		$strWMI = "//" + $fileserver + "/root/cimv2:Win32_ACE"
		$Ace_ReadGroup_Object = $null
		$Ace_ReadGroup_Object = [wmiclass]$strWMI
		$Ace_ReadGroup = $null
		$Ace_ReadGroup = $Ace_ReadGroup_Object.CreateInstance()
		$strWMI = $null
		$strWMI = "//" + $fileserver + "/root/cimv2:Win32_Trustee"
		$Trustee_ReadGroup_Object = $null
		$Trustee_ReadGroup_Object = [wmiclass]$strWMI
		$Trustee_ReadGroup = $null
		$Trustee_ReadGroup = $Trustee_ReadGroup_Object.CreateInstance()
		
		#Make the Trustee for the read group
		$strReadGroup = $null
		$strReadGroup = Get-ACLReadGroupCN $groupCN
		$Trustee_ReadGroup.Domain = $Domain
		$Trustee_ReadGroup.Name = $strReadGroup
		
		#Get the SID, and convert it into binary form
		$SidAccount_ReadGroup = $null
		$SidAccount_ReadGroup = New-Object System.Security.Principal.NtAccount($Domain,$strReadGroup)
		$StringSID_ReadGroup = $null
		$StringSID_ReadGroup = $SidAccount_ReadGroup.Translate([system.security.principal.securityidentifier])
		[byte[]]$BinarySID_ReadGroup = $null
		[byte[]]$BinarySID_ReadGroup = ,0 * $StringSID_ReadGroup.BinaryLength
		$StringSID_ReadGroup.GetBinaryForm($BinarySID_ReadGroup,0)
		$Trustee_ReadGroup.SID = $BinarySID_ReadGroup
		
		#Set up the ACE for the read group
		$Ace_ReadGroup.AccessMask = ([System.Security.AccessControl.FileSystemRights]1179817).Value__
		$Ace_ReadGroup.AceType = 0
		$Ace_ReadGroup.AceFlags = 3
		$Ace_ReadGroup.Trustee = $Trustee_ReadGroup.psobject.baseobject
		
		
		
		###Write Group
		
		#Create Objects for Write Group
		$strWMI = $null
		$strWMI = "//" + $fileserver + "/root/cimv2:Win32_ACE"
		$Ace_WriteGroup_Object = $null
		$Ace_WriteGroup_Object = [wmiclass]$strWMI
		$Ace_WriteGroup = $null
		$Ace_WriteGroup = $Ace_WriteGroup_Object.CreateInstance()
		$strWMI = $null
		$strWMI = "//" + $fileserver + "/root/cimv2:Win32_Trustee"
		$Trustee_WriteGroup_Object = $null
		$Trustee_WriteGroup_Object = [wmiclass]$strWMI
		$Trustee_WriteGroup = $null
		$Trustee_WriteGroup = $Trustee_WriteGroup_Object.CreateInstance()
		
		#Make the Trustee for the write group
		$strWriteGroup = $null
		$strWriteGroup = Get-ACLWriteGroupCN $groupCN
		$Trustee_WriteGroup.Domain = $Domain
		$Trustee_WriteGroup.Name = $strWriteGroup
		
		#Get the SID, and convert it into binary form
		$SidAccount_WriteGroup = $null
		$SidAccount_WriteGroup = New-Object System.Security.Principal.NtAccount($Domain,$strWriteGroup)
		$StringSID_WriteGroup = $null
		$StringSID_WriteGroup = $SidAccount_WriteGroup.Translate([system.security.principal.securityidentifier])
		[byte[]]$BinarySID_WriteGroup = $null
		[byte[]]$BinarySID_WriteGroup = ,0 * $StringSID_WriteGroup.BinaryLength
		$StringSID_WriteGroup.GetBinaryForm($BinarySID_WriteGroup,0)
		$Trustee_WriteGroup.SID = $BinarySID_WriteGroup
		
		#Set up the ACE for the write group
		
		$Ace_WriteGroup.AccessMask = ([System.Security.AccessControl.FileSystemRights]"FullControl").Value__
		$Ace_WriteGroup.AceType = 0
		$Ace_WriteGroup.AceFlags = 3
		$Ace_WriteGroup.Trustee = $Trustee_WriteGroup.psobject.baseobject
		
		
		
		###Admins Group
		
		#Create Objects for Admin's group
		$strWMI = $null
		$strWMI = "//" + $fileserver + "/root/cimv2:Win32_ACE"
		$Ace_ShareAdmins_Object = $null
		$Ace_ShareAdmins_Object = [wmiclass]$strWMI
		$Ace_ShareAdmins = $null
		$Ace_ShareAdmins = $Ace_ShareAdmins_Object.CreateInstance()
		$strWMI = $null
		$strWMI = "//" + $fileserver + "/root/cimv2:Win32_Trustee"
		$Trustee_ShareAdmins_Object = $null
		$Trustee_ShareAdmins_Object = [wmiclass]$strWMI
		$Trustee_ShareAdmins = $null
		$Trustee_ShareAdmins = $Trustee_ShareAdmins_Object.CreateInstance()
		
		#Make the Trustee for the Admin's group
		$strGroupDriveAdminsCN = Read-Variable "groupdriveAdminsGroup"
		$Trustee_ShareAdmins.Domain = $Domain
		$Trustee_ShareAdmins.Name = $strGroupDriveAdminsCN
		
		#Get the SID, and convert it into binary form
		$SidAccount_ShareAdmins = New-Object System.Security.Principal.NtAccount($Domain,"Group Drive Administrators")
		$StringSID_ShareAdmins = $SidAccount_ShareAdmins.Translate([system.security.principal.securityidentifier])
		[byte[]]$BinarySID_ShareAdmins = ,0 * $StringSID_ShareAdmins.BinaryLength
		$StringSID_ShareAdmins.GetBinaryForm($BinarySID_ShareAdmins,0)
		$Trustee_ShareAdmins.SID = $BinarySID_ShareAdmins
		
		#Set up the ACE for the Share Admin's group.
		$Ace_ShareAdmins.AccessMask = ([System.Security.AccessControl.FileSystemRights]"FullControl").Value__
		$Ace_ShareAdmins.AceType = 0
		$Ace_ShareAdmins.AceFlags = 3
		$Ace_ShareAdmins.Trustee = $Trustee_ShareAdmins.psobject.baseobject
		
		
		
		#Mix it together!
		
		#add the ACE(s) to the DACL
		$sd.DACL = @($Ace_ReadGroup.psobject.baseobject, $Ace_WriteGroup.psobject.baseobject, $Ace_ShareAdmins.psobject.baseobject)
		
		Return $sd
	}

Function Fix-ShareMapping($hshArguments)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		$fail = $true
		Return $false
		
#		$groupCN = $null
#		$groupCN = $hshArguments.Get_Item("groupCN")
#		
#		#open the mapping script
#		$mappingScript = $null
#		$mappingScript = $global:gMappingScript
#		$mappingScript = Read-Variable "DriveMappingScript"
#		$msg = "Action`t`tOpening the mapping file: """ + $mappingScript + """."
#		Write-Out $msg "darkcyan" 4
#		$arrMappingScript = $null
#		$arrMappingScript = Get-Content $mappingScript
#		
#		#look for our group lines
#		$strLineToMatch = $null
#		$strLineToMatch = "Case """ + $groupCN + """"
#		$line = $null
#		$blnFound = $null
#		$blnFound = $false
#		$i = $null
#		$i = 0
#		$msg = "Action`t`tLooking for the line: " + $strLineToMatch
#		Write-Out $msg "darkcyan" 4
#		$blnChanged = $null
#		$blnChanged = $false
#		$blnInsertLinefound = $null
#		$blnInsertLinefound = $false
#		
#		#prebuild lines
#		$shareName = $null
#		$shareName = Build-GroupShareName $groupCN
#		$newLinkLine = $null
#		$newLinkLine = "`t`tCase """ + $groupCN + """"
#		$newShareLine = $null
#		$newShareLine = "`t`tarrDrivesToMap(i) = ""\\winfs\" + $shareName + ""
#		$mappingLinkIncrementer = $null
#		$mappingLinkIncrementer = "i = i + 1"
#		
#		#Build new mapping script
#		Foreach($line in $arrMappingScript)
#			{
#				#look for the line to match
#				If($line -like ("*" + $strLineToMatch + "*"))
#					{
#						#we found our *** Case "Group CN" *** line
#						$msg = "Info`t`t`tFound a mapping link for this group."
#						Write-Out $msg "darkcyan" 4
#						$blnFound = $true
#						
#						#build out some variables
#						$j = $null
#						$j = $i + 1
#						$intShareNameMappingLine = $null
#						$intShareNameMappingLine = $j
#						$shareNameMappingLine = $null
#						$shareNameMappingLine = $arrMappingScript[$j]
#						$k = $null
#						$k = $i + 2
#						$intMappingLinkIncrementerLine = $null
#						$intMappingLinkIncrementerLine = $k
#						$mappingLinkIncrementerLine = $null
#						$mappingLinkIncrementerLine = $arrMappingScript[$k]
#						
#						#checking shareNameLine for the correct sharename
#						$msg = "Action`t`tChecking the mapping link for the correct sharename."
#						Write-Out $msg "darkcyan" 4
#						If($shareNameMappingLine -like ("*" + $shareName + "*"))
#							{
#								$msg = "Info`t`t`tThe correct sharename was found; """ + $shareName + """."
#								Write-Out $msg "darkcyan" 4
#							}
#						Else
#							{
#								$msg = "Info`t`t`tThe correct sharename was _NOT_ found; """ + $shareName + """."
#								Write-Out $msg "darkcyan" 4
#								
#								$arrMappingScript[$intShareNameMappingLine] = $newShareLine
#								$blnChanged = $true
#							}
#						
#						#checking sharename to make sure it's enabled
#						$msg = "Action`t`tChecking the share line to make sure it's enabled."
#						Write-Out $msg "darkcyan" 4
#						If($shareNameMappingLine -like "*'*")
#							{
#								$msg = "Info`t`t`tThe share line is disabled."
#								Write-Out $msg "darkcyan" 4
#								$msg = "Action`t`t`tWriting the new share line."
#								Write-Out $msg "darkcyan" 4
#								
#								$arrMappingScript[$intShareNameMappingLine] = $newShareLine
#								$blnChanged = $true
#							}
#						Else
#							{
#								$msg = "Info`t`t`tThe share line is enabled."
#								Write-Out $msg "darkcyan" 4
#							}
#						
#						#checking increnter
#						$msg = "Action`t`tChecking the structure of the mapping link."
#						Write-Out $msg "darkcyan" 4
#						If($mappingLinkIncrementerLine -like ("*" + $mappingLinkIncrementer + "*"))
#							{
#								$msg = "Info`t`t`tThe mapping link structure is correct."
#								Write-Out $msg "darkcyan" 4
#							}
#						Else
#							{
#								$msg = "Info`t`t`tThe mapping link structure is missing the incrementer."
#								Write-Out $msg "darkcyan" 4
#								$newIncrementerLine = $null
#								$newIncrementerLine = "`t`ti = i + 1"
#								$arrMappingScript[$k] = $newIncrementerLine
#								$blnChanged = $true
#							}
#						
#						#make sure it's not diabled
#						$msg = "Action`t`tChecking the mapping link to make sure it's enabled."
#						Write-Out $msg "darkcyan" 4
#						If($line -like "*'*")
#							{
#								$msg = "Info`t`t`tThe mapping link for this group is disabled."
#								Write-Out $msg "darkcyan" 4
#								$newLinkLine = $null
#								$newLinkLine = "`t`tCase """ + $groupCN + """"
#								$arrMappingScript[$i] = $newLinkLine
#								$blnChanged = $true
#							}
#						Else
#							{
#								$msg = "Info`t`t`tThe mapping link is enabled."
#								Write-Out $msg "darkcyan" 4
#							}
#					}
#				ElseIf($line -like "*Select*Case*strGroupName*" -and $blnInsertLinefound -eq $false)
#					{
#						$intInsertLine = $null
#						$intInsertLine = $i + 1
#						$blnInsertLinefound = $true
#						#write-host -f red "LINE: $i"
#					}
#				$i++
#			}
#		
#		#Add a mapping link if it DNE
#		$arrNewMappingScript = $null
#		$arrNewMappingScript = @()
#		If($blnFound -eq $false)
#			{
#				$msg = "Action`t`tAdding a mapping link for this group."
#				Write-Out $msg "darkcyan" 4
#				$i = $null
#				$i = 0
#				$line = $null
#				#throw together the first half of the script
#				Foreach($line in $arrMappingScript)
#					{
#						If($i -lt $intInsertLine)
#							{$arrNewMappingScript += $line}
#						$i++
#					}
#				#$arrNewMappingScript | % {Write-Host -f cyan $_}
#				
#				#build lines
#				$groupCN_ProperCase = $null
#				$groupCN_ProperCase = (Get-Culture).TextInfo.ToTitleCase($groupCN)
#				$caseLine = $null
#				$caseLine = "`t`tCase """ + $groupCN_ProperCase + """"
#				$shareLine = $null
#				$shareLine = "`t`t`tarrDrivesToMap(i) = ""\\winfs\" + $shareName + """"
#				$incrementLine = $null
#				$incrementLine = "`t`t`ti = i + 1"
#				#throw in the mapping link
#				$arrNewMappingScript += $caseLine
#				$arrNewMappingScript += $shareLine
#				$arrNewMappingScript += $incrementLine
#				
#				$arrNewMappingScript | % {Write-Host -f green $_}
#				
#				#throw in the rest
#				$i = $null
#				$i = 0
#				$line = $null
#				Foreach($line in $arrMappingScript)
#					{
#						If($i -ge $intInsertLine)
#							{$arrNewMappingScript += $line}
#						$i++
#					}
#				$blnChanged = $true
#			}
#		ElseIf($blnChanged -eq $true)
#			{
#				$line = $null
#				Foreach($line in $arrMappingScript)
#					{$arrNewMappingScript += $line}
#					$blnChanged = $true
#			}
#		
#		#$arrNewMappingScript | % {Write-Host -f yellow $_}
#		
#		#write changes
#		#REF: http://blogs.technet.com/b/gbordier/archive/2009/05/05/powershell-and-writing-files-how-fast-can-you-write-to-a-file.aspx
#		
#		
#		If($blnChanged -eq $true)
#			{
#				$msg = "Action`t`tApplying changes to the mapping script."
#				Write-Out $msg "darkcyan" 4
#				
#				#grab the location of the tmpMappingScript
#				$tmpMappingScript = $null
#				$tmpMappingScript = $global:gTempMappingScript
#				
#				#delete tmpMappingScript if it exists.
#				$pathTest = $null
#				$pathTest = $false
#				$pathTest = Test-Path $tmpMappingScript
#				If($pathTest -eq $true)
#					{Remove-Item $tmpMappingScript}
#				$pathTest = $null
#				$pathTest = $false
#				$pathTest = Test-Path $tmpMappingScript
#				If($pathTest -eq $true)
#					{
#						$msg = "Error`t`tCould not delete the temporary mapping script."
#						Throw-Warning $msg
#						$fail = $true
#					}
#				
#				#write tmpMappingScript
#				If($fail -eq $false)
#					{
#						$msg = "Action`t`tWriting changes to """ + $tmpMappingScript + """."
#						Write-Out $msg "darkcyan" 4
#						$pathTest = $null
#						$pathTest = $false
#						$pathTest = Test-Path $tmpMappingScript
#						If($pathTest -eq $false)
#							{
#								$stream = $null
#								$stream = [System.IO.StreamWriter]$tmpMappingScript
#								$nextString = $null
#								$line = $null
#								Foreach($line in $arrNewMappingScript)
#									{
#										#write-host -f yellow $line	
#										$stream.WriteLine($line)
#									}
#								$stream.close()
#							}
#						Else
#							{
#								$msg = "Error`t`tCould not write to the temporary mapping script location."
#								Throw-Warning $msg
#								$fail = $true
#							}
#					}
#				
#				#Apply mapping script changes
#				If($fail -eq $false)
#					{
#						$pathTest = $null
#						$pathTest = $false
#						$pathTest = Test-Path $tmpMappingScript
#						If($pathTest -eq $true)
#							{
#								#rename old mapping script
#								$i = $null
#								$i = 0
#								$blnBreak = $null
#								$blnBreak = $false
#								While($blnBreak -eq $false)
#									{
#										$oldName = $null
#										$oldName = $mappingScript + "_" + $i + ".old"
#										$pathTest = $null
#										$pathTest = $false
#										$pathTest = Test-Path $oldName
#										If($pathTest -eq $true)
#											{}
#										Else
#											{$blnBreak = $true}
#										$i++
#									}
#								
#								$msg = "Action`t`tRenaming """ + $mappingScript + """ to """ + $oldName + """."
#								Write-Out $msg "darkcyan" 4
#								Rename-Item $mappingScript -newname $oldName
#								
#								#rename temp to new
#								$msg = "Action`t`tRenaming """ + $tmpMappingScript + """ to """ + $mappingScript + """."
#								Write-Out $msg "darkcyan" 4
#								Rename-Item $tmpMappingScript -newname $mappingScript
#							}
#						Else
#							{
#								$msg = "ERROR`t`tCould not write to the mapping script."
#								Throw-Warning $msg
#								$fail = $true
#							}
#					}
#				
#			}
	
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $blnFound}
		Return $retval
	}

Function Conform-SecurityGroupsNesting($hshVariables)
	{
		$fail = $null
		$fail = $false
		$retval = $null
		
		$blnResults = $null
		$blnResults = $false
		$blnResults = Check-SecurityGroupsNesting $hshVariables
		If($blnResults -eq $true)
			{}
		Else
			{
				
				#find groupCN
				$groupCN = $null
				$groupCN = $hshArguments.get_item("groupCN")
				
				#build read group
				$strReadGroup = $null
				$strReadGroup = Get-ACLReadGroupCN $groupCN
				#get DN
				$readGroupDN = $null
				$readGroupDN = Get-DNbyCN $strReadGroup "group"
				
				#build write group
				$strWriteGroup = $null
				$strWriteGroup = Get-ACLWriteGroupCN $groupCN
				#get DN
				$writeGroupDN = $null
				$writeGroupDN = Get-DNbyCN $strWriteGroup "group"
				
				#array of groups to check
				$arrGroupsToCheck = $null
				$arrGroupsToCheck = @()
				$arrGroupsToCheck += $readGroupDN
				$arrGroupsToCheck += $writeGroupDN
				
				#check
				$blnAllOK = $null
				$blnAllOK = $true
				$groupDNToCheck = $null
				Foreach($groupDNToCheck in $arrGroupsToCheck)
					{
						$objGroup = $null
						$objGroup = [adsi]("LDAP://" + $groupDNToCheck)
						$testedGroupCN = $null
						$testedGroupCN = Pull-LDAPAttribute $objGroup "cn"
						$msg = "Action`t`tTesting group """ + $testedGroupCN + """."
						Write-Out $msg "darkcyan" 4
						$objRoleGroupDN = $null
						$objRoleGroupDN = Get-DNbyCN $groupCN "group"
						$blnCheck = $null
						$blnCheck = $false
						$blnCheck = Check-IsMemberOfGroup $objRoleGroupDN $groupDNtoCheck
						If($blnCheck -eq $true)
							{
								$msg = "Info`t`tThe group """ + $testedGroupCN + """ contains the group """ + $groupCN + """."
								Write-Out $msg "darkcyan" 4
							}
						Else
							{
								$msg = "Action`t`tAdding group """ + $groupCN + """ to the group """ + $testedGroupCN + """."
								Write-Out $msg "darkcyan" 4
								$objRoleGroup = $null
								$objRoleGroup = [adsi]("LDAP://" + $objRoleGroupDN)
								$destGroupDN = $null
								$destGroupDN = Get-DNbyCN $testedGroupCN
								$blnGroupAdded = $null
								$blnGroupAdded = Add-ToGroup $objRoleGroupDN $destGroupDN
								If($blnGroupAdded -eq $true)
									{
										$msg = "Info`t`tGroup added successfully."
										Write-Out $msg "darkcyan" 4
									}
								Else
									{
										$msg = "Error`t`tProblem changing group membership."
										Throw-Warning $msg
										$blnAllOK = $false
									}
							}
					}
				
				$blnResults = $null
				$blnResults = $false
				$blnResults = Check-SecurityGroupsNesting $hshVariables
			}
		
		If($fail -eq $true)
			{$retval = $false}
		Else
			{$retval = $blnResults}
		Return $retval
	}
	

#----Begin----
#initialize logging
$logFileDate = get-date -uformat '%d%m%Y-%H%M-%S'
$logFileName = $gScriptName + "_" + $logFileDate + ".txt"
$logFilePath = Read-Variable "logFilePath"
$logFilePath = Trim-TrailingSlash $logFilePath
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

#----Parse Arguments----
$global:gArrArguments = @()
$global:gArrArguments = $args

##General Variables
[array]$global:gArrArguments = $null	#Global copy of $args
$lArrArguments = $null								#Local scope copy of args (though, at the root)
$gStrRunMode = $null									#Run mode can be: gui, file, cli
$gStrRunModeModifiers = $null					#Run mode modifiers can be: verbose, eval, precopy
$gHshRunModeVariables = $null					#Run mode hash table of variables needed for that specific run mode to work.

##Regulatory Variables
$gBlnBadArgument = $null
$gBlnBadArgument = $false

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

#Second check - basic exclusivity checks
If($gBlnBadArgument -eq $false)
	{
		$blnExeclusivityCheckPassed = $null
		$blnExeclusivityCheckPassed = $false
		$blnExeclusivityCheckPassed = Verify-ArgumentExclusivity $lArrArguments
		If($blnExeclusivityCheckPassed -eq $false)
			{
				$warningMsg = "ERROR`tCould not verify arguments."
				Throw-Warning $warningMsg
				$gBlnBadArgument = $true
			}
	}

#Get all arguments and dependents, break if there's a problem
#e.g. turn "/file C:\test /precopy /eval" into @{"file","test;"precopy,"";"eval","";}
If($gBlnBadArgument -eq $false)
	{
		$hshValidatedArguments = $null
		$hshValidatedArguments = @{}
		$argCount = $null
		$argCount = $args.count
		$arg = $null
		$i = $null
		$i = 0
		While($i -lt $argCount -and $gBlnBadArgument -eq $false)
			{
				$currentArgument = $null
				$currentArgument = $lArrArguments[$i]
				
				$arrDependents = $null
				$arrDependents = Get-DependentArgs $currentArgument $lArrArguments
				###Write-Host -f yellow "arrDependents: $arrDependents"
				If($arrDependents -eq $false)
					{
						$msg = "ERROR`tCould not read or parse a dependent argument."
						Throw-Warning $msg
						$gBlnBadArgument = $true
					}
				ElseIf($arrDependents -eq "" -or $arrDependents -eq $null)
					{
						$arrDependents = @()
						$hshValidatedArguments.Add($currentArgument,"")
					}
				Else
					{
						$blnVerified = $null
						$blnVerified = $false
						$blnVerified = Verify-DependentArgs $currentArgument $arrDependents
						If($blnVerified -eq $true)
							{
								$strDependentArguments = $null
								$strDependentArguments = Parse-ArrayToCSVString $arrDependents
								$hshValidatedArguments.Add($currentArgument,$strDependentArguments)
								If($arrDependents -is [array] -eq $true)
									{$arrDependentsCount = $arrDependents.count}
								Else
									{$arrDependentsCount = 1}
								$i += $arrDependentsCount
							}
						Else
							{
								$warningMsg = "ERROR`tCould not verify an argument."
								Throw-Warning $warningMsg
								$gBlnBadArgument = $true
								Break
							}
					}
				$i++
			}
	}

If($hshValidatedArguments.Keys -contains "/newhome")
	{
		$gNewHome = $hshValidatedArguments.Get_Item("/newhome")
		#write-host -f magenta "adding newhome to script vars with variable " $gNewHome
		$script:gOverrideVals.Add("newHome",$gNewHome)
	}

#Call Director
$status = $null
If($gBlnBadArgument -eq $false)
	{
		write-openingblock
		$hshValidatedArguments | out-host
		$status = $null
		$status = Director $hshValidatedArguments
	}

If($gBlnBadArgument -eq $true -or $status -eq $false)
	{
		$warningMsg = "WARNING`tExiting script."
		Throw-Warning $warningMsg
		write-fail
		write-usageInfo
		Exit
	}
Else
	{Write-Win}