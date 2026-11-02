require "rails_helper"

RSpec.describe GenerateRowsAndBushesJob, type: :job do
  let(:vineyard) { create(:vineyard) }

  def perform(bushes_per_row)
    described_class.new.perform(vineyard.id, bushes_per_row)
  end

  describe "#perform" do
    context "with array input" do
      it "creates the correct number of rows" do
        perform([ 3, 4, 5 ])
        expect(vineyard.rows.count).to eq(3)
      end

      it "creates bushes with correct counts per row" do
        perform([ 3, 4, 5 ])
        counts = vineyard.rows.order(:row_number).map { |r| r.bushes.count }
        expect(counts).to eq([ 3, 4, 5 ])
      end

      it "numbers rows sequentially starting from 1" do
        perform([ 2, 2 ])
        expect(vineyard.rows.pluck(:row_number).sort).to eq([ 1, 2 ])
      end

      it "numbers bushes sequentially within each row" do
        perform([ 3 ])
        row = vineyard.rows.first
        expect(row.bushes.pluck(:bush_number).sort).to eq([ 1, 2, 3 ])
      end
    end

    context "with a large layout" do
      it "creates every row and bush" do
        perform(Array.new(60) { 250 })
        expect(vineyard.rows.count).to eq(60)
        expect(vineyard.bushes.count).to eq(15_000)
        expect(vineyard.rows.find_by(row_number: 60).bushes.maximum(:bush_number)).to eq(250)
      end
    end

    context "with an empty layout" do
      it "creates nothing" do
        expect { perform([]) }.not_to change(Row, :count)
      end
    end

    context "when vineyard does not exist" do
      it "is discarded without raising" do
        expect {
          described_class.perform_now(-1, [ 3 ])
        }.not_to raise_error
      end
    end
  end

  describe "a folder attached while the rows were being built" do
    # Её раскладка файлов отработала раньше, чем появились кусты, — повторяем после создания рядов
    it "re-distributes the folder's files onto the new bushes" do
      folder = create(:folder, user: vineyard.user, vineyard:)
      expect { perform([ 2 ]) }.to have_enqueued_job(DistributeMediaToBushesJob).with(folder.id)
    end

    it "does nothing extra without a folder" do
      expect { perform([ 2 ]) }.not_to have_enqueued_job(DistributeMediaToBushesJob)
    end
  end

  it "locks the vineyard while building its rows" do
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { perform([ 2 ]) }

    expect(queries.index { |sql| sql.match?(/FROM "vineyards".*FOR UPDATE/m) })
      .to be < queries.index { |sql| sql.match?(/INSERT INTO "rows"/) }
  end
end
