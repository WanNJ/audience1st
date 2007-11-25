class StoreController < ApplicationController
  include ActiveMerchant::Billing
  include Enumerable
  
  require "money.rb"
  
  before_filter :walkup_sales_filter, :only => %w[walkup do_walkup_sale]
  
  if RAILS_ENV == 'production'
    ssl_required :checkout, :place_order, :walkup, :do_walkup_sale
    ssl_allowed(:index, :reset_ticket_menus,
                :show_changed, :showdate_changed, :enter_promo_code,
                :add_tickets_to_cart, :add_donation_to_cart, :remove_from_cart,
                :empty_cart, :process_swipe)
  end
  
  verify(:method => :post,
         :only => %w[do_walkup_sale add_tickets_to_cart add_donation_to_cart
                        add_subscriptions_to_cart place_order],
         :add_flash => {:notice => "SYSTEM ERROR: action only callable as POST"},
         :redirect_to => {:action => 'index'})

  def index
    @customer,@is_admin = for_customer(params[:id])
    session[:store_customer] = @customer.id
    @subscriber = @customer && @customer.is_subscriber?
    @promo_code = session[:promo_code] || nil
    @cart = find_cart
    #
    # determine showdates first; then determine showdates for which this
    # customer is allowed to purchase vouchers; then determine show
    # names from that.
    #
    @shows = get_all_shows(get_all_showdates(@is_admin))
    @showdates = nil
    @vouchertypes = nil
  end

  def reset_ticket_menus
    @customer,@is_admin = for_customer(params[:id])
    @customer = Customer.find(session[:store_customer]) if session[:store_customer]
    @subscriber = @customer && @customer.is_subscriber?
    showdates = vouchertypes = show_id = showdate_id = nil
    shows  = get_all_shows(get_all_showdates(@is_admin))
    unless shows.empty?
      s = shows.first
      showdates = get_showdates(s.id, @is_admin)
    end
    render(:partial => 'ticket_menus',
           :locals => {
             :shows => shows, :show_id => show_id,
             :showdates => showdates, :showdate_id => showdate_id,
             :subscriber => @subscriber,
             :vouchertypes => vouchertypes})
  end

  def show_changed
    @customer,@is_admin = for_customer(params[:id])
    @customer = Customer.find(session[:store_customer]) if session[:store_customer]
    @subscriber = @customer && @customer.is_subscriber?
    #@is_admin = Customer.find(logged_in_id).is_boxoffice
    show_id = params[:show_id].to_i
    @shows = get_all_shows(get_all_showdates(@is_admin))
    if show_id > 0
      @showdates = get_showdates(show_id, @is_admin)
    else
      @showdates = nil
      show_id = nil
    end
    render(:partial => 'ticket_menus',
           :locals => {
             :shows => @shows, :show_id => show_id,
             :showdates => @showdates, :showdate_id => nil,
             :subscriber => @subscriber,
             :vouchertypes => nil
           } )
  end

  def showdate_changed
    @customer,@is_admin = for_customer(params[:id])
    @customer = Customer.find(session[:store_customer]) if session[:store_customer]
    @subscriber = @customer && @customer.is_subscriber?
    showdate_id = params[:showdate_id].to_i
    if showdate_id > 0
      @vouchertypes = ValidVoucher.numseats_for_showdate(showdate_id, @customer,
                                                         :ignore_cutoff => @is_admin)
      show_id = Showdate.find(showdate_id).show_id
      # if not staff, strip out stuff they shouldn't see
      @vouchertypes.reject! { |av| av.staff_only } unless @is_admin
      # if vouchertypes with promo code, only show if promo code supplied
      @vouchertypes.reject! do |av|
        (codes = av.promo_codes) &&
          !(codes.include?(session[:promo_code].to_s))
      end
    else
      @vouchertypes = nil
      show_id = 0
    end
    render(:partial => 'ticket_menus',
           :locals => {
             :shows => get_all_shows(get_all_showdates(@is_admin)),
             :show_id => show_id,
             :showdates => get_showdates(show_id, @is_admin),
             :showdate_id => showdate_id,
             :subscriber => @subscriber,
             :vouchertypes => @vouchertypes
           } )
  end

  # TBD: pull out above logic into a controller helper that, given a
  # showdate and purchaser (customer), returns a list of valid voucher
  # types and the corresponding show ID (or nils if needed).
  
  def enter_promo_code
    code = (params[:promo_code] || '').upcase
    if !code.empty?
      session[:promo_code] = code
    end
    redirect_to :action => 'index', :id => params[:id]
    #render( :partial => 'promo_entry', :locals => {:promo_code => code})
  end

  def subscribe_2008
    @customer,@is_admin = for_customer(params[:id])
    session[:store_customer] = @customer.id
    @subscriber = @customer && @customer.is_subscriber?
    @cart = find_cart
    @renew_discount_date = Date.new(2007, 9, 30)
    subs = {
      :type => :subscription,
      :since => Date.new(2007,9,11)
    }
    subs.merge!({:for_purchase_by => :subscribers}) if @subscriber
    @subs_to_offer = Vouchertype.find_products(subs).sort_by { |v| v.price }.reverse
  end

  # RSS feed of ticket availability info
  def ticket_rss
    @venue = APP_CONFIG[:venue]
    # what are the next N shows?
    now = Time.now
    end_date = now.next_year.at_beginning_of_year
    showdates =
      Showdate.find(:all,
                    :conditions => ["thedate > ? AND thedate < ?", now, end_date],
                    :order => "thedate")
    @showdate_avail = []
    unless showdates.nil? || showdates.empty?
      showdates.each do |sd|
        case sd.availability_in_words
        when :sold_out
          desc,link = "SOLD OUT", false
        when :nearly_sold_out
          desc,link = "Nearly sold out", true
        else
          desc,link = "Available", true
        end
        if link
          desc << " - " << (sd.advance_sales? ? "Buy online now" :
                            "Advance sales ended (Tickets may be available at box office)")
        end
        @showdate_avail << [sd, desc, link]
      end
    end
    render :layout => false
  end

  def ticket_vxml
    @venue = APP_CONFIG[:venue]
    @xferphone = APP_CONFIG[:venue_telephone]
    # just check shows thru "this weekend"
    end_date = (Time.now + 1.day + 1.week).at_beginning_of_week
    showdates = Showdate.find(:all, :conditions =>
                              ["thedate BETWEEN ? and ?", Time.now, end_date],
                              :order => "thedate" )
    if (showdates.nil? || showdates.empty?)
      @next_perf = Showdate.find(:first, :order => 'thedate',
                                 :conditions => ["thedate >?",Time.now])
      render :template => "ticket_noperfs_vxml", :layout => false
    else
      @showdates_info = showdates.map do |s|
        [s.speak, s.availability_in_words, s.advance_sales? ]
      end
      render :layout => false
    end
  end
  
  def add_subscriptions_to_cart
    @cart = find_cart
    qty = params[:subscription_qty].to_i
    vtype = params[:subscription_vouchertype_id].to_i
    if qty < 1
      flash[:notice] = "Quantity must be 1 or more."
    else
      unless (((v = Vouchertype.find(vtype)).is_subscription? && v.is_bundle?) rescue nil)
        flash[:notice] = "Invalid subscription type."
      else
        1.upto(qty) do
          @cart.add(Voucher.anonymous_bundle_for(vtype))
        end
      end
    end
    redirect_to :action => 'subscribe_2008', :id => params[:id]
  end
      
  def add_tickets_to_cart
    @cart = find_cart
    @customer,@is_admin = for_customer(params[:id])
    qty = params[:qty].to_i
    vtype = params[:vouchertype_id].to_i
    showdate_id = params[:showdate_id].to_i

    if  vtype.to_i.zero?
      flash[:ticket_error] = 'Please select show, date, and type of ticket first.'
    elsif ! Vouchertype.find_by_id(vtype)
      flash[:ticket_error] = "Sorry, you're not authorized to purchase that ticket type."
    elsif qty < 1 || qty > 99
      flash[:ticket_error] = 'Must order between 1 and 99 tickets.'
    else
      av = ValidVoucher.numseats_for_showdate_by_vouchertype(showdate_id,@customer,vtype,:ignore_cutoff => @is_admin)
      if av.howmany.zero?
        flash[:ticket_error] = 'Ticket type invalid for that show date, or show sold out'
      elsif av.howmany < qty
        flash[:ticket_error] = "Only #{av.howmany} of these tickets remaining for this show"
      else      # add vouchers to cart.  Vouchers will be validated at checkout.
        # was a promo code necessary to select this vouchertype?
        promo_code = ((session[:promo_code] && av.promo_codes) ?
                      session[:promo_code].upcase : nil)
        1.upto(qty) do
          @cart.add(Voucher.anonymous_voucher_for(showdate_id, vtype, promo_code, params[:comments]))
        end
      end
    end
    redirect_to :action => 'index', :id => params[:id]
  end

  def add_donation_to_cart
    @cart = find_cart
    params[:donation] = {
      :amount => amount_from_selects(params[:d]),
      :donation_fund_id => DonationFund.default_fund_id
    }
    if params[:donation][:amount] > 0
      params[:donation].merge!({ :date => Time.now, :donation_type_id => 1 })
      d = Donation.new(params[:donation])
      @cart.add(d)
    end
    redirect_to :action =>(params[:redirect_to] || 'index'), :id => params[:id]
  end

  def checkout
    @cust,@is_admin = for_customer(params[:id])
    @cart = find_cart
    @sales_final_acknowledged = (params[:sales_final].to_i > 0)
    if @cart.is_empty?
      flash[:notice] = "There is nothing in your cart."
      redirect_to :action => 'index', :id => params[:id]
      return
    end
    # if this is a "walkup web" sale (not logged in), nil out the
    # customer to avoid modifing the Walkup customer.
    if @cust.is_walkup_customer?
      @cust = Customer.new
      session[:checkout_in_progress] = true
      flash[:notice] = "Please sign in, or create an account if you don't already have one, so we can help you track your reservations and take advantage of ticket discounts.  We never share this information with anyone."
      redirect_to :controller => 'customers', :action => 'login'
      return
    end
    # else fall thru to checkout screen
    session[:checkout_in_progress] = false
  end

  def not_me
    @cust = Customer.new
    session[:checkout_in_progress] = true
    flash[:notice] = "Please sign in, or create an account if you don't already have one, so we can help you track your reservations and take advantage of ticket discounts.  We never share this information with anyone."
    redirect_to :controller => 'customers', :action => 'login'
  end
  
  def place_order
    @cart = find_cart
    id = params[:id]
    sales_final = params[:sales_final]
    @bill_to = params[:customer]
    cc_info = params[:credit_card].symbolize_keys
    cc_info[:first_name] = @bill_to[:first_name]
    cc_info[:last_name] = @bill_to[:last_name]
    # BUG: workaround bug in xmlbase.rb where to_int (nonexistent) is
    # called rather than to_i to convert month and year to ints.
    cc_info[:month] = cc_info[:month].to_i
    cc_info[:year] = cc_info[:year].to_i
    cc = CreditCard.new(cc_info)
    # prevalidations: CC# and address appear valid, amount >0,
    # billing address appears to be a well-formed address
    unless (errors = do_prevalidations(params, @cart, @bill_to, cc)).empty?
      flash[:notice] = errors
      redirect_to :action => 'checkout', :id => id, :sales_final => sales_final
      return
    end
    #
    # basic prevalidations OK, continue with customer validation
    #
    @customer, @is_admin = (params[:id] ?
                            for_customer(params[:id]) :
                            [Customer.new_or_find(params[:customer]), nil])
    unless @customer.kind_of?(Customer)
      flash[:notice] = @customer
      redirect_to :action => 'checkout', :id => id, :sales_final => sales_final
      return
    end
    # OK, we have a customer record to tie the transaction to
    resp = do_cc_not_present_transaction(@cart.total_price, cc, @bill_to)
    if !resp.success?
      flash[:notice] = "PAYMENT GATEWAY ERROR: " << resp.message
      flash[:notice] << "<br/>Please contact your credit card
        issuer for assistance."  if resp.message.match(/decline/i)
      logger.info("Cust id #{@customer.id} [#{@customer.full_name}] card xxxx..#{cc.number[-4..-1]}: #{resp.message}") rescue nil
      redirect_to :action => 'checkout', :id => @customer.id, :sales_final => sales_final
      return
    end
    #     All is well, fall through to confirmation
    #
    @tid = resp.params['transaction_id'] || '0'
    @customer.add_items(@cart.items, logged_in_id,
                        (logged_in_id == @customer.id ? 'cust_web' : 'cust_ph'),
                        @tid)
    @customer.save
    @amount = @cart.total_price
    @order_summary = @cart.to_s
    @cc_number = cc.number
    email_confirmation(:confirm_order, @customer,@order_summary,
                       @amount, "Credit card ending in #{@cc_number[-4..-1]}")
    @cart.empty!
    session[:promo_code] =  nil
    session[:store_customer] = nil
  end

  def show_cart
    cart = find_cart
    breakpoint
    render :text => "<pre> #{cart.to_s} </pre>"
  end

  def remove_from_cart
    @cart = find_cart
    @cart.remove_index(params[:item])
    redirect_to :action => (params[:redirect_to] || 'index'), :id => params[:id]
  end

  def empty_cart
    session[:cart] = Cart.new
    session[:promo_code] = nil
    redirect_to :action => (params[:redirect_to] || 'index'), :id => params[:id]
  end

  def walkup
    # walkup sales are restricted to either boxoffice staff or
    # specific IP's
    @ip = request.remote_ip
    # generate one-time pad for encrypting CC#s
    session[:otp] = @otp = String.random_string(256)
    now = Time.now - 1.hour
    @showdates = Showdate.find(:all,:conditions => ["thedate >= ?", now-1.week])
    @shows = get_all_shows(@showdates).map  { |s| [s,@showdates.select { |sd| sd.show_id == s.id } ]}
    @vouchertypes = Vouchertype.find(:all, :conditions => ["is_bundle = ? AND walkup_sale_allowed = ?", false, true])
    # if there was a show and showdate selected before redirect to this screen,
    # keep it selected
    if (params[:show])
      @show_id = params[:show].to_i
      @showdate_id = params[:showdate] ? params[:showdate].to_i : nil
    elsif (future_shows = @showdates.select { |x| x.thedate >= now })
      next_show = future_shows.min
      @showdate_id = next_show.id
      @show_id = next_show.show.id
    else
      @show_id = @showdate_id = nil # defaults
    end
  end

  def do_walkup_sale
    if params[:commit].match(/report/i) # generate report
      redirect_to(:controller => 'report', :action => 'walkup_sales',
                  :showdate_id => params[:showdate_select])
      return
    end
    qtys = params[:qty]
    showdate = params[:showdate_select]
    # CAUTION: disable_with on a Submit button makes its name (params[:commit])
    # empty on submit!
    is_cc_purch = !(params[:commit] && params[:commit] != APP_CONFIG[:cc_purch])
    vouchers = []
    # recompute the price
    total = 0.0
    ntix = 0
    begin
      qtys.each_pair do |vtype,q|
        ntix += (nq = q.to_i)
        total += nq * Vouchertype.find(vtype).price
        nq.times  { vouchers << Voucher.anonymous_voucher_for(showdate, vtype) }
      end
      total += (donation=params[:donation].to_f)
    rescue Exception => e
      flash[:notice] = "There was a problem verifying the total amount of the order:<br/>#{e.message}"
      redirect_to(:action => :walkup, :showdate => showdate,
                  :show => params[:show_select])
      return
    end
    # link record as a walkup customer
    # TBD: if can match name from CC, try to link to customer record
    customer = Customer.walkup_customer
    if is_cc_purch
      if false
        cc = CreditCard.new(params[:credit_card])
        # BUG: workaround bug in xmlbase.rb where to_int (nonexistent) is
        # called rather than to_i to convert month and year to ints.
        cc.month = cc.month.to_i
        cc.year = cc.year.to_i
        # run cc transaction....
        resp = do_cc_present_transaction(total,cc)
        unless resp.success?
          flash[:notice] = "PAYMENT GATEWAY ERROR: " + resp.message
          redirect_to :action => 'walkup', :showdate => showdate,
          :show => params[:show_select]
          return
        end
        tid = resp.params['transaction_id']
        flash[:notice] = "Transaction approved (#{tid})<br/>"
      end
      tid = 0
      howpurchased = Purchasemethod.get_type_by_name('walk_cc')
      flash[:notice] = "Credit card purchase recorded, "
    else
      tid = 0
      howpurchased = Purchasemethod.get_type_by_name('walk_cash')
      flash[:notice] = "Cash purchase recorded, "
    end
    # add tickets to "walkup customer"'s account
    unless (vouchers.empty?)
      vouchers.each do |v|
        if v.kind_of?(Voucher)
          v.purchasemethod_id = howpurchased
        end
      end
      customer.add_items(vouchers, logged_in_id, howpurchased, tid)
      customer.save!              # actually, probably unnecessary
      flash[:notice] << sprintf("%d tickets sold,", ntix)
      Txn.add_audit_record(:txn_type => 'tkt_purch',
                           :customer_id => customer.id,
                           :comments => 'walkup',
                           :purchasemethod_id => howpurchased,
                           :logged_in_id => logged_in_id)
    end
    if donation > 0.0
      flash[:notice] << sprintf(" $%.02f donation processed,", donation)
      # add donation for customer...
    end
    flash[:notice] << sprintf(" total $%.02f",  total)
    flash[:notice] << sprintf("<br/>%d seats remaining for this performance",
                              Showdate.find(showdate).total_seats_left)
    redirect_to(:action => 'walkup', :showdate => showdate,
                :show => params[:show_select])
  end

  def process_swipe
    swipe_data = String.new(params[:swipe_data])
    key = session[:otp].to_s
    no_encrypt = (swipe_data[0] == 37)
    if swipe_data && !(swipe_data.empty?)
      swipe_data = encrypt_with(swipe_data, key) unless no_encrypt
      @credit_card = convert_swipe_to_cc_info(swipe_data.chomp)
      @credit_card.number = encrypt_with(@credit_card.number, key) unless no_encrypt
      render :partial => 'credit_card', :locals => {'name_needed'=>true}
    end
  end

  def dummy
    @amount= 50.00
    @cc_number='xxxxxxxxx'
    render :action => 'place_order'
  end

  def encrypt_with(orig,pad)
    str = String.new(orig)
    for i in (0..str.length-1) do
      str[i] ^= pad[i]
    end
    str
  end

  def convert_swipe_to_cc_info(s)
    # trk1: '%B' accnum '^' last '/' first '^' YYMM svccode(3 chr)
    #   discretionary data (up to 8 chr)  '?'
    # '%B' is a format code for the standard credit card "open" format; format
    # code '%A' would indicate a proprietary encoding
    trk1 = Regexp.new('^%B(\d{1,19})\\^([^/]+)/?([^/]+)?\\^(\d\d)(\d\d)[^?]+\\?', :ignore_case => true)
    # trk2: ';' accnum '=' YY MM svccode(3 chr) discretionary(up to 8 chr) '?'
    trk2 = Regexp.new(';(\d{1,19})=(\d\d)(\d\d).{3,12}\?', :ignore_case => true)

    # if card has a track 1, we use that (even if trk 2 also present)
    # else if only has a track 2, try to use that, but doesn't include name
    # else error.
    
    if s.match(trk1)
      accnum = Regexp.last_match(1).to_s
      lastname = Regexp.last_match(2).to_s.upcase
      firstname = Regexp.last_match(3).to_s.upcase # may be nil if this field was absent
      expyear = 2000 + Regexp.last_match(4).to_i
      expmonth = Regexp.last_match(5).to_i
    elsif s.match(trk2)
      accnum = Regexp.last_match(1).to_s
      expyear = 2000 + Regexp.last_match(2).to_i
      expmonth = Regexp.last_match(3).to_i
      lastname = firstname = ''
    else
      accnum = lastname = firstname = 'ERROR'
      expyear = expmonth = 0
    end
    CreditCard.new(:first_name => firstname.strip,
                   :last_name => lastname.strip,
                   :month => expmonth.to_i,
                   :year => expyear.to_i,
                   :number => accnum.strip,
                   :type => CreditCard.type?(accnum.strip) || '')
  end
  
  def populate_cc_object(params)
    cc_info = params[:credit_card].symbolize_keys || {}
    cc_info[:first_name] = @bill_to[:first_name]
    cc_info[:last_name] = @bill_to[:last_name]
    # BUG: workaround bug in xmlbase.rb where to_int (nonexistent) is
    # called rather than to_i to convert month and year to ints.
    cc_info[:month] = cc_info[:month].to_i
    cc_info[:year] = cc_info[:year].to_i
    CreditCard.new(cc_info)
  end

  def do_prevalidations(params,cart,billing_info,cc)
    err = ''
    if cart.total_price <= 0
      #
      #  BEGIN CHECKS:
      #  total amount to be charged >= 0
      #
      err = "Total amount of sale must be greater than zero."
    elsif params[:sales_final].to_i.zero?
      #
      #  customer must accept Sales Final policy
      #
      err = "Please indicate your acceptance of our Sales Final policy "
      err << "by checking the box."
    elsif ! cc.valid?
      #
      #  CC# appears to be well formed
      #
      err = "Please provide valid credit card information:<br/>" + 
        cc.errors.full_messages.join("<br/>")
    elsif !prevalidate_billing_addr(billing_info)
      #
      #  Billing address appears to be a valid address
      #
      err = 'Please provide a valid billing name and address.'
    end
    return err
  end
  
  def prevalidate_credit_card(ccinfo)
  end

  def prevalidate_billing_addr(billinfo)
    true
  end

  def do_cc_present_transaction(amount, cc)
    params = {
      :order_id => '999',
      :address => {
        :name => "#{cc.first_name} #{cc.last_name}"
      }
    }
    return cc_transaction(amount,cc,params,card_present=true)
  end

  def do_cc_not_present_transaction(amount, cc, bill_to)
    email = bill_to[:login].to_s.default_to("invalid@audience1st.com")
    phone = bill_to[:day_phone].to_s.default_to("555-555-5555")
    params = {
      :order_id => '999',
      :email => email,
      :address =>  { 
        :name => "#{bill_to[:first_name]} #{bill_to[:last_name]}",
        :address1 => bill_to[:street],
        :city => bill_to[:city],
        :state => bill_to[:state],
        :zip => bill_to[:zip],
        :phone => phone,
        :country => 'US'
      }
    }
    return cc_transaction(amount,cc,params,card_present=false)
  end

  def cc_transaction(amount,cc,params,card_present)
    amount = Money.us_dollar((100 * amount).to_i)
    gw = get_payment_gateway_info(card_present)
    Base.gateway_mode = :test if gw[:testing]
    gateway = gw[:gateway].new(:login => gw[:username],
                               :password => gw[:password],
                               :pem => gw[:pem])
    response = gateway.purchase(amount, cc, params)
  end
                                
  def get_all_shows(showdates)
    return showdates.map { |s| s.show }.uniq.sort_by { |s| s.opening_date }
  end

  def get_all_showdates(ignore_cutoff=false)
    get_showdates(0, ignore_cutoff)
  end

  def get_showdates(show_id,ignore_cutoff=false)
    if show_id.zero?
      showdates = Showdate.find(:all)
    else
      showdates = Show.find(show_id).showdates rescue []
    end
    unless ignore_cutoff
      now = Time.now
      showdates.reject! { |sd| sd.end_advance_sales < now || sd.thedate < now }
    end
    showdates.sort_by { |s| s.thedate }
  end
  
  def get_all_subs(cust = Customer.generic_customer)
    return Vouchertype.find(:all, :conditions => ["is_bundle = 1 AND offer_public > ?", (cust.kind_of?(Customer) && cust.is_subscriber? ? 0 : 1)])
  end
  
  # helper: given array of showdates, produce an array each of whose
  # elements is an array [show, [showdate1,...,showdateN]]

  def parent_child_array(children,parent_method)
    return nil if (children.nil? || children.empty?)
    parents = children.map { |s| s.send(parent_method) }.uniq
    parents.map { |s| [s,children.select { |x| x.send("#{parent_method}_id") == s.id } ] }
  end
  
  # filter for walkup sales: requires specific privilege OR allows
  # anyone from selected IP addresses

  def walkup_sales_filter
    unless is_walkup or APP_CONFIG[:walkup_locations].include?(request.remote_ip)
      flash[:notice] = 'To process walkup sales, you must either sign in with
        Walkup Sales privilege OR from an approved walkup sales computer.'
      session[:return_to] = request.request_uri
      redirect_to :controller => 'customers', :action => 'login'
    end
  end

end
