# インポートジョブのリアルタイム進捗追跡

## 概要

長時間実行されるインポートジョブ（特にフルインポート）の進捗状況をリアルタイムで確認できる仕組みを実装する。

## 背景

- `ImportJquantsFinancialDataJob(full: true)` は約4,000社の財務データを個別にAPIから取得するため、数時間〜数日かかる可能性がある
- `ImportDailyQuotesJob(full: true)` も同様に長時間を要する
- 現在のジョブは完了時に `@stats` をログ出力するのみで、実行中の進捗を知る手段がない
- 「あと何社残っているか」「いま何%完了しているか」を知りたいという運用上のニーズがある
- 既存の `dev_job_monitoring_notification` (20260319_1403) はジョブ完了後の結果記録に特化しており、実行中の進捗追跡とは異なる

## 実装内容

### 1. ApplicationPropertyを活用した進捗記録

`ApplicationProperty` のEAVパターンを活用し、各ジョブの進捗を `data_json` に逐次記録する。

```ruby
# ApplicationProperty (kind: :job_monitoring) の data_json に進捗を追記
# 既存の "last_runs" と並列に "active_runs" キーを追加
{
  "active_runs": {
    "ImportJquantsFinancialDataJob": {
      "started_at": "2026-03-20T07:00:00+09:00",
      "total": 3842,
      "processed": 1520,
      "errors": 3,
      "current_item": "7203（トヨタ自動車）",
      "updated_at": "2026-03-20T08:30:00+09:00"
    }
  }
}
```

### 2. ProgressTrackerモジュール

```ruby
# app/models/concerns/progress_trackable.rb
module ProgressTrackable
  extend ActiveSupport::Concern

  private

  def init_progress(total:)
    @progress = { total: total, processed: 0, errors: 0, started_at: Time.current }
    save_progress
  end

  def increment_progress(current_item: nil)
    @progress[:processed] += 1
    @progress[:current_item] = current_item
    # 更新頻度を制限（10件ごと or 30秒ごと）
    save_progress if should_save_progress?
  end

  def increment_error
    @progress[:errors] += 1
  end

  def finalize_progress
    save_progress
    clear_active_run
  end
end
```

### 3. 進捗確認用rakeタスク

```ruby
# lib/tasks/stockoverflow.rake
namespace :stockoverflow do
  desc "Show active job progress"
  task progress: :environment do
    prop = ApplicationProperty.find_by(kind: :job_monitoring)
    active = prop&.data_json&.dig("active_runs")
    if active.present?
      active.each do |job_name, progress|
        pct = (progress["processed"].to_f / progress["total"] * 100).round(1)
        puts "#{job_name}: #{progress['processed']}/#{progress['total']} (#{pct}%) - #{progress['current_item']}"
      end
    else
      puts "No active jobs"
    end
  end
end
```

### 4. 既存ジョブへの組み込み

以下のジョブにProgressTrackableを組み込む:
- `ImportJquantsFinancialDataJob` (full: trueモード)
- `ImportDailyQuotesJob` (full: trueモード)
- `ImportEdinetDocumentsJob`
- `CalculateFinancialMetricsJob`

## テスト

- ProgressTrackableモジュールの `init_progress`, `increment_progress` メソッドのテスト
- ジョブの稼働テストは記述しない

## 注意事項

- 進捗書き込みの頻度を制御し、DBへの書き込み負荷を抑える（10件処理ごと or 30秒間隔）
- ジョブ異常終了時に `active_runs` が残り続ける問題の対処（起動時にstale checkを実施）

## 依存関係

- `dev_job_monitoring_notification` (20260319_1403) - 同じApplicationProperty (kind: :job_monitoring) を利用。data_json構造の整合性を保つ
- `dev_rake_operations_tasks` (20260320_0902) - rakeタスクの配置先と整合
