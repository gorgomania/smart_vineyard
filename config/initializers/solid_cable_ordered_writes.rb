# Solid Cable доставляет сообщения опросом «id > последнего прочитанного». Когда пишут несколько процессов
# (web + воркеры), запись с меньшим id может закоммититься позже записи с большим: опрос её уже проскочил,
# и сообщение до браузера не доходит. Пишем по очереди под advisory-локом транзакции: следующий процесс
# получает id только после коммита предыдущего, и порядок id совпадает с порядком коммитов
module SolidCableOrderedWrites
  LOCK_KEY = Zlib.crc32("solid_cable_messages")

  def broadcast(...)
    with_write_lock { super }
  end

  def broadcast_batch(...)
    with_write_lock { super }
  end

  private

  def with_write_lock
    transaction do
      connection.execute(sanitize_sql_array([ "SELECT pg_advisory_xact_lock(?)", LOCK_KEY ]))
      yield
    end
  end
end

Rails.application.config.to_prepare do
  SolidCable::Message.singleton_class.prepend(SolidCableOrderedWrites)
end
