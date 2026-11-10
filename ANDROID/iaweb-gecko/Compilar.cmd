@echo off
rem Duplo clique para compilar. Argumentos sao repassados (ex.: Compilar.cmd -Instalar).
rem A janela so fecha quando voce apertar uma tecla, mesmo se o PowerShell falhar.
cd /d "%~dp0"
set "PS=powershell"
where pwsh >nul 2>nul && set "PS=pwsh"
%PS% -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-iaweb.ps1" -SemPausa %*
set "COD=%ERRORLEVEL%"
echo.
echo Terminou (codigo %COD%).
pause
