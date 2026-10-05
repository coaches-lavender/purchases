# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

# Тесты работают на временной копии db/test.db, но без данных: таблицы очищаются ниже,
# все записи создают фабрики.
db_path = File.join(Dir.mktmpdir, 'test.db')
FileUtils.cp(File.expand_path('../db/test.db', __dir__), db_path)
ENV['DATABASE_PATH'] = db_path
ENV['APP_ENV'] = 'test'

require 'factory_bot'
require 'rack/test'
require_relative '../app'

%i[operations users products templates sqlite_sequence].each { DB[_1].delete }

# У Sequel-моделей нет save!, а save и так бросает исключение при ошибке.
FactoryBot.define { to_create(&:save) }
FactoryBot.find_definitions

# опечатка в ключе перевода роняет тест вместр "Translation missing"
I18n.exception_handler = lambda do |exception, *|
  raise exception.respond_to?(:to_exception) ? exception.to_exception : exception
end

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
  config.include Rack::Test::Methods

  config.around do |example|
    DB.transaction(rollback: :always, auto_savepoint: true) { example.run }
  end
end
