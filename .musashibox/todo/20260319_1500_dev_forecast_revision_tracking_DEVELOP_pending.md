# 業績予想修正の追跡と分析

## 概要

企業が発表する業績予想（売上高・営業利益・経常利益・純利益・EPS）の修正履歴を追跡し、修正率・修正方向・修正回数を分析する機能を実装する。業績予想の上方修正パターンは企業の飛躍の兆候として重要なシグナルとなる。

## 背景

現在、FinancialValueの`data_json`にforecast_net_sales, forecast_operating_income等の予想値が保存されているが、これは取り込み時点のスナップショットであり、「企業が予想をどのように修正したか」の履歴は保持されていない。予想修正のトラッキングによって以下のユースケースが可能になる:

- 期中に複数回上方修正した企業の抽出
- 予想修正率の大きい企業の検出
- 「飛躍前の変化」分析において予想修正パターンを手がかりにする

## 実装内容

### 1. forecast_revisionsテーブルの作成

```
forecast_revisions
  - company_id (FK)
  - financial_report_id (FK) 修正が含まれる決算短信のID
  - fiscal_year_end (date) 予想対象の決算期末日
  - revision_number (integer) 同一期内での修正回数（1=初回予想、2=第1回修正...）
  - scope (integer, enum) consolidated / non_consolidated
  - forecast_net_sales (integer)
  - forecast_operating_income (integer)
  - forecast_net_income (integer)
  - forecast_eps (decimal)
  - data_json (json) 追加の予想データ
  - disclosed_at (datetime) 修正公表日
  - timestamps
```

インデックス: `[company_id, fiscal_year_end, scope, revision_number]` にユニーク制約

### 2. ForecastRevisionモデル

- `belongs_to :company`
- `belongs_to :financial_report, optional: true`
- 修正率を算出するクラスメソッド:
  - `get_revision_rate(current_revision, previous_revision)` → 各予想項目の修正率Hash
  - `get_revision_direction(revision_rate)` → :upward / :downward / :unchanged

### 3. 予想データ取り込みの拡張

- ImportJquantsFinancialDataJob を拡張し、取り込み時にforecast_revisionsにも予想値を保存する
- 同一期・同一scopeで既存の予想値と異なる場合に新しいrevision_numberで保存
- EDINET からの修正報告書（doc_type_code 140/150系の修正報告）からも予想修正を取得

### 4. テスト

- ForecastRevisionモデルの各クラスメソッドのテスト
- 修正率算出、修正方向判定のテスト
