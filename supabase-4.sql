-- =====================================================================
-- PRENAB — ATUALIZAÇÃO 4 do banco (rode DEPOIS do supabase.sql, supabase-2.sql e supabase-3.sql, uma vez)
-- Supabase → SQL Editor → cole TUDO → Run.
-- Traz: Termos de uso com aceite obrigatório, Núcleos e células (com bandeiras),
--       lista de usuários com "convite pendente" e tipos novos de notificação.
-- =====================================================================

-- 0) Novos tipos de notificação
alter table public.notificacoes drop constraint if exists notificacoes_tipo_check;
alter table public.notificacoes add constraint notificacoes_tipo_check
  check (tipo in ('inscricao','materia_revisao','materia_status','conta_nova','papel','jornal','aviso','nucleo','termos'));

-- 1) TERMOS DE USO + ACEITES
create table if not exists public.termos (
  id bigint generated always as identity primary key,
  versao text not null unique check (char_length(versao) between 1 and 20),
  titulo text not null check (char_length(titulo) between 3 and 140),
  corpo text not null check (char_length(corpo) between 50 and 30000),
  ativo boolean not null default false,
  criado_em timestamptz not null default now(),
  criado_por uuid references auth.users(id) on delete set null
);
create unique index if not exists termos_um_ativo on public.termos (ativo) where ativo;
create table if not exists public.aceites (
  user_id uuid not null references auth.users(id) on delete cascade,
  termo_id bigint not null references public.termos(id) on delete cascade,
  aceito_em timestamptz not null default now(),
  primary key (user_id, termo_id)
);
alter table public.termos enable row level security;
alter table public.aceites enable row level security;
revoke all on public.termos from anon, authenticated;
revoke all on public.aceites from anon, authenticated;
grant select on public.termos to anon, authenticated;
grant select on public.aceites to authenticated;
drop policy if exists "termos: todos leem o vigente" on public.termos;
drop policy if exists "termos: admin le todos" on public.termos;
drop policy if exists "aceites: ver os meus" on public.aceites;
drop policy if exists "aceites: admin ve todos" on public.aceites;
create policy "termos: todos leem o vigente" on public.termos for select to anon, authenticated using (ativo);
create policy "termos: admin le todos" on public.termos for select to authenticated using (public.is_admin());
create policy "aceites: ver os meus" on public.aceites for select to authenticated using (user_id = auth.uid());
create policy "aceites: admin ve todos" on public.aceites for select to authenticated using (public.is_admin());

create or replace function public.aceitou_termos() returns boolean
language sql stable security definer set search_path = public as $$
  select not exists (select 1 from public.termos where ativo)
      or exists (select 1 from public.aceites a join public.termos t on t.id = a.termo_id
                  where a.user_id = auth.uid() and t.ativo) $$;
revoke all on function public.aceitou_termos() from public, anon;
grant execute on function public.aceitou_termos() to authenticated;

create or replace function public.aceitar_termos() returns void
language plpgsql security definer set search_path = public as $$
declare t bigint;
begin
  select id into t from public.termos where ativo;
  if t is null then return; end if;
  insert into public.aceites (user_id, termo_id) values (auth.uid(), t) on conflict do nothing;
end $$;
revoke all on function public.aceitar_termos() from public, anon;
grant execute on function public.aceitar_termos() to authenticated;

