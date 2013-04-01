if not exist D:\db-cert mkdir D:\db-cert
if not exist E:\log-cert mkdir E:\log-cert

copy /y capolicy.inf %windir%

PowerShell -ExecutionPolicy bypass -file .\SetupCA-IssuingCA1.ps1

rem Declare Configuration NC
certutil -setreg CA\DSConfigDN CN=Configuration,DC=chemistry,DC=Ohio-State,DC=edu

rem Define CRL Publication Intervals
certutil -setreg CA\CRLPeriodUnits 8
certutil -setreg CA\CRLPeriod "Days"
certutil -setreg CA\CRLOverlapUnits 1
certutil -setreg CA\CRLOverlapPeriod "Days"
certutil -setreg CA\CRLDeltaPeriodUnits 12
certutil -setreg CA\CRLDeltaPeriod "Hours"

REM Apply the required CDP Extension URLs
certutil -setreg CA\CRLPublicationURLs "65:%windir%\system32\CertSrv\CertEnroll\%%3%%8%%9.crl\n65:F:\inetpub\wwwroot\certdata\%%3%%8%%9.crl\n6:http://cdp.chemistry.ohio-state.edu/Certdata/%%3%%8%%9.crl\n6:http://ca1.chemistry.ohio-state.edu/Certdata/%%3%%8%%9.crl\n6:http://ca2.chemistry.ohio-state.edu/Certdata/%%3%%8%%9.crl"

REM Apply the required AIA Extension URLs
certutil -setreg CA\CACertPublicationURLs  "1:%windir%\system32\CertSrv\CertEnroll\%%1_%%3%%4.crt\n1:F:\inetpub\wwwroot\certdata\%%1_%%3%%4.crt\n2:http://aia.chemistry.ohio-state.edu/CertData/%%1_%%3%%4.crt\n2:http://ca1.chemistry.ohio-state.edu/CertData/%%1_%%3%%4.crt\n2:http://ca2.chemistry.ohio-state.edu/CertData/%%1_%%3%%4.crt\n32:http://%%1/ocsp"

rem Enable all auditing events for the Issuing CA
certutil -setreg CA\AuditFilter 127

rem  Enable discrete signatures in issued certificates
Certutil –setreg CA\csp\DiscreteSignatureAlgorithm 1
 
rem Set Maximum Validity Period for Issued Certificates
certutil -setreg CA\ValidityPeriodUnits 5
certutil -setreg CA\ValidityPeriod "Years"

rem Restart Certificate Services
net stop certsvc
net start certsvc