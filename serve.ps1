# 블로그 로컬 미리보기 서버
# 사용법: PowerShell에서  .\serve.ps1   (종료는 Ctrl+C)

param([int]$Port = 8080)

$root = $PSScriptRoot
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
}

$updateIndex = Join-Path $root 'update-index.ps1'

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()

Write-Host "블로그 미리보기: http://localhost:$Port/" -ForegroundColor Green
Write-Host "종료하려면 Ctrl+C 를 누르세요."

try {
  while ($listener.IsListening) {
    $context = $listener.GetContext()
    $path = [Uri]::UnescapeDataString($context.Request.Url.AbsolutePath)
    if ($path -eq '/') { $path = '/index.html' }

    # 글 목록을 요청할 때마다 해당 폴더를 다시 훑습니다. (posts, 일기, 비공개 모두)
    if ($path -match '^/([^/]+)/index\.json$') {
      & $updateIndex -Folder $Matches[1] | Out-Null
    }

    $full = Join-Path $root ($path.TrimStart('/') -replace '/', '\')
    $resolved = [System.IO.Path]::GetFullPath($full)

    if ($resolved.StartsWith($root) -and (Test-Path $resolved -PathType Leaf)) {
      $ext = [System.IO.Path]::GetExtension($resolved).ToLower()
      $context.Response.ContentType = if ($types.ContainsKey($ext)) { $types[$ext] } else { 'application/octet-stream' }
      $bytes = [System.IO.File]::ReadAllBytes($resolved)
      $context.Response.ContentLength64 = $bytes.Length
      $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    } else {
      $context.Response.StatusCode = 404
      $bytes = [System.Text.Encoding]::UTF8.GetBytes('404 Not Found')
      $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    }

    $context.Response.OutputStream.Close()
  }
} finally {
  $listener.Stop()
  $listener.Close()
}
