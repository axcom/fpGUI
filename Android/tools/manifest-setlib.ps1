# Rewrites the fpGUI Android manifest meta-data "com.fpgui.lib_name" so the
# Java shell loads lib<LibName>.so produced from the current project.
#
# Usage: manifest-setlib.ps1 -In <template manifest> -Out <patched manifest> -LibName <name>
param(
  [Parameter(Mandatory=$true)][string]$In,
  [Parameter(Mandatory=$true)][string]$Out,
  [Parameter(Mandatory=$true)][string]$LibName
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $In)) {
  throw "manifest not found: $In"
}

$text = Get-Content -Raw -LiteralPath $In
$text = $text -replace '(android:name="com\.fpgui\.lib_name"\s+android:value=")[^"]*(")', ('${1}' + $LibName + '${2}')
Set-Content -LiteralPath $Out -Value $text -NoNewline
Write-Output "lib_name=$LibName -> $Out"
