# PowerShell script to create a Hyper-V VM for code development (including nested virtualization and MAC address spoofing)
#
# NOTE; The commands in this script must be executed by a user that has the "Hyper-V Operator" role, or Administrator role.
#

$VMName = "Development"
$Cores = 3
$MemoryStartupBytes = 8GB
$VHDSizeBytes = 20GB
$VMPath = "C:\Hyper-V\VMs"  # Change this to your desired VM path
$VHDPath = "$VMPath\$VMName\Virtual Hard Disks\$VMName.vhdx"
$ISOPath = "C:\Path\To\Your\ISO\file.iso"  # Change this to your ISO file path

# Create a new virtual machine
New-VM -Name $VMName -Path $VMPath -Generation 2 -MemoryStartupBytes $MemoryStartupBytes
# Enable nested virtualization
# Make sure to enable the kvm_{intel,amd} kernel modules, and configure KVM for nested virtualization.
# WARN; `cat /sys/module/{kvm,amd}_intel/parameters/nested` must print 'Y'
Set-VMProcessor -VMName $VMName -ExposeVirtualizationExtensions $true -Count $Cores -MaximumCount $Count
# Enable MAC address spoofing so the nested VM's can have their own MAC
Set-VMNetworkAdapter -VMName $VMName -MacAddressSpoofing On

# Attach a new virtual hard disk to the VM
New-VHD -Path $VHDPath -SizeBytes $VHDSizeBytes -Dynamic
Add-VMHardDiskDrive -VMName $VMName -Path $VHDPath

# Set boot order to boot from ISO
Set-VMFirmware -VMName $VMName -FirstBootDevice (Get-VMDvdDrive -VMName $VMName)

# Attach the ISO to the VM
Add-VMDvdDrive -VMName $VMName -Path $ISOPath

# Start the VM
Start-VM -Name $VMName

# Print success message
Write-Host "Hyper-V VM '$VMName' created successfully with nested virtualization and MAC address spoofing enabled."