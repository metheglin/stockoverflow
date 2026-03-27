# DEVELOP: 成長加速度メトリクスの追加

## 概要

成長率の「変化率」（2階微分に相当する加速度指標）をFinancialMetricのdata_jsonに追加し、成長の勢いの強まり・弱まりを定量的に把握できるようにする。

## 背景・動機

現在のシステムでは以下の成長関連指標を保持している:

- **YoY成長率**: revenue_yoy, operating_income_yoy 等（1階微分）
- **連続増収増益期数**: consecutive_revenue_growth, consecutive_profit_growth（成長の持続性）
- **トレンド分類** (TODO): improving / deteriorating 等のラベル（方向性の定性判断）

しかし、成長の「勢い」を定量的に捉える指標が欠けている。例:

- 企業A: 売上YoY +5% → +10% → +15%（加速成長）
- 企業B: 売上YoY +15% → +10% → +5%（減速成長）

両社とも「3期連続増収」であり、トレンド分類では共に「improving」となりうるが、投資判断上は全く異なるシグナルである。

プロジェクトの主要ユースケースである「業績飛躍の直前の変化を捉える」にとって、成長加速度は飛躍の前兆を検出する上で極めて重要な指標となる。

## 追加指標（data_json拡張）

### 1. revenue_growth_acceleration（売上成長加速度）

```
算出: 当期 revenue_yoy - 前期 revenue_yoy
単位: ポイント差（例: +10% → +15% の場合、+5.0）
```

### 2. operating_income_growth_acceleration（営業利益成長加速度）

```
算出: 当期 operating_income_yoy - 前期 operating_income_yoy
```

### 3. net_income_growth_acceleration（純利益成長加速度）

```
算出: 当期 net_income_yoy - 前期 net_income_yoy
```

### 4. eps_growth_acceleration（EPS成長加速度）

```
算出: 当期 eps_yoy - 前期 eps_yoy
```

### 5. acceleration_consistency（加速の一貫性）

```
算出: 直近3期の revenue_growth_acceleration が全て正か全て負かを判定
値: "accelerating" | "decelerating" | "mixed"
```

## 実装方針

1. **FinancialMetric にクラスメソッドを追加**:
   - `self.get_growth_acceleration_metrics(current_metric, previous_metric)`
   - current_metric / previous_metric は共に FinancialMetric インスタンス
   - previous_metric の YoY値 と current_metric の YoY値 の差分を算出

2. **acceleration_consistency の算出**:
   - `self.get_acceleration_consistency(current_metric, previous_metrics)`
   - previous_metrics は直近2-3期分の FinancialMetric 配列
   - 各期の revenue_growth_acceleration の符号を確認

3. **CalculateFinancialMetricsJob への組み込み**:
   - メトリクス算出時に前期の FinancialMetric を取得する処理は既に存在
   - growth_acceleration_metrics を data_json に追加保存

4. **data_json スキーマ追加**:
   - FinancialMetric の define_json_attributes に上記5指標を追加

## テスト

- `FinancialMetric.get_growth_acceleration_metrics`:
  - 前期YoY=10%, 当期YoY=15% のとき acceleration=+5.0 であること
  - 前期YoY=15%, 当期YoY=10% のとき acceleration=-5.0 であること
  - 前期または当期のYoYがnilの場合にnilを返すこと
- `FinancialMetric.get_acceleration_consistency`:
  - 3期連続で加速の場合に "accelerating" を返すこと
  - 3期連続で減速の場合に "decelerating" を返すこと
  - 期数が不足する場合にnilを返すこと

## 関連TODO

- `dev_metric_trend_classification` - トレンド分類と組み合わせることで「加速的改善中」の検出が可能
- `dev_financial_event_detection` - 加速度の急変をイベントとして検出
- `plan_pre_breakthrough_pattern_analysis` - 飛躍前のパターンとして「成長加速度の転換」が重要指標になりうる
- `dev_company_comparison_report` - 比較レポートに加速度指標を含める
