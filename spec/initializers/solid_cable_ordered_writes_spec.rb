require "rails_helper"

RSpec.describe SolidCableOrderedWrites do
  let(:message) { SolidCable::BatchedBroadcaster::Message.new(channel: "spec", payload: "x") }

  # Отдельное соединение — как другой процесс, который сейчас пишет сообщение и ещё не закоммитил
  def other_writer_connection
    config = SolidCable::Message.connection_db_config.configuration_hash
    PG.connect(dbname: config[:database], user: config[:username], password: config[:password],
               host: config[:host], port: config[:port])
  end

  it "makes a broadcast wait until the other writer commits" do
    other = other_writer_connection
    other.exec("SELECT pg_advisory_lock(#{described_class::LOCK_KEY})")

    writer = Thread.new { SolidCable::Message.broadcast_batch([ message ]) }
    expect(writer.join(0.3)).to be_nil

    other.exec("SELECT pg_advisory_unlock(#{described_class::LOCK_KEY})")
    expect(writer.join(5)).to eq(writer)
    expect(SolidCable::Message.where(channel: "spec").count).to eq(1)
  ensure
    other&.close
  end
end
