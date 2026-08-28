# 글쓰기 앱 서버 — "글쓰기.bat" 을 더블클릭하면 이 스크립트가 실행됩니다.
# 브라우저에 글쓰기 화면을 띄우고, 저장 · 사진 올리기 · 인터넷에 올리기를 대신 해 줍니다.
# 종료는 검은 창을 닫으면 됩니다.

param([int]$Port = 8322)

try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$root = $PSScriptRoot
$siteUrl = 'https://mswp96-del.github.io/gangseo-science/'
$updateIndex = Join-Path $root 'update-index.ps1'
$utf8NoBom = New-Object Text.UTF8Encoding $false

$types = @{
  '.html' = 'text/html; charset=utf-8'
  '.css'  = 'text/css; charset=utf-8'
  '.js'   = 'text/javascript; charset=utf-8'
  '.json' = 'application/json; charset=utf-8'
  '.md'   = 'text/plain; charset=utf-8'
  '.png'  = 'image/png'
  '.jpg'  = 'image/jpeg'
  '.jpeg' = 'image/jpeg'
  '.gif'  = 'image/gif'
  '.svg'  = 'image/svg+xml'
  '.webp' = 'image/webp'
  '.pdf'  = 'application/pdf'
  '.mp4'  = 'video/mp4'
  '.webm' = 'video/webm'
  '.mov'  = 'video/quicktime'
  '.m4v'  = 'video/x-m4v'
}

# 파일 이름에 쓰면 안 되는 글자가 있는지, 폴더를 빠져나가려 하지는 않는지 확인합니다.
function Test-SafeName([string]$name) {
  if ([string]::IsNullOrWhiteSpace($name)) { return $false }
  if ($name -match '[\\/:*?"<>|]') { return $false }
  if ($name -match '\.\.') { return $false }
  return $true
}

function Test-SafeFolder([string]$folder) {
  if ([string]::IsNullOrWhiteSpace($folder)) { return $false }
  if ($folder -notmatch '^assets(/[^\\/:*?"<>|]+)*$') { return $false }
  if ($folder -match '\.\.') { return $false }
  return $true
}

# 디자인·기능 파일이 바뀌면 주소 뒤 번호를 갈아 끼웁니다. (방문자 브라우저가 옛 파일을 쓰지 않도록)
function Update-CacheStamp {
  $stamp = -join (@('assets\app.js', 'assets\style.css') | ForEach-Object {
    (Get-FileHash (Join-Path $root $_) -Algorithm MD5).Hash.Substring(0, 4)
  }).ToLower()

  foreach ($page in @('index.html', 'post.html')) {
    $path = Join-Path $root $page
    if (-not (Test-Path $path)) { continue }
    $text = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    $new = [regex]::Replace($text, 'assets/(app\.js|style\.css)(\?v=[0-9a-f]+)?', "assets/`$1?v=$stamp")
    if ($new -ne $text) { [IO.File]::WriteAllText($path, $new, $utf8NoBom) }
  }
}

# git 을 부르고 화면 출력을 글자로 받아 옵니다.
# ($ErrorActionPreference 를 낮춰야 git 이 stderr 에 적는 안내문이 빨간 오류로 튀지 않습니다)
function Invoke-Git {
  $old = $ErrorActionPreference
  $ErrorActionPreference = 'SilentlyContinue'
  try {
    $out = & git @args 2>&1 | ForEach-Object { $_.ToString() }
    $script:GitExit = $LASTEXITCODE
    return ($out -join [Environment]::NewLine)
  } finally {
    $ErrorActionPreference = $old
  }
}

# 처음 한 번, 이 저장소에 쓸 이름·메일과 줄바꿈 설정을 채워 둡니다.
function Initialize-GitConfig {
  if (-not (Invoke-Git config user.email)) {
    $url = Invoke-Git config --get remote.origin.url
    $owner = if ($url -match 'github\.com[:/]([^/]+)/') { $Matches[1] } else { 'blog' }
    Invoke-Git config user.name $owner | Out-Null
    Invoke-Git config user.email "$owner@users.noreply.github.com" | Out-Null
  }
  if (-not (Invoke-Git config core.autocrlf)) { Invoke-Git config core.autocrlf false | Out-Null }
}

function Invoke-Publish {
  Push-Location $root
  try {
    & $updateIndex | Out-Null
    Update-CacheStamp
    Initialize-GitConfig

    $log = New-Object Text.StringBuilder
    [void]$log.AppendLine((Invoke-Git add -A))

    Invoke-Git diff --cached --quiet | Out-Null
    if ($script:GitExit -eq 0) {
      return @{ ok = $true; changed = $false; log = '바뀐 내용이 없습니다.' }
    }

    [void]$log.AppendLine((Invoke-Git commit -m "글 수정 $(Get-Date -Format 'yyyy-MM-dd HH:mm')"))
    if ($script:GitExit -ne 0) { return @{ ok = $false; error = "저장 실패`n$($log.ToString())" } }

    [void]$log.AppendLine((Invoke-Git push))
    if ($script:GitExit -ne 0) {
      return @{ ok = $false; error = "올리기 실패 — 인터넷 연결이나 GitHub 로그인을 확인해 주세요.`n$($log.ToString())" }
    }

    return @{ ok = $true; changed = $true; log = $log.ToString() }
  } catch {
    return @{ ok = $false; error = $_.Exception.Message }
  } finally {
    Pop-Location
  }
}

