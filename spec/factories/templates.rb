# frozen_string_literal: true

require_relative '../../lib/models/template'

FactoryBot.define do
  # Уровни лояльности из ТЗ; по умолчанию Bronze — только кэшбек.
  factory :template do
    name { 'Bronze' }
    discount { 0 }
    cashback { 5 }

    trait :silver do
      name { 'Silver' }
      discount { 5 }
      cashback { 5 }
    end

    trait :gold do
      name { 'Gold' }
      discount { 15 }
      cashback { 0 }
    end
  end
end
