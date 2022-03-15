import RxSwift
import RxCocoa
import EthereumKit
import MarketKit

class SendXViewModel {
    private let service: SendBitcoinService
    private let disposeBag = DisposeBag()

    private let proceedEnabledRelay = BehaviorRelay<Bool>(value: false)
    private let proceedRelay = PublishRelay<()>()

    private var firstLoaded: Bool = false

    init(service: SendBitcoinService) {
        self.service = service

        subscribe(disposeBag, service.stateObservable) { [weak self] in self?.sync(state: $0) }

        sync(state: service.state)
    }

    private func sync(state: SendBitcoinService.State) {
        switch state {
        case .loading:
            if !firstLoaded {
                proceedEnabledRelay.accept(false)
            }
        case .ready:
            firstLoaded = true
            proceedEnabledRelay.accept(true)
        case .notReady:
            proceedEnabledRelay.accept(false)
        }
    }

}

extension SendXViewModel {

    var proceedEnableDriver: Driver<Bool> {
        proceedEnabledRelay.asDriver()
    }

    var proceedSignal: Signal<()> {
        proceedRelay.asSignal()
    }

    var platformCoin: PlatformCoin {
        service.sendPlatformCoin
    }

    func didTapProceed() {
        guard case .ready = service.state else {
            return
        }

        proceedRelay.accept(())
    }

}
