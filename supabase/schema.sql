-- IDCG Tender Management Platform - PostgreSQL / Supabase schema v1.0
-- Run only in a NEW IDCG Supabase project after reviewing the schema.
-- This script creates tables and policies; it does NOT import the 78 tender records.

create extension if not exists pgcrypto;

-- 1. Identity, roles and permissions
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  email text not null default '',
  department text,
  job_title text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.roles (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text,
  is_system boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.permissions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  module text not null,
  action text not null,
  description text
);

create table if not exists public.role_permissions (
  role_id uuid not null references public.roles(id) on delete cascade,
  permission_id uuid not null references public.permissions(id) on delete cascade,
  primary key (role_id, permission_id)
);

create table if not exists public.user_roles (
  user_id uuid not null references public.profiles(id) on delete cascade,
  role_id uuid not null references public.roles(id) on delete restrict,
  assigned_by uuid references public.profiles(id) on delete set null,
  assigned_at timestamptz not null default now(),
  primary key (user_id, role_id)
);

-- 2. Tender records
create table if not exists public.tenders (
  id uuid primary key default gen_random_uuid(),
  tender_name text not null,
  client_name text,
  tender_reference text,
  tender_value numeric(18,2),
  tender_currency char(3) not null default 'INR',
  awarded_value numeric(18,2),
  awarded_currency char(3),
  tender_date date,
  submission_deadline date,
  submitted_on date,
  decision_date date,
  status text not null default 'Draft'
    check (status in ('Draft','Under Review','Submitted','Won','Lost','Cancelled','No Bid')),
  sector text,
  contact_details text,
  notes text,
  loss_reason text,
  followed_up boolean not null default false,
  next_follow_up_at timestamptz,
  created_by uuid references public.profiles(id) on delete set null default auth.uid(),
  updated_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Exact source row retained for traceability during and after migration.
  source_record jsonb not null default '{}'::jsonb,
  import_batch_id uuid
);

