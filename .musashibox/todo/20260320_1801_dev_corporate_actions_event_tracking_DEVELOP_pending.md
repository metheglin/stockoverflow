# コーポレートアクション・イベント履歴追跡

## 概要

企業の重要なイベント（株式分割・併合、社名変更、上場・上場廃止、決算期変更など）を追跡するための仕組みを実装する。歴史的データの正確性を担保し、時系列分析の信頼性を向上させる。

## 背景

- 現在、Companyモデルの `listed` カラムは現在の上場状態のみを保持し、いつ上場廃止されたか（またはいつ上場したか）の履歴がない
- DailyQuoteの `adjustment_factor` に株式分割情報が含まれるが、分割イベントとして明示的に記録されていない
- SyncCompaniesJobが `mark_unlisted` で上場廃止を検知した際、イベントとして記録する仕組みがない
- 企業の社名変更は現在のCompanyレコードが上書きされるだけで、旧社名が消失する
- これらの情報は、飛躍前パターン分析(`dev_pre_breakthrough_pattern_analysis`)やライフサイクル追跡(`dev_company_lifecycle_tracking`)の精度に直接影響する

## 実装内容

### 1. CompanyモデルのEAVパターン活用

CLAUDE.mdの rails.md に記載のEAV+JSONパターンを適用し、company_propertiesテーブルを活用する。

```ruby
# company_propertiesテーブル（EAVパターン）
create_table :company_properties do |t|
  t.references :company, null: false, foreign_key: true
  t.integer :kind, null: false, default: 0
  t.string :primary_value
  t.integer :status, null: false, default: 1
  t.json :data_json
  t.timestamps
end

add_index :company_properties, [:company_id, :kind]
add_index :company_properties, [:kind, :primary_value]
```

### 2. Company::Propertyモデルと継承クラス

```ruby
class Company::Property < ApplicationRecord
  belongs_to :company

  enum :status, { disabled: 0, enabled: 1 }
  enum :kind, {
    stock_split: 1,
    name_change: 2,
    listing_change: 3,
    fiscal_year_change: 4,
    merger: 5,
  }
end
```

各イベント種別ごとの継承クラス例:

```ruby
class Company::Property::StockSplit < Company::Property
  default_scope -> { stock_split }
  alias_attribute :effective_date, :primary_value

  # data_json: { split_ratio: "1:2", adjustment_factor: 0.5 }
end

class Company::Property::NameChange < Company::Property
  default_scope -> { name_change }
  alias_attribute :changed_on, :primary_value

  # data_json: { old_name: "旧社名", new_name: "新社名" }
end

class Company::Property::ListingChange < Company::Property
  default_scope -> { listing_change }
  alias_attribute :changed_on, :primary_value

  # data_json: { action: "delisted"|"listed"|"market_transfer", market_code: "..." }
end
```

### 3. SyncCompaniesJobの拡張

- 企業がAPI応答から消えた際に `Company::Property::ListingChange` レコードを作成
- 企業名が変更された際に `Company::Property::NameChange` レコードを作成
- DailyQuoteのadjustment_factorが変化した際に `Company::Property::StockSplit` を作成（ImportDailyQuotesJobで検出）

### 4. Companyモデルへのassociation追加

```ruby
has_many :properties, class_name: "Company::Property", dependent: :destroy
```

## テスト

- Company::Property各継承クラスの基本動作テスト
- SyncCompaniesJobに追加されるイベント記録ロジックのテスト（モデルメソッドとして切り出す場合）

## 依存関係

- `plan_pre_breakthrough_pattern_analysis` (20260320_1404) - 飛躍前のイベント分析に活用
- `dev_company_lifecycle_tracking` (20260319_1702) - ライフサイクルイベントの情報源
- `plan_fiscal_period_normalization` (20260320_0904) - 決算期変更イベントの検出に活用
