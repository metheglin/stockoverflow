# 指標タイムシリーズアクセサの実装

## 概要

プロジェクト目標「推移やトレンドの転換がわかるようにしたい」を実現するための基盤として、
企業ごとのFinancialMetricを時系列で簡潔に取得できるアクセサメソッドを実装する。
現状ではFinancialMetricの時系列取得に毎回手動でクエリを組み立てる必要があり、
多くの下流タスク（トレンド分析、パターン検出、連続成長検証）の共通基盤となる。

## 背景

- FinancialMetricは(company_id, fiscal_year_end, scope, period_type)のユニーク制約で管理
- 各レコードはある1期間の指標を保持するため、複数期間を横断した分析にはクエリの組み立てが必要
- `dev_financial_value_period_navigation` はFinancialValue（生データ）のナビゲーションであり、FinancialMetric（算出指標）の時系列アクセスとは異なる
- ROE・営業利益率・連続増収期数などの推移を簡単に取得できるAPIが、スクリーニングやレポーティングの前提条件

## 作業内容

### 1. FinancialMetricモデルへのクラスメソッド追加

```ruby
# 指定企業の指標を時系列で取得
# @param company [Company] 対象企業
# @param metric_name [Symbol] 指標名 (:roe, :operating_margin, :revenue_yoy, etc.)
# @param scope [Symbol] :consolidated or :non_consolidated (default: :consolidated)
# @param period_type [Symbol] :annual, :q1, :q2, :q3 (default: :annual)
# @param periods [Integer, nil] 直近N期分（nilで全期間）
# @return [Array<Hash>] [{fiscal_year_end:, value:}, ...]
def self.get_metric_series(company, metric_name, scope: :consolidated, period_type: :annual, periods: nil)
```

### 2. data_json内指標への対応

- `per`, `pbr`, `psr`等のdata_json内の指標もmetric_nameで指定可能にする
- 固定カラムとdata_jsonの区別を呼び出し側が意識しなくてよい設計

### 3. 複数指標の同時取得

```ruby
# 複数指標を一括で時系列取得
# @return [Hash<Symbol, Array<Hash>>] { roe: [{fiscal_year_end:, value:}, ...], ... }
def self.get_metric_series_bulk(company, metric_names, **options)
```

### 4. Companyモデルへの委譲メソッド

```ruby
# company.metric_series(:roe, periods: 5)
def metric_series(metric_name, **options)
  FinancialMetric.get_metric_series(self, metric_name, **options)
end
```

### 5. テスト

- 固定カラム指標の時系列取得テスト
- data_json指標の時系列取得テスト
- periods指定による件数制限テスト
- データが存在しない場合の挙動テスト

## 対象ファイル

- `app/models/financial_metric.rb`
- `app/models/company.rb`
- `spec/models/financial_metric_spec.rb`
- `spec/models/company_spec.rb`

## 優先度

高 - 多数のスクリーニング・分析系TODOの共通基盤
