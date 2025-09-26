# =========================
# Classes
# =========================

# ----- ESXi Host class -----
class VsHost {
    [string] $Name
    [string] $PowerState
    [string] $Manufacturer
    [string] $Model
    [string] $CPUType
    [int]    $CPUs
    [string] $MemoryGB
    [string] $Version
    [string] $Build
    [string] $Timezone
    [System.Collections.Generic.List[string]] $DataStores = [System.Collections.Generic.List[string]]::new()
    VsHost() {}
}

# ----- VM class -----
class VsVirtualMachine {
    [string] $Name
    [string] $PowerState
    [int]    $CPUs
    [string] $MemoryGB
    [string] $CurrentHost
    [int]    $SnapshotCount
    [string] $SnapshotSizeGB
    [string] $UsedSpaceGB
    [string] $ProvisionedSpaceGB
    [string] $PercentFree
    [string] $CreationDate
    [string] $Notes
    [string] $HomeDatastorePath
    [System.Collections.Generic.List[string]] $DiskPaths = [System.Collections.Generic.List[string]]::new()
    VsVirtualMachine() {}
}

# ----- Snapshot class -----
class VsSnapshot {
    [string] $VM
    [string] $SizeGB
    [string] $Created
    [string] $PowerState
    [bool]   $IsCurrent
    [bool]   $Quiesced
    VsSnapshot() {}
}

# ----- Datastore class -----
class VsDataStore {
    [string] $Name
    [string] $State
    [bool]   $Accessible
    [string] $FreeSpaceGB
    [string] $CapacityGB
    [string] $PercentFree
    [string] $Type
    [string] $FSVersion
    VsDataStore() {}
}

# ----- Cluster class -----
class VsCluster {
    [string] $Name
    [bool]   $HAEnabld
    [bool]   $DRSEnabled
    [string] $DRSAutomationLevel
    [bool]   $VsanEnabled
    [string] $VsanDiskClaimMode
    [string] $EVCMode

    [System.Collections.Generic.List[VsHost]]            $Hosts           = [System.Collections.Generic.List[VsHost]]::new()
    [System.Collections.Generic.List[VsVirtualMachine]]  $VirtualMachines = [System.Collections.Generic.List[VsVirtualMachine]]::new()
    [System.Collections.Generic.List[VsSnapshot]]        $Snapshots       = [System.Collections.Generic.List[VsSnapshot]]::new()

    VsCluster() {}
}

# ----- Datacenter class -----
class VsDataCenter {
    [string] $Name
    [System.Collections.Generic.List[VsCluster]] $Clusters = [System.Collections.Generic.List[VsCluster]]::new()
    VsDataCenter([string]$name) { $this.Name = $name }
}

# ----- vCenter connection class -----
class VsVCenter {
    [string] $Name
    [int]    $Port
    [bool]   $Connected
    [string] $Version
    [string] $Build
    [string] $ConnectedAs
    [string] $SessionId

    [System.Collections.Generic.List[VsDataCenter]] $DataCenters = [System.Collections.Generic.List[VsDataCenter]]::new()
    [System.Collections.Generic.List[VsDataStore]]  $DataStores  = [System.Collections.Generic.List[VsDataStore]]::new()

    VsVCenter() {}

    static [VsVCenter] FromVIServer([object] $vi) {
        $o = [VsVCenter]::new()
        $o.Name        = $vi.Name
        $o.Port        = [int]$vi.Port
        $o.Connected   = [bool]$vi.IsConnected
        $o.Version     = [string]$vi.Version
        $o.Build       = [string]$vi.Build
        $o.ConnectedAs = [string]$vi.User
        $o.SessionId   = [string]$vi.SessionId
        return $o
    }

    [void] LoadDataCenters() {
        $dcObjs = Get-Datacenter -Server $this.Name -ErrorAction SilentlyContinue
        foreach ($dcObj in $dcObjs) {
            if (-not ($this.DataCenters | Where-Object { $_.Name -eq $dcObj.Name })) {
                [void]$this.DataCenters.Add([VsDataCenter]::new($dcObj.Name))
            }
        }
    }

