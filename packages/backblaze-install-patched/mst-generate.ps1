#Requires -Version 5

# Run on Windows
# This file produces an MSI Transform file that can be used to apply on top of the backblaze MSI installer.
# I expect this Transform file to be portable across multiple installer versions.

Install-PackageProvider -Force nuget
Set-packageSource -Name nuget.org -NewLocation https://www.nuget.org/api/v2 -Trusted

Install-Package WixToolset.Dtf.WindowsInstaller
Get-ChildItem -Recurse -Filter *.dll -LiteralPath (Join-Path (Split-Path (Get-Package WixToolset.Dtf.WindowsInstaller).Source) lib/netstandard2.0) `
| ForEach-Object { Add-Type -LiteralPath $_.FullName }

$msiPath ="C:\bzinstall.msi"
$transformPath ="C:\bzinstall.mst"
$tempCopy = (New-TemporaryFile).FullName

Copy-Item -Path $msiPath -Destination $tempCopy

$originalDatabase = New-Object WixToolset.Dtf.WindowsInstaller.Database($msiPath, [WixToolset.Dtf.WindowsInstaller.DatabaseOpenMode]::ReadOnly)
$updatedDatabase = New-Object WixToolset.Dtf.WindowsInstaller.Database($tempCopy, [WixToolset.Dtf.WindowsInstaller.DatabaseOpenMode]::Direct)

# ERROR; MSI sql-engine cannot handle more complex SQL strings!
$executeSequenceQuery = @"
SELECT ``Action``, ``Sequence`` FROM ``InstallExecuteSequence``
"@

$qView = $updatedDatabase.OpenView($executeSequenceQuery)
$qView.Execute()
while ($record = $qView.Fetch()) {
    $actionName = $record.GetString(1)
	$sequence = $record.GetInteger(2)
    
    # Remove all custom actions in InstallExecuteSequence after InstallFiles (4000) and InstallFinalize (6600)
    if (
        ($sequence -gt 4000 -and $sequence -lt 4100)`
        -or ($sequence -gt 6600 -and $sequence -lt 6700)`
    ) {
        Write-Host "Removing custom action: $actionName (Sequence: $sequence)"
        $qView.Modify([WixToolset.Dtf.WindowsInstaller.ViewModifyMode]::Delete, $record)
    }
}

$qView.Close()
# EEEGH.. this last step is stubbed by Mono libs :(
if(!($updatedDatabase.GenerateTransform($originalDatabase, $transformPath))) {
	throw "Generation of transform failed!"
}

$updatedDatabase.Dispose()
$originalDatabase.Dispose()

"Custom actions after InstallFiles and InstallFinalize have been removed."