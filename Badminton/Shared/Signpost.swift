import os
import os.signpost

enum SignpostLog {
    static let subsystem = "com.bebopbeluga.Badminton"
    static let navigation = OSLog(subsystem: subsystem, category: "Navigation")
    static let tmdb = OSLog(subsystem: subsystem, category: "TMDB")
}

struct SignpostInterval {
    let name: StaticString
    let log: OSLog
    let id: OSSignpostID

    func end(_ format: StaticString = "", _ args: CVarArg...) {
        os_signpost(.end, log: log, name: name, signpostID: id, format, args)
    }
}

enum Signpost {
    @discardableResult
    static func begin(_ name: StaticString, log: OSLog, _ format: StaticString = "", _ args: CVarArg...) -> SignpostInterval {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id, format, args)
        return SignpostInterval(name: name, log: log, id: id)
    }

    static func event(_ name: StaticString, log: OSLog, _ format: StaticString = "", _ args: CVarArg...) {
        os_signpost(.event, log: log, name: name, format, args)
    }
}
