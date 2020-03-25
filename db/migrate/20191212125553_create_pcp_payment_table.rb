class CreatePcpPaymentTable < ActiveRecord::Migration[5.1]
  def change
    create_table :pcp_payments do |t|
      t.integer   :community_id
      t.integer   :transaction_id
      t.string    :payer_id
      t.string    :receiver_id
      t.string    :status
      t.integer   :sum_cents
      t.integer   :commission_cents
      t.string    :currency
      t.string    :pcp_id
      t.string    :pcp_self_url
      t.string    :pcp_approve_url
      t.string    :pcp_update_url
      t.string    :pcp_authorize_url
      t.integer   :fee_cents
      t.integer   :real_fee_cents
      t.integer   :subtotal_cents
      t.datetime  :transfered_at
      t.datetime  :available_on
      t.integer   :authenticate_cents
      t.timestamps
    end
    
  end
end
