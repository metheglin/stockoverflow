# DEVELOP: インポートジョブの構造化結果サマリ

## 概要

全インポート・同期ジョブが実行結果の構造化サマリを返すようにし、何が起きたかを明確に把握できるようにする。

## 背景・動機

現在のインポートジョブは `Rails.logger` にログを出力するのみで、以下の情報が体系的に取得できない:

- 何件のレコードが作成/更新/スキップされたか
- エラーが何件発生し、どの企業で発生したか
- 処理にどれだけの時間がかかったか
- 前回実行時と比べてデータ量がどう変化したか

この情報がないと、以下の問題が生じる:
- インポートが正常に完了したのか、部分的に失敗しているのか判断できない
- パイプラインオーケストレーション（20260321_1101）で各ステップの成否を判断する材料がない
- データの鮮度や網羅性を確認する手段がない

## 実装方針

### 結果サマリのデータ構造

```ruby
# 各ジョブが共通で返す結果サマリ
{
  job_name: "ImportJquantsFinancialDataJob",
  started_at: Time,
  finished_at: Time,
  duration_seconds: Float,
  status: :success | :partial_failure | :failure,
  counts: {
    created: Integer,
    updated: Integer,
    skipped: Integer,
    errors: Integer,
  },
  errors: [
    { company_id: Integer, securities_code: String, message: String },
  ],
  summary_message: String,  # 人間が読めるサマリ文
}
```

### 実装アプローチ

1. **ImportResultクラスの作成**
   - `app/models/import_result.rb` にValue Objectとして配置
   - カウンタのインクリメント、エラー追加、サマリ生成のメソッドを提供
   - Immutableではなく、ジョブ処理中に状態を蓄積する設計（効率性重視）

2. **既存ジョブの修正**
   - 各ジョブの `perform` メソッド内で `ImportResult` インスタンスを生成
   - 処理の各ポイントでカウンタをインクリメント
   - 完了時に `ImportResult` を返却
   - 既存のログ出力は維持しつつ、サマリ出力を追加

3. **結果の保存**
   - ApplicationProperty の data_json に最新の実行結果を保存
   - 過去の実行履歴は保持しない（ログで十分）

### 対象ジョブ

- SyncCompaniesJob
- ImportDailyQuotesJob
- ImportJquantsFinancialDataJob
- ImportEdinetDocumentsJob
- CalculateFinancialMetricsJob

## テスト

- ImportResult クラスのメソッドテスト（カウンタ操作、サマリ生成）
- 各ジョブ内の結果記録ロジックは、ジョブを実行せずテスト可能なようにモデルメソッドとして切り出すことを検討
