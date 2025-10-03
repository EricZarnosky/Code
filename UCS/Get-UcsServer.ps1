function Get-UcsServer {
    <#
    .SYNOPSIS
      Summarize info about one or more connected UCS Manager servers.
    .DESCRIPTION
      Uses active sessions from $global:UcsSessions (created by Connect-UcsServer).
      Queries common classes via the XML API and returns counts & basics.
    .PARAMETER Server
      (Optional) Specific server to query. If omitted, queries all connected sessions.
    .EXAMPLE
      Get-UcsServer
    .EXAMPLE
      Get-UcsServer -Server ucsm01.lab.local
    #>
    [CmdletBinding()]
    param(
        [string]$Server
    )

    if (-not (Get-Variable -Name UcsSessions -Scope Global -ErrorAction SilentlyContinue) -or
        -not $global:UcsSessions.Keys.Count) {
        throw "No UCS sessions found. Run Connect-UcsServer first."
    }

    # Local helper: post XML to /nuova and return parsed XML object
    function Invoke-UcsXml {
        param(
            [Parameter(Mandatory)][string]$Target,
            [Parameter(Mandatory)][string]$XmlBody
        )
        $uri = "https://$Target/nuova"
        try {
            $resp = Invoke-WebRequest -Uri $uri -Method Post -Body $XmlBody -ContentType "application/xml" -TimeoutSec 20
            if ($resp.StatusCode -ne 200 -or -not $resp.Content) {
                throw "HTTP $($resp.StatusCode)"
            }
            [xml]$resp.Content
        } catch {
            Write-Verbose "Invoke-UcsXml error on $Target: $($_.Exception.Message)"
            $null
        }
    }

    $targets = if ($Server) { @($Server) } else { $global:UcsSessions.Keys }

    $results = foreach ($t in $targets) {
        if (-not $global:UcsSessions.ContainsKey($t)) {
            Write-Warning "Not connected to $t"
            continue
        }

        $sess   = $global:UcsSessions[$t]
        $cookie = $sess.Cookie

        # Queries (all safe, read-only)
        $q_sys      = "<configResolveDn cookie='$cookie' inHierarchical='false' dn='sys'/>"
        $q_chassis  = "<configResolveClass cookie='$cookie' inHierarchical='false' classId='equipmentChassis'/>"
        $q_blades   = "<configResolveClass cookie='$cookie' inHierarchical='false' classId='computeBlade'/>"
        $q_racks    = "<configResolveClass cookie='$cookie' inHierarchical='false' classId='computeRackUnit'/>"
        $q_sps      = "<configResolveClass cookie='$cookie' inHierarchical='false' classId='lsServer'/>"
        # firmware (best-effort; schema varies by platform/version)
        $q_fw       = "<configResolveClass cookie='$cookie' inHierarchical='false' classId='firmwareRunning'/>"

        $sysXml     = Invoke-UcsXml -Target $t -XmlBody $q_sys
        $chXml      = Invoke-UcsXml -Target $t -XmlBody $q_chassis
        $blXml      = Invoke-UcsXml -Target $t -XmlBody $q_blades
        $rkXml      = Invoke-UcsXml -Target $t -XmlBody $q_racks
        $spXml      = Invoke-UcsXml -Target $t -XmlBody $q_sps
        $fwXml      = Invoke-UcsXml -Target $t -XmlBody $q_fw

        # Safely extract attributes (XML -> PowerShell objects/attributes)
        $sysNode = $sysXml.configResolveDn.outConfig.topSystem
        $domainName = $sysNode.name
        $descr      = $sysNode.descr

        # Counts
        $chassisCount = @($chXml.configResolveClass.outConfigs.equipmentChassis).Count
        $bladeCount   = @($blXml.configResolveClass.outConfigs.computeBlade).Count
        $rackCount    = @($rkXml.configResolveClass.outConfigs.computeRackUnit).Count
        $spCount      = @($spXml.configResolveClass.outConfigs.lsServer).Count

        # Try to guess UCSM version from firmwareRunning (best-effort)
        $fwItems = @($fwXml.configResolveClass.outConfigs.firmwareRunning)
        $ucsmVersion = $null
        if ($fwItems.Count -gt 0) {
            # Look for something that smells like UCS Manager/system software
            $candidate = $fwItems |
                Where-Object { $_.dn -match 'sys' -or $_.type -match 'switch|system|kernel|ucs' -or $_.deployment -match 'system' } |
                Select-Object -First 1
            if ($candidate -and $candidate.version) { $ucsmVersion = $candidate.version }
        }

        # Cookie age
        $cookieAge = (Get-Date) - $sess.Time

        [pscustomobject]@{
            Server          = $t
            User            = $sess.User
            ConnectedSince  = $sess.Time
            CookieAgeMins   = [math]::Round($cookieAge.TotalMinutes, 1)
            DomainName      = $domainName
            Description     = $descr
            UCSMVersion     = $ucsmVersion
            ChassisCount    = $chassisCount
            BladeCount      = $bladeCount
            RackUnitCount   = $rackCount
            ServiceProfiles = $spCount
        }
    }

    # Pretty default view
    $results | Sort-Object Server
}
