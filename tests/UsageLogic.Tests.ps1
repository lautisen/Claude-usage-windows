BeforeAll {
    . (Join-Path $PSScriptRoot '..\src\UsageLogic.ps1')
}

Describe 'Get-SeverityLevel' {
    It 'devuelve <Expected> para <Percent>%' -ForEach @(
        @{ Percent = $null; Expected = 'Unknown' }
        @{ Percent = 0;     Expected = 'Ok' }
        @{ Percent = 74;    Expected = 'Ok' }
        @{ Percent = 75;    Expected = 'Warning' }
        @{ Percent = 89;    Expected = 'Warning' }
        @{ Percent = 90;    Expected = 'Critical' }
        @{ Percent = 100;   Expected = 'Critical' }
        @{ Percent = 130;   Expected = 'Critical' }
    ) {
        Get-SeverityLevel $Percent | Should -Be $Expected
    }
}

Describe 'Format-Remaining' {
    It 'formatea <Span> como "<Expected>"' -ForEach @(
        @{ Span = [TimeSpan]::FromSeconds(30);                   Expected = 'ya' }
        @{ Span = [TimeSpan]::FromMinutes(-5);                   Expected = 'ya' }
        @{ Span = [TimeSpan]::FromMinutes(1);                    Expected = '1m' }
        @{ Span = [TimeSpan]::FromMinutes(59);                   Expected = '59m' }
        @{ Span = [TimeSpan]::FromMinutes(60);                   Expected = '1h 00m' }
        @{ Span = [TimeSpan]::FromMinutes(150);                  Expected = '2h 30m' }
        @{ Span = [TimeSpan]::FromHours(24);                     Expected = '1d 0h' }
        @{ Span = [TimeSpan]::FromHours(51) + [TimeSpan]::FromMinutes(20); Expected = '2d 3h' }
    ) {
        Format-Remaining $Span | Should -Be $Expected
    }
}

Describe 'Get-LimitInfo' {
    It 'devuelve "sin datos" cuando no hay bloque' {
        $info = Get-LimitInfo -Block $null -TimeFormat 'HH:mm'
        $info.Pct   | Should -BeNullOrEmpty
        $info.Short | Should -Be 'sin datos'
        $info.Long  | Should -Be 'sin datos'
    }

    It 'devuelve "sin datos" cuando utilization es null' {
        $block = [pscustomobject]@{ utilization = $null; resets_at = $null }
        (Get-LimitInfo -Block $block -TimeFormat 'HH:mm').Short | Should -Be 'sin datos'
    }

    It 'redondea la utilización al entero más cercano' -ForEach @(
        @{ Value = 42.4; Expected = 42 }
        @{ Value = 42.5; Expected = 43 }
        @{ Value = 99.9; Expected = 100 }
    ) {
        $block = [pscustomobject]@{ utilization = $Value; resets_at = $null }
        $info = Get-LimitInfo -Block $block -TimeFormat 'HH:mm'
        $info.Pct   | Should -Be $Expected
        $info.Short | Should -Be "$Expected%"
    }

    It 'incluye hora de reinicio y tiempo restante' {
        $resetUtc = '2030-01-15T15:30:00Z'
        $reset = [DateTimeOffset]::Parse($resetUtc).LocalDateTime
        $block = [pscustomobject]@{ utilization = 61; resets_at = $resetUtc }

        $info = Get-LimitInfo -Block $block -TimeFormat 'HH:mm' -Now $reset.AddMinutes(-150)

        $info.Long | Should -Be ('61% - reinicia {0} (en 2h 30m)' -f $reset.ToString('HH:mm'))
    }

    It 'omite el reinicio cuando resets_at no viene' {
        $block = [pscustomobject]@{ utilization = 10; resets_at = $null }
        (Get-LimitInfo -Block $block -TimeFormat 'HH:mm').Long | Should -Be '10% - '
    }
}

