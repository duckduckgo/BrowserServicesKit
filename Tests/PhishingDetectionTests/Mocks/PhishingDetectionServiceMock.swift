import Foundation
import PhishingDetection

public class MockPhishingDetectionService: PhishingDetectionServiceProtocol {
    private var mockClient: PhishingDetectionClientProtocol
    private var hashPrefixes: [String] = []
    private var filterSet: [Filter] = []
    private var revision = 0
    public var didUpdateHashPrefixes: Bool = false
    public var didUpdateFilterSet: Bool = false

    init() {
        self.mockClient = MockPhishingDetectionClient()
    }

    public func updateFilterSet() async {
        filterSet = await mockClient.updateFilterSet(revision: revision)
        if !filterSet.isEmpty {
            didUpdateFilterSet = true
        }
    }

    public func updateHashPrefixes() async {
        hashPrefixes = await mockClient.updateHashPrefixes(revision: revision)
        if !hashPrefixes.isEmpty {
            didUpdateHashPrefixes = true
        }
    }

    public func getMatches(hashPrefix: String) async -> [Match] {
        return await mockClient.getMatches(hashPrefix: hashPrefix)
    }

    public func isMalicious(url: String) async -> Bool {
        return false
    }
    
    public func loadData() {
        didUpdateHashPrefixes = true
        didUpdateFilterSet = true
        return
    }
}

