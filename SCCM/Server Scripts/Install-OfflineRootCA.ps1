
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
Function ExistingKeySet ($Thumbprint) {
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

$siteCode = "TES"
$dnSuffix = "DC=dev-sccm,DC=local"
$domainSuffix = "dev-sccm.local"
$domainShort = "dev-sccm"
$sInstallFilesPath = "C:\Install_Files"
$CDPServerName = "dev-sccm-tes"


Function Install-RootCA()
	{
		$caName = $domainShort.ToLower() + "offline root CA"
		$csp = "RSA#Microsoft Software Key Storage Provider"
		$caType = "Standalone Root"
		$caDNSuffix = $dnSuffix
		$hashAlg = "SHA256"
		$dbDir = "C:\certdb"
		$logDir = "C:\certlogs"
		
		write-host -f cyan  "== Installing Office Standalone CA Role =="
		
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

Function Configure-RootCA()
	{
		$msg = "== Configure Root CA =="
		Write-host -f cyan $msg
		
		$system32 = ($env:windir).TrimEnd("\") + "\system32"
		
		$cdpString = $null
		$cdpString = """"
		$cdpString += "65:" + $env:windir + "\system32\CertSrv\CertEnroll\%3%8%9.crl\n"
		$cdpString += "6:http://cdp." + $domainSuffix + "/certdata/%3%8%9.crl\n"
		$cdpString += "6:http://" + ($CDPServerName).ToLower() + "." + $domainSuffix + "/certdata/%3%8%9.crl"
		$cdpString += """"
		
		$aiaString = $null
		$aiaString = """"
		$aiaString += "1:" + $env:windir + "\system32\CertSrv\CertEnroll\%1_%3%4.crt\n"
		$aiaString += "2:http://aia." + $domainSuffix + "/certdata/%1_%3%4.crt\n"
		$aiaString += "2:http://" + ($CDPServerName).ToLower() + "." + $domainSuffix + "/certdata/%1_%3%4.crt"
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
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "-setreg CA\CRLPeriodUnits 1"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Setting CRL Period (units)."
		$arrCmds += $oCmd
		
		#CRL Period Value
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\certutil.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "-setreg CA\CRLPeriod ""Years"""
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
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "-setreg CA\CRLOverlapPeriod ""Months"""
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Setting CRL Overlap value."
		$arrCmds += $oCmd
		
		#CRL Delta Units
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\certutil.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "-setreg CA\CRLDeltaPeriodUnits 0"
		$oCmd | Add-Member -type NoteProperty -name "DisplayName" -value "Setting CRL Delta (units)."
		$arrCmds += $oCmd
		
		#CRL Delta Value
		$oCmd = New-Object System.Object
		$oCmd | Add-Member -type NoteProperty -name "FullFilePath" -value ($system32 + "\certutil.exe")
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "-setreg CA\CRLDeltaPeriod ""Days"""
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
		$oCmd | Add-Member -type NoteProperty -name "Args" -value "-setreg CA\ValidityPeriodUnits 20"
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
	

Install-RootCA
Configure-RootCA

