#####################################################################
# SetupCA.ps1
# Version 1.0
#
# This script installs or uninstalls Certification Authority role from the local server
#
# Vadims Podans (c) 2011
# http://en-us.sysadmins.lv/
#####################################################################
#requires -Version 2.0

function Install-CertificationAuthority {
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
function NewKeySet ($CAName, $CADNSuffix, $CAType, $ParentCA, $CSP, $KeyLength, $HashAlgorithm, $ValidForYears, $RequestFileName) {

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
	Remove-Module ServerManager
}

function Uninstall-CertificationAuthority {
[CmdletBinding(
	ConfirmImpact = 'None',
	SupportsShouldProcess = $true
)]
	param(
		[switch]$AutoRestart,
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
	catch {
		Write-Error -Category ObjectNotFound -ErrorId "ElementNotFoundException" `
		-ErrorAction Stop -Message "Certificate Services are not installed on this computer."
	}
#endregion

#region Binaries checking and removal stuff
	try {$CASetup = New-Object -ComObject CertOCM.CertSrvSetup.1}
	catch {
		Write-Error -Category NotImplemented -ErrorId "NotImplementedException" `
		-ErrorAction Stop -Message "Unable to load necessary interfaces. Your Windows Server operating system is not supported!"
	}
	try {Import-Module ServerManager -ErrorAction Stop}
	catch {
		ocsetup 'ServerManager-PSH-Cmdlets' /quiet | Out-Null
		Start-Sleep 1
		Import-Module ServerManager
	}
	$status = (Get-WindowsFeature -Name ADCS-Cert-Authority).Installed
	if ($status) {
		$WarningPreference = "SilentlyContinue"
		if ($Force -or $PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Uninstall Certification Authority")) {
			$CASetup.PreUninstall($false)
			$retn = Remove-WindowsFeature -Name ADCS-Cert-Authority -ErrorAction Stop
			if ($retn.RestartNeeded -and $AutoRestart) {
				Restart-Computer -Force
			} else {
				Write-Host @"
Certification Authority role was removed successfully. You must restart this server to complete role removal.
"@ -ForegroundColor Yellow -BackgroundColor Black
			}
		}
	}
	Remove-Module ServerManager
#endregion
}

Install-CertificationAuthority -CAName "Offline Root CA" -CSP "RSA#Microsoft Software Key Storage Provider" -CADNSuffix "dc=chemistry,dc=ohio-state,dc=edu" -CAType "Standalone Root" -HashAlgorith SHA256 -DBDirectory "C:\db-cert" -LogDirectory "C:\log-cert"
