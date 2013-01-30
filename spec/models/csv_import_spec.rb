require 'spec_helper'

describe CsvImport do
  let(:new_import) { FactoryGirl.build :csv_import }
  let(:import) { FactoryGirl.create :csv_import }

  it "should trigger processing of itself on create" do
    new_import.should_receive(:enqueue_processing)
    new_import.save
  end

  context "state management" do
    it "should start in the new state" do
      new_import.state.should eq "new"
    end

    it "should transition to the queued state on '#enqueue_processing'" do
      new_import.send :enqueue_processing
      new_import.state.should eq "queued"
    end

    it "should transition to the analyzed state after it is analyzed" do
      import.analyze!
      import.state.should eq "analyzed"
    end

    it "should not permit analyzing unless it is saved" do
      expect(-> { new_import.analyze! }).to raise_exception
    end

    it "should not permit analyzing if it is currently analyzing" do
      import.send :state=, "analyzing"
      expect(-> { import.analyze! }).to raise_exception
    end

    it "should enter the analyzing state during analysis" do
      import.should_receive(:state=).with("analyzing").once.and_call_original
      import.should_receive(:state=).with("analyzed").once.and_call_original
      import.analyze!
    end
  end

  it "should start with no rows" do
    import.rows.should be_empty
  end

  it "should create rows records as part of analysis" do
    import.analyze!
    import.rows.should_not be_empty
  end
end
