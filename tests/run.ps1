# Windows 오프라인 검증 — Claude Code 없이 훅/게이트 스크립트에 샘플 JSON을 주입해 단언한다.
# run.sh 의 Windows(PowerShell) 대응판. python3 대신 python 사용.
# Windows PowerShell 5.1 / PowerShell 7 모두에서 동작(임시파일+리다이렉션으로 stdin 전달).
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Root = Split-Path -Parent $PSScriptRoot
$script:pass = 0
$script:fail = 0

function Ok($m)  { Write-Host "  ok: $m";  $script:pass++ }
function Bad($m) { Write-Host "  FAIL: $m"; $script:fail++ }

# stdin 을 BOM 없는 UTF-8 로 넘겨 스크립트를 실행(PS 버전 무관)
function Invoke-WithStdin($scriptPath, $stdinText) {
    $tmp = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllText($tmp, $stdinText, [System.Text.UTF8Encoding]::new($false))
    try   { return (cmd /c "python `"$scriptPath`" < `"$tmp`"") }
    finally { Remove-Item -LiteralPath $tmp -Force }
}

# policy.py 결정 단언: $expected = deny|ask|allow
function Decision($desc, $expected, $json) {
    $out = Invoke-WithStdin "$Root/scripts/policy.py" $json
    if ([string]::IsNullOrWhiteSpace($out)) {
        $got = 'allow'
    }
    else {
        try { $got = ($out | ConvertFrom-Json).hookSpecificOutput.permissionDecision }
        catch { $got = '?' }
    }
    if ($got -eq $expected) { Ok $desc } else { Bad "$desc (기대 $expected, 받음 $got)" }
}

Write-Host "== policy.py: 기존 Bash 회귀 =="
Decision "rm -rf 차단"     deny  '{"tool_name":"Bash","tool_input":{"command":"rm -rf / now"}}'
Decision "sudo 차단"       deny  '{"tool_name":"Bash","tool_input":{"command":"sudo apt update"}}'
Decision "git push ask"    ask   '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}'
Decision "정상 명령 allow" allow '{"tool_name":"Bash","tool_input":{"command":"pytest -q"}}'
Decision "cat .env 차단"   deny  '{"tool_name":"Bash","tool_input":{"command":"cat .env"}}'
Decision "rm 하위폴더 allow" allow '{"tool_name":"Bash","tool_input":{"command":"rm -rf ./build"}}'
Decision ".env.example allow" allow '{"tool_name":"Bash","tool_input":{"command":"grep KEY .env.example"}}'

Write-Host "== policy.py: PowerShell 파괴 명령 =="
Decision "Remove-Item C:\ 차단"      deny  '{"tool_name":"PowerShell","tool_input":{"command":"Remove-Item -Recurse -Force C:\\"}}'
Decision "rm 별칭 C:\ 차단"          deny  '{"tool_name":"PowerShell","tool_input":{"command":"rm -r -fo C:\\Windows"}}'
Decision "약식 -rec -fo 차단"        deny  '{"tool_name":"PowerShell","tool_input":{"command":"Remove-Item -rec -fo $HOME"}}'
Decision "-Confirm:$false 차단"      deny  '{"tool_name":"PowerShell","tool_input":{"command":"Remove-Item -Recurse -Confirm:$false D:\\"}}'
Decision "와일드카드 * 차단"         deny  '{"tool_name":"PowerShell","tool_input":{"command":"Remove-Item -Recurse -Force *"}}'
Decision "Format-Volume 차단"        deny  '{"tool_name":"PowerShell","tool_input":{"command":"Format-Volume -DriveLetter D"}}'
Decision "Set-ExecutionPolicy 차단"  deny  '{"tool_name":"PowerShell","tool_input":{"command":"Set-ExecutionPolicy Bypass"}}'
Decision "Stop-Computer 차단"        deny  '{"tool_name":"PowerShell","tool_input":{"command":"Stop-Computer -Force"}}'
Decision "rd /s /q C:\ 차단"         deny  '{"tool_name":"PowerShell","tool_input":{"command":"cmd /c rd /s /q C:\\"}}'

Write-Host "== policy.py: PowerShell 과차단 방지(allow) =="
Decision "하위폴더 삭제 allow"       allow '{"tool_name":"PowerShell","tool_input":{"command":"Remove-Item -Recurse -Force .\\build"}}'
Decision "-Filter 오탐 방지 allow"   allow '{"tool_name":"PowerShell","tool_input":{"command":"Remove-Item -Recurse -Force .\\dist -Filter *.tmp"}}'
Decision "Get-ChildItem allow"       allow '{"tool_name":"PowerShell","tool_input":{"command":"Get-ChildItem C:\\"}}'

Write-Host "== policy.py: PowerShell 시크릿 접근 =="
Decision "Get-Content .env 차단"     deny  '{"tool_name":"PowerShell","tool_input":{"command":"Get-Content .env"}}'
Decision "gc .env 차단"              deny  '{"tool_name":"PowerShell","tool_input":{"command":"gc D:\\proj\\.env"}}'
Decision "id_rsa 차단"               deny  '{"tool_name":"PowerShell","tool_input":{"command":"Get-Content $HOME\\.ssh\\id_rsa"}}'

Write-Host "== policy.py: Windows 경로 시크릿(Read/Write) =="
Decision "Read D:\proj\.env 차단"    deny  '{"tool_name":"Read","tool_input":{"file_path":"D:\\proj\\.env"}}'
Decision "Read .env.local 차단"      deny  '{"tool_name":"Read","tool_input":{"file_path":"C:\\app\\.env.local"}}'
Decision "Write .ssh\\id_rsa 차단"   deny  '{"tool_name":"Write","tool_input":{"file_path":"C:\\Users\\u\\.ssh\\id_rsa"}}'
Decision "정상 .py allow"            allow '{"tool_name":"Read","tool_input":{"file_path":"D:\\proj\\src\\main.py"}}'

Write-Host "== scaffold.ps1 (init) =="
$t = Join-Path $env:TEMP ("omni_scaf_" + [System.Guid]::NewGuid().ToString('N'))
& powershell -NoProfile -ExecutionPolicy Bypass -File "$Root/scripts/scaffold.ps1" $t | Out-Null
if ((Test-Path "$t/AGENTS.md") -and (Test-Path "$t/.claude/settings.json") -and (Test-Path "$t/feature_list.json") -and (Test-Path "$t/wiki/index.md")) { Ok "프로젝트 스캐폴드" } else { Bad "scaffold" }
"MINE" | Set-Content "$t/AGENTS.md"
& powershell -NoProfile -ExecutionPolicy Bypass -File "$Root/scripts/scaffold.ps1" $t | Out-Null
if ((Get-Content "$t/AGENTS.md" -Raw) -match 'MINE') { Ok "기존 파일 보존" } else { Bad "scaffold preserve" }
& powershell -NoProfile -ExecutionPolicy Bypass -File "$Root/scripts/scaffold.ps1" $t -Force | Out-Null
if ((Get-Content "$t/AGENTS.md" -Raw) -notmatch 'MINE') { Ok "-Force 덮어쓰기" } else { Bad "scaffold force" }
Remove-Item -Recurse -Force $t

Write-Host "== JSON 유효성 =="
foreach ($f in @('.claude-plugin/plugin.json', '.claude-plugin/marketplace.json', 'hooks/hooks.json', 'templates/.claude/settings.json')) {
    try { python -c "import json,sys; json.load(open(sys.argv[1], encoding='utf-8'))" "$Root/$f"; Ok "json $f" }
    catch { Bad "json $f" }
}

Write-Host "----"
Write-Host "통과 $script:pass / 실패 $script:fail"
exit $script:fail
