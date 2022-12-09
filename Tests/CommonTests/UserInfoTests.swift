//
//  UserInfoTests.swift
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

import XCTest
@testable import Common

private struct TestUserInfo1 {
    static func value(in userInfo: UserInfo) -> String {
        return userInfo.testStr
    }
    static func setValue(_ value: String, in userInfo: inout UserInfo) {
        userInfo.testStr = value
    }
}

private extension UserInfo.Values {
    var testStr: String { "test1" }
    var testBool: Bool { true }
}

final class UserInfoTests: XCTestCase {

    func testBoolValues() {
        var ui1 = UserInfo()
        var ui2 = UserInfo()
        XCTAssertTrue(ui1.testBool)
        XCTAssertTrue(ui2.testBool)

        ui1.testBool.toggle()
        ui2.testBool = true
        XCTAssertFalse(ui1.testBool)
        XCTAssertTrue(ui2.testBool)

        ui1.testBool = true
        ui2.testBool = false
        XCTAssertTrue(ui1.testBool)
        XCTAssertFalse(ui2.testBool)
    }

    func testWhenSameNameUsedInPrivateValueExtensions_valuesAreDifferent() {
        var ui = UserInfo()
        XCTAssertEqual(ui.testStr, "test1")
        XCTAssertEqual(TestUserInfo1.value(in: ui), "test1")
        XCTAssertEqual(TestUserInfo2.value(in: ui), "test2")

        ui.testStr = "mod1"
        XCTAssertEqual(ui.testStr, "mod1")
        XCTAssertEqual(TestUserInfo1.value(in: ui), "mod1")
        XCTAssertEqual(TestUserInfo2.value(in: ui), "test2")

        TestUserInfo1.setValue("mod2", in: &ui)
        XCTAssertEqual(ui.testStr, "mod2")
        XCTAssertEqual(TestUserInfo1.value(in: ui), "mod2")
        XCTAssertEqual(TestUserInfo2.value(in: ui), "test2")

        TestUserInfo2.setValue("mod3", in: &ui)
        XCTAssertEqual(ui.testStr, "mod2")
        XCTAssertEqual(TestUserInfo1.value(in: ui), "mod2")
        XCTAssertEqual(TestUserInfo2.value(in: ui), "mod3")
    }

}
