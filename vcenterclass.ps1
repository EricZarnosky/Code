# ----- Cluster class -----
class VsCluster {
    [string] $Name
    [bool]   $HAEnabld
    [bool]   $DRSEnabled
    [string] $DRSAutomationLevel
    [bool]   $VsanEnabled
    [string] $VsanDiskClaimMode
    [string] $EVCMode

    # NEW: Hosts list under each cluster
    [System.Collections.Generic.List[VsHost]] $Hosts = [System.Collections.Generic.List[VsHost]]::new()

    VsCluster() {}
}

# ----- Datacenter class -----
class VsDataCenter {
    [string] $Name
    [System.Collections.Generic.List[VsCluster]] $Clusters = [System.Collections.Generic.List[VsCluster]]::new()
    VsDataCenter([string]$name) { $this.Name = $name }
}

# NEW: ESXi Host class
class VsHost {
    [string] $Parent         # cluster name
    [string] $Name
    [string] $PowerState
    [string] $Manufacturer
    [string] $Model
    [string] $CPUType        # ProcessorType, with (R) stripped
    [int]    $CPUs           # NumCPU
    [string] $MemoryGB       # MemoryTotalGB formatted "{0:N0}"
    [string] $Version
    [string] $Build
    [string] $Timezone
    VsHost() {}
}

# ----- vCenter class -----
class VsVCenter {
    [string] $Name
    [int]    $Port
    [bool]   $Connected
    [string] $Version
    [string] $Build
    [string] $ConnectedAs
    [string] $SessionId

    [System.Collections.Generic.List[VsDataCenter]] $DataCenters = [System.Collections.Generic.List[VsDataCenter]]::new()

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

    # NEW: Populate ESXi hosts under each cluster
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
                        $vh.Parent      = $cl.Name
                        $vh.Name        = $h.Name
                        $vh.PowerState  = [string]$h.PowerState
                        $vh.Manufacturer= [string]$h.Manufacturer
                        $vh.Model       = [string]$h.Model
                        $vh.CPUType     = ([string]$h.ProcessorType) -replace '\(R\)',''  # strip (R)
                        $vh.CPUs        = [int]$h.NumCpu
                        $vh.MemoryGB    = ('{0:N0}' -f [double]$h.MemoryTotalGB)
                        $vh.Version     = [string]$h.Version
                        $vh.Build       = [string]$h.Build
                        # Some builds expose TimeZone or Timezone; try both safely
                        $vh.Timezone    = ($h | Select-Object -ExpandProperty TimeZone -ErrorAction SilentlyContinue)
                        if (-not $vh.Timezone) {
                            $tz = ($h | Select-Object -ExpandProperty Timezone -ErrorAction SilentlyContinue)
                            if ($tz) { $vh.Timezone = [string]$tz } else { $vh.Timezone = '' }
                        }
                        [void]$cl.Hosts.Add($vh)
                    }
                }
            }
        }
    }
}

# -------- Driver code --------

# Example: list of vCenter names you are connected to
$names = @('vcsa01.domain.tld','vcsa02.domain.tld')

# Grab VIServer objects
$viServers = Get-VIServer -Server $names

# Strongly typed list of vCenters
$vcenters = New-Object 'System.Collections.Generic.List[VsVCenter]'

foreach ($vi in $viServers) {
    $obj = [VsVCenter]::FromVIServer($vi)
    $obj.LoadDataCenters()
    $obj.LoadClusters()
    $obj.LoadHosts()     # NEW
    $vcenters.Add($obj) | Out-Null
}

# Quick view: flatten vCenter → DataCenter → Cluster → Host
$vcenters | ForEach-Object {
    $vc = $_
    foreach ($dc in $vc.DataCenters) {
        foreach ($cl in $dc.Clusters) {
            foreach ($h in $cl.Hosts) {
                [pscustomobject]@{
                    vCenter     = $vc.Name
                    DataCenter  = $dc.Name
                    Cluster     = $cl.Name
                    Host        = $h.Name
                    PowerState  = $h.PowerState
                    Manufacturer= $h.Manufacturer
                    Model       = $h.Model
                    CPUType     = $h.CPUType
                    CPUs        = $h.CPUs
                    MemoryGB    = $h.MemoryGB
                    Version     = $h.Version
                    Build       = $h.Build
                    Timezone    = $h.Timezone
                }
            }
        }
    }
} | Format-Table -Auto
