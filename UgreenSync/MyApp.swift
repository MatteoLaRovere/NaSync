import SwiftUI
import Combine
import UniformTypeIdentifiers
import AppKit

// Modello per una singola regola di sincronizzazione
struct SyncTask: Identifiable, Codable {
    var id = UUID()
    var name: String
    var localPath: String
    var remoteSubpath: String
    var isEnabled: Bool = true
}

// Struttura per l'esportazione/importazione del backup
struct AppConfigExport: Codable {
    var tailscaleIP: String
    var nasShareName: String
    var smbPort: String
    var nasUsername: String
    var tasks: [SyncTask]
}

// Oggetto di stato globale e persistente (con logica di sync universale e credenziali)
class SyncState: ObservableObject {
    @Published var isSyncing = false
    @Published var hasError = false
    @Published var statusText = "Pronto alla sincronizzazione"
    @Published var liveDetailText = "Nessuna attività recente"
    @Published var lastSyncTime = "Mai"
    
    // Ultimi 10 log di sistema
    @Published var logs: [String] = []
    
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    @AppStorage("tailscaleIP") var tailscaleIP: String = ""
    @AppStorage("nasShareName") var nasShareName: String = ""
    @AppStorage("smbPort") var smbPort: String = "445"
    @AppStorage("nasUsername") var nasUsername: String = ""
    @AppStorage("nasPassword") var nasPassword: String = ""
    
    @Published var tasks: [SyncTask] {
        didSet {
            if let encoded = try? JSONEncoder().encode(tasks) {
                UserDefaults.standard.set(encoded, forKey: "savedSyncTasks")
            }
        }
    }
    
    init() {
        if let data = UserDefaults.standard.data(forKey: "savedSyncTasks"),
           let decoded = try? JSONDecoder().decode([SyncTask].self, from: data) {
            self.tasks = decoded
        } else {
            self.tasks = []
        }
    }
    
