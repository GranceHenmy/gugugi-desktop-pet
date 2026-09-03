$ErrorActionPreference = "Stop"

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$nativeSource = @'
using System;
using System.Runtime.InteropServices;

public static class PetNative
{
    [StructLayout(LayoutKind.Sequential)]
    public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }

    [DllImport("user32.dll")]
    public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    public static double IdleSeconds()
    {
        var info = new LASTINPUTINFO();
        info.cbSize = (uint)Marshal.SizeOf(info);
        return GetLastInputInfo(ref info) ? (Environment.TickCount - info.dwTime) / 1000.0 : 0;
    }

    public static uint ForegroundProcessId()
    {
        uint pid;
        GetWindowThreadProcessId(GetForegroundWindow(), out pid);
        return pid;
    }
}
'@
Add-Type -TypeDefinition $nativeSource

$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, "GugugiDesktopPet.SingleInstance", [ref]$createdNew)
if (-not $createdNew) { return }

$scriptPath = $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $scriptPath
$frameRoot = Join-Path $root "assets\prepared-v12"
$settingsPath = Join-Path $root "settings.json"
$startupShortcut = Join-Path ([Environment]::GetFolderPath("Startup")) "咕咕叽桌面宠物.lnk"

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="咕咕叽桌面宠物" Width="200" Height="200"
        WindowStyle="None" ResizeMode="NoResize" AllowsTransparency="True"
        Background="Transparent" Topmost="True" ShowInTaskbar="False"
        ShowActivated="False" Focusable="False" SnapsToDevicePixels="True">
    <Grid Background="Transparent">
        <Image Name="BirdImage" Stretch="Uniform" RenderOptions.BitmapScalingMode="HighQuality"
               ToolTip="拖动小鸟移动位置；双击庆祝；右键打开菜单" />
    </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
$birdImage = $window.FindName("BirdImage")

function Load-Bitmap([string]$path) {
    $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
    $bitmap.BeginInit()
    $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bitmap.UriSource = New-Object System.Uri($path)
    $bitmap.EndInit()
    $bitmap.Freeze()
    return $bitmap
}

$frames = @{}
foreach ($state in @("idle", "typing", "thinking", "complete", "waiting")) {
    $stateFrames = New-Object System.Collections.Generic.List[object]
    Get-ChildItem -LiteralPath (Join-Path $frameRoot $state) -Filter "frame-*.png" |
        Sort-Object Name | ForEach-Object { $stateFrames.Add((Load-Bitmap $_.FullName)) }
    if ($stateFrames.Count -ne 6) { throw "状态 $state 应包含 6 帧，当前为 $($stateFrames.Count) 帧。" }
    $frames[$state] = $stateFrames
}

$durations = @{ idle = 400; typing = 100; thinking = 300; complete = 130; waiting = 470 }
$labels = @{ idle = "待机"; typing = "工作"; thinking = "思考"; complete = "完成"; waiting = "等待" }
$script:currentState = "idle"
$script:manualState = "auto"
$script:frameIndex = 0
$script:paused = $false
$script:lastAutoState = "idle"
$script:wasGenerating = $false
$script:generationStarted = [DateTime]::MinValue
$script:completeUntil = [DateTime]::MinValue

function Get-ChatGPTWindows {
    @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -match "^(ChatGPT|codex)$" -and $_.MainWindowHandle -ne 0
    })
}

function Test-ChatGPTRunning {
    return (Get-ChatGPTWindows).Count -gt 0
}

function Test-ChatGPTInstalled {
    try {
        if (Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -match "(?i)(OpenAI\.(Codex|ChatGPT)|ChatGPT|Codex)"
        } | Select-Object -First 1) { return $true }
    } catch {}
    try {
        $uninstallRoots = @(
            "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
            "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
            "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
        )
        if (Get-ChildItem $uninstallRoots -ErrorAction SilentlyContinue |
            Get-ItemProperty -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -match "(?i)(ChatGPT|Codex)" } |
            Select-Object -First 1) { return $true }
    } catch {}
    return $false
}

