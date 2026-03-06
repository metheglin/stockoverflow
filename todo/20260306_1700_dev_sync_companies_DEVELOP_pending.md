# 企業マスター同期ジョブ実装

## 概要

JQUANTS の上場銘柄一覧APIから企業マスター（`companies` テーブル）を同期するジョブを実装する。
`app/jobs/sync_companies_job.rb` に配置する。

## 前提知識

### JQUANTS 上場銘柄一覧 `/v2/equities/master`

`JquantsApi#load_listed_info` で取得可能。全銘柄を一括取得できる。

V2レスポンスフィールドと companies カラムの対応:

| V2フィールド | 説明 | companies カラム |
|-------------|------|-----------------|
| `Code` | 証券コード（5桁） | `securities_code` |
| `CoName` | 企業名（日本語） | `name` |
| `CoNameEn` | 企業名（英語） | `name_english` |
| `S17` | 17業種コード | `sector_17_code` |
| `S17Nm` | 17業種名 | `sector_17_name` |
| `S33` | 33業種コード | `sector_33_code` |
| `S33Nm` | 33業種名 | `sector_33_name` |
| `ScaleCat` | TOPIXスケール区分 | `scale_category` |
| `Mkt` | 市場コード | `market_code` |
| `MktNm` | 市場名 | `market_name` |
| `Mrgn` | 信用区分コード | `data_json` |
| `MrgnNm` | 信用区分名 | `data_json` |

### EDINETコードとの紐づけ

EDINETコードは EDINET 書類一覧APIのレスポンスに含まれる `edinetCode` と `secCode`（証券コード）を使って紐づける。
企業マスター同期ジョブでは JQUANTS から `securities_code` ベースで企業を作成し、
EDINETコードの設定は決算データ取り込みジョブ（`ImportEdinetDocumentsJob`）で EDINET 書類を処理する際におこなう。

### 実行頻度・運用

- **実行頻度**: 週次（上場銘柄の変動は頻繁ではない）
- **更新方式**: 全件取得 → upsert（`securities_code` をキーにした差分更新）
- **上場廃止の扱い**: JQUANTS一覧に存在しない既存企業は `listed: false` に更新
- **最終実行時刻**: `application_properties` (kind: `jquants_sync`) の `last_synced_at` に記録

### エラーハンドリング

- API呼び出し失敗時はFaradayの例外をそのまま伝播（ジョブ全体をリトライ）
- 個別企業のDB保存失敗時はログに記録して次の企業へ継続（エラーハンドリング規約準拠）

---

## 実装タスク

### タスク1: Company モデルへのフィールドマッピング定数追加

#### ファイル: `app/models/company.rb`

JQUANTSレスポンスフィールド → companiesカラムの対応マッピングを定数として定義する。

```ruby
class Company < ApplicationRecord
  # JQUANTS V2 listed info → companies カラム マッピング
  JQUANTS_FIELD_MAP = {
    "Code"      => :securities_code,
    "CoName"    => :name,
    "CoNameEn"  => :name_english,
    "S17"       => :sector_17_code,
    "S17Nm"     => :sector_17_name,
    "S33"       => :sector_33_code,
    "S33Nm"     => :sector_33_name,
    "ScaleCat"  => :scale_category,
    "Mkt"       => :market_code,
    "MktNm"     => :market_name,
  }.freeze

  # JQUANTS V2 listed info のうち data_json に格納するフィールド
  JQUANTS_DATA_JSON_FIELDS = %w[Mrgn MrgnNm].freeze

  has_many :financial_reports, dependent: :destroy
  has_many :financial_values, dependent: :destroy
  has_many :financial_metrics, dependent: :destroy
  has_many :daily_quotes, dependent: :destroy

  scope :listed, -> { where(listed: true) }

  # JQUANTS V2 listed info のレスポンスデータから属性Hashを生成する
  #
  # @param data [Hash] JQUANTSレスポンスの1銘柄分のHash
  # @return [Hash] Company.create / update に渡せる属性Hash
  #
  # 例:
  #   attrs = Company.get_attributes_from_jquants(jquants_data)
  #   # => { securities_code: "86970", name: "日本取引所グループ", ... }
  #
  def self.get_attributes_from_jquants(data)
    attrs = {}
    JQUANTS_FIELD_MAP.each do |jquants_key, column|
      attrs[column] = data[jquants_key] if data.key?(jquants_key)
    end

    # data_json に格納するフィールド
    json_data = {}
    JQUANTS_DATA_JSON_FIELDS.each do |key|
      json_data[key.underscore] = data[key] if data.key?(key)
    end
    attrs[:data_json] = json_data if json_data.any?
    attrs[:listed] = true

    attrs
  end
end
```

### タスク2: SyncCompaniesJob の実装

#### ファイル: `app/jobs/sync_companies_job.rb`

