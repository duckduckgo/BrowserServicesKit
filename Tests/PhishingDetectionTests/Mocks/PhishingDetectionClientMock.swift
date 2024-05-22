import Foundation
import PhishingDetection

public class MockPhishingDetectionClient: PhishingDetectionClientProtocol {
    private var filterRevisions: [Int: FilterSetResponseGeneric] = [
        0: FilterSetResponseGeneric(filters: [
            Filter(hashValue: "testhash1", regex: ".*example.*"),
            Filter(hashValue: "testhash2", regex: ".*test.*")
        ], revision: 0),
        1: FilterSetResponseGeneric(filters: [
            Filter(hashValue: "testhash3", regex: ".*test.*")
        ], revision: 1, delete: [
            Filter(hashValue: "testhash1", regex: ".*example.*"),
        ])
    ]

    private var hashPrefixRevisions: [Int: HashPrefixResponseGeneric] = [
        0: HashPrefixResponseGeneric(hashPrefixes: [
            "aa00bb11",
            "bb00cc11",
            "cc00dd11",
            "dd00ee11",
            "a379a6f6"
        ], revision: 0),
        1: HashPrefixResponseGeneric(hashPrefixes: ["93e2435e"], revision: 1, delete: [
            "cc00dd11",
            "dd00ee11",
        ])
    ]

    public func getFilterSet(revision: Int) async -> FilterSetResponseGeneric {
        return filterRevisions[revision] ?? FilterSetResponseGeneric(filters: [], revision: revision)
    }

    public func getHashPrefixes(revision: Int) async -> HashPrefixResponseGeneric {
        return hashPrefixRevisions[revision] ?? HashPrefixResponseGeneric(hashPrefixes: [], revision: revision)
    }

    public func getMatches(hashPrefix: String) async -> [Match] {
        return [
            Match(hostname: "example.com", url: "https://example.com/mal", regex: ".", hash: "a379a6f6eeafb9a55e378c118034e2751e682fab9f2d30ab13d2125586ce1947"),
            Match(hostname: "test.com", url: "https://test.com/mal", regex: ".*test.*", hash: "aa00bb11aa00cc11bb00cc11")
        ]
    }
}
