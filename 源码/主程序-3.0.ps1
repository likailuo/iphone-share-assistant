# iPhone 共享助手 3.0（单文件主程序，含 WPF 界面层）。
# 视觉设计来源：资源/UI原型/iphone-share-ui.html
# 运行：powershell.exe -ExecutionPolicy Bypass -File ".\源码\主程序-3.0.ps1"（需管理员权限）
#requires -Version 5.1
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing
$ErrorActionPreference = 'Stop'
# 管理元数据保存到 ProgramData；不保存 Windows 密码或文件内容。
# 本软件创建的共享仍使用 SMB 共享自身的 Description 作为归属标记。
$script:ManagedShareMarker = 'iPhone共享助手'
$script:ManagedMetadataDir = Join-Path $env:ProgramData 'iPhone共享助手'
$script:ManagedMetadataPath = Join-Path $script:ManagedMetadataDir 'managed-shares.json'
$script:Theme = 'Dark'
$script:AppVersion = '3.8'
try {
    $fileVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($PSCommandPath).FileVersion
    if ($fileVersion -match '^\d+\.\d+') { $script:AppVersion = $matches[0] }
} catch {}
try {
    $mainModule = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileVersionInfo
    if ($mainModule.FileName -like '*iPhone共享助手*.exe' -and $mainModule.FileVersion -match '^\d+\.\d+') {
        $script:AppVersion = $matches[0]
    }
} catch {}

# 无边框透明窗口需要手工处理 WM_NCHITTEST 才能支持边缘拖拽缩放。
# PowerShell 的 scriptblock 委托无法可靠回传 ref bool handled，因此用 C# 类实现。
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Interop;

public static class WindowResizer
{
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    private static HwndSourceHook _hook;
    private static IntPtr _hWnd;

    public static void Attach(IntPtr hwnd, int border)
    {
        _hWnd = hwnd;
        HwndSource source = HwndSource.FromHwnd(hwnd);
        if (source == null) return;
        _hook = new HwndSourceHook(OnMessage);
        source.AddHook(_hook);
    }

    private static IntPtr OnMessage(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == 0x0084) // WM_NCHITTEST
        {
            int x = (short)(lParam.ToInt64() & 0xFFFF);
            int y = (short)((lParam.ToInt64() >> 16) & 0xFFFF);
            RECT r;
            if (!GetWindowRect(hwnd, out r)) { handled = true; return (IntPtr)1; }
            int bx = 6;
            int ht = 1;
            if (x >= r.Left && x < r.Left + bx)
            {
                if (y < r.Top + bx) ht = 13;
                else if (y >= r.Bottom - bx) ht = 16;
                else ht = 10;
            }
            else if (x >= r.Right - bx && x < r.Right)
            {
                if (y < r.Top + bx) ht = 14;
                else if (y >= r.Bottom - bx) ht = 17;
                else ht = 11;
            }
            else if (y >= r.Top && y < r.Top + bx) ht = 12;
            else if (y >= r.Bottom - bx && y < r.Bottom) ht = 15;
            handled = true;
            return (IntPtr)ht;
        }
        return IntPtr.Zero;
    }
}
'@ -ReferencedAssemblies 'PresentationFramework','PresentationCore','WindowsBase'

# 深色模式下将常用浅色 hex 映射到深色等价色。
$script:DarkMap = @{
    '#F8FAFD' = '#14181F'
    '#FFFFFF' = '#1D2430'
    '#E3E9F2' = '#2C3543'
    '#172033' = '#E6EDF6'
    '#7A8699' = '#93A0B5'
    '#4A5A70' = '#A7B4C8'
    '#F0F4FF' = '#263047'
    '#4055D6' = '#8FA8FF'
    '#5268F4' = '#7C8CFF'
    '#F2F5FA' = '#232B3A'
    '#E4E9F2' = '#333D4E'
    '#2F405D' = '#C2CEDF'
    # 卡片次要按钮文字；深色背景上不能继续使用浅色主题的深蓝色。
    '#334155' = '#D7E0EE'
    '#DCE3EE' = '#3A4557'
    '#E4F6EC' = '#1D3326'
    '#1F9254' = '#3DD68C'
    '#FFF1E0' = '#3A2E1C'
    '#D97706' = '#F0A83D'
    '#EEF2F7' = '#2A3342'
    '#64748B' = '#93A0B5'
    '#EEF3FF' = '#232E4A'
    '#FFF4E5' = '#3A2E1C'
    '#E18A3B' = '#F0A83D'
    '#FFF7F6' = '#332A2A'
    '#E4B7B7' = '#6B4747'
    '#C24545' = '#FF8A80'
    '#FDECEA' = '#3A2A2A'
    '#FFF4E0' = '#3A2E1C'
}

function Test-IsAdministrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Test-ManagedShareObject($share) {
    $share -and ([string]$share.Description -eq $script:ManagedShareMarker)
}
function Get-ManagedShare([string]$name) {
    try {
        $share = Get-SmbShare -Name $name -ErrorAction SilentlyContinue
        if (Test-ManagedShareObject $share) { return $share }
    } catch {}
    $null
}

function Get-ManagedMetadata {
    if (-not (Test-Path -LiteralPath $script:ManagedMetadataPath -PathType Leaf)) { return @() }
    try {
        $raw = Get-Content -LiteralPath $script:ManagedMetadataPath -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
        $parsed = $raw | ConvertFrom-Json
        if ($parsed -is [System.Array]) { return @($parsed) }
        if ($parsed.PSObject.Properties['Name'] -and $parsed.PSObject.Properties['Path']) { return @($parsed) }

        # 兼容旧版以共享名为属性名的 managed-shares.json。
        $legacyRecords = @()
        foreach ($property in $parsed.PSObject.Properties) {
            $legacyPath = [string]$property.Value
            if ($property.Value.PSObject.Properties['Path']) { $legacyPath = [string]$property.Value.Path }
            $legacyRecords += [pscustomobject]@{
                Name = [string]$property.Name
                Path = $legacyPath
                Paused = $false
                CreatedAt = (Get-Date).ToString('o')
                AccessLines = @()
            }
        }
        if ($legacyRecords.Count) { Save-ManagedMetadata $legacyRecords }
        return @($legacyRecords)
    } catch {
        throw "读取共享管理记录失败：$($_.Exception.Message)"
    }
}

function Save-ManagedMetadata($records) {
    try {
        if (-not (Test-Path -LiteralPath $script:ManagedMetadataDir -PathType Container)) {
            New-Item -ItemType Directory -Path $script:ManagedMetadataDir -Force | Out-Null
        }
        $cleanRecords = @($records | ForEach-Object {
            [pscustomobject]@{
                Name = [string]$_.Name
                Path = [string]$_.Path
                Paused = [bool]$_.Paused
                CreatedAt = if ($_.CreatedAt) { [string]$_.CreatedAt } else { (Get-Date).ToString('o') }
                AccessLines = @($_.AccessLines | ForEach-Object { [string]$_ })
            }
        })
        # 强制写成数组，避免只有一条记录时 JSON 退化成单个对象。
        $json = if ($cleanRecords.Count) { ConvertTo-Json -InputObject @($cleanRecords) -Depth 6 } else { '[]' }
        $tempPath = "$script:ManagedMetadataPath.tmp"
        Set-Content -LiteralPath $tempPath -Value $json -Encoding UTF8
        Move-Item -LiteralPath $tempPath -Destination $script:ManagedMetadataPath -Force
    } catch {
        try { Remove-Item -LiteralPath "$script:ManagedMetadataPath.tmp" -Force -ErrorAction SilentlyContinue } catch {}
        throw "保存共享管理记录失败：$($_.Exception.Message)"
    }
}

function Get-ManagedRecord([string]$name) {
    @(Get-ManagedMetadata | Where-Object { $_.Name -eq $name } | Select-Object -First 1)
}

function Set-ManagedRecord($record) {
    if (-not $record -or [string]::IsNullOrWhiteSpace([string]$record.Name)) { throw '共享管理记录无效。' }
    $records = @(Get-ManagedMetadata | Where-Object { $_.Name -ne $record.Name })
    $records += [pscustomobject]@{
        Name = [string]$record.Name
        Path = [string]$record.Path
        Paused = [bool]$record.Paused
        CreatedAt = if ($record.CreatedAt) { [string]$record.CreatedAt } else { (Get-Date).ToString('o') }
        AccessLines = @($record.AccessLines | ForEach-Object { [string]$_ })
    }
    Save-ManagedMetadata $records
}

function Remove-ManagedRecord([string]$name) {
    $records = @(Get-ManagedMetadata | Where-Object { $_.Name -ne $name })
    Save-ManagedMetadata $records
}

