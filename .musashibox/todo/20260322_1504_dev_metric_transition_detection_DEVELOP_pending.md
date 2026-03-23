# 指標の前期比変化フラグ（トレンド転換検出基盤）

## 背景・課題

本プロジェクトのユースケース2:

> 「営業キャッシュフローがプラスかつ投資キャッシュフローがマイナスの企業のうち、営業キャッシュフローと投資キャッシュフローの差がプラスに転換した企業を一覧する」

これを実現するには、「FCFがマイナスからプラスに転換した」というトレンドの**転換点**を検出する仕組みが必要。

現状の `FinancialMetric` には `free_cf_positive` などの当期時点のBoolean値は存在するが、**前期からの変化（転換）**を示す情報がない。

### 問題の具体例

以下のようなデータがあるとき:

| 年度 | free_cf | free_cf_positive |
|------|---------|------------------|
| 2023 | -500    | false            |
| 2024 | 300     | true             |
| 2025 | 800     | true             |

2024年が「プラスに転換した年」だが、現状のスキーマからはこれを直接判定できない。毎回2つの期間のデータをJOINして比較する必要がある。

## 対応方針

### 1. FinancialMetric の data_json にトレンド転換フラグを追加

`CalculateFinancialMetricsJob` において、前期の `FinancialMetric` と比較し、以下のフラグを `data_json` に記録:

```ruby
# トレンド転換を検出するメソッド
def self.get_transition_flags(current_cf, previous_metric)
  return {} unless previous_metric

  flags = {}

  # FCFプラス転換: 前期false → 当期true
  if current_cf[:free_cf_positive] == true && previous_metric.free_cf_positive == false
    flags["free_cf_turned_positive"] = true
  end

  # FCFマイナス転換: 前期true → 当期false
  if current_cf[:free_cf_positive] == false && previous_metric.free_cf_positive == true
    flags["free_cf_turned_negative"] = true
  end

  # 営業CFプラス転換
  if current_cf[:operating_cf_positive] == true && previous_metric.operating_cf_positive == false
    flags["operating_cf_turned_positive"] = true
  end

  # 黒字転換（net_income_yoy比較ではなく、前期赤字→当期黒字の転換）
  # ※ FinancialValueの net_income を使用
  # 別途実装が必要

  flags
end
```

### 2. 成長性のトレンド転換も検出

YoY指標の符号変化もトレンド転換として有用:

- `revenue_growth_turned_positive`: 前期 revenue_yoy <= 0 → 当期 > 0 (減収→増収)
- `revenue_growth_turned_negative`: 前期 revenue_yoy > 0 → 当期 <= 0 (増収→減収)
- `profit_growth_turned_positive`: 純利益についても同様

これらにより「増収に転じた企業」「減益に転じた企業」のスクリーニングが可能になる。

### 3. CalculateFinancialMetricsJob への統合

既存の `calculate_metrics_for` メソッドに転換フラグ計算を追加:

```ruby
def calculate_metrics_for(fv)
  # ... existing code ...
  transitions = FinancialMetric.get_transition_flags(cf, previous_metric)
  growth_transitions = FinancialMetric.get_growth_transition_flags(growth, previous_metric)

  json_updates = {}.merge(valuation).merge(ev_ebitda).merge(surprise)
                    .merge(transitions).merge(growth_transitions)
  # ...
end
```

### 4. スクリーニングでの活用

SQLiteのJSON関数を使って `data_json` 内のフラグでフィルタリング:

```ruby
# FCFプラスに転換した企業
FinancialMetric.latest_annual
  .where("json_extract(data_json, '$.free_cf_turned_positive') = ?", true)
  .where(operating_cf_positive: true, investing_cf_negative: true)
```

## テスト観点

- `get_transition_flags` のユニットテスト: 各転換パターン（false→true, true→false, 変化なし, nil）
- `get_growth_transition_flags` のユニットテスト
- previous_metric が nil の場合のテスト（転換フラグは空Hashを返す）
- 全てDBアクセス不要

## 関連TODO

- `20260322_1503_dev_company_latest_metric_screening`: スクリーニング基盤。本TODOで追加するフラグは、スクリーニング条件として活用される
- `20260319_1401_plan_trend_turning_point_detection`: トレンド転換点の検出計画。本TODOはその実装の一部（指標レベルの転換フラグ）