function Test-ChatGPTGenerating {
    $names = @("停止", "停止生成", "Stop", "Stop generating", "正在思考", "Thinking")
    foreach ($process in (Get-ChatGPTWindows)) {
        try {
            $rootElement = [System.Windows.Automation.AutomationElement]::FromHandle($process.MainWindowHandle)
            foreach ($name in $names) {
                $condition = New-Object System.Windows.Automation.PropertyCondition(
                    [System.Windows.Automation.AutomationElement]::NameProperty, $name
                )
                if ($null -ne $rootElement.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)) {
                    return $true
                }
            }
        } catch {}
    }
    return $false
}

function Save-Settings {
    @{ Left = $window.Left; Top = $window.Top; Size = $window.Width; ManualState = $script:manualState } |
        ConvertTo-Json | Set-Content -LiteralPath $settingsPath -Encoding UTF8
}

function Set-PetSize([double]$size) {
    $window.Width = $size
    $window.Height = $size
}

function Set-State([string]$state) {
    if (-not $frames.ContainsKey($state)) { return }
    if ($script:currentState -ne $state) {
        $script:currentState = $state
        $script:frameIndex = 0
        $birdImage.Source = $frames[$state][0]
        $animationTimer.Interval = [TimeSpan]::FromMilliseconds($durations[$state])
        $window.Title = "咕咕叽桌面宠物 · $($labels[$state])"
    }
}

function Get-AutoState {
    $idleSeconds = [PetNative]::IdleSeconds()
    if ($idleSeconds -ge 180) { return "waiting" }
    if (-not $script:chatIntegrationInstalled) {
        if ($idleSeconds -lt 3) { return "typing" }
        return "idle"
    }
    $generating = Test-ChatGPTGenerating
    if ($generating) {
        if (-not $script:wasGenerating) {
            $script:generationStarted = [DateTime]::Now
        }
        $script:wasGenerating = $true
        if (([DateTime]::Now - $script:generationStarted).TotalSeconds -lt 3) {
            return "thinking"
        }
        return "typing"
    }
    if ($script:wasGenerating) {
        $script:wasGenerating = $false
        $script:completeUntil = [DateTime]::Now.AddSeconds(8)
    }
    if ([DateTime]::Now -lt $script:completeUntil) { return "complete" }
    try {
        $pid = [PetNative]::ForegroundProcessId()
        $process = Get-Process -Id $pid -ErrorAction Stop
        if ($process.ProcessName -match "^(ChatGPT|codex|codex-code-mode-host)$") {
            if ($idleSeconds -lt 3) { return "typing" }
            return "idle"
        }
    } catch {}
    return "idle"
}

function Set-ManualMode([string]$mode) {
    $script:manualState = $mode
    foreach ($item in $stateMenuItems.Values) { $item.IsChecked = $false }
    if ($mode -eq "auto") {
        $autoMenu.IsChecked = $true
        Set-State (Get-AutoState)
    } else {
        $autoMenu.IsChecked = $false
        $stateMenuItems[$mode].IsChecked = $true
        Set-State $mode
    }
    Save-Settings
}

function New-MenuItem([string]$header) {
    $item = New-Object System.Windows.Controls.MenuItem
    $item.Header = $header
    return $item
}

$menu = New-Object System.Windows.Controls.ContextMenu
$autoMenu = New-MenuItem "自动切换"
$autoMenu.IsCheckable = $true
$autoMenu.IsChecked = $true
$autoMenu.Add_Click({ Set-ManualMode "auto" })
[void]$menu.Items.Add($autoMenu)
[void]$menu.Items.Add((New-Object System.Windows.Controls.Separator))

$stateMenuItems = @{}
foreach ($entry in @(
    @{ Key="idle"; Text="待机" }, @{ Key="typing"; Text="工作 · 敲键盘" },
    @{ Key="thinking"; Text="思考" }, @{ Key="complete"; Text="完成 · 庆祝" },
    @{ Key="waiting"; Text="等待 · 睡觉" }
)) {
    $item = New-MenuItem $entry.Text
    $item.IsCheckable = $true
    $key = $entry.Key
    $item.Add_Click({ Set-ManualMode $key }.GetNewClosure())
    $stateMenuItems[$key] = $item
    [void]$menu.Items.Add($item)
}

