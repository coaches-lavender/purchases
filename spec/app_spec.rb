# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe 'API', :aggregate_failures do
  # метод для Rack::Test: его вызывают post и last_response
  def app
    App
  end

  # пользователь Bronze с балансом 10000
  let(:user) { create(:user) }
  let(:another_user) { create(:user) }

  def post_json(path, body)
    post path, body.to_json, 'CONTENT_TYPE' => 'application/json'
    JSON.parse(last_response.body, decimal_class: BigDecimal)
  end

  describe 'POST /operation' do
    subject(:calculation) { post_json('/operation', user_id:, positions:) }

    let(:user_id) { user.id }
    let(:positions) do
      [
        { id: 1_000, price: 100, quantity: 3 }, # товар без правил: его нет в products
        { id: create(:product, :increased_cashback).id, price: 50, quantity: 2 },
        { id: create(:product, :discount).id, price: 40, quantity: 1 },
        { id: create(:product, :noloyalty).id, price: 150, quantity: 2 }
      ]
    end

    it 'calculates operation and saves it' do
      expect(calculation).to include(
        'status' => 200,
        'user' => {
          'id' => user.id, 'name' => user.name, 'level' => 'Bronze', 'bonus' => BigDecimal('10000.0')
        },
        'check_summ' => BigDecimal('734.0'),
        'bonuses' => {
          'balance' => BigDecimal('10000.0'), 'allowed_write_off' => BigDecimal('434.0'),
          'cashback_percent' => BigDecimal('4.22'), 'cashback' => 31
        },
        'discounts' => { 'discount' => BigDecimal('6.0'), 'discount_percent' => BigDecimal('0.81') }
      )
      expect(last_response.status).to eq(200)
      expect(calculation['positions'][2]).to eq(
        'id' => positions[2][:id], 'price' => BigDecimal('40.0'), 'quantity' => BigDecimal('1.0'),
        'type' => 'discount', 'value' => BigDecimal('15.0'), 'description' => 'Дополнительная скидка 15%',
        'discount_percent' => BigDecimal('15.0'), 'discount_summ' => BigDecimal('6.0')
      )
      expect(Operation[calculation['operation_id']]).to have_attributes(
        done: false, check_summ: 734, allowed_write_off: 434, cashback: BigDecimal('31.7')
      )
      expect(calculation['positions'].map { _1['description'] }).to contain_exactly(
        nil, 'Дополнительный кэшбек 10%', 'Дополнительная скидка 15%', 'Не участвует в системе лояльности'
      )
    end

    context 'when loyalty sum is fractional' do
      let(:positions) { [{ id: create(:product, :increased_cashback).id, price: 10.99, quantity: 1 }] }

      it 'stores exact sum as distribution base and returns whole-point limit' do
        expect(calculation.dig('bonuses', 'allowed_write_off')).to eq(10)
        expect(Operation[calculation['operation_id']].allowed_write_off).to eq(BigDecimal('10.99'))
      end
    end

    it 'limits write-off by user balance' do
      user.update(bonus: 100)
      expect(calculation.dig('bonuses', 'allowed_write_off')).to eq(BigDecimal('100.0'))
    end

    it 'rounds write-off limit down after limiting by fractional balance' do
      user.update(bonus: BigDecimal('10.5'))
      limit = calculation.dig('bonuses', 'allowed_write_off')
      expect(limit).to eq(10)

      submission = { user: { id: user.id }, operation_id: calculation['operation_id'], write_off: limit }
      expect(post_json('/submit', submission)['status']).to eq(200)
    end

    context 'when user does not exist' do
      let(:user_id) { 999 }

      it 'returns 404' do
        expect(calculation).to eq('status' => 404, 'message' => 'Пользователь не найден')
        expect(last_response.status).to eq(404)
      end
    end

    {
      'with negative price' => [
        [{ id: 1, price: -1, quantity: 1 }],
        ['Параметр positions[0].price не может быть отрицательным']
      ],
      'with negative quantity' => [
        [{ id: 1, price: 1, quantity: -1 }],
        ['Параметр positions[0].quantity не может быть отрицательным']
      ],
      'with zero quantity' => [
        [{ id: 1, price: 1, quantity: 0 }],
        ['Параметр positions[0].quantity должен быть больше 0']
      ],
      'with non-integer id in second position' => [
        [{ id: 1, price: 1, quantity: 1 }, { id: 'abc', price: 1, quantity: 1 }],
        ['Параметр positions[1].id должен быть целым числом']
      ],
      'with a position that is not an object' => [
        [{ id: 1, price: 1, quantity: 1 }, 5],
        ['Некорректная позиция positions[1]']
      ],
      'with non-numeric price' => [
        [{ id: 1, price: 'foo', quantity: 1 }],
        ['Параметр positions[0].price должен быть числом']
      ],
      'with empty positions' => [
        [],
        ['Передайте непустой массив positions']
      ],
      'with errors in several positions' => [
        [{ price: 'x', quantity: 1 }, { id: 2, price: 1 }, 5],
        [
          'Параметр positions[0].id должен быть целым числом',
          'Параметр positions[0].price должен быть числом',
          'Параметр positions[1].quantity должен быть числом',
          'Некорректная позиция positions[2]'
        ]
      ]
    }.each do |description, (invalid_positions, errors)|
      context description do
        let(:positions) { invalid_positions }

        it 'returns 400 with list of errors' do
          expect(calculation).to eq(
            'status' => 400, 'message' => 'Некорректные параметры запроса', 'errors' => errors
          )
          expect(last_response.status).to eq(400)
        end
      end
    end

    context 'when numbers are passed as strings' do
      let(:user_id) { user.id.to_s }
      let(:positions) { [{ id: '1', price: '100', quantity: '3' }] }

      it 'rejects them' do
        expect(calculation['errors']).to contain_exactly(
          'Параметр user_id должен быть целым числом',
          'Параметр positions[0].id должен быть целым числом',
          'Параметр positions[0].price должен быть числом',
          'Параметр positions[0].quantity должен быть числом'
        )
      end
    end

    context 'when numbers have zero fractional part' do
      let(:user_id) { user.id.to_f }
      let(:positions) { [{ id: 1_000.0, price: 100.0, quantity: 3.0 }] }

      it 'rejects them for ids but accepts them for price and quantity' do
        expect(calculation['errors']).to contain_exactly(
          'Параметр user_id должен быть целым числом', 'Параметр positions[0].id должен быть целым числом'
        )
      end
    end

    context 'when position cost has more than 2 decimal places' do
      let(:positions) { [{ id: 1_000, price: 0.125, quantity: 3 }, { id: 1_001, price: 10.12, quantity: 0.333 }] }

      it 'rounds each position cost to kopecks' do
        expect(calculation['positions'].first['price']).to eq(BigDecimal('0.125'))
        expect(calculation['check_summ']).to eq(BigDecimal('3.75')) # 0.375 → 0.38, 3.36996 → 3.37
      end
    end

    context 'when prices are fractional' do
      let(:positions) { [{ id: 1_000, price: 0.1, quantity: 3 }] }

      it 'calculates them exactly' do
        expect(calculation['check_summ']).to eq(BigDecimal('0.3'))
      end
    end

    context 'when numbers are invalid' do
      let(:user_id) { 1.5 }
      let(:positions) do
        [
          { id: 2.5, price: 'foo', quantity: 'foo' },
          { id: 0, price: -1, quantity: 0 },
          { id: -1, price: 1, quantity: 1 }
        ]
      end

      it 'distinguishes non-integer, non-positive, non-numeric and negative values' do
        expect(calculation['errors']).to contain_exactly(
          'Параметр user_id должен быть целым числом',
          'Параметр positions[0].id должен быть целым числом',
          'Параметр positions[0].price должен быть числом',
          'Параметр positions[0].quantity должен быть числом',
          'Параметр positions[1].id должен быть больше 0',
          'Параметр positions[1].price не может быть отрицательным',
          'Параметр positions[1].quantity должен быть больше 0',
          'Параметр positions[2].id должен быть больше 0'
        )
      end
    end

    context 'when both user and positions are invalid' do
      let(:user_id) { 0 }
      let(:positions) { nil }

      it 'collects all errors together' do
        expect(calculation['errors']).to contain_exactly(
          'Параметр user_id должен быть больше 0', 'Передайте непустой массив positions'
        )
      end
    end

    it 'accepts JSON without Content-Type header' do
      post '/operation', { user_id: user.id, positions: }.to_json
      expect(last_response.status).to eq(200)
    end

    it 'returns 400 for malformed JSON' do
      post '/operation', '{oops', 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(400)
    end
  end

  describe 'POST /submit' do
    subject(:submit) { post_json('/submit', user: user_params, operation_id:, write_off:) }

    # операция создаётся заранее, чтобы before мог менять баланс уже после неё
    let!(:operation_id) { create(:operation, user_id: user.id).id }
    let(:user_params) { { id: user.id } }
    let(:write_off) { 150 }

    it 'confirms operation with a write-off and recalculates cashback' do
      expect(submit).to eq(
        'status' => 200,
        'message' => 'Операция успешно подтверждена',
        'operation' => {
          'id' => operation_id, 'user_id' => user.id,
          'cashback' => BigDecimal('20'), 'cashback_percent' => BigDecimal('3.42'),
          'discount' => BigDecimal('6.0'), 'discount_percent' => BigDecimal('0.81'),
          'write_off' => BigDecimal('150.0'), 'check_summ' => BigDecimal('584.0')
        }
      )
      expect(last_response.status).to eq(200)
      expect(user.refresh.bonus).to eq(BigDecimal('9870'))
      expect(Operation[operation_id]).to have_attributes(done: true, write_off: 150)
    end

    it 'returns previous result for retry with same write-off and keeps balance' do
      first = submit
      expect(post_json('/submit', user: user_params, operation_id:, write_off: 150)).to eq(first)
      expect(last_response.status).to eq(200)
      expect(user.refresh.bonus).to eq(BigDecimal('9870'))
    end

    it 'rejects repeated confirmation with different write-off' do
      submit
      expect(post_json('/submit', user: user_params, operation_id:, write_off: 100)['message']).to eq(
        'Операция уже подтверждена с другим списанием'
      )
      expect(last_response.status).to eq(422)
      expect(user.refresh.bonus).to eq(BigDecimal('9870'))
    end

    context 'when exact cashback is just below a whole point' do
      # как после /operation для товара за 399.8: точный кэшбек 5% = 19.99 балла
      let!(:operation_id) do
        create(
          :operation,
          user_id: user.id, cashback: BigDecimal('19.99'), cashback_percent: BigDecimal('4.75'),
          discount: 0, discount_percent: 0, check_summ: BigDecimal('399.8'), allowed_write_off: BigDecimal('399.8')
        ).id
      end
      let(:write_off) { 10 }

      it 'rounds only the final cashback' do
        expect(submit.dig('operation', 'cashback')).to eq(19) # floor(19.99 × (1 − 10/399.8)) = floor(19.49)
      end
    end

    context 'when loyalty sum is fractional' do
      # как после /operation для Bronze и товара с доп. кэшбеком 10% за 10.99: 15% = 1.6485 балла
      let!(:operation_id) do
        create(
          :operation,
          user_id: user.id, cashback: BigDecimal('1.6485'), cashback_percent: 0,
          discount: 0, discount_percent: 0, check_summ: BigDecimal('10.99'), allowed_write_off: BigDecimal('10.99')
        ).id
      end
      let(:write_off) { 4 }

      it 'distributes write-off over exact sum' do
        expect(submit.dig('operation', 'cashback')).to eq(1) # floor(1.6485 × (1 − 4/10.99)) = floor(1.0485)
      end

      it 'rejects write-off above whole-point limit' do
        response = post_json('/submit', user: user_params, operation_id:, write_off: 11)
        expect(response['message']).to eq('Списание превышает доступную сумму')
      end
    end

    context 'without write-off' do
      let(:write_off) { 0 }

      it 'accrues full cashback' do
        expect(submit.dig('operation', 'cashback')).to eq(BigDecimal('31'))
        expect(user.refresh.bonus).to eq(BigDecimal('10031'))
      end
    end

    context 'when write-off exceeds products limit' do
      let(:write_off) { 435 }

      it 'returns 422' do
        expect(submit['message']).to eq('Списание превышает доступную сумму')
        expect(last_response.status).to eq(422)
      end
    end

    context 'when write-off exceeds balance' do
      let(:write_off) { 11 }

      before { user.update(bonus: 10) }

      it 'returns 422' do
        expect(submit['message']).to eq('Недостаточно бонусов')
      end
    end

    context 'when operation belongs to another user' do
      let(:user_params) { { id: another_user.id } }

      it 'does not find it' do
        expect(submit['message']).to eq('Операция не найдена')
        expect(last_response.status).to eq(404)
      end
    end

    context 'when write-off is fractional' do
      let(:write_off) { 150.0 }

      it 'returns 400' do
        expect(submit['errors']).to contain_exactly('Параметр write_off должен быть целым числом')
      end
    end

    context 'when write-off is negative' do
      let(:write_off) { -1 }

      it 'returns 400' do
        submit
        expect(last_response.status).to eq(400)
      end
    end

    context 'when numbers are passed as strings' do
      let(:operation_id) { super().to_s }
      let(:user_params) { { id: user.id.to_s } }
      let(:write_off) { '150' }

      it 'rejects them' do
        expect(submit['errors']).to contain_exactly(
          'Параметр user.id должен быть целым числом',
          'Параметр operation_id должен быть целым числом',
          'Параметр write_off должен быть целым числом'
        )
      end
    end

    context 'when all parameters are invalid' do
      let(:operation_id) { 'x' }
      let(:user_params) { 1 }
      let(:write_off) { -1 }

      it 'returns all errors' do
        expect(submit['errors']).to contain_exactly(
          'Параметр user.id должен быть целым числом',
          'Параметр operation_id должен быть целым числом',
          'Параметр write_off не может быть отрицательным'
        )
      end
    end
  end
end
