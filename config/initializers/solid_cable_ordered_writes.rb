# Solid Cable доставляет сообщения опросом «id > последнего прочитанного». Когда пишут несколько процессов
# (web + воркеры), запись с меньшим id может закоммититься позже записи с большим: опрос её уже проскочил,
# и сообщение до браузера не доходит. Пишем по очереди под advisory-локом транзакции: следующий процесс
# получает id только после коммита предыдущего, и порядок id совпадает с порядком коммитов
module SolidCableOrderedWrites
  # Двухключевая форма: её пространство ключей не пересекается с одноключевыми локами (миграции и т. п.)
  LOCK_KEYS = [ 0x534356, 1 ].freeze # "SCV" — Solid Cable, запись сообщений
  # Обычно лок держат миллисекунды. Дольше — держатель завис (сеть, пауза пода): не ждём его бесконечно
  LOCK_TIMEOUT = "2s"
  ATTEMPTS = 3

  def broadcast(...)
    with_write_lock { super }
  end

  def broadcast_batch(...)
    with_write_lock { super }
  end

  private

  def with_write_lock(&block)
    ATTEMPTS.times do
      return locked_transaction(&block)
    rescue ActiveRecord::LockWaitTimeout
      # следующая попытка
    end

    # Лок так и не освободился. Пишем без очереди: порядок может нарушиться, но рассылки не встают и сообщения
    # не теряются целиком (иначе BatchedBroadcaster#flush проглотил бы ошибку вместе с пачкой)
    Rails.logger.warn("Solid Cable: advisory-лок записи не получен за #{ATTEMPTS} попытки, пишем без него")
    yield
  end

  def locked_transaction
    transaction(requires_new: true) do
      conn = lease_connection
      conn.select_value("SELECT set_config('lock_timeout', $1, true)", "Solid Cable lock timeout", [ LOCK_TIMEOUT ])
      # SELECT 1 FROM: функция возвращает void, который адаптер не знает и ругается в лог на каждой рассылке
      conn.select_value("SELECT 1 FROM pg_advisory_xact_lock($1, $2)", "Solid Cable write lock", LOCK_KEYS)
      yield
    end
  end
end

Rails.application.config.to_prepare do
  SolidCable::Message.singleton_class.prepend(SolidCableOrderedWrites)
end
