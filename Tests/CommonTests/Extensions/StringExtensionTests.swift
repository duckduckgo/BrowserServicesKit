//
//  StringExtensionTests.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import XCTest
@testable import Common

final class StringExtensionTests: XCTestCase {

    func testWhenNormalizingStringsForAutofill_ThenDiacriticsAreRemoved() {
        let stringToNormalize = "Dáx Thê Dûck"
        let normalizedString = stringToNormalize.autofillNormalized()

        XCTAssertEqual(normalizedString, "daxtheduck")
    }

    func testWhenNormalizingStringsForAutofill_ThenWhitespaceIsRemoved() {
        let stringToNormalize = "Dax The Duck"
        let normalizedString = stringToNormalize.autofillNormalized()

        XCTAssertEqual(normalizedString, "daxtheduck")
    }

    func testWhenNormalizingStringsForAutofill_ThenPunctuationIsRemoved() {
        let stringToNormalize = ",Dax+The_Duck."
        let normalizedString = stringToNormalize.autofillNormalized()

        XCTAssertEqual(normalizedString, "daxtheduck")
    }

    func testWhenNormalizingStringsForAutofill_ThenNumbersAreRetained() {
        let stringToNormalize = "Dax123"
        let normalizedString = stringToNormalize.autofillNormalized()

        XCTAssertEqual(normalizedString, "dax123")
    }

    func testWhenNormalizingStringsForAutofill_ThenStringsThatDoNotNeedNormalizationAreUntouched() {
        let stringToNormalize = "firstmiddlelast"
        let normalizedString = stringToNormalize.autofillNormalized()

        XCTAssertEqual(normalizedString, "firstmiddlelast")
    }

    func testWhenNormalizingStringsForAutofill_ThenEmojiAreRemoved() {
        let stringToNormalize = "Dax 🤔"
        let normalizedString = stringToNormalize.autofillNormalized()

        XCTAssertEqual(normalizedString, "dax")
    }

    func testWhenEmojisArePresentInDomains_ThenTheseCanBePunycoded() {

        XCTAssertEqual("example.com".punycodeEncodedHostname, "example.com")
        XCTAssertEqual("Dax🤔.com".punycodeEncodedHostname, "xn--dax-v153b.com")
        XCTAssertEqual("🤔.com".punycodeEncodedHostname, "xn--wp9h.com")
    }

    func testHashedSuffix() {
        XCTAssertEqual("http://localhost:8084/#navlink".hashedSuffix, "#navlink")
        XCTAssertEqual("http://localhost:8084/#navlink#1".hashedSuffix, "#navlink#1")
        XCTAssertEqual("http://localhost:8084/#".hashedSuffix, "#")
        XCTAssertEqual("http://localhost:8084/##".hashedSuffix, "##")
        XCTAssertNil("http://localhost:8084/".hashedSuffix)
        XCTAssertNil("http://localhost:8084".hashedSuffix)
    }

    func testDroppingHashedSuffix() {
        XCTAssertEqual("http://localhost:8084/#navlink".droppingHashedSuffix(), "http://localhost:8084/")
        XCTAssertEqual("http://localhost:8084/#navlink#1".droppingHashedSuffix(), "http://localhost:8084/")
        XCTAssertEqual("about://blank/#navlink1".url!.absoluteString.droppingHashedSuffix(), "about://blank/")
        XCTAssertEqual("about:blank/#navlink1".url!.absoluteString.droppingHashedSuffix(), "about:blank/")
        XCTAssertEqual("about:blank#navlink1".url!.absoluteString.droppingHashedSuffix(), "about:blank")
    }

    // MARK: - File paths detection

