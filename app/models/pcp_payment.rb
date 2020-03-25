# == Schema Information
#
# Table name: pcp_payments
#
#  id                     :integer          not null, primary key
#  community_id           :integer
#  transaction_id         :integer
#  payer_id               :string(255)
#  receiver_id            :string(255)
#  status                 :string(255)
#  sum_cents              :integer
#  commission_cents       :integer
#  currency               :string(255)
#  pcp_id                 :string(255)
#  pcp_authorization_id   :string(255)
#  pcp_capture_id         :string(255)
#  pcp_refund_id          :string(255)
#  pcp_self_url           :string(255)
#  pcp_approve_url        :string(255)
#  pcp_update_url         :string(255)
#  pcp_authorize_url      :string(255)
#  fee_cents              :integer
#  real_fee_cents         :integer
#  subtotal_cents         :integer
#  transfered_at          :datetime
#  available_on           :datetime
#  authenticate_cents     :integer
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  buyer_commission_cents :integer          default(0)
#

class PcpPayment < ApplicationRecord
  belongs_to :tx,       class_name: 'Transaction', foreign_key: 'transaction_id', inverse_of: :pcp_payments
  belongs_to :payer,    class_name: 'Person',      foreign_key: 'payer_id',       inverse_of: :payer_pcp_payments
  belongs_to :receiver, class_name: 'Person',      foreign_key: 'receiver_id',    inverse_of: :receiver_pcp_payments

  monetize :sum_cents,        with_model_currency: :currency
  monetize :commission_cents, with_model_currency: :currency
  monetize :fee_cents,        with_model_currency: :currency
  monetize :real_fee_cents,   with_model_currency: :currency, allow_nil: true
  monetize :subtotal_cents,   with_model_currency: :currency
  monetize :authenticate_cents,   with_model_currency: :currency, allow_nil: true
  monetize :buyer_commission_cents, with_model_currency: :currency

  STATUSES = %w(pending paid canceled transfered)
end
