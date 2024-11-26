//
//  ContentView.swift
//  Encryptify
//
//  Created by Eran Straub on 11/25/24.
//
import SwiftUI

// Define a struct for file history
struct FileHistoryItem: Codable, Equatable, Identifiable {
    var id: UUID = UUID() // Unique identifier for each item
    let fileName: String
    let action: String
    let algorithm: String
}

struct ContentView: View {
    @State private var inputFile: URL?
    @State private var inputFolder: URL?
    @State private var passphrase: String = ""
    @State private var iterations: String = ""
    @State private var encryptionStatus: String = ""
    @State private var fileHistory: [FileHistoryItem] = []
    @AppStorage("lastUsedAlgorithm") private var lastUsedAlgorithm: String = "aes-256-cbc"

    let algorithms: [String: String] = [
        "aes-256-cbc": "AES-256-CBC (default, highly secure)",
        "aes-128-cbc": "AES-128-CBC (faster, less secure than 256-bit)",
        "des-cbc": "DES-CBC (legacy, not recommended)",
        "bf-cbc": "Blowfish-CBC (legacy, not recommended)",
        "aes-256-ecb": "AES-256-ECB (not recommended, no IV support)"
    ]

    var body: some View {
        VStack(spacing: 20) {
            Button("Select File or Folder") {
                selectInput()
            }

            if let inputFile = inputFile {
                Text("Selected File: \(inputFile.lastPathComponent)")
            } else if let inputFolder = inputFolder {
                Text("Selected Folder: \(inputFolder.lastPathComponent)")
            }

            // Dropdown menu for selecting the encryption algorithm
            VStack {
                Text("Encryption Algorithm").fontWeight(.bold)
                Picker("Encryption Algorithm", selection: $lastUsedAlgorithm) {
                    ForEach(algorithms.keys.sorted(), id: \.self) { key in
                        Text(algorithms[key] ?? key).tag(key)
                    }
                }
                .pickerStyle(MenuPickerStyle()) // Dropdown menu style
                .padding()
            }

            SecureField("Enter Passphrase", text: $passphrase)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()

            SecureField("Enter Iterations (Used to derive keys)", text: $iterations)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()

            Button("Start Process") {
                if let file = inputFile {
                    processFile(file)
                } else if let folder = inputFolder {
                    processFolder(folder)
                }
            }
            .disabled(passphrase.isEmpty || iterations.isEmpty)

            Text(encryptionStatus)
                .foregroundColor(encryptionStatus.contains("Error") ? .red : .green)
                .padding()

            // History list
            List(fileHistory) { item in
                Button(action: {
                    reverseAction(for: item)
                }) {
                    Text("\(item.fileName) - \(item.action) using \(item.algorithm)")
                }
            }
            .frame(height: 150)

            HStack {
                Spacer()
                Button("Clear History") {
                    clearHistory()
                }
                .padding()
                .foregroundColor(.red)
                Spacer()
            }

            Spacer()
        }
        .padding()
        .frame(width: 500, height: 600)
        .onAppear {
            loadHistory()
        }
        .onChange(of: fileHistory) { _ in saveHistory() }
    }

