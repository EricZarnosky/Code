function Get-UcsVlan {
    <#
    .SYNOPSIS
      List VLANs defined in UCS (fabricVlan).
    .PARAMETER Server
      Optional UCS Manager hostname/IP. If omitted, queries all connected sessions.
    .PARAMETER Name
      Optional VLAN name filter (wildcards ok).
    .EXAMPLE
      Get-UcsVlan
    .EXAMPLE
      Get-UcsVlan -Server ucsm01.lab.local -Name "prod-*"
    #>
    [CmdletBinding()]
    param(
        [string]$Server,
        [string]$Name
    )

    if (-not (Get-Variable -Name UcsSessions -Scope Global -ErrorAction SilentlyContinue) -or -not $global:UcsSessions.Keys.Count) {
        throw "No UCS sessions found. Run Connect-UcsServer first."
    }

    function Invoke-UcsXml { param([string]$Target,[string]$XmlBody)
        $uri="https://$Target/nuova"
        try {
            $r=Invoke-WebRequest -Uri $uri -Method Post -Body $XmlBody -ContentType "application/xml" -TimeoutSec 20
            if ($r.StatusCode -ne 200 -or -not $r.Content) { return $null }
            [xml]$r.Content
        } catch { $null }
    }

    $targets = if ($Server){@($Server)} else {$global:UcsSessions.Keys}
    $out = foreach($t in $targets){
        if(-not $global:UcsSessions.ContainsKey($t)){ Write-Warning "Not connected to $t"; continue }
        $cookie = $global:UcsSessions[$t].Cookie
        $q = "<configResolveClass cookie='$cookie' inHierarchical='false' classId='fabricVlan'/>"
        $x = Invoke-UcsXml -Target $t -XmlBody $q
        $vlans = @($x.configResolveClass.outConfigs.fabricVlan)
        if ($Name){ $vlans = $vlans | Where-Object { $_.name -like $Name } }
        foreach($v in $vlans){
            [pscustomobject]@{
                Server    = $t
                Name      = $v.name
                Id        = [int]$v.id
                UcsmDn    = $v.dn
                Sharing   = $v.sharing        # none / primary / isolated / community (PVLAN)
                DefaultNet= $v.defaultNet     # true/false
                Multicast = $v.mcastPolicyName
                OperState = $v.operState
            }
        }
    }
    if($out){ $out | Sort-Object Server, Id }
}
