import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': Deno.env.get('APP_ORIGIN') ?? '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (request.method !== 'POST') return new Response('Method not allowed', { status: 405, headers: cors })
  const url = Deno.env.get('SUPABASE_URL')!
  const anon = Deno.env.get('SUPABASE_ANON_KEY')!
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const authorization = request.headers.get('Authorization') ?? ''
  const token = authorization.replace(/^Bearer\s+/i, '')
  const userClient = createClient(url, anon, { global: { headers: { Authorization: authorization } } })
  const { data: { user }, error: userError } = await userClient.auth.getUser(token)
  if (userError || !user) return new Response('Unauthorized', { status: 401, headers: cors })
  const admin = createClient(url, service, { auth: { persistSession: false } })
  const { data: caller } = await admin.from('profiles').select('role,active').eq('id', user.id).single()
  if (caller?.role !== 'admin' || caller?.active !== true) return new Response('Forbidden', { status: 403, headers: cors })
  const { employeeId } = await request.json()
  const { data: employee, error } = await admin.from('employee_directory').select('id,first_name,last_name,email,profile_id,active').eq('id', employeeId).single()
  if (error || !employee || !employee.active || !employee.email || employee.profile_id) return new Response('Agente non pronto per l’invito: controlla email e stato account.', { status: 400, headers: cors })
  const { data, error: inviteError } = await admin.auth.admin.inviteUserByEmail(employee.email, {
    data: { first_name: employee.first_name, last_name: employee.last_name, employee_id: employee.id },
    redirectTo: `${Deno.env.get('APP_ORIGIN')}/`,
  })
  if (inviteError) return new Response(inviteError.message, { status: 400, headers: cors })
  return Response.json({ invited: true, userId: data.user.id }, { headers: cors })
})
