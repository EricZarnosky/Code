function Get-UcsVnicTemplate {
    <#
    .SYNOPSIS
      List vNIC templates (LAN) in UCS (vnicLanConnTempl).
    .DESCRIPTION
      Shows MAC pool, MTU, VLAN policy, switch/fabric prefer, templating type (initial/Updating).
    .PARAMETER Server
      Optional UCS Manager hostname/IP. If omitted, queries all connected sessions.
    .PARAMETER Name
      Optional template name filter (wildcards ok).
    .EXAMPLE
      Get-UcsVnicTemplate
    .EXAMPLE
      Get-UcsVnicTemplate -Server ucsm01.lab.local -Name "vm-*-nic*"
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
        $q = "<configResolveClass cookie='$cookie' inHierarchical='false' classId='vnicLanConnTempl'/>"
        $x = Invoke-UcsXml -Target $t -XmlBody $q
        $temps = @($x.configResolveClass.outConfigs.vnicLanConnTempl)
        if ($Name){ $temps = $temps | Where-Object { $_.name -like $Name } }

        foreach($tpl in $temps){
            [pscustomobject]@{
                Server        = $t
                Name          = $tpl.name
                TemplateType  = $tpl.templType            # initial-template / updating-template
                FabricPref    = $tpl.switchId             # A / B / dual
                MacPool       = $tpl.identPoolName
                Mtu           = [int]$tpl.mtu
                VlanPolicy    = $tpl.vlanName             # if bound directly
                QosPolicy     = $tpl.qosPolicyName
                StatsPolicy   = $tpl.statsPolicyName
                PinGroup      = $tpl.pinToGroupName
                VnicDn        = $tpl.dn
            }
        }
    }
    if($out){ $out | Sort-Object Server, Name }
}
