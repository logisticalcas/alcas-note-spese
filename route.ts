import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { getRomeDateParts } from '@/lib/expense-period'

export const runtime = 'nodejs'

function escapeHtml(value: string) {
  const entities: Record<string, string> = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }
  return value.replace(/[&<>"']/g, (char) => entities[char])
}

export async function GET(request: NextRequest) {
  const secret = process.env.CRON_SECRET
  if (!secret || request.headers.get('authorization') !== `Bearer ${secret}`) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }
  const { year, month, day } = getRomeDateParts()
  const lastDay = new Date(Date.UTC(year, month, 0)).getUTCDate()
  if (day !== lastDay) return NextResponse.json({ skipped: true, reason: 'Not the last day of the month' })

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY
  const resendKey = process.env.RESEND_API_KEY
  const from = process.env.REMINDER_FROM_EMAIL
  if (!supabaseUrl || !serviceKey || !resendKey || !from) {
    return NextResponse.json({ error: 'Missing reminder configuration' }, { status: 500 })
  }
  const db = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } })
  const { data: agents, error: agentError } = await db.from('profiles')
    .select('id,email,first_name,last_name')
    .eq('role', 'agent').eq('active', true).eq('is_test', false)
  if (agentError) return NextResponse.json({ error: agentError.message }, { status: 500 })

  const { data: notes, error: noteError } = await db.from('expense_notes')
    .select('agent_id,status').eq('month', month).eq('year', year)
  if (noteError) return NextResponse.json({ error: noteError.message }, { status: 500 })
  const submitted = new Set((notes || []).filter((note) => ['in_review', 'approved'].includes(note.status)).map((note) => note.agent_id))
  const { data: alreadySent, error: logError } = await db.from('expense_reminder_log')
    .select('agent_id').eq('month', month).eq('year', year).eq('status', 'sent')
  if (logError) return NextResponse.json({ error: logError.message }, { status: 500 })
  const sentIds = new Set((alreadySent || []).map((row) => row.agent_id))
  let sent = 0
  const failures: string[] = []

  for (const agent of agents || []) {
    if (!agent.email || submitted.has(agent.id) || sentIds.has(agent.id)) continue
    const name = escapeHtml([agent.first_name, agent.last_name].filter(Boolean).join(' ') || 'Agente')
    const deadline = new Intl.DateTimeFormat('it-IT', { timeZone: 'Europe/Rome', day: 'numeric', month: 'long', year: 'numeric' })
      .format(new Date(Date.UTC(year, month, 10)))
    let errorText: string | null = null
    try {
      const response = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: { Authorization: `Bearer ${resendKey}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          from, to: [agent.email], subject: `Promemoria nota spese ${String(month).padStart(2, '0')}/${year}`,
          html: `<p>Buongiorno ${name},</p><p>ricordati di completare e inoltrare la nota spese di <strong>${new Intl.DateTimeFormat('it-IT', { month: 'long', year: 'numeric', timeZone: 'Europe/Rome' }).format(new Date(Date.UTC(year, month - 1, 1)))}</strong>.</p><p>Puoi inviarla dall’app ALCAS NOTE SPESE entro il <strong>${deadline}</strong> (incluso).</p><p>Dal giorno successivo si aprirà automaticamente il nuovo periodo.</p>`,
        }),
      })
      if (!response.ok) errorText = `Resend ${response.status}: ${(await response.text()).slice(0, 1000)}`
    } catch (error) {
      errorText = error instanceof Error ? error.message : String(error)
    }
    const { error: saveError } = await db.from('expense_reminder_log').upsert({
      agent_id: agent.id, month, year, status: errorText ? 'failed' : 'sent', sent_at: errorText ? null : new Date().toISOString(), error: errorText,
    }, { onConflict: 'agent_id,year,month' })
    if (saveError) failures.push(`${agent.email}: log write failed: ${saveError.message}`)
    else if (errorText) failures.push(`${agent.email}: ${errorText}`)
    else sent++
  }

  return NextResponse.json({ month, year, sent, failures })
}
