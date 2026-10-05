# frozen_string_literal: true

require_relative '../../lib/models/product'

FactoryBot.define do
  # Товары с модификаторами из ТЗ; товар без модификатора в products не хранится.
  factory :product do
    trait :increased_cashback do
      name { 'Молоко' }
      type { 'increased_cashback' }
      value { '10' }
    end

    trait :discount do
      name { 'Хлеб' }
      type { 'discount' }
      value { '15' }
    end

    trait :noloyalty do
      name { 'Сахар' }
      type { 'noloyalty' }
    end
  end
end
