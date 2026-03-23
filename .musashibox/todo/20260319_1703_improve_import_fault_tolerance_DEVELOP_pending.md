# インポートジョブの耐障害性改善

## 概要

現在の各種インポートジョブにおいて、部分的な失敗時のデータ整合性と再実行時の信頼性に課題がある。sync日時の記録タイミング、上場廃止の誤判定、EDINET修正報告のハンドリングを改善する。

## 背景

現状の問題点:

1. **ImportEdinetDocumentsJob / ImportJquantsFinancialDataJob**: 処理中に一部ドキュメントが失敗しても、`ApplicationProperty.last_synced_date` が最終日として記録される。再実行時にその日付以降から開始するため、失敗したドキュメントが永久にスキップされる
2. **SyncCompaniesJob**: JQUANTSのAPI応答から企業が一時的に欠落した場合（API障害等）、即座に `listed: false` にマークされ、以降のデータ取得対象から外れる
3. **ImportEdinetDocumentsJob**: EDINET修正報告（docTypeCode: 130, 170）が通常報告と同じ処理フローで取り込まれるが、修正であることがFinancialValueに記録されず、データの由来・信頼性が追跡できない

## 実装内容

### 1. sync日時の精緻化

- 各インポートジョブで `@failed_dates` を追跡し、失敗が発生した日付を記録する
- `ApplicationProperty.data_json` に `failed_dates` 配列として保存
- 次回実行時に `failed_dates` を再処理対象に含める
- 全件成功した場合のみ `failed_dates` をクリアする

### 2. 上場廃止の猶予期間

- SyncCompaniesJobで企業がAPI応答に含まれない場合、即座に `listed: false` にせず、`data_json` に `missing_since: Date.today` を記録
- 3回連続（3日間）の同期で欠落が続いた場合にのみ `listed: false` に変更
- `missing_since` が設定済みだが、再びAPIに出現した場合は `missing_since` をクリア

### 3. EDINET修正報告の識別

- FinancialReportに `amended` カラム（boolean, default: false）を追加するか、既存の `doc_type_code` を活用
- ImportEdinetDocumentsJobで docTypeCode 130, 170 のドキュメントを処理する際:
  - 同一企業・同一fiscal_year_end・同一report_typeの既存FinancialReportを探す
  - 既存レポートがあれば、FinancialValueの更新前に変更内容をログに記録
  - FinancialReport.data_json に `{ amended: true, original_doc_id: "..." }` を保存

## テスト

- ジョブの実行テストは記述しない（テスティング規約に従う）
- モデルに追加されるメソッドがあればテスト対象

## 依存関係

- なし（既存ジョブの改善）
