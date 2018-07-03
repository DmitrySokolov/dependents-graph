<#
    Copyright 2018 Dmitry Sokolov (mr.dmitry.sokolov@gmail.com).

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
#>
<#
.SYNOPSIS
    Buids dependency graph for given binary files.

.PARAMETER path
    Path to binary files.

.PARAMETER files
    File masks.

.PARAMETER filter
    File masks to exclude.

.PARAMETER output
    Output file name, default "result.graphml".

.EXAMPLE
    .\bin-dep-graph.ps1  -path c:\test  -files *.exe,*.dll
    .\bin-dep-graph.ps1  -path c:\test\x,c:\test\y  -files *.dll  -filter *d.dll
#>

# Command-line parameters
param (
    [Parameter(Mandatory=$true)] [String[]] $path = $(throw "-path is required."),
    [Parameter(Mandatory=$true)] [String[]] $files = $(throw "-files is required."),
    [String[]] $filter,
    [String] $output = 'result.graphml'
)

# Check dumpbin
where.exe dumpbin  >$null 2>&1
if (-not $?) {
    # Import env vars
    $installationPath = .\thirdparty\vswhere\vswhere.exe -prerelease -latest -property installationPath
    if ($installationPath -and (test-path "$installationPath\Common7\Tools\vsdevcmd.bat")) {
        & "${env:COMSPEC}" /s /c "`"$installationPath\Common7\Tools\vsdevcmd.bat`" -no_logo && set" | ForEach-Object {
            $name, $value = $_ -split '=', 2
            set-content env:\"$name" $value
        }
    }
    where.exe dumpbin  >$null 2>&1
    if (-not $?) { throw "can not find `"dumpbin`" tool" }
}

$graph = @{}

Write-Host "`nBuilding file list"
$list = $path | ForEach-Object {
    $p = $_
    $files | ForEach-Object { $r = Resolve-Path (Join-Path $p $_); if ($r) {$r.Path} }
}
$exclude = $path | ForEach-Object {
    $p = $_
    $filter | ForEach-Object { $r = Resolve-Path (Join-Path $p $_); if ($r) {$r.Path} }
}
$system = "kernel32|user32|advapi32|shell32|gdi32|ole32|oleaut32|comdlg32|winmm|mpr|dwmapi|uxtheme|api-ms-|vcruntime|msvc|ucrt"

Write-Host "`nProcessing files"
$list.Where{ $exclude -notcontains $_ } | ForEach-Object {
    $f = $_
    $fn = (Get-Item $f).Name
    Write-Host "  $f"
    $lines = (dumpbin.exe /dependents "$f") -join "`n"
    if ("$lines" -match 'Image has the following dependencies:[\r\n\s]+((?:[^\r\n]|[\r\n](?![\r\n\s]+Summary))+)') {
        $matches[1] -split '[\r\n]+\s+' | ForEach-Object {
            if ($_ -notmatch "^($system)") {
                if (-not $graph.ContainsKey($fn)) { $graph[$fn] = @{} }
                if (-not $graph.ContainsKey($_))  { $graph[$_] = @{} }
                if (-not $graph[$fn].ContainsKey($_)) { $graph[$fn][$_] = 1 }
                Write-Host "    $fn -> $_"
            }
        }
    }
}

Write-Host "`nOutput graph data"
@'
<?xml version="1.0" encoding="UTF-8"?>
<graphml xmlns="http://graphml.graphdrawing.org/xmlns"
    xmlns:y="http://www.yworks.com/xml/graphml"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://graphml.graphdrawing.org/xmlns/1.0/graphml.xsd">
  <key for="node" id="d6" yfiles.type="nodegraphics"/>
  <graph id="G" edgedefault="undirected">
'@ | Out-File $output -Encoding 'utf8'

$re_id = '[., +!@#$%()={}\[\];?-]'
$graph.GetEnumerator() | Sort-Object -Property key | ForEach-Object {
    $n1 = $_.Name.ToLower() -replace $re_id,'_'
    @"
    <node id="$n1">
      <data key="d6">
        <y:ShapeNode>
          <y:NodeLabel modelName="sides" modelPosition="s">$($_.Name)</y:NodeLabel>
        </y:ShapeNode>
      </data>
    </node>
"@ | Out-File $output -Encoding 'utf8' -Append
}
$i = 1
$graph.GetEnumerator() | Sort-Object -Property key | ForEach-Object {
    $n1 = $_.Name.ToLower() -replace $re_id,'_'
    foreach ($endpoint in $_.Value.Keys) {
        $n2 = $endpoint.ToLower() -replace $re_id,'_'
        "    <edge id=`"e$i`" source=`"$n1`" target=`"$n2`" />" | Out-File $output -Encoding 'utf8' -Append
        $i += 1
    }
}

@'
  </graph>
</graphml>
'@ | Out-File $output -Encoding 'utf8' -Append
