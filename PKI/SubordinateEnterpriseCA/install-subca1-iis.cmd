REM Install and Configure IIS for CertData content
Powershell -executionpolicy bypass -command "Import-Module ServerManager; Add-WindowsFeature net-framework-core"
PKGMGR.EXE /l:log.etw /iu:IIS-WebServerRole;IIS-WebServer;IIS-CommonHttpFeatures;IIS-StaticContent;IIS-DefaultDocument;IIS-HttpErrors;IIS-HttpRedirect;IIS-ApplicationDevelopment;IIS-ASP;IIS-ISAPIExtensions;IIS-HealthAndDiagnostics;IIS-HttpLogging;IIS-LoggingLibraries;IIS-RequestMonitor;IIS-HttpTracing;IIS-Security;IIS-WindowsAuthentication;IIS-RequestFiltering;IIS-IPSecurity;IIS-Performance;IIS-HttpCompressionStatic;IIS-WebServerManagementTools;IIS-IIS6ManagementCompatibility;IIS-Metabase
CALL moveIIS7Root.bat
REN C:\inetpub\wwwroot wwwroot.old
MKDIR F:\inetpub\wwwroot\CertData

REM Allow Double Escaping for Delta CRLs
%systemroot%\system32\inetsrv\appcmd set config /section:requestfiltering /allowdoubleescaping:true

REM Deny DFSRStaging from being accessed
%systemroot%\system32\inetsrv\appcmd set config /section:requestfiltering /+denyurlsequences.[sequence='DfsrPrivate']
