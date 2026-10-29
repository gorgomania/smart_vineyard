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

    it "copies active vineyards with their rows and bushes" do
      setup_vineyard("Живой")
      demo = clone

      vineyard = demo.vineyards.sole
      expect(vineyard.name).to eq("Живой")
      expect(vineyard.deleted_at).to be_nil
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

    it "enqueues CloneDemoMediaJob for the demo user" do
      expect { clone }.to have_enqueued_job(CloneDemoMediaJob)
    end
  end
end
