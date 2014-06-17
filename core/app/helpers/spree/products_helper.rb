module Spree
  module ProductsHelper
    # converts line breaks in product description into <p> tags (for html display purposes)
    def product_description(product)
      if Spree::Config[:show_raw_product_description]
        raw(product.description)
      else
        raw(product.description.gsub(/(.*?)\r?\n\r?\n/m, '<p>\1</p>'))
      end
    end

    def line_item_description(variant)
      ActiveSupport::Deprecation.warn "line_item_description(variant) is deprecated and may be removed from future releases, use line_item_description_text(line_item.description) instead.", caller

      line_item_description_text(variant.product.description)
    end

    def line_item_description_text description_text
      if description_text.present?
        truncate(strip_tags(description_text.gsub('&nbsp;', ' ')), length: 100)
      else
        Spree.t(:product_has_no_description)
      end
    end

    def cache_key_for_products
      count = @products.count
      max_updated_at = (@products.maximum(:updated_at) || Date.today).to_s(:number)
      "#{I18n.locale}/#{current_currency}/spree/products/all-#{params[:page]}-#{max_updated_at}-#{count}"
    end
  end
end
