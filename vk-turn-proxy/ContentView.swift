import SwiftUI

// MARK: - Главный экран
struct ContentView: View {
    // Сохраняемые настройки (@AppStorage)
    @AppStorage("coreURL") var coreURL: String = "https://github.com/alexmac6574/vk-turn-proxy/releases/latest/download/client-darwin-arm64"
    
    @AppStorage("listenAddress") var listenAddress: String = "127.0.0.1:9000"
    @AppStorage("connectionsNum") var connectionsNum: String = "4"
    @AppStorage("peerAddress") var peerAddress: String = ""
    @AppStorage("turnPort") var turnPort: String = ""
    @AppStorage("turnIP") var turnIP: String = ""
    @AppStorage("vkLink") var vkLink: String = ""
    
    @AppStorage("protocolMode") var protocolMode: String = "UDP" // Заменили useUDP на режим протокола
    @AppStorage("noDTLS") var noDTLS: Bool = false
    @AppStorage("customParams") var customParams: String = "" // Для своих параметров
    
    // Переменные состояния
    @State private var statusMessage: String = "Готов к работе"
    @State private var isRunning: Bool = false
    @State private var currentProcess: Process?
    @State private var consoleOutput: String = ""
    @State private var showAdvanced: Bool = false // Меню "Дополнительно"

