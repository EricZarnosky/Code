function Connect-UcsServer {
    <#
    .SYNOPSIS
      Connects to a Cisco UCS Manager server via XML API.
    .DESCRIPTION
      Works like VMware Connect-VIServer. Supports multiple UCS sessions by
      keeping a global hashtable keyed by server.
    .PARAMETER Server
      Hostname or IP of the UCS Manager (Fabric Interconnect VIP).
    .PARAMETER Credential
      PSCredential object with username/password.
    .PARAMETER SkipCertificateCheck
      Skip TLS certificate validation (default $true).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][pscredential]$Credential,
        [switch]$SkipCertificateCheck
    )

    # Ensure global session table exists
    if (-not (Get-Variable -Name UcsSessions -Scope Global -ErrorAction SilentlyContinue)) {
        $global:UcsSessions = @{}
    }

    if ($SkipCertificateCheck) {
        Add-Type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class PermissiveCertPolicy {
    public static bool Validator(object s, X509Certificate c, X509Chain ch, SslPolicyErrors e) { return true; }
}
"@
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = [PermissiveCertPolicy]::Validator
    }

    $uri = "https://$Server/nuova"
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Credential.Password))
    $loginXml = "<aaaLogin inName='$($Credential.UserName)' inPassword='$plain'/>"

    try {
        $resp = Invoke-WebRequest -Uri $uri -Method Post -Body $loginXml -ContentType "application/xml" -TimeoutSec 10
        [xml]$xmlResp = $resp.Content
        $cookie = $xmlResp.aaaLogin.outCookie

        if ([string]::IsNullOrEmpty($cookie)) {
            throw "No cookie returned from $Server. Invalid credentials?"
        }

        $session = [pscustomobject]@{
            Server = $Server
            User   = $Credential.UserName
            Cookie = $cookie
            Time   = Get-Date
        }

        $global:UcsSessions[$Server] = $session
        Write-Host "✅ Connected to UCS Manager $Server as $($Credential.UserName)."
        return $session
    }
    catch {
        Write-Error "❌ Failed to connect to $Server: $($_.Exception.Message)"
    }
    finally {
        if ($plain) { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Credential.Password)) | Out-Null }
    }
}
