require_relative '../../pcp_service/pcp_client'
require 'json'
require 'date'
include PayPalCheckoutSdk::Orders
include PayPalCheckoutSdk::Payments

module TransactionService::Gateway
  class PartnerReferallsRequest
    attr_accessor :path, :body, :headers, :verb

    def initialize()
        @headers = {}
        @body = nil
        @verb = "POST"
        @path = "/v2/customer/partner-referrals"
        @headers["Content-Type"] = "application/json"
    end

    def request_body(order)
        @body = order
    end
  end

  class PartnerTrackingRequest
    attr_accessor :path, :body, :headers, :verb

    def initialize(tracking_id)
        @headers = {}
        @body = nil
        @verb = "GET"
        @path = "/v1/customer/partners/RTQKMKVA2DTYN/merchant-integrations?tracking_id=" + tracking_id
        @headers["Content-Type"] = "application/json"
    end
  end

  class ReferencedPayoutsRequest
    attr_accessor :path, :body, :headers, :verb

    def initialize()
        @headers = {}
        @body = nil
        @verb = "POST"
        @path = "/v1/payments/referenced-payouts-items"
        @headers["Content-Type"] = "application/json"
    end

    def request_body(order)
        @body = order
    end
  end

  class CheckMerchant
    attr_accessor :path, :body, :headers, :verb

    def initialize(merchant_id)
        @headers = {}
        @body = nil
        @verb = "GET"
        @path = "/v1/customer/partners/RTQKMKVA2DTYN/merchant-integrations/" + merchant_id
        @headers["Content-Type"] = "application/json"
    end
  end


  class PcpAdapter < GatewayAdapter
    PaymentStore = PcpService::Store::PcpPayment
    attr_accessor :merchant_dictionary

    def initialize()
      @merchant_dictionary = {}
    end

    def implements_process(process)
      [:preauthorize].include?(process)
    end

    def authorize_order(order_id)
        request = OrdersAuthorizeRequest::new(order_id)
        response = PcpClient::client::execute(request)

        puts PcpClient::openstruct_to_hash(response.result).to_json

        response
      rescue StandardError => e
        Airbrake.notify(e)
        Result::Error.new(e.message)
    end

    def link_account(return_url, pcp_salt) 
      puts "link account"
      puts pcp_salt
      body = {
        "operations": [
          {
            "operation": "API_INTEGRATION",
            "api_integration_preference": {
              "rest_api_integration": {
                "integration_method": "PAYPAL",
                "integration_type": "THIRD_PARTY",
                "third_party_details": {
                  "features": [
                    "PAYMENT",
                    "REFUND",
                    "PARTNER_FEE",
                    "DELAY_FUNDS_DISBURSEMENT",
                    "ACCESS_MERCHANT_INFORMATION"
                  ]
                }
              }
            }
          }
        ],
        "tracking_id": pcp_salt,
        "partner_config_override": {
          "return_url": "http://www.reswings.com", #return_url,
          "return_url_description": "the url to return the merchant after the paypal onboarding process."
        },
        "products": [
          "EXPRESS_CHECKOUT"
        ]
      }

      request = PartnerReferallsRequest::new()
      request.request_body(body)

      response = PcpClient::client::execute(request)
      response.result

    rescue PayPalHttp::HttpError => ioe
      # Exception occured while processing the refund.
      puts " Status Code: #{ioe.status_code}"
      puts " Response: #{ioe.result}"
      puts ioe.headers
    end

    def referenced_payout(reference_id)
      body = {
        "reference_id": reference_id,
        "reference_type": "TRANSACTION_ID"
      }
      puts "//////"
      puts body

      request = ReferencedPayoutsRequest::new()
      request.request_body(body)

      response = PcpClient::client::execute(request)
      response

    rescue PayPalHttp::HttpError => ioe
      # Exception occured while processing the refund.
      puts " Status Code: #{ioe.status_code}"
      puts " Response: #{ioe.result}"
      puts ioe.headers
    end

    def track_partner(pcp_salt)
      puts ">>> track_partner"
      puts pcp_salt
      request = PartnerTrackingRequest::new(pcp_salt)

      response = PcpClient::client::execute(request)
      response.result

    rescue PayPalHttp::HttpError => ioe
      # Exception occured while processing the refund.
      puts " Status Code: #{ioe.status_code}"
      puts " Response: #{ioe.result}"
      puts ioe.headers
    end

    def check_merchant(merchant_id)
      request = CheckMerchant::new(merchant_id)

      response = PcpClient::client::execute(request)
      response.result

    rescue PayPalHttp::HttpError => ioe
      # Exception occured while processing the refund.
      puts " Status Code: #{ioe.status_code}"
      puts " Response: #{ioe.result}"
      puts ioe.headers
    end

    def lookup_order(pcp_id)
        request = OrdersGetRequest::new(pcp_id)
        response = PcpClient::client::execute(request)
        response.result
    end

    def get_merchant_id_by_user(user)
      if user.merchant_id != nil
        return user.merchant_id
      end
      if user.pcp_salt == nil
        return nil
      end
      
      track_partner_response = track_partner(user.pcp_salt)
      merchant_id = nil
      if track_partner_response != nil
        merchant_id = track_partner_response.merchant_id
        user.set_merchant_id(merchant_id)
      end
      merchant_id
    end

    def is_ready_for_payment(user)
      merchant_id = get_merchant_id_by_user(user)
      is_ready = false
      if merchant_id != nil
        Rails.logger.info(">>> merchant_id: " + merchant_id)

        check_merchant_response = check_merchant(merchant_id)
      
        if check_merchant_response.payments_receivable
          integration = check_merchant_response.oauth_integrations[0]
          has_payment = false
          has_refund = false
          has_partner_fee = false
          has_delay_funds_disbursement = false
          has_access_merchant_information = false
          for scope in integration.oauth_third_party[0].scopes
            if scope == "https://uri.paypal.com/services/payments/delay-funds-disbursement"
              has_delay_funds_disbursement = true
            elsif scope == "https://uri.paypal.com/services/payments/partnerfee"
              has_partner_fee = true
            elsif scope == "https://uri.paypal.com/services/payments/refund"
              has_refund = true
            elsif scope == "https://uri.paypal.com/services/customer/merchant-integrations/read"
              has_access_merchant_information = true
            elsif scope == "https://uri.paypal.com/services/payments/payment/authcapture"
              has_payment = true
            end
          end

          Rails.logger.info(">>> yay: " + merchant_id)
          is_ready = has_payment && has_refund && has_partner_fee && has_delay_funds_disbursement && has_access_merchant_information
        end
      end

      is_ready
    end

    def create_payment(tx:, gateway_fields:, force_sync:)
      person = Person.find(tx.listing.author_id)     
      merchant_id = get_merchant_id_by_user(person)
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
                user_action: 'PAY_NOW'
            },
            purchase_units: [
                {
                    reference_id: tx.id,
                    custom_id: tx.listing_id,
                    amount: {
                        currency_code: total.currency.iso_code,
                        value: total.cents / 100.0,
                        breakdown: {
                            item_total: {
                                currency_code: total.currency.iso_code,
                                value: (tx.unit_price * tx.listing_quantity).cents / 100.0
                            },
                            shipping: {
                                currency_code: total.currency.iso_code,
                                value: shipping_total.cents / 100.0
                            }
                            #,
                            #handling: {
                            #    currency_code: total.currency.iso_code,
                            #    value: auth_fee.cents / 100
                            #}
                        }
                    },
                    items: [
                        {
                            name: tx.listing_title,
                            unit_amount: {
                                currency_code: total.currency.iso_code,
                                value: (tx.unit_price * tx.listing_quantity).cents / 100.0
                            },
                            quantity: '1',
                            category: 'PHYSICAL_GOODS'
                        }
                    ],
                    payee: {
                      merchant_id: merchant_id
                    }
                }
            ]
        }
        
        Rails.logger.error("++++++")
        Rails.logger.error(body)
        Rails.logger.error("++++++")
        
        request = OrdersCreateRequest::new
        request.headers["PayPal-Partner-Attribution-Id"] = "Reswings_SP"
        request.headers["prefer"] = "return=representation"
        request.request_body(body)

        puts "llllll"
        puts request.to_json
        response = PcpClient::client.execute(request)
        puts "--------"
        puts PcpClient::openstruct_to_hash(response.result).to_json

        Rails.logger.error(response)
        Rails.logger.error(response.headers)

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
          pcp_authorize_url: pcp_authorize_url,
          order_debug_id: response.headers["paypal-debug-id"][0]
        }
        payment = PaymentStore.create(tx.community_id, tx.id, payload)
        
        result = {
            transaction_id: tx.id,
            pcp_id: response.result.id,
            redirect_url: pcp_approve_url,
            return_url: gateway_fields[:success_url],
            cancel_url: gateway_fields[:cancel_url]
          }

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
        payment[:data] = { status: "rejected", authorizations_void_debug_id: response.headers["paypal-debug-id"][0] }
        PaymentStore.update(payment)
      rescue PayPalHttp::HttpError => ioe
        # Exception occured while processing the refund.
        puts " Status Code: #{ioe.status_code}"
        puts " Response: #{ioe.result}"
      end

      SyncCompletion.new(Result::Success.new(payment))
    rescue StandardError => e
      Rails.logger.error(e)
      Rails.logger.error(e.message)
      Rails.logger.error(e.backtrace)
      Airbrake.notify(e)
      Result::Error.new(e.message)
    end

    def complete_preauthorization(tx:)
        payment = PaymentStore.get(tx.community_id, tx.id)
        request = AuthorizationsCaptureRequest::new(payment[:pcp_authorization_id])
        # platform fees would go here: https://developer.paypal.com/docs/api/payments/v2/#definition-payment_instruction
        body = {
          payment_instruction: { 
            disbursement_mode: "DELAYED"
          } 
        }
        request.request_body(body)

        begin
          response = PcpClient::client::execute(request)
          puts ">>>>>>>>>>>>>>>>>>>"
          puts response
          payment[:data] = { status: "captured", pcp_capture_id: response.result.id, authorizations_capture_debug_id: response.headers["paypal-debug-id"][0] }
          PaymentStore.update(payment)
        rescue PayPalHttp::HttpError => ioe
          # Exception occured while processing the refund.
          puts " Status Code: #{ioe.status_code}"
          puts " Response: #{ioe.result}"
        end
       
  
        SyncCompletion.new(Result::Success.new(payment))
      rescue StandardError => e
        Rails.logger.error(e)
        Rails.logger.error(e.message)
        Rails.logger.error(e.backtrace)
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
