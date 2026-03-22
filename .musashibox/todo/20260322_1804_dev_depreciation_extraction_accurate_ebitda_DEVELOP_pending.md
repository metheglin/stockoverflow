# DEVELOP: 減価償却費の抽出と正確なEBITDA算出

## 概要

EDINET XBRLから減価償却費（depreciation）を抽出し、`FinancialValue.data_json` に格納する。これにより、現在の簡易版 EBITDA（= 営業利益）を正確な EBITDA（= 営業利益 + 減価償却費）に改善する。

## 背景

### 現在の実装 (`app/models/financial_metric.rb:151`)

```ruby
ebitda = fv.operating_income  # 簡易版: 減価償却費データ未取得
```

### 問題

- EBITDA = Earnings Before Interest, Taxes, Depreciation, and Amortization
- 正確な EBITDA = 営業利益 + 減価償却費 + 償却費
- 現在は営業利益のみで代替しており、設備投資が大きい企業（製造業など）で過小評価される
- EV/EBITDA の精度に直結し、バリュエーション比較の信頼性を損なっている

### データの可用性

EDINET XBRL には以下のXBRL要素で減価償却費が含まれている:
- `jppfs_cor:DepreciationAndAmortizationSGA` - 販管費の減価償却費
- `jppfs_cor:DepreciationAndAmortizationCOGS` - 売上原価の減価償却費
- `jppfs_cor:DepreciationCF` / `jppfs_cor:DepreciationAndAmortizationCF` - CF計算書の減価償却費（間接法）

CF計算書の減価償却費が最も取得しやすく、営業利益に加算する形で EBITDA を算出するのに適している。

## 実装内容

### 1. `EdinetXbrlParser` の拡張

`app/lib/edinet_xbrl_parser.rb` の `EXTENDED_ELEMENTS` に減価償却費関連の要素を追加。

```ruby
EXTENDED_ELEMENTS = {
  # 既存要素...
  depreciation: {
    element: "DepreciationAndAmortizationOpeCF",
    context: :consolidated_duration,
    candidates: [
      "DepreciationAndAmortizationSGA",
      "DepreciationCF",
    ],
  },
}
```

### 2. `FinancialValue.data_json` スキーマの拡張

`app/models/financial_value.rb` の `define_json_attributes` に追加。

```ruby
define_json_attributes :data_json, schema: {
  # 既存フィールド...
  depreciation: { type: :integer },
}
```

### 3. `FinancialMetric.get_ev_ebitda` の改善

```ruby
def self.get_ev_ebitda(fv, stock_price)
  # 既存のバリデーション...

  market_cap = stock_price * fv.shares_outstanding
  debt_approx = fv.total_assets - fv.net_assets
  cash = fv.cash_and_equivalents || 0

  ev = market_cap + debt_approx - cash
  depreciation = fv.depreciation || 0
  ebitda = fv.operating_income + depreciation

  { "ev_ebitda" => (ev.to_d / ebitda.to_d).round(2).to_f }
end
```

### 4. ImportEdinetDocumentsJob での連携

XBRLパース時に `depreciation` がextendedデータとして抽出され、`data_json` に自動的にマージされるため、ジョブ側の変更は不要（既存のマージロジックで対応可能）。

## テスト

### `spec/lib/edinet_xbrl_parser_spec.rb`

- `extract_values`: depreciation が extended elements として抽出されること
- `extract_values`: 複数の候補要素からフォールバックで取得されること

### `spec/models/financial_metric_spec.rb`

- `get_ev_ebitda`: depreciation が存在する場合、EBITDA = operating_income + depreciation で計算されること
- `get_ev_ebitda`: depreciation が nil の場合、EBITDA = operating_income にフォールバックすること

## 影響範囲

- `app/lib/edinet_xbrl_parser.rb` - EXTENDED_ELEMENTS に depreciation 追加
- `app/models/financial_value.rb` - data_json スキーマに depreciation 追加
- `app/models/financial_metric.rb` - `get_ev_ebitda` メソッド改善
- `spec/lib/edinet_xbrl_parser_spec.rb` - テスト追加
- `spec/models/financial_metric_spec.rb` - テスト追加
- 既存の `financial_metrics` レコード（再計算が必要）
