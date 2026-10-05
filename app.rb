# frozen_string_literal: true

require 'sinatra/base'
require 'json'
require_relative 'lib/locale'
require_relative 'lib/purchase'

# HTTP-обёртка над сценариями Purchase: разбирает JSON-запрос и сериализует ответ.
class App < Sinatra::Base
  # целые значения BigDecimal отдаются без ".0" (734, а не 734.0)
  JSON_CODER = JSON::Coder.new do |value|
    next value unless value.is_a?(BigDecimal)

    value.frac.zero? ? value.to_i : JSON::Fragment.new(value.to_s('F'))
  end

  before { content_type :json }

  helpers do
    def json_params
      # без Content-Type: application/json данные будут в form_vars
      # дробные числа — сразу в BigDecimal
      params = JSON.parse(env['rack.request.form_vars'] || request.body.read, decimal_class: BigDecimal)
      params.is_a?(Hash) ? params : raise(Purchase::Error.new(400, I18n.t('errors.json_object_expected')))
    rescue JSON::ParserError
      raise Purchase::Error.new(400, I18n.t('errors.invalid_json'))
    end

    def respond
      JSON_CODER.dump(yield(json_params))
    rescue Purchase::Error => e
      body = { status: e.status, message: e.message }
      body[:errors] = e.errors if e.errors.any?
      halt e.status, JSON_CODER.dump(body)
    end
  end

  post('/operation') { respond { Purchase.new(_1).calculate } }

  post('/submit') { respond { Purchase.new(_1).submit } }
end
