function Get-UcsBlade {
    <#
    .SYNOPSIS
      Get information about a Cisco UCS blade (computeBlade) via XML API.
    .DESCRIPTION
      Uses active sessions in $global:UcsSessions (from Connect-UcsServer).
      You can target a blade by -Dn "sys/chassis-X/blade-Y" OR by -ChassisId/-SlotId.
      If -Server is omitted, the function searches all connected UCS servers.
    .PARAMETER Server
      UCS Manager hostname/IP. If omitted, all connected sessions are used.
    .PARAMETER Dn
      Blade DN, e.g. "sys/chassis-1/blade-2".
    .PARAMETER ChassisId
      Chassis ID number (integer). Use with -SlotId when -Dn is not provided.
    .PARAMETER SlotId
      Blade slot number (integer). Use with -ChassisId when -Dn is not provided.
    .EXAMPLE
      Get-UcsBlade -Server ucsm01.lab.local -Dn "sys/chassis-1/blade-2"
    .EXAMPLE
      Get-UcsBlade -ChassisId 1 -SlotId 2   # searches all connected UCS sessions
    .EXAMPLE
      # All blades on a server
      Get-UcsBlade -Server ucsm01.lab.local
    #>
    [CmdletBinding()]
    param(
        [string]$Server,
        [string]$Dn,
        [int]$ChassisId,
        [int]$SlotId
    )

    if (-not (Get-Variable -Name UcsSessions -Scope Global -ErrorAction SilentlyContinue) -or
        -not $global:UcsSessions.Keys.Count) {
        throw "No UCS sessions found. Run Connect-UcsServer first."
    }

    # Local helper to POST XML to /nuova and return [xml] (or $null on error)
    function Invoke-UcsXml {
        param(
            [Parameter(Mandatory)][string]$Target,
            [Parameter(Mandatory)][string]$XmlBody
        )
        $uri = "https://$Target/nuova"
        try {
            $resp = Invoke-WebRequest -Uri $uri -Method Post -Body $XmlBody -ContentType "application/xml" -TimeoutSec 25
            if ($resp.StatusCode -ne 200 -or -not $resp.Content) { return $null }
            [xml]$resp.Content
        } catch {
            Write-Verbose "Invoke-UcsXml error on $Target: $($_.Exception.Message)"
            $null
        }
    }

    # Determine targets (UCS servers) and blade selector
    $targets = if ($Server) { @($Server) } else { $global:UcsSessions.Keys }

    # If no explicit selector is provided, we’ll list ALL blades
    $selectAll = -not $Dn -and -not ($ChassisId -and $SlotId)

    # Build a DN from chassis/slot if needed
    if (-not $selectAll -and -not $Dn) {
        if (-not $ChassisId -or -not $SlotId) {
            throw "Provide either -Dn or both -ChassisId and -SlotId."
        }
        $Dn = "sys/chassis-$ChassisId/blade-$SlotId"
    }

    $out = foreach ($t in $targets) {
        if (-not $global:UcsSessions.ContainsKey($t)) {
            Write-Warning "Not connected to $t"
            continue
        }

        $cookie = $global:UcsSessions[$t].Cookie

        # Query set
        if ($selectAll) {
            # All blades on this UCS
            $q_blades = "<configResolveClass cookie='$cookie' inHierarchical='false' classId='computeBlade'/>"
            $blXml    = Invoke-UcsXml -Target $t -XmlBody $q_blades
            $blades   = @($blXml.configResolveClass.outConfigs.computeBlade)
        } else {
            # Specific blade DN
            $q_dn   = "<configResolveDn cookie='$cookie' inHierarchical='false' dn='$Dn'/>"
            $dnXml  = Invoke-UcsXml -Target $t -XmlBody $q_dn
            $blade  = $dnXml.configResolveDn.outConfig.computeBlade
            $blades = @()
            if ($blade) { $blades += $blade }
        }

        foreach ($b in $blades) {
            if (-not $b) { continue }

            # Pull basic blade attributes safely (null-safe access)
            $bdn         = $b.dn
            $model       = $b.model
            $serial      = $b.serial
            $uuid        = $b.uuid
            $adminPower  = $b.adminPower
            $operPower   = $b.operPower
            $operState   = $b.operState
            $numCpus     = [int]::TryParse($b.numOfCpus, [ref]([int]0)) | Out-Null; $numCpus = [int]$b.numOfCpus
            $numCores    = [int]$b.numOfCores
            $numThreads  = [int]$b.numOfThreads
            $availMemMb  = [int]$b.availableMemory
            $availMemGb  = if ($availMemMb) { [math]::Round($availMemMb/1024, 1) } else { $null }
            $chassis     = $b.chassisId
            $slot        = $b.slotId

            # Associated Service Profile (if any)
            # Many UCS versions expose computeBlade.assignedToDn when associated
            $spDn   = $b.assignedToDn
            $spName = $null
            $spAssocState = $null
            if ($spDn) {
                $q_sp  = "<configResolveDn cookie='$cookie' inHierarchical='false' dn='$spDn'/>"
                $spXml = Invoke-UcsXml -Target $t -XmlBody $q_sp
                $sp    = $spXml.configResolveDn.outConfig.lsServer
                if ($sp) {
                    $spName       = $sp.name
                    $spAssocState = $sp.assocState
                }
            }

            # Adapters in the blade (adaptorUnit)
            $adapters = @()
            $q_adp = "<configResolveChildren cookie='$cookie' inDn='$bdn' classId='adaptorUnit'/>"
            $adpXml = Invoke-UcsXml -Target $t -XmlBody $q_adp
            $adpList = @($adpXml.configResolveChildren.outConfigs.adaptorUnit)
            if ($adpList.Count -gt 0) {
                $adapters = $adpList | ForEach-Object {
                    $aModel = $_.model
                    $aSerial = $_.serial
                    if ($aSerial) { "$aModel (S/N $aSerial)" } else { "$aModel" }
                }
            }

            # Build result object
            [pscustomobject]@{
                Server             = $t
                BladeDn            = $bdn
                Chassis            = $chassis
                Slot               = $slot
                Model              = $model
                Serial             = $serial
                UUID               = $uuid
                AdminPower         = $adminPower
                OperPower          = $operPower
                OperState          = $operState
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

    if ($out) { $out | Sort-Object Server, BladeDn }
}
