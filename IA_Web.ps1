param([switch]$Atalho, [switch]$Navegador, [switch]$Diagnostico)  # -Atalho: cria o atalho "IA Web" no Menu Iniciar | -Navegador: pergunta o navegador de novo | -Diagnostico: grava em diagnostico.txt o que a extensao guardou de cada conta

if ($Atalho) {
    # o atalho fica na mesma pasta do script se ela estiver no Menu Iniciar; senao, na raiz de Programas
    $prog = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
    $l = Join-Path $(if ($PSScriptRoot -like "$prog*") { $PSScriptRoot } else { $prog }) 'IA Web.lnk'
    Remove-Item (Join-Path (Split-Path $l) 'Claude Web.lnk') -ErrorAction SilentlyContinue   # atalho da versao so-Claude
    $s = (New-Object -ComObject WScript.Shell).CreateShortcut($l)
    # lancador sem janela: o wscript roda o PowerShell com a janela oculta desde o nascimento (estilo 0)
    $vbs = [IO.Path]::ChangeExtension($PSCommandPath, '.vbs')
    Set-Content $vbs -Encoding ASCII -Value @'
CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & Left(WScript.ScriptFullName, Len(WScript.ScriptFullName) - 4) & ".ps1""", 0, False
'@
    $s.TargetPath   = 'wscript.exe'
    $s.Arguments    = "`"$vbs`""
    $s.Description  = 'IA Web'
    $s.IconLocation = Join-Path $PSScriptRoot 'AI_Web.ico'   # o .ico fica ao lado do script
    $s.Save()
    # grava a identidade (AppUserModelID) dentro do .lnk, para a barra de tarefas juntar atalho e janela
    Add-Type @'
using System; using System.Runtime.InteropServices; using System.Runtime.InteropServices.ComTypes;
public static class Aumid {
  [ComImport, Guid("00021401-0000-0000-C000-000000000046")] class ShellLink {}
  [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IPropertyStore {
    int GetCount(out uint c); int GetAt(uint i, out PropKey k);
    int GetValue(ref PropKey k, out PropVar v); int SetValue(ref PropKey k, ref PropVar v); int Commit();
  }
  [StructLayout(LayoutKind.Sequential, Pack = 4)] struct PropKey { public Guid fmtid; public uint pid; }
  [StructLayout(LayoutKind.Explicit, Size = 24)] struct PropVar { [FieldOffset(0)] public ushort vt; [FieldOffset(8)] public IntPtr p; }
  public static void Lnk(string path, string id) {
    var link = new ShellLink();
    ((IPersistFile)link).Load(path, 2);
    var ps = (IPropertyStore)link;
    var k = new PropKey { fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), pid = 5 };
    var v = new PropVar { vt = 31, p = Marshal.StringToCoTaskMemUni(id) };
    ps.SetValue(ref k, ref v); ps.Commit();
    ((IPersistFile)link).Save(path, true);
  }
}
'@
    [Aumid]::Lnk($l, 'Aguirre.IAWeb')
    (New-Object -ComObject WScript.Shell).Popup("Atalho criado em:`n$l", 0, 'IA Web') | Out-Null
    return
}

# esconde a janela preta do PowerShell (so a janela de escolha fica visivel)
Add-Type -Name W -Namespace N -MemberDefinition '[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow(); [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c); [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); [DllImport("shell32.dll")] public static extern int SetCurrentProcessExplicitAppUserModelID([MarshalAs(UnmanagedType.LPWStr)] string id);'
[void][N.W]::ShowWindow([N.W]::GetConsoleWindow(), 0)
[void][N.W]::SetProcessDPIAware()  # sem isso o Windows estica a janela e ela fica borrada
[void][N.W]::SetCurrentProcessExplicitAppUserModelID('Aguirre.IAWeb')  # mesma identidade do atalho: a janela agrupa no icone fixado da barra de tarefas
$ErrorActionPreference = 'Stop'   # qualquer erro vira aviso na tela (o PowerShell roda oculto)
trap { (New-Object -ComObject WScript.Shell).Popup(($_ | Out-String), 0, 'IA Web - erro') | Out-Null; exit 1 }
# -Diagnostico: relatorio do que a extensao guardou em cada conta (login l: 1 logada, 0 sem login, -1 nao decidiu). Grava diagnostico.txt e abre no Bloco de Notas
if ($Diagnostico) {
    $agora = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $rel = foreach ($p in Get-ChildItem "$env:LOCALAPPDATA\IAWebDados" -Recurse -Directory -Filter 'Local Extension Settings' -Depth 4 -ErrorAction SilentlyContinue) {
        "== $($p.Parent.Parent.Name)"
        $ult = @{}
        foreach ($a in Get-ChildItem "$($p.FullName)\*\*" -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.log', '.ldb' }) {
            try { $fs = [IO.File]::Open($a.FullName, 'Open', 'Read', 'ReadWrite, Delete'); $ms = New-Object IO.MemoryStream; $fs.CopyTo($ms); $fs.Close() } catch { continue }
            foreach ($m in [regex]::Matches([Text.Encoding]::GetEncoding(28591).GetString($ms.ToArray()), '\{\\"ts\\":\d+,.*?\}"')) {
                $j = $m.Value.Substring(0, $m.Value.Length - 1).Replace('\"', '"') | ConvertFrom-Json
                $id = if ($j.i) { $j.i } else { 'claude (sem i)' }
                if (-not $ult[$id] -or $j.ts -ge $ult[$id].ts) { $j | Add-Member -NotePropertyName arq -NotePropertyValue $a.Name -Force; $ult[$id] = $j }
            }
        }
        if (-not $ult.Count) { '   nenhum registro legivel (a extensao nao rodou nesta conta, ou o Chrome comprimiu o banco)' }
        foreach ($id in ($ult.Keys | Sort-Object)) { $j = $ult[$id]; '   {0,-14} l={1,-2} visto ha {2} min  ({3})' -f $id, $j.l, [int](($agora - $j.ts) / 60000), $j.arq }
    }
    $f = "$env:LOCALAPPDATA\IAWebDados\diagnostico.txt"
    Set-Content $f (@('IA Web - diagnostico', '') + @($rel)) -Encoding UTF8
    Start-Process notepad $f
    return
}

# uma janela de escolha por vez: um segundo duplo clique (ou o .ps1 junto com o atalho) sai em silencio
$trava = New-Object Threading.Mutex($false, 'Local\Aguirre.IAWeb')
try { $livre = $trava.WaitOne(0) } catch [Threading.AbandonedMutexException] { $livre = $true }
if (-not $livre) { return }

# ---------------------------------------------------------------------------
# IAs: cada uma tem URL, arquivo de contas e o que a mini-extensao le na pagina.
# Ico = icone da janela de contas dessa IA (<Nome>_Web.ico, ao lado do script; se faltar, usa o AI_Web.ico).
# Uso = $true: o site informa % de uso (so o Claude). Nas outras nao ha %; o limite estourado e marcado a mao na lista de contas (tecla L).
# Login = funcao JS que muda L: 1 logada, 0 sem login (senao deixa como esta e a pagina decide por geral(): botoes de entrar). ck(url) devolve os nomes dos cookies da url.
# Extra = enderecos adicionais em que o mesmo site pode cair (a extensao tambem roda neles). Ex.: NotebookLM, que mudou para notebook.google.com mas ainda redireciona algumas contas para notebooklm.google.com.
# Login depende dos cookies/HTML atuais de cada site: se parar de funcionar, e aqui que se ajusta.
# ---------------------------------------------------------------------------
$servicos = @(
    @{ Id = 'claude';  Nome = 'Claude';  Url = 'https://claude.ai/';        Uso = $true;  Ico = 'Claude_Web.ico' }
    @{ Id = 'chatgpt'; Nome = 'ChatGPT'; Url = 'https://chatgpt.com/';      Uso = $false; Ico = 'ChatGPT_Web.ico'
       Login = 'async () => { const c = await ck("https://chatgpt.com/"); if (c.some(n => /session-token/.test(n))) { L = 1; return; } try { const j = await (await fetch("/api/auth/session")).json(); L = j && j.user ? 1 : 0; } catch (e) {} }' }
    @{ Id = 'gemini';  Nome = 'Gemini';  Url = 'https://gemini.google.com/';Uso = $false; Ico = 'Gemini_Web.ico'
       Login = 'async () => { const c = await ck("https://accounts.google.com/"); if (c.some(n => /^(__Secure-[13]P)?SID$/.test(n))) L = 1; else if (c.length) L = 0; }' }
    @{ Id = 'deepseek'; Nome = 'DeepSeek'; Url = 'https://chat.deepseek.com/';Uso = $false; Ico = 'DeepSeek_Web.ico'
       Login = '() => { try { L = localStorage.getItem("userToken") ? 1 : 0; } catch (e) {} }' }
    @{ Id = 'notebooklm'; Nome = 'NotebookLM'; Url = 'https://notebook.google.com/'; Extra = @('https://notebooklm.google.com/'); Uso = $false; Ico = 'NotebookLM_Web.ico'
       Login = 'async () => { const c = await ck("https://accounts.google.com/"); if (c.some(n => /^(__Secure-[13]P)?SID$/.test(n))) L = 1; else if (c.length) L = 0; }' }
    @{ Id = 'perplexity'; Nome = 'Perplexity'; Url = 'https://www.perplexity.ai/'; Uso = $false; Ico = 'Perplexity_Web.ico'
       Login = '() => {}' }
)
# IA adicionada pelo usuario: abre em modo app com perfil por conta e e-mail no titulo, como as outras (sem leitura de login/limite)
function NovoServico($nome, $url) {
    $u = [Uri]$url
    @{ Id = ($nome.ToLower() -replace '[^a-z0-9]', ''); Nome = $nome; Url = "$($u.Scheme)://$($u.Host)/"; Uso = $false; Custom = $true
       Ico = ($nome -replace '[^\w-]', '') + '_Web.ico'; Login = '() => {}' }
}
$iasTxt = "$env:LOCALAPPDATA\IAWebDados\ias.txt"   # uma por linha: Nome;endereco
if (Test-Path $iasTxt) {
    foreach ($linha in Get-Content $iasTxt) {
        $p = $linha -split ';', 2
        if ($p.Count -eq 2 -and $p[0].Trim() -and $p[1].Trim() -match '^https?://') {
            $n = NovoServico $p[0].Trim() $p[1].Trim()
            if ($n.Id -and -not ($servicos | Where-Object { $_.Id -eq $n.Id })) { $servicos += $n }
        }
    }
}
$servicos = @($servicos | Sort-Object { $_.Nome })   # ordem alfabetica

