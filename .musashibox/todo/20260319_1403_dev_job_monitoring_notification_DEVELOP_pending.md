# DEVELOP: ジョブ実行監視・通知機能

## 背景

CLAUDE.mdの「なるべく最新の情報に追従し」という目的において、データ同期ジョブの失敗や遅延を早期に検知する仕組みが存在しない。

現在の各ジョブは以下の状態:
- `SyncCompaniesJob`, `ImportJquantsFinancialDataJob`, `ImportEdinetDocumentsJob`, `ImportDailyQuotesJob`, `CalculateFinancialMetricsJob` が実装済み
- 各ジョブは `Rails.logger` にログを出力しているが、失敗時の通知は一切ない
- `DataIntegrityCheckJob` がデータ整合性を検証し `application_properties` に結果を保存しているが、問題検知時の通知がない
- `ApplicationProperty` の `get_sync_staleness` は同期の鮮度を判定できるが、判定結果を通知する手段がない

ジョブスケジューリング（`dev_job_scheduling`）が実装されると日次で自動実行が始まるため、失敗を検知する仕組みが不可欠になる。

## 実装内容

### 1. ジョブ実行結果の記録

`application_properties` の `data_json` を活用し、各ジョブの実行結果を構造的に記録する。

```ruby
# ApplicationProperty (kind: :job_monitoring) の data_json 構造
{
  "last_runs": {
    "SyncCompaniesJob": {
      "started_at": "2026-03-19T07:00:00+09:00",
      "finished_at": "2026-03-19T07:02:30+09:00",
      "status": "success",     # success | failure | partial
      "summary": "Synced 3842 companies, 0 unlisted",
      "error_message": null
    },
    "ImportJquantsFinancialDataJob": { ... },
    ...
  }
}
```

### 2. ApplicationProperty に kind 追加

```ruby
enum :kind, {
  default: 0,
  edinet_sync: 1,
  jquants_sync: 2,
  data_integrity: 3,
  job_monitoring: 4,  # 追加
}
```

### 3. ジョブ共通のモニタリングモジュール

```ruby
# app/models/concerns/job_monitorable.rb
module JobMonitorable
  extend ActiveSupport::Concern

  private

  def record_job_result(status:, summary:, error_message: nil)
    prop = ApplicationProperty.find_or_create_by!(kind: :job_monitoring)
    runs = prop.data_json&.dig("last_runs") || {}
    runs[self.class.name] = {
      "started_at" => @job_started_at&.iso8601,
      "finished_at" => Time.current.iso8601,
      "status" => status,
      "summary" => summary,
      "error_message" => error_message,
    }
    prop.update!(data_json: (prop.data_json || {}).merge("last_runs" => runs))
  end
end
```

### 4. 各既存ジョブへの組み込み

各ジョブの `perform` メソッドの最後に `record_job_result` を呼び出す。既存のログ出力ロジックを活用して summary を構築する。rescueブロックで失敗も記録する。

### 5. ヘルスチェックエンドポイントの拡張

現在 `/up` はRails標準のヘルスチェックのみ。ジョブの実行状況を返すエンドポイントを追加する。

```ruby
# config/routes.rb
get "/health/jobs", to: "health#jobs"
```

```ruby
# app/controllers/health_controller.rb
class HealthController < ApplicationController
  skip_before_action :verify_authenticity_token

  def jobs
    prop = ApplicationProperty.find_by(kind: :job_monitoring)
    if prop&.data_json&.dig("last_runs").present?
      render json: prop.data_json["last_runs"]
    else
      render json: { status: "no_data" }
    end
  end
end
```

これにより、外部監視ツール（UptimeRobot等）やcurlによる簡易監視が可能になる。

## テスト

- `JobMonitorable#record_job_result`: ApplicationPropertyに正しく記録されること（DBアクセスが発生するがモジュールの単体テストとして記述）
- `HealthController`: テスティング規約に従いコントローラーテストは記述しない

## 成果物

- `app/models/concerns/job_monitorable.rb` - ジョブ監視モジュール
- 既存ジョブ6ファイルへのモジュール組み込み
- `app/controllers/health_controller.rb` - ジョブ状態エンドポイント
- `config/routes.rb` - ルーティング追加
- `spec/models/concerns/job_monitorable_spec.rb` - テスト
