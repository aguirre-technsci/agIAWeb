# IA Web (Android, GeckoView)

App que abre cada conta de IA em uma `GeckoSession` isolada por `contextId` (uma por e-mail), de modo que contas diferentes, inclusive do Google, ficam logadas ao mesmo tempo.

## Compilar e instalar

Requisitos: JDK 17, Android SDK com `platforms;android-37`, e Depuração USB ligada no celular (Configurações > Sobre o telefone > toque 7 vezes em "Número da versão" > Opções do desenvolvedor).

```powershell
.\build-iaweb.ps1                          # gera apk\iaweb-gecko.apk
.\build-iaweb.ps1 -Instalar                # gera e instala por ADB
.\build-iaweb.ps1 -GeckoVersion <versao>   # fixa a versão do GeckoView
```

Ou execute `Compilar.cmd` (aceita os mesmos argumentos).

O script procura a versão mais recente do GeckoView em `maven.mozilla.org` e grava em `apk\VERSAO-GECKO.txt`. Use `-GeckoVersion` com esse valor para repetir um build.

Versões usadas: Android Gradle plugin 9.1.1, Gradle 9.3.1, `compileSdk` 37, `targetSdk` 34, `minSdk` 26, só `arm64-v8a`. Compile fora de pastas sincronizadas (OneDrive) e sem `!` no caminho.

**Assinatura:** o APK de debug usa o `debug.keystore` da pasta `.android` do usuário. Uma assinatura diferente exige desinstalar o app, e desinstalar apaga os logins. Mantenha uma cópia desse arquivo e use sempre o mesmo ambiente de build.

## Usar

1. Copie `ia-web-export.json` (gerado no PC) para o celular e importe no app, ou adicione contas com **Nova conta**.
2. Abra cada conta e faça login. O login fica no contexto daquela conta.
3. **Log** (na lista e na tela da conta) mostra, copia e compartilha o registro de navegação, com os parâmetros de URL mascarados.

## Roteiro de teste

1. Duas contas da mesma IA logadas ao mesmo tempo continuam distintas.
2. Repetir com outra IA.
3. Login por e-mail (código ou senha) e por "Entrar com Google".
4. Fechar o app pelos recentes e abrir de novo: continua logado. Repetir após "Forçar parada".
5. As páginas carregam sem verificação anti-bot infinita.
6. Pressionar e segurar uma conta > "Apagar login": ela volta a pedir login e as outras não são afetadas.
7. Importar o mesmo JSON duas vezes não duplica contas.

## Limites conhecidos

Veja a seção "Limitações" do [README principal](../../README.md) e [`docs/ARQUITETURA.md`](../../docs/ARQUITETURA.md).
