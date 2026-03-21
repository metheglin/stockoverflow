# DEVELOP: 本番環境デプロイメント構成のセットアップ

## 概要

本システムを安定的に運用するためのデプロイメント構成を整備する。Kamalを用いたデプロイ設定、SQLiteデータの永続化、定期ジョブのスケジューリング、環境変数・認証情報の管理を行う。

## 背景・動機

- 本プロジェクトはデータ収集・分析パイプラインを定期的に実行する運用が前提だが、本番環境のデプロイメント構成が未整備
- GemfileにはKamal（デプロイツール）とThruster（HTTPプロキシ）が含まれているが、設定ファイルが未構成
- SQLiteは単一ファイルDBのため、コンテナ環境でのデータ永続化戦略が不可欠
- Solid Queueによる定期ジョブ実行の設定が必要
- EDINET/JQUANTSのAPIキーをproduction credentialsで安全に管理する必要がある

## 実装内容

### 1. Kamalデプロイ設定

`config/deploy.yml` の設定:

- サービス名、Dockerイメージ名
- デプロイ先サーバーの定義
- ヘルスチェック設定
- 環境変数の定義（SECRET_KEY_BASE等）
- ボリュームマウント: SQLiteデータベースファイルの永続化

### 2. SQLiteデータ永続化

- `db/` ディレクトリをDockerボリュームとしてマウント
- production用のdatabase.yml設定でデータベースパスを環境変数で指定可能にする
- SQLite PRAGMA設定（WALモード等）をproduction向けに最適化
  - `PRAGMA journal_mode = WAL`
  - `PRAGMA synchronous = NORMAL`
  - `PRAGMA busy_timeout = 5000`

### 3. Solid Queue 定期ジョブ設定

`config/recurring.yml` にパイプラインの定期実行を設定:

```yaml
production:
  daily_pipeline:
    class: PipelineOrchestrationJob
    args: [{ mode: :daily }]
    schedule: "0 6 * * *"  # 毎朝6時（日本時間）
```

※ PipelineOrchestrationJob（20260321_1101）の実装に依存するが、設定枠だけ先に用意しておく

### 4. Dockerfile の確認・調整

- マルチステージビルドの確認
- SQLiteの開発ライブラリが含まれていること
- タイムゾーン設定（Asia/Tokyo）
- 不要な開発依存を除外

### 5. 認証情報の管理

- `config/credentials/production.yml.enc` にEDINET/JQUANTSのAPIキーを格納
- master.keyの管理方針（環境変数 or Kamal secrets）

### 6. 運用スクリプト

`script/` ディレクトリに以下を用意:

- `script/backup_db.sh` - SQLiteデータベースのバックアップ（`.backup` コマンド利用）
- `script/restore_db.sh` - バックアップからのリストア

## テスト

- Dockerfile のビルドが成功すること（`docker build` の実行確認）
- production環境でのdatabase.yml設定が正しくSQLiteを指すこと
- テスティング規約に従い、デプロイ関連のテストは記述しない

## 依存関係

- `dev_full_pipeline_orchestration`（20260321_1101）- 定期ジョブの対象ジョブ
- `plan_sqlite_backup_restore_strategy`（20260320_1802）- バックアップ戦略の設計
- `improve_sqlite_query_performance`（20260319_1605）- SQLite PRAGMA設定と一部重複。先にPRAGMA設定を統一的に管理する仕組みを検討

## 注意事項

- SQLiteのファイルロックにより、同時に複数のコンテナからの書き込みはできない。Webサーバーとジョブワーカーを同一コンテナで実行するか、WALモードで読み取り並行性を確保するかを検討
- Kamalのデプロイ時にDBマイグレーションが自動実行されるよう設定
