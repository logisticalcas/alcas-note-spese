-- Profilo e veicolo dedicati per la modalità di prova amministrativa.
alter table public.profiles add column if not exists is_test boolean not null default false;

insert into public.employee_directory(first_name,last_name,email,active,employee_code,notes)
values('Agente','Test',null,true,'TEST-AGENT','Profilo riservato ai test amministrativi; tenere separato dall’operatività reale.')
on conflict(employee_code) do update set first_name=excluded.first_name,last_name=excluded.last_name,active=true,notes=excluded.notes;

insert into public.vehicles(plate,make,model,fuel_type,assigned_employee_id,active,notes)
select 'TEST-000','ALCAS','Veicolo di prova','Non applicabile',id,true,'Veicolo fittizio per la modalità di test; non usare per trasferte reali.'
from public.employee_directory where employee_code='TEST-AGENT'
on conflict(plate) do update set assigned_employee_id=excluded.assigned_employee_id,active=true,notes=excluded.notes;
