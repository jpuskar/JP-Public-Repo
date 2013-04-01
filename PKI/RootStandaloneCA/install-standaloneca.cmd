if not exist C:\db-cert mkdir C:\db-cert
if not exist C:\log-cert mkdir C:\log-cert

copy /y capolicy.inf %windir%

PowerShell -ExecutionPolicy bypass -file .\SetupCA-RootCA.ps1

REM Declare Configuration NC
certutil -setreg CA\DSConfigDN CN=Configuration,DC=chemistry,DC=ohio-state,DC=edu

REM Define CRL Publication Intervals
certutil -setreg CA\CRLPeriodUnits 1
certutil -setreg CA\CRLPeriod "Years"
certutil -setreg CA\CRLDeltaPeriodUnits 0
certutil -setreg CA\CRLDeltaPeriod "Days"
certutil -setreg CA\CRLOverlapPeriod "Months"
certutil -setreg CA\CRLOverlapUnits 1

REM Apply the required CDP Extension URLs
certutil -setreg CA\CRLPublicationURLs "1:%windir%\system32\CertSrv\CertEnroll\%%3%%8%%9.crl\n2:http://cdp.chemistry.ohio-state.edu/Certdata/%%3%%8%%9.crl\n2:http://ca1.chemistry.ohio-state.edu/Certdata/%%3%%8%%9.crl\n2:http://ca2.chemistry.ohio-state.edu/Certdata/%%3%%8%%9.crl"

REM Apply the required AIA Extension URLs
certutil -setreg CA\CACertPublicationURLs  "1:%windir%\system32\CertSrv\CertEnroll\%%1_%%3%%4.crt\n2:http://aia.chemistry.ohio-state.edu/CertData/%%1_%%3%%4.crt\n2:http://ca1.chemistry.ohio-state.edu/CertData/%%1_%%3%%4.crt\n2:http://ca2.chemistry.ohio-state.edu/CertData/%%1_%%3%%4.crt"

1REM Enable all auditing events for the Root CA
certutil -setreg CA\AuditFilter 127

REM Set Validity Period for Issued Certificates
certutil -setreg CA\ValidityPeriodUnits 10
certutil -setreg CA\ValidityPeriod "Years"

REM Enable discrete signatures in subordinate CA certificates
Certutil -setreg CA\csp\DiscreteSignatureAlgorithm 1

REM Restart Certificate Services
net stop certsvc
net start certsvc