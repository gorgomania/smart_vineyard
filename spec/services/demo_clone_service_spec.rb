require "rails_helper"

RSpec.describe DemoCloneService do
  let(:master) { create(:user) }

  def clone
    described_class.new(master).clone
  end

  def setup_vineyard(name, deleted: false)
    vineyard = create(:vineyard, user: master, name:)
    row = create(:row, vineyard:, row_number: 1)
    create(:bush, vineyard:, row:, bush_number: 1)
    vineyard.update_column(:deleted_at, Time.current) if deleted
    vineyard
  end

  describe "#clone" do
    it "creates a temporary confirmed demo user" do
      demo = clone

      expect(demo).to be_demo_temp
      expect(demo).to be_confirmed
      expect(demo.demo_expires_at).to be > 23.hours.from_now
    end

    it "copies active vineyards, leaving their rows and bushes to the job" do
      setup_vineyard("Живой")
      demo = clone

      vineyard = demo.vineyards.sole
      expect(vineyard.name).to eq("Живой")
      expect(vineyard.deleted_at).to be_nil
      expect(vineyard.rows).to be_empty

      perform_enqueued_jobs(only: CloneDemoDataJob)
      expect(vineyard.rows.count).to eq(1)
      expect(vineyard.bushes.count).to eq(1)
    end

    it "skips vineyards soft-deleted by the master" do
      setup_vineyard("Живой")
      setup_vineyard("Удалённый", deleted: true)

      expect(clone.vineyards.pluck(:name)).to eq([ "Живой" ])
    end

    it "keeps a folder linked to a deleted vineyard but without the link" do
      deleted = setup_vineyard("Удалённый", deleted: true)
      create(:folder, user: master, title: "Фото", vineyard: deleted)

      folder = clone.folders.find_by!(title: "Фото")
      expect(folder.vineyard_id).to be_nil
    end

    it "copies every row and bush with the same numbers into the right vineyard" do
      big = create(:vineyard, user: master, name: "Большой")
      small = setup_vineyard("Малый")
      [ 1, 2, 5 ].each do |row_number|
        row = create(:row, vineyard: big, row_number:)
        (1..row_number).each { |bush_number| create(:bush, vineyard: big, row:, bush_number:) }
      end
      layout = ->(vineyard) { vineyard.bushes.joins(:row).order("rows.row_number", :bush_number).pluck("rows.row_number", :bush_number) }

      demo = clone
      perform_enqueued_jobs(only: CloneDemoDataJob)

      expect(layout.(demo.vineyards.find_by!(name: "Большой"))).to eq(layout.(big))
      expect(layout.(demo.vineyards.find_by!(name: "Малый"))).to eq(layout.(small))
      expect(Bush.where(vineyard: demo.vineyards).pluck(:row_id, :vineyard_id))
        .to all(satisfy { |row_id, vineyard_id| Row.find(row_id).vineyard_id == vineyard_id })
    end

    it "enqueues CloneDemoDataJob with the vineyard map, not a map of every bush" do
      vineyard = setup_vineyard("Живой")
      demo = clone

      expect(CloneDemoDataJob).to have_been_enqueued.with(
        demo.id, {}, vineyard_map: { vineyard.id.to_s => demo.vineyards.sole.id }
      )
    end

    # Сервис и задача вместе: файл мастера на кусте оказывается на том же кусте клона
    it "ends with the demo copy of a file linked to the matching demo bush" do
      vineyard = setup_vineyard("Живой")
      folder = create(:folder, user: master, vineyard:)
      create(:media_item, :with_image, folder:, bush: vineyard.bushes.sole)

      demo = clone
      perform_enqueued_jobs(only: CloneDemoDataJob)

      copy = MediaItem.joins(:folder).where(folders: { user_id: demo.id }).sole
      expect(copy.bush).to eq(demo.vineyards.sole.bushes.sole)
    end
  end
end
