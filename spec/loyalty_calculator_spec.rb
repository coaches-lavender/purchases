# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lib/models/template'
require_relative '../lib/models/product'

RSpec.describe LoyaltyCalculator do
  subject(:result) { described_class.new(template, products).call(positions) }

  let(:template) { build(:template) }
  let(:products) do
    {
      2 => build(:product, :increased_cashback),
      3 => build(:product, :discount),
      4 => build(:product, :noloyalty)
    }
  end
  let(:positions) do
    [[1, 100, 3], [2, 50, 2], [3, 40, 1], [4, 150, 2]].map do |id, price, quantity|
      { 'id' => id, 'price' => price, 'quantity' => quantity }
    end
  end

  {
    'Bronze' => [[], %w[734 6 0.81 31.7 4.22]],
    'Silver' => [[:silver], %w[712 28 3.78 30.1 4.21]],
    'Gold' => [[:gold], %w[668 72 9.73 8.5 1.2]]
  }.each do |level, (traits, totals)|
    context "with #{level} level" do
      let(:template) { build(:template, *traits) }

      it 'calculates totals' do
        expect(result.values_at(:check_summ, :discount, :discount_percent, :cashback, :cashback_percent)).to eq(
          totals.map { BigDecimal(_1) }
        )
      end
    end
  end

  context 'with both level discount and cashback' do
    let(:template) { build(:template, discount: 15, cashback: 5) }

    it 'gives no discount or cashback for noloyalty' do
      expect(result[:positions].last.slice(:discount_percent, :discount_summ, :cashback, :loyal)).to eq(
        discount_percent: 0, discount_summ: 0, cashback: 0, loyal: false
      )
    end

    it 'excludes noloyalty from the amount available for write-off' do
      expect(result[:allowed_write_off]).to eq(BigDecimal('368'))
    end
  end

  context 'with fractional cashback and write-off limit' do
    let(:products) { {} }
    let(:positions) { [{ 'id' => 1, 'price' => BigDecimal('10.5'), 'quantity' => 3 }] }

    it 'keeps exact cashback and exact loyalty sum' do
      expect(result.slice(:cashback, :allowed_write_off)).to eq(
        cashback: BigDecimal('1.575'), allowed_write_off: BigDecimal('31.5')
      )
    end
  end
end
