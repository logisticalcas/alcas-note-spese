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

// Agents work on the previous month through day 10; from day 11 the new
// calendar month becomes the active expense period.
export function getOpenExpensePeriod(date = new Date()): ExpensePeriod {
  const today = getRomeDateParts(date)
  if (today.day > 10) return { month: today.month, year: today.year }
  const previous = new Date(Date.UTC(today.year, today.month - 2, 1))
  return { month: previous.getUTCMonth() + 1, year: previous.getUTCFullYear() }
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
