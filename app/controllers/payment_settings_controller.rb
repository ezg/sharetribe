require 'securerandom'

class PaymentSettingsController < ApplicationController
  before_action do |controller|
    controller.ensure_logged_in t("layouts.notifications.you_must_log_in_to_view_your_settings")
  end

  before_action :set_presenter
  before_action :ensure_payments_enabled
  skip_before_action :warn_about_missing_payment_info, only: [:update]

  def index
  end

  def update
    gateway_adapter = TransactionService::Transaction.gateway_adapter("pcp")
    is_ready = gateway_adapter.is_ready_for_payment(@current_user)

    Rails.logger.error(">>> unlink")
    @current_user.pcp_salt = SecureRandom.hex(10)
    @current_user.set_pcp_salt(@current_user.pcp_salt)
    @current_user.set_merchant_id(nil)
    redirect_to person_payment_settings_url(@current_user)
  end

  private

  def set_presenter
    gateway_adapter = TransactionService::Transaction.gateway_adapter("pcp")

    merchant_id = gateway_adapter.get_merchant_id_by_user(@current_user)
    Rails.logger.error("kkkkkkk")
    Rails.logger.error(merchant_id)

    if merchant_id == nil || @current_user.pcp_salt == nil
      @current_user.pcp_salt = SecureRandom.hex(10)
      @current_user.set_pcp_salt(@current_user.pcp_salt)
    end

    link_account_response = gateway_adapter.link_account(person_payment_settings_url(@current_user), @current_user.pcp_salt)
    redirect_link = ""
    for link in link_account_response.links
        if link["rel"] == "action_url"
          redirect_link = link["href"] + "&displayMode=minibrowser"
        end
    end
    Rails.logger.error("-------")
    Rails.logger.error(redirect_link)
    
    is_ready = gateway_adapter.is_ready_for_payment(@current_user)
    
    @selected_left_navi_link = "payments"
    @is_ready = is_ready
    @action_url = redirect_link
    @merchant_id = merchant_id
    @presenter = Person::PcpPaymentSettingsPresenter.new(community: @current_community, person_url: person_url(@current_user.username))
  end

  def ensure_payments_enabled
    unless @presenter.payments_enabled?
      flash[:warning] = t("stripe_accounts.admin_account_not_connected",
                            contact_admin_link: view_context.link_to(
                              t("stripe_accounts.contact_admin_link_text"),
                                new_user_feedback_path)).html_safe # rubocop:disable Rails/OutputSafety
      redirect_to person_settings_path
    end
  end
end
