create extension if not exists pgcrypto;
create type public.app_role as enum ('admin','agent');
create type public.expense_note_status as enum ('draft','in_review','integration_requested','approved','rejected','reopened');

create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 first_name text not null, last_name text not null, email text not null,
 role public.app_role not null default 'agent', active boolean not null default true,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.categories (
 id uuid primary key default gen_random_uuid(), name text not null unique,
 active boolean not null default true, position integer not null default 0,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
insert into public.categories(name,position) values ('Pasti',1),('Soggiorno',2),('Rifornimento auto',3),('Parcheggi',4),('Caselli',5),('Varie',6) on conflict(name) do nothing;
create or replace function public.keep_categories() returns trigger language plpgsql as $$ begin raise exception 'Disattiva la categoria invece di eliminarla'; end $$;
create trigger categories_no_delete before delete on public.categories for each row execute procedure public.keep_categories();
create table public.expense_notes (
 id uuid primary key default gen_random_uuid(), agent_id uuid not null references public.profiles(id),
 month smallint not null check(month between 1 and 12), year smallint not null check(year between 2020 and 2100),
 status public.expense_note_status not null default 'draft', submitted_at timestamptz,
 reviewed_at timestamptz, reviewer_id uuid references public.profiles(id), review_comment text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(agent_id,month,year),
 check(status not in ('rejected','integration_requested') or length(trim(coalesce(review_comment,'')))>0)
);
create table public.expenses (
 id uuid primary key default gen_random_uuid(), note_id uuid not null references public.expense_notes(id) on delete cascade,
 expense_date date not null, category_id uuid not null references public.categories(id),
 place text not null check(length(trim(place)) between 1 and 240), description text,
 amount numeric(12,2) not null check(amount > 0), amount_in_words text not null check(length(trim(amount_in_words)) between 1 and 300),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index expenses_note_date_idx on public.expenses(note_id,expense_date desc);
create table public.expense_attachments (
 id uuid primary key default gen_random_uuid(), expense_id uuid not null references public.expenses(id) on delete cascade,
 storage_path text not null unique, original_name text not null,
 mime_type text not null check(mime_type in ('image/jpeg','image/png','application/pdf')),
 size_bytes bigint not null check(size_bytes > 0 and size_bytes <= 10485760),
 uploaded_by uuid not null references public.profiles(id), created_at timestamptz not null default now()
);
create table public.expense_reviews (
 id uuid primary key default gen_random_uuid(), note_id uuid not null references public.expense_notes(id) on delete cascade,
 reviewer_id uuid not null references public.profiles(id),
 decision public.expense_note_status not null check(decision in ('approved','rejected','integration_requested','reopened')),
 comment text, created_at timestamptz not null default now(),
 check(decision='approved' or length(trim(coalesce(comment,'')))>0)
);
create table public.audit_log (
 id bigint generated always as identity primary key, actor_id uuid references public.profiles(id),
 entity text not null, entity_id uuid, action text not null, details jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);
create index audit_log_created_idx on public.audit_log(created_at desc);
create table public.app_settings (key text primary key, value jsonb not null, updated_at timestamptz not null default now(), updated_by uuid references public.profiles(id));
insert into public.app_settings(key,value) values ('company_cars_enabled','false'::jsonb),('expense_deadline_day','"month_end"'::jsonb),('allow_late_submissions','true'::jsonb) on conflict do nothing;

create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public,auth as $$
 select exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin' and p.active)
$$;
create or replace function public.can_access_note(p_id uuid) returns boolean language sql stable security definer set search_path=public,auth as $$
 select exists(select 1 from public.expense_notes n join public.profiles p on p.id=n.agent_id where n.id=p_id and p.active and (p.id=auth.uid() or public.is_admin()))
$$;
create or replace function public.can_edit_note(p_id uuid) returns boolean language sql stable security definer set search_path=public,auth as $$
 select exists(select 1 from public.expense_notes n join public.profiles p on p.id=n.agent_id where n.id=p_id and p.active and p.id=auth.uid() and n.status in ('draft','integration_requested','reopened'))
$$;
create or replace function public.can_edit_expense(p_id uuid) returns boolean language sql stable security definer set search_path=public,auth as $$
 select exists(select 1 from public.expenses e where e.id=p_id and public.can_edit_note(e.note_id))
$$;
create or replace function public.bootstrap_profile() returns trigger language plpgsql security definer set search_path=public,auth as $$
begin insert into public.profiles(id,first_name,last_name,email) values(new.id,coalesce(new.raw_user_meta_data->>'first_name','Agente'),coalesce(new.raw_user_meta_data->>'last_name',''),new.email); return new; end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.bootstrap_profile();
create or replace function public.audit_note_status() returns trigger language plpgsql security definer set search_path=public as $$
begin
 if not public.is_admin() and auth.uid() = old.agent_id then
  if new.agent_id is distinct from old.agent_id or new.month is distinct from old.month or new.year is distinct from old.year then
   raise exception 'Agente, mese e anno della nota non sono modificabili';
  end if;
  if old.status not in ('draft','integration_requested','reopened') or new.status not in ('draft','in_review','integration_requested','reopened') then
   raise exception 'Agente non autorizzato a eseguire questa transizione';
  end if;
  if old.status='draft' and new.status not in ('draft','in_review') then raise exception 'Transizione non consentita'; end if;
  if old.status in ('integration_requested','reopened') and new.status not in (old.status,'in_review') then raise exception 'Transizione non consentita'; end if;
  if new.review_comment is distinct from old.review_comment or new.reviewer_id is distinct from old.reviewer_id or new.reviewed_at is distinct from old.reviewed_at then
   raise exception 'I campi di revisione sono riservati all’amministrazione';
  end if;
 end if;
 if new.status is distinct from old.status then
  insert into public.audit_log(actor_id,entity,entity_id,action,details) values(auth.uid(),'expense_note',new.id,'status_changed',jsonb_build_object('from',old.status,'to',new.status,'comment',new.review_comment));
  if new.status in ('approved','rejected','integration_requested') then new.reviewed_at=now(); new.reviewer_id=auth.uid(); end if;
  if new.status='in_review' then new.submitted_at=now(); end if;
 end if;
 new.updated_at=now(); return new;
end $$;
create trigger expense_note_status_audit before update on public.expense_notes for each row execute procedure public.audit_note_status();

create or replace function public.validate_expense_period() returns trigger language plpgsql as $$
declare nm smallint; ny smallint;
begin
 select n.month,n.year into nm,ny from public.expense_notes n where n.id=new.note_id;
 if nm is null or extract(month from new.expense_date)::smallint<>nm or extract(year from new.expense_date)::smallint<>ny then
  raise exception 'La data della spesa deve rientrare nel mese e anno della nota';
 end if;
 return new;
end $$;
create trigger expense_period_guard before insert or update on public.expenses for each row execute procedure public.validate_expense_period();

create or replace function public.audit_expense_change() returns trigger language plpgsql security definer set search_path=public as $$
declare eid uuid; nid uuid; act text;
begin
 eid=coalesce(new.id,old.id); nid=coalesce(new.note_id,old.note_id); act=lower(tg_op);
 insert into public.audit_log(actor_id,entity,entity_id,action,details)
 values(auth.uid(),'expense',eid,act,jsonb_build_object('note_id',nid,'amount',coalesce(new.amount,old.amount),'category_id',coalesce(new.category_id,old.category_id)));
 if tg_op='DELETE' then return old; else return new; end if;
end $$;
create trigger expenses_audit after insert or update or delete on public.expenses for each row execute procedure public.audit_expense_change();

alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.expense_notes enable row level security;
alter table public.expenses enable row level security;
alter table public.expense_attachments enable row level security;
alter table public.expense_reviews enable row level security;
alter table public.audit_log enable row level security;
alter table public.app_settings enable row level security;
create policy "profile own or admin read" on public.profiles for select to authenticated using(id=auth.uid() or public.is_admin());
create policy "admin manages profiles" on public.profiles for update to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "authenticated reads active categories" on public.categories for select to authenticated using(active or public.is_admin());
create policy "admin manages categories" on public.categories for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "agent or admin reads notes" on public.expense_notes for select to authenticated using(agent_id=auth.uid() or public.is_admin());
create policy "agent creates own note" on public.expense_notes for insert to authenticated with check(agent_id=auth.uid() and status='draft');
create policy "agent submits or edits own note" on public.expense_notes for update to authenticated using((agent_id=auth.uid() and status in ('draft','integration_requested','reopened')) or public.is_admin()) with check((agent_id=auth.uid() and status in ('draft','in_review','integration_requested','reopened')) or public.is_admin());
create policy "admin deletes notes" on public.expense_notes for delete to authenticated using(public.is_admin());
create policy "agent or admin reads expenses" on public.expenses for select to authenticated using(public.can_access_note(note_id));
create policy "agent writes editable expenses" on public.expenses for insert to authenticated with check(public.can_edit_note(note_id));
create policy "agent updates editable expenses" on public.expenses for update to authenticated using(public.can_edit_note(note_id)) with check(public.can_edit_note(note_id));
create policy "agent deletes editable expenses" on public.expenses for delete to authenticated using(public.can_edit_note(note_id));
create policy "read attachments allowed" on public.expense_attachments for select to authenticated using(public.can_access_note((select e.note_id from public.expenses e where e.id=expense_id)));
create policy "add attachment on editable expense" on public.expense_attachments for insert to authenticated with check(uploaded_by=auth.uid() and public.can_edit_expense(expense_id));
create policy "remove attachment on editable expense" on public.expense_attachments for delete to authenticated using(public.can_edit_expense(expense_id) or public.is_admin());
create policy "agent or admin reads reviews" on public.expense_reviews for select to authenticated using(public.can_access_note(note_id));
create policy "admin creates reviews" on public.expense_reviews for insert to authenticated with check(public.is_admin() and reviewer_id=auth.uid());
create policy "admin reads audit" on public.audit_log for select to authenticated using(public.is_admin());
create policy "authenticated reads settings" on public.app_settings for select to authenticated using(true);
create policy "admin manages settings" on public.app_settings for all to authenticated using(public.is_admin()) with check(public.is_admin());

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('expense-receipts','expense-receipts',false,10485760,array['image/jpeg','image/png','application/pdf']) on conflict(id) do update set public=false,file_size_limit=10485760,allowed_mime_types=array['image/jpeg','image/png','application/pdf'];
create policy "read authorized receipts" on storage.objects for select to authenticated using(bucket_id='expense-receipts' and public.can_access_note((select e.note_id from public.expenses e where e.id=(storage.foldername(name))[2]::uuid)));
create policy "upload receipts to editable expense" on storage.objects for insert to authenticated with check(bucket_id='expense-receipts' and (storage.foldername(name))[1]=auth.uid()::text and public.can_edit_expense((storage.foldername(name))[2]::uuid));
create policy "delete receipts on editable expense" on storage.objects for delete to authenticated using(bucket_id='expense-receipts' and public.can_edit_expense((storage.foldername(name))[2]::uuid));
