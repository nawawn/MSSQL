### MSSQL
__New-PreflightCheck.ps1__ This script checks a number of things on the SQL server, generates the report in HTML format and creates a csv file with all the SQL services status. It can gracefully stop all the SQL services by using ***-StopService*** switch.

__New-PostflightCheck.ps1__ This script generates the report in HTML and can start all the services stopped by the New-PreflightCheck.ps1 script using ***-StartService*** switch. The script determines which services needed to be run by checking the values in the csv file generated by the preflight check script.