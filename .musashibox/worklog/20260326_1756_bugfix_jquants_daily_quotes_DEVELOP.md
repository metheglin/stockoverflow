# Bugfix: JQUANTS Daily Quotes Subscription Range Error

**Date:** 2026-03-26 09:22 UTC

## Overview

ImportDailyQuotesJobがJQuants APIのサブスクリプション範囲外のデータを取得しようとした際に発生する400エラーを修正した。

## Problem

- JQuants Freeプランでは過去2年分のデータのみ利用可能（例: 2024-01-01 ~ 2026-01-01）
- `import_full`モードのデフォルト開始日が`20200101`のため、サブスクリプション範囲外のリクエストが全銘柄で発生
- `import_incremental`モードでも、最終同期日が範囲外の場合に同様のエラーが発生
- エラーが発生してもrescueで無視され、全銘柄に対して繰り返し同じエラーが発生し続けていた

## Solution

### 1. JquantsApi: SubscriptionRangeError の追加 (`app/lib/jquants_api.rb`)

- `JquantsApi::SubscriptionRangeError` カスタム例外クラスを追加
  - `available_from`, `available_to` 属性でサブスクリプションの利用可能期間を保持
- APIの400レスポンスbodyからサブスクリプション範囲メッセージを正規表現で検出
- 検出された場合は `Faraday::BadRequestError` の代わりに `SubscriptionRangeError` を発生させる
- サブスクリプション範囲メッセージでない400エラーはそのまま `Faraday::BadRequestError` として伝播

### 2. ImportDailyQuotesJob: 日付範囲クランプと中断機構 (`app/jobs/import_daily_quotes_job.rb`)

**Full mode (`import_full`):**
- `SubscriptionRangeError` 発生時に `clamp_date_range` で from/to を利用可能範囲にクランプ
- クランプ後に自動 retry し、以降の銘柄は修正済みの日付範囲で取得

**Incremental mode (`import_incremental`):**
- `SubscriptionRangeError` 発生時に `@subscription_range` を記録
- 以降のイテレーションでサブスクリプション範囲外の日付を自動スキップ

**中断機構 (`handle_subscription_error!`):**
- サブスクリプションエラーの発生回数をカウント
- `MAX_SUBSCRIPTION_ERRORS`(3回)を超えた場合、例外を発生させてジョブを中断

### 3. Tests (`spec/lib/jquants_api_spec.rb`)

- サブスクリプション範囲メッセージを含む400レスポンスで `SubscriptionRangeError` が発生することを確認
- `available_from`, `available_to` が正しくパースされることを確認
- 通常の400エラーは `Faraday::BadRequestError` のまま発生することを確認

## Test Results

- 309 examples, 0 failures, 5 pending (credentials未設定のスキップのみ)
