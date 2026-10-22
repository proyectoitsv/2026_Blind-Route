-- ═══════════════════════════════════════════════════════════════════════════
-- AJUSTES DE NAVEGACIÓN (filtros, atraso, anticipos de giro)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Correr en Supabase: SQL Editor → pegar todo → Run. Se puede volver a
-- correr: borra las políticas anteriores (también las del rol
-- "desarrollador", que se sacó) y las vuelve a crear.
--
-- Una fila por capa (ver lib/ajustes_navegacion.dart):
--   • id = 'general'            → valores para todos los edificios.
--   • id = 'edificio:<nombre>'  → valores cambiados en ese edificio.
-- `valores` guarda SÓLO los parámetros cambiados en esa capa, por clave
-- (por ejemplo {"nav_filtro_caminando_hz": 0.5}).
--
-- Permisos (los controla la nube, no la app):
--   • Leer: cualquiera, también la app del usuario sin login.
--   • Escribir (generales y edificios): cualquier admin logueado. El
--     registro público está desactivado, así que "logueado" es "admin".
--     Es así mientras se calibran los valores; después pasan al código.

create table if not exists public.ajustes_navegacion (
  id text primary key,
  valores jsonb not null default '{}'::jsonb,
  actualizado_en timestamptz not null default now()
);

alter table public.ajustes_navegacion enable row level security;

-- Políticas de la versión anterior (rol de desarrollador y dueño del
-- edificio).
drop policy if exists "Admin del edificio crea sus ajustes" on public.ajustes_navegacion;
drop policy if exists "Admin del edificio cambia sus ajustes" on public.ajustes_navegacion;
drop policy if exists "Desarrollador crea los generales" on public.ajustes_navegacion;
drop policy if exists "Desarrollador cambia los generales" on public.ajustes_navegacion;

drop policy if exists "Cualquiera lee los ajustes" on public.ajustes_navegacion;
create policy "Cualquiera lee los ajustes"
  on public.ajustes_navegacion for select
  to anon, authenticated
  using (true);

-- Subir es un upsert: necesita permiso para crear y para cambiar.
drop policy if exists "Admins crean ajustes" on public.ajustes_navegacion;
create policy "Admins crean ajustes"
  on public.ajustes_navegacion for insert
  to authenticated
  with check (id = 'general' or id like 'edificio:%');

drop policy if exists "Admins cambian ajustes" on public.ajustes_navegacion;
create policy "Admins cambian ajustes"
  on public.ajustes_navegacion for update
  to authenticated
  using (id = 'general' or id like 'edificio:%')
  with check (id = 'general' or id like 'edificio:%');
