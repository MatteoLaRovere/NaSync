# 🔄 NaSync

**NaSync** è un'utility nativa per macOS che risiede discretamente nella barra dei menu (Menu Bar). Consente di sincronizzare in modo automatico, sicuro e personalizzabile cartelle locali del tuo Mac verso un NAS (Network Attached Storage) o server di rete tramite il protocollo **SMB** e **`rsync`**.

Designed for macOS Ventura, Sonoma, Sequoia e versioni successive.

🌐 **Sito Ufficiale:** [matteolarovere.altervista.org/Nasync/index.html](http://matteolarovere.altervista.org/Nasync/index.html)

---

## ✨ Caratteristiche Principali

* **Doppia Modalità Menu Bar:**
  * **Clic sinistro:** Visualizza lo stato di sincronizzazione, i log in tempo reale e il controllo rapido.
  * **Clic destro:** Menu contestuale a tendina per azioni immediate (*Sync Ora*, *Impostazioni*, *Log*, *Esci*).
* **Rete e Connessioni Generiche:**
  * Supporta **IP Locali** (Wi-Fi / Ethernet) e **VPN** (Tailscale, WireGuard, ZeroTier).
  * Porta **SMB personalizzabile** (predefinita `445`).
  * Autenticazione flessibile: supporto a credenziali manuali o integrazione diretta con il Portachiavi di macOS.
* **Controllo Permessi TCC:** Monitoraggio integrato in tempo reale dello stato dell'**Accesso completo al disco** (Full Disk Access) per prevenire fallimenti di lettura durante l'esecuzione di `rsync`.
* **Backup & Ripristino Configurazione:** Esporta e importa l'intera lista di cartelle e parametri di rete in formato `JSON`.

---

## 🚀 Installazione

1. Scarica l'ultima versione del file `.dmg` dal **[Sito Ufficiale](http://matteolarovere.altervista.org/Nasync/index.html)** oppure direttamente dalla sezione **[Releases](../../releases)**.
2. Apri il file `NaSync.dmg` e trascina **NaSync.app** nella cartella **Applicazioni**.
3. Avvia l'app e assegna i permessi di **Accesso completo al disco** quando richiesto:
   * *Impostazioni di Sistema > Privacy e Sicurezza > Accesso completo al disco* -> Abilita **NaSync**.

---

## ⚙️ Configurazione Iniziale

1. Inserisci l'**IP o Hostname** del tuo NAS e il nome della **Cartella Condivisa** (Share SMB).
2. Aggiungi i task di sincronizzazione specificando:
   * **Percorso Locale:** (es. `~/Documents/Cartella`)
   * **Percorso Remoto:** (es. `/Backup/`)
3. Fai clic su **Sincronizza Ora**.

---

## 🛡️ Privacy e Sicurezza

NaSync opera esclusivamente in locale sul tuo Mac. Nessun dato, credenziale o log viene inviato a server esterni.

---

## 🌐 Link Utili

* **Landing Page:** [http://matteolarovere.altervista.org/Nasync/index.html](http://matteolarovere.altervista.org/Nasync/index.html)
* **Download Diretto Ultima Versione:** [Scarica NaSync.dmg](https://github.com/MatteoLaRovere/NaSync/releases/latest/download/NaSync.dmg)

---

## 👨‍💻 Autore

Sviluppato con ❤️ da **[Matteo La Rovere](https://github.com/MatteoLaRovere)**.
