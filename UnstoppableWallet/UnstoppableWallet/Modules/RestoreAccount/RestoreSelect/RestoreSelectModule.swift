import UIKit
import RxSwift
import MarketKit

struct RestoreSelectModule {

    static func viewController(accountName: String, accountType: AccountType, returnViewController: UIViewController?) -> UIViewController {
        let (enableCoinService, enableCoinView) = EnableCoinModule.module()

        let service = RestoreSelectService(
                accountName: accountName,
                accountType: accountType,
                accountFactory: App.shared.accountFactory,
                accountManager: App.shared.accountManager,
                walletManager: App.shared.walletManager,
                testNetManager: App.shared.testNetManager,
                evmAccountRestoreStateManager: App.shared.evmAccountRestoreStateManager,
                marketKit: App.shared.marketKit,
                enableCoinService: enableCoinService
        )

        let viewModel = RestoreSelectViewModel(service: service)

        return RestoreSelectViewController(
                viewModel: viewModel,
                enableCoinView: enableCoinView,
                returnViewController: returnViewController
        )
    }

}
