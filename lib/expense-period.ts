export type ExpensePeriod = { month: number; year: number }

export function getRomeDateParts(date = new Date()) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Europe/Rome',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(date)
  const value = (type: string) => Number(parts.find((part) => part.type === type)?.value)
  return { year: value('year'), month: value('month'), day: value('day') }
}

// New expenses always belong to the current calendar month from day 1.
export function getOpenExpensePeriod(date = new Date()): ExpensePeriod {
  const today = getRomeDateParts(date)
  return { month: today.month, year: today.year }
}

// During days 1–10, agents can still complete and submit last month's note.
export function getGraceExpensePeriod(date = new Date()): ExpensePeriod | null {
  const today = getRomeDateParts(date)
  if (today.day > 10) return null
  const previous = new Date(Date.UTC(today.year, today.month - 2, 1))
  return { month: previous.getUTCMonth() + 1, year: previous.getUTCFullYear() }
}

export function canEditExpensePeriod(period: ExpensePeriod, date = new Date()) {
  const current = getOpenExpensePeriod(date)
  if (period.month === current.month && period.year === current.year) return true
  const grace = getGraceExpensePeriod(date)
  return !!grace && period.month === grace.month && period.year === grace.year
}

export function getExpenseDeadline(month: number, year: number) {
  const next = new Date(Date.UTC(year, month, 10))
  return new Intl.DateTimeFormat('it-IT', { timeZone: 'Europe/Rome', day: 'numeric', month: 'long', year: 'numeric' }).format(next)
}

export function formatRomeDateTime(value: string) {
  return new Intl.DateTimeFormat('it-IT', {
    timeZone: 'Europe/Rome',
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value))
}
