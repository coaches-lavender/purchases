# frozen_string_literal: true

require_relative 'db'
require_relative 'locale'
require_relative 'models/user'
require_relative 'models/product'
require_relative 'models/operation'
require_relative 'loyalty_calculator'
require_relative 'purchase_serializer'
require_relative 'purchase_validator'

# Расчёт и подтверждение покупки
class Purchase
  # ошибка с HTTP-статусом и списком ошибок валидации
  class Error < StandardError
    attr_reader :status, :errors

    def initialize(status, message, errors = [])
      super(message)
      @status = status
      @errors = errors
    end
  end

  def initialize(params)
    @params = params
    @validator = PurchaseValidator.new(params)
  end

  def calculate
    return raise_validation_errors! unless @validator.valid_calculation?

    positions = @params['positions']
    user = find_user!(@params['user_id'])
    products = Product.where(id: positions.map { _1['id'] }).to_hash(:id)
    result = LoyaltyCalculator.new(user.template, products).call(positions)

    # в операции храним лимит списания баллов, баланс проверяется при подтверждении
    operation = Operation.create(
      result.slice(:cashback, :cashback_percent, :discount, :discount_percent, :check_summ, :allowed_write_off)
            .merge(user_id: user.id, done: false)
    )

    PurchaseSerializer.calculation(user:, operation:, result:)
  end

  def submit
    return raise_validation_errors! unless @validator.valid_submission?

    write_off = @params['write_off']

    operation = DB.transaction(mode: :immediate) do
      user = find_user!(@params['user']['id'])
      operation = Operation.first(id: @params['operation_id'], user_id: user.id)
      raise Error.new(404, I18n.t('errors.operation_not_found')) unless operation

      # ретрай получает прежний результат и ничего не меняет
      next operation if operation.done && operation.write_off == write_off

      check_write_off!(user, operation, write_off)
      confirm(user, operation, write_off)
    end

    PurchaseSerializer.submission(operation)
  end

  private

  def find_user!(id)
    user = User[id]
    raise Error.new(404, I18n.t('errors.user_not_found')) unless user

    user
  end

  def raise_validation_errors!
    raise Error.new(400, I18n.t('errors.invalid_params'), @validator.errors)
  end

  def check_write_off!(user, operation, write_off)
    raise Error.new(422, I18n.t('errors.already_submitted')) if operation.done
    raise Error.new(422, I18n.t('errors.write_off_exceeds_allowed')) if write_off > operation.allowed_write_off
    raise Error.new(422, I18n.t('errors.not_enough_bonuses')) if write_off > user.balance
  end

  # кэшбек начисляется только на сумму к уплате, хранится как numeric до подтверждения,
  # чтобы не терять лишний бал при двойном округлении
  def confirm(user, operation, write_off)
    cashback = operation.cashback
    # кэшбек «размазывается» по всем товарам в операции пропорционально
    cashback *= 1 - (write_off / operation.allowed_write_off) if write_off.positive?
    cashback = cashback.floor
    check_summ = operation.check_summ - write_off

    user.update(bonus: user.balance - write_off + cashback)
    operation.update(
      write_off:, cashback:, check_summ:, done: true,
      cashback_percent: LoyaltyCalculator.percent(cashback, check_summ)
    )
  end
end
