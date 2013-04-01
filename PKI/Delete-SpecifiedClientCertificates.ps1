$badTempl = "1.3.6.1.4.1.311.21.8.3858753.1941150.1526201.15537621.13786382.63.15715115.11638692"
$badCA = "DC=edu, DC=ohio-state, DC=chemistry, CN=Chemistry Issuing CA1"

$cert = Get-ChildItem cert:\localmachine\my\*
$cert | % {
	$templateInfo = $null
	$templateInfo = ($_.Extensions | Where-Object {$_.Oid.FriendlyName -eq "Certificate Template Information"}).Format(1)
	If($templateInfo -like ("Template=" + $badTempl + "*") -and ($_.GetIssuerName().ToString() -eq $badCA))
		{
			#$_
			$exp = "certutil -delstore my " + ($_.Thumbprint.ToString())
			Invoke-Expression $exp | out-null
		}
}
