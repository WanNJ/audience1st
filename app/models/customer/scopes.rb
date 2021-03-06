class Customer < ActiveRecord::Base
  default_scope {  order('last_name, zip') }

  scope :subscriber_during, ->(seasons) {
    joins(:vouchertypes).where('vouchertypes.subscription = ? AND vouchertypes.season IN (?)', true, seasons)
  }

  scope :purchased_any_vouchertypes, ->(vouchertype_ids) {
    joins(:vouchertypes).where('vouchertypes.id IN (?)', vouchertype_ids).select('distinct customers.*')
  }
  
  def self.purchased_no_vouchertypes(vouchertype_ids)
    Customer.all - Customer.purchased_any_vouchertypes(vouchertype_ids)
  end

  scope :seen_any_of, ->(show_ids) {
    joins(:vouchers, :showdates).
    where('items.customer_id = customers.id AND items.showdate_id = showdates.id AND
           items.type = "Voucher" AND showdates.show_id IN (?)', show_ids).
    select('DISTINCT customers.*')
  }
  
  def self.seen_none_of(show_ids) ;  Customer.all - Customer.seen_any_of(show_ids) ;  end

  scope :with_open_subscriber_vouchers, ->(vtypes) {
    joins(:items).
    where('items.customer_id = customers.id AND items.type = "Voucher" AND
                       (items.showdate_id = 0 OR items.showdate_id IS NULL) AND
                       items.vouchertype_id IN (?)', vtypes).
    select('DISTINCT customers.*')
  }

  scope :donated_during, ->(start_date, end_date, amount) {
    joins(:items, :orders).
    where(%q{items.customer_id = customers.id AND items.amount >= ? AND items.type = "Donation"
            AND orders.sold_on BETWEEN ? AND ?},
      amount, start_date, end_date).
    select('distinct customers.*')
  }

end
