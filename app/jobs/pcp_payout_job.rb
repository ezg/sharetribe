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
    
    gateway_adapter = TransactionService::Transaction.gateway_adapter("pcp")

    Rails.logger.error("in payout 1")
    Rails.logger.error(tx.id)
    Rails.logger.error("in payout 2")
    payment = PaymentStore.get(tx.community_id, tx.id)
    Rails.logger.error(payment)

    #seller_gets = payment[:subtotal] - payment[:commission] - payment[:authenticate] 
    #Rails.logger.error(seller_gets)

    response = gateway_adapter.referenced_payout(payment[:pcp_capture_id])
    puts response
    response
    #raise

  rescue StandardError => exception
    error(self, exception, {})
    raise
  end

  def max_attempts
    1
  end
end
