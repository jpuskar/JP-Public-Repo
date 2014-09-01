Function Parse-SubjectLineForWiId($subjectLine) {
	$regex1 = $null
	$regex1 = "^*SR[0-9]+\s"
	#[string]$regex1 = "one"
	$regex2 = $null
	$regex2 = "^*IR[0-9]+\s"
	#[string]$regex2 = "two"
	
	$WorkitemId = $null
	$aRegexToTry = $null
	$aRegexToTry = @($regex1,$regex2)
	$aRegexToTry | % {
		$matches = $null
		$subjectLine -match $_ | out-null
		If($matches -eq "" -or $matches -eq $null) {}
		Else {
			$WorkitemId = $matches[0]
			#$matches
			#Continue
		}
	}
	
	$retval = $null
	$retval = $WorkitemId
	Return $retval
}

Parse-SubjectLineForWiId "Subject: ESL IT Support - SR566 - Software License - 1 HFSS license for Dr"