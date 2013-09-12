FactoryGirl.define do
  factory :audio_file do

    association :item, factory: :item

    factory :audio_file_private do
      association :item, factory: :item_private
    end

    after(:create) { |af| af.update_file!('test.mp3', 0) }
  end
end
