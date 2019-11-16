Function Get-SQLServices{
    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline,ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [String]$ComputerName
    )
    Process{
        Write-Verbose "$ComputerName - Retrieving SQL Services status..."
        $Property = @('State','ServiceName','DisplayName','ServiceType','InstanceName','StartMode','StartName')
        Get-DbaService -ComputerName $ComputerName | Select-Object -Property $Property
    }
}

Function Stop-SQLServices{
    [CmdletBinding()]
    Param(
        [Parameter()][ValidateNotNullOrEmpty()]
        [String]$ComputerName, 
        [Switch]$Wait  
    )
    Process{
        Write-Verbose "Loading SQL Management Object..."
        If ([Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")){            
            [void][System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO')
            [void][Reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlWmiManagement")
            
            $SqlServer = New-Object Microsoft.SqlServer.Management.Smo.Server($ComputerName)
            $SqlConf = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer $SqlServer.ComputerNamePhysicalNetBIOS            
        }    
        Else {         
            Write-Warning "Please install MS SQL Management Studio"   
            [Environment]::Exit(1)
        }

        Write-Verbose "$ComputerName - Stopping SQL Services..."
        $SqlConf.Services | Where-Object{$_.ServiceState -eq 'Running'} | ForEach-Object{$_.stop()}    
        If ($Wait){
            $SrvName = $SqlConf.Services | Where-Object{$_.ServiceState -eq 'Running'} | Select-Object -ExpandProperty Name
            Do {
                [Bool]$IsRunning = (($SrvName | Get-Service -ComputerName $ComputerName | Where-Object{$_.Status -eq "Running"}).count -gt 0)
                Write-Verbose "Services being stopped? $IsRunning"
                Start-Sleep 3
            }While($IsRunning)
        }
    }        
}

Function Test-ServiceStatus{
    #Is the service running
    [CmdletBinding()]
    [OutputType([bool])]
    Param(
        [Parameter()][ValidateNotNullOrEmpty()]
        [String]$ComputerName,
        [ValidateNotNullOrEmpty()]
        [String]$Name,
        [ValidateSet('Running', 'Stopped', 'Paused')]
        [String]$Status = 'Running'
    )
    Process{
        return ($Status -eq (Get-Service -Name $Name -ComputerName $ComputerName -ErrorAction 'SilentlyContinue').Status)
    }
}

Function Start-SQLServices{
    [CmdletBinding()]
    Param(
        [Parameter()][ValidateNotNullOrEmpty()]
        [String]$ComputerName,
        [System.IO.FileInfo]$CsvPath = "\\FileServer\Reports\CSV",
        [System.IO.FileInfo]$MasterList = '\\FileServer\reports\Scripts\MasterList.psd1'
    )
    Begin {
        $CsvFile = "$CSVPath\$ComputerName.csv"
        If (Test-Path $CsvFile){
            $Csv = Import-Csv $CsvFile
            #$Csv
            $CsvRunningSrv = ($Csv | Where-Object{$_.ServiceState -eq "Running"} | Select-Object -ExpandProperty Name)
            $CsvRunningSrv | Get-Service -ComputerName $ComputerName | Start-Service
        }
        Elseif(Test-Path $MasterList){
            Write-Warning "Unable to find the Services CSV file: $CsvFile"
            $ServiceList = Import-PowerShellDataFile $MasterList
            If ($null -ne $($ServiceList.$ComputerName.Running.Name)){
                $ServiceList.$ComputerName.Running.Name | Get-Service -ComputerName | Start-Service
            }
            Else {
                Write-Warning "Unable to obtain running services from the Master Service List for $ComputerName!"
            }
        }
        Else{
            Write-Warning "Please manually restart the Sql services or reboot the server!"
        }
    }
    Process {
        If ($CsvRunningSrv){
            Write-Verbose "Starting services according to running state in CSV..."       
            $CsvRunningSrv | Get-Service -ComputerName $ComputerName | Start-Service
        } 
        Else{            
            Write-Warning "Unable to find the CSV file with Services info"
            Write-Warning "The start-up process for services is ignored."
            Write-Warning "Please reboot the server, if the problem persists."
        }
    }
}