    func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        let time = formatter.string(from: Date())
        let entry = "[\(time)] \(message)"
        DispatchQueue.main.async {
            self.logs.append(entry)
            if self.logs.count > 10 {
                self.logs.removeFirst()
            }
        }
    }
    
    // Controllo rigoroso basato su file protetto da TCC (Full Disk Access)
    func checkFullDiskAccess() -> Bool {
        let protectedPath = "/Library/Preferences/com.apple.TimeMachine.plist"
        do {
            _ = try Data(contentsOf: URL(fileURLWithPath: protectedPath))
            return true
        } catch {
            return false
        }
    }
    
    func resetAllData() {
        hasCompletedOnboarding = false
        tailscaleIP = ""
        nasShareName = ""
        smbPort = "445"
        nasUsername = ""
        nasPassword = ""
        tasks.removeAll()
        logs.removeAll()
        UserDefaults.standard.removeObject(forKey: "savedSyncTasks")
        log("Reset totale eseguito.")
    }
    
    func exportBackupData() -> Data? {
        let config = AppConfigExport(tailscaleIP: tailscaleIP, nasShareName: nasShareName, smbPort: smbPort, nasUsername: nasUsername, tasks: tasks)
        return try? JSONEncoder().encode(config)
    }
    
    func importBackupData(from data: Data) -> Bool {
        guard let decoded = try? JSONDecoder().decode(AppConfigExport.self, from: data) else {
            log("Errore: file di backup non valido.")
            return false
        }
        self.tailscaleIP = decoded.tailscaleIP
        self.nasShareName = decoded.nasShareName
        self.smbPort = decoded.smbPort.isEmpty ? "445" : decoded.smbPort
        self.nasUsername = decoded.nasUsername
        self.tasks = decoded.tasks
        self.hasCompletedOnboarding = true
        log("Backup ripristinato con successo.")
        return true
    }
    
    // Logica di sincronizzazione con supporto a porta personalizzata e credenziali
    func runAllSyncProcesses() {
        let activeTasks = self.tasks.filter { $0.isEnabled }
        if activeTasks.isEmpty {
            self.statusText = "⚠️ Nessuna cartella attiva."
            self.liveDetailText = "Abilita almeno una cartella nelle impostazioni."
            self.log("Tentativo di sync fallito: nessun task attivo.")
            return
        }
        
        if !self.checkFullDiskAccess() {
            self.log("⚠️ Avviso: Accesso completo al disco non rilevato. Verifica i permessi in Privacy e Sicurezza se il sync fallisce.")
        }
        
        self.isSyncing = true
        self.hasError = false
        self.statusText = "Verifica connessione NAS..."
        
        let portToCheck = self.smbPort.isEmpty ? "445" : self.smbPort
        self.liveDetailText = "Controllo porta \(portToCheck) su \(self.tailscaleIP)..."
        self.log("Inizio processo di sincronizzazione verso \(self.tailscaleIP):\(portToCheck).")
        
        // Costruzione URL SMB con credenziali opzionali e porta personalizzata
        let authPart = (!self.nasUsername.isEmpty && !self.nasPassword.isEmpty) ? "\(self.nasUsername.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? self.nasUsername):\(self.nasPassword.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? self.nasPassword)@" : ""
        let nasShareURL = "smb://\(authPart)\(self.tailscaleIP):\(portToCheck)/\(self.nasShareName)"
        let mountPoint = "/Volumes/\(self.nasShareName)"
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Controllo porta in background
            let checkTask = Process()
            checkTask.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
            checkTask.arguments = ["-z", "-w", "3", self.tailscaleIP, portToCheck]
            
            do {
                try checkTask.run()
                checkTask.waitUntilExit()
                
                if checkTask.terminationStatus != 0 {
                    DispatchQueue.main.async {
                        self.statusText = "❌ Errore: NAS non raggiungibile."
                        self.liveDetailText = "Impossibile contattare \(self.tailscaleIP):\(portToCheck)."
                        self.hasError = true
                        self.isSyncing = false
                    }
                    self.log("Errore: porta \(portToCheck) non raggiungibile su \(self.tailscaleIP).")
                    return
                }
            } catch {
                DispatchQueue.main.async {
                    self.statusText = "❌ Errore di rete."
                    self.hasError = true
                    self.isSyncing = false
                }
                self.log("Eccezione durante il controllo di rete: \(error.localizedDescription)")
                return
            }
            
            DispatchQueue.main.async {
                self.statusText = "Montaggio volume SMB..."
                self.liveDetailText = "Connessione al percorso condiviso..."
            }
            
            let fileManager = FileManager.default
            if !fileManager.fileExists(atPath: mountPoint) {
                let mountTask = Process()
                mountTask.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                mountTask.arguments = ["-e", "mount volume \"\(nasShareURL)\""]
                try? mountTask.run()
                mountTask.waitUntilExit()
                sleep(2)
            }
            
            if !fileManager.fileExists(atPath: mountPoint) {
                DispatchQueue.main.async {
                    self.statusText = "❌ Errore montaggio."
                    self.liveDetailText = "Verifica credenziali o Portachiavi."
                    self.hasError = true
                    self.isSyncing = false
                }
                self.log("Errore: Impossibile montare \(self.nasShareName) su \(mountPoint).")
                return
            }
            
            self.log("Volume montato correttamente su \(mountPoint).")
            
            for (index, task) in activeTasks.enumerated() {
                DispatchQueue.main.async {
                    self.statusText = "Sync (\(index + 1)/\(activeTasks.count)): \(task.name)"
                }
                
                let localDir = task.hasPrefixTilde() ? task.resolvedLocalPath() : task.localPath
                let remoteDir = mountPoint + task.remoteSubpath
                
                try? fileManager.createDirectory(atPath: remoteDir, withIntermediateDirectories: true, attributes: nil)
                
                self.log("Sincronizzazione di '\(task.name)' in corso...")
                
                let rsyncTask = Process()
                rsyncTask.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
                rsyncTask.arguments = ["-avh", "--progress", "--delete", localDir, remoteDir]
                
                let outputPipe = Pipe()
                rsyncTask.standardOutput = outputPipe
                rsyncTask.standardError = outputPipe
                
                outputPipe.fileHandleForReading.readabilityHandler = { pipe in
                    let data = pipe.availableData
                    if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                        let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
                        if let lastLine = lines.last {
                            DispatchQueue.main.async {
                                self.liveDetailText = "[\(task.name)] \(lastLine)"
                            }
                        }
                    }
                }
                
                do {
                    try rsyncTask.run()
                    rsyncTask.waitUntilExit()
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                } catch {
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                }
            }
            
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            let timeString = formatter.string(from: Date())
            
            DispatchQueue.main.async {
                self.statusText = "✨ Sincronizzazione completata!"
                self.liveDetailText = "Tutti i task attivi sono aggiornati."
                self.lastSyncTime = timeString
                self.hasError = false
                self.isSyncing = false
            }
            self.log("Sincronizzazione completata con successo.")
        }
    }
}

