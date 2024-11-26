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

            SecureField("Enter Passphrase", text: $passphrase)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()

            TextField("Enter Iterations (Used to derive keys)", text: $iterations)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()

            Button("Start Process") {
                if let file = inputFile {
                    processFile(file)
                } else if let folder = inputFolder {
                    processFolder(folder)
                }
            }
            .disabled((inputFile == nil && inputFolder == nil) || passphrase.isEmpty || iterations.isEmpty)

            Text(encryptionStatus)
                .foregroundColor(encryptionStatus.contains("Error") ? .red : .green)
                .padding()
        }
        .padding()
        .frame(width: 400, height: 400)
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
        let isEncrypted = file.pathExtension == "enc"
        if isEncrypted {
            decryptFile(file)
        } else {
            encryptFile(file)
        }
    }

    func processFolder(_ folder: URL) {
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
            "enc", "-aes-256-cbc", "-salt", "-pbkdf2",
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
            "enc", "-d", "-aes-256-cbc", "-pbkdf2",
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
                // Delete the partially created decrypted file if it exists
                if FileManager.default.fileExists(atPath: decryptedFile.path) {
                    try FileManager.default.removeItem(at: decryptedFile)
                }
                encryptionStatus = "Error: Incorrect password or iterations"
            }
        } catch {
            // Delete the partially created decrypted file if it exists
            if FileManager.default.fileExists(atPath: decryptedFile.path) {
                try? FileManager.default.removeItem(at: decryptedFile)
            }
            encryptionStatus = "Error: \(error.localizedDescription)"
        }
    }
}
