# DEVELOP: 増分インポートのギャップ検出・自動補完

## 概要

増分（incremental）インポートにおいて、ジョブの失敗・ダウンタイム・API障害等により取り込みが行われなかった日付範囲を検出し、自動的にバックフィルする仕組みを実装する。

## 背景・動機

- 各インポートジョブ（ImportDailyQuotesJob, ImportJquantsFinancialDataJob, ImportEdinetDocumentsJob）は増分モードで `last_synced_date` 以降のデータを取り込むが、以下の問題がある:
  - ジョブが中途で失敗した場合、`last_synced_date` は更新されないため次回再取得されるが、途中までインポートされたデータは重複回避の対象にはなるものの、失敗した日のデータが確実に取り込まれた保証がない
  - サーバーダウンタイムや設定ミスで数日間ジョブが実行されなかった場合、`last_synced_date` から現在日までまとめて取り込むが、その中間にAPI側でデータが一時的に利用不可だった日がスキップされる可能性がある
  - EDINET APIは日付単位でドキュメントを返すが、特定日にAPI障害があった場合、その日のドキュメントが取りこぼされる

- 既存の `improve_import_fault_tolerance`（20260319_1703）は1レコード単位のエラー耐性であり、日付単位のギャップ検出とは異なる
- 既存の `dev_import_progress_tracking`（20260320_1803）はリアルタイム進捗の可視化であり、事後的なギャップ検出とは異なる

## 実装内容

### 1. インポートギャップの検出メソッド

各モデルに対してデータが存在すべき日付範囲と実際のデータ存在日を比較する。

#### DailyQuote のギャップ検出

```ruby
class DailyQuote < ApplicationRecord
  # 指定期間内で株価データが欠落している営業日を検出する
  # @param from [Date] 検出開始日
  # @param to [Date] 検出終了日（デフォルト: 前営業日）
  # @return [Array<Date>] データが欠落している営業日のリスト
  def self.detect_missing_dates(from:, to: Date.yesterday)
    # 土日祝を除いた営業日リストと、実際にデータが存在する日を比較
    # 祝日判定は簡易的に土日のみ除外で開始し、将来的に祝日マスタを検討
  end
end
```

#### FinancialReport / FinancialValue のギャップ検出

- EDINET: 日付単位でAPIを呼び出しているため、呼び出し済み日付と全営業日の差分を検出
- JQUANTS: 日付指定での取得時、レスポンスが空だった日を記録し、後日再確認

### 2. ギャップ記録

`ApplicationProperty` (kind: :import_gaps) にギャップ情報を記録:

```ruby
{
  "daily_quotes": {
    "missing_dates": ["2026-03-15", "2026-03-16"],
    "detected_at": "2026-03-21T10:00:00+09:00"
  },
  "edinet_documents": {
    "missing_dates": ["2026-03-10"],
    "detected_at": "2026-03-21T10:00:00+09:00"
  }
}
```

### 3. ギャップ補完ジョブ

検出されたギャップに対して再インポートを実行するrakeタスク:

```
rake import:fill_gaps
# 検出済みのmissing_datesに対して各インポートジョブを日付指定で再実行
# 補完成功した日付はmissing_datesから除去
```

### 4. 定期検出

DataIntegrityCheckJob にギャップ検出ステップを追加し、定期的にギャップを検出・記録する。

## テスト

- `DailyQuote.detect_missing_dates` のテスト
  - 全日データ存在 → 空配列を返す
  - 特定日が欠落 → その日付を返す
  - 土日はスキップされること
- ギャップ補完ロジックのメソッドテスト

## 依存関係

- 各インポートジョブが日付指定での部分実行に対応していること（現在の実装を確認する必要あり）
- `improve_data_integrity_check`（20260310_1403）- ギャップ検出を統合
- `dev_full_pipeline_orchestration`（20260321_1101）- ギャップ補完の実行タイミング

## 注意事項

- 営業日判定について、日本の祝日は最初は土日のみの簡易判定で開始し、必要に応じて祝日マスタを追加
- API障害による一時的なデータ不在と、本当にデータが存在しない日（IPO前、上場廃止後）を区別する必要がある
- ギャップ補完のAPI呼び出しがクォータを圧迫しないよう、補完上限を設定する
