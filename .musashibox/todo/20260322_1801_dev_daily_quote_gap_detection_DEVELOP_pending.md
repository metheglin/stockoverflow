# DEVELOP: 日次株価データのギャップ検出・アラート機能

## 概要

`daily_quotes` テーブルにおいて、取引日の欠落（ギャップ）を検出し、ログに記録する仕組みを実装する。ギャップの存在はバリュエーション指標の算出精度に直結するため、データ品質の監視として重要。

## 背景

- `CalculateFinancialMetricsJob#load_stock_price` は `fiscal_year_end` の前後7日で株価を検索する
- 該当期間に株価データが欠落していると、遠い日付の株価が使われ、バリュエーション指標（PER, PBR, PSR, EV/EBITDA）が不正確になる
- 現在の `DataIntegrityCheckJob#check_missing_daily_quotes` は「直近7日間にデータがあるか」のみで、中間期間のギャップは検出しない

## 実装内容

### 1. `DailyQuote` にギャップ検出メソッドを追加

`app/models/daily_quote.rb`

```ruby
# 指定企業の日次株価データにおけるギャップ（5営業日以上の連続欠落）を検出する
#
# 土日は除外するが、祝日は考慮しない（祝日カレンダー未実装のため）。
# 5営業日以上の連続欠落は異常とみなす。
#
# @param company_id [Integer]
# @param from [Date] 検索開始日（デフォルト: 1年前）
# @param to [Date] 検索終了日（デフォルト: 昨日）
# @param gap_threshold_days [Integer] ギャップとみなす連続欠落営業日数（デフォルト: 5）
# @return [Array<Hash>] ギャップ情報の配列
#   各要素: { from: Date, to: Date, business_days: Integer }
#
def self.detect_gaps(company_id:, from: 1.year.ago.to_date, to: Date.yesterday, gap_threshold_days: 5)
  # ...
end
```

### 2. `DataIntegrityCheckJob` にギャップチェックを追加

既存の `check_missing_daily_quotes` を拡張するか、新たに `check_daily_quote_gaps` メソッドを追加。

- 上場企業からサンプリング（全件チェックはコスト高）して代表的な企業のギャップをチェック
- 検出されたギャップを `ApplicationProperty(kind: :data_integrity)` の issues に記録
- ログ出力（warning レベル）

### 3. ギャップ再取得のためのヘルパー

ギャップが検出された場合、`ImportDailyQuotesJob` を特定日付範囲で再実行できるよう、対象日付を返すメソッドを用意する。

## テスト

### `spec/models/daily_quote_spec.rb` に追加

- `detect_gaps`: ギャップがない場合に空配列を返すこと
- `detect_gaps`: 5営業日以上のギャップが検出されること
- `detect_gaps`: 週末のみの2日間ギャップは検出されないこと
- `detect_gaps`: gap_threshold_days パラメータが機能すること

## 影響範囲

- `app/models/daily_quote.rb` - `detect_gaps` クラスメソッド追加
- `app/jobs/data_integrity_check_job.rb` - ギャップチェック追加
- `spec/models/daily_quote_spec.rb` - テスト追加
