import Foundation
import PhishingDetection

public class MockPhishingDetectionService: PhishingDetectionServiceProtocol {
    private var mockClient: PhishingDetectionClientProtocol
    public var hashPrefixes: Set<String> = Set()
    private var revision = 0
    public var filterSet: Set<Filter> = Set()
    public var didUpdateHashPrefixes: Bool = false
    public var didUpdateFilterSet: Bool = false

    init() {
        self.mockClient = MockPhishingDetectionClient()
    }

    public func updateFilterSet() async {
        let filterSetArray = await mockClient.updateFilterSet(revision: revision)
        filterSet = Set(filterSetArray)
        if !filterSet.isEmpty {
            didUpdateFilterSet = true
        }
    }

    public func updateHashPrefixes() async {
        let hashPrefixesArray = await mockClient.updateHashPrefixes(revision: revision)
        hashPrefixes = Set(hashPrefixesArray)
        if !hashPrefixes.isEmpty {
            didUpdateHashPrefixes = true
        }
    }

    public func getMatches(hashPrefix: String) async -> Set<Match> {
        let matches = await mockClient.getMatches(hashPrefix: hashPrefix)
        return Set(matches)
    }

    public func isMalicious(url: URL) async -> Bool {
        return false
    }
    
    public func loadData() {
        didUpdateHashPrefixes = true
        didUpdateFilterSet = true
        return
    }
    
    public func writeData() {
        return
    }
}

