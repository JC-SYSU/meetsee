import AppKit
import Contacts

/// The only module allowed to touch CNContactStore. All public methods and
/// callbacks are main-thread confined; database I/O/transliteration run off-main.
final class ContactsSearch {
    enum State: Equatable { case disabled, permissionRequired, denied, loading, ready, failed }
    private(set) var state: State = .disabled
    private(set) var enabled = false
    private(set) var index = ContactSearchIndex()
    var onChange: (() -> Void)?
    private let queue = DispatchQueue(label: "QuickFind.contacts", qos: .utility)
    private let authorization: () -> CNAuthorizationStatus
    private let request: (@escaping (Bool) -> Void) -> Void
    private let load: (@escaping () -> Bool) throws -> ContactSearchIndex
    private let notifications: NotificationCenter
    private var observer: NSObjectProtocol?
    private var pending: DispatchWorkItem?
    private var revision = 0
    private var token: LoadToken?
    private var lastAuthorization: CNAuthorizationStatus?
    private final class LoadToken {
        private let lock = NSLock()
        private var cancelled = false
        func cancel() { lock.lock(); cancelled = true; lock.unlock() }
        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    }
    init(authorization: @escaping () -> CNAuthorizationStatus = { CNContactStore.authorizationStatus(for: .contacts) },
         request: @escaping (@escaping (Bool) -> Void) -> Void = { reply in
             CNContactStore().requestAccess(for: .contacts) { granted, _ in reply(granted) }
         },
         load: @escaping (@escaping () -> Bool) throws -> ContactSearchIndex = ContactsSearch.fetch,
         notifications: NotificationCenter = .default) {
        self.authorization = authorization; self.request = request; self.load = load; self.notifications = notifications
    }
    deinit { token?.cancel(); pending?.cancel(); if let observer { notifications.removeObserver(observer) } }
    private static func canRead(_ value: CNAuthorizationStatus) -> Bool {
        value == .authorized
    }
    var needsSystemSettings: Bool { authorization() == .denied || authorization() == .restricted }
    var permissionGranted: Bool { Self.canRead(authorization()) }
    var statusText: String {
        switch state {
        case .disabled: return "未启用 · 仅在主动授权后读取通讯录"
        case .permissionRequired: return "尚未授权 · 点击授权访问"
        case .denied: return "访问受限或已拒绝 · 请在系统设置中允许访问"
        case .loading: return "正在后台加载通讯录…"
        case .ready: return "通讯录已就绪 · 仅在本机内存中检索"
        case .failed: return "通讯录读取失败 · 可点击重试，不影响文件搜索"
        }
    }
    func setEnabled(_ value: Bool) {
        guard enabled != value else { refreshAuthorization(); return }
        enabled = value
        revision += 1; token?.cancel(); pending?.cancel()
        index = ContactSearchIndex(); lastAuthorization = nil
        if !value {
            if let observer { notifications.removeObserver(observer); self.observer = nil }
            state = .disabled; onChange?(); return
        }
        observer = notifications.addObserver(forName: .CNContactStoreDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.scheduleRefresh()
        }
        refreshAuthorization()
    }
    /// Never requests permission: safe on launch and whenever the app regains focus.
    func refreshAuthorization() {
        guard enabled else { return }
        let current = authorization()
        guard lastAuthorization != current else { return }
        lastAuthorization = current
        if Self.canRead(current) { scheduleRefresh(immediate: true) }
        else {
            revision += 1; token?.cancel(); pending?.cancel(); index = ContactSearchIndex()
            state = current == .notDetermined ? .permissionRequired : .denied; onChange?()
        }
    }
    /// Call only after an explicit enable/save or authorization button click.
    func requestPermission(_ completion: @escaping () -> Void = {}) {
        guard authorization() == .notDetermined else {
            lastAuthorization = nil; refreshAuthorization(); completion(); return
        }
        request { [weak self] _ in
            DispatchQueue.main.async {
                self?.lastAuthorization = nil; self?.refreshAuthorization(); completion()
            }
        }
    }
    func retry() { if enabled { scheduleRefresh(immediate: true) } }
    private func scheduleRefresh(immediate: Bool = false) {
        guard enabled else { return }
        guard Self.canRead(authorization()) else { lastAuthorization = nil; refreshAuthorization(); return }
        revision += 1; let version = revision
        token?.cancel(); pending?.cancel(); let current = LoadToken(); token = current
        // Invalidate old objects immediately on change, not just after refetch.
        index = ContactSearchIndex(); state = .loading; onChange?()
        let loader = load
        let work = DispatchWorkItem { [weak self] in
            guard !current.isCancelled else { return }
            let loaded = Result { try loader { current.isCancelled } }
            DispatchQueue.main.async {
                guard let self, self.enabled, self.revision == version, !current.isCancelled else { return }
                guard Self.canRead(self.authorization()) else { self.lastAuthorization = nil; self.refreshAuthorization(); return }
                switch loaded {
                case .success(let index): self.index = index; self.state = .ready
                case .failure: self.index = ContactSearchIndex(); self.state = .failed
                }
                self.onChange?()
            }
        }
        pending = work; queue.asyncAfter(deadline: .now() + (immediate ? 0 : 0.4), execute: work)
    }
    static func fetch(cancelled: @escaping () -> Bool) throws -> ContactSearchIndex {
        let keys: [CNKeyDescriptor] = [CNContactIdentifierKey as CNKeyDescriptor,
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactPhoneticFamilyNameKey as CNKeyDescriptor, CNContactPhoneticGivenNameKey as CNKeyDescriptor,
            CNContactPhoneticMiddleNameKey as CNKeyDescriptor, CNContactPhoneNumbersKey as CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.unifyResults = true; request.sortOrder = .userDefault
        var phones: [ContactPhone] = []
        try CNContactStore().enumerateContacts(with: request) { contact, stop in
            if cancelled() { stop.pointee = true; return }
            phones += phoneEntries(for: contact)
        }
        return cancelled() ? ContactSearchIndex() : ContactSearchIndex(phones)
    }

    static func phoneEntries(for contact: CNContact) -> [ContactPhone] {
        guard !contact.givenName.isEmpty || !contact.familyName.isEmpty,
              let name = CNContactFormatter.string(from: contact, style: .fullName), !name.isEmpty else { return [] }
        let phonetic = (CNContactFormatter.nameOrder(for: contact) == .familyNameFirst
            ? [contact.phoneticFamilyName, contact.phoneticMiddleName, contact.phoneticGivenName]
            : [contact.phoneticGivenName, contact.phoneticMiddleName, contact.phoneticFamilyName])
            .filter { !$0.isEmpty }.joined(separator: " ")
        // An incomplete phonetic name must not become a partial-name alias.
        let completePhonetic = (contact.givenName.isEmpty || !contact.phoneticGivenName.isEmpty)
            && (contact.familyName.isEmpty || !contact.phoneticFamilyName.isEmpty)
            && (contact.middleName.isEmpty || !contact.phoneticMiddleName.isEmpty)
        var phones: [ContactPhone] = []
        for value in contact.phoneNumbers where !value.value.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            phones.append(ContactPhone(contactID: contact.identifier, numberID: value.identifier,
                name: name, label: value.label.map { CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: $0) } ?? "电话",
                rawNumber: value.value.stringValue, phoneticNames: completePhonetic && !phonetic.isEmpty ? [phonetic] : []))
        }
        return phones
    }
}