// Delegato AppKit per gestire Status Item nativo e riuso sicuro delle finestre
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    
    var onboardingWindow: NSWindow?
    var settingsWindow: NSWindow?
    var logsWindow: NSWindow?
    let syncState = SyncState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "externaldrive.connected.to.line.below", accessibilityDescription: "NaSync")
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 380)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarMainView(syncState: syncState, appDelegate: self))
        
        if !syncState.hasCompletedOnboarding {
            showOnboardingWindow()
        }
    }

    @objc func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            let menu = NSMenu()
            
            let syncItem = NSMenuItem(title: "Sincronizza Ora", action: #selector(menuSyncNow), keyEquivalent: "")
            syncItem.target = self
            syncItem.isEnabled = !syncState.isSyncing && syncState.hasCompletedOnboarding
            menu.addItem(syncItem)
            
            menu.addItem(NSMenuItem.separator())
            
            let settingsItem = NSMenuItem(title: "Impostazioni...", action: #selector(menuOpenSettings), keyEquivalent: ",")
            settingsItem.target = self
            settingsItem.isEnabled = syncState.hasCompletedOnboarding
            menu.addItem(settingsItem)
            
            let logsItem = NSMenuItem(title: "Log di Attività...", action: #selector(menuOpenLogs), keyEquivalent: "l")
            logsItem.target = self
            menu.addItem(logsItem)
            
            menu.addItem(NSMenuItem.separator())
            
            let quitItem = NSMenuItem(title: "Esci", action: #selector(menuQuit), keyEquivalent: "q")
            quitItem.target = self
            menu.addItem(quitItem)
            
            statusItem.menu = menu
            sender.performClick(nil)
            statusItem.menu = nil
        } else {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                if let button = statusItem.button {
                    NSApp.activate(ignoringOtherApps: true)
                    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                }
            }
        }
    }

    @objc func menuSyncNow() {
        syncState.runAllSyncProcesses()
    }

    @objc func menuOpenSettings() {
        showSettingsWindow()
    }

    @objc func menuOpenLogs() {
        showLogsWindow()
    }

    @objc func menuQuit() {
        NSApplication.shared.terminate(nil)
    }

    func showOnboardingWindow() {
        if onboardingWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 720),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false
            )
            window.center()
            window.title = "Benvenuto in NaSync"
            window.contentView = NSHostingView(rootView: OnboardingWindowView(syncState: syncState, appDelegate: self))
            window.isReleasedWhenClosed = false
            onboardingWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    func showSettingsWindow() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 760),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false
            )
            window.center()
            window.title = "Impostazioni e Gestione NaSync"
            window.contentView = NSHostingView(rootView: SettingsWindowView(syncState: syncState, appDelegate: self))
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    
    func showLogsWindow() {
        if logsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 350),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false
            )
            window.center()
            window.title = "Log di Attività"
            window.contentView = NSHostingView(rootView: LogsWindowView(syncState: syncState, appDelegate: self))
            window.isReleasedWhenClosed = false
            logsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        logsWindow?.makeKeyAndOrderFront(nil)
    }
    
    func closeOnboardingWindow() {
        onboardingWindow?.close()
        onboardingWindow = nil
    }
    
    func closeSettingsWindow() {
        settingsWindow?.close()
    }
    
    func closeLogsWindow() {
        logsWindow?.close()
    }
}

@main
struct NaSyncApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

