class AddAuthenticateToTransactions < ActiveRecord::Migration[5.1]
  def change
    add_column :transactions, :authenticate, :boolean, :default => false
  end
end
