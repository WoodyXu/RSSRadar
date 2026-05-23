import Foundation

extension Optional where Wrapped == Date {
    var appRelativeDate: String {
        guard let date = self else {
            return "Never"
        }
        return date.appShortDate
    }

    var appShortDate: String {
        guard let date = self else {
            return "None"
        }
        return date.appShortDate
    }
}

extension Date {
    var appShortDate: String {
        formatted(date: .abbreviated, time: .shortened)
    }
}
