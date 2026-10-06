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
2b. **Atualização 2:** em uma nova query, cole todo o `supabase-2.sql` e clique em **Run**. Ela traz: aprovar pré-inscrição = a conta vira militante, foto de perfil, suspender usuários, auditoria e os números da visão geral. Se você já rodou o `supabase.sql` antes, rode só este arquivo.
2c. **Atualização 3:** em outra nova query, cole todo o `supabase-3.sql` e clique em **Run**. Ela traz: lista de **Membros aprovados**, notificações (sino 🔔), avisos gerais e fotos nas matérias.
3. **Project Settings → API**: copie a *Project URL* e a *Publishable key* (`sb_publishable_...`) e cole em `config.js`. Se seu projeto só mostra a chave `anon` antiga, ela também funciona por enquanto, mas a Supabase vai aposentá-la até o fim de 2026.
4. **Authentication → URL Configuration**: em *Site URL* ponha o endereço do site e adicione o mesmo endereço em *Redirect URLs*. Em **Authentication → Providers → Email**, mantenha "Confirm email" ligado.
5. Envie os arquivos para o GitHub (inclusive `config.js` preenchido).
6. Abra `entrar.html`, crie **sua** conta e confirme o e-mail.
7. No **SQL Editor**, rode uma vez (com o seu e-mail): `update public.profiles set role = 'admin' where email = 'SEU-EMAIL@exemplo.com';`
8. Entre de novo e abra `painel.html`. Na aba **Usuários** você promove as outras pessoas. Quem cria conta entra como *visitante*.
9. **Teste de segurança**: rode os comandos comentados no fim do `supabase.sql`. Todos precisam dar erro de permissão. Teste também com outra conta de militante: ela não pode ver Inscrições nem Usuários.

## Se o painel não abrir
- **Mensagem "Seu perfil ainda não existe no banco":** a conta foi criada antes de você rodar o `supabase.sql`. No SQL Editor rode o bloco "CONTA CRIADA ANTES..." do fim do arquivo e depois o `update ... role = 'admin'`.
- **Mensagem "Não foi possível carregar" / "tempo esgotado":** clique em "Limpar sessão e entrar de novo". Se repetir, abra o site numa janela anônima e veja o console (F12) para o erro.
- **"Recurso ainda não ativado":** o `config.js` está com os textos "COLE_AQUI" ou o script do Supabase não carregou (internet/bloqueador).
- **Login diz e-mail ou senha incorretos:** confirme o e-mail pelo link que o Supabase enviou (olhe o spam).

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

## Se algo não funcionar
- **Painel mostra erro em vez de carregar:** a mensagem diz o motivo. Se citar "function does not exist" ou "column", falta rodar o `supabase-2.sql`.
- **Aprovei uma pré-inscrição e a pessoa "não aparece":** pré-inscrição não é conta. Quem foi aprovado aparece em **Pessoas → Membros aprovados**, com a situação da conta (sem conta, e-mail não confirmado ou conta ativa). Só entra em **Usuários** quando criar a conta. Use "Copiar convite" ou "WhatsApp" para chamar a pessoa.
- **Aprovei uma pré-inscrição e a pessoa não virou militante:** a conta precisa existir **com o mesmo e-mail** e ter o e-mail **confirmado**. Se ainda não existe, ela vira militante sozinha ao criar a conta e confirmar. O aviso na tela diz qual caso aconteceu.
- **Foto não envia:** confirme que o `supabase-2.sql` rodou (ele cria o espaço de fotos `avatars`).
- **Conta suspensa:** o administrador pode reativar em Usuários. A pessoa suspensa volta a ser tratada como visitante.
- **Notificações não chegam ao vivo:** confirme que o `supabase-3.sql` rodou sem erro. Em Database → Replication, a tabela `notificacoes` deve estar ativa para o Realtime.
- **Foto da matéria não envia:** o `supabase-3.sql` cria o espaço `materias` (máx. 1,5 MB por imagem; o site reduz a imagem antes de enviar).
- **Faixa de aviso no site público não aparece:** marque "Mostrar também como faixa no site público" ao criar o aviso e confira se o `config.js` está preenchido.
