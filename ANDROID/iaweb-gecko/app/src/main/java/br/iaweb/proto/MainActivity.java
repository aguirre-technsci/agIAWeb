package br.iaweb.proto;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.res.ColorStateList;
import android.content.res.Configuration;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.text.Spannable;
import android.text.SpannableStringBuilder;
import android.text.style.ForegroundColorSpan;
import android.text.style.RelativeSizeSpan;
import android.text.style.StyleSpan;
import android.net.Uri;
import android.graphics.Typeface;
import android.os.Bundle;
import android.text.InputType;
import android.text.TextUtils;
import android.util.Log;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.BaseAdapter;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.HorizontalScrollView;
import android.widget.ListView;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONArray;
import org.json.JSONObject;
import org.mozilla.geckoview.AllowOrDeny;
import org.mozilla.geckoview.GeckoResult;
import org.mozilla.geckoview.GeckoRuntime;
import org.mozilla.geckoview.GeckoRuntimeSettings;
import org.mozilla.geckoview.GeckoSession;
import org.mozilla.geckoview.GeckoSessionSettings;
import org.mozilla.geckoview.GeckoView;
import org.mozilla.geckoview.WebRequestError;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.Date;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.LinkedList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.function.Consumer;

/**
 * IA Web (GeckoView): uma GeckoSession por e-mail, isolada por contextId.
 * Contas do mesmo servico coexistem logadas e o login persiste entre aberturas.
 */
public class MainActivity extends Activity {

    private static final int REQ_IMPORT = 1;
    private static final String TAG = "IAWEB";
    private static final int MAX_LOG = 400;
    private static final int MAX_VIVAS = 3; // sessoes mantidas em memoria; as mais antigas sao fechadas

    // {id, nome, url} - mesmas URLs do IA_Web.ps1
    private static final String[][] IAS_PADRAO = {
        {"claude", "Claude", "https://claude.ai/"},
        {"chatgpt", "ChatGPT", "https://chatgpt.com/"},
        {"gemini", "Gemini", "https://gemini.google.com/"},
        {"deepseek", "DeepSeek", "https://chat.deepseek.com/"},
        {"notebooklm", "NotebookLM", "https://notebook.google.com/"},
        {"perplexity", "Perplexity", "https://www.perplexity.ai/"},
    };

    private static GeckoRuntime runtime; // so pode existir um por processo

    // dados (mesmo formato do ia-web-export.json, versao 1)
    private final List<String> contas = new ArrayList<>();
    private final Map<String, String> tags = new HashMap<>();   // "ia|email" -> tag
    private final Set<String> fixados = new HashSet<>();        // "ia|email"
    private final Map<String, Long> limites = new HashMap<>();  // "ia|email" -> instante (ms UTC) em que o limite volta
    private final Map<String, Long> acessos = new HashMap<>();  // "ia|email" -> ultimo acesso (ms UTC); so existe no app
    private String ordem = "az";                                // "az" | "recente"
    private final List<String[]> extras = new ArrayList<>();    // {id, nome, url}

    // sessoes
    private final Map<String, GeckoSession> sessoes = new HashMap<>();
    private final Map<String, String> iaAberta = new HashMap<>();
    private final Set<String> podeVoltar = new HashSet<>();
    private final LinkedList<String> uso = new LinkedList<>();

    private final LinkedList<String> logBuf = new LinkedList<>();

    // popup (janela de login aberta por window.open, ex.: botao Google do claude.ai)
    private LinearLayout telaPopup;
    private GeckoView popupView;
    private TextView tituloPopup;
    private GeckoSession popupSession;

    // UI
    private LinearLayout telaLista;
    private LinearLayout telaWeb;
    private GeckoView geckoView;
    private LinearLayout chips;
    private String chipsIa;
    private int chipsN;
    private LinearLayout vazio;
    private ListView lista;
    private TextView status;
    private TextView tituloWeb;
    private GrupoAdapter adaptador;
    private final List<Grupo> grupos = new ArrayList<>();
    private TextView bOrdem;
    private String iaAtual = "claude";
    private String emailAtual;

