@echo off
title Blog Preview
start "" http://localhost:8321
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0serve.ps1" -Port 8321
