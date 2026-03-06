class EdinetXbrlParser
  # 抽出対象のXBRL要素マッピング
  #
  # financial_values の固定カラムに対応するXBRL要素名を定義
  # キー: financial_values カラム名（Symbol）
  # 値: { elements: [要素名の候補配列], namespace: 名前空間 }
  #
  # 要素名の候補を配列にしているのは、企業によって使用する勘定科目が異なる場合があるため。
  # 配列の先頭から順に検索し、最初に見つかった値を採用する。
  ELEMENT_MAPPING = {
    # P/L
    net_sales: {
      elements: ["NetSales", "OperatingRevenue1", "OperatingRevenue2", "Revenue1"],
      namespace: "jppfs_cor",
    },
    operating_income: {
      elements: ["OperatingIncome", "OperatingProfit"],
      namespace: "jppfs_cor",
    },
    ordinary_income: {
      elements: ["OrdinaryIncome", "OrdinaryProfit"],
      namespace: "jppfs_cor",
    },
    net_income: {
      elements: ["ProfitLossAttributableToOwnersOfParent", "ProfitLoss", "NetIncome"],
      namespace: "jppfs_cor",
    },

    # B/S
    total_assets: {
      elements: ["Assets"],
      namespace: "jppfs_cor",
    },
    net_assets: {
      elements: ["NetAssets"],
      namespace: "jppfs_cor",
    },

    # C/F
    operating_cf: {
      elements: ["NetCashProvidedByUsedInOperatingActivities"],
      namespace: "jppfs_cor",
    },
    investing_cf: {
      elements: ["NetCashProvidedByUsedInInvestmentActivities"],
      namespace: "jppfs_cor",
    },
    financing_cf: {
      elements: ["NetCashProvidedByUsedInFinancingActivities"],
      namespace: "jppfs_cor",
    },
    cash_and_equivalents: {
      elements: ["CashAndCashEquivalentsAtEndOfPeriod", "CashAndCashEquivalents"],
      namespace: "jppfs_cor",
    },
  }.freeze

  # data_json に格納する拡張要素マッピング
  EXTENDED_ELEMENT_MAPPING = {
    cost_of_sales: {
      elements: ["CostOfSales"],
      namespace: "jppfs_cor",
    },
    gross_profit: {
      elements: ["GrossProfit"],
      namespace: "jppfs_cor",
    },
    sga_expenses: {
      elements: ["SellingGeneralAndAdministrativeExpenses"],
      namespace: "jppfs_cor",
    },
    current_assets: {
      elements: ["CurrentAssets"],
      namespace: "jppfs_cor",
    },
    noncurrent_assets: {
      elements: ["NoncurrentAssets"],
      namespace: "jppfs_cor",
    },
    current_liabilities: {
      elements: ["CurrentLiabilities"],
      namespace: "jppfs_cor",
    },
    noncurrent_liabilities: {
      elements: ["NoncurrentLiabilities"],
      namespace: "jppfs_cor",
    },
    shareholders_equity: {
      elements: ["ShareholdersEquity"],
      namespace: "jppfs_cor",
    },
  }.freeze

  # コンテキストIDのマッピング
  # XBRLでは同じ要素名でもコンテキストIDで期間（当期/前期）や連結/個別を区別する
  CONTEXT_PATTERNS = {
    consolidated_duration: /\ACurrentYearDuration\z/,
    consolidated_instant: /\ACurrentYearInstant\z/,
    non_consolidated_duration: /\ACurrentYearDuration_NonConsolidatedMember\z/,
    non_consolidated_instant: /\ACurrentYearInstant_NonConsolidatedMember\z/,
    prior_consolidated_duration: /\APrior1YearDuration\z/,
    prior_consolidated_instant: /\APrior1YearInstant\z/,
  }.freeze

  # P/L, C/F項目はduration（期間）コンテキスト、B/S項目はinstant（時点）コンテキスト
  DURATION_KEYS = %i[net_sales operating_income ordinary_income net_income
                     operating_cf investing_cf financing_cf
                     cost_of_sales gross_profit sga_expenses].freeze
  INSTANT_KEYS = %i[total_assets net_assets cash_and_equivalents
                    current_assets noncurrent_assets current_liabilities
                    noncurrent_liabilities shareholders_equity].freeze

  attr_reader :zip_path

  # @param zip_path [String] ダウンロードしたZIPファイルのパス
  def initialize(zip_path:)
    @zip_path = zip_path
  end

  # ZIPを展開しXBRLをパースして財務数値を抽出する
  #
  # @return [Hash] 抽出結果
  #   {
  #     consolidated: {
  #       net_sales: 1234567890,
  #       operating_income: 123456789,
  #       ...
  #       extended: { cost_of_sales: ..., gross_profit: ..., ... }
  #     },
  #     non_consolidated: { ... },  # 個別決算がない場合はnil
  #   }
  #
  def parse
    xbrl_content = load_xbrl_from_zip
    return nil unless xbrl_content

    doc = Nokogiri::XML(xbrl_content)
    register_namespaces(doc)

    {
      consolidated: extract_values(doc, scope: :consolidated),
      non_consolidated: extract_values(doc, scope: :non_consolidated),
    }
  end

  # ZIP内のXBRLインスタンスファイルを読み出す
  #
  # @return [String, nil] XBRLファイルの内容。見つからない場合nil
  def load_xbrl_from_zip
    Zip::File.open(zip_path) do |zip|
      entry = zip.glob("XBRL/PublicDoc/*.xbrl").first
      return entry&.get_input_stream&.read
    end
  end

  # 指定スコープ（連結/個別）の財務数値を抽出する
  #
  # @param doc [Nokogiri::XML::Document] パース済みXBRLドキュメント
  # @param scope [Symbol] :consolidated or :non_consolidated
  # @return [Hash, nil] 財務数値のHash。該当データがない場合nil
  def extract_values(doc, scope:)
    duration_context = get_context_pattern(scope, :duration)
    instant_context = get_context_pattern(scope, :instant)

    values = {}

    # 固定カラム対象の要素を抽出
    ELEMENT_MAPPING.each do |key, mapping|
      context = DURATION_KEYS.include?(key) ? duration_context : instant_context
      values[key] = find_element_value(doc, mapping, context)
    end

    # 拡張要素を抽出
    extended = {}
    EXTENDED_ELEMENT_MAPPING.each do |key, mapping|
      context = DURATION_KEYS.include?(key) ? duration_context : instant_context
      extended[key] = find_element_value(doc, mapping, context)
    end

    # 連結・個別の判定: 主要項目が1つも取得できなければnilを返す
    primary_keys = %i[net_sales operating_income total_assets]
    return nil if primary_keys.all? { |k| values[k].nil? }

    values[:extended] = extended.compact
    values.compact
  end

  # XBRL要素の値を検索して返す
  #
  # @param doc [Nokogiri::XML::Document]
  # @param mapping [Hash] { elements: [...], namespace: "..." }
  # @param context_pattern [Regexp] コンテキストIDのパターン
  # @return [Integer, nil] 抽出した数値。見つからない場合nil
  def find_element_value(doc, mapping, context_pattern)
    namespace = mapping[:namespace]
    mapping[:elements].each do |element_name|
      # 名前空間プレフィックス付きで要素を検索
      begin
        nodes = doc.xpath("//#{namespace}:#{element_name}")
      rescue Nokogiri::XML::XPath::SyntaxError
        # 名前空間が未定義の場合はスキップ
        next
      end
      nodes.each do |node|
        context_ref = node.attr("contextRef")
        next unless context_ref&.match?(context_pattern)

        text = node.text.strip
        next if text.empty?

        return parse_numeric(text)
      end
    end
    nil
  end

  private

  def register_namespaces(doc)
    # XBRLファイルに宣言された名前空間を登録
    # jppfs_cor が宣言されていない場合はデフォルトURIを設定
    unless doc.namespaces.values.any? { |ns| ns.include?("jppfs_cor") }
      doc.root&.add_namespace("jppfs_cor", "http://disclosure.edinet-fsa.go.jp/taxonomy/jppfs/cor")
    end
  end

  def get_context_pattern(scope, type)
    case [scope, type]
    when [:consolidated, :duration]
      CONTEXT_PATTERNS[:consolidated_duration]
    when [:consolidated, :instant]
      CONTEXT_PATTERNS[:consolidated_instant]
    when [:non_consolidated, :duration]
      CONTEXT_PATTERNS[:non_consolidated_duration]
    when [:non_consolidated, :instant]
      CONTEXT_PATTERNS[:non_consolidated_instant]
    end
  end

  # XBRL数値テキストをIntegerに変換する
  # XBRLでは数値はテキストで表現され、マイナスは先頭に"-"が付く
  # decimalsやunitRefも考慮が必要だが、EDINETでは基本的に単位は円
  def parse_numeric(text)
    # カンマを除去し整数変換
    cleaned = text.gsub(",", "")
    Integer(cleaned)
  rescue ArgumentError
    # 小数の場合
    Float(cleaned).to_i rescue nil
  end
end
