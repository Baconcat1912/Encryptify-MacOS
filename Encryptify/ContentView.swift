//
//  ContentView.swift
//  Encryptify
//
//  Created by Eran Straub on 11/25/24.
//
import SwiftUI

struct ContentView: View {
    @State private var inputFile: URL?
    @State private var inputFolder: URL?
    @State private var passphrase: String = ""
    @State private var iterations: String = ""
    @State private var encryptionStatus: String = ""
    @State private var progress: Double = 0.0
    @State private var isProcessing: Bool = false
    @State private var fileHistory: [String] = []
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
                .pickerStyle(MenuPickerStyle()) // Changes to dropdown
                .padding()
            }

            SecureField("Enter Passphrase", text: $passphrase)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .onChange(of: passphrase) { _ in validatePassphrase() }
                .padding()

            SecureField("Enter Iterations (Used to derive keys)", text: $iterations)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()

            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle())
                .padding()

            Button("Start Process") {
                if let file = inputFile {
                    startProcessing { processFile(file) }
                } else if let folder = inputFolder {
                    startProcessing { processFolder(folder) }
                }
            }
            .disabled(isProcessing || passphrase.isEmpty || iterations.isEmpty)

            Text(encryptionStatus)
                .foregroundColor(encryptionStatus.contains("Error") ? .red : .green)
                .padding()

            List(fileHistory, id: \.self) { file in
                Text(file)
            }
            .frame(height: 100)

            Spacer()
        }
        .padding()
        .frame(width: 500, height: 600)
    }

    func validatePassphrase() {
        guard passphrase.count >= 8 else {
            encryptionStatus = "Error: Passphrase must be at least 8 characters"
            return
        }
        encryptionStatus = ""
    }

    func startProcessing(_ action: @escaping () -> Void) {
        isProcessing = true
        progress = 0.0
        DispatchQueue.global(qos: .userInitiated).async {
            action()
            DispatchQueue.main.async {
                isProcessing = false
                progress = 1.0
            }
        }
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

    func processFile(_ file: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            let isEncrypted = file.pathExtension == "enc"
            if isEncrypted {
                decryptFile(file)
            } else {
                encryptFile(file)
            }
            DispatchQueue.main.async {
                fileHistory.append(file.lastPathComponent)
            }
        }
    }

    func processFolder(_ folder: URL) {
        let fileManager = FileManager.default
        do {
            let files = try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            for file in files {
                processFile(file)
            }
            DispatchQueue.main.async {
                encryptionStatus = "Processing of folder completed."
            }
        } catch {
            DispatchQueue.main.async {
                encryptionStatus = "Error: Failed to read folder contents"
            }
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
                DispatchQueue.main.async {
                    encryptionStatus = "Encryption successful: \(encryptedFile.lastPathComponent)"
                }
            } else {
                DispatchQueue.main.async {
                    encryptionStatus = "Error: Encryption failed"
                }
            }
        } catch {
            DispatchQueue.main.async {
                encryptionStatus = "Error: \(error.localizedDescription)"
            }
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
                DispatchQueue.main.async {
                    encryptionStatus = "Decryption successful: \(decryptedFile.lastPathComponent)"
                }
            } else {
                if FileManager.default.fileExists(atPath: decryptedFile.path) {
                    try FileManager.default.removeItem(at: decryptedFile)
                }
                DispatchQueue.main.async {
                    encryptionStatus = "Error: Incorrect password or iterations"
                }
            }
        } catch {
            if FileManager.default.fileExists(atPath: decryptedFile.path) {
                try? FileManager.default.removeItem(at: decryptedFile)
            }
            DispatchQueue.main.async {
                encryptionStatus = "Error: \(error.localizedDescription)"
            }
        }
    }
}