create table if not exists public.tender_contributions (
  id uuid primary key default gen_random_uuid(),
  tender_id uuid not null references public.tenders(id) on delete cascade,
  contribution_type text not null check (contribution_type in
    ('am_prepared','am_reviewed','cv_prepared','cv_reviewed','submitted_by','coordinator','other')),
  employee_user_id uuid references public.profiles(id) on delete set null,
  employee_name_raw text,
  source_field text,
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists public.tender_tasks (
  id uuid primary key default gen_random_uuid(),
  tender_id uuid not null references public.tenders(id) on delete cascade,
  title text not null,
  description text,
  task_type text not null default 'follow_up',
  status text not null default 'open' check (status in ('open','in_progress','completed','cancelled')),
  due_at timestamptz,
  assigned_to uuid references public.profiles(id) on delete set null,
  created_by uuid references public.profiles(id) on delete set null default auth.uid(),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.tender_documents (
  id uuid primary key default gen_random_uuid(),
  tender_id uuid not null references public.tenders(id) on delete cascade,
  file_name text not null,
  storage_path text not null unique,
  mime_type text,
  file_size_bytes bigint,
  document_type text,
  uploaded_by uuid references public.profiles(id) on delete set null default auth.uid(),
  uploaded_at timestamptz not null default now()
);

create table if not exists public.tender_reviews (
  id uuid primary key default gen_random_uuid(),
  tender_id uuid not null references public.tenders(id) on delete cascade,
  reviewer_id uuid references public.profiles(id) on delete set null,
  review_stage text not null default 'technical',
  decision text not null check (decision in ('pending','approved','changes_requested','rejected')),
  comments text,
  reviewed_at timestamptz not null default now()
);

create table if not exists public.import_batches (
  id uuid primary key default gen_random_uuid(),
  source_file_name text not null,
  source_version text,
  source_exported_at timestamptz,
  records_received integer not null default 0,
  records_imported integer not null default 0,
  records_flagged integer not null default 0,
  imported_by uuid references public.profiles(id) on delete set null,
  imported_at timestamptz not null default now(),
  notes text
);

alter table public.tenders
  drop constraint if exists tenders_import_batch_id_fkey;
alter table public.tenders
  add constraint tenders_import_batch_id_fkey
  foreign key (import_batch_id) references public.import_batches(id) on delete set null;

create table if not exists public.audit_logs (
  id bigint generated always as identity primary key,
  actor_user_id uuid references public.profiles(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  old_data jsonb,
  new_data jsonb,
  occurred_at timestamptz not null default now()
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  message text not null,
  link_path text,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

-- 3. Indexes for common filters and relationships
create index if not exists tenders_status_idx on public.tenders(status);
create index if not exists tenders_date_idx on public.tenders(tender_date desc);
create index if not exists tenders_deadline_idx on public.tenders(submission_deadline);
create index if not exists tenders_sector_idx on public.tenders(sector);
create index if not exists tenders_client_idx on public.tenders(client_name);
create index if not exists tender_contributions_tender_idx on public.tender_contributions(tender_id);
create index if not exists tender_contributions_employee_idx on public.tender_contributions(employee_user_id);
create index if not exists tender_tasks_due_idx on public.tender_tasks(due_at) where status in ('open','in_progress');
create index if not exists tender_tasks_assignee_idx on public.tender_tasks(assigned_to);
create index if not exists tender_documents_tender_idx on public.tender_documents(tender_id);
create index if not exists audit_logs_entity_idx on public.audit_logs(entity_type, entity_id, occurred_at desc);
create index if not exists notifications_user_unread_idx on public.notifications(user_id, created_at desc) where read_at is null;

-- 4. Seed built-in roles and granular permissions
insert into public.roles (code,name,description,is_system) values
 ('super_admin','Super Admin','Full platform control, including appointment of other Super Admins.',true),
 ('admin','Admin','Manage employees, roles, tenders and platform operations.',true),
 ('employee','Employee','View shared tender records; additional permissions can be assigned.',true),
 ('viewer','Viewer','Read-only access to authorised modules.',true)
on conflict (code) do nothing;

insert into public.permissions (code,module,action,description) values
 ('tender.view','tenders','view','View tender records'),
 ('tender.create','tenders','create','Create tender records'),
 ('tender.update','tenders','update','Edit tender records'),
 ('tender.delete','tenders','delete','Delete tender records'),
 ('tender.export','tenders','export','Export tender records'),
 ('contributions.manage','team','manage','Manage tender team contributions'),
 ('tasks.manage','tasks','manage','Create and manage tender tasks'),
 ('documents.view','documents','view','View tender documents'),
 ('documents.upload','documents','upload','Upload tender documents'),
 ('documents.delete','documents','delete','Delete tender documents'),
 ('reviews.create','reviews','create','Submit tender reviews'),
 ('reviews.manage','reviews','manage','Manage review decisions'),
 ('analytics.view','analytics','view','View analytics'),
 ('users.manage','administration','users','Invite, activate, deactivate and manage users'),
 ('roles.manage','administration','roles','Create and manage custom roles and permissions'),
 ('audit.view','administration','audit','View audit history'),
 ('data.import','administration','import','Import and reconcile legacy data'),
 ('system.super_admin_assign','administration','super_admin','Assign or revoke Super Admin role')
on conflict (code) do nothing;

-- Admin receives all operational permissions except Super Admin appointment.
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r cross join public.permissions p
where r.code='admin' and p.code <> 'system.super_admin_assign'
on conflict do nothing;

-- Employee and Viewer can see shared tender information and permitted read-only modules.
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r join public.permissions p
  on p.code in ('tender.view','documents.view','analytics.view')
where r.code in ('employee','viewer')
on conflict do nothing;

-- Super Admin receives every permission.
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r cross join public.permissions p
where r.code='super_admin'
on conflict do nothing;

-- 5. Helper functions used by Row Level Security policies.
create or replace function public.is_active_user()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid()) and p.is_active = true
  );
$$;

create or replace function public.has_permission(permission_code text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.profiles p
    join public.user_roles ur on ur.user_id = p.id
    join public.role_permissions rp on rp.role_id = ur.role_id
    join public.permissions pm on pm.id = rp.permission_id
    where p.id = (select auth.uid())
      and p.is_active = true
      and pm.code = permission_code
  );
$$;

create or replace function public.has_role(role_code text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profiles p
    join public.user_roles ur on ur.user_id = p.id
    join public.roles r on r.id = ur.role_id
    where p.id = (select auth.uid()) and p.is_active = true and r.code = role_code
  );
$$;

create or replace function public.user_has_role(target_user_id uuid, role_code text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where ur.user_id = target_user_id and r.code = role_code
  );
$$;

-- 6. Updated-at and audit triggers
create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.write_audit_log()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  old_row jsonb;
  new_row jsonb;
  row_id uuid;
begin
  if tg_op = 'INSERT' then
    new_row := to_jsonb(new);
    row_id := (new_row->>'id')::uuid;
  elsif tg_op = 'UPDATE' then
    old_row := to_jsonb(old);
    new_row := to_jsonb(new);
    row_id := (new_row->>'id')::uuid;
  else
    old_row := to_jsonb(old);
    row_id := (old_row->>'id')::uuid;
  end if;
  insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,old_data,new_data)
  values (auth.uid(),tg_op, tg_table_name, row_id, old_row, new_row);
  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$;

 drop trigger if exists tenders_set_updated_at on public.tenders;
create trigger tenders_set_updated_at before update on public.tenders
for each row execute function public.set_updated_at();
drop trigger if exists tender_tasks_set_updated_at on public.tender_tasks;
create trigger tender_tasks_set_updated_at before update on public.tender_tasks
for each row execute function public.set_updated_at();
drop trigger if exists tenders_audit on public.tenders;
create trigger tenders_audit after insert or update or delete on public.tenders
for each row execute function public.write_audit_log();

-- 7. Create a profile automatically when an Auth user is created.
create or replace function public.handle_new_auth_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id,full_name,email)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name',''), coalesce(new.email,''))
  on conflict (id) do update set email=excluded.email;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute function public.handle_new_auth_user();