Describe 'ConvertTo-UsageErrorMessage' {
    It 'mapea el código <Code> a un mensaje que contiene "<Expected>"' -ForEach @(
        @{ Code = 401; Expected = 'HTTP 401' }
        @{ Code = 403; Expected = 'Acceso denegado' }
        @{ Code = 429; Expected = 'Demasiadas solicitudes' }
        @{ Code = 500; Expected = 'no disponible (HTTP 500)' }
        @{ Code = 503; Expected = 'no disponible (HTTP 503)' }
        @{ Code = 418; Expected = 'Respuesta inesperada del servidor (HTTP 418)' }
    ) {
        ConvertTo-UsageErrorMessage -StatusCode $Code | Should -BeLike "*$Expected*"
    }

    It 'indica sin conexión cuando no hay código HTTP' {
        ConvertTo-UsageErrorMessage -StatusCode $null | Should -Be 'Sin conexión con api.anthropic.com'
    }

    It 'incluye el detalle de red cuando se proporciona' {
        ConvertTo-UsageErrorMessage -StatusCode $null -Detail 'No se pudo resolver el nombre remoto' |
            Should -Be 'Sin conexión con api.anthropic.com: No se pudo resolver el nombre remoto'
    }
}

Describe 'Get-OAuthCredential' {
    BeforeAll {
        $script:Now = [DateTimeOffset]::new(2030, 1, 1, 12, 0, 0, [TimeSpan]::Zero)

        function script:New-CredFile([string]$Name, $Oauth) {
            $path = Join-Path $TestDrive $Name
            @{ claudeAiOauth = $Oauth } | ConvertTo-Json | Set-Content -Path $path
            return $path
        }
    }

    It 'falla si el archivo no existe e indica la ruta' {
        $missing = Join-Path $TestDrive 'missing.json'
        { Get-OAuthCredential -Path $missing } | Should -Throw "No se encontró*missing.json*"
    }

    It 'falla con un mensaje claro si el JSON está corrupto' {
        $path = Join-Path $TestDrive 'broken.json'
        Set-Content -Path $path -Value '{ not json'
        { Get-OAuthCredential -Path $path -Now $script:Now } | Should -Throw 'No se pudo leer*como JSON*'
    }

    It 'falla si no hay accessToken' {
        $path = New-CredFile 'notoken.json' @{ expiresAt = 0 }
        { Get-OAuthCredential -Path $path -Now $script:Now } | Should -Throw '*accessToken*'
    }

    It 'falla si el token está vencido' {
        $expired = $script:Now.AddHours(-1).ToUnixTimeMilliseconds()
        $path = New-CredFile 'expired.json' @{ accessToken = 'abc'; expiresAt = $expired }
        { Get-OAuthCredential -Path $path -Now $script:Now } | Should -Throw 'Token vencido desde*'
    }

    It 'devuelve la credencial si el token es válido' {
        $valid = $script:Now.AddHours(1).ToUnixTimeMilliseconds()
        $path = New-CredFile 'valid.json' @{ accessToken = 'abc'; expiresAt = $valid }
        (Get-OAuthCredential -Path $path -Now $script:Now).accessToken | Should -Be 'abc'
    }

    It 'acepta un token sin fecha de expiración' {
        $path = New-CredFile 'noexp.json' @{ accessToken = 'abc' }
        (Get-OAuthCredential -Path $path -Now $script:Now).accessToken | Should -Be 'abc'
    }
}

Describe 'Get-Usage' {
    BeforeAll {
        $script:AuthFile = Join-Path $TestDrive 'cred.json'
        @{ claudeAiOauth = @{ accessToken = 'secret-token' } } | ConvertTo-Json | Set-Content -Path $script:AuthFile
    }

    It 'envía el token como Bearer y devuelve la respuesta' {
        Mock Invoke-RestMethod { [pscustomobject]@{ five_hour = @{ utilization = 12 } } }

        $result = Get-Usage -AuthFile $script:AuthFile -UsageUrl 'https://example.test/usage'

        $result.five_hour.utilization | Should -Be 12
        Should -Invoke Invoke-RestMethod -Exactly 1 -ParameterFilter {
            $Uri -eq 'https://example.test/usage' -and $Headers['Authorization'] -eq 'Bearer secret-token'
        }
    }

    It 'devuelve "Sin conexión" cuando la petición falla sin respuesta HTTP' {
        Mock Invoke-RestMethod { throw 'network down' }

        { Get-Usage -AuthFile $script:AuthFile -UsageUrl 'https://example.test/usage' } |
            Should -Throw 'Sin conexión con api.anthropic.com: network down'
    }

    It 'no llama a la API si faltan credenciales' {
        Mock Invoke-RestMethod { }

        { Get-Usage -AuthFile (Join-Path $TestDrive 'nope.json') -UsageUrl 'https://example.test/usage' } |
            Should -Throw 'No se encontró*'
        Should -Invoke Invoke-RestMethod -Exactly 0
    }
}
