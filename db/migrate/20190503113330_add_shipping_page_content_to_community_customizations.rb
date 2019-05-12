class AddShippingPageContentToCommunityCustomizations < ActiveRecord::Migration[5.1]
  def change
    add_column :community_customizations, :shipping_page_content, :text
  end
end