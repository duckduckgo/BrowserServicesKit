//
//  SecureStorageDatabaseProvider.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import Common
import GRDB

public protocol SecureStorageDatabaseProvider {

    var db: DatabaseWriter { get }

}

open class GRDBSecureStorageDatabaseProvider: SecureStorageDatabaseProvider {

    public enum DatabaseWriterType {
        case queue
        case pool
    }

    /// Configures the database migrations to use for the subclass of the database provider.
    ///
    /// This is called by the database provider's `init` function as a part of setting up the database.
    open class func registerMigrations(with migrator: inout DatabaseMigrator) throws {
        fatalError("Must be overridden by a subclass")
    }

    public let db: DatabaseWriter

    public init(file: URL, key: Data, writerType: DatabaseWriterType = .queue) throws {
        do {
            self.db = try Self.createDatabase(file: file, key: key, writerType: writerType)
        } catch SecureStorageDatabaseError.corruptedDatabase {
            try Self.recreateDatabase(withKey: key, databaseURL: file)
            self.db = try Self.createDatabase(file: file, key: key, writerType: writerType)
        }
    }

    private static func createDatabase(file: URL, key: Data, writerType: DatabaseWriterType) throws -> DatabaseWriter {
        var config = Configuration()
        config.prepareDatabase {
            try $0.usePassphrase(key)
        }

        let writer: DatabaseWriter

        do {
            switch writerType {
            case .queue: writer = try DatabaseQueue(path: file.path, configuration: config)
            case .pool: writer = try DatabasePool(path: file.path, configuration: config)
            }
        } catch let error as DatabaseError where [.SQLITE_NOTADB, .SQLITE_CORRUPT].contains(error.resultCode) {
            os_log("database corrupt: %{public}s", type: .error, error.message ?? "")
            throw SecureStorageDatabaseError.corruptedDatabase(error)
        } catch {
            os_log("database initialization failed with %{public}s", type: .error, error.localizedDescription)
            throw error
        }

        var migrator = DatabaseMigrator()
        try Self.registerMigrations(with: &migrator)

        do {
            try migrator.migrate(writer)
        } catch {
            os_log("database migration error: %{public}s", type: .error, error.localizedDescription)
            throw error
        }

        return writer
    }

    private static func recreateDatabase(withKey key: Data, databaseURL: URL) throws {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return
        }

        // create a new database file path
        let newDbFile = self.nonExistingDBFile(withExtension: databaseURL.pathExtension, originalURL: databaseURL)

        // backup old db file
        let backupFile = self.nonExistingDBFile(withExtension: databaseURL.pathExtension + ".bak", originalURL: databaseURL)
        try FileManager.default.moveItem(at: databaseURL, to: backupFile)

        // place just created new db in place of dbFile
        try FileManager.default.moveItem(at: newDbFile, to: databaseURL)
    }

    public static func databaseFilePath(directoryName: String, fileName: String) -> URL {

        let fm = FileManager.default
        let subDir = fm.applicationSupportDirectoryForComponent(named: directoryName)

        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: subDir.path, isDirectory: &isDir) {
            do {
                try fm.createDirectory(at: subDir, withIntermediateDirectories: true, attributes: nil)
                isDir = true
            } catch {
                fatalError("Failed to create directory at \(subDir.path)")
            }
        }

        if !isDir.boolValue {
            fatalError("Configuration folder at \(subDir.path) is not a directory")
        }

        return subDir.appendingPathComponent(fileName)
    }

    internal static func nonExistingDBFile(withExtension ext: String, originalURL: URL) -> URL {
        let originalPath = originalURL
            .deletingPathExtension()
            .path

        for i in 0... {
            var path = originalPath
            if i > 0 {
                path += "_\(i)"
            }
            path += "." + ext

            if !FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        fatalError()
    }

}

private enum DatabaseWriterType {
    case queue
    case pool
}
