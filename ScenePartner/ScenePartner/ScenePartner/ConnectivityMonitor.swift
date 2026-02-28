// ConnectivityMonitor.swift
import Foundation
import Network
import Observation

@Observable
final class ConnectivityMonitor {

    private(set) var isConnected: Bool = false
    private(set) var connectionType: ConnectionType = .none

    enum ConnectionType { case none, wifi, cellular, wired, other }

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.scenepartner.connectivity")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.connectionType = Self.type(from: path)
            }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }

    private static func type(from path: NWPath) -> ConnectionType {
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.cellular) { return .cellular }
        if path.usesInterfaceType(.wiredEthernet) { return .wired }
        if path.status == .satisfied { return .other }
        return .none
    }
}
