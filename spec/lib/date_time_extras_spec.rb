require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

include Utils

def stub_month_and_day(month,day)
  stub_option!(:season_start_month, month)
  stub_option!(:season_start_day, day)
end

describe "Date/time extras" do

  describe "season calculations" do
    context "for year 1/1 - 12/31" do
      before(:each) do
        stub_month_and_day(1,1)
        @now = Time.local(2009,2,1)
      end
      it "should compute beginning of season" do
        @now.at_beginning_of_season.should == Time.local(2009,1,1)
      end
      it "should compute end of season" do
        @now.at_end_of_season.to_date.should == Date.civil(2009,12,31)
      end
      it "should include first day of season" do
        Date.civil(2009,1,1).within_season?(2009).should be_true
      end
      it "should include last day of season is part of the season" do
        Date.civil(2009,12,31).within_season?(2009).should be_true
      end
      it "should NOT include a date in next season" do
        Date.civil(2010,1,1).within_season?(2009).should be_false
      end
      it "should NOT include a date in past season" do
        Date.civil(2008,1,1).within_season?(2009).should be_false
      end
    end
    context "for season 9/1/09 - 8/31/10" do
      before(:each) do
        stub_month_and_day(9,1)
        @start = Date.civil(2009,9,1)
        @end = Date.civil(2010,8,31)
      end
      it "should be identified as the 2009 season" do
        d = @start + 1.day
        d.at_beginning_of_season.should == d.at_beginning_of_season(2009)
      end
      it "should compute beginning of season for a date in this year" do
        (@start + 1.day).at_beginning_of_season.should == @start
      end
      it "should compute beginning of season for a date in next year" do
        (@end - 1.day).at_beginning_of_season.should == @start
      end
      it "should compute end of season for a date in this year" do
        (@start + 1.day).at_end_of_season.should == @end
      end
      it "should compute end of season for a date in next year" do
        (@end - 1.day).at_end_of_season.should == @end
      end
      it "should exclude a date that is within next calendar year but not season" do
        (@end + 1.day).within_season?(2009).should be_false
      end
      it "should exclude a date that is within this calendar year but not season" do
        (@start - 1.day).within_season?(2009).should be_false
      end
      it "should include a date that is this calendar year and season" do
        (@start + 1.day).within_season?(2009).should be_true
      end
      it "should include a date that is next calendar year and in season" do
        (@end - 1.day).within_season?(2009).should be_true
      end
    end
  end
end