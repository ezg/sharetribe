require_relative '../../pcp_service/pcp_client'
require 'json'
include PayPalCheckoutSdk::Orders
include PayPalCheckoutSdk::Payments

module TransactionService::Gateway
  class PcpAdapter < GatewayAdapter
    PaymentStore = PcpService::Store::PcpPayment

    def initialize()
    end

    def implements_process(process)
      [:preauthorize].include?(process)
    end

    def authorize_order(order_id)
        request = OrdersAuthorizeRequest::new(order_id)
        response = PcpClient::client::execute(request)
        puts PcpClient::openstruct_to_hash(response.result).to_json

        response.result
      rescue StandardError => e
        Airbrake.notify(e)
        Result::Error.new(e.message)
    end

    def lookup_order(pcp_id)
        request = OrdersGetRequest::new(pcp_id)
        response = PcpClient::client::execute(request)
        response.result
    end

    def create_payment(tx:, gateway_fields:, force_sync:)
      #oo = pcp_order["shipping"]["dd"]

      subtotal   = order_total(tx) # contains authentication fee
      total      = subtotal
      commission = order_commission(tx) 
      buyer_commission = tx.buyer_commission

      auth_fee = Money.new(0, "USD")
      if tx.authenticate_fee
        auth_fee = tx.authenticate_fee
      end

      shipping_total = Maybe(tx.shipping_price).or_else(0)
      ret = tx.unit_price * tx.listing_quantity + shipping_total + auth_fee + tx.buyer_commission

      body = {
            intent: 'AUTHORIZE',
            application_context: {
                return_url: gateway_fields[:success_url],
                cancel_url: gateway_fields[:cancel_url],
                brand_name: 'RESWINGS',
                landing_page: 'BILLING',
                user_action: 'CONTINUE'
            },
            purchase_units: [
                {
                    reference_id: tx.id,
                    custom_id: tx.listing_id,
                    amount: {
                        currency_code: total.currency.iso_code,
                        value: total.cents / 100,
                        breakdown: {
                            item_total: {
                                currency_code: total.currency.iso_code,
                                value: (tx.unit_price * tx.listing_quantity).cents / 100
                            },
                            shipping: {
                                currency_code: total.currency.iso_code,
                                value: shipping_total.cents / 100
                            },
                            handling: {
                                currency_code: total.currency.iso_code,
                                value: auth_fee.cents / 100
                            }
                        }
                    },
                    items: [
                        {
                            name: tx.listing_title,
                            unit_amount: {
                                currency_code: total.currency.iso_code,
                                value: (tx.unit_price * tx.listing_quantity).cents / 100
                            },
                            quantity: '1',
                            category: 'PHYSICAL_GOODS'
                        }
                    ]
                }
            ]
        }
        Rails.logger.error(body)
        
        request = OrdersCreateRequest::new
        request.headers["PayPal-Partner-Attribution-Id"] = "Reswings_SP"
        request.headers["prefer"] = "return=representation"
        request.request_body(body)
        response = PcpClient::client.execute(request)

        Rails.logger.error(response)

        pcp_self_url = ""
        pcp_approve_url = ""
        pcp_update_url = ""
        pcp_authorize_url = ""
        for link in response.result.links
            if link["rel"] == "self"
                pcp_self_url = link["href"]
            elsif link["rel"] == "approve"
                pcp_approve_url = link["href"]
            elsif link["rel"] == "update"
                pcp_update_url = link["href"]
            elsif link["rel"] == "authorize"
                pcp_authorize_url = link["href"]
            end
        end

        payload = {
          payer_id: tx.starter_id,
          receiver_id: tx.listing_author_id,
          currency: tx.unit_price.currency.iso_code,
          sum_cents: total.cents,
          commission_cents: commission.cents,
          authenticate_cents: auth_fee.cents,
          fee_cents: commission.cents + auth_fee.cents,
          buyer_commission_cents: buyer_commission.cents,
          subtotal_cents: subtotal.cents,
          pcp_id: response.result.id,
          pcp_self_url: pcp_self_url,
          pcp_approve_url: pcp_approve_url,
          pcp_update_url: pcp_update_url,
          pcp_authorize_url: pcp_authorize_url
        }
        payment = PaymentStore.create(tx.community_id, tx.id, payload)
        
        result = {
            transaction_id: tx.id,
            redirect_url: pcp_approve_url}

        SyncCompletion.new(Result::Success.new(result))

    rescue StandardError => e
        Rails.logger.error(e)
        Rails.logger.error(e.message)
        Rails.logger.error(e.backtrace)
        Airbrake.notify(e)
        Result::Error.new(e.message)
    end

    def order_total(tx)
        shipping_total = Maybe(tx.shipping_price).or_else(0)
        auth_fee = Maybe(tx.authenticate_fee).or_else(0)
        ret = tx.unit_price * tx.listing_quantity + shipping_total + auth_fee + tx.buyer_commission
        return ret
    end

    def order_commission(tx)
      tot = tx.unit_price * tx.listing_quantity
      if tx.shipping_price
        tot = tot + tx.shipping_price
      end
      TransactionService::Transaction.calculate_commission(tot, 
        tx.commission_from_seller, tx.minimum_commission)
    end

    def reject_payment(tx:, reason: "")
      payment = PaymentStore.get(tx.community_id, tx.id)
      request = AuthorizationsVoidRequest::new(payment[:pcp_authorization_id])
      begin
        response = PcpClient::client::execute(request)
      rescue PayPalHttp::HttpError => ioe
        # Exception occured while processing the refund.
        puts " Status Code: #{ioe.status_code}"
        puts " Response: #{ioe.result}"
      end
      payment[:data] = { status: "rejected" }
      PaymentStore.update(payment)

      SyncCompletion.new(Result::Success.new(payment))
    rescue StandardError => e
      Airbrake.notify(e)
      Result::Error.new(e.message)
    end

    def complete_preauthorization(tx:)
        payment = PaymentStore.get(tx.community_id, tx.id)
        request = AuthorizationsCaptureRequest::new(payment[:pcp_authorization_id])
        begin
          response = PcpClient::client::execute(request)
        rescue PayPalHttp::HttpError => ioe
          # Exception occured while processing the refund.
          puts " Status Code: #{ioe.status_code}"
          puts " Response: #{ioe.result}"
        end
        payment[:data] = { status: "captured" }
        PaymentStore.update(payment)
  
        SyncCompletion.new(Result::Success.new(payment))
      rescue StandardError => e
        Airbrake.notify(e)
        Result::Error.new(e.message)
    end 

    def get_payment_details(tx:)
      stripe_api.payments.payment_details(tx)
    end

    private

    def stripe_api
      StripeService::API::Api
    end
  end
end