-- 8. Enable RLS on all application tables.
alter table public.profiles enable row level security;
alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.role_permissions enable row level security;
alter table public.user_roles enable row level security;
alter table public.tenders enable row level security;
alter table public.tender_contributions enable row level security;
alter table public.tender_tasks enable row level security;
alter table public.tender_documents enable row level security;
alter table public.tender_reviews enable row level security;
alter table public.import_batches enable row level security;
alter table public.audit_logs enable row level security;
alter table public.notifications enable row level security;

-- Remove default API grants first; then grant only required operations.
revoke all on public.profiles, public.roles, public.permissions, public.role_permissions,
 public.user_roles, public.tenders, public.tender_contributions, public.tender_tasks,
 public.tender_documents, public.tender_reviews, public.import_batches,
 public.audit_logs, public.notifications from anon, authenticated;

grant select on public.profiles, public.roles, public.permissions, public.role_permissions,
 public.user_roles, public.tenders, public.tender_contributions, public.tender_tasks,
 public.tender_documents, public.tender_reviews, public.import_batches,
 public.audit_logs, public.notifications to authenticated;

grant update on public.tenders, public.tender_tasks to authenticated;
grant update on public.profiles to authenticated;
grant insert, delete on public.tenders, public.tender_contributions, public.tender_tasks,
 public.tender_documents, public.tender_reviews, public.notifications to authenticated;
grant update on public.tender_contributions, public.tender_documents, public.tender_reviews,
 public.notifications to authenticated;
grant insert, update, delete on public.roles, public.role_permissions, public.user_roles to authenticated;
grant insert, update on public.import_batches to authenticated;

-- Profiles are created by the Auth trigger; profile status and role assignment are Admin-controlled.
create policy profiles_read_active on public.profiles for select to authenticated
using (public.is_active_user());
create policy profiles_admin_update on public.profiles for update to authenticated
using (public.has_permission('users.manage') and
  (not public.user_has_role(id,'super_admin') or public.has_permission('system.super_admin_assign')))
with check (public.has_permission('users.manage') and
  (not public.user_has_role(id,'super_admin') or public.has_permission('system.super_admin_assign')));

create policy roles_read_active on public.roles for select to authenticated
using (public.is_active_user());
create policy roles_manage_custom on public.roles for all to authenticated
using (public.has_permission('roles.manage') and
  (is_system=false or public.has_permission('system.super_admin_assign')))
with check (public.has_permission('roles.manage') and
  (is_system=false or public.has_permission('system.super_admin_assign')));
create policy permissions_read_active on public.permissions for select to authenticated
using (public.is_active_user());
create policy role_permissions_read_active on public.role_permissions for select to authenticated
using (public.is_active_user());
create policy role_permissions_manage_custom on public.role_permissions for all to authenticated
using (public.has_permission('roles.manage') and
  exists (select 1 from public.roles r where r.id=role_id and
    (r.is_system=false or public.has_permission('system.super_admin_assign'))))
with check (public.has_permission('roles.manage') and
  exists (select 1 from public.roles r where r.id=role_id and
    (r.is_system=false or public.has_permission('system.super_admin_assign'))) and
  (not exists (select 1 from public.permissions p where p.id=permission_id and p.code='system.super_admin_assign')
    or public.has_permission('system.super_admin_assign')));

create policy user_roles_read_self_or_admin on public.user_roles for select to authenticated
using (user_id=(select auth.uid()) or public.has_permission('users.manage'));
create policy user_roles_admin_insert on public.user_roles for insert to authenticated
with check (
  public.has_permission('users.manage') and
  (not exists (select 1 from public.roles r where r.id=role_id and r.code='super_admin')
   or public.has_permission('system.super_admin_assign'))
);
create policy user_roles_admin_delete on public.user_roles for delete to authenticated
using (
  public.has_permission('users.manage') and
  (not exists (select 1 from public.roles r where r.id=role_id and r.code='super_admin')
   or public.has_permission('system.super_admin_assign'))
);

