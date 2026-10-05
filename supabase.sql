-- =====================================================================
-- PRENAB — banco de dados, papéis e regras de segurança (RLS)
-- Supabase → SQL Editor → cole TUDO → Run. Rode UMA vez só.
-- Papéis: visitante (conta nova, sem poderes) < militante < lider_nucleo,
--         moderador < admin. Quem não fez login é "anônimo".
-- =====================================================================
create type public.app_role as enum ('visitante','militante','lider_nucleo','moderador','admin');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  nome text check (char_length(nome) <= 120),
  role public.app_role not null default 'visitante',
  uf_responsavel text check (uf_responsavel ~ '^[A-Z]{2}$'),
  created_at timestamptz not null default now()
);

-- Cria o perfil automaticamente quando alguém cria conta (sempre como visitante)
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, nome)
  values (new.id, new.email, left(coalesce(new.raw_user_meta_data->>'nome',''), 120));
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Funções auxiliares usadas nas regras (lêem o papel sem cair em loop de RLS)
create function public.my_role() returns public.app_role
language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid() $$;
create function public.my_uf() returns text
language sql stable security definer set search_path = public as $$
  select uf_responsavel from public.profiles where id = auth.uid() $$;
create function public.is_member() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.my_role() <> 'visitante', false) $$;
create function public.is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.my_role() in ('moderador','admin'), false) $$;
create function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.my_role() = 'admin', false) $$;
revoke all on function public.my_role(), public.my_uf(), public.is_member(), public.is_staff(), public.is_admin() from public, anon;
grant execute on function public.my_role(), public.my_uf(), public.is_member(), public.is_staff(), public.is_admin() to authenticated;

