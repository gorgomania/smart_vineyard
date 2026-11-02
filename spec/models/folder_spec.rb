require "rails_helper"

RSpec.describe Folder, type: :model do
  let(:user) { create(:user) }
  subject(:folder) { build(:folder, user:) }

  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:parent).optional }
    it { is_expected.to belong_to(:vineyard).optional }
    it { is_expected.to have_many(:children).dependent(:destroy) }
    it { is_expected.to have_many(:media_items).dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:title).with_message("Имя не может быть пустым") }
    it { is_expected.to validate_length_of(:title).is_at_most(15).with_message("Длина не более 15 символов") }
    it { is_expected.to validate_uniqueness_of(:title).scoped_to(:parent_id, :user_id).with_message("Имя папки уже используется") }

    it "allows two folders with the same name under different users" do
      create(:folder, user:, title: "Photos")
      other = build(:folder, user: create(:user), title: "Photos")
      expect(other).to be_valid
    end

    it "prevents two folders from linking to the same vineyard" do
      vineyard = create(:vineyard, user:)
      create(:folder, user:, vineyard:)
      duplicate = build(:folder, user:, title: "Other", vineyard:)
      expect(duplicate).not_to be_valid
    end

    it "enforces one folder per vineyard at the database level" do
      vineyard = create(:vineyard, user:)
      create(:folder, user:, vineyard:)
      other = create(:folder, user:, title: "Other")
      expect { other.update_column(:vineyard_id, vineyard.id) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "turns a unique index race into a validation error" do
      vineyard = create(:vineyard, user:)
      create(:folder, user:, vineyard:)
      other = create(:folder, user:, title: "Other")
      allow(other).to receive(:vineyard_id_present?).and_return(false) # валидация «не успела» увидеть занятый виноградник

      expect(other.update(vineyard:)).to be false
      expect(other.errors).to be_added(:vineyard_id, :taken)
    end

    # Две вкладки создают папку с одним именем: обе проходят валидацию, второй INSERT упирается в индекс
    it "turns a title race into the form error, for nested and root folders" do
      parent = create(:folder, user:)
      create(:folder, user:, parent:, title: "Same")
      nested = build(:folder, user:, parent:, title: "Same")
      expect(nested.save(validate: false)).to be false
      expect(nested.errors[:title]).to eq([ "Имя папки уже используется" ])

      root = build(:folder, user:, title: parent.title)
      expect(root.save(validate: false)).to be false
      expect(root.errors[:title]).to eq([ "Имя папки уже используется" ])
    end
  end

  describe "#title_path" do
    it "returns just the title for a root folder" do
      expect(folder.title_path).to eq([ folder.title ])
    end

    it "returns full path for a nested folder" do
      parent = create(:folder, user:, title: "Root")
      child  = create(:folder, user:, title: "Child", parent:)
      expect(child.title_path).to eq([ "Root", "Child" ])
    end
  end

  describe "#id_path" do
    it "returns full id path for a nested folder" do
      parent = create(:folder, user:, title: "Root")
      child  = create(:folder, user:, title: "Child", parent:)
      expect(child.id_path).to eq([ parent.id, child.id ])
    end
  end
end
