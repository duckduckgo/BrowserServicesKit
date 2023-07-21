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

    var databaseFileName: String { get }

    init(file: URL, key: Data) throws

    static func recreateDatabase(withKey key: Data) throws -> Self

}

extension SecureStorageDatabaseProvider {

    public static func recreateDatabase(withKey key: Data) throws -> Self {
        let dbFile = self.databaseFilePath()

        guard FileManager.default.fileExists(atPath: dbFile.path) else {
            return try Self(file: dbFile, key: key)
        }

        // make sure we can create an empty db first and release it then
        let newDbFile = self.nonExistingDBFile(withExtension: dbFile.pathExtension)
        try autoreleasepool {
            try _=Self(file: newDbFile, key: key)
        }

        // backup old db file
        let backupFile = self.nonExistingDBFile(withExtension: dbFile.pathExtension + ".bak")
        try FileManager.default.moveItem(at: dbFile, to: backupFile)

        // place just created new db in place of dbFile
        try FileManager.default.moveItem(at: newDbFile, to: dbFile)

        return try Self(file: dbFile, key: key)
    }

    static public func databaseFilePath() -> URL {

        let fm = FileManager.default
        let subDir = fm.applicationSupportDirectoryForComponent(named: "Vault")

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

        return subDir.appendingPathComponent("Vault.db")
    }

    static internal func nonExistingDBFile(withExtension ext: String) -> URL {
        let originalPath = Self.databaseFilePath().deletingPathExtension().path

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

    public static func createDatabaseQueue(file: URL, key: Data, registerMigrationsHandler: (inout DatabaseMigrator) -> Void) throws -> DatabaseQueue {
        var config = Configuration()
        config.prepareDatabase {
            try $0.usePassphrase(key)
        }

        let queue: DatabaseQueue

        do {
            queue = try DatabaseQueue(path: file.path, configuration: config)
        } catch let error as DatabaseError where [.SQLITE_NOTADB, .SQLITE_CORRUPT].contains(error.resultCode) {
            os_log("database corrupt: %{public}s", type: .error, error.message ?? "")
            throw SecureStorageDatabaseError.nonRecoverable(error)
        } catch {
            os_log("database initialization failed with %{public}s", type: .error, error.localizedDescription)
            throw error
        }

        var migrator = DatabaseMigrator()
        registerMigrationsHandler(&migrator)

        // Add more sync migrations here ...
        // Note, these migrations will run synchronously on first access to secureVault DB

        do {
            try migrator.migrate(queue)
        } catch {
            os_log("database migration error: %{public}s", type: .error, error.localizedDescription)
            throw error
        }

        return queue
    }

}

private enum DatabaseWriterType {
    case queue
    case pool
}
