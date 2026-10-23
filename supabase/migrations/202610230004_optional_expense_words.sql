-- L'importo in lettere non è più richiesto nel modulo di inserimento.
-- I valori storici restano invariati; le nuove spese possono lasciarlo vuoto.
alter table public.expenses
alter column amount_in_words drop not null;
