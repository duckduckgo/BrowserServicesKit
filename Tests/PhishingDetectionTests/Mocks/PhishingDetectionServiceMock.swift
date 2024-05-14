import Foundation
import PhishingDetection

public class MockPhishingDetectionAPIService: PhishingDetectionAPIServiceProtocol {
    public func updateFilterSet(revision: Int) async -> [Filter] {
        let json = """
        {
            "filters": [
                {"hash": "testhash1", "regex": ".*example.*"},
                {"hash": "testhash2", "regex": ".*test.*"}
            ],
            "revision": 1
        }
        """
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        let response: FilterSetResponse = try! decoder.decode(FilterSetResponse.self, from: data)
        return response.filters
    }

    public func updateHashPrefixes(revision: Int) async -> [String] {
        let json = """
        {
            "hashPrefixes": [
                "aa00bb11",
                "bb00cc11",
                "cc00dd11",
                "dd00ee11",
                "a379a6f6"
            ],
            "revision": 1
        }
        """
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        let response: HashPrefixResponse = try! decoder.decode(HashPrefixResponse.self, from: data)
        return response.hashPrefixes
    }

    public func getMatches(hashPrefix: String) async -> [Match] {
        let json = """
        {
            "matches": [
                {"hash": "a379a6f6eeafb9a55e378c118034e2751e682fab9f2d30ab13d2125586ce1947", "regex": ".", "hostname": "example.com", "url": "https://example.com/mal"},
                {"hash": "aa00bb11aa00cc11bb00cc11", "regex": ".*test.*", "hostname": "test.com", "url": "https://test.com/mal"}
            ],
            "revision": 1
        }
        """
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        let response: MatchResponse = try! decoder.decode(MatchResponse.self, from: data)
        return response.matches
    }
}
