import UIKit
import ThemeKit
import UniswapKit
import HUD
import RxSwift
import RxCocoa
import SectionsTableView
import ComponentKit

class UniswapDataSource {
    private static let levelColors: [UIColor] = [.themeRemus, .themeJacob, .themeLucian]

    private let disposeBag = DisposeBag()

    private let viewModel: UniswapViewModel
    private let allowanceViewModel: SwapAllowanceViewModel

    private let settingsHeaderView = TextDropDownAndSettingsHeaderView()

    private let inputCell: SwapInputCell

    private let buyPriceCell = SwapPriceCell()
    private let allowanceCell = BaseThemeCell()
    private let availableBalanceCell = BaseThemeCell()
    private let priceImpactCell = BaseThemeCell()

    private let warningCell = HighlightedDescriptionCell(showVerticalMargin: false)
    private let errorCell = TitledHighlightedDescriptionCell()
    private let buttonStackCell = StackViewCell()
    private let revokeButton = PrimaryButton()
    private let approveButton = PrimaryButton()
    private let proceedButton = PrimaryButton()
    private let approvingView = ApprovingView(title: "swap.approving_button".localized)

    var onOpen: ((_ viewController: UIViewController, _ viaPush: Bool) -> ())? = nil
    var onOpenSelectProvider: (() -> ())? = nil
    var onOpenSettings: (() -> ())? = nil
    var onClose: (() -> ())? = nil
    var onReload: (() -> ())? = nil

    weak var tableView: UITableView?

    private var emptyAmountIn: Bool = true

    private var lastBuyPrice: SwapPriceCell.PriceViewItem?
    private var lastAllowance: String?
    private var lastAvailableBalance: String?
    private var lastPriceImpact: UniswapModule.PriceImpactViewItem?
    private var error: String?

    init(viewModel: UniswapViewModel, allowanceViewModel: SwapAllowanceViewModel) {
        self.viewModel = viewModel
        self.allowanceViewModel = allowanceViewModel

        inputCell = SwapInputModule.cell(service: viewModel.service, tradeService: viewModel.tradeService, switchService: viewModel.switchService)
        inputCell.presentDelegate = self
        inputCell.onSwitch = { [weak self] in
            self?.viewModel.onTapSwitch()
        }

        settingsHeaderView.bind(dropdownTitle: viewModel.dexName)
        settingsHeaderView.onTapDropDown = { [weak self] in self?.onOpenSelectProvider?() }
        settingsHeaderView.onTapSettings = { [weak self] in self?.onOpenSettings?() }

        settingsHeaderView.onTapSelector = { [weak self] in self?.onChangeAmountType(index: $0) }
        settingsHeaderView.setSelector(items: viewModel.amountTypeSelectorItems)


        initCells()
    }

