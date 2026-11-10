@echo off
rem Instala o IA Web em %LOCALAPPDATA%\IAWeb e cria o atalho "IA Web" no Menu Iniciar (o atalho antigo "Claude Web" e apagado).
rem Pode rodar de novo a qualquer momento para atualizar os arquivos (contas e logins nao sao apagados).
set "D=%LOCALAPPDATA%\IAWeb"
if not exist "%D%" mkdir "%D%"
copy /y "%~dp0IA_Web.ps1" "%D%" >nul || (echo Nao achei o IA_Web.ps1 ao lado deste arquivo. & pause & exit /b 1)
copy /y "%~dp0*.ico" "%D%" >nul
rem Versao antiga (Claude Web): apaga o programa antigo. Contas e logins sao migrados pelo proprio IA_Web.ps1 na primeira abertura.
if exist "%LOCALAPPDATA%\ClaudeWeb" rmdir /s /q "%LOCALAPPDATA%\ClaudeWeb"
powershell -NoProfile -ExecutionPolicy Bypass -File "%D%\IA_Web.ps1" -Atalho
