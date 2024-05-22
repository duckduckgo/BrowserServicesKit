import Foundation
import PhishingDetection

public class MockPhishingDetectionService: PhishingDetectionServiceProtocol {
    private var mockClient: PhishingDetectionClientProtocol
    public var hashPrefixes: Set<String> = Set()
    private var currentRevision = 0
    public var filterSet: Set<Filter> = Set()
    public var didUpdateHashPrefixes: Bool = false
    public var didUpdateFilterSet: Bool = false

    public var updateFilterSetCompletion: (() -> Void)?
    public var updateHashPrefixesCompletion: (() -> Void)?

    init() {
        self.mockClient = MockPhishingDetectionClient()
    }

    public func updateFilterSet() async {
        let response = await mockClient.getFilterSet(revision: currentRevision)
        switch response {
        case .filterSetResponse(let fullResponse):
            currentRevision = fullResponse.revision
            filterSet = Set(fullResponse.filters)
        case .filterSetUpdateResponse(let updateResponse):
            currentRevision = updateResponse.revision
            updateResponse.insert.forEach { self.filterSet.insert($0) }
            updateResponse.delete.forEach { self.filterSet.remove($0) }
        }
        didUpdateFilterSet = true
        updateFilterSetCompletion?()
    }

    public func updateHashPrefixes() async {
        let response = await mockClient.getHashPrefixes(revision: currentRevision)
        switch response {
        case .hashPrefixResponse(let fullResponse):
            currentRevision = fullResponse.revision
            hashPrefixes = Set(fullResponse.hashPrefixes)
        case .hashPrefixUpdateResponse(let updateResponse):
            currentRevision = updateResponse.revision
            updateResponse.insert.forEach { self.hashPrefixes.insert($0) }
            updateResponse.delete.forEach { self.hashPrefixes.remove($0) }
        }
        didUpdateHashPrefixes = true
        updateHashPrefixesCompletion?()
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
