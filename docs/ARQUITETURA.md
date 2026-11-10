# IA Web: arquitetura, exportador e app Android

## 1. Visão geral

- O IA Web (PC) guarda duas coisas: a **lista de contas** (texto simples, transferível) e o **login** (cookies dentro de um perfil de navegador por conta, **não transferível**).
- O app Android usa **GeckoView** com uma sessão isolada por e-mail (`contextId`). O WebView foi descartado porque o Google bloqueia login OAuth nele (`disallowed_useragent`); o GeckoView não se apresenta como WebView, mas isso não garante que o login Google passe, e por isso foi testado (seção 8).
- A lista é exportada do PC em JSON e importada no app. Os logins são refeitos no celular.

Estrutura do repositório:

```
AI_Web.ico  IA_Web.ps1  Instalar.cmd
Backup\        Exportar-IAWeb.cmd  Exportar-IAWeb.ps1
ANDROID\iaweb-gecko\   projeto Gradle (app, build-iaweb.ps1, Compilar.cmd)
docs\          esta documentação
```

## 2. Como o PC guarda as contas

Tudo em `%LOCALAPPDATA%\IAWebDados\`, em duas camadas.

**Camada 1: a lista (texto simples)**

| Arquivo | Conteúdo |
|---|---|
| `contas.txt` | um e-mail por linha; a mesma lista vale para todas as IAs |
| `tags.txt` | `ia\|e-mail\|tag` |
| `fixados.txt` | `ia\|e-mail\|1` (conta fixada no topo) |
| `limites.txt` | `ia\|e-mail\|instante em ms UTC` (quando o limite volta, marcado à mão) |
| `ordem.txt` | `az` ou `recente` |
| `ias.txt` | `Nome;https://endereco` (IAs adicionadas) |
| `navegador.txt` | navegador escolhido (não exportado) |

**Camada 2: o login (não transferível)**