[void]$menu.Items.Add((New-Object System.Windows.Controls.Separator))
$sizeMenu = New-MenuItem "大小"
foreach ($entry in @(@{Text="小";Value=140}, @{Text="中";Value=200}, @{Text="大";Value=260})) {
    $item = New-MenuItem $entry.Text
    $value = $entry.Value
    $item.Add_Click({ Set-PetSize $value; Save-Settings }.GetNewClosure())
    [void]$sizeMenu.Items.Add($item)
}
[void]$menu.Items.Add($sizeMenu)

$pauseMenu = New-MenuItem "暂停动画"
$pauseMenu.IsCheckable = $true
$pauseMenu.Add_Click({
    $script:paused = $pauseMenu.IsChecked
    if ($script:paused) { $birdImage.Source = $frames[$script:currentState][0] }
})
[void]$menu.Items.Add($pauseMenu)

$startupMenu = New-MenuItem "随 ChatGPT 自动显示"
$startupMenu.IsCheckable = $true
$startupMenu.IsChecked = Test-Path -LiteralPath $startupShortcut
$startupMenu.Add_Click({
    if ($startupMenu.IsChecked) {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($startupShortcut)
        $shortcut.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
        $shortcut.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
        $shortcut.WorkingDirectory = $root
        $shortcut.Save()
    } elseif (Test-Path -LiteralPath $startupShortcut) {
        Remove-Item -LiteralPath $startupShortcut -Force
    }
})
[void]$menu.Items.Add($startupMenu)

[void]$menu.Items.Add((New-Object System.Windows.Controls.Separator))
$exitMenu = New-MenuItem "退出小鸟"
$exitMenu.Add_Click({ $window.Close() })
[void]$menu.Items.Add($exitMenu)
$birdImage.ContextMenu = $menu

$animationTimer = New-Object System.Windows.Threading.DispatcherTimer
$animationTimer.Interval = [TimeSpan]::FromMilliseconds($durations.idle)
$animationTimer.Add_Tick({
    if ($script:paused) { return }
    $script:frameIndex++
    if ($script:frameIndex -ge $frames[$script:currentState].Count) {
        $script:frameIndex = 0
    }
    $birdImage.Source = $frames[$script:currentState][$script:frameIndex]
})

$autoTimer = New-Object System.Windows.Threading.DispatcherTimer
$autoTimer.Interval = [TimeSpan]::FromSeconds(1)
$autoTimer.Add_Tick({
    if ($script:chatIntegrationInstalled -and -not (Test-ChatGPTRunning)) {
        if ($window.IsVisible) { $window.Hide() }
        return
    }
    if (-not $window.IsVisible) { $window.Show() }
    if ($script:manualState -eq "auto") {
        Set-State (Get-AutoState)
    }
})

$window.Add_MouseLeftButtonDown({
    if ($_.ClickCount -ge 2) {
        Set-State "complete"
        $_.Handled = $true
    } else {
        try { $window.DragMove() } catch {}
    }
})

$window.Add_LocationChanged({ Save-Settings })
$window.Add_Closing({ Save-Settings; $animationTimer.Stop(); $autoTimer.Stop() })

$workArea = [System.Windows.SystemParameters]::WorkArea
$window.Left = $workArea.Right - $window.Width - 24
$window.Top = $workArea.Bottom - $window.Height - 24

if (Test-Path -LiteralPath $settingsPath) {
    try {
        $settings = Get-Content -Raw -LiteralPath $settingsPath | ConvertFrom-Json
        if ($settings.Size -ge 100 -and $settings.Size -le 400) { Set-PetSize $settings.Size }
        if ($settings.Left -ge $workArea.Left -and $settings.Left -lt $workArea.Right) { $window.Left = $settings.Left }
        if ($settings.Top -ge $workArea.Top -and $settings.Top -lt $workArea.Bottom) { $window.Top = $settings.Top }
    } catch {}
}

$birdImage.Source = $frames.idle[0]
$script:chatIntegrationInstalled = Test-ChatGPTInstalled
$window.Add_ContentRendered({
    if ($script:chatIntegrationInstalled -and -not (Test-ChatGPTRunning)) { $window.Hide() }
})
$animationTimer.Start()
$autoTimer.Start()
[void]$window.ShowDialog()
$mutex.ReleaseMutex()
$mutex.Dispose()