function Initialize-ManagedMetadata {
    # 读取一次以完成旧格式迁移；没有记录时不创建空文件。
    [void](Get-ManagedMetadata)
}
$script:CurrentAccountName = $null
function Get-CurrentAccountName {
    if ($script:CurrentAccountName) { return $script:CurrentAccountName }
    try { $script:CurrentAccountName = [Security.Principal.WindowsIdentity]::GetCurrent().Name }
    catch { $script:CurrentAccountName = "$env:COMPUTERNAME\$env:USERNAME" }
    $script:CurrentAccountName
}
function Get-PrimaryIp {
    try {
        $ips = @(Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
            $_.IPAddress -ne '127.0.0.1' -and
            $_.IPAddress -notlike '169.254.*' -and
            $_.InterfaceAlias -notmatch 'Loopback|Hyper-V|WSL|vEthernet'
        })
        $defaultRouteIndexes = @{}
        foreach ($route in @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue)) {
            $defaultRouteIndexes[[int]$route.InterfaceIndex] = $true
        }
        foreach ($ip in $ips) {
            if ($defaultRouteIndexes.ContainsKey([int]$ip.InterfaceIndex)) {
                return $ip.IPAddress
            }
        }
        if ($ips.Count) { return $ips[0].IPAddress }
    } catch {}
    '未连接'
}
function Import-SmbShareModule {
    if (Get-Module SmbShare) { return }
    $moduleRoot = Join-Path $PSHOME 'Modules\SmbShare'
    $candidates = @([Globalization.CultureInfo]::CurrentUICulture.Name, 'en-US')
    if (Test-Path -LiteralPath $moduleRoot) {
        foreach ($d in @(Get-ChildItem -LiteralPath $moduleRoot -Directory -ErrorAction SilentlyContinue)) {
            if (Test-Path -LiteralPath (Join-Path $d.FullName 'SmbLocalization.psd1')) { $candidates += $d.Name }
        }
    }
    $prevCulture = [Threading.Thread]::CurrentThread.CurrentUICulture
    $lastError = $null
    foreach ($culture in @($candidates | Select-Object -Unique)) {
        try {
            [Threading.Thread]::CurrentThread.CurrentUICulture = [Globalization.CultureInfo]::GetCultureInfo($culture)
            Import-Module SmbShare -ErrorAction Stop
            [Threading.Thread]::CurrentThread.CurrentUICulture = $prevCulture
            return
        } catch { $lastError = $_ }
    }
    [Threading.Thread]::CurrentThread.CurrentUICulture = $prevCulture
    throw "无法加载 SMB 共享模块（SmbShare）：$($lastError.Exception.Message)"
}
function Get-SharesSafe {
    try {
        Import-SmbShareModule
        @(Get-SmbShare -ErrorAction Stop | Sort-Object Name)
    }
    catch {
        try { @(Get-CimInstance Win32_Share -ErrorAction Stop | ForEach-Object { [pscustomobject]@{ Name=$_.Name; Path=$_.Path; Description=$_.Description; Special=($_.Type -ne 0) } } | Sort-Object Name) }
        catch { throw "SMB 共享扫描失败：$($_.Exception.Message)" }
    }
}
function Get-ShareRows([string]$ip) {
    if ([string]::IsNullOrWhiteSpace($ip)) { $ip = Get-PrimaryIp }
    $metadata = @(Get-ManagedMetadata)
    $metadataByName = @{}
    foreach ($record in $metadata) { if ($record.Name) { $metadataByName[[string]$record.Name] = $record } }
    $shares = @(Get-SharesSafe)
    $rows = @()
    $metadataChanged = $false

    foreach ($share in $shares) {
        if ($share.Special -or $share.Name -match '^(ADMIN|IPC|[A-Z])\$$') { continue }
        $managed = Test-ManagedShareObject $share
        $exists = $share.Path -and (Test-Path -LiteralPath $share.Path)
        $record = if ($managed) { $metadataByName[[string]$share.Name] } else { $null }
        $accessLines = @()
        if ($managed) {
            try { $accessLines = @(Get-ShareAccessLines $share.Name) } catch {}
            if (-not $record) {
                $record = [pscustomobject]@{
                    Name = [string]$share.Name
                    Path = [string]$share.Path
                    Paused = $false
                    CreatedAt = (Get-Date).ToString('o')
                    AccessLines = $accessLines
                }
                $metadata += $record
                $metadataByName[[string]$share.Name] = $record
                $metadataChanged = $true
            } else {
                if ([string]$record.Path -ne [string]$share.Path -or [bool]$record.Paused) { $metadataChanged = $true }
                $record.Path = [string]$share.Path
                $record.Paused = $false
                if ($accessLines.Count) { $record.AccessLines = $accessLines; $metadataChanged = $true }
            }
        }
        $rows += [pscustomobject]@{
            Name=$share.Name; Path=[string]$share.Path
            Status=if ($exists) {'已开启'} elseif ($share.Path) {'路径丢失'} else {'不可用'}
            Managed=[bool]$managed
            Paused=$false
            CreatedAt=if ($record) { [string]$record.CreatedAt } else { $null }
            AccessLines=if ($record) { @($record.AccessLines) } else { @() }
            Address="smb://$ip/$($share.Name)"
        }
    }

    foreach ($record in $metadata) {
        if (-not $record.Name -or ($shares | Where-Object { $_.Name -eq $record.Name } | Select-Object -First 1)) { continue }
        $rows += [pscustomobject]@{
            Name=[string]$record.Name; Path=[string]$record.Path; Status='已暂停'; Managed=$true; Paused=$true
            CreatedAt=[string]$record.CreatedAt; AccessLines=@($record.AccessLines)
            Address="smb://$ip/$($record.Name)"
        }
    }
    if ($metadataChanged) { Save-ManagedMetadata $metadata }
    @($rows | Sort-Object Name)
}
function Resolve-AccountSid([string]$user) {
    foreach ($candidate in @("$env:COMPUTERNAME\$user", "$env:USERDOMAIN\$user", $user)) {
        try { return ([Security.Principal.NTAccount]::new($candidate)).Translate([Security.Principal.SecurityIdentifier]) }
        catch {}
    }
    $null
}
function Set-FolderAccess([string]$path, [string[]]$users) {
    $acl = Get-Acl -LiteralPath $path
    foreach ($user in $users) {
        if ([string]::IsNullOrWhiteSpace($user)) { continue }
        $sid = Resolve-AccountSid $user.Trim()
        if (-not $sid) { throw "找不到 Windows 用户：$user" }
        $acl.SetAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid,[Security.AccessControl.FileSystemRights]::Modify,'ContainerInherit,ObjectInherit','None','Allow')))
    }
    Set-Acl -LiteralPath $path -AclObject $acl
}
function Enable-SmbForIPhone {
    if ((Get-Service LanmanServer).Status -ne 'Running') { Start-Service LanmanServer }
    Set-Service LanmanServer -StartupType Automatic
    if (Get-NetFirewallRule -DisplayName 'SMB (iPhone)' -ErrorAction SilentlyContinue) { Enable-NetFirewallRule -DisplayName 'SMB (iPhone)' | Out-Null }
    else { New-NetFirewallRule -DisplayName 'SMB (iPhone)' -Direction Inbound -Protocol TCP -LocalPort 445 -Action Allow -Profile Private | Out-Null }
}
function Test-ShareName([string]$name) {
    if ([string]::IsNullOrWhiteSpace($name)) { return $false }
    $value = $name.Trim()
    if ($value.Length -gt 80 -or $value -in @('.', '..')) { return $false }
    if ($value -match '[\\/:*?"<>|]') { return $false }
    if ($value -match '^(ADMIN|IPC|[A-Z])\$$') { return $false }
    return $true
}
function Get-AccessAccountNames([string[]]$lines) {
    @($lines | ForEach-Object {
        $line = ([string]$_).Trim()
        if ([string]::IsNullOrWhiteSpace($line)) { return }
        # 兼容旧记录的“账户 · 权限”和新记录的“账户|权限”显示格式，
        # 传给 SMB/NTFS 命令时只保留真实 Windows 账户名。
        if ($line -match '^(.+?)\s+·\s+(读写|只读)\s*$') { $line = $matches[1].Trim() }
        elseif ($line -match '^(.+?)\|(?:读写|只读)\s*$') { $line = $matches[1].Trim() }
        if ($line) { $line }
    } | Select-Object -Unique)
}
function Set-ManagedShare([string]$path, [string]$name, [string[]]$lines) {
    if (-not [IO.Path]::IsPathRooted($path) -or -not (Test-Path -LiteralPath $path -PathType Container)) { throw "文件夹不存在或不是绝对路径：$path" }
    if (-not (Test-ShareName $name)) { throw '共享名称无效：不能为空、不能包含 \\/:*?"<>|，也不能使用系统管理共享名称。' }
    $name = $name.Trim()
    Import-SmbShareModule
    $existing = Get-SmbShare -Name $name -ErrorAction SilentlyContinue
    if ($existing -and -not (Get-ManagedShare $name)) { throw "同名外部共享 [$name] 已存在，未做任何修改。" }
    if (-not $lines -or $lines.Count -eq 0) { $lines = @("$(Get-CurrentAccountName)|读写") }
    $users = @(Get-AccessAccountNames $lines)
    if ($users.Count -eq 0) { $users = @(Get-CurrentAccountName) }
    $created = $false
    try {
        if (-not $existing) {
            New-SmbShare -Name $name -Path $path -Description $script:ManagedShareMarker -FullAccess $users | Out-Null
            $created = $true
        }
        elseif ($existing.Path -ne $path) {
            throw "共享 [$name] 已指向其他文件夹，请先关闭后再创建。"
        }
        foreach ($u in $users) { Grant-SmbShareAccess -Name $name -AccountName $u -AccessRight Full -Force | Out-Null }
        Set-FolderAccess $path $users
        Enable-SmbForIPhone
        $oldRecord = Get-ManagedRecord $name
        Set-ManagedRecord ([pscustomobject]@{
            Name = $name
            Path = $path
            Paused = $false
            CreatedAt = if ($oldRecord) { $oldRecord.CreatedAt } else { (Get-Date).ToString('o') }
            AccessLines = @(Get-ShareAccessLines $name)
        })
    } catch {
        if ($created) { Remove-SmbShare -Name $name -Force -ErrorAction SilentlyContinue }
        throw
    }
}
function Remove-Share([string]$name) {
    if ([string]::IsNullOrWhiteSpace($name)) { throw '共享名称无效，无法关闭，请刷新列表后重试。' }
    if (-not (Test-ShareName $name)) { throw '共享名称无效，无法关闭，请刷新列表后重试。' }
    Import-SmbShareModule
    $share = Get-SmbShare -Name $name -ErrorAction Stop
    if ($share.Special -or $name -match '^(ADMIN|IPC|[A-Z])\$$') { throw '系统管理共享不能由本软件关闭。' }
    Remove-SmbShare -Name $name -Force
}
function Pause-ManagedShare([string]$name) {
    $record = Get-ManagedRecord $name
    if (-not $record) { throw "共享 [$name] 不是本软件管理的共享，无法暂停。" }
    Import-SmbShareModule
    $share = Get-SmbShare -Name $name -ErrorAction SilentlyContinue
    if ($share -and ($share.Special -or $name -match '^(ADMIN|IPC|[A-Z])\$$')) { throw '系统管理共享不能由本软件暂停。' }
    if ($share) { Remove-SmbShare -Name $name -Force }
    $record.Paused = $true
    Set-ManagedRecord $record
}
function Resume-ManagedShare([string]$name) {
    $record = Get-ManagedRecord $name
    if (-not $record) { throw "找不到共享 [$name] 的管理记录，无法重新开启。" }
    if (-not [IO.Path]::IsPathRooted([string]$record.Path) -or -not (Test-Path -LiteralPath $record.Path -PathType Container)) {
        throw "文件夹不存在或不是绝对路径：$($record.Path)"
    }
    $lines = @($record.AccessLines | Where-Object { $_ })
    if (-not $lines.Count) { $lines = @("$(Get-CurrentAccountName)|读写") }
    Set-ManagedShare $record.Path $record.Name $lines
}
function Delete-ManagedShare([string]$name) {
    $record = Get-ManagedRecord $name
    if (-not $record) { throw "找不到共享 [$name] 的管理记录，无法删除。" }
    Import-SmbShareModule
    $share = Get-SmbShare -Name $name -ErrorAction SilentlyContinue
    if ($share -and ($share.Special -or $name -match '^(ADMIN|IPC|[A-Z])\$$')) { throw '系统管理共享不能由本软件删除。' }
    if ($share) { Remove-SmbShare -Name $name -Force }
    Remove-ManagedRecord $name
}
function Get-ShareAccessLines([string]$name) {
    Import-SmbShareModule
    @(Get-SmbShareAccess -Name $name -ErrorAction Stop |
        Where-Object {
            $_.AccessControlType -eq 'Allow' -and
            $_.AccountName -notmatch 'Everyone|SYSTEM|CREATOR|Administrators|NT AUTHORITY|INTERACTIVE|^(S-1|BUILTIN|\\\\Everyone)'
        } |
        ForEach-Object {
            $right = if ($_.AccessRight -eq 'Full') { '读写' } else { '只读' }
            "$($_.AccountName) · $right"
        })
}
function Update-ShareConfig([string]$name, [string]$newName, [string]$newPath) {
    Import-SmbShareModule
    $share = Get-SmbShare -Name $name -ErrorAction Stop
    if (-not $share) { throw "共享 [$name] 不存在，请刷新列表后重试。" }
    if (-not (Test-ShareName $newName)) { throw '共享名称无效：不能为空、不能包含 \\/:*?"<>|，也不能使用系统管理共享名称。' }
    $newName = $newName.Trim()
    if ($newName -match '^(ADMIN|IPC|[A-Z])\$$') { throw '不能使用系统管理共享名称。' }
    $targetPath = if ([string]::IsNullOrWhiteSpace($newPath)) { [string]$share.Path } else { $newPath.Trim().TrimEnd('\') }
    if (-not [IO.Path]::IsPathRooted($targetPath) -or -not (Test-Path -LiteralPath $targetPath -PathType Container)) {
        throw "文件夹不存在或不是绝对路径：$targetPath"
    }
    if ($newName -ne $name) {
        $conflict = Get-SmbShare -Name $newName -ErrorAction SilentlyContinue
        if ($conflict) { throw "共享名 [$newName] 已被其他共享占用，请换一个名称。" }
    }
    $lines = Get-ShareAccessLines $name
    $users = @(Get-AccessAccountNames $lines)
    if ($users.Count -eq 0) { $users = @(Get-CurrentAccountName) }
    if ($newName -ne $name) {
        $newShareCreated = $false
        try {
            New-SmbShare -Name $newName -Path $targetPath -Description $share.Description -FullAccess $users | Out-Null
            $newShareCreated = $true
            foreach ($u in $users) { Grant-SmbShareAccess -Name $newName -AccountName $u -AccessRight Full -Force | Out-Null }
            if ($targetPath -ne [string]$share.Path) { Set-FolderAccess $targetPath $users }
            Remove-SmbShare -Name $name -Force
        } catch {
            if ($newShareCreated) { Remove-SmbShare -Name $newName -Force -ErrorAction SilentlyContinue }
            throw
        }
    } elseif ($targetPath -ne [string]$share.Path) {
        $oldPath = [string]$share.Path
        try {
            Set-SmbShare -Name $name -Path $targetPath -Force | Out-Null
            foreach ($u in $users) { Grant-SmbShareAccess -Name $name -AccountName $u -AccessRight Full -Force | Out-Null }
            Set-FolderAccess $targetPath $users
        } catch {
            Set-SmbShare -Name $name -Path $oldPath -Force -ErrorAction SilentlyContinue | Out-Null
            throw
        }
    }
    Enable-SmbForIPhone
    $managedRecord = Get-ManagedRecord $name
    if ($managedRecord) {
        if ($newName -ne $name) { Remove-ManagedRecord $name }
        Set-ManagedRecord ([pscustomobject]@{
            Name = $newName
            Path = $targetPath
            Paused = $false
            CreatedAt = $managedRecord.CreatedAt
            AccessLines = @(Get-ShareAccessLines $newName)
        })
    }
}
if (-not (Test-IsAdministrator)) { [Windows.MessageBox]::Show('请右键选择“以管理员身份运行”。共享、账户和防火墙操作需要管理员权限。','需要管理员权限')|Out-Null;exit 1 }
Initialize-ManagedMetadata

$xaml = @'
 <Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="iPhone 共享助手 __APP_VERSION__" Width="1060" Height="700" MinWidth="860" MinHeight="560" WindowStartupLocation="CenterScreen" Background="Transparent" FontFamily="Segoe UI" WindowStyle="None" ResizeMode="CanResize" AllowsTransparency="True">
 <Window.Resources>
  <Style TargetType="ScrollViewer"><Setter Property="Background" Value="Transparent"/></Style>
  <Style x:Key="TitleBarButton" TargetType="Button">
   <Setter Property="Width" Value="42"/>
   <Setter Property="Height" Value="46"/>
   <Setter Property="Background" Value="Transparent"/>
   <Setter Property="BorderThickness" Value="0"/>
   <Setter Property="Cursor" Value="Hand"/>
   <Setter Property="Template">
    <Setter.Value>
     <ControlTemplate TargetType="Button">
      <Border Background="{TemplateBinding Background}">
       <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Border>
      <ControlTemplate.Triggers>
       <Trigger Property="IsMouseOver" Value="True">
        <Setter Property="Background" Value="#26FFFFFF"/>
        <Setter Property="Foreground" Value="White"/>
       </Trigger>
      </ControlTemplate.Triggers>
     </ControlTemplate>
    </Setter.Value>
   </Setter>
  </Style>
  <Style x:Key="TitleBarCloseButton" TargetType="Button" BasedOn="{StaticResource TitleBarButton}">
   <Style.Triggers>
    <Trigger Property="IsMouseOver" Value="True">
     <Setter Property="Background" Value="#C42B1C"/>
    </Trigger>
   </Style.Triggers>
  </Style>
  </Window.Resources>
  <Border x:Name="WindowRoot" Background="#F8FAFD" CornerRadius="12">
  <Grid>
   <Grid.RowDefinitions>
    <RowDefinition Height="46"/>
    <RowDefinition Height="*"/>
    <RowDefinition Height="54"/>
   </Grid.RowDefinitions>
   <!-- 顶栏 -->
    <Border x:Name="TitleBar" Grid.Row="0" Background="#142238" CornerRadius="12,12,0,0">
     <Grid Margin="18,0">
      <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
       <Border x:Name="AppTitleIcon" Width="30" Height="30" CornerRadius="8" Background="Transparent" Margin="0,0,10,0">
        <Grid>
         <TextBlock Text="&#xE8B7;" FontFamily="Segoe MDL2 Assets" FontSize="20" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/>
         <TextBlock Text="&#xE8EA;" FontFamily="Segoe MDL2 Assets" FontSize="9" Foreground="White" HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,4,3"/>
        </Grid>
       </Border>
        <!-- Segoe UI 字体的可见字形基线略高，向下补 2px 后与左侧图标视觉居中。 -->
        <TextBlock x:Name="AppTitleText" Text="iPhone 共享助手 __APP_VERSION__" Foreground="White" FontSize="14" FontWeight="SemiBold" Margin="0,2,0,0" VerticalAlignment="Center"/>
      </StackPanel>
      <Border x:Name="IpChip" HorizontalAlignment="Center" VerticalAlignment="Center" Background="#1C2B47" CornerRadius="8" Padding="10,4">
       <StackPanel Orientation="Horizontal">
        <TextBlock Text="&#xE8EA;" FontFamily="Segoe MDL2 Assets" FontSize="11" Foreground="#8FA0BA" VerticalAlignment="Center"/>
        <TextBlock x:Name="IpChipText" Text="本机IP：—" FontSize="12" FontWeight="SemiBold" Foreground="#DCE6F5" Margin="6,0,0,0" VerticalAlignment="Center"/>
       </StackPanel>
      </Border>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
       <Button x:Name="ThemeButton" Style="{StaticResource TitleBarButton}" ToolTip="切换深色/浅色模式" Foreground="#8FA0BA" Margin="8,0,0,0"><TextBlock x:Name="ThemeIcon" Text="&#xE708;" FontFamily="Segoe MDL2 Assets" FontSize="12"/></Button>
       <Button x:Name="MinimizeButton" Style="{StaticResource TitleBarButton}" ToolTip="最小化" Foreground="#8FA0BA" Margin="8,0,0,0"><TextBlock Text="&#xE921;" FontFamily="Segoe MDL2 Assets" FontSize="10"/></Button>
       <Button x:Name="MaximizeButton" Style="{StaticResource TitleBarButton}" ToolTip="最大化" Foreground="#8FA0BA"><TextBlock x:Name="MaximizeIcon" Text="&#xE922;" FontFamily="Segoe MDL2 Assets" FontSize="10"/></Button>
       <Button x:Name="CloseButton" Style="{StaticResource TitleBarCloseButton}" ToolTip="关闭" Foreground="#8FA0BA"><TextBlock Text="&#xE8BB;" FontFamily="Segoe MDL2 Assets" FontSize="12"/></Button>
      </StackPanel>
     </Grid>
    </Border>
   <!-- 主体 -->
   <Grid Grid.Row="1">
   <ScrollViewer x:Name="ListView" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
    <StackPanel Margin="28,26,28,22">
     <Grid Margin="0,0,0,22">
      <Grid.ColumnDefinitions>
       <ColumnDefinition/>
       <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
       <StackPanel>
        <TextBlock x:Name="PageTitle" Text="共享文件夹" FontSize="23" FontWeight="Bold" Foreground="#172033"/>
        <TextBlock x:Name="PageSubtitle" Text="开启后，家人的 iPhone 就可以通过 SMB 访问" FontSize="13" Foreground="#7A8699" Margin="0,3,0,0"/>
       </StackPanel>
      <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
        <Button x:Name="AddButton" Height="38" Margin="12,0,0,0" Padding="36,0" FontWeight="Bold" FontSize="14" Cursor="Hand" Background="#5268F4" Foreground="White" BorderThickness="0">
         <Button.Template>
          <ControlTemplate TargetType="Button">
           <Border Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}">
            <Border.Effect><DropShadowEffect BlurRadius="16" ShadowDepth="0" Opacity="0.32" Color="#5268F4"/></Border.Effect>
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
           </Border>
          </ControlTemplate>
         </Button.Template>
         <StackPanel Orientation="Horizontal">
          <TextBlock Text="&#xE710;" FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="White" VerticalAlignment="Center"/>
          <TextBlock Text="选择文件夹并开启共享" FontFamily="Microsoft YaHei" FontSize="14" FontWeight="Bold" Foreground="White" VerticalAlignment="Center" Margin="6,0,0,0"/>
         </StackPanel>
        </Button>
      </StackPanel>
     </Grid>
     <StackPanel x:Name="CardPanel"/>
    </StackPanel>
   </ScrollViewer>
   <!-- 共享详情页 -->
   <Grid x:Name="DetailView" Visibility="Collapsed">
    <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
     <StackPanel Margin="28,26,28,22">
      <StackPanel Orientation="Horizontal" Margin="0,0,0,16">
       <Button x:Name="BackButton" Height="38" Padding="20,0" Cursor="Hand" Background="#F2F5FA" Foreground="#172033" BorderThickness="1" BorderBrush="#DCE3EE" FontSize="13" FontWeight="SemiBold">
        <Button.Template>
          <ControlTemplate TargetType="Button">
           <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
           </Border>
          </ControlTemplate>
        </Button.Template>
         <StackPanel Orientation="Horizontal">
          <TextBlock x:Name="BackIcon" Text="&#xE72B;" FontFamily="Segoe MDL2 Assets" FontSize="12" Foreground="#5268F4" VerticalAlignment="Center"/>
          <TextBlock x:Name="BackLabel" Text="返回共享列表" FontSize="13" FontWeight="SemiBold" Foreground="#172033" VerticalAlignment="Center" Margin="6,0,0,0"/>
         </StackPanel>
       </Button>
      </StackPanel>
      <Grid Margin="0,0,0,20">
       <Grid.ColumnDefinitions>
        <ColumnDefinition/>
        <ColumnDefinition Width="Auto"/>
       </Grid.ColumnDefinitions>
       <StackPanel>
        <StackPanel Orientation="Horizontal">
        <TextBlock x:Name="DetailName" FontSize="23" FontWeight="Bold" Foreground="#172033" VerticalAlignment="Center"/>
        <StackPanel x:Name="DetailBadgeHolder" Orientation="Horizontal" Margin="12,0,0,0" VerticalAlignment="Center"/>
       </StackPanel>
        <TextBlock x:Name="DetailSubtitle" Text="共享详情" FontSize="13" Foreground="#7A8699" Margin="0,3,0,0"/>
       </StackPanel>
       <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
        <Button x:Name="DetailCopyButton" Height="38" Padding="22,0" Margin="10,0,0,0" FontWeight="SemiBold" FontSize="14" Cursor="Hand" Background="#5268F4" Foreground="White" BorderThickness="0">
         <Button.Template>
          <ControlTemplate TargetType="Button">
           <Border Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}">
            <Border.Effect><DropShadowEffect BlurRadius="16" ShadowDepth="0" Opacity="0.32" Color="#5268F4"/></Border.Effect>
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
           </Border>
          </ControlTemplate>
         </Button.Template>
         <StackPanel Orientation="Horizontal">
          <TextBlock Text="&#xE8C8;" FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="White" VerticalAlignment="Center"/>
          <TextBlock Text="复制地址" FontSize="14" FontWeight="SemiBold" Foreground="White" VerticalAlignment="Center" Margin="6,0,0,0"/>
         </StackPanel>
        </Button>
        <Button x:Name="DetailEditButton" Height="38" Padding="22,0" Margin="10,0,0,0" FontWeight="SemiBold" FontSize="14" Cursor="Hand" Background="#FFF7F6" Foreground="#5268F4" BorderThickness="1" BorderBrush="#5268F4">
         <Button.Template>
          <ControlTemplate TargetType="Button">
           <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8" Padding="{TemplateBinding Padding}">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
           </Border>
          </ControlTemplate>
         </Button.Template>
         <StackPanel Orientation="Horizontal">
          <TextBlock x:Name="DetailEditIcon" Text="&#xE70F;" FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="#5268F4" VerticalAlignment="Center"/>
          <TextBlock x:Name="DetailEditLabel" Text="编辑共享" FontSize="14" FontWeight="SemiBold" Foreground="#5268F4" VerticalAlignment="Center" Margin="6,0,0,0"/>
         </StackPanel>
        </Button>
        <Button x:Name="DetailCloseButton" Height="38" Padding="22,0" Margin="10,0,0,0" FontWeight="SemiBold" FontSize="14" Cursor="Hand" Background="#FFF7F6" Foreground="#C24545" BorderThickness="1" BorderBrush="#E4B7B7">
         <Button.Template>
          <ControlTemplate TargetType="Button">
           <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8" Padding="{TemplateBinding Padding}">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
           </Border>
          </ControlTemplate>
         </Button.Template>
         <StackPanel Orientation="Horizontal">
          <TextBlock x:Name="DetailCloseIcon" Text="&#xE74D;" FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="#C24545" VerticalAlignment="Center"/>
          <TextBlock x:Name="DetailCloseLabel" Text="关闭共享" FontSize="14" FontWeight="SemiBold" Foreground="#C24545" VerticalAlignment="Center" Margin="6,0,0,0"/>
         </StackPanel>
        </Button>
       </StackPanel>
      </Grid>
    <Border x:Name="DetailInfoCard" Background="White" BorderBrush="#E3E9F2" BorderThickness="1" CornerRadius="12" Padding="20,18">
    <StackPanel>
     <TextBlock x:Name="DetailInfoTitle" Text="共享信息" FontSize="15" FontWeight="Bold" Foreground="#172033" Margin="0,0,0,12"/>
     <StackPanel x:Name="DetailInfoPanel"/>
    </StackPanel>
   </Border>
     </StackPanel>
    </ScrollViewer>
   </Grid>
   </Grid>
    <!-- 底栏 -->
    <Border x:Name="FooterBar" Grid.Row="2" Background="#142238" BorderBrush="#142238" BorderThickness="0" CornerRadius="0,0,12,12">
    <Grid Margin="28,0">
     <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
      <TextBlock Text="&#xE8EA;" FontFamily="Segoe MDL2 Assets" FontSize="16" Foreground="#5268F4" VerticalAlignment="Center" Margin="0,0,6,0"/>
      <TextBlock x:Name="FooterText" VerticalAlignment="Center" Foreground="#DCE6F5" FontSize="13"/>
      <Border x:Name="AccountChip" Background="#1C2B47" CornerRadius="8" Padding="10,5" Margin="12,0,0,0" VerticalAlignment="Center"><TextBlock x:Name="AccountChipText" Foreground="#DCE6F5" FontSize="12" FontWeight="SemiBold"/></Border>
      <Border x:Name="PasswordChip" Background="#1C2B47" CornerRadius="8" Padding="10,5" Margin="8,0,0,0" VerticalAlignment="Center"><TextBlock x:Name="PasswordChipText" Foreground="#DCE6F5" FontSize="12" FontWeight="SemiBold"/></Border>
     </StackPanel>
     <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
      <TextBlock x:Name="StatusText" VerticalAlignment="Center" Foreground="#8FA8FF" FontSize="12"/>
     </StackPanel>
    </Grid>
   </Border>
   </Grid>
  </Border>
  </Window>
