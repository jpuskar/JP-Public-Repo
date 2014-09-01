#cisco-interpreter

Import-Module ShowUI

$inputWindow = StackPanel -ControlName "InputWindow" {
	TextBox -minlines 6 -maxlines 10 -maxwidth 600 -AcceptsReturn -TextWrapping "wrap" -name "inputBox"
	Button "Process" -name "submitButton" -On_Click {
		Function Process-STPDetail ($inText) {
			
			
			$i = $null
			$i = 0
			
			$ppgStartNumbers = $null
			$ppgStartNumbers = @()
			
			$inText | % {
				If($_ -like "*is designated*") {$ppgStartNumbers += $i}
				$i++
			}
			
			write-host "ppgStartNumbers: $ppgStartNumbers"
			write-host -f green $inText
			
			#now we have a map of where the port objects start
			$aPortObj = $null
			$aPortObj = @()
			$i = $null
			$i = 0
			
			$ppgStartNumbers | % {
				$i = $_
				$startLine = $_
				$finishLine = $startLine + 10
				
				#portName is easy
				$portName = $null
				[int]$portName = ($inText[$startLine].Split(" "))[2]
				
				#get other props
				$portTransitions = $null
				$bpduReceived = $null
				$bpduSent = $null
				While($i -le $finishLine) {
					If($intext[$i] -like "*BPDU: *") {
						$bpduSent = (($inText[$i].Split(" "))[5]).Replace(",","")
						$bpduReceived = ($inText[$i].Split(" "))[7]
					}
					
					If($intext[$i] -like "*Number of transitions to forwarding state: *") {
						$portTransitions = ($inText[$i].Split(" "))[9]
					}
					
					$i++
				}
				
				$newPort = $null
				$newPort = New-Object -TypeName PSObject
				$newPort | Add-Member -MemberType NoteProperty -Name "Port Name" -Value $portName
				$newPort | Add-Member -MemberType NoteProperty -Name "Port Transitions" -Value $portTransitions
				$newPort | Add-Member -MemberType NoteProperty -Name "BPDUs Sent" -Value $bpduSent
				$newPort | Add-Member -MemberType NoteProperty -Name "BPDUs Received" -Value $bpduReceived
				$aPortObj += $newPort
			}
			
			Return $aPortObj
			
		}
		
		$inText = $inputBox.Text
		$inText = $inText.Split("[`r`n]")		
		$inText = $inText | ?{$_ -ne "" -and $_ -ne $null}
		$inText | % {Write-Host -f cyan $_}
		
		Process-STPDetail $inText | Sort "Port Name" | Out-Host
		
	}
} -Show