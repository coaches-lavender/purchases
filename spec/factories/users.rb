# frozen_string_literal: true

require_relative '../../lib/models/user'

FactoryBot.define do
  factory :user do
    template
    sequence(:name) { "User #{_1}" }
    bonus { BigDecimal('10000') }
  end
end
