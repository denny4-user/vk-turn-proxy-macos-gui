import SwiftUI
import Network
import Foundation

// MARK: - Модели данных для GitHub API
struct GitHubRelease: Codable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let tag_name: String
    let assets: [GitHubAsset]
}

struct GitHubAsset: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let browser_download_url: String
}

// MARK: - Главный экран
struct ContentView: View {
    // Сохраняемые настройки (@AppStorage)
    @AppStorage("savedRepos") var savedReposString: String = "https://github.com/alexmac6574/vk-turn-proxy"
    @AppStorage("selectedRepo") var selectedRepo: String = "https://github.com/alexmac6574/vk-turn-proxy"
    
    @AppStorage("listenAddress") var listenAddress: String = "127.0.0.1:9000"
    @AppStorage("connectionsNum") var connectionsNum: String = "4"
    @AppStorage("peerAddress") var peerAddress: String = ""
    @AppStorage("turnPort") var turnPort: String = ""
    @AppStorage("turnIP") var turnIP: String = ""
    @AppStorage("vkLink") var vkLink: String = ""
    
    @AppStorage("protocolMode") var protocolMode: String = "UDP"
    @AppStorage("noDTLS") var noDTLS: Bool = false
    @AppStorage("customParams") var customParams: String = ""
    
    // Переменные состояния
    @State private var statusMessage: String = "Готов к работе"
    @State private var isRunning: Bool = false
    @State private var currentProcess: Process?
    @State private var consoleOutput: String = ""
    @State private var showAdvanced: Bool = false
    
    // Таймер и счетчик для мониторинга порта
    @State private var portCheckTimer: Timer?
    @State private var checkAttempts: Int = 0
    
    // Состояния для работы с GitHub
    @State private var newRepoURL: String = ""
    @State private var releases: [GitHubRelease] = []
    @State private var selectedRelease: GitHubRelease? = nil
    @State private var selectedAsset: GitHubAsset? = nil
    @State private var isFetchingReleases = false
    
    // Состояния для проверки порта и Alert
    @State private var showPortConflictAlert: Bool = false
    @State private var conflictPort: String = ""
    @State private var conflictingPID: String = ""
    @State private var conflictingProcessName: String = ""

    // Вычисляемое свойство для получения массива
    var savedReposArray: [String] {
        savedReposString.components(separatedBy: ",").filter { !$0.isEmpty }
    }
    
