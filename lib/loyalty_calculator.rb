# frozen_string_literal: true

require 'bigdecimal'

# Рассчитывает скидки и кэшбек по позициям чека.
# positions — позиции запроса как есть: хеши 'id', 'price', 'quantity' с числами из JSON.
class LoyaltyCalculator
  def self.percent(part, whole)
    whole.zero? ? 0 : (part * 100 / whole).round(2)
  end

  def initialize(template, products)
    @template = template
    @products = products
  end

  def call(positions)
    items = positions.map { build(_1) }
    total = items.sum { _1[:amount] }
    check_summ = items.sum { _1[:summ] }
    discount = items.sum { _1[:discount_summ] }
    # кэшбек хранится точным, чтобы не терять баллы при двойном округлении
    cashback = items.sum { _1[:cashback] }

    # ключи совпадают с колонками operations
    {
      positions: items, check_summ:, discount:, cashback:,
      discount_percent: self.class.percent(discount, total),
      # процент — от целых баллов, которые клиент получит без списания
      cashback_percent: self.class.percent(cashback.floor, check_summ),
      # точная сумма товаров программы: по ней списание распределяется при подтверждении,
      # а целочисленный лимит списания — её округление вниз (в ответе и при проверке списания)
      allowed_write_off: items.select { _1[:loyal] }.sum { _1[:summ] }
    }
  end

  private

  # лишние поля позиции игнорируются
  def build(position)
    id, price, quantity = position.values_at('id', 'price', 'quantity')
    product = @products[id]
    type = product&.type
    value = product&.value && BigDecimal(product.value)
    loyal = type != 'noloyalty'

    discount_percent = loyalty_percent(type, @template.discount, 'discount', value)
    cashback_percent = loyalty_percent(type, @template.cashback, 'increased_cashback', value)
    # стоимость позиции — до копеек: цена может прийти с лишними знаками, количество может быть дробным
    amount = (BigDecimal(price) * BigDecimal(quantity)).round(2)
    discount_summ = (amount * discount_percent / 100).round(2)
    summ = amount - discount_summ

    {
      id:, price:, quantity:, type:, value:, loyal:, amount:, discount_percent:, discount_summ:, summ:,
      cashback: summ * cashback_percent / 100
    }
  end

  # процент уровня плюс процент товара, для noloyalty — 0
  def loyalty_percent(type, level_percent, modifier, value)
    return 0 if type == 'noloyalty'

    BigDecimal(level_percent) + (type == modifier ? value : 0)
  end
end