    [void] LoadClusters() {
        foreach ($dc in $this.DataCenters) {
            $dcObj = Get-Datacenter -Server $this.Name -Name $dc.Name -ErrorAction SilentlyContinue
            if (-not $dcObj) { continue }

            $clObjs = Get-Cluster -Server $this.Name -Location $dcObj -ErrorAction SilentlyContinue
            foreach ($cl in $clObjs) {
                if (-not ($dc.Clusters | Where-Object { $_.Name -eq $cl.Name })) {
                    $cluster = [VsCluster]::new()
                    $cluster.Name               = $cl.Name
                    $cluster.HAEnabld           = [bool]$cl.HAEnabled
                    $cluster.DRSEnabled         = [bool]$cl.DrsEnabled
                    $cluster.DRSAutomationLevel = [string]$cl.DrsAutomationLevel
                    $cluster.VsanEnabled        = [bool]$cl.VsanEnabled
                    $cluster.VsanDiskClaimMode  = [string]$cl.VsanDiskClaimMode
                    $cluster.EVCMode            = [string]$cl.EVCMode
                    [void]$dc.Clusters.Add($cluster)
                }
            }
        }
    }

    [void] LoadHosts() {
        foreach ($dc in $this.DataCenters) {
            $dcObj = Get-Datacenter -Server $this.Name -Name $dc.Name -ErrorAction SilentlyContinue
            if (-not $dcObj) { continue }

            foreach ($cl in $dc.Clusters) {
                $clObj = Get-Cluster -Server $this.Name -Name $cl.Name -Location $dcObj -ErrorAction SilentlyContinue
                if (-not $clObj) { continue }

                $hosts = Get-VMHost -Server $this.Name -Location $clObj -ErrorAction SilentlyContinue
                foreach ($h in $hosts) {
                    if (-not ($cl.Hosts | Where-Object { $_.Name -eq $h.Name })) {
                        $vh = [VsHost]::new()
                        $vh.Name         = $h.Name
                        $vh.PowerState   = [string]$h.PowerState
                        $vh.Manufacturer = [string]$h.Manufacturer
                        $vh.Model        = [string]$h.Model
                        $vh.CPUType      = ([string]$h.ProcessorType) -replace '\(R\)',''
                        $vh.CPUs         = [int]$h.NumCpu
                        $vh.MemoryGB     = ('{0:N0}' -f [double]$h.MemoryTotalGB)
                        $vh.Version      = [string]$h.Version
                        $vh.Build        = [string]$h.Build
                        $vh.Timezone     = ($h | Select-Object -ExpandProperty TimeZone -ErrorAction SilentlyContinue)
                        if (-not $vh.Timezone) {
                            $tz = ($h | Select-Object -ExpandProperty Timezone -ErrorAction SilentlyContinue)
                            if ($tz) { $vh.Timezone = [string]$tz } else { $vh.Timezone = '' }
                        }

                        # Host-level datastores
                        $hostDS = $h | Get-Datastore -ErrorAction SilentlyContinue
                        foreach ($ds in $hostDS) {
                            if (-not $vh.DataStores.Contains($ds.Name)) {
                                [void]$vh.DataStores.Add([string]$ds.Name)
                            }
                        }

                        [void]$cl.Hosts.Add($vh)
                    }
                }
            }
        }
    }

    [void] LoadSnapshots() {
        foreach ($dc in $this.DataCenters) {
            $dcObj = Get-Datacenter -Server $this.Name -Name $dc.Name -ErrorAction SilentlyContinue
            if (-not $dcObj) { continue }

            foreach ($cl in $dc.Clusters) {
                $clObj = Get-Cluster -Server $this.Name -Name $cl.Name -Location $dcObj -ErrorAction SilentlyContinue
                if (-not $clObj) { continue }

                $vmObjs = Get-VM -Server $this.Name -Location $clObj -ErrorAction SilentlyContinue
                foreach ($vmObj in $vmObjs) {
                    try {
                        $snaps = $vmObj | Get-Snapshot -ErrorAction Stop
                    } catch { continue }

                    foreach ($s in $snaps) {
                        $snap = [VsSnapshot]::new()
                        $snap.VM         = [string]$vmObj.Name
                        $snap.SizeGB     = ('{0:N2}' -f [double]$s.SizeGB)
                        $snap.Created    = [string]$s.Created
                        $snap.PowerState = [string]$s.PowerState
                        $snap.IsCurrent  = [bool]$s.IsCurrent
                        $snap.Quiesced   = [bool]$s.Quiesced
                        $cl.Snapshots.Add($snap) | Out-Null
                    }
                }
            }
        }
    }

