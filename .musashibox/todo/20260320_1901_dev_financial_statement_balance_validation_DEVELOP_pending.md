# 財務諸表の内部整合性検証

## 概要

FinancialValueに格納された財務データが、会計上の基本的な恒等式を満たしているかを検証する機能を
DataIntegrityCheckJobに追加する。

現在のcross_source_data_validation（EDINET vs JQUANTS間の比較）とは異なり、
単一の財務データレコード内部の論理的整合性を検証する。

## 背景・動機

- JQUANTS APIとEDINET XBRLからのデータ取り込みにおいて、パース・マッピングのバグが混入しうる
- 特にdata_jsonの拡張フィールド（cost_of_sales, gross_profit, sga_expenses等）は新しく追加されたもので、検証が不十分
- 整合性の崩れた財務データから計算されるメトリクス（ROE, ROA, マージン等）は信頼できない
- 早期にデータ品質の問題を検出し、分析の信頼性を担保する

## 検証ルール

### P/L整合性
- `gross_profit ≈ net_sales - cost_of_sales`（拡張データがある場合）
- `operating_income ≈ gross_profit - sga_expenses`（拡張データがある場合）
- `operating_income <= ordinary_income`は通常成り立つが、営業外損失が大きい場合は逆転しうるため、大きな乖離のみ警告

### B/S整合性
- `total_assets ≈ current_assets + noncurrent_assets`（拡張データがある場合）
- `total_assets ≈ (current_liabilities + noncurrent_liabilities) + net_assets`（概算）
- `equity_ratio ≈ shareholders_equity / total_assets * 100`（拡張データがある場合）

### 基本的な妥当性
- `eps ≈ net_income / shares_outstanding`（概算、自己株式考慮）
- `bps ≈ net_assets / shares_outstanding`（概算）
- 各値の符号チェック（net_salesが負でないか等）

## 実装方針

1. **FinancialValueモデルにバランス検証メソッドを追加**
   - `validate_pl_balance` → P/L整合性チェック結果を返す
   - `validate_bs_balance` → B/S整合性チェック結果を返す
   - `validate_basic_sanity` → 基本妥当性チェック結果を返す
   - 各メソッドは `{valid: bool, issues: [{field:, expected:, actual:, deviation_pct:}]}` 形式で返す

2. **許容誤差の設定**
   - 四捨五入や表示単位の違いによる誤差を許容するため、閾値を設定（例: 5%以内は正常）
   - 閾値は定数として定義

3. **DataIntegrityCheckJobへの統合**
   - 既存のチェック項目に追加
   - 拡張データ（data_json）が存在するレコードのみを検証対象とする

## 対象ファイル

- `app/models/financial_value.rb`
- `app/jobs/data_integrity_check_job.rb`

## テスト方針

- 正常データでのバランス検証パス
- 意図的に不整合を仕込んだデータでの検出確認
- 拡張データが欠落しているケースでのスキップ確認
