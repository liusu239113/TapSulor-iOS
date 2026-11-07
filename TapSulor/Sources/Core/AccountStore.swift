import Foundation

/// 账号仓库：accounts.json 的读写，以及登录 / 会话 / 工作室 / 删除的规则。
/// 纯逻辑，不依赖 WebKit；WKWebsiteDataStore 的创建与删除由 AppCoordinator 负责。
///
/// 与安卓 / 桌面版的差异：每个账号使用独立的 WKWebsiteDataStore（storeId），
/// 不再像桌面版那样在切换时复制 Cookie。
final class AccountStore {
    /// 登录结果：告诉调用方哪个存储要保留、哪个要删除
    struct LoginOutcome {
        var account: AccountRecord
        var isNew: Bool
        /// 是否切换了当前账号（add 模式为 false）
        var switched: Bool
        /// 本次登录所用的新存储是否已经归某个账号所有；false 时应删除该存储
        var keptLoginStore: Bool
        /// 被替换掉的旧存储；调用方在切换页面之后再删除
        var staleStoreId: String?
    }

    private(set) var file: AccountsFile
    private let fileURL: URL?

    init(fileURL: URL?) {
        self.fileURL = fileURL
        self.file = AccountStore.read(fileURL) ?? AccountsFile(current: nil, accounts: [])
    }

    var accounts: [AccountRecord] {
        file.accounts
    }

    var current: AccountRecord? {
        guard let id = file.current else { return nil }
        return file.accounts.first { $0.id == id }
    }

    /// 当前生效的开发者 ID（切换工作室后为选中的工作室）
    var activeDeveloperId: String? {
        guard let account = current else { return nil }
        return account.activeDeveloperId ?? account.developerId
    }

    func account(id: String) -> AccountRecord? {
        file.accounts.first { $0.id == id }
    }

    static func makeAccountID() -> String {
        "acc-\(Int(Date().timeIntervalSince1970 * 1000))-\(Int.random(in: 0..<10_000))"
    }

    // MARK: - 持久化

