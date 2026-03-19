# 配当分析メトリクス実装

## 概要

既存の `dividend_yield`（配当利回り）に加え、配当性向・連続増配期間・配当成長率を `FinancialMetric` に追加する。インカム投資やバリュー投資の分析に必要な指標群。

## 背景

- `financial_values` には `dividend_per_share`（1株あたり配当金）が JQUANTS から取得済み
- `financial_metrics` には `dividend_yield` が `data_json` に計算済み
- しかし、配当性向（配当金/利益の比率）や連続増配の追跡は未実装
- 「安定して利益を出しつつ配当を増やしている企業」は投資判断の重要な視点

## 実装内容

### 1. FinancialMetric にメソッド追加

#### `get_dividend_metrics(current_fv, prior_fv, prior_metric)`

```ruby
def self.get_dividend_metrics(current_fv, prior_fv, prior_metric)
  dps = current_fv.dividend_per_share
  eps = current_fv.eps
  prior_dps = prior_fv&.dividend_per_share

  {
    payout_ratio: get_payout_ratio(dps, eps),
    dividend_growth_rate: compute_yoy(dps, prior_dps),
    consecutive_dividend_growth: get_consecutive_dividend_growth(dps, prior_dps, prior_metric),
  }
end
```

#### 各指標の定義

- **payout_ratio（配当性向）**: `dividend_per_share / eps * 100`
  - EPSがマイナスの場合はNULL
  - 100%超も記録する（タコ足配当の検出に有用）
- **dividend_growth_rate（配当成長率）**: 前年DPSとのYoY
- **consecutive_dividend_growth（連続増配期間）**: 前年比で配当が増加し続けている期間数
  - 前年DPSと同額の場合は「増配」に含めない（増配 = strictly greater）
  - 前年DPS = 0 かつ今期 > 0 の場合は増配開始（1にリセット）

### 2. data_json スキーマ拡張

`financial_metrics.data_json` に以下を追加:
- `payout_ratio`: Float (%)
- `dividend_growth_rate`: Float (%)
- `consecutive_dividend_growth`: Integer

### 3. CalculateFinancialMetricsJob への統合

- 既存の metrics 計算フローに `get_dividend_metrics` を追加
- `prior_fv` と `prior_metric` は既に取得済みのため、追加クエリ不要

### 4. テスト

- `get_dividend_metrics()` のユニットテスト
  - 正常ケース（DPS増加、EPSプラス）
  - EPSマイナス時の配当性向 = NULL
  - 配当性向100%超（タコ足配当）
  - 無配から有配への転換
  - 連続増配カウントの継続・リセット
  - 前年データ欠損時

## 注意事項

- 中間配当と期末配当を合算した年間配当で計算すること（JQUANTSの `dividend_per_share` がどの範囲を示すか確認必要）
- 株式分割・併合が配当の見かけ上の変化を生む可能性があるが、初期実装では考慮外とする
