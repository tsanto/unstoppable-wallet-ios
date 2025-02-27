import Foundation
import MarketKit
import LanguageKit
import CurrencyKit
import Chart

class MetricChartFactory {
    static private let noChangesLimitPercent: Decimal = 0.2

    private let timelineHelper: ITimelineHelper
    private let valueType: CoinProChartModule.ChartValueType
    private let dateFormatter = DateFormatter()

    init(timelineHelper: ITimelineHelper, valueType: CoinProChartModule.ChartValueType = .last, currentLocale: Locale) {
        self.timelineHelper = timelineHelper
        self.valueType = valueType

        dateFormatter.locale = currentLocale
    }

    private func chartData(points: [MetricChartModule.Item]) -> ChartData {
        // fill items by points
        let items = points.map { (point: MetricChartModule.Item) -> ChartItem in
            let item = ChartItem(timestamp: point.timestamp)

            item.added(name: .rate, value: point.value)
            point.indicators?.forEach { key, value in
                item.added(name: key, value: value)
            }

            return item
        }

        return ChartData(items: items, startTimestamp: points.first?.timestamp ?? 0, endTimestamp: points.last?.timestamp ?? 0)
    }

    private func format(value: Decimal?, valueType: MetricChartModule.ValueType, exactlyValue: Bool = false) -> String? {
        guard let value = value else {
            return nil
        }

        switch valueType {
        case .percent:         // values in percent
            return ValueFormatter.instance.format(percentValue: value, showSign: false)
        case .currencyValue(let currency):
            return ValueFormatter.instance.formatFull(currency: currency, value: value)
        case .counter:
            if exactlyValue {
                return value.description
            } else {
                return ValueFormatter.instance.formatShort(value: value)
            }
        case .compactCoinValue(let coin):
            let valueString: String?
            if exactlyValue {
                valueString = value.description
            } else {
                valueString = ValueFormatter.instance.formatShort(value: value)
            }
            return [valueString, coin.code].compactMap { $0 }.joined(separator: " ")
        case .compactCurrencyValue(let currency):                   // others in compact forms
            if exactlyValue {
                return ValueFormatter.instance.formatFull(currency: currency, value: value)
            } else {
                return ValueFormatter.instance.formatShort(currency: currency, value: value)
            }
        }
    }

}

extension MetricChartFactory {

    func convert(items: [MetricChartModule.Item], interval: HsTimePeriod, valueType: MetricChartModule.ValueType) -> MetricChartViewModel.ViewItem {
        // build data with rates
        let data = chartData(points: items)

        // calculate min and max limit texts
        let values = data.values(name: .rate)
        var min = values.min()
        var max = values.max()
        if let minValue = min, let maxValue = max, minValue == maxValue {
            min = minValue * (1 - Self.noChangesLimitPercent)
            max = maxValue * (1 + Self.noChangesLimitPercent)
        }
        let minString = format(value: min, valueType: valueType)
        let maxString = format(value: max, valueType: valueType)

        // determine chart growing state. when chart not full - it's nil
        var chartTrend: MovementTrend = .neutral

        var valueDiff: Decimal?
        var value: String?
        if let first = data.items.first(where: { ($0.indicators[.rate] ?? 0) != 0 }), let last = data.items.last, let firstValue = first.indicators[.rate], let lastValue = last.indicators[.rate] {
            //check valueType
            switch self.valueType {
            case .last:
                value = format(value: lastValue, valueType: valueType)
                chartTrend = (lastValue - firstValue).isSignMinus ? .down : .up
                valueDiff = (lastValue - firstValue) / firstValue * 100
            case .cumulative:
                let valueDecimal = data.items.compactMap { $0.indicators[.rate] }.reduce(0, +)
                value = format(value: valueDecimal, valueType: valueType)
                chartTrend = .ignore
            }

        }

        // make timeline for chart

        let gridInterval = ChartIntervalConverter.convert(interval: interval) // hours count
        let timeline = timelineHelper
                .timestamps(startTimestamp: data.startWindow, endTimestamp: data.endWindow, separateHourlyInterval: gridInterval)
                .map {
                    ChartTimelineItem(text: timelineHelper.text(timestamp: $0, separateHourlyInterval: gridInterval, dateFormatter: dateFormatter), timestamp: $0)
                }

        return MetricChartViewModel.ViewItem(currentValue: value, chartData: data, chartTrend: chartTrend, chartDiff: valueDiff, minValue: minString, maxValue: maxString, timeline: timeline, selectedIndicator: ChartIndicatorSet.none)
    }

    func selectedPointViewItem(chartItem: ChartItem, valueType: MetricChartModule.ValueType) -> SelectedPointViewItem? {
        guard let value = chartItem.indicators[.rate] else {
            return nil
        }

        let date = Date(timeIntervalSince1970: chartItem.timestamp)
        let formattedDate = DateHelper.instance.formatFullTime(from: date)

        let formattedValue = format(value: value, valueType: valueType, exactlyValue: true)

        var rightSideMode: SelectedPointViewItem.RightSideMode = .none
        if let dominance = chartItem.indicators[.dominance] {
            rightSideMode = .dominance(value: dominance)
        }
        return SelectedPointViewItem(date: formattedDate, value: formattedValue, rightSideMode: rightSideMode)
    }

}
