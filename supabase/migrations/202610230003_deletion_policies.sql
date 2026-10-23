-- Eliminazioni esplicite e protette: gli agenti possono rimuovere solo bozze;
-- l'amministratore può rimuovere spese/report errati e i file associati.
create policy "agent deletes own draft note" on public.expense_notes
for delete to authenticated
using(agent_id=auth.uid() and status='draft');

create policy "admin deletes expenses" on public.expenses
for delete to authenticated
using(public.is_admin());

create policy "admin deletes expense receipts" on storage.objects
for delete to authenticated
using(bucket_id='expense-receipts' and public.is_admin());

create policy "admin deletes weekly reports" on public.vehicle_weekly_reports
for delete to authenticated
using(public.is_admin());
