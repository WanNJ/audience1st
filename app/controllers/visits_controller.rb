class VisitsController < ApplicationController

  before_filter :is_staff_filter

  def list
    @customer,@is_admin = for_customer(params[:id])
    unless @customer.kind_of?(Customer)
      redirect_to :controller => 'customers', :action => 'list'
      return
    end
    @logged_in_id = logged_in_id
    @visit ||= Visit.new(:visited_by_id => @logged_in_id, :followup_assigned_to_id => @logged_in_id, :thedate => Date.today) 
    @previous_visits = @customer.visits.sort_by { |v| (Date.today - v.thedate) }
    @previous_visits = nil if @previous_visits.empty?
  end

  # this should really be implemented by having a Prospector be a
  # subclass of Customer and using belongs_to.
  def list_by_prospector
    @customer,@is_admin = for_customer(params[:id])
    unless @customer.kind_of?(Customer)
      redirect_to :controller => 'customers', :action => 'list'
      return
    end
    @prospects = Customer.find_by_sql("SELECT DISTINCT c.* FROM customers c, visits v WHERE v.customer_id = c.id AND v.visited_by_id = #{@customer.id}")
  end

  def create
    @visit = Visit.new(params[:visit])
    @customer = Customer.find_by_id(@visit.customer_id)
    unless @customer.kind_of?(Customer)
      flash[:notice] = "You must go to a customer's account page before adding a visit"
      redirect_to :action => 'list'
      return
    end
    @customer.visits << @visit
    if @customer.save
      flash[:notice] = "Visit information saved"
    end
    redirect_to :action => 'list', :id => @customer
  end

  def update
    begin
      @visit = Visit.find(params[:id])
      if @visit.update_attributes(params[:visit])
        flash[:notice] = "Visit information updated successfully."
      else
        flash[:notice] = "Errors updating visit information"
      end
    rescue
      flash[:notice] = "Errors updating the visit information; see below."
    end
    redirect_to :action => 'list', :id => @visit.customer
  end

end