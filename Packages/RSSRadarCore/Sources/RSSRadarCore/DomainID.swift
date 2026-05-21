import Foundation

public enum DomainID {
    public static func make() -> String {
        UUID().uuidString
    }
}
