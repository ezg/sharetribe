require 'paypal-sdk-rest'
require 'securerandom'

class PcpPayoutJob < Struct.new(:transaction_id, :community_id)
  PaymentStore = PcpService::Store::PcpPayment
  include DelayedAirbrakeNotification
  include PayPal::SDK::REST

  # This before hook should be included in all Jobs to make sure that the service_name is
  # correct as it's stored in the thread and the same thread handles many different communities
  # if the job doesn't have host parameter, should call the method with nil, to set the default service_name
  def before(job)
    # Set the correct service name to thread for I18n to pick it
    ApplicationHelper.store_community_service_name_to_thread_from_community_id(community_id)
  end

  def perform
    tx = ::Transaction.find(transaction_id)
    
    PayPal::SDK.configure(
      :mode =>  APP_CONFIG.pcp_mode,
      :client_id => APP_CONFIG.pcp_client_id,
      :client_secret => APP_CONFIG.pcp_client_secret,
      :ssl_options => { } )

    Rails.logger.error("in payout 1")
    Rails.logger.error(tx.id)
    Rails.logger.error("in payout 2")
    payment = PaymentStore.get(tx.community_id, tx.id)
    Rails.logger.error(payment)

    seller_gets = payment[:subtotal] - payment[:commission] - payment[:authenticate] 
    Rails.logger.error(seller_gets)

    @payout = Payout.new({
                :sender_batch_header => {
                    :sender_batch_id => SecureRandom.hex(8),
                    :email_subject => 'You have a payout from RESWINGS!'
                },
                :items => [
                    {
                        :recipient_type => 'EMAIL',
                        :amount => {
                            :value => seller_gets.cents / 100.0,
                            :currency => seller_gets.currency
                        },
                        :note => 'Thanks for your patronage!',
                        :sender_item_id => tx.id,
                        :receiver => 'emanuel.zgraggen@gmail.com'
                    }
                ]
            })
    begin
      @payout_batch = @payout.create
      Rails.logger.info("Created Payout with [#{@payout_batch.batch_header.payout_batch_id}]")
    rescue ResourceNotFound => err
      Rails.logger.error @payout.error.inspect
    end
  end

  def max_attempts
    1
  end
end
