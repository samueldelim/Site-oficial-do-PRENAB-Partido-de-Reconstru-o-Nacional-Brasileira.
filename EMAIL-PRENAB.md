# Modelos de e-mail do Supabase (cole em Authentication → Email Templates)

Mantenha as expressões `{{ .ConfirmationURL }}` exatamente como estão: o Supabase troca pelo link de cada pessoa.

## 1) Invite user (convite para a militância)
**Assunto:** Seu convite para ser militante do PRENAB

```html
<h2>Bem-vindo(a) ao PRENAB!</h2>
<p>Sua pré-inscrição no PRENAB (Partido de Reconstrução Nacional Brasileira) foi aprovada e você foi convidado(a) para a militância.</p>
<p>Clique no botão para criar sua senha e acessar o painel:</p>
<p><a href="{{ .ConfirmationURL }}" style="background:#11a00f;color:#ffffff;padding:12px 22px;text-decoration:none;font-weight:bold;border-radius:4px;display:inline-block">Aceitar convite</a></p>
<p>Ao entrar, você vai ler e aceitar os Termos de Uso e as Regras de Conduta.</p>
<p>Se o botão não funcionar, copie e cole este endereço no navegador:<br>{{ .ConfirmationURL }}</p>
<p>Se você não fez essa pré-inscrição, ignore este e-mail.</p>
<p>Ordem, Nação e Progresso<br>PRENAB · partidoprenab@gmail.com</p>
```

## 2) Confirm signup (confirmação de conta)
**Assunto:** Confirme seu e-mail no PRENAB

```html
<h2>Confirme seu e-mail</h2>
<p>Você criou uma conta no site do PRENAB. Clique para confirmar seu e-mail:</p>
<p><a href="{{ .ConfirmationURL }}" style="background:#1f5fc1;color:#ffffff;padding:12px 22px;text-decoration:none;font-weight:bold;border-radius:4px;display:inline-block">Confirmar e-mail</a></p>
<p>Se você não criou essa conta, ignore este e-mail.</p>
<p>PRENAB · partidoprenab@gmail.com</p>
```

## 3) Reset password (redefinir senha)
**Assunto:** Redefinir sua senha do PRENAB

```html
<h2>Redefinir senha</h2>
<p>Recebemos um pedido para redefinir a senha da sua conta no PRENAB.</p>
<p><a href="{{ .ConfirmationURL }}" style="background:#1f5fc1;color:#ffffff;padding:12px 22px;text-decoration:none;font-weight:bold;border-radius:4px;display:inline-block">Criar nova senha</a></p>
<p>Se você não pediu isso, ignore este e-mail: sua senha continua a mesma.</p>
<p>PRENAB · partidoprenab@gmail.com</p>
```
