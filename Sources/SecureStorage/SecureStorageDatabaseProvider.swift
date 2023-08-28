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

/// Provides a concrete implementation of a GRDB database that uses SQLCipher for at-rest encryption.
///
/// Users of this class are intended to subclass it, so that they can extend their implementation with logic to read/write to and from the database.
/// Please see `DefaultAutofillDatabaseProvider` in the `BrowserServicesKit` module for an example of how you could implement a concrete database provider using GRDB.
open class GRDBSecureStorageDatabaseProvider: SecureStorageDatabaseProvider {

    public enum DatabaseWriterType {
        case queue
        case pool
    }

    public let db: DatabaseWriter

    public init(file: URL,
                key: Data,
                writerType: DatabaseWriterType = .queue,
                registerMigrationsHandler: (inout DatabaseMigrator) throws -> Void) throws {
        do {
            self.db = try Self.createDatabase(file: file, key: key, writerType: writerType, registerMigrationsHandler: registerMigrationsHandler)
        } catch SecureStorageDatabaseError.corruptedDatabase {
            try Self.recreateDatabase(withKey: key, databaseURL: file)
            self.db = try Self.createDatabase(file: file, key: key, writerType: writerType, registerMigrationsHandler: registerMigrationsHandler)
        }
    }

    private static func createDatabase(file: URL,
                                       key: Data,
                                       writerType: DatabaseWriterType,
                                       registerMigrationsHandler: (inout DatabaseMigrator) throws -> Void) throws -> DatabaseWriter {
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
        try registerMigrationsHandler(&migrator)

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