    func selectInput() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            if panel.url?.hasDirectoryPath == true {
                inputFolder = panel.url
                inputFile = nil
            } else {
                inputFile = panel.url
                inputFolder = nil
            }
        }
    }

    func verifyInputs() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Confirm Passphrase and Iterations"
        alert.informativeText = "Re-enter the passphrase and iterations to confirm."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        // Passphrase and iteration confirmation fields
        let passphraseField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        let iterationField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        let stackView = NSStackView(frame: NSRect(x: 0, y: 0, width: 200, height: 60))
        stackView.orientation = .vertical
        stackView.addArrangedSubview(passphraseField)
        stackView.addArrangedSubview(iterationField)
        alert.accessoryView = stackView
        
        if alert.runModal() == .alertFirstButtonReturn {
            return passphraseField.stringValue == passphrase &&
                   iterationField.stringValue == iterations
        }
        return false
    }

    func processFile(_ file: URL) {
        guard verifyInputs() else {
            encryptionStatus = "Error: Passphrase or iterations do not match."
            return
        }

        let isEncrypted = file.pathExtension == "enc"
        if isEncrypted {
            decryptFile(file)
        } else {
            encryptFile(file)
        }
        fileHistory.append(FileHistoryItem(fileName: file.lastPathComponent, action: isEncrypted ? "Decrypted" : "Encrypted", algorithm: lastUsedAlgorithm))
    }

    func processFolder(_ folder: URL) {
        guard verifyInputs() else {
            encryptionStatus = "Error: Passphrase or iterations do not match."
            return
        }

        let fileManager = FileManager.default
        do {
            let files = try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            for file in files {
                processFile(file)
            }
            encryptionStatus = "Processing of folder completed."
        } catch {
            encryptionStatus = "Error: Failed to read folder contents"
        }
    }

    func encryptFile(_ file: URL) {
        guard let iterationsInt = Int(iterations) else {
            encryptionStatus = "Error: Invalid iterations"
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        let encryptedFile = file.appendingPathExtension("enc")

        process.arguments = [
            "enc", "-\(lastUsedAlgorithm)", "-salt", "-pbkdf2",
            "-iter", "\(iterationsInt)",
            "-in", file.path,
            "-out", encryptedFile.path,
            "-pass", "pass:\(passphrase)"
        ]

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                try FileManager.default.removeItem(at: file)
                encryptionStatus = "Encryption successful: \(encryptedFile.lastPathComponent)"
            } else {
                encryptionStatus = "Error: Encryption failed"
            }
        } catch {
            encryptionStatus = "Error: \(error.localizedDescription)"
        }
    }

    func decryptFile(_ file: URL) {
        guard let iterationsInt = Int(iterations) else {
            encryptionStatus = "Error: Invalid iterations"
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        let decryptedFile = file.deletingPathExtension()

        process.arguments = [
            "enc", "-d", "-\(lastUsedAlgorithm)", "-pbkdf2",
            "-iter", "\(iterationsInt)",
            "-in", file.path,
            "-out", decryptedFile.path,
            "-pass", "pass:\(passphrase)"
        ]

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                try FileManager.default.removeItem(at: file)
                encryptionStatus = "Decryption successful: \(decryptedFile.lastPathComponent)"
            } else {
                encryptionStatus = "Error: Incorrect password or iterations"
            }
        } catch {
            encryptionStatus = "Error: \(error.localizedDescription)"
        }
    }

    func reverseAction(for item: FileHistoryItem) {
        // Append `.enc` if the action was "Encrypted"
        let matchingFile: URL?
        if item.action == "Encrypted" {
            matchingFile = inputFolder?.appendingPathComponent(item.fileName + ".enc") ?? inputFile?.deletingLastPathComponent().appendingPathComponent(item.fileName + ".enc")
        } else {
            matchingFile = inputFolder?.appendingPathComponent(item.fileName) ?? inputFile?.deletingLastPathComponent().appendingPathComponent(item.fileName)
        }

        guard let file = matchingFile else { return }

        passphrase = ""
        iterations = ""

        let alert = NSAlert()
        alert.messageText = "Reverse \(item.action)"
        alert.informativeText = "Enter the passphrase and iteration count for this action."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        // Passphrase and iteration fields
        let passphraseField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        let iterationField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        let stackView = NSStackView(frame: NSRect(x: 0, y: 0, width: 200, height: 60))
        stackView.orientation = .vertical
        stackView.addArrangedSubview(passphraseField)
        stackView.addArrangedSubview(iterationField)
        alert.accessoryView = stackView

        if alert.runModal() == .alertFirstButtonReturn {
            passphrase = passphraseField.stringValue
            iterations = iterationField.stringValue

            if item.action == "Encrypted" {
                decryptFile(file)
            } else {
                encryptFile(file)
            }
        }
    }


    func clearHistory() {
        fileHistory.removeAll()
        saveHistory()
    }

    func saveHistory() {
        do {
            let data = try JSONEncoder().encode(fileHistory)
            UserDefaults.standard.set(data, forKey: "fileHistory")
        } catch {
            print("Failed to save history: \(error)")
        }
    }

    func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: "fileHistory") {
            do {
                fileHistory = try JSONDecoder().decode([FileHistoryItem].self, from: data)
            } catch {
                print("Failed to load history: \(error)")
            }
        }
    }
}

