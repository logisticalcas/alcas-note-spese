# ALCAS NOTE SPESE

Applicazione Next.js + Supabase per note spese agenti. Interfaccia italiana, palette blu scuro, sessioni email/password, permessi RLS, ricevute private (JPG/PNG/PDF fino a 10 MB), revisione e CSV. Include gestione agenti/account, categorie, massimali, veicoli aziendali, report chilometrici e registro delle transazioni carburante.

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

Lo schema iniziale crea le tabelle e le policy. Se lo hai già lanciato manualmente nel SQL Editor, non rilanciarlo: applica solo la migrazione aggiuntiva descritta in **Procedura di aggiornamento**.

4. Configura **Authentication → URL Configuration** con l’URL locale `http://localhost:3000` e, dopo il deploy, con l’URL Vercel di produzione e gli eventuali domini di anteprima che intendi usare. Il recupero password torna alla home app: aggiungi `http://localhost:3000/**` e `https://TUO-DOMINIO-VERCEL/**` agli **Additional Redirect URLs**.
5. In **Authentication → Users**, invita gli account agenti. Al primo accesso il trigger crea un profilo con ruolo `agent`. Promuovi una sola volta l’amministratore iniziale in **SQL Editor**, dopo aver verificato l’UUID dell’account:

```sql
update public.profiles set role = 'admin'
where id = 'UUID_AMMINISTRATORE';
```

Dopo l’accesso amministratore, usa la pagina **Agenti** per collegare profili già esistenti, assegnare i ruoli e gestire gli account. Non promuovere un utente tramite dati inviati dal browser. Disattiva la registrazione pubblica non necessaria in **Authentication → Settings**.

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

## Pubblicare gli aggiornamenti usando GitHub online

1. Apri il repository GitHub e fai **Add file → Upload files**. Carica o sostituisci questi file mantenendo i percorsi:
   - `app/page.tsx`
   - `app/style.css`
   - `components/operations.tsx`
   - `package.json`
   - `tsconfig.json`
   - `supabase/migrations/202610230002_agent_test_mode.sql` (solo se non è già nel repository)
   - `supabase/migrations/202610230003_deletion_policies.sql` (nuovo)
   - `supabase/migrations/202610230004_optional_expense_words.sql` (nuovo)
   - `supabase/functions/agent-test-access/index.ts` (nuova funzione)
   - `README.md`
