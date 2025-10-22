//
//  ContentView.swift
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
import UniformTypeIdentifiers
import WhiskyKit
import SemanticVersion
import Foundation

struct ContentView: View {
    @AppStorage("selectedBottleURL") private var selectedBottleURL: URL?
    @EnvironmentObject var bottleVM: BottleVM
    @Binding var showSetup: Bool

    @State private var selected: URL?
    @State private var showBottleCreation: Bool = false
    @State private var bottlesLoaded: Bool = false
    @State private var showBottleSelection: Bool = false
    @State private var newlyCreatedBottleURL: URL?
    @State private var openedFileURL: URL?
    @State private var triggerRefresh: Bool = false
    @State private var refreshAnimation: Angle = .degrees(0)

    @State private var bottleFilter = ""

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showBottleCreation.toggle()
                } label: {
                    Image(systemName: "plus")
                        .help("button.createBottle")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    bottleVM.loadBottles()
                    if let bottle = bottleVM.bottles.first(where: { $0.url == selected }) {
                        bottle.updateInstalledPrograms()
                    }
                    triggerRefresh.toggle()
                    withAnimation(.default) {
                        refreshAnimation = .degrees(360)
                    } completion: {
                        refreshAnimation = .degrees(0)
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .help("button.refresh")
                        .rotationEffect(refreshAnimation)
                }
            }
        }
        .sheet(isPresented: $showBottleCreation) {
            BottleCreationView(newlyCreatedBottleURL: $newlyCreatedBottleURL)
        }
        .sheet(isPresented: $showSetup) {
            SetupView(showSetup: $showSetup, firstTime: false)
        }
        .sheet(item: $openedFileURL) { url in
            FileOpenView(fileURL: url,
                         currentBottle: selected,
                         bottles: bottleVM.bottles)
        }
        .onChange(of: selected) {
            selectedBottleURL = selected
        }
        .handlesExternalEvents(preferring: [], allowing: ["*"])
        .onOpenURL { url in
            openedFileURL = url
        }
        .task {
            bottleVM.loadBottles()
            bottlesLoaded = true

            if !bottleVM.bottles.isEmpty || bottleVM.countActive() != 0 {
                if let bottle = bottleVM.bottles.first(where: { $0.url == selectedBottleURL && $0.isAvailable }) {
                    selected = bottle.url
                } else {
                    selected = bottleVM.bottles[0].url
                }
            }

            if !WhiskyWineInstaller.isWhiskyWineInstalled() {
                showSetup = true
            }
            let task = Task.detached {
                await WhiskyWineInstaller.shouldUpdateWhiskyWine()
            }
            let (shouldUpdateRuntime, remoteRuntime) = await task.value
            if shouldUpdateRuntime, let remoteRuntime {
                let alert = NSAlert()
                alert.messageText = String(localized: "update.whiskywine.title")
                var informativeText = String(format: String(localized: "update.whiskywine.description"),
                                              versionString(WhiskyWineInstaller.whiskyWineVersion()),
                                              versionString(remoteRuntime.version))
                if let remoteToolkit = remoteRuntime.toolkitVersion {
                    let remoteToolkitString = versionString(remoteToolkit)
                    if let localToolkit = WhiskyWineInstaller.whiskyWineToolkitVersion() {
                        if localToolkit < remoteToolkit {
                            informativeText += "\n\n" + String(format: String(localized: "update.whiskywine.toolkit"),
                                                                   versionString(localToolkit),
                                                                   remoteToolkitString)
                        }
                    } else {
                        informativeText += "\n\n" + String(format: String(localized: "update.whiskywine.toolkit.new"),
                                                               remoteToolkitString)
                    }
                    if let remoteReleaseDate = remoteRuntime.toolkitReleaseDate {
                        let shouldSurfaceReleaseDate: Bool
                        if let localReleaseDate = WhiskyWineInstaller.whiskyWineToolkitReleaseDate() {
                            shouldSurfaceReleaseDate = localReleaseDate < remoteReleaseDate
                        } else {
                            shouldSurfaceReleaseDate = true
                        }
                        if shouldSurfaceReleaseDate {
                            informativeText += "\n\n" + String(format: String(localized: "update.whiskywine.toolkit.releaseDate"),
                                                                   remoteToolkitString,
                                                                   releaseDateString(remoteReleaseDate))
                        }
                    }
                } else if let remoteReleaseDate = remoteRuntime.toolkitReleaseDate {
                    informativeText += "\n\n" + String(format: String(localized: "update.whiskywine.toolkit.releaseDate"),
                                                           String(localized: "settings.runtime.toolkit"),
                                                           releaseDateString(remoteReleaseDate))
                }
                alert.informativeText = informativeText
                alert.alertStyle = .warning
                alert.addButton(withTitle: String(localized: "update.whiskywine.update"))
                alert.addButton(withTitle: String(localized: "button.removeAlert.cancel"))

                let response = alert.runModal()

                if response == .alertFirstButtonReturn {
                    WhiskyWineInstaller.uninstall()
                    showSetup = true
                }
            }
        }
    }

    var sidebar: some View {
        ScrollViewReader { proxy in
            List(selection: $selected) {
                Section {
                    ForEach(filteredBottles) { bottle in
                        Group {
                            if bottle.inFlight {
                                HStack {
                                    Text(bottle.settings.name)
                                    Spacer()
                                    ProgressView().controlSize(.small)
                                }
                                .opacity(0.5)
                            } else {
                                BottleListEntry(bottle: bottle, selected: $selected, refresh: $triggerRefresh)
                                    .selectionDisabled(!bottle.isAvailable)
                            }
                        }
                        .id(bottle.url)
                    }
                }
            }
            .animation(.default, value: bottleVM.bottles)
            .animation(.default, value: bottleFilter)
            .listStyle(.sidebar)
            .searchable(text: $bottleFilter, placement: .sidebar)
            .onChange(of: newlyCreatedBottleURL) { _, url in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    selected = url
                    withAnimation {
                        proxy.scrollTo(url, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    var detail: some View {
        if let bottle = selected {
            if let bottle = bottleVM.bottles.first(where: { $0.url == bottle }) {
                BottleView(bottle: bottle)
                    .disabled(bottle.inFlight)
                    .id(bottle.url)
            }
        } else {
            if (bottleVM.bottles.isEmpty || bottleVM.countActive() == 0) && bottlesLoaded {
                VStack {
                    Text("main.createFirst")
                    Button {
                        showBottleCreation.toggle()
                    } label: {
                        HStack {
                            Image(systemName: "plus")
                            Text("button.createBottle")
                        }
                        .padding(6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                }
            }
        }
    }

    var filteredBottles: [Bottle] {
        if bottleFilter.isEmpty {
            bottleVM.bottles
                .sorted()
        } else {
            bottleVM.bottles
                .filter { $0.settings.name.localizedCaseInsensitiveContains(bottleFilter) }
                .sorted()
        }
    }
}

private func versionString(_ version: SemanticVersion) -> String {
    "\(version.major).\(version.minor).\(version.patch)"
}

private func versionString(_ version: SemanticVersion?) -> String {
    guard let version else { return versionString(SemanticVersion(0, 0, 0)) }
    return versionString(version)
}

private func releaseDateString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .long
    formatter.timeStyle = .none
    return formatter.string(from: date)
}

#Preview {
    ContentView(showSetup: .constant(false))
        .environmentObject(BottleVM.shared)
}
