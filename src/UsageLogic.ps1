function Get-SeverityLevel {
    [CmdletBinding()]
    param([Nullable[int]]$Percent)

    if ($null -eq $Percent) { return 'Unknown' }
    if ($Percent -lt 50)    { return 'Ok' }
    if ($Percent -lt 80)    { return 'Warning' }
    return 'Critical'
}

function Format-Remaining {
    [CmdletBinding()]
    param([Parameter(Mandatory)][TimeSpan]$Span)

    if ($Span.TotalMinutes -lt 1) { return 'ya' }
    if ($Span.TotalHours -lt 1)   { return '{0}m' -f [int][Math]::Floor($Span.TotalMinutes) }
    if ($Span.TotalDays -lt 1)    { return '{0}h {1:00}m' -f [int][Math]::Floor($Span.TotalHours), $Span.Minutes }
    return '{0}d {1}h' -f [int][Math]::Floor($Span.TotalDays), $Span.Hours
}

function Get-LimitInfo {
    [CmdletBinding()]
    param(
        $Block,
        [Parameter(Mandatory)][string]$TimeFormat,
        [DateTime]$Now = (Get-Date)
    )

    if (-not $Block -or $null -eq $Block.utilization) {
        return @{ Pct = $null; Short = 'sin datos'; Long = 'sin datos' }
    }

    $pct = [int][Math]::Round([double]$Block.utilization, [MidpointRounding]::AwayFromZero)
    $reset = ''
    if ($Block.resets_at) {
        $t = [DateTimeOffset]::Parse($Block.resets_at).LocalDateTime
        $reset = 'reinicia {0} (en {1})' -f $t.ToString($TimeFormat), (Format-Remaining ($t - $Now))
    }
    return @{ Pct = $pct; Short = "$pct%"; Long = "$pct% - $reset" }
}

function ConvertTo-UsageErrorMessage {
    [CmdletBinding()]
    param([Nullable[int]]$StatusCode, [string]$Detail)

    if ($StatusCode -eq 401) { return 'Token vencido o inválido (HTTP 401): abre Claude Code para renovarlo' }
    if ($StatusCode -eq 403) { return 'Acceso denegado (HTTP 403): la cuenta no tiene permiso para ver el uso' }
    if ($StatusCode -eq 429) { return 'Demasiadas solicitudes (HTTP 429): se reintentará en el próximo ciclo' }
    if ($StatusCode -ge 500) { return "Servicio de Anthropic no disponible (HTTP $StatusCode): se reintentará en el próximo ciclo" }
    if ($StatusCode)         { return "Respuesta inesperada del servidor (HTTP $StatusCode)" }
    if ($Detail)             { return "Sin conexión con api.anthropic.com: $Detail" }
    return 'Sin conexión con api.anthropic.com'
}

function Get-OAuthCredential {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow)

    Write-Verbose "Leyendo credenciales de $Path"
    if (-not (Test-Path $Path)) {
        throw "No se encontró ${Path}: inicia sesión en Claude Code primero"
    }
    try {
        $cred = (Get-Content $Path -Raw | ConvertFrom-Json).claudeAiOauth
    } catch {
        throw "No se pudo leer $Path como JSON: $($_.Exception.Message)"
    }
    if (-not $cred.accessToken) {
        throw "${Path} no contiene claudeAiOauth.accessToken: inicia sesión en Claude Code con tu cuenta de Claude"
    }
    if ($cred.expiresAt) {
        $expires = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$cred.expiresAt)
        Write-Verbose "El token vence el $($expires.LocalDateTime)"
        if ($expires -lt $Now) {
            throw "Token vencido desde $($expires.LocalDateTime.ToString('g')): abre Claude Code para renovarlo"
        }
    }
    return $cred
}

function Get-Usage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$AuthFile, [Parameter(Mandatory)][string]$UsageUrl)

    $cred = Get-OAuthCredential -Path $AuthFile
    $headers = @{
        'Authorization'  = "Bearer $($cred.accessToken)"
        'anthropic-beta' = 'oauth-2025-04-20'
        'User-Agent'     = 'claude-usage-widget/1.0'
    }
    Write-Verbose "GET $UsageUrl"
    try {
        return Invoke-RestMethod -Uri $UsageUrl -Headers $headers -TimeoutSec 15 -UseBasicParsing
    } catch {
        $code = $null
        if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
        Write-Verbose "Falló la petición (HTTP $code): $($_.Exception.Message)"
        $detail = if ($code) { $null } else { $_.Exception.Message }
        throw (ConvertTo-UsageErrorMessage -StatusCode $code -Detail $detail)
    }
}
