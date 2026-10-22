# ALCAS NOTE SPESE

Applicazione Next.js + Supabase per note spese agenti. Interfaccia italiana, palette blu scuro, sessioni email/password, permessi RLS, ricevute private (JPG/PNG/PDF fino a 10 MB), revisione, CSV e registro delle modifiche principali. Il modulo Auto Aziendali resta disattivato.

## Requisiti

- Windows 10/11, Git, Node.js LTS (con npm).
- Next.js 16 richiede Node.js 20.9 o superiore.
- Account GitHub, Supabase e Vercel.
- Un progetto Supabase dedicato e accesso amministrativo.

## 1. Avvio locale

Apri PowerShell dentro la cartella `alcas-note-spese` ed esegui:

```powershell
npm install
Copy-Item .env.example .env.local
```

Per il momento il login locale richiede già il progetto Supabase al passo 3, quindi completa la configurazione sotto prima di avviare l'app.

## 2. Repository GitHub

1. Crea su GitHub un repository privato chiamato `alcas-note-spese` (senza aggiungere README o altri file iniziali).
2. Nella cartella `alcas-note-spese`, esegui:

```powershell
git init -b main
git add .
git commit -m "Prima versione ALCAS NOTE SPESE"
git remote add origin https://github.com/TUO-UTENTE/alcas-note-spese.git
git push -u origin main
```

Sostituisci `TUO-UTENTE` con il tuo nome utente/organizzazione GitHub. Non aggiungere `.env.local` al repository: è già escluso da `.gitignore`.

## 3. Supabase: progetto, schema e account

1. In [Supabase](https://supabase.com/dashboard) crea un progetto con regione europea, ad esempio Frankfurt, scegli una password database robusta e conservala nel password manager.
2. In **Project Settings → API** annota Project URL e chiave publishable/anon (non la `service_role`).
3. Installa Supabase CLI seguendo la [guida ufficiale](https://supabase.com/docs/guides/cli/getting-started), apri PowerShell nella cartella progetto e lancia:

```powershell
npx supabase@latest init
npx supabase login
npx supabase link --project-ref TUO_PROJECT_REF
npx supabase db push
```

La migrazione `supabase/migrations/202610220001_initial_schema.sql` crea le tabelle, i vincoli, le policy RLS, il bucket privato e i limiti per le ricevute. `TUO_PROJECT_REF` è il riferimento progetto mostrato nelle impostazioni Supabase. Controlla l’elenco migrazioni prima di confermare il push.

4. Configura **Authentication → URL Configuration** con l’URL locale `http://localhost:3000` e, dopo il deploy, con l’URL Vercel di produzione e gli eventuali domini di anteprima che intendi usare.
5. In **Authentication → Users**, invita gli account agenti. Al primo accesso il trigger crea un profilo con ruolo `agent`. Imposta nome e cognome del profilo in **SQL Editor** usando l’ID auth corretto:

```sql
update public.profiles
set first_name = 'Nome', last_name = 'Cognome'
where id = 'UUID_UTENTE';
```

Promuovi l’account amministratore solo dopo aver verificato l’UUID del proprietario:

```sql
update public.profiles set role = 'admin'
where id = 'UUID_AMMINISTRATORE';
```

Non promuovere un utente tramite dati di registrazione inviati dal browser. Gli agenti devono essere invitati dall’amministratore; disattiva la registrazione pubblica non necessaria in **Authentication → Settings**.

6. Configura `.env.local` (crealo da `.env.example`):

```env
NEXT_PUBLIC_SUPABASE_URL=https://TUO_PROJECT_REF.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=LA_TUA_CHIAVE_PUBLISHABLE
```

Usa la chiave anon legacy solo se il progetto non mostra ancora una publishable key. Mai usare `service_role` nel browser, nei file env pubblici o in Git.

7. Avvia e controlla l’app:

```powershell
npm run dev
```

Apri `http://localhost:3000`. Verifica con almeno due account agente che ognuno vede solo le proprie note, poi verifica il ruolo admin, upload/apertura ricevute, invio, rifiuto, integrazione e approvazione prima di caricare dati reali.

## 4. Vercel: deploy collegato a GitHub

1. Importa il repository GitHub in [Vercel](https://vercel.com/new), scegli framework Next.js e root directory `.` (se hai importato direttamente questa cartella come repository).
2. Nelle impostazioni **Environment Variables** aggiungi `NEXT_PUBLIC_SUPABASE_URL` e `NEXT_PUBLIC_SUPABASE_ANON_KEY` per Production e Preview. Sono chiavi pubblicabili; le policy RLS restano il controllo effettivo dei dati.
3. Fai il primo deploy dalla branch `main`; ogni push successivo alla branch collegata genera un deploy automatico. Ogni pull request può produrre un’anteprima.
4. Copia il dominio Vercel e aggiungilo in Supabase **Authentication → URL Configuration**. Imposta il Site URL sul dominio di produzione e aggiungi redirect URL per localhost, dominio di produzione e anteprime realmente utilizzate.
5. Dopo ogni modifica a una variabile d’ambiente, avvia un nuovo deploy: i deploy già creati non ricevono i nuovi valori.

## Procedura di aggiornamento

Modifica il codice localmente, prova `npm run build`, poi:

```powershell
git add .
git commit -m "Descrizione modifica"
git push
```

Le nuove migrazioni vanno aggiunte in `supabase/migrations/` e applicate al progetto Supabase con `npx supabase db push`. Crea prima un backup e applica le modifiche su un progetto di staging quando si gestiscono dati effettivi.

## Ambito implementato e punti da completare prima dell’uso operativo

- Inclusi login, dashboard agente/amministratore, inserimento e cancellazione spese, allegato privato, riepilogo totale, invio nota, approvazione/rifiuto/richiesta integrazioni/riapertura, filtro periodo/stato e export CSV.
- Nuovi account sono provisionati tramite Supabase Auth; il ruolo è un profilo con policy RLS. Le impostazioni e categorie sono nel database ma per questa versione si modificano dal dashboard/SQL Supabase.
- L’app non è ancora un sistema certificato o verificato per produzione. Prima dei dati reali esegui test RLS con due utenti agenti e un admin, verifica la policy storage e configura backup/database retention nel progetto Supabase.
- La recupero password self-service, gestione agenti/categorie dentro l’app, report annuali avanzati e notifiche email sono evoluzioni da completare. Il link di assistenza login è predisposto via email amministrativa.

## Fonti tecniche

- [Supabase SSR e autenticazione](https://supabase.com/docs/guides/auth/server-side)
- [Supabase Storage e bucket privati](https://supabase.com/docs/guides/storage/buckets/fundamentals)
- [Supabase migrazioni database](https://supabase.com/docs/guides/deployment/database-migrations)
- [Deploy Git su Vercel](https://vercel.com/docs/git)
- [Variabili d’ambiente Vercel](https://vercel.com/docs/environment-variables)
