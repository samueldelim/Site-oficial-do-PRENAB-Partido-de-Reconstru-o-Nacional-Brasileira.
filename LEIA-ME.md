# Site do PRENAB — arquivos para o GitHub Pages

## Como publicar
1. Envie **todos** os arquivos desta pasta para a raiz do repositório, não só o `index.html` (inclusive `.nojekyll` e a pasta `.github`).
2. Em Settings → Pages, escolha "Deploy from a branch" → `main` → **`/ (root)`**.
3. Espere 1 a 3 minutos e abra o endereço do site.

## Estrutura
- `index.html` é a página inicial; cada aba é um arquivo HTML próprio. Cada página já leva o visual e os scripts dentro dela.
- **Painel (login, matérias, inscrições):** `entrar.html`, `painel.html`, `inscricao.html`, `materias.html`, `privacidade.html`, `config.js` e `supabase.sql`. Para ativar, siga o **LEIA-ME-PAINEL.md**. Sem isso, essas páginas mostram "recurso ainda não ativado".
- `sitemap.xml`, `robots.txt`, `404.html` e `search.json` ajudam buscadores e a busca interna.

## Se o endereço mudar
O endereço do site aparece em `sitemap.xml`, `robots.txt` e nas tags `canonical` e `og:`. Faça "localizar e substituir" de
`https://samueldelim.github.io/Site-oficial-do-PRENAB-Partido-de-Reconstru-o-Nacional-Brasileira./`
pelo novo endereço, em todos os arquivos.

## Google (Search Console)
1. A tag `google-site-verification` já está em todas as páginas. Clique em "Verificar".
2. Envie o `sitemap.xml` e peça indexação das páginas principais em "Inspeção de URL".
3. Ponha o endereço do site no blog, no Linktree e na bio do TikTok.
