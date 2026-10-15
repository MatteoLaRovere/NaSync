<div align="center">

  # 🔄 NaSync

  **Utility nativa per macOS per la sincronizzazione automatica su NAS tramite SMB e `rsync`.**

  [![Sito Ufficiale](https://img.shields.io/badge/Sito_Ufficiale-NaSync-0071e3?style=for-the-badge&logo=safari&logoColor=white)](http://nasync.altervista.org/index.html)
  [![Download DMG](https://img.shields.io/badge/Scarica-NaSync.dmg-22c55e?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/MatteoLaRovere/NaSync/releases/latest/download/NaSync.dmg)
  [![GitHub Release](https://img.shields.io/github/v/release/MatteoLaRovere/NaSync?style=for-the-badge&color=blue)](https://github.com/MatteoLaRovere/NaSync/releases)

  ---

  [🌐 Sito Ufficiale](http://nasync.altervista.org/index.html) • [📦 Scarica l'Ultima Release](https://github.com/MatteoLaRovere/NaSync/releases/latest/download/NaSync.dmg) • [💬 Report Problemi](https://github.com/MatteoLaRovere/NaSync/issues)

</div>

<br>

**NaSync** è un'applicazione nativa per macOS che risiede discretamente nella barra dei menu (Menu Bar). Consente di sincronizzare in modo automatico, sicuro e personalizzabile le cartelle locali del tuo Mac verso un NAS (Network Attached Storage) o server di rete via **SMB** e **`rsync`**.

Progettato per macOS Ventura, Sonoma, Sequoia e versioni successive.

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

1. Scarica l'ultima versione del file `.dmg` dal **[Sito Ufficiale](http://nasync.altervista.org/index.html)** oppure direttamente dalla sezione **[Releases](../../releases)**.
2. Apri il file `NaSync.dmg` e trascina **NaSync.app** nella cartella **Applicazioni**.
3. Avvia l'app e assegna i permessi di **Accesso completo al disco** quando richiesto:
   * *Impostazioni di Sistema > Privacy e Sicurezza > Accesso completo al disco* ➔ Abilita **NaSync**.

---

## ⚙️ Configurazione Iniziale

1. Inserisci l'**IP o Hostname** del tuo NAS e il nome della **Cartella Condivisa** (Share SMB).
2. Aggiungi i task di sincronizzazione specificando:
   * **Percorso Locale:** (es. `~/Documents/Cartella`)
   * **Percorso Remoto:** (es. `/Backup/`)
3. Fai clic su **Sincronizza Ora**.

---

## 🛡️ Privacy e Sicurezza

NaSync opera esclusivamente in locale sul tuo Mac. Nessun dato, credenziale o log viene mai inviato a server esterni.

---

## 👨‍💻 Autore

Sviluppato con ❤️ da **[Matteo La Rovere](https://github.com/MatteoLaRovere)**.
