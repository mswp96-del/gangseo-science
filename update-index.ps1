# 지정한 폴더를 훑어서 그 안의 index.json 을 다시 만듭니다.
# 미리보기와 올리기 스크립트가 자동으로 호출하므로, 직접 실행할 일은 없습니다.

param(
  [string]$Root = $PSScriptRoot,
  [string]$Folder = 'posts'
)

$dir = Join-Path $Root $Folder
if (-not (Test-Path $dir -PathType Container)) { return 0 }

$names = @(Get-ChildItem -Path $dir -Filter '*.md' -File |
  Sort-Object Name -Descending |
  ForEach-Object { $_.Name })

if ($names.Count -eq 0) {
  $json = "[]`n"
} else {
  $lines = $names | ForEach-Object { '  ' + (ConvertTo-Json $_) }
  $json = "[`n" + ($lines -join ",`n") + "`n]`n"
}

# JSON 파일에 BOM이 들어가면 브라우저가 읽지 못하므로 BOM 없이 저장합니다.
[IO.File]::WriteAllText((Join-Path $dir 'index.json'), $json, (New-Object Text.UTF8Encoding $false))

$names.Count
