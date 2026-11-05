require "rails_helper"

RSpec.describe SyncRowsAndBushesJob, type: :job do
  let(:vineyard) { create(:vineyard) }

  def setup_rows(bushes_per_row)
    bushes_per_row.each_with_index do |count, i|
      row = create(:row, vineyard:, row_number: i + 1)
      count.times { |j| create(:bush, vineyard:, row:, bush_number: j + 1) }
    end
  end

  def perform(new_bushes_per_row)
    described_class.new.perform(vineyard.id, new_bushes_per_row)
  end

  describe "#perform" do
    it "refreshes open stats and heatmap of the vineyard" do
      setup_rows([ 3 ])
      allow(Vineyard).to receive(:broadcast_diagnoses_changed)

      perform([ 2 ])
      expect(Vineyard).to have_received(:broadcast_diagnoses_changed).with(vineyard.id)
    end

    context "on a new vineyard" do
      it "creates the rows with their bushes, numbered from 1" do
        perform([ 3, 4, 5 ])

        counts = vineyard.rows.order(:row_number).map { |row| [ row.row_number, row.bushes.pluck(:bush_number).sort ] }
        expect(counts).to eq([ [ 1, [ 1, 2, 3 ] ], [ 2, [ 1, 2, 3, 4 ] ], [ 3, [ 1, 2, 3, 4, 5 ] ] ])
      end

      it "creates every row and bush of a large layout" do
        perform(Array.new(60) { 250 })
        expect(vineyard.rows.count).to eq(60)
        expect(vineyard.bushes.count).to eq(15_000)
        expect(vineyard.rows.find_by(row_number: 60).bushes.maximum(:bush_number)).to eq(250)
      end

      it "does not create a row with no bushes" do
        perform([ 2, 0, 3 ])
        expect(vineyard.rows.pluck(:row_number)).to contain_exactly(1, 3)
      end

      it "creates nothing for an empty layout" do
        expect { perform([]) }.not_to change(Row, :count)
      end

      # Создали и сразу поправили: задача правки могла успеть первой
      it "changes nothing when run again with the same layout" do
        perform([ 3, 4 ])
        expect { perform([ 3, 4 ]) }.not_to change { vineyard.bushes.pluck(:id).sort }
        expect(vineyard.rows.count).to eq(2)
      end

      # Её раскладка файлов отработала раньше, чем появились кусты
      it "re-distributes the files of a folder attached while the rows were being built" do
        folder = create(:folder, user: vineyard.user, vineyard:)
        expect { perform([ 2 ]) }.to have_enqueued_job(DistributeMediaToBushesJob).with(folder.id)
      end

      it "does not distribute anything without a folder" do
        expect { perform([ 2 ]) }.not_to have_enqueued_job(DistributeMediaToBushesJob)
      end
    end

    context "adding bushes to an existing row" do
      before { setup_rows([ 3 ]) }

      it "increases bush count in the row" do
        perform([ 5 ])
        expect(vineyard.rows.find_by(row_number: 1).bushes.count).to eq(5)
      end
    end

    context "removing bushes from an existing row" do
      before { setup_rows([ 5 ]) }

      it "decreases bush count in the row" do
        perform([ 3 ])
        expect(vineyard.rows.find_by(row_number: 1).bushes.count).to eq(3)
      end
    end

    context "adding a new row" do
      before { setup_rows([ 3 ]) }

      it "creates the new row" do
        perform([ 3, 4 ])
        expect(vineyard.rows.count).to eq(2)
        expect(vineyard.rows.find_by(row_number: 2).bushes.count).to eq(4)
      end
    end

    context "removing a row (count = 0)" do
      before { setup_rows([ 3, 4 ]) }

      it "destroys the row" do
        perform([ 3, 0 ])
        expect(vineyard.rows.where(row_number: 2)).to be_empty
      end
    end

    context "when a removed bush or row had a media item" do
      before { setup_rows([ 3, 2 ]) }

      it "keeps the media item but unlinks it" do
        trimmed = create(:media_item, bush: vineyard.rows.find_by(row_number: 1).bushes.find_by(bush_number: 3))
        in_removed_row = create(:media_item, bush: vineyard.rows.find_by(row_number: 2).bushes.first)

        perform([ 2, 0 ])

        expect(trimmed.reload.bush_id).to be_nil
        expect(in_removed_row.reload.bush_id).to be_nil
      end
    end

    context "when an existing row has no bushes yet" do
      before { setup_rows([ 0 ]) }

      it "fills it instead of failing on a duplicate row" do
        perform([ 2 ])
        expect(vineyard.rows.count).to eq(1)
        expect(vineyard.rows.first.bushes.pluck(:bush_number).sort).to eq([ 1, 2 ])
      end
    end

    context "when bush numbers have gaps" do
      before do
        row = create(:row, vineyard:, row_number: 1)
        [ 1, 2, 5 ].each { |n| create(:bush, vineyard:, row:, bush_number: n) }
      end

      it "continues numbering after the highest number" do
        perform([ 7 ])
        expect(vineyard.rows.first.bushes.pluck(:bush_number).sort).to eq([ 1, 2, 5, 6, 7 ])
      end
    end

    context "with many rows and bushes" do
      before { setup_rows([ 2, 2 ]) }

      it "applies a large layout in bulk" do
        perform(Array.new(50) { 200 })
        expect(vineyard.rows.count).to eq(50)
        expect(vineyard.bushes.count).to eq(10_000)
      end
    end

    context "with an empty layout" do
      before { setup_rows([ 3, 4 ]) }

      it "keeps existing rows and bushes" do
        expect { perform([]) }.not_to change { vineyard.bushes.count }
        expect(vineyard.rows.count).to eq(2)
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

  # Две задачи раскладки одного виноградника идут по очереди: блокировка виноградника — до чтения его рядов,
  # тогда вторая задача читает ряды уже после первой, а не тот же снимок
  it "locks the vineyard before reading its rows" do
    setup_rows([ 3 ])
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { perform([ 4 ]) }

    lock = queries.index { |sql| sql.match?(/FROM "vineyards".*FOR UPDATE/m) }
    rows_read = queries.index { |sql| sql.include?('MAX(bushes.bush_number)') }
    expect(lock).to be_present
    expect(lock).to be < rows_read
  end
end