function Invoke-Api([string]$name, $data) {
  switch ($name) {

    'mode' { return @{ ok = $true; mode = 'local'; site = $siteUrl } }

    'save' {
      if (-not (Test-SafeName $data.file) -or $data.file -notmatch '\.md$') {
        return @{ ok = $false; error = "파일 이름에 쓸 수 없는 글자가 있습니다: $($data.file)" }
      }
      $postsDir = Join-Path $root 'posts'
      if (-not (Test-Path $postsDir)) { New-Item -ItemType Directory -Path $postsDir | Out-Null }
      [IO.File]::WriteAllText((Join-Path $postsDir $data.file), [string]$data.content, $utf8NoBom)

      if ($data.oldFile -and (Test-SafeName $data.oldFile)) {
        $old = Join-Path $postsDir $data.oldFile
        if (Test-Path $old) { Remove-Item $old -Force }
      }
      & $updateIndex | Out-Null
      return @{ ok = $true; file = $data.file }
    }

    'delete' {
      if (-not (Test-SafeName $data.file)) { return @{ ok = $false; error = '파일 이름이 이상합니다.' } }
      $target = Join-Path (Join-Path $root 'posts') $data.file
      if (Test-Path $target) { Remove-Item $target -Force }
      & $updateIndex | Out-Null
      return @{ ok = $true }
    }

    'upload' {
      if (-not (Test-SafeFolder $data.folder) -or -not (Test-SafeName $data.name)) {
        return @{ ok = $false; error = '파일 또는 폴더 이름에 쓸 수 없는 글자가 있습니다.' }
      }
      $dir = Join-Path $root ($data.folder -replace '/', '\')
      if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
      $bytes = [Convert]::FromBase64String([string]$data.base64)
      [IO.File]::WriteAllBytes((Join-Path $dir $data.name), $bytes)
      return @{ ok = $true; path = "$($data.folder)/$($data.name)"; bytes = $bytes.Length }
    }

    'publish' { return Invoke-Publish }

    default { return @{ ok = $false; error = "모르는 요청입니다: $name" } }
  }
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")

try {
  $listener.Start()
} catch {
  Write-Host ''
  Write-Host "  [실패] $Port 번 포트를 쓸 수 없습니다. 글쓰기 창이 이미 열려 있는지 확인해 주세요." -ForegroundColor Red
  Write-Host ''
  Read-Host '  엔터를 누르면 닫힙니다'
  exit
}

Write-Host ''
Write-Host '  ================================================' -ForegroundColor DarkGray
Write-Host '    강서중 과학수업 · 글쓰기' -ForegroundColor Cyan
Write-Host '  ================================================' -ForegroundColor DarkGray
Write-Host ''
Write-Host "    글쓰기 화면 : http://localhost:$Port/" -ForegroundColor Green
Write-Host "    블로그 미리보기 : http://localhost:$Port/index.html" -ForegroundColor Green
Write-Host ''
Write-Host '    다 쓰셨으면 이 검은 창을 닫으세요.' -ForegroundColor DarkGray
Write-Host ''

try { Start-Process "http://localhost:$Port/" } catch {}

try {
  while ($listener.IsListening) {
    $context = $listener.GetContext()
    $request = $context.Request
    $response = $context.Response
    $path = [Uri]::UnescapeDataString($request.Url.AbsolutePath)
    if ($path -eq '/') { $path = '/write.html' }

    try {
      if ($path -like '/api/*') {
        $body = ''
        if ($request.HasEntityBody) {
          $reader = New-Object IO.StreamReader($request.InputStream, [Text.Encoding]::UTF8)
          $body = $reader.ReadToEnd()
          $reader.Close()
        }
        $data = if ($body) { $body | ConvertFrom-Json } else { $null }
        $name = $path.Substring(5)

        Write-Host ("  · {0}  {1}" -f (Get-Date -Format 'HH:mm:ss'), $name) -ForegroundColor DarkGray
        $result = Invoke-Api $name $data

        $json = ConvertTo-Json $result -Depth 5 -Compress
        $bytes = [Text.Encoding]::UTF8.GetBytes($json)
        $response.ContentType = 'application/json; charset=utf-8'
        $response.StatusCode = if ($result.ok) { 200 } else { 400 }
        $response.ContentLength64 = $bytes.Length
        $response.OutputStream.Write($bytes, 0, $bytes.Length)
      } else {
        # 글 목록을 요청할 때마다 폴더를 다시 훑습니다.
        if ($path -match '^/([^/]+)/index\.json$') { & $updateIndex -Folder $Matches[1] | Out-Null }

        $full = Join-Path $root ($path.TrimStart('/') -replace '/', '\')
        $resolved = [IO.Path]::GetFullPath($full)

        if ($resolved.StartsWith($root) -and (Test-Path $resolved -PathType Leaf)) {
          $ext = [IO.Path]::GetExtension($resolved).ToLower()
          $response.ContentType = if ($types.ContainsKey($ext)) { $types[$ext] } else { 'application/octet-stream' }
          $response.Headers.Add('Cache-Control', 'no-store')
          $bytes = [IO.File]::ReadAllBytes($resolved)
          $response.ContentLength64 = $bytes.Length
          $response.OutputStream.Write($bytes, 0, $bytes.Length)
        } else {
          $response.StatusCode = 404
          $bytes = [Text.Encoding]::UTF8.GetBytes('404 Not Found')
          $response.OutputStream.Write($bytes, 0, $bytes.Length)
        }
      }
    } catch {
      $message = $_.Exception.Message
      Write-Host "  [오류] $message" -ForegroundColor Red
      $bytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json @{ ok = $false; error = $message } -Compress))
      $response.StatusCode = 500
      $response.ContentType = 'application/json; charset=utf-8'
      $response.OutputStream.Write($bytes, 0, $bytes.Length)
    }

    $response.OutputStream.Close()
  }
} finally {
  $listener.Stop()
  $listener.Close()
}
