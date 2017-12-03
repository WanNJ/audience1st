require 'rails_helper'

describe VouchersController do
  describe 'confirming' do
    before :each do
      @customer = create(:customer)
      login_as @customer
      @vouchers = Array.new(3) { Voucher.new }
      @vouchers.each do |v|
        allow(v).to receive(:customer).and_return(@customer)
        allow(v).to receive(:reserve_for).and_return(true)
      end
      @showdate = create(:showdate, :thedate => 1.week.from_now)
      allow(Voucher).to receive(:find).and_return(@vouchers)
      @params = {:customer_id => @customer.id, :voucher_ids => @vouchers.map(&:id), :showdate_id => @showdate.id}
    end
    shared_examples_for 'all reservations' do
      it "redirects to welcome" do ; response.should redirect_to customer_path(@customer) ; end
    end
    describe 'successful reservations' do
      describe 'for all 3 vouchers' do
        before :each do ; @successful = 3 ; post :confirm_multiple, @params.merge(:number => 3) ; end
        it 'notifies' do ; flash[:notice].should match(/^Your reservations are confirmed./) ; end
        it_should_behave_like 'all reservations'
      end
      describe 'for 2 vouchers' do
        before :each do
          allow(@vouchers[2]).to receive(:reserve_for).and_raise("Shouldn't have tried to reserve this one")
          @successful = 2
          post :confirm_multiple, @params.merge(:number => 2)
        end
        it 'notifies' do ; flash[:notice].should match(/^Your reservations are confirmed./) ; end
        it_should_behave_like 'all reservations'
      end
    end
    describe 'reservation with errors' do
      before :each do
        allow(@vouchers[1]).to receive(:reserve_for) do |*args|
          @vouchers[1].errors.add :base,"An error occurred"
          false
        end
      end
      describe 'for 3 vouchers' do
        before :each do ; @successful = 2; post :confirm_multiple, @params.merge(:number => 3) ; end
        it 'notifies' do ; flash[:alert].should match(/could not be completed: An error occurred/) ; end
        it_should_behave_like 'all reservations'
      end
    end
  end
  describe 'update comments' do
    before :each do
      @customer = create(:customer)
      login_as @customer
      @vouchers = Array.new(3) { Voucher.new }
      allow(Voucher).to receive(:find).and_return(@vouchers)
      @params = {:id => 2,:customer_id => @customer.id, :voucher_ids => @vouchers.map(&:id)}
    end
    it 'updates the comments for all the tickets' do
      @vouchers.each do |v|
        expect(v).to receive(:update_attributes).with(:comments => "comment", :processed_by => @customer)
      end
      expect(Voucher).to receive(:find).and_return(@vouchers)
      controller.class.skip_before_filter :is_boxoffice_filter
      controller.class.skip_before_filter :owns_voucher_or_is_boxoffice
      controller.instance_variable_set(:@customer, @customer)
      allow(Txn).to receive(:add_audit_record).and_return(true)
      put :update_comment, @params.merge(:comments => "comment")

    end
  end


end
