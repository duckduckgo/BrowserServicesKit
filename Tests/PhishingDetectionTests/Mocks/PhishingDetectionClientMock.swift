import Foundation
import PhishingDetection

public class MockPhishingDetectionClient: PhishingDetectionClientProtocol {

    public func updateFilterSet(revision: Int) async -> [Filter] {
        return [
            Filter(hashValue: "testhash1", regex: ".*example.*"),
            Filter(hashValue: "testhash2", regex: ".*test.*")
        ]
    }

    public func updateHashPrefixes(revision: Int) async -> [String] {
        return [
            "aa00bb11",
            "bb00cc11",
            "cc00dd11",
            "dd00ee11",
            "a379a6f6"
        ]
    }

    public func getMatches(hashPrefix: String) async -> [Match] {
        return [
            Match(hostname: "example.com", url: "https://example.com/mal", regex: ".", hash: "a379a6f6eeafb9a55e378c118034e2751e682fab9f2d30ab13d2125586ce1947"),
            Match(hostname: "test.com", url: "https://test.com/mal", regex: ".*test.*", hash: "aa00bb11aa00cc11bb00cc11")
        ]
    }
}