// ==========================================
// VISTA PRINCIPALE DELLA BARRA DEI MENU
// ==========================================
struct MenuBarMainView: View {
    @ObservedObject var syncState: SyncState
    var appDelegate: AppDelegate
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "server.rack")
                    .foregroundColor(.accentColor)
                Text("NaSync")
                    .font(.headline)
                Spacer()
                
                Button(action: { appDelegate.showLogsWindow() }) {
                    Image(systemName: "list.bullet.rectangle.portrait")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Visualizza ultimi log")
                
                if syncState.hasCompletedOnboarding {
                    Button(action: {
                        appDelegate.showSettingsWindow()
                    }) {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Impostazioni")
                }
                
                Circle()
                    .fill(syncState.hasError ? Color.red : (syncState.isSyncing ? Color.orange : (syncState.hasCompletedOnboarding ? Color.green : Color.gray)))
                    .frame(width: 8, height: 8)
            }
            
            Divider()
            
            if !syncState.hasCompletedOnboarding {
                VStack(alignment: .center, spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 24))
                        .foregroundColor(.accentColor)
                    
                    Text("Configurazione Richiesta")
                        .font(.subheadline)
                        .bold()
                    
                    Text("Configura il tuo NAS o ripristina un file di backup.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Apri Configurazione") {
                        appDelegate.showOnboardingWindow()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
            } else {
                if !syncState.checkFullDiskAccess() {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 14))
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Accesso disco mancante")
                                .font(.system(size: 11, weight: .bold))
                            Text("Necessario per rsync")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("Abilita") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                    .padding(6)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(6)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stato:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(syncState.statusText)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Attività in tempo reale:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    ScrollView {
                        Text(syncState.liveDetailText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 50)
                    .padding(6)
                    .background(Color(.textBackgroundColor).opacity(0.6))
                    .cornerRadius(6)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Elementi attivi (\(syncState.tasks.filter { $0.isEnabled }.count)):")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(syncState.tasks) { task in
                                HStack {
                                    Image(systemName: task.isEnabled ? "checkmark.circle.fill" : "pause.circle")
                                        .foregroundColor(task.isEnabled ? .green : .secondary)
                                    Text(task.name)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Spacer()
                                }
                            }
                        }
                    }
                    .frame(height: 40)
                    .padding(4)
                    .background(Color(.textBackgroundColor).opacity(0.3))
                    .cornerRadius(4)
                }
                
                HStack {
                    Text("Ultimo sync:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(syncState.lastSyncTime)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                Button(action: {
                    syncState.runAllSyncProcesses()
                }) {
                    HStack {
                        Spacer()
                        if syncState.isSyncing {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(height: 16)
                            Text("Sincronizzazione...")
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Sincronizza Ora")
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(syncState.isSyncing)
            }
            
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Text("Esci dall'app")
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(12)
        .frame(width: 280)
    }
}

extension SyncTask {
    func hasPrefixTilde() -> Bool { return localPath.hasPrefix("~") }
    func resolvedLocalPath() -> String {
        if localPath.hasPrefix("~") { return NSHomeDirectory() + localPath.dropFirst() }
        return localPath
    }
}

// ==========================================
// FINESTRA DEI LOG RECENTI
// ==========================================
struct LogsWindowView: View {
    @ObservedObject var syncState: SyncState
    var appDelegate: AppDelegate
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "list.bullet.rectangle.portrait.fill")
                    .foregroundColor(.accentColor)
                Text("Ultimi 10 Log di Attività")
                    .font(.headline)
                Spacer()
                Button("Chiudi") {
                    appDelegate.closeLogsWindow()
                }
                .buttonStyle(.borderedProminent)
            }
            
            Divider()
            
            if syncState.logs.isEmpty {
                Text("Nessun log registrato di recente.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(syncState.logs.reversed(), id: \.self) { log in
                            Text(log)
                                .font(.system(.caption, design: .monospaced))
                                .padding(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.textBackgroundColor).opacity(0.4))
                                .cornerRadius(4)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 440, height: 350)
    }
}

// ==========================================
// FINESTRA MODERNA DI SETUP / ONBOARDING
// ==========================================
struct OnboardingWindowView: View {
    @ObservedObject var syncState: SyncState
    var appDelegate: AppDelegate
    