    var body: some View {
        VStack {
            Form {
                // СЕКЦИЯ 1: Скачивание ядра
                Section(header: Text("Ядро (client-darwin-arm64)")) {
                    TextField("URL загрузки", text: $coreURL, prompt: Text("Ссылка на бинарный файл"))
                    Button("Скачать и обновить ядро") {
                        downloadAndSetPermissions()
                    }
                }
                
                // СЕКЦИЯ 2: Основные параметры
                Section(header: Text("Параметры запуска")) {
                    TextField("Локальный адрес", text: $listenAddress, prompt: Text("Например: 127.0.0.1:9000 (параметр -listen)"))
                    TextField("Соединения", text: $connectionsNum, prompt: Text("Кол-во: 1 ≈ 5 мбит (параметр -n)"))
                    TextField("Адрес пира", text: $peerAddress, prompt: Text("host:port (параметр -peer)"))
                    TextField("Ссылка на ВК", text: $vkLink, prompt: Text("https://vk.com/call/join/... (параметр -vk-link)"))
                }
                
                // СЕКЦИЯ 3: Чекбоксы (Флаги) и Дополнительно
                Section(header: Text("Флаги и Дополнительно")) {
                    Picker("Режим работы", selection: $protocolMode) {
                        Text("Пусто")
                            .tag("Пусто")
                            .help("Без флага (по умолчанию)")
                        
                        Text("UDP")
                            .tag("UDP")
                            .help("Для wireguard протокола")
                        
                        Text("TCP")
                            .tag("TCP")
                            .help("Для VLESS и др. протоколов")
                    }
                    .pickerStyle(.segmented)
                    
                    Toggle("Показать дополнительные настройки", isOn: $showAdvanced.animation())
                    
                    if showAdvanced {
                        TextField("Порт TURN", text: $turnPort, prompt: Text("Переопределить порт (параметр -port)"))
                        TextField("IP TURN", text: $turnIP, prompt: Text("Переопределить IP (параметр -turn)"))
                        Toggle("Без обфускации (-no-dtls, может привести к блокировке)", isOn: $noDTLS)
                        TextField("Свои параметры", text: $customParams, prompt: Text("Например: --help"))
                        
                        Divider() // Визуальный разделитель
                        
                        // КНОПКА СБРОСА КЭША
                        Button(action: resetCache) {
                            Text("Сбросить кэш (очистить поля)")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .padding()
            
            // КОНСОЛЬ ВЫВОДА
            ScrollViewReader { proxy in
                ScrollView {
                    Text(consoleOutput)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .id("ConsoleBottom")
                }
                .background(Color.black)
                .cornerRadius(8)
                // ДОБАВЛЯЕМ КНОПКУ КОПИРОВАНИЯ ПОВЕРХ КОНСОЛИ
                .overlay(alignment: .topTrailing) {
                    Button(action: copyToClipboard) {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain) // Убираем стандартную серую рамку кнопки macOS
                    .padding(8)
                    .help("Скопировать логи") // Подсказка при наведении мыши
                }
                .padding(.horizontal)
                .frame(height: 200) // Высота окошка консоли
                .onChange(of: consoleOutput) {
                    proxy.scrollTo("ConsoleBottom", anchor: .bottom)
                }
            }
            
            // СТАТУС И КНОПКИ УПРАВЛЕНИЯ
            VStack(spacing: 15) {
                Text("Статус: \(statusMessage)")
                    .foregroundColor(isRunning ? .green : .primary)
                    .bold()
                
                HStack(spacing: 20) {
                    Button(action: startProxy) {
                        Text("Запустить прокси")
                            .frame(width: 150)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRunning)
                    
                    Button(action: stopProxy) {
                        Text("Остановить")
                            .frame(width: 150)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!isRunning)
                }
            }
            .padding(.bottom, 20)
        }
        .frame(width: 600, height: 850) // Увеличили общую высоту окна
    }
    
    // MARK: - Логика сброса кэша
    func resetCache() {
        // Возвращаем все переменные к их дефолтным значениям
        coreURL = "https://github.com/alexmac6574/vk-turn-proxy/releases/latest/download/client-darwin-arm64"
        listenAddress = "127.0.0.1:9000"
        connectionsNum = "4"
        peerAddress = ""
        turnPort = ""
        turnIP = ""
        vkLink = ""
        protocolMode = "UDP"
        noDTLS = false
        customParams = ""
        
        statusMessage = "Кэш очищен и сброшен"
    }
    
    // MARK: - Логика копирования в буфер обмена (Только для macOS)
    func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents() // Обязательно сначала очистить
        pasteboard.setString(consoleOutput, forType: .string) // Положить наш текст
        
        // Маленький визуальный фидбек, чтобы пользователь понял, что скопировалось
        let oldStatus = statusMessage
        statusMessage = "Логи скопированы!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.statusMessage = oldStatus
        }
    }
    
    // MARK: - Логика скачивания
    func downloadAndSetPermissions() {
        guard let url = URL(string: coreURL) else {
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
                
                DispatchQueue.main.async {
                    statusMessage = "Ядро скачано в Документы и готово!"
                }
            } catch {
                DispatchQueue.main.async {
                    statusMessage = "Ошибка скачивания: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Логика запуска
    func startProxy() {
        let docsFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let executableURL = docsFolder.appendingPathComponent("client-darwin-arm64")
        
        guard FileManager.default.fileExists(atPath: executableURL.path) else {
            statusMessage = "Ядро не найдено! Нажмите кнопку 'Скачать'."
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
        
        // Добавляем свои параметры, разбивая строку по пробелам
        if !customParams.isEmpty {
            let parsedCustomArgs = customParams.split(separator: " ").map { String($0) }
            args.append(contentsOf: parsedCustomArgs)
        }
        
        let process = Process()
        process.executableURL = executableURL
        process.arguments = args
        
        // Настраиваем перехват вывода в консоль
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        consoleOutput = "--- Запуск ядра ---\n"
        
        // Читаем данные по мере их поступления
        pipe.fileHandleForReading.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            if data.isEmpty { return }
            if let str = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self.consoleOutput += str
                    
                    // Отслеживаем фразу об успешном подключении
                    if str.contains("Established DTLS connection!") {
                        self.statusMessage = "Прокси запущен на \(self.listenAddress)"
                    }
                }
            }
        }
        
        do {
            try process.run()
            currentProcess = process
            isRunning = true
            statusMessage = "Запуск ядра..."
            
            process.terminationHandler = { _ in
                // Обязательно отключаем чтение при завершении процесса
                pipe.fileHandleForReading.readabilityHandler = nil
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.statusMessage = "Процесс завершен"
                    self.consoleOutput += "\n--- Процесс завершен ---\n"
                }
            }
        } catch {
            statusMessage = "Ошибка запуска: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Логика остановки
    func stopProxy() {
        currentProcess?.terminate()
        isRunning = false
        statusMessage = "Остановлен пользователем"
    }
}