create or replace function public.publicar_termos(p_versao text, p_titulo text, p_corpo text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'sem permissao'; end if;
  update public.termos set ativo = false where ativo;
  insert into public.termos (versao, titulo, corpo, ativo, criado_por)
  values (trim(p_versao), trim(p_titulo), p_corpo, true, auth.uid());
  insert into public.notificacoes (user_id, tipo, titulo, corpo, link)
  select pr.id, 'termos', 'Novos termos de uso', 'Leia e aceite a versão ' || trim(p_versao) || ' para continuar usando o painel.', 'painel:inicio'
    from public.profiles pr where pr.ativo;
  perform public.log_acao('termos', trim(p_versao), null);
end $$;
revoke all on function public.publicar_termos(text, text, text) from public, anon;
grant execute on function public.publicar_termos(text, text, text) to authenticated;

create or replace function public.termos_resumo() returns table (
  id bigint, versao text, titulo text, ativo boolean, criado_em timestamptz, aceites bigint, contas bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'sem permissao'; end if;
  return query
  select t.id, t.versao, t.titulo, t.ativo, t.criado_em,
         (select count(*) from public.aceites a where a.termo_id = t.id),
         (select count(*) from public.profiles pr where pr.ativo)
    from public.termos t order by t.id desc;
end $$;
revoke all on function public.termos_resumo() from public, anon;
grant execute on function public.termos_resumo() to authenticated;

insert into public.termos (versao, titulo, corpo, ativo)
select '1.0', 'Termos de Uso e Regras de Conduta do PRENAB', $termos$## 1. O que é este documento
Estes Termos de Uso e Regras de Conduta valem para quem usa o painel do PRENAB: militantes, líderes de núcleo, moderadores e administradores. Eles complementam o Estatuto e as Regras Internas de Conduta e Filiação, que prevalecem em caso de conflito, assim como a lei.

## 2. Natureza do projeto
O PRENAB (Partido de Reconstrução Nacional Brasileira) é um projeto político em formação e ainda não é partido registrado no TSE. Ter conta no painel ou fazer parte de um núcleo ou célula não é filiação partidária e não cria direitos eleitorais.

## 3. Conta e acesso
Você deve informar dados verdadeiros, manter sua senha em sigilo e não compartilhar sua conta. Toda conta nova começa como visitante e só ganha poderes quando um administrador aprova. O PRENAB pode suspender contas que violem estes termos.

## 4. Regras de conduta
É proibido praticar, incentivar ou divulgar preconceito ou discriminação de qualquer natureza, discurso de ódio, incitação à violência, assédio moral ou sexual, ameaças e desinformação que prejudique pessoas ou o projeto. É proibido agir contra a Constituição e a ordem democrática ou praticar crimes. Ao se manifestar em nome do PRENAB, informe apenas o que você pode sustentar. Opiniões pessoais devem ser identificadas como tais.

## 5. Símbolos e identidade
O nome, o logo e a bandeira do PRENAB só podem ser usados nas atividades do projeto e com respeito, conforme as orientações da direção. A Bandeira Nacional e os demais símbolos pátrios devem ser tratados com o respeito devido.

## 6. Vedações internas
Por opção de organização interna, não podem integrar o quadro do PRENAB pessoas ligadas a maçonaria ou a sociedades secretas, nem manter filiação simultânea a outro partido político. Essa regra não faz juízo sobre a licitude dessas sociedades, cuja liberdade de associação é garantida pela Constituição.

## 7. Matérias, fotos e conteúdo
Você é responsável pelo que escreve e envia. Só envie textos e imagens próprios ou que você tenha direito de usar, e respeite a imagem e a privacidade de terceiros. Matérias passam por revisão antes de serem publicadas, e a equipe pode devolver, editar ou arquivar o que não cumprir estes termos.

## 8. Núcleos e células
Núcleos e células são formas internas de organização do projeto e não substituem os órgãos partidários exigidos pela lei. Líderes agem em nome do PRENAB apenas dentro do que a direção autorizar. Dados de membros de um núcleo só podem ser usados para as atividades do projeto.

## 9. Privacidade
Tratamos seus dados conforme a Política de Privacidade e a Lei Geral de Proteção de Dados (Lei nº 13.709/2018). Dados sobre interesse em projeto político podem revelar opinião política e, por isso, só são tratados com o seu consentimento específico. Você pode pedir acesso, correção ou exclusão a qualquer momento.

## 10. Consequências
Quem descumprir estes termos pode receber advertência por escrito, ter a conta suspensa ou ser desligado do projeto, sempre com aviso do motivo e chance de apresentar defesa. Condutas que configurem crime podem ser comunicadas às autoridades.

## 11. Mudanças
Estes termos podem mudar. Quando houver nova versão, o painel pedirá um novo aceite antes de você continuar usando.

## 12. Contato
Dúvidas e pedidos sobre estes termos: partidoprenab@gmail.com.$termos$, true
 where not exists (select 1 from public.termos);

-- O aceite passa a ser exigido pelo banco para escrever matérias, enviar fotos e analisar pré-inscrições
drop policy if exists "materia: membro cria rascunho" on public.materias;
create policy "materia: membro cria rascunho" on public.materias for insert to authenticated
  with check (public.is_member() and public.aceitou_termos() and autor_id = auth.uid() and status in ('rascunho','revisao'));
drop policy if exists "materia: autor edita rascunho" on public.materias;
create policy "materia: autor edita rascunho" on public.materias for update to authenticated
  using (public.is_member() and public.aceitou_termos() and autor_id = auth.uid() and status in ('rascunho','revisao'))
  with check (public.is_member() and public.aceitou_termos() and autor_id = auth.uid() and status in ('rascunho','revisao'));
drop policy if exists "materias-img: enviar" on storage.objects;
create policy "materias-img: enviar" on storage.objects for insert to authenticated
  with check (bucket_id = 'materias' and (storage.foldername(name))[1] = auth.uid()::text
              and public.is_member() and public.aceitou_termos());

create or replace function public.set_inscricao_status(p_id bigint, p_status text) returns text
language plpgsql security definer set search_path = public as $$
declare i public.inscricoes; res text := 'ok';
begin
  if p_status not in ('novo','em_analise','aprovado','recusado') then raise exception 'status invalido'; end if;
  if not public.aceitou_termos() then raise exception 'aceite os termos de uso no painel'; end if;
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

-- 2) NÚCLEOS E CÉLULAS
create table if not exists public.nucleos (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  tipo text not null check (tipo in ('estadual','municipal','celula')),
  nome text not null check (char_length(nome) between 3 and 120),
  uf text not null check (uf ~ '^[A-Z]{2}$'),
  cidade text check (char_length(cidade) between 2 and 80),
  parent_id bigint references public.nucleos(id) on delete restrict,
  descricao text check (char_length(descricao) <= 500),
  ativo boolean not null default true,
  bandeira_ver bigint,
  constraint nucleos_cidade_chk check ((tipo = 'estadual' and cidade is null) or (tipo <> 'estadual' and cidade is not null))
);
create index if not exists nucleos_parent_idx on public.nucleos (parent_id);

create or replace function public.nucleos_valida() returns trigger
language plpgsql as $$
declare pt public.nucleos;
begin
  if new.parent_id is not null then
    if new.parent_id = new.id then raise exception 'a unidade nao pode ser filha de si mesma'; end if;
    select * into pt from public.nucleos where id = new.parent_id;
    if pt.uf <> new.uf then raise exception 'a unidade superior precisa ser do mesmo estado'; end if;
    if new.tipo = 'estadual' then raise exception 'unidade estadual nao tem superior'; end if;
    if new.tipo = 'municipal' and pt.tipo <> 'estadual' then raise exception 'nucleo municipal so pode ficar sob o estadual'; end if;
    if new.tipo = 'celula' and pt.tipo = 'celula' then raise exception 'celula nao pode ficar sob outra celula'; end if;
  elsif new.tipo = 'celula' then
    raise exception 'celula precisa de uma unidade superior';
  end if;
  return new;
end $$;
drop trigger if exists nucleos_valida on public.nucleos;
create trigger nucleos_valida before insert or update on public.nucleos
  for each row execute function public.nucleos_valida();

create table if not exists public.nucleo_membros (
  nucleo_id bigint not null references public.nucleos(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  papel text not null default 'membro' check (papel in ('lider','vice','secretario','membro')),
  desde timestamptz not null default now(),
  primary key (nucleo_id, user_id)
);
create table if not exists public.estados_bandeira (
  uf text primary key check (uf ~ '^[A-Z]{2}$'),
  ver bigint not null
);

alter table public.nucleos enable row level security;
alter table public.nucleo_membros enable row level security;
alter table public.estados_bandeira enable row level security;
revoke all on public.nucleos from anon, authenticated;
revoke all on public.nucleo_membros from anon, authenticated;
revoke all on public.estados_bandeira from anon, authenticated;
grant select on public.nucleos to anon, authenticated;
grant insert (tipo, nome, uf, cidade, parent_id, descricao, ativo) on public.nucleos to authenticated;
grant update (nome, cidade, parent_id, descricao, ativo, bandeira_ver) on public.nucleos to authenticated;
grant delete on public.nucleos to authenticated;
grant select on public.nucleo_membros to authenticated;
grant select on public.estados_bandeira to anon, authenticated;
grant insert, update, delete on public.estados_bandeira to authenticated;
drop policy if exists "nucleo: todos leem os ativos" on public.nucleos;
drop policy if exists "nucleo: admin le todos" on public.nucleos;
drop policy if exists "nucleo: admin cria" on public.nucleos;
drop policy if exists "nucleo: admin edita" on public.nucleos;
drop policy if exists "nucleo: admin apaga" on public.nucleos;
drop policy if exists "nucleo-membro: ver o proprio" on public.nucleo_membros;
drop policy if exists "nucleo-membro: admin ve todos" on public.nucleo_membros;
drop policy if exists "estado-bandeira: todos leem" on public.estados_bandeira;
drop policy if exists "estado-bandeira: admin escreve" on public.estados_bandeira;
drop policy if exists "estado-bandeira: admin edita" on public.estados_bandeira;
drop policy if exists "estado-bandeira: admin apaga" on public.estados_bandeira;
create policy "nucleo: todos leem os ativos" on public.nucleos for select to anon, authenticated using (ativo);
create policy "nucleo: admin le todos" on public.nucleos for select to authenticated using (public.is_admin());
create policy "nucleo: admin cria" on public.nucleos for insert to authenticated with check (public.is_admin());
create policy "nucleo: admin edita" on public.nucleos for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "nucleo: admin apaga" on public.nucleos for delete to authenticated using (public.is_admin());
create policy "nucleo-membro: ver o proprio" on public.nucleo_membros for select to authenticated using (user_id = auth.uid());
create policy "nucleo-membro: admin ve todos" on public.nucleo_membros for select to authenticated using (public.is_admin());
create policy "estado-bandeira: todos leem" on public.estados_bandeira for select to anon, authenticated using (true);
create policy "estado-bandeira: admin escreve" on public.estados_bandeira for insert to authenticated with check (public.is_admin());
create policy "estado-bandeira: admin edita" on public.estados_bandeira for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "estado-bandeira: admin apaga" on public.estados_bandeira for delete to authenticated using (public.is_admin());

-- Líder (ou vice) da unidade ou de qualquer unidade acima dela; admin sempre
create or replace function public.gerencia_nucleo(nid bigint) returns boolean
language sql stable security definer set search_path = public as $$
  with recursive up as (
    select id, parent_id from public.nucleos where id = nid
    union all
    select n.id, n.parent_id from public.nucleos n join up on n.id = up.parent_id)
  select public.is_admin() or exists (
    select 1 from public.nucleo_membros m join up on up.id = m.nucleo_id
     where m.user_id = auth.uid() and m.papel in ('lider','vice')) $$;
revoke all on function public.gerencia_nucleo(bigint) from public, anon;
grant execute on function public.gerencia_nucleo(bigint) to authenticated;

-- Árvore completa para o administrador (com líderes e total de membros)
create or replace function public.arvore_nucleos() returns table (
  id bigint, tipo text, nome text, uf text, cidade text, parent_id bigint, descricao text,
  ativo boolean, bandeira_ver bigint, total_membros bigint, lideres text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'sem permissao'; end if;
  return query
  select n.id, n.tipo, n.nome, n.uf, n.cidade, n.parent_id, n.descricao, n.ativo, n.bandeira_ver,
         (select count(*) from public.nucleo_membros m where m.nucleo_id = n.id),
         (select string_agg(coalesce(p.nome, p.email), ', ' order by p.nome)
            from public.nucleo_membros m join public.profiles p on p.id = m.user_id
           where m.nucleo_id = n.id and m.papel = 'lider')
    from public.nucleos n order by n.uf, n.cidade nulls first, n.nome;
end $$;
revoke all on function public.arvore_nucleos() from public, anon;
grant execute on function public.arvore_nucleos() to authenticated;

-- Membros de uma unidade (admin, líderes acima e os próprios membros; e-mail só para o admin)
create or replace function public.membros_do_nucleo(nid bigint) returns table (
  user_id uuid, nome text, papel text, desde timestamptz, avatar_path text, avatar_ver bigint,
  role public.app_role, email text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.gerencia_nucleo(nid) or exists (
      select 1 from public.nucleo_membros x where x.nucleo_id = nid and x.user_id = auth.uid())) then
    raise exception 'sem permissao';
  end if;
  return query
  select m.user_id, p.nome, m.papel, m.desde, p.avatar_path, p.avatar_ver, p.role,
         case when public.is_admin() then p.email end
    from public.nucleo_membros m join public.profiles p on p.id = m.user_id
   where m.nucleo_id = nid
   order by case m.papel when 'lider' then 0 when 'vice' then 1 when 'secretario' then 2 else 3 end, p.nome;
end $$;
revoke all on function public.membros_do_nucleo(bigint) from public, anon;
grant execute on function public.membros_do_nucleo(bigint) to authenticated;

create or replace function public.definir_membro_nucleo(p_nucleo bigint, p_user uuid, p_papel text) returns void
language plpgsql security definer set search_path = public as $$
declare n public.nucleos; pr public.profiles;
begin
  if not public.is_admin() then raise exception 'sem permissao'; end if;
  if p_papel not in ('lider','vice','secretario','membro') then raise exception 'papel invalido'; end if;
  select * into n from public.nucleos where id = p_nucleo;
  if not found then raise exception 'unidade nao encontrada'; end if;
  select * into pr from public.profiles where id = p_user;
  if not found then raise exception 'conta nao encontrada'; end if;
  if pr.role = 'visitante' then raise exception 'aprove a conta como militante antes'; end if;
  insert into public.nucleo_membros (nucleo_id, user_id, papel) values (p_nucleo, p_user, p_papel)
  on conflict (nucleo_id, user_id) do update set papel = excluded.papel;
  if p_papel in ('lider','vice') and pr.role = 'militante' then
    update public.profiles set role = 'lider_nucleo', uf_responsavel = n.uf where id = p_user;
  end if;
  perform public.notificar(p_user, 'nucleo', 'Você foi adicionado a ' || n.nome,
    'Seu papel na unidade: ' || p_papel, 'painel:nucleos');
  perform public.log_acao('nucleo_membro', p_nucleo::text || ':' || p_user::text, p_papel);
end $$;
revoke all on function public.definir_membro_nucleo(bigint, uuid, text) from public, anon;
grant execute on function public.definir_membro_nucleo(bigint, uuid, text) to authenticated;

create or replace function public.remover_membro_nucleo(p_nucleo bigint, p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
declare antigo text;
begin
  if not public.is_admin() then raise exception 'sem permissao'; end if;
  delete from public.nucleo_membros where nucleo_id = p_nucleo and user_id = p_user returning papel into antigo;
  if antigo in ('lider','vice')
     and not exists (select 1 from public.nucleo_membros where user_id = p_user and papel in ('lider','vice')) then
    update public.profiles set role = 'militante', uf_responsavel = null where id = p_user and role = 'lider_nucleo';
  end if;
  perform public.log_acao('nucleo_membro_remover', p_nucleo::text || ':' || p_user::text, antigo);
end $$;
revoke all on function public.remover_membro_nucleo(bigint, uuid) from public, anon;
grant execute on function public.remover_membro_nucleo(bigint, uuid) to authenticated;

-- 3) Bandeiras (estados e cidades): imagens JPEG de até 1 MB; só o admin envia
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('bandeiras', 'bandeiras', true, 1048576, array['image/jpeg'])
on conflict (id) do update set public = true, file_size_limit = 1048576, allowed_mime_types = array['image/jpeg'];
drop policy if exists "bandeiras: admin tudo" on storage.objects;
create policy "bandeiras: admin tudo" on storage.objects for all to authenticated
  using (bucket_id = 'bandeiras' and public.is_admin())
  with check (bucket_id = 'bandeiras' and public.is_admin());

-- 4) Lista de usuários para o admin, com "convite pendente" (nunca entrou)
create or replace function public.listar_usuarios() returns table (
  id uuid, email text, nome text, role public.app_role, uf_responsavel text, ativo boolean,
  avatar_path text, avatar_ver bigint, created_at timestamptz, confirmado boolean,
  ultimo_acesso timestamptz, pendente boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'sem permissao'; end if;
  return query
  select p.id, p.email, p.nome, p.role, p.uf_responsavel, p.ativo, p.avatar_path, p.avatar_ver, p.created_at,
         (u.email_confirmed_at is not null), u.last_sign_in_at, (u.last_sign_in_at is null)
    from public.profiles p left join auth.users u on u.id = p.id
   order by p.created_at desc;
end $$;
revoke all on function public.listar_usuarios() from public, anon;
grant execute on function public.listar_usuarios() to authenticated;

-- 5) Registro destas mudanças em "Atualizações" do site (só insere se ainda não existir)
insert into public.atualizacoes (data, titulo, descricao)
select '2026-10-10', v.t, v.d
  from (values
    ('Núcleos e células com bandeiras do estado e da cidade', 'Núcleos estaduais, municipais e células, com líder, membros e hierarquia. Administradores veem e editam tudo no painel.'),
    ('Termos de Uso com aceite obrigatório', 'Quem usa o painel precisa ler e aceitar os Termos de Uso e as Regras de Conduta. Nova versão exige novo aceite.'),
    ('E-mail oficial do PRENAB envia o convite', 'Ao aprovar uma pré-inscrição, o convite sai do e-mail oficial partidoprenab@gmail.com e a pessoa entra como militante.')
  ) as v(t, d)
 where not exists (select 1 from public.atualizacoes a where a.titulo = v.t);