-- Só o admin muda papéis, e só por esta função
create function public.set_role(alvo uuid, novo public.app_role, uf text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'sem permissao'; end if;
  if alvo = auth.uid() and novo <> 'admin' then raise exception 'o admin nao pode rebaixar a si mesmo'; end if;
  if novo = 'lider_nucleo' and (uf is null or upper(uf) !~ '^[A-Z]{2}$') then raise exception 'lider de nucleo precisa de UF'; end if;
  update public.profiles
     set role = novo, uf_responsavel = case when novo = 'lider_nucleo' then upper(uf) else null end
   where id = alvo;
end $$;
revoke all on function public.set_role(uuid, public.app_role, text) from public, anon;
grant execute on function public.set_role(uuid, public.app_role, text) to authenticated;

-- ---------- PERFIS ----------
alter table public.profiles enable row level security;
revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;
grant update (nome) on public.profiles to authenticated;       -- ninguém edita o próprio papel
create policy "perfil: ver o proprio" on public.profiles for select to authenticated using (id = auth.uid());
create policy "perfil: admin ve todos" on public.profiles for select to authenticated using (public.is_admin());
create policy "perfil: editar o proprio nome" on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- ---------- PRÉ-INSCRIÇÕES ----------
create table public.inscricoes (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  nome text not null check (char_length(nome) between 3 and 120),
  email text not null check (char_length(email) <= 160 and email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  whatsapp text check (char_length(whatsapp) <= 30),
  cidade text not null check (char_length(cidade) between 2 and 80),
  uf text not null check (uf ~ '^[A-Z]{2}$'),
  consentimento boolean not null check (consentimento),
  consentimento_em timestamptz not null default now(),
  status text not null default 'novo' check (status in ('novo','em_analise','aprovado','recusado')),
  observacao text check (char_length(observacao) <= 500),
  analisado_por uuid references auth.users(id) on delete set null
);
create unique index inscricoes_email_unico on public.inscricoes (lower(email));
alter table public.inscricoes enable row level security;
revoke all on public.inscricoes from anon, authenticated;
grant insert (nome, email, whatsapp, cidade, uf, consentimento) on public.inscricoes to anon, authenticated;
grant select, delete on public.inscricoes to authenticated;
grant update (status, observacao, analisado_por) on public.inscricoes to authenticated;
create policy "inscricao: qualquer um envia" on public.inscricoes for insert to anon, authenticated
  with check (status = 'novo' and consentimento and analisado_por is null and observacao is null);
create policy "inscricao: equipe e lider da UF leem" on public.inscricoes for select to authenticated
  using (public.is_staff() or (public.my_role() = 'lider_nucleo' and uf = public.my_uf()));
create policy "inscricao: equipe e lider da UF analisam" on public.inscricoes for update to authenticated
  using (public.is_staff() or (public.my_role() = 'lider_nucleo' and uf = public.my_uf()))
  with check (public.is_staff() or (public.my_role() = 'lider_nucleo' and uf = public.my_uf()));
create policy "inscricao: so admin apaga" on public.inscricoes for delete to authenticated using (public.is_admin());
create function public.inscricoes_before_upd() returns trigger
language plpgsql security definer set search_path = public as $$
begin new.analisado_por := auth.uid(); return new; end $$;
create trigger inscricoes_before_upd before update on public.inscricoes
  for each row execute function public.inscricoes_before_upd();

-- ---------- MATÉRIAS ----------
create table public.materias (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  autor_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  autor_nome text,
  titulo text not null check (char_length(titulo) between 5 and 140),
  slug text not null unique check (slug ~ '^[a-z0-9-]{3,160}$'),
  resumo text check (char_length(resumo) <= 300),
  corpo text not null check (char_length(corpo) between 20 and 20000),
  status text not null default 'rascunho' check (status in ('rascunho','revisao','publicado','arquivado')),
  publicado_em timestamptz
);
create function public.materias_before() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.autor_id := auth.uid();
    new.autor_nome := (select nome from public.profiles where id = auth.uid());
    new.publicado_em := null;
  else
    new.autor_id := old.autor_id; new.autor_nome := old.autor_nome; new.publicado_em := old.publicado_em;
  end if;
  if new.status = 'publicado' and new.publicado_em is null then new.publicado_em := now(); end if;
  new.updated_at := now();
  return new;
end $$;
create trigger materias_before before insert or update on public.materias
  for each row execute function public.materias_before();
alter table public.materias enable row level security;
revoke all on public.materias from anon, authenticated;
grant select on public.materias to anon, authenticated;
grant insert (titulo, slug, resumo, corpo, status) on public.materias to authenticated;
grant update (titulo, slug, resumo, corpo, status) on public.materias to authenticated;
grant delete on public.materias to authenticated;
create policy "materia: todos leem as publicadas" on public.materias for select to anon, authenticated using (status = 'publicado');
create policy "materia: autor le as suas" on public.materias for select to authenticated using (autor_id = auth.uid());
create policy "materia: equipe le todas" on public.materias for select to authenticated using (public.is_staff());
create policy "materia: membro cria rascunho" on public.materias for insert to authenticated
  with check (public.is_member() and autor_id = auth.uid() and status in ('rascunho','revisao'));
create policy "materia: autor edita rascunho" on public.materias for update to authenticated
  using (public.is_member() and autor_id = auth.uid() and status in ('rascunho','revisao'))
  with check (public.is_member() and autor_id = auth.uid() and status in ('rascunho','revisao'));
create policy "materia: equipe edita e publica" on public.materias for update to authenticated
  using (public.is_staff()) with check (public.is_staff());
create policy "materia: autor apaga rascunho" on public.materias for delete to authenticated
  using (autor_id = auth.uid() and status in ('rascunho','revisao'));
create policy "materia: admin apaga" on public.materias for delete to authenticated using (public.is_admin());

-- ---------- ATUALIZAÇÕES DO SITE ----------
create table public.atualizacoes (
  id bigint generated always as identity primary key,
  data date not null default current_date,
  titulo text not null check (char_length(titulo) between 3 and 140),
  descricao text check (char_length(descricao) <= 600),
  publicado boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.atualizacoes enable row level security;
revoke all on public.atualizacoes from anon, authenticated;
grant select on public.atualizacoes to anon, authenticated;
grant insert, update, delete on public.atualizacoes to authenticated;
create policy "atualizacao: todos leem as publicadas" on public.atualizacoes for select to anon, authenticated using (publicado);
create policy "atualizacao: equipe le todas" on public.atualizacoes for select to authenticated using (public.is_staff());
create policy "atualizacao: equipe escreve" on public.atualizacoes for insert to authenticated with check (public.is_staff());
create policy "atualizacao: equipe edita" on public.atualizacoes for update to authenticated using (public.is_staff()) with check (public.is_staff());
create policy "atualizacao: equipe apaga" on public.atualizacoes for delete to authenticated using (public.is_staff());

-- =====================================================================
-- PRIMEIRO ADMIN: crie sua conta em entrar.html, confirme o e-mail e rode
-- (trocando o e-mail). Isto roda no painel do Supabase, nunca no site.
--
--   update public.profiles set role = 'admin' where email = 'SEU-EMAIL@exemplo.com';
--
-- TESTE DE SEGURANÇA (opcional): cada comando abaixo deve dar erro de permissão.
--   begin; set local role anon; select * from public.inscricoes; rollback;
--   begin; set local role anon; select * from public.profiles; rollback;
-- =====================================================================
