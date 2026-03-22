# DEVELOP: ApplicationProperty 初期レコード作成機構の整備

## 概要

`db/seeds.rb` に ApplicationProperty の全 kind に対する初期レコード作成処理を実装し、新規環境セットアップ時にジョブが正常に動作する状態を保証する。

## 背景・動機

### 現状の問題

各ジョブは `ApplicationProperty` の特定の kind レコードを参照・更新する:

- `SyncCompaniesJob`: `jquants_sync` の `last_synced_at` を更新
- `ImportEdinetDocumentsJob`: `edinet_sync` の `last_synced_date` を参照して増分起点を決定
- `ImportJquantsFinancialDataJob`: `jquants_sync` の `last_synced_date` を参照
- `ImportDailyQuotesJob`: `jquants_sync` の `last_synced_date` を参照
- `DataIntegrityCheckJob`: `data_integrity` に結果を記録、各syncの鮮度を参照

これらのレコードが存在しない新規環境では:

1. `find_by(kind: :edinet_sync)` が nil を返し、増分インポートの起点が未定義になる
2. `ApplicationProperty.get_sync_staleness` の呼び出しで `last_synced_date` が nil になり予期しない動作が起きる
3. ジョブの初回実行時に `find_or_create_by` で暗黙的にレコードが作成される箇所と、`find_by` で nil が返る箇所が混在し、動作が不統一

### 既存TODOとの関係

- `dev_development_seed_data` (20260321_1401): テスト用のサンプル企業・財務データのシード。ApplicationProperty の初期化とは異なる関心事
- `dev_full_pipeline_orchestration` (20260321_1101): パイプライン実行前提として ApplicationProperty の存在を暗黙に仮定している

## 実装内容

### 1. db/seeds.rb への追加

```ruby
# ApplicationProperty 初期レコード
ApplicationProperty::kinds.each_key do |kind_name|
  ApplicationProperty.find_or_create_by!(kind: kind_name) do |prop|
    prop.data_json = {}
    Rails.logger.info("[seeds] Created ApplicationProperty: #{kind_name}")
  end
end
```

### 2. ジョブ内の nil 安全性確認

各ジョブで `ApplicationProperty.find_by(kind: ...)` を呼び出している箇所を洗い出し、レコードが存在しない場合のフォールバック動作を明確にする:

- `find_by` が nil を返す場合: `find_or_create_by` に統一するか、明示的な nil チェックを追加
- `last_synced_date` が nil の場合: 増分インポートを「全件インポート」として動作させるか、エラーにするかの方針を統一

### 3. Rake タスクでの初期化

```ruby
# lib/tasks/setup.rake
namespace :setup do
  desc "Initialize application properties for all job types"
  task application_properties: :environment do
    ApplicationProperty::kinds.each_key do |kind_name|
      ApplicationProperty.find_or_create_by!(kind: kind_name) do |prop|
        prop.data_json = {}
        puts "Created ApplicationProperty: #{kind_name}"
      end
    end
    puts "Done. #{ApplicationProperty.count} application properties exist."
  end
end
```

## テスト

- モデルメソッドのテストのみ（テスティング規約に従う）
- ApplicationProperty に追加のメソッドがある場合はそのテスト
- seeds.rb の動作確認は手動で実施

## 対象ファイル

- `db/seeds.rb`
- `lib/tasks/setup.rake`（新規）
- `app/jobs/` 以下の各ジョブ（nil 安全性の確認・修正）

## 優先度

中。新規環境セットアップの安定性に影響する。`dev_full_pipeline_orchestration` の前提条件。

## 依存関係

- なし（独立して実装可能）
- `dev_rake_operations_tasks` (20260320_0902) と同時に実施すると効率的
