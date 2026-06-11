# templates/ → 프로젝트 스캐폴드 (scaffold.sh 의 PowerShell 포트).
# 기존 파일은 보존(덮어쓰지 않음). -Force 면 덮어쓰기.
# 사용: powershell -File scaffold.ps1 [대상경로] [-Force]
[CmdletBinding()]
param(
    [string]$Dest,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'

# 플러그인 루트: CLAUDE_PLUGIN_ROOT 우선, 없으면 이 스크립트의 상위 폴더
$here = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$root = if ($env:CLAUDE_PLUGIN_ROOT) { $env:CLAUDE_PLUGIN_ROOT } else { $here }
$src = Join-Path $root 'templates'

# 대상: 인자 > CLAUDE_PROJECT_DIR > 현재 폴더
if (-not $Dest) {
    $Dest = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { '.' }
}

if (-not (Test-Path -LiteralPath $src)) {
    Write-Error "templates 없음: $src"
    exit 1
}

$copied = 0
$skipped = 0
$srcFull = (Resolve-Path -LiteralPath $src).Path

Get-ChildItem -LiteralPath $src -Recurse -File -Force | ForEach-Object {
    $rel = $_.FullName.Substring($srcFull.Length).TrimStart('\', '/')
    $target = Join-Path $Dest $rel
    if ((Test-Path -LiteralPath $target) -and -not $Force) {
        $skipped++
    }
    else {
        $dir = Split-Path -Parent $target
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
        Copy-Item -LiteralPath $_.FullName -Destination $target -Force
        $copied++
    }
}

Write-Host "스캐폴드: $copied 복사, $skipped 보존 → $Dest"
Write-Host "  AGENTS.md(헌법) · .claude/settings.json(권한) · wiki/ · feature_list.json · init.sh"
