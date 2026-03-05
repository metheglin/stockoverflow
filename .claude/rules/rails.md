## Railsの設計・コーディング規則

### ディレクトリ構成とレイヤー設計

app/
├── controllers/
├── models/            # ActiveRecordクラスのほか、Entity, Value Objectの役割となるクラスをここに配置する
├── lib/               # 本ビジネスのロジックに依存せずに分離できる機能・場合によってはgemに切り出しも想定できる機能を配置する。APIクライアント・汎用性の高い機能など
├── jobs/              # 何らかのアクションをおこなう処理または単に非常に複雑な処理、非同期処理にするかにかかわらず一般的に言うServiceクラスをここに配置してよい
└── serializers/       # APIレスポンスの整形

### クラスの記述順序を統一する

```ruby
class User < ApplicationRecord
  # 記述順序を統一する
  # 1. includes / extends
  # 2. 定数
  # 3. enum
  # 4. associations
  # 5. validations
  # 6. callbacks
  # 7. scopes
  # 8. class methods
  # 9. instance methods

  ROLES = %w[member admin].freeze

  enum :role, { member: 0, admin: 1 }

  has_many :posts

  validates :name, presence: true

  scope :active, -> { where(deactivated_at: nil) }

  def self.generate_user_code
    SecureRandom.hex(8)
  end

  def full_name
    "#{first_name} #{last_name}"
  end
end
```

### ActiveRecord enum

- レコードの種別を表現するデータは、enumの利用を積極的に検討し、それに伴いカラムの型をintegerとして検討すること
- enum定義によって利用可能となるscopeも積極的に利用すること

### ActiveRecord scope

`scope` の実装判断

- このアプリケーションが解決する問題にとって重要なクエリと判断できるものは `scope` に定義し、そうでないものは定義せず都度呼び出し側で組み立てする
  - Ex: 「直近更新された100件の報告書を更新時間順に取得する」 → ページングのための100件limitであればその件数はこのビジネスに関係がないため、scope不要
  - Ex: 「直近7日間以内に更新された報告書を取得する」 → 7日という数字が業務サイクルを表しており、報告書業務に重要である場合、積極的にscopeに切り出す
- 重要だと判断されるクエリのうち、**非常に複雑なものに限って**QueryObjectクラスに切り出すことを検討する。QueryObjectだとわかるよう `Query` suffixをクラス名に付与する

`default_scope` の利用方針

- DBテーブルを直接表現したActiveRecordクラスには `default_scope` を定義しないこと
  - ただし、STIや元のテーブルクラスを継承して新たなデータ集合を表現したい場合は躊躇なく `default_scope` を駆使すること

```ruby
class Article < ApplicationRecord
  enum :kind, {
    recommend: 1,
    news: 2,
    static_page: 3,
  }
end

class RecommendArticle < Article
  default_scope ->{recommend}

  def summarize_content
    # ...
  end
end
```

### データベースJSON型の活用

将来的に大いにスキーマを拡張することが想定される場合、JSON型のDBカラムの利用を積極的に検討すること。
ただし、「そのデータをつかって検索することが重要でない場合」のみJSONデータとして保持する。

#### JSONの型指定

- JSONの型を指定し適用できるライブラリの導入・実装を検討すること
- JSONで定義した属性に、他のカラムと同様に読み書きできるインターフェースを想定すること

例:

```ruby
class Blob < ApplicationRecord
  include JsonAttribute

  define_json_attributes :metadata, schema: {
    variant_name: {type: :string},
    identifier: {type: :string},
    bytesize: {type: :integer},
  }
end

blob = Blob.find(1)
blob.bytesize
```

#### EAV(Entity-Attribute-Value) + JSON型 パターン

- WordPressの`wp_postmeta`に代表されるように、あるリソースのデータを柔軟に拡張できるEAVパターンの利用を検討すること
- EAVのテーブルでは基本的なカラムに加えて、5つのカラムを保持する
  - `{resource}_id` 拡張したい元のリソースのid
  - `kind` データの種別。必ずInteger型とし、ActiveRecord Enumで管理。
  - `primary_value` 必ず文字列・NULL許容・必ず`kind`と組み合わせてDB Index付与する。検索に必要なためDB Indexを活用したいデータのためのカラム
  - `data_json` 必ずJSON型。スキーマを適用し、自由なデータを管理できるようにする
  - `status` ON/OFFを可能にするためのカラム。デフォルトはON

■典型的な利用例:

- 組織アカウントについて、多数の新機能や契約プランが想定されるケース
- 次のようにDBを設計し、以下のように利用する
  - `organizations` 組織アカウントテーブル
  - `organization_properties` organizationsのEAVテーブル
    - カラム: `organization_id`, `kind`, `primary_value`, `status`, `data_json`
- `primary_value` を利用するときは `alias_attribute` を定義し、データに名前をつけることを検討すること

```ruby
class Organization::Property < ApplicationRecord
  include JsonAttribute

  belongs_to :organization

  enum :status, {
    disabled: 0,
    enabled: 1,
  }
  enum :kind, {
    access_control: 1,
    etax_connect: 2,
  }
end

class Organization::Property::EtaxConnect < Organization::Property
  default_scope -> {where(kind: :etax_connect)}

  alias_attribute :etax_subject_id, :primary_value

  schema :data_json, columns: {
    id_token_jwt: { type: :string },
    city_code: { type: :string },
  }

  validates :etax_subject_id, presence: true, uniqueness: {scope: :kind, case_sensitive: true}
end
```

■アンチパターン:

以下のケースではEAVパターンの利用をやめ、素直に専用のテーブルを作成すること。

- そのリソースにとって不可欠の情報で、DBレベルの厳格なチェックやバリデーション、DB Index活用が必要と思われるもの
- リソースにひもづくデータが多いもの

#### アプリケーション全体にかかわるメタデータをあつかうテーブルの利用

- プログラムから読み書きする必要のある「アプリケーション全体のメタデータ」を管理できる専用のテーブルを1つ用意する
- `application_properties`
    - `kind` 必ずInteger・必ずユニーク・ActiveRecord Enum管理。デフォルト値 `default` と決めておく
    - `data_json`
- ただ1つだけのレコードが入るテーブルとしてつかってもいいが、`kind`によって種別を設け、自由に増やせるよう設計しておく

■典型的な利用例:

- 最後に連携した実行時間の保持など
- 重要な外部データのキャッシュの保持など
- 保存場所に困ったデータ

