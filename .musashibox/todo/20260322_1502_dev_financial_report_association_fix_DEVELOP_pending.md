# FinancialReport と FinancialValue のアソシエーション修正

## 背景・課題

現在の `FinancialReport` モデルでは:

```ruby
class FinancialReport < ApplicationRecord
  has_one :financial_value
end
```

しかし実際のデータでは、1つの `FinancialReport`（1件の決算書類）に対して以下の2つの `FinancialValue` が紐付く可能性がある:

1. **連結** (scope: :consolidated)
2. **個別** (scope: :non_consolidated)

`ImportJquantsFinancialDataJob` および `ImportEdinetDocumentsJob` では、同一の `report` に対して連結・個別の両方の `FinancialValue` を作成するロジックが実装されている:

```ruby
# ImportJquantsFinancialDataJob#import_statement
import_financial_value(data, ..., scope_type: :consolidated)
if has_non_consolidated_data?(data)
  import_financial_value(data, ..., scope_type: :non_consolidated)
end
```

これにより `has_one :financial_value` では一方のレコードしか取得できず、以下の問題がある:

1. `report.financial_value` がどちらの scope を返すか不定（最初に作成された方? ID順?）
2. 一方の FinancialValue しかアクセスできない
3. コードの意図と実際の動作が不一致

## 対応方針

### 1. アソシエーションの修正

```ruby
class FinancialReport < ApplicationRecord
  has_many :financial_values

  # 連結のFinancialValueを返す便利メソッド
  def consolidated_value
    financial_values.find_by(scope: :consolidated)
  end

  # 個別のFinancialValueを返す便利メソッド
  def non_consolidated_value
    financial_values.find_by(scope: :non_consolidated)
  end
end
```

### 2. 影響範囲の調査と修正

`financial_report.financial_value` を呼び出している箇所を全て洗い出し、意図に応じて修正:

- 連結を意図 → `financial_report.consolidated_value` に変更
- 両方必要 → `financial_report.financial_values` に変更

### 3. FinancialValue側の確認

`FinancialValue` の `belongs_to :financial_report, optional: true` はそのまま維持。ただし同一 report に対して scope が重複しないことをアプリケーションレベルで保証する。

## テスト観点

- 連結・個別の両方が紐付いた FinancialReport に対して `consolidated_value` / `non_consolidated_value` が正しく返るテスト
- financial_values が0件、1件（連結のみ）、2件（連結+個別）のケースをカバー

## リスク

- `has_one` → `has_many` の変更は後方互換性を破壊するため、`.financial_value` を使用している全箇所の修正が必要
- 現時点で `report.financial_value` を直接呼び出す箇所がコントローラ・ジョブ等にないか確認が必要
