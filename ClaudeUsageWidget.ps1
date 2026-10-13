Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class NativeW {
    [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@

. (Join-Path $PSScriptRoot 'src\UsageLogic.ps1')

$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\ClaudeUsageWidget', [ref]$createdNew)
if (-not $createdNew) { exit }

[NativeW]::SetProcessDPIAware() | Out-Null
[System.Windows.Forms.Application]::EnableVisualStyles()
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RefreshSeconds  = 180
$ConfigDir       = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE '.claude' }
$AuthFile        = Join-Path $ConfigDir '.credentials.json'
$UsageUrl        = 'https://api.anthropic.com/api/oauth/usage'
$DashboardUrl    = 'https://claude.ai/settings/usage'
$Launcher        = Join-Path $PSScriptRoot 'ClaudeUsageWidget.vbs'
$StartupLnk      = Join-Path ([Environment]::GetFolderPath('Startup')) 'Claude Usage Widget.lnk'

$IconPx = [System.Windows.Forms.SystemInformation]::SmallIconSize.Width
if ($IconPx -lt 16) { $IconPx = 16 }

$script:Usage   = $null
$script:Updated = $null
$script:Err     = $null

$SeverityColors = @{
    Unknown  = [System.Drawing.Color]::FromArgb(120, 120, 120)
    Ok       = [System.Drawing.Color]::FromArgb(46, 160, 67)
    Warning  = [System.Drawing.Color]::FromArgb(212, 150, 20)
    Critical = [System.Drawing.Color]::FromArgb(218, 54, 51)
}

function New-RoundedPath([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

# Sesión: cuadrado relleno. Semana: cuadrado oscuro con borde del color de severidad.
function New-UsageIcon([string]$text, $color, [bool]$filled) {
    $s = $IconPx
    $bmp = New-Object System.Drawing.Bitmap $s, $s
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.Clear([System.Drawing.Color]::Transparent)

    $radius = [Math]::Max(2, $s / 5)
    if ($filled) {
        $path = New-RoundedPath 0 0 ($s - 1) ($s - 1) $radius
        $brush = New-Object System.Drawing.SolidBrush $color
        $g.FillPath($brush, $path); $brush.Dispose()
    } else {
        $bw = [Math]::Max(1.5, $s / 10)
        $half = $bw / 2
        $path = New-RoundedPath $half $half ($s - 1 - $bw) ($s - 1 - $bw) $radius
        $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(32, 32, 32))
        $g.FillPath($brush, $path); $brush.Dispose()
        $pen = New-Object System.Drawing.Pen $color, $bw
        $g.DrawPath($pen, $path); $pen.Dispose()
    }
    $path.Dispose()

    $fmt = [System.Drawing.StringFormat]::GenericTypographic
    $maxW = $s * 0.92
    $size = $s * 0.72
    do {
        $font = New-Object System.Drawing.Font 'Segoe UI', $size, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
        $m = $g.MeasureString($text, $font, 1000, $fmt)
        if ($m.Width -le $maxW -or $size -le 6) { break }
        $font.Dispose()
        $size -= 0.5
    } while ($true)

    $x = ($s - $m.Width) / 2
    $y = ($s - $m.Height) / 2
    $g.DrawString($text, $font, [System.Drawing.Brushes]::White, [float]$x, [float]$y, $fmt)
    $font.Dispose(); $g.Dispose()
    return $bmp
}

function Set-TrayIcon($ni, [string]$text, $pct, [bool]$filled, [string]$tip) {
    $color = $SeverityColors[(Get-SeverityLevel $pct)]
    $bmp = New-UsageIcon $text $color $filled
    $h = $bmp.GetHicon()
    $bmp.Dispose()
    $old = $ni.Tag
    $ni.Icon = [System.Drawing.Icon]::FromHandle($h)
    $ni.Tag = $h
    if ($old) { [NativeW]::DestroyIcon([IntPtr]$old) | Out-Null }
    if ($tip.Length -gt 63) { $tip = $tip.Substring(0, 63) }   # límite de NotifyIcon.Text
    $ni.Text = $tip
}

function Update-View {
    $u = $script:Usage
    $session = Get-LimitInfo $u.five_hour 'HH:mm'
    $week    = Get-LimitInfo $u.seven_day 'dddd HH:mm'

    $suffix = ''
    if ($script:Err) { $suffix = "`n! $($script:Err)" }
    elseif ($script:Updated) { $suffix = "`nAct. $($script:Updated.ToString('HH:mm'))" }

    $sText = if ($null -eq $session.Pct) { '--' } else { [string][Math]::Min($session.Pct, 100) }
    $wText = if ($null -eq $week.Pct)    { '--' } else { [string][Math]::Min($week.Pct, 100) }

    Set-TrayIcon $niSession $sText $session.Pct $true  ("Claude sesión: $($session.Short)$suffix")
    Set-TrayIcon $niWeek    $wText $week.Pct    $false ("Claude semana: $($week.Short)$suffix")

    $miSession.Text = "Sesión (5 h):  $($session.Long)"
    $miWeek.Text    = "Semana:  $($week.Long)"
    $miStatus.Text  = if ($script:Err) { "! $($script:Err)" }
                      elseif ($script:Updated) { "Actualizado a las $($script:Updated.ToString('HH:mm:ss'))" }
                      else { 'Cargando...' }
}

function Update-Widget {
    try {
        $script:Usage   = Get-Usage -AuthFile $AuthFile -UsageUrl $UsageUrl
        $script:Updated = Get-Date
        $script:Err     = $null
    } catch {
        $script:Err = $_.Exception.Message
    }
    Update-View
}

function Set-Autostart([bool]$on) {
    if ($on) {
        $sh = New-Object -ComObject WScript.Shell
        $lnk = $sh.CreateShortcut($StartupLnk)
        $lnk.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
        $lnk.Arguments = '"' + $Launcher + '"'
        $lnk.WorkingDirectory = $PSScriptRoot
        $lnk.Description = 'Claude Usage Widget'
        $lnk.Save()
    } elseif (Test-Path $StartupLnk) {
        Remove-Item $StartupLnk -Force
    }
}

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$miSession = $menu.Items.Add('Sesión: ...');  $miSession.Enabled = $false
$miWeek    = $menu.Items.Add('Semana: ...');  $miWeek.Enabled = $false
$miStatus  = $menu.Items.Add('Cargando...');  $miStatus.Enabled = $false
$menu.Items.Add('-') | Out-Null
$miRefresh = $menu.Items.Add('Actualizar ahora')
$miOpen    = $menu.Items.Add('Abrir uso en claude.ai')
$miAuto    = New-Object System.Windows.Forms.ToolStripMenuItem 'Iniciar con Windows'
$miAuto.CheckOnClick = $true
$miAuto.Checked = Test-Path $StartupLnk
$menu.Items.Add($miAuto) | Out-Null
$menu.Items.Add('-') | Out-Null
$miExit    = $menu.Items.Add('Salir')

$miRefresh.add_Click({ Update-Widget })
$miOpen.add_Click({ Start-Process $DashboardUrl })
$miAuto.add_CheckedChanged({ Set-Autostart $miAuto.Checked })

# El de semana se crea primero para que el de sesión quede a la izquierda
$niWeek = New-Object System.Windows.Forms.NotifyIcon
$niSession = New-Object System.Windows.Forms.NotifyIcon
foreach ($ni in @($niWeek, $niSession)) {
    $ni.ContextMenuStrip = $menu
    $ni.add_MouseDoubleClick({ Start-Process $DashboardUrl })
}
Update-View
$niWeek.Visible = $true
$niSession.Visible = $true

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $RefreshSeconds * 1000
$timer.add_Tick({ Update-Widget })

$miExit.add_Click({
    $timer.Stop()
    foreach ($ni in @($niSession, $niWeek)) {
        $ni.Visible = $false
        if ($ni.Tag) { [NativeW]::DestroyIcon([IntPtr]$ni.Tag) | Out-Null }
        $ni.Dispose()
    }
    [System.Windows.Forms.Application]::Exit()
})

Update-Widget
$timer.Start()
[System.Windows.Forms.Application]::Run()
$mutex.ReleaseMutex()
