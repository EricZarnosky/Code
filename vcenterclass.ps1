# Define the class
class VsVCenter {
    [string] $Name
    [int]    $Port
    [bool]   $Connected
    [string] $Version
    [string] $Build
    [string] $ConnectedAs
    [string] $SessionId

    # CHANGED: DataCenters now a list of VsDataCenter
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

    # Populate datacenters for this vCenter
    [void] LoadDataCenters() {
        $dcObjs = Get-Datacenter -Server $this.Name -ErrorAction SilentlyContinue
        foreach ($dcObj in $dcObjs) {
            if (-not ($this.DataCenters | Where-Object { $_.Name -eq $dcObj.Name })) {
                [void]$this.DataCenters.Add([VsDataCenter]::new($dcObj.Name))
            }
        }
    }

    # Populate clusters under each datacenter (scoped to this vCenter)
    [void] LoadClusters() {
        foreach ($dc in $this.DataCenters) {
            $dcObj = Get-Datacenter -Server $this.Name -Name $dc.Name -ErrorAction SilentlyContinue
            if (-not $dcObj) { continue }

            $clObjs = Get-Cluster -Server $this.Name -Location $dcObj -ErrorAction SilentlyContinue
            foreach ($cl in $clObjs) {
                if (-not ($dc.Clusters | Where-Object { $_.Name -eq $cl.Name })) {
                    $cluster = [VsCluster]::new()
                    $cluster.Name               = $cl.Name
                    # CHANGED: HAEnabled instead of NAEnabld
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
}

# CHANGED: renamed VsDatacenter → VsDataCenter
class VsDataCenter {
    [string] Name
    [System.Collections.Generic.List[VsCluster]] Clusters = [System.Collections.Generic.List[VsCluster]]::new()
    VsDataCenter([string]$name) { $this.Name = $name }
}

# Cluster class
class VsCluster {
    [string] Name
    [bool]   HAEnabld            # CHANGED: HAEnabld instead of NAEnabld
    [bool]   DRSEnabled
    [string] DRSAutomationLevel
    [bool]   VsanEnabled
    [string] VsanDiskClaimMode
    [string] EVCMode
    VsCluster() {}
}

# Example: list of vCenter names you are connected to
$names = @('vcsa01.domain.tld','vcsa02.domain.tld')

# Grab VIServer objects
$viServers = Get-VIServer -Server $names

# Create a strongly typed generic list
$vcenters = New-Object 'System.Collections.Generic.List[VsVCenter]'

foreach ($vi in $viServers) {
    $obj = [VsVCenter]::FromVIServer($vi)
    $obj.LoadDataCenters()
    $obj.LoadClusters()
    $vcenters.Add($obj) | Out-Null
}

# Show results (flatten for readability)
$vcenters | ForEach-Object {
    $vc = $_
    foreach ($dc in $vc.DataCenters) {
        foreach ($cl in $dc.Clusters) {
            [pscustomobject]@{
                vCenter            = $vc.Name
                DataCenter         = $dc.Name
                Cluster            = $cl.Name
                HAEnabld           = $cl.HAEnabld
                DRSEnabled         = $cl.DRSEnabled
                DRSAutomationLevel = $cl.DRSAutomationLevel
                VsanEnabled        = $cl.VsanEnabled
                VsanDiskClaimMode  = $cl.VsanDiskClaimMode
                EVCMode            = $cl.EVCMode
            }
        }
    }
} | Format-Table -Auto
