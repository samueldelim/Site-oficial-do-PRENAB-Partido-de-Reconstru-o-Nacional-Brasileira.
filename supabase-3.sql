-- =====================================================================
-- PRENAB — ATUALIZAÇÃO 3 do banco (rode DEPOIS do supabase.sql e do supabase-2.sql, uma vez)
-- Supabase → SQL Editor → cole TUDO → Run.
-- Traz: lista de MEMBROS aprovados (com situação da conta), notificações
-- (moderação, jornal, avisos), avisos gerais e fotos nas matérias.
-- =====================================================================

-- 0) Correção de segurança do gatilho de confirmação de e-mail (sem usar "old" em INSERT)
create or replace function public.on_user_confirmed() returns trigger
language plpgsql security definer set search_path = public as $$
declare confirmou boolean := false;
begin
  if tg_op = 'INSERT' then
    confirmou := new.email_confirmed_at is not null;
  else
    confirmou := new.email_confirmed_at is not null and old.email_confirmed_at is null;
  end if;
  if confirmou and exists (select 1 from public.inscricoes where lower(email) = lower(new.email) and status = 'aprovado') then
    update public.profiles set role = 'militante' where id = new.id and role = 'visitante';
  end if;
  return new;
end $$;

-- 1) Preferências de notificação e data de aprovação
alter table public.profiles add column if not exists notif_jornal boolean not null default true;
alter table public.profiles add column if not exists notif_moderacao boolean not null default true;
grant update (notif_jornal, notif_moderacao) on public.profiles to authenticated;
alter table public.inscricoes add column if not exists aprovado_em timestamptz;
alter table public.inscricoes disable trigger inscricoes_before_upd;
update public.inscricoes set aprovado_em = created_at where status = 'aprovado' and aprovado_em is null;
alter table public.inscricoes enable trigger inscricoes_before_upd;

create or replace function public.set_inscricao_status(p_id bigint, p_status text) returns text
language plpgsql security definer set search_path = public as $$
declare i public.inscricoes; res text := 'ok';
begin
  if p_status not in ('novo','em_analise','aprovado','recusado') then raise exception 'status invalido'; end if;
  select * into i from public.inscricoes where id = p_id;
  if not found then raise exception 'pedido nao encontrado'; end if;
  if not (public.is_staff() or (public.my_role() = 'lider_nucleo' and i.uf = public.my_uf())) then
    raise exception 'sem permissao';
  end if;
  update public.inscricoes
     set status = p_status, analisado_por = auth.uid(),
         aprovado_em = case when p_status = 'aprovado' then coalesce(aprovado_em, now()) else null end
   where id = p_id;
  if p_status = 'aprovado' then res := public.apply_approval(i.email); end if;
  perform public.log_acao('inscricao', p_id::text, p_status);
  return res;
end $$;

-- 2) MEMBROS: pré-inscrições aprovadas + situação da conta de cada uma
create or replace function public.listar_membros() returns table (
  id bigint, nome text, email text, whatsapp text, cidade text, uf text,
  aprovado_em timestamptz, conta text, papel public.app_role, user_id uuid)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_staff() or public.my_role() = 'lider_nucleo') then raise exception 'sem permissao'; end if;
  return query
  select i.id, i.nome, i.email, i.whatsapp, i.cidade, i.uf, coalesce(i.aprovado_em, i.created_at),
         case when p.id is null then 'sem_conta' when u.email_confirmed_at is null then 'nao_confirmada' else 'ativa' end,
         p.role, p.id
    from public.inscricoes i
    left join public.profiles p on lower(p.email) = lower(i.email)
    left join auth.users u on u.id = p.id
   where i.status = 'aprovado' and (public.is_staff() or i.uf = public.my_uf())
   order by coalesce(i.aprovado_em, i.created_at) desc;
end $$;
revoke all on function public.listar_membros() from public, anon;
grant execute on function public.listar_membros() to authenticated;

-- 3) NOTIFICAÇÕES (uma linha por pessoa; cada um só vê as suas)
create table if not exists public.notificacoes (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  user_id uuid not null references auth.users(id) on delete cascade,
  tipo text not null check (tipo in ('inscricao','materia_revisao','materia_status','conta_nova','papel','jornal','aviso')),
  titulo text not null,
  corpo text,
  link text,
  lida boolean not null default false
);
create index if not exists notificacoes_user_idx on public.notificacoes (user_id, lida, created_at desc);
alter table public.notificacoes enable row level security;
revoke all on public.notificacoes from anon, authenticated;
grant select, delete on public.notificacoes to authenticated;
grant update (lida) on public.notificacoes to authenticated;
drop policy if exists "notif: ver as minhas" on public.notificacoes;
drop policy if exists "notif: marcar as minhas" on public.notificacoes;
drop policy if exists "notif: apagar as minhas" on public.notificacoes;
create policy "notif: ver as minhas" on public.notificacoes for select to authenticated using (user_id = auth.uid());
create policy "notif: marcar as minhas" on public.notificacoes for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "notif: apagar as minhas" on public.notificacoes for delete to authenticated using (user_id = auth.uid());
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'notificacoes') then
    alter publication supabase_realtime add table public.notificacoes;
  end if;
