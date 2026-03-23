# BUGFIX: FinancialReport の has_one :financial_value を has_many に修正

## 概要

`FinancialReport` モデルの `has_one :financial_value` アソシエーションが実態と合っていない。1つの FinancialReport に対して連結 (consolidated) と個別 (non_consolidated) の2つの FinancialValue が紐づくケースがあり、`has_one` では一方しか返されない。

## 背景・動機

### 現状のコード

```ruby
# app/models/financial_report.rb
class FinancialReport < ApplicationRecord
  has_one :financial_value  # ← 問題箇所
end
```

### FinancialValue の紐づけ方

```ruby
# ImportJquantsFinancialDataJob#import_statement (L111-127)
# 1つの report に対して、連結と個別の2つの FinancialValue を作成
import_financial_value(data, ..., scope_type: :consolidated)
if has_non_consolidated_data?(data)
  import_financial_value(data, ..., scope_type: :non_consolidated)
end

# import_financial_value 内 (L149-150)
attrs = FinancialValue.get_attributes_from_jquants(data, scope_type: scope_type)
attrs[:financial_report] = report  # 同一 report を参照
```

### 同様のパターンが EDINET にも存在

```ruby
# ImportEdinetDocumentsJob#process_document (L131-146)
if xbrl_result[:consolidated]
  upsert_financial_value(..., scope_type: :consolidated)
end
if xbrl_result[:non_consolidated]
  upsert_financial_value(..., scope_type: :non_consolidated)
end
```

### 具体的な問題

1. **`financial_report.financial_value` が不定**: has_one は SQL で `LIMIT 1` を発行するため、連結・個別のどちらが返されるか不定。DB の物理順序に依存する。

2. **`financial_report.financial_value` を使ったコードのバグリスク**: 将来的に FinancialReport からデータにアクセスするコードを書いた場合、片方のスコープしか見えない。

3. **孤立レポート検出の精度低下**: `FinancialReport.left_joins(:financial_value).where(financial_values: { id: nil })` は has_one の場合も動作するが、意味的に不正確。FinancialReport に1つだけ FV があるのに「FV なし」と判定されることはないが、概念の混乱を招く。

4. **eager loading の非効率**: `FinancialReport.includes(:financial_value)` は has_one のため1件しかロードしない。連結・個別の両方をロードしたい場合に不適切。

## 実装方針

### 1. アソシエーションの変更

```ruby
# app/models/financial_report.rb
class FinancialReport < ApplicationRecord
  has_many :financial_values  # has_one → has_many
  # ...
end
```

### 2. スコープ別のアクセサを追加（任意）

```ruby
class FinancialReport < ApplicationRecord
  has_many :financial_values

  def consolidated_value
    financial_values.find_by(scope: :consolidated)
  end

  def non_consolidated_value
    financial_values.find_by(scope: :non_consolidated)
  end
end
```

### 3. 影響範囲の確認

現在 `financial_report.financial_value` を直接呼び出しているコードがないか grep で確認:

- FinancialValue 側の `belongs_to :financial_report, optional: true` は変更不要
- DataIntegrityCheckJob の孤立レポート検出クエリ（既存 TODO で追加予定）は has_many でも正しく動作する

### 4. FinancialValue 側の has_one は維持

```ruby
# app/models/financial_value.rb
belongs_to :financial_report, optional: true  # 変更なし
```

FinancialValue → FinancialReport は多対一の関係であり、belongs_to は正しい。

## テスト

- has_many に変更後、`financial_report.financial_values` が連結・個別の両方を返すことの確認
- 既存テストが壊れないことの確認

## 優先度

中。現時点で `financial_report.financial_value` を直接使うコードは確認されていないため、即座のバグは発生していない。ただし、孤立レポート検出（20260322_1904）やデータ整合性チェックの拡張時に正しいアソシエーションが前提となるため、それらの実装前に修正すべき。

## 関連TODO

- `20260322_1904_dev_orphaned_report_detection_integrity_check` - 孤立レポート検出でこのアソシエーションを使用する
