class UserPayment < ActiveRecord::Base
  belongs_to :incoming_payment
  belongs_to :user

  validates :incoming_payment_id, :user_id, :amount, :from_date, :to_date,
      presence: true

  def received_amount
    return amount unless incoming_payment_id
    incoming_payment.src_amount || amount
  end

  def received_currency
    return SysConfig.get(:plugin_payments, :default_currency) unless incoming_payment_id
    incoming_payment.src_currency || incoming_payment.currency
  end
end
