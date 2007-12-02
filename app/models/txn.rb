class Txn < ActiveRecord::Base
  belongs_to :txn_type
  belongs_to :purchasemethod
  belongs_to :show
  belongs_to :showdate
  belongs_to :customer

  validates_associated :txn_type, :purchasemethod

  # since the audit record schema is generic, not all fields are
  # relevant for every entry. There is a generic (private) add_audit_record
  # function that expects values for all fields, and specialized
  # (public)functions for each type of record that are actually called
  # from the relevant controllers when changes are committed.

  # in all cases, the id of the person making the change and the id of
  # the affected customer are recorded.  if the customer is logged in to
  # their online account, these id's will be the same.

  # TBD: can probably redo using keyword args to add_audit_record
  # (filling in defaults for omitted args) and eliminating the
  # specialized calls.

  def self.add_audit_record(args={})

    if args.has_key?(:txn_type)
      type_id = TxnType.get_type_by_name(args[:txn_type])
    else
      type_id = TxnType.get_type_by_name('???')
      # TBD: log that txn type wasn't specified
    end

    cust_id = args[:customer_id] || Customer.nobody_id
    logged_in = args[:logged_in_id].to_i
    show_id =  args[:show_id].to_i
    showdate_id = args[:showdate_id].to_i
    voucher_id =  args[:voucher_id].to_i
    amt = args[:dollar_amount].to_f
    comments =  args[:comments] ||  ''
    purch_id = args[:purchasemethod_id] || Purchasemethod.get_type_by_name('none')

    a = Txn.create( [:customer_id => cust_id,
                     :entered_by_id => logged_in,
                     :txn_date => Time.now,
                     :txn_type_id => type_id,
                     :show_id => show_id,
                     :showdate_id => showdate_id,
                     :purchasemethod_id => purch_id,
                     :voucher_id => voucher_id,
                     :dollar_amount => amt,
                     :comments => comments ] )
    
  end


end

class TxnType < ActiveRecord::Base
  has_many :txns

  def self.get_type_by_name(str)
    (TxnType.find_by_shortdesc(str) || TxnType.find(:first)).id rescue 0
  end

end
