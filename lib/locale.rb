# frozen_string_literal: true

require 'i18n'

I18n.load_path += Dir[File.expand_path('../locales/*.yml', __dir__)]
I18n.available_locales = [:ru]
I18n.default_locale = :ru
