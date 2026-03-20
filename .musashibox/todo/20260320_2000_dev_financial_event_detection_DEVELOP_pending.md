# DEVELOP: 財務イベント検出・記録システム

## 概要

FinancialMetric算出時に、投資判断上意味のある「財務イベント」を自動検出し、専用テーブルに記録する仕組みを構築する。

## 背景・動機

現在のシステムは財務指標を蓄積・算出しているが、「何か重要な変化が起きた」ことを自律的に検出する仕組みがない。

- `dev_financial_anomaly_detection` は統計的な異常値（2σ以上の乖離等）を検出するものであり、業務的な意味を持つイベントとは異なる
- `dev_metric_trend_classification` はトレンドの方向性をラベル付けするが、離散的なイベント（発生時点と内容）を記録するものではない
- 投資家が日常的に知りたいのは「今日何が変わったか」であり、FinancialMetricの比較だけでは変化の要点を即座に把握できない

## 検出対象イベント

### 成長ストリーク関連
- `streak_started`: 連続増収増益カウントが0→1に変化（新たなストリーク開始）
- `streak_broken`: 前期まで3期以上の連続増収増益があったが今期途切れた
- `streak_milestone`: 連続増収増益が5期・10期などのマイルストーンに到達

### キャッシュフロー関連
- `fcf_turned_positive`: フリーCFがマイナスからプラスに転換
- `fcf_turned_negative`: フリーCFがプラスからマイナスに転換
- `operating_cf_turned_negative`: 営業CFが初めてマイナスに転落

### 収益性関連
- `margin_expansion`: 営業利益率が前期比で3ポイント以上改善
- `margin_contraction`: 営業利益率が前期比で3ポイント以上悪化
- `roe_crossed_threshold`: ROEが10%/15%/20%の閾値を上方または下方に突破

### 成長率関連
- `extreme_growth`: 売上・営業利益のYoYが50%以上の急成長
- `extreme_decline`: 売上・営業利益のYoYが-30%以下の急落
- `growth_acceleration`: 成長率が前期より5ポイント以上加速
- `growth_deceleration`: 成長率が前期より5ポイント以上減速

## DB設計

### financial_events テーブル

```ruby
create_table :financial_events do |t|
  t.references :company, null: false, foreign_key: true
  t.references :financial_metric, null: false, foreign_key: true
  t.integer :event_type, null: false        # enum管理
  t.integer :severity, null: false, default: 0  # info=0, notable=1, critical=2
  t.date :fiscal_year_end, null: false
  t.json :data_json                          # イベント固有の詳細データ
  t.timestamps
end

add_index :financial_events, [:company_id, :fiscal_year_end]
add_index :financial_events, [:event_type, :created_at]
add_index :financial_events, :severity
```

### FinancialEvent モデル

```ruby
class FinancialEvent < ApplicationRecord
  belongs_to :company
  belongs_to :financial_metric

  enum :event_type, {
    streak_started: 1,
    streak_broken: 2,
    streak_milestone: 3,
    fcf_turned_positive: 10,
    fcf_turned_negative: 11,
    operating_cf_turned_negative: 12,
    margin_expansion: 20,
    margin_contraction: 21,
    roe_crossed_threshold: 22,
    extreme_growth: 30,
    extreme_decline: 31,
    growth_acceleration: 32,
    growth_deceleration: 33,
  }

  enum :severity, {
    info: 0,
    notable: 1,
    critical: 2,
  }
end
```

## 実装方針

1. **FinancialEvent モデルの作成**: 上記テーブル設計に基づくマイグレーション・モデル作成
2. **イベント検出ロジック**: `FinancialMetric` にクラスメソッドとして実装
   - `self.detect_events(current_metric, previous_metric)` → イベント配列を返す
   - 閾値は定数として管理
3. **CalculateFinancialMetricsJob への組み込み**: メトリクス算出後にイベント検出を実行し、`FinancialEvent` を保存
4. **冪等性**: 同一 company_id + fiscal_year_end + event_type の重複を防止

## テスト

- `FinancialMetric.detect_events` のユニットテスト
  - 連続増収増益が0→1になったときに `streak_started` が検出されること
  - 3期以上のストリークが途切れたときに `streak_broken` が検出されること
  - フリーCFの正負転換イベントが正しく検出されること
  - 営業利益率の大幅変化が検出されること
  - 前期データがない場合にエラーにならないこと

## 関連TODO

- `dev_financial_anomaly_detection` - 統計的異常値検出（本TODOとは相互補完的）
- `dev_metric_trend_classification` - トレンド分類（イベントの文脈を提供）
- `plan_investor_alert_digest` - イベントを集約・配信する仕組み（本TODOが基盤データを提供）
- `plan_watchlist_screening_preset` - ウォッチリスト企業のイベントを優先表示する連携
