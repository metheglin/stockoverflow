# DEVELOP: 企業コード変更・承継の追跡機能

## 概要

合併・組織再編・再上場などにより証券コードが変更された場合、現行システムは旧コードと新コードの企業を別レコードとして扱う。これにより過去データとの連続性が断絶し、連続増収増益などの時系列分析が正確にできない。コード変更の承継関係を追跡する仕組みを追加する。

## 背景・動機

### 現状の問題

1. Company テーブルは `securities_code`（ユニーク）で企業を識別
2. JQUANTS の SyncCompaniesJob は `securities_code` で find_or_create する
3. 企業が証券コードを変更すると、新コードの企業が新規作成される
4. 旧コードの企業に紐づく financial_values, financial_metrics, daily_quotes は参照不能に

### 実例となるケース

- **合併**: A社(1234)がB社(5678)を吸収合併し、A社がコード変更(1234→9012)
- **持株会社化**: C社(3456)が持株会社体制に移行しコード変更(3456→3457)
- **市場変更に伴うコード変更**: 稀だが発生する

### 影響範囲

- CalculateFinancialMetricsJob#find_previous_financial_value: 旧コードのデータが見つからずYoY計算不能
- consecutive_revenue_growth / consecutive_profit_growth: 連続カウントがリセットされる
- 企業単位のスクリーニング結果: 旧コード時代の優良企業が「データ不足」扱いになる

## 実装方針

### DBスキーマ

`company_successions` テーブルを追加:

```ruby
create_table :company_successions do |t|
  t.references :predecessor, null: false, foreign_key: { to_table: :companies }
  t.references :successor, null: false, foreign_key: { to_table: :companies }
  t.date :effective_date
  t.integer :succession_type, null: false, default: 0
  # succession_type: 0=code_change, 1=merger, 2=spin_off, 3=relisting
  t.json :data_json
  t.timestamps
end

add_index :company_successions, [:predecessor_id, :successor_id], unique: true
```

### Company モデルの拡張

```ruby
class Company < ApplicationRecord
  has_many :successor_relations, class_name: "CompanySuccession",
           foreign_key: :predecessor_id
  has_many :predecessor_relations, class_name: "CompanySuccession",
           foreign_key: :successor_id

  # 承継チェーンをたどって同一企業のcompany_idsをすべて返す
  def get_lineage_company_ids
    ids = Set.new([id])
    # 遡る（前身企業）
    predecessor_relations.each do |rel|
      ids.merge(rel.predecessor.get_lineage_company_ids)
    end
    ids.to_a
  end
end
```

### CalculateFinancialMetricsJob での活用

`find_previous_financial_value` で lineage を考慮した検索を行う:

```ruby
def find_previous_financial_value(fv)
  company_ids = fv.company.get_lineage_company_ids

  FinancialValue
    .where(company_id: company_ids, scope: fv.scope, period_type: fv.period_type)
    .where(fiscal_year_end: prev_start..prev_end)
    .order(fiscal_year_end: :desc)
    .first
end
```

## 備考

- 承継データの登録は手動を想定（自動検出は困難）
- EDINET の edinet_code は組織再編でも継続される場合があるため、edinet_code の一致で承継候補を検出するヒューリスティックも検討可能
- get_lineage_company_ids の再帰呼び出しには上限を設ける（無限ループ防止）

## 優先度

中。ユースケース1（6期連続増収増益）の正確性に影響するが、該当企業数は限定的。
