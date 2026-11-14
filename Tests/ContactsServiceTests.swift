import AppKit
import Contacts

@main struct ContactsServiceTests {
    static func main() {
        func wait(_ label: String, _ condition: () -> Bool) {
            let deadline = Date().addingTimeInterval(4)
            while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            precondition(condition(), label)
        }
        func tick(_ time: TimeInterval = 0.15) { RunLoop.main.run(until: Date().addingTimeInterval(time)) }
        let item = ContactPhone(contactID: "fixture", numberID: "n", name: "张三", label: "手机", rawNumber: "+86 13800123456")
        let native = CNMutableContact()
        native.familyName = "张"; native.givenName = "三"
        native.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "+86 13800123456"))]
        let nativePhones = ContactsSearch.phoneEntries(for: native)
        precondition(nativePhones.count == 1 && nativePhones[0].copyNumber == "13800123456")
        precondition(ContactSearchIndex(nativePhones).search("张三").count == 1, nativePhones[0].name)
        precondition(ContactSearchIndex(nativePhones).search("zhangsan").count == 1)
        native.familyName = "单"; native.givenName = "明"
        native.phoneticFamilyName = "shan"; native.phoneticGivenName = "ming"
        precondition(ContactSearchIndex(ContactsSearch.phoneEntries(for: native)).search("shanming").count == 1)
        native.phoneticGivenName = ""
        precondition(ContactSearchIndex(ContactsSearch.phoneEntries(for: native)).search("shan").isEmpty)
        var auth = CNAuthorizationStatus.notDetermined
        var asks = 0, loads = 0, changes = 0
        let center = NotificationCenter()
        var fail = false
        let service = ContactsSearch(authorization: { auth }, request: { reply in asks += 1; auth = .authorized; reply(true) }, load: { cancelled in
            precondition(!Thread.isMainThread); loads += 1
            if fail { throw NSError(domain: "fixture", code: 1) }
            return cancelled() ? ContactSearchIndex() : ContactSearchIndex([item])
        }, notifications: center)
        service.onChange = { precondition(Thread.isMainThread); changes += 1 }
        service.setEnabled(false); tick()
        precondition(asks == 0 && loads == 0 && service.index.search("张三").isEmpty)
        service.setEnabled(true); tick()
        precondition(service.state == .permissionRequired && asks == 0 && loads == 0)
        service.requestPermission()
        wait("explicit authorization then load") { service.state == .ready }
        precondition(asks == 1 && loads == 1 && service.index.search("zhangsan").count == 1)
        for _ in 0..<20 { service.refreshAuthorization() }
        precondition(loads == 1 && asks == 1)
        for _ in 0..<10 { center.post(name: .CNContactStoreDidChange, object: nil) }
        precondition(service.index.search("张三").isEmpty)
        wait("debounced change") { service.state == .ready }
        precondition(loads == 2)
        service.setEnabled(false)
        precondition(service.state == .disabled && service.index.search("张三").isEmpty)
        center.post(name: .CNContactStoreDidChange, object: nil); tick(0.5)
        precondition(loads == 2)
        service.setEnabled(true)
        wait("authorized re-enable") { service.state == .ready }
        precondition(asks == 1)
        auth = .denied; service.refreshAuthorization()
        precondition(service.state == .denied && service.index.search("张三").isEmpty)
        precondition(service.needsSystemSettings)
        auth = .authorized; fail = true; service.refreshAuthorization()
        wait("failure stays local") { service.state == .failed }
        fail = false; service.retry(); wait("explicit retry") { service.state == .ready }
        service.setEnabled(false)
        // An in-flight fetch must not publish after disabling, even if the loader ignores cancellation.
        let started = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let slow = ContactsSearch(authorization: { .authorized }, request: { _ in preconditionFailure() }, load: { _ in
            started.signal(); _ = release.wait(timeout: .now() + 3); return ContactSearchIndex([item])
        }, notifications: center)
        slow.setEnabled(true)
        precondition(started.wait(timeout: .now() + 2) == .success)
        slow.setEnabled(false); release.signal(); tick()
        precondition(slow.state == .disabled && slow.index.search("张三").isEmpty)
        // A cold saved-enable never displays a system authorization prompt.
        let denied = ContactsSearch(authorization: { .denied }, request: { _ in preconditionFailure() }, load: { _ in preconditionFailure() }, notifications: center)
        denied.setEnabled(true); precondition(denied.state == .denied)
        denied.setEnabled(false)
        precondition(changes > 0)
        print("PASS: no startup prompt/read; explicit access; background I/O; event coalescing; no polling; revoke/disable purge; failure/retry; stale-load cancellation; fake contacts only")
    }
}
