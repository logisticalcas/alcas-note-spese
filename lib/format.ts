export const months = ['Gennaio','Febbraio','Marzo','Aprile','Maggio','Giugno','Luglio','Agosto','Settembre','Ottobre','Novembre','Dicembre']
export const euro = (n:number) => new Intl.NumberFormat('it-IT',{style:'currency',currency:'EUR'}).format(n)
export const dateIT = (s:string) => new Date(`${s}T12:00:00`).toLocaleDateString('it-IT')
export const labels:Record<string,string> = {draft:'Bozza',in_review:'In revisione',integration_requested:'Integrazione richiesta',approved:'Approvata',rejected:'Respinta',reopened:'Riaperta'}
