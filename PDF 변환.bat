@echo off
title PDF to Blog Post
if "%~1"=="" (
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Write-Host ''; Write-Host '  [ PDF to Blog ]' -ForegroundColor Cyan; Write-Host ''; Write-Host '  PDF 파일을 이 아이콘 위로 끌어다 놓으세요.'; Write-Host ''; Read-Host '  엔터를 누르면 닫힙니다'"
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pdf-to-md.ps1" -PdfPath "%~1"
