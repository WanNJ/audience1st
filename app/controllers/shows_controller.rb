class ShowsController < ApplicationController

  # must be admin to do anything related to shows
  # FUTURE: distinguish reading from writing
  before_filter :is_boxoffice_filter # for all functions, must be at least boxoffice
  before_filter :is_boxoffice_manager_filter, :only => ['create', 'update', 'destroy']

  def index
    list
    render :action => 'list'
  end

  # GETs should be safe (see http://www.w3.org/2001/tag/doc/whenToUseGet.html)
  verify :method => :post, :only => [ :destroy, :create, :update ],
         :redirect_to => { :action => :list }

  def list
    @superadmin = Customer.find(logged_in_id).is_admin rescue false
    @show_pages, @shows = paginate :shows, :per_page => 20, :order => 'opening_date'
  end

  def new
    @show = Show.new
  end

  def create
    @show = Show.new(params[:show])
    if @show.save
      flash[:notice] = 'Show was successfully created.'
      redirect_to :action => 'list'
    else
      render :action => 'new'
    end
  end

  def edit
    @show = Show.find(params[:id])
    @showdates = @show.showdates.sort_by { |s| s.thedate }
    @is_boxoffice_manager = is_boxoffice_manager
  end

  def update
    @show = Show.find(params[:id])
    if @show.update_attributes(params[:show])
      flash[:notice] = 'Show details successfully updated.'
      redirect_to :action => 'edit', :id => @show
    else
      render :action => 'edit', :id => @show
    end
  end

  def destroy
    Show.find(params[:id]).destroy
    redirect_to :action => 'list'
  end
end