    // ---------------------------------------------------------------- ciclo de vida

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        if (runtime == null) {
            GeckoRuntimeSettings st = new GeckoRuntimeSettings.Builder()
                .remoteDebuggingEnabled(BuildConfig.DEBUG) // inspecao via USB so em build de debug
                .consoleOutput(true)          // console JS do Gecko no logcat (tag GeckoConsole)
                .build();
            runtime = GeckoRuntime.create(getApplicationContext(), st);
        }
        carregarLog();
        reg("APP iniciado, GeckoView " + BuildConfig.GECKO_VERSION);
        carregar();
        montarUi();
        atualizarLista();
    }

    @Override
    public void onBackPressed() {
        if (popupSession != null) {
            fecharPopup("voltar");
            return;
        }
        if (emailAtual == null) {
            super.onBackPressed();
            return;
        }
        GeckoSession s = sessoes.get(emailAtual);
        if (s != null && podeVoltar.contains(emailAtual)) s.goBack();
        else mostrarLista();
    }

    @Override
    protected void onActivityResult(int req, int res, Intent data) {
        super.onActivityResult(req, res, data);
        if (req != REQ_IMPORT || res != RESULT_OK || data == null || data.getData() == null) return;
        try {
            String txt = lerTexto(data.getData());
            int novas = mesclar(new JSONObject(txt));
            salvar();
            atualizarLista();
            reg("IMPORT ok, contas novas=" + novas + ", total=" + contas.size());
            toast("Importado. Contas novas: " + novas + " (total " + contas.size() + ")");
        } catch (Exception e) {
            toast("Importacao falhou: " + e.getMessage());
        }
    }

    // ---------------------------------------------------------------- UI

    // Paleta: neutros quentes e um unico acento (acoes, selecao, "aberta"). Claro/escuro seguem o sistema.
    private boolean temaNoite;
    private int cBg, cSup, cLinha, cTx, cSoft, cAc, cSobreAc, cAviso, cToque;

    private int dp(int v) {
        return (int) (v * getResources().getDisplayMetrics().density);
    }

    private boolean noite() {
        return (getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK)
            == Configuration.UI_MODE_NIGHT_YES;
    }

    private void definirTema() {
        temaNoite = noite();
        if (temaNoite) {
            cBg = 0xFF131412; cSup = 0xFF1D1E1B; cLinha = 0xFF2E2F2B; cTx = 0xFFECEAE4; cSoft = 0xFFA6A298;
            cAc = 0xFF5BD6C8; cSobreAc = 0xFF0B1F1D; cAviso = 0xFFF2A65A; cToque = 0x33FFFFFF;
        } else {
            cBg = 0xFFF7F6F3; cSup = 0xFFFFFFFF; cLinha = 0xFFE4E1DA; cTx = 0xFF1B1A17; cSoft = 0xFF66625A;
            cAc = 0xFF0B6B63; cSobreAc = 0xFFFFFFFF; cAviso = 0xFFA4570B; cToque = 0x1F000000;
        }
        getWindow().setStatusBarColor(cBg);
        getWindow().setNavigationBarColor(cBg);
        View d = getWindow().getDecorView();
        int f = d.getSystemUiVisibility();
        int claro = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR | View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR;
        d.setSystemUiVisibility(temaNoite ? (f & ~claro) : (f | claro));
    }

    private Drawable forma(int cor, int raioDp, int tracoCor) {
        GradientDrawable g = new GradientDrawable();
        g.setColor(cor);
        g.setCornerRadius(dp(raioDp));
        if (tracoCor != 0) g.setStroke(dp(1), tracoCor);
        return g;
    }

    /** Fundo com ondulacao de toque; a mascara segue o raio para o efeito nao vazar do canto. */
    private Drawable toque(Drawable base, int raioDp) {
        return new RippleDrawable(ColorStateList.valueOf(cToque), base, forma(0xFFFFFFFF, raioDp, 0));
    }

    private TextView txt(CharSequence s, float sp, int cor, boolean medio) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextSize(sp);
        t.setTextColor(cor);
        if (medio) t.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        return t;
    }

    /** primario = preenchido (uma acao principal por tela); senao, so texto na cor do acento. */
    private TextView botao(String rotulo, boolean primario, View.OnClickListener ac) {
        TextView b = txt(rotulo, 14, primario ? cSobreAc : cAc, true);
        b.setGravity(Gravity.CENTER);
        b.setMinHeight(dp(48));
        b.setMinWidth(dp(48));
        b.setPadding(dp(14), 0, dp(14), 0);
        b.setBackground(toque(forma(primario ? cAc : 0, 12, 0), 12));
        b.setClickable(true);
        b.setFocusable(true);
        b.setOnClickListener(ac);
        return b;
    }

    private TextView chip(String rotulo, boolean sel, View.OnClickListener ac) {
        TextView c = txt(rotulo, 14, sel ? cSobreAc : cTx, true);
        c.setGravity(Gravity.CENTER);
        c.setMinHeight(dp(44));
        c.setPadding(dp(16), 0, dp(16), 0);
        c.setBackground(toque(sel ? forma(cAc, 22, 0) : forma(cSup, 22, cLinha), 22));
        c.setSelected(sel);
        c.setClickable(true);
        c.setFocusable(true);
        c.setOnClickListener(ac);
        return c;
    }

    private View fio() {
        View v = new View(this);
        v.setBackgroundColor(cLinha);
        return v;
    }

    /** Duas linhas: e-mail em destaque e, abaixo, so o dominio da pagina em tom suave. */
    private CharSequence rotuloDuplo(String email, String url) {
        String host = url == null ? null : Uri.parse(url).getHost();
        String sub = host != null ? host : (url == null ? "" : url);
        SpannableStringBuilder sb = new SpannableStringBuilder(email);
        sb.setSpan(new StyleSpan(Typeface.BOLD), 0, sb.length(), Spannable.SPAN_EXCLUSIVE_EXCLUSIVE);
        int ini = sb.length();
        sb.append('\n').append(sub);
        sb.setSpan(new ForegroundColorSpan(cSoft), ini, sb.length(), Spannable.SPAN_EXCLUSIVE_EXCLUSIVE);
        sb.setSpan(new RelativeSizeSpan(0.85f), ini, sb.length(), Spannable.SPAN_EXCLUSIVE_EXCLUSIVE);
        return sb;
    }

    private LinearLayout barra() {
        LinearLayout b = new LinearLayout(this);
        b.setOrientation(LinearLayout.HORIZONTAL);
        b.setGravity(Gravity.CENTER_VERTICAL);
        b.setBackgroundColor(cSup);
        b.setPadding(dp(4), 0, dp(4), 0);
        return b;
    }

    private TextView tituloDaBarra() {
        TextView t = txt("", 13, cTx, false);
        t.setMaxLines(2);
        t.setEllipsize(TextUtils.TruncateAt.END);
        t.setPadding(dp(4), 0, dp(4), 0);
        return t;
    }

    private void importarJson() {
        Intent i = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        i.addCategory(Intent.CATEGORY_OPENABLE);
        i.setType("*/*");
        startActivityForResult(i, REQ_IMPORT);
    }

    private void recarregar() {
        GeckoSession s = emailAtual == null ? null : sessoes.get(emailAtual);
        if (s != null) s.reload();
    }

    private void montarUi() {
        definirTema();
        final int M = ViewGroup.LayoutParams.MATCH_PARENT, W = ViewGroup.LayoutParams.WRAP_CONTENT;
        FrameLayout raiz = new FrameLayout(this);
        raiz.setBackgroundColor(cBg);

        // --- tela da lista
        telaLista = new LinearLayout(this);
        telaLista.setOrientation(LinearLayout.VERTICAL);

        LinearLayout cab = new LinearLayout(this);
        cab.setOrientation(LinearLayout.HORIZONTAL);
        cab.setGravity(Gravity.CENTER_VERTICAL);
        cab.setPadding(dp(20), dp(12), dp(8), 0);
        LinearLayout tit = new LinearLayout(this);
        tit.setOrientation(LinearLayout.VERTICAL);
        tit.addView(txt("IA Web", 26, cTx, true));
        status = txt("", 13, cSoft, false);
        tit.addView(status);
        cab.addView(tit, new LinearLayout.LayoutParams(0, W, 1f));
        cab.addView(botao("Importar", false, v -> importarJson()));
        cab.addView(botao("Log", false, v -> mostrarLog()));
        telaLista.addView(cab);

        HorizontalScrollView rolagem = new HorizontalScrollView(this);
        rolagem.setHorizontalScrollBarEnabled(false);
        chips = new LinearLayout(this);
        chips.setOrientation(LinearLayout.HORIZONTAL);
        chips.setPadding(dp(16), dp(12), dp(8), dp(4));
        rolagem.addView(chips);
        telaLista.addView(rolagem);
        chipsIa = null;
        chipsN = -1;

        LinearLayout linhaOrdem = new LinearLayout(this);
        linhaOrdem.setOrientation(LinearLayout.HORIZONTAL);
        linhaOrdem.setGravity(Gravity.CENTER_VERTICAL);
        linhaOrdem.setPadding(dp(8), 0, dp(8), 0);
        linhaOrdem.addView(botao("Pr\u00f3xima livre", false, v -> abrirProximaLivre()));
        linhaOrdem.addView(new View(this), new LinearLayout.LayoutParams(0, 1, 1f));
        bOrdem = botao("Ordem: A-Z", false, v -> {
            ordem = "recente".equals(ordem) ? "az" : "recente";
            salvar();
            atualizarLista();
        });
        linhaOrdem.addView(bOrdem);
        telaLista.addView(linhaOrdem);
        telaLista.addView(fio(), new LinearLayout.LayoutParams(M, 1));

        lista = new ListView(this);
        adaptador = new GrupoAdapter();
        lista.setAdapter(adaptador);
        lista.setDivider(null);
        lista.setDividerHeight(0);
        lista.setSelector(new ColorDrawable(0));   // cada linha tem a propria ondulacao
        // toque: abre a conta (se o grupo tem varios dominios, pergunta qual)
        lista.setOnItemClickListener((p, v, pos, id) ->
            escolherConta(grupos.get(pos), e -> abrir(iaAtual, e)));
        // toque longo: menu da conta (tag, fixar, limite, apagar login...)
        lista.setOnItemLongClickListener((p, v, pos, id) -> {
            escolherConta(grupos.get(pos), this::menuConta);
            return true;
        });

        vazio = new LinearLayout(this);
        vazio.setOrientation(LinearLayout.VERTICAL);
        vazio.setGravity(Gravity.CENTER);
        vazio.setPadding(dp(32), dp(32), dp(32), dp(32));
        TextView vt = txt("Nenhuma conta ainda", 18, cTx, true);
        vt.setGravity(Gravity.CENTER);
        vazio.addView(vt);
        TextView vd = txt("Importe o ia-web-export.json do PC ou adicione uma conta.", 14, cSoft, false);
        vd.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams lpd = new LinearLayout.LayoutParams(W, W);
        lpd.topMargin = dp(8);
        vazio.addView(vd, lpd);
        LinearLayout.LayoutParams lpi = new LinearLayout.LayoutParams(W, W);
        lpi.topMargin = dp(16);
        vazio.addView(botao("Importar JSON", false, v -> importarJson()), lpi);

        FrameLayout miolo = new FrameLayout(this);
        miolo.addView(lista, new FrameLayout.LayoutParams(M, M));
        miolo.addView(vazio, new FrameLayout.LayoutParams(M, M));
        telaLista.addView(miolo, new LinearLayout.LayoutParams(M, 0, 1f));

        LinearLayout.LayoutParams lpn = new LinearLayout.LayoutParams(M, dp(52));
        lpn.setMargins(dp(16), dp(8), dp(16), dp(16));
        telaLista.addView(botao("Nova conta", true, v -> dialogoNovaConta()), lpn);

        // --- tela web
        telaWeb = new LinearLayout(this);
        telaWeb.setOrientation(LinearLayout.VERTICAL);
        telaWeb.setBackgroundColor(cBg);
        telaWeb.setVisibility(View.GONE);

        LinearLayout topo = barra();
        topo.addView(botao("Lista", false, v -> mostrarLista()));
        tituloWeb = tituloDaBarra();
        topo.addView(tituloWeb, new LinearLayout.LayoutParams(0, W, 1f));
        topo.addView(botao("Limite", false, v -> {
            if (emailAtual == null) return;
            String ia = iaAberta.get(emailAtual);
            dialogoLimite(ia == null ? iaAtual : ia, emailAtual, true);
        }));
        topo.addView(botao("Mais", false, v -> menuMais()));
        telaWeb.addView(topo, new LinearLayout.LayoutParams(M, dp(56)));
        telaWeb.addView(fio(), new LinearLayout.LayoutParams(M, 1));

        geckoView = new GeckoView(this);
        telaWeb.addView(geckoView, new LinearLayout.LayoutParams(M, 0, 1f));

        // --- tela do popup (sobrepoe a tela web enquanto aberta)
        telaPopup = new LinearLayout(this);
        telaPopup.setOrientation(LinearLayout.VERTICAL);
        telaPopup.setBackgroundColor(cBg);
        telaPopup.setVisibility(View.GONE);

        LinearLayout topoP = barra();
        topoP.addView(botao("Fechar", false, v -> fecharPopup("botao")));
        tituloPopup = tituloDaBarra();
        topoP.addView(tituloPopup, new LinearLayout.LayoutParams(0, W, 1f));
        telaPopup.addView(topoP, new LinearLayout.LayoutParams(M, dp(56)));
        telaPopup.addView(fio(), new LinearLayout.LayoutParams(M, 1));

        popupView = new GeckoView(this);
        telaPopup.addView(popupView, new LinearLayout.LayoutParams(M, 0, 1f));

        raiz.addView(telaLista, new FrameLayout.LayoutParams(M, M));
        raiz.addView(telaWeb, new FrameLayout.LayoutParams(M, M));
        raiz.addView(telaPopup, new FrameLayout.LayoutParams(M, M));
        setContentView(raiz);
    }

    /** uiMode esta em configChanges (nao recria a tela): ao trocar claro/escuro, refaz a UI e religa a sessao aberta. */
    @Override
    public void onConfigurationChanged(Configuration c) {
        super.onConfigurationChanged(c);
        if (noite() == temaNoite) return;
        String e = emailAtual;
        if (popupSession != null) fecharPopup("tema");
        if (geckoView != null && geckoView.getSession() != null) geckoView.releaseSession();
        montarUi();
        atualizarLista();
        GeckoSession s = e == null ? null : sessoes.get(e);
        if (s != null) {
            geckoView.setSession(s);
            tituloWeb.setText(rotuloDuplo(e, urlDa(iaAberta.get(e) == null ? iaAtual : iaAberta.get(e))));
            telaLista.setVisibility(View.GONE);
            telaWeb.setVisibility(View.VISIBLE);
        }
    }

    private void atualizarChips() {
        List<String[]> todas = todasIas();
        if (iaAtual.equals(chipsIa) && chipsN == todas.size()) return;
        chipsIa = iaAtual;
        chipsN = todas.size();
        chips.removeAllViews();
        for (final String[] ia : todas) {
            TextView c = chip(ia[1], ia[0].equals(iaAtual), v -> {
                iaAtual = ia[0];
                atualizarLista();
            });
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            lp.rightMargin = dp(8);
            chips.addView(c, lp);
        }
    }

    /** Contas com o mesmo texto antes do @ (ex.: nome@gmail.com e nome@outlook.com) formam um cartao. */
    private static class Grupo {
        final String chave;
        final List<String> emails = new ArrayList<>();

        Grupo(String chave) {
            this.chave = chave;
        }
    }

    private class GrupoAdapter extends BaseAdapter {
        @Override public int getCount() { return grupos.size(); }
        @Override public Object getItem(int i) { return grupos.get(i); }
        @Override public long getItemId(int i) { return i; }

        @Override
        public View getView(int pos, View conv, ViewGroup parent) {
            Grupo g = grupos.get(pos);
            boolean viva = false;
            for (String e : g.emails) if (sessoes.containsKey(e)) viva = true;

            LinearLayout linha = new LinearLayout(MainActivity.this);
            linha.setOrientation(LinearLayout.HORIZONTAL);
            linha.setGravity(Gravity.CENTER_VERTICAL);
            linha.setMinimumHeight(dp(68));
            linha.setPadding(dp(16), dp(10), dp(16), dp(10));
            linha.setBackground(toque(forma(0, 0, 0), 0));

            // inicial: preenchida quando ha sessao aberta (o texto "aberta" repete a informacao)
            String ini = g.chave.isEmpty() ? "?" : g.chave.substring(0, 1).toUpperCase(Locale.ROOT);
            TextView av = txt(ini, 16, viva ? cSobreAc : cAc, true);
            av.setGravity(Gravity.CENTER);
            av.setBackground(viva ? forma(cAc, 20, 0) : forma(cSup, 20, cLinha));
            linha.addView(av, new LinearLayout.LayoutParams(dp(40), dp(40)));

            LinearLayout col = new LinearLayout(MainActivity.this);
            col.setOrientation(LinearLayout.VERTICAL);
            TextView t1 = txt(tituloDe(g), 16, cTx, true);
            t1.setSingleLine(true);
            t1.setEllipsize(TextUtils.TruncateAt.END);
            col.addView(t1);
            String s2 = subtituloDe(g);
            if (!s2.isEmpty()) {
                TextView t2 = txt(s2, 13, cSoft, false);
                t2.setSingleLine(true);
                t2.setEllipsize(TextUtils.TruncateAt.END);
                col.addView(t2);
            }
            String s3 = limiteDe(g);
            if (s3 != null) {
                TextView t3 = txt(s3, 13, cAviso, false);
                t3.setSingleLine(true);
                t3.setEllipsize(TextUtils.TruncateAt.END);
                col.addView(t3);
            }
            LinearLayout.LayoutParams lpc = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
            lpc.leftMargin = dp(16);
            linha.addView(col, lpc);

            List<String> est = new ArrayList<>();
            if (fixado(g)) est.add("fixada");
            if (viva) est.add("aberta");
            if (!est.isEmpty()) {
                TextView te = txt(TextUtils.join(" · ", est), 12, viva ? cAc : cSoft, true);
                te.setPadding(dp(12), 0, 0, 0);
                linha.addView(te);
            }

            LinearLayout cel = new LinearLayout(MainActivity.this);
            cel.setOrientation(LinearLayout.VERTICAL);
            cel.addView(linha);
            LinearLayout.LayoutParams lpf = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 1);
            lpf.leftMargin = dp(72);
            cel.addView(fio(), lpf);
            return cel;
        }
    }

    private boolean fixado(Grupo g) {
        for (String e : g.emails) if (fixados.contains(iaAtual + "|" + e)) return true;
        return false;
    }

    private long ultimoAcesso(Grupo g) {
        long m = 0;
        for (String e : g.emails) {
            Long t = acessos.get(iaAtual + "|" + e);
            if (t != null && t > m) m = t;
        }
        return m;
    }

    private Long limiteAtivo(String ia, String email) {
        Long t = limites.get(ia + "|" + email);
        return (t != null && t > System.currentTimeMillis()) ? t : null;
    }

    /** "2h 10min" / "35 min" ate o instante dado. */
    private String restante(long ate) {
        long min = Math.max(1, (ate - System.currentTimeMillis() + 59999) / 60000);
        if (min < 60) return min + " min";
        return (min / 60) + "h" + (min % 60 == 0 ? "" : " " + (min % 60) + "min");
    }

    private String tituloDe(Grupo g) {
        return g.emails.size() == 1 ? g.emails.get(0) : g.chave + "  (" + g.emails.size() + ")";
    }

    /** Tag (conta unica) ou dominios (cartao com varias contas). Vazio se nao ha o que mostrar. */
    private String subtituloDe(Grupo g) {
        if (g.emails.size() == 1) {
            String tag = tags.get(iaAtual + "|" + g.emails.get(0));
            return tag == null || tag.isEmpty() ? "" : tag;
        }
        List<String> dominios = new ArrayList<>();
        for (String e : g.emails) dominios.add(e.substring(e.indexOf('@') + 1));
        return TextUtils.join(", ", dominios);
    }

    private String limiteDe(Grupo g) {
        if (g.emails.size() == 1) {
            Long lim = limiteAtivo(iaAtual, g.emails.get(0));
            return lim == null ? null : "Limite volta em ~" + restante(lim);
        }
        int n = 0;
        for (String e : g.emails) if (limiteAtivo(iaAtual, e) != null) n++;
        return n == 0 ? null : n + (n == 1 ? " conta com limite" : " contas com limite");
    }

    private void atualizarLista() {
        atualizarChips();
        Map<String, Grupo> mapa = new LinkedHashMap<>();
        for (String e : contas) {
            String k = e.substring(0, e.indexOf('@'));
            Grupo g = mapa.get(k);
            if (g == null) {
                g = new Grupo(k);
                mapa.put(k, g);
            }
            g.emails.add(e);
        }
        grupos.clear();
        for (Grupo g : mapa.values()) {
            Collections.sort(g.emails, String::compareToIgnoreCase);
            grupos.add(g);
        }
        final boolean recente = "recente".equals(ordem);
        Collections.sort(grupos, (a, b) -> {
            boolean fa = fixado(a), fb = fixado(b);
            if (fa != fb) return fa ? -1 : 1;
            if (recente) {
                long ra = ultimoAcesso(a), rb = ultimoAcesso(b);
                if (ra != rb) return ra > rb ? -1 : 1;
            }
            return a.chave.compareToIgnoreCase(b.chave);
        });
        adaptador.notifyDataSetChanged();
        bOrdem.setText(recente ? "Ordem: recentes" : "Ordem: A-Z");

        int comLimite = 0;
        for (String e : contas) if (limiteAtivo(iaAtual, e) != null) comLimite++;
        boolean semContas = contas.isEmpty();
        vazio.setVisibility(semContas ? View.VISIBLE : View.GONE);
        lista.setVisibility(semContas ? View.GONE : View.VISIBLE);
        status.setText(semContas ? "Nenhuma conta"
            : contas.size() + (contas.size() == 1 ? " conta" : " contas")
                + (comLimite > 0 ? "  ·  " + comLimite + " com limite" : ""));
    }

    /** Se o cartao tem uma conta so, usa ela; se tem varias dominios, pergunta qual. */
    private void escolherConta(Grupo g, final Consumer<String> acao) {
        if (g.emails.size() == 1) {
            acao.accept(g.emails.get(0));
            return;
        }
        final List<String> emails = new ArrayList<>(g.emails);
        String[] itens = new String[emails.size()];
        for (int i = 0; i < itens.length; i++) {
            String e = emails.get(i);
            String tag = tags.get(iaAtual + "|" + e);
            Long lim = limiteAtivo(iaAtual, e);
            itens[i] = e
                + (tag == null || tag.isEmpty() ? "" : "  [" + tag + "]")
                + (lim != null ? "  (limite volta em ~" + restante(lim) + ")" : "")
                + (sessoes.containsKey(e) ? "  (aberta)" : "");
        }
        dlg().setTitle(g.chave)
            .setItems(itens, (d, qual) -> acao.accept(emails.get(qual))).show();
    }

    private String nomeIa(String id) {
        for (String[] x : todasIas()) if (x[0].equals(id)) return x[1];
        return id;
    }

    private void menuConta(final String email) {
        final String chave = iaAtual + "|" + email;
        final boolean fix = fixados.contains(chave);
        final boolean comLimite = limiteAtivo(iaAtual, email) != null;
        final List<String> nomes = new ArrayList<>();
        final List<Runnable> acoes = new ArrayList<>();

        nomes.add(fix ? "Desafixar" : "Fixar no topo");
        acoes.add(() -> {
            if (fix) fixados.remove(chave); else fixados.add(chave);
            salvar();
            atualizarLista();
        });
        nomes.add("Definir tag");
        acoes.add(() -> dialogoTag(email));
        nomes.add(comLimite ? "Alterar limite..." : "Marcar limite...");
        acoes.add(() -> dialogoLimite(iaAtual, email, false));
        if (comLimite) {
            nomes.add("Limpar limite");
            acoes.add(() -> {
                limites.remove(chave);
                salvar();
                atualizarLista();
            });
        }
        nomes.add("Apagar login desta conta (cookies)");
        acoes.add(() -> confirmar("Apagar o login de " + email + "?", () -> apagarLogin(email)));
        nomes.add("Remover da lista (e apagar login)");
        acoes.add(() -> confirmar("Remover " + email + " e apagar o login?", () -> {
            apagarLogin(email);
            contas.remove(email);
            removerChaves(email);
            salvar();
            atualizarLista();
        }));

        dlg().setTitle(email + "  [" + nomeIa(iaAtual) + "]")
            .setItems(nomes.toArray(new String[0]), (d, qual) -> acoes.get(qual).run()).show();
    }

    /** Tira tag, fixado, limite e acesso de todas as IAs para esse e-mail. */
    private void removerChaves(String email) {
        String sufixo = "|" + email;
        tags.keySet().removeIf(k -> k.endsWith(sufixo));
        fixados.removeIf(k -> k.endsWith(sufixo));
        limites.keySet().removeIf(k -> k.endsWith(sufixo));
        acessos.keySet().removeIf(k -> k.endsWith(sufixo));
    }

    private static final long[] HORAS_LIMITE = {1, 3, 5, 12, 24};

    /** Janela tipica de cada IA (fonte secundaria, nao confirmada na documentacao): so ordena e rotula. */
    private static long horasSugeridas(String ia) {
        if ("claude".equals(ia)) return 5;
        if ("perplexity".equals(ia)) return 24;
        return 0;
    }

    /** Marca "limite atingido" por uma duracao (estimativa). Na web, oferece abrir a proxima conta livre. */
    private void dialogoLimite(final String ia, final String email, final boolean daWeb) {
        final long sug = horasSugeridas(ia);
        final List<Long> horas = new ArrayList<>();
        if (sug > 0) horas.add(sug);
        for (long h : HORAS_LIMITE) if (h != sug) horas.add(h);
        String[] rot = new String[horas.size()];
        for (int i = 0; i < rot.length; i++) {
            long h = horas.get(i);
            rot[i] = h + (h == 1 ? " hora" : " horas") + (h == sug ? "  (sugerido)" : "");
        }
        dlg().setTitle("O limite volta em...")
            .setItems(rot, (d, qual) -> {
                limites.put(ia + "|" + email, System.currentTimeMillis() + horas.get(qual) * 3600000L);
                reg("LIMITE " + ia + " " + email + " +" + horas.get(qual) + "h");
                salvar();
                atualizarLista();
                if (daWeb) oferecerProxima(ia, email);
            }).show();
    }

    /** Conta sem limite ativo que esta ha mais tempo sem uso (nunca usada vem primeiro). */
    private String proximaLivre(String ia, String excluir) {
        String melhor = null;
        long ma = Long.MAX_VALUE;
        for (String e : contas) {
            if (e.equals(excluir) || limiteAtivo(ia, e) != null) continue;
            Long t = acessos.get(ia + "|" + e);
            long a = t == null ? 0 : t;
            if (melhor == null || a < ma || (a == ma && e.compareToIgnoreCase(melhor) < 0)) {
                melhor = e;
                ma = a;
            }
        }
        return melhor;
    }

    private void oferecerProxima(final String ia, String atual) {
        final String p = proximaLivre(ia, atual);
        if (p == null) {
            toast("Limite marcado. Nenhuma outra conta livre em " + nomeIa(ia) + ".");
            return;
        }
        dlg().setTitle("Limite marcado")
            .setMessage("Abrir " + p + " em " + nomeIa(ia) + "?")
            .setPositiveButton("Abrir", (d, w) -> abrir(ia, p))
            .setNegativeButton("Agora n\u00e3o", null).show();
    }

    private void abrirProximaLivre() {
        String p = proximaLivre(iaAtual, null);
        if (p == null) toast("Todas as contas de " + nomeIa(iaAtual) + " est\u00e3o com limite.");
        else abrir(iaAtual, p);
    }

    private void menuMais() {
        dlg().setItems(new String[]{"Atualizar p\u00e1gina", "Log"}, (d, qual) -> {
            if (qual == 0) recarregar(); else mostrarLog();
        }).show();
    }

    private AlertDialog.Builder dlg() {
        return new AlertDialog.Builder(this, temaNoite
            ? android.R.style.Theme_DeviceDefault_Dialog_Alert
            : android.R.style.Theme_DeviceDefault_Light_Dialog_Alert);
    }

    private View comMargem(View v) {
        FrameLayout f = new FrameLayout(this);
        f.setPadding(dp(20), dp(8), dp(20), 0);
        f.addView(v);
        return f;
    }

    private void confirmar(String msg, final Runnable acao) {
        dlg().setMessage(msg)
            .setPositiveButton("Sim", (d, w) -> acao.run())
            .setNegativeButton("Cancelar", null).show();
    }

    private void dialogoNovaConta() {
        final EditText in = new EditText(this);
        in.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS);
        in.setHint("nome@exemplo.com");
        dlg().setTitle("Nova conta").setView(comMargem(in))
            .setPositiveButton("Adicionar", (d, w) -> {
                String e = in.getText().toString().trim().toLowerCase();
                if (!e.contains("@")) { toast("E-mail invalido"); return; }
                if (!contas.contains(e)) contas.add(e);
                salvar();
                atualizarLista();
            }).setNegativeButton("Cancelar", null).show();
    }

    private void dialogoTag(final String email) {
        final EditText in = new EditText(this);
        String atual = tags.get(iaAtual + "|" + email);
        in.setText(atual == null ? "" : atual);
        dlg().setTitle("Tag de " + email).setView(comMargem(in))
            .setPositiveButton("OK", (d, w) -> {
                String t = in.getText().toString().trim();
                if (t.isEmpty()) tags.remove(iaAtual + "|" + email);
                else tags.put(iaAtual + "|" + email, t);
                salvar();
                atualizarLista();
            }).setNegativeButton("Cancelar", null).show();
    }

    private void toast(String m) {
        Toast.makeText(this, m, Toast.LENGTH_LONG).show();
    }

    // ---------------------------------------------------------------- sessoes Gecko

    /** Para log: tira fragmento e mascara valores de query (OAuth carrega codigos/tokens). */
    static String limpa(String u) {
        if (u == null) return "(null)";
        int h = u.indexOf('#');
        if (h >= 0) u = u.substring(0, h) + "#...";
        u = u.replaceAll("=([^&#]*)", "=_");
        return u.length() > 200 ? u.substring(0, 200) + "..." : u;
    }

    // ---------------------------------------------------------------- log interno

    /** Registra no logcat (tag IAWEB) e no buffer do app (botao Log), persistido entre execucoes. */
    private void reg(String msg) {
        String linha = new SimpleDateFormat("HH:mm:ss.SSS", Locale.US).format(new Date()) + " " + msg;
        Log.i(TAG, msg);
        synchronized (logBuf) {
            logBuf.add(linha);
            while (logBuf.size() > MAX_LOG) logBuf.removeFirst();
            prefs().edit().putString("log", TextUtils.join("\n", logBuf)).apply();
        }
    }

    private void carregarLog() {
        String t = prefs().getString("log", null);
        if (t == null || t.isEmpty()) return;
        synchronized (logBuf) {
            Collections.addAll(logBuf, t.split("\n"));
        }
    }

    private String textoLog() {
        synchronized (logBuf) {
            return logBuf.isEmpty() ? "(vazio)" : TextUtils.join("\n", logBuf);
        }
    }

    private void mostrarLog() {
        final String txt = textoLog();
        TextView tv = new TextView(this);
        tv.setText(txt);
        tv.setTextSize(10);
        tv.setTypeface(Typeface.MONOSPACE);
        tv.setTextIsSelectable(true);
        tv.setPadding(dp(12), dp(8), dp(12), dp(8));
        final ScrollView sv = new ScrollView(this);
        sv.addView(tv);
        sv.post(() -> sv.fullScroll(View.FOCUS_DOWN));
        dlg()
            .setTitle("Log (" + logBuf.size() + " linhas)")
            .setView(sv)
            .setPositiveButton("Copiar", (d, w) -> {
                ClipboardManager cm = (ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
                cm.setPrimaryClip(ClipData.newPlainText("log IAWEB", txt));
                toast("Log copiado");
            })
            .setNeutralButton("Compartilhar", (d, w) -> {
                Intent i = new Intent(Intent.ACTION_SEND);
                i.setType("text/plain");
                i.putExtra(Intent.EXTRA_TEXT, txt);
                startActivity(Intent.createChooser(i, "Compartilhar log"));
            })
            .setNegativeButton("Limpar", (d, w) -> {
                synchronized (logBuf) { logBuf.clear(); }
                prefs().edit().remove("log").apply();
                toast("Log limpo");
            })
            .show();
    }

    /** Mesma regra do PC: e-mail com tudo que nao e a-z0-9 trocado por _. */
    static String contextId(String email) {
        return email.toLowerCase().replaceAll("[^a-z0-9]", "_");
    }

    private GeckoSession criarSessao(String email) {
        GeckoSession s = novaSessao(email, false);
        s.open(runtime);
        return s;
    }

    /** Cria a sessao (ainda nao aberta). popup=true: janela aberta por window.open, que o Gecko abre sozinho. */
    private GeckoSession novaSessao(final String email, final boolean popup) {
        GeckoSessionSettings cfg = new GeckoSessionSettings.Builder()
            .contextId(contextId(email))
            .build();
        final GeckoSession s = new GeckoSession(cfg);
        final String rot = popup ? " [popup]" : "";

        s.setNavigationDelegate(new GeckoSession.NavigationDelegate() {
            // window.open / target=_blank. Login Google do claude.ai usa popup que devolve o resultado
            // ao opener por postMessage: precisa ser uma janela de verdade, com opener.
            @Override
            public GeckoResult<GeckoSession> onNewSession(GeckoSession session, String uri) {
                reg(email + rot + " JANELA_NOVA -> " + limpa(uri));
                if (popup) {            // popup dentro de popup: carrega na propria janela
                    session.loadUri(uri);
                    return null;
                }
                GeckoResult<GeckoSession> r = abrirPopup(email, uri);
                if (r == null) session.loadUri(uri);   // plano B: mesma aba
                return r;
            }

            // Registra cada pedido de navegacao (inclui redirecionamentos). Sempre permite.
            // Sem @Override de proposito: se a assinatura mudar, nao quebra o build.
            public GeckoResult<AllowOrDeny> onLoadRequest(GeckoSession session, GeckoSession.NavigationDelegate.LoadRequest request) {
                reg(email + rot + " PEDIDO uri=" + limpa(request.uri) + " target=" + request.target);
                return null;
            }

            // Diagnostico: sem isto o GeckoView deixa a tela branca em erro de carga.
            public GeckoResult<String> onLoadError(GeckoSession session, String uri, WebRequestError error) {
                reg(email + rot + " ERRO uri=" + limpa(uri) + " code=" + error.code + " category=" + error.category);
                String u = uri == null ? "(sem endereco)" : uri.replace("&", "&amp;").replace("<", "&lt;");
                String html = "<html><head><meta name='viewport' content='width=device-width,initial-scale=1'></head>"
                    + "<body style='font-family:sans-serif;padding:16px;word-wrap:break-word'>"
                    + "<h3>Falha ao carregar</h3><p>" + u + "</p>"
                    + "<p>code=" + error.code + " category=" + error.category + "</p></body></html>";
                return GeckoResult.fromValue("data:text/html;charset=utf-8," + Uri.encode(html));
            }

            // sem @Override de proposito: se a assinatura mudar na sua versao, nao quebra o build
            public void onCanGoBack(GeckoSession session, boolean can) {
                if (popup) return;
                if (can) podeVoltar.add(email); else podeVoltar.remove(email);
            }
        });

        s.setProgressDelegate(new GeckoSession.ProgressDelegate() {
            @Override
            public void onPageStart(GeckoSession session, String url) {
                reg(email + rot + " INICIO " + limpa(url));
                if (popup) tituloPopup.setText(rotuloDuplo(email, url));
                else if (email.equals(emailAtual)) tituloWeb.setText(rotuloDuplo(email, url));
            }

            @Override
            public void onPageStop(GeckoSession session, boolean ok) {
                reg(email + rot + " FIM ok=" + ok);
            }
        });

        if (popup) {
            // window.close() da pagina: fecha a janela e devolve a tela a conta. Sem @Override de proposito.
            s.setContentDelegate(new GeckoSession.ContentDelegate() {
                public void onCloseRequest(GeckoSession session) {
                    reg(email + rot + " CLOSE_REQUEST (a pagina pediu para fechar)");
                    fecharPopup("pagina");
                }
            });
        }
        return s;
    }

    /** Abre a janela de popup. Retorna a sessao (nao aberta) para o Gecko ligar ao opener, ou null se falhar. */
    private GeckoResult<GeckoSession> abrirPopup(String email, String uri) {
        try {
            fecharPopup("novo popup");
            GeckoSession p = novaSessao(email, true);
            popupSession = p;
            popupView.setSession(p);
            tituloPopup.setText(rotuloDuplo(email, "Janela de login"));
            telaWeb.setVisibility(View.GONE);
            telaPopup.setVisibility(View.VISIBLE);
            reg("POPUP aberto -> " + limpa(uri));
            return GeckoResult.fromValue(p);
        } catch (Exception e) {
            reg("POPUP falhou: " + e + " (carregando na mesma aba)");
            popupSession = null;
            telaPopup.setVisibility(View.GONE);
            if (emailAtual != null) telaWeb.setVisibility(View.VISIBLE);
            return null;
        }
    }

    private void fecharPopup(String motivo) {
        if (popupSession == null) return;
        reg("POPUP fechado (" + motivo + ")");
        GeckoSession p = popupSession;
        popupSession = null;
        if (popupView.getSession() == p) popupView.releaseSession();
        p.close();
        telaPopup.setVisibility(View.GONE);
        if (emailAtual != null) telaWeb.setVisibility(View.VISIBLE);
    }

    private String urlDa(String ia) {
        for (String[] x : todasIas()) if (x[0].equals(ia)) return x[2];
        return IAS_PADRAO[0][2];
    }

    private void abrir(String ia, String email) {
        acessos.put(ia + "|" + email, System.currentTimeMillis());
        salvar();
        Long lim = limiteAtivo(ia, email);
        if (lim != null) toast("Limite marcado: volta em ~" + restante(lim));
        GeckoSession s = sessoes.get(email);
        boolean nova = false;
        if (s == null) {
            s = criarSessao(email);
            sessoes.put(email, s);
            nova = true;
        }
        uso.remove(email);
        uso.add(email);
        while (uso.size() > MAX_VIVAS) fecharSessao(uso.removeFirst());

        emailAtual = email;
        reg("ABRIR " + ia + " " + email + (nova ? " (sessao nova)" : " (sessao reaproveitada)"));
        if (geckoView.getSession() != s) {
            if (geckoView.getSession() != null) geckoView.releaseSession();
            geckoView.setSession(s);
        }
        if (nova || !ia.equals(iaAberta.get(email))) {
            s.loadUri(urlDa(ia));
            iaAberta.put(email, ia);
        }
        tituloWeb.setText(rotuloDuplo(email, urlDa(ia)));
        telaLista.setVisibility(View.GONE);
        telaWeb.setVisibility(View.VISIBLE);
    }

    private void mostrarLista() {
        fecharPopup("lista");
        emailAtual = null;
        if (geckoView.getSession() != null) geckoView.releaseSession();
        telaWeb.setVisibility(View.GONE);
        telaLista.setVisibility(View.VISIBLE);
        atualizarLista();
    }

    private void fecharSessao(String email) {
        GeckoSession s = sessoes.remove(email);
        uso.remove(email);
        iaAberta.remove(email);
        podeVoltar.remove(email);
        if (s == null) return;
        if (geckoView.getSession() == s) geckoView.releaseSession();
        s.close();
    }

    private void apagarLogin(String email) {
        reg("APAGAR_LOGIN " + email);
        fecharSessao(email);
        runtime.getStorageController().clearDataForSessionContext(contextId(email));
        toast("Login apagado: " + email);
        atualizarLista();
    }

    // ---------------------------------------------------------------- dados

    private List<String[]> todasIas() {
        List<String[]> r = new ArrayList<>();
        Collections.addAll(r, IAS_PADRAO);
        r.addAll(extras);
        return r;
    }

    private boolean iaExiste(String id) {
        for (String[] x : todasIas()) if (x[0].equals(id)) return true;
        return false;
    }

    private SharedPreferences prefs() {
        return getSharedPreferences("iaweb", MODE_PRIVATE);
    }

    private void carregar() {
        String txt = prefs().getString("dados", null);
        if (txt == null) return;
        try {
            mesclar(new JSONObject(txt));
        } catch (Exception e) {
            toast("Dados salvos ilegiveis: " + e.getMessage());
        }
    }

    /** Junta um JSON no formato do exportador ao estado atual. Retorna quantas contas novas. */
    private int mesclar(JSONObject o) throws Exception {
        int v = o.optInt("versao", -1);
        if (v != 1) throw new IllegalArgumentException("versao do JSON desconhecida: " + v);
        int novas = 0;

        JSONArray c = o.optJSONArray("contas");
        if (c != null) for (int i = 0; i < c.length(); i++) {
            String e = c.getString(i).trim().toLowerCase();
            if (e.contains("@") && !contas.contains(e)) { contas.add(e); novas++; }
        }
        JSONArray t = o.optJSONArray("tags");
        if (t != null) for (int i = 0; i < t.length(); i++) {
            JSONObject x = t.getJSONObject(i);
            String val = x.optString("valor", "");
            String k = x.getString("ia") + "|" + x.getString("email").toLowerCase();
            if (val.isEmpty()) tags.remove(k); else tags.put(k, val);
        }
        JSONArray f = o.optJSONArray("fixados");
        if (f != null) for (int i = 0; i < f.length(); i++) {
            JSONObject x = f.getJSONObject(i);
            fixados.add(x.getString("ia") + "|" + x.getString("email").toLowerCase());
        }
        JSONArray ia = o.optJSONArray("ias");
        if (ia != null) for (int i = 0; i < ia.length(); i++) {
            JSONObject x = ia.getJSONObject(i);
            String nome = x.getString("nome");
            String id = nome.toLowerCase().replaceAll("[^a-z0-9]", "");
            if (!id.isEmpty() && !iaExiste(id)) extras.add(new String[]{id, nome, x.getString("url")});
        }
        // limites: so os que ainda nao venceram (instante em ms UTC, guardado como texto)
        JSONArray lim = o.optJSONArray("limites");
        long agora = System.currentTimeMillis();
        if (lim != null) for (int i = 0; i < lim.length(); i++) {
            JSONObject x = lim.getJSONObject(i);
            try {
                long quando = Long.parseLong(x.optString("valor", "0").trim());
                if (quando > agora) limites.put(x.getString("ia") + "|" + x.getString("email").toLowerCase(), quando);
            } catch (NumberFormatException ignorado) { /* valor invalido: ignora */ }
        }
        String ord = o.optString("ordem", "");
        if (ord.equals("az") || ord.equals("recente")) ordem = ord;
        // acessos: so existe no app (o exportador nao tem ultimo acesso)
        JSONArray ac = o.optJSONArray("acessos");
        if (ac != null) for (int i = 0; i < ac.length(); i++) {
            JSONObject x = ac.getJSONObject(i);
            try {
                acessos.put(x.getString("ia") + "|" + x.getString("email").toLowerCase(),
                    Long.parseLong(x.optString("valor", "0").trim()));
            } catch (NumberFormatException ignorado) { /* ignora */ }
        }
        return novas;
    }

    private void salvar() {
        try {
            JSONObject o = new JSONObject();
            o.put("versao", 1);
            JSONArray c = new JSONArray();
            for (String e : contas) c.put(e);
            o.put("contas", c);

            JSONArray t = new JSONArray();
            for (Map.Entry<String, String> e : tags.entrySet()) {
                int p = e.getKey().indexOf('|');
                t.put(new JSONObject().put("ia", e.getKey().substring(0, p))
                    .put("email", e.getKey().substring(p + 1)).put("valor", e.getValue()));
            }
            o.put("tags", t);

            JSONArray f = new JSONArray();
            for (String k : fixados) {
                int p = k.indexOf('|');
                f.put(new JSONObject().put("ia", k.substring(0, p))
                    .put("email", k.substring(p + 1)).put("valor", "1"));
            }
            o.put("fixados", f);

            JSONArray ia = new JSONArray();
            for (String[] x : extras) ia.put(new JSONObject().put("nome", x[1]).put("url", x[2]));
            o.put("ias", ia);

            long agora = System.currentTimeMillis();
            JSONArray lim = new JSONArray();
            for (Map.Entry<String, Long> e : limites.entrySet()) {
                if (e.getValue() <= agora) continue;   // vencido: nao guarda
                int p = e.getKey().indexOf('|');
                lim.put(new JSONObject().put("ia", e.getKey().substring(0, p))
                    .put("email", e.getKey().substring(p + 1)).put("valor", String.valueOf(e.getValue())));
            }
            o.put("limites", lim);
            o.put("ordem", ordem);

            JSONArray ac = new JSONArray();
            for (Map.Entry<String, Long> e : acessos.entrySet()) {
                int p = e.getKey().indexOf('|');
                ac.put(new JSONObject().put("ia", e.getKey().substring(0, p))
                    .put("email", e.getKey().substring(p + 1)).put("valor", String.valueOf(e.getValue())));
            }
            o.put("acessos", ac);

            prefs().edit().putString("dados", o.toString()).apply();
        } catch (Exception e) {
            toast("Falha ao salvar: " + e.getMessage());
        }
    }

    private String lerTexto(Uri uri) throws Exception {
        try (InputStream in = getContentResolver().openInputStream(uri)) {
            if (in == null) throw new IllegalStateException("arquivo nao abriu");
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
            String s = new String(out.toByteArray(), StandardCharsets.UTF_8);
            return s.startsWith("\uFEFF") ? s.substring(1) : s;
        }
    }
}
