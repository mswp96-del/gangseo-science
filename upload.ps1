# 블로그 올리기 — "블로그 올리기.bat" 을 더블클릭하면 이 스크립트가 실행됩니다.

try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
Set-Location $PSScriptRoot

$siteUrl = 'https://mswp96-del.github.io/gangseo-science/'

Write-Host ''
Write-Host '  ================================================' -ForegroundColor DarkGray
Write-Host '    강서중 과학수업 블로그 올리기' -ForegroundColor Cyan
Write-Host '  ================================================' -ForegroundColor DarkGray
Write-Host ''

$count = & (Join-Path $PSScriptRoot 'update-index.ps1')
Write-Host "  글 $count 개를 목록에 반영했습니다." -ForegroundColor DarkGray

# 디자인·기능 파일이 바뀌면 주소 뒤 번호를 갈아 끼웁니다.
# 이걸 안 하면 이미 블로그를 본 적 있는 사람의 브라우저가 옛 파일을 계속 씁니다.
$stamp = -join (@('assets\app.js', 'assets\style.css') | ForEach-Object {
  (Get-FileHash (Join-Path $PSScriptRoot $_) -Algorithm MD5).Hash.Substring(0, 4)
}).ToLower()

foreach ($page in @('index.html', 'post.html')) {
  $path = Join-Path $PSScriptRoot $page
  $text = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
  $new = [regex]::Replace($text, 'assets/(app\.js|style\.css)(\?v=[0-9a-f]+)?', "assets/`$1?v=$stamp")
  if ($new -ne $text) {
    [IO.File]::WriteAllText($path, $new, (New-Object Text.UTF8Encoding $false))
    Write-Host "  $page 의 파일 번호를 갱신했습니다." -ForegroundColor DarkGray
  }
}

Write-Host ''

git add -A
git diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
  Write-Host '  바뀐 내용이 없습니다. 올릴 것이 없어요.' -ForegroundColor Yellow
  Write-Host ''
  Read-Host '  엔터를 누르면 닫힙니다'
  exit
}

Write-Host '  아래 파일을 인터넷에 올립니다.' -ForegroundColor White
Write-Host ''
git diff --cached --name-only | ForEach-Object { Write-Host "    - $_" -ForegroundColor Gray }
Write-Host ''

git commit -m "글 수정 $(Get-Date -Format 'yyyy-MM-dd HH:mm')" | Out-Null
if ($LASTEXITCODE -ne 0) {
  Write-Host '  [실패] 저장하는 중 문제가 생겼습니다.' -ForegroundColor Red
  Write-Host ''
  Read-Host '  엔터를 누르면 닫힙니다'
  exit
}

Write-Host '  올리는 중...' -ForegroundColor DarkGray
git push
if ($LASTEXITCODE -ne 0) {
  Write-Host ''
  Write-Host '  [실패] 올리는 중 문제가 생겼습니다.' -ForegroundColor Red
  Write-Host '  인터넷 연결을 확인하거나, 이 화면을 클로드에게 보여주세요.' -ForegroundColor Red
  Write-Host ''
  Read-Host '  엔터를 누르면 닫힙니다'
  exit
}

Write-Host ''
Write-Host '  ================================================' -ForegroundColor DarkGray
Write-Host '    다 됐습니다!' -ForegroundColor Green
Write-Host ''
Write-Host '    1분쯤 뒤에 아래 주소에서 확인하세요.'
Write-Host "    $siteUrl" -ForegroundColor Cyan
Write-Host '  ================================================' -ForegroundColor DarkGray
Write-Host ''
Read-Host '  엔터를 누르면 닫힙니다'
