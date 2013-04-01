$sessMgr = Get-View ‘SessionManager’
#added 4 hours because all of my sessions seem to be 4 hours ahead when looked at through this code.
$sessMgr.SessionList | Where {($_.LastActiveTime).addminutes(5) -lt (Get-Date).AddHours(4)} | % {
		#$_    # <--- this would output the session information before killing it.
		$sessMgr.TerminateSession($_.Key)
	}

