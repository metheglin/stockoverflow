# dev_fiscal_period_continuity_verification

## 概要

各企業の決算期データの**連続性**を検証し、期の欠損を特定する仕組みを実装する。

## 背景・目的

Use Case 1（6期連続増収増益）の信頼性は、consecutive_revenue_growth / consecutive_profit_growth カウンタの正確性に依存する。このカウンタは CalculateFinancialMetricsJob で前年度データとの比較により算出されるが、**前年度データ自体が存在しない（期の欠損がある）場合、カウンタが不正確になるリスク**がある。

既存の関連TODO:
- `data_coverage_analysis` は「何年分のデータがあるか」のサマリーに焦点
- `financial_value_completeness_audit` は「フィールド単位のNULL率」に焦点
- 本TODOは「期の連続性そのもの」に焦点。例：「トヨタは2020年3月期〜2025年3月期まで6期連続でannualデータがあるべきだが、2022年3月期が欠損している」を検出する

## 実装内容

### Company モデルにメソッドを追加

```ruby
class Company < ApplicationRecord
  # 会社の決算月を推定する（最頻のfiscal_year_end月を返す）
  def estimated_fiscal_month
    # financial_values の fiscal_year_end から最頻月を特定
  end

  # 期待される決算期のリストと、実際に存在する決算期を比較し、欠損を返す
  # @return [Array<Hash>] 欠損期の情報 [{fiscal_year_end:, scope:, period_type:}]
  def get_missing_fiscal_periods(scope: :consolidated, period_type: :annual, years_back: 6)
    # 最新のfiscal_year_endから過去years_back年分の期待される決算期を生成
    # 実在するfinancial_valuesと突合し、欠損を返す
  end

  # 連続性スコアを返す（0.0〜1.0, 1.0=完全連続）
  def get_period_continuity_score(scope: :consolidated, period_type: :annual, years_back: 6)
    # 期待期数に対する実在期数の割合
  end
end
```

### DataIntegrityCheckJob への統合

- 全上場企業に対して `get_missing_fiscal_periods` を実行
- 欠損が見つかった企業をリストアップし、ApplicationProperty に記録
- 特に consecutive_revenue_growth >= 3 かつ欠損がある企業を要注意として報告（カウンタが不正確な可能性）

### FinancialMetric の信頼性フラグ

- consecutive_revenue_growth / consecutive_profit_growth の値が「データ欠損により不正確な可能性がある」場合に、data_json 内に `continuity_verified: false` を付与することを検討

## テスト方針

- Company#estimated_fiscal_month のテスト（3月決算、12月決算の判定）
- Company#get_missing_fiscal_periods のテスト（欠損なし、1期欠損、複数期欠損）
- Company#get_period_continuity_score のテスト

## 依存関係

- 既存の FinancialValue データが前提
- data_integrity_check_job への統合は DataIntegrityCheckJob の既存構造に沿う

## 優先度

Phase 0相当。Use Case 1 の信頼性に直結するため、analysis_query_layer の実装前に完了が望ましい。
