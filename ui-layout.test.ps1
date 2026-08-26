$ErrorActionPreference = 'Stop'
$sourcePath = Get-ChildItem -LiteralPath $PSScriptRoot -File -Recurse |
    Where-Object { $_.Name -like '*3.0.ps1' } |
    Select-Object -First 1 -ExpandProperty FullName
if (-not $sourcePath) { throw 'UI layout test setup failed: main source file was not found.' }
$source = Get-Content -LiteralPath $sourcePath -Raw

if ($source -notmatch '\$iconBox\.Width = 78') {
    throw 'UI layout test failed: share card icon area has not been enlarged to the approved layout.'
}
if ($source -notmatch '\$statusCol =') {
    throw 'UI layout test failed: share card status column is missing.'
}
if ($source -notmatch '\$(actionCol|btnCol) =') {
    throw 'UI layout test failed: share card action column is missing.'
}
if ($source -notmatch 'x:Name="AppTitleIcon"') {
    throw 'UI layout test failed: title bar branded icon is missing.'
}
if ($source -notmatch 'x:Name="AppTitleText"') {
    throw 'UI layout test failed: title bar version text is not named for synchronization.'
}
if ($source -notmatch 'function Open-ShareFolder') { throw 'UI behavior test failed: open-folder action is missing.' }
if ($source -notmatch 'function New-OpenFolderInline') { throw 'UI behavior test failed: folder path is not an openable control.' }
if ($source -notmatch 'function New-AddressInline') { throw 'UI layout test failed: compact full-address display is missing.' }
if ($source -notmatch 'x:Name="BackButton"[^>]*Height="38"[^>]*Padding="20,0"') { throw 'UI layout test failed: back button frame is still too small.' }
if ($source -notmatch 'x:Name="AppTitleText"[^>]*Margin="0,2,0,0"[^>]*VerticalAlignment="Center"') {
    throw 'UI layout test failed: title bar text is not visually centered with the icon.'
}
if ($source -notmatch 'function Set-AppTitleIcon') {
    throw 'UI layout test failed: title bar is not loading the packaged logo resource.'
}
if ($source -match 'x:Name="AppTitleIcon"[^>]*Background="#2D78FF"') {
    throw 'UI layout test failed: title bar logo still has an extra blue background.'
}
if ($source -notmatch '\$icon\.Text = if \(\$row\.Path\) \{ \[char\]0xE8B7 \}') {
    throw 'UI layout test failed: system folder icon is missing from share cards.'
}
if ($source -match 'CornerRadius\]::new\(999\)') { throw 'UI layout test failed: status badge must not be pill-shaped.' }
if ($source -notmatch "'#E3E9F2'" -or $source -notmatch "'#F8FAFD'" -or $source -notmatch '\$script:CardShadowEffect\.Opacity = 0\.04') { throw 'UI layout test failed: 3.24 card styling is missing.' }
if ($source -notmatch 'x:Name="FooterBar"[^>]*Background="#142238"[^>]*BorderBrush="#142238"[^>]*BorderThickness="0"') { throw 'UI layout test failed: footer must match title bar styling.' }
if ($source -notmatch '__APP_VERSION__') {
    throw 'UI layout test failed: title bar version is not injected from the packaged version.'
}
if ($source -notmatch '\$script:Theme = ''Dark''') { throw 'UI theme test failed: dark mode is not the default startup theme.' }
if ($source -notmatch "'#334155'\s*=\s*'#D7E0EE'") {
    throw 'UI theme test failed: dark-mode secondary button text mapping is missing.'
}
if ($source -notmatch '\$script:ManagedMetadataPath = Join-Path \$script:ManagedMetadataDir') {
    throw 'UI layout test failed: managed metadata path is missing.'
}
foreach ($functionName in @('Get-ManagedMetadata','Save-ManagedMetadata','Get-AccessAccountNames','Pause-ManagedShare','Resume-ManagedShare','Delete-ManagedShare')) {
    if ($source -notmatch "function $functionName") { throw "UI behavior test failed: $functionName is missing." }
}
foreach ($labelPattern in @('\u5DF2\u6682\u505C','\u6682\u505C\u5171\u4EAB','\u91CD\u65B0\u5F00\u542F','\u5220\u9664\u8BB0\u5F55')) {
    if ($source -notmatch $labelPattern) { throw "UI behavior test failed: a required paused-share label is missing." }
}
if ($source -match 'managed-shares\.json.*Remove-Item|Remove-Item.*managed-shares\.json') {
    throw 'UI behavior test failed: managed metadata must not be deleted as legacy cleanup.'
}
if ($source -match 'x:Name="(Search|Refresh)(Box|Button)?"') {
    throw 'UI layout test failed: search or refresh control was added unexpectedly.'
}

Write-Output 'UI layout test passed.'