    private static func read(_ url: URL?) -> AccountsFile? {
        guard let url = url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AccountsFile.self, from: data)
    }

    func save() {
        guard let url = fileURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(file).write(to: url, options: .atomic)
        } catch {
            NSLog("[AccountStore] 保存 accounts.json 失败：\(error)")
        }
    }

    // MARK: - 规则

    /// 登录成功：写入或更新账号（对齐桌面版 upsertAccountFromProbe）。
    func applyLogin(developerId: String, profile: IdentityProfile, loginStoreId: String, mode: LoginMode) -> LoginOutcome {
        let isAdd = mode == .add
        var outcome: LoginOutcome

        if let index = file.accounts.firstIndex(where: { $0.developerId == developerId }) {
            var account = file.accounts[index]
            var stale: String? = nil
            var kept = false
            // add 模式不动已有账号的存储，避免新登录覆盖当前账号的会话
            if !isAdd && account.storeId != loginStoreId {
                stale = account.storeId
                account.storeId = loginStoreId
                kept = true
            }
            merge(profile, into: &account)
            file.accounts[index] = account
            outcome = LoginOutcome(account: account, isNew: false, switched: !isAdd,
                                   keptLoginStore: kept, staleStoreId: stale)
        } else {
            var account = AccountRecord(
                id: AccountStore.makeAccountID(),
                name: "",
                developerId: developerId,
                developerName: "",
                developerAvatar: "",
                nickname: "",
                avatar: "",
                storeId: loginStoreId,
                studios: [],
                activeDeveloperId: nil
            )
            merge(profile, into: &account)
            if account.name.isEmpty {
                account.name = profile.nickname.isEmpty
                    ? (profile.developerName.isEmpty ? "开发者 " + String(developerId.suffix(4)) : profile.developerName)
                    : profile.nickname
            }
            file.accounts.append(account)
            outcome = LoginOutcome(account: account, isNew: true, switched: !isAdd,
                                   keptLoginStore: true, staleStoreId: nil)
        }

        if !isAdd || file.current == nil {
            file.current = outcome.account.id
        }
        save()
        return outcome
    }

    /// 页面检查登录态（不涉及存储切换）时同步账号资料；返回对应的账号。
    /// 没有任何账号时，把系统默认存储里的会话收养为一个账号（storeId 为 nil）。
    func applySession(developerId: String, profile: IdentityProfile) -> AccountRecord? {
        if let index = file.accounts.firstIndex(where: { $0.developerId == developerId }) {
            var account = file.accounts[index]
            merge(profile, into: &account)
            file.accounts[index] = account
            file.current = account.id
            save()
            return account
        }

        if let index = file.accounts.firstIndex(where: { $0.id == file.current }) {
            // 当前账号存储里的会话已经换成了别的开发者：就地改绑，存储保持不变
            var account = file.accounts[index]
            account.developerId = developerId
            account.activeDeveloperId = nil
            merge(profile, into: &account)
            file.accounts[index] = account
            save()
            return account
        }

        if file.accounts.isEmpty {
            var account = AccountRecord(
                id: AccountStore.makeAccountID(),
                name: profile.nickname.isEmpty ? "TapTap " + developerId : profile.nickname,
                developerId: developerId,
                developerName: "",
                developerAvatar: "",
                nickname: "",
                avatar: "",
                storeId: nil,
                studios: [],
                activeDeveloperId: nil
            )
            merge(profile, into: &account)
            file.accounts.append(account)
            file.current = account.id
            save()
            return account
        }
        return nil
    }

    func setCurrent(id: String) -> Bool {
        guard file.accounts.contains(where: { $0.id == id }) else { return false }
        file.current = id
        save()
        return true
    }

    /// 切换工作室（对齐桌面版 switchStudio：记录选中的开发者，并同步显示名称与头像）
    func setActiveStudio(developerId: String) -> Bool {
        guard let index = file.accounts.firstIndex(where: { $0.id == file.current }) else { return false }
        var account = file.accounts[index]
        account.activeDeveloperId = developerId
        if let picked = account.studios.first(where: { $0.id == developerId }) {
            account.developerName = picked.name
            account.developerAvatar = picked.logo
        }
        file.accounts[index] = account
        save()
        return true
    }

    /// 删除账号。返回被删除的记录，以及当前账号是否因此改变。
    func remove(id: String) -> (removed: AccountRecord, currentChanged: Bool)? {
        guard let index = file.accounts.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = file.accounts.remove(at: index)
        var changed = false
        if file.current == id {
            file.current = file.accounts.first?.id
            changed = true
        }
        save()
        return (removed, changed)
    }

    /// 页面的 addAccount 接口：只新建一条账号记录，存储为新的空存储。
    func addAccount(name: String, developerId: String, storeId: String) -> AccountRecord? {
        guard !developerId.isEmpty, !file.accounts.contains(where: { $0.developerId == developerId }) else {
            return nil
        }
        let account = AccountRecord(
            id: AccountStore.makeAccountID(),
            name: name.isEmpty ? "TapTap " + developerId : name,
            developerId: developerId,
            developerName: name,
            developerAvatar: "",
            nickname: name,
            avatar: "",
            storeId: storeId,
            studios: [],
            activeDeveloperId: nil
        )
        file.accounts.append(account)
        if file.current == nil { file.current = account.id }
        save()
        return account
    }

    /// 把接口资料写入账号。昵称、头像、工作室列表有值时才覆盖；
    /// 选中了工作室时，显示名称与头像跟随该工作室（对齐桌面版 upsertAccountFromProbe）。
    private func merge(_ profile: IdentityProfile, into account: inout AccountRecord) {
        if !profile.nickname.isEmpty { account.nickname = profile.nickname }
        if !profile.avatar.isEmpty { account.avatar = profile.avatar }
        if let studios = profile.studios { account.studios = studios }

        if let activeId = account.activeDeveloperId,
           let picked = account.studios.first(where: { $0.id == activeId }) {
            account.developerName = picked.name
            account.developerAvatar = picked.logo
        } else {
            if !profile.developerName.isEmpty { account.developerName = profile.developerName }
            if !profile.developerAvatar.isEmpty { account.developerAvatar = profile.developerAvatar }
        }
    }
}
