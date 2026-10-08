# Adds (or replaces) one file in a zip archive, using forward-slash entry
# names as required by the APK format. PowerShell's Compress-Archive is not
# used because it may write Windows-style separators.
#
# Usage: zipadd.ps1 -Zip <archive> -Source <file> -Entry <name/in/apk>
param(
  [Parameter(Mandatory=$true)][string]$Zip,
  [Parameter(Mandatory=$true)][string]$Source,
  [Parameter(Mandatory=$true)][string]$Entry
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

if (-not (Test-Path -LiteralPath $Zip)) {
  throw "zip not found: $Zip"
}
if (-not (Test-Path -LiteralPath $Source)) {
  throw "source not found: $Source"
}

$entry = $Entry -replace '\\','/'
$archive = [System.IO.Compression.ZipFile]::Open($Zip, [System.IO.Compression.ZipArchiveMode]::Update)
try {
  $existing = $archive.GetEntry($entry)
  if ($existing -ne $null) {
    $existing.Delete()
  }
  $new = $archive.CreateEntry($entry, [System.IO.Compression.CompressionLevel]::Optimal)
  $outStream = $new.Open()
  try {
    $inStream = [System.IO.File]::OpenRead($Source)
    try {
      $inStream.CopyTo($outStream)
    } finally {
      $inStream.Dispose()
    }
  } finally {
    $outStream.Dispose()
  }
} finally {
  $archive.Dispose()
}
Write-Output "added $entry"
