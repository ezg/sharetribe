module StripeService::API
  class Payments
    class << self
      PaymentStore = StripeService::Store::StripePayment

      TransactionStore = TransactionService::Store::Transaction

      def create_preauth_payment(tx, gateway_fields)
        report = StripeService::Report.new(tx: tx)
        report.create_charge_start
        seller_account = accounts_api.get(community_id: tx.community_id, person_id: tx.listing_author_id).data
        if !seller_account || !seller_account[:stripe_seller_id].present?
          return SyncCompletion.new(Result::Error.new("No Seller Account"))
        end

        seller_id  = seller_account[:stripe_seller_id]
        source_id  = gateway_fields[:stripe_token]

        subtotal   = order_total(tx) # contains authentication fee
        total      = subtotal
        commission = order_commission(tx) 
        buyer_commission = tx.buyer_commission

        description = "Payment #{tx.id} for #{tx.listing_title} via #{gateway_fields[:service_name]} "
        metadata = {
          sharetribe_transaction_id: tx.id,
          sharetribe_seller_id: tx.listing_author_id,
          sharetribe_payer_id: tx.starter_id,
          sharetribe_mode: stripe_api.charges_mode(tx.community_id)
        }


        auth_fee = Money.new(0, "USD")
        if tx.authenticate_fee
          auth_fee = tx.authenticate_fee
        end
        
        stripe_charge = stripe_api.charge(
          community: tx.community_id,
          token: source_id,
          seller_account_id: seller_id,
          amount: total.cents,
          fee: commission.cents + auth_fee.cents + buyer_commission.cents,
          currency: total.currency.iso_code,
          description: description,
          metadata: metadata)

        payment = PaymentStore.create(tx.community_id, tx.id, {
          payer_id: tx.starter_id,
          receiver_id: tx.listing_author_id,
          currency: tx.unit_price.currency.iso_code,
          sum_cents: total.cents,
          commission_cents: commission.cents,
          authenticate_cents: auth_fee.cents,
          fee_cents: commission.cents + auth_fee.cents,
          buyer_commission_cents: buyer_commission.cents,
          subtotal_cents: subtotal.cents,
          stripe_charge_id: stripe_charge.id
        })

        if gateway_fields[:shipping_address].present?
          TransactionStore.upsert_shipping_address(
            community_id: tx.community_id,
            transaction_id: tx.id,
            addr: gateway_fields[:shipping_address])
        end

        report.create_charge_success
        Result::Success.new(payment)
      rescue StandardError => exception
        params_to_airbrake = StripeService::Report.new(tx: tx, exception: exception).create_charge_failed
        exception.extend ParamsToAirbrake
        exception.params_to_airbrake = {stripe: params_to_airbrake}
        Airbrake.notify(exception)
        Result::Error.new(exception.message)
      end

      def cancel_preauth(tx, reason)
        payment = PaymentStore.get(tx.community_id, tx.id)
        seller_account = accounts_api.get(community_id: tx.community_id, person_id: tx.listing_author_id).data
        stripe_api.cancel_charge(
          community: tx.community_id,
          charge_id: payment[:stripe_charge_id],
          account_id: seller_account[:stripe_seller_id],
          reason: reason,
          metadata: {sharetribe_transaction_id: tx.id}
        )
        payment = PaymentStore.update(transaction_id: tx.id, community_id: tx.community_id, data: {status: 'canceled'})
        Result::Success.new(payment)
      rescue StandardError => e
        Airbrake.notify(e)
        Result::Error.new(e.message)
      end

      def capture(tx)
        report = StripeService::Report.new(tx: tx)
        report.capture_charge_start
        payment = PaymentStore.get(tx.community_id, tx.id)
        seller_account = accounts_api.get(community_id: tx.community_id, person_id: tx.listing_author_id).data
        charge = stripe_api.capture_charge(community: tx.community_id, charge_id: payment[:stripe_charge_id], seller_id: seller_account[:stripe_seller_id])
        balance_txn = stripe_api.get_balance_txn(community: tx.community_id, balance_txn_id: charge.balance_transaction, account_id: seller_account[:stripe_seller_id])
        payment = PaymentStore.update(transaction_id: tx.id, community_id: tx.community_id,
                                      data: {
                                        status: 'paid',
                                        real_fee_cents: balance_txn.fee,
                                        available_on: Time.zone.at(balance_txn.available_on)
                                      })
        report.capture_charge_success
        Result::Success.new(payment)
      rescue StandardError => exception
        params_to_airbrake = StripeService::Report.new(tx: tx, exception: exception).capture_charge_failed
        exception.extend ParamsToAirbrake
        exception.params_to_airbrake = {stripe: params_to_airbrake}
        Airbrake.notify(exception)
        Result::Error.new(exception.message)
      end

      def payment_details(tx)
        payment = PaymentStore.get(tx.community_id, tx.id)
        unless payment
          total            = order_total(tx)
          commission       = order_commission(tx)
          buyer_commission = tx.buyer_commission
          fee              = Money.new(0, total.currency)
          authenticate     = Money.new(0, total.currency)
          payment = {
            sum: total,
            commission: commission,
            authenticate: authenticate,
            real_fee: fee,
            subtotal: total - fee,
            buyer_commission: buyer_commission
          }
        end
        # in case of :destination payments, gateway fee is always charged from admin account, we cannot know it upfront, as transfer to seller = total - commission, is immediate
        # in case of :separate payments, gateway fee is charged from admin account, but then deducted from seller on delayed transfer
        gateway_fee = if stripe_api.charges_mode(tx.community_id) == :destination
            Money.new(0, payment[:sum].currency)
          else
            payment[:real_fee]
          end
        {
          payment_total: payment[:sum],
          total_price: payment[:subtotal],
          charged_commission: payment[:commission],
          payment_gateway_fee: gateway_fee,
          buyer_commission: payment[:buyer_commission] || 0
        }
      end

      def payout(tx)
        report = StripeService::Report.new(tx: tx)
        report.create_payout_start
        seller_account = accounts_api.get(community_id: tx.community_id, person_id: tx.listing_author_id).data
        payment = PaymentStore.get(tx.community_id, tx.id)

        seller_gets = payment[:subtotal] - payment[:commission] - payment[:authenticate] 

        case stripe_api.charges_mode(tx.community_id)
        when :separate
          seller_gets -= payment[:real_fee] || 0
          if seller_gets > 0
            result = stripe_api.perform_transfer(
              community: tx.community_id,
              account_id: seller_account[:stripe_seller_id],
              amount_cents: seller_gets.cents,
              amount_currency: payment[:sum].currency,
              initial_amount: payment[:subtotal].cents,
              charge_id: payment[:stripe_charge_id],
              metadata: {sharetribe_transaction_id: tx.id}
            )
          end
        when :destination
          if seller_gets > 0
            charge = stripe_api.get_charge(community: tx.community_id, charge_id: payment[:stripe_charge_id])
            transfer = stripe_api.get_transfer(community: tx.community_id, transfer_id: charge.transfer)
            result = stripe_api.perform_payout(
              community: tx.community_id,
              account_id: seller_account[:stripe_seller_id],
              amount_cents: transfer.amount,
              currency: transfer.currency,
              metadata: {shretribe_order_id: tx.id}
            )
          end
        end

        payment = PaymentStore.update(transaction_id: tx.id, community_id: tx.community_id,
                                      data: {
                                        status: 'transfered',
                                        stripe_transfer_id: seller_gets > 0 ? result.id : "ZERO",
                                        transfered_at: Time.zone.now
                                      })

        report.create_payout_success
        payment
      end

      def stripe_api
        StripeService::API::Api.wrapper
      end

      def accounts_api
        StripeService::API::Api.accounts
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
    end
  end
end
