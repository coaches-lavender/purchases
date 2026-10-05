# frozen_string_literal: true

require_relative '../../lib/models/operation'

FactoryBot.define do
  # Неподтверждённая операция пользователя Bronze — то, что /operation сохраняет для корзины из app_spec.
  factory :operation do
    user_id { association(:user).id }
    cashback { BigDecimal('31.7') }
    cashback_percent { BigDecimal('4.22') }
    discount { BigDecimal('6') }
    discount_percent { BigDecimal('0.81') }
    check_summ { BigDecimal('734') }
    allowed_write_off { BigDecimal('434') }
    done { false }
  end
end