- Fica no perfil do navegador, uma pasta por conta: `IAWebDados\<navegador>\<e-mail com tudo que não é a-z0-9 trocado por _>\`. No Vivaldi não há a subpasta do navegador.
- O perfil é por conta, não por IA: um login Google serve em todas as IAs.
- Os cookies são criptografados pelo navegador. No Chrome 127+ a chave é presa ao app e à máquina e não funciona se o perfil for movido para outro computador ([Google Security Blog](https://security.googleblog.com/2024/07/improving-security-of-chrome-cookies-on.html)).
- O indicador "logada / não logada" do cartão vem de uma mini-extensão que grava dentro do perfil. Carrega só em Vivaldi, Opera e Opera GX (Chrome, Edge e Firefox não aceitam `--load-extension`, conforme o comentário do próprio script).
- Apagar a pasta do perfil apaga o login daquela conta naquele navegador.

IDs de IA usados em `ia|...`: `claude`, `chatgpt`, `gemini`, `deepseek`, `notebooklm`, `perplexity`, mais as personalizadas (nome em minúsculas, só `a-z0-9`).

## 3. O exportador

`Backup\Exportar-IAWeb.cmd` só **lê** `IAWebDados` e grava `ia-web-export.json` na própria pasta `Backup` (outro destino: `-Saida "caminho\arquivo.json"`).

- **Vai:** contas, tags, fixados, limites ainda ativos, ordem, IAs extras.
- **Não vai:** cookies, perfis, senhas, `ultimo-acesso-*.txt`, `navegador.txt`.

Formato (versão 1, UTF-8 sem BOM, valores ilustrativos):

```json
{
  "versao": 1,
  "exportado_em": "2026-11-09T21:00:00",
  "contas": ["a@exemplo.com"],
  "tags":    [{ "ia": "claude", "email": "a@exemplo.com", "valor": "trabalho" }],
  "fixados": [{ "ia": "claude", "email": "a@exemplo.com", "valor": "1" }],
  "limites": [{ "ia": "claude", "email": "a@exemplo.com", "valor": "1788999999999" }],
  "ordem": "az",
  "ias": [{ "nome": "MinhaIA", "url": "https://minhaia.com/" }]
}
```

O arquivo contém e-mails (dado pessoal) e não deve ser versionado. O script faz uma autochecagem ao final e para com erro se `contas.txt` estiver vazio.

## 4. Decisões técnicas do Android

| Tema | Achado |
|---|---|
| Isolar contas no WebView | Há múltiplos perfis desde `androidx.webkit` 1.9.0, cada um com cookies, storage e service workers próprios ([release notes](https://developer.android.com/jetpack/androidx/releases/webkit), [API Profile](https://developer.android.com/reference/kotlin/androidx/webkit/Profile)). Exige checar `MULTI_PROFILE` em runtime. |
| Login Google no WebView | Bloqueado pelo Google desde 30/09/2021 (`disallowed_useragent`). Atinge Gemini, NotebookLM e botões "Entrar com Google". |
| GeckoView `contextId` | `GeckoSessionSettings.Builder.contextId` separa cookies e localStorage entre sessões; só sessões com o mesmo ID compartilham dados, e eles persistem por contexto. `StorageController.clearDataForSessionContext` apaga um contexto. O código compila na versão 159; o comportamento foi observado no teste (seção 8). |
| GeckoView e login Google | Não há declaração oficial de que seja permitido ou bloqueado. Só o teste decide. |
| Firefox Android | Sem containers em 2026, segundo o fórum da Mozilla. O WebLibre (Gecko) tem containers, em alfa. |
| Instalar APK | Desde 30/09/2026, apps de desenvolvedor não verificado não instalam pelo fluxo normal em aparelhos certificados no Brasil; a instalação por **ADB** continua possível, e por isso é o caminho usado. |

### Transferência de logins

- **Cookies não são transferidos.** A criptografia é presa à máquina, o formato difere no Android, e copiar cookies entre aparelhos é o que ladrões de sessão fazem (o Google detecta). O login é feito uma vez por conta.
- **A parte cosmética é transferida** pelo `ia-web-export.json`: o app cria um perfil vazio por e-mail, marcado "não logada".
- Regras de importação: nome do perfil = e-mail com `[^a-z0-9]` trocado por `_`; cartões agrupados pelo texto antes do `@`; `limites` vencidos ignorados; `ordem = recente` começa sem histórico; IAs padrão mais as de `ias`; `versao` desconhecida é recusada; importar de novo não duplica contas.

## 5. Build do app

| Item | Valor |
|---|---|
| GeckoView | 159.0.20261102144711 (gravada em `apk\VERSAO-GECKO.txt`) |
| Android Gradle plugin | 9.1.1 |
| Gradle | 9.3.1 |
| JDK | 17 |
| `compileSdk` / `targetSdk` / `minSdk` | 37 / 34 / 26 |
| ABI | só `arm64-v8a` |
| APK de debug | cerca de 98,5 MB |

O `build-iaweb.ps1` localiza o JDK 17 e o Android SDK, grava o `local.properties`, descobre a versão do GeckoView e chama o `gradlew`. Com `-Instalar`, instala por ADB.

### Problemas conhecidos de build

| Sintoma | Causa | Solução |
|---|---|---|
| `JDK 17 nao encontrado` | só há outra versão do Java | instalar um JDK 17 (por exemplo `winget install EclipseAdoptium.Temurin.17.JDK`) ou apontar `JAVA_HOME` |
| `Android SDK nao encontrado` | SDK ausente | instalar as ferramentas de linha de comando em `%LOCALAPPDATA%\Android\Sdk` |
| `checkDebugAarMetadata FAILED` | GeckoView 159 e AndroidX atual exigem `compileSdk` 37 e AGP 9.1+ | usar AGP 9.1.1, Gradle 9.3.1 e `compileSdk` 37 |
| `adb`: nenhum aparelho autorizado | Depuração USB desligada ou chave RSA não aceita | ligar a depuração, usar cabo em modo Transferência de arquivos e aceitar o pedido no celular |
| Login Google termina em tela branca | o popup do Google devolve o resultado à página que o abriu; carregá-lo na mesma aba destruía essa página | abrir o popup em sessão separada, ligada à de origem, e fechá-la em `onCloseRequest` |

O build é reproduzível com `-GeckoVersion`; uma versão futura do GeckoView pode exigir outro AGP ou `compileSdk`.

## 6. Funcionamento do app

- **Cartões:** contas com o mesmo texto antes do `@` formam um cartão; com mais de um domínio, o toque pergunta qual abrir.
- **Ordem:** alterna entre `A-Z` e `recentes`; fixados vêm primeiro. O último acesso é gravado só no app.
- **Limites:** o toque longo oferece "Marcar limite..." (1, 3, 5, 12 ou 24 horas) e "Limpar limite". O cartão mostra quando o limite volta; limites vencidos somem. Ao abrir uma conta com limite, o app avisa e abre mesmo assim.
- **Limite na web e próxima conta livre:** botão **Limite** na barra da web e botão **Próxima livre** na lista (abre a conta sem limite que está há mais tempo sem uso). Durações sugeridas: Claude 5 h, Perplexity 24 h (estimativas de fontes secundárias, sem confirmação das empresas).
- **Remover conta:** apaga também tag, fixado, limite e acesso dela.
- **Log:** guarda as últimas 400 linhas no aparelho, com valores de parâmetros de URL mascarados.
- **Tema:** claro/escuro pelo sistema, com um único acento.

## 7. Assinatura e reinstalação

O APK de debug usa o `debug.keystore` do usuário. Assinatura diferente obriga a desinstalar, e desinstalar apaga os logins. Mantenha uma cópia do keystore e um único ambiente de build.

## 8. Resultados de teste (10/11/2026, Moto G85, contas Gmail)

| Critério | Resultado | Observação |
|---|---|---|
| Contas isoladas | Passou (Claude: 3 contas; ChatGPT: 2) | cada conta nova abriu em `/login` mesmo com outra já logada |
| Persistência ao fechar e reabrir o app | Passou | as contas abriram sem passar por `/login`; "Forçar parada" não foi distinguido no log |
| Sem verificação infinita | Passou, com ressalva | no ChatGPT houve cerca de 20 s de redirecionamentos antes de entrar |
| Login com Google | Passou | Claude por popup (fecha sozinho); ChatGPT por redirecionamento; nenhum `disallowed_useragent` |
| Importação do JSON | Passou | 18 contas importadas |
| Login por e-mail (código/senha) | Não testado | |
| Apagar login sem afetar outra conta | Não testado | |
| Gemini, DeepSeek, Perplexity, NotebookLM | Não testado | |
| Limite na web, Próxima livre, durações sugeridas | Implementado, ainda não testado | |

Notas:

- No ChatGPT, a conta que já tinha sessão do Claude reaproveitou a mesma sessão (login por conta, não por IA), como no PC.
- `FIM ok=false` no log aparece também em logins bem-sucedidos: é o carregamento interrompido pela navegação seguinte, não um erro.
- O resultado vale para Claude e ChatGPT com Google; não se generaliza para as outras IAs.

## 9. Riscos e alternativas

Riscos, do mais provável ao menos:

1. Login Google em outras IAs (cada uma com fluxo e anti-bot próprios).
2. Login por popup em sites com outros fluxos.
3. Anti-bot (Cloudflare e similares), não testado.
4. Quebra de build quando o GeckoView ou o AGP mudarem.
5. Perda de login por reinstalação com assinatura diferente.
6. Memória com muitas contas (limite de 3 sessões vivas).
7. Sem status "logada" automático nem % de uso (exigiria WebExtension, viabilidade não avaliada).

Alternativas, caso o Gecko falhe no Google: clones por perfil do Android (Private Space, perfil de trabalho), apps oficiais com troca de conta, controle remoto do PC, ou WebLibre.

## 10. Roteiro

- Seletor de contas dentro da web, com selo "atual".
- Lembrar a última IA; busca e filtro por tag.
- "Desfazer" ao remover; menu de toque longo em bottom sheet.
- Status "logada" inferido pela URL ou por WebExtension.
- Tema manual e acessibilidade (leitor de tela, fonte grande).
- Limite com horário absoluto e atualização por minuto.
