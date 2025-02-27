import UIKit
import SnapKit
import ThemeKit
import SectionsTableView
import Chart
import ComponentKit
import RxSwift

class MarketGlobalTvlMetricViewController: MarketListViewController {
    private let chartViewModel: MetricChartViewModel
    private let disposeBag = DisposeBag()

    private let headerViewModel: MarketTvlSortHeaderViewModel
    private let sortHeaderView: MarketTvlSortHeaderView

    override var headerView: UITableViewHeaderFooterView? { sortHeaderView }

    override var viewController: UIViewController? { self }
    override var refreshEnabled: Bool { false }

    /* Chart section */
    private let chartCell: ChartCell
    private let chartRow: StaticRow

    init(listViewModel: IMarketListViewModel, headerViewModel: MarketTvlSortHeaderViewModel, chartViewModel: MetricChartViewModel, configuration: ChartConfiguration) {
        self.chartViewModel = chartViewModel
        self.headerViewModel = headerViewModel

        sortHeaderView = MarketTvlSortHeaderView(viewModel: headerViewModel, hasTopSeparator: false)

        chartCell = ChartCell(viewModel: chartViewModel, touchDelegate: chartViewModel, viewOptions: ChartCell.metricChart, configuration: configuration)
        chartRow = StaticRow(
                cell: chartCell,
                id: "chartView",
                height: chartCell.cellHeight
        )

        super.init(listViewModel: listViewModel)

        sortHeaderView.viewController = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = chartViewModel.title.localized
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "button.close".localized, style: .plain, target: self, action: #selector(onTapClose))

        chartRow.onReady = { [weak chartCell] in chartCell?.onLoad() }

        tableView.buildSections()
        chartViewModel.start()
    }

    @objc private func onTapClose() {
        dismiss(animated: true)
    }

    override func topSections(loaded: Bool) -> [SectionProtocol] {
        guard loaded else {
            return []
        }

        return [
            Section(
                    id: "chart",
                    rows: [chartRow]
            )
        ]
    }

}
