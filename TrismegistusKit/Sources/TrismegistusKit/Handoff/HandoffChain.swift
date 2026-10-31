import Foundation

/// A thread: conversations linked by handoffs (`links`: newer id → the older id it continues), shown as one. The relay
/// keeps chains straight; these still stop at a loop or after `maxLinks`, since ids deleted elsewhere may linger.
public enum HandoffChain {
    /// The relay's limit per chain.
    public static let maxLinks = 32

    /// The parts `id` continues, newest first: the one it continues, then that one's, and so on. Ids that aren't listed
    /// are kept (the relay may still have them; a history that 404s is gone).
    public static func older(than id: String, links: [String: String]) -> [String] {
        var parts: [String] = []
        var seen: Set<String> = [id]
        var next = links[id]
        while let older = next, parts.count < maxLinks, seen.insert(older).inserted {
            parts.append(older)
            next = links[older]
        }
        return parts
    }

    /// The newest part of the thread `id` is in, moving only through listed ids (a link from a session deleted
    /// elsewhere leads nowhere).
    public static func tip(of id: String, links: [String: String], listed: Set<String>) -> String {
        var newer: [String: String] = [:]
        for (n, o) in links where listed.contains(n) { newer[o] = n }
        var tip = id
        var seen: Set<String> = [id]
        while let n = newer[tip], seen.count <= maxLinks, seen.insert(n).inserted { tip = n }
        return tip
    }

    /// Listed ids that a listed conversation continues: the lists show only the newest part of a thread.
    public static func continued(listed: Set<String>, links: [String: String]) -> Set<String> {
        Set(links.compactMap { n, o in listed.contains(n) && listed.contains(o) && n != o ? o : nil })
    }
}
