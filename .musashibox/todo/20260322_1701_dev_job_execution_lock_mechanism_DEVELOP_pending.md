# DEVELOP: ジョブ排他ロック機構の実装

## 概要

同一種別のジョブが同時に実行されることを防止する排他ロック機構を実装する。ApplicationProperty を活用したアドバイザリーロックにより、データ競合やリソースの無駄遣いを防止する。

## 背景・動機

### 現状の問題

現在のジョブ実装には同時実行を防止する機構が存在しない。以下のシナリオでデータ競合が発生しうる:

1. **手動実行とスケジュール実行の衝突**: `ImportJquantsFinancialDataJob` をRails consoleから手動実行中に、cronやSolid Queueからスケジュール実行がトリガーされた場合
2. **data_json マージの競合**: 2つの `ImportEdinetDocumentsJob` インスタンスが同一企業の同一 FinancialValue の `data_json` を同時に更新すると、一方の変更が失われる（last-write-wins）
3. **sync マーカーの不整合**: 2つの同一ジョブが `ApplicationProperty` の `last_synced_date` を異なるタイミングで更新し、一部の日付がスキップされる
4. **API レート制限の二重消費**: 同一ジョブが並行実行されると、API呼び出し回数が倍増しレート制限に抵触するリスクが高まる

### 既存TODOとの関係

- `dev_full_pipeline_orchestration` (20260321_1101): パイプライン内のステップ順序は制御するが、同一ジョブの並行実行は防止しない
- `dev_job_scheduling` (20260310_1402): スケジューリングの設計であり、排他制御は含まない
- `dev_import_metric_cascade_automation` (20260320_1900): カスケードトリガーのタイミング制御であり、排他制御は含まない

## 実装方針

### ApplicationProperty ベースのアドバイザリーロック

DBレベルのロックではなく、ApplicationProperty の data_json にロック情報を記録するソフトロック方式を採用する。

#### ApplicationProperty に新しい kind を追加

```ruby
class ApplicationProperty < ApplicationRecord
  enum :kind, {
    default: 0,
    edinet_sync: 1,
    jquants_sync: 2,
    data_integrity: 3,
    job_locks: 4,  # 追加
  }
end
```

#### ロック/アンロック機構

```ruby
module JobLock
  extend ActiveSupport::Concern

  class AlreadyRunningError < StandardError; end

  included do
    around_perform :with_execution_lock
  end

  private

  def with_execution_lock
    lock_key = self.class.name
    acquired = acquire_lock(lock_key)

    unless acquired
      Rails.logger.warn("[#{lock_key}] Skipped: another instance is already running")
      return
    end

    begin
      yield
    ensure
      release_lock(lock_key)
    end
  end

  def acquire_lock(lock_key)
    prop = ApplicationProperty.find_or_create_by!(kind: :job_locks)
    locks = prop.data_json || {}

    if locks[lock_key].present?
      started_at = Time.parse(locks[lock_key]["started_at"]) rescue nil
      # 古いロック（2時間以上）は自動解放
      if started_at && started_at < 2.hours.ago
        Rails.logger.warn("[#{lock_key}] Stale lock detected (started_at: #{started_at}), forcing release")
      else
        return false
      end
    end

    locks[lock_key] = { "started_at" => Time.current.iso8601, "pid" => Process.pid }
    prop.update!(data_json: locks)
    true
  end

  def release_lock(lock_key)
    prop = ApplicationProperty.find_by(kind: :job_locks)
    return unless prop

    locks = prop.data_json || {}
    locks.delete(lock_key)
    prop.update!(data_json: locks)
  end
end
```

#### 各ジョブへの適用

```ruby
class SyncCompaniesJob < ApplicationJob
  include JobLock
  # ...
end
```

### 注意事項

- **スタイルロック解放**: プロセスがクラッシュした場合にロックが残留するため、タイムアウト（2時間）による自動解放を実装
- **SQLite の ACID 保証**: `update!` はトランザクション内で実行されるため、同時アクセス時のデータ整合性は SQLite のファイルロックで保証される
- **テスト実行への影響**: テスト環境ではロックを無効化する設定を用意する

## テスト

`spec/models/concerns/job_lock_spec.rb` または `spec/lib/job_lock_spec.rb`:

- ロック未取得時にacquire_lockがtrueを返すこと
- ロック取得済み時にacquire_lockがfalseを返すこと
- release_lock後にacquire_lockが再度trueを返すこと
- スタイルロック（2時間超）が自動解放されること

## 対象ファイル

- `app/models/concerns/job_lock.rb`（新規）
- `app/models/application_property.rb`（kind追加）
- `app/jobs/sync_companies_job.rb`
- `app/jobs/import_jquants_financial_data_job.rb`
- `app/jobs/import_edinet_documents_job.rb`
- `app/jobs/import_daily_quotes_job.rb`
- `app/jobs/calculate_financial_metrics_job.rb`

## 優先度

中。`dev_full_pipeline_orchestration` や `dev_job_scheduling` を実装する前に、個別ジョブレベルの安全性を確保しておくことが望ましい。

## 依存関係

- なし（独立して実装可能）