    @State private var ipInput = ""
    @State private var shareInput = ""
    @State private var portInput = "445"
    @State private var userInput = ""
    @State private var passInput = ""
    
    @State private var taskName = ""
    @State private var localInput = ""
    @State private var remoteInput = ""
    @State private var errorMessage = ""
    @State private var showImporter = false
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Image(systemName: "externaldrive.connected.to.line.below.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)
                Text("Benvenuto in NaSync")
                    .font(.title2)
                    .bold()
                Text("Configura i parametri di connessione o ripristina un file di backup.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 10)
            
            Form {
                Section(header: Text("Opzione Rapida")) {
                    Button(action: { showImporter = true }) {
                        Label("Importa configurazione da Backup (JSON)", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.bordered)
                }
                
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 20))
                        Text("Ricorda di concedere l'**Accesso completo al disco** all'app in *Impostazioni di Sistema > Privacy e Sicurezza* affinché rsync possa leggere le cartelle protette.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                
                Section(header: Text("1. Connessione NAS (Universale)")) {
                    TextField("IP o Hostname (es. 192.168.1.50)", text: $ipInput)
                        .textFieldStyle(.roundedBorder)
                    TextField("Nome Cartella Condivisa (Share)", text: $shareInput)
                        .textFieldStyle(.roundedBorder)
                    TextField("Porta SMB (default 445)", text: $portInput)
                        .textFieldStyle(.roundedBorder)
                }
                
                Section(header: Text("2. Credenziali SMB (Opzionali)")) {
                    TextField("Username NAS", text: $userInput)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Password NAS", text: $passInput)
                        .textFieldStyle(.roundedBorder)
                }
                
                Section(header: Text("3. Prima Cartella da Sincronizzare")) {
                    TextField("Nome Cartella (es. Università)", text: $taskName)
                        .textFieldStyle(.roundedBorder)
                    TextField("Percorso Locale (es. ~/Desktop/Uni/)", text: $localInput)
                        .textFieldStyle(.roundedBorder)
                    TextField("Percorso Remoto sul NAS (es. /Uni/)", text: $remoteInput)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .formStyle(.grouped)
            
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            Button(action: {
                guard !ipInput.isEmpty, !shareInput.isEmpty, !taskName.isEmpty, !localInput.isEmpty, !remoteInput.isEmpty else {
                    errorMessage = "Per favore compila i campi essenziali o usa l'importazione JSON."
                    return
                }
                
                syncState.tailscaleIP = ipInput
                syncState.nasShareName = shareInput
                syncState.smbPort = portInput.isEmpty ? "445" : portInput
                syncState.nasUsername = userInput
                syncState.nasPassword = passInput
                
                let initialTask = SyncTask(name: taskName, localPath: localInput, remoteSubpath: remoteInput, isEnabled: true)
                syncState.tasks = [initialTask]
                
                syncState.hasCompletedOnboarding = true
                syncState.log("Configurazione iniziale completata.")
                appDelegate.closeOnboardingWindow()
            }) {
                Text("Salva e Inizia a Usare l'App")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            Spacer()
        }
        .padding(24)
        .frame(width: 480, height: 720)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let fileURL = try result.get().first else { return }
                if fileURL.startAccessingSecurityScopedResource() {
                    defer { fileURL.stopAccessingSecurityScopedResource() }
                    let data = try Data(contentsOf: fileURL)
                    if syncState.importBackupData(from: data) {
                        appDelegate.closeOnboardingWindow()
                    }
                }
            } catch {
                syncState.log("Errore importazione backup in onboarding: \(error.localizedDescription)")
            }
        }
    }
}

// ==========================================
// FINESTRA DI GESTIONE E IMPOSTAZIONI
// ==========================================
struct SettingsWindowView: View {
    @ObservedObject var syncState: SyncState
    var appDelegate: AppDelegate
    
