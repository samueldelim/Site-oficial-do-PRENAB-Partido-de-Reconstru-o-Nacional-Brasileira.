-- =====================================================================
-- PRENAB — ATUALIZAÇÃO 2 do banco (rode DEPOIS do supabase.sql, uma vez)
-- Supabase → SQL Editor → cole TUDO → Run.
-- Traz: aprovar pré-inscrição = virar militante, foto de perfil,
--       suspender usuários, auditoria e resumo do painel.
-- =====================================================================

-- 1) Novas colunas do perfil
alter table public.profiles add column if not exists ativo boolean not null default true;
alter table public.profiles add column if not exists avatar_path text;
alter table public.profiles add column if not exists avatar_ver bigint not null default 0;
alter table public.profiles drop constraint if exists profiles_avatar_chk;
alter table public.profiles add constraint profiles_avatar_chk
  check (avatar_path is null or avatar_path = id::text || '/avatar.jpg');
grant update (nome, avatar_path, avatar_ver) on public.profiles to authenticated;

-- 2) Conta suspensa perde todos os poderes (vira visitante)
create or replace function public.my_role() returns public.app_role
language sql stable security definer set search_path = public as $$
  select case when ativo then role else 'visitante'::public.app_role end
    from public.profiles where id = auth.uid() $$;

-- 3) Auditoria (só o admin lê)
create table if not exists public.auditoria (
  id bigint generated always as identity primary key,
  quando timestamptz not null default now(),
  ator_id uuid,
  ator_email text,
  acao text not null,
  alvo text,
  detalhe text
);
alter table public.auditoria enable row level security;
revoke all on public.auditoria from anon, authenticated;
grant select on public.auditoria to authenticated;
drop policy if exists "auditoria: admin le" on public.auditoria;
create policy "auditoria: admin le" on public.auditoria for select to authenticated using (public.is_admin());

create or replace function public.log_acao(acao text, alvo text, detalhe text default null) returns void
language sql security definer set search_path = public as $$
  insert into public.auditoria (ator_id, ator_email, acao, alvo, detalhe)
  values (auth.uid(), (select email from public.profiles where id = auth.uid()), acao, alvo, detalhe) $$;
revoke all on function public.log_acao(text, text, text) from public, anon, authenticated;

-- 4) Aprovar pré-inscrição => a conta com o mesmo e-mail (confirmado) vira militante
create or replace function public.apply_approval(p_email text) returns text
language plpgsql security definer set search_path = public as $$
declare r public.app_role;
begin
  select p.role into r from public.profiles p join auth.users u on u.id = p.id
   where lower(p.email) = lower(p_email) and u.email_confirmed_at is not null limit 1;
  if not found then return 'sem_conta'; end if;
  if r = 'visitante' then
    update public.profiles p set role = 'militante'
      from auth.users u
     where u.id = p.id and u.email_confirmed_at is not null
       and lower(p.email) = lower(p_email) and p.role = 'visitante';
    return 'promovido';
  end if;
  return 'ja_membro';
end $$;
revoke all on function public.apply_approval(text) from public, anon, authenticated;

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
  update public.inscricoes set status = p_status, analisado_por = auth.uid() where id = p_id;
  if p_status = 'aprovado' then res := public.apply_approval(i.email); end if;
  perform public.log_acao('inscricao', p_id::text, p_status);
  return res;
end $$;
revoke all on function public.set_inscricao_status(bigint, text) from public, anon;
grant execute on function public.set_inscricao_status(bigint, text) to authenticated;

-- Quem criar a conta DEPOIS da aprovação vira militante ao confirmar o e-mail
create or replace function public.on_user_confirmed() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.email_confirmed_at is not null and (tg_op = 'INSERT' or old.email_confirmed_at is null) then
    if exists (select 1 from public.inscricoes where lower(email) = lower(new.email) and status = 'aprovado') then
      update public.profiles set role = 'militante' where id = new.id and role = 'visitante';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists zz_user_confirmed_ins on auth.users;