end $$;

create or replace function public.notificar(p_user uuid, p_tipo text, p_titulo text, p_corpo text default null, p_link text default null) returns void
language sql security definer set search_path = public as $$
  insert into public.notificacoes (user_id, tipo, titulo, corpo, link)
  values (p_user, p_tipo, left(p_titulo, 160), left(p_corpo, 500), p_link) $$;
create or replace function public.notificar_equipe(p_tipo text, p_titulo text, p_corpo text, p_link text, p_uf text default null) returns void
language sql security definer set search_path = public as $$
  insert into public.notificacoes (user_id, tipo, titulo, corpo, link)
  select id, p_tipo, left(p_titulo, 160), left(p_corpo, 500), p_link from public.profiles
   where ativo and notif_moderacao
     and (role in ('moderador','admin') or (p_uf is not null and role = 'lider_nucleo' and uf_responsavel = p_uf)) $$;
revoke all on function public.notificar(uuid, text, text, text, text) from public, anon, authenticated;
revoke all on function public.notificar_equipe(text, text, text, text, text) from public, anon, authenticated;

-- 3a) nova pré-inscrição -> moderadores, admins e líder da UF
create or replace function public.inscricoes_notify() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.notificar_equipe('inscricao', 'Nova pré-inscrição', new.nome || ' (' || new.cidade || '/' || new.uf || ')', 'painel:inscricoes', new.uf);
  return new;
end $$;
drop trigger if exists inscricoes_notify on public.inscricoes;
create trigger inscricoes_notify after insert on public.inscricoes for each row execute function public.inscricoes_notify();

-- 3b) matérias: revisão, publicação (jornal), devolução
create or replace function public.materias_notify() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if new.status = 'revisao' then
      perform public.notificar_equipe('materia_revisao', 'Matéria aguardando revisão', new.titulo || ' — ' || coalesce(new.autor_nome, 'autor'), 'painel:revisao');
    end if;
  elsif new.status is distinct from old.status then
    if new.status = 'revisao' then
      perform public.notificar_equipe('materia_revisao', 'Matéria aguardando revisão', new.titulo || ' — ' || coalesce(new.autor_nome, 'autor'), 'painel:revisao');
    elsif new.status = 'publicado' then
      perform public.notificar(new.autor_id, 'materia_status', 'Sua matéria foi publicada', new.titulo, 'materias.html?m=' || new.slug);
      insert into public.notificacoes (user_id, tipo, titulo, corpo, link)
      select id, 'jornal', 'Novo no jornal', left(new.titulo, 160), 'materias.html?m=' || new.slug
        from public.profiles where ativo and notif_jornal and id <> new.autor_id;
    elsif new.status = 'rascunho' and old.status = 'revisao' then
      perform public.notificar(new.autor_id, 'materia_status', 'Sua matéria voltou para ajustes', new.titulo, 'painel:minhas');
    end if;
  end if;
  return new;
end $$;
drop trigger if exists materias_notify on public.materias;
create trigger materias_notify after insert or update on public.materias for each row execute function public.materias_notify();

-- 3c) conta nova -> admins; mudança de papel -> a própria pessoa
create or replace function public.profiles_notify_new() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.notificacoes (user_id, tipo, titulo, corpo, link)
  select id, 'conta_nova', 'Nova conta criada', left(coalesce(new.nome, new.email), 160), 'painel:usuarios'
    from public.profiles where role = 'admin' and ativo and notif_moderacao and id <> new.id;
  return new;
end $$;
drop trigger if exists profiles_notify_new on public.profiles;
create trigger profiles_notify_new after insert on public.profiles for each row execute function public.profiles_notify_new();

create or replace function public.profiles_notify_role() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.notificar(new.id, 'papel', 'Seu acesso mudou',
    'Seu papel agora é: ' || case new.role when 'militante' then 'Militante' when 'lider_nucleo' then 'Líder de núcleo'
      when 'moderador' then 'Moderador' when 'admin' then 'Administrador' else 'Visitante' end, 'painel:inicio');
  return new;
end $$;
drop trigger if exists profiles_notify_role on public.profiles;
create trigger profiles_notify_role after update of role on public.profiles
  for each row when (old.role is distinct from new.role) execute function public.profiles_notify_role();

