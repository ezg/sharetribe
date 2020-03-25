class AddBuyerCommisionToPcpPayments < ActiveRecord::Migration[5.1]
  def change
    add_column :pcp_payments, :buyer_commission_cents, :integer, default: 0
  end
end
