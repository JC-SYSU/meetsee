import Foundation

@main struct ContactsTests {
    static func main() throws {
        let a = ContactPhone(contactID: "a", numberID: "mobile", name: "张三", label: "手机", rawNumber: "+86 138 0012 3456")
        let b = ContactPhone(contactID: "a", numberID: "work", name: "张三", label: "工作", rawNumber: "010-12345678 转 801")
        let c = ContactPhone(contactID: "b", numberID: "mobile", name: "张三", label: "手机", rawNumber: "139 0012 3456")
        let index = ContactSearchIndex([a, b, c])
        for q in ["张三", "zhangsan", "ZHANGSAN", " zhangsan ", "zhang san"] {
            precondition(index.search(q).count == 3, q)
        }
        for q in ["", "张", "三", "zhang", "san", "zs", "张san", "13800123456", "zhang-san"] {
            precondition(index.search(q).isEmpty, q)
        }
        let phonetic = ContactPhone(contactID: "d", numberID: "n", name: "单明", label: "手机", rawNumber: "13800123456", phoneticNames: ["shan ming"])
        precondition(ContactSearchIndex([phonetic]).search("shanming").count == 1)
        precondition(a.copyNumber == "13800123456")
        precondition(b.copyNumber == "01012345678" && b.hasExtension)
        let examples: [(String, String?)] = [
            ("0086 138-0012-3456", "13800123456"), ("+ 86 13800123456", "13800123456"), ("8613800123456", "8613800123456"),
            ("+1 (415) 555-0123", "14155550123"), ("０１３８ ００１２ ３４５６", "013800123456"),
            ("010-12345678 ext. 801", "01012345678"), ("01012345678;ext=801", "01012345678"),
            ("01012345678 x801", "01012345678"), ("01012345678#801", "01012345678"),
            ("13800123456/13900123456", nil), ("*123#", nil), ("123,456", nil), ("", nil),
            ("+86 12", "8612"), ("+86 10 1234 5678", "1012345678"), ("+44 020 1234 5678", "4402012345678")
        ]
        for (raw, expected) in examples {
            let item = ContactPhone(contactID: "test", numberID: raw, name: "测试", label: "", rawNumber: raw)
            precondition(item.copyNumber == expected, raw)
            if let text = item.copyNumber { precondition(!text.isEmpty && text.utf8.allSatisfy { (48...57).contains($0) }) }
        }
        let duplicate = ContactPhone(contactID: "a", numberID: "duplicate", name: "张三", label: "其他", rawNumber: "13800123456")
        precondition(ContactSearchIndex([a, duplicate, c]).search("张三").count == 2)
        precondition(ContactSearchIndex([b, ContactPhone(contactID: "a", numberID: "ext2", name: "张三", label: "工作", rawNumber: "01012345678 转 802")]).search("张三").count == 2)
        let old = Settings(); precondition(old.searchContacts != true)
        var settings = old; settings.searchContacts = true; settings.searchSystemSettings = false; settings.limit = 5
        let update = SettingsUpdate(from: old, to: settings)
        precondition(update.queryChanged && !update.needsScan && !update.scopeChanged)
        let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        precondition(decoded.searchContacts == true)
        let empty = SearchResult(entries: [], total: 0)
        let merged = mergeSettings(empty, pages: [], query: "张三", settings: settings, contacts: index.search("张三"))
        precondition(merged.total == 3 && merged.items.count == 3 && merged.items[0].contact?.copyNumber == a.copyNumber)
        precondition(mergeSettings(empty, pages: [], query: "张三", settings: old, contacts: index.search("张三")).total == 0)
        let app = Entry(path: "/test/张三.app", directory: true)
        settings.applicationsFirst = true
        let files = SearchResult(entries: [app], total: 1)
        let priority = mergeSettings(files, pages: [], query: "张三", settings: settings, contacts: [a])
        precondition(priority.items.first?.file?.kind == .application)
        settings.pinnedItems = [try PinnedItem.make(term: "张三", target: "https://example.com", name: "置顶", others: [])]
        precondition(mergePinned(priority, files: files, query: "张三", settings: settings).items.first?.isPinned == true)
        let changed = SearchCandidate.contact(ContactPhone(contactID: "a", numberID: "mobile", name: "张三", label: "手机", rawNumber: "13700123456"))
        precondition(candidateRowsNeedingReload([.contact(a)], [changed]) == IndexSet(integer: 0))
        precondition(changed.selectionIdentity == SearchCandidate.contact(a).selectionIdentity)
        let large = ContactSearchIndex((0..<10000).map { ContactPhone(contactID: "p" + String($0), numberID: "n", name: "Person " + String($0), label: "手机", rawNumber: "13800123456") })
        precondition(large.search("Person 9999").count == 1 && large.search("Person 999").count == 1 && large.search("Person").isEmpty)
        let start = Date(); for _ in 0..<10000 { _ = index.search("zhangsan") }
        print("PASS: exact names/full pinyin only; conservative phone normalization; extensions; dedup; source toggle; ranking/pins; stable identity; 10k lookups \(Int(Date().timeIntervalSince(start)*1000))ms")
    }
}
