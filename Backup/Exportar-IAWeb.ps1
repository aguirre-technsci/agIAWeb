# Exporta a lista do IA Web (e-mails, tags, fixados, limites ativos, ordem, IAs extras) para um JSON que o app Android importa.
# NAO leva cookies nem pastas de perfil: o login e refeito na mao no celular. So le, nunca altera nada em IAWebDados.
param([string]$Saida = (Join-Path $PSScriptRoot 'ia-web-export.json'))
$ErrorActionPreference = 'Stop'
$d = "$env:LOCALAPPDATA\IAWebDados"
if (-not (Test-Path $d)) { throw "Nao achei $d (o IA Web ainda nao foi usado neste PC)." }

function Linhas($nome) {
    $f = "$d\$nome"
    if (Test-Path $f) { Get-Content $f -Encoding UTF8 | ForEach-Object { "$_".Trim() } | Where-Object { $_ } }
}
function Notas($nome) {   # formato do app: ia|e-mail|valor
    foreach ($l in Linhas $nome) {
        $p = $l -split '\|', 3
        if ($p.Count -eq 3 -and $p[2].Trim()) { [pscustomobject]@{ ia = $p[0]; email = $p[1]; valor = $p[2].Trim() } }
    }
}

$agora = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$exp = [ordered]@{
    versao       = 1
    exportado_em = (Get-Date).ToString('s')
    contas       = @(Linhas 'contas.txt' | ForEach-Object { $_.ToLower() } | Where-Object { $_ -match '^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$' } | Select-Object -Unique)
    tags         = @(Notas 'tags.txt')
    fixados      = @(Notas 'fixados.txt')
    limites      = @(Notas 'limites.txt' | Where-Object { $x = 0L; [long]::TryParse($_.valor, [ref]$x) -and $x -gt $agora })   # so os que ainda nao venceram (valor em ms UTC)
    ordem        = (@(Linhas 'ordem.txt') + 'az')[0]
    ias          = @(Linhas 'ias.txt' | ForEach-Object { $p = $_ -split ';', 2; if ($p.Count -eq 2 -and $p[1].Trim() -match '^https?://') { [pscustomobject]@{ nome = $p[0].Trim(); url = $p[1].Trim() } } })
}
if (-not $exp.contas.Count) { throw 'contas.txt vazio ou ausente: nada para exportar.' }

New-Item -ItemType Directory -Force -Path (Split-Path $Saida) | Out-Null   # cria a pasta Backup se nao existir

# UTF-8 sem BOM (parsers JSON do Android reclamam do BOM)
[IO.File]::WriteAllText($Saida, ($exp | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false))

# auto-checagem: le de volta e confere
$v = Get-Content $Saida -Raw -Encoding UTF8 | ConvertFrom-Json
if ($v.versao -ne 1 -or @($v.contas).Count -ne $exp.contas.Count -or @($v.tags).Count -ne $exp.tags.Count) { throw 'O arquivo gerado nao bate com o esperado. Nao use.' }

Write-Host "Pronto: $Saida"
Write-Host "$($exp.contas.Count) contas, $($exp.tags.Count) tags, $($exp.fixados.Count) fixadas, $($exp.limites.Count) limites ativos, $($exp.ias.Count) IAs extras."
Write-Host 'Nao inclui cookies nem logins: no celular voce entra na mao.'
