;WaitForBattery
;John Puskar 01/16/2013
;johnpuskar@gmail.com
;windowsmasher.wordpress.com

Dim $batterystatus, $objwmiservice_, $status, $battPercentage
Dim $oBattery, $batteryInfo, $acPower
Local $objwmiservice = ObjGet ('winmgmts:\\localhost\root\CIMV2')
Local $objwmiservice2 = ObjGet ('winmgmts:\\localhost\root\wmi')

ProgressOn("Initializing Power Driver", "Initializing Power Driver...", "Please wait.")
Dim $sysRoot
$sysRoot = EnvGet ( "systemroot" )
RunWait(@comspec & " /c drvload %systemroot%\inf\battery.inf","",@SW_HIDE)
Dim $i
For $i = 0 To 100 Step 1
    Sleep(75)
    ProgressSet($i, $i & " percent")
Next
ProgressOff()

;Power adapter
Dim $i
$i = 0
While 1
	$oBattery = $objWMIService2.ExecQuery("SELECT * FROM BatteryStatus WHERE Voltage > 0")
	If IsObj($oBattery) Then
		SetError(0)
		
		Dim $errorCode
		Dim $batteryInfo
		Dim $acPower
		For $batteryInfo in $oBattery
			$acPower = $batteryInfo.PowerOnline
		Next
		$errorCode = @Error
		
		;Dim $msg
		;$msg = "i: " & $i & " | acpower: " & $acPower & " | error: " & $errorCode
		;msgbox(1,"AC Power",$msg)
		
		If $errorCode <> 0 Then
			ExitLoop
		ElseIf $acPower <> True Then
			If $i = 0 Then
				ProgressOn("AC Adapter", "Waiting for AC Adapter.", "Please plug in the laptop and wait 10 seconds...")
			EndIf
			Sleep(1000)
		Else
			ExitLoop
		EndIf
	Else
		ExitLoop
	EndIf
	$i = $i + 1
Wend
ProgressOff()

;Power charge
$i = 0
While 1
	Local $batterystatus = $objWMIService.ExecQuery("SELECT * FROM Win32_Battery")
	Dim $msg
	Dim $progressPercentage
	If IsObj ($batterystatus) Then
		For $status in $batterystatus
			$battPercentage = $status.EstimatedChargeRemaining
		Next
		$msg = "Battery Charge: " & $battPercentage & "%"
		$progressPercentage = 100 / 60 * $battPercentage - 1
		
		If $battPercentage = "" Then
			ExitLoop
		Else
			If $i = 0 Then
				ProgressOn("Battery Percentage", "", "Waiting for 60% charge...")
			EndIf
			ProgressSet($progressPercentage,"",$msg)
		EndIf
		
	Else
		ExitLoop
	EndIf
	
	If $battPercentage > 59 Then
		ExitLoop
	Else
		Sleep(2000)
	EndIf
	$i = $i + 1
Wend
ProgressOff()