```ruby
class SyncCompaniesJob < ApplicationJob
  # 企業マスターをJQUANTSの上場銘柄一覧から同期する
  #
  # 処理フロー:
  # 1. JQUANTS APIから上場銘柄一覧を全件取得
  # 2. 各銘柄について securities_code でupsert
  # 3. JQUANTS一覧に存在しない既存上場企業を listed: false に更新
  # 4. application_properties に最終同期時刻を記録
  #
  # @param api_key [String, nil] JQUANTSのAPIキー。nilの場合はcredentialsから取得
  #
  def perform(api_key: nil)
    client = api_key ? JquantsApi.new(api_key: api_key) : JquantsApi.default
    listed_data = client.load_listed_info

    synced_codes = []
    error_count = 0

    listed_data.each do |data|
      code = data["Code"]
      next if code.blank?

      begin
        attrs = Company.get_attributes_from_jquants(data)
        company = Company.find_or_initialize_by(securities_code: code)
        company.assign_attributes(attrs)
        company.save! if company.changed?
        synced_codes << code
      rescue => e
        error_count += 1
        Rails.logger.error("[SyncCompaniesJob] Failed to sync company #{code}: #{e.message}")
      end
    end

    # JQUANTS一覧に存在しない上場企業を非上場に更新
    mark_unlisted(synced_codes)

    # 最終同期時刻を記録
    record_sync_time

    Rails.logger.info(
      "[SyncCompaniesJob] Completed: #{synced_codes.size} synced, #{error_count} errors"
    )
  end

  # JQUANTS一覧に含まれなかった上場企業を listed: false に更新する
  #
  # @param synced_codes [Array<String>] 同期された証券コードの配列
  def mark_unlisted(synced_codes)
    return if synced_codes.empty?

    Company.listed
      .where.not(securities_code: synced_codes)
      .where.not(securities_code: nil)
      .update_all(listed: false)
  end

  # application_properties に最終同期時刻を記録する
  def record_sync_time
    prop = ApplicationProperty.find_or_create_by!(kind: :jquants_sync)
    prop.last_synced_at = Time.current.iso8601
    prop.save!
  end
end
```

### タスク3: テスト

#### ファイル: `spec/models/company_spec.rb`

```ruby
RSpec.describe Company do
  describe ".get_attributes_from_jquants" do
    let(:jquants_data) do
      {
        "Date" => "2024-01-15",
        "Code" => "86970",
        "CoName" => "日本取引所グループ",
        "CoNameEn" => "Japan Exchange Group,Inc.",
        "S17" => "16",
        "S17Nm" => "金融（除く銀行）",
        "S33" => "7200",
        "S33Nm" => "その他金融業",
        "ScaleCat" => "TOPIX Large70",
        "Mkt" => "0111",
        "MktNm" => "プライム",
        "Mrgn" => "1",
        "MrgnNm" => "貸借",
      }
    end

    it "JQUANTSレスポンスからCompany属性Hashを生成できる" do
      attrs = Company.get_attributes_from_jquants(jquants_data)

      expect(attrs[:securities_code]).to eq("86970")
      expect(attrs[:name]).to eq("日本取引所グループ")
      expect(attrs[:name_english]).to eq("Japan Exchange Group,Inc.")
      expect(attrs[:sector_17_code]).to eq("16")
      expect(attrs[:sector_17_name]).to eq("金融（除く銀行）")
      expect(attrs[:sector_33_code]).to eq("7200")
      expect(attrs[:sector_33_name]).to eq("その他金融業")
      expect(attrs[:scale_category]).to eq("TOPIX Large70")
      expect(attrs[:market_code]).to eq("0111")
      expect(attrs[:market_name]).to eq("プライム")
      expect(attrs[:listed]).to eq(true)
    end

    it "data_jsonフィールドが正しく設定される" do
      attrs = Company.get_attributes_from_jquants(jquants_data)

      expect(attrs[:data_json]).to include("mrgn" => "1", "mrgn_nm" => "貸借")
    end

    it "キーが存在しない場合はスキップされる" do
      attrs = Company.get_attributes_from_jquants({ "Code" => "12340", "CoName" => "テスト" })

      expect(attrs[:securities_code]).to eq("12340")
      expect(attrs[:name]).to eq("テスト")
      expect(attrs).not_to have_key(:name_english)
    end
  end
end
```

#### ファイル: `spec/jobs/sync_companies_job_spec.rb`

テスティング規約に従い、ジョブの稼働テストは記述しない。
`Company.get_attributes_from_jquants` のテストは `spec/models/company_spec.rb` に記述する。
`mark_unlisted` と `record_sync_time` は公開メソッドとしてテスト可能だが、
DB操作を伴うためモデルテストの範囲を超える。必要に応じて後から追加する。

---

## 実装順序

1. `app/models/company.rb` に定数とクラスメソッドを追加
2. `app/jobs/sync_companies_job.rb` を新規作成
3. `spec/models/company_spec.rb` を新規作成・テスト実行
