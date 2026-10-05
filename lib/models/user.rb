# frozen_string_literal: true

require_relative '../db'
require_relative 'template'

class User < Sequel::Model
  many_to_one :template

  def balance
    bonus || 0
  end
end
