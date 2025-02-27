import RxSwift
import MarketKit
import CurrencyKit

class TopPlatformMarketCapFetcher {
    private let marketKit: MarketKit.Kit
    private let currencyKit: CurrencyKit.Kit
    private let topPlatform: TopPlatform

    init(marketKit: MarketKit.Kit, currencyKit: CurrencyKit.Kit, topPlatform: TopPlatform) {
        self.marketKit = marketKit
        self.currencyKit = currencyKit
        self.topPlatform = topPlatform
    }

}

extension TopPlatformMarketCapFetcher: IMetricChartConfiguration {

    var title: String {
        topPlatform.blockchain.name
    }

    var description: String? {
        "some description"
    }

    var poweredBy: String? {
        "HorizontalSystems API"
    }

    var valueType: MetricChartModule.ValueType {
        .compactCurrencyValue(currencyKit.baseCurrency)
    }

}

extension TopPlatformMarketCapFetcher: IMetricChartFetcher {

    var intervals: [HsTimePeriod] {
        [.day1, .week1, .month1]
    }

    func fetchSingle(interval: HsTimePeriod) -> RxSwift.Single<[MetricChartModule.Item]> {
        marketKit
                .topPlatformMarketCapChartSingle(platform: topPlatform.blockchain.uid, currencyCode: currencyKit.baseCurrency.code, timePeriod: interval)
                .map { points in
                    points.map { point -> MetricChartModule.Item in
                        MetricChartModule.Item(value: point.marketCap, timestamp: point.timestamp)
                    }
                }
    }

}