-- 4) AVISOS GERAIS IMPORTANTES
create table if not exists public.avisos (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  autor_id uuid default auth.uid() references auth.users(id) on delete set null,
  titulo text not null check (char_length(titulo) between 3 and 140),
  corpo text check (char_length(corpo) <= 1000),
  nivel text not null default 'importante' check (nivel in ('info','importante','urgente')),
  publico boolean not null default false,
  ativo boolean not null default true,
  expira_em timestamptz
);
alter table public.avisos enable row level security;
revoke all on public.avisos from anon, authenticated;
grant select on public.avisos to anon, authenticated;
grant insert (titulo, corpo, nivel, publico, expira_em) on public.avisos to authenticated;
grant update (titulo, corpo, nivel, publico, ativo, expira_em) on public.avisos to authenticated;
grant delete on public.avisos to authenticated;
drop policy if exists "aviso: publico le os do site" on public.avisos;
drop policy if exists "aviso: logados leem os ativos" on public.avisos;
drop policy if exists "aviso: equipe le todos" on public.avisos;
drop policy if exists "aviso: equipe cria" on public.avisos;
drop policy if exists "aviso: equipe edita" on public.avisos;
drop policy if exists "aviso: equipe apaga" on public.avisos;
create policy "aviso: publico le os do site" on public.avisos for select to anon, authenticated
  using (publico and ativo and (expira_em is null or expira_em > now()));
create policy "aviso: logados leem os ativos" on public.avisos for select to authenticated
  using (ativo and (expira_em is null or expira_em > now()));
create policy "aviso: equipe le todos" on public.avisos for select to authenticated using (public.is_staff());
create policy "aviso: equipe cria" on public.avisos for insert to authenticated with check (public.is_staff());
create policy "aviso: equipe edita" on public.avisos for update to authenticated using (public.is_staff()) with check (public.is_staff());
create policy "aviso: equipe apaga" on public.avisos for delete to authenticated using (public.is_staff());

create or replace function public.avisos_notify() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.notificacoes (user_id, tipo, titulo, corpo, link)
  select id, 'aviso', case new.nivel when 'urgente' then 'URGENTE: ' when 'importante' then 'Importante: ' else '' end || new.titulo,
         left(new.corpo, 500), 'painel:notificacoes'
    from public.profiles where ativo;
  return new;
end $$;
drop trigger if exists avisos_notify on public.avisos;
create trigger avisos_notify after insert on public.avisos for each row execute function public.avisos_notify();

-- 5) FOTOS NAS MATÉRIAS: capa + imagens dentro do texto
alter table public.materias add column if not exists capa_path text;
alter table public.materias add column if not exists capa_legenda text check (char_length(capa_legenda) <= 200);
alter table public.materias drop constraint if exists materias_capa_chk;
alter table public.materias add constraint materias_capa_chk
  check (capa_path is null or capa_path ~ '^[0-9a-f-]{36}/[a-z0-9-]+\.(jpg|png|webp)$');
grant insert (capa_path, capa_legenda) on public.materias to authenticated;
grant update (capa_path, capa_legenda) on public.materias to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('materias', 'materias', true, 1572864, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = true, file_size_limit = 1572864, allowed_mime_types = array['image/jpeg','image/png','image/webp'];
drop policy if exists "materias-img: ler" on storage.objects;
drop policy if exists "materias-img: enviar" on storage.objects;
drop policy if exists "materias-img: apagar" on storage.objects;
create policy "materias-img: ler" on storage.objects for select to authenticated
  using (bucket_id = 'materias' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_staff()));
create policy "materias-img: enviar" on storage.objects for insert to authenticated
  with check (bucket_id = 'materias' and (storage.foldername(name))[1] = auth.uid()::text and public.is_member());
create policy "materias-img: apagar" on storage.objects for delete to authenticated
  using (bucket_id = 'materias' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_staff()));

-- 6) Números da visão geral (agora com aprovados sem conta)
create or replace function public.resumo() returns json
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_member() then return null; end if;
  return json_build_object(
    'inscricoes_novas', case when public.is_staff() or public.my_role() = 'lider_nucleo'
      then (select count(*) from public.inscricoes where status = 'novo' and (public.is_staff() or uf = public.my_uf())) end,
    'aprovados_sem_conta', case when public.is_staff() or public.my_role() = 'lider_nucleo'
      then (select count(*) from public.inscricoes i where i.status = 'aprovado' and (public.is_staff() or i.uf = public.my_uf())
              and not exists (select 1 from public.profiles p where lower(p.email) = lower(i.email))) end,
    'materias_revisao', case when public.is_staff() then (select count(*) from public.materias where status = 'revisao') end,
    'visitantes', case when public.is_admin() then (select count(*) from public.profiles where role = 'visitante') end,
    'militantes', case when public.is_admin() then (select count(*) from public.profiles where role <> 'visitante') end,
    'minhas_materias', (select count(*) from public.materias where autor_id = auth.uid())
  );
end $$;
