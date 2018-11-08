class AddSearchCategoryFilterToCustomFields < ActiveRecord::Migration[5.1]
  def change
    add_column :custom_fields, :search_category_filter, :boolean, :default => false
  end
end
