# Сборка гемов: компилятор нужен только здесь (puma, json, bigdecimal собираются из исходников).
FROM ruby:3.3-alpine AS build

RUN apk add --no-cache build-base

WORKDIR /app
ENV BUNDLE_WITHOUT=development:test
COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 \
 && rm -rf /usr/local/bundle/cache /usr/local/bundle/gems/*/ext

# Итоговый образ: только Ruby, установленные гемы и код приложения.
FROM ruby:3.3-alpine

WORKDIR /app
ENV BUNDLE_WITHOUT=development:test \
    APP_ENV=production \
    RACK_ENV=production

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY Gemfile Gemfile.lock config.ru app.rb ./
COPY lib lib
COPY locales locales
COPY db db

# Приложение пишет в SQLite-базу, поэтому каталог db принадлежит непривилегированному пользователю.
RUN adduser -D app && chown -R app db
USER app

EXPOSE 9292
CMD ["bundle", "exec", "puma", "--bind", "tcp://0.0.0.0:9292", "--environment", "production"]
