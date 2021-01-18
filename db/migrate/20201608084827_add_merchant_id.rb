class AddMerchantId < ActiveRecord::Migration[5.1]
  def change
    add_column :people, :merchant_id, :string
  end
end