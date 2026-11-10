@echo off
rem Duplo clique: gera ia-web-export.json na pasta Backup do agIAWeb.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Exportar-IAWeb.ps1"
pause
