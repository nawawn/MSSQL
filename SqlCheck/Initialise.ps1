<#
$Manifest = @{
    Path = '.\BMSqlCheck\BMSqlCheck.psd1'
    RootModule = 'BMSqlCheck.psm1'
    Author     = 'Naw Awn'
    CompanyName = 'The British Museum'
    Description = 'MS SQL Server preflight and postflight check before and after the Windows update'
    RequiredModules = 'DbaTools'
    ScriptsToProcess = Initialise.ps1
}

New-ModuleManifest @Manifest
#>

#Initialise BMSqlCheck module
If(-Not(Get-PackageProvider).Where{$_.Name -eq 'NuGet'}){   
    Write-Verbose "NuGet Package Manager Not found! Installing it now..."
    Install-PackageProvider -Name "NuGet" -Force -Confirm:$false
}

If(-Not(Get-Module -ListAvailable -Name 'DbaTools')){
    Write-Verbose "DbaTools Module Not Found! Installing it now..."
    If (-Not(Get-PSRepository -Name PSGallery)){
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    }
    Install-Module -Name DbaTools -Force
}
