-- Migration: Enable RLS and create policies for pricing_settings table
-- Date: 2025-01-13
-- Purpose: Fix security warning about RLS being disabled on public.pricing_settings table

-- 1) Enable RLS (idempotent)
alter table if exists public.pricing_settings enable row level security;
alter table if exists public.pricing_settings force row level security;

-- 2) SELECT-Policy (authenticated: admin + teacher)
do $$
begin
  if not exists (
    select 1 from pg_policies
    where policyname = 'pricing_settings_select_authenticated'
      and tablename = 'pricing_settings'
      and schemaname = 'public'
  ) then
    create policy pricing_settings_select_authenticated
    on public.pricing_settings
    for select
    to authenticated
    using (
      -- Least-Privilege: nur eingeloggte User (RLS greift; Rolle egal)
      current_setting('request.jwt.claims', true) is not null
      and coalesce(public.get_user_role(), 'teacher') in ('admin','teacher')
    );
  end if;
end$$;

-- 3) INSERT nur Admin
do $$
begin
  if not exists (
    select 1 from pg_policies
    where policyname = 'pricing_settings_insert_admin'
      and tablename = 'pricing_settings'
      and schemaname = 'public'
  ) then
    create policy pricing_settings_insert_admin
    on public.pricing_settings
    for insert
    to authenticated
    with check (public.get_user_role() = 'admin');
  end if;
end$$;

-- 4) UPDATE nur Admin
do $$
begin
  if not exists (
    select 1 from pg_policies
    where policyname = 'pricing_settings_update_admin'
      and tablename = 'pricing_settings'
      and schemaname = 'public'
  ) then
    create policy pricing_settings_update_admin
    on public.pricing_settings
    for update
    to authenticated
    using (public.get_user_role() = 'admin')
    with check (public.get_user_role() = 'admin');
  end if;
end$$;

-- 5) DELETE nur Admin
do $$
begin
  if not exists (
    select 1 from pg_policies
    where policyname = 'pricing_settings_delete_admin'
      and tablename = 'pricing_settings'
      and schemaname = 'public'
  ) then
    create policy pricing_settings_delete_admin
    on public.pricing_settings
    for delete
    to authenticated
    using (public.get_user_role() = 'admin');
  end if;
end$$;

-- 6) Optional: Schreibschutz für Systemspalten, falls vorhanden
-- Beispiel: updated_at via trigger setzen (nur wenn Spalte existiert)
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='pricing_settings' and column_name='updated_at'
  ) then
    create or replace function public.set_updated_at()
    returns trigger
    language plpgsql
    security definer
    as $fn$
    begin
      new.updated_at := now();
      return new;
    end;
    $fn$;

    if not exists (
      select 1 from pg_trigger
      where tgname = 'trg_pricing_settings_set_updated_at'
    ) then
      create trigger trg_pricing_settings_set_updated_at
      before update on public.pricing_settings
      for each row execute function public.set_updated_at();
    end if;
  end if;
end$$;

-- Rollback-Hinweis:
--  - Policies entfernen: drop policy ... on public.pricing_settings;
--  - RLS ausschalten (nicht empfohlen): alter table public.pricing_settings disable row level security;
