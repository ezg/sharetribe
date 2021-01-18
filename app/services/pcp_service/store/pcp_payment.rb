module PcpService::Store::PcpPayment

  PcpPaymentModel = ::PcpPayment

  InitialPaymentData = EntityUtils.define_builder(
    [:community_id, :mandatory, :fixnum],
    [:transaction_id, :mandatory, :fixnum],
    [:payer_id, :mandatory, :string],
    [:receiver_id, :mandatory, :string],
    [:status, const_value: :pending],
    [:currency, :mandatory, :string],
    [:sum_cents, :fixnum],
    [:authenticate_cents, :fixnum],
    [:commission_cents, :fixnum],
    [:buyer_commission_cents, :fixnum],
    [:fee_cents, :fixnum],
    [:subtotal_cents, :fixnum],
    [:pcp_id, :string],
    [:pcp_self_url, :string],
    [:pcp_approve_url, :string],
    [:pcp_update_url, :string],
    [:pcp_authorize_url, :string],
    [:order_debug_id, :string],
    [:authorizations_capture_debug_id, :string],
    [:authorize_debug_id, :string],
    [:referenced_payout_debug_id, :string],
    [:authorizations_void_debug_id, :string]
  )

  PcpPayment = EntityUtils.define_builder(
    [:community_id, :mandatory, :fixnum],
    [:transaction_id, :mandatory, :fixnum],
    [:payer_id, :mandatory, :string],
    [:receiver_id, :mandatory, :string],
    [:status, :mandatory, :to_symbol],
    [:sum, :money],
    [:commission, :money],
    [:authenticate, :money],
    [:buyer_commission, :money],
    [:fee, :money],
    [:real_fee, :money],
    [:subtotal, :money],
    [:pcp_id, :string],
    [:pcp_authorization_id, :string],
    [:pcp_capture_id, :string],
    [:pcp_refund_id, :string],
    [:pcp_self_url, :string],
    [:pcp_approve_url, :string],
    [:pcp_update_url, :string],
    [:order_debug_id, :string],
    [:authorizations_capture_debug_id, :string],
    [:authorize_debug_id, :string],
    [:referenced_payout_debug_id, :string],
    [:authorizations_void_debug_id, :string],
    [:transfered_at, :time],
    [:available_on, :time]
  )

  module_function

  def update(opts)
    if(opts[:data].nil?)
      raise ArgumentError.new("No data provided")
    end

    payment = find_payment(opts)
    old_data = from_model(payment)
    update_payment!(payment, opts[:data])
  end

  def create(community_id, transaction_id, order)
    payment_data = InitialPaymentData.call(order.merge({community_id: community_id, transaction_id: transaction_id}))
    model = PcpPaymentModel.create!(payment_data)
    from_model(model)
  end

  def find_by_token(token)
    Maybe(PcpPaymentModel.where(
        pcp_id: token).first)
      .map { |model| from_model(model) }
      .or_else(nil)
  end

  def get(community_id, transaction_id)
    Maybe(PcpPaymentModel.where(
        community_id: community_id,
        transaction_id: transaction_id
        ).first)
      .map { |model| from_model(model) }
      .or_else(nil)
  end

  def from_model(pcp_payment)
    hash = HashUtils.compact(
      EntityUtils.model_to_hash(pcp_payment).merge({
          sum: pcp_payment.sum,
          fee: pcp_payment.fee,
          commission: pcp_payment.commission,
          authenticate: pcp_payment.authenticate,
          buyer_commission: pcp_payment.buyer_commission,
          subtotal: pcp_payment.subtotal,
          real_fee: pcp_payment.real_fee
        }))
    PcpPayment.call(hash)
  end

  def find_payment(opts)
    PcpPaymentModel.where(
      "(community_id = ? and transaction_id = ?)",
      opts[:community_id],
      opts[:transaction_id]
    ).first
  end

  def data_changed?(old_data, new_data)
    old_data != new_data
  end

  def update_payment!(payment, data)
    payment.update!(data)
    from_model(payment.reload)
  end
end
