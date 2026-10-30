require "rails_helper"

RSpec.describe SolidCableOrderedWrites do
  let(:message) { SolidCable::BatchedBroadcaster::Message.new(channel: "spec", payload: "x") }

  # Отдельное соединение — как другой процесс, который сейчас пишет сообщение и ещё не закоммитил
  def other_writer_connection
    config = SolidCable::Message.connection_db_config.configuration_hash
    PG.connect(dbname: config[:database], user: config[:username], password: config[:password],
               host: config[:host], port: config[:port])
  end

  def hold_lock(conn)
    conn.exec_params("SELECT pg_advisory_lock($1, $2)", described_class::LOCK_KEYS)
  end

  def release_lock(conn)
    conn.exec_params("SELECT pg_advisory_unlock($1, $2)", described_class::LOCK_KEYS)
  end

  it "makes a broadcast wait until the other writer commits" do
    other = other_writer_connection
    hold_lock(other)

    writer = Thread.new { SolidCable::Message.broadcast_batch([ message ]) }
    expect(writer.join(0.3)).to be_nil

    release_lock(other)
    expect(writer.join(5)).to eq(writer)
    expect(SolidCable::Message.where(channel: "spec").count).to eq(1)
  ensure
    other&.close
  end

  it "writes without the lock instead of hanging when the holder is stuck" do
    stub_const("#{described_class}::LOCK_TIMEOUT", "50ms")
    other = other_writer_connection
    hold_lock(other)

    writer = Thread.new { SolidCable::Message.broadcast_batch([ message ]) }
    expect(writer.join(5)).to eq(writer)
    expect(SolidCable::Message.where(channel: "spec").count).to eq(1)
  ensure
    other&.close
  end
end
