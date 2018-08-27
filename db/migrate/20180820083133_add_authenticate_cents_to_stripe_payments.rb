class AddAuthenticateCentsToStripePayments < ActiveRecord::Migration[5.1]
  def change
    add_column :stripe_payments, :authenticate_cents, :int
  end
end
