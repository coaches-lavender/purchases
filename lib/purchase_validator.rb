# frozen_string_literal: true

require_relative 'locale'

# id и баллы должны быть целыми, цена и количество — любые числа.
class PurchaseValidator
  attr_reader :errors

  def initialize(params)
    @params = params
  end

  def valid_calculation?
    @errors = [] # чтобы можно было вызвать повторно
    validate_integer(@params['user_id'], 'user_id', positive: true)

    positions = @params['positions']
    if positions.is_a?(Array) && positions.any?
      positions.each_with_index { |position, i| validate_position(position, "positions[#{i}]") }
    else
      @errors << I18n.t('errors.validation.positions_required')
    end

    @errors.empty?
  end

  def valid_submission?
    @errors = []
    user = @params['user']
    validate_integer(user.is_a?(Hash) && user['id'], 'user.id', positive: true)
    validate_integer(@params['operation_id'], 'operation_id', positive: true)
    validate_integer(@params['write_off'], 'write_off')

    @errors.empty?
  end

  private

  def validate_position(position, path)
    unless position.is_a?(Hash)
      @errors << I18n.t('errors.validation.invalid_position', path:)
      return
    end

    validate_integer(position['id'], "#{path}.id", positive: true)
    validate_number(position['price'], "#{path}.price")
    validate_number(position['quantity'], "#{path}.quantity", positive: true)
  end

  def validate_integer(value, name, positive: false)
    return add_error(name, :not_an_integer) unless value.is_a?(Integer)
    return add_error(name, :not_positive) if positive && !value.positive?

    add_error(name, :negative) if value.negative?
  end

  def validate_number(value, name, positive: false)
    return add_error(name, :not_a_number) unless value.is_a?(Numeric)
    return add_error(name, :negative) if value.negative?

    add_error(name, :not_positive) if positive && value.zero?
  end

  def add_error(name, key)
    @errors << I18n.t(key, scope: 'errors.validation', name:)
  end
end
