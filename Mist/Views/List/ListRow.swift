//
//  ListRow.swift
//  Mist
//
//  Created by Nindi Gill on 28/6/2022.
//

import Blessed
import SwiftUI
import System

struct ListRow: View {
    var type: DownloadType
    var image: String
    var version: String
    var build: String
    var beta: Bool
    var date: String
    var size: String
    var compatible: Bool
    @Binding var showPanel: Bool
    @ObservedObject var taskManager: TaskManager
    @State private var alertType: DownloadAlertType = .compatibility
    @State private var showAlert: Bool = false
    @AppStorage("cacheDownloads")
    private var cacheDownloads: Bool = false
    @AppStorage("cacheDirectory")
    private var cacheDirectory: String = .cacheDirectory
    private let length: CGFloat = 48
    private let spacing: CGFloat = 5
    private let padding: CGFloat = 3
    private var helpText: String {
        """
        Version: \(version)
        Build Number: \(build)
        Release Date: \(date)
        Download Size: \(size)
        """
    }
    private var compatibilityTitle: String {
        "macOS \(type.description) not compatible!"
    }
    private var compatibilityMessage: String {

        guard let architecture: Architecture = Hardware.architecture else {
            return "Invalid architecture!"
        }

        let operation: String = type == .firmware ? "restore" : "re-install"
        let string: String = "This macOS \(type.description) download cannot be used to \(operation) macOS on this \(architecture.description) Mac.\n\nAre you sure you want to continue?"
        return string
    }
    private var privilegedHelperToolTitle: String {
        "Privileged Helper Tool not installed!"
    }
    private var privilegedHelperToolMessage: String {
        "The Mist Privileged Helper Tool is required to perform Administrator tasks when \(type == .firmware ? "downloading macOS Firmwares" : "creating macOS Installers")."
    }
    private var fullDiskAccessTitle: String {
        "Full Disk Access required!"
    }
    private var fullDiskAccessMessage: String {
        "Mist requires Full Disk Access to perform Administrator tasks when creating macOS Installers."
    }
    private var cacheDirectoryTitle: String {
        "Cache directory settings incorrect!"
    }
    private var cacheDirectoryMessage: String {
        "The cache directory has incorrect ownership and/or permissions, which will cause issues caching macOS Installers.\n\nRepair the cache directory ownership and/or permissions and try again."
    }

