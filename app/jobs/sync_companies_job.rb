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
