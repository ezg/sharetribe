class AddCopyrightPageContentToCommunityCustomizations < ActiveRecord::Migration[5.1]
  def change
    add_column :community_customizations, :copyright_page_content, :text
  end
end