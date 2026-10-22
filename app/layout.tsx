import type { Metadata } from 'next'
import './style.css'
export const metadata: Metadata = { title:'ALCAS NOTE SPESE', description:'Gestione note spese agenti ALCAS ITALIA' }
export default function RootLayout({children}:{children:React.ReactNode}) { return <html lang="it"><body>{children}</body></html> }
