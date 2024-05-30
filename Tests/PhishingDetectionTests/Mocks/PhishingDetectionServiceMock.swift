import Foundation
import PhishingDetection

public class MockPhishingDetectionService: PhishingDetectionServiceProtocol {
    private var mockClient: PhishingDetectionClientProtocol
    public var hashPrefixes: Set<String> = Set()
    private var currentRevision = 0
    public var filterSet: Set<Filter> = Set()
    public var didUpdateHashPrefixes: Bool = false
    public var didUpdateFilterSet: Bool = false
    var completionHandler: (() -> Void)?

    init() {
        self.mockClient = MockPhishingDetectionClient()
    }

    public func updateFilterSet() async {
        let response = await mockClient.getFilterSet(revision: currentRevision)
        if response.replace {
            currentRevision = response.revision
            filterSet = Set(response.insert)
        } else {
            currentRevision = response.revision
            response.insert.forEach { self.filterSet.insert($0) }
            response.delete.forEach { self.filterSet.remove($0) }
        }
        didUpdateFilterSet = true
        checkCompletion()
    }

    public func updateHashPrefixes() async {
        let response = await mockClient.getHashPrefixes(revision: currentRevision)
        if response.replace {
            currentRevision = response.revision
            hashPrefixes = Set(response.insert)
        } else {
            currentRevision = response.revision
            response.insert.forEach { self.hashPrefixes.insert($0) }
            response.delete.forEach { self.hashPrefixes.remove($0) }
        }
        didUpdateHashPrefixes = true
        checkCompletion()
    }
    
    private func checkCompletion() {
        if didUpdateFilterSet && didUpdateHashPrefixes {
            completionHandler?()
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
