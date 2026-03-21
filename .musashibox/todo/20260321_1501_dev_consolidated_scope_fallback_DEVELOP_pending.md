# DEVELOP: 連結/個別スコープ自動フォールバック機能

## 概要

分析において連結（consolidated）データを優先し、連結データが存在しない企業については自動的に個別（non_consolidated）データにフォールバックする仕組みをモデル層に実装する。

## 背景・動機

- 上場企業の多くは連結決算を開示しているが、子会社を持たない中小型企業は個別決算のみを開示するケースが多い
- 現在の分析クエリ（QueryObject）は `scope_type: :consolidated` をデフォルトとしているが、この場合個別決算のみの企業は分析対象から完全に除外される
- 例えば連続増収増益のスクリーニングにおいて、実際には素晴らしい業績の個別決算企業が見逃される
- 分析の実用性を高めるために、「連結があれば連結、なければ個別」という自然なフォールバック戦略が必要

## 実装方針

### FinancialValueへのスコープ追加

```ruby
class FinancialValue < ApplicationRecord
  # 企業ごとに連結優先・個別フォールバックで最新のスコープタイプを決定する
  # 連結のFinancialValueが1件でも存在すれば連結、存在しなければ個別を採用
  #
  # @return [ActiveRecord::Relation] 適用されたスコープのFinancialValue
  scope :preferred_scope, -> {
    where(
      "scope = CASE " \
      "WHEN EXISTS (SELECT 1 FROM financial_values fv2 " \
      "  WHERE fv2.company_id = financial_values.company_id " \
      "  AND fv2.scope = 0) " \
      "THEN 0 ELSE 1 END"
    )
  }
end
```

### Companyへの便利メソッド追加

```ruby
class Company < ApplicationRecord
  # この企業で採用すべきスコープタイプを返す
  # consolidated のデータが存在すれば :consolidated、なければ :non_consolidated
  def preferred_scope_type
    if financial_values.consolidated.exists?
      :consolidated
    else
      :non_consolidated
    end
  end
end
```

### FinancialMetricへのスコープ追加

```ruby
class FinancialMetric < ApplicationRecord
  # preferred_scope: 企業ごとに連結優先・個別フォールバックのメトリクスを返す
  # 分析クエリレイヤー（QueryObject）での利用を想定
  scope :preferred_scope, -> {
    where(
      "scope = CASE " \
      "WHEN EXISTS (SELECT 1 FROM financial_metrics fm2 " \
      "  WHERE fm2.company_id = financial_metrics.company_id " \
      "  AND fm2.scope = 0) " \
      "THEN 0 ELSE 1 END"
    )
  }
end
```

### 分析クエリレイヤーとの連携

既存TODO `20260312_1000_dev_analysis_query_layer` のQueryObjectクラスに `scope_type: :preferred` オプションを追加可能にする。`:preferred` が指定された場合、上記のスコープを利用して企業ごとに最適なスコープを自動選択する。

## テスト

- `spec/models/company_spec.rb` に `preferred_scope_type` のテストを追加
  - 連結データが存在する企業 → `:consolidated` を返す
  - 個別データのみの企業 → `:non_consolidated` を返す
  - データが存在しない企業 → `:non_consolidated` を返す

## 依存関係

- 分析クエリレイヤー（dev_analysis_query_layer）の実装前に完了しておくことが望ましい
- Company検索・ルックアップ（dev_company_search_and_lookup）と併用可能
