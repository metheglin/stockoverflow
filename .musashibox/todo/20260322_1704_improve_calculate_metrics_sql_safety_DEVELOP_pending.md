# DEVELOP: CalculateFinancialMetricsJob の SQL 文字列補間をパラメータバインドに修正

## 概要

`CalculateFinancialMetricsJob#load_stock_price` で使用されている `Arel.sql` 内の文字列補間を、安全なパラメータバインドに置き換える。同時にプロジェクト全体で同様のパターンが存在しないか監査する。

## 背景・動機

### 現状のコード

```ruby
def load_stock_price(fv)
  DailyQuote
    .where(company_id: fv.company_id)
    .where(traded_on: (fv.fiscal_year_end - 7.days)..(fv.fiscal_year_end + 7.days))
    .order(Arel.sql("ABS(JULIANDAY(traded_on) - JULIANDAY('#{fv.fiscal_year_end}'))"))
    .pick(:adjusted_close)
end
```

`'#{fv.fiscal_year_end}'` は Ruby の文字列補間であり、SQL文字列に直接値を埋め込んでいる。

### リスク評価

- **現状のリスク**: 低い。`fv.fiscal_year_end` は DB 由来の Date オブジェクトであり、ユーザー入力が直接流入する経路はない
- **将来のリスク**: このパターンが他のコードでも模倣されると、ユーザー入力を含むケースで SQLインジェクションの脆弱性となりうる
- **コード品質**: OWASP Top 10 の「インジェクション」に該当するアンチパターン。コーディング規約にも「セキュリティ脆弱性を導入しない」原則がある

## 実装内容

### 1. load_stock_price の修正

SQLite の `JULIANDAY` 関数にバインドパラメータを渡す:

```ruby
def load_stock_price(fv)
  target_date = fv.fiscal_year_end
  DailyQuote
    .where(company_id: fv.company_id)
    .where(traded_on: (target_date - 7.days)..(target_date + 7.days))
    .order(
      Arel.sql(
        DailyQuote.sanitize_sql_array(
          ["ABS(JULIANDAY(traded_on) - JULIANDAY(?))", target_date.to_s]
        )
      )
    )
    .pick(:adjusted_close)
end
```

### 2. プロジェクト全体の監査

以下のパターンを検索し、同様の問題がないか確認:

- `Arel.sql` 内の `#{}` 文字列補間
- `.where("...")` 内の `#{}` 文字列補間
- `.order("...")` 内の `#{}` 文字列補間

### テスト

- `load_stock_price` の既存動作が変更されないことを確認
- 日付が正しくバインドされ、最も近い株価が返されることのテスト
  - 期末日当日にデータがあるケース
  - 期末日が休日で前後の営業日にデータがあるケース

## 対象ファイル

- `app/jobs/calculate_financial_metrics_job.rb`
- プロジェクト全体（監査対象）

## 優先度

低。現時点で実際の脆弱性は存在しないが、コード品質とセキュリティベストプラクティスの観点から改善が望ましい。

## 依存関係

- なし
