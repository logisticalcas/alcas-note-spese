import { createClient } from 'npm:@supabase/supabase-js@2'

const origin = Deno.env.get('APP_ORIGIN') ?? '*'
const cors = {
  'Access-Control-Allow-Origin': origin,
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function reply(message: string, status: number) {
  return new Response(message, { status, headers: cors })
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (request.method !== 'POST') return reply('Method not allowed', 405)

  const url = Deno.env.get('SUPABASE_URL')!
  const anon = Deno.env.get('SUPABASE_ANON_KEY')!
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const authorization = request.headers.get('Authorization') ?? ''
  const token = authorization.replace(/^Bearer\s+/i, '')
  if (!token) return reply('Unauthorized', 401)

  const callerClient = createClient(url, anon, { global: { headers: { Authorization: authorization } } })
  const { data: { user: caller }, error: authError } = await callerClient.auth.getUser(token)
  if (authError || !caller) return reply('Unauthorized', 401)

  const admin = createClient(url, service, { auth: { persistSession: false } })
  const { data: callerProfile } = await admin.from('profiles').select('role,active').eq('id', caller.id).single()
  if (callerProfile?.role !== 'admin' || callerProfile.active !== true) return reply('Forbidden', 403)

  const { data: employee, error: employeeError } = await admin.from('employee_directory')
    .select('id,first_name,last_name,profile_id,active').eq('employee_code', 'TEST-AGENT').single()
  if (employeeError || !employee || !employee.active) return reply('Applica prima la migrazione agent_test_mode.', 400)

  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%'
  const bytes = crypto.getRandomValues(new Uint8Array(40))
  const password = Array.from(bytes, b => alphabet[b % alphabet.length]).join('')
  const email = Deno.env.get('TEST_AGENT_EMAIL') ?? 'agente-test@alcas-note-spese.invalid'
  let userId = employee.profile_id

  if (userId) {
    const { data: existing, error } = await admin.auth.admin.getUserById(userId)
    if (error || existing.user?.user_metadata?.is_alcas_test_agent !== true) {
      return reply('Il profilo TEST-AGENT è collegato a un account non riservato ai test. Contatta l’amministratore tecnico.', 409)
    }
    const { error: resetError } = await admin.auth.admin.updateUserById(userId, { password })
    if (resetError) return reply(resetError.message, 500)
  } else {
    const { data, error } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { first_name: employee.first_name, last_name: employee.last_name, employee_id: employee.id, is_alcas_test_agent: true },
    })
    if (error || !data.user) return reply(error?.message ?? 'Impossibile creare l’account di prova.', 500)
    userId = data.user.id
  }

  const profile = await admin.from('profiles').update({ first_name: 'Agente', last_name: 'Test', role: 'agent', active: true, is_test: true }).eq('id', userId!)
  if (profile.error) return reply(profile.error.message, 500)
  const link = await admin.from('employee_directory').update({ profile_id: userId, first_name: 'Agente', last_name: 'Test', active: true }).eq('id', employee.id)
  if (link.error) return reply(link.error.message, 500)

  // Every new test session starts clean; only the dedicated test user's data is removed.
  const { data: notes } = await admin.from('expense_notes').select('id').eq('agent_id', userId!)
  if (notes?.length) {
    const { data: expenses } = await admin.from('expenses').select('id').in('note_id', notes.map(x => x.id))
    if (expenses?.length) {
      const { data: attachments } = await admin.from('expense_attachments').select('storage_path').in('expense_id', expenses.map(x => x.id))
      if (attachments?.length) await admin.storage.from('expense-receipts').remove(attachments.map(x => x.storage_path))
    }
    await admin.from('expense_notes').delete().eq('agent_id', userId!)
  }
  const { data: reports } = await admin.from('vehicle_weekly_reports').select('id').eq('agent_id', userId!)
  if (reports?.length) {
    const { data: files } = await admin.from('vehicle_report_files').select('storage_path').in('report_id', reports.map(x => x.id))
    if (files?.length) await admin.storage.from('vehicle-documents').remove(files.map(x => x.storage_path))
    await admin.from('vehicle_weekly_reports').delete().eq('agent_id', userId!)
  }
  return Response.json({ email, password }, { headers: cors })
})
