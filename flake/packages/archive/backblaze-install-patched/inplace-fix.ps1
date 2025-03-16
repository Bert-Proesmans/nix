#Requires -Version 5

Add-Type -LiteralPath "C:\WixToolset.Dtf.WindowsInstaller.dll"

$msiPath ="C:\bzinstall.msi"
$finishedMsi = "C:\bzinstall-finished.msi"

Copy-Item -Path $msiPath -Destination $finishedMsi
$updatedDatabase = New-Object WixToolset.Dtf.WindowsInstaller.Database($finishedMsi, [WixToolset.Dtf.WindowsInstaller.DatabaseOpenMode]::Direct)

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
$updatedDatabase.Dispose()

"Custom actions after InstallFiles and InstallFinalize have been removed."