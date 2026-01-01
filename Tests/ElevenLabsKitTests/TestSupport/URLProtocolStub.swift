import Foundation

private final class URLProtocolStubStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var stubs: [URLProtocolStub.Stub] = []
    private var requestObserver: ((URLRequest) -> Void)?

    func setStubs(_ newValue: [URLProtocolStub.Stub]) {
        lock.lock()
        stubs = newValue
        lock.unlock()
    }

    func popStub() -> URLProtocolStub.Stub? {
        lock.lock()
        defer { lock.unlock() }
        guard !stubs.isEmpty else { return nil }
        return stubs.removeFirst()
    }

    func setRequestObserver(_ newValue: ((URLRequest) -> Void)?) {
        lock.lock()
        requestObserver = newValue
        lock.unlock()
    }

    func getRequestObserver() -> ((URLRequest) -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        return requestObserver
    }
}

class URLProtocolStub: URLProtocol {
    struct Stub {
        var response: HTTPURLResponse?
        var dataChunks: [Data]
        var error: Error?
    }

    private static let storage = URLProtocolStubStorage()

    static func setStubs(_ stubs: [Stub]) {
        storage.setStubs(stubs)
    }

    static func setRequestObserver(_ observer: ((URLRequest) -> Void)?) {
        storage.setRequestObserver(observer)
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.storage.getRequestObserver()?(request)

        guard let stub = Self.storage.popStub() else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "URLProtocolStub", code: 1))
            return
        }

        if let response = stub.response {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        for chunk in stub.dataChunks {
            client?.urlProtocol(self, didLoad: chunk)
        }
        if let error = stub.error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
