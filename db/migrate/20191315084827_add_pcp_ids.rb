class AddPcpIds < ActiveRecord::Migration[5.1]
  def change
    add_column :pcp_payments, :pcp_authorization_id, :string
    add_column :pcp_payments, :pcp_capture_id, :string
    add_column :pcp_payments, :pcp_refund_id, :string
  end
end