    func viewDidLoad() {

    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func initCells() {
        revokeButton.set(style: .yellow)
        revokeButton.addTarget(self, action: #selector((onTapRevokeButton)), for: .touchUpInside)
        buttonStackCell.add(view: revokeButton)

        approveButton.set(style: .gray)
        approveButton.setImage(UIImage(named: "numbers_1_20"), for: .normal)
        approveButton.setImage(UIImage(named: "numbers_1_disabled_20"), for: .disabled)
        approveButton.syncInsets()

        approveButton.addTarget(self, action: #selector((onTapApproveButton)), for: .touchUpInside)

        approveButton.addSubview(approvingView)
        approvingView.snp.makeConstraints { maker in
            maker.centerX.equalToSuperview()
            maker.centerY.equalToSuperview()
        }
        approvingView.isHidden = true

        errorCell.set(backgroundStyle: .transparent, isFirst: true)
        buttonStackCell.add(view: approveButton)

        proceedButton.set(style: .yellow)
        proceedButton.addTarget(self, action: #selector((onTapProceedButton)), for: .touchUpInside)
        buttonStackCell.add(view: proceedButton)

        subscribeToViewModel()
    }

    private func subscribeToViewModel() {
        subscribe(disposeBag, viewModel.availableBalanceDriver) { [weak self] in self?.handle(balance: $0) }
        subscribe(disposeBag, viewModel.priceImpactDriver) { [weak self] in self?.handle(priceImpact: $0) }
        subscribe(disposeBag, viewModel.buyPriceDriver) { [weak self] in self?.handle(buyPrice: $0) }
        subscribe(disposeBag, viewModel.countdownTimerDriver) { [weak self] in self?.handle(countDownTimer: $0) }
        subscribe(disposeBag, viewModel.amountInDriver) { [weak self] in self?.handle(amountIn: $0) }

        subscribe(disposeBag, viewModel.isLoadingDriver) { [weak self] in self?.handle(loading: $0) }
        subscribe(disposeBag, viewModel.swapErrorDriver) { [weak self] in self?.handle(error: $0) }
        subscribe(disposeBag, viewModel.proceedActionDriver) { [weak self] in self?.handle(proceedActionState: $0) }
        subscribe(disposeBag, viewModel.revokeWarningDriver) { [weak self] in self?.handle(revokeWarning: $0) }
        subscribe(disposeBag, viewModel.revokeActionDriver) { [weak self] in self?.handle(revokeActionState: $0) }
        subscribe(disposeBag, viewModel.approveActionDriver) { [weak self] in self?.handle(approveActionState: $0) }
        subscribe(disposeBag, viewModel.approveStepDriver) { [weak self] in self?.handle(approveStepState: $0) }

        subscribe(disposeBag, viewModel.openRevokeSignal) { [weak self] in self?.openRevoke(approveData: $0) }
        subscribe(disposeBag, viewModel.openApproveSignal) { [weak self] in self?.openApprove(approveData: $0) }
        subscribe(disposeBag, viewModel.openConfirmSignal) { [weak self] in self?.openConfirm(sendData: $0) }
        subscribe(disposeBag, viewModel.amountTypeIndexDriver) { [weak self] in self?.settingsHeaderView.setSelector(index: $0) }
        subscribe(disposeBag, viewModel.isAmountTypeAvailableDriver) { [weak self] in self?.settingsHeaderView.setSelector(isEnabled: $0) }

        subscribe(disposeBag, allowanceViewModel.allowanceDriver) { [weak self] in self?.handle(allowance: $0)  }
    }

    func viewDidAppear() {
        _ = inputCell.becomeFirstResponder()
    }

    private func handle(balance: String?) {
        lastAvailableBalance = balance
        build(staticCell: availableBalanceCell, id: "available-balance", title: "send.available_balance".localized, value: balance, valueColor: .themeLeah)

        onReload?()
    }

    private func handle(priceImpact: UniswapModule.PriceImpactViewItem?) {
        lastPriceImpact = priceImpact
        let color = Self.levelColors[priceImpact?.level.rawValue ?? 2]
        build(staticCell: priceImpactCell, id: "price-impact", title: "swap.price_impact".localized, showInfo: true, value: priceImpact?.value, valueColor: color)

        onReload?()
    }

    private func handle(buyPrice: SwapPriceCell.PriceViewItem?) {
        lastBuyPrice = buyPrice
        buyPriceCell.set(item: buyPrice)

        onReload?()
    }

    private func handle(countDownTimer: Float) {
        buyPriceCell.set(progress: countDownTimer)
    }

    private func handle(allowance: String?) {
        lastAllowance = allowance
        build(staticCell: allowanceCell, id: "allowance", title: "swap.allowance".localized, showInfo: true, value: allowance, valueColor: .themeLucian)

        onReload?()
    }

    private func handle(amountIn: Decimal) {
        emptyAmountIn = amountIn.isZero

        onReload?()
    }

    private func handle(loading: Bool) {
        buyPriceCell.priceButton.isEnabled = !loading
    }

    private func handle(revokeWarning: String?) {
        warningCell.descriptionText = revokeWarning

        onReload?()
    }

    private func handle(revokeActionState: UniswapViewModel.ActionState) {
        handle(actionState: revokeActionState, button: revokeButton)
    }

    private func handle(error: String?) {
        self.error = error
        if let error = error {
            errorCell.isVisible = true
            errorCell.bind(caution: TitledCaution(title: "alert.error".localized, text: error, type: .error))
        } else {
            errorCell.isVisible = false
        }

        onReload?()
    }

    private func handle(proceedActionState: UniswapViewModel.ActionState) {
        handle(actionState: proceedActionState, button: proceedButton)
    }

    private func handle(approveActionState: UniswapViewModel.ActionState) {
        handle(actionState: approveActionState, button: approveButton)
    }

    private func handle(actionState: UniswapViewModel.ActionState, button: PrimaryButton) {
        switch actionState {
        case .hidden:
            button.isHidden = true
        case .enabled(let title):
            button.isHidden = false
            button.isEnabled = true
            button.setTitle(title, for: .normal)
        case .disabled(let title):
            button.isHidden = false
            button.isEnabled = false
            button.setTitle(title, for: .normal)
        }
    }

    private func handle(approveStepState: SwapModule.ApproveStepState) {
        let isApproving = approveStepState == .approving
        approvingView.isHidden = !isApproving
        approvingView.startAnimating(isApproving)

        approveButton.setImage(isApproving ? nil : UIImage(named: "numbers_1_20"), for: .normal)
        approveButton.setImage(isApproving ? nil : UIImage(named: "numbers_1_disabled_20"), for: .disabled)
        approveButton.syncInsets()

        switch approveStepState {
        case .notApproved, .revokeRequired, .revoking:
            proceedButton.setImage(nil, for: .normal)
            proceedButton.setImage(nil, for: .disabled)
            proceedButton.syncInsets()
        default:
            proceedButton.setImage(UIImage(named: "numbers_2_20"), for: .normal)
            proceedButton.setImage(UIImage(named: "numbers_2_disabled_20"), for: .disabled)
            proceedButton.syncInsets()
        }

        onReload?()
    }

    @objc private func onTapRevokeButton() {
        viewModel.onTapRevoke()
    }

    @objc private func onTapApproveButton() {
        viewModel.onTapApprove()
    }

    @objc private func onTapProceedButton() {
        viewModel.onTapProceed()
    }

    private func openRevoke(approveData: SwapAllowanceService.ApproveData) {
        guard let viewController = SwapApproveConfirmationModule.revokeViewController(data: approveData, delegate: self) else {
            return
        }

        onOpen?(viewController, false)
    }

    private func openApprove(approveData: SwapAllowanceService.ApproveData) {
        guard let viewController = SwapApproveModule.instance(data: approveData, delegate: self) else {
            return
        }

        onOpen?(viewController, false)
    }

    private func openConfirm(sendData: SendEvmData) {
        guard let viewController = SwapConfirmationModule.viewController(sendData: sendData, dex: viewModel.service.dex) else {
            return
        }

        onOpen?(viewController, true)
    }

    private func onChangeAmountType(index: Int) {
        viewModel.onChangeAmountType(index: index)
    }

    private func build(staticCell: BaseThemeCell, id: String, title: String, showInfo: Bool = false, value: String?, valueColor: UIColor, progress: CGFloat? = nil) {
        var cellElements = [CellBuilderNew.CellElement]()
        if showInfo {
            cellElements.append(.image20 { component in
                component.imageView.image = UIImage(named: "circle_information_20")?.withTintColor(.themeGray)
            })
        }
        cellElements.append(contentsOf: [
            .text { component in
                component.font = .subhead2
                component.textColor = .themeGray
                component.text = title
                component.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            },
            .text { component in
                component.font = .subhead2
                component.textColor = valueColor
                component.text = value
                component.textAlignment = .right
            },
        ])

        CellBuilderNew.buildStatic(cell: staticCell, rootElement: .hStack(cellElements))
    }

    private var infoSection: SectionProtocol {
        let noAlerts = warningCell.descriptionText == nil && error == nil

        let cellViewItems = [
            InfoCellViewItem(
                    id: "buy-price",
                    cell: buyPriceCell,
                    isVisible: noAlerts && lastBuyPrice != nil),
            InfoCellViewItem(
                    id: "allowance",
                    cell: allowanceCell,
                    descriptionTitle: "swap.dex_info.header_allowance".localized,
                    description: "swap.dex_info.content_allowance".localized,
                    isVisible: noAlerts && lastAllowance != nil),
            InfoCellViewItem(
                    id: "available-balance",
                    cell: availableBalanceCell,
                    isVisible: noAlerts && lastAvailableBalance != nil && lastBuyPrice == nil && lastAllowance == nil),
            InfoCellViewItem(
                    id: "price-impact",
                    cell: priceImpactCell,
                    descriptionTitle: "swap.dex_info.header_price_impact".localized,
                    description: "swap.dex_info.content_price_impact".localized,
                    isVisible: noAlerts && lastPriceImpact != nil),
        ]

        let firstIndex = cellViewItems.firstIndex(where: { $0.isVisible }) ?? -1
        let lastIndex = cellViewItems.lastIndex(where: { $0.isVisible }) ?? -1


        let rows = cellViewItems.enumerated().map { index, viewItem in
            viewItem.cell.set(backgroundStyle: .externalBorderOnly, isFirst: firstIndex == index, isLast: lastIndex == index)
            return StaticRow(
                    cell: viewItem.cell,
                    id: viewItem.id,
                    height: viewItem.isVisible ? .heightSingleLineCell : 0,
                    action: viewItem.description != nil ? { [weak self] in
                        self?.showInfo(title: viewItem.descriptionTitle, text: viewItem.description)
                    } : nil)
        }


        return Section(
                id: "info",
                headerState: .margin(height: noAlerts ? .margin12 : 0),
                rows: rows
        )
    }

    private func showInfo(title: String?, text: String?) {
        guard let title = title, let text = text else {
            return
        }

        let viewController = InformationModule.description(title: title, text: text)
        onOpen?(viewController, false)
    }

}

extension UniswapDataSource: ISwapDataSource {

    var state: SwapModule.DataSourceState {
        let exactIn = viewModel.tradeService.tradeType == .exactIn
        return SwapModule.DataSourceState(
                tokenFrom: viewModel.tradeService.tokenIn,
                tokenTo: viewModel.tradeService.tokenOut,
                amountFrom: viewModel.tradeService.amountIn,
                amountTo: viewModel.tradeService.amountOut,
                exactFrom: exactIn)
    }

    var buildSections: [SectionProtocol] {
        var sections = [SectionProtocol]()

        sections.append(Section(
                id: "header",
                headerState: .static(view: settingsHeaderView, height: TextDropDownAndSettingsHeaderView.height),
                rows: [
                ]
        ))

        sections.append(Section(
                id: "main",
                headerState: .margin(height: .margin8),
                rows: [
                    StaticRow(
                            cell: inputCell,
                            id: "input-card",
                            height: SwapInputCell.cellHeight
                    )
                ]
        ))

        sections.append(infoSection)

        let hasAlert = warningCell.descriptionText != nil || error != nil
        sections.append(Section(id: "error",
                headerState: .margin(height: hasAlert ? .margin12 : 0),
                rows: [
                    StaticRow(
                            cell: warningCell,
                            id: "warning",
                            dynamicHeight: { [weak self] width in
                                if self?.error != nil {
                                    return 0
                                }
                                return self?.warningCell.height(containerWidth: width) ?? 0
                            }
                    ),
                    StaticRow(
                            cell: errorCell,
                            id: "error",
                            dynamicHeight: { [weak self] width in
                                self?.errorCell.cellHeight(containerWidth: width) ?? 0
                            }
                    )
                ]
        ))
        sections.append(Section(
                id: "buttons",
                headerState: .margin(height: .margin16),
                footerState: .margin(height: .margin32),
                rows: [
                    StaticRow(
                            cell: buttonStackCell,
                            id: "button",
                            height: .heightButton
                    )
                ]
        ))

        return sections
    }

}

extension UniswapDataSource: IPresentDelegate {

    func present(viewController: UIViewController) {
        onOpen?(viewController, false)
    }

}

extension UniswapDataSource: ISwapApproveDelegate {

    func didApprove() {
        viewModel.didApprove()
    }

}

extension UniswapDataSource: IDynamicHeightCellDelegate {

    func onChangeHeight() {
        onReload?()
    }

}

extension UniswapDataSource {

    class InfoCellViewItem {
        let id: String
        let cell: BaseThemeCell
        let descriptionTitle: String?
        let description: String?
        let isVisible: Bool

        init(id: String, cell: BaseThemeCell, descriptionTitle: String? = nil, description: String? = nil, isVisible: Bool) {
            self.id = id
            self.cell = cell
            self.descriptionTitle = descriptionTitle
            self.description = description
            self.isVisible = isVisible
        }
    }

}
