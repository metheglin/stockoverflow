# データインポートの冪等性検証と強化

## 概要

全インポートジョブ（SyncCompaniesJob, ImportJquantsFinancialDataJob, ImportEdinetDocumentsJob,
ImportDailyQuotesJob）が冪等に動作することを検証し、問題があれば修正する。

## 背景・動機

- インポートジョブはfind_or_initialize_byパターンでupsertしているが、以下のエッジケースで冪等性が崩れる可能性がある:
  - **data_jsonのマージ**: ImportEdinetDocumentsJobがJQUANTS由来のfinancial_valuesのdata_jsonを補完する際、
    2回実行すると既存の拡張データが上書きされるリスク
  - **修正報告書の処理**: EDINETの修正報告書（doc_type_code 130等）を2回インポートした場合の挙動
  - **JQUANTS期間指定の重複**: incrementalモードで同じ日付範囲を2回実行した場合、
    financial_reportsが重複生成されないか
  - **企業の上場廃止と復活**: SyncCompaniesJobで一度unlistedにした企業が再びリストに現れた場合
- ジョブの再実行はエラーリカバリの基本手段であり、安全に再実行できることはシステムの信頼性の根幹

## 検証項目

### SyncCompaniesJob
- [ ] 同じデータで2回実行しても企業レコードが重複しない
- [ ] 企業のsecurities_codeが変わらない限り、既存レコードが正しく更新される
- [ ] listed -> unlisted -> listed の状態遷移が正しく処理される

### ImportJquantsFinancialDataJob
- [ ] 同じ期間を2回インポートしてもfinancial_reportsが重複しない
- [ ] financial_valuesの値が最新のインポートで正しく上書きされる
- [ ] data_jsonの既存フィールドがインポートで消失しない
- [ ] incrementalモードとfullモードで結果が一致する

### ImportEdinetDocumentsJob
- [ ] 同じ日のドキュメントを2回インポートしてもレコードが重複しない
- [ ] data_jsonの補完処理が2回実行されても、値が変わらない（冪等なマージ）
- [ ] 修正報告書がオリジナル報告書のデータを正しく上書きする
- [ ] XBRLパースが同じZIPに対して同一結果を返す

### ImportDailyQuotesJob
- [ ] 同じ日付のクオートを2回インポートしてもレコードが重複しない
- [ ] 株価修正（AdjustmentFactor変更）後の再インポートで値が正しく更新される

## 実装方針

1. **冪等性テストの追加**
   - 各ジョブのRSpecに「2回実行テスト」を追加（モック使用）
   - 2回目の実行後にレコード数が変わらないことを検証
   - data_jsonの内容が2回目の実行後も正しいことを検証

2. **問題箇所の修正**
   - data_jsonマージロジックの見直し: `merge` ではなく `reverse_merge` や条件付きマージを検討
   - 修正報告書の識別と既存データの上書きロジック確認
   - find_or_initialize_by のキー項目の網羅性確認

3. **ドキュメント化**
   - 各ジョブの冪等性保証の範囲をコメントとして記載

## 対象ファイル

- `app/jobs/sync_companies_job.rb`
- `app/jobs/import_jquants_financial_data_job.rb`
- `app/jobs/import_edinet_documents_job.rb`
- `app/jobs/import_daily_quotes_job.rb`
- `spec/jobs/` 配下のテストファイル

## テスト方針

- 各ジョブに対して「同一データ2回実行」のテストケースを追加
- data_jsonの内容比較を含む
- ジョブの実際のAPI呼び出しはモックし、DB操作の冪等性に集中
