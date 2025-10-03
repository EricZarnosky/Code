function Get-UcsChassis {
    <#
    .SYNOPSIS
      Get information about UCS chassis (equipmentChassis).
    .DESCRIPTION
      Queries per-chassis details (model, serial, state, PSU/FAN counts).
      Uses active sessions in $global:UcsSessions from Connect-UcsServer.
    .PARAMETER Server
      (Optional) UCS Manager hostname/IP. If omitted, queries all connected sessions.
    .PARAMETER ChassisId
      (Optional) Filter to a specific chassis number (integer).
    .EXAMPLE
      Get-UcsChassis -Server ucsm01.lab.local
    .EXAMPLE
      Get-UcsChassis -ChassisId 3
    #>
    [CmdletBinding()]
    param(
        [string]$Server,
        [int]$ChassisId
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

    $out = foreach ($t in $targets) {
        if (-not $global:UcsSessions.ContainsKey($t)) { Write-Warning "Not connected to $t"; continue }
        $cookie = $global:UcsSessions[$t].Cookie

        $q = "<configResolveClass cookie='$cookie' inHierarchical='false' classId='equipmentChassis'/>"
        $x = Invoke-UcsXml -Target $t -XmlBody $q
        $chList = @($x.configResolveClass.outConfigs.equipmentChassis)

        if ($ChassisId) { $chList = $chList | Where-Object { $_.id -eq "$ChassisId" } }

        foreach ($c in $chList) {
            if (-not $c) { continue }
            $dn        = $c.dn
            $id        = $c.id
            $model     = $c.model
            $serial    = $c.serial
            $operState = $c.operState
            $thermal   = $c.thermal
            $descr     = $c.descr
            $power     = $c.power
            $numSlots  = $c.numOfSlots

            # Children: power supplies & fan modules
            $q_psu = "<configResolveChildren cookie='$cookie' inDn='$dn' classId='equipmentPsu'/>"
            $q_fan = "<configResolveChildren cookie='$cookie' inDn='$dn' classId='equipmentFanModule'/>"
            $psuXml = Invoke-UcsXml -Target $t -XmlBody $q_psu
            $fanXml = Invoke-UcsXml -Target $t -XmlBody $q_fan

            $psus = @($psuXml.configResolveChildren.outConfigs.equipmentPsu)
            $fans = @($fanXml.configResolveChildren.outConfigs.equipmentFanModule)

            $psuTotal = $psus.Count
            $psuOk    = ($psus | Where-Object { $_.operState -in @('ok','on','powered-up','operable') }).Count
            $fanTotal = $fans.Count
            $fanOk    = ($fans | Where-Object { $_.operState -in @('ok','operable') }).Count

            [pscustomobject]@{
                Server         = $t
                ChassisId      = [int]$id
                ChassisDn      = $dn
                Model          = $model
                Serial         = $serial
                OperState      = $operState
                Thermal        = $thermal
                PowerState     = $power
                BladeSlots     = [int]$numSlots
                PSUs_OK_Total  = "$psuOk/$psuTotal"
                Fans_OK_Total  = "$fanOk/$fanTotal"
                Description    = $descr
            }
        }
    }

    if ($out) { $out | Sort-Object Server, ChassisId }
}
