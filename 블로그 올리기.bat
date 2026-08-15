@echo off
title Blog Upload
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0upload.ps1"
