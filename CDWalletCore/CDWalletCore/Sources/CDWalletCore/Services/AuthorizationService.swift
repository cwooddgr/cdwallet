import Foundation
import MusicKit

/// Manages MusicKit authorization
public actor AuthorizationService {
    public init() {}

    public var status: MusicAuthorization.Status {
        MusicAuthorization.currentStatus
    }

    /// Request authorization if needed; returns true if authorized
    public func ensureAuthorized() async -> Bool {
        let status = MusicAuthorization.currentStatus

        switch status {
        case .authorized:
            return true
        case .notDetermined, .denied, .restricted:
            let newStatus = await MusicAuthorization.request()
            return newStatus == .authorized
        @unknown default:
            return false
        }
    }
}