    [void] LoadVirtualMachines() {
        foreach ($dc in $this.DataCenters) {
            $dcObj = Get-Datacenter -Server $this.Name -Name $dc.Name -ErrorAction SilentlyContinue
            if (-not $dcObj) { continue }

            foreach ($cl in $dc.Clusters) {
                $clObj = Get-Cluster -Server $this.Name -Name $cl.Name -Location $dcObj -ErrorAction SilentlyContinue
                if (-not $clObj) { continue }

                $vmObjs = Get-VM -Server $this.Name -Location $clObj -ErrorAction SilentlyContinue
                foreach ($vmObj in $vmObjs) {
                    if (-not ($cl.VirtualMachines | Where-Object { $_.Name -eq $vmObj.Name })) {
                        $vm = [VsVirtualMachine]::new()
                        $vm.Name               = $vmObj.Name
                        $vm.PowerState         = [string]$vmObj.PowerState
                        $vm.CPUs               = [int]$vmObj.NumCpu
                        $vm.MemoryGB           = ('{0:N0}' -f [double]$vmObj.MemoryGB)
                        $vm.CurrentHost        = if ($vmObj.VMHost) { [string]$vmObj.VMHost.Name } else { '' }
                        $vm.UsedSpaceGB        = ('{0:N2}' -f [double]$vmObj.UsedSpaceGB)
                        $vm.ProvisionedSpaceGB = ('{0:N2}' -f [double]$vmObj.ProvisionedSpaceGB)

                        $used = [double]$vmObj.UsedSpaceGB
                        $prov = [double]$vmObj.ProvisionedSpaceGB
                        if ($prov -gt 0) { $vm.PercentFree = ('{0:P2}' -f ($used / $prov)) } else { $vm.PercentFree = '' }

                        $create = $vmObj | Select-Object -ExpandProperty CreateDate -ErrorAction SilentlyContinue
                        if (-not $create) { $create = $vmObj.ExtensionData.Config.CreateDate }
                        $vm.CreationDate = if ($create) { [string]$create } else { '' }
                        $vm.Notes = [string]$vmObj.Notes

                        # Snapshot aggregation
                        $vmSnaps = $cl.Snapshots | Where-Object { $_.VM -eq $vmObj.Name }
                        $vm.SnapshotCount = ($vmSnaps | Measure-Object).Count
                        $totalSize = ($vmSnaps | Measure-Object -Property SizeGB -Sum).Sum
                        $vm.SnapshotSizeGB = if ($totalSize) { '{0:N2}' -f [double]$totalSize } else { '0.00' }

                        # Datastore paths
                        $vm.HomeDatastorePath = [string]$vmObj.ExtensionData.Config.Files.VmPathName
                        $vm.DiskPaths.Clear()
                        $hardDisks = $vmObj | Get-HardDisk -ErrorAction SilentlyContinue
                        foreach ($hd in $hardDisks) {
                            if ($hd.Filename) { [void]$vm.DiskPaths.Add([string]$hd.Filename) }
                        }

                        $cl.VirtualMachines.Add($vm) | Out-Null
                    }
                }
            }
        }
    }

    [void] LoadDataStores() {
        $dsObjs = Get-Datastore -Server $this.Name -ErrorAction SilentlyContinue
        foreach ($ds in $dsObjs) {
            if (-not ($this.DataStores | Where-Object { $_.Name -eq $ds.Name })) {
                $dso = [VsDataStore]::new()
                $dso.Name        = $ds.Name
                $dso.State       = [string]$ds.State
                $dso.Accessible  = [bool]$ds.ExtensionData.Summary.Accessible
                $dso.FreeSpaceGB = ('{0:N2}' -f ($ds.FreeSpaceGB))
                $dso.CapacityGB  = ('{0:N2}' -f ($ds.CapacityGB))
                if ($ds.CapacityGB -gt 0) {
                    $dso.PercentFree = ('{0:P2}' -f ($ds.FreeSpaceGB / $ds.CapacityGB))
                } else { $dso.PercentFree = '' }
                $dso.Type        = [string]$ds.Type
                $dso.FSVersion   = [string]$ds.FileSystemVersion
                $this.DataStores.Add($dso) | Out-Null
            }
        }
    }
}

# =========================
# Driver code
# =========================

$names = @('vcsa01.domain.tld','vcsa02.domain.tld')
$viServers = Get-VIServer -Server $names
$vcenters = New-Object 'System.Collections.Generic.List[VsVCenter]'

foreach ($vi in $viServers) {
    $obj = [VsVCenter]::FromVIServer($vi)
    $obj.LoadDataCenters()
    $obj.LoadClusters()
    $obj.LoadHosts()
    $obj.LoadSnapshots()
    $obj.LoadVirtualMachines()
    $obj.LoadDataStores()
    $vcenters.Add($obj) | Out-Null
}
