# DEVELOP: メトリクス計算のエッジケース改善

## 概要

CalculateFinancialMetricsJobにおける前期データ検索・株価取得・スコープ遷移のエッジケースを改善し、計算結果の信頼性を向上させる。

## 背景・動機

現在のCalculateFinancialMetricsJobには以下のエッジケースが存在する:

### 1. 非3月決算企業の前期データ検索

`find_previous_financial_value` は `fiscal_year_end - 1.year` を基準に ±1ヶ月の範囲で前期を検索する。しかし:

- 決算期変更があった企業（例: 3月決算→12月決算への変更）では、変更年の前期が検出されない可能性がある
- 変則決算（9ヶ月決算等）の場合、1年前 ±1ヶ月のウィンドウに前期データが入らない

### 2. 株価取得の範囲制限

`load_stock_price` は `fiscal_year_end ±7日` で `adjusted_close` を検索するが:

- fiscal_year_endが祝日・連休と重なる場合、±7日でカバーできないケースがある（例: ゴールデンウィーク期間中の決算日）
- 新規上場直後の企業は、決算期末時点でまだ上場していない場合がある
- 出来高の少ない銘柄では、adjusted_closeが0やnullの日がある

### 3. スコープ遷移への未対応

- 企業が子会社を設立し、個別→連結に変更した場合、前期（個別）と当期（連結）のYoY比較は会計上の意味をなさない
- 逆に連結→個別に変更した場合も同様
- 現在のコードはスコープが同じもの同士でのみ比較するが、初年度のYoYが計算不能になることの記録・通知がない

## 実装方針

### 1. find_previous_financial_value の改善

```ruby
# 改善案: 検索ウィンドウを拡大し、最も近い前期を採用
def find_previous_financial_value(fv)
  target_date = fv.fiscal_year_end - 1.year
  # ±2ヶ月に拡大（変則決算への対応）
  candidates = FinancialValue
    .where(company_id: fv.company_id, scope: fv.scope, period_type: fv.period_type)
    .where(fiscal_year_end: (target_date - 2.months)..(target_date + 2.months))
    .order(Arel.sql("ABS(julianday(fiscal_year_end) - julianday('#{target_date.iso8601}'))"))

  candidates.first
end
```

### 2. load_stock_price の改善

```ruby
# 改善案: 段階的にウィンドウを拡大し、最も近い取引日の株価を取得
def load_stock_price(fv)
  base_date = fv.fiscal_year_end

  # まず±7日で探す
  quote = find_nearest_quote(fv.company_id, base_date, days: 7)
  return quote.adjusted_close if quote

  # 見つからなければ±30日に拡大（GW等の長期休暇対応）
  quote = find_nearest_quote(fv.company_id, base_date, days: 30)
  return quote.adjusted_close if quote

  # それでも見つからなければnil（ログ記録）
  Rails.logger.warn("No stock price found for company_id=#{fv.company_id} near #{base_date}")
  nil
end

def find_nearest_quote(company_id, base_date, days:)
  DailyQuote
    .where(company_id: company_id)
    .where(traded_on: (base_date - days.days)..(base_date + days.days))
    .where.not(adjusted_close: [nil, 0])
    .order(Arel.sql("ABS(julianday(traded_on) - julianday('#{base_date.iso8601}'))"))
    .first
end
```

### 3. スコープ遷移の検出・記録

```ruby
# メトリクス計算時にスコープ遷移を検出してログに記録
def detect_scope_transition(fv)
  opposite_scope = fv.scope == "consolidated" ? "non_consolidated" : "consolidated"
  target_date = fv.fiscal_year_end - 1.year

  has_opposite_previous = FinancialValue
    .where(company_id: fv.company_id, scope: opposite_scope, period_type: fv.period_type)
    .where(fiscal_year_end: (target_date - 2.months)..(target_date + 2.months))
    .exists?

  if has_opposite_previous && !find_previous_financial_value(fv)
    Rails.logger.info(
      "Scope transition detected: company_id=#{fv.company_id}, " \
      "fiscal_year_end=#{fv.fiscal_year_end}, current_scope=#{fv.scope}"
    )
  end
end
```

## テスト

`spec/jobs/calculate_financial_metrics_job_spec.rb` に追加（メソッド単位のテスト、テスティング規約に準拠）:

- `find_previous_financial_value`: 非3月決算企業での前期検索が成功すること
- `find_previous_financial_value`: 変則決算（9ヶ月決算）での前期検索
- `find_nearest_quote`: ±7日で見つからないとき±30日で見つかること
- `find_nearest_quote`: adjusted_closeが0の日をスキップすること
- `detect_scope_transition`: 個別→連結遷移の検出

## 依存関係

- CalculateFinancialMetricsJobの既存実装に対する改善
- メトリクス計算精度に依存する全ての分析TODO（analysis_query_layer, screening等）の品質に影響
