# 企業の上場ステータス履歴管理

## 概要

現在、`SyncCompaniesJob`は企業の上場廃止を`listed`カラムのbooleanフリップのみで処理しており、いつ上場/上場廃止になったかの履歴が残らない。
歴史的分析（特にユースケース3「飛躍直前の変化を調べる」）では、企業が上場していた期間を正確に把握する必要がある。
また、スクリーニングにおいて上場廃止企業の除外/包含を柔軟に制御する基盤が必要。

## 背景

- `SyncCompaniesJob`はJQUANTSの上場企業一覧にない企業を `listed=false` に更新するのみ
- 上場廃止日、上場日、上場廃止理由（合併・破綻等）が記録されない
- companiesテーブルには `listed` (boolean) のみで、時系列的な情報がない
- 再上場のケースも考慮が必要

## 作業内容

### 1. companiesテーブルへのカラム追加

- `listed_at` (date, nullable): 上場日（初期値として既存の上場企業には推定値を設定）
- `delisted_at` (date, nullable): 上場廃止日

### 2. SyncCompaniesJobの改修

- `listed=true` → `listed=false` に変更する際に `delisted_at` を記録する
- 新たに上場企業一覧に出現した企業について `listed_at` を記録する
- 再上場のケース: `delisted_at` をクリアし `listed_at` を更新

### 3. Companyモデルへのヘルパー追加

- `delisted?` メソッド: `delisted_at.present?`
- `listing_duration` メソッド: 上場期間を返す
- `listed_during?(date)` メソッド: 指定日時点で上場していたか判定

### 4. テスト

- Companyモデルの新メソッドのテスト
- SyncCompaniesJobのステータス変更ロジック（既にヘルパーメソッドとしてテスト可能な設計になっているか確認）

## 対象ファイル

- `db/migrate/` (新規マイグレーション)
- `app/models/company.rb`
- `app/jobs/sync_companies_job.rb`
- `spec/models/company_spec.rb`

## 優先度

中 - 歴史的分析の精度向上。スクリーニング結果の信頼性に影響
