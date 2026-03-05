# コーディング規約

## 基本方針

- 1インデント 2スペース
- マジックナンバーを避け、定数または enum を使う
- 既存コードのスタイルに合わせる。規約と既存コードが矛盾する場合は既存コードに従い、別途リファクタリングを提案する

## 全般の命名規則

- **略語をなるべく避ける**: `usr` → `user`, `cnt` → `count`
	- ただしコード内のローカルスコープにおいて長い単語が何度も現れることが想定されるとき、略語を検討
		- Ex: `advertisement_title` => `ad_title`
		- Ex: `admin_party_property_destination` => `adparty_prop_dest`
- **日時**: `_at` サフィックスを付ける（`published_at`, `deleted_at`）
- **コレクション**: 複数形にする（`users`, `items`）。単複同型の場合は `data_list` のように `_list` suffixを付ける
- **Boolean 変数・カラム**: `is_` プレフィックスを避ける。`active`, `published`, `visible` のように形容詞にする


## クラス設計の基本

### Immutability

- 大半のシンプルな責務のクラスにおいては、属性が実質immutableとみなせるよう設計すること
- 属性の外部読み出しが必要な場合 `attr_reader` のみを許可し、`attr_accessor`, `attr_writer`を不用意に許可せず、初期化時に渡された値が変更されない設計をとること
- ただし大きなデータを扱う場合や、複雑で困難な責務を扱う場合は効率性を重視し、このルールを放棄すること

### 汎用性と利便性

- 大半のシンプルな責務のクラスにおいては、以下に示すように汎用性と利便性が両立するよう設計すること
- 変数となりうるデータをハードコードせず、初期化時に引数で指定できるようにして動作を変更できるようにする
	- ただし、それによってよびだしが面倒になるため、必要に応じて便利メソッドをクラスメソッドとして追加することを検討する

良くない例:

```ruby
class ExampleApi
	def initialize
		api_key = Rails.credentials.config.example_api.api_key
		@client = SimpleClient.new(default_headers: {"Authorization" => "Bearer #{api_key}"})
	end

	def get_posts
		@client.get('/posts')
	end
end
```

修正例:

```ruby
class ExampleApi
	# api_keyを変更してよびだししたくなるときは多々想定できる。
	# その際わざわざcredentialsのキーを変更しデプロイしなければ動作確認できないという状況を避け、
	# 引数のキーを変更するだけで確認できる道筋を残しておく。
	# 一方で、いつも決まったAPIキーをつかう環境のために便利メソッドを提供しておく。

	class << self
		def get(**args)
			new(api_key: Rails.credentials.config.example_api.api_key, **args)
		end
	end

	def initialize(api_key:)
		@client = SimpleClient.new(default_headers: {"Authorization" => "Bearer #{api_key}"})
	end

	def get_posts
		@client.get('/posts')
	end
end
```

### メソッドの設計と命名規則

以下に示すように目的が明確なメソッド定義を心がけること。このようなメソッドをprivateで非公開にする必要はない。躊躇なく公開し、テストしやすいことを重視すること。

#### 「状態」を表すメソッド

- Booleanで示される値は形容詞系に `?` suffixを付与

```ruby
def active?
	# true | false
end
```

- 状態の種類を返す場合は状態名を表す名詞とする

```ruby
def publish_status
	# "open"|"closed"
end

def activeness
	# "active"|"inactive"|"banned"
end
```

#### 「計算された属性」を表すメソッド

- そのクラスが保持する属性値をフィルタや改変して使う必要がある場合は、メソッド名を「形容詞+名詞」としてどのような改変がなされたどの属性なのかを暗示すること
	- Immutableとして設計されたクラスであり、かつ後述する「引数に応じて変化する属性」でない限りにおいて、原則このメソッドはメモ化しても良い

```ruby
def valid_items
	@valid_items ||= @items.select(&:valid?)
end

# どのような改変を意図しているかメソッドコメントにてサンプルを含んだドキュメントが記載されるべき
def scored_items
	@scored_items ||= valid_items.map do |item|
		{
			item: item,
			score: get_score(item),
		}
	end.sort{|item| item.score}
end
```

#### 「引数」に応じて変化する「計算された属性」を表すメソッド

- `get_` prefixを付与し、都度計算され直す必要があることを暗示する
- 絶対にメモ化しないこと

```ruby
def get_score(item)
	item.title.length / valid_items.map{|i| i.title.length}.sum
end
```


#### 値を読み出してデータを返す役割であり、かつその読み出し処理がファイルopen・API呼び出し・SQL呼び出し・JSON parseなどの処理を伴うメソッド

- `load_` prefixを付与し、読み出しが発生することを暗示する
- そのメソッド呼び出しが何度も発生し、都度読み出すコストが非効率と思われるとき、内部で `load_xxx` を呼び出してメモ化をおこなう `load_` prefixを省略した属性名のように扱えるメソッドの追加を検討すること
	- ただし、`load_xxx`メソッドが引数を受ける場合、メモ化メソッドを絶対に使わないこと
	- 上記の理由から、`load_xxx`メソッドではなるべく引数を受けない方法を検討すること

```ruby
def load_services
	JSON.parse(File.read(SERVICE_LIST_PATH))
end

def services
	@services ||= load_services
end
```

悪い例

```ruby
def load_items(category)
	Item.where(category_id: category.id)
end

# 非常に危険なバグ。このようなメソッドを絶対に定義しないこと
def items(category)
	@items ||= load_items(category)
end
```

このようにどうしても引数が必要とされる場合は、以下のようにload機能を別個のクラスとして切り出し、引数を排除することを検討すること。

修正例

```ruby
class ItemLoader
	def initialize(category)
		@category = category
	end

	def load
		Item.where(category_id: @category.id)
	end

	def items
		@items ||= load
	end
end
```

#### 何らかのアクションをおこなうメソッド

- 必ずそのアクションを代表する動詞からメソッド名を始めること
	- Ex: ``
- このメソッドが複雑な実装を要する場合、Serviceクラスに切り出すことを検討すること。その際クラスの命名規則を 元のクラス名::動詞から始まる処理名
	- Ex: ``
- 前述の「引数」に応じて変化する「計算された属性」について、複雑な処理となる場合このケースとみなしてよい


## エラーハンドリングの基本

- 無闇に例外を捕捉しないこと。特にモデル層では、例外が出ても放置し、呼び出し側で捕捉の判断ができるように設計すること。
- よびだし側でも全ての例外の捕捉（`rescue => e`）をなるべく避けること。ただし以下の条件では許容できる場合もあるため、ログに記録するという前提で全捕捉を検討すること。
	- ある重要な処理の一部に失敗しても別に致命的でない処理が混在するとき
		- Ex: 重要な決済処理の中に、安定性の高くないAPIを通じた成果通知コールが発生する。このAPIの失敗によって決済を失敗させることが問題だと考えられる
	- 連続した繰り返し処理において、ささいな問題で中断してしまうことに大きな問題があるとき
		- Ex: 数百・数千の商品を滞りなく取り込む必要のあるバッチ処理において、1つの問題によって後続処理が停止してしまうことが問題だと考えられる
