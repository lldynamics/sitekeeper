actor SearchTestGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private(set) var wasCancelled = false

    func suspend() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started?.resume()
            started = nil
        }
    }

    func waitUntilStarted() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { started = $0 }
    }

    func recordCancellation(_ value: Bool) { wasCancelled = value }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
