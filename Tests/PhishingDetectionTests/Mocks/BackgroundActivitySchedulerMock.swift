import PhishingDetection

class MockBackgroundActivityScheduler: BackgroundActivityScheduling {
    var startCalled = false
    var stopCalled = false
    var interval: Int = 1
    var identifier: String = "test"

    func start(activity: @escaping () async -> Void) {
        startCalled = true
    }

    func stop() {
        stopCalled = true
    }
}
