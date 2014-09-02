module Spree
  class Variant < ActiveRecord::Base
    acts_as_paranoid

    belongs_to :product, touch: true, class_name: 'Spree::Product', inverse_of: :variants
    belongs_to :tax_category, class_name: 'Spree::TaxCategory'

    delegate_belongs_to :product, :name, :description, :slug, :available_on,
                        :shipping_category_id, :meta_description, :meta_keywords,
                        :shipping_category

    has_many :inventory_units
    has_many :line_items, inverse_of: :variant

    has_many :stock_items, dependent: :destroy, inverse_of: :variant
    has_many :stock_locations, through: :stock_items
    has_many :stock_movements

    has_and_belongs_to_many :option_values, join_table: :spree_option_values_variants
    has_many :images, -> { order(:position) }, as: :viewable, dependent: :destroy, class_name: "Spree::Image"

    has_many :prices,
      class_name: 'Spree::Price',
      dependent: :destroy,
      inverse_of: :variant

    validates :cost_price, numericality: { greater_than_or_equal_to: 0, allow_nil: true }

    before_validation :set_cost_currency
    after_create :create_stock_items
    after_create :set_position

    after_touch :clear_in_stock_cache

    # default variant scope only lists non-deleted variants
    scope :deleted, lambda { where.not(deleted_at: nil) }

    def self.active(currency = nil)
      joins(:prices).where(deleted_at: nil).
      where('spree_prices.currency' => currency || Spree::Config[:currency]).
      where('spree_prices.amount IS NOT NULL')
    end
    
    def price(address)
      prices.joins({market_pricelist: :pricelist_addresses}).
      where({market_pricelist_addresses: { spree_address_id: address}})[0]
    end
    
    def display_price(address)
      current_price = price(address)
      Spree::Money.new(current_price.amount, current_price.currency) if current_price
    end

    def tax_category
      if self[:tax_category_id].nil?
        product.tax_category
      else
        TaxCategory.find(self[:tax_category_id])
      end
    end

    def cost_price=(price)
      self[:cost_price] = parse_price(price) if price.present?
    end

    # returns number of units currently on backorder for this variant.
    def on_backorder
      inventory_units.with_state('backordered').size
    end

    def options_text
      values = self.option_values.sort do |a, b|
        a.option_type.position <=> b.option_type.position
      end

      values.map! do |ov|
        "#{ov.option_type.presentation}: #{ov.presentation}"
      end

      values.to_sentence({ words_connector: ", ", two_words_connector: ", " })
    end

    # use deleted? rather than checking the attribute directly. this
    # allows extensions to override deleted? if they want to provide
    # their own definition.
    def deleted?
      !!deleted_at
    end

    # Product may be created with deleted_at already set,
    # which would make AR's default finder return nil.
    # This is a stopgap for that little problem.
    def product
      Spree::Product.unscoped { super }
    end

    def options=(options = {})
      options.each do |option|
        set_option_value(option[:name], option[:value])
      end
    end

    def set_option_value(opt_name, opt_value)
      # no option values on master
      return if self.is_master

      option_type = Spree::OptionType.where(name: opt_name).first_or_initialize do |o|
        o.presentation = opt_name
        o.save!
      end

      current_value = self.option_values.detect { |o| o.option_type.name == opt_name }

      unless current_value.nil?
        return if current_value.name == opt_value
        self.option_values.delete(current_value)
      else
        # then we have to check to make sure that the product has the option type
        unless self.product.option_types.include? option_type
          self.product.option_types << option_type
        end
      end

      option_value = Spree::OptionValue.where(option_type_id: option_type.id, name: opt_value).first_or_initialize do |o|
        o.presentation = opt_value
        o.save!
      end

      self.option_values << option_value
      self.save
    end

    def option_value(opt_name)
      self.option_values.detect { |o| o.option_type.name == opt_name }.try(:presentation)
    end

    def name_and_sku
      "#{name} - #{sku}"
    end

    def sku_and_options_text
      "#{sku} #{options_text}".strip
    end

    def in_stock?
      Rails.cache.fetch(in_stock_cache_key) do
        total_on_hand > 0
      end
    end

    def can_supply?(quantity=1)
      Spree::Stock::Quantifier.new(self).can_supply?(quantity)
    end

    def total_on_hand
      Spree::Stock::Quantifier.new(self).total_on_hand
    end

    # Shortcut method to determine if inventory tracking is enabled for this variant
    # This considers both variant tracking flag and site-wide inventory tracking settings
    def should_track_inventory?
      self.track_inventory? && Spree::Config.track_inventory_levels
    end

    private
      # strips all non-price-like characters from the price, taking into account locale settings
      def parse_price(price)
        return price unless price.is_a?(String)

        separator, delimiter = I18n.t([:'number.currency.format.separator', :'number.currency.format.delimiter'])
        non_price_characters = /[^0-9\-#{separator}]/
        price.gsub!(non_price_characters, '') # strip everything else first
        price.gsub!(separator, '.') unless separator == '.' # then replace the locale-specific decimal separator with the standard separator if necessary

        price.to_d
      end

      def set_cost_currency
        self.cost_currency = Spree::Config[:currency] if cost_currency.nil? || cost_currency.empty?
      end

      def create_stock_items
        StockLocation.all.each do |stock_location|
          stock_location.propagate_variant(self) if stock_location.propagate_all_variants?
        end
      end

      def set_position
        self.update_column(:position, product.variants.maximum(:position).to_i + 1)
      end

      def in_stock_cache_key
        "variant-#{id}-in_stock"
      end

      def clear_in_stock_cache
        Rails.cache.delete(in_stock_cache_key)
      end
  end
end

require_dependency 'spree/variant/scopes'