    func testSanitize() {
        // both user file paths should be removed
        XCTAssertEqual("Error in /var/filename.txt In file included from /Volumes/data/framework dir".sanitized(), "Error in <removed> In file included from <removed>")

        // library names should stay
        // source files should be trimmed to the file name
        // path to the app should be trimmed to the bundle name
        XCTAssertEqual("""
        exception thrown in libobjc.A.dylib:
        UserScript/UserScript.swift:69: Fatal error: Failed to load JavaScript contentScope from \(Bundle.main.bundlePath)/Contents/Resources/ContentScopeScripts_ContentScopeScripts.bundle/Contents/Resources/contentScope.js
        """.sanitized(), """
        exception thrown in libobjc.A.dylib:
        UserScript.swift:69: Fatal error: Failed to load JavaScript contentScope from DuckDuckGo.app/Contents/Resources/ContentScopeScripts_ContentScopeScripts.bundle/Contents/Resources/contentScope.js
        """)

        // module name (Common) should stay
        // user file paths and names should be <removed>
        XCTAssertEqual("""
        Common/MainMenuActions.swift:686: Fatal error: 'try!' expression unexpectedly raised an error: Error Domain=NSCocoaErrorDomain Code=260 "The file “pa”th.txt” couldn’t be opened because there is no such file." UserInfo={NSFilePath=/non/exиstent file/pa”th.txt, NSUnderlyingError=0x600001a62580 {Error Domain=NSPOSIXErrorDomain Code=2 "No such file or directory"}}
        Error Domain=NSCocoaErrorDomain Code=260 "The file “pa”th.txt” couldn’t be opened because there is no such file." UserInfo={NSFilePath=/non/exis“tent folder/pa”th.txt, NSUnderlyingError=0x60000057da10 {Error Domain=NSPOSIXErrorDomain Code=2 "No such file or directory"}}
        """.sanitized(), """
        Common/MainMenuActions.swift:686: Fatal error: 'try!' expression unexpectedly raised an error: Error Domain=NSCocoaErrorDomain Code=260 "The file “<removed>” couldn’t be opened because there is no such file." UserInfo={NSFilePath=<removed>, NSUnderlyingError=0x600001a62580 {Error Domain=NSPOSIXErrorDomain Code=2 "No such file or directory"}}
        Error Domain=NSCocoaErrorDomain Code=260 "The file “<removed>” couldn’t be opened because there is no such file." UserInfo={NSFilePath=<removed>, NSUnderlyingError=0x60000057da10 {Error Domain=NSPOSIXErrorDomain Code=2 "No such file or directory"}}
        """)

        // library names should stay
        // app bundle URL should be trimmed to the bundle name
        XCTAssertEqual("""
        assertion failed: 23E224: libxpc.dylib + 202836 [C43D5322-9B69-37EE-B51E-45FDE5D81B5B]: 0x10000017
        assertion failed: 23E224: libxpc.dylib + 202836 [C43D5322-9B69-37EE-B51E-45FDE5D81B5B]: 0x10000017
        bundle \(Bundle.main.bundleURL.absoluteString)
        """.sanitized(), """
        assertion failed: 23E224: libxpc.dylib + 202836 [C43D5322-9B69-37EE-B51E-45FDE5D81B5B]: 0x10000017
        assertion failed: 23E224: libxpc.dylib + 202836 [C43D5322-9B69-37EE-B51E-45FDE5D81B5B]: 0x10000017
        bundle file:///DuckDuckGo.app/
        """)

        // source files should be trimmed to the file name
        // user file paths and names should be <removed>
        // email address should be <removed>
        XCTAssertEqual("""
        In file included from /Volumes/some мрé/directoy/3.33A.37.2/something else/dogs.txt,
         from /some/directoy/something else/dogs.txt, from ~/some/directoyr/3.33A.37.2/something else/dogs.txt, from /var/log/xyz/10032008. 10g,
        from /var/log/xyz/test.c: 29:
        Solution: please the file something.h has to be alone without others include, it has to be present in release letter,
        in order to be included in /var/log/xyz/test. automatically parse /the/file/name
        Other Note: send me an email at admin@duckduckgo.com!
        The file something. must contain the somethinge.h and not the ecpfmbsd.h because it doesn't contain C operative c in /var/filename.c.
        """.sanitized(), """
        In file included from <removed>,
         from <removed>, from <removed>, from <removed>. 10g,
        from test.c: 29:
        Solution: please the file <removed> has to be alone without others include, it has to be present in release letter,
        in order to be included in <removed>. automatically parse <removed>
        Other Note: send me an email at <removed>!
        The file something. must contain the <removed> and not the <removed> because it doesn't contain C operative c in filename.c.
        """)

        // no sensitive data hera
        XCTAssertEqual("""
        Error Domain=OSLogErrorDomain Code=-1 "issue with predicate: no such field: level" UserInfo={NSLocalizedDescription=issue with predicate: no such field: level}
        """.sanitized(), """
        Error Domain=OSLogErrorDomain Code=-1 "issue with predicate: no such field: level" UserInfo={NSLocalizedDescription=issue with predicate: no such field: level}
        """)

        // no sensitive data hera
        XCTAssertEqual("The application has crashed".sanitized(), "The application has crashed")

        // user file path should be <removed>
        XCTAssertEqual("""
        std::filesystem::filesystem_error: /home/user/Documents/Confidential/Report.pdf (No such file or directory)
        """.sanitized(), """
        std::filesystem::filesystem_error: <removed> (No such file or directory)
        """)

        // user file path should be <removed>
        XCTAssertEqual("""
        Unable to read file: /Users/JohnDoe/Documents/Secret/passwords.txt
        """.sanitized(), """
        Unable to read file: <removed>
        """)

        // URL should be <removed>
        XCTAssertEqual("""
        Illegal character in path at index 16: http://example.com/path/to/file?user=johndoe&password=secret
        """.sanitized(), """
        Illegal character in path at index 16: <removed>
        """)

        // URL should be <removed>
        XCTAssertEqual("""
        Read timed out at api.example.com/192.168.1.1
        """.sanitized(), """
        Read timed out at <removed>
        """)

        // user file path should be <removed>
        XCTAssertEqual("""
        terminate called after throwing an instance of 'std::runtime_error'
        what():  failed to open file: /home/user/documents/confidential/report.txt
        """.sanitized(), """
        terminate called after throwing an instance of 'std::runtime_error'
        what():  failed to open file: <removed>
        """)

        // user file path should be <removed>
        XCTAssertEqual("""
        std::filesystem::filesystem_error: cannot copy file: Permission denied [/home/user/secret/config.json]
        """.sanitized(), """
        std::filesystem::filesystem_error: cannot copy file: Permission denied [<removed>]
        """)

        // no sensitive data hera
        XCTAssertEqual("""
        terminate called after throwing an instance of 'std::out_of_range'
        what():  basic_string::substr: __pos (which is 10) > this->size() (which is 5)
        """.sanitized(), """
        terminate called after throwing an instance of 'std::out_of_range'
        what():  basic_string::substr: __pos (which is 10) > this->size() (which is 5)
        """)

        // user file path should be <removed>
        XCTAssertEqual("""
        *** Terminating app due to uncaught exception 'NSFileHandleOperationException', reason: '*** -[NSConcreteFileHandle readDataOfLength:]: No such file or directory ("/Users/johndoe/Library/Application Support/app/config.plist")'
        """.sanitized(), """
        *** Terminating app due to uncaught exception 'NSFileHandleOperationException', reason: '*** -[NSConcreteFileHandle readDataOfLength:]: No such file or directory ("<removed>")'
        """)

        // no sensitive data hera
        XCTAssertEqual("""
        *** Terminating app due to uncaught exception 'NSInvalidArgumentException', reason: '*** -[__NSArrayM objectAtIndex:]: index 10 beyond bounds [0 .. 5]'
        """.sanitized(), """
        *** Terminating app due to uncaught exception 'NSInvalidArgumentException', reason: '*** -[__NSArrayM objectAtIndex:]: index 10 beyond bounds [0 .. 5]'
        """)

        // user file path should be <removed>
        XCTAssertEqual("""
        Error Domain=NSCocoaErrorDomain Code=260 "The file “secrets.txt” couldn’t be opened because there is no such file." UserInfo={NSFilePath=/Users/janedoe/Documents/secrets.txt, NSUnderlyingError=0x600000c5e0 {Error Domain=NSPOSIXErrorDomain Code=2 "No such file or directory"}}
        """.sanitized(), """
        Error Domain=NSCocoaErrorDomain Code=260 "The file “<removed>” couldn’t be opened because there is no such file." UserInfo={NSFilePath=<removed>, NSUnderlyingError=0x600000c5e0 {Error Domain=NSPOSIXErrorDomain Code=2 "No such file or directory"}}
        """)

        // source files should be trimmed to the file name
        XCTAssertEqual("""
        Fatal error: Index out of range: file /Users/johndoe/Projects/Example/Example/ViewController.swift, line 32
        """.sanitized(), """
        Fatal error: Index out of range: file ViewController.swift, line 32
        """)

        // URL should be <removed>
        XCTAssertEqual("""
        Error Domain=WebKitErrorDomain Code=102 "Frame load interrupted" UserInfo={NSErrorFailingURLKey=https://example.com/path/to/file?user=johndoe&password=secret, NSErrorFailingURLStringKey=https://example.com/path/to/file?user=johndoe&password=secret}
        """.sanitized(), """
        Error Domain=WebKitErrorDomain Code=102 "Frame load interrupted" UserInfo={NSErrorFailingURLKey=<removed>, NSErrorFailingURLStringKey=<removed>}
        """)

        // URL should be <removed>
        XCTAssertEqual("""
        Uncaught JavaScript exception: TypeError: null is not an object (evaluating 'document.getElementById('username').value') in https://example.com/login.js at line 23
        """.sanitized(), """
        Uncaught JavaScript exception: TypeError: null is not an object (evaluating 'document.getElementById('username').value') in <removed> at line 23
        """)

        // user file path should be <removed>
        XCTAssertEqual("""
        FileAlreadyExistsException: File '/home/johndoe/backup/archive.zip' already exists. Mentioned in '/home/johndoe/backup/logs.txt'
        """.sanitized(), """
        FileAlreadyExistsException: File '<removed>' already exists. Mentioned in '<removed>'
        """)

        // source files should be trimmed to the file name
        XCTAssertEqual("""
        terminate called after throwing an instance of 'std::invalid_argument'
        what():  stoi: no conversion at /home/user/projects/app/source.cpp:85
        """.sanitized(), """
        terminate called after throwing an instance of 'std::invalid_argument'
        what():  stoi: no conversion at source.cpp:85
        """)

        // path to the app should be trimmed to the bundle name
        XCTAssertEqual("""
        *** Terminating app due to uncaught exception 'NSInternalInconsistencyException', reason: 'Could not load NIB in bundle: 'NSBundle <\(Bundle.main.bundleURL.path)> (loaded)' with name 'MainStoryboard''
        """.sanitized(), """
        *** Terminating app due to uncaught exception 'NSInternalInconsistencyException', reason: 'Could not load NIB in bundle: 'NSBundle <DuckDuckGo.app> (loaded)' with name 'MainStoryboard''
        """)

        // user file paths should be <removed>
        XCTAssertEqual("""
        *** Terminating app due to uncaught exception 'NSFileReadNoSuchFileError', reason: 'The file “data.json” couldn’t be opened because there is no such file in directory “/Users/janedoe/Library/Application Support/com.company.app”'
        """.sanitized(), """
        *** Terminating app due to uncaught exception 'NSFileReadNoSuchFileError', reason: 'The file “<removed>” couldn’t be opened because there is no such file in directory “<removed>”'
        """)

    }

}

private func + (lhs: UInt, rhs: String) -> (UInt, String) {
    (lhs, rhs)
}

