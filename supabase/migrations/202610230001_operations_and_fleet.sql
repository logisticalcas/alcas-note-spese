-- Estensioni operative: anagrafica agenti, massimali, rappresentanza e report carburante.
alter table public.categories add column if not exists is_representation boolean not null default false;
insert into public.categories(name,position,is_representation)
values('Spese di Rappresentanza (Ospiti)',7,true) on conflict(name) do update set is_representation=true;
alter table public.expenses add column if not exists guests jsonb not null default '[]'::jsonb;
alter table public.expenses add column if not exists payment_method text not null default 'personale' check(payment_method in ('personale','carta_aziendale'));
alter table public.expenses add column if not exists card_reference text;
create or replace function public.validate_expense_details() returns trigger language plpgsql security definer set search_path=public as $$
declare rep boolean;
begin
 select is_representation into rep from public.categories where id=new.category_id;
 if rep and (jsonb_typeof(new.guests)<>'array' or jsonb_array_length(new.guests)=0 or exists(select 1 from jsonb_array_elements(new.guests) as guest(value) where nullif(trim(value->>'name'),'') is null or nullif(trim(value->>'role'),'') is null or nullif(trim(value->>'company'),'') is null)) then
  raise exception 'Per le spese di rappresentanza indica nome, ruolo e azienda di ogni ospite';
 end if;
 return new;
end $$;
create trigger expense_representation_guard before insert or update on public.expenses for each row execute procedure public.validate_expense_details();

create table public.employee_directory (
 id uuid primary key default gen_random_uuid(),
 profile_id uuid unique references public.profiles(id) on delete set null,
 first_name text not null, last_name text not null, email text,
 active boolean not null default true, employee_code text unique,
 notes text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
insert into public.employee_directory(first_name,last_name,employee_code) values
 ('Fabio','Scognamiglio','AG-001'),('Emanuele','Santaniello','AG-002'),('Gianluca','Giordano','AG-003')
on conflict(employee_code) do update set first_name=excluded.first_name,last_name=excluded.last_name;

create table public.vehicles (
 id uuid primary key default gen_random_uuid(), plate text unique,
 make text, model text, fuel_type text, assigned_employee_id uuid references public.employee_directory(id),
 active boolean not null default true, notes text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
insert into public.vehicles(assigned_employee_id,notes)
select id,'Veicolo aziendale assegnato; completare targa, marca e modello dalle impostazioni admin.'
from public.employee_directory e where not exists(select 1 from public.vehicles v where v.assigned_employee_id=e.id and v.active);

insert into public.app_settings(key,value) values
 ('meal_daily_cap','60.00'::jsonb),('lodging_nightly_cap','150.00'::jsonb),
 ('company_cars_enabled','true'::jsonb),('fuel_weekly_deadline','{"day":"monday","time":"13:00"}'::jsonb),
 ('fuel_month_catchup_days','7'::jsonb),('expense_retention_years','10'::jsonb)
on conflict(key) do update set value=excluded.value;

create or replace function public.bootstrap_profile() returns trigger language plpgsql security definer set search_path=public,auth as $$
declare eid uuid;
begin
 eid=nullif(new.raw_user_meta_data->>'employee_id','')::uuid;
 insert into public.profiles(id,first_name,last_name,email)
 values(new.id,coalesce(new.raw_user_meta_data->>'first_name','Agente'),coalesce(new.raw_user_meta_data->>'last_name',''),new.email)
 on conflict(id) do nothing;
 if eid is not null then
  update public.employee_directory set profile_id=new.id,email=new.email,updated_at=now() where id=eid;
 end if;
 return new;
end $$;

create table public.vehicle_weekly_reports (
 id uuid primary key default gen_random_uuid(),
 vehicle_id uuid not null references public.vehicles(id),
 agent_id uuid not null references public.profiles(id),
 week_start date not null,
 friday_odometer integer not null check(friday_odometer>=0),
 monday_odometer integer not null check(monday_odometer>=friday_odometer),
 monday_refuel_at timestamptz not null,
 monday_liters numeric(9,2) not null check(monday_liters>0),
 monday_amount numeric(10,2) not null check(monday_amount>0),
 submitted_at timestamptz not null default now(), admin_comment text,
 status text not null default 'submitted' check(status in ('submitted','reviewed','anomaly')),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(vehicle_id,week_start)
);
create table public.vehicle_report_files (
 id uuid primary key default gen_random_uuid(), report_id uuid not null references public.vehicle_weekly_reports(id) on delete cascade,
 document_kind text not null check(document_kind in ('friday_dashboard','monday_dashboard','monday_receipt')),
 storage_path text not null unique, original_name text not null,
 mime_type text not null check(mime_type in ('image/jpeg','image/png','application/pdf')),
 size_bytes bigint not null check(size_bytes>0 and size_bytes<=10485760),
 created_at timestamptz not null default now(), unique(report_id,document_kind)
);
create table public.company_fuel_transactions (
 id uuid primary key default gen_random_uuid(),
 vehicle_id uuid not null references public.vehicles(id),
 occurred_at timestamptz not null,
 liters numeric(9,2) not null check(liters>0),
 amount numeric(10,2) not null check(amount>0),
 receipt_reference text,
 notes text,
 created_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now()
);
create or replace function public.can_access_vehicle(p_id uuid) returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.vehicles v join public.employee_directory d on d.id=v.assigned_employee_id join public.profiles p on p.id=d.profile_id where v.id=p_id and ((public.is_admin()) or (d.profile_id=auth.uid() and d.active and p.active)))
$$;
create or replace function public.can_access_vehicle_report(p_id uuid) returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.vehicle_weekly_reports r where r.id=p_id and (public.is_admin() or r.agent_id=auth.uid()))
$$;
create or replace function public.audit_vehicle_report() returns trigger language plpgsql security definer set search_path=public as $$
begin
 insert into public.audit_log(actor_id,entity,entity_id,action,details) values(auth.uid(),'vehicle_weekly_report',new.id,'submitted',jsonb_build_object('vehicle_id',new.vehicle_id,'week_start',new.week_start,'personal_km',new.monday_odometer-new.friday_odometer));
 return new;
