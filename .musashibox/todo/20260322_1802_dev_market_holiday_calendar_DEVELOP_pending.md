# DEVELOP: 日本市場休日カレンダーの統合

## 概要

東京証券取引所（TSE）の休業日カレンダーを管理する仕組みを実装し、日次株価データの検証・インポート最適化・バリュエーション算出の精度向上に活用する。

## 背景

現在、システムには市場休日の概念がなく、以下の問題が生じている:

1. **ImportDailyQuotesJob**: 祝日にもAPIコールを実行し、空のレスポンスを受け取る無駄が発生
2. **DailyQuoteギャップ検出**: 祝日を欠落と誤判定する可能性
3. **CalculateFinancialMetricsJob#load_stock_price**: 祝日の前後で最適な取引日を特定できない

## 実装内容

### 1. `MarketCalendar` クラスの作成

`app/lib/market_calendar.rb`

TSEの休業日を管理するシンプルなクラス。以下を管理:
- 土日（自動判定）
- 国民の祝日（年ごとの祝日リストを定義）
- 年末年始（12/31〜1/3）
- TSE独自の休業日

```ruby
class MarketCalendar
  # @param year [Integer] 対象年
  def initialize(year:)
    @year = year
    @holidays = build_holidays
  end

  # 指定日が取引日かどうかを判定する
  # @param date [Date]
  # @return [Boolean]
  def trading_day?(date)
    !date.saturday? && !date.sunday? && !@holidays.include?(date)
  end

  # 指定日以降の最初の取引日を返す
  # @param date [Date]
  # @return [Date]
  def next_trading_day(date)
    # ...
  end

  # 指定日以前の直近の取引日を返す
  # @param date [Date]
  # @return [Date]
  def previous_trading_day(date)
    # ...
  end

  # 指定期間の取引日数を返す
  # @param from [Date]
  # @param to [Date]
  # @return [Integer]
  def get_trading_days_count(from:, to:)
    # ...
  end

  # 便利メソッド: 複数年にまたがる判定用
  class << self
    def trading_day?(date)
      new(year: date.year).trading_day?(date)
    end

    def next_trading_day(date)
      new(year: date.year).next_trading_day(date)
    end

    def previous_trading_day(date)
      new(year: date.year).previous_trading_day(date)
    end
  end

  private

  def build_holidays
    # 国民の祝日を算出（春分の日・秋分の日は天文計算で近似）
    # 振替休日も考慮
    # ...
  end
end
```

### 2. 祝日データの管理方針

- 祝日法に基づく計算ロジックでプログラム的に算出する
- 固定祝日: 元日(1/1), 建国記念の日(2/11), 天皇誕生日(2/23), 昭和の日(4/29), 憲法記念日(5/3), みどりの日(5/4), こどもの日(5/5), 山の日(8/11), 文化の日(11/3), 勤労感謝の日(11/23)
- ハッピーマンデー: 成人の日(1月第2月曜), 海の日(7月第3月曜), 敬老の日(9月第3月曜), スポーツの日(10月第2月曜)
- 天文計算: 春分の日, 秋分の日
- 振替休日: 祝日が日曜の場合翌月曜
- 年末年始: 12/31〜1/3
- 大発会・大納会の考慮

### 3. 他コンポーネントへの適用

初期リリースでは `MarketCalendar` クラスの実装とテストのみ。
以下は別TODOで対応:
- `ImportDailyQuotesJob` での休日スキップ
- `DailyQuote.detect_gaps` での祝日考慮
- `load_stock_price` での最適取引日検索

## テスト

### `spec/lib/market_calendar_spec.rb`

- `trading_day?`: 平日の取引日が true を返すこと
- `trading_day?`: 土曜日が false を返すこと
- `trading_day?`: 日曜日が false を返すこと
- `trading_day?`: 祝日（元日、建国記念の日等）が false を返すこと
- `trading_day?`: 年末年始（12/31〜1/3）が false を返すこと
- `trading_day?`: 振替休日が false を返すこと
- `next_trading_day`: 金曜日の次の取引日が月曜日であること
- `next_trading_day`: 祝日前日の次の取引日が祝日の翌営業日であること
- `previous_trading_day`: 月曜日の前の取引日が金曜日であること
- `get_trading_days_count`: 正しい取引日数を返すこと

## 影響範囲

- `app/lib/market_calendar.rb` - 新規作成
- `spec/lib/market_calendar_spec.rb` - 新規作成
