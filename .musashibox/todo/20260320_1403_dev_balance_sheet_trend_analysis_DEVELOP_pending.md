# 貸借対照表構成比トレンド分析の実装

## 概要

企業の貸借対照表（B/S）の構成比がどのように変化しているかを時系列で追跡するメトリクスを実装する。
ポイントインタイムの比率だけでなく、その推移パターンから企業の財務戦略の変化を読み取れるようにする。

## 背景

- 既存の `dev_extend_financial_health_metrics` は流動比率やD/Eレシオなどの「ある時点の比率」を追加するタスク
- 本タスクは、それらの比率が「どう変化しているか」のトレンドメトリクスを追加する
- 「業績飛躍の直前にどのような変化があったか」を調べるには、B/S構成の変化トレンドが重要なシグナルとなる
  - 例: 総資産に占める現預金比率が減少し、固定資産比率が増加 → 積極投資フェーズ
  - 例: 有利子負債比率が減少し、自己資本比率が上昇 → 財務基盤強化フェーズ

## 実装内容

### B/S構成比（FinancialMetric data_json に追加）

1. **資産構成比**
   - 流動資産比率: current_assets / total_assets
   - 固定資産比率: noncurrent_assets / total_assets
   - 現預金比率: cash_and_equivalents / total_assets

2. **負債・資本構成比**
   - 負債比率: (total_assets - net_assets) / total_assets
   - equity_ratio は既にカラムとして存在

3. **トレンドメトリクス（前期比変化）**
   - equity_ratio_change: 自己資本比率の前期比変化幅（ポイント）
   - debt_ratio_change: 負債比率の前期比変化幅
   - cash_ratio_change: 現預金比率の前期比変化幅
   - asset_efficiency_change: 資産回転率の前期比変化

4. **財務戦略シグナル**
   - `bs_trend_signal`: B/Sの変化パターンから推定される戦略フェーズ
     - "aggressive_investment": 現預金減少 + 固定資産増加 + 売上成長
     - "financial_strengthening": 負債比率減少 + 自己資本比率上昇
     - "cash_accumulation": 現預金比率上昇 + 投資CF停滞
     - "leveraging_up": 負債比率上昇 + 積極投資
     - "neutral": 上記に該当しない

### 実装箇所

- `FinancialMetric` に `get_bs_trend_metrics(current_fv, previous_fv)` クラスメソッドを追加
- `get_bs_trend_signal` メソッドで戦略フェーズを判定
- `data_json` に上記指標を格納
- `CalculateFinancialMetricsJob` で併せて算出

### テスト

- 構成比算出のテスト
- トレンド変化幅の算出テスト（正・負・nil安全性）
- 戦略シグナル判定のテスト（各パターンおよびneutral）

## 依存

- 既存の `financial_values` テーブル（total_assets, net_assets, cash_and_equivalents, equity_ratio）
- EDINET XBRL拡張データ（current_assets, noncurrent_assets）があるとより精度が高い
- `dev_extend_financial_health_metrics` と並行実装可能（重複なし）
