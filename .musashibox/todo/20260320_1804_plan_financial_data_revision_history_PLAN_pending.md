# 財務データ変更履歴追跡の設計

## 概要

FinancialValueやFinancialMetricのデータが更新された際の変更履歴を追跡する仕組みを設計する。修正報告、データソース間の差異、再計算による値の変動を記録し、データの信頼性を検証可能にする。

## 背景・課題

### 1. 現在のデータ更新パターン

- **EDINET修正報告**: 修正有価証券報告書（docTypeCode: 130, 170）が提出されると、同一企業・同一期のFinancialValueが上書きされる。修正前の値が消失する。
- **JQUANTS更新**: JQUANTSの決算データが遡及的に修正されることがある。`import_financial_value` のupsert処理で上書きされる。
- **クロスソース競合**: 同一のfinancial_valueに対してEDINETとJQUANTSの両方からデータが入る場合、後から取り込まれた方で上書きされる（`import_financial_value` のJSON merge戦略）。
- **指標再計算**: `CalculateFinancialMetricsJob(recalculate: true)` で全指標が再計算されるが、なぜ値が変わったのかの追跡ができない。

### 2. 変更履歴が必要なシーン

- 企業分析において「この数値は当初発表値か修正値か」を判別したい
- データ品質チェックにおいて「不自然な値の変動がないか」を検証したい
- 修正報告が出た企業を「何が修正されたか」とともに一覧したい
- 連続増収増益の判定において、修正報告による遡及的な変更の影響を把握したい

## 設計検討事項

### アプローチ案

#### 案A: 変更ログテーブル方式
- `financial_value_changes` テーブルに変更前後の値を記録
- メリット: シンプル、検索しやすい
- デメリット: ストレージ使用量が増加

```
financial_value_changes:
  financial_value_id, changed_at, source (edinet/jquants/recalculation),
  changed_columns_json (変更されたカラムとbefore/afterの値), trigger (amendment/sync/manual)
```

#### 案B: FinancialValue data_json内にメタデータ方式
- `data_json` 内に `_revision_history` キーとして変更履歴を埋め込む
- メリット: テーブル追加不要
- デメリット: JSONの肥大化、検索が困難

#### 案C: Paper Trail gem等のライブラリ活用
- 汎用的な変更追跡gemを導入
- メリット: 実装コストが低い、汎用的
- デメリット: 外部依存の追加、カスタマイズの自由度

### 検討すべき項目

1. **追跡対象の範囲**: 全カラムか、主要カラムのみか（net_sales, operating_income等の重要項目のみ）
2. **保持期間**: 永続か、一定期間後にアーカイブするか
3. **変更検知のタイミング**: ActiveRecordコールバック(before_update) vs ジョブ内での明示的なdiff比較
4. **FinancialMetric再計算時の追跡**: FVの変更に起因するメトリクスの連鎖的な変更の記録方法
5. **修正報告との紐付け**: EDINET修正報告（`improve_import_fault_tolerance` 20260319_1703 でamended記録を検討中）との統合

## 成果物

- 変更履歴追跡の詳細設計書（DEVELOP TODO）
- データモデル設計（テーブル/カラム定義）
- 追跡ロジックの実装方針

## 依存関係

- `improve_import_fault_tolerance` (20260319_1703) - EDINET修正報告の識別と関連
- `dev_cross_source_data_validation` (20260319_1603) - ソース間の差異検出と関連
- `dev_data_integrity_check` (20260310_1403) - 整合性チェックの入力情報として活用可能