end $$;
create trigger vehicle_report_audit after insert on public.vehicle_weekly_reports for each row execute procedure public.audit_vehicle_report();

alter table public.employee_directory enable row level security;
alter table public.vehicles enable row level security;
alter table public.vehicle_weekly_reports enable row level security;
alter table public.vehicle_report_files enable row level security;
alter table public.company_fuel_transactions enable row level security;
create policy "agents read own directory profile" on public.employee_directory for select to authenticated using(profile_id=auth.uid() or public.is_admin());
create policy "admins manage employee directory" on public.employee_directory for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "agents see assigned vehicles" on public.vehicles for select to authenticated using(public.can_access_vehicle(id));
create policy "admins manage vehicles" on public.vehicles for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "agents and admin read weekly reports" on public.vehicle_weekly_reports for select to authenticated using(agent_id=auth.uid() or public.is_admin());
create policy "agent submits report for assigned vehicle" on public.vehicle_weekly_reports for insert to authenticated with check(agent_id=auth.uid() and public.can_access_vehicle(vehicle_id));
create policy "admin reviews weekly reports" on public.vehicle_weekly_reports for update to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "read authorized vehicle files" on public.vehicle_report_files for select to authenticated using(public.can_access_vehicle_report(report_id));
create policy "add files to own report" on public.vehicle_report_files for insert to authenticated with check(exists(select 1 from public.vehicle_weekly_reports r where r.id=report_id and r.agent_id=auth.uid()));
create policy "admin removes vehicle files" on public.vehicle_report_files for delete to authenticated using(public.is_admin());
create policy "admin manages company fuel transactions" on public.company_fuel_transactions for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "agents delete own incomplete weekly reports" on public.vehicle_weekly_reports for delete to authenticated using(agent_id=auth.uid());
create policy "agents delete own report files" on public.vehicle_report_files for delete to authenticated using(exists(select 1 from public.vehicle_weekly_reports r where r.id=report_id and r.agent_id=auth.uid()));

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('vehicle-documents','vehicle-documents',false,10485760,array['image/jpeg','image/png','application/pdf'])
on conflict(id) do update set public=false,file_size_limit=10485760,allowed_mime_types=array['image/jpeg','image/png','application/pdf'];
create policy "read private assigned vehicle documents" on storage.objects for select to authenticated using(bucket_id='vehicle-documents' and public.can_access_vehicle_report((storage.foldername(name))[2]::uuid));
create policy "upload own weekly vehicle documents" on storage.objects for insert to authenticated with check(bucket_id='vehicle-documents' and (storage.foldername(name))[1]=auth.uid()::text and exists(select 1 from public.vehicle_weekly_reports r where r.id=(storage.foldername(name))[2]::uuid and r.agent_id=auth.uid()));
create policy "admin deletes vehicle documents" on storage.objects for delete to authenticated using(bucket_id='vehicle-documents' and public.is_admin());
create policy "agents delete own incomplete vehicle uploads" on storage.objects for delete to authenticated using(bucket_id='vehicle-documents' and (storage.foldername(name))[1]=auth.uid()::text and exists(select 1 from public.vehicle_weekly_reports r where r.id=(storage.foldername(name))[2]::uuid and r.agent_id=auth.uid()));
