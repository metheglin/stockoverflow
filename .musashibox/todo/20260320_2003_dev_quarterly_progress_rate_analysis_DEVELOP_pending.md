# DEVELOP: 四半期進捗率分析

## 概要

四半期累計の実績が通期業績予想（または前年通期実績）に対してどの程度の進捗であるかを算出し、業績の上振れ・下振れシグナルを早期に検出する。

## 背景・動機

日本企業の多くは3月決算であり、本決算（通期）の開示は5-6月になる。一方、四半期決算（Q1: 8月頃、Q2: 11月頃、Q3: 2月頃）は順次開示される。

投資判断において最も実用的な分析の一つは「Q1-Q3時点で通期業績をどの程度達成しているか」の進捗率分析である:

- Q3時点で通期予想の90%を達成 → 上振れの可能性が高い
- Q3時点で通期予想の65%しか達成していない → 下振れの懸念
- 前年同期比で進捗率が改善 → 業績モメンタムの加速

現在のシステムは四半期データ（period_type: q1/q2/q3）と通期データ（period_type: annual）を保持しているが、両者を横断的に比較する仕組みがない。

## 実装内容

### 追加指標（FinancialMetric data_json 拡張）

Q1/Q2/Q3 の FinancialMetric に以下を追加:

1. **revenue_progress_vs_forecast**: 売上の対通期予想進捗率
   - 算出: 累計売上 / 通期売上予想 × 100
   - 通期予想は同一fiscal_yearの FinancialValue.data_json.forecast_net_sales を使用

2. **operating_income_progress_vs_forecast**: 営業利益の対通期予想進捗率
   - 算出: 累計営業利益 / 通期営業利益予想 × 100

3. **net_income_progress_vs_forecast**: 純利益の対通期予想進捗率

4. **revenue_progress_vs_prior_year**: 売上の対前年通期進捗率
   - 算出: 累計売上 / 前年通期売上 × 100
   - 前年通期データは前年の annual FinancialValue を使用

5. **progress_rate_vs_typical**: 標準的な進捗率との比較
   - 標準進捗率: Q1=25%, Q2=50%, Q3=75%（均等配分ベース）
   - 算出: 実際の進捗率 - 標準進捗率
   - 正の値 = 上振れ傾向、負の値 = 下振れ傾向

6. **progress_rate_yoy_delta**: 進捗率の前年同期比変化
   - 算出: 当期の進捗率 - 前年同期の進捗率
   - 進捗率そのものが改善しているか悪化しているかを判定

### 上振れ・下振れ判定

7. **earnings_trajectory**: 業績軌道の判定
   - `likely_upside`: 進捗率が標準を大きく上回る（+10ポイント以上）
   - `on_track`: 標準的な範囲内（±10ポイント）
   - `likely_downside`: 進捗率が標準を大きく下回る（-10ポイント以上）
   - `unknown`: 予想データがない場合

## 実装方針

1. **FinancialMetric にクラスメソッドを追加**:
   - `self.get_progress_rate_metrics(current_fv, annual_forecast_fv, prior_year_annual_fv, prior_year_quarterly_metric)`
   - current_fv: 当四半期の FinancialValue
   - annual_forecast_fv: 通期予想を含む FinancialValue（data_jsonのforecast値）
   - prior_year_annual_fv: 前年通期の FinancialValue
   - prior_year_quarterly_metric: 前年同四半期の FinancialMetric（進捗率YoY算出用）

2. **CalculateFinancialMetricsJob での条件分岐**:
   - period_type が q1/q2/q3 の場合のみ算出
   - annual の場合はスキップ
   - 通期予想データの取得: 同一company_id・同一fiscal_yearの直近 FinancialValue から forecast 値を取得

3. **標準進捗率の季節性調整（将来拡張）**:
   - 初期実装は均等配分（25%/50%/75%）をデフォルトとする
   - `dev_quarterly_revenue_seasonality_analysis` が実装された場合、企業ごとの季節性パターンを使った調整が可能

## テスト

- `FinancialMetric.get_progress_rate_metrics`:
  - Q3で累計売上90億、通期予想100億のとき progress_vs_forecast=90.0 であること
  - Q2で累計営業利益6億、前年通期10億のとき progress_vs_prior_year=60.0 であること
  - 通期予想がnilの場合に forecast系指標がnilとなること
  - progress_rate_vs_typical: Q3で進捗率90%のとき +15.0（90-75）であること
  - earnings_trajectory: 進捗率が標準+10以上で "likely_upside" であること
  - period_type=annual のとき nil を返すこと（算出対象外）

## 関連TODO

- `dev_quarterly_revenue_seasonality_analysis` - 季節性パターンを用いた進捗率の精緻化
- `dev_management_forecast_accuracy_profile` - 経営者予想の精度と組み合わせた総合判断
- `dev_financial_event_detection` - 進捗率が閾値を超えた場合にイベントとして検出
- `dev_forecast_revision_tracking` - 通期予想の修正と進捗率の連動分析
