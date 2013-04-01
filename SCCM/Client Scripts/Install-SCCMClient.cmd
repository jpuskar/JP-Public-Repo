if not exist \\%1\c$\scripts MKDIR \\%1\c$\scripts
if not exist \\%1\c$\scripts\sccm-client-5.00.7711.0000 MKDIR \\%1\c$\scripts\sccm-client-5.00.7711.0000
COPY /Y configMgrStartup.vbs \\%1\c$\scripts
COPY /Y ConfigMgrStartup-Math.xml \\%1\c$\scripts
XCOPY /E \\ad1.asc.ohio-state.edu\netlogon\sccm-client\5.00.7711.0000\* \\%1\c$\scripts\sccm-client-5.00.7711.0000\
REM psexec -s \\%1 cscript C:\scripts\configMgrStartup /config:C:\scripts\ConfigMgrStartup-Math.xml