# bugfix: EDINET訂正報告書の重複登録防止

## 概要

ImportEdinetDocumentsJob において、EDINET訂正報告書（docTypeCode 130, 150, 170）を通常の報告書と同様に新規レコードとして登録しているため、同一企業・同一期間に対して重複した FinancialReport / FinancialValue が作成されるリスクがある。

## 背景

EDINET docTypeCode の対応関係:
- `120` 有価証券報告書 → `130` 訂正有価証券報告書
- `140` 四半期報告書 → `150` 訂正四半期報告書
- `160` 半期報告書 → `170` 訂正半期報告書

現在の `EdinetApi::TARGET_DOC_TYPE_CODES = %w[120 130 140 150 160 170]` は訂正報告書も取り込み対象としているが、`ImportEdinetDocumentsJob#process_document` は訂正かどうかを区別せず新規の FinancialReport を作成しようとする。

## 問題の影響

1. 同一企業・同一期間の FinancialReport が重複し、ユニーク制約違反エラーまたはデータ不整合が発生する
2. 訂正報告書に含まれる修正後の数値が反映されず、訂正前の古いデータが使われ続ける
3. FinancialMetric の計算結果が不正確になる

## 修正方針

1. `process_document` で docTypeCode が 130/150/170 の場合、訂正対象の既存 FinancialReport を検索する
2. 既存レコードが見つかった場合は、FinancialValue の値を訂正後の値で上書き（UPDATE）する
3. 見つからない場合は通常通り新規作成する（訂正対象が未取り込みのケース）
4. 訂正であったことを data_json に記録する（amended: true, original_doc_id など）

## 関連ファイル

- `app/jobs/import_edinet_documents_job.rb`
- `app/lib/edinet_api.rb` （TARGET_DOC_TYPE_CODES）
- `app/models/financial_report.rb`
- `app/models/financial_value.rb`
