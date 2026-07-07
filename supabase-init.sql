-- ============================================================
-- TREZO CLOUD — Script d'initialisation Supabase (v1)
-- À exécuter UNE FOIS dans : Supabase → SQL Editor → Run
-- ============================================================

create extension if not exists pgcrypto with schema extensions;
create extension if not exists unaccent with schema extensions;

-- Schéma privé : le secret des licences vit ici, inaccessible aux clients
create schema if not exists private;
revoke usage on schema private from public, anon, authenticated;

-- ------------------------------------------------------------
-- Tables
-- ------------------------------------------------------------
create table public.companies (
  id             uuid primary key default gen_random_uuid(),
  name           text not null,
  currency       text not null default 'XOF',
  symbol         text not null default 'FCFA',
  license_key    text,
  license_expiry timestamptz,
  is_trial       boolean not null default false,
  created_at     timestamptz not null default now()
);

create table public.memberships (
  user_id    uuid not null references auth.users(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  role       text not null default 'owner',
  primary key (user_id, company_id)
);

create table public.company_data (
  company_id uuid primary key references public.companies(id) on delete cascade,
  data       jsonb not null default '{}'::jsonb,
  version    bigint not null default 1,
  updated_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- Sécurité : RLS + droits
-- ------------------------------------------------------------
alter table public.companies    enable row level security;
alter table public.memberships  enable row level security;
alter table public.company_data enable row level security;

create or replace function public.is_member(cid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.memberships
                 where company_id = cid and user_id = auth.uid());
$$;

create policy mem_select on public.memberships
  for select using (user_id = auth.uid());
create policy co_select on public.companies
  for select using (public.is_member(id));
create policy co_update on public.companies
  for update using (public.is_member(id)) with check (public.is_member(id));
create policy cd_select on public.company_data
  for select using (public.is_member(company_id));
-- (aucune policy d'insertion/suppression : tout passe par les fonctions RPC)

revoke all on public.companies, public.memberships, public.company_data
  from anon, authenticated;
grant select on public.companies, public.memberships, public.company_data
  to authenticated;
grant update (name, currency, symbol) on public.companies to authenticated;

-- Verrou supplémentaire : les colonnes de licence ne sont modifiables
-- que par les fonctions serveur (double protection avec le grant ci-dessus)
create or replace function public.protect_license() returns trigger
language plpgsql as $$
begin
  if coalesce(current_setting('app.lic', true), '') = '1' then return new; end if;
  if new.license_key    is distinct from old.license_key
  or new.license_expiry is distinct from old.license_expiry
  or new.is_trial       is distinct from old.is_trial then
    raise exception 'license_protected';
  end if;
  return new;
end $$;
create trigger trg_protect_license
  before update on public.companies
  for each row execute function public.protect_license();

-- ------------------------------------------------------------
-- Vérification des clés TRZO (côté serveur — le secret est ICI)
-- ------------------------------------------------------------
create or replace function private.b36(t text) returns bigint
language plpgsql immutable as $$
declare r bigint := 0; d int; i int;
begin
  t := upper(t);
  for i in 1..length(t) loop
    d := position(substr(t, i, 1) in '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ') - 1;
    if d < 0 then return null; end if;
    r := r * 36 + d;
  end loop;
  return r;
end $$;

create or replace function private.check_key(p_name text, p_key text) returns timestamptz
language plpgsql stable security definer
set search_path = public, private, extensions as $$
declare
  secret text := 'TREZO-K7#2026';
  k text; m text[]; ymd text; d date;
  n1 text; n2 text; h1 text; h2 text;
begin
  k := upper(trim(coalesce(p_key, '')));
  m := regexp_match(k, '^TRZO-([0-9A-Z]{1,8})-([0-9A-F]{4})-([0-9A-F]{4})$');
  if m is null then return null; end if;
  ymd := lpad(private.b36(m[1])::text, 8, '0');
  if length(ymd) <> 8 then return null; end if;
  -- deux normalisations tolérées (accents translittérés ou supprimés)
  n1 := regexp_replace(upper(unaccent(p_name)), '[^A-Z0-9]', '', 'g');
  n2 := regexp_replace(upper(p_name), '[^A-Z0-9]', '', 'g');
  h1 := upper(encode(digest(secret || '|' || n1 || '|' || ymd, 'sha256'), 'hex'));
  h2 := upper(encode(digest(secret || '|' || n2 || '|' || ymd, 'sha256'), 'hex'));
  if not ((substr(h1,1,4) = m[2] and substr(h1,5,4) = m[3])
       or (substr(h2,1,4) = m[2] and substr(h2,5,4) = m[3])) then
    return null;
  end if;
  begin d := to_date(ymd, 'YYYYMMDD'); exception when others then return null; end;
  return (d::timestamp + interval '23 hours 59 minutes 59 seconds')::timestamptz;
end $$;

revoke all on function private.b36(text) from public, anon, authenticated;
revoke all on function private.check_key(text, text) from public, anon, authenticated;

-- ------------------------------------------------------------
-- Fonctions applicatives (RPC)
-- ------------------------------------------------------------
create or replace function public.create_company_with_license(
  p_name text, p_currency text, p_symbol text, p_key text) returns json
language plpgsql security definer set search_path = public, private, extensions as $$
declare exp timestamptz; c public.companies;
begin
  if auth.uid() is null then raise exception 'auth_required'; end if;
  if exists (select 1 from public.memberships where user_id = auth.uid()) then
    raise exception 'already_has_company';
  end if;
  exp := private.check_key(p_name, p_key);
  if exp is null then raise exception 'invalid_key'; end if;
  if exp < now() then raise exception 'expired_key'; end if;
  insert into public.companies (name, currency, symbol, license_key, license_expiry, is_trial)
    values (trim(p_name), p_currency, p_symbol, upper(trim(p_key)), exp, false)
    returning * into c;
  insert into public.memberships (user_id, company_id, role) values (auth.uid(), c.id, 'owner');
  insert into public.company_data (company_id) values (c.id);
  return row_to_json(c);
end $$;

create or replace function public.start_trial(
  p_name text, p_currency text, p_symbol text) returns json
language plpgsql security definer set search_path = public, private, extensions as $$
declare c public.companies;
begin
  if auth.uid() is null then raise exception 'auth_required'; end if;
  if exists (select 1 from public.memberships where user_id = auth.uid()) then
    raise exception 'already_has_company';
  end if;
  insert into public.companies (name, currency, symbol, license_key, license_expiry, is_trial)
    values (trim(p_name), p_currency, p_symbol, 'ESSAI', now() + interval '14 days', true)
    returning * into c;
  insert into public.memberships (user_id, company_id, role) values (auth.uid(), c.id, 'owner');
  insert into public.company_data (company_id) values (c.id);
  return row_to_json(c);
end $$;

create or replace function public.renew_license(p_company uuid, p_key text) returns timestamptz
language plpgsql security definer set search_path = public, private, extensions as $$
declare exp timestamptz; n text;
begin
  if not public.is_member(p_company) then raise exception 'not_member'; end if;
  select name into n from public.companies where id = p_company;
  exp := private.check_key(n, p_key);
  if exp is null then raise exception 'invalid_key'; end if;
  if exp < now() then raise exception 'expired_key'; end if;
  perform set_config('app.lic', '1', true);
  update public.companies
     set license_key = upper(trim(p_key)), license_expiry = exp, is_trial = false
   where id = p_company;
  return exp;
end $$;

create or replace function public.save_data(
  p_company uuid, p_data jsonb, p_version bigint) returns bigint
language plpgsql security definer set search_path = public as $$
declare e timestamptz; v bigint;
begin
  if not public.is_member(p_company) then raise exception 'not_member'; end if;
  select license_expiry into e from public.companies where id = p_company;
  if e is null or e < now() then raise exception 'license_expired'; end if;
  update public.company_data
     set data = p_data, version = version + 1, updated_at = now()
   where company_id = p_company and version = p_version
   returning version into v;
  if v is null then raise exception 'version_conflict'; end if;
  return v;
end $$;

revoke all on function public.create_company_with_license(text,text,text,text) from public, anon;
revoke all on function public.start_trial(text,text,text) from public, anon;
revoke all on function public.renew_license(uuid,text) from public, anon;
revoke all on function public.save_data(uuid,jsonb,bigint) from public, anon;
grant execute on function public.create_company_with_license(text,text,text,text) to authenticated;
grant execute on function public.start_trial(text,text,text) to authenticated;
grant execute on function public.renew_license(uuid,text) to authenticated;
grant execute on function public.save_data(uuid,jsonb,bigint) to authenticated;
grant execute on function public.is_member(uuid) to authenticated;

-- Fin. Vérifiez qu'aucune erreur n'apparaît ci-dessus.
