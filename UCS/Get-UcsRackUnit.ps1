function Get-UcsRackUnit {
    <#
    .SYNOPSIS
      Get information about UCS rack servers (computeRackUnit).
    .DESCRIPTION
      Queries C-series rack units managed by UCS Manager.
      Returns model/serial/UUID/CPU/memory/state and SP association.
    .PARAMETER Server
      (Optional) UCS Manager hostname/IP. If omitted, queries all connected sessions.
    .PARAMETER Dn
      (Optional) Specific rack-unit DN (e.g. "sys/rack-unit-1").
    .PARAMETER Id
      (Optional) Rack unit numeric ID (e.g. 1 for sys/rack-unit-1). If both -Dn and -Id are omitted, returns all.
    .EXAMPLE
      Get-UcsRackUnit -Server ucsm01.lab.local
    .EXAMPLE
      Get-UcsRackUnit -Id 3
    .EXAMPLE
      Get-UcsRackUnit -Dn "sys/rack-unit-2"
    #>
    [CmdletBinding()]
    param(
        [string]$Server,
        [string]$Dn,
        [int]$Id
    )

    if (-not (Get-Variable -Name UcsSessions -Scope Global -ErrorAction SilentlyContinue) -or
        -not $global:UcsSessions.Keys.Count) {
        throw "No UCS sessions found. Run Connect-UcsServer first."
    }

    function Invoke-UcsXml {
        param([Parameter(Mandatory)][string]$Target,[Parameter(Mandatory)][string]$XmlBody)
        $uri = "https://$Target/nuova"
        try {
            $resp = Invoke-WebRequest -Uri $uri -Method Post -Body $XmlBody -ContentType "application/xml" -TimeoutSec 25
            if ($resp.StatusCode -ne 200 -or -not $resp.Content) { return $null }
            [xml]$resp.Content
        } catch { Write-Verbose "Invoke-UcsXml error on $Target: $($_.Exception.Message)"; $null }
    }

    $targets = if ($Server) { @($Server) } else { $global:UcsSessions.Keys }
    $selectAll = (-not $Dn -and -not $Id)

    if (-not $selectAll -and -not $Dn -and $Id) { $Dn = "sys/rack-unit-$Id" }

    $out = foreach ($t in $targets) {
        if (-not $global:UcsSessions.ContainsKey($t)) { Write-Warning "Not connected to $t"; continue }
        $cookie = $global:UcsSessions[$t].Cookie

        $ruList = @()
        if ($selectAll) {
            $q_all = "<configResolveClass cookie='$cookie' inHierarchical='false' classId='computeRackUnit'/>"
            $x = Invoke-UcsXml -Target $t -XmlBody $q_all
            $ruList = @($x.configResolveClass.outConfigs.computeRackUnit)
        } else {
            $q_dn = "<configResolveDn cookie='$cookie' inHierarchical='false' dn='$Dn'/>"
            $x = Invoke-UcsXml -Target $t -XmlBody $q_dn
            $ru = $x.configResolveDn.outConfig.computeRackUnit
            if ($ru) { $ruList = @($ru) }
        }

        foreach ($r in $ruList) {
            if (-not $r) { continue }
            $rdn         = $r.dn
            $rid         = $r.id
            $model       = $r.model
            $serial      = $r.serial
            $uuid        = $r.uuid
            $operState   = $r.operState
            $thermal     = $r.thermal
            $adminPower  = $r.adminPower
            $operPower   = $r.operPower
            $numCpus     = [int]$r.numOfCpus
            $numCores    = [int]$r.numOfCores
            $numThreads  = [int]$r.numOfThreads
            $availMemMb  = [int]$r.availableMemory
            $availMemGb  = if ($availMemMb) { [math]::Round($availMemMb/1024, 1) } else { $null }

            # Associated Service Profile (if any)
            $spDn   = $r.assignedToDn
            $spName = $null
            $spAssocState = $null
            if ($spDn) {
                $q_sp = "<configResolveDn cookie='$cookie' inHierarchical='false' dn='$spDn'/>"
                $spX  = Invoke-UcsXml -Target $t -XmlBody $q_sp
                $sp   = $spX.configResolveDn.outConfig.lsServer
                if ($sp) {
                    $spName       = $sp.name
                    $spAssocState = $sp.assocState
                }
            }

            # Installed adapters
            $adapters = @()
            $q_adp = "<configResolveChildren cookie='$cookie' inDn='$rdn' classId='adaptorUnit'/>"
            $adpX = Invoke-UcsXml -Target $t -XmlBody $q_adp
            $adpList = @($adpX.configResolveChildren.outConfigs.adaptorUnit)
            if ($adpList.Count -gt 0) {
                $adapters = $adpList | ForEach-Object {
                    $m = $_.model; $s = $_.serial
                    if ($s) { "$m (S/N $s)" } else { "$m" }
                }
            }

            [pscustomobject]@{
                Server             = $t
                RackUnitId         = [int]$rid
                RackUnitDn         = $rdn
                Model              = $model
                Serial             = $serial
                UUID               = $uuid
                AdminPower         = $adminPower
                OperPower          = $operPower
                OperState          = $operState
                Thermal            = $thermal
                CPUs               = $numCpus
                Cores              = $numCores
                Threads            = $numThreads
                AvailableMemoryGB  = $availMemGb
                ServiceProfileDn   = $spDn
                ServiceProfile     = $spName
                AssocState         = $spAssocState
                Adapters           = $adapters -join ', '
            }
        }
    }

    if ($out) { $out | Sort-Object Server, RackUnitId }
}
