# improve: EDINET大量提出日のドキュメント取りこぼし防止

## 概要

EdinetApi の `load_documents` は日付指定でドキュメント一覧を取得するが、EDINET APIのレスポンスに上限があり、3月末・6月末など大量の有価証券報告書が提出される日にドキュメントが取りこぼされるリスクがある。

## 背景

- EDINET API v2 の `/documents.json` は1リクエストで返却されるドキュメント数に上限がある
- 3月期決算企業の有価証券報告書提出期限は6月末であり、特に6月最終営業日は数百件の提出が集中する
- 同様に3月末（第3四半期報告書集中日）、5月中旬（決算短信集中日）も大量提出が発生する
- 現在の `load_documents` はレスポンスをそのまま返しており、ページネーションやオーバーフロー検知が存在しない

## 問題の影響

1. 大量提出日にドキュメントが取りこぼされ、一部企業の有価証券報告書がインポートされない
2. DataIntegrityCheckJob では「missing metrics」は検知できるが「FinancialReport自体が取り込まれていない」ことは検知できない
3. 取りこぼしはサイレントに発生するため、データの欠損に気づかない

## 修正方針

1. `EdinetApi#load_documents` のレスポンスに含まれる metadata (count フィールド等) を確認し、取得件数と申告件数に差異がある場合にログ出力する
2. `ImportEdinetDocumentsJob#process_date` で取得件数を検証し、想定上限に近い場合に警告をログに記録する
3. 上限超過が検知された場合に `ApplicationProperty(kind: :data_integrity)` の data_json に記録し、DataIntegrityCheckJob のレポートに反映する
4. 将来的に、EDINET APIが提供するフィルタリングパラメータ（docTypeCode指定等）を活用して、1リクエストあたりの件数を削減する方法も検討

## 関連ファイル

- `app/lib/edinet_api.rb` （load_documents, load_target_documents）
- `app/jobs/import_edinet_documents_job.rb` （process_date）
- `app/jobs/data_integrity_check_job.rb` （新規チェック追加）
- `app/models/application_property.rb`
