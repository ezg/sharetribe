class AddAuthenticateCentsToTransactions < ActiveRecord::Migration[5.1]
  def change
    add_column :transactions, :authenticate_fee_cents, :int
  end
end