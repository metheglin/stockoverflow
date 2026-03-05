require "rails_helper"

RSpec.describe JsonAttribute do
  let(:test_class) do
    Class.new do
      include ActiveModel::Model
      include ActiveModel::Attributes
      include JsonAttribute

      attribute :data_json

      define_json_attributes :data_json, schema: {
        name: { type: :string },
        count: { type: :integer },
      }
    end
  end

  describe "getter" do
    it "returns the value from the JSON column" do
      instance = test_class.new(data_json: { "name" => "test", "count" => 42 })

      expect(instance.name).to eq("test")
      expect(instance.count).to eq(42)
    end

    it "returns nil when the JSON column is nil" do
      instance = test_class.new(data_json: nil)

      expect(instance.name).to be_nil
      expect(instance.count).to be_nil
    end

    it "returns nil for a key not present in the JSON" do
      instance = test_class.new(data_json: { "name" => "test" })

      expect(instance.count).to be_nil
    end
  end

  describe "setter" do
    it "sets the value in the JSON column" do
      instance = test_class.new(data_json: nil)

      instance.name = "hello"
      expect(instance.data_json).to eq({ "name" => "hello" })
      expect(instance.name).to eq("hello")
    end

    it "preserves existing values when setting a new key" do
      instance = test_class.new(data_json: { "name" => "existing" })

      instance.count = 10
      expect(instance.data_json).to eq({ "name" => "existing", "count" => 10 })
    end

    it "overwrites an existing value" do
      instance = test_class.new(data_json: { "name" => "old" })

      instance.name = "new"
      expect(instance.name).to eq("new")
    end
  end

  describe "String JSON column" do
    it "parses a string JSON value for getter" do
      instance = test_class.new(data_json: '{"name":"from_string","count":99}')

      expect(instance.name).to eq("from_string")
      expect(instance.count).to eq(99)
    end

    it "parses a string JSON value for setter" do
      instance = test_class.new(data_json: '{"name":"original"}')

      instance.count = 5
      expect(instance.count).to eq(5)
      expect(instance.name).to eq("original")
    end
  end

  describe "class_attribute schema" do
    it "stores the schema definition as a class attribute" do
      schema = test_class.data_json_schema

      expect(schema).to eq({
        name: { type: :string },
        count: { type: :integer },
      })
    end
  end
end