# Cada item da lista: Linhas (texto do botao), Exe, Args
# (o perfil e da conta e vale para todas as IAs: IAWebDados\<navegador>\<conta>, assim o login do Google/e-mail serve em qualquer uma. Perfis de navegadores diferentes nao se misturam)
function NovoItem($m) {
    $dir = "$env:LOCALAPPDATA\IAWebDados\" + $(if ($nav.Id -ne 'vivaldi') { $nav.Id + '\' }) + ($m -replace '[^a-z0-9]', '_')
    $a = if ($nav.Id -eq 'firefox') { "-no-remote -profile `"$dir`" $($svc.Url)" }
         else { "--user-data-dir=`"$dir`" --no-first-run --disable-features=FedCm --app=$($svc.Url)" }   # FedCm desligado: o aviso "Entrar com o Google" (ex.: Perplexity) derruba o navegador de contas Google logadas
    [pscustomobject]@{ Linhas = @($m); Exe = $nav.Exe; Args = $a; Dir = $dir }
}

# ---------------------------------------------------------------------------
# JANELA DE ESCOLHA: duas colunas, lista unica. Setas navegam, Enter abre, Esc fecha.
# ---------------------------------------------------------------------------
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
# cartao desenhado a mao: usuario em destaque, dominio apagado, uso (%) com barra, anel de foco visivel, sem flicker
# no PowerShell 7 (.NET) os tipos ficam em varios DLLs (Component, Color...): referencia tudo que ja esta carregado
$null = [Windows.Forms.Control], [ComponentModel.Component], [Drawing.Color], [Drawing.Graphics], [Drawing.Drawing2D.GraphicsPath], [Windows.Forms.TextRenderer]
$pat = '^System\.(Windows|Drawing|ComponentModel|Private\.Windows)'
$carregados = { [AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.Location -and $_.GetName().Name -match $pat } }
foreach ($volta in 1..3) {   # carrega tambem as dependencias (System.Private.Windows.Core etc.)
    foreach ($asm in @(& $carregados)) {
        foreach ($n in $asm.GetReferencedAssemblies()) { if ($n.Name -match $pat) { try { [void][Reflection.Assembly]::Load($n) } catch {} } }
    }
}
$refs = @(& $carregados | ForEach-Object Location)
Add-Type -ReferencedAssemblies $refs -TypeDefinition @'
using System; using System.Drawing; using System.Drawing.Drawing2D; using System.Windows.Forms;
public class Cartao : Control {
  public Color Fundo, FundoSobre, Anel, Mudo, CorInfo, CorBarra, CorLogin, CorTag; public bool Ponto;
  public string Usuario, Dominio, Info, Direita; public float Escala = 1, Pct = -1; public bool Tracejado; bool sobre, transborda; int tick; System.Windows.Forms.Timer tm;
  public Cartao() {
    SetStyle(ControlStyles.Selectable | ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
    TabStop = true; Cursor = Cursors.Hand; AccessibleRole = AccessibleRole.PushButton;
  }
  protected override bool IsInputKey(Keys k) { return k == Keys.Up || k == Keys.Down || k == Keys.Left || k == Keys.Right || base.IsInputKey(k); }
  protected override void OnKeyDown(KeyEventArgs e) { base.OnKeyDown(e); if (e.KeyCode == Keys.Enter || e.KeyCode == Keys.Space) { e.Handled = true; OnClick(EventArgs.Empty); } }
  protected override void OnMouseEnter(EventArgs e) { sobre = true; Anima(); Invalidate(); base.OnMouseEnter(e); }
  protected override void OnMouseLeave(EventArgs e) { sobre = false; Anima(); Invalidate(); base.OnMouseLeave(e); }
  protected override void OnGotFocus(EventArgs e) { Anima(); Invalidate(); base.OnGotFocus(e); }
  protected override void OnLostFocus(EventArgs e) { Anima(); Invalidate(); base.OnLostFocus(e); }
  protected override void Dispose(bool d) { if (d && tm != null) tm.Dispose(); base.Dispose(d); }
  // o relogio so anda com o cartao em foco ou sob o mouse (e so repinta se algum texto nao couber)
  void Anima() {
    if (sobre || Focused) {
      if (tm == null) { tm = new System.Windows.Forms.Timer(); tm.Interval = 33; tm.Tick += delegate { tick++; if (transborda) Invalidate(); }; }
      if (!tm.Enabled) { tick = 0; tm.Start(); }
    } else if (tm != null) { tm.Stop(); tick = 0; }
  }
  // desenha ate dois trechos seguidos (a, b) dentro de r. Se nao couberem: com o cartao em foco ou sob o mouse o texto rola em loop (pausa, anda, pausa, volta ao inicio); senao termina em reticencias
  void Rola(Graphics g, string a, Font fa, Color ca, string b, Font fb, Color cb, Rectangle r, TextFormatFlags f) {
    a = a ?? ""; b = b ?? "";
    Size big = new Size(int.MaxValue, int.MaxValue);
    int aw = a.Length == 0 ? 0 : TextRenderer.MeasureText(g, a, fa, big, f).Width;
    int bw = b.Length == 0 ? 0 : TextRenderer.MeasureText(g, b, fb, big, f).Width;
    int over = aw + bw - r.Width;
    if (over > 0) transborda = true;
    if (over > 0 && r.Width > 0 && (sobre || Focused)) {
      float v = 1.5f * Escala; int pausa = 25, mov = (int)Math.Ceiling(over / v), t = tick % (2 * pausa + mov);
      int off = Math.Min(t < pausa ? 0 : t < pausa + mov ? (int)((t - pausa) * v) : over, over);
      // o TextRenderer ignora o recorte do Graphics: o texto e desenhado numa imagem do tamanho de r e so ela vai para o cartao
      Color fundo = sobre || Focused ? FundoSobre : Fundo;
      using (Bitmap bm = new Bitmap(r.Width, r.Height))
      using (Graphics bg = Graphics.FromImage(bm)) {
        bg.Clear(fundo);
        TextRenderer.DrawText(bg, a, fa, new Rectangle(-off, 0, aw + 8, r.Height), ca, fundo, f);
        if (bw > 0) TextRenderer.DrawText(bg, b, fb, new Rectangle(aw - off, 0, bw + 8, r.Height), cb, fundo, f);
        g.DrawImage(bm, r, 0, 0, r.Width, r.Height, GraphicsUnit.Pixel);
      }
    } else {
      int la = Math.Min(aw, r.Width);
      TextRenderer.DrawText(g, a, fa, r, ca, f | TextFormatFlags.EndEllipsis);
      if (bw > 0 && r.Width > la) TextRenderer.DrawText(g, b, fb, new Rectangle(r.X + la, r.Y, r.Width - la, r.Height), cb, f | TextFormatFlags.EndEllipsis);
    }
  }
  protected override void OnPaint(PaintEventArgs e) {
    Graphics g = e.Graphics; g.Clear(Parent.BackColor); g.SmoothingMode = SmoothingMode.AntiAlias;
    float w = (Focused ? 2f : 1f) * Escala, r = 10 * Escala;
    RectangleF rc = new RectangleF(w / 2, w / 2, Width - w, Height - w);
    using (GraphicsPath p = new GraphicsPath()) {
      p.AddArc(rc.X, rc.Y, r, r, 180, 90); p.AddArc(rc.Right - r, rc.Y, r, r, 270, 90);
      p.AddArc(rc.Right - r, rc.Bottom - r, r, r, 0, 90); p.AddArc(rc.X, rc.Bottom - r, r, r, 90, 90); p.CloseFigure();
      using (Brush b = new SolidBrush(sobre || Focused ? FundoSobre : Fundo)) g.FillPath(b, p);
      using (Pen pen = new Pen(Focused ? Anel : Color.FromArgb(63, 63, 70), w)) { if (Tracejado && !Focused) pen.DashStyle = DashStyle.Dash; g.DrawPath(pen, p); }
    }
    if (Ponto) { float d = 10 * Escala; using (Brush pb = new SolidBrush(CorLogin)) g.FillEllipse(pb, 16 * Escala, (Height - d) / 2, d, d); }
    TextFormatFlags f = TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix | TextFormatFlags.SingleLine | TextFormatFlags.VerticalCenter | TextFormatFlags.Left;
    int x = (int)((Ponto ? 34 : 16) * Escala);
    int rw = 0;   // espaco reservado ao "aberta ha ...": o e-mail termina antes dele (com reticencias) em vez de passar por cima
    if (!string.IsNullOrEmpty(Direita)) using (Font fd = new Font("Segoe UI", Font.Size - 1f)) rw = TextRenderer.MeasureText(g, Direita, fd, new Size(int.MaxValue, int.MaxValue), f).Width + (int)(24 * Escala);
    Rectangle tr = new Rectangle(x, (int)(6 * Escala), Math.Max(0, Width - x - rw), (int)(24 * Escala));
    transborda = false;
    // a tag fica ao lado do nome; se nao couber inteira ali (o "aberta ha ..." ocupa a direita), desce para a segunda linha, onde ha mais largura, em vez de virar "Financei..."
    string tag1 = Dominio, tag2 = "";
    using (Font fb = new Font("Segoe UI Semibold", Font.Size)) {
      Size grande = new Size(int.MaxValue, int.MaxValue);
      int wu = TextRenderer.MeasureText(g, Usuario ?? "", fb, grande, f).Width;
      int wt = string.IsNullOrEmpty(Dominio) ? 0 : TextRenderer.MeasureText(g, Dominio, Font, grande, f).Width;
      if (wt > 0 && wu + wt > tr.Width) { tag2 = Dominio; tag1 = ""; }
      Rola(g, Usuario, fb, ForeColor, tag1, Font, CorTag.IsEmpty ? Mudo : CorTag, tr, f);
    }
    if (!string.IsNullOrEmpty(Direita)) {
      Rectangle rr = new Rectangle(x, (int)(6 * Escala), Width - x - (int)(16 * Escala), (int)(24 * Escala));
      using (Font fd = new Font("Segoe UI", Font.Size - 1f)) TextRenderer.DrawText(g, Direita, fd, rr, Mudo, (f & ~TextFormatFlags.Left) | TextFormatFlags.Right);
    }
    Rectangle ti = new Rectangle(x, (int)(29 * Escala), Width - 2 * x, (int)(16 * Escala));
    using (Font fs = new Font("Segoe UI", Font.Size - 1f)) Rola(g, Info, fs, CorInfo, tag2, fs, CorTag.IsEmpty ? Mudo : CorTag, ti, f);
    if (Pct >= 0) {
      float bw = Width - 2 * x, by = Height - 10 * Escala, bh = 3 * Escala;
      using (Brush t = new SolidBrush(Color.FromArgb(82, 82, 91))) g.FillRectangle(t, x, by, bw, bh);
      using (Brush v = new SolidBrush(CorBarra)) g.FillRectangle(v, x, by, bw * Math.Min(Pct, 100f) / 100f, bh);
    }
  }
}
public static class Dwm {
  [System.Runtime.InteropServices.DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int a, ref int v, int s);
}
'@
$cor = { param($h) [Drawing.ColorTranslator]::FromHtml($h) }
$k   = [Drawing.Graphics]::FromHwnd([IntPtr]::Zero).DpiX / 96  # escala da tela (125%, 150%...)
$px  = { param($n) [int]($n * $k) }
$mudo = & $cor '#b4b4bd'   # >= 5:1 mesmo sobre o cartao em hover/foco (minimo 4.5:1)
$ico = Join-Path $PSScriptRoot 'AI_Web.ico'   # icone padrao (atalho e janelas)
$reEmail = '^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$'

# acabamento das janelas: barra de titulo escura (Windows 10 1809 ou mais novo; antes disso o Windows ignora), botoes e textos clicaveis que reagem ao mouse
function NovaJanela($props) {
    $w = New-Object Windows.Forms.Form -Property $props
    $w.Add_HandleCreated({ try { $v = 1; if ([Dwm]::DwmSetWindowAttribute($this.Handle, 20, [ref]$v, 4) -ne 0) { [void][Dwm]::DwmSetWindowAttribute($this.Handle, 19, [ref]$v, 4) } } catch { } })
    $w
}
function EstiloBotao($ok, $cancela) {
    $ok.FlatAppearance.MouseOverBackColor = & $cor '#e4e4e7'; $ok.FlatAppearance.MouseDownBackColor = & $cor '#d4d4d8'
    $cancela.FlatAppearance.MouseOverBackColor = & $cor '#3f3f46'; $cancela.FlatAppearance.MouseDownBackColor = & $cor '#52525b'
}
function LinkHover($l) {   # texto clicavel: sublinhado ao passar o mouse, e papel de botao para leitores de tela
    $l.Tag = @{ N = $l.Font; S = (New-Object Drawing.Font($l.Font, [Drawing.FontStyle]::Underline)) }
    $l.AccessibleRole = 'PushButton'
    $l.Add_MouseEnter({ $this.Font = $this.Tag.S }); $l.Add_MouseLeave({ $this.Font = $this.Tag.N })
}

# ---------------------------------------------------------------------------
# NAVEGADOR: fica salvo em navegador.txt. Na 1a vez (ou com -Navegador) pergunta: os instalados no local padrao + "Outro..." para apontar o .exe de qualquer pasta.
# Quem ja usava a versao so-Vivaldi (existe IAWebDados\_titulo) continua no Vivaldi sem ser perguntado.
# Chrome, Edge e Firefox abrem sem a mini-extensao (o Chrome oficial removeu --load-extension na versao 142, o Edge e tratado igual por seguranca; Firefox nao tem essa flag).
# ---------------------------------------------------------------------------
# Migracao de versoes antigas: traz o que existe em ClaudeApp para IAWebDados (move; se nao der, copia so o que falta) e junta os arquivos de contas de cada IA em contas.txt
# Tudo em try/catch: se falhar (ou se outra janela ja estiver migrando), segue em frente sem avisar.
try {
    $velho = "$env:LOCALAPPDATA\ClaudeApp"; $novo = "$env:LOCALAPPDATA\IAWebDados"
    if (Test-Path $velho) {
        try { if (-not (Test-Path $novo)) { Move-Item $velho $novo -ErrorAction Stop } } catch { }
        if (Test-Path $velho) {   # arquivo em uso ou pasta nova ja existente: copia sem sobrescrever e so apaga a antiga se tudo foi copiado
            robocopy $velho $novo /E /XC /XN /XO /R:0 /W:0 /NFL /NDL /NJH /NJS /NP | Out-Null
            if ($LASTEXITCODE -lt 8) { Remove-Item $velho -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
    # as contas agora sao as mesmas para todas as IAs: junta os arquivos antigos (um por IA) em contas.txt
    $antigos = 'extras', 'claude', 'chatgpt', 'gemini', 'deepseek' | ForEach-Object { "$novo\contas-$_.txt" } | Where-Object { Test-Path $_ }
    if ($antigos) {
        $todas = @($antigos | ForEach-Object { Get-Content $_ -ErrorAction SilentlyContinue }) + @(if (Test-Path "$novo\contas.txt") { Get-Content "$novo\contas.txt" })
        $todas = @($todas | ForEach-Object { "$_".Trim().ToLower() } | Where-Object { $_ } | Select-Object -Unique)
        if ($todas.Count) { Set-Content "$novo\contas.txt" $todas -Encoding UTF8 }
        $antigos | Remove-Item -Force -ErrorAction SilentlyContinue
    }
} catch { }
$cfg = "$env:LOCALAPPDATA\IAWebDados\navegador.txt"
$pf = $env:ProgramFiles; $pf86 = ${env:ProgramFiles(x86)}; $la = $env:LOCALAPPDATA
$navs = @(@(
    @{ Id = 'chrome';  Nome = 'Google Chrome'
       Exe = "$pf\Google\Chrome\Application\chrome.exe", "$pf86\Google\Chrome\Application\chrome.exe", "$la\Google\Chrome\Application\chrome.exe" }
    @{ Id = 'edge';    Nome = 'Microsoft Edge'
       Exe = "$pf86\Microsoft\Edge\Application\msedge.exe", "$pf\Microsoft\Edge\Application\msedge.exe" }
    @{ Id = 'vivaldi'; Nome = 'Vivaldi'; Perfil = "$la\Vivaldi\User Data"
       Exe = "$la\Vivaldi\Application\vivaldi_proxy.exe", "$pf\Vivaldi\Application\vivaldi_proxy.exe" }
    @{ Id = 'opera';   Nome = 'Opera'; Perfil = "$env:APPDATA\Opera Software\Opera Stable"
       Exe = "$la\Programs\Opera\opera.exe", "$la\Programs\Opera\launcher.exe", "$pf\Opera\opera.exe", "$pf\Opera\launcher.exe" }
    @{ Id = 'operagx'; Nome = 'Opera GX'; Perfil = "$env:APPDATA\Opera Software\Opera GX Stable"
       Exe = "$la\Programs\Opera GX\opera.exe", "$la\Programs\Opera GX\launcher.exe", "$pf\Opera GX\opera.exe", "$pf\Opera GX\launcher.exe" }
    @{ Id = 'firefox'; Nome = 'Firefox'
       Exe = "$pf\Mozilla Firefox\firefox.exe", "$pf86\Mozilla Firefox\firefox.exe" }
) | ForEach-Object { $_.Exe = @($_.Exe | Where-Object { Test-Path $_ })[0]; $_ } | Where-Object { $_.Exe })   # so os instalados

function NavDe($exe) {   # navegador fora do local padrao: o Id decide a pasta de dados e como abrir
    $id = if ($exe -match 'firefox') { 'firefox' } elseif ($exe -match 'vivaldi') { 'vivaldi' } elseif ($exe -match 'msedge\.exe$') { 'edge' }
          else { 'custom_' + ([IO.Path]::GetFileNameWithoutExtension($exe).ToLower() -replace '[^a-z0-9]', '') }   # uma pasta de perfil por navegador
    @{ Id = $id; Nome = [IO.Path]::GetFileNameWithoutExtension($exe); Exe = $exe; Custom = $true }
}
$nav = $null
if (-not $Navegador) {
    $id = if (Test-Path $cfg) { "$(Get-Content $cfg -Raw)".Trim() } elseif (Test-Path "$la\IAWebDados\_titulo") { 'vivaldi' }
    $nav = $navs | Where-Object { $_.Id -eq $id } | Select-Object -First 1
    if (-not $nav -and $id -and (Test-Path $id)) { $nav = NavDe $id }   # salvo como caminho do .exe
}
# dialogo pequeno: pede nome e endereco da IA, valida e devolve o servico novo (ou $null se cancelar)
function PedirIA($dono) {
    $d = NovaJanela @{
        Text = 'Adicionar IA'; StartPosition = 'CenterParent'; FormBorderStyle = 'FixedDialog'; ShowInTaskbar = $false
        MaximizeBox = $false; MinimizeBox = $false; BackColor = (& $cor '#18181b'); ForeColor = 'White'
        Font = (New-Object Drawing.Font('Segoe UI', 10)); ClientSize = (New-Object Drawing.Size((& $px 440), (& $px 250)))
    }
    $pt = { param($x, $y) New-Object Drawing.Point((& $px $x), (& $px $y)) }
    $rot = { param($t, $y) New-Object Windows.Forms.Label -Property @{ Text = $t; AutoSize = $true; Location = (& $pt 24 $y); Font = (New-Object Drawing.Font('Segoe UI Semibold', 11)) } }
    $caixa = { param($y) New-Object Windows.Forms.TextBox -Property @{ Location = (& $pt 24 $y); Width = (& $px 392); BackColor = (& $cor '#27272a'); ForeColor = 'White'
        BorderStyle = 'FixedSingle'; Font = (New-Object Drawing.Font('Segoe UI', 11)) } }
    $tn = & $caixa 48; $tu = & $caixa 120
    $erro = New-Object Windows.Forms.Label -Property @{ Text = ''; AutoSize = $true; Location = (& $pt 24 160); ForeColor = (& $cor '#fca5a5') }
    $ok = New-Object Windows.Forms.Button -Property @{
        Text = 'Adicionar'; Location = (& $pt 216 198); Size = (New-Object Drawing.Size((& $px 200), (& $px 38)))
        FlatStyle = 'Flat'; BackColor = (& $cor '#fafafa'); ForeColor = (& $cor '#18181b'); Cursor = 'Hand'
    }
    $cancela = New-Object Windows.Forms.Button -Property @{
        Text = 'Cancelar'; Location = (& $pt 24 198); Size = (New-Object Drawing.Size((& $px 120), (& $px 38)))
        FlatStyle = 'Flat'; BackColor = (& $cor '#27272a'); ForeColor = 'White'; Cursor = 'Hand'; DialogResult = 'Cancel'
    }
    $ok.FlatAppearance.BorderSize = 0; $cancela.FlatAppearance.BorderColor = (& $cor '#3f3f46'); EstiloBotao $ok $cancela
    $ok.Add_Click({
        $n = $tn.Text.Trim(); $u = $tu.Text.Trim()
        if ($u -and $u -notmatch '^https?://') { $u = 'https://' + $u }
        if ($n -notmatch '^[^;]{1,30}$' -or $n -replace '[^A-Za-z0-9]' -eq '') { $erro.Text = 'Digite o nome da IA (até 30 letras).'; $tn.Focus(); return }
        if ($u -notmatch '^https?://[^\s/]+\.[^\s/]+') { $erro.Text = 'Digite um endereço válido, como chat.exemplo.com'; $tu.Focus(); return }
        $novo = NovoServico $n $u
        if ($servicos | Where-Object { $_.Id -eq $novo.Id }) { $erro.Text = 'Essa IA já está na lista.'; $tn.Focus(); return }
        $d.Tag = $novo; $d.Close()
    })
    $d.AcceptButton = $ok; $d.CancelButton = $cancela
    $d.Controls.AddRange(@((& $rot 'Nome da IA' 20), $tn, (& $rot 'Endereço do site' 92), $tu, $erro, $ok, $cancela))
    $d.Add_Shown({ $tn.Focus() })
    [void]$d.ShowDialog($dono)
    return $d.Tag
}

# Fluxo em laco: navegador -> IA -> conta. Backspace (ou o link no canto) volta uma etapa: conta -> IA -> navegador.
$navAnt = $null
$reabrindo = $false
while ($true) {   # laco externo: escolher -> abrir a conta -> esperar fechar -> escolher de novo, no mesmo processo (sem iniciar outro PowerShell nem compilar o cartao de novo)
if ($reabrindo) { $livre = $false; try { $livre = $trava.WaitOne(0) } catch [Threading.AbandonedMutexException] { $livre = $true }; if (-not $livre) { return } }   # ja ha outra escolha aberta: esta sai em silencio
$reabrindo = $true
while ($true) {
$sel = $null; $script:volta = $false; $script:trocaNav = $false
if (-not $nav) {
    $lista = @($navs) + @{ Outro = $true }
    $d = NovaJanela @{
        Text = 'IA Web'; StartPosition = 'CenterScreen'; FormBorderStyle = 'FixedDialog'
        MaximizeBox = $false; MinimizeBox = $false; KeyPreview = $true
        BackColor = (& $cor '#18181b'); ForeColor = 'White'; Font = (New-Object Drawing.Font('Segoe UI', 10))
        ClientSize = (New-Object Drawing.Size((& $px 408), (& $px (68 + $lista.Count * 62 + 24))))
    }
    $d.Add_KeyDown({ if ($_.KeyCode -eq 'Escape') { $d.Close() } })
    $d.Controls.Add((New-Object Windows.Forms.Label -Property @{ Text = 'Qual navegador usar?'; AutoSize = $true; ForeColor = 'White'
        Font = (New-Object Drawing.Font('Segoe UI Semibold', 15)); Location = (New-Object Drawing.Point((& $px 24), (& $px 20))) }))
    $primeiro = $null
    for ($i = 0; $i -lt $lista.Count; $i++) {
        $t = $lista[$i]; $b = New-Object Cartao
        $b.Escala = [single]$k; $b.Dominio = ''
        if ($t.Outro) { $b.Usuario = 'Outro...'; $b.Tracejado = $true; $b.Info = 'procurar o .exe do navegador em qualquer pasta' }
        else {
            $b.Usuario = $t.Nome
            $b.Info = if ($t.Id -eq 'firefox') { 'janela normal, sem e-mail no título e sem uso' } elseif ($t.Id -in 'chrome', 'edge') { 'modo app, sem e-mail no título e sem uso' } else { 'modo app, e-mail no título, login e uso/limite' }
        }
        $b.AccessibleName = $b.Usuario
        $b.CorInfo = $mudo; $b.Pct = -1; $b.Fundo = & $cor '#27272a'; $b.FundoSobre = & $cor '#3f3f46'; $b.Anel = & $cor '#fafafa'; $b.Mudo = $mudo
        $b.Location = New-Object Drawing.Point((& $px 24), (& $px (68 + $i * 62)))
        $b.Size = New-Object Drawing.Size((& $px 360), (& $px 56))
        $b.Tag = $t
        $b.Add_KeyDown({ $e = $_; if ("$($e.KeyCode)" -in 'Down', 'Up') { $e.Handled = $true; [void]$d.SelectNextControl($this, "$($e.KeyCode)" -eq 'Down', $true, $true, $true) } })
        $b.Add_Click({
            $t = $this.Tag
            if ($t.Outro) {
                $o = New-Object Windows.Forms.OpenFileDialog -Property @{ Title = 'Escolha o .exe do navegador'; Filter = 'Navegador (*.exe)|*.exe' }
                if ($o.ShowDialog($d) -ne 'OK') { return }   # cancelou: continua na lista
                $t = NavDe $o.FileName
            }
            $script:nav = $t; $d.Close()
        })
        $d.Controls.Add($b)
        if (-not $primeiro) { $primeiro = $b }
    }
    $d.Add_Shown({ $d.TopMost = $true; $d.Activate(); $d.TopMost = $false; $primeiro.Focus() })
    [void]$d.ShowDialog()
}
if (-not $nav -and $navAnt) { $nav = $navAnt }   # veio de "trocar navegador" e fechou sem escolher: segue com o anterior
if (-not $nav) { return }   # fechou sem escolher
New-Item -ItemType Directory -Force (Split-Path $cfg) | Out-Null
Set-Content $cfg $(if ($nav.Custom) { $nav.Exe } else { $nav.Id }) -Encoding UTF8

# ---------------------------------------------------------------------------
# IA: ChatGPT, Claude, DeepSeek, Gemini ou as que voce adicionar. A lista de contas e os perfis sao os mesmos para todas.
# ---------------------------------------------------------------------------
$comExt = $nav.Id -notin 'firefox', 'chrome', 'edge'   # so os Chromium que ainda aceitam --load-extension carregam a mini-extensao
$d = NovaJanela @{
    Text = 'IA Web'; StartPosition = 'CenterScreen'; FormBorderStyle = 'FixedDialog'
    MaximizeBox = $false; MinimizeBox = $false; KeyPreview = $true
    BackColor = (& $cor '#18181b'); ForeColor = 'White'; Font = (New-Object Drawing.Font('Segoe UI', 10))
    ClientSize = (New-Object Drawing.Size((& $px 408), (& $px (68 + ($servicos.Count + 1) * 62 + 44))))
}
if (Test-Path $ico) { $d.Icon = New-Object Drawing.Icon($ico) }
$d.Add_KeyDown({ if ($_.KeyCode -eq 'Escape') { $d.Close() } elseif ($_.KeyCode -eq 'Back') { $script:trocaNav = $true; $d.Close() } })
$d.Controls.Add((New-Object Windows.Forms.Label -Property @{ Text = 'Qual IA?'; AutoSize = $true; ForeColor = 'White'
    Font = (New-Object Drawing.Font('Segoe UI Semibold', 15)); Location = (New-Object Drawing.Point((& $px 24), (& $px 20))) }))
$d.Controls.Add((New-Object Windows.Forms.Label -Property @{ Text = 'Backspace   trocar navegador        Esc   fechar'; AutoSize = $true; ForeColor = $mudo
    Font = (New-Object Drawing.Font('Segoe UI', 9)); Location = (New-Object Drawing.Point((& $px 24), (& $px (68 + ($servicos.Count + 1) * 62 + 8)))) }))
$lnk = New-Object Windows.Forms.Label -Property @{ Text = [string][char]0x2190 + ' Navegador'; AutoSize = $true; ForeColor = 'White'; Cursor = 'Hand'; Font = (New-Object Drawing.Font('Segoe UI', 10)) }; LinkHover $lnk
$lnk.Location = New-Object Drawing.Point(($d.ClientSize.Width - $lnk.PreferredWidth - (& $px 24)), (& $px 28))
$lnk.Add_Click({ $script:trocaNav = $true; $d.Close() })
$d.Controls.Add($lnk)
$primeiro = $null; $foco = $null
for ($i = 0; $i -le $servicos.Count; $i++) {   # a ultima posicao e o "+ Adicionar IA"
    $b = New-Object Cartao
    $b.Escala = [single]$k; $b.Dominio = ''
    if ($i -eq $servicos.Count) {
        $s = @{ NovaIA = $true }; $b.Usuario = '+ Adicionar IA'; $b.Tracejado = $true; $b.Info = 'cadastrar outro site de IA e abrir agora'
    } else {
        $s = $servicos[$i]; $b.Usuario = $s.Nome
        $b.Info = if (-not $comExt) { 'sem extensão neste navegador · tag, limite manual, última abertura' } elseif ($s.Custom) { 'e-mail no título, tag, limite manual' } elseif ($s.Uso) { 'uso (%), login, e-mail no título, tag, limite manual' } else { 'login, e-mail no título, tag, limite manual' }
    }
    $b.AccessibleName = $b.Usuario
    $b.CorInfo = $mudo; $b.Pct = -1; $b.Fundo = & $cor '#27272a'; $b.FundoSobre = & $cor '#3f3f46'; $b.Anel = & $cor '#fafafa'; $b.Mudo = $mudo
    $b.Location = New-Object Drawing.Point((& $px 24), (& $px (68 + $i * 62)))
    $b.Size = New-Object Drawing.Size((& $px 360), (& $px 56))
    $b.Tag = $s
    $b.Add_KeyDown({ $e = $_; if ("$($e.KeyCode)" -in 'Down', 'Up') { $e.Handled = $true; [void]$d.SelectNextControl($this, "$($e.KeyCode)" -eq 'Down', $true, $true, $true) } })
    $b.Add_Click({
        $t = $this.Tag
        if ($t.NovaIA) {
            $t = PedirIA $d
            if (-not $t) { return }   # cancelou: continua na lista
            Set-Content $iasTxt (@(Get-Content $iasTxt -ErrorAction SilentlyContinue | Where-Object { "$_".Trim() }) + "$($t.Nome);$($t.Url)") -Encoding UTF8
            $script:servicos = @(($servicos + $t) | Sort-Object { $_.Nome })
        }
        $script:ultimaIA = $t.Id; $d.Tag = $t; $d.Close()
    })
    $d.Controls.Add($b)
    if (-not $primeiro) { $primeiro = $b }
    if ($s.Id -and $s.Id -eq $script:ultimaIA) { $foco = $b }   # ao voltar, o foco fica na IA que estava escolhida
}
$d.Add_Shown({ $d.TopMost = $true; $d.Activate(); $d.TopMost = $false; $(if ($foco) { $foco } else { $primeiro }).Focus() })
[void]$d.ShowDialog()
$svc = $d.Tag
if ($script:trocaNav) { $navAnt = $nav; $nav = $null; continue }   # voltar: escolher outro navegador
if (-not $svc) { return }   # fechou sem escolher

# contas da IA escolhida ficam num arquivo de texto (um e-mail por linha); o botao "+ Adicionar conta" escreve nele
$contas = @()   # se quiser, pode listar e-mails fixos aqui (valem para qualquer IA)
$extras = "$env:LOCALAPPDATA\IAWebDados\contas.txt"   # a mesma lista de contas para todas as IAs
if (Test-Path $extras) { $contas = @($contas) + @(Get-Content $extras | ForEach-Object { "$_".Trim().ToLower() } | Where-Object { $_ -match $reEmail }) }   # linhas que nao sao e-mail sao ignoradas
$contas = @($contas | Select-Object -Unique)
# tag (contexto rapido) e limite (quando os tokens voltam, marcado a mao) por conta e IA: tags.txt e limites.txt, uma linha por registro no formato ia|e-mail|valor
function LeNotas($arq) {
    $h = @{}
    if (Test-Path $arq) { foreach ($l in Get-Content $arq -Encoding UTF8) { $p = "$l" -split '\|', 3; if ($p.Count -eq 3 -and $p[2].Trim()) { $h["$($p[0])|$($p[1])"] = $p[2].Trim() } } }
    $h
}
function GravaNotas($arq, $h) {
    $l = @($h.GetEnumerator() | Sort-Object Key | ForEach-Object { "$($_.Key)|$($_.Value)" })
    try { if ($l) { Set-Content $arq $l -Encoding UTF8 } else { Remove-Item $arq -ErrorAction SilentlyContinue } } catch { }
}
$tagsTxt = "$env:LOCALAPPDATA\IAWebDados\tags.txt"; $limitesTxt = "$env:LOCALAPPDATA\IAWebDados\limites.txt"
$tags = LeNotas $tagsTxt; $limites = LeNotas $limitesTxt
$fixadosTxt = "$env:LOCALAPPDATA\IAWebDados\fixados.txt"; $fixados = LeNotas $fixadosTxt   # contas fixadas no topo, por IA (ia|e-mail|1)
function FixadaG($g) { @($g.Membros | Where-Object { $fixados["$($svc.Id)|$($_.Linhas[0])"] }).Count -gt 0 }
$estrela = [string][char]0x2605 + ' '
# a lista mostra so o que vem antes do @. E-mails com o mesmo nome e dominios diferentes viram um cartao so (Membros), e ao escolher ele pergunta qual abrir
$itens = @($contas | ForEach-Object { NovoItem $_ } | Group-Object { $_.Linhas[0].Split('@')[0] } |
    ForEach-Object { [pscustomobject]@{ Linhas = @($_.Name); Membros = @($_.Group) } })

# ordem da lista: 'az' (alfabetica pelo e-mail) ou 'recente' (aberta por ultimo primeiro; as nunca abertas ficam no fim, em ordem alfabetica). A ultima escolha fica em ordem.txt
$ordemTxt = "$env:LOCALAPPDATA\IAWebDados\ordem.txt"
$ordem = if ((Test-Path $ordemTxt) -and "$(Get-Content $ordemTxt -Raw)".Trim() -eq 'recente') { 'recente' } else { 'az' }
function Ultimo($dir) { try { [long](Get-Content "$dir\ultimo-acesso-$($svc.Id).txt" -Raw -ErrorAction Stop).Trim() } catch { 0 } }
function UltimoG($g) { ($g.Membros | ForEach-Object { Ultimo $_.Dir } | Measure-Object -Maximum).Maximum }   # abertura mais recente entre os e-mails do grupo
function Distribui {   # ordena os itens e reparte nas duas colunas (ordem de leitura: esquerda, direita, esquerda, direita...)
    $c = @($script:itens | Where-Object { -not $_.Novo })
    $pin = @{ Expression = { if (FixadaG $_) { 0 } else { 1 } } }   # fixadas sempre no topo, depois a ordem escolhida
    $c = if ($script:ordem -eq 'recente') { @($c | Sort-Object $pin, @{ Expression = { UltimoG $_ }; Descending = $true }, @{ Expression = { $_.Linhas[0] } }) }
         else { @($c | Sort-Object $pin, @{ Expression = { $_.Linhas[0] } }) }
    $script:itens = @($c) + @($script:itens | Where-Object { $_.Novo })   # "+ Adicionar conta" sempre por ultimo
    $idx = 0..($script:itens.Count - 1)
    $script:colunas = @(
        , @($idx | Where-Object { $_ % 2 -eq 0 } | ForEach-Object { $script:itens[$_] })
        , @($idx | Where-Object { $_ % 2 -eq 1 } | ForEach-Object { $script:itens[$_] })
    )
}
$itens = @($itens) + [pscustomobject]@{ Novo = $true; Linhas = @('+ Adicionar conta') }
Distribui
$linhasMax = ($colunas | ForEach-Object { $_.Count } | Measure-Object -Maximum).Maximum
$larg = 360; $alt = 56; $gap = 6; $m = 24; $y0 = 68

# uso/login guardado pela extensao de cada conta: % da sessao/semana e horario de reset
$dias = 'dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb'
$ago  = { param($ms)
    $m = [int](([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - [long]$ms) / 60000)
    if ($m -lt 1) { 'agora' } elseif ($m -lt 60) { "há $m min" } elseif ($m -lt 1440) { "há $([int][Math]::Floor($m / 60)) h" } else {
        $d = [int][Math]::Floor($m / 1440)   # depois de 24 h: ontem, há N dias, meses, anos
        if ($d -eq 1) { 'ontem' } elseif ($d -lt 30) { "há $d dias" }
        elseif ($d -lt 365) { $n = [int][Math]::Floor($d / 30); "há $n " + $(if ($n -eq 1) { 'mês' } else { 'meses' }) }
        else { $n = [int][Math]::Floor($d / 365); "há $n " + $(if ($n -eq 1) { 'ano' } else { 'anos' }) }
    }
}
$hm = { param($r)   # horario de reset: so a hora se for hoje, senao com o dia da semana
    $h = $r.ToString('HH:mm', [Globalization.CultureInfo]::InvariantCulture)
    if ($r.Date -eq (Get-Date).Date) { $h } else { "$($dias[[int]$r.DayOfWeek]) $h" }
}
function Aberta($dir) {   # ultima vez que a conta foi aberta por aqui (gravado em ultimo-acesso.txt, dentro do perfil)
    $t = Ultimo $dir; if ($t) { 'aberta ' + (& $ago $t) } else { '' }
}
function TagDe($email) { $v = $tags["$($svc.Id)|$email"]; if ($v) { "  · $v" } else { '' } }   # tag da conta nesta IA, para aparecer apagada ao lado do nome
function LimiteDe($email) {   # instante (ms) em que o limite marcado a mao volta; 0 = sem limite marcado ou ja passou
    $n = 0L; $v = $limites["$($svc.Id)|$email"]
    if ($v -and [long]::TryParse("$v", [ref]$n) -and $n -gt [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) { $n } else { 0 }
}
function ParseVolta($s) {   # "15:45" (a proxima vez que der essa hora) ou duracao: "2h", "45min", "1d", "1d 2h 30min". Devolve o instante em ms (UTC), ou 0 se nao entendeu
    $s = "$s".Trim().ToLower(); $agora = Get-Date
    if ($s -match '^(\d{1,2}):(\d{2})$') {
        if ([int]$Matches[1] -gt 23 -or [int]$Matches[2] -gt 59) { return 0 }
        $r = $agora.Date.AddHours([int]$Matches[1]).AddMinutes([int]$Matches[2]); if ($r -le $agora) { $r = $r.AddDays(1) }
    } elseif ($s -and $s -match '^(?:(\d{1,3})\s*d)?\s*(?:(\d{1,3})\s*h)?\s*(?:(\d{1,3})\s*m(?:in)?)?$') {
        $r = $agora.AddDays([int]$Matches[1]).AddHours([int]$Matches[2]).AddMinutes([int]$Matches[3])
        if ($r -le $agora) { return 0 }
    } else { return 0 }
    ([DateTimeOffset]$r).ToUnixTimeMilliseconds()
}
function Uso($dir) {
    $vazio = @{ Texto = 'sem dados ainda'; Pct = -1; Cor = $mudo; Logado = -1 }
    try {
        # a extensao guarda o ultimo resultado no chrome.storage.local do perfil (LevelDB): o texto aparece inteiro nos arquivos, entao e so achar o mais recente
        $t = $null; $tmax = 0
        $arqs = Get-ChildItem "$dir\Default\Local Extension Settings\*\*" -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.log', '.ldb' }
        foreach ($a in $arqs) {
            try {
                $fs = [IO.File]::Open($a.FullName, 'Open', 'Read', 'ReadWrite, Delete'); $ms = New-Object IO.MemoryStream; $fs.CopyTo($ms); $fs.Close()
                $m = @([regex]::Matches([Text.Encoding]::GetEncoding(28591).GetString($ms.ToArray()), '\{\\"ts\\":\d+,.*?\}"') | Where-Object {
                    $de = if ($_.Value -match '\\"i\\":\\"(\w+)\\"') { $Matches[1] } else { 'claude' }; $de -eq $svc.Id })
                foreach ($r in $m) { $n = [long][regex]::Match($r.Value, '\d+').Value; if ($n -ge $tmax) { $tmax = $n; $t = $r.Value } }   # o mais novo (ts) entre todos os arquivos
            } catch { }
        }
        if (-not $t) { return $vazio }
        $j = $t.Substring(0, $t.Length - 1).Replace('\"', '"') | ConvertFrom-Json
        $lg = if ($null -ne $j.l) { [int]$j.l } else { -1 }   # 1 logada, 0 sem login, -1 nao sei (arquivo de versao antiga)
        $vazio.Logado = $lg; $vazio.Ts = $j.ts; if ($lg -eq 0) { $vazio.Texto = 'não logada' } elseif ($lg -eq 1) { $vazio.Texto = 'logada · sem dados de uso' }
        if (-not $svc.Uso) {   # ChatGPT, Gemini, DeepSeek e as adicionadas: sem %. O limite estourado e marcado a mao (tecla L na lista), nao lido da pagina
            if ($lg -eq 0) { return $vazio }
            $vazio.Texto = $(if ($lg -eq 1) { 'logada' } else { 'login não identificado' }) + ' · visto ' + (& $ago $j.ts); return $vazio
        }
        $c = @(@{ N = 'sessão'; B = $j.s }, @{ N = 'semana'; B = $j.w }) | Where-Object { $_.B -and $null -ne $_.B.u } |
            Sort-Object { [double]$_.B.u } -Descending | Select-Object -First 1   # mostra o limite mais apertado
        if (-not $c) { return $vazio }
        $visto = & $ago $j.ts
        $reset = if ($c.B.r) { [DateTimeOffset]::FromUnixTimeMilliseconds([long]$c.B.r).LocalDateTime }
        if ($reset -and $reset -lt (Get-Date)) { return @{ Texto = "$($c.N) resetou · visto $visto"; Pct = -1; Cor = $mudo; Logado = $lg; Ts = $j.ts } }
        $u = [int][Math]::Round([double]$c.B.u)
        $quando = ''
        if ($reset) {
            $quando = ' · reseta ' + (& $hm $reset)
        }
        $tom = if ($u -ge 95) { '#fca5a5' } elseif ($u -ge 80) { '#fbbf24' } else { $null }   # vermelho / ambar; abaixo de 80 fica neutro
        return @{ Texto = "$($c.N) $u%$quando · visto $visto"; Pct = $u; Cor = $(if ($tom) { [Drawing.ColorTranslator]::FromHtml($tom) } else { $mudo }); Logado = $lg; Ts = $j.ts }
    } catch { return $vazio }
}
function Preenche($b, $mem) {   # tag, login, uso/limite e "aberta há" de uma conta (item de NovoItem) no cartao
    $uso = Uso $mem.Dir
    $x = LimiteDe $mem.Linhas[0]   # limite marcado a mao (tecla L): vale por cima do que a extensao leu
    if ($x) { $uso = @{ Texto = 'limite atingido · volta ' + (& $hm ([DateTimeOffset]::FromUnixTimeMilliseconds($x).LocalDateTime)); Pct = 100; Cor = [Drawing.ColorTranslator]::FromHtml('#fca5a5'); Logado = $uso.Logado; Ts = $uso.Ts } }
    $b.Dominio = TagDe $mem.Linhas[0]   # a tag aparece em amarelo logo depois do nome
    $b.CorTag = & $cor '#facc15'
    $b.Direita = Aberta $mem.Dir
    $b.Info = $uso.Texto; $b.Pct = [single]$uso.Pct; $b.CorInfo = $uso.Cor; $b.CorBarra = if ($uso.Pct -ge 80) { $uso.Cor } else { & $cor '#d4d4d8' }
    $lg = if ($uso.Ts -and ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - [long]$uso.Ts) -gt 7 * 86400000) { -1 } else { $uso.Logado }   # dado com mais de 7 dias: cinza (nao sei)
    $b.Ponto = $true; $b.CorLogin = & $cor $(switch ($lg) { 1 { '#4ade80' } 0 { '#f87171' } default { '#71717a' } })
    $b.AccessibleName = "$($mem.Linhas[0]), $(switch ($lg) { 1 { 'logada, ' } 0 { 'sem login, ' } })$($uso.Texto)"
}

$f = NovaJanela @{
    Text = 'IA Web'; StartPosition = 'CenterScreen'; FormBorderStyle = 'FixedDialog'
    MaximizeBox = $false; MinimizeBox = $false; KeyPreview = $true
    BackColor = (& $cor '#18181b'); ForeColor = 'White'
    Font = (New-Object Drawing.Font('Segoe UI', 10))
    ClientSize = (New-Object Drawing.Size((& $px (2 * $m + 2 * $larg + 16)), (& $px ($y0 + $linhasMax * ($alt + $gap) + 66))))
}
$icoIa = Join-Path $PSScriptRoot $svc.Ico   # icone da IA escolhida; se nao existir, o padrao
if (Test-Path $icoIa) { $f.Icon = New-Object Drawing.Icon($icoIa) } elseif (Test-Path $ico) { $f.Icon = New-Object Drawing.Icon($ico) }
$f.Add_KeyDown({ if ($_.KeyCode -eq 'Escape') { $f.Close() } elseif ($_.KeyCode -eq 'Back') { $script:volta = $true; $f.Close() } elseif ($_.KeyCode -eq 'O') { & $trocaOrdem } elseif ($_.KeyCode -eq 'T') { & $editaConta 'tag' } elseif ($_.KeyCode -eq 'L') { & $editaConta 'limite' } elseif ($_.KeyCode -eq 'P') { & $editaConta 'fixar' } elseif ($_.KeyCode -eq 'Delete') { & $editaConta 'apagar' } })
$rotulo = { param($t, $x, $y, $fonte, $c) $f.Controls.Add((New-Object Windows.Forms.Label -Property @{
    Text = $t; AutoSize = $true; ForeColor = $c; Font = $fonte; Location = (New-Object Drawing.Point((& $px $x), (& $px $y))) })) }
& $rotulo "Qual conta do $($svc.Nome)?" $m 20 (New-Object Drawing.Font('Segoe UI Semibold', 15)) 'White'
$lnk = New-Object Windows.Forms.Label -Property @{ Text = [string][char]0x2190 + ' Voltar'; AutoSize = $true; ForeColor = 'White'; Cursor = 'Hand'; Font = (New-Object Drawing.Font('Segoe UI', 10)) }; LinkHover $lnk
$lnk.Location = New-Object Drawing.Point(($f.ClientSize.Width - $lnk.PreferredWidth - (& $px $m)), (& $px 28))
$lnk.Add_Click({ $script:volta = $true; $f.Close() })
$f.Controls.Add($lnk)
$lbOrdem = New-Object Windows.Forms.Label -Property @{ AutoSize = $true; ForeColor = 'White'; Cursor = 'Hand'; Font = (New-Object Drawing.Font('Segoe UI', 10)) }; LinkHover $lbOrdem
$lbOrdem.AccessibleName = 'Trocar a ordem da lista'
$mostraOrdem = {
    $lbOrdem.Text = 'Ordem: ' + $(if ($script:ordem -eq 'recente') { 'recentes' } else { 'A-Z' })
    $lbOrdem.Location = New-Object Drawing.Point(($lnk.Left - $lbOrdem.PreferredWidth - (& $px 24)), (& $px 28))
}
& $mostraOrdem
$f.Controls.Add($lbOrdem)

# dialogo pequeno: pede o e-mail, valida e devolve (ou $null se cancelar)
function PedirEmail($dono) {
    $d = NovaJanela @{
        Text = 'Adicionar conta'; StartPosition = 'CenterParent'; FormBorderStyle = 'FixedDialog'; ShowInTaskbar = $false
        MaximizeBox = $false; MinimizeBox = $false; BackColor = (& $cor '#18181b'); ForeColor = 'White'
        Font = (New-Object Drawing.Font('Segoe UI', 10)); ClientSize = (New-Object Drawing.Size((& $px 440), (& $px 180)))
    }
    $pt = { param($x, $y) New-Object Drawing.Point((& $px $x), (& $px $y)) }
    $d.Controls.Add((New-Object Windows.Forms.Label -Property @{ Text = 'E-mail da nova conta'; AutoSize = $true; Location = (& $pt 24 20); Font = (New-Object Drawing.Font('Segoe UI Semibold', 11)) }))
    $t = New-Object Windows.Forms.TextBox -Property @{
        Location = (& $pt 24 52); Width = (& $px 392); BackColor = (& $cor '#27272a'); ForeColor = 'White'; BorderStyle = 'FixedSingle'
        Font = (New-Object Drawing.Font('Segoe UI', 11))
    }
    $erro = New-Object Windows.Forms.Label -Property @{ Text = ''; AutoSize = $true; Location = (& $pt 24 90); ForeColor = (& $cor '#fca5a5') }
    $ok = New-Object Windows.Forms.Button -Property @{
        Text = 'Adicionar e abrir'; Location = (& $pt 216 128); Size = (New-Object Drawing.Size((& $px 200), (& $px 38)))
        FlatStyle = 'Flat'; BackColor = (& $cor '#fafafa'); ForeColor = (& $cor '#18181b'); Cursor = 'Hand'
    }
    $cancela = New-Object Windows.Forms.Button -Property @{
        Text = 'Cancelar'; Location = (& $pt 24 128); Size = (New-Object Drawing.Size((& $px 120), (& $px 38)))
        FlatStyle = 'Flat'; BackColor = (& $cor '#27272a'); ForeColor = 'White'; Cursor = 'Hand'; DialogResult = 'Cancel'
    }
    $ok.FlatAppearance.BorderSize = 0; $cancela.FlatAppearance.BorderColor = (& $cor '#3f3f46'); EstiloBotao $ok $cancela
    $ok.Add_Click({
        $m = $t.Text.Trim().ToLower()
        if ($m -notmatch $reEmail) { $erro.Text = 'Digite um e-mail válido, como nome@gmail.com'; $t.Focus(); return }
        if ($contas -contains $m) { $erro.Text = 'Essa conta já está na lista.'; $t.Focus(); return }
        $d.Tag = $m; $d.Close()
    })
    $d.AcceptButton = $ok; $d.CancelButton = $cancela
    $d.Controls.AddRange(@($t, $erro, $ok, $cancela))
    $d.Add_Shown({ $t.Focus() })
    [void]$d.ShowDialog($dono)
    return $d.Tag
}

# dialogo pequeno: pede um texto curto (tag, ou quando o limite volta). Devolve o texto (vazio = remover) ou $null se cancelar. $valida recebe o texto e devolve a mensagem de erro (ou nada se estiver certo)
function PedirTexto($dono, $titulo, $rotulo, $dica, $atual, $max, $valida) {
    $d = NovaJanela @{
        Text = $titulo; StartPosition = 'CenterParent'; FormBorderStyle = 'FixedDialog'; ShowInTaskbar = $false
        MaximizeBox = $false; MinimizeBox = $false; BackColor = (& $cor '#18181b'); ForeColor = 'White'
        Font = (New-Object Drawing.Font('Segoe UI', 10)); ClientSize = (New-Object Drawing.Size((& $px 440), (& $px 220)))
    }
    $pt = { param($x, $y) New-Object Drawing.Point((& $px $x), (& $px $y)) }
    $d.Controls.Add((New-Object Windows.Forms.Label -Property @{ Text = $rotulo; AutoSize = $true; MaximumSize = (New-Object Drawing.Size((& $px 392), 0)); Location = (& $pt 24 20); Font = (New-Object Drawing.Font('Segoe UI Semibold', 11)) }))
    $t = New-Object Windows.Forms.TextBox -Property @{
        Location = (& $pt 24 72); Width = (& $px 392); MaxLength = $max; Text = "$atual"; BackColor = (& $cor '#27272a'); ForeColor = 'White'; BorderStyle = 'FixedSingle'
        Font = (New-Object Drawing.Font('Segoe UI', 11))
    }
    $d.Controls.Add((New-Object Windows.Forms.Label -Property @{ Text = $dica; AutoSize = $true; MaximumSize = (New-Object Drawing.Size((& $px 392), 0)); Location = (& $pt 24 108); ForeColor = $mudo; Font = (New-Object Drawing.Font('Segoe UI', 9)) }))
    $erro = New-Object Windows.Forms.Label -Property @{ Text = ''; AutoSize = $true; Location = (& $pt 24 140); ForeColor = (& $cor '#fca5a5') }
    $ok = New-Object Windows.Forms.Button -Property @{
        Text = 'Salvar'; Location = (& $pt 216 168); Size = (New-Object Drawing.Size((& $px 200), (& $px 38)))
        FlatStyle = 'Flat'; BackColor = (& $cor '#fafafa'); ForeColor = (& $cor '#18181b'); Cursor = 'Hand'
    }
    $cancela = New-Object Windows.Forms.Button -Property @{
        Text = 'Cancelar'; Location = (& $pt 24 168); Size = (New-Object Drawing.Size((& $px 120), (& $px 38)))
        FlatStyle = 'Flat'; BackColor = (& $cor '#27272a'); ForeColor = 'White'; Cursor = 'Hand'; DialogResult = 'Cancel'
    }
    $ok.FlatAppearance.BorderSize = 0; $cancela.FlatAppearance.BorderColor = (& $cor '#3f3f46'); EstiloBotao $ok $cancela
    $ok.Add_Click({
        $v = ($t.Text -replace '\s+', ' ').Trim()
        $e = if ($valida) { & $valida $v }
        if ($e) { $erro.Text = $e; $t.Focus(); return }
        $d.Tag = $v; $d.Close()
    })
    $d.AcceptButton = $ok; $d.CancelButton = $cancela
    $d.Controls.AddRange(@($t, $erro, $ok, $cancela))
    $d.Add_Shown({ $t.Focus(); $t.SelectAll() })
    [void]$d.ShowDialog($dono)
    return $d.Tag
}

# varios e-mails com o mesmo nome antes do @: pergunta qual abrir (devolve o item da conta, ou $null se cancelar)
function EscolheEmail($dono, $g) {
    $mem = @($g.Membros | Sort-Object { $_.Linhas[0] })
    $d = NovaJanela @{
        Text = 'Qual e-mail?'; StartPosition = 'CenterParent'; FormBorderStyle = 'FixedDialog'; ShowInTaskbar = $false
        MaximizeBox = $false; MinimizeBox = $false; KeyPreview = $true
        BackColor = (& $cor '#18181b'); ForeColor = 'White'; Font = (New-Object Drawing.Font('Segoe UI', 10))
        ClientSize = (New-Object Drawing.Size((& $px 408), (& $px (68 + $mem.Count * 62 + 24))))
    }
    $d.Add_KeyDown({ if ($_.KeyCode -eq 'Escape') { $d.Close() } })
    $d.Controls.Add((New-Object Windows.Forms.Label -Property @{ Text = "Qual e-mail de $($g.Linhas[0])?"; AutoSize = $true; ForeColor = 'White'
        Font = (New-Object Drawing.Font('Segoe UI Semibold', 15)); Location = (New-Object Drawing.Point((& $px 24), (& $px 20))) }))
    $primeiro = $null
    for ($i = 0; $i -lt $mem.Count; $i++) {
        $b = New-Object Cartao
        $b.Escala = [single]$k; $b.Usuario = $mem[$i].Linhas[0]; $b.Dominio = ''
        Preenche $b $mem[$i]
        $b.Fundo = & $cor '#27272a'; $b.FundoSobre = & $cor '#3f3f46'; $b.Anel = & $cor '#fafafa'; $b.Mudo = $mudo
        $b.Location = New-Object Drawing.Point((& $px 24), (& $px (68 + $i * 62)))
        $b.Size = New-Object Drawing.Size((& $px 360), (& $px 56))
        $b.Tag = $mem[$i]
        $b.Add_KeyDown({ $e = $_; if ("$($e.KeyCode)" -in 'Down', 'Up') { $e.Handled = $true; [void]$d.SelectNextControl($this, "$($e.KeyCode)" -eq 'Down', $true, $true, $true) } })
        $b.Add_Click({ $d.Tag = $this.Tag; $d.Close() })
        $d.Controls.Add($b)
        if (-not $primeiro) { $primeiro = $b }
    }
    $d.Add_Shown({ $primeiro.Focus() })
    [void]$d.ShowDialog($dono)
    return $d.Tag
}

function Aviso($msg) { (New-Object -ComObject WScript.Shell).Popup($msg, 0, 'IA Web') | Out-Null }

# confirmacao de apagar conta: devolve 'lista' (so tira da lista), 'tudo' (tira da lista e apaga o login salvo neste navegador) ou $null (cancelou)
function PedirApagar($dono, $mail, $navNome) {
    $d = NovaJanela @{
        Text = 'Apagar conta'; StartPosition = 'CenterParent'; FormBorderStyle = 'FixedDialog'; ShowInTaskbar = $false
        MaximizeBox = $false; MinimizeBox = $false; BackColor = (& $cor '#18181b'); ForeColor = 'White'
        Font = (New-Object Drawing.Font('Segoe UI', 10)); ClientSize = (New-Object Drawing.Size((& $px 480), (& $px 250)))
    }
    $pt = { param($x, $y) New-Object Drawing.Point((& $px $x), (& $px $y)) }
    $txt = { param($t, $y, $fonte, $c) New-Object Windows.Forms.Label -Property @{ Text = $t; AutoSize = $true; MaximumSize = (New-Object Drawing.Size((& $px 432), 0)); Location = (& $pt 24 $y); Font = $fonte; ForeColor = $c } }
    $t1 = & $txt "Apagar $mail?" 20 (New-Object Drawing.Font('Segoe UI Semibold', 12)) 'White'
    $l1 = & $txt "Só tirar da lista: a conta some de todas as IAs, mas o login continua salvo no $navNome." 60 (New-Object Drawing.Font('Segoe UI', 10)) $mudo
    $l2 = & $txt "Apagar conta e login: também apaga o login e os dados dessa conta no $navNome. Não tem volta." 120 (New-Object Drawing.Font('Segoe UI', 10)) $mudo
    $botao = { param($t, $x, $w, $fundo, $hover, $borda)
        $o = New-Object Windows.Forms.Button -Property @{ Text = $t; Location = (& $pt $x 190); Size = (New-Object Drawing.Size((& $px $w), (& $px 38)))
            FlatStyle = 'Flat'; BackColor = (& $cor $fundo); ForeColor = 'White'; Cursor = 'Hand' }
        $o.FlatAppearance.BorderColor = (& $cor $borda); $o.FlatAppearance.MouseOverBackColor = (& $cor $hover)
        $o
    }
    $cancela = & $botao 'Cancelar' 24 110 '#27272a' '#3f3f46' '#3f3f46'; $cancela.DialogResult = 'Cancel'
    $bLista  = & $botao 'Só tirar da lista' 146 150 '#27272a' '#3f3f46' '#3f3f46'
    $bTudo   = & $botao 'Apagar conta e login' 308 148 '#dc2626' '#b91c1c' '#dc2626'
    $bLista.Add_Click({ $x = $this.FindForm(); $x.Tag = 'lista'; $x.Close() })
    $bTudo.Add_Click({ $x = $this.FindForm(); $x.Tag = 'tudo'; $x.Close() })
    $d.CancelButton = $cancela   # Esc cancela; o foco inicial tambem fica em Cancelar (apagar nunca e o padrao)
    $d.Controls.AddRange(@($t1, $l1, $l2, $cancela, $bLista, $bTudo))
    $d.Add_Shown({ $cancela.Focus() })
    [void]$d.ShowDialog($dono)
    return $d.Tag
}

# T = tag, L = limite: agem na conta em foco (cartao de varios e-mails pergunta qual primeiro). Os dois guardam em arquivo (tags.txt, limites.txt) e atualizam o cartao na hora
$editaConta = {
    param($oque)
    $b = $f.ActiveControl
    if ($b -isnot [Cartao] -or -not $b.Tag.Item -or $b.Tag.Item.Novo) { return }
    $it = $b.Tag.Item
    $it = if ($it.Membros.Count -gt 1) { EscolheEmail $f $it } else { $it.Membros[0] }
    if (-not $it) { $b.Focus(); return }
    $mail = $it.Linhas[0]; $chave = "$($svc.Id)|$mail"
    if ($oque -eq 'tag') {
        $r = PedirTexto $f 'Tag da conta' "Tag de $mail no $($svc.Nome)" 'Um contexto rápido para lembrar da conta. Vazio remove a tag.' $tags[$chave] 60 $null
        if ($null -eq $r) { $b.Focus(); return }
        if ($r) { $tags[$chave] = $r } else { $tags.Remove($chave) }
        GravaNotas $tagsTxt $tags
    } elseif ($oque -eq 'apagar') {
        & $apagaConta $b $it
        return
    } elseif ($oque -eq 'fixar') {
        if ($fixados[$chave]) { $fixados.Remove($chave) } else { $fixados[$chave] = '1' }
        GravaNotas $fixadosTxt $fixados
        $b.Usuario = $(if (FixadaG $b.Tag.Item) { $estrela }) + $b.Tag.Item.Linhas[0]
        & $reposiciona
    } else {
        $x = LimiteDe $mail; $atual = ''
        if ($x) { $v = [DateTimeOffset]::FromUnixTimeMilliseconds($x).LocalDateTime; if ($v.Date -eq (Get-Date).Date) { $atual = $v.ToString('HH:mm', [Globalization.CultureInfo]::InvariantCulture) } }
        $r = PedirTexto $f 'Limite da conta' "Quando voltam os tokens de $mail no $($svc.Nome)?" 'Horário (15:45) ou duração (2h, 45min, 1d). Vazio remove a marca.' $atual 20 { param($v) if ($v -and -not (ParseVolta $v)) { 'Não entendi. Use 15:45, 2h, 45min ou 1d.' } }
        if ($null -eq $r) { $b.Focus(); return }
        if ($r) { $limites[$chave] = [string](ParseVolta $r) } else { $limites.Remove($chave) }
        GravaNotas $limitesTxt $limites
    }
    if ($b.Tag.Item.Membros.Count -eq 1) { Preenche $b $it; $b.Invalidate() }
    $b.Focus()
}

$grade = @{}; $cartoes = @{}
$setas = {
    $ev = $_; $t = $this.Tag; $c = $t.C; $r = $t.R
    switch ("$($ev.KeyCode)") { 'Down' { $r++ } 'Up' { $r-- } 'Right' { $c++ } 'Left' { $c-- } default { return } }
    $ev.Handled = $true
    if ($c -lt 0 -or $c -ge $colunas.Count -or $colunas[$c].Count -eq 0) { return }
    $r = [Math]::Max(0, [Math]::Min($r, $colunas[$c].Count - 1))
    $grade["$c,$r"].Focus()
}
$primeiro = $null
for ($c = 0; $c -lt $colunas.Count; $c++) {
    $x = $m + $c * ($larg + 16)
    for ($r = 0; $r -lt $colunas[$c].Count; $r++) {
        $it = $colunas[$c][$r]; $mail = $it.Linhas[0]
        $b = New-Object Cartao
        $b.Escala = [single]$k
        if ($it.Novo) {
            $b.Usuario = $mail; $b.Dominio = ''; $b.Tracejado = $true
            $b.Info = 'cadastrar outro e-mail e abrir agora'; $b.CorInfo = $mudo; $b.AccessibleName = 'Adicionar conta'
        } else {
            $b.Usuario = $(if (FixadaG $it) { $estrela }) + $mail; $b.Dominio = ''   # so o que vem antes do @; ★ se fixada
            if ($it.Membros.Count -gt 1) {   # mesmo nome, dominios diferentes: um cartao so, a escolha vem ao abrir
                $b.Info = "$($it.Membros.Count) e-mails: " + (($it.Membros | ForEach-Object { ($_.Linhas[0] -split '@')[1] }) -join ', ')
                $b.CorInfo = $mudo; $b.Ponto = $true; $b.CorLogin = & $cor '#71717a'
                $b.Direita = Aberta ($it.Membros | Sort-Object { Ultimo $_.Dir } -Descending | Select-Object -First 1).Dir
                $b.AccessibleName = "$mail, $($it.Membros.Count) e-mails, escolher um"
            } else { Preenche $b $it.Membros[0] }
        }
        $b.Fundo = & $cor '#27272a'; $b.FundoSobre = & $cor '#3f3f46'; $b.Anel = & $cor '#fafafa'; $b.Mudo = $mudo
        $b.Location = New-Object Drawing.Point((& $px $x), (& $px ($y0 + $r * ($alt + $gap))))
        $b.Size = New-Object Drawing.Size((& $px $larg), (& $px $alt))
        $b.Tag = [pscustomobject]@{ Item = $it; C = $c; R = $r }
        $b.Add_KeyDown($setas)
        $b.Add_Click({
            $it = $this.Tag.Item
            if ($it.Novo) {
                $m = PedirEmail $f
                if (-not $m) { return }   # cancelou: continua na lista
                New-Item -ItemType Directory -Force (Split-Path $extras) | Out-Null
                Set-Content $extras (@(Get-Content $extras -ErrorAction SilentlyContinue | Where-Object { "$_".Trim() }) + $m) -Encoding UTF8   # regrava (nao acrescenta: o arquivo pode nao terminar em quebra de linha)
                $it = NovoItem $m
            } elseif ($it.Membros.Count -gt 1) {
                $it = EscolheEmail $f $it
                if (-not $it) { return }   # cancelou: continua na lista
            } else { $it = $it.Membros[0] }
            $script:sel = $it; $f.Close()
        })
        $f.Controls.Add($b)
        $grade["$c,$r"] = $b; $cartoes[$mail] = $b
        if (-not $primeiro) { $primeiro = $b }
    }
}
$dica = "{0} {1} {2} {3}   navegar        Enter   abrir        Backspace   voltar        O   ordem        P   fixar        Esc   fechar" -f [char]0x2191, [char]0x2193, [char]0x2190, [char]0x2192
# troca A-Z <-> recentes: guarda a escolha e so reposiciona os cartoes (sem refazer a janela nem reler o uso)
$trocaOrdem = {
    $script:ordem = if ($script:ordem -eq 'recente') { 'az' } else { 'recente' }
    try { Set-Content $ordemTxt $script:ordem -Encoding ASCII } catch { }
    & $reposiciona
    & $mostraOrdem
}
$reposiciona = {
    Distribui
    $grade.Clear()
    for ($c = 0; $c -lt $colunas.Count; $c++) { for ($r = 0; $r -lt $colunas[$c].Count; $r++) {
        $b = $cartoes[$colunas[$c][$r].Linhas[0]]
        $b.Location = New-Object Drawing.Point((& $px ($m + $c * ($larg + 16))), (& $px ($y0 + $r * ($alt + $gap))))
        $b.Tag.C = $c; $b.Tag.R = $r; $grade["$c,$r"] = $b
    } }
}
# Del = apagar a conta em foco: tira o e-mail de contas.txt (vale para todas as IAs), limpa tag/limite/fixacao dele e, se escolhido, apaga o login salvo (a pasta do perfil) NESTE navegador. Perfis de outros navegadores nao sao tocados
$apagaConta = {
    param($b, $it)
    $mail = $it.Linhas[0]; $g = $b.Tag.Item
    $r = PedirApagar $f $mail $nav.Nome
    if (-not $r) { $b.Focus(); return }   # cancelou
    if ($r -eq 'tudo') {
        $raiz = "$env:LOCALAPPDATA\IAWebDados\"; $dir = "$($it.Dir)"
        if (-not $dir.StartsWith($raiz, [StringComparison]::OrdinalIgnoreCase) -or $dir.Length -le $raiz.Length) { Aviso 'Pasta de login fora do esperado; nada foi apagado.'; $b.Focus(); return }
        $reDir = [regex]::Escape($dir) + '("|\s|$)'
        $aberta = @(Get-CimInstance Win32_Process -Filter "CommandLine like '%IAWebDados%'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match $reDir }).Count -gt 0
        if ($aberta) { Aviso "Essa conta está aberta no $($nav.Nome). Feche a janela dela e tente de novo."; $b.Focus(); return }
        try { if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction Stop } } catch { }
        if (Test-Path -LiteralPath $dir) { Aviso 'Não consegui apagar todo o login (algum arquivo está em uso). A conta continua na lista; feche o navegador dela e tente de novo.'; $b.Focus(); return }
    }
    try {
        if (Test-Path $extras) {
            $resto = @(Get-Content $extras | Where-Object { "$_".Trim() -and "$_".Trim().ToLower() -ne $mail })
            if ($resto.Count) { Set-Content $extras $resto -Encoding UTF8 } else { Remove-Item $extras -ErrorAction SilentlyContinue }
        }
    } catch { Aviso "Não consegui atualizar a lista de contas: $($_.Exception.Message)"; $b.Focus(); return }
    foreach ($h in $tags, $limites, $fixados) { foreach ($kk in @($h.Keys | Where-Object { $_.EndsWith("|$mail") })) { $h.Remove($kk) } }
    GravaNotas $tagsTxt $tags; GravaNotas $limitesTxt $limites; GravaNotas $fixadosTxt $fixados
    $script:contas = @($script:contas | Where-Object { $_ -ne $mail })
    $g.Membros = @($g.Membros | Where-Object { -not [object]::ReferenceEquals($_, $it) })
    if ($g.Membros.Count -gt 1) {   # sobrou mais de um e-mail com esse nome: so atualiza o texto do cartao
        $b.Info = "$($g.Membros.Count) e-mails: " + (($g.Membros | ForEach-Object { ($_.Linhas[0] -split '@')[1] }) -join ', ')
    } elseif ($g.Membros.Count -eq 1) {   # sobrou um: o cartao volta a mostrar login/uso desse e-mail
        Preenche $b $g.Membros[0]
    } else {   # nenhum: tira o cartao da janela e fecha o buraco
        $nome = $g.Linhas[0]
        $f.Controls.Remove($cartoes[$nome]); $cartoes[$nome].Dispose(); $cartoes.Remove($nome)
        $script:itens = @($script:itens | Where-Object { -not [object]::ReferenceEquals($_, $g) })
    }
    & $reposiciona
    $novoMax = ($colunas | ForEach-Object { $_.Count } | Measure-Object -Maximum).Maximum
    if ($novoMax -lt $script:linhasMax) {   # menos linhas: sobe os textos de baixo e encolhe a janela
        $dy = & $px (($script:linhasMax - $novoMax) * ($alt + $gap))
        foreach ($c in @($f.Controls)) { if ($c -isnot [Cartao] -and $c.Top -gt (& $px $y0)) { $c.Top -= $dy } }
        $f.ClientSize = New-Object Drawing.Size -ArgumentList $f.ClientSize.Width, ($f.ClientSize.Height - $dy)
        $script:linhasMax = $novoMax
    }
    $grade["0,0"].Focus()
}
$lbOrdem.Add_Click($trocaOrdem)
# links das teclas T e L: agem na conta selecionada (o clique no texto nao tira o foco do cartao)
$yL = $y0 + $linhasMax * ($alt + $gap) + 4
$lbTag = New-Object Windows.Forms.Label -Property @{ Text = 'T   Tag da conta'; AutoSize = $true; ForeColor = 'White'; Cursor = 'Hand'; Font = (New-Object Drawing.Font('Segoe UI', 10)); Location = (New-Object Drawing.Point((& $px $m), (& $px $yL))) }; LinkHover $lbTag
$lbTag.AccessibleName = 'Adicionar ou editar a tag da conta selecionada'
$lbTag.Add_Click({ & $editaConta 'tag' })
$lbLim = New-Object Windows.Forms.Label -Property @{ Text = 'L   Marcar limite'; AutoSize = $true; ForeColor = 'White'; Cursor = 'Hand'; Font = (New-Object Drawing.Font('Segoe UI', 10)); Location = (New-Object Drawing.Point(($lbTag.Left + $lbTag.PreferredWidth + (& $px 32)), (& $px $yL))) }; LinkHover $lbLim
$lbLim.AccessibleName = 'Marcar quando voltam os tokens da conta selecionada'
$lbLim.Add_Click({ & $editaConta 'limite' })
$lbFix = New-Object Windows.Forms.Label -Property @{ Text = 'P   Fixar no topo'; AutoSize = $true; ForeColor = 'White'; Cursor = 'Hand'; Font = (New-Object Drawing.Font('Segoe UI', 10)); Location = (New-Object Drawing.Point(($lbLim.Left + $lbLim.PreferredWidth + (& $px 32)), (& $px $yL))) }; LinkHover $lbFix
$lbFix.AccessibleName = 'Fixar ou desafixar a conta selecionada no topo da lista'
$lbFix.Add_Click({ & $editaConta 'fixar' })
$lbApa = New-Object Windows.Forms.Label -Property @{ Text = 'Del   Apagar conta'; AutoSize = $true; ForeColor = 'White'; Cursor = 'Hand'; Font = (New-Object Drawing.Font('Segoe UI', 10)); Location = (New-Object Drawing.Point(($lbFix.Left + $lbFix.PreferredWidth + (& $px 32)), (& $px $yL))) }; LinkHover $lbApa
$lbApa.AccessibleName = 'Apagar a conta selecionada'
$lbApa.Add_Click({ & $editaConta 'apagar' })
$f.Controls.AddRange(@($lbTag, $lbLim, $lbFix, $lbApa))
& $rotulo $dica $m ($yL + 30) (New-Object Drawing.Font('Segoe UI', 9)) $mudo
$f.Add_Shown({ $f.TopMost = $true; $f.Activate(); $f.TopMost = $false; $primeiro.Focus() })
[void]$f.ShowDialog()
if ($script:volta) { continue }   # voltar: escolher outra IA
if (-not $sel) { return }
break
}   # fim do laco

# mini-extensao por conta (so Chromium que ainda aceita --load-extension: Vivaldi, Opera, Opera GX...): (1) poe o e-mail na frente do titulo da janela; (2) le login e uso (Claude; nas outras IAs so o login) e guarda no chrome.storage da extensao, dentro do perfil da conta
if ($comExt) { try {
    $email = $sel.Linhas[0]
    $slug = $email -replace '[^a-z0-9]', '_'
    $ext = "$env:LOCALAPPDATA\IAWebDados\_titulo\$slug"   # uma extensao por conta, com as regras de todas as IAs (o perfil e compartilhado)
    New-Item -ItemType Directory -Force $ext | Out-Null
    $regras = foreach ($sv in $servicos) {
        # parte comum a todas as IAs: e-mail na frente do titulo
        $js = @"
const P = "$email - ";
const f = () => { if (!document.title.startsWith(P)) document.title = P + document.title; };
new MutationObserver(f).observe(document.documentElement, { childList: true, subtree: true, characterData: true });
f();
// o Chrome grava o storage em LevelDB com Snappy: registros parecidos viram referencias binarias e o IA_Web.ps1 nao os le mais. O enchimento aleatorio impede a compressao.
const pad = () => Array.from({ length: 50 }, () => Math.random().toString(36).slice(2)).join("");

"@
        # Claude: login + % de uso (sessao de 5 h e semana) pelo endereco interno do claude.ai
        $jsClaude = @'
const salva = m => chrome.storage.local.set({ u_claude: JSON.stringify(Object.assign({}, m, { i: "claude", p: pad() })) });
const b = x => (x && typeof x.utilization === "number") ? { u: x.utilization, r: x.resets_at ? Date.parse(x.resets_at) : null } : null;
const coleta = async () => {
  try {
    const r = await fetch("/api/organizations");
    if (r.status === 401 || r.status === 403) { salva({ ts: Date.now(), l: 0 }); return; }
    const o = await r.json();
    const org = o.find(x => (x.capabilities || []).includes("chat")) || o[0];
    const u = await (await fetch("/api/organizations/" + org.uuid + "/usage")).json();
    const s = b(u.five_hour), w = b(u.seven_day);
    salva({ ts: Date.now(), l: 1, s: s, w: w });
  } catch (e) {}
};
setTimeout(coleta, 1500);
setInterval(coleta, 300000);
'@
        # ChatGPT, Gemini, DeepSeek e as adicionadas: sem %. So guarda o login (L); o limite estourado nao e lido da pagina, e marcado a mao na lista de contas (tecla L)
        $jsOutras = @"
const login = $($sv.Login);
const ck = u => new Promise(ok => { try { chrome.runtime.sendMessage({ u }, r => { void chrome.runtime.lastError; ok(r || []); }); } catch (e) { ok([]); } });
// plano B quando o login do site nao decide: sem botao de entrar na pagina = logada (so com a pagina ja carregada)
const geral = () => {
  const b = document.body;
  if (!b || b.innerText.length < 200) return;
  const re = /^(log ?in|sign ?in|sign ?up|entrar|fazer login|iniciar sess(\u00e3|a)o|criar conta|cadastre-se)(?![\s\S])/i;   // fim do texto sem usar cifrao (o PowerShell expandiria)
  L = [...document.querySelectorAll("a, button")].some(e => re.test((e.innerText || "").trim())) ? 0 : 1;
};
const K = "u_$($sv.Id)";
let L = -1;
const salva = () => chrome.storage.local.set({ [K]: JSON.stringify({ ts: Date.now(), l: L, i: "$($sv.Id)", p: pad() }) });
const roda = async () => { L = -1; try { await login(); } catch (e) {} if (L < 0) geral(); salva(); };
let ult = 0;
const logo = () => { if (Date.now() - ult > 5000) { ult = Date.now(); roda(); } };
setTimeout(roda, 4000); setInterval(roda, 120000);
window.addEventListener("blur", logo);
document.addEventListener("visibilitychange", () => { if (document.hidden) logo(); });
"@
        Set-Content "$ext\t-$($sv.Id).js" -Encoding ASCII -Value ($js + $(if ($sv.Uso) { $jsClaude } else { $jsOutras }))
        '{"matches":[' + ((@($sv.Url) + @($sv.Extra) | Where-Object { $_ } | ForEach-Object { '"' + $_ + '*"' }) -join ',') + '],"js":["t-' + $sv.Id + '.js"],"run_at":"document_start"}'
    }
    # service worker: devolve so os NOMES dos cookies de uma url (cookie HttpOnly da sessao nao aparece para o script da pagina)
    Set-Content "$ext\bg.js" -Encoding ASCII -Value 'chrome.runtime.onMessage.addListener((m, s, r) => { chrome.cookies.getAll({ url: m.u }).then(c => r(c.map(x => x.name)), () => r([])); return true; });'
    $hosts = (@($servicos | ForEach-Object { @($_.Url) + @($_.Extra) } | Where-Object { $_ } | ForEach-Object { '"' + $_ + '*"' }) + '"https://accounts.google.com/*"') -join ','
    Set-Content "$ext\manifest.json" -Encoding ASCII -Value ('{"manifest_version":3,"name":"Conta IA","version":"8","permissions":["storage","cookies"],"host_permissions":[' + $hosts + '],"background":{"service_worker":"bg.js"},"content_scripts":[' + ($regras -join ',') + ']}')
    # extensoes suas (ex.: gerenciador de senhas): IDs em extensoes.txt, carregadas do perfil normal do navegador
    $cargas = @($ext)
    try {
        $lista = "$env:LOCALAPPDATA\IAWebDados\extensoes.txt"
        if ($nav.Perfil -and (Test-Path $lista)) {
            foreach ($id in (Get-Content $lista | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)) {
                $v = foreach ($raiz in "$($nav.Perfil)\Default\Extensions", "$($nav.Perfil)\Extensions") { Get-ChildItem "$raiz\$id" -Directory -ErrorAction SilentlyContinue }
                $v = $v | Sort-Object LastWriteTime -Descending | Select-Object -First 1   # a versao mais recente instalada
                if ($v) { $cargas += $v.FullName }
            }
        }
    } catch { }
    $sel.Args += " --load-extension=`"$($cargas -join ',')`""
} catch { } }   # se falhar, abre a conta mesmo assim, so sem titulo e sem uso
try { New-Item -ItemType Directory -Force $sel.Dir | Out-Null; Set-Content "$($sel.Dir)\ultimo-acesso-$($svc.Id).txt" ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Encoding ASCII } catch { }   # marca a abertura
$lancou = $false; $proc = $null
try { $proc = Start-Process $sel.Exe -ArgumentList $sel.Args -PassThru -ErrorAction Stop; $lancou = $true }
catch { (New-Object -ComObject WScript.Shell).Popup($_.Exception.Message, 0, 'IA Web') | Out-Null }

# reabrir a escolha de contas quando a conta for fechada
if ($lancou) {
    try { $trava.ReleaseMutex() } catch { }   # libera a trava: com a conta aberta, o atalho ainda pode abrir outra escolha
    # o processo iniciado costuma ser o proprio navegador: enquanto vive a conta esta aberta, e quando sai a escolha volta na hora.
    # Se ele sai cedo (navegador ja aberto nessa conta, ou lancador que passa o trabalho adiante), acompanha pela pasta de perfil: espera sumirem os processos que a usam
    $vivo = $false
    try { if ($proc) { $vivo = -not $proc.WaitForExit(15000) } } catch { }
    if ($vivo) { try { $proc.WaitForExit() } catch { } }
    else {
        $reDir = [regex]::Escape($sel.Dir) + '("|\s|$)'
        $rodando = { @(Get-CimInstance Win32_Process -Filter "CommandLine like '%IAWebDados%'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match $reDir }).Count -gt 0 }
        $t0 = Get-Date
        while (-not (& $rodando) -and ((Get-Date) - $t0).TotalSeconds -lt 4) { Start-Sleep -Milliseconds 300 }   # da tempo do navegador real aparecer
        while (& $rodando) { Start-Sleep -Milliseconds 800 }
    }
}
}   # fim do laco externo
