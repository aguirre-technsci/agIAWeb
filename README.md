# IA Web

Janela única para várias contas de IA (Claude, ChatGPT, Gemini, DeepSeek, Perplexity, NotebookLM). Cada conta tem o próprio perfil isolado, então dá para manter duas contas do mesmo serviço logadas ao mesmo tempo.

| Parte | Pasta | O que é |
|---|---|---|
| **PC (Windows)** | raiz | `IA_Web.ps1`: lista de contas, atalho no Menu Iniciar, um perfil de navegador por conta |
| **Android** | `ANDROID/iaweb-gecko` | App em GeckoView (motor do Firefox), uma sessão isolada por e-mail |

O app Android ainda é um protótipo; os limites estão listados abaixo.

## PC

1. Execute `Instalar.cmd`. Ele copia o programa para `%LOCALAPPDATA%\IAWeb` e cria o atalho **IA Web** no Menu Iniciar.
2. Para atualizar, execute de novo: contas e logins são preservados.

Contas e logins ficam em `%LOCALAPPDATA%\IAWebDados\`, fora deste repositório.

### Exportar contas para o celular

`Backup\Exportar-IAWeb.cmd` gera `Backup\ia-web-export.json` com a **lista** de contas, tags, fixados, limites e ordem. Cookies, senhas e perfis não são exportados: o login do PC não é transferível, então cada conta é logada de novo no celular.

O JSON contém e-mails e está no `.gitignore`. Não o publique.

## Android

Requisitos:

- JDK 17 (`JAVA_HOME` ou instalação padrão)
- Android SDK com a plataforma `android-37` (padrão: `%LOCALAPPDATA%\Android\Sdk`, ou `ANDROID_HOME`)
- Celular com Depuração USB, para instalar por cabo

```powershell
cd ANDROID\iaweb-gecko
.\build-iaweb.ps1              # gera apk\iaweb-gecko.apk
.\build-iaweb.ps1 -Instalar    # gera e instala por ADB
```

Detalhes de build, instalação e testes: [`ANDROID/iaweb-gecko/README.md`](ANDROID/iaweb-gecko/README.md).

### Limitações

- A depuração remota do GeckoView fica ligada apenas em build de debug (inspeção por USB).
- Popups e `target=_blank` abrem em sessão própria ligada à página de origem; outros fluxos de login por popup podem se comportar de forma diferente.
- Sem indicador automático de "logada" nem % de uso no Android (exigiria uma WebExtension).
- No máximo 3 sessões vivas ao mesmo tempo; as mais antigas fecham (os cookies persistem e a página recarrega).
- Login com Google testado em Claude e ChatGPT, em um aparelho (Moto G85). Gemini, DeepSeek, Perplexity e NotebookLM não foram testados.

## Documentação

[`docs/ARQUITETURA.md`](docs/ARQUITETURA.md): como o PC guarda as contas, formato do JSON, decisões do app Android, build e resultados de teste.

## Privacidade

Nada é enviado a servidor do projeto. Os logins ficam nos perfis locais (PC) e no armazenamento do app (Android, com `allowBackup=false`). Os sites das IAs veem o acesso como o de qualquer navegador.

## Aviso

Projeto independente, sem vínculo com Anthropic, OpenAI, Google, Perplexity, DeepSeek ou Mozilla. Os nomes pertencem aos respectivos donos. Use conforme os termos de cada serviço.

## Licença

[MIT](LICENSE). O GeckoView é distribuído pela Mozilla sob licença própria (MPL 2.0).
