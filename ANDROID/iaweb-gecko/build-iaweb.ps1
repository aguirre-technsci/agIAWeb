<#
 build-iaweb.ps1 - gera o APK do IA Web (GeckoView). Rode na pasta do projeto.
   .\build-iaweb.ps1                       -> compila; APK em apk\iaweb-gecko.apk
   .\build-iaweb.ps1 -Instalar             -> compila e instala por ADB (celular por cabo, depuracao USB)
   .\build-iaweb.ps1 -GeckoVersion 1xx.y.z -> fixa a versao do GeckoView (em vez de pegar a mais nova)
   .\build-iaweb.ps1 -SemPausa            -> nao espera Enter no final (para uso em scripts)
 A janela fica aberta ao terminar, ao dar erro ou ao ser interrompida (Ctrl+C): ela espera Enter.
 Para garantir tambem contra erro de sintaxe/pwsh ausente, use o Compilar.cmd (duplo clique).
 Texto sem acentos de proposito (o PowerShell 5.1 le arquivo sem BOM como ANSI).
#>
param(
    [string]$GeckoVersion = '',
    [switch]$Instalar,
    [switch]$SemPausa
)
$ErrorActionPreference = 'Stop'
$proj = $PSScriptRoot
$codigo = 0
$script:esperada = $false

# Falha lanca excecao; o catch no fim mostra a mensagem e o finally mantem a janela aberta.
function Falha($m) { $script:esperada = $true; throw $m }

try {
Set-Location $proj

# 1. JDK 17 -------------------------------------------------------------
function JavaMajor($home_) {
    $exe = Join-Path $home_ 'bin\java.exe'
    if (-not (Test-Path $exe)) { return 0 }
    $out = & $exe -version 2>&1 | Out-String
    if ($out -match 'version "(\d+)') { return [int]$Matches[1] }
    return 0
}
$cands = @($env:JAVA_HOME)
foreach ($raiz in @("$env:ProgramFiles\Eclipse Adoptium", "$env:ProgramFiles\Microsoft", "$env:ProgramFiles\Java", "$env:ProgramFiles\Amazon Corretto", "$env:ProgramFiles\Zulu")) {
    if (Test-Path $raiz) { $cands += (Get-ChildItem $raiz -Directory -Filter '*17*' -ErrorAction SilentlyContinue).FullName }
}
$jdk = $cands | Where-Object { $_ -and (JavaMajor $_) -eq 17 } | Select-Object -First 1
if (-not $jdk) { Falha "JDK 17 nao encontrado. Instale um JDK 17 ou defina JAVA_HOME apontando para ele. (O JBR do Android Studio pode ser de outra versao e nao ser compativel com este projeto.)" }
$env:JAVA_HOME = $jdk
Write-Host "JDK 17: $jdk"

# 2. Android SDK ----------------------------------------------------------
$sdk = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, "$env:LOCALAPPDATA\Android\Sdk") |
    Where-Object { $_ -and (Test-Path (Join-Path $_ 'platforms')) } | Select-Object -First 1
if (-not $sdk) { Falha "Android SDK nao encontrado (esperado em $env:LOCALAPPDATA\Android\Sdk ou em ANDROID_HOME)." }
Write-Host "SDK: $sdk"
if (-not (Get-ChildItem (Join-Path $sdk 'platforms') -Directory -Filter 'android-37*' -ErrorAction SilentlyContinue)) {
    Write-Host "AVISO: plataforma android-37 nao instalada. O Gradle tenta baixar sozinho se as licencas estiverem aceitas; se falhar, rode:" -ForegroundColor Yellow
    Write-Host "  & `"$sdk\cmdline-tools\latest\bin\sdkmanager.bat`" `"platforms;android-37`"" -ForegroundColor Yellow
}
# local.properties precisa de barras duplas no Windows
Set-Content -Path (Join-Path $proj 'local.properties') -Value ("sdk.dir=" + ($sdk -replace '\\', '\\')) -Encoding ASCII

# 3. Versao do GeckoView ----------------------------------------------------
if (-not $GeckoVersion) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $url = 'https://maven.mozilla.org/maven2/org/mozilla/geckoview/geckoview/maven-metadata.xml'
        $xml = [xml](New-Object Net.WebClient).DownloadString($url)
        $GeckoVersion = $xml.metadata.versioning.release
        if (-not $GeckoVersion) { $GeckoVersion = $xml.metadata.versioning.latest }
    } catch {
        Falha "Nao consegui consultar a versao do GeckoView em maven.mozilla.org ($($_.Exception.Message)). Passe -GeckoVersion manualmente."
    }
}
if (-not $GeckoVersion) { Falha "Versao do GeckoView vazia. Passe -GeckoVersion." }
Write-Host "GeckoView: $GeckoVersion"

# 4. Compilar -------------------------------------------------------------
& "$proj\gradlew.bat" --no-daemon "-PgeckoVersion=$GeckoVersion" assembleDebug
if ($LASTEXITCODE -ne 0) { Falha "Gradle falhou (codigo $LASTEXITCODE). Veja a saida do Gradle acima." }

$apkOrigem = Join-Path $proj 'app\build\outputs\apk\debug\app-debug.apk'
if (-not (Test-Path $apkOrigem)) { Falha "APK nao encontrado em $apkOrigem" }
New-Item -ItemType Directory -Force -Path (Join-Path $proj 'apk') | Out-Null
$apk = Join-Path $proj 'apk\iaweb-gecko.apk'
Copy-Item $apkOrigem $apk -Force
Set-Content -Path (Join-Path $proj 'apk\VERSAO-GECKO.txt') -Value $GeckoVersion -Encoding ASCII
Write-Host ("APK: $apk ({0:N1} MB)" -f ((Get-Item $apk).Length / 1MB)) -ForegroundColor Green

# 5. Instalar (opcional) ----------------------------------------------------
if ($Instalar) {
    $adb = Join-Path $sdk 'platform-tools\adb.exe'
    if (-not (Test-Path $adb)) { Falha "adb.exe nao encontrado em $adb" }
    $dev = & $adb devices | Select-String "`tdevice$"
    if (-not $dev) { Falha "Nenhum aparelho autorizado. Cabo conectado, Depuracao USB ligada e chave RSA aceita no celular?" }
    & $adb install -r $apk
    if ($LASTEXITCODE -ne 0) { Falha "adb install falhou. Se disser INSTALL_FAILED_UPDATE_INCOMPATIBLE, a assinatura mudou: desinstalar apaga os logins do app." }
    Write-Host "Instalado." -ForegroundColor Green
}
Write-Host ""
Write-Host "Concluido." -ForegroundColor Green
}
catch {
    $codigo = 1
    Write-Host ""
    Write-Host "ERRO: $($_.Exception.Message)" -ForegroundColor Red
    # erro inesperado (nao lancado por Falha): mostra onde ocorreu
    if (-not $script:esperada) {
        Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
    }
}
finally {
    # roda ao terminar, em erro e tambem em Ctrl+C
    if (-not $SemPausa) {
        Write-Host ""
        Read-Host "Pressione Enter para fechar" | Out-Null
    }
}
exit $codigo
