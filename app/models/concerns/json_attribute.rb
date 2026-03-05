module JsonAttribute
  extend ActiveSupport::Concern

  class_methods do
    # JSON型カラムにスキーマを定義し、各属性へのアクセサを提供する
    #
    # 使用例:
    #   define_json_attributes :data_json, schema: {
    #     variant_name: { type: :string },
    #     bytesize: { type: :integer },
    #   }
    #
    #   record.variant_name       # => "thumbnail"
    #   record.variant_name = "x" # => セッターも利用可能
    #
    def define_json_attributes(column_name, schema:)
      class_attribute :"#{column_name}_schema", default: schema

      # SQLite stores JSON as text, so the column value may be a String.
      # This helper normalizes it to a Hash.
      define_method(:"parse_#{column_name}") do
        raw = send(column_name)
        case raw
        when Hash then raw
        when String then JSON.parse(raw)
        else {}
        end
      end
      private :"parse_#{column_name}"

      schema.each_key do |attr_name|
        define_method(attr_name) do
          send(:"parse_#{column_name}")[attr_name.to_s]
        end

        define_method(:"#{attr_name}=") do |value|
          json = send(:"parse_#{column_name}")
          json[attr_name.to_s] = value
          send(:"#{column_name}=", json)
        end
      end
    end
  end
end