    var body: some View {
        HStack {
            Group {
                ZStack {
                    ScaledImage(name: image, length: length)
                    if beta {
                        TextRibbon(title: "BETA", length: length * 0.9)
                    }
                }
                HStack(spacing: spacing) {
                    Text(version)
                        .font(.title2)
                    Text("(\(build))")
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(date)
                    .foregroundColor(.secondary)
                Text(size)
            }
            .help(helpText)
            .textSelection(.enabled)
            Group {
                switch type {
                case .firmware:
                    Button {
                        compatible ? validate() : showCompatibilityWarning()
                    } label: {
                        Image(systemName: "arrow.down.circle")
                            .font(.body.bold())
                    }
                    .help("Download macOS Firmware")
                    .buttonStyle(.capsule(.standard))
                case .installer:
                    HStack(spacing: 1) {
                        Button {
                            compatible ? validate() : showCompatibilityWarning()
                        } label: {
                            Image(systemName: "arrow.down.circle")
                                .font(.body.bold())
                        }
                        .help("Download and export macOS Installer")
                        .buttonStyle(.capsule(.leading))
                        Button {
                            print("Create bootable installer...")
                        } label: {
                            Image(systemName: "externaldrive")
                                .font(.body.bold())
                                .padding(.vertical, 1)
                        }
                        .help("Create bootable macOS Installer")
                        .buttonStyle(.capsule(.trailing))
                    }
                }
            }
            .padding(.trailing, padding)
        }
        .alert(isPresented: $showAlert) {
            switch alertType {
            case .compatibility:
                return Alert(
                    title: Text(compatibilityTitle),
                    message: Text(compatibilityMessage),
                    primaryButton: .default(Text("Cancel")),
                    secondaryButton: .default(Text("Continue")) { Task { validate() } }
                )
            case .helperTool:
                return Alert(
                    title: Text(privilegedHelperToolTitle),
                    message: Text(privilegedHelperToolMessage),
                    primaryButton: .default(Text("Install...")) { installPrivilegedHelperTool() },
                    secondaryButton: .default(Text("Cancel"))
                )
            case .fullDiskAccess:
                return Alert(
                    title: Text(fullDiskAccessTitle),
                    message: Text(fullDiskAccessMessage),
                    primaryButton: .default(Text("Allow...")) { openFullDiskAccessPreferences() },
                    secondaryButton: .default(Text("Cancel"))
                )
            case .cacheDirectory:
                return Alert(
                    title: Text(cacheDirectoryTitle),
                    message: Text(cacheDirectoryMessage),
                    primaryButton: .default(Text("Repair...")) { Task { try await repairCacheDirectoryOwnershipAndPermissions() } },
                    secondaryButton: .default(Text("Cancel"))
                )
            }
        }
    }

    private func showCompatibilityWarning() {
        alertType = .compatibility
        showAlert = true
    }

    private func validate() {

        guard PrivilegedHelperTool.isInstalled() else {
            alertType = .helperTool
            showAlert = true
            return
        }

        if type == .installer {

            guard FileManager.default.isReadableFile(atPath: .tccDatabasePath) else {
                alertType = .fullDiskAccess
                showAlert = true
                return
            }
        }

        if cacheDownloads {

            do {
                var isDirectory: ObjCBool = false

                if !FileManager.default.fileExists(atPath: cacheDirectory, isDirectory: &isDirectory) {
                    try FileManager.default.createDirectory(atPath: cacheDirectory, withIntermediateDirectories: true)
                }

                let attributes: [FileAttributeKey: Any] = try FileManager.default.attributesOfItem(atPath: cacheDirectory)

                guard let posixPermissions: NSNumber = attributes[.posixPermissions] as? NSNumber else {
                    alertType = .cacheDirectory
                    showAlert = true
                    return
                }

                let filePermissions: FilePermissions = FilePermissions(rawValue: CModeT(posixPermissions.int16Value))

                guard filePermissions == [.ownerReadWriteExecute, .groupReadExecute, .otherReadExecute],
                    let ownerAccountName: String = attributes[.ownerAccountName] as? String,
                    ownerAccountName == NSUserName(),
                    let groupOwnerAccountName: String = attributes[.groupOwnerAccountName] as? String,
                    groupOwnerAccountName == "wheel" else {
                    alertType = .cacheDirectory
                    showAlert = true
                    return
                }
            } catch {
                alertType = .cacheDirectory
                showAlert = true
                return
            }
        }

        showPanel = true
    }

    private func installPrivilegedHelperTool() {
        try? PrivilegedHelperManager.shared.authorizeAndBless()
    }

    private func openFullDiskAccessPreferences() {

        guard let url: URL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func repairCacheDirectoryOwnershipAndPermissions() async throws {
        let url: URL = URL(fileURLWithPath: cacheDirectory)
        let ownerAccountName: String = NSUserName()
        try await FileAttributesUpdater.update(url: url, ownerAccountName: ownerAccountName)
    }
}

struct ListRow_Previews: PreviewProvider {
    static let firmware: Firmware = .example
    static let installer: Installer = .example

    static var previews: some View {
        ListRow(
            type: .firmware,
            image: firmware.imageName,
            version: firmware.version,
            build: firmware.build,
            beta: firmware.beta,
            date: firmware.formattedDate,
            size: firmware.size.bytesString(),
            compatible: firmware.compatible,
            showPanel: .constant(false),
            taskManager: .shared
        )
        ListRow(
            type: .installer,
            image: installer.imageName,
            version: installer.version,
            build: installer.build,
            beta: installer.beta,
            date: installer.date,
            size: installer.size.bytesString(),
            compatible: firmware.compatible,
            showPanel: .constant(false),
            taskManager: .shared
        )
    }
}
