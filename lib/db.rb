# frozen_string_literal: true

require 'sequel'

DB = Sequel.sqlite(ENV.fetch('DATABASE_PATH', File.expand_path('../db/test.db', __dir__)))
