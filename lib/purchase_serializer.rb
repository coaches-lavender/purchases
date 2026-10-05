# frozen_string_literal: true

require_relative 'locale'

class PurchaseSerializer
  class << self
    def calculation(user:, operation:, result:)
      {
        status: 200,
        user: serialize_user(user),
        operation_id: operation.id,
        check_summ: result[:check_summ],
        bonuses: serialize_bonuses(user, result),
        discounts: result.slice(:discount, :discount_percent),
        positions: result[:positions].map { serialize_position(_1) }
      }
    end

    def submission(operation)
      {
        status: 200,
        message: I18n.t('messages.submitted'),
        operation: operation.values.slice(
          :id, :user_id, :cashback, :cashback_percent, :discount, :discount_percent, :write_off, :check_summ
        )
      }
    end

    private

    def serialize_bonuses(user, result)
      # в operations кэшбек точный, клиенту показываем целые баллы, которые будут начислены без списания
      result.slice(:cashback_percent).merge(
        cashback: result[:cashback].floor,
        balance: user.balance,
        # баллы целые: округляем вниз уже после ограничения балансом, ведь и баланс может быть дробным
        allowed_write_off: [user.balance, result[:allowed_write_off]].min.floor
      )
    end

    def serialize_user(user)
      user.values.slice(:id, :name).merge(level: user.template.name, bonus: user.balance)
    end

    def serialize_position(position)
      position.slice(:id, :price, :quantity, :type, :value, :discount_percent, :discount_summ)
              .merge(description: description(position[:type], position[:value]))
    end

    def description(type, value)
      return unless type

      I18n.t(type, scope: 'modifiers', value: value && format('%g', value)) # %g выводит целые BigDecimal без нуля
    end
  end
end
