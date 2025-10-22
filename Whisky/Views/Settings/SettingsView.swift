//
//  SettingsView.swift
//  Whisky
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import SwiftUI
import WhiskyKit
import SemanticVersion

struct SettingsView: View {
    @AppStorage("SUEnableAutomaticChecks") var whiskyUpdate = true
    @AppStorage("killOnTerminate") var killOnTerminate = true
    @AppStorage("checkWhiskyWineUpdates") var checkWhiskyWineUpdates = true
    @AppStorage("defaultBottleLocation") var defaultBottleLocation = BottleData.defaultBottleDir

    var body: some View {
        Form {
            Section("settings.general") {
                Toggle("settings.toggle.kill.on.terminate", isOn: $killOnTerminate)
                ActionView(
                    text: "settings.path",
                    subtitle: defaultBottleLocation.prettyPath(),
                    actionName: "create.browse"
                ) {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.canCreateDirectories = true
                    panel.directoryURL = BottleData.containerDir
                    panel.begin { result in
                        if result == .OK, let url = panel.urls.first {
                            defaultBottleLocation = url
                        }
                    }
                }
            }
            Section("settings.updates") {
                Toggle("settings.toggle.whisky.updates", isOn: $whiskyUpdate)
                Toggle("settings.toggle.whiskywine.updates", isOn: $checkWhiskyWineUpdates)
            }
            Section("settings.runtime") {
                if let runtime = WhiskyWineInstaller.whiskyWineVersion() {
                    LabeledContent(String(localized: "settings.runtime.whiskywine")) {
                        Text(versionString(runtime))
                            .fontDesign(.monospaced)
                    }
                }
                if let toolkit = WhiskyWineInstaller.whiskyWineToolkitVersion() {
                    LabeledContent(String(localized: "settings.runtime.toolkit")) {
                        Text(versionString(toolkit))
                            .fontDesign(.monospaced)
                    }
                    if let releaseDate = WhiskyWineInstaller.whiskyWineToolkitReleaseDate() {
                        LabeledContent(String(localized: "settings.runtime.toolkit.releaseDate")) {
                            Text(releaseDateString(releaseDate))
                        }
                    }
                } else {
                    LabeledContent(String(localized: "settings.runtime.toolkit")) {
                        Text(String(localized: "settings.runtime.toolkit.unavailable"))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: ViewWidth.medium)
    }

    private func versionString(_ version: SemanticVersion) -> String {
        "\(version.major).\(version.minor).\(version.patch)"
    }

    private func releaseDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

#Preview {
    SettingsView()
}
