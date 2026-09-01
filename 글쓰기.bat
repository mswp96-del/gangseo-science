@echo off
title Blog Write
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0write-server.ps1"
