# 워드(.docx) 파일을 블로그 글(.md)로 바꿉니다.
# 쓰는 법: "워드 변환.bat" 위에 워드 파일을 끌어다 놓으세요.
#
# 하는 일
#   - 제목/소제목, 목록, 표, 굵은 글씨를 마크다운으로 변환
#   - 문서 안의 그림을 꺼내 assets 폴더에 넣고 본문에 연결
#   - posts 폴더에 오늘 날짜로 .md 파일 생성 (날짜·제목은 나중에 고치면 됨)

param([Parameter(Mandatory)][string]$DocxPath)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$root = $PSScriptRoot
$W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
$R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
$A = 'http://schemas.openxmlformats.org/drawingml/2006/main'

function Say($msg, $color = 'Gray') { Write-Host "  $msg" -ForegroundColor $color }

Write-Host ''
Write-Host '  ================================================' -ForegroundColor DarkGray
Write-Host '    워드 파일을 블로그 글로 바꾸기' -ForegroundColor Cyan
Write-Host '  ================================================' -ForegroundColor DarkGray
Write-Host ''

if (-not (Test-Path $DocxPath -PathType Leaf)) {
  Say "파일을 찾을 수 없습니다: $DocxPath" Red
  Read-Host '  엔터를 누르면 닫힙니다'; exit 1
}
if ([IO.Path]::GetExtension($DocxPath).ToLower() -ne '.docx') {
  Say '.docx 파일만 바꿀 수 있습니다. (.doc 는 워드에서 .docx 로 저장한 뒤 다시 시도하세요)' Red
  Read-Host '  엔터를 누르면 닫힙니다'; exit 1
}

$baseName = [IO.Path]::GetFileNameWithoutExtension($DocxPath)
Say "원본: $baseName.docx"

# --- 1. 압축 풀기 ---
$work = Join-Path $env:TEMP ("docx2md_" + [guid]::NewGuid().ToString('N'))
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory($DocxPath, $work)

