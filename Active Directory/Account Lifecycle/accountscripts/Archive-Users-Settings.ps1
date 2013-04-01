#Create-Accounts-Settings.ps1

Function Read-ArchVariable($variable)
	{
		$results = $null
		
		Switch($variable)
			{
				"NeedsExpirationDateGroupCN"
					{
						$results = "Needs Expiration Date"
					}
				"LDIFattributesToVerify"
					{
						#note -- ldifde breaks up lines for no reason, so you can only really verify attributes whose values will be under 40 characters or so.
						$arrAttributes = $null
						$arrAttributes = @()
						#$arrAttributes += "distinguishedName"
						$arrAttributes += "cn"
						$arrAttributes += "sn"
						$arrAttributes += "givenName"
						$arrAttributes += "sAMAccountName"
						$arrAttributes += "userPrincipalName"
						$arrAttributes += "mail"
						$arrAttributes += "unixUID"
						$arrAttributes += "unixGID"
						$results = $arrAttributes
					}
				"domainController"
					{
						$results = "dc1"
					}
				"pathToLDIFDE"
					{
						$results = "C:\scripts\bin\ldifde.exe"
					}
				"createAccountsFilename"
					{
						$results = "create-accounts-b032.ps1"
					}
				Default
					{}
			}
		
		Return $results
	}
