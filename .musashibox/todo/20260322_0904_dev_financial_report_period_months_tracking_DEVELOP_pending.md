# dev_financial_report_period_months_tracking

## 概要

financial_reports / financial_values に決算対象期間の月数（period_months）を追跡する仕組みを追加し、変則決算期を体系的に検出・管理する。

## 背景・目的

日本企業は決算期を変更する場合がある（例：3月決算→12月決算への移行）。この際、移行期には12ヶ月に満たない変則決算期が発生する。例：

- 通常: 2024年4月〜2025年3月（12ヶ月）
- 変則: 2025年4月〜2025年12月（9ヶ月）←決算期変更の移行期
- 新通常: 2026年1月〜2026年12月（12ヶ月）

この変則期のデータについて:
- **YoY比較が不適切**: 9ヶ月の売上と12ヶ月の売上を比較してYoYを計算すると、-25%の「減収」と誤判定される
- **consecutive growth カウンタが断絶**: 実質的に成長を続けている企業でも、変則期を挟むとカウンタがリセットされる
- **年換算の必要性**: 変則期のデータを12ヶ月換算して比較する需要がある

既存の関連TODO:
- `fiscal_period_normalization` (PLAN) はLTM/TTM計算や年換算の**設計**を含むが、その前提として「期間月数」のデータが必要
- `metric_calculation_edge_cases` は変則決算のYoY計算スキップに言及するが、期間月数のデータモデリングは含まれない
- 本TODOはこれらの**データ基盤**を提供する

## 実装内容

### マイグレーション

financial_values テーブルに以下を追加:

```ruby
add_column :financial_values, :period_months, :integer, default: nil
add_column :financial_values, :irregular_period, :boolean, default: false
```

### 期間月数の算出ロジック

FinancialValue にメソッドを追加:

```ruby
class FinancialValue < ApplicationRecord
  # FinancialReport の period_start / period_end から期間月数を算出
  def compute_period_months
    report = financial_report
    return nil unless report&.period_start && report&.period_end
    # 月数を計算（端数は四捨五入）
    months = ((report.period_end.year * 12 + report.period_end.month) -
              (report.period_start.year * 12 + report.period_start.month))
    months.clamp(1, 24)
  end

  # 変則決算期かどうかを判定（標準は12ヶ月、四半期は3ヶ月）
  def get_expected_period_months
    case period_type
    when "annual" then 12
    when "q1", "q2", "q3" then nil # 累計なので期によって異なる
    end
  end

  def irregular_period?
    return false if period_months.nil?
    expected = get_expected_period_months
    return false if expected.nil?
    period_months != expected
  end
end
```

### Import Job への統合

ImportJquantsFinancialDataJob / ImportEdinetDocumentsJob で FinancialValue 作成時に period_months を自動設定:

```ruby
# FinancialReport の period_start / period_end から算出
value.period_months = value.compute_period_months
value.irregular_period = value.irregular_period?
```

### CalculateFinancialMetricsJob での活用

- `irregular_period == true` の FinancialValue について:
  - YoY計算をスキップ（nil をセット）
  - consecutive growth カウンタについて、変則期を「中立」として扱う（カウンタをリセットしない）
  - data_json に `yoy_skipped_reason: "irregular_period"` を記録

### 既存データの補完

- rake タスクで既存の financial_values に対して period_months を一括算出・更新

## テスト方針

- FinancialValue#compute_period_months のテスト（12ヶ月、9ヶ月、6ヶ月、15ヶ月）
- FinancialValue#irregular_period? のテスト
- YoY計算スキップのテスト（CalculateFinancialMetricsJobのメソッドテスト内）

## 依存関係

- FinancialReport に period_start / period_end が存在することが前提（スキーマ確認済み）
- `fiscal_period_normalization` (PLAN) の前提データ基盤として機能する
- `metric_calculation_edge_cases` と補完的な関係

## 優先度

Phase 0相当。変則決算期のYoY誤判定は Use Case 1 の consecutive growth に直接影響するため、早期の実装が望ましい。fiscal_period_normalization (PLAN) の設計の前提としても必要。
