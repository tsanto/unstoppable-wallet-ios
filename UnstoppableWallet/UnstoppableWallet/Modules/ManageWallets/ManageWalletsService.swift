import RxSwift
import RxRelay
import MarketKit
import EvmKit

class ManageWalletsService {
    private let account: Account
    private let marketKit: MarketKit.Kit
    private let walletManager: WalletManager
    private let restoreSettingsManager: RestoreSettingsManager
    private let testNetManager: TestNetManager
    private let enableCoinService: EnableCoinService
    private let disposeBag = DisposeBag()

    private var fullCoins = [FullCoin]()
    private var wallets = Set<Wallet>()
    private var filter: String = ""

    private let itemsRelay = PublishRelay<[Item]>()
    private let cancelEnableCoinRelay = PublishRelay<Coin>()

    var items: [Item] = [] {
        didSet {
            itemsRelay.accept(items)
        }
    }

    init?(marketKit: MarketKit.Kit, walletManager: WalletManager, restoreSettingsManager: RestoreSettingsManager, testNetManager: TestNetManager, accountManager: AccountManager, enableCoinService: EnableCoinService) {
        guard let account = accountManager.activeAccount else {
            return nil
        }

        self.account = account
        self.marketKit = marketKit
        self.walletManager = walletManager
        self.restoreSettingsManager = restoreSettingsManager
        self.testNetManager = testNetManager
        self.enableCoinService = enableCoinService

        subscribe(disposeBag, walletManager.activeWalletsUpdatedObservable) { [weak self] wallets in
            self?.handleUpdated(wallets: wallets)
        }
        subscribe(disposeBag, enableCoinService.enableCoinObservable) { [weak self] configuredTokens, restoreSettings in
            self?.handleEnableCoin(configuredTokens: configuredTokens, restoreSettings: restoreSettings)
        }
        subscribe(disposeBag, enableCoinService.disableCoinObservable) { [weak self] coin in
            self?.handleDisable(coin: coin)
        }
        subscribe(disposeBag, enableCoinService.cancelEnableCoinObservable) { [weak self] coin in
            self?.handleCancelEnable(coin: coin)
        }

        sync(wallets: walletManager.activeWallets)
        syncFullCoins()
        sortFullCoins()
        syncState()
    }

    private func fetchFullCoins() -> [FullCoin] {
        do {
            if filter.trimmingCharacters(in: .whitespaces).isEmpty {
                var fullCoins = try marketKit.fullCoins(filter: "", limit: 1000)
                        .filter { !$0.eligibleTokens(accountType: account.type).isEmpty }
                        .prefix(100)

                if testNetManager.testNetEnabled {
                    fullCoins += testNetManager.baseTokens
                            .map { $0.fullCoin }
                            .filter { !$0.eligibleTokens(accountType: account.type).isEmpty }
                }

                let allCoins = fullCoins.map { $0.coin }
                let enabledFullCoins = try marketKit.fullCoins(coinUids: wallets.filter { !allCoins.contains($0.coin) }.map { $0.coin.uid })

                let customFullCoins = wallets.map { $0.token }.filter { $0.isCustom }.map { $0.fullCoin }

                return fullCoins + enabledFullCoins + customFullCoins
            } else if let ethAddress = try? EvmKit.Address(hex: filter) {
                let address = ethAddress.hex
                let tokens = try marketKit.tokens(reference: address)
                let coinUids = Array(Set(tokens.map { $0.coin.uid }))

                return try marketKit.fullCoins(coinUids: coinUids)
                        .filter { !$0.eligibleTokens(accountType: account.type).isEmpty }
            } else {
                var fullCoins = try marketKit.fullCoins(filter: filter, limit: 1000)
                        .filter { !$0.eligibleTokens(accountType: account.type).isEmpty }
                        .prefix(20)

                if testNetManager.testNetEnabled {
                    fullCoins += testNetManager.baseTokens(filter: filter)
                            .map { $0.fullCoin }
                            .filter { !$0.eligibleTokens(accountType: account.type).isEmpty }
                }

                return Array(fullCoins)
            }
        } catch {
            return []
        }
    }

    private func syncFullCoins() {
        fullCoins = fetchFullCoins()
    }

    private func isEnabled(coin: Coin) -> Bool {
        wallets.contains { $0.coin == coin }
    }

    private func sortFullCoins() {
        fullCoins.sort(filter: filter) { isEnabled(coin: $0) }
    }

    private func sync(wallets: [Wallet]) {
        self.wallets = Set(wallets)
    }

    private func hasSettingsOrTokens(tokens: [Token]) -> Bool {
        if tokens.count == 1 {
            let token = tokens[0]
            return token.blockchainType.coinSettingType != nil || token.type != .native
        } else {
            return true
        }
    }

