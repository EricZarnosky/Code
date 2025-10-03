function Disconnect-UcsServer {
    [CmdletBinding()]
    param([string]$Server)

    if (-not (Get-Variable -Name UcsSessions -Scope Global -ErrorAction SilentlyContinue)) { return }

    $targets = if ($Server) { @($Server) } else { $global:UcsSessions.Keys }
    foreach ($srv in $targets) {
        if ($global:UcsSessions.ContainsKey($srv)) {
            $cookie = $global:UcsSessions[$srv].Cookie
            $uri = "https://$srv/nuova"
            $logoutXml = "<aaaLogout cookie='$cookie'/>"
            try {
                Invoke-WebRequest -Uri $uri -Method Post -Body $logoutXml -ContentType "application/xml" -TimeoutSec 10 | Out-Null
            } catch { }
            $global:UcsSessions.Remove($srv) | Out-Null
            Write-Host "🔌 Disconnected from $srv"
        }
    }
}
