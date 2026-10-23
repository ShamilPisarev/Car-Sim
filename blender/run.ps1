param([string]$Script, [string]$Out = "")
$blender = "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($Out) { $env:PREVIEW_DIR = $Out }
$log = & $blender --background --python (Join-Path $here $Script) 2>&1 | Out-String
$lines = $log -split "`r?`n"
$keep = $lines | Where-Object { $_ -match 'Error|Traceback|^\s+File |OBJS|PARTS|DONE|WARN|^\w*Error' -and $_ -notmatch 'mpfb|MakeHuman' }
$keep | Select-Object -Last 25
