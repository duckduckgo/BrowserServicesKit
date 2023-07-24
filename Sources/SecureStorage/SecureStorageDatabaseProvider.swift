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

    init(file: URL, key: Data) throws

    static func recreateDatabase(withKey key: Data) throws -> Self

}

open class GRDBSecureStorageDatabaseProvider: SecureStorageDatabaseProvider {

    public enum DatabaseWriterType {
        case queue
        case pool
    }

    /// Provides the default database directory and file name.
    ///
    /// This is used to derive the database path relative to the application support directory.
    open class var databaseLocation: (directoryName: String, fileName: String) {
        fatalError("Must be overridden by a subclass")
    }

    /// Determines the GRDB DatabaseWriter type.
    ///
    /// The available options are `queue` and `pool`, representing a `DatabaseQueue` and `DatabasePool` respectively.
    open class var writerType: DatabaseWriterType {
        fatalError("Must be overridden by a subclass")
    }

    /// Configures the database migrations to use for the subclass of the database provider.
    ///
    /// This is called by the database provider's `init` function as a part of setting up the database.
    open class func registerMigrations(with migrator: inout DatabaseMigrator) throws {
        fatalError("Must be overridden by a subclass")
    }

    public let db: DatabaseWriter

    public required init(file: URL, key: Data) throws {
        var config = Configuration()
        config.prepareDatabase {
            try $0.usePassphrase(key)
        }

        let writer: DatabaseWriter

        do {
            switch Self.writerType {
            case .queue: writer = try DatabaseQueue(path: file.path, configuration: config)
            case .pool: writer = try DatabasePool(path: file.path, configuration: config)
            }
        } catch let error as DatabaseError where [.SQLITE_NOTADB, .SQLITE_CORRUPT].contains(error.resultCode) {
            os_log("database corrupt: %{public}s", type: .error, error.message ?? "")
            throw SecureStorageDatabaseError.nonRecoverable(error)
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

        self.db = writer
    }

    public static func recreateDatabase(withKey key: Data) throws -> Self {
        let dbFile = self.databaseFilePath(directoryName: Self.databaseLocation.directoryName, fileName: Self.databaseLocation.fileName)

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
        return databaseFilePath(directoryName: Self.databaseLocation.directoryName, fileName: Self.databaseLocation.fileName)
    }

    static public func databaseFilePath(directoryName: String, fileName: String) -> URL {

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

    static internal func nonExistingDBFile(withExtension ext: String) -> URL {
        let originalPath = Self.databaseFilePath(directoryName: databaseLocation.directoryName, fileName: databaseLocation.fileName)
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