2. Premi **Commit changes** sulla branch `main`. Vercel avvierà il deploy automatico dai file aggiornati.
3. Le migrazioni `202610230001_operations_and_fleet.sql` e `202610230002_agent_test_mode.sql` contengono flotta e modalità test. Se non sono ancora state applicate, esegui prima la `001`, poi la `002`. Applica in ordine anche `202610230003_deletion_policies.sql` e `202610230004_optional_expense_words.sql`, ciascuna una sola volta, da **Supabase → SQL Editor → New query → Run**. Non rilanciare lo schema iniziale.
4. In **Supabase → Edge Functions → Deploy a new function → Via Editor**, crea `agent-test-access`, incolla il contenuto di `supabase/functions/agent-test-access/index.ts` e distribuiscila. La funzione `invite-agent` già usata per invitare gli agenti non va sostituita. La Dashboard permette di distribuire le funzioni dal browser ([guida ufficiale](https://supabase.com/docs/guides/functions/quickstart-dashboard)).
5. Il deploy Vercel partirà dopo il commit GitHub. Include il download ZIP di riepilogo e ricevute, i controlli di eliminazione e gli aggiornamenti per smartphone. In Supabase **Authentication → URL Configuration**, verifica che il dominio Vercel sia tra gli URL consentiti.

Le anagrafiche iniziali sono Fabio Scognamiglio, Emanuele Santaniello e Gianluca Giordano. Inserisci le email degli agenti e completa targa, marca e modello dei veicoli dalla pagina amministratore. I dati mancanti non sono stati inventati.

Dal menu **Report carburante** l’amministratore può registrare i rifornimenti della carta aziendale e controllare date/orari; i rifornimenti nel fine settimana vengono segnalati. La registrazione si basa sui dati dell’estratto della carta, senza integrazione automatica col fornitore.

## Ambito implementato e punti da completare prima dell’uso operativo

- Inclusi login, dashboard agente/amministratore, spese con note e ospiti per la rappresentanza, allegati privati, massimali e revisione. L’esportazione ZIP contiene riepilogo CSV e ricevute del mese selezionato. Sono presenti eliminazioni con conferma per note, spese, report, veicoli, transazioni e anagrafiche non collegate; gli account con storico vengono disattivati invece di essere rimossi. La navigazione e i moduli sono adattati agli schermi smartphone.
- La modalità amministrativa “Prova come Agente Test” apre una seconda scheda con dati separati; ogni nuovo avvio pulisce soltanto i dati di prova precedenti.
- Incluso recupero password via email Supabase: dalla pagina login si richiede un link e si sceglie la password nuova. Richiede redirect URL configurati e invio email Auth funzionante.
- Nuovi account sono provisionati tramite Supabase Auth. L’admin gestisce dal portale anagrafiche, inviti, collegamento profili, ruoli, categorie, veicoli e massimali.
- L’app non è ancora un sistema certificato o verificato per produzione. Prima dei dati reali esegui test RLS con due utenti agenti e un admin, verifica la policy storage e configura backup/database retention nel progetto Supabase.
- Le transazioni della carta carburante vengono inserite dall’amministratore a partire dai dati dell’estratto; al momento non c’è un collegamento automatico al fornitore della carta.

## Fonti tecniche

- [Supabase SSR e autenticazione](https://supabase.com/docs/guides/auth/server-side)
- [Supabase Storage e bucket privati](https://supabase.com/docs/guides/storage/buckets/fundamentals)
- [Supabase migrazioni database](https://supabase.com/docs/guides/deployment/database-migrations)
- [Deploy Git su Vercel](https://vercel.com/docs/git)
- [Variabili d’ambiente Vercel](https://vercel.com/docs/environment-variables)

## Scadenza mensile, archivio e promemoria email

- Gli agenti non scelgono il mese. Le spese del mese corrente si registrano dal giorno 1; la bozza del mese precedente si può completare e inoltrare fino al giorno 10 incluso (fuso `Europe/Rome`). Dal giorno 11 quella nota diventa sola lettura. Il database applica la stessa regola alle modifiche e agli invii.
- L’agente vede lo storico completo e può scaricare ogni nota con il riepilogo e le ricevute. I report delle auto restano archiviati in Supabase; ciascun report si scarica come ZIP con riepilogo, dati chilometrici, importi, orari e allegati caricati.
- Ogni giorno Vercel controlla se è l’ultimo giorno del mese a Roma e invia il promemoria agli agenti attivi non ancora inviati/in revisione. I promemoria riusciti vengono registrati per impedire duplicati; gli invii falliti possono essere riprovati.

### Attivazione dopo il commit

1. Carica e fai commit di `supabase/migrations/202610260001_monthly_deadline_and_reminders.sql` insieme agli altri file. In Supabase SQL Editor esegui tutto il contenuto della nuova migrazione una sola volta.
2. In Vercel → **Settings → Environment Variables**, aggiungi per Production (e Preview se vuoi provarlo):
   - `SUPABASE_SERVICE_ROLE_KEY`: chiave `service_role` del progetto Supabase. È un segreto server, non va mai inserito in una variabile `NEXT_PUBLIC_`.
   - `CRON_SECRET`: valore casuale lungo. Vercel usa questo valore per autenticare le chiamate cron.
   - `RESEND_API_KEY`: chiave API Resend.
   - `REMINDER_FROM_EMAIL`: mittente del dominio verificato in Resend, per esempio `ALCAS NOTE SPESE <note-spese@azienda.it>`.
   - Verifica anche `NEXT_PUBLIC_SUPABASE_URL` e `NEXT_PUBLIC_SUPABASE_ANON_KEY`.
3. In Resend verifica il dominio mittente e autorizza i record DNS richiesti. Senza dominio verificato o con una chiave non valida le email falliscono; la risposta viene salvata nel log Supabase.
4. Dopo aver aggiunto le variabili, fai **Redeploy** su Vercel. Il file `vercel.json` configura il controllo giornaliero alle 08:00 UTC (09:00 o 10:00 in Italia secondo l’ora legale); il codice verifica comunque la data locale italiana.
5. Per un controllo manuale puoi aprire `/api/cron/expense-reminders` solo con un header `Authorization: Bearer <CRON_SECRET>`. Il route risponde senza inviare se non è l’ultimo giorno del mese. Controlla Vercel → **Logs** e la tabella `expense_reminder_log` in Supabase.

I cron Vercel funzionano sui deploy Production e sono pianificati in UTC. L’API email Resend richiede una chiave e un mittente configurato. Riferimenti: [Cron Vercel](https://vercel.com/docs/cron-jobs/manage-cron-jobs), [Email API Resend](https://resend.com/docs/api-reference/emails/send-email).

### Raccolta del mese e accesso Agente Test

- Il mese corrente è registrabile dal giorno 1. Fino al giorno 10 si può anche aprire dall’Archivio la bozza del mese precedente, completarla e inoltrarla. Dal giorno 11 quella nota diventa sola lettura.
- Dall’area amministratore usa **Crea accesso per il responsabile commerciale** e condividi credenziali e URL mostrati. È lo stesso account isolato `is_test`: non concede privilegi amministrativi. Ogni nuova generazione o avvio della modalità di prova reimposta la password e cancella i soli dati dell’Agente Test.
- Per feedback e malfunzionamenti applica `202610260002_agent_feedback.sql`; per la regola di raccolta dal primo giorno applica `202610260003_current_month_capture.sql`, dopo le migrazioni precedenti.
- Per visualizzare il profilo amministrativo come “Amministrazione Alcas Italia” applica anche `202610260004_admin_profile_display_name.sql` dopo le precedenti.
