class Person::PcpPaymentSettingsPresenter
  include Person::PaymentSettingsCommon

  private

  attr_reader :person_url

  public

  def initialize(person_url:, community:)
    @community = community
    @person_url = person_url
  end

  def payments_enabled?
    paypal_enabled || stripe_enabled || pcp_enabled
  end

  def stripe_enabled
    @stripe_enabled ||= StripeHelper.community_ready_for_payments?(@community.id)
  end

  def pcp_enabled
    @pcp_enabled = true
  end

  def paypal_enabled
    @paypal_enabled ||= PaypalHelper.community_ready_for_payments?(@community.id)
  end
end
