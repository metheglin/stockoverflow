# FinancialValueのフィールド別データソース追跡

## 概要

FinancialValueレコードはJQUANTSとEDINETの両方からデータが投入・補完されるが、
どのフィールドがどのソースから提供されたかを追跡する手段がない。
EDINET XBRLパーサーのバグ修正やJQUANTSのデータ仕様変更があった場合に、
影響範囲を特定できず、データの信頼性を担保できない。

## 背景

- `ImportJquantsFinancialDataJob`: 主要財務数値をJQUANTSから取得しFinancialValueを作成
- `ImportEdinetDocumentsJob`: 既存FinancialValueのdata_jsonをEDINETデータで補完、または新規作成
- 現在の補完ロジック（ImportEdinetDocumentsJob）:
  - 既存レコードがあればdata_jsonのみマージ
  - 既存レコードがなければEDINET由来で新規作成
- 問題:
  - EDINET由来で新規作成されたレコードのコアカラム（net_sales等）がEDINET由来であることが判別不能
  - `dev_xbrl_unit_scale_verification` で単位問題が発見された場合、影響レコードの特定が困難
  - `dev_cross_source_data_validation` でソース間の不一致を検証する際、どちらが「正」か判断する材料がない

## 作業内容

### 1. FinancialValueのdata_jsonにソースメタデータを追加

data_json内に `_source_metadata` キーを追加し、フィールドごとのソース情報を記録する。

```json
{
  "cost_of_sales": 50000000,
  "gross_profit": 30000000,
  "_source_metadata": {
    "core_fields_source": "jquants",
    "data_json_sources": {
      "cost_of_sales": "edinet",
      "gross_profit": "edinet",
      "forecast_net_sales": "jquants"
    },
    "last_jquants_import_at": "2026-03-20T10:00:00Z",
    "last_edinet_import_at": "2026-03-21T14:30:00Z"
  }
}
```

### 2. ImportJquantsFinancialDataJobの改修

- FinancialValue作成/更新時に `_source_metadata.core_fields_source = "jquants"` を記録
- data_jsonの各フィールドについてソースを記録
- `last_jquants_import_at` を更新

### 3. ImportEdinetDocumentsJobの改修

- data_json補完時に各フィールドのソースを `"edinet"` として記録
- 新規作成時に `core_fields_source = "edinet"` を記録
- `last_edinet_import_at` を更新

### 4. FinancialValueモデルへのヘルパー追加

```ruby
# コアフィールドのソースを返す
def core_fields_source
  data_json&.dig("_source_metadata", "core_fields_source")
end

# 指定フィールドのソースを返す
def get_field_source(field_name)
  data_json&.dig("_source_metadata", "data_json_sources", field_name.to_s) ||
    core_fields_source
end
```

### 5. テスト

- FinancialValueのソースメタデータ関連ヘルパーのテスト
- ソースメタデータが正しく記録されることの検証（Jobのヘルパーメソッドレベルで）

## 対象ファイル

- `app/models/financial_value.rb`
- `app/jobs/import_jquants_financial_data_job.rb`
- `app/jobs/import_edinet_documents_job.rb`
- `spec/models/financial_value_spec.rb`

## 優先度

中 - データの追跡可能性（traceability）に直結。`dev_xbrl_unit_scale_verification` や `dev_cross_source_data_validation` との連携で効果を発揮
