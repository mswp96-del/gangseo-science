# PDF 파일을 블로그 글(.md)로 바꿉니다.
# 쓰는 법: "PDF 변환.bat" 위에 PDF 파일을 끌어다 놓으세요.
#
# PDF의 각 쪽을 그림으로 만들어 슬라이드처럼 싣습니다.
# Windows에 들어 있는 기능만 쓰므로 따로 설치할 것이 없습니다.
#
# 주의: 글자를 뽑아내는 것이 아니라 쪽을 사진으로 찍는 방식입니다.
#       글자가 들어 있는 PDF를 '글'로 만들고 싶으면 Word로 연 뒤 .docx로 저장해
#       "워드 변환.bat" 을 쓰세요.

param(
  [Parameter(Mandatory)][string]$PdfPath,
  [int]$Width = 1400
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$root = $PSScriptRoot
function Say($m, $c = 'Gray') { Write-Host "  $m" -ForegroundColor $c }

Write-Host ''
Write-Host '  ================================================' -ForegroundColor DarkGray
Write-Host '    PDF를 블로그 글로 바꾸기' -ForegroundColor Cyan
Write-Host '  ================================================' -ForegroundColor DarkGray
Write-Host ''

if (-not (Test-Path $PdfPath -PathType Leaf)) {
  Say "파일을 찾을 수 없습니다: $PdfPath" Red
  Read-Host '  엔터를 누르면 닫힙니다'; exit 1
}

$baseName = [IO.Path]::GetFileNameWithoutExtension($PdfPath)
Say "원본: $baseName.pdf"

# --- WinRT 준비 ---
Add-Type -AssemblyName System.Runtime.WindowsRuntime
Add-Type -AssemblyName System.Drawing

$methods = [System.WindowsRuntimeSystemExtensions].GetMethods()
$asTaskOp = ($methods | Where-Object {
  $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
  $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
$asTaskAct = ($methods | Where-Object {
  $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
  $_.GetParameters()[0].ParameterType.FullName -eq 'Windows.Foundation.IAsyncAction' })[0]

function AwaitOp($op, $type) {
  $t = $asTaskOp.MakeGenericMethod($type).Invoke($null, @($op))
  if (-not $t.Wait(120000)) { throw '시간이 너무 오래 걸립니다' }
  $t.Result
}
function AwaitAct($act) {
  $t = $asTaskAct.Invoke($null, @($act))
  if (-not $t.Wait(120000)) { throw '시간이 너무 오래 걸립니다' }
}

[Windows.Storage.StorageFile, Windows.Storage, ContentType=WindowsRuntime] | Out-Null
[Windows.Data.Pdf.PdfDocument, Windows.Data.Pdf, ContentType=WindowsRuntime] | Out-Null
[Windows.Storage.Streams.InMemoryRandomAccessStream, Windows.Storage.Streams, ContentType=WindowsRuntime] | Out-Null
[Windows.Storage.Streams.DataReader, Windows.Storage.Streams, ContentType=WindowsRuntime] | Out-Null

# 인터넷에서 받은 표시가 있으면 막힐 수 있으므로 사본으로 작업
$temp = Join-Path $env:TEMP ("pdf2md_" + [guid]::NewGuid().ToString('N') + '.pdf')
Copy-Item $PdfPath $temp -Force
try { Unblock-File $temp } catch {}

try {
  $file = AwaitOp ([Windows.Storage.StorageFile]::GetFileFromPathAsync($temp)) ([Windows.Storage.StorageFile])
  $pdf = AwaitOp ([Windows.Data.Pdf.PdfDocument]::LoadFromFileAsync($file)) ([Windows.Data.Pdf.PdfDocument])
  $pages = [int]$pdf.PageCount
  Say "$pages 쪽을 그림으로 바꾸는 중..."

  $imgDirName = "pdf-$baseName"
  $imgDir = Join-Path $root "assets\$imgDirName"
  if (-not (Test-Path $imgDir)) { New-Item -ItemType Directory -Path $imgDir -Force | Out-Null }

  # JPEG로 저장하기 위한 설정 (용량 절감)
  $jpeg = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
  $encParams = New-Object Drawing.Imaging.EncoderParameters 1
  $encParams.Param[0] = New-Object Drawing.Imaging.EncoderParameter ([Drawing.Imaging.Encoder]::Quality, 85)

  $opts = New-Object Windows.Data.Pdf.PdfPageRenderOptions
  $opts.DestinationWidth = [uint32]$Width

  $totalKB = 0
  for ($i = 0; $i -lt $pages; $i++) {
    $page = $pdf.GetPage($i)
    $stream = New-Object Windows.Storage.Streams.InMemoryRandomAccessStream
    AwaitAct ($page.RenderToStreamAsync($stream, $opts))

    $size = [uint32]$stream.Size
    $reader = New-Object Windows.Storage.Streams.DataReader ($stream.GetInputStreamAt(0))
    AwaitOp ($reader.LoadAsync($size)) ([uint32]) | Out-Null
    $bytes = New-Object byte[] $size
    $reader.ReadBytes($bytes)
    $reader.Dispose(); $stream.Dispose()

    # PNG 원본을 JPEG로 다시 저장
    $ms = New-Object IO.MemoryStream (, $bytes)
    $bmp = [Drawing.Image]::FromStream($ms)
    $outFile = Join-Path $imgDir ("page-{0}.jpg" -f ($i + 1))
    $bmp.Save($outFile, $jpeg, $encParams)
    $bmp.Dispose(); $ms.Dispose()

    $totalKB += [math]::Round((Get-Item $outFile).Length / 1KB)
    Write-Host "`r  $($i + 1) / $pages 쪽" -NoNewline -ForegroundColor DarkGray
  }
  Write-Host ''

  # --- 글 만들기 ---
  $today = Get-Date -Format 'yyyy-MM-dd'
  $safe = ($baseName -replace '[\\/:*?"<>|]', '-')
  $outMd = Join-Path $root "posts\$today-$safe.md"
  $n = 2
  while (Test-Path $outMd) { $outMd = Join-Path $root "posts\$today-$safe-$n.md"; $n++ }

  $lines = @(
    '---'
    "title: $baseName"
    "date: $today"
    'category: 수업자료'
    'tags: 과학, 슬라이드'
    "summary: PDF 자료 $pages 쪽을 옮긴 글입니다."
    '---'
    ''
    "PDF 자료를 옮긴 글입니다. 전체 $pages 쪽입니다."
  )
  for ($i = 1; $i -le $pages; $i++) {
    $lines += ''
    $lines += "### $i 쪽"
    $lines += ''
    $lines += "![$i 쪽](assets/$imgDirName/page-$i.jpg)"
  }

  [IO.File]::WriteAllText($outMd, ($lines -join "`n") + "`n", (New-Object Text.UTF8Encoding $false))

  Write-Host ''
  Say "글 만듦: posts\$([IO.Path]::GetFileName($outMd))" Green
  Say "그림 $pages 장 (합계 약 $totalKB KB) → assets\$imgDirName" Green
  Write-Host ''
  Say '다음에 할 일' White
  Say '  1. 만들어진 파일을 열어 맨 위 title(제목)과 summary(요약)를 고치세요'
  Say '  2. 미리보기.bat 으로 확인하세요'
  Say '  3. 블로그 올리기.bat 으로 올리세요'
  Write-Host ''
  Say '쪽을 사진으로 찍는 방식이라 글자를 검색할 수는 없습니다.' Yellow
  Say '글자가 있는 PDF를 본문까지 살리려면 Word로 연 뒤 .docx로 저장해 "워드 변환.bat"을 쓰세요.' Yellow

} catch {
  Write-Host ''
  Say "변환 실패: $($_.Exception.Message)" Red
} finally {
  Remove-Item $temp -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Read-Host '  엔터를 누르면 닫힙니다'
