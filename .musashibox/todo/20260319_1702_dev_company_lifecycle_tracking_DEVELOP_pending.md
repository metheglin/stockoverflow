# 企業ライフサイクルイベント追跡の実装

## 概要

株式分割・併合、上場廃止、証券コード変更、決算期変更など、企業のライフサイクルイベントを追跡する仕組みを実装する。これらのイベントはEPS・BPSなどの株あたり指標やYoY比較に影響を与えるため、データ品質の観点で重要である。

## 背景

- 現在、SyncCompaniesJobでJQUANTSのAPIから企業情報を取得しているが、「上場廃止した時期」「株式分割が発生したか」などのイベント情報を保持していない
- 株式分割が発生した場合、過去のEPS・BPSとの単純なYoY比較が不適切になる
- JQUANTSのDailyQuoteには `adjustment_factor` が含まれており、これを活用して株式分割を検出できる
- 上場廃止はSyncCompaniesJobで `listed: false` にマークされるが、廃止時期が記録されない
- 決算期変更があると、YoY比較の対象期間がずれる

## 実装内容

### company_eventsテーブルの作成

CompanyのEAVパターンを活用し、`company_events` テーブルを作成する。

```
company_events:
  - company_id: integer (FK)
  - kind: integer (enum: stock_split, delisting, code_change, fiscal_year_change)
  - primary_value: string (イベント固有の主要値。stock_splitの場合は分割比率 "2:1" など)
  - status: integer (enum: disabled, enabled)
  - data_json: json (イベント詳細)
  - occurred_on: date (イベント発生日)
```

### 株式分割検出ロジック

- ImportDailyQuotesJobで `adjustment_factor` が前日と異なるレコードを検出した場合、CompanyEventを自動生成
- `data_json` に `{ ratio: "2:1", adjustment_factor: 2.0, detected_from: "daily_quote" }` を格納

### 上場廃止の追跡

- SyncCompaniesJobで `listed: true` → `listed: false` に変更されたとき、CompanyEventを生成
- `occurred_on` にsync日時を記録

### Companyモデルへの関連追加

- `has_many :company_events`
- `Company#stock_split_events` で株式分割イベントの一覧を取得

### FinancialMetricでの活用（将来）

- YoY計算時に、対象期間に株式分割イベントがあればEPS・BPSを調整して比較する（本TODOでは基盤のみ。調整ロジックは別途TODO）

## テスト

- CompanyEventモデルに `get_attributes_from_daily_quote_split` などの公開メソッドがあればテスト
- SyncCompaniesJobおよびImportDailyQuotesJobでのイベント検出はジョブテスト対象外（ルールに従う）

## 依存関係

- なし（新規テーブル追加のみ）