try {
  $doc = [xml](Get-Content (Join-Path $work 'word\document.xml') -Encoding UTF8)
  $nsm = New-Object Xml.XmlNamespaceManager $doc.NameTable
  $nsm.AddNamespace('w', $W); $nsm.AddNamespace('r', $R); $nsm.AddNamespace('a', $A)

  # 그림 관계
  $rels = @{}
  $relPath = Join-Path $work 'word\_rels\document.xml.rels'
  if (Test-Path $relPath) {
    foreach ($rel in ([xml](Get-Content $relPath -Encoding UTF8)).Relationships.Relationship) {
      $rels[$rel.Id] = $rel.Target
    }
  }

  # 번호 목록인지 글머리 기호인지
  $numKind = @{}
  $numPath = Join-Path $work 'word\numbering.xml'
  if (Test-Path $numPath) {
    $numDoc = [xml](Get-Content $numPath -Encoding UTF8)
    $nsm2 = New-Object Xml.XmlNamespaceManager $numDoc.NameTable
    $nsm2.AddNamespace('w', $W)
    $abstract = @{}
    foreach ($an in $numDoc.SelectNodes('//w:abstractNum', $nsm2)) {
      $fmt = $an.SelectSingleNode('w:lvl[@w:ilvl="0"]/w:numFmt/@w:val', $nsm2)
      $abstract[$an.GetAttribute('abstractNumId', $W)] =
        if ($fmt -and $fmt.Value -ne 'bullet') { 'ordered' } else { 'bullet' }
    }
    foreach ($n in $numDoc.SelectNodes('//w:num', $nsm2)) {
      $aid = $n.SelectSingleNode('w:abstractNumId/@w:val', $nsm2)
      if ($aid -and $abstract.ContainsKey($aid.Value)) {
        $numKind[$n.GetAttribute('numId', $W)] = $abstract[$aid.Value]
      }
    }
  }

  # 그림을 넣을 곳. 괄호·공백이 들어가면 마크다운 주소가 깨지므로 안전한 글자만 남김
  $slug = (($baseName -replace '[^\w가-힣.-]', '-') -replace '-{2,}', '-').Trim('-')
  $imgDirName = "img-$slug"
  $imgDir = Join-Path $root "assets\$imgDirName"
  $imgHref = "assets/$imgDirName/"
  $script:imgCount = 0

  function Convert-Paragraph($p) {
    $sb = New-Object Text.StringBuilder
    foreach ($run in $p.SelectNodes('.//w:r', $nsm)) {
      $text = ''
      foreach ($t in $run.SelectNodes('w:t | w:tab | w:br', $nsm)) {
        if ($t.LocalName -eq 't') { $text += $t.InnerText } else { $text += ' ' }
      }
      foreach ($blip in $run.SelectNodes('.//a:blip', $nsm)) {
        $rid = $blip.GetAttribute('embed', $R)
        if ($rid -and $rels.ContainsKey($rid)) {
          $srcImg = Join-Path $work ('word\' + ($rels[$rid] -replace '/', '\'))
          if (Test-Path $srcImg) {
            if (-not (Test-Path $imgDir)) { New-Item -ItemType Directory -Path $imgDir -Force | Out-Null }
            $script:imgCount++
            $name = "fig-$($script:imgCount)" + [IO.Path]::GetExtension($srcImg)
            Copy-Item $srcImg (Join-Path $imgDir $name) -Force
            [void]$sb.Append("`n![그림 $($script:imgCount)]($imgHref$name)`n")
          }
        }
      }
      if (-not $text) { continue }
      if ($run.SelectSingleNode('w:rPr/w:b', $nsm)) { $text = "**$text**" }
      if ($run.SelectSingleNode('w:rPr/w:i', $nsm)) { $text = "*$text*" }
      [void]$sb.Append($text)
    }
    return ($sb.ToString() -replace '\*\*\*\*', '').Trim()
  }

  function Convert-Table($tbl) {
    $rows = @()
    foreach ($tr in $tbl.SelectNodes('w:tr', $nsm)) {
      $cells = @()
      foreach ($tc in $tr.SelectNodes('w:tc', $nsm)) {
        $parts = @()
        foreach ($p in $tc.SelectNodes('w:p', $nsm)) {
          $t = Convert-Paragraph $p
          if ($t) { $parts += $t }
        }
        # 워드 표는 전체가 굵은 경우가 많아 강조 의미가 없으므로 제거
        $cells += ((($parts -join ' ') -replace '\*\*', '') -replace '\|', '\|')
      }
      if ($cells.Count) { $rows += , $cells }
    }
    if (-not $rows.Count) { return '' }
    $width = ($rows | ForEach-Object { $_.Count } | Measure-Object -Maximum).Maximum
    $lines = @()
    for ($i = 0; $i -lt $rows.Count; $i++) {
      $c = @($rows[$i]) + @('') * ($width - $rows[$i].Count)
      $lines += '| ' + ($c -join ' | ') + ' |'
      if ($i -eq 0) { $lines += '| ' + ((1..$width | ForEach-Object { '---' }) -join ' | ') + ' |' }
    }
    return ($lines -join "`n")
  }

  # --- 2. 본문 변환 ---
  $md = New-Object Collections.Generic.List[string]
  $counter = 0
  $docTitle = ''

  foreach ($node in $doc.document.body.ChildNodes) {
    if ($node.LocalName -eq 'tbl') {
      $counter = 0
      $t = Convert-Table $node
      if ($t) { $md.Add(''); $md.Add($t); $md.Add('') }
      continue
    }
    if ($node.LocalName -ne 'p') { continue }

    $text = Convert-Paragraph $node
    if (-not $text) { continue }

    $style = $node.SelectSingleNode('w:pPr/w:pStyle/@w:val', $nsm)
    $styleVal = if ($style) { $style.Value } else { '' }
    $numId = $node.SelectSingleNode('w:pPr/w:numPr/w:numId/@w:val', $nsm)

    # 문서의 첫 '글자' 줄을 제목으로 빼 둠. 그림뿐인 줄은 제목이 될 수 없음
    if (-not $docTitle -and $md.Count -eq 0 -and $text -notmatch '^!\[') {
      $docTitle = ($text -replace '\*\*', '').Trim()
      continue
    }

    if ($styleVal -match '^Heading(\d)$') {
      $counter = 0
      $md.Add('')
      $md.Add(('#' * ([int]$Matches[1] + 1)) + ' ' + ($text -replace '\*\*', ''))
      $md.Add('')
      continue
    }

    if ($numId) {
      $kind = if ($numKind.ContainsKey($numId.Value)) { $numKind[$numId.Value] } else { 'bullet' }
      if ($kind -eq 'ordered') { $counter++; $md.Add("$counter. $text") } else { $md.Add("- $text") }
      continue
    }

    $counter = 0
    if ($text -match '^\*\*(.+)\*\*$' -and $Matches[1] -notmatch '\*\*') {
      $inner = $Matches[1].Trim()
      # 워드에서 소제목을 제목 스타일 대신 굵은 글씨로만 표시한 경우가 많음.
      # "1. 개요", "가. 센서 사용법" 처럼 번호가 붙은 짧은 줄은 소제목으로 본다.
      if ($inner.Length -le 60 -and $inner -match '^(\d+\.|[가나다라마바사아자차카타파하]\.)\s*\S') {
        $level = if ($inner -match '^\d+\.') { 2 } else { 3 }
        $md.Add('')
        $md.Add(('#' * $level) + ' ' + $inner)
        $md.Add('')
      } else {
        # 그 밖의 굵은 문단은 원문의 강조 상자 → 인용 상자로
        $md.Add('> ' + $inner)
        $md.Add('')
      }
    } else {
      $md.Add($text)
      $md.Add('')
    }
  }

  # --- 3. 다듬기 ---
  $body = $md -join "`n"
  $body = [regex]::Replace($body, '(?m)^\*\*(\d+)\.\s*\*\*\s*', '$1. ')          # **1. ** -> 1.
  $body = [regex]::Replace($body, '(?m)(^\d+\. .+)\r?\n\r?\n(?=\d+\. )', "`$1`n") # 번호 목록 묶기
  $body = $body -replace "(`n){3,}", "`n`n"

  if (-not $docTitle) { $docTitle = $baseName }

  $today = Get-Date -Format 'yyyy-MM-dd'
  $front = @"
---
title: $docTitle
date: $today
category: 수업자료
tags: 과학
summary:
---


"@

  # --- 4. 저장 ---
  $outPath = Join-Path $root "posts\$today-$slug.md"
  $n = 2
  while (Test-Path $outPath) {
    $outPath = Join-Path $root "posts\$today-$slug-$n.md"
    $n++
  }
  [IO.File]::WriteAllText($outPath, $front + $body.Trim() + "`n", (New-Object Text.UTF8Encoding $false))

  Write-Host ''
  Say "글 만듦: posts\$([IO.Path]::GetFileName($outPath))" Green
  if ($script:imgCount -gt 0) { Say "그림 $($script:imgCount) 장을 assets\$imgDirName 에 넣었습니다" Green }
  Write-Host ''
  Say '다음에 할 일' White
  Say '  1. 만들어진 파일을 열어 맨 위 date(날짜)와 summary(요약)를 고치세요'
  Say '  2. 미리보기.bat 으로 확인하세요'
  Say '  3. 블로그 올리기.bat 으로 올리세요'
  Write-Host ''
  Say '워드의 수식과 도형은 그림으로 들어가지 않으면 사라질 수 있습니다. 확인해 보세요.' Yellow

} finally {
  Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Read-Host '  엔터를 누르면 닫힙니다'
