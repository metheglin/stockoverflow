# ROE算出ロジックの修正（純資産→株主資本）

## 背景・課題

`FinancialMetric.get_profitability_metrics` において、ROEの算出に `net_assets`（純資産）を使用している:

```ruby
def self.get_profitability_metrics(fv)
  {
    roe: safe_divide(fv.net_income, fv.net_assets),
    ...
  }
end
```

しかし、正確なROE（Return on Equity、自己資本利益率）は以下の通り:

```
ROE = 当期純利益 / 自己資本（株主資本）
```

`net_assets`（純資産）には非支配株主持分（少数株主持分）や新株予約権が含まれるため、分母が過大となりROEが過小評価される。

### 現状のデータ構造

`FinancialValue` の `data_json` には XBRL から抽出された `shareholders_equity`（株主資本）が格納される場合がある:

```ruby
define_json_attributes :data_json, schema: {
  # ...
  shareholders_equity: { type: :integer },
}
```

ただし `shareholders_equity` はXBRL経由でのみ取得されるため、JQUANTS由来のデータのみの企業では未設定の場合がある。

## 対応方針

### 1. ROE算出ロジックの修正

`get_profitability_metrics` を修正し、`shareholders_equity` を優先的に使用する:

```ruby
def self.get_profitability_metrics(fv)
  equity_for_roe = fv.shareholders_equity.presence || fv.net_assets
  {
    roe: safe_divide(fv.net_income, equity_for_roe),
    # ...
  }
end
```

- `shareholders_equity`（data_json）が存在する場合はそれを使用
- 存在しない場合は従来通り `net_assets` にフォールバック
- 将来的にJQUANTSからも株主資本データが取得可能になった場合に対応できるよう、フォールバック構造を維持

### 2. ROE計算根拠の記録

`FinancialMetric` の `data_json` に `roe_basis` フィールドを追加し、ROE計算に使用した分母の種類を記録:

- `"shareholders_equity"` : 株主資本を使用
- `"net_assets"` : 純資産を使用（フォールバック）

スクリーニング時に計算根拠の違いを考慮できるようにする。

## テスト観点

- `shareholders_equity` がある場合のROE計算テスト
- `shareholders_equity` がない場合のフォールバックテスト
- `roe_basis` の正しい記録テスト
- 全てDBアクセス不要のユニットテストで完結