    @State private var newName = ""
    @State private var newLocal = "~/Desktop/"
    @State private var newRemote = "/Backup/"
    
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var exportedData: Data? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "gearshape.fill")
                    .foregroundColor(.accentColor)
                Text("Impostazioni e Gestione NaSync")
                    .font(.headline)
                Spacer()
                Button("Salva e Chiudi") {
                    appDelegate.closeSettingsWindow()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            
            Form {
                Section(header: Text("Verifica Permessi macOS")) {
                    HStack {
                        Text("Accesso completo al disco:")
                        Spacer()
                        if syncState.checkFullDiskAccess() {
                            Label("Concesso", systemImage: "checkmark.seal.fill")
                                .foregroundColor(.green)
                        } else {
                            Label("Non Concesso", systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                        }
                    }
                    
                    Button("Apri Impostazioni di Privacy macOS") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                
                Section(header: Text("Parametri di Rete NAS e Porta")) {
                    TextField("IP o Hostname del NAS", text: $syncState.tailscaleIP)
                    TextField("Nome Cartella Condivisa (Share)", text: $syncState.nasShareName)
                    TextField("Porta SMB (default 445)", text: $syncState.smbPort)
                }
                
                Section(header: Text("Credenziali SMB (Opzionali)")) {
                    TextField("Username NAS", text: $syncState.nasUsername)
                    SecureField("Password NAS", text: $syncState.nasPassword)
                }
                
                Section(header: Text("Cartelle Sincronizzate")) {
                    List {
                        ForEach($syncState.tasks) { $task in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    TextField("Nome", text: $task.name)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 140)
                                    
                                    Spacer()
                                    
                                    Toggle("Attivo", isOn: $task.isEnabled)
                                }
                                
                                TextField("Percorso Locale", text: $task.localPath)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption)
                                
                                TextField("Percorso Remoto", text: $task.remoteSubpath)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption)
                            }
                            .padding(.vertical, 6)
                        }
                        .onDelete { indexSet in
                            syncState.tasks.remove(atOffsets: indexSet)
                        }
                    }
                    .frame(height: 160)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Aggiungi nuova cartella di sync").font(.subheadline).bold()
                        HStack {
                            TextField("Nome", text: $newName)
                                .textFieldStyle(.roundedBorder)
                            TextField("Locale (~/...)", text: $newLocal)
                                .textFieldStyle(.roundedBorder)
                            TextField("Remoto (/...)", text: $newRemote)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        Button(action: {
                            guard !newName.isEmpty else { return }
                            let task = SyncTask(name: newName, localPath: newLocal, remoteSubpath: newRemote, isEnabled: true)
                            syncState.tasks.append(task)
                            syncState.log("Aggiunto nuovo task: \(newName)")
                            newName = ""
                        }) {
                            Label("Aggiungi alla lista", systemImage: "plus.circle.fill")
                        }
                        .padding(.top, 2)
                    }
                }
                
                Section(header: Text("Backup e Ripristino Configurazione")) {
                    HStack {
                        Button("Esporta Backup (JSON)") {
                            exportedData = syncState.exportBackupData()
                            showExporter = true
                        }
                        
                        Button("Ripristina da Backup") {
                            showImporter = true
                        }
                    }
                }
                
                Section {
                    Button(role: .destructive, action: {
                        syncState.resetAllData()
                        appDelegate.closeSettingsWindow()
                        appDelegate.showOnboardingWindow()
                    }) {
                        Label("Ripristina tutto (Cancellazione totale e Reset)", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 520, height: 760)
        .padding()
        .fileExporter(
            isPresented: $showExporter,
            document: BackupDocument(data: exportedData),
            contentType: .json,
            defaultFilename: "NaSync_Backup.json"
        ) { result in
            if case .success = result {
                syncState.log("Backup esportato con successo.")
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let fileURL = try result.get().first else { return }
                if fileURL.startAccessingSecurityScopedResource() {
                    defer { fileURL.stopAccessingSecurityScopedResource() }
                    let data = try Data(contentsOf: fileURL)
                    _ = syncState.importBackupData(from: data)
                    appDelegate.closeSettingsWindow()
                }
            } catch {
                syncState.log("Errore importazione backup: \(error.localizedDescription)")
            }
        }
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data?

    init(data: Data?) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: data ?? Data())
    }
}
