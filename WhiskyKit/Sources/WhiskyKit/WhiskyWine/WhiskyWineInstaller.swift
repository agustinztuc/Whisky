//
//  WhiskyWineInstaller.swift
//  WhiskyKit
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

import Foundation
import SemanticVersion

public class WhiskyWineInstaller {
    /// The Whisky application folder
    public static let applicationFolder = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appending(path: Bundle.whiskyBundleIdentifier)

    /// The folder of all the libfrary files
    public static let libraryFolder = applicationFolder.appending(path: "Libraries")

    /// URL to the installed `wine` `bin` directory
    public static let binFolder: URL = libraryFolder.appending(path: "Wine").appending(path: "bin")

    private static let versionPlistURL = libraryFolder
        .appending(path: "WhiskyWineVersion")
        .appendingPathExtension("plist")

    private static let remoteVersionURL = URL(string: "https://data.getwhisky.app/Wine/WhiskyWineVersion.plist")

    public static func isWhiskyWineInstalled() -> Bool {
        return whiskyWineVersion() != nil
    }

    public static func install(from: URL) {
        do {
            if !FileManager.default.fileExists(atPath: applicationFolder.path) {
                try FileManager.default.createDirectory(at: applicationFolder, withIntermediateDirectories: true)
            } else {
                // Recreate it
                try FileManager.default.removeItem(at: applicationFolder)
                try FileManager.default.createDirectory(at: applicationFolder, withIntermediateDirectories: true)
            }

            try Tar.untar(tarBall: from, toURL: applicationFolder)
            try FileManager.default.removeItem(at: from)
        } catch {
            print("Failed to install WhiskyWine: \(error)")
        }
    }

    public static func uninstall() {
        do {
            try FileManager.default.removeItem(at: libraryFolder)
        } catch {
            print("Failed to uninstall WhiskyWine: \(error)")
        }
    }

    public static func shouldUpdateWhiskyWine() async -> (Bool, WhiskyWineVersion?) {
        let localInfo = whiskyWineMetadata()
        let remoteInfo = await fetchRemoteWhiskyWineMetadata()

        guard let localInfo = localInfo, let remoteInfo = remoteInfo else {
            return (false, remoteInfo)
        }

        if localInfo.version < remoteInfo.version {
            return (true, remoteInfo)
        }

        if shouldUpdateToolkit(local: localInfo, remote: remoteInfo) {
            return (true, remoteInfo)
        }

        return (false, remoteInfo)
    }

    public static func whiskyWineVersion() -> SemanticVersion? {
        return whiskyWineMetadata()?.version
    }

    public static func whiskyWineToolkitVersion() -> SemanticVersion? {
        return whiskyWineMetadata()?.toolkitVersion
    }

    public static func whiskyWineToolkitReleaseDate() -> Date? {
        return whiskyWineMetadata()?.toolkitReleaseDate
    }

    private static func whiskyWineMetadata() -> WhiskyWineVersion? {
        do {
            guard FileManager.default.fileExists(atPath: versionPlistURL.path) else { return nil }
            let decoder = PropertyListDecoder()
            let data = try Data(contentsOf: versionPlistURL)
            return try decoder.decode(WhiskyWineVersion.self, from: data)
        } catch {
            print(error)
            return nil
        }
    }

    private static func fetchRemoteWhiskyWineMetadata() async -> WhiskyWineVersion? {
        guard let remoteUrl = remoteVersionURL else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            URLSession(configuration: .ephemeral).dataTask(with: URLRequest(url: remoteUrl)) { data, _, error in
                var info: WhiskyWineVersion?

                if error == nil, let data = data {
                    do {
                        let decoder = PropertyListDecoder()
                        info = try decoder.decode(WhiskyWineVersion.self, from: data)
                    } catch {
                        print(error)
                    }
                } else if let error = error {
                    print(error)
                }

                continuation.resume(returning: info)
            }.resume()
        }
    }

    private static func shouldUpdateToolkit(local: WhiskyWineVersion, remote: WhiskyWineVersion) -> Bool {
        guard let remoteToolkit = remote.toolkitVersion else {
            return false
        }

        guard let localToolkit = local.toolkitVersion else {
            return true
        }

        if localToolkit < remoteToolkit {
            return true
        }

        guard localToolkit == remoteToolkit else {
            return false
        }

        guard let remoteReleaseDate = remote.toolkitReleaseDate else {
            return false
        }

        guard let localReleaseDate = local.toolkitReleaseDate else {
            return true
        }

        return localReleaseDate < remoteReleaseDate
    }
}

struct WhiskyWineVersion: Codable {
    var version: SemanticVersion = SemanticVersion(1, 0, 0)
    var toolkitVersion: SemanticVersion?
    var toolkitReleaseDate: Date?

    enum CodingKeys: String, CodingKey {
        case version
        case toolkitVersion = "toolkit"
        case legacyToolkitVersion = "toolkitVersion"
        case toolkitReleaseDate
    }

    init(version: SemanticVersion = SemanticVersion(1, 0, 0),
         toolkitVersion: SemanticVersion? = nil,
         toolkitReleaseDate: Date? = nil) {
        self.version = version
        self.toolkitVersion = toolkitVersion
        self.toolkitReleaseDate = toolkitReleaseDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decodeIfPresent(SemanticVersion.self, forKey: .version) ?? SemanticVersion(1, 0, 0)
        if let toolkit = try container.decodeIfPresent(SemanticVersion.self, forKey: .toolkitVersion) {
            self.toolkitVersion = toolkit
        } else {
            self.toolkitVersion = try container.decodeIfPresent(SemanticVersion.self, forKey: .legacyToolkitVersion)
        }
        if let releaseString = try container.decodeIfPresent(String.self, forKey: .toolkitReleaseDate) {
            self.toolkitReleaseDate = WhiskyWineVersion.parseReleaseDate(from: releaseString)
        } else {
            self.toolkitReleaseDate = try container.decodeIfPresent(Date.self, forKey: .toolkitReleaseDate)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        if let toolkitVersion = toolkitVersion {
            try container.encode(toolkitVersion, forKey: .toolkitVersion)
        }
        if let toolkitReleaseDate = toolkitReleaseDate {
            let releaseString = WhiskyWineVersion.releaseDateFormatter.string(from: toolkitReleaseDate)
            try container.encode(releaseString, forKey: .toolkitReleaseDate)
        }
    }
}

extension WhiskyWineVersion {
    fileprivate static let releaseDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let releaseDateTimeFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let releaseDateTimeWithFractionFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    static func parseReleaseDate(from string: String) -> Date? {
        if let date = releaseDateTimeWithFractionFormatter.date(from: string) {
            return date
        }
        if let date = releaseDateTimeFormatter.date(from: string) {
            return date
        }
        return releaseDateFormatter.date(from: string)
    }
}
