class PcpService::CheckoutOrdersController < ApplicationController
  PaymentStore = PcpService::Store::PcpPayment
  TransactionStore = TransactionService::Store::Transaction

  skip_before_action :verify_authenticity_token

  before_action do
    unless PcpHelper.community_ready_for_payments?(@current_community.id)
      render :body => nil, :status => :bad_request
    end
  end


  def success
    gateway_adapter = TransactionService::Transaction.gateway_adapter("pcp")

    return redirect_to error_not_found_path if params[:token].blank?
    
    payment = PaymentStore.find_by_token(params[:token])
    pcp_order = gateway_adapter.lookup_order(payment[:pcp_id])
    status = pcp_order["status"]

    return redirect_to error_not_found_path if status != "APPROVED"
    payment[:data] = { status: status }
    PaymentStore.update(payment)

    # update shipping address
    full_name = pcp_order["purchase_units"][0]["shipping"]["name"]["full_name"]
    shipping_address = pcp_order["purchase_units"][0]["shipping"]["address"]
    
    details = { 
      name: full_name,
      street1: shipping_address["address_line_1"],
      street2: shipping_address["address_line_2"],
      postal_code: shipping_address["postal_code"],
      city: shipping_address["admin_area_2"],
      country_code: shipping_address["country_code"],
      state_or_province: shipping_address["admin_area_1"]
    }
    #Rails.logger.error(PcpClient::openstruct_to_hash(shipping_address).to_json)

    TransactionStore.upsert_shipping_address(
      community_id: payment[:community_id],
      transaction_id: payment[:transaction_id],
      addr: details)

    # fix is here
    pcp_authorization = gateway_adapter.authorize_order(payment[:pcp_id])
    status = pcp_authorization["status"]

    return redirect_to error_not_found_path if status != "COMPLETED"
    payment[:data] = { 
        status: status, 
        pcp_authorization_id: pcp_authorization.purchase_units[0].payments.authorizations[0].id}
    PaymentStore.update(payment)

    TransactionService::StateMachine.transition_to(payment[:transaction_id], :preauthorized)
    redirect_to transaction_created_path(transaction_id: payment[:transaction_id])

  #rescue StandardError => e
  #  flash[:error] = t("error_messages.paypal.generic_error")
  #  return redirect_to search_path
  end

  def cancel
    flash[:notice] = t("paypal.cancel_succesful")
    return redirect_to person_listing_path(person_id: @current_user.id, id: params[:listing_id])
  end
end