create policy tenders_read on public.tenders for select to authenticated
using (public.has_permission('tender.view'));
create policy tenders_create on public.tenders for insert to authenticated
with check (public.has_permission('tender.create'));
create policy tenders_update on public.tenders for update to authenticated
using (public.has_permission('tender.update'))
with check (public.has_permission('tender.update'));
create policy tenders_delete on public.tenders for delete to authenticated
using (public.has_permission('tender.delete'));

create policy contributions_read on public.tender_contributions for select to authenticated
using (public.has_permission('tender.view'));
create policy contributions_create on public.tender_contributions for insert to authenticated
with check (public.has_permission('contributions.manage') or public.has_permission('tender.create'));
create policy contributions_update on public.tender_contributions for update to authenticated
using (public.has_permission('contributions.manage')) with check (public.has_permission('contributions.manage'));
create policy contributions_delete on public.tender_contributions for delete to authenticated
using (public.has_permission('contributions.manage'));

create policy tasks_read on public.tender_tasks for select to authenticated
using (public.has_permission('tender.view'));
create policy tasks_create on public.tender_tasks for insert to authenticated
with check (public.has_permission('tasks.manage'));
create policy tasks_update on public.tender_tasks for update to authenticated
using (public.has_permission('tasks.manage')) with check (public.has_permission('tasks.manage'));
create policy tasks_delete on public.tender_tasks for delete to authenticated
using (public.has_permission('tasks.manage'));

create policy documents_read on public.tender_documents for select to authenticated
using (public.has_permission('documents.view'));
create policy documents_create on public.tender_documents for insert to authenticated
with check (public.has_permission('documents.upload'));
create policy documents_update on public.tender_documents for update to authenticated
using (public.has_permission('documents.upload')) with check (public.has_permission('documents.upload'));
create policy documents_delete on public.tender_documents for delete to authenticated
using (public.has_permission('documents.delete'));

create policy reviews_read on public.tender_reviews for select to authenticated
using (public.has_permission('tender.view'));
create policy reviews_create on public.tender_reviews for insert to authenticated
with check (public.has_permission('reviews.create') or public.has_permission('reviews.manage'));
create policy reviews_update on public.tender_reviews for update to authenticated
using (public.has_permission('reviews.manage')) with check (public.has_permission('reviews.manage'));
create policy reviews_delete on public.tender_reviews for delete to authenticated
using (public.has_permission('reviews.manage'));

create policy import_batches_read on public.import_batches for select to authenticated
using (public.has_permission('data.import'));
create policy import_batches_create on public.import_batches for insert to authenticated
with check (public.has_permission('data.import'));
create policy import_batches_update on public.import_batches for update to authenticated
using (public.has_permission('data.import')) with check (public.has_permission('data.import'));

create policy audit_logs_read on public.audit_logs for select to authenticated
using (public.has_permission('audit.view'));
create policy notifications_read_own on public.notifications for select to authenticated
using (user_id=(select auth.uid()) and public.is_active_user());
create policy notifications_update_own on public.notifications for update to authenticated
using (user_id=(select auth.uid()) and public.is_active_user())
with check (user_id=(select auth.uid()) and public.is_active_user());
create policy notifications_create_admin on public.notifications for insert to authenticated
with check (public.has_permission('users.manage'));

-- 9. Private document bucket. Storage object policies are separate from table policies.
insert into storage.buckets(id,name,public)
values ('tender-documents','tender-documents',false)
on conflict (id) do nothing;

drop policy if exists tender_docs_read on storage.objects;
create policy tender_docs_read on storage.objects for select to authenticated
using (bucket_id='tender-documents' and public.has_permission('documents.view'));
drop policy if exists tender_docs_upload on storage.objects;
create policy tender_docs_upload on storage.objects for insert to authenticated
with check (bucket_id='tender-documents' and public.has_permission('documents.upload'));
drop policy if exists tender_docs_delete on storage.objects;
create policy tender_docs_delete on storage.objects for delete to authenticated
using (bucket_id='tender-documents' and public.has_permission('documents.delete'));

-- 10. Verification queries (run after the script)
-- select tablename, rowsecurity from pg_tables where schemaname='public' order by tablename;
-- select tablename, policyname, cmd, roles from pg_policies where schemaname='public' order by tablename,policyname;
