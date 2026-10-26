-- Usa una denominazione chiara per i profili amministrativi esistenti.
update public.profiles
set first_name = 'Amministrazione',
    last_name = 'Alcas Italia'
where role = 'admin'
  and (first_name is distinct from 'Amministrazione'
       or last_name is distinct from 'Alcas Italia');
