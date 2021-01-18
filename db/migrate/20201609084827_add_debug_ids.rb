class AddDebugIds < ActiveRecord::Migration[5.1]
  def change
    add_column :pcp_payments, :order_debug_id, :string
    add_column :pcp_payments, :authorizations_capture_debug_id, :string
    add_column :pcp_payments, :authorize_debug_id, :string
    add_column :pcp_payments, :referenced_payout_debug_id, :string
    add_column :pcp_payments, :authorizations_void_debug_id, :string
  end
end