    private func item(fullCoin: FullCoin) -> Item {
        if !fullCoin.tokens.isEmpty, fullCoin.tokens.allSatisfy({ $0.blockchainType.isUnsupported }) {
            return Item(fullCoin: fullCoin, state: .unsupportedByApp)
        }

        let eligibleTokens = fullCoin.eligibleTokens(accountType: accountType)

        let itemState: ItemState

        if eligibleTokens.isEmpty {
            itemState = .unsupportedByWalletType
        } else {
            let enabled = isEnabled(coin: fullCoin.coin)
            itemState = .supported(
                    enabled: enabled,
                    hasSettings: enabled && hasSettingsOrTokens(tokens: fullCoin.tokens),
                    hasInfo: enabled && fullCoin.tokens.first?.blockchainType == .zcash
            )
        }

        return Item(fullCoin: fullCoin, state: itemState)
    }

    private func syncState() {
        items = fullCoins.map { item(fullCoin: $0) }
    }

    private func handleUpdated(wallets: [Wallet]) {
        sync(wallets: wallets)

        let newFullCoins = fetchFullCoins()

        if newFullCoins.count > fullCoins.count {
            fullCoins = newFullCoins
            sortFullCoins()
        }

        syncState()
    }

    private func handleEnableCoin(configuredTokens: [ConfiguredToken], restoreSettings: RestoreSettings) {
        guard let coin = configuredTokens.first?.token.coin else {
            return
        }

        if !restoreSettings.isEmpty && configuredTokens.count == 1 {
            enableCoinService.save(restoreSettings: restoreSettings, account: account, blockchainType: configuredTokens[0].token.blockchainType)
        }

        let existingWallets = wallets.filter { $0.coin == coin }
        let existingConfiguredTokens = existingWallets.map { $0.configuredToken }

        let newConfiguredTokens = configuredTokens.filter { !existingConfiguredTokens.contains($0) }
        let removedWallets = existingWallets.filter { !configuredTokens.contains($0.configuredToken) }

        let newWallets = newConfiguredTokens.map { Wallet(configuredToken: $0, account: account) }

        if !newWallets.isEmpty || !removedWallets.isEmpty {
            walletManager.handle(newWallets: newWallets, deletedWallets: Array(removedWallets))
        }
    }

    private func handleDisable(coin: Coin) {
        let walletsToDelete = wallets.filter { $0.coin == coin }
        walletManager.delete(wallets: Array(walletsToDelete))

        cancelEnableCoinRelay.accept(coin)
    }

    private func handleCancelEnable(coin: Coin) {
        if !isEnabled(coin: coin) {
            cancelEnableCoinRelay.accept(coin)
        }
    }

}

extension ManageWalletsService {

    var itemsObservable: Observable<[Item]> {
        itemsRelay.asObservable()
    }

    var cancelEnableCoinObservable: Observable<Coin> {
        cancelEnableCoinRelay.asObservable()
    }

    var accountType: AccountType {
        account.type
    }

    func set(filter: String) {
        self.filter = filter

        syncFullCoins()
        sortFullCoins()
        syncState()
    }

    func enable(uid: String) {
        guard let fullCoin = fullCoins.first(where: { $0.coin.uid == uid }) else {
            return
        }

        enableCoinService.enable(fullCoin: fullCoin, accountType: account.type, account: account)
    }

    func disable(uid: String) {
        let walletsToDelete = wallets.filter { $0.coin.uid == uid }
        walletManager.delete(wallets: Array(walletsToDelete))
    }

    func configure(uid: String) {
        guard let fullCoin = fullCoins.first(where: { $0.coin.uid == uid }) else {
            return
        }

        let coinWallets = wallets.filter { $0.coin.uid == uid }
        enableCoinService.configure(fullCoin: fullCoin, accountType: account.type, configuredTokens: coinWallets.map { $0.configuredToken })
    }

    func birthdayHeight(uid: String) -> (Blockchain, Int)? {
        guard let fullCoin = fullCoins.first(where: { $0.coin.uid == uid }) else {
            return nil
        }

        guard let token = fullCoin.tokens.first else {
            return nil
        }

        let settings = restoreSettingsManager.settings(account: account, blockchainType: token.blockchainType)

        guard let birthdayHeight = settings.birthdayHeight else {
            return nil
        }

        return (token.blockchain, birthdayHeight)
    }

}

extension ManageWalletsService {

    struct Item {
        let fullCoin: FullCoin
        let state: ItemState
    }

    enum ItemState {
        case unsupportedByWalletType
        case unsupportedByApp
        case supported(enabled: Bool, hasSettings: Bool, hasInfo: Bool)
    }

}
