// ConnectivityMonitor.swift
import Foundation
import Network
import Combine

final class ConnectivityMonitor: ObservableObject {
    @Published private(set) var isConnected: Bool = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.scenepartner.connectivity")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async { self?.isConnected = path.status == .satisfied }
        }
        monitor.start(queue: queue)
    }
    deinit { monitor.cancel() }
}
