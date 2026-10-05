# Painel do PRENAB: login, papéis, pré-inscrições e matérias

## Por que não existe senha no código
O GitHub Pages só entrega arquivos. Qualquer login "feito só no JavaScript" pode ser lido e burlado por quem abrir o código, **por isso nenhuma senha, e-mail de admin ou chave secreta está nos arquivos**. O login é feito pelo **Supabase** (banco de dados + autenticação, plano gratuito):
- O que fica no GitHub é só a **URL** e a **chave pública** (`sb_publishable_...`) do projeto. Elas são públicas por desenho, como a Supabase documenta, e só abrem o que as regras do banco permitem.
- As regras (RLS) estão no `supabase.sql`. É elas que decidem quem lê e escreve, não o JavaScript da página. O papel de cada pessoa fica no banco, e ninguém consegue alterar o próprio papel.
- **A única chave que nunca pode aparecer** é a `secret` / `service_role`. Ela não é usada em nenhum arquivo deste site.

## Papéis
| Papel | Pode |
|---|---|
| Anônimo | Ler matérias e atualizações publicadas; enviar pré-inscrição |
| Visitante | Criou conta, mas ainda sem poderes (aguarda aprovação) |
| Militante | Escrever matérias e enviar para revisão; editar os próprios rascunhos |
| Líder de núcleo | Tudo do militante + ver e analisar as pré-inscrições **só da sua UF** |
| Moderador | Tudo do militante + publicar/devolver/arquivar matérias, ver todas as pré-inscrições, gerir atualizações do site |
| Administrador | Tudo + mudar papéis, excluir matérias e pré-inscrições (pedido de exclusão LGPD) |

## Passo a passo
1. Crie conta em supabase.com e um projeto novo (região **South America (São Paulo)**). Guarde a senha do banco em lugar seguro.
2. No projeto: **SQL Editor → New query**, cole todo o `supabase.sql` e clique em **Run**.
3. **Project Settings → API**: copie a *Project URL* e a *Publishable key* (`sb_publishable_...`) e cole em `config.js`. Se seu projeto só mostra a chave `anon` antiga, ela também funciona por enquanto, mas a Supabase vai aposentá-la até o fim de 2026.
4. **Authentication → URL Configuration**: em *Site URL* ponha o endereço do site e adicione o mesmo endereço em *Redirect URLs*. Em **Authentication → Providers → Email**, mantenha "Confirm email" ligado.
5. Envie os arquivos para o GitHub (inclusive `config.js` preenchido).
6. Abra `entrar.html`, crie **sua** conta e confirme o e-mail.
7. No **SQL Editor**, rode uma vez (com o seu e-mail): `update public.profiles set role = 'admin' where email = 'SEU-EMAIL@exemplo.com';`
8. Entre de novo e abra `painel.html`. Na aba **Usuários** você promove as outras pessoas. Quem cria conta entra como *visitante*.
9. **Teste de segurança**: rode os comandos comentados no fim do `supabase.sql`. Todos precisam dar erro de permissão. Teste também com outra conta de militante: ela não pode ver Inscrições nem Usuários.

## Cuidados
- **LGPD:** nome, contato e interesse num projeto político são dados pessoais, e opinião política é dado **sensível** (art. 5º, II). A lei exige consentimento **específico e destacado** (art. 11, I), que o formulário já traz. Preencha o contato do responsável na `privacidade.html` e revise o texto com advogado. Colete só o necessário e apague quando a pessoa pedir.
- **Antes do registro no TSE** o PRENAB não tem filiados: o formulário é de **pré-inscrição/interesse**. Não chame de "filiação".
- **Senhas:** use senha longa e única no Supabase, no GitHub e nas contas de admin. Ative a verificação em duas etapas no GitHub e no Supabase.
- **E-mails de confirmação:** o envio embutido do Supabase é muito limitado (poucos e-mails por hora). Antes de divulgar o cadastro, configure um SMTP próprio em *Authentication → SMTP*.
- **Projeto pausado:** no plano gratuito o projeto pausa após 7 dias sem uso. O arquivo `.github/workflows/keepalive.yml` faz um ping a cada 3 dias. Crie os *secrets* `SUPABASE_URL` e `SUPABASE_KEY` em Settings → Secrets and variables → Actions. O GitHub desativa agendamentos em repositórios parados por 60 dias.
- **Backup:** o plano gratuito não permite baixar backups. Use o botão "Baixar CSV" das inscrições de tempos em tempos.
- **Anti-spam:** o formulário tem um campo-armadilha e limites de tamanho. Se houver ataque, adicione um CAPTCHA (Cloudflare Turnstile é gratuito).
- **Google:** as matérias carregam por JavaScript, então o Google pode demorar a indexá-las. As páginas principais continuam em HTML puro.
- Os scripts do Supabase vêm do CDN jsDelivr (versão 2). Se quiser mais controle, baixe o arquivo e hospede junto.
