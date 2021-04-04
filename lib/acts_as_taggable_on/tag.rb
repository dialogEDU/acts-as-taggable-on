# encoding: utf-8
module ActsAsTaggableOn
  class Tag < ::ActiveRecord::Base

    ### ASSOCIATIONS:

    has_many :taggings, dependent: :destroy, class_name: '::ActsAsTaggableOn::Tagging'
    belongs_to :account, class_name: 'Account', foreign_key: 'account_id'
    belongs_to :site, class_name: 'Site', foreign_key: 'site_id'

    ### VALIDATIONS:

    validates_presence_of :name
    validates_uniqueness_of :name, scope: 'account_id', if: :validates_name_uniqueness?
    validates_length_of :name, maximum: 255

    # monkey patch this method if don't need name uniqueness validation
    def validates_name_uniqueness?
      true
    end

    ### SCOPES:
    scope :most_used, ->(limit = 20) { order('taggings_count desc').limit(limit) }
    scope :least_used, ->(limit = 20) { order('taggings_count asc').limit(limit) }

    def self.named(name, account)
      if ActsAsTaggableOn.strict_case_match
        where(["name = #{binary}? AND account_id = ?", as_8bit_ascii(name), account.id])
      else
        where(['LOWER(name) = LOWER(?) AND account_id = ?', as_8bit_ascii(unicode_downcase(name)), account.id])
      end
    end

    def self.named_any(list, account)
      clause = list.map { |tag|
        sanitize_sql_for_named_any(tag).force_encoding('BINARY')
      }.join(' OR ')
      where(account_id: account.id).where(clause)
    end

    def self.named_like(name, account)
      clause = ["name #{ActsAsTaggableOn::Utils.like_operator} ? ESCAPE '!'", "%#{ActsAsTaggableOn::Utils.escape_like(name)}%"]
      where(account_id: account.id).where(clause)
    end

    def self.named_like_any(list, account)
      clause = list.map { |tag|
        sanitize_sql(["name #{ActsAsTaggableOn::Utils.like_operator} ? ESCAPE '!'", "%#{ActsAsTaggableOn::Utils.escape_like(tag.to_s)}%"])
      }.join(' OR ')
      where(account_id: account.id).where(clause)
    end

    def self.for_context(context)
      joins(:taggings).
        where(["taggings.context = ?", context]).
        select("DISTINCT tags.*")
    end

    ### CLASS METHODS:

    def self.find_or_create_with_like_by_name(name, account)
      if ActsAsTaggableOn.strict_case_match
        self.find_or_create_all_with_like_by_name([name]).first
      else
        named_like(name, account).first || create(name: name, account: account)
      end
    end

    def self.find_or_create_all_with_like_by_name(account, *list)
      list = Array(list).flatten

      return [] if list.empty?

      list.map do |tag_name|
        begin
          tries ||= 3

          existing_tags = named_any(list, account)
          comparable_tag_name = comparable_name(tag_name)
          existing_tag = existing_tags.find { |tag| comparable_name(tag.name) == comparable_tag_name }
          existing_tag || create(name: tag_name, account: account)
        rescue ActiveRecord::RecordNotUnique
          APM::Error.call(e, self)

          if (tries -= 1).positive?
            ActiveRecord::Base.connection.execute 'ROLLBACK'
            retry
          end

          raise DuplicateTagError.new("'#{tag_name}' has already been taken")
        end
      end
    end

    ### INSTANCE METHODS:

    def ==(object)
      super || (object.is_a?(Tag) && name == object.name)
    end

    def to_s
      name
    end

    def count
      read_attribute(:count).to_i
    end

    class << self



      private

      def comparable_name(str)
        if ActsAsTaggableOn.strict_case_match
          str
        else
          unicode_downcase(str.to_s)
        end
      end

      def binary
        ActsAsTaggableOn::Utils.using_mysql? ? 'BINARY ' : nil
      end

      def unicode_downcase(string)
        if ActiveSupport::Multibyte::Unicode.respond_to?(:downcase)
          ActiveSupport::Multibyte::Unicode.downcase(string)
        else
          ActiveSupport::Multibyte::Chars.new(string).downcase.to_s
        end
      end

      def as_8bit_ascii(string)
        if defined?(Encoding)
          string.to_s.dup.force_encoding('BINARY')
        else
          string.to_s.mb_chars
        end
      end

      def sanitize_sql_for_named_any(tag)
        if ActsAsTaggableOn.strict_case_match
          sanitize_sql(["name = #{binary}?", as_8bit_ascii(tag)])
        else
          sanitize_sql(['LOWER(name) = LOWER(?)', as_8bit_ascii(unicode_downcase(tag))])
        end
      end
    end
  end
end
