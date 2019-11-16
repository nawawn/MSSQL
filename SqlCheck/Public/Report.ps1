Function Get-SQLServerHtmlReport{
    Param(
        [Parameter()][ValidateNotNullOrEmpty()]
        [String]$ComputerName,
        [System.IO.FileInfo]$OutputPath = "\\FileServer\Reports\PreFlightChecks"
    )
    Begin{
        $Head = @"
        <style type="text/css">
            body {font-size:10pt; font-family:Tahoma}    
            tr:nth-child(even) {background: #f8f8f8}
            tr:nth-child(odd) {background: #dae5f4}    
        </style>   
"@
    }
    Process{
        #Generate the report
        $CInfo   = Get-DriveSpace -ComputerName $ComputerName | ConvertTo-Html -Fragment -PreContent '<h4>Drive Details</h4>' -PostContent '<br/>' | Out-String
        $SqlSer  = Get-SQLServices -ComputerName $ComputerName | ConvertTo-Html -Fragment -PreContent '<h4>SQL Services Details</h4>' -PostContent '<br/>' | Out-String
        $DbState = Get-DbState -ComputerName $ComputerName | ConvertTo-Html -Fragment -PreContent '<h4>SQL Database State</h4>' -PostContent '<br/>' | Out-String
        $DbConns = Get-DbSession -ComputerName $ComputerName | ConvertTo-Html -Fragment -PreContent '<h4>SQL Database Connection Summary</h4>' -PostContent '<br/>' | Out-String
        $SqlVer  = Get-SQLServerVer -ComputerName $ComputerName | ConvertTo-Html -Fragment -PreContent '<h4>SQL Server Version</h4>' -PostContent '<br/>' | Out-String
        $DBInfo  = Get-DbBackupInfo -ComputerName $ComputerName | ConvertTo-Html -Fragment -PreContent '<h4>Database Backup Info</h4>' -PostContent '<br/>' | Out-String
        $DBJob   = Get-SQLJobActivity -ComputerName $ComputerName | ConvertTo-Html -Fragment -PreContent '<h4>SQL Job Activities</h4>' -PostContent '<br/>' | Out-String
        $SqlLog  = Get-SQLLog -ComputerName $ComputerName | ConvertTo-Html -Fragment -PreContent '<h4>SQL Log from today</h4>' -PostContent '<br/>' | Out-String
        $SqlErr  = Get-DbErrorLog -ComputerName $ComputerName | ConvertTo-Html -Fragment -PreContent '<h4>SQL Error Log from today</h4>' -PostContent '<br/>' | Out-String

        Write-Verbose "Generating SQL Server HTML Report..."
        If (Test-Path $OutputPath){
            ConvertTo-Html -Head $Head -Body "$CInfo $SqlSer $DbState $DbConns $SqlVer $DBInfo $DBJob $SqlLog $SqlErr" -Title "SQL Server Pre-flight Check Report" | 
                Out-File "$OutputPath\$ComputerName-Pre.html"
        }
        Else {  
            $OutFile =  [Environment]::GetFolderPath("Desktop")
            ConvertTo-Html -Head $Head -Body "$CInfo $SqlSer $DbState $DbConns $SqlVer $DBInfo $DBJob $SqlLog $SqlErr" -Title "SQL Server Pre-flight Check Report" | 
                Out-File "$OutFile\$ComputerName-Pre.html" -Force
        }
    }
}

Function Get-SQLServiceCsvReport{
    Param(
        [Parameter(ValueFromPipeline,ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [String]$ComputerName,
        [System.IO.FileInfo]$OutputPath = "\\FileServer\Reports\CSV"
    )
    Process{
        Write-Verbose "Generating CSV for SQL services..."
        Get-SQLServices -ComputerName $ComputerName | Export-Csv -Path "$OutputPath\$ComputerName.csv" -NoTypeInformation
    }    
}

Function Get-ServicePsd1{
    Param(
            [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName,Position=0)]
            [String]$ComputerName
        )
    Begin{
        $begin = '@{'
        $end = '}'
        Write-Output $begin
    }
    Process{
        $ServiceList = (Get-DbaService -ComputerName $ComputerName) 
        [String]$Running = (($ServiceList.where{$_.State -eq 'Running'}).ServiceName) | Foreach-Object{"'"+ "$_" + "',"}
        [String]$Stopped = (($ServiceList.where{$_.State -eq 'Stopped'}).ServiceName) | Foreach-Object{"'"+ "$_" + "',"}
        Write-Output "`'$ComputerName`' = @{"        
        Write-Output "`t Running = @{"
        Write-Output "`t`t Name = $((-Join $Running).TrimEnd(','))"
        Write-Output "`t }"
        Write-Output "`t Stopped = @{"
        Write-Output "`t`t Name = $((-Join $Stopped).TrimEnd(','))"
        Write-Output "`t }"
        Write-Output "}"              
    }
    End{
        Write-Output $end
    }
}