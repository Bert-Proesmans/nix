# PowerShell script to create a Hyper-V VM for code development (including nested virtualization and MAC address spoofing)
#
# NOTE; The commands in this script must be executed by a user that has the "Hyper-V Operator" role, or Administrator role.
#

$VMName = "Development"
$Cores = [int] [Math]::Truncate( $(Get-WmiObject Win32_Processor | Select-Object -ExpandProperty NumberOfCores) / 2)
# NOTE; Yes, the values below are not quoted! Powershell automatically converts the suffixes,
# and the variable will end up being an integer holding the total number of bytes.
$MemoryStartupBytes = [long] [Math]::Truncate( $((Get-WmiObject Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum) /2)
$VHDSizeBytes = 20GB
$VMPath = "C:\ProgramData\Microsoft\Windows\Hyper-V"  # Change this to your desired VM path
$VHDPath = "C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\$VMName.vhdx"

# Create a dedicated switch for development
# WARN; There is no DHCP server running on this interface!
New-VMSwitch -Name "Development" -SwitchType Internal
# NOTE; VM's must statically assign their own IP within the range 172.27.224.2-172.27.224.254
New-NetIPAddress -InterfaceAlias "vEthernet (Development)" -IPAddress "172.27.224.1" -PrefixLength 24
# NOTE; VM's must statically assign their own IP within the range fde0:5584:ba8e::2-fde0:5584:ba8e:0:ffff:ffff:ffff:ffff
# SLAAC is allowed ofcourse
New-NetIPAddress -InterfaceAlias "vEthernet (Development)" -IPAddress "fde0:5584:ba8e::1" -PrefixLength 64
# NOTE; Private security zone allows pings etc
Set-NetConnectionProfile -InterfaceAlias "vEthernet (Development)" -NetworkCategory "Private"

# NAT4 between VM and upstream internet
New-NetNat -Name "DevelopmentNAT" -InternalIPInterfaceAddressPrefix "172.27.224.0/24"
# NAT6 doesn't exist on Windows

# Create a new virtual machine
New-VM -Name $VMName -Path $VMPath -Generation 2 -MemoryStartupBytes $MemoryStartupBytes -SwitchName "Development"
# Enable nested virtualization
# Make sure to enable the kvm_{intel,amd} kernel modules, and configure KVM for nested virtualization.
# WARN; `cat /sys/module/{kvm,amd}_intel/parameters/nested` must print 'Y'
Set-VMProcessor -VMName $VMName -ExposeVirtualizationExtensions $true
Set-VMProcessor -VMName $VMName -Count $Cores -Reserve 10 -Maximum 75
Set-VMFirmware -VMName $VMName -EnableSecureBoot 'Off'

# Enable MAC address spoofing so the nested VM's can have their own MAC
Set-VMNetworkAdapter -VMName $VMName -MacAddressSpoofing 'On' -DhcpGuard 'On'

# Attach a new virtual hard disk to the VM
New-VHD -Path $VHDPath -SizeBytes $VHDSizeBytes -Dynamic
Add-VMHardDiskDrive -VMName $VMName -Path $VHDPath

# Attach the ISO to the VM
Add-VMDvdDrive -VMName $VMName

# Set boot order to boot from ISO first, followed by hard drive
Set-VMFirmware -VMName $VMName -FirstBootDevice (Get-VMHardDiskDrive -VMName $VMName)
Set-VMFirmware -VMName $VMName -FirstBootDevice (Get-VMDvdDrive -VMName $VMName)

# Start the VM
Start-VM -Name $VMName

# Print success message
Write-Host "Hyper-V VM '$VMName' created successfully with nested virtualization and MAC address spoofing enabled."