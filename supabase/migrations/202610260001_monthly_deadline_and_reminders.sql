-- Agents may edit or submit an expense note through day 10 (Rome time)
-- of the following month. From day 11, the current calendar month opens.
create or replace function public.is_open_expense_period(p_month smallint, p_year smallint)
returns boolean language sql stable as $$
  with local_day as (
    select (now() at time zone 'Europe/Rome')::date as today
  ), active_period as (
    select case when extract(day from today) <= 10
      then (date_trunc('month', today)::date - interval '1 month')::date
      else date_trunc('month', today)::date end as starts
    from local_day
  )
  select extract(month from starts)::smallint = p_month
     and extract(year from starts)::smallint = p_year
  from active_period;
$$;

create or replace function public.can_edit_note(p_id uuid)
returns boolean language sql stable security definer set search_path=public,auth as $$
  select exists(
    select 1 from public.expense_notes n
    join public.profiles p on p.id=n.agent_id
    where n.id=p_id and p.active and p.id=auth.uid()
      and n.status in ('draft','integration_requested','reopened')
      and public.is_open_expense_period(n.month,n.year)
  );
$$;

drop policy if exists "agent creates own note" on public.expense_notes;
create policy "agent creates own note" on public.expense_notes
for insert to authenticated
with check(agent_id=auth.uid() and status='draft' and public.is_open_expense_period(month,year));

drop policy if exists "agent submits or edits own note" on public.expense_notes;
create policy "agent submits or edits own note" on public.expense_notes
for update to authenticated
using((agent_id=auth.uid() and status in ('draft','integration_requested','reopened')
       and public.is_open_expense_period(month,year)) or public.is_admin())
with check((agent_id=auth.uid() and status in ('draft','in_review','integration_requested','reopened')
            and public.is_open_expense_period(month,year)) or public.is_admin());

drop policy if exists "agent deletes own draft note" on public.expense_notes;
create policy "agent deletes own draft note" on public.expense_notes
for delete to authenticated
using(agent_id=auth.uid() and status='draft' and public.is_open_expense_period(month,year));

-- One monthly reminder per agent and period; inaccessible to ordinary clients.
create table if not exists public.expense_reminder_log (
  agent_id uuid not null references public.profiles(id) on delete cascade,
  month smallint not null check(month between 1 and 12),
  year smallint not null check(year between 2020 and 2100),
  status text not null check(status in ('sent','failed')),
  sent_at timestamptz,
  error text,
  primary key(agent_id,year,month)
);
alter table public.expense_reminder_log enable row level security;
