# PowerShell script to create a Hyper-V VM for code development (including nested virtualization and MAC address spoofing)
#
# NOTE; The commands in this script must be executed by a user that has the "Hyper-V Operator" role, or Administrator role.
#

$VMName = "Development"
$Cores = 3
# NOTE; Yes, the values below are not quoted! Powershell automatically converts the suffixes,
# and the variable will end up being an integer holding the total number of bytes.
$MemoryStartupBytes = 8GB
$VHDSizeBytes = 20GB
$VMPath = "C:\ProgramData\Microsoft\Windows\Hyper-V"  # Change this to your desired VM path
$VHDPath = "C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\$VMName.vhdx"
$ISOPath = "C:\Path\To\Your\ISO\file.iso"  # Change this to your ISO file path

# Create a new virtual machine
New-VM -Name $VMName -Path $VMPath -Generation 2 -MemoryStartupBytes $MemoryStartupBytes -SwitchName "Default Switch"
# Enable nested virtualization
# Make sure to enable the kvm_{intel,amd} kernel modules, and configure KVM for nested virtualization.
# WARN; `cat /sys/module/{kvm,amd}_intel/parameters/nested` must print 'Y'
Set-VMProcessor -VMName $VMName -ExposeVirtualizationExtensions $true
Set-VMProcessor -VMName $VMName -Count $Cores -Reserve 10 -Maximum 75
Set-VMFirmware -VMName $VMName -EnableSecureBoot 'Off'

# Add second adapter for host<->vm connectivity
# ERROR; If the commands below don't work for you you're shit out of luck and that's the state of Hyper-V where
# seemingly simple shit goes down so bad in a way that is so complex that even the "how" you should figure your shit
# out is made impossible because the debugging commands also don't work. It's all built on sheit.
New-VMSwitch -Name "Static Net" -SwitchType Internal
Add-VMNetworkAdapter -VMName $VMName -SwitchName "Static Net" -Name "Static Net"
New-NetIPAddress -InterfaceAlias "vEthernet (Static Net)" -IPAddress "169.254.245.1" -PrefixLength 24
New-NetIPAddress -InterfaceAlias "vEthernet (Static Net)" -IPAddress "fe80::1" -PrefixLength 64

# Enable MAC address spoofing so the nested VM's can have their own MAC
# WARN; This applies to all VM adapters!
Set-VMNetworkAdapter -VMName $VMName -MacAddressSpoofing 'On' -DhcpGuard 'On'

# Attach a new virtual hard disk to the VM
New-VHD -Path $VHDPath -SizeBytes $VHDSizeBytes -Dynamic
Add-VMHardDiskDrive -VMName $VMName -Path $VHDPath

# Attach the ISO to the VM
Add-VMDvdDrive -VMName $VMName -Path $ISOPath
# Set boot order to boot from ISO
Set-VMFirmware -VMName $VMName -FirstBootDevice (Get-VMDvdDrive -VMName $VMName)

# Start the VM
Start-VM -Name $VMName

# Print success message
Write-Host "Hyper-V VM '$VMName' created successfully with nested virtualization and MAC address spoofing enabled."