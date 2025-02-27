import EvmKit
import MarketKit
import HsToolKit

class EvmBlockchainManager {
    private let blockchainTypes: [BlockchainType] = [
        .ethereum,
        .binanceSmartChain,
        .polygon,
        .avalanche,
        .optimism,
        .arbitrumOne,
        .gnosis,
    ]

    private let syncSourceManager: EvmSyncSourceManager
    private let testNetManager: TestNetManager
    private let marketKit: MarketKit.Kit
    private let accountManagerFactory: EvmAccountManagerFactory

    private var evmKitManagerMap = [BlockchainType: EvmKitManager]()
    private var evmAccountManagerMap = [BlockchainType: EvmAccountManager]()

    var allBlockchains: [Blockchain] {
        do {
            var allBlockchains = try marketKit.blockchains(uids: blockchainTypes.map { $0.uid })

            if testNetManager.testNetEnabled {
                allBlockchains += testNetManager.blockchains
            }

            return allBlockchains
        } catch {
            return []
        }
    }

    init(syncSourceManager: EvmSyncSourceManager, testNetManager: TestNetManager, marketKit: MarketKit.Kit, accountManagerFactory: EvmAccountManagerFactory) {
        self.syncSourceManager = syncSourceManager
        self.testNetManager = testNetManager
        self.marketKit = marketKit
        self.accountManagerFactory = accountManagerFactory
    }

    private func evmManagers(blockchainType: BlockchainType) -> (EvmKitManager, EvmAccountManager) {
        if let evmKitManager = evmKitManagerMap[blockchainType], let evmAccountManager = evmAccountManagerMap[blockchainType] {
            return (evmKitManager, evmAccountManager)
        }

        let evmKitManager = EvmKitManager(chain: chain(blockchainType: blockchainType), syncSourceManager: syncSourceManager)
        let evmAccountManager = accountManagerFactory.evmAccountManager(blockchainType: blockchainType, evmKitManager: evmKitManager)

        evmKitManagerMap[blockchainType] = evmKitManager
        evmAccountManagerMap[blockchainType] = evmAccountManager

        return (evmKitManager, evmAccountManager)
    }

}

extension EvmBlockchainManager {

    func blockchain(chainId: Int) -> Blockchain? {
        allBlockchains.first(where: { chain(blockchainType: $0.type).id == chainId })
    }

    func blockchain(token: Token) -> Blockchain? {
        allBlockchains.first(where: { token.blockchain == $0 })
    }

    func blockchain(type: BlockchainType) -> Blockchain? {
        allBlockchains.first(where: { $0.type == type })
    }

    func chain(chainId: Int) -> Chain? {
        blockchain(chainId: chainId).map { chain(blockchainType: $0.type) }
    }

    func chain(blockchainType: BlockchainType) -> Chain {
        switch blockchainType {
        case .ethereum: return .ethereum
        case .ethereumGoerli: return .ethereumGoerli
        case .binanceSmartChain: return .binanceSmartChain
        case .polygon: return .polygon
        case .avalanche: return .avalanche
        case .optimism: return .optimism
        case .arbitrumOne: return .arbitrumOne
        case .gnosis: return .gnosis
        default: fatalError("Unsupported blockchain type")
        }
    }

    func baseToken(blockchainType: BlockchainType) -> Token? {
        let query = TokenQuery(blockchainType: blockchainType, tokenType: .native)
        if let token = try? marketKit.token(query: query) {
            return token
        }

        return testNetManager.baseToken(blockchainType: blockchainType)
    }

    func evmKitManager(blockchainType: BlockchainType) -> EvmKitManager {
        evmManagers(blockchainType: blockchainType).0
    }

    func evmAccountManager(blockchainType: BlockchainType) -> EvmAccountManager {
        evmManagers(blockchainType: blockchainType).1
    }

}
