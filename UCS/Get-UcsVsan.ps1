function Get-UcsVsan {
    <#
    .SYNOPSIS
      List VSANs defined in UCS (fabricVsan).
    .PARAMETER Server
      Optional UCS Manager hostname/IP. If omitted, queries all connected sessions.
    .PARAMETER Name
      Optional VSAN name filter (wildcards ok).
    .EXAMPLE
      Get-UcsVsan
    .EXAMPLE
      Get-UcsVsan -Server ucsm01.lab.local -Name "vsan-*"
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
        $q = "<configResolveClass cookie='$cookie' inHierarchical='false' classId='fabricVsan'/>"
        $x = Invoke-UcsXml -Target $t -XmlBody $q
        $vsans = @($x.configResolveClass.outConfigs.fabricVsan)
        if ($Name){ $vsans = $vsans | Where-Object { $_.name -like $Name } }
        foreach($v in $vsans){
            [pscustomobject]@{
                Server    = $t
                Name      = $v.name
                Id        = [int]$v.id
                FcZoning  = $v.fcoeUplinkPortCount # sometimes blank; schema varies
                UcsmDn    = $v.dn
                FcoeVlan  = $v.fcoeVlan
                OperState = $v.operState
            }
        }
    }
    if($out){ $out | Sort-Object Server, Id }
}
