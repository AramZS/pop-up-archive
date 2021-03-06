require 'spec_helper'
require 'ostruct'

describe User do

  let(:user) { FactoryGirl.create :user }
  before { StripeMock.start }
  after { StripeMock.stop }


  it 'gets a holding collection automatically' do
    user.uploads_collection.should_not be_nil
  end

  context 'oauth' do
    it 'applies oauth info' do
      auth = OpenStruct.new(provider: 'foo', uid: 'bar', info: OpenStruct.new(name: 'test', email: 'test@popuparchive.org'))
      user.apply_oauth(auth)
      user.email.should eq 'test@popuparchive.org'
    end
  end

  context 'usage' do

    let(:org_user) {
      now = DateTime.now
      ou = FactoryGirl.create :organization_user
      ou.organization.monthly_usages.create(use: 'test', year: now.year, month: now.month, value: 10)
      ou
    }

    let(:audio_file) { FactoryGirl.create(:audio_file_private) }

    it 'gets usage for current month' do
      user.usage_for('test').should == 0
    end

    it 'does not confuse Org with User usage' do
      org_user.usage_for('test').should == 0
    end

    it 'gets org usage for current month' do
      org_user.organization.usage_for('test').should == 10
    end

    it 'gets usage for different month' do
      org_user.usage_for('test', 1.month.ago).should == 0
    end

    it 'updates usage' do
      time = DateTime.now
      user.usage_for('test', time).to_i.should == 0
      user.update_usage_for('test', {:seconds => 100, :cost => 0, :retail_cost => 0}, time)
      user.usage_for('test', time).should eq 100
      user.update_usage_for('test', {:seconds => 1000, :cost => 1234, :retail_cost => 5678}, time)
      user.usage_for('test', time).should eq 1000
    end

    it "counts deleted audio toward monthly usage" do
      audio_persist = FactoryGirl.create(:audio_file_private)
      audio_deleted = FactoryGirl.create(:audio_file_private)
      audio_persist_transcript = FactoryGirl.create :transcript
      audio_deleted_transcript = FactoryGirl.create :transcript
      # factory transcripts are created as orphans. must assign audio explicitly.
      audio_persist_transcript.audio_file_id = audio_persist.id
      audio_persist_transcript.transcriber = Transcriber.basic
      audio_deleted_transcript.audio_file_id = audio_deleted.id
      audio_deleted_transcript.transcriber = Transcriber.basic
      # nice round numbers
      audio_persist.duration = 3600
      audio_deleted.duration = 3600
      audio_persist_transcript.save!
      audio_deleted_transcript.save!
      audio_persist.save!
      audio_deleted.save!
      audio_persist_user = audio_persist.item.collection.billable_to
      audio_deleted_user = audio_deleted.item.collection.billable_to
      #STDERR.puts "audio_persist = #{audio_persist.inspect}"
      #STDERR.puts "audio_persist.user = #{audio_persist.user.inspect}"
      #STDERR.puts "audio_persist.item.collection.billable_to = #{audio_persist.item.collection.billable_to.inspect}"
      #STDERR.puts "audio_deleted = #{audio_deleted.inspect}"
      #STDERR.puts "audio_deleted.user = #{audio_deleted.user.inspect}"
      #STDERR.puts "audio_deleted.item.collection.billable_to = #{audio_deleted.item.collection.billable_to.inspect}"
      #STDERR.puts "audio_persist_transcript = #{audio_persist_transcript.inspect}"
      #STDERR.puts "audio_deleted_transcript = #{audio_deleted_transcript.inspect}"
      audio_persist_transcript.billable_seconds.should eq 3600
      audio_deleted_transcript.billable_seconds.should eq 3600
      audio_persist_transcript.billable_to.should eq audio_persist_user
      audio_deleted_transcript.billable_to.should eq audio_deleted_user
      Rails.logger.warn("-------------------------------- TEST FIXTURES COMPLETE ----------------------------------")

      audio_persist_user.calculate_monthly_usages!
      audio_deleted_user.calculate_monthly_usages!
      audio_persist_user.update_usage_report!
      audio_deleted_user.update_usage_report!
      #STDERR.puts audio_persist_user.usage_summary.inspect
      Rails.logger.warn("-------------------------------- TEST SETUP COMPLETE ----------------------------------")

      audio_persist_user.usage_summary[:this_month][:hours].should eq 1.0
      audio_deleted_user.usage_summary[:this_month][:hours].should eq 1.0
      audio_deleted.destroy # soft-delete and test again
      audio_deleted_user.calculate_monthly_usages!
      audio_deleted_user.update_usage_report!
      audio_deleted_user.usage_summary[:this_month][:hours].should eq 1.0
      #STDERR.puts "audio_deleted = #{audio_deleted.inspect}"
      Rails.logger.warn("-------------------------------- DELETED AUDIO TEST COMPLETE ----------------------------------")
            
    end

    it "counts deleted collection toward monthly usage" do
      audio = FactoryGirl.create(:audio_file_private)
      audio.duration = 3600
      transcript = FactoryGirl.create :transcript
      transcript.transcriber = Transcriber.basic
      transcript.audio_file_id = audio.id
      transcript.save!
      audio.save!
      collection = audio.item.collection
      audio.billable_to.collections << collection
      transcript.billable_seconds.should eq 3600
      #Rails.logger.warn("collection_grants == #{collection.collection_grants.inspect}")
      #Rails.logger.warn("audio.billable_to = #{audio.billable_to.inspect}")
      #Rails.logger.warn("collection.billable_to = #{collection.billable_to.inspect}")
      #Rails.logger.warn("-------------------------------- TEST FIXTURES COMPLETE ----------------------------------")

      # before and after delete should match
      user = audio.billable_to
      user.calculate_monthly_usages!
      user.update_usage_report!
      user.usage_summary[:this_month][:hours].should eq 1.0
      #Rails.logger.warn("-------------------------------- BEFORE TEST COMPLETE ----------------------------------")

      # delete and try again
      audio.item.collection.destroy

      user.calculate_monthly_usages!
      user.update_usage_report!
      user.usage_summary[:this_month][:hours].should eq 1.0
      #Rails.logger.warn("-------------------------------- DELETED COLLECTION TEST COMPLETE ----------------------------------")
    end

  end

  context 'storage' do
    it 'meters storage' do
      user.used_metered_storage.should eq 0
      user.used_unmetered_storage.should eq 0
    end

    context 'reports' do
      let(:user_slightly_over) { FactoryGirl.create :user, pop_up_hours_cache: 2, used_metered_storage_cache: 2.hours + 30.minutes }
      let(:user_very_over) { FactoryGirl.create :user, pop_up_hours_cache: 2, used_metered_storage_cache: 31.hours }
      let(:user_not_over) { FactoryGirl.create :user, pop_up_hours_cache: 2, used_metered_storage_cache: 1.hours + 21.minutes }

      it 'gets over limit users using cached calculations' do
        User.over_limits.should include(user_slightly_over)
        User.over_limits.should include(user_very_over)
      end

      it 'orders from most to least egregious' do
        user_very_over; user_slightly_over
        User.over_limits.first.should eq user_very_over
        User.over_limits.second.should eq user_slightly_over
      end

      it 'does not include users who have not crossed their limit' do
        User.over_limits.should_not include(user_not_over)
      end

      it 'generates the cache values for a given user' do
        user.stub(pop_up_hours: 25, used_metered_storage: 21.hours)

        user.save

        user.used_metered_storage_cache.should eq nil
        user.pop_up_hours_cache.should eq nil

        user.update_usage_report!

        user_again = User.find(user.id)

        user_again.used_metered_storage_cache.should eq 21.hours
        user_again.pop_up_hours_cache.should eq 25
      end
    end
  end

  context 'payment' do
    let (:plan) { free_plan }

    before do
      @other = SubscriptionPlanCached.create hours: 80, amount: 2000, name: 'big'
    end

    let (:free_plan) { SubscriptionPlanCached.community }
    let (:paid_plan) { @other }

    it 'has an amount' do
      user.plan_amount.should eq 0
    end

    it 'has a #customer method that returns a Customer' do
      user.customer.should be_a Customer
    end

    it 'persists the customer' do
      user.customer.id.should eq User.find(user.id).customer.id
    end

    it 'has the community plan if it is not subscribed' do
      user.plan.should eq SubscriptionPlanCached.community
    end

    it 'returns the name of the plan' do
      user.plan_name.should eq 'Community'
    end

    it 'can have a card added' do
      user.update_card!('void_card_token')
    end

    it 'can get current card if there is one' do
      user.active_credit_card.should be_nil
      user.update_card!('void_card_token')
      user.active_credit_card.should_not be_nil
    end

    it 'can get current card json ' do
      user.update_card!('void_card_token')
      cc = {"last4"=>"4242", "type"=>"Visa", "exp_month"=>4, "exp_year"=>2016}
      user.active_credit_card_json['type'].should eq 'Visa'
      user.active_credit_card_json.keys.sort.should eq ["exp_month", "exp_year", "last4", "type"]
    end

    it 'can be subscribed to a plan' do
      user.subscribe! plan
      user.plan.should eq plan
    end

    it 'has a json representation of the current plan' do
      user.plan_json[:pop_up_hours].should eq user.pop_up_hours
      user.plan_json[:amount].should eq user.plan_amount
      user.plan_json[:id].should eq user.plan_id
    end

    it 'won\'t subscribe to a paid plan when there is no card present' do
      expect { user.subscribe!(paid_plan) }.to raise_error Stripe::InvalidRequestError
    end

    it 'subscribes to paid plans successfully when there is a card present' do
      user.update_card!('void_card_token')
      user.subscribe!(paid_plan)

      user.plan.should eq paid_plan
    end

    it 'has a number of pop up hours determined by the subscription' do
      user.subscribe!(plan)

      user.pop_up_hours.should eq plan.hours
    end

    it 'has community plan number of hours when there is no subscription' do
      user.pop_up_hours.should eq 1
    end
  end

  context '#add_default_collection' do
    it 'is a collection' do
      user = FactoryGirl.create :user
      user.collections.count.should eq 1
      c = user.send(:add_default_collection)
      c.run_callbacks(:commit)
      c.should_not be_items_visible_by_default
      c.title.should eq "#{c.creator.name}'s Collection"
      user.collections.count.should eq 2
    end
  end

  context '#uploads_collection' do
    it 'is a collection' do
      user.uploads_collection.should be_a Collection
    end

    it 'returns the same collection across multiple calls' do
      user.uploads_collection.should eq user.uploads_collection
    end

    it 'is persisted in the database' do
      user.uploads_collection.should be_persisted
    end

    it 'works when the user is not saved' do
      user = FactoryGirl.build :user
      user.uploads_collection.should eq user.uploads_collection
    end

    it 'saves with the user' do
      user = FactoryGirl.build :user
      collection = user.uploads_collection

      user.save.should be true

      user.should be_persisted
      collection.should be_persisted
      user.uploads_collection.should eq collection
      user.uploads_collection.creator.should eq user
    end

    it 'persists as the uploads collection' do
      user = FactoryGirl.build :user
      collection = user.uploads_collection

      user.save

      User.find(user.id).uploads_collection.should eq collection
    end

    it 'handles situations where uploads collection is not there for some reason' do
      user = FactoryGirl.create :user
      user.uploads_collection.destroy
      user.reload

      collection = user.uploads_collection

      user.uploads_collection.should eq collection
      User.find(user.id).uploads_collection.should eq collection
    end

    it 'is not listed as searchable' do
      user.searchable_collection_ids.should_not be_include(user.uploads_collection.id)
    end
  end

  context "in an organization" do

    it "can be added to an organization" do
      user.organization.should be_nil
      user.should_not be_in_organization
      user.organization = FactoryGirl.create :organization
      user.should be_in_organization
    end

    it "allows org admin to order transcript" do
      audio_file = AudioFile.new

      ability = Ability.new(user)
      ability.should_not be_can(:order_transcript, audio_file)

      user.organization = FactoryGirl.create :organization

      ability = Ability.new(user)
      ability.should_not be_can(:order_transcript, audio_file)

      user.add_role :admin, user.organization

      ability = Ability.new(user)
      ability.should be_can(:order_transcript, audio_file)
    end

    it 'gets upload collection from the organization' do
      user = FactoryGirl.create :organization_user
      user.organization.run_callbacks(:commit)
      user.uploads_collection.should eq user.organization.uploads_collection
    end

    it "gets list of collections from the organization" do
      user = FactoryGirl.create :organization_user
      organization = user.organization
      organization.run_callbacks(:commit)
      organization.collections.count.should eq 1
      organization.collections << FactoryGirl.create(:collection)
      organization.collections.count.should eq 2
      user.collections.should eq organization.collections
      user.collection_ids.should eq organization.collections.collect(&:id)
    end

    it "returns a role" do
      user.role.should eq :admin

      user.organization = FactoryGirl.create :organization
      user.role.should eq :member

      user.add_role :admin, user.organization
      user.role.should eq :admin
    end

  end

  context "has account" do

    it "can view collection when it is_public" do
      user = FactoryGirl.create :user
      coll = FactoryGirl.create :collection
      coll.items_visible_by_default = true
      ability = Ability.new(user)
      ability.should be_can(:read, coll)
    end

    it "can view collection when it is not public but when is owner" do
      user = FactoryGirl.create :user
      anon_user = FactoryGirl.create :user
      coll = FactoryGirl.create :collection
      coll.items_visible_by_default = false
      user.collections << coll

      # owner can read
      ability = Ability.new(user)
      ability.should be_can(:read, coll) 

      # anonymous cannot read
      anon_ability = Ability.new(anon_user)
      anon_ability.should_not be_can(:read, coll)
    end

    it "can view public item" do
      user = FactoryGirl.create :user
      coll = FactoryGirl.create :collection
      coll.items_visible_by_default = true
      item = FactoryGirl.create :item
      item.collection = coll
      ability = Ability.new(user)
      ability.should be_can(:read, item)
    end

    it "can view item in private collection when own collection" do
      user = FactoryGirl.create :user
      coll = FactoryGirl.create :collection
      coll.items_visible_by_default = false
      user.collections << coll
      item = FactoryGirl.create :item
      item.is_public = nil  # unset so assigning collection will re-set
      item.collection = coll

      # owner can read
      ability = Ability.new(user)
      ability.should be_can(:read, item)

      # anonymous cannot read
      anon_user = FactoryGirl.create :user
      anon_ability = Ability.new(anon_user)
      anon_ability.should_not be_can(:read, item)
    end

  end

end