    // Константа для ровного выравнивания заголовков полей
    let labelWidth: CGFloat = 140

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - ОСНОВНОЙ КОНТЕНТ ПРОКРУТКИ
            ScrollView {
                VStack(spacing: 24) {
                    
                    // СЕКЦИЯ 1: ЯДРО ПРОКСИ
                    GroupBox(label: Label("Управление ядром (GitHub)", systemImage: "shippingbox.fill").foregroundColor(.secondary)) {
                        VStack(spacing: 12) {
                            
                            // Добавление нового репо
                            HStack {
                                Text("Добавить репо:")
                                    .frame(width: labelWidth, alignment: .trailing)
                                    .foregroundColor(.secondary)
                                HStack {
                                    TextField("https://github.com/...", text: $newRepoURL)
                                        .textFieldStyle(.roundedBorder)
                                    Button(action: { addRepository(newRepoURL) }) {
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundColor(isValidGitHubRepoURL(newRepoURL) ? .blue : .secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!isValidGitHubRepoURL(newRepoURL))
                                }
                            }
                            
                            // Выбор репо
                            if !savedReposArray.isEmpty {
                                HStack {
                                    Text("Исходник:")
                                        .frame(width: labelWidth, alignment: .trailing)
                                        .foregroundColor(.secondary)
                                    Picker("", selection: $selectedRepo) {
                                        ForEach(savedReposArray, id: \.self) { repo in
                                            Text(repo).tag(repo)
                                        }
                                    }
                                    .labelsHidden()
                                    .onChange(of: selectedRepo) { newValue in
                                        fetchReleases(for: newValue)
                                    }
                                }
                            }
                            
                            // Выбор релиза
                            HStack {
                                Text("Версия релиза:")
                                    .frame(width: labelWidth, alignment: .trailing)
                                    .foregroundColor(.secondary)
                                
                                if isFetchingReleases {
                                    ProgressView().scaleEffect(0.5).frame(height: 10)
                                    Spacer()
                                } else if !releases.isEmpty {
                                    Picker("", selection: $selectedRelease) {
                                        ForEach(releases, id: \.id) { release in
                                            Text(release.tag_name).tag(Optional(release))
                                        }
                                    }
                                    .labelsHidden()
                                    .onChange(of: selectedRelease) { _ in selectedAsset = nil }
                                } else {
                                    Text("Нет данных").foregroundColor(.red).font(.callout)
                                    Spacer()
                                }
                            }
                            
                            // Список файлов
                            if let release = selectedRelease {
                                let filteredAssets = release.assets.filter { !$0.name.hasSuffix(".zip") && !$0.name.hasSuffix(".tar.gz") }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Доступные файлы:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.leading, labelWidth + 8)
                                    
                                    HStack {
                                        Spacer().frame(width: labelWidth)
                                        
                                        ScrollView {
                                            VStack(spacing: 2) {
                                                ForEach(filteredAssets, id: \.id) { asset in
                                                    let isTarget = asset.name.contains("client-darwin-arm64")
                                                    let isSelected = selectedAsset == asset
                                                    
                                                    HStack {
                                                        Image(systemName: isTarget ? "bolt.fill" : "doc.zipper")
                                                            .foregroundColor(isSelected ? .white : (isTarget ? .green : .secondary))
                                                        Text(asset.name)
                                                            .foregroundColor(isSelected ? .white : (isTarget ? .green : .primary))
                                                            .fontWeight(isTarget ? .bold : .regular)
                                                        Spacer()
                                                        if isSelected {
                                                            Image(systemName: "checkmark").foregroundColor(.white)
                                                        }
                                                    }
                                                    .padding(.vertical, 6)
                                                    .padding(.horizontal, 10)
                                                    .background(isSelected ? Color.accentColor : Color.clear)
                                                    .cornerRadius(6)
                                                    .contentShape(Rectangle())
                                                    .onTapGesture { selectedAsset = asset }
                                                }
                                            }
                                            .padding(4)
                                        }
                                        .frame(height: 110)
                                        .background(Color(NSColor.controlBackgroundColor))
                                        .cornerRadius(8)
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                                    }
                                }
                            }
                            
                            // Кнопка загрузки
                            HStack {
                                Spacer().frame(width: labelWidth)
                                Button(action: {
                                    if let asset = selectedAsset { downloadAndSetPermissions(from: asset.browser_download_url) }
                                }) {
                                    Label("Скачать и обновить ядро", systemImage: "square.and.arrow.down.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(selectedAsset == nil)
                                .padding(.top, 4)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // СЕКЦИЯ 2: ПАРАМЕТРЫ ЗАПУСКА
                    GroupBox(label: Label("Параметры подключения", systemImage: "network").foregroundColor(.secondary)) {
                        VStack(spacing: 12) {
                            buildRow(label: "Локальный адрес", text: $listenAddress, prompt: "127.0.0.1:9000")
                            buildRow(label: "Соединения", text: $connectionsNum, prompt: "4 (для VK ≈ 10)")
                            buildRow(label: "Адрес пира", text: $peerAddress, prompt: "host:port")
                            buildRow(label: "Ссылка на ВК", text: $vkLink, prompt: "https://vk.com/call/join/...")
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // СЕКЦИЯ 3: ДОПОЛНИТЕЛЬНО
                    GroupBox {
                        VStack(spacing: 12) {
                            HStack {
                                Text("Режим работы:")
                                    .frame(width: labelWidth, alignment: .trailing)
                                    .foregroundColor(.secondary)
                                Picker("", selection: $protocolMode) {
                                    Text("По умолчанию").tag("Пусто")
                                    Text("UDP").tag("UDP")
                                    Text("TCP").tag("TCP")
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                            }
                            
                            DisclosureGroup(isExpanded: $showAdvanced) {
                                VStack(spacing: 12) {
                                    Divider().padding(.vertical, 4)
                                    buildRow(label: "Порт TURN", text: $turnPort, prompt: "Переопределить порт (-port)")
                                    buildRow(label: "IP TURN", text: $turnIP, prompt: "Переопределить IP (-turn)")
                                    buildRow(label: "Свои параметры", text: $customParams, prompt: "Например: --help")
                                    
                                    HStack {
                                        Spacer().frame(width: labelWidth)
                                        Toggle("Без обфускации (-no-dtls)", isOn: $noDTLS)
                                            .foregroundColor(.red)
                                        Spacer()
                                    }
                                    
                                    HStack {
                                        Spacer().frame(width: labelWidth)
                                        Button(role: .destructive, action: resetCache) {
                                            Label("Сбросить настройки", systemImage: "trash")
                                        }
                                        Spacer()
                                    }
                                    .padding(.top, 8)
                                }
                            } label: {
                                Text("Продвинутые настройки").fontWeight(.medium)
                            }
                            .accentColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // СЕКЦИЯ 4: КОНСОЛЬ
                    GroupBox(label: Label("Журнал событий", systemImage: "terminal.fill").foregroundColor(.secondary)) {
                        ScrollViewReader { proxy in
                            ScrollView {
                                Text(consoleOutput)
                                    .font(.system(.footnote, design: .monospaced))
                                    .foregroundColor(.green)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .id("ConsoleBottom")
                            }
                            .frame(height: 160)
                            .background(Color.black)
                            .cornerRadius(6)
                            .overlay(alignment: .topTrailing) {
                                Button(action: copyToClipboard) {
                                    Image(systemName: "doc.on.doc")
                                        .foregroundColor(.white.opacity(0.8))
                                        .padding(8)
                                        .background(Color.white.opacity(0.1))
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                .padding(8)
                            }
                            .onChange(of: consoleOutput) {
                                proxy.scrollTo("ConsoleBottom", anchor: .bottom)
                            }
                        }
                    }
                }
                .padding(20)
            }
            
            Divider()
            
            // MARK: - ЗАКРЕПЛЕННАЯ НИЖНЯЯ ПАНЕЛЬ (STATUS BAR)
            HStack(spacing: 20) {
                // Статус
                HStack(spacing: 8) {
                    Circle()
                        .fill(isRunning ? Color.green : Color.gray.opacity(0.5))
                        .frame(width: 10, height: 10)
                        .shadow(color: isRunning ? .green : .clear, radius: 3)
                    
                    Text(statusMessage)
                        .font(.subheadline)
                        .foregroundColor(isRunning ? .primary : .secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Кнопки управления
                Button(action: checkPortAndStartProxy) {
                    Label("Запустить", systemImage: "play.fill")
                        .padding(.horizontal, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)
                .disabled(isRunning)
                
                Button(action: stopProxy) {
                    Label("Остановить", systemImage: "stop.fill")
                        .padding(.horizontal, 10)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!isRunning)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.95))
        }
        .frame(minWidth: 650, minHeight: 850)
        .onAppear {
            if !selectedRepo.isEmpty { fetchReleases(for: selectedRepo) }
        }
        // MARK: - Alert при конфликте портов
        .alert("Порт \(conflictPort) занят", isPresented: $showPortConflictAlert) {
            Button("Завершить процесс", role: .destructive) {
                killConflictingProcessAndStart()
            }
            Button("Отмена", role: .cancel) {
                statusMessage = "Запуск отменён"
            }
        } message: {
            Text("Процесс \"\(conflictingProcessName)\" (PID: \(conflictingPID)) уже использует этот порт.\nЗавершить его принудительно и запустить прокси?")
        }
    }
    
    // Вспомогательный метод для создания ровных полей ввода
    private func buildRow(label: String, text: Binding<String>, prompt: String) -> some View {
        HStack {
            Text("\(label):")
                .frame(width: labelWidth, alignment: .trailing)
                .foregroundColor(.secondary)
            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
    
    // MARK: - Вспомогательный метод для выполнения Shell команд
    func shell(_ command: String) -> String {
        let task = Process()
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        try? task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    
    // MARK: - Валидация URL
    func isValidGitHubRepoURL(_ urlString: String) -> Bool {
        let cleanURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: cleanURL),
              let host = url.host,
              host.contains("github.com") else { return false }
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        return pathComponents.count >= 2
    }
    
    // MARK: - Логика GitHub
    func addRepository(_ url: String) {
        var cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanURL.hasSuffix("/") { cleanURL.removeLast() }
        guard isValidGitHubRepoURL(cleanURL), !savedReposArray.contains(cleanURL) else { return }
        
        var currentRepos = savedReposArray
        currentRepos.append(cleanURL)
        savedReposString = currentRepos.joined(separator: ",")
        selectedRepo = cleanURL
        newRepoURL = ""
        fetchReleases(for: cleanURL)
    }
    
    func fetchReleases(for urlString: String) {
        guard let url = URL(string: urlString), let host = url.host, host.contains("github.com") else {
            statusMessage = "Укажите корректную ссылку на GitHub"
            return
        }
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard pathComponents.count >= 2 else {
            statusMessage = "Неверный формат ссылки"
            return
        }
        let owner = pathComponents[0]
        var repo = pathComponents[1]
        if repo.hasSuffix(".git") { repo = String(repo.dropLast(4)) }
        let apiURLString = "https://api.github.com/repos/\(owner)/\(repo)/releases?per_page=10"
        guard let apiURL = URL(string: apiURLString) else { return }
        
        isFetchingReleases = true
        statusMessage = "Получение релизов..."
        
        Task {
            do {
                var request = URLRequest(url: apiURL)
                request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    DispatchQueue.main.async {
                        self.statusMessage = "Ошибка API (Код: \(httpResponse.statusCode))"
                        self.isFetchingReleases = false
                        self.releases = []
                    }
                    return
                }
                let fetchedReleases = try JSONDecoder().decode([GitHubRelease].self, from: data)
                DispatchQueue.main.async {
                    self.releases = fetchedReleases
                    self.selectedRelease = fetchedReleases.first
                    self.selectedAsset = nil
                    self.isFetchingReleases = false
                    self.statusMessage = "Релизы загружены"
                    if let firstRelease = fetchedReleases.first,
                       let targetAsset = firstRelease.assets.first(where: { $0.name.contains("client-darwin-arm64") }) {
                        self.selectedAsset = targetAsset
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.statusMessage = "Ошибка загрузки: \(error.localizedDescription)"
                    self.isFetchingReleases = false
                    self.releases = []
                }
            }
        }
    }
    
    // MARK: - Вспомогательные функции
    func resetCache() {
        savedReposString = "https://github.com/alexmac6574/vk-turn-proxy"
        selectedRepo = "https://github.com/alexmac6574/vk-turn-proxy"
        listenAddress = "127.0.0.1:9000"
        connectionsNum = "4"
        peerAddress = ""
        turnPort = ""
        turnIP = ""
        vkLink = ""
        protocolMode = "UDP"
        noDTLS = false
        customParams = ""
        selectedAsset = nil
        fetchReleases(for: selectedRepo)
        statusMessage = "Кэш очищен и сброшен"
    }
    
    func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(consoleOutput, forType: .string)
        let oldStatus = statusMessage
        statusMessage = "Логи скопированы!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.statusMessage = oldStatus }
    }
    
    func downloadAndSetPermissions(from downloadURLString: String) {
        guard let url = URL(string: downloadURLString) else {
            statusMessage = "Ошибка: неверная ссылка"
            return
        }
        statusMessage = "Скачивание ядра..."
        Task {
            do {
                let (tempURL, _) = try await URLSession.shared.download(from: url)
                let docsFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let destinationURL = docsFolder.appendingPathComponent("client-darwin-arm64")
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationURL.path)
                DispatchQueue.main.async { statusMessage = "Ядро успешно скачано!" }
            } catch {
                DispatchQueue.main.async { statusMessage = "Ошибка: \(error.localizedDescription)" }
            }
        }
    }
    
    // MARK: - Мониторинг порта (Apple Network Framework)
    func monitorPort(host: String, port: UInt16) {
        checkAttempts = 0
        portCheckTimer?.invalidate()
        statusMessage = "Ожидание порта \(port)..."
        
        let queue = DispatchQueue(label: "PortMonitorQueue")
        
        portCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            self.checkAttempts += 1
            
            // Если за 5 секунд (10 попыток) ядро так и не открыло TCP порт
            if self.checkAttempts > 10 {
                timer.invalidate()
                DispatchQueue.main.async {
                    if self.isRunning {
                        // Фолбэк: если процесс жив, считаем что всё ок (например, порт только UDP)
                        self.statusMessage = "Прокси работает (порт \(port))"
                    }
                }
                return
            }
            
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.connectionTimeout = 1 // Быстрый таймаут чтобы не вешать приложение
            let parameters = NWParameters(tls: nil, tcp: tcpOptions)
            
            let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: parameters)
            
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    timer.invalidate() // Ура, порт открыт!
                    DispatchQueue.main.async {
                        if self.isRunning {
                            self.statusMessage = "Подключено к \(host):\(port) 🟢"
                        }
                    }
                    connection.cancel()
                case .failed(_), .cancelled:
                    // Порт закрыт, повторяем попытку на следующем тике таймера
                    connection.cancel()
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }
    
    // MARK: - Логика проверки портов и запуска
    
    func checkPortAndStartProxy() {
        // Парсим порт из listenAddress (например из 127.0.0.1:9000 достаем 9000)
        let components = listenAddress.split(separator: ":")
        guard components.count == 2, let portStr = components.last else {
            // Если формат нестандартный, просто запускаем
            performStartProxy()
            return
        }
        
        let port = String(portStr)
        statusMessage = "Проверка порта \(port)..."
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Используем утилиту lsof (list open files) для поиска PID процесса слушающего порт
            // Флаг -t выводит только PID, флаг -i :port фильтрует по порту
            let pidOutput = self.shell("/usr/sbin/lsof -t -i :\(port) | head -n 1")
            
            DispatchQueue.main.async {
                if !pidOutput.isEmpty {
                    // Порт занят! Узнаем имя процесса
                    let processPath = self.shell("/bin/ps -p \(pidOutput) -o comm= | head -n 1")
                    let processName = (processPath as NSString).lastPathComponent // Берем только само имя без путей
                    
                    self.conflictingPID = pidOutput
                    self.conflictingProcessName = processName.isEmpty ? "Неизвестный процесс" : processName
                    self.conflictPort = port
                    self.showPortConflictAlert = true // Вызываем Alert
                } else {
                    // Порт свободен, стартуем
                    self.performStartProxy()
                }
            }
        }
    }
    
    func killConflictingProcessAndStart() {
        if !conflictingPID.isEmpty {
            statusMessage = "Убиваем процесс \(conflictingPID)..."
            _ = shell("kill -9 \(conflictingPID)")
            
            // Даем системе полсекунды на освобождение сокета
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.performStartProxy()
            }
        }
    }
    
    func performStartProxy() {
        let docsFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let executableURL = docsFolder.appendingPathComponent("client-darwin-arm64")
        guard FileManager.default.fileExists(atPath: executableURL.path) else {
            statusMessage = "Ядро не найдено! Сначала скачайте его."
            return
        }
        
        var args: [String] = []
        if !listenAddress.isEmpty { args.append(contentsOf: ["-listen", listenAddress]) }
        if !connectionsNum.isEmpty { args.append(contentsOf: ["-n", connectionsNum]) }
        if !peerAddress.isEmpty { args.append(contentsOf: ["-peer", peerAddress]) }
        if !vkLink.isEmpty { args.append(contentsOf: ["-vk-link", vkLink]) }
        if !turnPort.isEmpty { args.append(contentsOf: ["-port", turnPort]) }
        if !turnIP.isEmpty { args.append(contentsOf: ["-turn", turnIP]) }
        if protocolMode == "UDP" { args.append("-udp") }
        else if protocolMode == "TCP" { args.append("-tcp") }
        if noDTLS { args.append("-no-dtls") }
        if !customParams.isEmpty {
            let parsedCustomArgs = customParams.split(separator: " ").map { String($0) }
            args.append(contentsOf: parsedCustomArgs)
        }
        
        let process = Process()
        process.executableURL = executableURL
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        consoleOutput = "--- Запуск ядра ---\n"
        
        // Теперь мы просто читаем логи, без поиска костыльных строк
        pipe.fileHandleForReading.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            if data.isEmpty { return }
            if let str = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self.consoleOutput += str
                }
            }
        }
        
        do {
            try process.run()
            currentProcess = process
            isRunning = true
            
            // Вытаскиваем хост и порт из строки и запускаем мониторинг
            let components = listenAddress.split(separator: ":")
            if components.count == 2, let host = components.first.map(String.init), let port = UInt16(components[1]) {
                monitorPort(host: host, port: port)
            } else {
                statusMessage = "Запущено (нестандартный адрес)"
            }
            
            process.terminationHandler = { _ in
                pipe.fileHandleForReading.readabilityHandler = nil
                DispatchQueue.main.async {
                    self.portCheckTimer?.invalidate() // Очищаем таймер если процесс упал
                    self.isRunning = false
                    self.statusMessage = "Остановлен"
                    self.consoleOutput += "\n--- Процесс завершен ---\n"
                }
            }
        } catch {
            statusMessage = "Ошибка запуска: \(error.localizedDescription)"
        }
    }
    
    func stopProxy() {
        portCheckTimer?.invalidate() // Очищаем таймер при ручной остановке
        currentProcess?.terminate()
        isRunning = false
        statusMessage = "Остановлен пользователем"
    }
}