'@
 $xaml = $xaml.Replace('__APP_VERSION__', $script:AppVersion)
 $reader = [Xml.XmlNodeReader]::new([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
$reader.Close()
foreach ($name in @('AddButton','CardPanel','FooterText','StatusText','AccountChip','AccountChipText','PasswordChip','PasswordChipText','ListView','DetailView','DetailName','DetailBadgeHolder','DetailInfoPanel','BackButton','DetailCopyButton','DetailEditButton','DetailCloseButton','PageTitle','PageSubtitle','DetailSubtitle','DetailInfoCard','DetailInfoTitle','BackIcon','BackLabel','DetailEditIcon','DetailEditLabel','DetailCloseIcon','DetailCloseLabel','FooterBar','IpChip','IpChipText','ThemeButton','ThemeIcon','MinimizeButton','MaximizeButton','CloseButton','MaximizeIcon','WindowRoot','AppTitleIcon')) {
    Set-Variable -Name $name -Value $window.FindName($name)
}

# 透明窗口无系统非客户区，挂接 WM_NCHITTEST 恢复边缘缩放
$window.Add_SourceInitialized({
    $helper = New-Object System.Windows.Interop.WindowInteropHelper($window)
    [WindowResizer]::Attach($helper.Handle, 6)
})

# 无边框窗口：标题栏拖动、双击最大化、最小化/最大化/关闭按钮
$titleBar = $window.FindName('TitleBar')
$maxBtn = $window.FindName('MaximizeButton')
$maxIcon = $window.FindName('MaximizeIcon')

$titleBar.Add_MouseLeftButtonDown({
    param($s, $e)
    if ($e.ClickCount -eq 2) {
        if ($window.WindowState -eq 'Maximized') { $window.WindowState = 'Normal' } else { $window.WindowState = 'Maximized' }
    } else {
        try { $window.DragMove() } catch {}
    }
})
$window.FindName('MinimizeButton').Add_Click({ $window.WindowState = 'Minimized' })
$maxBtn.Add_Click({
    if ($window.WindowState -eq 'Maximized') { $window.WindowState = 'Normal' } else { $window.WindowState = 'Maximized' }
})
$window.FindName('CloseButton').Add_Click({ $window.Close() })
$window.Add_StateChanged({
    if ($window.WindowState -eq 'Maximized') {
        $maxIcon.Text = [char]0xE923
        $window.MaxWidth = [Windows.SystemParameters]::MaximizedPrimaryScreenWidth
        $window.MaxHeight = [Windows.SystemParameters]::MaximizedPrimaryScreenHeight
        $WindowRoot.CornerRadius = [Windows.CornerRadius]::new(0)
        $TitleBar.CornerRadius = [Windows.CornerRadius]::new(0)
        $FooterBar.CornerRadius = [Windows.CornerRadius]::new(0)
    } else {
        $maxIcon.Text = [char]0xE922
        $window.MaxWidth = [double]::PositiveInfinity
        $window.MaxHeight = [double]::PositiveInfinity
        $WindowRoot.CornerRadius = [Windows.CornerRadius]::new(12)
        $TitleBar.CornerRadius = [Windows.CornerRadius]::new(12,12,0,0)
        $FooterBar.CornerRadius = [Windows.CornerRadius]::new(0,0,12,12)
    }
})

function Show-Error([string]$title, $errorRecord) {
    $msg = $errorRecord.Exception.Message
    if ([string]::IsNullOrWhiteSpace($msg)) { $msg = $errorRecord.ToString() }
    Show-AppDialog $title $msg ([char]0xEA39) '#FDECEA' '#C24545' '确定' $null | Out-Null
}

# 静态 UI 资源缓存：减少刷新卡片时重复创建 Brush / FontFamily / ControlTemplate。
$script:BrushCache = @{}
$script:FontSegoe = [Windows.Media.FontFamily]::new('Segoe UI')
$script:FontSegoeIcons = [Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
$script:FontMono = [Windows.Media.FontFamily]::new('Cascadia Mono')

$cardButtonTemplateXaml = '<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button"><Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border></ControlTemplate>'
$script:CardButtonTemplate = [Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new([xml]$cardButtonTemplateXaml))

$script:BadgeMap = @{
    '已开启'  = @{ Icon=[char]0xE73E; Bg='#E4F6EC'; Fg='#1F9254'; Text='已开启' }
    '已暂停'  = @{ Icon=[char]0xE7BA; Bg='#FFF1E0'; Fg='#D97706'; Text='已暂停' }
    '路径丢失' = @{ Icon=[char]0xE7BA; Bg='#FFF1E0'; Fg='#D97706'; Text='路径丢失' }
    '不可用' = @{ Icon=[char]0xE7BA; Bg='#EEF2F7'; Fg='#64748B'; Text='不可用' }
}

$script:CardShadowEffect = [Windows.Media.Effects.DropShadowEffect]::new()
$script:CardShadowEffect.BlurRadius = 8
$script:CardShadowEffect.ShadowDepth = 0
$script:CardShadowEffect.Opacity = 0.04
$script:CardShadowEffect.Color = [Windows.Media.ColorConverter]::ConvertFromString('#172033')
if ($script:CardShadowEffect.CanFreeze) { $script:CardShadowEffect.Freeze() }

function Get-Brush([string]$hex) {
    if ($script:Theme -eq 'Dark' -and $script:DarkMap.ContainsKey($hex)) { $hex = $script:DarkMap[$hex] }
    if (-not $script:BrushCache.ContainsKey($hex)) {
        $brush = [Windows.Media.SolidColorBrush]::new(
            [Windows.Media.ColorConverter]::ConvertFromString($hex)
        )
        if ($brush.CanFreeze) { $brush.Freeze() }
        $script:BrushCache[$hex] = $brush
    }
    $script:BrushCache[$hex]
}

function New-CardButton([string]$text, [string]$bg, [string]$fg, [string]$border, [string]$iconChar, [double]$width, $onClick) {
    $btn = [Windows.Controls.Button]::new()
    $btn.Height = 34; $btn.Width = $width; $btn.Margin = [Windows.Thickness]::new(10,0,0,0)
    $btn.Padding = [Windows.Thickness]::new(0,0,0,0)
    $btn.Background = Get-Brush $bg; $btn.Foreground = Get-Brush $fg
    $btn.BorderBrush = if ($border) { Get-Brush $border } else { $null }
    $btn.BorderThickness = [Windows.Thickness]::new(1)
    $btn.FontWeight = [Windows.FontWeights]::SemiBold; $btn.Cursor = [Windows.Input.Cursors]::Hand
    $btn.FontFamily = $script:FontSegoe
    $btn.Template = $script:CardButtonTemplate
    $sp = [Windows.Controls.StackPanel]::new(); $sp.Orientation = [Windows.Controls.Orientation]::Horizontal
    if ($iconChar) {
        $ic = [Windows.Controls.TextBlock]::new(); $ic.Text = $iconChar
        $ic.FontFamily = $script:FontSegoeIcons; $ic.FontSize = 14
        $ic.Foreground = $btn.Foreground; $ic.Margin = [Windows.Thickness]::new(0,0,4,0)
        $ic.VerticalAlignment = [Windows.VerticalAlignment]::Center; [void]$sp.Children.Add($ic)
    }
    $tb = [Windows.Controls.TextBlock]::new(); $tb.Text = $text; $tb.FontSize = 13
    $tb.Foreground = $btn.Foreground; $tb.VerticalAlignment = [Windows.VerticalAlignment]::Center
    [void]$sp.Children.Add($tb)
    $btn.Content = $sp
    if ($onClick) { $btn.Add_Click($onClick) }
    $btn
}

function Show-AppDialog([string]$title, [string]$message, [string]$iconChar, [string]$iconBgHex, [string]$iconFgHex, [string]$confirmText, [string]$cancelText) {
    $dlg = [Windows.Window]::new()
    $dlg.Title = $title
    $dlg.WindowStyle = 'None'
    $dlg.ResizeMode = 'NoResize'
    $dlg.SizeToContent = 'WidthAndHeight'
    $dlg.WindowStartupLocation = 'CenterOwner'
    if ($window -and $window.IsVisible) { $dlg.Owner = $window }
    $dlg.Background = Get-Brush '#F8FAFD'
    $dlg.FontFamily = $script:FontSegoe
    $chrome = [System.Windows.Shell.WindowChrome]::new()
    $chrome.CaptionHeight = 0
    $chrome.ResizeBorderThickness = [Windows.Thickness]::new(0)
    $chrome.CornerRadius = [Windows.CornerRadius]::new(0)
    $chrome.GlassFrameThickness = [Windows.Thickness]::new(0)
    $chrome.UseAeroCaptionButtons = $false
    [System.Windows.Shell.WindowChrome]::SetWindowChrome($dlg, $chrome)

    $root = [Windows.Controls.Grid]::new()
    $r1 = [Windows.Controls.RowDefinition]::new(); $r1.Height = [Windows.GridLength]::Auto
    $r2 = [Windows.Controls.RowDefinition]::new(); $r2.Height = [Windows.GridLength]::Auto
    [void]$root.RowDefinitions.Add($r1); [void]$root.RowDefinitions.Add($r2)

    $titleBar = [Windows.Controls.Border]::new()
    $titleBar.Background = Get-Brush '#142238'
    $titleGrid = [Windows.Controls.Grid]::new()
    $left = [Windows.Controls.StackPanel]::new(); $left.Orientation = 'Horizontal'; $left.Margin = [Windows.Thickness]::new(16,0,0,0); $left.VerticalAlignment = 'Center'
    $dot = [Windows.Controls.Border]::new(); $dot.Width = 9; $dot.Height = 9; $dot.CornerRadius = [Windows.CornerRadius]::new(5); $dot.Background = Get-Brush '#3E8EFF'; $dot.Margin = [Windows.Thickness]::new(0,0,8,0); $dot.VerticalAlignment = 'Center'
    [void]$left.Children.Add($dot)
    $tt = [Windows.Controls.TextBlock]::new(); $tt.Text = $title; $tt.Foreground = [Windows.Media.Brushes]::White; $tt.FontSize = 13; $tt.FontWeight = [Windows.FontWeights]::SemiBold; $tt.VerticalAlignment = 'Center'
    [void]$left.Children.Add($tt)
    [void]$titleGrid.Children.Add($left)
    $xBtn = [Windows.Controls.Button]::new()
    $xBtn.Width = 38; $xBtn.Height = 36; $xBtn.Background = [Windows.Media.Brushes]::Transparent; $xBtn.BorderThickness = [Windows.Thickness]::new(0); $xBtn.Cursor = [Windows.Input.Cursors]::Hand
    $xTb = [Windows.Controls.TextBlock]::new(); $xTb.Text = [char]0xE8BB; $xTb.FontFamily = $script:FontSegoeIcons; $xTb.FontSize = 11; $xTb.Foreground = Get-Brush '#8FA0BA'
    $xBtn.Content = $xTb
    $xBtn.HorizontalAlignment = 'Right'; $xBtn.Margin = [Windows.Thickness]::new(0,0,4,0)
    $xBtn.Tag = $dlg
    $xBtn.Add_Click({ $this.Tag.DialogResult = $false })
    [void]$titleGrid.Children.Add($xBtn)
    $titleBar.Child = $titleGrid
    [void]$root.Children.Add($titleBar); [Windows.Controls.Grid]::SetRow($titleBar, 0)

    $body = [Windows.Controls.StackPanel]::new()
    $body.Margin = [Windows.Thickness]::new(24,22,24,20)
    $row1 = [Windows.Controls.StackPanel]::new(); $row1.Orientation = 'Horizontal'
    $iconBox = [Windows.Controls.Border]::new(); $iconBox.Width = 42; $iconBox.Height = 42; $iconBox.CornerRadius = [Windows.CornerRadius]::new(10); $iconBox.Background = Get-Brush $iconBgHex; $iconBox.VerticalAlignment = 'Top'
    $icon = [Windows.Controls.TextBlock]::new(); $icon.Text = $iconChar; $icon.FontFamily = $script:FontSegoeIcons; $icon.FontSize = 20; $icon.Foreground = Get-Brush $iconFgHex; $icon.HorizontalAlignment = 'Center'; $icon.VerticalAlignment = 'Center'
    $iconBox.Child = $icon
    [void]$row1.Children.Add($iconBox)
    $msgTb = [Windows.Controls.TextBlock]::new(); $msgTb.Text = $message; $msgTb.Width = 380; $msgTb.TextWrapping = 'Wrap'; $msgTb.FontSize = 14; $msgTb.Foreground = Get-Brush '#172033'; $msgTb.VerticalAlignment = 'Center'; $msgTb.Margin = [Windows.Thickness]::new(14,0,0,0)
    [void]$row1.Children.Add($msgTb)
    [void]$body.Children.Add($row1)
    $btnRow = [Windows.Controls.StackPanel]::new(); $btnRow.Orientation = 'Horizontal'; $btnRow.HorizontalAlignment = 'Right'; $btnRow.Margin = [Windows.Thickness]::new(0,22,0,0)
    if ($cancelText) {
        $cancelBtn = New-CardButton $cancelText '#FFFFFF' '#334155' '#DCE3EE' $null 92 { $this.Tag.DialogResult = $false }
        $cancelBtn.Tag = $dlg
        [void]$btnRow.Children.Add($cancelBtn)
    }
    if ($confirmText) {
        $confirmBtn = New-CardButton $confirmText '#5268F4' '#FFFFFF' $null $null 116 { $this.Tag.DialogResult = $true }
        $confirmBtn.Tag = $dlg
        [void]$btnRow.Children.Add($confirmBtn)
    }
    [void]$body.Children.Add($btnRow)
    [void]$root.Children.Add($body); [Windows.Controls.Grid]::SetRow($body, 1)

    $dlg.Content = $root
    [void]$dlg.ShowDialog()
    [bool]$dlg.DialogResult
}

function New-Badge([string]$status) {
    $cfg = $script:BadgeMap[$status]
    if (-not $cfg) { $cfg = @{ Icon=[char]0xE7BA; Bg='#EEF2F7'; Fg='#64748B'; Text=$status } }
    $badge = [Windows.Controls.Border]::new()
    $badge.CornerRadius = [Windows.CornerRadius]::new(7); $badge.Padding = [Windows.Thickness]::new(8,4,11,4)
    $sp = [Windows.Controls.StackPanel]::new(); $sp.Orientation = [Windows.Controls.Orientation]::Horizontal
    $badge.Background = Get-Brush $cfg.Bg
    $ic = [Windows.Controls.TextBlock]::new(); $ic.Text = $cfg.Icon
    $ic.FontFamily = $script:FontSegoeIcons; $ic.FontSize = 14
    $ic.Foreground = Get-Brush $cfg.Fg; $ic.Margin = [Windows.Thickness]::new(0,0,4,0); $ic.VerticalAlignment = 'Center'
    [void]$sp.Children.Add($ic)
    $txt = [Windows.Controls.TextBlock]::new(); $txt.Text = $cfg.Text
    $txt.Foreground = Get-Brush $cfg.Fg; $txt.FontSize = 13; $txt.FontWeight = [Windows.FontWeights]::Bold; $txt.VerticalAlignment = 'Center'
    [void]$sp.Children.Add($txt)
    $badge.Child = $sp
    $badge
}

function New-CodeInline([string]$text) {
    $border = [Windows.Controls.Border]::new()
    $border.Background = Get-Brush '#F2F5FA'; $border.BorderBrush = Get-Brush '#E4E9F2'
    $border.BorderThickness = [Windows.Thickness]::new(1); $border.CornerRadius = [Windows.CornerRadius]::new(7)
    $border.Padding = [Windows.Thickness]::new(8,3,8,3); $border.Margin = [Windows.Thickness]::new(0,0,6,0)
    $txt = [Windows.Controls.TextBlock]::new(); $txt.Text = $text
    $txt.FontFamily = $script:FontMono; $txt.FontSize = 12; $txt.TextTrimming = [Windows.TextTrimming]::CharacterEllipsis
    $txt.Foreground = Get-Brush '#2F405D'
    $border.ToolTip = $text
    $border.Child = $txt
    $border
}

function Set-AppTitleIcon {
    try {
        $sourcePath = $null
        $mainFile = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if ($mainFile -and $mainFile -like '*.exe') { $sourcePath = $mainFile }
        if (-not $sourcePath) { $sourcePath = Join-Path $PSScriptRoot '资源\222.ico' }
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { return }
        $nativeIcon = [Drawing.Icon]::ExtractAssociatedIcon($sourcePath)
        if (-not $nativeIcon) { return }
        try {
            $bitmap = [Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon(
                $nativeIcon.Handle,
                [Windows.Int32Rect]::Empty,
                [Windows.Media.Imaging.BitmapSizeOptions]::FromWidthAndHeight(64,64)
            )
            $bitmap.Freeze()
            $image = [Windows.Controls.Image]::new()
            $image.Source = $bitmap; $image.Stretch = [Windows.Media.Stretch]::Uniform
            $image.Margin = [Windows.Thickness]::new(2)
            $AppTitleIcon.Child = $image
        } finally { $nativeIcon.Dispose() }
    } catch { }
}

function New-AddressInline([string]$text) {
    $border = New-CodeInline $text
    # 卡片中地址与操作按钮共用一行，使用紧凑字号和留白，避免中文共享名被截断。
    $border.Padding = [Windows.Thickness]::new(6,3,6,3)
    $tb = $border.Child
    $tb.FontFamily = $script:FontSegoe
    $tb.FontSize = 11
    $tb.TextTrimming = [Windows.TextTrimming]::None
    $border.ToolTip = "完整地址：$text"
    $border
}

function Open-ShareFolder([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Container)) {
        throw "文件夹不存在，无法打开：$path"
    }
    Start-Process -FilePath 'explorer.exe' -ArgumentList @($path)
}

function New-OpenFolderInline([string]$path) {
    $border = New-CodeInline $path
    if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path -PathType Container)) {
        $border.Cursor = [Windows.Input.Cursors]::Hand
        $border.ToolTip = "点击打开文件夹：$path"
        $border.Tag = $path
        $border.Add_MouseLeftButtonUp({
            try { Open-ShareFolder ([string]$this.Tag) } catch { Show-Error '打开文件夹失败' $_ }
        })
    }
    $border
}

function Add-ShareCard($row) {
    $card = [Windows.Controls.Border]::new()
    $card.Tag = $row; $card.Background = Get-Brush '#FFFFFF'; $card.BorderBrush = Get-Brush '#E3E9F2'
    $card.BorderThickness = [Windows.Thickness]::new(1); $card.CornerRadius = [Windows.CornerRadius]::new(12)
    $card.Margin = [Windows.Thickness]::new(0,0,0,14); $card.Padding = [Windows.Thickness]::new(18,18,18,18)
    $card.Effect = $script:CardShadowEffect

    $grid = [Windows.Controls.Grid]::new()
    $c1 = [Windows.Controls.ColumnDefinition]::new(); $c1.Width = [Windows.GridLength]::Auto
    $c2 = [Windows.Controls.ColumnDefinition]::new(); $c2.Width = [Windows.GridLength]::new(1,[Windows.GridUnitType]::Star)
    $c3 = [Windows.Controls.ColumnDefinition]::new(); $c3.Width = [Windows.GridLength]::Auto
    $c4 = [Windows.Controls.ColumnDefinition]::new(); $c4.Width = [Windows.GridLength]::Auto
    $c5 = [Windows.Controls.ColumnDefinition]::new(); $c5.Width = [Windows.GridLength]::Auto
    $c6 = [Windows.Controls.ColumnDefinition]::new(); $c6.Width = [Windows.GridLength]::Auto
    [void]$grid.ColumnDefinitions.Add($c1); [void]$grid.ColumnDefinitions.Add($c2); [void]$grid.ColumnDefinitions.Add($c3); [void]$grid.ColumnDefinitions.Add($c4); [void]$grid.ColumnDefinitions.Add($c5); [void]$grid.ColumnDefinitions.Add($c6)

    $ok = ($row.Status -eq '已开启')
    $paused = [bool]$row.Paused
    $iconBox = [Windows.Controls.Border]::new()
    $iconBox.Width = 78; $iconBox.Height = 78; $iconBox.CornerRadius = [Windows.CornerRadius]::new(14)
    $iconBox.Background = if ($paused) { Get-Brush '#FFF4E5' } elseif ($row.Path) { Get-Brush '#EEF3FF' } else { Get-Brush '#FFF4E5' }
    $iconBox.VerticalAlignment = [Windows.VerticalAlignment]::Center
    $icon = [Windows.Controls.TextBlock]::new()
    # 使用 Windows 系统文件夹字形，避免自绘手机图标在小尺寸下显得拥挤。
    $icon.Text = if ($row.Path) { [char]0xE8B7 } else { [char]0xE7BA }
    $icon.FontFamily = $script:FontSegoeIcons; $icon.FontSize = 30
    $icon.Foreground = if ($paused) { Get-Brush '#D97706' } elseif ($row.Path) { Get-Brush '#5268F4' } else { Get-Brush '#E18A3B' }
    $icon.HorizontalAlignment = [Windows.HorizontalAlignment]::Center; $icon.VerticalAlignment = [Windows.VerticalAlignment]::Center
    $iconBox.Child = $icon
    [void]$grid.Children.Add($iconBox); [Windows.Controls.Grid]::SetColumn($iconBox, 0)

    $textCol = [Windows.Controls.StackPanel]::new()
    $textCol.Margin = [Windows.Thickness]::new(18,0,22,0); $textCol.VerticalAlignment = [Windows.VerticalAlignment]::Center
    $nameRow = [Windows.Controls.StackPanel]::new(); $nameRow.Orientation = [Windows.Controls.Orientation]::Horizontal
    $name = [Windows.Controls.TextBlock]::new()
    $name.Text = $row.Name; $name.FontSize = 16; $name.FontWeight = [Windows.FontWeights]::Bold
    $name.Foreground = Get-Brush '#172033'; $name.VerticalAlignment = [Windows.VerticalAlignment]::Center
    [void]$nameRow.Children.Add($name)
    [void]$textCol.Children.Add($nameRow)

    $meta1 = [Windows.Controls.StackPanel]::new()
    $meta1.Orientation = [Windows.Controls.Orientation]::Horizontal; $meta1.Margin = [Windows.Thickness]::new(0,6,0,0)
    $lbl1 = [Windows.Controls.TextBlock]::new()
    $lbl1.Text = '文件夹：'; $lbl1.FontSize = 12; $lbl1.Foreground = Get-Brush '#7A8699'
    $lbl1.VerticalAlignment = [Windows.VerticalAlignment]::Center
    [void]$meta1.Children.Add($lbl1)
    [void]$meta1.Children.Add((New-OpenFolderInline ([string]$row.Path)))
    if (-not $ok -and $row.Path) {
        $warn = [Windows.Controls.TextBlock]::new()
        $warn.Text = '（找不到这个文件夹）'; $warn.Foreground = Get-Brush '#D97706'
        $warn.FontSize = 12; $warn.VerticalAlignment = [Windows.VerticalAlignment]::Center
        [void]$meta1.Children.Add($warn)
    }
    [void]$textCol.Children.Add($meta1)

    $meta2 = [Windows.Controls.StackPanel]::new()
    $meta2.Orientation = [Windows.Controls.Orientation]::Horizontal; $meta2.Margin = [Windows.Thickness]::new(0,3,0,0)
    $lbl2 = [Windows.Controls.TextBlock]::new()
    $lbl2.Text = '手机地址：'; $lbl2.FontSize = 12; $lbl2.Foreground = Get-Brush '#7A8699'
    $lbl2.VerticalAlignment = [Windows.VerticalAlignment]::Center
    [void]$meta2.Children.Add($lbl2)
    [void]$meta2.Children.Add((New-AddressInline ([string]$row.Address)))
    [void]$textCol.Children.Add($meta2)
    [void]$grid.Children.Add($textCol); [Windows.Controls.Grid]::SetColumn($textCol, 1)

    $separator1 = [Windows.Controls.Border]::new()
    $separator1.Width = 1; $separator1.Margin = [Windows.Thickness]::new(0,4,20,4)
    $separator1.Background = Get-Brush '#E3E9F2'
    [void]$grid.Children.Add($separator1); [Windows.Controls.Grid]::SetColumn($separator1, 2)

    $statusCol = [Windows.Controls.StackPanel]::new()
    $statusCol.Width = 150; $statusCol.Margin = [Windows.Thickness]::new(0,0,20,0)
    $statusCol.VerticalAlignment = [Windows.VerticalAlignment]::Center
    if ($row.Status) {
        $bd = New-Badge $row.Status
        $bd.HorizontalAlignment = [Windows.HorizontalAlignment]::Left
        [void]$statusCol.Children.Add($bd)
    }
    $sourceText = [Windows.Controls.TextBlock]::new()
    $sourceText.Text = if ($paused) { '本软件管理 · 已暂停' } elseif ($row.Managed) { '本软件管理' } else { '电脑已有共享' }
    $sourceText.FontSize = 13; $sourceText.Foreground = Get-Brush '#4A5A70'
    $sourceText.Margin = [Windows.Thickness]::new(0,8,0,0)
    [void]$statusCol.Children.Add($sourceText)
    [void]$grid.Children.Add($statusCol); [Windows.Controls.Grid]::SetColumn($statusCol, 3)

    $separator2 = [Windows.Controls.Border]::new()
    $separator2.Width = 1; $separator2.Margin = [Windows.Thickness]::new(0,4,20,4)
    $separator2.Background = Get-Brush '#E3E9F2'
    [void]$grid.Children.Add($separator2); [Windows.Controls.Grid]::SetColumn($separator2, 4)

    $btnCol = [Windows.Controls.StackPanel]::new()
    $btnCol.Orientation = [Windows.Controls.Orientation]::Horizontal; $btnCol.VerticalAlignment = [Windows.VerticalAlignment]::Center
    $detailBtn = New-CardButton '详情' '#F2F5FA' '#334155' '#DCE3EE' ([char]0xE7C3) 68 {
        Show-ShareDetail $this.Tag
    }
    $detailBtn.Tag = $row
    [void]$btnCol.Children.Add($detailBtn)
    if ($row.Managed) {
        if ($ok) {
            $copyBtn = New-CardButton '复制地址' '#5268F4' '#FFFFFF' $null ([char]0xE8C8) 92 {
                $r = $this.Tag
                Set-Clipboard $r.Address
                $StatusText.Text = '连接地址已复制'
            }
            $copyBtn.Tag = $row
            [void]$btnCol.Children.Add($copyBtn)
        }
        if ($paused) {
            $resumeBtn = New-CardButton '重新开启' '#5268F4' '#FFFFFF' $null $null 92 {
                $r = $this.Tag
                try { Resume-ManagedShare $r.Name; Refresh-All } catch { Show-Error '重新开启失败' $_ }
            }
            $resumeBtn.Tag = $row
            [void]$btnCol.Children.Add($resumeBtn)
        } else {
            $pauseBtn = New-CardButton '暂停共享' '#F2F5FA' '#334155' '#DCE3EE' $null 92 {
                $r = $this.Tag
                $msg = "确定暂停共享 [$($r.Name)] 吗？`r`n只会暂时关闭 SMB 访问，文件夹和文件不会删除，之后可点击重新开启。"
                if (Show-AppDialog '确认暂停' $msg ([char]0xE7BA) '#FFF4E0' '#D97706' '确定暂停' '取消') {
                    try { Pause-ManagedShare $r.Name; Refresh-All } catch { Show-Error '暂停失败' $_ }
                }
            }
            $pauseBtn.Tag = $row
            [void]$btnCol.Children.Add($pauseBtn)
        }
        $deleteBtn = New-CardButton '删除记录' '#FFF7F6' '#C24545' '#E4B7B7' ([char]0xE74D) 92 {
            $r = $this.Tag
            $msg = "确定删除共享记录 [$($r.Name)] 吗？`r`n将关闭 SMB 共享并删除软件管理记录，文件夹和文件不会删除。"
            if (Show-AppDialog '确认删除记录' $msg ([char]0xE7BA) '#FFF4E0' '#D97706' '确定删除' '取消') {
                try { Delete-ManagedShare $r.Name; Refresh-All } catch { Show-Error '删除记录失败' $_ }
            }
        }
        $deleteBtn.Tag = $row
        [void]$btnCol.Children.Add($deleteBtn)
    } else {
        if ($ok) {
            $copyBtn = New-CardButton '复制地址' '#5268F4' '#FFFFFF' $null ([char]0xE8C8) 104 {
                $r = $this.Tag
                Set-Clipboard $r.Address
                $StatusText.Text = '连接地址已复制'
            }
            $copyBtn.Tag = $row
            [void]$btnCol.Children.Add($copyBtn)
        }
        $closeBtn = New-CardButton '关闭共享' '#FFF7F6' '#C24545' '#E4B7B7' ([char]0xE74D) 104 {
            $r = $this.Tag
            $msg = "这是电脑已有共享（不是本软件创建的）。`r`n确定要关闭 [$($r.Name)] 吗？`r`n只会删除 SMB 共享映射，文件夹和文件不会删除，之后可在 Windows 共享设置里重新开启。"
            if (Show-AppDialog '确认关闭' $msg ([char]0xE7BA) '#FFF4E0' '#D97706' '确定关闭' '取消') {
                try { Remove-Share $r.Name; Refresh-All } catch { Show-Error '关闭失败' $_ }
            }
        }
        $closeBtn.Tag = $row
        [void]$btnCol.Children.Add($closeBtn)
    }
    [void]$grid.Children.Add($btnCol); [Windows.Controls.Grid]::SetColumn($btnCol, 5)
    $card.Child = $grid
    [void]$CardPanel.Children.Add($card)
}

function Show-ListView {
    $DetailView.Visibility = [Windows.Visibility]::Collapsed
    $ListView.Visibility = [Windows.Visibility]::Visible
}

function Add-DetailInfoRow([string]$label, $valueElement) {
    $sp = [Windows.Controls.StackPanel]::new()
    $sp.Orientation = [Windows.Controls.Orientation]::Horizontal; $sp.Margin = [Windows.Thickness]::new(0,6,0,0)
    $lbl = [Windows.Controls.TextBlock]::new()
    $lbl.Text = "$label`t"; $lbl.FontSize = 13; $lbl.Foreground = Get-Brush '#7A8699'
    $lbl.VerticalAlignment = [Windows.VerticalAlignment]::Center; $lbl.Margin = [Windows.Thickness]::new(0,0,10,0)
    [void]$sp.Children.Add($lbl)
    [void]$sp.Children.Add($valueElement)
    [void]$DetailInfoPanel.Children.Add($sp)
}

function Show-ShareDetail($row) {
    $script:CurrentDetailRow = $row
    $DetailName.Text = $row.Name
    $DetailBadgeHolder.Children.Clear()
    if ($row.Status) { [void]$DetailBadgeHolder.Children.Add((New-Badge $row.Status)) }
    $DetailEditButton.IsEnabled = -not [bool]$row.Paused
    if ($row.Managed -and $row.Paused) {
        $DetailCloseLabel.Text = '重新开启'
        $DetailCloseButton.Background = Get-Brush '#5268F4'
        $DetailCloseButton.BorderBrush = $null
        $DetailCloseButton.Foreground = Get-Brush '#FFFFFF'
        $DetailCloseIcon.Foreground = Get-Brush '#FFFFFF'
        $DetailCloseLabel.Foreground = Get-Brush '#FFFFFF'
    } elseif ($row.Managed) {
        $DetailCloseLabel.Text = '暂停共享'
        $DetailCloseButton.Background = Get-Brush '#F2F5FA'
        $DetailCloseButton.BorderBrush = Get-Brush '#DCE3EE'
        $DetailCloseButton.Foreground = Get-Brush '#334155'
        $DetailCloseIcon.Foreground = Get-Brush '#334155'
        $DetailCloseLabel.Foreground = Get-Brush '#334155'
    } else {
        $DetailCloseLabel.Text = '关闭共享'
        $DetailCloseButton.Background = Get-Brush '#FFF7F6'
        $DetailCloseButton.BorderBrush = Get-Brush '#E4B7B7'
        $DetailCloseButton.Foreground = Get-Brush '#C24545'
        $DetailCloseIcon.Foreground = Get-Brush '#C24545'
        $DetailCloseLabel.Foreground = Get-Brush '#C24545'
    }
    $DetailInfoPanel.Children.Clear()
    Add-DetailInfoRow '文件夹' (New-OpenFolderInline ([string]$row.Path))
    if (-not $row.Path -or -not (Test-Path -LiteralPath $row.Path)) {
        $warn = [Windows.Controls.TextBlock]::new()
        $warn.Text = '（找不到这个文件夹）'; $warn.Foreground = Get-Brush '#D97706'
        $warn.FontSize = 12; $warn.VerticalAlignment = [Windows.VerticalAlignment]::Center
        $row2 = [Windows.Controls.StackPanel]::new(); $row2.Orientation = 'Horizontal'; $row2.Margin = [Windows.Thickness]::new(0,6,0,0)
        $lbl2 = [Windows.Controls.TextBlock]::new(); $lbl2.Text = '状态'; $lbl2.FontSize = 13; $lbl2.Foreground = Get-Brush '#7A8699'; $lbl2.VerticalAlignment = 'Center'; $lbl2.Margin = [Windows.Thickness]::new(0,0,10,0)
        [void]$row2.Children.Add($lbl2); [void]$row2.Children.Add($warn)
        [void]$DetailInfoPanel.Children.Add($row2)
    }
    Add-DetailInfoRow '手机地址' (New-CodeInline ([string]$row.Address))
    $source = if ($row.Managed) { '本软件管理（iPhone 共享助手创建）' } else { '电脑已有共享' }
    $srcTb = [Windows.Controls.TextBlock]::new()
    $srcTb.Text = $source; $srcTb.FontSize = 13; $srcTb.Foreground = Get-Brush '#2F405D'; $srcTb.VerticalAlignment = [Windows.VerticalAlignment]::Center
    Add-DetailInfoRow '来源' $srcTb
    $accessTb = [Windows.Controls.TextBlock]::new()
    $accessTb.TextWrapping = 'Wrap'; $accessTb.FontSize = 13; $accessTb.Foreground = Get-Brush '#2F405D'; $accessTb.VerticalAlignment = [Windows.VerticalAlignment]::Center
    try {
        $lines = if ($row.Paused) { @($row.AccessLines) } else { @(Get-ShareAccessLines $row.Name) }
        $accessTb.Text = if ($lines.Count) { $lines -join '；' } else { '未获取到访问账号' }
    } catch { $accessTb.Text = '获取访问权限失败：' + $_.Exception.Message }
    Add-DetailInfoRow '访问权限' $accessTb

    $ListView.Visibility = [Windows.Visibility]::Collapsed
    $DetailView.Visibility = [Windows.Visibility]::Visible
}

function Show-EditDialog($row) {
    $dlg = [Windows.Window]::new()
    $dlg.Title = "编辑共享 [$($row.Name)]"
    $dlg.WindowStyle = 'None'
    $dlg.ResizeMode = 'NoResize'
    $dlg.SizeToContent = 'WidthAndHeight'
    $dlg.WindowStartupLocation = 'CenterOwner'
    if ($window -and $window.IsVisible) { $dlg.Owner = $window }
    $dlg.Background = Get-Brush '#F8FAFD'
    $dlg.FontFamily = $script:FontSegoe
    $chrome = [System.Windows.Shell.WindowChrome]::new()
    $chrome.CaptionHeight = 0; $chrome.ResizeBorderThickness = [Windows.Thickness]::new(0)
    $chrome.CornerRadius = [Windows.CornerRadius]::new(0); $chrome.GlassFrameThickness = [Windows.Thickness]::new(0)
    $chrome.UseAeroCaptionButtons = $false
    [System.Windows.Shell.WindowChrome]::SetWindowChrome($dlg, $chrome)

    $root = [Windows.Controls.Grid]::new()
    $r1 = [Windows.Controls.RowDefinition]::new(); $r1.Height = [Windows.GridLength]::Auto
    $r2 = [Windows.Controls.RowDefinition]::new(); $r2.Height = [Windows.GridLength]::Auto
    [void]$root.RowDefinitions.Add($r1); [void]$root.RowDefinitions.Add($r2)

    $titleBar = [Windows.Controls.Border]::new(); $titleBar.Background = Get-Brush '#142238'
    $titleGrid = [Windows.Controls.Grid]::new()
    $left = [Windows.Controls.StackPanel]::new(); $left.Orientation = 'Horizontal'; $left.Margin = [Windows.Thickness]::new(16,0,0,0); $left.VerticalAlignment = 'Center'
    $dot = [Windows.Controls.Border]::new(); $dot.Width = 9; $dot.Height = 9; $dot.CornerRadius = [Windows.CornerRadius]::new(5); $dot.Background = Get-Brush '#3E8EFF'; $dot.Margin = [Windows.Thickness]::new(0,0,8,0); $dot.VerticalAlignment = 'Center'
    [void]$left.Children.Add($dot)
    $tt = [Windows.Controls.TextBlock]::new(); $tt.Text = "编辑共享 [$($row.Name)]"; $tt.Foreground = [Windows.Media.Brushes]::White; $tt.FontSize = 13; $tt.FontWeight = [Windows.FontWeights]::SemiBold; $tt.VerticalAlignment = 'Center'
    [void]$left.Children.Add($tt); [void]$titleGrid.Children.Add($left)
    $xBtn = [Windows.Controls.Button]::new(); $xBtn.Width = 38; $xBtn.Height = 36; $xBtn.Background = [Windows.Media.Brushes]::Transparent; $xBtn.BorderThickness = [Windows.Thickness]::new(0); $xBtn.Cursor = [Windows.Input.Cursors]::Hand
    $xTb = [Windows.Controls.TextBlock]::new(); $xTb.Text = [char]0xE8BB; $xTb.FontFamily = $script:FontSegoeIcons; $xTb.FontSize = 11; $xTb.Foreground = Get-Brush '#8FA0BA'
    $xBtn.Content = $xTb; $xBtn.HorizontalAlignment = 'Right'; $xBtn.Margin = [Windows.Thickness]::new(0,0,4,0); $xBtn.Tag = $dlg
    $xBtn.Add_Click({ $this.Tag.DialogResult = $false })
    [void]$titleGrid.Children.Add($xBtn)
    $titleBar.Child = $titleGrid
    [void]$root.Children.Add($titleBar); [Windows.Controls.Grid]::SetRow($titleBar, 0)

    $body = [Windows.Controls.StackPanel]::new()
    $body.Margin = [Windows.Thickness]::new(24,22,24,20); $body.Width = 430
    $hint = [Windows.Controls.TextBlock]::new()
    $hint.Text = '修改共享名称或文件夹路径，不会删除任何文件夹和文件。'
    $hint.FontSize = 13; $hint.Foreground = Get-Brush '#7A8699'; $hint.TextWrapping = 'Wrap'; $hint.Margin = [Windows.Thickness]::new(0,0,0,16)
    [void]$body.Children.Add($hint)

    function New-Field([string]$label, [string]$initial) {
        $wrap = [Windows.Controls.StackPanel]::new(); $wrap.Margin = [Windows.Thickness]::new(0,0,0,14)
        $lbl = [Windows.Controls.TextBlock]::new(); $lbl.Text = $label; $lbl.FontSize = 13; $lbl.Foreground = Get-Brush '#172033'; $lbl.FontWeight = [Windows.FontWeights]::SemiBold; $lbl.Margin = [Windows.Thickness]::new(0,0,0,6)
        [void]$wrap.Children.Add($lbl)
        $tb = [Windows.Controls.TextBox]::new(); $tb.Text = $initial; $tb.FontSize = 13; $tb.Height = 34; $tb.VerticalContentAlignment = 'Center'; $tb.Padding = [Windows.Thickness]::new(8,0,8,0)
        $tb.Background = Get-Brush '#FFFFFF'; $tb.BorderBrush = Get-Brush '#DCE3EE'; $tb.BorderThickness = [Windows.Thickness]::new(1)
        [void]$wrap.Children.Add($tb)
        [pscustomobject]@{ Panel = $wrap; Box = $tb }
    }

    $nameField = New-Field '共享名称' $row.Name
    [void]$body.Children.Add($nameField.Panel)

    $pathWrap = [Windows.Controls.StackPanel]::new(); $pathWrap.Margin = [Windows.Thickness]::new(0,0,0,14)
    $lbl = [Windows.Controls.TextBlock]::new(); $lbl.Text = '文件夹路径'; $lbl.FontSize = 13; $lbl.Foreground = Get-Brush '#172033'; $lbl.FontWeight = [Windows.FontWeights]::SemiBold; $lbl.Margin = [Windows.Thickness]::new(0,0,0,6)
    [void]$pathWrap.Children.Add($lbl)
    $pathGrid = [Windows.Controls.Grid]::new()
    $c1 = [Windows.Controls.ColumnDefinition]::new(); $c1.Width = [Windows.GridLength]::new(1,[Windows.GridUnitType]::Star)
    $c2 = [Windows.Controls.ColumnDefinition]::new(); $c2.Width = [Windows.GridLength]::Auto
    [void]$pathGrid.ColumnDefinitions.Add($c1); [void]$pathGrid.ColumnDefinitions.Add($c2)
    $pathBox = [Windows.Controls.TextBox]::new(); $pathBox.Text = [string]$row.Path; $pathBox.FontSize = 13; $pathBox.Height = 34; $pathBox.VerticalContentAlignment = 'Center'; $pathBox.Padding = [Windows.Thickness]::new(8,0,8,0)
    $pathBox.Background = Get-Brush '#FFFFFF'; $pathBox.BorderBrush = Get-Brush '#DCE3EE'; $pathBox.BorderThickness = [Windows.Thickness]::new(1)
    [void]$pathGrid.Children.Add($pathBox)
    $browseBtn = New-CardButton '浏览…' '#F2F5FA' '#334155' '#DCE3EE' $null 84 $null
    $browseBtn.Height = 34; $browseBtn.Margin = [Windows.Thickness]::new(8,0,0,0)
    $browseBtn.Add_Click({
        $d = [Windows.Forms.FolderBrowserDialog]::new()
        try {
            $d.SelectedPath = if (Test-Path -LiteralPath $pathBox.Text) { $pathBox.Text } else { [Environment]::GetFolderPath('MyComputer') }
            $d.ShowNewFolderButton = $true
            if ($d.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) { $pathBox.Text = $d.SelectedPath }
        } finally { $d.Dispose() }
    })
    [void]$pathGrid.Children.Add($browseBtn); [Windows.Controls.Grid]::SetColumn($browseBtn, 1)
    [void]$pathWrap.Children.Add($pathGrid)
    [void]$body.Children.Add($pathWrap)

    $accessHint = [Windows.Controls.TextBlock]::new()
    try {
        $accessHint.Text = '当前访问账号：' + ((Get-ShareAccessLines $row.Name) -join '；')
    } catch { $accessHint.Text = '当前访问账号：无法读取' }
    $accessHint.FontSize = 12; $accessHint.Foreground = Get-Brush '#7A8699'; $accessHint.TextWrapping = 'Wrap'; $accessHint.Margin = [Windows.Thickness]::new(0,0,0,16)
    [void]$body.Children.Add($accessHint)

    $btnRow = [Windows.Controls.StackPanel]::new(); $btnRow.Orientation = 'Horizontal'; $btnRow.HorizontalAlignment = 'Right'
    $cancelBtn = New-CardButton '取消' '#FFFFFF' '#334155' '#DCE3EE' $null 92 { $this.Tag.DialogResult = $false }
    $cancelBtn.Tag = $dlg; [void]$btnRow.Children.Add($cancelBtn)
    $saveBtn = New-CardButton '保存修改' '#5268F4' '#FFFFFF' $null $null 116 $null
    $saveBtn.Tag = $dlg; $saveBtn.Add_Click({ $this.Tag.Tag = [pscustomobject]@{ Name = $nameField.Box.Text; Path = $pathBox.Text }; $this.Tag.DialogResult = $true })
    [void]$btnRow.Children.Add($saveBtn)
    [void]$body.Children.Add($btnRow)
    [void]$root.Children.Add($body); [Windows.Controls.Grid]::SetRow($body, 1)

    $dlg.Content = $root
    $ok = [bool]$dlg.ShowDialog()
    if (-not $ok -or -not $dlg.Tag) { return $null }
    $dlg.Tag
}

function Apply-Theme {
    $WindowRoot.Background = Get-Brush '#F8FAFD'
    $PageTitle.Foreground = Get-Brush '#172033'
    $PageSubtitle.Foreground = Get-Brush '#7A8699'
    $DetailName.Foreground = Get-Brush '#172033'
    $DetailSubtitle.Foreground = Get-Brush '#7A8699'
    $DetailInfoCard.Background = Get-Brush '#FFFFFF'
    $DetailInfoCard.BorderBrush = Get-Brush '#E3E9F2'
    $DetailInfoTitle.Foreground = Get-Brush '#172033'
    $BackButton.Background = Get-Brush '#F2F5FA'
    $BackButton.BorderBrush = Get-Brush '#DCE3EE'
    $BackButton.Foreground = Get-Brush '#172033'
    $BackIcon.Foreground = Get-Brush '#5268F4'
    $BackLabel.Foreground = Get-Brush '#172033'
    $DetailCopyButton.Background = Get-Brush '#5268F4'
    $DetailEditButton.Background = Get-Brush '#FFF7F6'
    $DetailEditButton.BorderBrush = Get-Brush '#5268F4'
    $DetailEditButton.Foreground = Get-Brush '#5268F4'
    $DetailEditIcon.Foreground = Get-Brush '#5268F4'
    $DetailEditLabel.Foreground = Get-Brush '#5268F4'
    $DetailCloseButton.Background = Get-Brush '#FFF7F6'
    $DetailCloseButton.BorderBrush = Get-Brush '#E4B7B7'
    $DetailCloseButton.Foreground = Get-Brush '#C24545'
    $DetailCloseIcon.Foreground = Get-Brush '#C24545'
    $DetailCloseLabel.Foreground = Get-Brush '#C24545'
    $FooterBar.Background = Get-Brush '#142238'
    $FooterBar.BorderBrush = Get-Brush '#142238'
    $FooterText.Foreground = Get-Brush '#DCE6F5'
    $AccountChip.Background = Get-Brush '#1C2B47'
    $AccountChipText.Foreground = Get-Brush '#DCE6F5'
    $PasswordChip.Background = Get-Brush '#1C2B47'
    $PasswordChipText.Foreground = Get-Brush '#DCE6F5'
    $StatusText.Foreground = Get-Brush '#8FA8FF'
    $ThemeIcon.Text = if ($script:Theme -eq 'Dark') { [char]0xE706 } else { [char]0xE708 }
    Refresh-All
    if ($DetailView.Visibility -eq [Windows.Visibility]::Visible -and $script:CurrentDetailRow) {
        Show-ShareDetail $script:CurrentDetailRow
    }
}

function Refresh-All {
    try {
        $ip = Get-PrimaryIp
        $rows = @(Get-ShareRows $ip)
        $CardPanel.Children.Clear()
        foreach ($row in $rows) { Add-ShareCard $row }
        $FooterText.Text = "手机连接：iPhone「文件」App → 连接服务器 → smb://$ip"
        $AccountChipText.Text = "登录账号 $((Get-CurrentAccountName) -replace '^.*\\','')"
        $PasswordChipText.Text = '密码 = Windows 登录密码（不是 PIN）'
        $StatusText.Text = "共 $($rows.Count) 个共享 · $(Get-Date -Format 'HH:mm')"
        if ($IpChipText) { $IpChipText.Text = "本机IP：$ip" }
    } catch { Show-Error '刷新失败' $_ }
}

$AddButton.Add_Click({
    $d = [Windows.Forms.FolderBrowserDialog]::new()
    try {
        $d.ShowNewFolderButton = $true
        if ($d.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { return }
        $path = $d.SelectedPath.TrimEnd('\')
        $name = [IO.Path]::GetFileName($path)
        if (-not $name) { $name = $path.Replace(':','').Replace('\','') }
        try { Set-ManagedShare $path $name @("$(Get-CurrentAccountName)|读写"); Refresh-All }
        catch { Show-Error '开启共享失败' $_ }
    }
    finally {
        $d.Dispose()
    }
})

$BackButton.Add_Click({ Show-ListView })

$ThemeButton.Add_Click({
    if ($script:Theme -eq 'Light') {
        $script:Theme = 'Dark'
    } else {
        $script:Theme = 'Light'
    }
    try { Apply-Theme } catch { Show-Error '切换主题失败' $_ }
})

$DetailCopyButton.Add_Click({
    if (-not $script:CurrentDetailRow) { return }
    Set-Clipboard $script:CurrentDetailRow.Address
    $StatusText.Text = '连接地址已复制'
})

$DetailEditButton.Add_Click({
    $row = $script:CurrentDetailRow
    if (-not $row) { return }
    $result = Show-EditDialog $row
    if (-not $result) { return }
    try {
        if (-not $row.Managed) {
            $msg = "这是电脑已有共享（不是本软件创建的）。`r`n确定要修改 [$($row.Name)] 吗？`r`n只会修改共享名称或文件夹路径，文件夹和文件不会删除，之后可在 Windows 共享设置里重新开启。"
            if (-not (Show-AppDialog '确认修改' $msg ([char]0xE7BA) '#FFF4E0' '#D97706' '确定修改' '取消')) { return }
        }
        Update-ShareConfig $row.Name $result.Name $result.Path
        Refresh-All
        $newName = $result.Name.Trim()
        $newRow = @(Get-ShareRows (Get-PrimaryIp)) | Where-Object { $_.Name -eq $newName } | Select-Object -First 1
        if ($newRow) { Show-ShareDetail $newRow } else { Show-ListView }
        $StatusText.Text = "共享 [$newName] 已更新"
    } catch { Show-Error '保存失败' $_ }
})

$DetailCloseButton.Add_Click({
    $row = $script:CurrentDetailRow
    if (-not $row) { return }
    if ($row.Managed -and $row.Paused) {
        $msg = "确定重新开启共享 [$($row.Name)] 吗？`r`n将恢复 SMB 访问，文件夹和文件不会变化。"
        if (Show-AppDialog '确认重新开启' $msg ([char]0xE768) '#E4F6EC' '#1F9254' '重新开启' '取消') {
            try { Resume-ManagedShare $row.Name; Refresh-All; $newRow = @(Get-ShareRows (Get-PrimaryIp)) | Where-Object { $_.Name -eq $row.Name } | Select-Object -First 1; if ($newRow) { Show-ShareDetail $newRow } } catch { Show-Error '重新开启失败' $_ }
        }
        return
    } elseif ($row.Managed) {
        $msg = "确定暂停共享 [$($row.Name)] 吗？`r`n只会暂时关闭 SMB 访问，文件夹和文件不会删除，之后可点击重新开启。"
        if (Show-AppDialog '确认暂停' $msg ([char]0xE7BA) '#FFF4E0' '#D97706' '确定暂停' '取消') {
            try { Pause-ManagedShare $row.Name; Refresh-All; Show-ListView } catch { Show-Error '暂停失败' $_ }
        }
        return
    } else {
        $msg = "这是电脑已有共享（不是本软件创建的）。`r`n确定要关闭 [$($row.Name)] 吗？`r`n只会删除 SMB 共享映射，文件夹和文件不会删除，之后可在 Windows 共享设置里重新开启。"
    }
    if (Show-AppDialog '确认关闭' $msg ([char]0xE7BA) '#FFF4E0' '#D97706' '确定关闭' '取消') {
        try { Remove-Share $row.Name; Refresh-All; Show-ListView } catch { Show-Error '关闭失败' $_ }
    }
})

Set-AppTitleIcon
Apply-Theme
[void]$window.ShowDialog()