drop trigger if exists zz_user_confirmed_upd on auth.users;
create trigger zz_user_confirmed_ins after insert on auth.users for each row execute function public.on_user_confirmed();
create trigger zz_user_confirmed_upd after update of email_confirmed_at on auth.users for each row execute function public.on_user_confirmed();

-- Já aprovadas antes desta atualização: promove as contas confirmadas
update public.profiles p set role = 'militante'
  from auth.users u, public.inscricoes i
 where u.id = p.id and u.email_confirmed_at is not null
   and lower(i.email) = lower(p.email) and i.status = 'aprovado' and p.role = 'visitante';

-- 5) Papéis e suspensão (com auditoria)
create or replace function public.set_role(alvo uuid, novo public.app_role, uf text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'sem permissao'; end if;
  if alvo = auth.uid() and novo <> 'admin' then raise exception 'o admin nao pode rebaixar a si mesmo'; end if;
  if novo = 'lider_nucleo' and (uf is null or upper(uf) !~ '^[A-Z]{2}$') then raise exception 'lider de nucleo precisa de UF'; end if;
  update public.profiles
     set role = novo, uf_responsavel = case when novo = 'lider_nucleo' then upper(uf) else null end
   where id = alvo;
  perform public.log_acao('papel', alvo::text, novo::text);
end $$;

create or replace function public.set_user_active(alvo uuid, ligado boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'sem permissao'; end if;
  if alvo = auth.uid() then raise exception 'voce nao pode suspender a si mesmo'; end if;
  update public.profiles set ativo = ligado where id = alvo;
  perform public.log_acao(case when ligado then 'reativar' else 'suspender' end, alvo::text, null);
end $$;
revoke all on function public.set_user_active(uuid, boolean) from public, anon;
grant execute on function public.set_user_active(uuid, boolean) to authenticated;

-- 6) Registros automáticos na auditoria
create or replace function public.materias_audit() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status then perform public.log_acao('materia', new.id::text, new.status); end if;
  return new;
end $$;
drop trigger if exists materias_audit on public.materias;
create trigger materias_audit after update on public.materias for each row execute function public.materias_audit();

create or replace function public.inscricoes_audit_del() returns trigger
language plpgsql security definer set search_path = public as $$
begin perform public.log_acao('inscricao_excluida', old.id::text, null); return old; end $$;
drop trigger if exists inscricoes_audit_del on public.inscricoes;
create trigger inscricoes_audit_del after delete on public.inscricoes for each row execute function public.inscricoes_audit_del();

-- 7) Números da visão geral (cada papel só recebe o que pode ver)
create or replace function public.resumo() returns json
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_member() then return null; end if;
  return json_build_object(
    'inscricoes_novas', case when public.is_staff() or public.my_role() = 'lider_nucleo'
      then (select count(*) from public.inscricoes where status = 'novo' and (public.is_staff() or uf = public.my_uf())) end,
    'materias_revisao', case when public.is_staff() then (select count(*) from public.materias where status = 'revisao') end,
    'visitantes', case when public.is_admin() then (select count(*) from public.profiles where role = 'visitante') end,
    'militantes', case when public.is_admin() then (select count(*) from public.profiles where role <> 'visitante') end,
    'minhas_materias', (select count(*) from public.materias where autor_id = auth.uid())
  );
end $$;
revoke all on function public.resumo() from public, anon;
grant execute on function public.resumo() to authenticated;

-- 8) Foto de perfil (Storage): 1 arquivo JPEG por pessoa, até 512 KB
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 524288, array['image/jpeg'])
on conflict (id) do update set public = true, file_size_limit = 524288, allowed_mime_types = array['image/jpeg'];
drop policy if exists "avatar: ler o proprio" on storage.objects;
drop policy if exists "avatar: enviar o proprio" on storage.objects;
drop policy if exists "avatar: trocar o proprio" on storage.objects;
drop policy if exists "avatar: apagar o proprio" on storage.objects;
create policy "avatar: ler o proprio" on storage.objects for select to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "avatar: enviar o proprio" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "avatar: trocar o proprio" on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "avatar: apagar o proprio" on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
